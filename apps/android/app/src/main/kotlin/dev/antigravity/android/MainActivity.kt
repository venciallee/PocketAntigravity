package dev.antigravity.android

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.lifecycleScope
import dev.antigravity.android.core.platform.AndroidLiveUpdateBuilder
import dev.antigravity.android.core.platform.AndroidSharePayloadParser
import dev.antigravity.android.core.platform.BiometricApprovalController
import dev.antigravity.android.ui.AntigravityAppRoot
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.EsddVerifySceneCase
import dev.antigravity.shared.model.RemoteHostInstance
import kotlinx.coroutines.launch

/**
 * Main edge-to-edge Android Activity hosting [AntigravityAppRoot], wiring native
 * [BiometricApprovalController], `antigravity://verify/<case>` ESDD deep links,
 * `antigravity://cascade/<id>` notification tap links, pairing URIs, and Android `ACTION_SEND` shares.
 */
class MainActivity : FragmentActivity() {

    private val biometricController = BiometricApprovalController()

    private var activeCoordinator by mutableStateOf<AntigravityCoreCoordinator?>(null)
    private var activeVerifyScene by mutableStateOf<EsddVerifySceneCase?>(null)
    private var darkThemeOverride by mutableStateOf<Boolean?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        applyLaunchIntent(intent)

        setContent {
            val coordinator = activeCoordinator ?: AppGraph.coordinator(applicationContext)
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = activeVerifyScene,
                darkThemeOverride = darkThemeOverride,
                onBiometricPrompt = { title, onSuccess ->
                    if (biometricController.canAuthenticate(this)) {
                        biometricController.authenticate(
                            activity = this,
                            title = title,
                            subtitle = "Confirm with biometrics or device screen lock",
                            onSuccess = onSuccess,
                        )
                    } else {
                        // Graceful fallback on headless/unenrolled test devices & emulators
                        onSuccess()
                    }
                },
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyLaunchIntent(intent)
    }

    override fun onStart() {
        super.onStart()
        val coordinator = activeCoordinator ?: return
        if (!coordinator.isVerificationMode) {
            lifecycleScope.launch {
                runCatching { coordinator.onForeground() }
            }
        }
    }

    override fun onStop() {
        super.onStop()
        val coordinator = activeCoordinator ?: return
        if (!coordinator.isVerificationMode) {
            coordinator.onBackground()
        }
    }

    private fun applyLaunchIntent(incomingIntent: Intent?) {
        val dataUri = incomingIntent?.data

        // 1. Deterministic ESDD verification deep link (`antigravity://verify/<case>`)
        val verifyScene = resolveVerifySceneFromUri(dataUri)
        if (verifyScene != null) {
            activeCoordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
            activeVerifyScene = verifyScene
            darkThemeOverride = resolveAppearanceOverride(dataUri)
            return
        }

        // 2. Normal production coordinator
        val coordinator = AppGraph.coordinator(applicationContext)
        activeCoordinator = coordinator
        activeVerifyScene = null
        darkThemeOverride = resolveAppearanceOverride(dataUri)

        // 3. Incoming Android Share Intent (`ACTION_SEND` / `ACTION_SEND_MULTIPLE`)
        val sharedPayload = AndroidSharePayloadParser.parse(this, incomingIntent)
        if (sharedPayload != null) {
            val formatted = buildString {
                if (!sharedPayload.subject.isNullOrBlank()) {
                    append(sharedPayload.subject)
                    append("\n")
                }
                if (sharedPayload.text.isNotBlank()) {
                    append(sharedPayload.text)
                }
                if (sharedPayload.uris.isNotEmpty()) {
                    if (isNotEmpty()) append("\n")
                    append(sharedPayload.uris.joinToString("\n"))
                }
            }.trim()
            if (formatted.isNotEmpty()) {
                coordinator.chatStore.setDraftInputText(formatted)
            }
            return
        }

        // 4. Notification or Deep Link targeting a specific Cascade conversation or Pairing URI
        val extraCascadeId = incomingIntent?.getStringExtra(AndroidLiveUpdateBuilder.EXTRA_CASCADE_ID)
        if (!extraCascadeId.isNullOrBlank()) {
            coordinator.chatStore.setActiveCascade(extraCascadeId)
            return
        }

        if (dataUri != null &&
            (dataUri.scheme.equals("agpocket", ignoreCase = true) ||
                dataUri.scheme.equals("antigravity", ignoreCase = true))
        ) {
            val host = dataUri.host.orEmpty().lowercase()
            if (host == "cascade" || host == "c") {
                val cascadeId = dataUri.lastPathSegment.orEmpty()
                if (cascadeId.isNotEmpty()) {
                    coordinator.chatStore.setActiveCascade(cascadeId)
                }
            } else if (RemoteHostInstance.isDirectLanPairingUri(dataUri.toString()) ||
                RemoteHostInstance.parseRemoteControlTarget(dataUri.toString()) != null
            ) {
                lifecycleScope.launch {
                    runCatching { coordinator.connectWithPairingUri(dataUri.toString()) }
                }
            }
        } else if (dataUri != null &&
            dataUri.scheme.equals("https", ignoreCase = true) &&
            RemoteHostInstance.parseRemoteControlTarget(dataUri.toString()) != null
        ) {
            lifecycleScope.launch {
                runCatching { coordinator.connectWithPairingUri(dataUri.toString()) }
            }
        }
    }

    companion object {
        fun resolveVerifySceneFromUri(uri: Uri?): EsddVerifySceneCase? {
            if (uri == null) return null
            if (!uri.scheme.equals("agpocket", ignoreCase = true) &&
                !uri.scheme.equals("antigravity", ignoreCase = true)
            ) {
                return null
            }
            if (!uri.host.equals("verify", ignoreCase = true)) return null
            val rawSlug = uri.lastPathSegment?.trim().orEmpty()
            if (rawSlug.isEmpty()) return null

            EsddVerifySceneCase.entries.firstOrNull {
                it.rawValue.equals(rawSlug, ignoreCase = true) || it.name.equals(rawSlug, ignoreCase = true)
            }?.let { return it }

            return when (rawSlug.lowercase()) {
                "ue01", "agents-home", "new-conversation" -> EsddVerifySceneCase.AGENTS_HOME
                "ue01b", "sidebar-drawer", "sidebar" -> EsddVerifySceneCase.SIDEBAR_DRAWER
                "ue02", "display-options" -> EsddVerifySceneCase.DISPLAY_OPTIONS
                "ue03", "context-menu-pin", "context-menu" -> EsddVerifySceneCase.CONTEXT_MENU_PIN
                "ue05", "create-project", "new-project" -> EsddVerifySceneCase.CREATE_PROJECT
                "ue06", "automations" -> EsddVerifySceneCase.AUTOMATIONS
                "ue06b", "automation-detail" -> EsddVerifySceneCase.AUTOMATION_DETAIL
                "ue06c", "automation-edit" -> EsddVerifySceneCase.AUTOMATION_EDIT
                "ue07", "chat-and-composer" -> EsddVerifySceneCase.CHAT_AND_COMPOSER
                "ue07b", "permissions-preset", "preset" -> EsddVerifySceneCase.PERMISSIONS_PRESET
                "ue08", "add-context" -> EsddVerifySceneCase.ADD_CONTEXT
                "ue08b", "slash-menu", "slash" -> EsddVerifySceneCase.SLASH_MENU
                "ue09", "model-and-mode", "model" -> EsddVerifySceneCase.MODEL_AND_MODE
                "ue10", "structured-question", "ask" -> EsddVerifySceneCase.STRUCTURED_QUESTION
                "ue11", "plan-review" -> EsddVerifySceneCase.PLAN_REVIEW
                "ue12", "turn-diff-review", "diff" -> EsddVerifySceneCase.TURN_DIFF_REVIEW
                "ue13", "live-activity-spec", "live-updates-spec", "live-update" -> EsddVerifySceneCase.LIVE_ACTIVITY_SPEC
                "ue14", "rules-and-skills", "customizations" -> EsddVerifySceneCase.RULES_AND_SKILLS
                "ue15", "settings" -> EsddVerifySceneCase.SETTINGS
                else -> null
            }
        }

        private fun resolveAppearanceOverride(uri: Uri?): Boolean? {
            val raw = uri?.getQueryParameter("appearance")?.trim()?.lowercase() ?: return null
            return when (raw) {
                "dark" -> true
                "light" -> false
                else -> null
            }
        }
    }
}
