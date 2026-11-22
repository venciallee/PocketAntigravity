package dev.antigravity.android.core.platform

import android.content.Context
import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import dev.antigravity.shared.model.RequestedInteraction

/**
 * Policy classifying which [RequestedInteraction.MemberKind] gates execute privileged host actions
 * and therefore require biometric or device-credential verification before dispatching approval.
 */
object BiometricApprovalPolicy {
    private val highRiskKinds: Set<RequestedInteraction.MemberKind> = setOf(
        RequestedInteraction.MemberKind.RUN_COMMAND,
        RequestedInteraction.MemberKind.WORKFLOW_SCRIPT,
        RequestedInteraction.MemberKind.DEPLOY,
        RequestedInteraction.MemberKind.RUN_EXTENSION_CODE,
        RequestedInteraction.MemberKind.APPROVAL_INTERACTION,
        RequestedInteraction.MemberKind.PERMISSION,
        RequestedInteraction.MemberKind.FILE_PERMISSION,
        RequestedInteraction.MemberKind.MCP,
        RequestedInteraction.MemberKind.EXECUTE_URL,
        RequestedInteraction.MemberKind.DOWNLOAD_URL,
        RequestedInteraction.MemberKind.BROWSER_UPLOAD,
    )

    fun requiresBiometric(kind: RequestedInteraction.MemberKind): Boolean = kind in highRiskKinds
}

/**
 * Native Android [BiometricPrompt] wrapper using `BIOMETRIC_STRONG or DEVICE_CREDENTIAL`
 * (with API 29 fallback to `BIOMETRIC_WEAK or DEVICE_CREDENTIAL` as required by AndroidX Biometric).
 */
class BiometricApprovalController {

    private fun allowedAuthenticators(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else {
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        }

    fun canAuthenticate(context: Context): Boolean {
        val result = BiometricManager.from(context).canAuthenticate(allowedAuthenticators())
        return result == BiometricManager.BIOMETRIC_SUCCESS
    }

    fun authenticate(
        activity: FragmentActivity,
        title: String,
        subtitle: String? = null,
        description: String? = null,
        onSuccess: () -> Unit,
        onCancel: () -> Unit = {},
        onError: (errorCode: Int, message: String) -> Unit = { _, _ -> },
    ) {
        if (!canAuthenticate(activity)) {
            onError(
                BiometricPrompt.ERROR_NO_BIOMETRICS,
                "Biometric or device screen lock authentication is not configured.",
            )
            return
        }

        val executor = ContextCompat.getMainExecutor(activity)
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                onSuccess()
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                when (errorCode) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED,
                    -> onCancel()

                    else -> onError(errorCode, errString.toString())
                }
            }

            override fun onAuthenticationFailed() {
                // System prompt remains visible and allows retry; no terminal callback needed.
            }
        }

        val promptInfoBuilder = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setAllowedAuthenticators(allowedAuthenticators())

        if (!subtitle.isNullOrBlank()) {
            promptInfoBuilder.setSubtitle(subtitle)
        }
        if (!description.isNullOrBlank()) {
            promptInfoBuilder.setDescription(description)
        }

        val prompt = BiometricPrompt(activity, executor, callback)
        prompt.authenticate(promptInfoBuilder.build())
    }
}
