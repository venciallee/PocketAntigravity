import Foundation

/// Composer actions, message queueing, step expansion, biometric approvals, structured questions, /btw, overview, and voice mode.
extension AntigravitySessionStore {
    // MARK: - Add Context & Composer Actions (`UE07`, `UE08`, `UE09`)

    public func toggleContextCandidate(_ candidateId: String) {
        guard let idx = contextCandidates.firstIndex(where: { $0.id == candidateId }) else { return }
        contextCandidates[idx].isSelected.toggle()
    }

    public func applySelectedContextToComposer() {
        for candidate in contextCandidates where candidate.isSelected {
            if candidate.isActionTrigger {
                if !composerDraftText.hasPrefix(candidate.chipLabel) {
                    composerDraftText = "\(candidate.chipLabel) \(composerDraftText)".trimmingCharacters(in: .whitespaces)
                }
            } else if !composerAttachments.contains(where: { $0.label == candidate.chipLabel }) {
                composerAttachments.append(
                    ComposerAttachmentChip(
                        id: "chip-\(candidate.id)",
                        kind: candidate.attachmentKind,
                        label: candidate.chipLabel,
                        targetUri: "antigravity://context/\(candidate.id)"
                    )
                )
            }
        }
        presentedSheet = nil
    }

    public func applySlashCommand(_ item: SlashCommandItem) {
        composerDraftText = "\(item.command) "
        isSlashPopupDismissedManually = true
    }

    public func attachFileMention(_ filePath: String) {
        let fileName = (filePath as NSString).lastPathComponent
        let basePrefix: String = {
            if !isVerificationMode && selectedWorkspaceUri.hasPrefix("file://") {
                return selectedWorkspaceUri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            return "file:///Users/wl/code/ledger-svc"
        }()
        let chip = ComposerAttachmentChip(
            kind: .fileMention,
            label: "@\(fileName)",
            targetUri: "\(basePrefix)/\(filePath)"
        )
        if !composerAttachments.contains(where: { $0.targetUri == chip.targetUri || $0.label == chip.label }) {
            composerAttachments.append(chip)
        }
        if let lastRange = composerDraftText.range(of: "@[^\\s]*$", options: .regularExpression) {
            composerDraftText.removeSubrange(lastRange)
        }
    }

    public func removeAttachment(_ chipId: String) {
        composerAttachments.removeAll { $0.id == chipId }
    }

    public func sendCurrentDraft(bypassStreamingQueue: Bool = false) {
        let trimmed = composerDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let workflowPrefix = composerWorkflowCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty || !composerAttachments.isEmpty || !workflowPrefix.isEmpty else { return }

        let combinedText: String = {
            if workflowPrefix.isEmpty {
                return trimmed
            }
            if trimmed.isEmpty {
                return workflowPrefix
            }
            if trimmed.lowercased().hasPrefix(workflowPrefix.lowercased()) {
                return trimmed
            }
            return "\(workflowPrefix) \(trimmed)"
        }()

        if workflowPrefix.isEmpty {
            let lowerTrim = trimmed.lowercased()
            if lowerTrim == "/model" {
                composerDraftText = ""
                presentedSheet = .modelAndMode
                return
            }
            if lowerTrim == "/mode" {
                composerDraftText = ""
                if !selectedModelConfig.isOrchestrator {
                    selectedModelConfig.mode = (selectedModelConfig.mode == .planning) ? .fast : .planning
                }
                return
            }
            if lowerTrim == "/voice" {
                composerDraftText = ""
                startVoiceMode()
                return
            }
            if lowerTrim == "/clear" {
                composerDraftText = ""
                let targetProj = selectedProjectId.isEmpty ? (projects.first?.id ?? AntigravityCloudDetector.noProjectDisplayName) : selectedProjectId
                _ = createConversationInProject(targetProj)
                return
            }
        }

        if !bypassStreamingQueue && !activeSteps.isEmpty && pendingDraftConversation == nil && isCascadeStreaming && (hasPairedBackend || isLiveBackendConnected) && !isVerificationMode {
            enqueueFollowUpMessage(combinedText, attachments: composerAttachments)
            composerWorkflowCommand = nil
            composerDraftText = ""
            composerAttachments.removeAll()
            return
        }

        let messageBody = combinedText.isEmpty
            ? "Inspect attached context: \(composerAttachments.map(\.label).joined(separator: ", "))"
            : combinedText
        let mentionLabels = composerAttachments.map(\.label)

        // Materialize an unsent pending draft conversation (e.g. Automations "Create with Prompt") only on Send.
        var materializedDirectly = false
        if let draft = pendingDraftConversation, activeCascadeId.isEmpty {
            materializedDirectly = true
            pendingDraftConversation = nil
            let optimisticId = "cas-\(UUID().uuidString.prefix(8).lowercased())"
            let project = projects.first(where: { $0.id == draft.projectSlug || $0.name == draft.projectSlug })
            let isUnassigned = (project?.isNoProject == true) || AntigravityCloudDetector.isNoProjectSlug(draft.projectSlug)
            let isCloudProj = draft.isCloud || (project?.runtime == .cloud) || draft.projectSlug.lowercased().hasPrefix("cloud:")
            let effectiveSlug: String = {
                if let project { return project.id }
                if isUnassigned {
                    let hasLocalNoProj = projects.contains(where: { $0.isNoProject && $0.runtime != .cloud })
                    if isCloudProj && hasLocalNoProj {
                        return "cloud:\(AntigravityCloudDetector.noProjectDisplayName)"
                    }
                    return AntigravityCloudDetector.noProjectDisplayName
                }
                return draft.projectSlug
            }()
            let draftWorkspaceUri: String = {
                if isUnassigned { return "" }
                if let existingUri = project?.workspaceUri, !existingUri.isEmpty {
                    return existingUri
                }
                if hasPairedBackend || isLiveBackendConnected {
                    return ""
                }
                return isCloudProj ? "cloud://\(effectiveSlug)" : "file:///Users/wl/code/\(effectiveSlug)"
            }()
            let branch = isUnassigned ? "" : (project?.activeBranch ?? "main")
            let effectiveTitle: String = {
                let isDefaultGuided = (trimmed == draft.defaultGuidedPrompt)
                if !trimmed.isEmpty && !isDefaultGuided && draft.title == "New Automation" {
                    return String(trimmed.prefix(48))
                }
                return draft.title
            }()
            let newSummary = CascadeSummary(
                cascadeId: optimisticId,
                title: effectiveTitle,
                projectSlug: effectiveSlug,
                workspaceUri: draftWorkspaceUri,
                branchName: branch,
                status: .inProgress,
                stepCount: 1,
                currentStepIndex: 1,
                totalSteps: 1,
                updatedAt: Date(),
                relativeTimeLabel: "now",
                statusSubtitle: "Running · Step 1 of 1",
                isPinned: displayOptions.autoPinOnMessage,
                isArchived: false,
                isUnread: false,
                modelLabel: selectedModelConfig.displayName,
                lastMessagePreview: messageBody,
                isCloud: isCloudProj,
                cloudProjectId: isUnassigned ? nil : project?.cloudProjectId,
                originInstanceUuid: project?.originInstanceUuid,
                originHostName: isCloudProj ? "Antigravity" : activeHost.hostname
            )
            summaries.insert(newSummary, at: 0)
            if hasPairedBackend || isLiveBackendConnected {
                let existingCloudProjects = projects.filter { $0.runtime == .cloud && $0.cloudProjectId != nil }
                var nextSummaries = summaries
                projects = Self.reconcileLiveProjects(
                    workspaces: workspaces,
                    summaries: &nextSummaries,
                    existingProjects: projects,
                    hostName: activeHost.hostname,
                    cloudProjects: existingCloudProjects
                )
                summaries = nextSummaries
            }
            stepsByCascadeId[optimisticId] = []
            activeCascadeId = optimisticId
            selectedProjectId = summaries.first(where: { $0.cascadeId == optimisticId })?.projectSlug ?? effectiveSlug
            selectedWorkspaceUri = draftWorkspaceUri
            activeRoute = .cascadeChat(optimisticId)
        }
        let skipUpgradeWait = materializedDirectly

        var currentSteps = stepsByCascadeId[activeCascadeId] ?? []
        let nextIndex = (currentSteps.map(\.stepIndex).max() ?? -1) + 1
        stepLoadErrorText = nil

        let userStep = CascadeStep(
            cascadeId: activeCascadeId,
            stepIndex: nextIndex,
            type: .userInput,
            status: .done,
            createdAt: Date(),
            userInput: messageBody,
            attachedMentions: mentionLabels,
            isQueuedInOutbox: false,
            recordedExecutionMode: selectedModelConfig.mode,
            recordedModelId: selectedModelConfig.modelId
        )
        currentSteps.append(userStep)
        if !activeCascadeId.isEmpty {
            syncedConfigCascadeIds.insert(activeCascadeId)
        }

        // Only synthesize ESDD offline mock response when NO backend is paired (`!hasPairedBackend && !isLiveBackendConnected`)
        if !hasPairedBackend && !isLiveBackendConnected {
            let assistantStep = CascadeStep(
                cascadeId: activeCascadeId,
                stepIndex: nextIndex + 1,
                type: .plannerResponse,
                status: .inProgress,
                createdAt: Date(),
                plannerResponse: PlannerResponsePayload(
                    response: "Running in `\(selectedModelConfig.mode.rawValue)` mode with `\(selectedModelConfig.displayName)` (`\(selectedModelConfig.agentPersona)` agent)...",
                    thinking: "Evaluating prompt with \(mentionLabels.count) context chips on branch \(activeSummary?.branchName ?? "main").",
                    thinkingDurationSeconds: 2.0,
                    referencedFiles: composerAttachments.map(\.targetUri)
                )
            )
            currentSteps.append(assistantStep)
        }
        stepsByCascadeId[activeCascadeId] = currentSteps
        locallyCreatedEmptyCascadeIds.remove(activeCascadeId)

        let currentSummary = summaries.first(where: { $0.cascadeId == activeCascadeId })
        let currentProj = projects.first(where: { $0.id == (currentSummary?.projectSlug ?? selectedProjectId) })
        let summaryIsCloud = currentSummary?.isCloud ?? (currentProj?.runtime == .cloud)
        let summaryCloudProjId = currentSummary?.cloudProjectId ?? currentProj?.cloudProjectId
        let summaryOriginUuid = currentSummary?.originInstanceUuid ?? currentProj?.originInstanceUuid

        if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
            summaries[sumIdx].stepCount = currentSteps.count
            summaries[sumIdx].status = .inProgress
            summaries[sumIdx].lastMessagePreview = messageBody
            summaries[sumIdx].relativeTimeLabel = "now"
            summaries[sumIdx].updatedAt = Date()
            if summaries[sumIdx].needsTitleHydration {
                if let clean = CascadeSummaryTitleResolver.cleanSingleLine(messageBody) {
                    summaries[sumIdx].title = CascadeSummaryTitleResolver.truncateTitle(clean, maxLength: 64)
                    summaries[sumIdx].hasResolvedTitle = true
                    hydratingCascadeIds.remove(activeCascadeId)
                    settledEmptyTitleCascadeIds.remove(activeCascadeId)
                }
            }
            if displayOptions.autoPinOnMessage {
                summaries[sumIdx].isPinned = true
            }
        }

        let attachmentsSnapshot = composerAttachments
        composerWorkflowCommand = nil
        composerDraftText = ""
        composerAttachments.removeAll()
        isSlashPopupDismissedManually = false
        isAutoScrollPinnedToBottom = true

        let cid = activeCascadeId
        let cfg = selectedModelConfig
        let runtimeDefaultPreset = summaryIsCloud ? remotePermissionPreset : localPermissionPreset
        let effectivePreset: AgentPermissionPreset = {
            if let overridePreset = conversationPermissionPresets[cid], overridePreset != .inheritGlobal {
                return overridePreset
            }
            return runtimeDefaultPreset
        }()
        let storeRef = projectionStore
        let clientRef = rpcClient
        let engineRef = kmpEngine
        let shouldSendLive = (hasPairedBackend || isLiveBackendConnected)
        let isUnassignedSession = (currentProj?.isNoProject == true)
            || (currentSummary.map {
                AntigravityCloudDetector.isNoProjectSlug($0.projectSlug) && ($0.cloudProjectId ?? "").isEmpty
            } ?? false)
        let workspaceUri: String = {
            if isUnassignedSession {
                if let scratch = currentSummary?.workspaceUri, AntigravityCloudDetector.isPlaygroundScratchURI(scratch) {
                    return scratch
                }
                return ""
            }
            if let sumUri = currentSummary?.workspaceUri, !sumUri.isEmpty {
                return sumUri
            }
            if let projUri = currentProj?.workspaceUri, !projUri.isEmpty {
                return projUri
            }
            if !selectedWorkspaceUri.isEmpty {
                return selectedWorkspaceUri
            }
            return isVerificationMode ? "file:///Users/wl/code/ledger-svc" : ""
        }()

        let outboxEntry = OutboxEntry(cascadeId: cid, kind: .userMessage, messageText: messageBody)

        Task { [weak self] in
            await storeRef.enqueueOutbox(outboxEntry)
            await storeRef.saveProjectedSteps(currentSteps, for: cid)

            guard shouldSendLive, (engineRef != nil || clientRef != nil) else {
                await storeRef.removeOutboxEntry(id: outboxEntry.id)
                return
            }

            if let self, !self.isDeviceNetworkReachable {
                self.markStepQueuedInOutbox(cascadeId: cid, stepIndex: nextIndex)
                self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                if let updated = self.stepsByCascadeId[cid] {
                    await storeRef.saveProjectedSteps(updated, for: cid)
                }
                if let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == cid }) {
                    self.summaries[sumIdx].status = .pending
                    self.summaries[sumIdx].statusSubtitle = "Queued · Waiting for network"
                }
                return
            }

            var targetCascadeId = cid
            if !skipUpgradeWait && targetCascadeId.hasPrefix("cas-") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let upgraded = self?.activeCascadeId, !upgraded.isEmpty, !upgraded.hasPrefix("cas-") {
                    targetCascadeId = upgraded
                }
            }

            do {
                if let engineRef {
                    let isOptimistic = targetCascadeId.isEmpty
                        || (targetCascadeId.hasPrefix("cas-") && !Self.esddFixtureCascadeIds.contains(targetCascadeId))
                    let outcome = try await engineRef.sendMessage(
                        cascadeId: targetCascadeId,
                        message: messageBody,
                        workspaceUri: workspaceUri,
                        attachments: attachmentsSnapshot,
                        modelId: cfg.modelId,
                        effort: cfg.effort,
                        mode: cfg.mode,
                        agentPersona: cfg.agentPersona,
                        isCloud: summaryIsCloud,
                        cloudProjectId: summaryCloudProjId,
                        permissionPreset: effectivePreset,
                        instanceUuidOverride: summaryOriginUuid,
                        isOptimisticDraft: isOptimistic
                    )
                    let resolvedId = outcome.resolvedCascadeId
                    if let self, !resolvedId.isEmpty && resolvedId != targetCascadeId && isOptimistic {
                        self.locallyCreatedEmptyCascadeIds.remove(targetCascadeId)
                        self.locallyCreatedEmptyCascadeIds.remove(resolvedId)
                        let existing = self.stepsByCascadeId.removeValue(forKey: targetCascadeId) ?? currentSteps
                        self.stepsByCascadeId[resolvedId] = existing.map { step in
                            var copy = step
                            copy.cascadeId = resolvedId
                            return copy
                        }
                        self.syncedConfigCascadeIds.insert(resolvedId)
                        if let idx = self.summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                            self.summaries[idx].cascadeId = resolvedId
                        }
                        if self.activeCascadeId == targetCascadeId || self.activeCascadeId.isEmpty {
                            self.activeCascadeId = resolvedId
                            if case .cascadeChat = self.activeRoute {
                                self.activeRoute = .cascadeChat(resolvedId)
                            }
                        }
                        targetCascadeId = resolvedId
                    }
                    if let self, !targetCascadeId.isEmpty {
                        self.optimisticActiveUntilByCascadeId[targetCascadeId] = Date().addingTimeInterval(45)
                        self.syncStepsForCascade(targetCascadeId, pollUntilIdle: true)
                    }
                    if !outcome.dispatchedLive {
                        if outcome.queuedInOutbox {
                            throw AntigravityRPCError.httpError(statusCode: 503, body: outcome.errorMessage ?? "Queued in KMP Durable Outbox")
                        }
                        throw AntigravityRPCError.httpError(statusCode: 500, body: outcome.errorMessage ?? "KMP sendMessage failed")
                    }
                } else if let clientRef {
                    if targetCascadeId.isEmpty || targetCascadeId.hasPrefix("cas-") {
                        let createdId = try await clientRef.startCascade(
                            workspaceUri: workspaceUri,
                            initialPrompt: "",
                            modelId: cfg.modelId,
                            cloudProjectId: summaryCloudProjId,
                            isCloud: summaryIsCloud,
                            instanceUuidOverride: summaryOriginUuid
                        )
                        if let self, !createdId.isEmpty {
                            self.locallyCreatedEmptyCascadeIds.remove(targetCascadeId)
                            self.locallyCreatedEmptyCascadeIds.remove(createdId)
                            let existing = self.stepsByCascadeId.removeValue(forKey: targetCascadeId) ?? currentSteps
                            self.stepsByCascadeId[createdId] = existing.map { step in
                                var copy = step
                                copy.cascadeId = createdId
                                return copy
                            }
                            self.syncedConfigCascadeIds.insert(createdId)
                            if let idx = self.summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                                self.summaries[idx].cascadeId = createdId
                            }
                            if self.activeCascadeId == targetCascadeId || self.activeCascadeId.isEmpty {
                                self.activeCascadeId = createdId
                                if case .cascadeChat = self.activeRoute {
                                    self.activeRoute = .cascadeChat(createdId)
                                }
                            }
                            targetCascadeId = createdId
                        }
                    }

                    if let self, !targetCascadeId.isEmpty {
                        self.optimisticActiveUntilByCascadeId[targetCascadeId] = Date().addingTimeInterval(45)
                        self.syncStepsForCascade(targetCascadeId, pollUntilIdle: true)
                    }

                    try await clientRef.sendUserCascadeMessage(
                        cascadeId: targetCascadeId,
                        message: messageBody,
                        attachments: attachmentsSnapshot,
                        modelId: cfg.modelId,
                        effort: cfg.effort,
                        mode: cfg.mode,
                        agentPersona: cfg.agentPersona,
                        isModelAlias: cfg.isModelAlias,
                        isCloud: summaryIsCloud,
                        permissionPreset: effectivePreset,
                        instanceUuidOverride: summaryOriginUuid
                    )
                }
                await storeRef.removeOutboxEntry(id: outboxEntry.id)

                if let self {
                    self.lastBackendActivityAt = Date()
                    self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                    if self.hasPairedBackend && (!self.isLiveBackendConnected || !self.activeHost.isOnline) {
                        self.markBackendReconnected()
                    }
                    if !targetCascadeId.isEmpty {
                        self.syncStepsForCascade(targetCascadeId, pollUntilIdle: true)
                    }
                }
            } catch {
                if let self {
                    let stepsAdvanced = (self.stepsByCascadeId[targetCascadeId]?.count ?? 0) > currentSteps.count
                    if stepsAdvanced && !targetCascadeId.isEmpty {
                        await storeRef.removeOutboxEntry(id: outboxEntry.id)
                        self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                        // Turn already started streaming on backend despite unary HTTP timeout; keep polling steps
                        self.syncStepsForCascade(targetCascadeId, pollUntilIdle: true)
                    } else if Self.isBackendOfflineError(error) {
                        // Keep entry persisted in Durable Outbox so it automatically replays once host reconnects
                        self.optimisticActiveUntilByCascadeId.removeValue(forKey: targetCascadeId)
                        self.markStepQueuedInOutbox(cascadeId: targetCascadeId, stepIndex: nextIndex)
                        if let updated = self.stepsByCascadeId[targetCascadeId] {
                            await storeRef.saveProjectedSteps(updated, for: targetCascadeId)
                        }
                        self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                        if let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                            self.summaries[sumIdx].status = .pending
                            self.summaries[sumIdx].statusSubtitle = "Queued · Will send when back online"
                        }
                        if self.activeHost.channel != .cloudRelay {
                            self.markBackendOffline(error: error)
                        }
                    } else {
                        await storeRef.removeOutboxEntry(id: outboxEntry.id)
                        self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                        self.optimisticActiveUntilByCascadeId.removeValue(forKey: targetCascadeId)
                        self.stepLoadErrorText = "Failed to send message: \(error.localizedDescription)"
                        if let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                            self.summaries[sumIdx].status = .done
                            self.summaries[sumIdx].statusSubtitle = "Send failed · Tap to retry"
                        }
                    }
                }
            }
        }
    }

    internal func markStepQueuedInOutbox(cascadeId: String, stepIndex: Int) {
        guard var steps = stepsByCascadeId[cascadeId],
              let idx = steps.lastIndex(where: { $0.stepIndex == stepIndex && $0.type == .userInput }) else {
            return
        }
        steps[idx].isQueuedInOutbox = true
        stepsByCascadeId[cascadeId] = steps
    }

    /// Replays persisted offline Durable Outbox user messages in FIFO order once the paired host reconnects.
    public func replayPendingOutbox() async {
        guard !isReplayingOutbox,
              !isVerificationMode,
              !isNetworkingSuspended,
              isDeviceNetworkReachable,
              isLiveBackendConnected,
              activeHost.isOnline,
              (kmpEngine != nil || rpcClient != nil) else {
            return
        }

        isReplayingOutbox = true
        defer { isReplayingOutbox = false }

        let cfg = selectedModelConfig
        if let engine = kmpEngine {
            _ = await engine.replayPendingOutbox(
                modelId: cfg.modelId,
                effort: cfg.effort,
                mode: cfg.mode
            )
        }

        let pending = await projectionStore.loadPendingOutbox()
        pendingOutboxCount = pending.count
        guard !pending.isEmpty else { return }

        for entry in pending {
            guard !isNetworkingSuspended, isDeviceNetworkReachable, isLiveBackendConnected else { break }
            guard entry.kind == .userMessage,
                  let messageBody = entry.messageText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !messageBody.isEmpty else {
                await projectionStore.removeOutboxEntry(id: entry.id)
                continue
            }

            var targetCascadeId = entry.cascadeId
            let currentSummary = summaries.first(where: { $0.cascadeId == targetCascadeId })
            let currentProj = projects.first(where: { $0.id == (currentSummary?.projectSlug ?? selectedProjectId) })
            let summaryIsCloud = currentSummary?.isCloud ?? (currentProj?.runtime == .cloud)
            let summaryCloudProjId = currentSummary?.cloudProjectId ?? currentProj?.cloudProjectId
            let summaryOriginUuid = currentSummary?.originInstanceUuid ?? currentProj?.originInstanceUuid
            let workspaceUri = currentSummary?.workspaceUri ?? currentProj?.workspaceUri ?? selectedWorkspaceUri

            do {
                if let engine = kmpEngine {
                    let isOptimistic = targetCascadeId.isEmpty
                        || (targetCascadeId.hasPrefix("cas-") && !Self.esddFixtureCascadeIds.contains(targetCascadeId))
                    let outcome = try await engine.sendMessage(
                        cascadeId: targetCascadeId,
                        message: messageBody,
                        workspaceUri: workspaceUri,
                        attachments: [],
                        modelId: cfg.modelId,
                        effort: cfg.effort,
                        mode: cfg.mode,
                        agentPersona: cfg.agentPersona,
                        isCloud: summaryIsCloud,
                        cloudProjectId: summaryCloudProjId,
                        permissionPreset: summaryIsCloud ? remotePermissionPreset : localPermissionPreset,
                        instanceUuidOverride: summaryOriginUuid,
                        isOptimisticDraft: isOptimistic
                    )
                    let resolvedId = outcome.resolvedCascadeId
                    if !resolvedId.isEmpty && resolvedId != targetCascadeId && isOptimistic {
                        locallyCreatedEmptyCascadeIds.remove(targetCascadeId)
                        locallyCreatedEmptyCascadeIds.remove(resolvedId)
                        if let existing = stepsByCascadeId.removeValue(forKey: targetCascadeId) {
                            stepsByCascadeId[resolvedId] = existing.map { step in
                                var copy = step
                                copy.cascadeId = resolvedId
                                return copy
                            }
                        }
                        if let idx = summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                            summaries[idx].cascadeId = resolvedId
                        }
                        if activeCascadeId == targetCascadeId || activeCascadeId.isEmpty {
                            activeCascadeId = resolvedId
                            if case .cascadeChat = activeRoute {
                                activeRoute = .cascadeChat(resolvedId)
                            }
                        }
                        targetCascadeId = resolvedId
                    }
                    if !outcome.dispatchedLive {
                        throw AntigravityRPCError.httpError(
                            statusCode: outcome.queuedInOutbox ? 503 : 500,
                            body: outcome.errorMessage ?? "KMP outbox replay failed"
                        )
                    }
                } else if let clientRef = rpcClient {
                    if targetCascadeId.isEmpty || targetCascadeId.hasPrefix("cas-") {
                        let createdId = try await clientRef.startCascade(
                            workspaceUri: workspaceUri,
                            initialPrompt: "",
                            modelId: cfg.modelId,
                            cloudProjectId: summaryCloudProjId,
                            isCloud: summaryIsCloud,
                            instanceUuidOverride: summaryOriginUuid
                        )
                        if !createdId.isEmpty {
                            locallyCreatedEmptyCascadeIds.remove(targetCascadeId)
                            locallyCreatedEmptyCascadeIds.remove(createdId)
                            if let existing = stepsByCascadeId.removeValue(forKey: targetCascadeId) {
                                stepsByCascadeId[createdId] = existing.map { step in
                                    var copy = step
                                    copy.cascadeId = createdId
                                    return copy
                                }
                            }
                            if let idx = summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                                summaries[idx].cascadeId = createdId
                            }
                            if activeCascadeId == targetCascadeId || activeCascadeId.isEmpty {
                                activeCascadeId = createdId
                                if case .cascadeChat = activeRoute {
                                    activeRoute = .cascadeChat(createdId)
                                }
                            }
                            targetCascadeId = createdId
                        }
                    }

                    try await clientRef.sendUserCascadeMessage(
                        cascadeId: targetCascadeId,
                        message: messageBody,
                        attachments: [],
                        modelId: cfg.modelId,
                        effort: cfg.effort,
                        mode: cfg.mode,
                        agentPersona: cfg.agentPersona,
                        isModelAlias: cfg.isModelAlias,
                        isCloud: summaryIsCloud,
                        permissionPreset: summaryIsCloud ? remotePermissionPreset : localPermissionPreset,
                        instanceUuidOverride: summaryOriginUuid
                    )
                }

                await projectionStore.removeOutboxEntry(id: entry.id)
                lastBackendActivityAt = Date()

                if var steps = stepsByCascadeId[targetCascadeId] {
                    for i in steps.indices where steps[i].isQueuedInOutbox && steps[i].userInput == messageBody {
                        steps[i].isQueuedInOutbox = false
                    }
                    stepsByCascadeId[targetCascadeId] = steps
                    await projectionStore.saveProjectedSteps(steps, for: targetCascadeId)
                }
                if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                    summaries[sumIdx].status = .inProgress
                    summaries[sumIdx].statusSubtitle = "Running"
                }
                if !targetCascadeId.isEmpty {
                    optimisticActiveUntilByCascadeId[targetCascadeId] = Date().addingTimeInterval(45)
                    syncStepsForCascade(targetCascadeId, pollUntilIdle: true)
                }
            } catch {
                if Self.isBackendOfflineError(error) {
                    // Host dropped again mid-replay: keep remaining entries persisted for next reconnect
                    break
                } else {
                    await projectionStore.removeOutboxEntry(id: entry.id)
                }
            }
        }

        pendingOutboxCount = await projectionStore.loadPendingOutbox().count
    }

    public func stopActiveCascadeStreaming() {
        optimisticActiveUntilByCascadeId.removeValue(forKey: activeCascadeId)
        manuallyCancelledCascadeIds.insert(activeCascadeId)
        guard var currentSteps = stepsByCascadeId[activeCascadeId] else { return }
        for i in currentSteps.indices where currentSteps[i].status == .inProgress || currentSteps[i].status == .pending || currentSteps[i].status == .waiting {
            currentSteps[i].status = .cancelled
        }
        stepsByCascadeId[activeCascadeId] = currentSteps
        let originUuid = summaries.first(where: { $0.cascadeId == activeCascadeId })?.originInstanceUuid
        if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
            summaries[sumIdx].status = .cancelled
            summaries[sumIdx].statusSubtitle = "Stopped"
        }
        let cid = activeCascadeId
        let clientRef = rpcClient
        let engineRef = kmpEngine
        let isLive = isLiveBackendActive
        Task { [weak self] in
            do {
                if let engineRef {
                    try await engineRef.cancelActiveTurn(cascadeId: cid, instanceUuidOverride: originUuid)
                } else if let clientRef {
                    try await clientRef.cancelCascadeInvocation(cascadeId: cid, instanceUuidOverride: originUuid)
                } else {
                    return
                }
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .backgroundTaskControl,
                    fallbackActionLabel: "Stopping agent"
                )
            }
        }
    }

    // MARK: - Step Expansion & Face ID Command Approval Actions (`UE07`, `UE13`)

    public func toggleThinkingExpanded(stepId: String) {
        if expandedThinkingStepIds.contains(stepId) {
            expandedThinkingStepIds.remove(stepId)
        } else {
            expandedThinkingStepIds.insert(stepId)
        }
    }

    public func toggleEvidenceGroupExpanded(groupId: String) {
        if expandedEvidenceGroupIds.contains(groupId) {
            expandedEvidenceGroupIds.remove(groupId)
        } else {
            expandedEvidenceGroupIds.insert(groupId)
        }
    }

    public func toggleTerminalOutputExpanded(stepId: String) {
        if expandedTerminalStepIds.contains(stepId) {
            expandedTerminalStepIds.remove(stepId)
        } else {
            expandedTerminalStepIds.insert(stepId)
        }
    }

    public func approveWaitingCommandWithFaceID(stepIndex: Int? = nil) {
        let targetIdx = stepIndex ?? pendingWaitingStep?.stepIndex
        guard let resolvedStepIndex = targetIdx else { return }
        resolveWaitingStep(stepIndex: resolvedStepIndex, decision: .allowWithFaceID)
    }

    public func denyWaitingCommand(stepIndex: Int? = nil) {
        let targetIdx = stepIndex ?? pendingWaitingStep?.stepIndex
        guard let resolvedStepIndex = targetIdx else { return }
        resolveWaitingStep(stepIndex: resolvedStepIndex, decision: .reject)
    }

    public func resolveWaitingStep(
        stepIndex: Int,
        decision: InteractionDecision
    ) {
        guard var steps = stepsByCascadeId[activeCascadeId],
              let idx = steps.firstIndex(where: { $0.stepIndex == stepIndex }) else {
            return
        }
        let targetStep = steps[idx]
        let payload = InteractionBuilder.buildPayload(
            step: targetStep,
            decision: decision,
            workspaceUri: selectedWorkspaceUri
        )
        if payload == nil,
           targetStep.effectiveRequestedInteraction?.isUnrecognizedWireMember == true,
           (hasPairedBackend || isLiveBackendConnected) {
            compatibilityNoticeText = "This approval type uses a newer Antigravity Desktop schema. Approve or deny it directly in Antigravity Desktop, then refresh."
            return
        }
        lastDispatchedInteraction = payload

        switch decision {
        case .reject:
            steps[idx].status = .cancelled
            if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
                summaries[sumIdx].status = .cancelled
                summaries[sumIdx].statusSubtitle = "Denied · Awaiting instructions"
                summaries[sumIdx].pendingInteractionTitle = nil
            }
        case .allowOnce, .allowWithFaceID, .alwaysAllowInTurn, .allowInConversation, .alwaysAllow, .allowWithModifiedCommand, .answerQuestion:
            if (decision == .alwaysAllowInTurn || decision == .allowInConversation || decision == .alwaysAllow),
               let pattern = targetStep.requestedInteraction?.permission?.suggestedPersistPattern {
                activeTurnGrants.insert(pattern)
                if decision == .alwaysAllow, let spec = targetStep.requestedInteraction?.permission {
                    let ruleAction = PermissionRuleAction(rawValue: spec.action.lowercased()) ?? .command
                    addPermissionRule(PermissionRuleEntry(list: .allow, action: ruleAction, target: pattern))
                }
            }
            steps[idx].status = .done

            // Advance 7-segment task checklist if present
            if let tbIdx = steps.lastIndex(where: { $0.type == .taskBoundary }),
               var boundary = steps[tbIdx].taskBoundary {
                boundary.completedCount = min(boundary.totalCount, boundary.completedCount + 1)
                boundary.taskName = "Task · \(boundary.completedCount) of \(boundary.totalCount) done"
                for cIdx in boundary.checklist.indices where boundary.checklist[cIdx].status == .waiting {
                    boundary.checklist[cIdx].status = .done
                    boundary.checklist[cIdx].trailingBadge = "p99 4.2ms"
                }
                steps[tbIdx].taskBoundary = boundary
            }

            if !hasPairedBackend && !isLiveBackendConnected {
                let nextStepIndex = (steps.map(\.stepIndex).max() ?? stepIndex) + 1
                let followUp = CascadeStep(
                    cascadeId: activeCascadeId,
                    stepIndex: nextStepIndex,
                    type: .plannerResponse,
                    status: .done,
                    plannerResponse: PlannerResponsePayload(
                        response: "Face ID verified — executed `\(targetStep.runCommand?.commandLine ?? "approved action")`. Load test sustained 2,000 req/s with 0 drops.",
                        thinking: "Received signed HandleCascadeUserInteraction approval on step \(stepIndex).",
                        thinkingDurationSeconds: 1.4
                    )
                )
                steps.append(followUp)

                if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
                    summaries[sumIdx].status = .done
                    summaries[sumIdx].stepCount = steps.count
                    summaries[sumIdx].currentStepIndex = min(summaries[sumIdx].totalSteps, summaries[sumIdx].currentStepIndex + 1)
                    summaries[sumIdx].statusSubtitle = "Done · Load test passed"
                    summaries[sumIdx].pendingInteractionTitle = nil
                    summaries[sumIdx].updatedAt = Date()
                }
            } else if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
                summaries[sumIdx].status = .inProgress
                summaries[sumIdx].statusSubtitle = "Running · Approved action"
                summaries[sumIdx].pendingInteractionTitle = nil
                summaries[sumIdx].updatedAt = Date()
            }
        }

        stepsByCascadeId[activeCascadeId] = steps
        presentedSheet = nil

        if let payload, (kmpEngine != nil || rpcClient != nil) {
            let storeRef = projectionStore
            let clientRef = rpcClient
            let engineRef = kmpEngine
            let workspaceUriRef = selectedWorkspaceUri
            let cid = activeCascadeId
            let originUuid = summaries.first(where: { $0.cascadeId == cid })?.originInstanceUuid
            let shouldSyncLive = (hasPairedBackend || isLiveBackendConnected)
            let isRejection = (decision == .reject)
            let entry = OutboxEntry(cascadeId: cid, kind: .interactionApproval, messageText: "\(payload.stepIndex)")
            Task { [weak self] in
                await storeRef.enqueueOutbox(entry)
                var interactionError: String? = nil
                do {
                    if let engineRef {
                        _ = try await engineRef.resolveWaitingInteraction(
                            step: targetStep,
                            decision: decision,
                            workspaceUri: workspaceUriRef,
                            instanceUuidOverride: originUuid
                        )
                    } else if let clientRef {
                        try await clientRef.handleCascadeUserInteraction(payload, instanceUuidOverride: originUuid)
                    }
                } catch {
                    if shouldSyncLive {
                        interactionError = error.localizedDescription
                    }
                }
                await storeRef.removeOutboxEntry(id: entry.id)
                guard let self else { return }
                if let interactionError {
                    self.stepLoadErrorText = "Approval failed: \(interactionError)"
                } else if shouldSyncLive && !isRejection {
                    self.optimisticActiveUntilByCascadeId[cid] = Date().addingTimeInterval(6.0)
                }
                if shouldSyncLive && !cid.isEmpty {
                    self.syncStepsForCascade(cid, pollUntilIdle: !isRejection && interactionError == nil)
                }
            }
        }
    }

    // MARK: - Structured Multi-Step Question Actions (`UE10`)

    public func toggleQuestionOption(_ option: String, stepIndex: Int? = nil) {
        let idx = stepIndex ?? activeQuestionStepIndex
        guard questionSteps.indices.contains(idx) else { return }
        if questionSteps[idx].selectedOptions.contains(option) {
            questionSteps[idx].selectedOptions.remove(option)
        } else {
            if !questionSteps[idx].isMultiSelect {
                questionSteps[idx].selectedOptions.removeAll()
            }
            questionSteps[idx].selectedOptions.insert(option)
        }
    }

    public func advanceQuestionStep() {
        guard questionSteps.indices.contains(activeQuestionStepIndex) else { return }
        questionSteps[activeQuestionStepIndex].isCompleted = true
        if activeQuestionStepIndex + 1 < questionSteps.count {
            activeQuestionStepIndex += 1
        } else if let waiting = pendingWaitingStep {
            let combinedOptions = questionSteps.flatMap { Array($0.selectedOptions).sorted() }
            let custom = questionSteps
                .map(\.customWriteIn)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "; ")
            resolveWaitingStep(
                stepIndex: waiting.stepIndex,
                decision: .answerQuestion(
                    selectedOptions: combinedOptions,
                    customWriteIn: custom.isEmpty ? nil : custom
                )
            )
        }
    }

    public func previousQuestionStep() {
        guard activeQuestionStepIndex > 0 else { return }
        activeQuestionStepIndex -= 1
    }

    public func submitFreeformQuestionReply(_ text: String? = nil) {
        let body = (text ?? questionFreeformReplyDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        questionFreeformReplyDraft = ""
        if let waiting = pendingWaitingStep {
            resolveWaitingStep(
                stepIndex: waiting.stepIndex,
                decision: .answerQuestion(selectedOptions: [], customWriteIn: body)
            )
        } else {
            composerDraftText = body
            sendCurrentDraft()
        }
    }


    // MARK: - Conversation Overview, Subagents & Background Tasks

    public func refreshConversationOverview() async {
        let cid = activeCascadeId
        let steps = activeSteps

        // Extract local fallback overview from live steps & diffs so Overview always works offline or live
        var extractedSubagents: [SubagentPayload] = []
        var extractedPRs: [GitHubPullRequestInfo] = []
        var extractedDocs: [String] = []
        var seenPrIds: Set<String> = []
        for step in steps {
            if let sub = step.subagent {
                extractedSubagents.append(sub)
            }
            if let resp = step.plannerResponse?.response {
                for pr in AntigravityMarkdownParser.extractGitHubPRLinks(from: resp) where seenPrIds.insert(pr.id).inserted {
                    extractedPRs.append(pr)
                }
            }
            for ref in step.plannerResponse?.referencedFiles ?? [] {
                if !extractedDocs.contains(ref) { extractedDocs.append(ref) }
            }
        }

        if let client = rpcClient, !cid.isEmpty, (hasPairedBackend || isLiveBackendConnected) {
            if let remote = try? await client.fetchConversationOverview(cascadeId: cid) {
                var merged = remote
                merged.artifacts = activeArtifacts
                if merged.subagents.isEmpty { merged.subagents = extractedSubagents }
                if merged.pullRequests.isEmpty { merged.pullRequests = extractedPRs }
                if merged.modifiedFiles.isEmpty { merged.modifiedFiles = activeTurnDiffs.map(\.filePath) }
                if merged.reviewAdditions == 0 { merged.reviewAdditions = activeTurnDiffs.reduce(0) { $0 + $1.additions } }
                if merged.reviewDeletions == 0 { merged.reviewDeletions = activeTurnDiffs.reduce(0) { $0 + $1.deletions } }
                conversationOverview = merged
                return
            }
        }

        conversationOverview = ConversationOverviewSnapshot(
            reviewAdditions: activeTurnDiffs.reduce(0) { $0 + $1.additions },
            reviewDeletions: activeTurnDiffs.reduce(0) { $0 + $1.deletions },
            modifiedFiles: activeTurnDiffs.map(\.filePath),
            subagents: extractedSubagents,
            backgroundTasks: conversationOverview.backgroundTasks,
            goals: conversationOverview.goals,
            artifacts: activeArtifacts,
            documentLinks: extractedDocs,
            pullRequests: extractedPRs
        )
    }

    public func cancelBackgroundTask(_ taskId: String) {
        let previousTask = conversationOverview.backgroundTasks.first(where: { $0.id == taskId })
        if let idx = conversationOverview.backgroundTasks.firstIndex(where: { $0.id == taskId }) {
            conversationOverview.backgroundTasks[idx].status = .cancelled
            conversationOverview.backgroundTasks[idx].canCancel = false
        }
        let cid = activeCascadeId
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
        guard let clientRef = rpcClient else { return }
        Task { [weak self] in
            do {
                try await clientRef.cancelBackgroundTask(cascadeId: cid, taskId: taskId)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let prev = previousTask,
                   let idx = self.conversationOverview.backgroundTasks.firstIndex(where: { $0.id == taskId }) {
                    self.conversationOverview.backgroundTasks[idx] = prev
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .backgroundTaskControl,
                    fallbackActionLabel: "Cancelling background task"
                )
            }
        }
    }

    public func stopSubagent(_ subagentId: String) {
        let previousSubagent = conversationOverview.subagents.first(where: { $0.subagentId == subagentId })
        if let idx = conversationOverview.subagents.firstIndex(where: { $0.subagentId == subagentId }) {
            conversationOverview.subagents[idx].status = .cancelled
        }
        let cid = activeCascadeId
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
        guard let clientRef = rpcClient else { return }
        Task { [weak self] in
            do {
                try await clientRef.stopSubagent(cascadeId: cid, subagentId: subagentId)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let prev = previousSubagent,
                   let idx = self.conversationOverview.subagents.firstIndex(where: { $0.subagentId == subagentId }) {
                    self.conversationOverview.subagents[idx] = prev
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .backgroundTaskControl,
                    fallbackActionLabel: "Stopping subagent"
                )
            }
        }
    }

    // MARK: - Multi-Turn /btw Side Questions

    public func openSideQuestion(initialPrompt: String? = nil) {
        if sideQuestionThread.parentCascadeId != activeCascadeId {
            sideQuestionThread = SideQuestionThread(parentCascadeId: activeCascadeId)
        }
        presentedSheet = .sideQuestion
        if let initialPrompt, !initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendSideQuestion(initialPrompt)
        }
    }

    public func sendSideQuestion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if sideQuestionThread.parentCascadeId != activeCascadeId {
            sideQuestionThread = SideQuestionThread(parentCascadeId: activeCascadeId)
        }
        sideQuestionThread.messages.append(SideQuestionMessage(isUser: true, text: trimmed))
        sideQuestionThread.isStreaming = true

        let cid = activeCascadeId
        let threadId = sideQuestionThread.threadId
        let clientRef = rpcClient
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)

        Task { [weak self] in
            let reply: SideQuestionMessage
            if isLive, let clientRef, !cid.isEmpty {
                do {
                    reply = try await clientRef.sendSideQuestion(cascadeId: cid, question: trimmed, threadId: threadId)
                    await self?.refreshHostCapabilitiesFromClient()
                } catch {
                    if let self {
                        await self.handleLiveCapabilityWriteError(
                            error,
                            capability: .sideQuestion,
                            fallbackActionLabel: "/btw side question"
                        )
                        let honestText = self.compatibilityNoticeText
                            ?? self.activeHostCapabilities.userFacingUnsupportedMessage(for: .sideQuestion)
                        reply = SideQuestionMessage(isUser: false, text: "⚠️ \(honestText)")
                    } else {
                        reply = SideQuestionMessage(isUser: false, text: "⚠️ Side question failed: \(error.localizedDescription)")
                    }
                }
            } else {
                reply = SideQuestionMessage(
                    isUser: false,
                    text: "Read-only side analysis (does not mutate main context): `\(trimmed)` — checked current branch `\(self?.activeSummary?.branchName ?? "main")` and \(self?.activeSteps.count ?? 0) conversation steps."
                )
            }
            self?.sideQuestionThread.messages.append(reply)
            self?.sideQuestionThread.isStreaming = false
        }
    }

    public func insertSideQuestionAnswerIntoMain() {
        guard let answer = sideQuestionThread.latestAssistantAnswer, !answer.isEmpty else { return }
        let prefix = composerDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        composerDraftText += "\(prefix)From /btw side note:\n> \(answer)"
        presentedSheet = nil
    }

    public func resetSideQuestionThread() {
        sideQuestionThread = SideQuestionThread(parentCascadeId: activeCascadeId)
    }

    // MARK: - Message Queueing, Conversation Navigator & Revert to Step

    public func enqueueFollowUpMessage(_ text: String, attachments: [ComposerAttachmentChip] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queuedMessages.append(
            QueuedMessageItem(cascadeId: activeCascadeId, text: trimmed, attachments: attachments)
        )
    }

    public func updateQueuedMessage(id: String, newText: String) {
        if let idx = queuedMessages.firstIndex(where: { $0.id == id }) {
            queuedMessages[idx].text = newText
        }
    }

    public func removeQueuedMessage(id: String) {
        queuedMessages.removeAll { $0.id == id }
    }

    public func flushNextQueuedMessageIfIdle() {
        guard !isCascadeStreaming,
              let idx = queuedMessages.firstIndex(where: { $0.cascadeId == activeCascadeId }) else {
            return
        }
        let next = queuedMessages.remove(at: idx)
        composerDraftText = next.text
        composerAttachments = next.attachments
        sendCurrentDraft()
    }

    public var conversationTurns: [ConversationTurnSummary] {
        var turnNumber = 0
        return activeSteps.compactMap { step in
            guard step.type == .userInput, let text = step.userInput, !text.isEmpty else { return nil }
            turnNumber += 1
            return ConversationTurnSummary(
                turnNumber: turnNumber,
                stepIndex: step.stepIndex,
                promptPreview: String(text.prefix(72)),
                timestamp: step.createdAt
            )
        }
    }

    public func revertConversationToStep(_ stepIndex: Int) {
        guard let previousSteps = stepsByCascadeId[activeCascadeId] else { return }
        var steps = previousSteps
        steps.removeAll { $0.stepIndex > stepIndex }
        stepsByCascadeId[activeCascadeId] = steps
        let cid = activeCascadeId
        let clientRef = rpcClient
        let storeRef = projectionStore
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
        Task { [weak self] in
            await storeRef.saveProjectedSteps(steps, for: cid)
            guard let clientRef else { return }
            do {
                try await clientRef.revertConversationToStep(cascadeId: cid, stepIndex: stepIndex)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                self.stepsByCascadeId[cid] = previousSteps
                await storeRef.saveProjectedSteps(previousSteps, for: cid)
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .revertToStep,
                    fallbackActionLabel: "Reverting conversation"
                )
            }
        }
    }


    // MARK: - Live Structured Question Hydration (`UE10`)

    public func syncActiveLiveQuestionFromSteps(stepIndex: Int? = nil) {
        guard !isVerificationMode else { return }
        guard let waiting = waitingStep(at: stepIndex),
              let ask = waiting.effectiveRequestedInteraction?.askQuestion else {
            return
        }
        let stepId = "live-q-\(waiting.stepIndex)"
        if questionSteps.first?.id != stepId {
            questionSteps = [
                StructuredQuestionStepItem(
                    id: stepId,
                    stepNumber: 1,
                    shortTabTitle: "Question",
                    questionTitle: ask.question,
                    options: ask.options,
                    selectedOptions: [],
                    customWriteIn: "",
                    isCompleted: false,
                    isMultiSelect: ask.isMultiSelect
                )
            ]
            activeQuestionStepIndex = 0
        }
    }


    // MARK: - Gemini Live Voice Mode

    public func startVoiceMode() {
        voiceModeState.isActive = true
        voiceModeState.isMuted = false
        voiceModeState.startedAt = Date()
        if voiceModeState.activeTurns.isEmpty {
            voiceModeState.activeTurns.append(
                VoiceTranscriptTurn(
                    isUser: false,
                    transcript: "Connected to Gemini Live Voice Mode (\(voiceModeState.selectedVoiceId.capitalized)). How can I help with \(activeSummary?.projectSlug ?? "this workspace")?"
                )
            )
        }
        presentedSheet = .voiceMode
    }

    public func toggleVoiceMute() {
        voiceModeState.isMuted.toggle()
    }

    public func interruptVoiceAgent() {
        voiceModeState.isAgentSpeaking = false
    }

    public func selectVoiceOption(_ voiceId: String) {
        voiceModeState.selectedVoiceId = voiceId
    }

    public func setVoicePlaybackSpeed(_ speed: Double) {
        voiceModeState.playbackSpeed = min(2.0, max(0.75, speed))
    }

    public func appendVoiceTranscriptTurn(isUser: Bool, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        voiceModeState.activeTurns.append(VoiceTranscriptTurn(isUser: isUser, transcript: trimmed))
        if isUser {
            voiceModeState.isAgentSpeaking = true
            let ack = "Got it — queued voice instruction: \"\(trimmed)\" on \(activeSummary?.title ?? "active conversation")."
            voiceModeState.activeTurns.append(VoiceTranscriptTurn(isUser: false, transcript: ack))
            voiceModeState.isAgentSpeaking = false
        }
    }

    public func endVoiceMode() {
        guard voiceModeState.isActive else {
            presentedSheet = nil
            return
        }
        let duration = max(1, Int(Date().timeIntervalSince(voiceModeState.startedAt ?? Date())))
        let turns = voiceModeState.activeTurns
        let userTurnCount = turns.filter(\.isUser).count
        let summary = VoiceCallTranscriptSummary(
            cascadeId: activeCascadeId,
            durationSeconds: duration,
            summaryText: "Voice Mode session (\(duration)s · \(userTurnCount) spoken prompts · \(voiceModeState.selectedVoiceId.capitalized))",
            turns: turns
        )
        voiceModeState.lastCallSummary = summary
        voiceModeState.isActive = false
        voiceModeState.isAgentSpeaking = false
        voiceModeState.activeTurns = []

        if !activeCascadeId.isEmpty {
            var currentSteps = stepsByCascadeId[activeCascadeId] ?? []
            let nextIdx = (currentSteps.map(\.stepIndex).max() ?? 0) + 1
            let callStep = CascadeStep(
                cascadeId: activeCascadeId,
                stepIndex: nextIdx,
                type: .plannerResponse,
                status: .done,
                plannerResponse: PlannerResponsePayload(response: summary.summaryText),
                voiceSummary: summary
            )
            currentSteps.append(callStep)
            stepsByCascadeId[activeCascadeId] = currentSteps
        }
        presentedSheet = nil
    }

}
