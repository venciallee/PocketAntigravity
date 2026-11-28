package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.ResilientEnumSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

// MARK: - SemVer Parsing (`AntigravitySemVer`)

/**
 * Semantic version parsed from Antigravity Desktop / Cloud Relay metadata (`"v2.32.0"`,
 * `"2.33.1-beta.1"`, `"3.0.0"`). Returns `null` when a host does not advertise a parseable version
 * (never fabricates a fake default).
 */
@Serializable
public data class AntigravitySemVer(
    public val major: Int,
    public val minor: Int,
    public val patch: Int,
    public val prerelease: String? = null,
) : Comparable<AntigravitySemVer> {

    override fun toString(): String {
        val pre = prerelease?.takeIf { it.isNotEmpty() }
        return if (pre != null) "v$major.$minor.$patch-$pre" else "v$major.$minor.$patch"
    }

    override fun compareTo(other: AntigravitySemVer): Int {
        if (major != other.major) return major.compareTo(other.major)
        if (minor != other.minor) return minor.compareTo(other.minor)
        if (patch != other.patch) return patch.compareTo(other.patch)
        val lPre = prerelease?.takeIf { it.isNotEmpty() }
        val rPre = other.prerelease?.takeIf { it.isNotEmpty() }
        return when {
            lPre == null && rPre == null -> 0
            lPre != null && rPre == null -> -1 // prerelease < stable release
            lPre == null && rPre != null -> 1
            else -> comparePrerelease(lPre!!, rPre!!)
        }
    }

    public companion object {
        private val SEMVER_REGEX = Regex(
            """(?:^|[^0-9])v?(\d+)\.(\d+)(?:\.(\d+))?(?:-([A-Za-z0-9.\-]+))?"""
        )

        /**
         * Parses a version string such as `"v2.32.0"`, `"2.33.1-rc.1"`, `"3.0"`, or `"Antigravity v2.33.0"`.
         */
        public fun parse(raw: String?): AntigravitySemVer? {
            val trimmed = raw?.trim() ?: return null
            if (trimmed.isEmpty()) return null
            val lower = trimmed.lowercase()
            if (lower == "unknown" || lower == "n/a" || lower == "none") return null

            val match = SEMVER_REGEX.find(trimmed) ?: return null
            val major = match.groups[1]?.value?.toIntOrNull() ?: return null
            val minor = match.groups[2]?.value?.toIntOrNull() ?: return null
            val patch = match.groups[3]?.value?.toIntOrNull() ?: 0
            val prerelease = match.groups[4]?.value?.takeIf { it.isNotEmpty() }
            return AntigravitySemVer(
                major = major,
                minor = minor,
                patch = patch,
                prerelease = prerelease,
            )
        }

        private fun comparePrerelease(lhs: String, rhs: String): Int {
            val lParts = lhs.split('.')
            val rParts = rhs.split('.')
            val count = minOf(lParts.size, rParts.size)
            for (i in 0 until count) {
                val lp = lParts[i]
                val rp = rParts[i]
                if (lp == rp) continue
                val lNum = lp.toLongOrNull()
                val rNum = rp.toLongOrNull()
                val cmp = when {
                    lNum != null && rNum != null -> lNum.compareTo(rNum)
                    lNum != null -> -1
                    rNum != null -> 1
                    else -> lp.compareTo(rp, ignoreCase = true).let { if (it != 0) it else lp.compareTo(rp) }
                }
                if (cmp != 0) return cmp
            }
            return lParts.size.compareTo(rParts.size)
        }
    }
}

// MARK: - Host Capabilities & Per-Host Profile

/**
 * Runtime-discovered capabilities of a paired Antigravity Desktop / Companion Bridge host.
 *
 * Designed for **zero upstream cooperation**: capabilities are discovered via passive response
 * fingerprinting (`ListInstances`, `GetCascadeModelConfigs`, Bridge headers) and lazy
 * error-classification negative caching (`404 / 501 / unimplemented`), with optional SemVer
 * priors only as a non-blocking hint.
 */
@Serializable(with = HostCapabilitySerializer::class)
public enum class HostCapability(
    public val displayTitle: String,
    public val minimumRecommendedVersion: AntigravitySemVer?,
    public val rpcMethods: List<String>,
) {
    JETBOX_SUMMARIES(
        displayTitle = "Real-time Conversation Stream",
        minimumRecommendedVersion = AntigravitySemVer(2, 0, 11),
        rpcMethods = listOf("JetboxSubscribeToSummaries"),
    ),
    SIDECAR_AUTOMATIONS(
        displayTitle = "Native Sidecar Automations",
        minimumRecommendedVersion = AntigravitySemVer(2, 20, 0),
        rpcMethods = listOf("GetSidecars", "ManageSidecar", "GetSidecarEvents"),
    ),
    CONVERSATION_ANNOTATIONS(
        displayTitle = "Conversation Annotations",
        minimumRecommendedVersion = AntigravitySemVer(2, 10, 0),
        rpcMethods = listOf("UpdateConversationAnnotations", "DeleteCascadeTrajectory"),
    ),
    TURN_DIFF(
        displayTitle = "Turn Diff Review",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = listOf("GetTurnDiff", "RevertDiffHunk", "SendDiffReviewComments"),
    ),
    GIT_VCS(
        displayTitle = "Git Stage, Commit & Push",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = listOf("GitStageFile", "GitUnstageFile", "GitDiscardFile", "GitCommit", "GitPush"),
    ),
    CONVERSATION_OVERVIEW(
        displayTitle = "Conversation Overview",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = listOf("GetConversationOverview"),
    ),
    SIDE_QUESTION(
        displayTitle = "/btw Side Questions",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = listOf("SendSideQuestion"),
    ),
    REVERT_TO_STEP(
        displayTitle = "Revert Conversation to Step",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = listOf("RevertConversationToStep"),
    ),
    PERMISSION_PRESET(
        displayTitle = "Per-Conversation Permission Preset",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = listOf("SetPermissionPreset"),
    ),
    CUSTOMIZATIONS_CATALOG(
        displayTitle = "Customizations & MCP Controls",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = listOf("GetCustomizationsCatalog", "RestartMcpServer", "TogglePlugin", "InstallPlugin"),
    ),
    FULL_TEXT_SEARCH(
        displayTitle = "Server Full-Text Search",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = listOf("SearchAllConversations"),
    ),
    BACKGROUND_TASK_CONTROL(
        displayTitle = "Background Task & Subagent Control",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = listOf("CancelBackgroundTask", "StopSubagent"),
    ),
    THINKING_EFFORT_EXTRA(
        displayTitle = "Extra Thinking Effort (XHigh)",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = emptyList(),
    ),
    ORCHESTRATOR_MODELS(
        displayTitle = "Orchestrator Models",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = emptyList(),
    ),
    USAGE_QUOTA(
        displayTitle = "Model Usage Quota",
        minimumRecommendedVersion = AntigravitySemVer(2, 33, 0),
        rpcMethods = emptyList(),
    ),
    STREAM_CHUNKING(
        displayTitle = "Chunked Relay Streaming",
        minimumRecommendedVersion = AntigravitySemVer(2, 0, 0),
        rpcMethods = emptyList(),
    ),
    AGENT_STATE_PAGING(
        displayTitle = "Agent State Step Paging",
        minimumRecommendedVersion = AntigravitySemVer(2, 30, 0),
        rpcMethods = listOf("RequestAgentStatePageUpdate"),
    );

    public companion object {
        private val methodToCapability: Map<String, HostCapability> = buildMap {
            for (cap in HostCapability.entries) {
                for (method in cap.rpcMethods) {
                    put(method, cap)
                }
            }
        }

        public fun capabilityForMethod(method: String): HostCapability? =
            methodToCapability[method]

        /**
         * Core baseline & liveness-probe RPC methods expected across supported Desktop hosts.
         * These methods are NEVER permanently short-circuited by negative caching and serve
         * as the canonical allowlist for static RPC registration guardrails.
         */
        public val coreBaselineMethods: Set<String> = setOf(
            "CancelCascadeInvocation",
            "CreateAutomation",
            "CreateProject",
            "CreateProjectWorkspace",
            "GetAllCascadeTrajectories",
            "GetAllCustomAgentConfigs",
            "GetArtifactSnapshots",
            "GetAvailableModels",
            "GetCascadeModelConfigData",
            "GetCascadeModelConfigs",
            "GetCascadeTrajectory",
            "GetCascadeTrajectorySteps",
            "GetRevisionArtifact",
            "GetUserStatus",
            "GetWorkspaceInfos",
            "HandleCascadeUserInteraction",
            "ListAutomations",
            "ListAvailableResources",
            "ListProjects",
            "LoadTrajectory",
            "MoveCascadeToWorkspace",
            "OpenWorkspaceInFinder",
            "ProjectUpdatesStream",
            "ReadArtifactFile",
            "ReadProject",
            "SendPlanReviewComments",
            "SendUserCascadeMessage",
            "SetAutomationPaused",
            "StartCascade",
            "StreamAgentStateUpdates",
            "StreamCascadeReactiveUpdates",
            "TriggerAutomationNow",
        )

        /**
         * Legacy / Companion-Bridge alias RPCs that automatically fall back to upstream
         * `UpdateConversationAnnotations` or `DeleteCascadeTrajectory` on HTTP 404/501.
         */
        public val legacyAliasMethods: Set<String> = setOf(
            "ArchiveCascade",
            "DeleteCascade",
            "PinCascade",
            "RenameCascade",
        )

        /**
         * Complete set of registered Connect-RPC methods (core + legacy aliases + optional capabilities).
         */
        public val allRegisteredMethods: Set<String> = buildSet {
            addAll(coreBaselineMethods)
            addAll(legacyAliasMethods)
            for (cap in entries) {
                addAll(cap.rpcMethods)
            }
        }

        /**
         * Inverse-allowlist negative-caching policy: every non-core RPC (including future optional
         * RPCs not yet assigned a dedicated [HostCapability] case) is automatically cached as
         * unsupported per host upon `404/501/unimplemented`.
         */
        public fun shouldNegativeCacheOnUnimplemented(method: String): Boolean =
            method !in coreBaselineMethods
    }
}

public object HostCapabilitySerializer : ResilientEnumSerializer<HostCapability>(
    serialName = "dev.antigravity.shared.protocol.HostCapability",
    entriesProvider = { HostCapability.entries },
    fallbackProvider = { HostCapability.STREAM_CHUNKING },
)

/**
 * Tri-state capability support status discovered for a host.
 */
@Serializable(with = CapabilitySupportStateSerializer::class)
public enum class CapabilitySupportState {
    UNKNOWN,
    SUPPORTED,
    UNSUPPORTED,
}

public object CapabilitySupportStateSerializer : ResilientEnumSerializer<CapabilitySupportState>(
    serialName = "dev.antigravity.shared.protocol.CapabilitySupportState",
    entriesProvider = { CapabilitySupportState.entries },
    fallbackProvider = { CapabilitySupportState.UNKNOWN },
)

/**
 * Immutable per-host runtime compatibility profile tracking version, Bridge polyfills,
 * positive/negative RPC method caches, stripped unknown proto fields, enum downgrades,
 * and runtime-discovered trajectory step ceilings.
 */
@Serializable
public data class HostCapabilityProfile(
    public val hostKey: String = "default",
    public val reportedVersion: String? = null,
    public val isCompanionBridge: Boolean = false,
    public val bridgeSupportedMethods: Set<String> = emptySet(),
    public val supportedMethods: Set<String> = emptySet(),
    public val unsupportedMethods: Set<String> = emptySet(),
    public val strippedFieldsByMethod: Map<String, Set<String>> = emptyMap(),
    public val downgradedEnumsByMethod: Map<String, Map<String, String>> = emptyMap(),
    public val passiveSignals: Map<HostCapability, CapabilitySupportState> = emptyMap(),
    public val learnedJsonStepCeiling: Int? = null,
    public val binaryProtobufStepsUnsupported: Boolean = false,
    public val updatedAtEpochMs: Long = currentTimeMillis(),
) {
    public val parsedVersion: AntigravitySemVer?
        get() = AntigravitySemVer.parse(normalizedVersionString(reportedVersion))

    public val displayVersionLabel: String
        get() {
            parsedVersion?.let { return it.toString() }
            normalizedVersionString(reportedVersion)?.let { return it }
            return "Version unknown"
        }

    /**
     * Updates reported version; if the host upgraded/downgraded to a different version,
     * clears stale negative caches and learned trajectory ceilings so capabilities re-probe automatically.
     */
    public fun updateReportedVersion(newVersion: String?): HostCapabilityProfile {
        val normalized = normalizedVersionString(newVersion) ?: return this
        val existing = normalizedVersionString(reportedVersion)
        return if (existing != null && existing != normalized) {
            copy(
                reportedVersion = normalized,
                unsupportedMethods = emptySet(),
                strippedFieldsByMethod = emptyMap(),
                downgradedEnumsByMethod = emptyMap(),
                passiveSignals = emptyMap(),
                learnedJsonStepCeiling = null,
                binaryProtobufStepsUnsupported = false,
                updatedAtEpochMs = currentTimeMillis(),
            )
        } else {
            copy(
                reportedVersion = normalized,
                updatedAtEpochMs = currentTimeMillis(),
            )
        }
    }

    public fun recordMethodSupported(method: String): HostCapabilityProfile {
        val nextSupported = supportedMethods + method
        val nextUnsupported = unsupportedMethods - method
        val cap = HostCapability.capabilityForMethod(method)
        val nextSignals = if (cap != null) {
            passiveSignals + (cap to CapabilitySupportState.SUPPORTED)
        } else {
            passiveSignals
        }
        return copy(
            supportedMethods = nextSupported,
            unsupportedMethods = nextUnsupported,
            passiveSignals = nextSignals,
            updatedAtEpochMs = currentTimeMillis(),
        )
    }

    public fun recordMethodUnsupported(method: String): HostCapabilityProfile {
        if (method in bridgeSupportedMethods) return this
        val nextUnsupported = unsupportedMethods + method
        val nextSupported = supportedMethods - method
        val cap = HostCapability.capabilityForMethod(method)
        val nextSignals = if (cap != null) {
            val anySupported = cap.rpcMethods.any { it in nextSupported || it in bridgeSupportedMethods }
            if (!anySupported) {
                passiveSignals + (cap to CapabilitySupportState.UNSUPPORTED)
            } else {
                passiveSignals
            }
        } else {
            passiveSignals
        }
        return copy(
            supportedMethods = nextSupported,
            unsupportedMethods = nextUnsupported,
            passiveSignals = nextSignals,
            updatedAtEpochMs = currentTimeMillis(),
        )
    }

    public fun recordBridgeCapabilities(methods: Set<String>): HostCapabilityProfile {
        if (methods.isEmpty()) return this
        val nextBridge = bridgeSupportedMethods + methods
        val nextUnsupported = unsupportedMethods - methods
        val nextSignals = passiveSignals.toMutableMap()
        for (method in methods) {
            HostCapability.capabilityForMethod(method)?.let { cap ->
                nextSignals[cap] = CapabilitySupportState.SUPPORTED
            }
        }
        return copy(
            isCompanionBridge = true,
            bridgeSupportedMethods = nextBridge,
            unsupportedMethods = nextUnsupported,
            passiveSignals = nextSignals,
            updatedAtEpochMs = currentTimeMillis(),
        )
    }

    public fun recordStrippedField(fieldName: String, forMethod: String): HostCapabilityProfile {
        val existing = strippedFieldsByMethod[forMethod].orEmpty()
        return copy(
            strippedFieldsByMethod = strippedFieldsByMethod + (forMethod to (existing + fieldName)),
            updatedAtEpochMs = currentTimeMillis(),
        )
    }

    public fun recordDowngradedEnum(
        from: String,
        to: String,
        forMethod: String,
    ): HostCapabilityProfile {
        val existing = downgradedEnumsByMethod[forMethod].orEmpty()
        return copy(
            downgradedEnumsByMethod = downgradedEnumsByMethod + (forMethod to (existing + (from to to))),
            updatedAtEpochMs = currentTimeMillis(),
        )
    }

    public fun recordPassiveSignal(
        capability: HostCapability,
        state: CapabilitySupportState,
    ): HostCapabilityProfile = copy(
        passiveSignals = passiveSignals + (capability to state),
        updatedAtEpochMs = currentTimeMillis(),
    )

    /**
     * Records a runtime-observed JSON trajectory step ceiling for this host, keeping the
     * tightest positive ceiling so future large trajectories skip doomed JSON probes.
     */
    public fun recordJsonStepCeiling(ceiling: Int): HostCapabilityProfile {
        if (ceiling <= 0) return this
        val nextCeiling = learnedJsonStepCeiling?.let { minOf(it, ceiling) } ?: ceiling
        return copy(
            learnedJsonStepCeiling = nextCeiling,
            updatedAtEpochMs = currentTimeMillis(),
        )
    }

    /**
     * Records that this host explicitly rejected binary `application/proto` trajectory step requests.
     */
    public fun recordBinaryProtobufStepsUnsupported(): HostCapabilityProfile = copy(
        binaryProtobufStepsUnsupported = true,
        updatedAtEpochMs = currentTimeMillis(),
    )

    /**
     * Returns `true` only when this host has previously demonstrated a JSON step ceiling at or below [knownStepCount].
     */
    public fun shouldPreferBinaryProtobufSteps(knownStepCount: Int): Boolean {
        val ceiling = learnedJsonStepCeiling ?: return false
        if (binaryProtobufStepsUnsupported || knownStepCount <= 0 || ceiling <= 0) return false
        return knownStepCount >= ceiling
    }

    public fun isMethodKnownUnsupported(method: String): Boolean =
        method in unsupportedMethods && method !in bridgeSupportedMethods

    /**
     * Evaluates authoritative runtime support state for [capability].
     * Runtime observations and Bridge declarations always supersede version priors.
     */
    public fun supportState(capability: HostCapability): CapabilitySupportState {
        val methods = capability.rpcMethods
        if (methods.any { it in bridgeSupportedMethods || it in supportedMethods }) {
            return CapabilitySupportState.SUPPORTED
        }
        passiveSignals[capability]?.takeIf { it != CapabilitySupportState.UNKNOWN }?.let {
            return it
        }
        if (methods.isNotEmpty() && methods.any { it in unsupportedMethods }) {
            return CapabilitySupportState.UNSUPPORTED
        }
        return CapabilitySupportState.UNKNOWN
    }

    /**
     * Advisory version-prior hint (true when a known older SemVer predates the capability and
     * neither the host nor a Companion Bridge has confirmed support).
     */
    public fun isOlderThanRecommendedVersion(capability: HostCapability): Boolean {
        if (supportState(capability) == CapabilitySupportState.SUPPORTED) return false
        val parsed = parsedVersion ?: return false
        val minVer = capability.minimumRecommendedVersion ?: return false
        return parsed < minVer
    }

    /**
     * Honest user-facing explanation when an older PC rejects a newer mobile feature.
     */
    public fun userFacingUnsupportedMessage(capability: HostCapability): String {
        val versionPart = when {
            parsedVersion != null -> " (${parsedVersion})"
            !normalizedVersionString(reportedVersion).isNullOrEmpty() -> " (${normalizedVersionString(reportedVersion)})"
            else -> ""
        }
        val minHint = capability.minimumRecommendedVersion?.let { minVer ->
            " Upgrade Antigravity Desktop to $minVer+ or connect via Mac Companion Bridge."
        } ?: " Upgrade Antigravity Desktop or connect via Mac Companion Bridge."
        return "${capability.displayTitle} isn't supported by this Desktop host$versionPart.$minHint"
    }

    public companion object {
        public fun normalizedVersionString(raw: String?): String? {
            val trimmed = raw?.trim() ?: return null
            if (trimmed.isEmpty()) return null
            val lower = trimmed.lowercase()
            if (lower == "unknown" || lower == "n/a" || lower == "none") return null
            return trimmed
        }
    }
}

// MARK: - Protocol Compatibility Engine (Zero-Upstream Self-Healing Helpers)

/**
 * Stateless protocol compatibility utilities shared by **both** Direct LAN and Official Cloud Relay channels.
 * Mirrors Swift `ProtocolCompatibilityEngine` and `scripts/mac-companion-bridge.py` 1:1.
 */
public object ProtocolCompatibilityEngine {
    private val json = Json { ignoreUnknownKeys = true }

    private val UNKNOWN_FIELD_PATTERNS: List<Regex> = listOf(
        Regex("""unknown field\s+["'`]+([A-Za-z0-9_]+)["'`]+""", RegexOption.IGNORE_CASE),
        Regex("""no such field\s+["'`]+([A-Za-z0-9_]+)["'`]+""", RegexOption.IGNORE_CASE),
        Regex("""unrecognized field\s+["'`]+([A-Za-z0-9_]+)["'`]+""", RegexOption.IGNORE_CASE),
    )

    private val INVALID_ENUM_PATTERNS: List<Regex> = listOf(
        Regex("""invalid value for enum[^"'`]*["'`]+([A-Za-z0-9_\-]+)["'`]+""", RegexOption.IGNORE_CASE),
        Regex("""unknown enum value[^"'`]*["'`]+([A-Za-z0-9_\-]+)["'`]+""", RegexOption.IGNORE_CASE),
        Regex("""invalid enum value[^"'`]*["'`]+([A-Za-z0-9_\-]+)["'`]+""", RegexOption.IGNORE_CASE),
    )

    private val VERSION_HEADER_KEYS: Set<String> = setOf(
        "x-antigravity-desktop-version",
        "x-antigravity-server-version",
        "x-codeium-server-version",
        "x-language-server-version",
    )

    /**
     * Returns `true` when [error] indicates the remote `language_server` does not implement the requested RPC method.
     */
    public fun isMethodUnimplementedError(error: Throwable): Boolean {
        val http = error as? AntigravityRpcError.HttpError ?: return false
        return isMethodUnimplementedResponse(http.statusCode, http.body)
    }

    /**
     * Returns `true` when an HTTP/Connect error indicates a missing trajectory/conversation resource
     * (e.g. HTTP 404 `[5,"not_found: trajectory not found (error ID: ...)"]`) from a live `language_server`,
     * as opposed to an unimplemented RPC method or an offline host.
     */
    public fun isTrajectoryNotFoundResponse(statusCode: Int, body: String): Boolean {
        val lower = body.lowercase()
        val isAuthSessionError = lower.contains("google sign-in session") ||
            lower.contains("auth session") ||
            lower.contains("login session")
        if (lower.contains("trajectory not found") ||
            lower.contains("cascade not found") ||
            lower.contains("conversation not found") ||
            lower.contains("unknown cascade") ||
            (lower.contains("agent state") && lower.contains("not found")) ||
            (!isAuthSessionError && lower.contains("session not found"))
        ) {
            return true
        }
        return statusCode == 404 &&
            lower.contains("not_found") &&
            !lower.contains("method not found") &&
            !lower.contains("unimplemented") &&
            !lower.contains("instance")
    }

    public fun isTrajectoryNotFoundError(error: Throwable): Boolean {
        val http = error as? AntigravityRpcError.HttpError ?: return false
        return isTrajectoryNotFoundResponse(http.statusCode, http.body)
    }

    /**
     * Returns `true` when a Google Cloud Relay `ProxyCommand` error indicates the target Desktop
     * instance is no longer registered or reachable (for example, Boq HTTP 400
     * `[9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo",...]]]`).
     */
    public fun isInstanceNotRegisteredResponse(statusCode: Int, body: String): Boolean {
        if (isTrajectoryNotFoundResponse(statusCode, body)) return false
        if (statusCode !in setOf(400, 404, 412, 502, 503)) return false
        val detail = unwrapErrorDetail(body, statusCode = statusCode).lowercase()
        val rawLower = body.lowercase()
        fun matches(text: String): Boolean =
            text.contains("instance not registered") ||
                text.contains("instance is not registered") ||
                text.contains("instance_not_registered") ||
                text.contains("instance not found") ||
                text.contains("instance is offline") ||
                text.contains("instance offline") ||
                text.contains("instance disconnected") ||
                text.contains("target instance not connected") ||
                text.contains("no active tunnel")
        return matches(detail) || matches(rawLower)
    }

    public fun isInstanceNotRegisteredError(error: Throwable): Boolean {
        val http = error as? AntigravityRpcError.HttpError ?: return false
        return isInstanceNotRegisteredResponse(http.statusCode, http.body)
    }

    private fun isResourceNotFoundResponse(statusCode: Int, body: String): Boolean {
        if (isTrajectoryNotFoundResponse(statusCode, body)) return true
        if (isInstanceNotRegisteredResponse(statusCode, body)) return true
        val lower = body.lowercase()
        return lower.contains("project not found") ||
            lower.contains("artifact not found") ||
            lower.contains("step not found") ||
            lower.contains("file not found")
    }

    public fun isMethodUnimplementedResponse(statusCode: Int, body: String): Boolean {
        if (statusCode == 501) return true
        if (isResourceNotFoundResponse(statusCode, body)) return false
        if (statusCode == 404) return true
        val lower = body.lowercase()
        return lower.contains("unimplemented") ||
            lower.contains("unknown method") ||
            lower.contains("method not found") ||
            lower.contains("not implemented")
    }

    /**
     * Strips Google Boq JSPB error envelopes (`[5,"not_found: ..."]`), Connect JSON error envelopes,
     * and any redundant leading `HTTP <code>: ` prefixes into a clean single-line detail string.
     */
    public fun unwrapErrorDetail(raw: String, statusCode: Int? = null): String {
        var cleaned = raw.trim()
        if (cleaned.startsWith(")]}'")) {
            cleaned = cleaned.drop(4).trim()
        }
        val redundantPrefix = if (statusCode != null) Regex("""^HTTP\s+$statusCode:\s*""", RegexOption.IGNORE_CASE) else null
        if (redundantPrefix != null) {
            while (redundantPrefix.containsMatchIn(cleaned)) {
                cleaned = cleaned.replaceFirst(redundantPrefix, "").trim()
            }
        }
        val parsed = runCatching { json.parseToJsonElement(cleaned) }.getOrNull()
        when (parsed) {
            is JsonArray -> {
                val collected = mutableListOf<String>()
                collectJsonArrayStrings(parsed, collected)
                val preferred = collected.firstOrNull {
                    it.isNotBlank() && !it.startsWith("type.googleapis.com/", ignoreCase = true)
                } ?: collected.firstOrNull { it.isNotBlank() }
                preferred?.let { return it.trim() }
            }
            is JsonObject -> {
                val code = (parsed["code"] as? JsonPrimitive)?.contentOrNull?.trim().orEmpty()
                val msg = listOf("message", "error", "detail", "details")
                    .firstNotNullOfOrNull { (parsed[it] as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { s -> s.isNotEmpty() } }
                if (msg != null) {
                    return if (code.isNotEmpty() && !msg.startsWith(code, ignoreCase = true)) "$code: $msg" else msg
                }
            }
            else -> Unit
        }
        return cleaned
    }

    private fun isAlreadyFormattedUserFacingMessage(text: String): Boolean {
        val trimmed = text.trim()
        return trimmed.startsWith("Antigravity Desktop is offline") ||
            trimmed.startsWith("Conversation history could not be found on this host") ||
            trimmed.startsWith("This conversation was not found on this host")
    }

    /**
     * Formats an RPC/transport failure cleanly for UI presentation (never doubling `HTTP 404: HTTP 404:`
     * or leaking raw Boq JSON-array brackets like `[5,"not_found: ..."]`).
     */
    public fun formatUserFacingRpcError(error: Throwable): String {
        val http = error as? AntigravityRpcError.HttpError
        if (http != null) {
            val detail = unwrapErrorDetail(http.body, statusCode = http.statusCode)
            if (isAlreadyFormattedUserFacingMessage(detail)) {
                return detail
            }
            if (isInstanceNotRegisteredResponse(http.statusCode, http.body)) {
                return "Antigravity Desktop is offline or unregistered on Cloud Relay. Ensure Antigravity Desktop is open with Remote Control enabled."
            }
            if (isTrajectoryNotFoundResponse(http.statusCode, http.body)) {
                return if (detail.isNotEmpty()) {
                    "Conversation history could not be found on this host ($detail). Try Retry or open it once on Antigravity Desktop."
                } else {
                    "Conversation history could not be found on this host. Try Retry or open it once on Antigravity Desktop."
                }
            }
            return if (detail.isNotEmpty()) "HTTP ${http.statusCode}: $detail" else "HTTP ${http.statusCode}"
        }
        return error.message?.takeIf { it.isNotBlank() } ?: "Failed to load trajectory steps"
    }

    /**
     * Formats a message-send failure cleanly for UI presentation without conflating send failures
     * with history-loading errors or double-wrapping already formatted errors.
     */
    public fun formatUserFacingSendError(error: Throwable): String {
        val http = error as? AntigravityRpcError.HttpError
        if (http != null) {
            val detail = unwrapErrorDetail(http.body, statusCode = http.statusCode)
            if (isAlreadyFormattedUserFacingMessage(detail)) {
                return detail
            }
            if (isInstanceNotRegisteredResponse(http.statusCode, http.body)) {
                return "Antigravity Desktop is offline or unregistered on Cloud Relay. Ensure Antigravity Desktop is open with Remote Control enabled."
            }
            if (isTrajectoryNotFoundResponse(http.statusCode, http.body)) {
                return if (detail.isNotEmpty()) {
                    "This conversation was not found on this host ($detail). Tap Retry or start a new chat."
                } else {
                    "This conversation was not found on this host. Tap Retry or start a new chat."
                }
            }
            return if (detail.isNotEmpty()) "HTTP ${http.statusCode}: $detail" else "HTTP ${http.statusCode}"
        }
        return error.message?.takeIf { it.isNotBlank() } ?: "Message dispatch failed"
    }

    private fun collectJsonArrayStrings(arr: JsonArray, out: MutableList<String>, depth: Int = 0) {
        if (depth > 4) return
        for (el in arr) {
            when (el) {
                is JsonPrimitive -> {
                    val str = el.takeIf { it.isString }?.contentOrNull?.trim()
                    if (!str.isNullOrEmpty()) {
                        out.add(str)
                    }
                }
                is JsonArray -> collectJsonArrayStrings(el, out, depth + 1)
                is JsonObject -> {
                    for (key in listOf("message", "error", "detail", "details")) {
                        val msg = (el[key] as? JsonPrimitive)?.contentOrNull?.trim()
                        if (!msg.isNullOrEmpty()) out.add(msg)
                    }
                }
            }
        }
    }

    private fun candidateErrorStrings(raw: String): List<String> {
        val candidates = mutableListOf<String>()
        val trimmed = raw.trim().let { if (it.startsWith(")]}'")) it.drop(4).trim() else it }
        val parsed = runCatching { json.parseToJsonElement(trimmed) }.getOrNull()
        when (parsed) {
            is JsonObject -> {
                for (key in listOf("message", "error", "detail", "details")) {
                    val msg = (parsed[key] as? JsonPrimitive)?.contentOrNull
                    if (!msg.isNullOrEmpty()) {
                        candidates.add(msg)
                        if (msg.contains("\\\"")) {
                            candidates.add(msg.replace("\\\"", "\""))
                        }
                    }
                }
            }
            is JsonArray -> {
                val arrStrings = mutableListOf<String>()
                collectJsonArrayStrings(parsed, arrStrings)
                for (msg in arrStrings) {
                    candidates.add(msg)
                    if (msg.contains("\\\"")) {
                        candidates.add(msg.replace("\\\"", "\""))
                    }
                }
            }
            else -> Unit
        }
        candidates.add(raw)
        if (raw.contains("\\\"")) {
            candidates.add(raw.replace("\\\"", "\""))
        }
        return candidates
    }

    /**
     * Extracts an unknown protobuf JSON field name from Connect-RPC / protojson error messages, e.g.:
     * - `unknown field "thinkingEffort"`
     * - `{"code":"invalid_argument","message":"unknown field \"permissionPreset\""}`
     * - `no such field "agentPersona"`
     */
    public fun extractUnknownProtoFieldName(message: String): String? {
        for (candidate in candidateErrorStrings(message)) {
            for (pattern in UNKNOWN_FIELD_PATTERNS) {
                val field = pattern.find(candidate)?.groups?.get(1)?.value
                if (!field.isNullOrEmpty()) return field
            }
        }
        return null
    }

    /**
     * Extracts a rejected protobuf enum value string from Connect-RPC / protojson error messages, e.g.:
     * - `invalid value for enum type exa.cortex_pb.ThinkingEffort: "XHIGH"`
     * - `{"code":"invalid_argument","message":"invalid value for enum type ThinkingEffort: \"XHIGH\""}`
     * - `unknown enum value "PERMISSION_SCOPE_CONVERSATION"`
     */
    public fun extractInvalidEnumValue(message: String): String? {
        for (candidate in candidateErrorStrings(message)) {
            for (pattern in INVALID_ENUM_PATTERNS) {
                val enumVal = pattern.find(candidate)?.groups?.get(1)?.value
                if (!enumVal.isNullOrEmpty()) return enumVal
            }
        }
        return null
    }

    /**
     * Deterministic enum downgrade map when a newer mobile client talks to an older Desktop `language_server`.
     * Kept 1:1 in sync with `HostCapabilityRegistry.swift` and `BRIDGE_ENUM_DOWNGRADES` in `scripts/mac-companion-bridge.py`.
     */
    public fun downgradedEnumReplacement(invalidValue: String): String? = when (invalidValue) {
        "XHIGH" -> "HIGH"
        "xhigh" -> "high"
        "EXTRA" -> "HIGH"
        "extra" -> "high"
        "THINKING_EFFORT_EXTRA", "THINKING_EFFORT_XHIGH" -> "THINKING_EFFORT_HIGH"
        "PERMISSION_SCOPE_CONVERSATION", "PERMISSION_SCOPE_ALWAYS" -> "PERMISSION_SCOPE_TURN"
        "PERMISSION_SCOPE_TURN" -> "PERMISSION_SCOPE_ONCE"
        "ARTIFACT_REVIEW_MODE_TURBO" -> "ARTIFACT_REVIEW_MODE_AUTO"
        "CASCADE_COMMANDS_AUTO_EXECUTION_EAGER" -> "CASCADE_COMMANDS_AUTO_EXECUTION_AUTO"
        "PERMISSION_PRESET_DEFAULT" -> "PERMISSION_PRESET_AUTO"
        else -> null
    }

    /**
     * Recursively removes [fieldName] anywhere inside [body].
     * When stripping a rich `SendUserCascadeMessage` item subtype (`codeQuote`, `mention`, `media`),
     * preserves user intent by folding its readable label/URI/snippet into a plain `{"text": ...}` item.
     */
    public fun recursivelyRemoveField(
        fieldName: String,
        body: JsonObject,
    ): Pair<JsonObject, Boolean> {
        val mutable = LinkedHashMap<String, JsonElement>(body.size)
        var didRemove = false

        for ((key, value) in body) {
            if (key == fieldName) {
                didRemove = true
                continue
            }
            if (key == "items" && value is JsonArray) {
                var itemsMutated = false
                val newItems = value.map { entry ->
                    val folded = foldRichItemIfStripping(entry, fieldName)
                    if (folded != null) {
                        itemsMutated = true
                        folded
                    } else {
                        val (cleanedVal, removedInside) = recursivelyRemoveFieldFromElement(fieldName, entry)
                        if (removedInside) itemsMutated = true
                        cleanedVal
                    }
                }
                if (itemsMutated) {
                    mutable[key] = JsonArray(newItems)
                    didRemove = true
                } else {
                    mutable[key] = value
                }
            } else {
                val (cleanedVal, removedInside) = recursivelyRemoveFieldFromElement(fieldName, value)
                if (removedInside) {
                    mutable[key] = cleanedVal
                    didRemove = true
                } else {
                    mutable[key] = value
                }
            }
        }
        return JsonObject(mutable) to didRemove
    }

    private fun foldRichItemIfStripping(entry: JsonElement, fieldName: String): JsonElement? {
        if (fieldName != "codeQuote" && fieldName != "mention" && fieldName != "media") return null
        val entryObj = entry as? JsonObject ?: return null
        val container = (entryObj["item"] as? JsonObject) ?: entryObj
        val strippedObj = container[fieldName] as? JsonObject ?: return null
        val label = (strippedObj["label"] as? JsonPrimitive)?.contentOrNull
            ?: (strippedObj["uri"] as? JsonPrimitive)?.contentOrNull
            ?: (strippedObj["targetUri"] as? JsonPrimitive)?.contentOrNull
            ?: (strippedObj["filePath"] as? JsonPrimitive)?.contentOrNull
            ?: fieldName
        val snippet = (strippedObj["snippet"] as? JsonPrimitive)?.contentOrNull
        return if (!snippet.isNullOrEmpty()) {
            buildJsonObject { put("text", "[Context: $label]\n$snippet") }
        } else {
            buildJsonObject { put("text", "[Attached $fieldName: $label]") }
        }
    }

    private fun recursivelyRemoveFieldFromElement(
        fieldName: String,
        value: JsonElement,
    ): Pair<JsonElement, Boolean> = when (value) {
        is JsonObject -> recursivelyRemoveField(fieldName, value)
        is JsonArray -> {
            var didRemove = false
            val mapped = value.map { elem ->
                val (u, r) = recursivelyRemoveFieldFromElement(fieldName, elem)
                if (r) didRemove = true
                u
            }
            JsonArray(mapped) to didRemove
        }
        else -> value to false
    }

    /**
     * Recursively replaces exact string occurrences of [invalidValue] with [replacement].
     */
    public fun recursivelyReplaceEnumValue(
        invalidValue: String,
        replacement: String,
        body: JsonObject,
    ): Pair<JsonObject, Boolean> {
        val mutable = LinkedHashMap<String, JsonElement>(body.size)
        var didReplace = false
        for ((key, value) in body) {
            val (updated, replaced) = recursivelyReplaceEnumInElement(invalidValue, replacement, value)
            if (replaced) didReplace = true
            mutable[key] = updated
        }
        return JsonObject(mutable) to didReplace
    }

    private fun recursivelyReplaceEnumInElement(
        invalidValue: String,
        replacement: String,
        value: JsonElement,
    ): Pair<JsonElement, Boolean> = when (value) {
        is JsonPrimitive -> {
            if (value.isString && value.content == invalidValue) {
                JsonPrimitive(replacement) to true
            } else {
                value to false
            }
        }
        is JsonObject -> recursivelyReplaceEnumValue(invalidValue, replacement, value)
        is JsonArray -> {
            var didReplace = false
            val mapped = value.map { elem ->
                val (u, r) = recursivelyReplaceEnumInElement(invalidValue, replacement, elem)
                if (r) didReplace = true
                u
            }
            JsonArray(mapped) to didReplace
        }
    }

    /**
     * Secondary fallback when an older Desktop host rejects an unrecognized enum string value
     * not listed in [downgradedEnumReplacement]: recursively strips every JSON object key
     * whose string value matches [targetValue] so the older host falls back to its protobuf default.
     */
    public fun recursivelyRemoveKeysWithValue(
        targetValue: String,
        body: JsonObject,
    ): Pair<JsonObject, Set<String>> {
        val copy = LinkedHashMap<String, JsonElement>(body.size)
        val removedKeys = mutableSetOf<String>()
        for ((key, value) in body) {
            when (value) {
                is JsonPrimitive -> {
                    if (value.isString && value.content == targetValue) {
                        removedKeys.add(key)
                    } else {
                        copy[key] = value
                    }
                }
                is JsonObject -> {
                    val (updatedObj, nestedRemoved) = recursivelyRemoveKeysWithValue(targetValue, value)
                    copy[key] = updatedObj
                    removedKeys.addAll(nestedRemoved)
                }
                is JsonArray -> {
                    val mapped = value.map { elem ->
                        if (elem is JsonObject) {
                            val (updatedObj, subRemoved) = recursivelyRemoveKeysWithValue(targetValue, elem)
                            removedKeys.addAll(subRemoved)
                            updatedObj
                        } else {
                            elem
                        }
                    }
                    copy[key] = JsonArray(mapped)
                }
            }
        }
        return JsonObject(copy) to removedKeys
    }

    /**
     * Pre-applies cached field strips and enum downgrades learned for this host + [method]
     * so subsequent RPC calls succeed on the first round-trip.
     */
    public fun applyKnownDowngrades(
        body: JsonObject,
        method: String,
        profile: HostCapabilityProfile,
    ): JsonObject {
        var working = body
        profile.strippedFieldsByMethod[method]?.sorted()?.forEach { field ->
            working = recursivelyRemoveField(field, working).first
        }
        profile.downgradedEnumsByMethod[method]?.entries?.sortedBy { it.key }?.forEach { (invalidVal, replacement) ->
            working = recursivelyReplaceEnumValue(invalidVal, replacement, working).first
        }
        return working
    }

    /**
     * Extracts a reported Desktop / LanguageServer version from HTTP response headers or an upstream JSON body.
     */
    public fun extractVersionFromHeadersOrBody(
        headers: Map<String, String>,
        body: JsonObject? = null,
    ): String? {
        for ((rawKey, rawVal) in headers) {
            if (rawKey.lowercase() in VERSION_HEADER_KEYS) {
                HostCapabilityProfile.normalizedVersionString(rawVal)?.let { return it }
            }
        }
        if (body != null) {
            val directKeys = listOf("serverVersion", "desktopVersion", "appVersion", "languageServerVersion", "version")
            for (key in directKeys) {
                val value = HostCapabilityProfile.normalizedVersionString((body[key] as? JsonPrimitive)?.contentOrNull)
                if (value != null && AntigravitySemVer.parse(value) != null) {
                    return value
                }
            }
            val nestedContainers = listOf("serverInfo", "userStatus", "host", "metadata", "status")
            for (containerKey in nestedContainers) {
                val nested = body[containerKey] as? JsonObject ?: continue
                for (key in directKeys) {
                    val value = HostCapabilityProfile.normalizedVersionString((nested[key] as? JsonPrimitive)?.contentOrNull)
                    if (value != null && AntigravitySemVer.parse(value) != null) {
                        return value
                    }
                }
            }
        }
        return null
    }

    /**
     * Extracts comma-separated method names polyfilled by `scripts/mac-companion-bridge.py`.
     */
    public fun extractBridgeCapabilities(headers: Map<String, String>): Set<String> {
        for ((rawKey, rawVal) in headers) {
            if (rawKey.equals("x-antigravity-bridge-capabilities", ignoreCase = true)) {
                return rawVal.split(',')
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                    .toSet()
            }
        }
        return emptySet()
    }
}
