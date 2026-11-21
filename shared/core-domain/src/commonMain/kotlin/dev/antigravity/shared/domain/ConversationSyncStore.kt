package dev.antigravity.shared.domain

import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.AgentsQuickFilter
import dev.antigravity.shared.model.AntigravityCloudDetector
import dev.antigravity.shared.model.CascadeSummary
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

public data class ConversationSyncState(
    public val workspaces: List<WorkspaceInfo> = emptyList(),
    public val projects: List<ProjectWorkspace> = emptyList(),
    public val summaries: List<CascadeSummary> = emptyList(),
    public val isRefreshing: Boolean = false,
    public val isStreamHealthy: Boolean = false,
    public val lastSyncedAtEpochMs: Long = 0L,
    public val errorText: String? = null,
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

    public suspend fun applyHandshake(
        host: RemoteHostInstance,
        handshake: BackendHandshakeResult,
    ) {
        val refreshedKeys = computeRefreshedHostKeys(
            host = host,
            availableInstances = handshake.availableRelayInstances.map { it.uuid to it.status.isReachable },
            hasCloudData = handshake.cloudProjects.isNotEmpty() || handshake.summaries.any { it.isCloud },
            hostOnline = handshake.isSelectedHostOnline,
        )
        mergeAndPersist(
            host = host,
            incomingWorkspaces = handshake.workspaces,
            incomingSummaries = handshake.summaries,
            incomingCloudProjects = handshake.cloudProjects,
            refreshedHostKeys = refreshedKeys,
        )
    }

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
    ) {
        stopSummarySubscriptionStream()
        summaryStreamJob = scope.launch {
            client.subscribeEnvelopeStream("JetboxSubscribeToSummaries")
                .catch {
                    _state.update { prev -> prev.copy(isStreamHealthy = false) }
                }
                .collect { jsonObj ->
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
            for (removedId in event.removedCascadeIds) {
                byId.remove(removedId)
            }
            for (incoming in event.summaries) {
                val existing = byId[incoming.cascadeId]
                byId[incoming.cascadeId] = if (existing == null) {
                    incoming
                } else {
                    existing.copy(
                        title = if (incoming.title == "New Conversation" && existing.title != "New Conversation") existing.title else incoming.title,
                        status = incoming.status,
                        stepCount = maxOf(existing.stepCount, incoming.stepCount),
                        currentStepIndex = incoming.currentStepIndex,
                        totalSteps = maxOf(existing.totalSteps, incoming.totalSteps),
                        updatedAtEpochMs = maxOf(existing.updatedAtEpochMs, incoming.updatedAtEpochMs),
                        relativeTimeLabel = incoming.relativeTimeLabel,
                        statusSubtitle = incoming.statusSubtitle,
                        isPinned = incoming.isPinned,
                        isArchived = incoming.isArchived,
                        isUnread = incoming.isUnread,
                        pendingInteractionTitle = incoming.pendingInteractionTitle ?: existing.pendingInteractionTitle,
                    )
                }
            }
            val merged = byId.values.sortedWith(
                compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId }
            )
            prev.copy(
                summaries = merged,
                isStreamHealthy = true,
                lastSyncedAtEpochMs = currentTimeMillis(),
            )
        }
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
            prev.copy(summaries = prev.summaries.filterNot { it.cascadeId == cascadeId })
        }
    }

    public fun filteredSummaries(
        hostScope: AgentsHostFilterScope = AgentsHostFilterScope.AllHosts,
        quickFilter: AgentsQuickFilter = AgentsQuickFilter.ALL,
        searchQuery: String = "",
        includeArchived: Boolean = false,
    ): List<CascadeSummary> {
        val q = searchQuery.trim().lowercase()
        return _state.value.summaries.filter { s ->
            if (!includeArchived && s.isArchived) return@filter false
            val matchesScope = when (hostScope) {
                AgentsHostFilterScope.AllHosts -> true
                AgentsHostFilterScope.AntigravityCloud -> s.isCloud
                is AgentsHostFilterScope.LocalHost -> !s.isCloud &&
                    (s.originInstanceUuid == hostScope.id || s.originHostName == hostScope.name)
            }
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
        val incomingIds = incomingSummaries.map { it.cascadeId }.toSet()

        // Preserve summaries belonging to offline/unrefreshed host shards
        val preservedSummaries = prev.summaries.filter { existing ->
            if (existing.cascadeId in incomingIds) return@filter false
            val key = HostProjectionKey.compute(
                isCloud = existing.isCloud,
                instanceId = existing.originInstanceUuid,
                hostname = existing.originHostName,
                fallbackHostId = host.instanceId,
                fallbackHostName = host.hostname,
            )
            key !in refreshedHostKeys
        }

        val mergedSummaries = (incomingSummaries + preservedSummaries)
            .distinctBy { it.cascadeId }
            .sortedWith(compareByDescending<CascadeSummary> { it.updatedAtEpochMs }.thenBy { it.cascadeId })

        val incomingWsUris = incomingWorkspaces.map { it.workspaceUri }.toSet()
        val preservedWorkspaces = prev.workspaces.filter { ws ->
            if (ws.workspaceUri in incomingWsUris) return@filter false
            val key = HostProjectionKey.compute(
                isCloud = ws.isCloud,
                instanceId = ws.originInstanceUuid,
                hostname = ws.originHostName,
                fallbackHostId = host.instanceId,
                fallbackHostName = host.hostname,
            )
            key !in refreshedHostKeys
        }
        val mergedWorkspaces = (incomingWorkspaces + preservedWorkspaces).distinctBy { it.workspaceUri }
        val mergedProjects = reconcileProjects(
            workspaces = mergedWorkspaces,
            summaries = mergedSummaries,
            cloudProjects = incomingCloudProjects,
            defaultHostName = host.hostname,
        )

        _state.update {
            it.copy(
                workspaces = mergedWorkspaces,
                projects = mergedProjects,
                summaries = mergedSummaries,
                lastSyncedAtEpochMs = currentTimeMillis(),
            )
        }

        // Persist ONLY refreshed host shards so offline host shards on disk stay intact
        persistShards(host, mergedSummaries, mergedProjects, refreshedHostKeys)
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
    ): Set<String> {
        val keys = mutableSetOf<String>()
        if (host.channel == RemoteConnectionChannel.CLOUD_RELAY) {
            for ((uuid, reachable) in availableInstances) {
                if (reachable) keys.add("host:$uuid")
            }
            if (hostOnline && host.instanceId.isNotEmpty() && host.instanceId != "unpaired") {
                keys.add("host:${host.instanceId}")
            }
        } else {
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
    ): List<ProjectWorkspace> {
        val byId = linkedMapOf<String, ProjectWorkspace>()
        for (cp in cloudProjects) byId[cp.id] = cp
        for (ws in workspaces) {
            val id = ws.displayName.ifBlank { ws.workspaceUri }
            if (!byId.containsKey(id)) {
                byId[id] = ProjectWorkspace(
                    id = id,
                    name = ws.displayName,
                    pathDisplay = ws.workspaceUri.removePrefix("file://"),
                    workspaceUri = ws.workspaceUri,
                    runtime = if (ws.isCloud) ProjectRuntimeTarget.CLOUD else ProjectRuntimeTarget.MAC_BOOK_PRO,
                    hostName = ws.originHostName ?: defaultHostName,
                    activeBranch = ws.activeBranch,
                    worktrees = ws.worktrees,
                    originInstanceUuid = ws.originInstanceUuid,
                )
            }
        }
        for (s in summaries) {
            val slug = s.projectSlug.ifBlank { AntigravityCloudDetector.NO_PROJECT_DISPLAY_NAME }
            if (!byId.containsKey(slug)) {
                byId[slug] = ProjectWorkspace(
                    id = slug,
                    name = slug,
                    pathDisplay = s.workspaceUri.removePrefix("file://").ifBlank { slug },
                    workspaceUri = s.workspaceUri,
                    runtime = if (s.isCloud) ProjectRuntimeTarget.CLOUD else ProjectRuntimeTarget.MAC_BOOK_PRO,
                    hostName = s.originHostName ?: defaultHostName,
                    activeBranch = s.branchName,
                    cloudProjectId = s.cloudProjectId,
                    originInstanceUuid = s.originInstanceUuid,
                )
            }
        }
        return byId.values.toList()
    }
}
