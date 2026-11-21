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

    public var runningCount: Int {
        summaries.filter { !$0.isArchived && ($0.status == .inProgress || $0.status == .pending) }.count
    }

    public var runningCascadeCount: Int { runningCount }

    public var needsYouCount: Int {
        summaries.filter { !$0.isArchived && ($0.status == .waiting || $0.status == .blocked) }.count
    }

    public var waitingApprovalCount: Int { needsYouCount }

    public var unreadCount: Int {
        summaries.filter { !$0.isArchived && $0.isUnread }.count
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
        CascadeDisplayItem.buildDisplayItems(from: activeSteps)
    }

    public var activeTaskBoundary: TaskBoundaryPayload? {
        activeSteps.last(where: { $0.type == .taskBoundary })?.taskBoundary
    }

    public var pendingWaitingStep: CascadeStep? {
        activeSteps.first(where: { $0.status == .waiting })
    }

    public var isCascadeStreaming: Bool {
        if let summary = activeSummary, summary.status == .inProgress || summary.status == .pending {
            return true
        }
        return activeSteps.contains(where: { $0.status == .inProgress || $0.status == .pending })
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

    public func selectHost(_ host: RemoteHostInstance) {
        activeHost = host
        if (hasPairedBackend || isLiveBackendConnected), host.channel == .cloudRelay {
            let authIdx = activeAuthUser
            Task { [weak self] in
                guard let self, let cached = await self.loadSavedSessionCookie() else { return }
                _ = await self.connectCloudRelay(
                    relayURLString: host.endpointURL.absoluteString,
                    sessionCookie: cached.cookie,
                    authUser: cached.authUser ?? authIdx,
                    resolvedInstanceUuid: host.instanceId,
                    hostName: host.hostname
                )
            }
            return
        }
        rpcClient = AntigravityRPCClient(
            host: host,
            csrfToken: "csrf-antigravity-ios-session-token"
        )
    }

    public func selectProject(_ projectSlug: String) {
        selectedProjectId = projectSlug
        if let project = projects.first(where: { $0.id == projectSlug }) {
            selectedWorkspaceUri = project.workspaceUri
        }
        activeRoute = .projectDetail(projectSlug)
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
            if shouldSyncViewedAnnotation,
               !isVerificationMode,
               !cascadeId.hasPrefix("cas-") || Self.esddFixtureCascadeIds.contains(cascadeId),
               activeHost.channel == .cloudRelay,
               let clientRef = rpcClient {
                let targetUuid = originUuidForViewSync
                Task {
                    try? await clientRef.markCascadeViewed(
                        cascadeId: cascadeId,
                        viewedAt: viewedNow,
                        instanceUuidOverride: targetUuid
                    )
                }
            }
            syncStepsForCascade(cascadeId, pollUntilIdle: true)
        }
    }

    // MARK: - Conversation Context Menu & Swipe Actions (`UE03`)

    public func togglePinCascade(_ cascadeId: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].isPinned.toggle()
        let isPinned = summaries[idx].isPinned
        let originUuid = summaries[idx].originInstanceUuid
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.pinCascade(cascadeId: cascadeId, isPinned: isPinned, instanceUuidOverride: originUuid)
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
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            if let clientRef {
                try? await clientRef.markCascadeViewed(
                    cascadeId: cascadeId,
                    viewedAt: now,
                    instanceUuidOverride: originUuid
                )
            }
        }
    }

    public func renameCascade(_ cascadeId: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].title = trimmed
        let originUuid = summaries[idx].originInstanceUuid
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.renameCascade(cascadeId: cascadeId, newTitle: trimmed, instanceUuidOverride: originUuid)
        }
    }

    public func moveCascade(_ cascadeId: String, toProject projectSlug: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].projectSlug = projectSlug
        let targetUri = projects.first(where: { $0.id == projectSlug })?.workspaceUri ?? summaries[idx].workspaceUri
        summaries[idx].workspaceUri = targetUri
        let originUuid = summaries[idx].originInstanceUuid
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.moveCascadeToWorkspace(cascadeId: cascadeId, workspaceUri: targetUri, instanceUuidOverride: originUuid)
        }
    }

    public func archiveCascade(_ cascadeId: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].isArchived = true
        let originUuid = summaries[idx].originInstanceUuid
        if activeCascadeId == cascadeId, let next = filteredSummaries.first {
            activeCascadeId = next.cascadeId
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.archiveCascade(cascadeId: cascadeId, isArchived: true, instanceUuidOverride: originUuid)
        }
    }

    public func deleteCascade(_ cascadeId: String) {
        let originUuid = summaries.first(where: { $0.cascadeId == cascadeId })?.originInstanceUuid
        summaries.removeAll { $0.cascadeId == cascadeId }
        stepsByCascadeId.removeValue(forKey: cascadeId)
        if activeCascadeId == cascadeId, let next = filteredSummaries.first {
            activeCascadeId = next.cascadeId
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.deleteCascade(cascadeId: cascadeId, instanceUuidOverride: originUuid)
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
