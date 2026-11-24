package dev.antigravity.shared.domain

import dev.antigravity.shared.model.AgentDisplayOptions
import dev.antigravity.shared.model.AutomationItem
import dev.antigravity.shared.model.AutomationSectionKind
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.ContextCandidateItem
import dev.antigravity.shared.model.GitHubRepoItem
import dev.antigravity.shared.model.NewProjectDraft
import dev.antigravity.shared.model.ProjectDetailTab
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.HostCapability
import dev.antigravity.shared.protocol.currentTimeMillis
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlin.random.Random

public data class WorkspaceAndAutomationState(
    public val projects: List<ProjectWorkspace> = emptyList(),
    public val automations: List<AutomationItem> = emptyList(),
    public val selectedAutomationId: String = "auto-nightly-audit",
    public val availableRepos: List<GitHubRepoItem> = emptyList(),
    public val contextCandidates: List<ContextCandidateItem> = emptyList(),
    public val attachedComposerChips: List<ComposerAttachmentChip> = emptyList(),
    public val displayOptions: AgentDisplayOptions = AgentDisplayOptions(),
    public val collapsedProjectIds: Set<String> = emptySet(),
    public val selectedProjectId: String = "ledger-svc",
    public val selectedProjectTab: ProjectDetailTab = ProjectDetailTab.ACTIVE,
    public val newProjectDraft: NewProjectDraft = NewProjectDraft(),
    public val lastCapabilityError: String? = null,
)

/**
 * Shared KMP domain store managing Projects (`UE04`/`UE05`), Display Options (`UE02`),
 * Native Sidecar Automations (`UE06`), and Composer Add-Context candidates/chips (`UE08`).
 */
public class WorkspaceAndAutomationStore(
    private val onCapabilityError: (String) -> Unit = {},
) {
    private val _state = MutableStateFlow(WorkspaceAndAutomationState())
    public val state: StateFlow<WorkspaceAndAutomationState> = _state.asStateFlow()

    public fun seedFixture(
        projects: List<ProjectWorkspace>,
        automations: List<AutomationItem>,
        availableRepos: List<GitHubRepoItem>,
        contextCandidates: List<ContextCandidateItem>,
        attachedComposerChips: List<ComposerAttachmentChip> = emptyList(),
        selectedProjectId: String = "ledger-svc",
        selectedProjectTab: ProjectDetailTab = ProjectDetailTab.ACTIVE,
    ) {
        _state.update {
            it.copy(
                projects = projects,
                automations = automations,
                availableRepos = availableRepos,
                contextCandidates = contextCandidates,
                attachedComposerChips = attachedComposerChips,
                displayOptions = AgentDisplayOptions(),
                collapsedProjectIds = emptySet(),
                selectedProjectId = selectedProjectId,
                selectedProjectTab = selectedProjectTab,
                newProjectDraft = NewProjectDraft(selectedRepo = availableRepos.firstOrNull()),
                lastCapabilityError = null,
            )
        }
    }

    public fun updateDisplayOptions(transform: (AgentDisplayOptions) -> AgentDisplayOptions) {
        _state.update { it.copy(displayOptions = transform(it.displayOptions)) }
    }

    public fun resetDisplayOptions() {
        _state.update { it.copy(displayOptions = AgentDisplayOptions()) }
    }

    public fun toggleProjectExpanded(projectId: String) {
        _state.update { prev ->
            val nowCollapsed = projectId !in prev.collapsedProjectIds
            val nextCollapsed = if (nowCollapsed) {
                prev.collapsedProjectIds + projectId
            } else {
                prev.collapsedProjectIds - projectId
            }
            val nextProjects = prev.projects.map { proj ->
                if (proj.id == projectId) proj.copy(isExpandedInHome = !nowCollapsed) else proj
            }
            prev.copy(
                collapsedProjectIds = nextCollapsed,
                projects = nextProjects,
            )
        }
    }

    public fun selectProject(projectId: String) {
        _state.update { it.copy(selectedProjectId = projectId) }
    }

    public fun selectProjectTab(tab: ProjectDetailTab) {
        _state.update { it.copy(selectedProjectTab = tab) }
    }

    public fun updateNewProjectDraft(transform: (NewProjectDraft) -> NewProjectDraft) {
        _state.update { it.copy(newProjectDraft = transform(it.newProjectDraft)) }
    }

    public suspend fun createProject(
        client: AntigravityKmpRpcClient?,
        draft: NewProjectDraft = _state.value.newProjectDraft,
    ): ProjectWorkspace {
        val slug = draft.projectName.trim().ifEmpty {
            draft.selectedRepo?.fullName?.substringAfterLast('/')?.takeIf { it.isNotBlank() } ?: "new-project"
        }
        val repoPath = draft.selectedRepo?.fullName ?: "acme/$slug"
        val isCloud = draft.runsOn == ProjectRuntimeTarget.CLOUD
        val pathDisplay = if (isCloud) "cloud://$repoPath" else "~/code/$slug"
        val workspaceUri = if (isCloud) "cloud://$repoPath" else "file:///Users/wl/code/$slug"
        val branch = draft.selectedRepo?.defaultBranch ?: "main"

        val optimistic = ProjectWorkspace(
            id = slug,
            name = slug,
            pathDisplay = pathDisplay,
            workspaceUri = workspaceUri,
            runtime = draft.runsOn,
            hostName = if (isCloud) "Cloud" else draft.runsOn.displayTitle,
            activeBranch = branch,
            worktrees = listOf(branch, "worktree/$slug"),
            isExpandedInHome = true,
            rulesAndSkillsCount = 4,
        )

        val previousProjects = _state.value.projects
        val previousSelectedId = _state.value.selectedProjectId
        _state.update { prev ->
            val updated = if (prev.projects.any { it.id == optimistic.id }) {
                prev.projects.map { if (it.id == optimistic.id) optimistic else it }
            } else {
                prev.projects + optimistic
            }
            prev.copy(
                projects = updated,
                selectedProjectId = optimistic.id,
                lastCapabilityError = null,
            )
        }

        val remote = performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.CONVERSATION_ANNOTATIONS,
            onUnsupported = ::recordCapabilityError,
            rollback = {
                _state.update {
                    it.copy(
                        projects = previousProjects,
                        selectedProjectId = previousSelectedId,
                    )
                }
            },
        ) { rpc ->
            rpc.createProjectWorkspace(draft)
        }

        if (remote != null) {
            _state.update { prev ->
                val updated = prev.projects.map { proj ->
                    if (proj.id == optimistic.id) remote else proj
                }
                prev.copy(projects = updated, selectedProjectId = remote.id)
            }
            return remote
        }
        return optimistic
    }

    public suspend fun createAutomationFromPrompt(
        client: AntigravityKmpRpcClient?,
        prompt: String,
        projectSlug: String = "ledger-svc",
    ): AutomationItem? {
        val trimmed = prompt.trim()
        if (trimmed.isEmpty()) return null

        val optimistic = AutomationItem(
            id = "auto-${currentTimeMillis()}-${Random.nextInt(100, 999)}",
            title = trimmed.take(64),
            projectSlug = projectSlug,
            scheduleSummary = "$projectSlug · Scheduled · Pro",
            section = AutomationSectionKind.SCHEDULED,
            nextRunText = "Tomorrow, 09:00",
            lastRunText = "Just created",
            needsReview = false,
            isRunningNow = false,
            prompt = trimmed,
            isEnabled = true,
            isScheduleBuiltin = true,
        )

        val previous = _state.value.automations
        _state.update { prev ->
            prev.copy(
                automations = listOf(optimistic) + prev.automations,
                lastCapabilityError = null,
            )
        }

        val remote = performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.SIDECAR_AUTOMATIONS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(automations = previous) } },
        ) { rpc ->
            rpc.createAutomation(prompt = trimmed, projectSlug = projectSlug)
        }

        if (remote != null) {
            _state.update { prev ->
                prev.copy(
                    automations = prev.automations.map { item ->
                        if (item.id == optimistic.id) remote else item
                    },
                )
            }
            return remote
        }
        return optimistic
    }

    public suspend fun runAutomationNow(
        client: AntigravityKmpRpcClient?,
        automationId: String,
    ) {
        val previous = _state.value.automations
        _state.update { prev ->
            prev.copy(
                automations = prev.automations.map { item ->
                    if (item.id == automationId) {
                        item.copy(
                            isRunningNow = true,
                            lastRunText = "Running now...",
                        )
                    } else {
                        item
                    }
                },
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.SIDECAR_AUTOMATIONS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(automations = previous) } },
        ) { rpc ->
            rpc.triggerAutomationNow(automationId)
        }
    }

    public suspend fun resumeAutomation(
        client: AntigravityKmpRpcClient?,
        automationId: String,
    ) {
        val previous = _state.value.automations
        _state.update { prev ->
            prev.copy(
                automations = prev.automations.map { item ->
                    if (item.id == automationId) {
                        item.copy(
                            section = AutomationSectionKind.SCHEDULED,
                            isEnabled = true,
                            nextRunText = if (item.nextRunText.equals("Paused", ignoreCase = true)) {
                                "Tomorrow, 08:00"
                            } else {
                                item.nextRunText
                            },
                            lastRunText = "Resumed",
                        )
                    } else {
                        item
                    }
                },
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.SIDECAR_AUTOMATIONS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(automations = previous) } },
        ) { rpc ->
            rpc.setAutomationPaused(automationId = automationId, paused = false)
        }
    }

    public suspend fun pauseAutomation(
        client: AntigravityKmpRpcClient?,
        automationId: String,
    ) {
        val previous = _state.value.automations
        _state.update { prev ->
            prev.copy(
                automations = prev.automations.map { item ->
                    if (item.id == automationId) {
                        item.copy(
                            section = AutomationSectionKind.PAUSED,
                            isEnabled = false,
                            isRunningNow = false,
                            nextRunText = "Paused",
                            lastRunText = "Paused · just now",
                        )
                    } else {
                        item
                    }
                },
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.SIDECAR_AUTOMATIONS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(automations = previous) } },
        ) { rpc ->
            rpc.setAutomationPaused(automationId = automationId, paused = true)
        }
    }

    public fun selectAutomation(automationId: String) {
        _state.update { it.copy(selectedAutomationId = automationId) }
    }

    public suspend fun updateAutomation(
        client: AntigravityKmpRpcClient?,
        automationId: String,
        title: String,
        prompt: String,
        projectSlug: String,
        section: AutomationSectionKind,
        repeatsLabel: String,
        timeLabel: String,
        modelLabel: String,
    ) {
        val trimmedTitle = title.trim().ifEmpty { "Scheduled automation" }
        val trimmedPrompt = prompt.trim().ifEmpty { trimmedTitle }
        val summary = if (section == AutomationSectionKind.ALWAYS_ON) {
            "$projectSlug · On PR opened · $modelLabel"
        } else {
            "$projectSlug · $repeatsLabel at $timeLabel · $modelLabel"
        }
        val previous = _state.value.automations
        _state.update { prev ->
            prev.copy(
                automations = prev.automations.map { item ->
                    if (item.id == automationId) {
                        item.copy(
                            title = trimmedTitle,
                            prompt = trimmedPrompt,
                            projectSlug = projectSlug,
                            section = section,
                            scheduleSummary = summary,
                            repeatsLabel = "$repeatsLabel · $timeLabel",
                            timeLabel = timeLabel,
                            modelLabel = modelLabel,
                            isScheduleBuiltin = section != AutomationSectionKind.ALWAYS_ON,
                        )
                    } else {
                        item
                    }
                },
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.SIDECAR_AUTOMATIONS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(automations = previous) } },
        ) { rpc ->
            rpc.setAutomationPaused(automationId = automationId, paused = section == AutomationSectionKind.PAUSED)
        }
    }

    public suspend fun deleteAutomation(
        client: AntigravityKmpRpcClient?,
        automationId: String,
    ) {
        val previous = _state.value.automations
        _state.update { prev ->
            val remaining = prev.automations.filterNot { it.id == automationId }
            prev.copy(
                automations = remaining,
                selectedAutomationId = if (prev.selectedAutomationId == automationId) {
                    remaining.firstOrNull()?.id.orEmpty()
                } else {
                    prev.selectedAutomationId
                },
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.SIDECAR_AUTOMATIONS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(automations = previous) } },
        ) { rpc ->
            rpc.setAutomationPaused(automationId = automationId, paused = true)
        }
    }

    public suspend fun retryAutomationRun(
        client: AntigravityKmpRpcClient?,
        automationId: String,
        runId: String,
    ) {
        val previous = _state.value.automations
        _state.update { prev ->
            prev.copy(
                automations = prev.automations.map { item ->
                    if (item.id == automationId) {
                        item.copy(
                            isRunningNow = true,
                            lastRunText = "Retrying now...",
                            recentRuns = item.recentRuns.map { run ->
                                if (run.id == runId) {
                                    run.copy(
                                        status = dev.antigravity.shared.model.AutomationRunStatus.RUNNING,
                                        timestampLabel = "Running · just now",
                                        canRetry = false,
                                    )
                                } else {
                                    run
                                }
                            },
                        )
                    } else {
                        item
                    }
                },
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.SIDECAR_AUTOMATIONS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(automations = previous) } },
        ) { rpc ->
            rpc.triggerAutomationNow(automationId)
        }
    }

    public fun toggleContextCandidate(candidateId: String) {
        _state.update { prev ->
            prev.copy(
                contextCandidates = prev.contextCandidates.map { candidate ->
                    if (candidate.id == candidateId) {
                        candidate.copy(isSelected = !candidate.isSelected)
                    } else {
                        candidate
                    }
                },
            )
        }
    }

    public fun applySelectedContextToComposer() {
        _state.update { prev ->
            val selectedChips = prev.contextCandidates
                .filter { it.isSelected }
                .map { candidate ->
                    ComposerAttachmentChip(
                        id = "chip-${candidate.id}",
                        kind = candidate.attachmentKind,
                        label = candidate.chipLabel,
                        targetUri = candidate.title,
                    )
                }
            val merged = linkedMapOf<String, ComposerAttachmentChip>()
            for (chip in prev.attachedComposerChips) {
                merged[chip.label] = chip
            }
            for (chip in selectedChips) {
                merged.putIfAbsentCompat(chip.label, chip)
            }
            prev.copy(attachedComposerChips = merged.values.toList())
        }
    }

    public fun addComposerChip(chip: ComposerAttachmentChip) {
        _state.update { prev ->
            if (prev.attachedComposerChips.any { it.id == chip.id || (it.targetUri != null && it.targetUri == chip.targetUri && it.label == chip.label) }) {
                prev
            } else {
                prev.copy(attachedComposerChips = prev.attachedComposerChips + chip)
            }
        }
    }

    public fun removeComposerChip(chipId: String) {
        _state.update { prev ->
            prev.copy(
                attachedComposerChips = prev.attachedComposerChips.filterNot { it.id == chipId },
            )
        }
    }

    public fun clearComposerChips() {
        _state.update { it.copy(attachedComposerChips = emptyList()) }
    }

    public fun clearCapabilityError() {
        _state.update { it.copy(lastCapabilityError = null) }
    }

    private fun recordCapabilityError(message: String) {
        _state.update { it.copy(lastCapabilityError = message) }
        onCapabilityError(message)
    }

    private fun MutableMap<String, ComposerAttachmentChip>.putIfAbsentCompat(
        key: String,
        value: ComposerAttachmentChip,
    ) {
        if (!containsKey(key)) put(key, value)
    }
}
