package dev.antigravity.shared.domain

import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AppAppearanceMode
import dev.antigravity.shared.model.AppThemePreset
import dev.antigravity.shared.model.AutomationSectionKind
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.ConversationSortField
import dev.antigravity.shared.model.DiffCompareMode
import dev.antigravity.shared.model.EsddVerifySceneCase
import dev.antigravity.shared.model.NewProjectDraft
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectSourceKind
import dev.antigravity.shared.model.ThinkingEffortLevel
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class ExtendedDomainStoresTest {

    @Test
    fun esddVerificationCoordinatorPopulatesAll13CanonicalStates() {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        assertTrue(coordinator.isVerificationMode)
        assertTrue(coordinator.syncState.value.summaries.size >= 7)
        assertEquals(2, coordinator.workspaceStore.state.value.projects.size)
        assertEquals(4, coordinator.workspaceStore.state.value.automations.size)
        assertEquals(6, coordinator.workspaceStore.state.value.contextCandidates.size)
        assertTrue(coordinator.reviewStore.state.value.artifacts.isNotEmpty())
        assertTrue(coordinator.reviewStore.state.value.diffs.isNotEmpty())
        assertEquals(3, coordinator.chatStore.state.value.structuredQuestions.size)

        // Verify live progress snapshot matches UE13 running/waiting semantics
        val live = assertNotNull(coordinator.liveProgressSnapshot())
        assertEquals("cas-rate-limiter", live.cascadeId)
        assertEquals(4, live.currentStepIndex)
        assertEquals(7, live.totalSteps)
        assertEquals(128, live.additions)
        assertEquals(14, live.deletions)
    }

    @Test
    fun workspaceAndAutomationStoreHandlesDisplayOptionsProjectsAndAutomations() = runTest {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        val store = coordinator.workspaceStore

        // Display options + Mark all read + Reset
        store.updateDisplayOptions { it.copy(sortBy = ConversationSortField.TITLE, autoPinOnMessage = true) }
        assertEquals(ConversationSortField.TITLE, store.state.value.displayOptions.sortBy)
        assertTrue(store.state.value.displayOptions.autoPinOnMessage)
        coordinator.markAllConversationsRead()
        assertEquals(0, coordinator.syncState.value.summaries.count { it.isUnread })
        store.resetDisplayOptions()
        assertEquals(ConversationSortField.LAST_UPDATED, store.state.value.displayOptions.sortBy)
        assertFalse(store.state.value.displayOptions.autoPinOnMessage)

        // Create Project
        val beforeCount = store.state.value.projects.size
        store.createProject(
            client = null,
            draft = NewProjectDraft(
                runsOn = ProjectRuntimeTarget.CLOUD,
                source = ProjectSourceKind.GITHUB_REPO,
                projectName = "ledger-svc-cloud",
            )
        )
        assertEquals(beforeCount + 1, store.state.value.projects.size)
        assertTrue(store.state.value.projects.any { it.name == "ledger-svc-cloud" })

        // Automations: NL create, Run Now, Resume paused
        store.createAutomationFromPrompt(client = null, prompt = "Every weekday at 9, summarize open PRs")
        assertTrue(store.state.value.automations.any { it.title.contains("summarize open PRs", ignoreCase = true) })
        store.runAutomationNow(client = null, automationId = "auto-nightly-audit")
        assertTrue(store.state.value.automations.first { it.id == "auto-nightly-audit" }.isRunningNow)
        store.resumeAutomation(client = null, automationId = "auto-bundle-size")
        assertEquals(
            AutomationSectionKind.SCHEDULED,
            store.state.value.automations.first { it.id == "auto-bundle-size" }.section
        )
    }

    @Test
    fun reviewAndVcsStoreHandlesPlanCommentsDiffReviewAndGitStage() = runTest {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        val review = coordinator.reviewStore

        val initialComments = review.state.value.planComments.size
        review.addPlanComment(
            targetFilePath = "settlement/settlement_test.go",
            quotedSpan = "remove the package-level clk variable",
            body = "Ensure parallel subtests create isolated fake clocks."
        )
        assertEquals(initialComments + 1, review.state.value.planComments.size)
        review.sendPlanComments(client = null, cascadeId = "cas-flaky-settlement")
        assertTrue(review.state.value.planCommentsSentCount > 0)

        // Turn Diff review + line comment + stage/viewed
        review.selectDiffMode(DiffCompareMode.WORKING_TREE)
        assertEquals(DiffCompareMode.WORKING_TREE, review.state.value.compareMode)
        review.addDiffLineComment(
            filePath = "middleware/ratelimit.go",
            lineNumber = 29,
            body = "Use l.clock.Now() so tests remain deterministic."
        )
        assertTrue(review.state.value.diffLineComments.any { it.lineNumber == 29 })
        review.toggleFileReviewed("middleware/ratelimit.go")
        assertTrue(review.state.value.diffs.first { it.filePath == "middleware/ratelimit.go" }.isReviewed)
        review.stageFile(client = null, cascadeId = "cas-rate-limiter", filePath = "middleware/ratelimit.go")
        assertTrue(review.state.value.diffs.first { it.filePath == "middleware/ratelimit.go" }.isStaged)
    }

    @Test
    fun orchestrationAndSettingsStoresHandleV233FlowsAndOrchestratorEffortLock() = runTest {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        val orch = coordinator.orchestrationStore
        val settings = coordinator.settingsStore

        // /btw side question multi-turn + insert into main
        orch.openSideQuestion("cas-rate-limiter")
        orch.sendSideQuestion(client = null, prompt = "Does sync.Mutex block across tenants?")
        assertTrue(orch.state.value.sideQuestionThread.messages.size >= 2)

        // Queued follow-up messages
        orch.enqueueFollowUp("After load test, add p99 latency alert.")
        assertEquals(1, orch.state.value.queuedMessages.size)
        val qId = orch.state.value.queuedMessages.first().id
        orch.updateQueuedMessage(qId, "After load test, add p99 & p999 latency alerts.")
        assertTrue(orch.state.value.queuedMessages.first().text.contains("p999"))
        orch.removeQueuedMessage(qId)
        assertTrue(orch.state.value.queuedMessages.isEmpty())

        // Voice mode lifecycle -> generates persisted Call Summary
        orch.startVoiceMode()
        assertTrue(orch.state.value.voiceState.isActive)
        orch.appendVoiceTurn(isUser = true, text = "Approve the vegeta test and watch latency.")
        val summary = orch.endVoiceMode()
        assertFalse(orch.state.value.voiceState.isActive)
        assertNotNull(summary)
        assertTrue(summary.turns.isNotEmpty())

        // Settings: Model/Mode/Effort + Orchestrator effort lock + Dynamic Color
        settings.selectMode(CascadeExecutionMode.FAST)
        assertEquals(CascadeExecutionMode.FAST, settings.state.value.selectedMode)
        settings.selectThinkingEffort(ThinkingEffortLevel.EXTRA)
        assertEquals(ThinkingEffortLevel.EXTRA, settings.state.value.selectedEffort)
        settings.selectModel("MODEL_ORCHESTRATOR_NEON")
        assertTrue(settings.state.value.isEffortLockedForOrchestrator)
        settings.setPermissionPreset(client = null, cascadeId = "cas-rate-limiter", preset = AgentPermissionPreset.TURBO)
        assertEquals(AgentPermissionPreset.TURBO, settings.state.value.activePermissionPreset)
        settings.updateAppearance {
            it.copy(
                theme = AppThemePreset.OBSIDIAN,
                appearanceMode = AppAppearanceMode.DARK,
                useDynamicColor = true
            )
        }
        assertTrue(settings.state.value.appearance.useDynamicColor)

        // Configure scene helper routes cleanly across all 19 ESDD scenes
        assertEquals(19, EsddVerifySceneCase.entries.size)
        for (scene in EsddVerifySceneCase.entries) {
            EsddVerificationFixtures.configureCoordinatorForVerifyScene(coordinator, scene)
        }
    }

    @Test
    fun ueV21AutomationDetailEditRetryDeleteAndLanguageDefaultsWork() = runTest {
        val coordinator = AntigravityCoreCoordinator.createEsddVerificationCoordinator()
        val ws = coordinator.workspaceStore
        val settings = coordinator.settingsStore

        assertEquals("MODEL_GOOGLE_GEMINI_4_NEON", settings.state.value.selectedModelId)
        assertEquals(ThinkingEffortLevel.EXTRA, settings.state.value.selectedEffort)
        assertEquals("6.2k tokens", settings.state.value.customizations.loadedTokensLabel)
        assertEquals(5, settings.state.value.customizations.skills.size)
        assertEquals(4, settings.state.value.customizations.rules.size)

        // Language toggle
        assertEquals(dev.antigravity.shared.model.AppLanguage.ENGLISH, settings.state.value.appearance.language)
        settings.setAppLanguage(dev.antigravity.shared.model.AppLanguage.ZH_HANS)
        assertEquals(dev.antigravity.shared.model.AppLanguage.ZH_HANS, settings.state.value.appearance.language)

        // Automation Detail / Edit / Retry / Delete
        ws.selectAutomation("auto-nightly-audit")
        assertEquals("auto-nightly-audit", ws.state.value.selectedAutomationId)
        val nightly = ws.state.value.automations.first { it.id == "auto-nightly-audit" }
        assertTrue(nightly.recentRuns.size >= 3)
        ws.retryAutomationRun(client = null, automationId = "auto-nightly-audit", runId = "run-3")
        assertTrue(ws.state.value.automations.first { it.id == "auto-nightly-audit" }.isRunningNow)
        ws.updateAutomation(
            client = null,
            automationId = "auto-nightly-audit",
            title = "Nightly security & dependency audit",
            prompt = "Run govulncheck and open a PR for high CVEs.",
            projectSlug = "ledger-svc",
            section = dev.antigravity.shared.model.AutomationSectionKind.SCHEDULED,
            repeatsLabel = "Weekdays",
            timeLabel = "03:00",
            modelLabel = "Gemini 4 Neon",
        )
        val updated = ws.state.value.automations.first { it.id == "auto-nightly-audit" }
        assertEquals("Nightly security & dependency audit", updated.title)
        assertEquals("Weekdays · 03:00", updated.repeatsLabel)
        ws.deleteAutomation(client = null, automationId = "auto-bundle-size")
        assertFalse(ws.state.value.automations.any { it.id == "auto-bundle-size" })
    }

    @Test
    fun modelFirstThenEffortSelectionResolvesVariantsAndClampsUnsupportedEfforts() {
        val settings = SettingsAndCustomizationStore()
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
        val orchCarbon = dev.antigravity.shared.model.CascadeModelConfig(
            modelId = "ORCHESTRATOR_CARBON",
            displayName = "Orchestrator (Carbon)",
            subtitle = "Carbon plans · Hydrogen executes",
            isOrchestrator = true,
            supportedEfforts = emptyList(),
            isModelAlias = true,
        )

        settings.applyModelCatalog(
            dev.antigravity.shared.model.LiveModelCatalogResult(
                models = listOf(neon, carbon, orchCarbon),
                defaultModelId = "MODEL_PLACEHOLDER_M41",
            ),
        )
        assertEquals("MODEL_PLACEHOLDER_M41", settings.state.value.selectedModelId)
        assertEquals(ThinkingEffortLevel.HIGH, settings.state.value.selectedEffort)

        // Step 2: change effort on Gemini 4 Neon -> updates BOTH selectedEffort AND upstream variant modelId
        settings.selectThinkingEffort(ThinkingEffortLevel.EXTRA)
        assertEquals(ThinkingEffortLevel.EXTRA, settings.state.value.selectedEffort)
        assertEquals("MODEL_PLACEHOLDER_M42", settings.state.value.selectedModelId)
        assertEquals("Gemini 4 Neon", settings.state.value.selectedModel?.displayName)

        // Step 1: switch to Gemini 4 Carbon -> clamps EXTRA down to Carbon's default MEDIUM & variant ID
        settings.selectModel("MODEL_PLACEHOLDER_M44")
        assertEquals("Gemini 4 Carbon", settings.state.value.selectedModel?.displayName)
        assertEquals(ThinkingEffortLevel.MEDIUM, settings.state.value.selectedEffort)
        assertEquals("MODEL_PLACEHOLDER_M44", settings.state.value.selectedModelId)

        // Unsupported EXTRA on Carbon is ignored
        settings.selectThinkingEffort(ThinkingEffortLevel.EXTRA)
        assertEquals(ThinkingEffortLevel.MEDIUM, settings.state.value.selectedEffort)
        assertEquals("MODEL_PLACEHOLDER_M44", settings.state.value.selectedModelId)

        // Supported HIGH on Carbon resolves to M45
        settings.selectThinkingEffort(ThinkingEffortLevel.HIGH)
        assertEquals(ThinkingEffortLevel.HIGH, settings.state.value.selectedEffort)
        assertEquals("MODEL_PLACEHOLDER_M45", settings.state.value.selectedModelId)

        // Re-tapping Carbon family preserves chosen HIGH effort
        settings.selectModel("MODEL_PLACEHOLDER_M44")
        assertEquals(ThinkingEffortLevel.HIGH, settings.state.value.selectedEffort)
        assertEquals("MODEL_PLACEHOLDER_M45", settings.state.value.selectedModelId)

        // Selecting Orchestrator locks effort & preserves alias flag
        settings.selectModel("ORCHESTRATOR_CARBON")
        assertTrue(settings.state.value.isEffortLockedForOrchestrator)
        assertTrue(settings.state.value.resolvedSelectedIsModelAlias)
    }
}
