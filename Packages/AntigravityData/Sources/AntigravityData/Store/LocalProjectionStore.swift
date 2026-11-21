import Foundation

/// Durable outbox entry persisted before network dispatch so user turns and approvals
/// survive network transitions or backgrounding.
public struct OutboxEntry: Codable, Sendable, Equatable, Identifiable {
    public enum PayloadKind: String, Codable, Sendable {
        case userMessage
        case interactionApproval
        case planComments
        case diffComments
        case automationTrigger
    }

    public var id: UUID
    public var cascadeId: String
    public var kind: PayloadKind
    public var messageText: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        cascadeId: String,
        kind: PayloadKind,
        messageText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cascadeId = cascadeId
        self.kind = kind
        self.messageText = messageText
        self.createdAt = createdAt
    }
}

/// Per-host cached projection shard persisted under `AntigravityProjections/hosts/host_<key>.json`
/// so refreshing online Macs never overwrites or discards offline Macs' cached conversation lists or projects.
public struct HostProjectionSnapshot: Codable, Sendable, Equatable {
    public var hostKey: String
    public var instanceId: String?
    public var hostname: String
    public var isCloud: Bool
    public var summaries: [CascadeSummary]
    public var projects: [ProjectWorkspace]
    public var updatedAt: Date

    public init(
        hostKey: String,
        instanceId: String? = nil,
        hostname: String,
        isCloud: Bool = false,
        summaries: [CascadeSummary] = [],
        projects: [ProjectWorkspace] = [],
        updatedAt: Date = Date()
    ) {
        self.hostKey = hostKey
        self.instanceId = instanceId
        self.hostname = hostname
        self.isCloud = isCloud
        self.summaries = summaries
        self.projects = projects
        self.updatedAt = updatedAt
    }
}

/// Manages local display projections for `<10ms` instant cold start and offline browsing,
/// including per-host sharded conversation/project caches (`hosts/host_<key>.json`),
/// paired host roster (`hosts_projection.json`), per-cascade step caches (`steps_<id>.json`),
/// `AgentDisplayOptions`, `AutomationItem` records, and the Durable Outbox queue.
public actor LocalProjectionStore {
    private let storageDirectory: URL
    private let hostsDirectory: URL
    private var cachedSummaries: [CascadeSummary] = []
    private var cachedStepsByCascade: [String: [CascadeStep]] = [:]
    private var cachedProjects: [ProjectWorkspace] = []
    private var cachedHostProjections: [String: HostProjectionSnapshot] = [:]
    private var hasLoadedHostProjectionsFromDisk: Bool = false
    private var cachedKnownHosts: [RemoteHostInstance] = []
    private var hasLoadedKnownHostsFromDisk: Bool = false
    private var cachedAutomations: [AutomationItem] = []
    private var cachedDisplayOptions: AgentDisplayOptions?
    private var cachedAppearancePreferences: AppAppearancePreferences?
    private var cachedUsageQuota: ModelUsageQuota?
    private var cachedCustomizations: CustomizationsCatalog?
    private var outboxQueue: [OutboxEntry] = []
    private var hasLoadedOutboxFromDisk: Bool = false

    public init(storageDirectory: URL? = nil) {
        let base = storageDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.storageDirectory = base.appendingPathComponent("AntigravityProjections", isDirectory: true)
        self.hostsDirectory = self.storageDirectory.appendingPathComponent("hosts", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: self.hostsDirectory, withIntermediateDirectories: true)
    }

    public static func sanitizedHostFileKey(for hostKey: String) -> String {
        let trimmed = hostKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "default" }
        return trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "..", with: "_")
    }

    private func ensureHostProjectionsLoaded() {
        guard !hasLoadedHostProjectionsFromDisk else { return }
        hasLoadedHostProjectionsFromDisk = true

        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: hostsDirectory, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("host_") && url.pathExtension == "json" {
                if let data = try? Data(contentsOf: url),
                   let decoded = try? JSONDecoder().decode(HostProjectionSnapshot.self, from: data) {
                    cachedHostProjections[decoded.hostKey] = decoded
                }
            }
        }

        // Seamless migration from legacy single-file global projections when no per-host shards exist yet
        if cachedHostProjections.isEmpty {
            let legacySummaries = loadProjectedSummaries()
            let legacyProjects = loadProjects()
            if !legacySummaries.isEmpty || !legacyProjects.isEmpty {
                var summariesByKey: [String: [CascadeSummary]] = [:]
                var projectsByKey: [String: [ProjectWorkspace]] = [:]
                var metaByKey: [String: (instanceId: String?, hostname: String, isCloud: Bool)] = [:]

                for s in legacySummaries {
                    let key: String
                    if s.isCloud {
                        key = "cloud"
                        metaByKey[key] = (nil, "Antigravity", true)
                    } else if let uuid = s.originInstanceUuid?.trimmingCharacters(in: .whitespacesAndNewlines), !uuid.isEmpty {
                        key = "host:\(uuid)"
                        metaByKey[key] = (uuid, s.originHostName ?? uuid, false)
                    } else if let host = s.originHostName?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
                        key = "host:\(host)"
                        metaByKey[key] = (nil, host, false)
                    } else {
                        key = "host:default"
                        metaByKey[key] = (nil, "Local Mac", false)
                    }
                    summariesByKey[key, default: []].append(s)
                }

                for p in legacyProjects {
                    let key: String
                    if p.runtime == .cloud {
                        key = "cloud"
                        metaByKey[key] = (nil, "Antigravity", true)
                    } else if let uuid = p.originInstanceUuid?.trimmingCharacters(in: .whitespacesAndNewlines), !uuid.isEmpty {
                        key = "host:\(uuid)"
                        if metaByKey[key] == nil {
                            metaByKey[key] = (uuid, p.hostName.isEmpty ? uuid : p.hostName, false)
                        }
                    } else if !p.hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        key = "host:\(p.hostName)"
                        if metaByKey[key] == nil {
                            metaByKey[key] = (nil, p.hostName, false)
                        }
                    } else {
                        key = "host:default"
                        if metaByKey[key] == nil {
                            metaByKey[key] = (nil, "Local Mac", false)
                        }
                    }
                    projectsByKey[key, default: []].append(p)
                }

                let allKeys = Set(summariesByKey.keys).union(projectsByKey.keys)
                for key in allKeys {
                    let meta = metaByKey[key] ?? (nil, key, key == "cloud")
                    let snapshot = HostProjectionSnapshot(
                        hostKey: key,
                        instanceId: meta.instanceId,
                        hostname: meta.hostname,
                        isCloud: meta.isCloud,
                        summaries: summariesByKey[key] ?? [],
                        projects: projectsByKey[key] ?? [],
                        updatedAt: Date()
                    )
                    cachedHostProjections[key] = snapshot
                }
            }
        }
    }

    public func loadAllHostProjections() -> [HostProjectionSnapshot] {
        ensureHostProjectionsLoaded()
        return cachedHostProjections.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.hostKey < rhs.hostKey
        }
    }

    public func loadHostProjection(hostKey: String) -> HostProjectionSnapshot? {
        ensureHostProjectionsLoaded()
        return cachedHostProjections[hostKey]
    }

    public func saveHostProjection(_ snapshot: HostProjectionSnapshot) {
        ensureHostProjectionsLoaded()
        cachedHostProjections[snapshot.hostKey] = snapshot
        try? FileManager.default.createDirectory(at: hostsDirectory, withIntermediateDirectories: true)
        let safeKey = Self.sanitizedHostFileKey(for: snapshot.hostKey)
        let file = hostsDirectory.appendingPathComponent("host_\(safeKey).json")
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func saveHostProjections(_ snapshots: [HostProjectionSnapshot]) {
        guard !snapshots.isEmpty else { return }
        ensureHostProjectionsLoaded()
        try? FileManager.default.createDirectory(at: hostsDirectory, withIntermediateDirectories: true)
        for snapshot in snapshots {
            cachedHostProjections[snapshot.hostKey] = snapshot
            let safeKey = Self.sanitizedHostFileKey(for: snapshot.hostKey)
            let file = hostsDirectory.appendingPathComponent("host_\(safeKey).json")
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    public func loadKnownHosts() -> [RemoteHostInstance] {
        if hasLoadedKnownHostsFromDisk {
            return cachedKnownHosts
        }
        hasLoadedKnownHostsFromDisk = true
        let file = storageDirectory.appendingPathComponent("hosts_projection.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([RemoteHostInstance].self, from: data) else {
            return []
        }
        cachedKnownHosts = decoded
        return decoded
    }

    public func saveKnownHosts(_ hosts: [RemoteHostInstance]) {
        hasLoadedKnownHostsFromDisk = true
        cachedKnownHosts = hosts
        let file = storageDirectory.appendingPathComponent("hosts_projection.json")
        if let data = try? JSONEncoder().encode(hosts) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func loadProjectedSummaries() -> [CascadeSummary] {
        if !cachedSummaries.isEmpty { return cachedSummaries }
        let file = storageDirectory.appendingPathComponent("summaries_projection.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([CascadeSummary].self, from: data) else {
            return []
        }
        cachedSummaries = decoded
        return decoded
    }

    public func saveProjectedSummaries(_ summaries: [CascadeSummary]) {
        cachedSummaries = summaries
        let file = storageDirectory.appendingPathComponent("summaries_projection.json")
        if let data = try? JSONEncoder().encode(summaries) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private static func sanitizedFileKey(for cascadeId: String) -> String {
        cascadeId
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    public func loadProjectedSteps(cascadeId: String) -> [CascadeStep] {
        if let cached = cachedStepsByCascade[cascadeId] { return cached }
        let safeKey = Self.sanitizedFileKey(for: cascadeId)
        let file = storageDirectory.appendingPathComponent("steps_\(safeKey).json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([CascadeStep].self, from: data) else {
            return []
        }
        cachedStepsByCascade[cascadeId] = decoded
        return decoded
    }

    public func saveProjectedSteps(_ steps: [CascadeStep], for cascadeId: String) {
        cachedStepsByCascade[cascadeId] = steps
        let safeKey = Self.sanitizedFileKey(for: cascadeId)
        let file = storageDirectory.appendingPathComponent("steps_\(safeKey).json")
        if let data = try? JSONEncoder().encode(steps) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func loadDisplayOptions() -> AgentDisplayOptions? {
        if let cachedDisplayOptions { return cachedDisplayOptions }
        let file = storageDirectory.appendingPathComponent("display_options.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode(AgentDisplayOptions.self, from: data) else {
            return nil
        }
        cachedDisplayOptions = decoded
        return decoded
    }

    public func saveDisplayOptions(_ options: AgentDisplayOptions) {
        cachedDisplayOptions = options
        let file = storageDirectory.appendingPathComponent("display_options.json")
        if let data = try? JSONEncoder().encode(options) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func loadAppearancePreferences() -> AppAppearancePreferences? {
        if let cachedAppearancePreferences { return cachedAppearancePreferences }
        let file = storageDirectory.appendingPathComponent("appearance_prefs.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode(AppAppearancePreferences.self, from: data) else {
            return nil
        }
        cachedAppearancePreferences = decoded
        return decoded
    }

    public func saveAppearancePreferences(_ preferences: AppAppearancePreferences) {
        cachedAppearancePreferences = preferences
        let file = storageDirectory.appendingPathComponent("appearance_prefs.json")
        if let data = try? JSONEncoder().encode(preferences) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func loadUsageQuota() -> ModelUsageQuota? {
        if let cachedUsageQuota { return cachedUsageQuota }
        let file = storageDirectory.appendingPathComponent("usage_quota.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode(ModelUsageQuota.self, from: data) else {
            return nil
        }
        cachedUsageQuota = decoded
        return decoded
    }

    public func saveUsageQuota(_ quota: ModelUsageQuota) {
        cachedUsageQuota = quota
        let file = storageDirectory.appendingPathComponent("usage_quota.json")
        if let data = try? JSONEncoder().encode(quota) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func loadCustomizations() -> CustomizationsCatalog? {
        if let cachedCustomizations { return cachedCustomizations }
        let file = storageDirectory.appendingPathComponent("customizations_catalog.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode(CustomizationsCatalog.self, from: data) else {
            return nil
        }
        cachedCustomizations = decoded
        return decoded
    }

    public func saveCustomizations(_ catalog: CustomizationsCatalog) {
        cachedCustomizations = catalog
        let file = storageDirectory.appendingPathComponent("customizations_catalog.json")
        if let data = try? JSONEncoder().encode(catalog) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func loadProjects() -> [ProjectWorkspace] {
        if !cachedProjects.isEmpty { return cachedProjects }
        let file = storageDirectory.appendingPathComponent("projects_projection.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([ProjectWorkspace].self, from: data) else {
            return []
        }
        cachedProjects = decoded
        return decoded
    }

    public func saveProjects(_ projects: [ProjectWorkspace]) {
        cachedProjects = projects
        let file = storageDirectory.appendingPathComponent("projects_projection.json")
        if let data = try? JSONEncoder().encode(projects) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func loadAutomations() -> [AutomationItem] {
        if !cachedAutomations.isEmpty { return cachedAutomations }
        let file = storageDirectory.appendingPathComponent("automations_projection.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([AutomationItem].self, from: data) else {
            return []
        }
        cachedAutomations = decoded
        return decoded
    }

    public func saveAutomations(_ automations: [AutomationItem]) {
        cachedAutomations = automations
        let file = storageDirectory.appendingPathComponent("automations_projection.json")
        if let data = try? JSONEncoder().encode(automations) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func ensureOutboxLoaded() {
        guard !hasLoadedOutboxFromDisk else { return }
        hasLoadedOutboxFromDisk = true
        let file = storageDirectory.appendingPathComponent("outbox_queue.json")
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([OutboxEntry].self, from: data) else {
            return
        }
        outboxQueue = decoded
    }

    private func persistOutbox() {
        let file = storageDirectory.appendingPathComponent("outbox_queue.json")
        if outboxQueue.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else if let data = try? JSONEncoder().encode(outboxQueue) {
            try? data.write(to: file, options: .atomic)
        }
    }

    public func loadPendingOutbox() -> [OutboxEntry] {
        ensureOutboxLoaded()
        return outboxQueue
    }

    public func enqueueOutbox(_ entry: OutboxEntry) {
        ensureOutboxLoaded()
        if !outboxQueue.contains(where: { $0.id == entry.id }) {
            outboxQueue.append(entry)
            persistOutbox()
        }
    }

    public func removeOutboxEntry(id: UUID) {
        ensureOutboxLoaded()
        let before = outboxQueue.count
        outboxQueue.removeAll { $0.id == id }
        if outboxQueue.count != before {
            persistOutbox()
        }
    }

    public func drainOutbox() -> [OutboxEntry] {
        ensureOutboxLoaded()
        let items = outboxQueue
        outboxQueue.removeAll()
        persistOutbox()
        return items
    }

    /// Clears persisted conversation summaries, per-host shards, paired host roster, projects,
    /// automations, and per-cascade step caches on explicit sign-out / disconnect.
    public func clearCachedProjections() {
        cachedSummaries.removeAll()
        cachedProjects.removeAll()
        cachedHostProjections.removeAll()
        hasLoadedHostProjectionsFromDisk = false
        cachedKnownHosts.removeAll()
        hasLoadedKnownHostsFromDisk = false
        cachedAutomations.removeAll()
        cachedStepsByCascade.removeAll()

        let fm = FileManager.default
        let fixedFiles = [
            "summaries_projection.json",
            "projects_projection.json",
            "hosts_projection.json",
            "automations_projection.json"
        ]
        for name in fixedFiles {
            try? fm.removeItem(at: storageDirectory.appendingPathComponent(name))
        }
        if let contents = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            for url in contents where url.lastPathComponent.hasPrefix("steps_") && url.pathExtension == "json" {
                try? fm.removeItem(at: url)
            }
        }
        if let hostFiles = try? fm.contentsOfDirectory(at: hostsDirectory, includingPropertiesForKeys: nil) {
            for url in hostFiles where url.pathExtension == "json" {
                try? fm.removeItem(at: url)
            }
        }
    }
}
