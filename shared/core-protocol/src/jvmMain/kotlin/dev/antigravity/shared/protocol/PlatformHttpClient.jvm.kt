package dev.antigravity.shared.protocol

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import okio.ByteString.Companion.toByteString
import java.net.Proxy
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

public actual fun currentTimeMillis(): Long = System.currentTimeMillis()

internal actual fun createPlatformHttpClient(
    endpointHost: String,
    config: TlsEngineConfig,
): HttpClient {
    val pinnedHex = config.normalizedPinnedHex
    val isLocalHost = LocalHostClassifier.isPrivateOrTailscaleHost(endpointHost)

    return HttpClient(OkHttp) {
        expectSuccess = false
        engine {
            config {
                connectTimeout(config.connectTimeoutMs, TimeUnit.MILLISECONDS)
                readTimeout(config.requestTimeoutMs, TimeUnit.MILLISECONDS)
                writeTimeout(config.requestTimeoutMs, TimeUnit.MILLISECONDS)
                if (config.bypassProxyForLocalHosts && isLocalHost) {
                    proxy(Proxy.NO_PROXY)
                }

                if (pinnedHex != null || (config.allowLocalSelfSignedTofu && isLocalHost)) {
                    val defaultTm = defaultSystemTrustManager()
                    val customTm = AntigravityX509TrustManager(
                        delegate = defaultTm,
                        pinnedHex = pinnedHex,
                        allowLocalTofu = config.allowLocalSelfSignedTofu && isLocalHost,
                    )
                    val sslContext = SSLContext.getInstance("TLS").apply {
                        init(null, arrayOf(customTm), SecureRandom())
                    }
                    sslSocketFactory(sslContext.socketFactory, customTm)
                    hostnameVerifier(
                        HostnameVerifier { hostname, session ->
                            if (pinnedHex != null ||
                                (config.allowLocalSelfSignedTofu && LocalHostClassifier.isPrivateOrTailscaleHost(hostname))
                            ) {
                                true
                            } else {
                                okhttp3.internal.tls.OkHostnameVerifier.verify(hostname, session)
                            }
                        }
                    )
                }
            }
        }
    }
}

private fun defaultSystemTrustManager(): X509TrustManager {
    val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
    tmf.init(null as KeyStore?)
    return tmf.trustManagers.filterIsInstance<X509TrustManager>().first()
}

private class AntigravityX509TrustManager(
    private val delegate: X509TrustManager,
    private val pinnedHex: String?,
    private val allowLocalTofu: Boolean,
) : X509TrustManager {
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        delegate.checkClientTrusted(chain, authType)
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        val leaf = chain?.firstOrNull()
        if (pinnedHex != null) {
            if (leaf == null) throw CertificateException("Missing server certificate for SHA-256 pin verification")
            val actualHex = leaf.encoded.toByteString().sha256().hex()
            if (!LocalHostClassifier.matchesSha256Pin(actualHex, pinnedHex)) {
                throw CertificateException("TLS SHA-256 pin mismatch: actual=$actualHex expected=$pinnedHex")
            }
            return
        }
        if (allowLocalTofu) {
            return
        }
        delegate.checkServerTrusted(chain, authType)
    }

    override fun getAcceptedIssuers(): Array<X509Certificate> = delegate.acceptedIssuers
}
