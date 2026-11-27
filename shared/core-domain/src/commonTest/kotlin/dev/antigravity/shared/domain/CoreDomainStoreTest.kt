package dev.antigravity.shared.domain

import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.AgentsQuickFilter
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.model.RunCommandInteractionSpec
import dev.antigravity.shared.model.RunCommandPayload
import dev.antigravity.shared.platform.InMemoryPreferencesStore
import dev.antigravity.shared.platform.NetworkReachabilityStatus
import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.AntigravityRpcError
import dev.antigravity.shared.protocol.BackendHandshakeResult
import dev.antigravity.shared.protocol.ConnectionLifecyclePhase
import dev.antigravity.shared.protocol.JsonStepAndSummaryDecoder
import dev.antigravity.shared.protocol.RelayInstanceInfo
import dev.antigravity.shared.protocol.RelayInstanceStatus
import dev.antigravity.shared.protocol.platformTransportEngineName
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.engine.mock.toByteArray
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import okio.ByteString
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CoreDomainStoreTest {

    @Test
    fun testPerHostShardPreservationKeepsOfflineHostConversationsIntact() = runTest {
        val storage = InMemoryProjectionStorage()
        storage.saveHostShards(
            listOf(
                HostProjectionShard(
                    hostKey = "host:mac-offline-uuid",
                    instanceId = "mac-offline-uuid",
                    hostname = "Offline-Mac-Studio",
                    summaries = listOf(
                        CascadeSummary(
                            cascadeId = "cas-offline-only",
                            title = "Cached offline work",
                            projectSlug = "payments-api",
                            workspaceUri = "file:///Users/dev/payments-api",
                            status = CortexStepStatus.DONE,
                            stepCount = 12,
                            updatedAtEpochMs = 1_700_000_000_000L,
                            originInstanceUuid = "mac-offline-uuid",
                            originHostName = "Offline-Mac-Studio",
                        )
                    ),
                    projects = listOf(
                        ProjectWorkspace(
                            id = "payments-api",
                            name = "payments-api",
                            pathDisplay = "~/payments-api",
                            workspaceUri = "file:///Users/dev/payments-api",
                            runtime = ProjectRuntimeTarget.MAC_BOOK_PRO,
                            hostName = "Offline-Mac-Studio",
                            originInstanceUuid = "mac-offline-uuid",
                        )
                    ),
                )
            )
        )

        val syncStore = ConversationSyncStore(scope = this, projectionStorage = storage)
        syncStore.hydrateFromCache()
        assertEquals(1, syncStore.state.value.summaries.size)
        assertEquals("cas-offline-only", syncStore.state.value.summaries.first().cascadeId)

        // Now apply a fresh handshake from a DIFFERENT online Mac — offline Mac's cached summaries MUST survive!
        val onlineHost = RemoteHostInstance(
            instanceId = "mac-online-uuid",
            hostname = "Online-MacBook-Pro",
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = "https://antigravity.google.com/r/mac-online-uuid",
            isOnline = true,
        )
        val handshake = BackendHandshakeResult(
            latencyMs = 24,
            workspaces = emptyList(),
            summaries = listOf(
                CascadeSummary(
                    cascadeId = "cas-online-1",
                    title = "Live rate limiter",
                    projectSlug = "ledger-svc",
                    workspaceUri = "file:///Users/dev/ledger-svc",
                    status = CortexStepStatus.IN_PROGRESS,
                    stepCount = 5,
                    updatedAtEpochMs = 1_700_000_100_000L,
                    originInstanceUuid = "mac-online-uuid",
                    originHostName = "Online-MacBook-Pro",
                )
            ),
            availableRelayInstances = listOf(
                RelayInstanceInfo(uuid = "mac-online-uuid", name = "Online-MacBook-Pro", status = RelayInstanceStatus.CONNECTED),
                RelayInstanceInfo(uuid = "mac-offline-uuid", name = "Offline-Mac-Studio", status = RelayInstanceStatus.DISCONNECTED),
            ),
            isSelectedHostOnline = true,
        )

        syncStore.applyHandshake(onlineHost, handshake)
        val allIds = syncStore.state.value.summaries.map { it.cascadeId }.toSet()
        assertTrue("cas-online-1" in allIds, "Online summary should be present")
        assertTrue("cas-offline-only" in allIds, "Offline host cached summary must NOT be wiped")

        val scopedOffline = syncStore.filteredSummaries(
            hostScope = AgentsHostFilterScope.LocalHost("mac-offline-uuid", "Offline-Mac-Studio")
        )
        assertEquals(listOf("cas-offline-only"), scopedOffline.map { it.cascadeId })

        val runningOnly = syncStore.filteredSummaries(quickFilter = AgentsQuickFilter.RUNNING)
        assertEquals(listOf("cas-online-1"), runningOnly.map { it.cascadeId })
    }

    @Test
    fun testOfflineSendQueuesIntoDurableOutboxAndClearsOnInteraction() = runTest {
        val storage = InMemoryProjectionStorage()
        val chatStore = CascadeChatDomainStore(projectionStorage = storage)

        val outcome = chatStore.sendMessage(
            client = null,
            cascadeId = "cas-local-draft",
            message = "Ship Phase 2 KMP",
            isDeviceNetworkReachable = false,
        )
        assertFalse(outcome.dispatchedLive)
        assertTrue(outcome.queuedInOutbox)
        assertEquals(1, chatStore.state.value.pendingOutboxCount)
        assertEquals(1, storage.loadPendingOutbox().size)
        assertTrue(chatStore.state.value.stepsByCascadeId["cas-local-draft"]?.first()?.isQueuedInOutbox == true)

        val waitingStep = CascadeStep(
            cascadeId = "cas-local-draft",
            stepIndex = 1,
            type = CortexStepType.RUN_COMMAND,
            status = CortexStepStatus.WAITING,
            runCommand = RunCommandPayload(commandId = "cmd-1", commandLine = "pytest", cwd = "/workspace"),
            requestedInteraction = RequestedInteraction(
                kind = RequestedInteraction.MemberKind.RUN_COMMAND,
                runCommand = RunCommandInteractionSpec("pytest", "/workspace"),
                rawMemberKey = "runCommand",
            ),
        )
        val payload = chatStore.resolveWaitingInteraction(
            client = null,
            cascadeId = "cas-local-draft",
            stepIndex = 1,
            decision = InteractionDecision.AllowWithBiometric,
            stepOverride = waitingStep,
        )
        assertEquals(true, payload.runCommand?.confirm)
        assertEquals(true, payload.runCommand?.biometricVerified)
        assertEquals(payload, chatStore.state.value.lastDispatchedInteraction)
    }

    @Test
    fun testJetboxStreamEventUpdatesAndRemovalsAndLifecycleTransitions() = runTest {
        val coordinator = AntigravityCoreCoordinator(scope = this)
        coordinator.conversationSyncStore.applyStreamEvent(
            JsonStepAndSummaryDecoder.JetboxDecodedEvent(
                summaries = listOf(
                    CascadeSummary(
                        cascadeId = "cas-stream-1",
                        title = "Streamed task",
                        projectSlug = "ledger-svc",
                        workspaceUri = "file:///Users/dev/ledger-svc",
                        status = CortexStepStatus.WAITING,
                        stepCount = 4,
                        isUnread = true,
                    )
                )
            )
        )
        assertTrue(coordinator.syncState.value.isStreamHealthy)
        assertEquals(1, coordinator.filteredSummaries(quickFilter = AgentsQuickFilter.NEEDS_YOU).size)

        coordinator.conversationSyncStore.applyStreamEvent(
            JsonStepAndSummaryDecoder.JetboxDecodedEvent(
                summaries = emptyList(),
                removedCascadeIds = listOf("cas-stream-1"),
            )
        )
        assertTrue(coordinator.syncState.value.summaries.isEmpty())

        coordinator.connectionStore.onNetworkStatusChanged(NetworkReachabilityStatus.Unsatisfied)
        assertFalse(coordinator.connectionState.value.isDeviceNetworkReachable)
        coordinator.connectionStore.onNetworkStatusChanged(
            NetworkReachabilityStatus.Satisfied("wifi0", isExpensive = false, isConstrained = false)
        )
        assertTrue(coordinator.connectionState.value.isDeviceNetworkReachable)
        coordinator.onBackground()
        assertTrue(coordinator.connectionState.value.isNetworkingSuspended)
        assertEquals(ConnectionLifecyclePhase.Disconnected, coordinator.connectionState.value.lifecyclePhase)
    }

    @Test
    fun testCancelPendingConnectionAttemptAndCreateLocalDraftConversation() {
        val coordinator = AntigravityCoreCoordinator()
        val draftId = coordinator.createLocalDraftConversation(
            workspaceUri = "file:///Users/dev/ledger-svc",
            projectSlug = "ledger-svc",
            title = "Draft check",
        )
        assertTrue(draftId.startsWith("cascade-new-"))
        assertEquals(draftId, coordinator.chatState.value.activeCascadeId)
        assertTrue(coordinator.syncState.value.summaries.any { it.cascadeId == draftId })

        coordinator.cancelPendingConnectionAttempt()
        assertFalse(coordinator.connectionState.value.isConnecting)
        assertEquals(ConnectionLifecyclePhase.Disconnected, coordinator.connectionState.value.lifecyclePhase)
    }

    @Test
    fun testMarkAllReadPreservedAcrossJetboxStreamReplays() = runTest {
        val coordinator = AntigravityCoreCoordinator(scope = this)
        val baseUpdatedMs = 1_700_000_000_000L
        coordinator.conversationSyncStore.applyStreamEvent(
            JsonStepAndSummaryDecoder.JetboxDecodedEvent(
                summaries = listOf(
                    CascadeSummary(
                        cascadeId = "cas-unread-1",
                        title = "Review API",
                        projectSlug = "ledger-svc",
                        workspaceUri = "file:///Users/dev/ledger-svc",
                        status = CortexStepStatus.DONE,
                        stepCount = 5,
                        updatedAtEpochMs = baseUpdatedMs,
                        isUnread = true,
                    ),
                ),
            ),
        )
        assertEquals(1, coordinator.syncState.value.summaries.count { it.isUnread })

        coordinator.markAllConversationsRead()
        assertEquals(0, coordinator.syncState.value.summaries.count { it.isUnread })

        // Replaying the same snapshot from JetboxSubscribeToSummaries must NOT flip unread back to true
        coordinator.conversationSyncStore.applyStreamEvent(
            JsonStepAndSummaryDecoder.JetboxDecodedEvent(
                summaries = listOf(
                    CascadeSummary(
                        cascadeId = "cas-unread-1",
                        title = "Review API",
                        projectSlug = "ledger-svc",
                        workspaceUri = "file:///Users/dev/ledger-svc",
                        status = CortexStepStatus.DONE,
                        stepCount = 5,
                        updatedAtEpochMs = baseUpdatedMs,
                        isUnread = true,
                    ),
                ),
            ),
        )
        assertEquals(0, coordinator.syncState.value.summaries.count { it.isUnread })

        // Genuinely newer activity (higher stepCount + newer timestamp) marks unread again
        coordinator.conversationSyncStore.applyStreamEvent(
            JsonStepAndSummaryDecoder.JetboxDecodedEvent(
                summaries = listOf(
                    CascadeSummary(
                        cascadeId = "cas-unread-1",
                        title = "Review API",
                        projectSlug = "ledger-svc",
                        workspaceUri = "file:///Users/dev/ledger-svc",
                        status = CortexStepStatus.DONE,
                        stepCount = 7,
                        updatedAtEpochMs = baseUpdatedMs + 60_000L,
                        isUnread = true,
                    ),
                ),
            ),
        )
        assertEquals(1, coordinator.syncState.value.summaries.count { it.isUnread })
    }

    @Test
    fun testCloudRelayTimeoutSurfacesStageDiagnosticBreadcrumb() = runTest {
        withContext(Dispatchers.Default) {
            val hangingEngine = MockEngine { _ ->
                delay(5_000L)
                respond("", HttpStatusCode.OK)
            }
            val coordinator = AntigravityCoreCoordinator(
                scope = this,
                clientFactory = { host, csrf, cookie, authUser, resolvedUuid, relayApiKey, tlsConfig ->
                    AntigravityKmpRpcClient(
                        host = host,
                        csrfToken = csrf,
                        sessionCookie = cookie,
                        authUser = authUser,
                        resolvedInstanceUuid = resolvedUuid,
                        relayApiKey = relayApiKey,
                        tlsConfig = tlsConfig,
                        httpClientOverride = HttpClient(hangingEngine),
                    )
                },
            )
            coordinator.connectionStore.handshakeHardTimeoutMs = 350L

            val err = assertFailsWith<AntigravityRpcError.HttpError> {
                coordinator.connectCloudRelay(
                    relayUrlString = "https://antigravity.google/r/0f5819ac-9308-40d8-a308-98b55122c533-v2",
                    sessionCookie = "SAPISID=secret_cookie_value; SID=sid_value",
                    relayApiKey = "AI" + "zaSyDIAGTEST0000000000000000000000000",
                    startSummaryStream = false,
                )
            }
            val expectedEngine = "engine=${platformTransportEngineName()}"
            assertEquals(504, err.statusCode)
            assertTrue(err.body.contains(expectedEngine), "Expected engine tag in timeout error: ${err.body}")
            assertTrue(err.body.contains("origin=antigravity.google.com"), "Expected canonical origin in timeout error: ${err.body}")
            assertTrue(err.body.contains("trace="), "Expected stage trace in timeout error: ${err.body}")
            assertFalse(err.body.contains("secret_cookie_value"), "Timeout error must never leak raw cookie values")
            assertTrue(coordinator.lastHandshakeDiagnostic().contains(expectedEngine))
        }
    }

    @Test
    fun testCoordinatorHydratesConversationsInBackgroundWhenInitialHandshakeDefersSync() = runTest {
        withContext(Dispatchers.Default) {
            val rawUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            val validKey = "AI" + "zaSyDEFERREDSYNC000000000000000000000"
            val countMutex = Mutex()
            var workspaceCalls = 0
            var trajectoryCalls = 0

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
                        val bodyText = runCatching { request.body.toByteArray().decodeToString() }.getOrDefault("")
                        val jsonPayload = countMutex.withLock {
                            when {
                                bodyText.contains("GetWorkspaceInfos") -> {
                                    workspaceCalls += 1
                                    if (workspaceCalls <= 1) {
                                        """{"workspaces":[]}"""
                                    } else {
                                        """{"workspaces":[{"workspaceUri":"file:///Users/dev/payments","displayName":"payments"}]}"""
                                    }
                                }
                                bodyText.contains("GetAllCascadeTrajectories") -> {
                                    trajectoryCalls += 1
                                    if (trajectoryCalls <= 2) {
                                        // Calls 1 & 2 are the initial handshake's local + cloud trajectory fetches
                                        """{"trajectorySummaries":{}}"""
                                    } else {
                                        """{"trajectorySummaries":{"cas-bg-1":{"summary":"Background Hydrated Chat","stepCount":6,"status":"CORTEX_STEP_STATUS_DONE","workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/dev/payments"}]}}}"""
                                    }
                                }
                                else -> """{"projects":[]}"""
                            }
                        }
                        val b64 = ByteString.of(*jsonPayload.encodeToByteArray()).base64()
                        respond(
                            content = """["$b64",[["content-type","application/json"]]]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val coordinator = AntigravityCoreCoordinator(
                scope = this,
                clientFactory = { host, csrf, cookie, authUser, resolvedUuid, relayApiKey, tlsConfig ->
                    AntigravityKmpRpcClient(
                        host = host,
                        csrfToken = csrf,
                        sessionCookie = cookie,
                        authUser = authUser,
                        resolvedInstanceUuid = resolvedUuid,
                        relayApiKey = relayApiKey,
                        tlsConfig = tlsConfig,
                        httpClientOverride = HttpClient(engine),
                    )
                },
            )

            val handshake = coordinator.connectCloudRelay(
                relayUrlString = "https://antigravity.google.com/r/$rawUuid",
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                startSummaryStream = false,
            )
            assertEquals("MacBook Pro", handshake.resolvedHostname)
            assertTrue(handshake.summaries.isEmpty(), "Initial handshake must simulate deferred empty summaries")

            // Wait for the deferred background sync launched by onHandshakeSucceeded to populate summaries.
            var hydrated = false
            for (i in 0 until 80) {
                if (coordinator.syncState.value.summaries.any { it.cascadeId == "cas-bg-1" }) {
                    hydrated = true
                    break
                }
                delay(50L)
            }
            assertTrue(hydrated, "Background hydration must populate summaries when initial handshake returned empty")
        }
    }

    @Test
    fun testLiveUserDisplayNameHydratesFromGetUserStatusAndPersistsAcrossRestart() = runTest {
        withContext(Dispatchers.Default) {
            val rawUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
            val validKey = "AI" + "zaSyUSERPROFILE0000000000000000000000"
            val prefs = InMemoryPreferencesStore()

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = """[[["$rawUuid",["Venciallee","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val bodyText = runCatching { request.body.toByteArray().decodeToString() }.getOrDefault("")
                        val jsonPayload = when {
                            bodyText.contains("GetUserStatus") ->
                                """{"userStatus":{"name":"Vencial Lee","email":"venciallee@gmail.com","userTier":{"name":"Google AI Ultra"}}}"""
                            bodyText.contains("GetWorkspaceInfos") ->
                                """{"workspaces":[{"workspaceUri":"file:///Users/vencial/dsh-superagent","displayName":"dsh-superagent"}]}"""
                            bodyText.contains("GetAllCascadeTrajectories") ->
                                """{"trajectorySummaries":{}}"""
                            else -> """{"projects":[]}"""
                        }
                        val b64 = ByteString.of(*jsonPayload.encodeToByteArray()).base64()
                        respond(
                            content = """["$b64",[["content-type","application/json"]]]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val coordinator = AntigravityCoreCoordinator(
                preferencesStore = prefs,
                scope = this,
                clientFactory = { host, csrf, cookie, authUser, resolvedUuid, relayApiKey, tlsConfig ->
                    AntigravityKmpRpcClient(
                        host = host,
                        csrfToken = csrf,
                        sessionCookie = cookie,
                        authUser = authUser,
                        resolvedInstanceUuid = resolvedUuid,
                        relayApiKey = relayApiKey,
                        tlsConfig = tlsConfig,
                        httpClientOverride = HttpClient(engine),
                    )
                },
            )

            // Fresh live coordinator starts with null userDisplayName (never mock "Alex")
            assertEquals(null, coordinator.connectionState.value.userDisplayName)

            coordinator.connectCloudRelay(
                relayUrlString = "https://antigravity.google.com/r/$rawUuid",
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                startSummaryStream = false,
            )

            // Wait for background GetUserStatus hydration launched in onHandshakeSucceeded
            var resolved: String? = null
            for (i in 0 until 60) {
                resolved = coordinator.connectionState.value.userDisplayName
                if (resolved != null) break
                delay(25L)
            }
            assertEquals("Vencial", resolved)

            // Cold-starting a fresh coordinator with the same preferencesStore hydrates cached name immediately
            val restarted = AntigravityCoreCoordinator(preferencesStore = prefs)
            assertEquals("Vencial", restarted.connectionState.value.userDisplayName)

            // Disconnect clears both live state and persisted userDisplayName
            coordinator.disconnectAndClearCredentials()
            assertEquals(null, coordinator.connectionState.value.userDisplayName)
            assertEquals(null, AntigravityCoreCoordinator(preferencesStore = prefs).connectionState.value.userDisplayName)
        }
    }

    @Test
    fun testMultiHostDeviceSwitchUpdatesScopedProjectsAndPreservesCloudRepos() = runTest {
        withContext(Dispatchers.Default) {
            val mbpUuid = "11111111-1111-4111-8111-111111111111-v2"
            val macMiniUuid = "22222222-2222-4222-8222-222222222222-v2"
            val macMiniName = "huangjiafandemac-mini-local-swift-vapor"
            val validKey = "AI" + "zaSyMULTIHOSTTEST00000000000000000000"

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = """[[["$mbpUuid",["MacBook Pro","2.33.0",true],1,[1740000000,0]],["$macMiniUuid",["$macMiniName","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val bodyText = runCatching { request.body.toByteArray().decodeToString() }.getOrDefault("")
                        val targetsMini = bodyText.contains(macMiniUuid)
                        val jsonPayload = when {
                            bodyText.contains("ListProjects") ->
                                """{"projectIds":["cloud-pocket-1"]}"""
                            bodyText.contains("ReadProject") ->
                                """{"project":{"id":"cloud-pocket-1","name":"venciallee/PocketAntigravity"}}"""
                            bodyText.contains("GetWorkspaceInfos") && targetsMini ->
                                """{"workspaces":[{"workspaceUri":"file:///Users/mini/vapor-backend","displayName":"vapor-backend"},{"workspaceUri":"file:///Users/mini/PocketAntigravity","displayName":"PocketAntigravity"}]}"""
                            bodyText.contains("GetWorkspaceInfos") ->
                                """{"workspaces":[{"workspaceUri":"file:///Users/mbp/ios-app","displayName":"ios-app"},{"workspaceUri":"file:///Users/mbp/PocketAntigravity","displayName":"PocketAntigravity"}]}"""
                            bodyText.contains("GetAllCascadeTrajectories") && targetsMini ->
                                """{"trajectorySummaries":{"cas-mini-1":{"summary":"Mini Vapor Migration","stepCount":3,"status":"CORTEX_STEP_STATUS_DONE","workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/mini/PocketAntigravity"}]}}}"""
                            bodyText.contains("GetAllCascadeTrajectories") ->
                                """{"trajectorySummaries":{"cas-mbp-1":{"summary":"MBP iOS Build","stepCount":4,"status":"CORTEX_STEP_STATUS_DONE","workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/mbp/PocketAntigravity"}]}}}"""
                            else -> """{"projects":[]}"""
                        }
                        val b64 = ByteString.of(*jsonPayload.encodeToByteArray()).base64()
                        respond(
                            content = """["$b64",[["content-type","application/json"]]]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            val coordinator = AntigravityCoreCoordinator(
                autoPreloadConversations = false,
                clientFactory = { host, csrf, cookie, authUser, resolvedUuid, relayApiKey, tlsConfig ->
                    AntigravityKmpRpcClient(
                        host = host,
                        csrfToken = csrf,
                        sessionCookie = cookie,
                        authUser = authUser,
                        resolvedInstanceUuid = resolvedUuid,
                        relayApiKey = relayApiKey,
                        tlsConfig = tlsConfig,
                        httpClientOverride = HttpClient(engine),
                    )
                },
            )

            try {
                coordinator.connectCloudRelay(
                    relayUrlString = "https://antigravity.google.com/r/$mbpUuid",
                    sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                    relayApiKey = validKey,
                    startSummaryStream = false,
                )

                // Initial handshake targets MacBook Pro (and federates both reachable Macs + Cloud)
                val mbpScope = AgentsHostFilterScope.LocalHost(mbpUuid, "MacBook Pro")
                val miniScope = AgentsHostFilterScope.LocalHost(macMiniUuid, macMiniName)
                val cloudScope = AgentsHostFilterScope.AntigravityCloud

                // Switch to Mac mini -> scoped refresh must fetch vapor-backend & Mac mini PocketAntigravity and reconcile selectedProjectId
                coordinator.selectHostScope(miniScope)
                var miniProjects: List<ProjectWorkspace> = emptyList()
                for (i in 0 until 60) {
                    miniProjects = coordinator.filteredProjects(hostScope = miniScope)
                    if (coordinator.connectionState.value.activeHost?.instanceId == macMiniUuid &&
                        miniProjects.any { it.name == "vapor-backend" } &&
                        coordinator.workspaceStore.state.value.selectedProjectId.let { selId ->
                            miniProjects.any { it.id == selId }
                        }
                    ) {
                        break
                    }
                    delay(25L)
                }
                assertEquals(macMiniUuid, coordinator.connectionState.value.activeHost?.instanceId)
                assertEquals(setOf("vapor-backend", "PocketAntigravity"), miniProjects.map { it.name }.toSet())
                assertFalse(miniProjects.any { it.name == "ios-app" }, "MacBook Pro repo must not leak into Mac mini scope")
                assertFalse(miniProjects.any { it.runtime == ProjectRuntimeTarget.CLOUD }, "Cloud repo must not leak into Mac mini scope")
                val selectedMiniId = coordinator.workspaceStore.state.value.selectedProjectId
                assertTrue(miniProjects.any { it.id == selectedMiniId }, "Selected project must belong to Mac mini after device switch")

                // Mac mini's PocketAntigravity summary must point to Mac mini's reconciled project ID
                val miniSummary = coordinator.syncState.value.summaries.firstOrNull { it.cascadeId == "cas-mini-1" }
                val miniPocketProj = miniProjects.first { it.name == "PocketAntigravity" }
                assertEquals(miniPocketProj.id, miniSummary?.projectSlug)

                // 0-conversation Cloud project must survive local-host-only refresh
                val cloudProjects = coordinator.filteredProjects(hostScope = cloudScope)
                assertTrue(
                    cloudProjects.any { it.name == "venciallee/PocketAntigravity" },
                    "0-conversation Cloud project must remain available after local host refresh",
                )

                // Switch back to MacBook Pro -> scoped projects must isolate to MacBook Pro repos only
                coordinator.selectHostScope(mbpScope)
                var mbpProjects: List<ProjectWorkspace> = emptyList()
                for (i in 0 until 60) {
                    mbpProjects = coordinator.filteredProjects(hostScope = mbpScope)
                    if (coordinator.connectionState.value.activeHost?.instanceId == mbpUuid &&
                        mbpProjects.any { it.name == "ios-app" } &&
                        coordinator.workspaceStore.state.value.selectedProjectId.let { selId ->
                            mbpProjects.any { it.id == selId }
                        }
                    ) {
                        break
                    }
                    delay(25L)
                }
                assertEquals(mbpUuid, coordinator.connectionState.value.activeHost?.instanceId)
                assertEquals(setOf("ios-app", "PocketAntigravity"), mbpProjects.map { it.name }.toSet())
                assertFalse(mbpProjects.any { it.name == "vapor-backend" }, "Mac mini repo must not leak into MacBook Pro scope")
            } finally {
                coordinator.disconnectAndClearCredentials()
                coordinator.close()
            }
        }
    }

    @Test
    fun testProjectMatchesHostScopeIsolatesMacBookProHostFromSecondMac() = runTest {
        val syncStore = ConversationSyncStore(scope = this, projectionStorage = InMemoryProjectionStorage())
        val mbpHost = RemoteHostInstance(
            instanceId = "uuid-mbp",
            hostname = "MacBook Pro",
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = "https://antigravity.google.com/r/uuid-mbp",
            isOnline = true,
        )
        val miniHost = RemoteHostInstance(
            instanceId = "uuid-mini",
            hostname = "huangjiafandemac-mini-local-swift-vapor",
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = "https://antigravity.google.com/r/uuid-mini",
            isOnline = true,
        )
        val knownHosts = listOf(mbpHost, miniHost)

        // Legacy/untagged project with hostName == "MacBook Pro" and null originInstanceUuid
        val legacyMbpProject = ProjectWorkspace(
            id = "legacy-mbp-repo",
            name = "legacy-mbp-repo",
            pathDisplay = "~/legacy-mbp-repo",
            workspaceUri = "file:///Users/dev/legacy-mbp-repo",
            runtime = ProjectRuntimeTarget.MAC_BOOK_PRO,
            hostName = "MacBook Pro",
            originInstanceUuid = null,
        )
        val miniProject = ProjectWorkspace(
            id = "vapor-svc",
            name = "vapor-svc",
            pathDisplay = "~/vapor-svc",
            workspaceUri = "file:///Users/mini/vapor-svc",
            runtime = ProjectRuntimeTarget.MAC_BOOK_PRO,
            hostName = miniHost.hostname,
            originInstanceUuid = miniHost.instanceId,
        )
        val cloudProject = ProjectWorkspace(
            id = "cloud:venciallee/PocketAntigravity",
            name = "venciallee/PocketAntigravity",
            pathDisplay = "Cloud · venciallee/PocketAntigravity",
            workspaceUri = "cloud://venciallee/PocketAntigravity",
            runtime = ProjectRuntimeTarget.CLOUD,
            hostName = "Cloud",
        )

        val mbpScope = AgentsHostFilterScope.LocalHost(mbpHost.instanceId, mbpHost.hostname)
        val miniScope = AgentsHostFilterScope.LocalHost(miniHost.instanceId, miniHost.hostname)

        assertTrue(syncStore.projectMatchesHostScope(legacyMbpProject, mbpScope, knownHosts, activeHost = miniHost))
        assertFalse(
            syncStore.projectMatchesHostScope(legacyMbpProject, miniScope, knownHosts, activeHost = miniHost),
            "Project with hostName='MacBook Pro' must never leak into Mac mini scope when multiple local hosts exist",
        )
        assertTrue(syncStore.projectMatchesHostScope(miniProject, miniScope, knownHosts, activeHost = miniHost))
        assertFalse(syncStore.projectMatchesHostScope(cloudProject, miniScope, knownHosts, activeHost = miniHost))
        assertTrue(syncStore.projectMatchesHostScope(cloudProject, AgentsHostFilterScope.AntigravityCloud, knownHosts, activeHost = miniHost))
    }

    @Test
    fun testConversationPreloadHydratesLoadingTitleCachesStepsAndPersistsProjectCollapse() = runTest {
        withContext(Dispatchers.Default) {
            val prefs = InMemoryPreferencesStore()
            val storage = InMemoryProjectionStorage()
            val rawUuid = "98765432-1111-4000-8000-123456789abc"
            val unhydratedId = "aaaa1111-2222-4000-8000-000000000001"
            val resolvedId = "bbbb1111-2222-4000-8000-000000000002"
            val validKey = "AI" + "zaSyTESTPRELOAD00000000000000000000000"

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = """[[["$rawUuid",["MacBook-Pro","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val bodyText = runCatching { request.body.toByteArray().decodeToString() }.getOrDefault("")
                        val jsonPayload = when {
                            bodyText.contains("GetWorkspaceInfos") ->
                                """{"workspaces":[{"workspaceUri":"file:///Users/dev/slardar_app_ai","displayName":"slardar_app_ai"}]}"""
                            bodyText.contains("GetAllCascadeTrajectories") ->
                                """{
                                    "trajectorySummaries": {
                                        "$unhydratedId": {
                                            "stepCount": 2,
                                            "status": "CASCADE_RUN_STATUS_IDLE",
                                            "lastModifiedTime": "2026-04-01T10:00:00Z",
                                            "workspaces": [{"workspaceFolderAbsoluteUri": "file:///Users/dev/slardar_app_ai"}]
                                        },
                                        "$resolvedId": {
                                            "summary": "Optimize startup trace",
                                            "stepCount": 2,
                                            "status": "CASCADE_RUN_STATUS_IDLE",
                                            "lastModifiedTime": "2026-04-02T10:00:00Z",
                                            "workspaces": [{"workspaceFolderAbsoluteUri": "file:///Users/dev/slardar_app_ai"}]
                                        }
                                    }
                                }"""
                            bodyText.contains("GetCascadeTrajectorySteps") ->
                                """{
                                    "steps": [
                                        {
                                            "stepIndex": 0,
                                            "type": "CORTEX_STEP_TYPE_USER_INPUT",
                                            "status": "CORTEX_STEP_STATUS_DONE",
                                            "userInput": {"userResponse": "Investigate Slardar cold start regression"}
                                        },
                                        {
                                            "stepIndex": 1,
                                            "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
                                            "status": "CORTEX_STEP_STATUS_DONE",
                                            "plannerResponse": {"response": "Cached steps ready for Frame 0."}
                                        }
                                    ]
                                }"""
                            else -> """{}"""
                        }
                        val b64 = ByteString.of(*jsonPayload.encodeToByteArray()).base64()
                        respond(
                            content = """["$b64",[["content-type","application/json"]]]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    else -> respond("", HttpStatusCode.NotFound)
                }
            }

            // 1. Before hydration, an unhydrated server summary never displays "New Conversation":
            //    unpaired falls back to "Untitled conversation", and while hydrating displays "Loading..."
            val previewCoordinator = AntigravityCoreCoordinator(
                preferencesStore = prefs,
                projectionStorage = storage,
                autoPreloadConversations = false,
            )
            val unhydratedSummary = CascadeSummary(
                cascadeId = unhydratedId,
                title = "New Conversation",
                hasResolvedTitle = false,
                projectSlug = "slardar_app_ai",
                workspaceUri = "file:///Users/dev/slardar_app_ai",
                status = CortexStepStatus.DONE,
                stepCount = 2,
            )
            assertFalse(previewCoordinator.isSummaryTitleLoading(unhydratedSummary))
            assertEquals("Untitled conversation", previewCoordinator.displayTitleForSummary(unhydratedSummary))
            previewCoordinator.conversationSyncStore.markHydrating(unhydratedId)
            assertTrue(previewCoordinator.isSummaryTitleLoading(unhydratedSummary))
            assertEquals("Loading...", previewCoordinator.displayTitleForSummary(unhydratedSummary))

            // Local user-created drafts must still display their draft title without loading spinner
            val localDraftId = previewCoordinator.createLocalDraftConversation(
                workspaceUri = "file:///Users/dev/slardar_app_ai",
                projectSlug = "slardar_app_ai",
                title = "New Conversation",
            )
            val localDraftSummary = previewCoordinator.syncState.value.summaries.first { it.cascadeId == localDraftId }
            assertFalse(previewCoordinator.isSummaryTitleLoading(localDraftSummary))
            assertEquals("New Conversation", previewCoordinator.displayTitleForSummary(localDraftSummary))

            // 2. Live connection schedules background preloader -> hydrates title & caches steps to memory + disk
            val coordinator = AntigravityCoreCoordinator(
                preferencesStore = prefs,
                projectionStorage = storage,
                scope = this,
                clientFactory = { host, csrf, cookie, authUser, resolvedUuid, relayApiKey, tlsConfig ->
                    AntigravityKmpRpcClient(
                        host = host,
                        csrfToken = csrf,
                        sessionCookie = cookie,
                        authUser = authUser,
                        resolvedInstanceUuid = resolvedUuid,
                        relayApiKey = relayApiKey,
                        tlsConfig = tlsConfig,
                        httpClientOverride = HttpClient(engine),
                    )
                },
            )

            coordinator.connectCloudRelay(
                relayUrlString = "https://antigravity.google.com/r/$rawUuid",
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                startSummaryStream = false,
            )

            var hydratedTitle: String? = null
            for (i in 0 until 80) {
                val summary = coordinator.syncState.value.summaries.firstOrNull { it.cascadeId == unhydratedId }
                val cachedSteps = coordinator.chatState.value.stepsByCascadeId[unhydratedId].orEmpty()
                if (summary?.hasResolvedTitle == true && cachedSteps.size == 2) {
                    hydratedTitle = summary.title
                    break
                }
                delay(25L)
            }
            assertEquals("Investigate Slardar cold start regression", hydratedTitle)
            assertEquals(2, storage.loadSteps(unhydratedId).size)
            assertFalse(coordinator.isSummaryTitleLoading(coordinator.syncState.value.summaries.first { it.cascadeId == unhydratedId }))

            // 3. Cold-start hydration warms persisted titles + steps immediately into memory for Frame 0 entry
            val coldStarted = AntigravityCoreCoordinator(
                preferencesStore = prefs,
                projectionStorage = storage,
                autoPreloadConversations = false,
            )
            coldStarted.hydrateOfflineCache()
            val restoredSummary = coldStarted.syncState.value.summaries.firstOrNull { it.cascadeId == unhydratedId }
            assertEquals("Investigate Slardar cold start regression", restoredSummary?.title)
            assertTrue(restoredSummary?.hasResolvedTitle == true)
            assertEquals(2, coldStarted.chatState.value.stepsByCascadeId[unhydratedId]?.size)

            // 4. Collapsing a project persists across restarts via KeyValuePreferencesStore
            assertFalse(coordinator.workspaceStore.isProjectCollapsed("slardar_app_ai"))
            coordinator.workspaceStore.toggleProjectExpanded("slardar_app_ai")
            assertTrue(coordinator.workspaceStore.isProjectCollapsed("slardar_app_ai"))

            val restartedAfterCollapse = AntigravityCoreCoordinator(
                preferencesStore = prefs,
                projectionStorage = storage,
                autoPreloadConversations = false,
            )
            assertTrue(restartedAfterCollapse.workspaceStore.isProjectCollapsed("slardar_app_ai"))

            previewCoordinator.close()
            coldStarted.close()
            restartedAfterCollapse.close()
        }
    }

    @Test
    fun testFailedOrDeferredHandshakePreservesCachedProjectsAndSummaries() = runTest {
        val hostUuid = "huangjiafandemac-mini-local-swift-vapor"
        val storage = InMemoryProjectionStorage()
        storage.saveHostShards(
            listOf(
                HostProjectionShard(
                    hostKey = "host:$hostUuid",
                    instanceId = hostUuid,
                    hostname = hostUuid,
                    projects = listOf(
                        ProjectWorkspace(
                            id = "PocketAntigravity",
                            name = "PocketAntigravity",
                            pathDisplay = "Local · $hostUuid",
                            workspaceUri = "file:///Users/mini/PocketAntigravity",
                            runtime = ProjectRuntimeTarget.MAC_BOOK_PRO,
                            hostName = hostUuid,
                            activeBranch = "main",
                            originInstanceUuid = hostUuid,
                        ),
                    ),
                    summaries = listOf(
                        CascadeSummary(
                            cascadeId = "cas-cached-mini-1",
                            title = "Cached Mini Session",
                            projectSlug = "PocketAntigravity",
                            workspaceUri = "file:///Users/mini/PocketAntigravity",
                            status = CortexStepStatus.DONE,
                            stepCount = 3,
                            originInstanceUuid = hostUuid,
                            originHostName = hostUuid,
                        ),
                    ),
                ),
            ),
        )

        val syncStore = ConversationSyncStore(scope = this, projectionStorage = storage)
        syncStore.hydrateFromCache()
        assertEquals(1, syncStore.state.value.projects.count { !it.isNoProject })
        assertEquals(1, syncStore.state.value.summaries.size)

        val host = RemoteHostInstance(
            instanceId = hostUuid,
            hostname = hostUuid,
            channel = RemoteConnectionChannel.CLOUD_RELAY,
            endpointUrl = "https://antigravity.google.com/r/$hostUuid",
            isOnline = false,
        )
        val failedHandshake = BackendHandshakeResult(
            latencyMs = 180,
            workspaces = emptyList(),
            summaries = emptyList(),
            resolvedHostname = hostUuid,
            resolvedInstanceUuid = hostUuid,
            availableRelayInstances = listOf(
                RelayInstanceInfo(uuid = hostUuid, name = hostUuid, status = RelayInstanceStatus.DISCONNECTED),
            ),
            isSelectedHostOnline = false,
            succeededInstanceUuids = emptyList(),
            initialSyncCompleted = false,
        )
        syncStore.applyHandshake(host, failedHandshake)

        // Cached project & conversation MUST survive failed/deferred handshake in memory and on disk
        assertTrue(syncStore.state.value.projects.any { it.name == "PocketAntigravity" })
        assertTrue(syncStore.state.value.summaries.any { it.cascadeId == "cas-cached-mini-1" })
        val persistedShard = storage.loadAllHostShards().firstOrNull { it.hostKey == "host:$hostUuid" }
        assertEquals(1, persistedShard?.projects?.size)
        assertEquals(1, persistedShard?.summaries?.size)
    }

    @Test
    fun testSendMessageAgainstUnregisteredRelayQueuesOutboxMarksHostOfflineAndStopsStreaming() = runTest {
        withContext(Dispatchers.Default) {
            val validKey = "AI" + "zaSySENDUNREG400000000000000000000000"
            val hostUuid = "huangjiafandemac-mini-local-swift-vapor"
            val boqUnregistered = """[9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo","INSTANCE_NOT_REGISTERED","antigravity.googleapis.com"]]]"""
            val callMutex = Mutex()
            var startCascadeCalls = 0

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/ListInstances") -> {
                        respond(
                            content = """[[["$hostUuid",["$hostUuid","2.33.0",true],1,[1740000000,0]]],5]""",
                            status = HttpStatusCode.OK,
                            headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                        )
                    }
                    path.endsWith("/ProxyCommand") -> {
                        val bodyText = runCatching { request.body.toByteArray().decodeToString() }.getOrDefault("")
                        if (bodyText.contains("StartCascade") || bodyText.contains("SendUserCascadeMessage")) {
                            callMutex.withLock { startCascadeCalls += 1 }
                            respond(
                                content = boqUnregistered,
                                status = HttpStatusCode.BadRequest,
                                headers = headersOf(HttpHeaders.ContentType, "application/json+protobuf"),
                            )
                        } else {
                            val payload = if (bodyText.contains("GetWorkspaceInfos")) {
                                """{"workspaces":[{"workspaceUri":"file:///Users/mini/PocketAntigravity","displayName":"PocketAntigravity"}]}"""
                            } else {
                                """{"trajectorySummaries":{}}"""
                            }
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

            val coordinator = AntigravityCoreCoordinator(
                preferencesStore = InMemoryPreferencesStore(),
                projectionStorage = InMemoryProjectionStorage(),
                autoPreloadConversations = false,
                clientFactory = { host, csrf, cookie, authUser, resolvedUuid, relayApiKey, tlsConfig ->
                    AntigravityKmpRpcClient(
                        host = host,
                        csrfToken = csrf,
                        sessionCookie = cookie,
                        authUser = authUser,
                        resolvedInstanceUuid = resolvedUuid,
                        relayApiKey = relayApiKey,
                        tlsConfig = tlsConfig,
                        httpClientOverride = HttpClient(engine),
                    )
                },
            )

            coordinator.connectCloudRelay(
                relayUrlString = "https://antigravity.google.com/r/$hostUuid",
                sessionCookie = "SAPISID=test_sapisid; SID=test_sid",
                relayApiKey = validKey,
                startSummaryStream = false,
            )
            assertTrue(
                coordinator.connectionState.value.activeHost?.isOnline == true,
                "Expected host online immediately after initial handshake",
            )

            val draftId = coordinator.createLocalDraftConversation(
                workspaceUri = "",
                projectSlug = "No Project",
                title = "没拉到任何 project 啊",
            )
            val outcome = coordinator.sendMessage(
                cascadeId = draftId,
                message = "没拉到任何 project 啊",
                workspaceUri = "",
                isOptimisticDraft = true,
                instanceUuidOverride = hostUuid,
            )

            assertFalse(outcome.dispatchedLive, "Expected dispatchedLive=false, outcome=$outcome")
            assertTrue(outcome.queuedInOutbox, "Expected queuedInOutbox=true, outcome=$outcome")
            assertTrue(outcome.hostOfflineDetected, "Expected hostOfflineDetected=true, outcome=$outcome")
            val observedCalls = callMutex.withLock { startCascadeCalls }
            assertEquals(1, observedCalls, "StartCascade must not fire twice on unregistered host")
            assertFalse(coordinator.connectionState.value.activeHost?.isOnline == true, "Active host must flip offline immediately")
            assertFalse(coordinator.isCascadeActivelyStreaming(outcome.resolvedCascadeId), "Queued offline turn must never appear streaming")
            val summary = coordinator.syncState.value.summaries.firstOrNull { it.cascadeId == outcome.resolvedCascadeId }
            assertEquals(CortexStepStatus.PENDING, summary?.status, "Expected PENDING summary status, summary=$summary")
            assertFalse((outcome.errorMessage ?: "").contains("type.googleapis.com"), "Raw @type leaked: ${outcome.errorMessage}")
            coordinator.close()
        }
    }

    @Test
    fun testIdleCachedTrajectoryFastPathSkipsRpcAndForceRefreshBypassesCache() = runTest {
        withContext(Dispatchers.Default) {
            val storage = InMemoryProjectionStorage()
            val cid = "cas-idle-fastpath-1"
            storage.saveSteps(
                cid,
                listOf(
                    CascadeStep(
                        cascadeId = cid,
                        stepIndex = 0,
                        type = CortexStepType.USER_INPUT,
                        status = CortexStepStatus.DONE,
                        userInput = "Initial question",
                    ),
                    CascadeStep(
                        cascadeId = cid,
                        stepIndex = 1,
                        type = CortexStepType.PLANNER_RESPONSE,
                        status = CortexStepStatus.DONE,
                        plannerResponse = dev.antigravity.shared.model.PlannerResponsePayload(response = "Initial answer"),
                    ),
                ),
            )

            val countMutex = Mutex()
            var stepFetchCalls = 0
            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/GetWorkspaceInfos") -> respond(
                        content = """{"workspaces":[{"workspaceUri":"file:///Users/dev/app","displayName":"app"}]}""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json"),
                    )
                    path.endsWith("/GetAllCascadeTrajectories") -> respond(
                        content = """{"trajectorySummaries":{"$cid":{"summary":"Idle Cached Chat","stepCount":2,"status":"CORTEX_STEP_STATUS_DONE","lastModifiedTime":"2026-01-01T00:00:00Z","workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/dev/app"}]}}}""",
                        status = HttpStatusCode.OK,
                        headers = headersOf(HttpHeaders.ContentType, "application/json"),
                    )
                    path.endsWith("/GetCascadeTrajectorySteps") -> {
                        val ct = request.body.contentType?.toString()
                            ?: request.headers[HttpHeaders.ContentType].orEmpty()
                        if (ct.contains("application/proto")) {
                            respond(
                                content = "Unsupported Media Type",
                                status = HttpStatusCode.UnsupportedMediaType,
                                headers = headersOf(HttpHeaders.ContentType, "text/plain"),
                            )
                        } else {
                            countMutex.withLock { stepFetchCalls += 1 }
                            respond(
                                content = """{"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Initial question"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Refreshed answer"}}]}""",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json"),
                            )
                        }
                    }
                    else -> respond("{}", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                }
            }

            val coordinator = AntigravityCoreCoordinator(
                preferencesStore = InMemoryPreferencesStore(),
                projectionStorage = storage,
                autoPreloadConversations = false,
                clientFactory = { host, csrf, cookie, authUser, resolvedUuid, relayApiKey, tlsConfig ->
                    AntigravityKmpRpcClient(
                        host = host,
                        csrfToken = csrf,
                        sessionCookie = cookie,
                        authUser = authUser,
                        resolvedInstanceUuid = resolvedUuid,
                        relayApiKey = relayApiKey,
                        tlsConfig = tlsConfig,
                        httpClientOverride = HttpClient(engine),
                    )
                },
            )
            coordinator.connectDirectLan(
                endpointUrlString = "http://127.0.0.1:42100",
                csrfToken = "csrf-idle-test",
                startSummaryStream = false,
            )

            // 1. Entering cached idle DONE conversation -> 0-RTT fast-path, 0 HTTP calls
            val fastSteps = coordinator.syncSteps(cascadeId = cid, knownStepCount = 2)
            assertEquals(2, fastSteps.size)
            assertEquals("Initial answer", fastSteps[1].plannerResponse?.response)
            assertEquals(0, countMutex.withLock { stepFetchCalls }, "Idle cached DONE trajectory must serve in 0 RTT")

            // 2. Explicit forceSyncSteps bypasses idle cache and fetches fresh server steps
            val forcedSteps = coordinator.forceSyncSteps(cascadeId = cid, knownStepCount = 2)
            assertEquals(2, forcedSteps.size)
            assertEquals("Refreshed answer", forcedSteps[1].plannerResponse?.response)
            assertEquals(1, countMutex.withLock { stepFetchCalls }, "forceSyncSteps must bypass idle cache")
            coordinator.close()
        }
    }

    @Test
    fun testConcurrentPreloadAndForegroundSyncCoalesceIntoSingleRpc() = runTest {
        withContext(Dispatchers.Default) {
            val cid = "cas-coalesce-kmp-1"
            val countMutex = Mutex()
            var stepFetchCalls = 0

            val engine = MockEngine { request ->
                val path = request.url.encodedPath
                when {
                    path.endsWith("/GetCascadeTrajectorySteps") -> {
                        val ct = request.body.contentType?.toString()
                            ?: request.headers[HttpHeaders.ContentType].orEmpty()
                        if (ct.contains("application/proto")) {
                            respond(
                                content = "Unsupported Media Type",
                                status = HttpStatusCode.UnsupportedMediaType,
                                headers = headersOf(HttpHeaders.ContentType, "text/plain"),
                            )
                        } else {
                            countMutex.withLock { stepFetchCalls += 1 }
                            delay(120L)
                            respond(
                                content = """{"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Coalesced prompt"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Coalesced reply"}}]}""",
                                status = HttpStatusCode.OK,
                                headers = headersOf(HttpHeaders.ContentType, "application/json"),
                            )
                        }
                    }
                    else -> respond("{}", HttpStatusCode.OK, headersOf(HttpHeaders.ContentType, "application/json"))
                }
            }

            val client = AntigravityKmpRpcClient(
                host = RemoteHostInstance(
                    instanceId = "mac-coalesce",
                    hostname = "Coalesce Mac",
                    channel = RemoteConnectionChannel.DIRECT_HOST,
                    endpointUrl = "http://127.0.0.1:42101",
                    isOnline = true,
                ),
                csrfToken = "csrf-coalesce",
                httpClientOverride = HttpClient(engine),
            )
            val store = CascadeChatDomainStore(projectionStorage = InMemoryProjectionStorage())

            val results = listOf(
                async { store.preloadSteps(client, cid, knownStepCount = 2) },
                async { store.syncSteps(client, cid, knownStepCount = 2) },
            ).awaitAll()

            assertEquals(2, results[0].size)
            assertEquals(2, results[1].size)
            assertEquals("Coalesced reply", results[1][1].plannerResponse?.response)
            assertEquals(1, countMutex.withLock { stepFetchCalls }, "Concurrent preloadSteps + syncSteps must coalesce into 1 RPC")
        }
    }
}
