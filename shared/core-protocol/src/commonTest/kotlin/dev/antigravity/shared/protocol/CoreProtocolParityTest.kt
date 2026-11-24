package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.AskQuestionInteractionSpec
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.FilePermissionInteractionSpec
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.PermissionInteractionSpec
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.model.RunCommandInteractionSpec
import dev.antigravity.shared.platform.InMemoryPreferencesStore
import dev.antigravity.shared.platform.InMemorySecretStore
import dev.antigravity.shared.platform.SavedBackendCredentials
import dev.antigravity.shared.platform.StaticPowerStateProvider
import kotlinx.coroutines.test.runTest
import okio.ByteString.Companion.encodeUtf8
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CoreProtocolParityTest {

    @Test
    fun testConnectEnvelopeRoundTripAndIncrementalStreaming() {
        val f1 = ConnectEnvelope.encode("""{"cascadeId":"cas-1","status":"RUNNING"}""".encodeToByteArray())
        val f2 = ConnectEnvelope.encode(
            """{"error":{"code":"ok"}}""".encodeToByteArray(),
            flags = ConnectEnvelopeFlags.END_STREAM,
        )
        val combined = f1 + f2

        val parser = ConnectStreamParser()
        val parsed = mutableListOf<ConnectEnvelopeFrame>()
        // Feed 1 byte at a time to stress fragmentation
        for (b in combined) {
            parser.feedByte(b)?.let { parsed.add(it) }
        }
        assertFalse(parser.hasBufferedBytes)
        assertEquals(2, parsed.size)
        assertFalse(parsed[0].isEndStream)
        assertTrue(parsed[0].payload.decodeToString().contains("cas-1"))
        assertTrue(parsed[1].isEndStream)
    }

    @Test
    fun testProtobufStepCodecEncodesRequestAndDecodes605Steps() {
        val req = ProtobufStepCodec.encodeGetStepsRequest("cas-large", startIndex = 600)
        // field 1 tag 0x0A, len 9, "cas-large", field 2 tag 0x10, varint(600) = [0xD8, 0x04]
        assertEquals(0x0A.toByte(), req[0])
        assertEquals(9.toByte(), req[1])
        assertEquals("cas-large", req.copyOfRange(2, 11).decodeToString())
        assertEquals(0x10.toByte(), req[11])
        assertContentEquals(byteArrayOf(0xD8.toByte(), 0x04), req.copyOfRange(12, req.size))

        // Build synthetic binary GetCascadeTrajectoryStepsResponse with 605 steps
        val responseBytes = ArrayList<Byte>()
        for (i in 0 until 605) {
            val stepMsg = ArrayList<Byte>()
            if (i % 2 == 0) {
                // type = 14 (USER_INPUT), status = 3 (DONE), field 19 user_input (query=1)
                stepMsg.addAll(listOf(0x08, 14, 0x20, 3))
                val query = "Prompt #$i".encodeToByteArray()
                val uiMsg = byteArrayOf(0x0A) + ProtobufStepCodec.encodeVarint(query.size.toULong()) + query
                stepMsg.addAll(ProtobufStepCodec.encodeVarint(((19 shl 3) or 2).toULong()).toList())
                stepMsg.addAll(ProtobufStepCodec.encodeVarint(uiMsg.size.toULong()).toList())
                stepMsg.addAll(uiMsg.toList())
            } else {
                // type = 15 (PLANNER_RESPONSE), status = 3 (DONE), field 20 planner (response=1, thinking=3)
                stepMsg.addAll(listOf(0x08, 15, 0x20, 3))
                val resp = "Answer #$i".encodeToByteArray()
                val think = "Thought #$i".encodeToByteArray()
                val prMsg = byteArrayOf(0x0A) + ProtobufStepCodec.encodeVarint(resp.size.toULong()) + resp +
                    byteArrayOf(0x1A) + ProtobufStepCodec.encodeVarint(think.size.toULong()) + think
                stepMsg.addAll(ProtobufStepCodec.encodeVarint(((20 shl 3) or 2).toULong()).toList())
                stepMsg.addAll(ProtobufStepCodec.encodeVarint(prMsg.size.toULong()).toList())
                stepMsg.addAll(prMsg.toList())
            }
            // field 1 (steps), wire type 2
            responseBytes.add(0x0A)
            responseBytes.addAll(ProtobufStepCodec.encodeVarint(stepMsg.size.toULong()).toList())
            responseBytes.addAll(stepMsg)
        }

        val steps = ProtobufStepCodec.decodeStepsResponse(responseBytes.toByteArray(), cascadeId = "cas-large")
        assertEquals(605, steps.size)
        assertEquals(CortexStepType.USER_INPUT, steps[0].type)
        assertEquals("Prompt #0", steps[0].userInput)
        assertEquals(CortexStepType.PLANNER_RESPONSE, steps[603].type)
        assertEquals("Answer #603", steps[603].plannerResponse?.response)
        assertEquals("Thought #603", steps[603].plannerResponse?.thinking)
        assertEquals("MODEL_GOOGLE_GEMINI_4_HYDROGEN", ProtobufStepCodec.modelEnumName(404))
        assertEquals("MODEL_PLACEHOLDER_M42", ProtobufStepCodec.modelEnumName(1042))
    }

    @Test
    fun testSapisidHashAndCloudRelayJspbCodec() {
        // FIPS 180-4 SHA-1 test vector ("abc")
        assertEquals("a9993e364706816aba3e25717850c26c9cd0d89d", SapisidHashGenerator.sha1Hex("abc"))

        val cookie = "SID=sid_val; SAPISID=sapi_123; __Secure-1PAPISID=p1_456; __Secure-3PAPISID=p3_789"
        assertTrue(SapisidHashGenerator.hasRequiredGoogleAuthCookies(cookie))
        val auth = SapisidHashGenerator.computeAuthorizationHeader(
            cookieHeader = cookie,
            origin = "https://antigravity.google.com/r/mac-1",
            timestampSeconds = 1_700_000_000L,
        )
        assertNotNull(auth)
        assertTrue(auth.contains("SAPISIDHASH 1700000000_"))
        assertTrue(auth.contains("SAPISID1PHASH 1700000000_"))
        assertTrue(auth.contains("SAPISID3PHASH 1700000000_"))

        val headers = SapisidHashGenerator.buildApiServiceHeaders(
            cookieHeader = cookie,
            authUser = "2",
            isStreaming = false,
            timestampSeconds = 1_700_000_000L,
        )
        assertEquals("2", headers["X-Goog-AuthUser"])
        assertEquals(null, headers["X-Goog-Api-Key"])
        assertEquals("base64", headers["X-Goog-Encode-Response-If-Executable"])
        assertEquals("https://antigravity.google.com", headers["Origin"])

        val keyedHeaders = SapisidHashGenerator.buildApiServiceHeaders(
            cookieHeader = cookie,
            authUser = "0",
            apiKey = "runtime-relay-key",
            isStreaming = false,
            timestampSeconds = 1_700_000_000L,
        )
        assertEquals("runtime-relay-key", keyedHeaders["X-Goog-Api-Key"])
        assertEquals("mock-wiz-key-123456", SapisidHashGenerator.extractWebApiKey("""{"SNlM0e":"mock-wiz-key-123456"}"""))
        assertTrue(SapisidHashGenerator.isInvalidApiKeyError(400, "API_KEY_INVALID: API key not valid"))
        assertTrue(!SapisidHashGenerator.isInvalidApiKeyError(401, "UNAUTHENTICATED: session expired"))

        // ListInstances decoding with Google XSSI prefix
        val listJson = ")]}'\n" + """[[["uuid-mac-1",["macbook-pro-main","v2.33.0",true],1,[1700000000,0]]],5]"""
        val instances = CloudRelayJspbCodec.decodeListInstancesResponse(listJson.encodeToByteArray())
        assertEquals(1, instances.size)
        assertEquals("uuid-mac-1", instances[0].uuid)
        assertEquals("macbook-pro-main", instances[0].name)
        assertEquals(RelayInstanceStatus.CONNECTED, instances[0].status)
        assertTrue(instances[0].sameHostFamily("macbook-pro-secondary"))

        // ProxyCommand encode + decode + streaming JSPB parser
        val reqBytes = CloudRelayJspbCodec.encodeProxyCommandRequest(
            targetInstanceUuid = "uuid-mac-1",
            rpcPath = "/exa.language_server_pb.LanguageServerService/GetWorkspaceInfos",
            payload = "{}".encodeToByteArray(),
        )
        assertTrue(reqBytes.decodeToString().contains("uuid-mac-1"))

        val innerB64 = """{"workspaces":[]}""".encodeUtf8().base64()
        val proxyResp = """["$innerB64",[["content-type","application/json"]]]""".encodeToByteArray()
        val decoded = CloudRelayJspbCodec.decodeProxyCommandResponse(proxyResp)
        assertEquals("""{"workspaces":[]}""", decoded.payload.decodeToString())
        assertEquals("application/json", decoded.headers["content-type"])

        // Streaming open outer array parser
        val streamParser = CloudRelayJspbStreamParser()
        val streamData = """[[["$innerB64",[["content-type","application/connect+json"]]]],[null,[14,"host offline"]]]""".encodeToByteArray()
        val emitted = streamParser.feed(streamData)
        assertEquals(1, emitted.size)
        assertEquals("""{"workspaces":[]}""", emitted[0].decodeToString())
        assertEquals("Boq status 14: host offline", streamParser.lastErrorTrailer)
    }

    @Test
    fun testInteractionBuilderAndConnectionPowerPolicy() {
        assertTrue(SafeAutoAcceptPolicy.isSafeReadOnlyCommand("git status"))
        assertFalse(SafeAutoAcceptPolicy.isSafeReadOnlyCommand("git status && rm -rf /"))
        assertFalse(SafeAutoAcceptPolicy.isSafeReadOnlyCommand("find . -delete"))

        val runCmdStep = CascadeStep(
            cascadeId = "cas-7",
            stepIndex = 4,
            type = CortexStepType.RUN_COMMAND,
            status = CortexStepStatus.WAITING,
            requestedInteraction = RequestedInteraction(
                kind = RequestedInteraction.MemberKind.RUN_COMMAND,
                runCommand = RunCommandInteractionSpec("vegeta attack -rate=2000", "/repo"),
            ),
        )
        assertFalse(InteractionBuilder.canSafeAutoAccept(runCmdStep, listOf("file:///repo")))
        val bioPayload = InteractionBuilder.buildPayload(runCmdStep, InteractionDecision.AllowWithBiometric)
        assertNotNull(bioPayload)
        assertTrue(bioPayload.runCommand?.confirm == true)
        assertTrue(bioPayload.runCommand?.biometricVerified == true)

        val readPermStep = CascadeStep(
            cascadeId = "cas-7",
            stepIndex = 5,
            type = CortexStepType.VIEW_FILE,
            status = CortexStepStatus.WAITING,
            requestedInteraction = RequestedInteraction(
                kind = RequestedInteraction.MemberKind.FILE_PERMISSION,
                filePermission = FilePermissionInteractionSpec("file:///repo/main.go"),
            ),
        )
        assertTrue(InteractionBuilder.canSafeAutoAccept(readPermStep, listOf("file:///repo")))

        val questionStep = CascadeStep(
            cascadeId = "cas-7",
            stepIndex = 6,
            type = CortexStepType.PLANNER_RESPONSE,
            status = CortexStepStatus.WAITING,
            requestedInteraction = RequestedInteraction(
                kind = RequestedInteraction.MemberKind.ASK_QUESTION,
                askQuestion = AskQuestionInteractionSpec("Retention?", listOf("30d", "90d")),
            ),
        )
        val qPayload = InteractionBuilder.buildPayload(
            questionStep,
            InteractionDecision.AnswerQuestion(listOf("90d"), customWriteIn = "SOC2"),
        )
        assertEquals(listOf("90d"), qPayload?.askQuestion?.selectedOptions)
        assertEquals("SOC2", qPayload?.askQuestion?.customResponse)

        // Power policy checks
        assertEquals(30.0, ConnectionPowerPolicy.onlineHeartbeatIntervalSeconds(RemoteConnectionChannel.CLOUD_RELAY, false, false, true))
        assertEquals(60.0, ConnectionPowerPolicy.onlineHeartbeatIntervalSeconds(RemoteConnectionChannel.CLOUD_RELAY, true, false, true))
        assertNull(ConnectionPowerPolicy.idleChatFallbackStepPollIntervalSeconds(isStreamHealthy = true, isLowPowerMode = false))
        assertEquals(15.0, ConnectionPowerPolicy.idleChatFallbackStepPollIntervalSeconds(isStreamHealthy = false, isLowPowerMode = false))
        assertEquals(
            listOf(3.0, 6.0, 12.0, 24.0, 45.0, 60.0),
            (0..5).map { ConnectionPowerPolicy.offlineBackoffBaseDelaySeconds(it, isLowPowerMode = false) },
        )
        assertEquals(
            1,
            ConnectionPowerPolicy.offlineFailureThreshold(
                RemoteConnectionChannel.CLOUD_RELAY,
                AntigravityRpcError.HttpError(503, "No reachable desktop instance"),
            ),
        )
    }

    @Test
    fun testPlatformPortsInMemoryDoubles() = runTest {
        val secrets = InMemorySecretStore()
        val creds = SavedBackendCredentials(
            endpointUrlString = "https://antigravity.google.com/r/mac-1",
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            hostname = "MacBook Pro",
        )
        secrets.saveCredentials(creds)
        assertEquals(creds, secrets.loadCredentials())
        secrets.clearCredentials()
        assertNull(secrets.loadCredentials())

        val prefs = InMemoryPreferencesStore()
        prefs.putString("mode", CascadeExecutionMode.PLANNING.name)
        assertEquals("PLANNING", prefs.getString("mode"))
        assertTrue(StaticPowerStateProvider(isLowPowerModeEnabled = true).isLowPowerModeEnabled)
    }

    @Test
    fun testCloudRelaySanitizerPreservesTopLevelMediaAndStepDecoderReadsMedia() {
        val host = dev.antigravity.shared.model.RemoteHostInstance(
            instanceId = "relay-media-test",
            hostname = "Antigravity Cloud",
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = "https://antigravity.google.com/r/relay-media-test",
            isOnline = true,
        )
        val client = AntigravityKmpRpcClient(host = host, sessionCookie = "SAPISID=test")
        val rawBody = kotlinx.serialization.json.buildJsonObject {
            put("cascadeId", kotlinx.serialization.json.JsonPrimitive("cas-media"))
            put("items", kotlinx.serialization.json.buildJsonArray {
                add(kotlinx.serialization.json.buildJsonObject {
                    put("text", kotlinx.serialization.json.JsonPrimitive("Check this screenshot"))
                })
            })
            put("media", kotlinx.serialization.json.buildJsonArray {
                add(kotlinx.serialization.json.buildJsonObject {
                    put("mimeType", kotlinx.serialization.json.JsonPrimitive("image/jpeg"))
                    put("inlineData", kotlinx.serialization.json.JsonPrimitive("iVBORw0KGgo="))
                    put("description", kotlinx.serialization.json.JsonPrimitive("photo-1.jpg"))
                    put("uri", kotlinx.serialization.json.JsonPrimitive("file:///private/var/mobile/photo-1.jpg"))
                })
            })
        }
        val sanitized = client.sanitizeCloudRelayPayload("SendUserCascadeMessage", rawBody)
        val mediaArr = sanitized["media"] as? kotlinx.serialization.json.JsonArray
        assertNotNull(mediaArr)
        assertEquals(1, mediaArr.size)
        val mediaObj = mediaArr[0] as kotlinx.serialization.json.JsonObject
        assertEquals("image/jpeg", (mediaObj["mimeType"] as kotlinx.serialization.json.JsonPrimitive).content)
        assertEquals("iVBORw0KGgo=", (mediaObj["inlineData"] as kotlinx.serialization.json.JsonPrimitive).content)
        assertEquals("photo-1.jpg", (mediaObj["description"] as kotlinx.serialization.json.JsonPrimitive).content)
        assertNull(mediaObj["uri"], "Device-local file:// URI must not leak to Cloud Relay media entry")

        // Verify JSON step decoder extracts userInput.media labels into attachedMentions
        val stepJson = kotlinx.serialization.json.buildJsonObject {
            put("stepIndex", kotlinx.serialization.json.JsonPrimitive(0))
            put("type", kotlinx.serialization.json.JsonPrimitive("CORTEX_STEP_TYPE_USER_INPUT"))
            put("status", kotlinx.serialization.json.JsonPrimitive("CORTEX_STEP_STATUS_DONE"))
            put("userInput", kotlinx.serialization.json.buildJsonObject {
                put("userResponse", kotlinx.serialization.json.JsonPrimitive("Check this screenshot"))
                put("media", kotlinx.serialization.json.buildJsonArray {
                    add(kotlinx.serialization.json.buildJsonObject {
                        put("mimeType", kotlinx.serialization.json.JsonPrimitive("image/jpeg"))
                        put("description", kotlinx.serialization.json.JsonPrimitive("photo-1.jpg"))
                    })
                })
            })
        }
        val decoded = JsonStepAndSummaryDecoder.decodeJsonStep(stepJson, "cas-media", 0)
        assertNotNull(decoded)
        assertTrue("photo-1.jpg" in decoded.attachedMentions)
    }
}
