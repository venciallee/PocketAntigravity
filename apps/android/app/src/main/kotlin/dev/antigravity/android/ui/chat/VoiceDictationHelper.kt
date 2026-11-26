package dev.antigravity.android.ui.chat

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import java.util.Locale

/**
 * Pure helper matching iOS `VoiceInputManager.mergeTranscript(prefix:transcript:)`:
 * appends dictated speech onto existing typed draft text without wiping prior input.
 */
internal fun mergeDictatedTranscript(prefix: String, transcript: String): String {
    val trimmedTranscript = transcript.trim()
    if (trimmedTranscript.isEmpty()) return prefix
    if (prefix.isBlank()) return trimmedTranscript
    val lastChar = prefix.last()
    return if (lastChar.isWhitespace()) {
        prefix + trimmedTranscript
    } else {
        "$prefix $trimmedTranscript"
    }
}

/**
 * Crash-safe native Android speech-to-text controller backed by [SpeechRecognizer].
 *
 * Guards every platform pitfall:
 * - Runtime `RECORD_AUDIO` permission request before touching [SpeechRecognizer]
 * - [SpeechRecognizer.isRecognitionAvailable] check (with `<queries>` in `AndroidManifest.xml`)
 * - Main-thread confinement + `runCatching` around OEM `SpeechRecognizer` IPC calls
 * - Monotonic session generation token to ignore stale callbacks after stop/restart
 * - Deterministic `cancel()` + `destroy()` cleanup in `DisposableEffect`
 */
@Stable
class VoiceDictationController(
    context: Context,
) {
    private val appContext: Context = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    var isRecording: Boolean by mutableStateOf(false)
        private set
    var isStarting: Boolean by mutableStateOf(false)
        private set
    var errorMessage: String? by mutableStateOf(null)
        private set

    private var speechRecognizer: SpeechRecognizer? = null
    private var sessionGeneration: Long = 0L
    private var lastTranscript: String = ""
    private var pendingPrefix: String = ""
    private var pendingOnDraftUpdated: ((String) -> Unit)? = null
    internal var requestAudioPermissionLauncher: (() -> Unit)? = null

    fun clearError() {
        errorMessage = null
    }

    fun toggleRecording(
        existingDraft: String,
        onDraftUpdated: (String) -> Unit,
    ) {
        if (isRecording || isStarting) {
            stopRecording()
            return
        }
        errorMessage = null
        lastTranscript = ""
        pendingPrefix = existingDraft
        pendingOnDraftUpdated = onDraftUpdated

        val granted = ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED

        if (granted) {
            startRecognizerOnMainThread()
        } else {
            val launcher = requestAudioPermissionLauncher
            if (launcher == null) {
                errorMessage = "Enable Microphone permission in Settings to dictate prompts."
                return
            }
            isStarting = true
            runCatching { launcher() }.onFailure {
                isStarting = false
                errorMessage = "Unable to request Microphone permission on this device."
            }
        }
    }

    internal fun onPermissionResult(granted: Boolean) {
        if (!isStarting) return
        if (!granted) {
            isStarting = false
            pendingOnDraftUpdated = null
            errorMessage = "Enable Microphone permission in Settings to dictate prompts."
            return
        }
        startRecognizerOnMainThread()
    }

    fun stopRecording() {
        sessionGeneration += 1L
        isStarting = false
        isRecording = false
        pendingOnDraftUpdated = null
        runOnMainThread {
            tearDownRecognizerLocked()
        }
    }

    fun release() {
        stopRecording()
    }

    private fun startRecognizerOnMainThread() {
        val generation = ++sessionGeneration
        isStarting = true
        runOnMainThread {
            if (generation != sessionGeneration) return@runOnMainThread

            val available = runCatching {
                SpeechRecognizer.isRecognitionAvailable(appContext)
            }.getOrDefault(false)
            if (!available) {
                isStarting = false
                isRecording = false
                errorMessage = "Speech recognition service is unavailable on this device."
                return@runOnMainThread
            }

            tearDownRecognizerLocked()

            val recognizer = runCatching {
                SpeechRecognizer.createSpeechRecognizer(appContext)
            }.getOrNull()
            if (recognizer == null) {
                isStarting = false
                isRecording = false
                errorMessage = "Unable to initialize Speech Recognizer on this device."
                return@runOnMainThread
            }

            speechRecognizer = recognizer
            val prefix = pendingPrefix
            val onUpdate = pendingOnDraftUpdated

            recognizer.setRecognitionListener(
                object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        if (generation != sessionGeneration) return
                        isStarting = false
                        isRecording = true
                    }

                    override fun onBeginningOfSpeech() = Unit
                    override fun onRmsChanged(rmsdB: Float) = Unit
                    override fun onBufferReceived(buffer: ByteArray?) = Unit

                    override fun onEndOfSpeech() {
                        if (generation != sessionGeneration) return
                        isStarting = false
                    }

                    override fun onError(error: Int) {
                        if (generation != sessionGeneration) return
                        val hadTranscript = lastTranscript.isNotBlank()
                        stopRecording()
                        if (!hadTranscript && !isBenignSpeechError(error)) {
                            errorMessage = humanReadableSpeechError(error)
                        }
                    }

                    override fun onResults(results: Bundle?) {
                        if (generation != sessionGeneration) return
                        val text = extractBestTranscript(results)
                        if (!text.isNullOrBlank()) {
                            lastTranscript = text
                            onUpdate?.invoke(mergeDictatedTranscript(prefix, text))
                        }
                        stopRecording()
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        if (generation != sessionGeneration) return
                        val text = extractBestTranscript(partialResults)
                        if (!text.isNullOrBlank()) {
                            lastTranscript = text
                            onUpdate?.invoke(mergeDictatedTranscript(prefix, text))
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) = Unit
                },
            )

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
            }

            val started = runCatching {
                recognizer.startListening(intent)
                true
            }.getOrElse { err ->
                errorMessage = "Unable to start voice dictation: ${err.localizedMessage ?: "audio error"}"
                tearDownRecognizerLocked()
                false
            }

            if (started) {
                isStarting = false
                isRecording = true
            } else {
                isStarting = false
                isRecording = false
            }
        }
    }

    private fun tearDownRecognizerLocked() {
        val current = speechRecognizer ?: return
        speechRecognizer = null
        runCatching { current.cancel() }
        runCatching { current.destroy() }
    }

    private fun runOnMainThread(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    companion object {
        internal fun extractBestTranscript(bundle: Bundle?): String? {
            val matches = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            return matches?.firstOrNull { it.isNotBlank() }?.trim()
        }

        internal fun isBenignSpeechError(code: Int): Boolean =
            code == SpeechRecognizer.ERROR_CLIENT ||
                code == SpeechRecognizer.ERROR_NO_MATCH ||
                code == SpeechRecognizer.ERROR_SPEECH_TIMEOUT

        internal fun humanReadableSpeechError(code: Int): String = when (code) {
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                "Enable Microphone permission in Settings to dictate prompts."
            SpeechRecognizer.ERROR_AUDIO ->
                "Microphone audio input is temporarily unavailable."
            SpeechRecognizer.ERROR_NETWORK,
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
            -> "Voice recognition requires a network connection or offline speech pack."
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                "Speech recognizer is busy. Please try again."
            else -> "Voice dictation stopped. Please try again."
        }
    }
}

@Composable
fun rememberVoiceDictationController(): VoiceDictationController {
    val context = LocalContext.current
    val controller = remember(context.applicationContext) {
        VoiceDictationController(context.applicationContext)
    }

    val registryOwner = LocalActivityResultRegistryOwner.current
    if (registryOwner != null) {
        val permissionLauncher = rememberLauncherForActivityResult(
            contract = ActivityResultContracts.RequestPermission(),
        ) { granted ->
            controller.onPermissionResult(granted)
        }
        controller.requestAudioPermissionLauncher = {
            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    } else {
        controller.requestAudioPermissionLauncher = null
    }

    DisposableEffect(controller) {
        onDispose {
            controller.release()
        }
    }

    return controller
}
