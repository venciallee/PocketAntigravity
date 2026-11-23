package dev.antigravity.shared.domain

import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.platform.InMemorySecretStore
import dev.antigravity.shared.protocol.AntigravityRpcError
import dev.antigravity.shared.protocol.ConnectionLifecyclePhase
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Full-stack KMP Phase 2 E2E tests exercising Ktor OkHttp (`AntigravityKmpRpcClient`) +
 * `AntigravityCoreCoordinator` (`ConnectionDomainStore`, `ConversationSyncStore`,
 * `CascadeChatDomainStore`, `DurableOutbox`) against the live Python `LiveMockServer`.
 */
class KtorCoordinatorMockServerE2eTest {

    private fun findRepoRoot(): File {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            if (File(dir, "verification/mock_language_server.py").exists()) return dir
            dir = dir.parentFile
        }
        error("Could not locate verification/mock_language_server.py")
    }

    private fun withMockServer(block: suspend (port: Int) -> Unit) {
        val repoRoot = findRepoRoot()
        val script = """
            import sys, time
            sys.path.insert(0, 'verification')
            from mock_language_server import LiveMockServer
            with LiveMockServer() as srv:
                print(srv.port, flush=True)
                while True:
                    time.sleep(0.5)
        """.trimIndent()
        val proc = ProcessBuilder("python3", "-u", "-c", script)
            .directory(repoRoot)
            .redirectErrorStream(true)
            .start()
        try {
            val reader = BufferedReader(InputStreamReader(proc.inputStream))
            val portLine = reader.readLine()?.trim() ?: error("Mock server exited without printing port")
            val port = portLine.toInt()
            runBlocking { block(port) }
        } finally {
            proc.destroyForcibly()
            proc.waitFor()
        }
    }

    @Test
    fun testDirectLanFullCoordinatorLifecycleWithKtorAnd605ProtobufStepsAndFaceId() = withMockServer { port ->
        val secretStore = InMemorySecretStore()
        val storage = InMemoryProjectionStorage()
        val coordinator = AntigravityCoreCoordinator(
            secretStore = secretStore,
            projectionStorage = storage,
        )
        try {
            // 1. Direct LAN Handshake via Ktor OkHttp
            val handshake = coordinator.connectDirectLan(
                endpointUrlString = "http://127.0.0.1:$port",
                csrfToken = "kmp-phase2-csrf-token",
                hostName = "Phase2-MacBook-Pro",
                startSummaryStream = true,
            )
            assertTrue(handshake.latencyMs >= 1)
            assertTrue(coordinator.connectionState.value.isConnected)
            assertEquals(ConnectionLifecyclePhase.OnlineIdle, coordinator.connectionState.value.lifecyclePhase)
            assertNotNull(secretStore.loadCredentials())

            // Wait briefly for 5-byte Connect-RPC JetboxSubscribeToSummaries stream to deliver snapshot (Frame 1) + delta (Frame 2)
            repeat(40) {
                val rl = coordinator.syncState.value.summaries.firstOrNull { it.cascadeId == "cas-rate-limiter" }
                if (rl?.status == CortexStepStatus.WAITING) return@repeat
                delay(50)
            }
            assertTrue(coordinator.syncState.value.summaries.isNotEmpty(), "Jetbox 5-byte stream should populate summaries")
            val rateLimiter = coordinator.syncState.value.summaries.firstOrNull { it.cascadeId == "cas-rate-limiter" }
            assertNotNull(rateLimiter)
            assertEquals(CortexStepStatus.WAITING, rateLimiter.status, "Delta frame should update cas-rate-limiter to WAITING")

            // 2. Sync >600-step trajectory: Local host uses Binary-first Protobuf directly (605 steps)
            val steps = coordinator.syncSteps("cas-rate-limiter", knownStepCount = 0)
            assertEquals(605, steps.size)
            assertEquals(605, coordinator.chatState.value.stepsByCascadeId["cas-rate-limiter"]?.size)
            val waitingStep = steps.last()
            assertEquals(604, waitingStep.stepIndex)
            assertEquals(CortexStepStatus.WAITING, waitingStep.status)
            assertEquals(RequestedInteraction.MemberKind.RUN_COMMAND, waitingStep.requestedInteraction?.kind)

            // 3. Send message via Durable Outbox + Ktor SendUserCascadeMessage
            val sendOutcome = coordinator.sendMessage(
                cascadeId = "cas-rate-limiter",
                message = "Keep rate at 1000/s on staging",
                workspaceUri = "file:///Users/dev/code/ledger-svc",
            )
            assertTrue(sendOutcome.dispatchedLive)
            assertFalse(sendOutcome.queuedInOutbox)
            assertEquals(0, coordinator.chatState.value.pendingOutboxCount)

            // 4. Face ID enforcement: approving runCommand WITHOUT biometricVerified must fail with 403 Unauthorized!
            assertFailsWith<AntigravityRpcError.Unauthorized> {
                coordinator.resolveWaitingInteraction(
                    cascadeId = "cas-rate-limiter",
                    stepIndex = 604,
                    decision = InteractionDecision.AllowOnce,
                )
            }

            // 5. Approving WITH biometricVerified succeeds (200) and transitions step 604 to DONE
            val approvedPayload = coordinator.resolveWaitingInteraction(
                cascadeId = "cas-rate-limiter",
                stepIndex = 604,
                decision = InteractionDecision.AllowWithBiometric,
            )
            assertEquals(true, approvedPayload.runCommand?.confirm)
            assertEquals(true, approvedPayload.runCommand?.biometricVerified)
            val updatedStep604 = coordinator.chatState.value.stepsByCascadeId["cas-rate-limiter"]
                ?.firstOrNull { it.stepIndex == 604 }
            assertEquals(CortexStepStatus.DONE, updatedStep604?.status)

            // 6. Disconnect clears Keychain, projection cache, and connection state
            coordinator.disconnectAndClearCredentials()
            assertFalse(coordinator.connectionState.value.isConnected)
            assertEquals(null, secretStore.loadCredentials())
            assertTrue(coordinator.syncState.value.summaries.isEmpty())
        } finally {
            coordinator.close()
        }
    }

    @Test
    fun testCloudRelayMultiAuthUserAndProxyCommandAnd605BinaryProtobufViaKtor() = withMockServer { port ->
        val secretStore = InMemorySecretStore()
        val coordinator = AntigravityCoreCoordinator(secretStore = secretStore)
        try {
            // Connect to mock Cloud Relay (`http://127.0.0.1:<port>/r/lt74xt6l0m-golden-star`) without explicit authuser.
            // Mock server only owns the instance on authuser=2 -> Ktor client must auto-discover authuser=2!
            val handshake = coordinator.connectCloudRelay(
                relayUrlString = "http://127.0.0.1:$port/r/lt74xt6l0m-golden-star",
                sessionCookie = "SAPISID=kmp-phase2-sapisid; SID=kmp-sid",
                hostName = "Golden Star Mac",
                startSummaryStream = false,
            )
            assertEquals("2", handshake.resolvedAuthUser)
            assertEquals("0f5819ac-9308-40d8-a308-98b55122c533-v2", handshake.resolvedInstanceUuid)
            assertEquals("lt74xt6l0m-golden-star", handshake.resolvedHostname)
            assertEquals(1, handshake.workspaces.size)
            assertEquals("ledger-svc", handshake.workspaces.first().displayName)
            assertEquals(1, handshake.summaries.size)
            assertEquals("cas-rate-limiter", handshake.summaries.first().cascadeId)

            // StartCascade over Cloud Relay must strip companion-only `modelId`/`initialUserInput` (protojson strictness)
            val createdId = coordinator.startConversation(
                workspaceUri = "file:///Users/dev/code/ledger-svc",
                initialPrompt = "Draft KMP migration plan",
                modelId = "MODEL_GOOGLE_GEMINI_4_NEON",
            )
            assertEquals("cas-cloud-relay-01", createdId)

            // Fetch 605 Binary Protobuf steps over Cloud Relay ProxyCommand (`application/proto` inside JSPB)
            val protoSteps = coordinator.syncSteps(
                cascadeId = "cas-rate-limiter",
                knownStepCount = 605,
            )
            assertEquals(605, protoSteps.size)
            assertEquals(RequestedInteraction.MemberKind.RUN_COMMAND, protoSteps.last().requestedInteraction?.kind)
        } finally {
            coordinator.close()
        }
    }
}
