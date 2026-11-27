import Foundation

/// Pure Swift 6 Connect-RPC & Google Cloud Relay client for `exa.language_server_pb.LanguageServerService`.
///
/// Connects either to:
/// 1. Official Antigravity Remote Control Relay (`https://antigravity.google.com/r/<instance-id>` via `devtools_jetski_boq_api_proto.ApiService`)
/// 2. Direct LAN / Tailscale `language_server` or Mac Companion Bridge (`https://<host>:<port>`) with `x-codeium-csrf-token`
public actor AntigravityRPCClient {
    public static let servicePrefix = "/exa.language_server_pb.LanguageServerService"
    public static let clientAppVersion = "2.33.0"

    internal let channel: RemoteConnectionChannel
    internal let initialHostName: String
    internal let endpointURL: URL
    internal let relayOriginURL: URL
    internal let csrfToken: String?
    internal let sessionCookie: String?
    internal let explicitAuthUser: String?
    internal var authUser: String
    internal var targetInstanceIdentifier: String
    internal var resolvedInstanceUuid: String?
    internal var relayApiKey: String?
    internal var discoveredRelayApiKeyCandidates: [String] = []
    internal var hasAttemptedApiKeyDiscovery: Bool = false
    internal var didRunOriginApiKeyDiscovery: Bool = false
    internal var didForceRefreshInvalidApiKey: Bool = false
    internal var preferredCloudInstanceUuid: String? = nil
    internal static let endToEndFreshnessWindowSeconds: TimeInterval = 45.0
    internal var cachedRelayInstances: [RelayInstanceInfo] = []
    internal var lastEndToEndVerifiedAtByUuid: [String: Date] = [:]
    internal var cachedCloudProjectsById: [String: ProjectWorkspace] = [:]
    internal var cachedLocalProjectNameById: [String: String] = [:]
    internal var cachedLocalProjectIdByName: [String: String] = [:]
    internal var lastLocalProjectFetchAt: Date? = nil
    internal var wokenInstanceCascadeKeys: Set<String> = []
    internal var pinnedInstanceByCascadeId: [String: String] = [:]
    internal var cachedValidUpstreamModels: Set<String>?
    internal var cachedDefaultUpstreamModel: String?
    internal var capabilityProfilesByHost: [String: HostCapabilityProfile] = [:]
    internal var repairedStepCache: [String: CascadeStep] = [:]
    internal var repairedStepCacheOrder: [String] = []
    internal var attemptedRepairStepKeys: Set<String> = []
    internal var learnedWireStepTypeByHost: [String: CortexStepType] = [:]
    internal var stepOffsetIgnoredHosts: Set<String> = []

    internal enum CloudTrajectoryBackendField: String, Sendable {
        case backend = "backend"
        case backendType = "backendType"
        case none = ""

        var jsonKey: String? {
            rawValue.isEmpty ? nil : rawValue
        }
    }

    internal var preferredCloudBackendFieldByHostAndMethod: [String: CloudTrajectoryBackendField] = [:]

    internal func recordPinnedInstance(for cascadeId: String, instanceUuid: String?) {
        let cid = cascadeId.trimmingCharacters(in: .whitespacesAndNewlines)
        let uuid = instanceUuid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cid.isEmpty, !uuid.isEmpty else { return }
        pinnedInstanceByCascadeId[cid] = uuid
        if pinnedInstanceByCascadeId.count > 256, let oldestKey = pinnedInstanceByCascadeId.keys.first {
            pinnedInstanceByCascadeId.removeValue(forKey: oldestKey)
        }
    }

    internal func pinnedInstance(for cascadeId: String) -> String? {
        let cid = cascadeId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty,
              let pinned = pinnedInstanceByCascadeId[cid],
              !pinned.isEmpty else {
            return nil
        }
        if cachedRelayInstances.isEmpty || cachedRelayInstances.contains(where: { $0.uuid == pinned && $0.status.isReachable }) {
            return pinned
        }
        return nil
    }

    internal static func extractServerCascadeId(from response: [String: JSONValue]) -> String? {
        let directKeys = ["cascadeId", "conversationId", "trajectoryId"]
        for key in directKeys {
            if let val = nonEmptyString(response[key]?.stringValue) {
                return val
            }
        }
        for nestedKey in ["cascade", "conversation", "trajectory"] {
            guard let nested = response[nestedKey]?.objectValue else { continue }
            for key in directKeys {
                if let val = nonEmptyString(nested[key]?.stringValue) {
                    return val
                }
            }
        }
        return nil
    }
    internal let urlSession: URLSession
    internal let streamingURLSession: URLSession
    internal let handshakeDiagBox: HandshakeDiagnosticBox

    internal final class HandshakeDiagnosticBox: @unchecked Sendable {
        private let lock = NSLock()
        private var startTime: Date = Date()
        private var keySource: String
        private var events: [String] = []
        private let originHost: String
        private let cookieSummary: String

        init(originHost: String, cookieHeader: String, initialApiKey: String?) {
            self.originHost = originHost
            self.cookieSummary = SAPISIDHashGenerator.summarizeCookieNames(cookieHeader)
            if let key = initialApiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                self.keySource = "provided(\(key.count))"
            } else {
                self.keySource = "none"
            }
        }

        func reset() {
            lock.lock()
            startTime = Date()
            events.removeAll(keepingCapacity: true)
            lock.unlock()
        }

        func setKeySource(_ source: String) {
            lock.lock()
            keySource = source
            lock.unlock()
        }

        func record(_ event: String) {
            lock.lock()
            let elapsedMs = max(0, Int(Date().timeIntervalSince(startTime) * 1000.0))
            if events.count >= 16 {
                events.removeFirst()
            }
            events.append("\(event)@\(elapsedMs)ms")
            lock.unlock()
        }

        func snapshot() -> String {
            lock.lock()
            let trace = events.isEmpty ? "init" : events.joined(separator: "->")
            let ks = keySource
            lock.unlock()
            return "engine=Swift-URLSession origin=\(originHost) key=\(ks) ck=\(cookieSummary) trace=\(trace)"
        }
    }

    /// Zero-secret stage-by-stage handshake diagnostic breadcrumb (safe to read synchronously from any thread).
    nonisolated public func currentHandshakeDiagnostic() -> String {
        handshakeDiagBox.snapshot()
    }

    public struct LiveModelCatalogResult: Sendable, Equatable {
        public let models: [CascadeModelConfig]
        public let defaultModelId: String?
        public let agents: [String]
        public let usageQuota: ModelUsageQuota?

        public init(
            models: [CascadeModelConfig],
            defaultModelId: String? = nil,
            agents: [String] = ["Default"],
            usageQuota: ModelUsageQuota? = nil
        ) {
            self.models = models
            self.defaultModelId = defaultModelId
            self.agents = agents
            self.usageQuota = usageQuota
        }
    }

    /// Only true local-OS-only desktop commands (like revealing a local folder in macOS Finder
    /// or Companion Bridge's sandboxed `ReadArtifactFile`) are local-only; all upstream data & review RPCs forward over Cloud Relay.
    internal static let localDesktopOnlyMethods: Set<String> = [
        "OpenWorkspaceInFinder",
        "ReadArtifactFile"
    ]

    public init(
        host: RemoteHostInstance,
        csrfToken: String? = nil,
        sessionCookie: String? = nil,
        authUser: String? = nil,
        resolvedInstanceUuid: String? = nil,
        relayApiKey: String? = nil,
        pinnedFingerprintSHA256: String? = nil,
        urlSession: URLSession? = nil
    ) {
        self.channel = host.channel
        self.initialHostName = host.hostname
        self.endpointURL = host.endpointURL
        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(host.endpointURL.absoluteString)
        let originURL = URL(string: parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin)
            ?? host.endpointURL
        self.relayOriginURL = originURL
        let extractedId = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : host.instanceId
        self.targetInstanceIdentifier = extractedId
        self.resolvedInstanceUuid = resolvedInstanceUuid
        let trimmedRelayKey = relayApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInitialKey = (trimmedRelayKey?.isEmpty == false ? trimmedRelayKey : nil)
            ?? SAPISIDHashGenerator.configuredRelayWebApiKeyOverride()
        self.relayApiKey = effectiveInitialKey
        let effectiveAuthUser = authUser ?? parsedTarget?.authUser
        self.explicitAuthUser = effectiveAuthUser
        self.authUser = effectiveAuthUser ?? "0"
        self.csrfToken = csrfToken
        self.sessionCookie = sessionCookie
        self.handshakeDiagBox = HandshakeDiagnosticBox(
            originHost: originURL.host ?? originURL.absoluteString,
            cookieHeader: sessionCookie ?? "",
            initialApiKey: effectiveInitialKey
        )
        if let urlSession {
            self.urlSession = urlSession
            self.streamingURLSession = urlSession
        } else {
            self.urlSession = Self.makeDefaultURLSession(
                for: host.endpointURL,
                pinnedFingerprintSHA256: pinnedFingerprintSHA256,
                allowLocalSelfSignedTOFU: host.channel == .directHost,
                requestTimeout: 20,
                resourceTimeout: 300
            )
            self.streamingURLSession = Self.makeDefaultURLSession(
                for: host.endpointURL,
                pinnedFingerprintSHA256: pinnedFingerprintSHA256,
                allowLocalSelfSignedTOFU: host.channel == .directHost,
                requestTimeout: 300,
                resourceTimeout: 3600
            )
        }
    }

    public init(
        baseURL: URL,
        csrfToken: String? = nil,
        sessionCookie: String? = nil,
        authUser: String? = nil,
        resolvedInstanceUuid: String? = nil,
        relayApiKey: String? = nil,
        pinnedFingerprintSHA256: String? = nil,
        urlSession: URLSession? = nil
    ) {
        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(baseURL.absoluteString)
        let isRelay = parsedTarget != nil && (csrfToken == nil || csrfToken?.isEmpty == true) && (sessionCookie?.isEmpty == false)
        self.channel = isRelay ? .cloudRelay : .directHost
        self.initialHostName = parsedTarget?.instanceId ?? baseURL.host ?? ""
        self.endpointURL = baseURL
        let originURL = URL(string: parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin) ?? baseURL
        self.relayOriginURL = originURL
        self.targetInstanceIdentifier = parsedTarget?.instanceId ?? ""
        self.resolvedInstanceUuid = resolvedInstanceUuid
        let trimmedRelayKey = relayApiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveInitialKey = (trimmedRelayKey?.isEmpty == false ? trimmedRelayKey : nil)
            ?? SAPISIDHashGenerator.configuredRelayWebApiKeyOverride()
        self.relayApiKey = effectiveInitialKey
        let effectiveAuthUser = authUser ?? parsedTarget?.authUser
        self.explicitAuthUser = effectiveAuthUser
        self.authUser = effectiveAuthUser ?? "0"
        self.csrfToken = csrfToken
        self.sessionCookie = sessionCookie
        self.handshakeDiagBox = HandshakeDiagnosticBox(
            originHost: originURL.host ?? originURL.absoluteString,
            cookieHeader: sessionCookie ?? "",
            initialApiKey: effectiveInitialKey
        )
        if let urlSession {
            self.urlSession = urlSession
            self.streamingURLSession = urlSession
        } else {
            self.urlSession = Self.makeDefaultURLSession(
                for: baseURL,
                pinnedFingerprintSHA256: pinnedFingerprintSHA256,
                allowLocalSelfSignedTOFU: true,
                requestTimeout: 20,
                resourceTimeout: 300
            )
            self.streamingURLSession = Self.makeDefaultURLSession(
                for: baseURL,
                pinnedFingerprintSHA256: pinnedFingerprintSHA256,
                allowLocalSelfSignedTOFU: true,
                requestTimeout: 300,
                resourceTimeout: 3600
            )
        }
    }

    nonisolated private static func makeDefaultURLSession(
        for endpointURL: URL,
        pinnedFingerprintSHA256: String?,
        allowLocalSelfSignedTOFU: Bool,
        requestTimeout: TimeInterval = 20,
        resourceTimeout: TimeInterval = 300
    ) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        let host = (endpointURL.host ?? "").lowercased()
        let isLocalOrPrivateHost =
            host == "localhost" ||
            host == "127.0.0.1" ||
            host == "::1" ||
            host.hasSuffix(".local") ||
            host.hasSuffix(".ts.net") ||
            host.hasPrefix("192.168.") ||
            host.hasPrefix("10.") ||
            host.hasPrefix("100.") ||
            host.hasPrefix("172.")
        if isLocalOrPrivateHost {
            config.connectionProxyDictionary = [:]
        }
        let delegate = PinnedTLSURLSessionDelegate(
            pinnedFingerprintSHA256: pinnedFingerprintSHA256,
            allowLocalSelfSignedTOFU: allowLocalSelfSignedTOFU
        )
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Cloud Relay Public Web API Key Runtime Discovery

    /// Returns the currently active Cloud Relay public web API key (captured via Sign-In WebView,
    /// discovered dynamically from the relay web frontend, or supplied via environment/Info.plist).
    public func currentRelayApiKey() -> String? {
        relayApiKey
    }

    /// Seeds resolved Cloud Relay metadata (instance UUID, `X-Goog-AuthUser`, API key, and cached instance roster)
    /// obtained from the KMP engine handshake so follow-up Swift-only RPCs (`fetchModelCatalog`, `listAutomations`,
    /// artifact/diff review) reuse the warm state without re-running `ListInstances` or API key discovery.
    public func seedRelayState(
        resolvedInstanceUuid: String?,
        authUser: String?,
        relayApiKey: String?,
        relayInstances: [RelayInstanceInfo]
    ) {
        if let uuid = resolvedInstanceUuid?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uuid.isEmpty,
           !Self.isWildcardRelayIdentifier(uuid) {
            self.resolvedInstanceUuid = uuid
        }
        if let user = authUser?.trimmingCharacters(in: .whitespacesAndNewlines), !user.isEmpty {
            self.authUser = user
        }
        if let key = relayApiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            self.relayApiKey = key
        }
        if !relayInstances.isEmpty {
            self.cachedRelayInstances = relayInstances
        }
    }

    /// Resolves the public browser `X-Goog-Api-Key` required by Google Boq `ApiService`
    /// without hardcoding any API key literal in source code.
    public func resolveRelayApiKey(forceRefresh: Bool = false) async -> String? {
        let originStr = SAPISIDHashGenerator.normalizeOrigin(relayOriginURL.absoluteString)
        let isLoopback = SAPISIDHashGenerator.isLoopbackOrigin(originStr)

        if forceRefresh {
            relayApiKey = nil
            hasAttemptedApiKeyDiscovery = false
            if !isLoopback {
                await KeychainStore.shared.clearRelayWebApiKey(forOrigin: originStr)
            }
        } else if let existing = relayApiKey, !existing.isEmpty {
            return existing
        } else if !isLoopback,
                  let cached = await KeychainStore.shared.loadRelayWebApiKey(forOrigin: originStr) {
            relayApiKey = cached
            return cached
        }

        guard !hasAttemptedApiKeyDiscovery else {
            return relayApiKey
        }
        hasAttemptedApiKeyDiscovery = true

        if let discovered = await discoverRelayWebApiKeyFromOrigin(originStr: originStr) {
            relayApiKey = discovered
            if !isLoopback {
                await KeychainStore.shared.saveRelayWebApiKey(discovered, forOrigin: originStr)
            }
            return discovered
        }
        return relayApiKey
    }

    internal func makeBootstrapGetRequest(
        for url: URL,
        originStr: String,
        includeSessionCookie: Bool
    ) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 8
        #if os(iOS) || os(macOS)
        req.assumesHTTP3Capable = false
        #endif
        req.setValue("text/html,application/xhtml+xml,application/javascript,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue(SAPISIDHashGenerator.mobileRemoteUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("\(originStr)/", forHTTPHeaderField: "Referer")
        if includeSessionCookie,
           var cleanedCookie = sessionCookie?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cleanedCookie.isEmpty {
            if cleanedCookie.lowercased().hasPrefix("cookie:") {
                cleanedCookie = String(cleanedCookie.dropFirst("cookie:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !cleanedCookie.isEmpty
                && !cleanedCookie.lowercased().hasPrefix("bearer ")
                && !cleanedCookie.hasPrefix("ya29.") {
                req.setValue(cleanedCookie, forHTTPHeaderField: "Cookie")
            }
        }
        return req
    }

    internal func discoverRelayWebApiKeyFromOrigin(originStr: String) async -> String? {
        await discoverRelayWebApiKeysFromOrigin(originStr: originStr).first
    }

    internal func discoverRelayWebApiKeysFromOrigin(
        originStr: String,
        forceRefresh: Bool = false
    ) async -> [String] {
        if !forceRefresh && didRunOriginApiKeyDiscovery {
            return discoveredRelayApiKeyCandidates
        }
        let originHost = relayOriginURL.host?.lowercased()
        var candidatePages: [URL] = []
        if endpointURL.host?.lowercased() == originHost {
            candidatePages.append(endpointURL)
        }
        if let rootURL = URL(string: "\(originStr)/"),
           !candidatePages.contains(where: { $0.absoluteString == rootURL.absoluteString }) {
            candidatePages.append(rootURL)
        }

        var seenKeys = Set<String>()
        var collectedKeys: [String] = []
        var seenScripts = Set<String>()
        var scriptURLsToInspect: [URL] = []

        func appendKey(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && seenKeys.insert(trimmed).inserted {
                collectedKeys.append(trimmed)
            }
        }

        let discoveryStart = Date()
        handshakeDiagBox.record("discoverKey:start")

        for (pageIdx, pageURL) in candidatePages.enumerated() {
            if Date().timeIntervalSince(discoveryStart) >= 5.5 {
                break
            }
            if pageIdx > 0 && (!collectedKeys.isEmpty || !scriptURLsToInspect.isEmpty) {
                break
            }
            var pageReq = makeBootstrapGetRequest(
                for: pageURL,
                originStr: originStr,
                includeSessionCookie: pageURL.host?.lowercased() == originHost
            )
            pageReq.timeoutInterval = pageIdx == 0 ? 3.0 : 2.5
            guard let (data, response) = try? await urlSession.data(for: pageReq),
                  let http = response as? HTTPURLResponse,
                  (200..<400).contains(http.statusCode) else {
                continue
            }

            if let finalHost = http.url?.host?.lowercased(),
               let expectedHost = originHost,
               finalHost != expectedHost,
               !RemoteHostInstance.isAntigravityRelayHost(finalHost) {
                continue
            }

            if let headerKey = http.value(forHTTPHeaderField: "X-Goog-Api-Key") {
                appendKey(headerKey)
            }

            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            for key in SAPISIDHashGenerator.extractAllWebApiKeys(from: html) {
                appendKey(key)
            }

            let effectiveBaseURL = http.url ?? pageURL
            for scriptURL in SAPISIDHashGenerator.extractBootstrapScriptURLs(
                fromHTML: html,
                baseURL: effectiveBaseURL,
                limit: 8
            ) {
                if seenScripts.insert(scriptURL.absoluteString).inserted {
                    scriptURLsToInspect.append(scriptURL)
                }
            }
            if collectedKeys.count >= 4 {
                break
            }
        }

        if collectedKeys.count < 3 && !scriptURLsToInspect.isEmpty && Date().timeIntervalSince(discoveryStart) < 5.5 {
            let session = urlSession
            let remainingScriptTimeout = max(1.5, min(3.0, 6.0 - Date().timeIntervalSince(discoveryStart)))
            let indexedRequests: [(Int, URLRequest)] = scriptURLsToInspect.prefix(6).enumerated().map { idx, scriptURL in
                var scriptReq = makeBootstrapGetRequest(
                    for: scriptURL,
                    originStr: originStr,
                    includeSessionCookie: scriptURL.host?.lowercased() == originHost
                )
                scriptReq.timeoutInterval = remainingScriptTimeout
                return (idx, scriptReq)
            }
            var orderedResults: [(Int, [String])] = []
            await withTaskGroup(of: (Int, [String]).self) { group in
                for (idx, req) in indexedRequests {
                    group.addTask {
                        guard let (scriptData, scriptResp) = try? await session.data(for: req),
                              let scriptHTTP = scriptResp as? HTTPURLResponse,
                              (200..<300).contains(scriptHTTP.statusCode) else {
                            return (idx, [])
                        }
                        let scriptText = String(data: scriptData, encoding: .utf8)
                            ?? String(data: scriptData, encoding: .isoLatin1)
                            ?? ""
                        return (idx, SAPISIDHashGenerator.extractAllWebApiKeys(from: scriptText))
                    }
                }
                for await pair in group {
                    orderedResults.append(pair)
                }
            }
            for (_, keys) in orderedResults.sorted(by: { $0.0 < $1.0 }) {
                for key in keys {
                    appendKey(key)
                }
                if collectedKeys.count >= 6 {
                    break
                }
            }
        }

        didRunOriginApiKeyDiscovery = true
        if !collectedKeys.isEmpty {
            discoveredRelayApiKeyCandidates = collectedKeys
            if relayApiKey == nil {
                handshakeDiagBox.setKeySource("discovered(n=\(collectedKeys.count),len=\(collectedKeys[0].count))")
            }
        }
        handshakeDiagBox.record("discoverKey:n=\(collectedKeys.count)")
        return collectedKeys
    }


    // MARK: - Per-Host Capability Profile & Zero-Upstream Feature Discovery

    internal func capabilityHostKey(for instanceUuidOverride: String? = nil) -> String {
        if channel == .cloudRelay {
            let candidate = (instanceUuidOverride?.isEmpty == false)
                ? instanceUuidOverride!
                : ((resolvedInstanceUuid?.isEmpty == false) ? resolvedInstanceUuid! : targetInstanceIdentifier)
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "relay:default" : trimmed
        }
        let hostPart = endpointURL.host ?? endpointURL.absoluteString
        if let port = endpointURL.port {
            return "direct:\(hostPart):\(port)"
        }
        return "direct:\(hostPart)"
    }

    /// Returns the runtime-discovered `HostCapabilityProfile` for `key` (or the active host when `nil`).
    public func capabilityProfile(forHostKey key: String? = nil) -> HostCapabilityProfile {
        let resolvedKey = (key?.isEmpty == false) ? key! : capabilityHostKey(for: nil)
        return capabilityProfilesByHost[resolvedKey] ?? HostCapabilityProfile(hostKey: resolvedKey)
    }

    /// Returns all per-host `HostCapabilityProfile` snapshots observed during this client's lifetime.
    public func allCapabilityProfiles() -> [String: HostCapabilityProfile] {
        capabilityProfilesByHost
    }

    internal func mutateCapabilityProfile(
        for instanceUuidOverride: String? = nil,
        _ mutate: (inout HostCapabilityProfile) -> Void
    ) {
        let key = capabilityHostKey(for: instanceUuidOverride)
        var profile = capabilityProfilesByHost[key] ?? HostCapabilityProfile(hostKey: key)
        mutate(&profile)
        capabilityProfilesByHost[key] = profile
    }

    /// Returns the runtime-learned JSON step ceiling for the active or specified host (`nil` if no truncation observed).
    public func learnedJsonTrajectoryStepCeiling(forHostKey key: String? = nil) -> Int? {
        capabilityProfile(forHostKey: key).learnedJsonStepCeiling
    }

    internal func learnedJsonStepCeiling(for instanceUuidOverride: String? = nil) -> Int? {
        capabilityProfile(forHostKey: capabilityHostKey(for: instanceUuidOverride)).learnedJsonStepCeiling
    }

    internal func recordLearnedJsonStepCeiling(_ ceiling: Int, for instanceUuidOverride: String? = nil) {
        guard ceiling > 0 else { return }
        mutateCapabilityProfile(for: instanceUuidOverride) { profile in
            profile.recordJsonStepCeiling(ceiling)
        }
    }

    internal func isBinaryProtobufStepsUnsupported(for instanceUuidOverride: String? = nil) -> Bool {
        capabilityProfile(forHostKey: capabilityHostKey(for: instanceUuidOverride)).binaryProtobufStepsUnsupported
    }

    internal func recordBinaryProtobufStepsUnsupported(for instanceUuidOverride: String? = nil) {
        mutateCapabilityProfile(for: instanceUuidOverride) { profile in
            profile.recordBinaryProtobufStepsUnsupported()
        }
    }

    internal func observeResponseMetadata(
        headers: [AnyHashable: Any],
        body: [String: JSONValue]?,
        method: String,
        instanceUuidOverride: String?
    ) {
        let bridgeCaps = ProtocolCompatibilityEngine.extractBridgeCapabilities(from: headers)
        let detectedVersion = ProtocolCompatibilityEngine.extractVersionFromHeadersOrBody(
            headers: headers,
            body: body
        )
        mutateCapabilityProfile(for: instanceUuidOverride) { profile in
            profile.recordMethodSupported(method)
            if !bridgeCaps.isEmpty {
                profile.recordBridgeCapabilities(bridgeCaps)
            }
            if let detectedVersion {
                profile.updateReportedVersion(detectedVersion)
            }
        }
    }

    /// Applies one self-healing compatibility mutation (`unknown field` recursive strip or `invalid enum` downgrade)
    /// when a Desktop host returns HTTP 400 / invalid_argument, caching the rule for future requests.
    internal func attemptSelfHealingDowngrade(
        for errorMessage: String,
        method: String,
        body: inout [String: JSONValue],
        instanceUuidOverride: String?
    ) -> Bool {
        if let unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: errorMessage) {
            let (updated, removed) = ProtocolCompatibilityEngine.recursivelyRemoveField(unknownField, from: body)
            if removed {
                body = updated
                mutateCapabilityProfile(for: instanceUuidOverride) { profile in
                    profile.recordStrippedField(unknownField, forMethod: method)
                }
                return true
            }
        }
        if let invalidEnum = ProtocolCompatibilityEngine.extractInvalidEnumValue(from: errorMessage) {
            if let replacement = ProtocolCompatibilityEngine.downgradedEnumReplacement(for: invalidEnum) {
                let (updated, replaced) = ProtocolCompatibilityEngine.recursivelyReplaceEnumValue(
                    invalidEnum,
                    with: replacement,
                    in: body
                )
                if replaced {
                    body = updated
                    mutateCapabilityProfile(for: instanceUuidOverride) { profile in
                        profile.recordDowngradedEnum(from: invalidEnum, to: replacement, forMethod: method)
                    }
                    return true
                }
            }
            // Secondary fallback for unrecognized future enum values not in the explicit downgrade table:
            // strip the holding JSON key(s) so older Desktop hosts fall back to protobuf default values.
            let (strippedBody, removedKeys) = ProtocolCompatibilityEngine.recursivelyRemoveKeysWithValue(
                invalidEnum,
                from: body
            )
            if !removedKeys.isEmpty {
                body = strippedBody
                mutateCapabilityProfile(for: instanceUuidOverride) { profile in
                    for key in removedKeys {
                        profile.recordStrippedField(key, forMethod: method)
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Core Unary RPC (`Sendable` JSONValue & Binary Protobuf)

    public func callUnaryJSON(
        method: String,
        body: [String: JSONValue] = [:],
        instanceUuidOverride: String? = nil,
        allowCrossHostFailover: Bool = false,
        timeoutInterval: TimeInterval? = nil,
        respectNegativeCache: Bool = true,
        allowStripUnknownFields: Bool = true
    ) async throws -> [String: JSONValue] {
        // Inverse-allowlist negative cache: fast-fail any non-core RPC previously rejected as
        // unimplemented by this host (even future optional RPCs not yet assigned a HostCapability).
        if respectNegativeCache,
           HostCapability.shouldNegativeCacheOnUnimplemented(method) {
            let profile = capabilityProfile(forHostKey: capabilityHostKey(for: instanceUuidOverride))
            if profile.isMethodKnownUnsupported(method) {
                throw AntigravityRPCError.httpError(
                    statusCode: 501,
                    body: "unimplemented (cached): \(method)"
                )
            }
        }

        if channel == .cloudRelay {
            let relayTimeout = timeoutInterval.map { max($0, 10.0) }
            return try await callCloudRelayUnaryJSON(
                method: method,
                body: body,
                instanceUuidOverride: instanceUuidOverride,
                allowCrossHostFailover: allowCrossHostFailover,
                timeoutInterval: relayTimeout,
                allowStripUnknownFields: allowStripUnknownFields
            )
        }

        let url = endpointURL.appendingPathComponent("\(Self.servicePrefix)/\(method)")
        let profile = capabilityProfile(forHostKey: capabilityHostKey(for: instanceUuidOverride))
        var workingBody = allowStripUnknownFields
            ? ProtocolCompatibilityEngine.applyKnownDowngrades(
                to: body,
                method: method,
                profile: profile
            )
            : body

        for attempt in 1...8 {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            if let timeoutInterval {
                request.timeoutInterval = timeoutInterval
            }
            applyAuthHeaders(to: &request)
            request.httpBody = try JSONEncoder().encode(workingBody)

            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AntigravityRPCError.invalidEndpoint
            }
            // Capture Bridge version / capability headers even on non-2xx responses
            let bridgeCaps = ProtocolCompatibilityEngine.extractBridgeCapabilities(from: http.allHeaderFields)
            let headerVer = ProtocolCompatibilityEngine.extractVersionFromHeadersOrBody(headers: http.allHeaderFields)
            if !bridgeCaps.isEmpty || headerVer != nil {
                mutateCapabilityProfile(for: instanceUuidOverride) { p in
                    if !bridgeCaps.isEmpty { p.recordBridgeCapabilities(bridgeCaps) }
                    if let headerVer { p.updateReportedVersion(headerVer) }
                }
            }

            if http.statusCode == 401 || http.statusCode == 403 {
                let text = String(data: data, encoding: .utf8) ?? "Unauthorized"
                throw AntigravityRPCError.unauthorized(text)
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                if allowStripUnknownFields, http.statusCode == 400, attempt < 8,
                   attemptSelfHealingDowngrade(
                       for: text,
                       method: method,
                       body: &workingBody,
                       instanceUuidOverride: instanceUuidOverride
                   ) {
                    continue
                }
                if ProtocolCompatibilityEngine.isMethodUnimplementedResponse(statusCode: http.statusCode, body: text),
                   HostCapability.shouldNegativeCacheOnUnimplemented(method) {
                    mutateCapabilityProfile(for: instanceUuidOverride) { p in
                        p.recordMethodUnsupported(method)
                    }
                }
                throw AntigravityRPCError.httpError(statusCode: http.statusCode, body: text)
            }
            if data.isEmpty {
                observeResponseMetadata(
                    headers: http.allHeaderFields,
                    body: nil,
                    method: method,
                    instanceUuidOverride: instanceUuidOverride
                )
                return [:]
            }
            guard let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
                throw AntigravityRPCError.decodingError("Expected JSON object from \(method)")
            }
            observeResponseMetadata(
                headers: http.allHeaderFields,
                body: decoded,
                method: method,
                instanceUuidOverride: instanceUuidOverride
            )
            return decoded
        }
        return [:]
    }

    internal func callCloudRelayUnaryJSON(
        method: String,
        body: [String: JSONValue],
        instanceUuidOverride: String? = nil,
        allowCrossHostFailover: Bool = false,
        timeoutInterval: TimeInterval? = nil,
        allowStripUnknownFields: Bool = true
    ) async throws -> [String: JSONValue] {
        if Self.localDesktopOnlyMethods.contains(method) {
            mutateCapabilityProfile(for: instanceUuidOverride) { p in
                p.recordMethodUnsupported(method)
            }
            throw AntigravityRPCError.httpError(
                statusCode: 501,
                body: "\(method) is only available when connected directly to a local desktop workspace."
            )
        }

        let isCloudBackendRequest = body["backend"]?.stringValue == "BACKEND_TYPE_REMOTE_AICODE"
            || body["backendType"]?.stringValue == "BACKEND_TYPE_REMOTE_AICODE"
        let effectiveCrossHostFailover = allowCrossHostFailover || isCloudBackendRequest

        let sanitized = try await sanitizeCloudRelayPayload(method: method, body: body)
        let profile = capabilityProfile(forHostKey: capabilityHostKey(for: instanceUuidOverride))
        var workingBody = allowStripUnknownFields
            ? ProtocolCompatibilityEngine.applyKnownDowngrades(
                to: sanitized,
                method: method,
                profile: profile
            )
            : sanitized
        let requestCascadeId = body["cascadeId"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        for attempt in 1...8 {
            let encodedPayload = workingBody.isEmpty ? Data("{}".utf8) : try JSONEncoder().encode(workingBody)
            let rawRespData: Data
            let respHeaders: [String: String]
            let actualTargetUuid: String
            do {
                let res = try await callCloudRelayProxyCommandWithTarget(
                    method: method,
                    payload: encodedPayload,
                    contentType: "application/json",
                    instanceUuidOverride: instanceUuidOverride,
                    allowCrossHostFailover: effectiveCrossHostFailover,
                    timeoutInterval: timeoutInterval
                )
                rawRespData = res.payload
                respHeaders = res.headers
                actualTargetUuid = res.targetUuid
            } catch let err {
                if case let AntigravityRPCError.httpError(statusCode, errBody) = err,
                   allowStripUnknownFields, attempt < 8,
                   (statusCode == 400
                       || ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: errBody) != nil
                       || ProtocolCompatibilityEngine.extractInvalidEnumValue(from: errBody) != nil),
                   attemptSelfHealingDowngrade(
                       for: errBody,
                       method: method,
                       body: &workingBody,
                       instanceUuidOverride: instanceUuidOverride
                   ) {
                    continue
                }
                if ProtocolCompatibilityEngine.isMethodUnimplementedError(err),
                   HostCapability.shouldNegativeCacheOnUnimplemented(method) {
                    mutateCapabilityProfile(for: instanceUuidOverride) { p in
                        p.recordMethodUnsupported(method)
                    }
                }
                throw err
            }
            let respData = Self.unwrapConnectFramedPayloadIfNeeded(rawRespData)
            if respData.isEmpty {
                observeResponseMetadata(
                    headers: respHeaders,
                    body: nil,
                    method: method,
                    instanceUuidOverride: actualTargetUuid
                )
                if !requestCascadeId.isEmpty && method != "StartCascade" {
                    recordPinnedInstance(for: requestCascadeId, instanceUuid: actualTargetUuid)
                }
                return [:]
            }
            if let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: respData) {
                if let code = decoded["code"]?.stringValue,
                   let message = decoded["message"]?.stringValue,
                   decoded.count <= 3 {
                    let combinedError = "\(code): \(message)"
                    if allowStripUnknownFields, attempt < 8,
                       attemptSelfHealingDowngrade(
                           for: combinedError,
                           method: method,
                           body: &workingBody,
                           instanceUuidOverride: actualTargetUuid
                       ) {
                        continue
                    }
                    let statusCode: Int
                    if ProtocolCompatibilityEngine.isMethodUnimplementedResponse(statusCode: 400, body: combinedError) {
                        statusCode = 501
                    } else if code.caseInsensitiveCompare("not_found") == .orderedSame {
                        statusCode = 404
                    } else {
                        statusCode = 400
                    }
                    if statusCode == 501,
                       HostCapability.shouldNegativeCacheOnUnimplemented(method) {
                        mutateCapabilityProfile(for: actualTargetUuid) { p in
                            p.recordMethodUnsupported(method)
                        }
                    }
                    throw AntigravityRPCError.httpError(statusCode: statusCode, body: combinedError)
                }
                observeResponseMetadata(
                    headers: respHeaders,
                    body: decoded,
                    method: method,
                    instanceUuidOverride: actualTargetUuid
                )
                let pinCascadeId = (method == "StartCascade")
                    ? (Self.extractServerCascadeId(from: decoded) ?? "")
                    : requestCascadeId
                if !pinCascadeId.isEmpty {
                    recordPinnedInstance(for: pinCascadeId, instanceUuid: actualTargetUuid)
                }
                return decoded
            }
            let rawText = String(data: respData, encoding: .utf8) ?? ""
            if allowStripUnknownFields, attempt < 8,
               attemptSelfHealingDowngrade(
                   for: rawText,
                   method: method,
                   body: &workingBody,
                   instanceUuidOverride: actualTargetUuid
               ) {
                continue
            }
            if ProtocolCompatibilityEngine.isMethodUnimplementedResponse(statusCode: 400, body: rawText) {
                if HostCapability.shouldNegativeCacheOnUnimplemented(method) {
                    mutateCapabilityProfile(for: actualTargetUuid) { p in
                        p.recordMethodUnsupported(method)
                    }
                }
                throw AntigravityRPCError.httpError(statusCode: 501, body: rawText)
            }
            throw AntigravityRPCError.decodingError("Expected JSON object from Cloud Relay \(method)")
        }
        return [:]
    }

    internal static func unwrapConnectFramedPayloadIfNeeded(_ data: Data) -> Data {
        guard data.count >= 5 else { return data }
        let firstByte = data[data.startIndex]
        guard firstByte == 0x00 || firstByte == 0x01 else { return data }
        var parser = ConnectStreamParser()
        let frames = parser.feed(data)
        let nonTrailerFrames = frames.filter { !$0.isEndStream }
        guard !nonTrailerFrames.isEmpty else { return data }
        var out = Data()
        for frame in nonTrailerFrames {
            let decoded = frame.isCompressed
                ? CloudRelayJSPBCodec.decompressPayloadIfNeeded(frame.payload)
                : frame.payload
            out.append(decoded)
        }
        return out.isEmpty ? data : out
    }

    internal func selectReachableRelayUuid(
        preferred: String?,
        allowCrossHostFailover: Bool = false
    ) -> String? {
        let explicitOverride = (preferred?.isEmpty == false) ? preferred : nil
        let candidate = explicitOverride ?? resolvedInstanceUuid
        guard !cachedRelayInstances.isEmpty else { return candidate }
        if let candidate,
           cachedRelayInstances.contains(where: { $0.uuid == candidate && $0.status.isReachable }) {
            return candidate
        }

        // Only fail over within the SAME machine (`sameHostFamily`) for local RPCs.
        let familySeed = cachedRelayInstances.first(where: { $0.uuid == candidate })?.name
            ?? (explicitOverride == nil && !Self.isWildcardRelayIdentifier(targetInstanceIdentifier) ? targetInstanceIdentifier : "")
        if !familySeed.isEmpty,
           let familyOnline = cachedRelayInstances.first(where: {
               $0.status.isReachable && $0.sameHostFamily(as: familySeed)
           }) {
            if explicitOverride == nil {
                self.resolvedInstanceUuid = familyOnline.uuid
            }
            return familyOnline.uuid
        }

        // Cross-host failover is ONLY allowed for Cloud / host-agnostic RPCs (`allowCrossHostFailover == true`).
        if allowCrossHostFailover {
            let preferredResolved = resolvedInstanceUuid.flatMap { resUuid in
                cachedRelayInstances.contains(where: { $0.uuid == resUuid && $0.status.isReachable }) ? resUuid : nil
            }
            let anyOnline = cachedRelayInstances.first(where: \.status.isReachable)
            if let liveBest = preferredResolved ?? anyOnline?.uuid {
                return liveBest
            }
        }

        if let candidate,
           cachedRelayInstances.contains(where: { $0.uuid == candidate && !$0.status.isReachable }) {
            return nil
        }
        return candidate
    }

    internal func callCloudRelayProxyCommand(
        method: String,
        payload: Data,
        contentType: String,
        instanceUuidOverride: String? = nil,
        allowCrossHostFailover: Bool = false,
        timeoutInterval: TimeInterval? = nil,
        ignoreCachedOfflineStatus: Bool = false
    ) async throws -> (payload: Data, headers: [String: String]) {
        let res = try await callCloudRelayProxyCommandWithTarget(
            method: method,
            payload: payload,
            contentType: contentType,
            instanceUuidOverride: instanceUuidOverride,
            allowCrossHostFailover: allowCrossHostFailover,
            timeoutInterval: timeoutInterval,
            ignoreCachedOfflineStatus: ignoreCachedOfflineStatus
        )
        return (res.payload, res.headers)
    }

    internal func callCloudRelayProxyCommandWithTarget(
        method: String,
        payload: Data,
        contentType: String,
        instanceUuidOverride: String? = nil,
        allowCrossHostFailover: Bool = false,
        timeoutInterval: TimeInterval? = nil,
        ignoreCachedOfflineStatus: Bool = false
    ) async throws -> (payload: Data, headers: [String: String], targetUuid: String) {
        if !ignoreCachedOfflineStatus && instanceUuidOverride == nil && resolvedInstanceUuid == nil {
            _ = try await resolveCloudRelayInstance(
                preferredIdentifier: targetInstanceIdentifier,
                allowCrossHostFallback: allowCrossHostFailover,
                timeoutInterval: timeoutInterval
            )
        } else if !ignoreCachedOfflineStatus && cachedRelayInstances.isEmpty {
            if let refreshed = try? await listRelayInstances(timeoutInterval: min(timeoutInterval ?? 6.0, 6.0)),
               !refreshed.isEmpty {
                self.cachedRelayInstances = refreshed
            }
        }

        let resolvedTargetUuid: String? = {
            if ignoreCachedOfflineStatus, let explicit = instanceUuidOverride, !explicit.isEmpty {
                return explicit
            }
            return selectReachableRelayUuid(
                preferred: instanceUuidOverride,
                allowCrossHostFailover: allowCrossHostFailover
            )
        }()
        guard let initialTargetUuid = resolvedTargetUuid, !initialTargetUuid.isEmpty else {
            throw AntigravityRPCError.httpError(
                statusCode: 503,
                body: "Selected Antigravity Desktop host is offline"
            )
        }

        let originStr = SAPISIDHashGenerator.normalizeOrigin(relayOriginURL.absoluteString)
        guard var comps = URLComponents(string: "\(originStr)\(SAPISIDHashGenerator.apiServicePrefix)/ProxyCommand") else {
            throw AntigravityRPCError.invalidEndpoint
        }
        comps.queryItems = [URLQueryItem(name: "$unique", value: method)]
        guard let url = comps.url else {
            throw AntigravityRPCError.invalidEndpoint
        }

        let currentCookie = sessionCookie ?? ""
        let currentAuthUser = authUser
        let session = urlSession

        func sendOnce(
            to targetUuid: String,
            authUserOverride: String? = nil,
            didRetryInvalidApiKey: Bool = false
        ) async throws -> (payload: Data, headers: [String: String], targetUuid: String) {
            let activeApiKey = await resolveRelayApiKey()
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let timeoutInterval {
                request.timeoutInterval = timeoutInterval
            }
            #if os(iOS) || os(macOS)
            request.assumesHTTP3Capable = false
            #endif
            SAPISIDHashGenerator.applyApiServiceHeaders(
                to: &request,
                cookieHeader: currentCookie,
                origin: originStr,
                authUser: authUserOverride ?? currentAuthUser,
                apiKey: activeApiKey,
                isStreaming: false
            )
            request.httpBody = try CloudRelayJSPBCodec.encodeProxyCommandRequest(
                targetInstanceUuid: targetUuid,
                rpcPath: "\(Self.servicePrefix)/\(method)",
                payload: payload,
                contentType: contentType,
                isStreaming: false
            )

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AntigravityRPCError.invalidEndpoint
            }
            if !didRetryInvalidApiKey && (http.statusCode == 400 || http.statusCode == 403) {
                let text = String(data: data, encoding: .utf8) ?? ""
                if SAPISIDHashGenerator.isInvalidApiKeyError(statusCode: http.statusCode, responseBody: text),
                   let refreshedKey = await resolveRelayApiKey(forceRefresh: true),
                   refreshedKey != activeApiKey {
                    return try await sendOnce(
                        to: targetUuid,
                        authUserOverride: authUserOverride,
                        didRetryInvalidApiKey: true
                    )
                }
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                let text = String(data: data, encoding: .utf8) ?? "Unauthorized"
                throw AntigravityRPCError.unauthorized(text)
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw AntigravityRPCError.httpError(statusCode: http.statusCode, body: text)
            }
            let decoded = try CloudRelayJSPBCodec.decodeProxyCommandResponse(
                data,
                responseHeaders: http.allHeaderFields
            )
            self.lastEndToEndVerifiedAtByUuid[targetUuid] = Date()
            return (decoded.payload, decoded.headers, targetUuid)
        }

        do {
            return try await sendOnce(to: initialTargetUuid)
        } catch let AntigravityRPCError.unauthorized(msg) {
            if ignoreCachedOfflineStatus {
                throw AntigravityRPCError.unauthorized(msg)
            }
            if let resolved = try? await resolveCloudRelayInstance(
                preferredIdentifier: instanceUuidOverride ?? targetInstanceIdentifier,
                allowCrossHostFallback: allowCrossHostFailover,
                timeoutInterval: 6.0
            ), resolved.selected.status.isReachable,
               (resolved.matchedAuthUser != currentAuthUser || resolved.selected.uuid != initialTargetUuid) {
                return try await sendOnce(to: resolved.selected.uuid, authUserOverride: resolved.matchedAuthUser)
            }
            throw AntigravityRPCError.unauthorized(msg)
        } catch {
            if error is CancellationError {
                throw error
            }
            let isInstanceUnregistered = ProtocolCompatibilityEngine.isInstanceNotRegisteredError(error)
            if isInstanceUnregistered {
                self.lastEndToEndVerifiedAtByUuid.removeValue(forKey: initialTargetUuid)
                self.cachedRelayInstances = self.cachedRelayInstances.map { inst in
                    inst.uuid == initialTargetUuid ? inst.withStatus(.disconnected) : inst
                }
            } else if error is URLError {
                self.lastEndToEndVerifiedAtByUuid.removeValue(forKey: initialTargetUuid)
            } else if case let AntigravityRPCError.httpError(code, _) = error,
                      code == 502 || code == 503 || code == 504 {
                self.lastEndToEndVerifiedAtByUuid.removeValue(forKey: initialTargetUuid)
            }
            if ignoreCachedOfflineStatus {
                throw error
            }
            let isHttp404: Bool = {
                if case let AntigravityRPCError.httpError(code, _) = error {
                    return code == 404
                }
                return false
            }()
            let isTrajectoryNotFound = ProtocolCompatibilityEngine.isTrajectoryNotFoundError(error)
            let shouldFailover: Bool = {
                if isTrajectoryNotFound { return false }
                if isInstanceUnregistered { return true }
                if error is URLError { return true }
                if case let AntigravityRPCError.httpError(code, _) = error {
                    return code == 404 || code == 502 || code == 503 || code == 504
                }
                return false
            }()
            if shouldFailover {
                let prevNameForTarget = self.cachedRelayInstances.first(where: { $0.uuid == initialTargetUuid })?.name
                if let refreshedRaw = try? await listRelayInstances(timeoutInterval: min(timeoutInterval ?? 6.0, 6.0)),
                   !refreshedRaw.isEmpty {
                    let refreshed = isInstanceUnregistered
                        ? refreshedRaw.map { $0.uuid == initialTargetUuid ? $0.withStatus(.disconnected) : $0 }
                        : refreshedRaw
                    self.cachedRelayInstances = refreshed
                    // An HTTP 404 from a still-online instance means the RPC method itself is unimplemented
                    // (e.g. GetWorkspaceInfos) — NEVER fail over to another host on an application-level 404!
                    if isHttp404 && !isInstanceUnregistered && refreshed.contains(where: { $0.uuid == initialTargetUuid && $0.status.isReachable }) {
                        throw error
                    }
                    let fallbackHostSeed: String = {
                        let trimmed = initialHostName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty,
                              trimmed.caseInsensitiveCompare("Antigravity Desktop") != .orderedSame,
                              trimmed.caseInsensitiveCompare("MacBook Pro") != .orderedSame,
                              !Self.isWildcardRelayIdentifier(trimmed) else {
                            return ""
                        }
                        return trimmed
                    }()
                    let familySeed = refreshed.first(where: { $0.uuid == initialTargetUuid })?.name
                        ?? prevNameForTarget
                        ?? (instanceUuidOverride == nil && !Self.isWildcardRelayIdentifier(targetInstanceIdentifier) ? targetInstanceIdentifier : fallbackHostSeed)
                    let sameFamilyAlt: RelayInstanceInfo? = !familySeed.isEmpty
                        ? refreshed.first(where: {
                            $0.uuid != initialTargetUuid && $0.status.isReachable && $0.sameHostFamily(as: familySeed)
                        })
                        : nil
                    let crossHostAlt: RelayInstanceInfo? = allowCrossHostFailover
                        ? refreshed.first(where: { $0.uuid != initialTargetUuid && $0.status.isReachable })
                        : nil
                    if let altInst = sameFamilyAlt ?? crossHostAlt {
                        if instanceUuidOverride == nil || self.resolvedInstanceUuid == initialTargetUuid {
                            self.resolvedInstanceUuid = altInst.uuid
                        }
                        return try await sendOnce(to: altInst.uuid)
                    }
                }
            }
            throw error
        }
    }

    internal func sanitizeCloudRelayPayload(
        method: String,
        body: [String: JSONValue]
    ) async throws -> [String: JSONValue] {
        let desktopMetadata: JSONValue = .object([
            "ideName": .string("antigravity"),
            "extensionName": .string("antigravity"),
            "locale": .string("en")
        ])

        switch method {
        case "StartCascade":
            var clean: [String: JSONValue] = [
                "metadata": desktopMetadata,
                "source": .string("CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT")
            ]
            if let backend = body["backend"]?.stringValue, !backend.isEmpty {
                clean["backend"] = .string(backend)
            }
            if let backendType = body["backendType"]?.stringValue, !backendType.isEmpty {
                clean["backendType"] = .string(backendType)
            }
            if let projEnv = body["projectEnvConfig"] {
                clean["projectEnvConfig"] = projEnv
            } else if let uris = body["workspaceUris"], uris.arrayValue?.isEmpty == false {
                clean["workspaceUris"] = uris
            }
            return clean

        case "SendUserCascadeMessage":
            var cleanItems: [JSONValue] = []
            if let rawItems = body["items"]?.arrayValue {
                for entry in rawItems {
                    guard let obj = entry.objectValue else { continue }
                    if let text = obj["text"]?.stringValue {
                        cleanItems.append(.object(["text": .string(text)]))
                    } else {
                        let itemObj = obj["item"]?.objectValue ?? obj
                        if let fileObj = itemObj["file"]?.objectValue,
                           let absUri = fileObj["absoluteUri"]?.stringValue ?? fileObj["absolutePathUri"]?.stringValue,
                           !absUri.isEmpty {
                            var cleanFile: [String: JSONValue] = ["absoluteUri": .string(absUri)]
                            if let label = fileObj["label"]?.stringValue, !label.isEmpty {
                                cleanFile["label"] = .string(label)
                            }
                            cleanItems.append(.object(["item": .object(["file": .object(cleanFile)])]))
                        } else if let mediaObj = itemObj["media"]?.objectValue {
                            cleanItems.append(.object(["item": .object(["media": .object(mediaObj)])]))
                        } else if let quoteObj = itemObj["codeQuote"]?.objectValue {
                            cleanItems.append(.object(["item": .object(["codeQuote": .object(quoteObj)])]))
                        } else if let mentionObj = itemObj["mention"]?.objectValue {
                            cleanItems.append(.object(["item": .object(["mention": .object(mentionObj)])]))
                        }
                    }
                }
            }
            if cleanItems.isEmpty, let fallbackText = body["userResponse"]?.stringValue, !fallbackText.isEmpty {
                cleanItems.append(.object(["text": .string(fallbackText)]))
            }

            var clean: [String: JSONValue] = [
                "cascadeId": body["cascadeId"] ?? .string(""),
                "items": .array(cleanItems),
                "metadata": desktopMetadata
            ]
            if let backend = body["backend"]?.stringValue, !backend.isEmpty {
                clean["backend"] = .string(backend)
            }
            if let backendType = body["backendType"]?.stringValue, !backendType.isEmpty {
                clean["backendType"] = .string(backendType)
            }

            if let rawMedia = body["media"]?.arrayValue, !rawMedia.isEmpty {
                var cleanMedia: [JSONValue] = []
                for entry in rawMedia {
                    guard let m = entry.objectValue else { continue }
                    let inlineData = m["inlineData"]?.stringValue ?? m["inlineBase64Data"]?.stringValue
                    let uri = m["uri"]?.stringValue
                    if (inlineData ?? "").isEmpty && (uri ?? "").isEmpty { continue }
                    var cleanEntry: [String: JSONValue] = [
                        "mimeType": .string(m["mimeType"]?.stringValue ?? "image/jpeg")
                    ]
                    if let inlineData, !inlineData.isEmpty {
                        cleanEntry["inlineData"] = .string(inlineData)
                    }
                    if let desc = m["description"]?.stringValue, !desc.isEmpty {
                        cleanEntry["description"] = .string(desc)
                    }
                    if let uri, uri.hasPrefix("https://") || uri.hasPrefix("http://") {
                        cleanEntry["uri"] = .string(uri)
                    }
                    if let thumb = m["thumbnail"]?.stringValue, !thumb.isEmpty {
                        cleanEntry["thumbnail"] = .string(thumb)
                    }
                    if let duration = m["durationSeconds"] {
                        cleanEntry["durationSeconds"] = duration
                    }
                    cleanMedia.append(.object(cleanEntry))
                }
                if !cleanMedia.isEmpty {
                    clean["media"] = .array(cleanMedia)
                }
            }

            if var cascadeCfg = body["cascadeConfig"]?.objectValue,
               var plannerCfg = cascadeCfg["plannerConfig"]?.objectValue {
                // Ensure conversational.plannerMode is ALWAYS valid upstream enum (`CONVERSATIONAL_PLANNER_MODE_DEFAULT`)
                if var convObj = plannerCfg["conversational"]?.objectValue {
                    let rawMode = convObj["plannerMode"]?.stringValue ?? ""
                    if rawMode != "CONVERSATIONAL_PLANNER_MODE_DEFAULT" && rawMode != "CONVERSATIONAL_PLANNER_MODE_READ_ONLY" {
                        convObj["plannerMode"] = .string("CONVERSATIONAL_PLANNER_MODE_DEFAULT")
                    }
                    plannerCfg["conversational"] = .object(convObj)
                }

                // Preserve thinkingEffort, agentPersona, and permissionPreset on Cloud Relay
                if let modelCfgObj = body["modelConfig"]?.objectValue {
                    if let effort = modelCfgObj["thinkingEffort"]?.stringValue, !effort.isEmpty {
                        plannerCfg["thinkingEffort"] = .string(effort)
                    }
                    if let persona = modelCfgObj["agentPersona"]?.stringValue,
                       !persona.isEmpty, persona != "Default" {
                        plannerCfg["agentPersona"] = .string(persona)
                    }
                    if let permPreset = modelCfgObj["permissionPreset"]?.stringValue, !permPreset.isEmpty {
                        plannerCfg["permissionPreset"] = .string(permPreset)
                    }
                }

                let reqModelObj = plannerCfg["requestedModel"]?.objectValue
                let requestedModel = reqModelObj?["model"]?.stringValue ?? reqModelObj?["alias"]?.stringValue ?? ""
                let isAlias = (reqModelObj?["alias"]?.stringValue != nil)
                let (defaultModel, validModels) = await ensureUpstreamModelCatalog()

                if !validModels.isEmpty && !validModels.contains(requestedModel) {
                    if let defaultModel, !defaultModel.isEmpty {
                        plannerCfg["requestedModel"] = .object(["model": .string(defaultModel)])
                        if plannerCfg["planModel"] != nil && defaultModel.hasPrefix("MODEL_") {
                            plannerCfg["planModel"] = .string(defaultModel)
                        }
                    } else {
                        plannerCfg.removeValue(forKey: "requestedModel")
                        plannerCfg.removeValue(forKey: "planModel")
                    }
                } else if validModels.isEmpty && !isAlias && (!requestedModel.hasPrefix("MODEL_") || requestedModel.contains(" ")) {
                    if let defaultModel, !defaultModel.isEmpty {
                        plannerCfg["requestedModel"] = .object(["model": .string(defaultModel)])
                    } else {
                        plannerCfg.removeValue(forKey: "requestedModel")
                        plannerCfg.removeValue(forKey: "planModel")
                    }
                }
                cascadeCfg["plannerConfig"] = .object(plannerCfg)
                clean["cascadeConfig"] = .object(cascadeCfg)
            }
            return clean

        case "HandleCascadeUserInteraction":
            guard var interaction = body["interaction"]?.objectValue else {
                return body
            }
            if var rc = interaction["runCommand"]?.objectValue {
                if rc["confirm"]?.boolValue == true && rc["faceIdVerified"]?.boolValue == false {
                    throw AntigravityRPCError.unauthorized("Face ID verification required before approving command")
                }
                rc.removeValue(forKey: "faceIdVerified")
                interaction["runCommand"] = .object(rc)
            }
            return ["interaction": .object(interaction)]

        default:
            return body
        }
    }

    internal func ensureUpstreamModelCatalog() async -> (defaultModel: String?, validModels: Set<String>) {
        if let cachedValidUpstreamModels {
            return (cachedDefaultUpstreamModel, cachedValidUpstreamModels)
        }
        let result = await fetchModelCatalog()
        if let cachedValidUpstreamModels {
            return (cachedDefaultUpstreamModel, cachedValidUpstreamModels)
        }
        let ids = Set(result.models.map(\.modelId).filter { $0.hasPrefix("MODEL_") })
        return (result.defaultModelId, ids)
    }

    /// Queries the connected `language_server` / `agy` daemon for its live model, custom agent catalog,
    /// and dual-pool usage quota via `GetCascadeModelConfigs`, `GetCascadeModelConfigData`, `GetAvailableModels`,
    /// and `GetAllCustomAgentConfigs`.
    internal struct DecodedModelCatalogSlice: Sendable {
        let models: [CascadeModelConfig]
        let validIds: Set<String>
        let defaultModelId: String?
        let usageQuota: ModelUsageQuota?
    }

    internal static func parseExplicitSupportedEfforts(_ rawArray: [JSONValue]?) -> [ThinkingEffortLevel]? {
        guard let rawArray, !rawArray.isEmpty else { return nil }
        let mapped = Set(rawArray.compactMap { val -> ThinkingEffortLevel? in
            guard let raw = val.stringValue else { return nil }
            return CascadeModelConfig.parseEffortToken(raw)
        })
        guard !mapped.isEmpty else { return nil }
        let order: [ThinkingEffortLevel] = [.low, .medium, .high, .extra]
        return order.filter { mapped.contains($0) }
    }

    internal static func parseClientModelConfigsResponse(_ obj: [String: JSONValue]) -> DecodedModelCatalogSlice? {
        guard let configs = obj["clientModelConfigs"]?.arrayValue, !configs.isEmpty else {
            return nil
        }
        var parsedQuota: ModelUsageQuota? = nil
        if let quotaObj = obj["usageQuota"]?.objectValue ?? obj["quotaSummary"]?.objectValue {
            parsedQuota = Self.parseUsageQuota(quotaObj)
        }
        var rawEntries: [CascadeModelConfig.RawModelVariantEntry] = []
        var validIds = Set<String>()
        var defaultModelId: String? = Self.nonEmptyString(obj["defaultModel"]?.stringValue)
            .flatMap { $0 == "MODEL_UNSPECIFIED" ? nil : $0 }

        for entry in configs {
            guard let cfg = entry.objectValue else { continue }
            if cfg["disabled"]?.boolValue == true { continue }
            let label = (cfg["label"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            let moa = cfg["modelOrAlias"]?.objectValue
            let rawModel = moa?["model"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawAlias = moa?["alias"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isAlias = (rawModel == nil || rawModel == "MODEL_UNSPECIFIED" || rawModel?.isEmpty == true) && (rawAlias?.isEmpty == false)
            guard let modelId = isAlias ? rawAlias : rawModel,
                  !modelId.isEmpty,
                  modelId != "MODEL_UNSPECIFIED",
                  !validIds.contains(modelId) else {
                continue
            }
            validIds.insert(modelId)

            let lowerLabel = label.lowercased()
            let isOrchestrator = (cfg["isOrchestrator"]?.boolValue ?? false) || lowerLabel.contains("orchestrator")
            let supportsThinking = (cfg["supportsThoughtCirculation"]?.boolValue ?? false)
                || (cfg["supportsThinking"]?.boolValue ?? false)
                || lowerLabel.contains("thinking")
                || lowerLabel.contains("neon")
                || lowerLabel.contains("carbon")
                || lowerLabel.contains("argon")
                || lowerLabel.contains("hydrogen")
                || lowerLabel.contains("pro")
                || lowerLabel.contains("opus")
            let explicitEfforts = Self.parseExplicitSupportedEfforts(cfg["supportedEfforts"]?.arrayValue)
            let supportedEfforts: [ThinkingEffortLevel] = {
                if isOrchestrator { return [] }
                if let explicitEfforts, !explicitEfforts.isEmpty { return explicitEfforts }
                if lowerLabel.contains("neon") || lowerLabel.contains("hydrogen") {
                    return [.low, .medium, .high, .extra]
                }
                return [.low, .medium, .high]
            }()
            let effort: ThinkingEffortLevel = {
                if lowerLabel.contains("(xhigh)") || lowerLabel.contains("(x-high)")
                    || lowerLabel.contains("(extra") || lowerLabel.contains("(max)") {
                    return .extra
                }
                if lowerLabel.contains("(low)") || lowerLabel.contains("(minimal)") {
                    return .low
                }
                if lowerLabel.contains("(medium)") || lowerLabel.contains("(med)") || lowerLabel.contains("flash") {
                    return .medium
                }
                return .high
            }()
            let rawTag = Self.nonEmptyString(cfg["tagTitle"]?.stringValue)
                ?? Self.nonEmptyString(cfg["badge"]?.stringValue)
            let rawDesc = Self.nonEmptyString(cfg["description"]?.stringValue)
            let cleanDesc: String? = {
                guard let rawDesc, !CascadeModelConfig.isGenericBadgeLabel(rawDesc) else { return nil }
                return rawDesc
            }()
            let badgeTitle = rawTag ?? (rawDesc != nil && cleanDesc == nil ? rawDesc : nil)
            let baseSubtitle = cleanDesc ?? CascadeModelConfig.descriptiveSubtitle(forModelLabel: label)
            let quotaSuffix: String? = {
                if let rem = cfg["quotaInfo"]?.objectValue?["remainingFraction"]?.doubleValue, rem < 0.99 {
                    let pct = max(0, min(100, Int((rem * 100.0).rounded())))
                    return pct == 0 ? "Quota exhausted" : "\(pct)% quota left"
                }
                return nil
            }()
            let desc = quotaSuffix.map { "\(baseSubtitle) · \($0)" } ?? baseSubtitle
            let hasNonNewTag = badgeTitle != nil && badgeTitle?.caseInsensitiveCompare("New") != .orderedSame
            let isNew = !hasNonNewTag && ((cfg["isNew"]?.boolValue ?? false) || lowerLabel.contains("gemini 4") || isOrchestrator)
            let isRecommended = cfg["isRecommended"]?.boolValue == true
            if isRecommended && defaultModelId == nil {
                defaultModelId = modelId
            }

            let config = CascadeModelConfig(
                modelId: modelId,
                displayName: label,
                subtitle: desc,
                hasThinkingBadge: supportsThinking,
                requiresUpgradeNote: Self.nonEmptyString(cfg["upgradeNote"]?.stringValue),
                mode: .planning,
                agentPersona: "Default",
                effort: effort,
                isModelAlias: isAlias,
                badgeTitle: badgeTitle,
                isOrchestrator: isOrchestrator,
                plannerModelName: Self.nonEmptyString(cfg["plannerModelName"]?.stringValue),
                executorModelName: Self.nonEmptyString(cfg["executorModelName"]?.stringValue),
                supportedEfforts: supportedEfforts,
                isNewBadge: isNew
            )
            rawEntries.append(
                CascadeModelConfig.RawModelVariantEntry(
                    config: config,
                    explicitSupportedEfforts: explicitEfforts,
                    isRecommended: isRecommended,
                    rawDescription: cleanDesc,
                    quotaSuffix: quotaSuffix
                )
            )
        }

        let overrideMoa = obj["defaultOverrideModelConfig"]?.objectValue?["modelOrAlias"]?.objectValue
        if let defM = Self.nonEmptyString(overrideMoa?["model"]?.stringValue), defM != "MODEL_UNSPECIFIED" {
            defaultModelId = defM
        } else if let defA = Self.nonEmptyString(overrideMoa?["alias"]?.stringValue) {
            defaultModelId = defA
        }

        let groupedModels = CascadeModelConfig.groupEffortVariants(rawEntries, defaultModelId: defaultModelId)
        return DecodedModelCatalogSlice(
            models: groupedModels,
            validIds: validIds,
            defaultModelId: defaultModelId,
            usageQuota: parsedQuota
        )
    }

    internal static func parseAvailableModelsResponse(_ availWrapper: [String: JSONValue]) -> DecodedModelCatalogSlice {
        let resp = availWrapper["response"]?.objectValue ?? availWrapper
        let parsedQuota = resp["usageQuota"]?.objectValue.map { Self.parseUsageQuota($0) }
        guard let modelsMap = resp["models"]?.objectValue, !modelsMap.isEmpty else {
            return DecodedModelCatalogSlice(models: [], validIds: [], defaultModelId: nil, usageQuota: parsedQuota)
        }

        var orderedKeys: [String] = []
        let sorts = resp["agentModelSorts"]?.arrayValue ?? resp["battleModeModelSorts"]?.arrayValue ?? []
        for sort in sorts {
            for grp in sort.objectValue?["groups"]?.arrayValue ?? [] {
                for midVal in grp.objectValue?["modelIds"]?.arrayValue ?? [] {
                    if let mid = Self.nonEmptyString(midVal.stringValue), !orderedKeys.contains(mid) {
                        orderedKeys.append(mid)
                    }
                }
            }
        }
        if orderedKeys.isEmpty {
            orderedKeys = modelsMap.keys.sorted()
        }

        var rawEntries: [CascadeModelConfig.RawModelVariantEntry] = []
        var validIds = Set<String>()
        for key in orderedKeys {
            guard let details = modelsMap[key]?.objectValue else { continue }
            if details["disabled"]?.boolValue == true || details["isInternal"]?.boolValue == true {
                continue
            }
            let displayName = Self.nonEmptyString(details["displayName"]?.stringValue) ?? key
            let protoEnum = Self.nonEmptyString(details["model"]?.stringValue)
            let modelId = (protoEnum != nil && protoEnum != "MODEL_UNSPECIFIED") ? protoEnum! : key
            guard !validIds.contains(modelId) else { continue }
            validIds.insert(modelId)

            let lowerLabel = displayName.lowercased()
            let isOrchestrator = (details["isOrchestrator"]?.boolValue ?? false) || lowerLabel.contains("orchestrator")
            let supportsThinking = (details["supportsThinking"]?.boolValue ?? false)
                || lowerLabel.contains("thinking")
                || lowerLabel.contains("neon")
                || lowerLabel.contains("carbon")
                || lowerLabel.contains("argon")
                || lowerLabel.contains("hydrogen")
                || lowerLabel.contains("opus")
            let explicitEfforts = Self.parseExplicitSupportedEfforts(details["supportedEfforts"]?.arrayValue)
            let supportedEfforts: [ThinkingEffortLevel] = {
                if isOrchestrator { return [] }
                if let explicitEfforts, !explicitEfforts.isEmpty { return explicitEfforts }
                return (lowerLabel.contains("neon") || lowerLabel.contains("hydrogen"))
                    ? [.low, .medium, .high, .extra] : [.low, .medium, .high]
            }()
            let effort: ThinkingEffortLevel = {
                if lowerLabel.contains("(xhigh)") || lowerLabel.contains("(x-high)")
                    || lowerLabel.contains("(extra") || lowerLabel.contains("(max)") {
                    return .extra
                }
                if lowerLabel.contains("(low)") || lowerLabel.contains("(minimal)") {
                    return .low
                }
                if lowerLabel.contains("(medium)") || lowerLabel.contains("(med)") || lowerLabel.contains("flash") {
                    return .medium
                }
                return .high
            }()
            let rawTag = Self.nonEmptyString(details["tagTitle"]?.stringValue)
                ?? Self.nonEmptyString(details["badge"]?.stringValue)
            let rawDesc = Self.nonEmptyString(details["description"]?.stringValue)
            let cleanDesc: String? = {
                guard let rawDesc, !CascadeModelConfig.isGenericBadgeLabel(rawDesc) else { return nil }
                return rawDesc
            }()
            let badgeTitle = rawTag ?? (rawDesc != nil && cleanDesc == nil ? rawDesc : nil)
            let subtitle = cleanDesc ?? CascadeModelConfig.descriptiveSubtitle(forModelLabel: displayName)
            let hasNonNewTag = badgeTitle != nil && badgeTitle?.caseInsensitiveCompare("New") != .orderedSame
            let isNew = !hasNonNewTag && (lowerLabel.contains("gemini 4") || isOrchestrator)

            let config = CascadeModelConfig(
                modelId: modelId,
                displayName: displayName,
                subtitle: subtitle,
                hasThinkingBadge: supportsThinking,
                requiresUpgradeNote: nil,
                mode: .planning,
                agentPersona: "Default",
                effort: effort,
                isModelAlias: !modelId.hasPrefix("MODEL_"),
                badgeTitle: badgeTitle,
                isOrchestrator: isOrchestrator,
                supportedEfforts: supportedEfforts,
                isNewBadge: isNew
            )
            rawEntries.append(
                CascadeModelConfig.RawModelVariantEntry(
                    config: config,
                    explicitSupportedEfforts: explicitEfforts,
                    isRecommended: rawEntries.isEmpty,
                    rawDescription: cleanDesc
                )
            )
        }

        let groupedModels = CascadeModelConfig.groupEffortVariants(rawEntries, defaultModelId: nil)
        return DecodedModelCatalogSlice(
            models: groupedModels,
            validIds: validIds,
            defaultModelId: groupedModels.first?.modelId,
            usageQuota: parsedQuota
        )
    }

    public func fetchModelCatalog(forceRefresh: Bool = false) async -> LiveModelCatalogResult {
        if forceRefresh {
            self.cachedValidUpstreamModels = nil
            self.cachedDefaultUpstreamModel = nil
        }
        var parsedModels: [CascadeModelConfig] = []
        var validIds = Set<String>()
        var defaultModelId: String? = nil
        var parsedQuota: ModelUsageQuota? = nil

        let metaReq: [String: JSONValue] = [
            "forceRefresh": .bool(forceRefresh),
            "metadata": .object([
                "ideName": .string("antigravity"),
                "extensionName": .string("antigravity"),
                "locale": .string("en")
            ])
        ]
        for method in ["GetCascadeModelConfigs", "GetCascadeModelConfigData"] {
            if let obj = try? await callUnaryJSON(method: method, body: metaReq, timeoutInterval: 8.0),
               let slice = Self.parseClientModelConfigsResponse(obj),
               !slice.models.isEmpty {
                parsedModels = slice.models
                validIds = slice.validIds
                defaultModelId = slice.defaultModelId
                parsedQuota = slice.usageQuota
                break
            }
        }

        if parsedModels.isEmpty,
           let availWrapper = try? await callUnaryJSON(
               method: "GetAvailableModels",
               body: ["forceRefresh": .bool(forceRefresh)],
               timeoutInterval: 8.0
           ) {
            let slice = Self.parseAvailableModelsResponse(availWrapper)
            parsedModels = slice.models
            validIds = slice.validIds
            defaultModelId = slice.defaultModelId
            if parsedQuota == nil {
                parsedQuota = slice.usageQuota
            }
        }

        if !validIds.isEmpty {
            self.cachedValidUpstreamModels = validIds
            self.cachedDefaultUpstreamModel = defaultModelId ?? parsedModels.first?.modelId
        } else {
            self.cachedValidUpstreamModels = []
            self.cachedDefaultUpstreamModel = nil
        }

        var agents: [String] = ["Default"]
        if let agentResp = try? await callUnaryJSON(method: "GetAllCustomAgentConfigs", body: [:], timeoutInterval: 5.0) {
            let rawAgents = agentResp["customAgentConfigs"]?.arrayValue
                ?? agentResp["agents"]?.arrayValue
                ?? agentResp["configs"]?.arrayValue
                ?? []
            for item in rawAgents {
                if let name = Self.nonEmptyString(item.objectValue?["name"]?.stringValue)
                    ?? Self.nonEmptyString(item.objectValue?["displayName"]?.stringValue)
                    ?? Self.nonEmptyString(item.objectValue?["id"]?.stringValue),
                   !agents.contains(name) {
                    agents.append(name)
                }
            }
        }

        if !parsedModels.isEmpty {
            let hasOrchestrator = parsedModels.contains(where: \.isOrchestrator)
            let hasExtraEffort = parsedModels.contains(where: { $0.supportedEfforts.contains(.extra) })
            let hasQuota = (parsedQuota != nil)
            mutateCapabilityProfile(for: nil) { profile in
                profile.recordPassiveSignal(.orchestratorModels, state: hasOrchestrator ? .supported : .unsupported)
                profile.recordPassiveSignal(.thinkingEffortExtra, state: hasExtraEffort ? .supported : .unsupported)
                profile.recordPassiveSignal(.usageQuota, state: hasQuota ? .supported : .unsupported)
            }
        }

        let finalModels = parsedModels.isEmpty ? CascadeModelConfig.liveDefaultCatalog : parsedModels
        return LiveModelCatalogResult(
            models: finalModels,
            defaultModelId: defaultModelId ?? finalModels.first?.modelId,
            agents: agents,
            usageQuota: parsedQuota
        )
    }

    internal static func parseUsageQuota(_ obj: [String: JSONValue]) -> ModelUsageQuota {
        ModelUsageQuota(
            geminiWeeklyRemaining: obj["geminiWeeklyRemaining"]?.doubleValue ?? 0.85,
            geminiFiveHourRemaining: obj["geminiFiveHourRemaining"]?.doubleValue ?? 0.92,
            partnerWeeklyRemaining: obj["partnerWeeklyRemaining"]?.doubleValue ?? 0.70,
            partnerFiveHourRemaining: obj["partnerFiveHourRemaining"]?.doubleValue ?? 0.80,
            aiCreditOveragesEnabled: obj["aiCreditOveragesEnabled"]?.boolValue ?? obj["hasExtraCredits"]?.boolValue ?? false,
            planDisplayName: obj["planDisplayName"]?.stringValue ?? obj["planTier"]?.stringValue ?? "Google AI Ultra"
        )
    }

    internal static func defaultSubtitle(forModelLabel label: String) -> String {
        CascadeModelConfig.descriptiveSubtitle(forModelLabel: label)
    }


    // MARK: - Server-Streaming Envelope Subscription

    internal static func hasBase64TransferHeader(_ headers: [AnyHashable: Any]) -> Bool {
        headers.contains { key, val in
            let lowerKey = String(describing: key).lowercased()
            guard lowerKey == "x-goog-safety-encoding" || lowerKey == "content-transfer-encoding" else {
                return false
            }
            return String(describing: val).lowercased().contains("base64")
        }
    }

    internal static func extractConnectEndStreamError(from data: Data, decoder: JSONDecoder) -> AntigravityRPCError? {
        guard !data.isEmpty,
              let obj = try? decoder.decode([String: JSONValue].self, from: data) else {
            return nil
        }
        let errObj = obj["error"]?.objectValue
        let code = nonEmptyString(errObj?["code"]?.stringValue) ?? nonEmptyString(obj["code"]?.stringValue)
        let msg = nonEmptyString(errObj?["message"]?.stringValue) ?? nonEmptyString(obj["message"]?.stringValue)
        guard code != nil || msg != nil else { return nil }
        let combined = [code, msg].compactMap { $0 }.joined(separator: ": ")
        let lowerCode = (code ?? "").lowercased()
        if lowerCode == "unauthenticated" || lowerCode == "permission_denied" {
            return .unauthorized(combined)
        }
        if lowerCode == "unimplemented"
            || ProtocolCompatibilityEngine.isMethodUnimplementedResponse(statusCode: 400, body: combined) {
            return .httpError(statusCode: 501, body: combined)
        }
        if lowerCode == "not_found" {
            return .httpError(statusCode: 404, body: combined)
        }
        return .httpError(statusCode: 400, body: combined)
    }

    /// Subscribes to a Connect-RPC server-streaming method (`JetboxSubscribeToSummaries`, `StreamCascadeReactiveUpdates`, etc.)
    public func subscribeEnvelopeStream(
        method: String,
        requestPayload: [String: JSONValue] = [:],
        instanceUuidOverride: String? = nil,
        allowCrossHostFailover: Bool = false
    ) throws -> AsyncThrowingStream<[String: JSONValue], Error> {
        let rawJSON = requestPayload.isEmpty ? Data("{}".utf8) : try JSONEncoder().encode(requestPayload)
        let framedPayload = ConnectEnvelopeFrame(flags: [], payload: rawJSON).encode()

        if channel == .cloudRelay {
            let isCloudRequest = requestPayload["backend"]?.stringValue == "BACKEND_TYPE_REMOTE_AICODE"
                || requestPayload["backendType"]?.stringValue == "BACKEND_TYPE_REMOTE_AICODE"
            let effectiveAllowCrossHost = allowCrossHostFailover || isCloudRequest
            let initialUuid = selectReachableRelayUuid(
                preferred: instanceUuidOverride,
                allowCrossHostFailover: effectiveAllowCrossHost
            )
            let originStr = SAPISIDHashGenerator.normalizeOrigin(relayOriginURL.absoluteString)
            guard var comps = URLComponents(string: "\(originStr)\(SAPISIDHashGenerator.apiServicePrefix)/StreamProxyCommand") else {
                throw AntigravityRPCError.invalidEndpoint
            }
            comps.queryItems = [URLQueryItem(name: "$unique", value: "\(method)-\(UUID().uuidString.prefix(8))")]
            guard let relayURL = comps.url else {
                throw AntigravityRPCError.invalidEndpoint
            }
            let capturedCookie = sessionCookie ?? ""
            let capturedAuthUser = authUser
            let cachedApiKey = relayApiKey
            let session = self.streamingURLSession
            let capturedTargetIdentifier = targetInstanceIdentifier
            let rpcPath = "\(Self.servicePrefix)/\(method)"
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let targetUuid: String
                        if let initialUuid, !initialUuid.isEmpty {
                            targetUuid = initialUuid
                        } else if instanceUuidOverride == nil {
                            let resolved = try await self.resolveCloudRelayInstance(
                                preferredIdentifier: capturedTargetIdentifier,
                                allowCrossHostFallback: effectiveAllowCrossHost,
                                timeoutInterval: 6.0
                            )
                            guard !resolved.selected.uuid.isEmpty else {
                                throw AntigravityRPCError.httpError(
                                    statusCode: 503,
                                    body: "Selected Antigravity Desktop host is offline"
                                )
                            }
                            targetUuid = resolved.selected.uuid
                        } else {
                            throw AntigravityRPCError.httpError(
                                statusCode: 503,
                                body: "Selected Antigravity Desktop host is offline"
                            )
                        }

                        let encodedStreamBody = try CloudRelayJSPBCodec.encodeProxyCommandRequest(
                            targetInstanceUuid: targetUuid,
                            rpcPath: rpcPath,
                            payload: framedPayload,
                            contentType: "application/connect+json",
                            isStreaming: true
                        )

                        func makeStreamRequest(apiKey: String?) -> URLRequest {
                            var req = URLRequest(url: relayURL)
                            req.httpMethod = "POST"
                            req.timeoutInterval = 300
                            SAPISIDHashGenerator.applyApiServiceHeaders(
                                to: &req,
                                cookieHeader: capturedCookie,
                                origin: originStr,
                                authUser: capturedAuthUser,
                                apiKey: apiKey,
                                isStreaming: true
                            )
                            req.httpBody = encodedStreamBody
                            return req
                        }

                        var activeApiKey: String?
                        if let cachedApiKey, !cachedApiKey.isEmpty {
                            activeApiKey = cachedApiKey
                        } else {
                            activeApiKey = await self.resolveRelayApiKey()
                        }

                        var (bytes, response) = try await session.bytes(for: makeStreamRequest(apiKey: activeApiKey))
                        guard var http = response as? HTTPURLResponse else {
                            throw AntigravityRPCError.invalidEndpoint
                        }
                        if http.statusCode == 400 || http.statusCode == 403 {
                            var errBytes: [UInt8] = []
                            for try await byte in bytes {
                                errBytes.append(byte)
                                if errBytes.count >= 2048 { break }
                            }
                            let errText = String(decoding: errBytes, as: UTF8.self)
                            if SAPISIDHashGenerator.isInvalidApiKeyError(statusCode: http.statusCode, responseBody: errText),
                               let refreshedKey = await self.resolveRelayApiKey(forceRefresh: true),
                               refreshedKey != activeApiKey {
                                activeApiKey = refreshedKey
                                let retryResult = try await session.bytes(for: makeStreamRequest(apiKey: activeApiKey))
                                bytes = retryResult.0
                                guard let retryHTTP = retryResult.1 as? HTTPURLResponse else {
                                    throw AntigravityRPCError.invalidEndpoint
                                }
                                http = retryHTTP
                            } else if http.statusCode == 403 {
                                throw AntigravityRPCError.unauthorized(
                                    errText.isEmpty ? "StreamProxyCommand HTTP 403" : errText
                                )
                            } else {
                                throw AntigravityRPCError.httpError(
                                    statusCode: http.statusCode,
                                    body: errText.isEmpty ? "StreamProxyCommand HTTP \(http.statusCode)" : errText
                                )
                            }
                        }
                        if http.statusCode == 401 || http.statusCode == 403 {
                            throw AntigravityRPCError.unauthorized("StreamProxyCommand HTTP \(http.statusCode)")
                        }
                        guard (200..<300).contains(http.statusCode) else {
                            throw AntigravityRPCError.httpError(
                                statusCode: http.statusCode,
                                body: "StreamProxyCommand HTTP \(http.statusCode)"
                            )
                        }

                        let decoder = JSONDecoder()
                        var jspbStreamParser = CloudRelayJSPBStreamParser()
                        var connectParser = ConnectStreamParser()
                        var outerB64Decoder = StreamingBase64Decoder()
                        // 0 = auto-detect outer base64 vs raw UTF-8 JSPB, 1 = raw, 2 = base64
                        var outerMode: Int = Self.hasBase64TransferHeader(http.allHeaderFields) ? 2 : 0
                        var sniffBuffer: [UInt8] = []
                        var yieldedAny = false

                        func processStreamByte(_ decodedByte: UInt8) throws -> Bool {
                            guard let chunks = jspbStreamParser.feedByte(decodedByte) else {
                                return true
                            }
                            for rawChunk in chunks {
                                let chunkData = CloudRelayJSPBCodec.decompressPayloadIfNeeded(rawChunk)
                                if !connectParser.hasBufferedBytes,
                                   chunkData.first == UInt8(ascii: "{"),
                                   let obj = try? decoder.decode([String: JSONValue].self, from: chunkData) {
                                    yieldedAny = true
                                    continuation.yield(obj)
                                } else {
                                    for frame in connectParser.feed(chunkData) {
                                        let frameBytes = frame.isCompressed
                                            ? CloudRelayJSPBCodec.decompressPayloadIfNeeded(frame.payload)
                                            : frame.payload
                                        if frame.flags.contains(.endStream) {
                                            if let streamErr = Self.extractConnectEndStreamError(from: frameBytes, decoder: decoder) {
                                                throw streamErr
                                            }
                                            continuation.finish()
                                            return false
                                        }
                                        if let obj = try? decoder.decode([String: JSONValue].self, from: frameBytes) {
                                            yieldedAny = true
                                            continuation.yield(obj)
                                        }
                                    }
                                }
                            }
                            return true
                        }

                        for try await byte in bytes {
                            if outerMode == 1 {
                                if !(try processStreamByte(byte)) { return }
                            } else if outerMode == 2 {
                                if let decodedChunk = outerB64Decoder.feedByte(byte) {
                                    for db in decodedChunk {
                                        if !(try processStreamByte(db)) { return }
                                    }
                                }
                            } else {
                                if sniffBuffer.isEmpty,
                                   byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
                                    || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\n") {
                                    continue
                                }
                                if sniffBuffer.isEmpty,
                                   byte == UInt8(ascii: "[") || byte == UInt8(ascii: "{")
                                    || byte == UInt8(ascii: ")") || byte == UInt8(ascii: "(")
                                    || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) {
                                    outerMode = 1
                                    if !(try processStreamByte(byte)) { return }
                                } else {
                                    sniffBuffer.append(byte)
                                    if sniffBuffer.count == 4 {
                                        let candidateStr = String(decoding: sniffBuffer, as: UTF8.self)
                                        if let decodedPrefix = CloudRelayJSPBCodec.decodeBase64Flexible(candidateStr),
                                           let firstByte = decodedPrefix.first,
                                           firstByte == UInt8(ascii: ")") || firstByte == UInt8(ascii: "[")
                                            || firstByte == UInt8(ascii: "{") || firstByte == UInt8(ascii: " ")
                                            || firstByte == UInt8(ascii: "\n") {
                                            outerMode = 2
                                            for db in decodedPrefix {
                                                if !(try processStreamByte(db)) { return }
                                            }
                                        } else {
                                            outerMode = 1
                                            for rb in sniffBuffer {
                                                if !(try processStreamByte(rb)) { return }
                                            }
                                        }
                                        sniffBuffer.removeAll(keepingCapacity: false)
                                    }
                                }
                            }
                        }

                        if outerMode == 2 {
                            let trailing = outerB64Decoder.flush()
                            for db in trailing {
                                if !(try processStreamByte(db)) { return }
                            }
                        } else if !sniffBuffer.isEmpty {
                            for rb in sniffBuffer {
                                if !(try processStreamByte(rb)) { return }
                            }
                        }

                        if !yieldedAny, let boqErr = jspbStreamParser.lastErrorTrailer {
                            throw AntigravityRPCError.httpError(statusCode: 502, body: boqErr)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        let url = endpointURL.appendingPathComponent("\(Self.servicePrefix)/\(method)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/connect+json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        applyAuthHeaders(to: &request)
        request.httpBody = framedPayload

        let session = self.streamingURLSession
        let immutableRequest = request
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: immutableRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AntigravityRPCError.invalidEndpoint
                    }
                    if http.statusCode == 401 || http.statusCode == 403 {
                        throw AntigravityRPCError.unauthorized("Stream HTTP \(http.statusCode)")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errBytes: [UInt8] = []
                        for try await byte in bytes {
                            errBytes.append(byte)
                            if errBytes.count >= 2048 { break }
                        }
                        let errText = String(decoding: errBytes, as: UTF8.self)
                        throw AntigravityRPCError.httpError(
                            statusCode: http.statusCode,
                            body: errText.isEmpty ? "Stream HTTP \(http.statusCode)" : errText
                        )
                    }
                    var parser = ConnectStreamParser()
                    let decoder = JSONDecoder()
                    for try await byte in bytes {
                        if let frame = parser.feedByte(byte) {
                            let frameBytes = frame.isCompressed
                                ? CloudRelayJSPBCodec.decompressPayloadIfNeeded(frame.payload)
                                : frame.payload
                            if frame.flags.contains(.endStream) {
                                if let streamErr = Self.extractConnectEndStreamError(from: frameBytes, decoder: decoder) {
                                    throw streamErr
                                }
                                continuation.finish()
                                return
                            }
                            if let obj = try? decoder.decode([String: JSONValue].self, from: frameBytes) {
                                continuation.yield(obj)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    internal func applyAuthHeaders(to request: inout URLRequest) {
        if let csrfToken, !csrfToken.isEmpty {
            request.setValue(csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        }
        if let sessionCookie, !sessionCookie.isEmpty {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
    }

}
