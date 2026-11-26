package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.engine.mock.toByteArray
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import okio.ByteString
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
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
    fun testApiServiceHeadersIncludeMobileSafariUserAgentAndNormalizeVanityOrigin() {
        assertEquals(
            "https://antigravity.google.com",
            SapisidHashGenerator.normalizeOrigin("https://antigravity.google/r/abc-123"),
        )
        assertEquals(
            "https://antigravity.google.com",
            SapisidHashGenerator.normalizeOrigin("https://ANTIGRAVITY.GOOGLE"),
        )

        val headers = SapisidHashGenerator.buildApiServiceHeaders(
            cookieHeader = "SAPISID=test_val; SID=test_sid",
            origin = "https://antigravity.google/r/abc-123",
            apiKey = "AI" + "zaSyUAHEADER0000000000000000000000000",
            authUser = "0",
            timestampSeconds = 1_750_000_000L,
        )
        assertEquals(SapisidHashGenerator.MOBILE_REMOTE_USER_AGENT, headers["User-Agent"])
        assertEquals("https://antigravity.google.com", headers["Origin"])
        assertEquals("https://antigravity.google.com/", headers["Referer"])
        assertTrue(headers["Authorization"]?.startsWith("SAPISIDHASH ") == true)
    }

    @Test
    fun testVerifyConnectionDefersSlowInitialTrajectorySyncInsteadOfTimingOut504() = runTest {
        withContext(Dispatchers.Default) {
            val validKey = "AI" + "zaSyFASTHANDSHAKE00000000000000000000"
            val rawUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            val secretCookie = "SUPER_SECRET_SAPISID_VALUE_999"
            var observedUserAgent: String? = null

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        observedUserAgent = request.headers["User-Agent"]
                        respond(
                            content = """[[["$rawUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        // Simulate a slow VPN / large trajectory list stalling beyond the initial sync soft cap
                        kotlinx.coroutines.delay(15_000L)
                        respond("", HttpStatusCode.OK)
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = rawUuid,
                hostname = "Antigravity Desktop",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google/r/$rawUuid",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=$secretCookie; SID=sid_token",
                relayApiKey = validKey,
                httpClientOverride = HttpClient(engine),
            )

            val startedMs = currentTimeMillis()
            val handshake = client.verifyConnection(allowCrossHostFallback = true)
            val elapsedMs = currentTimeMillis() - startedMs

            assertEquals("MacBook Pro", handshake.resolvedHostname)
            assertEquals(rawUuid, handshake.resolvedInstanceUuid)
            assertEquals(validKey, handshake.resolvedRelayApiKey)
            assertTrue(handshake.isSelectedHostOnline)
            assertTrue(handshake.summaries.isEmpty(), "Stalled initial sync must be deferred rather than blocking handshake")
            assertTrue(elapsedMs < 12_000L, "Handshake must complete well before 22s hard cap even when initial sync stalls; took ${elapsedMs}ms")
            assertEquals(SapisidHashGenerator.MOBILE_REMOTE_USER_AGENT, observedUserAgent)

            val diag = client.currentHandshakeDiagnostic()
            assertTrue(diag.contains("engine=${platformTransportEngineName()}"), "Expected engine in diagnostic: $diag")
            assertTrue(diag.contains("origin=antigravity.google.com"), "Expected canonical origin in diagnostic: $diag")
            assertTrue(diag.contains("sync:deferred"), "Expected sync:deferred breadcrumb in diagnostic: $diag")
            assertTrue(!diag.contains(secretCookie), "Diagnostic must never leak raw cookie values: $diag")
            assertTrue(!diag.contains(validKey), "Diagnostic must never leak full API key: $diag")
        }
    }

    @Test
    fun testResolveCloudRelayInstanceFailsFastOnPrimary504WithoutProbingFallbackAuthUsers() = runTest {
        withContext(Dispatchers.Default) {
            val validKey = "AI" + "zaSyFAILFAST5040000000000000000000000"
            val secretCookie = "SECRET_SAPISID_SHOULD_NOT_LEAK_504"
            val probedAuthUsers = mutableListOf<String?>()

            val engine = MockEngine { request ->
                if (request.url.encodedPath.endsWith("/ListInstances")) {
                    probedAuthUsers.add(request.headers["X-Goog-AuthUser"])
                    respond(
                        content = "Gateway Timeout",
                        status = HttpStatusCode.GatewayTimeout,
                        headers = headersOf(HttpHeaders.ContentType, "text/plain"),
                    )
                } else {
                    respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = "lt74xt6l0m-golden-star",
                hostname = "Antigravity Desktop",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/lt74xt6l0m-golden-star",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=$secretCookie; SID=sid_504",
                relayApiKey = validKey,
                httpClientOverride = HttpClient(engine),
            )

            val err = assertFailsWith<AntigravityRpcError.HttpError> {
                client.resolveCloudRelayInstance(allowCrossHostFallback = true)
            }
            assertEquals(504, err.statusCode)
            assertEquals(
                listOf<String?>("0"),
                probedAuthUsers,
                "Primary HTTP 504 must fail fast instead of burning timeout probing authUser=1..4",
            )
            val diag = client.currentHandshakeDiagnostic()
            assertTrue(diag.contains("resolve:failFast"), "Expected resolve:failFast trace in diagnostic: $diag")
            assertTrue(!diag.contains(secretCookie), "Diagnostic must never leak secret cookie value: $diag")
            assertTrue(!diag.contains(validKey), "Diagnostic must never leak API key value: $diag")
        }
    }

    @Test
    fun testResolveCloudRelayInstanceThrows404NotUnauthorizedWhenHttp200ReturnsEmptyInstances() = runTest {
        withContext(Dispatchers.Default) {
            val validKey = "AI" + "zaSyEMPTY200KEY0000000000000000000000"

            val engine = MockEngine { request ->
                if (request.url.encodedPath.endsWith("/ListInstances")) {
                    respond(
                        content = ")]}'\n[[],5]",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                } else {
                    respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = "golden-star",
                hostname = "Antigravity Desktop",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/golden-star",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                httpClientOverride = HttpClient(engine),
            )

            val err = assertFailsWith<AntigravityRpcError.HttpError> {
                client.resolveCloudRelayInstance(allowCrossHostFallback = true)
            }
            assertEquals(
                404,
                err.statusCode,
                "Empty HTTP 200 ListInstances must throw actionable 404 instead of Unauthorized login loop",
            )
        }
    }

    @Test
    fun testVerifyConnectionCompletesEvenWhenInitialProxyCommandFailsWith504() = runTest {
        withContext(Dispatchers.Default) {
            val validKey = "AI" + "zaSyPROXY504OK00000000000000000000000"
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
                            content = "Gateway Timeout",
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
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                httpClientOverride = HttpClient(engine),
            )

            val handshake = client.verifyConnection(allowCrossHostFallback = true)
            assertEquals("MacBook Pro", handshake.resolvedHostname)
            assertEquals(rawUuid, handshake.resolvedInstanceUuid)
            assertTrue(handshake.isSelectedHostOnline)
            assertFalse(handshake.initialSyncCompleted)
            assertTrue(handshake.succeededInstanceUuids.isEmpty())
            assertTrue(handshake.summaries.isEmpty())
        }
    }

    @Test
    fun testInstanceNotRegisteredBoq400ClassificationAndUserFacingFormat() {
        val boqBody = """[9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo","INSTANCE_NOT_REGISTERED","antigravity.googleapis.com"]]]"""
        assertTrue(ProtocolCompatibilityEngine.isInstanceNotRegisteredResponse(400, boqBody))
        assertFalse(ProtocolCompatibilityEngine.isMethodUnimplementedResponse(400, boqBody))
        assertTrue(ProtocolCompatibilityEngine.isInstanceNotRegisteredError(AntigravityRpcError.HttpError(400, boqBody)))

        val formatted = ProtocolCompatibilityEngine.formatUserFacingRpcError(
            AntigravityRpcError.HttpError(400, boqBody),
        )
        assertTrue(formatted.contains("offline", ignoreCase = true), "Expected clean offline guidance, got: $formatted")
        assertFalse(formatted.contains("type.googleapis.com"), "Raw protobuf @type must not leak: $formatted")
        assertFalse(formatted.contains("[9,"), "Raw Boq JSON must not leak: $formatted")
    }

    @Test
    fun testCloudRelayFailoverOnHttp400InstanceNotRegisteredToSameMacSiblingWindow() = runTest {
        withContext(Dispatchers.Default) {
            val validKey = "AI" + "zaSyFAILOVER4000000000000000000000000"
            val deadUuid = "huangjiafandemac-mini-local-swift-vapor"
            val liveUuid = "huangjiafandemac-mini-local-game-loop"
            val boqUnregistered = """[9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo","INSTANCE_NOT_REGISTERED","antigravity.googleapis.com"]]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        // Relay still reports both windows as status=1 CONNECTED even though swift-vapor died
                        respond(
                            content = """[[["$deadUuid",["$deadUuid","2.33.0",true],1,[1740000000,0]],["$liveUuid",["$liveUuid","2.33.0",true],1,[1740000005,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val bodyText = runCatching { request.body.toByteArray().decodeToString() }.getOrDefault("")
                        if (bodyText.contains(deadUuid)) {
                            respond(
                                content = boqUnregistered,
                                status = HttpStatusCode.BadRequest,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        } else {
                            val payload = """{"workspaces":[{"workspaceUri":"file:///Users/mini/PocketAntigravity","displayName":"PocketAntigravity"}]}"""
                            val b64 = ByteString.of(*payload.encodeToByteArray()).base64()
                            respond(
                                content = """["$b64",[["content-type","application/json"]]]""",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = deadUuid,
                hostname = deadUuid,
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/$deadUuid",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                httpClientOverride = HttpClient(engine),
            )

            val workspaces = client.getWorkspaceInfos()
            assertEquals(1, workspaces.size)
            assertEquals("PocketAntigravity", workspaces.first().displayName)
            assertEquals(liveUuid, client.currentResolvedInstanceUuid())
            val deadInstance = client.currentCachedRelayInstances().firstOrNull { it.uuid == deadUuid }
            assertEquals(RelayInstanceStatus.DISCONNECTED, deadInstance?.status)
        }
    }

    @Test
    fun testVerifyConnectionDirectUuidFallbackProbesLivenessAndMarksUnregisteredOffline() = runTest {
        withContext(Dispatchers.Default) {
            val validKey = "AI" + "zaSyDIRECTUUID00000000000000000000000"
            val deadUuid = "huangjiafandemac-mini-local-swift-vapor"
            val boqUnregistered = """[9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo","INSTANCE_NOT_REGISTERED","antigravity.googleapis.com"]]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = "[]",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        respond(
                            content = boqUnregistered,
                            status = HttpStatusCode.BadRequest,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = deadUuid,
                hostname = deadUuid,
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/$deadUuid",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                httpClientOverride = HttpClient(engine),
            )

            val handshake = client.verifyConnection(allowCrossHostFallback = false)
            assertFalse(handshake.isSelectedHostOnline, "Unregistered 39-char UUID must NOT be fabricated as online")
            assertFalse(handshake.initialSyncCompleted)
            assertTrue(handshake.succeededInstanceUuids.isEmpty())
            val reported = handshake.availableRelayInstances.firstOrNull { it.uuid == deadUuid }
            assertEquals(RelayInstanceStatus.DISCONNECTED, reported?.status)
        }
    }

    @Test
    fun testProbeHostReachabilityVerifyEndToEndDowngradesZombieConnectedInstance() = runTest {
        withContext(Dispatchers.Default) {
            val validKey = "AI" + "zaSyZOMBIEPROBE0000000000000000000000"
            val zombieUuid = "huangjiafandemac-mini-local-swift-vapor"
            val boqUnregistered = """[9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo","INSTANCE_NOT_REGISTERED","antigravity.googleapis.com"]]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = """[[["$zombieUuid",["$zombieUuid","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        respond(
                            content = boqUnregistered,
                            status = HttpStatusCode.BadRequest,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val host = RemoteHostInstance(
                instanceId = zombieUuid,
                hostname = zombieUuid,
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/$zombieUuid",
            )
            val client = AntigravityKmpRpcClient(
                host = host,
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                httpClientOverride = HttpClient(engine),
            )

            val probe = client.probeHostReachability(allowCrossHostFallback = false, verifyEndToEnd = true)
            assertFalse(probe.isSelectedHostOnline, "End-to-end probe must detect zombie CONNECTED instance returning HTTP 400")
            val reported = probe.availableRelayInstances.firstOrNull { it.uuid == zombieUuid }
            assertEquals(RelayInstanceStatus.DISCONNECTED, reported?.status)
        }
    }
}
