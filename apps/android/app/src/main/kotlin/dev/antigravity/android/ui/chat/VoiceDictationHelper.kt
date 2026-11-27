package dev.antigravity.android.ui.chat

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Resources
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Language
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.shared.model.AppLanguage
import dev.antigravity.shared.model.VoiceDictationLanguage
import dev.antigravity.shared.model.VoiceLocaleResolver
import java.util.Locale

private const val VOICE_PREFS_NAME = "antigravity_voice_prefs"
private const val KEY_DICTATION_LANGUAGE = "dictation_language"
private const val KEY_LAST_DETECTED_LOCALE = "last_detected_locale"

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
 * - Resolves normalized BCP-47 speech locale via KMP [VoiceLocaleResolver] using conversation/draft
 *   context, in-app [AppLanguage], OS preferred locales, active & installed IME languages, and
 *   last auto-detected locale so bilingual Chinese/English users never need to manually switch.
 * - On Android 14+ (API 34+), enables native `EXTRA_ENABLE_LANGUAGE_DETECTION` +
 *   `EXTRA_ENABLE_LANGUAGE_SWITCH` (`LANGUAGE_SWITCH_BALANCED`) with `onLanguageDetection` feedback
 *   and automatic single-locale fallback if an OEM recognizer lacks downloaded switch models.
 * - Guards runtime `RECORD_AUDIO` permission, post-permission audio settle delay, cold-start
 *   `ERROR_RECOGNIZER_BUSY` retry, [SpeechRecognizer.isRecognitionAvailable], main-thread
 *   confinement, OEM IPC exceptions, monotonic session generations, and dispose cleanup.
 */
@Stable
class VoiceDictationController(
    context: Context,
) {
    private val appContext: Context = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val prefs = appContext.getSharedPreferences(VOICE_PREFS_NAME, Context.MODE_PRIVATE)

    var isRecording: Boolean by mutableStateOf(false)
        private set
    var isStarting: Boolean by mutableStateOf(false)
        private set
    var errorMessage: String? by mutableStateOf(null)
        private set
    var preferredLanguage: VoiceDictationLanguage by mutableStateOf(
        VoiceDictationLanguage.fromTag(prefs.getString(KEY_DICTATION_LANGUAGE, null)),
    )
        private set
    var activeLocaleTag: String? by mutableStateOf(null)
        private set
    var lastDetectedLocaleTag: String? by mutableStateOf(
        prefs.getString(KEY_LAST_DETECTED_LOCALE, null)?.trim()?.takeIf { it.isNotEmpty() },
    )
        private set

    private var speechRecognizer: SpeechRecognizer? = null
    private var sessionGeneration: Long = 0L
    private var lastTranscript: String = ""
    private var pendingPrefix: String = ""
    private var pendingAppLanguage: AppLanguage = AppLanguage.ENGLISH
    private var pendingContextTextHint: String? = null
    private var pendingOnDraftUpdated: ((String) -> Unit)? = null
    internal var requestAudioPermissionLauncher: (() -> Unit)? = null

    fun clearError() {
        errorMessage = null
    }

    fun activeLanguageBadgeLabel(
        appLanguage: AppLanguage,
        contextTextHint: String? = null,
    ): String {
        if (preferredLanguage != VoiceDictationLanguage.AUTO) {
            return preferredLanguage.shortBadgeLabel(appLanguage)
        }
        val resolved = activeLocaleTag ?: resolveSpeechLocaleTag(
            appLanguage = appLanguage,
            contextTextHint = contextTextHint ?: pendingContextTextHint,
        )
        val shortLang = VoiceLocaleResolver.shortDisplayLabelForLocale(resolved)
        val autoPrefix = appLanguage.t("Auto", "自动")
        return if (shortLang == "Auto") autoPrefix else "$autoPrefix · $shortLang"
    }

    fun selectLanguage(
        language: VoiceDictationLanguage,
        appLanguage: AppLanguage = AppLanguage.ENGLISH,
        existingDraft: String = "",
        contextTextHint: String? = null,
        onDraftUpdated: ((String) -> Unit)? = null,
    ) {
        preferredLanguage = language
        prefs.edit().putString(KEY_DICTATION_LANGUAGE, language.tag).apply()
        val effectiveHint = contextTextHint ?: pendingContextTextHint
        activeLocaleTag = language.bcp47Tag ?: resolveSpeechLocaleTag(appLanguage, effectiveHint)
        if ((isRecording || isStarting) && onDraftUpdated != null) {
            stopRecording()
            toggleRecording(
                existingDraft = existingDraft,
                appLanguage = appLanguage,
                contextTextHint = effectiveHint,
                onDraftUpdated = onDraftUpdated,
            )
        }
    }

    fun toggleRecording(
        existingDraft: String,
        appLanguage: AppLanguage = AppLanguage.ENGLISH,
        contextTextHint: String? = null,
        onDraftUpdated: (String) -> Unit,
    ) {
        if (isRecording || isStarting) {
            stopRecording()
            return
        }
        errorMessage = null
        lastTranscript = ""
        pendingPrefix = existingDraft
        pendingAppLanguage = appLanguage
        pendingContextTextHint = contextTextHint ?: existingDraft.takeIf { it.isNotBlank() }
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
                errorMessage = appLanguage.t(
                    "Enable Microphone permission in Settings to dictate prompts.",
                    "请在系统设置中开启麦克风权限以使用语音输入。",
                )
                return
            }
            isStarting = true
            runCatching { launcher() }.onFailure {
                isStarting = false
                errorMessage = appLanguage.t(
                    "Unable to request Microphone permission on this device.",
                    "当前设备无法请求麦克风权限。",
                )
            }
        }
    }

    internal fun onPermissionResult(granted: Boolean) {
        if (!isStarting) return
        if (!granted) {
            isStarting = false
            pendingOnDraftUpdated = null
            errorMessage = pendingAppLanguage.t(
                "Enable Microphone permission in Settings to dictate prompts.",
                "请在系统设置中开启麦克风权限以使用语音输入。",
            )
            return
        }
        // Give the system permission overlay ~120ms to release focus/audio state before binding
        // SpeechRecognizer so first-tap recognition never races with dialog dismissal.
        val generationAtGrant = sessionGeneration
        mainHandler.postDelayed(
            {
                if (isStarting && sessionGeneration == generationAtGrant) {
                    startRecognizerOnMainThread()
                }
            },
            120L,
        )
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

    internal fun resolveCandidateLocaleTags(
        appLanguage: AppLanguage,
        contextTextHint: String? = pendingContextTextHint,
    ): List<String> {
        val systemLocales = readSystemPreferredLanguages()
        val keyboardLang = readActiveImeLanguage()
        val installedImes = readInstalledImeLanguages()
        return VoiceLocaleResolver.buildCandidateLocaleTags(
            preference = preferredLanguage,
            appLanguage = appLanguage,
            systemPreferredLanguages = systemLocales,
            activeKeyboardLanguage = keyboardLang,
            installedKeyboardLanguages = installedImes,
            contextTextHint = contextTextHint,
            lastDetectedLocaleTag = lastDetectedLocaleTag,
            fallbackLocaleTag = Locale.getDefault().toLanguageTag(),
        )
    }

    internal fun resolveSpeechLocaleTag(
        appLanguage: AppLanguage,
        contextTextHint: String? = pendingContextTextHint,
    ): String = resolveCandidateLocaleTags(appLanguage, contextTextHint).firstOrNull() ?: "en-US"

    @SuppressLint("InlinedApi")
    internal fun buildRecognizerIntent(
        appLanguage: AppLanguage,
        contextTextHint: String? = pendingContextTextHint,
        enableApi34AutoSwitch: Boolean = true,
        sdkInt: Int = Build.VERSION.SDK_INT,
    ): Pair<Intent, String> {
        val candidates = resolveCandidateLocaleTags(appLanguage, contextTextHint)
        val resolvedLocaleTag = candidates.firstOrNull() ?: "en-US"
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, resolvedLocaleTag)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, resolvedLocaleTag)
            putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, false)

            if (preferredLanguage == VoiceDictationLanguage.AUTO &&
                enableApi34AutoSwitch &&
                sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
            ) {
                val allowedLanguages = VoiceLocaleResolver.buildAutoDetectionAllowedLocales(
                    candidates = candidates,
                    includeBilingualFallback = false,
                    maxCount = 4,
                )
                putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, true)
                if (allowedLanguages.isNotEmpty()) {
                    putStringArrayListExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES,
                        ArrayList(allowedLanguages),
                    )
                }
                if (allowedLanguages.size >= 2) {
                    putExtra(
                        RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH,
                        RecognizerIntent.LANGUAGE_SWITCH_BALANCED,
                    )
                    putStringArrayListExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_SWITCH_ALLOWED_LANGUAGES,
                        ArrayList(allowedLanguages),
                    )
                }
            }
        }
        return intent to resolvedLocaleTag
    }

    private fun rememberDetectedLocale(localeTag: String) {
        val trimmed = localeTag.trim()
        if (trimmed.isEmpty()) return
        lastDetectedLocaleTag = trimmed
        prefs.edit().putString(KEY_LAST_DETECTED_LOCALE, trimmed).apply()
    }

    private fun rememberDetectedLocaleFromTranscript(text: String, activeLocale: String) {
        val inferred = VoiceLocaleResolver.inferLocaleTagFromText(text)
        if (inferred != null) {
            val activeNorm = activeLocale.replace('_', '-').lowercase()
            if (inferred.startsWith("zh") && (activeNorm.startsWith("zh") || activeNorm.startsWith("yue"))) {
                rememberDetectedLocale(activeLocale)
            } else {
                rememberDetectedLocale(inferred)
            }
        } else {
            rememberDetectedLocale(activeLocale)
        }
    }

    private fun readSystemPreferredLanguages(): List<String> = runCatching {
        val localeList = Resources.getSystem().configuration.locales
        buildList {
            for (i in 0 until localeList.size()) {
                val tag = localeList.get(i)?.toLanguageTag().orEmpty()
                if (tag.isNotBlank()) add(tag)
            }
        }
    }.getOrDefault(emptyList())

    @Suppress("DEPRECATION")
    private fun readActiveImeLanguage(): String? = runCatching {
        val imm = appContext.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            ?: return@runCatching null
        val subtype = imm.currentInputMethodSubtype ?: return@runCatching null
        subtype.languageTag.takeIf { it.isNotBlank() }
            ?: subtype.locale.takeIf { it.isNotBlank() }
    }.getOrNull()

    @Suppress("DEPRECATION")
    private fun readInstalledImeLanguages(): List<String> = runCatching {
        val imm = appContext.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            ?: return@runCatching emptyList()
        val result = LinkedHashSet<String>()
        for (imi in imm.enabledInputMethodList.orEmpty()) {
            val subtypes = runCatching {
                imm.getEnabledInputMethodSubtypeList(imi, true)
            }.getOrDefault(emptyList())
            for (subtype in subtypes) {
                val tag = subtype.languageTag.takeIf { it.isNotBlank() }
                    ?: subtype.locale.takeIf { it.isNotBlank() }
                if (!tag.isNullOrBlank()) {
                    result.add(tag)
                }
            }
        }
        result.toList()
    }.getOrDefault(emptyList())

    private fun startRecognizerOnMainThread(
        enableApi34AutoSwitch: Boolean = true,
        retriedColdBusy: Boolean = false,
        retriedWithoutAutoSwitch: Boolean = false,
    ) {
        val generation = ++sessionGeneration
        val appLanguage = pendingAppLanguage
        val contextHint = pendingContextTextHint
        isStarting = true
        runOnMainThread {
            if (generation != sessionGeneration) return@runOnMainThread

            val available = runCatching {
                SpeechRecognizer.isRecognitionAvailable(appContext)
            }.getOrDefault(false)
            if (!available) {
                isStarting = false
                isRecording = false
                errorMessage = appLanguage.t(
                    "Speech recognition service is unavailable on this device.",
                    "当前设备的语音识别服务暂不可用。",
                )
                return@runOnMainThread
            }

            tearDownRecognizerLocked()

            val recognizer = runCatching {
                SpeechRecognizer.createSpeechRecognizer(appContext)
            }.getOrNull()
            if (recognizer == null) {
                isStarting = false
                isRecording = false
                errorMessage = appLanguage.t(
                    "Unable to initialize Speech Recognizer on this device.",
                    "无法初始化当前设备的语音识别器。",
                )
                return@runOnMainThread
            }

            val (intent, resolvedLocaleTag) = buildRecognizerIntent(
                appLanguage = appLanguage,
                contextTextHint = contextHint,
                enableApi34AutoSwitch = enableApi34AutoSwitch,
            )
            val api34AutoSwitchActive = preferredLanguage == VoiceDictationLanguage.AUTO &&
                enableApi34AutoSwitch &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
            val startedElapsedMs = SystemClock.elapsedRealtime()
            activeLocaleTag = resolvedLocaleTag
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

                    override fun onLanguageDetection(results: Bundle) {
                        if (generation != sessionGeneration) return
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val detected = results.getString(SpeechRecognizer.DETECTED_LANGUAGE)
                                ?.trim()
                                ?.takeIf { it.isNotEmpty() }
                            if (detected != null) {
                                activeLocaleTag = detected
                                rememberDetectedLocale(detected)
                            }
                        }
                    }

                    override fun onError(error: Int) {
                        if (generation != sessionGeneration) return
                        val hadTranscript = lastTranscript.isNotBlank()

                        // 1. OEM fallback: if API 34+ language-switch extras fail because an offline
                        //    pack is missing on the device, immediately retry once in single-locale mode.
                        if (!hadTranscript &&
                            api34AutoSwitchActive &&
                            !retriedWithoutAutoSwitch &&
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                            (error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
                                error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE)
                        ) {
                            startRecognizerOnMainThread(
                                enableApi34AutoSwitch = false,
                                retriedColdBusy = retriedColdBusy,
                                retriedWithoutAutoSwitch = true,
                            )
                            return
                        }

                        // 2. Cold-start OEM recognizer-busy race within first 800ms -> retry once after 180ms.
                        val elapsedMs = SystemClock.elapsedRealtime() - startedElapsedMs
                        if (!hadTranscript &&
                            !retriedColdBusy &&
                            error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY &&
                            elapsedMs < 800L
                        ) {
                            tearDownRecognizerLocked()
                            mainHandler.postDelayed(
                                {
                                    if (generation == sessionGeneration) {
                                        startRecognizerOnMainThread(
                                            enableApi34AutoSwitch = enableApi34AutoSwitch,
                                            retriedColdBusy = true,
                                            retriedWithoutAutoSwitch = retriedWithoutAutoSwitch,
                                        )
                                    }
                                },
                                180L,
                            )
                            return
                        }

                        stopRecording()
                        if (!hadTranscript && !isBenignSpeechError(error)) {
                            errorMessage = humanReadableSpeechError(error, appLanguage)
                        }
                    }

                    override fun onResults(results: Bundle?) {
                        if (generation != sessionGeneration) return
                        val text = extractBestTranscript(results)
                        if (!text.isNullOrBlank()) {
                            lastTranscript = text
                            rememberDetectedLocaleFromTranscript(text, activeLocaleTag ?: resolvedLocaleTag)
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

            val started = runCatching {
                recognizer.startListening(intent)
                true
            }.getOrElse { err ->
                errorMessage = appLanguage.t(
                    "Unable to start voice dictation: ${err.localizedMessage ?: "audio error"}",
                    "无法启动语音输入：${err.localizedMessage ?: "音频异常"}",
                )
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

        internal fun humanReadableSpeechError(code: Int, language: AppLanguage = AppLanguage.ENGLISH): String =
            when (code) {
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> language.t(
                    "Enable Microphone permission in Settings to dictate prompts.",
                    "请在系统设置中开启麦克风权限以使用语音输入。",
                )
                SpeechRecognizer.ERROR_AUDIO -> language.t(
                    "Microphone audio input is temporarily unavailable.",
                    "麦克风音频输入暂不可用。",
                )
                SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                -> language.t(
                    "Voice recognition requires a network connection or offline speech pack.",
                    "语音识别需要网络连接或已下载的离线语音包。",
                )
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> language.t(
                    "Speech recognizer is busy. Please try again.",
                    "语音识别服务正忙，请稍后重试。",
                )
                else -> language.t(
                    "Voice dictation stopped. Please try again.",
                    "语音输入已停止，请重试。",
                )
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

/**
 * Compact active-listening bar shown ONLY while recording/starting (zero idle composer clutter),
 * displaying active recognition language with a 1-tap dropdown switcher.
 */
@Composable
internal fun VoiceListeningLanguageBar(
    controller: VoiceDictationController,
    existingDraft: String,
    onDraftUpdated: (String) -> Unit,
    modifier: Modifier = Modifier,
    contextTextHint: String? = null,
) {
    if (!controller.isRecording && !controller.isStarting) return
    val colors = LocalAntigravityColors.current
    val appLanguage = LocalAppLanguage.current
    var menuExpanded by remember { mutableStateOf(false) }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .testTag("composer-voice-listening-bar"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            modifier = Modifier
                .size(7.dp)
                .clip(CircleShape)
                .background(if (controller.isRecording) colors.statusError else colors.accentPeriwinkle),
        )
        Text(
            text = if (controller.isRecording) {
                appLanguage.t("Listening", "正在聆听")
            } else {
                appLanguage.t("Starting microphone...", "正在启动麦克风...")
            },
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium),
            color = colors.inkSecondary,
        )
        Spacer(modifier = Modifier.weight(1f))
        Box {
            Surface(
                shape = RoundedCornerShape(999.dp),
                color = colors.surfaceElevated,
                modifier = Modifier
                    .clip(RoundedCornerShape(999.dp))
                    .clickable { menuExpanded = true }
                    .testTag("composer-voice-language-menu"),
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Language,
                        contentDescription = null,
                        tint = colors.accentPeriwinkle,
                        modifier = Modifier.size(13.dp),
                    )
                    Text(
                        text = controller.activeLanguageBadgeLabel(appLanguage, contextTextHint),
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                        color = colors.accentPeriwinkle,
                    )
                    Icon(
                        imageVector = Icons.Rounded.KeyboardArrowDown,
                        contentDescription = appLanguage.t("Switch dictation language", "切换语音识别语言"),
                        tint = colors.accentPeriwinkle,
                        modifier = Modifier.size(13.dp),
                    )
                }
            }
            VoiceLanguageDropdownMenu(
                expanded = menuExpanded,
                selectedLanguage = controller.preferredLanguage,
                onDismiss = { menuExpanded = false },
                onSelect = { chosen ->
                    menuExpanded = false
                    controller.selectLanguage(
                        language = chosen,
                        appLanguage = appLanguage,
                        existingDraft = existingDraft,
                        contextTextHint = contextTextHint,
                        onDraftUpdated = onDraftUpdated,
                    )
                },
            )
        }
    }
}

@Composable
internal fun VoiceLanguageDropdownMenu(
    expanded: Boolean,
    selectedLanguage: VoiceDictationLanguage,
    onDismiss: () -> Unit,
    onSelect: (VoiceDictationLanguage) -> Unit,
) {
    val colors = LocalAntigravityColors.current
    val appLanguage = LocalAppLanguage.current
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
        containerColor = colors.surfaceCard,
    ) {
        VoiceDictationLanguage.entries.forEach { option ->
            DropdownMenuItem(
                text = {
                    Text(
                        text = option.localizedTitle(appLanguage),
                        color = colors.inkReading,
                        fontWeight = if (option == selectedLanguage) FontWeight.SemiBold else FontWeight.Normal,
                    )
                },
                trailingIcon = if (option == selectedLanguage) {
                    {
                        Icon(
                            imageVector = Icons.Rounded.Check,
                            contentDescription = null,
                            tint = colors.accentPeriwinkle,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                } else {
                    null
                },
                onClick = { onSelect(option) },
            )
        }
    }
}
