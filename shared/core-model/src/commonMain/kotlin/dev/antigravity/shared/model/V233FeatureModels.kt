package dev.antigravity.shared.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlin.math.roundToInt

@Serializable
public data class ModelUsageQuota(
    public val planTierLabel: String = "Google AI Pro",
    public val usedPercent: Double = 0.0,
    public val refreshCountdownLabel: String = "",
    public val creditsRemaining: Int? = null,
    public val isQuotaWarning: Boolean = false,
    public val updatedAtEpochMs: Long = 0L,
    public val geminiWeeklyRemaining: Double = 1.0,
    public val geminiFiveHourRemaining: Double = 1.0,
    public val partnerWeeklyRemaining: Double = 1.0,
    public val partnerFiveHourRemaining: Double = 1.0,
    public val aiCreditOveragesEnabled: Boolean = false,
) {
    public val geminiWeeklyPercent: Int get() = (geminiWeeklyRemaining.coerceIn(0.0, 1.0) * 100.0).roundToInt()
    public val geminiFiveHourPercent: Int get() = (geminiFiveHourRemaining.coerceIn(0.0, 1.0) * 100.0).roundToInt()
    public val partnerWeeklyPercent: Int get() = (partnerWeeklyRemaining.coerceIn(0.0, 1.0) * 100.0).roundToInt()
    public val partnerFiveHourPercent: Int get() = (partnerFiveHourRemaining.coerceIn(0.0, 1.0) * 100.0).roundToInt()
}

@Serializable(with = PermissionRuleListKindSerializer::class)
public enum class PermissionRuleListKind {
    ALLOW,
    DENY,
}

public object PermissionRuleListKindSerializer : ResilientEnumSerializer<PermissionRuleListKind>(
    serialName = "dev.antigravity.shared.model.PermissionRuleListKind",
    entriesProvider = { PermissionRuleListKind.entries },
    fallbackProvider = { PermissionRuleListKind.DENY },
)

@Serializable(with = PermissionRuleActionSerializer::class)
public enum class PermissionRuleAction {
    COMMAND,
    FILE_READ,
    FILE_WRITE,
    MCP,
    BROWSER,
}

public object PermissionRuleActionSerializer : ResilientEnumSerializer<PermissionRuleAction>(
    serialName = "dev.antigravity.shared.model.PermissionRuleAction",
    entriesProvider = { PermissionRuleAction.entries },
    fallbackProvider = { PermissionRuleAction.COMMAND },
)

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
    public val modifiedFiles: List<String> = emptyList(),
    public val artifacts: List<ArtifactSnapshot> = emptyList(),
    public val documentLinks: List<String> = emptyList(),
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

@Serializable(with = DiffCompareModeSerializer::class)
public enum class DiffCompareMode(public val displayTitle: String) {
    TURN("This Turn"),
    WORKING_TREE("Working Tree"),
    STAGED("Staged"),
    BRANCH_BASE("vs Base Branch"),
}

public object DiffCompareModeSerializer : ResilientEnumSerializer<DiffCompareMode>(
    serialName = "dev.antigravity.shared.model.DiffCompareMode",
    entriesProvider = { DiffCompareMode.entries },
    fallbackProvider = { DiffCompareMode.TURN },
    extraMatcher = { raw ->
        val norm = normalizeResilientEnumToken(raw)
        when (norm) {
            "perturn", "turn", "thisturn" -> DiffCompareMode.TURN
            "uncommitted", "workingtree" -> DiffCompareMode.WORKING_TREE
            "staged", "agentedits" -> DiffCompareMode.STAGED
            "branch", "branchbase", "vsbasebranch" -> DiffCompareMode.BRANCH_BASE
            else -> null
        }
    },
)

@Serializable(with = GitFileStatusLetterSerializer::class)
public enum class GitFileStatusLetter(public val code: String) {
    MODIFIED("M"),
    ADDED("A"),
    DELETED("D"),
    RENAMED("R"),
    UNTRACKED("U"),
}

public object GitFileStatusLetterSerializer : ResilientEnumSerializer<GitFileStatusLetter>(
    serialName = "dev.antigravity.shared.model.GitFileStatusLetter",
    entriesProvider = { GitFileStatusLetter.entries },
    fallbackProvider = { GitFileStatusLetter.MODIFIED },
    extraMatcher = { raw ->
        val upper = raw.trim().uppercase()
        GitFileStatusLetter.entries.firstOrNull { it.code == upper }
    },
)

@Serializable
public data class GitCommitDraft(
    public val message: String = "",
    public val amendLastCommit: Boolean = false,
    public val pushAfterCommit: Boolean = false,
    public val includeUnstaged: Boolean = true,
)

@Serializable
public data class GitCommitResult(
    public val commitHash: String,
    public val summary: String,
    public val pushed: Boolean = false,
    public val branchName: String = "main",
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
    public val missingCommandHint: String? = null,
    public val oauthConnected: Boolean = true,
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
    public val provider: String = name,
    public val isFeaturedPartner: Boolean = false,
    public val accountSignedIn: Boolean = false,
    public val mcpStartupError: String? = null,
    public val suggestedPrompts: List<String> = emptyList(),
)

@Serializable
public data class LifecycleHookItem(
    public val id: String,
    public val event: String,
    public val command: String,
    public val isEnabled: Boolean = true,
    public val matcher: String = "*",
    public val timeoutSeconds: Int = 60,
)

@Serializable
public data class CustomizationsCatalog(
    public val skills: List<SkillSummary> = emptyList(),
    public val rules: List<RuleSummary> = emptyList(),
    public val mcpServers: List<McpServerStatusItem> = emptyList(),
    public val plugins: List<PluginCatalogItem> = emptyList(),
    public val hooks: List<LifecycleHookItem> = emptyList(),
    public val customAgents: List<String> = listOf("Default"),
) {
    public companion object {
        public val defaultCatalog: CustomizationsCatalog = CustomizationsCatalog(
            skills = listOf(
                SkillSummary(name = "antigravity-doc-sync", description = "Auto-sync Antigravity 2.0 docs & ESDD deltas", scope = "Workspace"),
                SkillSummary(name = "go-testing", description = "Table-driven Go tests & fake clock patterns", scope = "Workspace"),
                SkillSummary(name = "generative_ui", description = "Interactive HTML widgets & data diagrams", scope = "Global"),
            ),
            rules = listOf(
                RuleSummary(name = "AGENTS.md", scope = "Workspace", preview = "KMP shared core parity & 4-gate ESDD verification."),
            ),
            mcpServers = listOf(
                McpServerStatusItem(name = "github", transport = "remote-oauth", isConnected = true, toolCount = 18, oauthConnected = true),
                McpServerStatusItem(name = "postgres-dev", transport = "stdio", isConnected = true, toolCount = 6, oauthConnected = true),
            ),
            plugins = listOf(
                PluginCatalogItem(
                    id = "plugin-github",
                    name = "GitHub",
                    summary = "Repositories, PR status pills, Issues & Actions",
                    isInstalled = true,
                    isEnabled = true,
                    provider = "GitHub",
                    isFeaturedPartner = true,
                    accountSignedIn = true,
                    suggestedPrompts = listOf("Review open PRs with failing checks"),
                ),
                PluginCatalogItem(
                    id = "plugin-figma",
                    name = "Figma",
                    summary = "Inspect design frames, tokens & screenshots",
                    isInstalled = false,
                    isEnabled = false,
                    provider = "Figma",
                    isFeaturedPartner = true,
                    accountSignedIn = false,
                ),
            ),
            hooks = listOf(
                LifecycleHookItem(
                    id = "hook-pre-tool",
                    event = "PreToolUse",
                    command = "scripts/verify-safe-cmd.sh",
                    isEnabled = true,
                    matcher = "run_command",
                    timeoutSeconds = 30,
                ),
            ),
            customAgents = listOf("Default", "go-reviewer", "release-captain"),
        )
    }
}

@Serializable(with = InterfaceLayoutModeSerializer::class)
public enum class InterfaceLayoutMode(public val displayTitle: String) {
    COMPACT("Compact"),
    COMFORTABLE("Comfortable"),
}

public object InterfaceLayoutModeSerializer : ResilientEnumSerializer<InterfaceLayoutMode>(
    serialName = "dev.antigravity.shared.model.InterfaceLayoutMode",
    entriesProvider = { InterfaceLayoutMode.entries },
    fallbackProvider = { InterfaceLayoutMode.COMFORTABLE },
)

@Serializable(with = AppThemePresetSerializer::class)
public enum class AppThemePreset(public val displayTitle: String) {
    OBSIDIAN("Matte Obsidian"),
    NORD("Nord"),
    EVERFOREST_DARK("Everforest Dark"),
    EVERFOREST_LIGHT("Everforest Light"),
}

public object AppThemePresetSerializer : ResilientEnumSerializer<AppThemePreset>(
    serialName = "dev.antigravity.shared.model.AppThemePreset",
    entriesProvider = { AppThemePreset.entries },
    fallbackProvider = { AppThemePreset.OBSIDIAN },
)

@Serializable(with = AppAppearanceModeSerializer::class)
public enum class AppAppearanceMode(public val displayTitle: String) {
    SYSTEM("System"),
    DARK("Dark"),
    LIGHT("Light"),
}

public object AppAppearanceModeSerializer : ResilientEnumSerializer<AppAppearanceMode>(
    serialName = "dev.antigravity.shared.model.AppAppearanceMode",
    entriesProvider = { AppAppearanceMode.entries },
    fallbackProvider = { AppAppearanceMode.SYSTEM },
)

@Serializable
public data class AppAppearancePreferences(
    public val layoutMode: InterfaceLayoutMode = InterfaceLayoutMode.COMFORTABLE,
    public val appearanceMode: AppAppearanceMode = AppAppearanceMode.SYSTEM,
    public val theme: AppThemePreset = AppThemePreset.OBSIDIAN,
    public val collapsedProjectIds: Set<String> = emptySet(),
    public val globalPermissionPreset: AgentPermissionPreset = AgentPermissionPreset.DEFAULT_POLICY,
    public val useDynamicColor: Boolean = false,
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
    public constructor(
        turnIndex: Int,
        title: String,
        stepStartIndex: Int,
        stepEndIndex: Int,
        changedFileCount: Int = 0,
    ) : this(
        turnIndex = turnIndex,
        startStepIndex = stepStartIndex,
        endStepIndex = stepEndIndex,
        userPromptPreview = title,
        changedFileCount = changedFileCount,
    )

    public val id: String get() = "turn-$turnIndex"
    public val title: String get() = userPromptPreview
    public val stepStartIndex: Int get() = startStepIndex
    public val stepEndIndex: Int get() = endStepIndex
}

// MARK: - Jupyter Notebook (.ipynb) & Image Region Comments (v2.27 - v2.33)

@Serializable(with = JupyterCellKindSerializer::class)
public enum class JupyterCellKind {
    MARKDOWN,
    CODE,
    RAW,
}

public object JupyterCellKindSerializer : ResilientEnumSerializer<JupyterCellKind>(
    serialName = "dev.antigravity.shared.model.JupyterCellKind",
    entriesProvider = { JupyterCellKind.entries },
    fallbackProvider = { JupyterCellKind.RAW },
)

@Serializable
public data class JupyterCellOutput(
    public val id: String,
    public val text: String? = null,
    public val imageBase64Png: String? = null,
    public val errorName: String? = null,
    public val errorValue: String? = null,
)

@Serializable
public data class JupyterNotebookCell(
    public val id: String,
    public val cellType: JupyterCellKind,
    public val executionCount: Int? = null,
    public val source: String,
    public val outputs: List<JupyterCellOutput> = emptyList(),
)

@Serializable
public data class JupyterNotebookDocument(
    public val kernelName: String = "python3",
    public val cells: List<JupyterNotebookCell> = emptyList(),
) {
    public companion object {
        private val parserJson = Json { ignoreUnknownKeys = true }

        /**
         * Pure KMP parser for standard `.ipynb` JSON documents into [JupyterNotebookDocument].
         */
        public fun parse(jsonString: String): JupyterNotebookDocument? {
            val root = runCatching { parserJson.parseToJsonElement(jsonString) as? JsonObject }.getOrNull()
                ?: return null
            val metadata = root["metadata"] as? JsonObject
            val kernelspec = metadata?.get("kernelspec") as? JsonObject
            val kernelName = (kernelspec?.get("display_name") as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
                ?: (kernelspec?.get("name") as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
                ?: "python3"

            val rawCells = root["cells"] as? JsonArray ?: JsonArray(emptyList())
            val parsedCells = rawCells.mapIndexedNotNull { idx, cellEl ->
                val cell = cellEl as? JsonObject ?: return@mapIndexedNotNull null
                val typeRaw = (cell["cell_type"] as? JsonPrimitive)?.contentOrNull ?: "code"
                val cellType = decodeResilientEnumOrDefault(
                    raw = typeRaw,
                    values = JupyterCellKind.entries,
                    fallback = JupyterCellKind.CODE,
                )
                val execCount = (cell["execution_count"] as? JsonPrimitive)?.intOrNull
                val source = joinJsonStringOrArray(cell["source"]) ?: ""
                val rawOutputs = cell["outputs"] as? JsonArray ?: JsonArray(emptyList())
                val outputs = rawOutputs.mapIndexedNotNull { oIdx, outEl ->
                    val out = outEl as? JsonObject ?: return@mapIndexedNotNull null
                    val outType = (out["output_type"] as? JsonPrimitive)?.contentOrNull?.lowercase().orEmpty()
                    when {
                        outType == "stream" -> JupyterCellOutput(
                            id = "$idx-o-$oIdx",
                            text = joinJsonStringOrArray(out["text"]),
                        )
                        outType == "error" -> JupyterCellOutput(
                            id = "$idx-o-$oIdx",
                            errorName = (out["ename"] as? JsonPrimitive)?.contentOrNull,
                            errorValue = (out["evalue"] as? JsonPrimitive)?.contentOrNull,
                        )
                        out["data"] is JsonObject -> {
                            val dataObj = out["data"] as JsonObject
                            JupyterCellOutput(
                                id = "$idx-o-$oIdx",
                                text = joinJsonStringOrArray(dataObj["text/plain"]),
                                imageBase64Png = (dataObj["image/png"] as? JsonPrimitive)?.contentOrNull,
                            )
                        }
                        else -> null
                    }
                }
                JupyterNotebookCell(
                    id = (cell["id"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() } ?: "cell-$idx",
                    cellType = cellType,
                    executionCount = execCount,
                    source = source,
                    outputs = outputs,
                )
            }
            return JupyterNotebookDocument(kernelName = kernelName, cells = parsedCells)
        }

        private fun joinJsonStringOrArray(element: kotlinx.serialization.json.JsonElement?): String? = when (element) {
            is JsonPrimitive -> element.contentOrNull
            is JsonArray -> element.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }.joinToString("")
            else -> null
        }
    }
}

@Serializable
public data class ImageRegionComment(
    public val id: String,
    public val artifactPath: String,
    public val normalizedX: Double,
    public val normalizedY: Double,
    public val normalizedWidth: Double,
    public val normalizedHeight: Double,
    public val body: String,
    public val author: String = "You",
    public val createdAtEpochMs: Long = 0L,
)
