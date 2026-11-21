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
import dev.antigravity.shared.model.InteractionDecision
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
import dev.antigravity.shared.protocol.HostReachabilityProbeResult
import dev.antigravity.shared.protocol.RelayInstanceInfo
import dev.antigravity.shared.protocol.TlsEngineConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.StateFlow

/**
 * Unified KMP Core Coordinator exported to both iOS (via SKIE `AsyncSequence` + `async throws`)
 * and Android (via Jetpack Compose `collectAsStateWithLifecycle`).
 *
 * Composes:
 * - [ConnectionDomainStore]: Direct LAN / Cloud Relay / Pairing URI / Keychain / Reachability
 * - [ConversationSyncStore]: Federated sync + per-host sharded offline cache + Jetbox stream
 * - [CascadeChatDomainStore]: `<600` JSON + `>=600` Binary Protobuf steps + Durable Outbox + PC interactions
 */
public class AntigravityCoreCoordinator(
    secretStore: SecretStore = InMemorySecretStore(),
    networkMonitor: NetworkReachabilityMonitoring = NoopNetworkReachabilityMonitor(),
    powerStateProvider: PowerStateProviding = StaticPowerStateProvider(),
    preferencesStore: KeyValuePreferencesStore = InMemoryPreferencesStore(),
    projectionStorage: ProjectionStoragePort = InMemoryProjectionStorage(),
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
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
    )

    public val connectionState: StateFlow<ConnectionState>
        get() = connectionStore.state

    public val syncState: StateFlow<ConversationSyncState>
        get() = conversationSyncStore.state

    public val chatState: StateFlow<CascadeChatState>
        get() = chatStore.state

    public suspend fun hydrateOfflineCache() {
        conversationSyncStore.hydrateFromCache()
    }

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

    public suspend fun connectWithPairingUri(
        rawUri: String,
        fallbackCookie: String = "",
        startSummaryStream: Boolean = true,
    ): BackendHandshakeResult {
        val handshake = connectionStore.connectWithPairingUri(rawUri, fallbackCookie)
        onHandshakeSucceeded(handshake, startSummaryStream)
        return handshake
    }

    public suspend fun restoreSavedSession(startSummaryStream: Boolean = true): BackendHandshakeResult? {
        conversationSyncStore.hydrateFromCache()
        val handshake = connectionStore.restoreSavedSession() ?: return null
        onHandshakeSucceeded(handshake, startSummaryStream)
        return handshake
    }

    public suspend fun probeHostReachability(allowCrossHostFallback: Boolean = true): HostReachabilityProbeResult =
        connectionStore.probeHostReachability(allowCrossHostFallback = allowCrossHostFallback)

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
        )
        if (outcome.resolvedCascadeId != cascadeId) {
            conversationSyncStore.replaceCascadeId(cascadeId, outcome.resolvedCascadeId)
        }
        return outcome
    }

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

    public suspend fun replayPendingOutbox(
        modelId: String = "MODEL_PLACEHOLDER_M37",
        effort: ThinkingEffortLevel = ThinkingEffortLevel.HIGH,
        mode: CascadeExecutionMode = CascadeExecutionMode.PLANNING,
    ): OutboxReplayResult {
        val client = connectionStore.activeClient() ?: return OutboxReplayResult(0)
        return OutboxReplayResult(chatStore.replayPendingOutbox(client, modelId, effort, mode))
    }

    public suspend fun switchToRelayInstance(instance: RelayInstanceInfo) {
        connectionStore.switchToRelayInstance(instance)
    }

    public fun selectHostScope(scope: AgentsHostFilterScope) {
        connectionStore.selectHostScope(scope)
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

    public suspend fun onForeground() {
        connectionStore.onForeground()
        val client = connectionStore.activeClient()
        val host = connectionStore.state.value.activeHost
        if (client != null && host != null && connectionStore.state.value.isConnected) {
            conversationSyncStore.startSummarySubscriptionStream(client, host)
            replayPendingOutbox()
        }
    }

    public suspend fun disconnectAndClearCredentials() {
        conversationSyncStore.clear()
        chatStore.clear()
        connectionStore.disconnectAndClearCredentials()
    }

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
            chatStore.replayPendingOutbox(client)
        }
    }
}
