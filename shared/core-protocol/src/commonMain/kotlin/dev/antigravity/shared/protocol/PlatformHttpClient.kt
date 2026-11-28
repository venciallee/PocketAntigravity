package dev.antigravity.shared.protocol

import io.ktor.client.HttpClient

/**
 * TLS certificate pinning & local self-signed TOFU configuration shared by
 * Ktor OkHttp (Android/JVM) and Ktor Darwin (iOS).
 */
public data class TlsEngineConfig(
    public val pinnedFingerprintSha256: String? = null,
    public val allowLocalSelfSignedTofu: Boolean = true,
    public val bypassProxyForLocalHosts: Boolean = true,
    public val requestTimeoutMs: Long = 20_000L,
    public val connectTimeoutMs: Long = 10_000L,
) {
    public val normalizedPinnedHex: String?
        get() = pinnedFingerprintSha256
            ?.replace("SHA256:", "", ignoreCase = true)
            ?.replace(":", "")
            ?.trim()
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }
}

/**
 * Shared private LAN / loopback / Tailscale host classifier used by both OkHttp and Darwin TLS handlers.
 */
public object LocalHostClassifier {
    public fun isPrivateOrTailscaleHost(rawHost: String): Boolean {
        val host = rawHost.trim().lowercase()
        return host == "localhost" ||
            host == "127.0.0.1" ||
            host == "::1" ||
            host == "[::1]" ||
            host.endsWith(".local") ||
            host.endsWith(".ts.net") ||
            host.startsWith("192.168.") ||
            host.startsWith("10.") ||
            host.startsWith("100.") ||
            host.startsWith("172.")
    }

    public fun matchesSha256Pin(actualHex: String, expectedHex: String): Boolean {
        val a = actualHex.lowercase()
        val e = expectedHex.lowercase()
        return a.startsWith(e) || e.startsWith(a)
    }
}

public expect fun currentTimeMillis(): Long

public expect fun platformTransportEngineName(): String

internal expect fun logProtocolDiagnostic(message: String)

internal expect fun createPlatformHttpClient(
    endpointHost: String,
    config: TlsEngineConfig,
): HttpClient
