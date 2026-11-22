package dev.antigravity.android

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real Android Emulator Instrumented E2E test suite executed on GitHub Actions `ubuntu-latest` KVM runners.
 * Routes via `antigravity://verify/<case>` deep links to validate live Activity startup, Compose rendering,
 * and interactive journeys on a real Android 16 (API 36) runtime.
 */
@RunWith(AndroidJUnit4::class)
class AndroidEmulatorE2eTest {

    @get:Rule
    val composeRule = createEmptyComposeRule()

    private fun launchVerifyScene(sceneSlug: String): ActivityScenario<MainActivity> {
        val intent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("antigravity://verify/$sceneSlug"),
            ApplicationProvider.getApplicationContext(),
            MainActivity::class.java,
        )
        return ActivityScenario.launch(intent)
    }

    @Test
    fun emulatorLaunchAgentsHomeAndFilterNeedsYou() {
        launchVerifyScene("UE01_AGENTS_HOME").use {
            composeRule.onNodeWithTag("host-switcher-pill").assertIsDisplayed()
            composeRule.onNodeWithTag("fab-compose").assertIsDisplayed()
            composeRule.onNodeWithTag("filter-pill-needs-you").performClick()
            composeRule.onNodeWithTag("bottom-nav-bar").assertIsDisplayed()
        }
    }

    @Test
    fun emulatorChatTaskCardAndBiometricGate() {
        launchVerifyScene("UE07_CHAT_AND_COMPOSER").use {
            composeRule.onNodeWithTag("chat-diff-pill").assertIsDisplayed()
            composeRule.onNodeWithTag("card-task-progress-7seg").assertIsDisplayed()
            composeRule.onNodeWithTag("card-command-approval").assertIsDisplayed()
            composeRule.onNodeWithTag("composer-btn-send").assertIsDisplayed()
        }
    }

    @Test
    fun emulatorPlanReviewAndTurnDiffScreens() {
        launchVerifyScene("UE11_PLAN_REVIEW").use {
            composeRule.onNodeWithTag("plan-paused-banner").assertIsDisplayed()
            composeRule.onNodeWithTag("btn-plan-proceed").assertIsDisplayed()
        }
        launchVerifyScene("UE12_TURN_DIFF_REVIEW").use {
            composeRule.onNodeWithTag("file-pager-card").assertIsDisplayed()
            composeRule.onNodeWithTag("btn-accept-file").assertIsDisplayed()
        }
    }

    @Test
    fun emulatorLiveUpdatesSpecShowcase() {
        launchVerifyScene("UE13_LIVE_ACTIVITY_SPEC").use {
            composeRule.onNodeWithTag("lu-chip-running").assertIsDisplayed()
            composeRule.onNodeWithTag("lu-expanded-waiting").assertIsDisplayed()
            composeRule.onNodeWithTag("lu-lockscreen-multi-agent").assertIsDisplayed()
        }
    }
}
