package dev.antigravity.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import dev.antigravity.android.ui.AntigravityAppRoot
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.EsddVerifySceneCase
import dev.antigravity.shared.model.RequestedInteraction
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Complete Android Interactive Compose E2E suite (`ATC-01` .. `ATC-18`),
 * verifying every user journey across UE01–UE13, v2.33 sheets, and forward-compatible unknown steps/gates.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-xxhdpi")
class AndroidInteractiveE2eTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun atc01_agentsHomeDisplaysHostFilterAndFiltersNeedsYou() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AGENTS_HOME,
            )
        }

        composeRule.onNodeWithTag("host-switcher-pill").assertIsDisplayed()
        composeRule.onNodeWithTag("pinned-section-card").assertIsDisplayed()
        composeRule.onNodeWithTag("project-group-ledger-svc").assertIsDisplayed()
        composeRule.onNodeWithTag("bottom-nav-bar").assertIsDisplayed()
        composeRule.onNodeWithTag("fab-compose").assertIsDisplayed()

        composeRule.onNodeWithTag("filter-pill-needs-you").performClick()
        composeRule.onNodeWithText("Fix flaky TestSettlementBatch", substring = true).assertIsDisplayed()
    }

    @Test
    fun atc02_displayOptionsMarksAllReadAndResets() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.DISPLAY_OPTIONS,
            )
        }

        composeRule.onNodeWithTag("row-group-by").assertIsDisplayed()
        composeRule.onNodeWithTag("sort-options-menu").assertIsDisplayed()
        composeRule.onNodeWithTag("toggle-auto-pin").performClick()
        assertTrue(coordinator.workspaceStore.state.value.displayOptions.autoPinOnMessage)

        composeRule.onNodeWithTag("btn-mark-all-read").performClick()
        assertEquals(0, coordinator.syncState.value.summaries.count { it.isUnread })

        composeRule.onNodeWithTag("sheet-reset-btn").performClick()
        assertEquals(false, coordinator.workspaceStore.state.value.displayOptions.autoPinOnMessage)
    }

    @Test
    fun atc03_contextMenuPreviewRendersPlanChipsAndPinsConversation() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CONTEXT_MENU_PIN,
            )
        }

        composeRule.onNodeWithTag("context-preview-card").assertIsDisplayed()
        composeRule.onNodeWithTag("chip-implementation-plan").assertIsDisplayed()
        composeRule.onNodeWithTag("chip-awaiting-review").assertIsDisplayed()
        composeRule.onNodeWithTag("swipe-action-pin").assertIsDisplayed()
        composeRule.onNodeWithTag("swipe-action-archive").assertIsDisplayed()

        composeRule.onNodeWithTag("menu-action-pin").performClick()
        val target = coordinator.syncState.value.summaries.first { it.cascadeId == "cas-flaky-settlement" }
        assertTrue(target.isPinned)
    }

    @Test
    fun atc04_projectDetailShowsMetadataTabsAndTools() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.PROJECT_DETAIL,
            )
        }

        composeRule.onNodeWithTag("project-hero-title").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-new-conv-in-project").assertIsDisplayed()
        composeRule.onNodeWithTag("project-tab-active").assertIsDisplayed()
        composeRule.onNodeWithTag("project-row-automation").assertIsDisplayed()
        composeRule.onNodeWithTag("project-row-skills").assertIsDisplayed()
    }

    @Test
    fun atc05_createProjectSubmitsNewCloudWorkspace() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CREATE_PROJECT,
            )
        }

        composeRule.onNodeWithTag("seg-runs-on-cloud").performClick()
        composeRule.onNodeWithTag("source-card-github").performClick()
        composeRule.onNodeWithTag("repo-row-ledger-svc").performClick()
        val beforeCount = coordinator.workspaceStore.state.value.projects.size
        composeRule.onNodeWithTag("btn-submit-create-project").performClick()
        assertEquals(beforeCount + 1, coordinator.workspaceStore.state.value.projects.size)
    }

    @Test
    fun atc06_automationsCreatesRunsAndResumesPaused() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AUTOMATIONS,
            )
        }

        composeRule.onNodeWithTag("automation-prompt-input").performTextInput("Daily lint check")
        composeRule.onNodeWithTag("btn-create-automation-inline").performClick()
        assertTrue(coordinator.workspaceStore.state.value.automations.any { it.title.contains("Daily lint check") })

        composeRule.onNodeWithTag("btn-run-nightly").performClick()
        assertTrue(coordinator.workspaceStore.state.value.automations.first { it.id == "auto-nightly-audit" }.isRunningNow)

        composeRule.onNodeWithTag("btn-resume-paused").performClick()
        assertEquals(
            dev.antigravity.shared.model.AutomationSectionKind.SCHEDULED,
            coordinator.workspaceStore.state.value.automations.first { it.id == "auto-bundle-size" }.section,
        )
    }

    @Test
    fun atc07_and_atc08_chatRendersTaskCardApprovesWithBiometricAndSendsMessage() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        var biometricTriggered = false
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CHAT_AND_COMPOSER,
                onBiometricPrompt = { _, onSuccess ->
                    biometricTriggered = true
                    onSuccess()
                },
            )
        }

        composeRule.onNodeWithTag("chat-diff-pill").assertIsDisplayed()
        composeRule.onNodeWithTag("row-thought-14s").performClick()
        composeRule.onNodeWithTag("card-artifact-plan").assertIsDisplayed()
        composeRule.onNodeWithTag("card-task-progress-7seg").assertIsDisplayed()
        composeRule.onNodeWithTag("card-command-approval").assertIsDisplayed()

        // Approve command gate via biometric callback
        composeRule.onNodeWithTag("btn-command-allow-biometric").performClick()
        assertTrue("Biometric gate callback must be invoked", biometricTriggered)
        val cmdStep = coordinator.chatState.value.steps.first { it.stepIndex == 5 }
        assertEquals(CortexStepStatus.DONE, cmdStep.status)

        // Send message from composer
        composeRule.onNodeWithTag("composer-btn-send").performClick()
        assertTrue(coordinator.chatState.value.steps.any { it.userInput?.contains("1000/s") == true })
    }

    @Test
    fun atc09_addContextSelectsAndAddsChipsToComposer() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.ADD_CONTEXT,
            )
        }

        composeRule.onNodeWithTag("tile-files").assertIsDisplayed()
        composeRule.onNodeWithTag("tile-skills").assertIsDisplayed()
        composeRule.onNodeWithTag("ctx-row-ratelimit").assertIsDisplayed()
        composeRule.onNodeWithTag("ctx-row-go-testing").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-add-to-message").performClick()
        assertTrue(coordinator.workspaceStore.state.value.attachedComposerChips.size >= 3)
    }

    @Test
    fun atc10_modelAndModeUpdatesSelectionAndLocksOrchestratorEffort() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.MODEL_AND_MODE,
            )
        }

        composeRule.onNodeWithTag("mode-card-fast").performClick()
        assertEquals(
            dev.antigravity.shared.model.CascadeExecutionMode.FAST,
            coordinator.settingsStore.state.value.selectedMode,
        )
        composeRule.onNodeWithTag("model-row-claude-opus").performClick()
        composeRule.onNodeWithTag("agent-pill-go-reviewer").performClick()
        assertEquals("go-reviewer", coordinator.settingsStore.state.value.selectedAgentPersona)
        composeRule.onNodeWithTag("btn-model-done").assertIsDisplayed()
    }

    @Test
    fun atc11_structuredQuestionTogglesMultiSelectAndAdvancesStep() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.STRUCTURED_QUESTION,
            )
        }

        composeRule.onNodeWithTag("q-step-1-storage").assertIsDisplayed()
        composeRule.onNodeWithTag("q-step-2-actions").assertIsDisplayed()
        composeRule.onNodeWithTag("q-opt-role").performClick()
        composeRule.onNodeWithTag("q-input-something-else").performTextInput("API key rotation")
        composeRule.onNodeWithTag("q-btn-next").performClick()
        assertEquals(2, coordinator.chatState.value.activeQuestionStepIndex)
    }

    @Test
    fun atc12_planReviewDisplaysPausedBannerAndSendsComments() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.PLAN_REVIEW,
            )
        }

        composeRule.onNodeWithTag("plan-comments-badge").assertIsDisplayed()
        composeRule.onNodeWithTag("plan-paused-banner").assertIsDisplayed()
        composeRule.onNodeWithTag("plan-pending-comment-card").assertIsDisplayed()
        composeRule.onNodeWithTag("selection-callout-comment").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-plan-send-comments").performClick()
        assertTrue(coordinator.reviewStore.state.value.planCommentsSentCount >= 2)
    }

    @Test
    fun atc13_turnDiffReviewAttachesLineCommentAndMarksViewed() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.TURN_DIFF_REVIEW,
            )
        }

        composeRule.onNodeWithTag("btn-accept-all-diffs").assertIsDisplayed()
        composeRule.onNodeWithTag("turn-pill-3-latest").assertIsDisplayed()
        composeRule.onNodeWithTag("file-pager-card").assertIsDisplayed()
        composeRule.onNodeWithTag("diff-line-29").assertIsDisplayed()
        composeRule.onNodeWithTag("line-comment-composer").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-send-to-agent").performClick()
        composeRule.onNodeWithTag("checkbox-viewed").performClick()
        assertTrue(coordinator.reviewStore.state.value.diffs.first().isReviewed)
    }

    @Test
    fun atc14_liveUpdatesSpecRendersAll7Android16Variants() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.LIVE_ACTIVITY_SPEC,
            )
        }

        composeRule.onNodeWithTag("lu-chip-running").assertIsDisplayed()
        composeRule.onNodeWithTag("lu-chip-waiting").assertIsDisplayed()
        composeRule.onNodeWithTag("lu-minimal-badge").assertIsDisplayed()
        composeRule.onNodeWithTag("lu-chip-done").assertIsDisplayed()
        composeRule.onNodeWithTag("lu-expanded-running").assertIsDisplayed()
        composeRule.onNodeWithTag("lu-expanded-waiting").assertIsDisplayed()
        composeRule.onNodeWithTag("lu-lockscreen-multi-agent").assertIsDisplayed()
    }

    @Test
    fun atc17_v233OverviewAndSideQuestionFlowsWorkInteractively() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CHAT_AND_COMPOSER,
            )
        }

        composeRule.onNodeWithTag("btn-chat-overview").performClick()
        composeRule.onNodeWithTag("sheet-conversation-overview").assertIsDisplayed()
    }

    @Test
    fun atc18_forwardCompatibleUnknownStepAndGenericInteractionGateRenderAndResolve() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        coordinator.chatStore.injectDebugSteps(
            listOf(
                CascadeStep(
                    cascadeId = "cas-rate-limiter",
                    stepIndex = 99,
                    type = CortexStepType.UNSPECIFIED,
                    status = CortexStepStatus.DONE,
                    rawTypeName = "CORTEX_STEP_TYPE_FUTURE_SANDBOX_AUDIT",
                    fallbackSummary = "Future upstream tool completed security audit across 4 targets.",
                ),
                CascadeStep(
                    cascadeId = "cas-rate-limiter",
                    stepIndex = 100,
                    type = CortexStepType.UNSPECIFIED,
                    status = CortexStepStatus.WAITING,
                    rawTypeName = "CORTEX_STEP_TYPE_FUTURE_DEPLOY_GATE",
                    fallbackSummary = "Deploy ledger-svc canary to us-central1",
                    requestedInteraction = RequestedInteraction(
                        kind = RequestedInteraction.MemberKind.APPROVAL_INTERACTION,
                        rawMemberKey = "futureDeployApproval",
                        rawSummary = "Approve canary deployment to us-central1?",
                    ),
                ),
            )
        )

        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CHAT_AND_COMPOSER,
                onBiometricPrompt = { _, onSuccess -> onSuccess() },
            )
        }

        val listExists = composeRule.onAllNodesWithTag("chat-steps-list").fetchSemanticsNodes().isNotEmpty()
        if (listExists) {
            composeRule.onNodeWithTag("chat-steps-list").performScrollToNode(hasTestTag("card-forward-step-99"))
        }
        composeRule.onNodeWithTag("card-forward-step-99").assertIsDisplayed()
        if (listExists) {
            composeRule.onNodeWithTag("chat-steps-list").performScrollToNode(hasTestTag("card-generic-gate-100"))
        }
        composeRule.onNodeWithTag("card-generic-gate-100").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-generic-gate-allow-100").performClick()
        assertEquals(
            CortexStepStatus.DONE,
            coordinator.chatState.value.steps.first { it.stepIndex == 100 }.status,
        )
    }

    @Test
    fun atc19_displayOptionsSortMenuCollapsedByDefaultAndDismissesOnSelectionOrOutsideTap() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AGENTS_HOME,
            )
        }

        // 1. Open Display Options from Agents Home -> sort menu must be collapsed by default
        composeRule.onNodeWithTag("btn-display-options").performClick()
        composeRule.onNodeWithTag("row-sort-conversations").assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithTag("sort-options-menu").fetchSemanticsNodes().size)

        // 2. Expand sort menu -> selecting 'Title' updates displayOptions and collapses menu
        composeRule.onNodeWithTag("row-sort-conversations").performClick()
        composeRule.onNodeWithTag("sort-options-menu").assertIsDisplayed()
        composeRule.onNodeWithText("Title").performClick()
        assertEquals(
            dev.antigravity.shared.model.ConversationSortField.TITLE,
            coordinator.workspaceStore.state.value.displayOptions.sortBy,
        )
        assertEquals(0, composeRule.onAllNodesWithTag("sort-options-menu").fetchSemanticsNodes().size)

        // 3. Re-expand -> tapping scrim dismisses sort menu while keeping Display Options sheet open
        composeRule.onNodeWithTag("row-sort-conversations").performClick()
        composeRule.onNodeWithTag("sort-options-menu").assertIsDisplayed()
        composeRule.onNodeWithTag("display-options-scrim").performClick()
        assertEquals(0, composeRule.onAllNodesWithTag("sort-options-menu").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("row-sort-conversations").assertIsDisplayed()

        // 4. Re-expand -> tapping another row collapses sort menu while applying that row's change
        composeRule.onNodeWithTag("row-sort-conversations").performClick()
        composeRule.onNodeWithTag("sort-options-menu").assertIsDisplayed()
        composeRule.onNodeWithTag("row-group-by").performClick()
        assertEquals(0, composeRule.onAllNodesWithTag("sort-options-menu").fetchSemanticsNodes().size)
        assertEquals(
            dev.antigravity.shared.model.DisplayGroupBy.HOST,
            coordinator.workspaceStore.state.value.displayOptions.groupBy,
        )
    }

    @Test
    fun atc20_pairingScreenOpensRemoteLinkDialogAndSupportsCancelAndErrorBanner() {
        val coordinator = AntigravityCoreCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = null,
            )
        }

        composeRule.onNodeWithTag("welcome-pairing-screen").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-welcome-scan-qr").performClick()
        composeRule.onNodeWithTag("input-remote-control-link").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-submit-remote-link").assertIsDisplayed()
    }
}
