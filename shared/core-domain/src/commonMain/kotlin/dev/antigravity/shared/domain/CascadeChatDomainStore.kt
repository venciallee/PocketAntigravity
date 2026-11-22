package dev.antigravity.shared.domain

import dev.antigravity.shared.markdown.AntigravityMarkdownParser
import dev.antigravity.shared.markdown.MarkdownBlock
import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.CascadeDisplayItem
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeUserInteractionPayload
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.ConversationTurnSummary
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.StructuredQuestionStepItem
import dev.antigravity.shared.model.ThinkingEffortLevel
import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.AntigravityRpcError
import dev.antigravity.shared.protocol.HostCapability
import dev.antigravity.shared.protocol.InteractionBuilder
import dev.antigravity.shared.protocol.currentTimeMillis
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlin.Throws
import kotlin.random.Random

public data class CascadeChatState(
    public val activeCascadeId: String = "",
    public val stepsByCascadeId: Map<String, List<CascadeStep>> = emptyMap(),
    public val displayItemsByCascadeId: Map<String, List<CascadeDisplayItem>> = emptyMap(),
    public val isLoadingSteps: Boolean = false,
    public val stepLoadErrorText: String? = null,
    public val pendingOutboxCount: Int = 0,
    public val lastDispatchedInteraction: CascadeUserInteractionPayload? = null,
    public val structuredQuestions: List<StructuredQuestionStepItem> = emptyList(),
    public val activeQuestionStepIndex: Int = 1,
    public val expandedThinkingStepIds: Set<String> = emptySet(),
    public val expandedEvidenceGroupIds: Set<String> = emptySet(),
    public val draftInputText: String = "",
) {
    public val activeSteps: List<CascadeStep>
        get() = stepsByCascadeId[activeCascadeId].orEmpty()

    public val steps: List<CascadeStep>
        get() = activeSteps

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
 * - Trajectory step fetching (Binary-first Protobuf + adaptive JSON ceiling discovery) + disk caching
 * - `CascadeDisplayItem.buildDisplayItems` evidence grouping
 * - Markdown AST parsing cache (`AntigravityMarkdownParser`)
 * - Durable Outbox message send & offline replay (`StartCascade` + `SendUserCascadeMessage`)
 * - Authoritative `HandleCascadeUserInteraction` approval/rejection (`InteractionBuilder`)
 * - Active turn cancellation (`CancelCascadeInvocation`), structured questions, and draft/expansion state
 */
public class CascadeChatDomainStore(
    private val projectionStorage: ProjectionStoragePort,
    private val onCapabilityError: (String) -> Unit = {},
) {
    private val _state = MutableStateFlow(CascadeChatState())
    public val state: StateFlow<CascadeChatState> = _state.asStateFlow()

    public var isVerificationMode: Boolean = false

    private val markdownCache = linkedMapOf<String, List<MarkdownBlock>>()

    public fun setActiveCascade(cascadeId: String) {
        _state.update { it.copy(activeCascadeId = cascadeId, stepLoadErrorText = null) }
    }

    public fun injectDebugSteps(extraSteps: List<CascadeStep>) {
        if (extraSteps.isEmpty()) return
        val grouped = extraSteps.groupBy { it.cascadeId.ifBlank { _state.value.activeCascadeId } }
        for ((cascadeId, incoming) in grouped) {
            if (cascadeId.isEmpty()) continue
            val existing = _state.value.stepsByCascadeId[cascadeId].orEmpty()
            val byIndex = linkedMapOf<Int, CascadeStep>()
            for (step in existing) byIndex[step.stepIndex] = step
            for (step in incoming) byIndex[step.stepIndex] = step.copy(cascadeId = cascadeId)
            val merged = byIndex.values.sortedBy { it.stepIndex }
            putSteps(cascadeId, merged)
        }
    }

    public fun seedFixtureSteps(
        stepsByCascade: Map<String, List<CascadeStep>>,
        questions: List<StructuredQuestionStepItem>,
        activeQuestionStepIndex: Int = 1,
    ) {
        val displayMap = stepsByCascade.mapValues { (_, steps) ->
            CascadeDisplayItem.buildDisplayItems(steps)
        }
        val clampedQuestionIdx = if (questions.isEmpty()) {
            activeQuestionStepIndex
        } else {
            activeQuestionStepIndex.coerceIn(0, questions.lastIndex)
        }
        _state.update { prev ->
            prev.copy(
                stepsByCascadeId = stepsByCascade,
                displayItemsByCascadeId = displayMap,
                structuredQuestions = questions,
                activeQuestionStepIndex = clampedQuestionIdx,
                isLoadingSteps = false,
                stepLoadErrorText = null,
            )
        }
    }

    public fun setDraftInputText(text: String) {
        _state.update { it.copy(draftInputText = text) }
    }

    public fun toggleThinkingExpanded(stepId: String) {
        _state.update { prev ->
            val next = if (stepId in prev.expandedThinkingStepIds) {
                prev.expandedThinkingStepIds - stepId
            } else {
                prev.expandedThinkingStepIds + stepId
            }
            prev.copy(expandedThinkingStepIds = next)
        }
    }

    public fun toggleEvidenceGroupExpanded(groupId: String) {
        _state.update { prev ->
            val next = if (groupId in prev.expandedEvidenceGroupIds) {
                prev.expandedEvidenceGroupIds - groupId
            } else {
                prev.expandedEvidenceGroupIds + groupId
            }
            prev.copy(expandedEvidenceGroupIds = next)
        }
    }

    public fun setActiveQuestionStepIndex(stepIndex: Int) {
        _state.update { prev ->
            val clamped = if (prev.structuredQuestions.isEmpty()) {
                stepIndex.coerceAtLeast(0)
            } else {
                stepIndex.coerceIn(0, prev.structuredQuestions.lastIndex)
            }
            prev.copy(activeQuestionStepIndex = clamped)
        }
    }

    public fun toggleQuestionOption(option: String, stepIndex: Int? = null) {
        _state.update { prev ->
            val targetIdx = stepIndex ?: prev.activeQuestionStepIndex
            if (targetIdx !in prev.structuredQuestions.indices) return@update prev
            val updated = prev.structuredQuestions.mapIndexed { idx, item ->
                if (idx != targetIdx) {
                    item
                } else {
                    val nextSelected = if (item.isMultiSelect) {
                        if (option in item.selectedOptions) item.selectedOptions - option else item.selectedOptions + option
                    } else {
                        setOf(option)
                    }
                    item.copy(
                        selectedOptions = nextSelected,
                        isCompleted = nextSelected.isNotEmpty() || item.customWriteIn.isNotBlank(),
                    )
                }
            }
            prev.copy(structuredQuestions = updated)
        }
    }

    public fun setQuestionCustomWriteIn(text: String, stepIndex: Int? = null) {
        _state.update { prev ->
            val targetIdx = stepIndex ?: prev.activeQuestionStepIndex
            if (targetIdx !in prev.structuredQuestions.indices) return@update prev
            val updated = prev.structuredQuestions.mapIndexed { idx, item ->
                if (idx != targetIdx) {
                    item
                } else {
                    item.copy(
                        customWriteIn = text,
                        isCompleted = item.selectedOptions.isNotEmpty() || text.isNotBlank(),
                    )
                }
            }
            prev.copy(structuredQuestions = updated)
        }
    }

    public fun advanceQuestionStep() {
        _state.update { prev ->
            if (prev.structuredQuestions.isEmpty()) return@update prev
            val currentIdx = prev.activeQuestionStepIndex.coerceIn(0, prev.structuredQuestions.lastIndex)
            val nextIdx = (currentIdx + 1).coerceAtMost(prev.structuredQuestions.lastIndex)
            val updated = prev.structuredQuestions.mapIndexed { idx, item ->
                if (idx == currentIdx) {
                    item.copy(
                        isCompleted = item.selectedOptions.isNotEmpty() ||
                            item.customWriteIn.isNotBlank() ||
                            item.isCompleted,
                    )
                } else {
                    item
                }
            }
            prev.copy(
                structuredQuestions = updated,
                activeQuestionStepIndex = nextIdx,
            )
        }
    }

    public fun previousQuestionStep() {
        _state.update { prev ->
            prev.copy(activeQuestionStepIndex = (prev.activeQuestionStepIndex - 1).coerceAtLeast(0))
        }
    }

    public fun resolveWaitingInteractionLocally(
        cascadeId: String,
        stepIndex: Int,
        approved: Boolean,
    ) {
        val targetCascadeId = cascadeId.ifBlank { _state.value.activeCascadeId }
        val currentSteps = _state.value.stepsByCascadeId[targetCascadeId].orEmpty()
        if (currentSteps.isEmpty()) return
        val nextStatus = if (approved) CortexStepStatus.DONE else CortexStepStatus.CANCELLED
        val updated = currentSteps.map { step ->
            if (step.stepIndex == stepIndex) step.copy(status = nextStatus) else step
        }
        putSteps(targetCascadeId, updated)
    }

    @Throws(Throwable::class)
    public suspend fun revertToStep(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        stepIndex: Int,
        instanceUuidOverride: String? = null,
    ) {
        val targetCascadeId = cascadeId.ifBlank { _state.value.activeCascadeId }
        val previousSteps = _state.value.stepsByCascadeId[targetCascadeId].orEmpty()
        val truncated = previousSteps.filter { it.stepIndex <= stepIndex }
        putSteps(targetCascadeId, truncated)
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.REVERT_TO_STEP,
            onUnsupported = { msg ->
                _state.update { it.copy(stepLoadErrorText = msg) }
                onCapabilityError(msg)
            },
            rollback = { putSteps(targetCascadeId, previousSteps) },
        ) { rpc ->
            rpc.revertConversationToStep(
                cascadeId = targetCascadeId,
                stepIndex = stepIndex,
                instanceUuidOverride = instanceUuidOverride,
            )
        }
    }

    public fun turnSummaries(cascadeId: String = _state.value.activeCascadeId): List<ConversationTurnSummary> {
        val steps = _state.value.stepsByCascadeId[cascadeId].orEmpty()
        if (steps.isEmpty()) return emptyList()
        val userIndices = steps.indices.filter { steps[it].type == CortexStepType.USER_INPUT }
        if (userIndices.isEmpty()) return emptyList()
        return userIndices.mapIndexed { turnIdx, startPos ->
            val endPos = if (turnIdx + 1 < userIndices.size) userIndices[turnIdx + 1] - 1 else steps.lastIndex
            val slice = steps.subList(startPos, endPos + 1)
            val changedFiles = slice.mapNotNull { it.codeAction?.targetFileUri }.distinct().size
            ConversationTurnSummary(
                turnIndex = turnIdx + 1,
                startStepIndex = steps[startPos].stepIndex,
                endStepIndex = steps[endPos].stepIndex,
                userPromptPreview = steps[startPos].userInput?.trim().orEmpty().ifEmpty { "Turn ${turnIdx + 1}" },
                changedFileCount = changedFiles,
            )
        }
    }

    @Throws(Throwable::class)
    public suspend fun loadCachedSteps(cascadeId: String): List<CascadeStep> {
        val cached = projectionStorage.loadSteps(cascadeId)
        if (cached.isNotEmpty()) {
            putSteps(cascadeId, cached)
        }
        return cached
    }

    @Throws(Throwable::class)
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

    @Throws(Throwable::class)
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

    @Throws(Throwable::class)
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
        isVerificationMode: Boolean = this.isVerificationMode,
    ): SendMessageOutcome {
        val trimmed = message.trim()
        if (trimmed.isEmpty() && attachments.isEmpty()) {
            return SendMessageOutcome(cascadeId, dispatchedLive = false, queuedInOutbox = false)
        }

        var targetCascadeId = cascadeId.ifBlank { _state.value.activeCascadeId }
        val existingSteps = _state.value.stepsByCascadeId[targetCascadeId].orEmpty()
        val nextStepIndex = (existingSteps.maxOfOrNull { it.stepIndex } ?: -1) + 1
        val isOfflineVerification = client == null && isVerificationMode
        val optimisticStep = CascadeStep(
            cascadeId = targetCascadeId,
            stepIndex = nextStepIndex,
            type = CortexStepType.USER_INPUT,
            status = CortexStepStatus.DONE,
            createdAtEpochMs = currentTimeMillis(),
            userInput = trimmed,
            attachedMentions = attachments.map { it.label },
            isQueuedInOutbox = !isOfflineVerification && (!isDeviceNetworkReachable || client == null),
            recordedExecutionMode = mode,
            recordedModelId = modelId,
        )
        val updatedSteps = existingSteps + optimisticStep
        putSteps(targetCascadeId, updatedSteps)
        _state.update { it.copy(draftInputText = "") }
        projectionStorage.saveSteps(targetCascadeId, updatedSteps)

        if (isOfflineVerification) {
            return SendMessageOutcome(targetCascadeId, dispatchedLive = false, queuedInOutbox = false)
        }

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

    @Throws(Throwable::class)
    public suspend fun resolveWaitingInteraction(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        stepIndex: Int,
        decision: InteractionDecision,
        workspaceUri: String? = null,
        instanceUuidOverride: String? = null,
        stepOverride: CascadeStep? = null,
    ): CascadeUserInteractionPayload {
        val targetCascadeId = cascadeId.ifBlank { _state.value.activeCascadeId }
        val currentSteps = _state.value.stepsByCascadeId[targetCascadeId].orEmpty()
        val targetStep = stepOverride ?: currentSteps.firstOrNull { it.stepIndex == stepIndex }
            ?: throw AntigravityRpcError.InteractionRejected("Step $stepIndex not found in $targetCascadeId")

        val payload = InteractionBuilder.buildPayload(
            step = targetStep,
            decision = decision,
            workspaceUri = workspaceUri,
        ) ?: throw AntigravityRpcError.InteractionRejected("Step $stepIndex has no requestedInteraction")

        _state.update { it.copy(lastDispatchedInteraction = payload) }

        val outboxEntry = DurableOutboxEntry(
            id = "interaction-${currentTimeMillis()}-${Random.nextInt(1000, 9999)}",
            cascadeId = targetCascadeId,
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
                putSteps(targetCascadeId, updated)
                projectionStorage.saveSteps(targetCascadeId, updated)
            }
            return payload
        } finally {
            projectionStorage.removeOutbox(outboxEntry.id)
            refreshOutboxCount()
        }
    }

    @Throws(Throwable::class)
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

    @Throws(Throwable::class)
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
