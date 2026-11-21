package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

/**
 * Maps to `exa.cortex_pb.CortexStepStatus` (binary field 4 on `gemini_coder.Step`).
 */
@Serializable
public enum class CortexStepStatus(public val rawValue: Int) {
    UNSPECIFIED(0),
    PENDING(1),
    IN_PROGRESS(2),
    DONE(3),
    ERROR(4),
    CANCELLED(5),
    BLOCKED(7),
    WAITING(9);

    public val jsonName: String
        get() = when (this) {
            UNSPECIFIED -> "CORTEX_STEP_STATUS_UNSPECIFIED"
            PENDING -> "CORTEX_STEP_STATUS_PENDING"
            IN_PROGRESS -> "CORTEX_STEP_STATUS_IN_PROGRESS"
            DONE -> "CORTEX_STEP_STATUS_DONE"
            ERROR -> "CORTEX_STEP_STATUS_ERROR"
            CANCELLED -> "CORTEX_STEP_STATUS_CANCELLED"
            BLOCKED -> "CORTEX_STEP_STATUS_BLOCKED"
            WAITING -> "CORTEX_STEP_STATUS_WAITING"
        }

    public val displayBadgeText: String
        get() = when (this) {
            UNSPECIFIED -> "IDLE"
            PENDING -> "QUEUED"
            IN_PROGRESS -> "RUNNING"
            DONE -> "DONE"
            ERROR -> "ERROR"
            CANCELLED -> "STOPPED"
            BLOCKED -> "BLOCKED"
            WAITING -> "WAITING"
        }

    public companion object {
        public fun fromRaw(raw: Int): CortexStepStatus =
            entries.firstOrNull { it.rawValue == raw } ?: UNSPECIFIED

        public fun fromJsonName(jsonName: String): CortexStepStatus {
            entries.firstOrNull { it.jsonName == jsonName }?.let { return it }
            val upper = jsonName.trim().uppercase()
            return when {
                upper.contains("WAITING") || upper.contains("NEEDS_USER") ||
                    upper.contains("APPROVAL") || upper.contains("PAUSED") -> WAITING
                upper.contains("BLOCKED") -> BLOCKED
                upper.contains("RUNNING") || upper.contains("IN_PROGRESS") ||
                    upper.contains("GENERAT") || upper.contains("THINK") ||
                    upper.contains("PROCESS") || upper.contains("WORK") ||
                    upper.contains("ACTIVE") || upper.contains("BUSY") ||
                    upper.contains("STREAMING") || upper.contains("EXECUTING") -> IN_PROGRESS
                upper.contains("PENDING") || upper.contains("QUEUED") -> PENDING
                upper.contains("ERROR") || upper.contains("FAIL") -> ERROR
                upper.contains("CANCEL") || upper.contains("ABORT") ||
                    upper.contains("STOP") || upper.contains("INTERRUPT") -> CANCELLED
                upper.contains("DONE") || upper.contains("COMPLETE") ||
                    upper.contains("FINISH") -> DONE
                else -> UNSPECIFIED
            }
        }

        /**
         * Maps upstream numeric `CascadeRunStatus` enum values:
         * `0 = UNSPECIFIED`, `1 = IDLE`, `2 = RUNNING`, `3 = WAITING_FOR_USER`, `4 = CANCELLED`.
         */
        public fun fromCascadeRunStatusCode(code: Int): CortexStepStatus = when (code) {
            2 -> IN_PROGRESS
            3 -> WAITING
            4 -> CANCELLED
            else -> UNSPECIFIED
        }
    }
}

/**
 * Maps to `exa.cortex_pb.CortexStepType` (binary field 1 on `gemini_coder.Step`).
 */
@Serializable
public enum class CortexStepType(public val rawValue: Int) {
    UNSPECIFIED(0),
    CODE_ACTION(5),
    VIEW_FILE(8),
    LIST_DIRECTORY(9),
    USER_INPUT(14),
    PLANNER_RESPONSE(15),
    GENERATE_IMAGE(17),
    RUN_COMMAND(21),
    CHECKPOINT(23),
    COMMAND_STATUS(28),
    READ_URL_CONTENT(31),
    VIEW_CONTENT_CHUNK(32),
    SEARCH(33),
    WORKSPACE_API(47),
    TASK_BOUNDARY(81),
    NOTIFY_USER(82),
    CODE_ACKNOWLEDGEMENT(83),
    BROWSER_SUBAGENT(85),
    EPHEMERAL_MESSAGE(90),
    CONVERSATION_HISTORY(98),
    KNOWLEDGE_ARTIFACTS(99),
    SEND_COMMAND_INPUT(100),
    SUBAGENT_INVOCATION(130),
    DYNAMIC_WORKFLOW(131),
    SWARM_BOARD(132),
    MCP_TOOL_CALL(133),
    BACKGROUND_TASK(134),
    SIDE_QUESTION(135);

    public val jsonName: String
        get() = "CORTEX_STEP_TYPE_$name"

    public val isGroupableEvidenceStep: Boolean
        get() = when (this) {
            CODE_ACTION, VIEW_FILE, LIST_DIRECTORY, SEARCH, VIEW_CONTENT_CHUNK -> true
            else -> false
        }

    public companion object {
        public fun fromRaw(raw: Int): CortexStepType =
            entries.firstOrNull { it.rawValue == raw } ?: UNSPECIFIED
    }
}

@Serializable
public enum class TaskChecklistStatus {
    DONE,
    IN_PROGRESS,
    WAITING,
    PENDING,
}

@Serializable
public data class TaskChecklistItem(
    public val id: String,
    public val title: String,
    public val status: TaskChecklistStatus,
    public val trailingBadge: String? = null,
)

@Serializable
public data class TaskBoundaryPayload(
    public val taskName: String,
    public val taskStatus: String,
    public val taskSummary: String,
    public val completedCount: Int = 4,
    public val totalCount: Int = 7,
    public val elapsedLabel: String = "2m 41s",
    public val checklist: List<TaskChecklistItem> = emptyList(),
) {
    public val progressFraction: Double
        get() = if (totalCount <= 0) 0.0 else (completedCount.toDouble() / totalCount.toDouble()).coerceIn(0.0, 1.0)
}

@Serializable
public data class PlannerResponsePayload(
    public val response: String,
    public val thinking: String? = null,
    public val thinkingDurationSeconds: Double? = null,
    public val messageId: String? = null,
    public val referencedFiles: List<String> = emptyList(),
)

@Serializable
public data class RunCommandPayload(
    public val commandId: String,
    public val commandLine: String,
    public val proposedCommandLine: String? = null,
    public val cwd: String,
    public val exitCode: Int? = null,
    public val outputPreview: String? = null,
    public val durationMs: Int? = null,
)

@Serializable
public data class CodeActionPayload(
    public val targetFileUri: String,
    public val description: String,
    public val additions: Int,
    public val deletions: Int,
    public val isArtifactFile: Boolean = false,
    public val startLine: Int? = null,
    public val endLine: Int? = null,
    public val diffPreviewLines: List<String> = emptyList(),
    public val fileContent: String? = null,
) {
    public val fileName: String
        get() = lastPathComponent(targetFileUri)
}

@Serializable
public data class ViewFilePayload(
    public val fileUri: String,
    public val startLine: Int = 1,
    public val endLine: Int = 120,
    public val totalLines: Int = 240,
    public val fileContent: String? = null,
) {
    public val fileName: String
        get() = lastPathComponent(fileUri)
}

@Serializable
public data class SearchPayload(
    public val query: String,
    public val scopeDirectory: String,
    public val matchCount: Int,
)

@Serializable
public data class CascadeStep(
    public val cascadeId: String,
    public val stepIndex: Int,
    public val type: CortexStepType,
    public val status: CortexStepStatus,
    public val createdAtEpochMs: Long = 0L,
    public val userInput: String? = null,
    public val attachedMentions: List<String> = emptyList(),
    public val isQueuedInOutbox: Boolean = false,
    public val plannerResponse: PlannerResponsePayload? = null,
    public val taskBoundary: TaskBoundaryPayload? = null,
    public val runCommand: RunCommandPayload? = null,
    public val codeAction: CodeActionPayload? = null,
    public val viewFile: ViewFilePayload? = null,
    public val search: SearchPayload? = null,
    public val requestedInteraction: RequestedInteraction? = null,
    public val recordedExecutionMode: CascadeExecutionMode? = null,
    public val recordedModelId: String? = null,
    public val subagent: SubagentPayload? = null,
    public val dynamicWorkflow: DynamicWorkflowPayload? = null,
    public val swarmBoard: SwarmBoardPayload? = null,
    public val mcpToolCall: McpToolCallPayload? = null,
    public val voiceSummary: VoiceCallTranscriptSummary? = null,
    public val rawTypeName: String? = null,
    public val fallbackSummary: String? = null,
) {
    public val id: String get() = "$cascadeId-$stepIndex"

    public val isUnrecognizedForwardStep: Boolean
        get() = type == CortexStepType.UNSPECIFIED &&
            (!rawTypeName.isNullOrBlank() || !fallbackSummary.isNullOrBlank())

    public val hasRenderableChatContent: Boolean
        get() {
            if (status == CortexStepStatus.WAITING || requestedInteraction != null) return true
            if (isUnrecognizedForwardStep) return true
            if (voiceSummary != null || subagent != null || dynamicWorkflow != null ||
                swarmBoard != null || mcpToolCall != null
            ) {
                return true
            }
            return when (type) {
                CortexStepType.USER_INPUT ->
                    !userInput.isNullOrBlank() || attachedMentions.isNotEmpty()
                CortexStepType.PLANNER_RESPONSE, CortexStepType.NOTIFY_USER ->
                    !plannerResponse?.response.isNullOrBlank() ||
                        !plannerResponse?.thinking.isNullOrBlank() ||
                        status == CortexStepStatus.IN_PROGRESS ||
                        status == CortexStepStatus.PENDING
                CortexStepType.TASK_BOUNDARY -> taskBoundary != null
                CortexStepType.RUN_COMMAND -> runCommand != null
                CortexStepType.CODE_ACTION -> codeAction != null
                CortexStepType.VIEW_FILE, CortexStepType.VIEW_CONTENT_CHUNK -> viewFile != null
                CortexStepType.SEARCH, CortexStepType.LIST_DIRECTORY -> search != null || viewFile != null
                CortexStepType.SUBAGENT_INVOCATION,
                CortexStepType.DYNAMIC_WORKFLOW,
                CortexStepType.SWARM_BOARD,
                CortexStepType.MCP_TOOL_CALL -> false
                CortexStepType.GENERATE_IMAGE,
                CortexStepType.READ_URL_CONTENT,
                CortexStepType.BROWSER_SUBAGENT ->
                    !plannerResponse?.response.isNullOrBlank() ||
                        (plannerResponse?.referencedFiles?.isNotEmpty() == true) ||
                        viewFile != null || search != null ||
                        status == CortexStepStatus.IN_PROGRESS
                else -> !plannerResponse?.response.isNullOrBlank()
            }
        }
}

public sealed interface CascadeDisplayItem {
    public val id: String

    public data class Single(public val step: CascadeStep) : CascadeDisplayItem {
        override val id: String get() = step.id
    }

    public data class EvidenceGroup(
        override val id: String,
        public val steps: List<CascadeStep>,
    ) : CascadeDisplayItem

    public companion object {
        public fun buildDisplayItems(steps: List<CascadeStep>): List<CascadeDisplayItem> {
            val result = mutableListOf<CascadeDisplayItem>()
            val buffer = mutableListOf<CascadeStep>()

            fun flushBuffer() {
                if (buffer.isEmpty()) return
                if (buffer.size == 1 && buffer[0].type == CortexStepType.CODE_ACTION) {
                    result.add(Single(buffer[0]))
                } else {
                    val firstIdx = buffer.first().stepIndex
                    val lastIdx = buffer.last().stepIndex
                    val cid = buffer.first().cascadeId
                    result.add(EvidenceGroup(id = "$cid-group-$firstIdx-$lastIdx", steps = buffer.toList()))
                }
                buffer.clear()
            }

            for (step in steps) {
                if (!step.hasRenderableChatContent) continue
                if (step.type == CortexStepType.TASK_BOUNDARY) {
                    flushBuffer()
                    result.add(Single(step))
                } else if (step.type.isGroupableEvidenceStep && step.status != CortexStepStatus.WAITING) {
                    buffer.add(step)
                } else {
                    flushBuffer()
                    result.add(Single(step))
                }
            }
            flushBuffer()
            return result
        }
    }
}

@Serializable
public data class CascadeSummary(
    public val cascadeId: String,
    public val title: String,
    public val projectSlug: String = "ledger-svc",
    public val workspaceUri: String,
    public val branchName: String = "main",
    public val status: CortexStepStatus,
    public val stepCount: Int,
    public val currentStepIndex: Int = 1,
    public val totalSteps: Int = 7,
    public val updatedAtEpochMs: Long = 0L,
    public val relativeTimeLabel: String = "now",
    public val statusSubtitle: String = status.displayBadgeText,
    public val isPinned: Boolean = false,
    public val isArchived: Boolean = false,
    public val isUnread: Boolean = false,
    public val modelLabel: String = "Gemini 3.1 Pro",
    public val pendingInteractionTitle: String? = null,
    public val lastMessagePreview: String? = null,
    public val totalAdditions: Int = 0,
    public val totalDeletions: Int = 0,
    public val isCloud: Boolean = AntigravityCloudDetector.isCloudWorkspaceUri(workspaceUri, cascadeId),
    public val cloudProjectId: String? = null,
    public val originInstanceUuid: String? = null,
    public val originHostName: String? = null,
    public val lastUserViewTimeEpochMs: Long? = null,
) {
    public val id: String get() = cascadeId
}

internal fun lastPathComponent(rawUri: String): String {
    val clean = ResolvedEmbedResource.normalizePath(rawUri).trimEnd('/')
    val slash = clean.lastIndexOf('/')
    return if (slash >= 0) clean.substring(slash + 1) else clean
}
