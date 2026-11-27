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
                if case .localHost(let selectedId, _) = selectedHostScope {
                    if let exact = reachable.first(where: { $0.uuid == selectedId }) {
                        return [(exact.uuid, exact.uuid, exact.name)]
                    }
                    if activeHost.isOnline && !activeHost.instanceId.isEmpty && activeHost.instanceId != "unpaired" {
                        return [(activeHost.instanceId, activeHost.instanceId, activeHost.hostname)]
                    }
                    return []
                }
                if !reachable.isEmpty {
                    return reachable.map { ($0.uuid, $0.uuid, $0.name) }
                }
                if activeHost.isOnline && !activeHost.instanceId.isEmpty && activeHost.instanceId != "unpaired" {
                    return [(activeHost.instanceId, activeHost.instanceId, activeHost.hostname)]
                }
                return []
            }
            return [("direct", nil, activeHost.hostname)]
        }()

        // Cancel local streams for instances that are no longer reachable or out of scope
        let activeTargetKeys = Set(localTargets.map(\.key))
        for (existingKey, existingTask) in localSummaryStreamTasks where !activeTargetKeys.contains(existingKey) {
            existingTask.cancel()
            localSummaryStreamTasks.removeValue(forKey: existingKey)
        }
        if localSummaryStreamTasks.isEmpty {
            hasReceivedLocalStreamEvent = false
        }

        let generation = self.summaryStreamGeneration
        let boundHostGen = self.hostSwitchGeneration

        for target in localTargets where localSummaryStreamTasks[target.key] == nil {
            let targetKey = target.key
            let targetUuid = target.uuid
            let targetHostName = target.hostName
            localSummaryStreamTasks[targetKey] = Task { [weak self] in
                guard let stream = try? await client.subscribeEnvelopeStream(
                    method: "JetboxSubscribeToSummaries",
                    instanceUuidOverride: targetUuid,
                    allowCrossHostFailover: false
                ) else {
                    if let self, self.summaryStreamGeneration == generation && self.hostSwitchGeneration == boundHostGen {
                        self.localSummaryStreamTasks.removeValue(forKey: targetKey)
                        if self.localSummaryStreamTasks.isEmpty {
                            self.hasReceivedLocalStreamEvent = false
                        }
                    }
                    return
                }
                do {
                    for try await event in stream {
                        guard let self,
                              !Task.isCancelled,
                              self.summaryStreamGeneration == generation,
                              self.hostSwitchGeneration == boundHostGen else { break }
                        self.hasReceivedLocalStreamEvent = true
                        self.lastBackendActivityAt = Date()
                        self.applyJetboxSummaryEvent(
                            event,
                            forceCloud: false,
                            originInstanceUuid: targetUuid,
                            originHostName: targetHostName
                        )
                    }
                    if let self, self.summaryStreamGeneration == generation && self.hostSwitchGeneration == boundHostGen {
                        self.localSummaryStreamTasks.removeValue(forKey: targetKey)
                        if self.localSummaryStreamTasks.isEmpty {
                            self.hasReceivedLocalStreamEvent = false
                        }
                    }
                } catch {
                    // Clear dead stream reference BEFORE running passive probe so it can reopen cleanly
                    if let self, self.summaryStreamGeneration == generation && self.hostSwitchGeneration == boundHostGen {
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
                        instanceUuidOverride: resolvedCloudTarget,
                        allowCrossHostFailover: true
                    ) else {
                        break
                    }
                    do {
                        for try await event in stream {
                            guard let self,
                                  !Task.isCancelled,
                                  self.summaryStreamGeneration == generation,
                                  self.hostSwitchGeneration == boundHostGen else { break }
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
                        where idx == 0 && ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body)?.lowercased() == "backend" {
                        continue
                    } catch {
                        break
                    }
                }
                if let self, self.summaryStreamGeneration == generation && self.hostSwitchGeneration == boundHostGen {
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
            ensureActiveSummaryStreamRunning()
            connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
        }

        let boundGeneration = hostSwitchGeneration
        summaryPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let sleepSeconds: TimeInterval? = {
                    guard let self,
                          self.hostSwitchGeneration == boundGeneration,
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
                      self.hostSwitchGeneration == boundGeneration,
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

    /// Resolves the freshest known display name for a local host UUID from `availableRelayInstances` / `hosts`,
    /// falling back cleanly to `fallback` or `activeHost.hostname`.
    public func resolvedHostName(forInstanceUuid instanceUuid: String?, fallback: String? = nil) -> String {
        if let uuid = instanceUuid, !uuid.isEmpty {
            if let inst = availableRelayInstances.first(where: { $0.uuid == uuid }) {
                return inst.name
            }
            if let host = hosts.first(where: { $0.instanceId == uuid }) {
                return host.hostname
            }
            if activeHost.instanceId == uuid {
                return activeHost.hostname
            }
        }
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback
        }
        return activeHost.hostname
    }

    /// Returns live online status for a specific host UUID (consistent with per-device Relay reachability).
    public func isHostOnline(forInstanceUuid instanceUuid: String?) -> Bool {
        guard hasPairedBackend else { return true }
        return isLocalHostOnline(instanceId: instanceUuid, hostname: nil)
    }

    internal func syncRelayInstancesToHosts(
        _ relayInstances: [RelayInstanceInfo],
        latencyMs: Int? = nil,
        preferredActiveInstance: RelayInstanceInfo? = nil,
        persistKeychainIfChanged: Bool = true
    ) {
        guard !relayInstances.isEmpty else { return }
        let previousActiveId = activeHost.instanceId
        let previousActiveHostname = activeHost.hostname
        availableRelayInstances = relayInstances

        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
        let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
        let effectiveLatency = latencyMs ?? lastPingLatencyMs ?? activeHost.latencyMs
        let seenIds = Set(relayInstances.map(\.uuid))

        hosts.removeAll { $0.instanceId == "unpaired" }

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
        } else if activeHost.channel == .cloudRelay {
            if let matchedActive = relayInstances.first(where: { $0.uuid == activeHost.instanceId }) {
                var updatedActive = activeHost
                updatedActive.hostname = matchedActive.name
                updatedActive.version = matchedActive.version
                updatedActive.isOnline = matchedActive.status.isReachable
                updatedActive.latencyMs = effectiveLatency
                activeHost = updatedActive
            } else if activeHost.instanceId != "unpaired" && !activeHost.instanceId.isEmpty {
                // Active Cloud Relay device disappeared from authoritative ListInstances roster -> mark offline cleanly.
                var offlineActive = activeHost
                offlineActive.isOnline = false
                activeHost = offlineActive
            }
        }
        if activeHost.channel == .cloudRelay && !activeHost.isOnline {
            isLiveBackendConnected = false
        }
        if isLiveBackendConnected && activeHost.isOnline {
            if let pingMs = latencyMs ?? lastPingLatencyMs {
                connectionStatusText = "Connected · \(activeHost.hostname) · \(pingMs)ms"
            } else {
                connectionStatusText = "Connected · \(activeHost.hostname)"
            }
        } else if hasPairedBackend && !activeHost.isOnline {
            connectionStatusText = "Offline · \(activeHost.hostname)"
        }

        var newNameByUuid: [String: String] = [:]
        for inst in relayInstances {
            newNameByUuid[inst.uuid] = inst.name
        }
        newNameByUuid[activeHost.instanceId] = activeHost.hostname

        let activeUuidRotated = previousActiveId != activeHost.instanceId
            && previousActiveId != "unpaired"
            && previousActiveId != "auto"
            && !previousActiveId.isEmpty
            && newNameByUuid[previousActiveId] == nil
        let activeNameChanged = previousActiveHostname != activeHost.hostname
        let previousNameStillPresent = newNameByUuid.values.contains(previousActiveHostname)

        for idx in workspaces.indices where !workspaces[idx].isCloud {
            if let u = workspaces[idx].originInstanceUuid {
                if let freshName = newNameByUuid[u] {
                    workspaces[idx].originHostName = freshName
                } else if activeUuidRotated && u == previousActiveId {
                    workspaces[idx].originInstanceUuid = activeHost.instanceId
                    workspaces[idx].originHostName = activeHost.hostname
                }
            } else if activeNameChanged && !previousNameStillPresent && workspaces[idx].originHostName == previousActiveHostname {
                workspaces[idx].originHostName = activeHost.hostname
            }
        }

        var summariesChanged = false
        for idx in summaries.indices where !summaries[idx].isCloud {
            if let u = summaries[idx].originInstanceUuid {
                if let freshName = newNameByUuid[u] {
                    if summaries[idx].originHostName != freshName {
                        summaries[idx].originHostName = freshName
                        summariesChanged = true
                    }
                } else if activeUuidRotated && u == previousActiveId {
                    summaries[idx].originInstanceUuid = activeHost.instanceId
                    summaries[idx].originHostName = activeHost.hostname
                    summariesChanged = true
                }
            } else if activeNameChanged && !previousNameStillPresent && summaries[idx].originHostName == previousActiveHostname {
                summaries[idx].originHostName = activeHost.hostname
                summariesChanged = true
            }
        }

        var projectsChanged = false
        for idx in projects.indices where projects[idx].runtime != .cloud {
            if let u = projects[idx].originInstanceUuid {
                if let freshName = newNameByUuid[u] {
                    if projects[idx].hostName != freshName {
                        projects[idx].hostName = freshName
                        if projects[idx].isNoProject {
                            projects[idx].pathDisplay = "Unassigned · \(freshName)"
                        }
                        projectsChanged = true
                    }
                } else if activeUuidRotated && u == previousActiveId {
                    projects[idx].originInstanceUuid = activeHost.instanceId
                    projects[idx].hostName = activeHost.hostname
                    if projects[idx].isNoProject {
                        projects[idx].pathDisplay = "Unassigned · \(activeHost.hostname)"
                    }
                    projectsChanged = true
                }
            } else if activeNameChanged && !previousNameStillPresent && projects[idx].hostName == previousActiveHostname {
                projects[idx].hostName = activeHost.hostname
                if projects[idx].isNoProject {
                    projects[idx].pathDisplay = "Unassigned · \(activeHost.hostname)"
                }
                projectsChanged = true
            }
        }

        if !isVerificationMode && (projectsChanged || summariesChanged) {
            let localHostsSnapshot = pairedLocalHosts
            let storeRef = projectionStore
            Task { [weak self] in
                await self?.persistHostProjections()
                if !localHostsSnapshot.isEmpty {
                    await storeRef.saveKnownHosts(localHostsSnapshot)
                }
            }
        } else if !isVerificationMode && !pairedLocalHosts.isEmpty {
            let localHostsSnapshot = pairedLocalHosts
            let storeRef = projectionStore
            Task {
                await storeRef.saveKnownHosts(localHostsSnapshot)
            }
        }

        if persistKeychainIfChanged
            && !isVerificationMode
            && hasPairedBackend
            && activeHost.channel == .cloudRelay
            && (activeNameChanged || previousActiveId != activeHost.instanceId) {
            let updatedHostname = activeHost.hostname
            let updatedUuid = activeHost.instanceId
            let updatedEndpoint = activeHost.endpointURL.absoluteString
            let updatedAuthUser = activeAuthUser
            persistPairedHostLaunchHint(
                PairedHostLaunchHint(
                    instanceId: updatedUuid,
                    hostname: updatedHostname,
                    channel: .cloudRelay,
                    endpointURLString: updatedEndpoint
                )
            )
            let secretStoreRef = secretStore
            Task {
                if var saved = await secretStoreRef.loadCredentials(),
                   saved.channel == .cloudRelay {
                    var changed = false
                    if saved.hostname != updatedHostname {
                        saved.hostname = updatedHostname
                        changed = true
                    }
                    if saved.resolvedInstanceUuid != updatedUuid {
                        saved.resolvedInstanceUuid = updatedUuid
                        changed = true
                    }
                    if saved.endpointURLString != updatedEndpoint {
                        saved.endpointURLString = updatedEndpoint
                        changed = true
                    }
                    if !updatedAuthUser.isEmpty && saved.authUser != updatedAuthUser {
                        saved.authUser = updatedAuthUser
                        changed = true
                    }
                    if changed {
                        await secretStoreRef.saveCredentials(saved)
                    }
                }
            }
        }
        reconcileSelectedHostScopeWithHosts()
    }

    internal func applyRelayProbeMetadata(
        _ probe: HostReachabilityProbeResult,
        allowCrossHostFallback: Bool
    ) {
        lastPingLatencyMs = probe.latencyMs
        let approvedActiveInst: RelayInstanceInfo? = {
            guard let activeInst = probe.activeRelayInstance else { return nil }
            let matchesCurrentOrFamily = activeInst.uuid == activeHost.instanceId
                || activeInst.matches(identifier: activeHost.hostname)
                || activeInst.sameHostFamily(as: activeHost.hostname)
            return (allowCrossHostFallback || matchesCurrentOrFamily) ? activeInst : nil
        }()

        if !probe.availableRelayInstances.isEmpty {
            syncRelayInstancesToHosts(
                probe.availableRelayInstances,
                latencyMs: probe.latencyMs,
                preferredActiveInstance: approvedActiveInst
            )
        } else if let activeInst = approvedActiveInst {
            if probe.isSelectedHostOnline {
                syncRelayInstancesToHosts(
                    [activeInst],
                    latencyMs: probe.latencyMs,
                    preferredActiveInstance: activeInst
                )
            } else {
                let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
                let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
                let nextURL = URL(string: "\(originPrefix)/r/\(activeInst.uuid)") ?? activeHost.endpointURL
                let refreshedHost = RemoteHostInstance(
                    instanceId: activeInst.uuid,
                    hostname: activeInst.name,
                    version: activeInst.version,
                    channel: .cloudRelay,
                    endpointURL: nextURL,
                    isOnline: false,
                    latencyMs: probe.latencyMs
                )
                activeHost = refreshedHost
                if let idx = hosts.firstIndex(where: { $0.instanceId == refreshedHost.instanceId }) {
                    hosts[idx] = refreshedHost
                } else {
                    hosts.insert(refreshedHost, at: 0)
                }
                reconcileSelectedHostScopeWithHosts()
            }
        } else {
            var updatedHost = activeHost
            updatedHost.latencyMs = probe.latencyMs
            updatedHost.isOnline = probe.isSelectedHostOnline
            activeHost = updatedHost
            if let idx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
                hosts[idx] = updatedHost
            }
        }
        let isOnlineNow = probe.isSelectedHostOnline && activeHost.isOnline
        isLiveBackendConnected = isOnlineNow
        if isOnlineNow {
            connectionErrorText = nil
            connectionStatusText = "Connected · \(activeHost.hostname) · \(probe.latencyMs)ms"
            connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
        } else {
            connectionStatusText = "Offline · \(activeHost.hostname)"
            if !isNetworkingSuspended && isDeviceNetworkReachable && hasPairedBackend {
                let nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelay(
                    attempt: reconnectAttemptCount,
                    isLowPowerMode: isLowPowerModeEnabled
                )
                connectionLifecyclePhase = .offlineBackoff(attempt: reconnectAttemptCount, nextRetrySeconds: nextDelay)
            }
        }
    }

    internal func performLightweightHeartbeatTick(allowFullReconciliation: Bool) async {
        guard !isNetworkingSuspended, isDeviceNetworkReachable, (kmpEngine != nil || rpcClient != nil) else { return }
        let generation = hostSwitchGeneration
        let isRelay = (activeHost.channel == .cloudRelay)
        let probeTimeout: TimeInterval = isRelay ? 8.0 : 3.0
        let allowCrossHost = (selectedHostScope == .allHosts || selectedHostScope == .antigravityCloud)

        do {
            let probe: HostReachabilityProbeResult
            if let kmpEngine {
                probe = try await kmpEngine.probeHostReachability(
                    allowCrossHostFallback: allowCrossHost,
                    verifyEndToEnd: false
                )
            } else if let client = rpcClient {
                probe = try await client.probeHostReachability(
                    timeoutInterval: probeTimeout,
                    allowCrossHostFallback: allowCrossHost
                )
            } else {
                return
            }
            guard self.hostSwitchGeneration == generation else { return }
            let wasOfflineBeforeProbe = !isLiveBackendConnected || !activeHost.isOnline
            applyRelayProbeMetadata(probe, allowCrossHostFallback: allowCrossHost)

            if !probe.isSelectedHostOnline {
                let hasReachablePeers = probe.availableRelayInstances.contains(where: \.status.isReachable)
                markBackendOffline(
                    error: AntigravityRPCError.httpError(
                        statusCode: 503,
                        body: "\(activeHost.hostname) is offline"
                    ),
                    preservePeerOnlineStates: hasReachablePeers
                )
                return
            }

            consecutiveSyncFailures = 0
            reconnectAttemptCount = 0
            nextReconnectAt = nil
            lastBackendActivityAt = Date()

            if wasOfflineBeforeProbe {
                markBackendReconnected(forceReconnectedActions: true)
            } else {
                connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
            }

            if probe.relayTopologyChanged {
                cancelAllSummaryStreams()
                lastStreamReopenAttemptAt = .distantPast
                ensureActiveSummaryStreamRunning()
                await refreshWorkspacesAndSummaries(
                    forceFullSync: true,
                    includeAutomations: false,
                    skipRelayMetadataProbe: true
                )
            } else {
                if kmpEngine != nil {
                    if kmpSummaryStreamTask == nil {
                        startKmpSummarySubscriptionIfNeeded()
                    }
                } else {
                    let missingLocalStream: Bool = {
                        if isRelay, case .localHost(let selectedId, _) = selectedHostScope {
                            return localSummaryStreamTasks[selectedId] == nil
                        }
                        return localSummaryStreamTasks.isEmpty
                            || (isRelay && availableRelayInstances.contains { $0.status.isReachable && localSummaryStreamTasks[$0.uuid] == nil })
                    }()
                    let missingCloudStream = (cloudSummaryStreamTask == nil)
                    if missingLocalStream || missingCloudStream {
                        ensureSummaryEnvelopeStreamRunning()
                    }
                }
                if allowFullReconciliation {
                    await refreshWorkspacesAndSummaries(
                        forceFullSync: false,
                        includeAutomations: false,
                        skipRelayMetadataProbe: true
                    )
                }
            }
        } catch {
            guard self.hostSwitchGeneration == generation else { return }
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

    internal func ensureActiveSummaryStreamRunning() {
        if kmpEngine != nil {
            if kmpSummaryStreamTask == nil {
                startKmpSummarySubscriptionIfNeeded()
            }
        } else {
            ensureSummaryEnvelopeStreamRunning()
        }
    }

    internal func performOfflineRecoveryProbe() async -> Bool {
        guard !isNetworkingSuspended, isDeviceNetworkReachable, (kmpEngine != nil || rpcClient != nil) else { return false }
        let generation = hostSwitchGeneration
        let isRelay = (activeHost.channel == .cloudRelay)
        let probeTimeout: TimeInterval = isRelay ? 8.0 : 3.0
        let allowCrossHost = (selectedHostScope == .allHosts || selectedHostScope == .antigravityCloud)

        do {
            let probe: HostReachabilityProbeResult
            if let kmpEngine {
                probe = try await kmpEngine.probeHostReachability(
                    allowCrossHostFallback: allowCrossHost,
                    verifyEndToEnd: true
                )
            } else if let client = rpcClient {
                probe = try await client.probeHostReachability(
                    timeoutInterval: probeTimeout,
                    allowCrossHostFallback: allowCrossHost,
                    verifyEndToEnd: true
                )
            } else {
                return false
            }
            guard self.hostSwitchGeneration == generation else { return false }
            applyRelayProbeMetadata(probe, allowCrossHostFallback: allowCrossHost)
            guard probe.isSelectedHostOnline else {
                isLiveBackendConnected = false
                connectionStatusText = "Offline · \(activeHost.hostname)"
                return false
            }
            markBackendReconnected(forceReconnectedActions: true)
            await refreshWorkspacesAndSummaries(
                forceFullSync: true,
                includeAutomations: selectedTab == .automations,
                skipRelayMetadataProbe: true
            )
            return true
        } catch {
            guard self.hostSwitchGeneration == generation else { return false }
            if Self.isBackendOfflineError(error) {
                connectionErrorText = ProtocolCompatibilityEngine.formatUserFacingRpcError(error)
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
        var activeChatNeedsStepSync = false
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
                    if existing.hasResolvedTitle && !merged.hasResolvedTitle {
                        merged.title = existing.title
                        merged.hasResolvedTitle = true
                    } else if merged.hasResolvedTitle {
                        hydratingCascadeIds.remove(cid)
                        settledEmptyTitleCascadeIds.remove(cid)
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

                    let stepCountAdvanced = merged.stepCount > prevStepCount
                    let statusChanged = merged.status != existing.status
                    let timestampAdvanced = decoded.updatedAt.timeIntervalSince(existing.updatedAt) > 0.5
                    let isActivelyRunningOrWaiting = merged.status == .inProgress
                        || merged.status == .pending
                        || merged.status == .waiting
                        || merged.status == .blocked
                    let hasNewActivity = stepCountAdvanced || timestampAdvanced
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
                    if cid == activeCascadeId && (stepCountAdvanced || statusChanged || (timestampAdvanced && isActivelyRunningOrWaiting)) {
                        activeChatNeedsStepSync = true
                    }
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
                    if cid == activeCascadeId {
                        activeChatNeedsStepSync = true
                    }
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
            if cid == activeCascadeId {
                activeChatNeedsStepSync = true
            }
            let statusRaw = event["status"]?.stringValue ?? "CORTEX_STEP_STATUS_IN_PROGRESS"
            let newStatus = CortexStepStatus.from(jsonName: statusRaw)
            let stepCount = event["stepCount"]?.intValue
            let title = event["title"]?.stringValue
            if let idx = summaries.firstIndex(where: { $0.cascadeId == cid }) {
                summaries[idx].status = newStatus
                if let stepCount { summaries[idx].stepCount = stepCount }
                if let title, !CascadeSummaryTitleResolver.isPlaceholderTitle(title) {
                    summaries[idx].title = title
                    summaries[idx].hasResolvedTitle = true
                    hydratingCascadeIds.remove(cid)
                    settledEmptyTitleCascadeIds.remove(cid)
                }
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

        if !activeCascadeId.isEmpty && activeChatNeedsStepSync {
            syncStepsForCascade(
                activeCascadeId,
                pollUntilIdle: activeRoute == .cascadeChat(activeCascadeId),
                forceRefresh: true
            )
        }

        if !isVerificationMode && (!changedIds.isEmpty || !decodedBatch.deletes.isEmpty) {
            let touchedHostKey = Self.projectionHostKey(
                isCloud: forceCloud,
                instanceId: forceCloud ? nil : effectiveOriginUuid,
                hostname: forceCloud ? "Antigravity" : effectiveOriginHost,
                fallbackHostId: activeHost.instanceId,
                fallbackHostName: activeHost.hostname
            )
            Task { [weak self] in
                await self?.persistHostProjections(refreshedHostKeys: [touchedHostKey])
            }
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

    /// Returns `true` when an in-flight foreground step synchronization task is already running for `cascadeId`.
    public func hasActiveStepSync(for cascadeId: String) -> Bool {
        !cascadeId.isEmpty && stepPollingTask != nil && activeStepSyncCascadeId == cascadeId
    }

    internal func isIdleCachedTrajectoryFresh(
        cascadeId: String,
        cachedSteps: [CascadeStep],
        summary: CascadeSummary?
    ) -> Bool {
        guard !cachedSteps.isEmpty, let summary else { return false }
        guard !summary.needsTitleHydration else { return false }
        let knownCount = summary.stepCount
        guard knownCount > 0, cachedSteps.count >= knownCount else { return false }
        let hasActiveSteps = cachedSteps.contains {
            $0.status == .inProgress
                || $0.status == .pending
                || $0.status == .waiting
                || $0.status == .blocked
                || $0.isQueuedInOutbox
        }
        guard !hasActiveSteps else { return false }

        let isExplicitTerminal = summary.status == .done
            || summary.status == .error
            || summary.status == .cancelled
        let isActiveSummary = summary.status == .inProgress
            || summary.status == .pending
            || summary.status == .waiting
            || summary.status == .blocked
        let marker = syncedStepsMarkerByCascadeId[cascadeId]
        let canSkip = isExplicitTerminal || (marker != nil && !isActiveSummary)
        guard canSkip else { return false }
        if let marker {
            return marker.updatedAt >= summary.updatedAt && marker.stepCount >= knownCount
        }
        return true
    }

    /// Synchronizes `GetCascadeTrajectorySteps` (local-default Binary Protobuf + targeted JSON repair + runtime JSON ceiling learning) for `cascadeId`.
    /// Polls adaptively ONLY while an agent turn is actively streaming (`500ms` LAN / `1.0s` Relay; slowed in Low Power Mode).
    /// When the conversation is idle and the push stream is healthy, stops polling completely (0 idle RPCs) and relies
    /// on `JetboxSubscribeToSummaries` to wake step sync on demand.
    public func syncStepsForCascade(_ cascadeId: String, pollUntilIdle: Bool = true, forceRefresh: Bool = false) {
        if !forceRefresh,
           !cascadeId.isEmpty,
           stepPollingTask != nil,
           activeStepSyncCascadeId == cascadeId {
            if pollUntilIdle {
                activeStepSyncPollsUntilIdle = true
            }
            return
        }

        stepPollingTask?.cancel()
        stepPollingTask = nil
        activeStepSyncCascadeId = nil
        activeStepSyncPollsUntilIdle = false
        stepSyncGeneration &+= 1
        let generation = stepSyncGeneration
        guard !isNetworkingSuspended else { return }
        guard (hasPairedBackend || isLiveBackendConnected), !cascadeId.isEmpty else { return }

        stepLoadErrorText = nil

        // Local optimistic IDs (`cas-<8hex>`) have not been materialized on the server via `StartCascade` yet.
        // Never show a stuck "Loading conversation history..." spinner or `not_found` error on them.
        if cascadeId.hasPrefix("cas-") && !Self.esddFixtureCascadeIds.contains(cascadeId) {
            isLoadingSteps = false
            return
        }

        let initialSummary = summaries.first(where: { $0.cascadeId == cascadeId })
        let withinInitialOptimisticSend = (optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
        let isBrandNewEmptySession = locallyCreatedEmptyCascadeIds.contains(cascadeId)
            && !withinInitialOptimisticSend
        let summaryHostOnline = isSummaryHostOnline(initialSummary)
        let isKnownOfflineLocal = hasPairedBackend
            && !summaryHostOnline
            && (initialSummary?.isCloud != true)
        let isConfirmedOfflinePeerHost = isKnownOfflineLocal && isLiveBackendConnected
        let storeRef = projectionStore

        if isBrandNewEmptySession && isKnownOfflineLocal {
            isLoadingSteps = false
            return
        }

        // Confirmed-offline peer Mac (while another Mac is online), iPhone no-network, or pre-handshake cold start:
        // serve persisted steps immediately from disk without issuing cross-host failover RPCs against another online Mac.
        guard isDeviceNetworkReachable, !isConfirmedOfflinePeerHost, (kmpEngine != nil || rpcClient != nil) else {
            let isActivelyConnecting = !isConfirmedOfflinePeerHost
                && !isLiveBackendConnected
                && (isConnectingToBackend || connectionLifecyclePhase == .connecting)
            let offlineHostLabel = initialSummary?.originHostName ?? activeHost.hostname
            let shouldNoteUncachedOffline = isKnownOfflineLocal && !isBrandNewEmptySession && !isActivelyConnecting
            if (stepsByCascadeId[cascadeId] ?? []).isEmpty {
                isLoadingSteps = isActivelyConnecting && !isBrandNewEmptySession
                activeStepSyncCascadeId = cascadeId
                activeStepSyncPollsUntilIdle = pollUntilIdle
                stepPollingTask = Task { [weak self] in
                    defer {
                        if let self, self.stepSyncGeneration == generation {
                            self.stepPollingTask = nil
                            self.activeStepSyncCascadeId = nil
                            self.activeStepSyncPollsUntilIdle = false
                        }
                    }
                    let cached = await storeRef.loadProjectedSteps(cascadeId: cascadeId)
                    guard let self, !Task.isCancelled, self.stepSyncGeneration == generation else { return }
                    if !cached.isEmpty {
                        if (self.stepsByCascadeId[cascadeId] ?? []).isEmpty {
                            self.stepsByCascadeId[cascadeId] = cached
                            self.harvestEmbedResources(from: cached)
                        }
                        self.applyHydratedMetadataIfNeeded(cascadeId: cascadeId, steps: cached, persist: false)
                        if self.activeCascadeId == cascadeId {
                            self.isLoadingSteps = false
                            self.stepLoadErrorText = nil
                        }
                    } else if shouldNoteUncachedOffline && self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                        self.stepLoadErrorText = "\(offlineHostLabel) is currently offline and this conversation has not been cached on this device yet."
                    } else {
                        let stillConnecting = !self.isLiveBackendConnected
                            && (self.isConnectingToBackend || self.connectionLifecyclePhase == .connecting)
                        if !stillConnecting && self.activeCascadeId == cascadeId {
                            self.isLoadingSteps = false
                        }
                    }
                }
            } else {
                isLoadingSteps = false
            }
            return
        }

        let initialInMemorySteps = stepsByCascadeId[cascadeId] ?? []
        let initialKnownCount = initialSummary?.stepCount ?? 0
        let isActiveRunSummary = initialSummary?.status == .inProgress
            || initialSummary?.status == .pending
            || initialSummary?.status == .waiting
            || initialSummary?.status == .blocked
        let needsHistoryBackfill = forceRefresh
            || (!initialInMemorySteps.isEmpty
                && initialKnownCount > initialInMemorySteps.count
                && !isActiveRunSummary
                && !withinInitialOptimisticSend)
        if (initialInMemorySteps.isEmpty && !isBrandNewEmptySession) || needsHistoryBackfill {
            isLoadingSteps = true
        } else {
            isLoadingSteps = false
        }

        let clientRef = rpcClient
        let countsAsForeground = pollUntilIdle || activeRoute == .cascadeChat(cascadeId)
        if countsAsForeground {
            preemptNonTargetPreloads(keeping: cascadeId)
        }
        activeStepSyncCascadeId = cascadeId
        activeStepSyncPollsUntilIdle = pollUntilIdle
        if countsAsForeground {
            activeForegroundStepSyncCount += 1
        }
        if pollUntilIdle, let engine = kmpEngine, engine.supportsNativeLiveChatStream {
            startKmpLiveChatSubscriptionIfNeeded()
        }
        stepPollingTask = Task { [weak self] in
            defer {
                if let self {
                    if countsAsForeground {
                        self.activeForegroundStepSyncCount = max(0, self.activeForegroundStepSyncCount - 1)
                    }
                    if self.stepSyncGeneration == generation {
                        if self.activeCascadeId == cascadeId {
                            self.isLoadingSteps = false
                        }
                        self.stepPollingTask = nil
                        self.activeStepSyncCascadeId = nil
                        self.activeStepSyncPollsUntilIdle = false
                    }
                }
            }
            if (self?.stepsByCascadeId[cascadeId] ?? []).isEmpty {
                let cached = await storeRef.loadProjectedSteps(cascadeId: cascadeId)
                if !cached.isEmpty, let self, (self.stepsByCascadeId[cascadeId] ?? []).isEmpty {
                    self.stepsByCascadeId[cascadeId] = cached
                    self.harvestEmbedResources(from: cached)
                    self.applyHydratedMetadataIfNeeded(cascadeId: cascadeId, steps: cached, persist: false)
                    let cachedNeedsMore = forceRefresh
                        || (initialKnownCount > cached.count && !isActiveRunSummary && !withinInitialOptimisticSend)
                    if !cachedNeedsMore && self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                    }
                }
            }

            // 0-RTT idle cached fast-path: if cached steps already match a settled terminal summary
            // with no active/pending/waiting/queued steps, render immediately with zero network RTTs.
            if let self, !forceRefresh {
                let cachedNow = self.stepsByCascadeId[cascadeId] ?? []
                let currentSummary = self.summaries.first(where: { $0.cascadeId == cascadeId })
                let withinOptimistic = (self.optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
                if !withinOptimistic,
                   self.isIdleCachedTrajectoryFresh(
                       cascadeId: cascadeId,
                       cachedSteps: cachedNow,
                       summary: currentSummary
                   ) {
                    if let currentSummary {
                        self.syncedStepsMarkerByCascadeId[cascadeId] = (
                            stepCount: max(currentSummary.stepCount, cachedNow.count),
                            updatedAt: currentSummary.updatedAt
                        )
                    }
                    if self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                        self.stepLoadErrorText = nil
                    }
                    if self.activeStepSyncPollsUntilIdle,
                       let engine = self.kmpEngine,
                       engine.supportsNativeLiveChatStream {
                        let isCloudChat = currentSummary.map { self.isSummaryCloudRuntime($0) }
                            ?? AntigravityCloudDetector.isCloudWorkspaceURI("", cascadeId: cascadeId)
                        engine.startLiveChatStream(
                            cascadeId: cascadeId,
                            isCloud: isCloudChat,
                            instanceUuidOverride: currentSummary?.originInstanceUuid
                        )
                    }
                    return
                }
            }

            // Coalesce onto an already in-flight background preload for the same conversation instead of firing a duplicate RPC.
            if let self, !forceRefresh, let inFlightPreload = self.inFlightPreloadTasksByCascadeId[cascadeId] {
                let preloadedSteps = await inFlightPreload.value
                guard !Task.isCancelled, self.stepSyncGeneration == generation else { return }
                if !preloadedSteps.isEmpty {
                    if (self.stepsByCascadeId[cascadeId] ?? []) != preloadedSteps {
                        self.stepsByCascadeId[cascadeId] = preloadedSteps
                        self.harvestEmbedResources(from: preloadedSteps)
                    }
                    self.applyHydratedMetadataIfNeeded(cascadeId: cascadeId, steps: preloadedSteps, persist: false)
                    if self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                        self.stepLoadErrorText = nil
                    }
                    let refreshedSummary = self.summaries.first(where: { $0.cascadeId == cascadeId })
                    let withinOptimistic = (self.optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
                    if !withinOptimistic,
                       self.isIdleCachedTrajectoryFresh(
                           cascadeId: cascadeId,
                           cachedSteps: preloadedSteps,
                           summary: refreshedSummary
                       ) {
                        if let refreshedSummary {
                            self.syncedStepsMarkerByCascadeId[cascadeId] = (
                                stepCount: max(refreshedSummary.stepCount, preloadedSteps.count),
                                updatedAt: refreshedSummary.updatedAt
                            )
                        }
                        if self.activeStepSyncPollsUntilIdle,
                           let engine = self.kmpEngine,
                           engine.supportsNativeLiveChatStream {
                            let isCloudChat = refreshedSummary.map { self.isSummaryCloudRuntime($0) }
                                ?? AntigravityCloudDetector.isCloudWorkspaceURI("", cascadeId: cascadeId)
                            engine.startLiveChatStream(
                                cascadeId: cascadeId,
                                isCloud: isCloudChat,
                                instanceUuidOverride: refreshedSummary?.originInstanceUuid
                            )
                        }
                        return
                    }
                }
            }

            var attempts = 0
            while !Task.isCancelled && attempts < 10_000 {
                guard let self, !self.isNetworkingSuspended, self.isDeviceNetworkReachable else { break }
                attempts += 1
                let summaryMeta = self.summaries.first(where: { $0.cascadeId == cascadeId })
                if let summaryMeta,
                   !summaryMeta.isCloud,
                   self.hasPairedBackend,
                   self.isLiveBackendConnected,
                   !self.isSummaryHostOnline(summaryMeta) {
                    break
                }
                let knownCount = summaryMeta?.stepCount ?? 0
                let summaryIsCloud: Bool = {
                    if summaryMeta?.isCloud == true
                        || AntigravityCloudDetector.isCloudWorkspaceURI("", cascadeId: cascadeId) {
                        return true
                    }
                    if let slug = summaryMeta?.projectSlug,
                       let matchedProject = self.projects.first(where: { $0.id == slug || $0.name == slug }),
                       matchedProject.runtime == .cloud {
                        return true
                    }
                    return false
                }()
                let originUuid = summaryMeta?.originInstanceUuid
                let isEmptyNewSessionNow = self.locallyCreatedEmptyCascadeIds.contains(cascadeId)
                    && !(self.optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
                let existingStepsSnapshot = self.stepsByCascadeId[cascadeId] ?? []
                let useForceOnThisAttempt = forceRefresh && attempts == 1
                var stillActive = false
                do {
                    let remoteSteps: [CascadeStep]
                    if let engine = self.kmpEngine {
                        if !useForceOnThisAttempt,
                           !summaryIsCloud,
                           let deltaMerged = try await self.tryFetchKmpIncrementalBinaryDelta(
                               engine: engine,
                               cascadeId: cascadeId,
                               existingSteps: existingStepsSnapshot,
                               knownStepCount: knownCount,
                               instanceUuidOverride: originUuid
                           ) {
                            remoteSteps = deltaMerged
                        } else if useForceOnThisAttempt {
                            remoteSteps = try await engine.forceSyncSteps(
                                cascadeId: cascadeId,
                                knownStepCount: knownCount,
                                isCloud: summaryIsCloud,
                                instanceUuidOverride: originUuid
                            )
                        } else {
                            remoteSteps = try await engine.syncSteps(
                                cascadeId: cascadeId,
                                knownStepCount: knownCount,
                                isCloud: summaryIsCloud,
                                instanceUuidOverride: originUuid
                            )
                        }
                    } else if let clientRef {
                        remoteSteps = try await clientRef.fetchAllTrajectorySteps(
                            cascadeId: cascadeId,
                            knownStepCount: knownCount,
                            isCloud: summaryIsCloud,
                            instanceUuidOverride: originUuid,
                            existingSteps: useForceOnThisAttempt ? [] : existingStepsSnapshot,
                            onPartialSteps: { [weak self] partial in
                                await MainActor.run {
                                    guard let self, self.stepSyncGeneration == generation else { return }
                                    self.applyKmpLiveChatUpdate(
                                        KmpLiveChatUpdate(
                                            cascadeId: cascadeId,
                                            steps: partial,
                                            totalLength: max(knownCount, partial.count),
                                            isSnapshotComplete: false
                                        )
                                    )
                                }
                            }
                        )
                    } else {
                        break
                    }
                    let liveRelaySnapshot: (instances: [RelayInstanceInfo], active: RelayInstanceInfo?)? =
                        (self.activeHost.channel == .cloudRelay && clientRef != nil)
                            ? await clientRef?.currentRelayInstancesSnapshot()
                            : nil
                    guard !Task.isCancelled, !self.isNetworkingSuspended else { return }

                    self.lastBackendActivityAt = Date()

                    if let liveRelaySnapshot, !liveRelaySnapshot.instances.isEmpty {
                        if liveRelaySnapshot.instances != self.availableRelayInstances {
                            self.syncRelayInstancesToHosts(liveRelaySnapshot.instances)
                        }
                        if !summaryIsCloud,
                           let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == cascadeId }),
                           let existingUuid = self.summaries[sumIdx].originInstanceUuid,
                           let matchedPeer = liveRelaySnapshot.instances.first(where: { $0.uuid == existingUuid }) {
                            self.summaries[sumIdx].originHostName = matchedPeer.name
                        }
                    }

                    let belongsToActiveHost = !summaryIsCloud && (
                        originUuid == nil
                            || originUuid?.isEmpty == true
                            || originUuid == self.activeHost.instanceId
                    )
                    if belongsToActiveHost && self.hasPairedBackend && (!self.isLiveBackendConnected || !self.activeHost.isOnline) {
                        self.markBackendReconnected()
                    }
                    self.stepLoadErrorText = nil
                    if self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                    }

                    let withinOptimisticWindow = (self.optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
                    if !remoteSteps.isEmpty {
                        self.locallyCreatedEmptyCascadeIds.remove(cascadeId)
                        let stepsChanged = (self.stepsByCascadeId[cascadeId] ?? []) != remoteSteps
                        if stepsChanged {
                            self.stepsByCascadeId[cascadeId] = remoteSteps
                            self.harvestEmbedResources(from: remoteSteps)
                            await storeRef.saveProjectedSteps(remoteSteps, for: cascadeId)
                        }
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
                            var summaryDidMutate = false
                            let prevStepCount = self.summaries[sumIdx].stepCount
                            let nextStepCount = max(prevStepCount, remoteSteps.count)
                            if nextStepCount != prevStepCount {
                                self.summaries[sumIdx].stepCount = nextStepCount
                                self.summaries[sumIdx].currentStepIndex = max(1, nextStepCount)
                                self.summaries[sumIdx].totalSteps = max(self.summaries[sumIdx].totalSteps, nextStepCount)
                                summaryDidMutate = true
                            }
                            if self.summaries[sumIdx].needsTitleHydration,
                               let derivedTitle = CascadeSummaryTitleResolver.deriveTitle(from: remoteSteps) {
                                self.summaries[sumIdx].title = derivedTitle
                                self.summaries[sumIdx].hasResolvedTitle = true
                                self.hydratingCascadeIds.remove(cascadeId)
                                self.settledEmptyTitleCascadeIds.remove(cascadeId)
                                summaryDidMutate = true
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
                            self.syncedStepsMarkerByCascadeId[cascadeId] = (
                                stepCount: self.summaries[sumIdx].stepCount,
                                updatedAt: self.summaries[sumIdx].updatedAt
                            )
                            if summaryDidMutate {
                                self.scheduleDebouncedHostProjectionPersist(for: self.summaries[sumIdx])
                            }
                        } else {
                            stillActive = remoteSteps.contains { $0.status == .inProgress || $0.status == .pending }
                                || withinOptimisticWindow
                        }
                    } else {
                        stillActive = withinOptimisticWindow
                            || summaryMeta?.status == .inProgress
                            || summaryMeta?.status == .pending
                        if !stillActive && !isEmptyNewSessionNow && summaryMeta?.needsTitleHydration == true {
                            self.hydratingCascadeIds.remove(cascadeId)
                            self.settledEmptyTitleCascadeIds.insert(cascadeId)
                        }
                    }
                    if belongsToActiveHost {
                        self.connectionLifecyclePhase = stillActive ? .onlineStreaming : .onlineIdle
                    }
                } catch {
                    if !Task.isCancelled {
                        if !summaryIsCloud && ProtocolCompatibilityEngine.isInstanceNotRegisteredError(error) {
                            self.markLocalHostOffline(
                                instanceUuid: originUuid ?? self.activeHost.instanceId,
                                hostname: summaryMeta?.originHostName,
                                error: error
                            )
                        } else if Self.isBackendOfflineError(error) && self.activeHost.channel != .cloudRelay {
                            self.markBackendOffline(error: error)
                        }
                        if self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                            self.isLoadingSteps = false
                            if (self.stepsByCascadeId[cascadeId] ?? []).isEmpty && !isEmptyNewSessionNow {
                                self.stepLoadErrorText = ProtocolCompatibilityEngine.formatUserFacingRpcError(error)
                            }
                        }
                    }
                    if !self.activeStepSyncPollsUntilIdle { break }
                }

                guard !Task.isCancelled, !self.isNetworkingSuspended, self.isDeviceNetworkReachable else { break }
                if !self.activeStepSyncPollsUntilIdle {
                    break
                }
                let isViewingThisChat = (self.activeRoute == .cascadeChat(cascadeId) && self.activeCascadeId == cascadeId)
                let isTargetHostOffline: Bool = {
                    if summaryIsCloud {
                        if self.activeHost.channel == .cloudRelay && !self.availableRelayInstances.isEmpty {
                            return !self.availableRelayInstances.contains(where: \.status.isReachable)
                        }
                        return false
                    }
                    if let originUuid, !originUuid.isEmpty {
                        return !self.isLocalHostOnline(instanceId: originUuid, hostname: summaryMeta?.originHostName)
                    }
                    return !self.isLiveBackendConnected || !self.activeHost.isOnline
                }()

                if isTargetHostOffline {
                    // Central exponential-backoff reconnect scheduler owns host recovery; do not spin here
                    break
                }

                // When running on the real KMP engine, hand off continuous real-time updates to
                // `StreamAgentStateUpdates` (with built-in legacy delta fallback) instead of running a duplicate Swift polling loop.
                if let engine = self.kmpEngine, engine.supportsNativeLiveChatStream {
                    if isViewingThisChat || stillActive {
                        engine.startLiveChatStream(
                            cascadeId: cascadeId,
                            isCloud: summaryIsCloud,
                            instanceUuidOverride: originUuid
                        )
                    }
                    break
                }

                if stillActive {
                    let interval = ConnectionPowerPolicy.activeStreamingStepPollInterval(
                        channel: self.activeHost.channel,
                        isLowPowerMode: self.isLowPowerModeEnabled
                    )
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } else {
                    let streamCoversTarget: Bool = {
                        if summaryIsCloud {
                            return self.cloudSummaryStreamTask != nil && self.hasReceivedCloudStreamEvent
                        }
                        if self.activeHost.channel == .cloudRelay, let originUuid, !originUuid.isEmpty {
                            return self.localSummaryStreamTasks[originUuid] != nil && self.hasReceivedLocalStreamEvent
                        }
                        return self.isSummaryStreamHealthy
                    }()
                    guard isViewingThisChat,
                          let fallbackInterval = ConnectionPowerPolicy.idleChatFallbackStepPollInterval(
                              isStreamHealthy: streamCoversTarget,
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

    /// Cancels in-flight background preload tasks for other conversations so foreground chat opens
    /// immediately get full Relay/LAN bandwidth and Desktop server capacity.
    internal func preemptNonTargetPreloads(keeping cascadeId: String) {
        let keysToCancel = inFlightPreloadTasksByCascadeId.keys.filter { $0 != cascadeId }
        for cid in keysToCancel {
            inFlightPreloadTasksByCascadeId.removeValue(forKey: cid)?.cancel()
            preloadAttemptedAtByCascadeId.removeValue(forKey: cid)
            if !conversationPreloadQueue.contains(cid) {
                conversationPreloadQueue.append(cid)
            }
        }
    }

    /// Fetches only newly added tail steps via KMP `fetchBinaryStepDelta` when Swift already has
    /// contiguous disk/memory-cached steps, eliminating cold-start full-history re-downloads and
    /// cross-bridge conversion of hundreds of unchanged steps.
    internal func tryFetchKmpIncrementalBinaryDelta(
        engine: any AntigravityKmpEnginePort,
        cascadeId: String,
        existingSteps: [CascadeStep],
        knownStepCount: Int,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep]? {
        guard existingSteps.count >= 2 else { return nil }
        if knownStepCount > 0 && knownStepCount < existingSteps.count { return nil }
        guard existingSteps.first?.stepIndex == 0,
              existingSteps.last?.stepIndex == existingSteps.count - 1 else {
            return nil
        }
        let hostKey = instanceUuidOverride?.isEmpty == false ? instanceUuidOverride! : activeHost.instanceId
        guard !kmpDeltaOffsetIgnoredHosts.contains(hostKey) else { return nil }

        let deltaOffset = existingSteps.count - 1
        let deltaSteps: [CascadeStep]
        do {
            deltaSteps = try await engine.fetchBinaryStepDelta(
                cascadeId: cascadeId,
                startIndex: deltaOffset,
                knownStepCount: knownStepCount,
                instanceUuidOverride: instanceUuidOverride
            )
        } catch let AntigravityRPCError.unauthorized(msg) {
            throw AntigravityRPCError.unauthorized(msg)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        guard let firstDelta = deltaSteps.first else { return nil }

        let anchorStep = existingSteps[deltaOffset]
        let matchesAnchor = Self.isStepAnchorMatch(cached: anchorStep, remote: firstDelta)
        let looksLikeFullUnfiltered = deltaSteps.count >= existingSteps.count
            && Self.isStepAnchorMatch(cached: existingSteps[0], remote: firstDelta)
            && (!matchesAnchor || (knownStepCount > 0 && deltaOffset + deltaSteps.count > knownStepCount + 1))

        if looksLikeFullUnfiltered {
            kmpDeltaOffsetIgnoredHosts.insert(hostKey)
            return deltaSteps.enumerated().map { idx, step in
                if step.stepIndex == idx { return step }
                var copy = step
                copy.stepIndex = idx
                return copy
            }
        }
        guard matchesAnchor else { return nil }

        var merged = Array(existingSteps[0..<deltaOffset])
        merged.reserveCapacity(deltaOffset + deltaSteps.count)
        merged.append(contentsOf: deltaSteps)
        return merged
    }

    internal static func isStepAnchorMatch(cached: CascadeStep, remote: CascadeStep) -> Bool {
        let typeMatches = cached.type == remote.type
            || (cached.type == .unspecified && cached.rawTypeName != nil && cached.rawTypeName == remote.rawTypeName)
        guard typeMatches else { return false }
        if cached.createdAt.timeIntervalSince1970 > 1.0 && remote.createdAt.timeIntervalSince1970 > 1.0 {
            return abs(cached.createdAt.timeIntervalSince(remote.createdAt)) <= 2.0
        }
        switch cached.type {
        case .userInput:
            return cached.userInput == remote.userInput
        case .viewFile, .listDirectory, .viewContentChunk:
            return cached.viewFile?.fileUri == remote.viewFile?.fileUri
        case .codeAction:
            return cached.codeAction?.targetFileUri == remote.codeAction?.targetFileUri
        case .runCommand:
            return cached.runCommand?.commandLine == remote.runCommand?.commandLine
        case .search:
            return cached.search?.query == remote.search?.query
        case .taskBoundary:
            return cached.taskBoundary?.taskName == remote.taskBoundary?.taskName
        case .plannerResponse, .notifyUser:
            let cachedResp = cached.plannerResponse?.response ?? ""
            let remoteResp = remote.plannerResponse?.response ?? ""
            return cachedResp.isEmpty || remoteResp.hasPrefix(String(cachedResp.prefix(24)))
        default:
            return true
        }
    }

    // MARK: - Conversation Title Loading State & Smart Background Preloader

    /// Returns `true` when `summary` is a server conversation whose title has not been hydrated yet
    /// and should render an inline loading indicator instead of `"New Conversation"`.
    public func isSummaryTitleLoading(_ summary: CascadeSummary) -> Bool {
        if isVerificationMode && !hasPairedBackend && !isLiveBackendConnected {
            return false
        }
        if locallyCreatedEmptyCascadeIds.contains(summary.cascadeId) {
            return false
        }
        if summary.cascadeId.hasPrefix("cas-") && !Self.esddFixtureCascadeIds.contains(summary.cascadeId) {
            return false
        }
        guard summary.needsTitleHydration else { return false }
        if hydratingCascadeIds.contains(summary.cascadeId) {
            return true
        }
        if settledEmptyTitleCascadeIds.contains(summary.cascadeId) {
            return false
        }
        guard isDeviceNetworkReachable else { return false }
        if !isLiveBackendConnected && (isConnectingToBackend || connectionLifecyclePhase == .connecting) {
            return true
        }
        return isSummaryHostOnline(summary) && (isLiveBackendConnected || hasPairedBackend)
    }

    /// Returns the user-facing display title for `summary`, preventing unloaded server conversations
    /// from falling back to `"New Conversation"`.
    public func displayTitle(for summary: CascadeSummary) -> String {
        if locallyCreatedEmptyCascadeIds.contains(summary.cascadeId)
            || (summary.cascadeId.hasPrefix("cas-") && !Self.esddFixtureCascadeIds.contains(summary.cascadeId)) {
            return summary.title.isEmpty ? CascadeSummaryTitleResolver.placeholderTitle : summary.title
        }
        if summary.needsTitleHydration {
            return isSummaryTitleLoading(summary)
                ? "Loading..."
                : CascadeSummaryTitleResolver.untitledFallback
        }
        return summary.title
    }

    /// Applies hydrated title/stepCount metadata from locally cached or remotely fetched steps.
    internal func applyHydratedMetadataIfNeeded(
        cascadeId: String,
        steps: [CascadeStep],
        persist: Bool
    ) {
        guard let sumIdx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        var changed = false
        let nextStepCount = max(summaries[sumIdx].stepCount, steps.count)
        if nextStepCount != summaries[sumIdx].stepCount {
            summaries[sumIdx].stepCount = nextStepCount
            summaries[sumIdx].currentStepIndex = max(1, nextStepCount)
            summaries[sumIdx].totalSteps = max(summaries[sumIdx].totalSteps, nextStepCount)
            changed = true
        }
        if summaries[sumIdx].needsTitleHydration,
           let derivedTitle = CascadeSummaryTitleResolver.deriveTitle(from: steps) {
            summaries[sumIdx].title = derivedTitle
            summaries[sumIdx].hasResolvedTitle = true
            hydratingCascadeIds.remove(cascadeId)
            settledEmptyTitleCascadeIds.remove(cascadeId)
            changed = true
        }
        if changed {
            summaries[sumIdx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                status: summaries[sumIdx].status,
                stepCount: summaries[sumIdx].stepCount,
                isUnread: summaries[sumIdx].isUnread
            )
            if persist && !isVerificationMode {
                scheduleDebouncedHostProjectionPersist(for: summaries[sumIdx])
            }
        }
    }

    internal func scheduleDebouncedHostProjectionPersist(for summary: CascadeSummary) {
        guard !isVerificationMode else { return }
        let key = Self.projectionHostKey(
            isCloud: summary.isCloud,
            instanceId: summary.originInstanceUuid,
            hostname: summary.originHostName,
            fallbackHostId: activeHost.instanceId,
            fallbackHostName: activeHost.hostname
        )
        pendingPersistHostKeys.insert(key)
        preloadPersistDebounceTask?.cancel()
        preloadPersistDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            let keys = self.pendingPersistHostKeys
            self.pendingPersistHostKeys.removeAll()
            guard !keys.isEmpty else { return }
            await self.persistHostProjections(refreshedHostKeys: keys)
        }
    }

    /// Cancels any active background conversation preload worker without clearing cached disk data.
    public func cancelConversationPreload() {
        conversationPreloadTask?.cancel()
        conversationPreloadTask = nil
        conversationPreloadQueue.removeAll()
        hydratingCascadeIds.removeAll()
        for task in inFlightPreloadTasksByCascadeId.values {
            task.cancel()
        }
        inFlightPreloadTasksByCascadeId.removeAll()
    }

    /// Prioritizes preloading a conversation as soon as its row scrolls into view in the sidebar or project list.
    public func requestPreloadForVisibleConversation(_ cascadeId: String) {
        guard !isVerificationMode, !isNetworkingSuspended, isDeviceNetworkReachable else { return }
        guard hasPairedBackend || isLiveBackendConnected else { return }
        guard !cascadeId.isEmpty, !locallyCreatedEmptyCascadeIds.contains(cascadeId) else { return }
        guard !(cascadeId.hasPrefix("cas-") && !Self.esddFixtureCascadeIds.contains(cascadeId)) else { return }
        guard let summary = summaries.first(where: { $0.cascadeId == cascadeId }) else { return }
        let hasCachedSteps = !(stepsByCascadeId[cascadeId] ?? []).isEmpty
        if !summary.needsTitleHydration && hasCachedSteps {
            return
        }
        scheduleConversationPreload(priorityCascadeIds: [cascadeId])
    }

    /// Schedules bounded-concurrency background preloading of top recent conversations' steps and
    /// unhydrated conversation titles so opening recent chats is instant and sidebar rows resolve cleanly.
    public func scheduleConversationPreload(priorityCascadeIds: [String] = []) {
        guard !isVerificationMode, !isNetworkingSuspended, isDeviceNetworkReachable else { return }
        guard isLiveBackendConnected || (hasPairedBackend && activeHost.isOnline) else { return }
        guard kmpEngine != nil || rpcClient != nil else { return }

        let maxBackgroundHydrateCount = 32
        let maxRecentStepPreloadCount = 8
        let collapsedIds = appearancePreferences.collapsedProjectIds
        var candidates: [String] = []
        var seen = Set<String>()

        func appendCandidate(_ cid: String) {
            guard !cid.isEmpty,
                  !locallyCreatedEmptyCascadeIds.contains(cid),
                  !(cid.hasPrefix("cas-") && !Self.esddFixtureCascadeIds.contains(cid)),
                  seen.insert(cid).inserted else {
                return
            }
            candidates.append(cid)
        }

        for cid in priorityCascadeIds {
            appendCandidate(cid)
        }

        // 1. Preload steps for top recent conversations in expanded projects FIRST so tapping recent chats opens on Frame 0
        let recentUncached = summaries.filter { s in
            !s.isArchived
                && !collapsedIds.contains(s.projectSlug)
                && (stepsByCascadeId[s.cascadeId] ?? []).isEmpty
                && isSummaryHostOnline(s)
        }
        for s in recentUncached.prefix(maxRecentStepPreloadCount) {
            appendCandidate(s.cascadeId)
        }

        // 2. Hydrate remaining unhydrated titles in expanded projects
        let unresolvedExpanded = summaries.filter { s in
            !s.isArchived && s.needsTitleHydration
                && !settledEmptyTitleCascadeIds.contains(s.cascadeId)
                && !collapsedIds.contains(s.projectSlug)
                && isSummaryHostOnline(s)
        }
        for s in unresolvedExpanded.prefix(maxBackgroundHydrateCount) {
            appendCandidate(s.cascadeId)
        }

        // 3. Hydrate unhydrated titles in collapsed projects last so they never starve recent active chats
        let unresolvedCollapsed = summaries.filter { s in
            !s.isArchived && s.needsTitleHydration
                && !settledEmptyTitleCascadeIds.contains(s.cascadeId)
                && collapsedIds.contains(s.projectSlug)
                && isSummaryHostOnline(s)
        }
        for s in unresolvedCollapsed.prefix(maxBackgroundHydrateCount) {
            appendCandidate(s.cascadeId)
        }

        guard !candidates.isEmpty else { return }

        // Place explicit priority IDs at the very front of the queue
        for cid in priorityCascadeIds.reversed() where seen.contains(cid) {
            conversationPreloadQueue.removeAll { $0 == cid }
            conversationPreloadQueue.insert(cid, at: 0)
        }
        for cid in candidates where !conversationPreloadQueue.contains(cid) {
            conversationPreloadQueue.append(cid)
        }

        guard conversationPreloadTask == nil else { return }
        let maxConcurrency = (isLowPowerModeEnabled || isNetworkExpensiveOrConstrained) ? 1 : 2
        let generation = hostSwitchGeneration

        conversationPreloadTask = Task { [weak self] in
            defer {
                if let self, self.hostSwitchGeneration == generation {
                    self.conversationPreloadTask = nil
                }
            }
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<maxConcurrency {
                    group.addTask { [weak self] in
                        while !Task.isCancelled {
                            // Yield immediately whenever foreground conversation loading is active so
                            // background preload RPCs never contend with user-initiated chat opens.
                            var isForegroundBusy = await MainActor.run {
                                (self?.activeForegroundStepSyncCount ?? 0) > 0
                            }
                            while isForegroundBusy && !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 120_000_000)
                                isForegroundBusy = await MainActor.run {
                                    (self?.activeForegroundStepSyncCount ?? 0) > 0
                                }
                            }
                            if Task.isCancelled { break }

                            let nextId: String? = await MainActor.run {
                                guard let self,
                                      self.hostSwitchGeneration == generation,
                                      !self.isNetworkingSuspended,
                                      self.isDeviceNetworkReachable,
                                      !self.conversationPreloadQueue.isEmpty else {
                                    return nil
                                }
                                return self.conversationPreloadQueue.removeFirst()
                            }
                            guard let nextId else { break }
                            await self?.preloadSingleConversation(nextId, expectedGeneration: generation)
                        }
                    }
                }
                await group.waitForAll()
            }
        }
    }

    internal func preloadSingleConversation(_ cascadeId: String, expectedGeneration: UInt64) async {
        guard hostSwitchGeneration == expectedGeneration,
              !isNetworkingSuspended,
              isDeviceNetworkReachable else {
            return
        }
        guard let summary = summaries.first(where: { $0.cascadeId == cascadeId }) else { return }
        guard isSummaryHostOnline(summary) else { return }

        let now = Date()
        if let prevAttempt = preloadAttemptedAtByCascadeId[cascadeId],
           now.timeIntervalSince(prevAttempt) < 30.0 {
            return
        }
        preloadAttemptedAtByCascadeId[cascadeId] = now

        // 1. Check in-memory & disk cache first (zero network RPCs when already cached)
        let storeRef = projectionStore
        let existingInMem = stepsByCascadeId[cascadeId] ?? []
        if !existingInMem.isEmpty {
            applyHydratedMetadataIfNeeded(cascadeId: cascadeId, steps: existingInMem, persist: true)
            let updatedNeed = summaries.first(where: { $0.cascadeId == cascadeId })?.needsTitleHydration ?? false
            if !updatedNeed && (summary.stepCount <= 0 || existingInMem.count >= summary.stepCount) {
                return
            }
        } else {
            let diskCached = await storeRef.loadProjectedSteps(cascadeId: cascadeId)
            guard !Task.isCancelled, hostSwitchGeneration == expectedGeneration else { return }
            if !diskCached.isEmpty {
                if (stepsByCascadeId[cascadeId] ?? []).isEmpty {
                    stepsByCascadeId[cascadeId] = diskCached
                    harvestEmbedResources(from: diskCached)
                }
                applyHydratedMetadataIfNeeded(cascadeId: cascadeId, steps: diskCached, persist: true)
                let updatedNeed = summaries.first(where: { $0.cascadeId == cascadeId })?.needsTitleHydration ?? false
                if !updatedNeed && (summary.stepCount <= 0 || diskCached.count >= summary.stepCount) {
                    return
                }
            }
        }

        // 2. Fetch remotely with non-intrusive preload path (never touches activeCascadeId / isLoadingSteps)
        let latestSummary = summaries.first(where: { $0.cascadeId == cascadeId }) ?? summary
        let shouldMarkHydrating = latestSummary.needsTitleHydration
        if shouldMarkHydrating {
            hydratingCascadeIds.insert(cascadeId)
        }
        defer {
            hydratingCascadeIds.remove(cascadeId)
        }

        let summaryIsCloud: Bool = {
            if latestSummary.isCloud || AntigravityCloudDetector.isCloudWorkspaceURI(latestSummary.workspaceUri, cascadeId: cascadeId) {
                return true
            }
            if let matchedProj = projects.first(where: { $0.id == latestSummary.projectSlug || $0.name == latestSummary.projectSlug }),
               matchedProj.runtime == .cloud {
                return true
            }
            return false
        }()

        let engineRef = kmpEngine
        let clientRef = rpcClient
        let knownStepCount = latestSummary.stepCount
        let originUuid = latestSummary.originInstanceUuid
        let baselineSteps = stepsByCascadeId[cascadeId] ?? []

        let fetchTask = Task<[CascadeStep], Never> {
            do {
                if let engineRef {
                    return try await engineRef.preloadSteps(
                        cascadeId: cascadeId,
                        knownStepCount: knownStepCount,
                        isCloud: summaryIsCloud,
                        instanceUuidOverride: originUuid,
                        requireRemoteRefresh: shouldMarkHydrating
                    )
                } else if let clientRef {
                    return try await clientRef.fetchAllTrajectorySteps(
                        cascadeId: cascadeId,
                        knownStepCount: knownStepCount,
                        isCloud: summaryIsCloud,
                        instanceUuidOverride: originUuid,
                        existingSteps: shouldMarkHydrating ? [] : baselineSteps
                    )
                }
            } catch {
                return []
            }
            return []
        }
        inFlightPreloadTasksByCascadeId[cascadeId] = fetchTask
        let remoteSteps = await fetchTask.value
        if inFlightPreloadTasksByCascadeId[cascadeId] == fetchTask {
            inFlightPreloadTasksByCascadeId.removeValue(forKey: cascadeId)
        }
        guard !Task.isCancelled, hostSwitchGeneration == expectedGeneration, !isNetworkingSuspended else { return }

        if !remoteSteps.isEmpty {
            locallyCreatedEmptyCascadeIds.remove(cascadeId)
            if (stepsByCascadeId[cascadeId] ?? []) != remoteSteps {
                stepsByCascadeId[cascadeId] = remoteSteps
                harvestEmbedResources(from: remoteSteps)
                await storeRef.saveProjectedSteps(remoteSteps, for: cascadeId)
            }
            applyHydratedMetadataIfNeeded(cascadeId: cascadeId, steps: remoteSteps, persist: true)
            if let updatedSummary = summaries.first(where: { $0.cascadeId == cascadeId }) {
                syncedStepsMarkerByCascadeId[cascadeId] = (
                    stepCount: max(updatedSummary.stepCount, remoteSteps.count),
                    updatedAt: updatedSummary.updatedAt
                )
                if updatedSummary.needsTitleHydration {
                    settledEmptyTitleCascadeIds.insert(cascadeId)
                }
            }
        } else if shouldMarkHydrating {
            settledEmptyTitleCascadeIds.insert(cascadeId)
        }
    }
}
