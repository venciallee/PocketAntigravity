package dev.antigravity.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import dev.antigravity.android.core.ui.theme.AntigravityTheme
import dev.antigravity.android.ui.home.AgentsHomeScreen
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Verifies Android Home (`UE01`) renders the real signed-in user's name from `GetUserStatus`
 * (or a clean nameless fallback) in live mode, and never leaks the static ESDD mockup name `"Alex"`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-xxhdpi")
class AndroidUserGreetingE2eTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun liveHomeGreetingUsesRealUserNameAndNeverShowsMockAlex() {
        val coordinator = AntigravityCoreCoordinator()
        assertFalse(coordinator.isVerificationMode)

        composeRule.setContent {
            AntigravityTheme(darkTheme = true) {
                AgentsHomeScreen(
                    coordinator = coordinator,
                    onOpenSidebar = {},
                    onOpenConversation = {},
                )
            }
        }

        // Before GetUserStatus resolves, live Home shows clean nameless greeting (never "Alex")
        composeRule.onNodeWithText("Welcome back.\nWhere should\nwe pick up?").assertIsDisplayed()
        composeRule.onNodeWithText("Alex", substring = true).assertDoesNotExist()

        // Once GetUserStatus populates the real user name, greeting updates dynamically
        coordinator.connectionStore.setUserDisplayName("Vencial Lee", persist = false)
        composeRule.onNodeWithText("Welcome back,\nVencial. Where\nshould we pick up?").assertIsDisplayed()
        composeRule.onNodeWithText("Alex", substring = true).assertDoesNotExist()
    }
}
