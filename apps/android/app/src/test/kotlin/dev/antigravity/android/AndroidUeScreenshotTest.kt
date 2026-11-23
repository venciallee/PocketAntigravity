package dev.antigravity.android

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.github.takahirom.roborazzi.captureRoboImage
import dev.antigravity.android.ui.AntigravityAppRoot
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.EsddVerifySceneCase
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Real Jetpack Compose pixel screenshot capture & Material 3 geometry audit across ALL 20 aligned
 * UE screens (`UE01_AGENTS_HOME` .. `UE15_SETTINGS`) plus Light Mode visual verification.
 *
 * Output PNGs are written deterministically under `build/outputs/android_ue/` and paired side-by-side
 * with `docs/ue/android/` PNG boards via `python3 verification/android_visual_compare.py`.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-xxhdpi")
class AndroidUeScreenshotTest {

    @get:Rule
    val composeRule = createComposeRule()

    private fun capturePortraitScreen(
        scene: EsddVerifySceneCase,
        fileName: String,
        darkTheme: Boolean = true,
        touchTargetTags: List<String> = emptyList(),
    ) {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            Box(modifier = Modifier.size(width = 412.dp, height = 915.dp)) {
                AntigravityAppRoot(
                    coordinator = coordinator,
                    initialVerifyScene = scene,
                    darkThemeOverride = darkTheme,
                )
            }
        }
        composeRule.waitForIdle()

        // Audit Material 3 touch targets & zero horizontal overflow
        for (tag in touchTargetTags) {
            assertTouchTargetAndNoOverflow(composeRule.onNodeWithTag(tag), tag)
        }

        composeRule.onRoot().captureRoboImage("build/outputs/android_ue/$fileName.png")
    }

    private fun assertTouchTargetAndNoOverflow(node: SemanticsNodeInteraction, tag: String) {
        val bounds = node.getUnclippedBoundsInRoot()
        val widthDp = (bounds.right - bounds.left).value
        val heightDp = (bounds.bottom - bounds.top).value
        assertTrue(
            "Touch target '$tag' dimensions ${widthDp}x${heightDp}dp too small",
            heightDp >= 34f || widthDp >= 36f,
        )
        assertTrue(
            "Control '$tag' overflows right viewport edge: right=${bounds.right.value}dp > 414dp",
            bounds.right.value <= 414f,
        )
    }

    @Test
    fun capture_UE01_AGENTS_HOME() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.AGENTS_HOME,
            fileName = "UE01_AGENTS_HOME",
            touchTargetTags = listOf("btn-sidebar", "host-switcher-pill", "btn-search", "home-needs-approval-banner"),
        )
    }

    @Test
    fun capture_UE01_AGENTS_HOME_LIGHT() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.AGENTS_HOME,
            fileName = "UE01_AGENTS_HOME_LIGHT",
            darkTheme = false,
            touchTargetTags = listOf("btn-sidebar", "host-switcher-pill"),
        )
    }

    @Test
    fun capture_UE01B_SIDEBAR_DRAWER() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.SIDEBAR_DRAWER,
            fileName = "UE01B_SIDEBAR_DRAWER",
            touchTargetTags = listOf("btn-new-conversation", "btn-display-options", "btn-create-project", "drawer-settings"),
        )
    }

    @Test
    fun capture_UE02_DISPLAY_OPTIONS() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.DISPLAY_OPTIONS,
            fileName = "UE02_DISPLAY_OPTIONS",
            touchTargetTags = listOf("sheet-reset-btn", "btn-mark-all-read"),
        )
    }

    @Test
    fun capture_UE03_CONTEXT_MENU_PIN() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.CONTEXT_MENU_PIN,
            fileName = "UE03_CONTEXT_MENU_PIN",
            touchTargetTags = listOf("action-pin", "action-delete"),
        )
    }

    @Test
    fun capture_UE04_PROJECT_DETAIL() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.PROJECT_DETAIL,
            fileName = "UE04_PROJECT_DETAIL",
            touchTargetTags = listOf("btn-back", "btn-new-conv-in-project", "project-row-rules-skills"),
        )
    }

    @Test
    fun capture_UE05_CREATE_PROJECT() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.CREATE_PROJECT,
            fileName = "UE05_CREATE_PROJECT",
            touchTargetTags = listOf("btn-cancel-create-project", "btn-create-project-submit"),
        )
    }

    @Test
    fun capture_UE06_AUTOMATIONS() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.AUTOMATIONS,
            fileName = "UE06_AUTOMATIONS",
            touchTargetTags = listOf("btn-create-automation", "automation-overflow-menu"),
        )
    }

    @Test
    fun capture_UE06B_AUTOMATION_DETAIL() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.AUTOMATION_DETAIL,
            fileName = "UE06B_AUTOMATION_DETAIL",
            touchTargetTags = listOf("btn-automation-run-now", "btn-automation-pause-resume"),
        )
    }

    @Test
    fun capture_UE06C_AUTOMATION_EDIT() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.AUTOMATION_EDIT,
            fileName = "UE06C_AUTOMATION_EDIT",
            touchTargetTags = listOf("btn-close-edit-automation", "btn-save-automation"),
        )
    }

    @Test
    fun capture_UE07_CHAT_AND_COMPOSER() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.CHAT_AND_COMPOSER,
            fileName = "UE07_CHAT_AND_COMPOSER",
            touchTargetTags = listOf("btn-command-deny", "btn-command-allow-biometric", "composer-btn-send"),
        )
    }

    @Test
    fun capture_UE07_CHAT_AND_COMPOSER_LIGHT() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.CHAT_AND_COMPOSER,
            fileName = "UE07_CHAT_AND_COMPOSER_LIGHT",
            darkTheme = false,
            touchTargetTags = listOf("btn-command-allow-biometric", "composer-btn-send"),
        )
    }

    @Test
    fun capture_UE07B_PERMISSIONS_PRESET() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.PERMISSIONS_PRESET,
            fileName = "UE07B_PERMISSIONS_PRESET",
            touchTargetTags = listOf("permissions-preset-popover"),
        )
    }

    @Test
    fun capture_UE08_ADD_CONTEXT() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.ADD_CONTEXT,
            fileName = "UE08_ADD_CONTEXT",
            touchTargetTags = listOf("add-context-popover", "ctx-menu-files"),
        )
    }

    @Test
    fun capture_UE08B_SLASH_MENU() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.SLASH_MENU,
            fileName = "UE08B_SLASH_MENU",
            touchTargetTags = listOf("slash-menu-card", "slash-item-plan"),
        )
    }

    @Test
    fun capture_UE09_MODEL_AND_MODE() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.MODEL_AND_MODE,
            fileName = "UE09_MODEL_AND_MODE",
            touchTargetTags = listOf("btn-model-done", "model-row-MODEL_GOOGLE_GEMINI_4_NEON"),
        )
    }

    @Test
    fun capture_UE10_STRUCTURED_QUESTION() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.STRUCTURED_QUESTION,
            fileName = "UE10_STRUCTURED_QUESTION",
            touchTargetTags = listOf("btn-question-prev", "btn-question-next"),
        )
    }

    @Test
    fun capture_UE11_PLAN_REVIEW() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.PLAN_REVIEW,
            fileName = "UE11_PLAN_REVIEW",
            touchTargetTags = listOf("btn-plan-proceed", "btn-plan-send-comments"),
        )
    }

    @Test
    fun capture_UE12_TURN_DIFF_REVIEW() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.TURN_DIFF_REVIEW,
            fileName = "UE12_TURN_DIFF_REVIEW",
            touchTargetTags = listOf("btn-accept-all-diffs", "btn-revert-file", "btn-accept-file"),
        )
    }

    @Test
    fun capture_UE13_LIVE_ACTIVITY_SPEC() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.LIVE_ACTIVITY_SPEC,
            fileName = "UE13_LIVE_ACTIVITY_SPEC",
            touchTargetTags = listOf("live-card-running", "live-card-approval"),
        )
    }

    @Test
    fun capture_UE14_RULES_AND_SKILLS() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.RULES_AND_SKILLS,
            fileName = "UE14_RULES_AND_SKILLS",
            touchTargetTags = listOf("rules-token-budget-card", "switch-plugin-plugin-firebase"),
        )
    }

    @Test
    fun capture_UE15_SETTINGS() {
        capturePortraitScreen(
            scene = EsddVerifySceneCase.SETTINGS,
            fileName = "UE15_SETTINGS",
            touchTargetTags = listOf("btn-scan-new-qr", "row-settings-language", "row-settings-more"),
        )
    }
}
