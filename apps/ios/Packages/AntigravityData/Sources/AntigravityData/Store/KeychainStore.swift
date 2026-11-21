import Foundation
#if canImport(Security)
import Security
#endif

/// Persisted Remote Control / Direct LAN login credentials stored strictly in iOS Keychain.
public struct SavedBackendCredentials: Codable, Sendable, Equatable {
    public var endpointURLString: String
    public var channel: RemoteConnectionChannel
    public var hostname: String
    public var csrfToken: String?
    public var sessionCookie: String?
    public var authUser: String?
    public var resolvedInstanceUuid: String?
    public var relayApiKey: String?
    public var certFingerprintSHA256: String?
    public var pairedAt: Date

    public init(
        endpointURLString: String,
        channel: RemoteConnectionChannel,
        hostname: String,
        csrfToken: String? = nil,
        sessionCookie: String? = nil,
        authUser: String? = nil,
        resolvedInstanceUuid: String? = nil,
        relayApiKey: String? = nil,
        certFingerprintSHA256: String? = nil,
        pairedAt: Date = Date()
    ) {
        self.endpointURLString = endpointURLString
        self.channel = channel
        self.hostname = hostname
        self.csrfToken = csrfToken
        self.sessionCookie = sessionCookie
        self.authUser = authUser
        self.resolvedInstanceUuid = resolvedInstanceUuid
        self.relayApiKey = relayApiKey
        self.certFingerprintSHA256 = certFingerprintSHA256
        self.pairedAt = pairedAt
    }
}

/// Non-secret host display & routing metadata persisted in `UserDefaults` so cold launches can enter
/// the Conversations screen on Frame 0 (`<1ms`) without waiting for async Keychain or network I/O.
/// Never stores cookies, CSRF tokens, API keys, or TLS certificate secrets.
public struct PairedHostLaunchHint: Codable, Sendable, Equatable {
    public var instanceId: String
    public var hostname: String
    public var channel: RemoteConnectionChannel
    public var endpointURLString: String

    public init(
        instanceId: String,
        hostname: String,
        channel: RemoteConnectionChannel,
        endpointURLString: String
    ) {
        self.instanceId = instanceId
        self.hostname = hostname
        self.channel = channel
        self.endpointURLString = endpointURLString
    }

    public init(credentials: SavedBackendCredentials) {
        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(credentials.endpointURLString)
        let resolvedId: String = {
            if let uuid = credentials.resolvedInstanceUuid?.trimmingCharacters(in: .whitespacesAndNewlines), !uuid.isEmpty {
                return uuid
            }
            if let parsedId = parsedTarget?.instanceId, !parsedId.isEmpty {
                return parsedId
            }
            if credentials.channel == .directHost, let host = URL(string: credentials.endpointURLString)?.host {
                return "direct-\(host)"
            }
            return credentials.hostname
        }()
        self.instanceId = resolvedId
        self.hostname = credentials.hostname
        self.channel = credentials.channel
        self.endpointURLString = credentials.endpointURLString
    }
}

/// Isolates sensitive Remote Control credentials (Google OAuth session cookie,
/// `x-codeium-csrf-token`, and TLS certificate SHA-256 pins) in iOS Keychain.
/// Credentials are never written to `UserDefaults` or App Group shared containers.
public actor KeychainStore: SecretStore {
    public static let shared = KeychainStore()
    public static let serviceIdentifier = "com.antigravity.ios.remotecontrol"
    private static let activeCredentialsAccount = "active_backend_credentials_v2"
    private static let relayWebApiKeyPrefix = "relay_web_api_key_v1::"

    private var memoryFallback: [String: String] = [:]

    public init() {}

    public func storeSecret(_ value: String, forKey key: String) {
        memoryFallback[key] = value
        #if canImport(Security)
        guard let secretData = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = secretData
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(attributes as CFDictionary, nil)
        #endif
    }

    public func readSecret(forKey key: String) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        #endif
        return memoryFallback[key]
    }

    public func removeSecret(forKey key: String) {
        memoryFallback.removeValue(forKey: key)
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        #endif
    }

    public func saveCredentials(_ credentials: SavedBackendCredentials) {
        guard let encoded = try? JSONEncoder().encode(credentials),
              let json = String(data: encoded, encoding: .utf8) else { return }
        storeSecret(json, forKey: Self.activeCredentialsAccount)
    }

    public func loadCredentials() -> SavedBackendCredentials? {
        guard let json = readSecret(forKey: Self.activeCredentialsAccount),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SavedBackendCredentials.self, from: data)
    }

    public func clearCredentials() {
        removeSecret(forKey: Self.activeCredentialsAccount)
    }

    public func saveRelayWebApiKey(_ apiKey: String, forOrigin origin: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let account = Self.relayWebApiKeyPrefix + SAPISIDHashGenerator.normalizeOrigin(origin)
        storeSecret(trimmed, forKey: account)
    }

    public func loadRelayWebApiKey(forOrigin origin: String) -> String? {
        let account = Self.relayWebApiKeyPrefix + SAPISIDHashGenerator.normalizeOrigin(origin)
        guard let raw = readSecret(forKey: account)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    public func clearRelayWebApiKey(forOrigin origin: String) {
        let account = Self.relayWebApiKeyPrefix + SAPISIDHashGenerator.normalizeOrigin(origin)
        removeSecret(forKey: account)
    }

    /// Synchronously extracts ONLY non-secret host routing metadata (`PairedHostLaunchHint`)
    /// from iOS Keychain so existing paired installs upgrading to this build skip the Welcome screen
    /// immediately on Frame 0 without exposing cookies, CSRF tokens, or API keys.
    public nonisolated static func peekSavedHostLaunchHintSync() -> PairedHostLaunchHint? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceIdentifier,
            kSecAttrAccount as String: Self.activeCredentialsAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let creds = try? JSONDecoder().decode(SavedBackendCredentials.self, from: data) else {
            return nil
        }
        return PairedHostLaunchHint(credentials: creds)
        #else
        return nil
        #endif
    }
}
