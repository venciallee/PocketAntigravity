package dev.antigravity.shared.domain

import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.model.UserGreetingFormatter
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
import dev.antigravity.shared.protocol.ProtocolCompatibilityEngine
import dev.antigravity.shared.protocol.RelayInstanceInfo
import dev.antigravity.shared.protocol.RelayInstanceStatus
import dev.antigravity.shared.protocol.SapisidHashGenerator
import dev.antigravity.shared.protocol.TlsEngineConfig
import dev.antigravity.shared.protocol.currentTimeMillis
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
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
    public val userDisplayName: String? = null,
    public val lastPingLatencyMs: Int? = null,
    public val isDeviceNetworkReachable: Boolean = true,
    public val isNetworkExpensiveOrConstrained: Boolean = false,
    public val isNetworkingSuspended: Boolean = false,
    public val selectedHostScope: AgentsHostFilterScope = AgentsHostFilterScope.AllHosts,
    public val isRefreshingRelayHosts: Boolean = false,
) {
    /**
     * Authoritative per-host online evaluation aligned with iOS (`isLocalHostOnline`):
     * - Returns `false` immediately when the mobile device has no network connectivity.
     * - On Cloud Relay with a non-empty authoritative `availableRelayInstances` snapshot, resolves
     *   exact UUID/name reachability and treats absent devices as offline (never falling back to
     *   another online peer or stale `isConnecting` state).
     * - On Direct LAN or pre-handshake/verification states with empty `availableRelayInstances`,
     *   requires both `matched.isOnline` and `isConnected`.
     */
    public fun isLocalHostOnline(instanceId: String?, hostname: String?): Boolean {
        if (!hasPairedBackend) return true
        if (!isDeviceNetworkReachable) return false
        val trimmedId = instanceId?.trim().orEmpty()
        val trimmedName = hostname?.trim().orEmpty()

        if (activeHost?.channel == RemoteConnectionChannel.CLOUD_RELAY && availableRelayInstances.isNotEmpty()) {
            if (trimmedId.isNotEmpty()) {
                availableRelayInstances.firstOrNull { it.uuid == trimmedId }?.let {
                    return it.status.isReachable
                }
            }
            if (trimmedName.isNotEmpty()) {
                availableRelayInstances.firstOrNull { it.name == trimmedName }?.let {
                    return it.status.isReachable
                }
            }
            if (trimmedId.isNotEmpty() || trimmedName.isNotEmpty()) {
                return false
            }
            val activeId = activeHost.instanceId
            return availableRelayInstances.firstOrNull { it.uuid == activeId }?.status?.isReachable == true
        }

        if (trimmedId.isNotEmpty()) {
            knownHosts.firstOrNull { it.instanceId == trimmedId }?.let {
                return it.isOnline && isConnected
            }
        }
        if (trimmedName.isNotEmpty()) {
            knownHosts.firstOrNull { it.hostname == trimmedName }?.let {
                return it.isOnline && isConnected
            }
        }
        return isConnected && (activeHost?.isOnline == true)
    }

    /**
     * Authoritative host-scope reachability evaluation for Home header pills, Cloud mode, and All Hosts.
     */
    public fun isHostScopeOnline(scope: AgentsHostFilterScope = selectedHostScope): Boolean {
        if (!hasPairedBackend) return true
        if (!isDeviceNetworkReachable) return false
        return when (scope) {
            is AgentsHostFilterScope.LocalHost -> isLocalHostOnline(scope.id, scope.name)
            AgentsHostFilterScope.AntigravityCloud -> {
                if (activeHost?.channel == RemoteConnectionChannel.CLOUD_RELAY && availableRelayInstances.isNotEmpty()) {
                    availableRelayInstances.any { it.status.isReachable }
                } else {
                    isConnected
                }
            }
            AgentsHostFilterScope.AllHosts -> {
                if (activeHost?.channel == RemoteConnectionChannel.CLOUD_RELAY && availableRelayInstances.isNotEmpty()) {
                    availableRelayInstances.any { it.status.isReachable }
                } else {
                    val localHosts = knownHosts.filter {
                        it.instanceId != "unpaired" && !it.hostname.equals("cloud", ignoreCase = true)
                    }
                    if (localHosts.isNotEmpty()) {
                        isConnected && localHosts.any { it.isOnline }
                    } else {
                        isConnected && (activeHost?.isOnline == true)
                    }
                }
            }
        }
    }
}

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
    private var previousNetworkStatus: NetworkReachabilityStatus? = null
    private var connectGeneration: Long = 0L
    internal var handshakeHardTimeoutMs: Long = DEFAULT_HANDSHAKE_TIMEOUT_MS
    internal var onNetworkRecovered: (() -> Unit)? = null

    @kotlin.concurrent.Volatile
    private var activeHandshakeClient: AntigravityKmpRpcClient? = null

    @kotlin.concurrent.Volatile
    public var lastHandshakeDiagnostic: String = ""
        private set

    public fun currentHandshakeDiagnostic(): String =
        activeHandshakeClient?.currentHandshakeDiagnostic()?.takeIf { it.isNotBlank() }
            ?: lastHandshakeDiagnostic

    private val _state = MutableStateFlow(
        ConnectionState(
            userDisplayName = UserGreetingFormatter.formatGreetingName(
                preferencesStore.getString(KEY_USER_DISPLAY_NAME),
            ),
        ),
    )
    public val state: StateFlow<ConnectionState> = _state.asStateFlow()

    public suspend fun activeClient(): AntigravityKmpRpcClient? = clientMutex.withLock { currentClient }

    internal fun currentReconnectAttempt(): Int = reconnectAttempt

    internal fun resetReconnectAttempt() {
        reconnectAttempt = 0
    }

    internal fun incrementReconnectAttempt(): Int {
        reconnectAttempt = (reconnectAttempt + 1).coerceAtMost(ConnectionPowerPolicy.offlineBackoffScheduleSeconds.size)
        return reconnectAttempt
    }

    internal fun setRefreshingRelayHosts(refreshing: Boolean) {
        _state.update { it.copy(isRefreshingRelayHosts = refreshing) }
    }

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
        val prevStatus = previousNetworkStatus
        previousNetworkStatus = status
        var shouldNotifyRecovery = false
        _state.update { prev ->
            if (!status.isSatisfied) {
                val nextPhase = when {
                    prev.isNetworkingSuspended -> prev.lifecyclePhase
                    prev.hasPairedBackend -> ConnectionLifecyclePhase.NoNetwork
                    else -> prev.lifecyclePhase
                }
                prev.copy(
                    isDeviceNetworkReachable = false,
                    isNetworkExpensiveOrConstrained = status.isExpensiveOrConstrained,
                    isConnected = false,
                    lastPingLatencyMs = null,
                    activeHost = prev.activeHost?.copy(isOnline = false),
                    knownHosts = prev.knownHosts.map { it.copy(isOnline = false) },
                    availableRelayInstances = prev.availableRelayInstances.map {
                        it.copy(status = RelayInstanceStatus.DISCONNECTED)
                    },
                    statusText = if (prev.hasPairedBackend) "No Internet Connection" else prev.statusText,
                    lifecyclePhase = nextPhase,
                )
            } else {
                val recoveredFromNoNetwork = (prevStatus != null && !prevStatus.isSatisfied) ||
                    prev.lifecyclePhase is ConnectionLifecyclePhase.NoNetwork
                val prevFp = (prevStatus as? NetworkReachabilityStatus.Satisfied)?.interfaceFingerprint
                val nextFp = (status as? NetworkReachabilityStatus.Satisfied)?.interfaceFingerprint
                val interfaceSwitched = prevFp != null && nextFp != null && prevFp != nextFp
                if ((recoveredFromNoNetwork || interfaceSwitched) &&
                    prev.hasPairedBackend &&
                    !prev.isNetworkingSuspended
                ) {
                    shouldNotifyRecovery = true
                }
                val nextPhase = when {
                    prev.isNetworkingSuspended -> prev.lifecyclePhase
                    recoveredFromNoNetwork && prev.hasPairedBackend -> ConnectionLifecyclePhase.Connecting
                    else -> prev.lifecyclePhase
                }
                prev.copy(
                    isDeviceNetworkReachable = true,
                    isNetworkExpensiveOrConstrained = status.isExpensiveOrConstrained,
                    lifecyclePhase = nextPhase,
                )
            }
        }
        if (shouldNotifyRecovery) {
            onNetworkRecovered?.invoke()
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
                when {
                    !prev.isDeviceNetworkReachable -> ConnectionLifecyclePhase.NoNetwork
                    prev.isConnected -> ConnectionLifecyclePhase.OnlineIdle
                    else -> ConnectionLifecyclePhase.Connecting
                }
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

        val generation = ++connectGeneration
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
            val handshake = awaitHandshakeWithHardTimeout(candidate, allowCrossHostFallback = true)
            if (connectGeneration != generation) {
                candidate.close()
                throw CancellationException("Connection superseded or cancelled")
            }
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
            if (connectGeneration == generation) {
                handleConnectFailure(hostInstance, e, isRestoringSavedSession)
            }
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
                    lifecyclePhase = if (it.hasPairedBackend) it.lifecyclePhase else ConnectionLifecyclePhase.Disconnected,
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

        val generation = ++connectGeneration
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
            val handshake = awaitHandshakeWithHardTimeout(candidate, allowCrossHostFallback = !strictTargetMatch)
            if (connectGeneration != generation) {
                candidate.close()
                throw CancellationException("Connection superseded or cancelled")
            }
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
            val updatedHosts = mergeHostList(
                existing = _state.value.knownHosts,
                incoming = listOf(verifiedHost) + relayHosts,
                markAbsentCloudRelayOffline = handshake.availableRelayInstances.isNotEmpty(),
            )
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
            if (connectGeneration == generation) {
                handleConnectFailure(hostInstance, e, isRestoringSavedSession)
            }
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
        // Always hydrate cached knownHosts as offline until the live handshake confirms reachability,
        // preventing stale disk cache from falsely showing a sleeping/powered-off host as online.
        val cachedHosts = projectionStorage.loadKnownHosts().map { it.copy(isOnline = false) }
        if (cachedHosts.isNotEmpty()) {
            val cachedActive = cachedHosts.firstOrNull {
                it.instanceId == saved.resolvedInstanceUuid || it.hostname == saved.hostname
            } ?: cachedHosts.first()
            _state.update {
                it.copy(
                    knownHosts = cachedHosts,
                    activeHost = it.activeHost ?: cachedActive,
                    hasPairedBackend = true,
                )
            }
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
    public suspend fun probeHostReachability(
        allowCrossHostFallback: Boolean = true,
        verifyEndToEnd: Boolean = false,
    ): HostReachabilityProbeResult {
        val client = activeClient()
            ?: throw AntigravityRpcError.HttpError(503, "No active backend client")
        val result = try {
            client.probeHostReachability(
                allowCrossHostFallback = allowCrossHostFallback,
                verifyEndToEnd = verifyEndToEnd,
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (isBackendOfflineError(e)) {
                markAllChannelHostsOffline(error = e)
            }
            throw e
        }

        if (result.isSelectedHostOnline) {
            reconnectAttempt = 0
        }
        var hostsToPersist: List<RemoteHostInstance>? = null
        _state.update { prev ->
            val hasFreshRelaySnapshot = result.availableRelayInstances.isNotEmpty()
            val nextRelayInstances = if (hasFreshRelaySnapshot) {
                result.availableRelayInstances
            } else {
                prev.availableRelayInstances
            }
            val originPrefix = RemoteHostInstance.parseRemoteControlTarget(
                prev.activeHost?.endpointUrl.orEmpty()
            )?.relayOrigin ?: SapisidHashGenerator.DEFAULT_ORIGIN

            val nextActiveHost = result.activeRelayInstance?.let { inst ->
                val base = prev.activeHost
                if (base != null) {
                    base.copy(
                        instanceId = inst.uuid,
                        hostname = inst.name.ifBlank { base.hostname },
                        version = inst.version.ifBlank { base.version },
                        endpointUrl = "${originPrefix.trimEnd('/')}/r/${inst.uuid}",
                        isOnline = result.isSelectedHostOnline,
                        latencyMs = result.latencyMs,
                    )
                } else {
                    RemoteHostInstance(
                        instanceId = inst.uuid,
                        hostname = inst.name,
                        version = inst.version,
                        channel = RemoteConnectionChannel.CLOUD_RELAY,
                        endpointUrl = "${originPrefix.trimEnd('/')}/r/${inst.uuid}",
                        isOnline = result.isSelectedHostOnline,
                        latencyMs = result.latencyMs,
                    )
                }
            } ?: prev.activeHost?.let { active ->
                val activeStillPresent = !hasFreshRelaySnapshot ||
                    active.channel != RemoteConnectionChannel.CLOUD_RELAY ||
                    nextRelayInstances.any { it.uuid == active.instanceId && it.status.isReachable }
                active.copy(
                    isOnline = result.isSelectedHostOnline && activeStillPresent,
                    latencyMs = result.latencyMs,
                )
            }

            val nextKnownHosts = if (hasFreshRelaySnapshot) {
                val incomingRelayHosts = nextRelayInstances.map { inst ->
                    RemoteHostInstance(
                        instanceId = inst.uuid,
                        hostname = inst.name,
                        version = inst.version,
                        channel = RemoteConnectionChannel.CLOUD_RELAY,
                        endpointUrl = "${originPrefix.trimEnd('/')}/r/${inst.uuid}",
                        isOnline = inst.status.isReachable,
                        latencyMs = result.latencyMs,
                    )
                }
                val merged = mergeHostList(
                    existing = prev.knownHosts,
                    incoming = incomingRelayHosts,
                    markAbsentCloudRelayOffline = true,
                )
                if (merged != prev.knownHosts) {
                    hostsToPersist = merged
                }
                merged
            } else if (nextActiveHost != null) {
                prev.knownHosts.map { host ->
                    if (host.instanceId == nextActiveHost.instanceId) nextActiveHost else host
                }
            } else {
                prev.knownHosts
            }

            val isOnlineNow = result.isSelectedHostOnline && (nextActiveHost?.isOnline != false)
            val displayHostName = nextActiveHost?.hostname?.takeIf { it.isNotBlank() } ?: "Desktop"
            prev.copy(
                isConnected = isOnlineNow,
                lastPingLatencyMs = if (isOnlineNow) result.latencyMs else null,
                activeHost = nextActiveHost,
                knownHosts = nextKnownHosts,
                availableRelayInstances = nextRelayInstances,
                errorText = if (isOnlineNow) null else prev.errorText,
                statusText = if (isOnlineNow) {
                    "Connected · $displayHostName · ${result.latencyMs}ms"
                } else {
                    "Offline · $displayHostName"
                },
                lifecyclePhase = if (isOnlineNow) {
                    ConnectionLifecyclePhase.OnlineIdle
                } else if (!prev.isDeviceNetworkReachable) {
                    ConnectionLifecyclePhase.NoNetwork
                } else {
                    val delay = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(
                        reconnectAttempt,
                        powerStateProvider.isLowPowerModeEnabled,
                    )
                    ConnectionLifecyclePhase.OfflineBackoff(reconnectAttempt, delay)
                },
            )
        }
        hostsToPersist?.let { updated ->
            try {
                projectionStorage.saveKnownHosts(updated)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Best-effort knownHosts cache persistence.
            }
        }
        return result
    }

    /**
     * Propagates an authoritative Cloud Relay `ListInstances` snapshot (from federated workspace sync
     * or deferred handshake hydration) back into [ConnectionState] so `availableRelayInstances`,
     * `knownHosts[*].isOnline`, `activeHost.isOnline`, and `isConnected` never go stale.
     */
    @Throws(Throwable::class)
    public suspend fun syncRelayInstances(
        instances: List<RelayInstanceInfo>,
        latencyMs: Int? = null,
        succeededInstanceUuids: Collection<String> = emptyList(),
        allowCrossHostPromotion: Boolean = false,
    ) {
        if (instances.isEmpty()) return
        val succeededSet = succeededInstanceUuids.filter { it.isNotBlank() }.toSet()
        var hostsToPersist: List<RemoteHostInstance>? = null
        var promotedRelayInstance: RelayInstanceInfo? = null

        _state.update { prev ->
            if (!prev.isDeviceNetworkReachable) {
                return@update prev
            }
            val originPrefix = RemoteHostInstance.parseRemoteControlTarget(
                prev.activeHost?.endpointUrl.orEmpty()
            )?.relayOrigin ?: SapisidHashGenerator.DEFAULT_ORIGIN
            val effectiveLatency = latencyMs?.takeIf { it > 0 } ?: prev.lastPingLatencyMs ?: prev.activeHost?.latencyMs ?: 0

            val incomingRelayHosts = instances.map { inst ->
                RemoteHostInstance(
                    instanceId = inst.uuid,
                    hostname = inst.name,
                    version = inst.version,
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "${originPrefix.trimEnd('/')}/r/${inst.uuid}",
                    isOnline = inst.status.isReachable,
                    latencyMs = effectiveLatency,
                )
            }
            val nextKnownHosts = mergeHostList(
                existing = prev.knownHosts,
                incoming = incomingRelayHosts,
                markAbsentCloudRelayOffline = true,
            )
            if (nextKnownHosts != prev.knownHosts) {
                hostsToPersist = nextKnownHosts
            }

            val currentActive = prev.activeHost
            val matchedActive = currentActive?.let { active ->
                instances.firstOrNull { it.uuid == active.instanceId }
            }
            val nextActive: RemoteHostInstance? = when {
                currentActive == null -> {
                    val chosen = instances.firstOrNull { it.uuid in succeededSet && it.status.isReachable }
                        ?: instances.firstOrNull { it.status.isReachable }
                        ?: instances.firstOrNull()
                    chosen?.let { inst ->
                        RemoteHostInstance(
                            instanceId = inst.uuid,
                            hostname = inst.name,
                            version = inst.version,
                            channel = RemoteConnectionChannel.CLOUD_RELAY,
                            endpointUrl = "${originPrefix.trimEnd('/')}/r/${inst.uuid}",
                            isOnline = inst.status.isReachable,
                            latencyMs = effectiveLatency,
                        )
                    }
                }
                currentActive.channel != RemoteConnectionChannel.CLOUD_RELAY -> currentActive
                matchedActive != null && matchedActive.status.isReachable -> currentActive.copy(
                    hostname = matchedActive.name.ifBlank { currentActive.hostname },
                    version = matchedActive.version.ifBlank { currentActive.version },
                    isOnline = true,
                    latencyMs = effectiveLatency,
                )
                allowCrossHostPromotion -> {
                    val onlinePeer = instances.firstOrNull { it.uuid in succeededSet && it.status.isReachable }
                        ?: instances.firstOrNull { it.status.isReachable }
                    if (onlinePeer != null) {
                        promotedRelayInstance = onlinePeer
                        currentActive.copy(
                            instanceId = onlinePeer.uuid,
                            hostname = onlinePeer.name.ifBlank { currentActive.hostname },
                            version = onlinePeer.version.ifBlank { currentActive.version },
                            endpointUrl = "${originPrefix.trimEnd('/')}/r/${onlinePeer.uuid}",
                            isOnline = true,
                            latencyMs = effectiveLatency,
                        )
                    } else {
                        currentActive.copy(
                            hostname = matchedActive?.name?.takeIf { it.isNotBlank() } ?: currentActive.hostname,
                            version = matchedActive?.version?.takeIf { it.isNotBlank() } ?: currentActive.version,
                            isOnline = false,
                        )
                    }
                }
                else -> currentActive.copy(
                    hostname = matchedActive?.name?.takeIf { it.isNotBlank() } ?: currentActive.hostname,
                    version = matchedActive?.version?.takeIf { it.isNotBlank() } ?: currentActive.version,
                    isOnline = false,
                )
            }

            val activeIsOnline = nextActive?.isOnline == true
            if (activeIsOnline) {
                reconnectAttempt = 0
            }
            val displayName = nextActive?.hostname?.takeIf { it.isNotBlank() } ?: "Desktop"
            val nextStatusText = when {
                activeIsOnline && effectiveLatency > 0 -> "Connected · $displayName · ${effectiveLatency}ms"
                activeIsOnline -> "Connected · $displayName"
                else -> "Offline · $displayName"
            }
            val nextPhase = when {
                prev.isNetworkingSuspended -> prev.lifecyclePhase
                !prev.isDeviceNetworkReachable -> ConnectionLifecyclePhase.NoNetwork
                activeIsOnline -> ConnectionLifecyclePhase.OnlineIdle
                else -> {
                    val delay = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(
                        reconnectAttempt,
                        powerStateProvider.isLowPowerModeEnabled,
                    )
                    ConnectionLifecyclePhase.OfflineBackoff(reconnectAttempt, delay)
                }
            }
            prev.copy(
                isConnected = activeIsOnline,
                lastPingLatencyMs = if (activeIsOnline && effectiveLatency > 0) effectiveLatency else prev.lastPingLatencyMs,
                activeHost = nextActive,
                knownHosts = nextKnownHosts,
                availableRelayInstances = instances,
                errorText = if (activeIsOnline) null else prev.errorText,
                statusText = nextStatusText,
                lifecyclePhase = nextPhase,
            )
        }
        promotedRelayInstance?.let { inst ->
            activeClient()?.setTargetRelayInstance(inst.uuid, inst.name)
        }
        hostsToPersist?.let { updated ->
            try {
                projectionStorage.saveKnownHosts(updated)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Best-effort knownHosts cache persistence.
            }
        }
    }

    public fun markBackendConnected(latencyMs: Int? = null) {
        reconnectAttempt = 0
        _state.update { prev ->
            if (!prev.isDeviceNetworkReachable) return@update prev
            val effectiveLatency = latencyMs?.takeIf { it > 0 } ?: prev.lastPingLatencyMs ?: prev.activeHost?.latencyMs ?: 0
            val nextActive = prev.activeHost?.copy(isOnline = true, latencyMs = effectiveLatency)
            val nextKnownHosts = if (nextActive != null) {
                prev.knownHosts.map { host ->
                    if (host.instanceId == nextActive.instanceId) nextActive else host
                }
            } else {
                prev.knownHosts
            }
            val displayName = nextActive?.hostname?.takeIf { it.isNotBlank() } ?: "Desktop"
            prev.copy(
                isConnected = true,
                lastPingLatencyMs = if (effectiveLatency > 0) effectiveLatency else prev.lastPingLatencyMs,
                activeHost = nextActive,
                knownHosts = nextKnownHosts,
                errorText = null,
                statusText = if (effectiveLatency > 0) "Connected · $displayName · ${effectiveLatency}ms" else "Connected · $displayName",
                lifecyclePhase = if (prev.isNetworkingSuspended) prev.lifecyclePhase else ConnectionLifecyclePhase.OnlineIdle,
            )
        }
    }

    public fun markAllChannelHostsOffline(
        error: Throwable? = null,
        errorMessage: String? = null,
    ) {
        val isAuthError = error is AntigravityRpcError.Unauthorized
        val resolvedMsg = errorMessage ?: when (error) {
            is AntigravityRpcError.Unauthorized -> error.detail.ifBlank { "Google session unauthorized: please sign in again." }
            is AntigravityRpcError.HttpError -> ProtocolCompatibilityEngine.formatUserFacingRpcError(error)
            else -> error?.message
        }
        _state.update { prev ->
            val channel = prev.activeHost?.channel
            val nextActive = prev.activeHost?.copy(isOnline = false)
            val nextKnownHosts = prev.knownHosts.map { h ->
                if (channel == null || h.channel == channel || !prev.isDeviceNetworkReachable) {
                    h.copy(isOnline = false)
                } else {
                    h
                }
            }
            val nextRelayInstances = prev.availableRelayInstances.map { inst ->
                inst.copy(status = RelayInstanceStatus.DISCONNECTED)
            }
            val displayName = nextActive?.hostname?.takeIf { it.isNotBlank() } ?: "Desktop"
            val statusText = when {
                !prev.isDeviceNetworkReachable -> "No Internet Connection"
                isAuthError && channel == RemoteConnectionChannel.CLOUD_RELAY -> "Google Sign-In Expired"
                isAuthError -> "Auth Expired · $displayName"
                else -> "Offline · $displayName"
            }
            val phase = when {
                prev.isNetworkingSuspended -> ConnectionLifecyclePhase.Suspended
                !prev.isDeviceNetworkReachable -> ConnectionLifecyclePhase.NoNetwork
                prev.hasPairedBackend -> {
                    val delay = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(
                        reconnectAttempt,
                        powerStateProvider.isLowPowerModeEnabled,
                    )
                    ConnectionLifecyclePhase.OfflineBackoff(reconnectAttempt, delay)
                }
                else -> ConnectionLifecyclePhase.Disconnected
            }
            prev.copy(
                isConnected = false,
                lastPingLatencyMs = null,
                activeHost = nextActive,
                knownHosts = nextKnownHosts,
                availableRelayInstances = nextRelayInstances,
                statusText = statusText,
                errorText = resolvedMsg ?: prev.errorText,
                lifecyclePhase = phase,
            )
        }
    }

    public fun markInstanceOffline(
        instanceUuid: String? = null,
        errorMessage: String? = null,
    ) {
        _state.update { prev ->
            val targetId = instanceUuid?.takeIf { it.isNotBlank() } ?: prev.activeHost?.instanceId
            val nextRelayInstances = prev.availableRelayInstances.map { inst ->
                if (targetId == null || inst.uuid == targetId) {
                    inst.copy(status = RelayInstanceStatus.DISCONNECTED)
                } else {
                    inst
                }
            }
            val nextKnownHosts = prev.knownHosts.map { h ->
                if (targetId == null || h.instanceId == targetId) h.copy(isOnline = false) else h
            }
            val activeMatches = targetId == null || prev.activeHost?.instanceId == targetId
            val nextActive = if (activeMatches) prev.activeHost?.copy(isOnline = false) else prev.activeHost
            val displayName = nextActive?.hostname?.takeIf { it.isNotBlank() } ?: "Desktop"
            if (activeMatches) {
                val delay = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(
                    reconnectAttempt,
                    powerStateProvider.isLowPowerModeEnabled,
                )
                prev.copy(
                    isConnected = false,
                    activeHost = nextActive,
                    knownHosts = nextKnownHosts,
                    availableRelayInstances = nextRelayInstances,
                    statusText = "Offline · $displayName",
                    errorText = errorMessage ?: prev.errorText,
                    lifecyclePhase = if (prev.hasPairedBackend) {
                        ConnectionLifecyclePhase.OfflineBackoff(reconnectAttempt, delay)
                    } else {
                        prev.lifecyclePhase
                    },
                )
            } else {
                prev.copy(
                    knownHosts = nextKnownHosts,
                    availableRelayInstances = nextRelayInstances,
                )
            }
        }
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
            val originPrefix = RemoteHostInstance.parseRemoteControlTarget(
                currentHost?.endpointUrl.orEmpty()
            )?.relayOrigin ?: SapisidHashGenerator.DEFAULT_ORIGIN
            val nextHost = currentHost?.copy(
                instanceId = instance.uuid,
                hostname = instance.name,
                version = instance.version.ifBlank { currentHost.version },
                endpointUrl = "${originPrefix.trimEnd('/')}/r/${instance.uuid}",
                isOnline = instance.status.isReachable,
            )
            val isOnline = prev.isDeviceNetworkReachable && instance.status.isReachable
            val nextKnownHosts = if (nextHost != null) {
                val updated = prev.knownHosts.map { host ->
                    if (host.instanceId == nextHost.instanceId) nextHost else host
                }
                if (updated.any { it.instanceId == nextHost.instanceId }) updated else listOf(nextHost) + updated
            } else {
                prev.knownHosts
            }
            val nextPhase = when {
                prev.isNetworkingSuspended -> prev.lifecyclePhase
                !prev.isDeviceNetworkReachable -> ConnectionLifecyclePhase.NoNetwork
                isOnline -> ConnectionLifecyclePhase.OnlineIdle
                else -> {
                    val delay = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(
                        reconnectAttempt,
                        powerStateProvider.isLowPowerModeEnabled,
                    )
                    ConnectionLifecyclePhase.OfflineBackoff(reconnectAttempt, delay)
                }
            }
            prev.copy(
                activeHost = nextHost,
                knownHosts = nextKnownHosts,
                isConnected = isOnline,
                errorText = if (isOnline) null else prev.errorText,
                statusText = if (isOnline) "Connected · ${instance.name}" else "Offline · ${instance.name}",
                lifecyclePhase = nextPhase,
                selectedHostScope = AgentsHostFilterScope.LocalHost(instance.uuid, instance.name),
            )
        }
    }

    public fun setUserDisplayName(
        rawName: String?,
        persist: Boolean = true,
    ) {
        val clean = UserGreetingFormatter.formatGreetingName(rawName)
        _state.update { it.copy(userDisplayName = clean) }
        if (persist) {
            preferencesStore.putString(KEY_USER_DISPLAY_NAME, clean)
        }
    }

    public fun seedVerificationConnection(
        activeHost: RemoteHostInstance,
        knownHosts: List<RemoteHostInstance>,
        statusText: String = "Demo Sandbox · Offline ESDD Fixtures",
        userDisplayName: String? = "Alex",
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
                userDisplayName = UserGreetingFormatter.formatGreetingName(userDisplayName),
                lastPingLatencyMs = activeHost.latencyMs,
            )
        }
    }

    public fun cancelPendingConnectionAttempt() {
        connectGeneration += 1
        _state.update { prev ->
            if (!prev.isConnecting && prev.lifecyclePhase !is ConnectionLifecyclePhase.Connecting) {
                prev
            } else {
                prev.copy(
                    isConnecting = false,
                    lifecyclePhase = if (prev.hasPairedBackend) {
                        ConnectionLifecyclePhase.OfflineBackoff(
                            attempt = reconnectAttempt,
                            nextRetrySeconds = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(
                                reconnectAttempt,
                                powerStateProvider.isLowPowerModeEnabled,
                            ),
                        )
                    } else {
                        ConnectionLifecyclePhase.Disconnected
                    },
                    statusText = if (prev.hasPairedBackend) {
                        "Offline · ${prev.activeHost?.hostname ?: "Desktop"}"
                    } else {
                        "Connection cancelled"
                    },
                )
            }
        }
    }

    @Throws(Throwable::class)
    public suspend fun disconnectAndClearCredentials() {
        connectGeneration += 1
        stopNetworkMonitoring()
        replaceClient(null)
        reconnectAttempt = 0
        preferencesStore.putString(KEY_SELECTED_HOST_SCOPE, null)
        preferencesStore.putString(KEY_USER_DISPLAY_NAME, null)
        secretStore.clearCredentials()
        projectionStorage.clearAll()
        _state.value = ConnectionState()
    }

    @Throws(Throwable::class)
    public suspend fun close() {
        connectGeneration += 1
        stopNetworkMonitoring()
        replaceClient(null)
    }

    private suspend fun awaitHandshakeWithHardTimeout(
        candidate: AntigravityKmpRpcClient,
        allowCrossHostFallback: Boolean,
    ): BackendHandshakeResult {
        activeHandshakeClient = candidate
        val result = try {
            withTimeoutOrNull(handshakeHardTimeoutMs) {
                candidate.verifyConnection(allowCrossHostFallback = allowCrossHostFallback)
            }
        } catch (e: CancellationException) {
            lastHandshakeDiagnostic = candidate.currentHandshakeDiagnostic()
            if (!currentCoroutineContext().isActive) throw e
            null
        } finally {
            lastHandshakeDiagnostic = candidate.currentHandshakeDiagnostic()
            if (activeHandshakeClient === candidate) {
                activeHandshakeClient = null
            }
        }
        if (result != null) return result
        val diag = lastHandshakeDiagnostic.ifBlank { candidate.currentHandshakeDiagnostic() }
        throw AntigravityRpcError.HttpError(
            504,
            "Cloud Relay handshake timed out after ${handshakeHardTimeoutMs / 1000}s. Check Google / VPN reachability or tap Sign in with Google. [$diag]",
        )
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
            is AntigravityRpcError.HttpError -> ProtocolCompatibilityEngine.formatUserFacingRpcError(error)
            else -> error.message ?: "Connection failed"
        }
        val nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(
            reconnectAttempt,
            powerStateProvider.isLowPowerModeEnabled,
        )
        reconnectAttempt += 1
        _state.update { prev ->
            val keepPaired = isRestoringSavedSession || prev.hasPairedBackend
            val resolvedHost = if (keepPaired) {
                val prevHost = prev.activeHost
                val incomingIsPlaceholder = host.hostname.isBlank() ||
                    host.hostname == host.instanceId ||
                    host.hostname == "Antigravity Desktop"
                if (prevHost != null && incomingIsPlaceholder && prevHost.hostname.isNotBlank()) {
                    prevHost.copy(isOnline = false)
                } else {
                    host.copy(isOnline = false)
                }
            } else {
                prev.activeHost
            }
            val nextKnownHosts = prev.knownHosts.map { known ->
                if (known.channel == host.channel || known.instanceId == resolvedHost?.instanceId) {
                    known.copy(isOnline = false)
                } else {
                    known
                }
            }
            val nextRelayInstances = if (host.channel == RemoteConnectionChannel.CLOUD_RELAY) {
                prev.availableRelayInstances.map { it.copy(status = RelayInstanceStatus.DISCONNECTED) }
            } else {
                prev.availableRelayInstances
            }
            val displayHostName = resolvedHost?.hostname?.takeIf { it.isNotBlank() } ?: host.hostname
            val statusText = when {
                !prev.isDeviceNetworkReachable -> "No Internet Connection"
                isAuthError && host.channel == RemoteConnectionChannel.CLOUD_RELAY -> "Google Sign-In Expired"
                isAuthError -> "Auth Expired · $displayHostName"
                else -> "Offline · $displayHostName"
            }
            prev.copy(
                hasPairedBackend = keepPaired,
                isConnected = false,
                isConnecting = false,
                lastPingLatencyMs = null,
                activeHost = resolvedHost,
                knownHosts = nextKnownHosts,
                availableRelayInstances = nextRelayInstances,
                errorText = errMsg,
                statusText = statusText,
                lifecyclePhase = if (!prev.isDeviceNetworkReachable && keepPaired) {
                    ConnectionLifecyclePhase.NoNetwork
                } else if (keepPaired) {
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
        markAbsentCloudRelayOffline: Boolean = false,
    ): List<RemoteHostInstance> {
        val map = linkedMapOf<String, RemoteHostInstance>()
        for (h in incoming) map[h.instanceId] = h
        for (h in existing) {
            if (!map.containsKey(h.instanceId)) {
                map[h.instanceId] = if (markAbsentCloudRelayOffline && h.channel == RemoteConnectionChannel.CLOUD_RELAY) {
                    h.copy(isOnline = false)
                } else {
                    h
                }
            }
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

    internal companion object {
        private const val KEY_SELECTED_HOST_SCOPE = "antigravity.kmp.selectedHostScope.v1"
        private const val KEY_USER_DISPLAY_NAME = "antigravity.userDisplayName.v1"
        private const val DEFAULT_HANDSHAKE_TIMEOUT_MS = 22_000L

        internal fun isBackendOfflineError(error: Throwable): Boolean {
            if (error is CancellationException) return false
            if (ProtocolCompatibilityEngine.isInstanceNotRegisteredError(error)) return true
            return when (error) {
                is AntigravityRpcError.Unauthorized,
                is AntigravityRpcError.InvalidEndpoint,
                -> true
                is AntigravityRpcError.HttpError ->
                    error.statusCode == -1 || error.statusCode in setOf(502, 503, 504)
                is AntigravityRpcError.DecodingError,
                is AntigravityRpcError.InteractionRejected,
                -> false
                else -> true
            }
        }
    }
}
