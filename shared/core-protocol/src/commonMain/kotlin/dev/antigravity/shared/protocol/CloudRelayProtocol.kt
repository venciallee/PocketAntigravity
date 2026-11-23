package dev.antigravity.shared.protocol

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import okio.ByteString.Companion.encodeUtf8
import okio.ByteString.Companion.toByteString

/**
 * Connection lifecycle state reported by `ApiService/ListInstances` (JSPB field 3).
 */
@Serializable
public enum class RelayInstanceStatus(public val rawCode: Int) {
    UNKNOWN(0),
    CONNECTED(1),
    DISCONNECTED(2),
    IDLE(3);

    public val isReachable: Boolean
        get() = this == CONNECTED || this == IDLE

    public val badgeText: String
        get() = when (this) {
            CONNECTED -> "Online"
            IDLE -> "Idle"
            DISCONNECTED -> "Offline"
            UNKNOWN -> "Unknown"
        }

    public companion object {
        public fun fromRawCode(code: Int): RelayInstanceStatus =
            entries.firstOrNull { it.rawCode == code } ?: UNKNOWN
    }
}

/**
 * Metadata for a Desktop or Cloud Antigravity instance registered on Google Cloud Relay.
 */
@Serializable
public data class RelayInstanceInfo(
    public val uuid: String,
    public val name: String,
    public val version: String = "v2.32.0",
    public val supportsChunking: Boolean = true,
    public val status: RelayInstanceStatus = RelayInstanceStatus.CONNECTED,
    public val updatedAtEpochMs: Long? = null,
) {
    public val id: String get() = uuid

    public fun matches(rawIdentifier: String): Boolean {
        val needle = rawIdentifier.trim().lowercase()
        if (needle.isEmpty()) return false
        val uuidLower = uuid.lowercase()
        val nameLower = name.lowercase()
        if (uuidLower == needle || nameLower == needle) return true
        return needle.length >= 8 && (uuidLower.startsWith(needle) || nameLower.startsWith(needle))
    }

    public fun sameHostFamily(rawIdentifier: String): Boolean {
        val needle = rawIdentifier.trim().lowercase()
        val candidate = name.trim().lowercase()
        if (needle.isEmpty() || candidate.isEmpty()) return false
        if (matches(needle)) return true

        val lhsParts = needle.split('-').filter { it.isNotEmpty() }
        val rhsParts = candidate.split('-').filter { it.isNotEmpty() }
        if (lhsParts.isEmpty() || rhsParts.isEmpty()) return false

        val commonSegments = mutableListOf<String>()
        for (i in 0 until minOf(lhsParts.size, rhsParts.size)) {
            if (lhsParts[i] == rhsParts[i]) commonSegments.add(lhsParts[i]) else break
        }
        if (commonSegments.size >= 2 && commonSegments.joinToString("-").length >= 7) {
            return true
        }
        val genericPrefixes = setOf("antigravity", "localhost", "macbook", "desktop", "workspace")
        val first = commonSegments.firstOrNull()
        return commonSegments.size == 1 && first != null && first.length >= 8 && first !in genericPrefixes
    }
}

/**
 * Computes Google `SAPISIDHASH` / `SAPISID1PHASH` / `SAPISID3PHASH` authorization headers
 * and builds required `devtools_jetski_boq_api_proto.ApiService` gRPC-Web / JSPB headers.
 */
public object SapisidHashGenerator {
    public const val DEFAULT_ORIGIN: String = "https://antigravity.google.com"
    public const val API_SERVICE_PREFIX: String = "/\$rpc/devtools_jetski_boq_api_proto.ApiService"
    public const val RELAY_API_KEY_ENV_VAR_NAME: String = "ANTIGRAVITY_RELAY_API_KEY"
    public const val ANTIGRAVITY_TEST_HEADER_NAME: String = "x-antigravity-test-72e4dd1c-e8ae-4e97-873b-c3d3a01b735d"
    public const val MOBILE_REMOTE_USER_AGENT: String =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private val contextualApiKeyRegex = Regex(
        """(?:x-goog-api-key|WIu0Nc|QrtxK|P10xbc|apiKey|api_key|webApiKey)["']?\s*[:=]\s*["'](AIza[0-9A-Za-z_-]{35})["']""",
        RegexOption.IGNORE_CASE,
    )
    private val googleWebApiKeyRegex = Regex("""(?<![0-9A-Za-z_-])(AIza[0-9A-Za-z_-]{35})(?![0-9A-Za-z_-])""")
    private val metaNameFirstRegex = Regex(
        """<meta\b[^>]*\bname\s*=\s*["']antigravity-relay-api-key["'][^>]*\bcontent\s*=\s*["']([A-Za-z0-9_.\-]{8,128})["']""",
        RegexOption.IGNORE_CASE,
    )
    private val metaContentFirstRegex = Regex(
        """<meta\b[^>]*\bcontent\s*=\s*["']([A-Za-z0-9_.\-]{8,128})["'][^>]*\bname\s*=\s*["']antigravity-relay-api-key["']""",
        RegexOption.IGNORE_CASE,
    )
    private val explicitHeaderJsonRegex = Regex(
        """["']x-goog-api-key["']\s*[:=]\s*["']([A-Za-z0-9_.\-]{8,128})["']""",
        RegexOption.IGNORE_CASE,
    )
    private val explicitConfigKeyRegex = Regex(
        """(?:"apiKey"|'apiKey'|apiKey|"x-goog-api-key"|'x-goog-api-key'|"SNlM0e"|'SNlM0e')\s*[:=]\s*["']([^"'\s]{16,128})["']""",
        RegexOption.IGNORE_CASE,
    )
    private val scriptSrcRegex = Regex(
        """<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']""",
        RegexOption.IGNORE_CASE,
    )
    private val modulePreloadHrefRegex = Regex(
        """<link\b[^>]*\brel\s*=\s*["'](?:modulepreload|preload)["'][^>]*\bhref\s*=\s*["']([^"']+\.m?js(?:\?[^"']*)?)["']""",
        RegexOption.IGNORE_CASE,
    )
    private val modulePreloadHrefFirstRegex = Regex(
        """<link\b[^>]*\bhref\s*=\s*["']([^"']+\.m?js(?:\?[^"']*)?)["'][^>]*\brel\s*=\s*["'](?:modulepreload|preload)["']""",
        RegexOption.IGNORE_CASE,
    )

    public fun isLoopbackOrigin(rawOrigin: String): Boolean {
        val normalized = normalizeOrigin(rawOrigin)
        val authority = normalized.substringAfter("://", "")
        val host = if (authority.startsWith("[")) {
            authority.substringBefore(']').lowercase() + "]"
        } else {
            authority.substringBefore(':').lowercase()
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }

    public fun extractAllWebApiKeys(sourceText: String): List<String> {
        if (sourceText.isBlank()) return emptyList()
        val ordered = linkedSetOf<String>()
        fun collect(regex: Regex) {
            for (match in regex.findAll(sourceText)) {
                match.groupValues.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() }?.let { ordered.add(it) }
            }
        }
        collect(contextualApiKeyRegex)
        collect(googleWebApiKeyRegex)
        collect(metaNameFirstRegex)
        collect(metaContentFirstRegex)
        collect(explicitHeaderJsonRegex)
        collect(explicitConfigKeyRegex)
        return ordered.toList()
    }

    public fun extractWebApiKey(sourceText: String): String? =
        extractAllWebApiKeys(sourceText).firstOrNull()

    public fun extractBootstrapScriptUrls(
        html: String,
        baseUrl: String,
        limit: Int = 12,
    ): List<String> {
        if (html.isBlank() || limit <= 0) return emptyList()
        val normalizedBase = baseUrl.trim()
        val baseOrigin = normalizeOrigin(normalizedBase)
        val baseScheme = baseOrigin.substringBefore("://", "https")
        val baseAuthority = baseOrigin.substringAfter("://", "")
        val baseHost = baseAuthority.substringBefore(':').lowercase()
        val basePathDir = run {
            val afterOrigin = normalizedBase.removePrefix(baseOrigin)
            val pathOnly = afterOrigin.substringBefore('?').substringBefore('#')
            if (pathOnly.isEmpty() || pathOnly == "/") "/" else pathOnly.substringBeforeLast('/') + "/"
        }

        val seen = linkedSetOf<String>()
        val prioritized = mutableListOf<String>()
        val secondary = mutableListOf<String>()

        val allMatches = sequence {
            yieldAll(scriptSrcRegex.findAll(html))
            yieldAll(modulePreloadHrefRegex.findAll(html))
            yieldAll(modulePreloadHrefFirstRegex.findAll(html))
        }

        for (match in allMatches) {
            val rawSrc = match.groupValues.getOrNull(1)?.trim()?.replace("&amp;", "&").orEmpty()
            if (rawSrc.isEmpty()) continue
            val resolved = when {
                rawSrc.startsWith("https://", ignoreCase = true) || rawSrc.startsWith("http://", ignoreCase = true) -> rawSrc
                rawSrc.startsWith("//") -> "$baseScheme:$rawSrc"
                rawSrc.startsWith("/") -> "$baseOrigin$rawSrc"
                else -> "$baseOrigin$basePathDir$rawSrc"
            }
            val resolvedOrigin = normalizeOrigin(resolved)
            val host = resolvedOrigin.substringAfter("://", "").substringBefore(':').lowercase()
            val isTrustedHost = (baseHost.isNotEmpty() && host == baseHost) ||
                host == "google.com" ||
                host.endsWith(".google.com") ||
                host == "gstatic.com" ||
                host.endsWith(".gstatic.com") ||
                host.endsWith(".googleusercontent.com")
            if (!isTrustedHost) continue
            if (!seen.add(resolved)) continue

            val lowerPathAndQuery = resolved.removePrefix(resolvedOrigin).lowercase()
            val isPriorityBundle = lowerPathAndQuery.contains("antigravity") ||
                lowerPathAndQuery.contains("jetski") ||
                lowerPathAndQuery.contains("boq") ||
                lowerPathAndQuery.contains("/_/") ||
                lowerPathAndQuery.contains("main") ||
                lowerPathAndQuery.contains("app") ||
                lowerPathAndQuery.contains("bundle") ||
                lowerPathAndQuery.contains("chunk") ||
                lowerPathAndQuery.contains("bootstrap")
            if (isPriorityBundle) {
                prioritized.add(resolved)
            } else {
                secondary.add(resolved)
            }
        }
        return (prioritized + secondary).take(limit)
    }

    public fun isInvalidApiKeyError(statusCode: Int, responseBody: String): Boolean {
        if (statusCode != 400 && statusCode != 403) return false
        val lower = responseBody.lowercase()
        return lower.contains("api_key_invalid") ||
            lower.contains("api_key_service_blocked") ||
            lower.contains("api_key_http_referrer_blocked") ||
            lower.contains("api key not valid") ||
            lower.contains("api key expired") ||
            lower.contains("invalid api key") ||
            lower.contains("missing a valid api key") ||
            lower.contains("unregistered callers") ||
            lower.contains("x-goog-api-key") ||
            lower.contains("requests to this api") ||
            lower.contains("are blocked") ||
            lower.contains("keyinvalid")
    }

    /**
     * Safe, non-secret diagnostic summary of which Google auth cookie names are present (never exposes values).
     */
    public fun summarizeCookieNames(rawCookieHeader: String): String {
        val trimmed = rawCookieHeader.trim()
        if (trimmed.isEmpty()) return "none"
        if (trimmed.lowercase().startsWith("bearer ") || trimmed.startsWith("ya29.")) return "bearer"
        val cookies = parseCookies(trimmed)
        val interesting = listOf(
            "SAPISID",
            "__Secure-1PAPISID",
            "__Secure-3PAPISID",
            "SID",
            "__Secure-1PSID",
            "__Secure-3PSID",
            "OSID",
            "__Secure-OSID",
            "SIDCC",
            "__Secure-1PSIDCC",
            "__Secure-1PSIDTS",
        )
        val present = interesting.filter { cookies.containsKey(it) }
            .map { it.removePrefix("__Secure-") }
        return "n=${cookies.size}[${present.joinToString(",")}]"
    }

    public fun parseCookies(rawCookieHeader: String): Map<String, String> {
        val result = linkedMapOf<String, String>()
        var cleaned = rawCookieHeader.trim()
        if (cleaned.lowercase().startsWith("cookie:")) {
            cleaned = cleaned.drop("cookie:".length).trim()
        }
        for (part in cleaned.split(';')) {
            val trimmed = part.trim()
            val eqIdx = trimmed.indexOf('=')
            if (eqIdx <= 0) continue
            val key = trimmed.substring(0, eqIdx).trim()
            val value = trimmed.substring(eqIdx + 1).trim()
            if (key.isNotEmpty() && value.isNotEmpty()) {
                result[key] = value
            }
        }
        return result
    }

    public fun hasRequiredGoogleAuthCookies(rawCookieOrToken: String): Boolean {
        val trimmed = rawCookieOrToken.trim()
        if (trimmed.lowercase().startsWith("bearer ") || trimmed.startsWith("ya29.")) return true
        val cookies = parseCookies(trimmed)
        val hasApiSid = cookies.containsKey("SAPISID") ||
            cookies.containsKey("__Secure-1PAPISID") ||
            cookies.containsKey("__Secure-3PAPISID")
        val hasSid = cookies.containsKey("SID") ||
            cookies.containsKey("__Secure-1PSID") ||
            cookies.containsKey("__Secure-3PSID")
        return hasApiSid && (hasSid || cookies.isNotEmpty())
    }

    public fun computeAuthorizationHeader(
        cookieHeader: String,
        origin: String = DEFAULT_ORIGIN,
        timestampSeconds: Long,
    ): String? {
        val trimmed = cookieHeader.trim()
        if (trimmed.isEmpty()) return null
        if (trimmed.lowercase().startsWith("bearer ")) return trimmed
        if (trimmed.startsWith("ya29.") && !trimmed.contains('=')) return "Bearer $trimmed"

        val normalizedOrigin = normalizeOrigin(origin)
        val cookies = parseCookies(trimmed)
        val schemes = mutableListOf<String>()

        cookies["SAPISID"]?.takeIf { it.isNotEmpty() }?.let { sapisid ->
            val digest = sha1Hex("$timestampSeconds $sapisid $normalizedOrigin")
            schemes.add("SAPISIDHASH ${timestampSeconds}_$digest")
        }
        cookies["__Secure-1PAPISID"]?.takeIf { it.isNotEmpty() }?.let { p1 ->
            val digest = sha1Hex("$timestampSeconds $p1 $normalizedOrigin")
            schemes.add("SAPISID1PHASH ${timestampSeconds}_$digest")
        }
        cookies["__Secure-3PAPISID"]?.takeIf { it.isNotEmpty() }?.let { p3 ->
            val digest = sha1Hex("$timestampSeconds $p3 $normalizedOrigin")
            schemes.add("SAPISID3PHASH ${timestampSeconds}_$digest")
        }
        return if (schemes.isEmpty()) null else schemes.joinToString(" ")
    }

    public fun buildApiServiceHeaders(
        cookieHeader: String,
        origin: String = DEFAULT_ORIGIN,
        authUser: String = "0",
        apiKey: String? = null,
        isStreaming: Boolean? = null,
        timestampSeconds: Long,
    ): Map<String, String> {
        val normalizedOrigin = normalizeOrigin(origin)
        val headers = linkedMapOf(
            "Content-Type" to "application/json+protobuf",
            "Accept" to "*/*",
            "User-Agent" to MOBILE_REMOTE_USER_AGENT,
            "X-User-Agent" to "grpc-web-javascript/0.1",
            "X-Goog-AuthUser" to authUser.ifEmpty { "0" },
            "Origin" to normalizedOrigin,
            "X-Origin" to normalizedOrigin,
            "Referer" to "$normalizedOrigin/",
            ANTIGRAVITY_TEST_HEADER_NAME to "true",
        )
        apiKey?.trim()?.takeIf { it.isNotEmpty() }?.let { resolvedKey ->
            headers["X-Goog-Api-Key"] = resolvedKey
        }
        if (isStreaming != true) {
            headers["X-Goog-Encode-Response-If-Executable"] = "base64"
        }
        if (isStreaming != null) {
            headers["x-is-streaming"] = if (isStreaming) "true" else "false"
        }
        var cleanedCookie = cookieHeader.trim()
        if (cleanedCookie.lowercase().startsWith("cookie:")) {
            cleanedCookie = cleanedCookie.drop("cookie:".length).trim()
        }
        if (cleanedCookie.isNotEmpty() && !cleanedCookie.lowercase().startsWith("bearer ") && !cleanedCookie.startsWith("ya29.")) {
            headers["Cookie"] = cleanedCookie
        }
        computeAuthorizationHeader(cleanedCookie, normalizedOrigin, timestampSeconds)?.let {
            headers["Authorization"] = it
        }
        return headers
    }

    public fun normalizeOrigin(rawOrigin: String): String {
        val trimmed = rawOrigin.trim()
        val schemeEnd = trimmed.indexOf("://")
        if (schemeEnd <= 0) return DEFAULT_ORIGIN
        val scheme = trimmed.substring(0, schemeEnd).lowercase()
        val afterScheme = trimmed.substring(schemeEnd + 3)
        val authority = afterScheme.substringBefore('/').substringBefore('?').substringBefore('#').lowercase()
        if (authority.isEmpty()) return DEFAULT_ORIGIN
        val hostPart = if (authority.startsWith("[")) authority else authority.substringBefore(':')
        val portSuffix = if (!authority.startsWith("[") && authority.contains(':')) {
            ":" + authority.substringAfter(':')
        } else {
            ""
        }
        val canonicalHost = when {
            hostPart == "antigravity.google" || hostPart == "www.antigravity.google" -> "antigravity.google.com"
            hostPart.endsWith(".antigravity.google") -> hostPart.removeSuffix(".antigravity.google") + ".antigravity.google.com"
            else -> hostPart
        }
        return "$scheme://$canonicalHost$portSuffix"
    }

    public fun sha1Hex(input: String): String =
        input.encodeUtf8().sha1().hex()
}

public data class DecodedProxyCommandResponse(
    public val payload: ByteArray,
    public val headers: Map<String, String>,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is DecodedProxyCommandResponse) return false
        return payload.contentEquals(other.payload) && headers == other.headers
    }

    override fun hashCode(): Int = 31 * payload.contentHashCode() + headers.hashCode()
}

/**
 * Encodes and decodes Google JSPB (`application/json+protobuf`) arrays for
 * `ListInstances`, `ProxyCommand`, and `StreamProxyCommand`.
 */
public object CloudRelayJspbCodec {
    private val json = Json { ignoreUnknownKeys = true }

    public fun decodeBase64Flexible(raw: String): ByteArray? {
        val cleaned = buildString(raw.length) {
            for (ch in raw) {
                when (ch) {
                    '-' -> append('+')
                    '_' -> append('/')
                    '\r', '\n', ' ', '\t' -> Unit
                    else -> append(ch)
                }
            }
        }
        if (cleaned.isEmpty()) return ByteArray(0)
        if (cleaned.length % 4 == 1) return null
        val padded = when (cleaned.length % 4) {
            0 -> cleaned
            2 -> "$cleaned=="
            3 -> "$cleaned="
            else -> return null
        }
        return decodeStandardBase64(padded)
    }

    public fun isPlausibleBase64Payload(raw: String): Boolean {
        val trimmed = raw.trim()
        if (trimmed.length < 2) return false
        var count = 0
        for (ch in trimmed) {
            when (ch) {
                in 'A'..'Z', in 'a'..'z', in '0'..'9', '+', '/', '-', '_', '=' -> count += 1
                '\r', '\n' -> continue
                else -> return false
            }
        }
        return count >= 2 && (count % 4) != 1
    }

    public fun unwrapGoogleRpcBody(
        rawData: ByteArray,
        responseHeaders: Map<String, String> = emptyMap(),
    ): ByteArray {
        var data = rawData
        val isBase64Header = responseHeaders.any { (k, v) ->
            val lk = k.lowercase()
            (lk == "x-goog-safety-encoding" || lk == "content-transfer-encoding") &&
                v.lowercase().contains("base64")
        }

        val initialText = data.decodeToString().trim()
        val firstChar = initialText.firstOrNull()
        if (firstChar != null && firstChar != '[' && firstChar != '{' && firstChar != ')') {
            val decoded = decodeBase64Flexible(initialText)
            if (decoded != null) {
                val decodedText = decoded.decodeToString().trim()
                if (isBase64Header || decodedText.startsWith("[") || decodedText.startsWith(")]}'")) {
                    data = decoded
                }
            }
        }

        val text = data.decodeToString().trim()
        if (text.startsWith(")]}'")) {
            return text.drop(4).trim().encodeToByteArray()
        }
        return data
    }

    public fun encodeListInstancesRequest(): ByteArray = "[]".encodeToByteArray()

    public fun decodeListInstancesResponse(
        rawData: ByteArray,
        responseHeaders: Map<String, String> = emptyMap(),
    ): List<RelayInstanceInfo> {
        val unwrapped = unwrapGoogleRpcBody(rawData, responseHeaders)
        if (unwrapped.isEmpty()) return emptyList()
        val rootElement = runCatching { json.parseToJsonElement(unwrapped.decodeToString()) }.getOrElse {
            throw AntigravityRpcError.DecodingError("Invalid JSON in ListInstancesResponse: ${it.message}")
        }
        val rawInstances: JsonArray = when (rootElement) {
            is JsonArray -> rootElement.firstOrNull() as? JsonArray ?: return emptyList()
            is JsonObject -> rootElement["instances"] as? JsonArray ?: return emptyList()
            else -> throw AntigravityRpcError.DecodingError("Expected JSPB array from ListInstances")
        }

        val preferredNameKeys = listOf(
            "deviceName", "device_name",
            "displayName", "display_name",
            "customName", "custom_name",
            "nickname", "hostname", "name",
        )
        val versionKeys = listOf("version", "appVersion", "app_version")

        fun firstNonEmptyString(obj: JsonObject?, keys: List<String>): String? {
            if (obj == null) return null
            for (k in keys) {
                val value = (obj[k] as? JsonPrimitive)?.contentOrNull?.trim()
                if (!value.isNullOrEmpty()) return value
            }
            return null
        }

        fun decodeStatus(el: JsonElement?): RelayInstanceStatus {
            val prim = el as? JsonPrimitive ?: return RelayInstanceStatus.UNKNOWN
            prim.intOrNull?.let { return RelayInstanceStatus.fromRawCode(it) }
            val upper = prim.contentOrNull?.uppercase().orEmpty()
            return when {
                upper.contains("CONNECTED") && !upper.contains("DISCONNECTED") -> RelayInstanceStatus.CONNECTED
                upper.contains("IDLE") -> RelayInstanceStatus.IDLE
                upper.contains("DISCONNECTED") || upper.contains("OFFLINE") -> RelayInstanceStatus.DISCONNECTED
                else -> RelayInstanceStatus.UNKNOWN
            }
        }

        fun decodeTimestampEpochMs(el: JsonElement?): Long? {
            when (el) {
                is JsonArray -> {
                    val secs = (el.getOrNull(0) as? JsonPrimitive)?.let { it.doubleOrNull ?: it.contentOrNull?.toDoubleOrNull() }
                    val nanos = (el.getOrNull(1) as? JsonPrimitive)?.let { it.doubleOrNull ?: it.contentOrNull?.toDoubleOrNull() } ?: 0.0
                    if (secs != null && secs > 0.0) {
                        return ((secs * 1000.0) + (nanos / 1_000_000.0)).toLong()
                    }
                }
                is JsonObject -> {
                    val secs = (el["seconds"] as? JsonPrimitive)?.let { it.doubleOrNull ?: it.contentOrNull?.toDoubleOrNull() }
                    val nanos = (el["nanos"] as? JsonPrimitive)?.let { it.doubleOrNull ?: it.contentOrNull?.toDoubleOrNull() } ?: 0.0
                    if (secs != null && secs > 0.0) {
                        return ((secs * 1000.0) + (nanos / 1_000_000.0)).toLong()
                    }
                }
                else -> Unit
            }
            return null
        }

        return rawInstances.mapNotNull { item ->
            when (item) {
                is JsonArray -> {
                    val uuid = (item.getOrNull(0) as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }
                        ?: return@mapNotNull null
                    val metadataVal = item.getOrNull(1)
                    val metadataArr = metadataVal as? JsonArray
                    val metadataObj = metadataVal as? JsonObject

                    val arrName = (metadataArr?.getOrNull(0) as? JsonPrimitive)?.contentOrNull?.trim()
                    val objName = firstNonEmptyString(metadataObj, preferredNameKeys)
                    val name = (objName ?: arrName)?.takeIf { it.isNotEmpty() } ?: uuid

                    val arrVersion = (metadataArr?.getOrNull(1) as? JsonPrimitive)?.contentOrNull?.trim()
                    val objVersion = firstNonEmptyString(metadataObj, versionKeys)
                    val version = objVersion ?: arrVersion ?: ""

                    val supportsChunking = when {
                        (metadataObj?.get("supportsChunking") as? JsonPrimitive)?.booleanOrNull != null ->
                            (metadataObj["supportsChunking"] as JsonPrimitive).booleanOrNull!!
                        (metadataObj?.get("supports_chunking") as? JsonPrimitive)?.booleanOrNull != null ->
                            (metadataObj["supports_chunking"] as JsonPrimitive).booleanOrNull!!
                        else -> when (val chunkEl = metadataArr?.getOrNull(2) as? JsonPrimitive) {
                            null -> true
                            else -> chunkEl.booleanOrNull ?: ((chunkEl.intOrNull ?: 1) != 0)
                        }
                    }

                    val status = if (item.size > 2) decodeStatus(item[2]) else RelayInstanceStatus.UNKNOWN
                    val updatedAtEpochMs = if (item.size > 3) decodeTimestampEpochMs(item[3]) else null

                    RelayInstanceInfo(
                        uuid = uuid,
                        name = name,
                        version = version,
                        supportsChunking = supportsChunking,
                        status = status,
                        updatedAtEpochMs = updatedAtEpochMs,
                    )
                }
                is JsonObject -> {
                    val uuid = firstNonEmptyString(item, listOf("uuid", "instanceId", "instance_id", "id"))
                        ?: return@mapNotNull null
                    val metadataObj = item["metadata"] as? JsonObject
                    val metadataArr = item["metadata"] as? JsonArray

                    val topName = firstNonEmptyString(item, preferredNameKeys)
                    val metaName = firstNonEmptyString(metadataObj, preferredNameKeys)
                    val arrName = (metadataArr?.getOrNull(0) as? JsonPrimitive)?.contentOrNull?.trim()
                    val name = (topName ?: metaName ?: arrName)?.takeIf { it.isNotEmpty() } ?: uuid

                    val version = firstNonEmptyString(item, versionKeys)
                        ?: firstNonEmptyString(metadataObj, versionKeys)
                        ?: (metadataArr?.getOrNull(1) as? JsonPrimitive)?.contentOrNull?.trim()
                        ?: ""

                    val supportsChunking = (item["supportsChunking"] as? JsonPrimitive)?.booleanOrNull
                        ?: (item["supports_chunking"] as? JsonPrimitive)?.booleanOrNull
                        ?: (metadataObj?.get("supportsChunking") as? JsonPrimitive)?.booleanOrNull
                        ?: (metadataObj?.get("supports_chunking") as? JsonPrimitive)?.booleanOrNull
                        ?: true

                    val status = decodeStatus(item["status"] ?: item["connectionStatus"] ?: item["connection_status"])
                    val updatedAtEpochMs = decodeTimestampEpochMs(item["updatedAt"] ?: item["updated_at"])

                    RelayInstanceInfo(
                        uuid = uuid,
                        name = name,
                        version = version,
                        supportsChunking = supportsChunking,
                        status = status,
                        updatedAtEpochMs = updatedAtEpochMs,
                    )
                }
                else -> null
            }
        }
    }

    public fun encodeProxyCommandRequest(
        targetInstanceUuid: String,
        rpcPath: String,
        payload: ByteArray,
        contentType: String = "application/json",
        isStreaming: Boolean = false,
        remoteUserAgent: String = SapisidHashGenerator.MOBILE_REMOTE_USER_AGENT,
    ): ByteArray {
        val base64Payload = if (payload.isEmpty()) "" else payload.toByteString().base64()
        val headerPairs = listOf(
            listOf("x-is-streaming", if (isStreaming) "true" else "false"),
            listOf("x-jetski-remote-control-user-agent", remoteUserAgent),
            listOf("content-type", contentType),
            listOf("connect-protocol-version", "1"),
        )
        val jspb = JsonArray(
            listOf(
                JsonPrimitive(targetInstanceUuid),
                JsonPrimitive(rpcPath),
                JsonPrimitive(base64Payload),
                JsonArray(headerPairs.map { pair -> JsonArray(pair.map { JsonPrimitive(it) }) }),
            )
        )
        return jspb.toString().encodeToByteArray()
    }

    public fun decompressPayloadIfNeeded(data: ByteArray): ByteArray {
        // 1. RFC 1952 GZIP (`0x1f 0x8b 0x08`)
        if (data.size >= 18 &&
            (data[0].toInt() and 0xFF) == 0x1F &&
            (data[1].toInt() and 0xFF) == 0x8B &&
            (data[2].toInt() and 0xFF) == 0x08
        ) {
            val flags = data[3].toInt() and 0xFF
            var headerEnd = 10
            val payloadLimit = data.size - 8
            if ((flags and 0x04) != 0) {
                if (headerEnd + 2 > payloadLimit) return data
                val xlen = (data[headerEnd].toInt() and 0xFF) or ((data[headerEnd + 1].toInt() and 0xFF) shl 8)
                headerEnd += 2 + xlen
            }
            if ((flags and 0x08) != 0) {
                while (headerEnd < payloadLimit && data[headerEnd].toInt() != 0) headerEnd += 1
                headerEnd += 1
            }
            if ((flags and 0x10) != 0) {
                while (headerEnd < payloadLimit && data[headerEnd].toInt() != 0) headerEnd += 1
                headerEnd += 1
            }
            if ((flags and 0x02) != 0) {
                headerEnd += 2
            }
            if (headerEnd <= payloadLimit) {
                decompressRawDeflate(data.copyOfRange(headerEnd, payloadLimit))?.let { return it }
            }
            return data
        }

        // 2. RFC 1950 ZLIB (`CM == 8`, `(CMF*256 + FLG) % 31 == 0`)
        if (data.size >= 6) {
            val b0 = data[0].toInt() and 0xFF
            val b1 = data[1].toInt() and 0xFF
            if ((b0 and 0x0F) == 0x08 && (b0 ushr 4) <= 7 && (((b0 shl 8) or b1) % 31) == 0) {
                val headerEnd = if ((b1 and 0x20) != 0) 6 else 2
                val payloadLimit = data.size - 4
                if (headerEnd <= payloadLimit) {
                    decompressRawDeflate(data.copyOfRange(headerEnd, payloadLimit))?.let { return it }
                }
            }
        }
        return data
    }

    public fun decodeProxyCommandResponse(
        rawData: ByteArray,
        responseHeaders: Map<String, String> = emptyMap(),
    ): DecodedProxyCommandResponse {
        val unwrapped = unwrapGoogleRpcBody(rawData, responseHeaders)
        if (unwrapped.isEmpty()) return DecodedProxyCommandResponse(ByteArray(0), emptyMap())

        val parsedRoot = runCatching { json.parseToJsonElement(unwrapped.decodeToString()) }.getOrNull()
        if (parsedRoot != null) {
            val rootArray = parsedRoot as? JsonArray
                ?: throw AntigravityRpcError.DecodingError("Expected JSPB array in ProxyCommandResponse")
            if (rootArray.firstOrNull() is JsonNull && rootArray.size >= 2) {
                throw AntigravityRpcError.HttpError(502, unwrapped.decodeToString())
            }
            val firstString = (rootArray.firstOrNull() as? JsonPrimitive)?.takeIf { it.isString }?.content
            if (firstString != null) {
                val decoded = decodeBase64Flexible(firstString)
                    ?: throw AntigravityRpcError.DecodingError("Invalid base64 payload in ProxyCommandResponse")
                val innerHeaders = parseInnerHeaderPairs(rootArray.getOrNull(1))
                return DecodedProxyCommandResponse(decompressPayloadIfNeeded(decoded), innerHeaders)
            }

            val nestedFirst = rootArray.firstOrNull() as? JsonArray
            val innerHeaders = parseInnerHeaderPairs(nestedFirst?.getOrNull(1))
            val chunks = extractPayloadsFromJspbArray(rootArray)
            return DecodedProxyCommandResponse(decompressPayloadIfNeeded(concatChunks(chunks)), innerHeaders)
        }

        val streamParser = CloudRelayJspbStreamParser()
        val streamedChunks = streamParser.feed(unwrapped)
        if (streamedChunks.isEmpty()) {
            throw AntigravityRpcError.DecodingError("Expected JSPB array in ProxyCommandResponse")
        }
        return DecodedProxyCommandResponse(decompressPayloadIfNeeded(concatChunks(streamedChunks)), emptyMap())
    }

    public fun extractStreamProxyPayloads(rawText: String): List<ByteArray> {
        val cleaned = rawText.trim()
        if (cleaned.isEmpty()) return emptyList()
        val stripped = if (cleaned.startsWith(")]}'")) cleaned.drop(4).trim() else cleaned
        val parsed = runCatching { json.parseToJsonElement(stripped) }.getOrNull()
        if (parsed is JsonArray) {
            return extractPayloadsFromJspbArray(parsed)
        }
        val decodedB64 = decodeBase64Flexible(stripped)
        if (decodedB64 != null) {
            val text = decodedB64.decodeToString()
            if (text != stripped) return extractStreamProxyPayloads(text)
        }
        return emptyList()
    }

    private fun parseInnerHeaderPairs(element: JsonElement?): Map<String, String> {
        val pairs = element as? JsonArray ?: return emptyMap()
        val headers = linkedMapOf<String, String>()
        for (pairEl in pairs) {
            val pair = pairEl as? JsonArray ?: continue
            val k = (pair.getOrNull(0) as? JsonPrimitive)?.contentOrNull?.lowercase()
            val v = (pair.getOrNull(1) as? JsonPrimitive)?.contentOrNull
            if (k != null && v != null) headers[k] = v
        }
        return headers
    }

    private fun extractPayloadsFromJspbArray(arr: JsonArray): List<ByteArray> {
        val payloads = mutableListOf<ByteArray>()
        fun walk(node: JsonArray) {
            val firstStr = (node.firstOrNull() as? JsonPrimitive)?.takeIf { it.isString }?.content
            if (firstStr != null && node.size <= 3 &&
                (node.size == 1 || node[1] is JsonArray || node[1] is JsonNull)
            ) {
                if (firstStr.isNotEmpty()) {
                    val bytes = decodeBase64Flexible(firstStr)
                    if (bytes != null && bytes.isNotEmpty()) payloads.add(bytes)
                }
                return
            }
            for (child in node) {
                if (child is JsonArray) walk(child)
            }
        }
        walk(arr)
        return payloads
    }

    private fun concatChunks(chunks: List<ByteArray>): ByteArray {
        val total = chunks.sumOf { it.size }
        val out = ByteArray(total)
        var pos = 0
        for (chunk in chunks) {
            chunk.copyInto(out, pos)
            pos += chunk.size
        }
        return out
    }
}

/**
 * Incremental Base64 / Base64URL byte decoder for streaming Google Boq responses.
 */
public class StreamingBase64Decoder {
    private val quartet = ByteArray(4)
    private var quartetSize = 0

    public fun feedByte(byte: Byte): ByteArray? {
        val c = byte.toInt() and 0xFF
        val normalized: Byte = when (c) {
            in 'A'.code..'Z'.code,
            in 'a'.code..'z'.code,
            in '0'.code..'9'.code,
            '+'.code, '/'.code, '='.code -> byte
            '-'.code -> '+'.code.toByte()
            '_'.code -> '/'.code.toByte()
            else -> return null
        }
        quartet[quartetSize++] = normalized
        if (quartetSize < 4) return null
        val chunk = quartet.decodeToString()
        quartetSize = 0
        return decodeStandardBase64(chunk)
    }

    public fun feed(bytes: ByteArray): ByteArray {
        val out = ArrayList<Byte>(bytes.size)
        for (b in bytes) {
            feedByte(b)?.forEach { out.add(it) }
        }
        return out.toByteArray()
    }

    public fun flush(): ByteArray {
        if (quartetSize < 2) {
            quartetSize = 0
            return ByteArray(0)
        }
        while (quartetSize < 4) {
            quartet[quartetSize++] = '='.code.toByte()
        }
        val chunk = quartet.decodeToString()
        quartetSize = 0
        return decodeStandardBase64(chunk) ?: ByteArray(0)
    }
}

/**
 * Incremental O(1)-memory byte-level parser for Google Boq `StreamProxyCommand` JSPB streams.
 */
public class CloudRelayJspbStreamParser {
    private enum class ElementKind { STRING, ARRAY, NULL, OTHER }

    private class ArrayFrame {
        var elementCount: Int = 0
        var firstElement: ElementKind? = null
        var secondElement: ElementKind? = null
        var firstString: String? = null
        var firstInt: Int? = null
        var secondString: String? = null

        fun append(kind: ElementKind, stringValue: String? = null, intValue: Int? = null) {
            if (elementCount == 0) {
                firstElement = kind
                firstString = stringValue
                firstInt = intValue
            } else if (elementCount == 1) {
                secondElement = kind
                secondString = stringValue
            }
            elementCount += 1
        }
    }

    private val stack = ArrayList<ArrayFrame>()
    private var objectDepth = 0
    private var inString = false
    private var isEscaped = false
    private var stringHasEscape = false
    private var captureCurrentString = false
    private val stringBytes = ArrayList<Byte>(128)
    private val tokenBytes = ArrayList<Byte>(32)

    public var lastErrorTrailer: String? = null
        private set

    public fun feed(bytes: ByteArray): List<ByteArray> {
        val emitted = mutableListOf<ByteArray>()
        for (b in bytes) {
            feedByte(b)?.let { emitted.addAll(it) }
        }
        return emitted
    }

    private fun flushPendingToken() {
        if (tokenBytes.isEmpty()) return
        val token = tokenBytes.toByteArray().decodeToString()
        tokenBytes.clear()
        val top = stack.lastOrNull() ?: return
        when {
            token == "null" -> top.append(ElementKind.NULL)
            token.toIntOrNull() != null -> top.append(ElementKind.OTHER, intValue = token.toInt())
            else -> top.append(ElementKind.OTHER)
        }
    }

    public fun feedByte(byte: Byte): List<ByteArray>? {
        val c = byte.toInt() and 0xFF
        if (inString) {
            if (captureCurrentString) stringBytes.add(byte)
            if (isEscaped) {
                isEscaped = false
            } else if (c == '\\'.code) {
                isEscaped = true
                if (captureCurrentString) stringHasEscape = true
            } else if (c == '"'.code) {
                inString = false
                if (objectDepth == 0 && stack.isNotEmpty()) {
                    val decoded: String? = if (captureCurrentString && stringBytes.size >= 2) {
                        val rawJson = stringBytes.toByteArray().decodeToString()
                        if (!stringHasEscape) {
                            rawJson.substring(1, rawJson.length - 1)
                        } else {
                            runCatching { Json.decodeFromString<String>(rawJson) }
                                .getOrElse { rawJson.substring(1, rawJson.length - 1) }
                        }
                    } else {
                        null
                    }
                    stringBytes.clear()
                    stringHasEscape = false
                    captureCurrentString = false
                    stack.last().append(ElementKind.STRING, stringValue = decoded)
                }
            }
            return null
        }

        if (objectDepth > 0) {
            when (c) {
                '"'.code -> {
                    inString = true
                    isEscaped = false
                    captureCurrentString = false
                }
                '{'.code -> objectDepth += 1
                '}'.code -> {
                    objectDepth -= 1
                    if (objectDepth == 0 && stack.isNotEmpty()) {
                        stack.last().append(ElementKind.OTHER)
                    }
                }
            }
            return null
        }

        if (stack.isEmpty()) {
            if (c == '['.code) {
                stack.add(ArrayFrame())
                tokenBytes.clear()
            }
            return null
        }

        return when (c) {
            '"'.code -> {
                flushPendingToken()
                inString = true
                isEscaped = false
                stringHasEscape = false
                captureCurrentString = stack.last().elementCount <= 1
                stringBytes.clear()
                if (captureCurrentString) stringBytes.add(byte)
                null
            }
            '{'.code -> {
                flushPendingToken()
                objectDepth = 1
                null
            }
            '['.code -> {
                flushPendingToken()
                stack.add(ArrayFrame())
                null
            }
            ','.code, ' '.code, '\t'.code, '\n'.code, '\r'.code -> {
                flushPendingToken()
                null
            }
            ']'.code -> {
                flushPendingToken()
                val closed = stack.removeAt(stack.lastIndex)
                val insideErrorTrailer = stack.any { it.firstElement == ElementKind.NULL || it.firstElement == ElementKind.OTHER }
                if (stack.isNotEmpty()) {
                    stack.last().append(ElementKind.ARRAY)
                }
                if (insideErrorTrailer) {
                    val code = closed.firstInt
                    val msg = closed.secondString
                    if (code != null && code != 0 && !msg.isNullOrEmpty()) {
                        lastErrorTrailer = "Boq status $code: $msg"
                    }
                    return null
                }
                if (closed.firstElement == ElementKind.STRING &&
                    closed.elementCount in 1..3 &&
                    (closed.elementCount == 1 || closed.secondElement == ElementKind.ARRAY || closed.secondElement == ElementKind.NULL)
                ) {
                    val b64 = closed.firstString
                    if (b64 != null && CloudRelayJspbCodec.isPlausibleBase64Payload(b64)) {
                        val decoded = CloudRelayJspbCodec.decodeBase64Flexible(b64)
                        if (decoded != null && decoded.isNotEmpty()) return listOf(decoded)
                    }
                }
                null
            }
            else -> {
                tokenBytes.add(byte)
                null
            }
        }
    }
}

private fun decodeStandardBase64(padded: String): ByteArray? {
    if (padded.isEmpty()) return ByteArray(0)
    if (padded.length % 4 != 0) return null
    val out = ByteArray((padded.length / 4) * 3)
    var outIdx = 0
    var i = 0
    while (i < padded.length) {
        val c0 = b64Val(padded[i]) ?: return null
        val c1 = b64Val(padded[i + 1]) ?: return null
        val p2 = padded[i + 2]
        val p3 = padded[i + 3]
        val c2 = if (p2 == '=') -1 else (b64Val(p2) ?: return null)
        val c3 = if (p3 == '=') -1 else (b64Val(p3) ?: return null)
        out[outIdx++] = ((c0 shl 2) or (c1 ushr 4)).toByte()
        if (c2 >= 0) {
            out[outIdx++] = (((c1 and 0x0F) shl 4) or (c2 ushr 2)).toByte()
            if (c3 >= 0) {
                out[outIdx++] = (((c2 and 0x03) shl 6) or c3).toByte()
            }
        }
        i += 4
    }
    return out.copyOf(outIdx)
}

private fun b64Val(ch: Char): Int? = when (ch) {
    in 'A'..'Z' -> ch - 'A'
    in 'a'..'z' -> ch - 'a' + 26
    in '0'..'9' -> ch - '0' + 52
    '+' -> 62
    '/' -> 63
    else -> null
}
