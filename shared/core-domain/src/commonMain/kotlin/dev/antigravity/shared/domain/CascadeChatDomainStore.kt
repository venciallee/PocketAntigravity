package dev.antigravity.shared.domain

import dev.antigravity.shared.markdown.AntigravityMarkdownParser
import dev.antigravity.shared.markdown.MarkdownBlock
import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.CascadeDisplayItem
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeUserInteractionPayload
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.ThinkingEffortLevel
import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.AntigravityRpcError
import dev.antigravity.shared.protocol.InteractionBuilder
import dev.antigravity.shared.protocol.currentTimeMillis
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlin.random.Random

public data class CascadeChatState(
    public val activeCascadeId: String = "",
    public val stepsByCascadeId: Map<String, List<CascadeStep>> = emptyMap(),
    public val displayItemsByCascadeId: Map<String, List<CascadeDisplayItem>> = emptyMap(),
    public val isLoadingSteps: Boolean = false,
    public val stepLoadErrorText: String? = null,
    public val pendingOutboxCount: Int = 0,
    public val lastDispatchedInteraction: CascadeUserInteractionPayload? = null,
) {
    public val activeSteps: List<CascadeStep>
        get() = stepsByCascadeId[activeCascadeId].orEmpty()

    public val activeDisplayItems: List<CascadeDisplayItem>
        get() = displayItemsByCascadeId[activeCascadeId].orEmpty()
}

public data class SendMessageOutcome(
    public val resolvedCascadeId: String,
    public val dispatchedLive: Boolean,
    public val queuedInOutbox: Boolean,
    public val errorMessage: String? = null,
)

public data class OutboxReplayResult(
    public val replayedCount: Int,
)

/**
 * Shared KMP message-list & PC-side core interaction store (`StateFlow<CascadeChatState>`).
 *
 * Owns:
 * - Trajectory step fetching (`<600` JSON + `>=600` Binary Protobuf) + disk caching
 * - `CascadeDisplayItem.buildDisplayItems` evidence grouping
 * - Markdown AST parsing cache (`AntigravityMarkdownParser`)
 * - Durable Outbox message send & offline replay (`StartCascade` + `SendUserCascadeMessage`)
 * - Authoritative `HandleCascadeUserInteraction` approval/rejection (`InteractionBuilder`)
 * - Active turn cancellation (`CancelCascadeInvocation`)
 */
public class CascadeChatDomainStore(
    private val projectionStorage: ProjectionStoragePort,
) {
    private val _state = MutableStateFlow(CascadeChatState())
    public val state: StateFlow<CascadeChatState> = _state.asStateFlow()

    private val markdownCache = linkedMapOf<String, List<MarkdownBlock>>()

    public fun setActiveCascade(cascadeId: String) {
        _state.update { it.copy(activeCascadeId = cascadeId, stepLoadErrorText = null) }
    }

    public suspend fun loadCachedSteps(cascadeId: String): List<CascadeStep> {
        val cached = projectionStorage.loadSteps(cascadeId)
        if (cached.isNotEmpty()) {
            putSteps(cascadeId, cached)
        }
        return cached
    }

    public suspend fun syncSteps(
        client: AntigravityKmpRpcClient,
        cascadeId: String,
        knownStepCount: Int = 0,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ): List<CascadeStep> {
        if (cascadeId.isEmpty()) return emptyList()
        if (_state.value.stepsByCascadeId[cascadeId].isNullOrEmpty()) {
            val cached = projectionStorage.loadSteps(cascadeId)
            if (cached.isNotEmpty()) {
                putSteps(cascadeId, cached)
            } else {
                _state.update { it.copy(isLoadingSteps = true, stepLoadErrorText = null) }
            }
        }
        return try {
            val remoteSteps = client.fetchAllTrajectorySteps(
                cascadeId = cascadeId,
                knownStepCount = knownStepCount,
                isCloud = isCloud,
                instanceUuidOverride = instanceUuidOverride,
            )
            if (remoteSteps.isNotEmpty()) {
                putSteps(cascadeId, remoteSteps)
                projectionStorage.saveSteps(cascadeId, remoteSteps)
            }
            _state.update { it.copy(isLoadingSteps = false, stepLoadErrorText = null) }
            remoteSteps
        } catch (e: Throwable) {
            _state.update { it.copy(isLoadingSteps = false, stepLoadErrorText = e.message ?: "Failed to load steps") }
            throw e
        }
    }

    public suspend fun startConversation(
        client: AntigravityKmpRpcClient,
        workspaceUri: String,
        initialPrompt: String = "",
        modelId: String = "MODEL_PLACEHOLDER_M37",
        cloudProjectId: String? = null,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ): String {
        val cascadeId = client.startCascade(
            workspaceUri = workspaceUri,
            initialPrompt = initialPrompt,
            modelId = modelId,
            cloudProjectId = cloudProjectId,
            isCloud = isCloud,
            instanceUuidOverride = instanceUuidOverride,
        )
        _state.update { prev ->
            prev.copy(
                activeCascadeId = cascadeId,
                stepsByCascadeId = prev.stepsByCascadeId + (cascadeId to prev.stepsByCascadeId[cascadeId].orEmpty()),
            )
        }
        return cascadeId
    }

    public suspend fun sendMessage(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        message: String,
        workspaceUri: String = "",
        attachments: List<ComposerAttachmentChip> = emptyList(),
        modelId: String = "MODEL_PLACEHOLDER_M37",
        effort: ThinkingEffortLevel = ThinkingEffortLevel.HIGH,
        mode: CascadeExecutionMode = CascadeExecutionMode.PLANNING,
        agentPersona: String = "Default",
        isCloud: Boolean = false,
        cloudProjectId: String? = null,
        permissionPreset: AgentPermissionPreset? = null,
        instanceUuidOverride: String? = null,
        isDeviceNetworkReachable: Boolean = true,
        isOptimisticDraft: Boolean = false,
    ): SendMessageOutcome {
        val trimmed = message.trim()
        if (trimmed.isEmpty() && attachments.isEmpty()) {
            return SendMessageOutcome(cascadeId, dispatchedLive = false, queuedInOutbox = false)
        }

        var targetCascadeId = cascadeId
        val existingSteps = _state.value.stepsByCascadeId[targetCascadeId].orEmpty()
        val nextStepIndex = (existingSteps.maxOfOrNull { it.stepIndex } ?: -1) + 1
        val optimisticStep = CascadeStep(
            cascadeId = targetCascadeId,
            stepIndex = nextStepIndex,
            type = CortexStepType.USER_INPUT,
            status = CortexStepStatus.DONE,
            createdAtEpochMs = currentTimeMillis(),
            userInput = trimmed,
            attachedMentions = attachments.map { it.label },
            isQueuedInOutbox = !isDeviceNetworkReachable || client == null,
            recordedExecutionMode = mode,
            recordedModelId = modelId,
        )
        val updatedSteps = existingSteps + optimisticStep
        putSteps(targetCascadeId, updatedSteps)
        projectionStorage.saveSteps(targetCascadeId, updatedSteps)

        val outboxEntry = DurableOutboxEntry(
            id = "outbox-${currentTimeMillis()}-${Random.nextInt(1000, 9999)}",
            cascadeId = targetCascadeId,
            kind = OutboxPayloadKind.USER_MESSAGE,
            messageText = trimmed,
            stepIndex = nextStepIndex,
        )
        projectionStorage.enqueueOutbox(outboxEntry)
        refreshOutboxCount()

        if (client == null || !isDeviceNetworkReachable) {
            return SendMessageOutcome(targetCascadeId, dispatchedLive = false, queuedInOutbox = true)
        }

        return try {
            if (targetCascadeId.isEmpty() || isOptimisticDraft) {
                val createdId = client.startCascade(
                    workspaceUri = workspaceUri,
                    initialPrompt = "",
                    modelId = modelId,
                    cloudProjectId = cloudProjectId,
                    isCloud = isCloud,
                    instanceUuidOverride = instanceUuidOverride,
                )
                if (createdId.isNotEmpty() && createdId != targetCascadeId) {
                    migrateLocalSteps(targetCascadeId, createdId)
                    targetCascadeId = createdId
                }
            }

            client.sendUserCascadeMessage(
                cascadeId = targetCascadeId,
                message = trimmed,
                attachments = attachments,
                modelId = modelId,
                effort = effort,
                mode = mode,
                agentPersona = agentPersona,
                isCloud = isCloud,
                permissionPreset = permissionPreset,
                instanceUuidOverride = instanceUuidOverride,
            )

            projectionStorage.removeOutbox(outboxEntry.id)
            markStepQueued(targetCascadeId, nextStepIndex, queued = false)
            refreshOutboxCount()
            SendMessageOutcome(targetCascadeId, dispatchedLive = true, queuedInOutbox = false)
        } catch (e: Throwable) {
            val isOffline = isTransportOfflineError(e)
            if (isOffline) {
                markStepQueued(targetCascadeId, nextStepIndex, queued = true)
                refreshOutboxCount()
                SendMessageOutcome(
                    resolvedCascadeId = targetCascadeId,
                    dispatchedLive = false,
                    queuedInOutbox = true,
                    errorMessage = e.message,
                )
            } else {
                projectionStorage.removeOutbox(outboxEntry.id)
                refreshOutboxCount()
                _state.update { it.copy(stepLoadErrorText = "Failed to send message: ${e.message}") }
                SendMessageOutcome(
                    resolvedCascadeId = targetCascadeId,
                    dispatchedLive = false,
                    queuedInOutbox = false,
                    errorMessage = e.message,
                )
            }
        }
    }

    public suspend fun resolveWaitingInteraction(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        stepIndex: Int,
        decision: InteractionDecision,
        workspaceUri: String? = null,
        instanceUuidOverride: String? = null,
        stepOverride: CascadeStep? = null,
    ): CascadeUserInteractionPayload {
        val currentSteps = _state.value.stepsByCascadeId[cascadeId].orEmpty()
        val targetStep = stepOverride ?: currentSteps.firstOrNull { it.stepIndex == stepIndex }
            ?: throw AntigravityRpcError.InteractionRejected("Step $stepIndex not found in $cascadeId")

        val payload = InteractionBuilder.buildPayload(
            step = targetStep,
            decision = decision,
            workspaceUri = workspaceUri,
        ) ?: throw AntigravityRpcError.InteractionRejected("Step $stepIndex has no requestedInteraction")

        _state.update { it.copy(lastDispatchedInteraction = payload) }

        val outboxEntry = DurableOutboxEntry(
            id = "interaction-${currentTimeMillis()}-${Random.nextInt(1000, 9999)}",
            cascadeId = cascadeId,
            kind = OutboxPayloadKind.INTERACTION_APPROVAL,
            stepIndex = stepIndex,
        )
        projectionStorage.enqueueOutbox(outboxEntry)
        refreshOutboxCount()

        try {
            if (client != null) {
                client.handleCascadeUserInteraction(payload, instanceUuidOverride = instanceUuidOverride)
            }
            val nextStatus = if (decision is InteractionDecision.Reject) {
                CortexStepStatus.CANCELLED
            } else {
                CortexStepStatus.DONE
            }
            if (currentSteps.isNotEmpty()) {
                val updated = currentSteps.map { step ->
                    if (step.stepIndex == stepIndex) step.copy(status = nextStatus) else step
                }
                putSteps(cascadeId, updated)
                projectionStorage.saveSteps(cascadeId, updated)
            }
            return payload
        } finally {
            projectionStorage.removeOutbox(outboxEntry.id)
            refreshOutboxCount()
        }
    }

    public suspend fun cancelActiveTurn(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        instanceUuidOverride: String? = null,
    ) {
        val currentSteps = _state.value.stepsByCascadeId[cascadeId].orEmpty()
        if (currentSteps.isNotEmpty()) {
            val updated = currentSteps.map { step ->
                if (step.status == CortexStepStatus.IN_PROGRESS ||
                    step.status == CortexStepStatus.PENDING ||
                    step.status == CortexStepStatus.WAITING
                ) {
                    step.copy(status = CortexStepStatus.CANCELLED)
                } else {
                    step
                }
            }
            putSteps(cascadeId, updated)
        }
        client?.cancelCascadeInvocation(cascadeId, instanceUuidOverride = instanceUuidOverride)
    }

    public suspend fun replayPendingOutbox(
        client: AntigravityKmpRpcClient,
        modelId: String = "MODEL_PLACEHOLDER_M37",
        effort: ThinkingEffortLevel = ThinkingEffortLevel.HIGH,
        mode: CascadeExecutionMode = CascadeExecutionMode.PLANNING,
    ): Int {
        val pending = projectionStorage.loadPendingOutbox()
        if (pending.isEmpty()) {
            _state.update { it.copy(pendingOutboxCount = 0) }
            return 0
        }
        var replayed = 0
        for (entry in pending) {
            if (entry.kind != OutboxPayloadKind.USER_MESSAGE || entry.messageText.isNullOrBlank()) {
                projectionStorage.removeOutbox(entry.id)
                continue
            }
            try {
                client.sendUserCascadeMessage(
                    cascadeId = entry.cascadeId,
                    message = entry.messageText,
                    modelId = modelId,
                    effort = effort,
                    mode = mode,
                )
                projectionStorage.removeOutbox(entry.id)
                entry.stepIndex?.let { markStepQueued(entry.cascadeId, it, queued = false) }
                replayed += 1
            } catch (e: Throwable) {
                if (isTransportOfflineError(e)) {
                    break
                } else {
                    projectionStorage.removeOutbox(entry.id)
                }
            }
        }
        refreshOutboxCount()
        return replayed
    }

    public fun parseMarkdown(markdown: String): List<MarkdownBlock> {
        markdownCache[markdown]?.let { return it }
        val parsed = AntigravityMarkdownParser.parse(markdown)
        if (markdownCache.size >= 256) {
            markdownCache.keys.firstOrNull()?.let { markdownCache.remove(it) }
        }
        markdownCache[markdown] = parsed
        return parsed
    }

    public fun clear() {
        markdownCache.clear()
        _state.value = CascadeChatState()
    }

    private fun putSteps(cascadeId: String, steps: List<CascadeStep>) {
        val displayItems = CascadeDisplayItem.buildDisplayItems(steps)
        _state.update { prev ->
            prev.copy(
                stepsByCascadeId = prev.stepsByCascadeId + (cascadeId to steps),
                displayItemsByCascadeId = prev.displayItemsByCascadeId + (cascadeId to displayItems),
            )
        }
    }

    private suspend fun migrateLocalSteps(oldId: String, newId: String) {
        val existing = _state.value.stepsByCascadeId[oldId].orEmpty().map { it.copy(cascadeId = newId) }
        val display = CascadeDisplayItem.buildDisplayItems(existing)
        _state.update { prev ->
            val nextSteps = prev.stepsByCascadeId.toMutableMap().apply {
                remove(oldId)
                put(newId, existing)
            }
            val nextDisplay = prev.displayItemsByCascadeId.toMutableMap().apply {
                remove(oldId)
                put(newId, display)
            }
            prev.copy(
                activeCascadeId = if (prev.activeCascadeId == oldId || prev.activeCascadeId.isEmpty()) newId else prev.activeCascadeId,
                stepsByCascadeId = nextSteps,
                displayItemsByCascadeId = nextDisplay,
            )
        }
        projectionStorage.saveSteps(newId, existing)
    }

    private suspend fun markStepQueued(cascadeId: String, stepIndex: Int, queued: Boolean) {
        val current = _state.value.stepsByCascadeId[cascadeId] ?: return
        val updated = current.map { step ->
            if (step.stepIndex == stepIndex && step.type == CortexStepType.USER_INPUT) {
                step.copy(isQueuedInOutbox = queued)
            } else {
                step
            }
        }
        putSteps(cascadeId, updated)
        projectionStorage.saveSteps(cascadeId, updated)
    }

    private suspend fun refreshOutboxCount() {
        val count = projectionStorage.loadPendingOutbox().size
        _state.update { it.copy(pendingOutboxCount = count) }
    }

    private fun isTransportOfflineError(e: Throwable): Boolean = when (e) {
        is AntigravityRpcError.HttpError -> e.statusCode in setOf(502, 503, 504)
        is AntigravityRpcError.Unauthorized,
        is AntigravityRpcError.DecodingError,
        is AntigravityRpcError.InteractionRejected,
        is AntigravityRpcError.InvalidEndpoint -> false
        else -> true
    }
}
