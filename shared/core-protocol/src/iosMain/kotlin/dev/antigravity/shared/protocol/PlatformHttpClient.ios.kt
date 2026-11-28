@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package dev.antigravity.shared.protocol

import io.ktor.client.HttpClient
import io.ktor.client.engine.darwin.Darwin
import kotlinx.cinterop.readBytes
import kotlinx.cinterop.reinterpret
import okio.ByteString.Companion.toByteString
import platform.CoreFoundation.CFArrayGetCount
import platform.CoreFoundation.CFArrayGetValueAtIndex
import platform.CoreFoundation.CFDataGetBytePtr
import platform.CoreFoundation.CFDataGetLength
import platform.CoreFoundation.CFRelease
import platform.Foundation.NSDate
import platform.Foundation.NSURLAuthenticationMethodServerTrust
import platform.Foundation.NSURLCredential
import platform.Foundation.NSURLRequestReloadIgnoringLocalCacheData
import platform.Foundation.NSURLSessionAuthChallengeCancelAuthenticationChallenge
import platform.Foundation.NSURLSessionAuthChallengePerformDefaultHandling
import platform.Foundation.NSURLSessionAuthChallengeUseCredential
import platform.Foundation.credentialForTrust
import platform.Foundation.serverTrust
import platform.Foundation.setHTTPShouldHandleCookies
import platform.Foundation.timeIntervalSince1970
import platform.Security.SecCertificateCopyData
import platform.Security.SecCertificateRef
import platform.Security.SecTrustCopyCertificateChain

public actual fun currentTimeMillis(): Long =
    (NSDate().timeIntervalSince1970 * 1000.0).toLong()

public actual fun platformTransportEngineName(): String = "KMP-Darwin"

internal actual fun logProtocolDiagnostic(message: String) {
    // Use pure Kotlin/Native stdout println (captured directly in Xcode Console) instead of
    // C-variadic NSLog("%@", ...), which marshals Kotlin String varargs as `const char *`
    // rather than `NSString *` and triggers EXC_BAD_ACCESS / SIGSEGV on iOS.
    println("[CloudRelay] $message")
}

internal actual fun createPlatformHttpClient(
    endpointHost: String,
    config: TlsEngineConfig,
): HttpClient {
    val pinnedHex = config.normalizedPinnedHex
    val isLocalHost = LocalHostClassifier.isPrivateOrTailscaleHost(endpointHost)

    return HttpClient(Darwin) {
        expectSuccess = false
        engine {
            configureSession {
                timeoutIntervalForRequest = config.requestTimeoutMs / 1000.0
                timeoutIntervalForResource = maxOf(25.0, (config.requestTimeoutMs * 2) / 1000.0)
                HTTPShouldSetCookies = false
                HTTPCookieStorage = null
                URLCache = null
                if (config.bypassProxyForLocalHosts && isLocalHost) {
                    connectionProxyDictionary = emptyMap<Any?, Any>()
                }
            }
            configureRequest {
                setHTTPShouldHandleCookies(false)
                setCachePolicy(NSURLRequestReloadIgnoringLocalCacheData)
                setAssumesHTTP3Capable(false)
            }
            handleChallenge { _, _, challenge, completionHandler ->
                val space = challenge.protectionSpace
                if (space.authenticationMethod != NSURLAuthenticationMethodServerTrust) {
                    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, null)
                    return@handleChallenge
                }
                val serverTrust = space.serverTrust
                if (serverTrust == null) {
                    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, null)
                    return@handleChallenge
                }

                if (pinnedHex != null) {
                    val actualHex = extractLeafCertSha256Hex(serverTrust)
                    if (actualHex != null && LocalHostClassifier.matchesSha256Pin(actualHex, pinnedHex)) {
                        completionHandler(
                            NSURLSessionAuthChallengeUseCredential,
                            NSURLCredential.credentialForTrust(serverTrust),
                        )
                    } else {
                        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, null)
                    }
                    return@handleChallenge
                }

                val challengeHost = space.host
                if (config.allowLocalSelfSignedTofu && LocalHostClassifier.isPrivateOrTailscaleHost(challengeHost)) {
                    completionHandler(
                        NSURLSessionAuthChallengeUseCredential,
                        NSURLCredential.credentialForTrust(serverTrust),
                    )
                    return@handleChallenge
                }

                completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, null)
            }
        }
    }
}

private fun extractLeafCertSha256Hex(serverTrust: platform.Security.SecTrustRef): String? {
    val chain = SecTrustCopyCertificateChain(serverTrust) ?: return null
    return try {
        if (CFArrayGetCount(chain) <= 0L) return null
        val certPtr = CFArrayGetValueAtIndex(chain, 0L) ?: return null
        val certRef: SecCertificateRef = certPtr.reinterpret()
        val cfData = SecCertificateCopyData(certRef) ?: return null
        try {
            val length = CFDataGetLength(cfData).toInt()
            val ptr = CFDataGetBytePtr(cfData) ?: return null
            if (length <= 0) return null
            val bytes = ptr.readBytes(length)
            bytes.toByteString().sha256().hex()
        } finally {
            CFRelease(cfData)
        }
    } finally {
        CFRelease(chain)
    }
}
