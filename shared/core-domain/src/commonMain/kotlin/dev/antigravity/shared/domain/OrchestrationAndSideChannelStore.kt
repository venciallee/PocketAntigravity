package dev.antigravity.shared.domain

import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.ConversationOverviewSnapshot
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.QueuedMessageItem
import dev.antigravity.shared.model.SideQuestionMessage
import dev.antigravity.shared.model.SideQuestionThread
import dev.antigravity.shared.model.SwarmBoardPayload
import dev.antigravity.shared.model.VoiceCallTranscriptSummary
import dev.antigravity.shared.model.VoiceModeState
import dev.antigravity.shared.model.VoiceTranscriptTurn
import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.HostCapability
import dev.antigravity.shared.protocol.ProtocolCompatibilityEngine
import dev.antigravity.shared.protocol.currentTimeMillis
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlin.random.Random

public data class OrchestrationState(
    public val overview: ConversationOverviewSnapshot = ConversationOverviewSnapshot(),
    public val sideQuestionThread: SideQuestionThread = SideQuestionThread(),
    public val swarmBoard: SwarmBoardPayload? = null,
    public val swarmMemberFilter: String? = null,
    public val queuedMessages: List<QueuedMessageItem> = emptyList(),
    public val voiceState: VoiceModeState = VoiceModeState(),
    public val voiceTranscriptTurns: List<VoiceTranscriptTurn> = emptyList(),
    public val voicePlaybackSpeed: Double = 1.0,
    public val lastVoiceCallSummary: VoiceCallTranscriptSummary? = null,
    public val lastCapabilityError: String? = null,
)

/**
 * Shared KMP domain store for Antigravity 2.0 (v2.33) multi-agent orchestration:
 * Conversation Overview, `/btw` Side Question threads, `/swarm` board filtering,
 * queued follow-up messages, and Gemini Live Voice Mode transcripts.
 */
public class OrchestrationAndSideChannelStore(
    private val onCapabilityError: (String) -> Unit = {},
) {
    private val _state = MutableStateFlow(OrchestrationState())
    public val state: StateFlow<OrchestrationState> = _state.asStateFlow()

    public fun seedFixture(
        overview: ConversationOverviewSnapshot,
        swarmBoard: SwarmBoardPayload? = null,
        sideQuestionThread: SideQuestionThread = SideQuestionThread(),
        queuedMessages: List<QueuedMessageItem> = emptyList(),
    ) {
        _state.update {
            it.copy(
                overview = overview,
                swarmBoard = swarmBoard,
                swarmMemberFilter = null,
                sideQuestionThread = sideQuestionThread,
                queuedMessages = queuedMessages,
                voiceState = VoiceModeState(),
                voiceTranscriptTurns = emptyList(),
                voicePlaybackSpeed = 1.0,
                lastVoiceCallSummary = null,
                lastCapabilityError = null,
            )
        }
    }

    public suspend fun refreshOverview(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
    ): ConversationOverviewSnapshot {
        if (client == null) return _state.value.overview
        return try {
            val fetched = client.fetchConversationOverview(cascadeId)
            _state.update { it.copy(overview = fetched, lastCapabilityError = null) }
            fetched
        } catch (c: CancellationException) {
            throw c
        } catch (e: Throwable) {
            val msg = if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                client.capabilityProfile().userFacingUnsupportedMessage(HostCapability.CONVERSATION_OVERVIEW)
            } else {
                e.message ?: "Failed to refresh conversation overview"
            }
            recordCapabilityError(msg)
            _state.value.overview
        }
    }

    public suspend fun cancelBackgroundTask(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        taskId: String,
    ) {
        val previousOverview = _state.value.overview
        _state.update { prev ->
            prev.copy(
                overview = prev.overview.copy(
                    backgroundTasks = prev.overview.backgroundTasks.map { task ->
                        if (task.id == taskId) task.copy(status = CortexStepStatus.CANCELLED) else task
                    },
                ),
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.BACKGROUND_TASK_CONTROL,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(overview = previousOverview) } },
        ) { rpc ->
            rpc.cancelBackgroundTask(cascadeId = cascadeId, taskId = taskId)
        }
    }

    public suspend fun stopSubagent(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        subagentId: String,
    ) {
        val previousOverview = _state.value.overview
        _state.update { prev ->
            prev.copy(
                overview = prev.overview.copy(
                    activeSubagents = prev.overview.activeSubagents.map { sub ->
                        if (sub.subagentId == subagentId) sub.copy(status = CortexStepStatus.CANCELLED) else sub
                    },
                ),
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.BACKGROUND_TASK_CONTROL,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(overview = previousOverview) } },
        ) { rpc ->
            rpc.stopSubagent(cascadeId = cascadeId, subagentId = subagentId)
        }
    }

    public fun openSideQuestion(cascadeId: String) {
        _state.update { prev ->
            val thread = if (prev.sideQuestionThread.parentCascadeId == cascadeId) {
                prev.sideQuestionThread
            } else {
                SideQuestionThread(
                    parentCascadeId = cascadeId,
                    messages = emptyList(),
                    isLoading = false,
                )
            }
            prev.copy(sideQuestionThread = thread)
        }
    }

    public suspend fun sendSideQuestion(
        client: AntigravityKmpRpcClient?,
        prompt: String,
        cascadeId: String? = null,
    ) {
        val trimmed = prompt.trim()
        if (trimmed.isEmpty()) return
        val parentCascadeId = cascadeId ?: _state.value.sideQuestionThread.parentCascadeId
        val now = currentTimeMillis()
        val userMsg = SideQuestionMessage(
            id = "btw-user-$now-${Random.nextInt(100, 999)}",
            isUser = true,
            text = trimmed,
            createdAtEpochMs = now,
        )

        if (client == null) {
            val offlineAnswer = if (trimmed.contains("Mutex", ignoreCase = true)) {
                "No — each tenant owns an isolated bucket struct with its own sync.Mutex, so locking b.mu never blocks other tenants."
            } else {
                "Read-only /btw answer for: $trimmed"
            }
            val assistantMsg = SideQuestionMessage(
                id = "btw-assistant-${now + 1}-${Random.nextInt(100, 999)}",
                isUser = false,
                text = offlineAnswer,
                createdAtEpochMs = now + 1,
            )
            _state.update { prev ->
                prev.copy(
                    sideQuestionThread = prev.sideQuestionThread.copy(
                        parentCascadeId = parentCascadeId,
                        messages = prev.sideQuestionThread.messages + userMsg + assistantMsg,
                        isLoading = false,
                    ),
                    lastCapabilityError = null,
                )
            }
            return
        }

        val previousThread = _state.value.sideQuestionThread
        _state.update { prev ->
            prev.copy(
                sideQuestionThread = prev.sideQuestionThread.copy(
                    parentCascadeId = parentCascadeId,
                    messages = prev.sideQuestionThread.messages + userMsg,
                    isLoading = true,
                ),
                lastCapabilityError = null,
            )
        }

        val answer = performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.SIDE_QUESTION,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(sideQuestionThread = previousThread) } },
        ) { rpc ->
            rpc.sendSideQuestion(cascadeId = parentCascadeId, question = trimmed)
        }

        if (answer != null) {
            val replyNow = currentTimeMillis()
            val assistantMsg = SideQuestionMessage(
                id = "btw-assistant-$replyNow-${Random.nextInt(100, 999)}",
                isUser = false,
                text = answer,
                createdAtEpochMs = replyNow,
            )
            _state.update { prev ->
                prev.copy(
                    sideQuestionThread = prev.sideQuestionThread.copy(
                        messages = prev.sideQuestionThread.messages + assistantMsg,
                        isLoading = false,
                    ),
                )
            }
        }
    }

    public fun insertSideQuestionIntoMain(): String? {
        val messages = _state.value.sideQuestionThread.messages
        if (messages.isEmpty()) return null
        val formatted = messages.joinToString("\n") { msg ->
            val prefix = if (msg.isUser) "Q:" else "A:"
            "$prefix ${msg.text}"
        }
        return "[From /btw side question]\n$formatted"
    }

    public fun setSwarmMemberFilter(memberName: String?) {
        _state.update { it.copy(swarmMemberFilter = memberName) }
    }

    public fun enqueueFollowUp(
        text: String,
        attachments: List<ComposerAttachmentChip> = emptyList(),
    ): QueuedMessageItem? {
        val trimmed = text.trim()
        if (trimmed.isEmpty() && attachments.isEmpty()) return null
        val item = QueuedMessageItem(
            id = "queued-${currentTimeMillis()}-${Random.nextInt(100, 999)}",
            text = trimmed,
            attachments = attachments,
            createdAtEpochMs = currentTimeMillis(),
        )
        _state.update { prev ->
            prev.copy(queuedMessages = prev.queuedMessages + item)
        }
        return item
    }

    public fun updateQueuedMessage(id: String, newText: String) {
        _state.update { prev ->
            prev.copy(
                queuedMessages = prev.queuedMessages.map { item ->
                    if (item.id == id) item.copy(text = newText) else item
                },
            )
        }
    }

    public fun removeQueuedMessage(id: String) {
        _state.update { prev ->
            prev.copy(queuedMessages = prev.queuedMessages.filterNot { it.id == id })
        }
    }

    public fun startVoiceMode() {
        _state.update { prev ->
            prev.copy(
                voiceState = prev.voiceState.copy(
                    isActive = true,
                    isMuted = false,
                    liveTranscript = "",
                    statusLabel = "Listening · Gemini Live",
                ),
                voiceTranscriptTurns = emptyList(),
            )
        }
    }

    public fun toggleVoiceMute() {
        _state.update { prev ->
            val nextMuted = !prev.voiceState.isMuted
            prev.copy(
                voiceState = prev.voiceState.copy(
                    isMuted = nextMuted,
                    statusLabel = if (nextMuted) "Muted" else "Listening · Gemini Live",
                ),
            )
        }
    }

    public fun setVoiceOption(voiceName: String) {
        _state.update { prev ->
            prev.copy(voiceState = prev.voiceState.copy(selectedVoice = voiceName))
        }
    }

    public fun setVoicePlaybackSpeed(speed: Double) {
        _state.update { prev ->
            prev.copy(voicePlaybackSpeed = speed.coerceIn(0.5, 2.0))
        }
    }

    public fun appendVoiceTurn(isUser: Boolean, text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        val turn = VoiceTranscriptTurn(
            id = "voice-turn-${currentTimeMillis()}-${Random.nextInt(100, 999)}",
            isUser = isUser,
            text = trimmed,
        )
        _state.update { prev ->
            prev.copy(
                voiceTranscriptTurns = prev.voiceTranscriptTurns + turn,
                voiceState = prev.voiceState.copy(liveTranscript = trimmed),
            )
        }
    }

    public fun endVoiceMode(): VoiceCallTranscriptSummary? {
        val current = _state.value
        val turns = current.voiceTranscriptTurns
        val summary = if (current.voiceState.isActive || turns.isNotEmpty()) {
            val summaryText = turns.joinToString(" · ") { turn ->
                "${if (turn.isUser) "You" else "Agent"}: ${turn.text}"
            }.ifEmpty { "Voice session completed." }
            val seconds = (turns.size * 15).coerceIn(12, 59)
            VoiceCallTranscriptSummary(
                id = "voice-summary-${currentTimeMillis()}-${Random.nextInt(100, 999)}",
                durationLabel = "0:$seconds",
                voiceName = current.voiceState.selectedVoice,
                summaryText = summaryText,
                turns = turns,
            )
        } else {
            null
        }
        _state.update { prev ->
            prev.copy(
                voiceState = prev.voiceState.copy(
                    isActive = false,
                    isMuted = false,
                    statusLabel = "Ready",
                ),
                lastVoiceCallSummary = summary ?: prev.lastVoiceCallSummary,
            )
        }
        return summary
    }

    public fun clearCapabilityError() {
        _state.update { it.copy(lastCapabilityError = null) }
    }

    private fun recordCapabilityError(message: String) {
        _state.update { it.copy(lastCapabilityError = message) }
        onCapabilityError(message)
    }
}
