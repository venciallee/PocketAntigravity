package dev.antigravity.shared.platform

import dev.antigravity.shared.model.RemoteConnectionChannel
import kotlinx.serialization.Serializable

/**
 * Persisted Remote Control / Direct LAN login credentials stored strictly in secure hardware-backed storage.
 */
@Serializable
public data class SavedBackendCredentials(
    public val endpointUrlString: String,
    public val channel: RemoteConnectionChannel,
    public val hostname: String,
    public val csrfToken: String? = null,
    public val sessionCookie: String? = null,
    public val authUser: String? = null,
    public val resolvedInstanceUuid: String? = null,
    public val certFingerprintSha256: String? = null,
    public val pairedAtEpochMs: Long = 0L,
)

/**
 * Snapshot of device-level IP connectivity reported by iOS `NWPathMonitor` or Android `ConnectivityManager`.
 */
public sealed interface NetworkReachabilityStatus {
    public data class Satisfied(
        public val interfaceFingerprint: String,
        public val isExpensive: Boolean,
        public val isConstrained: Boolean,
    ) : NetworkReachabilityStatus

    public data object Unsatisfied : NetworkReachabilityStatus

    public val isSatisfied: Boolean
        get() = this is Satisfied

    public val isExpensiveOrConstrained: Boolean
        get() = this is Satisfied && (isExpensive || isConstrained)

    public val interfaceFingerprintOrNull: String?
        get() = (this as? Satisfied)?.interfaceFingerprint
}

/**
 * Platform-neutral encrypted secret/credential storage contract.
 * - iOS: Keychain (`Security`)
 * - Android: Android Keystore + EncryptedDataStore
 */
public interface SecretStore {
    public suspend fun storeSecret(value: String, key: String)
    public suspend fun readSecret(key: String): String?
    public suspend fun removeSecret(key: String)
    public suspend fun saveCredentials(credentials: SavedBackendCredentials)
    public suspend fun loadCredentials(): SavedBackendCredentials?
    public suspend fun clearCredentials()
}

/**
 * Platform-neutral network reachability & interface-change observer contract.
 * - iOS: `NWPathMonitor`
 * - Android: `ConnectivityManager.NetworkCallback`
 */
public interface NetworkReachabilityMonitoring {
    public fun start(onChange: (NetworkReachabilityStatus) -> Unit)
    public fun stop()
}

/**
 * Platform-neutral power-saving state provider contract.
 * - iOS: `ProcessInfo.isLowPowerModeEnabled`
 * - Android: `PowerManager.isPowerSaveMode`
 */
public interface PowerStateProviding {
    public val isLowPowerModeEnabled: Boolean
}

/**
 * Platform-neutral lightweight key-value preference storage contract.
 * - iOS: `UserDefaults`
 * - Android: `DataStore<Preferences>` / `SharedPreferences`
 */
public interface KeyValuePreferencesStore {
    public fun getString(key: String): String?
    public fun putString(key: String, value: String?)
}

/**
 * Deterministic in-memory [SecretStore] for unit tests & offline fixtures.
 */
public class InMemorySecretStore(
    initialCredentials: SavedBackendCredentials? = null,
) : SecretStore {
    private val secrets = mutableMapOf<String, String>()
    private var credentials: SavedBackendCredentials? = initialCredentials

    override suspend fun storeSecret(value: String, key: String) {
        secrets[key] = value
    }

    override suspend fun readSecret(key: String): String? = secrets[key]

    override suspend fun removeSecret(key: String) {
        secrets.remove(key)
    }

    override suspend fun saveCredentials(credentials: SavedBackendCredentials) {
        this.credentials = credentials
    }

    override suspend fun loadCredentials(): SavedBackendCredentials? = credentials

    override suspend fun clearCredentials() {
        credentials = null
    }
}

/**
 * Deterministic in-memory [KeyValuePreferencesStore] for unit tests & offline fixtures.
 */
public class InMemoryPreferencesStore(
    initialValues: Map<String, String> = emptyMap(),
) : KeyValuePreferencesStore {
    private val values = initialValues.toMutableMap()

    override fun getString(key: String): String? = values[key]

    override fun putString(key: String, value: String?) {
        if (value == null) values.remove(key) else values[key] = value
    }
}

public class StaticPowerStateProvider(
    override val isLowPowerModeEnabled: Boolean = false,
) : PowerStateProviding

public class NoopNetworkReachabilityMonitor : NetworkReachabilityMonitoring {
    override fun start(onChange: (NetworkReachabilityStatus) -> Unit) = Unit
    override fun stop() = Unit
}
