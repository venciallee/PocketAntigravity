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
import dev.antigravity.shared.platform.NetworkReachabilityStatus
import dev.antigravity.shared.protocol.BackendHandshakeResult
import dev.antigravity.shared.protocol.ConnectionLifecyclePhase
import dev.antigravity.shared.protocol.JsonStepAndSummaryDecoder
import dev.antigravity.shared.protocol.RelayInstanceInfo
import dev.antigravity.shared.protocol.RelayInstanceStatus
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
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
}
