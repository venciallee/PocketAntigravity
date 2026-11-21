package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AntigravityCloudDetector
import dev.antigravity.shared.model.AutomationItem
import dev.antigravity.shared.model.AutomationSectionKind
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.CascadeUserInteractionPayload
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.NewProjectDraft
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.model.ThinkingEffortLevel
import dev.antigravity.shared.model.WorkspaceInfo
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.preparePost
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsBytes
import io.ktor.client.statement.bodyAsChannel
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.content.ByteArrayContent
import io.ktor.utils.io.readAvailable
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlin.math.max
import kotlin.random.Random

@Serializable
public data class BackendHandshakeResult(
    public val latencyMs: Int,
    public val workspaces: List<WorkspaceInfo>,
    public val summaries: List<CascadeSummary>,
    public val cloudProjects: List<ProjectWorkspace> = emptyList(),
    public val serverVersion: String = "v2.33.0",
    public val resolvedHostname: String? = null,
    public val resolvedInstanceUuid: String? = null,
    public val resolvedAuthUser: String? = null,
    public val availableRelayInstances: List<RelayInstanceInfo> = emptyList(),
    public val isSelectedHostOnline: Boolean = true,
)

@Serializable
public data class HostReachabilityProbeResult(
    public val latencyMs: Int,
    public val availableRelayInstances: List<RelayInstanceInfo> = emptyList(),
    public val activeRelayInstance: RelayInstanceInfo? = null,
    public val relayTopologyChanged: Boolean = false,
    public val relayMetadataChanged: Boolean = false,
    public val isSelectedHostOnline: Boolean = true,
)

@Serializable
public data class FederatedWorkspaceSyncResult(
    public val workspaces: List<WorkspaceInfo>,
    public val summaries: List<CascadeSummary>,
    public val cloudProjects: List<ProjectWorkspace> = emptyList(),
    public val cloudWarmingUp: Boolean = false,
    public val availableRelayInstances: List<RelayInstanceInfo> = emptyList(),
    public val succeededInstanceUuids: List<String> = emptyList(),
    public val cloudSucceeded: Boolean = false,
    public val latencyMs: Int = 0,
)

@Serializable
public data class RelayResolutionResult(
    public val selected: RelayInstanceInfo,
    public val allInstances: List<RelayInstanceInfo>,
    public val matchedAuthUser: String,
)

/**
 * Kotlin Multiplatform Connect-RPC & Google Cloud Relay transport client powered by Ktor
 * (`ktor-client-okhttp` on JVM/Android, `ktor-client-darwin` on iOS with SHA-256 pinning & LAN TOFU).
 *
 * Connects either to:
 * 1. Direct LAN / Tailscale `language_server` or `mac-companion-bridge.py` (`x-codeium-csrf-token`)
 * 2. Official Google Cloud Remote Control Relay (`SAPISIDHASH` + `ApiService/ListInstances` + `ProxyCommand` + `StreamProxyCommand`)
 */
public class AntigravityKmpRpcClient(
    public val host: RemoteHostInstance,
    private val csrfToken: String? = null,
    private val sessionCookie: String? = null,
    authUser: String? = null,
    resolvedInstanceUuid: String? = null,
    relayApiKey: String? = null,
    tlsConfig: TlsEngineConfig = TlsEngineConfig(
        pinnedFingerprintSha256 = host.certificateFingerprintSha256
            .takeIf { it.isNotBlank() && it != "TOFU-LOCAL-TLS" && !it.startsWith("SHA256:9F:86:D0") },
        allowLocalSelfSignedTofu = host.channel == RemoteConnectionChannel.DIRECT_HOST,
    ),
    httpClientOverride: HttpClient? = null,
) {
    public companion object {
        public const val SERVICE_PREFIX: String = "/exa.language_server_pb.LanguageServerService"
        public const val PROTOBUF_STEP_THRESHOLD: Int = 600

        private val localDesktopOnlyMethods = setOf("OpenWorkspaceInFinder", "ReadArtifactFile")
        private val unknownFieldRegex = Regex("""unknown field\s+"([^"]+)"""", RegexOption.IGNORE_CASE)

        public fun extractUnknownProtoFieldName(message: String): String? =
            unknownFieldRegex.find(message)?.groupValues?.getOrNull(1)

        public fun isWildcardRelayIdentifier(raw: String): Boolean {
            val trimmed = raw.trim().lowercase()
            return trimmed.isEmpty() ||
                trimmed == "r" ||
                trimmed == "auto" ||
                trimmed == "unpaired" ||
                trimmed == "macbook-pro-local"
        }

        public fun unwrapConnectFramedPayloadIfNeeded(data: ByteArray): ByteArray {
            if (data.size < 5) return data
            val first = data[0].toInt() and 0xFF
            if (first != 0x00 && first != 0x01) return data
            val parser = ConnectStreamParser()
            val frames = parser.feed(data).filter { !it.isEndStream }
            if (frames.isEmpty()) return data
            val out = ArrayList<Byte>(data.size)
            for (frame in frames) {
                val decoded = if (frame.isCompressed) {
                    CloudRelayJspbCodec.decompressPayloadIfNeeded(frame.payload)
                } else {
                    frame.payload
                }
                for (b in decoded) out.add(b)
            }
            return if (out.isEmpty()) data else out.toByteArray()
        }

        internal fun randomUuidV4(): String {
            val bytes = Random.nextBytes(16)
            bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x40).toByte()
            bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte()
            val hex = "0123456789abcdef"
            val sb = StringBuilder(36)
            for (i in 0 until 16) {
                if (i == 4 || i == 6 || i == 8 || i == 10) sb.append('-')
                val v = bytes[i].toInt() and 0xFF
                sb.append(hex[v ushr 4])
                sb.append(hex[v and 0x0F])
            }
            return sb.toString()
        }
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val stateMutex = Mutex()
    private val ownsHttpClients: Boolean = (httpClientOverride == null)
    private val endpointBaseUrl: String = host.endpointUrl.trimEnd('/')
    private val parsedTarget = RemoteHostInstance.parseRemoteControlTarget(host.endpointUrl)
    private val relayOrigin: String = SapisidHashGenerator.normalizeOrigin(
        parsedTarget?.relayOrigin ?: SapisidHashGenerator.DEFAULT_ORIGIN
    )
    private val endpointHost: String = extractHostFromUrl(host.endpointUrl)

    private val explicitAuthUser: String? = authUser ?: parsedTarget?.authUser
    private var currentAuthUser: String = explicitAuthUser ?: "0"
    private var targetInstanceIdentifier: String =
        parsedTarget?.instanceId?.takeIf { it.isNotEmpty() } ?: host.instanceId
    private var resolvedInstanceUuidState: String? = resolvedInstanceUuid
    private var currentRelayApiKey: String? = relayApiKey?.trim()?.takeIf { it.isNotEmpty() }
    private var attemptedApiKeyDiscovery: Boolean = false
    private var cachedRelayInstances: List<RelayInstanceInfo> = emptyList()
    private val wokenInstanceCascadeKeys = mutableSetOf<String>()

    private val httpClient: HttpClient = httpClientOverride ?: createPlatformHttpClient(
        endpointHost = endpointHost,
        config = tlsConfig,
    )
    private val streamingHttpClient: HttpClient = httpClientOverride ?: createPlatformHttpClient(
        endpointHost = endpointHost,
        config = tlsConfig.copy(requestTimeoutMs = max(tlsConfig.requestTimeoutMs, 120_000L)),
    )

    public val channel: RemoteConnectionChannel
        get() = host.channel

    public suspend fun currentCachedRelayInstances(): List<RelayInstanceInfo> =
        stateMutex.withLock { cachedRelayInstances }

    public suspend fun currentResolvedInstanceUuid(): String? =
        stateMutex.withLock { resolvedInstanceUuidState }

    public suspend fun currentAuthUser(): String =
        stateMutex.withLock { currentAuthUser }

    public suspend fun currentRelayApiKey(): String? =
        stateMutex.withLock { currentRelayApiKey }

    private suspend fun ensureRelayWebApiKey(forceRefresh: Boolean = false): String? {
        val existing = stateMutex.withLock {
            if (!forceRefresh && !currentRelayApiKey.isNullOrEmpty()) return@withLock currentRelayApiKey
            if (!forceRefresh && attemptedApiKeyDiscovery) return@withLock currentRelayApiKey
            attemptedApiKeyDiscovery = true
            null
        }
        if (existing != null) return existing
        if (LocalHostClassifier.isPrivateOrTailscaleHost(endpointHost)) return null
        val discovered = runCatching {
            val resp = httpClient.get(relayOrigin) {
                sessionCookie?.takeIf { it.isNotEmpty() }?.let { header("Cookie", it) }
            }
            if (resp.status.value in 200..299) {
                SapisidHashGenerator.extractWebApiKey(resp.bodyAsText())
            } else {
                null
            }
        }.getOrNull()
        if (!discovered.isNullOrEmpty()) {
            stateMutex.withLock { currentRelayApiKey = discovered }
        }
        return discovered
    }

    public suspend fun currentActiveRelayInstance(): RelayInstanceInfo? = stateMutex.withLock {
        val resUuid = resolvedInstanceUuidState
        if (resUuid != null) {
            cachedRelayInstances.firstOrNull { it.uuid == resUuid && it.status.isReachable }?.let { return@withLock it }
        }
        if (!isWildcardRelayIdentifier(targetInstanceIdentifier)) {
            cachedRelayInstances.firstOrNull { it.matches(targetInstanceIdentifier) && it.status.isReachable }?.let { return@withLock it }
        }
        null
    }

    public suspend fun setTargetRelayInstance(uuid: String, name: String) {
        stateMutex.withLock {
            val trimmedUuid = uuid.trim()
            val trimmedName = name.trim()
            if (trimmedUuid.isNotEmpty() && !isWildcardRelayIdentifier(trimmedUuid)) {
                resolvedInstanceUuidState = trimmedUuid
                targetInstanceIdentifier = trimmedUuid
            } else if (trimmedName.isNotEmpty()) {
                targetInstanceIdentifier = trimmedName
            }
        }
    }

    // MARK: - Cloud Relay `ListInstances` & Resolution

    public suspend fun listRelayInstances(authUserOverride: String? = null): List<RelayInstanceInfo> {
        val activeAuthUser = authUserOverride ?: stateMutex.withLock { currentAuthUser }
        val url = "$relayOrigin${SapisidHashGenerator.API_SERVICE_PREFIX}/ListInstances"
        val apiKey = ensureRelayWebApiKey()
        val headers = SapisidHashGenerator.buildApiServiceHeaders(
            cookieHeader = sessionCookie.orEmpty(),
            origin = relayOrigin,
            authUser = activeAuthUser,
            apiKey = apiKey,
            timestampSeconds = currentTimeMillis() / 1000L,
        )
        val response = httpClient.post(url) {
            for ((k, v) in headers) {
                if (!k.equals("Content-Type", ignoreCase = true)) {
                    header(k, v)
                }
            }
            setBody(
                ByteArrayContent(
                    CloudRelayJspbCodec.encodeListInstancesRequest(),
                    ContentType.parse("application/json+protobuf"),
                )
            )
        }
        val rawBytes = response.bodyAsBytes()
        val statusCode = response.status.value
        if (statusCode == 401 || statusCode == 403) {
            throw AntigravityRpcError.Unauthorized
        }
        if (statusCode !in 200..299) {
            throw AntigravityRpcError.HttpError(statusCode, rawBytes.decodeToString())
        }
        return CloudRelayJspbCodec.decodeListInstancesResponse(rawBytes, response.flattenHeaders())
    }

    public suspend fun resolveCloudRelayInstance(
        preferredIdentifier: String? = null,
        allowCrossHostFallback: Boolean = true,
    ): RelayResolutionResult {
        val rawTarget = (preferredIdentifier ?: stateMutex.withLock { targetInstanceIdentifier }).trim()
        val isWildcard = isWildcardRelayIdentifier(rawTarget)

        val candidateAuthUsers = buildList {
            explicitAuthUser?.takeIf { it.isNotEmpty() }?.let { add(it) }
            for (idx in listOf("0", "1", "2", "3", "4")) {
                if (idx !in this) add(idx)
            }
        }

        var firstNonEmpty: Pair<List<RelayInstanceInfo>, String>? = null
        var bestReachableFallback: Triple<RelayInstanceInfo, List<RelayInstanceInfo>, String>? = null
        var bestOfflineMatch: Triple<RelayInstanceInfo, List<RelayInstanceInfo>, String>? = null
        var lastError: Throwable? = null

        for (candidateUser in candidateAuthUsers) {
            try {
                val instances = listRelayInstances(authUserOverride = candidateUser)
                if (instances.isEmpty()) continue
                if (firstNonEmpty == null) firstNonEmpty = instances to candidateUser

                if (!isWildcard) {
                    instances.firstOrNull { it.matches(rawTarget) && it.status.isReachable }?.let { exact ->
                        updateRelayCache(candidateUser, exact.uuid, instances)
                        return RelayResolutionResult(exact, instances, candidateUser)
                    }
                    instances.firstOrNull { it.sameHostFamily(rawTarget) && it.status.isReachable }?.let { fam ->
                        updateRelayCache(candidateUser, fam.uuid, instances)
                        return RelayResolutionResult(fam, instances, candidateUser)
                    }
                    val exactTargetMatch = instances.firstOrNull { it.matches(rawTarget) }
                    if (bestOfflineMatch == null) {
                        val offline = exactTargetMatch
                            ?: instances.firstOrNull { it.sameHostFamily(rawTarget) }
                        if (offline != null) bestOfflineMatch = Triple(offline, instances, candidateUser)
                    }
                    if (bestReachableFallback == null) {
                        instances.firstOrNull { it.status.isReachable }?.let { anyOnline ->
                            bestReachableFallback = Triple(anyOnline, instances, candidateUser)
                        }
                    }
                    if (exactTargetMatch != null) {
                        break
                    }
                } else {
                    instances.firstOrNull { it.status.isReachable }?.let { online ->
                        updateRelayCache(candidateUser, online.uuid, instances)
                        return RelayResolutionResult(online, instances, candidateUser)
                    }
                }
            } catch (e: Throwable) {
                lastError = e
            }
        }

        if (!allowCrossHostFallback && bestOfflineMatch != null) {
            updateRelayCache(bestOfflineMatch.third, bestOfflineMatch.first.uuid, bestOfflineMatch.second)
            return RelayResolutionResult(bestOfflineMatch.first, bestOfflineMatch.second, bestOfflineMatch.third)
        }
        if (allowCrossHostFallback && bestReachableFallback != null) {
            updateRelayCache(bestReachableFallback.third, bestReachableFallback.first.uuid, bestReachableFallback.second)
            return RelayResolutionResult(bestReachableFallback.first, bestReachableFallback.second, bestReachableFallback.third)
        }
        if (bestOfflineMatch != null) {
            updateRelayCache(bestOfflineMatch.third, bestOfflineMatch.first.uuid, bestOfflineMatch.second)
            return RelayResolutionResult(bestOfflineMatch.first, bestOfflineMatch.second, bestOfflineMatch.third)
        }
        if (!allowCrossHostFallback && !isWildcard && firstNonEmpty != null) {
            val syntheticOffline = RelayInstanceInfo(uuid = rawTarget, name = rawTarget, status = RelayInstanceStatus.DISCONNECTED)
            updateRelayCache(firstNonEmpty.second, rawTarget, firstNonEmpty.first)
            return RelayResolutionResult(syntheticOffline, firstNonEmpty.first, firstNonEmpty.second)
        }
        if (firstNonEmpty != null) {
            val chosen = firstNonEmpty.first.firstOrNull { it.status.isReachable } ?: firstNonEmpty.first.first()
            updateRelayCache(firstNonEmpty.second, chosen.uuid, firstNonEmpty.first)
            return RelayResolutionResult(chosen, firstNonEmpty.first, firstNonEmpty.second)
        }
        if (!isWildcard && (rawTarget.endsWith("-v2") || rawTarget.length >= 32)) {
            val direct = RelayInstanceInfo(uuid = rawTarget, name = rawTarget, status = RelayInstanceStatus.CONNECTED)
            val auth = stateMutex.withLock { currentAuthUser }
            updateRelayCache(auth, rawTarget, listOf(direct))
            return RelayResolutionResult(direct, listOf(direct), auth)
        }
        throw lastError ?: AntigravityRpcError.Unauthorized
    }

    private suspend fun updateRelayCache(authUser: String, resolvedUuid: String, instances: List<RelayInstanceInfo>) {
        stateMutex.withLock {
            this.currentAuthUser = authUser
            this.resolvedInstanceUuidState = resolvedUuid
            this.cachedRelayInstances = instances
        }
    }

    // MARK: - Handshake & Reachability Probe

    public suspend fun verifyConnection(allowCrossHostFallback: Boolean = true): BackendHandshakeResult {
        val startMs = currentTimeMillis()
        var resolvedName: String? = null
        var selectedUuid: String? = currentResolvedInstanceUuid()
        var isSelectedOnline = true
        var serverVersion = "v2.33.0"
        var allRelayInstances = emptyList<RelayInstanceInfo>()

        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            val preferred = selectedUuid?.takeIf { it.isNotEmpty() } ?: stateMutex.withLock { targetInstanceIdentifier }
            val resolution = resolveCloudRelayInstance(
                preferredIdentifier = preferred,
                allowCrossHostFallback = allowCrossHostFallback,
            )
            resolvedName = resolution.selected.name
            selectedUuid = resolution.selected.uuid
            isSelectedOnline = resolution.selected.status.isReachable
            serverVersion = resolution.selected.version
            allRelayInstances = resolution.allInstances
        }

        val federated = fetchFederatedWorkspacesAndSummaries(
            skipRelayListRefresh = channel == RemoteConnectionChannel.CLOUD_RELAY && allRelayInstances.isNotEmpty(),
            targetInstanceUuid = if (channel == RemoteConnectionChannel.CLOUD_RELAY && !allowCrossHostFallback && isSelectedOnline) selectedUuid else null,
            includeLocal = (channel != RemoteConnectionChannel.CLOUD_RELAY) || isSelectedOnline || allowCrossHostFallback,
            includeCloud = true,
        )

        val latestInstances = federated.availableRelayInstances.ifEmpty {
            currentCachedRelayInstances().ifEmpty { allRelayInstances }
        }
        val latestActive = currentActiveRelayInstance()
        val elapsedMs = max(1L, currentTimeMillis() - startMs).toInt()
        return BackendHandshakeResult(
            latencyMs = elapsedMs,
            workspaces = federated.workspaces,
            summaries = federated.summaries,
            cloudProjects = federated.cloudProjects,
            serverVersion = latestActive?.version ?: serverVersion,
            resolvedHostname = latestActive?.name ?: resolvedName ?: host.hostname,
            resolvedInstanceUuid = selectedUuid ?: currentResolvedInstanceUuid(),
            resolvedAuthUser = if (channel == RemoteConnectionChannel.CLOUD_RELAY) currentAuthUser() else null,
            availableRelayInstances = latestInstances,
            isSelectedHostOnline = isSelectedOnline,
        )
    }

    public suspend fun probeHostReachability(allowCrossHostFallback: Boolean = true): HostReachabilityProbeResult {
        val startMs = currentTimeMillis()
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            val prev = currentCachedRelayInstances()
            val resolution = resolveCloudRelayInstance(allowCrossHostFallback = allowCrossHostFallback)
            val elapsedMs = max(1L, currentTimeMillis() - startMs).toInt()
            val prevUuids = prev.map { it.uuid to it.status }.toSet()
            val nextUuids = resolution.allInstances.map { it.uuid to it.status }.toSet()
            val prevNames = prev.map { it.uuid to it.name }.toSet()
            val nextNames = resolution.allInstances.map { it.uuid to it.name }.toSet()
            return HostReachabilityProbeResult(
                latencyMs = elapsedMs,
                availableRelayInstances = resolution.allInstances,
                activeRelayInstance = resolution.selected,
                relayTopologyChanged = prevUuids != nextUuids,
                relayMetadataChanged = prevNames != nextNames,
                isSelectedHostOnline = resolution.selected.status.isReachable,
            )
        }
        // Direct LAN lightweight reachability check
        getWorkspaceInfos()
        val elapsedMs = max(1L, currentTimeMillis() - startMs).toInt()
        return HostReachabilityProbeResult(
            latencyMs = elapsedMs,
            isSelectedHostOnline = true,
        )
    }

    // MARK: - Core Unary JSON & Binary Protobuf Transport

    public suspend fun callUnaryJson(
        method: String,
        body: JsonObject = JsonObject(emptyMap()),
        instanceUuidOverride: String? = null,
        allowCrossHostFailover: Boolean = false,
    ): JsonObject {
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            return callCloudRelayUnaryJson(
                method = method,
                body = body,
                instanceUuidOverride = instanceUuidOverride,
                allowCrossHostFailover = allowCrossHostFailover,
            )
        }

        val url = "$endpointBaseUrl$SERVICE_PREFIX/$method"
        val bodyBytes = body.toString().encodeToByteArray()
        val response = httpClient.post(url) {
            header("Connect-Protocol-Version", "1")
            csrfToken?.takeIf { it.isNotEmpty() }?.let { header("x-codeium-csrf-token", it) }
            sessionCookie?.takeIf { it.isNotEmpty() }?.let { header("Cookie", it) }
            setBody(ByteArrayContent(bodyBytes, ContentType.Application.Json))
        }
        val rawBytes = response.bodyAsBytes()
        val statusCode = response.status.value
        if (statusCode == 401 || statusCode == 403) {
            throw AntigravityRpcError.Unauthorized
        }
        if (statusCode !in 200..299) {
            throw AntigravityRpcError.HttpError(statusCode, rawBytes.decodeToString())
        }
        if (rawBytes.isEmpty()) return JsonObject(emptyMap())
        val parsed = runCatching { json.parseToJsonElement(rawBytes.decodeToString()) }.getOrNull()
        return parsed as? JsonObject
            ?: throw AntigravityRpcError.DecodingError("Expected JSON object from $method")
    }

    private suspend fun callCloudRelayUnaryJson(
        method: String,
        body: JsonObject,
        instanceUuidOverride: String? = null,
        allowCrossHostFailover: Boolean = false,
    ): JsonObject {
        if (method in localDesktopOnlyMethods) {
            throw AntigravityRpcError.HttpError(501, "$method is only available on direct local desktop hosts.")
        }
        val isCloudBackend = (body["backend"] as? JsonPrimitive)?.contentOrNull == "BACKEND_TYPE_REMOTE_AICODE" ||
            (body["backendType"] as? JsonPrimitive)?.contentOrNull == "BACKEND_TYPE_REMOTE_AICODE"
        val effectiveFailover = allowCrossHostFailover || isCloudBackend

        var workingBody = sanitizeCloudRelayPayload(method, body)
        for (attempt in 1..4) {
            val encodedPayload = workingBody.toString().encodeToByteArray()
            val (rawRespBytes, _) = callCloudRelayProxyCommand(
                method = method,
                payload = encodedPayload,
                contentType = "application/json",
                instanceUuidOverride = instanceUuidOverride,
                allowCrossHostFailover = effectiveFailover,
            )
            val respData = unwrapConnectFramedPayloadIfNeeded(rawRespBytes)
            if (respData.isEmpty()) return JsonObject(emptyMap())

            val respText = respData.decodeToString()
            val decoded = runCatching { json.parseToJsonElement(respText) as? JsonObject }.getOrNull()
            if (decoded != null) {
                val code = (decoded["code"] as? JsonPrimitive)?.contentOrNull
                val message = (decoded["message"] as? JsonPrimitive)?.contentOrNull
                if (code != null && message != null && decoded.size <= 3) {
                    val unknownField = if (attempt < 4) extractUnknownProtoFieldName(message) else null
                    if (unknownField != null) {
                        val stripped = stripFieldFromJsonObject(workingBody, unknownField)
                        if (stripped != null) {
                            workingBody = stripped
                            continue
                        }
                    }
                    throw AntigravityRpcError.HttpError(400, "$code: $message")
                }
                return decoded
            }
            val unknownField = if (attempt < 4) extractUnknownProtoFieldName(respText) else null
            if (unknownField != null) {
                val stripped = stripFieldFromJsonObject(workingBody, unknownField)
                if (stripped != null) {
                    workingBody = stripped
                    continue
                }
            }
            throw AntigravityRpcError.DecodingError("Expected JSON object from Cloud Relay $method")
        }
        return JsonObject(emptyMap())
    }

    private suspend fun selectReachableRelayUuid(
        preferred: String?,
        allowCrossHostFailover: Boolean,
    ): String? = stateMutex.withLock {
        val explicit = preferred?.takeIf { it.isNotEmpty() }
        val candidate = explicit ?: resolvedInstanceUuidState
        if (cachedRelayInstances.isEmpty()) return@withLock candidate
        if (candidate != null && cachedRelayInstances.any { it.uuid == candidate && it.status.isReachable }) {
            return@withLock candidate
        }
        val familySeed = cachedRelayInstances.firstOrNull { it.uuid == candidate }?.name
            ?: if (explicit == null && !isWildcardRelayIdentifier(targetInstanceIdentifier)) targetInstanceIdentifier else ""
        if (familySeed.isNotEmpty()) {
            cachedRelayInstances.firstOrNull { it.status.isReachable && it.sameHostFamily(familySeed) }?.let { fam ->
                if (explicit == null) resolvedInstanceUuidState = fam.uuid
                return@withLock fam.uuid
            }
        }
        if (allowCrossHostFailover) {
            val preferredLive = resolvedInstanceUuidState?.takeIf { res ->
                cachedRelayInstances.any { it.uuid == res && it.status.isReachable }
            }
            val anyLive = cachedRelayInstances.firstOrNull { it.status.isReachable }?.uuid
            (preferredLive ?: anyLive)?.let { return@withLock it }
        }
        if (candidate != null && cachedRelayInstances.any { it.uuid == candidate && !it.status.isReachable }) {
            return@withLock null
        }
        candidate
    }

    private suspend fun callCloudRelayProxyCommand(
        method: String,
        payload: ByteArray,
        contentType: String,
        instanceUuidOverride: String? = null,
        allowCrossHostFailover: Boolean = false,
    ): DecodedProxyCommandResponse {
        val needsResolve = stateMutex.withLock { instanceUuidOverride == null && resolvedInstanceUuidState == null }
        if (needsResolve) {
            resolveCloudRelayInstance(allowCrossHostFallback = allowCrossHostFailover)
        } else if (currentCachedRelayInstances().isEmpty()) {
            runCatching { listRelayInstances() }.getOrNull()?.takeIf { it.isNotEmpty() }?.let { refreshed ->
                stateMutex.withLock { cachedRelayInstances = refreshed }
            }
        }

        val initialTargetUuid = selectReachableRelayUuid(instanceUuidOverride, allowCrossHostFailover)
            ?.takeIf { it.isNotEmpty() }
            ?: throw AntigravityRpcError.HttpError(503, "Selected Antigravity Desktop host is offline")

        val url = "$relayOrigin${SapisidHashGenerator.API_SERVICE_PREFIX}/ProxyCommand?\$unique=$method"

        suspend fun sendOnce(targetUuid: String, authUserOverride: String? = null): DecodedProxyCommandResponse {
            val activeAuth = authUserOverride ?: currentAuthUser()
            val apiKey = ensureRelayWebApiKey()
            val headers = SapisidHashGenerator.buildApiServiceHeaders(
                cookieHeader = sessionCookie.orEmpty(),
                origin = relayOrigin,
                authUser = activeAuth,
                apiKey = apiKey,
                isStreaming = false,
                timestampSeconds = currentTimeMillis() / 1000L,
            )
            val jspbBody = CloudRelayJspbCodec.encodeProxyCommandRequest(
                targetInstanceUuid = targetUuid,
                rpcPath = "$SERVICE_PREFIX/$method",
                payload = payload,
                contentType = contentType,
                isStreaming = false,
            )
            val response = httpClient.post(url) {
                for ((k, v) in headers) {
                    if (!k.equals("Content-Type", ignoreCase = true)) header(k, v)
                }
                setBody(ByteArrayContent(jspbBody, ContentType.parse("application/json+protobuf")))
            }
            val rawBytes = response.bodyAsBytes()
            val code = response.status.value
            if (code == 401 || code == 403) throw AntigravityRpcError.Unauthorized
            if (code !in 200..299) throw AntigravityRpcError.HttpError(code, rawBytes.decodeToString())
            return CloudRelayJspbCodec.decodeProxyCommandResponse(rawBytes, response.flattenHeaders())
        }

        return try {
            sendOnce(initialTargetUuid)
        } catch (e: AntigravityRpcError.Unauthorized) {
            val prevAuth = currentAuthUser()
            val resolved = runCatching {
                resolveCloudRelayInstance(
                    preferredIdentifier = instanceUuidOverride ?: stateMutex.withLock { targetInstanceIdentifier },
                    allowCrossHostFallback = allowCrossHostFailover,
                )
            }.getOrNull()
            if (resolved != null && resolved.selected.status.isReachable &&
                (resolved.matchedAuthUser != prevAuth || resolved.selected.uuid != initialTargetUuid)
            ) {
                sendOnce(resolved.selected.uuid, resolved.matchedAuthUser)
            } else {
                throw e
            }
        } catch (e: Throwable) {
            val isHttp404 = e is AntigravityRpcError.HttpError && e.statusCode == 404
            val shouldFailover = e !is AntigravityRpcError ||
                (e is AntigravityRpcError.HttpError && e.statusCode in setOf(404, 502, 503, 504))
            if (shouldFailover) {
                val refreshed = runCatching { listRelayInstances() }.getOrNull().orEmpty()
                if (refreshed.isNotEmpty()) {
                    stateMutex.withLock { cachedRelayInstances = refreshed }
                    if (isHttp404 && refreshed.any { it.uuid == initialTargetUuid && it.status.isReachable }) {
                        throw e
                    }
                    val familySeed = refreshed.firstOrNull { it.uuid == initialTargetUuid }?.name
                        ?: stateMutex.withLock {
                            if (instanceUuidOverride == null && !isWildcardRelayIdentifier(targetInstanceIdentifier)) targetInstanceIdentifier else ""
                        }
                    val sameFamAlt = if (familySeed.isNotEmpty()) {
                        refreshed.firstOrNull { it.uuid != initialTargetUuid && it.status.isReachable && it.sameHostFamily(familySeed) }
                    } else null
                    val crossAlt = if (allowCrossHostFailover) {
                        refreshed.firstOrNull { it.uuid != initialTargetUuid && it.status.isReachable }
                    } else null
                    val alt = sameFamAlt ?: crossAlt
                    if (alt != null) {
                        if (instanceUuidOverride == null) {
                            stateMutex.withLock { resolvedInstanceUuidState = alt.uuid }
                        }
                        return sendOnce(alt.uuid)
                    }
                }
            }
            throw e
        }
    }

    private fun sanitizeCloudRelayPayload(method: String, body: JsonObject): JsonObject {
        val desktopMetadata = buildJsonObject {
            put("ideName", "antigravity")
            put("extensionName", "antigravity")
            put("locale", "en")
        }
        return when (method) {
            "StartCascade" -> buildJsonObject {
                put("metadata", desktopMetadata)
                put("source", "CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT")
                (body["cascadeId"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }?.let { put("cascadeId", it) }
                (body["backend"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }?.let { put("backend", it) }
                body["projectEnvConfig"]?.let { put("projectEnvConfig", it) }
                    ?: body["workspaceUris"]?.let { put("workspaceUris", it) }
            }
            "SendUserCascadeMessage" -> buildJsonObject {
                put("cascadeId", body["cascadeId"] ?: JsonPrimitive(""))
                val rawItems = (body["items"] as? JsonArray) ?: buildJsonArray {
                    val fallbackText = (body["userResponse"] as? JsonPrimitive)?.contentOrNull
                    if (!fallbackText.isNullOrEmpty()) add(buildJsonObject { put("text", fallbackText) })
                }
                put("items", rawItems)
                put("metadata", desktopMetadata)
                body["cascadeConfig"]?.let { put("cascadeConfig", it) }
            }
            "HandleCascadeUserInteraction" -> {
                val interaction = body["interaction"] as? JsonObject ?: return body
                val rc = interaction["runCommand"] as? JsonObject
                if (rc != null) {
                    val confirm = (rc["confirm"] as? JsonPrimitive)?.booleanOrNull == true
                    val verified = (rc["faceIdVerified"] as? JsonPrimitive)?.booleanOrNull == true
                    if (confirm && !verified) {
                        throw AntigravityRpcError.Unauthorized
                    }
                    val cleanedRc = JsonObject(rc.filterKeys { it != "faceIdVerified" })
                    val cleanedInteraction = JsonObject(interaction.toMutableMap().apply { put("runCommand", cleanedRc) })
                    JsonObject(mapOf("interaction" to cleanedInteraction))
                } else {
                    body
                }
            }
            else -> body
        }
    }

    private fun stripFieldFromJsonObject(obj: JsonObject, fieldName: String): JsonObject? {
        if (obj.containsKey(fieldName)) {
            return JsonObject(obj.filterKeys { it != fieldName })
        }
        val cascadeCfg = obj["cascadeConfig"] as? JsonObject ?: return null
        val plannerCfg = cascadeCfg["plannerConfig"] as? JsonObject ?: return null
        if (!plannerCfg.containsKey(fieldName)) return null
        val nextPlanner = JsonObject(plannerCfg.filterKeys { it != fieldName })
        val nextCascade = JsonObject(cascadeCfg.toMutableMap().apply { put("plannerConfig", nextPlanner) })
        return JsonObject(obj.toMutableMap().apply { put("cascadeConfig", nextCascade) })
    }

    // MARK: - Workspaces & Conversation Summaries

    public suspend fun getWorkspaceInfos(
        instanceUuidOverride: String? = null,
        originHostName: String? = null,
    ): List<WorkspaceInfo> {
        val res = callUnaryJson("GetWorkspaceInfos", instanceUuidOverride = instanceUuidOverride)
        val arr = (res["workspaces"] as? JsonArray) ?: (res["workspaceInfos"] as? JsonArray) ?: return emptyList()
        val effectiveUuid = instanceUuidOverride ?: currentResolvedInstanceUuid()
        return arr.mapNotNull {
            JsonStepAndSummaryDecoder.decodeWorkspaceInfo(
                element = it,
                originInstanceUuid = effectiveUuid,
                originHostName = originHostName ?: host.hostname,
            )
        }
    }

    public suspend fun getAllCascadeTrajectories(
        instanceUuidOverride: String? = null,
        originHostName: String? = null,
    ): List<CascadeSummary> {
        val res = callUnaryJson("GetAllCascadeTrajectories", instanceUuidOverride = instanceUuidOverride)
        val nowMs = currentTimeMillis()
        val effectiveUuid = instanceUuidOverride ?: currentResolvedInstanceUuid()
        val effectiveHost = originHostName ?: host.hostname

        val summaryMap = res["trajectorySummaries"] as? JsonObject
        if (summaryMap != null) {
            return summaryMap.entries.mapNotNull { (cid, value) ->
                JsonStepAndSummaryDecoder.decodeTrajectorySummaryEntry(
                    cascadeId = cid,
                    value = value,
                    nowEpochMs = nowMs,
                    originInstanceUuid = effectiveUuid,
                    originHostName = effectiveHost,
                )
            }.sortedWith(compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId })
        }

        val list = res["trajectories"] as? JsonArray ?: return emptyList()
        return list.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val cid = (obj["cascadeId"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
            JsonStepAndSummaryDecoder.decodeTrajectorySummaryEntry(
                cascadeId = cid,
                value = obj,
                nowEpochMs = nowMs,
                originInstanceUuid = effectiveUuid,
                originHostName = effectiveHost,
            )
        }.sortedWith(compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId })
    }

    public suspend fun fetchFederatedWorkspacesAndSummaries(
        skipRelayListRefresh: Boolean = false,
        targetInstanceUuid: String? = null,
        includeLocal: Boolean = true,
        includeCloud: Boolean = true,
    ): FederatedWorkspaceSyncResult {
        val startMs = currentTimeMillis()
        if (channel == RemoteConnectionChannel.DIRECT_HOST) {
            val (workspaces, summaries) = coroutineScope {
                val wsDeferred = async {
                    runCatching { getWorkspaceInfos(originHostName = host.hostname) }.getOrElse { emptyList() }
                }
                val sumDeferred = async {
                    getAllCascadeTrajectories(originHostName = host.hostname)
                }
                wsDeferred.await() to sumDeferred.await()
            }
            val elapsedMs = max(1L, currentTimeMillis() - startMs).toInt()
            return FederatedWorkspaceSyncResult(
                workspaces = workspaces,
                summaries = summaries,
                succeededInstanceUuids = listOf(host.instanceId),
                cloudSucceeded = summaries.any { it.isCloud },
                latencyMs = elapsedMs,
            )
        }

        val relayInstances = if (!skipRelayListRefresh) {
            runCatching { listRelayInstances() }.getOrNull()?.also { list ->
                if (list.isNotEmpty()) stateMutex.withLock { cachedRelayInstances = list }
            } ?: currentCachedRelayInstances()
        } else {
            currentCachedRelayInstances()
        }

        val reachableInstances = relayInstances.filter { it.status.isReachable }
        val targets = when {
            !includeLocal -> emptyList()
            targetInstanceUuid != null -> reachableInstances.filter { it.uuid == targetInstanceUuid }
            else -> reachableInstances
        }

        val mergedWorkspaces = linkedMapOf<String, WorkspaceInfo>()
        val mergedSummaries = linkedMapOf<String, CascadeSummary>()
        val succeededUuids = mutableListOf<String>()

        val perInstanceResults = coroutineScope {
            targets.map { inst ->
                async {
                    val wsDeferred = async {
                        runCatching {
                            getWorkspaceInfos(instanceUuidOverride = inst.uuid, originHostName = inst.name)
                        }.getOrElse { emptyList() }
                    }
                    val trajDeferred = async {
                        runCatching {
                            getAllCascadeTrajectories(instanceUuidOverride = inst.uuid, originHostName = inst.name)
                        }
                    }
                    Triple(inst, wsDeferred.await(), trajDeferred.await())
                }
            }.awaitAll()
        }

        for ((inst, wsList, trajResult) in perInstanceResults) {
            for (ws in wsList) mergedWorkspaces[ws.workspaceUri] = ws
            trajResult.onSuccess { list ->
                succeededUuids.add(inst.uuid)
                for (s in list) {
                    val existing = mergedSummaries[s.cascadeId]
                    if (existing == null || s.updatedAtEpochMs >= existing.updatedAtEpochMs) {
                        mergedSummaries[s.cascadeId] = s
                    }
                }
            }
        }

        val sortedSummaries = mergedSummaries.values.sortedWith(
            compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId }
        )
        val elapsedMs = max(1L, currentTimeMillis() - startMs).toInt()
        return FederatedWorkspaceSyncResult(
            workspaces = mergedWorkspaces.values.toList(),
            summaries = sortedSummaries,
            availableRelayInstances = relayInstances,
            succeededInstanceUuids = succeededUuids,
            cloudSucceeded = includeCloud && sortedSummaries.any { it.isCloud },
            latencyMs = elapsedMs,
        )
    }

    // MARK: - Trajectory Steps (`<600` JSON + `>=600` Binary Protobuf)

    public suspend fun loadTrajectory(
        cascadeId: String,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ) {
        val isRemoteCloud = isCloud || cascadeId.startsWith("v1/")
        val body = buildJsonObject {
            put("cascadeId", cascadeId)
            if (isRemoteCloud) put("backend", "BACKEND_TYPE_REMOTE_AICODE")
        }
        callUnaryJson("LoadTrajectory", body = body, instanceUuidOverride = instanceUuidOverride, allowCrossHostFailover = isRemoteCloud)
    }

    public suspend fun fetchTrajectoryStepsJson(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = 200,
        instanceUuidOverride: String? = null,
    ): List<CascadeStep> {
        val body = buildJsonObject {
            put("cascadeId", cascadeId)
            if (startIndex > 0) put("stepOffset", startIndex)
        }
        val res = callUnaryJson("GetCascadeTrajectorySteps", body = body, instanceUuidOverride = instanceUuidOverride)
        if (res.containsKey("truncatedAt")) {
            return fetchTrajectoryStepsProtobuf(
                cascadeId = cascadeId,
                startIndex = startIndex,
                endIndex = max(endIndex, PROTOBUF_STEP_THRESHOLD),
                instanceUuidOverride = instanceUuidOverride,
            )
        }
        val rawSteps = res["steps"] as? JsonArray ?: return emptyList()
        return rawSteps.mapIndexedNotNull { idx, item ->
            JsonStepAndSummaryDecoder.decodeJsonStep(item, cascadeId, startIndex + idx)
        }
    }

    public suspend fun fetchTrajectoryStepsProtobuf(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = PROTOBUF_STEP_THRESHOLD,
        instanceUuidOverride: String? = null,
        allowCrossHostFailover: Boolean = false,
    ): List<CascadeStep> {
        val reqBytes = ProtobufStepCodec.encodeGetStepsRequest(cascadeId, startIndex, endIndex)
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            val (rawBytes, _) = callCloudRelayProxyCommand(
                method = "GetCascadeTrajectorySteps",
                payload = reqBytes,
                contentType = "application/proto",
                instanceUuidOverride = instanceUuidOverride,
                allowCrossHostFailover = allowCrossHostFailover,
            )
            val unwrapped = unwrapConnectFramedPayloadIfNeeded(rawBytes)
            return ProtobufStepCodec.decodeStepsResponse(unwrapped, cascadeId, startingIndex = startIndex)
        }

        val url = "$endpointBaseUrl$SERVICE_PREFIX/GetCascadeTrajectorySteps"
        val response = httpClient.post(url) {
            header("Accept", "application/proto")
            header("Connect-Protocol-Version", "1")
            csrfToken?.takeIf { it.isNotEmpty() }?.let { header("x-codeium-csrf-token", it) }
            sessionCookie?.takeIf { it.isNotEmpty() }?.let { header("Cookie", it) }
            setBody(ByteArrayContent(reqBytes, ContentType.parse("application/proto")))
        }
        val data = response.bodyAsBytes()
        val code = response.status.value
        if (code == 401 || code == 403) throw AntigravityRpcError.Unauthorized
        if (code !in 200..299) {
            throw AntigravityRpcError.HttpError(code, "Binary step fetch failed")
        }
        val unwrapped = unwrapConnectFramedPayloadIfNeeded(data)
        return ProtobufStepCodec.decodeStepsResponse(unwrapped, cascadeId, startingIndex = startIndex)
    }

    public suspend fun fetchAllTrajectorySteps(
        cascadeId: String,
        knownStepCount: Int = 0,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ): List<CascadeStep> {
        val isRemoteCloud = isCloud || cascadeId.startsWith("v1/")
        val primaryTarget = if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            selectReachableRelayUuid(instanceUuidOverride, allowCrossHostFailover = isRemoteCloud)
        } else {
            instanceUuidOverride
        }

        var primaryError: Throwable? = null
        if (channel != RemoteConnectionChannel.CLOUD_RELAY || primaryTarget != null) {
            try {
                val steps = fetchStepsFromSingleInstance(cascadeId, knownStepCount, isRemoteCloud, primaryTarget)
                if (steps.isNotEmpty()) return steps
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: Throwable) {
                primaryError = e
            }
        } else {
            primaryError = AntigravityRpcError.HttpError(503, "Selected Antigravity Desktop host is offline")
        }

        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            val instances = currentCachedRelayInstances().ifEmpty {
                runCatching { listRelayInstances() }.getOrElse { emptyList() }
            }
            val seedUuid = primaryTarget ?: instanceUuidOverride ?: currentResolvedInstanceUuid()
            val familySeed = instances.firstOrNull { it.uuid == seedUuid }?.name.orEmpty()
            val peers = instances.filter { inst ->
                inst.status.isReachable && inst.uuid != primaryTarget &&
                    (isRemoteCloud || (familySeed.isNotEmpty() && inst.sameHostFamily(familySeed)))
            }
            for (peer in peers) {
                try {
                    val peerSteps = fetchStepsFromSingleInstance(cascadeId, knownStepCount, isRemoteCloud, peer.uuid)
                    if (peerSteps.isNotEmpty()) {
                        if (instanceUuidOverride == null && !isRemoteCloud) {
                            stateMutex.withLock { resolvedInstanceUuidState = peer.uuid }
                        }
                        return peerSteps
                    }
                } catch (e: AntigravityRpcError.Unauthorized) {
                    throw e
                } catch (e: Throwable) {
                    if (primaryError == null) primaryError = e
                }
            }
        }
        primaryError?.let { throw it }
        return emptyList()
    }

    private suspend fun fetchStepsFromSingleInstance(
        cascadeId: String,
        knownStepCount: Int,
        isRemoteCloud: Boolean,
        targetUuid: String?,
    ): List<CascadeStep> {
        val wakeKey = "${targetUuid ?: "direct"}|$cascadeId"
        if (knownStepCount >= PROTOBUF_STEP_THRESHOLD) {
            val firstTry = runCatching {
                fetchTrajectoryStepsProtobuf(cascadeId, 0, knownStepCount, targetUuid, isRemoteCloud)
            }
            firstTry.getOrNull()?.takeIf { it.isNotEmpty() }?.let {
                stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                return it
            }
            if (firstTry.exceptionOrNull() is AntigravityRpcError.Unauthorized) {
                throw firstTry.exceptionOrNull()!!
            }
            runCatching { loadTrajectory(cascadeId, isRemoteCloud, targetUuid) }
            val retry = fetchTrajectoryStepsProtobuf(cascadeId, 0, knownStepCount, targetUuid, isRemoteCloud)
            if (retry.isNotEmpty()) stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
            return retry
        }

        val reqBody = buildJsonObject {
            put("cascadeId", cascadeId)
            if (isRemoteCloud) put("backend", "BACKEND_TYPE_REMOTE_AICODE")
        }

        var lastError: Throwable? = null
        val firstResp = try {
            callUnaryJson("GetCascadeTrajectorySteps", reqBody, targetUuid, isRemoteCloud)
        } catch (e: AntigravityRpcError.Unauthorized) {
            throw e
        } catch (e: Throwable) {
            lastError = e
            null
        }

        if (firstResp != null && firstResp.containsKey("truncatedAt")) {
            val protoSteps = fetchTrajectoryStepsProtobuf(
                cascadeId = cascadeId,
                startIndex = 0,
                endIndex = max(knownStepCount, PROTOBUF_STEP_THRESHOLD),
                instanceUuidOverride = targetUuid,
                allowCrossHostFailover = isRemoteCloud,
            )
            if (protoSteps.isNotEmpty()) stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
            return protoSteps
        }

        var rawSteps = (firstResp?.get("steps") as? JsonArray)?.toList().orEmpty()
        val alreadyWoken = stateMutex.withLock { wakeKey in wokenInstanceCascadeKeys }
        if (rawSteps.isNotEmpty()) {
            stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
        } else if (firstResp == null || knownStepCount > 0 || !alreadyWoken) {
            runCatching { loadTrajectory(cascadeId, isRemoteCloud, targetUuid) }
            try {
                val retryResp = callUnaryJson("GetCascadeTrajectorySteps", reqBody, targetUuid, isRemoteCloud)
                lastError = null
                if (retryResp.containsKey("truncatedAt")) {
                    val protoSteps = fetchTrajectoryStepsProtobuf(
                        cascadeId, 0, max(knownStepCount, PROTOBUF_STEP_THRESHOLD), targetUuid, isRemoteCloud
                    )
                    if (protoSteps.isNotEmpty()) stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                    return protoSteps
                }
                rawSteps = (retryResp["steps"] as? JsonArray)?.toList().orEmpty()
                if (rawSteps.isNotEmpty()) stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: Throwable) {
                lastError = e
            }
        }

        if (rawSteps.isEmpty() && (firstResp == null || lastError != null || knownStepCount > 0)) {
            runCatching {
                fetchTrajectoryStepsProtobuf(cascadeId, 0, max(knownStepCount, PROTOBUF_STEP_THRESHOLD), targetUuid, isRemoteCloud)
            }.getOrNull()?.takeIf { it.isNotEmpty() }?.let {
                stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                return it
            }
        }

        if (rawSteps.isEmpty() && lastError != null) throw lastError

        if (rawSteps.size >= 590) {
            runCatching {
                fetchTrajectoryStepsProtobuf(cascadeId, 0, max(knownStepCount, rawSteps.size), targetUuid, isRemoteCloud)
            }.getOrNull()?.takeIf { it.size >= rawSteps.size }?.let {
                stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                return it
            }
        }

        val seen = mutableSetOf<Int>()
        val collected = mutableListOf<CascadeStep>()
        rawSteps.forEachIndexed { idx, el ->
            JsonStepAndSummaryDecoder.decodeJsonStep(el, cascadeId, idx)?.let { step ->
                if (seen.add(step.stepIndex)) collected.add(step)
            }
        }
        return collected.sortedBy { it.stepIndex }
    }

    // MARK: - PC Core Interactions (StartCascade, SendMessage, Approve/Reject, Cancel)

    public suspend fun startCascade(
        workspaceUri: String,
        initialPrompt: String = "",
        modelId: String = "MODEL_PLACEHOLDER_M37",
        cloudProjectId: String? = null,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ): String {
        val protoModel = JsonStepAndSummaryDecoder.normalizeProtoModelEnum(modelId)
        val clientCid = randomUuidV4()
        val body = buildJsonObject {
            put("cascadeId", clientCid)
            put("metadata", buildJsonObject {
                put("ideName", "antigravity-kmp")
                put("ideVersion", "2.33.0")
            })
            put("modelId", protoModel)
            if (!cloudProjectId.isNullOrEmpty()) {
                put("backend", "BACKEND_TYPE_REMOTE_AICODE")
                put("projectEnvConfig", buildJsonObject {
                    put("projectId", cloudProjectId)
                    put("defaultProjectEnvironment", JsonObject(emptyMap()))
                })
            } else if (isCloud) {
                put("backend", "BACKEND_TYPE_REMOTE_AICODE")
            } else if (workspaceUri.isNotEmpty() && !AntigravityCloudDetector.isGenericContainerUri(workspaceUri)) {
                put("workspaceUris", buildJsonArray { add(JsonPrimitive(workspaceUri)) })
            }
            if (initialPrompt.isNotEmpty()) {
                put("initialUserInput", initialPrompt)
            }
        }
        val res = callUnaryJson(
            method = "StartCascade",
            body = body,
            instanceUuidOverride = instanceUuidOverride,
            allowCrossHostFailover = isCloud || !cloudProjectId.isNullOrEmpty(),
        )
        return (res["cascadeId"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() } ?: clientCid
    }

    public suspend fun sendUserCascadeMessage(
        cascadeId: String,
        message: String,
        attachments: List<ComposerAttachmentChip> = emptyList(),
        modelId: String = "MODEL_PLACEHOLDER_M37",
        effort: ThinkingEffortLevel = ThinkingEffortLevel.HIGH,
        mode: CascadeExecutionMode = CascadeExecutionMode.PLANNING,
        agentPersona: String = "Default",
        isCloud: Boolean = false,
        permissionPreset: AgentPermissionPreset? = null,
        instanceUuidOverride: String? = null,
    ) {
        val isRemoteCloud = isCloud || cascadeId.startsWith("v1/")
        val protoModel = JsonStepAndSummaryDecoder.normalizeProtoModelEnum(modelId)
        val effectivePermission = permissionPreset?.takeIf { it != AgentPermissionPreset.INHERIT_GLOBAL }
            ?: AgentPermissionPreset.defaultPreset(isRemote = isRemoteCloud)

        val items = buildJsonArray {
            add(buildJsonObject { put("text", message) })
            for (chip in attachments) {
                val uri = chip.targetUri ?: chip.label
                when (chip.kind) {
                    ComposerAttachmentChip.Kind.IMAGE_SCREENSHOT,
                    ComposerAttachmentChip.Kind.AUDIO_CLIP,
                    ComposerAttachmentChip.Kind.VIDEO_CLIP,
                    ComposerAttachmentChip.Kind.PDF_DOCUMENT -> {
                        if (!chip.inlinePayload.isNullOrEmpty()) {
                            add(buildJsonObject {
                                put("item", buildJsonObject {
                                    put("media", buildJsonObject {
                                        put("uri", uri)
                                        put("label", chip.label)
                                        put("mimeType", chip.mimeType ?: "application/octet-stream")
                                        put("inlineBase64Data", chip.inlinePayload)
                                        put("kind", chip.kind.name.lowercase())
                                    })
                                })
                            })
                        } else {
                            add(buildJsonObject {
                                put("item", buildJsonObject {
                                    put("file", buildJsonObject {
                                        put("absoluteUri", uri)
                                        put("label", chip.label)
                                    })
                                })
                            })
                        }
                    }
                    ComposerAttachmentChip.Kind.DIFF_QUOTE -> add(buildJsonObject {
                        put("item", buildJsonObject {
                            put("codeQuote", buildJsonObject {
                                put("uri", uri)
                                put("label", chip.label)
                            })
                        })
                    })
                    ComposerAttachmentChip.Kind.SKILL,
                    ComposerAttachmentChip.Kind.WORKFLOW,
                    ComposerAttachmentChip.Kind.CONVERSATION_MENTION -> add(buildJsonObject {
                        put("item", buildJsonObject {
                            put("mention", buildJsonObject {
                                put("kind", chip.kind.name.lowercase())
                                put("targetUri", uri)
                                put("label", chip.label)
                            })
                        })
                    })
                    ComposerAttachmentChip.Kind.FILE_MENTION,
                    ComposerAttachmentChip.Kind.FOLDER,
                    ComposerAttachmentChip.Kind.TERMINAL_LOG -> add(buildJsonObject {
                        put("item", buildJsonObject {
                            put("file", buildJsonObject {
                                put("absoluteUri", uri)
                                put("label", chip.label)
                            })
                        })
                    })
                }
            }
        }

        val toolConfig = buildJsonObject {
            put("code", buildJsonObject { put("allowEditGitignore", true) })
            put("viewFile", buildJsonObject { put("allowViewGitignore", true) })
            put("grep", buildJsonObject { put("allowAccessGitignore", true) })
            when (effectivePermission) {
                AgentPermissionPreset.REQUEST_REVIEW -> {
                    put("runCommand", buildJsonObject {
                        put("autoCommandConfig", buildJsonObject {
                            put("autoExecutionPolicy", "CASCADE_COMMANDS_AUTO_EXECUTION_OFF")
                        })
                    })
                    put("notifyUser", buildJsonObject { put("artifactReviewMode", "ARTIFACT_REVIEW_MODE_ALWAYS") })
                }
                AgentPermissionPreset.TURBO -> {
                    put("runCommand", buildJsonObject {
                        put("autoCommandConfig", buildJsonObject {
                            put("autoExecutionPolicy", "CASCADE_COMMANDS_AUTO_EXECUTION_EAGER")
                        })
                    })
                    put("notifyUser", buildJsonObject { put("artifactReviewMode", "ARTIFACT_REVIEW_MODE_TURBO") })
                }
                else -> {
                    put("notifyUser", buildJsonObject { put("artifactReviewMode", "ARTIFACT_REVIEW_MODE_AUTO") })
                }
            }
        }

        val plannerConfig = buildJsonObject {
            put("conversational", buildJsonObject {
                put("plannerMode", "CONVERSATIONAL_PLANNER_MODE_DEFAULT")
                put("agenticMode", mode == CascadeExecutionMode.PLANNING)
            })
            put("toolConfig", toolConfig)
            put("requestedModel", buildJsonObject { put("model", protoModel) })
            put("thinkingEffort", effort.protoWireValue)
            if (agentPersona != "Default" && agentPersona.isNotEmpty()) {
                put("agentPersona", agentPersona)
            }
            put("permissionPreset", effectivePermission.rawValue)
            if (isRemoteCloud && protoModel.startsWith("MODEL_")) {
                put("planModel", protoModel)
            }
        }

        val body = buildJsonObject {
            put("cascadeId", cascadeId)
            put("items", items)
            put("userResponse", message)
            put("metadata", buildJsonObject {
                put("ideName", "antigravity-kmp")
                put("ideVersion", "2.33.0")
            })
            put("cascadeConfig", buildJsonObject { put("plannerConfig", plannerConfig) })
            put("modelConfig", buildJsonObject {
                put("modelId", modelId)
                put("thinkingEffort", effort.protoWireValue)
                put("mode", mode.displayTitle.uppercase())
                put("agentPersona", agentPersona)
                put("permissionPreset", effectivePermission.rawValue)
            })
        }

        callUnaryJson(
            method = "SendUserCascadeMessage",
            body = body,
            instanceUuidOverride = instanceUuidOverride,
            allowCrossHostFailover = isRemoteCloud,
        )
    }

    public suspend fun handleCascadeUserInteraction(
        payload: CascadeUserInteractionPayload,
        instanceUuidOverride: String? = null,
    ) {
        val rc = payload.runCommand
        val perm = payload.permission
        val fp = payload.filePermission
        val qa = payload.askQuestion
        val genericConfirm = payload.genericConfirm

        val interactionObj = buildJsonObject {
            put("trajectoryId", payload.cascadeId)
            put("stepIndex", payload.stepIndex)
            when {
                rc != null -> {
                    put("runCommand", buildJsonObject {
                        put("confirm", rc.confirm)
                        put("proposedCommandLine", rc.proposedCommandLine)
                        put("submittedCommandLine", rc.submittedCommandLine)
                        put("faceIdVerified", rc.biometricVerified)
                    })
                }
                perm != null -> {
                    put("permission", buildJsonObject {
                        put("allow", perm.allow)
                        put("scope", perm.scope)
                        put("turnGrants", buildJsonObject {
                            put("allow", buildJsonArray { perm.grantPatterns.forEach { add(JsonPrimitive(it)) } })
                            put("deny", JsonArray(emptyList()))
                        })
                    })
                }
                fp != null -> {
                    put("filePermission", buildJsonObject {
                        put("allow", fp.allow)
                        put("scope", fp.scope)
                        fp.absolutePathUri?.takeIf { it.isNotEmpty() }?.let { put("absolutePathUri", it) }
                    })
                }
                qa != null -> {
                    put("askQuestion", buildJsonObject {
                        put("selectedOptions", buildJsonArray { qa.selectedOptions.forEach { add(JsonPrimitive(it)) } })
                        qa.customResponse?.let { put("customResponse", it) }
                    })
                }
                genericConfirm != null -> {
                    val memberKey = payload.rawMemberKey ?: payload.kind.wireKey
                    if (payload.kind == RequestedInteraction.MemberKind.DEPLOY) {
                        put(memberKey, buildJsonObject { put("cancel", !genericConfirm) })
                    } else {
                        put(memberKey, buildJsonObject {
                            put("confirm", genericConfirm)
                            payload.approvalScope?.let { put("scope", it) }
                        })
                    }
                }
            }
        }

        try {
            callUnaryJson(
                method = "HandleCascadeUserInteraction",
                body = buildJsonObject { put("interaction", interactionObj) },
                instanceUuidOverride = instanceUuidOverride,
            )
        } catch (e: AntigravityRpcError.HttpError) {
            val lowerBody = e.body.lowercase()
            if (e.statusCode != 400 && !lowerBody.contains("unknown field") && !lowerBody.contains("invalid_argument")) {
                throw e
            }
            // Retry with minimal proto3-compatible fields
            val fallbackObj = buildJsonObject {
                put("trajectoryId", payload.cascadeId)
                put("stepIndex", payload.stepIndex)
                when {
                    perm != null -> {
                        put("permission", buildJsonObject {
                            put("allow", perm.allow)
                            if (perm.grantPatterns.isNotEmpty()) {
                                put("turnGrants", buildJsonObject {
                                    put("allow", buildJsonArray { perm.grantPatterns.forEach { add(JsonPrimitive(it)) } })
                                    put("deny", JsonArray(emptyList()))
                                })
                            }
                        })
                    }
                    fp != null -> {
                        val compatScope = if (fp.scope == "PERMISSION_SCOPE_CONVERSATION" || fp.scope == "PERMISSION_SCOPE_ALWAYS") {
                            "PERMISSION_SCOPE_TURN"
                        } else {
                            "PERMISSION_SCOPE_ONCE"
                        }
                        put("filePermission", buildJsonObject {
                            put("allow", fp.allow)
                            put("scope", compatScope)
                            fp.absolutePathUri?.takeIf { it.isNotEmpty() }?.let { put("absolutePathUri", it) }
                        })
                    }
                    genericConfirm != null -> {
                        val memberKey = payload.rawMemberKey ?: payload.kind.wireKey
                        val useAllow = lowerBody.contains("\"confirm\"")
                        put(memberKey, buildJsonObject {
                            put(if (useAllow) "allow" else "confirm", genericConfirm)
                        })
                    }
                    else -> throw e
                }
            }
            callUnaryJson(
                method = "HandleCascadeUserInteraction",
                body = buildJsonObject { put("interaction", fallbackObj) },
                instanceUuidOverride = instanceUuidOverride,
            )
        }
    }

    public suspend fun cancelCascadeInvocation(
        cascadeId: String,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "CancelCascadeInvocation",
            body = buildJsonObject { put("cascadeId", cascadeId) },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun pinCascade(cascadeId: String, isPinned: Boolean, instanceUuidOverride: String? = null) {
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            callUnaryJson(
                method = "UpdateConversationAnnotations",
                body = buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("annotations", buildJsonObject { put("pinned", isPinned) })
                    put("mergeAnnotations", true)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        } else {
            callUnaryJson(
                method = "PinCascade",
                body = buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("isPinned", isPinned)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        }
    }

    public suspend fun renameCascade(cascadeId: String, newTitle: String, instanceUuidOverride: String? = null) {
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            callUnaryJson(
                method = "UpdateConversationAnnotations",
                body = buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("annotations", buildJsonObject { put("title", newTitle) })
                    put("mergeAnnotations", true)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        } else {
            callUnaryJson(
                method = "RenameCascade",
                body = buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("title", newTitle)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        }
    }

    public suspend fun archiveCascade(cascadeId: String, isArchived: Boolean = true, instanceUuidOverride: String? = null) {
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            callUnaryJson(
                method = "UpdateConversationAnnotations",
                body = buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("annotations", buildJsonObject { put("archived", isArchived) })
                    put("mergeAnnotations", true)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        } else {
            callUnaryJson(
                method = "ArchiveCascade",
                body = buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("isArchived", isArchived)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        }
    }

    public suspend fun deleteCascade(cascadeId: String, instanceUuidOverride: String? = null) {
        val method = if (channel == RemoteConnectionChannel.CLOUD_RELAY) "DeleteCascadeTrajectory" else "DeleteCascade"
        callUnaryJson(
            method = method,
            body = buildJsonObject { put("cascadeId", cascadeId) },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun createProjectWorkspace(draft: NewProjectDraft): ProjectWorkspace {
        val repoName = draft.selectedRepo?.fullName ?: draft.projectName
        val body = buildJsonObject {
            put("name", draft.projectName)
            put("runtime", if (draft.runsOn == ProjectRuntimeTarget.CLOUD) "cloud" else "macbook_pro")
            put("source", draft.source.displayTitle)
            put("repository", repoName)
            put("branchWorktree", draft.branchWorktree)
            if (draft.driveResourceLinks.isNotEmpty()) {
                put("googleDriveLinks", buildJsonArray { draft.driveResourceLinks.forEach { add(JsonPrimitive(it)) } })
            }
            if (draft.envSetupScript.isNotBlank()) {
                put("envSetupScript", draft.envSetupScript)
            }
        }
        val res = callUnaryJson("CreateProjectWorkspace", body)
        val workspaceUri = (res["workspaceUri"] as? JsonPrimitive)?.contentOrNull
            ?: if (draft.runsOn == ProjectRuntimeTarget.CLOUD) "cloud://$repoName" else "file:///Users/dev/code/${draft.projectName}"
        return ProjectWorkspace(
            id = draft.projectName,
            name = draft.projectName,
            pathDisplay = if (draft.runsOn == ProjectRuntimeTarget.CLOUD) "cloud://$repoName" else "~/code/${draft.projectName}",
            workspaceUri = workspaceUri,
            runtime = draft.runsOn,
            hostName = if (draft.runsOn == ProjectRuntimeTarget.CLOUD) "Antigravity" else host.hostname,
            activeBranch = draft.selectedRepo?.defaultBranch ?: "main",
        )
    }

    public suspend fun listAutomations(): List<AutomationItem> {
        val res = callUnaryJson("ListAutomations")
        val list = res["automations"] as? JsonArray ?: return emptyList()
        return list.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val id = (obj["id"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
            val title = (obj["title"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
            val state = (obj["state"] as? JsonPrimitive)?.contentOrNull?.lowercase().orEmpty()
            val section = when {
                state.contains("pause") -> AutomationSectionKind.PAUSED
                state.contains("always") -> AutomationSectionKind.ALWAYS_ON
                else -> AutomationSectionKind.SCHEDULED
            }
            AutomationItem(
                id = id,
                title = title,
                projectSlug = (obj["project"] as? JsonPrimitive)?.contentOrNull ?: "ledger-svc",
                scheduleSummary = (obj["schedule"] as? JsonPrimitive)?.contentOrNull ?: "Scheduled",
                section = section,
                nextRunText = (obj["nextRun"] as? JsonPrimitive)?.contentOrNull ?: "",
                lastRunText = (obj["lastRun"] as? JsonPrimitive)?.contentOrNull ?: "",
                modelLabel = (obj["model"] as? JsonPrimitive)?.contentOrNull,
            )
        }
    }

    public suspend fun triggerAutomationNow(automationId: String) {
        callUnaryJson("TriggerAutomationNow", buildJsonObject { put("automationId", automationId) })
    }

    // MARK: - 5-Byte Connect-RPC Server Streaming (`JetboxSubscribeToSummaries`, etc.)

    public fun subscribeEnvelopeStream(
        method: String,
        body: JsonObject = JsonObject(emptyMap()),
        instanceUuidOverride: String? = null,
    ): Flow<JsonObject> = flow {
        val innerPayload = ConnectEnvelope.encode(body.toString().encodeToByteArray())
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            val targetUuid = selectReachableRelayUuid(instanceUuidOverride, allowCrossHostFailover = false)
                ?.takeIf { it.isNotEmpty() }
                ?: throw AntigravityRpcError.HttpError(503, "Selected Antigravity Desktop host is offline")
            val url = "$relayOrigin${SapisidHashGenerator.API_SERVICE_PREFIX}/StreamProxyCommand?\$unique=$method"
            val apiKey = ensureRelayWebApiKey()
            val headers = SapisidHashGenerator.buildApiServiceHeaders(
                cookieHeader = sessionCookie.orEmpty(),
                origin = relayOrigin,
                authUser = currentAuthUser(),
                apiKey = apiKey,
                isStreaming = true,
                timestampSeconds = currentTimeMillis() / 1000L,
            )
            val reqBytes = CloudRelayJspbCodec.encodeProxyCommandRequest(
                targetInstanceUuid = targetUuid,
                rpcPath = "$SERVICE_PREFIX/$method",
                payload = innerPayload,
                contentType = "application/connect+json",
                isStreaming = true,
            )
            streamingHttpClient.preparePost(url) {
                for ((k, v) in headers) {
                    if (!k.equals("Content-Type", ignoreCase = true)) header(k, v)
                }
                setBody(ByteArrayContent(reqBytes, ContentType.parse("application/json+protobuf")))
            }.execute { response ->
                val code = response.status.value
                if (code == 401 || code == 403) throw AntigravityRpcError.Unauthorized
                if (code !in 200..299) throw AntigravityRpcError.HttpError(code, "StreamProxyCommand HTTP $code")
                val respHeaders = response.flattenHeaders()
                val headerBase64 = respHeaders.any { (k, v) ->
                    (k.equals("x-goog-safety-encoding", ignoreCase = true) ||
                        k.equals("content-transfer-encoding", ignoreCase = true)) &&
                        v.contains("base64", ignoreCase = true)
                }
                val jspbParser = CloudRelayJspbStreamParser()
                val connectParser = ConnectStreamParser()
                val b64Decoder = StreamingBase64Decoder()
                val channelReader = response.bodyAsChannel()
                val buf = ByteArray(4096)

                var done = false
                while (!done) {
                    val read = channelReader.readAvailable(buf, 0, buf.size)
                    if (read < 0) break
                    if (read == 0) continue
                    val rawSlice = buf.copyOf(read)
                    val feedSlice = if (headerBase64) b64Decoder.feed(rawSlice) else rawSlice
                    val innerChunks = jspbParser.feed(feedSlice)
                    for (chunk in innerChunks) {
                        val frames = connectParser.feed(chunk)
                        for (frame in frames) {
                            if (frame.isEndStream) {
                                done = true
                                break
                            }
                            val frameBytes = if (frame.isCompressed) {
                                CloudRelayJspbCodec.decompressPayloadIfNeeded(frame.payload)
                            } else {
                                frame.payload
                            }
                            val obj = runCatching { json.parseToJsonElement(frameBytes.decodeToString()) as? JsonObject }.getOrNull()
                            if (obj != null) emit(obj)
                        }
                        if (done) break
                    }
                }
            }
        } else {
            val url = "$endpointBaseUrl$SERVICE_PREFIX/$method"
            streamingHttpClient.preparePost(url) {
                header("Connect-Protocol-Version", "1")
                csrfToken?.takeIf { it.isNotEmpty() }?.let { header("x-codeium-csrf-token", it) }
                sessionCookie?.takeIf { it.isNotEmpty() }?.let { header("Cookie", it) }
                setBody(ByteArrayContent(innerPayload, ContentType.parse("application/connect+json")))
            }.execute { response ->
                val code = response.status.value
                if (code == 401 || code == 403) throw AntigravityRpcError.Unauthorized
                if (code !in 200..299) throw AntigravityRpcError.HttpError(code, "Stream HTTP $code")
                val connectParser = ConnectStreamParser()
                val channelReader = response.bodyAsChannel()
                val buf = ByteArray(4096)

                var done = false
                while (!done) {
                    val read = channelReader.readAvailable(buf, 0, buf.size)
                    if (read < 0) break
                    if (read == 0) continue
                    val frames = connectParser.feed(buf.copyOf(read))
                    for (frame in frames) {
                        if (frame.isEndStream) {
                            done = true
                            break
                        }
                        val frameBytes = if (frame.isCompressed) {
                            CloudRelayJspbCodec.decompressPayloadIfNeeded(frame.payload)
                        } else {
                            frame.payload
                        }
                        val obj = runCatching { json.parseToJsonElement(frameBytes.decodeToString()) as? JsonObject }.getOrNull()
                        if (obj != null) emit(obj)
                    }
                }
            }
        }
    }

    public fun close() {
        if (ownsHttpClients) {
            httpClient.close()
            streamingHttpClient.close()
        }
    }

    private fun HttpResponse.flattenHeaders(): Map<String, String> {
        val map = linkedMapOf<String, String>()
        headers.forEach { name, values ->
            map[name.lowercase()] = values.joinToString(", ")
        }
        return map
    }

    private fun extractHostFromUrl(rawUrl: String): String {
        val afterScheme = rawUrl.substringAfter("://", rawUrl)
        val authority = afterScheme.substringBefore('/').substringBefore('?').substringBefore('#')
        return if (authority.startsWith("[")) {
            authority.substringBefore(']') + "]"
        } else {
            authority.substringBefore(':')
        }
    }
}
