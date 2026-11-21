import Foundation

/// Project workspace creation, scoped conversations, and Antigravity 2.0 native Automations sidecars.
extension AntigravitySessionStore {
    // MARK: - Project Creation & Scoped Conversation Actions (`UE04`, `UE05`)

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
        activeRoute = .projectDetail(created.id)

        let projectsSnapshot = projects
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task { [weak self] in
            await storeRef.saveProjects(projectsSnapshot)
            if let remoteCreated = try? await clientRef?.createProjectWorkspace(draft: draft),
               let self,
               let idx = self.projects.firstIndex(where: { $0.id == slug }) {
                self.projects[idx].cloudProjectId = remoteCreated.cloudProjectId ?? self.projects[idx].cloudProjectId
                self.projects[idx].originInstanceUuid = remoteCreated.originInstanceUuid ?? self.projects[idx].originInstanceUuid
                await storeRef.saveProjects(self.projects)
            }
        }
        return created
    }

    @discardableResult
    public func createConversationInProject(
        _ projectSlug: String,
        title: String = "New Conversation",
        initialPrompt: String? = nil
    ) -> String {
        discardPendingDraftConversation()
        let optimisticId = "cas-\(UUID().uuidString.prefix(8).lowercased())"
        let trimmedSlug = projectSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = projects.first(where: { $0.id == trimmedSlug })
            ?? projects.first(where: { $0.name == trimmedSlug })
        let isUnassigned = (project?.isNoProject == true) || AntigravityCloudDetector.isNoProjectSlug(trimmedSlug)
        let isCloudProj = (project?.runtime == .cloud) || trimmedSlug.lowercased().hasPrefix("cloud:")
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
        let originUuid = project?.originInstanceUuid
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

        let newSummary = CascadeSummary(
            cascadeId: optimisticId,
            title: title,
            projectSlug: effectiveSlug,
            workspaceUri: workspaceUri,
            branchName: branch,
            status: initialPrompt != nil ? .inProgress : .done,
            stepCount: initialPrompt != nil ? 1 : 0,
            currentStepIndex: 1,
            totalSteps: 1,
            updatedAt: Date(),
            relativeTimeLabel: "now",
            statusSubtitle: initialPrompt != nil ? "Running · Step 1 of 1" : "Ready for instructions",
            isPinned: displayOptions.autoPinOnMessage,
            isArchived: false,
            isUnread: false,
            modelLabel: selectedModelConfig.displayName,
            lastMessagePreview: initialPrompt ?? "Ready for instructions...",
            isCloud: isCloudProj,
            cloudProjectId: cloudProjId,
            originInstanceUuid: originUuid,
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
        if initialPrompt == nil || initialPrompt?.isEmpty == true {
            locallyCreatedEmptyCascadeIds.insert(optimisticId)
        }
        activeCascadeId = optimisticId
        selectedProjectId = summaries.first(where: { $0.cascadeId == optimisticId })?.projectSlug ?? effectiveSlug
        selectedWorkspaceUri = workspaceUri
        activeRoute = .cascadeChat(optimisticId)

        let clientRef = rpcClient
        let modelId = selectedModelConfig.modelId
        let shouldCallLiveBackend = (hasPairedBackend || isLiveBackendConnected)

        Task { [weak self] in
            if shouldCallLiveBackend,
               let clientRef,
               let realCascadeId = try? await clientRef.startCascade(
                   workspaceUri: workspaceUri,
                   initialPrompt: initialPrompt ?? "",
                   modelId: modelId,
                   cloudProjectId: cloudProjId,
                   isCloud: isCloudProj,
                   instanceUuidOverride: originUuid
               ),
               !realCascadeId.isEmpty {
                guard let self else { return }
                if self.hasPairedBackend && (!self.isLiveBackendConnected || !self.activeHost.isOnline) {
                    self.markBackendReconnected()
                }
                let wasEmptyNew = self.locallyCreatedEmptyCascadeIds.remove(optimisticId) != nil
                let existingSteps = self.stepsByCascadeId.removeValue(forKey: optimisticId) ?? []
                if wasEmptyNew && existingSteps.isEmpty && (initialPrompt == nil || initialPrompt?.isEmpty == true) {
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
                if let prompt = initialPrompt, !prompt.isEmpty {
                    self.locallyCreatedEmptyCascadeIds.remove(realCascadeId)
                    self.composerDraftText = prompt
                    self.sendCurrentDraft()
                } else {
                    self.syncStepsForCascade(realCascadeId, pollUntilIdle: false)
                }
                return
            }

            if let prompt = initialPrompt, !prompt.isEmpty {
                self?.composerDraftText = prompt
                self?.sendCurrentDraft()
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
            if let selected = selectedProject?.id, !selected.isEmpty {
                return selected
            }
            if hasPairedBackend || isLiveBackendConnected {
                return projects.first?.id ?? AntigravityCloudDetector.noProjectDisplayName
            }
            return "ledger-svc"
        }()
        let newId = createConversationInProject(slug, title: title, initialPrompt: nil)
        if let branchName, let idx = summaries.firstIndex(where: { $0.cascadeId == newId }) {
            summaries[idx].branchName = branchName
        }
        if let initialPrompt, !initialPrompt.isEmpty {
            composerDraftText = initialPrompt
            sendCurrentDraft()
        }
    }

    public func revealProjectInFinder(_ projectSlug: String) {
        guard let project = projects.first(where: { $0.id == projectSlug }),
              !project.workspaceUri.isEmpty else { return }
        let uri = project.workspaceUri
        let clientRef = rpcClient
        Task {
            try? await clientRef?.openWorkspaceInFinder(workspaceUri: uri)
        }
    }

    public func refreshWorkspacesAndSummaries(
        forceFullSync: Bool = false,
        includeAutomations: Bool = false
    ) async {
        guard !isNetworkingSuspended else { return }
        isRefreshingSummaries = true
        defer { isRefreshingSummaries = false }
        guard let client = rpcClient else { return }

        backgroundPollCounter += 1
        let isRelay = (activeHost.channel == .cloudRelay)
        let syncTimeout: TimeInterval = isRelay ? 14.0 : 3.5
        let useLightweight = !forceFullSync && isRelay && (backgroundPollCounter % 4 != 1) && isSummaryStreamHealthy
        do {
            let federated = try await client.fetchFederatedWorkspacesAndSummaries(
                timeoutInterval: syncTimeout,
                lightweightPoll: useLightweight
            )
            consecutiveSyncFailures = 0
            lastBackendActivityAt = Date()
            lastFullSyncAt = Date()
            cloudAgentWarmingUp = federated.cloudWarmingUp

            if isRelay {
                let latestInstances = await client.currentCachedRelayInstances()
                let latestActive = await client.currentActiveRelayInstance()
                if !latestInstances.isEmpty {
                    syncRelayInstancesToHosts(
                        latestInstances,
                        preferredActiveInstance: latestActive
                    )
                }
            }

            let remoteSummaries = federated.summaries
            if !federated.workspaces.isEmpty {
                workspaces = federated.workspaces
            }

            if hasPairedBackend && (!isLiveBackendConnected || !activeHost.isOnline) {
                markBackendReconnected()
            } else if isLiveBackendConnected && activeHost.isOnline {
                connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
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
                    if existing.title != "New Conversation" && copy.title == "New Conversation" {
                        copy.title = existing.title
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

            mergedList.sort { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.cascadeId < rhs.cascadeId
            }

            if hasPairedBackend || isLiveBackendConnected {
                projects = Self.reconcileLiveProjects(
                    workspaces: workspaces,
                    summaries: &mergedList,
                    existingProjects: projects,
                    hostName: activeHost.hostname,
                    cloudProjects: federated.cloudProjects
                )
                summaries = mergedList
                if selectedProjectId.isEmpty || !projects.contains(where: { $0.id == selectedProjectId }) {
                    let defaultProj = projects.first(where: { !$0.isNoProject }) ?? projects.first
                    selectedProjectId = defaultProj?.id ?? ""
                }
                if shouldResyncActiveCascade && !activeCascadeId.isEmpty {
                    syncStepsForCascade(
                        activeCascadeId,
                        pollUntilIdle: activeRoute == .cascadeChat(activeCascadeId)
                    )
                }
                await projectionStore.saveProjects(projects)
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
            await projectionStore.saveProjectedSummaries(summaries)
        } catch {
            if Self.isBackendOfflineError(error) {
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

        if isLiveBackendConnected {
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
        pendingDraftConversation = draft
        selectedProjectId = draft.projectSlug
        if let proj = projects.first(where: { $0.id == draft.projectSlug || $0.name == draft.projectSlug }),
           !proj.isNoProject {
            selectedWorkspaceUri = proj.workspaceUri
        } else {
            selectedWorkspaceUri = ""
        }
    }

    /// Backwards-compatible alias that opens the interactive `/automation` prompt draft without auto-sending.
    public func createAutomationWithAgent(prompt: String = "", projectSlug: String? = nil) {
        openAutomationPromptDraft(prompt: prompt, projectSlug: projectSlug)
    }
}
