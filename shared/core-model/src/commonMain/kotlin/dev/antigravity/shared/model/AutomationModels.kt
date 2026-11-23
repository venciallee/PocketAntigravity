package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

@Serializable(with = AutomationSectionKindSerializer::class)
public enum class AutomationSectionKind(public val displayTitle: String) {
    SCHEDULED("SCHEDULED"),
    ALWAYS_ON("ALWAYS ON"),
    PAUSED("PAUSED"),
}

public object AutomationSectionKindSerializer : ResilientEnumSerializer<AutomationSectionKind>(
    serialName = "dev.antigravity.shared.model.AutomationSectionKind",
    entriesProvider = { AutomationSectionKind.entries },
    fallbackProvider = { AutomationSectionKind.SCHEDULED },
    extraMatcher = { raw ->
        val norm = normalizeResilientEnumToken(raw)
        AutomationSectionKind.entries.firstOrNull { normalizeResilientEnumToken(it.displayTitle) == norm }
    },
)

@Serializable(with = SidecarManageActionSerializer::class)
public enum class SidecarManageAction(public val wireValue: String) {
    UNSPECIFIED("SIDECAR_ACTION_UNSPECIFIED"),
    DISABLE("SIDECAR_ACTION_DISABLE"),
    ENABLE("SIDECAR_ACTION_ENABLE"),
    DELETE("SIDECAR_ACTION_DELETE"),
    RESTART("SIDECAR_ACTION_RESTART"),
    CREATE("SIDECAR_ACTION_CREATE"),
    SET_PROJECT("SIDECAR_ACTION_SET_PROJECT"),
    UPDATE("SIDECAR_ACTION_UPDATE"),
    SET_ALL_PROJECTS("SIDECAR_ACTION_SET_ALL_PROJECTS"),
    UPDATE_ARGS("SIDECAR_ACTION_UPDATE_ARGS"),
    RUN_NOW("SIDECAR_ACTION_RUN_NOW"),
}

public object SidecarManageActionSerializer : ResilientEnumSerializer<SidecarManageAction>(
    serialName = "dev.antigravity.shared.model.SidecarManageAction",
    entriesProvider = { SidecarManageAction.entries },
    fallbackProvider = { SidecarManageAction.UNSPECIFIED },
    extraMatcher = { raw ->
        SidecarManageAction.entries.firstOrNull { it.wireValue.equals(raw, ignoreCase = true) }
    },
)

@Serializable
public data class SidecarRunEvent(
    public val timestampMs: Long,
    public val error: String? = null,
    public val conversationId: String? = null,
    public val prompt: String? = null,
)

@Serializable(with = AutomationRunStatusSerializer::class)
public enum class AutomationRunStatus(public val displayTitle: String) {
    SUCCEEDED("Succeeded"),
    NEEDS_REVIEW("Needs review"),
    FAILED("Failed"),
    RUNNING("Running"),
}

public object AutomationRunStatusSerializer : ResilientEnumSerializer<AutomationRunStatus>(
    serialName = "dev.antigravity.shared.model.AutomationRunStatus",
    entriesProvider = { AutomationRunStatus.entries },
    fallbackProvider = { AutomationRunStatus.SUCCEEDED },
    extraMatcher = { raw ->
        val norm = normalizeResilientEnumToken(raw)
        AutomationRunStatus.entries.firstOrNull { normalizeResilientEnumToken(it.displayTitle) == norm }
    },
)

@Serializable
public data class AutomationRunRecord(
    public val id: String,
    public val status: AutomationRunStatus,
    public val timestampLabel: String,
    public val summary: String,
    public val canRetry: Boolean = status == AutomationRunStatus.FAILED,
)

@Serializable
public data class AutomationItem(
    public val id: String,
    public val title: String,
    public val projectSlug: String,
    public val scheduleSummary: String,
    public val section: AutomationSectionKind,
    public val nextRunText: String,
    public val lastRunText: String,
    public val needsReview: Boolean = false,
    public val isRunningNow: Boolean = false,
    public val descriptionText: String = "",
    public val prompt: String = title,
    public val cronExpression: String = "",
    public val projectId: String? = null,
    public val allProjects: Boolean = false,
    public val modelLabel: String? = null,
    public val lastRunCascadeId: String? = null,
    public val lastError: String? = null,
    public val isEnabled: Boolean = section != AutomationSectionKind.PAUSED,
    public val isScheduleBuiltin: Boolean = section != AutomationSectionKind.ALWAYS_ON,
    public val originInstanceUuid: String? = null,
    public val repeatsLabel: String = "Every day · 2:00 AM",
    public val timeLabel: String = "2:00 AM",
    public val timezoneLabel: String = "GMT+8:00",
    public val recentRuns: List<AutomationRunRecord> = emptyList(),
)

/**
 * Category entries in the Add Context popover & picker (`UE08`).
 */
@Serializable(with = ContextCandidateCategorySerializer::class)
public enum class ContextCandidateCategory(public val displayTitle: String) {
    FILES("Files"),
    FOLDER("Folder"),
    MENTIONS("Mentions"),
    ACTIONS("Actions"),
    DRIVE("Drive"),
    SKILLS("Skills"),
}

public object ContextCandidateCategorySerializer : ResilientEnumSerializer<ContextCandidateCategory>(
    serialName = "dev.antigravity.shared.model.ContextCandidateCategory",
    entriesProvider = { ContextCandidateCategory.entries },
    fallbackProvider = { ContextCandidateCategory.FILES },
    extraMatcher = { raw ->
        val norm = normalizeResilientEnumToken(raw)
        ContextCandidateCategory.entries.firstOrNull { normalizeResilientEnumToken(it.displayTitle) == norm }
    },
)

/**
 * Selectable file, folder, mention, action, drive, or skill item in Add Context (`UE08`).
 */
@Serializable
public data class ContextCandidateItem(
    public val id: String,
    public val category: ContextCandidateCategory,
    public val title: String,
    public val subtitle: String,
    public val chipLabel: String,
    public val isActionTrigger: Boolean = false,
    public val isSelected: Boolean = false,
) {
    public val attachmentKind: ComposerAttachmentChip.Kind
        get() = when (category) {
            ContextCandidateCategory.FILES -> ComposerAttachmentChip.Kind.FILE_MENTION
            ContextCandidateCategory.FOLDER -> ComposerAttachmentChip.Kind.FOLDER
            ContextCandidateCategory.MENTIONS ->
                if (title.lowercase().contains("terminal")) ComposerAttachmentChip.Kind.TERMINAL_LOG
                else ComposerAttachmentChip.Kind.CONVERSATION_MENTION
            ContextCandidateCategory.ACTIONS -> ComposerAttachmentChip.Kind.WORKFLOW
            ContextCandidateCategory.DRIVE -> ComposerAttachmentChip.Kind.FILE_MENTION
            ContextCandidateCategory.SKILLS -> ComposerAttachmentChip.Kind.SKILL
        }
}
