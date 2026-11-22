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
}
