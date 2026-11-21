package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

@Serializable
public data class ModelUsageQuota(
    public val planTierLabel: String = "Google AI Pro",
    public val usedPercent: Double = 0.0,
    public val refreshCountdownLabel: String = "",
    public val creditsRemaining: Int? = null,
    public val isQuotaWarning: Boolean = false,
    public val updatedAtEpochMs: Long = 0L,
)

@Serializable
public enum class PermissionRuleListKind {
    ALLOW,
    DENY,
}

@Serializable
public enum class PermissionRuleAction {
    COMMAND,
    FILE_READ,
    FILE_WRITE,
    MCP,
    BROWSER,
}

@Serializable
public data class PermissionRuleEntry(
    public val id: String,
    public val list: PermissionRuleListKind,
    public val action: PermissionRuleAction,
    public val target: String,
    public val note: String? = null,
)

@Serializable
public data class SubagentPayload(
    public val subagentId: String,
    public val role: String,
    public val typeName: String,
    public val modelLabel: String = "Gemini 4 Hydrogen",
    public val status: CortexStepStatus = CortexStepStatus.IN_PROGRESS,
    public val summary: String = "",
    public val waitingApprovalTitle: String? = null,
) {
    public val id: String get() = subagentId
}

@Serializable
public data class WorkflowPhaseItem(
    public val id: String,
    public val name: String,
    public val isCompleted: Boolean = false,
    public val isActive: Boolean = false,
    public val durationLabel: String? = null,
)

@Serializable
public data class DynamicWorkflowPayload(
    public val workflowId: String,
    public val description: String,
    public val pythonScript: String,
    public val currentPhase: String,
    public val completedAgents: Int,
    public val totalAgents: Int,
    public val phases: List<WorkflowPhaseItem> = emptyList(),
)

@Serializable
public data class SwarmMemberItem(
    public val name: String,
    public val role: String,
    public val status: CortexStepStatus = CortexStepStatus.IN_PROGRESS,
    public val currentTask: String? = null,
) {
    public val id: String get() = name
}

@Serializable
public data class SwarmBoardPost(
    public val id: String,
    public val author: String,
    public val channel: String = "general",
    public val body: String,
    public val timestampLabel: String = "just now",
)

@Serializable
public data class SwarmBoardPayload(
    public val swarmId: String,
    public val title: String,
    public val members: List<SwarmMemberItem> = emptyList(),
    public val posts: List<SwarmBoardPost> = emptyList(),
)

@Serializable
public data class McpToolCallPayload(
    public val serverName: String,
    public val toolName: String,
    public val pluginName: String? = null,
    public val argumentsPreview: String = "{}",
    public val resultPreview: String? = null,
    public val isError: Boolean = false,
)

@Serializable
public data class BackgroundTaskItem(
    public val id: String,
    public val title: String,
    public val commandOrKind: String,
    public val status: CortexStepStatus = CortexStepStatus.IN_PROGRESS,
    public val elapsedLabel: String = "",
)

@Serializable
public data class ConversationGoalItem(
    public val id: String,
    public val title: String,
    public val isCompleted: Boolean = false,
)

@Serializable
public data class GitHubPullRequestInfo(
    public val number: Int,
    public val title: String,
    public val url: String,
    public val state: String = "OPEN",
    public val checksStatus: String = "PASSING",
) {
    public val id: String get() = "$number-$url"
}

@Serializable
public data class ConversationOverviewSnapshot(
    public val goals: List<ConversationGoalItem> = emptyList(),
    public val activeSubagents: List<SubagentPayload> = emptyList(),
    public val backgroundTasks: List<BackgroundTaskItem> = emptyList(),
    public val linkedPullRequests: List<GitHubPullRequestInfo> = emptyList(),
    public val changedFilesCount: Int = 0,
    public val totalAdditions: Int = 0,
    public val totalDeletions: Int = 0,
)

@Serializable
public data class SideQuestionMessage(
    public val id: String,
    public val isUser: Boolean,
    public val text: String,
    public val createdAtEpochMs: Long = 0L,
)

@Serializable
public data class SideQuestionThread(
    public val parentCascadeId: String = "",
    public val messages: List<SideQuestionMessage> = emptyList(),
    public val isLoading: Boolean = false,
)

@Serializable
public enum class DiffCompareMode(public val displayTitle: String) {
    TURN("This Turn"),
    WORKING_TREE("Working Tree"),
    STAGED("Staged"),
    BRANCH_BASE("vs Base Branch"),
}

@Serializable
public enum class GitFileStatusLetter(public val code: String) {
    MODIFIED("M"),
    ADDED("A"),
    DELETED("D"),
    RENAMED("R"),
    UNTRACKED("U"),
}

@Serializable
public data class GitCommitDraft(
    public val message: String = "",
    public val amendLastCommit: Boolean = false,
    public val pushAfterCommit: Boolean = false,
)

@Serializable
public data class GitCommitResult(
    public val commitHash: String,
    public val summary: String,
    public val pushed: Boolean = false,
)

@Serializable
public data class VoiceTranscriptTurn(
    public val id: String,
    public val isUser: Boolean,
    public val text: String,
)

@Serializable
public data class VoiceCallTranscriptSummary(
    public val id: String,
    public val durationLabel: String,
    public val voiceName: String = "Kore",
    public val summaryText: String,
    public val turns: List<VoiceTranscriptTurn> = emptyList(),
)

@Serializable
public data class VoiceModeState(
    public val isActive: Boolean = false,
    public val isMuted: Boolean = false,
    public val selectedVoice: String = "Kore",
    public val liveTranscript: String = "",
    public val statusLabel: String = "Ready",
)

@Serializable
public data class SkillSummary(
    public val name: String,
    public val description: String,
    public val scope: String = "Workspace",
    public val isEnabled: Boolean = true,
) {
    public val id: String get() = name
}

@Serializable
public data class RuleSummary(
    public val name: String,
    public val scope: String = "Workspace",
    public val preview: String,
    public val isActive: Boolean = true,
) {
    public val id: String get() = name
}

@Serializable
public data class McpServerStatusItem(
    public val name: String,
    public val transport: String = "stdio",
    public val isConnected: Boolean = true,
    public val toolCount: Int = 0,
    public val errorMessage: String? = null,
) {
    public val id: String get() = name
}

@Serializable
public data class PluginCatalogItem(
    public val id: String,
    public val name: String,
    public val summary: String,
    public val isInstalled: Boolean = false,
    public val isEnabled: Boolean = false,
)

@Serializable
public data class LifecycleHookItem(
    public val id: String,
    public val event: String,
    public val command: String,
    public val isEnabled: Boolean = true,
)

@Serializable
public data class CustomizationsCatalog(
    public val skills: List<SkillSummary> = emptyList(),
    public val rules: List<RuleSummary> = emptyList(),
    public val mcpServers: List<McpServerStatusItem> = emptyList(),
    public val plugins: List<PluginCatalogItem> = emptyList(),
    public val hooks: List<LifecycleHookItem> = emptyList(),
)

@Serializable
public enum class InterfaceLayoutMode(public val displayTitle: String) {
    COMPACT("Compact"),
    COMFORTABLE("Comfortable"),
}

@Serializable
public enum class AppThemePreset(public val displayTitle: String) {
    OBSIDIAN("Matte Obsidian"),
    NORD("Nord"),
    EVERFOREST_DARK("Everforest Dark"),
    EVERFOREST_LIGHT("Everforest Light"),
}

@Serializable
public enum class AppAppearanceMode(public val displayTitle: String) {
    SYSTEM("System"),
    DARK("Dark"),
    LIGHT("Light"),
}

@Serializable
public data class AppAppearancePreferences(
    public val layoutMode: InterfaceLayoutMode = InterfaceLayoutMode.COMFORTABLE,
    public val appearanceMode: AppAppearanceMode = AppAppearanceMode.SYSTEM,
    public val theme: AppThemePreset = AppThemePreset.OBSIDIAN,
    public val collapsedProjectIds: Set<String> = emptySet(),
    public val globalPermissionPreset: AgentPermissionPreset = AgentPermissionPreset.DEFAULT_POLICY,
)

@Serializable
public data class QueuedMessageItem(
    public val id: String,
    public val text: String,
    public val attachments: List<ComposerAttachmentChip> = emptyList(),
    public val createdAtEpochMs: Long = 0L,
)

@Serializable
public data class ConversationTurnSummary(
    public val turnIndex: Int,
    public val startStepIndex: Int,
    public val endStepIndex: Int,
    public val userPromptPreview: String,
    public val changedFileCount: Int = 0,
) {
    public val id: String get() = "turn-$turnIndex"
}
