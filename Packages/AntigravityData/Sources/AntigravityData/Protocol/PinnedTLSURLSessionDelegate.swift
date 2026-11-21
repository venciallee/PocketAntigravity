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

    public init(
        latencyMs: Int,
        availableRelayInstances: [RelayInstanceInfo] = [],
        activeRelayInstance: RelayInstanceInfo? = nil,
        relayTopologyChanged: Bool = false
    ) {
        self.latencyMs = latencyMs
        self.availableRelayInstances = availableRelayInstances
        self.activeRelayInstance = activeRelayInstance
        self.relayTopologyChanged = relayTopologyChanged
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
