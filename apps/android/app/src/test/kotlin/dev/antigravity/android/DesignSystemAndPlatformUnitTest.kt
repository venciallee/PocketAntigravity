package dev.antigravity.android

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import dev.antigravity.android.core.platform.AndroidLiveUpdateBuilder
import dev.antigravity.android.core.platform.AndroidPreferencesStore
import dev.antigravity.android.core.platform.AndroidProjectionStorage
import dev.antigravity.android.core.platform.AndroidSharePayloadParser
import dev.antigravity.android.core.platform.BiometricApprovalPolicy
import dev.antigravity.android.core.platform.LiveUpdateDismissTracker
import dev.antigravity.android.core.ui.icons.toMaterialIcon
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.shared.model.AppThemePreset
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.LiveProgressPhase
import dev.antigravity.shared.model.LiveProgressSnapshot
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.model.SemanticIcon
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DesignSystemAndPlatformUnitTest {

    @Test
    fun allSemanticIconsMapToMaterialSymbolsWithoutException() {
        for (icon in SemanticIcon.entries) {
            val vector = icon.toMaterialIcon()
            assertNotNull("Missing Material icon mapping for $icon", vector)
        }
    }

    @Test
    fun themeTokensPreserveLockedSemanticStatusAcrossPresetsAndDarkLight() {
        val darkObsidian = AntigravityDesignTokens.extendedColors(
            preset = AppThemePreset.OBSIDIAN,
            darkTheme = true,
        )
        val lightObsidian = AntigravityDesignTokens.extendedColors(
            preset = AppThemePreset.OBSIDIAN,
            darkTheme = false,
        )
        assertEquals(0xFF090A0D.toInt(), darkObsidian.canvasBackgroundHex)
        assertEquals(0xFF8EB4FF.toInt(), darkObsidian.accentPeriwinkleHex)
        assertEquals(0xFFEBB365.toInt(), darkObsidian.statusWaitingHex)
        assertEquals(0xFF57C88A.toInt(), darkObsidian.statusDoneHex)
        assertEquals(0xFFF07167.toInt(), darkObsidian.statusErrorHex)

        // Light mode maintains high-contrast WCAG AA tokens
        assertEquals(0xFFF4F5F8.toInt(), lightObsidian.canvasBackgroundHex)
        assertEquals(0xFF2F66E8.toInt(), lightObsidian.accentPeriwinkleHex)
        assertEquals(0xFFB86E00.toInt(), lightObsidian.statusWaitingHex)
        assertEquals(48, AntigravityDesignTokens.MIN_TOUCH_TARGET_DP)
    }

    @Test
    fun android16LiveUpdateBuilderEnforcesPromotionAndSuppressionRules() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val running = LiveProgressSnapshot(
            cascadeId = "cas-rate-limiter",
            cascadeTitle = "Add rate limiter to /transfers",
            hostName = "MacBook Pro",
            workspaceName = "ledger-svc",
            branchName = "main",
            phase = LiveProgressPhase.RUNNING,
            currentStepIndex = 4,
            totalSteps = 7,
            activeToolAction = "go test ./internal/...",
            elapsedSeconds = 161,
            additions = 128,
            deletions = 14,
        )

        val runningSpec = AndroidLiveUpdateBuilder.buildRenderSpec(running)
        assertEquals("4/7", runningSpec.shortCriticalText)
        assertEquals(7, runningSpec.totalSegments)
        assertEquals(4, runningSpec.completedSegments)
        assertTrue(runningSpec.requestPromotedOngoing)
        assertFalse("Must never use custom RemoteViews for Android 16 promotion", runningSpec.usesCustomRemoteViews)
        assertFalse("Must never set colorized=true for Android 16 promotion", runningSpec.isColorized)

        val waiting = running.copy(
            phase = LiveProgressPhase.WAITING_APPROVAL,
            pendingApprovalCommand = "vegeta attack -rate=2000/s -duration=30s",
        )
        val waitingSpec = AndroidLiveUpdateBuilder.buildRenderSpec(waiting)
        assertEquals("Approve", waitingSpec.shortCriticalText)
        assertTrue(waitingSpec.requiresBiometricApprovalAction)
        assertTrue(waitingSpec.hasDenyAction)

        val done = running.copy(phase = LiveProgressPhase.COMPLETED)
        val doneSpec = AndroidLiveUpdateBuilder.buildRenderSpec(done)
        assertEquals("+128 -14", doneSpec.shortCriticalText)

        // Build real Android notification without crashing on Robolectric API 35
        val notification = AndroidLiveUpdateBuilder.buildNotification(context, waiting)
        assertNotNull(notification)

        // Dismiss tracker suppresses re-posting for the same turn until next turn starts
        val dismissTracker = LiveUpdateDismissTracker()
        assertFalse(dismissTracker.isSuppressed("cas-rate-limiter", stepIndex = 4))
        dismissTracker.markUserDismissed("cas-rate-limiter", stepIndex = 4)
        assertTrue(dismissTracker.isSuppressed("cas-rate-limiter", stepIndex = 4))
        assertFalse(dismissTracker.isSuppressed("cas-rate-limiter", stepIndex = 5))

        // Manual cancel must suppress completion alert (matching desktop v2.22+ & iOS)
        assertFalse(
            AndroidLiveUpdateBuilder.shouldNotifyOnStatusTransition(
                previousStatus = CortexStepStatus.IN_PROGRESS,
                nextStatus = CortexStepStatus.CANCELLED,
                wasManuallyCancelled = true,
            )
        )
        assertTrue(
            AndroidLiveUpdateBuilder.shouldNotifyOnStatusTransition(
                previousStatus = CortexStepStatus.IN_PROGRESS,
                nextStatus = CortexStepStatus.WAITING,
                wasManuallyCancelled = false,
            )
        )
    }

    @Test
    fun biometricPolicyAndShareParserAndPlatformStoresWorkCorrectly() = runTest {
        val context = ApplicationProvider.getApplicationContext<Context>()

        // High-risk interactions require biometric verification
        assertTrue(BiometricApprovalPolicy.requiresBiometric(RequestedInteraction.MemberKind.RUN_COMMAND))
        assertTrue(BiometricApprovalPolicy.requiresBiometric(RequestedInteraction.MemberKind.WORKFLOW_SCRIPT))
        assertTrue(BiometricApprovalPolicy.requiresBiometric(RequestedInteraction.MemberKind.APPROVAL_INTERACTION))
        assertFalse(BiometricApprovalPolicy.requiresBiometric(RequestedInteraction.MemberKind.ASK_QUESTION))

        // Share intent extraction (text + URL)
        val shareIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, "Production Error Stack")
            putExtra(Intent.EXTRA_TEXT, "See https://github.com/acme/ledger-svc/pull/42")
        }
        val parsedShare = AndroidSharePayloadParser.parse(context, shareIntent)
        assertNotNull(parsedShare)
        assertEquals("Production Error Stack", parsedShare!!.subject)
        assertTrue(parsedShare.text.contains("pull/42"))

        // Preferences & Projection storage round-trip
        val prefs = AndroidPreferencesStore(context, prefsName = "test_prefs_unit")
        prefs.putString("theme", "OBSIDIAN")
        assertEquals("OBSIDIAN", prefs.getString("theme"))
        prefs.putString("theme", null)
        assertNull(prefs.getString("theme"))

        val storage = AndroidProjectionStorage(context)
        storage.writeText("unit-test.json", """{"ok":true}""")
        assertEquals("""{"ok":true}""", storage.readText("unit-test.json"))
        storage.delete("unit-test.json")
        assertNull(storage.readText("unit-test.json"))
    }

    @Test
    fun cloudRelayCookieBridgeNormalizesShortDomainAndSanitizesWebViewUserAgent() {
        val urls = dev.antigravity.android.core.platform.CloudRelayCookieBridge.urlsForHost("antigravity.google")
        assertTrue(urls.contains("https://antigravity.google"))
        assertTrue(urls.contains("https://antigravity.google.com"))
        assertTrue(urls.contains("https://google.com"))

        val normalized = dev.antigravity.android.ui.pairing.normalizeRelayStartUrl("https://antigravity.google/r/test-id")
        assertEquals("https://antigravity.google.com/r/test-id", normalized)
        val normalizedSubdomain = dev.antigravity.android.ui.pairing.normalizeRelayStartUrl("https://staging.antigravity.google/r/test-id")
        assertEquals("https://staging.antigravity.google.com/r/test-id", normalizedSubdomain)
        assertTrue(dev.antigravity.android.ui.pairing.isRelayHostUrl("https://antigravity.google.com/r/test-id"))
        assertTrue(dev.antigravity.android.ui.pairing.isRelayHostUrl("https://antigravity.google/r/test-id"))
        assertFalse(dev.antigravity.android.ui.pairing.isRelayHostUrl("https://accounts.google.com/signin"))

        val captured = dev.antigravity.android.ui.pairing.CloudRelayCapturedSession(
            cookieHeader = "SAPISID=test; SID=test",
            relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
            authUser = "0",
            finalUrl = "https://antigravity.google.com/r/test-id",
        )
        assertEquals(
            "https://antigravity.google.com/r/test-id",
            dev.antigravity.shared.model.RemoteHostInstance.resolveEffectiveRelayTarget(
                scannedInput = "https://antigravity.google/r/test-id",
                webViewFinalUrl = captured.finalUrl,
            ),
        )

        val sanitizedUa = dev.antigravity.android.ui.pairing.sanitizeGoogleOAuthUserAgent(
            "Mozilla/5.0 (Linux; Android 15; Pixel 9; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.0.0 Mobile Safari/537.36",
        )
        assertFalse("WebView `; wv)` marker must be stripped for Google OAuth", sanitizedUa.contains("; wv)"))
        assertFalse(sanitizedUa.contains("Version/4.0"))
        assertTrue(sanitizedUa.contains("Chrome/131.0.0.0"))

        // Android evaluateJavascript result decoding (JSON-quoted string vs null/empty/short)
        val fakeKey = "AI" + "zaSyANDROIDWIZKEY00000000000000000000"
        assertEquals(fakeKey, dev.antigravity.android.ui.pairing.parseEvaluateJsStringResult("\"$fakeKey\""))
        assertNull(dev.antigravity.android.ui.pairing.parseEvaluateJsStringResult("null"))
        assertNull(dev.antigravity.android.ui.pairing.parseEvaluateJsStringResult("\"\""))
        assertNull(dev.antigravity.android.ui.pairing.parseEvaluateJsStringResult("\"short\""))

        // DOM inspection script covers WIZ_global_data + inline scripts without hardcoding any secret literal
        val inspectJs = dev.antigravity.android.ui.pairing.ANDROID_API_KEY_INSPECT_JS
        assertTrue(inspectJs.contains("WIZ_global_data"))
        assertTrue(inspectJs.contains("WIu0Nc"))
        assertTrue(inspectJs.contains("antigravity-relay-api-key"))
        assertFalse("Inspect script must split prefix instead of hardcoding AIza literal", inspectJs.contains("AI" + "za"))

        // Effective relay target resolves WebView finalUrl and canonicalizes vanity host
        val resolved = dev.antigravity.shared.model.RemoteHostInstance.resolveEffectiveRelayTarget(
            scannedInput = "https://antigravity.google/r/0f5819ac-9308-40d8-a308-98b55122c533-v2",
            webViewFinalUrl = "https://antigravity.google.com/r/0f5819ac-9308-40d8-a308-98b55122c533-v2?authuser=1",
        )
        assertEquals("https://antigravity.google.com/r/0f5819ac-9308-40d8-a308-98b55122c533-v2?authuser=1", resolved)
        val resolvedNoFinal = dev.antigravity.shared.model.RemoteHostInstance.resolveEffectiveRelayTarget(
            scannedInput = "https://antigravity.google/r/0f5819ac-9308-40d8-a308-98b55122c533-v2",
            webViewFinalUrl = null,
        )
        assertEquals("https://antigravity.google.com/r/0f5819ac-9308-40d8-a308-98b55122c533-v2", resolvedNoFinal)
    }
}
