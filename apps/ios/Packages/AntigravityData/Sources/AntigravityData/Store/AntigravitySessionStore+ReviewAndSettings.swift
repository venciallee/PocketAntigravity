import Foundation

/// Embed & artifact resolution, Implementation Plan & Turn Diff review, Git VCS, customizations, preferences, and extension bridges.
extension AntigravitySessionStore {
    // MARK: - Embed & Artifact Resource Resolution (`<agent-embed>`, `file:///` Images & HTML Widgets)

    public func harvestEmbedResources(from steps: [CascadeStep]) {
        for step in steps {
            if let ca = step.codeAction, let content = ca.fileContent, !content.isEmpty {
                let norm = ResolvedEmbedResource.normalizePath(ca.targetFileUri)
                let res = ResolvedEmbedResource(
                    uri: ca.targetFileUri,
                    normalizedPath: norm,
                    mimeType: ResolvedEmbedResource.inferredMimeType(for: ca.targetFileUri),
                    textContent: content,
                    binaryData: Data(content.utf8),
                    source: .trajectoryStep
                )
                storeResolvedEmbedInCache(res)
            }
            if let vf = step.viewFile, let content = vf.fileContent, !content.isEmpty {
                let norm = ResolvedEmbedResource.normalizePath(vf.fileUri)
                let res = ResolvedEmbedResource(
                    uri: vf.fileUri,
                    normalizedPath: norm,
                    mimeType: ResolvedEmbedResource.inferredMimeType(for: vf.fileUri),
                    textContent: content,
                    binaryData: Data(content.utf8),
                    source: .trajectoryStep
                )
                storeResolvedEmbedInCache(res)
            }
        }
    }

    public func harvestEmbedResources(from artifacts: [ArtifactSnapshot]) {
        for artifact in artifacts where !artifact.content.isEmpty {
            let norm = ResolvedEmbedResource.normalizePath(artifact.artifactPath)
            let res = ResolvedEmbedResource(
                uri: artifact.artifactPath,
                normalizedPath: norm,
                mimeType: ResolvedEmbedResource.inferredMimeType(for: artifact.artifactPath),
                textContent: artifact.content,
                binaryData: Data(artifact.content.utf8),
                source: .artifactSnapshot
            )
            storeResolvedEmbedInCache(res)
        }
    }

    internal func storeResolvedEmbedInCache(_ resource: ResolvedEmbedResource) {
        if resolvedEmbedCache.count >= 64, resolvedEmbedCache[resource.normalizedPath] == nil {
            if let firstKey = resolvedEmbedCache.keys.first {
                resolvedEmbedCache.removeValue(forKey: firstKey)
            }
        }
        resolvedEmbedCache[resource.normalizedPath] = resource
    }

    public func cachedEmbedResource(for uri: String) -> ResolvedEmbedResource? {
        let norm = ResolvedEmbedResource.normalizePath(uri)
        if let exact = resolvedEmbedCache[norm] {
            return exact
        }
        let targetBase = (norm as NSString).lastPathComponent.lowercased()
        guard !targetBase.isEmpty else { return nil }
        // Match `/brain/<id>/<filename>` even if host home directory prefix differs (e.g. `/Users/...` vs `/home/...`)
        if norm.contains("/brain/") || norm.contains("/.gemini/") {
            if let byBase = resolvedEmbedCache.values.first(where: {
                ($0.normalizedPath as NSString).lastPathComponent.lowercased() == targetBase
            }) {
                return byBase
            }
        }
        return nil
    }

    /// 4-tier resolver for `<agent-embed src="...">` HTML widgets, SVGs, and `file:///` images:
    /// 1. In-memory trajectory & artifact snapshot cache (works offline & over Cloud Relay)
    /// 2. Inline `data:` URI decoding
    /// 3. Direct `http://`/`https://` URL pass-through
    /// 4. Remote host / Companion Bridge / Desktop `GetArtifactSnapshots` / `GetRevisionArtifact` RPC
    public func resolveEmbedResource(
        uri: String,
        cascadeId: String? = nil
    ) async -> ResolvedEmbedResource? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Tier 1: Local trajectory & artifact cache
        if let cached = cachedEmbedResource(for: trimmed) {
            return cached
        }

        // Tier 2: Inline `data:` URI
        if trimmed.lowercased().hasPrefix("data:"),
           let decoded = ResolvedEmbedResource.decodeDataURI(trimmed) {
            storeResolvedEmbedInCache(decoded)
            return decoded
        }

        // Tier 3: Direct HTTP(S) URL
        let lower = trimmed.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            let direct = ResolvedEmbedResource(
                uri: trimmed,
                normalizedPath: trimmed,
                mimeType: ResolvedEmbedResource.inferredMimeType(for: trimmed),
                textContent: nil,
                binaryData: nil,
                source: .directNetwork
            )
            return direct
        }

        // Tier 4: Live backend RPC fetch (`ReadArtifactFile` -> `GetArtifactSnapshots` -> `GetRevisionArtifact`)
        guard (hasPairedBackend || isLiveBackendConnected),
              isDeviceNetworkReachable,
              !isNetworkingSuspended,
              let client = rpcClient else {
            return nil
        }

        let effectiveCascadeId = cascadeId ?? activeCascadeId
        let originUuid = summaries.first(where: { $0.cascadeId == effectiveCascadeId })?.originInstanceUuid
        if let fetched = await client.fetchRemoteArtifactResource(
            uri: trimmed,
            cascadeId: effectiveCascadeId,
            instanceUuidOverride: originUuid
        ) {
            storeResolvedEmbedInCache(fetched)
            return fetched
        }
        return nil
    }

    public func resetDisplayOptions() {
        displayOptions = AgentDisplayOptions()
        let opts = displayOptions
        let storeRef = projectionStore
        Task {
            await storeRef.saveDisplayOptions(opts)
        }
    }

    public func markAllConversationsAsRead() {
        let now = Date()
        var targetsToSync: [(cascadeId: String, originUuid: String?)] = []
        for idx in summaries.indices {
            if summaries[idx].isUnread {
                targetsToSync.append((summaries[idx].cascadeId, summaries[idx].originInstanceUuid))
            }
            summaries[idx].isUnread = false
            summaries[idx].lastUserViewTime = now
            if hasPairedBackend || isLiveBackendConnected {
                summaries[idx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                    status: summaries[idx].status,
                    stepCount: summaries[idx].stepCount,
                    isUnread: false
                )
            }
            locallyViewedAtByCascadeId[summaries[idx].cascadeId] = now
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let shouldSyncRemote = !isVerificationMode
            && (hasPairedBackend || isLiveBackendConnected)
            && activeHost.channel == .cloudRelay
        let clientRef = shouldSyncRemote ? rpcClient : nil
        Task { [weak self] in
            await storeRef.saveProjectedSummaries(snapshot)
            if let clientRef {
                for item in targetsToSync where !item.cascadeId.hasPrefix("cas-") {
                    do {
                        try await clientRef.markCascadeViewed(
                            cascadeId: item.cascadeId,
                            viewedAt: now,
                            instanceUuidOverride: item.originUuid
                        )
                    } catch {
                        await self?.refreshHostCapabilitiesFromClient()
                    }
                }
            }
        }
    }


    // MARK: - Implementation Plan Review Actions (`UE11`)

    @discardableResult
    public func addPlanComment(
        targetFilePath: String = "settlement/settlement_test.go",
        quotedSpan: String = "remove the package-level clk variable",
        body: String
    ) -> PlanInlineComment? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let comment = PlanInlineComment(
            authorInitials: "WL",
            authorName: "You",
            statusLabel: "Pending",
            targetFilePath: targetFilePath,
            quotedSpan: quotedSpan,
            body: trimmed
        )
        planComments.append(comment)
        return comment
    }

    public func sendPlanCommentsToAgent() {
        guard !planComments.isEmpty else { return }
        for idx in planComments.indices {
            planComments[idx].statusLabel = "Sent"
        }
        let commentsSnapshot = planComments
        let cid = activeCascadeId
        if let idx = summaries.firstIndex(where: { $0.cascadeId == "cas-flaky-settlement" }) {
            summaries[idx].status = .inProgress
            summaries[idx].statusSubtitle = "Running · Addressing \(commentsSnapshot.count) plan comments"
            summaries[idx].isUnread = false
        }
        activeRoute = .cascadeChat(cid)

        let storeRef = projectionStore
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        let entry = OutboxEntry(
            cascadeId: cid,
            kind: .planComments,
            messageText: "Sent \(commentsSnapshot.count) plan review comments"
        )
        Task { [weak self] in
            await storeRef.enqueueOutbox(entry)
            if let clientRef {
                do {
                    try await clientRef.sendPlanReviewComments(cascadeId: cid, comments: commentsSnapshot)
                    await self?.refreshHostCapabilitiesFromClient()
                    await storeRef.removeOutboxEntry(id: entry.id)
                } catch {
                    if !isLive {
                        await storeRef.removeOutboxEntry(id: entry.id)
                        return
                    }
                    await self?.handleLiveCapabilityWriteError(
                        error,
                        capability: .turnDiff,
                        fallbackActionLabel: "Sending plan review comments"
                    )
                }
            } else {
                await storeRef.removeOutboxEntry(id: entry.id)
            }
        }
    }

    public func approveArtifactPlan(artifactPath: String = "/brain/implementation_plan.md") {
        if let idx = activeArtifacts.firstIndex(where: { $0.artifactPath == artifactPath }) {
            activeArtifacts[idx].requestFeedback = false
            activeArtifacts[idx].summary = "Approved · \(planComments.count) comments addressed"
        }
        if let waiting = pendingWaitingStep {
            resolveWaitingStep(stepIndex: waiting.stepIndex, decision: .allowOnce)
        }
        activeRoute = .cascadeChat(activeCascadeId)
    }

    // MARK: - Turn Diff Line-Level Review Actions (`UE12`)

    public func selectNextDiffFile() {
        guard !activeTurnDiffs.isEmpty else { return }
        selectedDiffFileIndex = (selectedDiffFileIndex + 1) % activeTurnDiffs.count
    }

    public func selectPreviousDiffFile() {
        guard !activeTurnDiffs.isEmpty else { return }
        selectedDiffFileIndex = (selectedDiffFileIndex - 1 + activeTurnDiffs.count) % activeTurnDiffs.count
    }

    public func addDiffComment(filePath: String, lineNumber: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        diffComments.append(
            DiffLineComment(filePath: filePath, lineNumber: lineNumber, body: trimmed, sentToAgent: false)
        )
    }

    public func submitDiffLineComment(sendImmediately: Bool) {
        let trimmed = activeLineCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let path = currentDiffFile?.filePath ?? "middleware/ratelimit.go"
        let line = selectedDiffLineNumber ?? 29
        let comment = DiffLineComment(
            filePath: path,
            lineNumber: line,
            body: trimmed,
            sentToAgent: sendImmediately
        )
        diffComments.append(comment)
        activeLineCommentDraft = ""

        if sendImmediately {
            let cid = activeCascadeId
            let clientRef = rpcClient
            let storeRef = projectionStore
            let isLive = isLiveBackendActive
            let entry = OutboxEntry(cascadeId: cid, kind: .diffComments, messageText: comment.body)
            Task { [weak self] in
                await storeRef.enqueueOutbox(entry)
                if let clientRef {
                    do {
                        try await clientRef.sendDiffReviewComments(cascadeId: cid, comments: [comment])
                        await self?.refreshHostCapabilitiesFromClient()
                        await storeRef.removeOutboxEntry(id: entry.id)
                    } catch {
                        if !isLive {
                            await storeRef.removeOutboxEntry(id: entry.id)
                            return
                        }
                        await self?.handleLiveCapabilityWriteError(
                            error,
                            capability: .turnDiff,
                            fallbackActionLabel: "Sending diff review comment"
                        )
                    }
                } else {
                    await storeRef.removeOutboxEntry(id: entry.id)
                }
            }
        }
    }

    public func toggleDiffFileViewed() {
        guard activeTurnDiffs.indices.contains(selectedDiffFileIndex) else { return }
        activeTurnDiffs[selectedDiffFileIndex].isReviewed.toggle()
    }

    public func acceptCurrentDiffFile() {
        guard activeTurnDiffs.indices.contains(selectedDiffFileIndex) else { return }
        activeTurnDiffs.remove(at: selectedDiffFileIndex)
        if activeTurnDiffs.isEmpty {
            selectedDiffFileIndex = 0
            activeRoute = .cascadeChat(activeCascadeId)
        } else {
            selectedDiffFileIndex = min(selectedDiffFileIndex, activeTurnDiffs.count - 1)
        }
    }

    public func acceptPatchFile(_ filePath: String) {
        if let idx = activeTurnDiffs.firstIndex(where: { $0.filePath == filePath }) {
            selectedDiffFileIndex = idx
            acceptCurrentDiffFile()
        }
    }

    public func revertCurrentDiffHunk() {
        guard let current = currentDiffFile else { return }
        let cid = activeCascadeId
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        Task { [weak self] in
            guard let clientRef else { return }
            do {
                try await clientRef.revertDiffHunk(
                    cascadeId: cid,
                    filePath: current.filePath,
                    hunkHeader: current.hunkHeader
                )
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .turnDiff,
                    fallbackActionLabel: "Reverting diff hunk"
                )
            }
        }
    }

    public func revertCurrentDiffFile() {
        guard activeTurnDiffs.indices.contains(selectedDiffFileIndex) else { return }
        let removedIdx = selectedDiffFileIndex
        let removed = activeTurnDiffs.remove(at: removedIdx)
        let previousRoute = activeRoute
        if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
            summaries[sumIdx].totalAdditions = max(0, summaries[sumIdx].totalAdditions - removed.additions)
            summaries[sumIdx].totalDeletions = max(0, summaries[sumIdx].totalDeletions - removed.deletions)
        }
        if activeTurnDiffs.isEmpty {
            selectedDiffFileIndex = 0
            activeRoute = .cascadeChat(activeCascadeId)
        } else {
            selectedDiffFileIndex = min(selectedDiffFileIndex, activeTurnDiffs.count - 1)
        }
        let cid = activeCascadeId
        let clientRef = rpcClient
        let isLive = isLiveBackendActive
        Task { [weak self] in
            guard let clientRef else { return }
            do {
                try await clientRef.revertDiffHunk(cascadeId: cid, filePath: removed.filePath, hunkHeader: nil)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if !self.activeTurnDiffs.contains(where: { $0.filePath == removed.filePath }) {
                    let restoreIdx = min(removedIdx, self.activeTurnDiffs.count)
                    self.activeTurnDiffs.insert(removed, at: restoreIdx)
                    self.selectedDiffFileIndex = restoreIdx
                    if let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == cid }) {
                        self.summaries[sumIdx].totalAdditions += removed.additions
                        self.summaries[sumIdx].totalDeletions += removed.deletions
                    }
                    self.activeRoute = previousRoute
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .turnDiff,
                    fallbackActionLabel: "Reverting diff file"
                )
            }
        }
    }

    public func acceptAllTurnDiffs() {
        activeTurnDiffs.removeAll()
        selectedDiffFileIndex = 0
        activeRoute = .cascadeChat(activeCascadeId)
    }

    // MARK: - Antigravity 2.0 (v2.33) Capabilities (P0 - P2)

    /// Returns the effective permission preset for a conversation (falls back to global preset).
    public func effectivePermissionPreset(for cascadeId: String? = nil) -> AgentPermissionPreset {
        let cid = cascadeId ?? activeCascadeId
        if let explicit = conversationPermissionPresets[cid], explicit != .inheritGlobal {
            return explicit
        }
        return activePermissionPreset
    }

    public func setConversationPermissionPreset(_ preset: AgentPermissionPreset, for cascadeId: String? = nil) {
        let cid = cascadeId ?? activeCascadeId
        let previousPreset = conversationPermissionPresets[cid]
        if preset == .inheritGlobal {
            conversationPermissionPresets.removeValue(forKey: cid)
        } else {
            conversationPermissionPresets[cid] = preset
        }
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
        let clientRef = rpcClient
        if !cid.isEmpty, let clientRef {
            Task { [weak self] in
                do {
                    try await clientRef.setConversationPermissionPreset(cascadeId: cid, preset: preset)
                    await self?.refreshHostCapabilitiesFromClient()
                } catch {
                    guard let self, isLive else { return }
                    if let previousPreset {
                        self.conversationPermissionPresets[cid] = previousPreset
                    } else {
                        self.conversationPermissionPresets.removeValue(forKey: cid)
                    }
                    await self.handleLiveCapabilityWriteError(
                        error,
                        capability: .permissionPreset,
                        fallbackActionLabel: "Updating permission preset"
                    )
                }
            }
        }
    }

    public func addPermissionRule(_ rule: PermissionRuleEntry) {
        if !permissionRules.contains(where: { $0.formattedRule == rule.formattedRule && $0.list == rule.list }) {
            permissionRules.append(rule)
        }
    }

    public func removePermissionRule(id: String) {
        permissionRules.removeAll { $0.id == id }
    }

    // MARK: - Persistent Sidebar Collapse & Appearance Preferences

    public func isProjectCollapsed(_ projectId: String) -> Bool {
        appearancePreferences.collapsedProjectIds.contains(projectId)
    }

    public func toggleProjectCollapsedPersisted(_ projectId: String) {
        if appearancePreferences.collapsedProjectIds.contains(projectId) {
            appearancePreferences.collapsedProjectIds.remove(projectId)
        } else {
            appearancePreferences.collapsedProjectIds.insert(projectId)
        }
        if let idx = projects.firstIndex(where: { $0.id == projectId }) {
            projects[idx].isExpandedInHome = !appearancePreferences.collapsedProjectIds.contains(projectId)
        }
        saveAppearancePreferences()
    }

    public func setAppearanceMode(_ mode: AppAppearanceMode) {
        hasModifiedAppearanceModeInSession = true
        appearancePreferences.appearanceMode = mode
        preferencesStore.set(mode.rawValue, forKey: Self.appearanceModeDefaultsKey)
        saveAppearancePreferences()
    }

    public func saveAppearancePreferences() {
        let snapshot = appearancePreferences
        preferencesStore.set(snapshot.appearanceMode.rawValue, forKey: Self.appearanceModeDefaultsKey)
        let storeRef = projectionStore
        Task {
            await storeRef.saveAppearancePreferences(snapshot)
        }
    }

    public func loadPersistedV233Preferences() async {
        if var prefs = await projectionStore.loadAppearancePreferences() {
            if hasModifiedAppearanceModeInSession {
                prefs.appearanceMode = appearancePreferences.appearanceMode
            } else {
                preferencesStore.set(prefs.appearanceMode.rawValue, forKey: Self.appearanceModeDefaultsKey)
            }
            appearancePreferences = prefs
            for idx in projects.indices {
                projects[idx].isExpandedInHome = !prefs.collapsedProjectIds.contains(projects[idx].id)
            }
        }
        if let quota = await projectionStore.loadUsageQuota() {
            usageQuota = quota
        }
        if let custom = await projectionStore.loadCustomizations() {
            customizations = custom
        }
    }


    // MARK: - Live Artifacts, Diff Hydration & Git VCS (Stage / Unstage / Discard / Commit / Push / Quote)

    public func loadLiveArtifactsAndDiffs(for cascadeId: String? = nil) async {
        guard !isVerificationMode, let client = rpcClient else { return }
        let cid = cascadeId ?? activeCascadeId
        guard !cid.isEmpty else { return }

        if let snapshots = try? await client.getArtifactSnapshots(cascadeId: cid), !snapshots.isEmpty {
            activeArtifacts = snapshots
            if !snapshots.contains(where: { $0.artifactPath == selectedArtifactPath }) {
                selectedArtifactPath = snapshots[0].artifactPath
            }
        }
        do {
            let diffs = try await client.getTurnDiff(
                cascadeId: cid,
                turnNumber: diffCompareMode == .turn ? selectedDiffTurn : nil,
                compareMode: diffCompareMode
            )
            if !diffs.isEmpty || (hasPairedBackend || isLiveBackendConnected) {
                activeTurnDiffs = diffs
                selectedDiffFileIndex = min(selectedDiffFileIndex, max(0, diffs.count - 1))
            }
            await refreshHostCapabilitiesFromClient()
        } catch {
            await refreshHostCapabilitiesFromClient()
        }
    }

    public func setDiffCompareMode(_ mode: DiffCompareMode) {
        diffCompareMode = mode
        if !isVerificationMode && (hasPairedBackend || isLiveBackendConnected) {
            Task { [weak self] in
                await self?.loadLiveArtifactsAndDiffs()
            }
        }
    }

    public func toggleStageDiffFile(at index: Int? = nil) {
        let idx = index ?? selectedDiffFileIndex
        guard activeTurnDiffs.indices.contains(idx) else { return }
        let previousStaged = activeTurnDiffs[idx].isStaged
        activeTurnDiffs[idx].isStaged.toggle()
        let filePath = activeTurnDiffs[idx].filePath
        let nowStaged = activeTurnDiffs[idx].isStaged
        let cid = activeCascadeId
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
        guard let clientRef = rpcClient else { return }
        Task { [weak self] in
            do {
                if nowStaged {
                    try await clientRef.gitStageFile(cascadeId: cid, filePath: filePath)
                } else {
                    try await clientRef.gitUnstageFile(cascadeId: cid, filePath: filePath)
                }
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let revertIdx = self.activeTurnDiffs.firstIndex(where: { $0.filePath == filePath }) {
                    self.activeTurnDiffs[revertIdx].isStaged = previousStaged
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .gitVcs,
                    fallbackActionLabel: nowStaged ? "Staging file" : "Unstaging file"
                )
            }
        }
    }

    public func discardDiffFile(at index: Int? = nil) {
        let idx = index ?? selectedDiffFileIndex
        guard activeTurnDiffs.indices.contains(idx) else { return }
        let removed = activeTurnDiffs.remove(at: idx)
        let previousSelected = selectedDiffFileIndex
        selectedDiffFileIndex = min(selectedDiffFileIndex, max(0, activeTurnDiffs.count - 1))
        let cid = activeCascadeId
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
        guard let clientRef = rpcClient else { return }
        Task { [weak self] in
            do {
                try await clientRef.gitDiscardFile(cascadeId: cid, filePath: removed.filePath)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if !self.activeTurnDiffs.contains(where: { $0.filePath == removed.filePath }) {
                    let restoreIdx = min(idx, self.activeTurnDiffs.count)
                    self.activeTurnDiffs.insert(removed, at: restoreIdx)
                    self.selectedDiffFileIndex = min(previousSelected, max(0, self.activeTurnDiffs.count - 1))
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .gitVcs,
                    fallbackActionLabel: "Discarding file changes"
                )
            }
        }
    }

    public func commitDiffChanges() async -> GitCommitResult? {
        let message = gitCommitDraft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }
        let draft = gitCommitDraft
        let cid = activeCascadeId
        let branch = activeSummary?.branchName ?? "main"
        return await performLiveCapabilityWrite(
            capability: .gitVcs,
            actionLabel: "Git commit",
            offlineResult: {
                GitCommitResult(
                    commitSha: String(UUID().uuidString.prefix(7)).lowercased(),
                    commitMessage: message,
                    branchName: branch,
                    pushed: false
                )
            },
            remote: { client in
                try await client.gitCommitChanges(cascadeId: cid, draft: draft)
            },
            onSuccess: { result in
                self.lastCommitResult = result
                self.gitCommitDraft.message = ""
                if draft.includeUnstaged {
                    self.activeTurnDiffs.removeAll()
                } else {
                    self.activeTurnDiffs.removeAll(where: \.isStaged)
                }
                self.selectedDiffFileIndex = 0
            }
        )
    }

    public func pushCurrentDiffBranch() async -> Bool {
        let cid = activeCascadeId
        let branch = activeSummary?.branchName ?? "main"
        return await performLiveCapabilityWrite(
            capability: .gitVcs,
            actionLabel: "Git push",
            offlineResult: { true },
            remote: { client in
                try await client.gitPushBranch(cascadeId: cid, branchName: branch)
            },
            onSuccess: { pushed in
                if pushed, var last = self.lastCommitResult {
                    last.pushed = true
                    self.lastCommitResult = last
                }
            }
        ) ?? false
    }

    public func quoteDiffLinesToComposer(filePath: String, startLine: Int, endLine: Int, snippet: String) {
        let fileName = (filePath as NSString).lastPathComponent
        let rangeLabel = startLine == endLine ? "L\(startLine)" : "L\(startLine)-L\(endLine)"
        let chip = ComposerAttachmentChip(
            kind: .codeQuote,
            label: "\(fileName):\(rangeLabel)",
            targetUri: "\(filePath)#\(rangeLabel)"
        )
        if !composerAttachments.contains(where: { $0.targetUri == chip.targetUri }) {
            composerAttachments.append(chip)
        }
        let cleanSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSnippet.isEmpty {
            let prefix = composerDraftText.isEmpty ? "" : "\n"
            composerDraftText += "\(prefix)Regarding `\(fileName):\(rangeLabel)`:\n```\n\(cleanSnippet)\n```\n"
        }
        activeRoute = .cascadeChat(activeCascadeId)
    }

    public func addImageRegionComment(_ comment: ImageRegionComment) {
        imageRegionComments.append(comment)
    }


    // MARK: - Customizations Hub (Skills, Rules, MCP Servers, Plugins Marketplace, Hooks)

    public func refreshCustomizations() async {
        guard let client = rpcClient, (hasPairedBackend || isLiveBackendConnected) else { return }
        do {
            let fetched = try await client.fetchCustomizationsCatalog()
            customizations = fetched
            await projectionStore.saveCustomizations(fetched)
            await refreshHostCapabilitiesFromClient()
        } catch {
            await refreshHostCapabilitiesFromClient()
        }
    }

    public func restartMcpServer(_ serverName: String) {
        let previousServer = customizations.mcpServers.first(where: { $0.name == serverName })
        if let idx = customizations.mcpServers.firstIndex(where: { $0.name == serverName }) {
            customizations.mcpServers[idx].state = .connected
            customizations.mcpServers[idx].errorMessage = nil
        }
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
        guard let clientRef = rpcClient else { return }
        Task { [weak self] in
            do {
                try await clientRef.restartMcpServer(serverName: serverName)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let prev = previousServer,
                   let idx = self.customizations.mcpServers.firstIndex(where: { $0.name == serverName }) {
                    self.customizations.mcpServers[idx] = prev
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .customizationsCatalog,
                    fallbackActionLabel: "Restarting MCP server"
                )
            }
        }
    }

    public func togglePlugin(_ pluginId: String, isEnabled: Bool) {
        let previousPlugin = customizations.plugins.first(where: { $0.id == pluginId })
        if let idx = customizations.plugins.firstIndex(where: { $0.id == pluginId }) {
            customizations.plugins[idx].isEnabled = isEnabled
        }
        let snapshot = customizations
        let storeRef = projectionStore
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
        let clientRef = rpcClient
        Task { [weak self] in
            await storeRef.saveCustomizations(snapshot)
            guard let clientRef else { return }
            do {
                try await clientRef.togglePlugin(pluginId: pluginId, isEnabled: isEnabled)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let prev = previousPlugin,
                   let idx = self.customizations.plugins.firstIndex(where: { $0.id == pluginId }) {
                    self.customizations.plugins[idx] = prev
                    await storeRef.saveCustomizations(self.customizations)
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .customizationsCatalog,
                    fallbackActionLabel: "Updating plugin"
                )
            }
        }
    }

    public func installPlugin(_ pluginId: String) {
        let previousPlugin = customizations.plugins.first(where: { $0.id == pluginId })
        if let idx = customizations.plugins.firstIndex(where: { $0.id == pluginId }) {
            customizations.plugins[idx].isInstalled = true
            customizations.plugins[idx].isEnabled = true
        }
        let snapshot = customizations
        let storeRef = projectionStore
        let isLive = !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
        let clientRef = rpcClient
        Task { [weak self] in
            await storeRef.saveCustomizations(snapshot)
            guard let clientRef else { return }
            do {
                try await clientRef.installMarketplacePlugin(pluginId: pluginId)
                await self?.refreshHostCapabilitiesFromClient()
            } catch {
                guard let self, isLive else { return }
                if let prev = previousPlugin,
                   let idx = self.customizations.plugins.firstIndex(where: { $0.id == pluginId }) {
                    self.customizations.plugins[idx] = prev
                    await storeRef.saveCustomizations(self.customizations)
                }
                await self.handleLiveCapabilityWriteError(
                    error,
                    capability: .customizationsCatalog,
                    fallbackActionLabel: "Installing plugin"
                )
            }
        }
    }


    // MARK: - Live Activity & Share Extension Shared Bridge Reconciliation

    public func consumePendingLiveActivityActions() async {
        let actions = await SharedAppGroupBridge.shared.drainLiveActivityActions()
        guard !actions.isEmpty else { return }
        for action in actions {
            if !action.cascadeId.isEmpty {
                activeCascadeId = action.cascadeId
            }
            switch action.kind {
            case .approveWithFaceID:
                approveWaitingCommandWithFaceID(stepIndex: action.stepIndex > 0 ? action.stepIndex : nil)
            case .deny:
                denyWaitingCommand(stepIndex: action.stepIndex > 0 ? action.stepIndex : nil)
            case .stopTurn:
                stopActiveCascadeStreaming()
            }
        }
    }

    public func consumePendingSharePayload(id: String? = nil) async -> Bool {
        guard let payload = await SharedAppGroupBridge.shared.consumeSharePayload(id: id) else {
            return false
        }
        var parts: [String] = []
        if !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(payload.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let urlStr = payload.urlString, !urlStr.isEmpty {
            parts.append(urlStr)
            composerAttachments.append(
                ComposerAttachmentChip(kind: .genericFile, label: urlStr, targetUri: urlStr)
            )
        }
        if let fname = payload.fileName, !fname.isEmpty {
            composerAttachments.append(
                ComposerAttachmentChip(kind: .genericFile, label: fname, targetUri: "share://\(fname)")
            )
        }
        let joined = parts.joined(separator: "\n")
        if !joined.isEmpty {
            composerDraftText = composerDraftText.isEmpty ? joined : "\(composerDraftText)\n\(joined)"
        }
        if activeCascadeId.isEmpty, let first = summaries.first {
            activeCascadeId = first.cascadeId
        }
        if !activeCascadeId.isEmpty {
            activeRoute = .cascadeChat(activeCascadeId)
        }
        return true
    }

    /// Evaluates NotificationPolicy on a status transition and emits a local notification payload when eligible.
    public func evaluateNotificationTransition(
        cascadeId: String,
        title: String,
        previousStatus: CortexStepStatus,
        newStatus: CortexStepStatus
    ) {
        let wasManualStop = manuallyCancelledCascadeIds.contains(cascadeId)
        if NotificationPolicy.shouldNotify(
            previousStatus: previousStatus,
            newStatus: newStatus,
            wasManuallyCancelled: wasManualStop,
            preferences: appearancePreferences
        ) {
            let body: String
            switch newStatus {
            case .waiting: body = "Approval or input required in \(title)"
            case .done: body = "Agent finished working on \(title)"
            case .error: body = "Run encountered an error in \(title)"
            default: body = "Status updated in \(title)"
            }
            lastNotificationEvent = (id: UUID().uuidString, title: title, body: body, cascadeId: cascadeId)
        }
    }

}
