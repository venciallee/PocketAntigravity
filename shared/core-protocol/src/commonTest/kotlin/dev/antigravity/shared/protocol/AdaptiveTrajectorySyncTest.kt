package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.model.RequestedInteraction
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.ByteArrayContent
import io.ktor.http.headersOf
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AdaptiveTrajectorySyncTest {

    private data class RecordedRequest(
        val path: String,
        val contentType: String,
        val bodyBytes: ByteArray,
    ) {
        val bodyText: String get() = bodyBytes.decodeToString()
        val isProto: Boolean get() = contentType.contains("application/proto", ignoreCase = true)
        val isJson: Boolean get() = contentType.contains("application/json", ignoreCase = true)
    }

    private fun testHost(instanceId: String = "mac-local-1"): RemoteHostInstance = RemoteHostInstance(
        instanceId = instanceId,
        hostname = "MacBook-Pro-Test",
        channel = RemoteConnectionChannel.DIRECT_HOST,
        endpointUrl = "https://127.0.0.1:42100",
        isOnline = true,
    )

    private fun encodeLd(fieldNumber: Int, payload: ByteArray): ByteArray {
        val tag = ProtobufStepCodec.encodeVarint(((fieldNumber shl 3) or 2).toULong())
        val len = ProtobufStepCodec.encodeVarint(payload.size.toULong())
        return tag + len + payload
    }

    private fun encodeVarintField(fieldNumber: Int, value: Int): ByteArray {
        val tag = ProtobufStepCodec.encodeVarint(((fieldNumber shl 3) or 0).toULong())
        val v = ProtobufStepCodec.encodeVarint(value.toULong())
        return tag + v
    }

    private fun buildBinaryPlannerSteps(count: Int): ByteArray {
        val out = ArrayList<Byte>()
        for (i in 0 until count) {
            val stepBytes = if (i % 2 == 0) {
                encodeVarintField(1, 14) + // USER_INPUT
                    encodeVarintField(4, 3) + // DONE
                    encodeLd(19, encodeLd(1, "User prompt #$i".encodeToByteArray()))
            } else {
                encodeVarintField(1, 15) + // PLANNER_RESPONSE
                    encodeVarintField(4, 3) + // DONE
                    encodeLd(20, encodeLd(1, "Planner answer #$i".encodeToByteArray()))
            }
            out.addAll(encodeLd(1, stepBytes).toList())
        }
        return out.toByteArray()
    }

    private fun buildJsonStepsPayload(
        indices: IntRange,
        truncatedAt: Int? = null,
    ): String = buildJsonObject {
        put(
            "steps",
            buildJsonArray {
                for (i in indices) {
                    add(
                        buildJsonObject {
                            put("stepIndex", i)
                            put("type", "CORTEX_STEP_TYPE_PLANNER_RESPONSE")
                            put("status", "CORTEX_STEP_STATUS_DONE")
                            put("plannerResponse", buildJsonObject { put("response", "JSON step #$i") })
                        }
                    )
                }
            },
        )
        if (truncatedAt != null) {
            put("truncatedAt", truncatedAt)
        }
    }.toString()

    @Test
    fun testLocalDirectHostDefaultsToBinaryProtobufWithZeroJsonCalls() = runTest {
        val recorded = mutableListOf<RecordedRequest>()
        val protoPayload = buildBinaryPlannerSteps(count = 4)

        val engine = MockEngine { request ->
            val ct = request.body.contentType?.toString()
                ?: request.headers[HttpHeaders.ContentType].orEmpty()
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            recorded.add(RecordedRequest(request.url.encodedPath, ct, bytes))

            assertTrue(ct.contains("application/proto"), "Local direct host must default to application/proto, got $ct")
            respond(
                content = protoPayload,
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/proto"),
            )
        }

        val client = AntigravityKmpRpcClient(
            host = testHost(),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )

        val steps = client.fetchAllTrajectorySteps(cascadeId = "cas-local-1", knownStepCount = 4)
        assertEquals(4, steps.size)
        assertEquals(CortexStepType.USER_INPUT, steps[0].type)
        assertEquals("User prompt #0", steps[0].userInput)
        assertEquals(CortexStepType.PLANNER_RESPONSE, steps[3].type)
        assertEquals("Planner answer #3", steps[3].plannerResponse?.response)

        assertEquals(1, recorded.count { it.isProto })
        assertEquals(0, recorded.count { it.isJson })
    }

    @Test
    fun testBinaryProtobufUnknownWireInteractionAndUnknownStepTypeTriggerTargetedJsonRepair() = runTest {
        val recorded = mutableListOf<RecordedRequest>()
        val json = Json { ignoreUnknownKeys = true }

        val step0 = encodeVarintField(1, 14) +
            encodeVarintField(4, 3) +
            encodeLd(19, encodeLd(1, "Render topology & deploy".encodeToByteArray()))
        val step1UnknownType = encodeVarintField(1, 199) +
            encodeVarintField(4, 3) +
            encodeLd(199, encodeLd(1, "Wire canvas preview".encodeToByteArray()))
        val step2UnknownWaitingInteraction = encodeVarintField(1, 15) +
            encodeVarintField(4, 9) + // WAITING
            encodeLd(20, encodeLd(1, "Cluster deploy awaiting approval".encodeToByteArray())) +
            encodeLd(56, encodeLd(99, encodeLd(1, "Approve canary rollout".encodeToByteArray())))

        val protoPayload = encodeLd(1, step0) + encodeLd(1, step1UnknownType) + encodeLd(1, step2UnknownWaitingInteraction)

        // Sanity-check raw binary decoding before repair
        val rawDecoded = ProtobufStepCodec.decodeStepsResponse(protoPayload, cascadeId = "cas-forward")
        assertEquals(3, rawDecoded.size)
        assertEquals(CortexStepType.UNSPECIFIED, rawDecoded[1].type)
        assertEquals("STEP_TYPE_199", rawDecoded[1].rawTypeName)
        assertEquals("Wire canvas preview", rawDecoded[1].fallbackSummary)
        assertTrue(rawDecoded[1].isUnrecognizedForwardStep)
        assertTrue(rawDecoded[1].hasRenderableChatContent)
        assertEquals(99, rawDecoded[2].requestedInteraction?.rawWireFieldNumber)
        assertTrue(rawDecoded[2].requestedInteraction?.isUnrecognizedWireMember == true)

        val engine = MockEngine { request ->
            val ct = request.body.contentType?.toString()
                ?: request.headers[HttpHeaders.ContentType].orEmpty()
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            recorded.add(RecordedRequest(request.url.encodedPath, ct, bytes))

            if (ct.contains("application/proto")) {
                respond(
                    content = protoPayload,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/proto"),
                )
            } else {
                val reqObj = json.parseToJsonElement(bytes.decodeToString()) as JsonObject
                val offset = (reqObj["stepOffset"] as? JsonPrimitive)?.intOrNull
                val jsonBody = when (offset) {
                    1 -> """
                        {
                          "steps": [
                            {
                              "stepIndex": 1,
                              "type": "CORTEX_STEP_TYPE_FUTURE_CANVAS_RENDER",
                              "status": "CORTEX_STEP_STATUS_DONE",
                              "futureCanvasRender": {
                                "title": "Interactive 3D architecture canvas"
                              }
                            }
                          ]
                        }
                    """.trimIndent()
                    2 -> """
                        {
                          "steps": [
                            {
                              "stepIndex": 2,
                              "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
                              "status": "CORTEX_STEP_STATUS_WAITING",
                              "plannerResponse": { "response": "Cluster deploy awaiting approval" },
                              "requestedInteraction": {
                                "futureClusterDeploy": {
                                  "summary": "Deploy canary cluster to us-west1"
                                }
                              }
                            }
                          ]
                        }
                    """.trimIndent()
                    else -> """{"steps":[]}"""
                }
                respond(
                    content = jsonBody,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
        }

        val client = AntigravityKmpRpcClient(
            host = testHost(),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )

        val repaired = client.fetchAllTrajectorySteps(cascadeId = "cas-forward", knownStepCount = 3)
        assertEquals(3, repaired.size)

        // Verify exactly 1 binary fetch + 2 targeted stepOffset JSON repairs (offsets 1 and 2)
        assertEquals(1, recorded.count { it.isProto })
        val jsonRequests = recorded.filter { it.isJson }
        assertEquals(2, jsonRequests.size)
        val requestedOffsets = jsonRequests.map { req ->
            val obj = json.parseToJsonElement(req.bodyText) as JsonObject
            (obj["stepOffset"] as? JsonPrimitive)?.intOrNull
        }
        assertEquals(listOf(1, 2), requestedOffsets)

        // Step 1 recovered real step type name + summary
        assertEquals(CortexStepType.UNSPECIFIED, repaired[1].type)
        assertEquals("CORTEX_STEP_TYPE_FUTURE_CANVAS_RENDER", repaired[1].rawTypeName)
        assertEquals("Interactive 3D architecture canvas", repaired[1].fallbackSummary)
        assertTrue(repaired[1].isUnrecognizedForwardStep)
        assertTrue(repaired[1].hasRenderableChatContent)

        // Step 2 recovered exact rawMemberKey + cleared rawWireFieldNumber
        val interaction = repaired[2].requestedInteraction
        assertNotNull(interaction)
        assertEquals(RequestedInteraction.MemberKind.APPROVAL_INTERACTION, interaction.kind)
        assertEquals("futureClusterDeploy", interaction.rawMemberKey)
        assertEquals("Deploy canary cluster to us-west1", interaction.rawSummary)
        assertNull(interaction.rawWireFieldNumber)
        assertFalse(interaction.isUnrecognizedWireMember)
    }

    @Test
    fun testHttp415FallsBackToJsonCachesUnsupportedAndVersionUpgradeResetsCapabilities() = runTest {
        val recorded = mutableListOf<RecordedRequest>()
        var rejectProtobuf = true

        val engine = MockEngine { request ->
            val ct = request.body.contentType?.toString()
                ?: request.headers[HttpHeaders.ContentType].orEmpty()
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            recorded.add(RecordedRequest(request.url.encodedPath, ct, bytes))

            if (ct.contains("application/proto")) {
                if (rejectProtobuf) {
                    respond(
                        content = "Unsupported Media Type: application/proto",
                        status = HttpStatusCode.UnsupportedMediaType,
                        headers = headersOf(HttpHeaders.ContentType, "text/plain"),
                    )
                } else {
                    respond(
                        content = buildBinaryPlannerSteps(count = 2),
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/proto"),
                    )
                }
            } else {
                respond(
                    content = buildJsonStepsPayload(0 until 2, truncatedAt = 80),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
        }

        val client = AntigravityKmpRpcClient(
            host = testHost("mac-legacy-415"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )
        client.updateReportedHostVersion("2.33.0")

        // Fetch 1: tries application/proto -> HTTP 415 -> falls back to JSON + learns ceiling 80
        val firstSteps = client.fetchAllTrajectorySteps(cascadeId = "cas-legacy", knownStepCount = 2)
        assertEquals(2, firstSteps.size)
        assertTrue(client.isBinaryProtobufStepsUnsupported())
        assertEquals(80, client.learnedJsonStepCeiling())
        assertEquals(1, recorded.count { it.isProto })
        assertEquals(1, recorded.count { it.isJson })

        // Same version must NOT reset cached capabilities
        client.updateReportedHostVersion("2.33.0")
        assertTrue(client.isBinaryProtobufStepsUnsupported())
        assertEquals(80, client.learnedJsonStepCeiling())

        // Fetch 2: makes 0 application/proto requests
        recorded.clear()
        val secondSteps = client.fetchAllTrajectorySteps(cascadeId = "cas-legacy", knownStepCount = 2)
        assertEquals(2, secondSteps.size)
        assertEquals(0, recorded.count { it.isProto })
        assertEquals(1, recorded.count { it.isJson })

        // Host upgrade to 2.35.0 resets BOTH binaryProtobufStepsUnsupported and learnedJsonStepCeiling
        client.updateReportedHostVersion("2.35.0")
        assertFalse(client.isBinaryProtobufStepsUnsupported())
        assertNull(client.learnedJsonStepCeiling())

        // Fetch 3 after upgrade re-probes binary Protobuf cleanly
        rejectProtobuf = false
        recorded.clear()
        val upgradedSteps = client.fetchAllTrajectorySteps(cascadeId = "cas-legacy", knownStepCount = 2)
        assertEquals(2, upgradedSteps.size)
        assertEquals(1, recorded.count { it.isProto })
        assertEquals(0, recorded.count { it.isJson })
    }

    @Test
    fun testCloudArbitraryTruncatedAtLearnsCeilingAndAppliesLearnedFastPath() = runTest {
        val recorded = mutableListOf<RecordedRequest>()
        val json = Json { ignoreUnknownKeys = true }
        val proto260 = buildBinaryPlannerSteps(count = 260)

        val engine = MockEngine { request ->
            val ct = request.body.contentType?.toString()
                ?: request.headers[HttpHeaders.ContentType].orEmpty()
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            recorded.add(RecordedRequest(request.url.encodedPath, ct, bytes))

            if (ct.contains("application/proto")) {
                respond(
                    content = proto260,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/proto"),
                )
            } else {
                val reqObj = json.parseToJsonElement(bytes.decodeToString()) as JsonObject
                val cid = (reqObj["cascadeId"] as? JsonPrimitive)?.contentOrNull.orEmpty()
                val body = if (cid == "v1/cas-cloud-240") {
                    buildJsonStepsPayload(0 until 10, truncatedAt = 240)
                } else {
                    buildJsonStepsPayload(0 until 100)
                }
                respond(
                    content = body,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
        }

        val client = AntigravityKmpRpcClient(
            host = testHost("cloud-proxy-1"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )

        // Fetch 1: Cloud session hits truncatedAt=240 -> learns ceiling 240 & upgrades to Protobuf
        val firstSteps = client.fetchAllTrajectorySteps(cascadeId = "v1/cas-cloud-240", knownStepCount = 0)
        assertEquals(260, firstSteps.size)
        assertEquals(240, client.learnedJsonStepCeiling())
        assertEquals(1, recorded.count { it.isJson })
        assertEquals(1, recorded.count { it.isProto })

        // Fetch 2: knownStepCount=250 (>= 240) skips JSON completely and goes straight to Protobuf
        recorded.clear()
        val largeSteps = client.fetchAllTrajectorySteps(cascadeId = "v1/cas-cloud-240", knownStepCount = 250)
        assertEquals(260, largeSteps.size)
        assertEquals(0, recorded.count { it.isJson })
        assertEquals(1, recorded.count { it.isProto })

        // Fetch 3: knownStepCount=100 (< 240) stays on JSON with 0 Protobuf calls
        recorded.clear()
        val smallSteps = client.fetchAllTrajectorySteps(cascadeId = "v1/cas-cloud-small", knownStepCount = 100)
        assertEquals(100, smallSteps.size)
        assertEquals(1, recorded.count { it.isJson })
        assertEquals(0, recorded.count { it.isProto })
    }

    @Test
    fun testCloudSilentPaginationStallLearnsCeilingAndUpgradesToProtobuf() = runTest {
        val recorded = mutableListOf<RecordedRequest>()
        val json = Json { ignoreUnknownKeys = true }
        val proto12 = buildBinaryPlannerSteps(count = 12)

        val engine = MockEngine { request ->
            val ct = request.body.contentType?.toString()
                ?: request.headers[HttpHeaders.ContentType].orEmpty()
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            recorded.add(RecordedRequest(request.url.encodedPath, ct, bytes))

            if (ct.contains("application/proto")) {
                respond(
                    content = proto12,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/proto"),
                )
            } else {
                val reqObj = json.parseToJsonElement(bytes.decodeToString()) as JsonObject
                val offset = (reqObj["stepOffset"] as? JsonPrimitive)?.intOrNull ?: 0
                val body = if (offset == 0) {
                    buildJsonStepsPayload(0 until 5)
                } else {
                    """{"steps":[]}"""
                }
                respond(
                    content = body,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
        }

        val client = AntigravityKmpRpcClient(
            host = testHost("cloud-stall-host"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )

        val steps = client.fetchAllTrajectorySteps(cascadeId = "v1/cas-stall", knownStepCount = 12)
        assertEquals(12, steps.size)
        assertEquals(5, client.learnedJsonStepCeiling())
        assertEquals(2, recorded.count { it.isJson }) // offset=0 (5 steps) + offset=5 ([])
        assertEquals(1, recorded.count { it.isProto })
    }

    @Test
    fun testHttp413PayloadTooLargeOnJsonUpgradesToProtobufAndLearnsCeiling() = runTest {
        val recorded = mutableListOf<RecordedRequest>()
        val proto150 = buildBinaryPlannerSteps(count = 150)

        val engine = MockEngine { request ->
            val ct = request.body.contentType?.toString()
                ?: request.headers[HttpHeaders.ContentType].orEmpty()
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            recorded.add(RecordedRequest(request.url.encodedPath, ct, bytes))

            if (ct.contains("application/proto")) {
                respond(
                    content = proto150,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/proto"),
                )
            } else {
                respond(
                    content = "Payload Too Large: JSON response exceeds server limit",
                    status = HttpStatusCode.PayloadTooLarge,
                    headers = headersOf(HttpHeaders.ContentType, "text/plain"),
                )
            }
        }

        val client = AntigravityKmpRpcClient(
            host = testHost("cloud-413-host"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )

        val steps = client.fetchAllTrajectorySteps(cascadeId = "v1/cas-413", knownStepCount = 150)
        assertEquals(150, steps.size)
        assertEquals(150, client.learnedJsonStepCeiling())
        assertEquals(1, recorded.count { it.isJson })
        assertEquals(1, recorded.count { it.isProto })
    }
}
