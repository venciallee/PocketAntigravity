package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AntigravityCloudDetector
import dev.antigravity.shared.model.ArtifactSnapshot
import dev.antigravity.shared.model.AutomationItem
import dev.antigravity.shared.model.AutomationSectionKind
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeModelConfig
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.CascadeUserInteractionPayload
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.ConversationOverviewSnapshot
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.CustomizationsCatalog
import dev.antigravity.shared.model.DiffCompareMode
import dev.antigravity.shared.model.DiffLineComment
import dev.antigravity.shared.model.EmbedResourceSource
import dev.antigravity.shared.model.FilePatchDiff
import dev.antigravity.shared.model.GitCommitDraft
import dev.antigravity.shared.model.GitCommitResult
import dev.antigravity.shared.model.GitHubRepoItem
import dev.antigravity.shared.model.LiveModelCatalogResult
import dev.antigravity.shared.model.LiveUserProfile
import dev.antigravity.shared.model.ModelUsageQuota
import dev.antigravity.shared.model.NewProjectDraft
import dev.antigravity.shared.model.PlanInlineComment
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.model.ResolvedEmbedResource
import dev.antigravity.shared.model.SidecarManageAction
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlin.Throws
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
    public val resolvedRelayApiKey: String? = null,
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

        private val localDesktopOnlyMethods = setOf("OpenWorkspaceInFinder", "ReadArtifactFile")

        public fun extractUnknownProtoFieldName(message: String): String? =
            ProtocolCompatibilityEngine.extractUnknownProtoFieldName(message)

        internal fun extractJsonTruncationCeiling(response: JsonObject, fallbackStepCount: Int): Int? {
            val truncatedPrim = response["truncatedAt"] as? JsonPrimitive
            if (truncatedPrim != null && truncatedPrim !is JsonNull) {
                val parsed = truncatedPrim.intOrNull ?: truncatedPrim.contentOrNull?.toIntOrNull()
                if (parsed != null) {
                    if (parsed > 0) return parsed
                } else if (truncatedPrim.booleanOrNull == true) {
                    return max(1, fallbackStepCount)
                }
            }
            val isTruncated = (response["isTruncated"] as? JsonPrimitive)?.booleanOrNull == true
            val truncated = (response["truncated"] as? JsonPrimitive)?.booleanOrNull == true
            if (isTruncated || truncated) {
                return max(1, fallbackStepCount)
            }
            return null
        }

        internal fun isJsonPayloadLimitError(error: Throwable): Boolean {
            if (error is AntigravityRpcError.HttpError) {
                if (error.statusCode == 413) return true
                val lower = error.body.lowercase()
                return lower.contains("resource_exhausted") ||
                    lower.contains("message too large") ||
                    lower.contains("max message size") ||
                    lower.contains("payload too large") ||
                    lower.contains("too many steps")
            }
            val lower = error.message?.lowercase().orEmpty()
            return lower.contains("resource_exhausted") ||
                lower.contains("message too large") ||
                lower.contains("max message size") ||
                lower.contains("payload too large") ||
                lower.contains("too many steps")
        }

        internal fun isBinaryProtobufUnsupportedError(error: Throwable): Boolean {
            if (error is AntigravityRpcError.HttpError) {
                if (error.statusCode == 415 || error.statusCode == 406 || error.statusCode == 501) {
                    return true
                }
                if (error.statusCode == 400) {
                    val lower = error.body.lowercase()
                    return lower.contains("unsupported media") ||
                        lower.contains("application/proto") ||
                        lower.contains("content-type") ||
                        lower.contains("invalid json") ||
                        lower.contains("unexpected character")
                }
            }
            return false
        }

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
    private var discoveredRelayApiKeyCandidates: List<String> = emptyList()
    private val rejectedRelayApiKeys = mutableSetOf<String>()
    private var attemptedApiKeyDiscovery: Boolean = false
    private var didRunOriginApiKeyDiscovery: Boolean = false
    private var cachedRelayInstances: List<RelayInstanceInfo> = emptyList()
    private var preferredCloudInstanceUuid: String? = null
    private val cachedCloudProjectsById = linkedMapOf<String, ProjectWorkspace>()
    private var cachedValidUpstreamModels: Set<String>? = null
    private var cachedDefaultUpstreamModel: String? = null
    private val wokenInstanceCascadeKeys = mutableSetOf<String>()
    private val capabilityProfilesByHost = linkedMapOf<String, HostCapabilityProfile>()

    private enum class CloudTrajectoryBackendField(val jsonKey: String?) {
        BACKEND("backend"),
        BACKEND_TYPE("backendType"),
        NONE(null),
    }

    private val preferredCloudBackendFieldByHostAndMethod = linkedMapOf<String, CloudTrajectoryBackendField>()

    @kotlin.concurrent.Volatile
    private var handshakeStartMs: Long = currentTimeMillis()

    @kotlin.concurrent.Volatile
    private var handshakeKeySource: String = if (relayApiKey?.trim()?.isNotEmpty() == true) {
        "provided(${relayApiKey.trim().length})"
    } else {
        "none"
    }

    @kotlin.concurrent.Volatile
    private var handshakeTraceEvents: List<String> = emptyList()

    private fun resetHandshakeTrace() {
        handshakeStartMs = currentTimeMillis()
        handshakeTraceEvents = emptyList()
    }

    private fun recordHandshakeTrace(event: String) {
        val elapsed = max(0L, currentTimeMillis() - handshakeStartMs)
        val entry = "$event@${elapsed}ms"
        val current = handshakeTraceEvents
        handshakeTraceEvents = if (current.size >= 16) current.drop(1) + entry else current + entry
    }

    /**
     * Zero-secret stage-by-stage handshake diagnostic breadcrumb (never prints cookie values or API key text).
     */
    public fun currentHandshakeDiagnostic(): String {
        val originHost = extractHostFromUrl(relayOrigin).ifEmpty { relayOrigin }
        val ck = SapisidHashGenerator.summarizeCookieNames(sessionCookie.orEmpty())
        val trace = handshakeTraceEvents.joinToString("->").ifEmpty { "init" }
        return "engine=${platformTransportEngineName()} origin=$originHost key=$handshakeKeySource ck=$ck trace=$trace"
    }

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

    private fun hostCapabilityKey(instanceUuidOverride: String?): String =
        instanceUuidOverride?.takeIf { it.isNotBlank() }
            ?: resolvedInstanceUuidState?.takeIf { it.isNotBlank() }
            ?: host.instanceId.takeIf { it.isNotBlank() }
            ?: endpointBaseUrl

    private fun getOrCreateProfileLocked(key: String): HostCapabilityProfile =
        capabilityProfilesByHost.getOrPut(key) {
            val defaultKey = hostCapabilityKey(null)
            val initialVer = if (key == defaultKey) {
                HostCapabilityProfile.normalizedVersionString(host.version)
            } else {
                null
            }
            HostCapabilityProfile(hostKey = key, reportedVersion = initialVer)
        }

    /**
     * Returns the runtime-discovered [HostCapabilityProfile] for [hostKey] (or the active host when `null`).
     */
    public suspend fun capabilityProfile(hostKey: String? = null): HostCapabilityProfile =
        stateMutex.withLock {
            val key = hostKey?.takeIf { it.isNotBlank() } ?: hostCapabilityKey(null)
            getOrCreateProfileLocked(key)
        }

    /**
     * Returns all per-host [HostCapabilityProfile] snapshots observed during this client's lifetime.
     */
    public suspend fun allCapabilityProfiles(): Map<String, HostCapabilityProfile> =
        stateMutex.withLock { capabilityProfilesByHost.toMap() }

    private suspend fun mutateCapabilityProfile(
        instanceUuidOverride: String? = null,
        transform: (HostCapabilityProfile) -> HostCapabilityProfile,
    ) {
        stateMutex.withLock {
            val key = hostCapabilityKey(instanceUuidOverride)
            val current = getOrCreateProfileLocked(key)
            capabilityProfilesByHost[key] = transform(current)
        }
    }

    public suspend fun learnedJsonStepCeiling(instanceUuidOverride: String? = null): Int? =
        stateMutex.withLock {
            getOrCreateProfileLocked(hostCapabilityKey(instanceUuidOverride)).learnedJsonStepCeiling
        }

    public suspend fun isBinaryProtobufStepsUnsupported(instanceUuidOverride: String? = null): Boolean =
        stateMutex.withLock {
            getOrCreateProfileLocked(hostCapabilityKey(instanceUuidOverride)).binaryProtobufStepsUnsupported
        }

    public suspend fun updateReportedHostVersion(version: String, instanceUuidOverride: String? = null) {
        val trimmed = version.trim()
        if (trimmed.isEmpty()) return
        stateMutex.withLock {
            updateReportedHostVersionLocked(hostCapabilityKey(instanceUuidOverride), trimmed)
        }
    }

    private fun updateReportedHostVersionLocked(key: String, version: String) {
        val trimmed = version.trim()
        if (trimmed.isEmpty()) return
        val current = getOrCreateProfileLocked(key)
        capabilityProfilesByHost[key] = current.updateReportedVersion(trimmed)
    }

    private fun recordRelayInstanceVersionsLocked(instances: List<RelayInstanceInfo>) {
        for (inst in instances) {
            if (inst.uuid.isNotBlank()) {
                var profile = getOrCreateProfileLocked(inst.uuid)
                if (inst.version.isNotBlank()) {
                    profile = profile.updateReportedVersion(inst.version)
                }
                profile = profile.recordPassiveSignal(
                    HostCapability.STREAM_CHUNKING,
                    if (inst.supportsChunking) CapabilitySupportState.SUPPORTED else CapabilitySupportState.UNSUPPORTED,
                )
                capabilityProfilesByHost[inst.uuid] = profile
            }
        }
    }

    private suspend fun recordLearnedJsonStepCeiling(ceiling: Int, instanceUuidOverride: String?) {
        if (ceiling <= 0) return
        mutateCapabilityProfile(instanceUuidOverride) { it.recordJsonStepCeiling(ceiling) }
    }

    private suspend fun recordBinaryProtobufStepsUnsupported(instanceUuidOverride: String?) {
        mutateCapabilityProfile(instanceUuidOverride) { it.recordBinaryProtobufStepsUnsupported() }
    }

    private suspend fun observeResponseMetadata(
        headers: Map<String, String>,
        body: JsonObject?,
        method: String,
        instanceUuidOverride: String?,
    ) {
        val bridgeCaps = ProtocolCompatibilityEngine.extractBridgeCapabilities(headers)
        val detectedVersion = ProtocolCompatibilityEngine.extractVersionFromHeadersOrBody(headers, body)
        mutateCapabilityProfile(instanceUuidOverride) { profile ->
            var updated = profile.recordMethodSupported(method)
            if (bridgeCaps.isNotEmpty()) {
                updated = updated.recordBridgeCapabilities(bridgeCaps)
            }
            if (detectedVersion != null) {
                updated = updated.updateReportedVersion(detectedVersion)
            }
            updated
        }
    }

    /**
     * Applies one self-healing compatibility mutation (`unknown field` recursive strip with rich item
     * folding, or `invalid enum` downgrade / holding-key strip) when a Desktop host returns HTTP 400
     * or `invalid_argument`, caching the learned rule per host + method for future round-trips.
     */
    private suspend fun attemptSelfHealingDowngrade(
        errorMessage: String,
        method: String,
        body: JsonObject,
        instanceUuidOverride: String?,
    ): JsonObject? {
        val unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(errorMessage)
        if (unknownField != null) {
            val (updated, removed) = ProtocolCompatibilityEngine.recursivelyRemoveField(unknownField, body)
            if (removed) {
                mutateCapabilityProfile(instanceUuidOverride) { p ->
                    p.recordStrippedField(unknownField, forMethod = method)
                }
                return updated
            }
        }
        val invalidEnum = ProtocolCompatibilityEngine.extractInvalidEnumValue(errorMessage)
        if (invalidEnum != null) {
            val replacement = ProtocolCompatibilityEngine.downgradedEnumReplacement(invalidEnum)
            if (replacement != null) {
                val (updated, replaced) = ProtocolCompatibilityEngine.recursivelyReplaceEnumValue(
                    invalidValue = invalidEnum,
                    replacement = replacement,
                    body = body,
                )
                if (replaced) {
                    mutateCapabilityProfile(instanceUuidOverride) { p ->
                        p.recordDowngradedEnum(from = invalidEnum, to = replacement, forMethod = method)
                    }
                    return updated
                }
            }
            val (strippedBody, removedKeys) = ProtocolCompatibilityEngine.recursivelyRemoveKeysWithValue(
                targetValue = invalidEnum,
                body = body,
            )
            if (removedKeys.isNotEmpty()) {
                mutateCapabilityProfile(instanceUuidOverride) { p ->
                    var next = p
                    for (key in removedKeys) {
                        next = next.recordStrippedField(key, forMethod = method)
                    }
                    next
                }
                return strippedBody
            }
        }
        return null
    }

    /**
     * KTOR-9183-safe timeout wrapper: Ktor 3.1.x can occasionally surface a plain [CancellationException]
     * when a request aborts on timeout instead of `TimeoutCancellationException`. Only rethrow when the
     * enclosing coroutine itself is no longer active.
     */
    private suspend fun <T> withSafeTimeoutOrNull(
        timeoutMs: Long,
        block: suspend () -> T,
    ): T? = try {
        withTimeoutOrNull(timeoutMs) { block() }
    } catch (e: CancellationException) {
        if (!currentCoroutineContext().isActive) throw e
        null
    }

    private suspend fun ensureRelayWebApiKey(forceRefresh: Boolean = false): String? {
        val existing = stateMutex.withLock {
            if (forceRefresh) {
                currentRelayApiKey = null
                if (!didRunOriginApiKeyDiscovery) {
                    discoveredRelayApiKeyCandidates = emptyList()
                }
                attemptedApiKeyDiscovery = true
                return@withLock null
            }
            if (!currentRelayApiKey.isNullOrEmpty() && currentRelayApiKey !in rejectedRelayApiKeys) {
                return@withLock currentRelayApiKey
            }
            val nextCandidate = discoveredRelayApiKeyCandidates.firstOrNull { it !in rejectedRelayApiKeys }
            if (nextCandidate != null) {
                currentRelayApiKey = nextCandidate
                return@withLock nextCandidate
            }
            if (attemptedApiKeyDiscovery || didRunOriginApiKeyDiscovery) {
                return@withLock currentRelayApiKey
            }
            attemptedApiKeyDiscovery = true
            null
        }
        if (existing != null) return existing

        val discovered = discoverRelayWebApiKeysFromOrigin()
        val chosen = stateMutex.withLock {
            didRunOriginApiKeyDiscovery = true
            if (discovered.isNotEmpty()) {
                discoveredRelayApiKeyCandidates = (discoveredRelayApiKeyCandidates + discovered).distinct()
            }
            val nextValid = discoveredRelayApiKeyCandidates.firstOrNull { it !in rejectedRelayApiKeys }
            if (!nextValid.isNullOrEmpty()) {
                currentRelayApiKey = nextValid
            }
            nextValid ?: discovered.firstOrNull()
        }
        return chosen
    }

    private suspend fun discoverCandidateRelayApiKeys(forceRefresh: Boolean = false): List<String> {
        val cached = stateMutex.withLock {
            // Never re-crawl HTML/JS a second time within the same client handshake once origin discovery has run.
            if (didRunOriginApiKeyDiscovery || (!forceRefresh && discoveredRelayApiKeyCandidates.isNotEmpty())) {
                discoveredRelayApiKeyCandidates
            } else {
                null
            }
        }
        if (cached != null) return cached
        val fresh = discoverRelayWebApiKeysFromOrigin()
        return stateMutex.withLock {
            attemptedApiKeyDiscovery = true
            didRunOriginApiKeyDiscovery = true
            if (fresh.isNotEmpty()) {
                discoveredRelayApiKeyCandidates = (discoveredRelayApiKeyCandidates + fresh).distinct()
            }
            discoveredRelayApiKeyCandidates
        }
    }

    private suspend fun discoverRelayWebApiKeysFromOrigin(): List<String> {
        val originHost = extractHostFromUrl(relayOrigin).lowercase()
        val candidatePages = buildList {
            if (extractHostFromUrl(endpointBaseUrl).lowercase() == originHost && endpointBaseUrl.isNotEmpty()) {
                add(endpointBaseUrl)
            }
            val rootUrl = "${relayOrigin.trimEnd('/')}/"
            if (rootUrl !in this) {
                add(rootUrl)
            }
        }

        val cleanedCookie = sessionCookie?.trim()?.let { raw ->
            if (raw.lowercase().startsWith("cookie:")) raw.drop("cookie:".length).trim() else raw
        }?.takeIf {
            it.isNotEmpty() && !it.lowercase().startsWith("bearer ") && !it.startsWith("ya29.")
        }

        val collectedKeys = linkedSetOf<String>()
        val scriptUrlsToInspect = linkedSetOf<String>()
        recordHandshakeTrace("discoverKey:start")

        // Enforce a hard 6s ceiling across ALL HTML + parallel script discovery so slow VPN
        // or stalled HTML bodies can never consume the 25s handshake budget.
        withSafeTimeoutOrNull(6_000L) {
            for ((pageIdx, pageUrl) in candidatePages.withIndex()) {
                // Skip fetching the root fallback page if the target page already gave us keys or bootstrap scripts.
                if (pageIdx > 0 && (collectedKeys.isNotEmpty() || scriptUrlsToInspect.isNotEmpty())) {
                    break
                }
                val pageHost = extractHostFromUrl(pageUrl).lowercase()
                val fetchedPage = try {
                    withSafeTimeoutOrNull(if (pageIdx == 0) 3_000L else 2_500L) {
                        val pageResp = httpClient.get(pageUrl) {
                            header("Accept", "text/html,application/xhtml+xml,application/javascript,*/*;q=0.8")
                            header("User-Agent", SapisidHashGenerator.MOBILE_REMOTE_USER_AGENT)
                            header("Referer", "${relayOrigin.trimEnd('/')}/")
                            if (pageHost == originHost && cleanedCookie != null) {
                                header("Cookie", cleanedCookie)
                            }
                        }
                        if (pageResp.status.value !in 200..399) {
                            return@withSafeTimeoutOrNull null
                        }
                        val finalUrl = pageResp.call.request.url.toString()
                        val finalHost = extractHostFromUrl(finalUrl).lowercase()
                        if (finalHost.isNotEmpty() &&
                            originHost.isNotEmpty() &&
                            finalHost != originHost &&
                            !RemoteHostInstance.isAntigravityRelayHost(finalHost)
                        ) {
                            return@withSafeTimeoutOrNull null
                        }
                        val headerKey = pageResp.headers["X-Goog-Api-Key"]?.trim()?.takeIf { it.isNotEmpty() }
                        val html = runCatching { pageResp.bodyAsText() }.getOrDefault("")
                        Triple(finalUrl.ifBlank { pageUrl }, headerKey, html)
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    null
                } ?: continue

                val (effectiveBaseUrl, headerKey, html) = fetchedPage
                headerKey?.let { collectedKeys.add(it) }
                collectedKeys.addAll(SapisidHashGenerator.extractAllWebApiKeys(html))
                scriptUrlsToInspect.addAll(
                    SapisidHashGenerator.extractBootstrapScriptUrls(
                        html = html,
                        baseUrl = effectiveBaseUrl,
                        limit = 8,
                    )
                )
                if (collectedKeys.size >= 4) break
            }

            // Inspect prioritized bootstrap script bundles IN PARALLEL with a tight 3s per-script budget.
            if (collectedKeys.size < 3 && scriptUrlsToInspect.isNotEmpty()) {
                val batch = scriptUrlsToInspect.take(6)
                val scriptResults = coroutineScope {
                    batch.map { scriptUrl ->
                        async {
                            val scriptHost = extractHostFromUrl(scriptUrl).lowercase()
                            try {
                                withSafeTimeoutOrNull(3_000L) {
                                    val sResp = httpClient.get(scriptUrl) {
                                        header("Accept", "application/javascript,*/*;q=0.8")
                                        header("User-Agent", SapisidHashGenerator.MOBILE_REMOTE_USER_AGENT)
                                        header("Referer", "${relayOrigin.trimEnd('/')}/")
                                        if (scriptHost == originHost && cleanedCookie != null) {
                                            header("Cookie", cleanedCookie)
                                        }
                                    }
                                    if (sResp.status.value in 200..299) {
                                        SapisidHashGenerator.extractAllWebApiKeys(sResp.bodyAsText())
                                    } else {
                                        emptyList()
                                    }
                                }.orEmpty()
                            } catch (e: CancellationException) {
                                throw e
                            } catch (_: Throwable) {
                                emptyList()
                            }
                        }
                    }.awaitAll()
                }
                for (keys in scriptResults) {
                    collectedKeys.addAll(keys)
                    if (collectedKeys.size >= 6) break
                }
            }
        }
        val result = collectedKeys.toList()
        if (result.isNotEmpty() && handshakeKeySource == "none") {
            handshakeKeySource = "discovered(n=${result.size},len=${result.first().length})"
        }
        recordHandshakeTrace("discoverKey:n=${result.size}")
        return result
    }

    private fun unwrapErrorBodyText(rawBytes: ByteArray, responseHeaders: Map<String, String>): String {
        val unwrapped = runCatching {
            CloudRelayJspbCodec.unwrapGoogleRpcBody(rawBytes, responseHeaders)
        }.getOrDefault(rawBytes)
        return runCatching { unwrapped.decodeToString() }
            .getOrElse { runCatching { rawBytes.decodeToString() }.getOrDefault("") }
            .trim()
    }

    private fun buildUnauthorizedDiagnostic(
        operation: String,
        statusCode: Int,
        responseHeaders: Map<String, String>,
        rawBytes: ByteArray,
        apiKey: String?,
        authUser: String,
    ): String {
        val decoded = unwrapErrorBodyText(rawBytes, responseHeaders)
            .replace("\r", " ")
            .replace("\n", " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        val snippet = if (decoded.length > 160) decoded.take(160) + "…" else decoded
        val keyState = if (apiKey.isNullOrEmpty()) "none" else "len:${apiKey.length}"
        val ckState = SapisidHashGenerator.summarizeCookieNames(sessionCookie.orEmpty())
        val base = "HTTP $statusCode [$operation u=$authUser key=$keyState ck=$ckState]"
        return if (snippet.isEmpty()) base else "$base: $snippet"
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

    @Throws(Throwable::class)
    public suspend fun listRelayInstances(
        authUserOverride: String? = null,
        timeoutMs: Long = 7_000L,
    ): List<RelayInstanceInfo> {
        val activeAuthUser = authUserOverride ?: stateMutex.withLock { currentAuthUser }
        val url = "$relayOrigin${SapisidHashGenerator.API_SERVICE_PREFIX}/ListInstances"
        val listStartMs = currentTimeMillis()

        suspend fun perform(apiKey: String?, attemptTimeoutMs: Long = timeoutMs): Pair<HttpResponse, ByteArray> {
            val headers = SapisidHashGenerator.buildApiServiceHeaders(
                cookieHeader = sessionCookie.orEmpty(),
                origin = relayOrigin,
                authUser = activeAuthUser,
                apiKey = apiKey,
                timestampSeconds = currentTimeMillis() / 1000L,
            )
            return withSafeTimeoutOrNull(attemptTimeoutMs) {
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
                response to response.bodyAsBytes()
            } ?: run {
                recordHandshakeTrace("list(u=$activeAuthUser):timeout(${attemptTimeoutMs}ms)")
                throw AntigravityRpcError.HttpError(
                    504,
                    "ListInstances timed out after ${attemptTimeoutMs}ms (u=$activeAuthUser) [${currentHandshakeDiagnostic()}]",
                )
            }
        }

        var activeApiKey = ensureRelayWebApiKey()
        val triedKeys = mutableSetOf<String>()
        triedKeys.add(activeApiKey.orEmpty())

        recordHandshakeTrace("list(u=$activeAuthUser):req")
        var (response, rawBytes) = try {
            perform(activeApiKey)
        } catch (e: CancellationException) {
            throw e
        } catch (e: AntigravityRpcError) {
            throw e
        } catch (e: Throwable) {
            recordHandshakeTrace("list(u=$activeAuthUser):err(${e::class.simpleName})")
            throw e
        }
        var statusCode = response.status.value
        var respHeaders = response.flattenHeaders()
        recordHandshakeTrace("list(u=$activeAuthUser):http$statusCode")

        if (statusCode == 400 || statusCode == 403) {
            val unwrappedText = unwrapErrorBodyText(rawBytes, respHeaders)
            val isExplicitKeyError = SapisidHashGenerator.isInvalidApiKeyError(statusCode, unwrappedText)
            if (isExplicitKeyError && !activeApiKey.isNullOrEmpty()) {
                stateMutex.withLock { rejectedRelayApiKeys.add(activeApiKey!!) }
            }
            val shouldRotateApiKey = activeApiKey.isNullOrEmpty() || isExplicitKeyError || statusCode == 403
            if (shouldRotateApiKey) {
                val candidates = discoverCandidateRelayApiKeys(forceRefresh = false)
                val knownRejected = stateMutex.withLock { rejectedRelayApiKeys.toSet() }
                var rotationAttempts = 0
                for (candidateKey in candidates) {
                    if (rotationAttempts >= 2) break
                    if (currentTimeMillis() - listStartMs >= 11_000L) break
                    if (candidateKey.isBlank() || candidateKey in knownRejected || !triedKeys.add(candidateKey)) continue
                    rotationAttempts += 1
                    recordHandshakeTrace("list(u=$activeAuthUser):rot$rotationAttempts")
                    val retry = perform(candidateKey, attemptTimeoutMs = 3_500L)
                    response = retry.first
                    rawBytes = retry.second
                    statusCode = response.status.value
                    respHeaders = response.flattenHeaders()
                    activeApiKey = candidateKey
                    recordHandshakeTrace("list(u=$activeAuthUser):rot${rotationAttempts}_http$statusCode")
                    if (statusCode in 200..299) {
                        stateMutex.withLock { currentRelayApiKey = candidateKey }
                        handshakeKeySource = "rotated(len=${candidateKey.length})"
                        break
                    }
                    if ((statusCode == 400 || statusCode == 403) &&
                        SapisidHashGenerator.isInvalidApiKeyError(statusCode, unwrapErrorBodyText(rawBytes, respHeaders))
                    ) {
                        stateMutex.withLock { rejectedRelayApiKeys.add(candidateKey) }
                    }
                    if (statusCode != 400 && statusCode != 403) {
                        break
                    }
                }
            }
        }

        if (statusCode == 401 || statusCode == 403) {
            throw AntigravityRpcError.Unauthorized(
                buildUnauthorizedDiagnostic(
                    operation = "ListInstances",
                    statusCode = statusCode,
                    responseHeaders = respHeaders,
                    rawBytes = rawBytes,
                    apiKey = activeApiKey,
                    authUser = activeAuthUser,
                )
            )
        }
        if (statusCode !in 200..299) {
            throw AntigravityRpcError.HttpError(statusCode, unwrapErrorBodyText(rawBytes, respHeaders))
        }
        if (!activeApiKey.isNullOrEmpty()) {
            stateMutex.withLock { currentRelayApiKey = activeApiKey }
        }
        return CloudRelayJspbCodec.decodeListInstancesResponse(rawBytes, respHeaders)
    }

    @Throws(Throwable::class)
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
        var anySucceededCall = false
        var primaryError: Throwable? = null
        var lastError: Throwable? = null

        suspend fun evaluateCandidateResult(
            candidateUser: String,
            instances: List<RelayInstanceInfo>,
        ): RelayResolutionResult? {
            anySucceededCall = true
            if (instances.isEmpty()) return null
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
            } else {
                instances.firstOrNull { it.status.isReachable }?.let { online ->
                    updateRelayCache(candidateUser, online.uuid, instances)
                    return RelayResolutionResult(online, instances, candidateUser)
                }
            }
            return null
        }

        // 1. Probe primary authUser first (fastest single-RTT happy path + primes API key discovery once).
        val primaryUser = candidateAuthUsers.first()
        var stopFallbacks = false
        try {
            val primaryInstances = listRelayInstances(authUserOverride = primaryUser, timeoutMs = 7_000L)
            evaluateCandidateResult(primaryUser, primaryInstances)?.let {
                recordHandshakeTrace("resolve:ok(u=$primaryUser,n=${primaryInstances.size})")
                return it
            }
            if (!isWildcard && primaryInstances.any { it.matches(rawTarget) }) {
                stopFallbacks = true
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            primaryError = e
            lastError = e
            // Fail fast on network/timeout errors: probing authUser=1..4 cannot fix an unreachable relay/VPN.
            val isTransportOrTimeout = (e is AntigravityRpcError.HttpError && (e.statusCode == 504 || e.statusCode == -1)) ||
                (e !is AntigravityRpcError)
            if (isTransportOrTimeout) {
                recordHandshakeTrace("resolve:failFast(u=$primaryUser)")
                stopFallbacks = true
            }
        }

        // 2. If primary authUser did not return a reachable match, probe remaining multi-login slots IN PARALLEL
        // with a tight 4.5s budget instead of 4 sequential retries.
        val fallbackUsers = if (stopFallbacks) emptyList() else candidateAuthUsers.drop(1)
        if (fallbackUsers.isNotEmpty()) {
            recordHandshakeTrace("resolve:fallback(${fallbackUsers.joinToString(",")})")
            val parallelOutcomes = coroutineScope {
                fallbackUsers.map { candidateUser ->
                    async {
                        try {
                            val list = withSafeTimeoutOrNull(4_500L) {
                                listRelayInstances(authUserOverride = candidateUser, timeoutMs = 4_000L)
                            }
                            candidateUser to (if (list != null) Result.success(list) else null)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Throwable) {
                            candidateUser to Result.failure<List<RelayInstanceInfo>>(e)
                        }
                    }
                }.awaitAll()
            }
            for ((candidateUser, outcome) in parallelOutcomes) {
                if (outcome == null) continue
                val instances = outcome.getOrNull()
                if (instances != null) {
                    evaluateCandidateResult(candidateUser, instances)?.let {
                        recordHandshakeTrace("resolve:ok(u=$candidateUser,n=${instances.size})")
                        return it
                    }
                    if (!isWildcard && instances.any { it.matches(rawTarget) }) {
                        break
                    }
                } else {
                    val err = outcome.exceptionOrNull()
                    if (err != null) {
                        if (primaryError == null) primaryError = err
                        lastError = err
                    }
                }
            }
        }

        if (!allowCrossHostFallback && bestOfflineMatch != null) {
            updateRelayCache(bestOfflineMatch.third, bestOfflineMatch.first.uuid, bestOfflineMatch.second)
            recordHandshakeTrace("resolve:offlineMatch(u=${bestOfflineMatch.third})")
            return RelayResolutionResult(bestOfflineMatch.first, bestOfflineMatch.second, bestOfflineMatch.third)
        }
        if (allowCrossHostFallback && bestReachableFallback != null) {
            updateRelayCache(bestReachableFallback.third, bestReachableFallback.first.uuid, bestReachableFallback.second)
            recordHandshakeTrace("resolve:crossHost(u=${bestReachableFallback.third})")
            return RelayResolutionResult(bestReachableFallback.first, bestReachableFallback.second, bestReachableFallback.third)
        }
        if (bestOfflineMatch != null) {
            updateRelayCache(bestOfflineMatch.third, bestOfflineMatch.first.uuid, bestOfflineMatch.second)
            recordHandshakeTrace("resolve:offline(u=${bestOfflineMatch.third})")
            return RelayResolutionResult(bestOfflineMatch.first, bestOfflineMatch.second, bestOfflineMatch.third)
        }
        if (!allowCrossHostFallback && !isWildcard && firstNonEmpty != null) {
            val syntheticOffline = RelayInstanceInfo(uuid = rawTarget, name = rawTarget, status = RelayInstanceStatus.DISCONNECTED)
            updateRelayCache(firstNonEmpty.second, rawTarget, firstNonEmpty.first)
            recordHandshakeTrace("resolve:targetOffline")
            return RelayResolutionResult(syntheticOffline, firstNonEmpty.first, firstNonEmpty.second)
        }
        if (firstNonEmpty != null) {
            val chosen = firstNonEmpty.first.firstOrNull { it.status.isReachable } ?: firstNonEmpty.first.first()
            updateRelayCache(firstNonEmpty.second, chosen.uuid, firstNonEmpty.first)
            recordHandshakeTrace("resolve:firstNonEmpty(u=${firstNonEmpty.second})")
            return RelayResolutionResult(chosen, firstNonEmpty.first, firstNonEmpty.second)
        }
        // Only allow direct-UUID fallback when ListInstances genuinely succeeded (HTTP 200) with empty results.
        // Never swallow Unauthorized (401/403) or network errors into a fake connected UUID host.
        if (anySucceededCall && lastError == null && !isWildcard && (rawTarget.endsWith("-v2") || rawTarget.length >= 32)) {
            val direct = RelayInstanceInfo(uuid = rawTarget, name = rawTarget, status = RelayInstanceStatus.CONNECTED)
            val auth = stateMutex.withLock { currentAuthUser }
            updateRelayCache(auth, rawTarget, listOf(direct))
            recordHandshakeTrace("resolve:directUuid")
            return RelayResolutionResult(direct, listOf(direct), auth)
        }
        if (anySucceededCall && primaryError == null && lastError == null) {
            recordHandshakeTrace("resolve:empty200")
            throw AntigravityRpcError.HttpError(
                404,
                "Signed in to Google, but no online Antigravity Desktop instances were found on this account. Enable Remote Control in Antigravity Desktop and verify both devices use the same Google account.",
            )
        }
        recordHandshakeTrace("resolve:failed")
        throw primaryError ?: lastError ?: AntigravityRpcError.Unauthorized("No reachable Cloud Relay instance resolved")
    }

    private suspend fun updateRelayCache(authUser: String, resolvedUuid: String, instances: List<RelayInstanceInfo>) {
        stateMutex.withLock {
            this.currentAuthUser = authUser
            this.resolvedInstanceUuidState = resolvedUuid
            this.cachedRelayInstances = instances
            recordRelayInstanceVersionsLocked(instances)
        }
    }

    // MARK: - Handshake & Reachability Probe

    @Throws(Throwable::class)
    public suspend fun verifyConnection(allowCrossHostFallback: Boolean = true): BackendHandshakeResult {
        resetHandshakeTrace()
        recordHandshakeTrace("verify:start")
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

        val federated = if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            val resolveElapsedMs = max(0L, currentTimeMillis() - startMs)
            // Keep initial handshake well below the 22s/25s hard timeout: once ListInstances succeeds,
            // give initial federated sync a bounded 2.5s–6.5s soft window; if it's still downloading a large
            // trajectory list over VPN, complete handshake immediately and finish hydrating in background.
            val initialSyncBudgetMs = (17_000L - resolveElapsedMs).coerceIn(2_500L, 6_500L)
            recordHandshakeTrace("sync:start(${initialSyncBudgetMs}ms)")
            val synced = try {
                withSafeTimeoutOrNull(initialSyncBudgetMs) {
                    fetchFederatedWorkspacesAndSummaries(
                        skipRelayListRefresh = allRelayInstances.isNotEmpty(),
                        targetInstanceUuid = if (!allowCrossHostFallback && isSelectedOnline) selectedUuid else null,
                        includeLocal = isSelectedOnline || allowCrossHostFallback,
                        includeCloud = true,
                        includeJetboxSnapshot = false,
                        perCallTimeoutMs = initialSyncBudgetMs,
                    )
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (_: Throwable) {
                null
            }
            if (synced != null) {
                recordHandshakeTrace("sync:ok(sum=${synced.summaries.size},ws=${synced.workspaces.size})")
                synced
            } else {
                recordHandshakeTrace("sync:deferred")
                FederatedWorkspaceSyncResult(
                    workspaces = emptyList(),
                    summaries = emptyList(),
                    availableRelayInstances = allRelayInstances,
                    latencyMs = max(1L, currentTimeMillis() - startMs).toInt(),
                )
            }
        } else {
            fetchFederatedWorkspacesAndSummaries(
                skipRelayListRefresh = false,
                targetInstanceUuid = null,
                includeLocal = true,
                includeCloud = true,
                includeJetboxSnapshot = false,
            )
        }

        val latestInstances = federated.availableRelayInstances.ifEmpty {
            currentCachedRelayInstances().ifEmpty { allRelayInstances }
        }
        val latestActive = currentActiveRelayInstance()
        val elapsedMs = max(1L, currentTimeMillis() - startMs).toInt()
        recordHandshakeTrace("verify:done")
        return BackendHandshakeResult(
            latencyMs = elapsedMs,
            workspaces = federated.workspaces,
            summaries = federated.summaries,
            cloudProjects = federated.cloudProjects,
            serverVersion = latestActive?.version?.takeIf { it.isNotBlank() } ?: serverVersion,
            resolvedHostname = latestActive?.name ?: resolvedName ?: host.hostname,
            resolvedInstanceUuid = selectedUuid ?: currentResolvedInstanceUuid(),
            resolvedAuthUser = if (channel == RemoteConnectionChannel.CLOUD_RELAY) currentAuthUser() else null,
            resolvedRelayApiKey = if (channel == RemoteConnectionChannel.CLOUD_RELAY) currentRelayApiKey() else null,
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
        respectNegativeCache: Boolean = true,
        allowStripUnknownFields: Boolean = true,
        perCallTimeoutMs: Long? = null,
    ): JsonObject {
        // Inverse-allowlist negative cache: fast-fail any non-core RPC previously rejected as
        // unimplemented by this host (including future optional RPCs not yet assigned a HostCapability).
        if (respectNegativeCache && HostCapability.shouldNegativeCacheOnUnimplemented(method)) {
            val cachedProfile = capabilityProfile(hostKey = stateMutex.withLock { hostCapabilityKey(instanceUuidOverride) })
            if (cachedProfile.isMethodKnownUnsupported(method)) {
                throw AntigravityRpcError.HttpError(501, "unimplemented (cached): $method")
            }
        }

        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            return callCloudRelayUnaryJson(
                method = method,
                body = body,
                instanceUuidOverride = instanceUuidOverride,
                allowCrossHostFailover = allowCrossHostFailover,
                allowStripUnknownFields = allowStripUnknownFields,
                perCallTimeoutMs = perCallTimeoutMs,
            )
        }

        val url = "$endpointBaseUrl$SERVICE_PREFIX/$method"
        val currentProfile = capabilityProfile(hostKey = stateMutex.withLock { hostCapabilityKey(instanceUuidOverride) })
        var workingBody = if (allowStripUnknownFields) {
            ProtocolCompatibilityEngine.applyKnownDowngrades(body, method, currentProfile)
        } else {
            body
        }

        for (attempt in 1..4) {
            val bodyBytes = workingBody.toString().encodeToByteArray()
            val response = httpClient.post(url) {
                header("Connect-Protocol-Version", "1")
                csrfToken?.takeIf { it.isNotEmpty() }?.let { header("x-codeium-csrf-token", it) }
                sessionCookie?.takeIf { it.isNotEmpty() }?.let { header("Cookie", it) }
                setBody(ByteArrayContent(bodyBytes, ContentType.Application.Json))
            }
            val rawBytes = response.bodyAsBytes()
            val statusCode = response.status.value
            val respHeaders = response.flattenHeaders()

            // Capture Bridge capability & version headers even on non-2xx responses
            val bridgeCaps = ProtocolCompatibilityEngine.extractBridgeCapabilities(respHeaders)
            val headerVer = ProtocolCompatibilityEngine.extractVersionFromHeadersOrBody(respHeaders, null)
            if (bridgeCaps.isNotEmpty() || headerVer != null) {
                mutateCapabilityProfile(instanceUuidOverride) { p ->
                    var next = p
                    if (bridgeCaps.isNotEmpty()) next = next.recordBridgeCapabilities(bridgeCaps)
                    if (headerVer != null) next = next.updateReportedVersion(headerVer)
                    next
                }
            }

            if (statusCode == 401 || statusCode == 403) {
                throw AntigravityRpcError.Unauthorized("HTTP $statusCode [$method]")
            }
            if (statusCode !in 200..299) {
                val errText = rawBytes.decodeToString()
                if (allowStripUnknownFields && statusCode == 400 && attempt < 4) {
                    val healed = attemptSelfHealingDowngrade(errText, method, workingBody, instanceUuidOverride)
                    if (healed != null) {
                        workingBody = healed
                        continue
                    }
                }
                if (ProtocolCompatibilityEngine.isMethodUnimplementedResponse(statusCode, errText) &&
                    HostCapability.shouldNegativeCacheOnUnimplemented(method)
                ) {
                    mutateCapabilityProfile(instanceUuidOverride) { it.recordMethodUnsupported(method) }
                }
                throw AntigravityRpcError.HttpError(statusCode, errText)
            }
            if (rawBytes.isEmpty()) {
                observeResponseMetadata(respHeaders, null, method, instanceUuidOverride)
                return JsonObject(emptyMap())
            }
            val parsed = runCatching { json.parseToJsonElement(rawBytes.decodeToString()) as? JsonObject }.getOrNull()
                ?: throw AntigravityRpcError.DecodingError("Expected JSON object from $method")
            observeResponseMetadata(respHeaders, parsed, method, instanceUuidOverride)
            return parsed
        }
        return JsonObject(emptyMap())
    }

    private suspend fun callCloudRelayUnaryJson(
        method: String,
        body: JsonObject,
        instanceUuidOverride: String? = null,
        allowCrossHostFailover: Boolean = false,
        allowStripUnknownFields: Boolean = true,
        perCallTimeoutMs: Long? = null,
    ): JsonObject {
        if (method in localDesktopOnlyMethods) {
            mutateCapabilityProfile(instanceUuidOverride) { it.recordMethodUnsupported(method) }
            throw AntigravityRpcError.HttpError(501, "$method is only available on direct local desktop hosts.")
        }
        val isCloudBackend = (body["backend"] as? JsonPrimitive)?.contentOrNull == "BACKEND_TYPE_REMOTE_AICODE" ||
            (body["backendType"] as? JsonPrimitive)?.contentOrNull == "BACKEND_TYPE_REMOTE_AICODE"
        val effectiveFailover = allowCrossHostFailover || isCloudBackend

        val sanitized = sanitizeCloudRelayPayload(method, body)
        val currentProfile = capabilityProfile(hostKey = stateMutex.withLock { hostCapabilityKey(instanceUuidOverride) })
        var workingBody = if (allowStripUnknownFields) {
            ProtocolCompatibilityEngine.applyKnownDowngrades(sanitized, method, currentProfile)
        } else {
            sanitized
        }

        for (attempt in 1..4) {
            val encodedPayload = workingBody.toString().encodeToByteArray()
            val (rawRespBytes, respHeaders) = try {
                callCloudRelayProxyCommand(
                    method = method,
                    payload = encodedPayload,
                    contentType = "application/json",
                    instanceUuidOverride = instanceUuidOverride,
                    allowCrossHostFailover = effectiveFailover,
                    perCallTimeoutMs = perCallTimeoutMs,
                )
            } catch (err: Throwable) {
                if (err is AntigravityRpcError.HttpError &&
                    allowStripUnknownFields &&
                    attempt < 4 &&
                    (err.statusCode == 400 ||
                        ProtocolCompatibilityEngine.extractUnknownProtoFieldName(err.body) != null ||
                        ProtocolCompatibilityEngine.extractInvalidEnumValue(err.body) != null)
                ) {
                    val healed = attemptSelfHealingDowngrade(err.body, method, workingBody, instanceUuidOverride)
                    if (healed != null) {
                        workingBody = healed
                        continue
                    }
                }
                if (ProtocolCompatibilityEngine.isMethodUnimplementedError(err) &&
                    HostCapability.shouldNegativeCacheOnUnimplemented(method)
                ) {
                    mutateCapabilityProfile(instanceUuidOverride) { it.recordMethodUnsupported(method) }
                }
                throw err
            }
            val respData = unwrapConnectFramedPayloadIfNeeded(rawRespBytes)
            if (respData.isEmpty()) {
                observeResponseMetadata(respHeaders, null, method, instanceUuidOverride)
                return JsonObject(emptyMap())
            }

            val respText = respData.decodeToString()
            val decoded = runCatching { json.parseToJsonElement(respText) as? JsonObject }.getOrNull()
            if (decoded != null) {
                val code = (decoded["code"] as? JsonPrimitive)?.contentOrNull
                val message = (decoded["message"] as? JsonPrimitive)?.contentOrNull
                if (code != null && message != null && decoded.size <= 3) {
                    val combinedError = "$code: $message"
                    if (allowStripUnknownFields && attempt < 4) {
                        val healed = attemptSelfHealingDowngrade(combinedError, method, workingBody, instanceUuidOverride)
                        if (healed != null) {
                            workingBody = healed
                            continue
                        }
                    }
                    val statusCode = when {
                        ProtocolCompatibilityEngine.isMethodUnimplementedResponse(400, combinedError) -> 501
                        code.equals("not_found", ignoreCase = true) -> 404
                        else -> 400
                    }
                    if (statusCode == 501 && HostCapability.shouldNegativeCacheOnUnimplemented(method)) {
                        mutateCapabilityProfile(instanceUuidOverride) { it.recordMethodUnsupported(method) }
                    }
                    throw AntigravityRpcError.HttpError(statusCode, combinedError)
                }
                observeResponseMetadata(respHeaders, decoded, method, instanceUuidOverride)
                return decoded
            }
            if (allowStripUnknownFields && attempt < 4) {
                val healed = attemptSelfHealingDowngrade(respText, method, workingBody, instanceUuidOverride)
                if (healed != null) {
                    workingBody = healed
                    continue
                }
            }
            if (ProtocolCompatibilityEngine.isMethodUnimplementedResponse(400, respText)) {
                if (HostCapability.shouldNegativeCacheOnUnimplemented(method)) {
                    mutateCapabilityProfile(instanceUuidOverride) { it.recordMethodUnsupported(method) }
                }
                throw AntigravityRpcError.HttpError(501, respText)
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
        perCallTimeoutMs: Long? = null,
    ): DecodedProxyCommandResponse {
        val needsResolve = stateMutex.withLock { instanceUuidOverride == null && resolvedInstanceUuidState == null }
        if (needsResolve) {
            resolveCloudRelayInstance(allowCrossHostFallback = allowCrossHostFailover)
        } else if (currentCachedRelayInstances().isEmpty()) {
            runCatching { listRelayInstances() }.getOrNull()?.takeIf { it.isNotEmpty() }?.let { refreshed ->
                stateMutex.withLock {
                    cachedRelayInstances = refreshed
                    recordRelayInstanceVersionsLocked(refreshed)
                }
            }
        }

        val initialTargetUuid = selectReachableRelayUuid(instanceUuidOverride, allowCrossHostFailover)
            ?.takeIf { it.isNotEmpty() }
            ?: throw AntigravityRpcError.HttpError(503, "Selected Antigravity Desktop host is offline")

        val url = "$relayOrigin${SapisidHashGenerator.API_SERVICE_PREFIX}/ProxyCommand?\$unique=$method"
        val effectiveTimeoutMs = perCallTimeoutMs ?: 12_000L

        suspend fun sendOnce(targetUuid: String, authUserOverride: String? = null): DecodedProxyCommandResponse {
            val activeAuth = authUserOverride ?: currentAuthUser()

            suspend fun postWithKey(apiKey: String?, timeoutMs: Long = effectiveTimeoutMs): Pair<HttpResponse, ByteArray> {
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
                return withSafeTimeoutOrNull(timeoutMs) {
                    val response = httpClient.post(url) {
                        for ((k, v) in headers) {
                            if (!k.equals("Content-Type", ignoreCase = true)) header(k, v)
                        }
                        setBody(ByteArrayContent(jspbBody, ContentType.parse("application/json+protobuf")))
                    }
                    response to response.bodyAsBytes()
                } ?: throw AntigravityRpcError.HttpError(504, "ProxyCommand/$method timed out")
            }

            var activeApiKey = ensureRelayWebApiKey()
            val triedKeys = mutableSetOf<String>()
            triedKeys.add(activeApiKey.orEmpty())

            var (response, rawBytes) = postWithKey(activeApiKey)
            var code = response.status.value
            var respHeaders = response.flattenHeaders()

            if (code == 400 || code == 403) {
                val unwrappedText = unwrapErrorBodyText(rawBytes, respHeaders)
                val isExplicitKeyError = SapisidHashGenerator.isInvalidApiKeyError(code, unwrappedText)
                if (isExplicitKeyError && !activeApiKey.isNullOrEmpty()) {
                    stateMutex.withLock { rejectedRelayApiKeys.add(activeApiKey!!) }
                }
                val shouldRotate = activeApiKey.isNullOrEmpty() || isExplicitKeyError || code == 403
                if (shouldRotate) {
                    val candidates = discoverCandidateRelayApiKeys(forceRefresh = false)
                    val knownRejected = stateMutex.withLock { rejectedRelayApiKeys.toSet() }
                    var rotationAttempts = 0
                    for (candidateKey in candidates) {
                        if (rotationAttempts >= 2) break
                        if (candidateKey.isBlank() || candidateKey in knownRejected || !triedKeys.add(candidateKey)) continue
                        rotationAttempts += 1
                        val retry = postWithKey(candidateKey, timeoutMs = minOf(effectiveTimeoutMs, 4_000L))
                        response = retry.first
                        rawBytes = retry.second
                        code = response.status.value
                        respHeaders = response.flattenHeaders()
                        activeApiKey = candidateKey
                        if (code in 200..299) {
                            stateMutex.withLock { currentRelayApiKey = candidateKey }
                            break
                        }
                        if ((code == 400 || code == 403) &&
                            SapisidHashGenerator.isInvalidApiKeyError(code, unwrapErrorBodyText(rawBytes, respHeaders))
                        ) {
                            stateMutex.withLock { rejectedRelayApiKeys.add(candidateKey) }
                        }
                        if (code != 400 && code != 403) {
                            break
                        }
                    }
                }
            }

            if (code == 401 || code == 403) {
                throw AntigravityRpcError.Unauthorized(
                    buildUnauthorizedDiagnostic(
                        operation = "ProxyCommand/$method",
                        statusCode = code,
                        responseHeaders = respHeaders,
                        rawBytes = rawBytes,
                        apiKey = activeApiKey,
                        authUser = activeAuth,
                    )
                )
            }
            if (code !in 200..299) throw AntigravityRpcError.HttpError(code, unwrapErrorBodyText(rawBytes, respHeaders))
            return CloudRelayJspbCodec.decodeProxyCommandResponse(rawBytes, respHeaders)
        }

        return try {
            sendOnce(initialTargetUuid)
        } catch (e: AntigravityRpcError.Unauthorized) {
            if (perCallTimeoutMs != null) throw e
            val prevAuth = currentAuthUser()
            val resolved = runCatching {
                withSafeTimeoutOrNull(6_000L) {
                    resolveCloudRelayInstance(
                        preferredIdentifier = instanceUuidOverride ?: stateMutex.withLock { targetInstanceIdentifier },
                        allowCrossHostFallback = allowCrossHostFailover,
                    )
                }
            }.getOrNull()
            if (resolved != null && resolved.selected.status.isReachable &&
                (resolved.matchedAuthUser != prevAuth || resolved.selected.uuid != initialTargetUuid)
            ) {
                sendOnce(resolved.selected.uuid, resolved.matchedAuthUser)
            } else {
                throw e
            }
        } catch (e: Throwable) {
            if (perCallTimeoutMs != null) throw e
            val isHttp404 = e is AntigravityRpcError.HttpError && e.statusCode == 404
            val isTrajectoryNotFound = ProtocolCompatibilityEngine.isTrajectoryNotFoundError(e)
            val shouldFailover = !isTrajectoryNotFound && (
                e !is AntigravityRpcError ||
                    (e is AntigravityRpcError.HttpError && e.statusCode in setOf(404, 502, 503, 504))
                )
            if (shouldFailover) {
                val refreshed = runCatching { listRelayInstances() }.getOrNull().orEmpty()
                if (refreshed.isNotEmpty()) {
                    stateMutex.withLock {
                        cachedRelayInstances = refreshed
                        recordRelayInstanceVersionsLocked(refreshed)
                    }
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

    internal fun sanitizeCloudRelayPayload(method: String, body: JsonObject): JsonObject {
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
                val rawMedia = body["media"] as? JsonArray
                if (rawMedia != null && rawMedia.isNotEmpty()) {
                    val cleanMedia = buildJsonArray {
                        for (entry in rawMedia) {
                            val m = entry as? JsonObject ?: continue
                            val inlineData = (m["inlineData"] as? JsonPrimitive)?.contentOrNull
                                ?: (m["inlineBase64Data"] as? JsonPrimitive)?.contentOrNull
                            val mimeType = (m["mimeType"] as? JsonPrimitive)?.contentOrNull
                            val uri = (m["uri"] as? JsonPrimitive)?.contentOrNull
                            if (inlineData.isNullOrEmpty() && uri.isNullOrEmpty()) continue
                            add(buildJsonObject {
                                put("mimeType", mimeType ?: "image/jpeg")
                                if (!inlineData.isNullOrEmpty()) {
                                    put("inlineData", inlineData)
                                }
                                (m["description"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }?.let {
                                    put("description", it)
                                }
                                if (!uri.isNullOrEmpty() && (uri.startsWith("https://") || uri.startsWith("http://"))) {
                                    put("uri", uri)
                                }
                                (m["thumbnail"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }?.let {
                                    put("thumbnail", it)
                                }
                                m["durationSeconds"]?.let { put("durationSeconds", it) }
                            })
                        }
                    }
                    if (cleanMedia.isNotEmpty()) {
                        put("media", cleanMedia)
                    }
                }
                put("metadata", desktopMetadata)
                val cascadeCfg = body["cascadeConfig"] as? JsonObject
                val plannerCfg = cascadeCfg?.get("plannerConfig") as? JsonObject
                if (cascadeCfg != null && plannerCfg != null) {
                    val plannerMap = plannerCfg.toMutableMap()
                    val convObj = plannerMap["conversational"] as? JsonObject
                    if (convObj != null) {
                        val rawMode = (convObj["plannerMode"] as? JsonPrimitive)?.contentOrNull.orEmpty()
                        if (rawMode != "CONVERSATIONAL_PLANNER_MODE_DEFAULT" && rawMode != "CONVERSATIONAL_PLANNER_MODE_READ_ONLY") {
                            plannerMap["conversational"] = JsonObject(
                                convObj.toMutableMap().apply {
                                    put("plannerMode", JsonPrimitive("CONVERSATIONAL_PLANNER_MODE_DEFAULT"))
                                }
                            )
                        }
                    }
                    val modelCfgObj = body["modelConfig"] as? JsonObject
                    if (modelCfgObj != null) {
                        (modelCfgObj["thinkingEffort"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }?.let {
                            plannerMap.putIfAbsentCompat("thinkingEffort", JsonPrimitive(it))
                        }
                        (modelCfgObj["agentPersona"] as? JsonPrimitive)?.contentOrNull
                            ?.takeIf { it.isNotEmpty() && it != "Default" }
                            ?.let { plannerMap.putIfAbsentCompat("agentPersona", JsonPrimitive(it)) }
                        (modelCfgObj["permissionPreset"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }?.let {
                            plannerMap.putIfAbsentCompat("permissionPreset", JsonPrimitive(it))
                        }
                    }
                    val nextCascade = JsonObject(cascadeCfg.toMutableMap().apply {
                        put("plannerConfig", JsonObject(plannerMap))
                    })
                    put("cascadeConfig", nextCascade)
                } else {
                    body["cascadeConfig"]?.let { put("cascadeConfig", it) }
                }
            }
            "HandleCascadeUserInteraction" -> {
                val interaction = body["interaction"] as? JsonObject ?: return body
                val rc = interaction["runCommand"] as? JsonObject
                if (rc != null) {
                    val confirm = (rc["confirm"] as? JsonPrimitive)?.booleanOrNull == true
                    val verified = (rc["faceIdVerified"] as? JsonPrimitive)?.booleanOrNull == true
                    if (confirm && !verified) {
                        throw AntigravityRpcError.Unauthorized("Biometric Face ID verification required")
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

    private fun MutableMap<String, JsonElement>.putIfAbsentCompat(key: String, value: JsonElement) {
        if (!containsKey(key)) put(key, value)
    }

    // MARK: - Workspaces & Conversation Summaries

    public suspend fun getWorkspaceInfos(
        instanceUuidOverride: String? = null,
        originHostName: String? = null,
        perCallTimeoutMs: Long? = null,
    ): List<WorkspaceInfo> {
        val res = callUnaryJson(
            "GetWorkspaceInfos",
            instanceUuidOverride = instanceUuidOverride,
            perCallTimeoutMs = perCallTimeoutMs,
        )
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
        perCallTimeoutMs: Long? = null,
    ): List<CascadeSummary> {
        val res = callUnaryJson(
            "GetAllCascadeTrajectories",
            instanceUuidOverride = instanceUuidOverride,
            perCallTimeoutMs = perCallTimeoutMs,
        )
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

    @Throws(Throwable::class)
    public suspend fun fetchFederatedWorkspacesAndSummaries(
        skipRelayListRefresh: Boolean = false,
        targetInstanceUuid: String? = null,
        includeLocal: Boolean = true,
        includeCloud: Boolean = true,
        includeJetboxSnapshot: Boolean = true,
        perCallTimeoutMs: Long? = null,
    ): FederatedWorkspaceSyncResult {
        val startMs = currentTimeMillis()
        if (channel == RemoteConnectionChannel.DIRECT_HOST) {
            val (workspaces, summaries) = coroutineScope {
                val wsDeferred = async {
                    try {
                        getWorkspaceInfos(originHostName = host.hostname, perCallTimeoutMs = perCallTimeoutMs)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: AntigravityRpcError.Unauthorized) {
                        throw e
                    } catch (_: Throwable) {
                        emptyList()
                    }
                }
                val sumDeferred = async {
                    getAllCascadeTrajectories(originHostName = host.hostname, perCallTimeoutMs = perCallTimeoutMs)
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
            try {
                val refreshed = listRelayInstances()
                if (refreshed.isNotEmpty()) {
                    stateMutex.withLock {
                        cachedRelayInstances = refreshed
                        recordRelayInstanceVersionsLocked(refreshed)
                    }
                }
                refreshed.ifEmpty { currentCachedRelayInstances() }
            } catch (e: CancellationException) {
                throw e
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (_: Throwable) {
                currentCachedRelayInstances()
            }
        } else {
            currentCachedRelayInstances()
        }

        val reachableInstances = relayInstances.filter { it.status.isReachable }
        val targets = when {
            !includeLocal -> emptyList()
            targetInstanceUuid != null -> {
                val matched = reachableInstances.filter { it.uuid == targetInstanceUuid }
                if (matched.isNotEmpty()) {
                    matched
                } else if (relayInstances.isEmpty() && targetInstanceUuid.isNotBlank() && targetInstanceUuid != "unpaired") {
                    listOf(
                        RelayInstanceInfo(
                            uuid = targetInstanceUuid,
                            name = host.hostname.ifBlank { targetInstanceUuid },
                            version = host.version,
                            status = RelayInstanceStatus.CONNECTED,
                        )
                    )
                } else {
                    emptyList()
                }
            }
            else -> reachableInstances
        }

        val mergedWorkspaces = linkedMapOf<String, WorkspaceInfo>()
        val mergedSummaries = linkedMapOf<String, CascadeSummary>()
        val succeededUuids = mutableListOf<String>()
        var firstLocalError: Throwable? = null
        var authError: AntigravityRpcError.Unauthorized? = null

        data class LocalInstanceFetchOutcome(
            val inst: RelayInstanceInfo,
            val wsOk: Boolean,
            val workspaces: List<WorkspaceInfo>,
            val trajResult: Result<List<CascadeSummary>>,
            val jbSummaries: List<CascadeSummary>,
            val wsAuthError: AntigravityRpcError.Unauthorized?,
        )

        val cloudBudgetMs = minOf(5_000L, perCallTimeoutMs ?: 5_000L)
        val (perInstanceResults, cloudProjects, cloudSummaries) = coroutineScope {
            val cloudProjectsDeferred = async {
                if (includeCloud && reachableInstances.isNotEmpty()) {
                    withSafeTimeoutOrNull(cloudBudgetMs) {
                        fetchCloudProjects(reachableInstances)
                    }.orEmpty()
                } else {
                    emptyList()
                }
            }
            val cloudSummariesDeferred = async {
                if (includeCloud && reachableInstances.isNotEmpty()) {
                    withSafeTimeoutOrNull(cloudBudgetMs) {
                        fetchCloudSummariesAcrossInstances(
                            candidates = reachableInstances,
                            includeJetboxSnapshot = includeJetboxSnapshot,
                        )
                    }.orEmpty()
                } else {
                    emptyList()
                }
            }
            val localDeferreds = targets.map { inst ->
                async {
                    val wsDeferred = async {
                        try {
                            Triple(
                                true,
                                getWorkspaceInfos(
                                    instanceUuidOverride = inst.uuid,
                                    originHostName = inst.name,
                                    perCallTimeoutMs = perCallTimeoutMs,
                                ),
                                null as AntigravityRpcError.Unauthorized?,
                            )
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: AntigravityRpcError.Unauthorized) {
                            Triple(false, emptyList(), e)
                        } catch (e: AntigravityRpcError.HttpError) {
                            Triple(e.statusCode == 404, emptyList(), null)
                        } catch (_: Throwable) {
                            Triple(false, emptyList(), null)
                        }
                    }
                    val trajDeferred = async {
                        try {
                            Result.success(
                                getAllCascadeTrajectories(
                                    instanceUuidOverride = inst.uuid,
                                    originHostName = inst.name,
                                    perCallTimeoutMs = perCallTimeoutMs,
                                )
                            )
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Throwable) {
                            Result.failure(e)
                        }
                    }
                    val jbDeferred = async {
                        if (includeJetboxSnapshot) {
                            fetchJetboxSummariesSnapshot(
                                cloud = false,
                                instanceUuidOverride = inst.uuid,
                                originHostName = inst.name,
                                timeoutMs = 2_000L,
                            )
                        } else {
                            emptyList()
                        }
                    }
                    val (wsOk, wsList, wsAuthErr) = wsDeferred.await()
                    val trajRes = trajDeferred.await()
                    val jbList = jbDeferred.await()
                    LocalInstanceFetchOutcome(inst, wsOk, wsList, trajRes, jbList, wsAuthErr)
                }
            }
            Triple(localDeferreds.awaitAll(), cloudProjectsDeferred.await(), cloudSummariesDeferred.await())
        }

        for (outcome in perInstanceResults) {
            if (outcome.wsAuthError != null) {
                authError = outcome.wsAuthError
            }
            val trajErr = outcome.trajResult.exceptionOrNull()
            if (trajErr is AntigravityRpcError.Unauthorized) {
                authError = trajErr
            } else if (trajErr != null && firstLocalError == null) {
                firstLocalError = trajErr
            }

            val trajList = outcome.trajResult.getOrNull()
            val instOk = outcome.wsOk || trajList != null || outcome.jbSummaries.isNotEmpty()
            if (instOk) {
                succeededUuids.add(outcome.inst.uuid)
            }
            for (ws in outcome.workspaces) {
                val wsKey = "${if (ws.isCloud) "cloud" else (ws.originInstanceUuid ?: outcome.inst.uuid)}|${ws.workspaceUri}"
                if (!mergedWorkspaces.containsKey(wsKey)) {
                    mergedWorkspaces[wsKey] = ws
                }
            }
            for (s in (trajList.orEmpty() + outcome.jbSummaries)) {
                mergeSummaryInto(s, mergedSummaries)
            }
        }

        if (includeCloud) {
            for (cp in cloudProjects) {
                val wsKey = "cloud|${cp.workspaceUri}"
                if (!mergedWorkspaces.containsKey(wsKey)) {
                    mergedWorkspaces[wsKey] = WorkspaceInfo(
                        workspaceUri = cp.workspaceUri,
                        displayName = cp.name,
                        activeBranch = cp.activeBranch,
                        isCloud = true,
                        originInstanceUuid = cp.originInstanceUuid,
                        originHostName = "Antigravity",
                    )
                }
            }
            for (s in cloudSummaries) {
                mergeSummaryInto(s, mergedSummaries)
            }
        }

        if (authError != null && succeededUuids.isEmpty() && cloudSummaries.isEmpty() && cloudProjects.isEmpty()) {
            throw authError
        }
        if (targets.isNotEmpty() && succeededUuids.isEmpty() && cloudSummaries.isEmpty() && cloudProjects.isEmpty() && firstLocalError != null) {
            throw firstLocalError
        }

        val sortedSummaries = mergedSummaries.values.sortedWith(
            compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId }
        )
        val elapsedMs = max(1L, currentTimeMillis() - startMs).toInt()
        return FederatedWorkspaceSyncResult(
            workspaces = mergedWorkspaces.values.toList(),
            summaries = sortedSummaries,
            cloudProjects = cloudProjects,
            availableRelayInstances = relayInstances,
            succeededInstanceUuids = succeededUuids,
            cloudSucceeded = includeCloud && (cloudSummaries.isNotEmpty() || cloudProjects.isNotEmpty() || sortedSummaries.any { it.isCloud }),
            latencyMs = elapsedMs,
        )
    }

    private fun mergeSummaryInto(incoming: CascadeSummary, map: MutableMap<String, CascadeSummary>) {
        val existing = map[incoming.cascadeId]
        if (existing == null) {
            map[incoming.cascadeId] = incoming
            return
        }
        val base = if (incoming.stepCount >= existing.stepCount && incoming.updatedAtEpochMs >= existing.updatedAtEpochMs) {
            incoming
        } else {
            existing
        }
        val resolvedTitle = when {
            existing.hasResolvedTitle && !incoming.hasResolvedTitle -> existing.title
            incoming.hasResolvedTitle && !existing.hasResolvedTitle -> incoming.title
            else -> base.title
        }
        val resolvedHasTitle = existing.hasResolvedTitle || incoming.hasResolvedTitle
        map[incoming.cascadeId] = base.copy(
            title = resolvedTitle,
            hasResolvedTitle = resolvedHasTitle,
            stepCount = maxOf(existing.stepCount, incoming.stepCount),
            totalSteps = maxOf(existing.totalSteps, incoming.totalSteps),
            updatedAtEpochMs = maxOf(existing.updatedAtEpochMs, incoming.updatedAtEpochMs),
            isCloud = existing.isCloud || incoming.isCloud,
            cloudProjectId = incoming.cloudProjectId ?: existing.cloudProjectId,
        )
    }

    private suspend fun fetchJetboxSummariesSnapshot(
        cloud: Boolean,
        instanceUuidOverride: String? = null,
        originHostName: String? = null,
        timeoutMs: Long = 2_000L,
    ): List<CascadeSummary> {
        val collected = linkedMapOf<String, CascadeSummary>()
        val body = if (cloud) {
            buildJsonObject { put("backend", "BACKEND_TYPE_REMOTE_AICODE") }
        } else {
            JsonObject(emptyMap())
        }
        val effectiveUuid = instanceUuidOverride ?: currentResolvedInstanceUuid()
        val effectiveHost = if (cloud) "Antigravity" else (originHostName ?: host.hostname)
        try {
            withSafeTimeoutOrNull(timeoutMs) {
                subscribeEnvelopeStream(
                    method = "JetboxSubscribeToSummaries",
                    body = body,
                    instanceUuidOverride = instanceUuidOverride,
                    allowCrossHostFailover = cloud,
                ).collect { jsonObj ->
                    val event = JsonStepAndSummaryDecoder.decodeJetboxSummariesEvent(
                        obj = jsonObj,
                        forceCloud = cloud,
                        originInstanceUuid = effectiveUuid,
                        originHostName = effectiveHost,
                    )
                    for (s in event.summaries) {
                        mergeSummaryInto(s, collected)
                    }
                    if (collected.isNotEmpty()) {
                        throw SnapshotCompleteSignal()
                    }
                }
            }
        } catch (_: SnapshotCompleteSignal) {
            // Snapshot received cleanly; close stream immediately.
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            // Best-effort snapshot fallback; primary GetAllCascadeTrajectories handles hard errors.
        }
        return collected.values.toList()
    }

    private class SnapshotCompleteSignal : Exception()

    private suspend fun getAllCascadeTrajectoriesCloud(instanceUuidOverride: String?): List<CascadeSummary> {
        val candidatePayloads = listOf(
            buildJsonObject { put("backend", "BACKEND_TYPE_REMOTE_AICODE") },
            buildJsonObject { put("backendType", "BACKEND_TYPE_REMOTE_AICODE") },
        )
        var res: JsonObject? = null
        for ((idx, payload) in candidatePayloads.withIndex()) {
            try {
                res = callUnaryJson(
                    method = "GetAllCascadeTrajectories",
                    body = payload,
                    instanceUuidOverride = instanceUuidOverride,
                    allowCrossHostFailover = true,
                    allowStripUnknownFields = false,
                )
                break
            } catch (e: CancellationException) {
                throw e
            } catch (e: AntigravityRpcError.HttpError) {
                val unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(e.body)
                if (idx == 0 && (unknownField.equals("backend", ignoreCase = true) || e.statusCode == 400)) {
                    continue
                }
                return emptyList()
            } catch (_: Throwable) {
                return emptyList()
            }
        }
        val responseObj = res ?: return emptyList()
        val nowMs = currentTimeMillis()
        val summaryMap = responseObj["trajectorySummaries"] as? JsonObject
        if (summaryMap != null) {
            return summaryMap.entries.mapNotNull { (cid, value) ->
                JsonStepAndSummaryDecoder.decodeTrajectorySummaryEntry(
                    cascadeId = cid,
                    value = value,
                    nowEpochMs = nowMs,
                    forceCloud = true,
                    originInstanceUuid = instanceUuidOverride,
                    originHostName = "Antigravity",
                )
            }
        }
        val list = responseObj["trajectories"] as? JsonArray ?: return emptyList()
        return list.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val cid = (obj["cascadeId"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
            JsonStepAndSummaryDecoder.decodeTrajectorySummaryEntry(
                cascadeId = cid,
                value = obj,
                nowEpochMs = nowMs,
                forceCloud = true,
                originInstanceUuid = instanceUuidOverride,
                originHostName = "Antigravity",
            )
        }
    }

    private suspend fun fetchCloudSummariesAcrossInstances(
        candidates: List<RelayInstanceInfo>,
        includeJetboxSnapshot: Boolean = true,
    ): List<CascadeSummary> {
        for (inst in candidates) {
            val (unaryCloud, jbCloud) = coroutineScope {
                val u = async { getAllCascadeTrajectoriesCloud(inst.uuid) }
                val j = async {
                    if (includeJetboxSnapshot) {
                        fetchJetboxSummariesSnapshot(
                            cloud = true,
                            instanceUuidOverride = inst.uuid,
                            originHostName = "Antigravity",
                            timeoutMs = 2_000L,
                        )
                    } else {
                        emptyList()
                    }
                }
                u.await() to j.await()
            }
            val combined = linkedMapOf<String, CascadeSummary>()
            for (s in unaryCloud + jbCloud) {
                mergeSummaryInto(s, combined)
            }
            if (combined.isNotEmpty()) {
                return combined.values.toList()
            }
        }
        return emptyList()
    }

    // MARK: - Trajectory Steps (Binary-First + Adaptive JSON Ceiling)

    private fun isRemoteCloudCascade(cascadeId: String, isCloud: Boolean): Boolean =
        isCloud || AntigravityCloudDetector.isCloudWorkspaceUri("", cascadeId = cascadeId)

    private suspend fun orderedCloudBackendFields(
        method: String,
        targetUuid: String?,
    ): List<CloudTrajectoryBackendField> {
        val (preferred, stripped) = stateMutex.withLock {
            val hostKey = hostCapabilityKey(targetUuid)
            val pref = preferredCloudBackendFieldByHostAndMethod["$hostKey|$method"]
            val strippedFields = capabilityProfilesByHost[hostKey]?.strippedFieldsByMethod?.get(method).orEmpty()
            pref to strippedFields
        }
        val base = listOf(
            CloudTrajectoryBackendField.BACKEND,
            CloudTrajectoryBackendField.BACKEND_TYPE,
            CloudTrajectoryBackendField.NONE,
        )
        val ordered = if (preferred != null) {
            listOf(preferred) + base.filter { it != preferred }
        } else {
            base
        }
        val filtered = ordered.filter { field -> field.jsonKey == null || field.jsonKey !in stripped }
        return filtered.ifEmpty { listOf(CloudTrajectoryBackendField.NONE) }
    }

    private suspend fun recordPreferredCloudBackendField(
        method: String,
        targetUuid: String?,
        field: CloudTrajectoryBackendField,
    ) {
        stateMutex.withLock {
            val hostKey = hostCapabilityKey(targetUuid)
            preferredCloudBackendFieldByHostAndMethod["$hostKey|$method"] = field
        }
    }

    private fun buildTrajectoryRequestBody(
        cascadeId: String,
        cloudField: CloudTrajectoryBackendField?,
        stepOffset: Int = 0,
    ): JsonObject = buildJsonObject {
        put("cascadeId", cascadeId)
        if (stepOffset > 0) put("stepOffset", stepOffset)
        cloudField?.jsonKey?.let { put(it, "BACKEND_TYPE_REMOTE_AICODE") }
    }

    public suspend fun loadTrajectory(
        cascadeId: String,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ) {
        val isRemoteCloud = isRemoteCloudCascade(cascadeId, isCloud)
        if (!isRemoteCloud) {
            callUnaryJson(
                method = "LoadTrajectory",
                body = buildJsonObject { put("cascadeId", cascadeId) },
                instanceUuidOverride = instanceUuidOverride,
                allowCrossHostFailover = false,
            )
            return
        }
        val candidates = orderedCloudBackendFields("LoadTrajectory", instanceUuidOverride)
        var lastError: Throwable? = null
        for (variant in candidates) {
            try {
                callUnaryJson(
                    method = "LoadTrajectory",
                    body = buildTrajectoryRequestBody(cascadeId, variant),
                    instanceUuidOverride = instanceUuidOverride,
                    allowCrossHostFailover = true,
                    allowStripUnknownFields = false,
                )
                recordPreferredCloudBackendField("LoadTrajectory", instanceUuidOverride, variant)
                return
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: CancellationException) {
                throw e
            } catch (e: AntigravityRpcError.HttpError) {
                lastError = e
                val unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(e.body)
                if (unknownField != null) {
                    mutateCapabilityProfile(instanceUuidOverride) { p ->
                        p.recordStrippedField(unknownField, forMethod = "LoadTrajectory")
                    }
                }
                val retryNextVariant = e.statusCode == 400 ||
                    unknownField != null ||
                    ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(e.statusCode, e.body)
                if (!retryNextVariant) throw e
            } catch (e: Throwable) {
                lastError = e
                throw e
            }
        }
        lastError?.let { throw it }
    }

    public suspend fun fetchTrajectoryStepsJson(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = 0,
        instanceUuidOverride: String? = null,
    ): List<CascadeStep> {
        val isRemoteCloud = isRemoteCloudCascade(cascadeId, isCloud = false)
        val cloudField = if (isRemoteCloud) {
            orderedCloudBackendFields("GetCascadeTrajectorySteps", instanceUuidOverride).first()
        } else {
            null
        }
        val body = buildTrajectoryRequestBody(cascadeId, cloudField, stepOffset = startIndex)
        val res = try {
            callUnaryJson(
                method = "GetCascadeTrajectorySteps",
                body = body,
                instanceUuidOverride = instanceUuidOverride,
                allowCrossHostFailover = isRemoteCloud,
            )
        } catch (e: AntigravityRpcError.Unauthorized) {
            throw e
        } catch (e: Throwable) {
            if (isJsonPayloadLimitError(e) && !isBinaryProtobufStepsUnsupported(instanceUuidOverride)) {
                val protoSteps = fetchTrajectoryStepsProtobuf(
                    cascadeId = cascadeId,
                    startIndex = startIndex,
                    endIndex = endIndex,
                    instanceUuidOverride = instanceUuidOverride,
                    allowCrossHostFailover = isRemoteCloud,
                )
                if (protoSteps.isNotEmpty()) {
                    val observed = if (endIndex > 0) minOf(endIndex, protoSteps.size) else protoSteps.size
                    recordLearnedJsonStepCeiling(observed, instanceUuidOverride)
                }
                return protoSteps
            }
            throw e
        }

        val rawSteps = res["steps"] as? JsonArray
        val ceiling = extractJsonTruncationCeiling(
            response = res,
            fallbackStepCount = max(rawSteps?.size ?: 0, endIndex),
        )
        if (ceiling != null) {
            recordLearnedJsonStepCeiling(ceiling, instanceUuidOverride)
            if (!isBinaryProtobufStepsUnsupported(instanceUuidOverride)) {
                return fetchTrajectoryStepsProtobuf(
                    cascadeId = cascadeId,
                    startIndex = startIndex,
                    endIndex = max(endIndex, ceiling),
                    instanceUuidOverride = instanceUuidOverride,
                    allowCrossHostFailover = isRemoteCloud,
                )
            }
        }
        val stepsArray = rawSteps ?: return emptyList()
        return stepsArray.mapIndexedNotNull { idx, item ->
            JsonStepAndSummaryDecoder.decodeJsonStep(item, cascadeId, startIndex + idx)
        }
    }

    public suspend fun fetchTrajectoryStepsProtobuf(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = 0,
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
            val decoded = ProtobufStepCodec.decodeStepsResponse(unwrapped, cascadeId, startingIndex = startIndex)
            return repairUnrecognizedWireStepsIfNeeded(
                steps = decoded,
                cascadeId = cascadeId,
                instanceUuidOverride = instanceUuidOverride,
                allowCrossHostFailover = allowCrossHostFailover,
            )
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
        if (code == 401 || code == 403) throw AntigravityRpcError.Unauthorized("HTTP $code [GetCascadeTrajectorySteps]")
        if (code !in 200..299) {
            val bodyText = runCatching { data.decodeToString() }.getOrDefault("")
            throw AntigravityRpcError.HttpError(code, bodyText.ifBlank { "Binary step fetch failed" })
        }
        val unwrapped = unwrapConnectFramedPayloadIfNeeded(data)
        val decoded = ProtobufStepCodec.decodeStepsResponse(unwrapped, cascadeId, startingIndex = startIndex)
        return repairUnrecognizedWireStepsIfNeeded(
            steps = decoded,
            cascadeId = cascadeId,
            instanceUuidOverride = instanceUuidOverride,
            allowCrossHostFailover = allowCrossHostFailover,
        )
    }

    internal suspend fun repairUnrecognizedWireStepsIfNeeded(
        steps: List<CascadeStep>,
        cascadeId: String,
        instanceUuidOverride: String? = null,
        allowCrossHostFailover: Boolean = false,
    ): List<CascadeStep> {
        val targetIndices = steps.indices.filter { idx ->
            val step = steps[idx]
            val needsInteractionRepair =
                (step.status == CortexStepStatus.WAITING || step.status == CortexStepStatus.BLOCKED) &&
                    step.requestedInteraction?.isUnrecognizedWireMember == true
            val needsStepTypeRepair =
                step.type == CortexStepType.UNSPECIFIED && !step.rawTypeName.isNullOrBlank()
            needsInteractionRepair || needsStepTypeRepair
        }
        if (targetIndices.isEmpty()) return steps

        val repaired = steps.toMutableList()
        for (idx in targetIndices.take(4)) {
            val current = repaired[idx]
            val stepIndex = current.stepIndex
            val reqBody = buildJsonObject {
                put("cascadeId", cascadeId)
                put("stepOffset", stepIndex)
                if (cascadeId.startsWith("v1/")) {
                    put("backend", "BACKEND_TYPE_REMOTE_AICODE")
                }
            }
            val jsonResp = runCatching {
                callUnaryJson(
                    method = "GetCascadeTrajectorySteps",
                    body = reqBody,
                    instanceUuidOverride = instanceUuidOverride,
                    allowCrossHostFailover = allowCrossHostFailover,
                )
            }.getOrNull() ?: continue

            val rawSteps = jsonResp["steps"] as? JsonArray ?: continue
            if (rawSteps.isEmpty()) continue

            val decodedSlice = rawSteps.mapIndexedNotNull { offset, item ->
                JsonStepAndSummaryDecoder.decodeJsonStep(item, cascadeId, stepIndex + offset)
            }
            val matched = decodedSlice.firstOrNull { it.stepIndex == stepIndex } ?: continue

            var updated = current
            if (current.type == CortexStepType.UNSPECIFIED && !current.rawTypeName.isNullOrBlank()) {
                if (matched.type != CortexStepType.UNSPECIFIED ||
                    matched.plannerResponse != null ||
                    matched.requestedInteraction != null ||
                    !matched.fallbackSummary.isNullOrBlank() ||
                    (!matched.rawTypeName.isNullOrBlank() && matched.rawTypeName != current.rawTypeName)
                ) {
                    updated = if (matched.fallbackSummary.isNullOrBlank() && !current.fallbackSummary.isNullOrBlank()) {
                        matched.copy(fallbackSummary = current.fallbackSummary)
                    } else {
                        matched
                    }
                }
            }

            val recoveredInteraction = matched.requestedInteraction
            if (recoveredInteraction != null &&
                !recoveredInteraction.isUnrecognizedWireMember &&
                !recoveredInteraction.rawMemberKey.isNullOrEmpty()
            ) {
                val mergedInteraction = if (recoveredInteraction.rawSummary.isNullOrBlank() &&
                    !current.requestedInteraction?.rawSummary.isNullOrBlank()
                ) {
                    recoveredInteraction.copy(rawSummary = current.requestedInteraction?.rawSummary)
                } else {
                    recoveredInteraction
                }
                updated = updated.copy(requestedInteraction = mergedInteraction)
            }
            repaired[idx] = updated
        }
        return repaired
    }

    public suspend fun fetchAllTrajectorySteps(
        cascadeId: String,
        knownStepCount: Int = 0,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ): List<CascadeStep> {
        val isRemoteCloud = isRemoteCloudCascade(cascadeId, isCloud)
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
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                primaryError = e
            }
        } else {
            primaryError = AntigravityRpcError.HttpError(503, "Selected Antigravity Desktop host is offline")
        }

        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            val probedUuids = mutableSetOf<String>()
            primaryTarget?.let { probedUuids.add(it) }

            suspend fun probePeers(instances: List<RelayInstanceInfo>): List<CascadeStep>? {
                val seedUuid = primaryTarget ?: instanceUuidOverride ?: currentResolvedInstanceUuid()
                val familySeed = instances.firstOrNull { it.uuid == seedUuid }?.name.orEmpty()
                val peers = instances.filter { inst ->
                    inst.status.isReachable && inst.uuid !in probedUuids &&
                        (isRemoteCloud || (familySeed.isNotEmpty() && inst.sameHostFamily(familySeed)))
                }
                for (peer in peers) {
                    probedUuids.add(peer.uuid)
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
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Throwable) {
                        if (primaryError == null || primaryTarget == null) primaryError = e
                    }
                }
                return null
            }

            val cachedInstances = currentCachedRelayInstances()
            if (cachedInstances.isNotEmpty()) {
                probePeers(cachedInstances)?.let { return it }
            }

            val shouldRefreshInstances = cachedInstances.isEmpty() ||
                (primaryError is AntigravityRpcError.HttpError &&
                    (primaryError as AntigravityRpcError.HttpError).statusCode in setOf(404, 502, 503, 504))
            if (shouldRefreshInstances) {
                val refreshed = runCatching {
                    withSafeTimeoutOrNull(4_000L) { listRelayInstances(timeoutMs = 3_500L) }
                }.getOrNull().orEmpty()
                if (refreshed.isNotEmpty()) {
                    stateMutex.withLock {
                        cachedRelayInstances = refreshed
                        recordRelayInstanceVersionsLocked(refreshed)
                    }
                    probePeers(refreshed)?.let { return it }
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
        var lastError: Throwable? = null

        // Path 0 (Antigravity 2.x Cloud Primary): Remote Cloud (`v1/...`) conversations live on
        // Google's remote backend rather than local `.pb` files, so `GetCascadeTrajectorySteps` /
        // `LoadTrajectory` / `GetCascadeTrajectory` often return `not_found: trajectory not found`
        // even for actively running Cloud chats. `StreamAgentStateUpdates` is the authoritative
        // Antigravity 2.x streaming RPC that delivers live & historical Cloud trajectories.
        if (isRemoteCloud) {
            try {
                val streamedSteps = fetchStepsViaAgentStateStream(
                    cascadeId = cascadeId,
                    isRemoteCloud = true,
                    targetUuid = targetUuid,
                    timeoutMs = 5_000L,
                )
                if (!streamedSteps.isNullOrEmpty()) {
                    stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                    return streamedSteps
                }
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (!ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                    lastError = e
                }
            }
        }

        // Path 1 (Local PC Default): Binary Protobuf (`application/proto`) first.
        // Saves ~65% mobile bandwidth, avoids server-side JSON truncation dynamically,
        // wakes dormant disk sessions on empty OR 404 `not_found`, and repairs unknown wire types via JSON.
        if (!isRemoteCloud && !isBinaryProtobufStepsUnsupported(targetUuid)) {
            var shouldWakeAndRetryProto = false
            try {
                val protoSteps = fetchTrajectoryStepsProtobuf(
                    cascadeId = cascadeId,
                    startIndex = 0,
                    endIndex = knownStepCount,
                    instanceUuidOverride = targetUuid,
                    allowCrossHostFailover = false,
                )
                if (protoSteps.isNotEmpty()) {
                    stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                    return protoSteps
                }
                val alreadyWoken = stateMutex.withLock { wakeKey in wokenInstanceCascadeKeys }
                shouldWakeAndRetryProto = knownStepCount > 0 || !alreadyWoken
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (isBinaryProtobufUnsupportedError(e)) {
                    recordBinaryProtobufStepsUnsupported(targetUuid)
                } else {
                    lastError = e
                    if (ProtocolCompatibilityEngine.isTrajectoryNotFoundError(e)) {
                        shouldWakeAndRetryProto = true
                    }
                }
            }

            if (shouldWakeAndRetryProto) {
                try {
                    loadTrajectory(cascadeId, isCloud = false, instanceUuidOverride = targetUuid)
                } catch (e: AntigravityRpcError.Unauthorized) {
                    throw e
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    // Best-effort wake; still retry Binary Protobuf and fall through to Path 2 if needed.
                }
                try {
                    val retryProtoSteps = fetchTrajectoryStepsProtobuf(
                        cascadeId = cascadeId,
                        startIndex = 0,
                        endIndex = knownStepCount,
                        instanceUuidOverride = targetUuid,
                        allowCrossHostFailover = false,
                    )
                    if (retryProtoSteps.isNotEmpty()) {
                        stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                        return retryProtoSteps
                    }
                } catch (e: AntigravityRpcError.Unauthorized) {
                    throw e
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    if (isBinaryProtobufUnsupportedError(e)) {
                        recordBinaryProtobufStepsUnsupported(targetUuid)
                    } else {
                        lastError = e
                    }
                }
            }
        }

        // Path 2: Adaptive JSON (`GetCascadeTrajectorySteps` + `LoadTrajectory` + `GetCascadeTrajectory`)
        // for Cloud fallback or local sessions, with zero hardcoded step thresholds and per-host runtime ceiling learning.
        var adaptiveError: Throwable? = null
        val adaptiveSteps = try {
            fetchStepsViaAdaptiveJson(
                cascadeId = cascadeId,
                knownStepCount = knownStepCount,
                isRemoteCloud = isRemoteCloud,
                targetUuid = targetUuid,
                wakeKey = wakeKey,
                initialError = lastError,
            )
        } catch (e: AntigravityRpcError.Unauthorized) {
            throw e
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            adaptiveError = e
            emptyList()
        }

        if (adaptiveSteps.isNotEmpty()) {
            return adaptiveSteps
        }

        // Path 3 (Local Antigravity 2.x Fallback): If local checkpoint RPCs failed (`not_found`)
        // or returned empty on a session that may have live un-checkpointed turns or SQLite-backed
        // state, fall back to `StreamAgentStateUpdates` before surfacing an error.
        if (!isRemoteCloud && (adaptiveError != null || knownStepCount > 0)) {
            try {
                val streamedSteps = fetchStepsViaAgentStateStream(
                    cascadeId = cascadeId,
                    isRemoteCloud = false,
                    targetUuid = targetUuid,
                    timeoutMs = 3_500L,
                )
                if (!streamedSteps.isNullOrEmpty()) {
                    stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                    return streamedSteps
                }
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Preserve original adaptiveError below.
            }
        }

        adaptiveError?.let { throw it }
        return adaptiveSteps
    }

    /**
     * Reads the initial trajectory snapshot from Antigravity 2.x's authoritative
     * `StreamAgentStateUpdates` server-streaming Connect-RPC (`mainTrajectoryUpdate.stepsUpdate`),
     * merging sparse `indices` + `steps` up to `totalLength` and immediately closing the stream.
     * Returns `null` when this host does not implement `StreamAgentStateUpdates` (negative-cached).
     */
    private suspend fun fetchStepsViaAgentStateStream(
        cascadeId: String,
        isRemoteCloud: Boolean,
        targetUuid: String?,
        timeoutMs: Long = 5_000L,
    ): List<CascadeStep>? {
        val profile = stateMutex.withLock {
            getOrCreateProfileLocked(hostCapabilityKey(targetUuid))
        }
        if (profile.isMethodKnownUnsupported("StreamAgentStateUpdates")) {
            return null
        }

        val strippedFields = profile.strippedFieldsByMethod["StreamAgentStateUpdates"].orEmpty()
        val payloadVariants = mutableListOf<JsonObject>()
        // Canonical Antigravity 2.x request (`conversationId` + `subscriberId`)
        payloadVariants.add(
            buildJsonObject {
                put("conversationId", cascadeId)
                put("subscriberId", "pocket-${randomUuidV4()}")
            }
        )
        if (isRemoteCloud && "backend" !in strippedFields) {
            payloadVariants.add(
                buildJsonObject {
                    put("conversationId", cascadeId)
                    put("subscriberId", "pocket-${randomUuidV4()}")
                    put("backend", "BACKEND_TYPE_REMOTE_AICODE")
                }
            )
        }

        var lastError: Throwable? = null
        for (variant in payloadVariants) {
            val stepsByIndex = linkedMapOf<Int, CascadeStep>()
            var reportedTotalLength: Int? = null
            var sawMainTrajectory = false
            try {
                withSafeTimeoutOrNull(timeoutMs) {
                    subscribeEnvelopeStream(
                        method = "StreamAgentStateUpdates",
                        body = variant,
                        instanceUuidOverride = targetUuid,
                        allowCrossHostFailover = isRemoteCloud,
                    ).collect { frameObj ->
                        val decoded = JsonStepAndSummaryDecoder.decodeAgentStateStepsUpdate(
                            obj = frameObj,
                            cascadeId = cascadeId,
                        )
                        if (decoded.hasMainTrajectoryUpdate) {
                            sawMainTrajectory = true
                        }
                        if (decoded.totalLength != null) {
                            reportedTotalLength = decoded.totalLength
                        }
                        for (step in decoded.steps) {
                            stepsByIndex[step.stepIndex] = step
                        }
                        val totalLen = reportedTotalLength
                        if (totalLen != null && totalLen >= 0) {
                            stepsByIndex.keys.removeAll { it >= totalLen }
                        }
                        if (stepsByIndex.isNotEmpty() && (totalLen == null || stepsByIndex.size >= totalLen)) {
                            throw SnapshotCompleteSignal()
                        }
                        if (sawMainTrajectory && totalLen == 0) {
                            throw SnapshotCompleteSignal()
                        }
                    }
                }
                if (stepsByIndex.isNotEmpty() || (sawMainTrajectory && reportedTotalLength == 0)) {
                    mutateCapabilityProfile(targetUuid) { it.recordMethodSupported("StreamAgentStateUpdates") }
                    return stepsByIndex.values.sortedBy { it.stepIndex }
                }
            } catch (_: SnapshotCompleteSignal) {
                mutateCapabilityProfile(targetUuid) { it.recordMethodSupported("StreamAgentStateUpdates") }
                return stepsByIndex.values.sortedBy { it.stepIndex }
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                    mutateCapabilityProfile(targetUuid) { it.recordMethodUnsupported("StreamAgentStateUpdates") }
                    return null
                }
                if (e is AntigravityRpcError.HttpError) {
                    ProtocolCompatibilityEngine.extractUnknownProtoFieldName(e.body)?.let { unknownField ->
                        mutateCapabilityProfile(targetUuid) {
                            it.recordStrippedField(unknownField, forMethod = "StreamAgentStateUpdates")
                        }
                    }
                }
                lastError = e
                val shouldTryNext = e is AntigravityRpcError.HttpError && (
                    e.statusCode == 400 ||
                        ProtocolCompatibilityEngine.extractUnknownProtoFieldName(e.body) != null ||
                        ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(e.statusCode, e.body)
                    )
                if (!shouldTryNext) {
                    break
                }
            }
        }
        lastError?.let { throw it }
        return emptyList()
    }

    private suspend fun fetchStepsViaAdaptiveJson(
        cascadeId: String,
        knownStepCount: Int,
        isRemoteCloud: Boolean,
        targetUuid: String?,
        wakeKey: String,
        initialError: Throwable? = null,
    ): List<CascadeStep> {
        var lastError: Throwable? = initialError
        val learnedCeiling = learnedJsonStepCeiling(targetUuid)

        // Learned fast-path: skip JSON when host previously revealed a ceiling <= knownStepCount
        if (!isBinaryProtobufStepsUnsupported(targetUuid) &&
            learnedCeiling != null &&
            knownStepCount >= learnedCeiling
        ) {
            try {
                val protoSteps = fetchTrajectoryStepsProtobuf(
                    cascadeId = cascadeId,
                    startIndex = 0,
                    endIndex = knownStepCount,
                    instanceUuidOverride = targetUuid,
                    allowCrossHostFailover = isRemoteCloud,
                )
                if (protoSteps.isNotEmpty()) {
                    stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                    return protoSteps
                }
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (isBinaryProtobufUnsupportedError(e)) {
                    recordBinaryProtobufStepsUnsupported(targetUuid)
                } else {
                    lastError = e
                }
            }
        }

        val cloudCandidates: List<CloudTrajectoryBackendField> = if (isRemoteCloud) {
            orderedCloudBackendFields("GetCascadeTrajectorySteps", targetUuid)
        } else {
            emptyList()
        }
        var activeCloudField: CloudTrajectoryBackendField? = cloudCandidates.firstOrNull()
        val reqBody = buildTrajectoryRequestBody(cascadeId, activeCloudField)

        suspend fun tryProtobufOnCeiling(ceiling: Int): List<CascadeStep>? {
            recordLearnedJsonStepCeiling(ceiling, targetUuid)
            if (isBinaryProtobufStepsUnsupported(targetUuid)) return null
            return try {
                val protoSteps = fetchTrajectoryStepsProtobuf(
                    cascadeId = cascadeId,
                    startIndex = 0,
                    endIndex = max(knownStepCount, ceiling),
                    instanceUuidOverride = targetUuid,
                    allowCrossHostFailover = isRemoteCloud,
                )
                if (protoSteps.isNotEmpty()) {
                    stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                    protoSteps
                } else {
                    null
                }
            } catch (pe: AntigravityRpcError.Unauthorized) {
                throw pe
            } catch (pe: CancellationException) {
                throw pe
            } catch (pe: Throwable) {
                if (isBinaryProtobufUnsupportedError(pe)) {
                    recordBinaryProtobufStepsUnsupported(targetUuid)
                } else {
                    lastError = pe
                }
                null
            }
        }

        var firstResp: JsonObject? = null
        try {
            firstResp = callUnaryJson(
                method = "GetCascadeTrajectorySteps",
                body = reqBody,
                instanceUuidOverride = targetUuid,
                allowCrossHostFailover = isRemoteCloud,
                allowStripUnknownFields = !isRemoteCloud,
            )
            lastError = null
        } catch (e: AntigravityRpcError.Unauthorized) {
            throw e
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            lastError = e
            firstResp = null
            if (isRemoteCloud && e is AntigravityRpcError.HttpError) {
                ProtocolCompatibilityEngine.extractUnknownProtoFieldName(e.body)?.let { unknownField ->
                    mutateCapabilityProfile(targetUuid) { it.recordStrippedField(unknownField, forMethod = "GetCascadeTrajectorySteps") }
                }
            }
            if (isJsonPayloadLimitError(e) && !isBinaryProtobufStepsUnsupported(targetUuid)) {
                try {
                    val protoSteps = fetchTrajectoryStepsProtobuf(
                        cascadeId = cascadeId,
                        startIndex = 0,
                        endIndex = knownStepCount,
                        instanceUuidOverride = targetUuid,
                        allowCrossHostFailover = isRemoteCloud,
                    )
                    if (protoSteps.isNotEmpty()) {
                        val observed = if (knownStepCount > 0) minOf(knownStepCount, protoSteps.size) else protoSteps.size
                        recordLearnedJsonStepCeiling(observed, targetUuid)
                        stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                        return protoSteps
                    }
                } catch (pe: AntigravityRpcError.Unauthorized) {
                    throw pe
                } catch (pe: CancellationException) {
                    throw pe
                } catch (pe: Throwable) {
                    if (isBinaryProtobufUnsupportedError(pe)) {
                        recordBinaryProtobufStepsUnsupported(targetUuid)
                    }
                }
            }
        }

        if (firstResp != null) {
            val firstStepCount = (firstResp["steps"] as? JsonArray)?.size ?: knownStepCount
            val ceiling = extractJsonTruncationCeiling(firstResp, fallbackStepCount = firstStepCount)
            if (ceiling != null) {
                tryProtobufOnCeiling(ceiling)?.let { return it }
            }
        }

        var rawSteps = (firstResp?.get("steps") as? JsonArray)?.toList().orEmpty()
        val alreadyWoken = stateMutex.withLock { wakeKey in wokenInstanceCascadeKeys }
        if (rawSteps.isNotEmpty()) {
            stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
            activeCloudField?.let { recordPreferredCloudBackendField("GetCascadeTrajectorySteps", targetUuid, it) }
        } else if (firstResp == null || knownStepCount > 0 || !alreadyWoken) {
            try {
                loadTrajectory(cascadeId, isRemoteCloud, targetUuid)
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Best-effort wake; still retry GetCascadeTrajectorySteps and fallbacks below.
            }
            val retryVariants: List<CloudTrajectoryBackendField?> = if (isRemoteCloud) {
                orderedCloudBackendFields("GetCascadeTrajectorySteps", targetUuid)
            } else {
                listOf(null)
            }
            for (variant in retryVariants) {
                val candidateBody = buildTrajectoryRequestBody(cascadeId, variant)
                try {
                    val retryResp = callUnaryJson(
                        method = "GetCascadeTrajectorySteps",
                        body = candidateBody,
                        instanceUuidOverride = targetUuid,
                        allowCrossHostFailover = isRemoteCloud,
                        allowStripUnknownFields = !isRemoteCloud,
                    )
                    lastError = null
                    val retryCount = (retryResp["steps"] as? JsonArray)?.size ?: knownStepCount
                    val retryCeiling = extractJsonTruncationCeiling(retryResp, fallbackStepCount = retryCount)
                    if (retryCeiling != null) {
                        tryProtobufOnCeiling(retryCeiling)?.let { return it }
                    }
                    val candidateSteps = (retryResp["steps"] as? JsonArray)?.toList().orEmpty()
                    if (candidateSteps.isNotEmpty()) {
                        rawSteps = candidateSteps
                        activeCloudField = variant
                        stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                        variant?.let { recordPreferredCloudBackendField("GetCascadeTrajectorySteps", targetUuid, it) }
                        break
                    } else if (!isRemoteCloud) {
                        break
                    }
                } catch (e: AntigravityRpcError.Unauthorized) {
                    throw e
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    lastError = e
                    if (isRemoteCloud && e is AntigravityRpcError.HttpError) {
                        ProtocolCompatibilityEngine.extractUnknownProtoFieldName(e.body)?.let { unknownField ->
                            mutateCapabilityProfile(targetUuid) {
                                it.recordStrippedField(unknownField, forMethod = "GetCascadeTrajectorySteps")
                            }
                        }
                    }
                    if (isJsonPayloadLimitError(e) && !isBinaryProtobufStepsUnsupported(targetUuid)) {
                        val protoSteps = runCatching {
                            fetchTrajectoryStepsProtobuf(
                                cascadeId = cascadeId,
                                startIndex = 0,
                                endIndex = knownStepCount,
                                instanceUuidOverride = targetUuid,
                                allowCrossHostFailover = isRemoteCloud,
                            )
                        }.getOrNull()
                        if (!protoSteps.isNullOrEmpty()) {
                            val observed = if (knownStepCount > 0) minOf(knownStepCount, protoSteps.size) else protoSteps.size
                            recordLearnedJsonStepCeiling(observed, targetUuid)
                            stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                            return protoSteps
                        }
                    }
                    if (!isRemoteCloud) break
                    val retryNext = e is AntigravityRpcError.HttpError && (
                        e.statusCode == 400 ||
                            ProtocolCompatibilityEngine.extractUnknownProtoFieldName(e.body) != null ||
                            ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(e.statusCode, e.body)
                        )
                    if (!retryNext) break
                }
            }
        }

        // Fallback A: Query `GetCascadeTrajectory` (`{"trajectory": {"steps": [...]}}`) when `GetCascadeTrajectorySteps`
        // returns empty or `not_found` — mirrors Swift fallback & canonical Antigravity 2.0 daemon trajectory retrieval.
        if (rawSteps.isEmpty() && (firstResp == null || lastError != null || knownStepCount > 0 || !alreadyWoken)) {
            val trajVariants: List<CloudTrajectoryBackendField?> = if (isRemoteCloud) {
                orderedCloudBackendFields("GetCascadeTrajectory", targetUuid)
            } else {
                listOf(null)
            }
            for (variant in trajVariants) {
                val trajBody = buildTrajectoryRequestBody(cascadeId, variant)
                try {
                    val trajResp = callUnaryJson(
                        method = "GetCascadeTrajectory",
                        body = trajBody,
                        instanceUuidOverride = targetUuid,
                        allowCrossHostFailover = isRemoteCloud,
                        allowStripUnknownFields = !isRemoteCloud,
                    )
                    val fallbackArr = ((trajResp["trajectory"] as? JsonObject)?.get("steps") as? JsonArray)
                        ?: (trajResp["steps"] as? JsonArray)
                    val candidateSteps = fallbackArr?.toList().orEmpty()
                    if (candidateSteps.isNotEmpty()) {
                        rawSteps = candidateSteps
                        lastError = null
                        activeCloudField = variant
                        stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                        variant?.let { recordPreferredCloudBackendField("GetCascadeTrajectory", targetUuid, it) }
                        break
                    } else if (!isRemoteCloud) {
                        break
                    }
                } catch (e: AntigravityRpcError.Unauthorized) {
                    throw e
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    if (isRemoteCloud && e is AntigravityRpcError.HttpError) {
                        ProtocolCompatibilityEngine.extractUnknownProtoFieldName(e.body)?.let { unknownField ->
                            mutateCapabilityProfile(targetUuid) {
                                it.recordStrippedField(unknownField, forMethod = "GetCascadeTrajectory")
                            }
                        }
                    }
                    if (lastError == null) lastError = e
                    if (!isRemoteCloud) break
                    val retryNext = e is AntigravityRpcError.HttpError && (
                        e.statusCode == 400 ||
                            ProtocolCompatibilityEngine.extractUnknownProtoFieldName(e.body) != null ||
                            ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(e.statusCode, e.body)
                        )
                    if (!retryNext) break
                }
            }
        }

        // Fallback B: Try Binary Protobuf if JSON came back empty/failed on a non-empty session
        if (rawSteps.isEmpty() &&
            (firstResp == null || lastError != null || knownStepCount > 0) &&
            !isBinaryProtobufStepsUnsupported(targetUuid)
        ) {
            val protoFallback = runCatching {
                fetchTrajectoryStepsProtobuf(
                    cascadeId = cascadeId,
                    startIndex = 0,
                    endIndex = knownStepCount,
                    instanceUuidOverride = targetUuid,
                    allowCrossHostFailover = isRemoteCloud,
                )
            }.getOrNull()
            if (!protoFallback.isNullOrEmpty()) {
                val observed = if (knownStepCount > 0) minOf(knownStepCount, protoFallback.size) else protoFallback.size
                recordLearnedJsonStepCeiling(observed, targetUuid)
                stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                return protoFallback
            }
        }

        val finalError = lastError
        if (rawSteps.isEmpty() && finalError != null) throw finalError

        val seen = mutableSetOf<Int>()
        val collected = mutableListOf<CascadeStep>()
        rawSteps.forEachIndexed { idx, el ->
            JsonStepAndSummaryDecoder.decodeJsonStep(el, cascadeId, idx)?.let { step ->
                if (seen.add(step.stepIndex)) collected.add(step)
            }
        }

        // If knownStepCount was omitted (0) and we hit a previously learned JSON ceiling, probe Binary Protobuf
        val postInitialCeiling = learnedJsonStepCeiling(targetUuid)
        if (knownStepCount == 0 &&
            !isBinaryProtobufStepsUnsupported(targetUuid) &&
            postInitialCeiling != null &&
            collected.size >= postInitialCeiling
        ) {
            val protoSteps = runCatching {
                fetchTrajectoryStepsProtobuf(
                    cascadeId = cascadeId,
                    startIndex = 0,
                    endIndex = collected.size,
                    instanceUuidOverride = targetUuid,
                    allowCrossHostFailover = isRemoteCloud,
                )
            }.getOrNull()
            if (protoSteps != null && protoSteps.size > collected.size) {
                stateMutex.withLock { wokenInstanceCascadeKeys.add(wakeKey) }
                return protoSteps
            }
        }

        // Dynamic stepOffset pagination with automatic truncation & stall detection (no hardcoded ceiling)
        var offset = collected.size
        var pagesFetched = 0
        val maxPaginationRounds = 32
        while (offset > 0 && knownStepCount > 0 && collected.size < knownStepCount && pagesFetched < maxPaginationRounds) {
            pagesFetched += 1
            val pageBody = buildTrajectoryRequestBody(cascadeId, activeCloudField, stepOffset = offset)
            val pageResp = try {
                callUnaryJson(
                    method = "GetCascadeTrajectorySteps",
                    body = pageBody,
                    instanceUuidOverride = targetUuid,
                    allowCrossHostFailover = isRemoteCloud,
                )
            } catch (e: AntigravityRpcError.Unauthorized) {
                throw e
            } catch (e: Throwable) {
                if (isJsonPayloadLimitError(e)) {
                    recordLearnedJsonStepCeiling(max(1, collected.size), targetUuid)
                }
                if (!isBinaryProtobufStepsUnsupported(targetUuid)) {
                    val protoSteps = runCatching {
                        fetchTrajectoryStepsProtobuf(
                            cascadeId = cascadeId,
                            startIndex = 0,
                            endIndex = knownStepCount,
                            instanceUuidOverride = targetUuid,
                            allowCrossHostFailover = isRemoteCloud,
                        )
                    }.getOrNull()
                    if (protoSteps != null && protoSteps.size > collected.size) {
                        recordLearnedJsonStepCeiling(max(1, collected.size), targetUuid)
                        return protoSteps
                    }
                }
                break
            }

            val pageCeiling = extractJsonTruncationCeiling(pageResp, fallbackStepCount = collected.size)
            if (pageCeiling != null) {
                recordLearnedJsonStepCeiling(max(collected.size, pageCeiling), targetUuid)
                if (!isBinaryProtobufStepsUnsupported(targetUuid)) {
                    val protoSteps = runCatching {
                        fetchTrajectoryStepsProtobuf(
                            cascadeId = cascadeId,
                            startIndex = 0,
                            endIndex = max(knownStepCount, pageCeiling),
                            instanceUuidOverride = targetUuid,
                            allowCrossHostFailover = isRemoteCloud,
                        )
                    }.getOrNull()
                    if (protoSteps != null && protoSteps.size >= collected.size) {
                        return protoSteps
                    }
                }
                break
            }

            val pageSteps = (pageResp["steps"] as? JsonArray)?.toList().orEmpty()
            var addedNew = false
            pageSteps.forEachIndexed { idxOffset, el ->
                JsonStepAndSummaryDecoder.decodeJsonStep(el, cascadeId, offset + idxOffset)?.let { step ->
                    if (seen.add(step.stepIndex)) {
                        collected.add(step)
                        addedNew = true
                    }
                }
            }
            if (pageSteps.isEmpty() || !addedNew) {
                recordLearnedJsonStepCeiling(max(1, collected.size), targetUuid)
                if (!isBinaryProtobufStepsUnsupported(targetUuid)) {
                    val protoSteps = runCatching {
                        fetchTrajectoryStepsProtobuf(
                            cascadeId = cascadeId,
                            startIndex = 0,
                            endIndex = knownStepCount,
                            instanceUuidOverride = targetUuid,
                            allowCrossHostFailover = isRemoteCloud,
                        )
                    }.getOrNull()
                    if (protoSteps != null && protoSteps.size > collected.size) {
                        return protoSteps
                    }
                }
                break
            }
            offset = max(offset + pageSteps.size, collected.size)
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
        isModelAlias: Boolean = false,
    ) {
        val isRemoteCloud = isCloud || cascadeId.startsWith("v1/")
        val protoModel = JsonStepAndSummaryDecoder.normalizeProtoModelEnum(modelId)
        val effectivePermission = permissionPreset?.takeIf { it != AgentPermissionPreset.INHERIT_GLOBAL }
            ?: AgentPermissionPreset.defaultPreset(isRemote = isRemoteCloud)

        val mediaEntries = mutableListOf<JsonObject>()
        val items = buildJsonArray {
            add(buildJsonObject { put("text", message) })
            for (chip in attachments) {
                val uri = chip.targetUri ?: chip.label
                if (!chip.inlinePayload.isNullOrEmpty()) {
                    mediaEntries.add(buildJsonObject {
                        put("mimeType", chip.mimeType ?: when (chip.kind) {
                            ComposerAttachmentChip.Kind.IMAGE_SCREENSHOT -> "image/jpeg"
                            ComposerAttachmentChip.Kind.PDF_DOCUMENT -> "application/pdf"
                            ComposerAttachmentChip.Kind.AUDIO_CLIP -> "audio/m4a"
                            ComposerAttachmentChip.Kind.VIDEO_CLIP -> "video/mp4"
                            else -> "application/octet-stream"
                        })
                        put("inlineData", chip.inlinePayload)
                        if (chip.label.isNotBlank()) {
                            put("description", chip.label)
                        }
                    })
                    continue
                }
                when (chip.kind) {
                    ComposerAttachmentChip.Kind.IMAGE_SCREENSHOT,
                    ComposerAttachmentChip.Kind.AUDIO_CLIP,
                    ComposerAttachmentChip.Kind.VIDEO_CLIP,
                    ComposerAttachmentChip.Kind.PDF_DOCUMENT -> {
                        add(buildJsonObject {
                            put("item", buildJsonObject {
                                put("file", buildJsonObject {
                                    put("absoluteUri", uri)
                                    put("label", chip.label)
                                })
                            })
                        })
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

        val requestedModelObj = if (isModelAlias) {
            buildJsonObject { put("alias", modelId) }
        } else {
            buildJsonObject { put("model", protoModel) }
        }

        val plannerConfig = buildJsonObject {
            put("conversational", buildJsonObject {
                put("plannerMode", "CONVERSATIONAL_PLANNER_MODE_DEFAULT")
                put("agenticMode", mode == CascadeExecutionMode.PLANNING)
            })
            put("toolConfig", toolConfig)
            put("requestedModel", requestedModelObj)
            put("thinkingEffort", effort.protoWireValue)
            if (agentPersona != "Default" && agentPersona.isNotEmpty()) {
                put("agentPersona", agentPersona)
            }
            put("permissionPreset", effectivePermission.rawValue)
            if (isRemoteCloud && !isModelAlias && protoModel.startsWith("MODEL_")) {
                put("planModel", protoModel)
            }
        }

        val body = buildJsonObject {
            put("cascadeId", cascadeId)
            put("items", items)
            if (mediaEntries.isNotEmpty()) {
                put("media", JsonArray(mediaEntries))
            }
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
        val annotationsBody = buildJsonObject {
            put("cascadeId", cascadeId)
            put("annotations", buildJsonObject { put("pinned", isPinned) })
            put("mergeAnnotations", true)
        }
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            callUnaryJson("UpdateConversationAnnotations", annotationsBody, instanceUuidOverride = instanceUuidOverride)
            return
        }
        try {
            callUnaryJson(
                method = "PinCascade",
                body = buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("isPinned", isPinned)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        } catch (e: Throwable) {
            if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                callUnaryJson("UpdateConversationAnnotations", annotationsBody, instanceUuidOverride = instanceUuidOverride)
            } else {
                throw e
            }
        }
    }

    public suspend fun renameCascade(cascadeId: String, newTitle: String, instanceUuidOverride: String? = null) {
        val annotationsBody = buildJsonObject {
            put("cascadeId", cascadeId)
            put("annotations", buildJsonObject { put("title", newTitle) })
            put("mergeAnnotations", true)
        }
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            callUnaryJson("UpdateConversationAnnotations", annotationsBody, instanceUuidOverride = instanceUuidOverride)
            return
        }
        try {
            callUnaryJson(
                method = "RenameCascade",
                body = buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("title", newTitle)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        } catch (e: Throwable) {
            if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                callUnaryJson("UpdateConversationAnnotations", annotationsBody, instanceUuidOverride = instanceUuidOverride)
            } else {
                throw e
            }
        }
    }

    public suspend fun moveCascadeToWorkspace(
        cascadeId: String,
        workspaceUri: String,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "MoveCascadeToWorkspace",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("workspaceUri", workspaceUri)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun archiveCascade(cascadeId: String, isArchived: Boolean = true, instanceUuidOverride: String? = null) {
        val annotationsBody = buildJsonObject {
            put("cascadeId", cascadeId)
            put("annotations", buildJsonObject { put("archived", isArchived) })
            put("mergeAnnotations", true)
        }
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            callUnaryJson("UpdateConversationAnnotations", annotationsBody, instanceUuidOverride = instanceUuidOverride)
            return
        }
        try {
            callUnaryJson(
                method = "ArchiveCascade",
                body = buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("isArchived", isArchived)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        } catch (e: Throwable) {
            if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                callUnaryJson("UpdateConversationAnnotations", annotationsBody, instanceUuidOverride = instanceUuidOverride)
            } else {
                throw e
            }
        }
    }

    public suspend fun deleteCascade(cascadeId: String, instanceUuidOverride: String? = null) {
        val body = buildJsonObject { put("cascadeId", cascadeId) }
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            callUnaryJson("DeleteCascadeTrajectory", body, instanceUuidOverride = instanceUuidOverride)
            return
        }
        try {
            callUnaryJson("DeleteCascade", body, instanceUuidOverride = instanceUuidOverride)
        } catch (e: Throwable) {
            if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                callUnaryJson("DeleteCascadeTrajectory", body, instanceUuidOverride = instanceUuidOverride)
            } else {
                throw e
            }
        }
    }

    // MARK: - Signed-In User Profile (`GetUserStatus`)

    @Throws(Throwable::class)
    public suspend fun fetchUserProfile(instanceUuidOverride: String? = null): LiveUserProfile? {
        val metaReq = buildJsonObject {
            put(
                "metadata",
                buildJsonObject {
                    put("ideName", "antigravity")
                    put("extensionName", "antigravity")
                    put("locale", "en")
                },
            )
        }
        val resp = try {
            callUnaryJson(
                method = "GetUserStatus",
                body = metaReq,
                instanceUuidOverride = instanceUuidOverride,
                respectNegativeCache = false,
                perCallTimeoutMs = 5_000L,
            )
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            return null
        }
        return V233RpcPayloadCodec.parseUserProfileResponse(resp)
    }

    // MARK: - Models, Quota & Custom Agents (`GetCascadeModelConfigs` / `GetAvailableModels`)

    public suspend fun fetchModelCatalog(forceRefresh: Boolean = false): LiveModelCatalogResult {
        if (forceRefresh) {
            stateMutex.withLock {
                cachedValidUpstreamModels = null
                cachedDefaultUpstreamModel = null
            }
        }

        val parsedModels = mutableListOf<CascadeModelConfig>()
        val validIds = linkedSetOf<String>()
        var defaultModelId: String? = null
        var parsedQuota: ModelUsageQuota? = null
        val agents = mutableListOf("Default")

        val metaReq = buildJsonObject {
            put("forceRefresh", forceRefresh)
            put(
                "metadata",
                buildJsonObject {
                    put("ideName", "antigravity")
                    put("extensionName", "antigravity")
                    put("locale", "en")
                },
            )
        }

        for (method in listOf("GetCascadeModelConfigs", "GetCascadeModelConfigData")) {
            val obj = runCatching { callUnaryJson(method = method, body = metaReq) }.getOrNull() ?: continue
            val slice = V233RpcPayloadCodec.parseClientModelConfigsResponse(obj) ?: continue
            if (slice.models.isNotEmpty()) {
                parsedModels.addAll(slice.models)
                validIds.addAll(slice.validIds)
                if (defaultModelId == null) defaultModelId = slice.defaultModelId
                if (parsedQuota == null) parsedQuota = slice.quota
                for (name in slice.inlineAgents) {
                    if (name !in agents) agents.add(name)
                }
                break
            }
        }

        if (parsedModels.isEmpty()) {
            val availWrapper = runCatching {
                callUnaryJson(
                    method = "GetAvailableModels",
                    body = buildJsonObject { put("forceRefresh", forceRefresh) },
                )
            }.getOrNull()
            if (availWrapper != null) {
                val slice = V233RpcPayloadCodec.parseAvailableModelsResponse(availWrapper)
                parsedModels.addAll(slice.models)
                validIds.addAll(slice.validIds)
                if (defaultModelId == null) defaultModelId = slice.defaultModelId
                if (parsedQuota == null) parsedQuota = slice.quota
            }
        }

        stateMutex.withLock {
            if (validIds.isNotEmpty()) {
                cachedValidUpstreamModels = validIds
                cachedDefaultUpstreamModel = defaultModelId ?: parsedModels.firstOrNull()?.modelId
            } else {
                cachedValidUpstreamModels = emptySet()
                cachedDefaultUpstreamModel = null
            }
        }

        runCatching { callUnaryJson(method = "GetAllCustomAgentConfigs") }.getOrNull()?.let { agentResp ->
            for (name in V233RpcPayloadCodec.parseCustomAgentNames(agentResp)) {
                if (name !in agents) agents.add(name)
            }
        }

        if (parsedModels.isNotEmpty()) {
            val hasOrchestrator = parsedModels.any { it.isOrchestrator }
            val hasExtraEffort = parsedModels.any { ThinkingEffortLevel.EXTRA in it.supportedEfforts }
            val hasQuota = (parsedQuota != null)
            mutateCapabilityProfile(null) { profile ->
                profile
                    .recordPassiveSignal(
                        HostCapability.ORCHESTRATOR_MODELS,
                        if (hasOrchestrator) CapabilitySupportState.SUPPORTED else CapabilitySupportState.UNSUPPORTED,
                    )
                    .recordPassiveSignal(
                        HostCapability.THINKING_EFFORT_EXTRA,
                        if (hasExtraEffort) CapabilitySupportState.SUPPORTED else CapabilitySupportState.UNSUPPORTED,
                    )
                    .recordPassiveSignal(
                        HostCapability.USAGE_QUOTA,
                        if (hasQuota) CapabilitySupportState.SUPPORTED else CapabilitySupportState.UNSUPPORTED,
                    )
            }
        }

        val finalModels = parsedModels.ifEmpty { CascadeModelConfig.liveDefaultCatalog }
        return LiveModelCatalogResult(
            models = finalModels,
            quota = parsedQuota,
            customAgents = agents,
            defaultModelId = defaultModelId ?: finalModels.firstOrNull()?.modelId,
        )
    }

    // MARK: - Artifacts, Plan Review, Turn Diff Review & Git VCS (`UE11`, `UE12`)

    public suspend fun getArtifactSnapshots(
        cascadeId: String,
        instanceUuidOverride: String? = null,
    ): List<ArtifactSnapshot> {
        val res = callUnaryJson(
            method = "GetArtifactSnapshots",
            body = buildJsonObject { put("cascadeId", cascadeId) },
            instanceUuidOverride = instanceUuidOverride,
        )
        return V233RpcPayloadCodec.parseArtifactSnapshots(res)
    }

    public suspend fun fetchRemoteArtifactResource(
        uri: String,
        cascadeId: String,
        instanceUuidOverride: String? = null,
    ): ResolvedEmbedResource? {
        val normalizedTarget = ResolvedEmbedResource.normalizePath(uri)
        if (normalizedTarget.isEmpty()) return null
        val targetBaseName = normalizedTarget.trimEnd('/').substringAfterLast('/').lowercase()

        // 1. Companion Bridge / Direct LAN `ReadArtifactFile`
        if (channel == RemoteConnectionChannel.DIRECT_HOST) {
            val res = runCatching {
                callUnaryJson(
                    method = "ReadArtifactFile",
                    body = buildJsonObject {
                        put("uri", uri)
                        put("path", normalizedTarget)
                        put("cascadeId", cascadeId)
                    },
                    instanceUuidOverride = instanceUuidOverride,
                )
            }.getOrNull()
            if (res != null) {
                V233RpcPayloadCodec.parseReadArtifactFileResponse(uri, normalizedTarget, res)?.let { return it }
            }
        }

        // 2. Upstream `GetArtifactSnapshots`
        if (cascadeId.isNotEmpty()) {
            val snapshots = runCatching { getArtifactSnapshots(cascadeId, instanceUuidOverride) }.getOrNull().orEmpty()
            val matched = snapshots.firstOrNull { snap ->
                val snapNorm = ResolvedEmbedResource.normalizePath(snap.artifactPath)
                snapNorm == normalizedTarget ||
                    (targetBaseName.isNotEmpty() && snapNorm.trimEnd('/').substringAfterLast('/').lowercase() == targetBaseName)
            }
            if (matched != null && matched.content.isNotEmpty()) {
                return ResolvedEmbedResource(
                    uri = uri,
                    normalizedPath = normalizedTarget,
                    mimeType = ResolvedEmbedResource.inferredMimeType(uri),
                    textContent = matched.content,
                    binaryData = matched.content.encodeToByteArray(),
                    source = EmbedResourceSource.ARTIFACT_SNAPSHOT,
                )
            }
        }

        // 3. Upstream `GetRevisionArtifact` fallback
        if (cascadeId.isNotEmpty()) {
            val revBodies = listOf(
                buildJsonObject {
                    put("cascadeId", cascadeId)
                    put("artifactPath", normalizedTarget)
                },
                buildJsonObject {
                    put("trajectoryId", cascadeId)
                    put("fileUri", uri)
                },
            )
            for (reqBody in revBodies) {
                val res = runCatching {
                    callUnaryJson(
                        method = "GetRevisionArtifact",
                        body = reqBody,
                        instanceUuidOverride = instanceUuidOverride,
                    )
                }.getOrNull() ?: continue
                val content = (res["content"] as? JsonPrimitive)?.contentOrNull
                    ?: ((res["artifact"] as? JsonObject)?.get("content") as? JsonPrimitive)?.contentOrNull
                    ?: (res["text"] as? JsonPrimitive)?.contentOrNull
                if (!content.isNullOrEmpty()) {
                    return ResolvedEmbedResource(
                        uri = uri,
                        normalizedPath = normalizedTarget,
                        mimeType = ResolvedEmbedResource.inferredMimeType(uri),
                        textContent = content,
                        binaryData = content.encodeToByteArray(),
                        source = EmbedResourceSource.ARTIFACT_SNAPSHOT,
                    )
                }
            }
        }
        return null
    }

    public suspend fun sendPlanReviewComments(
        cascadeId: String,
        comments: List<PlanInlineComment>,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "SendPlanReviewComments",
            body = V233RpcPayloadCodec.encodePlanReviewCommentsBody(cascadeId, comments),
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun getTurnDiff(
        cascadeId: String,
        turnNumber: Int? = null,
        mode: DiffCompareMode = DiffCompareMode.TURN,
        instanceUuidOverride: String? = null,
    ): List<FilePatchDiff> {
        val body = buildJsonObject {
            put("cascadeId", cascadeId)
            put("compareMode", mode.displayTitle)
            if (turnNumber != null) put("turnNumber", turnNumber)
        }
        val res = callUnaryJson(
            method = "GetTurnDiff",
            body = body,
            instanceUuidOverride = instanceUuidOverride,
        )
        return V233RpcPayloadCodec.parseFilePatchDiffs(res, defaultTurn = turnNumber ?: 1, defaultScope = mode)
    }

    public suspend fun revertDiffHunk(
        cascadeId: String,
        filePath: String,
        hunkHeader: String? = null,
        instanceUuidOverride: String? = null,
    ) {
        val body = buildJsonObject {
            put("cascadeId", cascadeId)
            put("filePath", filePath)
            if (hunkHeader != null) put("hunkHeader", hunkHeader)
        }
        callUnaryJson("RevertDiffHunk", body, instanceUuidOverride = instanceUuidOverride)
    }

    public suspend fun sendDiffReviewComments(
        cascadeId: String,
        comments: List<DiffLineComment>,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "SendDiffReviewComments",
            body = V233RpcPayloadCodec.encodeDiffReviewCommentsBody(cascadeId, comments),
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun gitStageFile(
        cascadeId: String,
        filePath: String,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "GitStageFile",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("filePath", filePath)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun gitUnstageFile(
        cascadeId: String,
        filePath: String,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "GitUnstageFile",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("filePath", filePath)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun gitDiscardFile(
        cascadeId: String,
        filePath: String,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "GitDiscardFile",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("filePath", filePath)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun gitCommitChanges(
        cascadeId: String,
        draft: GitCommitDraft,
        instanceUuidOverride: String? = null,
    ): GitCommitResult {
        val res = callUnaryJson(
            method = "GitCommit",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("message", draft.message)
                put("includeUnstaged", draft.includeUnstaged)
                put("amend", draft.amendLastCommit)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
        return V233RpcPayloadCodec.parseGitCommitResult(res, draft)
    }

    public suspend fun gitPushBranch(
        cascadeId: String,
        branchName: String,
        instanceUuidOverride: String? = null,
    ): Boolean {
        val res = callUnaryJson(
            method = "GitPush",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("branchName", branchName)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
        return (res["pushed"] as? JsonPrimitive)?.booleanOrNull
            ?: (res["ok"] as? JsonPrimitive)?.booleanOrNull
            ?: true
    }

    // MARK: - v2.33 Orchestration, Side Questions, Permissions, Customizations & Search

    public suspend fun fetchConversationOverview(
        cascadeId: String,
        instanceUuidOverride: String? = null,
    ): ConversationOverviewSnapshot {
        val res = callUnaryJson(
            method = "GetConversationOverview",
            body = buildJsonObject { put("cascadeId", cascadeId) },
            instanceUuidOverride = instanceUuidOverride,
        )
        return V233RpcPayloadCodec.parseConversationOverview(res)
    }

    public suspend fun cancelBackgroundTask(
        cascadeId: String,
        taskId: String,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "CancelBackgroundTask",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("taskId", taskId)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun stopSubagent(
        cascadeId: String,
        subagentId: String,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "StopSubagent",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("subagentId", subagentId)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun sendSideQuestion(
        cascadeId: String,
        question: String,
        threadId: String = "btw-${randomUuidV4().take(8)}",
        instanceUuidOverride: String? = null,
    ): String {
        val res = callUnaryJson(
            method = "SendSideQuestion",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("threadId", threadId)
                put("question", question)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
        return (res["answer"] as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }
            ?: (res["response"] as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }
            ?: "Read-only side answer for: $question"
    }

    public suspend fun revertConversationToStep(
        cascadeId: String,
        stepIndex: Int,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "RevertConversationToStep",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("stepIndex", stepIndex)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun setConversationPermissionPreset(
        cascadeId: String,
        preset: AgentPermissionPreset,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "SetPermissionPreset",
            body = buildJsonObject {
                put("cascadeId", cascadeId)
                put("preset", preset.wireValue)
                put("label", preset.rawValue)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun fetchCustomizationsCatalog(
        instanceUuidOverride: String? = null,
    ): CustomizationsCatalog {
        val res = callUnaryJson(
            method = "GetCustomizationsCatalog",
            body = JsonObject(emptyMap()),
            instanceUuidOverride = instanceUuidOverride,
        )
        return V233RpcPayloadCodec.parseCustomizationsCatalog(res)
    }

    public suspend fun restartMcpServer(
        serverName: String,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "RestartMcpServer",
            body = buildJsonObject { put("serverName", serverName) },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun togglePlugin(
        pluginId: String,
        isEnabled: Boolean,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "TogglePlugin",
            body = buildJsonObject {
                put("pluginId", pluginId)
                put("isEnabled", isEnabled)
            },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun installMarketplacePlugin(
        pluginId: String,
        instanceUuidOverride: String? = null,
    ) {
        callUnaryJson(
            method = "InstallPlugin",
            body = buildJsonObject { put("pluginId", pluginId) },
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    public suspend fun searchAllConversations(
        query: String,
        instanceUuidOverride: String? = null,
    ): List<CascadeSummary> {
        val res = callUnaryJson(
            method = "SearchAllConversations",
            body = buildJsonObject { put("query", query) },
            instanceUuidOverride = instanceUuidOverride,
        )
        return V233RpcPayloadCodec.parseSearchConversations(
            res = res,
            nowEpochMs = currentTimeMillis(),
            originInstanceUuid = instanceUuidOverride ?: currentResolvedInstanceUuid(),
            originHostName = host.hostname,
        )
    }

    // MARK: - Cloud Projects, Repositories & Automations (`UE04`, `UE05`, `UE06`)

    public suspend fun fetchCloudProjects(
        candidateInstances: List<RelayInstanceInfo> = emptyList(),
    ): List<ProjectWorkspace> {
        val pref = stateMutex.withLock { preferredCloudInstanceUuid }
        val targetUuids: List<String?> = if (channel == RemoteConnectionChannel.CLOUD_RELAY && candidateInstances.isNotEmpty()) {
            if (pref != null && candidateInstances.any { it.uuid == pref }) {
                listOf(pref) + candidateInstances.filter { it.uuid != pref }.map { it.uuid }
            } else {
                candidateInstances.map { it.uuid }
            }
        } else {
            listOf(null)
        }

        for (targetUuid in targetUuids) {
            val listResp = runCatching {
                callUnaryJson(
                    method = "ListProjects",
                    body = buildJsonObject { put("backend", "BACKEND_TYPE_REMOTE_AICODE") },
                    instanceUuidOverride = targetUuid,
                    allowCrossHostFailover = true,
                )
            }.getOrNull() ?: continue

            val ids = ((listResp["projectIds"] ?: listResp["project_ids"]) as? JsonArray)
                ?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.takeIf { s -> s.isNotEmpty() } }
                ?: emptyList()
            if (ids.isEmpty()) continue

            val loaded = coroutineScope {
                ids.map { pid ->
                    async {
                        val readResp = runCatching {
                            callUnaryJson(
                                method = "ReadProject",
                                body = buildJsonObject { put("id", pid) },
                                instanceUuidOverride = targetUuid,
                                allowCrossHostFailover = true,
                            )
                        }.getOrNull() ?: return@async null
                        val projObj = readResp["project"] as? JsonObject ?: return@async null
                        V233RpcPayloadCodec.decodeCloudProjectObject(projObj, fallbackId = pid, originInstanceUuid = targetUuid)
                    }
                }.awaitAll().filterNotNull()
            }

            if (loaded.isNotEmpty()) {
                stateMutex.withLock {
                    for (proj in loaded) cachedCloudProjectsById[proj.id] = proj
                    val effectiveUuid = targetUuid ?: resolvedInstanceUuidState
                    if (!effectiveUuid.isNullOrEmpty()) preferredCloudInstanceUuid = effectiveUuid
                }
                return loaded
            }
        }
        return emptyList()
    }

    public suspend fun fetchCloudGitHubRepos(instanceUuidOverride: String? = null): List<GitHubRepoItem> =
        listAvailableResources(resourceType = "github", instanceUuidOverride = instanceUuidOverride)

    public suspend fun listAvailableResources(
        resourceType: String = "github",
        instanceUuidOverride: String? = null,
    ): List<GitHubRepoItem> {
        val resp = runCatching {
            callUnaryJson(
                method = "ListAvailableResources",
                body = buildJsonObject {
                    put("backend", "BACKEND_TYPE_REMOTE_AICODE")
                    put("type", resourceType)
                },
                instanceUuidOverride = instanceUuidOverride,
                allowCrossHostFailover = true,
            )
        }.getOrNull() ?: return emptyList()
        return V233RpcPayloadCodec.parseCloudGitHubRepos(resp)
    }

    public suspend fun createProjectWorkspace(draft: NewProjectDraft): ProjectWorkspace {
        val repoName = draft.selectedRepo?.fullName ?: draft.projectName
        if (channel == RemoteConnectionChannel.CLOUD_RELAY && draft.runsOn == ProjectRuntimeTarget.CLOUD) {
            val newProjectId = randomUuidV4()
            val resourceEntries = buildJsonArray {
                draft.selectedRepo?.let { repo ->
                    add(
                        buildJsonObject {
                            put(
                                "remoteResource",
                                buildJsonObject {
                                    put("type", "github")
                                    put("name", repo.fullName)
                                    put("displayName", repo.fullName)
                                },
                            )
                        }
                    )
                }
                for (link in draft.driveResourceLinks) {
                    val trimmed = link.trim()
                    if (trimmed.isNotEmpty()) {
                        add(
                            buildJsonObject {
                                put(
                                    "remoteResource",
                                    buildJsonObject {
                                        put("type", "google_drive")
                                        put("name", trimmed)
                                        put("displayName", trimmed)
                                    },
                                )
                            }
                        )
                    }
                }
            }
            val projectObj = buildJsonObject {
                put("id", newProjectId)
                put("name", draft.projectName)
                put("backendType", "BACKEND_TYPE_REMOTE_AICODE")
                if (resourceEntries.isNotEmpty()) {
                    put("projectResources", buildJsonObject { put("resources", resourceEntries) })
                }
                if (draft.envSetupScript.isNotBlank()) {
                    put("envSetupScript", draft.envSetupScript)
                }
            }
            val res = callUnaryJson(
                method = "CreateProject",
                body = buildJsonObject {
                    put("backend", "BACKEND_TYPE_REMOTE_AICODE")
                    put("project", projectObj)
                },
                allowCrossHostFailover = true,
            )
            val returnedProj = res["project"] as? JsonObject
            val finalId = (returnedProj?.get("id") as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() } ?: newProjectId
            val finalName = (returnedProj?.get("name") as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() } ?: draft.projectName
            val cloudUri = "cloud://$repoName"
            val created = ProjectWorkspace(
                id = finalId,
                name = finalName,
                pathDisplay = cloudUri,
                workspaceUri = cloudUri,
                runtime = ProjectRuntimeTarget.CLOUD,
                hostName = "Antigravity",
                activeBranch = draft.selectedRepo?.defaultBranch ?: "main",
                cloudProjectId = finalId,
                originInstanceUuid = currentResolvedInstanceUuid(),
            )
            stateMutex.withLock { cachedCloudProjectsById[finalId] = created }
            return created
        }

        val body = buildJsonObject {
            put("name", draft.projectName)
            put("runtime", if (draft.runsOn == ProjectRuntimeTarget.CLOUD) "cloud" else "macbook_pro")
            put("source", draft.source.displayTitle)
            put("repository", repoName)
            put("branchWorktree", draft.branchWorktree)
            if (draft.driveResourceLinks.isNotEmpty()) {
                put("googleDriveLinks", buildJsonArray { draft.driveResourceLinks.forEach { add(JsonPrimitive(it)) } })
            }
            if (draft.uploadedFilePaths.isNotEmpty()) {
                put("uploadedFilePaths", buildJsonArray { draft.uploadedFilePaths.forEach { add(JsonPrimitive(it)) } })
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

    public suspend fun createAutomation(
        prompt: String,
        projectSlug: String = "ledger-svc",
        instanceUuidOverride: String? = null,
    ): AutomationItem {
        val trimmedTitle = prompt.trim().take(64).ifEmpty { "Scheduled Automation" }
        val sidecarId = V233RpcPayloadCodec.makeSidecarId(trimmedTitle)
        val (cronExpr, humanSchedule) = V233RpcPayloadCodec.inferCronAndScheduleLabel(prompt)
        val sidecarBody = buildJsonObject {
            put("sidecarId", sidecarId)
            put("action", SidecarManageAction.CREATE.wireValue)
            put(
                "config",
                buildJsonObject {
                    put("builtin", "schedule")
                    put("restartPolicy", "always")
                    put("displayName", trimmedTitle)
                    put("description", "$humanSchedule: $prompt")
                    put(
                        "args",
                        buildJsonArray {
                            add(JsonPrimitive(cronExpr))
                            add(JsonPrimitive("agentapi"))
                            add(JsonPrimitive("new-conversation"))
                            add(JsonPrimitive("--"))
                            add(JsonPrimitive(prompt.trim()))
                        },
                    )
                },
            )
            if (projectSlug.isBlank() || projectSlug.equals("All projects", ignoreCase = true)) {
                put("allProjects", true)
            }
        }

        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            val createResp = callUnaryJson("ManageSidecar", sidecarBody, instanceUuidOverride = instanceUuidOverride)
            val createdId = (createResp["sidecarId"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
                ?: (createResp["sidecar_id"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() }
                ?: sidecarId
            runCatching {
                callUnaryJson(
                    method = "ManageSidecar",
                    body = buildJsonObject {
                        put("sidecarId", createdId)
                        put("action", SidecarManageAction.ENABLE.wireValue)
                    },
                    instanceUuidOverride = instanceUuidOverride,
                )
            }
            return V233RpcPayloadCodec.parseCreatedAutomation(
                res = createResp,
                prompt = prompt,
                projectSlug = projectSlug,
                fallbackId = createdId,
                originInstanceUuid = instanceUuidOverride ?: currentResolvedInstanceUuid(),
            )
        }

        return try {
            val res = callUnaryJson(
                method = "CreateAutomation",
                body = buildJsonObject {
                    put("prompt", prompt)
                    put("project", projectSlug)
                    put("projectSlug", projectSlug)
                    put("schedule", humanSchedule)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
            V233RpcPayloadCodec.parseCreatedAutomation(
                res = res,
                prompt = prompt,
                projectSlug = projectSlug,
                fallbackId = sidecarId,
                originInstanceUuid = instanceUuidOverride ?: currentResolvedInstanceUuid(),
            )
        } catch (e: Throwable) {
            if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                val createResp = callUnaryJson("ManageSidecar", sidecarBody, instanceUuidOverride = instanceUuidOverride)
                V233RpcPayloadCodec.parseCreatedAutomation(
                    res = createResp,
                    prompt = prompt,
                    projectSlug = projectSlug,
                    fallbackId = sidecarId,
                    originInstanceUuid = instanceUuidOverride ?: currentResolvedInstanceUuid(),
                )
            } else {
                throw e
            }
        }
    }

    public suspend fun setAutomationPaused(
        automationId: String,
        paused: Boolean,
        instanceUuidOverride: String? = null,
    ) {
        val action = if (paused) SidecarManageAction.DISABLE else SidecarManageAction.ENABLE
        val sidecarBody = buildJsonObject {
            put("sidecarId", automationId)
            put("action", action.wireValue)
        }
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            callUnaryJson("ManageSidecar", sidecarBody, instanceUuidOverride = instanceUuidOverride)
            return
        }
        try {
            callUnaryJson(
                method = "SetAutomationPaused",
                body = buildJsonObject {
                    put("automationId", automationId)
                    put("isPaused", paused)
                    put("paused", paused)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
        } catch (e: Throwable) {
            if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                callUnaryJson("ManageSidecar", sidecarBody, instanceUuidOverride = instanceUuidOverride)
            } else {
                throw e
            }
        }
    }

    public suspend fun triggerAutomationNow(
        automationId: String,
        instanceUuidOverride: String? = null,
    ) {
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            callUnaryJson(
                method = "ManageSidecar",
                body = buildJsonObject {
                    put("sidecarId", automationId)
                    put("action", SidecarManageAction.RUN_NOW.wireValue)
                },
                instanceUuidOverride = instanceUuidOverride,
            )
            return
        }
        try {
            callUnaryJson(
                method = "TriggerAutomationNow",
                body = buildJsonObject { put("automationId", automationId) },
                instanceUuidOverride = instanceUuidOverride,
            )
        } catch (e: Throwable) {
            if (ProtocolCompatibilityEngine.isMethodUnimplementedError(e)) {
                callUnaryJson(
                    method = "ManageSidecar",
                    body = buildJsonObject {
                        put("sidecarId", automationId)
                        put("action", SidecarManageAction.RUN_NOW.wireValue)
                    },
                    instanceUuidOverride = instanceUuidOverride,
                )
            } else {
                throw e
            }
        }
    }

    // MARK: - 5-Byte Connect-RPC Server Streaming (`JetboxSubscribeToSummaries`, `StreamCascadeReactiveUpdates`)

    public fun subscribeCascadeReactiveUpdates(
        cascadeId: String,
        instanceUuidOverride: String? = null,
    ): Flow<JsonObject> = subscribeEnvelopeStream(
        method = "StreamCascadeReactiveUpdates",
        body = buildJsonObject {
            put("cascadeId", cascadeId)
            put("protocolVersion", 1)
        },
        instanceUuidOverride = instanceUuidOverride,
    )

    private fun extractConnectEndStreamError(frameBytes: ByteArray): AntigravityRpcError? {
        if (frameBytes.isEmpty()) return null
        val obj = runCatching { json.parseToJsonElement(frameBytes.decodeToString()) as? JsonObject }.getOrNull()
            ?: return null
        val errObj = obj["error"] as? JsonObject
        val rawCode = ((errObj?.get("code") ?: obj["code"]) as? JsonPrimitive)?.contentOrNull?.trim().orEmpty()
        val rawMessage = ((errObj?.get("message") ?: obj["message"]) as? JsonPrimitive)?.contentOrNull?.trim().orEmpty()
        if (rawCode.isEmpty() && rawMessage.isEmpty()) return null
        val combined = listOf(rawCode, rawMessage).filter { it.isNotEmpty() }.joinToString(": ")
        val lowerCode = rawCode.lowercase()
        return when {
            lowerCode == "unauthenticated" || lowerCode == "permission_denied" ->
                AntigravityRpcError.Unauthorized(combined)
            lowerCode == "unimplemented" ||
                ProtocolCompatibilityEngine.isMethodUnimplementedResponse(400, combined) ->
                AntigravityRpcError.HttpError(501, combined)
            lowerCode == "not_found" ->
                AntigravityRpcError.HttpError(404, combined)
            else ->
                AntigravityRpcError.HttpError(400, combined)
        }
    }

    public fun subscribeEnvelopeStream(
        method: String,
        body: JsonObject = JsonObject(emptyMap()),
        instanceUuidOverride: String? = null,
        allowCrossHostFailover: Boolean = false,
    ): Flow<JsonObject> = flow {
        val innerPayload = ConnectEnvelope.encode(body.toString().encodeToByteArray())
        if (channel == RemoteConnectionChannel.CLOUD_RELAY) {
            val isCloudStream = allowCrossHostFailover ||
                (body["backend"] as? JsonPrimitive)?.contentOrNull == "BACKEND_TYPE_REMOTE_AICODE" ||
                (body["backendType"] as? JsonPrimitive)?.contentOrNull == "BACKEND_TYPE_REMOTE_AICODE"
            if (instanceUuidOverride == null && currentResolvedInstanceUuid() == null) {
                resolveCloudRelayInstance(
                    preferredIdentifier = null,
                    allowCrossHostFallback = isCloudStream,
                )
            }
            val targetUuid = selectReachableRelayUuid(instanceUuidOverride, allowCrossHostFailover = isCloudStream)
                ?.takeIf { it.isNotEmpty() }
                ?: throw AntigravityRpcError.HttpError(503, "Selected Antigravity Desktop host is offline")
            val uniqueTag = "$method-${randomUuidV4().take(8)}"
            val url = "$relayOrigin${SapisidHashGenerator.API_SERVICE_PREFIX}/StreamProxyCommand?\$unique=$uniqueTag"
            var activeApiKey = ensureRelayWebApiKey()
            val activeAuth = currentAuthUser()
            val reqBytes = CloudRelayJspbCodec.encodeProxyCommandRequest(
                targetInstanceUuid = targetUuid,
                rpcPath = "$SERVICE_PREFIX/$method",
                payload = innerPayload,
                contentType = "application/connect+json",
                isStreaming = true,
            )

            suspend fun executeCloudStreamOnce(apiKey: String?, allowKeyRefreshRetry: Boolean): Boolean {
                val headers = SapisidHashGenerator.buildApiServiceHeaders(
                    cookieHeader = sessionCookie.orEmpty(),
                    origin = relayOrigin,
                    authUser = activeAuth,
                    apiKey = apiKey,
                    isStreaming = true,
                    timestampSeconds = currentTimeMillis() / 1000L,
                )
                var retryWithRefreshedKey = false
                streamingHttpClient.preparePost(url) {
                    for ((k, v) in headers) {
                        if (!k.equals("Content-Type", ignoreCase = true)) header(k, v)
                    }
                    setBody(ByteArrayContent(reqBytes, ContentType.parse("application/json+protobuf")))
                }.execute { response ->
                    val code = response.status.value
                    val respHeaders = response.flattenHeaders()
                    if (allowKeyRefreshRetry && (code == 400 || code == 403)) {
                        val errBytes = runCatching { response.bodyAsBytes() }.getOrDefault(ByteArray(0))
                        val errText = unwrapErrorBodyText(errBytes, respHeaders)
                        if (SapisidHashGenerator.isInvalidApiKeyError(code, errText)) {
                            val refreshedKey = ensureRelayWebApiKey(forceRefresh = true)
                            if (!refreshedKey.isNullOrEmpty() && refreshedKey != apiKey) {
                                activeApiKey = refreshedKey
                                retryWithRefreshedKey = true
                                return@execute
                            }
                        }
                        if (code == 403) {
                            throw AntigravityRpcError.Unauthorized(
                                buildUnauthorizedDiagnostic(
                                    operation = "StreamProxyCommand/$method",
                                    statusCode = code,
                                    responseHeaders = respHeaders,
                                    rawBytes = errBytes,
                                    apiKey = apiKey,
                                    authUser = activeAuth,
                                )
                            )
                        }
                        throw AntigravityRpcError.HttpError(
                            code,
                            errText.ifBlank { "StreamProxyCommand HTTP $code" },
                        )
                    }
                    if (code == 401 || code == 403) {
                        val errBytes = runCatching { response.bodyAsBytes() }.getOrDefault(ByteArray(0))
                        throw AntigravityRpcError.Unauthorized(
                            buildUnauthorizedDiagnostic(
                                operation = "StreamProxyCommand/$method",
                                statusCode = code,
                                responseHeaders = respHeaders,
                                rawBytes = errBytes,
                                apiKey = apiKey,
                                authUser = activeAuth,
                            )
                        )
                    }
                    if (code !in 200..299) {
                        val errBytes = runCatching { response.bodyAsBytes() }.getOrDefault(ByteArray(0))
                        val errText = unwrapErrorBodyText(errBytes, respHeaders)
                        throw AntigravityRpcError.HttpError(
                            code,
                            errText.ifBlank { "StreamProxyCommand HTTP $code" },
                        )
                    }
                    val headerBase64 = respHeaders.any { (k, v) ->
                        (k.equals("x-goog-safety-encoding", ignoreCase = true) ||
                            k.equals("content-transfer-encoding", ignoreCase = true)) &&
                            v.contains("base64", ignoreCase = true)
                    }
                    val jspbParser = CloudRelayJspbStreamParser()
                    val connectParser = ConnectStreamParser()
                    val b64Decoder = StreamingBase64Decoder()
                    // 0 = auto-detect outer base64 vs raw UTF-8 JSPB, 1 = raw, 2 = base64
                    var outerMode = if (headerBase64) 2 else 0
                    val sniffBuffer = ArrayList<Byte>(4)
                    var yieldedAny = false
                    var done = false

                    suspend fun processDecodedBytes(decodedSlice: ByteArray) {
                        if (decodedSlice.isEmpty() || done) return
                        val innerChunks = jspbParser.feed(decodedSlice)
                        for (rawChunk in innerChunks) {
                            val chunkData = CloudRelayJspbCodec.decompressPayloadIfNeeded(rawChunk)
                            if (!connectParser.hasBufferedBytes &&
                                chunkData.isNotEmpty() &&
                                (chunkData[0].toInt() and 0xFF) == '{'.code
                            ) {
                                val directObj = runCatching {
                                    json.parseToJsonElement(chunkData.decodeToString()) as? JsonObject
                                }.getOrNull()
                                if (directObj != null) {
                                    yieldedAny = true
                                    emit(directObj)
                                    continue
                                }
                            }
                            val frames = connectParser.feed(chunkData)
                            for (frame in frames) {
                                val frameBytes = if (frame.isCompressed) {
                                    CloudRelayJspbCodec.decompressPayloadIfNeeded(frame.payload)
                                } else {
                                    frame.payload
                                }
                                if (frame.isEndStream) {
                                    extractConnectEndStreamError(frameBytes)?.let { throw it }
                                    done = true
                                    break
                                }
                                val obj = runCatching {
                                    json.parseToJsonElement(frameBytes.decodeToString()) as? JsonObject
                                }.getOrNull()
                                if (obj != null) {
                                    yieldedAny = true
                                    emit(obj)
                                }
                            }
                            if (done) break
                        }
                    }

                    val channelReader = response.bodyAsChannel()
                    val buf = ByteArray(4096)
                    while (!done) {
                        val read = channelReader.readAvailable(buf, 0, buf.size)
                        if (read < 0) break
                        if (read == 0) continue
                        when (outerMode) {
                            1 -> processDecodedBytes(buf.copyOf(read))
                            2 -> processDecodedBytes(b64Decoder.feed(buf.copyOf(read)))
                            else -> {
                                var idx = 0
                                while (idx < read && outerMode == 0 && !done) {
                                    val b = buf[idx]
                                    val c = b.toInt() and 0xFF
                                    if (sniffBuffer.isEmpty() &&
                                        (c == ' '.code || c == '\t'.code || c == '\r'.code || c == '\n'.code)
                                    ) {
                                        idx += 1
                                        continue
                                    }
                                    if (sniffBuffer.isEmpty() &&
                                        (c == '['.code || c == '{'.code || c == ')'.code || c == '('.code || c in '0'.code..'9'.code)
                                    ) {
                                        outerMode = 1
                                        processDecodedBytes(buf.copyOfRange(idx, read))
                                        idx = read
                                        break
                                    }
                                    sniffBuffer.add(b)
                                    idx += 1
                                    if (sniffBuffer.size == 4) {
                                        val candidateStr = sniffBuffer.toByteArray().decodeToString()
                                        val decodedPrefix = CloudRelayJspbCodec.decodeBase64Flexible(candidateStr)
                                        val firstDecoded = decodedPrefix?.firstOrNull()?.toInt()?.and(0xFF)
                                        if (decodedPrefix != null &&
                                            (firstDecoded == ')'.code || firstDecoded == '['.code ||
                                                firstDecoded == '{'.code || firstDecoded == ' '.code ||
                                                firstDecoded == '\n'.code)
                                        ) {
                                            outerMode = 2
                                            processDecodedBytes(decodedPrefix)
                                            if (idx < read && !done) {
                                                processDecodedBytes(b64Decoder.feed(buf.copyOfRange(idx, read)))
                                            }
                                        } else {
                                            outerMode = 1
                                            processDecodedBytes(sniffBuffer.toByteArray())
                                            if (idx < read && !done) {
                                                processDecodedBytes(buf.copyOfRange(idx, read))
                                            }
                                        }
                                        sniffBuffer.clear()
                                        idx = read
                                    }
                                }
                            }
                        }
                    }

                    if (!done) {
                        if (outerMode == 2) {
                            processDecodedBytes(b64Decoder.flush())
                        } else if (sniffBuffer.isNotEmpty()) {
                            processDecodedBytes(sniffBuffer.toByteArray())
                            sniffBuffer.clear()
                        }
                    }

                    if (!yieldedAny && !done) {
                        jspbParser.lastErrorTrailer?.let { boqErr ->
                            throw AntigravityRpcError.HttpError(502, boqErr)
                        }
                    }
                }
                return retryWithRefreshedKey
            }

            if (executeCloudStreamOnce(activeApiKey, allowKeyRefreshRetry = true)) {
                executeCloudStreamOnce(activeApiKey, allowKeyRefreshRetry = false)
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
                if (code == 401 || code == 403) throw AntigravityRpcError.Unauthorized("HTTP $code [Stream/$method]")
                if (code !in 200..299) {
                    val errText = runCatching { response.bodyAsBytes().decodeToString() }.getOrDefault("")
                    throw AntigravityRpcError.HttpError(code, errText.ifBlank { "Stream HTTP $code" })
                }
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
                        val frameBytes = if (frame.isCompressed) {
                            CloudRelayJspbCodec.decompressPayloadIfNeeded(frame.payload)
                        } else {
                            frame.payload
                        }
                        if (frame.isEndStream) {
                            extractConnectEndStreamError(frameBytes)?.let { throw it }
                            done = true
                            break
                        }
                        val obj = runCatching {
                            json.parseToJsonElement(frameBytes.decodeToString()) as? JsonObject
                        }.getOrNull()
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
