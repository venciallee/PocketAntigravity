package dev.antigravity.shared.domain

import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.platform.KeyValuePreferencesStore
import dev.antigravity.shared.platform.NetworkReachabilityMonitoring
import dev.antigravity.shared.platform.NetworkReachabilityStatus
import dev.antigravity.shared.platform.PowerStateProviding
import dev.antigravity.shared.platform.SavedBackendCredentials
import dev.antigravity.shared.platform.SecretStore
import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.AntigravityRpcError
import dev.antigravity.shared.protocol.BackendHandshakeResult
import dev.antigravity.shared.protocol.ConnectionLifecyclePhase
import dev.antigravity.shared.protocol.ConnectionPowerPolicy
import dev.antigravity.shared.protocol.HostReachabilityProbeResult
import dev.antigravity.shared.protocol.RelayInstanceInfo
import dev.antigravity.shared.protocol.SapisidHashGenerator
import dev.antigravity.shared.protocol.TlsEngineConfig
import dev.antigravity.shared.protocol.currentTimeMillis
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.Throws

public data class ConnectionState(
    public val hasPairedBackend: Boolean = false,
    public val isConnected: Boolean = false,
    public val isConnecting: Boolean = false,
    public val lifecyclePhase: ConnectionLifecyclePhase = ConnectionLifecyclePhase.Disconnected,
    public val statusText: String = "Not Connected",
    public val errorText: String? = null,
    public val activeHost: RemoteHostInstance? = null,
    public val knownHosts: List<RemoteHostInstance> = emptyList(),
    public val availableRelayInstances: List<RelayInstanceInfo> = emptyList(),
    public val activeAuthUser: String = "0",
    public val lastPingLatencyMs: Int? = null,
    public val isDeviceNetworkReachable: Boolean = true,
    public val isNetworkExpensiveOrConstrained: Boolean = false,
    public val isNetworkingSuspended: Boolean = false,
    public val selectedHostScope: AgentsHostFilterScope = AgentsHostFilterScope.AllHosts,
)

/**
 * Shared KMP connection & authentication state machine (`StateFlow<ConnectionState>`).
 *
 * Manages Direct LAN (`x-codeium-csrf-token` + SHA-256 pinning/TOFU), Google Cloud Relay
 * (`SAPISIDHASH` + `ListInstances` + multi-host scoping), Keychain/Keystore credential persistence,
 * network reachability monitoring, and low-power lifecycle suspension.
 */
public class ConnectionDomainStore(
    private val secretStore: SecretStore,
    private val networkMonitor: NetworkReachabilityMonitoring,
    private val powerStateProvider: PowerStateProviding,
    private val preferencesStore: KeyValuePreferencesStore,
    private val projectionStorage: ProjectionStoragePort,
    private val clientFactory: (
        host: RemoteHostInstance,
        csrfToken: String?,
        sessionCookie: String?,
        authUser: String?,
        resolvedInstanceUuid: String?,
        relayApiKey: String?,
        tlsConfig: TlsEngineConfig,
    ) -> AntigravityKmpRpcClient = { host, csrf, cookie, authUser, resolvedUuid, relayApiKey, tlsConfig ->
        AntigravityKmpRpcClient(
            host = host,
            csrfToken = csrf,
            sessionCookie = cookie,
            authUser = authUser,
            resolvedInstanceUuid = resolvedUuid,
            relayApiKey = relayApiKey,
            tlsConfig = tlsConfig,
        )
    },
) {
    private val clientMutex = Mutex()
    private var currentClient: AntigravityKmpRpcClient? = null
    private var reconnectAttempt: Int = 0
    private var isMonitoringNetwork: Boolean = false

    private val _state = MutableStateFlow(ConnectionState())
    public val state: StateFlow<ConnectionState> = _state.asStateFlow()

    public suspend fun activeClient(): AntigravityKmpRpcClient? = clientMutex.withLock { currentClient }

    public fun startNetworkMonitoring() {
        if (isMonitoringNetwork) return
        isMonitoringNetwork = true
        networkMonitor.start { status ->
            onNetworkStatusChanged(status)
        }
    }

    public fun stopNetworkMonitoring() {
        if (!isMonitoringNetwork) return
        isMonitoringNetwork = false
        networkMonitor.stop()
    }

    public fun onNetworkStatusChanged(status: NetworkReachabilityStatus) {
        _state.update { prev ->
            val nextPhase = when {
                prev.isNetworkingSuspended -> prev.lifecyclePhase
                !status.isSatisfied && prev.hasPairedBackend -> ConnectionLifecyclePhase.NoNetwork
                status.isSatisfied && prev.lifecyclePhase is ConnectionLifecyclePhase.NoNetwork ->
                    ConnectionLifecyclePhase.OnlineIdle
                else -> prev.lifecyclePhase
            }
            prev.copy(
                isDeviceNetworkReachable = status.isSatisfied,
                isNetworkExpensiveOrConstrained = status.isExpensiveOrConstrained,
                lifecyclePhase = nextPhase,
            )
        }
    }

    public fun onBackground() {
        stopNetworkMonitoring()
        _state.update { prev ->
            prev.copy(
                isNetworkingSuspended = true,
                lifecyclePhase = if (prev.hasPairedBackend || prev.isConnected) {
                    ConnectionLifecyclePhase.Suspended
                } else {
                    prev.lifecyclePhase
                },
            )
        }
    }

    public fun onForeground() {
        startNetworkMonitoring()
        _state.update { prev ->
            val resumedPhase = if (prev.lifecyclePhase is ConnectionLifecyclePhase.Suspended) {
                if (prev.isConnected) ConnectionLifecyclePhase.OnlineIdle else ConnectionLifecyclePhase.Connecting
            } else {
                prev.lifecyclePhase
            }
            prev.copy(
                isNetworkingSuspended = false,
                lifecyclePhase = resumedPhase,
            )
        }
    }

    @Throws(Throwable::class)
    public suspend fun connectDirectLan(
        endpointUrlString: String,
        csrfToken: String,
        certSha256: String? = null,
        hostName: String = "MacBook Pro",
        isRestoringSavedSession: Boolean = false,
    ): BackendHandshakeResult {
        val trimmed = endpointUrlString.trim()
        if (!trimmed.startsWith("http://", ignoreCase = true) && !trimmed.startsWith("https://", ignoreCase = true)) {
            _state.update { it.copy(errorText = "Invalid endpoint URL: $endpointUrlString", isConnecting = false) }
            throw AntigravityRpcError.InvalidEndpoint(endpointUrlString)
        }

        val hostPart = trimmed.substringAfter("://").substringBefore('/').substringBefore(':')
        val hostInstance = RemoteHostInstance(
            instanceId = "direct-${hostPart.ifEmpty { "mac" }}",
            hostname = hostName,
            channel = RemoteConnectionChannel.DIRECT_HOST,
            endpointUrl = trimmed,
            isOnline = true,
            certificateFingerprintSha256 = certSha256 ?: "TOFU-LOCAL-TLS",
        )

        _state.update {
            it.copy(
                isConnecting = true,
                errorText = null,
                statusText = "Handshaking with ${hostPart.ifEmpty { trimmed }}...",
                lifecyclePhase = ConnectionLifecyclePhase.Connecting,
            )
        }

        val tlsConfig = TlsEngineConfig(
            pinnedFingerprintSha256 = certSha256,
            allowLocalSelfSignedTofu = true,
            bypassProxyForLocalHosts = true,
        )
        val candidate = clientFactory(hostInstance, csrfToken, null, null, null, null, tlsConfig)

        return try {
            val handshake = candidate.verifyConnection(allowCrossHostFallback = true)
            val verifiedHost = hostInstance.copy(
                hostname = handshake.resolvedHostname?.takeIf { it.isNotBlank() } ?: hostName,
                version = handshake.serverVersion,
                isOnline = handshake.isSelectedHostOnline,
                latencyMs = handshake.latencyMs,
            )
            replaceClient(candidate)
            reconnectAttempt = 0
            startNetworkMonitoring()

            val updatedHosts = mergeHostList(_state.value.knownHosts, listOf(verifiedHost))
            projectionStorage.saveKnownHosts(updatedHosts)
            secretStore.saveCredentials(
                SavedBackendCredentials(
                    endpointUrlString = trimmed,
                    channel = RemoteConnectionChannel.DIRECT_HOST,
                    hostname = verifiedHost.hostname,
                    csrfToken = csrfToken,
                    certFingerprintSha256 = certSha256,
                    pairedAtEpochMs = currentTimeMillis(),
                )
            )
            _state.update {
                it.copy(
                    hasPairedBackend = true,
                    isConnected = handshake.isSelectedHostOnline,
                    isConnecting = false,
                    lifecyclePhase = ConnectionLifecyclePhase.OnlineIdle,
                    statusText = "Connected · ${verifiedHost.hostname} · ${handshake.latencyMs}ms",
                    errorText = null,
                    activeHost = verifiedHost,
                    knownHosts = updatedHosts,
                    lastPingLatencyMs = handshake.latencyMs,
                )
            }
            handshake
        } catch (e: Throwable) {
            candidate.close()
            handleConnectFailure(hostInstance, e, isRestoringSavedSession)
            throw e
        }
    }

    @Throws(Throwable::class)
    public suspend fun connectCloudRelay(
        relayUrlString: String,
        sessionCookie: String,
        authUser: String? = null,
        resolvedInstanceUuid: String? = null,
        relayApiKey: String? = null,
        hostName: String = "Antigravity Desktop",
        isRestoringSavedSession: Boolean = false,
        strictTargetMatch: Boolean = false,
    ): BackendHandshakeResult {
        val trimmedInput = relayUrlString.trim()
        val parsed = RemoteHostInstance.parseRemoteControlTarget(
            trimmedInput.ifEmpty { SapisidHashGenerator.DEFAULT_ORIGIN }
        )
        val canonicalUrl = parsed?.canonicalRelayUrlString ?: trimmedInput
        if (!canonicalUrl.startsWith("http://", ignoreCase = true) && !canonicalUrl.startsWith("https://", ignoreCase = true)) {
            _state.update { it.copy(errorText = "Invalid Remote Control link: $relayUrlString", isConnecting = false) }
            throw AntigravityRpcError.InvalidEndpoint(relayUrlString)
        }
        val trimmedCookie = sessionCookie.trim()
        if (trimmedCookie.isEmpty()) {
            _state.update {
                it.copy(
                    isConnected = false,
                    isConnecting = false,
                    errorText = "Google Sign-In required to pair via Cloud Relay.",
                    statusText = "Sign in with Google to pair Remote Control",
                )
            }
            throw AntigravityRpcError.Unauthorized("Missing Google session cookie")
        }

        val effectiveAuth = authUser ?: parsed?.authUser
        val initialId = parsed?.instanceId?.takeIf { it.isNotEmpty() } ?: "auto"
        val hostInstance = RemoteHostInstance(
            instanceId = resolvedInstanceUuid ?: initialId,
            hostname = hostName,
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = canonicalUrl,
            isOnline = true,
        )

        _state.update {
            it.copy(
                isConnecting = true,
                errorText = null,
                statusText = "Pairing with ${parsed?.instanceId?.ifEmpty { "Cloud Relay" } ?: "Cloud Relay"} via Google Cloud Relay...",
                lifecyclePhase = ConnectionLifecyclePhase.Connecting,
            )
        }

        val tlsConfig = TlsEngineConfig(
            pinnedFingerprintSha256 = null,
            allowLocalSelfSignedTofu = false,
            bypassProxyForLocalHosts = true,
        )
        val effectiveApiKey = relayApiKey?.trim()?.takeIf { it.isNotEmpty() }
            ?: if (isRestoringSavedSession) {
                secretStore.loadCredentials()?.relayApiKey?.trim()?.takeIf { it.isNotEmpty() }
            } else {
                null
            }
        val candidate = clientFactory(hostInstance, null, trimmedCookie, effectiveAuth, resolvedInstanceUuid, effectiveApiKey, tlsConfig)

        return try {
            val handshake = candidate.verifyConnection(allowCrossHostFallback = !strictTargetMatch)
            val finalHostName = handshake.resolvedHostname?.takeIf { it.isNotBlank() } ?: hostName
            val finalUuid = handshake.resolvedInstanceUuid?.takeIf { it.isNotBlank() } ?: hostInstance.instanceId
            val finalAuthUser = handshake.resolvedAuthUser ?: effectiveAuth ?: "0"
            val finalApiKey = candidate.currentRelayApiKey() ?: handshake.resolvedRelayApiKey ?: effectiveApiKey
            val originPrefix = parsed?.relayOrigin ?: SapisidHashGenerator.DEFAULT_ORIGIN
            val finalRelayUrl = "${originPrefix.trimEnd('/')}/r/$finalUuid"

            val verifiedHost = RemoteHostInstance(
                instanceId = finalUuid,
                hostname = finalHostName,
                version = handshake.serverVersion,
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = finalRelayUrl,
                isOnline = handshake.isSelectedHostOnline,
                latencyMs = handshake.latencyMs,
            )

            replaceClient(candidate)
            reconnectAttempt = 0
            startNetworkMonitoring()

            val relayHosts = handshake.availableRelayInstances.map { inst ->
                RemoteHostInstance(
                    instanceId = inst.uuid,
                    hostname = inst.name,
                    version = inst.version,
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "${originPrefix.trimEnd('/')}/r/${inst.uuid}",
                    isOnline = inst.status.isReachable,
                    latencyMs = handshake.latencyMs,
                )
            }
            val updatedHosts = mergeHostList(_state.value.knownHosts, listOf(verifiedHost) + relayHosts)
            projectionStorage.saveKnownHosts(updatedHosts)
            secretStore.saveCredentials(
                SavedBackendCredentials(
                    endpointUrlString = finalRelayUrl,
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    hostname = finalHostName,
                    sessionCookie = trimmedCookie,
                    authUser = finalAuthUser,
                    resolvedInstanceUuid = finalUuid,
                    relayApiKey = finalApiKey,
                    pairedAtEpochMs = currentTimeMillis(),
                )
            )

            val phase = if (handshake.isSelectedHostOnline) {
                ConnectionLifecyclePhase.OnlineIdle
            } else {
                val delay = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(0, powerStateProvider.isLowPowerModeEnabled)
                ConnectionLifecyclePhase.OfflineBackoff(attempt = 0, nextRetrySeconds = delay)
            }
            _state.update {
                it.copy(
                    hasPairedBackend = true,
                    isConnected = handshake.isSelectedHostOnline,
                    isConnecting = false,
                    lifecyclePhase = phase,
                    statusText = if (handshake.isSelectedHostOnline) {
                        "Connected · $finalHostName · ${handshake.latencyMs}ms"
                    } else {
                        "Offline · $finalHostName"
                    },
                    errorText = if (handshake.isSelectedHostOnline) null else "$finalHostName is currently offline.",
                    activeHost = verifiedHost,
                    knownHosts = updatedHosts,
                    availableRelayInstances = handshake.availableRelayInstances,
                    activeAuthUser = finalAuthUser,
                    lastPingLatencyMs = handshake.latencyMs,
                )
            }
            handshake.copy(resolvedRelayApiKey = finalApiKey)
        } catch (e: Throwable) {
            candidate.close()
            handleConnectFailure(hostInstance, e, isRestoringSavedSession)
            throw e
        }
    }

    @Throws(Throwable::class)
    public suspend fun connectWithPairingUri(
        rawUri: String,
        fallbackCookie: String = "",
    ): BackendHandshakeResult {
        val trimmed = rawUri.trim()
        if (RemoteHostInstance.isDirectLanPairingUri(trimmed)) {
            val queryStr = trimmed.substringAfter('?', "")
            val params = parseSimpleQuery(queryStr)
            val targetUrl = params["url"] ?: throw AntigravityRpcError.InvalidEndpoint(trimmed)
            val csrf = params["csrf"].orEmpty()
            val sha256 = params["sha256"]
            val name = params["name"]?.takeIf { it.isNotBlank() } ?: "MacBook Pro"
            return connectDirectLan(
                endpointUrlString = targetUrl,
                csrfToken = csrf,
                certSha256 = sha256,
                hostName = name,
            )
        }
        val parsed = RemoteHostInstance.parseRemoteControlTarget(trimmed)
        if (parsed != null) {
            val savedCreds = secretStore.loadCredentials()
            val cookie = fallbackCookie.trim().ifEmpty { savedCreds?.sessionCookie.orEmpty() }
            val authUser = parsed.authUser ?: savedCreds?.authUser
            return connectCloudRelay(
                relayUrlString = trimmed,
                sessionCookie = cookie,
                authUser = authUser,
                relayApiKey = savedCreds?.relayApiKey,
                hostName = parsed.instanceId.ifEmpty { "Antigravity Desktop" },
            )
        }
        return connectDirectLan(endpointUrlString = trimmed, csrfToken = fallbackCookie)
    }

    @Throws(Throwable::class)
    public suspend fun restoreSavedSession(): BackendHandshakeResult? {
        val saved = secretStore.loadCredentials() ?: return null
        val cachedHosts = projectionStorage.loadKnownHosts()
        if (cachedHosts.isNotEmpty()) {
            _state.update { it.copy(knownHosts = cachedHosts, hasPairedBackend = true) }
        }
        return when (saved.channel) {
            RemoteConnectionChannel.DIRECT_HOST -> connectDirectLan(
                endpointUrlString = saved.endpointUrlString,
                csrfToken = saved.csrfToken.orEmpty(),
                certSha256 = saved.certFingerprintSha256,
                hostName = saved.hostname,
                isRestoringSavedSession = true,
            )
            RemoteConnectionChannel.CLOUD_RELAY -> connectCloudRelay(
                relayUrlString = saved.endpointUrlString,
                sessionCookie = saved.sessionCookie.orEmpty(),
                authUser = saved.authUser,
                resolvedInstanceUuid = saved.resolvedInstanceUuid,
                relayApiKey = saved.relayApiKey,
                hostName = saved.hostname,
                isRestoringSavedSession = true,
            )
        }
    }

    @Throws(Throwable::class)
    public suspend fun probeHostReachability(allowCrossHostFallback: Boolean = true): HostReachabilityProbeResult {
        val client = activeClient()
            ?: throw AntigravityRpcError.HttpError(503, "No active backend client")
        val result = client.probeHostReachability(allowCrossHostFallback = allowCrossHostFallback)
        _state.update { prev ->
            prev.copy(
                isConnected = result.isSelectedHostOnline,
                lastPingLatencyMs = result.latencyMs,
                availableRelayInstances = result.availableRelayInstances.ifEmpty { prev.availableRelayInstances },
                lifecyclePhase = if (result.isSelectedHostOnline) {
                    ConnectionLifecyclePhase.OnlineIdle
                } else {
                    val delay = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(
                        reconnectAttempt,
                        powerStateProvider.isLowPowerModeEnabled,
                    )
                    ConnectionLifecyclePhase.OfflineBackoff(reconnectAttempt, delay)
                },
            )
        }
        return result
    }

    public fun selectHostScope(scope: AgentsHostFilterScope) {
        _state.update { it.copy(selectedHostScope = scope) }
        val encoded = when (scope) {
            AgentsHostFilterScope.AllHosts -> "all"
            AgentsHostFilterScope.AntigravityCloud -> "cloud"
            is AgentsHostFilterScope.LocalHost -> "local:${scope.id}|${scope.name}"
        }
        preferencesStore.putString(KEY_SELECTED_HOST_SCOPE, encoded)
    }

    @Throws(Throwable::class)
    public suspend fun switchToRelayInstance(instance: RelayInstanceInfo) {
        val client = activeClient() ?: return
        client.setTargetRelayInstance(instance.uuid, instance.name)
        _state.update { prev ->
            val currentHost = prev.activeHost
            val nextHost = currentHost?.copy(
                instanceId = instance.uuid,
                hostname = instance.name,
                version = instance.version,
                isOnline = instance.status.isReachable,
            )
            prev.copy(
                activeHost = nextHost,
                isConnected = instance.status.isReachable,
                selectedHostScope = AgentsHostFilterScope.LocalHost(instance.uuid, instance.name),
            )
        }
    }

    public fun seedVerificationConnection(
        activeHost: RemoteHostInstance,
        knownHosts: List<RemoteHostInstance>,
        statusText: String = "Demo Sandbox · Offline ESDD Fixtures",
    ) {
        _state.update {
            it.copy(
                hasPairedBackend = true,
                isConnected = true,
                isConnecting = false,
                lifecyclePhase = ConnectionLifecyclePhase.OnlineIdle,
                statusText = statusText,
                errorText = null,
                activeHost = activeHost,
                knownHosts = knownHosts,
                lastPingLatencyMs = activeHost.latencyMs,
            )
        }
    }

    @Throws(Throwable::class)
    public suspend fun disconnectAndClearCredentials() {
        stopNetworkMonitoring()
        replaceClient(null)
        reconnectAttempt = 0
        preferencesStore.putString(KEY_SELECTED_HOST_SCOPE, null)
        secretStore.clearCredentials()
        projectionStorage.clearAll()
        _state.value = ConnectionState()
    }

    @Throws(Throwable::class)
    public suspend fun close() {
        stopNetworkMonitoring()
        replaceClient(null)
    }

    private suspend fun replaceClient(next: AntigravityKmpRpcClient?) {
        val previous = clientMutex.withLock {
            val prev = currentClient
            currentClient = next
            prev
        }
        previous?.close()
    }

    private fun handleConnectFailure(
        host: RemoteHostInstance,
        error: Throwable,
        isRestoringSavedSession: Boolean,
    ) {
        val isAuthError = error is AntigravityRpcError.Unauthorized
        val errMsg = when (error) {
            is AntigravityRpcError.Unauthorized -> error.detail.ifBlank { "Authentication rejected (401/403). Please re-authenticate." }
            is AntigravityRpcError.HttpError -> "Backend HTTP ${error.statusCode}: ${error.body}"
            else -> error.message ?: "Connection failed"
        }
        val nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(
            reconnectAttempt,
            powerStateProvider.isLowPowerModeEnabled,
        )
        reconnectAttempt += 1
        _state.update { prev ->
            val keepPaired = isRestoringSavedSession || prev.hasPairedBackend
            prev.copy(
                hasPairedBackend = keepPaired,
                isConnected = false,
                isConnecting = false,
                activeHost = if (keepPaired) host.copy(isOnline = false) else prev.activeHost,
                errorText = errMsg,
                statusText = if (isAuthError) "Auth Expired · ${host.hostname}" else "Offline · ${host.hostname}",
                lifecyclePhase = if (keepPaired) {
                    ConnectionLifecyclePhase.OfflineBackoff(reconnectAttempt, nextDelay)
                } else {
                    ConnectionLifecyclePhase.Disconnected
                },
            )
        }
    }

    private fun mergeHostList(
        existing: List<RemoteHostInstance>,
        incoming: List<RemoteHostInstance>,
    ): List<RemoteHostInstance> {
        val map = linkedMapOf<String, RemoteHostInstance>()
        for (h in incoming) map[h.instanceId] = h
        for (h in existing) {
            if (!map.containsKey(h.instanceId)) map[h.instanceId] = h
        }
        return map.values.toList()
    }

    private fun parseSimpleQuery(query: String): Map<String, String> {
        if (query.isEmpty()) return emptyMap()
        val out = linkedMapOf<String, String>()
        for (pair in query.split('&')) {
            val idx = pair.indexOf('=')
            if (idx <= 0) continue
            val k = pair.substring(0, idx)
            val v = pair.substring(idx + 1).replace("+", " ")
                .replace("%3A", ":", ignoreCase = true)
                .replace("%2F", "/", ignoreCase = true)
                .replace("%20", " ", ignoreCase = true)
            out[k] = v
        }
        return out
    }

    private companion object {
        private const val KEY_SELECTED_HOST_SCOPE = "antigravity.kmp.selectedHostScope.v1"
    }
}
