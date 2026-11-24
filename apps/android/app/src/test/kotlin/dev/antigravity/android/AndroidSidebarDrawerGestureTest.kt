package dev.antigravity.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import dev.antigravity.android.ui.AntigravityAppRoot
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.EsddVerifySceneCase
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Interactive Compose E2E tests verifying Left Sidebar Drawer (`UE01B_SIDEBAR_DRAWER`)
 * left-to-right swipe-to-open, right-to-left swipe-to-close, underlying screen preservation,
 * and isolation on pushed sub-screens.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-xxhdpi")
class AndroidSidebarDrawerGestureTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun sidebarDrawerOpensOnLeftToRightSwipeAndClosesOnRightToLeftSwipe() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AGENTS_HOME,
            )
        }

        assertEquals(0, composeRule.onAllNodesWithTag("sidebar-drawer").fetchSemanticsNodes().size)

        // Swipe left-to-right from the left edge on Home -> opens Sidebar Drawer
        composeRule.onRoot().performTouchInput {
            swipeRight(startX = width * 0.03f, endX = width * 0.85f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("sidebar-drawer").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-new-conversation").assertIsDisplayed()

        // Swipe right-to-left on the open Sidebar Drawer -> closes cleanly back to Home
        composeRule.onRoot().performTouchInput {
            swipeLeft(startX = width * 0.72f, endX = width * 0.08f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        assertEquals(0, composeRule.onAllNodesWithTag("sidebar-drawer").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("home-greeting").assertIsDisplayed()
    }

    @Test
    fun sidebarDrawerSwipeInChatPreservesActiveConversationOnDismiss() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CHAT_AND_COMPOSER,
            )
        }

        composeRule.onNodeWithTag("chat-diff-pill").assertIsDisplayed()

        // Swipe left-to-right inside CascadeChat -> opens Sidebar Drawer over active conversation
        composeRule.onRoot().performTouchInput {
            swipeRight(startX = width * 0.03f, endX = width * 0.85f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("sidebar-drawer").assertIsDisplayed()

        // Swipe right-to-left -> closes drawer without losing the active conversation
        composeRule.onRoot().performTouchInput {
            swipeLeft(startX = width * 0.72f, endX = width * 0.08f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        assertEquals(0, composeRule.onAllNodesWithTag("sidebar-drawer").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("chat-diff-pill").assertIsDisplayed()
    }

    @Test
    fun pushedProjectDetailDoesNotOpenSidebarOnLeftSwipe() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.PROJECT_DETAIL,
            )
        }

        composeRule.onNodeWithTag("project-tab-active").assertIsDisplayed()
        composeRule.onRoot().performTouchInput {
            swipeRight(startX = width * 0.03f, endX = width * 0.85f, durationMillis = 220)
        }
        composeRule.waitForIdle()
        assertEquals(0, composeRule.onAllNodesWithTag("sidebar-drawer").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("project-tab-active").assertIsDisplayed()
    }
}
