import Foundation

/// Project workspace creation, scoped conversations, and Antigravity 2.0 native Automations sidecars.
extension AntigravitySessionStore {
    // MARK: - Project Creation & Scoped Conversation Actions (`UE05`)

    @discardableResult
    public func createNewProject(
        name: String? = nil,
        runtime: ProjectRuntimeTarget? = nil,
        source: ProjectSourceKind? = nil,
        selectedRepo: GitHubRepoItem? = nil,
        branchWorktree: String? = nil
    ) -> ProjectWorkspace {
        var draft = newProjectDraft
        if let runtime { draft.runsOn = runtime }
        if let source { draft.source = source }
        if let selectedRepo { draft.selectedRepo = selectedRepo }
        if let branchWorktree { draft.branchWorktree = branchWorktree }
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.projectName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let slug = draft.projectName.isEmpty ? "new-project" : draft.projectName
        let repoPath = draft.selectedRepo?.fullName ?? "acme/\(slug)"
        let pathDisplay = draft.runsOn == .cloud ? "cloud://\(repoPath)" : "~/code/\(slug)"
        let workspaceUri = draft.runsOn == .cloud ? "cloud://\(repoPath)" : "file:///Users/wl/code/\(slug)"
        let branch = draft.selectedRepo?.defaultBranch ?? "main"

        let created = ProjectWorkspace(
            id: slug,
            name: slug,
            pathDisplay: pathDisplay,
            workspaceUri: workspaceUri,
            runtime: draft.runsOn,
            hostName: draft.runsOn == .cloud ? "Cloud" : draft.runsOn.rawValue,
            activeBranch: branch,
            worktrees: [branch, "worktree/\(slug)"],
            isExpandedInHome: true,
            rulesAndSkillsCount: 4
        )
        if let existingIdx = projects.firstIndex(where: { $0.id == slug }) {
            projects[existingIdx] = created
        } else {
            projects.append(created)
        }
        selectedProjectId = created.id
        selectedWorkspaceUri = created.workspaceUri
        presentedSheet = nil
        selectedTab = .agents
        activeRoute = .tabRoot

        let projectsSnapshot = projects
        let storeRef = projectionStore
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        Task { [weak self] in
            await storeRef.saveProjects(projectsSnapshot)
            guard let clientRef else { return }
            do {
                let remoteCreated = try await clientRef.createProjectWorkspace(draft: draft)
                await self?.refreshHostCapabilitiesFromClient()
                if let self,
                   let idx = self.projects.firstIndex(where: { $0.id == slug }) {
                    self.projects[idx].cloudProjectId = remoteCreated.cloudProjectId ?? self.projects[idx].cloudProjectId
                    self.projects[idx].originInstanceUuid = remoteCreated.originInstanceUuid ?? self.projects[idx].originInstanceUuid
                    await storeRef.saveProjects(self.projects)
                }
            } catch {
                guard let self, isLive else { return }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .conversationAnnotations,
                    fallbackActionLabel: "Creating project workspace"
                )
            }
        }
        return created
    }

    @discardableResult
    public func createConversationInProject(
        _ projectSlug: String,
        title: String = "New Conversation",
        initialPrompt: String? = nil,
        initialAttachments: [ComposerAttachmentChip] = [],
        isCloudOverride: Bool? = nil
    ) -> String {
        discardPendingDraftConversation()
        let hasInitialPayload = (initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            || !initialAttachments.isEmpty
        if !initialAttachments.isEmpty {
            // Clear immediately so the newly opened chat composer does not display stale pre-send chips
            composerAttachments.removeAll()
        }
        let optimisticId = "cas-\(UUID().uuidString.prefix(8).lowercased())"
        let trimmedSlug = projectSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        let project: ProjectWorkspace? = {
            if let exact = projects.first(where: { $0.id == trimmedSlug }) {
                return exact
            }
            if case .localHost(let scopeId, let scopeName) = selectedHostScope {
                if let scopedMatch = projects.first(where: {
                    $0.runtime != .cloud
                        && ($0.name == trimmedSlug || (AntigravityCloudDetector.isNoProjectSlug(trimmedSlug) && $0.isNoProject))
                        && ($0.originInstanceUuid == scopeId || $0.hostName == scopeName)
                }) {
                    return scopedMatch
                }
            }
            if selectedHostScope == .antigravityCloud {
                if let cloudMatch = projects.first(where: {
                    $0.runtime == .cloud
                        && ($0.name == trimmedSlug || (AntigravityCloudDetector.isNoProjectSlug(trimmedSlug) && $0.isNoProject))
                }) {
                    return cloudMatch
                }
            }
            return projects.first(where: { $0.name == trimmedSlug })
        }()
        let isUnassigned = (project?.isNoProject == true) || AntigravityCloudDetector.isNoProjectSlug(trimmedSlug)
        let isCloudProj = isCloudOverride
            ?? ((project?.runtime == .cloud)
                || trimmedSlug.lowercased().hasPrefix("cloud:")
                || (project == nil && selectedHostScope == .antigravityCloud))
        let effectiveSlug: String = {
            if let project { return project.id }
            if isUnassigned {
                let hasLocalNoProj = projects.contains(where: { $0.isNoProject && $0.runtime != .cloud })
                if isCloudProj && hasLocalNoProj {
                    return "cloud:\(AntigravityCloudDetector.noProjectDisplayName)"
                }
                return AntigravityCloudDetector.noProjectDisplayName
            }
            return trimmedSlug
        }()
        let cloudProjId = isUnassigned ? nil : project?.cloudProjectId
        let originUuid: String? = {
            if isCloudProj { return project?.originInstanceUuid }
            if let projUuid = project?.originInstanceUuid, !projUuid.isEmpty {
                return projUuid
            }
            if case .localHost(let scopeId, _) = selectedHostScope, !scopeId.isEmpty {
                return scopeId
            }
            return activeHost.instanceId == "unpaired" ? nil : activeHost.instanceId
        }()
        let resolvedOriginHostName: String = {
            if isCloudProj { return "Antigravity" }
            if let projHost = project?.hostName, !projHost.isEmpty, projHost != "Cloud" {
                return projHost
            }
            if case .localHost(_, let scopeName) = selectedHostScope, !scopeName.isEmpty {
                return scopeName
            }
            return activeHost.hostname
        }()
        let workspaceUri: String = {
            if isUnassigned { return "" }
            if let existingUri = project?.workspaceUri, !existingUri.isEmpty {
                return existingUri
            }
            if hasPairedBackend || isLiveBackendConnected {
                return ""
            }
            return isCloudProj ? "cloud://\(trimmedSlug)" : "file:///Users/wl/code/\(trimmedSlug)"
        }()
        let branch = isUnassigned ? "" : (project?.activeBranch ?? "main")

        let initialPreviewText: String = {
            if let p = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                return p
            }
            if !initialAttachments.isEmpty {
                return "Attached: \(initialAttachments.map(\.label).joined(separator: ", "))"
            }
            return "Ready for instructions..."
        }()
        let newSummary = CascadeSummary(
            cascadeId: optimisticId,
            title: title,
            projectSlug: effectiveSlug,
            workspaceUri: workspaceUri,
            branchName: branch,
            status: .done,
            stepCount: 0,
            currentStepIndex: 1,
            totalSteps: 1,
            updatedAt: Date(),
            relativeTimeLabel: "now",
            statusSubtitle: hasInitialPayload ? "Sending..." : "Ready for instructions",
            isPinned: displayOptions.autoPinOnMessage,
            isArchived: false,
            isUnread: false,
            modelLabel: selectedModelConfig.displayName,
            lastMessagePreview: initialPreviewText,
            isCloud: isCloudProj,
            cloudProjectId: cloudProjId,
            originInstanceUuid: originUuid,
            originHostName: resolvedOriginHostName,
            hasResolvedTitle: true
        )
        summaries.insert(newSummary, at: 0)
        if (hasPairedBackend || isLiveBackendConnected) && project == nil {
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
        if !hasInitialPayload {
            locallyCreatedEmptyCascadeIds.insert(optimisticId)
        }
        activeCascadeId = optimisticId
        selectedProjectId = summaries.first(where: { $0.cascadeId == optimisticId })?.projectSlug ?? effectiveSlug
        selectedWorkspaceUri = workspaceUri
        activeRoute = .cascadeChat(optimisticId)

        // When launched with an initial prompt or attachment (e.g. Home composer send), dispatch
        // synchronously through a single `sendCurrentDraft` transaction so the user message bubble
        // appears immediately (never flashing an empty `Ready for Prompt` / `Host Offline` card with
        // a Stop button) and `StartCascade` + `SendUserCascadeMessage` execute exactly once.
        if hasInitialPayload {
            composerDraftText = initialPrompt ?? ""
            composerAttachments = initialAttachments
            sendCurrentDraft(bypassStreamingQueue: true, skipUpgradeWait: true)
            return optimisticId
        }

        let clientRef = rpcClient
        let engineRef = kmpEngine
        let modelId = selectedModelConfig.modelId
        let shouldCallLiveBackend = isLiveBackendConnected || (hasPairedBackend && !isConnectingToBackend)
        let isLive = isLiveBackendActive

        Task { [weak self] in
            var createdCascadeId: String? = nil
            if shouldCallLiveBackend {
                do {
                    if let engineRef {
                        createdCascadeId = try await engineRef.startConversation(
                            workspaceUri: workspaceUri,
                            initialPrompt: "",
                            modelId: modelId,
                            cloudProjectId: cloudProjId,
                            isCloud: isCloudProj,
                            instanceUuidOverride: originUuid
                        )
                    } else if let clientRef {
                        createdCascadeId = try await clientRef.startCascade(
                            workspaceUri: workspaceUri,
                            initialPrompt: "",
                            modelId: modelId,
                            cloudProjectId: cloudProjId,
                            isCloud: isCloudProj,
                            instanceUuidOverride: originUuid
                        )
                    }
                } catch {
                    if let self, isLive {
                        if Self.isBackendOfflineError(error) {
                            if !isCloudProj {
                                self.markLocalHostOffline(
                                    instanceUuid: originUuid,
                                    hostname: resolvedOriginHostName,
                                    error: error
                                )
                            }
                        } else {
                            await self.handleLiveCapabilityWriteError(
                                error,
                                capability: .conversationAnnotations,
                                fallbackActionLabel: "Starting conversation"
                            )
                        }
                    }
                }
            }
            if let realCascadeId = createdCascadeId, !realCascadeId.isEmpty {
                guard let self else { return }
                let belongsToActiveHost = !isCloudProj && (
                    originUuid == nil
                        || originUuid?.isEmpty == true
                        || originUuid == self.activeHost.instanceId
                )
                if belongsToActiveHost && self.hasPairedBackend && (!self.isLiveBackendConnected || !self.activeHost.isOnline) {
                    self.markBackendReconnected()
                }
                let wasEmptyNew = self.locallyCreatedEmptyCascadeIds.remove(optimisticId) != nil
                let existingSteps = self.stepsByCascadeId.removeValue(forKey: optimisticId) ?? []
                if wasEmptyNew && existingSteps.isEmpty {
                    self.locallyCreatedEmptyCascadeIds.insert(realCascadeId)
                }
                self.stepsByCascadeId[realCascadeId] = existingSteps.map { step in
                    var copy = step
                    copy.cascadeId = realCascadeId
                    return copy
                }
                if let idx = self.summaries.firstIndex(where: { $0.cascadeId == optimisticId }) {
                    self.summaries[idx].cascadeId = realCascadeId
                }
                if self.activeCascadeId == optimisticId {
                    self.activeCascadeId = realCascadeId
                    if case .cascadeChat = self.activeRoute {
                        self.activeRoute = .cascadeChat(realCascadeId)
                    }
                }
                if !self.locallyCreatedEmptyCascadeIds.contains(realCascadeId) {
                    self.syncStepsForCascade(realCascadeId, pollUntilIdle: false)
                }
            }
        }
        return optimisticId
    }

    public func createNewCascade(
        title: String = "New Agentic Session",
        branchName: String? = nil,
        initialPrompt: String? = nil
    ) {
        let slug: String = {
            if let selected = selectedProject,
               !selected.id.isEmpty,
               projectMatchesHostScope(selected) {
                return selected.id
            }
            if hasPairedBackend || isLiveBackendConnected {
                if let scopedProject = projects.first(where: { projectMatchesHostScope($0) && !$0.isNoProject })
                    ?? projects.first(where: { projectMatchesHostScope($0) }) {
                    return scopedProject.id
                }
                if selectedHostScope == .antigravityCloud {
                    return "cloud:\(AntigravityCloudDetector.noProjectDisplayName)"
                }
                return AntigravityCloudDetector.noProjectDisplayName
            }
            if let selected = selectedProject?.id, !selected.isEmpty {
                return selected
            }
            return "ledger-svc"
        }()
        let newId = createConversationInProject(slug, title: title, initialPrompt: nil)
        if let branchName, let idx = summaries.firstIndex(where: { $0.cascadeId == newId }) {
            summaries[idx].branchName = branchName
        }
        if let initialPrompt, !initialPrompt.isEmpty {
            composerDraftText = initialPrompt
            sendCurrentDraft(bypassStreamingQueue: true)
        }
    }

    public func revealProjectInFinder(_ projectSlug: String) {
        guard let project = projects.first(where: { $0.id == projectSlug || $0.name == projectSlug }),
              project.runtime != .cloud,
              !project.isNoProject,
              !project.workspaceUri.isEmpty else { return }
        let uri = project.workspaceUri
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        Task { [weak self] in
            guard let clientRef else { return }
            do {
                try await clientRef.openWorkspaceInFinder(workspaceUri: uri)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .conversationAnnotations,
                    fallbackActionLabel: "Opening workspace in Finder"
                )
            }
        }
    }

    public func refreshWorkspacesAndSummaries(
        forceFullSync: Bool = false,
        includeAutomations: Bool = false,
        skipRelayMetadataProbe: Bool = false,
        verifyRelayEndToEnd: Bool = false,
        targetScope: AgentsHostFilterScope? = nil,
        expectedGeneration: UInt64? = nil
    ) async {
        guard !isNetworkingSuspended else { return }
        let generation = expectedGeneration ?? hostSwitchGeneration
        activeRefreshCount += 1
        isRefreshingSummaries = true
        defer {
            activeRefreshCount = max(0, activeRefreshCount - 1)
            isRefreshingSummaries = (activeRefreshCount > 0)
        }
        guard let client = rpcClient else { return }

        backgroundPollCounter += 1
        let isRelay = (activeHost.channel == .cloudRelay)
        let effectiveScope = targetScope ?? selectedHostScope
        let syncTimeout: TimeInterval = isRelay ? 14.0 : 3.5
        let useLightweight = !forceFullSync && isRelay && (backgroundPollCounter % 4 != 1) && isSummaryStreamHealthy
        let allowCrossHostFallback = (effectiveScope == .allHosts || effectiveScope == .antigravityCloud)

        var didRefreshRelayList = skipRelayMetadataProbe
        if isRelay && !skipRelayMetadataProbe {
            let probeResult: HostReachabilityProbeResult?
            if let kmpEngine {
                probeResult = try? await kmpEngine.probeHostReachability(
                    allowCrossHostFallback: allowCrossHostFallback,
                    verifyEndToEnd: verifyRelayEndToEnd
                )
            } else {
                probeResult = try? await client.probeHostReachability(
                    timeoutInterval: min(syncTimeout, 8.0),
                    allowCrossHostFallback: allowCrossHostFallback,
                    verifyEndToEnd: verifyRelayEndToEnd
                )
            }
            if let probe = probeResult {
                guard self.hostSwitchGeneration == generation, !self.isNetworkingSuspended else { return }
                applyRelayProbeMetadata(probe, allowCrossHostFallback: allowCrossHostFallback)
                didRefreshRelayList = true
            }
        }

        let targetInstanceUuid: String?
        let includeLocal: Bool
        let includeCloud: Bool
        if isRelay {
            switch effectiveScope {
            case .localHost(let id, _):
                targetInstanceUuid = id
                includeLocal = true
                includeCloud = false
            case .antigravityCloud:
                targetInstanceUuid = nil
                includeLocal = false
                includeCloud = true
            case .allHosts:
                targetInstanceUuid = nil
                includeLocal = true
                includeCloud = true
            }
        } else {
            targetInstanceUuid = nil
            includeLocal = true
            includeCloud = true
        }

        do {
            let federated: (
                workspaces: [WorkspaceInfo],
                summaries: [CascadeSummary],
                cloudProjects: [ProjectWorkspace],
                cloudWarmingUp: Bool,
                availableRelayInstances: [RelayInstanceInfo],
                succeededInstanceUuids: Set<String>,
                cloudSucceeded: Bool
            )
            if let kmpEngine {
                let kmpSync = try await kmpEngine.refreshWorkspacesAndSummaries(
                    hostScope: effectiveScope,
                    skipRelayListRefresh: didRefreshRelayList
                )
                federated = (
                    workspaces: kmpSync.workspaces,
                    summaries: kmpSync.summaries,
                    cloudProjects: kmpSync.cloudProjects,
                    cloudWarmingUp: kmpSync.cloudWarmingUp,
                    availableRelayInstances: kmpSync.availableRelayInstances,
                    succeededInstanceUuids: Set(kmpSync.succeededInstanceUuids),
                    cloudSucceeded: kmpSync.cloudSucceeded
                )
            } else {
                federated = try await client.fetchFederatedWorkspacesAndSummaries(
                    timeoutInterval: syncTimeout,
                    lightweightPoll: useLightweight,
                    skipRelayListRefresh: didRefreshRelayList,
                    targetInstanceUuid: targetInstanceUuid,
                    includeLocal: includeLocal,
                    includeCloud: includeCloud
                )
            }
            guard self.hostSwitchGeneration == generation, !self.isNetworkingSuspended else { return }

            if isRelay && !federated.availableRelayInstances.isEmpty {
                syncRelayInstancesToHosts(
                    federated.availableRelayInstances,
                    latencyMs: lastPingLatencyMs
                )
            }

            if isRelay, case .localHost(let targetId, let targetName) = effectiveScope {
                if federated.succeededInstanceUuids.isEmpty {
                    var offlineHost = activeHost
                    offlineHost.isOnline = false
                    activeHost = offlineHost
                    if let idx = hosts.firstIndex(where: { $0.instanceId == offlineHost.instanceId || $0.instanceId == targetId }) {
                        hosts[idx].isOnline = false
                    }
                    isLiveBackendConnected = false
                    connectionStatusText = "Offline · \(activeHost.hostname)"
                    connectionErrorText = "\(targetName) is currently offline."
                    let nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelay(
                        attempt: reconnectAttemptCount,
                        isLowPowerMode: isLowPowerModeEnabled
                    )
                    connectionLifecyclePhase = .offlineBackoff(attempt: reconnectAttemptCount, nextRetrySeconds: nextDelay)
                    return
                }
                if let liveUuid = federated.succeededInstanceUuids.first,
                   liveUuid != activeHost.instanceId,
                   let liveInst = federated.availableRelayInstances.first(where: { $0.uuid == liveUuid }) {
                    let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
                    let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
                    let nextURL = URL(string: "\(originPrefix)/r/\(liveInst.uuid)") ?? activeHost.endpointURL
                    let refreshedHost = RemoteHostInstance(
                        instanceId: liveInst.uuid,
                        hostname: liveInst.name,
                        version: liveInst.version,
                        channel: .cloudRelay,
                        endpointURL: nextURL,
                        isOnline: true,
                        latencyMs: lastPingLatencyMs ?? activeHost.latencyMs
                    )
                    activeHost = refreshedHost
                    if let idx = hosts.firstIndex(where: { $0.instanceId == refreshedHost.instanceId }) {
                        hosts[idx] = refreshedHost
                    } else {
                        hosts.insert(refreshedHost, at: 0)
                    }
                    if case .localHost = selectedHostScope {
                        selectedHostScope = .localHost(id: refreshedHost.instanceId, name: refreshedHost.hostname)
                        persistSelectedHostScope()
                    }
                }
            } else if isRelay && federated.succeededInstanceUuids.isEmpty && !federated.cloudSucceeded {
                if !federated.availableRelayInstances.isEmpty
                    && federated.availableRelayInstances.allSatisfy({ !$0.status.isReachable }) {
                    markBackendOffline(
                        error: AntigravityRPCError.httpError(
                            statusCode: 503,
                            body: "No reachable Antigravity Desktop instances online"
                        )
                    )
                }
                return
            }

            consecutiveSyncFailures = 0
            lastBackendActivityAt = Date()
            lastFullSyncAt = Date()
            cloudAgentWarmingUp = federated.cloudWarmingUp

            if isRelay && !didRefreshRelayList && federated.availableRelayInstances.isEmpty {
                let latestInstances = await client.currentCachedRelayInstances()
                if !latestInstances.isEmpty {
                    syncRelayInstancesToHosts(latestInstances)
                }
            }

            var replacedLocalUuids = federated.succeededInstanceUuids
            if isRelay, case .localHost(let targetId, _) = effectiveScope, !federated.succeededInstanceUuids.isEmpty {
                replacedLocalUuids.insert(targetId)
            }
            var replacedLocalHostNames = Set<String>()
            for inst in federated.availableRelayInstances where replacedLocalUuids.contains(inst.uuid) {
                replacedLocalHostNames.insert(inst.name)
            }
            for h in hosts where replacedLocalUuids.contains(h.instanceId) {
                replacedLocalHostNames.insert(h.hostname)
            }
            if replacedLocalUuids.contains(activeHost.instanceId) {
                replacedLocalHostNames.insert(activeHost.hostname)
            }

            func isReplacedLocal(originUuid: String?, originHostName: String?) -> Bool {
                if let uuid = originUuid, !uuid.isEmpty {
                    return replacedLocalUuids.contains(uuid)
                }
                if let host = originHostName, !host.isEmpty {
                    return replacedLocalHostNames.contains(host)
                }
                return replacedLocalUuids.contains(activeHost.instanceId)
            }

            let remoteSummaries = federated.summaries
            if isRelay {
                let incomingWsKeys = Set(federated.workspaces.map { ws in
                    "\(ws.isCloud ? "cloud" : (ws.originInstanceUuid ?? "local"))|\(ws.workspaceUri)"
                })
                var keptWorkspaces = workspaces.filter { ws in
                    let key = "\(ws.isCloud ? "cloud" : (ws.originInstanceUuid ?? "local"))|\(ws.workspaceUri)"
                    if incomingWsKeys.contains(key) { return false }
                    if ws.isCloud {
                        return !federated.cloudSucceeded
                    }
                    return !isReplacedLocal(originUuid: ws.originInstanceUuid, originHostName: ws.originHostName)
                }
                keptWorkspaces.append(contentsOf: federated.workspaces)
                workspaces = keptWorkspaces
            } else if !federated.workspaces.isEmpty {
                workspaces = federated.workspaces
            }

            var activeHostResponded = !isRelay || federated.succeededInstanceUuids.contains(activeHost.instanceId)
            if !activeHostResponded && isRelay && effectiveScope == .allHosts,
               let onlinePeerUuid = federated.succeededInstanceUuids.first,
               let onlinePeerInst = availableRelayInstances.first(where: { $0.uuid == onlinePeerUuid && $0.status.isReachable }) {
                // Promote activeHost to the responding online peer in All Hosts mode rather than
                // falsely marking the offline previous activeHost back to online.
                syncRelayInstancesToHosts(
                    availableRelayInstances,
                    latencyMs: lastPingLatencyMs,
                    preferredActiveInstance: onlinePeerInst,
                    persistKeychainIfChanged: false
                )
                activeHostResponded = true
            }
            if activeHostResponded {
                if hasPairedBackend && (!isLiveBackendConnected || !activeHost.isOnline) {
                    markBackendReconnected()
                } else if isLiveBackendConnected && activeHost.isOnline {
                    connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
                    if case .localHost = effectiveScope {
                        let latencySuffix = lastPingLatencyMs.map { " · \($0)ms" } ?? ""
                        connectionStatusText = "Connected · \(activeHost.hostname)\(latencySuffix)"
                    }
                }
            }

            let existingById = Dictionary(uniqueKeysWithValues: summaries.map { ($0.cascadeId, $0) })
            let remoteIds = Set(remoteSummaries.map(\.cascadeId))
            var shouldResyncActiveCascade = false
            let now = Date()

            var mergedList: [CascadeSummary] = remoteSummaries.map { remote in
                var copy = remote
                if let existing = existingById[remote.cascadeId] {
                    let hasNewActivity = remote.stepCount > existing.stepCount
                        || remote.updatedAt.timeIntervalSince(existing.updatedAt) > 0.5
                    if existing.hasResolvedTitle && !copy.hasResolvedTitle {
                        copy.title = existing.title
                        copy.hasResolvedTitle = true
                    } else if copy.hasResolvedTitle {
                        hydratingCascadeIds.remove(remote.cascadeId)
                        settledEmptyTitleCascadeIds.remove(remote.cascadeId)
                    }
                    if existing.isCloud && !copy.isCloud {
                        copy.isCloud = true
                        copy.originHostName = "Antigravity"
                    }
                    copy.isPinned = existing.isPinned || remote.isPinned
                    copy.isArchived = existing.isArchived || remote.isArchived
                    copy.stepCount = max(existing.stepCount, remote.stepCount)
                    copy.currentStepIndex = max(1, copy.stepCount)
                    copy.totalSteps = max(1, copy.stepCount)
                    copy.cloudProjectId = remote.cloudProjectId ?? existing.cloudProjectId
                    copy.lastUserViewTime = [existing.lastUserViewTime, remote.lastUserViewTime].compactMap { $0 }.max()
                    if copy.originInstanceUuid == nil {
                        copy.originInstanceUuid = existing.originInstanceUuid
                        copy.originHostName = copy.originHostName ?? existing.originHostName
                    }
                    if let optimisticExpiry = optimisticActiveUntilByCascadeId[remote.cascadeId],
                       optimisticExpiry > now,
                       copy.status != .waiting && copy.status != .blocked && copy.status != .error {
                        copy.status = .inProgress
                    }
                    if hasNewActivity {
                        if activeRoute != .cascadeChat(remote.cascadeId) {
                            copy.isUnread = (copy.status != .inProgress && copy.status != .pending)
                            locallyViewedAtByCascadeId.removeValue(forKey: remote.cascadeId)
                        } else {
                            copy.isUnread = false
                            locallyViewedAtByCascadeId[remote.cascadeId] = now
                        }
                    } else if copy.status == .inProgress || copy.status == .pending {
                        copy.isUnread = false
                    } else if remote.lastUserViewTime == nil && existing.isUnread {
                        copy.isUnread = true
                    }
                    if remote.cascadeId == activeCascadeId && (
                        hasNewActivity
                            || remote.status != existing.status
                            || copy.status == .inProgress
                            || copy.status == .pending
                    ) {
                        shouldResyncActiveCascade = true
                    }
                } else if remote.cascadeId == activeCascadeId {
                    shouldResyncActiveCascade = true
                }
                if let viewedAt = locallyViewedAtByCascadeId[remote.cascadeId],
                   copy.updatedAt <= viewedAt {
                    copy.isUnread = false
                }
                if copy.isUnread != remote.isUnread
                    || copy.status != remote.status
                    || copy.stepCount != remote.stepCount {
                    copy.statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                        status: copy.status,
                        stepCount: copy.stepCount,
                        isUnread: copy.isUnread
                    )
                }
                return copy
            }

            // Preserve any in-flight optimistic iOS sessions (`cas-*`) not yet returned by `GetAllCascadeTrajectories`
            for local in summaries where !remoteIds.contains(local.cascadeId)
                && local.cascadeId.hasPrefix("cas-")
                && !Self.esddFixtureCascadeIds.contains(local.cascadeId)
                && (hasPairedBackend || isLiveBackendConnected) {
                mergedList.insert(local, at: 0)
            }

            // On Cloud Relay, scoped syncs only replace the hosts/cloud partition that actually succeeded;
            // cached conversations from other hosts or Cloud stay intact so switching back is instantaneous.
            if isRelay {
                for existing in summaries where !remoteIds.contains(existing.cascadeId)
                    && !existing.cascadeId.hasPrefix("cas-")
                    && !Self.esddFixtureCascadeIds.contains(existing.cascadeId) {
                    if existing.isCloud {
                        if !federated.cloudSucceeded {
                            mergedList.append(existing)
                        }
                    } else if !isReplacedLocal(
                        originUuid: existing.originInstanceUuid,
                        originHostName: existing.originHostName
                    ) {
                        mergedList.append(existing)
                    }
                }
            }

            mergedList.sort { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.cascadeId < rhs.cascadeId
            }

            if hasPairedBackend || isLiveBackendConnected {
                let effectiveCloudProjects: [ProjectWorkspace] = {
                    if !federated.cloudProjects.isEmpty {
                        return federated.cloudProjects
                    }
                    return projects.filter { $0.runtime == .cloud && $0.cloudProjectId != nil }
                }()
                projects = Self.reconcileLiveProjects(
                    workspaces: workspaces,
                    summaries: &mergedList,
                    existingProjects: projects,
                    hostName: activeHost.hostname,
                    cloudProjects: effectiveCloudProjects
                )
                summaries = mergedList
                reconcileSelectedProjectForCurrentHostScope()
                if shouldResyncActiveCascade && !activeCascadeId.isEmpty {
                    syncStepsForCascade(
                        activeCascadeId,
                        pollUntilIdle: activeRoute == .cascadeChat(activeCascadeId)
                    )
                }
            } else {
                var knownIds = Set(projects.map(\.id))
                for ws in workspaces where !knownIds.contains(ws.displayName) {
                    knownIds.insert(ws.displayName)
                    let isCloud = ws.isCloud || AntigravityCloudDetector.isCloudWorkspaceURI(ws.workspaceUri)
                    projects.insert(
                        ProjectWorkspace(
                            id: ws.displayName,
                            name: ws.displayName,
                            pathDisplay: ws.workspaceUri.replacingOccurrences(of: "file://", with: ""),
                            workspaceUri: ws.workspaceUri,
                            runtime: isCloud ? .cloud : .macBookPro,
                            hostName: isCloud ? "Cloud" : activeHost.hostname,
                            activeBranch: ws.activeBranch,
                            worktrees: ws.worktrees.isEmpty ? [ws.activeBranch] : ws.worktrees,
                            isExpandedInHome: true
                        ),
                        at: 0
                    )
                }
                for remote in mergedList {
                    if let idx = summaries.firstIndex(where: { $0.cascadeId == remote.cascadeId }) {
                        summaries[idx] = remote
                    } else {
                        summaries.append(remote)
                    }
                }
            }
            var refreshedHostKeys = Set<String>()
            if isRelay {
                for uuid in replacedLocalUuids where !uuid.isEmpty && uuid != "unpaired" {
                    refreshedHostKeys.insert("host:\(uuid)")
                }
                if federated.cloudSucceeded {
                    refreshedHostKeys.insert("cloud")
                }
            } else {
                refreshedHostKeys.insert(
                    Self.projectionHostKey(
                        isCloud: false,
                        instanceId: activeHost.instanceId,
                        hostname: activeHost.hostname,
                        fallbackHostId: activeHost.instanceId,
                        fallbackHostName: activeHost.hostname
                    )
                )
                if federated.cloudSucceeded {
                    refreshedHostKeys.insert("cloud")
                }
            }
            if !refreshedHostKeys.isEmpty {
                await persistHostProjections(refreshedHostKeys: refreshedHostKeys)
            }
            settledEmptyTitleCascadeIds.removeAll()
            preloadAttemptedAtByCascadeId.removeAll()
            scheduleConversationPreload()
        } catch {
            guard self.hostSwitchGeneration == generation else { return }
            if ProtocolCompatibilityEngine.isInstanceNotRegisteredError(error) {
                if case .localHost(let targetId, let targetName) = effectiveScope {
                    markLocalHostOffline(instanceUuid: targetId, hostname: targetName, error: error)
                } else {
                    markLocalHostOffline(instanceUuid: activeHost.instanceId, hostname: activeHost.hostname, error: error)
                }
            } else if Self.isBackendOfflineError(error) {
                consecutiveSyncFailures += 1
                let failureThreshold = ConnectionPowerPolicy.offlineFailureThreshold(
                    channel: activeHost.channel,
                    error: error
                )
                if consecutiveSyncFailures >= failureThreshold {
                    markBackendOffline(error: error)
                }
            }
            return
        }

        if isLiveBackendConnected && self.hostSwitchGeneration == generation {
            if includeAutomations {
                await refreshAutomations(silent: true)
            } else if !automations.isEmpty {
                automations = Self.reconcileAutomations(automations, with: summaries)
            }
        }
    }

    // MARK: - Automations Actions (`UE06` — Native Antigravity 2.0 Sidecars)

    internal static func formatAutomationError(_ error: Error, isCloudRelay: Bool = true) -> String {
        if let rpcErr = error as? AntigravityRPCError {
            switch rpcErr {
            case .unauthorized:
                if isCloudRelay {
                    return "Google 登录会话已过期，请点击下方重新登录。"
                }
                return "宿主机鉴权失败，请检查配对 Token 或重新配对。"
            case .httpError(let code, let body):
                let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty {
                    return "Host rejected request (HTTP \(code))."
                }
                return "Host error (\(code)): \(String(cleaned.prefix(160)))"
            case .invalidEndpoint:
                return "Host endpoint is unavailable."
            case .decodingError(let msg):
                return "Invalid response from host: \(msg)"
            case .interactionRejected:
                return "Automation action was rejected by host."
            }
        }
        return error.localizedDescription
    }

    internal func recordAutomationError(_ error: Error, silent: Bool = false) {
        let isRelay = (activeHost.channel == .cloudRelay)
        if case AntigravityRPCError.unauthorized = error {
            isAutomationsAuthExpired = true
            connectionStatusText = isRelay ? "Google Sign-In Expired" : "Offline · \(activeHost.hostname) (Auth Expired)"
            automationsErrorText = Self.formatAutomationError(error, isCloudRelay: isRelay)
            return
        }
        if !silent || automations.isEmpty {
            automationsErrorText = Self.formatAutomationError(error, isCloudRelay: isRelay)
        }
    }

    /// Reconciles live Cascade summary state (`running`, `waiting`, `error`, `done`) onto Automations
    /// whose latest `GetSidecarEvents` payload references a `lastRunCascadeId`.
    public static func reconcileAutomations(
        _ items: [AutomationItem],
        with summaries: [CascadeSummary]
    ) -> [AutomationItem] {
        guard !items.isEmpty, !summaries.isEmpty else { return items }
        var byCascadeId: [String: CascadeSummary] = [:]
        for summary in summaries {
            byCascadeId[summary.cascadeId] = summary
        }
        return items.map { raw in
            var copy = raw
            guard let cid = copy.lastRunCascadeId, let summary = byCascadeId[cid] else {
                return copy
            }
            switch summary.status {
            case .inProgress, .pending:
                copy.isRunningNow = true
                copy.needsReview = false
                copy.lastRunText = "Running · \(summary.relativeTimeLabel)"
            case .waiting, .blocked:
                copy.isRunningNow = false
                copy.needsReview = true
                copy.lastRunText = "Needs review · \(summary.relativeTimeLabel)"
            case .error:
                copy.isRunningNow = false
                copy.needsReview = true
                let lower = copy.lastRunText.lowercased()
                if !lower.hasPrefix("failed") && !lower.hasPrefix("error") {
                    copy.lastRunText = "Failed · \(summary.relativeTimeLabel)"
                }
            case .done:
                copy.isRunningNow = false
                if copy.lastRunText.lowercased().hasPrefix("running") {
                    copy.lastRunText = "Succeeded · \(summary.relativeTimeLabel)"
                }
            case .unspecified, .cancelled:
                copy.isRunningNow = false
            }
            return copy
        }
    }

    internal func preferredLocalAutomationProjectSlug() -> String {
        if let selected = selectedProject, selected.runtime != .cloud, !selected.isNoProject {
            return selected.name
        }
        if let firstLocal = projects.first(where: { $0.runtime != .cloud && !$0.isNoProject }) {
            return firstLocal.name
        }
        if hasPairedBackend || isLiveBackendConnected {
            return "This Computer"
        }
        return selectedProject?.id ?? "ledger-svc"
    }

    /// Refreshes native Antigravity 2.0 Automations via `GetSidecars` + `GetSidecarEvents`.
    public func refreshAutomations(silent: Bool = false) async {
        if isVerificationMode && !isLiveBackendConnected {
            return
        }
        guard !isNetworkingSuspended, isDeviceNetworkReachable else {
            return
        }
        guard let client = rpcClient, (hasPairedBackend || isLiveBackendConnected) else {
            return
        }
        if !silent {
            isLoadingAutomations = true
        }
        defer {
            if !silent {
                isLoadingAutomations = false
            }
        }
        do {
            let remote = try await client.listAutomations()
            let reconciled = Self.reconcileAutomations(remote, with: summaries)
            automations = reconciled
            automationsErrorText = nil
            isAutomationsAuthExpired = false
            lastAutomationsSyncAt = Date()
            await projectionStore.saveAutomations(reconciled)
        } catch {
            recordAutomationError(error, silent: silent)
        }
    }

    @discardableResult
    public func createAutomationFromPrompt(_ prompt: String = "") -> AutomationItem? {
        let raw = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? automationPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            : prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let parsed = AutomationScheduleCodec.parseNaturalLanguagePrompt(raw)
        let slug = preferredLocalAutomationProjectSlug()
        let optimisticId = parsed.sidecarId
        let item = AutomationItem(
            id: optimisticId,
            title: parsed.displayName,
            projectSlug: slug,
            scheduleSummary: "\(slug) · \(parsed.humanScheduleLabel) · Flash",
            section: .scheduled,
            nextRunText: AutomationScheduleCodec.nextFireDescription(from: parsed.cronExpression),
            lastRunText: (hasPairedBackend || isLiveBackendConnected) ? "Creating..." : "Created just now",
            needsReview: false,
            isRunningNow: false,
            descriptionText: "\(parsed.humanScheduleLabel): \(parsed.prompt)",
            prompt: parsed.prompt,
            cronExpression: parsed.cronExpression,
            projectId: nil,
            allProjects: slug == "All projects",
            modelLabel: "Flash",
            isEnabled: true,
            isScheduleBuiltin: true
        )
        automations.insert(item, at: 0)
        automationPromptDraft = ""
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        if isLive {
            isMutatingAutomation = true
        }

        Task { [weak self] in
            if !isLive {
                await storeRef.saveAutomations(snapshot)
                return
            }
            defer {
                self?.isMutatingAutomation = false
            }
            guard let clientRef else { return }
            do {
                let created = try await clientRef.createAutomation(
                    displayName: parsed.displayName,
                    prompt: parsed.prompt,
                    cronExpression: parsed.cronExpression,
                    projectSlug: slug,
                    projectId: nil,
                    allProjects: slug == "All projects",
                    modelArg: nil,
                    description: "\(parsed.humanScheduleLabel): \(parsed.prompt)",
                    enableImmediately: true
                )
                guard let self else { return }
                if let idx = self.automations.firstIndex(where: { $0.id == optimisticId }) {
                    self.automations[idx] = created
                } else {
                    self.automations.insert(created, at: 0)
                }
                self.automationsErrorText = nil
                await storeRef.saveAutomations(self.automations)
                await self.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                self.automations.removeAll { $0.id == optimisticId }
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
        return item
    }

    /// Creates a structured scheduled Automation via native `ManageSidecar(SIDECAR_ACTION_CREATE)`.
    @discardableResult
    public func createAutomation(
        displayName: String,
        prompt: String,
        cronExpression: String,
        projectSlug: String,
        projectId: String? = nil,
        allProjects: Bool = false,
        modelArg: String? = nil,
        description: String = "",
        enableImmediately: Bool = true
    ) async -> Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCron = cronExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty, !trimmedCron.isEmpty else {
            automationsErrorText = "Please enter a name, schedule, and prompt."
            return false
        }

        automationsErrorText = nil
        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        if !isLive {
            let humanSched = AutomationScheduleCodec.humanReadableSchedule(from: trimmedCron)
            let modelBadge = AutomationScheduleCodec.formatModelBadge(modelArg ?? "Flash")
            let slugLabel = projectSlug.isEmpty ? (allProjects ? "All projects" : "This Computer") : projectSlug
            let localItem = AutomationItem(
                id: AutomationScheduleCodec.makeSidecarId(from: trimmedName),
                title: trimmedName,
                projectSlug: slugLabel,
                scheduleSummary: "\(slugLabel) · \(humanSched) · \(modelBadge)",
                section: enableImmediately ? .scheduled : .paused,
                nextRunText: enableImmediately ? AutomationScheduleCodec.nextFireDescription(from: trimmedCron) : "Paused",
                lastRunText: enableImmediately ? "Created just now" : "Paused · New",
                descriptionText: description,
                prompt: trimmedPrompt,
                cronExpression: trimmedCron,
                projectId: projectId,
                allProjects: allProjects,
                modelLabel: modelBadge,
                isEnabled: enableImmediately,
                isScheduleBuiltin: true
            )
            automations.insert(localItem, at: 0)
            await projectionStore.saveAutomations(automations)
            return true
        }

        guard let client = rpcClient else { return false }
        isMutatingAutomation = true
        defer { isMutatingAutomation = false }

        do {
            let created = try await client.createAutomation(
                displayName: trimmedName,
                prompt: trimmedPrompt,
                cronExpression: trimmedCron,
                projectSlug: projectSlug,
                projectId: projectId,
                allProjects: allProjects,
                modelArg: modelArg,
                description: description,
                enableImmediately: enableImmediately
            )
            automations.removeAll { $0.id == created.id }
            automations.insert(created, at: 0)
            automationsErrorText = nil
            await projectionStore.saveAutomations(automations)
            await refreshAutomations(silent: true)
            return true
        } catch {
            recordAutomationError(error)
            return false
        }
    }

    /// Updates an existing scheduled Automation via `ManageSidecar(SIDECAR_ACTION_UPDATE)`.
    @discardableResult
    public func updateAutomation(
        automationId: String,
        displayName: String,
        prompt: String,
        cronExpression: String,
        projectSlug: String,
        projectId: String? = nil,
        allProjects: Bool = false,
        modelArg: String? = nil,
        description: String = ""
    ) async -> Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCron = cronExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty, !trimmedCron.isEmpty else {
            automationsErrorText = "Please enter a name, schedule, and prompt."
            return false
        }

        automationsErrorText = nil
        let existing = automations.first(where: { $0.id == automationId })
        let originUuid = existing?.originInstanceUuid
        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil

        if isLive, let client = rpcClient {
            isMutatingAutomation = true
            defer { isMutatingAutomation = false }
            do {
                try await client.updateAutomation(
                    automationId: automationId,
                    displayName: trimmedName,
                    prompt: trimmedPrompt,
                    cronExpression: trimmedCron,
                    projectSlug: projectSlug,
                    projectId: projectId,
                    allProjects: allProjects,
                    modelArg: modelArg,
                    description: description,
                    instanceUuidOverride: originUuid
                )
            } catch {
                recordAutomationError(error)
                return false
            }
        }

        if let idx = automations.firstIndex(where: { $0.id == automationId }) {
            let humanSched = AutomationScheduleCodec.humanReadableSchedule(from: trimmedCron)
            let modelBadge = AutomationScheduleCodec.formatModelBadge(modelArg ?? automations[idx].modelLabel ?? "Flash")
            let slugLabel = projectSlug.isEmpty ? (allProjects ? "All projects" : "This Computer") : projectSlug
            automations[idx].title = trimmedName
            automations[idx].prompt = trimmedPrompt
            automations[idx].cronExpression = trimmedCron
            automations[idx].descriptionText = description
            automations[idx].projectSlug = slugLabel
            automations[idx].projectId = projectId
            automations[idx].allProjects = allProjects
            automations[idx].modelLabel = modelBadge
            automations[idx].scheduleSummary = "\(slugLabel) · \(humanSched) · \(modelBadge)"
            if automations[idx].section == .scheduled {
                automations[idx].nextRunText = AutomationScheduleCodec.nextFireDescription(from: trimmedCron)
            }
        }
        await projectionStore.saveAutomations(automations)
        if isLive {
            await refreshAutomations(silent: true)
        }
        return true
    }

    public func triggerAutomationNow(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let previous = automations[idx]
        automations[idx].isRunningNow = true
        automations[idx].needsReview = false
        automations[idx].lastRunText = "Running now..."
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        let originUuid = previous.originInstanceUuid
        let entry = OutboxEntry(cascadeId: automationId, kind: .automationTrigger, messageText: "ManageSidecar:RUN_NOW")

        Task { [weak self] in
            await storeRef.enqueueOutbox(entry)
            await storeRef.saveAutomations(snapshot)
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.triggerAutomationNow(
                    automationId: automationId,
                    instanceUuidOverride: originUuid
                )
                await storeRef.removeOutboxEntry(id: entry.id)
                // Follow up briefly so newly spawned conversation links to `lastRunCascadeId`.
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                await self?.refreshAutomations(silent: true)
                await self?.refreshWorkspacesAndSummaries()
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                await self?.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                await storeRef.removeOutboxEntry(id: entry.id)
                if let currentIdx = self.automations.firstIndex(where: { $0.id == automationId }) {
                    self.automations[currentIdx] = previous
                }
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
    }

    public func pauseAutomation(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let previous = automations[idx]
        automations[idx].section = .paused
        automations[idx].isEnabled = false
        automations[idx].isRunningNow = false
        automations[idx].nextRunText = "Paused"
        automations[idx].lastRunText = "Paused · just now"
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        let originUuid = previous.originInstanceUuid

        Task { [weak self] in
            await storeRef.saveAutomations(snapshot)
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.setAutomationPaused(
                    automationId: automationId,
                    isPaused: true,
                    instanceUuidOverride: originUuid
                )
                await self?.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                if let currentIdx = self.automations.firstIndex(where: { $0.id == automationId }) {
                    self.automations[currentIdx] = previous
                }
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
    }

    public func resumeAutomation(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let previous = automations[idx]
        let targetSection: AutomationSectionKind = previous.isScheduleBuiltin ? .scheduled : .alwaysOn
        automations[idx].section = targetSection
        automations[idx].isEnabled = true
        if targetSection == .scheduled {
            automations[idx].nextRunText = previous.cronExpression.isEmpty
                ? "Tomorrow, 08:00"
                : AutomationScheduleCodec.nextFireDescription(from: previous.cronExpression)
        } else {
            automations[idx].nextRunText = "Listening"
        }
        automations[idx].lastRunText = "Resumed · just now"
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        let originUuid = previous.originInstanceUuid

        Task { [weak self] in
            await storeRef.saveAutomations(snapshot)
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.setAutomationPaused(
                    automationId: automationId,
                    isPaused: false,
                    instanceUuidOverride: originUuid
                )
                await self?.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                if let currentIdx = self.automations.firstIndex(where: { $0.id == automationId }) {
                    self.automations[currentIdx] = previous
                }
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
    }

    public func deleteAutomation(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let removed = automations.remove(at: idx)
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        let originUuid = removed.originInstanceUuid

        Task { [weak self] in
            await storeRef.saveAutomations(snapshot)
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.deleteAutomation(
                    automationId: automationId,
                    instanceUuidOverride: originUuid
                )
                await self?.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                let insertIdx = min(idx, self.automations.count)
                self.automations.insert(removed, at: insertIdx)
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
    }

    public var selectedAutomation: AutomationItem? {
        automations.first(where: { $0.id == selectedAutomationId }) ?? automations.first
    }

    public func openAutomationDetail(_ automationId: String) {
        selectedAutomationId = automationId
        isSidebarPresented = false
        activeRoute = .automationDetail(automationId)
    }

    public func openAutomationEdit(_ automationId: String) {
        selectedAutomationId = automationId
        presentedSheet = .automationEdit(automationId: automationId)
    }

    public func retryAutomationRun(automationId: String, runId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        if let runIdx = automations[idx].recentRuns.firstIndex(where: { $0.id == runId }) {
            automations[idx].recentRuns[runIdx].status = .running
            automations[idx].recentRuns[runIdx].relativeTimeLabel = "now"
            automations[idx].recentRuns[runIdx].summaryText = "Retrying run..."
        }
        triggerAutomationNow(automationId)
    }

    public func restartAutomation(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let originUuid = automations[idx].originInstanceUuid
        automations[idx].lastRunText = "Restarting..."
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let clientRef = rpcClient
        Task { [weak self] in
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.restartAutomation(
                    automationId: automationId,
                    instanceUuidOverride: originUuid
                )
                await self?.refreshAutomations(silent: true)
            } catch {
                self?.recordAutomationError(error)
            }
        }
    }

    /// Opens an unsent draft composer pre-filled with the `/automation` workflow chip and editable guided prompt,
    /// matching Antigravity Desktop's "Create with Prompt" flow.
    /// Does NOT call `StartCascade`, does NOT auto-send, and does NOT add an entry to `summaries` until the user taps Send.
    public func openAutomationPromptDraft(prompt: String = "", projectSlug: String? = nil) {
        let trimmedRaw = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedBody: String = {
            if trimmedRaw.lowercased() == "/automation" {
                return ""
            }
            if trimmedRaw.lowercased().hasPrefix("/automation ") {
                return String(trimmedRaw.dropFirst("/automation ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmedRaw
        }()
        let initialBody = strippedBody.isEmpty ? Self.defaultAutomationGuidedPrompt : strippedBody
        let targetSlug: String = {
            if let explicit = projectSlug,
               !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let match = projects.first(where: { ($0.id == explicit || $0.name == explicit) && $0.runtime != .cloud }) {
                return match.id
            }
            return AntigravityCloudDetector.noProjectDisplayName
        }()
        let workspaceUri: String = {
            if AntigravityCloudDetector.isNoProjectSlug(targetSlug) {
                return ""
            }
            return projects.first(where: { $0.id == targetSlug || $0.name == targetSlug })?.workspaceUri ?? ""
        }()

        stepPollingTask?.cancel()
        stepPollingTask = nil
        isLoadingSteps = false
        stepLoadErrorText = nil

        pendingDraftConversation = PendingDraftConversation(
            title: "New Automation",
            projectSlug: targetSlug,
            isCloud: false,
            workflowCommand: "/automation",
            defaultGuidedPrompt: Self.defaultAutomationGuidedPrompt
        )
        activeCascadeId = ""
        selectedProjectId = targetSlug
        selectedWorkspaceUri = workspaceUri
        composerWorkflowCommand = "/automation"
        composerDraftText = initialBody
        composerAttachments.removeAll()
        isSlashPopupDismissedManually = true
        activeRoute = .cascadeChat("")
    }

    /// Discards an unsent draft conversation (e.g., tapping Back before sending) without creating any backend session.
    public func discardPendingDraftConversation() {
        guard pendingDraftConversation != nil else { return }
        pendingDraftConversation = nil
        composerWorkflowCommand = nil
        composerDraftText = ""
        composerAttachments.removeAll()
        isSlashPopupDismissedManually = false
    }

    /// Updates the target project for an unsent draft conversation (matching PC's `No Project ⌄` picker).
    public func updatePendingDraftProject(_ projectSlug: String) {
        guard var draft = pendingDraftConversation else { return }
        let trimmed = projectSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.projectSlug = trimmed.isEmpty ? AntigravityCloudDetector.noProjectDisplayName : trimmed
        if let proj = projects.first(where: { $0.id == draft.projectSlug || $0.name == draft.projectSlug }),
           !proj.isNoProject {
            draft.isCloud = (proj.runtime == .cloud)
            selectedWorkspaceUri = proj.workspaceUri
        } else {
            draft.isCloud = false
            selectedWorkspaceUri = ""
        }
        pendingDraftConversation = draft
        selectedProjectId = draft.projectSlug
    }

    /// Backwards-compatible alias that opens the interactive `/automation` prompt draft without auto-sending.
    public func createAutomationWithAgent(prompt: String = "", projectSlug: String? = nil) {
        openAutomationPromptDraft(prompt: prompt, projectSlug: projectSlug)
    }

}
