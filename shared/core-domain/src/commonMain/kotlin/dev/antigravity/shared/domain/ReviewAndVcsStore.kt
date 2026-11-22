package dev.antigravity.shared.domain

import dev.antigravity.shared.model.ArtifactSnapshot
import dev.antigravity.shared.model.DiffCompareMode
import dev.antigravity.shared.model.DiffLineComment
import dev.antigravity.shared.model.FilePatchDiff
import dev.antigravity.shared.model.GitCommitDraft
import dev.antigravity.shared.model.GitCommitResult
import dev.antigravity.shared.model.PlanInlineComment
import dev.antigravity.shared.model.PlanProposedFileChange
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

public data class ReviewAndVcsState(
    public val artifacts: List<ArtifactSnapshot> = emptyList(),
    public val selectedArtifactPath: String = "/brain/implementation_plan.md",
    public val planChanges: List<PlanProposedFileChange> = emptyList(),
    public val planComments: List<PlanInlineComment> = emptyList(),
    public val planCommentsSentCount: Int = 0,
    public val planProceeded: Boolean = false,
    public val diffs: List<FilePatchDiff> = emptyList(),
    public val selectedDiffTurn: Int = 3,
    public val compareMode: DiffCompareMode = DiffCompareMode.TURN,
    public val selectedDiffFileIndex: Int = 0,
    public val selectedDiffLineNumber: Int = 29,
    public val diffLineComments: List<DiffLineComment> = emptyList(),
    public val lastCommitResult: GitCommitResult? = null,
    public val lastCapabilityError: String? = null,
) {
    public val selectedArtifact: ArtifactSnapshot?
        get() = artifacts.firstOrNull { it.artifactPath == selectedArtifactPath } ?: artifacts.firstOrNull()

    public val selectedDiffFile: FilePatchDiff?
        get() = diffs.getOrNull(selectedDiffFileIndex) ?: diffs.firstOrNull()
}

/**
 * Shared KMP domain store managing Implementation Plan Review (`UE11`), Turn Diff Review (`UE12`),
 * inline review comments, hunk/file reverts, and Git VCS stage/unstage/discard/commit/push.
 */
public class ReviewAndVcsStore(
    private val onCapabilityError: (String) -> Unit = {},
) {
    private val _state = MutableStateFlow(ReviewAndVcsState())
    public val state: StateFlow<ReviewAndVcsState> = _state.asStateFlow()

    public fun seedFixture(
        artifacts: List<ArtifactSnapshot>,
        planChanges: List<PlanProposedFileChange>,
        planComments: List<PlanInlineComment>,
        diffs: List<FilePatchDiff>,
        selectedArtifactPath: String = "/brain/implementation_plan.md",
        selectedDiffTurn: Int = 3,
        selectedDiffFileIndex: Int = 0,
        selectedDiffLineNumber: Int = 29,
        diffLineComments: List<DiffLineComment> = emptyList(),
    ) {
        _state.update {
            it.copy(
                artifacts = artifacts,
                selectedArtifactPath = selectedArtifactPath,
                planChanges = planChanges,
                planComments = planComments,
                planCommentsSentCount = 0,
                planProceeded = false,
                diffs = diffs,
                selectedDiffTurn = selectedDiffTurn,
                compareMode = DiffCompareMode.TURN,
                selectedDiffFileIndex = selectedDiffFileIndex,
                selectedDiffLineNumber = selectedDiffLineNumber,
                diffLineComments = diffLineComments,
                lastCommitResult = null,
                lastCapabilityError = null,
            )
        }
    }

    public fun selectArtifact(artifactPath: String) {
        _state.update { it.copy(selectedArtifactPath = artifactPath) }
    }

    public suspend fun refreshArtifacts(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
    ): List<ArtifactSnapshot> {
        if (client == null) return _state.value.artifacts
        return try {
            val fetched = client.getArtifactSnapshots(cascadeId)
            if (fetched.isNotEmpty()) {
                _state.update { prev ->
                    val nextSelected = if (fetched.any { it.artifactPath == prev.selectedArtifactPath }) {
                        prev.selectedArtifactPath
                    } else {
                        fetched.first().artifactPath
                    }
                    prev.copy(
                        artifacts = fetched,
                        selectedArtifactPath = nextSelected,
                        lastCapabilityError = null,
                    )
                }
            }
            fetched
        } catch (c: CancellationException) {
            throw c
        } catch (e: Throwable) {
            val msg = e.message ?: "Failed to refresh artifacts"
            recordCapabilityError(msg)
            _state.value.artifacts
        }
    }

    public fun addPlanComment(
        targetFilePath: String,
        quotedSpan: String,
        body: String,
    ): PlanInlineComment? {
        val trimmed = body.trim()
        if (trimmed.isEmpty()) return null
        val comment = PlanInlineComment(
            id = "plan-comment-${currentTimeMillis()}-${Random.nextInt(100, 999)}",
            authorInitials = "WL",
            authorName = "You",
            statusLabel = "Pending",
            targetFilePath = targetFilePath,
            quotedSpan = quotedSpan,
            body = trimmed,
        )
        _state.update { prev ->
            prev.copy(planComments = prev.planComments + comment)
        }
        return comment
    }

    public suspend fun sendPlanComments(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
    ) {
        val current = _state.value.planComments
        if (current.isEmpty()) return
        val toSend = current.filter { !it.statusLabel.equals("Sent", ignoreCase = true) }.ifEmpty { current }
        val previousComments = current
        val previousSentCount = _state.value.planCommentsSentCount

        _state.update { prev ->
            prev.copy(
                planComments = prev.planComments.map { it.copy(statusLabel = "Sent") },
                planCommentsSentCount = prev.planCommentsSentCount + toSend.size,
                lastCapabilityError = null,
            )
        }

        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.TURN_DIFF,
            onUnsupported = ::recordCapabilityError,
            rollback = {
                _state.update {
                    it.copy(
                        planComments = previousComments,
                        planCommentsSentCount = previousSentCount,
                    )
                }
            },
        ) { rpc ->
            rpc.sendPlanReviewComments(cascadeId = cascadeId, comments = toSend)
        }
    }

    public fun proceedPlan() {
        _state.update { it.copy(planProceeded = true) }
    }

    public suspend fun refreshTurnDiff(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        turnNumber: Int? = _state.value.selectedDiffTurn,
        mode: DiffCompareMode = _state.value.compareMode,
    ): List<FilePatchDiff> {
        if (client == null) return _state.value.diffs
        return try {
            val fetched = client.getTurnDiff(
                cascadeId = cascadeId,
                turnNumber = turnNumber,
                mode = mode,
            )
            _state.update { prev ->
                prev.copy(
                    diffs = fetched,
                    compareMode = mode,
                    selectedDiffTurn = turnNumber ?: prev.selectedDiffTurn,
                    selectedDiffFileIndex = 0,
                    lastCapabilityError = null,
                )
            }
            fetched
        } catch (c: CancellationException) {
            throw c
        } catch (e: Throwable) {
            val msg = if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                client.capabilityProfile().userFacingUnsupportedMessage(HostCapability.TURN_DIFF)
            } else {
                e.message ?: "Failed to load turn diff"
            }
            recordCapabilityError(msg)
            _state.value.diffs
        }
    }

    public fun selectDiffTurn(turnNumber: Int) {
        _state.update { it.copy(selectedDiffTurn = turnNumber) }
    }

    public fun selectDiffMode(mode: DiffCompareMode) {
        _state.update { it.copy(compareMode = mode) }
    }

    public fun selectDiffFile(fileIndex: Int) {
        _state.update { prev ->
            val clamped = if (prev.diffs.isEmpty()) 0 else fileIndex.coerceIn(0, prev.diffs.lastIndex)
            prev.copy(selectedDiffFileIndex = clamped)
        }
    }

    public fun selectDiffLine(lineNumber: Int) {
        _state.update { it.copy(selectedDiffLineNumber = lineNumber) }
    }

    public fun addDiffLineComment(
        filePath: String,
        lineNumber: Int,
        body: String,
        sentToAgent: Boolean = false,
    ): DiffLineComment? {
        val trimmed = body.trim()
        if (trimmed.isEmpty()) return null
        val comment = DiffLineComment(
            id = "diff-comment-${currentTimeMillis()}-${Random.nextInt(100, 999)}",
            filePath = filePath,
            lineNumber = lineNumber,
            body = trimmed,
            sentToAgent = sentToAgent,
            author = "You",
            createdAtEpochMs = currentTimeMillis(),
        )
        _state.update { prev ->
            prev.copy(diffLineComments = prev.diffLineComments + comment)
        }
        return comment
    }

    public suspend fun sendDiffLineComments(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
    ) {
        val current = _state.value.diffLineComments
        if (current.isEmpty()) return
        val toSend = current.filter { !it.sentToAgent }.ifEmpty { current }
        val previous = current

        _state.update { prev ->
            prev.copy(
                diffLineComments = prev.diffLineComments.map { it.copy(sentToAgent = true) },
                lastCapabilityError = null,
            )
        }

        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.TURN_DIFF,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(diffLineComments = previous) } },
        ) { rpc ->
            rpc.sendDiffReviewComments(cascadeId = cascadeId, comments = toSend)
        }
    }

    public fun toggleFileReviewed(filePath: String) {
        _state.update { prev ->
            prev.copy(
                diffs = prev.diffs.map { diff ->
                    if (diff.filePath == filePath) diff.copy(isReviewed = !diff.isReviewed) else diff
                },
            )
        }
    }

    public fun acceptAllDiffs() {
        _state.update { prev ->
            prev.copy(diffs = prev.diffs.map { it.copy(isReviewed = true) })
        }
    }

    public suspend fun revertHunk(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        filePath: String,
        hunkHeader: String? = null,
    ) {
        val previousDiffs = _state.value.diffs
        val previousIndex = _state.value.selectedDiffFileIndex
        _state.update { prev ->
            val nextDiffs = prev.diffs.filterNot { diff ->
                diff.filePath == filePath && (hunkHeader == null || diff.hunkHeader == hunkHeader)
            }
            val nextIndex = if (nextDiffs.isEmpty()) 0 else prev.selectedDiffFileIndex.coerceIn(0, nextDiffs.lastIndex)
            prev.copy(
                diffs = nextDiffs,
                selectedDiffFileIndex = nextIndex,
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.TURN_DIFF,
            onUnsupported = ::recordCapabilityError,
            rollback = {
                _state.update {
                    it.copy(diffs = previousDiffs, selectedDiffFileIndex = previousIndex)
                }
            },
        ) { rpc ->
            rpc.revertDiffHunk(
                cascadeId = cascadeId,
                filePath = filePath,
                hunkHeader = hunkHeader,
            )
        }
    }

    public suspend fun stageFile(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        filePath: String,
    ) {
        val previousDiffs = _state.value.diffs
        _state.update { prev ->
            prev.copy(
                diffs = prev.diffs.map { diff ->
                    if (diff.filePath == filePath) diff.copy(isStaged = true) else diff
                },
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.GIT_VCS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(diffs = previousDiffs) } },
        ) { rpc ->
            rpc.gitStageFile(cascadeId = cascadeId, filePath = filePath)
        }
    }

    public suspend fun unstageFile(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        filePath: String,
    ) {
        val previousDiffs = _state.value.diffs
        _state.update { prev ->
            prev.copy(
                diffs = prev.diffs.map { diff ->
                    if (diff.filePath == filePath) diff.copy(isStaged = false) else diff
                },
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.GIT_VCS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(diffs = previousDiffs) } },
        ) { rpc ->
            rpc.gitUnstageFile(cascadeId = cascadeId, filePath = filePath)
        }
    }

    public suspend fun discardFile(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        filePath: String,
    ) {
        val previousDiffs = _state.value.diffs
        val previousIndex = _state.value.selectedDiffFileIndex
        _state.update { prev ->
            val nextDiffs = prev.diffs.filterNot { it.filePath == filePath }
            val nextIndex = if (nextDiffs.isEmpty()) 0 else prev.selectedDiffFileIndex.coerceIn(0, nextDiffs.lastIndex)
            prev.copy(
                diffs = nextDiffs,
                selectedDiffFileIndex = nextIndex,
                lastCapabilityError = null,
            )
        }
        performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.GIT_VCS,
            onUnsupported = ::recordCapabilityError,
            rollback = {
                _state.update {
                    it.copy(diffs = previousDiffs, selectedDiffFileIndex = previousIndex)
                }
            },
        ) { rpc ->
            rpc.gitDiscardFile(cascadeId = cascadeId, filePath = filePath)
        }
    }

    public suspend fun commitChanges(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        draft: GitCommitDraft,
    ): GitCommitResult? {
        val trimmedMessage = draft.message.trim()
        if (trimmedMessage.isEmpty()) return null
        val previousResult = _state.value.lastCommitResult
        val previousDiffs = _state.value.diffs
        val optimistic = GitCommitResult(
            commitHash = "local-${Random.nextInt(100000, 999999)}",
            summary = trimmedMessage,
            pushed = draft.pushAfterCommit,
            branchName = "main",
        )
        _state.update { prev ->
            prev.copy(
                lastCommitResult = optimistic,
                diffs = prev.diffs.map { it.copy(isStaged = false, isReviewed = true) },
                lastCapabilityError = null,
            )
        }
        if (client == null) return optimistic

        val remote = performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.GIT_VCS,
            onUnsupported = ::recordCapabilityError,
            rollback = {
                _state.update {
                    it.copy(lastCommitResult = previousResult, diffs = previousDiffs)
                }
            },
        ) { rpc ->
            rpc.gitCommitChanges(cascadeId = cascadeId, draft = draft)
        }
        if (remote != null) {
            _state.update { it.copy(lastCommitResult = remote) }
        }
        return remote
    }

    public suspend fun pushBranch(
        client: AntigravityKmpRpcClient?,
        cascadeId: String,
        branchName: String = "main",
    ): Boolean {
        val previousResult = _state.value.lastCommitResult
        _state.update { prev ->
            prev.copy(
                lastCommitResult = prev.lastCommitResult?.copy(pushed = true, branchName = branchName),
                lastCapabilityError = null,
            )
        }
        if (client == null) return true
        val pushed = performLiveCapabilityWrite(
            client = client,
            capability = HostCapability.GIT_VCS,
            onUnsupported = ::recordCapabilityError,
            rollback = { _state.update { it.copy(lastCommitResult = previousResult) } },
        ) { rpc ->
            rpc.gitPushBranch(cascadeId = cascadeId, branchName = branchName)
        }
        return pushed == true
    }

    public fun clearCapabilityError() {
        _state.update { it.copy(lastCapabilityError = null) }
    }

    private fun recordCapabilityError(message: String) {
        _state.update { it.copy(lastCapabilityError = message) }
        onCapabilityError(message)
    }
}
