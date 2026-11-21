import Foundation
#if canImport(Security)
import Security
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum AntigravityRPCError: Error, Sendable, Equatable {
    case invalidEndpoint
    case unauthorized(String)
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case interactionRejected
}

/// Handshake telemetry returned by `AntigravityRPCClient.verifyConnection()`.
public struct BackendHandshakeResult: Sendable, Equatable {
    public let latencyMs: Int
    public let workspaces: [WorkspaceInfo]
    public let summaries: [CascadeSummary]
    public let cloudProjects: [ProjectWorkspace]
    public let serverVersion: String
    public let resolvedHostname: String?
    public let resolvedInstanceUuid: String?
    public let resolvedAuthUser: String?
    public let availableRelayInstances: [RelayInstanceInfo]

    public init(
        latencyMs: Int,
        workspaces: [WorkspaceInfo],
        summaries: [CascadeSummary],
        cloudProjects: [ProjectWorkspace] = [],
        serverVersion: String = "v2.32.0",
        resolvedHostname: String? = nil,
        resolvedInstanceUuid: String? = nil,
        resolvedAuthUser: String? = nil,
        availableRelayInstances: [RelayInstanceInfo] = []
    ) {
        self.latencyMs = latencyMs
        self.workspaces = workspaces
        self.summaries = summaries
        self.cloudProjects = cloudProjects
        self.serverVersion = serverVersion
        self.resolvedHostname = resolvedHostname
        self.resolvedInstanceUuid = resolvedInstanceUuid
        self.resolvedAuthUser = resolvedAuthUser
        self.availableRelayInstances = availableRelayInstances
    }
}

/// Lightweight heartbeat / reachability result returned by `AntigravityRPCClient.probeHostReachability()`.
public struct HostReachabilityProbeResult: Sendable, Equatable {
    public let latencyMs: Int
    public let availableRelayInstances: [RelayInstanceInfo]
    public let activeRelayInstance: RelayInstanceInfo?
    public let relayTopologyChanged: Bool
    public let relayMetadataChanged: Bool

    public init(
        latencyMs: Int,
        availableRelayInstances: [RelayInstanceInfo] = [],
        activeRelayInstance: RelayInstanceInfo? = nil,
        relayTopologyChanged: Bool = false,
        relayMetadataChanged: Bool = false
    ) {
        self.latencyMs = latencyMs
        self.availableRelayInstances = availableRelayInstances
        self.activeRelayInstance = activeRelayInstance
        self.relayTopologyChanged = relayTopologyChanged
        self.relayMetadataChanged = relayMetadataChanged
    }
}

/// Scoped workspace & summary synchronization outcome returned by `fetchScopedWorkspacesAndSummaries(target:)`.
/// Tracks exactly which local hosts and/or Cloud scope actually succeeded so callers can refresh targeted devices
/// without discarding cached conversations for offline or unqueried hosts.
public struct ScopedWorkspaceSyncResult: Sendable {
    public var workspaces: [WorkspaceInfo]
    public var summaries: [CascadeSummary]
    public var cloudProjects: [ProjectWorkspace]
    public var cloudWarmingUp: Bool
    public var relayInstances: [RelayInstanceInfo]
    public var refreshedLocalHostUuids: Set<String>
    public var refreshedLocalHostNames: Set<String>
    public var refreshedCloud: Bool
    public var targetReachable: Bool
    public var latencyMs: Int?

    public init(
        workspaces: [WorkspaceInfo] = [],
        summaries: [CascadeSummary] = [],
        cloudProjects: [ProjectWorkspace] = [],
        cloudWarmingUp: Bool = false,
        relayInstances: [RelayInstanceInfo] = [],
        refreshedLocalHostUuids: Set<String> = [],
        refreshedLocalHostNames: Set<String> = [],
        refreshedCloud: Bool = false,
        targetReachable: Bool = true,
        latencyMs: Int? = nil
    ) {
        self.workspaces = workspaces
        self.summaries = summaries
        self.cloudProjects = cloudProjects
        self.cloudWarmingUp = cloudWarmingUp
        self.relayInstances = relayInstances
        self.refreshedLocalHostUuids = refreshedLocalHostUuids
        self.refreshedLocalHostNames = refreshedLocalHostNames
        self.refreshedCloud = refreshedCloud
        self.targetReachable = targetReachable
        self.latencyMs = latencyMs
    }
}

/// URLSession TLS delegate supporting SHA-256 certificate pinning and local LAN / Tailscale TOFU
/// for Antigravity Desktop's dynamically generated self-signed `language_server` HTTPS certificate.
public final class PinnedTLSURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let pinnedFingerprintHex: String?
    private let allowLocalSelfSignedTOFU: Bool

    public init(pinnedFingerprintSHA256: String? = nil, allowLocalSelfSignedTOFU: Bool = true) {
        self.pinnedFingerprintHex = pinnedFingerprintSHA256?
            .replacingOccurrences(of: "SHA256:", with: "")
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.allowLocalSelfSignedTOFU = allowLocalSelfSignedTOFU
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        #if canImport(Security)
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host.lowercased()
        if let expectedHex = pinnedFingerprintHex, !expectedHex.isEmpty {
            if let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
               let leaf = certChain.first {
                let derData = SecCertificateCopyData(leaf) as Data
                #if canImport(CryptoKit)
                let digest = SHA256.hash(data: derData)
                let actualHex = digest.map { String(format: "%02x", $0) }.joined()
                if actualHex.hasPrefix(expectedHex) || expectedHex.hasPrefix(actualHex) {
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
                #endif
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let isPrivateOrTailscaleHost =
            host == "localhost" ||
            host == "127.0.0.1" ||
            host.hasSuffix(".local") ||
            host.hasSuffix(".ts.net") ||
            host.hasPrefix("192.168.") ||
            host.hasPrefix("10.") ||
            host.hasPrefix("100.") ||
            host.hasPrefix("172.")

        if allowLocalSelfSignedTOFU && isPrivateOrTailscaleHost {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }
        #endif
        completionHandler(.performDefaultHandling, nil)
    }
}

/// Pure Swift 6 Connect-RPC & Google Cloud Relay client for `exa.language_server_pb.LanguageServerService`.
///
/// Connects either to:
/// 1. Official Antigravity Remote Control Relay (`https://antigravity.google.com/r/<instance-id>` via `devtools_jetski_boq_api_proto.ApiService`)
/// 2. Direct LAN / Tailscale `language_server` or Mac Companion Bridge (`https://<host>:<port>`) with `x-codeium-csrf-token`
public actor AntigravityRPCClient {
    public static let servicePrefix = "/exa.language_server_pb.LanguageServerService"
    public static let protobufStepThreshold = 600

    private let channel: RemoteConnectionChannel
    private let endpointURL: URL
    private let relayOriginURL: URL
    private let csrfToken: String?
    private let sessionCookie: String?
    private let explicitAuthUser: String?
    private var authUser: String
    private var targetInstanceIdentifier: String
    private var resolvedInstanceUuid: String?
    private var preferredCloudInstanceUuid: String? = nil
    private var cachedRelayInstances: [RelayInstanceInfo] = []
    private var cachedCloudProjectsById: [String: ProjectWorkspace] = [:]
    private var cachedLocalProjectNameById: [String: String] = [:]
    private var cachedLocalProjectIdByName: [String: String] = [:]
    private var lastLocalProjectFetchAt: Date? = nil
    private var wokenInstanceCascadeKeys: Set<String> = []
    private var cachedValidUpstreamModels: Set<String>?
    private var cachedDefaultUpstreamModel: String?
    private let urlSession: URLSession
    private let streamingURLSession: URLSession

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
    private static let localDesktopOnlyMethods: Set<String> = [
        "OpenWorkspaceInFinder",
        "ReadArtifactFile"
    ]

    public init(
        host: RemoteHostInstance,
        csrfToken: String? = nil,
        sessionCookie: String? = nil,
        authUser: String? = nil,
        resolvedInstanceUuid: String? = nil,
        pinnedFingerprintSHA256: String? = nil,
        urlSession: URLSession? = nil
    ) {
        self.channel = host.channel
        self.endpointURL = host.endpointURL
        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(host.endpointURL.absoluteString)
        self.relayOriginURL = URL(string: parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin)
            ?? host.endpointURL
        let extractedId = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : host.instanceId
        self.targetInstanceIdentifier = extractedId
        self.resolvedInstanceUuid = resolvedInstanceUuid
        let effectiveAuthUser = authUser ?? parsedTarget?.authUser
        self.explicitAuthUser = effectiveAuthUser
        self.authUser = effectiveAuthUser ?? "0"
        self.csrfToken = csrfToken
        self.sessionCookie = sessionCookie
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
        pinnedFingerprintSHA256: String? = nil,
        urlSession: URLSession? = nil
    ) {
        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(baseURL.absoluteString)
        let isRelay = parsedTarget != nil && (csrfToken == nil || csrfToken?.isEmpty == true) && (sessionCookie?.isEmpty == false)
        self.channel = isRelay ? .cloudRelay : .directHost
        self.endpointURL = baseURL
        self.relayOriginURL = URL(string: parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin) ?? baseURL
        self.targetInstanceIdentifier = parsedTarget?.instanceId ?? ""
        self.resolvedInstanceUuid = resolvedInstanceUuid
        let effectiveAuthUser = authUser ?? parsedTarget?.authUser
        self.explicitAuthUser = effectiveAuthUser
        self.authUser = effectiveAuthUser ?? "0"
        self.csrfToken = csrfToken
        self.sessionCookie = sessionCookie
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

    // MARK: - Cloud Relay `ApiService/ListInstances` & Instance Resolution

    /// Queries `POST /$rpc/devtools_jetski_boq_api_proto.ApiService/ListInstances` for a given `X-Goog-AuthUser`.
    public func listRelayInstances(
        authUserOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> [RelayInstanceInfo] {
        let activeAuthUser = authUserOverride ?? authUser
        let urlString = "\(SAPISIDHashGenerator.normalizeOrigin(relayOriginURL.absoluteString))\(SAPISIDHashGenerator.apiServicePrefix)/ListInstances"
        guard let url = URL(string: urlString) else {
            throw AntigravityRPCError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        SAPISIDHashGenerator.applyApiServiceHeaders(
            to: &request,
            cookieHeader: sessionCookie ?? "",
            origin: relayOriginURL.absoluteString,
            authUser: activeAuthUser
        )
        request.httpBody = CloudRelayJSPBCodec.encodeListInstancesRequest()

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AntigravityRPCError.invalidEndpoint
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            let text = String(data: data, encoding: .utf8) ?? "Google session expired or unauthorized"
            throw AntigravityRPCError.unauthorized(text)
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AntigravityRPCError.httpError(statusCode: http.statusCode, body: text)
        }
        return try CloudRelayJSPBCodec.decodeListInstancesResponse(
            data,
            responseHeaders: http.allHeaderFields
        )
    }

    /// Returns the currently active reachable Cloud Relay instance, if resolved.
    public func currentActiveRelayInstance() -> RelayInstanceInfo? {
        if let resUuid = resolvedInstanceUuid,
           let matched = cachedRelayInstances.first(where: { $0.uuid == resUuid && $0.status.isReachable }) {
            return matched
        }
        return cachedRelayInstances.first(where: \.status.isReachable)
    }

    /// Returns the latest known Cloud Relay instance list (including end-to-end reachability status updates).
    public func cachedInstancesSnapshot() -> [RelayInstanceInfo] {
        cachedRelayInstances
    }

    /// Returns the latest Cloud Relay instance list observed from `ApiService/ListInstances`.
    public func currentCachedRelayInstances() -> [RelayInstanceInfo] {
        cachedRelayInstances
    }

    /// Updates the preferred active Cloud Relay target UUID/name when the user selects a specific online host.
    public func setPreferredRelayInstance(uuid: String, name: String) {
        let trimmedUuid = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUuid.isEmpty {
            self.resolvedInstanceUuid = trimmedUuid
        }
        if !trimmedName.isEmpty {
            self.targetInstanceIdentifier = trimmedName
        } else if !trimmedUuid.isEmpty {
            self.targetInstanceIdentifier = trimmedUuid
        }
    }

    /// Returns the latest cached `ListInstances` snapshot together with the active reachable instance.
    public func currentRelayInstancesSnapshot() -> (instances: [RelayInstanceInfo], active: RelayInstanceInfo?) {
        (cachedRelayInstances, currentActiveRelayInstance())
    }
    /// Resolves a scanned Remote Control device slug (`lt74xt6l0m-golden-star`) or UUID (`0f5819ac-...-v2`)
    /// to an online `RelayInstanceInfo`, automatically failing over across open windows on the same Mac/account
    /// and probing `X-Goog-AuthUser` `0..4` for multi-account sessions.
    public func resolveCloudRelayInstance(
        preferredIdentifier: String? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> (selected: RelayInstanceInfo, allInstances: [RelayInstanceInfo], matchedAuthUser: String) {
        let rawTarget = (preferredIdentifier ?? targetInstanceIdentifier).trimmingCharacters(in: .whitespacesAndNewlines)
        let isWildcardTarget = rawTarget.isEmpty
            || rawTarget == "r"
            || rawTarget == "auto"
            || rawTarget == "macbook-pro-local"

        var candidateAuthUsers: [String] = []
        if let explicitAuthUser, !explicitAuthUser.isEmpty {
            candidateAuthUsers.append(explicitAuthUser)
        }
        for fallbackIdx in ["0", "1", "2", "3", "4"] where !candidateAuthUsers.contains(fallbackIdx) {
            candidateAuthUsers.append(fallbackIdx)
        }

        var firstNonEmptyResult: (instances: [RelayInstanceInfo], authUser: String)? = nil
        var bestReachableFallback: (selected: RelayInstanceInfo, instances: [RelayInstanceInfo], authUser: String)? = nil
        var bestOfflineMatch: (selected: RelayInstanceInfo, instances: [RelayInstanceInfo], authUser: String)? = nil
        var lastError: Error? = nil

        for (userIdx, candidateUser) in candidateAuthUsers.enumerated() {
            do {
                let perUserTimeout = userIdx == 0 ? timeoutInterval : min(timeoutInterval ?? 6.0, 5.0)
                let instances = try await listRelayInstances(
                    authUserOverride: candidateUser,
                    timeoutInterval: perUserTimeout
                )
                if instances.isEmpty {
                    continue
                }
                if firstNonEmptyResult == nil {
                    firstNonEmptyResult = (instances, candidateUser)
                }

                if !isWildcardTarget {
                    // 1. Exact UUID or window slug match that is currently ONLINE (`isReachable`)
                    if let exactOnline = instances.first(where: { $0.matches(identifier: rawTarget) && $0.status.isReachable }) {
                        self.authUser = candidateUser
                        self.resolvedInstanceUuid = exactOnline.uuid
                        self.cachedRelayInstances = instances
                        return (exactOnline, instances, candidateUser)
                    }
                    // 2. Peer window on the SAME Mac (`huangjiafandemac-mini-local-...`) that is currently ONLINE
                    if let familyOnline = instances.first(where: { $0.sameHostFamily(as: rawTarget) && $0.status.isReachable }) {
                        self.authUser = candidateUser
                        self.resolvedInstanceUuid = familyOnline.uuid
                        self.cachedRelayInstances = instances
                        return (familyOnline, instances, candidateUser)
                    }
                    // 3. Record any online instance on this account before considering disconnected windows
                    if bestReachableFallback == nil,
                       let anyOnline = instances.first(where: \.status.isReachable) {
                        bestReachableFallback = (anyOnline, instances, candidateUser)
                    }
                    if bestOfflineMatch == nil,
                       let exactOffline = instances.first(where: { $0.matches(identifier: rawTarget) })
                           ?? instances.first(where: { $0.sameHostFamily(as: rawTarget) }) {
                        bestOfflineMatch = (exactOffline, instances, candidateUser)
                    }
                } else if let online = instances.first(where: \.status.isReachable) {
                    self.authUser = candidateUser
                    self.resolvedInstanceUuid = online.uuid
                    self.cachedRelayInstances = instances
                    return (online, instances, candidateUser)
                }
            } catch {
                lastError = error
                if explicitAuthUser != nil && candidateUser == explicitAuthUser {
                    continue
                }
            }
        }

        if let reachable = bestReachableFallback {
            self.authUser = reachable.authUser
            self.resolvedInstanceUuid = reachable.selected.uuid
            self.cachedRelayInstances = reachable.instances
            return (reachable.selected, reachable.instances, reachable.authUser)
        }

        if let offline = bestOfflineMatch {
            self.authUser = offline.authUser
            self.resolvedInstanceUuid = offline.selected.uuid
            self.cachedRelayInstances = offline.instances
            return (offline.selected, offline.instances, offline.authUser)
        }

        if let fallback = firstNonEmptyResult,
           let chosen = fallback.instances.first(where: \.status.isReachable) ?? fallback.instances.first {
            self.authUser = fallback.authUser
            self.resolvedInstanceUuid = chosen.uuid
            self.cachedRelayInstances = fallback.instances
            return (chosen, fallback.instances, fallback.authUser)
        }

        if firstNonEmptyResult == nil && !isWildcardTarget && (rawTarget.hasSuffix("-v2") || rawTarget.count >= 32) {
            let directInfo = RelayInstanceInfo(
                uuid: rawTarget,
                name: rawTarget,
                status: .connected
            )
            self.resolvedInstanceUuid = rawTarget
            self.cachedRelayInstances = [directInfo]
            return (directInfo, [directInfo], authUser)
        }

        if let lastError {
            throw lastError
        }
        throw AntigravityRPCError.unauthorized(
            "No online Antigravity Desktop instances found for this Google account. Ensure Remote Control is enabled on your Mac/PC."
        )
    }

    // MARK: - Handshake & Login Verification

    /// Verifies authentication (`SAPISIDHASH` + `ApiService/ListInstances` + `ProxyCommand`, or `x-codeium-csrf-token`)
    /// and hydrates initial local + Antigravity Cloud workspaces & trajectories across all reachable instances.
    public func verifyConnection(
        timeoutInterval: TimeInterval = 4.0,
        strictTargetSelection: Bool = false
    ) async throws -> BackendHandshakeResult {
        let start = Date()
        let effectiveTimeout = (channel == .cloudRelay) ? max(timeoutInterval, 15.0) : timeoutInterval
        var resolvedName: String? = nil
        var serverVersion = "v2.32.0"
        var allRelayInstances: [RelayInstanceInfo] = []
        var initialSelectedUuid: String? = nil

        if channel == .cloudRelay {
            let preferred = (resolvedInstanceUuid?.isEmpty == false) ? resolvedInstanceUuid : targetInstanceIdentifier
            let resolution = try await resolveCloudRelayInstance(
                preferredIdentifier: preferred,
                timeoutInterval: effectiveTimeout
            )
            resolvedName = resolution.selected.name
            serverVersion = resolution.selected.version
            allRelayInstances = resolution.allInstances
            initialSelectedUuid = resolution.selected.uuid

            if strictTargetSelection {
                let targetTrimmed = targetInstanceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchedTarget = targetTrimmed.isEmpty || resolution.selected.matches(identifier: targetTrimmed)
                if !matchedTarget || !resolution.selected.status.isReachable {
                    let targetLabel = targetTrimmed.isEmpty ? resolution.selected.name : targetTrimmed
                    throw AntigravityRPCError.httpError(
                        statusCode: 503,
                        body: "\(targetLabel) is currently offline or unreachable"
                    )
                }
            }
        }

        let federated = try await fetchFederatedWorkspacesAndSummaries(
            timeoutInterval: effectiveTimeout,
            skipRelayListRefresh: channel == .cloudRelay && !allRelayInstances.isEmpty
        )
        let reconciledInstances = federated.relayInstances.isEmpty ? allRelayInstances : federated.relayInstances

        if channel == .cloudRelay && !reconciledInstances.isEmpty {
            let selectedUuid = initialSelectedUuid ?? resolvedInstanceUuid
            if let selectedUuid,
               let verifiedSelected = reconciledInstances.first(where: { $0.uuid == selectedUuid }) {
                if !verifiedSelected.status.isReachable {
                    if strictTargetSelection {
                        throw AntigravityRPCError.httpError(
                            statusCode: 503,
                            body: "\(verifiedSelected.name) is currently offline or not responding"
                        )
                    }
                    if let liveFallback = reconciledInstances.first(where: {
                        $0.status.isReachable && $0.sameHostFamily(as: verifiedSelected.name)
                    }) ?? reconciledInstances.first(where: \.status.isReachable) {
                        self.resolvedInstanceUuid = liveFallback.uuid
                        resolvedName = liveFallback.name
                        serverVersion = liveFallback.version
                    }
                } else {
                    self.resolvedInstanceUuid = verifiedSelected.uuid
                    resolvedName = verifiedSelected.name
                    serverVersion = verifiedSelected.version
                }
            }
        }

        let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
        return BackendHandshakeResult(
            latencyMs: elapsedMs,
            workspaces: federated.workspaces,
            summaries: federated.summaries,
            cloudProjects: federated.cloudProjects,
            serverVersion: serverVersion,
            resolvedHostname: resolvedName,
            resolvedInstanceUuid: resolvedInstanceUuid,
            resolvedAuthUser: channel == .cloudRelay ? authUser : nil,
            availableRelayInstances: reconciledInstances
        )
    }

    /// Lightweight reachability probe used by foreground idle heartbeats and offline recovery.
    /// - Cloud Relay (`verifyEndToEnd == false`): sends only `ApiService/ListInstances` (zero `ProxyCommand` fan-out).
    /// - Cloud Relay (`verifyEndToEnd == true`, e.g. Settings refresh): verifies each reachable Relay instance end-to-end
    ///   with a short-timeout `GetWorkspaceInfos` `ProxyCommand` (`allowCrossInstanceFailover: false`) so stale/zombie
    ///   Relay entries are truthfully downgraded to `.disconnected`.
    /// - Direct LAN: sends a single short-timeout `GetWorkspaceInfos` probe (HTTP 404 still proves server + auth liveness).
    public func probeHostReachability(
        timeoutInterval: TimeInterval? = nil,
        verifyEndToEnd: Bool = false
    ) async throws -> HostReachabilityProbeResult {
        let start = Date()
        if channel == .cloudRelay {
            let effectiveTimeout = timeoutInterval ?? 8.0
            let prevReachableIds = Set(cachedRelayInstances.filter(\.status.isReachable).map(\.uuid))
            let prevNamesByUuid = Dictionary(
                cachedRelayInstances.map { ($0.uuid, $0.name) },
                uniquingKeysWith: { _, latest in latest }
            )
            let prevActiveUuid = resolvedInstanceUuid

            var instances = try await listRelayInstances(timeoutInterval: effectiveTimeout)
            if verifyEndToEnd && !instances.isEmpty {
                let candidateReachable = instances.filter(\.status.isReachable)
                if !candidateReachable.isEmpty {
                    let perHostTimeout = min(effectiveTimeout, 4.5)
                    var failedUuids = Set<String>()
                    await withTaskGroup(of: (String, Bool).self) { group in
                        for inst in candidateReachable {
                            group.addTask {
                                do {
                                    _ = try await self.getWorkspaceInfos(
                                        instanceUuidOverride: inst.uuid,
                                        originHostName: inst.name,
                                        timeoutInterval: perHostTimeout,
                                        allowCrossInstanceFailover: false
                                    )
                                    return (inst.uuid, true)
                                } catch let AntigravityRPCError.httpError(code, _) where code == 404 {
                                    return (inst.uuid, true)
                                } catch {
                                    return (inst.uuid, false)
                                }
                            }
                        }
                        for await (uuid, ok) in group where !ok {
                            failedUuids.insert(uuid)
                        }
                    }
                    if !failedUuids.isEmpty {
                        instances = instances.map { inst in
                            failedUuids.contains(inst.uuid) ? inst.withStatus(.disconnected) : inst
                        }
                    }
                }
            }

            if !instances.isEmpty {
                self.cachedRelayInstances = instances
            }

            let reachable = instances.filter(\.status.isReachable)
            if reachable.isEmpty {
                if instances.isEmpty, let directUuid = resolvedInstanceUuid, !directUuid.isEmpty {
                    do {
                        _ = try await getWorkspaceInfos(
                            instanceUuidOverride: directUuid,
                            timeoutInterval: effectiveTimeout,
                            allowCrossInstanceFailover: false
                        )
                    } catch let AntigravityRPCError.httpError(statusCode, _) where statusCode == 404 {
                        // HTTP 404 on optional endpoint still proves the remote language_server is alive.
                    }
                    let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
                    return HostReachabilityProbeResult(
                        latencyMs: elapsedMs,
                        availableRelayInstances: cachedRelayInstances,
                        activeRelayInstance: currentActiveRelayInstance(),
                        relayTopologyChanged: false,
                        relayMetadataChanged: false
                    )
                }
                throw AntigravityRPCError.httpError(
                    statusCode: 503,
                    body: "No reachable Antigravity Desktop instances online"
                )
            }

            let chosen: RelayInstanceInfo = {
                if let prevActiveUuid,
                   let stillOnline = reachable.first(where: { $0.uuid == prevActiveUuid }) {
                    return stillOnline
                }
                if !targetInstanceIdentifier.isEmpty {
                    if let exact = reachable.first(where: { $0.matches(identifier: targetInstanceIdentifier) }) {
                        return exact
                    }
                    if let sameFamily = reachable.first(where: { $0.sameHostFamily(as: targetInstanceIdentifier) }) {
                        return sameFamily
                    }
                }
                return reachable[0]
            }()

            self.resolvedInstanceUuid = chosen.uuid
            let newReachableIds = Set(reachable.map(\.uuid))
            let newNamesByUuid = Dictionary(
                instances.map { ($0.uuid, $0.name) },
                uniquingKeysWith: { _, latest in latest }
            )
            let topologyChanged = (newReachableIds != prevReachableIds) || (chosen.uuid != prevActiveUuid)
            let metadataChanged = (newNamesByUuid != prevNamesByUuid)
            let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
            return HostReachabilityProbeResult(
                latencyMs: elapsedMs,
                availableRelayInstances: instances,
                activeRelayInstance: chosen,
                relayTopologyChanged: topologyChanged,
                relayMetadataChanged: metadataChanged
            )
        }

        let effectiveTimeout = timeoutInterval ?? 3.0
        _ = try await getWorkspaceInfosOptional(timeoutInterval: effectiveTimeout)
        let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
        return HostReachabilityProbeResult(latencyMs: elapsedMs)
    }

    /// Returns all currently reachable Cloud Relay Desktop instances (falling back to the resolved instance).
    public func currentReachableRelayInstances() -> [RelayInstanceInfo] {
        guard channel == .cloudRelay else { return [] }
        let reachable = cachedRelayInstances.filter(\.status.isReachable)
        if !reachable.isEmpty {
            return reachable
        }
        if let uuid = resolvedInstanceUuid, !uuid.isEmpty {
            return [RelayInstanceInfo(uuid: uuid, name: targetInstanceIdentifier.isEmpty ? "Mac" : targetInstanceIdentifier, status: .connected)]
        }
        return []
    }

    /// Returns the reachable Cloud Relay instance that most recently served Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) RPCs.
    public func currentPreferredCloudInstanceUuid() -> String? {
        if let pref = preferredCloudInstanceUuid, !pref.isEmpty {
            if cachedRelayInstances.isEmpty
                || cachedRelayInstances.contains(where: { $0.uuid == pref && $0.status.isReachable }) {
                return pref
            }
        }
        return selectReachableRelayUuid(preferred: resolvedInstanceUuid)
    }

    /// Refreshes `ListInstances` (when on `.cloudRelay`), federates local workspaces & summaries across all
    /// reachable instances on the signed-in Google account without cross-host spoofing, reconciles each instance's
    /// live end-to-end reachability status, and queries Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) projects & sessions.
    public func fetchFederatedWorkspacesAndSummaries(
        timeoutInterval: TimeInterval? = nil,
        lightweightPoll: Bool = false,
        skipRelayListRefresh: Bool = false
    ) async throws -> (
        workspaces: [WorkspaceInfo],
        summaries: [CascadeSummary],
        cloudProjects: [ProjectWorkspace],
        cloudWarmingUp: Bool,
        relayInstances: [RelayInstanceInfo]
    ) {
        let scoped = try await fetchFederatedScopedSyncResult(
            timeoutInterval: timeoutInterval,
            lightweightPoll: lightweightPoll,
            skipRelayListRefresh: skipRelayListRefresh
        )
        return (
            scoped.workspaces,
            scoped.summaries,
            scoped.cloudProjects,
            scoped.cloudWarmingUp,
            scoped.relayInstances
        )
    }

    /// Refreshes workspaces & conversation summaries scoped to a single `AgentHostFilter` target:
    /// - `.localHost(id, name)`: queries ONLY that specific Mac/PC (`allowCrossInstanceFailover: false`) and reconciles its live reachability.
    /// - `.antigravityCloud`: queries ONLY Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) projects & sessions.
    /// - `.allHosts`: runs full multi-host + Cloud federation and reports exactly which local hosts succeeded.
    public func fetchScopedWorkspacesAndSummaries(
        target: AgentHostFilter,
        timeoutInterval: TimeInterval? = nil,
        lightweightPoll: Bool = false,
        skipRelayListRefresh: Bool = false
    ) async throws -> ScopedWorkspaceSyncResult {
        switch target {
        case .allHosts:
            return try await fetchFederatedScopedSyncResult(
                timeoutInterval: timeoutInterval,
                lightweightPoll: lightweightPoll,
                skipRelayListRefresh: skipRelayListRefresh
            )

        case .antigravityCloud:
            let start = Date()
            if channel == .cloudRelay && cachedRelayInstances.isEmpty && !skipRelayListRefresh {
                if let refreshed = try? await listRelayInstances(timeoutInterval: min(timeoutInterval ?? 8.0, 8.0)),
                   !refreshed.isEmpty {
                    self.cachedRelayInstances = refreshed
                }
            }
            let reachableInstances = currentReachableRelayInstances()
            let preferredCloudUuid = self.preferredCloudInstanceUuid
            let orderedCloudCandidates: [RelayInstanceInfo] = {
                guard let preferredCloudUuid,
                      let prefInst = reachableInstances.first(where: { $0.uuid == preferredCloudUuid }) else {
                    return reachableInstances
                }
                return [prefInst] + reachableInstances.filter { $0.uuid != preferredCloudUuid }
            }()

            let cloudProjectOutcome = await fetchCloudProjects(
                candidateInstances: orderedCloudCandidates,
                timeoutInterval: timeoutInterval
            )
            let cloudProjects = cloudProjectOutcome.projects

            var mergedWorkspacesByKey: [String: WorkspaceInfo] = [:]
            for cp in cloudProjects {
                mergedWorkspacesByKey["cloud|\(cp.workspaceUri)"] = WorkspaceInfo(
                    workspaceUri: cp.workspaceUri,
                    displayName: cp.name,
                    activeBranch: cp.activeBranch,
                    isCloud: true,
                    originInstanceUuid: cp.originInstanceUuid,
                    originHostName: "Antigravity"
                )
            }

            let cloudSummaries: [CascadeSummary]
            if channel == .cloudRelay {
                cloudSummaries = orderedCloudCandidates.isEmpty
                    ? []
                    : await fetchCloudSummariesAcrossInstances(
                        candidates: orderedCloudCandidates,
                        timeoutInterval: timeoutInterval
                    )
            } else {
                cloudSummaries = await fetchJetboxSummariesSnapshot(
                    cloud: true,
                    originHostName: "Antigravity",
                    snapshotTimeout: min(timeoutInterval ?? 4.0, 4.0)
                )
            }

            var mergedSummariesById: [String: CascadeSummary] = [:]
            let updatedCloudProjects = self.cachedCloudProjectsById
            for s in cloudSummaries {
                Self.mergeSummaryEntry(s, into: &mergedSummariesById, cloudProjectsById: updatedCloudProjects)
            }
            Self.reconcileBatchUnreadStates(&mergedSummariesById)

            let sortedSummaries = mergedSummariesById.values.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.cascadeId < rhs.cascadeId
            }
            let sortedWorkspaces = Array(mergedWorkspacesByKey.values).sorted { $0.displayName < $1.displayName }
            let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
            let cloudReachable = (channel != .cloudRelay) || !orderedCloudCandidates.isEmpty
            return ScopedWorkspaceSyncResult(
                workspaces: sortedWorkspaces,
                summaries: sortedSummaries,
                cloudProjects: cloudProjects,
                cloudWarmingUp: cloudProjectOutcome.warmingUp,
                relayInstances: cachedRelayInstances,
                refreshedLocalHostUuids: [],
                refreshedLocalHostNames: [],
                refreshedCloud: cloudReachable,
                targetReachable: cloudReachable,
                latencyMs: elapsedMs
            )

        case .localHost(let requestedId, let requestedName):
            let start = Date()
            if channel == .cloudRelay {
                if cachedRelayInstances.isEmpty && !skipRelayListRefresh {
                    if let refreshed = try? await listRelayInstances(timeoutInterval: min(timeoutInterval ?? 6.0, 6.0)),
                       !refreshed.isEmpty {
                        self.cachedRelayInstances = refreshed
                    }
                }
                let matchedInst = cachedRelayInstances.first(where: { $0.uuid == requestedId })
                    ?? cachedRelayInstances.first(where: { $0.name == requestedName })
                let resolvedUuid = matchedInst?.uuid ?? requestedId
                let resolvedName = matchedInst?.name ?? requestedName
                let perHostTimeout = min(timeoutInterval ?? 8.0, 8.0)

                var instOk = false
                var authError: AntigravityRPCError? = nil
                let wsList: [WorkspaceInfo]
                do {
                    wsList = try await getWorkspaceInfos(
                        instanceUuidOverride: resolvedUuid,
                        originHostName: resolvedName,
                        timeoutInterval: perHostTimeout,
                        allowCrossInstanceFailover: false
                    )
                    instOk = true
                } catch let err as AntigravityRPCError {
                    if case .unauthorized = err {
                        authError = err
                    } else if case .httpError(let code, _) = err, code == 404 {
                        instOk = true
                    }
                    wsList = []
                } catch {
                    wsList = []
                }

                if let authError {
                    throw authError
                }

                async let memTask = fetchTrajectoriesResult(
                    instanceUuidOverride: resolvedUuid,
                    originHostName: resolvedName,
                    timeoutInterval: perHostTimeout,
                    allowCrossInstanceFailover: false
                )
                async let jbLocalTask = fetchJetboxSummariesSnapshot(
                    cloud: false,
                    instanceUuidOverride: resolvedUuid,
                    originHostName: resolvedName,
                    snapshotTimeout: min(perHostTimeout, 4.0),
                    allowCrossInstanceFailover: false
                )

                let memOutcome = await memTask
                let jbLocal = await jbLocalTask
                let memList: [CascadeSummary]
                switch memOutcome {
                case .success(let list):
                    memList = list
                    instOk = true
                case .failure(let err):
                    if case AntigravityRPCError.unauthorized = err {
                        throw err
                    }
                    memList = []
                }
                if !jbLocal.isEmpty {
                    instOk = true
                }

                if !cachedRelayInstances.isEmpty {
                    self.cachedRelayInstances = self.cachedRelayInstances.map { inst in
                        guard inst.uuid == resolvedUuid else { return inst }
                        if instOk {
                            return inst.status.isReachable ? inst : inst.withStatus(.connected)
                        } else {
                            return inst.status.isReachable ? inst.withStatus(.disconnected) : inst
                        }
                    }
                }

                let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
                guard instOk else {
                    return ScopedWorkspaceSyncResult(
                        workspaces: [],
                        summaries: [],
                        cloudProjects: [],
                        cloudWarmingUp: false,
                        relayInstances: cachedRelayInstances,
                        refreshedLocalHostUuids: [],
                        refreshedLocalHostNames: [],
                        refreshedCloud: false,
                        targetReachable: false,
                        latencyMs: elapsedMs
                    )
                }

                var mergedWorkspacesByKey: [String: WorkspaceInfo] = [:]
                for ws in wsList {
                    let key = ws.isCloud
                        ? "cloud|\(ws.workspaceUri)"
                        : "\(ws.originInstanceUuid ?? resolvedUuid)|\(ws.workspaceUri)"
                    if mergedWorkspacesByKey[key] == nil {
                        mergedWorkspacesByKey[key] = ws
                    }
                }
                var mergedSummariesById: [String: CascadeSummary] = [:]
                let cloudProjectsSnapshot = self.cachedCloudProjectsById
                for s in memList + jbLocal {
                    Self.mergeSummaryEntry(s, into: &mergedSummariesById, cloudProjectsById: cloudProjectsSnapshot)
                }
                Self.reconcileBatchUnreadStates(&mergedSummariesById)

                let sortedSummaries = mergedSummariesById.values.sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    return lhs.cascadeId < rhs.cascadeId
                }
                let sortedWorkspaces = Array(mergedWorkspacesByKey.values).sorted { $0.displayName < $1.displayName }
                return ScopedWorkspaceSyncResult(
                    workspaces: sortedWorkspaces,
                    summaries: sortedSummaries,
                    cloudProjects: [],
                    cloudWarmingUp: false,
                    relayInstances: cachedRelayInstances,
                    refreshedLocalHostUuids: resolvedUuid.isEmpty ? [] : [resolvedUuid],
                    refreshedLocalHostNames: resolvedName.isEmpty ? [] : [resolvedName],
                    refreshedCloud: false,
                    targetReachable: true,
                    latencyMs: elapsedMs
                )
            } else {
                // Direct LAN / Companion single host
                async let workspacesTask = getWorkspaceInfosOptional(timeoutInterval: timeoutInterval)
                async let summariesTask = getAllCascadeTrajectories(
                    originHostName: requestedName.isEmpty ? nil : requestedName,
                    timeoutInterval: timeoutInterval
                )
                let wsList = try await workspacesTask
                let sums = try await summariesTask
                var mergedWorkspacesByKey: [String: WorkspaceInfo] = [:]
                for w in wsList {
                    let key = w.isCloud ? "cloud|\(w.workspaceUri)" : "local|\(w.workspaceUri)"
                    if mergedWorkspacesByKey[key] == nil {
                        mergedWorkspacesByKey[key] = w
                    }
                }
                var mergedSummariesById: [String: CascadeSummary] = [:]
                let cloudProjectsSnapshot = self.cachedCloudProjectsById
                for s in sums {
                    Self.mergeSummaryEntry(s, into: &mergedSummariesById, cloudProjectsById: cloudProjectsSnapshot)
                }
                Self.reconcileBatchUnreadStates(&mergedSummariesById)
                let sortedSummaries = mergedSummariesById.values.sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    return lhs.cascadeId < rhs.cascadeId
                }
                let sortedWorkspaces = Array(mergedWorkspacesByKey.values).sorted { $0.displayName < $1.displayName }
                let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
                let effectiveId = requestedId.isEmpty ? targetInstanceIdentifier : requestedId
                return ScopedWorkspaceSyncResult(
                    workspaces: sortedWorkspaces,
                    summaries: sortedSummaries,
                    cloudProjects: [],
                    cloudWarmingUp: false,
                    relayInstances: [],
                    refreshedLocalHostUuids: effectiveId.isEmpty ? [] : [effectiveId],
                    refreshedLocalHostNames: requestedName.isEmpty ? [] : [requestedName],
                    refreshedCloud: false,
                    targetReachable: true,
                    latencyMs: elapsedMs
                )
            }
        }
    }

    private func fetchTrajectoriesResult(
        instanceUuidOverride: String?,
        originHostName: String?,
        timeoutInterval: TimeInterval?,
        allowCrossInstanceFailover: Bool
    ) async -> Result<[CascadeSummary], Error> {
        do {
            let list = try await getAllCascadeTrajectories(
                instanceUuidOverride: instanceUuidOverride,
                originHostName: originHostName,
                timeoutInterval: timeoutInterval,
                allowCrossInstanceFailover: allowCrossInstanceFailover
            )
            return .success(list)
        } catch {
            return .failure(error)
        }
    }

    private func fetchFederatedScopedSyncResult(
        timeoutInterval: TimeInterval? = nil,
        lightweightPoll: Bool = false,
        skipRelayListRefresh: Bool = false
    ) async throws -> ScopedWorkspaceSyncResult {
        let start = Date()
        if channel == .cloudRelay && !skipRelayListRefresh {
            if let refreshed = try? await listRelayInstances(timeoutInterval: timeoutInterval), !refreshed.isEmpty {
                self.cachedRelayInstances = refreshed
                if let currentUuid = resolvedInstanceUuid {
                    if !refreshed.contains(where: { $0.uuid == currentUuid && $0.status.isReachable }) {
                        let reachable = refreshed.filter(\.status.isReachable)
                        let exactMatch = reachable.first(where: { $0.matches(identifier: targetInstanceIdentifier) })
                        let familyMatch = reachable.first(where: { $0.sameHostFamily(as: targetInstanceIdentifier) })
                        let fallback = exactMatch ?? familyMatch ?? reachable.first ?? refreshed.first
                        if let fallback {
                            self.resolvedInstanceUuid = fallback.uuid
                        }
                    }
                } else if let fallback = refreshed.first(where: \.status.isReachable) ?? refreshed.first {
                    self.resolvedInstanceUuid = fallback.uuid
                }
            }
        }

        let reachableInstances = currentReachableRelayInstances()

        // 1. Fetch Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) projects (reuse cache on lightweight periodic ticks)
        let cloudProjectOutcome: (projects: [ProjectWorkspace], warmingUp: Bool)
        if lightweightPoll && !cachedCloudProjectsById.isEmpty {
            cloudProjectOutcome = (Array(cachedCloudProjectsById.values), false)
        } else {
            cloudProjectOutcome = await fetchCloudProjects(
                candidateInstances: reachableInstances,
                timeoutInterval: timeoutInterval
            )
        }
        let cloudProjects = cloudProjectOutcome.projects

        var mergedWorkspacesByKey: [String: WorkspaceInfo] = [:]
        for cp in cloudProjects {
            mergedWorkspacesByKey["cloud|\(cp.workspaceUri)"] = WorkspaceInfo(
                workspaceUri: cp.workspaceUri,
                displayName: cp.name,
                activeBranch: cp.activeBranch,
                isCloud: true,
                originInstanceUuid: cp.originInstanceUuid,
                originHostName: "Antigravity"
            )
        }

        var mergedSummariesById: [String: CascadeSummary] = [:]
        var verifiedOnlineUuids = Set<String>()
        var verifiedOnlineNames = Set<String>()
        var didRefreshCloud = false

        if channel == .cloudRelay && !reachableInstances.isEmpty {
            let cloudProjectsSnapshot = self.cachedCloudProjectsById
            var anyInstanceSucceeded = false
            var failedProbeUuids = Set<String>()

            // Order Cloud candidate instances with the instance that served Cloud projects first
            let preferredCloudUuid = self.preferredCloudInstanceUuid
            let orderedCloudCandidates: [RelayInstanceInfo] = {
                guard let preferredCloudUuid,
                      let prefInst = reachableInstances.first(where: { $0.uuid == preferredCloudUuid }) else {
                    return reachableInstances
                }
                return [prefInst] + reachableInstances.filter { $0.uuid != preferredCloudUuid }
            }()

            // Run Cloud (`BACKEND_TYPE_REMOTE_AICODE`) summary fetch concurrently with Local per-instance federation
            async let cloudSummariesTask: [CascadeSummary] = self.fetchCloudSummariesAcrossInstances(
                candidates: orderedCloudCandidates,
                timeoutInterval: timeoutInterval
            )

            await withTaskGroup(of: (String, String, Bool, [WorkspaceInfo], [CascadeSummary], [CascadeSummary]).self) { group in
                for inst in reachableInstances {
                    group.addTask {
                        var instOk = false
                        let ws: [WorkspaceInfo]
                        do {
                            ws = try await self.getWorkspaceInfos(
                                instanceUuidOverride: inst.uuid,
                                originHostName: inst.name,
                                timeoutInterval: timeoutInterval,
                                allowCrossInstanceFailover: false
                            )
                            instOk = true
                        } catch let AntigravityRPCError.httpError(code, _) where code == 404 {
                            ws = []
                            instOk = true
                        } catch {
                            ws = []
                        }

                        async let memTask = self.getAllCascadeTrajectories(
                            instanceUuidOverride: inst.uuid,
                            originHostName: inst.name,
                            timeoutInterval: timeoutInterval,
                            allowCrossInstanceFailover: false
                        )
                        async let jbLocalTask = self.fetchJetboxSummariesSnapshot(
                            cloud: false,
                            instanceUuidOverride: inst.uuid,
                            originHostName: inst.name,
                            snapshotTimeout: 4.0,
                            allowCrossInstanceFailover: false
                        )

                        let memResult = try? await memTask
                        let jbLocal = await jbLocalTask
                        if memResult != nil || !jbLocal.isEmpty {
                            instOk = true
                        }
                        return (inst.uuid, inst.name, instOk, ws, memResult ?? [], jbLocal)
                    }
                }

                for await (instUuid, instName, instOk, wsList, memList, jbLocalList) in group {
                    if instOk {
                        anyInstanceSucceeded = true
                        verifiedOnlineUuids.insert(instUuid)
                        if !instName.isEmpty {
                            verifiedOnlineNames.insert(instName)
                        }
                    } else {
                        failedProbeUuids.insert(instUuid)
                    }
                    for ws in wsList {
                        let key = ws.isCloud
                            ? "cloud|\(ws.workspaceUri)"
                            : "\(ws.originInstanceUuid ?? instUuid)|\(ws.workspaceUri)"
                        if mergedWorkspacesByKey[key] == nil {
                            mergedWorkspacesByKey[key] = ws
                        }
                    }
                    for s in memList + jbLocalList {
                        Self.mergeSummaryEntry(s, into: &mergedSummariesById, cloudProjectsById: cloudProjectsSnapshot)
                    }
                }
            }

            // Reconcile end-to-end reachability back into `cachedRelayInstances` so unresponsive Relay entries show Offline.
            if !failedProbeUuids.isEmpty {
                self.cachedRelayInstances = self.cachedRelayInstances.map { inst in
                    if failedProbeUuids.contains(inst.uuid) && inst.status.isReachable {
                        return inst.withStatus(.disconnected)
                    }
                    return inst
                }
            }

            let cloudSummaries = await cloudSummariesTask
            let updatedCloudProjects = self.cachedCloudProjectsById
            if !cloudSummaries.isEmpty {
                anyInstanceSucceeded = true
                for s in cloudSummaries {
                    Self.mergeSummaryEntry(s, into: &mergedSummariesById, cloudProjectsById: updatedCloudProjects)
                }
            }
            didRefreshCloud = !cloudProjects.isEmpty || !cloudSummaries.isEmpty || !verifiedOnlineUuids.isEmpty

            if !anyInstanceSucceeded && cloudProjects.isEmpty {
                let ws = try await getWorkspaceInfosOptional(timeoutInterval: timeoutInterval)
                let sums = try await getAllCascadeTrajectories(timeoutInterval: timeoutInterval)
                for w in ws {
                    let key = w.isCloud ? "cloud|\(w.workspaceUri)" : "\(w.originInstanceUuid ?? "local")|\(w.workspaceUri)"
                    mergedWorkspacesByKey[key] = w
                }
                for s in sums { Self.mergeSummaryEntry(s, into: &mergedSummariesById, cloudProjectsById: updatedCloudProjects) }
                if let fallbackUuid = resolvedInstanceUuid, !fallbackUuid.isEmpty {
                    verifiedOnlineUuids.insert(fallbackUuid)
                }
            }
        } else {
            // Direct LAN / Companion / Mock server mode
            async let workspacesTask = getWorkspaceInfosOptional(timeoutInterval: timeoutInterval)
            async let summariesTask = getAllCascadeTrajectories(timeoutInterval: timeoutInterval)
            let workspaces = try await workspacesTask
            let summaries = try await summariesTask
            let cloudSummaries = await fetchJetboxSummariesSnapshot(
                cloud: true,
                originHostName: "Antigravity",
                snapshotTimeout: 1.5
            )
            let cloudProjectsSnapshot = self.cachedCloudProjectsById
            for w in workspaces {
                let key = w.isCloud ? "cloud|\(w.workspaceUri)" : "local|\(w.workspaceUri)"
                if mergedWorkspacesByKey[key] == nil {
                    mergedWorkspacesByKey[key] = w
                }
            }
            for s in summaries + cloudSummaries {
                Self.mergeSummaryEntry(s, into: &mergedSummariesById, cloudProjectsById: cloudProjectsSnapshot)
            }
            let directId = resolvedInstanceUuid ?? targetInstanceIdentifier
            if !directId.isEmpty {
                verifiedOnlineUuids.insert(directId)
            }
            didRefreshCloud = !cloudProjects.isEmpty || !cloudSummaries.isEmpty
        }

        Self.reconcileBatchUnreadStates(&mergedSummariesById)

        let sortedSummaries = mergedSummariesById.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.cascadeId < rhs.cascadeId
        }
        let sortedWorkspaces = Array(mergedWorkspacesByKey.values).sorted { $0.displayName < $1.displayName }
        let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
        return ScopedWorkspaceSyncResult(
            workspaces: sortedWorkspaces,
            summaries: sortedSummaries,
            cloudProjects: cloudProjects,
            cloudWarmingUp: cloudProjectOutcome.warmingUp,
            relayInstances: cachedRelayInstances,
            refreshedLocalHostUuids: verifiedOnlineUuids,
            refreshedLocalHostNames: verifiedOnlineNames,
            refreshedCloud: didRefreshCloud,
            targetReachable: !verifiedOnlineUuids.isEmpty || didRefreshCloud || channel != .cloudRelay,
            latencyMs: elapsedMs
        )
    }

    private func fetchCloudSummariesAcrossInstances(
        candidates: [RelayInstanceInfo],
        timeoutInterval: TimeInterval?
    ) async -> [CascadeSummary] {
        let cloudProjectsSnapshot = self.cachedCloudProjectsById
        for inst in candidates {
            async let jbTask = fetchJetboxSummariesSnapshot(
                cloud: true,
                instanceUuidOverride: inst.uuid,
                originHostName: "Antigravity",
                snapshotTimeout: 4.5
            )
            async let unaryTask = getAllCascadeTrajectoriesCloud(
                instanceUuidOverride: inst.uuid,
                timeoutInterval: timeoutInterval ?? 8.0
            )
            let jbCloud = await jbTask
            let unaryCloud = await unaryTask
            var combined: [String: CascadeSummary] = [:]
            for s in unaryCloud + jbCloud {
                Self.mergeSummaryEntry(s, into: &combined, cloudProjectsById: cloudProjectsSnapshot)
            }
            if !combined.isEmpty {
                self.preferredCloudInstanceUuid = inst.uuid
                return Array(combined.values)
            }
        }
        return []
    }

    /// Resolves the canonical Antigravity Cloud `ProjectWorkspace` matching `summary` by:
    /// 1. Exact or `projects/`-normalized `cloudProjectId`,
    /// 2. Case-insensitive `workspaceUri` (`cloud://owner/repo`),
    /// 3. Normalized Cloud location label (`owner/repo`), or
    /// 4. Unique repo short-name suffix when `summary.isCloud == true`.
    internal static func matchCloudProject(
        for summary: CascadeSummary,
        cloudProjects: [ProjectWorkspace]
    ) -> ProjectWorkspace? {
        guard !cloudProjects.isEmpty else { return nil }

        func normalizeProjectId(_ raw: String) -> String {
            var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("projects/") {
                trimmed = String(trimmed.dropFirst("projects/".count))
            }
            return trimmed
        }

        if let rawCpid = summary.cloudProjectId, !rawCpid.isEmpty {
            let normCpid = normalizeProjectId(rawCpid)
            if let exact = cloudProjects.first(where: { cp in
                let cpId = cp.cloudProjectId ?? cp.id
                return cpId == rawCpid || cp.id == rawCpid
                    || normalizeProjectId(cpId) == normCpid
                    || normalizeProjectId(cp.id) == normCpid
            }) {
                return exact
            }
        }

        if !summary.workspaceUri.isEmpty {
            if let byUri = cloudProjects.first(where: {
                !$0.workspaceUri.isEmpty
                    && $0.workspaceUri.caseInsensitiveCompare(summary.workspaceUri) == .orderedSame
            }) {
                return byUri
            }
            if let summaryLabel = AntigravityCloudDetector.extractCloudLocationLabel(summary.workspaceUri) {
                if let byLabel = cloudProjects.first(where: { cp in
                    if let cpLabel = AntigravityCloudDetector.extractCloudLocationLabel(cp.workspaceUri),
                       cpLabel.caseInsensitiveCompare(summaryLabel) == .orderedSame {
                        return true
                    }
                    return cp.name.caseInsensitiveCompare(summaryLabel) == .orderedSame
                }) {
                    return byLabel
                }
            }
        }

        if summary.isCloud && !AntigravityCloudDetector.isNoProjectSlug(summary.projectSlug) {
            let cleanSlug = summary.projectSlug.lowercased().hasPrefix("cloud:")
                ? String(summary.projectSlug.dropFirst("cloud:".count))
                : summary.projectSlug
            if let exactName = cloudProjects.first(where: {
                $0.name.caseInsensitiveCompare(cleanSlug) == .orderedSame
            }) {
                return exactName
            }
            let suffixMatches = cloudProjects.filter { cp in
                let repoFromName = cp.name.split(separator: "/").last.map(String.init) ?? cp.name
                let repoFromUri = AntigravityCloudDetector.extractCloudLocationLabel(cp.workspaceUri)?
                    .split(separator: "/").last.map(String.init)
                return repoFromName.caseInsensitiveCompare(cleanSlug) == .orderedSame
                    || (repoFromUri?.caseInsensitiveCompare(cleanSlug) == .orderedSame)
            }
            if suffixMatches.count == 1 {
                return suffixMatches[0]
            }
        }

        return nil
    }

    private static func summaryStatusPriority(_ status: CortexStepStatus) -> Int {
        switch status {
        case .waiting, .blocked: return 4
        case .inProgress, .pending: return 3
        case .error, .cancelled: return 2
        case .done: return 1
        case .unspecified: return 0
        }
    }

    internal static func mergeSummaryEntry(
        _ incoming: CascadeSummary,
        into map: inout [String: CascadeSummary],
        cloudProjectsById: [String: ProjectWorkspace]
    ) {
        let allCloudProjects = Array(cloudProjectsById.values)
        var resolved = incoming
        if let cp = matchCloudProject(for: resolved, cloudProjects: allCloudProjects) {
            resolved.isCloud = true
            resolved.cloudProjectId = cp.cloudProjectId ?? cp.id
            resolved.projectSlug = cp.name
            resolved.workspaceUri = cp.workspaceUri
            resolved.originHostName = "Antigravity"
        }

        guard let existing = map[resolved.cascadeId] else {
            map[resolved.cascadeId] = resolved
            return
        }

        var merged = resolved.stepCount >= existing.stepCount && resolved.updatedAt >= existing.updatedAt
            ? resolved
            : existing

        // 1. Title: never let default placeholder overwrite a real title
        if existing.title != "New Conversation" && resolved.title == "New Conversation" {
            merged.title = existing.title
        } else if resolved.title != "New Conversation" && existing.title == "New Conversation" {
            merged.title = resolved.title
        } else if resolved.title != "New Conversation" && resolved.updatedAt >= existing.updatedAt {
            merged.title = resolved.title
        } else {
            merged.title = existing.title
        }

        // 2. Cloud identity & canonical project binding
        merged.isCloud = existing.isCloud || resolved.isCloud
        merged.cloudProjectId = nonEmptyString(resolved.cloudProjectId) ?? nonEmptyString(existing.cloudProjectId)
        if merged.isCloud {
            merged.originHostName = "Antigravity"
        }
        if !AntigravityCloudDetector.isNoProjectSlug(existing.projectSlug)
            && AntigravityCloudDetector.isNoProjectSlug(merged.projectSlug) {
            merged.projectSlug = existing.projectSlug
            if merged.workspaceUri.isEmpty {
                merged.workspaceUri = existing.workspaceUri
            }
        }
        if !AntigravityCloudDetector.isNoProjectSlug(resolved.projectSlug)
            && AntigravityCloudDetector.isNoProjectSlug(merged.projectSlug) {
            merged.projectSlug = resolved.projectSlug
            if merged.workspaceUri.isEmpty {
                merged.workspaceUri = resolved.workspaceUri
            }
        }
        if let cp = matchCloudProject(for: merged, cloudProjects: allCloudProjects) {
            merged.isCloud = true
            merged.cloudProjectId = cp.cloudProjectId ?? cp.id
            merged.projectSlug = cp.name
            merged.workspaceUri = cp.workspaceUri
            merged.originHostName = "Antigravity"
        }

        // 3. Step count & timestamps
        merged.stepCount = max(existing.stepCount, resolved.stepCount)
        merged.currentStepIndex = max(1, merged.stepCount)
        merged.totalSteps = max(1, merged.stepCount)
        if resolved.updatedAt >= existing.updatedAt {
            merged.updatedAt = resolved.updatedAt
            merged.relativeTimeLabel = resolved.relativeTimeLabel
        } else {
            merged.updatedAt = existing.updatedAt
            merged.relativeTimeLabel = existing.relativeTimeLabel
        }

        // 4. Status: prioritize live RUNNING / WAITING over stale IDLE across multi-window & Jetbox merges
        let chosenStatus: CortexStepStatus
        if resolved.stepCount > existing.stepCount {
            if resolved.status == .unspecified
                && (existing.status == .waiting || existing.status == .blocked)
                && resolved.updatedAt <= existing.updatedAt {
                chosenStatus = existing.status
            } else {
                chosenStatus = resolved.status
            }
        } else if existing.stepCount > resolved.stepCount {
            if existing.status == .unspecified
                && (resolved.status == .waiting || resolved.status == .blocked)
                && resolved.updatedAt >= existing.updatedAt {
                chosenStatus = resolved.status
            } else {
                chosenStatus = existing.status
            }
        } else {
            let pResolved = summaryStatusPriority(resolved.status)
            let pExisting = summaryStatusPriority(existing.status)
            if pResolved > pExisting {
                if (resolved.status == .inProgress || resolved.status == .pending)
                    && existing.updatedAt > resolved.updatedAt.addingTimeInterval(2.0) {
                    chosenStatus = existing.status
                } else {
                    chosenStatus = resolved.status
                }
            } else if pExisting > pResolved {
                if (existing.status == .waiting || existing.status == .blocked
                    || existing.status == .inProgress || existing.status == .pending)
                    && resolved.updatedAt <= existing.updatedAt.addingTimeInterval(2.0) {
                    chosenStatus = existing.status
                } else {
                    chosenStatus = resolved.updatedAt >= existing.updatedAt ? resolved.status : existing.status
                }
            } else {
                chosenStatus = resolved.updatedAt >= existing.updatedAt ? resolved.status : existing.status
            }
        }
        merged.status = chosenStatus

        // 5. Route origin instance to whichever peer owns the active run or higher step count
        if !merged.isCloud {
            let resolvedIsMoreActive = summaryStatusPriority(resolved.status) > summaryStatusPriority(existing.status)
                || resolved.stepCount > existing.stepCount
            if resolvedIsMoreActive, let rUuid = resolved.originInstanceUuid, !rUuid.isEmpty {
                merged.originInstanceUuid = rUuid
                merged.originHostName = resolved.originHostName ?? existing.originHostName
            } else if let eUuid = existing.originInstanceUuid, !eUuid.isEmpty,
                      (summaryStatusPriority(existing.status) > summaryStatusPriority(resolved.status)
                       || existing.stepCount > resolved.stepCount
                       || resolved.originInstanceUuid == nil) {
                merged.originInstanceUuid = eUuid
                merged.originHostName = existing.originHostName ?? resolved.originHostName
            } else {
                merged.originInstanceUuid = resolved.originInstanceUuid ?? existing.originInstanceUuid
                merged.originHostName = resolved.originHostName ?? existing.originHostName
            }
        } else {
            merged.originInstanceUuid = resolved.originInstanceUuid ?? existing.originInstanceUuid
            merged.originHostName = "Antigravity"
        }

        // 6. Annotations (`isPinned`, `isArchived`, `lastUserViewTime`, `isUnread`)
        merged.isPinned = existing.isPinned || resolved.isPinned
        merged.isArchived = existing.isArchived || resolved.isArchived
        let latestViewed = [existing.lastUserViewTime, resolved.lastUserViewTime].compactMap { $0 }.max()
        merged.lastUserViewTime = latestViewed

        if merged.status == .inProgress || merged.status == .pending {
            merged.isUnread = false
        } else if let latestViewed {
            merged.isUnread = merged.updatedAt.timeIntervalSince(latestViewed) > 0.5
                || merged.status == .waiting
                || merged.status == .blocked
        } else {
            merged.isUnread = existing.isUnread || resolved.isUnread
                || merged.status == .waiting
                || merged.status == .blocked
        }

        merged.statusSubtitle = Self.buildLiveStatusSubtitle(
            status: merged.status,
            stepCount: merged.stepCount,
            isUnread: merged.isUnread
        )
        map[resolved.cascadeId] = merged
    }

    /// Reconciles unread flags per host/cloud bucket when Desktop emits `lastUserViewTime` on viewed
    /// conversations and omits `lastUserViewTime` on newly completed conversations never opened yet.
    internal static func reconcileBatchUnreadStates(
        _ map: inout [String: CascadeSummary],
        now: Date = Date()
    ) {
        var buckets: [String: [String]] = [:]
        for (cid, summary) in map {
            let bucketKey = summary.isCloud ? "__cloud__" : (summary.originInstanceUuid ?? "__local__")
            buckets[bucketKey, default: []].append(cid)
        }
        let maxInferredUnreadAgeSeconds: TimeInterval = 7 * 86_400
        for (_, cids) in buckets {
            let bucketTracksViewTime = cids.contains { map[$0]?.lastUserViewTime != nil }
            guard bucketTracksViewTime else { continue }
            for cid in cids {
                guard var s = map[cid] else { continue }
                guard s.lastUserViewTime == nil,
                      !s.isUnread,
                      !s.isArchived,
                      s.stepCount > 0,
                      s.status != .inProgress,
                      s.status != .pending,
                      s.status != .cancelled,
                      now.timeIntervalSince(s.updatedAt) <= maxInferredUnreadAgeSeconds else {
                    continue
                }
                s.isUnread = true
                s.statusSubtitle = Self.buildLiveStatusSubtitle(
                    status: s.status,
                    stepCount: s.stepCount,
                    isUnread: true
                )
                map[cid] = s
            }
        }
    }

    private func getWorkspaceInfosOptional(timeoutInterval: TimeInterval?) async throws -> [WorkspaceInfo] {
        do {
            return try await getWorkspaceInfos(timeoutInterval: timeoutInterval)
        } catch let AntigravityRPCError.httpError(statusCode, _) where statusCode == 404 {
            return []
        } catch {
            if channel == .cloudRelay {
                return []
            }
            throw error
        }
    }

    // MARK: - Core Unary RPC (`Sendable` JSONValue & Binary Protobuf)

    public func callUnaryJSON(
        method: String,
        body: [String: JSONValue] = [:],
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil,
        allowCrossInstanceFailover: Bool = true
    ) async throws -> [String: JSONValue] {
        if channel == .cloudRelay {
            let relayTimeout = allowCrossInstanceFailover
                ? timeoutInterval.map { max($0, 10.0) }
                : timeoutInterval
            return try await callCloudRelayUnaryJSON(
                method: method,
                body: body,
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: relayTimeout,
                allowCrossInstanceFailover: allowCrossInstanceFailover
            )
        }

        let url = endpointURL.appendingPathComponent("\(Self.servicePrefix)/\(method)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        applyAuthHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AntigravityRPCError.invalidEndpoint
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            let text = String(data: data, encoding: .utf8) ?? "Unauthorized"
            throw AntigravityRPCError.unauthorized(text)
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AntigravityRPCError.httpError(statusCode: http.statusCode, body: text)
        }
        if data.isEmpty {
            return [:]
        }
        guard let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            throw AntigravityRPCError.decodingError("Expected JSON object from \(method)")
        }
        return decoded
    }

    private func callCloudRelayUnaryJSON(
        method: String,
        body: [String: JSONValue],
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil,
        allowCrossInstanceFailover: Bool = true,
        allowStripUnknownFields: Bool = true
    ) async throws -> [String: JSONValue] {
        if Self.localDesktopOnlyMethods.contains(method) {
            throw AntigravityRPCError.httpError(
                statusCode: 501,
                body: "\(method) is only available when connected directly to a local desktop workspace."
            )
        }

        var workingBody = try await sanitizeCloudRelayPayload(method: method, body: body)
        for attempt in 1...4 {
            let encodedPayload = workingBody.isEmpty ? Data("{}".utf8) : try JSONEncoder().encode(workingBody)
            let (rawRespData, _) = try await callCloudRelayProxyCommand(
                method: method,
                payload: encodedPayload,
                contentType: "application/json",
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: timeoutInterval,
                allowCrossInstanceFailover: allowCrossInstanceFailover
            )
            let respData = Self.unwrapConnectFramedPayloadIfNeeded(rawRespData)
            if respData.isEmpty {
                return [:]
            }
            if let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: respData) {
                if let code = decoded["code"]?.stringValue,
                   let message = decoded["message"]?.stringValue,
                   decoded.count <= 3 {
                    if allowStripUnknownFields, attempt < 4, let unknownField = Self.extractUnknownProtoFieldName(from: message) {
                        if workingBody[unknownField] != nil {
                            workingBody.removeValue(forKey: unknownField)
                            continue
                        }
                        if var cascadeCfg = workingBody["cascadeConfig"]?.objectValue,
                           var plannerCfg = cascadeCfg["plannerConfig"]?.objectValue,
                           plannerCfg[unknownField] != nil {
                            plannerCfg.removeValue(forKey: unknownField)
                            cascadeCfg["plannerConfig"] = .object(plannerCfg)
                            workingBody["cascadeConfig"] = .object(cascadeCfg)
                            continue
                        }
                    }
                    throw AntigravityRPCError.httpError(statusCode: 400, body: "\(code): \(message)")
                }
                return decoded
            }
            let rawText = String(data: respData, encoding: .utf8) ?? ""
            if allowStripUnknownFields, attempt < 4,
               let unknownField = Self.extractUnknownProtoFieldName(from: rawText),
               workingBody[unknownField] != nil {
                workingBody.removeValue(forKey: unknownField)
                continue
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

    private func selectReachableRelayUuid(
        preferred: String?,
        allowCrossInstanceFailover: Bool = true
    ) -> String? {
        let candidate = (preferred?.isEmpty == false) ? preferred : resolvedInstanceUuid
        if !allowCrossInstanceFailover, let candidate, !candidate.isEmpty {
            return candidate
        }
        guard !cachedRelayInstances.isEmpty else { return candidate }
        if let candidate,
           cachedRelayInstances.contains(where: { $0.uuid == candidate && $0.status.isReachable }) {
            return candidate
        }
        let familySeed = cachedRelayInstances.first(where: { $0.uuid == candidate })?.name ?? targetInstanceIdentifier
        let familyOnline = cachedRelayInstances.first(where: {
            $0.status.isReachable && $0.sameHostFamily(as: familySeed)
        })
        let preferredResolved = resolvedInstanceUuid.flatMap { resUuid in
            cachedRelayInstances.contains(where: { $0.uuid == resUuid && $0.status.isReachable }) ? resUuid : nil
        }
        let anyOnline = cachedRelayInstances.first(where: \.status.isReachable)
        if let liveBest = familyOnline?.uuid ?? preferredResolved ?? anyOnline?.uuid {
            if resolvedInstanceUuid == nil
                || !cachedRelayInstances.contains(where: { $0.uuid == resolvedInstanceUuid && $0.status.isReachable }) {
                self.resolvedInstanceUuid = liveBest
            }
            return liveBest
        }
        return candidate
    }

    private func callCloudRelayProxyCommand(
        method: String,
        payload: Data,
        contentType: String,
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil,
        allowCrossInstanceFailover: Bool = true
    ) async throws -> (payload: Data, headers: [String: String]) {
        if instanceUuidOverride == nil && resolvedInstanceUuid == nil {
            _ = try await resolveCloudRelayInstance(
                preferredIdentifier: targetInstanceIdentifier,
                timeoutInterval: timeoutInterval
            )
        } else if cachedRelayInstances.isEmpty {
            if let refreshed = try? await listRelayInstances(timeoutInterval: min(timeoutInterval ?? 6.0, 6.0)),
               !refreshed.isEmpty {
                self.cachedRelayInstances = refreshed
            }
        }

        guard let initialTargetUuid = selectReachableRelayUuid(
            preferred: instanceUuidOverride,
            allowCrossInstanceFailover: allowCrossInstanceFailover
        ),
              !initialTargetUuid.isEmpty else {
            throw AntigravityRPCError.invalidEndpoint
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

        func sendOnce(to targetUuid: String, authUserOverride: String? = nil) async throws -> (payload: Data, headers: [String: String]) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            if let timeoutInterval {
                request.timeoutInterval = timeoutInterval
            }
            SAPISIDHashGenerator.applyApiServiceHeaders(
                to: &request,
                cookieHeader: currentCookie,
                origin: originStr,
                authUser: authUserOverride ?? currentAuthUser,
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
            if http.statusCode == 401 || http.statusCode == 403 {
                let text = String(data: data, encoding: .utf8) ?? "Unauthorized"
                throw AntigravityRPCError.unauthorized(text)
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw AntigravityRPCError.httpError(statusCode: http.statusCode, body: text)
            }
            return try CloudRelayJSPBCodec.decodeProxyCommandResponse(
                data,
                responseHeaders: http.allHeaderFields
            )
        }

        do {
            return try await sendOnce(to: initialTargetUuid)
        } catch let AntigravityRPCError.unauthorized(msg) {
            if let resolved = try? await resolveCloudRelayInstance(
                preferredIdentifier: targetInstanceIdentifier,
                timeoutInterval: 6.0
            ), (resolved.matchedAuthUser != currentAuthUser || resolved.selected.uuid != initialTargetUuid) {
                return try await sendOnce(to: resolved.selected.uuid, authUserOverride: resolved.matchedAuthUser)
            }
            throw AntigravityRPCError.unauthorized(msg)
        } catch {
            let shouldFailover: Bool = {
                guard allowCrossInstanceFailover else { return false }
                if error is URLError { return true }
                if case let AntigravityRPCError.httpError(code, _) = error {
                    return code == 404 || code == 502 || code == 503 || code == 504
                }
                return false
            }()
            if shouldFailover,
               let refreshed = try? await listRelayInstances(timeoutInterval: 6.0),
               !refreshed.isEmpty {
                self.cachedRelayInstances = refreshed
                let familySeed = refreshed.first(where: { $0.uuid == initialTargetUuid })?.name ?? targetInstanceIdentifier
                if let altInst = refreshed.first(where: {
                    $0.uuid != initialTargetUuid && $0.status.isReachable && $0.sameHostFamily(as: familySeed)
                }) ?? refreshed.first(where: {
                    $0.uuid != initialTargetUuid && $0.status.isReachable
                }) {
                    self.resolvedInstanceUuid = altInst.uuid
                    return try await sendOnce(to: altInst.uuid)
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
            if let cid = body["cascadeId"]?.stringValue, !cid.isEmpty {
                clean["cascadeId"] = .string(cid)
            }
            if let backend = body["backend"]?.stringValue, !backend.isEmpty {
                clean["backend"] = .string(backend)
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

    private func ensureUpstreamModelCatalog() async -> (defaultModel: String?, validModels: Set<String>) {
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
               let configs = obj["clientModelConfigs"]?.arrayValue,
               !configs.isEmpty {
                if let quotaObj = obj["usageQuota"]?.objectValue ?? obj["quotaSummary"]?.objectValue {
                    parsedQuota = Self.parseUsageQuota(quotaObj)
                }
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
                    let supportedEfforts: [ThinkingEffortLevel] = {
                        if let rawEfforts = cfg["supportedEfforts"]?.arrayValue {
                            let mapped = rawEfforts.compactMap { val -> ThinkingEffortLevel? in
                                guard let s = val.stringValue?.lowercased() else { return nil }
                                if s == "xhigh" || s == "extra" { return .extra }
                                return ThinkingEffortLevel.allCases.first { $0.rawValue.lowercased() == s }
                            }
                            if !mapped.isEmpty { return mapped }
                        }
                        if isOrchestrator { return [.high] }
                        if lowerLabel.contains("neon") || lowerLabel.contains("hydrogen") {
                            return [.low, .medium, .high, .extra]
                        }
                        return [.low, .medium, .high]
                    }()
                    let effort: ThinkingEffortLevel = {
                        if lowerLabel.contains("(xhigh)") || lowerLabel.contains("(x-high)") || lowerLabel.contains("(extra") {
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

                    parsedModels.append(
                        CascadeModelConfig(
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
                            isNewBadge: (cfg["isNew"]?.boolValue ?? false) || lowerLabel.contains("gemini 4") || isOrchestrator
                        )
                    )
                    if cfg["isRecommended"]?.boolValue == true && defaultModelId == nil {
                        defaultModelId = modelId
                    }
                }
                let overrideMoa = obj["defaultOverrideModelConfig"]?.objectValue?["modelOrAlias"]?.objectValue
                if let defM = Self.nonEmptyString(overrideMoa?["model"]?.stringValue), defM != "MODEL_UNSPECIFIED" {
                    defaultModelId = defM
                } else if let defA = Self.nonEmptyString(overrideMoa?["alias"]?.stringValue) {
                    defaultModelId = defA
                }
                if !parsedModels.isEmpty {
                    break
                }
            }
        }

        if parsedModels.isEmpty,
           let availWrapper = try? await callUnaryJSON(
               method: "GetAvailableModels",
               body: ["forceRefresh": .bool(forceRefresh)],
               timeoutInterval: 8.0
           ) {
            let resp = availWrapper["response"]?.objectValue ?? availWrapper
            if parsedQuota == nil, let quotaObj = resp["usageQuota"]?.objectValue {
                parsedQuota = Self.parseUsageQuota(quotaObj)
            }
            if let modelsMap = resp["models"]?.objectValue, !modelsMap.isEmpty {
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
                    let effort: ThinkingEffortLevel = {
                        if lowerLabel.contains("(xhigh)") || lowerLabel.contains("(x-high)") || lowerLabel.contains("(extra") {
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

                    parsedModels.append(
                        CascadeModelConfig(
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
                            supportedEfforts: (lowerLabel.contains("neon") || lowerLabel.contains("hydrogen"))
                                ? [.low, .medium, .high, .extra] : [.low, .medium, .high],
                            isNewBadge: lowerLabel.contains("gemini 4") || isOrchestrator
                        )
                    )
                }
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

        let finalModels = parsedModels.isEmpty ? CascadeModelConfig.liveDefaultCatalog : parsedModels
        return LiveModelCatalogResult(
            models: finalModels,
            defaultModelId: defaultModelId ?? finalModels.first?.modelId,
            agents: agents,
            usageQuota: parsedQuota
        )
    }

    private static func parseUsageQuota(_ obj: [String: JSONValue]) -> ModelUsageQuota {
        ModelUsageQuota(
            geminiWeeklyRemaining: obj["geminiWeeklyRemaining"]?.doubleValue ?? 0.85,
            geminiFiveHourRemaining: obj["geminiFiveHourRemaining"]?.doubleValue ?? 0.92,
            partnerWeeklyRemaining: obj["partnerWeeklyRemaining"]?.doubleValue ?? 0.70,
            partnerFiveHourRemaining: obj["partnerFiveHourRemaining"]?.doubleValue ?? 0.80,
            aiCreditOveragesEnabled: obj["aiCreditOveragesEnabled"]?.boolValue ?? obj["hasExtraCredits"]?.boolValue ?? false,
            planDisplayName: obj["planDisplayName"]?.stringValue ?? obj["planTier"]?.stringValue ?? "Google AI Ultra"
        )
    }

    private static func defaultSubtitle(forModelLabel label: String) -> String {
        CascadeModelConfig.descriptiveSubtitle(forModelLabel: label)
    }

    // MARK: - Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) Projects & Summaries

    /// Lists and reads Antigravity Cloud ("Remote Agents") projects via `ListProjects` + `ReadProject`.
    public func fetchCloudProjects(
        candidateInstances: [RelayInstanceInfo] = [],
        timeoutInterval: TimeInterval? = nil
    ) async -> (projects: [ProjectWorkspace], warmingUp: Bool) {
        let targetUuids: [String?] = {
            if channel == .cloudRelay && !candidateInstances.isEmpty {
                if let pref = preferredCloudInstanceUuid,
                   candidateInstances.contains(where: { $0.uuid == pref }) {
                    let rest = candidateInstances.filter { $0.uuid != pref }.map { Optional($0.uuid) }
                    return [Optional(pref)] + rest
                }
                return candidateInstances.map { Optional($0.uuid) }
            }
            return [nil]
        }()

        var sawWarmingUp = false
        for targetUuid in targetUuids {
            do {
                let listResp = try await callUnaryJSON(
                    method: "ListProjects",
                    body: ["backend": .string("BACKEND_TYPE_REMOTE_AICODE")],
                    instanceUuidOverride: targetUuid,
                    timeoutInterval: timeoutInterval ?? 8.0
                )
                let ids = listResp["projectIds"]?.arrayValue?.compactMap(\.stringValue).filter { !$0.isEmpty } ?? []
                guard !ids.isEmpty else { continue }

                var loaded: [ProjectWorkspace] = []
                for pid in ids {
                    if let readResp = try? await callUnaryJSON(
                        method: "ReadProject",
                        body: ["id": .string(pid)],
                        instanceUuidOverride: targetUuid,
                        timeoutInterval: timeoutInterval ?? 8.0
                    ),
                    let projObj = readResp["project"]?.objectValue {
                        let parsed = Self.decodeCloudProjectObject(projObj, fallbackId: pid, originInstanceUuid: targetUuid)
                        cachedCloudProjectsById[parsed.id] = parsed
                        loaded.append(parsed)
                    }
                }
                if !loaded.isEmpty {
                    if let effectiveUuid = targetUuid ?? resolvedInstanceUuid, !effectiveUuid.isEmpty {
                        self.preferredCloudInstanceUuid = effectiveUuid
                    }
                    return (loaded, false)
                }
            } catch let AntigravityRPCError.httpError(_, body) {
                let lower = body.lowercased()
                if lower.contains("failed_precondition") || lower.contains("not enabled") || lower.contains("precondition") {
                    sawWarmingUp = true
                }
            } catch {
                continue
            }
        }
        return ([], sawWarmingUp)
    }

    private static func decodeCloudProjectObject(
        _ projObj: [String: JSONValue],
        fallbackId: String,
        originInstanceUuid: String?
    ) -> ProjectWorkspace {
        let pid = nonEmptyString(projObj["id"]?.stringValue) ?? fallbackId
        let name = nonEmptyString(projObj["name"]?.stringValue) ?? "Antigravity Cloud"
        let resources = projObj["projectResources"]?.objectValue?["resources"]?.arrayValue ?? []
        var repoDisplay: String? = nil
        for resEntry in resources {
            guard let resObj = resEntry.objectValue else { continue }
            let nestedCandidates: [[String: JSONValue]?] = [
                resObj["remoteResource"]?.objectValue,
                resObj["githubRepo"]?.objectValue,
                resObj["githubRepository"]?.objectValue,
                resObj["gitFolder"]?.objectValue
            ]
            if let rr = nestedCandidates.compactMap({ $0 }).first {
                let displayNameCandidates: [String?] = [
                    rr["displayName"]?.stringValue,
                    rr["fullName"]?.stringValue,
                    rr["name"]?.stringValue,
                    rr["uri"]?.stringValue,
                    rr["folderUri"]?.stringValue
                ]
                if let dn = displayNameCandidates.compactMap(nonEmptyString).first {
                    var normalized = dn
                        .replacingOccurrences(of: "https://github.com/", with: "")
                        .replacingOccurrences(of: "http://github.com/", with: "")
                        .replacingOccurrences(of: "cloud://", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if normalized.hasSuffix(".git") {
                        normalized = String(normalized.dropLast(4))
                    }
                    if !normalized.isEmpty {
                        repoDisplay = normalized
                        break
                    }
                }
            }
        }
        if repoDisplay == nil {
            if let fallbackRepo = nonEmptyString(projObj["repository"]?.stringValue)
                ?? nonEmptyString(projObj["repo"]?.stringValue) {
                repoDisplay = fallbackRepo
                    .replacingOccurrences(of: "https://github.com/", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }
        let cloudSlug = repoDisplay ?? name
        let workspaceUri = "cloud://\(cloudSlug)"
        return ProjectWorkspace(
            id: pid,
            name: name,
            pathDisplay: workspaceUri,
            workspaceUri: workspaceUri,
            runtime: .cloud,
            hostName: "Antigravity",
            activeBranch: "main",
            cloudProjectId: pid,
            originInstanceUuid: originInstanceUuid
        )
    }

    /// Queries connected GitHub repositories available to Antigravity Cloud (`ListAvailableResources`).
    public func fetchCloudGitHubRepos() async -> [GitHubRepoItem] {
        guard let resp = try? await callUnaryJSON(
            method: "ListAvailableResources",
            body: [
                "backend": .string("BACKEND_TYPE_REMOTE_AICODE"),
                "type": .string("github")
            ],
            timeoutInterval: 8.0
        ),
        let resources = resp["resources"]?.arrayValue else {
            return []
        }
        return resources.compactMap { entry -> GitHubRepoItem? in
            guard let obj = entry.objectValue else { return nil }
            guard let fullName = Self.nonEmptyString(obj["displayName"]?.stringValue)
                ?? Self.nonEmptyString(obj["name"]?.stringValue) else {
                return nil
            }
            let branch = Self.nonEmptyString(obj["defaultBranch"]?.stringValue) ?? "main"
            return GitHubRepoItem(
                id: "repo-\(fullName)",
                fullName: fullName,
                visibilityLabel: obj["isPrivate"]?.boolValue == true ? "Private" : "GitHub",
                defaultBranch: branch
            )
        }
    }

    private actor JetboxSnapshotAccumulator {
        private var byId: [String: CascadeSummary] = [:]
        private var finished: Bool = false
        private var recordedError: Error? = nil

        func merge(_ items: [CascadeSummary], cloudProjectsById: [String: ProjectWorkspace]) {
            for item in items {
                AntigravityRPCClient.mergeSummaryEntry(item, into: &byId, cloudProjectsById: cloudProjectsById)
            }
        }

        func markFinished(error: Error? = nil) {
            finished = true
            if let error, recordedError == nil {
                recordedError = error
            }
        }

        func status() -> (hasEntries: Bool, isFinished: Bool, error: Error?) {
            (!byId.isEmpty, finished, recordedError)
        }

        func values() -> [CascadeSummary] {
            Array(byId.values)
        }
    }

    /// Unary Cloud companion query (`GetAllCascadeTrajectories` with `BACKEND_TYPE_REMOTE_AICODE`).
    /// Never silently strips `backend` so local-only trajectories cannot leak into Cloud results.
    private func getAllCascadeTrajectoriesCloud(
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async -> [CascadeSummary] {
        let candidatePayloads: [[String: JSONValue]] = [
            ["backend": .string("BACKEND_TYPE_REMOTE_AICODE")],
            ["backendType": .string("BACKEND_TYPE_REMOTE_AICODE")]
        ]
        let cloudProjectsSnapshot = self.cachedCloudProjectsById
        let allCloudProjects = Array(cloudProjectsSnapshot.values)
        let effectiveUuid = instanceUuidOverride ?? resolvedInstanceUuid

        for (idx, payload) in candidatePayloads.enumerated() {
            do {
                let res: [String: JSONValue]
                if channel == .cloudRelay {
                    res = try await callCloudRelayUnaryJSON(
                        method: "GetAllCascadeTrajectories",
                        body: payload,
                        instanceUuidOverride: instanceUuidOverride,
                        timeoutInterval: timeoutInterval ?? 8.0,
                        allowStripUnknownFields: false
                    )
                } else {
                    res = try await callUnaryJSON(
                        method: "GetAllCascadeTrajectories",
                        body: payload,
                        instanceUuidOverride: instanceUuidOverride,
                        timeoutInterval: timeoutInterval ?? 4.0
                    )
                }
                let decoded = Self.decodeJetboxSummariesEvent(
                    res,
                    forceCloud: true,
                    originInstanceUuid: effectiveUuid,
                    originHostName: "Antigravity",
                    cloudProjectsById: cloudProjectsSnapshot
                ).upserts.map { item -> CascadeSummary in
                    var copy = item
                    if let cp = Self.matchCloudProject(for: copy, cloudProjects: allCloudProjects) {
                        copy.isCloud = true
                        copy.cloudProjectId = cp.cloudProjectId ?? cp.id
                        copy.projectSlug = cp.name
                        copy.workspaceUri = cp.workspaceUri
                        copy.originHostName = "Antigravity"
                    }
                    return copy
                }
                return decoded
            } catch let AntigravityRPCError.httpError(_, body) {
                if idx == 0 && body.lowercased().contains("unknown field \"backend\"") {
                    continue
                }
                return []
            } catch {
                return []
            }
        }
        return []
    }

    private func readJetboxSnapshotOnce(
        requestPayload: [String: JSONValue],
        cloud: Bool,
        instanceUuidOverride: String?,
        originHostName: String?,
        snapshotTimeout: TimeInterval,
        cloudProjectsSnapshot: [String: ProjectWorkspace],
        allowCrossInstanceFailover: Bool = true
    ) async throws -> [CascadeSummary] {
        let stream = try subscribeEnvelopeStream(
            method: "JetboxSubscribeToSummaries",
            requestPayload: requestPayload,
            instanceUuidOverride: instanceUuidOverride,
            allowCrossInstanceFailover: allowCrossInstanceFailover
        )
        let accumulator = JetboxSnapshotAccumulator()
        let readerTask = Task {
            do {
                for try await event in stream {
                    let parsed = Self.decodeJetboxSummariesEvent(
                        event,
                        forceCloud: cloud,
                        originInstanceUuid: instanceUuidOverride,
                        originHostName: originHostName,
                        cloudProjectsById: cloudProjectsSnapshot
                    )
                    if !parsed.upserts.isEmpty {
                        await accumulator.merge(parsed.upserts, cloudProjectsById: cloudProjectsSnapshot)
                    }
                }
                await accumulator.markFinished()
            } catch {
                await accumulator.markFinished(error: error)
            }
        }
        defer { readerTask.cancel() }

        let deadline = Date().addingTimeInterval(max(0.5, snapshotTimeout))
        while Date() < deadline {
            let st = await accumulator.status()
            if st.hasEntries {
                // Allow a brief settle window so any back-to-back initial snapshot frames arrive together
                let remaining = deadline.timeIntervalSinceNow
                if !st.isFinished && remaining > 0.05 {
                    let settleSeconds = min(0.22, remaining)
                    try? await Task.sleep(nanoseconds: UInt64(settleSeconds * 1_000_000_000))
                }
                return await accumulator.values()
            }
            if st.isFinished {
                if let err = st.error {
                    throw err
                }
                return await accumulator.values()
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return await accumulator.values()
    }

    /// Reads the initial snapshot frame(s) emitted by `JetboxSubscribeToSummaries` (either local or `BACKEND_TYPE_REMOTE_AICODE` Cloud),
    /// skipping empty initial ack frames and retrying `backendType` if the server rejects `"backend"`, then closes the temporary stream.
    public func fetchJetboxSummariesSnapshot(
        cloud: Bool,
        instanceUuidOverride: String? = nil,
        originHostName: String? = nil,
        snapshotTimeout: TimeInterval = 4.0,
        allowCrossInstanceFailover: Bool = true
    ) async -> [CascadeSummary] {
        let cloudProjectsSnapshot = self.cachedCloudProjectsById
        let primaryPayload: [String: JSONValue] = cloud
            ? ["backend": .string("BACKEND_TYPE_REMOTE_AICODE")]
            : [:]
        do {
            let primary = try await readJetboxSnapshotOnce(
                requestPayload: primaryPayload,
                cloud: cloud,
                instanceUuidOverride: instanceUuidOverride,
                originHostName: originHostName,
                snapshotTimeout: snapshotTimeout,
                cloudProjectsSnapshot: cloudProjectsSnapshot,
                allowCrossInstanceFailover: allowCrossInstanceFailover
            )
            if !primary.isEmpty || !cloud {
                return primary
            }
        } catch let AntigravityRPCError.httpError(_, body) where cloud && body.lowercased().contains("unknown field \"backend\"") {
            if let fallback = try? await readJetboxSnapshotOnce(
                requestPayload: ["backendType": .string("BACKEND_TYPE_REMOTE_AICODE")],
                cloud: true,
                instanceUuidOverride: instanceUuidOverride,
                originHostName: originHostName,
                snapshotTimeout: snapshotTimeout,
                cloudProjectsSnapshot: cloudProjectsSnapshot,
                allowCrossInstanceFailover: allowCrossInstanceFailover
            ) {
                return fallback
            }
        } catch {
            return []
        }
        return []
    }

    /// Decodes a `JetboxSubscribeToSummariesResponse` (`updates` map + `deletes` array, `trajectorySummaries` map, or mock `summaries` array).
    public static func decodeJetboxSummariesEvent(
        _ event: [String: JSONValue],
        forceCloud: Bool = false,
        originInstanceUuid: String? = nil,
        originHostName: String? = nil,
        cloudProjectsById: [String: ProjectWorkspace] = [:]
    ) -> (upserts: [CascadeSummary], deletes: [String]) {
        let now = Date()
        var upserts: [CascadeSummary] = []
        let deletes = event["deletes"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let allCloudProjects = Array(cloudProjectsById.values)

        func finalizeDecodedSummary(_ rawSummary: CascadeSummary) -> CascadeSummary? {
            var summary = rawSummary
            if forceCloud {
                // Ignore local `file://` workspaces echoed by older/mock servers that do not filter by `backend`,
                // while keeping Cloud `No Project` sessions (`summary.workspaceUri.isEmpty`).
                if !summary.workspaceUri.isEmpty
                    && !AntigravityCloudDetector.isPlaygroundScratchURI(summary.workspaceUri)
                    && !summary.isCloud
                    && (summary.cloudProjectId ?? "").isEmpty {
                    return nil
                }
                summary.isCloud = true
                summary.originHostName = "Antigravity"
            } else if !summary.isCloud {
                summary.originHostName = originHostName
            }
            summary.originInstanceUuid = originInstanceUuid
            if let cp = Self.matchCloudProject(for: summary, cloudProjects: allCloudProjects) {
                summary.isCloud = true
                summary.cloudProjectId = cp.cloudProjectId ?? cp.id
                summary.projectSlug = cp.name
                summary.workspaceUri = cp.workspaceUri
                summary.originHostName = "Antigravity"
            }
            return summary
        }

        if let updatesMap = event["updates"]?.objectValue ?? event["trajectorySummaries"]?.objectValue {
            for (cid, val) in updatesMap {
                if let obj = val.objectValue,
                   obj["killed"]?.boolValue == true,
                   (obj["status"]?.stringValue ?? "").contains("UNSPECIFIED") {
                    continue
                }
                if let decoded = Self.decodeTrajectorySummaryEntry(
                    cascadeId: cid,
                    value: val,
                    now: now,
                    forceCloud: forceCloud
                ), let finalized = finalizeDecodedSummary(decoded) {
                    upserts.append(finalized)
                }
            }
        } else if let summariesArr = event["summaries"]?.arrayValue ?? event["trajectories"]?.arrayValue {
            for val in summariesArr {
                guard let cid = val.objectValue?["cascadeId"]?.stringValue else { continue }
                if let decoded = Self.decodeTrajectorySummaryEntry(
                    cascadeId: cid,
                    value: val,
                    now: now,
                    forceCloud: forceCloud
                ), let finalized = finalizeDecodedSummary(decoded) {
                    upserts.append(finalized)
                }
            }
        }
        return (upserts, deletes)
    }

    private static func extractUnknownProtoFieldName(from message: String) -> String? {
        guard let markerRange = message.range(of: "unknown field \"") else { return nil }
        let rest = message[markerRange.upperBound...]
        guard let endQuote = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<endQuote])
    }

    /// Wakes a dormant disk trajectory into `language_server` memory (`LoadTrajectory`).
    public func loadTrajectory(
        cascadeId: String,
        isCloud: Bool = false,
        instanceUuidOverride: String? = nil
    ) async throws {
        let isRemoteCloud = isCloud || cascadeId.hasPrefix("v1/")
        var body: [String: JSONValue] = ["cascadeId": .string(cascadeId)]
        if isRemoteCloud {
            body["backend"] = .string("BACKEND_TYPE_REMOTE_AICODE")
        }
        _ = try await callUnaryJSON(
            method: "LoadTrajectory",
            body: body,
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 8.0
        )
    }

    /// Fetches trajectory steps, automatically switching from JSON (`0..<600`) to Binary Protobuf (`>=600`).
    public func fetchTrajectorySteps(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = 200,
        instanceUuidOverride: String? = nil
    ) async throws -> [CascadeStep] {
        if endIndex >= Self.protobufStepThreshold {
            return try await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: startIndex,
                endIndex: endIndex,
                instanceUuidOverride: instanceUuidOverride
            )
        }
        return try await fetchTrajectoryStepsJSON(
            cascadeId: cascadeId,
            startIndex: startIndex,
            endIndex: endIndex,
            instanceUuidOverride: instanceUuidOverride
        )
    }

    /// Fetches the complete trajectory for a live or historical session using upstream `GetCascadeTrajectorySteps`,
    /// waking dormant trajectories via `LoadTrajectory`, falling back to `GetCascadeTrajectory` / Binary Protobuf,
    /// and failing over across reachable Cloud Relay instances when a conversation lives in a peer window.
    public func fetchAllTrajectorySteps(
        cascadeId: String,
        knownStepCount: Int = 0,
        isCloud: Bool = false,
        instanceUuidOverride: String? = nil
    ) async throws -> [CascadeStep] {
        let primaryTarget: String? = {
            if channel == .cloudRelay {
                return selectReachableRelayUuid(preferred: instanceUuidOverride)
            }
            return instanceUuidOverride
        }()

        var primaryError: Error? = nil
        do {
            let steps = try await fetchStepsFromSingleInstance(
                cascadeId: cascadeId,
                knownStepCount: knownStepCount,
                isCloud: isCloud,
                targetUuid: primaryTarget
            )
            if !steps.isEmpty {
                return steps
            }
        } catch let AntigravityRPCError.unauthorized(msg) {
            throw AntigravityRPCError.unauthorized(msg)
        } catch {
            primaryError = error
        }

        // Multi-window Cloud Relay failover: if the trajectory was opened or stored in another live Desktop window,
        // probe reachable peer instances (`sameHostFamily` windows on the same Mac first).
        if channel == .cloudRelay {
            if cachedRelayInstances.isEmpty,
               let refreshed = try? await listRelayInstances(timeoutInterval: 6.0),
               !refreshed.isEmpty {
                self.cachedRelayInstances = refreshed
            }
            let familySeed = cachedRelayInstances.first(where: { $0.uuid == primaryTarget })?.name ?? targetInstanceIdentifier
            let peerCandidates = cachedRelayInstances
                .filter { $0.status.isReachable && $0.uuid != primaryTarget }
                .sorted { lhs, rhs in
                    let lFam = lhs.sameHostFamily(as: familySeed)
                    let rFam = rhs.sameHostFamily(as: familySeed)
                    if lFam != rFam { return lFam && !rFam }
                    return false
                }

            for peer in peerCandidates {
                do {
                    let peerSteps = try await fetchStepsFromSingleInstance(
                        cascadeId: cascadeId,
                        knownStepCount: knownStepCount,
                        isCloud: isCloud,
                        targetUuid: peer.uuid
                    )
                    if !peerSteps.isEmpty {
                        self.resolvedInstanceUuid = peer.uuid
                        return peerSteps
                    }
                } catch let AntigravityRPCError.unauthorized(msg) {
                    throw AntigravityRPCError.unauthorized(msg)
                } catch {
                    if primaryError == nil {
                        primaryError = error
                    }
                }
            }
        }

        if let primaryError {
            throw primaryError
        }
        return []
    }

    private func fetchStepsFromSingleInstance(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        targetUuid: String?
    ) async throws -> [CascadeStep] {
        let isRemoteCloud = isCloud || cascadeId.hasPrefix("v1/")
        let wakeKey = "\(targetUuid ?? "direct")|\(cascadeId)"
        var lastError: Error? = nil

        if knownStepCount >= Self.protobufStepThreshold {
            do {
                let protoSteps = try await fetchTrajectoryStepsProtobuf(
                    cascadeId: cascadeId,
                    startIndex: 0,
                    endIndex: knownStepCount,
                    instanceUuidOverride: targetUuid
                )
                if !protoSteps.isEmpty {
                    wokenInstanceCascadeKeys.insert(wakeKey)
                    return protoSteps
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                lastError = error
            }
            try? await loadTrajectory(cascadeId: cascadeId, isCloud: isRemoteCloud, instanceUuidOverride: targetUuid)
            let retryProtoSteps = try await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: knownStepCount,
                instanceUuidOverride: targetUuid
            )
            if !retryProtoSteps.isEmpty {
                wokenInstanceCascadeKeys.insert(wakeKey)
            }
            return retryProtoSteps
        }

        var stepReqBody: [String: JSONValue] = ["cascadeId": .string(cascadeId)]
        if isRemoteCloud {
            stepReqBody["backend"] = .string("BACKEND_TYPE_REMOTE_AICODE")
        }

        var firstResp: [String: JSONValue]? = nil
        do {
            firstResp = try await callUnaryJSON(
                method: "GetCascadeTrajectorySteps",
                body: stepReqBody,
                instanceUuidOverride: targetUuid,
                timeoutInterval: 10.0
            )
            lastError = nil
        } catch let AntigravityRPCError.unauthorized(msg) {
            throw AntigravityRPCError.unauthorized(msg)
        } catch {
            lastError = error
            firstResp = nil
        }

        if let resp = firstResp, resp["truncatedAt"] != nil {
            let protoSteps = try await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: max(knownStepCount, Self.protobufStepThreshold),
                instanceUuidOverride: targetUuid
            )
            if !protoSteps.isEmpty {
                wokenInstanceCascadeKeys.insert(wakeKey)
            }
            return protoSteps
        }

        var rawSteps = firstResp?["steps"]?.arrayValue ?? []
        if !rawSteps.isEmpty {
            wokenInstanceCascadeKeys.insert(wakeKey)
        } else if firstResp == nil || knownStepCount > 0 || !wokenInstanceCascadeKeys.contains(wakeKey) {
            try? await loadTrajectory(cascadeId: cascadeId, isCloud: isRemoteCloud, instanceUuidOverride: targetUuid)
            do {
                let retryResp = try await callUnaryJSON(
                    method: "GetCascadeTrajectorySteps",
                    body: stepReqBody,
                    instanceUuidOverride: targetUuid,
                    timeoutInterval: 10.0
                )
                lastError = nil
                if retryResp["truncatedAt"] != nil {
                    let protoSteps = try await fetchTrajectoryStepsProtobuf(
                        cascadeId: cascadeId,
                        startIndex: 0,
                        endIndex: max(knownStepCount, Self.protobufStepThreshold),
                        instanceUuidOverride: targetUuid
                    )
                    if !protoSteps.isEmpty {
                        wokenInstanceCascadeKeys.insert(wakeKey)
                    }
                    return protoSteps
                }
                rawSteps = retryResp["steps"]?.arrayValue ?? []
                if !rawSteps.isEmpty {
                    wokenInstanceCascadeKeys.insert(wakeKey)
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                lastError = error
            }
        }

        // Fallback A: Query `GetCascadeTrajectory` (`{"trajectory": {"steps": [...]}}`) when `GetCascadeTrajectorySteps` returns empty
        if rawSteps.isEmpty && !wokenInstanceCascadeKeys.contains(wakeKey) {
            do {
                let trajResp = try await callUnaryJSON(
                    method: "GetCascadeTrajectory",
                    body: stepReqBody,
                    instanceUuidOverride: targetUuid,
                    timeoutInterval: 10.0
                )
                let fallbackArr = trajResp["trajectory"]?.objectValue?["steps"]?.arrayValue
                    ?? trajResp["steps"]?.arrayValue
                    ?? []
                if !fallbackArr.isEmpty {
                    rawSteps = fallbackArr
                    lastError = nil
                    wokenInstanceCascadeKeys.insert(wakeKey)
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                if lastError == nil { lastError = error }
            }
        }

        // Fallback B: Binary Protobuf (`application/proto`) when a >600-step dormant session omitted `stepCount` in summaries
        if rawSteps.isEmpty && (firstResp == nil || lastError != nil || knownStepCount > 0) {
            if let protoFallback = try? await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: max(knownStepCount, Self.protobufStepThreshold),
                instanceUuidOverride: targetUuid
            ), !protoFallback.isEmpty {
                wokenInstanceCascadeKeys.insert(wakeKey)
                return protoFallback
            }
        }

        if rawSteps.isEmpty, let lastError {
            throw lastError
        }

        if rawSteps.count >= 590 {
            if let protoSteps = try? await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: max(knownStepCount, rawSteps.count),
                instanceUuidOverride: targetUuid
            ), protoSteps.count >= rawSteps.count {
                wokenInstanceCascadeKeys.insert(wakeKey)
                return protoSteps
            }
        }

        var seenIndices = Set<Int>()
        var collected: [CascadeStep] = []
        for (idxOffset, item) in rawSteps.enumerated() {
            if let step = Self.decodeJSONStep(item, cascadeId: cascadeId, fallbackIndex: idxOffset) {
                if seenIndices.insert(step.stepIndex).inserted {
                    collected.append(step)
                }
            }
        }

        var offset = rawSteps.count
        while offset > 0 && offset < knownStepCount && offset < Self.protobufStepThreshold {
            var pageBody = stepReqBody
            pageBody["stepOffset"] = .int(offset)
            let pageResp = try await callUnaryJSON(
                method: "GetCascadeTrajectorySteps",
                body: pageBody,
                instanceUuidOverride: targetUuid
            )
            guard let pageSteps = pageResp["steps"]?.arrayValue, !pageSteps.isEmpty else {
                break
            }
            var addedNew = false
            for (idxOffset, item) in pageSteps.enumerated() {
                if let step = Self.decodeJSONStep(item, cascadeId: cascadeId, fallbackIndex: offset + idxOffset) {
                    if seenIndices.insert(step.stepIndex).inserted {
                        collected.append(step)
                        addedNew = true
                    }
                }
            }
            if !addedNew {
                break
            }
            offset += pageSteps.count
        }

        return collected.sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Fetches trajectory steps over JSON (`GetCascadeTrajectorySteps`) for conversations under 600 steps.
    /// Supports both native Desktop `language_server` step JSON (`stepOffset`) and companion/mock step schemas.
    public func fetchTrajectoryStepsJSON(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = 200,
        instanceUuidOverride: String? = nil
    ) async throws -> [CascadeStep] {
        var body: [String: JSONValue] = ["cascadeId": .string(cascadeId)]
        if startIndex > 0 {
            body["stepOffset"] = .int(startIndex)
        }
        let res = try await callUnaryJSON(
            method: "GetCascadeTrajectorySteps",
            body: body,
            instanceUuidOverride: instanceUuidOverride
        )
        if res["truncatedAt"] != nil {
            return try await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: startIndex,
                endIndex: max(endIndex, Self.protobufStepThreshold),
                instanceUuidOverride: instanceUuidOverride
            )
        }
        guard let rawSteps = res["steps"]?.arrayValue else { return [] }
        return rawSteps.enumerated().compactMap { offset, item in
            Self.decodeJSONStep(item, cascadeId: cascadeId, fallbackIndex: startIndex + offset)
        }
    }

    /// Fetches trajectory steps using binary Protobuf (`application/proto`) to bypass the 600-step JSON ceiling.
    public func fetchTrajectoryStepsProtobuf(
        cascadeId: String,
        startIndex: Int,
        endIndex: Int,
        instanceUuidOverride: String? = nil
    ) async throws -> [CascadeStep] {
        let protoReqBytes = ProtobufStepCodec.encodeGetStepsRequest(
            cascadeId: cascadeId,
            startIndex: startIndex,
            endIndex: endIndex
        )
        if channel == .cloudRelay {
            let (rawBytes, _) = try await callCloudRelayProxyCommand(
                method: "GetCascadeTrajectorySteps",
                payload: protoReqBytes,
                contentType: "application/proto",
                instanceUuidOverride: instanceUuidOverride
            )
            let unwrapped = Self.unwrapConnectFramedPayloadIfNeeded(rawBytes)
            return ProtobufStepCodec.decodeStepsResponse(unwrapped, cascadeId: cascadeId)
        }

        let url = endpointURL.appendingPathComponent("\(Self.servicePrefix)/GetCascadeTrajectorySteps")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/proto", forHTTPHeaderField: "Content-Type")
        request.setValue("application/proto", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        applyAuthHeaders(to: &request)
        request.httpBody = protoReqBytes

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AntigravityRPCError.httpError(statusCode: status, body: "Binary step fetch failed")
        }
        let unwrapped = Self.unwrapConnectFramedPayloadIfNeeded(data)
        return ProtobufStepCodec.decodeStepsResponse(unwrapped, cascadeId: cascadeId)
    }

    // MARK: - Workspace & Project Operations (`UE01`, `UE04`, `UE05`)

    public func getWorkspaceInfos(
        instanceUuidOverride: String? = nil,
        originHostName: String? = nil,
        timeoutInterval: TimeInterval? = nil,
        allowCrossInstanceFailover: Bool = true
    ) async throws -> [WorkspaceInfo] {
        let res = try await callUnaryJSON(
            method: "GetWorkspaceInfos",
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: timeoutInterval,
            allowCrossInstanceFailover: allowCrossInstanceFailover
        )
        let items = res["workspaces"]?.arrayValue ?? res["workspaceInfos"]?.arrayValue ?? []
        return items.compactMap { item -> WorkspaceInfo? in
            guard let obj = item.objectValue else { return nil }
            guard let rawUri = obj["workspaceUri"]?.stringValue
                ?? obj["workspaceFolderAbsoluteUri"]?.stringValue else { return nil }
            if AntigravityCloudDetector.isGenericContainerURI(rawUri)
                || AntigravityCloudDetector.isPlaygroundScratchURI(rawUri) {
                return nil
            }
            let sourceHint = [obj["runtime"]?.stringValue, obj["source"]?.stringValue]
                .compactMap { $0 }
                .joined(separator: " ")
            let isCloud = (obj["isCloud"]?.boolValue ?? false)
                || AntigravityCloudDetector.isCloudWorkspaceURI(rawUri, sourceHint: sourceHint)
            let uri = AntigravityCloudDetector.normalizeWorkspaceURI(rawUri, isCloud: isCloud)
            guard !uri.isEmpty else { return nil }
            let fallbackName: String
            if uri.hasPrefix("cloud://") {
                let tail = uri.replacingOccurrences(of: "cloud://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                fallbackName = (tail as NSString).lastPathComponent.isEmpty ? tail : (tail as NSString).lastPathComponent
            } else if uri.contains("://"), let parsedURL = URL(string: uri), !parsedURL.lastPathComponent.isEmpty {
                fallbackName = parsedURL.lastPathComponent
            } else {
                fallbackName = (uri.replacingOccurrences(of: "file://", with: "") as NSString).lastPathComponent
            }
            let name = obj["displayName"]?.stringValue ?? fallbackName
            guard !AntigravityCloudDetector.isNoProjectSlug(name) else { return nil }
            let branch = obj["activeBranch"]?.stringValue ?? obj["gitBranch"]?.stringValue ?? "main"
            let files = obj["indexedFiles"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return WorkspaceInfo(
                workspaceUri: uri,
                displayName: name,
                activeBranch: branch,
                indexedFiles: files,
                isCloud: isCloud,
                originInstanceUuid: instanceUuidOverride ?? resolvedInstanceUuid,
                originHostName: isCloud ? "Antigravity" : originHostName
            )
        }
    }

    public func createProjectWorkspace(draft: NewProjectDraft) async throws -> ProjectWorkspace {
        let repoName = draft.selectedRepo?.fullName ?? draft.projectName
        if channel == .cloudRelay && draft.runsOn == .cloud {
            let newProjectId = UUID().uuidString.lowercased()
            var projectObj: [String: JSONValue] = [
                "id": .string(newProjectId),
                "name": .string(draft.projectName),
                "backendType": .string("BACKEND_TYPE_REMOTE_AICODE")
            ]
            var resourceEntries: [JSONValue] = []
            if let repo = draft.selectedRepo {
                resourceEntries.append(
                    .object([
                        "remoteResource": .object([
                            "type": .string("github"),
                            "name": .string(repo.fullName),
                            "displayName": .string(repo.fullName)
                        ])
                    ])
                )
            }
            for link in draft.driveResourceLinks where !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resourceEntries.append(
                    .object([
                        "remoteResource": .object([
                            "type": .string("google_drive"),
                            "name": .string(link),
                            "displayName": .string(link)
                        ])
                    ])
                )
            }
            if !resourceEntries.isEmpty {
                projectObj["projectResources"] = .object(["resources": .array(resourceEntries)])
            }
            if !draft.envSetupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                projectObj["envSetupScript"] = .string(draft.envSetupScript)
            }
            let res = try await callUnaryJSON(
                method: "CreateProject",
                body: [
                    "backend": .string("BACKEND_TYPE_REMOTE_AICODE"),
                    "project": .object(projectObj)
                ]
            )
            let returnedProj = res["project"]?.objectValue
            let finalId = Self.nonEmptyString(returnedProj?["id"]?.stringValue) ?? newProjectId
            let finalName = Self.nonEmptyString(returnedProj?["name"]?.stringValue) ?? draft.projectName
            let cloudUri = "cloud://\(repoName)"
            let created = ProjectWorkspace(
                id: finalId,
                name: finalName,
                pathDisplay: cloudUri,
                workspaceUri: cloudUri,
                runtime: .cloud,
                hostName: "Antigravity",
                activeBranch: draft.selectedRepo?.defaultBranch ?? "main",
                cloudProjectId: finalId,
                originInstanceUuid: resolvedInstanceUuid
            )
            cachedCloudProjectsById[finalId] = created
            return created
        }

        var body: [String: JSONValue] = [
            "name": .string(draft.projectName),
            "runtime": .string(draft.runsOn.rawValue),
            "source": .string(draft.source.rawValue),
            "repository": .string(repoName),
            "branchWorktree": .string(draft.branchWorktree)
        ]
        if !draft.driveResourceLinks.isEmpty {
            body["googleDriveLinks"] = .array(draft.driveResourceLinks.map(JSONValue.string))
        }
        if !draft.uploadedFilePaths.isEmpty {
            body["uploadedFilePaths"] = .array(draft.uploadedFilePaths.map(JSONValue.string))
        }
        if !draft.envSetupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["envSetupScript"] = .string(draft.envSetupScript)
        }
        let res = try await callUnaryJSON(
            method: "CreateProjectWorkspace",
            body: body
        )
        let workspaceUri = res["workspaceUri"]?.stringValue
            ?? (draft.runsOn == .cloud ? "cloud://\(repoName)" : "file:///Users/wl/code/\(draft.projectName)")
        return ProjectWorkspace(
            id: draft.projectName,
            name: draft.projectName,
            pathDisplay: draft.runsOn == .cloud ? "cloud://\(repoName)" : "~/code/\(draft.projectName)",
            workspaceUri: workspaceUri,
            runtime: draft.runsOn,
            hostName: draft.runsOn == .cloud ? "Antigravity" : draft.runsOn.rawValue,
            activeBranch: draft.selectedRepo?.defaultBranch ?? "main"
        )
    }

    public func openWorkspaceInFinder(workspaceUri: String) async throws {
        _ = try await callUnaryJSON(
            method: "OpenWorkspaceInFinder",
            body: ["workspaceUri": .string(workspaceUri)]
        )
    }

    // MARK: - Conversation & Trajectory Operations (`UE01`, `UE03`, `UE07`)

    /// Fetches all sessions from either Desktop `language_server` (`trajectorySummaries` map)
    /// or Companion/Mock (`trajectories` array).
    public func getAllCascadeTrajectories(
        instanceUuidOverride: String? = nil,
        originHostName: String? = nil,
        timeoutInterval: TimeInterval? = nil,
        allowCrossInstanceFailover: Bool = true
    ) async throws -> [CascadeSummary] {
        let res = try await callUnaryJSON(
            method: "GetAllCascadeTrajectories",
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: timeoutInterval,
            allowCrossInstanceFailover: allowCrossInstanceFailover
        )
        let now = Date()
        let allCloudProjects = Array(self.cachedCloudProjectsById.values)
        let effectiveUuid = instanceUuidOverride ?? resolvedInstanceUuid

        // Format A: Native Desktop `language_server` map `{"trajectorySummaries": {"<cascadeId>": {...}}}`
        if let summaryMap = res["trajectorySummaries"]?.objectValue {
            let decoded = summaryMap.compactMap { cascadeId, value -> CascadeSummary? in
                guard var s = Self.decodeTrajectorySummaryEntry(cascadeId: cascadeId, value: value, now: now) else {
                    return nil
                }
                s.originInstanceUuid = effectiveUuid
                s.originHostName = s.isCloud ? "Antigravity" : originHostName
                if let cp = Self.matchCloudProject(for: s, cloudProjects: allCloudProjects) {
                    s.isCloud = true
                    s.cloudProjectId = cp.cloudProjectId ?? cp.id
                    s.projectSlug = cp.name
                    s.workspaceUri = cp.workspaceUri
                    s.originHostName = "Antigravity"
                }
                return s
            }
            return decoded.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.cascadeId < rhs.cascadeId
            }
        }

        // Format B: Array `{"trajectories": [...]}`
        guard let list = res["trajectories"]?.arrayValue else { return [] }
        return list.compactMap { item -> CascadeSummary? in
            guard let obj = item.objectValue,
                  let id = obj["cascadeId"]?.stringValue,
                  let title = obj["title"]?.stringValue else { return nil }
            let rawUri = (obj["workspaceUri"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceHint = [obj["runtime"]?.stringValue, obj["source"]?.stringValue]
                .compactMap { $0 }
                .joined(separator: " ")
            let isCloud = (obj["isCloud"]?.boolValue ?? false)
                || (obj["cloud"]?.boolValue ?? false)
                || AntigravityCloudDetector.isCloudWorkspaceURI(rawUri, cascadeId: id, sourceHint: sourceHint)
            let isUnassigned = rawUri.isEmpty
                || AntigravityCloudDetector.isGenericContainerURI(rawUri)
                || AntigravityCloudDetector.isPlaygroundScratchURI(rawUri)
            let uri = isUnassigned
                ? (AntigravityCloudDetector.isPlaygroundScratchURI(rawUri) ? rawUri : "")
                : AntigravityCloudDetector.normalizeWorkspaceURI(rawUri, isCloud: isCloud)
            let explicitSlug = obj["projectSlug"]?.stringValue ?? obj["project"]?.stringValue
            let slug: String
            if let explicitSlug, !AntigravityCloudDetector.isNoProjectSlug(explicitSlug) {
                slug = explicitSlug
            } else if isUnassigned {
                slug = AntigravityCloudDetector.noProjectDisplayName
            } else {
                slug = (rawUri as NSString).lastPathComponent
            }
            let statusName = obj["status"]?.stringValue ?? "CORTEX_STEP_STATUS_DONE"
            let stepCount = obj["stepCount"]?.intValue ?? 0
            let branch = isUnassigned ? "" : (obj["branchName"]?.stringValue ?? "main")
            let subtitle = obj["statusSubtitle"]?.stringValue ?? ""
            let updatedAt = Self.parseProtoTimestamp(obj["updatedAt"] ?? obj["lastModifiedTime"]) ?? now
            let relativeLabel = obj["relativeTimeLabel"]?.stringValue ?? Self.formatRelativeTimeLabel(from: updatedAt, now: now)
            return CascadeSummary(
                cascadeId: id,
                title: title,
                projectSlug: slug,
                workspaceUri: uri,
                branchName: branch,
                status: CortexStepStatus.from(jsonName: statusName),
                stepCount: stepCount,
                updatedAt: updatedAt,
                relativeTimeLabel: relativeLabel,
                statusSubtitle: subtitle,
                isPinned: obj["isPinned"]?.boolValue ?? false,
                isArchived: obj["isArchived"]?.boolValue ?? false,
                isUnread: obj["isUnread"]?.boolValue ?? false,
                isCloud: isCloud,
                originInstanceUuid: effectiveUuid,
                originHostName: isCloud ? "Antigravity" : originHostName
            )
        }
    }

    public static func normalizeProtoModelEnum(_ modelId: String) -> String {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("MODEL_") {
            return trimmed
        }
        let lower = trimmed.lowercased()
        if lower.contains("orchestrator") {
            if lower.contains("carbon") { return "MODEL_ORCHESTRATOR_CARBON" }
            if lower.contains("argon") { return "MODEL_ORCHESTRATOR_ARGON" }
            return "MODEL_ORCHESTRATOR_NEON"
        }
        if lower.contains("neon") { return "MODEL_GOOGLE_GEMINI_4_NEON" }
        if lower.contains("carbon") { return "MODEL_GOOGLE_GEMINI_4_CARBON" }
        if lower.contains("argon") { return "MODEL_GOOGLE_GEMINI_4_ARGON" }
        if lower.contains("hydrogen") { return "MODEL_GOOGLE_GEMINI_4_HYDROGEN" }
        if lower.contains("flash") {
            return "MODEL_PLACEHOLDER_M18"
        }
        if lower.contains("sonnet") {
            return "MODEL_PLACEHOLDER_M35"
        }
        if lower.contains("opus") {
            return "MODEL_PLACEHOLDER_M26"
        }
        if lower.contains("low") {
            return "MODEL_PLACEHOLDER_M36"
        }
        if lower.contains("gemini") || lower.contains("pro") {
            return "MODEL_PLACEHOLDER_M37"
        }
        return "MODEL_PLACEHOLDER_M37"
    }

    /// Creates a new Cascade session (`StartCascade`) on either Local or Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`),
    /// supporting both project-bound workspaces and unassigned `No Project` sessions.
    public func startCascade(
        workspaceUri: String,
        initialPrompt: String = "",
        modelId: String = "MODEL_PLACEHOLDER_M37",
        cloudProjectId: String? = nil,
        isCloud: Bool = false,
        instanceUuidOverride: String? = nil
    ) async throws -> String {
        let protoModel = Self.normalizeProtoModelEnum(modelId)
        let clientCid = UUID().uuidString.lowercased()
        var payload: [String: JSONValue] = [
            "cascadeId": .string(clientCid),
            "metadata": .object([
                "ideName": .string("antigravity-ios"),
                "ideVersion": .string("2.0.0")
            ]),
            "modelId": .string(protoModel)
        ]
        if let cloudProjectId, !cloudProjectId.isEmpty {
            payload["backend"] = .string("BACKEND_TYPE_REMOTE_AICODE")
            payload["projectEnvConfig"] = .object([
                "projectId": .string(cloudProjectId),
                "defaultProjectEnvironment": .object([:])
            ])
        } else if isCloud {
            payload["backend"] = .string("BACKEND_TYPE_REMOTE_AICODE")
        } else if !workspaceUri.isEmpty && !AntigravityCloudDetector.isGenericContainerURI(workspaceUri) {
            payload["workspaceUris"] = .array([.string(workspaceUri)])
        }
        if !initialPrompt.isEmpty {
            payload["initialUserInput"] = .string(initialPrompt)
        }
        let res = try await callUnaryJSON(
            method: "StartCascade",
            body: payload,
            instanceUuidOverride: instanceUuidOverride
        )
        if let returnedId = Self.nonEmptyString(res["cascadeId"]?.stringValue) {
            return returnedId
        }
        return clientCid
    }

    /// Sends a user prompt + rich multimodal/context items + model/mode/effort/permission config (`SendUserCascadeMessage`).
    /// Encodes `Planning` vs `Fast` via `conversational.agenticMode` (`CONVERSATIONAL_PLANNER_MODE_DEFAULT`),
    /// applies the selected `AgentPermissionPreset` via `plannerConfig.toolConfig`,
    /// and sets `planModel` alongside `requestedModel` for Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) sessions.
    public func sendUserCascadeMessage(
        cascadeId: String,
        message: String,
        attachments: [ComposerAttachmentChip] = [],
        modelId: String,
        effort: ThinkingEffortLevel = .high,
        mode: CascadeExecutionMode = .planning,
        agentPersona: String = "Default",
        isModelAlias: Bool = false,
        isCloud: Bool = false,
        permissionPreset: AgentPermissionPreset? = nil,
        instanceUuidOverride: String? = nil
    ) async throws {
        var items: [JSONValue] = [.object(["text": .string(message)])]
        for chip in attachments {
            switch chip.kind {
            case .imageScreenshot, .audioRecording, .videoClip, .pdfDocument, .archiveZip, .genericFile:
                if let b64 = chip.inlineBase64Data, !b64.isEmpty {
                    items.append(
                        .object([
                            "item": .object([
                                "media": .object([
                                    "uri": .string(chip.targetUri),
                                    "label": .string(chip.label),
                                    "mimeType": .string(chip.mimeType ?? "application/octet-stream"),
                                    "inlineBase64Data": .string(b64),
                                    "kind": .string(chip.kind.rawValue)
                                ])
                            ])
                        ])
                    )
                } else {
                    items.append(
                        .object([
                            "item": .object([
                                "file": .object([
                                    "absoluteUri": .string(chip.targetUri),
                                    "label": .string(chip.label)
                                ])
                            ])
                        ])
                    )
                }
            case .codeQuote:
                items.append(
                    .object([
                        "item": .object([
                            "codeQuote": .object([
                                "uri": .string(chip.targetUri),
                                "label": .string(chip.label)
                            ])
                        ])
                    ])
                )
            case .pluginMention, .skill, .conversationMention, .action:
                items.append(
                    .object([
                        "item": .object([
                            "mention": .object([
                                "kind": .string(chip.kind.rawValue),
                                "targetUri": .string(chip.targetUri),
                                "label": .string(chip.label)
                            ])
                        ])
                    ])
                )
            case .fileMention, .folder, .terminalLog:
                items.append(
                    .object([
                        "item": .object([
                            "file": .object([
                                "absoluteUri": .string(chip.targetUri),
                                "label": .string(chip.label)
                            ])
                        ])
                    ])
                )
            }
        }

        let protoModel = Self.normalizeProtoModelEnum(modelId)
        let requestedModelPayload: JSONValue = isModelAlias
            ? .object(["alias": .string(modelId)])
            : .object(["model": .string(protoModel)])

        let effectivePermission: AgentPermissionPreset = {
            if let preset = permissionPreset, preset != .inheritGlobal {
                return preset
            }
            return AgentPermissionPreset.defaultPreset(isRemote: isCloud || cascadeId.hasPrefix("v1/"))
        }()
        var toolConfig: [String: JSONValue] = [
            "code": .object(["allowEditGitignore": .bool(true)]),
            "viewFile": .object(["allowViewGitignore": .bool(true)]),
            "grep": .object(["allowAccessGitignore": .bool(true)])
        ]
        switch effectivePermission {
        case .requestReview:
            toolConfig["runCommand"] = .object([
                "autoCommandConfig": .object([
                    "autoExecutionPolicy": .string("CASCADE_COMMANDS_AUTO_EXECUTION_OFF")
                ])
            ])
            toolConfig["notifyUser"] = .object([
                "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_ALWAYS")
            ])
        case .defaultPolicy, .auto, .inheritGlobal:
            toolConfig["notifyUser"] = .object([
                "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_AUTO")
            ])
        case .turbo:
            toolConfig["runCommand"] = .object([
                "autoCommandConfig": .object([
                    "autoExecutionPolicy": .string("CASCADE_COMMANDS_AUTO_EXECUTION_EAGER")
                ])
            ])
            toolConfig["notifyUser"] = .object([
                "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_TURBO")
            ])
        }

        var plannerConfig: [String: JSONValue] = [
            "conversational": .object([
                "plannerMode": .string("CONVERSATIONAL_PLANNER_MODE_DEFAULT"),
                "agenticMode": .bool(mode == .planning)
            ]),
            "toolConfig": .object(toolConfig),
            "requestedModel": requestedModelPayload,
            "thinkingEffort": .string(effort.protoWireValue)
        ]
        if agentPersona != "Default" && !agentPersona.isEmpty {
            plannerConfig["agentPersona"] = .string(agentPersona)
        }
        plannerConfig["permissionPreset"] = .string(effectivePermission.rawValue)
        if (isCloud || cascadeId.hasPrefix("v1/")) && !isModelAlias && protoModel.hasPrefix("MODEL_") {
            plannerConfig["planModel"] = .string(protoModel)
        }

        let modelCfgObj: [String: JSONValue] = [
            "modelId": .string(modelId),
            "thinkingEffort": .string(effort.protoWireValue),
            "mode": .string(mode.rawValue.uppercased()),
            "agentPersona": .string(agentPersona),
            "permissionPreset": .string(effectivePermission.rawValue)
        ]

        _ = try await callUnaryJSON(
            method: "SendUserCascadeMessage",
            body: [
                "cascadeId": .string(cascadeId),
                "items": .array(items),
                "userResponse": .string(message),
                "metadata": .object([
                    "ideName": .string("antigravity-ios"),
                    "ideVersion": .string("2.33.0")
                ]),
                "cascadeConfig": .object([
                    "plannerConfig": .object(plannerConfig)
                ]),
                "modelConfig": .object(modelCfgObj)
            ],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 300.0
        )
    }

    public func handleCascadeUserInteraction(
        _ payload: CascadeUserInteractionPayload,
        instanceUuidOverride: String? = nil
    ) async throws {
        var interactionObj: [String: JSONValue] = [
            "trajectoryId": .string(payload.cascadeId),
            "stepIndex": .int(payload.stepIndex)
        ]

        if let rc = payload.runCommand {
            interactionObj["runCommand"] = .object([
                "confirm": .bool(rc.confirm),
                "proposedCommandLine": .string(rc.proposedCommandLine),
                "submittedCommandLine": .string(rc.submittedCommandLine),
                "faceIdVerified": .bool(rc.faceIdVerified)
            ])
        } else if let perm = payload.permission {
            interactionObj["permission"] = .object([
                "allow": .bool(perm.allow),
                "scope": .string(perm.scope),
                "turnGrants": .object([
                    "allow": .array(perm.grantPatterns.map(JSONValue.string)),
                    "deny": .array([])
                ])
            ])
        } else if let fp = payload.filePermission {
            var fpObj: [String: JSONValue] = [
                "allow": .bool(fp.allow),
                "scope": .string(fp.scope)
            ]
            if let uri = fp.absolutePathUri, !uri.isEmpty {
                fpObj["absolutePathUri"] = .string(uri)
            }
            interactionObj["filePermission"] = .object(fpObj)
        } else if let qa = payload.askQuestion {
            var qaObj: [String: JSONValue] = [
                "selectedOptions": .array(qa.selectedOptions.map(JSONValue.string))
            ]
            if let custom = qa.customResponse {
                qaObj["customResponse"] = .string(custom)
            }
            interactionObj["askQuestion"] = .object(qaObj)
        } else if let confirm = payload.genericConfirm {
            let memberKey = payload.rawMemberKey ?? payload.kind.rawValue
            if payload.kind == .deploy {
                interactionObj[memberKey] = .object(["cancel": .bool(!confirm)])
            } else {
                var genericObj: [String: JSONValue] = ["confirm": .bool(confirm)]
                if let scope = payload.approvalScope {
                    genericObj["scope"] = .string(scope)
                }
                interactionObj[memberKey] = .object(genericObj)
            }
        }

        do {
            _ = try await callUnaryJSON(
                method: "HandleCascadeUserInteraction",
                body: ["interaction": .object(interactionObj)],
                instanceUuidOverride: instanceUuidOverride
            )
        } catch let AntigravityRPCError.httpError(statusCode, errorBody)
            where statusCode == 400
                || errorBody.lowercased().contains("unknown field")
                || errorBody.lowercased().contains("invalid_argument") {
            // Retry with strict upstream-minimal proto3 fields (e.g., Desktop servers whose protojson rejects optional `scope` or expects `allow`)
            var fallbackObj: [String: JSONValue] = [
                "trajectoryId": .string(payload.cascadeId),
                "stepIndex": .int(payload.stepIndex)
            ]
            if let perm = payload.permission {
                var minPerm: [String: JSONValue] = ["allow": .bool(perm.allow)]
                if !perm.grantPatterns.isEmpty {
                    minPerm["turnGrants"] = .object([
                        "allow": .array(perm.grantPatterns.map(JSONValue.string)),
                        "deny": .array([])
                    ])
                }
                fallbackObj["permission"] = .object(minPerm)
            } else if let fp = payload.filePermission {
                let compatScope = (fp.scope == "PERMISSION_SCOPE_CONVERSATION" || fp.scope == "PERMISSION_SCOPE_ALWAYS")
                    ? "PERMISSION_SCOPE_TURN"
                    : "PERMISSION_SCOPE_ONCE"
                var minFp: [String: JSONValue] = [
                    "allow": .bool(fp.allow),
                    "scope": .string(compatScope)
                ]
                if let uri = fp.absolutePathUri, !uri.isEmpty {
                    minFp["absolutePathUri"] = .string(uri)
                }
                fallbackObj["filePermission"] = .object(minFp)
            } else if let confirm = payload.genericConfirm {
                let memberKey = payload.rawMemberKey ?? payload.kind.rawValue
                let useAllowKey = errorBody.lowercased().contains("\"confirm\"")
                fallbackObj[memberKey] = .object([
                    (useAllowKey ? "allow" : "confirm"): .bool(confirm)
                ])
            } else {
                throw AntigravityRPCError.httpError(statusCode: statusCode, body: errorBody)
            }

            _ = try await callUnaryJSON(
                method: "HandleCascadeUserInteraction",
                body: ["interaction": .object(fallbackObj)],
                instanceUuidOverride: instanceUuidOverride
            )
        }
    }

    public func handleCascadeUserInteraction(
        step: CascadeStep,
        decision: InteractionDecision,
        instanceUuidOverride: String? = nil
    ) async throws {
        guard let payload = InteractionBuilder.buildPayload(step: step, decision: decision) else {
            throw AntigravityRPCError.interactionRejected
        }
        try await handleCascadeUserInteraction(payload, instanceUuidOverride: instanceUuidOverride)
    }

    public func cancelCascadeInvocation(
        cascadeId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        _ = try await callUnaryJSON(
            method: "CancelCascadeInvocation",
            body: ["cascadeId": .string(cascadeId)],
            instanceUuidOverride: instanceUuidOverride
        )
    }

    public func pinCascade(
        cascadeId: String,
        isPinned: Bool,
        instanceUuidOverride: String? = nil
    ) async throws {
        if channel == .cloudRelay {
            _ = try await callUnaryJSON(
                method: "UpdateConversationAnnotations",
                body: [
                    "cascadeId": .string(cascadeId),
                    "annotations": .object(["pinned": .bool(isPinned)]),
                    "mergeAnnotations": .bool(true)
                ],
                instanceUuidOverride: instanceUuidOverride
            )
            return
        }
        _ = try await callUnaryJSON(
            method: "PinCascade",
            body: [
                "cascadeId": .string(cascadeId),
                "isPinned": .bool(isPinned)
            ],
            instanceUuidOverride: instanceUuidOverride
        )
    }

    public func renameCascade(
        cascadeId: String,
        newTitle: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        if channel == .cloudRelay {
            _ = try await callUnaryJSON(
                method: "UpdateConversationAnnotations",
                body: [
                    "cascadeId": .string(cascadeId),
                    "annotations": .object(["title": .string(newTitle)]),
                    "mergeAnnotations": .bool(true)
                ],
                instanceUuidOverride: instanceUuidOverride
            )
            return
        }
        _ = try await callUnaryJSON(
            method: "RenameCascade",
            body: [
                "cascadeId": .string(cascadeId),
                "title": .string(newTitle)
            ],
            instanceUuidOverride: instanceUuidOverride
        )
    }

    public func moveCascadeToWorkspace(
        cascadeId: String,
        workspaceUri: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        _ = try await callUnaryJSON(
            method: "MoveCascadeToWorkspace",
            body: [
                "cascadeId": .string(cascadeId),
                "workspaceUri": .string(workspaceUri)
            ],
            instanceUuidOverride: instanceUuidOverride
        )
    }

    public func archiveCascade(
        cascadeId: String,
        isArchived: Bool = true,
        instanceUuidOverride: String? = nil
    ) async throws {
        if channel == .cloudRelay {
            _ = try await callUnaryJSON(
                method: "UpdateConversationAnnotations",
                body: [
                    "cascadeId": .string(cascadeId),
                    "annotations": .object(["archived": .bool(isArchived)]),
                    "mergeAnnotations": .bool(true)
                ],
                instanceUuidOverride: instanceUuidOverride
            )
            return
        }
        _ = try await callUnaryJSON(
            method: "ArchiveCascade",
            body: [
                "cascadeId": .string(cascadeId),
                "isArchived": .bool(isArchived)
            ],
            instanceUuidOverride: instanceUuidOverride
        )
    }

    public func deleteCascade(
        cascadeId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        if channel == .cloudRelay {
            _ = try await callUnaryJSON(
                method: "DeleteCascadeTrajectory",
                body: ["cascadeId": .string(cascadeId)],
                instanceUuidOverride: instanceUuidOverride
            )
            return
        }
        _ = try await callUnaryJSON(
            method: "DeleteCascade",
            body: ["cascadeId": .string(cascadeId)],
            instanceUuidOverride: instanceUuidOverride
        )
    }

    /// Updates `annotations.lastUserViewTime` on Antigravity Desktop (`UpdateConversationAnnotations`)
    /// so opening or marking a conversation as read on iOS clears the unread indicator on Desktop too.
    public func markCascadeViewed(
        cascadeId: String,
        viewedAt: Date = Date(),
        instanceUuidOverride: String? = nil
    ) async throws {
        guard !cascadeId.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: viewedAt)
        _ = try await callUnaryJSON(
            method: "UpdateConversationAnnotations",
            body: [
                "cascadeId": .string(cascadeId),
                "annotations": .object(["lastUserViewTime": .string(timestamp)]),
                "mergeAnnotations": .bool(true)
            ],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 6.0
        )
    }

    // MARK: - Automations RPC (`UE06` — Native Antigravity 2.0 Sidecars)

    private static func isMethodUnimplementedError(_ error: Error) -> Bool {
        guard case let AntigravityRPCError.httpError(code, body) = error else { return false }
        if code == 404 || code == 501 { return true }
        let lower = body.lowercased()
        return lower.contains("unimplemented") || lower.contains("unknown method") || lower.contains("method not found")
    }

    public static func parseInt64Millis(_ value: JSONValue?) -> Int64? {
        guard let value else { return nil }
        switch value {
        case .int(let i):
            return Int64(i)
        case .double(let d):
            return Int64(d)
        case .string(let s):
            return Int64(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private static func normalizeSidecarStatus(_ value: JSONValue?) -> String {
        guard let value else { return "UNSPECIFIED" }
        if let raw = value.stringValue?.uppercased() {
            if raw.contains("RUNNING") { return "RUNNING" }
            if raw.contains("STOPPED") { return "STOPPED" }
            if raw.contains("ERROR") { return "ERRORED" }
            if raw.contains("BACKOFF") { return "BACKOFF" }
            if raw.contains("STARTING") { return "STARTING" }
            return raw
        }
        if let code = value.intValue {
            switch code {
            case 1: return "RUNNING"
            case 2: return "STOPPED"
            case 3: return "ERRORED"
            case 4: return "BACKOFF"
            case 5: return "STARTING"
            default: return "UNSPECIFIED"
            }
        }
        return "UNSPECIFIED"
    }

    /// Refreshes local Antigravity Desktop `Project.id <-> Project.name` mapping via `ListProjects({})` + `ReadProject`.
    private func ensureLocalProjectIndex(forceRefresh: Bool = false) async {
        if !forceRefresh,
           let last = lastLocalProjectFetchAt,
           Date().timeIntervalSince(last) < 30.0,
           !cachedLocalProjectNameById.isEmpty {
            return
        }
        lastLocalProjectFetchAt = Date()
        guard let listResp = try? await callUnaryJSON(method: "ListProjects", body: [:], timeoutInterval: 6.0),
              let ids = (listResp["projectIds"] ?? listResp["project_ids"])?.arrayValue?.compactMap(\.stringValue).filter({ !$0.isEmpty }),
              !ids.isEmpty else {
            return
        }
        for pid in ids.prefix(32) {
            guard let readResp = try? await callUnaryJSON(method: "ReadProject", body: ["id": .string(pid)], timeoutInterval: 5.0),
                  let projObj = readResp["project"]?.objectValue else {
                continue
            }
            let resolvedId = Self.nonEmptyString(projObj["id"]?.stringValue) ?? pid
            let name = Self.nonEmptyString(projObj["name"]?.stringValue) ?? resolvedId
            cachedLocalProjectNameById[resolvedId] = name
            cachedLocalProjectIdByName[name.lowercased()] = resolvedId
        }
    }

    /// Decodes a single `exa.cortex_pb.SidecarStatusInfo` JSON object into an `AutomationItem`.
    /// Returns `nil` for pure auxiliary Web UI panel sidecars (`hasWebUi: true`) or bundled non-schedule sidecars.
    public static func decodeSidecarStatusInfo(
        _ obj: [String: JSONValue],
        projectNameById: [String: String] = [:],
        originInstanceUuid: String? = nil,
        now: Date = Date()
    ) -> AutomationItem? {
        guard let sidecarId = nonEmptyString(obj["sidecarId"]?.stringValue)
            ?? nonEmptyString(obj["sidecar_id"]?.stringValue)
            ?? nonEmptyString(obj["id"]?.stringValue) else {
            return nil
        }

        let cfg = obj["config"]?.objectValue ?? [:]
        let uiCfg = obj["uiConfig"]?.objectValue ?? obj["ui_config"]?.objectValue
            ?? cfg["uiConfig"]?.objectValue ?? cfg["ui_config"]?.objectValue
        let uiViews = uiCfg?["views"]?.arrayValue ?? []
        let hasWebUI = (cfg["hasWebUi"]?.boolValue ?? cfg["has_web_ui"]?.boolValue ?? false) || !uiViews.isEmpty
        let isBundled = obj["isBundled"]?.boolValue ?? obj["is_bundled"]?.boolValue ?? false

        let builtin = (nonEmptyString(cfg["builtin"]?.stringValue) ?? nonEmptyString(obj["builtin"]?.stringValue) ?? "").lowercased()
        let command = nonEmptyString(cfg["command"]?.stringValue) ?? ""
        let args = cfg["args"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let invokesAgentApi = args.count >= 3 && args.contains("agentapi") && args.contains("new-conversation")
        let isSchedule = (builtin == "schedule") || invokesAgentApi

        // Exclude Auxiliary Pane Web UI widgets and internal bundled daemons unless they are scheduled automations.
        if !isSchedule && (hasWebUI || isBundled) {
            return nil
        }

        let displayName = nonEmptyString(cfg["displayName"]?.stringValue)
            ?? nonEmptyString(cfg["display_name"]?.stringValue)
            ?? nonEmptyString(obj["name"]?.stringValue)
            ?? sidecarId
        let descriptionText = nonEmptyString(cfg["description"]?.stringValue)
            ?? nonEmptyString(obj["description"]?.stringValue)
            ?? ""

        let statusNorm = normalizeSidecarStatus(obj["status"])
        let lastError = nonEmptyString(obj["lastError"]?.stringValue) ?? nonEmptyString(obj["last_error"]?.stringValue)

        let userCfg = obj["userConfig"]?.objectValue ?? obj["user_config"]?.objectValue
        let userProjectId = nonEmptyString(userCfg?["projectId"]?.stringValue) ?? nonEmptyString(userCfg?["project_id"]?.stringValue)
        let allProjects = userCfg?["allProjects"]?.boolValue ?? userCfg?["all_projects"]?.boolValue ?? false
        let configDisabled = cfg["disabled"]?.boolValue ?? false

        // Proto3 JSON omits scalar `bool enabled = false`, so combine explicit `userConfig.enabled` with runtime `status`.
        let isEnabled: Bool = {
            if let explicitEnabled = userCfg?["enabled"]?.boolValue {
                return explicitEnabled
            }
            if configDisabled {
                return false
            }
            if statusNorm == "RUNNING" || statusNorm == "STARTING" {
                return true
            }
            if userCfg != nil {
                return false
            }
            return statusNorm != "STOPPED"
        }()

        let section: AutomationSectionKind = {
            if !isEnabled { return .paused }
            return isSchedule ? .scheduled : .alwaysOn
        }()

        let parsedArgs: (cron: String, prompt: String, modelLabel: String?) = isSchedule
            ? AutomationScheduleCodec.parseScheduleArgs(args)
            : (cron: "", prompt: "", modelLabel: nil)
        let cronExpr = parsedArgs.cron
        let promptText = parsedArgs.prompt.isEmpty ? (descriptionText.isEmpty ? displayName : descriptionText) : parsedArgs.prompt
        let modelBadge = parsedArgs.modelLabel ?? (isSchedule ? "Flash" : nil)

        // Resolve human-readable project label from `projectId`, `agentPermissions.workspaceUris`, or `allProjects`.
        let agentPerms = cfg["agentPermissions"]?.objectValue ?? cfg["agent_permissions"]?.objectValue
        let permWorkspaceUris = (agentPerms?["workspaceUris"] ?? agentPerms?["workspace_uris"])?.arrayValue?.compactMap(\.stringValue) ?? []
        let projectSlug: String = {
            if let pid = userProjectId, !pid.isEmpty {
                if let resolved = projectNameById[pid], !resolved.isEmpty {
                    return resolved
                }
                return pid
            }
            if let firstUri = permWorkspaceUris.first, !firstUri.isEmpty {
                let cleaned = firstUri.replacingOccurrences(of: "file://", with: "")
                let base = (cleaned as NSString).lastPathComponent
                if !base.isEmpty && base != "/" {
                    return base
                }
            }
            return allProjects ? "All projects" : "This Computer"
        }()

        let humanSchedule = isSchedule
            ? AutomationScheduleCodec.humanReadableSchedule(from: cronExpr)
            : (command.isEmpty ? "Background listener" : (command as NSString).lastPathComponent)

        let scheduleSummary: String = {
            if isSchedule {
                return "\(projectSlug) · \(humanSchedule) · \(modelBadge ?? "Flash")"
            }
            return "\(projectSlug) · Always On · \(humanSchedule)"
        }()

        let nextRunText: String = {
            if section == .paused { return "Paused" }
            if isSchedule {
                return AutomationScheduleCodec.nextFireDescription(from: cronExpr, after: now)
            }
            switch statusNorm {
            case "RUNNING": return "Listening"
            case "STARTING": return "Starting..."
            case "ERRORED", "BACKOFF": return "Error"
            default: return "Active"
            }
        }()

        let hasRuntimeError = (statusNorm == "ERRORED" || statusNorm == "BACKOFF") || (lastError != nil)
        let lastRunText: String = {
            if let lastError, !lastError.isEmpty {
                return "Error · \(String(lastError.prefix(28)))"
            }
            if statusNorm == "ERRORED" || statusNorm == "BACKOFF" {
                return "Failed · Needs review"
            }
            if section == .paused {
                return "Paused"
            }
            if let startMs = parseInt64Millis(obj["startTimeMs"] ?? obj["start_time_ms"]), startMs > 0 {
                return isSchedule ? "Scheduled · Ready" : "Running · \(AutomationScheduleCodec.relativeTimeLabel(from: startMs, now: now))"
            }
            return isSchedule ? "Scheduled · Ready" : "Active"
        }()

        return AutomationItem(
            id: sidecarId,
            title: displayName,
            projectSlug: projectSlug,
            scheduleSummary: scheduleSummary,
            section: section,
            nextRunText: nextRunText,
            lastRunText: lastRunText,
            needsReview: hasRuntimeError,
            isRunningNow: false,
            descriptionText: descriptionText,
            prompt: promptText,
            cronExpression: cronExpr,
            projectId: userProjectId,
            allProjects: allProjects,
            modelLabel: modelBadge,
            lastRunCascadeId: nil,
            lastError: lastError,
            isEnabled: isEnabled,
            isScheduleBuiltin: isSchedule,
            originInstanceUuid: originInstanceUuid
        )
    }

    public static func decodeSidecarEvent(_ obj: [String: JSONValue]) -> SidecarRunEvent? {
        let ts = parseInt64Millis(obj["timestampMs"] ?? obj["timestamp_ms"])
            ?? parseInt64Millis(obj["commandInvocationTimestampMs"] ?? obj["command_invocation_timestamp_ms"])
            ?? 0
        let err = nonEmptyString(obj["error"]?.stringValue)
        let payload = obj["payload"]?.objectValue
        let newConv = payload?["newConversation"]?.objectValue ?? payload?["new_conversation"]?.objectValue
        let convId = nonEmptyString(newConv?["conversationId"]?.stringValue)
            ?? nonEmptyString(newConv?["conversation_id"]?.stringValue)
        let prompt = nonEmptyString(newConv?["prompt"]?.stringValue)
        guard ts > 0 || convId != nil || err != nil else { return nil }
        return SidecarRunEvent(
            timestampMs: ts,
            error: err,
            conversationId: convId,
            prompt: prompt
        )
    }

    /// Builds a native `ManageSidecarRequest` (`SIDECAR_ACTION_CREATE` or `SIDECAR_ACTION_UPDATE`) JSON body.
    public static func buildManageSidecarConfigBody(
        sidecarId: String,
        action: SidecarManageAction,
        displayName: String,
        prompt: String,
        cronExpression: String,
        description: String = "",
        projectId: String? = nil,
        allProjects: Bool = false,
        modelArg: String? = nil
    ) -> [String: JSONValue] {
        let args = AutomationScheduleCodec.buildScheduleArgs(
            cron: cronExpression,
            prompt: prompt,
            modelArg: modelArg
        )
        var configObj: [String: JSONValue] = [
            "builtin": .string("schedule"),
            "restartPolicy": .string("always"),
            "displayName": .string(displayName),
            "args": .array(args.map { .string($0) })
        ]
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configObj["description"] = .string(description.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var body: [String: JSONValue] = [
            "sidecarId": .string(sidecarId),
            "action": .string(action.rawValue),
            "config": .object(configObj)
        ]
        if let projectId = nonEmptyString(projectId) {
            body["projectId"] = .string(projectId)
        } else if allProjects {
            body["allProjects"] = .bool(true)
        }
        return body
    }

    public func getSidecarEvents(
        sidecarId: String,
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval = 5.0
    ) async throws -> [SidecarRunEvent] {
        let res = try await callUnaryJSON(
            method: "GetSidecarEvents",
            body: ["sidecarId": .string(sidecarId)],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: timeoutInterval
        )
        guard let arr = res["events"]?.arrayValue else { return [] }
        return arr.compactMap { entry -> SidecarRunEvent? in
            guard let obj = entry.objectValue else { return nil }
            return Self.decodeSidecarEvent(obj)
        }
        .sorted { $0.timestampMs > $1.timestampMs }
    }

    public func listAutomations(timeoutInterval: TimeInterval? = nil) async throws -> [AutomationItem] {
        await ensureLocalProjectIndex()
        var projectNameById = cachedLocalProjectNameById
        for (pid, proj) in cachedCloudProjectsById where projectNameById[pid] == nil {
            projectNameById[pid] = proj.name
        }

        do {
            let res = try await callUnaryJSON(
                method: "GetSidecars",
                body: [:],
                timeoutInterval: timeoutInterval ?? 10.0
            )
            let activeOrigin = resolvedInstanceUuid
            let rawSidecars = res["sidecars"]?.arrayValue ?? []
            var items: [AutomationItem] = rawSidecars.compactMap { entry in
                guard let obj = entry.objectValue else { return nil }
                return Self.decodeSidecarStatusInfo(
                    obj,
                    projectNameById: projectNameById,
                    originInstanceUuid: activeOrigin
                )
            }

            // Enrich top automations with real run history (`lastRunText` & `lastRunCascadeId`) via `GetSidecarEvents`.
            if !items.isEmpty {
                let targetIds = items.prefix(20).map(\.id)
                let eventsById: [String: SidecarRunEvent] = await withTaskGroup(of: (String, SidecarRunEvent?).self) { group in
                    for sid in targetIds {
                        group.addTask {
                            let events = (try? await self.getSidecarEvents(
                                sidecarId: sid,
                                instanceUuidOverride: activeOrigin,
                                timeoutInterval: 4.5
                            )) ?? []
                            return (sid, events.first)
                        }
                    }
                    var map: [String: SidecarRunEvent] = [:]
                    for await (sid, latest) in group {
                        if let latest {
                            map[sid] = latest
                        }
                    }
                    return map
                }

                let now = Date()
                for idx in items.indices {
                    guard let latest = eventsById[items[idx].id] else { continue }
                    if let cid = latest.conversationId, !cid.isEmpty {
                        items[idx].lastRunCascadeId = cid
                    }
                    let rel = latest.timestampMs > 0
                        ? AutomationScheduleCodec.relativeTimeLabel(from: latest.timestampMs, now: now)
                        : "recently"
                    if let err = latest.error, !err.isEmpty {
                        items[idx].lastError = err
                        items[idx].needsReview = true
                        items[idx].lastRunText = "Failed · \(rel)"
                    } else if items[idx].lastError == nil {
                        items[idx].lastRunText = "Succeeded · \(rel)"
                    }
                }
            }

            items.sort { lhs, rhs in
                if lhs.section != rhs.section {
                    let rank: (AutomationSectionKind) -> Int = { s in
                        switch s {
                        case .scheduled: return 0
                        case .alwaysOn: return 1
                        case .paused: return 2
                        }
                    }
                    return rank(lhs.section) < rank(rhs.section)
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return items
        } catch {
            // Only fall back to legacy `ListAutomations` on direct LAN mock/sandbox servers that don't expose `GetSidecars`.
            if channel == .directHost && Self.isMethodUnimplementedError(error) {
                return try await listLegacyCompanionAutomations()
            }
            throw error
        }
    }

    private func listLegacyCompanionAutomations() async throws -> [AutomationItem] {
        let res = try await callUnaryJSON(method: "ListAutomations")
        guard let arr = res["automations"]?.arrayValue else { return [] }
        return arr.compactMap { item -> AutomationItem? in
            guard let obj = item.objectValue,
                  let id = obj["id"]?.stringValue,
                  let title = obj["title"]?.stringValue else { return nil }
            let slug = obj["projectSlug"]?.stringValue ?? "ledger-svc"
            let summary = obj["scheduleSummary"]?.stringValue ?? "\(slug) · Daily · Flash"
            let sectionRaw = (obj["section"]?.stringValue ?? AutomationSectionKind.scheduled.rawValue).uppercased()
            let section = AutomationSectionKind(rawValue: sectionRaw) ?? .scheduled
            return AutomationItem(
                id: id,
                title: title,
                projectSlug: slug,
                scheduleSummary: summary,
                section: section,
                nextRunText: obj["nextRunText"]?.stringValue ?? "Tonight, 02:00",
                lastRunText: obj["lastRunText"]?.stringValue ?? "Scheduled",
                needsReview: obj["needsReview"]?.boolValue ?? false,
                isRunningNow: obj["isRunningNow"]?.boolValue ?? false
            )
        }
    }

    public func createAutomation(prompt: String, projectSlug: String) async throws -> AutomationItem {
        let parsed = AutomationScheduleCodec.parseNaturalLanguagePrompt(prompt)
        return try await createAutomation(
            displayName: parsed.displayName,
            prompt: parsed.prompt,
            cronExpression: parsed.cronExpression,
            projectSlug: projectSlug,
            projectId: nil,
            allProjects: projectSlug.isEmpty || projectSlug == "All projects",
            modelArg: nil,
            description: "\(parsed.humanScheduleLabel): \(parsed.prompt)",
            enableImmediately: true
        )
    }

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
    ) async throws -> AutomationItem {
        await ensureLocalProjectIndex()
        let resolvedLocalProjectId: String? = {
            if let explicit = Self.nonEmptyString(projectId),
               cachedLocalProjectNameById[explicit] != nil || !explicit.hasPrefix("projects/") {
                return explicit
            }
            let normalizedSlug = projectSlug
                .replacingOccurrences(of: "cloud:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !normalizedSlug.isEmpty, let match = cachedLocalProjectIdByName[normalizedSlug] {
                return match
            }
            return nil
        }()

        let sidecarId = AutomationScheduleCodec.makeSidecarId(from: displayName)
        let createBody = Self.buildManageSidecarConfigBody(
            sidecarId: sidecarId,
            action: .create,
            displayName: displayName,
            prompt: prompt,
            cronExpression: cronExpression,
            description: description,
            projectId: resolvedLocalProjectId,
            allProjects: resolvedLocalProjectId == nil && allProjects,
            modelArg: modelArg
        )

        do {
            let createResp = try await callUnaryJSON(
                method: "ManageSidecar",
                body: createBody,
                timeoutInterval: 15.0
            )
            let createdId = Self.nonEmptyString(createResp["sidecarId"]?.stringValue)
                ?? Self.nonEmptyString(createResp["sidecar_id"]?.stringValue)
                ?? sidecarId

            // Bind target project explicitly via `SIDECAR_ACTION_SET_PROJECT` so Desktop honors it even when
            // `jetski-sidecar-declared-permissions` omits project binding on initial CREATE.
            if let pid = resolvedLocalProjectId, !pid.isEmpty {
                _ = try? await callUnaryJSON(
                    method: "ManageSidecar",
                    body: [
                        "sidecarId": .string(createdId),
                        "action": .string(SidecarManageAction.setProject.rawValue),
                        "projectId": .string(pid)
                    ],
                    timeoutInterval: 10.0
                )
            } else if allProjects {
                _ = try? await callUnaryJSON(
                    method: "ManageSidecar",
                    body: [
                        "sidecarId": .string(createdId),
                        "action": .string(SidecarManageAction.setAllProjects.rawValue),
                        "allProjects": .bool(true)
                    ],
                    timeoutInterval: 10.0
                )
            }

            if enableImmediately {
                _ = try? await callUnaryJSON(
                    method: "ManageSidecar",
                    body: [
                        "sidecarId": .string(createdId),
                        "action": .string(SidecarManageAction.enable.rawValue)
                    ],
                    timeoutInterval: 10.0
                )
            }

            let humanSched = AutomationScheduleCodec.humanReadableSchedule(from: cronExpression)
            let modelBadge = AutomationScheduleCodec.formatModelBadge(modelArg ?? "Flash")
            let slugLabel = projectSlug.isEmpty ? (allProjects ? "All projects" : "This Computer") : projectSlug
            return AutomationItem(
                id: createdId,
                title: displayName,
                projectSlug: slugLabel,
                scheduleSummary: "\(slugLabel) · \(humanSched) · \(modelBadge)",
                section: enableImmediately ? .scheduled : .paused,
                nextRunText: enableImmediately ? AutomationScheduleCodec.nextFireDescription(from: cronExpression) : "Paused",
                lastRunText: enableImmediately ? "Created just now" : "Paused · New",
                needsReview: false,
                isRunningNow: false,
                descriptionText: description,
                prompt: prompt,
                cronExpression: cronExpression,
                projectId: resolvedLocalProjectId,
                allProjects: resolvedLocalProjectId == nil && allProjects,
                modelLabel: modelBadge,
                isEnabled: enableImmediately,
                isScheduleBuiltin: true,
                originInstanceUuid: resolvedInstanceUuid
            )
        } catch {
            if channel == .directHost && Self.isMethodUnimplementedError(error) {
                let res = try await callUnaryJSON(
                    method: "CreateAutomation",
                    body: [
                        "prompt": .string(prompt),
                        "projectSlug": .string(projectSlug)
                    ]
                )
                let id = res["id"]?.stringValue ?? sidecarId
                return AutomationItem(
                    id: id,
                    title: displayName,
                    projectSlug: projectSlug,
                    scheduleSummary: "\(projectSlug) · \(AutomationScheduleCodec.humanReadableSchedule(from: cronExpression)) · Flash",
                    section: .scheduled,
                    nextRunText: AutomationScheduleCodec.nextFireDescription(from: cronExpression),
                    lastRunText: "Created just now",
                    prompt: prompt,
                    cronExpression: cronExpression
                )
            }
            throw error
        }
    }

    public func updateAutomation(
        automationId: String,
        displayName: String,
        prompt: String,
        cronExpression: String,
        projectSlug: String,
        projectId: String? = nil,
        allProjects: Bool = false,
        modelArg: String? = nil,
        description: String = "",
        instanceUuidOverride: String? = nil
    ) async throws {
        await ensureLocalProjectIndex()
        let resolvedLocalProjectId: String? = {
            if let explicit = Self.nonEmptyString(projectId) { return explicit }
            let key = projectSlug.replacingOccurrences(of: "cloud:", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return cachedLocalProjectIdByName[key]
        }()

        let body = Self.buildManageSidecarConfigBody(
            sidecarId: automationId,
            action: .update,
            displayName: displayName,
            prompt: prompt,
            cronExpression: cronExpression,
            description: description,
            projectId: resolvedLocalProjectId,
            allProjects: resolvedLocalProjectId == nil && allProjects,
            modelArg: modelArg
        )
        _ = try await callUnaryJSON(
            method: "ManageSidecar",
            body: body,
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 15.0
        )
        if let pid = resolvedLocalProjectId, !pid.isEmpty {
            _ = try? await callUnaryJSON(
                method: "ManageSidecar",
                body: [
                    "sidecarId": .string(automationId),
                    "action": .string(SidecarManageAction.setProject.rawValue),
                    "projectId": .string(pid)
                ],
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: 10.0
            )
        } else if allProjects {
            _ = try? await callUnaryJSON(
                method: "ManageSidecar",
                body: [
                    "sidecarId": .string(automationId),
                    "action": .string(SidecarManageAction.setAllProjects.rawValue),
                    "allProjects": .bool(true)
                ],
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: 10.0
            )
        }
    }

    public func triggerAutomationNow(
        automationId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        do {
            _ = try await callUnaryJSON(
                method: "ManageSidecar",
                body: [
                    "sidecarId": .string(automationId),
                    "action": .string(SidecarManageAction.runNow.rawValue)
                ],
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: 15.0
            )
        } catch {
            if channel == .directHost && Self.isMethodUnimplementedError(error) {
                _ = try await callUnaryJSON(
                    method: "TriggerAutomationNow",
                    body: ["automationId": .string(automationId)]
                )
                return
            }
            throw error
        }
    }

    public func setAutomationPaused(
        automationId: String,
        isPaused: Bool,
        instanceUuidOverride: String? = nil
    ) async throws {
        let action: SidecarManageAction = isPaused ? .disable : .enable
        do {
            _ = try await callUnaryJSON(
                method: "ManageSidecar",
                body: [
                    "sidecarId": .string(automationId),
                    "action": .string(action.rawValue)
                ],
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: 12.0
            )
        } catch {
            if channel == .directHost && Self.isMethodUnimplementedError(error) {
                _ = try await callUnaryJSON(
                    method: "SetAutomationPaused",
                    body: [
                        "automationId": .string(automationId),
                        "isPaused": .bool(isPaused)
                    ]
                )
                return
            }
            throw error
        }
    }

    public func deleteAutomation(
        automationId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        _ = try await callUnaryJSON(
            method: "ManageSidecar",
            body: [
                "sidecarId": .string(automationId),
                "action": .string(SidecarManageAction.delete.rawValue)
            ],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 12.0
        )
    }

    public func restartAutomation(
        automationId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        _ = try await callUnaryJSON(
            method: "ManageSidecar",
            body: [
                "sidecarId": .string(automationId),
                "action": .string(SidecarManageAction.restart.rawValue)
            ],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 12.0
        )
    }

    // MARK: - Artifacts & Turn Diff RPC (`UE11`, `UE12` + Git VCS)

    public func getArtifactSnapshots(cascadeId: String, instanceUuidOverride: String? = nil) async throws -> [ArtifactSnapshot] {
        let res = try await callUnaryJSON(
            method: "GetArtifactSnapshots",
            body: ["cascadeId": .string(cascadeId)],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 8.0
        )
        let arr = res["artifacts"]?.arrayValue
            ?? res["artifactSnapshots"]?.arrayValue
            ?? res["snapshots"]?.arrayValue
            ?? []
        return arr.compactMap { item -> ArtifactSnapshot? in
            guard let obj = item.objectValue else { return nil }
            let path = obj["artifactPath"]?.stringValue
                ?? obj["path"]?.stringValue
                ?? obj["fileUri"]?.stringValue
                ?? obj["uri"]?.stringValue
            guard let path, !path.isEmpty else { return nil }
            let kind: ArtifactKind = {
                if let rawKind = obj["kind"]?.stringValue,
                   let parsed = ArtifactKind(rawValue: rawKind) {
                    return parsed
                }
                let lower = path.lowercased()
                if lower.hasSuffix(".pdf") { return .pdfDocument }
                if lower.hasSuffix(".ipynb") { return .jupyterNotebook }
                if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") {
                    return .imageAsset
                }
                if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".webm") {
                    return .videoAsset
                }
                if lower.hasSuffix(".html") || lower.hasSuffix(".htm") { return .generativeUIHTML }
                if lower.hasSuffix(".url.json") { return .urlBookmark }
                if lower.contains("walkthrough") { return .walkthrough }
                if lower.contains("task") { return .taskList }
                return .implementationPlan
            }()
            let content = obj["content"]?.stringValue
                ?? obj["textContent"]?.stringValue
                ?? obj["body"]?.stringValue
                ?? ""
            return ArtifactSnapshot(
                artifactPath: path,
                title: obj["title"]?.stringValue ?? (path as NSString).lastPathComponent,
                summary: obj["summary"]?.stringValue ?? "",
                kind: kind,
                content: content,
                requestFeedback: obj["requestFeedback"]?.boolValue ?? false,
                userFacing: obj["userFacing"]?.boolValue ?? true,
                version: obj["version"]?.intValue ?? 1
            )
        }
    }

    /// Resolves a host-local `file:///...` artifact (such as an `<agent-embed src="file:///.../fig4.html">`
    /// widget or generated image) through Companion Bridge `ReadArtifactFile`, `GetArtifactSnapshots`,
    /// or `GetRevisionArtifact` across both Direct LAN and Cloud Relay channels.
    public func fetchRemoteArtifactResource(
        uri: String,
        cascadeId: String,
        instanceUuidOverride: String? = nil
    ) async -> ResolvedEmbedResource? {
        let normalizedTarget = ResolvedEmbedResource.normalizePath(uri)
        let targetBaseName = (normalizedTarget as NSString).lastPathComponent.lowercased()
        guard !normalizedTarget.isEmpty else { return nil }

        // 1. Companion Bridge / Direct LAN `ReadArtifactFile` (supports HTML, SVG, MD, PNG/JPG/WebP/GIF)
        if channel == .directHost {
            if let res = try? await callUnaryJSON(
                method: "ReadArtifactFile",
                body: [
                    "uri": .string(uri),
                    "path": .string(normalizedTarget),
                    "cascadeId": .string(cascadeId)
                ],
                timeoutInterval: 8.0
            ), res["ok"]?.boolValue != false,
               let rawContent = res["content"]?.stringValue,
               !rawContent.isEmpty {
                let mime = res["mimeType"]?.stringValue ?? ResolvedEmbedResource.inferredMimeType(for: uri)
                let encoding = (res["encoding"]?.stringValue ?? "utf-8").lowercased()
                if encoding == "base64", let data = Data(base64Encoded: rawContent, options: .ignoreUnknownCharacters) {
                    let text = mime.lowercased().hasPrefix("text/") || mime.lowercased().contains("svg")
                        ? String(data: data, encoding: .utf8)
                        : nil
                    return ResolvedEmbedResource(
                        uri: uri,
                        normalizedPath: normalizedTarget,
                        mimeType: mime,
                        textContent: text,
                        binaryData: data,
                        source: .remoteHost
                    )
                } else {
                    return ResolvedEmbedResource(
                        uri: uri,
                        normalizedPath: normalizedTarget,
                        mimeType: mime,
                        textContent: rawContent,
                        binaryData: Data(rawContent.utf8),
                        source: .remoteHost
                    )
                }
            }
        }

        // 2. Upstream `LanguageServerService/GetArtifactSnapshots` (works over Direct LAN & Official Cloud Relay!)
        if !cascadeId.isEmpty,
           let snapshots = try? await getArtifactSnapshots(cascadeId: cascadeId, instanceUuidOverride: instanceUuidOverride) {
            if let matched = snapshots.first(where: { snap in
                let snapNorm = ResolvedEmbedResource.normalizePath(snap.artifactPath)
                if snapNorm == normalizedTarget { return true }
                if !targetBaseName.isEmpty && (snapNorm as NSString).lastPathComponent.lowercased() == targetBaseName {
                    return true
                }
                return false
            }), !matched.content.isEmpty {
                return ResolvedEmbedResource(
                    uri: uri,
                    normalizedPath: normalizedTarget,
                    mimeType: ResolvedEmbedResource.inferredMimeType(for: uri),
                    textContent: matched.content,
                    binaryData: Data(matched.content.utf8),
                    source: .artifactSnapshot
                )
            }
        }

        // 3. Upstream `LanguageServerService/GetRevisionArtifact` fallback
        if !cascadeId.isEmpty {
            let revBodies: [[String: JSONValue]] = [
                ["cascadeId": .string(cascadeId), "artifactPath": .string(normalizedTarget)],
                ["trajectoryId": .string(cascadeId), "fileUri": .string(uri)]
            ]
            for reqBody in revBodies {
                if let res = try? await callUnaryJSON(
                    method: "GetRevisionArtifact",
                    body: reqBody,
                    instanceUuidOverride: instanceUuidOverride,
                    timeoutInterval: 6.0
                ) {
                    let content = res["content"]?.stringValue
                        ?? res["artifact"]?.objectValue?["content"]?.stringValue
                        ?? res["text"]?.stringValue
                    if let content, !content.isEmpty {
                        return ResolvedEmbedResource(
                            uri: uri,
                            normalizedPath: normalizedTarget,
                            mimeType: ResolvedEmbedResource.inferredMimeType(for: uri),
                            textContent: content,
                            binaryData: Data(content.utf8),
                            source: .artifactSnapshot
                        )
                    }
                }
            }
        }

        return nil
    }

    public func sendPlanReviewComments(cascadeId: String, comments: [PlanInlineComment]) async throws {
        let encodedComments: [JSONValue] = comments.map { c in
            .object([
                "id": .string(c.id),
                "targetFilePath": .string(c.targetFilePath),
                "quotedSpan": .string(c.quotedSpan),
                "body": .string(c.body)
            ])
        }
        _ = try await callUnaryJSON(
            method: "SendPlanReviewComments",
            body: [
                "cascadeId": .string(cascadeId),
                "comments": .array(encodedComments)
            ]
        )
    }

    public func getTurnDiff(
        cascadeId: String,
        turnNumber: Int?,
        compareMode: DiffCompareMode = .turn
    ) async throws -> [FilePatchDiff] {
        var body: [String: JSONValue] = [
            "cascadeId": .string(cascadeId),
            "compareMode": .string(compareMode.rawValue)
        ]
        if let turnNumber {
            body["turnNumber"] = .int(turnNumber)
        }
        let res = try await callUnaryJSON(method: "GetTurnDiff", body: body)
        return Self.parseFilePatchDiffs(from: res, defaultTurn: turnNumber ?? 1, defaultScope: compareMode)
    }

    internal static func parseFilePatchDiffs(
        from response: [String: JSONValue],
        defaultTurn: Int = 1,
        defaultScope: DiffCompareMode = .turn
    ) -> [FilePatchDiff] {
        guard let rawFiles = response["files"]?.arrayValue ?? response["diffs"]?.arrayValue else {
            return []
        }
        return rawFiles.compactMap { entry -> FilePatchDiff? in
            guard let obj = entry.objectValue,
                  let path = nonEmptyString(obj["filePath"]?.stringValue ?? obj["path"]?.stringValue) else {
                return nil
            }
            let turn = obj["turnNumber"]?.intValue ?? defaultTurn
            let statusLetter = GitFileStatusLetter(
                rawValue: (obj["statusLetter"]?.stringValue ?? obj["status"]?.stringValue ?? "M").uppercased()
            ) ?? .modified
            let isStaged = obj["isStaged"]?.boolValue ?? false
            let isReviewed = obj["isReviewed"]?.boolValue ?? false
            let scope = DiffCompareMode(rawValue: obj["compareScope"]?.stringValue ?? "") ?? defaultScope
            let hunkHeader = obj["hunkHeader"]?.stringValue ?? "@@ -1,1 +1,1 @@"

            var parsedLines: [DiffLine] = []
            if let rawLines = obj["lines"]?.arrayValue {
                for (idx, lineVal) in rawLines.enumerated() {
                    guard let lObj = lineVal.objectValue else { continue }
                    let kindStr = (lObj["kind"]?.stringValue ?? "context").lowercased()
                    let lineKind: DiffLine.Kind
                    switch kindStr {
                    case "addition", "add", "+": lineKind = .addition
                    case "deletion", "del", "-": lineKind = .deletion
                    case "hunkheader", "hunk": lineKind = .hunkHeader
                    default: lineKind = .context
                    }
                    parsedLines.append(
                        DiffLine(
                            id: lObj["id"]?.intValue ?? idx,
                            kind: lineKind,
                            oldLineNumber: lObj["oldLineNumber"]?.intValue,
                            newLineNumber: lObj["newLineNumber"]?.intValue,
                            text: lObj["text"]?.stringValue ?? "",
                            wordHighlightRange: lObj["wordHighlightRange"]?.stringValue
                        )
                    )
                }
            } else if let rawHunks = obj["hunks"]?.arrayValue {
                var runningId = 0
                for hVal in rawHunks {
                    guard let hObj = hVal.objectValue else { continue }
                    if let hdr = nonEmptyString(hObj["header"]?.stringValue) {
                        parsedLines.append(DiffLine(id: runningId, kind: .hunkHeader, text: hdr))
                        runningId += 1
                    }
                    for lineVal in hObj["lines"]?.arrayValue ?? [] {
                        guard let lObj = lineVal.objectValue else { continue }
                        let kindStr = (lObj["kind"]?.stringValue ?? "context").lowercased()
                        let lineKind: DiffLine.Kind = (kindStr == "addition" || kindStr == "+")
                            ? .addition
                            : ((kindStr == "deletion" || kindStr == "-") ? .deletion : .context)
                        parsedLines.append(
                            DiffLine(
                                id: runningId,
                                kind: lineKind,
                                oldLineNumber: lObj["oldLineNumber"]?.intValue,
                                newLineNumber: lObj["newLineNumber"]?.intValue,
                                text: lObj["text"]?.stringValue ?? ""
                            )
                        )
                        runningId += 1
                    }
                }
            } else if let rawPatch = obj["patch"]?.stringValue ?? obj["unifiedDiff"]?.stringValue {
                parsedLines = parseUnifiedDiffText(rawPatch)
            }

            let additions = obj["additions"]?.intValue ?? parsedLines.filter { $0.kind == .addition }.count
            let deletions = obj["deletions"]?.intValue ?? parsedLines.filter { $0.kind == .deletion }.count

            return FilePatchDiff(
                turnNumber: turn,
                filePath: path,
                additions: additions,
                deletions: deletions,
                hunkHeader: hunkHeader,
                isReviewed: isReviewed,
                statusLetter: statusLetter,
                isStaged: isStaged,
                compareScope: scope,
                lines: parsedLines
            )
        }
    }

    internal static func parseUnifiedDiffText(_ unifiedDiff: String) -> [DiffLine] {
        var result: [DiffLine] = []
        var oldNum = 1
        var newNum = 1
        for (idx, rawLine) in unifiedDiff.components(separatedBy: "\n").enumerated() {
            if rawLine.hasPrefix("@@") {
                result.append(DiffLine(id: idx, kind: .hunkHeader, text: rawLine))
            } else if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                result.append(DiffLine(id: idx, kind: .addition, oldLineNumber: nil, newLineNumber: newNum, text: String(rawLine.dropFirst())))
                newNum += 1
            } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                result.append(DiffLine(id: idx, kind: .deletion, oldLineNumber: oldNum, newLineNumber: nil, text: String(rawLine.dropFirst())))
                oldNum += 1
            } else if !rawLine.hasPrefix("---") && !rawLine.hasPrefix("+++") {
                let content = rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
                result.append(DiffLine(id: idx, kind: .context, oldLineNumber: oldNum, newLineNumber: newNum, text: content))
                oldNum += 1
                newNum += 1
            }
        }
        return result
    }

    public func revertDiffHunk(cascadeId: String, filePath: String, hunkHeader: String? = nil) async throws {
        var body: [String: JSONValue] = [
            "cascadeId": .string(cascadeId),
            "filePath": .string(filePath)
        ]
        if let hunkHeader {
            body["hunkHeader"] = .string(hunkHeader)
        }
        _ = try await callUnaryJSON(method: "RevertDiffHunk", body: body)
    }

    public func sendDiffReviewComments(cascadeId: String, comments: [DiffLineComment]) async throws {
        let encoded: [JSONValue] = comments.map { c in
            .object([
                "id": .string(c.id),
                "filePath": .string(c.filePath),
                "lineNumber": .int(c.lineNumber),
                "body": .string(c.body)
            ])
        }
        _ = try await callUnaryJSON(
            method: "SendDiffReviewComments",
            body: [
                "cascadeId": .string(cascadeId),
                "comments": .array(encoded)
            ]
        )
    }

    // MARK: - Antigravity 2.0 (v2.33) Git VCS, Overview, Side Question, Permissions & Customizations RPCs

    public func gitStageFile(cascadeId: String, filePath: String) async throws {
        _ = try await callUnaryJSON(
            method: "GitStageFile",
            body: ["cascadeId": .string(cascadeId), "filePath": .string(filePath)]
        )
    }

    public func gitUnstageFile(cascadeId: String, filePath: String) async throws {
        _ = try await callUnaryJSON(
            method: "GitUnstageFile",
            body: ["cascadeId": .string(cascadeId), "filePath": .string(filePath)]
        )
    }

    public func gitDiscardFile(cascadeId: String, filePath: String) async throws {
        _ = try await callUnaryJSON(
            method: "GitDiscardFile",
            body: ["cascadeId": .string(cascadeId), "filePath": .string(filePath)]
        )
    }

    public func gitCommitChanges(cascadeId: String, draft: GitCommitDraft) async throws -> GitCommitResult {
        let res = try await callUnaryJSON(
            method: "GitCommit",
            body: [
                "cascadeId": .string(cascadeId),
                "message": .string(draft.message),
                "includeUnstaged": .bool(draft.includeUnstaged),
                "amend": .bool(draft.amend)
            ]
        )
        return GitCommitResult(
            commitSha: res["commitSha"]?.stringValue ?? String(UUID().uuidString.prefix(7)).lowercased(),
            commitMessage: res["commitMessage"]?.stringValue ?? draft.message,
            branchName: res["branchName"]?.stringValue ?? "main",
            pushed: res["pushed"]?.boolValue ?? false
        )
    }

    public func gitPushBranch(cascadeId: String, branchName: String) async throws -> Bool {
        let res = try await callUnaryJSON(
            method: "GitPush",
            body: ["cascadeId": .string(cascadeId), "branchName": .string(branchName)]
        )
        return res["pushed"]?.boolValue ?? res["ok"]?.boolValue ?? true
    }

    public func fetchConversationOverview(cascadeId: String) async throws -> ConversationOverviewSnapshot {
        let res = try await callUnaryJSON(
            method: "GetConversationOverview",
            body: ["cascadeId": .string(cascadeId)]
        )
        let subagents: [SubagentPayload] = (res["subagents"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue else { return nil }
            return SubagentPayload(
                subagentId: obj["subagentId"]?.stringValue ?? obj["id"]?.stringValue ?? UUID().uuidString,
                role: obj["role"]?.stringValue ?? "Subagent",
                typeName: obj["typeName"]?.stringValue ?? "self",
                modelLabel: obj["modelLabel"]?.stringValue ?? "Gemini 4 Hydrogen",
                status: CortexStepStatus.from(jsonName: obj["status"]?.stringValue ?? "IN_PROGRESS"),
                summary: obj["summary"]?.stringValue ?? "",
                waitingApprovalTitle: obj["waitingApprovalTitle"]?.stringValue
            )
        }
        let bgTasks: [BackgroundTaskItem] = (res["backgroundTasks"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue else { return nil }
            return BackgroundTaskItem(
                id: obj["id"]?.stringValue ?? UUID().uuidString,
                title: obj["title"]?.stringValue ?? "Background Task",
                commandSummary: obj["commandSummary"]?.stringValue ?? "",
                status: CortexStepStatus.from(jsonName: obj["status"]?.stringValue ?? "IN_PROGRESS"),
                elapsedLabel: obj["elapsedLabel"]?.stringValue ?? "running",
                canCancel: obj["canCancel"]?.boolValue ?? true
            )
        }
        let goals: [ConversationGoalItem] = (res["goals"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue else { return nil }
            return ConversationGoalItem(
                id: obj["id"]?.stringValue ?? UUID().uuidString,
                title: obj["title"]?.stringValue ?? "Goal",
                status: CortexStepStatus.from(jsonName: obj["status"]?.stringValue ?? "IN_PROGRESS"),
                progressText: obj["progressText"]?.stringValue ?? "Active"
            )
        }
        let prs: [GitHubPullRequestInfo] = (res["pullRequests"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue,
                  let repo = obj["ownerRepo"]?.stringValue,
                  let num = obj["number"]?.intValue else { return nil }
            return GitHubPullRequestInfo(
                ownerRepo: repo,
                number: num,
                title: obj["title"]?.stringValue ?? "PR #\(num)",
                state: GitHubPullRequestInfo.PRState(rawValue: (obj["state"]?.stringValue ?? "open").lowercased()) ?? .open,
                checksSummary: obj["checksSummary"]?.stringValue ?? "Checks passing",
                url: obj["url"]?.stringValue ?? "https://github.com/\(repo)/pull/\(num)",
                additions: obj["additions"]?.intValue ?? 0,
                deletions: obj["deletions"]?.intValue ?? 0
            )
        }
        let modifiedFiles = (res["modifiedFiles"]?.arrayValue ?? []).compactMap(\.stringValue)
        let docLinks = (res["documentLinks"]?.arrayValue ?? []).compactMap(\.stringValue)

        return ConversationOverviewSnapshot(
            reviewAdditions: res["reviewAdditions"]?.intValue ?? 0,
            reviewDeletions: res["reviewDeletions"]?.intValue ?? 0,
            modifiedFiles: modifiedFiles,
            subagents: subagents,
            backgroundTasks: bgTasks,
            goals: goals,
            artifacts: [],
            documentLinks: docLinks,
            pullRequests: prs
        )
    }

    public func cancelBackgroundTask(cascadeId: String, taskId: String) async throws {
        _ = try await callUnaryJSON(
            method: "CancelBackgroundTask",
            body: ["cascadeId": .string(cascadeId), "taskId": .string(taskId)]
        )
    }

    public func stopSubagent(cascadeId: String, subagentId: String) async throws {
        _ = try await callUnaryJSON(
            method: "StopSubagent",
            body: ["cascadeId": .string(cascadeId), "subagentId": .string(subagentId)]
        )
    }

    public func sendSideQuestion(
        cascadeId: String,
        question: String,
        threadId: String
    ) async throws -> SideQuestionMessage {
        let res = try await callUnaryJSON(
            method: "SendSideQuestion",
            body: [
                "cascadeId": .string(cascadeId),
                "threadId": .string(threadId),
                "question": .string(question)
            ]
        )
        let answer = Self.nonEmptyString(res["answer"]?.stringValue)
            ?? Self.nonEmptyString(res["response"]?.stringValue)
            ?? "Read-only side answer for: \(question)"
        return SideQuestionMessage(isUser: false, text: answer)
    }

    public func revertConversationToStep(cascadeId: String, stepIndex: Int) async throws {
        _ = try await callUnaryJSON(
            method: "RevertConversationToStep",
            body: [
                "cascadeId": .string(cascadeId),
                "stepIndex": .int(stepIndex)
            ]
        )
    }

    public func setConversationPermissionPreset(cascadeId: String, preset: AgentPermissionPreset) async throws {
        _ = try await callUnaryJSON(
            method: "SetPermissionPreset",
            body: [
                "cascadeId": .string(cascadeId),
                "preset": .string(preset.wireValue),
                "label": .string(preset.rawValue)
            ]
        )
    }

    public func fetchCustomizationsCatalog() async throws -> CustomizationsCatalog {
        let res = try await callUnaryJSON(method: "GetCustomizationsCatalog", body: [:])
        let skills: [SkillSummary] = (res["skills"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue, let name = obj["name"]?.stringValue else { return nil }
            return SkillSummary(
                name: name,
                description: obj["description"]?.stringValue ?? "",
                scope: obj["scope"]?.stringValue ?? "Workspace",
                isEnabled: obj["isEnabled"]?.boolValue ?? true
            )
        }
        let rules: [RuleSummary] = (res["rules"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue, let name = obj["name"]?.stringValue else { return nil }
            return RuleSummary(
                name: name,
                scope: obj["scope"]?.stringValue ?? "Workspace",
                preview: obj["preview"]?.stringValue ?? "",
                isActive: obj["isActive"]?.boolValue ?? true
            )
        }
        let agents = (res["customAgents"]?.arrayValue ?? []).compactMap(\.stringValue)
        let servers: [McpServerStatusItem] = (res["mcpServers"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue, let name = obj["name"]?.stringValue else { return nil }
            let state = McpServerStatusItem.ConnectionState(rawValue: (obj["state"]?.stringValue ?? "connected").lowercased()) ?? .connected
            return McpServerStatusItem(
                name: name,
                transport: obj["transport"]?.stringValue ?? "stdio",
                state: state,
                toolCount: obj["toolCount"]?.intValue ?? 0,
                errorMessage: obj["errorMessage"]?.stringValue,
                missingCommandHint: obj["missingCommandHint"]?.stringValue,
                oauthConnected: obj["oauthConnected"]?.boolValue ?? true
            )
        }
        let plugins: [PluginCatalogItem] = (res["plugins"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue,
                  let id = obj["id"]?.stringValue,
                  let name = obj["name"]?.stringValue else { return nil }
            return PluginCatalogItem(
                id: id,
                name: name,
                provider: obj["provider"]?.stringValue ?? name,
                description: obj["description"]?.stringValue ?? "",
                isInstalled: obj["isInstalled"]?.boolValue ?? false,
                isEnabled: obj["isEnabled"]?.boolValue ?? true,
                isFeaturedPartner: obj["isFeaturedPartner"]?.boolValue ?? false,
                accountSignedIn: obj["accountSignedIn"]?.boolValue ?? false,
                mcpStartupError: obj["mcpStartupError"]?.stringValue,
                suggestedPrompts: (obj["suggestedPrompts"]?.arrayValue ?? []).compactMap(\.stringValue)
            )
        }
        let hooks: [LifecycleHookItem] = (res["hooks"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue,
                  let eventName = obj["eventName"]?.stringValue,
                  let cmd = obj["command"]?.stringValue else { return nil }
            return LifecycleHookItem(
                id: obj["id"]?.stringValue ?? UUID().uuidString,
                eventName: eventName,
                matcher: obj["matcher"]?.stringValue ?? "*",
                command: cmd,
                timeoutSeconds: obj["timeoutSeconds"]?.intValue ?? 60,
                isValid: obj["isValid"]?.boolValue ?? true
            )
        }
        if skills.isEmpty && rules.isEmpty && servers.isEmpty && plugins.isEmpty {
            return CustomizationsCatalog.defaultCatalog
        }
        return CustomizationsCatalog(
            skills: skills,
            rules: rules,
            customAgents: agents.isEmpty ? ["Default"] : agents,
            mcpServers: servers,
            plugins: plugins,
            hooks: hooks
        )
    }

    public func restartMcpServer(serverName: String) async throws {
        _ = try await callUnaryJSON(
            method: "RestartMcpServer",
            body: ["serverName": .string(serverName)]
        )
    }

    public func togglePlugin(pluginId: String, isEnabled: Bool) async throws {
        _ = try await callUnaryJSON(
            method: "TogglePlugin",
            body: ["pluginId": .string(pluginId), "isEnabled": .bool(isEnabled)]
        )
    }

    public func installMarketplacePlugin(pluginId: String) async throws {
        _ = try await callUnaryJSON(
            method: "InstallPlugin",
            body: ["pluginId": .string(pluginId)]
        )
    }

    public func searchAllConversations(query: String) async throws -> [CascadeSummary] {
        let res = try await callUnaryJSON(
            method: "SearchAllConversations",
            body: ["query": .string(query)]
        )
        guard let list = res["trajectories"]?.arrayValue ?? res["results"]?.arrayValue else {
            return []
        }
        let now = Date()
        return list.compactMap { item -> CascadeSummary? in
            guard let obj = item.objectValue,
                  let id = obj["cascadeId"]?.stringValue,
                  let title = obj["title"]?.stringValue else { return nil }
            return CascadeSummary(
                cascadeId: id,
                title: title,
                projectSlug: obj["projectSlug"]?.stringValue ?? "workspace",
                workspaceUri: obj["workspaceUri"]?.stringValue ?? "",
                branchName: obj["branchName"]?.stringValue ?? "main",
                status: CortexStepStatus.from(jsonName: obj["status"]?.stringValue ?? "DONE"),
                stepCount: obj["stepCount"]?.intValue ?? 0,
                updatedAt: now,
                relativeTimeLabel: obj["relativeTimeLabel"]?.stringValue ?? "now",
                statusSubtitle: obj["snippet"]?.stringValue ?? obj["statusSubtitle"]?.stringValue ?? ""
            )
        }
    }

    // MARK: - Server-Streaming Envelope Subscription

    private static func hasBase64TransferHeader(_ headers: [AnyHashable: Any]) -> Bool {
        headers.contains { key, val in
            let lowerKey = String(describing: key).lowercased()
            guard lowerKey == "x-goog-safety-encoding" || lowerKey == "content-transfer-encoding" else {
                return false
            }
            return String(describing: val).lowercased().contains("base64")
        }
    }

    private static func extractConnectEndStreamError(from data: Data, decoder: JSONDecoder) -> String? {
        guard !data.isEmpty,
              let obj = try? decoder.decode([String: JSONValue].self, from: data) else {
            return nil
        }
        if let errObj = obj["error"]?.objectValue {
            let code = nonEmptyString(errObj["code"]?.stringValue)
            let msg = nonEmptyString(errObj["message"]?.stringValue)
            if code != nil || msg != nil {
                return [code, msg].compactMap { $0 }.joined(separator: ": ")
            }
        }
        if let code = nonEmptyString(obj["code"]?.stringValue),
           let msg = nonEmptyString(obj["message"]?.stringValue) {
            return "\(code): \(msg)"
        }
        return nil
    }

    /// Subscribes to a Connect-RPC server-streaming method (`JetboxSubscribeToSummaries`, `StreamCascadeReactiveUpdates`, etc.)
    public func subscribeEnvelopeStream(
        method: String,
        requestPayload: [String: JSONValue] = [:],
        instanceUuidOverride: String? = nil,
        allowCrossInstanceFailover: Bool = true
    ) throws -> AsyncThrowingStream<[String: JSONValue], Error> {
        let rawJSON = requestPayload.isEmpty ? Data("{}".utf8) : try JSONEncoder().encode(requestPayload)
        let framedPayload = ConnectEnvelopeFrame(flags: [], payload: rawJSON).encode()

        if channel == .cloudRelay {
            var effectiveUuid = (instanceUuidOverride?.isEmpty == false) ? instanceUuidOverride : resolvedInstanceUuid
            if allowCrossInstanceFailover,
               let candidate = effectiveUuid,
               !cachedRelayInstances.isEmpty,
               !cachedRelayInstances.contains(where: { $0.uuid == candidate && $0.status.isReachable }),
               let fallbackOnline = cachedRelayInstances.first(where: { $0.status.isReachable }) {
                let preferredResolved = resolvedInstanceUuid.flatMap { resUuid in
                    cachedRelayInstances.contains(where: { $0.uuid == resUuid && $0.status.isReachable }) ? resUuid : nil
                }
                effectiveUuid = preferredResolved ?? fallbackOnline.uuid
            }
            guard let targetUuid = effectiveUuid, !targetUuid.isEmpty else {
                return AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
            let originStr = SAPISIDHashGenerator.normalizeOrigin(relayOriginURL.absoluteString)
            guard var comps = URLComponents(string: "\(originStr)\(SAPISIDHashGenerator.apiServicePrefix)/StreamProxyCommand") else {
                throw AntigravityRPCError.invalidEndpoint
            }
            comps.queryItems = [URLQueryItem(name: "$unique", value: "\(method)-\(UUID().uuidString.prefix(8))")]
            guard let relayURL = comps.url else {
                throw AntigravityRPCError.invalidEndpoint
            }
            var relayRequest = URLRequest(url: relayURL)
            relayRequest.httpMethod = "POST"
            relayRequest.timeoutInterval = 300
            SAPISIDHashGenerator.applyApiServiceHeaders(
                to: &relayRequest,
                cookieHeader: sessionCookie ?? "",
                origin: originStr,
                authUser: authUser,
                isStreaming: true
            )
            relayRequest.httpBody = try CloudRelayJSPBCodec.encodeProxyCommandRequest(
                targetInstanceUuid: targetUuid,
                rpcPath: "\(Self.servicePrefix)/\(method)",
                payload: framedPayload,
                contentType: "application/connect+json",
                isStreaming: true
            )

            let session = self.streamingURLSession
            let immutableRelayReq = relayRequest
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let (bytes, response) = try await session.bytes(for: immutableRelayReq)
                        guard let http = response as? HTTPURLResponse else {
                            throw AntigravityRPCError.invalidEndpoint
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
                                            if let errMsg = Self.extractConnectEndStreamError(from: frameBytes, decoder: decoder) {
                                                throw AntigravityRPCError.httpError(statusCode: 400, body: errMsg)
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
                        throw AntigravityRPCError.httpError(
                            statusCode: http.statusCode,
                            body: "Stream HTTP \(http.statusCode)"
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
                                if let errMsg = Self.extractConnectEndStreamError(from: frameBytes, decoder: decoder) {
                                    throw AntigravityRPCError.httpError(statusCode: 400, body: errMsg)
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

    private func applyAuthHeaders(to request: inout URLRequest) {
        if let csrfToken, !csrfToken.isEmpty {
            request.setValue(csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        }
        if let sessionCookie, !sessionCookie.isEmpty {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
    }

    // MARK: - JSON Step Decoder (`language_server` + Companion Schema)

    private static func nonEmptyString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : raw
    }

    private static func resolveStepType(_ typeName: String) -> CortexStepType {
        if let exact = CortexStepType.allCases.first(where: { $0.jsonName == typeName }) {
            return exact
        }
        let upper = typeName.uppercased()
        if upper.contains("USER_INPUT") { return .userInput }
        if upper.contains("PLANNER_RESPONSE") { return .plannerResponse }
        if upper.contains("NOTIFY_USER") { return .notifyUser }
        if upper.contains("TASK_BOUNDARY") { return .taskBoundary }
        if upper.contains("SEND_COMMAND_INPUT") { return .sendCommandInput }
        if upper.contains("COMMAND_STATUS") { return .commandStatus }
        if upper.contains("RUN_COMMAND") || upper.contains("SHELL_EXEC") { return .runCommand }
        if upper.contains("VIEW_CONTENT_CHUNK") { return .viewContentChunk }
        if upper.contains("VIEW_FILE") || upper.contains("VIEW_CODE") { return .viewFile }
        if upper.contains("GREP_SEARCH") || upper.contains("FIND_BY_NAME") || upper.contains("SEARCH") { return .search }
        if upper.contains("LIST_DIRECTORY") { return .listDirectory }
        if upper.contains("READ_URL_CONTENT") { return .readUrlContent }
        if upper.contains("BROWSER_SUBAGENT") || upper.contains("BROWSER_") { return .browserSubagent }
        if upper.contains("SUBAGENT") { return .subagentInvocation }
        if upper.contains("WORKFLOW") { return .dynamicWorkflow }
        if upper.contains("SWARM") { return .swarmBoard }
        if upper.contains("MCP") { return .mcpToolCall }
        if upper.contains("CHECKPOINT") { return .checkpoint }
        if upper.contains("EPHEMERAL_MESSAGE") { return .ephemeralMessage }
        if upper.contains("CODE_ACTION")
            || upper.contains("REPLACE_FILE")
            || upper.contains("MULTI_REPLACE_FILE")
            || upper.contains("WRITE_TO_FILE")
            || upper.contains("FILE_CHANGE")
            || upper.contains("PROPOSE_CODE") {
            return .codeAction
        }
        return .unspecified
    }

    private static func extractReadableSummary(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let s = nonEmptyString(value.stringValue) {
            return s
        }
        guard let obj = value.objectValue else { return nil }
        let preferredKeys = [
            "proposedCommandLine", "commandLine", "command", "input",
            "absolutePathUri", "fileUri", "targetFileUri", "path", "target",
            "url", "domain", "question", "title", "reason", "description",
            "message", "action", "toolName", "serverName", "summary", "query"
        ]
        for key in preferredKeys {
            if let s = nonEmptyString(obj[key]?.stringValue) {
                return s
            }
        }
        for key in obj.keys.sorted() {
            if let s = nonEmptyString(obj[key]?.stringValue) {
                return s
            }
        }
        return nil
    }

    private static func decodePersistSuggestionType(_ value: JSONValue?) -> PersistSuggestionType {
        if let raw = value?.intValue, let parsed = PersistSuggestionType(rawValue: raw) {
            return parsed
        }
        if let str = value?.stringValue?.uppercased() {
            if str.contains("BLOCKED") { return .blocked }
            if str.contains("SUGGESTED") { return .suggested }
            if str.contains("UNSPECIFIED") { return .unspecified }
        }
        return .suggested
    }

    private static func decodeJSONRequestedInteraction(
        _ reqInt: [String: JSONValue],
        fallbackCommandLine: String?,
        fallbackCwd: String?
    ) -> RequestedInteraction? {
        if let rcInt = (reqInt["runCommand"] ?? reqInt["run_command"])?.objectValue {
            let cmd = nonEmptyString(rcInt["proposedCommandLine"]?.stringValue)
                ?? nonEmptyString(rcInt["commandLine"]?.stringValue)
                ?? nonEmptyString(rcInt["command"]?.stringValue)
                ?? fallbackCommandLine
                ?? ""
            let cwd = nonEmptyString(rcInt["cwd"]?.stringValue)
                ?? fallbackCwd
                ?? "~"
            return RequestedInteraction(
                kind: .runCommand,
                runCommand: RunCommandInteractionSpec(
                    proposedCommandLine: cmd,
                    cwd: cwd,
                    isDaemon: rcInt["isDaemon"]?.boolValue ?? false
                ),
                rawMemberKey: "runCommand"
            )
        }
        if let permInt = reqInt["permission"]?.objectValue {
            let action = nonEmptyString(permInt["action"]?.stringValue)
                ?? nonEmptyString(permInt["toolName"]?.stringValue)
                ?? nonEmptyString(permInt["permissionType"]?.stringValue)
                ?? "tool"
            let pattern = nonEmptyString(permInt["suggestedPersistPattern"]?.stringValue)
                ?? nonEmptyString(permInt["persistPattern"]?.stringValue)
            let targetKeys = ["target", "resource", "path", "absolutePathUri", "command"]
            var resolvedTarget: String? = nil
            for key in targetKeys {
                if let candidate = nonEmptyString(permInt[key]?.stringValue) {
                    resolvedTarget = candidate
                    break
                }
            }
            let target = resolvedTarget ?? pattern ?? "*"
            let reason = nonEmptyString(permInt["reason"]?.stringValue)
                ?? nonEmptyString(permInt["description"]?.stringValue)
                ?? nonEmptyString(permInt["message"]?.stringValue)
            let plugin = nonEmptyString(permInt["pluginName"]?.stringValue)
                ?? nonEmptyString(permInt["serverName"]?.stringValue)
            let persistType = decodePersistSuggestionType(permInt["persistSuggestionType"])
            return RequestedInteraction(
                kind: .permission,
                permission: PermissionInteractionSpec(
                    action: action,
                    target: target,
                    suggestedPersistPattern: pattern ?? target,
                    persistSuggestionType: persistType,
                    reason: reason,
                    pluginName: plugin,
                    toolIconName: nonEmptyString(permInt["toolIconName"]?.stringValue)
                ),
                pluginName: plugin,
                rawMemberKey: "permission",
                rawSummary: reason ?? "\(action)(\(target))"
            )
        }
        if let fpInt = (reqInt["filePermission"] ?? reqInt["file_permission"])?.objectValue {
            let uri = nonEmptyString(fpInt["absolutePathUri"]?.stringValue)
                ?? nonEmptyString(fpInt["fileUri"]?.stringValue)
                ?? nonEmptyString(fpInt["absolutePath"]?.stringValue)
                ?? nonEmptyString(fpInt["path"]?.stringValue)
                ?? ""
            return RequestedInteraction(
                kind: .filePermission,
                filePermission: FilePermissionInteractionSpec(
                    absolutePathUri: uri,
                    isDirectory: fpInt["isDirectory"]?.boolValue ?? false,
                    blockReason: nonEmptyString(fpInt["blockReason"]?.stringValue)
                        ?? nonEmptyString(fpInt["reason"]?.stringValue)
                ),
                rawMemberKey: "filePermission",
                rawSummary: uri.isEmpty ? nil : uri
            )
        }
        if let qaInt = (reqInt["askQuestion"] ?? reqInt["ask_question"] ?? reqInt["elicitation"])?.objectValue {
            let isElicitation = (reqInt["askQuestion"] == nil && reqInt["ask_question"] == nil && reqInt["elicitation"] != nil)
            let primaryQ = qaInt["questions"]?.arrayValue?.first?.objectValue ?? qaInt
            let rawOptions = primaryQ["options"]?.arrayValue ?? []
            let options: [String] = rawOptions.compactMap { item in
                if let s = nonEmptyString(item.stringValue) { return s }
                if let o = item.objectValue {
                    return nonEmptyString(o["label"]?.stringValue)
                        ?? nonEmptyString(o["text"]?.stringValue)
                        ?? nonEmptyString(o["title"]?.stringValue)
                        ?? nonEmptyString(o["value"]?.stringValue)
                }
                return nil
            }
            let questionText = nonEmptyString(primaryQ["question"]?.stringValue)
                ?? nonEmptyString(qaInt["question"]?.stringValue)
                ?? nonEmptyString(qaInt["prompt"]?.stringValue)
                ?? nonEmptyString(qaInt["message"]?.stringValue)
                ?? "Input required"
            return RequestedInteraction(
                kind: isElicitation ? .elicitation : .askQuestion,
                askQuestion: AskQuestionInteractionSpec(
                    question: questionText,
                    options: options,
                    isMultiSelect: primaryQ["isMultiSelect"]?.boolValue ?? qaInt["isMultiSelect"]?.boolValue ?? false
                ),
                rawMemberKey: isElicitation ? "elicitation" : "askQuestion",
                rawSummary: questionText
            )
        }
        if let mcpInt = reqInt["mcp"]?.objectValue {
            let server = nonEmptyString(mcpInt["serverName"]?.stringValue)
                ?? nonEmptyString(mcpInt["mcpServerName"]?.stringValue)
                ?? "mcp-server"
            let tool = nonEmptyString(mcpInt["toolName"]?.stringValue)
                ?? nonEmptyString(mcpInt["mcpToolName"]?.stringValue)
                ?? "invoke_tool"
            let plugin = nonEmptyString(mcpInt["pluginName"]?.stringValue)
            return RequestedInteraction(
                kind: .mcp,
                mcpServerName: server,
                mcpToolName: tool,
                pluginName: plugin,
                rawMemberKey: "mcp",
                rawSummary: "\(server): \(tool)"
            )
        }
        if let sciInt = (reqInt["sendCommandInput"] ?? reqInt["send_command_input"])?.objectValue {
            let summary = nonEmptyString(sciInt["input"]?.stringValue)
                ?? nonEmptyString(sciInt["commandLine"]?.stringValue)
                ?? nonEmptyString(sciInt["commandId"]?.stringValue)
            return RequestedInteraction(
                kind: .sendCommandInput,
                rawMemberKey: "sendCommandInput",
                rawSummary: summary
            )
        }
        if let dlInt = (reqInt["downloadUrl"] ?? reqInt["download_url"])?.objectValue {
            let url = nonEmptyString(dlInt["url"]?.stringValue) ?? ""
            let origin = nonEmptyString(dlInt["origin"]?.stringValue) ?? (URL(string: url)?.host ?? "external")
            let fileName = nonEmptyString(dlInt["fileName"]?.stringValue) ?? (URL(string: url)?.lastPathComponent ?? "download")
            return RequestedInteraction(
                kind: .downloadUrl,
                downloadUrl: DownloadUrlInteractionSpec(
                    url: url,
                    origin: origin,
                    fileName: fileName,
                    mimeType: nonEmptyString(dlInt["mimeType"]?.stringValue) ?? "application/octet-stream",
                    destinationFolder: nonEmptyString(dlInt["destinationFolder"]?.stringValue) ?? "~/Downloads"
                ),
                rawMemberKey: "downloadUrl"
            )
        }
        if let upInt = (reqInt["browserUpload"] ?? reqInt["browser_upload"])?.objectValue {
            let origin = nonEmptyString(upInt["origin"]?.stringValue) ?? "external site"
            let files = upInt["fileNames"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return RequestedInteraction(
                kind: .browserUpload,
                browserUpload: BrowserUploadInteractionSpec(origin: origin, fileNames: files),
                rawMemberKey: "browserUpload"
            )
        }
        if let wfInt = (reqInt["workflowScript"] ?? reqInt["workflow_script"])?.objectValue {
            return RequestedInteraction(
                kind: .workflowScript,
                workflowScript: WorkflowScriptInteractionSpec(
                    title: nonEmptyString(wfInt["title"]?.stringValue) ?? "Dynamic Workflow",
                    pythonScript: nonEmptyString(wfInt["pythonScript"]?.stringValue) ?? "",
                    phaseNames: wfInt["phaseNames"]?.arrayValue?.compactMap(\.stringValue) ?? []
                ),
                rawMemberKey: "workflowScript"
            )
        }
        let browserMembers: [(String, RequestedInteraction.MemberKind)] = [
            ("executeUrl", .executeUrl),
            ("openBrowserUrl", .openBrowserUrl),
            ("browserAction", .browserAction),
            ("executeBrowserJavascript", .executeBrowserJavascript),
            ("captureBrowserScreenshot", .captureBrowserScreenshot),
            ("clickBrowserPixel", .clickBrowserPixel),
            ("openBrowserSetup", .openBrowserSetup),
            ("confirmBrowserSetup", .confirmBrowserSetup)
        ]
        for (key, kind) in browserMembers {
            if let bObj = reqInt[key]?.objectValue {
                let url = nonEmptyString(bObj["url"]?.stringValue) ?? ""
                let domain = nonEmptyString(bObj["domain"]?.stringValue)
                    ?? URL(string: url)?.host
                    ?? (url.isEmpty ? nil : url)
                return RequestedInteraction(
                    kind: kind,
                    executeUrl: url.isEmpty ? nil : ExecuteUrlInteractionSpec(
                        url: url,
                        domain: domain ?? "external site",
                        isRedirect: bObj["isRedirect"]?.boolValue ?? false
                    ),
                    rawMemberKey: key,
                    rawSummary: extractReadableSummary(from: .object(bObj))
                )
            }
        }
        if let readUrlObj = reqInt["readUrlContent"]?.objectValue {
            return RequestedInteraction(
                kind: .readUrlContent,
                rawMemberKey: "readUrlContent",
                rawSummary: nonEmptyString(readUrlObj["url"]?.stringValue)
                    ?? extractReadableSummary(from: .object(readUrlObj))
            )
        }
        if let deployVal = reqInt["deploy"] {
            return RequestedInteraction(
                kind: .deploy,
                rawMemberKey: "deploy",
                rawSummary: extractReadableSummary(from: deployVal)
            )
        }
        if let extVal = reqInt["runExtensionCode"] {
            return RequestedInteraction(
                kind: .runExtensionCode,
                rawMemberKey: "runExtensionCode",
                rawSummary: extractReadableSummary(from: extVal)
            )
        }
        if let appVal = reqInt["approvalInteraction"] {
            return RequestedInteraction(
                kind: .approvalInteraction,
                rawMemberKey: "approvalInteraction",
                rawSummary: extractReadableSummary(from: appVal)
            )
        }
        // Preserve any unrecognized future server interaction oneof key verbatim
        let ignoredMetaKeys: Set<String> = ["trajectoryId", "stepIndex", "id", "metadata"]
        if let unknownKey = reqInt.keys.sorted().first(where: { !ignoredMetaKeys.contains($0) }) {
            let memberVal = reqInt[unknownKey]
            return RequestedInteraction(
                kind: .approvalInteraction,
                rawMemberKey: unknownKey,
                rawSummary: extractReadableSummary(from: memberVal)
            )
        }
        return nil
    }

    private static func parseDurationSeconds(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        if let d = value.doubleValue { return d }
        if let obj = value.objectValue {
            let secs = obj["seconds"]?.doubleValue ?? Double(obj["seconds"]?.stringValue ?? "") ?? 0
            let nanos = obj["nanos"]?.doubleValue ?? Double(obj["nanos"]?.stringValue ?? "") ?? 0
            let total = secs + (nanos / 1_000_000_000.0)
            return total > 0 ? total : nil
        }
        if let str = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let numeric = str.hasSuffix("s") ? String(str.dropLast()) : str
            return Double(numeric)
        }
        return nil
    }

    public static func decodeJSONStep(
        _ value: JSONValue,
        cascadeId: String,
        fallbackIndex: Int
    ) -> CascadeStep? {
        guard let obj = value.objectValue else { return nil }
        let stepIndex = obj["stepIndex"]?.intValue ?? fallbackIndex
        var stepType: CortexStepType = {
            if let typeName = obj["type"]?.stringValue, !typeName.isEmpty {
                return resolveStepType(typeName)
            }
            if let typeInt = obj["type"]?.intValue {
                return ProtobufStepCodec.decodeStepType(typeInt)
            }
            return .unspecified
        }()
        let stepStatus: CortexStepStatus = {
            if let statusName = obj["status"]?.stringValue, !statusName.isEmpty {
                return CortexStepStatus.from(jsonName: statusName)
            }
            if let statusInt = obj["status"]?.intValue {
                return ProtobufStepCodec.decodeStepStatus(statusInt)
            }
            return .done
        }()

        // Decode userInput (string or nested object `{"userResponse": ...}` / `{"items": [{"text": ...}]}`)
        var userText: String? = nonEmptyString(obj["userInput"]?.stringValue)
        var mentions: [String] = obj["attachedMentions"]?.arrayValue?.compactMap(\.stringValue) ?? []
        var recordedMode: CascadeExecutionMode?
        var recordedModelId: String?

        if let uiObj = obj["userInput"]?.objectValue {
            let itemsJoined = uiObj["items"]?.arrayValue?
                .compactMap { nonEmptyString($0.objectValue?["text"]?.stringValue) }
                .joined(separator: "\n")
            userText = nonEmptyString(uiObj["userResponse"]?.stringValue)
                ?? nonEmptyString(uiObj["query"]?.stringValue)
                ?? nonEmptyString(uiObj["text"]?.stringValue)
                ?? nonEmptyString(uiObj["prompt"]?.stringValue)
                ?? nonEmptyString(uiObj["message"]?.stringValue)
                ?? nonEmptyString(itemsJoined)
            if let itemArr = uiObj["items"]?.arrayValue {
                for item in itemArr {
                    if let fileObj = item.objectValue?["item"]?.objectValue?["file"]?.objectValue {
                        if let fileLabel = nonEmptyString(fileObj["label"]?.stringValue) {
                            if !mentions.contains(fileLabel) { mentions.append(fileLabel) }
                        } else if let uri = nonEmptyString(fileObj["absoluteUri"]?.stringValue) {
                            let base = (uri.replacingOccurrences(of: "file://", with: "") as NSString).lastPathComponent
                            let chip = base.hasPrefix("@") ? base : "@\(base)"
                            if !base.isEmpty && !mentions.contains(chip) { mentions.append(chip) }
                        }
                    }
                }
            }
            if let userCfg = (uiObj["userConfig"] ?? uiObj["lastUserConfig"])?.objectValue,
               let plannerCfg = userCfg["plannerConfig"]?.objectValue {
                if let convObj = plannerCfg["conversational"]?.objectValue {
                    if let agentic = convObj["agenticMode"]?.boolValue {
                        recordedMode = agentic ? .planning : .fast
                    }
                }
                let reqModelObj = plannerCfg["requestedModel"]?.objectValue
                recordedModelId = nonEmptyString(reqModelObj?["model"]?.stringValue)
                    ?? nonEmptyString(reqModelObj?["alias"]?.stringValue)
                    ?? nonEmptyString(plannerCfg["planModel"]?.stringValue)
                if recordedModelId == "MODEL_UNSPECIFIED" {
                    recordedModelId = nil
                }
            }
            if stepType == .unspecified && (userText != nil || !mentions.isEmpty) {
                stepType = .userInput
            }
        }

        // Decode plannerResponse & notifyUser
        var plannerPayload: PlannerResponsePayload?
        if let pr = obj["plannerResponse"]?.objectValue {
            let text = nonEmptyString(pr["modifiedResponse"]?.stringValue)
                ?? nonEmptyString(pr["response"]?.stringValue)
                ?? nonEmptyString(pr["text"]?.stringValue)
                ?? nonEmptyString(pr["content"]?.stringValue)
                ?? nonEmptyString(pr["message"]?.stringValue)
                ?? ""
            let thinking = nonEmptyString(pr["thinking"]?.stringValue)
            let duration = parseDurationSeconds(pr["thinkingDurationSeconds"] ?? pr["thinkingDuration"])
            if !text.isEmpty || thinking != nil || stepStatus == .inProgress || stepStatus == .pending {
                plannerPayload = PlannerResponsePayload(
                    response: text,
                    thinking: thinking,
                    thinkingDurationSeconds: duration
                )
                if stepType == .unspecified {
                    stepType = .plannerResponse
                }
            }
        } else if let nu = obj["notifyUser"]?.objectValue {
            let notifyText = nonEmptyString(nu["notificationContent"]?.stringValue)
                ?? nonEmptyString(nu["message"]?.stringValue)
                ?? nonEmptyString(nu["reviewContent"]?.stringValue)
            let paths = (nu["pathsToReview"]?.arrayValue ?? nu["reviewAbsoluteUris"]?.arrayValue)?
                .compactMap(\.stringValue) ?? []
            if notifyText != nil || !paths.isEmpty {
                plannerPayload = PlannerResponsePayload(
                    response: notifyText ?? "Ready for your review.",
                    referencedFiles: paths
                )
                stepType = .notifyUser
            }
        }

        // Decode runCommand / shellExec + sendCommandInput + requestedInteraction
        var runCmdPayload: RunCommandPayload?
        var interaction: RequestedInteraction?
        if let rc = (obj["runCommand"] ?? obj["shellExec"])?.objectValue {
            let cmdLine = nonEmptyString(rc["commandLine"]?.stringValue)
                ?? nonEmptyString(rc["proposedCommandLine"]?.stringValue)
                ?? nonEmptyString(rc["command"]?.stringValue)
                ?? nonEmptyString(rc["CommandLine"]?.stringValue)
                ?? ""
            let cwd = nonEmptyString(rc["cwd"]?.stringValue)
                ?? nonEmptyString(rc["Cwd"]?.stringValue)
                ?? "~"
            if !cmdLine.isEmpty {
                runCmdPayload = RunCommandPayload(
                    commandId: rc["commandId"]?.stringValue ?? "cmd-\(stepIndex)",
                    commandLine: cmdLine,
                    proposedCommandLine: nonEmptyString(rc["proposedCommandLine"]?.stringValue) ?? cmdLine,
                    cwd: cwd,
                    exitCode: rc["exitCode"]?.intValue,
                    outputPreview: nonEmptyString(rc["combinedOutput"]?.objectValue?["full"]?.stringValue)
                        ?? nonEmptyString(rc["outputPreview"]?.stringValue)
                        ?? nonEmptyString(rc["output"]?.stringValue)
                )
                if stepType == .unspecified {
                    stepType = .runCommand
                }
            }
        } else if let sci = obj["sendCommandInput"]?.objectValue {
            let inputText = nonEmptyString(sci["input"]?.stringValue)
                ?? nonEmptyString(sci["commandLine"]?.stringValue)
                ?? ""
            if !inputText.isEmpty {
                runCmdPayload = RunCommandPayload(
                    commandId: sci["commandId"]?.stringValue ?? "stdin-\(stepIndex)",
                    commandLine: inputText,
                    proposedCommandLine: inputText,
                    cwd: "~"
                )
            }
            if stepType == .unspecified {
                stepType = .sendCommandInput
            }
        }

        if let reqInt = obj["requestedInteraction"]?.objectValue {
            interaction = decodeJSONRequestedInteraction(
                reqInt,
                fallbackCommandLine: runCmdPayload?.proposedCommandLine ?? runCmdPayload?.commandLine,
                fallbackCwd: runCmdPayload?.cwd
            )
            if interaction?.kind == .runCommand, let spec = interaction?.runCommand {
                if runCmdPayload == nil {
                    runCmdPayload = RunCommandPayload(
                        commandId: "cmd-\(stepIndex)",
                        commandLine: spec.proposedCommandLine,
                        proposedCommandLine: spec.proposedCommandLine,
                        cwd: spec.cwd
                    )
                } else if runCmdPayload?.commandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
                          !spec.proposedCommandLine.isEmpty {
                    runCmdPayload?.commandLine = spec.proposedCommandLine
                    runCmdPayload?.proposedCommandLine = spec.proposedCommandLine
                }
            }
        }

        if interaction == nil && (stepStatus == .waiting || stepStatus == .blocked),
           let rc = runCmdPayload,
           stepType == .runCommand {
            interaction = RequestedInteraction(
                kind: .runCommand,
                runCommand: RunCommandInteractionSpec(
                    proposedCommandLine: rc.proposedCommandLine ?? rc.commandLine,
                    cwd: rc.cwd
                ),
                rawMemberKey: "runCommand"
            )
        }

        var viewFilePayload: ViewFilePayload?
        let vfCandidate = obj["viewFile"]?.objectValue
            ?? obj["viewFileOutline"]?.objectValue
            ?? obj["viewCodeItem"]?.objectValue
        if let vf = vfCandidate,
           let uri = nonEmptyString(vf["fileUri"]?.stringValue)
            ?? nonEmptyString(vf["absolutePathUri"]?.stringValue)
            ?? nonEmptyString(vf["absolutePath"]?.stringValue)
            ?? nonEmptyString(vf["path"]?.stringValue) {
            var capturedViewContent: String? = nil
            if ResolvedEmbedResource.isEmbeddableTextArtifactPath(uri),
               let rawContent = nonEmptyString(vf["content"]?.stringValue),
               rawContent.utf8.count <= 524_288 {
                capturedViewContent = rawContent
            }
            viewFilePayload = ViewFilePayload(
                fileUri: uri,
                startLine: vf["startLine"]?.intValue ?? 1,
                endLine: vf["endLine"]?.intValue ?? 120,
                fileContent: capturedViewContent
            )
            if stepType == .unspecified { stepType = .viewFile }
        } else if let ld = obj["listDirectory"]?.objectValue,
                  let uri = nonEmptyString(ld["directoryPathUri"]?.stringValue)
                    ?? nonEmptyString(ld["directoryPath"]?.stringValue)
                    ?? nonEmptyString(ld["absolutePathUri"]?.stringValue)
                    ?? nonEmptyString(ld["path"]?.stringValue) {
            viewFilePayload = ViewFilePayload(fileUri: uri, startLine: 1, endLine: 1)
            if stepType == .unspecified { stepType = .listDirectory }
        }

        var searchPayload: SearchPayload?
        let searchCandidate = obj["grepSearch"]?.objectValue
            ?? obj["findByName"]?.objectValue
            ?? obj["search"]?.objectValue
        if let sc = searchCandidate {
            let query = nonEmptyString(sc["query"]?.stringValue)
                ?? nonEmptyString(sc["pattern"]?.stringValue)
                ?? "workspace"
            let scope = nonEmptyString(sc["searchPath"]?.stringValue)
                ?? nonEmptyString(sc["searchDirectory"]?.stringValue)
                ?? nonEmptyString(sc["searchPathUri"]?.stringValue)
                ?? "."
            let count = sc["results"]?.arrayValue?.count ?? sc["matchCount"]?.intValue ?? 0
            searchPayload = SearchPayload(query: query, scopeDirectory: scope, matchCount: count)
            if stepType == .unspecified { stepType = .search }
        }

        var codeActionPayload: CodeActionPayload?
        let caCandidate: [String: JSONValue]? = [
            obj["codeAction"],
            obj["replaceFileContent"],
            obj["multiReplaceFileContent"],
            obj["writeToFile"],
            obj["fileChange"]
        ].compactMap { $0?.objectValue }.first
        if let ca = caCandidate {
            let actionSpec = ca["actionSpec"]?.objectValue
            let createFileSpec = actionSpec?["createFile"]?.objectValue
            let directUriKeys = [
                "targetFileUri", "fileUri", "targetFile", "TargetFile",
                "absoluteUri", "absolutePathUri", "absolutePath", "filePath", "path"
            ]
            var uri: String? = nil
            for key in directUriKeys {
                if let candidate = nonEmptyString(ca[key]?.stringValue) {
                    uri = candidate
                    break
                }
            }
            if uri == nil {
                let specObjects: [[String: JSONValue]?] = [
                    createFileSpec,
                    actionSpec?["insertBlock"]?.objectValue,
                    actionSpec?["editFile"]?.objectValue,
                    actionSpec?["replaceFileContent"]?.objectValue
                ]
                for spec in specObjects {
                    if let candidate = nonEmptyString(spec?["path"]?.objectValue?["absoluteUri"]?.stringValue) {
                        uri = candidate
                        break
                    }
                }
            }
            if let uri {
                let lowerUri = uri.lowercased()
                let isArtifact = (ca["artifactMetadata"] != nil)
                    || (ca["isArtifactFile"]?.boolValue == true)
                    || lowerUri.contains("/.gemini/")
                    || lowerUri.contains("/brain/")
                var capturedContent: String? = nil
                if isArtifact || ResolvedEmbedResource.isEmbeddableTextArtifactPath(uri) {
                    let directCandidates: [String?] = [
                        ca["codeContent"]?.stringValue,
                        ca["content"]?.stringValue,
                        ca["fileContent"]?.stringValue,
                        createFileSpec?["codeContent"]?.stringValue,
                        createFileSpec?["content"]?.stringValue,
                        createFileSpec?["fileContent"]?.stringValue,
                        createFileSpec?["instruction"]?.stringValue
                    ]
                    for cand in directCandidates {
                        if let c = nonEmptyString(cand), c.utf8.count <= 524_288 {
                            capturedContent = c
                            break
                        }
                    }
                    // Fallback: reconstruct newly created artifact content from `actionResult.edit.diff.unifiedDiff.lines`
                    if capturedContent == nil,
                       let diffLines = ca["actionResult"]?.objectValue?["edit"]?.objectValue?["diff"]?.objectValue?["unifiedDiff"]?.objectValue?["lines"]?.arrayValue {
                        var addedLines: [String] = []
                        var hasRemoved = false
                        for lineItem in diffLines {
                            if let lineObj = lineItem.objectValue {
                                let lineText = lineObj["text"]?.stringValue ?? ""
                                let kind = (lineObj["type"]?.stringValue ?? "").uppercased()
                                if kind.contains("DELETE") || kind.contains("REMOVE") {
                                    hasRemoved = true
                                } else {
                                    addedLines.append(lineText)
                                }
                            } else if let rawLine = lineItem.stringValue {
                                if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                                    addedLines.append(String(rawLine.dropFirst()))
                                } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                                    hasRemoved = true
                                }
                            }
                        }
                        if !hasRemoved && !addedLines.isEmpty {
                            let joined = addedLines.joined(separator: "\n")
                            if joined.utf8.count <= 524_288 {
                                capturedContent = joined
                            }
                        }
                    }
                }

                codeActionPayload = CodeActionPayload(
                    targetFileUri: uri,
                    description: nonEmptyString(ca["description"]?.stringValue)
                        ?? nonEmptyString(ca["instruction"]?.stringValue)
                        ?? "Updated file",
                    additions: ca["additions"]?.intValue ?? 0,
                    deletions: ca["deletions"]?.intValue ?? 0,
                    isArtifactFile: isArtifact,
                    fileContent: capturedContent
                )
                if stepType == .unspecified { stepType = .codeAction }
            }
        }

        // Decode generateImage / readUrlContent / browserSubagent into lightweight display payloads
        if plannerPayload == nil {
            if let genImg = obj["generateImage"]?.objectValue {
                let imgPath = nonEmptyString(genImg["imagePath"]?.stringValue)
                    ?? nonEmptyString(genImg["outputPath"]?.stringValue)
                    ?? nonEmptyString(genImg["savedPath"]?.stringValue)
                    ?? nonEmptyString(genImg["artifactUri"]?.stringValue)
                let prompt = nonEmptyString(genImg["prompt"]?.stringValue) ?? "Generated image"
                if let imgPath {
                    let fileURI = imgPath.contains("://") ? imgPath : "file://\(imgPath)"
                    plannerPayload = PlannerResponsePayload(
                        response: "![\(prompt)](\(fileURI))",
                        referencedFiles: [fileURI]
                    )
                    stepType = .generateImage
                }
            } else if let readUrl = obj["readUrlContent"]?.objectValue {
                let targetUrl = nonEmptyString(readUrl["url"]?.stringValue) ?? nonEmptyString(readUrl["uri"]?.stringValue)
                if let targetUrl {
                    plannerPayload = PlannerResponsePayload(response: targetUrl)
                    stepType = .readUrlContent
                }
            } else if let browser = obj["browserSubagent"]?.objectValue {
                let taskSummary = nonEmptyString(browser["taskName"]?.stringValue)
                    ?? nonEmptyString(browser["task"]?.stringValue)
                    ?? "Browser automation task"
                plannerPayload = PlannerResponsePayload(response: taskSummary)
                stepType = .browserSubagent
            }
        }

        var taskBoundaryPayload: TaskBoundaryPayload?
        if let tb = obj["taskBoundary"]?.objectValue {
            taskBoundaryPayload = TaskBoundaryPayload(
                taskName: nonEmptyString(tb["taskName"]?.stringValue) ?? "Task",
                taskStatus: nonEmptyString(tb["taskStatus"]?.stringValue) ?? "",
                taskSummary: nonEmptyString(tb["taskSummary"]?.stringValue) ?? "",
                completedCount: tb["completedCount"]?.intValue ?? 0,
                totalCount: tb["totalCount"]?.intValue ?? 0,
                elapsedLabel: nonEmptyString(tb["elapsedLabel"]?.stringValue) ?? ""
            )
            if stepType == .unspecified { stepType = .taskBoundary }
        }

        var subagentPayload: SubagentPayload?
        if let sub = (obj["subagentInvocation"] ?? obj["subagent"])?.objectValue {
            subagentPayload = SubagentPayload(
                subagentId: nonEmptyString(sub["subagentId"]?.stringValue) ?? "sub-\(stepIndex)",
                role: nonEmptyString(sub["role"]?.stringValue) ?? "Subagent",
                typeName: nonEmptyString(sub["typeName"]?.stringValue) ?? "self",
                modelLabel: nonEmptyString(sub["modelLabel"]?.stringValue) ?? "Gemini 4 Hydrogen",
                status: stepStatus,
                summary: nonEmptyString(sub["summary"]?.stringValue) ?? "",
                waitingApprovalTitle: nonEmptyString(sub["waitingApprovalTitle"]?.stringValue)
            )
            if stepType == .unspecified { stepType = .subagentInvocation }
        }

        var dynamicWorkflowPayload: DynamicWorkflowPayload?
        if let wf = obj["dynamicWorkflow"]?.objectValue {
            let phaseNames = wf["phaseNames"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let phases = phaseNames.enumerated().map { idx, name in
                WorkflowPhaseItem(id: "phase-\(idx)", name: name, isCompleted: false)
            }
            dynamicWorkflowPayload = DynamicWorkflowPayload(
                workflowId: nonEmptyString(wf["workflowId"]?.stringValue) ?? "wf-\(stepIndex)",
                description: nonEmptyString(wf["description"]?.stringValue) ?? "Dynamic Workflow",
                pythonScript: nonEmptyString(wf["pythonScript"]?.stringValue) ?? "",
                currentPhase: nonEmptyString(wf["currentPhase"]?.stringValue) ?? phaseNames.first ?? "Phase 1",
                completedAgents: wf["completedAgents"]?.intValue ?? 0,
                totalAgents: wf["totalAgents"]?.intValue ?? max(1, phases.count),
                phases: phases,
                requiresScriptApproval: stepStatus == .waiting || stepStatus == .blocked
            )
            if stepType == .unspecified { stepType = .dynamicWorkflow }
        }

        var swarmBoardPayload: SwarmBoardPayload?
        if let sw = obj["swarmBoard"]?.objectValue {
            let memberNames = sw["memberNames"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let members = memberNames.map { SwarmMemberItem(name: $0, role: "Specialist", status: stepStatus) }
            swarmBoardPayload = SwarmBoardPayload(
                swarmId: nonEmptyString(sw["swarmId"]?.stringValue) ?? "swarm-\(stepIndex)",
                title: nonEmptyString(sw["title"]?.stringValue) ?? "Swarm Team",
                status: stepStatus,
                members: members,
                posts: []
            )
            if stepType == .unspecified { stepType = .swarmBoard }
        }

        var mcpToolCallPayload: McpToolCallPayload?
        if let mcp = (obj["mcpToolCall"] ?? obj["mcp"])?.objectValue {
            mcpToolCallPayload = McpToolCallPayload(
                serverName: nonEmptyString(mcp["serverName"]?.stringValue) ?? "mcp",
                toolName: nonEmptyString(mcp["toolName"]?.stringValue) ?? "tool",
                pluginName: nonEmptyString(mcp["pluginName"]?.stringValue),
                argumentsPreview: nonEmptyString(mcp["argumentsPreview"]?.stringValue) ?? "{}",
                resultPreview: nonEmptyString(mcp["resultPreview"]?.stringValue),
                isError: stepStatus == .error
            )
            if stepType == .unspecified { stepType = .mcpToolCall }
        }

        if (stepType == .plannerResponse || stepType == .notifyUser)
            && plannerPayload == nil
            && (stepStatus == .inProgress || stepStatus == .pending) {
            plannerPayload = PlannerResponsePayload(response: "")
        }

        let createdDate = Self.parseProtoTimestamp(obj["metadata"]?.objectValue?["createdAt"] ?? obj["createdAt"]) ?? Date()

        return CascadeStep(
            cascadeId: cascadeId,
            stepIndex: stepIndex,
            type: stepType,
            status: stepStatus,
            createdAt: createdDate,
            userInput: userText,
            attachedMentions: mentions,
            plannerResponse: plannerPayload,
            taskBoundary: taskBoundaryPayload,
            runCommand: runCmdPayload,
            codeAction: codeActionPayload,
            viewFile: viewFilePayload,
            search: searchPayload,
            requestedInteraction: interaction,
            recordedExecutionMode: recordedMode,
            recordedModelId: recordedModelId,
            subagent: subagentPayload,
            dynamicWorkflow: dynamicWorkflowPayload,
            swarmBoard: swarmBoardPayload,
            mcpToolCall: mcpToolCallPayload
        )
    }

    // MARK: - Live Desktop Summary & Timestamp Helpers

    /// Decodes a single entry from `GetAllCascadeTrajectories.trajectorySummaries` or `JetboxSubscribeToSummaries.updates`,
    /// filtering out blank 0-step unused Desktop tabs and computing accurate Cloud/local/`No Project`/unread/status fields.
    public static func decodeTrajectorySummaryEntry(
        cascadeId: String,
        value: JSONValue,
        now: Date = Date(),
        forceCloud: Bool = false
    ) -> CascadeSummary? {
        guard let obj = value.objectValue else { return nil }
        let annotations = obj["annotations"]?.objectValue ?? obj["conversationAnnotations"]?.objectValue
        let trajMeta = obj["trajectoryMetadata"]?.objectValue

        let candidateTitles: [String?] = [
            annotations?["title"]?.stringValue,
            annotations?["customTitle"]?.stringValue,
            annotations?["name"]?.stringValue,
            obj["summary"]?.stringValue,
            obj["title"]?.stringValue,
            obj["displayName"]?.stringValue,
            obj["name"]?.stringValue,
            trajMeta?["title"]?.stringValue,
            trajMeta?["summary"]?.stringValue,
            trajMeta?["name"]?.stringValue,
            obj["firstUserInput"]?.stringValue,
            obj["query"]?.stringValue
        ]
        let resolvedTitle = candidateTitles
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        let stepCount = obj["stepCount"]?.intValue
            ?? Int(obj["stepCount"]?.stringValue ?? "")
            ?? 0

        let projectIdCandidates: [String?] = [
            trajMeta?["projectId"]?.stringValue,
            trajMeta?["project_id"]?.stringValue,
            obj["projectId"]?.stringValue,
            obj["project_id"]?.stringValue,
            annotations?["projectId"]?.stringValue,
            obj["projectEnvConfig"]?.objectValue?["projectId"]?.stringValue,
            obj["metadata"]?.objectValue?["projectId"]?.stringValue
        ]
        let cloudProjectId = projectIdCandidates.compactMap(Self.nonEmptyString).first
        let explicitCloudBool = (obj["cloud"]?.boolValue == true)
            || (obj["isCloud"]?.boolValue == true)
            || (trajMeta?["isCloud"]?.boolValue == true)

        let statusValue = obj["status"] ?? obj["runStatus"] ?? obj["cascadeRunStatus"]
        let statusRaw = statusValue?.stringValue ?? "CASCADE_RUN_STATUS_IDLE"
        var status: CortexStepStatus
        if let statusCode = statusValue?.intValue {
            status = CortexStepStatus.from(cascadeRunStatusCode: statusCode)
        } else {
            status = CortexStepStatus.from(jsonName: statusRaw)
        }
        if status == .unspecified {
            if obj["waitingForUser"]?.boolValue == true
                || obj["hasPendingInteraction"]?.boolValue == true
                || obj["needsUserAction"]?.boolValue == true {
                status = .waiting
            } else if obj["isRunning"]?.boolValue == true || obj["running"]?.boolValue == true {
                status = .inProgress
            }
        }
        let isActiveRun = status == .inProgress || status == .pending || status == .waiting

        // Antigravity Desktop keeps unused 0-step local New Chat placeholders in `trajectorySummaries`
        // without a title/summary and hides them in its sidebar. Filter them out cleanly (unless Cloud or active).
        if resolvedTitle == nil && stepCount == 0 && !explicitCloudBool && !forceCloud && !isActiveRun {
            return nil
        }
        let title = resolvedTitle ?? "New Conversation"
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("ios connect-rpc handshake")
            || lowerTitle.contains("reply in one short sentence confirming ios connect-rpc handshake") {
            return nil
        }

        let workspaceObjects = (obj["workspaces"]?.arrayValue ?? []).compactMap(\.objectValue)
        let allMetaUris = trajMeta?["workspaceUris"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let directWsUri = obj["workspaceUri"]?.stringValue
        let allCandidateUris: [String] = workspaceObjects.compactMap {
            $0["workspaceFolderAbsoluteUri"]?.stringValue ?? $0["workspaceUri"]?.stringValue
        } + allMetaUris + [directWsUri].compactMap { $0 }
        let hasCloudWorkspaceEntry = allCandidateUris.contains { AntigravityCloudDetector.isCloudWorkspaceURI($0) }

        let selectedWorkspace = Self.selectPrimaryWorkspaceObject(from: workspaceObjects)
        let metaWorkspaceUri = allMetaUris.first {
            !AntigravityCloudDetector.isGenericContainerURI($0)
        }
        let primaryWsUri: String? = selectedWorkspace?["workspaceFolderAbsoluteUri"]?.stringValue
            ?? selectedWorkspace?["workspaceUri"]?.stringValue
        let rawUri: String = [primaryWsUri, metaWorkspaceUri, directWsUri]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !AntigravityCloudDetector.isGenericContainerURI($0) })
            ?? ""

        let sourceHint = [
            obj["source"]?.stringValue,
            obj["runtime"]?.stringValue,
            obj["backend"]?.stringValue,
            trajMeta?["runtime"]?.stringValue,
            trajMeta?["environment"]?.stringValue,
            trajMeta?["executionEnvironment"]?.stringValue,
            trajMeta?["source"]?.stringValue
        ]
            .compactMap { $0 }
            .joined(separator: " ")

        let isForceCloudContainerPath: Bool = {
            guard forceCloud else { return false }
            let lowerRaw = (rawUri.removingPercentEncoding ?? rawUri).lowercased()
            return lowerRaw.hasPrefix("file:///workspace/")
                || lowerRaw.hasPrefix("file:///workspaces/")
                || lowerRaw.hasPrefix("file:///root/")
        }()

        let isCloud = explicitCloudBool
            || hasCloudWorkspaceEntry
            || isForceCloudContainerPath
            || AntigravityCloudDetector.isCloudWorkspaceURI(rawUri, cascadeId: cascadeId, sourceHint: sourceHint)

        let isScratchPlayground = AntigravityCloudDetector.isPlaygroundScratchURI(rawUri)
        let isUnassigned = (cloudProjectId ?? "").isEmpty && (rawUri.isEmpty || isScratchPlayground)

        let uri: String
        if isUnassigned {
            uri = isScratchPlayground ? rawUri : ""
        } else if rawUri.isEmpty, let cpid = cloudProjectId, !cpid.isEmpty {
            uri = "cloud://\(cpid)"
        } else {
            uri = AntigravityCloudDetector.normalizeWorkspaceURI(rawUri, isCloud: isCloud)
        }

        let explicitSlug = (obj["projectSlug"]?.stringValue ?? obj["project"]?.stringValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let slug: String
        if let explicitSlug, !explicitSlug.isEmpty, !AntigravityCloudDetector.isNoProjectSlug(explicitSlug) {
            slug = explicitSlug
        } else if isUnassigned {
            slug = AntigravityCloudDetector.noProjectDisplayName
        } else if rawUri.isEmpty, let cpid = cloudProjectId, !cpid.isEmpty {
            slug = cpid
        } else if rawUri.hasPrefix("cloud://") {
            let trimmedCloud = rawUri.replacingOccurrences(of: "cloud://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            slug = trimmedCloud.isEmpty || AntigravityCloudDetector.isNoProjectSlug(trimmedCloud)
                ? (cloudProjectId ?? AntigravityCloudDetector.noProjectDisplayName)
                : trimmedCloud
        } else if rawUri.hasPrefix("https://github.com/") {
            let trimmedGH = rawUri.replacingOccurrences(of: "https://github.com/", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            slug = trimmedGH.isEmpty ? AntigravityCloudDetector.noProjectDisplayName : trimmedGH
        } else if rawUri.contains("://") && !rawUri.hasPrefix("file://") {
            let decodedRaw = rawUri.removingPercentEncoding ?? rawUri
            let lastComp = ((URL(string: decodedRaw)?.path ?? decodedRaw) as NSString).lastPathComponent
            slug = lastComp.isEmpty || AntigravityCloudDetector.isNoProjectSlug(lastComp)
                ? (cloudProjectId ?? AntigravityCloudDetector.noProjectDisplayName)
                : lastComp
        } else {
            let cleanPath = (rawUri.removingPercentEncoding ?? rawUri)
                .replacingOccurrences(of: "file://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let lastComp = (cleanPath as NSString).lastPathComponent
            if !lastComp.isEmpty && !AntigravityCloudDetector.isNoProjectSlug(lastComp) {
                slug = lastComp
            } else {
                slug = cloudProjectId ?? AntigravityCloudDetector.noProjectDisplayName
            }
        }

        let branch: String
        if isUnassigned {
            branch = ""
        } else {
            branch = selectedWorkspace?["gitBranch"]?.stringValue
                ?? selectedWorkspace?["branchName"]?.stringValue
                ?? obj["branchName"]?.stringValue
                ?? "main"
        }

        let candidateUpdateDates: [Date] = [
            Self.parseProtoTimestamp(obj["lastModifiedTime"]),
            Self.parseProtoTimestamp(obj["updatedAt"]),
            Self.parseProtoTimestamp(obj["lastStepTime"]),
            Self.parseProtoTimestamp(obj["lastAgentReplyTime"]),
            Self.parseProtoTimestamp(
                obj["latestNotifyUserStep"]?.objectValue?["step"]?.objectValue?["metadata"]?.objectValue?["createdAt"]
            ),
            Self.parseProtoTimestamp(
                obj["latestTaskBoundaryStep"]?.objectValue?["step"]?.objectValue?["metadata"]?.objectValue?["createdAt"]
            )
        ].compactMap { $0 }
        let updatedDate = candidateUpdateDates.max() ?? Self.parseProtoTimestamp(obj["createdTime"])
        let lastViewedCandidates: [JSONValue?] = [
            annotations?["lastUserViewTime"],
            annotations?["last_user_view_time"],
            annotations?["lastViewedTime"],
            annotations?["lastReadTime"],
            obj["lastUserViewTime"],
            obj["last_user_view_time"],
            obj["lastViewedTime"],
            trajMeta?["lastUserViewTime"]
        ]
        let lastViewedDate = lastViewedCandidates.compactMap { Self.parseProtoTimestamp($0) }.first
        let updatedAt = updatedDate ?? now
        let relativeLabel = Self.formatRelativeTimeLabel(from: updatedDate, now: now)

        let unreadCandidates: [Bool?] = [
            obj["isUnread"]?.boolValue,
            obj["unread"]?.boolValue,
            obj["hasUnread"]?.boolValue,
            obj["hasUnreadMessages"]?.boolValue,
            obj["hasUnseenUpdates"]?.boolValue,
            obj["unseen"]?.boolValue,
            annotations?["isUnread"]?.boolValue,
            annotations?["unread"]?.boolValue,
            annotations?["hasUnread"]?.boolValue,
            trajMeta?["unread"]?.boolValue,
            trajMeta?["isUnread"]?.boolValue
        ]
        let explicitUnread: Bool? = unreadCandidates.compactMap { $0 }.first

        let isUnread: Bool
        if let explicitUnread {
            isUnread = explicitUnread
        } else if status == .inProgress || status == .pending {
            isUnread = false
        } else if let updatedDate, let lastViewedDate {
            isUnread = updatedDate.timeIntervalSince(lastViewedDate) > 0.5
                || statusRaw.uppercased() == "CASCADE_RUN_STATUS_DONE"
                || status == .waiting
        } else {
            isUnread = statusRaw.uppercased() == "CASCADE_RUN_STATUS_DONE" || status == .waiting
        }

        let isPinned = obj["isPinned"]?.boolValue
            ?? annotations?["pinned"]?.boolValue
            ?? annotations?["isPinned"]?.boolValue
            ?? false
        let isArchived = obj["isArchived"]?.boolValue
            ?? annotations?["archived"]?.boolValue
            ?? annotations?["isArchived"]?.boolValue
            ?? false

        let explicitSubtitle = obj["statusSubtitle"]?.stringValue
        let subtitle = Self.buildLiveStatusSubtitle(
            status: status,
            stepCount: stepCount,
            isUnread: isUnread,
            explicitSubtitle: explicitSubtitle
        )

        return CascadeSummary(
            cascadeId: cascadeId,
            title: title,
            projectSlug: slug.isEmpty ? AntigravityCloudDetector.noProjectDisplayName : slug,
            workspaceUri: uri,
            branchName: branch,
            status: status,
            stepCount: stepCount,
            currentStepIndex: max(1, stepCount),
            totalSteps: max(1, stepCount),
            updatedAt: updatedAt,
            relativeTimeLabel: relativeLabel,
            statusSubtitle: subtitle,
            isPinned: isPinned,
            isArchived: isArchived,
            isUnread: isUnread,
            isCloud: isCloud,
            cloudProjectId: cloudProjectId,
            originHostName: isCloud ? "Antigravity" : nil,
            lastUserViewTime: lastViewedDate
        )
    }

    private static func selectPrimaryWorkspaceObject(
        from workspaces: [[String: JSONValue]]
    ) -> [String: JSONValue]? {
        guard !workspaces.isEmpty else { return nil }
        for entry in workspaces {
            let raw = (entry["workspaceFolderAbsoluteUri"]?.stringValue ?? entry["workspaceUri"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !AntigravityCloudDetector.isGenericContainerURI(raw) else { continue }
            let lower = raw.lowercased()
            if lower.hasPrefix("cloud://")
                || lower.hasPrefix("vscode-remote://")
                || lower.hasPrefix("vscode-vfs://")
                || lower.hasPrefix("https://github.com/") {
                return entry
            }
        }
        for entry in workspaces {
            let raw = (entry["workspaceFolderAbsoluteUri"]?.stringValue ?? entry["workspaceUri"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !AntigravityCloudDetector.isGenericContainerURI(raw) else { continue }
            return entry
        }
        return nil
    }

    /// Parses Protobuf `google.protobuf.Timestamp` values encoded either as RFC3339 strings
    /// (including 1–9 fractional nanosecond digits) or `{"seconds": ..., "nanos": ...}` objects.
    public static func parseProtoTimestamp(_ value: JSONValue?) -> Date? {
        guard let value else { return nil }

        if let tsObj = value.objectValue {
            let secs: Double? = tsObj["seconds"]?.doubleValue
                ?? Double(tsObj["seconds"]?.stringValue ?? "")
            if let secs {
                let nanos = tsObj["nanos"]?.doubleValue
                    ?? Double(tsObj["nanos"]?.stringValue ?? "")
                    ?? 0
                return Date(timeIntervalSince1970: secs + (nanos / 1_000_000_000.0))
            }
            return nil
        }

        guard let rawString = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawString.isEmpty else {
            return nil
        }

        if let dotIdx = rawString.firstIndex(of: ".") {
            let fracStart = rawString.index(after: dotIdx)
            var fracEnd = fracStart
            while fracEnd < rawString.endIndex && rawString[fracEnd].isNumber {
                fracEnd = rawString.index(after: fracEnd)
            }
            let digits = rawString[fracStart..<fracEnd]
            if !digits.isEmpty {
                let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
                let normalized = "\(rawString[..<dotIdx]).\(millis)\(rawString[fracEnd...])"
                let fracFormatter = ISO8601DateFormatter()
                fracFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = fracFormatter.date(from: normalized) {
                    return parsed
                }
            }
        }

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        return plainFormatter.date(from: rawString)
    }

    /// Formats a compact mobile relative timestamp (`now`, `8m`, `2h`, `Yesterday`, `4d`, `2w`).
    public static func formatRelativeTimeLabel(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "now" }
        let delta = max(0, now.timeIntervalSince(date))
        if delta < 60 {
            return "now"
        } else if delta < 3_600 {
            return "\(Int(delta / 60))m"
        } else if delta < 86_400 {
            return "\(Int(delta / 3_600))h"
        } else if delta < 172_800 {
            return "Yesterday"
        } else if delta < 604_800 {
            return "\(Int(delta / 86_400))d"
        } else {
            return "\(Int(delta / 604_800))w"
        }
    }

    public static func buildLiveStatusSubtitle(
        status: CortexStepStatus,
        stepCount: Int,
        isUnread: Bool,
        explicitSubtitle: String? = nil
    ) -> String {
        if let explicitSubtitle, !explicitSubtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitSubtitle
        }
        switch status {
        case .inProgress:
            return stepCount > 0 ? "Running · Step \(stepCount)" : "Running..."
        case .pending:
            return "Queued · Waiting to start"
        case .waiting, .blocked:
            return "Needs review · Waiting on you"
        case .error:
            return stepCount > 0 ? "Error · Step \(stepCount)" : "Error"
        case .cancelled:
            return stepCount > 0 ? "Stopped · \(stepCount) steps" : "Stopped"
        case .done:
            if isUnread {
                return stepCount > 0 ? "Done · New reply · \(stepCount) steps" : "Done · New reply"
            }
            return stepCount > 0 ? "Done · \(stepCount) steps" : "Done"
        case .unspecified:
            if isUnread {
                return stepCount > 0 ? "New reply · \(stepCount) steps" : "New reply"
            }
            return stepCount > 0 ? "Idle · \(stepCount) steps" : "Idle"
        }
    }
}
