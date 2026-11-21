import Foundation

// MARK: - Platform Port Protocols (KMP `expect`/`actual` Boundary)

/// Platform-neutral encrypted secret/credential storage contract.
///
/// - iOS implementation: `KeychainStore` (Security.framework Keychain)
/// - Android (KMP Phase 1+): Android Keystore + EncryptedDataStore
public protocol SecretStore: Sendable {
    func storeSecret(_ value: String, forKey key: String) async
    func readSecret(forKey key: String) async -> String?
    func removeSecret(forKey key: String) async
    func saveCredentials(_ credentials: SavedBackendCredentials) async
    func loadCredentials() async -> SavedBackendCredentials?
    func clearCredentials() async
}

/// Platform-neutral network reachability & interface-change observer contract.
///
/// - iOS implementation: `NetworkPathObserver` (`NWPathMonitor`)
/// - Android (KMP Phase 1+): `ConnectivityManager.NetworkCallback`
public protocol NetworkReachabilityMonitoring: Sendable {
    func start(onChange: @escaping @Sendable (NetworkReachabilityStatus) -> Void)
    func stop()
}

/// Platform-neutral power-saving state provider contract.
///
/// - iOS implementation: `SystemPowerStateProvider` (`ProcessInfo.isLowPowerModeEnabled`)
/// - Android (KMP Phase 1+): `PowerManager.isPowerSaveMode`
public protocol PowerStateProviding: Sendable {
    var isLowPowerModeEnabled: Bool { get }
}

/// Platform-neutral lightweight key-value preference storage contract.
///
/// - iOS implementation: `UserDefaultsPreferencesStore` (`UserDefaults`)
/// - Android (KMP Phase 1+): `DataStore<Preferences>` / `SharedPreferences`
public protocol KeyValuePreferencesStore: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

// MARK: - Default Apple Platform Adapters

/// Default Apple `PowerStateProviding` backed by `ProcessInfo.processInfo.isLowPowerModeEnabled`.
public struct SystemPowerStateProvider: PowerStateProviding, Sendable {
    public init() {}

    public var isLowPowerModeEnabled: Bool {
        #if os(iOS) || os(macOS)
        return ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        return false
        #endif
    }
}

/// Default Apple `KeyValuePreferencesStore` backed by `UserDefaults`.
public struct UserDefaultsPreferencesStore: KeyValuePreferencesStore, Sendable {
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private func resolvedDefaults() -> UserDefaults {
        if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
            return suite
        }
        return .standard
    }

    public func string(forKey key: String) -> String? {
        resolvedDefaults().string(forKey: key)
    }

    public func set(_ value: String?, forKey key: String) {
        if let value {
            resolvedDefaults().set(value, forKey: key)
        } else {
            resolvedDefaults().removeObject(forKey: key)
        }
    }
}

// MARK: - Deterministic In-Memory Test / Verification Doubles

/// Pure in-memory `SecretStore` for deterministic unit tests and offline verification stores.
public actor InMemorySecretStore: SecretStore {
    private var secrets: [String: String] = [:]
    private var credentials: SavedBackendCredentials?

    public init(initialCredentials: SavedBackendCredentials? = nil) {
        self.credentials = initialCredentials
    }

    public func storeSecret(_ value: String, forKey key: String) {
        secrets[key] = value
    }

    public func readSecret(forKey key: String) -> String? {
        secrets[key]
    }

    public func removeSecret(forKey key: String) {
        secrets.removeValue(forKey: key)
    }

    public func saveCredentials(_ credentials: SavedBackendCredentials) {
        self.credentials = credentials
    }

    public func loadCredentials() -> SavedBackendCredentials? {
        credentials
    }

    public func clearCredentials() {
        credentials = nil
    }
}

/// Pure in-memory `KeyValuePreferencesStore` safe under Swift 6 strict concurrency.
public final class InMemoryPreferencesStore: KeyValuePreferencesStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]

    public init(initialValues: [String: String] = [:]) {
        self.values = initialValues
    }

    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func set(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }
}

/// Fixed-value `PowerStateProviding` for deterministic tests.
public struct StaticPowerStateProvider: PowerStateProviding, Sendable {
    public var isLowPowerModeEnabled: Bool

    public init(isLowPowerModeEnabled: Bool = false) {
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
    }
}

/// No-op `NetworkReachabilityMonitoring` for offline fixtures and unit tests.
public struct NoopNetworkReachabilityMonitor: NetworkReachabilityMonitoring, Sendable {
    public init() {}
    public func start(onChange: @escaping @Sendable (NetworkReachabilityStatus) -> Void) {}
    public func stop() {}
}
