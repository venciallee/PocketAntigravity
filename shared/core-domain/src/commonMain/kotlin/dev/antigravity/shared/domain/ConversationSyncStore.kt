package dev.antigravity.shared.domain

import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.AgentsQuickFilter
import dev.antigravity.shared.model.AntigravityCloudDetector
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.CascadeSummaryTitleResolver
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.model.RemoteConnectionChannel
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.model.WorkspaceInfo
import dev.antigravity.shared.protocol.AntigravityKmpRpcClient
import dev.antigravity.shared.protocol.BackendHandshakeResult
import dev.antigravity.shared.protocol.FederatedWorkspaceSyncResult
import dev.antigravity.shared.protocol.JsonStepAndSummaryDecoder
import dev.antigravity.shared.protocol.currentTimeMillis
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.Throws

public data class ConversationSyncState(
    public val workspaces: List<WorkspaceInfo> = emptyList(),
    public val projects: List<ProjectWorkspace> = emptyList(),
    public val summaries: List<CascadeSummary> = emptyList(),
    public val isRefreshing: Boolean = false,
    public val isStreamHealthy: Boolean = false,
    public val lastSyncedAtEpochMs: Long = 0L,
    public val errorText: String? = null,
    public val hydratingCascadeIds: Set<String> = emptySet(),
    public val settledEmptyTitleCascadeIds: Set<String> = emptySet(),
    public val cachedStepCascadeIds: Set<String> = emptySet(),
)

/**
 * Shared KMP conversation & workspace synchronization store (`StateFlow<ConversationSyncState>`).
 *
 * Implements per-host sharded offline caching (`HostProjectionShard`) so refreshing an online
 * host never overwrites or discards cached conversations belonging to an offline peer host,
 * plus live 5-byte Connect-RPC `JetboxSubscribeToSummaries` stream updates.
 */
public class ConversationSyncStore(
    private val scope: CoroutineScope,
    private val projectionStorage: ProjectionStoragePort,
) {
    private val _state = MutableStateFlow(ConversationSyncState())
    public val state: StateFlow<ConversationSyncState> = _state.asStateFlow()

    private var summaryStreamJob: Job? = null

    @Throws(Throwable::class)
    public suspend fun hydrateFromCache() {
        val shards = projectionStorage.loadAllHostShards()
        if (shards.isEmpty()) return
        val allSummaries = shards.flatMap { it.summaries }
            .distinctBy { it.cascadeId }
            .sortedWith(compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId })
        val allProjects = shards.flatMap { it.projects }.distinctBy { it.id }
        _state.update { prev ->
            if (prev.summaries.isNotEmpty()) prev
            else prev.copy(summaries = allSummaries, projects = allProjects)
        }
    }

    @Throws(Throwable::class)
    public suspend fun applyHandshake(
        host: RemoteHostInstance,
        handshake: BackendHandshakeResult,
    ) {
        val refreshedKeys = computeRefreshedHostKeys(
            host = host,
            availableInstances = handshake.availableRelayInstances.map { it.uuid to it.status.isReachable },
            hasCloudData = handshake.cloudProjects.isNotEmpty() || handshake.summaries.any { it.isCloud },
            hostOnline = handshake.isSelectedHostOnline,
            succeededInstanceUuids = handshake.succeededInstanceUuids.toSet(),
            initialSyncCompleted = handshake.initialSyncCompleted,
            hasLocalIncomingData = handshake.workspaces.any { !it.isCloud } || handshake.summaries.any { !it.isCloud },
        )
        mergeAndPersist(
            host = host,
            incomingWorkspaces = handshake.workspaces,
            incomingSummaries = handshake.summaries,
            incomingCloudProjects = handshake.cloudProjects,
            refreshedHostKeys = refreshedKeys,
        )
    }

    @Throws(Throwable::class)
    public suspend fun refreshWorkspacesAndSummaries(
        client: AntigravityKmpRpcClient,
        host: RemoteHostInstance,
        hostScope: AgentsHostFilterScope = AgentsHostFilterScope.AllHosts,
        skipRelayListRefresh: Boolean = false,
    ): FederatedWorkspaceSyncResult {
        _state.update { it.copy(isRefreshing = true, errorText = null) }
        return try {
            val isRelay = host.channel == RemoteConnectionChannel.CLOUD_RELAY
            val targetUuid = if (isRelay && hostScope is AgentsHostFilterScope.LocalHost) hostScope.id else null
            val includeLocal = !isRelay || hostScope !is AgentsHostFilterScope.AntigravityCloud
            val includeCloud = !isRelay || hostScope !is AgentsHostFilterScope.LocalHost

            val result = client.fetchFederatedWorkspacesAndSummaries(
                skipRelayListRefresh = skipRelayListRefresh,
                targetInstanceUuid = targetUuid,
                includeLocal = includeLocal,
                includeCloud = includeCloud,
            )

            val refreshedKeys = mutableSetOf<String>()
            if (isRelay) {
                for (uuid in result.succeededInstanceUuids) refreshedKeys.add("host:$uuid")
                if (includeCloud && (result.cloudSucceeded || result.cloudProjects.isNotEmpty())) {
                    refreshedKeys.add("cloud")
                }
            } else {
                refreshedKeys.add(
                    HostProjectionKey.compute(
                        isCloud = false,
                        instanceId = host.instanceId,
                        hostname = host.hostname,
                        fallbackHostId = host.instanceId,
                        fallbackHostName = host.hostname,
                    )
                )
                if (result.summaries.any { it.isCloud } || result.cloudProjects.isNotEmpty()) {
                    refreshedKeys.add("cloud")
                }
            }

            mergeAndPersist(
                host = host,
                incomingWorkspaces = result.workspaces,
                incomingSummaries = result.summaries,
                incomingCloudProjects = result.cloudProjects,
                refreshedHostKeys = refreshedKeys,
            )
            _state.update { it.copy(isRefreshing = false, lastSyncedAtEpochMs = currentTimeMillis()) }
            result
        } catch (e: Throwable) {
            _state.update { it.copy(isRefreshing = false, errorText = e.message ?: "Sync failed") }
            throw e
        }
    }

    public fun startSummarySubscriptionStream(
        client: AntigravityKmpRpcClient,
        host: RemoteHostInstance,
        onStreamActivity: (() -> Unit)? = null,
        onStreamError: ((Throwable) -> Unit)? = null,
    ) {
        stopSummarySubscriptionStream()
        val isRelay = host.channel == RemoteConnectionChannel.CLOUD_RELAY
        val cleanEofDelayMs = if (isRelay) 5_000L else 2_000L
        summaryStreamJob = scope.launch {
            var consecutiveErrors = 0
            while (isActive) {
                var receivedFrame = false
                try {
                    client.subscribeEnvelopeStream("JetboxSubscribeToSummaries")
                        .collect { jsonObj ->
                            receivedFrame = true
                            consecutiveErrors = 0
                            onStreamActivity?.invoke()
                            val event = JsonStepAndSummaryDecoder.decodeJetboxSummariesEvent(
                                obj = jsonObj,
                                originInstanceUuid = host.instanceId,
                                originHostName = host.hostname,
                            )
                            if (event.summaries.isNotEmpty() || event.removedCascadeIds.isNotEmpty()) {
                                applyStreamEvent(event)
                            } else {
                                _state.update { prev -> prev.copy(isStreamHealthy = true) }
                            }
                        }
                    if (!isActive) break
                    if (!receivedFrame) {
                        _state.update { prev -> prev.copy(isStreamHealthy = false) }
                    }
                    delay(cleanEofDelayMs)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    _state.update { prev -> prev.copy(isStreamHealthy = false) }
                    onStreamError?.invoke(e)
                    if (!isActive) break
                    consecutiveErrors += 1
                    val backoffMs = when {
                        consecutiveErrors <= 1 -> 3_000L
                        consecutiveErrors == 2 -> 6_000L
                        consecutiveErrors == 3 -> 12_000L
                        else -> 30_000L
                    }
                    delay(backoffMs)
                }
            }
        }
    }

    public fun stopSummarySubscriptionStream() {
        summaryStreamJob?.cancel()
        summaryStreamJob = null
        _state.update { it.copy(isStreamHealthy = false) }
    }

    public fun applyStreamEvent(event: JsonStepAndSummaryDecoder.JetboxDecodedEvent) {
        _state.update { prev ->
            val byId = prev.summaries.associateBy { it.cascadeId }.toMutableMap()
            val nextHydrating = prev.hydratingCascadeIds.toMutableSet()
            val nextSettled = prev.settledEmptyTitleCascadeIds.toMutableSet()
            for (removedId in event.removedCascadeIds) {
                byId.remove(removedId)
                nextHydrating.remove(removedId)
                nextSettled.remove(removedId)
            }
            for (incoming in event.summaries) {
                val existing = byId[incoming.cascadeId]
                val mergedItem = mergeIncomingSummary(existing = existing, incoming = incoming)
                byId[incoming.cascadeId] = mergedItem
                if (mergedItem.hasResolvedTitle) {
                    nextHydrating.remove(incoming.cascadeId)
                    nextSettled.remove(incoming.cascadeId)
                }
            }
            val merged = byId.values.sortedWith(
                compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId }
            )
            prev.copy(
                summaries = merged,
                isStreamHealthy = true,
                lastSyncedAtEpochMs = currentTimeMillis(),
                hydratingCascadeIds = nextHydrating,
                settledEmptyTitleCascadeIds = nextSettled,
            )
        }
    }

    private fun mergeIncomingSummary(
        existing: CascadeSummary?,
        incoming: CascadeSummary,
    ): CascadeSummary {
        if (existing == null) return incoming
        val mergedStepCount = maxOf(existing.stepCount, incoming.stepCount)
        val hasNewActivity = incoming.stepCount > existing.stepCount ||
            (incoming.updatedAtEpochMs - existing.updatedAtEpochMs) > 500L
        val latestViewed = listOfNotNull(existing.lastUserViewTimeEpochMs, incoming.lastUserViewTimeEpochMs).maxOrNull()
        val effectiveUnread = when {
            incoming.status == CortexStepStatus.IN_PROGRESS || incoming.status == CortexStepStatus.PENDING -> false
            hasNewActivity -> incoming.isUnread
            latestViewed != null && incoming.updatedAtEpochMs <= latestViewed -> false
            else -> incoming.isUnread
        }
        val effectiveSubtitle = if (effectiveUnread == incoming.isUnread) {
            incoming.statusSubtitle
        } else {
            JsonStepAndSummaryDecoder.buildLiveStatusSubtitle(
                status = incoming.status,
                stepCount = mergedStepCount,
                isUnread = effectiveUnread,
            )
        }
        val keepExistingTitle = existing.hasResolvedTitle && !incoming.hasResolvedTitle
        val resolvedTitle = if (keepExistingTitle) existing.title else incoming.title
        val resolvedHasTitle = existing.hasResolvedTitle || incoming.hasResolvedTitle
        return existing.copy(
            title = resolvedTitle,
            hasResolvedTitle = resolvedHasTitle,
            status = incoming.status,
            stepCount = mergedStepCount,
            currentStepIndex = incoming.currentStepIndex,
            totalSteps = maxOf(existing.totalSteps, incoming.totalSteps),
            updatedAtEpochMs = maxOf(existing.updatedAtEpochMs, incoming.updatedAtEpochMs),
            relativeTimeLabel = incoming.relativeTimeLabel,
            statusSubtitle = effectiveSubtitle,
            isPinned = existing.isPinned || incoming.isPinned,
            isArchived = existing.isArchived || incoming.isArchived,
            isUnread = effectiveUnread,
            lastUserViewTimeEpochMs = latestViewed,
            pendingInteractionTitle = incoming.pendingInteractionTitle ?: existing.pendingInteractionTitle,
        )
    }

    public fun markHydrating(cascadeId: String) {
        if (cascadeId.isEmpty()) return
        _state.update { prev ->
            if (cascadeId in prev.hydratingCascadeIds) prev
            else prev.copy(hydratingCascadeIds = prev.hydratingCascadeIds + cascadeId)
        }
    }

    public fun clearHydrating(cascadeId: String) {
        if (cascadeId.isEmpty()) return
        _state.update { prev ->
            if (cascadeId !in prev.hydratingCascadeIds) prev
            else prev.copy(hydratingCascadeIds = prev.hydratingCascadeIds - cascadeId)
        }
    }

    public fun markSettledEmptyTitle(cascadeId: String) {
        if (cascadeId.isEmpty()) return
        _state.update { prev ->
            prev.copy(
                hydratingCascadeIds = prev.hydratingCascadeIds - cascadeId,
                settledEmptyTitleCascadeIds = prev.settledEmptyTitleCascadeIds + cascadeId,
            )
        }
    }

    public fun resetSettledEmptyTitles() {
        _state.update { prev ->
            if (prev.settledEmptyTitleCascadeIds.isEmpty()) prev
            else prev.copy(settledEmptyTitleCascadeIds = emptySet())
        }
    }

    public fun markStepsCached(cascadeIds: Collection<String>) {
        if (cascadeIds.isEmpty()) return
        _state.update { prev ->
            prev.copy(cachedStepCascadeIds = prev.cachedStepCascadeIds + cascadeIds)
        }
    }

    /**
     * Applies step-derived metadata (`title`, `hasResolvedTitle`, `stepCount`) for [cascadeId] and
     * persists the updated host projection shard so future launches render the hydrated title instantly.
     */
    @Throws(Throwable::class)
    public suspend fun applyHydratedStepsMetadata(
        host: RemoteHostInstance?,
        cascadeId: String,
        steps: List<CascadeStep>,
        persist: Boolean = true,
    ): Boolean {
        if (cascadeId.isEmpty()) return false
        val derivedTitle = CascadeSummaryTitleResolver.deriveTitleFromSteps(steps)
        var changed = false
        var touchedSummary: CascadeSummary? = null

        _state.update { prev ->
            val idx = prev.summaries.indexOfFirst { it.cascadeId == cascadeId }
            val nextHydrating = prev.hydratingCascadeIds - cascadeId
            val nextCached = if (steps.isNotEmpty()) prev.cachedStepCascadeIds + cascadeId else prev.cachedStepCascadeIds
            if (idx < 0) {
                return@update prev.copy(
                    hydratingCascadeIds = nextHydrating,
                    cachedStepCascadeIds = nextCached,
                )
            }
            val current = prev.summaries[idx]
            val nextStepCount = maxOf(current.stepCount, steps.size)
            val shouldUpdateTitle = current.needsTitleHydration && !derivedTitle.isNullOrBlank()
            val updated = if (shouldUpdateTitle || nextStepCount != current.stepCount) {
                changed = true
                current.copy(
                    title = if (shouldUpdateTitle) derivedTitle!! else current.title,
                    hasResolvedTitle = if (shouldUpdateTitle) true else current.hasResolvedTitle,
                    stepCount = nextStepCount,
                    currentStepIndex = maxOf(1, nextStepCount),
                    totalSteps = maxOf(current.totalSteps, nextStepCount),
                    statusSubtitle = JsonStepAndSummaryDecoder.buildLiveStatusSubtitle(
                        status = current.status,
                        stepCount = nextStepCount,
                        isUnread = current.isUnread,
                    ),
                )
            } else {
                current
            }
            touchedSummary = updated
            val nextSummaries = if (changed) {
                prev.summaries.toMutableList().apply { this[idx] = updated }
            } else {
                prev.summaries
            }
            val nextSettled = when {
                updated.hasResolvedTitle -> prev.settledEmptyTitleCascadeIds - cascadeId
                steps.isEmpty() && current.needsTitleHydration -> prev.settledEmptyTitleCascadeIds + cascadeId
                else -> prev.settledEmptyTitleCascadeIds
            }
            prev.copy(
                summaries = nextSummaries,
                hydratingCascadeIds = nextHydrating,
                settledEmptyTitleCascadeIds = nextSettled,
                cachedStepCascadeIds = nextCached,
            )
        }

        val summary = touchedSummary
        if (persist && changed && host != null && summary != null) {
            val hostKey = HostProjectionKey.compute(
                isCloud = summary.isCloud,
                instanceId = summary.originInstanceUuid,
                hostname = summary.originHostName,
                fallbackHostId = host.instanceId,
                fallbackHostName = host.hostname,
            )
            val snapshot = _state.value
            persistShards(
                host = host,
                summaries = snapshot.summaries,
                projects = snapshot.projects,
                refreshedHostKeys = setOf(hostKey),
            )
        }
        return changed
    }

    public fun upsertSummary(summary: CascadeSummary) {
        _state.update { prev ->
            val byId = prev.summaries.associateBy { it.cascadeId }.toMutableMap()
            byId[summary.cascadeId] = summary
            val sorted = byId.values.sortedWith(
                compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId }
            )
            prev.copy(summaries = sorted)
        }
    }

    public fun replaceCascadeId(oldId: String, newId: String) {
        if (oldId == newId || newId.isEmpty()) return
        _state.update { prev ->
            val next = prev.summaries.map { s ->
                if (s.cascadeId == oldId) s.copy(cascadeId = newId) else s
            }.distinctBy { it.cascadeId }
            prev.copy(summaries = next)
        }
    }

    public fun removeSummary(cascadeId: String) {
        _state.update { prev ->
            prev.copy(
                summaries = prev.summaries.filterNot { it.cascadeId == cascadeId },
                hydratingCascadeIds = prev.hydratingCascadeIds - cascadeId,
                settledEmptyTitleCascadeIds = prev.settledEmptyTitleCascadeIds - cascadeId,
                cachedStepCascadeIds = prev.cachedStepCascadeIds - cascadeId,
            )
        }
    }

    public fun seedFixtureData(
        workspaces: List<WorkspaceInfo>,
        projects: List<ProjectWorkspace>,
        summaries: List<CascadeSummary>,
    ) {
        _state.update {
            it.copy(
                workspaces = workspaces,
                projects = projects,
                summaries = summaries,
                isRefreshing = false,
                isStreamHealthy = true,
                lastSyncedAtEpochMs = currentTimeMillis(),
                errorText = null,
            )
        }
    }

    public fun markAllRead() {
        val now = currentTimeMillis()
        _state.update { prev ->
            prev.copy(
                summaries = prev.summaries.map { summary ->
                    summary.copy(
                        isUnread = false,
                        lastUserViewTimeEpochMs = maxOf(now, summary.updatedAtEpochMs),
                        statusSubtitle = JsonStepAndSummaryDecoder.buildLiveStatusSubtitle(
                            status = summary.status,
                            stepCount = summary.stepCount,
                            isUnread = false,
                        ),
                    )
                },
            )
        }
    }

    public fun togglePinned(cascadeId: String) {
        _state.update { prev ->
            prev.copy(
                summaries = prev.summaries.map { summary ->
                    if (summary.cascadeId == cascadeId) summary.copy(isPinned = !summary.isPinned) else summary
                },
            )
        }
    }

    public fun toggleUnread(cascadeId: String) {
        val now = currentTimeMillis()
        _state.update { prev ->
            prev.copy(
                summaries = prev.summaries.map { summary ->
                    if (summary.cascadeId == cascadeId) {
                        val nextUnread = !summary.isUnread
                        summary.copy(
                            isUnread = nextUnread,
                            lastUserViewTimeEpochMs = if (nextUnread) summary.lastUserViewTimeEpochMs else now,
                        )
                    } else {
                        summary
                    }
                },
            )
        }
    }

    public fun archiveConversation(cascadeId: String) {
        _state.update { prev ->
            prev.copy(
                summaries = prev.summaries.map { summary ->
                    if (summary.cascadeId == cascadeId) {
                        summary.copy(isArchived = true, isPinned = false)
                    } else {
                        summary
                    }
                },
            )
        }
    }

    public fun deleteConversation(cascadeId: String) {
        removeSummary(cascadeId)
    }

    public fun updateSummaries(transform: (List<CascadeSummary>) -> List<CascadeSummary>) {
        _state.update { prev ->
            prev.copy(summaries = transform(prev.summaries))
        }
    }

    public fun summaryMatchesHostScope(
        summary: CascadeSummary,
        hostScope: AgentsHostFilterScope,
        knownLocalHosts: List<RemoteHostInstance> = emptyList(),
        activeHost: RemoteHostInstance? = null,
    ): Boolean = when (hostScope) {
        AgentsHostFilterScope.AllHosts -> true
        AgentsHostFilterScope.AntigravityCloud -> summary.isCloud
        is AgentsHostFilterScope.LocalHost -> {
            if (summary.isCloud) {
                false
            } else {
                val distinctLocalHosts = knownLocalHosts
                    .filter { it.instanceId != "unpaired" && !it.hostname.equals("cloud", ignoreCase = true) }
                    .distinctBy { it.instanceId }
                val originId = summary.originInstanceUuid?.takeIf { it.isNotBlank() }
                val originHost = summary.originHostName?.takeIf { it.isNotBlank() }
                if (distinctLocalHosts.size <= 1) {
                    if (originId != null) {
                        originId == hostScope.id || originId == activeHost?.instanceId || originHost == hostScope.name
                    } else {
                        true
                    }
                } else {
                    when {
                        originId != null -> originId == hostScope.id || (originHost != null && originHost == hostScope.name)
                        originHost != null -> originHost == hostScope.name
                        else -> activeHost?.instanceId == hostScope.id || activeHost?.hostname == hostScope.name
                    }
                }
            }
        }
    }

    public fun projectMatchesHostScope(
        project: ProjectWorkspace,
        hostScope: AgentsHostFilterScope,
        knownLocalHosts: List<RemoteHostInstance> = emptyList(),
        activeHost: RemoteHostInstance? = null,
    ): Boolean = when (hostScope) {
        AgentsHostFilterScope.AllHosts -> true
        AgentsHostFilterScope.AntigravityCloud -> project.runtime == ProjectRuntimeTarget.CLOUD
        is AgentsHostFilterScope.LocalHost -> {
            if (project.runtime == ProjectRuntimeTarget.CLOUD) {
                false
            } else {
                val distinctLocalHosts = knownLocalHosts
                    .filter { it.instanceId != "unpaired" && !it.hostname.equals("cloud", ignoreCase = true) }
                    .distinctBy { it.instanceId }
                val originId = project.originInstanceUuid?.takeIf { it.isNotBlank() }
                val hostLabel = project.hostName.trim()
                if (distinctLocalHosts.size <= 1) {
                    if (originId != null) {
                        originId == hostScope.id || originId == activeHost?.instanceId || hostLabel == hostScope.name
                    } else {
                        true
                    }
                } else {
                    when {
                        originId != null -> originId == hostScope.id || (hostLabel.isNotEmpty() && hostLabel == hostScope.name)
                        hostLabel.isNotEmpty() -> hostLabel == hostScope.name
                        else -> activeHost?.instanceId == hostScope.id || activeHost?.hostname == hostScope.name
                    }
                }
            }
        }
    }

    public fun filteredProjects(
        hostScope: AgentsHostFilterScope = AgentsHostFilterScope.AllHosts,
        knownLocalHosts: List<RemoteHostInstance> = emptyList(),
        activeHost: RemoteHostInstance? = null,
        excludeNoProject: Boolean = true,
    ): List<ProjectWorkspace> = _state.value.projects.filter { project ->
        if (excludeNoProject && project.isNoProject) return@filter false
        projectMatchesHostScope(
            project = project,
            hostScope = hostScope,
            knownLocalHosts = knownLocalHosts,
            activeHost = activeHost,
        )
    }

    public fun filteredSummaries(
        hostScope: AgentsHostFilterScope = AgentsHostFilterScope.AllHosts,
        quickFilter: AgentsQuickFilter = AgentsQuickFilter.ALL,
        searchQuery: String = "",
        includeArchived: Boolean = false,
        knownLocalHosts: List<RemoteHostInstance> = emptyList(),
        activeHost: RemoteHostInstance? = null,
    ): List<CascadeSummary> {
        val q = searchQuery.trim().lowercase()
        return _state.value.summaries.filter { s ->
            if (!includeArchived && s.isArchived) return@filter false
            val matchesScope = summaryMatchesHostScope(
                summary = s,
                hostScope = hostScope,
                knownLocalHosts = knownLocalHosts,
                activeHost = activeHost,
            )
            if (!matchesScope) return@filter false
            val matchesFilter = when (quickFilter) {
                AgentsQuickFilter.ALL -> true
                AgentsQuickFilter.RUNNING -> s.status == CortexStepStatus.IN_PROGRESS || s.status == CortexStepStatus.PENDING
                AgentsQuickFilter.NEEDS_YOU -> s.status == CortexStepStatus.WAITING || s.status == CortexStepStatus.BLOCKED
                AgentsQuickFilter.UNREAD -> s.isUnread
            }
            if (!matchesFilter) return@filter false
            if (q.isNotEmpty()) {
                s.title.lowercase().contains(q) || s.projectSlug.lowercase().contains(q)
            } else {
                true
            }
        }
    }

    public fun clear() {
        stopSummarySubscriptionStream()
        _state.value = ConversationSyncState()
    }

    private suspend fun mergeAndPersist(
        host: RemoteHostInstance,
        incomingWorkspaces: List<WorkspaceInfo>,
        incomingSummaries: List<CascadeSummary>,
        incomingCloudProjects: List<ProjectWorkspace>,
        refreshedHostKeys: Set<String>,
    ) {
        val prev = _state.value
        val existingById = prev.summaries.associateBy { it.cascadeId }
        val reconciledIncomingSummaries = incomingSummaries.map { incoming ->
            mergeIncomingSummary(existing = existingById[incoming.cascadeId], incoming = incoming)
        }
        val incomingIds = reconciledIncomingSummaries.map { it.cascadeId }.toSet()

        // Preserve local optimistic drafts (not yet upgraded to a server UUID) and summaries belonging to offline/unrefreshed host shards
        val preservedSummaries = prev.summaries.filter { existing ->
            if (existing.cascadeId in incomingIds) return@filter false
            if (existing.cascadeId.startsWith("cas-") || existing.cascadeId.startsWith("cascade-new-")) return@filter true
            val key = HostProjectionKey.compute(
                isCloud = existing.isCloud,
                instanceId = existing.originInstanceUuid,
                hostname = existing.originHostName,
                fallbackHostId = host.instanceId,
                fallbackHostName = host.hostname,
            )
            key !in refreshedHostKeys
        }

        val mergedSummaries = (reconciledIncomingSummaries + preservedSummaries)
            .distinctBy { it.cascadeId }
            .sortedWith(compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId })

        fun workspaceCompositeKey(ws: WorkspaceInfo): String {
            val hostKey = HostProjectionKey.compute(
                isCloud = ws.isCloud,
                instanceId = ws.originInstanceUuid,
                hostname = ws.originHostName,
                fallbackHostId = host.instanceId,
                fallbackHostName = host.hostname,
            )
            return "$hostKey|${ws.workspaceUri.lowercase()}"
        }

        val incomingWsKeys = incomingWorkspaces.map(::workspaceCompositeKey).toSet()
        val preservedWorkspaces = prev.workspaces.filter { ws ->
            if (workspaceCompositeKey(ws) in incomingWsKeys) return@filter false
            val key = HostProjectionKey.compute(
                isCloud = ws.isCloud,
                instanceId = ws.originInstanceUuid,
                hostname = ws.originHostName,
                fallbackHostId = host.instanceId,
                fallbackHostName = host.hostname,
            )
            key !in refreshedHostKeys
        }.toMutableList()

        // Preserve unrefreshed local hosts' 0-conversation projects even when prev.workspaces wasn't populated (e.g., cache hydration)
        val keptWsKeySet = (incomingWorkspaces + preservedWorkspaces).map(::workspaceCompositeKey).toMutableSet()
        for (existingProj in prev.projects) {
            if (existingProj.runtime == ProjectRuntimeTarget.CLOUD || existingProj.isNoProject || existingProj.workspaceUri.isBlank()) {
                continue
            }
            val projHostKey = HostProjectionKey.compute(
                isCloud = false,
                instanceId = existingProj.originInstanceUuid,
                hostname = existingProj.hostName,
                fallbackHostId = host.instanceId,
                fallbackHostName = host.hostname,
            )
            if (projHostKey in refreshedHostKeys) continue
            val candidate = WorkspaceInfo(
                workspaceUri = existingProj.workspaceUri,
                displayName = existingProj.name,
                activeBranch = existingProj.activeBranch,
                worktrees = existingProj.worktrees,
                isCloud = false,
                originInstanceUuid = existingProj.originInstanceUuid,
                originHostName = existingProj.hostName,
            )
            val ck = workspaceCompositeKey(candidate)
            if (keptWsKeySet.add(ck)) {
                preservedWorkspaces.add(candidate)
            }
        }

        val mergedWorkspaces = (incomingWorkspaces + preservedWorkspaces).distinctBy(::workspaceCompositeKey)
        val effectiveCloudProjects = if ("cloud" in refreshedHostKeys || incomingCloudProjects.isNotEmpty()) {
            incomingCloudProjects
        } else {
            prev.projects.filter { it.runtime == ProjectRuntimeTarget.CLOUD && !it.isNoProject }
        }
        val (mergedProjects, normalizedSummaries) = reconcileProjects(
            workspaces = mergedWorkspaces,
            summaries = mergedSummaries,
            cloudProjects = effectiveCloudProjects,
            defaultHostName = host.hostname,
            defaultInstanceUuid = host.instanceId,
        )

        _state.update {
            it.copy(
                workspaces = mergedWorkspaces,
                projects = mergedProjects,
                summaries = normalizedSummaries,
                lastSyncedAtEpochMs = currentTimeMillis(),
            )
        }

        // Persist ONLY refreshed host shards so offline host shards on disk stay intact.
        // Never rewrite shards when a failed/deferred handshake returned empty data.
        if (refreshedHostKeys.isNotEmpty() || incomingWorkspaces.isNotEmpty() || incomingSummaries.isNotEmpty() || incomingCloudProjects.isNotEmpty()) {
            persistShards(host, normalizedSummaries, mergedProjects, refreshedHostKeys)
        }
    }

    private suspend fun persistShards(
        host: RemoteHostInstance,
        summaries: List<CascadeSummary>,
        projects: List<ProjectWorkspace>,
        refreshedHostKeys: Set<String>,
    ) {
        val summariesByKey = mutableMapOf<String, MutableList<CascadeSummary>>()
        val projectsByKey = mutableMapOf<String, MutableList<ProjectWorkspace>>()
        for (s in summaries) {
            val k = HostProjectionKey.compute(s.isCloud, s.originInstanceUuid, s.originHostName, host.instanceId, host.hostname)
            summariesByKey.getOrPut(k) { mutableListOf() }.add(s)
        }
        for (p in projects) {
            val k = HostProjectionKey.compute(p.runtime == ProjectRuntimeTarget.CLOUD, p.originInstanceUuid, p.hostName, host.instanceId, host.hostname)
            projectsByKey.getOrPut(k) { mutableListOf() }.add(p)
        }
        val keysToWrite = refreshedHostKeys.ifEmpty { summariesByKey.keys + projectsByKey.keys }
        val now = currentTimeMillis()
        val shards = keysToWrite.map { key ->
            val isCloud = (key == "cloud")
            val rawId = key.removePrefix("host:")
            val hostName = if (isCloud) "Antigravity" else {
                summariesByKey[key]?.firstOrNull()?.originHostName
                    ?: projectsByKey[key]?.firstOrNull()?.hostName
                    ?: host.hostname
            }
            HostProjectionShard(
                hostKey = key,
                instanceId = if (isCloud) null else rawId,
                hostname = hostName,
                isCloud = isCloud,
                summaries = summariesByKey[key].orEmpty(),
                projects = projectsByKey[key].orEmpty(),
                updatedAtEpochMs = now,
            )
        }
        if (shards.isNotEmpty()) {
            projectionStorage.saveHostShards(shards)
        }
    }

    private fun computeRefreshedHostKeys(
        host: RemoteHostInstance,
        availableInstances: List<Pair<String, Boolean>>,
        hasCloudData: Boolean,
        hostOnline: Boolean,
        succeededInstanceUuids: Set<String> = emptySet(),
        initialSyncCompleted: Boolean = true,
        hasLocalIncomingData: Boolean = true,
    ): Set<String> {
        if (!initialSyncCompleted) return emptySet()
        val keys = mutableSetOf<String>()
        if (host.channel == RemoteConnectionChannel.CLOUD_RELAY) {
            if (succeededInstanceUuids.isNotEmpty()) {
                for (uuid in succeededInstanceUuids) {
                    if (uuid.isNotEmpty() && uuid != "unpaired") {
                        keys.add("host:$uuid")
                    }
                }
            } else if (hasLocalIncomingData) {
                for ((uuid, reachable) in availableInstances) {
                    if (reachable) keys.add("host:$uuid")
                }
                if (hostOnline && host.instanceId.isNotEmpty() && host.instanceId != "unpaired") {
                    keys.add("host:${host.instanceId}")
                }
            }
        } else if (hostOnline || succeededInstanceUuids.isNotEmpty() || hasLocalIncomingData) {
            keys.add(HostProjectionKey.compute(false, host.instanceId, host.hostname, host.instanceId, host.hostname))
        }
        if (hasCloudData) keys.add("cloud")
        return keys
    }

    private fun reconcileProjects(
        workspaces: List<WorkspaceInfo>,
        summaries: List<CascadeSummary>,
        cloudProjects: List<ProjectWorkspace>,
        defaultHostName: String,
        defaultInstanceUuid: String? = null,
    ): Pair<List<ProjectWorkspace>, List<CascadeSummary>> {
        val byId = linkedMapOf<String, ProjectWorkspace>()
        val keyToProjectId = mutableMapOf<String, String>()

        fun allocateProjectId(
            baseName: String,
            isCloud: Boolean,
            originUuid: String?,
            originHostName: String?,
        ): String {
            if (!byId.containsKey(baseName)) return baseName
            if (isCloud) {
                val cloudId = "cloud:$baseName"
                if (!byId.containsKey(cloudId)) return cloudId
            }
            val hostKey = originUuid?.takeIf { it.isNotBlank() }
                ?: originHostName?.takeIf { it.isNotBlank() }
                ?: defaultInstanceUuid?.takeIf { it.isNotBlank() }
                ?: defaultHostName
            return if (isCloud) "cloud:$baseName" else "host:$hostKey:$baseName"
        }

        fun dedupeKey(
            name: String,
            isCloud: Boolean,
            originUuid: String?,
            originHostName: String?,
            workspaceUri: String,
        ): String {
            val scopeKey = if (isCloud) {
                "cloud"
            } else {
                originUuid?.takeIf { it.isNotBlank() }
                    ?: originHostName?.takeIf { it.isNotBlank() }
                    ?: defaultHostName
            }
            val normalizedUri = workspaceUri.trim().lowercase()
            return if (normalizedUri.isNotEmpty()) "$scopeKey|uri|$normalizedUri" else "$scopeKey|name|${name.lowercase()}"
        }

        for (cp in cloudProjects) {
            val key = dedupeKey(cp.name, true, cp.originInstanceUuid, "Cloud", cp.workspaceUri)
            if (!keyToProjectId.containsKey(key)) {
                val id = if (cp.id.isNotBlank() && !byId.containsKey(cp.id)) cp.id else allocateProjectId(cp.name, true, cp.originInstanceUuid, "Cloud")
                byId[id] = cp.copy(id = id, runtime = ProjectRuntimeTarget.CLOUD, hostName = "Cloud")
                keyToProjectId[key] = id
            }
        }

        for (ws in workspaces) {
            val baseName = ws.displayName.ifBlank { ws.workspaceUri }
            if (AntigravityCloudDetector.isNoProjectSlug(baseName)) continue
            val isCloud = ws.isCloud || AntigravityCloudDetector.isCloudWorkspaceUri(ws.workspaceUri)
            val resolvedHost = if (isCloud) "Cloud" else (ws.originHostName?.takeIf { it.isNotBlank() } ?: defaultHostName)
            val resolvedUuid = ws.originInstanceUuid?.takeIf { it.isNotBlank() } ?: if (isCloud) null else defaultInstanceUuid
            val key = dedupeKey(baseName, isCloud, resolvedUuid, resolvedHost, ws.workspaceUri)
            if (keyToProjectId.containsKey(key)) continue
            val id = allocateProjectId(baseName, isCloud, resolvedUuid, resolvedHost)
            if (!byId.containsKey(id)) {
                byId[id] = ProjectWorkspace(
                    id = id,
                    name = baseName,
                    pathDisplay = ws.workspaceUri.removePrefix("file://"),
                    workspaceUri = ws.workspaceUri,
                    runtime = if (isCloud) ProjectRuntimeTarget.CLOUD else ProjectRuntimeTarget.MAC_BOOK_PRO,
                    hostName = resolvedHost,
                    activeBranch = ws.activeBranch,
                    worktrees = ws.worktrees,
                    originInstanceUuid = resolvedUuid,
                )
            }
            keyToProjectId[key] = id
        }

        val normalizedSummaries = summaries.map { s ->
            val rawSlug = s.projectSlug.ifBlank { AntigravityCloudDetector.NO_PROJECT_DISPLAY_NAME }
            val baseName = AntigravityCloudDetector.stripProjectScopePrefix(rawSlug).ifBlank {
                AntigravityCloudDetector.NO_PROJECT_DISPLAY_NAME
            }
            val resolvedHost = if (s.isCloud) "Cloud" else (s.originHostName?.takeIf { it.isNotBlank() } ?: defaultHostName)
            val resolvedUuid = s.originInstanceUuid?.takeIf { it.isNotBlank() } ?: if (s.isCloud) null else defaultInstanceUuid
            val key = dedupeKey(baseName, s.isCloud, resolvedUuid, resolvedHost, s.workspaceUri)

            val matchedProjectId = keyToProjectId[key]
                ?: byId.values.firstOrNull { existing ->
                    existing.name.equals(baseName, ignoreCase = true) &&
                        (existing.runtime == ProjectRuntimeTarget.CLOUD) == s.isCloud &&
                        (s.isCloud || existing.originInstanceUuid == resolvedUuid || existing.hostName == resolvedHost)
                }?.id
                ?: run {
                    val id = allocateProjectId(baseName, s.isCloud, resolvedUuid, resolvedHost)
                    if (!byId.containsKey(id)) {
                        byId[id] = ProjectWorkspace(
                            id = id,
                            name = baseName,
                            pathDisplay = s.workspaceUri.removePrefix("file://").ifBlank { baseName },
                            workspaceUri = s.workspaceUri,
                            runtime = if (s.isCloud) ProjectRuntimeTarget.CLOUD else ProjectRuntimeTarget.MAC_BOOK_PRO,
                            hostName = resolvedHost,
                            activeBranch = s.branchName,
                            cloudProjectId = s.cloudProjectId,
                            originInstanceUuid = resolvedUuid,
                        )
                    }
                    keyToProjectId[key] = id
                    id
                }

            if (s.projectSlug == matchedProjectId) s else s.copy(projectSlug = matchedProjectId)
        }
        return byId.values.toList() to normalizedSummaries
    }
}
