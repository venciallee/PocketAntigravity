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
    public let isSelectedHostOnline: Bool
    public let hostCapabilities: HostCapabilityProfile

    public init(
        latencyMs: Int,
        workspaces: [WorkspaceInfo],
        summaries: [CascadeSummary],
        cloudProjects: [ProjectWorkspace] = [],
        serverVersion: String = "",
        resolvedHostname: String? = nil,
        resolvedInstanceUuid: String? = nil,
        resolvedAuthUser: String? = nil,
        availableRelayInstances: [RelayInstanceInfo] = [],
        isSelectedHostOnline: Bool = true,
        hostCapabilities: HostCapabilityProfile = HostCapabilityProfile()
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
        self.isSelectedHostOnline = isSelectedHostOnline
        self.hostCapabilities = hostCapabilities
    }
}

/// Lightweight heartbeat / reachability result returned by `AntigravityRPCClient.probeHostReachability()`.
public struct HostReachabilityProbeResult: Sendable, Equatable {
    public let latencyMs: Int
    public let availableRelayInstances: [RelayInstanceInfo]
    public let activeRelayInstance: RelayInstanceInfo?
    public let relayTopologyChanged: Bool
    public let relayMetadataChanged: Bool
    public let isSelectedHostOnline: Bool

    public init(
        latencyMs: Int,
        availableRelayInstances: [RelayInstanceInfo] = [],
        activeRelayInstance: RelayInstanceInfo? = nil,
        relayTopologyChanged: Bool = false,
        relayMetadataChanged: Bool = false,
        isSelectedHostOnline: Bool = true
    ) {
        self.latencyMs = latencyMs
        self.availableRelayInstances = availableRelayInstances
        self.activeRelayInstance = activeRelayInstance
        self.relayTopologyChanged = relayTopologyChanged
        self.relayMetadataChanged = relayMetadataChanged
        self.isSelectedHostOnline = isSelectedHostOnline
    }
}

/// Scoped workspace & summary synchronization outcome returned by `fetchScopedWorkspacesAndSummaries(target:)`.
public struct ScopedWorkspaceSyncResult: Sendable, Equatable {
    public let workspaces: [WorkspaceInfo]
    public let summaries: [CascadeSummary]
    public let cloudProjects: [ProjectWorkspace]
    public let cloudWarmingUp: Bool
    public let relayInstances: [RelayInstanceInfo]
    public let refreshedLocalHostUuids: Set<String>
    public let refreshedLocalHostNames: Set<String>
    public let refreshedCloud: Bool
    public let targetReachable: Bool
    public let latencyMs: Int

    public init(
        workspaces: [WorkspaceInfo],
        summaries: [CascadeSummary],
        cloudProjects: [ProjectWorkspace] = [],
        cloudWarmingUp: Bool = false,
        relayInstances: [RelayInstanceInfo] = [],
        refreshedLocalHostUuids: Set<String> = [],
        refreshedLocalHostNames: Set<String> = [],
        refreshedCloud: Bool = false,
        targetReachable: Bool = true,
        latencyMs: Int = 0
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
