package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.CortexStepType
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URI
import java.util.zip.GZIPOutputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * JVM E2E integration test executing KMP protocol codecs directly against `verification/mock_language_server.py`:
 * 1. GZIP decompression parity
 * 2. Direct Connect-RPC `GetCascadeTrajectorySteps` (>600 binary Protobuf steps)
 * 3. Direct Connect-RPC 5-byte `JetboxSubscribeToSummaries` server stream
 * 4. Official Cloud Relay `ApiService/ListInstances` (`SAPISIDHASH` 401->200 + `X-Goog-AuthUser=2`)
 * 5. Official Cloud Relay `ApiService/ProxyCommand` tunneling 605 binary Protobuf steps
 */
class MockLanguageServerE2eTest {

    private fun findRepoRoot(): File? {
        var cur = File(System.getProperty("user.dir")).absoluteFile
        repeat(5) {
            if (File(cur, "verification/mock_language_server.py").isFile) return cur
            cur = cur.parentFile ?: return null
        }
        return null
    }

    @Test
    fun testGzipDecompressionParity() {
        val original = """{"trajectorySummaries":{"cas-1":{"stepCount":605}}}""".encodeToByteArray()
        val baos = ByteArrayOutputStream()
        GZIPOutputStream(baos).use { it.write(original) }
        val decompressed = CloudRelayJspbCodec.decompressPayloadIfNeeded(baos.toByteArray())
        assertEquals(original.decodeToString(), decompressed.decodeToString())
    }

    @Test
    fun testLiveMockLanguageServerDirectAndCloudRelayE2e() {
        val repoRoot = findRepoRoot() ?: return
        val bootstrap = """
            import sys, time
            sys.path.insert(0, 'verification')
            from mock_language_server import LiveMockServer
            with LiveMockServer() as srv:
                print(srv.port, flush=True)
                time.sleep(30)
        """.trimIndent()

        val process = ProcessBuilder("python3", "-u", "-c", bootstrap)
            .directory(repoRoot)
            .redirectErrorStream(true)
            .start()

        try {
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val portLine = reader.readLine()?.trim()
            val port = portLine?.toIntOrNull()
            assertTrue(port != null && port > 0, "Failed to start MockLanguageServer; output=$portLine")

            val base = "http://127.0.0.1:$port"

            // 1. Direct Connect-RPC >600 binary Protobuf steps
            val protoReq = ProtobufStepCodec.encodeGetStepsRequest("cas-large-proto", startIndex = 0)
            val protoConn = (URI.create("$base/exa.language_server_pb.LanguageServerService/GetCascadeTrajectorySteps")
                .toURL().openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/proto")
                doOutput = true
                outputStream.write(protoReq)
            }
            assertEquals(200, protoConn.responseCode)
            val protoBytes = protoConn.inputStream.readBytes()
            protoConn.disconnect()

            val decodedSteps = ProtobufStepCodec.decodeStepsResponse(protoBytes, cascadeId = "cas-large-proto")
            assertEquals(605, decodedSteps.size)
            assertTrue(decodedSteps.any { it.type == CortexStepType.PLANNER_RESPONSE })

            // 2. Direct Connect-RPC 5-byte envelope stream (`JetboxSubscribeToSummaries`)
            val streamConn = (URI.create("$base/exa.language_server_pb.LanguageServerService/JetboxSubscribeToSummaries")
                .toURL().openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/connect+json")
                doOutput = true
                outputStream.write(ConnectEnvelope.encode("{}".encodeToByteArray()))
            }
            assertEquals(200, streamConn.responseCode)
            val streamBytes = streamConn.inputStream.readBytes()
            streamConn.disconnect()

            val frames = ConnectStreamParser().feed(streamBytes)
            assertTrue(frames.isNotEmpty(), "Expected >=1 Connect-RPC frame from JetboxSubscribeToSummaries")
            assertTrue(frames.first().payload.decodeToString().contains("cascadeId") || frames.first().payload.decodeToString().contains("updates"))

            // 3. Official Cloud Relay `ApiService/ListInstances`: 401 without SAPISIDHASH -> 200 with KMP SAPISIDHASH
            val unauthConn = (URI.create("$base${SapisidHashGenerator.API_SERVICE_PREFIX}/ListInstances")
                .toURL().openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/json+protobuf")
                doOutput = true
                outputStream.write(CloudRelayJspbCodec.encodeListInstancesRequest())
            }
            assertEquals(401, unauthConn.responseCode)
            unauthConn.disconnect()

            val cookie = "SID=test_sid; SAPISID=test_sapisid_secret"
            val ts = System.currentTimeMillis() / 1000L
            val relayHeaders = SapisidHashGenerator.buildApiServiceHeaders(
                cookieHeader = cookie,
                origin = SapisidHashGenerator.DEFAULT_ORIGIN,
                authUser = "2",
                isStreaming = false,
                timestampSeconds = ts,
            )
            val listConn = (URI.create("$base${SapisidHashGenerator.API_SERVICE_PREFIX}/ListInstances")
                .toURL().openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                relayHeaders.forEach { (k, v) -> setRequestProperty(k, v) }
                doOutput = true
                outputStream.write(CloudRelayJspbCodec.encodeListInstancesRequest())
            }
            assertEquals(200, listConn.responseCode)
            val instances = CloudRelayJspbCodec.decodeListInstancesResponse(listConn.inputStream.readBytes())
            listConn.disconnect()

            assertEquals(1, instances.size)
            assertEquals("0f5819ac-9308-40d8-a308-98b55122c533-v2", instances[0].uuid)
            assertTrue(instances[0].matches("lt74xt6l0m-golden-star"))

            // 4. Official Cloud Relay `ApiService/ProxyCommand` tunneling 605 binary Protobuf steps
            val proxyReqBytes = CloudRelayJspbCodec.encodeProxyCommandRequest(
                targetInstanceUuid = instances[0].uuid,
                rpcPath = "/exa.language_server_pb.LanguageServerService/GetCascadeTrajectorySteps",
                payload = protoReq,
                contentType = "application/proto",
            )
            val proxyConn = (URI.create("$base${SapisidHashGenerator.API_SERVICE_PREFIX}/ProxyCommand")
                .toURL().openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                relayHeaders.forEach { (k, v) -> setRequestProperty(k, v) }
                doOutput = true
                outputStream.write(proxyReqBytes)
            }
            assertEquals(200, proxyConn.responseCode)
            val decodedProxy = CloudRelayJspbCodec.decodeProxyCommandResponse(proxyConn.inputStream.readBytes())
            proxyConn.disconnect()

            val relaySteps = ProtobufStepCodec.decodeStepsResponse(decodedProxy.payload, cascadeId = "cas-cloud-relay")
            assertEquals(605, relaySteps.size)
        } finally {
            process.destroyForcibly()
        }
    }
}
