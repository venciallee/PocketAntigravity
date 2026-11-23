import Foundation
#if canImport(os)
import os
#endif

/// Backend login, pairing, Cloud Relay / Direct LAN auth, lifecycle suspension, and network path handling.
extension AntigravitySessionStore {
    #if canImport(os)
    private static let cloudRelayLogger = Logger(
        subsystem: "com.thousandtimes.agpocket",
        category: "CloudRelay"
    )
    #endif

    internal static func logCloudRelayDiagnostic(_ message: String) {
        #if canImport(os)
        cloudRelayLogger.notice("\(message, privacy: .public)")
        #endif
    }

    // MARK: - Live Backend Login, Pairing & Streaming Actions

    /// Computes the canonical shard key (`"cloud"` or `"host:<uuid|hostname>"`) for per-host disk caching.
    internal static func projectionHostKey(
        isCloud: Bool,
        instanceId: String?,
        hostname: String?,
        fallbackHostId: String,
        fallbackHostName: String
    ) -> String {
        if isCloud {
            return "cloud"
        }
        if let uuid = instanceId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uuid.isEmpty, uuid != "unpaired" {
            return "host:\(uuid)"
        }
        if let name = hostname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "host:\(name)"
        }
        let trimmedFallbackId = fallbackHostId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFallbackId.isEmpty && trimmedFallbackId != "unpaired" {
            return "host:\(trimmedFallbackId)"
        }
        let trimmedFallbackName = fallbackHostName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFallbackName.isEmpty {
            return "host:\(trimmedFallbackName)"
        }
        return "host:default"
    }

    /// Persists per-host sharded projections (`hosts/host_<key>.json`), paired host roster (`hosts_projection.json`),
    /// and backward-compatible global projections. When `refreshedHostKeys` is provided, only those refreshed shards
    /// are rewritten on disk so offline hosts' cached shards are never overwritten or touched.
    internal func persistHostProjections(refreshedHostKeys: Set<String>? = nil) async {
        let nonFixtureSummaries = summaries.filter { !Self.esddFixtureCascadeIds.contains($0.cascadeId) }
        let nonFixtureProjects = projects.filter { !Self.esddFixtureProjectIds.contains($0.id) }
        let fallbackId = activeHost.instanceId
        let fallbackName = activeHost.hostname

        var summariesByKey: [String: [CascadeSummary]] = [:]
        var projectsByKey: [String: [ProjectWorkspace]] = [:]
        var metaByKey: [String: (instanceId: String?, hostname: String, isCloud: Bool)] = [:]

        for s in nonFixtureSummaries {
            let key = Self.projectionHostKey(
                isCloud: s.isCloud,
                instanceId: s.originInstanceUuid,
                hostname: s.originHostName,
                fallbackHostId: fallbackId,
                fallbackHostName: fallbackName
            )
            summariesByKey[key, default: []].append(s)
            if metaByKey[key] == nil {
                metaByKey[key] = s.isCloud
                    ? (nil, "Antigravity", true)
                    : (s.originInstanceUuid, s.originHostName ?? fallbackName, false)
            }
        }

        for p in nonFixtureProjects {
            let isCloud = (p.runtime == .cloud)
            let key = Self.projectionHostKey(
                isCloud: isCloud,
                instanceId: p.originInstanceUuid,
                hostname: p.hostName,
                fallbackHostId: fallbackId,
                fallbackHostName: fallbackName
            )
            projectsByKey[key, default: []].append(p)
            if metaByKey[key] == nil {
                metaByKey[key] = isCloud
                    ? (nil, "Antigravity", true)
                    : (p.originInstanceUuid, p.hostName.isEmpty ? fallbackName : p.hostName, false)
            }
        }

        let keysToWrite: Set<String> = {
            if let refreshedHostKeys, !refreshedHostKeys.isEmpty {
                return refreshedHostKeys
            }
            return Set(summariesByKey.keys).union(projectsByKey.keys)
        }()

        let now = Date()
        var shardsToSave: [HostProjectionSnapshot] = []
        for key in keysToWrite {
            let meta: (instanceId: String?, hostname: String, isCloud: Bool) = {
                if let existing = metaByKey[key] {
                    return existing
                }
                if key == "cloud" {
                    return (nil, "Antigravity", true)
                }
                let rawId = key.hasPrefix("host:") ? String(key.dropFirst("host:".count)) : key
                let matchedHost = hosts.first(where: { $0.instanceId == rawId || $0.hostname == rawId })
                return (matchedHost?.instanceId ?? rawId, matchedHost?.hostname ?? rawId, false)
            }()
            shardsToSave.append(
                HostProjectionSnapshot(
                    hostKey: key,
                    instanceId: meta.instanceId,
                    hostname: meta.hostname,
                    isCloud: meta.isCloud,
                    summaries: summariesByKey[key] ?? [],
                    projects: projectsByKey[key] ?? [],
                    updatedAt: now
                )
            )
        }

        let localHostsSnapshot = pairedLocalHosts
        let projectsSnapshot = nonFixtureProjects
        let summariesSnapshot = nonFixtureSummaries
        let storeRef = projectionStore
        await storeRef.saveHostProjections(shardsToSave)
        if !localHostsSnapshot.isEmpty {
            await storeRef.saveKnownHosts(localHostsSnapshot)
        }
        await storeRef.saveProjects(projectsSnapshot)
        await storeRef.saveProjectedSummaries(summariesSnapshot)
    }

    /// Instantly hydrates cached per-host conversations, projects, and paired host roster from disk (`<10ms`)
    /// BEFORE waiting on the live network handshake so cold launches show all online/offline hosts immediately.
    public func hydratePersistedHostProjectionsIfNeeded(
        savedCredentials: SavedBackendCredentials? = nil
    ) async {
        guard !isVerificationMode else { return }

        let shards = await projectionStore.loadAllHostProjections()
        let savedKnownHosts = await projectionStore.loadKnownHosts()

        var hydratedHosts: [RemoteHostInstance] = []
        var seenHostIds = Set<String>()

        func appendOfflineHostIfNeeded(_ host: RemoteHostInstance) {
            guard host.instanceId != "unpaired", !host.instanceId.isEmpty else { return }
            if seenHostIds.insert(host.instanceId).inserted {
                var offlineCopy = host
                offlineCopy.isOnline = false
                hydratedHosts.append(offlineCopy)
            }
        }

        for savedHost in savedKnownHosts {
            appendOfflineHostIfNeeded(savedHost)
        }

        var primaryOfflineHost: RemoteHostInstance? = nil
        if let saved = savedCredentials {
            let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(saved.endpointURLString)
            let credId: String = {
                if let resolved = saved.resolvedInstanceUuid, !resolved.isEmpty {
                    return resolved
                }
                if let parsedId = parsedTarget?.instanceId, !parsedId.isEmpty {
                    return parsedId
                }
                if saved.channel == .directHost, let host = URL(string: saved.endpointURLString)?.host {
                    return "direct-\(host)"
                }
                return saved.hostname
            }()
            let credURL = URL(string: saved.endpointURLString)
                ?? URL(string: SAPISIDHashGenerator.defaultOrigin)!
            let credHost = RemoteHostInstance(
                instanceId: credId,
                hostname: saved.hostname,
                channel: saved.channel,
                endpointURL: credURL,
                isOnline: false,
                certificateFingerprintSHA256: saved.certFingerprintSHA256 ?? ""
            )
            if let existing = hydratedHosts.first(where: { $0.instanceId == credId || $0.hostname == saved.hostname }) {
                primaryOfflineHost = existing
            } else {
                appendOfflineHostIfNeeded(credHost)
                primaryOfflineHost = credHost
            }
        }

        // Also surface any offline local host discovered in cached shards even if `hosts_projection.json` wasn't saved yet
        let defaultChannel: RemoteConnectionChannel = savedCredentials?.channel ?? activeHost.channel
        for shard in shards where !shard.isCloud {
            let shardId = (shard.instanceId?.isEmpty == false)
                ? shard.instanceId!
                : (shard.hostKey.hasPrefix("host:") ? String(shard.hostKey.dropFirst("host:".count)) : shard.hostKey)
            guard !shardId.isEmpty, shardId != "default", shardId != "unpaired" else { continue }
            if !hydratedHosts.contains(where: { $0.instanceId == shardId || $0.hostname == shard.hostname }) {
                let fallbackURL = URL(string: "\(SAPISIDHashGenerator.defaultOrigin)/r/\(shardId)")
                    ?? activeHost.endpointURL
                appendOfflineHostIfNeeded(
                    RemoteHostInstance(
                        instanceId: shardId,
                        hostname: shard.hostname.isEmpty ? shardId : shard.hostname,
                        channel: defaultChannel,
                        endpointURL: fallbackURL,
                        isOnline: false
                    )
                )
            }
        }

        var mergedSummariesById: [String: CascadeSummary] = [:]
        var cachedProjects: [ProjectWorkspace] = []
        var cachedCloudProjects: [ProjectWorkspace] = []
        var cachedWorkspaces: [WorkspaceInfo] = []
        var seenWorkspaceKeys = Set<String>()

        for shard in shards {
            for s in shard.summaries where !Self.esddFixtureCascadeIds.contains(s.cascadeId) {
                if let existing = mergedSummariesById[s.cascadeId] {
                    if s.updatedAt > existing.updatedAt || s.stepCount > existing.stepCount {
                        mergedSummariesById[s.cascadeId] = s
                    }
                } else {
                    mergedSummariesById[s.cascadeId] = s
                }
            }
            for p in shard.projects where !Self.esddFixtureProjectIds.contains(p.id) {
                cachedProjects.append(p)
                if p.runtime == .cloud {
                    cachedCloudProjects.append(p)
                } else if !p.isNoProject && !p.workspaceUri.isEmpty {
                    let wsKey = "\(p.originInstanceUuid ?? p.hostName)|\(p.workspaceUri.lowercased())"
                    if seenWorkspaceKeys.insert(wsKey).inserted {
                        cachedWorkspaces.append(
                            WorkspaceInfo(
                                workspaceUri: p.workspaceUri,
                                displayName: p.name,
                                activeBranch: p.activeBranch,
                                worktrees: p.worktrees,
                                isCloud: false,
                                originInstanceUuid: p.originInstanceUuid,
                                originHostName: p.hostName
                            )
                        )
                    }
                }
            }
        }

        var hydratedSummaries = mergedSummariesById.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.cascadeId < rhs.cascadeId
        }

        guard savedCredentials != nil || !hydratedSummaries.isEmpty || !cachedProjects.isEmpty else {
            return
        }

        if !hydratedHosts.isEmpty {
            hosts = hydratedHosts
            if let primaryOfflineHost {
                activeHost = primaryOfflineHost
            } else if activeHost.instanceId == "unpaired", let first = hydratedHosts.first {
                activeHost = first
            }
            if availableRelayInstances.isEmpty {
                let relayHosts = hydratedHosts.filter { $0.channel == .cloudRelay }
                if !relayHosts.isEmpty {
                    availableRelayInstances = relayHosts.map { host in
                        RelayInstanceInfo(
                            uuid: host.instanceId,
                            name: host.hostname,
                            version: host.version,
                            status: .disconnected
                        )
                    }
                }
            }
        }

        if let savedScope = loadPersistedSelectedHostScope() {
            selectedHostScope = savedScope
            reconcileSelectedHostScopeWithHosts()
        }

        if !hydratedSummaries.isEmpty || !cachedProjects.isEmpty {
            let reconciled = Self.reconcileLiveProjects(
                workspaces: cachedWorkspaces,
                summaries: &hydratedSummaries,
                existingProjects: cachedProjects,
                hostName: activeHost.hostname,
                cloudProjects: cachedCloudProjects
            )
            workspaces = cachedWorkspaces
            projects = reconciled
            summaries = hydratedSummaries
            if selectedProjectId.isEmpty {
                let defaultProj = reconciled.first(where: { projectMatchesHostScope($0) && !$0.isNoProject })
                    ?? reconciled.first(where: { !$0.isNoProject })
                    ?? reconciled.first
                selectedProjectId = defaultProj?.id ?? ""
                selectedWorkspaceUri = defaultProj?.workspaceUri ?? ""
            }
            if activeCascadeId.isEmpty {
                activeCascadeId = hydratedSummaries.first?.cascadeId ?? ""
            }
        }

        let cachedAutomations = (await projectionStore.loadAutomations()).filter {
            !Self.esddFixtureAutomationIds.contains($0.id)
        }
        if automations.isEmpty && !cachedAutomations.isEmpty {
            automations = cachedAutomations
        }
        pendingOutboxCount = await projectionStore.loadPendingOutbox().count

        if let saved = savedCredentials {
            persistPairedHostLaunchHint(from: saved)
            isOptimisticInitialPairing = false
        }
        hasPairedBackend = true
        isLiveBackendConnected = false
        isInitialSessionCheckComplete = true
        connectionLifecyclePhase = savedCredentials != nil ? .connecting : .offlineBackoff(attempt: 0, nextRetrySeconds: 3)
        connectionStatusText = savedCredentials != nil
            ? "Connecting · \(activeHost.hostname)..."
            : "Offline · \(activeHost.hostname)"
    }

    // MARK: - Fast Frame-0 Launch & Non-Secret Launch Hint

    internal func persistPairedHostLaunchHint(_ hint: PairedHostLaunchHint) {
        guard !isVerificationMode else { return }
        if let data = try? JSONEncoder().encode(hint),
           let json = String(data: data, encoding: .utf8) {
            preferencesStore.set(json, forKey: Self.pairedHostLaunchHintDefaultsKey)
        }
    }

    internal func persistPairedHostLaunchHint(from credentials: SavedBackendCredentials) {
        persistPairedHostLaunchHint(PairedHostLaunchHint(credentials: credentials))
    }

    internal func loadPairedHostLaunchHint() -> PairedHostLaunchHint? {
        guard !isVerificationMode,
              let raw = preferencesStore.string(forKey: Self.pairedHostLaunchHintDefaultsKey),
              let decoded = try? JSONDecoder().decode(PairedHostLaunchHint.self, from: Data(raw.utf8)) else {
            return nil
        }
        return decoded
    }

    internal func clearPairedHostLaunchHint() {
        guard !isVerificationMode else { return }
        preferencesStore.set(nil, forKey: Self.pairedHostLaunchHintDefaultsKey)
    }

    /// Immediately transitions the UI into the Conversations shell (or deep-linked chat) with a non-blocking
    /// loading state before the remote network handshake finishes so the app never stalls on the Welcome screen.
    public func beginOptimisticConnectingSession(
        hostName: String,
        channel: RemoteConnectionChannel,
        endpointURLString: String,
        instanceId: String? = nil,
        deepLinkedConversationId: String? = nil,
        isRestoringSaved: Bool = false
    ) {
        guard !isVerificationMode else { return }
        let trimmedHost = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayHost = trimmedHost.isEmpty
            ? (channel == .cloudRelay ? "Antigravity Desktop" : "MacBook Pro")
            : trimmedHost
        let fallbackURL = URL(string: SAPISIDHashGenerator.defaultOrigin)!
        let resolvedURL = URL(string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallbackURL
        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(endpointURLString)
        let resolvedId: String = {
            if let explicit = instanceId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !explicit.isEmpty, explicit != "unpaired" {
                return explicit
            }
            if let parsedId = parsedTarget?.instanceId, !parsedId.isEmpty {
                return parsedId
            }
            if channel == .directHost, let host = resolvedURL.host, !host.isEmpty {
                return "direct-\(host)"
            }
            return displayHost
        }()

        let placeholderHost = RemoteHostInstance(
            instanceId: resolvedId,
            hostname: displayHost,
            channel: channel,
            endpointURL: resolvedURL,
            isOnline: false
        )
        hosts.removeAll { $0.instanceId == "unpaired" }
        if !hosts.contains(where: { $0.instanceId == placeholderHost.instanceId }) {
            hosts.insert(placeholderHost, at: 0)
        }
        if activeHost.instanceId == "unpaired" || activeHost.instanceId == placeholderHost.instanceId || !hasPairedBackend {
            activeHost = placeholderHost
        }

        let alreadyVerified = hasPairedBackend && !isOptimisticInitialPairing
        hasPairedBackend = true
        isLiveBackendConnected = false
        isInitialSessionCheckComplete = true
        isConnectingToBackend = true
        isOptimisticInitialPairing = !isRestoringSaved && !alreadyVerified
        connectionErrorText = nil
        connectionLifecyclePhase = .connecting
        connectionStatusText = "Connecting · \(displayHost)..."

        if let cid = deepLinkedConversationId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty {
            activeCascadeId = cid
            activeRoute = .cascadeChat(cid)
        } else if activeRoute == .pairingSettings {
            activeRoute = .tabRoot
        }
    }

    /// Synchronous (`<1ms`) Frame-0 launch preparation run inside `AntigravityApp.init()`:
    /// - Returning paired users and env-configured launches enter the Conversations screen on Frame 0
    ///   (with inline loading) instead of flashing or blocking on `AntigravityWelcomeView`.
    /// - Brand-new unpaired users immediately resolve `isInitialSessionCheckComplete = true` so
    ///   "Scan Remote Control QR" renders without a "Checking saved connection..." spinner.
    public func prepareFastLaunchSessionState(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard !isVerificationMode else { return }

        if let relayURL = environment["ANTIGRAVITY_RELAY_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !relayURL.isEmpty {
            let parsed = RemoteHostInstance.parseRemoteControlTarget(relayURL)
            let hostName = environment["ANTIGRAVITY_HOST_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayHost = (hostName?.isEmpty == false ? hostName! : nil)
                ?? (parsed?.instanceId.isEmpty == false ? parsed!.instanceId : "Antigravity Desktop")
            beginOptimisticConnectingSession(
                hostName: displayHost,
                channel: .cloudRelay,
                endpointURLString: relayURL,
                instanceId: parsed?.instanceId,
                deepLinkedConversationId: parsed?.conversationId,
                isRestoringSaved: false
            )
            return
        }

        if let backendURL = environment["ANTIGRAVITY_BACKEND_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !backendURL.isEmpty {
            let hostName = environment["ANTIGRAVITY_HOST_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            beginOptimisticConnectingSession(
                hostName: (hostName?.isEmpty == false ? hostName! : "MacBook Pro"),
                channel: .directHost,
                endpointURLString: backendURL,
                isRestoringSaved: false
            )
            return
        }

        let launchHint = loadPairedHostLaunchHint()

        if let hint = launchHint {
            if let savedScope = loadPersistedSelectedHostScope() {
                selectedHostScope = savedScope
            }
            beginOptimisticConnectingSession(
                hostName: hint.hostname,
                channel: hint.channel,
                endpointURLString: hint.endpointURLString,
                instanceId: hint.instanceId,
                isRestoringSaved: true
            )
        } else {
            hasPairedBackend = false
            isLiveBackendConnected = false
            isConnectingToBackend = false
            isOptimisticInitialPairing = false
            isInitialSessionCheckComplete = true
        }
    }

    /// Loads Keychain credentials and immediately hydrates cached per-host projections from disk (`<10ms`)
    /// so cached conversations appear right away before any KMP runtime or network handshake completes.
    /// If a stale launch hint existed without backing Keychain credentials (e.g. device restore), cleanly resets
    /// back to the unpaired Welcome screen.
    public func hydrateSavedSessionFromDisk() async -> SavedBackendCredentials? {
        guard !isVerificationMode else { return nil }
        guard let saved = await secretStore.loadCredentials() else {
            clearPairedHostLaunchHint()
            if hasPairedBackend && !isLiveBackendConnected && !isOptimisticInitialPairing && rpcClient == nil {
                hasPairedBackend = false
                isConnectingToBackend = false
                connectionLifecyclePhase = .disconnected
                connectionStatusText = "Not Connected"
                hosts.removeAll()
                activeRoute = .tabRoot
            }
            isInitialSessionCheckComplete = true
            return nil
        }
        persistPairedHostLaunchHint(from: saved)
        await hydratePersistedHostProjectionsIfNeeded(savedCredentials: saved)
        return saved
    }

    /// Connects live using already-loaded `SavedBackendCredentials` (preserving offline cache on failure).
    @discardableResult
    public func connectSavedCredentials(_ saved: SavedBackendCredentials) async -> Bool {
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
            let hasExplicitLocalScope: Bool = {
                if case .localHost = loadPersistedSelectedHostScope() {
                    return true
                }
                return false
            }()
            return await connectCloudRelay(
                relayURLString: saved.endpointURLString,
                sessionCookie: saved.sessionCookie ?? "",
                authUser: saved.authUser,
                resolvedInstanceUuid: saved.resolvedInstanceUuid,
                relayApiKey: saved.relayApiKey,
                hostName: saved.hostname,
                isRestoringSavedSession: true,
                strictTargetMatch: hasExplicitLocalScope
            )
        }
    }

    /// Restores saved Keychain credentials on launch: instantly hydrates cached per-host projections from disk
    /// (`<10ms`) so both online and offline hosts' conversations appear immediately, then connects live to merge fresh data.
    @discardableResult
    public func restoreSavedBackendSession() async -> Bool {
        guard let saved = await hydrateSavedSessionFromDisk() else {
            return false
        }
        return await connectSavedCredentials(saved)
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
        let wasOptimisticInitial = isOptimisticInitialPairing && !isRestoringSavedSession
        guard let url = URL(string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            if wasOptimisticInitial {
                isOptimisticInitialPairing = false
                hasPairedBackend = false
                isLiveBackendConnected = false
                connectionLifecyclePhase = .disconnected
            }
            isConnectingToBackend = false
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
            let handshake: BackendHandshakeResult
            if let kmpEngine {
                handshake = try await kmpEngine.connectDirectLan(
                    endpointURLString: url.absoluteString,
                    csrfToken: csrfToken,
                    certSHA256: certSHA256,
                    hostName: hostName,
                    isRestoringSavedSession: isRestoringSavedSession
                )
            } else {
                handshake = try await candidateClient.verifyConnection()
            }
            applyVerifiedLiveConnection(
                host: hostInstance,
                client: candidateClient,
                handshake: handshake
            )
            startKmpSummarySubscriptionIfNeeded()
            let savedCredentials = SavedBackendCredentials(
                endpointURLString: url.absoluteString,
                channel: .directHost,
                hostname: hostName,
                csrfToken: csrfToken,
                certFingerprintSHA256: certSHA256
            )
            persistPairedHostLaunchHint(from: savedCredentials)
            await secretStore.saveCredentials(savedCredentials)
            return true
        } catch let AntigravityRPCError.unauthorized(reason) {
            let errMsg = "Authentication rejected (401/403): check x-codeium-csrf-token. \(reason)"
            let statusMsg = "Auth Failed · Invalid CSRF Token"
            if isRestoringSavedSession || (hasPairedBackend && !wasOptimisticInitial) {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName) (Auth Expired)"
                )
            } else {
                isOptimisticInitialPairing = false
                hasPairedBackend = false
                isLiveBackendConnected = false
                connectionLifecyclePhase = .disconnected
                connectionErrorText = errMsg
                connectionStatusText = statusMsg
            }
            return false
        } catch {
            let errMsg = "Connection failed: \(error.localizedDescription)"
            if isRestoringSavedSession || (hasPairedBackend && !wasOptimisticInitial) {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName)"
                )
            } else {
                isOptimisticInitialPairing = false
                hasPairedBackend = false
                isLiveBackendConnected = false
                connectionLifecyclePhase = .disconnected
                connectionErrorText = errMsg
                connectionStatusText = "Unreachable · \(url.host ?? endpointURLString)"
            }
            return false
        }
    }

    ///Resolves HTTP redirects for official Google shortlinks (`g.co`, `c.gle`, `goo.gl`, `*.page.link`)
    /// using an ephemeral `URLSession` (without attaching session cookies) so the target `/r/<instance-id>` is discovered.
    nonisolated private static func resolveShortlinkRedirectIfNeeded(_ urlString: String) async -> String? {
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
        relayApiKey: String? = nil,
        deepLinkedConversationId: String? = nil,
        hostName: String = "Antigravity Desktop",
        isRestoringSavedSession: Bool = false,
        strictTargetMatch: Bool = false,
        ignoreCachedRelayApiKey: Bool = false
    ) async -> Bool {
        let wasOptimisticInitial = isOptimisticInitialPairing && !isRestoringSavedSession
        let trimmedInput = relayURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedTarget = RemoteHostInstance.parseRemoteControlTarget(
            trimmedInput.isEmpty ? SAPISIDHashGenerator.defaultOrigin : trimmedInput
        )
        var canonicalURLString = parsedTarget?.canonicalRelayURLString ?? trimmedInput
        guard URL(string: canonicalURLString)?.scheme != nil else {
            if wasOptimisticInitial {
                isOptimisticInitialPairing = false
                hasPairedBackend = false
                isLiveBackendConnected = false
                connectionLifecyclePhase = .disconnected
            }
            isConnectingToBackend = false
            connectionErrorText = "Invalid Remote Control QR link: \(relayURLString)"
            return false
        }

        lastScannedRelayURL = canonicalURLString
        let trimmedCookie = sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCookie.isEmpty else {
            if wasOptimisticInitial {
                isOptimisticInitialPairing = false
                hasPairedBackend = false
                connectionLifecyclePhase = .disconnected
            }
            isConnectingToBackend = false
            isLiveBackendConnected = false
            let fallbackName = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : "Antigravity Desktop"
            connectionErrorText = "Google Sign-In required: sign in once to pair with \(fallbackName)."
            connectionStatusText = "Sign in with Google to pair Remote Control"
            return false
        }

        hostSwitchGeneration &+= 1
        let generation = hostSwitchGeneration
        if !strictTargetMatch {
            hostSwitchTask?.cancel()
            hostSwitchTask = nil
        }
        cancelAllSummaryStreams()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        stepPollingTask?.cancel()
        stepPollingTask = nil

        isConnectingToBackend = true
        connectionErrorText = nil
        defer {
            if self.hostSwitchGeneration == generation {
                self.isConnectingToBackend = false
                self.isSwitchingHost = false
                if !self.isLiveBackendConnected && self.connectionLifecyclePhase == .connecting {
                    self.connectionLifecyclePhase = self.hasPairedBackend
                        ? .offlineBackoff(
                            attempt: 0,
                            nextRetrySeconds: ConnectionPowerPolicy.offlineBackoffBaseDelay(
                                attempt: 0,
                                isLowPowerMode: self.isLowPowerModeEnabled
                            )
                        )
                        : .disconnected
                }
            }
        }

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
            if wasOptimisticInitial {
                isOptimisticInitialPairing = false
                hasPairedBackend = false
                isLiveBackendConnected = false
                connectionLifecyclePhase = .disconnected
            }
            connectionErrorText = "Invalid Remote Control QR link: \(relayURLString)"
            return false
        }

        let targetBadge = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : "Cloud Relay"
        connectionStatusText = "Pairing with \(targetBadge) via Google Cloud Relay..."

        let effectiveAuthUser = authUser ?? parsedTarget?.authUser
        let initialInstanceId = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : "auto"
        let deepLinkConv = deepLinkedConversationId ?? parsedTarget?.conversationId
        let initialOriginPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
        let trimmedExplicitKey = relayApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        var effectiveRelayApiKey: String? = (trimmedExplicitKey?.isEmpty == false ? trimmedExplicitKey : nil)
        if effectiveRelayApiKey == nil && !ignoreCachedRelayApiKey && !SAPISIDHashGenerator.isLoopbackOrigin(initialOriginPrefix) {
            if let originCachedKey = await secretStore.loadRelayWebApiKey(forOrigin: initialOriginPrefix) {
                effectiveRelayApiKey = originCachedKey
            } else if let savedCredsKey = await secretStore.loadCredentials()?.relayApiKey?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                      !savedCredsKey.isEmpty {
                effectiveRelayApiKey = savedCredsKey
            }
        }

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
            resolvedInstanceUuid: resolvedInstanceUuid,
            relayApiKey: effectiveRelayApiKey
        )

        let handshakeURLString = canonicalURLString
        let handshakeApiKey = effectiveRelayApiKey
        let activeEngine = kmpEngine
        let engineLabel = activeEngine?.engineName ?? "Swift-URLSession"
        let cookieSummary = SAPISIDHashGenerator.summarizeCookieNames(trimmedCookie)
        let keySummary = handshakeApiKey.map { "len:\($0.count)" } ?? "none"
        Self.logCloudRelayDiagnostic(
            "Handshake start engine=\(engineLabel) origin=\(initialOriginPrefix) target=\(targetBadge) authUser=\(effectiveAuthUser ?? "auto") key=\(keySummary) ck=\(cookieSummary) restore=\(isRestoringSavedSession) strict=\(strictTargetMatch)"
        )

        do {
            let handshake: BackendHandshakeResult = try await withThrowingTaskGroup(of: BackendHandshakeResult.self) { group in
                group.addTask {
                    if let activeEngine {
                        return try await activeEngine.connectCloudRelay(
                            relayURLString: handshakeURLString,
                            sessionCookie: trimmedCookie,
                            authUser: effectiveAuthUser,
                            resolvedInstanceUuid: resolvedInstanceUuid,
                            relayApiKey: handshakeApiKey,
                            hostName: hostName,
                            isRestoringSavedSession: isRestoringSavedSession,
                            strictTargetMatch: strictTargetMatch
                        )
                    } else {
                        return try await candidateClient.verifyConnection(
                            allowCrossHostFallback: !strictTargetMatch
                        )
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 28_000_000_000)
                    let diag: String = {
                        if let activeEngine {
                            let kmpDiag = activeEngine.lastHandshakeDiagnostic
                            if !kmpDiag.isEmpty {
                                return kmpDiag
                            }
                            return "engine=\(activeEngine.engineName) origin=\(initialOriginPrefix) key=\(keySummary) ck=\(cookieSummary) trace=no-kmp-trace"
                        }
                        return candidateClient.currentHandshakeDiagnostic()
                    }()
                    throw AntigravityRPCError.httpError(
                        statusCode: 504,
                        body: "Cloud Relay handshake timed out after 28s. Check Google / VPN reachability or tap Sign in with Google. [\(diag)]"
                    )
                }
                guard let first = try await group.next() else {
                    throw AntigravityRPCError.httpError(statusCode: 504, body: "Cloud Relay handshake cancelled")
                }
                group.cancelAll()
                return first
            }
            guard self.hostSwitchGeneration == generation else { return false }

            let finalHostName = handshake.resolvedHostname ?? hostName
            let finalUuid = handshake.resolvedInstanceUuid ?? hostInstance.instanceId
            let finalAuthUser = handshake.resolvedAuthUser ?? effectiveAuthUser ?? "0"
            let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
            let finalRelayURL = URL(string: "\(originPrefix)/r/\(finalUuid)") ?? url
            let handshakeApiKey = handshake.resolvedRelayApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            let kmpSavedApiKey: String? = (kmpEngine != nil && (handshakeApiKey?.isEmpty != false))
                ? await secretStore.loadCredentials()?.relayApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let candidateApiKey = await candidateClient.currentRelayApiKey()
            let finalRelayApiKey = (handshakeApiKey?.isEmpty == false ? handshakeApiKey : nil)
                ?? candidateApiKey
                ?? effectiveRelayApiKey
                ?? (kmpSavedApiKey?.isEmpty == false ? kmpSavedApiKey : nil)

            Self.logCloudRelayDiagnostic(
                "Handshake OK engine=\(engineLabel) host=\(finalHostName) online=\(handshake.isSelectedHostOnline) instances=\(handshake.availableRelayInstances.count) workspaces=\(handshake.workspaces.count) summaries=\(handshake.summaries.count) authUser=\(finalAuthUser) latencyMs=\(handshake.latencyMs)"
            )

            if kmpEngine != nil {
                await candidateClient.seedRelayState(
                    resolvedInstanceUuid: finalUuid,
                    authUser: finalAuthUser,
                    relayApiKey: finalRelayApiKey,
                    relayInstances: handshake.availableRelayInstances
                )
            }

            let verifiedHost = RemoteHostInstance(
                instanceId: finalUuid,
                hostname: finalHostName,
                version: handshake.serverVersion,
                channel: .cloudRelay,
                endpointURL: finalRelayURL,
                isOnline: handshake.isSelectedHostOnline,
                latencyMs: handshake.latencyMs
            )

            availableRelayInstances = handshake.availableRelayInstances
            activeAuthUser = finalAuthUser
            applyVerifiedLiveConnection(
                host: verifiedHost,
                client: candidateClient,
                handshake: handshake
            )
            startKmpSummarySubscriptionIfNeeded()

            // Sync all Cloud Relay instances (online & offline) into `hosts` so Home reflects per-device reachability
            let activeRelayInst = handshake.availableRelayInstances.first(where: { $0.uuid == finalUuid })
            syncRelayInstancesToHosts(
                handshake.availableRelayInstances,
                latencyMs: handshake.latencyMs,
                preferredActiveInstance: activeRelayInst,
                persistKeychainIfChanged: false
            )

            if let finalRelayApiKey,
               !finalRelayApiKey.isEmpty,
               !SAPISIDHashGenerator.isLoopbackOrigin(originPrefix) {
                await secretStore.saveRelayWebApiKey(finalRelayApiKey, forOrigin: originPrefix)
            }

            let hasMultipleLocalHosts = pairedLocalHosts.count > 1
            if strictTargetMatch {
                selectedHostScope = .localHost(id: finalUuid, name: finalHostName)
                persistSelectedHostScope()
            } else if isRestoringSavedSession {
                if let savedScope = loadPersistedSelectedHostScope() {
                    selectedHostScope = savedScope
                    reconcileSelectedHostScopeWithHosts()
                } else if hasMultipleLocalHosts {
                    selectedHostScope = .localHost(id: finalUuid, name: finalHostName)
                    persistSelectedHostScope()
                } else {
                    selectedHostScope = .allHosts
                }
            } else if hasMultipleLocalHosts && initialInstanceId != "auto" {
                selectedHostScope = .localHost(id: finalUuid, name: finalHostName)
                persistSelectedHostScope()
            } else {
                selectedHostScope = .allHosts
            }

            if !handshake.isSelectedHostOnline {
                isLiveBackendConnected = false
                var offlineHost = verifiedHost
                offlineHost.isOnline = false
                activeHost = offlineHost
                if let idx = hosts.firstIndex(where: { $0.instanceId == offlineHost.instanceId }) {
                    hosts[idx] = offlineHost
                }
                connectionStatusText = "Offline · \(finalHostName)"
                connectionErrorText = "\(finalHostName) is currently offline. Ensure Remote Control is enabled on that machine."
                let nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelay(
                    attempt: 0,
                    isLowPowerMode: isLowPowerModeEnabled
                )
                connectionLifecyclePhase = .offlineBackoff(attempt: 0, nextRetrySeconds: nextDelay)
            }

            let savedCredentials = SavedBackendCredentials(
                endpointURLString: finalRelayURL.absoluteString,
                channel: .cloudRelay,
                hostname: finalHostName,
                sessionCookie: trimmedCookie,
                authUser: finalAuthUser,
                resolvedInstanceUuid: finalUuid,
                relayApiKey: finalRelayApiKey
            )
            persistPairedHostLaunchHint(from: savedCredentials)
            await secretStore.saveCredentials(savedCredentials)

            if let deepLinkConv, !deepLinkConv.isEmpty {
                selectCascade(deepLinkConv)
            }
            return true
        } catch let AntigravityRPCError.unauthorized(reason) {
            guard self.hostSwitchGeneration == generation else { return false }
            Self.logCloudRelayDiagnostic("Handshake Unauthorized engine=\(engineLabel) reason=\(reason)")
            if !SAPISIDHashGenerator.isLoopbackOrigin(initialOriginPrefix) {
                await secretStore.clearRelayWebApiKey(forOrigin: initialOriginPrefix)
            }
            let errMsg = "Google session unauthorized: please sign in again. (\(reason))"
            if isRestoringSavedSession {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Google Sign-In Expired"
                )
            } else {
                if wasOptimisticInitial {
                    isOptimisticInitialPairing = false
                    hasPairedBackend = false
                }
                isLiveBackendConnected = false
                connectionLifecyclePhase = .disconnected
                connectionErrorText = errMsg
                connectionStatusText = "Google Sign-In Expired"
            }
            return false
        } catch let AntigravityRPCError.httpError(code, body) {
            guard self.hostSwitchGeneration == generation else { return false }
            Self.logCloudRelayDiagnostic("Handshake HTTP error engine=\(engineLabel) status=\(code) detail=\(body)")
            let errMsg = "Cloud Relay error (\(code)): \(body)"
            if (isRestoringSavedSession || (hasPairedBackend && !wasOptimisticInitial)) && (code == 502 || code == 503 || code == 504) {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName)"
                )
            } else {
                if wasOptimisticInitial {
                    isOptimisticInitialPairing = false
                    hasPairedBackend = false
                }
                isLiveBackendConnected = false
                connectionLifecyclePhase = .disconnected
                connectionErrorText = errMsg
                connectionStatusText = "Cloud Relay Handshake Failed"
            }
            return false
        } catch {
            guard self.hostSwitchGeneration == generation else { return false }
            Self.logCloudRelayDiagnostic("Handshake failed engine=\(engineLabel) error=\(error.localizedDescription)")
            let errMsg = "Cloud Relay handshake failed: \(error.localizedDescription)"
            if isRestoringSavedSession || (hasPairedBackend && !wasOptimisticInitial) {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName)"
                )
            } else {
                if wasOptimisticInitial {
                    isOptimisticInitialPairing = false
                    hasPairedBackend = false
                }
                isLiveBackendConnected = false
                connectionLifecyclePhase = .disconnected
                connectionErrorText = errMsg
                connectionStatusText = "Cloud Relay Disconnected"
            }
            return false
        }
    }

    /// Immediately aborts any in-flight pairing/reconnect UI spinner so the user can retry or sign in again.
    public func cancelPendingConnectionAttempt() {
        hostSwitchGeneration &+= 1
        hostSwitchTask?.cancel()
        hostSwitchTask = nil
        isConnectingToBackend = false
        isSwitchingHost = false
        if isOptimisticInitialPairing && !isLiveBackendConnected {
            isOptimisticInitialPairing = false
            hasPairedBackend = false
        }
        if !isLiveBackendConnected && connectionLifecyclePhase == .connecting {
            connectionLifecyclePhase = .disconnected
        }
        if connectionStatusText.hasPrefix("Pairing") || connectionStatusText.hasPrefix("Connecting") || connectionStatusText.hasPrefix("Resolving") {
            connectionStatusText = hasPairedBackend ? "Offline · \(activeHost.hostname)" : "Not Connected"
        }
    }

    public func disconnectBackendAndClearKeychain() async {
        hostSwitchGeneration &+= 1
        hostSwitchTask?.cancel()
        hostSwitchTask = nil
        cancelAllSummaryStreams()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        stepPollingTask?.cancel()
        stepPollingTask = nil
        networkMonitor.stop()
        hasPairedBackend = false
        isLiveBackendConnected = false
        isConnectingToBackend = false
        isOptimisticInitialPairing = false
        isSwitchingHost = false
        activeRefreshCount = 0
        isRefreshingSummaries = false
        selectedHostScope = .allHosts
        if !isVerificationMode {
            preferencesStore.set(nil, forKey: Self.selectedHostScopeDefaultsKey)
            clearPairedHostLaunchHint()
        }
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
        hostCapabilitiesByKey.removeAll()
        compatibilityNoticeText = nil
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
        for task in inFlightHostRefreshTasks.values {
            task.cancel()
        }
        inFlightHostRefreshTasks.removeAll()
        refreshingHostScopeKeys.removeAll()
        isRefreshingRelayHosts = false
        if !isVerificationMode {
            hosts = []
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
        await projectionStore.clearCachedProjections()
        await secretStore.clearCredentials()
        await kmpEngine?.disconnectAndClearCredentials()
    }

    // MARK: - Foreground / Screen-Off Lifecycle & Network Path Control

    /// Immediately suspends all streams, heartbeats, backoff timers, step polling, and `NWPathMonitor`
    /// when the device locks, sleeps, or enters the background so battery & radio overhead is zero.
    public func suspendNetworkingForBackground() {
        guard !isVerificationMode else { return }
        guard !isNetworkingSuspended else { return }
        isNetworkingSuspended = true
        hostSwitchTask?.cancel()
        hostSwitchTask = nil
        for task in inFlightHostRefreshTasks.values {
            task.cancel()
        }
        inFlightHostRefreshTasks.removeAll()
        refreshingHostScopeKeys.removeAll()
        cancelAllSummaryStreams()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        stepPollingTask?.cancel()
        stepPollingTask = nil
        networkMonitor.stop()
        kmpEngine?.onBackground()
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
        await kmpEngine?.onForeground()
        if kmpEngine != nil && (hasPairedBackend || isLiveBackendConnected) {
            startKmpSummarySubscriptionIfNeeded()
        }

        guard hasPairedBackend else { return }
        guard !isConnectingToBackend else { return }

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
        isOptimisticInitialPairing = false
        isLoadingSteps = false
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

        if wasInESDDDemoState || (summaries.isEmpty && projects.isEmpty) {
            let shards = await projectionStore.loadAllHostProjections()
            let savedKnownHosts = await projectionStore.loadKnownHosts()
            for savedHost in savedKnownHosts where savedHost.instanceId != "unpaired" && !savedHost.instanceId.isEmpty {
                if !hosts.contains(where: { $0.instanceId == savedHost.instanceId }) {
                    var offlinePeer = savedHost
                    offlinePeer.isOnline = false
                    hosts.append(offlinePeer)
                }
            }
            if availableRelayInstances.isEmpty {
                let relayHosts = hosts.filter { $0.channel == .cloudRelay && $0.instanceId != "unpaired" }
                if !relayHosts.isEmpty {
                    availableRelayInstances = relayHosts.map { h in
                        RelayInstanceInfo(uuid: h.instanceId, name: h.hostname, version: h.version, status: .disconnected)
                    }
                }
            }

            var cachedProjects: [ProjectWorkspace] = []
            var cachedCloudProjects: [ProjectWorkspace] = []
            var cachedSummariesById: [String: CascadeSummary] = [:]
            for shard in shards {
                for proj in shard.projects where !Self.esddFixtureProjectIds.contains(proj.id) {
                    var copy = proj
                    if copy.runtime != .cloud && copy.originInstanceUuid == nil {
                        copy.originInstanceUuid = shard.instanceId ?? offlineHost.instanceId
                        if copy.hostName.isEmpty || copy.hostName == "MacBook Pro" {
                            copy.hostName = shard.hostname.isEmpty ? offlineHost.hostname : shard.hostname
                        }
                    }
                    cachedProjects.append(copy)
                    if copy.runtime == .cloud {
                        cachedCloudProjects.append(copy)
                    }
                }
                for s in shard.summaries where !Self.esddFixtureCascadeIds.contains(s.cascadeId) {
                    var copy = s
                    if !copy.isCloud && copy.originInstanceUuid == nil {
                        copy.originInstanceUuid = shard.instanceId ?? offlineHost.instanceId
                        copy.originHostName = copy.originHostName ?? (shard.hostname.isEmpty ? offlineHost.hostname : shard.hostname)
                    }
                    if let existing = cachedSummariesById[copy.cascadeId] {
                        if copy.updatedAt > existing.updatedAt || copy.stepCount > existing.stepCount {
                            cachedSummariesById[copy.cascadeId] = copy
                        }
                    } else {
                        cachedSummariesById[copy.cascadeId] = copy
                    }
                }
            }

            var hydratedSummaries = cachedSummariesById.values.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.cascadeId < rhs.cascadeId
            }
            if !cachedProjects.isEmpty || !hydratedSummaries.isEmpty {
                projects = Self.reconcileLiveProjects(
                    workspaces: [],
                    summaries: &hydratedSummaries,
                    existingProjects: cachedProjects,
                    hostName: offlineHost.hostname,
                    cloudProjects: cachedCloudProjects
                )
                summaries = hydratedSummaries
            } else {
                projects = []
                summaries = []
            }
            workspaces = []
            if wasInESDDDemoState {
                stepsByCascadeId = [:]
            }
            automations = (await projectionStore.loadAutomations()).filter {
                !Self.esddFixtureAutomationIds.contains($0.id)
            }
            selectedProjectId = projects.first?.id ?? ""
            selectedWorkspaceUri = projects.first?.workspaceUri ?? ""
            activeCascadeId = summaries.first?.cascadeId ?? ""
        }

        if let savedScope = loadPersistedSelectedHostScope() {
            selectedHostScope = savedScope
            reconcileSelectedHostScopeWithHosts()
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

    internal func markBackendOffline(error: Error, preservePeerOnlineStates: Bool = false) {
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
        if !preservePeerOnlineStates && (updatedHost.channel == .cloudRelay || !isDeviceNetworkReachable) {
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
            AntigravityCloudDetector.stripProjectScopePrefix(rawSlug)
        }

        func localHostKey(for s: CascadeSummary) -> String {
            if let uuid = s.originInstanceUuid, !uuid.isEmpty { return uuid }
            if let hName = s.originHostName, !hName.isEmpty { return hName }
            return ""
        }

        func partitionLocalIndicesByHost(_ indices: [Int]) -> [(hostKey: String, indices: [Int])] {
            var nonEmptyKeys = Set<String>()
            for idx in indices {
                let key = localHostKey(for: summaries[idx])
                if !key.isEmpty {
                    nonEmptyKeys.insert(key)
                }
            }
            // Keep single-host summaries unified even when mixed with legacy untagged entries
            // (`originInstanceUuid == nil`) so a single Mac never splits into two project sections.
            if nonEmptyKeys.count <= 1 {
                return [(nonEmptyKeys.first ?? "", indices)]
            }
            var order: [String] = []
            var grouped: [String: [Int]] = [:]
            for idx in indices {
                let key = localHostKey(for: summaries[idx])
                if grouped[key] == nil {
                    order.append(key)
                    grouped[key] = [idx]
                } else {
                    grouped[key]?.append(idx)
                }
            }
            return order.map { ($0, grouped[$0] ?? []) }
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

        func appendLocalHostGroups(
            canonicalName: String,
            isNoProj: Bool,
            localIndices: [Int],
            matchingWorkspaces: [WorkspaceInfo],
            cloudWs: WorkspaceInfo?,
            allowCloudOnlyFallback: Bool
        ) {
            let hostGroups = partitionLocalIndicesByHost(localIndices)
            let isMultiHostLocal = hostGroups.count > 1
            let singleLocalWs = matchingWorkspaces.first(where: { !$0.isCloud })

            for (hostKey, groupIndices) in hostGroups {
                guard let firstIdx = groupIndices.first else { continue }
                let firstLocal = summaries[firstIdx]
                let groupOriginHost = groupIndices.compactMap { summaries[$0].originHostName }.first(where: { !$0.isEmpty })
                let groupOriginUuid = groupIndices.compactMap { summaries[$0].originInstanceUuid }.first(where: { !$0.isEmpty })
                let projectId = (isMultiHostLocal && !hostKey.isEmpty)
                    ? "host:\(hostKey):\(canonicalName)"
                    : canonicalName

                for idx in groupIndices {
                    summaries[idx].projectSlug = projectId
                }

                let matchedLocalWs = matchingWorkspaces.first(where: { ws in
                    guard !ws.isCloud else { return false }
                    if let wsUuid = ws.originInstanceUuid, !wsUuid.isEmpty,
                       let sUuid = groupOriginUuid, !sUuid.isEmpty {
                        return wsUuid == sUuid
                    }
                    if let wsHost = ws.originHostName, !wsHost.isEmpty,
                       let sHost = groupOriginHost, !sHost.isEmpty {
                        return wsHost == sHost
                    }
                    return !isMultiHostLocal
                }) ?? (isMultiHostLocal ? nil : singleLocalWs)

                let isWsCloudOnly = allowCloudOnlyFallback
                    && !isMultiHostLocal
                    && !isNoProj
                    && (cloudWs != nil && matchedLocalWs == nil && AntigravityCloudDetector.isCloudWorkspaceURI(firstLocal.workspaceUri))
                let effectiveUri = isNoProj
                    ? ""
                    : ((isWsCloudOnly ? cloudWs?.workspaceUri : matchedLocalWs?.workspaceUri) ?? firstLocal.workspaceUri)
                let effectiveBranch = isNoProj ? "" : (matchedLocalWs?.activeBranch ?? firstLocal.branchName)
                let resolvedLocalHost = groupOriginHost ?? matchedLocalWs?.originHostName ?? hostName
                let resolvedOriginUuid = groupOriginUuid ?? matchedLocalWs?.originInstanceUuid
                let pathDisplay = isNoProj
                    ? "Unassigned · \(resolvedLocalHost)"
                    : effectiveUri.replacingOccurrences(of: "file://", with: "")

                if knownIds.insert(projectId).inserted {
                    reconciled.append(
                        ProjectWorkspace(
                            id: projectId,
                            name: canonicalName,
                            pathDisplay: pathDisplay,
                            workspaceUri: effectiveUri,
                            runtime: isWsCloudOnly ? .cloud : .macBookPro,
                            hostName: isWsCloudOnly ? "Cloud" : resolvedLocalHost,
                            activeBranch: effectiveBranch,
                            worktrees: isNoProj ? [] : (matchedLocalWs?.worktrees.isEmpty == false ? matchedLocalWs!.worktrees : [effectiveBranch]),
                            isExpandedInHome: expandedById[projectId] ?? expandedById[canonicalName] ?? true,
                            originInstanceUuid: resolvedOriginUuid
                        )
                    )
                }
            }
        }

        for slug in orderedBaseSlugs {
            let isNoProj = AntigravityCloudDetector.isNoProjectSlug(slug)
            let canonicalName = isNoProj ? AntigravityCloudDetector.noProjectDisplayName : slug
            let matchingIndices = summaries.indices.filter { baseSlug(for: summaries[$0].projectSlug) == slug }
            let cloudIndices = matchingIndices.filter { summaries[$0].isCloud }
            let localIndices = matchingIndices.filter { !summaries[$0].isCloud }

            let matchingWorkspaces = isNoProj ? [] : (wsByName[slug] ?? [])
            let cloudWs = matchingWorkspaces.first(where: \.isCloud)
            let matchedCloudProj = isNoProj ? nil : cloudProjByName[slug]?.first

            if !cloudIndices.isEmpty && !localIndices.isEmpty {
                // Both active local Mac chats and active Cloud chats exist for the same group (`slug` or `No Project`):
                // keep local chats under `canonicalName` (or `host:<uuid>:<canonicalName>` across multiple Macs)
                // and separate Cloud chats under `cloud:<canonicalName>`.
                appendLocalHostGroups(
                    canonicalName: canonicalName,
                    isNoProj: isNoProj,
                    localIndices: localIndices,
                    matchingWorkspaces: matchingWorkspaces,
                    cloudWs: cloudWs,
                    allowCloudOnlyFallback: false
                )

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
                appendLocalHostGroups(
                    canonicalName: canonicalName,
                    isNoProj: isNoProj,
                    localIndices: localIndices,
                    matchingWorkspaces: matchingWorkspaces,
                    cloudWs: cloudWs,
                    allowCloudOnlyFallback: true
                )
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
            if reconciled.contains(where: { existing in
                guard !existing.workspaceUri.isEmpty,
                      existing.workspaceUri.caseInsensitiveCompare(ws.workspaceUri) == .orderedSame,
                      (existing.runtime == .cloud) == isCloud else {
                    return false
                }
                if isCloud { return true }
                if let eUuid = existing.originInstanceUuid, !eUuid.isEmpty,
                   let wsUuid = ws.originInstanceUuid, !wsUuid.isEmpty {
                    return eUuid == wsUuid
                }
                return true
            }) {
                continue
            }
            let targetId: String
            if knownIds.contains(slug) {
                if isCloud,
                   let idx = reconciled.firstIndex(where: { $0.id == slug }),
                   !summaries.contains(where: { $0.projectSlug == slug && !$0.isCloud }) {
                    let mergedUri = preferredCloudUri(reconciled[idx].workspaceUri, ws.workspaceUri)
                    reconciled[idx].runtime = .cloud
                    reconciled[idx].hostName = "Cloud"
                    reconciled[idx].workspaceUri = mergedUri
                    reconciled[idx].pathDisplay = mergedUri
                    continue
                }
                if !isCloud, let wsKey = (ws.originInstanceUuid?.isEmpty == false ? ws.originInstanceUuid : ws.originHostName), !wsKey.isEmpty {
                    targetId = "host:\(wsKey):\(slug)"
                    guard !knownIds.contains(targetId) else { continue }
                } else {
                    continue
                }
            } else {
                targetId = slug
            }
            knownIds.insert(targetId)
            reconciled.append(
                ProjectWorkspace(
                    id: targetId,
                    name: slug,
                    pathDisplay: ws.workspaceUri.replacingOccurrences(of: "file://", with: ""),
                    workspaceUri: ws.workspaceUri,
                    runtime: isCloud ? .cloud : .macBookPro,
                    hostName: isCloud ? "Cloud" : (ws.originHostName ?? hostName),
                    activeBranch: ws.activeBranch,
                    worktrees: ws.worktrees.isEmpty ? [ws.activeBranch] : ws.worktrees,
                    isExpandedInHome: expandedById[targetId] ?? expandedById[slug] ?? true,
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
        let wasAlreadyPaired = hasPairedBackend
        let hostOnline = handshake.isSelectedHostOnline
        var updatedHost = host
        updatedHost.latencyMs = handshake.latencyMs
        updatedHost.isOnline = hostOnline
        if !handshake.serverVersion.isEmpty {
            updatedHost.version = handshake.serverVersion
        } else if let reported = handshake.hostCapabilities.reportedVersion, !reported.isEmpty {
            updatedHost.version = reported
        }
        activeHost = updatedHost
        if let existingIdx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
            hosts[existingIdx] = updatedHost
        } else {
            hosts.insert(updatedHost, at: 0)
        }
        rpcClient = client
        hostCapabilitiesByKey[handshake.hostCapabilities.hostKey] = handshake.hostCapabilities
        if !updatedHost.instanceId.isEmpty {
            hostCapabilitiesByKey[updatedHost.instanceId] = handshake.hostCapabilities
        }
        compatibilityNoticeText = nil
        Task { [weak self] in
            await self?.refreshHostCapabilitiesFromClient()
        }
        consecutiveSyncFailures = 0
        reconnectAttemptCount = 0
        nextReconnectAt = nil
        lastBackendActivityAt = Date()
        lastFullSyncAt = Date()
        lastStreamReopenAttemptAt = .distantPast
        isDeviceNetworkReachable = true
        isOptimisticInitialPairing = false
        hasPairedBackend = true
        isLiveBackendConnected = hostOnline
        lastPingLatencyMs = handshake.latencyMs
        connectionErrorText = nil
        if hostOnline {
            connectionStatusText = "Connected · \(updatedHost.hostname) · \(handshake.latencyMs)ms"
            connectionLifecyclePhase = .onlineIdle
        } else {
            connectionStatusText = "Offline · \(updatedHost.hostname)"
            let nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelay(
                attempt: 0,
                isLowPowerMode: isLowPowerModeEnabled
            )
            connectionLifecyclePhase = .offlineBackoff(attempt: 0, nextRetrySeconds: nextDelay)
        }

        let existingSummariesBeforeConnect = wasAlreadyPaired
            ? summaries.filter { !Self.esddFixtureCascadeIds.contains($0.cascadeId) }
            : []
        let existingProjectsBeforeConnect = wasAlreadyPaired
            ? projects.filter { !Self.esddFixtureProjectIds.contains($0.id) }
            : []
        let existingWorkspacesBeforeConnect = wasAlreadyPaired ? workspaces : []

        var refreshedHostKeys = Set<String>()
        if updatedHost.channel == .cloudRelay {
            for inst in handshake.availableRelayInstances where inst.status.isReachable {
                refreshedHostKeys.insert("host:\(inst.uuid)")
            }
            if hostOnline && !updatedHost.instanceId.isEmpty && updatedHost.instanceId != "unpaired" {
                refreshedHostKeys.insert("host:\(updatedHost.instanceId)")
            }
            if !handshake.cloudProjects.isEmpty || handshake.summaries.contains(where: \.isCloud) {
                refreshedHostKeys.insert("cloud")
            }
        } else {
            refreshedHostKeys.insert(
                Self.projectionHostKey(
                    isCloud: false,
                    instanceId: updatedHost.instanceId,
                    hostname: updatedHost.hostname,
                    fallbackHostId: updatedHost.instanceId,
                    fallbackHostName: updatedHost.hostname
                )
            )
            if !handshake.cloudProjects.isEmpty || handshake.summaries.contains(where: \.isCloud) {
                refreshedHostKeys.insert("cloud")
            }
        }

        let incomingSummaryIds = Set(handshake.summaries.map(\.cascadeId))
        let preservedOfflineSummaries = existingSummariesBeforeConnect.filter { existing in
            guard !incomingSummaryIds.contains(existing.cascadeId) else { return false }
            let key = Self.projectionHostKey(
                isCloud: existing.isCloud,
                instanceId: existing.originInstanceUuid,
                hostname: existing.originHostName,
                fallbackHostId: updatedHost.instanceId,
                fallbackHostName: updatedHost.hostname
            )
            return !refreshedHostKeys.contains(key)
        }
        let preservedOfflineProjects = existingProjectsBeforeConnect.filter { existing in
            let key = Self.projectionHostKey(
                isCloud: existing.runtime == .cloud,
                instanceId: existing.originInstanceUuid,
                hostname: existing.hostName,
                fallbackHostId: updatedHost.instanceId,
                fallbackHostName: updatedHost.hostname
            )
            return !refreshedHostKeys.contains(key)
        }
        let preservedOfflineWorkspaces = existingWorkspacesBeforeConnect.filter { existing in
            let key = Self.projectionHostKey(
                isCloud: existing.isCloud,
                instanceId: existing.originInstanceUuid,
                hostname: existing.originHostName,
                fallbackHostId: updatedHost.instanceId,
                fallbackHostName: updatedHost.hostname
            )
            return !refreshedHostKeys.contains(key)
        }

        let mergedWorkspaces = handshake.workspaces + preservedOfflineWorkspaces
        workspaces = mergedWorkspaces

        var sortedSummaries = (handshake.summaries + preservedOfflineSummaries).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.cascadeId < rhs.cascadeId
        }
        let preservedCloudProjects = preservedOfflineProjects.filter { $0.runtime == .cloud }
        let nextProjects = Self.reconcileLiveProjects(
            workspaces: mergedWorkspaces,
            summaries: &sortedSummaries,
            existingProjects: preservedOfflineProjects,
            hostName: updatedHost.hostname,
            cloudProjects: handshake.cloudProjects.isEmpty ? preservedCloudProjects : handshake.cloudProjects
        )
        summaries = sortedSummaries
        projects = nextProjects
        let defaultProject = nextProjects.first(where: { projectMatchesHostScope($0) && !$0.isNoProject })
            ?? nextProjects.first(where: { !$0.isNoProject })
            ?? nextProjects.first
        if selectedProjectId.isEmpty || !nextProjects.contains(where: { $0.id == selectedProjectId }) {
            selectedProjectId = defaultProject?.id ?? ""
            selectedWorkspaceUri = defaultProject?.workspaceUri ?? ""
        }
        let isViewingActiveChat: Bool = {
            if case .cascadeChat(let routeCid) = activeRoute, !routeCid.isEmpty, routeCid == activeCascadeId {
                return true
            }
            return false
        }()
        if activeCascadeId.isEmpty || (!isViewingActiveChat && !sortedSummaries.contains(where: { $0.cascadeId == activeCascadeId })) {
            activeCascadeId = sortedSummaries.first?.cascadeId ?? ""
        }

        // Clear offline ESDD demo state when transitioning out of demo mode, while keeping any cached steps read during cold-start
        if !wasAlreadyPaired {
            stepsByCascadeId = [:]
        } else {
            for fixtureId in Self.esddFixtureCascadeIds {
                stepsByCascadeId.removeValue(forKey: fixtureId)
            }
        }
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
        if !wasAlreadyPaired {
            automations = []
        }

        let keysToPersist = refreshedHostKeys
        let needsDeferredInitialSync = hostOnline && handshake.summaries.isEmpty && handshake.workspaces.isEmpty
        Task { [weak self] in
            if !keysToPersist.isEmpty {
                await self?.persistHostProjections(refreshedHostKeys: keysToPersist)
            }
            if needsDeferredInitialSync {
                await self?.refreshWorkspacesAndSummaries(
                    forceFullSync: true,
                    includeAutomations: false
                )
            }
            if hostOnline {
                await self?.refreshModelCatalog()
                await self?.refreshAutomations()
                await self?.replayPendingOutbox()
            }
        }

        startSummarySubscriptionStream()
        if hostOnline && !activeCascadeId.isEmpty {
            syncStepsForCascade(
                activeCascadeId,
                pollUntilIdle: activeRoute == .cascadeChat(activeCascadeId)
            )
        }
    }
}
