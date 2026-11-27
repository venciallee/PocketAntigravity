import Foundation

/// Derived UI projections, navigation, display options, conversation context menu, search, and @mentions.
extension AntigravitySessionStore {
    // MARK: - Computed Properties for Agents Home & Project Hub (`UE01`, `UE02`, `UE04`)

    public var currentWorkspace: WorkspaceInfo? {
        workspaces.first(where: { $0.workspaceUri == selectedWorkspaceUri }) ?? workspaces.first
    }

    public var selectedProject: ProjectWorkspace? {
        projects.first(where: { $0.id == selectedProjectId }) ?? projects.first
    }

    public var availableWorktrees: [String] {
        selectedProject?.worktrees ?? currentWorkspace?.worktrees ?? ["main"]
    }

    /// Distinct paired local Mac/PC hosts (excluding Cloud placeholders and unpaired default).
    public var pairedLocalHosts: [RemoteHostInstance] {
        var seen = Set<String>()
        var result: [RemoteHostInstance] = []
        for host in hosts where host.instanceId != "unpaired" && host.hostname.lowercased() != "cloud" {
            if seen.insert(host.instanceId).inserted {
                result.append(host)
            }
        }
        if result.isEmpty && hasPairedBackend && activeHost.instanceId != "unpaired" {
            result.append(activeHost)
        }
        return result
    }

    /// Evaluates whether a specific local host (by `instanceId` and/or `hostname`) is currently online,
    /// without falsely falling back to a different device's status.
    public func isLocalHostOnline(instanceId: String?, hostname: String?) -> Bool {
        guard isDeviceNetworkReachable else { return false }
        let trimmedId = instanceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedName = hostname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if activeHost.channel == .cloudRelay && !availableRelayInstances.isEmpty {
            if !trimmedId.isEmpty,
               let exact = availableRelayInstances.first(where: { $0.uuid == trimmedId }) {
                return exact.status.isReachable
            }
            if !trimmedName.isEmpty,
               let byName = availableRelayInstances.first(where: { $0.name == trimmedName }) {
                return byName.status.isReachable
            }
            if !trimmedId.isEmpty || !trimmedName.isEmpty {
                return false
            }
            return availableRelayInstances.first(where: { $0.uuid == activeHost.instanceId })?.status.isReachable ?? false
        }

        if !trimmedId.isEmpty,
           let matched = hosts.first(where: { $0.instanceId == trimmedId }) {
            return matched.isOnline && (matched.channel == .cloudRelay || isLiveBackendConnected)
        }
        if !trimmedName.isEmpty,
           let matchedByName = hosts.first(where: { $0.hostname == trimmedName }) {
            return matchedByName.isOnline && (matchedByName.channel == .cloudRelay || isLiveBackendConnected)
        }
        return isLiveBackendConnected && activeHost.isOnline
    }

    /// Evaluates whether the host backing a specific conversation summary is currently online.
    public func isSummaryHostOnline(_ summary: CascadeSummary?) -> Bool {
        guard hasPairedBackend else { return true }
        guard isDeviceNetworkReachable else { return false }
        if let summary, isSummaryCloudRuntime(summary) {
            if activeHost.channel == .cloudRelay && !availableRelayInstances.isEmpty {
                return availableRelayInstances.contains(where: \.status.isReachable)
            }
            return isLiveBackendConnected && activeHost.isOnline
        }
        return isLocalHostOnline(
            instanceId: summary?.originInstanceUuid,
            hostname: summary?.originHostName
        )
    }

    /// Returns `true` when `cascadeId` was newly created locally in this session and has not synced server steps yet.
    public func isLocallyCreatedEmptyCascade(_ cascadeId: String) -> Bool {
        locallyCreatedEmptyCascadeIds.contains(cascadeId)
    }

    /// True while a scoped conversation/workspace refresh is in flight for the currently selected host scope.
    public var isRefreshingSelectedHost: Bool {
        if refreshingHostScopeKeys.contains(selectedHostScope.id) {
            return true
        }
        if case .localHost = selectedHostScope,
           refreshingHostScopeKeys.contains(AgentsHostFilterScope.allHosts.id) {
            return true
        }
        return false
    }

    /// True while a scoped refresh is in flight for the specified local host.
    public func isRefreshingHost(instanceId: String?, hostname: String?) -> Bool {
        let trimmedId = instanceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedId.isEmpty {
            let scopeKey = AgentsHostFilterScope.localHost(id: trimmedId, name: hostname ?? trimmedId).id
            if refreshingHostScopeKeys.contains(scopeKey) {
                return true
            }
        }
        return refreshingHostScopeKeys.contains(AgentsHostFilterScope.allHosts.id)
    }

    /// Evaluates whether a conversation summary belongs to `scope` (defaults to `selectedHostScope`).
    public func summaryMatchesHostScope(
        _ s: CascadeSummary,
        scope: AgentsHostFilterScope? = nil
    ) -> Bool {
        let activeScope = scope ?? selectedHostScope
        switch activeScope {
        case .allHosts:
            return true
        case .antigravityCloud:
            return s.isCloud
        case .localHost(let id, let name):
            guard !s.isCloud else { return false }
            let localHosts = pairedLocalHosts
            if localHosts.count <= 1 {
                if let originId = s.originInstanceUuid, !originId.isEmpty {
                    return originId == id || originId == activeHost.instanceId || s.originHostName == name
                }
                return true
            }
            if let originId = s.originInstanceUuid, !originId.isEmpty {
                if originId == id { return true }
                if let originHost = s.originHostName, !originHost.isEmpty, originHost == name {
                    return true
                }
                return false
            }
            if let originHost = s.originHostName, !originHost.isEmpty {
                return originHost == name
            }
            return activeHost.instanceId == id || activeHost.hostname == name
        }
    }

    /// Evaluates whether a project workspace card belongs to `scope` (defaults to `selectedHostScope`).
    public func projectMatchesHostScope(
        _ proj: ProjectWorkspace,
        scope: AgentsHostFilterScope? = nil
    ) -> Bool {
        let activeScope = scope ?? selectedHostScope
        switch activeScope {
        case .allHosts:
            return true
        case .antigravityCloud:
            return proj.runtime == .cloud
        case .localHost(let id, let name):
            guard proj.runtime != .cloud else { return false }
            let localHosts = pairedLocalHosts
            if localHosts.count <= 1 {
                if let originId = proj.originInstanceUuid, !originId.isEmpty {
                    return originId == id || originId == activeHost.instanceId || proj.hostName == name
                }
                return true
            }
            if let originId = proj.originInstanceUuid, !originId.isEmpty {
                if originId == id { return true }
                if !proj.hostName.isEmpty && proj.hostName == name {
                    return true
                }
                return false
            }
            if !proj.hostName.isEmpty {
                return proj.hostName == name
            }
            return activeHost.instanceId == id || activeHost.hostname == name
        }
    }

    /// Ensures `selectedProjectId` and `selectedWorkspaceUri` point to a repository belonging to
    /// `selectedHostScope` so switching devices immediately updates the composer's selected repository.
    public func reconcileSelectedProjectForCurrentHostScope() {
        let scopedNonEmpty = projects.filter { projectMatchesHostScope($0) && !$0.isNoProject }
        if let current = scopedNonEmpty.first(where: { $0.id == selectedProjectId }) {
            if selectedWorkspaceUri != current.workspaceUri {
                selectedWorkspaceUri = current.workspaceUri
            }
            return
        }
        if let preferred = scopedNonEmpty.first {
            selectedProjectId = preferred.id
            selectedWorkspaceUri = preferred.workspaceUri
            return
        }
        if let fallbackScoped = projects.first(where: { projectMatchesHostScope($0) }) {
            selectedProjectId = fallbackScoped.id
            selectedWorkspaceUri = fallbackScoped.workspaceUri
            return
        }
        if hasPairedBackend || isLiveBackendConnected {
            selectedProjectId = ""
            selectedWorkspaceUri = ""
        }
    }

    public func runningCount(for scope: AgentsHostFilterScope) -> Int {
        summaries.filter {
            !$0.isArchived && summaryMatchesHostScope($0, scope: scope) && ($0.status == .inProgress || $0.status == .pending)
        }.count
    }

    public func needsYouCount(for scope: AgentsHostFilterScope) -> Int {
        summaries.filter {
            !$0.isArchived && summaryMatchesHostScope($0, scope: scope) && ($0.status == .waiting || $0.status == .blocked)
        }.count
    }

    public func unreadCount(for scope: AgentsHostFilterScope) -> Int {
        summaries.filter {
            !$0.isArchived && summaryMatchesHostScope($0, scope: scope) && $0.isUnread
        }.count
    }

    public var runningCount: Int {
        runningCount(for: selectedHostScope)
    }

    public var runningCascadeCount: Int { runningCount }

    public var needsYouCount: Int {
        needsYouCount(for: selectedHostScope)
    }

    public var waitingApprovalCount: Int { needsYouCount }

    public var unreadCount: Int {
        unreadCount(for: selectedHostScope)
    }

    internal func persistSelectedHostScope() {
        guard !isVerificationMode else { return }
        if let data = try? JSONEncoder().encode(selectedHostScope),
           let json = String(data: data, encoding: .utf8) {
            preferencesStore.set(json, forKey: Self.selectedHostScopeDefaultsKey)
        }
    }

    internal func loadPersistedSelectedHostScope() -> AgentsHostFilterScope? {
        guard !isVerificationMode,
              let raw = preferencesStore.string(forKey: Self.selectedHostScopeDefaultsKey),
              let decoded = try? JSONDecoder().decode(AgentsHostFilterScope.self, from: Data(raw.utf8)) else {
            return nil
        }
        return decoded
    }

    internal func reconcileSelectedHostScopeWithHosts() {
        guard case .localHost(let selectedId, let selectedName) = selectedHostScope else { return }
        if let exact = hosts.first(where: { $0.instanceId == selectedId }) {
            if exact.hostname != selectedName {
                selectedHostScope = .localHost(id: exact.instanceId, name: exact.hostname)
            }
            return
        }
        if let byName = hosts.first(where: { $0.hostname == selectedName }) {
            selectedHostScope = .localHost(id: byName.instanceId, name: byName.hostname)
            return
        }
        if let familyOnline = availableRelayInstances.first(where: {
            $0.status.isReachable && $0.sameHostFamily(as: selectedName)
        }) {
            selectedHostScope = .localHost(id: familyOnline.uuid, name: familyOnline.name)
        }
    }

    /// Filtered and sorted conversation summaries driven by `quickFilter`, `displayOptions`, and `searchQuery`.
    public var filteredSummaries: [CascadeSummary] {
        summaries
            .filter { summary in
                if displayOptions.archivedOnly {
                    if !summary.isArchived { return false }
                } else {
                    if summary.isArchived { return false }
                }
                if let branch = selectedWorktreeFilter, !branch.isEmpty, summary.branchName != branch {
                    return false
                }
                switch quickFilter {
                case .all:
                    break
                case .running:
                    if summary.status != .inProgress && summary.status != .pending { return false }
                case .needsYou:
                    if summary.status != .waiting && summary.status != .blocked { return false }
                case .unread:
                    if !summary.isUnread { return false }
                }
                switch selectedFilterCategory {
                case .all:
                    break
                case .waitingApproval:
                    if summary.status != .waiting && summary.status != .blocked { return false }
                case .running:
                    if summary.status != .inProgress && summary.status != .pending { return false }
                case .pinned:
                    if !summary.isPinned { return false }
                case .done:
                    if summary.status != .done { return false }
                }
                let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !q.isEmpty {
                    let matchesTitle = summary.title.lowercased().contains(q)
                    let matchesProject = summary.projectSlug.lowercased().contains(q)
                    let matchesSubtitle = summary.statusSubtitle.lowercased().contains(q)
                    let matchesBranch = summary.branchName.lowercased().contains(q)
                    let matchesPreview = (summary.lastMessagePreview ?? "").lowercased().contains(q)
                    return matchesTitle || matchesProject || matchesSubtitle || matchesBranch || matchesPreview
                }
                return true
            }
            .sorted { lhs, rhs in
                switch displayOptions.sortBy {
                case .title:
                    let cmp = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    return displayOptions.newestFirst ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
                case .lastUpdated, .dateCreated:
                    return displayOptions.newestFirst ? (lhs.updatedAt > rhs.updatedAt) : (lhs.updatedAt < rhs.updatedAt)
                }
            }
    }

    public var pinnedSummaries: [CascadeSummary] {
        filteredSummaries.filter { $0.isPinned }
    }

    public var unpinnedSummaries: [CascadeSummary] {
        filteredSummaries.filter { !$0.isPinned }
    }

    public func unpinnedSummaries(forProject projectSlug: String) -> [CascadeSummary] {
        unpinnedSummaries.filter { $0.projectSlug == projectSlug }
    }

    public func activeSummaries(forProject projectSlug: String) -> [CascadeSummary] {
        summaries.filter { $0.projectSlug == projectSlug && !$0.isArchived }
    }

    public func archivedSummaries(forProject projectSlug: String) -> [CascadeSummary] {
        summaries.filter { $0.projectSlug == projectSlug && $0.isArchived }
    }

    public func totalConversationCount(forProject projectSlug: String) -> Int {
        summaries.filter { $0.projectSlug == projectSlug }.count
    }

    public func automations(forProject projectSlug: String) -> [AutomationItem] {
        automations.filter { $0.projectSlug == projectSlug }
    }

    public var filteredGitHubRepos: [GitHubRepoItem] {
        let q = newProjectDraft.repoSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return availableGitHubRepos }
        return availableGitHubRepos.filter {
            $0.fullName.lowercased().contains(q) || $0.visibilityLabel.lowercased().contains(q)
        }
    }

    // MARK: - Computed Properties for Automations & Context (`UE06`, `UE08`)

    public var scheduledAutomations: [AutomationItem] {
        automations.filter { $0.section == .scheduled }
    }

    public var alwaysOnAutomations: [AutomationItem] {
        automations.filter { $0.section == .alwaysOn }
    }

    public var pausedAutomations: [AutomationItem] {
        automations.filter { $0.section == .paused }
    }

    public var filteredContextCandidates: [ContextCandidateItem] {
        let q = contextSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return contextCandidates.filter { item in
            if let cat = selectedContextCategoryFilter, item.category != cat {
                return false
            }
            if !q.isEmpty {
                return item.title.lowercased().contains(q) || item.subtitle.lowercased().contains(q)
            }
            return true
        }
    }

    public var selectedContextCount: Int {
        contextCandidates.filter { $0.isSelected }.count
    }

    // MARK: - Computed Properties for Active Chat, Question, Plan & Diff (`UE07`, `UE10`, `UE11`, `UE12`)

    public var activeSummary: CascadeSummary? {
        summaries.first(where: { $0.cascadeId == activeCascadeId })
    }

    public var contextMenuTargetSummary: CascadeSummary? {
        summaries.first(where: { $0.cascadeId == contextMenuTargetCascadeId }) ?? summaries.first
    }

    public var activeSteps: [CascadeStep] {
        get { stepsByCascadeId[activeCascadeId] ?? [] }
        set { stepsByCascadeId[activeCascadeId] = newValue }
    }

    public var displayItems: [CascadeDisplayItem] {
        let cid = activeCascadeId
        let steps = stepsByCascadeId[cid] ?? []
        if let cached = displayItemsCacheByCascadeId[cid] {
            return cached
        }
        let built = CascadeDisplayItem.buildDisplayItems(from: steps)
        displayItemsCacheByCascadeId[cid] = built
        return built
    }

    public var activeTaskBoundary: TaskBoundaryPayload? {
        activeSteps.last(where: { $0.type == .taskBoundary })?.taskBoundary
    }

    public var pendingWaitingStep: CascadeStep? {
        activeSteps.last(where: { $0.isWaitingForUser })
    }

    public func waitingStep(at stepIndex: Int?) -> CascadeStep? {
        if let stepIndex,
           let matched = activeSteps.first(where: { $0.stepIndex == stepIndex && $0.isWaitingForUser }) {
            return matched
        }
        return pendingWaitingStep
    }

    public var isCascadeStreaming: Bool {
        if let summary = activeSummary {
            if summary.status == .pending {
                if !isSummaryHostOnline(summary)
                    || activeSteps.isEmpty
                    || activeSteps.contains(where: \.isQueuedInOutbox) {
                    return false
                }
                return true
            }
            if summary.status == .inProgress {
                if hasPairedBackend && !isSummaryHostOnline(summary) {
                    return false
                }
                return !activeSteps.isEmpty
            }
        }
        return activeSteps.contains(where: { $0.status == .inProgress || ($0.status == .pending && !$0.isQueuedInOutbox) })
    }

    public var currentQuestionStep: StructuredQuestionStepItem? {
        guard questionSteps.indices.contains(activeQuestionStepIndex) else { return questionSteps.first }
        return questionSteps[activeQuestionStepIndex]
    }

    public var currentDiffFile: FilePatchDiff? {
        guard !activeTurnDiffs.isEmpty else { return nil }
        let clamped = min(max(0, selectedDiffFileIndex), activeTurnDiffs.count - 1)
        return activeTurnDiffs[clamped]
    }

    public var selectedDiffFilePath: String {
        get { currentDiffFile?.filePath ?? "middleware/ratelimit.go" }
        set {
            if let idx = activeTurnDiffs.firstIndex(where: { $0.filePath == newValue }) {
                selectedDiffFileIndex = idx
            }
        }
    }

    public var totalDiffAdditions: Int {
        let sum = activeTurnDiffs.reduce(0) { $0 + $1.additions }
        if sum > 0 { return sum }
        let stepSum = activeSteps.compactMap(\.codeAction).reduce(0) { $0 + $1.additions }
        if stepSum > 0 { return stepSum }
        if isLiveBackendConnected {
            return activeSummary?.totalAdditions ?? 0
        }
        return activeSummary?.totalAdditions ?? 128
    }

    public var totalDiffDeletions: Int {
        let sum = activeTurnDiffs.reduce(0) { $0 + $1.deletions }
        if sum > 0 { return sum }
        let stepSum = activeSteps.compactMap(\.codeAction).reduce(0) { $0 + $1.deletions }
        if stepSum > 0 { return stepSum }
        if isLiveBackendConnected {
            return activeSummary?.totalDeletions ?? 0
        }
        return activeSummary?.totalDeletions ?? 14
    }

    // MARK: - Composer Suggestions (`UE07`)

    public var activeSlashCommandSuggestions: [SlashCommandItem] {
        guard !isSlashPopupDismissedManually else { return [] }
        let trimmed = composerDraftText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        let token = String(trimmed.split(separator: " ").first ?? Substring(trimmed)).lowercased()
        if token == "/" {
            return SlashCommandItem.allCommands
        }
        return SlashCommandItem.allCommands.filter {
            $0.command.lowercased().hasPrefix(token) || $0.title.lowercased().contains(token.dropFirst())
        }
    }

    public var activeFileMentionSuggestions: [String] {
        guard let lastWord = composerDraftText.split(separator: " ").last,
              lastWord.hasPrefix("@") else {
            return []
        }
        let query = String(lastWord.dropFirst()).lowercased()
        let files = currentWorkspace?.indexedFiles ?? [
            "internal/middleware/ratelimit.go",
            "internal/router/transfers.go",
            "internal/settlement/batch.go",
            "internal/settlement/settlement_test.go",
            "load/transfers.txt"
        ]
        if query.isEmpty { return Array(files.prefix(5)) }
        return files.filter { $0.lowercased().contains(query) }
    }

    public var canSendCurrentDraft: Bool {
        !composerDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !composerAttachments.isEmpty
            || !(composerWorkflowCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }


    // MARK: - Navigation & Display Options Actions (`UE01`, `UE02`)

    /// Refreshes the Cloud Relay host roster (`AVAILABLE HOSTS`) and optionally probes every reported-online
    /// instance end-to-end via `GetWorkspaceInfos` (`allowCrossHostFailover: false`) so stale/zombie Relay entries
    /// (such as a Mac that recently closed or slept) are truthfully marked Offline.
    public func refreshAvailableRelayHosts(verifyEndToEnd: Bool = true) async {
        guard !isVerificationMode, !isNetworkingSuspended, isDeviceNetworkReachable else { return }
        guard activeHost.channel == .cloudRelay, (kmpEngine != nil || rpcClient != nil) else { return }
        guard !isRefreshingRelayHosts else { return }

        isRefreshingRelayHosts = true
        defer { isRefreshingRelayHosts = false }

        let generation = hostSwitchGeneration
        let allowCrossHostFallback = (selectedHostScope == .allHosts || selectedHostScope == .antigravityCloud)
        let wasOfflineBeforeProbe = !isLiveBackendConnected || !activeHost.isOnline
        do {
            let probe: HostReachabilityProbeResult
            if let kmpEngine {
                probe = try await kmpEngine.probeHostReachability(
                    allowCrossHostFallback: allowCrossHostFallback,
                    verifyEndToEnd: verifyEndToEnd
                )
            } else if let client = rpcClient {
                probe = try await client.probeHostReachability(
                    timeoutInterval: 8.0,
                    allowCrossHostFallback: allowCrossHostFallback,
                    verifyEndToEnd: verifyEndToEnd
                )
            } else {
                return
            }
            if generation != hostSwitchGeneration {
                if !probe.availableRelayInstances.isEmpty {
                    syncRelayInstancesToHosts(
                        probe.availableRelayInstances,
                        latencyMs: probe.latencyMs,
                        preferredActiveInstance: nil
                    )
                }
                return
            }
            let currentAllowCrossHost = (selectedHostScope == .allHosts || selectedHostScope == .antigravityCloud)
            applyRelayProbeMetadata(probe, allowCrossHostFallback: currentAllowCrossHost)
            if probe.isSelectedHostOnline && activeHost.isOnline {
                if wasOfflineBeforeProbe {
                    markBackendReconnected(forceReconnectedActions: true)
                }
            } else {
                let hasReachablePeers = probe.availableRelayInstances.contains(where: \.status.isReachable)
                markBackendOffline(
                    error: AntigravityRPCError.httpError(
                        statusCode: 503,
                        body: "\(activeHost.hostname) is offline"
                    ),
                    preservePeerOnlineStates: hasReachablePeers
                )
            }
            let localHostsSnapshot = pairedLocalHosts
            if !localHostsSnapshot.isEmpty {
                await projectionStore.saveKnownHosts(localHostsSnapshot)
            }
        } catch {
            guard generation == hostSwitchGeneration else { return }
            if Self.isBackendOfflineError(error) {
                if let client = rpcClient {
                    let latestInstances = await client.currentCachedRelayInstances()
                    if !latestInstances.isEmpty {
                        let downgraded = latestInstances.map { $0.withStatus(.disconnected) }
                        syncRelayInstancesToHosts(downgraded, latencyMs: nil)
                    }
                }
                markBackendOffline(error: error)
            }
        }
    }

    @discardableResult
    internal func ensureInFlightHostRefreshTask(
        _ scope: AgentsHostFilterScope,
        forceFullSync: Bool = false
    ) -> Task<Bool, Never> {
        let key = scope.id
        if let existingTask = inFlightHostRefreshTasks[key] {
            return existingTask
        }

        refreshingHostScopeKeys.insert(key)
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            let ok = await self.executeScopedHostRefresh(scope, forceFullSync: forceFullSync)
            self.inFlightHostRefreshTasks.removeValue(forKey: key)
            self.refreshingHostScopeKeys.remove(key)
            return ok
        }
        inFlightHostRefreshTasks[key] = task
        return task
    }

    /// Triggers a scoped conversation & workspace refresh for `scope`, coalescing concurrent requests targeting
    /// the exact same device/scope (`scope.id`) into a single in-flight network request while allowing independent
    /// devices to finish cleanly without cancelling each other or overwriting offline hosts' cached projections.
    @discardableResult
    public func refreshConversationsForHostScope(
        _ scope: AgentsHostFilterScope,
        forceFullSync: Bool = false
    ) async -> Bool {
        let task = ensureInFlightHostRefreshTask(scope, forceFullSync: forceFullSync)
        return await task.value
    }

    internal func executeScopedHostRefresh(
        _ scope: AgentsHostFilterScope,
        forceFullSync: Bool
    ) async -> Bool {
        guard !isNetworkingSuspended else { return false }
        guard hostRefreshExecutorOverrideForTesting != nil || isDeviceNetworkReachable else { return false }

        do {
            let result: ScopedWorkspaceSyncResult
            if let override = hostRefreshExecutorOverrideForTesting {
                result = try await override(scope)
            } else if let kmpEngine {
                let kmpSync = try await kmpEngine.refreshWorkspacesAndSummaries(
                    hostScope: scope,
                    skipRelayListRefresh: false
                )
                let succeededUuids = Set(kmpSync.succeededInstanceUuids)
                var refreshedNames = Set(
                    kmpSync.availableRelayInstances
                        .filter { succeededUuids.contains($0.uuid) }
                        .map(\.name)
                )
                if case .localHost(let targetId, let targetName) = scope,
                   succeededUuids.contains(targetId) {
                    refreshedNames.insert(targetName)
                }
                let targetReachable: Bool = {
                    switch scope {
                    case .localHost:
                        return !succeededUuids.isEmpty
                    case .antigravityCloud:
                        return kmpSync.cloudSucceeded || !kmpSync.cloudProjects.isEmpty
                    case .allHosts:
                        return (activeHost.channel != .cloudRelay)
                            || !succeededUuids.isEmpty
                            || kmpSync.cloudSucceeded
                    }
                }()
                let normalizedWorkspaces: [WorkspaceInfo] = kmpSync.workspaces.map { ws in
                    guard !ws.isCloud else { return ws }
                    if ws.originInstanceUuid?.isEmpty == false { return ws }
                    if case .localHost(let targetId, let targetName) = scope {
                        return WorkspaceInfo(
                            workspaceUri: ws.workspaceUri,
                            displayName: ws.displayName,
                            activeBranch: ws.activeBranch,
                            worktrees: ws.worktrees,
                            activeCascadeCount: ws.activeCascadeCount,
                            indexedFiles: ws.indexedFiles,
                            isCloud: false,
                            originInstanceUuid: targetId,
                            originHostName: (ws.originHostName?.isEmpty == false) ? ws.originHostName : targetName
                        )
                    }
                    return ws
                }
                result = ScopedWorkspaceSyncResult(
                    workspaces: normalizedWorkspaces,
                    summaries: kmpSync.summaries,
                    cloudProjects: kmpSync.cloudProjects,
                    cloudWarmingUp: kmpSync.cloudWarmingUp,
                    relayInstances: kmpSync.availableRelayInstances,
                    refreshedLocalHostUuids: succeededUuids,
                    refreshedLocalHostNames: refreshedNames,
                    refreshedCloud: kmpSync.cloudSucceeded,
                    targetReachable: targetReachable,
                    latencyMs: kmpSync.latencyMs
                )
            } else {
                guard let client = rpcClient else { return false }
                let isRelay = (activeHost.channel == .cloudRelay)
                let syncTimeout: TimeInterval = isRelay ? 14.0 : 4.0
                result = try await client.fetchScopedWorkspacesAndSummaries(
                    target: scope,
                    timeoutInterval: syncTimeout,
                    lightweightPoll: !forceFullSync && isRelay && isSummaryStreamHealthy,
                    skipRelayListRefresh: false
                )
            }

            guard !isNetworkingSuspended else { return false }
            await applyScopedHostRefreshResult(result, for: scope)
            return result.targetReachable
        } catch {
            if Self.isBackendOfflineError(error) {
                if case .localHost(let id, let name) = scope {
                    if let idx = hosts.firstIndex(where: { $0.instanceId == id || $0.hostname == name }) {
                        hosts[idx].isOnline = false
                    }
                    if activeHost.instanceId == id || activeHost.hostname == name {
                        activeHost.isOnline = false
                        isLiveBackendConnected = false
                        connectionStatusText = "Offline · \(activeHost.hostname)"
                        connectionErrorText = "\(name) is currently offline."
                    }
                }
            }
            return false
        }
    }

    internal func applyScopedHostRefreshResult(
        _ result: ScopedWorkspaceSyncResult,
        for scope: AgentsHostFilterScope
    ) async {
        if !result.relayInstances.isEmpty {
            syncRelayInstancesToHosts(
                result.relayInstances,
                latencyMs: result.latencyMs > 0 ? result.latencyMs : lastPingLatencyMs
            )
        }
        if result.latencyMs > 0 {
            lastPingLatencyMs = result.latencyMs
        }
        cloudAgentWarmingUp = result.cloudWarmingUp

        if case .localHost(let targetId, let targetName) = scope, !result.targetReachable {
            if let idx = hosts.firstIndex(where: { $0.instanceId == targetId || $0.hostname == targetName }) {
                hosts[idx].isOnline = false
            }
            if let rIdx = availableRelayInstances.firstIndex(where: { $0.uuid == targetId || $0.name == targetName }) {
                availableRelayInstances[rIdx] = availableRelayInstances[rIdx].withStatus(.disconnected)
            }
            if activeHost.instanceId == targetId || activeHost.hostname == targetName {
                var offlineActive = activeHost
                offlineActive.isOnline = false
                activeHost = offlineActive
                isLiveBackendConnected = false
                connectionStatusText = "Offline · \(activeHost.hostname)"
                connectionErrorText = "\(targetName) is currently offline."
                let nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelay(
                    attempt: reconnectAttemptCount,
                    isLowPowerMode: isLowPowerModeEnabled
                )
                connectionLifecyclePhase = .offlineBackoff(attempt: reconnectAttemptCount, nextRetrySeconds: nextDelay)
            }
            return
        }

        consecutiveSyncFailures = 0
        lastBackendActivityAt = Date()
        lastFullSyncAt = Date()

        var replacedLocalUuids = result.refreshedLocalHostUuids
        var replacedLocalHostNames = result.refreshedLocalHostNames
        if case .localHost(let targetId, let targetName) = scope, result.targetReachable {
            replacedLocalUuids.insert(targetId)
            replacedLocalHostNames.insert(targetName)
        }
        for inst in result.relayInstances where replacedLocalUuids.contains(inst.uuid) {
            replacedLocalHostNames.insert(inst.name)
        }
        for h in hosts where replacedLocalUuids.contains(h.instanceId) {
            replacedLocalHostNames.insert(h.hostname)
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

        let incomingWsKeys = Set(result.workspaces.map { ws in
            "\(ws.isCloud ? "cloud" : (ws.originInstanceUuid ?? ws.originHostName ?? "local"))|\(ws.workspaceUri)"
        })
        var keptWorkspaces = workspaces.filter { ws in
            let key = "\(ws.isCloud ? "cloud" : (ws.originInstanceUuid ?? ws.originHostName ?? "local"))|\(ws.workspaceUri)"
            if incomingWsKeys.contains(key) { return false }
            if ws.isCloud {
                return !result.refreshedCloud
            }
            return !isReplacedLocal(originUuid: ws.originInstanceUuid, originHostName: ws.originHostName)
        }
        keptWorkspaces.append(contentsOf: result.workspaces)

        // Ensure untouched local hosts' 0-conversation projects stay represented in `workspaces` across reconciliation
        let keptWsKeySet = Set(keptWorkspaces.map { ws in
            "\(ws.isCloud ? "cloud" : (ws.originInstanceUuid ?? ws.originHostName ?? "local"))|\(ws.workspaceUri.lowercased())"
        })
        for existingProj in projects where existingProj.runtime != .cloud
            && !existingProj.isNoProject
            && !existingProj.workspaceUri.isEmpty
            && !Self.esddFixtureProjectIds.contains(existingProj.id) {
            guard !isReplacedLocal(
                originUuid: existingProj.originInstanceUuid,
                originHostName: existingProj.hostName
            ) else { continue }
            let key = "\(existingProj.originInstanceUuid ?? existingProj.hostName)|\(existingProj.workspaceUri.lowercased())"
            if !keptWsKeySet.contains(key) {
                keptWorkspaces.append(
                    WorkspaceInfo(
                        workspaceUri: existingProj.workspaceUri,
                        displayName: existingProj.name,
                        activeBranch: existingProj.activeBranch,
                        worktrees: existingProj.worktrees,
                        isCloud: false,
                        originInstanceUuid: existingProj.originInstanceUuid,
                        originHostName: existingProj.hostName
                    )
                )
            }
        }
        workspaces = keptWorkspaces

        let existingById = Dictionary(uniqueKeysWithValues: summaries.map { ($0.cascadeId, $0) })
        let remoteIds = Set(result.summaries.map(\.cascadeId))
        let now = Date()
        var shouldResyncActiveCascade = false

        var mergedList: [CascadeSummary] = result.summaries.map { remote in
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

        // Preserve optimistic iOS sessions (`cas-*`) and ALL cached conversations belonging to untouched/offline hosts
        for existing in summaries where !remoteIds.contains(existing.cascadeId)
            && !Self.esddFixtureCascadeIds.contains(existing.cascadeId) {
            if existing.cascadeId.hasPrefix("cas-") {
                mergedList.insert(existing, at: 0)
            } else if existing.isCloud {
                if !result.refreshedCloud {
                    mergedList.append(existing)
                }
            } else if !isReplacedLocal(
                originUuid: existing.originInstanceUuid,
                originHostName: existing.originHostName
            ) {
                mergedList.append(existing)
            }
        }

        mergedList.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.cascadeId < rhs.cascadeId
        }

        let effectiveCloudProjects: [ProjectWorkspace] = result.refreshedCloud
            ? result.cloudProjects
            : projects.filter { $0.runtime == .cloud && $0.cloudProjectId != nil }
        let reconcileDefaultHostName: String = {
            if case .localHost(_, let targetName) = scope, !targetName.isEmpty {
                return targetName
            }
            return activeHost.hostname
        }()
        projects = Self.reconcileLiveProjects(
            workspaces: workspaces,
            summaries: &mergedList,
            existingProjects: projects,
            hostName: reconcileDefaultHostName,
            cloudProjects: effectiveCloudProjects
        )
        summaries = mergedList

        reconcileSelectedProjectForCurrentHostScope()

        var activeHostResponded = replacedLocalUuids.contains(activeHost.instanceId)
            || replacedLocalHostNames.contains(activeHost.hostname)
        if !activeHostResponded && scope == .allHosts && activeHost.channel == .cloudRelay,
           let onlinePeerUuid = replacedLocalUuids.first,
           let onlinePeerInst = availableRelayInstances.first(where: { $0.uuid == onlinePeerUuid && $0.status.isReachable }) {
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
                let latencySuffix = lastPingLatencyMs.map { " · \($0)ms" } ?? ""
                connectionStatusText = "Connected · \(activeHost.hostname)\(latencySuffix)"
            }
        }

        if shouldResyncActiveCascade && !activeCascadeId.isEmpty {
            syncStepsForCascade(
                activeCascadeId,
                pollUntilIdle: activeRoute == .cascadeChat(activeCascadeId)
            )
        }

        var refreshedHostKeys = Set<String>()
        for uuid in replacedLocalUuids where !uuid.isEmpty && uuid != "unpaired" {
            refreshedHostKeys.insert("host:\(uuid)")
        }
        if refreshedHostKeys.isEmpty {
            for hostName in replacedLocalHostNames where !hostName.isEmpty {
                refreshedHostKeys.insert("host:\(hostName)")
            }
        }
        if result.refreshedCloud {
            refreshedHostKeys.insert("cloud")
        }
        if !refreshedHostKeys.isEmpty {
            await persistHostProjections(refreshedHostKeys: refreshedHostKeys)
        }
        settledEmptyTitleCascadeIds.removeAll()
        preloadAttemptedAtByCascadeId.removeAll()
        scheduleConversationPreload()
    }

    /// Switches the active host scope (`All Hosts`, `Antigravity Cloud`, or a specific local Mac/PC),
    /// persists the selection, rebinds `activeHost` + `rpcClient` + push streams when a local device is chosen,
    /// and triggers a coalesced scoped refresh so rapid repeated switches to the same host never duplicate RPCs.
    public func selectHostScope(_ scope: AgentsHostFilterScope) {
        selectedHostScope = scope
        persistSelectedHostScope()

        guard !isVerificationMode, hasPairedBackend || isLiveBackendConnected else {
            if case .localHost(let id, let name) = scope,
               let matched = hosts.first(where: { $0.instanceId == id || $0.hostname == name }) {
                activeHost = matched
            }
            reconcileSelectedProjectForCurrentHostScope()
            return
        }

        reconcileSelectedProjectForCurrentHostScope()

        switch scope {
        case .localHost(let id, let name):
            let targetHost: RemoteHostInstance = {
                if let existing = hosts.first(where: { $0.instanceId == id }) {
                    return existing
                }
                if let byName = hosts.first(where: { $0.hostname == name }) {
                    return byName
                }
                let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
                let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
                if let inst = availableRelayInstances.first(where: { $0.uuid == id || $0.name == name }) {
                    let nextURL = URL(string: "\(originPrefix)/r/\(inst.uuid)") ?? activeHost.endpointURL
                    return RemoteHostInstance(
                        instanceId: inst.uuid,
                        hostname: inst.name,
                        version: inst.version,
                        channel: .cloudRelay,
                        endpointURL: nextURL,
                        isOnline: inst.status.isReachable,
                        latencyMs: lastPingLatencyMs ?? activeHost.latencyMs
                    )
                }
                let fallbackURL = URL(string: "\(originPrefix)/r/\(id)") ?? activeHost.endpointURL
                return RemoteHostInstance(
                    instanceId: id,
                    hostname: name,
                    version: activeHost.version,
                    channel: activeHost.channel,
                    endpointURL: fallbackURL,
                    isOnline: isLocalHostOnline(instanceId: id, hostname: name),
                    latencyMs: lastPingLatencyMs ?? activeHost.latencyMs
                )
            }()
            if rpcClient != nil || kmpEngine != nil || hostRefreshExecutorOverrideForTesting != nil {
                _ = ensureInFlightHostRefreshTask(
                    .localHost(id: targetHost.instanceId, name: targetHost.hostname),
                    forceFullSync: true
                )
            }
            hostSwitchTask?.cancel()
            hostSwitchTask = Task { [weak self] in
                _ = await self?.switchActiveHost(targetHost)
            }

        case .antigravityCloud, .allHosts:
            if rpcClient != nil || kmpEngine != nil || hostRefreshExecutorOverrideForTesting != nil {
                _ = ensureInFlightHostRefreshTask(scope, forceFullSync: true)
            }
            hostSwitchTask?.cancel()
            hostSwitchGeneration &+= 1
            let generation = hostSwitchGeneration
            isSwitchingHost = false
            cancelAllSummaryStreams()
            summaryPollingTask?.cancel()
            summaryPollingTask = nil
            hostSwitchTask = Task { [weak self] in
                guard let self else { return }
                _ = await self.refreshConversationsForHostScope(scope, forceFullSync: true)
                guard self.hostSwitchGeneration == generation else { return }
                if self.selectedTab == .automations {
                    await self.refreshAutomations()
                }
                self.startSummarySubscriptionStream()
            }
        }
    }

    /// Rebinds `activeHost`, `rpcClient`, Keychain target, and live summary streams to `host`
    /// without allowing cross-host failover to silently hijack a different machine if `host` is offline.
    @discardableResult
    public func switchActiveHost(_ host: RemoteHostInstance) async -> Bool {
        let previousChannel = activeHost.channel
        let existingRelayClient = (previousChannel == .cloudRelay) ? rpcClient : nil

        hostSwitchGeneration &+= 1
        let generation = hostSwitchGeneration
        cancelAllSummaryStreams()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        stepPollingTask?.cancel()
        stepPollingTask = nil

        selectedHostScope = .localHost(id: host.instanceId, name: host.hostname)
        persistSelectedHostScope()

        activeHost = host
        if let idx = hosts.firstIndex(where: { $0.instanceId == host.instanceId }) {
            hosts[idx] = host
        } else {
            hosts.insert(host, at: 0)
        }
        reconcileSelectedProjectForCurrentHostScope()

        isSwitchingHost = true
        consecutiveSyncFailures = 0
        reconnectAttemptCount = 0
        nextReconnectAt = nil
        connectionErrorText = nil
        connectionStatusText = host.isOnline
            ? "Switching to \(host.hostname)..."
            : "Offline · \(host.hostname)"
        defer {
            if self.hostSwitchGeneration == generation {
                self.isSwitchingHost = false
            }
        }

        if host.channel == .cloudRelay {
            if let client = existingRelayClient {
                await client.setTargetRelayInstance(uuid: host.instanceId, name: host.hostname)
                if let engine = kmpEngine {
                    let targetInst = availableRelayInstances.first(where: { $0.uuid == host.instanceId })
                        ?? RelayInstanceInfo(
                            uuid: host.instanceId,
                            name: host.hostname,
                            version: host.version,
                            status: host.isOnline ? .connected : .disconnected
                        )
                    await engine.switchToRelayInstance(targetInst)
                }
                if let savedCreds = await secretStore.loadCredentials(),
                   let cookie = savedCreds.sessionCookie,
                   !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(host.endpointURL.absoluteString)
                    let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
                    let relayURL = URL(string: "\(originPrefix)/r/\(host.instanceId)") ?? host.endpointURL
                    await secretStore.saveCredentials(
                        SavedBackendCredentials(
                            endpointURLString: relayURL.absoluteString,
                            channel: .cloudRelay,
                            hostname: host.hostname,
                            sessionCookie: cookie,
                            authUser: savedCreds.authUser ?? activeAuthUser,
                            resolvedInstanceUuid: host.instanceId,
                            relayApiKey: savedCreds.relayApiKey
                        )
                    )
                }
                guard self.hostSwitchGeneration == generation else { return false }

                _ = await refreshConversationsForHostScope(
                    .localHost(id: host.instanceId, name: host.hostname),
                    forceFullSync: true
                )
                guard self.hostSwitchGeneration == generation else { return false }

                if activeHost.instanceId != host.instanceId,
                   let savedCreds = await secretStore.loadCredentials(),
                   let cookie = savedCreds.sessionCookie,
                   !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
                    let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
                    let relayURL = URL(string: "\(originPrefix)/r/\(activeHost.instanceId)") ?? activeHost.endpointURL
                    await secretStore.saveCredentials(
                        SavedBackendCredentials(
                            endpointURLString: relayURL.absoluteString,
                            channel: .cloudRelay,
                            hostname: activeHost.hostname,
                            sessionCookie: cookie,
                            authUser: savedCreds.authUser ?? activeAuthUser,
                            resolvedInstanceUuid: activeHost.instanceId,
                            relayApiKey: savedCreds.relayApiKey
                        )
                    )
                }

                startSummarySubscriptionStream()
                if isLiveBackendConnected && activeHost.isOnline {
                    Task { [weak self] in
                        await self?.refreshModelCatalog()
                        if self?.selectedTab == .automations {
                            await self?.refreshAutomations()
                        }
                    }
                }
                return isLiveBackendConnected && activeHost.isOnline
            }

            guard let cached = await loadSavedSessionCookie() else {
                isLiveBackendConnected = false
                connectionErrorText = "Google Sign-In required to switch to \(host.hostname)."
                connectionStatusText = "Sign in with Google"
                return false
            }
            guard self.hostSwitchGeneration == generation else { return false }
            return await connectCloudRelay(
                relayURLString: host.endpointURL.absoluteString,
                sessionCookie: cached.cookie,
                authUser: cached.authUser ?? activeAuthUser,
                resolvedInstanceUuid: host.instanceId,
                hostName: host.hostname,
                strictTargetMatch: true
            )
        }

        rpcClient = AntigravityRPCClient(
            host: host,
            csrfToken: "csrf-antigravity-ios-session-token"
        )
        _ = await refreshConversationsForHostScope(
            .localHost(id: host.instanceId, name: host.hostname),
            forceFullSync: true
        )
        guard self.hostSwitchGeneration == generation else { return false }
        startSummarySubscriptionStream()
        return isLiveBackendConnected && activeHost.isOnline
    }

    /// Convenience wrapper for Settings / Remote Pairing host selection.
    @discardableResult
    public func switchToRelayInstance(_ inst: RelayInstanceInfo) async -> Bool {
        await kmpEngine?.switchToRelayInstance(inst)
        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
        let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
        let relayURL = URL(string: "\(originPrefix)/r/\(inst.uuid)")
            ?? URL(string: "\(SAPISIDHashGenerator.defaultOrigin)/r/\(inst.uuid)")!
        let targetHost = RemoteHostInstance(
            instanceId: inst.uuid,
            hostname: inst.name,
            version: inst.version,
            channel: .cloudRelay,
            endpointURL: relayURL,
            isOnline: inst.status.isReachable,
            latencyMs: lastPingLatencyMs ?? activeHost.latencyMs
        )
        return await switchActiveHost(targetHost)
    }

    public func selectHost(_ host: RemoteHostInstance) {
        if !isVerificationMode && (hasPairedBackend || isLiveBackendConnected) {
            selectedHostScope = .localHost(id: host.instanceId, name: host.hostname)
            persistSelectedHostScope()
            hostSwitchTask?.cancel()
            hostSwitchTask = Task { [weak self] in
                _ = await self?.switchActiveHost(host)
            }
            return
        }
        activeHost = host
        selectedHostScope = .localHost(id: host.instanceId, name: host.hostname)
        rpcClient = AntigravityRPCClient(
            host: host,
            csrfToken: "csrf-antigravity-ios-session-token"
        )
    }

    public func selectProject(_ projectSlug: String) {
        selectedProjectId = projectSlug
        if let project = projects.first(where: { $0.id == projectSlug || $0.name == projectSlug }) {
            selectedProjectId = project.id
            selectedWorkspaceUri = project.workspaceUri
        }
        selectedTab = .agents
        activeRoute = .tabRoot
    }

    public func toggleProjectExpandedInHome(_ projectSlug: String) {
        guard let idx = projects.firstIndex(where: { $0.id == projectSlug }) else { return }
        projects[idx].isExpandedInHome.toggle()
    }

    public func selectWorkspace(_ workspaceUri: String) {
        selectedWorkspaceUri = workspaceUri
        selectedWorktreeFilter = nil
        if let firstCascade = summaries.first(where: { $0.workspaceUri == workspaceUri && !$0.isArchived }) {
            selectCascade(firstCascade.cascadeId)
        }
    }

    public func selectCascade(_ cascadeId: String) {
        discardPendingDraftConversation()
        activeCascadeId = cascadeId
        let viewedNow = Date()
        locallyViewedAtByCascadeId[cascadeId] = viewedNow
        var shouldSyncViewedAnnotation = false
        var originUuidForViewSync: String? = nil
        if let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
            shouldSyncViewedAnnotation = summaries[idx].isUnread
            originUuidForViewSync = summaries[idx].originInstanceUuid
            summaries[idx].isUnread = false
            summaries[idx].lastUserViewTime = viewedNow
            selectedWorkspaceUri = summaries[idx].workspaceUri
            selectedProjectId = summaries[idx].projectSlug
            if hasPairedBackend || isLiveBackendConnected {
                summaries[idx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                    status: summaries[idx].status,
                    stepCount: summaries[idx].stepCount,
                    isUnread: false
                )
            }
        }
        if let cachedSteps = stepsByCascadeId[cascadeId] {
            harvestEmbedResources(from: cachedSteps)
            if let latestCfgStep = cachedSteps.last(where: {
                $0.type == .userInput && ($0.recordedExecutionMode != nil || $0.recordedModelId != nil)
            }) {
                applyRecordedConversationConfig(from: latestCfgStep)
            }
        }
        activeRoute = .cascadeChat(cascadeId)
        unreadStreamingStepCount = 0
        isAutoScrollPinnedToBottom = true
        if hasPairedBackend || isLiveBackendConnected {
            let selectedSummary = summaries.first(where: { $0.cascadeId == cascadeId })
            if shouldSyncViewedAnnotation,
               !isVerificationMode,
               isSummaryHostOnline(selectedSummary),
               !cascadeId.hasPrefix("cas-") || Self.esddFixtureCascadeIds.contains(cascadeId),
               activeHost.channel == .cloudRelay,
               let clientRef = rpcClient {
                let targetUuid = originUuidForViewSync
                Task { [weak self] in
                    do {
                        try await clientRef.markCascadeViewed(
                            cascadeId: cascadeId,
                            viewedAt: viewedNow,
                            instanceUuidOverride: targetUuid
                        )
                    } catch {
                        await self?.refreshHostCapabilitiesFromClient()
                    }
                }
            }
            syncStepsForCascade(cascadeId, pollUntilIdle: true)
        }
    }


    // MARK: - Conversation Context Menu & Swipe Actions (`UE03`)

    public func togglePinCascade(_ cascadeId: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        let previousPinned = summaries[idx].isPinned
        summaries[idx].isPinned.toggle()
        let isPinned = summaries[idx].isPinned
        let originUuid = summaries[idx].originInstanceUuid
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        Task { [weak self] in
            await storeRef.saveProjectedSummaries(snapshot)
            guard let clientRef else { return }
            do {
                try await clientRef.pinCascade(cascadeId: cascadeId, isPinned: isPinned, instanceUuidOverride: originUuid)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let rIdx = self.summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
                    self.summaries[rIdx].isPinned = previousPinned
                    await storeRef.saveProjectedSummaries(self.summaries)
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .conversationAnnotations,
                    fallbackActionLabel: isPinned ? "Pinning conversation" : "Unpinning conversation"
                )
            }
        }
    }

    public func toggleUnreadCascade(_ cascadeId: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].isUnread.toggle()
        let now = Date()
        let nowUnread = summaries[idx].isUnread
        let originUuid = summaries[idx].originInstanceUuid
        if nowUnread {
            locallyViewedAtByCascadeId.removeValue(forKey: cascadeId)
        } else {
            locallyViewedAtByCascadeId[cascadeId] = now
            summaries[idx].lastUserViewTime = now
        }
        if hasPairedBackend || isLiveBackendConnected {
            summaries[idx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                status: summaries[idx].status,
                stepCount: summaries[idx].stepCount,
                isUnread: nowUnread
            )
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let shouldSyncViewed = !nowUnread
            && !isVerificationMode
            && (hasPairedBackend || isLiveBackendConnected)
            && activeHost.channel == .cloudRelay
            && !cascadeId.hasPrefix("cas-")
        let clientRef = shouldSyncViewed ? rpcClient : nil
        Task { [weak self] in
            await storeRef.saveProjectedSummaries(snapshot)
            if let clientRef {
                do {
                    try await clientRef.markCascadeViewed(
                        cascadeId: cascadeId,
                        viewedAt: now,
                        instanceUuidOverride: originUuid
                    )
                } catch {
                    await self?.refreshHostCapabilitiesFromClient()
                }
            }
        }
    }

    public func renameCascade(_ cascadeId: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        let previousTitle = summaries[idx].title
        summaries[idx].title = trimmed
        let originUuid = summaries[idx].originInstanceUuid
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        Task { [weak self] in
            await storeRef.saveProjectedSummaries(snapshot)
            guard let clientRef else { return }
            do {
                try await clientRef.renameCascade(cascadeId: cascadeId, newTitle: trimmed, instanceUuidOverride: originUuid)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let rIdx = self.summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
                    self.summaries[rIdx].title = previousTitle
                    await storeRef.saveProjectedSummaries(self.summaries)
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .conversationAnnotations,
                    fallbackActionLabel: "Renaming conversation"
                )
            }
        }
    }

    public func moveCascade(_ cascadeId: String, toProject projectSlug: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        let previousSlug = summaries[idx].projectSlug
        let previousUri = summaries[idx].workspaceUri
        summaries[idx].projectSlug = projectSlug
        let targetUri = projects.first(where: { $0.id == projectSlug })?.workspaceUri ?? summaries[idx].workspaceUri
        summaries[idx].workspaceUri = targetUri
        let originUuid = summaries[idx].originInstanceUuid
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        Task { [weak self] in
            await storeRef.saveProjectedSummaries(snapshot)
            guard let clientRef else { return }
            do {
                try await clientRef.moveCascadeToWorkspace(cascadeId: cascadeId, workspaceUri: targetUri, instanceUuidOverride: originUuid)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let rIdx = self.summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
                    self.summaries[rIdx].projectSlug = previousSlug
                    self.summaries[rIdx].workspaceUri = previousUri
                    await storeRef.saveProjectedSummaries(self.summaries)
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .conversationAnnotations,
                    fallbackActionLabel: "Moving conversation"
                )
            }
        }
    }

    public func archiveCascade(_ cascadeId: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        let previousArchived = summaries[idx].isArchived
        summaries[idx].isArchived = true
        let originUuid = summaries[idx].originInstanceUuid
        if activeCascadeId == cascadeId, let next = filteredSummaries.first {
            activeCascadeId = next.cascadeId
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        Task { [weak self] in
            await storeRef.saveProjectedSummaries(snapshot)
            guard let clientRef else { return }
            do {
                try await clientRef.archiveCascade(cascadeId: cascadeId, isArchived: true, instanceUuidOverride: originUuid)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let rIdx = self.summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
                    self.summaries[rIdx].isArchived = previousArchived
                    await storeRef.saveProjectedSummaries(self.summaries)
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .conversationAnnotations,
                    fallbackActionLabel: "Archiving conversation"
                )
            }
        }
    }

    public func deleteCascade(_ cascadeId: String) {
        guard let removedIdx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        let removedSummary = summaries.remove(at: removedIdx)
        let removedSteps = stepsByCascadeId.removeValue(forKey: cascadeId)
        let originUuid = removedSummary.originInstanceUuid
        if activeCascadeId == cascadeId, let next = filteredSummaries.first {
            activeCascadeId = next.cascadeId
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        Task { [weak self] in
            await storeRef.saveProjectedSummaries(snapshot)
            guard let clientRef else { return }
            do {
                try await clientRef.deleteCascade(cascadeId: cascadeId, instanceUuidOverride: originUuid)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if !self.summaries.contains(where: { $0.cascadeId == cascadeId }) {
                    let insertIdx = min(removedIdx, self.summaries.count)
                    self.summaries.insert(removedSummary, at: insertIdx)
                    if let removedSteps {
                        self.stepsByCascadeId[cascadeId] = removedSteps
                    }
                    await storeRef.saveProjectedSummaries(self.summaries)
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .conversationAnnotations,
                    fallbackActionLabel: "Deleting conversation"
                )
            }
        }
    }


    // MARK: - Full-Text Search, Slash Commands & Typo-Tolerant @Mentions

    public func runFullTextConversationSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remoteSearchResults = []
            isSearchingAllConversations = false
            return
        }
        isSearchingAllConversations = true
        defer { isSearchingAllConversations = false }

        if let client = rpcClient, (hasPairedBackend || isLiveBackendConnected),
           let remote = try? await client.searchAllConversations(query: trimmed),
           !remote.isEmpty {
            remoteSearchResults = remote
            return
        }

        // Offline/local full-text fallback across titles, previews, and loaded step contents
        let q = trimmed.lowercased()
        remoteSearchResults = summaries.filter { summary in
            if summary.title.lowercased().contains(q)
                || summary.projectSlug.lowercased().contains(q)
                || summary.statusSubtitle.lowercased().contains(q)
                || (summary.lastMessagePreview?.lowercased().contains(q) ?? false) {
                return true
            }
            if let steps = stepsByCascadeId[summary.cascadeId] {
                return steps.contains { step in
                    (step.userInput?.lowercased().contains(q) ?? false)
                        || (step.plannerResponse?.response.lowercased().contains(q) ?? false)
                }
            }
            return false
        }
    }

    public func filteredSlashCommands(for draft: String) -> [SlashCommandItem] {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        let query = String(trimmed.dropFirst()).lowercased()
        let isRemote = activeSummary?.isCloud ?? false
        let all = SlashCommandItem.commands(isRemoteAgent: isRemote, customSkills: customizations.skills)
        guard !query.isEmpty else { return all }
        return all.filter { item in
            item.command.lowercased().contains(query)
                || item.title.lowercased().contains(query)
                || item.summary.lowercased().contains(query)
        }
    }

    public func filteredMentionCandidates(for query: String) -> [ContextCandidateItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return contextCandidates }
        return contextCandidates.filter { candidate in
            let hay = "\(candidate.title) \(candidate.subtitle)".lowercased()
            if hay.contains(q) { return true }
            // Typo-tolerant subsequence match for @ mentions (v2.32.0+)
            var qIdx = q.startIndex
            for ch in hay {
                if qIdx < q.endIndex && ch == q[qIdx] {
                    qIdx = q.index(after: qIdx)
                }
            }
            return qIdx == q.endIndex
        }
    }
}
