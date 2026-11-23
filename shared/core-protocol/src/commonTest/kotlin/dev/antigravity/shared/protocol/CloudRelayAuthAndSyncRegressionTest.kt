package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class CloudRelayAuthAndSyncRegressionTest {

    @Test
    fun testDiscoverRelayApiKeyFromBootstrapScriptAndRetryOnInvalidKey() = runTest {
        withContext(Dispatchers.Default) {
            val discoveredKey = "AI" + "zaSyA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q"
            val staleKey = "AI" + "zaSySTALEKEY0000000000000000000000000"
            var listInstancesCalls = 0
            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path == "/r/0f5819ac-9308-40d8-a308-98b55122c533-v2" -> {
                        respond(
                            content = """<html><head><script src="/_/boq/antigravity_main.js"></script></head></html>""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "text/html"),
                        )
                    }
                    path == "/_/boq/antigravity_main.js" -> {
                        respond(
                            content = """window.__cfg = {"apiKey": "$discoveredKey"};""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/javascript"),
                        )
                    }
                    path.endsWith("/ListInstances") -> {
                        listInstancesCalls += 1
                        val sentKey = request.headers["X-Goog-Api-Key"]
                        if (sentKey != discoveredKey) {
                            respond(
                                content = """{"error":{"message":"API_KEY_INVALID: x-goog-api-key rejected"}}""",
                                status = HttpStatusCode.Forbidden,
                                headers = headersOf(HttpHeaders.ContentType, "application/json"),
                            )
                        } else {
                            respond(
                                content = """[[["0f5819ac-9308-40d8-a308-98b55122c533-v2",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = "0f5819ac-9308-40d8-a308-98b55122c533-v2",
                hostname = "Antigravity Desktop",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/0f5819ac-9308-40d8-a308-98b55122c533-v2",
            )
            // Seed a stale key to verify 403 API_KEY_INVALID triggers bootstrap JS rediscovery + automatic retry.
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = staleKey,
                httpClientOverride = HttpClient(engine),
            )

            val instances = client.listRelayInstances(authUserOverride = "0")
            assertEquals(2, listInstancesCalls, "ListInstances must retry once after refreshing invalid API key")
            assertEquals(1, instances.size)
            assertEquals("MacBook Pro", instances.first().name)
            assertEquals(discoveredKey, client.currentRelayApiKey())
        }
    }

    @Test
    fun testResolveCloudRelayInstanceThrowsUnauthorizedInsteadOfFabricatingUuidHost() = runTest {
        withContext(Dispatchers.Default) {
            val rawUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            val engine = MockEngine { request ->
                if (request.url.encodedPath.endsWith("/ListInstances")) {
                    respond(
                        content = """{"error":{"code":401,"message":"Google session expired"}}""",
                        status = HttpStatusCode.Unauthorized,
                        headers = headersOf(HttpHeaders.ContentType, "application/json"),
                    )
                } else {
                    respond("<html></html>", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "text/html"))
                }
            }

            val host = RemoteHostInstance(
                instanceId = rawUuid,
                hostname = rawUuid,
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/$rawUuid",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=expired_cookie; SID=expired_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            assertFailsWith<AntigravityRpcError.Unauthorized> {
                client.resolveCloudRelayInstance(preferredIdentifier = rawUuid, allowCrossHostFallback = true)
            }
        }
    }

    @Test
    fun testFetchFederatedPropagatesUnauthorizedInsteadOfReturningEmpty() = runTest {
        withContext(Dispatchers.Default) {
            val rawUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = """[[["$rawUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") || path.endsWith("/StreamProxyCommand") -> {
                        respond(
                            content = """{"error":{"code":401,"message":"Session expired"}}""",
                            status = HttpStatusCode.Unauthorized,
                            headers = headersOf(HttpHeaders.ContentType, "application/json"),
                        )
                    }
                    else -> respond("", HttpStatusCode.OK)
                }
            }

            val host = RemoteHostInstance(
                instanceId = rawUuid,
                hostname = "MacBook Pro",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/$rawUuid",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=expired_cookie; SID=expired_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            assertFailsWith<AntigravityRpcError.Unauthorized> {
                client.fetchFederatedWorkspacesAndSummaries(skipRelayListRefresh = false)
            }
        }
    }

    @Test
    fun testDecodeListInstancesSupportsProtojsonObjectAndDeviceNameKeys() {
        val protojson = """
            {
              "instances": [
                {
                  "uuid": "uuid-mac-studio-v2",
                  "metadata": {
                    "deviceName": "Mac Studio M4",
                    "appVersion": "2.33.0",
                    "supportsChunking": true
                  },
                  "status": "CONNECTED"
                }
              ]
            }
        """.trimIndent().encodeToByteArray()

        val decoded = CloudRelayJspbCodec.decodeListInstancesResponse(protojson)
        assertEquals(1, decoded.size)
        assertEquals("uuid-mac-studio-v2", decoded[0].uuid)
        assertEquals("Mac Studio M4", decoded[0].name)
        assertEquals("2.33.0", decoded[0].version)
        assertEquals(RelayInstanceStatus.CONNECTED, decoded[0].status)
        assertTrue(decoded[0].supportsChunking)
    }

    @Test
    fun testRotatesPastBlockedOneGoogleApiKeyToModulePreloadApiServiceKey() = runTest {
        withContext(Dispatchers.Default) {
            val blockedOgsKey = "AI" + "zaSyOGSBLOCKED00000000000000000000000"
            val validApiServiceKey = "AI" + "zaSyREALAPISERVICE1111111111111111111"
            val attemptedKeys = mutableListOf<String?>()

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path == "/r/0f5819ac-9308-40d8-a308-98b55122c533-v2" -> {
                        respond(
                            content = """
                                <html><head>
                                <script>window.WIZ_global_data = {"ogsKey":"$blockedOgsKey"};</script>
                                <link rel="modulepreload" href="/_/boq/antigravity_app.mjs">
                                </head></html>
                            """.trimIndent(),
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "text/html"),
                        )
                    }
                    path == "/_/boq/antigravity_app.mjs" -> {
                        respond(
                            content = """export const cfg = {"x-goog-api-key": "$validApiServiceKey"};""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/javascript"),
                        )
                    }
                    path.endsWith("/ListInstances") -> {
                        val sentKey = request.headers["X-Goog-Api-Key"]
                        attemptedKeys.add(sentKey)
                        if (sentKey == validApiServiceKey) {
                            respond(
                                content = """[[["0f5819ac-9308-40d8-a308-98b55122c533-v2",["Studio Mac","2.33.0",true],1,[1740000000,0]]],5]""",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        } else {
                            respond(
                                content = """[7,"Requests to this API devtools_jetski_boq_api_proto.ApiService method ListInstances are blocked."]""",
                                status = HttpStatusCode.Forbidden,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = "0f5819ac-9308-40d8-a308-98b55122c533-v2",
                hostname = "Antigravity Desktop",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/0f5819ac-9308-40d8-a308-98b55122c533-v2",
            )
            // Start with no explicit key: HTML returns blockedOgsKey first, then modulepreload JS provides validApiServiceKey.
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = null,
                httpClientOverride = HttpClient(engine),
            )

            val instances = client.listRelayInstances(authUserOverride = "0")
            assertEquals(1, instances.size)
            assertEquals("Studio Mac", instances[0].name)
            assertEquals(validApiServiceKey, client.currentRelayApiKey())
            assertTrue(attemptedKeys.contains(blockedOgsKey))
            assertTrue(attemptedKeys.contains(validApiServiceKey))
        }
    }

    @Test
    fun testUnauthorizedDiagnosticIncludesHttpStatusAndSafeCookieSummaryWithoutLeakingSecretValues() = runTest {
        withContext(Dispatchers.Default) {
            val secretCookieVal = "SUPER_SECRET_COOKIE_VALUE_DO_NOT_LEAK"
            val engine = MockEngine { request ->
                if (request.url.encodedPath.endsWith("/ListInstances")) {
                    respond(
                        content = """{"error":{"code":401,"message":"UNAUTHENTICATED: SAPISIDHASH mismatch"}}""",
                        status = HttpStatusCode.Unauthorized,
                        headers = headersOf(HttpHeaders.ContentType, "application/json"),
                    )
                } else {
                    respond("<html></html>", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "text/html"))
                }
            }

            val host = RemoteHostInstance(
                instanceId = "0f5819ac-9308-40d8-a308-98b55122c533-v2",
                hostname = "Mac",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/0f5819ac-9308-40d8-a308-98b55122c533-v2",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=$secretCookieVal; SID=sid_val; OSID=osid_val",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val err = assertFailsWith<AntigravityRpcError.Unauthorized> {
                client.listRelayInstances(authUserOverride = "0")
            }
            assertTrue(err.detail.contains("HTTP 401"), "Expected HTTP 401 in diagnostic: ${err.detail}")
            assertTrue(err.detail.contains("SAPISID"), "Expected cookie key name in diagnostic: ${err.detail}")
            assertTrue(err.detail.contains("OSID"), "Expected OSID cookie key name in diagnostic: ${err.detail}")
            assertTrue(err.detail.contains("SAPISIDHASH mismatch"), "Expected server error snippet: ${err.detail}")
            assertTrue(!err.detail.contains(secretCookieVal), "Diagnostic must NEVER leak raw cookie values")
        }
    }

    @Test
    fun testOriginApiKeyDiscoveryRunsAtMostOnceAcrossAuthUsers() = runTest {
        withContext(Dispatchers.Default) {
            val badKey1 = "AI" + "zaSyBADKEYONE000000000000000000000000"
            val badKey2 = "AI" + "zaSyBADKEYTWO000000000000000000000000"
            var htmlFetchCount = 0
            var jsFetchCount = 0
            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path == "/r/0f5819ac-9308-40d8-a308-98b55122c533-v2" || path == "/" -> {
                        htmlFetchCount += 1
                        respond(
                            content = """<html><script>window.__k="$badKey1";</script><script src="/_/boq/app.js"></script></html>""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "text/html"),
                        )
                    }
                    path == "/_/boq/app.js" -> {
                        jsFetchCount += 1
                        respond(
                            content = """const k = "$badKey2";""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/javascript"),
                        )
                    }
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = """{"error":{"code":403,"message":"API_KEY_SERVICE_BLOCKED: Requests to this API are blocked"}}""",
                            status = HttpStatusCode.Forbidden,
                            headers = headersOf(HttpHeaders.ContentType, "application/json"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = "0f5819ac-9308-40d8-a308-98b55122c533-v2",
                hostname = "Mac",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/0f5819ac-9308-40d8-a308-98b55122c533-v2",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = null,
                httpClientOverride = HttpClient(engine),
            )

            assertFailsWith<AntigravityRpcError.Unauthorized> {
                client.resolveCloudRelayInstance(preferredIdentifier = host.instanceId, allowCrossHostFallback = true)
            }
            assertEquals(1, htmlFetchCount, "Origin HTML must be crawled at most once per client even across 5 authUsers")
            assertEquals(1, jsFetchCount, "Origin bootstrap JS must be crawled at most once per client")
        }
    }

    @Test
    fun testVerifyConnectionSkipsJetboxStreamAndUsesUnencodedRpcPath() = runTest {
        withContext(Dispatchers.Default) {
            val validKey = "AI" + "zaSyHANDSHAKEKEY000000000000000000000"
            val rawUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            var streamCalls = 0
            val observedUrls = mutableListOf<String>()
            val engine = MockEngine { request ->
                val fullUrl = request.url.toString()
                observedUrls.add(fullUrl)
                val path = request.url.encodedPath
                when {
                    path.endsWith("/StreamProxyCommand") -> {
                        streamCalls += 1
                        respond("", HttpStatusCode.OK)
                    }
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = """[[["$rawUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val b64Json = okio.ByteString.Companion.run {
                            """{"workspaces":[],"trajectorySummaries":{}}""".encodeToByteArray().let { bytes ->
                                okio.ByteString.of(*bytes).base64()
                            }
                        }
                        respond(
                            content = """["$b64Json",[["content-type","application/json"]]]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = rawUuid,
                hostname = "Antigravity Desktop",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/$rawUuid",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                httpClientOverride = HttpClient(engine),
            )

            val handshake = client.verifyConnection(allowCrossHostFallback = true)
            assertEquals("MacBook Pro", handshake.resolvedHostname)
            assertEquals(rawUuid, handshake.resolvedInstanceUuid)
            assertEquals(0, streamCalls, "verifyConnection must not open/cancel StreamProxyCommand during handshake")
            assertTrue(
                observedUrls.any { it.contains("/\$rpc/devtools_jetski_boq_api_proto.ApiService/ListInstances") },
                "ListInstances must preserve unencoded /\$rpc/ path; saw $observedUrls",
            )
            assertTrue(
                observedUrls.any { it.contains("/\$rpc/devtools_jetski_boq_api_proto.ApiService/ProxyCommand?\$unique=") },
                "ProxyCommand must preserve unencoded /\$rpc/ and ?\$unique= query; saw $observedUrls",
            )
        }
    }

    @Test
    fun testNormalizeOriginCanonicalizesAntigravityGoogleAlias() {
        assertEquals(
            "https://antigravity.google.com",
            SapisidHashGenerator.normalizeOrigin("https://antigravity.google"),
        )
        assertEquals(
            "https://antigravity.google.com",
            SapisidHashGenerator.normalizeOrigin("https://antigravity.google/r/mac-mini"),
        )
        assertEquals(
            "https://staging.antigravity.google.com",
            SapisidHashGenerator.normalizeOrigin("https://staging.antigravity.google/r/mac-mini"),
        )
    }

    @Test
    fun testResolveCloudRelayInstanceFailsFastOnPrimary504WithoutProbingFallbackAuthUsers() = runTest {
        withContext(Dispatchers.Default) {
            val probedAuthUsers = mutableListOf<String?>()
            val engine = MockEngine { request ->
                if (request.url.encodedPath.endsWith("/ListInstances")) {
                    probedAuthUsers.add(request.headers["X-Goog-AuthUser"])
                    respond(
                        content = "Upstream gateway timed out",
                        status = HttpStatusCode.GatewayTimeout,
                        headers = headersOf(HttpHeaders.ContentType, "text/plain"),
                    )
                } else {
                    respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = "mac-mini-slug",
                hostname = "Mac Mini",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google/r/mac-mini-slug",
            )
            val secretCookie = "SUPER_SECRET_SHOULD_NEVER_LEAK"
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=$secretCookie; SID=sid_val; OSID=osid_val",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val err = assertFailsWith<AntigravityRpcError.HttpError> {
                client.resolveCloudRelayInstance(preferredIdentifier = "mac-mini-slug", allowCrossHostFallback = true)
            }
            assertEquals(504, err.statusCode)
            assertEquals(
                listOf<String?>("0"),
                probedAuthUsers,
                "Primary 504 transport timeout must fail fast without wasting RTTs on authUser=1..4",
            )
            val diag = client.currentHandshakeDiagnosticSummary()
            assertTrue(diag.contains("engine=KMP"))
            assertTrue(diag.contains("origin=https://antigravity.google.com"))
            assertTrue(diag.contains("SAPISID"))
            assertTrue(!diag.contains(secretCookie), "Diagnostic summary must never leak cookie values")
        }
    }

    @Test
    fun testResolveCloudRelayInstanceThrows404NotUnauthorizedWhenHttp200ReturnsEmptyInstances() = runTest {
        withContext(Dispatchers.Default) {
            val engine = MockEngine { request ->
                if (request.url.encodedPath.endsWith("/ListInstances")) {
                    respond(
                        content = """[[],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                } else {
                    respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = "golden-star",
                hostname = "MacBook Pro",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/golden-star",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=valid_sapisid; SID=valid_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val err = assertFailsWith<AntigravityRpcError.HttpError> {
                client.resolveCloudRelayInstance(preferredIdentifier = "golden-star", allowCrossHostFallback = true)
            }
            assertEquals(404, err.statusCode)
            assertTrue(err.body.contains("no online Antigravity Desktop instances", ignoreCase = true))
        }
    }

    @Test
    fun testVerifyConnectionCompletesEvenWhenInitialProxyCommandFailsWith504() = runTest {
        withContext(Dispatchers.Default) {
            val rawUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = """[[["$rawUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        respond(
                            content = "Desktop RPC timed out",
                            status = HttpStatusCode.GatewayTimeout,
                            headers = headersOf(HttpHeaders.ContentType, "text/plain"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = rawUuid,
                hostname = "Antigravity Desktop",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/$rawUuid",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=valid_sapisid; SID=valid_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val handshake = client.verifyConnection(allowCrossHostFallback = true)
            assertEquals("MacBook Pro", handshake.resolvedHostname)
            assertEquals(rawUuid, handshake.resolvedInstanceUuid)
            assertEquals(1, handshake.availableRelayInstances.size)
            assertTrue(handshake.isSelectedHostOnline)
            assertTrue(client.currentHandshakeDiagnosticSummary().contains("phase=connected"))
        }
    }
}
