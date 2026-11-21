import Foundation

/// Policy helper for mobile Safe Auto-Accept of read-only workspace operations.
public enum SafeAutoAcceptPolicy: Sendable {
    private static let safeGitSubcommands: Set<String> = [
        "status", "diff", "log", "branch", "show", "rev-parse"
    ]

    private static let safeExecutables: Set<String> = [
        "ls", "pwd", "cat", "head", "tail", "wc", "which", "rg", "grep", "find"
    ]

    private static let shellChainTokens: [String] = [
        "&&", "||", ";", "|", ">", "<", "$(", "`"
    ]

    /// Returns `true` only for deterministic read-only commands without shell chaining or redirection.
    public static func isSafeReadOnlyCommand(_ commandLine: String) -> Bool {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        for token in shellChainTokens where trimmed.contains(token) {
            return false
        }
        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let binary = parts.first else { return false }
        if binary == "git" {
            guard parts.count >= 2 else { return false }
            return safeGitSubcommands.contains(parts[1])
        }
        if binary == "find" && (parts.contains("-delete") || parts.contains("-exec")) {
            return false
        }
        return safeExecutables.contains(binary)
    }

    public static func canAutoAccept(step: CascadeStep, allowedWorkspaceRoots: [String]) -> Bool {
        InteractionBuilder.canSafeAutoAccept(step: step, allowedWorkspaceRoots: allowedWorkspaceRoots)
    }
}

/// Builds authoritative `HandleCascadeUserInteraction` request payloads matching
/// the exact oneof member declared in `step.requestedInteraction`.
///
/// As verified against Antigravity's LanguageServer (`exa.cortex_pb.CascadeUserInteraction`),
/// answering with any member other than the one declared in `requestedInteraction` is
/// silently dropped by the server.
public enum InteractionBuilder: Sendable {

    private static let readOnlyVerbs: Set<String> = [
        "read", "list", "view", "search", "stat", "glob", "grep", "find", "fetch", "get"
    ]

    public static func buildPayload(
        step: CascadeStep,
        decision: InteractionDecision,
        workspaceUri: String? = nil
    ) -> CascadeUserInteractionPayload? {
        guard let requested = step.effectiveRequestedInteraction else {
            return nil
        }

        // Never fabricate a mismatched `approvalInteraction` oneof when binary Protobuf decoded an unknown field number
        // without recovering its exact JSON `rawMemberKey` — newer servers silently drop mismatched oneof replies.
        if requested.isUnrecognizedWireMember && (requested.rawMemberKey?.isEmpty != false) {
            return nil
        }

        if decision == .reject {
            switch requested.kind {
            case .permission:
                return CascadeUserInteractionPayload(
                    cascadeId: step.cascadeId,
                    stepIndex: step.stepIndex,
                    kind: .permission,
                    workspaceUri: workspaceUri,
                    permission: .init(allow: false),
                    rawMemberKey: requested.rawMemberKey
                )
            case .filePermission:
                return CascadeUserInteractionPayload(
                    cascadeId: step.cascadeId,
                    stepIndex: step.stepIndex,
                    kind: .filePermission,
                    workspaceUri: workspaceUri,
                    filePermission: .init(allow: false, absolutePathUri: requested.filePermission?.absolutePathUri),
                    rawMemberKey: requested.rawMemberKey
                )
            case .runCommand:
                let proposed = requested.runCommand?.proposedCommandLine
                    ?? step.runCommand?.proposedCommandLine
                    ?? step.runCommand?.commandLine
                    ?? ""
                return CascadeUserInteractionPayload(
                    cascadeId: step.cascadeId,
                    stepIndex: step.stepIndex,
                    kind: .runCommand,
                    workspaceUri: workspaceUri,
                    runCommand: .init(
                        confirm: false,
                        proposedCommandLine: proposed,
                        submittedCommandLine: proposed,
                        faceIdVerified: false
                    ),
                    rawMemberKey: requested.rawMemberKey
                )
            default:
                return CascadeUserInteractionPayload(
                    cascadeId: step.cascadeId,
                    stepIndex: step.stepIndex,
                    kind: requested.kind,
                    workspaceUri: workspaceUri,
                    genericConfirm: false,
                    rawMemberKey: requested.rawMemberKey
                )
            }
        }

        let resolvedScope: String
        switch decision {
        case .allowInConversation:
            resolvedScope = "PERMISSION_SCOPE_CONVERSATION"
        case .alwaysAllow:
            resolvedScope = "PERMISSION_SCOPE_ALWAYS"
        case .alwaysAllowInTurn:
            resolvedScope = "PERMISSION_SCOPE_TURN"
        default:
            resolvedScope = "PERMISSION_SCOPE_ONCE"
        }

        switch requested.kind {
        case .permission:
            var grants: [String] = []
            if let spec = requested.permission {
                let shouldGrant = (decision == .alwaysAllowInTurn || decision == .allowInConversation || decision == .alwaysAllow)
                if shouldGrant && spec.persistSuggestionType != .blocked {
                    let patternTarget = spec.suggestedPersistPattern ?? spec.target
                    grants = ["\(spec.action)(\(patternTarget))"]
                }
            }
            return CascadeUserInteractionPayload(
                cascadeId: step.cascadeId,
                stepIndex: step.stepIndex,
                kind: .permission,
                workspaceUri: workspaceUri,
                permission: .init(allow: true, grantPatterns: grants, scope: resolvedScope),
                approvalScope: resolvedScope,
                rawMemberKey: requested.rawMemberKey
            )

        case .filePermission:
            let uri = requested.filePermission?.absolutePathUri
            return CascadeUserInteractionPayload(
                cascadeId: step.cascadeId,
                stepIndex: step.stepIndex,
                kind: .filePermission,
                workspaceUri: workspaceUri,
                filePermission: .init(allow: true, scope: resolvedScope, absolutePathUri: uri),
                approvalScope: resolvedScope,
                rawMemberKey: requested.rawMemberKey
            )

        case .runCommand:
            let proposed = requested.runCommand?.proposedCommandLine
                ?? step.runCommand?.proposedCommandLine
                ?? step.runCommand?.commandLine
                ?? ""
            let submitted: String
            if case .allowWithModifiedCommand(let custom) = decision {
                submitted = custom
            } else {
                submitted = proposed
            }
            let faceId = (decision == .allowWithFaceID)
            return CascadeUserInteractionPayload(
                cascadeId: step.cascadeId,
                stepIndex: step.stepIndex,
                kind: .runCommand,
                workspaceUri: workspaceUri,
                runCommand: .init(
                    confirm: true,
                    proposedCommandLine: proposed,
                    submittedCommandLine: submitted,
                    faceIdVerified: faceId
                ),
                approvalScope: resolvedScope,
                rawMemberKey: requested.rawMemberKey
            )

        case .askQuestion, .elicitation:
            guard case .answerQuestion(let selectedOptions, let customWriteIn) = decision else {
                return nil
            }
            return CascadeUserInteractionPayload(
                cascadeId: step.cascadeId,
                stepIndex: step.stepIndex,
                kind: requested.kind,
                workspaceUri: workspaceUri,
                askQuestion: .init(
                    selectedOptions: selectedOptions,
                    customResponse: (customWriteIn?.isEmpty == false) ? customWriteIn : nil
                ),
                rawMemberKey: requested.rawMemberKey
            )

        case .executeUrl, .downloadUrl, .mcp:
            return CascadeUserInteractionPayload(
                cascadeId: step.cascadeId,
                stepIndex: step.stepIndex,
                kind: requested.kind,
                workspaceUri: workspaceUri,
                genericConfirm: true,
                approvalScope: resolvedScope,
                rawMemberKey: requested.rawMemberKey
            )

        case .browserUpload, .workflowScript:
            // One-time browser upload and dynamic workflow script approvals are strictly single-use
            return CascadeUserInteractionPayload(
                cascadeId: step.cascadeId,
                stepIndex: step.stepIndex,
                kind: requested.kind,
                workspaceUri: workspaceUri,
                genericConfirm: true,
                approvalScope: "PERMISSION_SCOPE_ONCE",
                rawMemberKey: requested.rawMemberKey
            )

        default:
            return CascadeUserInteractionPayload(
                cascadeId: step.cascadeId,
                stepIndex: step.stepIndex,
                kind: requested.kind,
                workspaceUri: workspaceUri,
                genericConfirm: true,
                approvalScope: resolvedScope,
                rawMemberKey: requested.rawMemberKey
            )
        }
    }

    /// Evaluates whether a `WAITING` step is eligible for Safe Auto-Accept on mobile.
    /// Read-only permissions and workspace-scoped file reads auto-resolve; commands, browser
    /// actions/downloads/uploads, workflow scripts, MCP writes, and `ask_question` always require explicit user action.
    public static func canSafeAutoAccept(step: CascadeStep, allowedWorkspaceRoots: [String]) -> Bool {
        guard step.status == .waiting,
              let requested = step.requestedInteraction,
              !requested.isUnrecognizedWireMember else {
            return false
        }
        switch requested.kind {
        case .permission:
            guard let action = requested.permission?.action.lowercased() else { return false }
            return readOnlyVerbs.contains(action)
        case .filePermission:
            guard let uri = requested.filePermission?.absolutePathUri else { return false }
            return allowedWorkspaceRoots.contains { uri.hasPrefix($0) }
        case .askQuestion, .elicitation, .runCommand, .sendCommandInput,
             .executeUrl, .downloadUrl, .browserUpload, .workflowScript, .mcp:
            return false
        default:
            return false
        }
    }
}
