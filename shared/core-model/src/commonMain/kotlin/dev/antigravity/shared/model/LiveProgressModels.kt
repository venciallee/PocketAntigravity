package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

/**
 * Platform-neutral live task execution phase shared by iOS `ActivityKit` Live Activities
 * and Android 16 `NotificationCompat.ProgressStyle` promoted Live Updates (`UE13`).
 */
@Serializable(with = LiveProgressPhaseSerializer::class)
public enum class LiveProgressPhase {
    RUNNING,
    WAITING_APPROVAL,
    COMPLETED,
}

public object LiveProgressPhaseSerializer : ResilientEnumSerializer<LiveProgressPhase>(
    serialName = "dev.antigravity.shared.model.LiveProgressPhase",
    entriesProvider = { LiveProgressPhase.entries },
    fallbackProvider = { LiveProgressPhase.RUNNING },
)

/**
 * Compact per-agent row shown inside expanded multi-agent Live Update / Lock Screen cards.
 */
@Serializable
public data class LiveProgressAgentSummary(
    public val id: String,
    public val title: String,
    public val subtitle: String,
    public val phase: LiveProgressPhase,
    public val trailingLabel: String,
)

/**
 * Platform-neutral snapshot driving both iOS Live Activities and Android 16 promoted Live Updates (`UE13`).
 */
@Serializable
public data class LiveProgressSnapshot(
    public val cascadeId: String,
    public val cascadeTitle: String,
    public val hostName: String,
    public val workspaceName: String,
    public val branchName: String,
    public val phase: LiveProgressPhase,
    public val currentStepIndex: Int,
    public val totalSteps: Int,
    public val activeToolAction: String,
    public val pendingApprovalCommand: String? = null,
    public val elapsedSeconds: Int = 0,
    public val additions: Int = 0,
    public val deletions: Int = 0,
    public val multiAgentItems: List<LiveProgressAgentSummary> = emptyList(),
)
