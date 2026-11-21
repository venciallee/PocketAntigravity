import Foundation

/// Summary push streams, federated host/workspace synchronization, heartbeat, offline backoff, and step polling.
extension AntigravitySessionStore {
    internal func ensureSummaryEnvelopeStreamRunning() {
        guard !isVerificationMode, !isNetworkingSuspended, isDeviceNetworkReachable else { return }
        guard let client = rpcClient else { return }

        if localSummaryStreamTasks.isEmpty && cloudSummaryStreamTask == nil {
            let sinceLastOpen = Date().timeIntervalSince(lastStreamReopenAttemptAt)
            guard sinceLastOpen >= ConnectionPowerPolicy.minStreamReopenSpacingSeconds else { return }
            lastStreamReopenAttemptAt = Date()
        }

        let localTargets: [(key: String, uuid: String?, hostName: String)] = {
            if activeHost.channel == .cloudRelay {
                let reachable = availableRelayInstances.filter(\.status.isReachable)
                if !reachable.isEmpty {
                    return reachable.map { ($0.uuid, $0.uuid, $0.name) }
                }
                if !activeHost.instanceId.isEmpty && activeHost.instanceId != "unpaired" {
                    return [(activeHost.instanceId, activeHost.instanceId, activeHost.hostname)]
                }
                return []
            }
            return [("direct", nil, activeHost.hostname)]
        }()

        // Cancel local streams for instances that are no longer reachable
        let activeTargetKeys = Set(localTargets.map(\.key))
        for (existingKey, existingTask) in localSummaryStreamTasks where !activeTargetKeys.contains(existingKey) {
            existingTask.cancel()
            localSummaryStreamTasks.removeValue(forKey: existingKey)
        }
        if localSummaryStreamTasks.isEmpty {
            hasReceivedLocalStreamEvent = false
        }

        let generation = self.summaryStreamGeneration

        for target in localTargets where localSummaryStreamTasks[target.key] == nil {
            let targetKey = target.key
            let targetUuid = target.uuid
            let targetHostName = target.hostName
            localSummaryStreamTasks[targetKey] = Task { [weak self] in
                guard let stream = try? await client.subscribeEnvelopeStream(
                    method: "JetboxSubscribeToSummaries",
                    instanceUuidOverride: targetUuid
                ) else {
                    if let self, self.summaryStreamGeneration == generation {
                        self.localSummaryStreamTasks.removeValue(forKey: targetKey)
                        if self.localSummaryStreamTasks.isEmpty {
                            self.hasReceivedLocalStreamEvent = false
                        }
                    }
                    return
                }
                do {
                    for try await event in stream {
                        guard let self, !Task.isCancelled, self.summaryStreamGeneration == generation else { break }
                        self.hasReceivedLocalStreamEvent = true
                        self.lastBackendActivityAt = Date()
                        self.applyJetboxSummaryEvent(
                            event,
                            forceCloud: false,
                            originInstanceUuid: targetUuid,
                            originHostName: targetHostName
                        )
                    }
                    if let self, self.summaryStreamGeneration == generation {
                        self.localSummaryStreamTasks.removeValue(forKey: targetKey)
                        if self.localSummaryStreamTasks.isEmpty {
                            self.hasReceivedLocalStreamEvent = false
                        }
                    }
                } catch {
                    // Clear dead stream reference BEFORE running passive probe so it can reopen cleanly
                    if let self, self.summaryStreamGeneration == generation {
                        self.localSummaryStreamTasks.removeValue(forKey: targetKey)
                        if self.localSummaryStreamTasks.isEmpty {
                            self.hasReceivedLocalStreamEvent = false
                        }
                        if !Task.isCancelled,
                           !self.isNetworkingSuspended,
                           self.isDeviceNetworkReachable,
                           self.isLiveBackendConnected {
                            await self.performLightweightHeartbeatTick(allowFullReconciliation: false)
                        }
                    }
                }
            }
        }

        if cloudSummaryStreamTask == nil {
            cloudSummaryStreamTask = Task { [weak self] in
                let cloudTargetUuid: String? = {
                    guard let self else { return nil }
                    return self.activeHost.channel == .cloudRelay ? self.activeHost.instanceId : nil
                }()
                let resolvedCloudTarget: String?
                if cloudTargetUuid != nil {
                    resolvedCloudTarget = await client.currentPreferredCloudInstanceUuid() ?? cloudTargetUuid
                } else {
                    resolvedCloudTarget = nil
                }

                let payloads: [[String: JSONValue]] = [
                    ["backend": .string("BACKEND_TYPE_REMOTE_AICODE")],
                    ["backendType": .string("BACKEND_TYPE_REMOTE_AICODE")]
                ]
                for (idx, payload) in payloads.enumerated() {
                    guard !Task.isCancelled else { break }
                    guard let stream = try? await client.subscribeEnvelopeStream(
                        method: "JetboxSubscribeToSummaries",
                        requestPayload: payload,
                        instanceUuidOverride: resolvedCloudTarget
                    ) else {
                        break
                    }
                    do {
                        for try await event in stream {
                            guard let self, !Task.isCancelled, self.summaryStreamGeneration == generation else { break }
                            self.hasReceivedCloudStreamEvent = true
                            self.lastBackendActivityAt = Date()
                            self.applyJetboxSummaryEvent(
                                event,
                                forceCloud: true,
                                originInstanceUuid: resolvedCloudTarget,
                                originHostName: "Antigravity"
                            )
                        }
                        break
                    } catch let AntigravityRPCError.httpError(_, body)
                        where idx == 0 && body.lowercased().contains("unknown field \"backend\"") {
                        continue
                    } catch {
                        break
                    }
                }
                if let self, self.summaryStreamGeneration == generation {
                    self.cloudSummaryStreamTask = nil
                    self.hasReceivedCloudStreamEvent = false
                }
            }
        }
    }

    /// Subscribes to Connect-RPC 5-byte framed `JetboxSubscribeToSummaries` stream (Local & Cloud)
    /// AND runs a power-aware foreground scheduler:
    /// - Screen off / background (`isNetworkingSuspended`): zero streams, zero timers, zero radio wakeups.
    /// - iPhone no network (`!isDeviceNetworkReachable`): zero requests until `NWPathMonitor` reports recovery.
    /// - Online idle: relies on push stream + lightweight single-RPC heartbeat (`30s–60s` Relay / `15s–30s` LAN).
    /// - Host offline: exponential backoff with jitter (`3s → 6s → 12s → 24s → 45s → 60s`, ×2 in Low Power Mode).
    public func startSummarySubscriptionStream() {
        cancelAllSummaryStreams()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil

        guard !isVerificationMode, !isNetworkingSuspended else { return }
        guard rpcClient != nil else { return }

        startNetworkPathMonitoringIfNeeded()
        guard isDeviceNetworkReachable else {
            connectionLifecyclePhase = .noNetwork
            connectionStatusText = "No Internet Connection"
            return
        }

        if isLiveBackendConnected && activeHost.isOnline {
            lastStreamReopenAttemptAt = .distantPast
            ensureSummaryEnvelopeStreamRunning()
            connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
        }

        summaryPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let sleepSeconds: TimeInterval? = {
                    guard let self,
                          !self.isNetworkingSuspended,
                          self.isDeviceNetworkReachable,
                          (self.hasPairedBackend || self.isLiveBackendConnected) else {
                        return nil
                    }
                    let isLowPower = self.isLowPowerModeEnabled
                    if self.isLiveBackendConnected && self.activeHost.isOnline {
                        let heartbeatInterval = ConnectionPowerPolicy.onlineHeartbeatInterval(
                            channel: self.activeHost.channel,
                            isLowPowerMode: isLowPower,
                            isExpensiveNetwork: self.isNetworkExpensiveOrConstrained,
                            isStreamHealthy: self.isSummaryStreamHealthy
                        )
                        let elapsedSinceActivity = Date().timeIntervalSince(self.lastBackendActivityAt)
                        return max(2.0, heartbeatInterval - elapsedSinceActivity)
                    } else {
                        let attempt = self.reconnectAttemptCount
                        let delaySeconds = ConnectionPowerPolicy.offlineBackoffDelay(
                            attempt: attempt,
                            isLowPowerMode: isLowPower,
                            applyJitter: true
                        )
                        self.nextReconnectAt = Date().addingTimeInterval(delaySeconds)
                        self.connectionLifecyclePhase = .offlineBackoff(
                            attempt: attempt,
                            nextRetrySeconds: delaySeconds
                        )
                        return delaySeconds
                    }
                }()
                guard let sleepSeconds else { break }

                try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                guard let self,
                      !Task.isCancelled,
                      !self.isNetworkingSuspended,
                      self.isDeviceNetworkReachable,
                      (self.hasPairedBackend || self.isLiveBackendConnected) else {
                    break
                }

                if self.isLiveBackendConnected && self.activeHost.isOnline {
                    let streamHealthy = self.isSummaryStreamHealthy
                    let heartbeatInterval = ConnectionPowerPolicy.onlineHeartbeatInterval(
                        channel: self.activeHost.channel,
                        isLowPowerMode: self.isLowPowerModeEnabled,
                        isExpensiveNetwork: self.isNetworkExpensiveOrConstrained,
                        isStreamHealthy: streamHealthy
                    )
                    let fullSyncInterval = ConnectionPowerPolicy.onlineFullSyncInterval(
                        channel: self.activeHost.channel,
                        isLowPowerMode: self.isLowPowerModeEnabled
                    )
                    let needsFullSync = Date().timeIntervalSince(self.lastFullSyncAt) >= fullSyncInterval
                        || !streamHealthy
                    let refreshedElapsed = Date().timeIntervalSince(self.lastBackendActivityAt)

                    // Skip redundant heartbeat if push events or user RPCs already proved liveness recently
                    if refreshedElapsed < heartbeatInterval * 0.8 && !needsFullSync {
                        continue
                    }

                    await self.performLightweightHeartbeatTick(allowFullReconciliation: needsFullSync)
                } else {
                    let recovered = await self.performOfflineRecoveryProbe()
                    if !recovered {
                        self.reconnectAttemptCount = min(
                            self.reconnectAttemptCount + 1,
                            ConnectionPowerPolicy.offlineBackoffScheduleSeconds.count
                        )
                    }
                }
            }
        }
    }

    internal func syncRelayInstancesToHosts(
        _ relayInstances: [RelayInstanceInfo],
        latencyMs: Int? = nil,
        preferredActiveInstance: RelayInstanceInfo? = nil
    ) {
        guard !relayInstances.isEmpty else { return }
        availableRelayInstances = relayInstances

        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
        let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
        let effectiveLatency = latencyMs ?? lastPingLatencyMs ?? activeHost.latencyMs
        let seenIds = Set(relayInstances.map(\.uuid))

        for inst in relayInstances {
            let instURL = URL(string: "\(originPrefix)/r/\(inst.uuid)") ?? activeHost.endpointURL
            let peerHost = RemoteHostInstance(
                instanceId: inst.uuid,
                hostname: inst.name,
                version: inst.version,
                channel: .cloudRelay,
                endpointURL: instURL,
                isOnline: inst.status.isReachable,
                latencyMs: effectiveLatency
            )
            if let idx = hosts.firstIndex(where: { $0.instanceId == inst.uuid }) {
                hosts[idx] = peerHost
                hosts.removeAll {
                    $0.channel == .cloudRelay && $0.instanceId != inst.uuid && $0.instanceId == inst.name
                }
            } else if let slugIdx = hosts.firstIndex(where: { $0.channel == .cloudRelay && $0.instanceId == inst.name }) {
                hosts[slugIdx] = peerHost
            } else {
                hosts.append(peerHost)
            }
        }

        // Any previously cached Cloud Relay device absent from the latest ListInstances snapshot is no longer online
        for idx in hosts.indices where hosts[idx].channel == .cloudRelay && !seenIds.contains(hosts[idx].instanceId) {
            hosts[idx].isOnline = false
        }

        if let activeInst = preferredActiveInstance {
            let nextURL = URL(string: "\(originPrefix)/r/\(activeInst.uuid)") ?? activeHost.endpointURL
            let refreshedHost = RemoteHostInstance(
                instanceId: activeInst.uuid,
                hostname: activeInst.name,
                version: activeInst.version,
                channel: .cloudRelay,
                endpointURL: nextURL,
                isOnline: activeInst.status.isReachable,
                latencyMs: effectiveLatency
            )
            activeHost = refreshedHost
            if let idx = hosts.firstIndex(where: { $0.instanceId == refreshedHost.instanceId }) {
                hosts[idx] = refreshedHost
            } else {
                hosts.insert(refreshedHost, at: 0)
            }
        } else if activeHost.channel == .cloudRelay,
                  let matchedActive = relayInstances.first(where: { $0.uuid == activeHost.instanceId }) {
            var updatedActive = activeHost
            updatedActive.hostname = matchedActive.name
            updatedActive.version = matchedActive.version
            updatedActive.isOnline = matchedActive.status.isReachable
            updatedActive.latencyMs = effectiveLatency
            activeHost = updatedActive
        }
    }

    internal func applyRelayProbeMetadata(_ probe: HostReachabilityProbeResult) {
        lastPingLatencyMs = probe.latencyMs
        if !probe.availableRelayInstances.isEmpty {
            syncRelayInstancesToHosts(
                probe.availableRelayInstances,
                latencyMs: probe.latencyMs,
                preferredActiveInstance: probe.activeRelayInstance
            )
        } else if let activeInst = probe.activeRelayInstance {
            let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
            let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
            let nextURL = URL(string: "\(originPrefix)/r/\(activeInst.uuid)") ?? activeHost.endpointURL
            let refreshedHost = RemoteHostInstance(
                instanceId: activeInst.uuid,
                hostname: activeInst.name,
                version: activeInst.version,
                channel: .cloudRelay,
                endpointURL: nextURL,
                isOnline: activeInst.status.isReachable,
                latencyMs: probe.latencyMs
            )
            activeHost = refreshedHost
            if let idx = hosts.firstIndex(where: { $0.instanceId == refreshedHost.instanceId }) {
                hosts[idx] = refreshedHost
            } else {
                hosts.insert(refreshedHost, at: 0)
            }
        } else {
            var updatedHost = activeHost
            updatedHost.latencyMs = probe.latencyMs
            updatedHost.isOnline = true
            activeHost = updatedHost
            if let idx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
                hosts[idx] = updatedHost
            }
        }
        connectionStatusText = "Connected · \(activeHost.hostname) · \(probe.latencyMs)ms"
    }

    internal func performLightweightHeartbeatTick(allowFullReconciliation: Bool) async {
        guard !isNetworkingSuspended, isDeviceNetworkReachable, let client = rpcClient else { return }
        let isRelay = (activeHost.channel == .cloudRelay)
        let probeTimeout: TimeInterval = isRelay ? 8.0 : 3.0

        do {
            let probe = try await client.probeHostReachability(timeoutInterval: probeTimeout)
            consecutiveSyncFailures = 0
            reconnectAttemptCount = 0
            nextReconnectAt = nil
            lastBackendActivityAt = Date()
            applyRelayProbeMetadata(probe)

            if !isLiveBackendConnected || !activeHost.isOnline {
                markBackendReconnected()
            } else {
                connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
            }

            if probe.relayTopologyChanged {
                cancelAllSummaryStreams()
                lastStreamReopenAttemptAt = .distantPast
                ensureSummaryEnvelopeStreamRunning()
                await refreshWorkspacesAndSummaries(forceFullSync: true, includeAutomations: false)
            } else {
                let missingLocalStream = localSummaryStreamTasks.isEmpty
                    || (isRelay && availableRelayInstances.contains { $0.status.isReachable && localSummaryStreamTasks[$0.uuid] == nil })
                let missingCloudStream = (cloudSummaryStreamTask == nil)
                if missingLocalStream || missingCloudStream {
                    ensureSummaryEnvelopeStreamRunning()
                }
                if allowFullReconciliation {
                    await refreshWorkspacesAndSummaries(forceFullSync: false, includeAutomations: false)
                }
            }
        } catch {
            if Self.isBackendOfflineError(error) {
                consecutiveSyncFailures += 1
                let threshold = ConnectionPowerPolicy.offlineFailureThreshold(
                    channel: activeHost.channel,
                    error: error
                )
                if consecutiveSyncFailures >= threshold {
                    markBackendOffline(error: error)
                }
            }
        }
    }

    internal func performOfflineRecoveryProbe() async -> Bool {
        guard !isNetworkingSuspended, isDeviceNetworkReachable, let client = rpcClient else { return false }
        let isRelay = (activeHost.channel == .cloudRelay)
        let probeTimeout: TimeInterval = isRelay ? 8.0 : 3.0

        do {
            let probe = try await client.probeHostReachability(timeoutInterval: probeTimeout)
            applyRelayProbeMetadata(probe)
            markBackendReconnected()
            await refreshWorkspacesAndSummaries(
                forceFullSync: true,
                includeAutomations: selectedTab == .automations
            )
            return true
        } catch {
            if Self.isBackendOfflineError(error) {
                connectionErrorText = error.localizedDescription
                if case AntigravityRPCError.unauthorized = error {
                    // Auth expired requires user re-sign-in; immediately cap backoff to avoid noisy 401 retries
                    reconnectAttemptCount = ConnectionPowerPolicy.offlineBackoffScheduleSeconds.count
                    connectionStatusText = isRelay ? "Google Sign-In Expired" : "Offline · \(activeHost.hostname) (Auth Expired)"
                } else {
                    connectionStatusText = "Offline · \(activeHost.hostname)"
                }
            }
            return false
        }
    }

    /// Handles both Antigravity 2.0.11+ `{"updates": {"<cascadeId>": {...}}, "deletes": [...]}` frames
    /// and single-cascade `{"cascadeId": "...", "status": "..."}` frames.
    internal func applyJetboxSummaryEvent(
        _ event: [String: JSONValue],
        forceCloud: Bool = false,
        originInstanceUuid: String? = nil,
        originHostName: String? = nil
    ) {
        var changedIds = Set<String>()
        let existingCloudProjects = projects.filter { $0.runtime == .cloud }
        let cloudProjById: [String: ProjectWorkspace] = Dictionary(
            existingCloudProjects.map { cp in (cp.cloudProjectId ?? cp.id, cp) },
            uniquingKeysWith: { first, _ in first }
        )

        let effectiveOriginUuid = originInstanceUuid ?? activeHost.instanceId
        let effectiveOriginHost = forceCloud ? "Antigravity" : (originHostName ?? activeHost.hostname)

        let decodedBatch = AntigravityRPCClient.decodeJetboxSummariesEvent(
            event,
            forceCloud: forceCloud,
            originInstanceUuid: effectiveOriginUuid,
            originHostName: effectiveOriginHost,
            cloudProjectsById: cloudProjById
        )
        if !decodedBatch.upserts.isEmpty {
            let now = Date()
            for decoded in decodedBatch.upserts {
                let cid = decoded.cascadeId
                changedIds.insert(cid)
                if let idx = summaries.firstIndex(where: { $0.cascadeId == cid }) {
                    let existing = summaries[idx]
                    let prevStepCount = existing.stepCount
                    var merged = decoded
                    if existing.title != "New Conversation" && merged.title == "New Conversation" {
                        merged.title = existing.title
                    }
                    if existing.isCloud && !merged.isCloud {
                        merged.isCloud = true
                        merged.originHostName = "Antigravity"
                    }
                    merged.isPinned = existing.isPinned || decoded.isPinned
                    merged.isArchived = existing.isArchived || decoded.isArchived
                    merged.stepCount = max(prevStepCount, decoded.stepCount)
                    merged.currentStepIndex = max(1, merged.stepCount)
                    merged.totalSteps = max(1, merged.stepCount)
                    merged.cloudProjectId = decoded.cloudProjectId ?? existing.cloudProjectId

                    // Prevent a different peer window's stale IDLE snapshot from clobbering an active run at equal stepCount
                    let sameOrigin = (decoded.originInstanceUuid == nil)
                        || (existing.originInstanceUuid == nil)
                        || (decoded.originInstanceUuid == existing.originInstanceUuid)
                    if !sameOrigin
                        && decoded.stepCount <= prevStepCount
                        && (existing.status == .inProgress || existing.status == .pending || existing.status == .waiting || existing.status == .blocked)
                        && (merged.status == .unspecified || merged.status == .done) {
                        merged.status = existing.status
                        merged.originInstanceUuid = existing.originInstanceUuid
                        merged.originHostName = existing.originHostName
                    }

                    if let optimisticExpiry = optimisticActiveUntilByCascadeId[cid],
                       optimisticExpiry > now,
                       merged.status != .waiting && merged.status != .blocked && merged.status != .error {
                        merged.status = .inProgress
                    }

                    let latestViewed = [existing.lastUserViewTime, decoded.lastUserViewTime].compactMap { $0 }.max()
                    merged.lastUserViewTime = latestViewed

                    let hasNewActivity = merged.stepCount > prevStepCount
                        || decoded.updatedAt.timeIntervalSince(existing.updatedAt) > 0.5
                    if hasNewActivity {
                        if activeRoute != .cascadeChat(cid) {
                            merged.isUnread = (merged.status != .inProgress && merged.status != .pending)
                            locallyViewedAtByCascadeId.removeValue(forKey: cid)
                        } else {
                            merged.isUnread = false
                            locallyViewedAtByCascadeId[cid] = now
                        }
                    } else if merged.status == .inProgress || merged.status == .pending {
                        merged.isUnread = false
                    } else if let latestViewed {
                        merged.isUnread = merged.updatedAt.timeIntervalSince(latestViewed) > 0.5
                            || merged.status == .waiting
                            || merged.status == .blocked
                    } else {
                        merged.isUnread = decoded.isUnread || existing.isUnread
                    }

                    if let localViewed = locallyViewedAtByCascadeId[cid], merged.updatedAt <= localViewed {
                        merged.isUnread = false
                    }

                    merged.statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                        status: merged.status,
                        stepCount: merged.stepCount,
                        isUnread: merged.isUnread
                    )
                    summaries[idx] = merged
                } else {
                    var fresh = decoded
                    if let localViewed = locallyViewedAtByCascadeId[cid], fresh.updatedAt <= localViewed {
                        fresh.isUnread = false
                        fresh.statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                            status: fresh.status,
                            stepCount: fresh.stepCount,
                            isUnread: false
                        )
                    }
                    summaries.insert(fresh, at: 0)
                }
            }

            var byIdMap: [String: CascadeSummary] = Dictionary(
                summaries.map { ($0.cascadeId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            AntigravityRPCClient.reconcileBatchUnreadStates(&byIdMap, now: now)
            for idx in summaries.indices {
                if let reconciled = byIdMap[summaries[idx].cascadeId] {
                    if let localViewed = locallyViewedAtByCascadeId[reconciled.cascadeId],
                       reconciled.updatedAt <= localViewed {
                        continue
                    }
                    summaries[idx] = reconciled
                }
            }

            var updatedSummaries = summaries.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.cascadeId < rhs.cascadeId
            }
            projects = Self.reconcileLiveProjects(
                workspaces: workspaces,
                summaries: &updatedSummaries,
                existingProjects: projects,
                hostName: activeHost.hostname,
                cloudProjects: existingCloudProjects
            )
            summaries = updatedSummaries
        }

        if !decodedBatch.deletes.isEmpty {
            let deletedIds = Set(decodedBatch.deletes)
            summaries.removeAll { deletedIds.contains($0.cascadeId) }
        }

        if let cid = event["cascadeId"]?.stringValue {
            changedIds.insert(cid)
            let statusRaw = event["status"]?.stringValue ?? "CORTEX_STEP_STATUS_IN_PROGRESS"
            let newStatus = CortexStepStatus.from(jsonName: statusRaw)
            let stepCount = event["stepCount"]?.intValue
            let title = event["title"]?.stringValue
            if let idx = summaries.firstIndex(where: { $0.cascadeId == cid }) {
                summaries[idx].status = newStatus
                if let stepCount { summaries[idx].stepCount = stepCount }
                if let title, !title.isEmpty { summaries[idx].title = title }
                summaries[idx].updatedAt = Date()
                summaries[idx].relativeTimeLabel = "now"
                summaries[idx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                    status: newStatus,
                    stepCount: summaries[idx].stepCount,
                    isUnread: summaries[idx].isUnread,
                    explicitSubtitle: event["summary"]?.stringValue
                )
            }
        }

        if isLiveBackendConnected && activeHost.isOnline {
            connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
        }

        if !activeCascadeId.isEmpty && changedIds.contains(activeCascadeId) {
            syncStepsForCascade(activeCascadeId, pollUntilIdle: activeRoute == .cascadeChat(activeCascadeId))
        }
    }

    /// Reconciles summary streaming state from fetched trajectory steps without prematurely flipping
    /// an active turn to `.done` while the agent is preparing its first step or thinking between tool calls.
    public static func reconcileSummaryStreamingStatus(
        currentStatus: CortexStepStatus,
        remoteSteps: [CascadeStep],
        withinOptimisticSendWindow: Bool
    ) -> (status: CortexStepStatus, stillActive: Bool) {
        if remoteSteps.contains(where: { $0.status == .waiting || $0.status == .blocked }) {
            return (.waiting, false)
        }
        if remoteSteps.contains(where: { $0.status == .inProgress || $0.status == .pending }) {
            return (.inProgress, true)
        }
        if let lastStep = remoteSteps.last, (lastStep.status == .error || lastStep.status == .cancelled) {
            return (lastStep.status, false)
        }

        let lastUserIdx = remoteSteps.lastIndex(where: { $0.type == .userInput })
        let turnTail: ArraySlice<CascadeStep> = {
            if let lastUserIdx {
                return remoteSteps[(lastUserIdx + 1)...]
            }
            return remoteSteps[...]
        }()
        let hasCompletedAssistantReply = turnTail.contains { step in
            (step.type == .plannerResponse || step.type == .notifyUser)
                && step.status == .done
                && !(step.plannerResponse?.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let lastVisible = remoteSteps.last(where: { $0.hasRenderableChatContent }) ?? remoteSteps.last
        let endsMidTurn: Bool = {
            guard let lastVisible else { return remoteSteps.isEmpty }
            if lastVisible.status == .error || lastVisible.status == .cancelled {
                return false
            }
            switch lastVisible.type {
            case .userInput, .taskBoundary, .viewFile, .viewContentChunk, .search, .listDirectory, .codeAction:
                return true
            case .runCommand:
                return lastVisible.runCommand?.exitCode == nil || !hasCompletedAssistantReply
            default:
                return false
            }
        }()

        if withinOptimisticSendWindow && !hasCompletedAssistantReply {
            return (.inProgress, true)
        }
        if currentStatus == .inProgress || currentStatus == .pending {
            if hasCompletedAssistantReply && !endsMidTurn {
                return (.done, false)
            }
            if remoteSteps.isEmpty || endsMidTurn || !hasCompletedAssistantReply {
                return (.inProgress, true)
            }
            return (.done, false)
        }
        return (currentStatus, false)
    }

    /// Synchronizes `GetCascadeTrajectorySteps` (`stepOffset` JSON `<600`, Binary Protobuf `>=600`) for `cascadeId`.
    /// Polls adaptively ONLY while an agent turn is actively streaming (`500ms` LAN / `1.0s` Relay; slowed in Low Power Mode).
    /// When the conversation is idle and the push stream is healthy, stops polling completely (0 idle RPCs) and relies
    /// on `JetboxSubscribeToSummaries` to wake step sync on demand.
    public func syncStepsForCascade(_ cascadeId: String, pollUntilIdle: Bool = true) {
        stepPollingTask?.cancel()
        stepPollingTask = nil
        stepSyncGeneration &+= 1
        let generation = stepSyncGeneration
        guard !isNetworkingSuspended else { return }
        guard (hasPairedBackend || isLiveBackendConnected), let client = rpcClient, !cascadeId.isEmpty else { return }

        stepLoadErrorText = nil

        // Local optimistic IDs (`cas-<8hex>`) have not been materialized on the server via `StartCascade` yet.
        // Never show a stuck "Loading conversation history..." spinner or `not_found` error on them.
        if cascadeId.hasPrefix("cas-") && !Self.esddFixtureCascadeIds.contains(cascadeId) {
            isLoadingSteps = false
            return
        }

        if !isDeviceNetworkReachable {
            isLoadingSteps = false
            let storeRef = projectionStore
            if (stepsByCascadeId[cascadeId] ?? []).isEmpty {
                Task { [weak self] in
                    let cached = await storeRef.loadProjectedSteps(cascadeId: cascadeId)
                    if !cached.isEmpty, let self, (self.stepsByCascadeId[cascadeId] ?? []).isEmpty {
                        self.stepsByCascadeId[cascadeId] = cached
                    }
                }
            }
            return
        }

        let initialSummary = summaries.first(where: { $0.cascadeId == cascadeId })
        let withinInitialOptimisticSend = (optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
        let isBrandNewEmptySession = locallyCreatedEmptyCascadeIds.contains(cascadeId)
            && !withinInitialOptimisticSend
        let isKnownOfflineLocal = hasPairedBackend
            && (!isLiveBackendConnected || !activeHost.isOnline)
            && (initialSummary?.isCloud != true)

        if isBrandNewEmptySession && isKnownOfflineLocal {
            isLoadingSteps = false
            return
        }

        if (stepsByCascadeId[cascadeId] ?? []).isEmpty && !isBrandNewEmptySession {
            isLoadingSteps = true
        } else {
            isLoadingSteps = false
        }
        let storeRef = projectionStore

        stepPollingTask = Task { [weak self] in
            defer {
                if let self,
                   self.stepSyncGeneration == generation {
                    if self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                    }
                    self.stepPollingTask = nil
                }
            }
            if (self?.stepsByCascadeId[cascadeId] ?? []).isEmpty {
                let cached = await storeRef.loadProjectedSteps(cascadeId: cascadeId)
                    if !cached.isEmpty, let self, (self.stepsByCascadeId[cascadeId] ?? []).isEmpty {
                        self.stepsByCascadeId[cascadeId] = cached
                        self.harvestEmbedResources(from: cached)
                        if self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                            self.isLoadingSteps = false
                        }
                    }
            }

            var attempts = 0
            let maxAttempts = pollUntilIdle ? 10_000 : 1
            while !Task.isCancelled && attempts < maxAttempts {
                guard let self, !self.isNetworkingSuspended, self.isDeviceNetworkReachable else { break }
                attempts += 1
                let summaryMeta = self.summaries.first(where: { $0.cascadeId == cascadeId })
                let knownCount = summaryMeta?.stepCount ?? 0
                let summaryIsCloud = summaryMeta?.isCloud ?? false
                let originUuid = summaryMeta?.originInstanceUuid
                let isEmptyNewSessionNow = self.locallyCreatedEmptyCascadeIds.contains(cascadeId)
                    && !(self.optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
                var stillActive = false
                do {
                    let remoteSteps = try await client.fetchAllTrajectorySteps(
                        cascadeId: cascadeId,
                        knownStepCount: knownCount,
                        isCloud: summaryIsCloud,
                        instanceUuidOverride: originUuid
                    )
                    let liveRelayInst: RelayInstanceInfo? = (self.activeHost.channel == .cloudRelay)
                        ? await client.currentActiveRelayInstance()
                        : nil
                    guard !Task.isCancelled, !self.isNetworkingSuspended else { return }

                    self.lastBackendActivityAt = Date()

                    if let liveRelayInst {
                        if self.activeHost.instanceId != liveRelayInst.uuid
                            || self.activeHost.hostname != liveRelayInst.name
                            || !self.activeHost.isOnline {
                            let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(self.activeHost.endpointURL.absoluteString)
                            let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
                            let nextURL = URL(string: "\(originPrefix)/r/\(liveRelayInst.uuid)") ?? self.activeHost.endpointURL
                            let refreshedHost = RemoteHostInstance(
                                instanceId: liveRelayInst.uuid,
                                hostname: liveRelayInst.name,
                                version: liveRelayInst.version,
                                channel: .cloudRelay,
                                endpointURL: nextURL,
                                isOnline: true,
                                latencyMs: self.activeHost.latencyMs
                            )
                            self.activeHost = refreshedHost
                            if let hostIdx = self.hosts.firstIndex(where: { $0.instanceId == refreshedHost.instanceId }) {
                                self.hosts[hostIdx] = refreshedHost
                            } else {
                                self.hosts.insert(refreshedHost, at: 0)
                            }
                        }
                        if !summaryIsCloud,
                           let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
                            self.summaries[sumIdx].originInstanceUuid = liveRelayInst.uuid
                            self.summaries[sumIdx].originHostName = liveRelayInst.name
                        }
                    }

                    if self.hasPairedBackend && (!self.isLiveBackendConnected || !self.activeHost.isOnline) {
                        self.markBackendReconnected()
                    }
                    self.stepLoadErrorText = nil
                    if self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                    }

                    let withinOptimisticWindow = (self.optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
                    if !remoteSteps.isEmpty {
                        self.locallyCreatedEmptyCascadeIds.remove(cascadeId)
                        self.stepsByCascadeId[cascadeId] = remoteSteps
                        self.harvestEmbedResources(from: remoteSteps)
                        await storeRef.saveProjectedSteps(remoteSteps, for: cascadeId)
                        if !self.syncedConfigCascadeIds.contains(cascadeId),
                           let latestCfgStep = remoteSteps.last(where: {
                               $0.type == .userInput && ($0.recordedExecutionMode != nil || $0.recordedModelId != nil)
                           }) {
                            self.syncedConfigCascadeIds.insert(cascadeId)
                            if self.activeCascadeId == cascadeId {
                                self.applyRecordedConversationConfig(from: latestCfgStep)
                            }
                        }
                        if let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
                            self.summaries[sumIdx].stepCount = max(self.summaries[sumIdx].stepCount, remoteSteps.count)
                            if self.summaries[sumIdx].title == "New Conversation",
                               let firstPrompt = remoteSteps.first(where: { $0.type == .userInput })?.userInput?
                                   .trimmingCharacters(in: .whitespacesAndNewlines),
                               !firstPrompt.isEmpty {
                                self.summaries[sumIdx].title = String(firstPrompt.prefix(56))
                            }
                            let reconciled = Self.reconcileSummaryStreamingStatus(
                                currentStatus: self.summaries[sumIdx].status,
                                remoteSteps: remoteSteps,
                                withinOptimisticSendWindow: withinOptimisticWindow
                            )
                            self.summaries[sumIdx].status = reconciled.status
                            stillActive = reconciled.stillActive
                            if !reconciled.stillActive {
                                self.optimisticActiveUntilByCascadeId.removeValue(forKey: cascadeId)
                            }
                            self.summaries[sumIdx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                                status: self.summaries[sumIdx].status,
                                stepCount: self.summaries[sumIdx].stepCount,
                                isUnread: self.summaries[sumIdx].isUnread
                            )
                        } else {
                            stillActive = remoteSteps.contains { $0.status == .inProgress || $0.status == .pending }
                                || withinOptimisticWindow
                        }
                    } else {
                        stillActive = withinOptimisticWindow
                            || summaryMeta?.status == .inProgress
                            || summaryMeta?.status == .pending
                    }
                    self.connectionLifecyclePhase = stillActive ? .onlineStreaming : .onlineIdle
                } catch {
                    if !Task.isCancelled {
                        if Self.isBackendOfflineError(error) && self.activeHost.channel != .cloudRelay {
                            self.markBackendOffline(error: error)
                        }
                        if self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                            self.isLoadingSteps = false
                            if (self.stepsByCascadeId[cascadeId] ?? []).isEmpty && !isEmptyNewSessionNow {
                                self.stepLoadErrorText = error.localizedDescription
                            }
                        }
                    }
                    if !pollUntilIdle { break }
                }

                guard !Task.isCancelled, !self.isNetworkingSuspended, self.isDeviceNetworkReachable else { break }
                if !pollUntilIdle {
                    break
                }
                let isViewingThisChat = (self.activeRoute == .cascadeChat(cascadeId) && self.activeCascadeId == cascadeId)
                let isHostOffline = !self.isLiveBackendConnected || !self.activeHost.isOnline

                if isHostOffline {
                    // Central exponential-backoff reconnect scheduler owns host recovery; do not spin here
                    break
                }

                if stillActive {
                    let interval = ConnectionPowerPolicy.activeStreamingStepPollInterval(
                        channel: self.activeHost.channel,
                        isLowPowerMode: self.isLowPowerModeEnabled
                    )
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } else {
                    guard isViewingThisChat,
                          let fallbackInterval = ConnectionPowerPolicy.idleChatFallbackStepPollInterval(
                              isStreamHealthy: self.isSummaryStreamHealthy,
                              isLowPowerMode: self.isLowPowerModeEnabled
                          ) else {
                        // Idle chat with healthy push stream -> stop polling completely (0 idle RPCs)
                        break
                    }
                    try? await Task.sleep(nanoseconds: UInt64(fallbackInterval * 1_000_000_000))
                }
            }
        }
    }
}
