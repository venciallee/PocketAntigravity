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
 * Routes via `agpocket://verify/<case>` deep links to validate live Activity startup, Compose rendering,
 * and interactive journeys across all aligned UE boards on a real Android 16 (API 36) runtime.
 */
@RunWith(AndroidJUnit4::class)
class AndroidEmulatorE2eTest {

    @get:Rule
    val composeRule = createEmptyComposeRule()

    private fun launchVerifyScene(sceneSlug: String): ActivityScenario<MainActivity> {
        val intent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("agpocket://verify/$sceneSlug"),
            ApplicationProvider.getApplicationContext(),
            MainActivity::class.java,
        )
        return ActivityScenario.launch(intent)
    }

    @Test
    fun emulatorLaunchNewConversationHomeAndOpenSidebarDrawer() {
        launchVerifyScene("UE01_AGENTS_HOME").use {
            composeRule.onNodeWithTag("btn-sidebar").assertIsDisplayed()
            composeRule.onNodeWithTag("host-switcher-pill").assertIsDisplayed()
            composeRule.onNodeWithTag("home-needs-approval-banner").assertIsDisplayed()
            composeRule.onNodeWithTag("home-composer-card").assertIsDisplayed()
            composeRule.onNodeWithTag("btn-sidebar").performClick()
            composeRule.onNodeWithTag("sidebar-drawer").assertIsDisplayed()
            composeRule.onNodeWithTag("drawer-automations").assertIsDisplayed()
        }
    }

    @Test
    fun emulatorChatTaskCardAndBiometricGate() {
        launchVerifyScene("UE07_CHAT_AND_COMPOSER").use {
            composeRule.onNodeWithTag("chat-diff-pill").assertIsDisplayed()
            composeRule.onNodeWithTag("card-task-progress-7seg").assertIsDisplayed()
            composeRule.onNodeWithTag("card-command-approval").assertIsDisplayed()
            composeRule.onNodeWithTag("composer-pill-model").assertIsDisplayed()
            composeRule.onNodeWithTag("composer-pill-permissions").assertIsDisplayed()
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
    fun emulatorLiveUpdatesNotificationShade() {
        launchVerifyScene("UE13_LIVE_ACTIVITY_SPEC").use {
            composeRule.onNodeWithTag("live-card-running").assertIsDisplayed()
            composeRule.onNodeWithTag("live-card-approval").assertIsDisplayed()
            composeRule.onNodeWithTag("live-card-cloud").assertIsDisplayed()
            composeRule.onNodeWithTag("live-card-done").assertIsDisplayed()
        }
    }

    @Test
    fun emulatorAutomationDetailRulesSkillsAndFlattenedSettings() {
        launchVerifyScene("UE06B_AUTOMATION_DETAIL").use {
            composeRule.onNodeWithTag("btn-automation-run-now").assertIsDisplayed()
            composeRule.onNodeWithTag("btn-retry-run-3").assertIsDisplayed()
        }
        launchVerifyScene("UE14_RULES_AND_SKILLS").use {
            composeRule.onNodeWithTag("rules-token-budget-card").assertIsDisplayed()
            composeRule.onNodeWithTag("skill-row-go-testing").assertIsDisplayed()
        }
        launchVerifyScene("UE15_SETTINGS").use {
            composeRule.onNodeWithTag("btn-scan-new-qr").assertIsDisplayed()
            composeRule.onNodeWithTag("row-settings-language").assertIsDisplayed()
            composeRule.onNodeWithTag("row-settings-more").performClick()
            composeRule.onNodeWithTag("settings-more-subpage").assertIsDisplayed()
        }
    }
}
