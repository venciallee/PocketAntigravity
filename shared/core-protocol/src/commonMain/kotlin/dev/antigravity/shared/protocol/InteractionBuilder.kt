package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeUserInteractionPayload
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.PersistSuggestionType
import dev.antigravity.shared.model.RequestedInteraction

/**
 * Policy helper for mobile Safe Auto-Accept of read-only workspace operations.
 */
public object SafeAutoAcceptPolicy {
    private val safeGitSubcommands = setOf("status", "diff", "log", "branch", "show", "rev-parse")
    private val safeExecutables = setOf("ls", "pwd", "cat", "head", "tail", "wc", "which", "rg", "grep", "find")
    private val shellChainTokens = listOf("&&", "||", ";", "|", ">", "<", "\$(", "`")

    public fun isSafeReadOnlyCommand(commandLine: String): Boolean {
        val trimmed = commandLine.trim()
        if (trimmed.isEmpty()) return false
        if (shellChainTokens.any { trimmed.contains(it) }) return false
        val parts = trimmed.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val binary = parts.firstOrNull() ?: return false
        if (binary == "git") {
            return parts.size >= 2 && parts[1] in safeGitSubcommands
        }
        if (binary == "find" && ("-delete" in parts || "-exec" in parts)) {
            return false
        }
        return binary in safeExecutables
    }

    public fun canAutoAccept(step: CascadeStep, allowedWorkspaceRoots: List<String>): Boolean =
        InteractionBuilder.canSafeAutoAccept(step, allowedWorkspaceRoots)
}

/**
 * Builds authoritative `HandleCascadeUserInteraction` request payloads matching
 * the exact oneof member declared in `step.requestedInteraction`.
 */
public object InteractionBuilder {
    private val readOnlyVerbs = setOf(
        "read", "list", "view", "search", "stat", "glob", "grep", "find", "fetch", "get",
    )

    public fun buildPayload(
        step: CascadeStep,
        decision: InteractionDecision,
        workspaceUri: String? = null,
    ): CascadeUserInteractionPayload? {
        val requested = step.requestedInteraction ?: return null

        if (decision == InteractionDecision.Reject) {
            return when (requested.kind) {
                RequestedInteraction.MemberKind.PERMISSION -> CascadeUserInteractionPayload(
                    cascadeId = step.cascadeId,
                    stepIndex = step.stepIndex,
                    kind = RequestedInteraction.MemberKind.PERMISSION,
                    workspaceUri = workspaceUri,
                    permission = CascadeUserInteractionPayload.PermissionAnswer(allow = false),
                )
                RequestedInteraction.MemberKind.FILE_PERMISSION -> CascadeUserInteractionPayload(
                    cascadeId = step.cascadeId,
                    stepIndex = step.stepIndex,
                    kind = RequestedInteraction.MemberKind.FILE_PERMISSION,
                    workspaceUri = workspaceUri,
                    filePermission = CascadeUserInteractionPayload.FilePermissionAnswer(
                        allow = false,
                        absolutePathUri = requested.filePermission?.absolutePathUri,
                    ),
                )
                RequestedInteraction.MemberKind.RUN_COMMAND -> {
                    val proposed = requested.runCommand?.proposedCommandLine
                        ?: step.runCommand?.proposedCommandLine
                        ?: step.runCommand?.commandLine
                        ?: ""
                    CascadeUserInteractionPayload(
                        cascadeId = step.cascadeId,
                        stepIndex = step.stepIndex,
                        kind = RequestedInteraction.MemberKind.RUN_COMMAND,
                        workspaceUri = workspaceUri,
                        runCommand = CascadeUserInteractionPayload.RunCommandAnswer(
                            confirm = false,
                            proposedCommandLine = proposed,
                            submittedCommandLine = proposed,
                            biometricVerified = false,
                        ),
                    )
                }
                else -> CascadeUserInteractionPayload(
                    cascadeId = step.cascadeId,
                    stepIndex = step.stepIndex,
                    kind = requested.kind,
                    workspaceUri = workspaceUri,
                    genericConfirm = false,
                )
            }
        }

        val resolvedScope = when (decision) {
            InteractionDecision.AllowInConversation -> "PERMISSION_SCOPE_CONVERSATION"
            InteractionDecision.AlwaysAllow -> "PERMISSION_SCOPE_ALWAYS"
            InteractionDecision.AlwaysAllowInTurn -> "PERMISSION_SCOPE_TURN"
            else -> "PERMISSION_SCOPE_ONCE"
        }

        return when (requested.kind) {
            RequestedInteraction.MemberKind.PERMISSION -> {
                val spec = requested.permission ?: return null
                val shouldGrant = decision == InteractionDecision.AlwaysAllowInTurn ||
                    decision == InteractionDecision.AllowInConversation ||
                    decision == InteractionDecision.AlwaysAllow
                val grants = if (shouldGrant && spec.persistSuggestionType != PersistSuggestionType.BLOCKED) {
                    val patternTarget = spec.suggestedPersistPattern ?: spec.target
                    listOf("${spec.action}($patternTarget)")
                } else {
                    emptyList()
                }
                CascadeUserInteractionPayload(
                    cascadeId = step.cascadeId,
                    stepIndex = step.stepIndex,
                    kind = RequestedInteraction.MemberKind.PERMISSION,
                    workspaceUri = workspaceUri,
                    permission = CascadeUserInteractionPayload.PermissionAnswer(
                        allow = true,
                        grantPatterns = grants,
                        scope = resolvedScope,
                    ),
                    approvalScope = resolvedScope,
                )
            }
            RequestedInteraction.MemberKind.FILE_PERMISSION -> CascadeUserInteractionPayload(
                cascadeId = step.cascadeId,
                stepIndex = step.stepIndex,
                kind = RequestedInteraction.MemberKind.FILE_PERMISSION,
                workspaceUri = workspaceUri,
                filePermission = CascadeUserInteractionPayload.FilePermissionAnswer(
                    allow = true,
                    scope = resolvedScope,
                    absolutePathUri = requested.filePermission?.absolutePathUri,
                ),
                approvalScope = resolvedScope,
            )
            RequestedInteraction.MemberKind.RUN_COMMAND -> {
                val proposed = requested.runCommand?.proposedCommandLine
                    ?: step.runCommand?.proposedCommandLine
                    ?: step.runCommand?.commandLine
                    ?: ""
                val submitted = (decision as? InteractionDecision.AllowWithModifiedCommand)?.commandLine ?: proposed
                CascadeUserInteractionPayload(
                    cascadeId = step.cascadeId,
                    stepIndex = step.stepIndex,
                    kind = RequestedInteraction.MemberKind.RUN_COMMAND,
                    workspaceUri = workspaceUri,
                    runCommand = CascadeUserInteractionPayload.RunCommandAnswer(
                        confirm = true,
                        proposedCommandLine = proposed,
                        submittedCommandLine = submitted,
                        biometricVerified = decision == InteractionDecision.AllowWithBiometric,
                    ),
                    approvalScope = resolvedScope,
                )
            }
            RequestedInteraction.MemberKind.ASK_QUESTION,
            RequestedInteraction.MemberKind.ELICITATION -> {
                val answer = decision as? InteractionDecision.AnswerQuestion ?: return null
                CascadeUserInteractionPayload(
                    cascadeId = step.cascadeId,
                    stepIndex = step.stepIndex,
                    kind = requested.kind,
                    workspaceUri = workspaceUri,
                    askQuestion = CascadeUserInteractionPayload.AskQuestionAnswer(
                        selectedOptions = answer.selectedOptions,
                        customResponse = answer.customWriteIn?.takeIf { it.isNotEmpty() },
                    ),
                )
            }
            RequestedInteraction.MemberKind.BROWSER_UPLOAD,
            RequestedInteraction.MemberKind.WORKFLOW_SCRIPT -> CascadeUserInteractionPayload(
                cascadeId = step.cascadeId,
                stepIndex = step.stepIndex,
                kind = requested.kind,
                workspaceUri = workspaceUri,
                genericConfirm = true,
                approvalScope = "PERMISSION_SCOPE_ONCE",
            )
            else -> CascadeUserInteractionPayload(
                cascadeId = step.cascadeId,
                stepIndex = step.stepIndex,
                kind = requested.kind,
                workspaceUri = workspaceUri,
                genericConfirm = true,
                approvalScope = resolvedScope,
            )
        }
    }

    public fun canSafeAutoAccept(step: CascadeStep, allowedWorkspaceRoots: List<String>): Boolean {
        if (step.status != CortexStepStatus.WAITING) return false
        val requested = step.requestedInteraction ?: return false
        return when (requested.kind) {
            RequestedInteraction.MemberKind.PERMISSION -> {
                val action = requested.permission?.action?.lowercase() ?: return false
                action in readOnlyVerbs
            }
            RequestedInteraction.MemberKind.FILE_PERMISSION -> {
                val uri = requested.filePermission?.absolutePathUri ?: return false
                allowedWorkspaceRoots.any { uri.startsWith(it) }
            }
            else -> false
        }
    }
}
