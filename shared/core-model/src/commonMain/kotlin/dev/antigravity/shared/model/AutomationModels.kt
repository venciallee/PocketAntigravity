package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

@Serializable
public enum class AutomationSectionKind(public val displayTitle: String) {
    SCHEDULED("SCHEDULED"),
    ALWAYS_ON("ALWAYS ON"),
    PAUSED("PAUSED"),
}

@Serializable
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

@Serializable
public data class SidecarRunEvent(
    public val timestampMs: Long,
    public val error: String? = null,
    public val conversationId: String? = null,
    public val prompt: String? = null,
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
)
