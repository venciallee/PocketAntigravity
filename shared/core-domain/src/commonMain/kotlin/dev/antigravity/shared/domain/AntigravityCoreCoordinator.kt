package dev.antigravity.shared.domain

import dev.antigravity.shared.markdown.MarkdownBlock
import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.AgentsQuickFilter
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.CascadeUserInteractionPayload
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.LiveProgressAgentSummary
import dev.antigravity.shared.model.LiveProgressPhase
import dev.antigravity.shared.model.LiveProgressSnapshot
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.model.ThinkingEffortLevel
import dev.antigravity.shared.platform.InMemoryPreferencesStore
import dev.antigravity.shared.platform.InMemorySecretStore
import dev.antigravity.shared.platform.KeyValuePreferencesStore
import dev.antigravity.shared.platform.NetworkReachabilityMonitoring
import dev.antigravity.shared.platform.NoopNetworkReachabilityMonitor
import dev.antigravity.shared.platform.PowerStateProviding
import dev.antigravity.shared.platform.SecretStore
import dev.antigravity.shared.platform.StaticPowerStateProvider
import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.AntigravityRpcError
import dev.antigravity.shared.protocol.BackendHandshakeResult
import dev.antigravity.shared.protocol.FederatedWorkspaceSyncResult
import dev.antigravity.shared.protocol.HostCapability
import dev.antigravity.shared.protocol.HostReachabilityProbeResult
import dev.antigravity.shared.protocol.RelayInstanceInfo
import dev.antigravity.shared.protocol.TlsEngineConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.Throws

/**
 * Unified KMP Core Coordinator exported to both iOS (via SKIE `AsyncSequence` + `async throws`)
 * and Android (via Jetpack Compose `collectAsStateWithLifecycle`).
 *
 * Composes 7 cohesive `StateFlow`-backed stores:
 * - [ConnectionDomainStore]: Direct LAN / Cloud Relay / Pairing URI / Keychain / Reachability
 * - [ConversationSyncStore]: Federated sync + per-host sharded offline cache + Jetbox stream
 * - [CascadeChatDomainStore]: Binary-first Protobuf + adaptive JSON ceiling trajectory sync + Durable Outbox + PC interactions
 * - [WorkspaceAndAutomationStore]: Projects, Display Options, Sidecar Automations, Add Context chips
 * - [ReviewAndVcsStore]: Artifacts, Plan Review comments, Turn Diffs, Git VCS stage/commit/push
 * - [OrchestrationAndSideChannelStore]: Overview, `/btw` Side Questions, Swarm Board, Queued Messages, Voice Mode
 * - [SettingsAndCustomizationStore]: Model/Mode/Effort/Agent catalog, Quota, Permissions, Customizations, Appearance
 */
public class AntigravityCoreCoordinator(
    secretStore: SecretStore = InMemorySecretStore(),
    networkMonitor: NetworkReachabilityMonitoring = NoopNetworkReachabilityMonitor(),
    powerStateProvider: PowerStateProviding = StaticPowerStateProvider(),
    preferencesStore: KeyValuePreferencesStore = InMemoryPreferencesStore(),
    projectionStorage: ProjectionStoragePort = InMemoryProjectionStorage(),
    private val scope: CoroutineScope = CoroutineScope(
        SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, _ ->
            // Prevent uncaught background coroutine exceptions from aborting Kotlin/Native via propagateExceptionFinalResort.
        }
    ),
    clientFactory: (
        host: RemoteHostInstance,
        csrfToken: String?,
        sessionCookie: String?,
        authUser: String?,
        resolvedInstanceUuid: String?,
        relayApiKey: String?,
        tlsConfig: TlsEngineConfig,
    ) -> AntigravityKmpRpcClient = { host, csrf, cookie, authUser, resolvedUuid, relayApiKey, tlsConfig ->
        AntigravityKmpRpcClient(
            host = host,
            csrfToken = csrf,
            sessionCookie = cookie,
            authUser = authUser,
            resolvedInstanceUuid = resolvedUuid,
            relayApiKey = relayApiKey,
            tlsConfig = tlsConfig,
        )
    },
) {
    private val _capabilityErrorBanner = MutableStateFlow<String?>(null)
    public val capabilityErrorBanner: StateFlow<String?> = _capabilityErrorBanner.asStateFlow()

    public val connectionStore: ConnectionDomainStore = ConnectionDomainStore(
        secretStore = secretStore,
        networkMonitor = networkMonitor,
        powerStateProvider = powerStateProvider,
        preferencesStore = preferencesStore,
        projectionStorage = projectionStorage,
        clientFactory = clientFactory,
    )

    public val conversationSyncStore: ConversationSyncStore = ConversationSyncStore(
        scope = scope,
        projectionStorage = projectionStorage,
    )

    public val chatStore: CascadeChatDomainStore = CascadeChatDomainStore(
        projectionStorage = projectionStorage,
        onCapabilityError = ::reportCapabilityError,
    )

    public val workspaceStore: WorkspaceAndAutomationStore = WorkspaceAndAutomationStore(
        onCapabilityError = ::reportCapabilityError,
    )

    public val reviewStore: ReviewAndVcsStore = ReviewAndVcsStore(
        onCapabilityError = ::reportCapabilityError,
    )

    public val orchestrationStore: OrchestrationAndSideChannelStore = OrchestrationAndSideChannelStore(
        onCapabilityError = ::reportCapabilityError,
    )

    public val settingsStore: SettingsAndCustomizationStore = SettingsAndCustomizationStore(
        onCapabilityError = ::reportCapabilityError,
    )

    public var isVerificationMode: Boolean = false
        set(value) {
            field = value
            chatStore.isVerificationMode = value
        }

    public val connectionState: StateFlow<ConnectionState>
        get() = connectionStore.state

    public val syncState: StateFlow<ConversationSyncState>
        get() = conversationSyncStore.state

    public val chatState: StateFlow<CascadeChatState>
        get() = chatStore.state

    public fun dismissCapabilityError() {
        _capabilityErrorBanner.value = null
        workspaceStore.clearCapabilityError()
        reviewStore.clearCapabilityError()
        orchestrationStore.clearCapabilityError()
        settingsStore.clearCapabilityError()
    }

    private fun reportCapabilityError(message: String) {
        _capabilityErrorBanner.value = message
    }

    @Throws(Throwable::class)
    public suspend fun hydrateOfflineCache() {
        conversationSyncStore.hydrateFromCache()
    }

    @Throws(Throwable::class)
    public suspend fun connectDirectLan(
        endpointUrlString: String,
        csrfToken: String,
        certSha256: String? = null,
        hostName: String = "MacBook Pro",
        isRestoringSavedSession: Boolean = false,
        startSummaryStream: Boolean = true,
    ): BackendHandshakeResult {
        val handshake = connectionStore.connectDirectLan(
            endpointUrlString = endpointUrlString,
            csrfToken = csrfToken,
            certSha256 = certSha256,
            hostName = hostName,
            isRestoringSavedSession = isRestoringSavedSession,
        )
        onHandshakeSucceeded(handshake, startSummaryStream)
        return handshake
    }

    @Throws(Throwable::class)
    public suspend fun connectCloudRelay(
        relayUrlString: String,
        sessionCookie: String,
        authUser: String? = null,
        resolvedInstanceUuid: String? = null,
        relayApiKey: String? = null,
        hostName: String = "Antigravity Desktop",
        isRestoringSavedSession: Boolean = false,
        strictTargetMatch: Boolean = false,
        startSummaryStream: Boolean = true,
    ): BackendHandshakeResult {
        val handshake = connectionStore.connectCloudRelay(
            relayUrlString = relayUrlString,
            sessionCookie = sessionCookie,
            authUser = authUser,
            resolvedInstanceUuid = resolvedInstanceUuid,
            relayApiKey = relayApiKey,
            hostName = hostName,
            isRestoringSavedSession = isRestoringSavedSession,
            strictTargetMatch = strictTargetMatch,
        )
        onHandshakeSucceeded(handshake, startSummaryStream)
        return handshake
    }

    @Throws(Throwable::class)
    public suspend fun connectWithPairingUri(
        rawUri: String,
        fallbackCookie: String = "",
        startSummaryStream: Boolean = true,
    ): BackendHandshakeResult {
        val handshake = connectionStore.connectWithPairingUri(rawUri, fallbackCookie)
        onHandshakeSucceeded(handshake, startSummaryStream)
        return handshake
    }

    @Throws(Throwable::class)
    public suspend fun restoreSavedSession(startSummaryStream: Boolean = true): BackendHandshakeResult? {
        conversationSyncStore.hydrateFromCache()
        val handshake = connectionStore.restoreSavedSession() ?: return null
        onHandshakeSucceeded(handshake, startSummaryStream)
        return handshake
    }

    public fun cancelPendingConnectionAttempt() {
        connectionStore.cancelPendingConnectionAttempt()
    }

    public fun lastHandshakeDiagnostic(): String =
        connectionStore.currentHandshakeDiagnostic()

    /**
     * Creates an optimistic local conversation draft without prematurely firing `startConversation`
     * while the initial backend handshake is still connecting. The first `sendMessage(..., isOptimisticDraft = true)`
     * call lazily promotes the draft to a real backend cascade ID once connected.
     */
    public fun createLocalDraftConversation(
        workspaceUri: String = "",
        projectSlug: String = "",
        title: String = "New Conversation",
    ): String {
        val draftId = "cascade-new-${dev.antigravity.shared.protocol.currentTimeMillis()}"
        val activeHost = connectionStore.state.value.activeHost
        val resolvedProject = projectSlug.ifBlank {
            conversationSyncStore.state.value.projects.firstOrNull()?.id ?: "workspace"
        }
        val resolvedWorkspace = workspaceUri.ifBlank {
            conversationSyncStore.state.value.projects.firstOrNull { it.id == resolvedProject }?.workspaceUri.orEmpty()
        }
        conversationSyncStore.upsertSummary(
            CascadeSummary(
                cascadeId = draftId,
                title = title,
                projectSlug = resolvedProject,
                workspaceUri = resolvedWorkspace,
                status = CortexStepStatus.UNSPECIFIED,
                stepCount = 0,
                currentStepIndex = 0,
                totalSteps = 0,
                statusSubtitle = "New conversation",
                originInstanceUuid = activeHost?.instanceId,
                originHostName = activeHost?.hostname,
                updatedAtEpochMs = dev.antigravity.shared.protocol.currentTimeMillis(),
            ),
        )
        chatStore.setActiveCascade(draftId)
        return draftId
    }

    @Throws(Throwable::class)
    public suspend fun probeHostReachability(allowCrossHostFallback: Boolean = true): HostReachabilityProbeResult =
        connectionStore.probeHostReachability(allowCrossHostFallback = allowCrossHostFallback)

    @Throws(Throwable::class)
    public suspend fun refreshWorkspacesAndSummaries(
        hostScope: AgentsHostFilterScope? = null,
        skipRelayListRefresh: Boolean = false,
    ): FederatedWorkspaceSyncResult {
        val client = connectionStore.activeClient()
            ?: throw AntigravityRpcError.HttpError(503, "No active backend connection")
        val host = connectionStore.state.value.activeHost
            ?: throw AntigravityRpcError.HttpError(503, "No active paired host")
        val effectiveScope = hostScope ?: connectionStore.state.value.selectedHostScope
        return conversationSyncStore.refreshWorkspacesAndSummaries(
            client = client,
            host = host,
            hostScope = effectiveScope,
            skipRelayListRefresh = skipRelayListRefresh,
        )
    }

    @Throws(Throwable::class)
    public suspend fun syncSteps(
        cascadeId: String,
        knownStepCount: Int = 0,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ): List<CascadeStep> {
        val client = connectionStore.activeClient()
            ?: return chatStore.loadCachedSteps(cascadeId)
        chatStore.setActiveCascade(cascadeId)
        return chatStore.syncSteps(
            client = client,
            cascadeId = cascadeId,
            knownStepCount = knownStepCount,
            isCloud = isCloud,
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    @Throws(Throwable::class)
    public suspend fun startConversation(
        workspaceUri: String,
        initialPrompt: String = "",
        modelId: String = "MODEL_PLACEHOLDER_M37",
        cloudProjectId: String? = null,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ): String {
        val client = connectionStore.activeClient()
            ?: throw AntigravityRpcError.HttpError(503, "No active backend connection")
        return chatStore.startConversation(
            client = client,
            workspaceUri = workspaceUri,
            initialPrompt = initialPrompt,
            modelId = modelId,
            cloudProjectId = cloudProjectId,
            isCloud = isCloud,
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    @Throws(Throwable::class)
    public suspend fun sendMessage(
        cascadeId: String,
        message: String,
        workspaceUri: String = "",
        attachments: List<ComposerAttachmentChip> = emptyList(),
        modelId: String = "MODEL_PLACEHOLDER_M37",
        effort: ThinkingEffortLevel = ThinkingEffortLevel.HIGH,
        mode: CascadeExecutionMode = CascadeExecutionMode.PLANNING,
        agentPersona: String = "Default",
        isCloud: Boolean = false,
        cloudProjectId: String? = null,
        permissionPreset: AgentPermissionPreset? = null,
        instanceUuidOverride: String? = null,
        isOptimisticDraft: Boolean = false,
    ): SendMessageOutcome {
        val client = connectionStore.activeClient()
        val isReachable = connectionStore.state.value.isDeviceNetworkReachable
        val outcome = chatStore.sendMessage(
            client = client,
            cascadeId = cascadeId,
            message = message,
            workspaceUri = workspaceUri,
            attachments = attachments,
            modelId = modelId,
            effort = effort,
            mode = mode,
            agentPersona = agentPersona,
            isCloud = isCloud,
            cloudProjectId = cloudProjectId,
            permissionPreset = permissionPreset,
            instanceUuidOverride = instanceUuidOverride,
            isDeviceNetworkReachable = isReachable,
            isOptimisticDraft = isOptimisticDraft,
            isVerificationMode = isVerificationMode,
        )
        if (outcome.resolvedCascadeId != cascadeId) {
            conversationSyncStore.replaceCascadeId(cascadeId, outcome.resolvedCascadeId)
        }
        return outcome
    }

    @Throws(Throwable::class)
    public suspend fun resolveWaitingInteraction(
        cascadeId: String,
        stepIndex: Int,
        decision: InteractionDecision,
        workspaceUri: String? = null,
        instanceUuidOverride: String? = null,
        stepOverride: CascadeStep? = null,
    ): CascadeUserInteractionPayload {
        val client = connectionStore.activeClient()
        return chatStore.resolveWaitingInteraction(
            client = client,
            cascadeId = cascadeId,
            stepIndex = stepIndex,
            decision = decision,
            workspaceUri = workspaceUri,
            instanceUuidOverride = instanceUuidOverride,
            stepOverride = stepOverride,
        )
    }

    @Throws(Throwable::class)
    public suspend fun cancelActiveTurn(
        cascadeId: String,
        instanceUuidOverride: String? = null,
    ) {
        chatStore.cancelActiveTurn(
            client = connectionStore.activeClient(),
            cascadeId = cascadeId,
            instanceUuidOverride = instanceUuidOverride,
        )
    }

    @Throws(Throwable::class)
    public suspend fun replayPendingOutbox(
        modelId: String = "MODEL_PLACEHOLDER_M37",
        effort: ThinkingEffortLevel = ThinkingEffortLevel.HIGH,
        mode: CascadeExecutionMode = CascadeExecutionMode.PLANNING,
    ): OutboxReplayResult {
        val client = connectionStore.activeClient() ?: return OutboxReplayResult(0)
        return OutboxReplayResult(chatStore.replayPendingOutbox(client, modelId, effort, mode))
    }

    @Throws(Throwable::class)
    public suspend fun switchToRelayInstance(instance: RelayInstanceInfo) {
        connectionStore.switchToRelayInstance(instance)
    }

    public fun selectHostScope(scope: AgentsHostFilterScope) {
        connectionStore.selectHostScope(scope)
    }

    public fun markAllConversationsRead() {
        conversationSyncStore.markAllRead()
    }

    public fun toggleConversationPinned(cascadeId: String) {
        val existing = conversationSyncStore.state.value.summaries.firstOrNull { it.cascadeId == cascadeId }
        conversationSyncStore.togglePinned(cascadeId)
        if (!isVerificationMode && existing != null && connectionStore.state.value.isConnected) {
            val nextPinned = !existing.isPinned
            scope.launch {
                try {
                    val client = connectionStore.activeClient() ?: return@launch
                    performLiveCapabilityWrite(
                        client = client,
                        capability = HostCapability.CONVERSATION_ANNOTATIONS,
                        onUnsupported = ::reportCapabilityError,
                        rollback = { conversationSyncStore.togglePinned(cascadeId) },
                    ) { rpc ->
                        rpc.pinCascade(
                            cascadeId = cascadeId,
                            isPinned = nextPinned,
                            instanceUuidOverride = existing.originInstanceUuid,
                        )
                    }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    reportCapabilityError(e.message ?: "Failed to update pin state")
                }
            }
        }
    }

    public fun toggleConversationUnread(cascadeId: String) {
        conversationSyncStore.toggleUnread(cascadeId)
    }

    public fun archiveConversation(cascadeId: String) {
        val existing = conversationSyncStore.state.value.summaries.firstOrNull { it.cascadeId == cascadeId }
        conversationSyncStore.archiveConversation(cascadeId)
        if (!isVerificationMode && existing != null && connectionStore.state.value.isConnected) {
            scope.launch {
                try {
                    val client = connectionStore.activeClient() ?: return@launch
                    performLiveCapabilityWrite(
                        client = client,
                        capability = HostCapability.CONVERSATION_ANNOTATIONS,
                        onUnsupported = ::reportCapabilityError,
                        rollback = { conversationSyncStore.upsertSummary(existing) },
                    ) { rpc ->
                        rpc.archiveCascade(
                            cascadeId = cascadeId,
                            isArchived = true,
                            instanceUuidOverride = existing.originInstanceUuid,
                        )
                    }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    reportCapabilityError(e.message ?: "Failed to archive conversation")
                }
            }
        }
    }

    public fun deleteConversation(cascadeId: String) {
        val existing = conversationSyncStore.state.value.summaries.firstOrNull { it.cascadeId == cascadeId }
        conversationSyncStore.deleteConversation(cascadeId)
        if (!isVerificationMode && existing != null && connectionStore.state.value.isConnected) {
            scope.launch {
                try {
                    val client = connectionStore.activeClient() ?: return@launch
                    performLiveCapabilityWrite(
                        client = client,
                        capability = HostCapability.CONVERSATION_ANNOTATIONS,
                        onUnsupported = ::reportCapabilityError,
                        rollback = { conversationSyncStore.upsertSummary(existing) },
                    ) { rpc ->
                        rpc.deleteCascade(
                            cascadeId = cascadeId,
                            instanceUuidOverride = existing.originInstanceUuid,
                        )
                    }
                } catch (e: kotlinx.coroutines.CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    reportCapabilityError(e.message ?: "Failed to delete conversation")
                }
            }
        }
    }

    public fun liveProgressSnapshot(): LiveProgressSnapshot? {
        val summaries = conversationSyncStore.state.value.summaries
        if (summaries.isEmpty()) return null

        val activeId = chatStore.state.value.activeCascadeId
        val target = summaries.firstOrNull { it.cascadeId == activeId && !it.isArchived }
            ?: summaries.firstOrNull { !it.isArchived && (it.status == CortexStepStatus.WAITING || it.status == CortexStepStatus.IN_PROGRESS) }
            ?: summaries.firstOrNull { !it.isArchived }
            ?: summaries.first()

        val steps = chatStore.state.value.stepsByCascadeId[target.cascadeId].orEmpty()
        val waitingStep = steps.lastOrNull { it.status == CortexStepStatus.WAITING }
        val taskBoundary = steps.lastOrNull { it.taskBoundary != null }?.taskBoundary

        val phase = when {
            waitingStep != null || target.status == CortexStepStatus.WAITING || target.status == CortexStepStatus.BLOCKED ->
                LiveProgressPhase.WAITING_APPROVAL
            target.status == CortexStepStatus.DONE ->
                LiveProgressPhase.COMPLETED
            else ->
                LiveProgressPhase.RUNNING
        }

        val pendingCommand = waitingStep?.runCommand?.proposedCommandLine
            ?: waitingStep?.runCommand?.commandLine
            ?: waitingStep?.requestedInteraction?.runCommand?.proposedCommandLine
            ?: target.pendingInteractionTitle

        val totalSteps = (taskBoundary?.totalCount ?: target.totalSteps).coerceAtLeast(1)
        val currentStep = (taskBoundary?.completedCount ?: target.currentStepIndex).coerceIn(0, totalSteps)
        val elapsedSeconds = parseElapsedSeconds(taskBoundary?.elapsedLabel)

        val multiAgentItems = summaries
            .filter { !it.isArchived }
            .take(4)
            .map { summary ->
                val itemPhase = when (summary.status) {
                    CortexStepStatus.WAITING, CortexStepStatus.BLOCKED -> LiveProgressPhase.WAITING_APPROVAL
                    CortexStepStatus.DONE -> LiveProgressPhase.COMPLETED
                    else -> LiveProgressPhase.RUNNING
                }
                val trailing = when (itemPhase) {
                    LiveProgressPhase.WAITING_APPROVAL -> "Approve"
                    LiveProgressPhase.COMPLETED -> "+${summary.totalAdditions} -${summary.totalDeletions}"
                    LiveProgressPhase.RUNNING -> "${summary.currentStepIndex}/${summary.totalSteps.coerceAtLeast(1)}"
                }
                LiveProgressAgentSummary(
                    id = summary.cascadeId,
                    title = summary.title,
                    subtitle = "${summary.projectSlug} · ${summary.originHostName ?: "MacBook Pro"}",
                    phase = itemPhase,
                    trailingLabel = trailing,
                )
            }

        return LiveProgressSnapshot(
            cascadeId = target.cascadeId,
            cascadeTitle = target.title,
            hostName = target.originHostName ?: connectionStore.state.value.activeHost?.hostname ?: "MacBook Pro",
            workspaceName = target.projectSlug.ifBlank { "workspace" },
            branchName = target.branchName.ifBlank { "main" },
            phase = phase,
            currentStepIndex = currentStep,
            totalSteps = totalSteps,
            activeToolAction = target.statusSubtitle.ifBlank { taskBoundary?.taskStatus ?: target.status.displayBadgeText },
            pendingApprovalCommand = pendingCommand,
            elapsedSeconds = elapsedSeconds,
            additions = target.totalAdditions,
            deletions = target.totalDeletions,
            multiAgentItems = multiAgentItems,
        )
    }

    public fun filteredSummaries(
        quickFilter: AgentsQuickFilter = AgentsQuickFilter.ALL,
        searchQuery: String = "",
        includeArchived: Boolean = false,
    ): List<CascadeSummary> = conversationSyncStore.filteredSummaries(
        hostScope = connectionStore.state.value.selectedHostScope,
        quickFilter = quickFilter,
        searchQuery = searchQuery,
        includeArchived = includeArchived,
    )

    public fun parseMarkdown(markdown: String): List<MarkdownBlock> =
        chatStore.parseMarkdown(markdown)

    public fun onBackground() {
        conversationSyncStore.stopSummarySubscriptionStream()
        connectionStore.onBackground()
    }

    @Throws(Throwable::class)
    public suspend fun onForeground() {
        connectionStore.onForeground()
        val client = connectionStore.activeClient()
        val host = connectionStore.state.value.activeHost
        if (client != null && host != null && connectionStore.state.value.isConnected) {
            conversationSyncStore.startSummarySubscriptionStream(client, host)
            replayPendingOutbox()
        }
    }

    @Throws(Throwable::class)
    public suspend fun disconnectAndClearCredentials() {
        conversationSyncStore.clear()
        chatStore.clear()
        connectionStore.disconnectAndClearCredentials()
    }

    @Throws(Throwable::class)
    public suspend fun close() {
        conversationSyncStore.stopSummarySubscriptionStream()
        connectionStore.close()
        scope.cancel()
    }

    private suspend fun onHandshakeSucceeded(
        handshake: BackendHandshakeResult,
        startSummaryStream: Boolean,
    ) {
        val host = connectionStore.state.value.activeHost ?: return
        conversationSyncStore.applyHandshake(host, handshake)
        val client = connectionStore.activeClient()
        if (client != null && handshake.isSelectedHostOnline) {
            if (startSummaryStream) {
                conversationSyncStore.startSummarySubscriptionStream(client, host)
            }
            if (host.channel == RemoteConnectionChannel.CLOUD_RELAY &&
                (handshake.summaries.isEmpty() || handshake.workspaces.isEmpty())
            ) {
                val activeScope = connectionStore.state.value.selectedHostScope
                scope.launch {
                    try {
                        conversationSyncStore.refreshWorkspacesAndSummaries(
                            client = client,
                            host = host,
                            hostScope = activeScope,
                            skipRelayListRefresh = true,
                        )
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Throwable) {
                        // Best-effort deferred hydration after fast handshake; UI stays connected and pull-to-refresh can retry.
                    }
                }
            }
            scope.launch {
                try {
                    chatStore.replayPendingOutbox(client)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    // Best-effort outbox replay after reconnect; never crash process.
                }
            }
        }
    }

    private fun parseElapsedSeconds(rawLabel: String?): Int {
        if (rawLabel.isNullOrBlank()) return 0
        var total = 0
        for (token in rawLabel.trim().split(' ')) {
            when {
                token.endsWith("h") -> total += (token.dropLast(1).toIntOrNull() ?: 0) * 3600
                token.endsWith("m") -> total += (token.dropLast(1).toIntOrNull() ?: 0) * 60
                token.endsWith("s") -> total += token.dropLast(1).toIntOrNull() ?: 0
            }
        }
        return total
    }

    public companion object {
        public fun createEsddVerificationCoordinator(): AntigravityCoreCoordinator =
            EsddVerificationFixtures.createVerificationCoordinator()
    }
}
