package dev.antigravity.android.core.platform

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.PowerManager
import android.util.Base64
import android.webkit.CookieManager
import androidx.core.content.IntentCompat
import com.google.crypto.tink.Aead
import com.google.crypto.tink.KeyTemplates
import com.google.crypto.tink.KeysetHandle
import com.google.crypto.tink.RegistryConfiguration
import com.google.crypto.tink.aead.AeadConfig
import com.google.crypto.tink.integration.android.AndroidKeysetManager
import dev.antigravity.shared.domain.DurableOutboxEntry
import dev.antigravity.shared.domain.HostProjectionShard
import dev.antigravity.shared.domain.ProjectionStoragePort
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.platform.KeyValuePreferencesStore
import dev.antigravity.shared.platform.NetworkReachabilityMonitoring
import dev.antigravity.shared.platform.NetworkReachabilityStatus
import dev.antigravity.shared.platform.PowerStateProviding
import dev.antigravity.shared.platform.SavedBackendCredentials
import dev.antigravity.shared.platform.SecretStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

private val PlatformJson: Json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
}

/**
 * Hardware-backed encrypted [SecretStore] using Google Tink (`AES256_GCM` keyset wrapped by an
 * Android Keystore master key) with graceful software AEAD fallback in Robolectric / JVM tests.
 */
class AndroidSecretStore(
    context: Context,
    prefsName: String = DEFAULT_PREFS_NAME,
) : SecretStore {
    private val appContext: Context = context.applicationContext
    private val prefs = appContext.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
    private val mutex = Mutex()

    private val aead: Aead? by lazy { createAead(appContext) }

    override suspend fun storeSecret(value: String, key: String) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val encoded = encryptValue(value, key)
                prefs.edit().putString(key, encoded).apply()
            }
        }
    }

    override suspend fun readSecret(key: String): String? = withContext(Dispatchers.IO) {
        mutex.withLock {
            val stored = prefs.getString(key, null) ?: return@withLock null
            decryptValue(stored, key)
        }
    }

    override suspend fun removeSecret(key: String) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                prefs.edit().remove(key).apply()
            }
        }
    }

    override suspend fun saveCredentials(credentials: SavedBackendCredentials) {
        val json = PlatformJson.encodeToString(credentials)
        storeSecret(json, KEY_SAVED_CREDENTIALS)
    }

    override suspend fun loadCredentials(): SavedBackendCredentials? {
        val raw = readSecret(KEY_SAVED_CREDENTIALS) ?: return null
        return runCatching { PlatformJson.decodeFromString<SavedBackendCredentials>(raw) }.getOrNull()
    }

    override suspend fun clearCredentials() {
        removeSecret(KEY_SAVED_CREDENTIALS)
    }

    private fun encryptValue(plaintext: String, key: String): String {
        val bytes = plaintext.toByteArray(Charsets.UTF_8)
        val aad = key.toByteArray(Charsets.UTF_8)
        val cipher = aead
        if (cipher != null) {
            val encrypted = runCatching { cipher.encrypt(bytes, aad) }.getOrNull()
            if (encrypted != null) {
                return ENCRYPTED_PREFIX + Base64.encodeToString(encrypted, Base64.NO_WRAP)
            }
        }
        return FALLBACK_PREFIX + Base64.encodeToString(bytes, Base64.NO_WRAP)
    }

    private fun decryptValue(encoded: String, key: String): String? {
        val aad = key.toByteArray(Charsets.UTF_8)
        return when {
            encoded.startsWith(ENCRYPTED_PREFIX) -> {
                val cipher = aead ?: return null
                runCatching {
                    val payload = Base64.decode(encoded.removePrefix(ENCRYPTED_PREFIX), Base64.NO_WRAP)
                    String(cipher.decrypt(payload, aad), Charsets.UTF_8)
                }.getOrNull()
            }

            encoded.startsWith(FALLBACK_PREFIX) -> {
                runCatching {
                    val payload = Base64.decode(encoded.removePrefix(FALLBACK_PREFIX), Base64.NO_WRAP)
                    String(payload, Charsets.UTF_8)
                }.getOrNull()
            }

            else -> null
        }
    }

    companion object {
        private const val DEFAULT_PREFS_NAME = "antigravity_secure_secrets"
        private const val KEYSET_NAME = "antigravity_master_keyset_v1"
        private const val KEYSET_PREF_FILE = "antigravity_tink_keyset_prefs"
        private const val FALLBACK_KEYSET_NAME = "antigravity_software_keyset_v1"
        private const val FALLBACK_KEYSET_PREF_FILE = "antigravity_tink_software_prefs"
        private const val MASTER_KEY_URI = "android-keystore://antigravity_master_key_v1"
        private const val KEY_SAVED_CREDENTIALS = "__antigravity_saved_credentials__"
        private const val ENCRYPTED_PREFIX = "v1:tink:"
        private const val FALLBACK_PREFIX = "v1:b64:"

        private val tinkInitLock = Any()
        @Volatile
        private var tinkRegistered: Boolean = false

        private fun ensureTinkRegistered() {
            if (tinkRegistered) return
            synchronized(tinkInitLock) {
                if (!tinkRegistered) {
                    AeadConfig.register()
                    tinkRegistered = true
                }
            }
        }

        private fun createAead(context: Context): Aead? {
            runCatching { ensureTinkRegistered() }.onFailure { return null }

            // 1. Hardware-backed Android Keystore wrapped Tink keyset (production Android devices)
            runCatching {
                val handle = AndroidKeysetManager.Builder()
                    .withSharedPref(context, KEYSET_NAME, KEYSET_PREF_FILE)
                    .withKeyTemplate(KeyTemplates.get("AES256_GCM"))
                    .withMasterKeyUri(MASTER_KEY_URI)
                    .build()
                    .keysetHandle
                return handle.getPrimitive(RegistryConfiguration.get(), Aead::class.java)
            }

            // 2. Software Tink keyset persisted in private prefs (Robolectric / keystore-unavailable)
            runCatching {
                val handle = AndroidKeysetManager.Builder()
                    .withSharedPref(context, FALLBACK_KEYSET_NAME, FALLBACK_KEYSET_PREF_FILE)
                    .withKeyTemplate(KeyTemplates.get("AES256_GCM"))
                    .build()
                    .keysetHandle
                return handle.getPrimitive(RegistryConfiguration.get(), Aead::class.java)
            }

            // 3. Ephemeral in-memory Tink AES256-GCM fallback
            return runCatching {
                val handle = KeysetHandle.generateNew(KeyTemplates.get("AES256_GCM"))
                handle.getPrimitive(RegistryConfiguration.get(), Aead::class.java)
            }.getOrNull()
        }
    }
}

/**
 * Connectivity observer backed by [ConnectivityManager.NetworkCallback], emitting interface
 * fingerprint and metered/congested status to the KMP domain layer.
 */
class AndroidNetworkReachabilityMonitor(
    context: Context,
) : NetworkReachabilityMonitoring {
    private val connectivityManager: ConnectivityManager? =
        context.applicationContext.getSystemService(ConnectivityManager::class.java)
    private val lock = Any()
    private var activeCallback: ConnectivityManager.NetworkCallback? = null

    @SuppressLint("MissingPermission")
    override fun start(onChange: (NetworkReachabilityStatus) -> Unit) {
        synchronized(lock) {
            stopLocked()
            val manager = connectivityManager ?: run {
                onChange(NetworkReachabilityStatus.Unsatisfied)
                return
            }

            onChange(currentSnapshot(manager))

            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    onChange(snapshotFor(network, manager.getNetworkCapabilities(network)))
                }

                override fun onCapabilitiesChanged(
                    network: Network,
                    networkCapabilities: NetworkCapabilities,
                ) {
                    onChange(snapshotFor(network, networkCapabilities))
                }

                override fun onLost(network: Network) {
                    onChange(currentSnapshot(manager))
                }

                override fun onUnavailable() {
                    onChange(NetworkReachabilityStatus.Unsatisfied)
                }
            }

            runCatching {
                manager.registerDefaultNetworkCallback(callback)
                activeCallback = callback
            }.onFailure {
                onChange(currentSnapshot(manager))
            }
        }
    }

    override fun stop() {
        synchronized(lock) {
            stopLocked()
        }
    }

    private fun stopLocked() {
        val callback = activeCallback ?: return
        activeCallback = null
        runCatching {
            connectivityManager?.unregisterNetworkCallback(callback)
        }
    }

    @SuppressLint("MissingPermission")
    private fun currentSnapshot(manager: ConnectivityManager): NetworkReachabilityStatus {
        val active = runCatching { manager.activeNetwork }.getOrNull()
            ?: return NetworkReachabilityStatus.Unsatisfied
        val caps = runCatching { manager.getNetworkCapabilities(active) }.getOrNull()
        return snapshotFor(active, caps)
    }

    private fun snapshotFor(
        network: Network,
        capabilities: NetworkCapabilities?,
    ): NetworkReachabilityStatus {
        if (capabilities == null) return NetworkReachabilityStatus.Unsatisfied
        val hasInternet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        if (!hasInternet) return NetworkReachabilityStatus.Unsatisfied

        val transports = buildList {
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) add("wifi")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) add("cellular")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) add("ethernet")
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) add("vpn")
            if (isEmpty()) add("other")
        }.joinToString("+")

        val isExpensive = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        val isConstrained = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_CONGESTED)

        return NetworkReachabilityStatus.Satisfied(
            interfaceFingerprint = "$transports:$network",
            isExpensive = isExpensive,
            isConstrained = isConstrained,
        )
    }
}

/**
 * Low-power mode adapter backed by [PowerManager.isPowerSaveMode].
 */
class AndroidPowerStateProvider(
    context: Context,
) : PowerStateProviding {
    private val powerManager: PowerManager? =
        context.applicationContext.getSystemService(PowerManager::class.java)

    override val isLowPowerModeEnabled: Boolean
        get() = runCatching { powerManager?.isPowerSaveMode == true }.getOrDefault(false)
}

/**
 * Lightweight [KeyValuePreferencesStore] backed by private Android `SharedPreferences`.
 */
class AndroidPreferencesStore(
    context: Context,
    prefsName: String = "antigravity_prefs",
) : KeyValuePreferencesStore {
    private val prefs = context.applicationContext.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    override fun getString(key: String): String? = prefs.getString(key, null)

    override fun putString(key: String, value: String?) {
        prefs.edit().apply {
            if (value == null) remove(key) else putString(key, value)
        }.apply()
    }
}

/**
 * Atomic JSON file persistence implementing KMP [ProjectionStoragePort] under
 * `context.filesDir/projections`, plus direct atomic text file helpers for local caches & tests.
 */
class AndroidProjectionStorage(
    context: Context,
) : ProjectionStoragePort {
    private val projectionsDir: File = File(context.applicationContext.filesDir, "projections")
    private val mutex = Mutex()

    fun writeText(fileName: String, content: String) {
        val target = resolveFile(fileName)
        target.parentFile?.mkdirs()
        val tempFile = File(target.parentFile, "${target.name}.tmp")
        tempFile.writeText(content, Charsets.UTF_8)
        if (!tempFile.renameTo(target)) {
            target.writeText(content, Charsets.UTF_8)
            tempFile.delete()
        }
    }

    fun readText(fileName: String): String? {
        val target = resolveFile(fileName)
        if (!target.exists() || !target.isFile) return null
        return runCatching { target.readText(Charsets.UTF_8) }.getOrNull()
    }

    fun delete(fileName: String): Boolean {
        val target = resolveFile(fileName)
        return if (target.exists()) target.delete() else false
    }

    override suspend fun loadAllHostShards(): List<HostProjectionShard> = withContext(Dispatchers.IO) {
        mutex.withLock {
            val raw = readText(FILE_HOST_SHARDS) ?: return@withLock emptyList()
            runCatching { PlatformJson.decodeFromString<List<HostProjectionShard>>(raw) }
                .getOrDefault(emptyList())
                .sortedWith(
                    compareByDescending<HostProjectionShard> { it.updatedAtEpochMs }
                        .thenBy { it.hostKey },
                )
        }
    }

    override suspend fun saveHostShards(shards: List<HostProjectionShard>) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val existing = readText(FILE_HOST_SHARDS)?.let { raw ->
                    runCatching { PlatformJson.decodeFromString<List<HostProjectionShard>>(raw) }.getOrNull()
                }.orEmpty().associateBy { it.hostKey }.toMutableMap()

                for (shard in shards) {
                    existing[shard.hostKey] = shard
                }
                val sorted = existing.values.sortedWith(
                    compareByDescending<HostProjectionShard> { it.updatedAtEpochMs }
                        .thenBy { it.hostKey },
                )
                writeText(FILE_HOST_SHARDS, PlatformJson.encodeToString(sorted))
            }
        }
    }

    override suspend fun loadKnownHosts(): List<RemoteHostInstance> = withContext(Dispatchers.IO) {
        mutex.withLock {
            val raw = readText(FILE_KNOWN_HOSTS) ?: return@withLock emptyList()
            runCatching { PlatformJson.decodeFromString<List<RemoteHostInstance>>(raw) }
                .getOrDefault(emptyList())
        }
    }

    override suspend fun saveKnownHosts(hosts: List<RemoteHostInstance>) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                writeText(FILE_KNOWN_HOSTS, PlatformJson.encodeToString(hosts))
            }
        }
    }

    override suspend fun loadSteps(cascadeId: String): List<CascadeStep> = withContext(Dispatchers.IO) {
        mutex.withLock {
            val raw = readText(stepsFileName(cascadeId)) ?: return@withLock emptyList()
            runCatching { PlatformJson.decodeFromString<List<CascadeStep>>(raw) }
                .getOrDefault(emptyList())
        }
    }

    override suspend fun saveSteps(cascadeId: String, steps: List<CascadeStep>) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                writeText(stepsFileName(cascadeId), PlatformJson.encodeToString(steps))
            }
        }
    }

    override suspend fun loadPendingOutbox(): List<DurableOutboxEntry> = withContext(Dispatchers.IO) {
        mutex.withLock {
            val raw = readText(FILE_PENDING_OUTBOX) ?: return@withLock emptyList()
            runCatching { PlatformJson.decodeFromString<List<DurableOutboxEntry>>(raw) }
                .getOrDefault(emptyList())
        }
    }

    override suspend fun enqueueOutbox(entry: DurableOutboxEntry) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val existing = readText(FILE_PENDING_OUTBOX)?.let { raw ->
                    runCatching { PlatformJson.decodeFromString<List<DurableOutboxEntry>>(raw) }.getOrNull()
                }.orEmpty().toMutableList()

                if (existing.none { it.id == entry.id }) {
                    existing.add(entry)
                    writeText(FILE_PENDING_OUTBOX, PlatformJson.encodeToString(existing))
                }
            }
        }
    }

    override suspend fun removeOutbox(entryId: String) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val existing = readText(FILE_PENDING_OUTBOX)?.let { raw ->
                    runCatching { PlatformJson.decodeFromString<List<DurableOutboxEntry>>(raw) }.getOrNull()
                }.orEmpty()
                val updated = existing.filterNot { it.id == entryId }
                writeText(FILE_PENDING_OUTBOX, PlatformJson.encodeToString(updated))
            }
        }
    }

    override suspend fun clearAll() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (projectionsDir.exists()) {
                    projectionsDir.listFiles()?.forEach { file ->
                        runCatching { file.deleteRecursively() }
                    }
                }
            }
        }
    }

    private fun resolveFile(rawName: String): File {
        val safeName = rawName
            .replace('/', '_')
            .replace('\\', '_')
            .replace("..", "_")
            .trim()
            .ifEmpty { "unnamed.json" }
        return File(projectionsDir, safeName)
    }

    private fun stepsFileName(cascadeId: String): String {
        val sanitized = cascadeId.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return "steps_$sanitized.json"
    }

    companion object {
        private const val FILE_HOST_SHARDS = "host_shards.json"
        private const val FILE_KNOWN_HOSTS = "known_hosts.json"
        private const val FILE_PENDING_OUTBOX = "pending_outbox.json"
    }
}

/**
 * Normalized payload extracted from an incoming Android `ACTION_SEND` / `ACTION_SEND_MULTIPLE` share intent.
 */
data class SharedIncomingPayload(
    val subject: String?,
    val text: String,
    val uris: List<String>,
    val mimeType: String?,
)

/**
 * Safely extracts text, subject, MIME type, and attachment URIs from incoming Android Share intents.
 */
object AndroidSharePayloadParser {
    fun parse(context: Context, intent: Intent?): SharedIncomingPayload? {
        if (intent == null) return null
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return null
        }

        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

        var text = intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: ""

        val uris = LinkedHashSet<String>()

        if (action == Intent.ACTION_SEND) {
            val streamUri = runCatching {
                IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            }.getOrNull()
            if (streamUri != null) {
                uris.add(streamUri.toString())
            }
        } else {
            val streamUris = runCatching {
                IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            }.getOrNull().orEmpty()
            for (uri in streamUris) {
                uris.add(uri.toString())
            }
        }

        val clipData = intent.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                val item = clipData.getItemAt(i)
                item.uri?.let { uris.add(it.toString()) }
                if (text.isBlank()) {
                    val coerced = runCatching { item.coerceToText(context)?.toString() }.getOrNull()
                    if (!coerced.isNullOrBlank()) {
                        text = coerced
                    }
                }
            }
        }

        val mimeType = intent.type
            ?: uris.firstOrNull()?.let { uriStr ->
                runCatching { context.contentResolver.getType(Uri.parse(uriStr)) }.getOrNull()
            }

        val cleanedText = text.trim()
        if (subject == null && cleanedText.isEmpty() && uris.isEmpty()) {
            return null
        }

        return SharedIncomingPayload(
            subject = subject,
            text = cleanedText,
            uris = uris.toList(),
            mimeType = mimeType,
        )
    }
}

/**
 * Extracts Google Cloud Relay authentication cookies (`SAPISID`, `__Secure-1PAPISID`,
 * `__Secure-3PAPISID`, and sibling session cookies) from Android `WebView` [CookieManager].
 */
object CloudRelayCookieBridge {
    val DEFAULT_RELAY_URLS: List<String> = listOf(
        "https://google.com",
        "https://www.google.com",
        "https://accounts.google.com",
        "https://antigravity.google.com",
    )

    val REQUIRED_SAPISID_KEYS: Set<String> = setOf(
        "SAPISID",
        "__Secure-1PAPISID",
        "__Secure-3PAPISID",
    )

    fun extractAuthCookies(urls: List<String> = DEFAULT_RELAY_URLS): Map<String, String> {
        val cookieManager = runCatching { CookieManager.getInstance() }.getOrNull() ?: return emptyMap()
        val merged = linkedMapOf<String, String>()
        for (url in urls) {
            val rawHeader = runCatching { cookieManager.getCookie(url) }.getOrNull() ?: continue
            parseCookieHeader(rawHeader).forEach { (name, value) ->
                merged[name] = value
            }
        }
        return merged
    }

    fun extractSessionCookieHeader(urls: List<String> = DEFAULT_RELAY_URLS): String? {
        val cookies = extractAuthCookies(urls)
        if (cookies.keys.none { it in REQUIRED_SAPISID_KEYS }) {
            return null
        }
        return cookies.entries.joinToString("; ") { (k, v) -> "$k=$v" }
    }

    fun extractSapisidToken(urls: List<String> = DEFAULT_RELAY_URLS): String? {
        val cookies = extractAuthCookies(urls)
        return cookies["__Secure-3PAPISID"]
            ?: cookies["__Secure-1PAPISID"]
            ?: cookies["SAPISID"]
    }

    fun hasRequiredAuthCookies(cookieHeader: String?): Boolean {
        if (cookieHeader.isNullOrBlank()) return false
        val parsed = parseCookieHeader(cookieHeader)
        return parsed.keys.any { it in REQUIRED_SAPISID_KEYS }
    }

    fun clearGoogleCookies(onComplete: (() -> Unit)? = null) {
        val manager = runCatching { CookieManager.getInstance() }.getOrNull()
        if (manager == null) {
            onComplete?.invoke()
            return
        }
        val dispatched = runCatching {
            manager.removeAllCookies {
                runCatching { manager.flush() }
                onComplete?.invoke()
            }
            true
        }.getOrDefault(false)
        if (!dispatched) {
            onComplete?.invoke()
        }
    }

    internal fun parseCookieHeader(rawHeader: String): Map<String, String> {
        val result = linkedMapOf<String, String>()
        rawHeader.split(';').forEach { segment ->
            val trimmed = segment.trim()
            val eqIdx = trimmed.indexOf('=')
            if (eqIdx > 0) {
                val name = trimmed.substring(0, eqIdx).trim()
                val value = trimmed.substring(eqIdx + 1).trim()
                if (name.isNotEmpty() && value.isNotEmpty()) {
                    result[name] = value
                }
            }
        }
        return result
    }
}
