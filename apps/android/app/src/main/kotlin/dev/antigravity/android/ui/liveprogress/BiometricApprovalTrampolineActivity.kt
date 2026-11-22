package dev.antigravity.android.ui.liveprogress

import android.app.NotificationManager
import android.os.Bundle
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.lifecycleScope
import dev.antigravity.android.AppGraph
import dev.antigravity.android.core.platform.AndroidLiveUpdateBuilder
import dev.antigravity.android.core.platform.BiometricApprovalController
import dev.antigravity.shared.model.InteractionDecision
import kotlinx.coroutines.launch

/**
 * Transparent single-instance trampoline activity launched when the user taps "Allow" from an
 * Android 16 Live Update notification or Lock Screen approval card. Invokes native Android
 * [BiometricApprovalController] (`BIOMETRIC_STRONG or DEVICE_CREDENTIAL`) and dispatches
 * `HandleCascadeUserInteraction` upon cryptographic/OS verification.
 */
class BiometricApprovalTrampolineActivity : FragmentActivity() {

    private val biometricController = BiometricApprovalController()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val cascadeId = intent?.getStringExtra(AndroidLiveUpdateBuilder.EXTRA_CASCADE_ID).orEmpty()
        val stepIndex = intent?.getIntExtra(AndroidLiveUpdateBuilder.EXTRA_STEP_INDEX, -1) ?: -1
        val commandPreview = intent?.getStringExtra(AgentProgressForegroundService.EXTRA_COMMAND_PREVIEW)
            ?.takeIf { it.isNotBlank() }

        if (cascadeId.isEmpty() || stepIndex < 0) {
            finish()
            return
        }

        biometricController.authenticate(
            activity = this,
            title = "Approve agent command",
            subtitle = "Confirm with biometrics or screen lock",
            description = commandPreview,
            onSuccess = {
                val coordinator = AppGraph.coordinator(applicationContext)
                lifecycleScope.launch {
                    runCatching {
                        coordinator.resolveWaitingInteraction(
                            cascadeId = cascadeId,
                            stepIndex = stepIndex,
                            decision = InteractionDecision.AllowWithBiometric,
                        )
                    }
                    getSystemService(NotificationManager::class.java)
                        ?.cancel(AgentProgressForegroundService.NOTIFICATION_ID)
                    finish()
                }
            },
            onCancel = { finish() },
            onError = { _, _ -> finish() },
        )
    }
}
