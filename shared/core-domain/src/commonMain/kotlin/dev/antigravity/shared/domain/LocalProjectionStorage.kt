package dev.antigravity.shared.domain

import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.protocol.currentTimeMillis
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable

@Serializable
public enum class OutboxPayloadKind {
    USER_MESSAGE,
    INTERACTION_APPROVAL,
    PLAN_COMMENTS,
    DIFF_COMMENTS,
    AUTOMATION_TRIGGER,
}

@Serializable
public data class DurableOutboxEntry(
    public val id: String,
    public val cascadeId: String,
    public val kind: OutboxPayloadKind,
    public val messageText: String? = null,
    public val stepIndex: Int? = null,
    public val createdAtEpochMs: Long = currentTimeMillis(),
)

/**
 * Per-host cached projection shard so refreshing online Macs never overwrites
 * or discards offline Macs' cached conversation lists or projects.
 */
@Serializable
public data class HostProjectionShard(
    public val hostKey: String,
    public val instanceId: String? = null,
    public val hostname: String,
    public val isCloud: Boolean = false,
    public val summaries: List<CascadeSummary> = emptyList(),
    public val projects: List<ProjectWorkspace> = emptyList(),
    public val updatedAtEpochMs: Long = currentTimeMillis(),
)

public object HostProjectionKey {
    public fun compute(
        isCloud: Boolean,
        instanceId: String?,
        hostname: String?,
        fallbackHostId: String,
        fallbackHostName: String,
    ): String {
        if (isCloud) return "cloud"
        val cleanId = instanceId?.trim().orEmpty()
        if (cleanId.isNotEmpty() && cleanId != "unpaired") return "host:$cleanId"
        val cleanHost = hostname?.trim().orEmpty()
        if (cleanHost.isNotEmpty()) return "host:$cleanHost"
        val fbId = fallbackHostId.trim()
        if (fbId.isNotEmpty() && fbId != "unpaired") return "host:$fbId"
        val fbHost = fallbackHostName.trim()
        if (fbHost.isNotEmpty()) return "host:$fbHost"
        return "host:default"
    }
}

/**
 * Platform-neutral local display projection & Durable Outbox storage contract.
 * - iOS: backed by `LocalProjectionStore` (atomic JSON files in Caches directory)
 * - Android: backed by Room / SQLDelight / DataStore
 * - Tests: [InMemoryProjectionStorage]
 */
public interface ProjectionStoragePort {
    public suspend fun loadAllHostShards(): List<HostProjectionShard>
    public suspend fun saveHostShards(shards: List<HostProjectionShard>)
    public suspend fun loadKnownHosts(): List<RemoteHostInstance>
    public suspend fun saveKnownHosts(hosts: List<RemoteHostInstance>)
    public suspend fun loadSteps(cascadeId: String): List<CascadeStep>
    public suspend fun saveSteps(cascadeId: String, steps: List<CascadeStep>)
    public suspend fun loadPendingOutbox(): List<DurableOutboxEntry>
    public suspend fun enqueueOutbox(entry: DurableOutboxEntry)
    public suspend fun removeOutbox(entryId: String)
    public suspend fun clearAll()
}

/**
 * Thread-safe in-memory [ProjectionStoragePort] usable across JVM, Android, and iOS.
 */
public class InMemoryProjectionStorage : ProjectionStoragePort {
    private val mutex = Mutex()
    private val shards = linkedMapOf<String, HostProjectionShard>()
    private var hosts: List<RemoteHostInstance> = emptyList()
    private val stepsByCascade = linkedMapOf<String, List<CascadeStep>>()
    private val outbox = mutableListOf<DurableOutboxEntry>()

    override suspend fun loadAllHostShards(): List<HostProjectionShard> = mutex.withLock {
        shards.values.sortedWith(compareByDescending<HostProjectionShard> { it.updatedAtEpochMs }.thenBy { it.hostKey })
    }

    override suspend fun saveHostShards(shards: List<HostProjectionShard>) {
        mutex.withLock {
            for (shard in shards) {
                this.shards[shard.hostKey] = shard
            }
        }
    }

    override suspend fun loadKnownHosts(): List<RemoteHostInstance> = mutex.withLock { hosts }

    override suspend fun saveKnownHosts(hosts: List<RemoteHostInstance>) {
        mutex.withLock { this.hosts = hosts }
    }

    override suspend fun loadSteps(cascadeId: String): List<CascadeStep> = mutex.withLock {
        stepsByCascade[cascadeId].orEmpty()
    }

    override suspend fun saveSteps(cascadeId: String, steps: List<CascadeStep>) {
        mutex.withLock { stepsByCascade[cascadeId] = steps }
    }

    override suspend fun loadPendingOutbox(): List<DurableOutboxEntry> = mutex.withLock {
        outbox.toList()
    }

    override suspend fun enqueueOutbox(entry: DurableOutboxEntry) {
        mutex.withLock {
            if (outbox.none { it.id == entry.id }) {
                outbox.add(entry)
            }
        }
    }

    override suspend fun removeOutbox(entryId: String) {
        mutex.withLock {
            outbox.removeAll { it.id == entryId }
        }
    }

    override suspend fun clearAll() {
        mutex.withLock {
            shards.clear()
            hosts = emptyList()
            stepsByCascade.clear()
            outbox.clear()
        }
    }
}
