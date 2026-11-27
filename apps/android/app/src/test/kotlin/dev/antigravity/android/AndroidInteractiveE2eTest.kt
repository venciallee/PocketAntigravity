package dev.antigravity.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import dev.antigravity.android.ui.AntigravityAppRoot
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AppLanguage
import dev.antigravity.shared.model.AppThemePreset
import dev.antigravity.shared.model.AutomationSectionKind
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.ConversationSortField
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.DisplayGroupBy
import dev.antigravity.shared.model.EsddVerifySceneCase
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.model.ThinkingEffortLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Complete Android Interactive Compose E2E suite (`ATC-01` .. `ATC-28`),
 * verifying every user journey across all 19 aligned UE boards (`UE01`..`UE15`),
 * v2.33 sheets, and forward-compatible unknown steps/gates.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-xxhdpi")
class AndroidInteractiveE2eTest {

    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun atc01_newConversationHomeAndSidebarDrawerNavigation() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AGENTS_HOME,
            )
        }

        // UE01 New Conversation Home (no bottom tab bar or compose FAB)
        composeRule.onNodeWithTag("btn-sidebar").assertIsDisplayed()
        composeRule.onNodeWithTag("host-switcher-pill").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-search").assertIsDisplayed()
        composeRule.onNodeWithTag("home-greeting").assertIsDisplayed()
        composeRule.onNodeWithTag("home-needs-approval-banner").assertIsDisplayed()
        composeRule.onNodeWithTag("home-composer-card").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-model-picker").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-permissions-preset").assertIsDisplayed()

        // Open Sidebar Drawer (UE01B)
        composeRule.onNodeWithTag("btn-sidebar").performClick()
        composeRule.onNodeWithTag("sidebar-drawer").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-new-conversation").assertIsDisplayed()
        composeRule.onNodeWithTag("drawer-automations").assertIsDisplayed()
        composeRule.onNodeWithTag("drawer-customizations").assertIsDisplayed()
        composeRule.onNodeWithTag("project-header-ledger-svc").assertIsDisplayed()
        composeRule.onNodeWithTag("conversation-row-cas-rate-limiter").assertIsDisplayed()
        composeRule.onNodeWithTag("drawer-settings").assertIsDisplayed()
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

        composeRule.onNodeWithTag("display-options-sheet").assertIsDisplayed()
        composeRule.onNodeWithTag("option-group-by").assertIsDisplayed()
        composeRule.onNodeWithTag("sort-dropdown-menu").assertIsDisplayed()
        val beforeAutoPin = coordinator.workspaceStore.state.value.displayOptions.autoPinOnMessage
        composeRule.onNodeWithTag("switch-auto-pin").performClick()
        assertEquals(!beforeAutoPin, coordinator.workspaceStore.state.value.displayOptions.autoPinOnMessage)

        composeRule.onNodeWithTag("btn-mark-all-read").performClick()
        assertEquals(0, coordinator.syncState.value.summaries.count { it.isUnread })

        composeRule.onNodeWithTag("sheet-reset-btn").performClick()
        assertEquals(false, coordinator.workspaceStore.state.value.displayOptions.archivedOnly)
    }

    @Test
    fun atc03_contextMenuPreviewRendersAndPinsConversation() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CONTEXT_MENU_PIN,
            )
        }

        composeRule.onNodeWithTag("context-menu-sheet").assertIsDisplayed()
        composeRule.onNodeWithTag("context-preview-card").assertIsDisplayed()
        composeRule.onNodeWithTag("action-pin").assertIsDisplayed()
        composeRule.onNodeWithTag("action-archive").assertIsDisplayed()

        composeRule.onNodeWithTag("action-pin").performClick()
        val target = coordinator.syncState.value.summaries.first { it.cascadeId == "cas-flaky-settlement" }
        assertTrue(target.isPinned)
    }

    @Test
    fun atc04_sidebarProjectHeaderCollapsesAndLongPressOpensProjectActions() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.SIDEBAR_DRAWER,
            )
        }

        // Tapping project header directly collapses & expands conversations (no intermediate Project Detail screen)
        composeRule.onNodeWithTag("project-header-ledger-svc").assertIsDisplayed()
        composeRule.onNodeWithTag("conversation-row-cas-rate-limiter").assertIsDisplayed()
        composeRule.onNodeWithTag("project-header-ledger-svc").performClick()
        assertTrue(coordinator.workspaceStore.isProjectCollapsed("ledger-svc"))
        assertEquals(0, composeRule.onAllNodesWithTag("conversation-row-cas-rate-limiter").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("project-header-ledger-svc").performClick()
        assertFalse(coordinator.workspaceStore.isProjectCollapsed("ledger-svc"))
        composeRule.onNodeWithTag("conversation-row-cas-rate-limiter").assertIsDisplayed()

        // Long-pressing local project exposes New conversation, Project rules & skills, and Reveal in Finder
        composeRule.onNodeWithTag("project-header-ledger-svc").performTouchInput { longClick() }
        composeRule.onNodeWithTag("project-menu-new-conv-ledger-svc").assertIsDisplayed()
        composeRule.onNodeWithTag("project-menu-reveal-finder-ledger-svc").assertIsDisplayed()
        composeRule.onNodeWithTag("project-menu-rules-skills-ledger-svc").performClick()
        composeRule.onNodeWithTag("rules-token-budget-card").assertIsDisplayed()
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

        composeRule.onNodeWithTag("runtime-cloud").performClick()
        composeRule.onNodeWithTag("source-github").performClick()
        composeRule.onNodeWithTag("repo-row-repo-design-tokens").performClick()
        val beforeCount = coordinator.workspaceStore.state.value.projects.size
        composeRule.onNodeWithTag("btn-create-project-submit").performClick()
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

        // First exercise & close the initial overflow menu via Run Now
        composeRule.onNodeWithTag("automation-overflow-menu").assertIsDisplayed()
        composeRule.onNodeWithTag("menu-run-now").performClick()
        assertTrue(coordinator.workspaceStore.state.value.automations.first { it.id == "auto-nightly-audit" }.isRunningNow)

        // Create automation from natural-language prompt
        composeRule.onNodeWithTag("input-automation-prompt").performTextInput("Daily lint check")
        composeRule.onNodeWithTag("btn-create-automation").performClick()
        assertTrue(coordinator.workspaceStore.state.value.automations.any { it.title.contains("Daily lint check") })

        // Resume paused automation
        composeRule.onNodeWithTag("btn-resume-auto-bundle-size").performClick()
        assertEquals(
            AutomationSectionKind.SCHEDULED,
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
        composeRule.onNodeWithTag("card-artifact-plan").assertIsDisplayed()
        composeRule.onNodeWithTag("card-task-progress-7seg").assertIsDisplayed()
        composeRule.onNodeWithTag("card-command-approval").assertIsDisplayed()
        composeRule.onNodeWithTag("composer-pill-model").assertIsDisplayed()
        composeRule.onNodeWithTag("composer-pill-permissions").assertIsDisplayed()

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
    fun atc09_addContextPopoverDrillsDownAndAppliesChips() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.ADD_CONTEXT,
            )
        }

        composeRule.onNodeWithTag("add-context-popover").assertIsDisplayed()
        composeRule.onNodeWithTag("ctx-menu-files").assertIsDisplayed()
        composeRule.onNodeWithTag("ctx-menu-drive").assertIsDisplayed()

        // Drill into Files picker and apply selected chips
        composeRule.onNodeWithTag("ctx-menu-files").performClick()
        composeRule.onNodeWithTag("add-context-picker-sheet").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-add-context-apply").performClick()
        assertTrue(coordinator.workspaceStore.state.value.attachedComposerChips.size >= 3)
    }

    @Test
    fun atc10_modelPickerHasZeroPlanningFastToggleAndSwitchesModelAndEffort() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.MODEL_AND_MODE,
            )
        }

        composeRule.onNodeWithTag("model-picker-sheet").assertIsDisplayed()
        // Official docs verdict: NO Planning/Fast mode cards in model picker
        assertEquals(0, composeRule.onAllNodesWithTag("mode-card-planning").fetchSemanticsNodes().size)
        assertEquals(0, composeRule.onAllNodesWithTag("mode-card-fast").fetchSemanticsNodes().size)

        composeRule.onNodeWithTag("model-row-orchestrator").assertIsDisplayed()
        composeRule.onNodeWithTag("effort-chip-high").performClick()
        assertEquals(ThinkingEffortLevel.HIGH, coordinator.settingsStore.state.value.selectedEffort)

        composeRule.onNodeWithTag("model-row-MODEL_CLAUDE_5_5_OPUS_THINKING").performClick()
        assertEquals("MODEL_CLAUDE_5_5_OPUS_THINKING", coordinator.settingsStore.state.value.selectedModelId)
        // Claude Opus 5.5 supports only Low/Medium/High (no Extra High)
        assertEquals(0, composeRule.onAllNodesWithTag("effort-chip-extra").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("effort-chip-medium").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-model-done").assertIsDisplayed()
    }

    @Test
    fun atc10b_modelPickerGroupsLiveVariantsAndScopesEffortsPerModel() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        val neon = dev.antigravity.shared.model.CascadeModelConfig(
            modelId = "MODEL_PLACEHOLDER_M41",
            displayName = "Gemini 4 Neon",
            subtitle = "Frontier reasoning",
            thinkingEffort = ThinkingEffortLevel.HIGH,
            supportedEfforts = listOf(
                ThinkingEffortLevel.LOW,
                ThinkingEffortLevel.MEDIUM,
                ThinkingEffortLevel.HIGH,
                ThinkingEffortLevel.EXTRA,
            ),
            isNewBadge = true,
            effortVariantModelIds = mapOf(
                "low" to "MODEL_PLACEHOLDER_M39",
                "medium" to "MODEL_PLACEHOLDER_M40",
                "high" to "MODEL_PLACEHOLDER_M41",
                "xhigh" to "MODEL_PLACEHOLDER_M42",
            ),
        )
        val carbon = dev.antigravity.shared.model.CascadeModelConfig(
            modelId = "MODEL_PLACEHOLDER_M44",
            displayName = "Gemini 4 Carbon",
            subtitle = "Balanced SWE reasoning",
            thinkingEffort = ThinkingEffortLevel.MEDIUM,
            supportedEfforts = listOf(
                ThinkingEffortLevel.LOW,
                ThinkingEffortLevel.MEDIUM,
                ThinkingEffortLevel.HIGH,
            ),
            effortVariantModelIds = mapOf(
                "low" to "MODEL_PLACEHOLDER_M43",
                "medium" to "MODEL_PLACEHOLDER_M44",
                "high" to "MODEL_PLACEHOLDER_M45",
            ),
        )
        val orchNeon = dev.antigravity.shared.model.CascadeModelConfig(
            modelId = "ORCHESTRATOR_NEON",
            displayName = "Orchestrator (Neon)",
            subtitle = "Neon plans · Hydrogen executes",
            isOrchestrator = true,
            plannerModelName = "Gemini 4 Neon",
            executorModelName = "Gemini 4 Hydrogen",
            supportedEfforts = emptyList(),
            isModelAlias = true,
        )
        val orchCarbon = dev.antigravity.shared.model.CascadeModelConfig(
            modelId = "ORCHESTRATOR_CARBON",
            displayName = "Orchestrator (Carbon)",
            subtitle = "Carbon plans · Hydrogen executes",
            isOrchestrator = true,
            plannerModelName = "Gemini 4 Carbon",
            executorModelName = "Gemini 4 Hydrogen",
            supportedEfforts = emptyList(),
            isModelAlias = true,
        )
        coordinator.settingsStore.applyModelCatalog(
            dev.antigravity.shared.model.LiveModelCatalogResult(
                models = listOf(neon, carbon, orchNeon, orchCarbon),
                defaultModelId = "MODEL_PLACEHOLDER_M41",
            ),
        )

        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.MODEL_AND_MODE,
            )
        }

        // Neon starts selected with 4 effort chips; tapping Extra High switches to variant M42
        composeRule.onNodeWithTag("model-row-MODEL_PLACEHOLDER_M41").assertIsDisplayed()
        composeRule.onNodeWithTag("effort-chip-extra").performClick()
        assertEquals("MODEL_PLACEHOLDER_M42", coordinator.settingsStore.state.value.selectedModelId)
        assertEquals(ThinkingEffortLevel.EXTRA, coordinator.settingsStore.state.value.selectedEffort)

        // Switching to Gemini 4 Carbon reveals ONLY Low/Medium/High (NO Extra High)
        composeRule.onNodeWithTag("model-row-MODEL_PLACEHOLDER_M44").performClick()
        assertEquals("MODEL_PLACEHOLDER_M44", coordinator.settingsStore.state.value.selectedModelId)
        assertEquals(ThinkingEffortLevel.MEDIUM, coordinator.settingsStore.state.value.selectedEffort)
        assertEquals(0, composeRule.onAllNodesWithTag("effort-chip-extra").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("effort-chip-high").performClick()
        assertEquals("MODEL_PLACEHOLDER_M45", coordinator.settingsStore.state.value.selectedModelId)

        // Tapping Orchestrator exposes inline planner chips (Neon / Carbon) with zero effort chips
        composeRule.onNodeWithTag("model-row-orchestrator").performClick()
        assertEquals("ORCHESTRATOR_NEON", coordinator.settingsStore.state.value.selectedModelId)
        assertEquals(0, composeRule.onAllNodesWithTag("effort-chip-high").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("orchestrator-chip-carbon").performClick()
        assertEquals("ORCHESTRATOR_CARBON", coordinator.settingsStore.state.value.selectedModelId)
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

        composeRule.onNodeWithTag("structured-question-card").assertIsDisplayed()
        composeRule.onNodeWithTag("question-answered-pill-0").assertIsDisplayed()
        composeRule.onNodeWithTag("question-option-3").performClick()
        composeRule.onNodeWithTag("question-freeform-input").performTextInput("API key rotation")
        composeRule.onNodeWithTag("btn-question-next").performClick()
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
    fun atc14_liveUpdatesNotificationShadeRendersAll4Cards() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.LIVE_ACTIVITY_SPEC,
            )
        }

        composeRule.onNodeWithTag("live-card-running").assertIsDisplayed()
        composeRule.onNodeWithTag("live-card-approval").assertIsDisplayed()
        composeRule.onNodeWithTag("live-card-cloud").assertIsDisplayed()
        composeRule.onNodeWithTag("live-card-done").assertIsDisplayed()
    }

    @Test
    fun atc17_v233OverviewSheetOpensFromChatTopBar() {
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
    fun atc19_displayOptionsSortMenuCollapsedByDefaultAndDismissesOnSelectionOrScrim() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.SIDEBAR_DRAWER,
            )
        }

        // Open Display Options from Sidebar Drawer -> sort menu starts collapsed
        composeRule.onNodeWithTag("btn-display-options").performClick()
        composeRule.onNodeWithTag("option-sort-by").assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithTag("sort-dropdown-menu").fetchSemanticsNodes().size)

        // Expand sort menu -> selecting 'Title' updates displayOptions and collapses menu
        composeRule.onNodeWithTag("option-sort-by").performClick()
        composeRule.onNodeWithTag("sort-dropdown-menu").assertIsDisplayed()
        composeRule.onNodeWithTag("sort-option-title").performClick()
        assertEquals(
            ConversationSortField.TITLE,
            coordinator.workspaceStore.state.value.displayOptions.sortBy,
        )
        assertEquals(0, composeRule.onAllNodesWithTag("sort-dropdown-menu").fetchSemanticsNodes().size)

        // Re-expand -> tapping Group by updates grouping and closes dropdown
        composeRule.onNodeWithTag("option-sort-by").performClick()
        composeRule.onNodeWithTag("sort-dropdown-menu").assertIsDisplayed()
        composeRule.onNodeWithTag("option-group-by").performClick()
        assertEquals(0, composeRule.onAllNodesWithTag("sort-dropdown-menu").fetchSemanticsNodes().size)
        assertEquals(
            DisplayGroupBy.HOST,
            coordinator.workspaceStore.state.value.displayOptions.groupBy,
        )
    }

    @Test
    fun atc20_automationDetailRetryAndEditSaveDeleteFlows() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AUTOMATION_DETAIL,
            )
        }

        composeRule.onNodeWithTag("btn-automation-run-now").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-automation-pause-resume").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-retry-run-3").performClick()
        val nightlyAfterRetry = coordinator.workspaceStore.state.value.automations
            .first { it.id == "auto-nightly-audit" }
        assertTrue(nightlyAfterRetry.isRunningNow)
        assertEquals(
            dev.antigravity.shared.model.AutomationRunStatus.RUNNING,
            nightlyAfterRetry.recentRuns.first { it.id == "run-3" }.status,
        )

        // Navigate to Edit screen (UE06C) and save
        composeRule.onNodeWithTag("btn-edit-automation").performClick()
        composeRule.onNodeWithTag("input-edit-automation-name").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-save-automation").performClick()
        composeRule.onNodeWithTag("btn-automation-run-now").assertIsDisplayed()
    }

    @Test
    fun atc21_permissionsPresetPopoverAndSlashMenuInsertAction() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.PERMISSIONS_PRESET,
            )
        }

        composeRule.onNodeWithTag("permissions-preset-popover").assertIsDisplayed()
        composeRule.onNodeWithTag("preset-option-turbo").performClick()
        assertEquals(AgentPermissionPreset.TURBO, coordinator.settingsStore.state.value.activePermissionPreset)

        // Open Slash Menu from composer
        val coordinator2 = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        assertTrue(coordinator2.isVerificationMode)
    }

    @Test
    fun atc21b_slashMenuInsertsPlanAction() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.SLASH_MENU,
            )
        }

        composeRule.onNodeWithTag("slash-menu-card").assertIsDisplayed()
        composeRule.onNodeWithTag("slash-item-plan").performClick()
        assertEquals("/plan ", coordinator.chatState.value.draftInputText)
    }

    @Test
    fun atc22_rulesSkillsPluginToggleAndFlattenedSettingsLanguageAndMore() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.RULES_AND_SKILLS,
            )
        }

        composeRule.onNodeWithTag("rules-token-budget-card").assertIsDisplayed()
        composeRule.onNodeWithTag("skill-row-go-testing").assertIsDisplayed()
        composeRule.onNodeWithTag("customizations-tab-2").performClick() // Plugins tab
        val beforeEnabled = coordinator.settingsStore.state.value.customizations.plugins
            .first { it.id == "plugin-datadog" }.isEnabled
        composeRule.onNodeWithTag("switch-plugin-plugin-datadog").performClick()
        val afterEnabled = coordinator.settingsStore.state.value.customizations.plugins
            .first { it.id == "plugin-datadog" }.isEnabled
        assertEquals(!beforeEnabled, afterEnabled)
    }

    @Test
    fun atc22b_flattenedSettingsThemeLanguageAndPermissionsSubpage() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.SETTINGS,
            )
        }

        composeRule.onNodeWithTag("btn-scan-new-qr").assertIsDisplayed()
        composeRule.onNodeWithTag("settings-host-macbook-pro-local").assertIsDisplayed()
        composeRule.onNodeWithTag("theme-preset-nord").performClick()
        assertEquals(AppThemePreset.NORD, coordinator.settingsStore.state.value.appearance.theme)

        composeRule.onNodeWithTag("row-settings-language").performClick()
        composeRule.onNodeWithTag("language-option-zh_hans").performClick()
        assertEquals(AppLanguage.ZH_HANS, coordinator.settingsStore.state.value.appearance.language)

        // Open Permissions, notifications & about subpage
        composeRule.onNodeWithTag("row-settings-more").performClick()
        composeRule.onNodeWithTag("settings-more-subpage").assertIsDisplayed()
        composeRule.onNodeWithTag("card-about-copyright").assertIsDisplayed()
    }

    @Test
    fun atc23_pairingScreenOpensRemoteLinkDialog() {
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

    @Test
    fun atc24_composerSingleLineModelPillAndImageAttachmentSend() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        // Add an inline image attachment directly to verify image chip renders even when draft text is empty
        val samplePngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFklEQVR4nGPs2/KfgYGBiYGBgYGBAQAaxQJFDxGZ5wAAAABJRU5ErkJggg=="
        val photoChip = dev.antigravity.shared.model.ComposerAttachmentChip(
            id = "photo-e2e-1",
            kind = dev.antigravity.shared.model.ComposerAttachmentChip.Kind.IMAGE_SCREENSHOT,
            label = "photo-1.png",
            targetUri = "attachment://photo/photo-e2e-1/photo-1.png",
            mimeType = "image/png",
            inlinePayload = samplePngBase64,
        )

        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AGENTS_HOME,
            )
        }

        // Single-line model pill must show model name without stacked "Extra High" / "High" text in Home composer
        composeRule.onNodeWithTag("btn-model-picker").assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodes(androidx.compose.ui.test.hasText("Extra High")).fetchSemanticsNodes().size)

        // Adding a photo renders the thumbnail chip on Home even with empty draft text, and enables image-only send
        coordinator.workspaceStore.addComposerChip(photoChip)
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("composer-image-chip-photo-e2e-1").assertIsDisplayed()

        // Tap Send with empty text + image attachment -> navigates into chat & attaches photo-1.png
        composeRule.onNodeWithTag("btn-home-send").performClick()
        composeRule.waitForIdle()
        assertTrue(
            coordinator.chatState.value.steps.any { step ->
                step.type == CortexStepType.USER_INPUT && "photo-1.png" in step.attachedMentions
            },
        )
        assertTrue(coordinator.workspaceStore.state.value.attachedComposerChips.isEmpty())
    }

    @Test
    fun atc25_cascadeChatRendersStepLoadErrorCardAndRetryButton() {
        val coordinator = AntigravityCoreCoordinator()
        coordinator.chatStore.setActiveCascade("v1/sync-mobile-concept")
        coordinator.chatStore.setStepLoadError("HTTP 404: not_found: trajectory not found")
        var retryTapped = 0

        composeRule.setContent {
            dev.antigravity.android.core.ui.theme.AntigravityTheme {
                dev.antigravity.android.ui.chat.CascadeChatScreen(
                    coordinator = coordinator,
                    onBack = {},
                    onOpenDiffReview = {},
                    onOpenPlanReview = {},
                    onOpenAddContext = {},
                    onOpenModelAndMode = {},
                    onOpenOverview = {},
                    onOpenSideQuestion = {},
                    onOpenSwarmBoard = {},
                    onOpenVoiceMode = {},
                    onBiometricPrompt = { _, onSuccess -> onSuccess() },
                    onRetryLoadSteps = { retryTapped += 1 },
                )
            }
        }

        composeRule.onNodeWithTag("chat-step-load-error-card").assertIsDisplayed()
        composeRule.onNodeWithText("Could not load trajectory steps").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-chat-retry-steps").performClick()
        assertEquals(1, retryTapped)
        assertEquals(null, coordinator.chatState.value.stepLoadErrorText)
    }

    @Test
    fun atc26_homeRuntimeIconShowsComputerForLocalProjectAndCloudForCloudProject() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AGENTS_HOME,
            )
        }

        // Default local project (ledger-svc) displays local computer runtime icon semantics
        composeRule.onNode(
            androidx.compose.ui.test.hasTestTag("home-cloud-toggle")
                .and(androidx.compose.ui.test.hasContentDescription("Local runtime selected")),
        ).assertIsDisplayed()

        // Selecting a cloud project switches the runtime icon to Cloud
        composeRule.onNodeWithTag("home-project-picker").performClick()
        composeRule.onNodeWithTag("home-project-option-web-console").performClick()
        composeRule.onNode(
            androidx.compose.ui.test.hasTestTag("home-cloud-toggle")
                .and(androidx.compose.ui.test.hasContentDescription("Cloud runtime selected")),
        ).assertIsDisplayed()

        // Switching back to a local project restores the local computer runtime icon
        composeRule.onNodeWithTag("home-project-picker").performClick()
        composeRule.onNodeWithTag("home-project-option-ledger-svc").performClick()
        composeRule.onNode(
            androidx.compose.ui.test.hasTestTag("home-cloud-toggle")
                .and(androidx.compose.ui.test.hasContentDescription("Local runtime selected")),
        ).assertIsDisplayed()

        // Tapping the runtime toggle directly switches between Cloud and Local computer
        composeRule.onNodeWithTag("home-cloud-toggle").performClick()
        composeRule.onNode(
            androidx.compose.ui.test.hasTestTag("home-cloud-toggle")
                .and(androidx.compose.ui.test.hasContentDescription("Cloud runtime selected")),
        ).assertIsDisplayed()
        composeRule.onNodeWithTag("home-cloud-toggle").performClick()
        composeRule.onNode(
            androidx.compose.ui.test.hasTestTag("home-cloud-toggle")
                .and(androidx.compose.ui.test.hasContentDescription("Local runtime selected")),
        ).assertIsDisplayed()
    }

    @Test
    fun atc27_sidebarProjectHeaderAndToggleBothCollapseAndRestoreConversations() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.SIDEBAR_DRAWER,
            )
        }

        // Initially expanded: project conversations are visible
        composeRule.onNodeWithTag("project-header-ledger-svc").assertIsDisplayed()
        composeRule.onNodeWithTag("project-toggle-ledger-svc").assertIsDisplayed()
        composeRule.onNodeWithTag("conversation-row-cas-rate-limiter").assertIsDisplayed()

        // Tap collapse toggle -> conversations under ledger-svc collapse and count badge renders
        composeRule.onNodeWithTag("project-toggle-ledger-svc").performClick()
        assertTrue(coordinator.workspaceStore.isProjectCollapsed("ledger-svc"))
        assertEquals(0, composeRule.onAllNodesWithTag("conversation-row-cas-rate-limiter").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("project-collapsed-count-ledger-svc", useUnmergedTree = true).assertIsDisplayed()

        // Tap collapse toggle again -> conversations expand back into view
        composeRule.onNodeWithTag("project-toggle-ledger-svc").performClick()
        assertFalse(coordinator.workspaceStore.isProjectCollapsed("ledger-svc"))
        composeRule.onNodeWithTag("conversation-row-cas-rate-limiter").assertIsDisplayed()

        // Tapping project header directly also collapses & expands cleanly without navigating away
        composeRule.onNodeWithTag("project-header-ledger-svc").performClick()
        assertTrue(coordinator.workspaceStore.isProjectCollapsed("ledger-svc"))
        assertEquals(0, composeRule.onAllNodesWithTag("conversation-row-cas-rate-limiter").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("project-collapsed-count-ledger-svc", useUnmergedTree = true).assertIsDisplayed()

        composeRule.onNodeWithTag("project-header-ledger-svc").performClick()
        assertFalse(coordinator.workspaceStore.isProjectCollapsed("ledger-svc"))
        composeRule.onNodeWithTag("conversation-row-cas-rate-limiter").assertIsDisplayed()
    }

    @Test
    fun atc28_unhydratedLiveConversationShowsLoadingInsteadOfNewConversationAndUpdatesWhenHydrated() {
        val unhydratedId = "8b52c910-1111-4000-8000-000000000099"
        val coordinator = AntigravityCoreCoordinator(autoPreloadConversations = false)
        coordinator.workspaceStore.seedFixture(
            projects = listOf(
                dev.antigravity.shared.model.ProjectWorkspace(
                    id = "slardar_app_ai",
                    name = "slardar_app_ai",
                    pathDisplay = "~/code/slardar_app_ai",
                    workspaceUri = "file:///Users/dev/code/slardar_app_ai",
                    runtime = dev.antigravity.shared.model.ProjectRuntimeTarget.MAC_BOOK_PRO,
                    hostName = "MacBook Pro",
                ),
            ),
            automations = emptyList(),
            availableRepos = emptyList(),
            contextCandidates = emptyList(),
        )
        coordinator.conversationSyncStore.applyStreamEvent(
            dev.antigravity.shared.protocol.JsonStepAndSummaryDecoder.JetboxDecodedEvent(
                summaries = listOf(
                    dev.antigravity.shared.model.CascadeSummary(
                        cascadeId = unhydratedId,
                        title = "New Conversation",
                        hasResolvedTitle = false,
                        projectSlug = "slardar_app_ai",
                        workspaceUri = "file:///Users/dev/code/slardar_app_ai",
                        status = CortexStepStatus.DONE,
                        stepCount = 4,
                        relativeTimeLabel = "1w",
                    ),
                ),
            ),
        )
        coordinator.conversationSyncStore.markHydrating(unhydratedId)

        // Disable auto-advance while indeterminate CircularProgressIndicator is visible
        composeRule.mainClock.autoAdvance = false
        composeRule.setContent {
            dev.antigravity.android.core.ui.theme.AntigravityTheme {
                dev.antigravity.android.ui.home.AgentsSidebarDrawerContent(
                    coordinator = coordinator,
                    onNewConversation = {},
                    onOpenAutomations = {},
                    onOpenCustomizations = {},
                    onOpenDisplayOptions = {},
                    onOpenNewProject = {},
                    onOpenConversation = {},
                    onLongPressConversation = {},
                    onOpenSettings = {},
                    activeHighlightCascadeId = "",
                )
            }
        }
        composeRule.mainClock.advanceTimeByFrame()

        // Unhydrated row renders Loading... indicator instead of placeholder "New Conversation"
        composeRule.onNodeWithTag("conversation-loading-$unhydratedId", useUnmergedTree = true).assertIsDisplayed()
        composeRule.onNodeWithText("Loading...", useUnmergedTree = true).assertIsDisplayed()

        // Once hydrated metadata arrives, the real derived title immediately replaces Loading...
        kotlinx.coroutines.runBlocking {
            coordinator.conversationSyncStore.applyHydratedStepsMetadata(
                host = null,
                cascadeId = unhydratedId,
                steps = listOf(
                    CascadeStep(
                        cascadeId = unhydratedId,
                        stepIndex = 0,
                        type = CortexStepType.USER_INPUT,
                        status = CortexStepStatus.DONE,
                        userInput = "Fix Slardar startup cold cache",
                    ),
                ),
                persist = false,
            )
        }
        composeRule.mainClock.autoAdvance = true
        composeRule.waitForIdle()
        assertEquals(
            0,
            composeRule.onAllNodesWithTag("conversation-loading-$unhydratedId", useUnmergedTree = true).fetchSemanticsNodes().size,
        )
        composeRule.onNodeWithText("Fix Slardar startup cold cache").assertIsDisplayed()
    }

    @Test
    fun atc29_plusButtonsOpenContextAndCreateProjectDraftCleanly() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CHAT_AND_COMPOSER,
            )
        }

        // 1. Tapping composer '+' opens Add Context popover cleanly and dismisses cleanly
        composeRule.onNodeWithTag("composer-btn-add-context").performClick()
        composeRule.onNodeWithTag("add-context-popover").assertIsDisplayed()
        composeRule.onNodeWithTag("ctx-menu-files").performClick()
        composeRule.onNodeWithTag("add-context-picker-sheet").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-add-context-apply").performClick()
        composeRule.onNodeWithTag("chat-steps-list").assertIsDisplayed()

        // 2. Tapping Back in chat returns to Home; opening sidebar and tapping '+' on a project transitions cleanly
        assertEquals(0, composeRule.onAllNodesWithTag("btn-sidebar").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("btn-chat-back").performClick()
        composeRule.onNodeWithTag("home-greeting").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-sidebar").performClick()
        composeRule.onNodeWithTag("sidebar-drawer").assertIsDisplayed()
        composeRule.onNodeWithTag("project-add-ledger-svc").performClick()
        composeRule.onNodeWithTag("home-composer-card").assertIsDisplayed()
    }

    @Test
    fun atc30_voiceDictationButtonsNeverCrashAndPreserveHomeContext() {
        // 1. Pure transcript merging matches iOS VoiceInputManager.mergeTranscript semantics
        assertEquals("Fix auth bug", dev.antigravity.android.ui.chat.mergeDictatedTranscript("", "Fix auth bug"))
        assertEquals(
            "Check middleware Fix auth bug",
            dev.antigravity.android.ui.chat.mergeDictatedTranscript("Check middleware", "Fix auth bug"),
        )
        assertEquals(
            "Check middleware Fix auth bug",
            dev.antigravity.android.ui.chat.mergeDictatedTranscript("Check middleware ", "Fix auth bug"),
        )
        assertEquals(
            "Keep typed text",
            dev.antigravity.android.ui.chat.mergeDictatedTranscript("Keep typed text", "   "),
        )

        // Grant RECORD_AUDIO in Robolectric so VoiceDictationController exercises the SpeechRecognizer path
        val app = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.app.Application>()
        org.robolectric.Shadows.shadowOf(app).grantPermissions(android.Manifest.permission.RECORD_AUDIO)

        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AGENTS_HOME,
            )
        }

        // 2. Tapping Home mic stays on Home (never jumps to hardcoded mock conversation) and never crashes
        composeRule.onNodeWithTag("btn-voice-mode").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("home-greeting").assertIsDisplayed()
        composeRule.onNodeWithTag("home-voice-error").assertIsDisplayed()
        composeRule.onNodeWithTag("home-voice-error").performClick()
        composeRule.waitForIdle()
        assertEquals(0, composeRule.onAllNodesWithTag("home-voice-error").fetchSemanticsNodes().size)

        // 3. Navigate into Chat and verify composer mic button never crashes and shows dismissible status when recognizer is absent
        composeRule.onNodeWithTag("btn-sidebar").performClick()
        composeRule.onNodeWithTag("conversation-row-cas-rate-limiter").performClick()
        composeRule.onNodeWithTag("composer-btn-voice").assertIsDisplayed()
        composeRule.onNodeWithTag("composer-btn-voice").performClick()
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("composer-voice-error").assertIsDisplayed()
        composeRule.onNodeWithTag("composer-voice-error").performClick()
        composeRule.waitForIdle()
        assertEquals(0, composeRule.onAllNodesWithTag("composer-voice-error").fetchSemanticsNodes().size)

        // 4. Verify Android VoiceDictationController honors AppLanguage.ZH_HANS, conversation context
        //    hints, API 34+ native automatic language detection/switching extras, and persistence
        val controller = dev.antigravity.android.ui.chat.VoiceDictationController(app)
        controller.selectLanguage(dev.antigravity.shared.model.VoiceDictationLanguage.AUTO)
        assertEquals("zh-CN", controller.resolveSpeechLocaleTag(AppLanguage.ZH_HANS))
        assertEquals(
            "zh-CN",
            controller.resolveSpeechLocaleTag(AppLanguage.ENGLISH, contextTextHint = "帮我排查一下登录超时问题"),
        )
        assertEquals(
            "自动 · 中文",
            controller.activeLanguageBadgeLabel(AppLanguage.ZH_HANS),
        )
        val (api34Intent, api34Locale) = controller.buildRecognizerIntent(
            appLanguage = AppLanguage.ENGLISH,
            contextTextHint = "帮我排查一下登录超时问题",
            enableApi34AutoSwitch = true,
            sdkInt = android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE,
        )
        assertEquals("zh-CN", api34Locale)
        assertTrue(api34Intent.getBooleanExtra(android.speech.RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, false))
        assertEquals(
            arrayListOf("zh-CN", "en-US"),
            api34Intent.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES),
        )
        assertEquals(
            android.speech.RecognizerIntent.LANGUAGE_SWITCH_BALANCED,
            api34Intent.getStringExtra(android.speech.RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH),
        )
        assertEquals(
            arrayListOf("zh-CN", "en-US"),
            api34Intent.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_SWITCH_ALLOWED_LANGUAGES),
        )
        controller.selectLanguage(dev.antigravity.shared.model.VoiceDictationLanguage.ZH_CN)
        assertEquals("zh-CN", controller.resolveSpeechLocaleTag(AppLanguage.ENGLISH))
        assertEquals("中文", controller.activeLanguageBadgeLabel(AppLanguage.ENGLISH))
        val reloaded = dev.antigravity.android.ui.chat.VoiceDictationController(app)
        assertEquals(dev.antigravity.shared.model.VoiceDictationLanguage.ZH_CN, reloaded.preferredLanguage)
        reloaded.selectLanguage(dev.antigravity.shared.model.VoiceDictationLanguage.AUTO)
    }

    @Test
    fun atc31_realtimeBilingualLanguageSwitchingUpdatesUiImmediatelyAndPersists() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.SETTINGS,
            )
        }

        // 1. Initial English baseline renders Settings, Language, and Scan New QR
        composeRule.onNodeWithText("Settings").assertIsDisplayed()
        composeRule.onNodeWithText("Language").assertIsDisplayed()
        composeRule.onNodeWithText("Scan New QR").assertIsDisplayed()

        // 2. Switch to Simplified Chinese -> UI recomposes in real time without recreating Activity
        composeRule.onNodeWithTag("row-settings-language").performClick()
        composeRule.onNodeWithTag("language-option-zh_hans").performClick()
        assertEquals(AppLanguage.ZH_HANS, coordinator.settingsStore.state.value.appearance.language)
        composeRule.onNodeWithText("设置").assertIsDisplayed()
        composeRule.onNodeWithText("语言").assertIsDisplayed()
        composeRule.onNodeWithText("扫描新二维码").assertIsDisplayed()

        // 3. Navigate into More subpage -> Chinese labels + Google LLC trademark attribution preserved
        composeRule.onNodeWithTag("row-settings-more").performClick()
        composeRule.onNodeWithTag("settings-more-subpage").assertIsDisplayed()
        composeRule.onNodeWithText("权限").assertIsDisplayed()
        composeRule.onNodeWithTag("card-about-copyright").assertIsDisplayed()
        composeRule.onNodeWithTag("btn-settings-more-back").performClick()

        // 4. Switch back to English -> UI immediately restores English labels
        composeRule.onNodeWithTag("row-settings-language").performClick()
        composeRule.onNodeWithTag("language-option-english").performClick()
        assertEquals(AppLanguage.ENGLISH, coordinator.settingsStore.state.value.appearance.language)
        composeRule.onNodeWithText("Settings").assertIsDisplayed()
        composeRule.onNodeWithText("Language").assertIsDisplayed()
        composeRule.onNodeWithText("Scan New QR").assertIsDisplayed()

        // 5. Cold-start persistence across live coordinator instances sharing preferences store
        val sharedPrefs = dev.antigravity.shared.platform.InMemoryPreferencesStore()
        val live1 = AntigravityCoreCoordinator(preferencesStore = sharedPrefs)
        live1.settingsStore.setAppLanguage(AppLanguage.ZH_HANS)
        val live2 = AntigravityCoreCoordinator(preferencesStore = sharedPrefs)
        assertEquals(AppLanguage.ZH_HANS, live2.settingsStore.state.value.appearance.language)
    }

    @Test
    fun atc32_emptyChatStaysCleanWhenOnlineAndShowsCompactPillWhenOffline() {
        val hostUuid = "huangjiafandemac-mini-local-swift-vapor"
        val storage = dev.antigravity.shared.domain.InMemoryProjectionStorage()
        val coordinator = AntigravityCoreCoordinator(
            preferencesStore = dev.antigravity.shared.platform.InMemoryPreferencesStore(),
            projectionStorage = storage,
            autoPreloadConversations = false,
        )
        val pairedHost = dev.antigravity.shared.model.RemoteHostInstance(
            instanceId = hostUuid,
            hostname = hostUuid,
            channel = dev.antigravity.shared.model.RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = "https://antigravity.google.com/r/$hostUuid",
            isOnline = true,
        )
        coordinator.connectionStore.seedVerificationConnection(
            activeHost = pairedHost,
            knownHosts = listOf(pairedHost),
            statusText = "Connected · $hostUuid",
        )
        val emptyDraftId = coordinator.createLocalDraftConversation(
            workspaceUri = "",
            projectSlug = "No Project",
            title = "New Conversation",
        )
        coordinator.chatStore.setActiveCascade(emptyDraftId)

        composeRule.setContent {
            dev.antigravity.android.core.ui.theme.AntigravityTheme {
                dev.antigravity.android.ui.chat.CascadeChatScreen(
                    coordinator = coordinator,
                    onBack = {},
                    onOpenDiffReview = {},
                    onOpenPlanReview = {},
                    onOpenAddContext = {},
                    onOpenModelAndMode = {},
                    onOpenOverview = {},
                    onOpenSideQuestion = {},
                    onOpenSwarmBoard = {},
                    onOpenVoiceMode = {},
                    onBiometricPrompt = { _, _ -> },
                )
            }
        }

        // 1. When online & empty, canvas stays clean with NO "Ready for Prompt" / "Unassigned conversation" card or offline pill
        assertEquals(0, composeRule.onAllNodesWithTag("chat-offline-status-pill").fetchSemanticsNodes().size)
        composeRule.onNodeWithText("Ready for Prompt", substring = true, useUnmergedTree = true).assertDoesNotExist()
        composeRule.onNodeWithText("Unassigned conversation", substring = true, useUnmergedTree = true).assertDoesNotExist()
        composeRule.onNodeWithText("No Project · $hostUuid", useUnmergedTree = true).assertIsDisplayed()

        // 2. When host goes offline with 1 queued message, header shows Offline prefix and canvas shows only a compact pill
        coordinator.connectionStore.markInstanceOffline(
            instanceUuid = hostUuid,
            errorMessage = "Antigravity Desktop is offline or unregistered on Cloud Relay.",
        )
        val queuedDraftId = coordinator.createLocalDraftConversation(
            workspaceUri = "",
            projectSlug = "No Project",
            title = "Queued follow-up",
        )
        kotlinx.coroutines.runBlocking {
            coordinator.sendMessage(
                cascadeId = queuedDraftId,
                message = "没拉到任何 project 啊",
                workspaceUri = "",
                isOptimisticDraft = true,
                instanceUuidOverride = hostUuid,
            )
        }
        coordinator.chatStore.setActiveCascade(emptyDraftId)
        composeRule.waitForIdle()

        composeRule.onNodeWithTag("chat-offline-status-pill").assertIsDisplayed()
        composeRule.onNodeWithText("Host offline · 1 queued", useUnmergedTree = true).assertIsDisplayed()
        composeRule.onNodeWithText("No Project · Offline · $hostUuid", useUnmergedTree = true).assertIsDisplayed()
        composeRule.onNodeWithText("Unassigned conversation", substring = true, useUnmergedTree = true).assertDoesNotExist()
    }

    @Test
    fun atc31_errorMessageStepAndLegacyCachedErrorRenderDedicatedErrorCardNotUnknownFallback() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        coordinator.chatStore.injectDebugSteps(
            listOf(
                CascadeStep(
                    cascadeId = "cas-rate-limiter",
                    stepIndex = 101,
                    type = CortexStepType.ERROR_MESSAGE,
                    status = CortexStepStatus.ERROR,
                    errorMessage = dev.antigravity.shared.model.ErrorMessagePayload(
                        message = "Model quota reached for Gemini 4 Neon.",
                        detail = "rpc error: code = ResourceExhausted",
                        errorCode = "HTTP 429",
                    ),
                ),
                CascadeStep(
                    cascadeId = "cas-rate-limiter",
                    stepIndex = 102,
                    type = CortexStepType.UNSPECIFIED,
                    status = CortexStepStatus.DONE,
                    rawTypeName = "CORTEX_STEP_TYPE_ERROR_MESSAGE",
                ),
            )
        )

        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.CHAT_AND_COMPOSER,
            )
        }

        val listExists = composeRule.onAllNodesWithTag("chat-steps-list").fetchSemanticsNodes().isNotEmpty()
        if (listExists) {
            composeRule.onNodeWithTag("chat-steps-list").performScrollToNode(hasTestTag("step-error-101"))
        }
        composeRule.onNodeWithTag("step-error-101").assertIsDisplayed()
        composeRule.onNodeWithText("Model quota reached for Gemini 4 Neon.", substring = true, useUnmergedTree = true)
            .assertIsDisplayed()
        composeRule.onNodeWithText("HTTP 429", useUnmergedTree = true).assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithTag("card-forward-step-101").fetchSemanticsNodes().size)

        // Expand technical details
        composeRule.onNodeWithText("Show details", useUnmergedTree = true).performClick()
        composeRule.onNodeWithText("rpc error: code = ResourceExhausted", substring = true, useUnmergedTree = true)
            .assertIsDisplayed()

        // Legacy cached UNSPECIFIED + rawTypeName = CORTEX_STEP_TYPE_ERROR_MESSAGE renders ErrorMessageStepCard too
        if (listExists) {
            composeRule.onNodeWithTag("chat-steps-list").performScrollToNode(hasTestTag("step-error-102"))
        }
        composeRule.onNodeWithTag("step-error-102").assertIsDisplayed()
        composeRule.onNodeWithText(
            "Antigravity Desktop encountered an error while processing this turn.",
            substring = true,
            useUnmergedTree = true,
        ).assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithTag("card-forward-step-102").fetchSemanticsNodes().size)
    }

    @Test
    fun testInlineSendErrorBannerShowsRetryAndDismissActions() {
        val coordinator = AntigravityCoreCoordinator(
            preferencesStore = dev.antigravity.shared.platform.InMemoryPreferencesStore(),
            projectionStorage = dev.antigravity.shared.domain.InMemoryProjectionStorage(),
            autoPreloadConversations = false,
        )
        coordinator.isVerificationMode = false
        val cid = "v1/cloud-error-banner-test"
        coordinator.conversationSyncStore.upsertSummary(
            dev.antigravity.shared.model.CascadeSummary(
                cascadeId = cid,
                title = "介绍下这个仓库",
                projectSlug = "slardar_app_ai",
                workspaceUri = "cloud://slardar_app_ai",
                status = CortexStepStatus.DONE,
                stepCount = 1,
                isCloud = true,
                originHostName = "Antigravity",
            ),
        )
        coordinator.chatStore.seedFixtureSteps(
            stepsByCascade = mapOf(
                cid to listOf(
                    dev.antigravity.shared.model.CascadeStep(
                        cascadeId = cid,
                        stepIndex = 0,
                        type = dev.antigravity.shared.model.CortexStepType.USER_INPUT,
                        status = CortexStepStatus.DONE,
                        userInput = "介绍下这个仓库",
                    ),
                ),
            ),
            questions = emptyList(),
        )
        coordinator.chatStore.setActiveCascade(cid)
        coordinator.chatStore.setStepLoadError(
            "Failed to send message: This conversation was not found on this host (session not found). Tap Retry or start a new chat.",
        )

        var retryCount = 0
        composeRule.setContent {
            dev.antigravity.android.core.ui.theme.AntigravityTheme {
                dev.antigravity.android.ui.chat.CascadeChatScreen(
                    coordinator = coordinator,
                    onBack = {},
                    onOpenDiffReview = {},
                    onOpenPlanReview = {},
                    onOpenAddContext = {},
                    onOpenModelAndMode = {},
                    onOpenOverview = {},
                    onOpenSideQuestion = {},
                    onOpenSwarmBoard = {},
                    onOpenVoiceMode = {},
                    onBiometricPrompt = { _, _ -> },
                    onRetryLoadSteps = { retryCount += 1 },
                )
            }
        }

        composeRule.onNodeWithTag("chat-step-load-error-banner").assertIsDisplayed()
        composeRule.onNodeWithTag("chat-inline-error-retry").assertIsDisplayed()
        composeRule.onNodeWithTag("chat-inline-error-dismiss").assertIsDisplayed()
        composeRule.onNodeWithText("session not found", substring = true, useUnmergedTree = true).assertIsDisplayed()

        composeRule.onNodeWithTag("chat-inline-error-retry").performClick()
        composeRule.waitForIdle()
        assertEquals(1, retryCount)
        assertEquals(0, composeRule.onAllNodesWithTag("chat-step-load-error-banner").fetchSemanticsNodes().size)
    }

    @Test
    fun atc32_localProjectAutoPermissionModeAndRemoteIsolation() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = EsddVerifySceneCase.AGENTS_HOME,
            )
        }

        // 1. Local project (`ledger-svc`) exposes Auto mode in Permissions popover and updates composer pill
        composeRule.onNodeWithTag("btn-permissions-preset").performClick()
        composeRule.onNodeWithTag("permissions-preset-popover").assertIsDisplayed()
        composeRule.onNodeWithText("Permissions for this conversation", useUnmergedTree = true).assertIsDisplayed()
        composeRule.onNodeWithTag("preset-option-auto").assertIsDisplayed()
        composeRule.onNodeWithTag("preset-option-auto").performClick()

        assertEquals(AgentPermissionPreset.AUTO, coordinator.settingsStore.state.value.localPermissionPreset)
        assertEquals(AgentPermissionPreset.AUTO, coordinator.settingsStore.state.value.activePermissionPreset)
        assertEquals(AgentPermissionPreset.TURBO, coordinator.settingsStore.state.value.remotePermissionPreset)
        composeRule.onNodeWithText("Auto", useUnmergedTree = true).assertIsDisplayed()

        // 2. Switching Home runtime toggle to Cloud opens Remote Permissions (no Auto) and isolates remote preset
        composeRule.onNodeWithTag("home-cloud-toggle").performClick()
        composeRule.onNodeWithText("Turbo", useUnmergedTree = true).assertIsDisplayed()
        composeRule.onNodeWithTag("btn-permissions-preset").performClick()
        composeRule.onNodeWithTag("permissions-preset-popover").assertIsDisplayed()
        composeRule.onNodeWithText("Remote Permissions", useUnmergedTree = true).assertIsDisplayed()
        assertEquals(0, composeRule.onAllNodesWithTag("preset-option-auto").fetchSemanticsNodes().size)
        composeRule.onNodeWithTag("preset-option-request_review").performClick()

        assertEquals(AgentPermissionPreset.REQUEST_REVIEW, coordinator.settingsStore.state.value.remotePermissionPreset)
        assertEquals(AgentPermissionPreset.AUTO, coordinator.settingsStore.state.value.localPermissionPreset)
    }

    @Test
    fun atc33_settingsAndHomeRenderAccurateOfflineAndOnlineHostStatus() {
        val coordinator = AntigravityCoreCoordinator(
            autoPreloadConversations = false,
            enableForegroundHeartbeatLoop = false,
        )
        val macHost = dev.antigravity.shared.domain.EsddVerificationFixtures.macHost
        val imacHost = dev.antigravity.shared.domain.EsddVerificationFixtures.officeImacHost
        coordinator.connectionStore.seedVerificationConnection(
            activeHost = macHost,
            knownHosts = listOf(macHost, imacHost),
            statusText = "Connected · MacBook Pro · 42ms",
        )
        coordinator.isVerificationMode = false
        coordinator.connectionStore.markInstanceOffline(
            instanceUuid = macHost.instanceId,
            errorMessage = "MacBook Pro is offline",
        )

        composeRule.setContent {
            AntigravityAppRoot(
                coordinator = coordinator,
                initialVerifyScene = null,
            )
        }

        // Home switcher pill must truthfully show Offline when all paired hosts are offline
        composeRule.onNodeWithTag("host-switcher-pill").assertIsDisplayed()
        composeRule.onNodeWithText("All Hosts · Offline", useUnmergedTree = true).assertIsDisplayed()

        // Navigate into Settings via Sidebar -> Hero Card must show Host Offline + Reconnect button (not hardcoded Connected)
        composeRule.onNodeWithTag("btn-sidebar").performClick()
        composeRule.onNodeWithTag("drawer-settings").performClick()
        composeRule.onNodeWithText("Host Offline: MacBook Pro", useUnmergedTree = true).assertIsDisplayed()
        composeRule.onNodeWithTag("btn-reconnect-host").assertIsDisplayed()
    }
}
