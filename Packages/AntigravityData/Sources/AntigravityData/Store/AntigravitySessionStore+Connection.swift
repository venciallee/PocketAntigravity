import Foundation

/// Backend login, pairing, Cloud Relay / Direct LAN auth, lifecycle suspension, and network path handling.
extension AntigravitySessionStore {
    /// Restores saved Keychain credentials on launch and connects to the live backend if available.
    /// If the saved host is temporarily offline on launch, retains paired mode (`hasPairedBackend = true`),
    /// marks `activeHost.isOnline = false`, hydrates cached sessions from `LocalProjectionStore`,
    /// and starts background reconnect polling.
    @discardableResult
    public func restoreSavedBackendSession() async -> Bool {
        guard let saved = await secretStore.loadCredentials() else {
            return false
        }
        switch saved.channel {
        case .directHost:
            return await connectDirectLAN(
                endpointURLString: saved.endpointURLString,
                csrfToken: saved.csrfToken ?? "",
                certSHA256: saved.certFingerprintSHA256,
                hostName: saved.hostname,
                isRestoringSavedSession: true
            )
        case .cloudRelay:
            return await connectCloudRelay(
                relayURLString: saved.endpointURLString,
                sessionCookie: saved.sessionCookie ?? "",
                authUser: saved.authUser,
                resolvedInstanceUuid: saved.resolvedInstanceUuid,
                hostName: saved.hostname,
                isRestoringSavedSession: true
            )
        }
    }

    /// Reads any previously saved Google Cloud Relay session cookie from Keychain so scanning a new QR code
    /// connects immediately without asking the user to sign in again.
    public func loadSavedSessionCookie() async -> (cookie: String, authUser: String?)? {
        guard let saved = await secretStore.loadCredentials(),
              let cookie = saved.sessionCookie,
              !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return (cookie, saved.authUser)
    }

    /// Parses and connects via QR / Deep Link URI:
    /// - Official Antigravity Desktop QR: `https://antigravity.google.com/r/<instance-id>?p=c%2F<cascadeId>`
    /// - Optional LAN / Bridge Deep Link: `antigravity://pair?url=https://192.168.1.20:8787&csrf=<token>&sha256=<fp>&name=MacBook%20Pro`
    @discardableResult
    public func connectWithPairingURI(_ rawURI: String, fallbackCookie: String = "") async -> Bool {
        let trimmed = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
        if RemoteHostInstance.isDirectLANPairingURI(trimmed),
           let comps = URLComponents(string: trimmed),
           let targetURL = comps.queryItems?.first(where: { $0.name == "url" })?.value {
            let csrf = comps.queryItems?.first(where: { $0.name == "csrf" })?.value ?? ""
            let sha256 = comps.queryItems?.first(where: { $0.name == "sha256" })?.value
            let name = comps.queryItems?.first(where: { $0.name == "name" })?.value ?? "MacBook Pro"
            return await connectDirectLAN(
                endpointURLString: targetURL,
                csrfToken: csrf,
                certSHA256: sha256,
                hostName: name
            )
        }

        if let target = RemoteHostInstance.parseRemoteControlTarget(trimmed) {
            lastScannedRelayURL = target.canonicalRelayURLString
            var effectiveCookie = fallbackCookie.trimmingCharacters(in: .whitespacesAndNewlines)
            var savedAuthUser = target.authUser
            if effectiveCookie.isEmpty, let cached = await loadSavedSessionCookie() {
                effectiveCookie = cached.cookie
                if savedAuthUser == nil {
                    savedAuthUser = cached.authUser
                }
            }
            let displayHost = target.instanceId.isEmpty ? "Antigravity Desktop" : target.instanceId
            return await connectCloudRelay(
                relayURLString: trimmed,
                sessionCookie: effectiveCookie,
                authUser: savedAuthUser,
                deepLinkedConversationId: target.conversationId,
                hostName: displayHost
            )
        }

        return await connectDirectLAN(endpointURLString: trimmed, csrfToken: fallbackCookie)
    }

    /// Connects directly to Mac `language_server` or `mac-companion-bridge.py` over LAN / Tailscale
    /// using `x-codeium-csrf-token` + SHA-256 certificate pinning / TOFU.
    @discardableResult
    public func connectDirectLAN(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String? = nil,
        hostName: String = "MacBook Pro",
        isRestoringSavedSession: Bool = false
    ) async -> Bool {
        guard let url = URL(string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            connectionErrorText = "Invalid endpoint URL: \(endpointURLString)"
            return false
        }

        isConnectingToBackend = true
        connectionErrorText = nil
        connectionStatusText = "Handshaking with \(url.host ?? endpointURLString)..."
        defer { isConnectingToBackend = false }

        let hostInstance = RemoteHostInstance(
            instanceId: "direct-\(url.host ?? "mac")",
            hostname: hostName,
            channel: .directHost,
            endpointURL: url,
            isOnline: true,
            certificateFingerprintSHA256: certSHA256 ?? "TOFU-LOCAL-TLS"
        )
        let candidateClient = AntigravityRPCClient(
            host: hostInstance,
            csrfToken: csrfToken,
            pinnedFingerprintSHA256: certSHA256
        )

        do {
            let handshake = try await candidateClient.verifyConnection()
            applyVerifiedLiveConnection(
                host: hostInstance,
                client: candidateClient,
                handshake: handshake
            )
            await secretStore.saveCredentials(
                SavedBackendCredentials(
                    endpointURLString: url.absoluteString,
                    channel: .directHost,
                    hostname: hostName,
                    csrfToken: csrfToken,
                    certFingerprintSHA256: certSHA256
                )
            )
            return true
        } catch let AntigravityRPCError.unauthorized(reason) {
            let errMsg = "Authentication rejected (401/403): check x-codeium-csrf-token. \(reason)"
            let statusMsg = "Auth Failed · Invalid CSRF Token"
            if isRestoringSavedSession || hasPairedBackend {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName) (Auth Expired)"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = statusMsg
            }
            return false
        } catch {
            let errMsg = "Connection failed: \(error.localizedDescription)"
            if isRestoringSavedSession || hasPairedBackend {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName)"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = "Unreachable · \(url.host ?? endpointURLString)"
            }
            return false
        }
    }

    ///Resolves HTTP redirects for official Google shortlinks (`g.co`, `c.gle`, `goo.gl`, `*.page.link`)
    /// using an ephemeral `URLSession` (without attaching session cookies) so the target `/r/<instance-id>` is discovered.
    nonisolated internal static func resolveShortlinkRedirectIfNeeded(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var headReq = URLRequest(url: url)
        headReq.httpMethod = "HEAD"
        if let (_, resp) = try? await session.data(for: headReq),
           let finalStr = resp.url?.absoluteString,
           finalStr != urlString,
           RemoteHostInstance.parseRemoteControlTarget(finalStr) != nil {
            return finalStr
        }

        var getReq = URLRequest(url: url)
        getReq.httpMethod = "GET"
        if let (_, resp) = try? await session.data(for: getReq),
           let finalStr = resp.url?.absoluteString,
           finalStr != urlString,
           RemoteHostInstance.parseRemoteControlTarget(finalStr) != nil {
            return finalStr
        }
        return nil
    }

    /// Connects to official Google Cloud Remote Control Relay (`https://antigravity.google.com/r/<instance-id>`)
    /// via `devtools_jetski_boq_api_proto.ApiService` (`ListInstances` + `ProxyCommand` + `SAPISIDHASH`).
    @discardableResult
    public func connectCloudRelay(
        relayURLString: String,
        sessionCookie: String,
        authUser: String? = nil,
        resolvedInstanceUuid: String? = nil,
        deepLinkedConversationId: String? = nil,
        hostName: String = "Antigravity Desktop",
        isRestoringSavedSession: Bool = false
    ) async -> Bool {
        let trimmedInput = relayURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedTarget = RemoteHostInstance.parseRemoteControlTarget(
            trimmedInput.isEmpty ? SAPISIDHashGenerator.defaultOrigin : trimmedInput
        )
        var canonicalURLString = parsedTarget?.canonicalRelayURLString ?? trimmedInput
        guard URL(string: canonicalURLString)?.scheme != nil else {
            connectionErrorText = "Invalid Remote Control QR link: \(relayURLString)"
            return false
        }

        lastScannedRelayURL = canonicalURLString
        let trimmedCookie = sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCookie.isEmpty else {
            isLiveBackendConnected = false
            let fallbackName = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : "Antigravity Desktop"
            connectionErrorText = "Google Sign-In required: sign in once to pair with \(fallbackName)."
            connectionStatusText = "Sign in with Google to pair Remote Control"
            return false
        }

        isConnectingToBackend = true
        connectionErrorText = nil
        defer { isConnectingToBackend = false }

        if parsedTarget?.requiresRedirectResolution == true,
           let origURL = parsedTarget?.originalURLString {
            connectionStatusText = "Resolving Remote Control link..."
            if let resolvedStr = await Self.resolveShortlinkRedirectIfNeeded(origURL),
               let resolvedTarget = RemoteHostInstance.parseRemoteControlTarget(resolvedStr) {
                parsedTarget = resolvedTarget
                canonicalURLString = resolvedTarget.canonicalRelayURLString
                lastScannedRelayURL = canonicalURLString
            }
        }

        guard let url = URL(string: canonicalURLString), url.scheme != nil else {
            connectionErrorText = "Invalid Remote Control QR link: \(relayURLString)"
            return false
        }

        let targetBadge = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : "Cloud Relay"
        connectionStatusText = "Pairing with \(targetBadge) via Google Cloud Relay..."

        let effectiveAuthUser = authUser ?? parsedTarget?.authUser
        let initialInstanceId = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : "auto"
        let deepLinkConv = deepLinkedConversationId ?? parsedTarget?.conversationId

        let hostInstance = RemoteHostInstance(
            instanceId: resolvedInstanceUuid ?? initialInstanceId,
            hostname: hostName,
            channel: .cloudRelay,
            endpointURL: url,
            isOnline: true
        )
        let candidateClient = AntigravityRPCClient(
            host: hostInstance,
            sessionCookie: trimmedCookie,
            authUser: effectiveAuthUser,
            resolvedInstanceUuid: resolvedInstanceUuid
        )

        do {
            let handshake = try await candidateClient.verifyConnection()
            let finalHostName = handshake.resolvedHostname ?? hostName
            let finalUuid = handshake.resolvedInstanceUuid ?? hostInstance.instanceId
            let finalAuthUser = handshake.resolvedAuthUser ?? effectiveAuthUser ?? "0"
            let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
            let finalRelayURL = URL(string: "\(originPrefix)/r/\(finalUuid)") ?? url

            let verifiedHost = RemoteHostInstance(
                instanceId: finalUuid,
                hostname: finalHostName,
                version: handshake.serverVersion,
                channel: .cloudRelay,
                endpointURL: finalRelayURL,
                isOnline: true,
                latencyMs: handshake.latencyMs
            )

            availableRelayInstances = handshake.availableRelayInstances
            activeAuthUser = finalAuthUser
            applyVerifiedLiveConnection(
                host: verifiedHost,
                client: candidateClient,
                handshake: handshake
            )

            // Sync all Cloud Relay instances (online & offline) into `hosts` so Home reflects per-device reachability
            syncRelayInstancesToHosts(
                handshake.availableRelayInstances,
                latencyMs: handshake.latencyMs
            )

            await secretStore.saveCredentials(
                SavedBackendCredentials(
                    endpointURLString: finalRelayURL.absoluteString,
                    channel: .cloudRelay,
                    hostname: finalHostName,
                    sessionCookie: trimmedCookie,
                    authUser: finalAuthUser,
                    resolvedInstanceUuid: finalUuid
                )
            )

            if let deepLinkConv, !deepLinkConv.isEmpty {
                selectCascade(deepLinkConv)
            }
            return true
        } catch let AntigravityRPCError.unauthorized(reason) {
            let errMsg = "Google session unauthorized: please sign in again. (\(reason))"
            if isRestoringSavedSession {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Google Sign-In Expired"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = "Google Sign-In Expired"
            }
            return false
        } catch let AntigravityRPCError.httpError(code, body) {
            let errMsg = "Cloud Relay error (\(code)): \(body)"
            if (isRestoringSavedSession || hasPairedBackend) && (code == 502 || code == 503 || code == 504) {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName)"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = "Cloud Relay Handshake Failed"
            }
            return false
        } catch {
            let errMsg = "Cloud Relay handshake failed: \(error.localizedDescription)"
            if isRestoringSavedSession || hasPairedBackend {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName)"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = "Cloud Relay Disconnected"
            }
            return false
        }
    }

    public func disconnectBackendAndClearKeychain() async {
        cancelAllSummaryStreams()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        stepPollingTask?.cancel()
        stepPollingTask = nil
        networkMonitor.stop()
        hasPairedBackend = false
        isLiveBackendConnected = false
        cloudAgentWarmingUp = false
        consecutiveSyncFailures = 0
        reconnectAttemptCount = 0
        nextReconnectAt = nil
        backgroundPollCounter = 0
        lastBackendActivityAt = .distantPast
        lastFullSyncAt = .distantPast
        lastStreamReopenAttemptAt = .distantPast
        pendingOutboxCount = 0
        connectionLifecyclePhase = .disconnected
        lastAutomationsSyncAt = nil
        isLoadingAutomations = false
        isMutatingAutomation = false
        automationsErrorText = nil
        isAutomationsAuthExpired = false
        pendingDraftConversation = nil
        composerWorkflowCommand = nil
        optimisticActiveUntilByCascadeId.removeAll()
        syncedConfigCascadeIds.removeAll()
        locallyCreatedEmptyCascadeIds.removeAll()
        rpcClient = nil
        lastPingLatencyMs = nil
        availableRelayInstances = []
        connectionErrorText = nil
        connectionStatusText = "Not Connected"
        if !isVerificationMode {
            projects = []
            workspaces = []
            summaries = []
            automations = []
            stepsByCascadeId = [:]
            activeArtifacts = []
            activeTurnDiffs = []
            planChanges = []
            planComments = []
            composerAttachments = []
            composerDraftText = ""
            selectedProjectId = ""
            selectedWorkspaceUri = ""
            activeCascadeId = ""
            activeRoute = .tabRoot
        }
        _ = await projectionStore.drainOutbox()
        await secretStore.clearCredentials()
    }

    // MARK: - Foreground / Screen-Off Lifecycle & Network Path Control

    /// Immediately suspends all streams, heartbeats, backoff timers, step polling, and `NWPathMonitor`
    /// when the device locks, sleeps, or enters the background so battery & radio overhead is zero.
    public func suspendNetworkingForBackground() {
        guard !isVerificationMode else { return }
        guard !isNetworkingSuspended else { return }
        isNetworkingSuspended = true
        cancelAllSummaryStreams()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        stepPollingTask?.cancel()
        stepPollingTask = nil
        networkMonitor.stop()
        if hasPairedBackend || isLiveBackendConnected {
            connectionLifecyclePhase = .suspended
        }
    }

    /// Resumes connectivity cleanly when the screen unlocks or the app returns to `.active`:
    /// performs a single fresh reconciliation pass and restarts push streams + low-power scheduler.
    public func resumeNetworkingFromForeground() async {
        guard !isVerificationMode else { return }
        let wasSuspended = isNetworkingSuspended
        isNetworkingSuspended = false
        startNetworkPathMonitoringIfNeeded()

        guard hasPairedBackend else { return }

        if rpcClient == nil {
            _ = await restoreSavedBackendSession()
            return
        }

        guard isDeviceNetworkReachable else {
            connectionLifecyclePhase = .noNetwork
            connectionStatusText = "No Internet Connection"
            return
        }

        reconnectAttemptCount = 0
        nextReconnectAt = nil
        if wasSuspended {
            connectionLifecyclePhase = .connecting
        }

        await refreshWorkspacesAndSummaries(
            forceFullSync: true,
            includeAutomations: selectedTab == .automations
        )
        startSummarySubscriptionStream()

        if case .cascadeChat(let cid) = activeRoute, !cid.isEmpty {
            syncStepsForCascade(cid, pollUntilIdle: true)
        }
    }

    /// Immediately resets exponential backoff and attempts a fresh connection + sync.
    /// Used by `Reconnect Now`, pull-to-refresh, `NWPathMonitor` recovery, and chat retry buttons.
    public func reconnectNow(userInitiated: Bool = true, includeAutomations: Bool = false) async {
        guard !isVerificationMode else { return }
        if isNetworkingSuspended {
            isNetworkingSuspended = false
            startNetworkPathMonitoringIfNeeded()
        }
        guard hasPairedBackend else { return }

        if !userInitiated && !isDeviceNetworkReachable {
            connectionLifecyclePhase = .noNetwork
            connectionStatusText = "No Internet Connection"
            return
        }

        reconnectAttemptCount = 0
        consecutiveSyncFailures = 0
        nextReconnectAt = nil
        lastStreamReopenAttemptAt = .distantPast
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        connectionLifecyclePhase = .connecting

        if rpcClient == nil {
            _ = await restoreSavedBackendSession()
            return
        }

        await refreshWorkspacesAndSummaries(
            forceFullSync: true,
            includeAutomations: includeAutomations || selectedTab == .automations
        )
        startSummarySubscriptionStream()

        if case .cascadeChat(let cid) = activeRoute, !cid.isEmpty {
            syncStepsForCascade(cid, pollUntilIdle: true)
        }
    }

    internal func startNetworkPathMonitoringIfNeeded() {
        guard !isVerificationMode, !isNetworkingSuspended else { return }
        networkMonitor.start { [weak self] status in
            Task { @MainActor [weak self] in
                self?.handleNetworkPathChange(status)
            }
        }
    }

    internal func handleNetworkPathChange(_ status: NetworkReachabilityStatus) {
        let previous = lastNetworkStatus
        lastNetworkStatus = status
        isDeviceNetworkReachable = status.isSatisfied
        isNetworkExpensiveOrConstrained = status.isExpensiveOrConstrained

        guard !isVerificationMode, !isNetworkingSuspended, hasPairedBackend else { return }

        if !status.isSatisfied {
            // Device lost IP connectivity (e.g. elevator / Airplane Mode): stop all timers & streams (0 packets)
            cancelAllSummaryStreams()
            summaryPollingTask?.cancel()
            summaryPollingTask = nil
            stepPollingTask?.cancel()
            stepPollingTask = nil
            isLiveBackendConnected = false
            lastPingLatencyMs = nil
            nextReconnectAt = nil
            connectionLifecyclePhase = .noNetwork
            connectionStatusText = "No Internet Connection"
            connectionErrorText = "iPhone is offline. Waiting for Wi-Fi or cellular network..."
            return
        }

        // Network transitioned from unsatisfied -> satisfied, OR switched interfaces (Wi-Fi <-> 5G)
        let recoveredFromNoNetwork = (previous == .unsatisfied)
        let interfaceSwitched: Bool = {
            guard let prevFp = previous?.interfaceFingerprint,
                  let nextFp = status.interfaceFingerprint else {
                return false
            }
            return prevFp != nextFp
        }()

        if recoveredFromNoNetwork || interfaceSwitched {
            cancelAllSummaryStreams()
            Task { [weak self] in
                await self?.reconnectNow(userInitiated: false)
            }
        }
    }

    internal func applyOfflinePairedSession(
        host: RemoteHostInstance,
        client: AntigravityRPCClient,
        errorText: String,
        statusText: String
    ) async {
        var offlineHost = host
        offlineHost.isOnline = false
        activeHost = offlineHost
        if let existingIdx = hosts.firstIndex(where: { $0.instanceId == offlineHost.instanceId }) {
            hosts[existingIdx] = offlineHost
        } else {
            hosts.insert(offlineHost, at: 0)
        }

        let wasInESDDDemoState = !hasPairedBackend
        hasPairedBackend = true
        isLiveBackendConnected = false
        lastPingLatencyMs = nil
        rpcClient = client
        reconnectAttemptCount = 0
        connectionErrorText = errorText
        connectionStatusText = statusText
        pendingOutboxCount = await projectionStore.loadPendingOutbox().count

        if isNetworkingSuspended {
            connectionLifecyclePhase = .suspended
        } else if !isDeviceNetworkReachable {
            connectionLifecyclePhase = .noNetwork
        } else {
            let nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelay(
                attempt: 0,
                isLowPowerMode: isLowPowerModeEnabled
            )
            connectionLifecyclePhase = .offlineBackoff(attempt: 0, nextRetrySeconds: nextDelay)
        }

        if wasInESDDDemoState {
            let cachedProjects = (await projectionStore.loadProjects()).filter {
                !Self.esddFixtureProjectIds.contains($0.id)
            }
            let cachedSummaries = (await projectionStore.loadProjectedSummaries()).filter {
                !Self.esddFixtureCascadeIds.contains($0.cascadeId)
            }
            var hydratedSummaries = cachedSummaries
            if !cachedProjects.isEmpty || !hydratedSummaries.isEmpty {
                projects = Self.reconcileLiveProjects(
                    workspaces: [],
                    summaries: &hydratedSummaries,
                    existingProjects: cachedProjects,
                    hostName: offlineHost.hostname
                )
                summaries = hydratedSummaries
            } else {
                projects = []
                summaries = []
            }
            workspaces = []
            stepsByCascadeId = [:]
            automations = (await projectionStore.loadAutomations()).filter {
                !Self.esddFixtureAutomationIds.contains($0.id)
            }
            selectedProjectId = projects.first?.id ?? ""
            selectedWorkspaceUri = projects.first?.workspaceUri ?? ""
            activeCascadeId = summaries.first?.cascadeId ?? ""
        }

        startSummarySubscriptionStream()
    }

    internal static func isBackendOfflineError(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let rpcErr = error as? AntigravityRPCError {
            switch rpcErr {
            case .unauthorized, .invalidEndpoint:
                return true
            case .httpError(let statusCode, _):
                return statusCode == -1 || statusCode == 502 || statusCode == 503 || statusCode == 504
            case .decodingError, .interactionRejected:
                return false
            }
        }
        if error is URLError {
            return true
        }
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain || nsErr.domain == NSPOSIXErrorDomain {
            return true
        }
        return false
    }

    internal func markBackendOffline(error: Error) {
        guard hasPairedBackend || isLiveBackendConnected else { return }
        cancelAllSummaryStreams()
        isLiveBackendConnected = false
        lastPingLatencyMs = nil

        var updatedHost = activeHost
        updatedHost.isOnline = false
        activeHost = updatedHost
        if let idx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
            hosts[idx] = updatedHost
        }
        if updatedHost.channel == .cloudRelay || !isDeviceNetworkReachable {
            for idx in hosts.indices where hosts[idx].channel == updatedHost.channel || !isDeviceNetworkReachable {
                hosts[idx].isOnline = false
            }
            availableRelayInstances = availableRelayInstances.map { inst in
                RelayInstanceInfo(
                    uuid: inst.uuid,
                    name: inst.name,
                    version: inst.version,
                    supportsChunking: inst.supportsChunking,
                    status: .disconnected,
                    updatedAt: inst.updatedAt
                )
            }
        }

        connectionErrorText = error.localizedDescription
        connectionStatusText = "Offline · \(updatedHost.hostname)"

        if isNetworkingSuspended {
            connectionLifecyclePhase = .suspended
        } else if !isDeviceNetworkReachable {
            connectionLifecyclePhase = .noNetwork
        } else {
            let nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelay(
                attempt: reconnectAttemptCount,
                isLowPowerMode: isLowPowerModeEnabled
            )
            connectionLifecyclePhase = .offlineBackoff(attempt: reconnectAttemptCount, nextRetrySeconds: nextDelay)
        }
    }

    internal func markBackendReconnected() {
        let wasOffline = !isLiveBackendConnected || !activeHost.isOnline
        consecutiveSyncFailures = 0
        reconnectAttemptCount = 0
        nextReconnectAt = nil
        lastBackendActivityAt = Date()
        isDeviceNetworkReachable = true
        hasPairedBackend = true
        isLiveBackendConnected = true
        connectionErrorText = nil

        var updatedHost = activeHost
        updatedHost.isOnline = true
        activeHost = updatedHost
        if let idx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
            hosts[idx] = updatedHost
        }
        connectionStatusText = "Connected · \(updatedHost.hostname)"
        connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle

        if wasOffline && !isNetworkingSuspended {
            lastStreamReopenAttemptAt = .distantPast
            ensureSummaryEnvelopeStreamRunning()
            if case .cascadeChat(let cid) = activeRoute, !cid.isEmpty, stepPollingTask == nil {
                syncStepsForCascade(cid, pollUntilIdle: true)
            }
            Task { [weak self] in
                await self?.replayPendingOutbox()
            }
        }
    }

    internal static func normalizeNoProjectSummary(_ s: inout CascadeSummary) {
        guard !esddFixtureCascadeIds.contains(s.cascadeId) else { return }
        guard (s.cloudProjectId ?? "").isEmpty else { return }
        if AntigravityCloudDetector.isGenericContainerURI(s.workspaceUri) {
            s.workspaceUri = ""
        }
        let isScratch = AntigravityCloudDetector.isPlaygroundScratchURI(s.workspaceUri)
        if AntigravityCloudDetector.isNoProjectSlug(s.projectSlug) || isScratch {
            let hasCloudPrefix = s.projectSlug.lowercased().hasPrefix("cloud:")
            s.projectSlug = hasCloudPrefix
                ? "cloud:\(AntigravityCloudDetector.noProjectDisplayName)"
                : AntigravityCloudDetector.noProjectDisplayName
            s.branchName = ""
            if !isScratch && s.workspaceUri.isEmpty == false && AntigravityCloudDetector.isGenericContainerURI(s.workspaceUri) {
                s.workspaceUri = ""
            }
        }
    }

    internal static func reconcileLiveProjects(
        workspaces: [WorkspaceInfo],
        summaries: inout [CascadeSummary],
        existingProjects: [ProjectWorkspace],
        hostName: String,
        cloudProjects: [ProjectWorkspace] = []
    ) -> [ProjectWorkspace] {
        let nonDemoExisting = existingProjects.filter { existing in
            guard !esddFixtureProjectIds.contains(existing.id) else { return false }
            if (existing.cloudProjectId ?? "").isEmpty && AntigravityCloudDetector.isNoProjectSlug(existing.name) {
                return existing.name == AntigravityCloudDetector.noProjectDisplayName
            }
            return true
        }
        var expandedById: [String: Bool] = [:]
        var existingById: [String: ProjectWorkspace] = [:]
        for p in nonDemoExisting {
            expandedById[p.id] = p.isExpandedInHome
            existingById[p.id] = p
        }

        let cloudProjByName = Dictionary(grouping: cloudProjects, by: \.name)

        func baseSlug(for rawSlug: String) -> String {
            if rawSlug.hasPrefix("cloud:") {
                return String(rawSlug.dropFirst("cloud:".count))
            }
            return rawSlug
        }

        // Link Cloud summaries (by projectId, workspaceUri, or owner/repo label) to their canonical Cloud project,
        // and normalize unassigned / legacy `"workspace"` / scratch playground summaries to `"No Project"`.
        for idx in summaries.indices {
            if let cp = AntigravityRPCClient.matchCloudProject(for: summaries[idx], cloudProjects: cloudProjects) {
                summaries[idx].isCloud = true
                summaries[idx].cloudProjectId = cp.cloudProjectId ?? cp.id
                summaries[idx].projectSlug = cp.name
                summaries[idx].workspaceUri = cp.workspaceUri
                summaries[idx].originHostName = "Antigravity"
            } else {
                normalizeNoProjectSummary(&summaries[idx])
            }
        }

        func preferredCloudUri(_ primary: String?, _ secondary: String) -> String {
            if let p = primary, !p.isEmpty {
                let pHasOwner = AntigravityCloudDetector.extractCloudLocationLabel(p)?.contains("/") == true
                let sHasOwner = AntigravityCloudDetector.extractCloudLocationLabel(secondary)?.contains("/") == true
                if !pHasOwner && sHasOwner {
                    return secondary
                }
                return p
            }
            return secondary
        }

        var orderedBaseSlugs: [String] = []
        var seenBaseSlugs = Set<String>()
        for s in summaries {
            let b = baseSlug(for: s.projectSlug)
            if !b.isEmpty && seenBaseSlugs.insert(b).inserted {
                orderedBaseSlugs.append(b)
            }
        }

        let wsByName = Dictionary(grouping: workspaces, by: \.displayName)
        var reconciled: [ProjectWorkspace] = []
        var knownIds = Set<String>()

        for slug in orderedBaseSlugs {
            let isNoProj = AntigravityCloudDetector.isNoProjectSlug(slug)
            let canonicalName = isNoProj ? AntigravityCloudDetector.noProjectDisplayName : slug
            let matchingIndices = summaries.indices.filter { baseSlug(for: summaries[$0].projectSlug) == slug }
            let cloudIndices = matchingIndices.filter { summaries[$0].isCloud }
            let localIndices = matchingIndices.filter { !summaries[$0].isCloud }

            let matchingWorkspaces = isNoProj ? [] : (wsByName[slug] ?? [])
            let cloudWs = matchingWorkspaces.first(where: \.isCloud)
            let localWs = matchingWorkspaces.first(where: { !$0.isCloud })
            let matchedCloudProj = isNoProj ? nil : cloudProjByName[slug]?.first

            if !cloudIndices.isEmpty && !localIndices.isEmpty {
                // Both active local Mac chats and active Cloud chats exist for the same group (`slug` or `No Project`):
                // keep local chats under `canonicalName` and separate Cloud chats under `cloud:<canonicalName>`.
                for idx in localIndices {
                    summaries[idx].projectSlug = canonicalName
                }
                let firstLocal = summaries[localIndices[0]]
                let localUri = isNoProj ? "" : (localWs?.workspaceUri ?? firstLocal.workspaceUri)
                let localBranch = isNoProj ? "" : (localWs?.activeBranch ?? firstLocal.branchName)
                let resolvedLocalHost = localWs?.originHostName ?? firstLocal.originHostName ?? hostName
                let localPathDisplay = isNoProj
                    ? "Unassigned · \(resolvedLocalHost)"
                    : localUri.replacingOccurrences(of: "file://", with: "")
                if knownIds.insert(canonicalName).inserted {
                    reconciled.append(
                        ProjectWorkspace(
                            id: canonicalName,
                            name: canonicalName,
                            pathDisplay: localPathDisplay,
                            workspaceUri: localUri,
                            runtime: .macBookPro,
                            hostName: resolvedLocalHost,
                            activeBranch: localBranch,
                            worktrees: isNoProj ? [] : (localWs?.worktrees.isEmpty == false ? localWs!.worktrees : [localBranch]),
                            isExpandedInHome: expandedById[canonicalName] ?? true,
                            originInstanceUuid: localWs?.originInstanceUuid ?? firstLocal.originInstanceUuid
                        )
                    )
                }

                let cloudId = "cloud:\(canonicalName)"
                for idx in cloudIndices {
                    summaries[idx].projectSlug = cloudId
                }
                let firstCloud = summaries[cloudIndices[0]]
                let cloudUri = isNoProj
                    ? ""
                    : preferredCloudUri(matchedCloudProj?.workspaceUri ?? cloudWs?.workspaceUri, firstCloud.workspaceUri)
                let cloudBranch = isNoProj
                    ? ""
                    : (matchedCloudProj?.activeBranch ?? cloudWs?.activeBranch ?? firstCloud.branchName)
                let cloudPathDisplay = isNoProj ? "Antigravity Cloud · Unassigned" : cloudUri
                if knownIds.insert(cloudId).inserted {
                    reconciled.append(
                        ProjectWorkspace(
                            id: cloudId,
                            name: canonicalName,
                            pathDisplay: cloudPathDisplay,
                            workspaceUri: cloudUri,
                            runtime: .cloud,
                            hostName: "Cloud",
                            activeBranch: cloudBranch,
                            worktrees: isNoProj ? [] : (cloudWs?.worktrees.isEmpty == false ? cloudWs!.worktrees : [cloudBranch]),
                            isExpandedInHome: expandedById[cloudId] ?? true,
                            cloudProjectId: isNoProj ? nil : (matchedCloudProj?.cloudProjectId ?? matchedCloudProj?.id ?? firstCloud.cloudProjectId ?? existingById[cloudId]?.cloudProjectId),
                            originInstanceUuid: matchedCloudProj?.originInstanceUuid ?? firstCloud.originInstanceUuid
                        )
                    )
                }
            } else if !cloudIndices.isEmpty {
                for idx in cloudIndices {
                    summaries[idx].projectSlug = canonicalName
                }
                let firstCloud = summaries[cloudIndices[0]]
                let cloudUri = isNoProj
                    ? ""
                    : preferredCloudUri(matchedCloudProj?.workspaceUri ?? cloudWs?.workspaceUri, firstCloud.workspaceUri)
                let cloudBranch = isNoProj
                    ? ""
                    : (matchedCloudProj?.activeBranch ?? cloudWs?.activeBranch ?? firstCloud.branchName)
                let cloudPathDisplay = isNoProj ? "Antigravity Cloud · Unassigned" : cloudUri
                if knownIds.insert(canonicalName).inserted {
                    reconciled.append(
                        ProjectWorkspace(
                            id: canonicalName,
                            name: canonicalName,
                            pathDisplay: cloudPathDisplay,
                            workspaceUri: cloudUri,
                            runtime: .cloud,
                            hostName: "Cloud",
                            activeBranch: cloudBranch,
                            worktrees: isNoProj ? [] : (cloudWs?.worktrees.isEmpty == false ? cloudWs!.worktrees : [cloudBranch]),
                            isExpandedInHome: expandedById[canonicalName] ?? true,
                            cloudProjectId: isNoProj ? nil : (matchedCloudProj?.cloudProjectId ?? matchedCloudProj?.id ?? firstCloud.cloudProjectId ?? existingById[canonicalName]?.cloudProjectId),
                            originInstanceUuid: matchedCloudProj?.originInstanceUuid ?? firstCloud.originInstanceUuid
                        )
                    )
                }
            } else if !localIndices.isEmpty {
                for idx in localIndices {
                    summaries[idx].projectSlug = canonicalName
                }
                let firstLocal = summaries[localIndices[0]]
                let isWsCloudOnly = !isNoProj && (cloudWs != nil && localWs == nil && AntigravityCloudDetector.isCloudWorkspaceURI(firstLocal.workspaceUri))
                let effectiveUri = isNoProj
                    ? ""
                    : ((isWsCloudOnly ? cloudWs?.workspaceUri : localWs?.workspaceUri) ?? firstLocal.workspaceUri)
                let effectiveBranch = isNoProj ? "" : (localWs?.activeBranch ?? firstLocal.branchName)
                let resolvedLocalHost = localWs?.originHostName ?? firstLocal.originHostName ?? hostName
                let pathDisplay = isNoProj
                    ? "Unassigned · \(resolvedLocalHost)"
                    : effectiveUri.replacingOccurrences(of: "file://", with: "")
                if knownIds.insert(canonicalName).inserted {
                    reconciled.append(
                        ProjectWorkspace(
                            id: canonicalName,
                            name: canonicalName,
                            pathDisplay: pathDisplay,
                            workspaceUri: effectiveUri,
                            runtime: isWsCloudOnly ? .cloud : .macBookPro,
                            hostName: isWsCloudOnly ? "Cloud" : resolvedLocalHost,
                            activeBranch: effectiveBranch,
                            worktrees: isNoProj ? [] : (localWs?.worktrees.isEmpty == false ? localWs!.worktrees : [effectiveBranch]),
                            isExpandedInHome: expandedById[canonicalName] ?? true,
                            originInstanceUuid: localWs?.originInstanceUuid ?? firstLocal.originInstanceUuid
                        )
                    )
                }
            }
        }

        // Append any open 0-conversation workspaces not yet represented above
        for ws in workspaces {
            let slug = ws.displayName
            guard !AntigravityCloudDetector.isNoProjectSlug(slug),
                  !AntigravityCloudDetector.isGenericContainerURI(ws.workspaceUri),
                  !AntigravityCloudDetector.isPlaygroundScratchURI(ws.workspaceUri) else {
                continue
            }
            let isCloud = ws.isCloud || AntigravityCloudDetector.isCloudWorkspaceURI(ws.workspaceUri)
            if reconciled.contains(where: { !$0.workspaceUri.isEmpty && $0.workspaceUri.caseInsensitiveCompare(ws.workspaceUri) == .orderedSame }) {
                continue
            }
            if knownIds.contains(slug) {
                if isCloud,
                   let idx = reconciled.firstIndex(where: { $0.id == slug }),
                   !summaries.contains(where: { $0.projectSlug == slug && !$0.isCloud }) {
                    let mergedUri = preferredCloudUri(reconciled[idx].workspaceUri, ws.workspaceUri)
                    reconciled[idx].runtime = .cloud
                    reconciled[idx].hostName = "Cloud"
                    reconciled[idx].workspaceUri = mergedUri
                    reconciled[idx].pathDisplay = mergedUri
                }
                continue
            }
            knownIds.insert(slug)
            reconciled.append(
                ProjectWorkspace(
                    id: slug,
                    name: slug,
                    pathDisplay: ws.workspaceUri.replacingOccurrences(of: "file://", with: ""),
                    workspaceUri: ws.workspaceUri,
                    runtime: isCloud ? .cloud : .macBookPro,
                    hostName: isCloud ? "Cloud" : (ws.originHostName ?? hostName),
                    activeBranch: ws.activeBranch,
                    worktrees: ws.worktrees.isEmpty ? [ws.activeBranch] : ws.worktrees,
                    isExpandedInHome: expandedById[slug] ?? true,
                    originInstanceUuid: ws.originInstanceUuid
                )
            )
        }

        // Append any 0-conversation Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) projects
        for cp in cloudProjects {
            let cpid = cp.cloudProjectId ?? cp.id
            if let existingIdx = reconciled.firstIndex(where: {
                $0.cloudProjectId == cpid
                    || ($0.runtime == .cloud && $0.name.caseInsensitiveCompare(cp.name) == .orderedSame)
                    || ($0.runtime == .cloud && !cp.workspaceUri.isEmpty && $0.workspaceUri.caseInsensitiveCompare(cp.workspaceUri) == .orderedSame)
            }) {
                reconciled[existingIdx].cloudProjectId = reconciled[existingIdx].cloudProjectId ?? cpid
                reconciled[existingIdx].originInstanceUuid = reconciled[existingIdx].originInstanceUuid ?? cp.originInstanceUuid
                continue
            }
            let targetId = knownIds.contains(cp.name) ? "cloud:\(cp.name)" : cp.name
            guard knownIds.insert(targetId).inserted else { continue }
            reconciled.append(
                ProjectWorkspace(
                    id: targetId,
                    name: cp.name,
                    pathDisplay: cp.workspaceUri,
                    workspaceUri: cp.workspaceUri,
                    runtime: .cloud,
                    hostName: "Cloud",
                    activeBranch: cp.activeBranch,
                    worktrees: [cp.activeBranch],
                    isExpandedInHome: expandedById[targetId] ?? true,
                    cloudProjectId: cpid,
                    originInstanceUuid: cp.originInstanceUuid
                )
            )
        }

        // Preserve any user-created empty projects from `existingById` if workspaces didn't report them yet
        if reconciled.isEmpty {
            return nonDemoExisting.map { existing in
                var copy = existing
                if copy.runtime == .macBookPro {
                    copy.hostName = hostName
                }
                return copy
            }
        }

        // Keep all named projects first (preserving recency order) and `No Project` sections cleanly at the bottom
        let namedProjects = reconciled.filter { !$0.isNoProject }
        let unassignedProjects = reconciled.filter(\.isNoProject)
        return namedProjects + unassignedProjects
    }

    /// Queries the connected `language_server` / `agy` daemon for live models, dual-pool usage quota, custom agents, and Cloud GitHub repos.
    public func refreshModelCatalog(forceRefresh: Bool = false) async {
        guard let client = rpcClient else { return }
        let result = await client.fetchModelCatalog(forceRefresh: forceRefresh)
        if let quota = result.usageQuota {
            usageQuota = quota
            await projectionStore.saveUsageQuota(quota)
        }
        if !result.models.isEmpty {
            availableModels = result.models
            availableAgents = result.agents.isEmpty ? ["Default"] : result.agents

            let currentMode = selectedModelConfig.mode
            let currentPersona = availableAgents.contains(selectedModelConfig.agentPersona)
                ? selectedModelConfig.agentPersona
                : (availableAgents.first ?? "Default")

            let matchedModel: CascadeModelConfig = {
                if let exact = result.models.first(where: { $0.modelId == selectedModelConfig.modelId }) {
                    return exact
                }
                if let defId = result.defaultModelId,
                   let defMatch = result.models.first(where: { $0.modelId == defId }) {
                    return defMatch
                }
                return result.models[0]
            }()

            let preservedEffort = matchedModel.supportedEfforts.contains(selectedModelConfig.effort)
                ? selectedModelConfig.effort
                : matchedModel.effort

            selectedModelConfig = CascadeModelConfig(
                modelId: matchedModel.modelId,
                displayName: matchedModel.displayName,
                subtitle: matchedModel.subtitle,
                hasThinkingBadge: matchedModel.hasThinkingBadge,
                requiresUpgradeNote: matchedModel.requiresUpgradeNote,
                mode: matchedModel.isOrchestrator ? .planning : currentMode,
                agentPersona: currentPersona,
                effort: matchedModel.isOrchestrator ? .high : preservedEffort,
                isModelAlias: matchedModel.isModelAlias,
                badgeTitle: matchedModel.badgeTitle,
                isOrchestrator: matchedModel.isOrchestrator,
                plannerModelName: matchedModel.plannerModelName,
                executorModelName: matchedModel.executorModelName,
                supportedEfforts: matchedModel.supportedEfforts,
                isNewBadge: matchedModel.isNewBadge
            )
        }

        let cloudRepos = await client.fetchCloudGitHubRepos()
        if !cloudRepos.isEmpty {
            availableGitHubRepos = cloudRepos
        }
    }

    internal func applyRecordedConversationConfig(from step: CascadeStep) {
        guard step.recordedExecutionMode != nil || step.recordedModelId != nil else { return }
        let nextMode = step.recordedExecutionMode ?? selectedModelConfig.mode
        var matchedModel: CascadeModelConfig? = nil
        if let rawId = step.recordedModelId, !rawId.isEmpty {
            let normalized = AntigravityRPCClient.normalizeProtoModelEnum(rawId)
            matchedModel = availableModels.first(where: {
                $0.modelId == rawId || AntigravityRPCClient.normalizeProtoModelEnum($0.modelId) == normalized
            })
        }
        if let m = matchedModel {
            selectedModelConfig = CascadeModelConfig(
                modelId: m.modelId,
                displayName: m.displayName,
                subtitle: m.subtitle,
                hasThinkingBadge: m.hasThinkingBadge,
                requiresUpgradeNote: m.requiresUpgradeNote,
                mode: m.isOrchestrator ? .planning : nextMode,
                agentPersona: selectedModelConfig.agentPersona,
                effort: m.effort,
                isModelAlias: m.isModelAlias,
                badgeTitle: m.badgeTitle,
                isOrchestrator: m.isOrchestrator,
                plannerModelName: m.plannerModelName,
                executorModelName: m.executorModelName,
                supportedEfforts: m.supportedEfforts,
                isNewBadge: m.isNewBadge
            )
        } else {
            selectedModelConfig.mode = nextMode
        }
    }

    internal func applyVerifiedLiveConnection(
        host: RemoteHostInstance,
        client: AntigravityRPCClient,
        handshake: BackendHandshakeResult
    ) {
        var updatedHost = host
        updatedHost.latencyMs = handshake.latencyMs
        updatedHost.isOnline = true
        activeHost = updatedHost
        if let existingIdx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
            hosts[existingIdx] = updatedHost
        } else {
            hosts.insert(updatedHost, at: 0)
        }
        rpcClient = client
        consecutiveSyncFailures = 0
        reconnectAttemptCount = 0
        nextReconnectAt = nil
        lastBackendActivityAt = Date()
        lastFullSyncAt = Date()
        lastStreamReopenAttemptAt = .distantPast
        isDeviceNetworkReachable = true
        hasPairedBackend = true
        isLiveBackendConnected = true
        lastPingLatencyMs = handshake.latencyMs
        connectionErrorText = nil
        connectionStatusText = "Connected · \(updatedHost.hostname) · \(handshake.latencyMs)ms"
        connectionLifecyclePhase = .onlineIdle

        workspaces = handshake.workspaces
        var sortedSummaries = handshake.summaries.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.cascadeId < rhs.cascadeId
        }
        let nextProjects = Self.reconcileLiveProjects(
            workspaces: handshake.workspaces,
            summaries: &sortedSummaries,
            existingProjects: [],
            hostName: updatedHost.hostname,
            cloudProjects: handshake.cloudProjects
        )
        summaries = sortedSummaries
        projects = nextProjects
        let defaultProject = nextProjects.first(where: { !$0.isNoProject }) ?? nextProjects.first
        selectedProjectId = defaultProject?.id ?? ""
        selectedWorkspaceUri = defaultProject?.workspaceUri ?? ""
        activeCascadeId = sortedSummaries.first?.cascadeId ?? ""

        // Clear offline ESDD demo state when connected to a live backend
        stepsByCascadeId = [:]
        syncedConfigCascadeIds.removeAll()
        activeTurnDiffs = []
        pendingDraftConversation = nil
        composerWorkflowCommand = nil
        composerDraftText = ""
        composerAttachments = []
        stepLoadErrorText = nil
        automationsErrorText = nil
        isAutomationsAuthExpired = false
        lastAutomationsSyncAt = nil
        automations = []

        let projectsSnapshot = projects
        let summariesSnapshot = summaries
        let storeRef = projectionStore
        Task { [weak self] in
            await storeRef.saveProjects(projectsSnapshot)
            await storeRef.saveProjectedSummaries(summariesSnapshot)
            await self?.refreshModelCatalog()
            await self?.refreshAutomations()
            await self?.replayPendingOutbox()
        }

        startSummarySubscriptionStream()
        if !activeCascadeId.isEmpty {
            syncStepsForCascade(activeCascadeId, pollUntilIdle: false)
        }
    }
}
