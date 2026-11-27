package dev.antigravity.shared.domain

import dev.antigravity.shared.markdown.MarkdownBlock
import dev.antigravity.shared.model.AgentPermissionPreset
import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.AgentsQuickFilter
import dev.antigravity.shared.model.AntigravityCloudDetector
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.CascadeSummaryTitleResolver
import dev.antigravity.shared.model.CascadeUserInteractionPayload
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.LiveModelCatalogResult
import dev.antigravity.shared.model.LiveProgressAgentSummary
import dev.antigravity.shared.model.LiveProgressPhase
import dev.antigravity.shared.model.LiveProgressSnapshot
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
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
import dev.antigravity.shared.protocol.ProtocolCompatibilityEngine
import dev.antigravity.shared.protocol.RelayInstanceInfo
import dev.antigravity.shared.protocol.RelayInstanceStatus
import dev.antigravity.shared.protocol.TlsEngineConfig
import dev.antigravity.shared.protocol.currentTimeMillis
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
    private val powerStateProvider: PowerStateProviding = StaticPowerStateProvider(),
    preferencesStore: KeyValuePreferencesStore = InMemoryPreferencesStore(),
    projectionStorage: ProjectionStoragePort = InMemoryProjectionStorage(),
    private val scope: CoroutineScope = CoroutineScope(
        SupervisorJob() + Dispatchers.Default + CoroutineExceptionHandler { _, _ ->
            // Prevent uncaught background coroutine exceptions from aborting Kotlin/Native via propagateExceptionFinalResort.
        }
    ),
    private val autoPreloadConversations: Boolean = true,
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
    private var hostSwitchJob: Job? = null
    private var hostSwitchGeneration: Long = 0L

    private val preloadMutex = Mutex()
    private val preloadQueue = ArrayDeque<String>()
    private val preloadAttemptedAtMs = mutableMapOf<String, Long>()
    private var preloadWorkerJob: Job? = null
    private val activeForegroundSyncCount = MutableStateFlow(0)

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
        preferencesStore = preferencesStore,
        onCapabilityError = ::reportCapabilityError,
    )

    public val reviewStore: ReviewAndVcsStore = ReviewAndVcsStore(
        onCapabilityError = ::reportCapabilityError,
    )

    public val orchestrationStore: OrchestrationAndSideChannelStore = OrchestrationAndSideChannelStore(
        onCapabilityError = ::reportCapabilityError,
    )

    public val settingsStore: SettingsAndCustomizationStore = SettingsAndCustomizationStore(
        preferencesStore = preferencesStore,
        onCapabilityError = ::reportCapabilityError,
    )

    public var isVerificationMode: Boolean = false
        set(value) {
            field = value
            chatStore.isVerificationMode = value
            settingsStore.persistPreferences = !value
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
        val summaries = conversationSyncStore.state.value.summaries
        if (summaries.isEmpty()) return
        val idsToWarm = buildList {
            for (s in summaries) {
                if (s.needsTitleHydration && s.cascadeId !in this) add(s.cascadeId)
                if (size >= 24) break
            }
            for (s in summaries) {
                if (!s.isArchived && s.cascadeId !in this) add(s.cascadeId)
                if (size >= 24) break
            }
        }
        val warmed = chatStore.warmCachedSteps(idsToWarm)
        if (warmed.isNotEmpty()) {
            conversationSyncStore.markStepsCached(warmed.keys)
            val host = connectionStore.state.value.activeHost
            for ((cid, steps) in warmed) {
                val summary = conversationSyncStore.state.value.summaries.firstOrNull { it.cascadeId == cid }
                if (summary != null && summary.needsTitleHydration) {
                    conversationSyncStore.applyHydratedStepsMetadata(
                        host = host,
                        cascadeId = cid,
                        steps = steps,
                        persist = host != null,
                    )
                }
            }
        }
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
        isCloud: Boolean = false,
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
                isCloud = isCloud,
                originInstanceUuid = if (isCloud) null else activeHost?.instanceId,
                originHostName = if (isCloud) "Antigravity" else activeHost?.hostname,
                updatedAtEpochMs = dev.antigravity.shared.protocol.currentTimeMillis(),
                hasResolvedTitle = true,
            ),
        )
        chatStore.setActiveCascade(draftId)
        return draftId
    }

    /**
     * Determines accurately whether a conversation targets Antigravity Cloud vs a paired local Mac/PC,
     * preventing same-name Cloud projects from hijacking concrete local `file://` workspaces.
     */
    public fun isSummaryCloudRuntime(cascadeId: String, summary: CascadeSummary?): Boolean {
        if (summary?.isCloud == true) return true
        val uri = summary?.workspaceUri.orEmpty()
        if (AntigravityCloudDetector.isCloudWorkspaceUri(uri, cascadeId = cascadeId)) {
            return true
        }
        if (uri.startsWith("file://") && !AntigravityCloudDetector.isPlaygroundScratchUri(uri)) {
            return false
        }
        if (summary == null) return false
        val allProjects = (workspaceStore.state.value.projects + conversationSyncStore.state.value.projects)
            .distinctBy { it.id }
        val cpid = summary.cloudProjectId
        if (!cpid.isNullOrBlank()) {
            allProjects.firstOrNull { it.cloudProjectId == cpid || it.id == cpid }?.let {
                return it.runtime == ProjectRuntimeTarget.CLOUD
            }
        }
        if (uri.isNotBlank()) {
            allProjects.firstOrNull { it.workspaceUri.equals(uri, ignoreCase = true) }?.let {
                return it.runtime == ProjectRuntimeTarget.CLOUD
            }
        }
        if (summary.projectSlug.isNotBlank()) {
            val slugMatches = allProjects.filter {
                it.id == summary.projectSlug || it.name.equals(summary.projectSlug, ignoreCase = true)
            }
            if (slugMatches.size == 1) {
                return slugMatches[0].runtime == ProjectRuntimeTarget.CLOUD
            }
            return false
        }
        return false
    }

    @Throws(Throwable::class)
    public suspend fun probeHostReachability(
        allowCrossHostFallback: Boolean = true,
        verifyEndToEnd: Boolean = false,
    ): HostReachabilityProbeResult =
        connectionStore.probeHostReachability(
            allowCrossHostFallback = allowCrossHostFallback,
            verifyEndToEnd = verifyEndToEnd,
        )

    @Throws(Throwable::class)
    public suspend fun refreshWorkspacesAndSummaries(
        hostScope: AgentsHostFilterScope? = null,
        skipRelayListRefresh: Boolean = false,
    ): FederatedWorkspaceSyncResult {
        val client = connectionStore.activeClient()
            ?: throw AntigravityRpcError.HttpError(503, "No active backend connection")
        val connState = connectionStore.state.value
        val activeHost = connState.activeHost
            ?: throw AntigravityRpcError.HttpError(503, "No active paired host")
        val effectiveScope = hostScope ?: connState.selectedHostScope
        val effectiveHost = when (effectiveScope) {
            is AgentsHostFilterScope.LocalHost -> {
                connState.knownHosts.firstOrNull {
                    it.instanceId == effectiveScope.id || it.hostname == effectiveScope.name
                } ?: activeHost.copy(
                    instanceId = effectiveScope.id,
                    hostname = effectiveScope.name.ifBlank { activeHost.hostname },
                )
            }
            else -> activeHost
        }
        val result = try {
            conversationSyncStore.refreshWorkspacesAndSummaries(
                client = client,
                host = effectiveHost,
                hostScope = effectiveScope,
                skipRelayListRefresh = skipRelayListRefresh,
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (ProtocolCompatibilityEngine.isInstanceNotRegisteredError(e)) {
                connectionStore.markInstanceOffline(
                    instanceUuid = effectiveHost.instanceId,
                    errorMessage = ProtocolCompatibilityEngine.formatUserFacingRpcError(e),
                )
            }
            throw e
        }
        if (effectiveHost.channel == RemoteConnectionChannel.CLOUD_RELAY &&
            effectiveScope is AgentsHostFilterScope.LocalHost &&
            result.succeededInstanceUuids.isEmpty()
        ) {
            connectionStore.markInstanceOffline(
                instanceUuid = effectiveHost.instanceId,
                errorMessage = "${effectiveHost.hostname} is currently offline.",
            )
        }
        reconcileSelectedProjectForScope(effectiveScope)
        conversationSyncStore.resetSettledEmptyTitles()
        scheduleConversationPreload()
        if (!isVerificationMode && connectionStore.state.value.userDisplayName == null) {
            scope.launch {
                try {
                    refreshUserProfile()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    // Best-effort profile refresh; greeting falls back cleanly without failing sync.
                }
            }
        }
        return result
    }

    @Throws(Throwable::class)
    public suspend fun syncSteps(
        cascadeId: String,
        knownStepCount: Int = 0,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ): List<CascadeStep> = syncStepsInternal(
        cascadeId = cascadeId,
        knownStepCount = knownStepCount,
        isCloud = isCloud,
        instanceUuidOverride = instanceUuidOverride,
        forceRefresh = false,
    )

    @Throws(Throwable::class)
    public suspend fun forceSyncSteps(
        cascadeId: String,
        knownStepCount: Int = 0,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
    ): List<CascadeStep> = syncStepsInternal(
        cascadeId = cascadeId,
        knownStepCount = knownStepCount,
        isCloud = isCloud,
        instanceUuidOverride = instanceUuidOverride,
        forceRefresh = true,
    )

    private suspend fun syncStepsInternal(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Boolean,
        instanceUuidOverride: String?,
        forceRefresh: Boolean,
    ): List<CascadeStep> {
        val client = connectionStore.activeClient()
        if (client == null) {
            val cached = chatStore.loadCachedSteps(cascadeId)
            if (cached.isNotEmpty()) {
                conversationSyncStore.applyHydratedStepsMetadata(
                    host = connectionStore.state.value.activeHost,
                    cascadeId = cascadeId,
                    steps = cached,
                    persist = false,
                )
            }
            return cached
        }
        chatStore.setActiveCascade(cascadeId)
        val summary = conversationSyncStore.state.value.summaries.firstOrNull { it.cascadeId == cascadeId }
        val effectiveKnownCount = maxOf(knownStepCount, summary?.stepCount ?: 0)
        activeForegroundSyncCount.update { it + 1 }
        return try {
            val steps = chatStore.syncSteps(
                client = client,
                cascadeId = cascadeId,
                knownStepCount = effectiveKnownCount,
                isCloud = isCloud,
                instanceUuidOverride = instanceUuidOverride,
                summaryStatus = summary?.status,
                summaryUpdatedAtEpochMs = summary?.updatedAtEpochMs ?: 0L,
                forceRefresh = forceRefresh,
            )
            conversationSyncStore.applyHydratedStepsMetadata(
                host = connectionStore.state.value.activeHost,
                cascadeId = cascadeId,
                steps = steps,
                persist = true,
            )
            steps
        } finally {
            activeForegroundSyncCount.update { (it - 1).coerceAtLeast(0) }
        }
    }

    /**
     * Background-safe step preloader exported to both Android and iOS (SKIE).
     * Never mutates `activeCascadeId`, `isLoadingSteps`, or `stepLoadErrorText`.
     */
    @Throws(Throwable::class)
    public suspend fun preloadSteps(
        cascadeId: String,
        knownStepCount: Int = 0,
        isCloud: Boolean = false,
        instanceUuidOverride: String? = null,
        requireRemoteRefresh: Boolean = false,
    ): List<CascadeStep> {
        val client = connectionStore.activeClient()
            ?: return chatStore.loadCachedSteps(cascadeId)
        val steps = chatStore.preloadSteps(
            client = client,
            cascadeId = cascadeId,
            knownStepCount = knownStepCount,
            isCloud = isCloud,
            instanceUuidOverride = instanceUuidOverride,
            requireRemoteRefresh = requireRemoteRefresh,
        )
        conversationSyncStore.applyHydratedStepsMetadata(
            host = connectionStore.state.value.activeHost,
            cascadeId = cascadeId,
            steps = steps,
            persist = autoPreloadConversations,
        )
        return steps
    }

    /**
     * Returns `true` when [summary] represents a server conversation whose title has not finished
     * hydrating yet (and should render a loading indicator instead of `"New Conversation"`).
     */
    public fun isSummaryTitleLoading(summary: CascadeSummary): Boolean {
        val conn = connectionStore.state.value
        if (isVerificationMode && !conn.hasPairedBackend && !conn.isConnected) {
            return false
        }
        if (summary.cascadeId.startsWith("cascade-new-")) {
            return false
        }
        if (!summary.needsTitleHydration) return false
        val sync = conversationSyncStore.state.value
        if (summary.cascadeId in sync.hydratingCascadeIds) return true
        if (summary.cascadeId in sync.settledEmptyTitleCascadeIds) return false
        if (!conn.isDeviceNetworkReachable) return false
        if (!conn.isConnected && conn.isConnecting) return true
        return isSummaryHostReachable(summary, conn) && (conn.isConnected || conn.hasPairedBackend)
    }

    /**
     * Returns the user-facing display title for [summary], replacing placeholder `"New Conversation"`
     * on unloaded server conversations with `"Loading..."` or `"Untitled conversation"`.
     */
    public fun displayTitleForSummary(summary: CascadeSummary): String {
        if (summary.cascadeId.startsWith("cascade-new-")) {
            return summary.title.ifBlank { CascadeSummaryTitleResolver.PLACEHOLDER_TITLE }
        }
        if (summary.needsTitleHydration) {
            return if (isSummaryTitleLoading(summary)) {
                "Loading..."
            } else {
                CascadeSummaryTitleResolver.UNTITLED_FALLBACK
            }
        }
        return summary.title
    }

    /**
     * Enqueues a visible conversation at the front of the background preload queue so scrolling
     * through long project lists hydrates titles and caches steps immediately.
     */
    public fun prioritizeConversationPreload(cascadeId: String) {
        if (!autoPreloadConversations || isVerificationMode || cascadeId.isBlank()) return
        if (cascadeId.startsWith("cascade-new-")) return
        val summary = conversationSyncStore.state.value.summaries.firstOrNull { it.cascadeId == cascadeId } ?: return
        val hasCachedSteps = !chatStore.state.value.stepsByCascadeId[cascadeId].isNullOrEmpty()
        if (!summary.needsTitleHydration && hasCachedSteps) return
        scheduleConversationPreload(priorityCascadeIds = listOf(cascadeId))
    }

    /**
     * Schedules bounded-concurrency background preloading of unhydrated conversation titles and
     * top recent conversations' steps so both sidebar titles and conversation entry load fast.
     */
    public fun scheduleConversationPreload(priorityCascadeIds: List<String> = emptyList()) {
        if (!autoPreloadConversations || isVerificationMode) return
        val conn = connectionStore.state.value
        if (!conn.isConnected || conn.isNetworkingSuspended || !conn.isDeviceNetworkReachable) return

        val collapsedIds = workspaceStore.state.value.collapsedProjectIds
        val sync = conversationSyncStore.state.value
        val existingStepsById = chatStore.state.value.stepsByCascadeId
        val candidates = buildList {
            val seen = mutableSetOf<String>()
            fun addIfEligible(id: String) {
                if (id.isNotBlank() && !id.startsWith("cascade-new-") && seen.add(id)) {
                    add(id)
                }
            }
            for (cid in priorityCascadeIds) addIfEligible(cid)
            // 1. Prioritize recent conversations in expanded projects so tapping them opens on Frame 0
            val recentToWarm = sync.summaries.filter { s ->
                !s.isArchived &&
                    s.projectSlug !in collapsedIds &&
                    existingStepsById[s.cascadeId].isNullOrEmpty() &&
                    isSummaryHostReachable(s, conn)
            }
            for (s in recentToWarm.take(MAX_RECENT_STEP_PRELOAD_COUNT)) {
                addIfEligible(s.cascadeId)
            }
            // 2. Hydrate remaining unresolved-title conversations in expanded projects
            val unresolvedExpanded = sync.summaries.filter { s ->
                !s.isArchived && s.needsTitleHydration &&
                    s.cascadeId !in sync.settledEmptyTitleCascadeIds &&
                    s.projectSlug !in collapsedIds &&
                    isSummaryHostReachable(s, conn)
            }
            for (s in unresolvedExpanded.take(MAX_BACKGROUND_HYDRATE_COUNT)) {
                addIfEligible(s.cascadeId)
            }
            // 3. Lastly hydrate unresolved-title conversations in collapsed projects
            val unresolvedCollapsed = sync.summaries.filter { s ->
                !s.isArchived && s.needsTitleHydration &&
                    s.cascadeId !in sync.settledEmptyTitleCascadeIds &&
                    s.projectSlug in collapsedIds &&
                    isSummaryHostReachable(s, conn)
            }
            for (s in unresolvedCollapsed.take(MAX_BACKGROUND_HYDRATE_COUNT)) {
                addIfEligible(s.cascadeId)
            }
        }
        if (candidates.isEmpty()) return

        scope.launch {
            try {
                preloadMutex.withLock {
                    // Re-insert explicit priorities at the front of the queue
                    for (cid in priorityCascadeIds.asReversed()) {
                        if (cid in candidates) {
                            preloadQueue.remove(cid)
                            preloadQueue.addFirst(cid)
                        }
                    }
                    for (cid in candidates) {
                        if (cid !in preloadQueue) {
                            preloadQueue.addLast(cid)
                        }
                    }
                    if (preloadWorkerJob?.isActive == true) return@withLock
                    preloadWorkerJob = scope.launch {
                        try {
                            runPreloadWorkers()
                        } catch (e: CancellationException) {
                            throw e
                        } catch (_: Throwable) {
                            // Never allow background preloader failures to crash the app.
                        }
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Best-effort scheduling
            }
        }
    }

    private fun stopConversationPreload() {
        preloadWorkerJob?.cancel()
        preloadWorkerJob = null
    }

    private suspend fun runPreloadWorkers() {
        val conn = connectionStore.state.value
        val maxConcurrency = if (powerStateProvider.isLowPowerModeEnabled || conn.isNetworkExpensiveOrConstrained) 1 else 2
        coroutineScope {
            repeat(maxConcurrency) {
                launch {
                    while (isActive) {
                        if (activeForegroundSyncCount.value > 0) {
                            activeForegroundSyncCount.first { it == 0 }
                        }
                        val nextId = preloadMutex.withLock {
                            if (preloadQueue.isEmpty()) null else preloadQueue.removeFirst()
                        } ?: break
                        val liveConn = connectionStore.state.value
                        if (!liveConn.isConnected || liveConn.isNetworkingSuspended || !liveConn.isDeviceNetworkReachable) {
                            break
                        }
                        if (activeForegroundSyncCount.value > 0) {
                            preloadMutex.withLock { preloadQueue.addFirst(nextId) }
                            continue
                        }
                        preloadSingleConversation(nextId)
                    }
                }
            }
        }
    }

    private suspend fun preloadSingleConversation(cascadeId: String) {
        val summary = conversationSyncStore.state.value.summaries.firstOrNull { it.cascadeId == cascadeId } ?: return
        val conn = connectionStore.state.value
        if (!isSummaryHostReachable(summary, conn)) return
        val nowMs = currentTimeMillis()
        val recentlyAttempted = preloadMutex.withLock {
            val prev = preloadAttemptedAtMs[cascadeId]
            if (prev != null && (nowMs - prev) < PRELOAD_RETRY_COOLDOWN_MS) {
                true
            } else {
                preloadAttemptedAtMs[cascadeId] = nowMs
                false
            }
        }
        if (recentlyAttempted) return

        val client = connectionStore.activeClient() ?: return
        val isCloud = isSummaryCloud(summary)
        val shouldMarkHydrating = summary.needsTitleHydration
        if (shouldMarkHydrating) {
            conversationSyncStore.markHydrating(cascadeId)
        }
        try {
            var steps = chatStore.preloadSteps(
                client = client,
                cascadeId = cascadeId,
                knownStepCount = summary.stepCount,
                isCloud = isCloud,
                instanceUuidOverride = summary.originInstanceUuid,
                requireRemoteRefresh = false,
            )
            if (steps.isNotEmpty() && shouldMarkHydrating &&
                CascadeSummaryTitleResolver.deriveTitleFromSteps(steps) == null
            ) {
                steps = chatStore.preloadSteps(
                    client = client,
                    cascadeId = cascadeId,
                    knownStepCount = summary.stepCount,
                    isCloud = isCloud,
                    instanceUuidOverride = summary.originInstanceUuid,
                    requireRemoteRefresh = true,
                )
            }
            if (steps.isNotEmpty()) {
                conversationSyncStore.applyHydratedStepsMetadata(
                    host = conn.activeHost,
                    cascadeId = cascadeId,
                    steps = steps,
                    persist = true,
                )
            } else if (shouldMarkHydrating) {
                conversationSyncStore.markSettledEmptyTitle(cascadeId)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            // Settle cleanly so the row does not spin indefinitely; refresh/reconnect or tapping retries.
            if (shouldMarkHydrating) {
                conversationSyncStore.markSettledEmptyTitle(cascadeId)
            }
        } finally {
            if (shouldMarkHydrating) {
                conversationSyncStore.clearHydrating(cascadeId)
            }
        }
    }

    private fun isSummaryCloud(summary: CascadeSummary): Boolean {
        if (summary.isCloud) return true
        if (AntigravityCloudDetector.isCloudWorkspaceUri(summary.workspaceUri, cascadeId = summary.cascadeId)) return true
        val proj = (workspaceStore.state.value.projects + conversationSyncStore.state.value.projects).firstOrNull {
            (!summary.cloudProjectId.isNullOrBlank() && (it.cloudProjectId == summary.cloudProjectId || it.id == summary.cloudProjectId)) ||
                (summary.workspaceUri.isNotBlank() && it.workspaceUri == summary.workspaceUri) ||
                it.id == summary.projectSlug ||
                it.name.equals(summary.projectSlug, ignoreCase = true)
        }
        return proj?.runtime == ProjectRuntimeTarget.CLOUD
    }

    private fun isSummaryHostReachable(summary: CascadeSummary, conn: ConnectionState): Boolean {
        if (!conn.isDeviceNetworkReachable) return false
        if (summary.isCloud) {
            return if (conn.activeHost?.channel == RemoteConnectionChannel.CLOUD_RELAY && conn.availableRelayInstances.isNotEmpty()) {
                conn.availableRelayInstances.any { it.status.isReachable } || conn.isConnected
            } else {
                conn.isConnected || conn.isConnecting
            }
        }
        val originUuid = summary.originInstanceUuid?.trim().orEmpty()
        if (originUuid.isNotEmpty() && conn.availableRelayInstances.isNotEmpty()) {
            val matched = conn.availableRelayInstances.firstOrNull { it.uuid == originUuid }
            if (matched != null) return matched.status.isReachable
        }
        val originHost = summary.originHostName?.trim().orEmpty()
        if (originHost.isNotEmpty() && conn.availableRelayInstances.isNotEmpty()) {
            val matched = conn.availableRelayInstances.firstOrNull { it.name == originHost }
            if (matched != null) return matched.status.isReachable
        }
        return conn.isConnected || conn.isConnecting
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

    public fun isHostOnlineForSummary(summary: CascadeSummary?): Boolean {
        val conn = connectionStore.state.value
        if (!conn.hasPairedBackend) return true
        if (!conn.isDeviceNetworkReachable) return false
        if (summary == null) return conn.isConnected && (conn.activeHost?.isOnline != false)
        return isSummaryHostReachable(summary, conn)
    }

    public fun isCascadeActivelyStreaming(cascadeId: String): Boolean {
        val summary = conversationSyncStore.state.value.summaries.firstOrNull { it.cascadeId == cascadeId }
        val steps = chatStore.state.value.stepsByCascadeId[cascadeId].orEmpty()
        val conn = connectionStore.state.value
        if (summary != null) {
            if (summary.status == CortexStepStatus.PENDING) {
                if (!isHostOnlineForSummary(summary) || steps.isEmpty() || steps.any { it.isQueuedInOutbox }) {
                    return false
                }
                return true
            }
            if (summary.status == CortexStepStatus.IN_PROGRESS) {
                if (conn.hasPairedBackend && !isHostOnlineForSummary(summary)) {
                    return false
                }
                return steps.isNotEmpty()
            }
        }
        return steps.any { it.status == CortexStepStatus.IN_PROGRESS }
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
        val matchedModel = settingsStore.state.value.models.firstOrNull { it.containsModelId(modelId) }
        val resolvedModelId = matchedModel?.resolvedModelId(effort) ?: modelId
        val resolvedIsAlias = matchedModel?.resolvedIsModelAlias(effort) ?: !resolvedModelId.startsWith("MODEL_")
        val outcome = chatStore.sendMessage(
            client = client,
            cascadeId = cascadeId,
            message = message,
            workspaceUri = workspaceUri,
            attachments = attachments,
            modelId = resolvedModelId,
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
            isModelAlias = resolvedIsAlias,
        )
        if (outcome.resolvedCascadeId != cascadeId) {
            conversationSyncStore.replaceCascadeId(cascadeId, outcome.resolvedCascadeId)
        }
        val effectiveCid = outcome.resolvedCascadeId.ifBlank { cascadeId }
        val existingSummary = conversationSyncStore.state.value.summaries.firstOrNull { it.cascadeId == effectiveCid }
        if (existingSummary != null) {
            val updatedSummary = when {
                outcome.dispatchedLive -> existingSummary.copy(
                    status = CortexStepStatus.IN_PROGRESS,
                    statusSubtitle = "Running...",
                    updatedAtEpochMs = currentTimeMillis(),
                )
                outcome.queuedInOutbox -> existingSummary.copy(
                    status = CortexStepStatus.PENDING,
                    statusSubtitle = "Queued · Will send when back online",
                    updatedAtEpochMs = currentTimeMillis(),
                )
                !isVerificationMode && !outcome.errorMessage.isNullOrBlank() -> existingSummary.copy(
                    status = CortexStepStatus.DONE,
                    statusSubtitle = "Send failed · Tap to retry",
                    updatedAtEpochMs = currentTimeMillis(),
                )
                else -> existingSummary
            }
            if (updatedSummary != existingSummary) {
                conversationSyncStore.upsertSummary(updatedSummary)
            }
        }
        if (!isCloud && outcome.hostOfflineDetected) {
            connectionStore.markInstanceOffline(
                instanceUuid = instanceUuidOverride ?: existingSummary?.originInstanceUuid,
                errorMessage = outcome.errorMessage,
            )
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
        reconcileSelectedProjectForScope(
            AgentsHostFilterScope.LocalHost(instance.uuid, instance.name),
        )
        val client = connectionStore.activeClient()
        val host = connectionStore.state.value.activeHost
        if (client != null && host != null && host.isOnline) {
            conversationSyncStore.startSummarySubscriptionStream(client, host)
        } else {
            conversationSyncStore.stopSummarySubscriptionStream()
        }
    }

    public fun selectHostScope(targetScope: AgentsHostFilterScope) {
        connectionStore.selectHostScope(targetScope)
        reconcileSelectedProjectForScope(targetScope)
        if (isVerificationMode) return

        val connState = connectionStore.state.value
        if (!connState.hasPairedBackend && !connState.isConnected) return

        val generation = ++hostSwitchGeneration
        hostSwitchJob?.cancel()
        hostSwitchJob = scope.launch {
            try {
                val client = connectionStore.activeClient() ?: return@launch
                if (targetScope is AgentsHostFilterScope.LocalHost &&
                    connState.activeHost?.channel == RemoteConnectionChannel.CLOUD_RELAY
                ) {
                    val matchedRelay = connState.availableRelayInstances.firstOrNull {
                        it.uuid == targetScope.id || it.name == targetScope.name
                    }
                    val matchedHost = connState.knownHosts.firstOrNull {
                        it.instanceId == targetScope.id || it.hostname == targetScope.name
                    }
                    val targetInstance = matchedRelay ?: RelayInstanceInfo(
                        uuid = matchedHost?.instanceId ?: targetScope.id,
                        name = matchedHost?.hostname ?: targetScope.name,
                        version = matchedHost?.version.orEmpty(),
                        status = if (matchedHost?.isOnline == false) {
                            RelayInstanceStatus.DISCONNECTED
                        } else {
                            RelayInstanceStatus.CONNECTED
                        },
                    )
                    connectionStore.switchToRelayInstance(targetInstance)
                    if (!isActive || hostSwitchGeneration != generation || !connectionStore.state.value.hasPairedBackend) {
                        return@launch
                    }
                    val nextHost = connectionStore.state.value.activeHost
                    if (nextHost != null && nextHost.isOnline) {
                        conversationSyncStore.startSummarySubscriptionStream(client, nextHost)
                    } else {
                        conversationSyncStore.stopSummarySubscriptionStream()
                    }
                }
                if (!isActive || hostSwitchGeneration != generation || !connectionStore.state.value.hasPairedBackend) {
                    return@launch
                }
                refreshWorkspacesAndSummaries(
                    hostScope = targetScope,
                    skipRelayListRefresh = false,
                )
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Best-effort scoped refresh; offline hosts preserve their cached shards and status.
            }
        }
    }

    private fun reconcileSelectedProjectForScope(targetScope: AgentsHostFilterScope) {
        val connState = connectionStore.state.value
        val combined = (workspaceStore.state.value.projects + conversationSyncStore.state.value.projects)
            .distinctBy { it.id }
        val scopedNonEmpty = combined.filter { project ->
            !project.isNoProject && conversationSyncStore.projectMatchesHostScope(
                project = project,
                hostScope = targetScope,
                knownLocalHosts = connState.knownHosts,
                activeHost = connState.activeHost,
            )
        }
        val currentId = workspaceStore.state.value.selectedProjectId
        if (scopedNonEmpty.any { it.id == currentId }) {
            return
        }
        val preferred = scopedNonEmpty.firstOrNull()
        workspaceStore.selectProject(preferred?.id.orEmpty())
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

    public fun projectMatchesHostScope(
        project: ProjectWorkspace,
        hostScope: AgentsHostFilterScope = connectionStore.state.value.selectedHostScope,
    ): Boolean {
        val connState = connectionStore.state.value
        return conversationSyncStore.projectMatchesHostScope(
            project = project,
            hostScope = hostScope,
            knownLocalHosts = connState.knownHosts,
            activeHost = connState.activeHost,
        )
    }

    public fun summaryMatchesHostScope(
        summary: CascadeSummary,
        hostScope: AgentsHostFilterScope = connectionStore.state.value.selectedHostScope,
    ): Boolean {
        val connState = connectionStore.state.value
        return conversationSyncStore.summaryMatchesHostScope(
            summary = summary,
            hostScope = hostScope,
            knownLocalHosts = connState.knownHosts,
            activeHost = connState.activeHost,
        )
    }

    public fun filteredProjects(
        hostScope: AgentsHostFilterScope = connectionStore.state.value.selectedHostScope,
        excludeNoProject: Boolean = true,
    ): List<ProjectWorkspace> {
        val connState = connectionStore.state.value
        val combined = (workspaceStore.state.value.projects + conversationSyncStore.state.value.projects)
            .distinctBy { it.id }
        return combined.filter { project ->
            if (excludeNoProject && project.isNoProject) return@filter false
            conversationSyncStore.projectMatchesHostScope(
                project = project,
                hostScope = hostScope,
                knownLocalHosts = connState.knownHosts,
                activeHost = connState.activeHost,
            )
        }
    }

    public fun filteredSummaries(
        quickFilter: AgentsQuickFilter = AgentsQuickFilter.ALL,
        searchQuery: String = "",
        includeArchived: Boolean = false,
    ): List<CascadeSummary> {
        val connState = connectionStore.state.value
        return conversationSyncStore.filteredSummaries(
            hostScope = connState.selectedHostScope,
            quickFilter = quickFilter,
            searchQuery = searchQuery,
            includeArchived = includeArchived,
            knownLocalHosts = connState.knownHosts,
            activeHost = connState.activeHost,
        )
    }

    public fun parseMarkdown(markdown: String): List<MarkdownBlock> =
        chatStore.parseMarkdown(markdown)

    public fun onBackground() {
        stopConversationPreload()
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
            scheduleConversationPreload()
        }
    }

    @Throws(Throwable::class)
    public suspend fun disconnectAndClearCredentials() {
        hostSwitchGeneration += 1L
        val activeHostSwitch = hostSwitchJob
        hostSwitchJob = null
        activeHostSwitch?.cancelAndJoin()
        stopConversationPreload()
        preloadMutex.withLock {
            preloadQueue.clear()
            preloadAttemptedAtMs.clear()
        }
        conversationSyncStore.clear()
        chatStore.clear()
        connectionStore.disconnectAndClearCredentials()
    }

    @Throws(Throwable::class)
    public suspend fun close() {
        hostSwitchGeneration += 1L
        hostSwitchJob?.cancel()
        hostSwitchJob = null
        stopConversationPreload()
        conversationSyncStore.stopSummarySubscriptionStream()
        connectionStore.close()
        scope.cancel()
    }

    @Throws(Throwable::class)
    public suspend fun refreshModelCatalog(forceRefresh: Boolean = false): LiveModelCatalogResult? {
        if (isVerificationMode && !connectionStore.state.value.hasPairedBackend) {
            return null
        }
        val client = connectionStore.activeClient() ?: return null
        return settingsStore.refreshModelCatalog(client = client, forceRefresh = forceRefresh)
    }

    @Throws(Throwable::class)
    public suspend fun refreshUserProfile(): String? {
        if (isVerificationMode && !connectionStore.state.value.hasPairedBackend) {
            return connectionStore.state.value.userDisplayName
        }
        val client = connectionStore.activeClient() ?: return connectionStore.state.value.userDisplayName
        val profile = client.fetchUserProfile()
        if (profile?.displayName != null) {
            connectionStore.setUserDisplayName(profile.displayName, persist = !isVerificationMode)
        }
        return connectionStore.state.value.userDisplayName
    }

    @Throws(Throwable::class)
    public suspend fun revealProjectInFinder(projectId: String): Boolean {
        val project = (workspaceStore.state.value.projects + conversationSyncStore.state.value.projects)
            .firstOrNull { it.id == projectId || it.name == projectId }
            ?: return false
        if (project.runtime == ProjectRuntimeTarget.CLOUD ||
            project.isNoProject ||
            project.workspaceUri.isBlank()
        ) {
            return false
        }
        val client = connectionStore.activeClient() ?: return false
        client.openWorkspaceInFinder(project.workspaceUri)
        return true
    }

    private suspend fun onHandshakeSucceeded(
        handshake: BackendHandshakeResult,
        startSummaryStream: Boolean,
    ) {
        val host = connectionStore.state.value.activeHost ?: return
        conversationSyncStore.applyHandshake(host, handshake)
        reconcileSelectedProjectForScope(connectionStore.state.value.selectedHostScope)
        conversationSyncStore.resetSettledEmptyTitles()
        val client = connectionStore.activeClient()
        if (client != null && handshake.isSelectedHostOnline) {
            if (startSummaryStream) {
                conversationSyncStore.startSummarySubscriptionStream(client, host)
            }
            if (host.channel == RemoteConnectionChannel.CLOUD_RELAY &&
                (!handshake.initialSyncCompleted || (handshake.summaries.isEmpty() && handshake.workspaces.isEmpty()))
            ) {
                val activeScope = connectionStore.state.value.selectedHostScope
                scope.launch {
                    try {
                        val synced = conversationSyncStore.refreshWorkspacesAndSummaries(
                            client = client,
                            host = host,
                            hostScope = activeScope,
                            skipRelayListRefresh = true,
                        )
                        if (activeScope is AgentsHostFilterScope.LocalHost && synced.succeededInstanceUuids.isEmpty()) {
                            connectionStore.markInstanceOffline(
                                instanceUuid = host.instanceId,
                                errorMessage = "${host.hostname} is currently offline.",
                            )
                        }
                        reconcileSelectedProjectForScope(activeScope)
                        scheduleConversationPreload()
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Throwable) {
                        if (ProtocolCompatibilityEngine.isInstanceNotRegisteredError(e)) {
                            connectionStore.markInstanceOffline(
                                instanceUuid = host.instanceId,
                                errorMessage = ProtocolCompatibilityEngine.formatUserFacingRpcError(e),
                            )
                        }
                    }
                }
            } else {
                scheduleConversationPreload()
            }
            scope.launch {
                try {
                    refreshModelCatalog()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    // Best-effort live model catalog hydration; sheet refreshes again on open.
                }
            }
            scope.launch {
                try {
                    refreshUserProfile()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Throwable) {
                    // Best-effort signed-in user profile hydration; greeting falls back cleanly without blocking handshake.
                }
            }
            scope.launch {
                try {
                    if (connectionStore.state.value.isConnected) {
                        chatStore.replayPendingOutbox(client)
                    }
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
        private const val MAX_BACKGROUND_HYDRATE_COUNT: Int = 32
        private const val MAX_RECENT_STEP_PRELOAD_COUNT: Int = 8
        private const val PRELOAD_RETRY_COOLDOWN_MS: Long = 30_000L

        public fun createEsddVerificationCoordinator(): AntigravityCoreCoordinator =
            EsddVerificationFixtures.createVerificationCoordinator()
    }
}
