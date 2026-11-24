import Foundation
import AntigravityData
#if canImport(AntigravityShared)
@preconcurrency import AntigravityShared

/// Lossless bidirectional converters between SKIE-bridged `AntigravityShared` (KMP) models
/// and `AntigravityData` (Swift 6 UI/ViewModel) models.
enum KmpModelConverters {

    // MARK: - Error Mapping (KMP -> Swift)

    static func mapKmpError(_ error: Error) -> Error {
        let nsErr = error as NSError
        if let kotlinThrowable = nsErr.userInfo["KotlinException"] as? KotlinThrowable {
            let tag = KmpBridgeHelpers.shared.errorKindTag(throwable: kotlinThrowable)
            let detail = KmpBridgeHelpers.shared.errorDetailMessage(throwable: kotlinThrowable)
            let msg = detail.isEmpty ? (kotlinThrowable.message ?? nsErr.localizedDescription) : detail
            if tag == "unauthorized" {
                return AntigravityData.AntigravityRPCError.unauthorized(msg)
            }
            if tag == "invalidEndpoint" {
                return AntigravityData.AntigravityRPCError.invalidEndpoint
            }
            if tag.hasPrefix("http:") {
                let code = Int(tag.dropFirst("http:".count)) ?? 500
                let cleanBody = ProtocolCompatibilityEngine.stripRedundantHttpPrefix(from: msg, statusCode: code)
                return AntigravityData.AntigravityRPCError.httpError(statusCode: code, body: cleanBody)
            }
            if tag == "decoding" {
                return AntigravityData.AntigravityRPCError.decodingError(msg)
            }
            if tag == "interactionRejected" {
                return AntigravityData.AntigravityRPCError.interactionRejected
            }
        }
        return error
    }

    // MARK: - Credentials

    static func toSwiftCredentials(
        _ creds: AntigravityShared.SavedBackendCredentials
    ) -> AntigravityData.SavedBackendCredentials {
        let isRelay = KmpBridgeHelpers.shared.isCloudRelayChannel(channel: creds.channel)
        return AntigravityData.SavedBackendCredentials(
            endpointURLString: creds.endpointUrlString,
            channel: isRelay ? .cloudRelay : .directHost,
            hostname: creds.hostname,
            csrfToken: creds.csrfToken,
            sessionCookie: creds.sessionCookie,
            authUser: creds.authUser,
            resolvedInstanceUuid: creds.resolvedInstanceUuid,
            relayApiKey: creds.relayApiKey,
            certFingerprintSHA256: creds.certFingerprintSha256,
            pairedAt: creds.pairedAtEpochMs > 0
                ? Date(timeIntervalSince1970: Double(creds.pairedAtEpochMs) / 1000.0)
                : Date()
        )
    }

    static func toKmpCredentials(
        _ creds: AntigravityData.SavedBackendCredentials
    ) -> AntigravityShared.SavedBackendCredentials {
        KmpBridgeHelpers.shared.makeSavedCredentials(
            endpointUrlString: creds.endpointURLString,
            isCloudRelay: creds.channel == .cloudRelay,
            hostname: creds.hostname,
            csrfToken: creds.csrfToken,
            sessionCookie: creds.sessionCookie,
            authUser: creds.authUser,
            resolvedInstanceUuid: creds.resolvedInstanceUuid,
            relayApiKey: creds.relayApiKey,
            certFingerprintSha256: creds.certFingerprintSHA256,
            pairedAtEpochMs: Int64(creds.pairedAt.timeIntervalSince1970 * 1000.0)
        )
    }

    // MARK: - Relay & Workspace & Project (KMP -> Swift)

    static func toSwiftRelayInstance(_ kmp: AntigravityShared.RelayInstanceInfo) -> AntigravityData.RelayInstanceInfo {
        AntigravityData.RelayInstanceInfo(
            uuid: kmp.uuid,
            name: kmp.name,
            version: kmp.version,
            supportsChunking: kmp.supportsChunking,
            status: AntigravityData.RelayInstanceStatus(rawStatusCode: Int(kmp.status.rawCode)),
            updatedAt: kmp.updatedAtEpochMs.map { Date(timeIntervalSince1970: Double($0.int64Value) / 1000.0) }
        )
    }

    static func toKmpRelayInstance(_ swift: AntigravityData.RelayInstanceInfo) -> AntigravityShared.RelayInstanceInfo {
        KmpBridgeHelpers.shared.makeRelayInstanceInfo(
            uuid: swift.uuid,
            name: swift.name,
            version: swift.version,
            supportsChunking: swift.supportsChunking,
            statusRawCode: Int32(swift.status.rawValue),
            updatedAtEpochMs: swift.updatedAt.map { KotlinLong(value: Int64($0.timeIntervalSince1970 * 1000.0)) }
        )
    }

    static func toSwiftWorkspace(_ kmp: AntigravityShared.WorkspaceInfo) -> AntigravityData.WorkspaceInfo {
        AntigravityData.WorkspaceInfo(
            workspaceUri: kmp.workspaceUri,
            displayName: kmp.displayName,
            activeBranch: kmp.activeBranch,
            worktrees: kmp.worktrees,
            activeCascadeCount: Int(kmp.activeCascadeCount),
            indexedFiles: kmp.indexedFiles,
            isCloud: kmp.isCloud,
            originInstanceUuid: kmp.originInstanceUuid,
            originHostName: kmp.originHostName
        )
    }

    static func toSwiftProject(_ kmp: AntigravityShared.ProjectWorkspace) -> AntigravityData.ProjectWorkspace {
        let isCloud = KmpBridgeHelpers.shared.isCloudProjectRuntime(runtime: kmp.runtime)
        return AntigravityData.ProjectWorkspace(
            id: kmp.id,
            name: kmp.name,
            pathDisplay: kmp.pathDisplay,
            workspaceUri: kmp.workspaceUri,
            runtime: isCloud ? .cloud : .macBookPro,
            hostName: kmp.hostName,
            activeBranch: kmp.activeBranch,
            worktrees: kmp.worktrees,
            isExpandedInHome: kmp.isExpandedInHome,
            rulesAndSkillsCount: Int(kmp.rulesAndSkillsCount),
            cloudProjectId: kmp.cloudProjectId,
            originInstanceUuid: kmp.originInstanceUuid
        )
    }

    static func toSwiftSummary(_ kmp: AntigravityShared.CascadeSummary) -> AntigravityData.CascadeSummary {
        let status = AntigravityData.CortexStepStatus(rawValue: Int(kmp.status.rawValue)) ?? .unspecified
        let updatedDate = kmp.updatedAtEpochMs > 0
            ? Date(timeIntervalSince1970: Double(kmp.updatedAtEpochMs) / 1000.0)
            : Date()
        let lastViewed = kmp.lastUserViewTimeEpochMs.map {
            Date(timeIntervalSince1970: Double($0.int64Value) / 1000.0)
        }
        return AntigravityData.CascadeSummary(
            cascadeId: kmp.cascadeId,
            title: kmp.title,
            projectSlug: kmp.projectSlug,
            workspaceUri: kmp.workspaceUri,
            branchName: kmp.branchName,
            status: status,
            stepCount: Int(kmp.stepCount),
            currentStepIndex: Int(kmp.currentStepIndex),
            totalSteps: Int(kmp.totalSteps),
            updatedAt: updatedDate,
            relativeTimeLabel: kmp.relativeTimeLabel,
            statusSubtitle: kmp.statusSubtitle,
            isPinned: kmp.isPinned,
            isArchived: kmp.isArchived,
            isUnread: kmp.isUnread,
            modelLabel: kmp.modelLabel,
            pendingInteractionTitle: kmp.pendingInteractionTitle,
            lastMessagePreview: kmp.lastMessagePreview,
            totalAdditions: Int(kmp.totalAdditions),
            totalDeletions: Int(kmp.totalDeletions),
            isCloud: kmp.isCloud,
            cloudProjectId: kmp.cloudProjectId,
            originInstanceUuid: kmp.originInstanceUuid,
            originHostName: kmp.originHostName,
            lastUserViewTime: lastViewed
        )
    }

    static func toSwiftHandshake(
        _ kmp: AntigravityShared.BackendHandshakeResult
    ) -> AntigravityData.BackendHandshakeResult {
        AntigravityData.BackendHandshakeResult(
            latencyMs: Int(kmp.latencyMs),
            workspaces: kmp.workspaces.map(toSwiftWorkspace),
            summaries: kmp.summaries.map(toSwiftSummary),
            cloudProjects: kmp.cloudProjects.map(toSwiftProject),
            serverVersion: kmp.serverVersion,
            resolvedHostname: kmp.resolvedHostname,
            resolvedInstanceUuid: kmp.resolvedInstanceUuid,
            resolvedAuthUser: kmp.resolvedAuthUser,
            resolvedRelayApiKey: kmp.resolvedRelayApiKey,
            availableRelayInstances: kmp.availableRelayInstances.map(toSwiftRelayInstance),
            isSelectedHostOnline: kmp.isSelectedHostOnline
        )
    }

    static func toSwiftProbeResult(
        _ kmp: AntigravityShared.HostReachabilityProbeResult
    ) -> AntigravityData.HostReachabilityProbeResult {
        AntigravityData.HostReachabilityProbeResult(
            latencyMs: Int(kmp.latencyMs),
            availableRelayInstances: kmp.availableRelayInstances.map(toSwiftRelayInstance),
            activeRelayInstance: kmp.activeRelayInstance.map(toSwiftRelayInstance),
            relayTopologyChanged: kmp.relayTopologyChanged,
            relayMetadataChanged: kmp.relayMetadataChanged,
            isSelectedHostOnline: kmp.isSelectedHostOnline
        )
    }

    static func toSwiftFederatedSync(
        _ kmp: AntigravityShared.FederatedWorkspaceSyncResult
    ) -> AntigravityData.KmpFederatedSyncResult {
        AntigravityData.KmpFederatedSyncResult(
            workspaces: kmp.workspaces.map(toSwiftWorkspace),
            summaries: kmp.summaries.map(toSwiftSummary),
            cloudProjects: kmp.cloudProjects.map(toSwiftProject),
            cloudWarmingUp: kmp.cloudWarmingUp,
            availableRelayInstances: kmp.availableRelayInstances.map(toSwiftRelayInstance),
            succeededInstanceUuids: kmp.succeededInstanceUuids,
            cloudSucceeded: kmp.cloudSucceeded,
            latencyMs: Int(kmp.latencyMs)
        )
    }

    // MARK: - CascadeStep & RequestedInteraction (KMP -> Swift)

    static func toSwiftStep(_ kmp: AntigravityShared.CascadeStep) -> AntigravityData.CascadeStep {
        let stepType = AntigravityData.CortexStepType(rawValue: Int(kmp.type.rawValue)) ?? .unspecified
        let stepStatus = AntigravityData.CortexStepStatus(rawValue: Int(kmp.status.rawValue)) ?? .unspecified
        let createdDate = kmp.createdAtEpochMs > 0
            ? Date(timeIntervalSince1970: Double(kmp.createdAtEpochMs) / 1000.0)
            : Date()

        let planner = kmp.plannerResponse.map { pr in
            AntigravityData.PlannerResponsePayload(
                response: pr.response,
                thinking: pr.thinking,
                thinkingDurationSeconds: pr.thinkingDurationSeconds?.doubleValue,
                messageId: pr.messageId,
                referencedFiles: pr.referencedFiles
            )
        }

        let taskBoundary = kmp.taskBoundary.map { tb in
            let items = tb.checklist.map { item -> AntigravityData.TaskChecklistItem in
                let raw = KmpBridgeHelpers.shared.taskChecklistStatusRaw(status: item.status)
                let st = AntigravityData.TaskChecklistStatus(rawValue: raw) ?? .pending
                return AntigravityData.TaskChecklistItem(
                    id: item.id,
                    title: item.title,
                    status: st,
                    trailingBadge: item.trailingBadge
                )
            }
            return AntigravityData.TaskBoundaryPayload(
                taskName: tb.taskName,
                taskStatus: tb.taskStatus,
                taskSummary: tb.taskSummary,
                completedCount: Int(tb.completedCount),
                totalCount: Int(tb.totalCount),
                elapsedLabel: tb.elapsedLabel,
                checklist: items
            )
        }

        let runCommand = kmp.runCommand.map { rc in
            AntigravityData.RunCommandPayload(
                commandId: rc.commandId,
                commandLine: rc.commandLine,
                proposedCommandLine: rc.proposedCommandLine,
                cwd: rc.cwd,
                exitCode: rc.exitCode.map { Int($0.int32Value) },
                outputPreview: rc.outputPreview,
                durationMs: rc.durationMs.map { Int($0.int32Value) }
            )
        }

        let codeAction = kmp.codeAction.map { ca in
            AntigravityData.CodeActionPayload(
                targetFileUri: ca.targetFileUri,
                description: ca.description_,
                additions: Int(ca.additions),
                deletions: Int(ca.deletions),
                isArtifactFile: ca.isArtifactFile,
                startLine: ca.startLine.map { Int($0.int32Value) },
                endLine: ca.endLine.map { Int($0.int32Value) },
                diffPreviewLines: ca.diffPreviewLines,
                fileContent: ca.fileContent
            )
        }

        let viewFile = kmp.viewFile.map { vf in
            AntigravityData.ViewFilePayload(
                fileUri: vf.fileUri,
                startLine: Int(vf.startLine),
                endLine: Int(vf.endLine),
                totalLines: Int(vf.totalLines),
                fileContent: vf.fileContent
            )
        }

        let search = kmp.search.map { sc in
            AntigravityData.SearchPayload(
                query: sc.query,
                scopeDirectory: sc.scopeDirectory,
                matchCount: Int(sc.matchCount)
            )
        }

        let requestedInteraction = kmp.requestedInteraction.map(toSwiftRequestedInteraction)
        let recordedMode: AntigravityData.CascadeExecutionMode? = kmp.recordedExecutionMode.map {
            KmpBridgeHelpers.shared.isPlanningMode(mode: $0) ? .planning : .fast
        }

        let subagent = kmp.subagent.map { sub in
            AntigravityData.SubagentPayload(
                subagentId: sub.subagentId,
                role: sub.role,
                typeName: sub.typeName,
                modelLabel: sub.modelLabel,
                status: AntigravityData.CortexStepStatus(rawValue: Int(sub.status.rawValue)) ?? .inProgress,
                summary: sub.summary,
                waitingApprovalTitle: sub.waitingApprovalTitle
            )
        }

        let dynamicWorkflow = kmp.dynamicWorkflow.map { wf in
            AntigravityData.DynamicWorkflowPayload(
                workflowId: wf.workflowId,
                description: wf.description_,
                pythonScript: wf.pythonScript,
                currentPhase: wf.currentPhase,
                completedAgents: Int(wf.completedAgents),
                totalAgents: Int(wf.totalAgents),
                phases: wf.phases.map { p in
                    AntigravityData.WorkflowPhaseItem(id: p.id, name: p.name, isCompleted: p.isCompleted)
                }
            )
        }

        let swarmBoard = kmp.swarmBoard.map { sw in
            AntigravityData.SwarmBoardPayload(
                swarmId: sw.swarmId,
                title: sw.title,
                status: stepStatus,
                members: sw.members.map { m in
                    AntigravityData.SwarmMemberItem(
                        name: m.name,
                        role: m.role,
                        status: AntigravityData.CortexStepStatus(rawValue: Int(m.status.rawValue)) ?? .inProgress
                    )
                },
                posts: sw.posts.map { p in
                    AntigravityData.SwarmBoardPost(id: p.id, authorName: p.author, bodyMarkdown: p.body)
                }
            )
        }

        let mcpToolCall = kmp.mcpToolCall.map { mcp in
            AntigravityData.McpToolCallPayload(
                serverName: mcp.serverName,
                toolName: mcp.toolName,
                pluginName: mcp.pluginName,
                argumentsPreview: mcp.argumentsPreview,
                resultPreview: mcp.resultPreview,
                isError: mcp.isError
            )
        }

        return AntigravityData.CascadeStep(
            cascadeId: kmp.cascadeId,
            stepIndex: Int(kmp.stepIndex),
            type: stepType,
            status: stepStatus,
            createdAt: createdDate,
            userInput: kmp.userInput,
            attachedMentions: kmp.attachedMentions,
            isQueuedInOutbox: kmp.isQueuedInOutbox,
            plannerResponse: planner,
            taskBoundary: taskBoundary,
            runCommand: runCommand,
            codeAction: codeAction,
            viewFile: viewFile,
            search: search,
            requestedInteraction: requestedInteraction,
            recordedExecutionMode: recordedMode,
            recordedModelId: kmp.recordedModelId,
            subagent: subagent,
            dynamicWorkflow: dynamicWorkflow,
            swarmBoard: swarmBoard,
            mcpToolCall: mcpToolCall
        )
    }

    static func toSwiftRequestedInteraction(
        _ kmp: AntigravityShared.RequestedInteraction
    ) -> AntigravityData.RequestedInteraction {
        let kind = AntigravityData.RequestedInteraction.MemberKind(rawValue: kmp.kind.wireKey) ?? .approvalInteraction
        return AntigravityData.RequestedInteraction(
            kind: kind,
            permission: kmp.permission.map { p in
                AntigravityData.PermissionInteractionSpec(
                    action: p.action,
                    target: p.target,
                    suggestedPersistPattern: p.suggestedPersistPattern,
                    persistSuggestionType: AntigravityData.PersistSuggestionType(rawValue: Int(p.persistSuggestionType.rawValue)) ?? .suggested,
                    reason: p.reason,
                    pluginName: p.pluginName,
                    toolIconName: p.toolIconName
                )
            },
            filePermission: kmp.filePermission.map { fp in
                AntigravityData.FilePermissionInteractionSpec(
                    absolutePathUri: fp.absolutePathUri,
                    isDirectory: fp.isDirectory,
                    blockReason: fp.blockReason
                )
            },
            runCommand: kmp.runCommand.map { rc in
                AntigravityData.RunCommandInteractionSpec(
                    proposedCommandLine: rc.proposedCommandLine,
                    cwd: rc.cwd,
                    isDaemon: rc.isDaemon
                )
            },
            askQuestion: kmp.askQuestion.map { qa in
                AntigravityData.AskQuestionInteractionSpec(
                    question: qa.question,
                    options: qa.options,
                    isMultiSelect: qa.isMultiSelect
                )
            },
            executeUrl: kmp.executeUrl.map { eu in
                AntigravityData.ExecuteUrlInteractionSpec(url: eu.url, domain: eu.domain, isRedirect: eu.isRedirect)
            },
            downloadUrl: kmp.downloadUrl.map { du in
                AntigravityData.DownloadUrlInteractionSpec(
                    url: du.url,
                    origin: du.origin,
                    fileName: du.fileName,
                    mimeType: du.mimeType,
                    destinationFolder: du.destinationFolder
                )
            },
            browserUpload: kmp.browserUpload.map { bu in
                AntigravityData.BrowserUploadInteractionSpec(origin: bu.origin, fileNames: bu.fileNames)
            },
            workflowScript: kmp.workflowScript.map { ws in
                AntigravityData.WorkflowScriptInteractionSpec(
                    title: ws.title,
                    pythonScript: ws.pythonScript,
                    phaseNames: ws.phaseNames
                )
            },
            mcpServerName: kmp.mcpServerName,
            mcpToolName: kmp.mcpToolName,
            pluginName: kmp.pluginName,
            rawMemberKey: kmp.rawMemberKey,
            rawSummary: kmp.rawSummary
        )
    }

    static func toSwiftInteractionPayload(
        _ kmp: AntigravityShared.CascadeUserInteractionPayload
    ) -> AntigravityData.CascadeUserInteractionPayload {
        let kind = AntigravityData.RequestedInteraction.MemberKind(rawValue: kmp.kind.wireKey) ?? .approvalInteraction
        return AntigravityData.CascadeUserInteractionPayload(
            cascadeId: kmp.cascadeId,
            stepIndex: Int(kmp.stepIndex),
            kind: kind,
            workspaceUri: kmp.workspaceUri,
            runCommand: kmp.runCommand.map { rc in
                AntigravityData.CascadeUserInteractionPayload.RunCommandAnswer(
                    confirm: rc.confirm,
                    proposedCommandLine: rc.proposedCommandLine,
                    submittedCommandLine: rc.submittedCommandLine,
                    faceIdVerified: rc.biometricVerified
                )
            },
            permission: kmp.permission.map { p in
                AntigravityData.CascadeUserInteractionPayload.PermissionAnswer(
                    allow: p.allow,
                    grantPatterns: p.grantPatterns,
                    scope: p.scope
                )
            },
            filePermission: kmp.filePermission.map { fp in
                AntigravityData.CascadeUserInteractionPayload.FilePermissionAnswer(
                    allow: fp.allow,
                    scope: fp.scope,
                    absolutePathUri: fp.absolutePathUri
                )
            },
            askQuestion: kmp.askQuestion.map { qa in
                AntigravityData.CascadeUserInteractionPayload.AskQuestionAnswer(
                    selectedOptions: qa.selectedOptions,
                    customResponse: qa.customResponse
                )
            },
            genericConfirm: kmp.genericConfirm?.boolValue,
            approvalScope: kmp.approvalScope,
            rawMemberKey: kmp.rawMemberKey
        )
    }

    // MARK: - Swift -> KMP Converters

    static func toKmpHostScope(_ scope: AntigravityData.AgentsHostFilterScope) -> AntigravityShared.AgentsHostFilterScope {
        switch scope {
        case .allHosts:
            return KmpBridgeHelpers.shared.scopeAllHosts()
        case .antigravityCloud:
            return KmpBridgeHelpers.shared.scopeAntigravityCloud()
        case .localHost(let id, let name):
            return KmpBridgeHelpers.shared.scopeLocalHost(id: id, name: name)
        }
    }

    static func toKmpAttachment(_ chip: AntigravityData.ComposerAttachmentChip) -> AntigravityShared.ComposerAttachmentChip {
        let kindName: String
        switch chip.kind {
        case .fileMention, .genericFile, .archiveZip: kindName = "FILE_MENTION"
        case .folder: kindName = "FOLDER"
        case .conversationMention: kindName = "CONVERSATION_MENTION"
        case .imageScreenshot: kindName = "IMAGE_SCREENSHOT"
        case .terminalLog: kindName = "TERMINAL_LOG"
        case .skill, .pluginMention: kindName = "SKILL"
        case .action: kindName = "WORKFLOW"
        case .audioRecording: kindName = "AUDIO_CLIP"
        case .pdfDocument: kindName = "PDF_DOCUMENT"
        case .videoClip: kindName = "VIDEO_CLIP"
        case .codeQuote: kindName = "DIFF_QUOTE"
        }
        return KmpBridgeHelpers.shared.makeAttachmentChip(
            id: chip.id,
            kindName: kindName,
            label: chip.label,
            targetUri: chip.targetUri,
            mimeType: chip.mimeType,
            inlinePayload: chip.inlineBase64Data
        )
    }

    static func toKmpDecision(_ decision: AntigravityData.InteractionDecision) -> AntigravityShared.InteractionDecision {
        switch decision {
        case .allowOnce:
            return KmpBridgeHelpers.shared.decisionAllowOnce()
        case .allowWithFaceID:
            return KmpBridgeHelpers.shared.decisionAllowWithBiometric()
        case .alwaysAllowInTurn:
            return KmpBridgeHelpers.shared.decisionAlwaysAllowInTurn()
        case .allowInConversation:
            return KmpBridgeHelpers.shared.decisionAllowInConversation()
        case .alwaysAllow:
            return KmpBridgeHelpers.shared.decisionAlwaysAllow()
        case .allowWithModifiedCommand(let cmd):
            return KmpBridgeHelpers.shared.decisionAllowWithModifiedCommand(commandLine: cmd)
        case .answerQuestion(let options, let writeIn):
            return KmpBridgeHelpers.shared.decisionAnswerQuestion(
                selectedOptions: options,
                customWriteIn: writeIn
            )
        case .reject:
            return KmpBridgeHelpers.shared.decisionReject()
        }
    }

    static func toKmpStepForInteraction(_ step: AntigravityData.CascadeStep) -> AntigravityShared.CascadeStep {
        let req = step.requestedInteraction
        return KmpBridgeHelpers.shared.makeCascadeStepForInteraction(
            cascadeId: step.cascadeId,
            stepIndex: Int32(step.stepIndex),
            stepTypeRaw: Int32(step.type.rawValue),
            stepStatusRaw: Int32(step.status.rawValue),
            runCommandId: step.runCommand?.commandId,
            runCommandLine: step.runCommand?.commandLine,
            runCommandProposed: req?.runCommand?.proposedCommandLine ?? step.runCommand?.proposedCommandLine,
            runCommandCwd: req?.runCommand?.cwd ?? step.runCommand?.cwd,
            interactionKindWireKey: req?.kind.rawValue,
            interactionRawMemberKey: req?.rawMemberKey,
            permAction: req?.permission?.action,
            permTarget: req?.permission?.target,
            permSuggestedPattern: req?.permission?.suggestedPersistPattern,
            permPersistTypeRaw: Int32(req?.permission?.persistSuggestionType.rawValue ?? 1),
            permReason: req?.permission?.reason,
            permPluginName: req?.permission?.pluginName ?? req?.pluginName,
            filePermUri: req?.filePermission?.absolutePathUri,
            filePermIsDirectory: req?.filePermission?.isDirectory ?? false,
            filePermBlockReason: req?.filePermission?.blockReason,
            askQuestionText: req?.askQuestion?.question,
            askQuestionOptions: req?.askQuestion?.options ?? [],
            askQuestionMultiSelect: req?.askQuestion?.isMultiSelect ?? false,
            executeUrl: req?.executeUrl?.url,
            executeUrlDomain: req?.executeUrl?.domain,
            executeUrlIsRedirect: req?.executeUrl?.isRedirect ?? false,
            downloadUrl: req?.downloadUrl?.url,
            downloadOrigin: req?.downloadUrl?.origin,
            downloadFileName: req?.downloadUrl?.fileName,
            downloadMimeType: req?.downloadUrl?.mimeType,
            downloadDestFolder: req?.downloadUrl?.destinationFolder,
            browserUploadOrigin: req?.browserUpload?.origin,
            browserUploadFiles: req?.browserUpload?.fileNames ?? [],
            workflowTitle: req?.workflowScript?.title,
            workflowScript: req?.workflowScript?.pythonScript,
            workflowPhases: req?.workflowScript?.phaseNames ?? [],
            mcpServerName: req?.mcpServerName,
            mcpToolName: req?.mcpToolName
        )
    }
}
#endif
