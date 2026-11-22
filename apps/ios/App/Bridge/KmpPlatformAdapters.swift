import Foundation
import AntigravityData
#if canImport(Security)
import Security
#endif
#if canImport(AntigravityShared)
@preconcurrency import AntigravityShared

/// Bridges KMP `SyncSecretStore` directly to iOS Hardware Keychain (`Security.framework`),
/// sharing the exact service & account namespace with `AntigravityData.KeychainStore`.
final class KmpKeychainSecretStore: NSObject, AntigravityShared.SyncSecretStore, @unchecked Sendable {
    private static let serviceIdentifier = AntigravityData.KeychainStore.serviceIdentifier
    private static let legacyServiceIdentifier = AntigravityData.KeychainStore.legacyServiceIdentifier
    private static let activeCredentialsAccount = "active_backend_credentials_v2"
    private let lock = NSLock()
    private var memoryFallback: [String: String] = [:]

    func storeSecretSync(value: String, key: String) {
        lock.lock()
        memoryFallback[key] = value
        lock.unlock()

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

    func readSecretSync(key: String) -> String? {
        #if canImport(Security)
        for service in [Self.serviceIdentifier, Self.legacyServiceIdentifier] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
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
        }
        #endif
        lock.lock()
        defer { lock.unlock() }
        return memoryFallback[key]
    }

    func removeSecretSync(key: String) {
        lock.lock()
        memoryFallback.removeValue(forKey: key)
        lock.unlock()

        #if canImport(Security)
        for service in [Self.serviceIdentifier, Self.legacyServiceIdentifier] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            SecItemDelete(query as CFDictionary)
        }
        #endif
    }

    func saveCredentialsSync(credentials: AntigravityShared.SavedBackendCredentials) {
        let swiftCreds = KmpModelConverters.toSwiftCredentials(credentials)
        guard let encoded = try? JSONEncoder().encode(swiftCreds),
              let json = String(data: encoded, encoding: .utf8) else { return }
        storeSecretSync(value: json, key: Self.activeCredentialsAccount)
    }

    func loadCredentialsSync() -> AntigravityShared.SavedBackendCredentials? {
        guard let json = readSecretSync(key: Self.activeCredentialsAccount),
              let data = json.data(using: .utf8),
              let swiftCreds = try? JSONDecoder().decode(AntigravityData.SavedBackendCredentials.self, from: data) else {
            return nil
        }
        return KmpModelConverters.toKmpCredentials(swiftCreds)
    }

    func clearCredentialsSync() {
        removeSecretSync(key: Self.activeCredentialsAccount)
    }
}

/// Bridges iOS `NWPathMonitor` (`AntigravityData.NetworkPathObserver`) to KMP `NetworkReachabilityMonitoring`.
final class KmpNetworkPathMonitorAdapter: NSObject, AntigravityShared.NetworkReachabilityMonitoring, @unchecked Sendable {
    private let observer = AntigravityData.NetworkPathObserver()

    func start(onChange: @escaping (AntigravityShared.NetworkReachabilityStatus) -> Void) {
        let callbackBox = UncheckedCallbackBox(onChange)
        observer.start { status in
            switch status {
            case .satisfied(let fingerprint, let isExpensive, let isConstrained):
                callbackBox.invoke(
                    KmpBridgeHelpers.shared.networkSatisfied(
                        interfaceFingerprint: fingerprint,
                        isExpensive: isExpensive,
                        isConstrained: isConstrained
                    )
                )
            case .unsatisfied:
                callbackBox.invoke(KmpBridgeHelpers.shared.networkUnsatisfied())
            }
        }
    }

    func stop() {
        observer.stop()
    }
}

private final class UncheckedCallbackBox<T>: @unchecked Sendable {
    private let closure: (T) -> Void
    init(_ closure: @escaping (T) -> Void) {
        self.closure = closure
    }
    func invoke(_ value: T) {
        closure(value)
    }
}

/// Bridges `ProcessInfo.processInfo.isLowPowerModeEnabled` to KMP `PowerStateProviding`.
final class KmpPowerStateAdapter: NSObject, AntigravityShared.PowerStateProviding, @unchecked Sendable {
    var isLowPowerModeEnabled: Bool {
        #if os(iOS) || os(macOS)
        return ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        return false
        #endif
    }
}

/// Bridges `UserDefaults.standard` to KMP `KeyValuePreferencesStore`.
final class KmpUserDefaultsPreferencesAdapter: NSObject, AntigravityShared.KeyValuePreferencesStore, @unchecked Sendable {
    func getString(key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    func putString(key: String, value: String?) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
#endif
