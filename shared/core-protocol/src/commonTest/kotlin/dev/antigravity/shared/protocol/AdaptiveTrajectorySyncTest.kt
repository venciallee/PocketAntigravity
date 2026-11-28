package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.CascadeStep
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
import io.ktor.utils.io.ByteChannel
import io.ktor.utils.io.writeFully
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import okio.ByteString.Companion.toByteString
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
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
            if (request.url.encodedPath.endsWith("/StreamAgentStateUpdates")) {
                return@MockEngine respond(
                    content = """{"code":"unimplemented","message":"unknown method StreamAgentStateUpdates"}""",
                    status = HttpStatusCode.NotImplemented,
                    headers = headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
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
            if (request.url.encodedPath.endsWith("/StreamAgentStateUpdates")) {
                return@MockEngine respond(
                    content = """{"code":"unimplemented","message":"unknown method StreamAgentStateUpdates"}""",
                    status = HttpStatusCode.NotImplemented,
                    headers = headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
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
            if (request.url.encodedPath.endsWith("/StreamAgentStateUpdates")) {
                return@MockEngine respond(
                    content = """{"code":"unimplemented","message":"unknown method StreamAgentStateUpdates"}""",
                    status = HttpStatusCode.NotImplemented,
                    headers = headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
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

    private fun encodeJspbProxyResponse(jsonPayload: String): String {
        val b64 = jsonPayload.encodeToByteArray().toByteString().base64()
        return """["$b64",[["content-type","application/json"]]]"""
    }

    private fun decodeProxyCommandInner(bodyText: String): Triple<String, String, String> {
        val arr = Json.parseToJsonElement(bodyText) as kotlinx.serialization.json.JsonArray
        val targetUuid = (arr[0] as JsonPrimitive).content
        val rpcPath = (arr[1] as JsonPrimitive).content
        val b64Payload = (arr[2] as JsonPrimitive).content
        val payloadText = CloudRelayJspbCodec.decodeBase64Flexible(b64Payload)?.decodeToString().orEmpty()
        return Triple(targetUuid, rpcPath, payloadText)
    }

    @Test
    fun testCloudRelayDormantHistoricalCloudTrajectoryWakesViaBareLoadTrajectoryAndSkipsExtraListInstances() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            val wokenIds = mutableSetOf<String>()
            var listInstancesCalls = 0
            val loadPayloads = mutableListOf<JsonObject>()
            val json = Json { ignoreUnknownKeys = true }

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
                when {
                    path.endsWith("/ListInstances") -> {
                        listInstancesCalls += 1
                        respond(
                            content = """[[["$instanceUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val (_, rpcPath, payloadText) = decodeProxyCommandInner(bytes.decodeToString())
                        val method = rpcPath.substringAfterLast('/')
                        val reqObj = json.parseToJsonElement(payloadText) as JsonObject
                        val cid = (reqObj["cascadeId"] as? JsonPrimitive)?.contentOrNull.orEmpty()
                        when (method) {
                            "LoadTrajectory" -> {
                                loadPayloads.add(reqObj)
                                when {
                                    "backend" in reqObj -> respond(
                                        content = """[3,"invalid_argument: unknown field \"backend\""]""",
                                        status = HttpStatusCode.BadRequest,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                    "backendType" in reqObj -> respond(
                                        content = """[3,"invalid_argument: unknown field \"backendType\""]""",
                                        status = HttpStatusCode.BadRequest,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                    else -> {
                                        wokenIds.add(cid)
                                        respond(
                                            content = encodeJspbProxyResponse("{}"),
                                            status = HttpStatusCode.OK,
                                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                        )
                                    }
                                }
                            }
                            "GetCascadeTrajectorySteps" -> {
                                if (cid in wokenIds) {
                                    respond(
                                        content = encodeJspbProxyResponse(buildJsonStepsPayload(0 until 3)),
                                        status = HttpStatusCode.OK,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                } else {
                                    respond(
                                        content = """[5,"not_found: trajectory not found (error ID: 721ffeb9b0bb4fb6b2a971dfa56087e2)"]""",
                                        status = HttpStatusCode.NotFound,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                }
                            }
                            else -> respond(
                                content = encodeJspbProxyResponse("{}"),
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val cloudRelayHost = RemoteHostInstance(
                instanceId = instanceUuid,
                hostname = "MacBook Pro",
                channel = RemoteConnectionChannel.CLOUD_RELAY,
                endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                isOnline = true,
            )
            val client = AntigravityKmpRpcClient(
                host = cloudRelayHost,
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val steps1 = client.fetchAllTrajectorySteps(
                cascadeId = "v1/sync-mobile-concept",
                knownStepCount = 3,
                isCloud = true,
            )
            assertEquals(3, steps1.size)
            assertEquals(1, listInstancesCalls, "Trajectory-level 404 must not trigger extra ListInstances RTTs")
            assertEquals(3, loadPayloads.size, "First dormant Cloud wake probes backend -> backendType -> bare {cascadeId}")
            assertFalse("backend" in loadPayloads.last())
            assertFalse("backendType" in loadPayloads.last())

            // Second dormant Cloud chat reuses cached bare `{cascadeId}` variant on the very first LoadTrajectory call
            loadPayloads.clear()
            val steps2 = client.fetchAllTrajectorySteps(
                cascadeId = "v1/sync-mobile-concept-2",
                knownStepCount = 3,
                isCloud = true,
            )
            assertEquals(3, steps2.size)
            assertEquals(1, loadPayloads.size, "Subsequent dormant Cloud wakes must reuse learned bare {cascadeId} in 1 RTT")
            assertEquals(1, listInstancesCalls)
        }
    }

    @Test
    fun testCloudRelayFallbackToGetCascadeTrajectoryWhenStepsReturns404() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            val json = Json { ignoreUnknownKeys = true }
            var getTrajectoryCalls = 0

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/ProxyCommand") -> {
                        val (_, rpcPath, payloadText) = decodeProxyCommandInner(bytes.decodeToString())
                        val method = rpcPath.substringAfterLast('/')
                        val reqObj = runCatching { json.parseToJsonElement(payloadText) as? JsonObject }.getOrNull()
                        when (method) {
                            "GetCascadeTrajectorySteps" -> respond(
                                content = """[5,"not_found: trajectory not found (error ID: abc123)"]""",
                                status = HttpStatusCode.NotFound,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                            "LoadTrajectory" -> respond(
                                content = encodeJspbProxyResponse("{}"),
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                            "GetCascadeTrajectory" -> {
                                getTrajectoryCalls += 1
                                if (reqObj != null && "backend" in reqObj) {
                                    respond(
                                        content = """[3,"invalid_argument: unknown field \"backend\""]""",
                                        status = HttpStatusCode.BadRequest,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                } else {
                                    val wrapped = """{"trajectory":${buildJsonStepsPayload(0 until 2)}}"""
                                    respond(
                                        content = encodeJspbProxyResponse(wrapped),
                                        status = HttpStatusCode.OK,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                }
                            }
                            else -> respond("", HttpStatusCode.NotFound)
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(
                cascadeId = "v1/fallback-traj",
                knownStepCount = 2,
                isCloud = true,
            )
            assertEquals(2, steps.size)
            assertTrue(getTrajectoryCalls >= 2, "Should self-heal unknown backend and recover via GetCascadeTrajectory")
        }
    }

    @Test
    fun testLocalDormantTrajectoryWakesOnBinaryProtobuf404NotFound() = runTest {
        val recorded = mutableListOf<RecordedRequest>()
        var woken = false
        val protoPayload = buildBinaryPlannerSteps(count = 4)

        val engine = MockEngine { request ->
            val ct = request.body.contentType?.toString()
                ?: request.headers[HttpHeaders.ContentType].orEmpty()
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            recorded.add(RecordedRequest(request.url.encodedPath, ct, bytes))

            when {
                request.url.encodedPath.endsWith("/LoadTrajectory") -> {
                    woken = true
                    respond(
                        content = "{}",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json"),
                    )
                }
                request.url.encodedPath.endsWith("/GetCascadeTrajectorySteps") && ct.contains("application/proto") -> {
                    if (woken) {
                        respond(
                            content = protoPayload,
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/proto"),
                        )
                    } else {
                        respond(
                            content = """{"code":"not_found","message":"trajectory not found"}""",
                            status = HttpStatusCode.NotFound,
                            headers = headersOf(HttpHeaders.ContentType, "application/json"),
                        )
                    }
                }
                else -> respond("""{"steps":[]}""", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
            }
        }

        val client = AntigravityKmpRpcClient(
            host = testHost("mac-dormant-local"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )

        val steps = client.fetchAllTrajectorySteps(cascadeId = "cas-dormant-local", knownStepCount = 4)
        assertEquals(4, steps.size)
        assertEquals(2, recorded.count { it.isProto }, "Should retry Binary Protobuf directly after waking")
        assertEquals(1, recorded.count { it.path.endsWith("/LoadTrajectory") })
        assertEquals(0, recorded.count { it.path.endsWith("/GetCascadeTrajectorySteps") && it.isJson })
    }

    @Test
    fun testCloudJetboxSummariesPreserveCloudFlagForUuidSessionsAndFilterLocalFileUris() {
        val event = buildJsonObject {
            put(
                "updates",
                buildJsonObject {
                    put(
                        "9f2b14a1-4c22-4a91-9e12-1234567890ab",
                        buildJsonObject {
                            put("summary", "Sync Antigravity Mobile Concept")
                            put("status", "CASCADE_RUN_STATUS_IDLE")
                            put("stepCount", 42)
                        },
                    )
                    put(
                        "local-echoed-chat",
                        buildJsonObject {
                            put("summary", "Local workspace chat")
                            put("status", "CASCADE_RUN_STATUS_IDLE")
                            put("stepCount", 5)
                            put(
                                "workspaces",
                                buildJsonArray {
                                    add(buildJsonObject { put("workspaceFolderAbsoluteUri", "file:///Users/dev/local-repo") })
                                },
                            )
                        },
                    )
                },
            )
        }

        val decoded = JsonStepAndSummaryDecoder.decodeJetboxSummariesEvent(
            obj = event,
            nowEpochMs = 1_750_000_000_000L,
            forceCloud = true,
            originInstanceUuid = "inst-1",
            originHostName = "Antigravity",
        )
        assertEquals(1, decoded.summaries.size)
        val cloudItem = decoded.summaries.first()
        assertEquals("9f2b14a1-4c22-4a91-9e12-1234567890ab", cloudItem.cascadeId)
        assertTrue(cloudItem.isCloud)
        assertEquals("Antigravity", cloudItem.originHostName)
    }

    @Test
    fun testProtocolCompatibilityEngineBoqParsingTrajectory404AndUserFacingError() {
        val boqUnknownBackend = """[3,"invalid_argument: unknown field \"backend\""]"""
        assertEquals("backend", ProtocolCompatibilityEngine.extractUnknownProtoFieldName(boqUnknownBackend))

        val boqNotFound = """[5,"not_found: trajectory not found (error ID: 721ffeb9b0bb4fb6b2a971dfa56087e2)"]"""
        assertTrue(ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(404, boqNotFound))
        assertFalse(
            ProtocolCompatibilityEngine.isMethodUnimplementedResponse(404, boqNotFound),
            "Trajectory-level 404 must never be classified as method-unimplemented",
        )
        assertTrue(
            ProtocolCompatibilityEngine.isMethodUnimplementedResponse(
                404,
                """{"code":"unimplemented","message":"unknown method SendSideQuestion"}""",
            )
        )

        val formatted = ProtocolCompatibilityEngine.formatUserFacingRpcError(
            AntigravityRpcError.HttpError(404, boqNotFound)
        )
        assertFalse(formatted.contains("HTTP 404: HTTP 404:"), "Must never double HTTP status prefix")
        assertFalse(formatted.contains("[5,"), "Must unwrap Boq JSPB array envelope")
        assertTrue(formatted.contains("not_found: trajectory not found"))
    }

    @Test
    fun testCloudStreamAgentStateUpdatesLoadsActiveCloudTrajectoryWhenLegacyStepsReturns404() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            val cloudCascadeId = "v1/default/jetski_remote_agents_3p_devbox/356aa3f9-503f-447a-8319-3e1baae4c634"
            var streamCalls = 0
            var proxyCommandCalls = 0

            val metaFrameJson = """{"update":{"conversationId":"$cloudCascadeId","status":"CASCADE_RUN_STATUS_RUNNING"}}"""
            val stepsFrameJson = """{"update":{"conversationId":"$cloudCascadeId","status":"CASCADE_RUN_STATUS_RUNNING","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0,1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"items":[{"text":"聊天记录加载优化建议"}]}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_IN_PROGRESS","plannerResponse":{"response":"正在分析聊天记录加载路径..."}}]}}}}"""
            val connectStreamBytes = ConnectEnvelope.encode(metaFrameJson.encodeToByteArray()) +
                ConnectEnvelope.encode(stepsFrameJson.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
            val boqChunk = """["${connectStreamBytes.toByteString().base64()}",[["content-type","application/connect+json"]]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.34.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/StreamProxyCommand") -> {
                        streamCalls += 1
                        respond(
                            content = boqChunk,
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        proxyCommandCalls += 1
                        respond(
                            content = """[5,"not_found: trajectory not found (error ID: 356aa3f9503f447a83193e1baae4c634)"]""",
                            status = HttpStatusCode.NotFound,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(
                cascadeId = cloudCascadeId,
                knownStepCount = 2,
                isCloud = true,
            )
            assertEquals(2, steps.size)
            assertEquals(0, steps[0].stepIndex)
            assertEquals("聊天记录加载优化建议", steps[0].userInput)
            assertEquals(1, steps[1].stepIndex)
            assertEquals("正在分析聊天记录加载路径...", steps[1].plannerResponse?.response)
            assertEquals(1, streamCalls)
            assertEquals(0, proxyCommandCalls, "Cloud StreamAgentStateUpdates primary path must succeed without calling legacy ProxyCommand")
        }
    }

    @Test
    fun testLocalTrajectoryFallsBackToStreamAgentStateUpdatesWhenLegacyStepsReturns404() = runTest {
        withContext(Dispatchers.Default) {
            val localCid = "cas-local-sqlite-234"
            val frame1Json = """{"update":{"conversationId":"$localCid","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Inspect live turn"}}]}}}}"""
            val frame2Json = """{"update":{"conversationId":"$localCid","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Recovered via StreamAgentStateUpdates"}}]}}}}"""
            val streamBytes = ConnectEnvelope.encode(frame1Json.encodeToByteArray()) +
                ConnectEnvelope.encode(frame2Json.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)

            val engine = MockEngine { request ->
                if (request.url.encodedPath.endsWith("/StreamAgentStateUpdates")) {
                    respond(
                        content = streamBytes,
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/connect+json"),
                    )
                } else {
                    respond(
                        content = """{"code":"not_found","message":"trajectory not found"}""",
                        status = HttpStatusCode.NotFound,
                        headers = headersOf(HttpHeaders.ContentType, "application/json"),
                    )
                }
            }

            val client = AntigravityKmpRpcClient(
                host = testHost("mac-local-stream-fallback"),
                csrfToken = "test-csrf",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(
                cascadeId = localCid,
                knownStepCount = 2,
                isCloud = false,
            )
            assertEquals(2, steps.size)
            assertEquals(0, steps[0].stepIndex)
            assertEquals("Inspect live turn", steps[0].userInput)
            assertEquals(1, steps[1].stepIndex)
            assertEquals("Recovered via StreamAgentStateUpdates", steps[1].plannerResponse?.response)
        }
    }

    @Test
    fun testDecodeAgentStateStepsUpdateHandlesSparseIndicesAndSnakeCase() {
        val json = Json { ignoreUnknownKeys = true }
        val raw = json.parseToJsonElement(
            """
            {
              "update": {
                "status": "CASCADE_RUN_STATUS_RUNNING",
                "main_trajectory_update": {
                  "steps_update": {
                    "indices": [2, 5],
                    "total_length": 6,
                    "steps": [
                      {"type": "CORTEX_STEP_TYPE_USER_INPUT", "status": "CORTEX_STEP_STATUS_DONE", "userInput": {"text": "Second turn"}},
                      {"type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE", "status": "CORTEX_STEP_STATUS_DONE", "plannerResponse": {"response": "Fifth step answer"}}
                    ]
                  }
                }
              }
            }
            """.trimIndent(),
        ) as JsonObject

        val decoded = JsonStepAndSummaryDecoder.decodeAgentStateStepsUpdate(raw, cascadeId = "v1/sparse")
        assertTrue(decoded.hasMainTrajectoryUpdate)
        assertEquals(6, decoded.totalLength)
        assertEquals(2, decoded.steps.size)
        assertEquals(2, decoded.steps[0].stepIndex)
        assertEquals("Second turn", decoded.steps[0].userInput)
        assertEquals(5, decoded.steps[1].stepIndex)
        assertEquals("Fifth step answer", decoded.steps[1].plannerResponse?.response)
    }

    @Test
    fun testSendUserCascadeMessageWakesDormantTrajectoryOnSessionNotFound() = runTest {
        withContext(Dispatchers.Default) {
            val wokenIds = mutableSetOf<String>()
            var sendAttempts = 0
            var loadCalls = 0
            val json = Json { ignoreUnknownKeys = true }

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
                val reqObj = runCatching { json.parseToJsonElement(bytes.decodeToString()) as JsonObject }.getOrNull()
                val cid = (reqObj?.get("cascadeId") as? JsonPrimitive)?.contentOrNull.orEmpty()
                when {
                    path.endsWith("/LoadTrajectory") -> {
                        loadCalls += 1
                        wokenIds.add(cid)
                        respond(
                            content = "{}",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json"),
                        )
                    }
                    path.endsWith("/SendUserCascadeMessage") -> {
                        sendAttempts += 1
                        if (cid in wokenIds) {
                            respond(
                                content = "{}",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json"),
                            )
                        } else {
                            respond(
                                content = """{"code":"not_found","message":"session not found"}""",
                                status = HttpStatusCode.NotFound,
                                headers = headersOf(HttpHeaders.ContentType, "application/json"),
                            )
                        }
                    }
                    else -> respond("{}", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                }
            }

            val client = AntigravityKmpRpcClient(
                host = testHost("mac-wake-send"),
                csrfToken = "test-csrf",
                httpClientOverride = HttpClient(engine),
            )

            client.sendUserCascadeMessage(
                cascadeId = "cas-dormant-send",
                message = "Who is the most violent",
            )
            assertEquals(1, loadCalls, "Expected LoadTrajectory wake call on session not found")
            assertEquals(2, sendAttempts, "Expected retry after LoadTrajectory wake")
        }
    }

    @Test
    fun testSendUserCascadeMessageOverCloudRelayProbesPeerInstanceAndPinsTarget() = runTest {
        withContext(Dispatchers.Default) {
            val primaryUuid = "inst-primary-aaaa"
            val peerUuid = "inst-peer-bbbb"
            val cloudCascadeId = "v1/cloud-peer-pinned"
            val wokenOnPeer = mutableSetOf<String>()
            val sendTargets = mutableListOf<String>()
            val cancelTargets = mutableListOf<String>()
            val json = Json { ignoreUnknownKeys = true }

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$primaryUuid",["MacBook Pro","2.34.0",true],1,[1740000000,0]],["$peerUuid",["Studio Cloud Relay","2.34.0",true],1,[1740000001,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/ProxyCommand") -> {
                        val (targetUuid, rpcPath, payloadText) = decodeProxyCommandInner(bytes.decodeToString())
                        val method = rpcPath.substringAfterLast('/')
                        val reqObj = json.parseToJsonElement(payloadText) as JsonObject
                        val cid = (reqObj["cascadeId"] as? JsonPrimitive)?.contentOrNull.orEmpty()
                        when (method) {
                            "LoadTrajectory" -> {
                                if (targetUuid == peerUuid) {
                                    wokenOnPeer.add(cid)
                                    respond(
                                        content = encodeJspbProxyResponse("{}"),
                                        status = HttpStatusCode.OK,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                } else {
                                    respond(
                                        content = """[5,"not_found: session not found"]""",
                                        status = HttpStatusCode.NotFound,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                }
                            }
                            "SendUserCascadeMessage" -> {
                                sendTargets.add(targetUuid)
                                if (targetUuid == peerUuid && cid in wokenOnPeer) {
                                    respond(
                                        content = encodeJspbProxyResponse("{}"),
                                        status = HttpStatusCode.OK,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                } else {
                                    respond(
                                        content = """[5,"not_found: trajectory not found"]""",
                                        status = HttpStatusCode.NotFound,
                                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                    )
                                }
                            }
                            "CancelCascadeInvocation" -> {
                                cancelTargets.add(targetUuid)
                                respond(
                                    content = encodeJspbProxyResponse("{}"),
                                    status = HttpStatusCode.OK,
                                    headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                )
                            }
                            else -> respond(
                                content = encodeJspbProxyResponse("{}"),
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = primaryUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$primaryUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            // First send hits primary -> not_found -> wakes/probes peer -> succeeds & pins peerUuid
            client.sendUserCascadeMessage(
                cascadeId = cloudCascadeId,
                message = "First message",
                isCloud = true,
            )
            assertTrue(peerUuid in sendTargets, "Expected peer relay instance to handle Cloud send")

            // Subsequent send & cancel should route directly to pinned peerUuid without hitting primary
            sendTargets.clear()
            client.sendUserCascadeMessage(
                cascadeId = cloudCascadeId,
                message = "Second message",
                isCloud = true,
            )
            client.cancelCascadeInvocation(cloudCascadeId)
            assertEquals(listOf(peerUuid), sendTargets, "Subsequent send must use pinned peer instance directly")
            assertEquals(listOf(peerUuid), cancelTargets, "Cancel must use pinned peer instance directly")
        }
    }

    @Test
    fun testStartCascadeOverCloudRelayOmitsClientIdAndNegotiatesBackendType() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "inst-cloud-start-01"
            val startPayloads = mutableListOf<JsonObject>()
            val json = Json { ignoreUnknownKeys = true }

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.34.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/ProxyCommand") -> {
                        val (_, rpcPath, payloadText) = decodeProxyCommandInner(bytes.decodeToString())
                        val method = rpcPath.substringAfterLast('/')
                        val reqObj = json.parseToJsonElement(payloadText) as JsonObject
                        if (method == "StartCascade") {
                            startPayloads.add(reqObj)
                            if ("backend" in reqObj) {
                                respond(
                                    content = """[3,"invalid_argument: unknown field \"backend\""]""",
                                    status = HttpStatusCode.BadRequest,
                                    headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                )
                            } else {
                                respond(
                                    content = encodeJspbProxyResponse("""{"cascadeId":"v1/cloud-minted-99"}"""),
                                    status = HttpStatusCode.OK,
                                    headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                )
                            }
                        } else {
                            respond(
                                content = encodeJspbProxyResponse("{}"),
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val minted = client.startCascade(
                workspaceUri = "cloud://slardar_app_ai",
                isCloud = true,
                cloudProjectId = "cp-slardar",
            )
            assertEquals("v1/cloud-minted-99", minted)
            assertTrue(startPayloads.isNotEmpty())
            assertTrue(startPayloads.none { "cascadeId" in it }, "Cloud Relay StartCascade must not send client-invented cascadeId")
            assertEquals("BACKEND_TYPE_REMOTE_AICODE", (startPayloads.last()["backendType"] as? JsonPrimitive)?.contentOrNull)
        }
    }

    @Test
    fun testSendErrorFormattingRecognizesSessionNotFoundAndIsIdempotent() {
        assertTrue(
            ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(
                404,
                """{"code":"not_found","message":"session not found"}""",
            ),
        )
        assertTrue(
            ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(
                404,
                "agent state for cas-123 not found",
            ),
        )
        assertFalse(
            ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(
                401,
                "Google sign-in session not found",
            ),
        )

        val err = AntigravityRpcError.HttpError(
            statusCode = 404,
            body = """[5,"not_found: session not found"]""",
        )
        val formatted = ProtocolCompatibilityEngine.formatUserFacingSendError(err)
        assertTrue(formatted.contains("This conversation was not found on this host"))
        assertTrue(formatted.contains("session not found"))
        assertTrue(formatted.contains("Tap Retry or start a new chat."))

        // Re-formatting an already formatted user-facing message must NOT add "HTTP 500:" prefix
        val reWrapped = ProtocolCompatibilityEngine.formatUserFacingRpcError(
            AntigravityRpcError.HttpError(500, formatted),
        )
        assertEquals(formatted, reWrapped)
        assertFalse(reWrapped.contains("HTTP 500"))
    }

    @Test
    fun testSingleSliceJsonRepairReusesTailStepsAndCachesRepairedSteps() = runTest {
        val recorded = mutableListOf<RecordedRequest>()
        val json = Json { ignoreUnknownKeys = true }

        val step0 = encodeVarintField(1, 14) +
            encodeVarintField(4, 3) +
            encodeLd(19, encodeLd(1, "Open dashboard".encodeToByteArray()))
        val step1Unknown = encodeVarintField(1, 991) +
            encodeVarintField(4, 3) +
            encodeLd(91, "future-canvas-1".encodeToByteArray())
        val step2Unknown = encodeVarintField(1, 992) +
            encodeVarintField(4, 3) +
            encodeLd(92, "future-canvas-2".encodeToByteArray())
        val binaryPayload = encodeLd(1, step0) + encodeLd(1, step1Unknown) + encodeLd(1, step2Unknown)

        val engine = MockEngine { request ->
            val ct = request.body.contentType?.toString()
                ?: request.headers[HttpHeaders.ContentType].orEmpty()
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            recorded.add(RecordedRequest(request.url.encodedPath, ct, bytes))

            if (ct.contains("application/proto")) {
                respond(
                    content = binaryPayload,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/proto"),
                )
            } else {
                val reqObj = json.parseToJsonElement(bytes.decodeToString()) as JsonObject
                val offset = (reqObj["stepOffset"] as? JsonPrimitive)?.intOrNull ?: 0
                val tailSteps = buildJsonArray {
                    if (offset <= 1) {
                        add(
                            buildJsonObject {
                                put("type", "CORTEX_STEP_TYPE_FUTURE_WIDGET_A")
                                put("status", "CORTEX_STEP_STATUS_DONE")
                                put("futureWidgetA", buildJsonObject { put("summary", "Widget A repaired") })
                            },
                        )
                    }
                    if (offset <= 2) {
                        add(
                            buildJsonObject {
                                put("type", "CORTEX_STEP_TYPE_FUTURE_WIDGET_B")
                                put("status", "CORTEX_STEP_STATUS_DONE")
                                put("futureWidgetB", buildJsonObject { put("summary", "Widget B repaired") })
                            },
                        )
                    }
                }
                respond(
                    content = buildJsonObject { put("steps", tailSteps) }.toString(),
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
        }

        val client = AntigravityKmpRpcClient(
            host = testHost("mac-repair-reuse"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )

        // First fetch: 1 binary RPC + ONLY 1 JSON repair RPC (offset 1 returns [step1, step2] reused for step 2!)
        val first = client.fetchAllTrajectorySteps(cascadeId = "cas-reuse", knownStepCount = 3)
        assertEquals(3, first.size)
        assertEquals("CORTEX_STEP_TYPE_FUTURE_WIDGET_A", first[1].rawTypeName)
        assertEquals("Widget A repaired", first[1].fallbackSummary)
        assertEquals("CORTEX_STEP_TYPE_FUTURE_WIDGET_B", first[2].rawTypeName)
        assertEquals("Widget B repaired", first[2].fallbackSummary)
        assertEquals(1, recorded.count { it.isProto })
        assertEquals(1, recorded.count { it.isJson }, "Tail slice from offset=1 must satisfy both step 1 and step 2 in 1 RTT")

        // Second fetch: repaired steps are cached -> 0 JSON repair RPCs
        recorded.clear()
        val second = client.fetchAllTrajectorySteps(cascadeId = "cas-reuse", knownStepCount = 3)
        assertEquals(3, second.size)
        assertEquals("Widget A repaired", second[1].fallbackSummary)
        assertEquals("Widget B repaired", second[2].fallbackSummary)
        assertEquals(1, recorded.count { it.isProto })
        assertEquals(0, recorded.count { it.isJson }, "Cached repaired steps must require 0 JSON repair RPCs")
    }

    @Test
    fun testIncrementalBinaryDeltaSyncAndIgnoredOffsetDetection() = runTest {
        fun decodeProtoStepOffset(bytes: ByteArray): Int {
            val offsetRef = intArrayOf(0)
            while (offsetRef[0] < bytes.size) {
                val tag = ProtobufStepCodec.readVarint(bytes, offsetRef) ?: break
                val fieldNum = (tag shr 3).toInt()
                val wireType = (tag and 0x07UL).toInt()
                when (wireType) {
                    0 -> {
                        val v = ProtobufStepCodec.readVarint(bytes, offsetRef) ?: break
                        if (fieldNum == 2) return v.toInt()
                    }
                    2 -> {
                        val len = ProtobufStepCodec.readVarint(bytes, offsetRef) ?: break
                        offsetRef[0] += len.toInt()
                    }
                    else -> break
                }
            }
            return 0
        }

        fun buildSliceBinarySteps(indices: IntRange): ByteArray {
            val out = ArrayList<Byte>()
            for (i in indices) {
                val stepBytes = if (i % 2 == 0) {
                    encodeVarintField(1, 14) +
                        encodeVarintField(4, 3) +
                        encodeLd(19, encodeLd(1, "User prompt #$i".encodeToByteArray()))
                } else {
                    encodeVarintField(1, 15) +
                        encodeVarintField(4, 3) +
                        encodeLd(20, encodeLd(1, "Planner answer #$i".encodeToByteArray()))
                }
                out.addAll(encodeLd(1, stepBytes).toList())
            }
            return out.toByteArray()
        }

        // Case 1: Host honors step_offset -> incremental delta fetch from offset = existing.size - 1
        val offsetsHonored = mutableListOf<Int>()
        val honoringEngine = MockEngine { request ->
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            val offset = decodeProtoStepOffset(bytes)
            offsetsHonored.add(offset)
            val slice = buildSliceBinarySteps(offset until 6)
            respond(
                content = slice,
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/proto"),
            )
        }
        val honoringClient = AntigravityKmpRpcClient(
            host = testHost("mac-delta-ok"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(honoringEngine),
        )
        val initialFour = ProtobufStepCodec.decodeStepsResponse(buildSliceBinarySteps(0 until 4), "cas-delta")
        assertEquals(4, initialFour.size)

        val merged = honoringClient.fetchAllTrajectorySteps(
            cascadeId = "cas-delta",
            knownStepCount = 6,
            existingSteps = initialFour,
        )
        assertEquals(6, merged.size)
        assertEquals(listOf(3), offsetsHonored, "Incremental delta must request stepOffset = existing.size - 1 (anchor)")
        assertEquals("User prompt #0", merged[0].userInput)
        assertEquals("Planner answer #3", merged[3].plannerResponse?.response)
        assertEquals("User prompt #4", merged[4].userInput)
        assertEquals("Planner answer #5", merged[5].plannerResponse?.response)

        // Case 2: Host ignores step_offset (returns full 0..5 even when offset=3) -> merges cleanly & caches ignore flag
        val offsetsIgnored = mutableListOf<Int>()
        val ignoringEngine = MockEngine { request ->
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            offsetsIgnored.add(decodeProtoStepOffset(bytes))
            respond(
                content = buildSliceBinarySteps(0 until 6),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/proto"),
            )
        }
        val ignoringClient = AntigravityKmpRpcClient(
            host = testHost("mac-delta-ignored"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(ignoringEngine),
        )
        val fullFirst = ignoringClient.fetchAllTrajectorySteps(
            cascadeId = "cas-delta-ign",
            knownStepCount = 6,
            existingSteps = initialFour,
        )
        assertEquals(6, fullFirst.size)
        assertEquals(listOf(3), offsetsIgnored)

        // Next incremental call skips step_offset probe and goes straight to offset=0
        offsetsIgnored.clear()
        val fullSecond = ignoringClient.fetchAllTrajectorySteps(
            cascadeId = "cas-delta-ign",
            knownStepCount = 6,
            existingSteps = initialFour,
        )
        assertEquals(6, fullSecond.size)
        assertEquals(listOf(0), offsetsIgnored, "Hosts known to ignore binary stepOffset should skip delta probes")
    }

    @Test
    fun testCloudRelayProxyRequestIncludesGzipAndProtoAcceptHeaders() {
        val protoBody = CloudRelayJspbCodec.encodeProxyCommandRequest(
            targetInstanceUuid = "uuid-test",
            rpcPath = "/exa.language_server_pb.LanguageServerService/GetCascadeTrajectorySteps",
            payload = byteArrayOf(0x0A, 0x01, 0x61),
            contentType = "application/proto",
        ).decodeToString()
        assertTrue(protoBody.contains("""["accept-encoding","gzip"]"""), "Expected gzip accept-encoding in unary proxy request: $protoBody")
        assertTrue(protoBody.contains("""["accept","application/proto"]"""), "Expected application/proto accept header: $protoBody")

        val streamBody = CloudRelayJspbCodec.encodeProxyCommandRequest(
            targetInstanceUuid = "uuid-test",
            rpcPath = "/exa.language_server_pb.LanguageServerService/StreamAgentStateUpdates",
            payload = ConnectEnvelope.encode("""{"conversationId":"v1/c"}""".encodeToByteArray()),
            contentType = "application/connect+json",
            isStreaming = true,
        ).decodeToString()
        assertFalse(streamBody.contains("""["accept-encoding","gzip"]"""), "Streaming StreamProxyCommand must NOT send accept-encoding:gzip: $streamBody")
    }

    @Test
    fun testCloudRelayBinaryProtoJsonErrorInside200OkFallsBackAndCachesUnsupported() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "inst-relay-proto-415"
            var protoCalls = 0
            var jsonCalls = 0

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.34.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/ProxyCommand") -> {
                        val bodyText = bytes.decodeToString()
                        val isProto = bodyText.contains(""""content-type","application/proto"""")
                        if (isProto) {
                            protoCalls += 1
                            // Cloud Relay returns outer HTTP 200 wrapping inner Connect JSON 415 error
                            respond(
                                content = encodeJspbProxyResponse("""{"code":"invalid_argument","message":"unsupported media type application/proto"}"""),
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        } else {
                            jsonCalls += 1
                            respond(
                                content = encodeJspbProxyResponse(buildJsonStepsPayload(0 until 3)),
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val first = client.fetchAllTrajectorySteps(cascadeId = "cas-relay-proto-1", knownStepCount = 3, isCloud = false)
            assertEquals(3, first.size)
            assertEquals(1, protoCalls)
            assertEquals(1, jsonCalls)

            // Second fetch must remember binary protobuf is unsupported and go directly to JSON
            protoCalls = 0
            jsonCalls = 0
            val second = client.fetchAllTrajectorySteps(cascadeId = "cas-relay-proto-2", knownStepCount = 3, isCloud = false)
            assertEquals(3, second.size)
            assertEquals(0, protoCalls, "Unsupported binary protobuf over Cloud Relay must be cached per host")
            assertEquals(1, jsonCalls)
        }
    }

    @Test
    fun testLargeHistoricalBinaryTrajectorySkipsFullTailJsonRepairAndCachesHousekeepingType() = runTest {
        fun buildTrajectoryWithUnknown(totalSteps: Int, unknownIdx: Int, unknownWireType: Int): ByteArray {
            val out = ArrayList<Byte>()
            for (i in 0 until totalSteps) {
                val stepBytes = when (i) {
                    unknownIdx -> encodeVarintField(1, unknownWireType) +
                        encodeVarintField(4, 3) +
                        encodeLd(95, "housekeeping-$i".encodeToByteArray())
                    else -> if (i % 2 == 0) {
                        encodeVarintField(1, 14) +
                            encodeVarintField(4, 3) +
                            encodeLd(19, encodeLd(1, "User #$i".encodeToByteArray()))
                    } else {
                        encodeVarintField(1, 15) +
                            encodeVarintField(4, 3) +
                            encodeLd(20, encodeLd(1, "Answer #$i".encodeToByteArray()))
                    }
                }
                out.addAll(encodeLd(1, stepBytes).toList())
            }
            return out.toByteArray()
        }

        val large40Binary = buildTrajectoryWithUnknown(totalSteps = 40, unknownIdx = 2, unknownWireType = 995)
        val small5Binary = buildTrajectoryWithUnknown(totalSteps = 5, unknownIdx = 3, unknownWireType = 996)
        var protoCalls = 0
        var jsonCalls = 0
        var serveSmall = false

        val engine = MockEngine { request ->
            val ct = request.body.contentType?.toString()
                ?: request.headers[HttpHeaders.ContentType].orEmpty()
            if (ct.contains("application/proto")) {
                protoCalls += 1
                respond(
                    content = if (serveSmall) small5Binary else large40Binary,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/proto"),
                )
            } else {
                jsonCalls += 1
                respond(
                    content = """{"steps":[{"type":"CORTEX_STEP_TYPE_CONVERSATION_HISTORY","status":"CORTEX_STEP_STATUS_DONE"},{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"User #4"}}]}""",
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/json"),
                )
            }
        }

        val client = AntigravityKmpRpcClient(
            host = testHost("mac-bounded-repair"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )

        // 1. 40-step trajectory with unknown non-waiting step at index 2 (tailSpan=38 > 24) -> 0 JSON repair RPCs
        val largeSteps = client.fetchAllTrajectorySteps(cascadeId = "cas-large-40", knownStepCount = 40)
        assertEquals(40, largeSteps.size)
        assertEquals(1, protoCalls)
        assertEquals(0, jsonCalls, "Large historical trajectory must not download multi-MB full-tail JSON for non-waiting unknown wire types")

        // 2. Small trajectory (tailSpan <= 24) probes once, learns STEP_TYPE_996 is housekeeping, and skips on subsequent chats
        serveSmall = true
        protoCalls = 0
        jsonCalls = 0
        val smallFirst = client.fetchAllTrajectorySteps(cascadeId = "cas-small-hk-1", knownStepCount = 5)
        assertEquals(5, smallFirst.size)
        assertEquals(1, protoCalls)
        assertEquals(1, jsonCalls)

        protoCalls = 0
        jsonCalls = 0
        val smallSecond = client.fetchAllTrajectorySteps(cascadeId = "cas-small-hk-2", knownStepCount = 5)
        assertEquals(5, smallSecond.size)
        assertEquals(1, protoCalls)
        assertEquals(0, jsonCalls, "Learned housekeeping wire type must skip JSON repair on subsequent trajectories")
    }

    @Test
    fun testLocal2xDormantTrajectoryShortCircuitsToStreamWithoutDuplicateWakeOrJsonProbes() = runTest {
        withContext(Dispatchers.Default) {
            val localCid = "cas-local-2x-fast-stream"
            val frame1 = """{"update":{"conversationId":"$localCid","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0,1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Open history fast"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Loaded in 1 stream RTT"}}]}}}}"""
            val streamPayload = ConnectEnvelope.encode(frame1.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)

            var loadTrajectoryCalls = 0
            var jsonStepsCalls = 0
            var protoStepsCalls = 0
            var streamCalls = 0

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val ct = request.body.contentType?.toString()
                    ?: request.headers[HttpHeaders.ContentType].orEmpty()
                when {
                    path.endsWith("/LoadTrajectory") -> {
                        loadTrajectoryCalls += 1
                        respond("{}", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                    }
                    path.endsWith("/GetCascadeTrajectorySteps") -> {
                        if (ct.contains("application/proto")) {
                            protoStepsCalls += 1
                        } else {
                            jsonStepsCalls += 1
                        }
                        respond(
                            content = """{"code":"not_found","message":"trajectory not found"}""",
                            status = HttpStatusCode.NotFound,
                            headers = headersOf(HttpHeaders.ContentType, "application/json"),
                        )
                    }
                    path.endsWith("/StreamAgentStateUpdates") -> {
                        streamCalls += 1
                        respond(
                            content = streamPayload,
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/connect+json"),
                        )
                    }
                    else -> respond(
                        content = """{"code":"not_found","message":"not found"}""",
                        status = HttpStatusCode.NotFound,
                        headers = headersOf(HttpHeaders.ContentType, "application/json"),
                    )
                }
            }

            val client = AntigravityKmpRpcClient(
                host = testHost("mac-2x-shortcircuit"),
                csrfToken = "test-csrf",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(cascadeId = localCid, knownStepCount = 2, isCloud = false)
            assertEquals(2, steps.size)
            assertEquals("Loaded in 1 stream RTT", steps[1].plannerResponse?.response)
            assertEquals(1, loadTrajectoryCalls, "Must not call LoadTrajectory twice across Path 1 and Path 2")
            assertEquals(0, jsonStepsCalls, "Must skip doomed JSON GetCascadeTrajectorySteps probes when proto already confirmed 404 after wake")
            assertEquals(2, protoStepsCalls, "Expected initial proto attempt + single post-wake retry")
            assertEquals(1, streamCalls, "Must jump directly to StreamAgentStateUpdates")
        }
    }

    @Test
    fun testCloudStreamAuthoritativeEmptySkipsLegacyFallbackRpcs() = runTest {
        withContext(Dispatchers.Default) {
            val cloudCid = "v1/cloud-authoritative-empty"
            val emptyFrame = """{"update":{"conversationId":"$cloudCid","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[],"totalLength":0,"steps":[]}}}}"""
            val streamPayload = ConnectEnvelope.encode(emptyFrame.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)

            var streamCalls = 0
            var legacyCalls = 0

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                if (path.endsWith("/StreamAgentStateUpdates")) {
                    streamCalls += 1
                    respond(
                        content = streamPayload,
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/connect+json"),
                    )
                } else {
                    legacyCalls += 1
                    respond("""{"code":"not_found"}""", HttpStatusCode.NotFound, headersOf(HttpHeaders.ContentType, "application/json"))
                }
            }

            val client = AntigravityKmpRpcClient(
                host = testHost("cloud-empty-fast"),
                csrfToken = "test-csrf",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(cascadeId = cloudCid, knownStepCount = 0, isCloud = true)
            assertTrue(steps.isEmpty())
            assertEquals(2, streamCalls, "Cloud empty stub on Variant #1 probes Variant #2 backend before settling authoritative empty")
            assertEquals(0, legacyCalls, "Authoritative empty Cloud snapshot must NOT fall through to legacy GetCascadeTrajectorySteps/LoadTrajectory probes")
        }
    }

    @Test
    fun testCloudRelayMultiWindowPeerProbeRunsInParallel() = runTest {
        withContext(Dispatchers.Default) {
            val primaryUuid = "inst-par-primary"
            val peer1 = "inst-par-peer-1"
            val peer2 = "inst-par-peer-2"
            val peer3 = "inst-par-peer-3"
            val cloudCid = "v1/cloud-par-peer"
            val winnerFrame = """{"update":{"conversationId":"$cloudCid","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0],"totalLength":1,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Found on peer 3 in parallel"}}]}}}}"""
            val winnerStream = ConnectEnvelope.encode(winnerFrame.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
            val winnerB64 = winnerStream.toByteString().base64()

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$primaryUuid",["Primary","2.34.0",true],1,[1740000000,0]],["$peer1",["Window 1","2.34.0",true],1,[1740000001,0]],["$peer2",["Window 2","2.34.0",true],1,[1740000002,0]],["$peer3",["Window 3","2.34.0",true],1,[1740000003,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/StreamProxyCommand") -> {
                        val (targetUuid, _, _) = decodeProxyCommandInner(bytes.decodeToString())
                        when (targetUuid) {
                            peer3 -> respond(
                                content = """[["$winnerB64",[["content-type","application/connect+json"]]]]""",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                            peer1, peer2 -> {
                                kotlinx.coroutines.delay(150)
                                respond("""[5,"not_found: trajectory not found"]""", HttpStatusCode.NotFound, headersOf(HttpHeaders.ContentType, "application/json+protobuf"))
                            }
                            else -> respond("""[5,"not_found: trajectory not found"]""", HttpStatusCode.NotFound, headersOf(HttpHeaders.ContentType, "application/json+protobuf"))
                        }
                    }
                    else -> respond("""[5,"not_found: trajectory not found"]""", HttpStatusCode.NotFound, headersOf(HttpHeaders.ContentType, "application/json+protobuf"))
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = primaryUuid,
                    hostname = "Primary",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$primaryUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(cascadeId = cloudCid, knownStepCount = 1, isCloud = true)
            assertEquals(1, steps.size)
            assertEquals("Found on peer 3 in parallel", steps.first().userInput)
        }
    }

    @Test
    fun testCloudStreamAgentStateUpdatesDoesNotAbortOnEmptyZeroStubAndTriesBackendVariant() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "inst-cloud-stub-1"
            val cloudCascadeId = "v1/default/jetski_remote_agents_3p_devbox/xcode-signing-analysis"
            var streamAttempt = 0
            val seenBackends = mutableListOf<String?>()
            val json = Json { ignoreUnknownKeys = true }

            val emptyStubFrame = """{"update":{"conversationId":"$cloudCascadeId","mainTrajectoryUpdate":{"stepsUpdate":{"totalLength":0}}}}"""
            val emptyStreamBytes = ConnectEnvelope.encode(emptyStubFrame.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
            val emptyBoqChunk = """["${emptyStreamBytes.toByteString().base64()}",[["content-type","application/connect+json"]]]"""

            val realStepsFrame = """{"update":{"conversationId":"$cloudCascadeId","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0,1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Xcode签名丢失原因分析"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"根因是 xcodegen 重新生成覆盖了自动签名配置。"}}]}}}}"""
            val realStreamBytes = ConnectEnvelope.encode(realStepsFrame.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
            val realBoqChunk = """["${realStreamBytes.toByteString().base64()}",[["content-type","application/connect+json"]]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bodyText = ((request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)).decodeToString()
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.34.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/StreamProxyCommand") -> {
                        streamAttempt += 1
                        val jspbArr = json.parseToJsonElement(bodyText) as JsonArray
                        val b64Inner = (jspbArr[2] as JsonPrimitive).content
                        val framed = CloudRelayJspbCodec.decodeBase64Flexible(b64Inner) ?: ByteArray(0)
                        val innerJsonStr = if (framed.size > 5) framed.copyOfRange(5, framed.size).decodeToString() else "{}"
                        val innerObj = json.parseToJsonElement(innerJsonStr) as JsonObject
                        val backendVal = (innerObj["backend"] as? JsonPrimitive)?.contentOrNull
                        seenBackends.add(backendVal)
                        val respChunk = if (backendVal == "BACKEND_TYPE_REMOTE_AICODE") realBoqChunk else emptyBoqChunk
                        respond(
                            content = respChunk,
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("{}", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json+protobuf"))
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(
                cascadeId = cloudCascadeId,
                knownStepCount = 2,
                isCloud = true,
            )
            assertEquals(2, steps.size)
            assertEquals("Xcode签名丢失原因分析", steps[0].userInput)
            assertTrue(steps[1].plannerResponse?.response?.contains("自动签名配置") == true)
            assertEquals(listOf(null, "BACKEND_TYPE_REMOTE_AICODE"), seenBackends)
        }
    }

    @Test
    fun testDormantCloudTrajectoryRetriesStreamAgentStateUpdatesAfterLoadTrajectoryWake() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "inst-cloud-dormant-wake"
            val cloudCascadeId = "v1/default/jetski_remote_agents_3p_devbox/dormant-cloud-wake"
            var isWoken = false
            var loadCalls = 0
            var streamCalls = 0
            val json = Json { ignoreUnknownKeys = true }

            val emptyStreamBytes = ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
            val emptyBoqChunk = """["${emptyStreamBytes.toByteString().base64()}",[["content-type","application/connect+json"]]]"""

            val wokeFrame = """{"update":{"conversationId":"$cloudCascadeId","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0,1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"唤醒历史云端对话"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"已成功从云端恢复历史轨迹。"}}]}}}}"""
            val wokeStreamBytes = ConnectEnvelope.encode(wokeFrame.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
            val wokeBoqChunk = """["${wokeStreamBytes.toByteString().base64()}",[["content-type","application/connect+json"]]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bodyText = ((request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)).decodeToString()
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.34.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/StreamProxyCommand") -> {
                        streamCalls += 1
                        respond(
                            content = if (isWoken) wokeBoqChunk else emptyBoqChunk,
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val jspbArr = json.parseToJsonElement(bodyText) as JsonArray
                        val rpcPath = (jspbArr[1] as JsonPrimitive).content
                        if (rpcPath.endsWith("/LoadTrajectory")) {
                            loadCalls += 1
                            isWoken = true
                            val okB64 = "{}".encodeToByteArray().toByteString().base64()
                            respond(
                                content = """["$okB64",[["content-type","application/json"]]]""",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        } else {
                            // Legacy GetCascadeTrajectorySteps / GetCascadeTrajectory return 404 on Antigravity 2.x Cloud
                            respond(
                                content = """[5,"not_found: trajectory not found"]""",
                                status = HttpStatusCode.NotFound,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(
                cascadeId = cloudCascadeId,
                knownStepCount = 2,
                isCloud = true,
            )
            assertTrue(loadCalls >= 1, "Expected LoadTrajectory wake call")
            assertTrue(streamCalls >= 2, "Expected StreamAgentStateUpdates retry after LoadTrajectory wake")
            assertEquals(2, steps.size)
            assertEquals("唤醒历史云端对话", steps[0].userInput)
            assertEquals("已成功从云端恢复历史轨迹。", steps[1].plannerResponse?.response)
        }
    }

    @Test
    fun testDecodeAgentStateStepsUpdateHandlesAlternativeWrappersAndSnakeCaseSteps() {
        val json = Json { ignoreUnknownKeys = true }
        val raw = json.parseToJsonElement(
            """
            {
              "agentStateUpdate": {
                "mainTrajectory": {
                  "trajectory": {
                    "total_length": 4,
                    "steps": [
                      {"type": "CORTEX_STEP_TYPE_USER_INPUT", "status": "CORTEX_STEP_STATUS_DONE", "user_input": {"items": [{"item": {"text": "为什么进来显示空白"}}]}},
                      {"type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE", "status": "CORTEX_STEP_STATUS_DONE", "planner_response": {"modified_response": "已定位根因并修复"}}
                    ]
                  }
                }
              }
            }
            """.trimIndent(),
        ) as JsonObject

        val decoded = JsonStepAndSummaryDecoder.decodeAgentStateStepsUpdate(raw, cascadeId = "v1/alt")
        assertTrue(decoded.hasMainTrajectoryUpdate)
        assertEquals(4, decoded.totalLength)
        assertEquals(2, decoded.steps.size)
        assertEquals("为什么进来显示空白", decoded.steps[0].userInput)
        assertEquals("已定位根因并修复", decoded.steps[1].plannerResponse?.response)
    }

    @Test
    fun testTailFirstFastPaintEmitsRecentSliceBeforeFullBackfillAndCachesOffsetIgnoringHost() = runTest {
        fun encodeVarint(value: Int): ByteArray {
            var v = value
            val out = mutableListOf<Byte>()
            while (v > 0x7F) {
                out.add(((v and 0x7F) or 0x80).toByte())
                v = v ushr 7
            }
            out.add((v and 0x7F).toByte())
            return out.toByteArray()
        }

        fun encodeTagLen(tag: Int, payload: ByteArray): ByteArray =
            encodeVarint(tag) + encodeVarint(payload.size) + payload

        fun buildSliceBinarySteps(indices: IntRange): ByteArray {
            val out = mutableListOf<Byte>()
            for (idx in indices) {
                val inner = if (idx % 2 == 0) {
                    val text = "User #$idx".encodeToByteArray()
                    val ui = encodeTagLen(0x0A, text)
                    byteArrayOf(0x08, 0x05, 0x10, 0x03) + encodeTagLen(0x2A, ui)
                } else {
                    val text = "Reply #$idx".encodeToByteArray()
                    val pr = encodeTagLen(0x0A, text)
                    byteArrayOf(0x08, 0x0A, 0x10, 0x03) + encodeTagLen(0x7A, pr)
                }
                for (b in encodeTagLen(0x0A, inner)) out.add(b)
            }
            return out.toByteArray()
        }

        fun decodeProtoStepOffset(req: ByteArray): Int {
            var pos = 0
            while (pos < req.size) {
                val tag = req[pos++].toInt() and 0xFF
                val fieldNum = tag ushr 3
                val wireType = tag and 0x07
                if (wireType == 2) {
                    var len = 0
                    var shift = 0
                    while (pos < req.size) {
                        val b = req[pos++].toInt() and 0xFF
                        len = len or ((b and 0x7F) shl shift)
                        if ((b and 0x80) == 0) break
                        shift += 7
                    }
                    pos += len
                } else if (wireType == 0) {
                    var v = 0
                    var shift = 0
                    while (pos < req.size) {
                        val b = req[pos++].toInt() and 0xFF
                        v = v or ((b and 0x7F) shl shift)
                        if ((b and 0x80) == 0) break
                        shift += 7
                    }
                    if (fieldNum == 2) return v
                }
            }
            return 0
        }

        // Case 1: Host honors stepOffset -> first partial emit delivers 48-step tail (52..99), second fills 0..99
        val requestedOffsets = mutableListOf<Int>()
        val partialSnapshots = mutableListOf<List<CascadeStep>>()
        val engine = MockEngine { request ->
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            val offset = decodeProtoStepOffset(bytes)
            requestedOffsets.add(offset)
            respond(
                content = buildSliceBinarySteps(offset until 100),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/proto"),
            )
        }
        val client = AntigravityKmpRpcClient(
            host = testHost("mac-tail-fast"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )
        val full = client.fetchAllTrajectorySteps(
            cascadeId = "cas-long-100",
            knownStepCount = 100,
            onPartialSteps = { partialSnapshots.add(it) },
        )
        assertEquals(100, full.size)
        assertEquals(listOf(52, 0), requestedOffsets, "Long uncached chat must fetch tail 52..99 first, then backfill 0..99")
        assertTrue(partialSnapshots.isNotEmpty(), "Expected immediate partial paint callback")
        assertEquals(48, partialSnapshots.first().size, "First partial paint must contain the 48 tail steps")
        assertEquals(52, partialSnapshots.first().first().stepIndex)
        assertEquals(99, partialSnapshots.first().last().stepIndex)

        // Case 2: Host ignores stepOffset -> returns all 100 steps in 1 RTT without wasting a second request
        val ignoredOffsets = mutableListOf<Int>()
        val ignoredEngine = MockEngine { request ->
            val bytes = (request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)
            ignoredOffsets.add(decodeProtoStepOffset(bytes))
            respond(
                content = buildSliceBinarySteps(0 until 100),
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/proto"),
            )
        }
        val ignoredClient = AntigravityKmpRpcClient(
            host = testHost("mac-tail-ignored"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(ignoredEngine),
        )
        val ignoredPartials = mutableListOf<List<CascadeStep>>()
        val fullSingleRtt = ignoredClient.fetchAllTrajectorySteps(
            cascadeId = "cas-long-ignored",
            knownStepCount = 100,
            onPartialSteps = { ignoredPartials.add(it) },
        )
        assertEquals(100, fullSingleRtt.size)
        assertEquals(listOf(52), ignoredOffsets, "Host ignoring stepOffset must finish in 1 RTT without a redundant second fetch")
        assertEquals(0, fullSingleRtt.first().stepIndex)
        assertEquals(99, fullSingleRtt.last().stepIndex)
    }

    @Test
    fun testStreamAgentStateUpdatesEmitsRealTimeFramesWithStatusAndMergesSparseIndices() = runTest {
        val cid = "cas-live-stream-1"
        val frame1 = ConnectEnvelope.encode(
            """{"update":{"status":"CASCADE_RUN_STATUS_RUNNING","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"items":[{"text":"Optimize loading"}]}}]}}}}""".encodeToByteArray()
        )
        val frame2 = ConnectEnvelope.encode(
            """{"update":{"status":"CASCADE_RUN_STATUS_IDLE","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Done streaming!"}}]}}}}""".encodeToByteArray()
        )
        val endFrame = ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
        val combined = frame1 + frame2 + endFrame

        val engine = MockEngine { request ->
            if (request.url.encodedPath.endsWith("/StreamAgentStateUpdates")) {
                respond(
                    content = combined,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "application/connect+json"),
                )
            } else {
                respond("", HttpStatusCode.NotFound)
            }
        }

        val client = AntigravityKmpRpcClient(
            host = testHost("mac-live-stream"),
            csrfToken = "test-csrf",
            httpClientOverride = HttpClient(engine),
        )
        val updates = mutableListOf<AgentStateLiveUpdate>()
        client.streamAgentStateUpdates(cascadeId = cid).collect { updates.add(it) }

        assertEquals(2, updates.size, "Expected 2 real-time frames emitted progressively")
        assertEquals("CASCADE_RUN_STATUS_RUNNING", updates[0].runStatus)
        assertEquals(1, updates[0].steps.size)
        assertFalse(updates[0].isSnapshotComplete)

        assertEquals("CASCADE_RUN_STATUS_IDLE", updates[1].runStatus)
        assertEquals(2, updates[1].steps.size)
        assertTrue(updates[1].isSnapshotComplete)
        assertEquals("Optimize loading", updates[1].steps[0].userInput)
        assertEquals("Done streaming!", updates[1].steps[1].plannerResponse?.response)
    }

    @Test
    fun testZeroBoxingConnectAndCloudRelayStreamParsersHandleChunkedMultiFramePayloads() {
        val payloadA = """{"step":1,"msg":"${"A".repeat(4096)}"}""".encodeToByteArray()
        val payloadB = """{"step":2,"msg":"${"B".repeat(2048)}"}""".encodeToByteArray()
        val framed = ConnectEnvelope.encode(payloadA) + ConnectEnvelope.encode(payloadB)

        // Feed in tiny 73-byte slices to stress cursor compaction & buffer growth
        val connectParser = ConnectStreamParser()
        val parsedFrames = mutableListOf<ConnectEnvelopeFrame>()
        var offset = 0
        while (offset < framed.size) {
            val end = minOf(framed.size, offset + 73)
            parsedFrames.addAll(connectParser.feed(framed.copyOfRange(offset, end)))
            offset = end
        }
        assertEquals(2, parsedFrames.size)
        assertEquals(payloadA.decodeToString(), parsedFrames[0].payload.decodeToString())
        assertEquals(payloadB.decodeToString(), parsedFrames[1].payload.decodeToString())
        assertFalse(connectParser.hasBufferedBytes)

        // Stress StreamingBase64Decoder + CloudRelayJspbStreamParser in small chunks
        val innerB64 = okio.ByteString.of(*framed).base64()
        val jspbStream = ")]}'\n[[[\"$innerB64\",[]]]]".encodeToByteArray()
        val outerB64 = okio.ByteString.of(*jspbStream).base64().encodeToByteArray()
        val b64Decoder = StreamingBase64Decoder()
        val jspbParser = CloudRelayJspbStreamParser()
        val chunks = mutableListOf<ByteArray>()
        var pos = 0
        while (pos < outerB64.size) {
            val end = minOf(outerB64.size, pos + 137)
            val decoded = b64Decoder.feed(outerB64.copyOfRange(pos, end))
            chunks.addAll(jspbParser.feed(decoded))
            pos = end
        }
        chunks.addAll(jspbParser.feed(b64Decoder.flush()))
        assertEquals(1, chunks.size)
        assertEquals(framed.size, chunks[0].size)
        assertTrue(framed.contentEquals(chunks[0]))
    }

    @Test
    fun testCloudStreamAgentStateUpdatesUsesProdUiEmptyMetadataAndTailFirstPageUpdateBackfill() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "inst-cloud-prod-ui-paging"
            val cloudCid = "v1/default/jetski_remote_agents_3p_devbox/app-bug-report-100"
            val json = Json { ignoreUnknownKeys = true }

            val observedStreamRequest = CompletableDeferred<JsonObject>()
            val observedProxyHeaders = CompletableDeferred<String>()
            val observedPageUpdateReq = CompletableDeferred<JsonObject>()
            val streamChannel = ByteChannel(autoFlush = true)

            fun buildStepJsonRange(indices: IntRange): String = indices.joinToString(",") { idx ->
                if (idx % 2 == 0) {
                    """{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Cloud prompt #$idx"}}"""
                } else {
                    """{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Cloud answer #$idx"}}"""
                }
            }

            // Frame 1 uses `pageBounds.startIndex = 50` (omitting `indices`) to verify decoder `pageBounds` fallback
            val tailFrameJson = """{"update":{"conversationId":"$cloudCid","mainTrajectoryUpdate":{"stepsUpdate":{"pageBounds":{"startIndex":50},"totalLength":100,"steps":[${buildStepJsonRange(50..99)}]}}}}"""
            val tailFramed = ConnectEnvelope.encode(tailFrameJson.encodeToByteArray())
            val tailBoqPrefix = """[["${tailFramed.toByteString().base64()}",[["content-type","application/connect+json"]]]"""

            val headFrameJson = """{"update":{"conversationId":"$cloudCid","mainTrajectoryUpdate":{"stepsUpdate":{"pageBounds":{"startIndex":0,"endIndexExclusive":50},"totalLength":100,"steps":[${buildStepJsonRange(0..49)}]}}}}"""
            val headFramed = ConnectEnvelope.encode(headFrameJson.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
            val headBoqSuffix = """,["${headFramed.toByteString().base64()}"]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bodyText = ((request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)).decodeToString()
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/StreamProxyCommand") -> {
                        observedProxyHeaders.complete(bodyText)
                        val jspbArr = json.parseToJsonElement(bodyText) as JsonArray
                        val framed = CloudRelayJspbCodec.decodeBase64Flexible((jspbArr[2] as JsonPrimitive).content) ?: ByteArray(0)
                        val innerJson = if (framed.size > 5) framed.copyOfRange(5, framed.size).decodeToString() else "{}"
                        observedStreamRequest.complete(json.parseToJsonElement(innerJson) as JsonObject)
                        // Write tail Frame 1 immediately and leave stream open for RequestAgentStatePageUpdate backfill
                        streamChannel.writeFully(tailBoqPrefix.encodeToByteArray())
                        respond(
                            content = streamChannel,
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val jspbArr = json.parseToJsonElement(bodyText) as JsonArray
                        val rpcPath = (jspbArr[1] as JsonPrimitive).content
                        if (rpcPath.endsWith("/RequestAgentStatePageUpdate")) {
                            val decoded = CloudRelayJspbCodec.decodeBase64Flexible((jspbArr[2] as JsonPrimitive).content)
                                ?.decodeToString()
                                .orEmpty()
                            observedPageUpdateReq.complete(json.parseToJsonElement(decoded) as JsonObject)
                            // Emit Frame 2 (steps 0..49) + EndStream over the open StreamAgentStateUpdates channel
                            launch {
                                streamChannel.writeFully(headBoqSuffix.encodeToByteArray())
                                streamChannel.flushAndClose()
                            }
                            val okB64 = "{}".encodeToByteArray().toByteString().base64()
                            respond(
                                content = """["$okB64",[["content-type","application/json"]]]""",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        } else {
                            respond("""[5,"not_found: trajectory not found"]""", HttpStatusCode.NotFound)
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val partialPaints = mutableListOf<List<CascadeStep>>()
            val allSteps = client.fetchAllTrajectorySteps(
                cascadeId = cloudCid,
                knownStepCount = 100,
                isCloud = true,
                onPartialSteps = { partialPaints.add(it) },
            )

            val streamReq = observedStreamRequest.await()
            val rawProxyReq = observedProxyHeaders.await()
            assertTrue(
                rawProxyReq.contains("""["connect-accept-encoding","gzip"]"""),
                "Streaming StreamProxyCommand should advertise connect-accept-encoding:gzip: $rawProxyReq",
            )
            assertFalse(
                rawProxyReq.contains("""["accept-encoding","gzip"]"""),
                "Streaming StreamProxyCommand must NOT send HTTP accept-encoding:gzip",
            )
            assertEquals("CLIENT_TRAJECTORY_VERBOSITY_PROD_UI", (streamReq["trajectoryVerbosity"] as? JsonPrimitive)?.contentOrNull)
            assertEquals(0, ((streamReq["initialGeneratorMetadatasPageBounds"] as? JsonObject)?.get("endIndexExclusive") as? JsonPrimitive)?.intOrNull)
            assertEquals(0, ((streamReq["initialExecutorMetadatasPageBounds"] as? JsonObject)?.get("endIndexExclusive") as? JsonPrimitive)?.intOrNull)
            assertEquals(50, ((streamReq["initialStepsPageBounds"] as? JsonObject)?.get("startIndex") as? JsonPrimitive)?.intOrNull)

            val pageUpdate = observedPageUpdateReq.await()
            assertEquals(cloudCid, (pageUpdate["conversationId"] as? JsonPrimitive)?.contentOrNull)
            assertEquals(
                (streamReq["subscriberId"] as? JsonPrimitive)?.contentOrNull,
                (pageUpdate["subscriberId"] as? JsonPrimitive)?.contentOrNull,
            )
            assertEquals(0, ((pageUpdate["stepPageBounds"] as? JsonObject)?.get("startIndex") as? JsonPrimitive)?.intOrNull)

            assertTrue(partialPaints.isNotEmpty(), "Expected immediate Frame 1 tail fast-paint callback")
            assertEquals(50, partialPaints.first().size, "First paint must deliver the 50 tail steps (50..99)")
            assertEquals(50, partialPaints.first().first().stepIndex)
            assertEquals(99, partialPaints.first().last().stepIndex)

            assertEquals(100, allSteps.size, "Backfill over open stream must complete all 100 steps")
            assertEquals(0, allSteps.first().stepIndex)
            assertEquals("Cloud prompt #0", allSteps.first().userInput)
            assertEquals(99, allSteps.last().stepIndex)
            assertEquals("Cloud answer #99", allSteps.last().plannerResponse?.response)
        }
    }

    @Test
    fun testCloudStreamAgentStateUpdatesSelfHealsUnknownOptionalFieldsAndCachesStripped() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "inst-cloud-older-schema"
            val cloudCid = "v1/default/jetski_remote_agents_3p_devbox/older-desktop-stream"
            val json = Json { ignoreUnknownKeys = true }
            var streamAttempts = 0

            val successFrame = """{"update":{"conversationId":"$cloudCid","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0],"totalLength":1,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Self-healed older host"}}]}}}}"""
            val successFramed = ConnectEnvelope.encode(successFrame.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
            val successBoq = """["${successFramed.toByteString().base64()}",[["content-type","application/connect+json"]]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bodyText = ((request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)).decodeToString()
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["Older Mac","2.26.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/StreamProxyCommand") -> {
                        streamAttempts += 1
                        val jspbArr = json.parseToJsonElement(bodyText) as JsonArray
                        val framed = CloudRelayJspbCodec.decodeBase64Flexible((jspbArr[2] as JsonPrimitive).content) ?: ByteArray(0)
                        val innerObj = json.parseToJsonElement(framed.copyOfRange(5, framed.size).decodeToString()) as JsonObject
                        // Simulate direct non-enveloped Connect JSON error inside StreamProxyCommand for unknown fields
                        val rejectedField = listOf(
                            "initialGeneratorMetadatasPageBounds",
                            "initialExecutorMetadatasPageBounds",
                            "trajectoryVerbosity",
                        ).firstOrNull { innerObj.containsKey(it) }
                        if (rejectedField != null) {
                            val directErr = """{"code":"invalid_argument","message":"unknown field \"$rejectedField\""}"""
                            val errB64 = directErr.encodeToByteArray().toByteString().base64()
                            respond(
                                content = """["$errB64",[["content-type","application/json"]]]""",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        } else {
                            respond(
                                content = successBoq,
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "Older Mac",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(cascadeId = cloudCid, knownStepCount = 1, isCloud = true)
            assertEquals(1, steps.size)
            assertEquals("Self-healed older host", steps.first().userInput)
            assertEquals(4, streamAttempts, "Should strip 3 unknown optional fields and succeed on 4th canonical attempt")

            // Second fetch must reuse cached stripped fields and succeed in 1 RTT
            streamAttempts = 0
            val cachedSteps = client.fetchAllTrajectorySteps(cascadeId = cloudCid, knownStepCount = 1, isCloud = true)
            assertEquals(1, cachedSteps.size)
            assertEquals(1, streamAttempts, "Cached stripped fields must make subsequent calls succeed in 1 RTT")
        }
    }

    @Test
    fun testCloudStreamAgentStateUpdatesWaitsPast1500msHydrationStubWithoutPrematureCancel() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "inst-cloud-hydration-2s"
            val cloudCid = "v1/default/jetski_remote_agents_3p_devbox/app-bug-report-slow-hydrate"
            var streamCalls = 0

            val stubFrame = """{"update":{"conversationId":"$cloudCid","mainTrajectoryUpdate":{"stepsUpdate":{"totalLength":0}}}}"""
            val stubFramed = ConnectEnvelope.encode(stubFrame.encodeToByteArray())
            val stubBoqPrefix = """[["${stubFramed.toByteString().base64()}",[["content-type","application/connect+json"]]]"""

            val hydratedFrame = """{"update":{"conversationId":"$cloudCid","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0,1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Cold Cloud hydration after 1.8s"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Loaded without premature 1.5s cancellation!"}}]}}}}"""
            val hydratedFramed = ConnectEnvelope.encode(hydratedFrame.encodeToByteArray()) +
                ConnectEnvelope.encode("{}".encodeToByteArray(), flags = ConnectEnvelopeFlags.END_STREAM)
            val hydratedBoqSuffix = """,["${hydratedFramed.toByteString().base64()}"]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/StreamProxyCommand") -> {
                        streamCalls += 1
                        val ch = ByteChannel(autoFlush = true)
                        ch.writeFully(stubBoqPrefix.encodeToByteArray())
                        launch {
                            delay(1_800L) // > old 1,500ms premature kill window
                            ch.writeFully(hydratedBoqSuffix.encodeToByteArray())
                            ch.flushAndClose()
                        }
                        respond(
                            content = ch,
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("""[5,"not_found: trajectory not found"]""", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )

            val steps = client.fetchAllTrajectorySteps(cascadeId = cloudCid, knownStepCount = 2, isCloud = true)
            assertEquals(1, streamCalls, "Must keep single open stream alive past 1.5s stub instead of cancelling and retrying")
            assertEquals(2, steps.size)
            assertEquals("Cold Cloud hydration after 1.8s", steps[0].userInput)
            assertEquals("Loaded without premature 1.5s cancellation!", steps[1].plannerResponse?.response)
        }
    }

    @Test
    fun testStreamProxyCommandDecodesGrpcWeb80TrailersInnerHeadersAndPreservesCloudDiagnostics() = runTest {
        withContext(Dispatchers.Default) {
            // 1. CloudRelayJspbStreamParser captures inner HTTP & gRPC error headers even inside `[null, headers]`
            val headerParser = CloudRelayJspbStreamParser()
            val innerHeaderErrPayload = """[[null,[[":status","503"],["grpc-status","14"],["grpc-message","relay%20overloaded"]]]]""".encodeToByteArray()
            assertTrue(headerParser.feed(innerHeaderErrPayload).isEmpty())
            val headerErr = assertNotNull(headerParser.lastInnerHeaderError() as? AntigravityRpcError.HttpError)
            assertEquals(503, headerErr.statusCode)
            assertEquals("relay overloaded", headerErr.body)

            // 2. gRPC-Web 0x80 trailer frame inside StreamProxyCommand throws true error AND preserves it over local 404 fallback
            val instanceUuid = "inst-cloud-grpc-trailer"
            val cloudCid = "v1/default/jetski_remote_agents_3p_devbox/grpc-error-diag"
            val json = Json { ignoreUnknownKeys = true }
            var listInstancesCalls = 0
            var protoCalls = 0
            var getCascadeTrajectoryCalls = 0

            val grpcTrailerBytes = ConnectEnvelope.encode(
                payload = "grpc-status: 13\r\ngrpc-message: remote%20agent%20proxy%20failed\r\n".encodeToByteArray(),
                flags = ConnectEnvelopeFlags.GRPC_WEB_TRAILER,
            )
            val grpcTrailerBoq = """["${grpcTrailerBytes.toByteString().base64()}",[["content-type","application/grpc-web+json"]]]"""

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bodyText = ((request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)).decodeToString()
                when {
                    path.endsWith("/ListInstances") -> {
                        listInstancesCalls += 1
                        respond(
                            content = """[[["$instanceUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/StreamProxyCommand") -> respond(
                        content = grpcTrailerBoq,
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/ProxyCommand") -> {
                        val jspbArr = json.parseToJsonElement(bodyText) as JsonArray
                        val rpcPath = (jspbArr[1] as JsonPrimitive).content
                        if (bodyText.contains("application/proto")) protoCalls += 1
                        if (rpcPath.endsWith("/GetCascadeTrajectory")) getCascadeTrajectoryCalls += 1
                        respond(
                            content = """[5,"not_found: trajectory not found"]""",
                            status = HttpStatusCode.NotFound,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )
            // Pre-populate cached instances + resolved UUID (1 initial ListInstances call)
            client.resolveCloudRelayInstance()
            assertEquals(1, listInstancesCalls)

            val thrown = assertFailsWith<AntigravityRpcError.HttpError> {
                client.fetchAllTrajectorySteps(cascadeId = cloudCid, knownStepCount = 10, isCloud = true)
            }
            assertEquals(500, thrown.statusCode, "Must preserve gRPC-Web 0x80 internal error (500) instead of local 404")
            assertTrue(thrown.body.contains("remote agent proxy failed"), "Unexpected error body: ${thrown.body}")
            assertEquals(0, protoCalls, "Cloud fallback must NOT waste a Binary Protobuf Fallback B RPC")
            assertEquals(0, getCascadeTrajectoryCalls, "Cloud fallback must short-circuit GetCascadeTrajectory after LoadTrajectory 404")
            assertEquals(1, listInstancesCalls, "Must NOT waste an extra ListInstances refresh on Cloud trajectory 404/500")
        }
    }

    @Test
    fun testCloudPath2ShortCircuitsTransportTimeoutWithoutCascadingLoadOrTrajectoryRetries() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "inst-cloud-timeout-short"
            val cloudCid = "v1/default/jetski_remote_agents_3p_devbox/timeout-cascade"
            val json = Json { ignoreUnknownKeys = true }
            var stepsCalls = 0
            var loadCalls = 0
            var getTrajCalls = 0
            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bodyText = ((request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)).decodeToString()
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/StreamProxyCommand") -> respond(
                        content = """[null,[501,"unimplemented"]]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/ProxyCommand") -> {
                        val jspbArr = json.parseToJsonElement(bodyText) as JsonArray
                        val rpcPath = (jspbArr[1] as JsonPrimitive).content
                        when {
                            rpcPath.endsWith("/GetCascadeTrajectorySteps") -> {
                                stepsCalls += 1
                                respond(
                                    content = "Gateway Timeout",
                                    status = HttpStatusCode.GatewayTimeout,
                                    headers = headersOf(HttpHeaders.ContentType, "text/plain"),
                                )
                            }
                            rpcPath.endsWith("/LoadTrajectory") -> {
                                loadCalls += 1
                                respond(
                                    content = """[5,"not_found"]""",
                                    status = HttpStatusCode.NotFound,
                                    headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                )
                            }
                            rpcPath.endsWith("/GetCascadeTrajectory") -> {
                                getTrajCalls += 1
                                respond(
                                    content = """[5,"not_found"]""",
                                    status = HttpStatusCode.NotFound,
                                    headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                )
                            }
                            else -> respond("", HttpStatusCode.NotFound)
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )
            client.resolveCloudRelayInstance()

            val err = assertFailsWith<AntigravityRpcError.HttpError> {
                client.fetchAllTrajectorySteps(cascadeId = cloudCid, knownStepCount = 20, isCloud = true)
            }
            assertEquals(504, err.statusCode)
            assertEquals(1, stepsCalls, "Cloud Path 2 timeout must NOT retry GetCascadeTrajectorySteps multiple times")
            assertEquals(0, loadCalls, "Cloud Path 2 timeout must NOT cascade into LoadTrajectory")
            assertEquals(0, getTrajCalls, "Cloud Path 2 timeout must NOT cascade into GetCascadeTrajectory")
        }
    }

    @Test
    fun testLocalCloudRelayPreservesTailStepsWhenFullFetchTimesOutAndFallsBackToStream() = runTest {
        withContext(Dispatchers.Default) {
            val instanceUuid = "inst-local-relay-tail"
            val localCid = "local-big-relay-chat"
            val json = Json { ignoreUnknownKeys = true }
            var streamFallbackCalls = 0
            var jsonFallbackCalls = 0
            val tailBinaryPayload = buildBinaryPlannerSteps(32)
            val tailB64 = tailBinaryPayload.toByteString().base64()

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                val bodyText = ((request.body as? ByteArrayContent)?.bytes() ?: ByteArray(0)).decodeToString()
                when {
                    path.endsWith("/ListInstances") -> respond(
                        content = """[[["$instanceUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                    )
                    path.endsWith("/StreamProxyCommand") -> {
                        streamFallbackCalls += 1
                        respond(
                            content = """[null,[["grpc-status","12"],["grpc-message","unimplemented"]]]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val jspbArr = json.parseToJsonElement(bodyText) as JsonArray
                        val innerB64 = (jspbArr[2] as JsonPrimitive).content
                        val innerBytes = CloudRelayJspbCodec.decodeBase64Flexible(innerB64) ?: ByteArray(0)
                        if (bodyText.contains("application/proto")) {
                            // Decode startIndex (field 2 varint) from GetCascadeTrajectoryStepsRequest
                            var startIdx = 0
                            val off = IntArray(1)
                            while (off[0] < innerBytes.size) {
                                val tag = ProtobufStepCodec.readVarint(innerBytes, off) ?: break
                                val fn = (tag shr 3).toInt()
                                val wt = (tag and 0x07UL).toInt()
                                when (wt) {
                                    0 -> {
                                        val v = ProtobufStepCodec.readVarint(innerBytes, off) ?: break
                                        if (fn == 2) startIdx = v.toInt()
                                    }
                                    2 -> {
                                        val len = ProtobufStepCodec.readVarint(innerBytes, off)?.toInt() ?: break
                                        off[0] += len
                                    }
                                    else -> break
                                }
                            }
                            if (startIdx >= 20) {
                                respond(
                                    content = """["$tailB64",[["content-type","application/proto"]]]""",
                                    status = HttpStatusCode.OK,
                                    headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                                )
                            } else {
                                // Simulate full 0..60 unary ProxyCommand timing out (504)
                                respond(
                                    content = "Gateway Timeout",
                                    status = HttpStatusCode.GatewayTimeout,
                                    headers = headersOf(HttpHeaders.ContentType, "text/plain"),
                                )
                            }
                        } else {
                            jsonFallbackCalls += 1
                            respond("", HttpStatusCode.NotFound)
                        }
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = instanceUuid,
                    hostname = "MacBook Pro",
                    channel = RemoteConnectionChannel.CLOUD_RELAY,
                    endpointUrl = "https://antigravity.google.com/r/$instanceUuid",
                    isOnline = true,
                ),
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = "AI" + "zaSyVALIDKEY0000000000000000000000000",
                httpClientOverride = HttpClient(engine),
            )
            client.resolveCloudRelayInstance()

            val partialSnapshots = mutableListOf<List<CascadeStep>>()
            val result = client.fetchAllTrajectorySteps(
                cascadeId = localCid,
                knownStepCount = 60,
                isCloud = false,
                onPartialSteps = { partialSnapshots.add(it) },
            )

            assertEquals(1, partialSnapshots.size, "Cloud Relay local chat >=50 steps must paint 32 tail steps first")
            assertEquals(32, result.size, "Must preserve painted tail steps when full 0..60 unary ProxyCommand times out")
            assertEquals(1, streamFallbackCalls, "Must fast-try StreamAgentStateUpdates before falling back to preserved tail")
            assertEquals(0, jsonFallbackCalls, "Must NOT discard tail steps and burn Path 2 JSON fallbacks")
        }
    }

    @Test
    fun testLogProtocolDiagnosticHandlesFormatSpecifiersSafely() {
        // Directly exercises the platform actual implementation on both JVM and KMP iOS Simulator
        // (`iosSimulatorArm64Test`) to ensure format specifiers (`%@`, `%s`, `%n`, `%24`) never crash.
        logProtocolDiagnostic("StepSync diagnostic probe %@ %s %d %n https://antigravity.google.com/%24rpc")
    }
}
