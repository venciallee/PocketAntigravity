import Foundation
import Observation

/// Active navigation destination in `AntigravityShellController` across all 13 UE screens.
public enum AntigravityNavigationRoute: Sendable, Equatable, Hashable {
    case tabRoot
    case projectDetail(String)
    case cascadeChat(String)
    case planReview
    case turnDiffReview
    case pairingSettings

    // Compatibility aliases
    public static var workspaceHome: AntigravityNavigationRoute { .tabRoot }
    public static var chatAndComposer: AntigravityNavigationRoute { .cascadeChat("cas-rate-limiter") }
    public static var artifactInspector: AntigravityNavigationRoute { .planReview }
    public static var turnDiffInspector: AntigravityNavigationRoute { .turnDiffReview }
    public static var pairingQR: AntigravityNavigationRoute { .pairingSettings }
}

/// Modal sheet presentation state in `AntigravityShellController`.
public enum AntigravityModalSheet: Identifiable, Sendable, Equatable {
    case displayOptions
    case contextMenuPreview(cascadeId: String)
    case createProject
    case addContext
    case modelAndMode
    case permissionGate(stepIndex: Int)
    case askQuestion(stepIndex: Int)
    case modelConfigPicker
    case fileMentionPicker
    case newCascadeSheet
    case conversationOverview
    case sideQuestion
    case swarmBoard(stepIndex: Int)
    case voiceMode
    case richArtifactViewer(artifactPath: String)
    case customizationsSettings

    public var id: String {
        switch self {
        case .displayOptions: return "display-options"
        case .contextMenuPreview(let cid): return "context-menu-\(cid)"
        case .createProject: return "create-project"
        case .addContext: return "add-context"
        case .modelAndMode: return "model-and-mode"
        case .permissionGate(let idx): return "permission-\(idx)"
        case .askQuestion(let idx): return "question-\(idx)"
        case .modelConfigPicker: return "model-picker"
        case .fileMentionPicker: return "file-picker"
        case .newCascadeSheet: return "new-cascade"
        case .conversationOverview: return "conversation-overview"
        case .sideQuestion: return "side-question"
        case .swarmBoard(let idx): return "swarm-board-\(idx)"
        case .voiceMode: return "voice-mode"
        case .richArtifactViewer(let path): return "rich-artifact-\(path)"
        case .customizationsSettings: return "customizations-settings"
        }
    }
}

/// Central `@Observable` state coordinator for `iOSAntigravity` (v2.0 UE Aligned).
/// Drives all 13 UE screens: Agents Home (`UE01`), Display Options (`UE02`), Long-Press & Pin (`UE03`),
/// Project Detail (`UE04`), Create New Project (`UE05`), Automations (`UE06`), Chat & Composer (`UE07`),
/// Add Context (`UE08`), Model & Mode (`UE09`), Structured Multi-Step Question (`UE10`),
/// Implementation Plan Review (`UE11`), Turn Diff Line Review (`UE12`), and Live Activity (`UE13`).
@MainActor
@Observable
public final class AntigravitySessionStore {

    // MARK: - Top-Level Navigation & Sheet State
    public var selectedTab: PrimaryTab = .agents
    public var activeRoute: AntigravityNavigationRoute = .tabRoot
    public var presentedSheet: AntigravityModalSheet? = nil

    public var currentRoute: AntigravityNavigationRoute {
        get { activeRoute }
        set {
            if newValue == .chatAndComposer {
                activeRoute = .cascadeChat(activeCascadeId)
            } else {
                activeRoute = newValue
            }
        }
    }

    // MARK: - Agents Home, Display Options & Search State (`UE01`, `UE02`, `UE03`)
    public var hostFilter: AgentHostFilter = .allHosts
    public var quickFilter: AgentsQuickFilter = .all
    public var displayOptions: AgentDisplayOptions = AgentDisplayOptions()
    public var isSortPopoverPresented: Bool = true
    public var searchQuery: String = ""
    public var selectedFilterCategory: SessionFilterCategory = .all
    public var selectedWorktreeFilter: String? = nil
    public var isRefreshingSummaries: Bool = false
    public var contextMenuTargetCascadeId: String = "cas-flaky-settlement"
    public var swipePreviewCascadeId: String = "cas-upgrade-go"

    // MARK: - Hosts, Projects & Create Project State (`UE01`, `UE04`, `UE05`)
    public var hosts: [RemoteHostInstance]
    public var activeHost: RemoteHostInstance
    public var projects: [ProjectWorkspace]
    public var selectedProjectId: String = "ledger-svc"
    public var selectedProjectTab: ProjectDetailTab = .active
    public var newProjectDraft: NewProjectDraft = NewProjectDraft()
    public var availableGitHubRepos: [GitHubRepoItem] = GitHubRepoItem.sampleCatalog
    public var workspaces: [WorkspaceInfo]
    public var selectedWorkspaceUri: String

    // MARK: - Conversations, Automations & Context State (`UE01`, `UE06`, `UE08`)
    public var summaries: [CascadeSummary]
    public var automations: [AutomationItem]
    public var automationPromptDraft: String = ""
    public var isLoadingAutomations: Bool = false
    public var isMutatingAutomation: Bool = false
    public var automationsErrorText: String? = nil
    public var isAutomationsAuthExpired: Bool = false
    public var contextCandidates: [ContextCandidateItem]
    public var contextSearchQuery: String = ""
    public var selectedContextCategoryFilter: ContextCategory? = nil

    // MARK: - Active Trajectory & Message List State (`UE07`)
    public var activeCascadeId: String
    public var stepsByCascadeId: [String: [CascadeStep]] = [:]
    public var expandedThinkingStepIds: Set<String> = []
    public var expandedEvidenceGroupIds: Set<String> = []
    public var expandedTerminalStepIds: Set<String> = []
    public var isAutoScrollPinnedToBottom: Bool = true
    public var unreadStreamingStepCount: Int = 0

    // MARK: - Composer, Model & Permission State (`UE07`, `UE08`, `UE09`)
    public static let defaultAutomationGuidedPrompt = "Guide me through creating an automated task"
    public var pendingDraftConversation: PendingDraftConversation? = nil
    public var composerWorkflowCommand: String? = nil
    public var composerDraftText: String = ""
    public var composerAttachments: [ComposerAttachmentChip] = []
    public var selectedModelConfig: CascadeModelConfig
    public var availableModels: [CascadeModelConfig]
    public var availableAgents: [String]
    public var localPermissionPreset: AgentPermissionPreset = .defaultPolicy
    public var remotePermissionPreset: AgentPermissionPreset = .turbo
    public var isSlashPopupDismissedManually: Bool = false

    private static let localPermissionDefaultsKey = "antigravity.ios.permissionPreset.local"
    private static let remotePermissionDefaultsKey = "antigravity.ios.permissionPreset.remote"

    /// `true` when the active conversation or selected project targets Antigravity Cloud / Remote Agents.
    public var isActiveSessionCloud: Bool {
        if let draft = pendingDraftConversation, activeCascadeId.isEmpty {
            return draft.isCloud
        }
        if activeSummary?.isCloud == true { return true }
        if activeCascadeId.hasPrefix("v1/") { return true }
        if let slug = activeSummary?.projectSlug,
           let proj = projects.first(where: { $0.id == slug || $0.name == slug }),
           proj.runtime == .cloud {
            return true
        }
        if selectedProject?.runtime == .cloud { return true }
        if selectedWorkspaceUri.hasPrefix("cloud://") { return true }
        return false
    }

    /// Active permission preset for the current session runtime (`Remote Permissions` vs local `Permissions`).
    public var activePermissionPreset: AgentPermissionPreset {
        get { isActiveSessionCloud ? remotePermissionPreset : localPermissionPreset }
        set { setActivePermissionPreset(newValue) }
    }

    public func setActivePermissionPreset(_ preset: AgentPermissionPreset, isRemoteOverride: Bool? = nil) {
        let isRemote = isRemoteOverride ?? isActiveSessionCloud
        if isRemote {
            remotePermissionPreset = preset
            if !isVerificationMode {
                UserDefaults.standard.set(preset.rawValue, forKey: Self.remotePermissionDefaultsKey)
            }
        } else {
            localPermissionPreset = preset
            if !isVerificationMode {
                UserDefaults.standard.set(preset.rawValue, forKey: Self.localPermissionDefaultsKey)
            }
        }
    }

    // MARK: - Structured Multi-Step Question State (`UE10`)
    public var questionSteps: [StructuredQuestionStepItem]
    public var activeQuestionStepIndex: Int = 1
    public var questionFreeformReplyDraft: String = ""

    // MARK: - Implementation Plan Review State (`UE11`)
    public var safeAutoAcceptEnabled: Bool
    public var activeTurnGrants: Set<String> = ["ReadOnlyWorkspace", "verification/*"]
    public var activeArtifacts: [ArtifactSnapshot]
    public var selectedArtifactPath: String = "/brain/implementation_plan.md"
    public var resolvedEmbedCache: [String: ResolvedEmbedResource] = [:]
    public var planChanges: [PlanProposedFileChange]
    public var planComments: [PlanInlineComment]

    // MARK: - Multi-Turn Line-Level Diff Review State (`UE12`)
    public var activeTurnDiffs: [FilePatchDiff]
    public var selectedDiffTurn: Int = 3
    public var selectedDiffFileIndex: Int = 0
    public var selectedDiffLineNumber: Int? = 29
    public var activeLineCommentDraft: String
    public var diffComments: [DiffLineComment] = []
    public var lastDispatchedInteraction: CascadeUserInteractionPayload? = nil

    // MARK: - Antigravity 2.0 (v2.33) State: Quota, Permissions, Overview, /btw, Voice, Git VCS, Customizations & Appearance
    public var usageQuota: ModelUsageQuota = ModelUsageQuota(
        geminiWeeklyRemaining: 0.86,
        geminiFiveHourRemaining: 0.94,
        partnerWeeklyRemaining: 0.72,
        partnerFiveHourRemaining: 0.81,
        aiCreditOveragesEnabled: false,
        planDisplayName: "Google AI Ultra"
    )
    public var conversationPermissionPresets: [String: AgentPermissionPreset] = [:]
    public var permissionRules: [PermissionRuleEntry] = [
        PermissionRuleEntry(list: .allow, action: .readFile, target: "workspace/**"),
        PermissionRuleEntry(list: .ask, action: .command, target: "git push*"),
        PermissionRuleEntry(list: .deny, action: .readFile, target: "~/.ssh/**")
    ]
    public var conversationOverview: ConversationOverviewSnapshot = ConversationOverviewSnapshot()
    public var sideQuestionThread: SideQuestionThread = SideQuestionThread()
    public var queuedMessages: [QueuedMessageItem] = []
    public var voiceModeState: VoiceModeState = VoiceModeState()
    public var customizations: CustomizationsCatalog = CustomizationsCatalog.defaultCatalog
    public var appearancePreferences: AppAppearancePreferences = AppAppearancePreferences()
    public var diffCompareMode: DiffCompareMode = .turn
    public var gitCommitDraft: GitCommitDraft = GitCommitDraft()
    public var lastCommitResult: GitCommitResult? = nil
    public var imageRegionComments: [ImageRegionComment] = []
    public var isScheduledFilterActive: Bool = false
    public var remoteSearchResults: [CascadeSummary] = []
    public var isSearchingAllConversations: Bool = false
    public var manuallyCancelledCascadeIds: Set<String> = []
    public var lastNotificationEvent: (id: String, title: String, body: String, cascadeId: String)? = nil

    // MARK: - Live Backend Connectivity & Auth State
    public var isVerificationMode: Bool = false
    public var isInitialSessionCheckComplete: Bool = false
    public var hasPairedBackend: Bool = false
    public var isLiveBackendConnected: Bool = false
    public var isConnectingToBackend: Bool = false
    public var connectionStatusText: String = "Not Connected"
    public var connectionErrorText: String? = nil
    public var lastPingLatencyMs: Int? = nil
    public var availableRelayInstances: [RelayInstanceInfo] = []
    public var isRefreshingRelayHosts: Bool = false
    public var refreshingHostScopeKeys: Set<String> = []
    public var activeAuthUser: String = "0"
    public var lastScannedRelayURL: String = ""
    public var isLoadingSteps: Bool = false
    public var stepLoadErrorText: String? = nil
    public var cloudAgentWarmingUp: Bool = false
    public var connectionLifecyclePhase: ConnectionLifecyclePhase = .disconnected
    public var isDeviceNetworkReachable: Bool = true
    public var isNetworkingSuspended: Bool = false
    public var reconnectAttemptCount: Int = 0
    public var nextReconnectAt: Date? = nil
    public var pendingOutboxCount: Int = 0

    // MARK: - Dependencies
    private let projectionStore: LocalProjectionStore
    private let networkPathObserver = NetworkPathObserver()
    private var rpcClient: AntigravityRPCClient?
    private var localSummaryStreamTasks: [String: Task<Void, Never>] = [:]
    private var cloudSummaryStreamTask: Task<Void, Never>? = nil
    private var hasReceivedLocalStreamEvent: Bool = false
    private var hasReceivedCloudStreamEvent: Bool = false
    private var summaryPollingTask: Task<Void, Never>? = nil
    private var stepPollingTask: Task<Void, Never>? = nil
    private var inFlightHostRefreshTasks: [String: Task<Bool, Never>] = [:]
    private var inFlightRelayHostsProbeTask: Task<Void, Never>? = nil
    private var locallyViewedAtByCascadeId: [String: Date] = [:]
    private var optimisticActiveUntilByCascadeId: [String: Date] = [:]
    private var consecutiveSyncFailures: Int = 0
    private var backgroundPollCounter: Int = 0
    private var lastAutomationsSyncAt: Date? = nil
    private var syncedConfigCascadeIds: Set<String> = []
    internal var locallyCreatedEmptyCascadeIds: Set<String> = []
    private var stepSyncGeneration: UInt64 = 0
    private var lastNetworkStatus: NetworkReachabilityStatus? = nil
    private var isNetworkExpensiveOrConstrained: Bool = false
    private var lastBackendActivityAt: Date = .distantPast
    private var lastFullSyncAt: Date = .distantPast
    private var lastStreamReopenAttemptAt: Date = .distantPast
    private var isReplayingOutbox: Bool = false
    internal var lowPowerModeOverrideForTesting: Bool? = nil
    internal var hostRefreshExecutorOverrideForTesting: (@Sendable (AgentHostFilter) async throws -> ScopedWorkspaceSyncResult)? = nil
    internal var coalescedHostRefreshJoinCountForTesting: Int = 0

    private var summaryStreamGeneration: UInt64 = 0

    private var isSummaryStreamHealthy: Bool {
        if activeHost.channel == .cloudRelay {
            return (!localSummaryStreamTasks.isEmpty && hasReceivedLocalStreamEvent)
                || (cloudSummaryStreamTask != nil && hasReceivedCloudStreamEvent)
        }
        return !localSummaryStreamTasks.isEmpty && hasReceivedLocalStreamEvent
    }

    private func cancelAllSummaryStreams() {
        summaryStreamGeneration &+= 1
        for task in localSummaryStreamTasks.values {
            task.cancel()
        }
        localSummaryStreamTasks.removeAll()
        cloudSummaryStreamTask?.cancel()
        cloudSummaryStreamTask = nil
        hasReceivedLocalStreamEvent = false
        hasReceivedCloudStreamEvent = false
    }

    private func cancelAllInFlightHostRefreshes() {
        for task in inFlightHostRefreshTasks.values {
            task.cancel()
        }
        inFlightHostRefreshTasks.removeAll()
        refreshingHostScopeKeys.removeAll()
        isRefreshingSummaries = false
        inFlightRelayHostsProbeTask?.cancel()
        inFlightRelayHostsProbeTask = nil
        isRefreshingRelayHosts = false
    }

    public var isLowPowerModeEnabled: Bool {
        if let override = lowPowerModeOverrideForTesting {
            return override
        }
        #if os(iOS) || os(macOS)
        return ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        return false
        #endif
    }

    public init(
        hosts: [RemoteHostInstance] = [],
        activeHost: RemoteHostInstance,
        projects: [ProjectWorkspace] = [],
        workspaces: [WorkspaceInfo] = [],
        selectedWorkspaceUri: String = "",
        summaries: [CascadeSummary] = [],
        automations: [AutomationItem] = [],
        contextCandidates: [ContextCandidateItem] = [],
        questionSteps: [StructuredQuestionStepItem] = [],
        activeQuestionStepIndex: Int = 1,
        planChanges: [PlanProposedFileChange] = [],
        planComments: [PlanInlineComment] = [],
        activeCascadeId: String = "",
        stepsByCascadeId: [String: [CascadeStep]] = [:],
        activeSteps: [CascadeStep] = [],
        activeArtifacts: [ArtifactSnapshot] = [],
        activeTurnDiffs: [FilePatchDiff] = [],
        selectedDiffTurn: Int = 3,
        selectedDiffFileIndex: Int = 0,
        activeLineCommentDraft: String = "",
        selectedModelConfig: CascadeModelConfig = CascadeModelConfig.catalog[0],
        availableModels: [CascadeModelConfig] = CascadeModelConfig.catalog,
        availableAgents: [String] = CascadeModelConfig.availableAgents,
        safeAutoAcceptEnabled: Bool = true,
        projectionStore: LocalProjectionStore = LocalProjectionStore()
    ) {
        self.hosts = hosts.isEmpty ? [activeHost] : hosts
        self.activeHost = activeHost
        self.projects = projects
        self.workspaces = workspaces
        self.selectedWorkspaceUri = selectedWorkspaceUri
        self.summaries = summaries
        self.automations = automations
        self.contextCandidates = contextCandidates
        self.questionSteps = questionSteps
        self.activeQuestionStepIndex = activeQuestionStepIndex
        self.planChanges = planChanges
        self.planComments = planComments
        self.activeCascadeId = activeCascadeId
        var mergedSteps = stepsByCascadeId
        if !activeCascadeId.isEmpty && mergedSteps[activeCascadeId] == nil && !activeSteps.isEmpty {
            mergedSteps[activeCascadeId] = activeSteps
        }
        self.stepsByCascadeId = mergedSteps
        self.activeArtifacts = activeArtifacts
        self.activeTurnDiffs = activeTurnDiffs
        self.selectedDiffTurn = selectedDiffTurn
        self.selectedDiffFileIndex = selectedDiffFileIndex
        self.activeLineCommentDraft = activeLineCommentDraft
        self.selectedModelConfig = selectedModelConfig
        self.availableModels = availableModels
        self.availableAgents = availableAgents
        self.safeAutoAcceptEnabled = safeAutoAcceptEnabled
        self.projectionStore = projectionStore
        self.rpcClient = AntigravityRPCClient(
            host: activeHost,
            csrfToken: "csrf-antigravity-ios-session-token"
        )
        self.harvestEmbedResources(from: activeArtifacts)
        for (_, stepList) in mergedSteps {
            self.harvestEmbedResources(from: stepList)
        }
    }

    // MARK: - Computed Properties for Agents Home & Project Hub (`UE01`, `UE02`, `UE04`)

    public var currentWorkspace: WorkspaceInfo? {
        workspaces.first(where: { $0.workspaceUri == selectedWorkspaceUri }) ?? workspaces.first
    }

    public var selectedProject: ProjectWorkspace? {
        projects.first(where: { $0.id == selectedProjectId }) ?? projects.first
    }

    public var availableWorktrees: [String] {
        selectedProject?.worktrees ?? currentWorkspace?.worktrees ?? ["main"]
    }

    public var runningCount: Int {
        summaries.filter { !$0.isArchived && ($0.status == .inProgress || $0.status == .pending) }.count
    }

    public var runningCascadeCount: Int { runningCount }

    public var needsYouCount: Int {
        summaries.filter { !$0.isArchived && ($0.status == .waiting || $0.status == .blocked) }.count
    }

    public var waitingApprovalCount: Int { needsYouCount }

    public var unreadCount: Int {
        summaries.filter { !$0.isArchived && $0.isUnread }.count
    }

    /// Deduplicated list of paired local Mac/PC hosts (excluding Antigravity Cloud and placeholder unpaired entries).
    public var pairedLocalHosts: [RemoteHostInstance] {
        var seen = Set<String>()
        var result: [RemoteHostInstance] = []
        for host in hosts where host.instanceId != "unpaired" && host.hostname.lowercased() != "cloud" {
            if seen.insert(host.instanceId).inserted {
                result.append(host)
            }
        }
        if result.isEmpty && hasPairedBackend && activeHost.instanceId != "unpaired" {
            result.append(activeHost)
        }
        return result
    }

    /// Returns real per-host online reachability for a specific local Mac/PC instance.
    public func isLocalHostOnline(instanceId: String?, hostname: String?) -> Bool {
        guard isDeviceNetworkReachable && isLiveBackendConnected else { return false }
        if let id = instanceId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            if let inst = availableRelayInstances.first(where: { $0.uuid == id }) {
                return inst.status.isReachable
            }
            if let host = hosts.first(where: { $0.instanceId == id }) {
                return host.isOnline
            }
        }
        if let name = hostname?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            if let inst = availableRelayInstances.first(where: { $0.name == name }) {
                return inst.status.isReachable
            }
            if let host = hosts.first(where: { $0.hostname == name }) {
                return host.isOnline
            }
        }
        return activeHost.isOnline
    }

    /// Returns real online reachability for a project's owning runtime/host.
    public func isProjectHostOnline(_ project: ProjectWorkspace) -> Bool {
        if project.runtime == .cloud {
            return isDeviceNetworkReachable
        }
        guard hasPairedBackend else { return true }
        return isLocalHostOnline(instanceId: project.originInstanceUuid, hostname: project.hostName)
    }

    /// Returns real online reachability for a conversation summary's owning runtime/host.
    public func isSummaryHostOnline(_ summary: CascadeSummary?) -> Bool {
        guard let summary else {
            return isDeviceNetworkReachable && isLiveBackendConnected && activeHost.isOnline
        }
        if summary.isCloud {
            return isDeviceNetworkReachable
        }
        guard hasPairedBackend else { return true }
        return isLocalHostOnline(instanceId: summary.originInstanceUuid, hostname: summary.originHostName)
    }

    /// Returns `true` when at least one paired local Mac/PC host is currently online.
    public var anyPairedLocalHostOnline: Bool {
        guard isDeviceNetworkReachable && isLiveBackendConnected else { return false }
        let localHosts = pairedLocalHosts
        if !localHosts.isEmpty {
            return localHosts.contains(where: {
                isLocalHostOnline(instanceId: $0.instanceId, hostname: $0.hostname)
            })
        }
        return activeHost.isOnline
    }

    /// Strict host filter check for conversation summaries so projects/chats from other Macs never leak across hosts.
    public func summaryMatchesHostFilter(_ s: CascadeSummary, filter: AgentHostFilter? = nil) -> Bool {
        switch filter ?? hostFilter {
        case .allHosts:
            return true
        case .antigravityCloud:
            return s.isCloud
        case .localHost(let id, let name):
            guard !s.isCloud else { return false }
            if pairedLocalHosts.count <= 1 {
                return true
            }
            let liveName = resolvedHostName(forInstanceUuid: id, fallback: name)
            if let originUuid = s.originInstanceUuid, !originUuid.isEmpty {
                return originUuid == id || s.originHostName == name || s.originHostName == liveName
            }
            if let originHost = s.originHostName, !originHost.isEmpty {
                return originHost == name || originHost == liveName
            }
            return activeHost.instanceId == id
        }
    }

    /// Strict host filter check for project sections so projects from other Macs never leak across hosts.
    public func projectMatchesHostFilter(_ proj: ProjectWorkspace, filter: AgentHostFilter? = nil) -> Bool {
        switch filter ?? hostFilter {
        case .allHosts:
            return true
        case .antigravityCloud:
            return proj.runtime == .cloud
        case .localHost(let id, let name):
            guard proj.runtime != .cloud else { return false }
            if pairedLocalHosts.count <= 1 {
                return true
            }
            let liveName = resolvedHostName(forInstanceUuid: id, fallback: name)
            if let originUuid = proj.originInstanceUuid, !originUuid.isEmpty {
                return originUuid == id || proj.hostName == name || proj.hostName == liveName
            }
            if !proj.hostName.isEmpty {
                return proj.hostName == name || proj.hostName == liveName
            }
            return activeHost.instanceId == id
        }
    }

    public var hostScopedRunningCount: Int {
        summaries.filter {
            !$0.isArchived && summaryMatchesHostFilter($0) && ($0.status == .inProgress || $0.status == .pending)
        }.count
    }

    public var hostScopedNeedsYouCount: Int {
        summaries.filter {
            !$0.isArchived && summaryMatchesHostFilter($0) && ($0.status == .waiting || $0.status == .blocked)
        }.count
    }

    public var hostScopedUnreadCount: Int {
        summaries.filter {
            !$0.isArchived && summaryMatchesHostFilter($0) && $0.isUnread
        }.count
    }

    /// Canonicalizes a host filter against known Relay instances / paired hosts so Home and Settings
    /// always coalesce requests for the same physical device onto the exact same key.
    internal func canonicalHostFilterForCoalescing(_ target: AgentHostFilter) -> AgentHostFilter {
        switch target {
        case .allHosts:
            return .allHosts
        case .antigravityCloud:
            return .antigravityCloud
        case .localHost(let id, let name):
            let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let inst = availableRelayInstances.first(where: {
                (!trimmedId.isEmpty && $0.uuid == trimmedId)
                    || (!trimmedName.isEmpty && $0.name == trimmedName)
            }) {
                return .localHost(id: inst.uuid, name: inst.name)
            }
            if let host = hosts.first(where: {
                (!trimmedId.isEmpty && $0.instanceId == trimmedId)
                    || (!trimmedName.isEmpty && $0.hostname == trimmedName)
            }) {
                return .localHost(id: host.instanceId, name: host.hostname)
            }
            return .localHost(id: trimmedId, name: trimmedName)
        }
    }

    internal func coalescingScopeKey(for target: AgentHostFilter) -> String {
        let canonical = canonicalHostFilterForCoalescing(target)
        switch canonical {
        case .allHosts:
            return AgentHostFilter.allHosts.id
        case .antigravityCloud:
            return AgentHostFilter.antigravityCloud.id
        case .localHost(let id, let name):
            if !id.isEmpty {
                return "host-\(id)"
            }
            return "host-name-\(name)"
        }
    }

    /// `true` while a live refresh is currently in flight for the active host filter (or all hosts).
    public var isRefreshingActiveHostFilter: Bool {
        let activeKey = coalescingScopeKey(for: hostFilter)
        return refreshingHostScopeKeys.contains(activeKey)
            || refreshingHostScopeKeys.contains(AgentHostFilter.allHosts.id)
    }

    /// `true` while a live refresh is currently in flight for the specified local host instance.
    public func isRefreshingHost(instanceId: String, hostname: String? = nil) -> Bool {
        let key = coalescingScopeKey(for: .localHost(id: instanceId, name: hostname ?? ""))
        return refreshingHostScopeKeys.contains(key)
    }

    /// Updates `hostFilter` (persisted across tab & chat navigation), aligns `activeHost` + Relay target
    /// when selecting an online local host, and triggers a coalesced per-device refresh so cached
    /// conversations display immediately while fresh data loads without duplicate in-flight requests.
    public func selectHostFilter(_ target: AgentHostFilter, triggerRefresh: Bool = true) {
        hostFilter = target
        if case let .localHost(id, name) = target,
           let matchedHost = hosts.first(where: { $0.instanceId == id || $0.hostname == name }),
           matchedHost.instanceId != activeHost.instanceId,
           isLocalHostOnline(instanceId: matchedHost.instanceId, hostname: matchedHost.hostname) {
            activeHost = matchedHost
            if isLiveBackendConnected {
                connectionStatusText = "Connected · \(matchedHost.hostname)"
            }
            let clientRef = rpcClient
            let targetUuid = matchedHost.instanceId
            let targetName = matchedHost.hostname
            Task {
                await clientRef?.setPreferredRelayInstance(uuid: targetUuid, name: targetName)
            }
        }
        if triggerRefresh {
            _ = scheduleCoalescedHostRefresh(
                for: target,
                forceFullSync: true,
                includeAutomations: false,
                requirePairedBackend: true
            )
        }
    }

    /// Synchronously registers (or joins an existing) in-flight refresh task for `target` on `@MainActor`,
    /// guaranteeing that rapid/repeated device switches targeting the same host coalesce into 1 request.
    @discardableResult
    internal func scheduleCoalescedHostRefresh(
        for target: AgentHostFilter,
        forceFullSync: Bool = true,
        includeAutomations: Bool = false,
        requirePairedBackend: Bool = true,
        skipRelayMetadataProbe: Bool = false
    ) -> Task<Bool, Never>? {
        guard !isNetworkingSuspended else { return nil }
        if requirePairedBackend {
            guard !isVerificationMode,
                  isDeviceNetworkReachable,
                  (hasPairedBackend || isLiveBackendConnected || hostRefreshExecutorOverrideForTesting != nil) else {
                return nil
            }
        }
        guard rpcClient != nil || hostRefreshExecutorOverrideForTesting != nil else {
            return nil
        }

        let canonicalTarget = canonicalHostFilterForCoalescing(target)
        let key = coalescingScopeKey(for: canonicalTarget)

        if let existingTask = inFlightHostRefreshTasks[key] {
            coalescedHostRefreshJoinCountForTesting += 1
            return existingTask
        }

        refreshingHostScopeKeys.insert(key)
        isRefreshingSummaries = !refreshingHostScopeKeys.isEmpty

        let task = Task<Bool, Never> { @MainActor [weak self] in
            guard let self else { return false }
            defer {
                self.inFlightHostRefreshTasks.removeValue(forKey: key)
                self.refreshingHostScopeKeys.remove(key)
                self.isRefreshingSummaries = !self.refreshingHostScopeKeys.isEmpty
            }
            return await self.executeScopedHostRefresh(
                target: canonicalTarget,
                forceFullSync: forceFullSync,
                includeAutomations: includeAutomations,
                skipRelayMetadataProbe: skipRelayMetadataProbe
            )
        }

        inFlightHostRefreshTasks[key] = task
        return task
    }

    /// Refreshes conversations & workspaces for `target`, coalescing concurrent/repeated requests
    /// targeting the same device or scope onto a single in-flight request while preserving cached
    /// conversations for other (including offline) hosts.
    @discardableResult
    public func refreshConversationsForHostFilter(
        _ target: AgentHostFilter,
        forceFullSync: Bool = true,
        includeAutomations: Bool = false
    ) async -> Bool {
        guard let task = scheduleCoalescedHostRefresh(
            for: target,
            forceFullSync: forceFullSync,
            includeAutomations: includeAutomations,
            requirePairedBackend: true
        ) else {
            return false
        }
        return await task.value
    }

    /// Switches the active Cloud Relay device from Settings (`AVAILABLE HOSTS`) using the shared
    /// per-device coalescer without tearing down `stepsByCascadeId` or wiping offline host caches.
    @discardableResult
    public func switchToRelayHost(
        instanceUuid: String,
        hostName: String
    ) async -> Bool {
        let targetFilter = AgentHostFilter.localHost(id: instanceUuid, name: hostName)

        if (hasPairedBackend || isLiveBackendConnected)
            && activeHost.channel == .cloudRelay
            && (rpcClient != nil || hostRefreshExecutorOverrideForTesting != nil) {
            connectionErrorText = nil
            let reachable = await refreshConversationsForHostFilter(targetFilter, forceFullSync: true)
            guard reachable else {
                connectionErrorText = "\(hostName) is currently offline or unreachable."
                return false
            }

            let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
            let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
            let matchedInst = availableRelayInstances.first(where: { $0.uuid == instanceUuid || $0.name == hostName })
            let finalUuid = matchedInst?.uuid ?? instanceUuid
            let finalName = matchedInst?.name ?? hostName
            let finalVersion = matchedInst?.version ?? activeHost.version
            let finalURL = URL(string: "\(originPrefix)/r/\(finalUuid)") ?? activeHost.endpointURL

            let updatedHost = RemoteHostInstance(
                instanceId: finalUuid,
                hostname: finalName,
                version: finalVersion,
                channel: .cloudRelay,
                endpointURL: finalURL,
                isOnline: true,
                latencyMs: lastPingLatencyMs ?? activeHost.latencyMs
            )
            activeHost = updatedHost
            if let idx = hosts.firstIndex(where: { $0.instanceId == finalUuid }) {
                hosts[idx] = updatedHost
            } else {
                hosts.insert(updatedHost, at: 0)
            }
            hostFilter = .localHost(id: finalUuid, name: finalName)
            isLiveBackendConnected = true
            connectionErrorText = nil
            if let latency = lastPingLatencyMs {
                connectionStatusText = "Connected · \(finalName) · \(latency)ms"
            } else {
                connectionStatusText = "Connected · \(finalName)"
            }

            if hostRefreshExecutorOverrideForTesting == nil {
                if let client = rpcClient {
                    await client.setPreferredRelayInstance(uuid: finalUuid, name: finalName)
                }
                if let cached = await loadSavedSessionCookie() {
                    await KeychainStore.shared.saveCredentials(
                        SavedBackendCredentials(
                            endpointURLString: finalURL.absoluteString,
                            channel: .cloudRelay,
                            hostname: finalName,
                            sessionCookie: cached.cookie,
                            authUser: activeAuthUser,
                            resolvedInstanceUuid: finalUuid
                        )
                    )
                }
                ensureSummaryEnvelopeStreamRunning()
            }
            return true
        }

        if let cached = await loadSavedSessionCookie() {
            return await connectCloudRelay(
                relayURLString: "https://antigravity.google.com/r/\(instanceUuid)",
                sessionCookie: cached.cookie,
                authUser: activeAuthUser,
                resolvedInstanceUuid: instanceUuid,
                hostName: hostName,
                focusHostFilterOnConnected: true,
                strictTargetSelection: true
            )
        }
        return false
    }

    /// Filtered and sorted conversation summaries driven by `quickFilter`, `displayOptions`, and `searchQuery`.
    public var filteredSummaries: [CascadeSummary] {
        summaries
            .filter { summary in
                if displayOptions.archivedOnly {
                    if !summary.isArchived { return false }
                } else {
                    if summary.isArchived { return false }
                }
                if let branch = selectedWorktreeFilter, !branch.isEmpty, summary.branchName != branch {
                    return false
                }
                switch quickFilter {
                case .all:
                    break
                case .running:
                    if summary.status != .inProgress && summary.status != .pending { return false }
                case .needsYou:
                    if summary.status != .waiting && summary.status != .blocked { return false }
                case .unread:
                    if !summary.isUnread { return false }
                }
                switch selectedFilterCategory {
                case .all:
                    break
                case .waitingApproval:
                    if summary.status != .waiting && summary.status != .blocked { return false }
                case .running:
                    if summary.status != .inProgress && summary.status != .pending { return false }
                case .pinned:
                    if !summary.isPinned { return false }
                case .done:
                    if summary.status != .done { return false }
                }
                let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !q.isEmpty {
                    let matchesTitle = summary.title.lowercased().contains(q)
                    let matchesProject = summary.projectSlug.lowercased().contains(q)
                    let matchesSubtitle = summary.statusSubtitle.lowercased().contains(q)
                    let matchesBranch = summary.branchName.lowercased().contains(q)
                    let matchesPreview = (summary.lastMessagePreview ?? "").lowercased().contains(q)
                    return matchesTitle || matchesProject || matchesSubtitle || matchesBranch || matchesPreview
                }
                return true
            }
            .sorted { lhs, rhs in
                switch displayOptions.sortBy {
                case .title:
                    let cmp = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    return displayOptions.newestFirst ? (cmp == .orderedAscending) : (cmp == .orderedDescending)
                case .lastUpdated, .dateCreated:
                    return displayOptions.newestFirst ? (lhs.updatedAt > rhs.updatedAt) : (lhs.updatedAt < rhs.updatedAt)
                }
            }
    }

    public var pinnedSummaries: [CascadeSummary] {
        filteredSummaries.filter { $0.isPinned }
    }

    public var unpinnedSummaries: [CascadeSummary] {
        filteredSummaries.filter { !$0.isPinned }
    }

    public func unpinnedSummaries(forProject projectSlug: String) -> [CascadeSummary] {
        unpinnedSummaries.filter { $0.projectSlug == projectSlug }
    }

    public func activeSummaries(forProject projectSlug: String) -> [CascadeSummary] {
        summaries.filter { $0.projectSlug == projectSlug && !$0.isArchived }
    }

    public func archivedSummaries(forProject projectSlug: String) -> [CascadeSummary] {
        summaries.filter { $0.projectSlug == projectSlug && $0.isArchived }
    }

    public func totalConversationCount(forProject projectSlug: String) -> Int {
        summaries.filter { $0.projectSlug == projectSlug }.count
    }

    public func automations(forProject projectSlug: String) -> [AutomationItem] {
        automations.filter { $0.projectSlug == projectSlug }
    }

    public var filteredGitHubRepos: [GitHubRepoItem] {
        let q = newProjectDraft.repoSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return availableGitHubRepos }
        return availableGitHubRepos.filter {
            $0.fullName.lowercased().contains(q) || $0.visibilityLabel.lowercased().contains(q)
        }
    }

    // MARK: - Computed Properties for Automations & Context (`UE06`, `UE08`)

    public var scheduledAutomations: [AutomationItem] {
        automations.filter { $0.section == .scheduled }
    }

    public var alwaysOnAutomations: [AutomationItem] {
        automations.filter { $0.section == .alwaysOn }
    }

    public var pausedAutomations: [AutomationItem] {
        automations.filter { $0.section == .paused }
    }

    public var filteredContextCandidates: [ContextCandidateItem] {
        let q = contextSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return contextCandidates.filter { item in
            if let cat = selectedContextCategoryFilter, item.category != cat {
                return false
            }
            if !q.isEmpty {
                return item.title.lowercased().contains(q) || item.subtitle.lowercased().contains(q)
            }
            return true
        }
    }

    public var selectedContextCount: Int {
        contextCandidates.filter { $0.isSelected }.count
    }

    // MARK: - Computed Properties for Active Chat, Question, Plan & Diff (`UE07`, `UE10`, `UE11`, `UE12`)

    public var activeSummary: CascadeSummary? {
        summaries.first(where: { $0.cascadeId == activeCascadeId })
    }

    public var contextMenuTargetSummary: CascadeSummary? {
        summaries.first(where: { $0.cascadeId == contextMenuTargetCascadeId }) ?? summaries.first
    }

    public var activeSteps: [CascadeStep] {
        get { stepsByCascadeId[activeCascadeId] ?? [] }
        set { stepsByCascadeId[activeCascadeId] = newValue }
    }

    public var displayItems: [CascadeDisplayItem] {
        CascadeDisplayItem.buildDisplayItems(from: activeSteps)
    }

    public var activeTaskBoundary: TaskBoundaryPayload? {
        activeSteps.last(where: { $0.type == .taskBoundary })?.taskBoundary
    }

    public var pendingWaitingStep: CascadeStep? {
        activeSteps.last(where: { $0.isWaitingForUser })
    }

    public func waitingStep(at stepIndex: Int?) -> CascadeStep? {
        if let stepIndex,
           let matched = activeSteps.first(where: { $0.stepIndex == stepIndex && $0.isWaitingForUser }) {
            return matched
        }
        return pendingWaitingStep
    }

    public var isCascadeStreaming: Bool {
        if let summary = activeSummary, summary.status == .inProgress || summary.status == .pending {
            return true
        }
        return activeSteps.contains(where: { $0.status == .inProgress || $0.status == .pending })
    }

    public var currentQuestionStep: StructuredQuestionStepItem? {
        guard questionSteps.indices.contains(activeQuestionStepIndex) else { return questionSteps.first }
        return questionSteps[activeQuestionStepIndex]
    }

    public var currentDiffFile: FilePatchDiff? {
        guard !activeTurnDiffs.isEmpty else { return nil }
        let clamped = min(max(0, selectedDiffFileIndex), activeTurnDiffs.count - 1)
        return activeTurnDiffs[clamped]
    }

    public var selectedDiffFilePath: String {
        get { currentDiffFile?.filePath ?? "middleware/ratelimit.go" }
        set {
            if let idx = activeTurnDiffs.firstIndex(where: { $0.filePath == newValue }) {
                selectedDiffFileIndex = idx
            }
        }
    }

    public var totalDiffAdditions: Int {
        let sum = activeTurnDiffs.reduce(0) { $0 + $1.additions }
        if sum > 0 { return sum }
        let stepSum = activeSteps.compactMap(\.codeAction).reduce(0) { $0 + $1.additions }
        if stepSum > 0 { return stepSum }
        if isLiveBackendConnected {
            return activeSummary?.totalAdditions ?? 0
        }
        return activeSummary?.totalAdditions ?? 128
    }

    public var totalDiffDeletions: Int {
        let sum = activeTurnDiffs.reduce(0) { $0 + $1.deletions }
        if sum > 0 { return sum }
        let stepSum = activeSteps.compactMap(\.codeAction).reduce(0) { $0 + $1.deletions }
        if stepSum > 0 { return stepSum }
        if isLiveBackendConnected {
            return activeSummary?.totalDeletions ?? 0
        }
        return activeSummary?.totalDeletions ?? 14
    }

    // MARK: - Composer Suggestions (`UE07`)

    public var activeSlashCommandSuggestions: [SlashCommandItem] {
        guard !isSlashPopupDismissedManually else { return [] }
        let trimmed = composerDraftText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        let token = String(trimmed.split(separator: " ").first ?? Substring(trimmed)).lowercased()
        if token == "/" {
            return SlashCommandItem.allCommands
        }
        return SlashCommandItem.allCommands.filter {
            $0.command.lowercased().hasPrefix(token) || $0.title.lowercased().contains(token.dropFirst())
        }
    }

    public var activeFileMentionSuggestions: [String] {
        guard let lastWord = composerDraftText.split(separator: " ").last,
              lastWord.hasPrefix("@") else {
            return []
        }
        let query = String(lastWord.dropFirst()).lowercased()
        let files = currentWorkspace?.indexedFiles ?? [
            "internal/middleware/ratelimit.go",
            "internal/router/transfers.go",
            "internal/settlement/batch.go",
            "internal/settlement/settlement_test.go",
            "load/transfers.txt"
        ]
        if query.isEmpty { return Array(files.prefix(5)) }
        return files.filter { $0.lowercased().contains(query) }
    }

    public var canSendCurrentDraft: Bool {
        !composerDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !composerAttachments.isEmpty
            || !(composerWorkflowCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    // MARK: - Live Backend Login, Pairing & Streaming Actions

    private static let esddFixtureProjectIds: Set<String> = ["ledger-svc", "web-console"]
    private static let esddFixtureCascadeIds: Set<String> = [
        "cas-rate-limiter",
        "cas-release-checklist",
        "cas-flaky-settlement",
        "cas-upgrade-go",
        "cas-idempotency-payouts",
        "cas-pgx-v5-migration",
        "cas-audit-csp-headers",
        "cas-audit-log-admin"
    ]
    private static let esddFixtureAutomationIds: Set<String> = [
        "auto-nightly-audit",
        "auto-weekly-flaky",
        "auto-pr-triage",
        "auto-bundle-size"
    ]

    /// Computes the canonical shard key (`"cloud"` or `"host:<uuid|hostname>"`) for per-host disk caching.
    internal static func projectionHostKey(
        isCloud: Bool,
        instanceId: String?,
        hostname: String?,
        fallbackHostId: String,
        fallbackHostName: String
    ) -> String {
        if isCloud {
            return "cloud"
        }
        if let uuid = instanceId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uuid.isEmpty, uuid != "unpaired" {
            return "host:\(uuid)"
        }
        if let name = hostname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "host:\(name)"
        }
        let trimmedFallbackId = fallbackHostId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFallbackId.isEmpty && trimmedFallbackId != "unpaired" {
            return "host:\(trimmedFallbackId)"
        }
        let trimmedFallbackName = fallbackHostName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFallbackName.isEmpty {
            return "host:\(trimmedFallbackName)"
        }
        return "host:default"
    }

    /// Persists per-host sharded projections (`hosts/host_<key>.json`), paired host roster (`hosts_projection.json`),
    /// and backward-compatible global projections. When `refreshedHostKeys` is provided, only those refreshed shards
    /// are rewritten on disk so offline hosts' cached shards are never overwritten or touched.
    internal func persistHostProjections(refreshedHostKeys: Set<String>? = nil) async {
        let nonFixtureSummaries = summaries.filter { !Self.esddFixtureCascadeIds.contains($0.cascadeId) }
        let nonFixtureProjects = projects.filter { !Self.esddFixtureProjectIds.contains($0.id) }
        let fallbackId = activeHost.instanceId
        let fallbackName = activeHost.hostname

        var summariesByKey: [String: [CascadeSummary]] = [:]
        var projectsByKey: [String: [ProjectWorkspace]] = [:]
        var metaByKey: [String: (instanceId: String?, hostname: String, isCloud: Bool)] = [:]

        for s in nonFixtureSummaries {
            let key = Self.projectionHostKey(
                isCloud: s.isCloud,
                instanceId: s.originInstanceUuid,
                hostname: s.originHostName,
                fallbackHostId: fallbackId,
                fallbackHostName: fallbackName
            )
            summariesByKey[key, default: []].append(s)
            if metaByKey[key] == nil {
                metaByKey[key] = s.isCloud
                    ? (nil, "Antigravity", true)
                    : (s.originInstanceUuid, s.originHostName ?? fallbackName, false)
            }
        }

        for p in nonFixtureProjects {
            let isCloud = (p.runtime == .cloud)
            let key = Self.projectionHostKey(
                isCloud: isCloud,
                instanceId: p.originInstanceUuid,
                hostname: p.hostName,
                fallbackHostId: fallbackId,
                fallbackHostName: fallbackName
            )
            projectsByKey[key, default: []].append(p)
            if metaByKey[key] == nil {
                metaByKey[key] = isCloud
                    ? (nil, "Antigravity", true)
                    : (p.originInstanceUuid, p.hostName.isEmpty ? fallbackName : p.hostName, false)
            }
        }

        let keysToWrite: Set<String> = {
            if let refreshedHostKeys, !refreshedHostKeys.isEmpty {
                return refreshedHostKeys
            }
            return Set(summariesByKey.keys).union(projectsByKey.keys)
        }()

        let now = Date()
        var shardsToSave: [HostProjectionSnapshot] = []
        for key in keysToWrite {
            let isCloud = (key == "cloud")
            let meta: (instanceId: String?, hostname: String, isCloud: Bool) = {
                if let existing = metaByKey[key] {
                    return existing
                }
                if isCloud {
                    return (nil, "Antigravity", true)
                }
                let rawId = key.hasPrefix("host:") ? String(key.dropFirst("host:".count)) : key
                let matchedHost = hosts.first(where: { $0.instanceId == rawId || $0.hostname == rawId })
                return (matchedHost?.instanceId ?? rawId, matchedHost?.hostname ?? rawId, false)
            }()
            shardsToSave.append(
                HostProjectionSnapshot(
                    hostKey: key,
                    instanceId: meta.instanceId,
                    hostname: meta.hostname,
                    isCloud: meta.isCloud,
                    summaries: summariesByKey[key] ?? [],
                    projects: projectsByKey[key] ?? [],
                    updatedAt: now
                )
            )
        }

        let localHostsSnapshot = pairedLocalHosts
        let projectsSnapshot = nonFixtureProjects
        let summariesSnapshot = nonFixtureSummaries
        let storeRef = projectionStore
        await storeRef.saveHostProjections(shardsToSave)
        if !localHostsSnapshot.isEmpty {
            await storeRef.saveKnownHosts(localHostsSnapshot)
        }
        await storeRef.saveProjects(projectsSnapshot)
        await storeRef.saveProjectedSummaries(summariesSnapshot)
    }

    /// Instantly hydrates cached per-host conversations, projects, and paired host roster from disk (`<10ms`)
    /// BEFORE waiting on the live network handshake so cold launches show all online/offline hosts immediately.
    public func hydratePersistedHostProjectionsIfNeeded(
        savedCredentials: SavedBackendCredentials? = nil
    ) async {
        guard !isVerificationMode else { return }

        let shards = await projectionStore.loadAllHostProjections()
        let savedKnownHosts = await projectionStore.loadKnownHosts()

        var hydratedHosts: [RemoteHostInstance] = []
        var seenHostIds = Set<String>()

        func appendOfflineHostIfNeeded(_ host: RemoteHostInstance) {
            guard host.instanceId != "unpaired", !host.instanceId.isEmpty else { return }
            if seenHostIds.insert(host.instanceId).inserted {
                var offlineCopy = host
                offlineCopy.isOnline = false
                hydratedHosts.append(offlineCopy)
            }
        }

        for savedHost in savedKnownHosts {
            appendOfflineHostIfNeeded(savedHost)
        }

        var primaryOfflineHost: RemoteHostInstance? = nil
        if let saved = savedCredentials {
            let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(saved.endpointURLString)
            let credId: String = {
                if let resolved = saved.resolvedInstanceUuid, !resolved.isEmpty {
                    return resolved
                }
                if let parsedId = parsedTarget?.instanceId, !parsedId.isEmpty {
                    return parsedId
                }
                if saved.channel == .directHost, let host = URL(string: saved.endpointURLString)?.host {
                    return "direct-\(host)"
                }
                return saved.hostname
            }()
            let credURL = URL(string: saved.endpointURLString)
                ?? URL(string: SAPISIDHashGenerator.defaultOrigin)!
            let credHost = RemoteHostInstance(
                instanceId: credId,
                hostname: saved.hostname,
                channel: saved.channel,
                endpointURL: credURL,
                isOnline: false,
                certificateFingerprintSHA256: saved.certFingerprintSHA256
            )
            if let existing = hydratedHosts.first(where: { $0.instanceId == credId || $0.hostname == saved.hostname }) {
                primaryOfflineHost = existing
            } else {
                appendOfflineHostIfNeeded(credHost)
                primaryOfflineHost = credHost
            }
        }

        // Also surface any offline local host discovered in cached shards even if `hosts_projection.json` wasn't saved yet
        let defaultChannel: RemoteConnectionChannel = savedCredentials?.channel ?? activeHost.channel
        for shard in shards where !shard.isCloud {
            let shardId = (shard.instanceId?.isEmpty == false)
                ? shard.instanceId!
                : (shard.hostKey.hasPrefix("host:") ? String(shard.hostKey.dropFirst("host:".count)) : shard.hostKey)
            guard !shardId.isEmpty, shardId != "default", shardId != "unpaired" else { continue }
            if !hydratedHosts.contains(where: { $0.instanceId == shardId || $0.hostname == shard.hostname }) {
                let fallbackURL = URL(string: "\(SAPISIDHashGenerator.defaultOrigin)/r/\(shardId)")
                    ?? activeHost.endpointURL
                appendOfflineHostIfNeeded(
                    RemoteHostInstance(
                        instanceId: shardId,
                        hostname: shard.hostname.isEmpty ? shardId : shard.hostname,
                        channel: defaultChannel,
                        endpointURL: fallbackURL,
                        isOnline: false
                    )
                )
            }
        }

        var mergedSummariesById: [String: CascadeSummary] = [:]
        var cachedProjects: [ProjectWorkspace] = []
        var cachedCloudProjects: [ProjectWorkspace] = []
        var cachedWorkspaces: [WorkspaceInfo] = []
        var seenWorkspaceKeys = Set<String>()

        for shard in shards {
            for s in shard.summaries where !Self.esddFixtureCascadeIds.contains(s.cascadeId) {
                if let existing = mergedSummariesById[s.cascadeId] {
                    if s.updatedAt > existing.updatedAt || s.stepCount > existing.stepCount {
                        mergedSummariesById[s.cascadeId] = s
                    }
                } else {
                    mergedSummariesById[s.cascadeId] = s
                }
            }
            for p in shard.projects where !Self.esddFixtureProjectIds.contains(p.id) {
                cachedProjects.append(p)
                if p.runtime == .cloud {
                    cachedCloudProjects.append(p)
                } else if !p.isNoProject && !p.workspaceUri.isEmpty {
                    let wsKey = "\(p.originInstanceUuid ?? p.hostName)|\(p.workspaceUri.lowercased())"
                    if seenWorkspaceKeys.insert(wsKey).inserted {
                        cachedWorkspaces.append(
                            WorkspaceInfo(
                                workspaceUri: p.workspaceUri,
                                displayName: p.name,
                                activeBranch: p.activeBranch,
                                worktrees: p.worktrees,
                                isCloud: false,
                                originInstanceUuid: p.originInstanceUuid,
                                originHostName: p.hostName
                            )
                        )
                    }
                }
            }
        }

        var hydratedSummaries = mergedSummariesById.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.cascadeId < rhs.cascadeId
        }

        guard savedCredentials != nil || !hydratedSummaries.isEmpty || !cachedProjects.isEmpty else {
            return
        }

        if !hydratedHosts.isEmpty {
            hosts = hydratedHosts
            if let primaryOfflineHost {
                activeHost = primaryOfflineHost
            } else if activeHost.instanceId == "unpaired", let first = hydratedHosts.first {
                activeHost = first
            }
            if availableRelayInstances.isEmpty {
                let relayHosts = hydratedHosts.filter { $0.channel == .cloudRelay }
                if !relayHosts.isEmpty {
                    availableRelayInstances = relayHosts.map { host in
                        RelayInstanceInfo(
                            uuid: host.instanceId,
                            name: host.hostname,
                            version: host.version,
                            status: .disconnected
                        )
                    }
                }
            }
        }

        if !hydratedSummaries.isEmpty || !cachedProjects.isEmpty {
            let reconciled = Self.reconcileLiveProjects(
                workspaces: cachedWorkspaces,
                summaries: &hydratedSummaries,
                existingProjects: cachedProjects,
                hostName: activeHost.hostname,
                cloudProjects: cachedCloudProjects
            )
            workspaces = cachedWorkspaces
            projects = reconciled
            summaries = hydratedSummaries
            if selectedProjectId.isEmpty {
                let defaultProj = reconciled.first(where: { !$0.isNoProject }) ?? reconciled.first
                selectedProjectId = defaultProj?.id ?? ""
                selectedWorkspaceUri = defaultProj?.workspaceUri ?? ""
            }
            if activeCascadeId.isEmpty {
                activeCascadeId = hydratedSummaries.first?.cascadeId ?? ""
            }
        }

        let cachedAutomations = (await projectionStore.loadAutomations()).filter {
            !Self.esddFixtureAutomationIds.contains($0.id)
        }
        if automations.isEmpty && !cachedAutomations.isEmpty {
            automations = cachedAutomations
        }
        pendingOutboxCount = await projectionStore.loadPendingOutbox().count

        hasPairedBackend = true
        isLiveBackendConnected = false
        isInitialSessionCheckComplete = true
        connectionLifecyclePhase = savedCredentials != nil ? .connecting : .offlineBackoff(attempt: 0, nextRetrySeconds: 3)
        connectionStatusText = savedCredentials != nil
            ? "Reconnecting · \(activeHost.hostname)..."
            : "Offline · \(activeHost.hostname)"
    }

    /// Restores saved Keychain credentials on launch: instantly hydrates cached per-host projections from disk
    /// (`<10ms`) so both online and offline hosts' conversations appear immediately, then connects live to merge fresh data.
    @discardableResult
    public func restoreSavedBackendSession() async -> Bool {
        guard let saved = await KeychainStore.shared.loadCredentials() else {
            return false
        }
        await hydratePersistedHostProjectionsIfNeeded(savedCredentials: saved)
        switch saved.channel {
        case .directHost:
            return await connectDirectLAN(
                endpointURLString: saved.endpointURLString,
                csrfToken: saved.csrfToken ?? "",
                certSHA256: saved.certFingerprintSHA256,
                hostName: saved.hostname,
                isRestoringSavedSession: true
            )
        case .cloudRelay:
            return await connectCloudRelay(
                relayURLString: saved.endpointURLString,
                sessionCookie: saved.sessionCookie ?? "",
                authUser: saved.authUser,
                resolvedInstanceUuid: saved.resolvedInstanceUuid,
                hostName: saved.hostname,
                isRestoringSavedSession: true
            )
        }
    }

    /// Reads any previously saved Google Cloud Relay session cookie from Keychain so scanning a new QR code
    /// connects immediately without asking the user to sign in again.
    public func loadSavedSessionCookie() async -> (cookie: String, authUser: String?)? {
        guard let saved = await KeychainStore.shared.loadCredentials(),
              let cookie = saved.sessionCookie,
              !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return (cookie, saved.authUser)
    }

    /// Parses and connects via QR / Deep Link URI:
    /// - Official Antigravity Desktop QR: `https://antigravity.google.com/r/<instance-id>?p=c%2F<cascadeId>`
    /// - Optional LAN / Bridge Deep Link: `antigravity://pair?url=https://192.168.1.20:8787&csrf=<token>&sha256=<fp>&name=MacBook%20Pro`
    @discardableResult
    public func connectWithPairingURI(_ rawURI: String, fallbackCookie: String = "") async -> Bool {
        let trimmed = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
        if RemoteHostInstance.isDirectLANPairingURI(trimmed),
           let comps = URLComponents(string: trimmed),
           let targetURL = comps.queryItems?.first(where: { $0.name == "url" })?.value {
            let csrf = comps.queryItems?.first(where: { $0.name == "csrf" })?.value ?? ""
            let sha256 = comps.queryItems?.first(where: { $0.name == "sha256" })?.value
            let name = comps.queryItems?.first(where: { $0.name == "name" })?.value ?? "MacBook Pro"
            return await connectDirectLAN(
                endpointURLString: targetURL,
                csrfToken: csrf,
                certSHA256: sha256,
                hostName: name
            )
        }

        if let target = RemoteHostInstance.parseRemoteControlTarget(trimmed) {
            lastScannedRelayURL = target.canonicalRelayURLString
            var effectiveCookie = fallbackCookie.trimmingCharacters(in: .whitespacesAndNewlines)
            var savedAuthUser = target.authUser
            if effectiveCookie.isEmpty, let cached = await loadSavedSessionCookie() {
                effectiveCookie = cached.cookie
                if savedAuthUser == nil {
                    savedAuthUser = cached.authUser
                }
            }
            let displayHost = target.instanceId.isEmpty ? "Antigravity Desktop" : target.instanceId
            return await connectCloudRelay(
                relayURLString: trimmed,
                sessionCookie: effectiveCookie,
                authUser: savedAuthUser,
                deepLinkedConversationId: target.conversationId,
                hostName: displayHost
            )
        }

        return await connectDirectLAN(endpointURLString: trimmed, csrfToken: fallbackCookie)
    }

    /// Connects directly to Mac `language_server` or `mac-companion-bridge.py` over LAN / Tailscale
    /// using `x-codeium-csrf-token` + SHA-256 certificate pinning / TOFU.
    @discardableResult
    public func connectDirectLAN(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String? = nil,
        hostName: String = "MacBook Pro",
        isRestoringSavedSession: Bool = false
    ) async -> Bool {
        guard let url = URL(string: endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            connectionErrorText = "Invalid endpoint URL: \(endpointURLString)"
            return false
        }

        isConnectingToBackend = true
        connectionErrorText = nil
        connectionStatusText = "Handshaking with \(url.host ?? endpointURLString)..."
        defer { isConnectingToBackend = false }

        let hostInstance = RemoteHostInstance(
            instanceId: "direct-\(url.host ?? "mac")",
            hostname: hostName,
            channel: .directHost,
            endpointURL: url,
            isOnline: true,
            certificateFingerprintSHA256: certSHA256 ?? "TOFU-LOCAL-TLS"
        )
        let candidateClient = AntigravityRPCClient(
            host: hostInstance,
            csrfToken: csrfToken,
            pinnedFingerprintSHA256: certSHA256
        )

        do {
            let handshake = try await candidateClient.verifyConnection()
            applyVerifiedLiveConnection(
                host: hostInstance,
                client: candidateClient,
                handshake: handshake
            )
            await KeychainStore.shared.saveCredentials(
                SavedBackendCredentials(
                    endpointURLString: url.absoluteString,
                    channel: .directHost,
                    hostname: hostName,
                    csrfToken: csrfToken,
                    certFingerprintSHA256: certSHA256
                )
            )
            return true
        } catch let AntigravityRPCError.unauthorized(reason) {
            let errMsg = "Authentication rejected (401/403): check x-codeium-csrf-token. \(reason)"
            let statusMsg = "Auth Failed · Invalid CSRF Token"
            if isRestoringSavedSession || hasPairedBackend {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName) (Auth Expired)"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = statusMsg
            }
            return false
        } catch {
            let errMsg = "Connection failed: \(error.localizedDescription)"
            if isRestoringSavedSession || hasPairedBackend {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName)"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = "Unreachable · \(url.host ?? endpointURLString)"
            }
            return false
        }
    }

    ///Resolves HTTP redirects for official Google shortlinks (`g.co`, `c.gle`, `goo.gl`, `*.page.link`)
    /// using an ephemeral `URLSession` (without attaching session cookies) so the target `/r/<instance-id>` is discovered.
    nonisolated private static func resolveShortlinkRedirectIfNeeded(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var headReq = URLRequest(url: url)
        headReq.httpMethod = "HEAD"
        if let (_, resp) = try? await session.data(for: headReq),
           let finalStr = resp.url?.absoluteString,
           finalStr != urlString,
           RemoteHostInstance.parseRemoteControlTarget(finalStr) != nil {
            return finalStr
        }

        var getReq = URLRequest(url: url)
        getReq.httpMethod = "GET"
        if let (_, resp) = try? await session.data(for: getReq),
           let finalStr = resp.url?.absoluteString,
           finalStr != urlString,
           RemoteHostInstance.parseRemoteControlTarget(finalStr) != nil {
            return finalStr
        }
        return nil
    }

    /// Connects to official Google Cloud Remote Control Relay (`https://antigravity.google.com/r/<instance-id>`)
    /// via `devtools_jetski_boq_api_proto.ApiService` (`ListInstances` + `ProxyCommand` + `SAPISIDHASH`).
    @discardableResult
    public func connectCloudRelay(
        relayURLString: String,
        sessionCookie: String,
        authUser: String? = nil,
        resolvedInstanceUuid: String? = nil,
        deepLinkedConversationId: String? = nil,
        hostName: String = "Antigravity Desktop",
        isRestoringSavedSession: Bool = false,
        focusHostFilterOnConnected: Bool = false,
        strictTargetSelection: Bool = false
    ) async -> Bool {
        let trimmedInput = relayURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedTarget = RemoteHostInstance.parseRemoteControlTarget(
            trimmedInput.isEmpty ? SAPISIDHashGenerator.defaultOrigin : trimmedInput
        )
        var canonicalURLString = parsedTarget?.canonicalRelayURLString ?? trimmedInput
        guard URL(string: canonicalURLString)?.scheme != nil else {
            connectionErrorText = "Invalid Remote Control QR link: \(relayURLString)"
            return false
        }

        lastScannedRelayURL = canonicalURLString
        let trimmedCookie = sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCookie.isEmpty else {
            isLiveBackendConnected = false
            let fallbackName = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : "Antigravity Desktop"
            connectionErrorText = "Google Sign-In required: sign in once to pair with \(fallbackName)."
            connectionStatusText = "Sign in with Google to pair Remote Control"
            return false
        }

        let previousStatusText = connectionStatusText
        isConnectingToBackend = true
        connectionErrorText = nil
        defer { isConnectingToBackend = false }

        if parsedTarget?.requiresRedirectResolution == true,
           let origURL = parsedTarget?.originalURLString {
            connectionStatusText = "Resolving Remote Control link..."
            if let resolvedStr = await Self.resolveShortlinkRedirectIfNeeded(origURL),
               let resolvedTarget = RemoteHostInstance.parseRemoteControlTarget(resolvedStr) {
                parsedTarget = resolvedTarget
                canonicalURLString = resolvedTarget.canonicalRelayURLString
                lastScannedRelayURL = canonicalURLString
            }
        }

        guard let url = URL(string: canonicalURLString), url.scheme != nil else {
            connectionErrorText = "Invalid Remote Control QR link: \(relayURLString)"
            return false
        }

        let targetBadge = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : "Cloud Relay"
        connectionStatusText = "Pairing with \(targetBadge) via Google Cloud Relay..."

        let effectiveAuthUser = authUser ?? parsedTarget?.authUser
        let initialInstanceId = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : "auto"
        let deepLinkConv = deepLinkedConversationId ?? parsedTarget?.conversationId

        let hostInstance = RemoteHostInstance(
            instanceId: resolvedInstanceUuid ?? initialInstanceId,
            hostname: hostName,
            channel: .cloudRelay,
            endpointURL: url,
            isOnline: true
        )
        let candidateClient = AntigravityRPCClient(
            host: hostInstance,
            sessionCookie: trimmedCookie,
            authUser: effectiveAuthUser,
            resolvedInstanceUuid: resolvedInstanceUuid
        )

        do {
            let handshake = try await candidateClient.verifyConnection(
                strictTargetSelection: strictTargetSelection
            )
            let finalHostName = handshake.resolvedHostname ?? hostName
            let finalUuid = handshake.resolvedInstanceUuid ?? hostInstance.instanceId
            let finalAuthUser = handshake.resolvedAuthUser ?? effectiveAuthUser ?? "0"
            let originPrefix = parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
            let finalRelayURL = URL(string: "\(originPrefix)/r/\(finalUuid)") ?? url

            let verifiedHost = RemoteHostInstance(
                instanceId: finalUuid,
                hostname: finalHostName,
                version: handshake.serverVersion,
                channel: .cloudRelay,
                endpointURL: finalRelayURL,
                isOnline: true,
                latencyMs: handshake.latencyMs
            )

            let preservedCachedSummaries: [CascadeSummary]
            let preservedCachedProjects: [ProjectWorkspace]
            if isRestoringSavedSession || hasPairedBackend {
                let shards = await projectionStore.loadAllHostProjections()
                if !shards.isEmpty {
                    preservedCachedSummaries = shards.flatMap(\.summaries).filter {
                        !Self.esddFixtureCascadeIds.contains($0.cascadeId)
                    }
                    preservedCachedProjects = shards.flatMap(\.projects).filter {
                        !Self.esddFixtureProjectIds.contains($0.id)
                    }
                } else {
                    preservedCachedSummaries = (await projectionStore.loadProjectedSummaries()).filter {
                        !Self.esddFixtureCascadeIds.contains($0.cascadeId)
                    }
                    preservedCachedProjects = (await projectionStore.loadProjects()).filter {
                        !Self.esddFixtureProjectIds.contains($0.id)
                    }
                }
            } else {
                preservedCachedSummaries = []
                preservedCachedProjects = []
            }

            activeAuthUser = finalAuthUser
            // Sync all Cloud Relay instances (online & offline) into `hosts` before saving projections
            // so `hosts_projection.json` always records every paired Mac on this Google account.
            let activeRelayInst = handshake.availableRelayInstances.first(where: { $0.uuid == finalUuid })
            syncRelayInstancesToHosts(
                handshake.availableRelayInstances,
                latencyMs: handshake.latencyMs,
                preferredActiveInstance: activeRelayInst,
                relayOriginPrefix: originPrefix,
                persistKeychainIfChanged: false
            )
            applyVerifiedLiveConnection(
                host: verifiedHost,
                client: candidateClient,
                handshake: handshake,
                preservedCachedSummaries: preservedCachedSummaries,
                preservedCachedProjects: preservedCachedProjects
            )
            if focusHostFilterOnConnected {
                hostFilter = .localHost(id: finalUuid, name: finalHostName)
            }

            await KeychainStore.shared.saveCredentials(
                SavedBackendCredentials(
                    endpointURLString: finalRelayURL.absoluteString,
                    channel: .cloudRelay,
                    hostname: finalHostName,
                    sessionCookie: trimmedCookie,
                    authUser: finalAuthUser,
                    resolvedInstanceUuid: finalUuid
                )
            )

            if let deepLinkConv, !deepLinkConv.isEmpty {
                selectCascade(deepLinkConv)
            }
            return true
        } catch let AntigravityRPCError.unauthorized(reason) {
            let errMsg = "Google session unauthorized: please sign in again. (\(reason))"
            if isRestoringSavedSession {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Google Sign-In Expired"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = "Google Sign-In Expired"
            }
            return false
        } catch let AntigravityRPCError.httpError(code, body) {
            let latestInstances = await candidateClient.cachedInstancesSnapshot()
            if !latestInstances.isEmpty {
                syncRelayInstancesState(
                    latestInstances,
                    latencyMs: lastPingLatencyMs ?? activeHost.latencyMs,
                    relayOriginPrefix: parsedTarget?.relayOrigin
                )
            }
            if strictTargetSelection && isLiveBackendConnected {
                connectionErrorText = body.isEmpty ? "\(hostName) is currently offline or unreachable." : body
                connectionStatusText = previousStatusText
                return false
            }
            let errMsg = "Cloud Relay error (\(code)): \(body)"
            if (isRestoringSavedSession || hasPairedBackend) && (code == 502 || code == 503 || code == 504) {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName)"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = "Cloud Relay Handshake Failed"
            }
            return false
        } catch {
            let latestInstances = await candidateClient.cachedInstancesSnapshot()
            if !latestInstances.isEmpty {
                syncRelayInstancesState(
                    latestInstances,
                    latencyMs: lastPingLatencyMs ?? activeHost.latencyMs,
                    relayOriginPrefix: parsedTarget?.relayOrigin
                )
            }
            if strictTargetSelection && isLiveBackendConnected {
                connectionErrorText = "\(hostName) is unreachable: \(error.localizedDescription)"
                connectionStatusText = previousStatusText
                return false
            }
            let errMsg = "Cloud Relay handshake failed: \(error.localizedDescription)"
            if isRestoringSavedSession || hasPairedBackend {
                await applyOfflinePairedSession(
                    host: hostInstance,
                    client: candidateClient,
                    errorText: errMsg,
                    statusText: "Offline · \(hostName)"
                )
            } else {
                isLiveBackendConnected = false
                connectionErrorText = errMsg
                connectionStatusText = "Cloud Relay Disconnected"
            }
            return false
        }
    }

    public func disconnectBackendAndClearKeychain() async {
        cancelAllSummaryStreams()
        cancelAllInFlightHostRefreshes()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        stepPollingTask?.cancel()
        stepPollingTask = nil
        networkPathObserver.stop()
        hasPairedBackend = false
        isLiveBackendConnected = false
        cloudAgentWarmingUp = false
        consecutiveSyncFailures = 0
        reconnectAttemptCount = 0
        nextReconnectAt = nil
        backgroundPollCounter = 0
        lastBackendActivityAt = .distantPast
        lastFullSyncAt = .distantPast
        lastStreamReopenAttemptAt = .distantPast
        pendingOutboxCount = 0
        connectionLifecyclePhase = .disconnected
        lastAutomationsSyncAt = nil
        isLoadingAutomations = false
        isMutatingAutomation = false
        automationsErrorText = nil
        isAutomationsAuthExpired = false
        pendingDraftConversation = nil
        composerWorkflowCommand = nil
        optimisticActiveUntilByCascadeId.removeAll()
        syncedConfigCascadeIds.removeAll()
        locallyCreatedEmptyCascadeIds.removeAll()
        rpcClient = nil
        lastPingLatencyMs = nil
        availableRelayInstances = []
        isRefreshingRelayHosts = false
        hostFilter = .allHosts
        connectionErrorText = nil
        connectionStatusText = "Not Connected"
        if !isVerificationMode {
            projects = []
            workspaces = []
            summaries = []
            automations = []
            stepsByCascadeId = [:]
            activeArtifacts = []
            activeTurnDiffs = []
            planChanges = []
            planComments = []
            composerAttachments = []
            composerDraftText = ""
            selectedProjectId = ""
            selectedWorkspaceUri = ""
            activeCascadeId = ""
            activeRoute = .tabRoot
        }
        _ = await projectionStore.drainOutbox()
        await projectionStore.clearCachedProjections()
        await KeychainStore.shared.clearCredentials()
    }

    // MARK: - Foreground / Screen-Off Lifecycle & Network Path Control

    /// Immediately suspends all streams, heartbeats, backoff timers, step polling, and `NWPathMonitor`
    /// when the device locks, sleeps, or enters the background so battery & radio overhead is zero.
    public func suspendNetworkingForBackground() {
        guard !isVerificationMode else { return }
        guard !isNetworkingSuspended else { return }
        isNetworkingSuspended = true
        cancelAllSummaryStreams()
        cancelAllInFlightHostRefreshes()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        stepPollingTask?.cancel()
        stepPollingTask = nil
        networkPathObserver.stop()
        if hasPairedBackend || isLiveBackendConnected {
            connectionLifecyclePhase = .suspended
        }
    }

    /// Resumes connectivity cleanly when the screen unlocks or the app returns to `.active`:
    /// performs a single fresh reconciliation pass and restarts push streams + low-power scheduler.
    public func resumeNetworkingFromForeground() async {
        guard !isVerificationMode else { return }
        let wasSuspended = isNetworkingSuspended
        isNetworkingSuspended = false
        startNetworkPathMonitoringIfNeeded()

        guard hasPairedBackend else { return }

        if rpcClient == nil {
            _ = await restoreSavedBackendSession()
            return
        }

        guard isDeviceNetworkReachable else {
            connectionLifecyclePhase = .noNetwork
            connectionStatusText = "No Internet Connection"
            return
        }

        reconnectAttemptCount = 0
        nextReconnectAt = nil
        if wasSuspended {
            connectionLifecyclePhase = .connecting
        }

        await refreshWorkspacesAndSummaries(
            forceFullSync: true,
            includeAutomations: selectedTab == .automations
        )
        startSummarySubscriptionStream()

        if case .cascadeChat(let cid) = activeRoute, !cid.isEmpty {
            syncStepsForCascade(cid, pollUntilIdle: true)
        }
    }

    /// Immediately resets exponential backoff and attempts a fresh connection + sync.
    /// Used by `Reconnect Now`, pull-to-refresh, `NWPathMonitor` recovery, and chat retry buttons.
    public func reconnectNow(userInitiated: Bool = true, includeAutomations: Bool = false) async {
        guard !isVerificationMode else { return }
        if isNetworkingSuspended {
            isNetworkingSuspended = false
            startNetworkPathMonitoringIfNeeded()
        }
        guard hasPairedBackend else { return }

        if !userInitiated && !isDeviceNetworkReachable {
            connectionLifecyclePhase = .noNetwork
            connectionStatusText = "No Internet Connection"
            return
        }

        reconnectAttemptCount = 0
        consecutiveSyncFailures = 0
        nextReconnectAt = nil
        lastStreamReopenAttemptAt = .distantPast
        summaryPollingTask?.cancel()
        summaryPollingTask = nil
        connectionLifecyclePhase = .connecting

        if rpcClient == nil {
            _ = await restoreSavedBackendSession()
            return
        }

        await refreshWorkspacesAndSummaries(
            forceFullSync: true,
            includeAutomations: includeAutomations || selectedTab == .automations
        )
        startSummarySubscriptionStream()

        if case .cascadeChat(let cid) = activeRoute, !cid.isEmpty {
            syncStepsForCascade(cid, pollUntilIdle: true)
        }
    }

    private func startNetworkPathMonitoringIfNeeded() {
        guard !isVerificationMode, !isNetworkingSuspended else { return }
        networkPathObserver.start { [weak self] status in
            Task { @MainActor [weak self] in
                self?.handleNetworkPathChange(status)
            }
        }
    }

    internal func handleNetworkPathChange(_ status: NetworkReachabilityStatus) {
        let previous = lastNetworkStatus
        lastNetworkStatus = status
        isDeviceNetworkReachable = status.isSatisfied
        isNetworkExpensiveOrConstrained = status.isExpensiveOrConstrained

        guard !isVerificationMode, !isNetworkingSuspended, hasPairedBackend else { return }

        if !status.isSatisfied {
            // Device lost IP connectivity (e.g. elevator / Airplane Mode): stop all timers & streams (0 packets)
            cancelAllSummaryStreams()
            summaryPollingTask?.cancel()
            summaryPollingTask = nil
            stepPollingTask?.cancel()
            stepPollingTask = nil
            isLiveBackendConnected = false
            lastPingLatencyMs = nil
            nextReconnectAt = nil
            connectionLifecyclePhase = .noNetwork
            connectionStatusText = "No Internet Connection"
            connectionErrorText = "iPhone is offline. Waiting for Wi-Fi or cellular network..."
            return
        }

        // Network transitioned from unsatisfied -> satisfied, OR switched interfaces (Wi-Fi <-> 5G)
        let recoveredFromNoNetwork = (previous == .unsatisfied)
        let interfaceSwitched: Bool = {
            guard let prevFp = previous?.interfaceFingerprint,
                  let nextFp = status.interfaceFingerprint else {
                return false
            }
            return prevFp != nextFp
        }()

        if recoveredFromNoNetwork || interfaceSwitched {
            cancelAllSummaryStreams()
            Task { [weak self] in
                await self?.reconnectNow(userInitiated: false)
            }
        }
    }

    private func applyOfflinePairedSession(
        host: RemoteHostInstance,
        client: AntigravityRPCClient,
        errorText: String,
        statusText: String
    ) async {
        var offlineHost = host
        offlineHost.isOnline = false
        activeHost = offlineHost
        if let existingIdx = hosts.firstIndex(where: { $0.instanceId == offlineHost.instanceId }) {
            hosts[existingIdx] = offlineHost
        } else {
            hosts.insert(offlineHost, at: 0)
        }

        let wasInESDDDemoState = !hasPairedBackend
        hasPairedBackend = true
        isLiveBackendConnected = false
        lastPingLatencyMs = nil
        rpcClient = client
        reconnectAttemptCount = 0
        connectionErrorText = errorText
        connectionStatusText = statusText
        pendingOutboxCount = await projectionStore.loadPendingOutbox().count

        if isNetworkingSuspended {
            connectionLifecyclePhase = .suspended
        } else if !isDeviceNetworkReachable {
            connectionLifecyclePhase = .noNetwork
        } else {
            let nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelay(
                attempt: 0,
                isLowPowerMode: isLowPowerModeEnabled
            )
            connectionLifecyclePhase = .offlineBackoff(attempt: 0, nextRetrySeconds: nextDelay)
        }

        if wasInESDDDemoState || (summaries.isEmpty && projects.isEmpty) {
            let shards = await projectionStore.loadAllHostProjections()
            let cachedProjects: [ProjectWorkspace]
            let cachedSummaries: [CascadeSummary]
            if !shards.isEmpty {
                cachedProjects = shards.flatMap(\.projects).filter {
                    !Self.esddFixtureProjectIds.contains($0.id)
                }
                var byId: [String: CascadeSummary] = [:]
                for s in shards.flatMap(\.summaries) where !Self.esddFixtureCascadeIds.contains(s.cascadeId) {
                    if let existing = byId[s.cascadeId] {
                        if s.updatedAt > existing.updatedAt || s.stepCount > existing.stepCount {
                            byId[s.cascadeId] = s
                        }
                    } else {
                        byId[s.cascadeId] = s
                    }
                }
                cachedSummaries = byId.values.sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    return lhs.cascadeId < rhs.cascadeId
                }
            } else {
                cachedProjects = (await projectionStore.loadProjects()).filter {
                    !Self.esddFixtureProjectIds.contains($0.id)
                }
                cachedSummaries = (await projectionStore.loadProjectedSummaries()).filter {
                    !Self.esddFixtureCascadeIds.contains($0.cascadeId)
                }
            }
            var hydratedSummaries = cachedSummaries
            let cachedCloudProjects = cachedProjects.filter { $0.runtime == .cloud }
            var cachedWorkspaces: [WorkspaceInfo] = []
            var seenWs = Set<String>()
            for p in cachedProjects where p.runtime == .macBookPro && !p.isNoProject && !p.workspaceUri.isEmpty {
                let wsKey = "\(p.originInstanceUuid ?? p.hostName)|\(p.workspaceUri.lowercased())"
                if seenWs.insert(wsKey).inserted {
                    cachedWorkspaces.append(
                        WorkspaceInfo(
                            workspaceUri: p.workspaceUri,
                            displayName: p.name,
                            activeBranch: p.activeBranch,
                            worktrees: p.worktrees,
                            isCloud: false,
                            originInstanceUuid: p.originInstanceUuid,
                            originHostName: p.hostName
                        )
                    )
                }
            }
            if !cachedProjects.isEmpty || !hydratedSummaries.isEmpty {
                projects = Self.reconcileLiveProjects(
                    workspaces: cachedWorkspaces,
                    summaries: &hydratedSummaries,
                    existingProjects: cachedProjects,
                    hostName: offlineHost.hostname,
                    cloudProjects: cachedCloudProjects
                )
                summaries = hydratedSummaries
                workspaces = cachedWorkspaces
            } else if wasInESDDDemoState {
                projects = []
                summaries = []
                workspaces = []
            }
            if wasInESDDDemoState {
                stepsByCascadeId = [:]
            }
            automations = (await projectionStore.loadAutomations()).filter {
                !Self.esddFixtureAutomationIds.contains($0.id)
            }
            selectedProjectId = projects.first?.id ?? ""
            selectedWorkspaceUri = projects.first?.workspaceUri ?? ""
            activeCascadeId = summaries.first?.cascadeId ?? ""
        }

        startSummarySubscriptionStream()
    }

    internal static func isBackendOfflineError(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let rpcErr = error as? AntigravityRPCError {
            switch rpcErr {
            case .unauthorized, .invalidEndpoint:
                return true
            case .httpError(let statusCode, _):
                return statusCode == -1 || statusCode == 502 || statusCode == 503 || statusCode == 504
            case .decodingError, .interactionRejected:
                return false
            }
        }
        if error is URLError {
            return true
        }
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain || nsErr.domain == NSPOSIXErrorDomain {
            return true
        }
        return false
    }

    internal func markBackendOffline(error: Error) {
        guard hasPairedBackend || isLiveBackendConnected else { return }
        cancelAllSummaryStreams()
        isLiveBackendConnected = false
        lastPingLatencyMs = nil

        var updatedHost = activeHost
        updatedHost.isOnline = false
        activeHost = updatedHost
        if let idx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
            hosts[idx] = updatedHost
        }
        if updatedHost.channel == .cloudRelay || !isDeviceNetworkReachable {
            for idx in hosts.indices where hosts[idx].channel == updatedHost.channel || !isDeviceNetworkReachable {
                hosts[idx].isOnline = false
            }
            availableRelayInstances = availableRelayInstances.map { inst in
                RelayInstanceInfo(
                    uuid: inst.uuid,
                    name: inst.name,
                    version: inst.version,
                    supportsChunking: inst.supportsChunking,
                    status: .disconnected,
                    updatedAt: inst.updatedAt
                )
            }
        }

        connectionErrorText = error.localizedDescription
        connectionStatusText = "Offline · \(updatedHost.hostname)"

        if isNetworkingSuspended {
            connectionLifecyclePhase = .suspended
        } else if !isDeviceNetworkReachable {
            connectionLifecyclePhase = .noNetwork
        } else {
            let nextDelay = ConnectionPowerPolicy.offlineBackoffBaseDelay(
                attempt: reconnectAttemptCount,
                isLowPowerMode: isLowPowerModeEnabled
            )
            connectionLifecyclePhase = .offlineBackoff(attempt: reconnectAttemptCount, nextRetrySeconds: nextDelay)
        }
    }

    private func markBackendReconnected() {
        let wasOffline = !isLiveBackendConnected || !activeHost.isOnline
        consecutiveSyncFailures = 0
        reconnectAttemptCount = 0
        nextReconnectAt = nil
        lastBackendActivityAt = Date()
        isDeviceNetworkReachable = true
        hasPairedBackend = true
        isLiveBackendConnected = true
        connectionErrorText = nil

        var updatedHost = activeHost
        updatedHost.isOnline = true
        activeHost = updatedHost
        if let idx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
            hosts[idx] = updatedHost
        }
        connectionStatusText = "Connected · \(updatedHost.hostname)"
        connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle

        if wasOffline && !isNetworkingSuspended {
            lastStreamReopenAttemptAt = .distantPast
            ensureSummaryEnvelopeStreamRunning()
            if case .cascadeChat(let cid) = activeRoute, !cid.isEmpty, stepPollingTask == nil {
                syncStepsForCascade(cid, pollUntilIdle: true)
            }
            Task { [weak self] in
                await self?.replayPendingOutbox()
            }
        }
    }

    internal static func normalizeNoProjectSummary(_ s: inout CascadeSummary) {
        guard !esddFixtureCascadeIds.contains(s.cascadeId) else { return }
        guard (s.cloudProjectId ?? "").isEmpty else { return }
        if AntigravityCloudDetector.isGenericContainerURI(s.workspaceUri) {
            s.workspaceUri = ""
        }
        let isScratch = AntigravityCloudDetector.isPlaygroundScratchURI(s.workspaceUri)
        if AntigravityCloudDetector.isNoProjectSlug(s.projectSlug) || isScratch {
            let hasCloudPrefix = s.projectSlug.lowercased().hasPrefix("cloud:")
            s.projectSlug = hasCloudPrefix
                ? "cloud:\(AntigravityCloudDetector.noProjectDisplayName)"
                : AntigravityCloudDetector.noProjectDisplayName
            s.branchName = ""
            if !isScratch && s.workspaceUri.isEmpty == false && AntigravityCloudDetector.isGenericContainerURI(s.workspaceUri) {
                s.workspaceUri = ""
            }
        }
    }

    internal static func reconcileLiveProjects(
        workspaces: [WorkspaceInfo],
        summaries: inout [CascadeSummary],
        existingProjects: [ProjectWorkspace],
        hostName: String,
        cloudProjects: [ProjectWorkspace] = []
    ) -> [ProjectWorkspace] {
        let nonDemoExisting = existingProjects.filter { existing in
            guard !esddFixtureProjectIds.contains(existing.id) else { return false }
            if (existing.cloudProjectId ?? "").isEmpty && AntigravityCloudDetector.isNoProjectSlug(existing.name) {
                return existing.name == AntigravityCloudDetector.noProjectDisplayName
            }
            return true
        }
        var expandedById: [String: Bool] = [:]
        var existingById: [String: ProjectWorkspace] = [:]
        for p in nonDemoExisting {
            expandedById[p.id] = p.isExpandedInHome
            existingById[p.id] = p
        }

        let cloudProjByName = Dictionary(grouping: cloudProjects, by: \.name)

        func baseSlug(for rawSlug: String) -> String {
            AntigravityCloudDetector.stripProjectNamespacePrefix(rawSlug)
        }

        // Link Cloud summaries (by projectId, workspaceUri, or owner/repo label) to their canonical Cloud project,
        // and normalize unassigned / legacy `"workspace"` / scratch playground summaries to `"No Project"`.
        for idx in summaries.indices {
            if let cp = AntigravityRPCClient.matchCloudProject(for: summaries[idx], cloudProjects: cloudProjects) {
                summaries[idx].isCloud = true
                summaries[idx].cloudProjectId = cp.cloudProjectId ?? cp.id
                summaries[idx].projectSlug = cp.name
                summaries[idx].workspaceUri = cp.workspaceUri
                summaries[idx].originHostName = "Antigravity"
            } else {
                normalizeNoProjectSummary(&summaries[idx])
            }
        }

        func preferredCloudUri(_ primary: String?, _ secondary: String) -> String {
            if let p = primary, !p.isEmpty {
                let pHasOwner = AntigravityCloudDetector.extractCloudLocationLabel(p)?.contains("/") == true
                let sHasOwner = AntigravityCloudDetector.extractCloudLocationLabel(secondary)?.contains("/") == true
                if !pHasOwner && sHasOwner {
                    return secondary
                }
                return p
            }
            return secondary
        }

        func localHostPartitionKey(for summary: CascadeSummary) -> String {
            if let uuid = summary.originInstanceUuid?.trimmingCharacters(in: .whitespacesAndNewlines), !uuid.isEmpty {
                return uuid
            }
            if let originHost = summary.originHostName?.trimmingCharacters(in: .whitespacesAndNewlines), !originHost.isEmpty {
                return originHost
            }
            return hostName
        }

        var orderedBaseSlugs: [String] = []
        var seenBaseSlugs = Set<String>()
        for s in summaries {
            let b = baseSlug(for: s.projectSlug)
            if !b.isEmpty && seenBaseSlugs.insert(b).inserted {
                orderedBaseSlugs.append(b)
            }
        }

        let wsByName = Dictionary(grouping: workspaces, by: \.displayName)
        var reconciled: [ProjectWorkspace] = []
        var knownIds = Set<String>()

        func appendLocalGroups(
            canonicalName: String,
            isNoProj: Bool,
            localIndices: [Int],
            localWorkspaces: [WorkspaceInfo],
            cloudWs: WorkspaceInfo?,
            summaries: inout [CascadeSummary],
            reconciled: inout [ProjectWorkspace],
            knownIds: inout Set<String>
        ) {
            var orderedHostKeys: [String] = []
            var indicesByHostKey: [String: [Int]] = [:]
            for idx in localIndices {
                let key = localHostPartitionKey(for: summaries[idx])
                if indicesByHostKey[key] == nil {
                    orderedHostKeys.append(key)
                    indicesByHostKey[key] = []
                }
                indicesByHostKey[key]?.append(idx)
            }

            for (groupOffset, hostKey) in orderedHostKeys.enumerated() {
                guard let groupIndices = indicesByHostKey[hostKey], !groupIndices.isEmpty else { continue }
                let firstLocal = summaries[groupIndices[0]]
                let matchedLocalWs = localWorkspaces.first(where: { ws in
                    if let wsUuid = ws.originInstanceUuid, !wsUuid.isEmpty,
                       let sumUuid = firstLocal.originInstanceUuid, !sumUuid.isEmpty {
                        return wsUuid == sumUuid
                    }
                    if let wsHost = ws.originHostName, !wsHost.isEmpty,
                       let sumHost = firstLocal.originHostName, !sumHost.isEmpty {
                        return wsHost == sumHost
                    }
                    return orderedHostKeys.count == 1
                }) ?? (orderedHostKeys.count == 1 ? localWorkspaces.first : nil)

                let projectId = (groupOffset == 0 && !knownIds.contains(canonicalName))
                    ? canonicalName
                    : "host:\(hostKey):\(canonicalName)"
                for idx in groupIndices {
                    summaries[idx].projectSlug = projectId
                }

                let isWsCloudOnly = orderedHostKeys.count == 1
                    && !isNoProj
                    && (cloudWs != nil && matchedLocalWs == nil && AntigravityCloudDetector.isCloudWorkspaceURI(firstLocal.workspaceUri))
                let effectiveUri = isNoProj
                    ? ""
                    : ((isWsCloudOnly ? cloudWs?.workspaceUri : matchedLocalWs?.workspaceUri) ?? firstLocal.workspaceUri)
                let effectiveBranch = isNoProj ? "" : (matchedLocalWs?.activeBranch ?? firstLocal.branchName)
                let resolvedLocalHost = matchedLocalWs?.originHostName ?? firstLocal.originHostName ?? hostName
                let pathDisplay = isNoProj
                    ? "Unassigned · \(resolvedLocalHost)"
                    : effectiveUri.replacingOccurrences(of: "file://", with: "")

                if knownIds.insert(projectId).inserted {
                    reconciled.append(
                        ProjectWorkspace(
                            id: projectId,
                            name: canonicalName,
                            pathDisplay: pathDisplay,
                            workspaceUri: effectiveUri,
                            runtime: isWsCloudOnly ? .cloud : .macBookPro,
                            hostName: isWsCloudOnly ? "Cloud" : resolvedLocalHost,
                            activeBranch: effectiveBranch,
                            worktrees: isNoProj ? [] : (matchedLocalWs?.worktrees.isEmpty == false ? matchedLocalWs!.worktrees : [effectiveBranch]),
                            isExpandedInHome: expandedById[projectId] ?? expandedById[canonicalName] ?? true,
                            originInstanceUuid: matchedLocalWs?.originInstanceUuid ?? firstLocal.originInstanceUuid
                        )
                    )
                }
            }
        }

        for slug in orderedBaseSlugs {
            let isNoProj = AntigravityCloudDetector.isNoProjectSlug(slug)
            let canonicalName = isNoProj ? AntigravityCloudDetector.noProjectDisplayName : slug
            let matchingIndices = summaries.indices.filter { baseSlug(for: summaries[$0].projectSlug) == slug }
            let cloudIndices = matchingIndices.filter { summaries[$0].isCloud }
            let localIndices = matchingIndices.filter { !summaries[$0].isCloud }

            let matchingWorkspaces = isNoProj ? [] : (wsByName[slug] ?? [])
            let cloudWs = matchingWorkspaces.first(where: \.isCloud)
            let localWorkspaces = matchingWorkspaces.filter { !$0.isCloud }
            let matchedCloudProj = isNoProj ? nil : cloudProjByName[slug]?.first

            if !cloudIndices.isEmpty && !localIndices.isEmpty {
                // Both active local Mac chats and active Cloud chats exist for the same group (`slug` or `No Project`):
                // keep local chats grouped per host and separate Cloud chats under `cloud:<canonicalName>`.
                appendLocalGroups(
                    canonicalName: canonicalName,
                    isNoProj: isNoProj,
                    localIndices: localIndices,
                    localWorkspaces: localWorkspaces,
                    cloudWs: nil,
                    summaries: &summaries,
                    reconciled: &reconciled,
                    knownIds: &knownIds
                )

                let cloudId = "cloud:\(canonicalName)"
                for idx in cloudIndices {
                    summaries[idx].projectSlug = cloudId
                }
                let firstCloud = summaries[cloudIndices[0]]
                let cloudUri = isNoProj
                    ? ""
                    : preferredCloudUri(matchedCloudProj?.workspaceUri ?? cloudWs?.workspaceUri, firstCloud.workspaceUri)
                let cloudBranch = isNoProj
                    ? ""
                    : (matchedCloudProj?.activeBranch ?? cloudWs?.activeBranch ?? firstCloud.branchName)
                let cloudPathDisplay = isNoProj ? "Antigravity Cloud · Unassigned" : cloudUri
                if knownIds.insert(cloudId).inserted {
                    reconciled.append(
                        ProjectWorkspace(
                            id: cloudId,
                            name: canonicalName,
                            pathDisplay: cloudPathDisplay,
                            workspaceUri: cloudUri,
                            runtime: .cloud,
                            hostName: "Cloud",
                            activeBranch: cloudBranch,
                            worktrees: isNoProj ? [] : (cloudWs?.worktrees.isEmpty == false ? cloudWs!.worktrees : [cloudBranch]),
                            isExpandedInHome: expandedById[cloudId] ?? true,
                            cloudProjectId: isNoProj ? nil : (matchedCloudProj?.cloudProjectId ?? matchedCloudProj?.id ?? firstCloud.cloudProjectId ?? existingById[cloudId]?.cloudProjectId),
                            originInstanceUuid: matchedCloudProj?.originInstanceUuid ?? firstCloud.originInstanceUuid
                        )
                    )
                }
            } else if !cloudIndices.isEmpty {
                for idx in cloudIndices {
                    summaries[idx].projectSlug = canonicalName
                }
                let firstCloud = summaries[cloudIndices[0]]
                let cloudUri = isNoProj
                    ? ""
                    : preferredCloudUri(matchedCloudProj?.workspaceUri ?? cloudWs?.workspaceUri, firstCloud.workspaceUri)
                let cloudBranch = isNoProj
                    ? ""
                    : (matchedCloudProj?.activeBranch ?? cloudWs?.activeBranch ?? firstCloud.branchName)
                let cloudPathDisplay = isNoProj ? "Antigravity Cloud · Unassigned" : cloudUri
                if knownIds.insert(canonicalName).inserted {
                    reconciled.append(
                        ProjectWorkspace(
                            id: canonicalName,
                            name: canonicalName,
                            pathDisplay: cloudPathDisplay,
                            workspaceUri: cloudUri,
                            runtime: .cloud,
                            hostName: "Cloud",
                            activeBranch: cloudBranch,
                            worktrees: isNoProj ? [] : (cloudWs?.worktrees.isEmpty == false ? cloudWs!.worktrees : [cloudBranch]),
                            isExpandedInHome: expandedById[canonicalName] ?? true,
                            cloudProjectId: isNoProj ? nil : (matchedCloudProj?.cloudProjectId ?? matchedCloudProj?.id ?? firstCloud.cloudProjectId ?? existingById[canonicalName]?.cloudProjectId),
                            originInstanceUuid: matchedCloudProj?.originInstanceUuid ?? firstCloud.originInstanceUuid
                        )
                    )
                }
            } else if !localIndices.isEmpty {
                appendLocalGroups(
                    canonicalName: canonicalName,
                    isNoProj: isNoProj,
                    localIndices: localIndices,
                    localWorkspaces: localWorkspaces,
                    cloudWs: cloudWs,
                    summaries: &summaries,
                    reconciled: &reconciled,
                    knownIds: &knownIds
                )
            }
        }

        // Append any open 0-conversation workspaces not yet represented above
        for ws in workspaces {
            let slug = ws.displayName
            guard !AntigravityCloudDetector.isNoProjectSlug(slug),
                  !AntigravityCloudDetector.isGenericContainerURI(ws.workspaceUri),
                  !AntigravityCloudDetector.isPlaygroundScratchURI(ws.workspaceUri) else {
                continue
            }
            let isCloud = ws.isCloud || AntigravityCloudDetector.isCloudWorkspaceURI(ws.workspaceUri)
            let wsHostName = ws.originHostName ?? hostName
            let alreadyRepresented = reconciled.contains { existing in
                guard !existing.workspaceUri.isEmpty,
                      existing.workspaceUri.caseInsensitiveCompare(ws.workspaceUri) == .orderedSame else {
                    return false
                }
                if isCloud || existing.runtime == .cloud {
                    return isCloud && existing.runtime == .cloud
                }
                if let eUuid = existing.originInstanceUuid, !eUuid.isEmpty,
                   let wUuid = ws.originInstanceUuid, !wUuid.isEmpty {
                    return eUuid == wUuid
                }
                return existing.hostName == wsHostName
            }
            if alreadyRepresented {
                continue
            }

            var targetId = slug
            if knownIds.contains(targetId) {
                if isCloud,
                   let idx = reconciled.firstIndex(where: { $0.id == slug }),
                   !summaries.contains(where: { $0.projectSlug == slug && !$0.isCloud }) {
                    let mergedUri = preferredCloudUri(reconciled[idx].workspaceUri, ws.workspaceUri)
                    reconciled[idx].runtime = .cloud
                    reconciled[idx].hostName = "Cloud"
                    reconciled[idx].workspaceUri = mergedUri
                    reconciled[idx].pathDisplay = mergedUri
                    continue
                }
                if !isCloud {
                    guard reconciled.contains(where: { $0.runtime == .macBookPro && $0.name == slug }) else {
                        continue
                    }
                    let wsHostKey = (ws.originInstanceUuid?.isEmpty == false) ? ws.originInstanceUuid! : wsHostName
                    let namespacedId = "host:\(wsHostKey):\(slug)"
                    let existingSameHost = reconciled.contains { existing in
                        existing.runtime == .macBookPro
                            && existing.name == slug
                            && ((existing.originInstanceUuid != nil && existing.originInstanceUuid == ws.originInstanceUuid)
                                || existing.hostName == wsHostName)
                    }
                    if existingSameHost || knownIds.contains(namespacedId) {
                        continue
                    }
                    targetId = namespacedId
                } else {
                    continue
                }
            }
            knownIds.insert(targetId)
            reconciled.append(
                ProjectWorkspace(
                    id: targetId,
                    name: slug,
                    pathDisplay: ws.workspaceUri.replacingOccurrences(of: "file://", with: ""),
                    workspaceUri: ws.workspaceUri,
                    runtime: isCloud ? .cloud : .macBookPro,
                    hostName: isCloud ? "Cloud" : wsHostName,
                    activeBranch: ws.activeBranch,
                    worktrees: ws.worktrees.isEmpty ? [ws.activeBranch] : ws.worktrees,
                    isExpandedInHome: expandedById[targetId] ?? expandedById[slug] ?? true,
                    originInstanceUuid: ws.originInstanceUuid
                )
            )
        }

        // Append any 0-conversation Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) projects
        for cp in cloudProjects {
            let cpid = cp.cloudProjectId ?? cp.id
            if let existingIdx = reconciled.firstIndex(where: {
                $0.cloudProjectId == cpid
                    || ($0.runtime == .cloud && $0.name.caseInsensitiveCompare(cp.name) == .orderedSame)
                    || ($0.runtime == .cloud && !cp.workspaceUri.isEmpty && $0.workspaceUri.caseInsensitiveCompare(cp.workspaceUri) == .orderedSame)
            }) {
                reconciled[existingIdx].cloudProjectId = reconciled[existingIdx].cloudProjectId ?? cpid
                reconciled[existingIdx].originInstanceUuid = reconciled[existingIdx].originInstanceUuid ?? cp.originInstanceUuid
                continue
            }
            let targetId = knownIds.contains(cp.name) ? "cloud:\(cp.name)" : cp.name
            guard knownIds.insert(targetId).inserted else { continue }
            reconciled.append(
                ProjectWorkspace(
                    id: targetId,
                    name: cp.name,
                    pathDisplay: cp.workspaceUri,
                    workspaceUri: cp.workspaceUri,
                    runtime: .cloud,
                    hostName: "Cloud",
                    activeBranch: cp.activeBranch,
                    worktrees: [cp.activeBranch],
                    isExpandedInHome: expandedById[targetId] ?? true,
                    cloudProjectId: cpid,
                    originInstanceUuid: cp.originInstanceUuid
                )
            )
        }

        // Preserve any user-created empty projects from `existingById` if workspaces didn't report them yet
        if reconciled.isEmpty {
            return nonDemoExisting.map { existing in
                var copy = existing
                if copy.runtime == .macBookPro {
                    copy.hostName = hostName
                }
                return copy
            }
        }

        // Keep all named projects first (preserving recency order) and `No Project` sections cleanly at the bottom
        let namedProjects = reconciled.filter { !$0.isNoProject }
        let unassignedProjects = reconciled.filter(\.isNoProject)
        return namedProjects + unassignedProjects
    }

    /// Queries the connected `language_server` / `agy` daemon for live models, dual-pool usage quota, custom agents, and Cloud GitHub repos.
    public func refreshModelCatalog(forceRefresh: Bool = false) async {
        guard let client = rpcClient else { return }
        let result = await client.fetchModelCatalog(forceRefresh: forceRefresh)
        if let quota = result.usageQuota {
            usageQuota = quota
            await projectionStore.saveUsageQuota(quota)
        }
        if !result.models.isEmpty {
            availableModels = result.models
            availableAgents = result.agents.isEmpty ? ["Default"] : result.agents

            let currentMode = selectedModelConfig.mode
            let currentPersona = availableAgents.contains(selectedModelConfig.agentPersona)
                ? selectedModelConfig.agentPersona
                : (availableAgents.first ?? "Default")

            let matchedModel: CascadeModelConfig = {
                if let exact = result.models.first(where: { $0.modelId == selectedModelConfig.modelId }) {
                    return exact
                }
                if let defId = result.defaultModelId,
                   let defMatch = result.models.first(where: { $0.modelId == defId }) {
                    return defMatch
                }
                return result.models[0]
            }()

            let preservedEffort = matchedModel.supportedEfforts.contains(selectedModelConfig.effort)
                ? selectedModelConfig.effort
                : matchedModel.effort

            selectedModelConfig = CascadeModelConfig(
                modelId: matchedModel.modelId,
                displayName: matchedModel.displayName,
                subtitle: matchedModel.subtitle,
                hasThinkingBadge: matchedModel.hasThinkingBadge,
                requiresUpgradeNote: matchedModel.requiresUpgradeNote,
                mode: matchedModel.isOrchestrator ? .planning : currentMode,
                agentPersona: currentPersona,
                effort: matchedModel.isOrchestrator ? .high : preservedEffort,
                isModelAlias: matchedModel.isModelAlias,
                badgeTitle: matchedModel.badgeTitle,
                isOrchestrator: matchedModel.isOrchestrator,
                plannerModelName: matchedModel.plannerModelName,
                executorModelName: matchedModel.executorModelName,
                supportedEfforts: matchedModel.supportedEfforts,
                isNewBadge: matchedModel.isNewBadge
            )
        }

        let cloudRepos = await client.fetchCloudGitHubRepos()
        if !cloudRepos.isEmpty {
            availableGitHubRepos = cloudRepos
        }
    }

    private func applyRecordedConversationConfig(from step: CascadeStep) {
        guard step.recordedExecutionMode != nil || step.recordedModelId != nil else { return }
        let nextMode = step.recordedExecutionMode ?? selectedModelConfig.mode
        var matchedModel: CascadeModelConfig? = nil
        if let rawId = step.recordedModelId, !rawId.isEmpty {
            let normalized = AntigravityRPCClient.normalizeProtoModelEnum(rawId)
            matchedModel = availableModels.first(where: {
                $0.modelId == rawId || AntigravityRPCClient.normalizeProtoModelEnum($0.modelId) == normalized
            })
        }
        if let m = matchedModel {
            selectedModelConfig = CascadeModelConfig(
                modelId: m.modelId,
                displayName: m.displayName,
                subtitle: m.subtitle,
                hasThinkingBadge: m.hasThinkingBadge,
                requiresUpgradeNote: m.requiresUpgradeNote,
                mode: m.isOrchestrator ? .planning : nextMode,
                agentPersona: selectedModelConfig.agentPersona,
                effort: m.effort,
                isModelAlias: m.isModelAlias,
                badgeTitle: m.badgeTitle,
                isOrchestrator: m.isOrchestrator,
                plannerModelName: m.plannerModelName,
                executorModelName: m.executorModelName,
                supportedEfforts: m.supportedEfforts,
                isNewBadge: m.isNewBadge
            )
        } else {
            selectedModelConfig.mode = nextMode
        }
    }

    private func applyVerifiedLiveConnection(
        host: RemoteHostInstance,
        client: AntigravityRPCClient,
        handshake: BackendHandshakeResult,
        preservedCachedSummaries: [CascadeSummary] = [],
        preservedCachedProjects: [ProjectWorkspace] = []
    ) {
        let wasAlreadyPairedLive = hasPairedBackend && !isVerificationMode
        var updatedHost = host
        updatedHost.latencyMs = handshake.latencyMs
        updatedHost.isOnline = true
        activeHost = updatedHost
        if let existingIdx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
            hosts[existingIdx] = updatedHost
        } else {
            hosts.insert(updatedHost, at: 0)
        }
        rpcClient = client
        consecutiveSyncFailures = 0
        reconnectAttemptCount = 0
        nextReconnectAt = nil
        lastBackendActivityAt = Date()
        lastFullSyncAt = Date()
        lastStreamReopenAttemptAt = .distantPast
        isDeviceNetworkReachable = true
        hasPairedBackend = true
        isLiveBackendConnected = true
        lastPingLatencyMs = handshake.latencyMs
        connectionErrorText = nil
        connectionStatusText = "Connected · \(updatedHost.hostname) · \(handshake.latencyMs)ms"
        connectionLifecyclePhase = .onlineIdle

        let refreshedLocalUuids: Set<String> = {
            var set: Set<String> = updatedHost.instanceId.isEmpty ? [] : [updatedHost.instanceId]
            for inst in handshake.availableRelayInstances where inst.status.isReachable {
                set.insert(inst.uuid)
            }
            return set
        }()
        let refreshedLocalNames: Set<String> = {
            var set: Set<String> = updatedHost.hostname.isEmpty ? [] : [updatedHost.hostname]
            for inst in handshake.availableRelayInstances where inst.status.isReachable {
                set.insert(inst.name)
            }
            return set
        }()
        let refreshedCloud = !handshake.cloudProjects.isEmpty
            || handshake.summaries.contains(where: \.isCloud)
            || (updatedHost.channel == .cloudRelay && !refreshedLocalUuids.isEmpty)
        let isSingleDirectHost = (updatedHost.channel == .directHost)

        var mergedWorkspaces = handshake.workspaces
        var mergedWorkspaceKeys = Set(mergedWorkspaces.map { ws in
            ws.isCloud
                ? "cloud|\(ws.workspaceUri.lowercased())"
                : "\(ws.originInstanceUuid ?? ws.originHostName ?? "local")|\(ws.workspaceUri.lowercased())"
        })

        let priorProjectsPool = preservedCachedProjects + (wasAlreadyPairedLive ? projects : [])
        for cachedProj in priorProjectsPool where cachedProj.runtime == .macBookPro
            && !cachedProj.isNoProject
            && !Self.esddFixtureProjectIds.contains(cachedProj.id)
            && !cachedProj.workspaceUri.isEmpty
            && !Self.itemBelongsToRefreshedScope(
                isCloud: false,
                originUuid: cachedProj.originInstanceUuid,
                originHost: cachedProj.hostName,
                refreshedLocalHostUuids: refreshedLocalUuids,
                refreshedLocalHostNames: refreshedLocalNames,
                refreshedCloud: refreshedCloud,
                fallbackActiveHostId: updatedHost.instanceId,
                fallbackActiveHostName: updatedHost.hostname,
                isSingleDirectHost: isSingleDirectHost
            ) {
            let wsKey = "\(cachedProj.originInstanceUuid ?? cachedProj.hostName)|\(cachedProj.workspaceUri.lowercased())"
            if mergedWorkspaceKeys.insert(wsKey).inserted {
                mergedWorkspaces.append(
                    WorkspaceInfo(
                        workspaceUri: cachedProj.workspaceUri,
                        displayName: cachedProj.name,
                        activeBranch: cachedProj.activeBranch,
                        worktrees: cachedProj.worktrees,
                        isCloud: false,
                        originInstanceUuid: cachedProj.originInstanceUuid,
                        originHostName: cachedProj.hostName
                    )
                )
            }
        }
        workspaces = mergedWorkspaces

        var combinedSummaries = handshake.summaries
        var seenCascadeIds = Set(combinedSummaries.map(\.cascadeId))
        let priorSummariesPool = (wasAlreadyPairedLive ? summaries : []) + preservedCachedSummaries
        for cached in priorSummariesPool where !seenCascadeIds.contains(cached.cascadeId)
            && !Self.esddFixtureCascadeIds.contains(cached.cascadeId)
            && !Self.itemBelongsToRefreshedScope(
                isCloud: cached.isCloud,
                originUuid: cached.originInstanceUuid,
                originHost: cached.originHostName,
                refreshedLocalHostUuids: refreshedLocalUuids,
                refreshedLocalHostNames: refreshedLocalNames,
                refreshedCloud: refreshedCloud,
                fallbackActiveHostId: updatedHost.instanceId,
                fallbackActiveHostName: updatedHost.hostname,
                isSingleDirectHost: isSingleDirectHost
            ) {
            seenCascadeIds.insert(cached.cascadeId)
            combinedSummaries.append(cached)
        }

        var sortedSummaries = combinedSummaries.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.cascadeId < rhs.cascadeId
        }
        let nextProjects = Self.reconcileLiveProjects(
            workspaces: mergedWorkspaces,
            summaries: &sortedSummaries,
            existingProjects: priorProjectsPool,
            hostName: updatedHost.hostname,
            cloudProjects: handshake.cloudProjects
        )
        summaries = sortedSummaries
        projects = nextProjects
        let defaultProject = nextProjects.first(where: { !$0.isNoProject }) ?? nextProjects.first
        if !wasAlreadyPairedLive || selectedProjectId.isEmpty || !nextProjects.contains(where: { $0.id == selectedProjectId }) {
            selectedProjectId = defaultProject?.id ?? ""
            selectedWorkspaceUri = defaultProject?.workspaceUri ?? ""
        }
        if !wasAlreadyPairedLive || activeCascadeId.isEmpty {
            activeCascadeId = sortedSummaries.first?.cascadeId ?? ""
        }

        // Clear offline ESDD demo state only when transitioning from unpaired demo mode to a live backend
        if !wasAlreadyPairedLive {
            stepsByCascadeId = [:]
            syncedConfigCascadeIds.removeAll()
            activeTurnDiffs = []
            pendingDraftConversation = nil
            composerWorkflowCommand = nil
            composerDraftText = ""
            composerAttachments = []
            automations = []
            lastAutomationsSyncAt = nil
        }
        stepLoadErrorText = nil
        automationsErrorText = nil
        isAutomationsAuthExpired = false

        var refreshedShardKeys = Set(refreshedLocalUuids.map { "host:\($0)" })
        if refreshedCloud {
            refreshedShardKeys.insert("cloud")
        }
        Task { [weak self] in
            await self?.persistHostProjections(refreshedHostKeys: refreshedShardKeys.isEmpty ? nil : refreshedShardKeys)
            await self?.refreshModelCatalog()
            await self?.refreshAutomations()
            await self?.replayPendingOutbox()
        }

        startSummarySubscriptionStream()
        if !activeCascadeId.isEmpty {
            syncStepsForCascade(activeCascadeId, pollUntilIdle: false)
        }
    }

    private func ensureSummaryEnvelopeStreamRunning() {
        guard !isVerificationMode, !isNetworkingSuspended, isDeviceNetworkReachable else { return }
        guard let client = rpcClient else { return }

        if localSummaryStreamTasks.isEmpty && cloudSummaryStreamTask == nil {
            let sinceLastOpen = Date().timeIntervalSince(lastStreamReopenAttemptAt)
            guard sinceLastOpen >= ConnectionPowerPolicy.minStreamReopenSpacingSeconds else { return }
            lastStreamReopenAttemptAt = Date()
        }

        let localTargets: [(key: String, uuid: String?, hostName: String)] = {
            if activeHost.channel == .cloudRelay {
                let reachable = availableRelayInstances.filter(\.status.isReachable)
                if !reachable.isEmpty {
                    return reachable.map { ($0.uuid, $0.uuid, $0.name) }
                }
                if !activeHost.instanceId.isEmpty && activeHost.instanceId != "unpaired" {
                    return [(activeHost.instanceId, activeHost.instanceId, activeHost.hostname)]
                }
                return []
            }
            return [("direct", nil, activeHost.hostname)]
        }()

        // Cancel local streams for instances that are no longer reachable
        let activeTargetKeys = Set(localTargets.map(\.key))
        for (existingKey, existingTask) in localSummaryStreamTasks where !activeTargetKeys.contains(existingKey) {
            existingTask.cancel()
            localSummaryStreamTasks.removeValue(forKey: existingKey)
        }
        if localSummaryStreamTasks.isEmpty {
            hasReceivedLocalStreamEvent = false
        }

        let generation = self.summaryStreamGeneration

        for target in localTargets where localSummaryStreamTasks[target.key] == nil {
            let targetKey = target.key
            let targetUuid = target.uuid
            let targetHostName = target.hostName
            localSummaryStreamTasks[targetKey] = Task { [weak self] in
                guard let stream = try? await client.subscribeEnvelopeStream(
                    method: "JetboxSubscribeToSummaries",
                    instanceUuidOverride: targetUuid
                ) else {
                    if let self, self.summaryStreamGeneration == generation {
                        self.localSummaryStreamTasks.removeValue(forKey: targetKey)
                        if self.localSummaryStreamTasks.isEmpty {
                            self.hasReceivedLocalStreamEvent = false
                        }
                    }
                    return
                }
                do {
                    for try await event in stream {
                        guard let self, !Task.isCancelled, self.summaryStreamGeneration == generation else { break }
                        self.hasReceivedLocalStreamEvent = true
                        self.lastBackendActivityAt = Date()
                        self.applyJetboxSummaryEvent(
                            event,
                            forceCloud: false,
                            originInstanceUuid: targetUuid,
                            originHostName: targetHostName
                        )
                    }
                    if let self, self.summaryStreamGeneration == generation {
                        self.localSummaryStreamTasks.removeValue(forKey: targetKey)
                        if self.localSummaryStreamTasks.isEmpty {
                            self.hasReceivedLocalStreamEvent = false
                        }
                    }
                } catch {
                    // Clear dead stream reference BEFORE running passive probe so it can reopen cleanly
                    if let self, self.summaryStreamGeneration == generation {
                        self.localSummaryStreamTasks.removeValue(forKey: targetKey)
                        if self.localSummaryStreamTasks.isEmpty {
                            self.hasReceivedLocalStreamEvent = false
                        }
                        if !Task.isCancelled,
                           !self.isNetworkingSuspended,
                           self.isDeviceNetworkReachable,
                           self.isLiveBackendConnected {
                            await self.performLightweightHeartbeatTick(allowFullReconciliation: false)
                        }
                    }
                }
            }
        }

        if cloudSummaryStreamTask == nil {
            cloudSummaryStreamTask = Task { [weak self] in
                let cloudTargetUuid: String? = {
                    guard let self else { return nil }
                    return self.activeHost.channel == .cloudRelay ? self.activeHost.instanceId : nil
                }()
                let resolvedCloudTarget: String?
                if cloudTargetUuid != nil {
                    resolvedCloudTarget = await client.currentPreferredCloudInstanceUuid() ?? cloudTargetUuid
                } else {
                    resolvedCloudTarget = nil
                }

                let payloads: [[String: JSONValue]] = [
                    ["backend": .string("BACKEND_TYPE_REMOTE_AICODE")],
                    ["backendType": .string("BACKEND_TYPE_REMOTE_AICODE")]
                ]
                for (idx, payload) in payloads.enumerated() {
                    guard !Task.isCancelled else { break }
                    guard let stream = try? await client.subscribeEnvelopeStream(
                        method: "JetboxSubscribeToSummaries",
                        requestPayload: payload,
                        instanceUuidOverride: resolvedCloudTarget
                    ) else {
                        break
                    }
                    do {
                        for try await event in stream {
                            guard let self, !Task.isCancelled, self.summaryStreamGeneration == generation else { break }
                            self.hasReceivedCloudStreamEvent = true
                            self.lastBackendActivityAt = Date()
                            self.applyJetboxSummaryEvent(
                                event,
                                forceCloud: true,
                                originInstanceUuid: resolvedCloudTarget,
                                originHostName: "Antigravity"
                            )
                        }
                        break
                    } catch let AntigravityRPCError.httpError(_, body)
                        where idx == 0 && body.lowercased().contains("unknown field \"backend\"") {
                        continue
                    } catch {
                        break
                    }
                }
                if let self, self.summaryStreamGeneration == generation {
                    self.cloudSummaryStreamTask = nil
                    self.hasReceivedCloudStreamEvent = false
                }
            }
        }
    }

    /// Subscribes to Connect-RPC 5-byte framed `JetboxSubscribeToSummaries` stream (Local & Cloud)
    /// AND runs a power-aware foreground scheduler:
    /// - Screen off / background (`isNetworkingSuspended`): zero streams, zero timers, zero radio wakeups.
    /// - iPhone no network (`!isDeviceNetworkReachable`): zero requests until `NWPathMonitor` reports recovery.
    /// - Online idle: relies on push stream + lightweight single-RPC heartbeat (`30s–60s` Relay / `15s–30s` LAN).
    /// - Host offline: exponential backoff with jitter (`3s → 6s → 12s → 24s → 45s → 60s`, ×2 in Low Power Mode).
    public func startSummarySubscriptionStream() {
        cancelAllSummaryStreams()
        summaryPollingTask?.cancel()
        summaryPollingTask = nil

        guard !isVerificationMode, !isNetworkingSuspended else { return }
        guard rpcClient != nil else { return }

        startNetworkPathMonitoringIfNeeded()
        guard isDeviceNetworkReachable else {
            connectionLifecyclePhase = .noNetwork
            connectionStatusText = "No Internet Connection"
            return
        }

        if isLiveBackendConnected && activeHost.isOnline {
            lastStreamReopenAttemptAt = .distantPast
            ensureSummaryEnvelopeStreamRunning()
            connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
        }

        summaryPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let sleepSeconds: TimeInterval? = {
                    guard let self,
                          !self.isNetworkingSuspended,
                          self.isDeviceNetworkReachable,
                          (self.hasPairedBackend || self.isLiveBackendConnected) else {
                        return nil
                    }
                    let isLowPower = self.isLowPowerModeEnabled
                    if self.isLiveBackendConnected && self.activeHost.isOnline {
                        let heartbeatInterval = ConnectionPowerPolicy.onlineHeartbeatInterval(
                            channel: self.activeHost.channel,
                            isLowPowerMode: isLowPower,
                            isExpensiveNetwork: self.isNetworkExpensiveOrConstrained,
                            isStreamHealthy: self.isSummaryStreamHealthy
                        )
                        let elapsedSinceActivity = Date().timeIntervalSince(self.lastBackendActivityAt)
                        return max(2.0, heartbeatInterval - elapsedSinceActivity)
                    } else {
                        let attempt = self.reconnectAttemptCount
                        let delaySeconds = ConnectionPowerPolicy.offlineBackoffDelay(
                            attempt: attempt,
                            isLowPowerMode: isLowPower,
                            applyJitter: true
                        )
                        self.nextReconnectAt = Date().addingTimeInterval(delaySeconds)
                        self.connectionLifecyclePhase = .offlineBackoff(
                            attempt: attempt,
                            nextRetrySeconds: delaySeconds
                        )
                        return delaySeconds
                    }
                }()
                guard let sleepSeconds else { break }

                try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                guard let self,
                      !Task.isCancelled,
                      !self.isNetworkingSuspended,
                      self.isDeviceNetworkReachable,
                      (self.hasPairedBackend || self.isLiveBackendConnected) else {
                    break
                }

                if self.isLiveBackendConnected && self.activeHost.isOnline {
                    let streamHealthy = self.isSummaryStreamHealthy
                    let heartbeatInterval = ConnectionPowerPolicy.onlineHeartbeatInterval(
                        channel: self.activeHost.channel,
                        isLowPowerMode: self.isLowPowerModeEnabled,
                        isExpensiveNetwork: self.isNetworkExpensiveOrConstrained,
                        isStreamHealthy: streamHealthy
                    )
                    let fullSyncInterval = ConnectionPowerPolicy.onlineFullSyncInterval(
                        channel: self.activeHost.channel,
                        isLowPowerMode: self.isLowPowerModeEnabled
                    )
                    let needsFullSync = Date().timeIntervalSince(self.lastFullSyncAt) >= fullSyncInterval
                        || !streamHealthy
                    let refreshedElapsed = Date().timeIntervalSince(self.lastBackendActivityAt)

                    // Skip redundant heartbeat if push events or user RPCs already proved liveness recently
                    if refreshedElapsed < heartbeatInterval * 0.8 && !needsFullSync {
                        continue
                    }

                    await self.performLightweightHeartbeatTick(allowFullReconciliation: needsFullSync)
                } else {
                    let recovered = await self.performOfflineRecoveryProbe()
                    if !recovered {
                        self.reconnectAttemptCount = min(
                            self.reconnectAttemptCount + 1,
                            ConnectionPowerPolicy.offlineBackoffScheduleSeconds.count
                        )
                    }
                }
            }
        }
    }

    /// Resolves the freshest known display name for a local host UUID from `availableRelayInstances` / `hosts`,
    /// falling back cleanly to `fallback` or `activeHost.hostname`.
    public func resolvedHostName(forInstanceUuid instanceUuid: String?, fallback: String? = nil) -> String {
        if let uuid = instanceUuid, !uuid.isEmpty {
            if let inst = availableRelayInstances.first(where: { $0.uuid == uuid }) {
                return inst.name
            }
            if let host = hosts.first(where: { $0.instanceId == uuid }) {
                return host.hostname
            }
            if activeHost.instanceId == uuid {
                return activeHost.hostname
            }
        }
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback
        }
        return activeHost.hostname
    }

    /// Returns live online status for a specific host UUID (consistent with per-device Relay reachability).
    public func isHostOnline(forInstanceUuid instanceUuid: String?) -> Bool {
        guard hasPairedBackend else { return true }
        guard isDeviceNetworkReachable && isLiveBackendConnected else { return false }
        if let uuid = instanceUuid, !uuid.isEmpty {
            if let inst = availableRelayInstances.first(where: { $0.uuid == uuid }) {
                return inst.status.isReachable
            }
            if let host = hosts.first(where: { $0.instanceId == uuid }) {
                return host.isOnline
            }
        }
        return activeHost.isOnline
    }

    internal func syncRelayInstancesToHosts(
        _ relayInstances: [RelayInstanceInfo],
        latencyMs: Int? = nil,
        preferredActiveInstance: RelayInstanceInfo? = nil,
        relayOriginPrefix: String? = nil,
        persistKeychainIfChanged: Bool = true
    ) {
        guard !relayInstances.isEmpty else { return }
        let previousActiveId = activeHost.instanceId
        let previousActiveHostname = activeHost.hostname
        availableRelayInstances = relayInstances

        let originPrefix: String = {
            if let relayOriginPrefix, !relayOriginPrefix.isEmpty {
                return relayOriginPrefix
            }
            let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(activeHost.endpointURL.absoluteString)
            return parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin
        }()
        let effectiveLatency = latencyMs ?? lastPingLatencyMs ?? activeHost.latencyMs
        let seenIds = Set(relayInstances.map(\.uuid))

        hosts.removeAll { $0.instanceId == "unpaired" }

        for inst in relayInstances {
            let instURL = URL(string: "\(originPrefix)/r/\(inst.uuid)") ?? activeHost.endpointURL
            let peerHost = RemoteHostInstance(
                instanceId: inst.uuid,
                hostname: inst.name,
                version: inst.version,
                channel: .cloudRelay,
                endpointURL: instURL,
                isOnline: inst.status.isReachable,
                latencyMs: effectiveLatency
            )
            if let idx = hosts.firstIndex(where: { $0.instanceId == inst.uuid }) {
                hosts[idx] = peerHost
                hosts.removeAll {
                    $0.channel == .cloudRelay && $0.instanceId != inst.uuid && $0.instanceId == inst.name
                }
            } else if let slugIdx = hosts.firstIndex(where: { $0.channel == .cloudRelay && $0.instanceId == inst.name }) {
                hosts[slugIdx] = peerHost
            } else {
                hosts.append(peerHost)
            }
        }

        // Any previously cached Cloud Relay device absent from the latest ListInstances snapshot is no longer online
        for idx in hosts.indices where hosts[idx].channel == .cloudRelay && !seenIds.contains(hosts[idx].instanceId) {
            if hosts[idx].instanceId != "unpaired" {
                hosts[idx].isOnline = false
            }
        }

        if let activeInst = preferredActiveInstance {
            let nextURL = URL(string: "\(originPrefix)/r/\(activeInst.uuid)") ?? activeHost.endpointURL
            let refreshedHost = RemoteHostInstance(
                instanceId: activeInst.uuid,
                hostname: activeInst.name,
                version: activeInst.version,
                channel: .cloudRelay,
                endpointURL: nextURL,
                isOnline: activeInst.status.isReachable,
                latencyMs: effectiveLatency
            )
            activeHost = refreshedHost
            if let idx = hosts.firstIndex(where: { $0.instanceId == refreshedHost.instanceId }) {
                hosts[idx] = refreshedHost
            } else {
                hosts.insert(refreshedHost, at: 0)
            }
        } else if activeHost.channel == .cloudRelay,
                  let matchedActive = relayInstances.first(where: { $0.uuid == activeHost.instanceId }) {
            var updatedActive = activeHost
            updatedActive.hostname = matchedActive.name
            updatedActive.version = matchedActive.version
            updatedActive.isOnline = matchedActive.status.isReachable
            updatedActive.latencyMs = effectiveLatency
            activeHost = updatedActive
            if let idx = hosts.firstIndex(where: { $0.instanceId == updatedActive.instanceId }) {
                hosts[idx] = updatedActive
            }
        }

        if isLiveBackendConnected && activeHost.isOnline {
            if let pingMs = latencyMs ?? lastPingLatencyMs {
                connectionStatusText = "Connected · \(activeHost.hostname) · \(pingMs)ms"
            } else {
                connectionStatusText = "Connected · \(activeHost.hostname)"
            }
        } else if hasPairedBackend && !activeHost.isOnline {
            connectionStatusText = "Offline · \(activeHost.hostname)"
        }

        var newNameByUuid: [String: String] = [:]
        for inst in relayInstances {
            newNameByUuid[inst.uuid] = inst.name
        }
        newNameByUuid[activeHost.instanceId] = activeHost.hostname

        let activeUuidRotated = previousActiveId != activeHost.instanceId
            && previousActiveId != "unpaired"
            && previousActiveId != "auto"
            && !previousActiveId.isEmpty
            && newNameByUuid[previousActiveId] == nil
        let activeNameChanged = previousActiveHostname != activeHost.hostname
        let previousNameStillPresent = newNameByUuid.values.contains(previousActiveHostname)

        if case let .localHost(fid, fname) = hostFilter {
            if let freshName = newNameByUuid[fid], freshName != fname {
                hostFilter = .localHost(id: fid, name: freshName)
            } else if activeUuidRotated && fid == previousActiveId {
                hostFilter = .localHost(id: activeHost.instanceId, name: activeHost.hostname)
            }
        }

        for idx in workspaces.indices where !workspaces[idx].isCloud {
            if let u = workspaces[idx].originInstanceUuid {
                if let freshName = newNameByUuid[u] {
                    workspaces[idx].originHostName = freshName
                } else if activeUuidRotated && u == previousActiveId {
                    workspaces[idx].originInstanceUuid = activeHost.instanceId
                    workspaces[idx].originHostName = activeHost.hostname
                }
            } else if activeNameChanged && !previousNameStillPresent && workspaces[idx].originHostName == previousActiveHostname {
                workspaces[idx].originHostName = activeHost.hostname
            }
        }

        var summariesChanged = false
        for idx in summaries.indices where !summaries[idx].isCloud {
            if let u = summaries[idx].originInstanceUuid {
                if let freshName = newNameByUuid[u] {
                    if summaries[idx].originHostName != freshName {
                        summaries[idx].originHostName = freshName
                        summariesChanged = true
                    }
                } else if activeUuidRotated && u == previousActiveId {
                    summaries[idx].originInstanceUuid = activeHost.instanceId
                    summaries[idx].originHostName = activeHost.hostname
                    summariesChanged = true
                }
            } else if activeNameChanged && !previousNameStillPresent && summaries[idx].originHostName == previousActiveHostname {
                summaries[idx].originHostName = activeHost.hostname
                summariesChanged = true
            }
        }

        var projectsChanged = false
        for idx in projects.indices where projects[idx].runtime != .cloud {
            if let u = projects[idx].originInstanceUuid {
                if let freshName = newNameByUuid[u] {
                    if projects[idx].hostName != freshName {
                        projects[idx].hostName = freshName
                        if projects[idx].isNoProject {
                            projects[idx].pathDisplay = "Unassigned · \(freshName)"
                        }
                        projectsChanged = true
                    }
                } else if activeUuidRotated && u == previousActiveId {
                    projects[idx].originInstanceUuid = activeHost.instanceId
                    projects[idx].hostName = activeHost.hostname
                    if projects[idx].isNoProject {
                        projects[idx].pathDisplay = "Unassigned · \(activeHost.hostname)"
                    }
                    projectsChanged = true
                }
            } else if activeNameChanged && !previousNameStillPresent && projects[idx].hostName == previousActiveHostname {
                projects[idx].hostName = activeHost.hostname
                if projects[idx].isNoProject {
                    projects[idx].pathDisplay = "Unassigned · \(activeHost.hostname)"
                }
                projectsChanged = true
            }
        }

        if !isVerificationMode && (projectsChanged || summariesChanged) {
            let storeRef = projectionStore
            let projectsSnapshot = projectsChanged ? projects : nil
            let summariesSnapshot = summariesChanged ? summaries : nil
            Task {
                if let projectsSnapshot {
                    await storeRef.saveProjects(projectsSnapshot)
                }
                if let summariesSnapshot {
                    await storeRef.saveProjectedSummaries(summariesSnapshot)
                }
            }
        }

        if persistKeychainIfChanged
            && !isVerificationMode
            && hasPairedBackend
            && activeHost.channel == .cloudRelay
            && (activeNameChanged || previousActiveId != activeHost.instanceId) {
            let updatedHostname = activeHost.hostname
            let updatedUuid = activeHost.instanceId
            let updatedEndpoint = activeHost.endpointURL.absoluteString
            let updatedAuthUser = activeAuthUser
            Task {
                if var saved = await KeychainStore.shared.loadCredentials(),
                   saved.channel == .cloudRelay {
                    var changed = false
                    if saved.hostname != updatedHostname {
                        saved.hostname = updatedHostname
                        changed = true
                    }
                    if saved.resolvedInstanceUuid != updatedUuid {
                        saved.resolvedInstanceUuid = updatedUuid
                        changed = true
                    }
                    if saved.endpointURLString != updatedEndpoint {
                        saved.endpointURLString = updatedEndpoint
                        changed = true
                    }
                    if !updatedAuthUser.isEmpty && saved.authUser != updatedAuthUser {
                        saved.authUser = updatedAuthUser
                        changed = true
                    }
                    if changed {
                        await KeychainStore.shared.saveCredentials(saved)
                    }
                }
            }
        }
    }

    internal func syncRelayInstancesState(
        _ instances: [RelayInstanceInfo],
        latencyMs: Int,
        relayOriginPrefix: String? = nil
    ) {
        syncRelayInstancesToHosts(
            instances,
            latencyMs: latencyMs,
            preferredActiveInstance: nil,
            relayOriginPrefix: relayOriginPrefix
        )
    }

    private func applyRelayProbeMetadata(_ probe: HostReachabilityProbeResult) {
        lastPingLatencyMs = probe.latencyMs
        if !probe.availableRelayInstances.isEmpty {
            let pinnedToSpecificHost: Bool = {
                if case .localHost(let fid, _) = hostFilter {
                    return fid == activeHost.instanceId && probe.availableRelayInstances.contains(where: { $0.uuid == fid })
                }
                return false
            }()
            syncRelayInstancesToHosts(
                probe.availableRelayInstances,
                latencyMs: probe.latencyMs,
                preferredActiveInstance: pinnedToSpecificHost ? nil : probe.activeRelayInstance
            )
        } else if let activeInst = probe.activeRelayInstance {
            syncRelayInstancesToHosts(
                [activeInst],
                latencyMs: probe.latencyMs,
                preferredActiveInstance: activeInst
            )
        } else {
            var updatedHost = activeHost
            updatedHost.latencyMs = probe.latencyMs
            updatedHost.isOnline = true
            activeHost = updatedHost
            if let idx = hosts.firstIndex(where: { $0.instanceId == updatedHost.instanceId }) {
                hosts[idx] = updatedHost
            }
            connectionStatusText = "Connected · \(activeHost.hostname) · \(probe.latencyMs)ms"
        }
    }

    /// On-demand live refresh of available Cloud Relay hosts (called when opening or pulling-to-refresh Settings).
    /// Performs end-to-end `ProxyCommand` verification per host so offline/stale Relay entries flip to `Offline` immediately,
    /// coalescing overlapping refreshes into a single in-flight probe.
    public func refreshAvailableRelayHosts(verifyEndToEnd: Bool = true) async {
        guard !isVerificationMode, !isNetworkingSuspended, hasPairedBackend, isDeviceNetworkReachable else { return }
        guard let client = rpcClient else { return }
        if activeHost.channel != .cloudRelay {
            await reconnectNow(userInitiated: true)
            return
        }

        if let existingTask = inFlightRelayHostsProbeTask {
            await existingTask.value
            return
        }

        isRefreshingRelayHosts = true
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.inFlightRelayHostsProbeTask = nil
                self.isRefreshingRelayHosts = false
            }

            do {
                let probe = try await client.probeHostReachability(
                    timeoutInterval: 8.0,
                    verifyEndToEnd: verifyEndToEnd
                )
                self.consecutiveSyncFailures = 0
                self.reconnectAttemptCount = 0
                self.nextReconnectAt = nil
                self.lastBackendActivityAt = Date()
                self.applyRelayProbeMetadata(probe)
                if !self.isLiveBackendConnected || !self.activeHost.isOnline {
                    self.markBackendReconnected()
                } else {
                    self.connectionErrorText = nil
                }
                if probe.relayTopologyChanged {
                    await self.refreshWorkspacesAndSummaries(
                        forceFullSync: true,
                        includeAutomations: false,
                        skipRelayMetadataProbe: true
                    )
                }
            } catch {
                let latestInstances = await client.cachedInstancesSnapshot()
                if !latestInstances.isEmpty {
                    self.syncRelayInstancesState(
                        latestInstances,
                        latencyMs: self.lastPingLatencyMs ?? self.activeHost.latencyMs
                    )
                }
                if Self.isBackendOfflineError(error) {
                    self.markBackendOffline(error: error)
                }
            }
        }
        inFlightRelayHostsProbeTask = task
        await task.value
    }

    private func performLightweightHeartbeatTick(allowFullReconciliation: Bool) async {
        guard !isNetworkingSuspended, isDeviceNetworkReachable, let client = rpcClient else { return }
        let isRelay = (activeHost.channel == .cloudRelay)
        let probeTimeout: TimeInterval = isRelay ? 8.0 : 3.0

        do {
            let probe = try await client.probeHostReachability(timeoutInterval: probeTimeout)
            consecutiveSyncFailures = 0
            reconnectAttemptCount = 0
            nextReconnectAt = nil
            lastBackendActivityAt = Date()
            applyRelayProbeMetadata(probe)

            if !isLiveBackendConnected || !activeHost.isOnline {
                markBackendReconnected()
            } else {
                connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
            }

            if probe.relayTopologyChanged {
                cancelAllSummaryStreams()
                lastStreamReopenAttemptAt = .distantPast
                ensureSummaryEnvelopeStreamRunning()
                await refreshWorkspacesAndSummaries(
                    forceFullSync: true,
                    includeAutomations: false,
                    skipRelayMetadataProbe: true
                )
            } else {
                let missingLocalStream = localSummaryStreamTasks.isEmpty
                    || (isRelay && availableRelayInstances.contains { $0.status.isReachable && localSummaryStreamTasks[$0.uuid] == nil })
                let missingCloudStream = (cloudSummaryStreamTask == nil)
                if missingLocalStream || missingCloudStream {
                    ensureSummaryEnvelopeStreamRunning()
                }
                if allowFullReconciliation {
                    await refreshWorkspacesAndSummaries(
                        forceFullSync: false,
                        includeAutomations: false,
                        skipRelayMetadataProbe: true
                    )
                }
            }
        } catch {
            if Self.isBackendOfflineError(error) {
                consecutiveSyncFailures += 1
                let threshold = ConnectionPowerPolicy.offlineFailureThreshold(
                    channel: activeHost.channel,
                    error: error
                )
                if consecutiveSyncFailures >= threshold {
                    markBackendOffline(error: error)
                }
            }
        }
    }

    private func performOfflineRecoveryProbe() async -> Bool {
        guard !isNetworkingSuspended, isDeviceNetworkReachable, let client = rpcClient else { return false }
        let isRelay = (activeHost.channel == .cloudRelay)
        let probeTimeout: TimeInterval = isRelay ? 8.0 : 3.0

        do {
            let probe = try await client.probeHostReachability(timeoutInterval: probeTimeout)
            applyRelayProbeMetadata(probe)
            markBackendReconnected()
            await refreshWorkspacesAndSummaries(
                forceFullSync: true,
                includeAutomations: selectedTab == .automations,
                skipRelayMetadataProbe: true
            )
            return true
        } catch {
            if Self.isBackendOfflineError(error) {
                connectionErrorText = error.localizedDescription
                if case AntigravityRPCError.unauthorized = error {
                    // Auth expired requires user re-sign-in; immediately cap backoff to avoid noisy 401 retries
                    reconnectAttemptCount = ConnectionPowerPolicy.offlineBackoffScheduleSeconds.count
                    connectionStatusText = isRelay ? "Google Sign-In Expired" : "Offline · \(activeHost.hostname) (Auth Expired)"
                } else {
                    connectionStatusText = "Offline · \(activeHost.hostname)"
                }
            }
            return false
        }
    }

    /// Handles both Antigravity 2.0.11+ `{"updates": {"<cascadeId>": {...}}, "deletes": [...]}` frames
    /// and single-cascade `{"cascadeId": "...", "status": "..."}` frames.
    private func applyJetboxSummaryEvent(
        _ event: [String: JSONValue],
        forceCloud: Bool = false,
        originInstanceUuid: String? = nil,
        originHostName: String? = nil
    ) {
        var changedIds = Set<String>()
        let existingCloudProjects = projects.filter { $0.runtime == .cloud }
        let cloudProjById: [String: ProjectWorkspace] = Dictionary(
            existingCloudProjects.map { cp in (cp.cloudProjectId ?? cp.id, cp) },
            uniquingKeysWith: { first, _ in first }
        )

        let effectiveOriginUuid = originInstanceUuid ?? activeHost.instanceId
        let effectiveOriginHost = forceCloud ? "Antigravity" : (originHostName ?? activeHost.hostname)

        let decodedBatch = AntigravityRPCClient.decodeJetboxSummariesEvent(
            event,
            forceCloud: forceCloud,
            originInstanceUuid: effectiveOriginUuid,
            originHostName: effectiveOriginHost,
            cloudProjectsById: cloudProjById
        )
        if !decodedBatch.upserts.isEmpty {
            let now = Date()
            for decoded in decodedBatch.upserts {
                let cid = decoded.cascadeId
                changedIds.insert(cid)
                if let idx = summaries.firstIndex(where: { $0.cascadeId == cid }) {
                    let existing = summaries[idx]
                    let prevStepCount = existing.stepCount
                    var merged = decoded
                    if existing.title != "New Conversation" && merged.title == "New Conversation" {
                        merged.title = existing.title
                    }
                    if existing.isCloud && !merged.isCloud {
                        merged.isCloud = true
                        merged.originHostName = "Antigravity"
                    }
                    merged.isPinned = existing.isPinned || decoded.isPinned
                    merged.isArchived = existing.isArchived || decoded.isArchived
                    merged.stepCount = max(prevStepCount, decoded.stepCount)
                    merged.currentStepIndex = max(1, merged.stepCount)
                    merged.totalSteps = max(1, merged.stepCount)
                    merged.cloudProjectId = decoded.cloudProjectId ?? existing.cloudProjectId

                    // Prevent a different peer window's stale IDLE snapshot from clobbering an active run at equal stepCount
                    let sameOrigin = (decoded.originInstanceUuid == nil)
                        || (existing.originInstanceUuid == nil)
                        || (decoded.originInstanceUuid == existing.originInstanceUuid)
                    if !sameOrigin
                        && decoded.stepCount <= prevStepCount
                        && (existing.status == .inProgress || existing.status == .pending || existing.status == .waiting || existing.status == .blocked)
                        && (merged.status == .unspecified || merged.status == .done) {
                        merged.status = existing.status
                        merged.originInstanceUuid = existing.originInstanceUuid
                        merged.originHostName = existing.originHostName
                    }

                    if let optimisticExpiry = optimisticActiveUntilByCascadeId[cid],
                       optimisticExpiry > now,
                       merged.status != .waiting && merged.status != .blocked && merged.status != .error {
                        merged.status = .inProgress
                    }

                    let latestViewed = [existing.lastUserViewTime, decoded.lastUserViewTime].compactMap { $0 }.max()
                    merged.lastUserViewTime = latestViewed

                    let hasNewActivity = merged.stepCount > prevStepCount
                        || decoded.updatedAt.timeIntervalSince(existing.updatedAt) > 0.5
                    if hasNewActivity {
                        if activeRoute != .cascadeChat(cid) {
                            merged.isUnread = (merged.status != .inProgress && merged.status != .pending)
                            locallyViewedAtByCascadeId.removeValue(forKey: cid)
                        } else {
                            merged.isUnread = false
                            locallyViewedAtByCascadeId[cid] = now
                        }
                    } else if merged.status == .inProgress || merged.status == .pending {
                        merged.isUnread = false
                    } else if let latestViewed {
                        merged.isUnread = merged.updatedAt.timeIntervalSince(latestViewed) > 0.5
                            || merged.status == .waiting
                            || merged.status == .blocked
                    } else {
                        merged.isUnread = decoded.isUnread || existing.isUnread
                    }

                    if let localViewed = locallyViewedAtByCascadeId[cid], merged.updatedAt <= localViewed {
                        merged.isUnread = false
                    }

                    merged.statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                        status: merged.status,
                        stepCount: merged.stepCount,
                        isUnread: merged.isUnread
                    )
                    summaries[idx] = merged
                } else {
                    var fresh = decoded
                    if let localViewed = locallyViewedAtByCascadeId[cid], fresh.updatedAt <= localViewed {
                        fresh.isUnread = false
                        fresh.statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                            status: fresh.status,
                            stepCount: fresh.stepCount,
                            isUnread: false
                        )
                    }
                    summaries.insert(fresh, at: 0)
                }
            }

            var byIdMap: [String: CascadeSummary] = Dictionary(
                summaries.map { ($0.cascadeId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            AntigravityRPCClient.reconcileBatchUnreadStates(&byIdMap, now: now)
            for idx in summaries.indices {
                if let reconciled = byIdMap[summaries[idx].cascadeId] {
                    if let localViewed = locallyViewedAtByCascadeId[reconciled.cascadeId],
                       reconciled.updatedAt <= localViewed {
                        continue
                    }
                    summaries[idx] = reconciled
                }
            }

            var updatedSummaries = summaries.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.cascadeId < rhs.cascadeId
            }
            projects = Self.reconcileLiveProjects(
                workspaces: workspaces,
                summaries: &updatedSummaries,
                existingProjects: projects,
                hostName: activeHost.hostname,
                cloudProjects: existingCloudProjects
            )
            summaries = updatedSummaries
        }

        if !decodedBatch.deletes.isEmpty {
            let deletedIds = Set(decodedBatch.deletes)
            summaries.removeAll { deletedIds.contains($0.cascadeId) }
        }

        if let cid = event["cascadeId"]?.stringValue {
            changedIds.insert(cid)
            let statusRaw = event["status"]?.stringValue ?? "CORTEX_STEP_STATUS_IN_PROGRESS"
            let newStatus = CortexStepStatus.from(jsonName: statusRaw)
            let stepCount = event["stepCount"]?.intValue
            let title = event["title"]?.stringValue
            if let idx = summaries.firstIndex(where: { $0.cascadeId == cid }) {
                summaries[idx].status = newStatus
                if let stepCount { summaries[idx].stepCount = stepCount }
                if let title, !title.isEmpty { summaries[idx].title = title }
                summaries[idx].updatedAt = Date()
                summaries[idx].relativeTimeLabel = "now"
                summaries[idx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                    status: newStatus,
                    stepCount: summaries[idx].stepCount,
                    isUnread: summaries[idx].isUnread,
                    explicitSubtitle: event["summary"]?.stringValue
                )
            }
        }

        if isLiveBackendConnected && activeHost.isOnline {
            connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
        }

        if (!changedIds.isEmpty || !decodedBatch.deletes.isEmpty) && (hasPairedBackend || isLiveBackendConnected) {
            let shardKey = Self.projectionHostKey(
                isCloud: forceCloud,
                instanceId: effectiveOriginUuid,
                hostname: effectiveOriginHost,
                fallbackHostId: activeHost.instanceId,
                fallbackHostName: activeHost.hostname
            )
            Task { [weak self] in
                await self?.persistHostProjections(refreshedHostKeys: [shardKey])
            }
        }

        if !activeCascadeId.isEmpty && changedIds.contains(activeCascadeId) {
            syncStepsForCascade(activeCascadeId, pollUntilIdle: activeRoute == .cascadeChat(activeCascadeId))
        }
    }

    /// Reconciles summary streaming state from fetched trajectory steps without prematurely flipping
    /// an active turn to `.done` while the agent is preparing its first step or thinking between tool calls.
    public static func reconcileSummaryStreamingStatus(
        currentStatus: CortexStepStatus,
        remoteSteps: [CascadeStep],
        withinOptimisticSendWindow: Bool
    ) -> (status: CortexStepStatus, stillActive: Bool) {
        if remoteSteps.contains(where: { $0.status == .waiting || $0.status == .blocked }) {
            return (.waiting, false)
        }
        if remoteSteps.contains(where: { $0.status == .inProgress || $0.status == .pending }) {
            return (.inProgress, true)
        }
        if let lastStep = remoteSteps.last, (lastStep.status == .error || lastStep.status == .cancelled) {
            return (lastStep.status, false)
        }

        let lastUserIdx = remoteSteps.lastIndex(where: { $0.type == .userInput })
        let turnTail: ArraySlice<CascadeStep> = {
            if let lastUserIdx {
                return remoteSteps[(lastUserIdx + 1)...]
            }
            return remoteSteps[...]
        }()
        let hasCompletedAssistantReply = turnTail.contains { step in
            (step.type == .plannerResponse || step.type == .notifyUser)
                && step.status == .done
                && !(step.plannerResponse?.response ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let lastVisible = remoteSteps.last(where: { $0.hasRenderableChatContent }) ?? remoteSteps.last
        let endsMidTurn: Bool = {
            guard let lastVisible else { return remoteSteps.isEmpty }
            if lastVisible.status == .error || lastVisible.status == .cancelled {
                return false
            }
            switch lastVisible.type {
            case .userInput, .taskBoundary, .viewFile, .viewContentChunk, .search, .listDirectory, .codeAction:
                return true
            case .runCommand:
                return lastVisible.runCommand?.exitCode == nil || !hasCompletedAssistantReply
            default:
                return false
            }
        }()

        if withinOptimisticSendWindow && !hasCompletedAssistantReply {
            return (.inProgress, true)
        }
        if currentStatus == .inProgress || currentStatus == .pending {
            if hasCompletedAssistantReply && !endsMidTurn {
                return (.done, false)
            }
            if remoteSteps.isEmpty || endsMidTurn || !hasCompletedAssistantReply {
                return (.inProgress, true)
            }
            return (.done, false)
        }
        return (currentStatus, false)
    }

    /// Synchronizes `GetCascadeTrajectorySteps` (`stepOffset` JSON `<600`, Binary Protobuf `>=600`) for `cascadeId`.
    /// Polls adaptively ONLY while an agent turn is actively streaming (`500ms` LAN / `1.0s` Relay; slowed in Low Power Mode).
    /// When the conversation is idle and the push stream is healthy, stops polling completely (0 idle RPCs) and relies
    /// on `JetboxSubscribeToSummaries` to wake step sync on demand.
    public func syncStepsForCascade(_ cascadeId: String, pollUntilIdle: Bool = true) {
        stepPollingTask?.cancel()
        stepPollingTask = nil
        stepSyncGeneration &+= 1
        let generation = stepSyncGeneration
        guard !isNetworkingSuspended else { return }
        guard (hasPairedBackend || isLiveBackendConnected), !cascadeId.isEmpty else { return }

        stepLoadErrorText = nil

        // Local optimistic IDs (`cas-<8hex>`) have not been materialized on the server via `StartCascade` yet.
        // Never show a stuck "Loading conversation history..." spinner or `not_found` error on them.
        if cascadeId.hasPrefix("cas-") && !Self.esddFixtureCascadeIds.contains(cascadeId) {
            isLoadingSteps = false
            return
        }

        let initialSummary = summaries.first(where: { $0.cascadeId == cascadeId })
        let withinInitialOptimisticSend = (optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
        let isBrandNewEmptySession = locallyCreatedEmptyCascadeIds.contains(cascadeId)
            && !withinInitialOptimisticSend
        let summaryHostOnline = isSummaryHostOnline(initialSummary)
        let isKnownOfflineLocal = hasPairedBackend
            && !summaryHostOnline
            && (initialSummary?.isCloud != true)
        let storeRef = projectionStore

        // Offline device / no network / pre-handshake cold start: serve persisted steps immediately from disk
        // without issuing cross-host failover RPCs against another online Mac.
        guard isDeviceNetworkReachable, !isKnownOfflineLocal, let client = rpcClient else {
            isLoadingSteps = false
            let offlineHostLabel = initialSummary?.originHostName ?? activeHost.hostname
            let shouldNoteUncachedOffline = isKnownOfflineLocal && !isBrandNewEmptySession
            if (stepsByCascadeId[cascadeId] ?? []).isEmpty {
                stepPollingTask = Task { [weak self] in
                    defer {
                        if let self, self.stepSyncGeneration == generation {
                            self.stepPollingTask = nil
                        }
                    }
                    let cached = await storeRef.loadProjectedSteps(cascadeId: cascadeId)
                    guard let self, !Task.isCancelled, self.stepSyncGeneration == generation else { return }
                    if !cached.isEmpty {
                        if (self.stepsByCascadeId[cascadeId] ?? []).isEmpty {
                            self.stepsByCascadeId[cascadeId] = cached
                            self.harvestEmbedResources(from: cached)
                        }
                        if self.activeCascadeId == cascadeId {
                            self.stepLoadErrorText = nil
                        }
                    } else if shouldNoteUncachedOffline && self.activeCascadeId == cascadeId {
                        self.stepLoadErrorText = "\(offlineHostLabel) is currently offline and this conversation has not been cached on this device yet."
                    }
                }
            }
            return
        }

        if (stepsByCascadeId[cascadeId] ?? []).isEmpty && !isBrandNewEmptySession {
            isLoadingSteps = true
        } else {
            isLoadingSteps = false
        }

        stepPollingTask = Task { [weak self] in
            defer {
                if let self,
                   self.stepSyncGeneration == generation {
                    if self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                    }
                    self.stepPollingTask = nil
                }
            }
            if (self?.stepsByCascadeId[cascadeId] ?? []).isEmpty {
                let cached = await storeRef.loadProjectedSteps(cascadeId: cascadeId)
                if !cached.isEmpty, let self, (self.stepsByCascadeId[cascadeId] ?? []).isEmpty {
                    self.stepsByCascadeId[cascadeId] = cached
                    self.harvestEmbedResources(from: cached)
                    if self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                    }
                }
            }

            var attempts = 0
            let maxAttempts = pollUntilIdle ? 10_000 : 1
            while !Task.isCancelled && attempts < maxAttempts {
                guard let self, !self.isNetworkingSuspended, self.isDeviceNetworkReachable else { break }
                attempts += 1
                let summaryMeta = self.summaries.first(where: { $0.cascadeId == cascadeId })
                if let summaryMeta, !summaryMeta.isCloud, self.hasPairedBackend, !self.isSummaryHostOnline(summaryMeta) {
                    break
                }
                let knownCount = summaryMeta?.stepCount ?? 0
                let summaryIsCloud = summaryMeta?.isCloud ?? false
                let originUuid = summaryMeta?.originInstanceUuid
                let allowFailover = summaryIsCloud
                    || originUuid == nil
                    || originUuid?.isEmpty == true
                    || self.pairedLocalHosts.count <= 1
                let isEmptyNewSessionNow = self.locallyCreatedEmptyCascadeIds.contains(cascadeId)
                    && !(self.optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
                var stillActive = false
                do {
                    let remoteSteps = try await client.fetchAllTrajectorySteps(
                        cascadeId: cascadeId,
                        knownStepCount: knownCount,
                        isCloud: summaryIsCloud,
                        instanceUuidOverride: originUuid,
                        allowCrossInstanceFailover: allowFailover
                    )
                    let liveRelaySnapshot: (instances: [RelayInstanceInfo], active: RelayInstanceInfo?)? =
                        (self.activeHost.channel == .cloudRelay)
                            ? await client.currentRelayInstancesSnapshot()
                            : nil
                    guard !Task.isCancelled, !self.isNetworkingSuspended else { return }

                    self.lastBackendActivityAt = Date()

                    if let liveRelaySnapshot,
                       (!liveRelaySnapshot.instances.isEmpty || liveRelaySnapshot.active != nil) {
                        let activeChanged = liveRelaySnapshot.active.map {
                            self.activeHost.instanceId != $0.uuid
                                || self.activeHost.hostname != $0.name
                                || !self.activeHost.isOnline
                        } ?? false
                        let listChanged = !liveRelaySnapshot.instances.isEmpty
                            && liveRelaySnapshot.instances != self.availableRelayInstances
                        if activeChanged || listChanged {
                            let instancesToApply = liveRelaySnapshot.instances.isEmpty
                                ? (liveRelaySnapshot.active.map { [$0] } ?? [])
                                : liveRelaySnapshot.instances
                            self.syncRelayInstancesToHosts(
                                instancesToApply,
                                preferredActiveInstance: liveRelaySnapshot.active
                            )
                        }
                        if !summaryIsCloud,
                           let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
                            let existingUuid = self.summaries[sumIdx].originInstanceUuid
                            if let existingUuid,
                               let matchedPeer = liveRelaySnapshot.instances.first(where: {
                                   $0.uuid == existingUuid && $0.status.isReachable
                               }) {
                                self.summaries[sumIdx].originHostName = matchedPeer.name
                            } else if allowFailover, let liveRelayInst = liveRelaySnapshot.active {
                                self.summaries[sumIdx].originInstanceUuid = liveRelayInst.uuid
                                self.summaries[sumIdx].originHostName = liveRelayInst.name
                            }
                        }
                    }

                    if self.hasPairedBackend && (!self.isLiveBackendConnected || !self.activeHost.isOnline) {
                        self.markBackendReconnected()
                    }
                    self.stepLoadErrorText = nil
                    if self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                        self.isLoadingSteps = false
                    }

                    let withinOptimisticWindow = (self.optimisticActiveUntilByCascadeId[cascadeId].map { $0 > Date() } ?? false)
                    if !remoteSteps.isEmpty {
                        self.locallyCreatedEmptyCascadeIds.remove(cascadeId)
                        self.stepsByCascadeId[cascadeId] = remoteSteps
                        self.harvestEmbedResources(from: remoteSteps)
                        await storeRef.saveProjectedSteps(remoteSteps, for: cascadeId)
                        if !self.syncedConfigCascadeIds.contains(cascadeId),
                           let latestCfgStep = remoteSteps.last(where: {
                               $0.type == .userInput && ($0.recordedExecutionMode != nil || $0.recordedModelId != nil)
                           }) {
                            self.syncedConfigCascadeIds.insert(cascadeId)
                            if self.activeCascadeId == cascadeId {
                                self.applyRecordedConversationConfig(from: latestCfgStep)
                            }
                        }
                        if let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
                            self.summaries[sumIdx].stepCount = max(self.summaries[sumIdx].stepCount, remoteSteps.count)
                            if self.summaries[sumIdx].title == "New Conversation",
                               let firstPrompt = remoteSteps.first(where: { $0.type == .userInput })?.userInput?
                                   .trimmingCharacters(in: .whitespacesAndNewlines),
                               !firstPrompt.isEmpty {
                                self.summaries[sumIdx].title = String(firstPrompt.prefix(56))
                            }
                            let reconciled = Self.reconcileSummaryStreamingStatus(
                                currentStatus: self.summaries[sumIdx].status,
                                remoteSteps: remoteSteps,
                                withinOptimisticSendWindow: withinOptimisticWindow
                            )
                            self.summaries[sumIdx].status = reconciled.status
                            stillActive = reconciled.stillActive
                            if !reconciled.stillActive {
                                self.optimisticActiveUntilByCascadeId.removeValue(forKey: cascadeId)
                            }
                            self.summaries[sumIdx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                                status: self.summaries[sumIdx].status,
                                stepCount: self.summaries[sumIdx].stepCount,
                                isUnread: self.summaries[sumIdx].isUnread
                            )
                        } else {
                            stillActive = remoteSteps.contains { $0.status == .inProgress || $0.status == .pending }
                                || withinOptimisticWindow
                        }
                    } else {
                        stillActive = withinOptimisticWindow
                            || summaryMeta?.status == .inProgress
                            || summaryMeta?.status == .pending
                    }
                    self.connectionLifecyclePhase = stillActive ? .onlineStreaming : .onlineIdle
                } catch {
                    if !Task.isCancelled {
                        if Self.isBackendOfflineError(error) && self.activeHost.channel != .cloudRelay {
                            self.markBackendOffline(error: error)
                        }
                        if self.stepSyncGeneration == generation && self.activeCascadeId == cascadeId {
                            self.isLoadingSteps = false
                            if (self.stepsByCascadeId[cascadeId] ?? []).isEmpty && !isEmptyNewSessionNow {
                                self.stepLoadErrorText = error.localizedDescription
                            }
                        }
                    }
                    if !pollUntilIdle { break }
                }

                guard !Task.isCancelled, !self.isNetworkingSuspended, self.isDeviceNetworkReachable else { break }
                if !pollUntilIdle {
                    break
                }
                let isViewingThisChat = (self.activeRoute == .cascadeChat(cascadeId) && self.activeCascadeId == cascadeId)
                let latestSummary = self.summaries.first(where: { $0.cascadeId == cascadeId })
                let isHostOffline = !self.isSummaryHostOnline(latestSummary)

                if isHostOffline {
                    // Central exponential-backoff reconnect scheduler owns host recovery; do not spin here
                    break
                }

                if stillActive {
                    let interval = ConnectionPowerPolicy.activeStreamingStepPollInterval(
                        channel: self.activeHost.channel,
                        isLowPowerMode: self.isLowPowerModeEnabled
                    )
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } else {
                    guard isViewingThisChat,
                          let fallbackInterval = ConnectionPowerPolicy.idleChatFallbackStepPollInterval(
                              isStreamHealthy: self.isSummaryStreamHealthy,
                              isLowPowerMode: self.isLowPowerModeEnabled
                          ) else {
                        // Idle chat with healthy push stream -> stop polling completely (0 idle RPCs)
                        break
                    }
                    try? await Task.sleep(nanoseconds: UInt64(fallbackInterval * 1_000_000_000))
                }
            }
        }
    }

    // MARK: - Navigation & Display Options Actions (`UE01`, `UE02`)

    public func selectHost(_ host: RemoteHostInstance) {
        activeHost = host
        if (hasPairedBackend || isLiveBackendConnected), host.channel == .cloudRelay {
            let authIdx = activeAuthUser
            Task { [weak self] in
                guard let self, let cached = await self.loadSavedSessionCookie() else { return }
                _ = await self.connectCloudRelay(
                    relayURLString: host.endpointURL.absoluteString,
                    sessionCookie: cached.cookie,
                    authUser: cached.authUser ?? authIdx,
                    resolvedInstanceUuid: host.instanceId,
                    hostName: host.hostname
                )
            }
            return
        }
        rpcClient = AntigravityRPCClient(
            host: host,
            csrfToken: "csrf-antigravity-ios-session-token"
        )
    }

    public func selectProject(_ projectSlug: String) {
        selectedProjectId = projectSlug
        if let project = projects.first(where: { $0.id == projectSlug }) {
            selectedWorkspaceUri = project.workspaceUri
        }
        activeRoute = .projectDetail(projectSlug)
    }

    public func toggleProjectExpandedInHome(_ projectSlug: String) {
        guard let idx = projects.firstIndex(where: { $0.id == projectSlug }) else { return }
        projects[idx].isExpandedInHome.toggle()
    }

    public func selectWorkspace(_ workspaceUri: String) {
        selectedWorkspaceUri = workspaceUri
        selectedWorktreeFilter = nil
        if let firstCascade = summaries.first(where: { $0.workspaceUri == workspaceUri && !$0.isArchived }) {
            selectCascade(firstCascade.cascadeId)
        }
    }

    public func selectCascade(_ cascadeId: String) {
        discardPendingDraftConversation()
        activeCascadeId = cascadeId
        let viewedNow = Date()
        locallyViewedAtByCascadeId[cascadeId] = viewedNow
        var shouldSyncViewedAnnotation = false
        var originUuidForViewSync: String? = nil
        var selectedSummaryForOnlineCheck: CascadeSummary? = nil
        if let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) {
            selectedSummaryForOnlineCheck = summaries[idx]
            shouldSyncViewedAnnotation = summaries[idx].isUnread
            originUuidForViewSync = summaries[idx].originInstanceUuid
            summaries[idx].isUnread = false
            summaries[idx].lastUserViewTime = viewedNow
            selectedWorkspaceUri = summaries[idx].workspaceUri
            selectedProjectId = summaries[idx].projectSlug
            if hasPairedBackend || isLiveBackendConnected {
                summaries[idx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                    status: summaries[idx].status,
                    stepCount: summaries[idx].stepCount,
                    isUnread: false
                )
            }
        }
        if let cachedSteps = stepsByCascadeId[cascadeId] {
            harvestEmbedResources(from: cachedSteps)
            if let latestCfgStep = cachedSteps.last(where: {
                $0.type == .userInput && ($0.recordedExecutionMode != nil || $0.recordedModelId != nil)
            }) {
                applyRecordedConversationConfig(from: latestCfgStep)
            }
        }
        activeRoute = .cascadeChat(cascadeId)
        unreadStreamingStepCount = 0
        isAutoScrollPinnedToBottom = true
        if hasPairedBackend || isLiveBackendConnected {
            if shouldSyncViewedAnnotation,
               !isVerificationMode,
               !cascadeId.hasPrefix("cas-") || Self.esddFixtureCascadeIds.contains(cascadeId),
               activeHost.channel == .cloudRelay,
               isSummaryHostOnline(selectedSummaryForOnlineCheck),
               let clientRef = rpcClient {
                let targetUuid = originUuidForViewSync
                Task {
                    try? await clientRef.markCascadeViewed(
                        cascadeId: cascadeId,
                        viewedAt: viewedNow,
                        instanceUuidOverride: targetUuid
                    )
                }
            }
            syncStepsForCascade(cascadeId, pollUntilIdle: true)
        }
    }

    // MARK: - Embed & Artifact Resource Resolution (`<agent-embed>`, `file:///` Images & HTML Widgets)

    public func harvestEmbedResources(from steps: [CascadeStep]) {
        for step in steps {
            if let ca = step.codeAction, let content = ca.fileContent, !content.isEmpty {
                let norm = ResolvedEmbedResource.normalizePath(ca.targetFileUri)
                let res = ResolvedEmbedResource(
                    uri: ca.targetFileUri,
                    normalizedPath: norm,
                    mimeType: ResolvedEmbedResource.inferredMimeType(for: ca.targetFileUri),
                    textContent: content,
                    binaryData: Data(content.utf8),
                    source: .trajectoryStep
                )
                storeResolvedEmbedInCache(res)
            }
            if let vf = step.viewFile, let content = vf.fileContent, !content.isEmpty {
                let norm = ResolvedEmbedResource.normalizePath(vf.fileUri)
                let res = ResolvedEmbedResource(
                    uri: vf.fileUri,
                    normalizedPath: norm,
                    mimeType: ResolvedEmbedResource.inferredMimeType(for: vf.fileUri),
                    textContent: content,
                    binaryData: Data(content.utf8),
                    source: .trajectoryStep
                )
                storeResolvedEmbedInCache(res)
            }
        }
    }

    public func harvestEmbedResources(from artifacts: [ArtifactSnapshot]) {
        for artifact in artifacts where !artifact.content.isEmpty {
            let norm = ResolvedEmbedResource.normalizePath(artifact.artifactPath)
            let res = ResolvedEmbedResource(
                uri: artifact.artifactPath,
                normalizedPath: norm,
                mimeType: ResolvedEmbedResource.inferredMimeType(for: artifact.artifactPath),
                textContent: artifact.content,
                binaryData: Data(artifact.content.utf8),
                source: .artifactSnapshot
            )
            storeResolvedEmbedInCache(res)
        }
    }

    private func storeResolvedEmbedInCache(_ resource: ResolvedEmbedResource) {
        if resolvedEmbedCache.count >= 64, resolvedEmbedCache[resource.normalizedPath] == nil {
            if let firstKey = resolvedEmbedCache.keys.first {
                resolvedEmbedCache.removeValue(forKey: firstKey)
            }
        }
        resolvedEmbedCache[resource.normalizedPath] = resource
    }

    public func cachedEmbedResource(for uri: String) -> ResolvedEmbedResource? {
        let norm = ResolvedEmbedResource.normalizePath(uri)
        if let exact = resolvedEmbedCache[norm] {
            return exact
        }
        let targetBase = (norm as NSString).lastPathComponent.lowercased()
        guard !targetBase.isEmpty else { return nil }
        // Match `/brain/<id>/<filename>` even if host home directory prefix differs (e.g. `/Users/...` vs `/home/...`)
        if norm.contains("/brain/") || norm.contains("/.gemini/") {
            if let byBase = resolvedEmbedCache.values.first(where: {
                ($0.normalizedPath as NSString).lastPathComponent.lowercased() == targetBase
            }) {
                return byBase
            }
        }
        return nil
    }

    /// 4-tier resolver for `<agent-embed src="...">` HTML widgets, SVGs, and `file:///` images:
    /// 1. In-memory trajectory & artifact snapshot cache (works offline & over Cloud Relay)
    /// 2. Inline `data:` URI decoding
    /// 3. Direct `http://`/`https://` URL pass-through
    /// 4. Remote host / Companion Bridge / Desktop `GetArtifactSnapshots` / `GetRevisionArtifact` RPC
    public func resolveEmbedResource(
        uri: String,
        cascadeId: String? = nil
    ) async -> ResolvedEmbedResource? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Tier 1: Local trajectory & artifact cache
        if let cached = cachedEmbedResource(for: trimmed) {
            return cached
        }

        // Tier 2: Inline `data:` URI
        if trimmed.lowercased().hasPrefix("data:"),
           let decoded = ResolvedEmbedResource.decodeDataURI(trimmed) {
            storeResolvedEmbedInCache(decoded)
            return decoded
        }

        // Tier 3: Direct HTTP(S) URL
        let lower = trimmed.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            let direct = ResolvedEmbedResource(
                uri: trimmed,
                normalizedPath: trimmed,
                mimeType: ResolvedEmbedResource.inferredMimeType(for: trimmed),
                textContent: nil,
                binaryData: nil,
                source: .directNetwork
            )
            return direct
        }

        // Tier 4: Live backend RPC fetch (`ReadArtifactFile` -> `GetArtifactSnapshots` -> `GetRevisionArtifact`)
        guard (hasPairedBackend || isLiveBackendConnected),
              isDeviceNetworkReachable,
              !isNetworkingSuspended,
              let client = rpcClient else {
            return nil
        }

        let effectiveCascadeId = cascadeId ?? activeCascadeId
        let originUuid = summaries.first(where: { $0.cascadeId == effectiveCascadeId })?.originInstanceUuid
        if let fetched = await client.fetchRemoteArtifactResource(
            uri: trimmed,
            cascadeId: effectiveCascadeId,
            instanceUuidOverride: originUuid
        ) {
            storeResolvedEmbedInCache(fetched)
            return fetched
        }
        return nil
    }

    public func resetDisplayOptions() {
        displayOptions = AgentDisplayOptions()
        let opts = displayOptions
        let storeRef = projectionStore
        Task {
            await storeRef.saveDisplayOptions(opts)
        }
    }

    public func markAllConversationsAsRead() {
        let now = Date()
        var targetsToSync: [(cascadeId: String, originUuid: String?)] = []
        for idx in summaries.indices {
            if summaries[idx].isUnread {
                targetsToSync.append((summaries[idx].cascadeId, summaries[idx].originInstanceUuid))
            }
            summaries[idx].isUnread = false
            summaries[idx].lastUserViewTime = now
            if hasPairedBackend || isLiveBackendConnected {
                summaries[idx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                    status: summaries[idx].status,
                    stepCount: summaries[idx].stepCount,
                    isUnread: false
                )
            }
            locallyViewedAtByCascadeId[summaries[idx].cascadeId] = now
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let shouldSyncRemote = !isVerificationMode
            && (hasPairedBackend || isLiveBackendConnected)
            && activeHost.channel == .cloudRelay
        let clientRef = shouldSyncRemote ? rpcClient : nil
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            if let clientRef {
                for item in targetsToSync where !item.cascadeId.hasPrefix("cas-") {
                    try? await clientRef.markCascadeViewed(
                        cascadeId: item.cascadeId,
                        viewedAt: now,
                        instanceUuidOverride: item.originUuid
                    )
                }
            }
        }
    }

    // MARK: - Conversation Context Menu & Swipe Actions (`UE03`)

    public func togglePinCascade(_ cascadeId: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].isPinned.toggle()
        let isPinned = summaries[idx].isPinned
        let originUuid = summaries[idx].originInstanceUuid
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.pinCascade(cascadeId: cascadeId, isPinned: isPinned, instanceUuidOverride: originUuid)
        }
    }

    public func toggleUnreadCascade(_ cascadeId: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].isUnread.toggle()
        let now = Date()
        let nowUnread = summaries[idx].isUnread
        let originUuid = summaries[idx].originInstanceUuid
        if nowUnread {
            locallyViewedAtByCascadeId.removeValue(forKey: cascadeId)
        } else {
            locallyViewedAtByCascadeId[cascadeId] = now
            summaries[idx].lastUserViewTime = now
        }
        if hasPairedBackend || isLiveBackendConnected {
            summaries[idx].statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                status: summaries[idx].status,
                stepCount: summaries[idx].stepCount,
                isUnread: nowUnread
            )
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let shouldSyncViewed = !nowUnread
            && !isVerificationMode
            && (hasPairedBackend || isLiveBackendConnected)
            && activeHost.channel == .cloudRelay
            && !cascadeId.hasPrefix("cas-")
        let clientRef = shouldSyncViewed ? rpcClient : nil
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            if let clientRef {
                try? await clientRef.markCascadeViewed(
                    cascadeId: cascadeId,
                    viewedAt: now,
                    instanceUuidOverride: originUuid
                )
            }
        }
    }

    public func renameCascade(_ cascadeId: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].title = trimmed
        let originUuid = summaries[idx].originInstanceUuid
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.renameCascade(cascadeId: cascadeId, newTitle: trimmed, instanceUuidOverride: originUuid)
        }
    }

    public func moveCascade(_ cascadeId: String, toProject projectSlug: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].projectSlug = projectSlug
        let targetUri = projects.first(where: { $0.id == projectSlug })?.workspaceUri ?? summaries[idx].workspaceUri
        summaries[idx].workspaceUri = targetUri
        let originUuid = summaries[idx].originInstanceUuid
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.moveCascadeToWorkspace(cascadeId: cascadeId, workspaceUri: targetUri, instanceUuidOverride: originUuid)
        }
    }

    public func archiveCascade(_ cascadeId: String) {
        guard let idx = summaries.firstIndex(where: { $0.cascadeId == cascadeId }) else { return }
        summaries[idx].isArchived = true
        let originUuid = summaries[idx].originInstanceUuid
        if activeCascadeId == cascadeId, let next = filteredSummaries.first {
            activeCascadeId = next.cascadeId
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.archiveCascade(cascadeId: cascadeId, isArchived: true, instanceUuidOverride: originUuid)
        }
    }

    public func deleteCascade(_ cascadeId: String) {
        let originUuid = summaries.first(where: { $0.cascadeId == cascadeId })?.originInstanceUuid
        summaries.removeAll { $0.cascadeId == cascadeId }
        stepsByCascadeId.removeValue(forKey: cascadeId)
        if activeCascadeId == cascadeId, let next = filteredSummaries.first {
            activeCascadeId = next.cascadeId
        }
        let snapshot = summaries
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveProjectedSummaries(snapshot)
            try? await clientRef?.deleteCascade(cascadeId: cascadeId, instanceUuidOverride: originUuid)
        }
    }

    // MARK: - Project Creation & Scoped Conversation Actions (`UE04`, `UE05`)

    @discardableResult
    public func createNewProject(
        name: String? = nil,
        runtime: ProjectRuntimeTarget? = nil,
        source: ProjectSourceKind? = nil,
        selectedRepo: GitHubRepoItem? = nil,
        branchWorktree: String? = nil
    ) -> ProjectWorkspace {
        var draft = newProjectDraft
        if let runtime { draft.runsOn = runtime }
        if let source { draft.source = source }
        if let selectedRepo { draft.selectedRepo = selectedRepo }
        if let branchWorktree { draft.branchWorktree = branchWorktree }
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.projectName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let slug = draft.projectName.isEmpty ? "new-project" : draft.projectName
        let repoPath = draft.selectedRepo?.fullName ?? "acme/\(slug)"
        let pathDisplay = draft.runsOn == .cloud ? "cloud://\(repoPath)" : "~/code/\(slug)"
        let workspaceUri = draft.runsOn == .cloud ? "cloud://\(repoPath)" : "file:///Users/wl/code/\(slug)"
        let branch = draft.selectedRepo?.defaultBranch ?? "main"

        let created = ProjectWorkspace(
            id: slug,
            name: slug,
            pathDisplay: pathDisplay,
            workspaceUri: workspaceUri,
            runtime: draft.runsOn,
            hostName: draft.runsOn == .cloud ? "Cloud" : draft.runsOn.rawValue,
            activeBranch: branch,
            worktrees: [branch, "worktree/\(slug)"],
            isExpandedInHome: true,
            rulesAndSkillsCount: 4
        )
        if let existingIdx = projects.firstIndex(where: { $0.id == slug }) {
            projects[existingIdx] = created
        } else {
            projects.append(created)
        }
        selectedProjectId = created.id
        selectedWorkspaceUri = created.workspaceUri
        presentedSheet = nil
        activeRoute = .projectDetail(created.id)

        let projectsSnapshot = projects
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task { [weak self] in
            await storeRef.saveProjects(projectsSnapshot)
            if let remoteCreated = try? await clientRef?.createProjectWorkspace(draft: draft),
               let self,
               let idx = self.projects.firstIndex(where: { $0.id == slug }) {
                self.projects[idx].cloudProjectId = remoteCreated.cloudProjectId ?? self.projects[idx].cloudProjectId
                self.projects[idx].originInstanceUuid = remoteCreated.originInstanceUuid ?? self.projects[idx].originInstanceUuid
                await storeRef.saveProjects(self.projects)
            }
        }
        return created
    }

    @discardableResult
    public func createConversationInProject(
        _ projectSlug: String,
        title: String = "New Conversation",
        initialPrompt: String? = nil
    ) -> String {
        discardPendingDraftConversation()
        let optimisticId = "cas-\(UUID().uuidString.prefix(8).lowercased())"
        let trimmedSlug = projectSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedLocalFilter: (id: String, name: String)? = {
            if case let .localHost(id, name) = hostFilter {
                return (id, name)
            }
            return nil
        }()
        let project: ProjectWorkspace? = {
            if let exact = projects.first(where: { $0.id == trimmedSlug }) {
                return exact
            }
            if let selectedLocalFilter,
               let hostScoped = projects.first(where: {
                   $0.name == trimmedSlug
                       && $0.runtime != .cloud
                       && ($0.originInstanceUuid == selectedLocalFilter.id || $0.hostName == selectedLocalFilter.name)
               }) {
                return hostScoped
            }
            return projects.first(where: { $0.name == trimmedSlug })
        }()
        let isUnassigned = (project?.isNoProject == true) || AntigravityCloudDetector.isNoProjectSlug(trimmedSlug)
        let isCloudProj = (project?.runtime == .cloud) || trimmedSlug.lowercased().hasPrefix("cloud:")
        let effectiveSlug: String = {
            if let project { return project.id }
            if isUnassigned {
                let hasLocalNoProj = projects.contains(where: { $0.isNoProject && $0.runtime != .cloud })
                if isCloudProj && hasLocalNoProj {
                    return "cloud:\(AntigravityCloudDetector.noProjectDisplayName)"
                }
                return AntigravityCloudDetector.noProjectDisplayName
            }
            return trimmedSlug
        }()
        let cloudProjId = isUnassigned ? nil : project?.cloudProjectId
        let originUuid: String? = isCloudProj
            ? project?.originInstanceUuid
            : (project?.originInstanceUuid ?? selectedLocalFilter?.id)
        let originHostName: String = isCloudProj
            ? "Antigravity"
            : (project?.hostName ?? selectedLocalFilter?.name ?? activeHost.hostname)
        let workspaceUri: String = {
            if isUnassigned { return "" }
            if let existingUri = project?.workspaceUri, !existingUri.isEmpty {
                return existingUri
            }
            if hasPairedBackend || isLiveBackendConnected {
                return ""
            }
            return isCloudProj ? "cloud://\(trimmedSlug)" : "file:///Users/wl/code/\(trimmedSlug)"
        }()
        let branch = isUnassigned ? "" : (project?.activeBranch ?? "main")

        let newSummary = CascadeSummary(
            cascadeId: optimisticId,
            title: title,
            projectSlug: effectiveSlug,
            workspaceUri: workspaceUri,
            branchName: branch,
            status: initialPrompt != nil ? .inProgress : .done,
            stepCount: initialPrompt != nil ? 1 : 0,
            currentStepIndex: 1,
            totalSteps: 1,
            updatedAt: Date(),
            relativeTimeLabel: "now",
            statusSubtitle: initialPrompt != nil ? "Running · Step 1 of 1" : "Ready for instructions",
            isPinned: displayOptions.autoPinOnMessage,
            isArchived: false,
            isUnread: false,
            modelLabel: selectedModelConfig.displayName,
            lastMessagePreview: initialPrompt ?? "Ready for instructions...",
            isCloud: isCloudProj,
            cloudProjectId: cloudProjId,
            originInstanceUuid: originUuid,
            originHostName: originHostName
        )
        summaries.insert(newSummary, at: 0)
        if hasPairedBackend || isLiveBackendConnected {
            let existingCloudProjects = projects.filter { $0.runtime == .cloud && $0.cloudProjectId != nil }
            var nextSummaries = summaries
            projects = Self.reconcileLiveProjects(
                workspaces: workspaces,
                summaries: &nextSummaries,
                existingProjects: projects,
                hostName: activeHost.hostname,
                cloudProjects: existingCloudProjects
            )
            summaries = nextSummaries
        }
        stepsByCascadeId[optimisticId] = []
        if initialPrompt == nil || initialPrompt?.isEmpty == true {
            locallyCreatedEmptyCascadeIds.insert(optimisticId)
        }
        activeCascadeId = optimisticId
        selectedProjectId = summaries.first(where: { $0.cascadeId == optimisticId })?.projectSlug ?? effectiveSlug
        selectedWorkspaceUri = workspaceUri
        activeRoute = .cascadeChat(optimisticId)

        let clientRef = rpcClient
        let modelId = selectedModelConfig.modelId
        let shouldCallLiveBackend = (hasPairedBackend || isLiveBackendConnected)

        Task { [weak self] in
            if shouldCallLiveBackend,
               let clientRef,
               let realCascadeId = try? await clientRef.startCascade(
                   workspaceUri: workspaceUri,
                   initialPrompt: initialPrompt ?? "",
                   modelId: modelId,
                   cloudProjectId: cloudProjId,
                   isCloud: isCloudProj,
                   instanceUuidOverride: originUuid
               ),
               !realCascadeId.isEmpty {
                guard let self else { return }
                if self.hasPairedBackend && (!self.isLiveBackendConnected || !self.activeHost.isOnline) {
                    self.markBackendReconnected()
                }
                let wasEmptyNew = self.locallyCreatedEmptyCascadeIds.remove(optimisticId) != nil
                let existingSteps = self.stepsByCascadeId.removeValue(forKey: optimisticId) ?? []
                if wasEmptyNew && existingSteps.isEmpty && (initialPrompt == nil || initialPrompt?.isEmpty == true) {
                    self.locallyCreatedEmptyCascadeIds.insert(realCascadeId)
                }
                self.stepsByCascadeId[realCascadeId] = existingSteps.map { step in
                    var copy = step
                    copy.cascadeId = realCascadeId
                    return copy
                }
                if let idx = self.summaries.firstIndex(where: { $0.cascadeId == optimisticId }) {
                    self.summaries[idx].cascadeId = realCascadeId
                }
                if self.activeCascadeId == optimisticId {
                    self.activeCascadeId = realCascadeId
                    if case .cascadeChat = self.activeRoute {
                        self.activeRoute = .cascadeChat(realCascadeId)
                    }
                }
                if let prompt = initialPrompt, !prompt.isEmpty {
                    self.locallyCreatedEmptyCascadeIds.remove(realCascadeId)
                    self.composerDraftText = prompt
                    self.sendCurrentDraft()
                } else {
                    self.syncStepsForCascade(realCascadeId, pollUntilIdle: false)
                }
                return
            }

            if let prompt = initialPrompt, !prompt.isEmpty {
                self?.composerDraftText = prompt
                self?.sendCurrentDraft()
            }
        }
        return optimisticId
    }

    public func createNewCascade(
        title: String = "New Agentic Session",
        branchName: String? = nil,
        initialPrompt: String? = nil
    ) {
        let slug: String = {
            if let selected = selectedProject?.id, !selected.isEmpty {
                return selected
            }
            if hasPairedBackend || isLiveBackendConnected {
                return projects.first?.id ?? AntigravityCloudDetector.noProjectDisplayName
            }
            return "ledger-svc"
        }()
        let newId = createConversationInProject(slug, title: title, initialPrompt: nil)
        if let branchName, let idx = summaries.firstIndex(where: { $0.cascadeId == newId }) {
            summaries[idx].branchName = branchName
        }
        if let initialPrompt, !initialPrompt.isEmpty {
            composerDraftText = initialPrompt
            sendCurrentDraft()
        }
    }

    public func revealProjectInFinder(_ projectSlug: String) {
        guard let project = projects.first(where: { $0.id == projectSlug }),
              !project.workspaceUri.isEmpty else { return }
        let uri = project.workspaceUri
        let clientRef = rpcClient
        Task {
            try? await clientRef?.openWorkspaceInFinder(workspaceUri: uri)
        }
    }

    /// Returns `true` when an existing cached workspace, project, or conversation summary belongs to one of
    /// the hosts (or Cloud) that was authoritatively refreshed in the current sync pass.
    internal static func itemBelongsToRefreshedScope(
        isCloud: Bool,
        originUuid: String?,
        originHost: String?,
        refreshedLocalHostUuids: Set<String>,
        refreshedLocalHostNames: Set<String>,
        refreshedCloud: Bool,
        fallbackActiveHostId: String,
        fallbackActiveHostName: String,
        isSingleDirectHost: Bool
    ) -> Bool {
        if isCloud {
            return refreshedCloud
        }
        if let uuid = originUuid?.trimmingCharacters(in: .whitespacesAndNewlines), !uuid.isEmpty {
            if refreshedLocalHostUuids.contains(uuid) {
                return true
            }
            if let host = originHost?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty,
               refreshedLocalHostNames.contains(host) {
                return true
            }
            return false
        }
        if let host = originHost?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            return refreshedLocalHostNames.contains(host)
        }
        if isSingleDirectHost {
            return !refreshedLocalHostUuids.isEmpty
        }
        return refreshedLocalHostUuids.contains(fallbackActiveHostId)
            || refreshedLocalHostNames.contains(fallbackActiveHostName)
    }

    private func updateSpecificLocalHostReachability(
        instanceId: String,
        hostname: String,
        isOnline: Bool,
        latencyMs: Int? = nil
    ) {
        if !availableRelayInstances.isEmpty {
            availableRelayInstances = availableRelayInstances.map { inst in
                guard inst.uuid == instanceId || (!hostname.isEmpty && inst.name == hostname) else {
                    return inst
                }
                if isOnline {
                    return inst.status.isReachable ? inst : inst.withStatus(.connected)
                } else {
                    return inst.status.isReachable ? inst.withStatus(.disconnected) : inst
                }
            }
        }
        for idx in hosts.indices {
            if hosts[idx].instanceId == instanceId || (!hostname.isEmpty && hosts[idx].hostname == hostname) {
                hosts[idx].isOnline = isOnline
                if let latencyMs, isOnline {
                    hosts[idx].latencyMs = latencyMs
                }
            }
        }
        if activeHost.instanceId == instanceId || (!hostname.isEmpty && activeHost.hostname == hostname) {
            var updated = activeHost
            updated.isOnline = isOnline
            if let latencyMs, isOnline {
                updated.latencyMs = latencyMs
            }
            activeHost = updated
        }
    }

    public func refreshWorkspacesAndSummaries(
        forceFullSync: Bool = false,
        includeAutomations: Bool = false,
        skipRelayMetadataProbe: Bool = false
    ) async {
        guard let task = scheduleCoalescedHostRefresh(
            for: .allHosts,
            forceFullSync: forceFullSync,
            includeAutomations: includeAutomations,
            requirePairedBackend: false,
            skipRelayMetadataProbe: skipRelayMetadataProbe
        ) else {
            return
        }
        _ = await task.value
    }

    private func executeScopedHostRefresh(
        target: AgentHostFilter,
        forceFullSync: Bool,
        includeAutomations: Bool,
        skipRelayMetadataProbe: Bool = false
    ) async -> Bool {
        guard !isNetworkingSuspended else { return false }

        let isRelay = (activeHost.channel == .cloudRelay)
        let syncTimeout: TimeInterval = isRelay ? 14.0 : 3.5
        let useLightweight: Bool
        if target == .allHosts {
            backgroundPollCounter += 1
            useLightweight = !forceFullSync && isRelay && (backgroundPollCounter % 4 != 1) && isSummaryStreamHealthy
        } else {
            useLightweight = false
        }

        var didRefreshRelayList = skipRelayMetadataProbe
        if isRelay && !skipRelayMetadataProbe && hostRefreshExecutorOverrideForTesting == nil,
           let client = rpcClient {
            if let probe = try? await client.probeHostReachability(timeoutInterval: min(syncTimeout, 8.0)) {
                applyRelayProbeMetadata(probe)
                didRefreshRelayList = true
            }
        }

        do {
            let syncResult: ScopedWorkspaceSyncResult
            if let testExecutor = hostRefreshExecutorOverrideForTesting {
                syncResult = try await testExecutor(target)
            } else if let client = rpcClient {
                syncResult = try await client.fetchScopedWorkspacesAndSummaries(
                    target: target,
                    timeoutInterval: syncTimeout,
                    lightweightPoll: useLightweight,
                    skipRelayListRefresh: didRefreshRelayList
                )
            } else {
                return false
            }

            if let latencyMs = syncResult.latencyMs, syncResult.targetReachable {
                lastPingLatencyMs = latencyMs
            }

            if isRelay {
                let latestInstances: [RelayInstanceInfo]
                if !syncResult.relayInstances.isEmpty {
                    latestInstances = syncResult.relayInstances
                } else if let client = rpcClient {
                    latestInstances = await client.currentCachedRelayInstances()
                } else {
                    latestInstances = []
                }
                let latestActive: RelayInstanceInfo?
                if target == .allHosts, let client = rpcClient,
                   (hostFilter == .allHosts || !activeHost.isOnline) {
                    latestActive = await client.currentActiveRelayInstance()
                } else {
                    latestActive = nil
                }
                if !latestInstances.isEmpty {
                    syncRelayInstancesToHosts(
                        latestInstances,
                        latencyMs: syncResult.latencyMs ?? lastPingLatencyMs ?? activeHost.latencyMs,
                        preferredActiveInstance: latestActive
                    )
                }
            }

            // Handle targeted single-host or Cloud unreachability without discarding cached conversations
            switch target {
            case .localHost(let targetId, let targetName):
                if !syncResult.targetReachable {
                    updateSpecificLocalHostReachability(
                        instanceId: targetId,
                        hostname: targetName,
                        isOnline: false
                    )
                    let anyOtherOnline = hosts.contains(where: { $0.instanceId != targetId && $0.isOnline })
                    if !anyOtherOnline && hasPairedBackend && !isRelay {
                        let offlineErr = AntigravityRPCError.httpError(
                            statusCode: 503,
                            body: "\(targetName) is currently offline or unreachable"
                        )
                        markBackendOffline(error: offlineErr)
                    }
                    return false
                }
                updateSpecificLocalHostReachability(
                    instanceId: targetId,
                    hostname: targetName,
                    isOnline: true,
                    latencyMs: syncResult.latencyMs
                )
                // Only align `activeHost` to this refreshed device if the user is still viewing it
                if coalescingScopeKey(for: hostFilter) == coalescingScopeKey(for: target),
                   let matchedHost = hosts.first(where: { $0.instanceId == targetId || $0.hostname == targetName }) {
                    activeHost = matchedHost
                    if isLiveBackendConnected {
                        if let latency = syncResult.latencyMs ?? lastPingLatencyMs {
                            connectionStatusText = "Connected · \(matchedHost.hostname) · \(latency)ms"
                        } else {
                            connectionStatusText = "Connected · \(matchedHost.hostname)"
                        }
                    }
                }

            case .antigravityCloud:
                if !syncResult.targetReachable {
                    return false
                }

            case .allHosts:
                break
            }

            consecutiveSyncFailures = 0
            lastBackendActivityAt = Date()
            if target == .allHosts {
                lastFullSyncAt = Date()
            }
            if syncResult.refreshedCloud {
                cloudAgentWarmingUp = syncResult.cloudWarmingUp
            }

            let activeRelayIsReachable: Bool = {
                guard isRelay, !syncResult.relayInstances.isEmpty else { return true }
                if let matched = syncResult.relayInstances.first(where: { $0.uuid == activeHost.instanceId }) {
                    return matched.status.isReachable
                }
                return syncResult.relayInstances.contains(where: \.status.isReachable)
            }()

            if hasPairedBackend && (!isLiveBackendConnected || (!activeHost.isOnline && activeRelayIsReachable)) {
                if activeRelayIsReachable {
                    markBackendReconnected()
                } else {
                    isLiveBackendConnected = syncResult.relayInstances.contains(where: \.status.isReachable)
                }
            } else if isLiveBackendConnected && activeHost.isOnline {
                connectionLifecyclePhase = isCascadeStreaming ? .onlineStreaming : .onlineIdle
            }

            let isSingleDirectHost = (activeHost.channel == .directHost)
            let refreshedLocalUuids = syncResult.refreshedLocalHostUuids
            let refreshedLocalNames = syncResult.refreshedLocalHostNames
            let refreshedCloud = syncResult.refreshedCloud
            let fallbackHostId = activeHost.instanceId
            let fallbackHostName = activeHost.hostname

            // 1. Merge workspaces: replace only scopes actually refreshed, preserve cached workspaces & 0-chat projects for other/offline hosts
            var mergedWorkspaces: [WorkspaceInfo] = []
            var mergedWorkspaceKeys = Set<String>()

            func appendWorkspaceIfUnique(_ ws: WorkspaceInfo) {
                let key = ws.isCloud
                    ? "cloud|\(ws.workspaceUri.lowercased())"
                    : "\(ws.originInstanceUuid ?? ws.originHostName ?? "local")|\(ws.workspaceUri.lowercased())"
                if mergedWorkspaceKeys.insert(key).inserted {
                    mergedWorkspaces.append(ws)
                }
            }

            for existingWs in workspaces where !Self.itemBelongsToRefreshedScope(
                isCloud: existingWs.isCloud,
                originUuid: existingWs.originInstanceUuid,
                originHost: existingWs.originHostName,
                refreshedLocalHostUuids: refreshedLocalUuids,
                refreshedLocalHostNames: refreshedLocalNames,
                refreshedCloud: refreshedCloud,
                fallbackActiveHostId: fallbackHostId,
                fallbackActiveHostName: fallbackHostName,
                isSingleDirectHost: isSingleDirectHost
            ) {
                appendWorkspaceIfUnique(existingWs)
            }

            for existingProj in projects where existingProj.runtime == .macBookPro
                && !existingProj.isNoProject
                && !Self.esddFixtureProjectIds.contains(existingProj.id)
                && !existingProj.workspaceUri.isEmpty
                && !Self.itemBelongsToRefreshedScope(
                    isCloud: false,
                    originUuid: existingProj.originInstanceUuid,
                    originHost: existingProj.hostName,
                    refreshedLocalHostUuids: refreshedLocalUuids,
                    refreshedLocalHostNames: refreshedLocalNames,
                    refreshedCloud: refreshedCloud,
                    fallbackActiveHostId: fallbackHostId,
                    fallbackActiveHostName: fallbackHostName,
                    isSingleDirectHost: isSingleDirectHost
                ) {
                appendWorkspaceIfUnique(
                    WorkspaceInfo(
                        workspaceUri: existingProj.workspaceUri,
                        displayName: existingProj.name,
                        activeBranch: existingProj.activeBranch,
                        worktrees: existingProj.worktrees,
                        isCloud: false,
                        originInstanceUuid: existingProj.originInstanceUuid,
                        originHostName: existingProj.hostName
                    )
                )
            }

            for freshWs in syncResult.workspaces {
                appendWorkspaceIfUnique(freshWs)
            }
            if !mergedWorkspaces.isEmpty || !syncResult.workspaces.isEmpty {
                workspaces = mergedWorkspaces
            }

            // 2. Merge summaries: replace refreshed host(s)/Cloud authoritatively while preserving cached conversations for unrefreshed/offline hosts
            let remoteSummaries = syncResult.summaries
            let existingById = Dictionary(uniqueKeysWithValues: summaries.map { ($0.cascadeId, $0) })
            let remoteIds = Set(remoteSummaries.map(\.cascadeId))
            var shouldResyncActiveCascade = false
            let now = Date()

            var mergedList: [CascadeSummary] = remoteSummaries.map { remote in
                var copy = remote
                if let existing = existingById[remote.cascadeId] {
                    let hasNewActivity = remote.stepCount > existing.stepCount
                        || remote.updatedAt.timeIntervalSince(existing.updatedAt) > 0.5
                    if existing.title != "New Conversation" && copy.title == "New Conversation" {
                        copy.title = existing.title
                    }
                    if existing.isCloud && !copy.isCloud {
                        copy.isCloud = true
                        copy.originHostName = "Antigravity"
                    }
                    copy.isPinned = existing.isPinned || remote.isPinned
                    copy.isArchived = existing.isArchived || remote.isArchived
                    copy.stepCount = max(existing.stepCount, remote.stepCount)
                    copy.currentStepIndex = max(1, copy.stepCount)
                    copy.totalSteps = max(1, copy.stepCount)
                    copy.cloudProjectId = remote.cloudProjectId ?? existing.cloudProjectId
                    copy.lastUserViewTime = [existing.lastUserViewTime, remote.lastUserViewTime].compactMap { $0 }.max()
                    if copy.originInstanceUuid == nil {
                        copy.originInstanceUuid = existing.originInstanceUuid
                        copy.originHostName = copy.originHostName ?? existing.originHostName
                    }
                    if let optimisticExpiry = optimisticActiveUntilByCascadeId[remote.cascadeId],
                       optimisticExpiry > now,
                       copy.status != .waiting && copy.status != .blocked && copy.status != .error {
                        copy.status = .inProgress
                    }
                    if hasNewActivity {
                        if activeRoute != .cascadeChat(remote.cascadeId) {
                            copy.isUnread = (copy.status != .inProgress && copy.status != .pending)
                            locallyViewedAtByCascadeId.removeValue(forKey: remote.cascadeId)
                        } else {
                            copy.isUnread = false
                            locallyViewedAtByCascadeId[remote.cascadeId] = now
                        }
                    } else if copy.status == .inProgress || copy.status == .pending {
                        copy.isUnread = false
                    } else if remote.lastUserViewTime == nil && existing.isUnread {
                        copy.isUnread = true
                    }
                    if remote.cascadeId == activeCascadeId && (
                        hasNewActivity
                            || remote.status != existing.status
                            || copy.status == .inProgress
                            || copy.status == .pending
                    ) {
                        shouldResyncActiveCascade = true
                    }
                } else if remote.cascadeId == activeCascadeId {
                    shouldResyncActiveCascade = true
                }
                if let viewedAt = locallyViewedAtByCascadeId[remote.cascadeId],
                   copy.updatedAt <= viewedAt {
                    copy.isUnread = false
                }
                if copy.isUnread != remote.isUnread
                    || copy.status != remote.status
                    || copy.stepCount != remote.stepCount {
                    copy.statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                        status: copy.status,
                        stepCount: copy.stepCount,
                        isUnread: copy.isUnread
                    )
                }
                return copy
            }

            // Preserve in-flight optimistic iOS sessions (`cas-*`) AND cached summaries belonging to unrefreshed/offline hosts
            for local in summaries where !remoteIds.contains(local.cascadeId)
                && !Self.esddFixtureCascadeIds.contains(local.cascadeId) {
                let isOptimisticLocal = local.cascadeId.hasPrefix("cas-") && (hasPairedBackend || isLiveBackendConnected)
                let belongsToUnrefreshedHost = !Self.itemBelongsToRefreshedScope(
                    isCloud: local.isCloud,
                    originUuid: local.originInstanceUuid,
                    originHost: local.originHostName,
                    refreshedLocalHostUuids: refreshedLocalUuids,
                    refreshedLocalHostNames: refreshedLocalNames,
                    refreshedCloud: refreshedCloud,
                    fallbackActiveHostId: fallbackHostId,
                    fallbackActiveHostName: fallbackHostName,
                    isSingleDirectHost: isSingleDirectHost
                )
                if isOptimisticLocal {
                    mergedList.insert(local, at: 0)
                } else if belongsToUnrefreshedHost {
                    mergedList.append(local)
                }
            }

            mergedList.sort { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.cascadeId < rhs.cascadeId
            }

            let effectiveCloudProjects: [ProjectWorkspace] = refreshedCloud
                ? syncResult.cloudProjects
                : projects.filter { $0.runtime == .cloud && !Self.esddFixtureProjectIds.contains($0.id) }

            if hasPairedBackend || isLiveBackendConnected {
                projects = Self.reconcileLiveProjects(
                    workspaces: workspaces,
                    summaries: &mergedList,
                    existingProjects: projects,
                    hostName: activeHost.hostname,
                    cloudProjects: effectiveCloudProjects
                )
                summaries = mergedList
                if selectedProjectId.isEmpty || !projects.contains(where: { $0.id == selectedProjectId }) {
                    let defaultProj = projects.first(where: { !$0.isNoProject }) ?? projects.first
                    selectedProjectId = defaultProj?.id ?? ""
                }
                if shouldResyncActiveCascade && !activeCascadeId.isEmpty {
                    syncStepsForCascade(
                        activeCascadeId,
                        pollUntilIdle: activeRoute == .cascadeChat(activeCascadeId)
                    )
                }
                var refreshedShardKeys = Set(refreshedLocalUuids.map { "host:\($0)" })
                if refreshedCloud {
                    refreshedShardKeys.insert("cloud")
                }
                await persistHostProjections(refreshedHostKeys: refreshedShardKeys.isEmpty ? nil : refreshedShardKeys)
            } else {
                var knownIds = Set(projects.map(\.id))
                for ws in workspaces where !knownIds.contains(ws.displayName) {
                    knownIds.insert(ws.displayName)
                    let isCloud = ws.isCloud || AntigravityCloudDetector.isCloudWorkspaceURI(ws.workspaceUri)
                    projects.insert(
                        ProjectWorkspace(
                            id: ws.displayName,
                            name: ws.displayName,
                            pathDisplay: ws.workspaceUri.replacingOccurrences(of: "file://", with: ""),
                            workspaceUri: ws.workspaceUri,
                            runtime: isCloud ? .cloud : .macBookPro,
                            hostName: isCloud ? "Cloud" : activeHost.hostname,
                            activeBranch: ws.activeBranch,
                            worktrees: ws.worktrees.isEmpty ? [ws.activeBranch] : ws.worktrees,
                            isExpandedInHome: true
                        ),
                        at: 0
                    )
                }
                for remote in mergedList {
                    if let idx = summaries.firstIndex(where: { $0.cascadeId == remote.cascadeId }) {
                        summaries[idx] = remote
                    } else {
                        summaries.append(remote)
                    }
                }
                await projectionStore.saveProjectedSummaries(summaries)
            }
        } catch {
            if error is CancellationError {
                return false
            }
            if case AntigravityRPCError.unauthorized = error {
                markBackendOffline(error: error)
                return false
            }
            if case let .localHost(targetId, targetName) = target,
               isRelay,
               hosts.contains(where: { $0.instanceId != targetId && $0.isOnline }) {
                updateSpecificLocalHostReachability(
                    instanceId: targetId,
                    hostname: targetName,
                    isOnline: false
                )
                return false
            }
            if Self.isBackendOfflineError(error) {
                consecutiveSyncFailures += 1
                let failureThreshold = ConnectionPowerPolicy.offlineFailureThreshold(
                    channel: activeHost.channel,
                    error: error
                )
                if consecutiveSyncFailures >= failureThreshold {
                    markBackendOffline(error: error)
                }
            }
            return false
        }

        if target == .allHosts && isLiveBackendConnected {
            if includeAutomations {
                await refreshAutomations(silent: true)
            } else if !automations.isEmpty {
                automations = Self.reconcileAutomations(automations, with: summaries)
            }
        }
        return true
    }

    // MARK: - Automations Actions (`UE06` — Native Antigravity 2.0 Sidecars)

    private static func formatAutomationError(_ error: Error, isCloudRelay: Bool = true) -> String {
        if let rpcErr = error as? AntigravityRPCError {
            switch rpcErr {
            case .unauthorized:
                if isCloudRelay {
                    return "Google 登录会话已过期，请点击下方重新登录。"
                }
                return "宿主机鉴权失败，请检查配对 Token 或重新配对。"
            case .httpError(let code, let body):
                let cleaned = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.isEmpty {
                    return "Host rejected request (HTTP \(code))."
                }
                return "Host error (\(code)): \(String(cleaned.prefix(160)))"
            case .invalidEndpoint:
                return "Host endpoint is unavailable."
            case .decodingError(let msg):
                return "Invalid response from host: \(msg)"
            case .interactionRejected:
                return "Automation action was rejected by host."
            }
        }
        return error.localizedDescription
    }

    private func recordAutomationError(_ error: Error, silent: Bool = false) {
        let isRelay = (activeHost.channel == .cloudRelay)
        if case AntigravityRPCError.unauthorized = error {
            isAutomationsAuthExpired = true
            connectionStatusText = isRelay ? "Google Sign-In Expired" : "Offline · \(activeHost.hostname) (Auth Expired)"
            automationsErrorText = Self.formatAutomationError(error, isCloudRelay: isRelay)
            return
        }
        if !silent || automations.isEmpty {
            automationsErrorText = Self.formatAutomationError(error, isCloudRelay: isRelay)
        }
    }

    /// Reconciles live Cascade summary state (`running`, `waiting`, `error`, `done`) onto Automations
    /// whose latest `GetSidecarEvents` payload references a `lastRunCascadeId`.
    public static func reconcileAutomations(
        _ items: [AutomationItem],
        with summaries: [CascadeSummary]
    ) -> [AutomationItem] {
        guard !items.isEmpty, !summaries.isEmpty else { return items }
        var byCascadeId: [String: CascadeSummary] = [:]
        for summary in summaries {
            byCascadeId[summary.cascadeId] = summary
        }
        return items.map { raw in
            var copy = raw
            guard let cid = copy.lastRunCascadeId, let summary = byCascadeId[cid] else {
                return copy
            }
            switch summary.status {
            case .inProgress, .pending:
                copy.isRunningNow = true
                copy.needsReview = false
                copy.lastRunText = "Running · \(summary.relativeTimeLabel)"
            case .waiting, .blocked:
                copy.isRunningNow = false
                copy.needsReview = true
                copy.lastRunText = "Needs review · \(summary.relativeTimeLabel)"
            case .error:
                copy.isRunningNow = false
                copy.needsReview = true
                let lower = copy.lastRunText.lowercased()
                if !lower.hasPrefix("failed") && !lower.hasPrefix("error") {
                    copy.lastRunText = "Failed · \(summary.relativeTimeLabel)"
                }
            case .done:
                copy.isRunningNow = false
                if copy.lastRunText.lowercased().hasPrefix("running") {
                    copy.lastRunText = "Succeeded · \(summary.relativeTimeLabel)"
                }
            case .unspecified, .cancelled:
                copy.isRunningNow = false
            }
            return copy
        }
    }

    private func preferredLocalAutomationProjectSlug() -> String {
        if let selected = selectedProject, selected.runtime != .cloud, !selected.isNoProject {
            return selected.name
        }
        if let firstLocal = projects.first(where: { $0.runtime != .cloud && !$0.isNoProject }) {
            return firstLocal.name
        }
        if hasPairedBackend || isLiveBackendConnected {
            return "This Computer"
        }
        return selectedProject?.id ?? "ledger-svc"
    }

    /// Refreshes native Antigravity 2.0 Automations via `GetSidecars` + `GetSidecarEvents`.
    public func refreshAutomations(silent: Bool = false) async {
        if isVerificationMode && !isLiveBackendConnected {
            return
        }
        guard !isNetworkingSuspended, isDeviceNetworkReachable else {
            return
        }
        guard let client = rpcClient, (hasPairedBackend || isLiveBackendConnected) else {
            return
        }
        if !silent {
            isLoadingAutomations = true
        }
        defer {
            if !silent {
                isLoadingAutomations = false
            }
        }
        do {
            let remote = try await client.listAutomations()
            let reconciled = Self.reconcileAutomations(remote, with: summaries)
            automations = reconciled
            automationsErrorText = nil
            isAutomationsAuthExpired = false
            lastAutomationsSyncAt = Date()
            await projectionStore.saveAutomations(reconciled)
        } catch {
            recordAutomationError(error, silent: silent)
        }
    }

    @discardableResult
    public func createAutomationFromPrompt(_ prompt: String = "") -> AutomationItem? {
        let raw = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? automationPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            : prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let parsed = AutomationScheduleCodec.parseNaturalLanguagePrompt(raw)
        let slug = preferredLocalAutomationProjectSlug()
        let optimisticId = parsed.sidecarId
        let item = AutomationItem(
            id: optimisticId,
            title: parsed.displayName,
            projectSlug: slug,
            scheduleSummary: "\(slug) · \(parsed.humanScheduleLabel) · Flash",
            section: .scheduled,
            nextRunText: AutomationScheduleCodec.nextFireDescription(from: parsed.cronExpression),
            lastRunText: (hasPairedBackend || isLiveBackendConnected) ? "Creating..." : "Created just now",
            needsReview: false,
            isRunningNow: false,
            descriptionText: "\(parsed.humanScheduleLabel): \(parsed.prompt)",
            prompt: parsed.prompt,
            cronExpression: parsed.cronExpression,
            projectId: nil,
            allProjects: slug == "All projects",
            modelLabel: "Flash",
            isEnabled: true,
            isScheduleBuiltin: true
        )
        automations.insert(item, at: 0)
        automationPromptDraft = ""
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        if isLive {
            isMutatingAutomation = true
        }

        Task { [weak self] in
            if !isLive {
                await storeRef.saveAutomations(snapshot)
                return
            }
            defer {
                self?.isMutatingAutomation = false
            }
            guard let clientRef else { return }
            do {
                let created = try await clientRef.createAutomation(
                    displayName: parsed.displayName,
                    prompt: parsed.prompt,
                    cronExpression: parsed.cronExpression,
                    projectSlug: slug,
                    projectId: nil,
                    allProjects: slug == "All projects",
                    modelArg: nil,
                    description: "\(parsed.humanScheduleLabel): \(parsed.prompt)",
                    enableImmediately: true
                )
                guard let self else { return }
                if let idx = self.automations.firstIndex(where: { $0.id == optimisticId }) {
                    self.automations[idx] = created
                } else {
                    self.automations.insert(created, at: 0)
                }
                self.automationsErrorText = nil
                await storeRef.saveAutomations(self.automations)
                await self.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                self.automations.removeAll { $0.id == optimisticId }
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
        return item
    }

    /// Creates a structured scheduled Automation via native `ManageSidecar(SIDECAR_ACTION_CREATE)`.
    @discardableResult
    public func createAutomation(
        displayName: String,
        prompt: String,
        cronExpression: String,
        projectSlug: String,
        projectId: String? = nil,
        allProjects: Bool = false,
        modelArg: String? = nil,
        description: String = "",
        enableImmediately: Bool = true
    ) async -> Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCron = cronExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty, !trimmedCron.isEmpty else {
            automationsErrorText = "Please enter a name, schedule, and prompt."
            return false
        }

        automationsErrorText = nil
        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        if !isLive {
            let humanSched = AutomationScheduleCodec.humanReadableSchedule(from: trimmedCron)
            let modelBadge = AutomationScheduleCodec.formatModelBadge(modelArg ?? "Flash")
            let slugLabel = projectSlug.isEmpty ? (allProjects ? "All projects" : "This Computer") : projectSlug
            let localItem = AutomationItem(
                id: AutomationScheduleCodec.makeSidecarId(from: trimmedName),
                title: trimmedName,
                projectSlug: slugLabel,
                scheduleSummary: "\(slugLabel) · \(humanSched) · \(modelBadge)",
                section: enableImmediately ? .scheduled : .paused,
                nextRunText: enableImmediately ? AutomationScheduleCodec.nextFireDescription(from: trimmedCron) : "Paused",
                lastRunText: enableImmediately ? "Created just now" : "Paused · New",
                descriptionText: description,
                prompt: trimmedPrompt,
                cronExpression: trimmedCron,
                projectId: projectId,
                allProjects: allProjects,
                modelLabel: modelBadge,
                isEnabled: enableImmediately,
                isScheduleBuiltin: true
            )
            automations.insert(localItem, at: 0)
            await projectionStore.saveAutomations(automations)
            return true
        }

        guard let client = rpcClient else { return false }
        isMutatingAutomation = true
        defer { isMutatingAutomation = false }

        do {
            let created = try await client.createAutomation(
                displayName: trimmedName,
                prompt: trimmedPrompt,
                cronExpression: trimmedCron,
                projectSlug: projectSlug,
                projectId: projectId,
                allProjects: allProjects,
                modelArg: modelArg,
                description: description,
                enableImmediately: enableImmediately
            )
            automations.removeAll { $0.id == created.id }
            automations.insert(created, at: 0)
            automationsErrorText = nil
            await projectionStore.saveAutomations(automations)
            await refreshAutomations(silent: true)
            return true
        } catch {
            recordAutomationError(error)
            return false
        }
    }

    /// Updates an existing scheduled Automation via `ManageSidecar(SIDECAR_ACTION_UPDATE)`.
    @discardableResult
    public func updateAutomation(
        automationId: String,
        displayName: String,
        prompt: String,
        cronExpression: String,
        projectSlug: String,
        projectId: String? = nil,
        allProjects: Bool = false,
        modelArg: String? = nil,
        description: String = ""
    ) async -> Bool {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCron = cronExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty, !trimmedCron.isEmpty else {
            automationsErrorText = "Please enter a name, schedule, and prompt."
            return false
        }

        automationsErrorText = nil
        let existing = automations.first(where: { $0.id == automationId })
        let originUuid = existing?.originInstanceUuid
        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil

        if isLive, let client = rpcClient {
            isMutatingAutomation = true
            defer { isMutatingAutomation = false }
            do {
                try await client.updateAutomation(
                    automationId: automationId,
                    displayName: trimmedName,
                    prompt: trimmedPrompt,
                    cronExpression: trimmedCron,
                    projectSlug: projectSlug,
                    projectId: projectId,
                    allProjects: allProjects,
                    modelArg: modelArg,
                    description: description,
                    instanceUuidOverride: originUuid
                )
            } catch {
                recordAutomationError(error)
                return false
            }
        }

        if let idx = automations.firstIndex(where: { $0.id == automationId }) {
            let humanSched = AutomationScheduleCodec.humanReadableSchedule(from: trimmedCron)
            let modelBadge = AutomationScheduleCodec.formatModelBadge(modelArg ?? automations[idx].modelLabel ?? "Flash")
            let slugLabel = projectSlug.isEmpty ? (allProjects ? "All projects" : "This Computer") : projectSlug
            automations[idx].title = trimmedName
            automations[idx].prompt = trimmedPrompt
            automations[idx].cronExpression = trimmedCron
            automations[idx].descriptionText = description
            automations[idx].projectSlug = slugLabel
            automations[idx].projectId = projectId
            automations[idx].allProjects = allProjects
            automations[idx].modelLabel = modelBadge
            automations[idx].scheduleSummary = "\(slugLabel) · \(humanSched) · \(modelBadge)"
            if automations[idx].section == .scheduled {
                automations[idx].nextRunText = AutomationScheduleCodec.nextFireDescription(from: trimmedCron)
            }
        }
        await projectionStore.saveAutomations(automations)
        if isLive {
            await refreshAutomations(silent: true)
        }
        return true
    }

    public func triggerAutomationNow(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let previous = automations[idx]
        automations[idx].isRunningNow = true
        automations[idx].needsReview = false
        automations[idx].lastRunText = "Running now..."
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        let originUuid = previous.originInstanceUuid
        let entry = OutboxEntry(cascadeId: automationId, kind: .automationTrigger, messageText: "ManageSidecar:RUN_NOW")

        Task { [weak self] in
            await storeRef.enqueueOutbox(entry)
            await storeRef.saveAutomations(snapshot)
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.triggerAutomationNow(
                    automationId: automationId,
                    instanceUuidOverride: originUuid
                )
                await storeRef.removeOutboxEntry(id: entry.id)
                // Follow up briefly so newly spawned conversation links to `lastRunCascadeId`.
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                await self?.refreshAutomations(silent: true)
                await self?.refreshWorkspacesAndSummaries()
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                await self?.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                await storeRef.removeOutboxEntry(id: entry.id)
                if let currentIdx = self.automations.firstIndex(where: { $0.id == automationId }) {
                    self.automations[currentIdx] = previous
                }
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
    }

    public func pauseAutomation(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let previous = automations[idx]
        automations[idx].section = .paused
        automations[idx].isEnabled = false
        automations[idx].isRunningNow = false
        automations[idx].nextRunText = "Paused"
        automations[idx].lastRunText = "Paused · just now"
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        let originUuid = previous.originInstanceUuid

        Task { [weak self] in
            await storeRef.saveAutomations(snapshot)
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.setAutomationPaused(
                    automationId: automationId,
                    isPaused: true,
                    instanceUuidOverride: originUuid
                )
                await self?.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                if let currentIdx = self.automations.firstIndex(where: { $0.id == automationId }) {
                    self.automations[currentIdx] = previous
                }
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
    }

    public func resumeAutomation(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let previous = automations[idx]
        let targetSection: AutomationSectionKind = previous.isScheduleBuiltin ? .scheduled : .alwaysOn
        automations[idx].section = targetSection
        automations[idx].isEnabled = true
        if targetSection == .scheduled {
            automations[idx].nextRunText = previous.cronExpression.isEmpty
                ? "Tomorrow, 08:00"
                : AutomationScheduleCodec.nextFireDescription(from: previous.cronExpression)
        } else {
            automations[idx].nextRunText = "Listening"
        }
        automations[idx].lastRunText = "Resumed · just now"
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        let originUuid = previous.originInstanceUuid

        Task { [weak self] in
            await storeRef.saveAutomations(snapshot)
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.setAutomationPaused(
                    automationId: automationId,
                    isPaused: false,
                    instanceUuidOverride: originUuid
                )
                await self?.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                if let currentIdx = self.automations.firstIndex(where: { $0.id == automationId }) {
                    self.automations[currentIdx] = previous
                }
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
    }

    public func deleteAutomation(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let removed = automations.remove(at: idx)
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let snapshot = automations
        let storeRef = projectionStore
        let clientRef = rpcClient
        let originUuid = removed.originInstanceUuid

        Task { [weak self] in
            await storeRef.saveAutomations(snapshot)
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.deleteAutomation(
                    automationId: automationId,
                    instanceUuidOverride: originUuid
                )
                await self?.refreshAutomations(silent: true)
            } catch {
                guard let self else { return }
                let insertIdx = min(idx, self.automations.count)
                self.automations.insert(removed, at: insertIdx)
                self.recordAutomationError(error)
                await storeRef.saveAutomations(self.automations)
            }
        }
    }

    public func restartAutomation(_ automationId: String) {
        guard let idx = automations.firstIndex(where: { $0.id == automationId }) else { return }
        let originUuid = automations[idx].originInstanceUuid
        automations[idx].lastRunText = "Restarting..."
        automationsErrorText = nil

        let isLive = (hasPairedBackend || isLiveBackendConnected) && rpcClient != nil
        let clientRef = rpcClient
        Task { [weak self] in
            guard isLive, let clientRef else { return }
            do {
                try await clientRef.restartAutomation(
                    automationId: automationId,
                    instanceUuidOverride: originUuid
                )
                await self?.refreshAutomations(silent: true)
            } catch {
                self?.recordAutomationError(error)
            }
        }
    }

    /// Opens an unsent draft composer pre-filled with the `/automation` workflow chip and editable guided prompt,
    /// matching Antigravity Desktop's "Create with Prompt" flow.
    /// Does NOT call `StartCascade`, does NOT auto-send, and does NOT add an entry to `summaries` until the user taps Send.
    public func openAutomationPromptDraft(prompt: String = "", projectSlug: String? = nil) {
        let trimmedRaw = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let strippedBody: String = {
            if trimmedRaw.lowercased() == "/automation" {
                return ""
            }
            if trimmedRaw.lowercased().hasPrefix("/automation ") {
                return String(trimmedRaw.dropFirst("/automation ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return trimmedRaw
        }()
        let initialBody = strippedBody.isEmpty ? Self.defaultAutomationGuidedPrompt : strippedBody
        let targetSlug: String = {
            if let explicit = projectSlug,
               !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let match = projects.first(where: { ($0.id == explicit || $0.name == explicit) && $0.runtime != .cloud }) {
                return match.id
            }
            return AntigravityCloudDetector.noProjectDisplayName
        }()
        let workspaceUri: String = {
            if AntigravityCloudDetector.isNoProjectSlug(targetSlug) {
                return ""
            }
            return projects.first(where: { $0.id == targetSlug || $0.name == targetSlug })?.workspaceUri ?? ""
        }()

        stepPollingTask?.cancel()
        stepPollingTask = nil
        isLoadingSteps = false
        stepLoadErrorText = nil

        pendingDraftConversation = PendingDraftConversation(
            title: "New Automation",
            projectSlug: targetSlug,
            isCloud: false,
            workflowCommand: "/automation",
            defaultGuidedPrompt: Self.defaultAutomationGuidedPrompt
        )
        activeCascadeId = ""
        selectedProjectId = targetSlug
        selectedWorkspaceUri = workspaceUri
        composerWorkflowCommand = "/automation"
        composerDraftText = initialBody
        composerAttachments.removeAll()
        isSlashPopupDismissedManually = true
        activeRoute = .cascadeChat("")
    }

    /// Discards an unsent draft conversation (e.g., tapping Back before sending) without creating any backend session.
    public func discardPendingDraftConversation() {
        guard pendingDraftConversation != nil else { return }
        pendingDraftConversation = nil
        composerWorkflowCommand = nil
        composerDraftText = ""
        composerAttachments.removeAll()
        isSlashPopupDismissedManually = false
    }

    /// Updates the target project for an unsent draft conversation (matching PC's `No Project ⌄` picker).
    public func updatePendingDraftProject(_ projectSlug: String) {
        guard var draft = pendingDraftConversation else { return }
        let trimmed = projectSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.projectSlug = trimmed.isEmpty ? AntigravityCloudDetector.noProjectDisplayName : trimmed
        pendingDraftConversation = draft
        selectedProjectId = draft.projectSlug
        if let proj = projects.first(where: { $0.id == draft.projectSlug || $0.name == draft.projectSlug }),
           !proj.isNoProject {
            selectedWorkspaceUri = proj.workspaceUri
        } else {
            selectedWorkspaceUri = ""
        }
    }

    /// Backwards-compatible alias that opens the interactive `/automation` prompt draft without auto-sending.
    public func createAutomationWithAgent(prompt: String = "", projectSlug: String? = nil) {
        openAutomationPromptDraft(prompt: prompt, projectSlug: projectSlug)
    }

    // MARK: - Add Context & Composer Actions (`UE07`, `UE08`, `UE09`)

    public func toggleContextCandidate(_ candidateId: String) {
        guard let idx = contextCandidates.firstIndex(where: { $0.id == candidateId }) else { return }
        contextCandidates[idx].isSelected.toggle()
    }

    public func applySelectedContextToComposer() {
        for candidate in contextCandidates where candidate.isSelected {
            if candidate.isActionTrigger {
                if !composerDraftText.hasPrefix(candidate.chipLabel) {
                    composerDraftText = "\(candidate.chipLabel) \(composerDraftText)".trimmingCharacters(in: .whitespaces)
                }
            } else if !composerAttachments.contains(where: { $0.label == candidate.chipLabel }) {
                composerAttachments.append(
                    ComposerAttachmentChip(
                        id: "chip-\(candidate.id)",
                        kind: candidate.attachmentKind,
                        label: candidate.chipLabel,
                        targetUri: "antigravity://context/\(candidate.id)"
                    )
                )
            }
        }
        presentedSheet = nil
    }

    public func applySlashCommand(_ item: SlashCommandItem) {
        composerDraftText = "\(item.command) "
        isSlashPopupDismissedManually = true
    }

    public func attachFileMention(_ filePath: String) {
        let fileName = (filePath as NSString).lastPathComponent
        let basePrefix: String = {
            if !isVerificationMode && selectedWorkspaceUri.hasPrefix("file://") {
                return selectedWorkspaceUri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            return "file:///Users/wl/code/ledger-svc"
        }()
        let chip = ComposerAttachmentChip(
            kind: .fileMention,
            label: "@\(fileName)",
            targetUri: "\(basePrefix)/\(filePath)"
        )
        if !composerAttachments.contains(where: { $0.targetUri == chip.targetUri || $0.label == chip.label }) {
            composerAttachments.append(chip)
        }
        if let lastRange = composerDraftText.range(of: "@[^\\s]*$", options: .regularExpression) {
            composerDraftText.removeSubrange(lastRange)
        }
    }

    public func removeAttachment(_ chipId: String) {
        composerAttachments.removeAll { $0.id == chipId }
    }

    public func sendCurrentDraft() {
        let trimmed = composerDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let workflowPrefix = composerWorkflowCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty || !composerAttachments.isEmpty || !workflowPrefix.isEmpty else { return }

        let combinedText: String = {
            if workflowPrefix.isEmpty {
                return trimmed
            }
            if trimmed.isEmpty {
                return workflowPrefix
            }
            if trimmed.lowercased().hasPrefix(workflowPrefix.lowercased()) {
                return trimmed
            }
            return "\(workflowPrefix) \(trimmed)"
        }()

        if workflowPrefix.isEmpty {
            let lowerTrim = trimmed.lowercased()
            if lowerTrim == "/btw" || lowerTrim.hasPrefix("/btw ") {
                let sidePrompt = trimmed.count > 4 ? String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                composerDraftText = ""
                openSideQuestion(initialPrompt: sidePrompt.isEmpty ? nil : sidePrompt)
                return
            }
            if lowerTrim == "/model" {
                composerDraftText = ""
                presentedSheet = .modelAndMode
                return
            }
            if lowerTrim == "/mode" {
                composerDraftText = ""
                if !selectedModelConfig.isOrchestrator {
                    selectedModelConfig.mode = (selectedModelConfig.mode == .planning) ? .fast : .planning
                }
                return
            }
            if lowerTrim == "/voice" {
                composerDraftText = ""
                startVoiceMode()
                return
            }
            if lowerTrim == "/clear" {
                composerDraftText = ""
                let targetProj = selectedProjectId.isEmpty ? (projects.first?.id ?? AntigravityCloudDetector.noProjectDisplayName) : selectedProjectId
                _ = createConversationInProject(targetProj)
                return
            }
        }

        if pendingDraftConversation == nil && isCascadeStreaming && (hasPairedBackend || isLiveBackendConnected) && !isVerificationMode {
            enqueueFollowUpMessage(combinedText, attachments: composerAttachments)
            composerWorkflowCommand = nil
            composerDraftText = ""
            composerAttachments.removeAll()
            return
        }

        let messageBody = combinedText.isEmpty
            ? "Inspect attached context: \(composerAttachments.map(\.label).joined(separator: ", "))"
            : combinedText
        let mentionLabels = composerAttachments.map(\.label)

        // Materialize an unsent pending draft conversation (e.g. Automations "Create with Prompt") only on Send.
        var materializedDirectly = false
        if let draft = pendingDraftConversation, activeCascadeId.isEmpty {
            materializedDirectly = true
            pendingDraftConversation = nil
            let optimisticId = "cas-\(UUID().uuidString.prefix(8).lowercased())"
            let project = projects.first(where: { $0.id == draft.projectSlug || $0.name == draft.projectSlug })
            let isUnassigned = (project?.isNoProject == true) || AntigravityCloudDetector.isNoProjectSlug(draft.projectSlug)
            let isCloudProj = draft.isCloud || (project?.runtime == .cloud) || draft.projectSlug.lowercased().hasPrefix("cloud:")
            let effectiveSlug: String = {
                if let project { return project.id }
                if isUnassigned {
                    let hasLocalNoProj = projects.contains(where: { $0.isNoProject && $0.runtime != .cloud })
                    if isCloudProj && hasLocalNoProj {
                        return "cloud:\(AntigravityCloudDetector.noProjectDisplayName)"
                    }
                    return AntigravityCloudDetector.noProjectDisplayName
                }
                return draft.projectSlug
            }()
            let draftWorkspaceUri: String = {
                if isUnassigned { return "" }
                if let existingUri = project?.workspaceUri, !existingUri.isEmpty {
                    return existingUri
                }
                if hasPairedBackend || isLiveBackendConnected {
                    return ""
                }
                return isCloudProj ? "cloud://\(effectiveSlug)" : "file:///Users/wl/code/\(effectiveSlug)"
            }()
            let branch = isUnassigned ? "" : (project?.activeBranch ?? "main")
            let effectiveTitle: String = {
                let isDefaultGuided = (trimmed == draft.defaultGuidedPrompt)
                if !trimmed.isEmpty && !isDefaultGuided && draft.title == "New Automation" {
                    return String(trimmed.prefix(48))
                }
                return draft.title
            }()
            let newSummary = CascadeSummary(
                cascadeId: optimisticId,
                title: effectiveTitle,
                projectSlug: effectiveSlug,
                workspaceUri: draftWorkspaceUri,
                branchName: branch,
                status: .inProgress,
                stepCount: 1,
                currentStepIndex: 1,
                totalSteps: 1,
                updatedAt: Date(),
                relativeTimeLabel: "now",
                statusSubtitle: "Running · Step 1 of 1",
                isPinned: displayOptions.autoPinOnMessage,
                isArchived: false,
                isUnread: false,
                modelLabel: selectedModelConfig.displayName,
                lastMessagePreview: messageBody,
                isCloud: isCloudProj,
                cloudProjectId: isUnassigned ? nil : project?.cloudProjectId,
                originInstanceUuid: project?.originInstanceUuid,
                originHostName: isCloudProj ? "Antigravity" : activeHost.hostname
            )
            summaries.insert(newSummary, at: 0)
            if hasPairedBackend || isLiveBackendConnected {
                let existingCloudProjects = projects.filter { $0.runtime == .cloud && $0.cloudProjectId != nil }
                var nextSummaries = summaries
                projects = Self.reconcileLiveProjects(
                    workspaces: workspaces,
                    summaries: &nextSummaries,
                    existingProjects: projects,
                    hostName: activeHost.hostname,
                    cloudProjects: existingCloudProjects
                )
                summaries = nextSummaries
            }
            stepsByCascadeId[optimisticId] = []
            activeCascadeId = optimisticId
            selectedProjectId = summaries.first(where: { $0.cascadeId == optimisticId })?.projectSlug ?? effectiveSlug
            selectedWorkspaceUri = draftWorkspaceUri
            activeRoute = .cascadeChat(optimisticId)
        }
        let skipUpgradeWait = materializedDirectly

        var currentSteps = stepsByCascadeId[activeCascadeId] ?? []
        let nextIndex = (currentSteps.map(\.stepIndex).max() ?? 0) + 1
        stepLoadErrorText = nil

        let userStep = CascadeStep(
            cascadeId: activeCascadeId,
            stepIndex: nextIndex,
            type: .userInput,
            status: .done,
            createdAt: Date(),
            userInput: messageBody,
            attachedMentions: mentionLabels,
            isQueuedInOutbox: false,
            recordedExecutionMode: selectedModelConfig.mode,
            recordedModelId: selectedModelConfig.modelId
        )
        currentSteps.append(userStep)
        if !activeCascadeId.isEmpty {
            syncedConfigCascadeIds.insert(activeCascadeId)
        }

        // Only synthesize ESDD offline mock response when NO backend is paired (`!hasPairedBackend && !isLiveBackendConnected`)
        if !hasPairedBackend && !isLiveBackendConnected {
            let assistantStep = CascadeStep(
                cascadeId: activeCascadeId,
                stepIndex: nextIndex + 1,
                type: .plannerResponse,
                status: .inProgress,
                createdAt: Date(),
                plannerResponse: PlannerResponsePayload(
                    response: "Running in `\(selectedModelConfig.mode.rawValue)` mode with `\(selectedModelConfig.displayName)` (`\(selectedModelConfig.agentPersona)` agent)...",
                    thinking: "Evaluating prompt with \(mentionLabels.count) context chips on branch \(activeSummary?.branchName ?? "main").",
                    thinkingDurationSeconds: 2.0,
                    referencedFiles: composerAttachments.map(\.targetUri)
                )
            )
            currentSteps.append(assistantStep)
        }
        stepsByCascadeId[activeCascadeId] = currentSteps
        locallyCreatedEmptyCascadeIds.remove(activeCascadeId)

        let currentSummary = summaries.first(where: { $0.cascadeId == activeCascadeId })
        let currentProj = projects.first(where: { $0.id == (currentSummary?.projectSlug ?? selectedProjectId) })
        let summaryIsCloud = currentSummary?.isCloud ?? (currentProj?.runtime == .cloud)
        let summaryCloudProjId = currentSummary?.cloudProjectId ?? currentProj?.cloudProjectId
        let summaryOriginUuid = currentSummary?.originInstanceUuid ?? currentProj?.originInstanceUuid

        if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
            summaries[sumIdx].stepCount = currentSteps.count
            summaries[sumIdx].status = .inProgress
            summaries[sumIdx].lastMessagePreview = messageBody
            summaries[sumIdx].relativeTimeLabel = "now"
            summaries[sumIdx].updatedAt = Date()
            if summaries[sumIdx].title == "New Conversation" {
                summaries[sumIdx].title = String(messageBody.prefix(48))
            }
            if displayOptions.autoPinOnMessage {
                summaries[sumIdx].isPinned = true
            }
        }

        let attachmentsSnapshot = composerAttachments
        composerWorkflowCommand = nil
        composerDraftText = ""
        composerAttachments.removeAll()
        isSlashPopupDismissedManually = false
        isAutoScrollPinnedToBottom = true

        let cid = activeCascadeId
        let cfg = selectedModelConfig
        let runtimeDefaultPreset = summaryIsCloud ? remotePermissionPreset : localPermissionPreset
        let effectivePreset: AgentPermissionPreset = {
            if let overridePreset = conversationPermissionPresets[cid], overridePreset != .inheritGlobal {
                return overridePreset
            }
            return runtimeDefaultPreset
        }()
        let storeRef = projectionStore
        let clientRef = rpcClient
        let shouldSendLive = (hasPairedBackend || isLiveBackendConnected)
        let isUnassignedSession = (currentProj?.isNoProject == true)
            || (currentSummary.map {
                AntigravityCloudDetector.isNoProjectSlug($0.projectSlug) && ($0.cloudProjectId ?? "").isEmpty
            } ?? false)
        let workspaceUri: String = {
            if isUnassignedSession {
                if let scratch = currentSummary?.workspaceUri, AntigravityCloudDetector.isPlaygroundScratchURI(scratch) {
                    return scratch
                }
                return ""
            }
            if let sumUri = currentSummary?.workspaceUri, !sumUri.isEmpty {
                return sumUri
            }
            if let projUri = currentProj?.workspaceUri, !projUri.isEmpty {
                return projUri
            }
            if !selectedWorkspaceUri.isEmpty {
                return selectedWorkspaceUri
            }
            return isVerificationMode ? "file:///Users/wl/code/ledger-svc" : ""
        }()

        let outboxEntry = OutboxEntry(cascadeId: cid, kind: .userMessage, messageText: messageBody)

        Task { [weak self] in
            await storeRef.enqueueOutbox(outboxEntry)
            await storeRef.saveProjectedSteps(currentSteps, for: cid)

            guard shouldSendLive, let clientRef else {
                await storeRef.removeOutboxEntry(id: outboxEntry.id)
                return
            }

            if let self, !self.isDeviceNetworkReachable {
                self.markStepQueuedInOutbox(cascadeId: cid, stepIndex: nextIndex)
                self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                if let updated = self.stepsByCascadeId[cid] {
                    await storeRef.saveProjectedSteps(updated, for: cid)
                }
                if let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == cid }) {
                    self.summaries[sumIdx].status = .pending
                    self.summaries[sumIdx].statusSubtitle = "Queued · Waiting for network"
                }
                return
            }

            var targetCascadeId = cid
            if !skipUpgradeWait && targetCascadeId.hasPrefix("cas-") {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let upgraded = self?.activeCascadeId, !upgraded.isEmpty, !upgraded.hasPrefix("cas-") {
                    targetCascadeId = upgraded
                }
            }

            do {
                if targetCascadeId.isEmpty || targetCascadeId.hasPrefix("cas-") {
                    let createdId = try await clientRef.startCascade(
                        workspaceUri: workspaceUri,
                        initialPrompt: "",
                        modelId: cfg.modelId,
                        cloudProjectId: summaryCloudProjId,
                        isCloud: summaryIsCloud,
                        instanceUuidOverride: summaryOriginUuid
                    )
                    if let self, !createdId.isEmpty {
                        self.locallyCreatedEmptyCascadeIds.remove(targetCascadeId)
                        self.locallyCreatedEmptyCascadeIds.remove(createdId)
                        let existing = self.stepsByCascadeId.removeValue(forKey: targetCascadeId) ?? currentSteps
                        self.stepsByCascadeId[createdId] = existing.map { step in
                            var copy = step
                            copy.cascadeId = createdId
                            return copy
                        }
                        self.syncedConfigCascadeIds.insert(createdId)
                        if let idx = self.summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                            self.summaries[idx].cascadeId = createdId
                        }
                        if self.activeCascadeId == targetCascadeId || self.activeCascadeId.isEmpty {
                            self.activeCascadeId = createdId
                            if case .cascadeChat = self.activeRoute {
                                self.activeRoute = .cascadeChat(createdId)
                            }
                        }
                        targetCascadeId = createdId
                    }
                }

                if let self, !targetCascadeId.isEmpty {
                    self.optimisticActiveUntilByCascadeId[targetCascadeId] = Date().addingTimeInterval(45)
                    self.syncStepsForCascade(targetCascadeId, pollUntilIdle: true)
                }

                try await clientRef.sendUserCascadeMessage(
                    cascadeId: targetCascadeId,
                    message: messageBody,
                    attachments: attachmentsSnapshot,
                    modelId: cfg.modelId,
                    effort: cfg.effort,
                    mode: cfg.mode,
                    agentPersona: cfg.agentPersona,
                    isModelAlias: cfg.isModelAlias,
                    isCloud: summaryIsCloud,
                    permissionPreset: effectivePreset,
                    instanceUuidOverride: summaryOriginUuid
                )
                await storeRef.removeOutboxEntry(id: outboxEntry.id)

                if let self {
                    self.lastBackendActivityAt = Date()
                    self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                    if self.hasPairedBackend && (!self.isLiveBackendConnected || !self.activeHost.isOnline) {
                        self.markBackendReconnected()
                    }
                    if !targetCascadeId.isEmpty {
                        self.syncStepsForCascade(targetCascadeId, pollUntilIdle: true)
                    }
                }
            } catch {
                if let self {
                    let stepsAdvanced = (self.stepsByCascadeId[targetCascadeId]?.count ?? 0) > currentSteps.count
                    if stepsAdvanced && !targetCascadeId.isEmpty {
                        await storeRef.removeOutboxEntry(id: outboxEntry.id)
                        self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                        // Turn already started streaming on backend despite unary HTTP timeout; keep polling steps
                        self.syncStepsForCascade(targetCascadeId, pollUntilIdle: true)
                    } else if Self.isBackendOfflineError(error) {
                        // Keep entry persisted in Durable Outbox so it automatically replays once host reconnects
                        self.optimisticActiveUntilByCascadeId.removeValue(forKey: targetCascadeId)
                        self.markStepQueuedInOutbox(cascadeId: targetCascadeId, stepIndex: nextIndex)
                        if let updated = self.stepsByCascadeId[targetCascadeId] {
                            await storeRef.saveProjectedSteps(updated, for: targetCascadeId)
                        }
                        self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                        if let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                            self.summaries[sumIdx].status = .pending
                            self.summaries[sumIdx].statusSubtitle = "Queued · Will send when back online"
                        }
                        if self.activeHost.channel != .cloudRelay {
                            self.markBackendOffline(error: error)
                        }
                    } else {
                        await storeRef.removeOutboxEntry(id: outboxEntry.id)
                        self.pendingOutboxCount = await storeRef.loadPendingOutbox().count
                        self.optimisticActiveUntilByCascadeId.removeValue(forKey: targetCascadeId)
                        self.stepLoadErrorText = "Failed to send message: \(error.localizedDescription)"
                        if let sumIdx = self.summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                            self.summaries[sumIdx].status = .done
                            self.summaries[sumIdx].statusSubtitle = "Send failed · Tap to retry"
                        }
                    }
                }
            }
        }
    }

    private func markStepQueuedInOutbox(cascadeId: String, stepIndex: Int) {
        guard var steps = stepsByCascadeId[cascadeId],
              let idx = steps.lastIndex(where: { $0.stepIndex == stepIndex && $0.type == .userInput }) else {
            return
        }
        steps[idx].isQueuedInOutbox = true
        stepsByCascadeId[cascadeId] = steps
    }

    /// Replays persisted offline Durable Outbox user messages in FIFO order once the paired host reconnects.
    public func replayPendingOutbox() async {
        guard !isReplayingOutbox,
              !isVerificationMode,
              !isNetworkingSuspended,
              isDeviceNetworkReachable,
              isLiveBackendConnected,
              activeHost.isOnline,
              let clientRef = rpcClient else {
            return
        }

        isReplayingOutbox = true
        defer { isReplayingOutbox = false }

        let pending = await projectionStore.loadPendingOutbox()
        pendingOutboxCount = pending.count
        guard !pending.isEmpty else { return }

        let cfg = selectedModelConfig
        for entry in pending {
            guard !isNetworkingSuspended, isDeviceNetworkReachable, isLiveBackendConnected else { break }
            guard entry.kind == .userMessage,
                  let messageBody = entry.messageText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !messageBody.isEmpty else {
                await projectionStore.removeOutboxEntry(id: entry.id)
                continue
            }

            var targetCascadeId = entry.cascadeId
            let currentSummary = summaries.first(where: { $0.cascadeId == targetCascadeId })
            let currentProj = projects.first(where: { $0.id == (currentSummary?.projectSlug ?? selectedProjectId) })
            let summaryIsCloud = currentSummary?.isCloud ?? (currentProj?.runtime == .cloud)
            let summaryCloudProjId = currentSummary?.cloudProjectId ?? currentProj?.cloudProjectId
            let summaryOriginUuid = currentSummary?.originInstanceUuid ?? currentProj?.originInstanceUuid
            let workspaceUri = currentSummary?.workspaceUri ?? currentProj?.workspaceUri ?? selectedWorkspaceUri

            do {
                if targetCascadeId.isEmpty || targetCascadeId.hasPrefix("cas-") {
                    let createdId = try await clientRef.startCascade(
                        workspaceUri: workspaceUri,
                        initialPrompt: "",
                        modelId: cfg.modelId,
                        cloudProjectId: summaryCloudProjId,
                        isCloud: summaryIsCloud,
                        instanceUuidOverride: summaryOriginUuid
                    )
                    if !createdId.isEmpty {
                        locallyCreatedEmptyCascadeIds.remove(targetCascadeId)
                        locallyCreatedEmptyCascadeIds.remove(createdId)
                        if let existing = stepsByCascadeId.removeValue(forKey: targetCascadeId) {
                            stepsByCascadeId[createdId] = existing.map { step in
                                var copy = step
                                copy.cascadeId = createdId
                                return copy
                            }
                        }
                        if let idx = summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                            summaries[idx].cascadeId = createdId
                        }
                        if activeCascadeId == targetCascadeId || activeCascadeId.isEmpty {
                            activeCascadeId = createdId
                            if case .cascadeChat = activeRoute {
                                activeRoute = .cascadeChat(createdId)
                            }
                        }
                        targetCascadeId = createdId
                    }
                }

                try await clientRef.sendUserCascadeMessage(
                    cascadeId: targetCascadeId,
                    message: messageBody,
                    attachments: [],
                    modelId: cfg.modelId,
                    effort: cfg.effort,
                    mode: cfg.mode,
                    agentPersona: cfg.agentPersona,
                    isModelAlias: cfg.isModelAlias,
                    isCloud: summaryIsCloud,
                    permissionPreset: summaryIsCloud ? remotePermissionPreset : localPermissionPreset,
                    instanceUuidOverride: summaryOriginUuid
                )

                await projectionStore.removeOutboxEntry(id: entry.id)
                lastBackendActivityAt = Date()

                if var steps = stepsByCascadeId[targetCascadeId] {
                    for i in steps.indices where steps[i].isQueuedInOutbox && steps[i].userInput == messageBody {
                        steps[i].isQueuedInOutbox = false
                    }
                    stepsByCascadeId[targetCascadeId] = steps
                    await projectionStore.saveProjectedSteps(steps, for: targetCascadeId)
                }
                if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == targetCascadeId }) {
                    summaries[sumIdx].status = .inProgress
                    summaries[sumIdx].statusSubtitle = "Running"
                }
                if !targetCascadeId.isEmpty {
                    optimisticActiveUntilByCascadeId[targetCascadeId] = Date().addingTimeInterval(45)
                    syncStepsForCascade(targetCascadeId, pollUntilIdle: true)
                }
            } catch {
                if Self.isBackendOfflineError(error) {
                    // Host dropped again mid-replay: keep remaining entries persisted for next reconnect
                    break
                } else {
                    await projectionStore.removeOutboxEntry(id: entry.id)
                }
            }
        }

        pendingOutboxCount = await projectionStore.loadPendingOutbox().count
    }

    public func stopActiveCascadeStreaming() {
        optimisticActiveUntilByCascadeId.removeValue(forKey: activeCascadeId)
        manuallyCancelledCascadeIds.insert(activeCascadeId)
        guard var currentSteps = stepsByCascadeId[activeCascadeId] else { return }
        for i in currentSteps.indices where currentSteps[i].status == .inProgress || currentSteps[i].status == .pending || currentSteps[i].status == .waiting {
            currentSteps[i].status = .cancelled
        }
        stepsByCascadeId[activeCascadeId] = currentSteps
        let originUuid = summaries.first(where: { $0.cascadeId == activeCascadeId })?.originInstanceUuid
        if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
            summaries[sumIdx].status = .cancelled
            summaries[sumIdx].statusSubtitle = "Stopped"
        }
        let cid = activeCascadeId
        let clientRef = rpcClient
        Task {
            try? await clientRef?.cancelCascadeInvocation(cascadeId: cid, instanceUuidOverride: originUuid)
        }
    }

    // MARK: - Step Expansion & Face ID Command Approval Actions (`UE07`, `UE13`)

    public func toggleThinkingExpanded(stepId: String) {
        if expandedThinkingStepIds.contains(stepId) {
            expandedThinkingStepIds.remove(stepId)
        } else {
            expandedThinkingStepIds.insert(stepId)
        }
    }

    public func toggleEvidenceGroupExpanded(groupId: String) {
        if expandedEvidenceGroupIds.contains(groupId) {
            expandedEvidenceGroupIds.remove(groupId)
        } else {
            expandedEvidenceGroupIds.insert(groupId)
        }
    }

    public func toggleTerminalOutputExpanded(stepId: String) {
        if expandedTerminalStepIds.contains(stepId) {
            expandedTerminalStepIds.remove(stepId)
        } else {
            expandedTerminalStepIds.insert(stepId)
        }
    }

    public func approveWaitingCommandWithFaceID(stepIndex: Int? = nil) {
        let targetIdx = stepIndex ?? pendingWaitingStep?.stepIndex
        guard let resolvedStepIndex = targetIdx else { return }
        resolveWaitingStep(stepIndex: resolvedStepIndex, decision: .allowWithFaceID)
    }

    public func denyWaitingCommand(stepIndex: Int? = nil) {
        let targetIdx = stepIndex ?? pendingWaitingStep?.stepIndex
        guard let resolvedStepIndex = targetIdx else { return }
        resolveWaitingStep(stepIndex: resolvedStepIndex, decision: .reject)
    }

    public func resolveWaitingStep(
        stepIndex: Int,
        decision: InteractionDecision
    ) {
        guard var steps = stepsByCascadeId[activeCascadeId],
              let idx = steps.firstIndex(where: { $0.stepIndex == stepIndex }) else {
            return
        }
        let targetStep = steps[idx]
        let payload = InteractionBuilder.buildPayload(
            step: targetStep,
            decision: decision,
            workspaceUri: selectedWorkspaceUri
        )
        lastDispatchedInteraction = payload

        switch decision {
        case .reject:
            steps[idx].status = .cancelled
            if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
                summaries[sumIdx].status = .cancelled
                summaries[sumIdx].statusSubtitle = "Denied · Awaiting instructions"
                summaries[sumIdx].pendingInteractionTitle = nil
            }
        case .allowOnce, .allowWithFaceID, .alwaysAllowInTurn, .allowInConversation, .alwaysAllow, .allowWithModifiedCommand, .answerQuestion:
            if (decision == .alwaysAllowInTurn || decision == .allowInConversation || decision == .alwaysAllow),
               let pattern = targetStep.requestedInteraction?.permission?.suggestedPersistPattern {
                activeTurnGrants.insert(pattern)
                if decision == .alwaysAllow, let spec = targetStep.requestedInteraction?.permission {
                    let ruleAction = PermissionRuleAction(rawValue: spec.action.lowercased()) ?? .command
                    addPermissionRule(PermissionRuleEntry(list: .allow, action: ruleAction, target: pattern))
                }
            }
            steps[idx].status = .done

            // Advance 7-segment task checklist if present
            if let tbIdx = steps.lastIndex(where: { $0.type == .taskBoundary }),
               var boundary = steps[tbIdx].taskBoundary {
                boundary.completedCount = min(boundary.totalCount, boundary.completedCount + 1)
                boundary.taskName = "Task · \(boundary.completedCount) of \(boundary.totalCount) done"
                for cIdx in boundary.checklist.indices where boundary.checklist[cIdx].status == .waiting {
                    boundary.checklist[cIdx].status = .done
                    boundary.checklist[cIdx].trailingBadge = "p99 4.2ms"
                }
                steps[tbIdx].taskBoundary = boundary
            }

            if !hasPairedBackend && !isLiveBackendConnected {
                let nextStepIndex = (steps.map(\.stepIndex).max() ?? stepIndex) + 1
                let followUp = CascadeStep(
                    cascadeId: activeCascadeId,
                    stepIndex: nextStepIndex,
                    type: .plannerResponse,
                    status: .done,
                    plannerResponse: PlannerResponsePayload(
                        response: "Face ID verified — executed `\(targetStep.runCommand?.commandLine ?? "approved action")`. Load test sustained 2,000 req/s with 0 drops.",
                        thinking: "Received signed HandleCascadeUserInteraction approval on step \(stepIndex).",
                        thinkingDurationSeconds: 1.4
                    )
                )
                steps.append(followUp)

                if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
                    summaries[sumIdx].status = .done
                    summaries[sumIdx].stepCount = steps.count
                    summaries[sumIdx].currentStepIndex = min(summaries[sumIdx].totalSteps, summaries[sumIdx].currentStepIndex + 1)
                    summaries[sumIdx].statusSubtitle = "Done · Load test passed"
                    summaries[sumIdx].pendingInteractionTitle = nil
                    summaries[sumIdx].updatedAt = Date()
                }
            } else if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
                summaries[sumIdx].status = .inProgress
                summaries[sumIdx].statusSubtitle = "Running · Approved action"
                summaries[sumIdx].pendingInteractionTitle = nil
                summaries[sumIdx].updatedAt = Date()
            }
        }

        stepsByCascadeId[activeCascadeId] = steps
        presentedSheet = nil

        if let payload, let clientRef = rpcClient {
            let storeRef = projectionStore
            let cid = activeCascadeId
            let originUuid = summaries.first(where: { $0.cascadeId == cid })?.originInstanceUuid
            let shouldSyncLive = (hasPairedBackend || isLiveBackendConnected)
            let isRejection = (decision == .reject)
            let entry = OutboxEntry(cascadeId: cid, kind: .interactionApproval, messageText: "\(payload.stepIndex)")
            Task { [weak self] in
                await storeRef.enqueueOutbox(entry)
                var interactionError: String? = nil
                do {
                    try await clientRef.handleCascadeUserInteraction(payload, instanceUuidOverride: originUuid)
                } catch {
                    if shouldSyncLive {
                        interactionError = error.localizedDescription
                    }
                }
                await storeRef.removeOutboxEntry(id: entry.id)
                guard let self else { return }
                if let interactionError {
                    self.stepLoadErrorText = "Approval failed: \(interactionError)"
                } else if shouldSyncLive && !isRejection {
                    self.optimisticActiveUntilByCascadeId[cid] = Date().addingTimeInterval(6.0)
                }
                if shouldSyncLive && !cid.isEmpty {
                    self.syncStepsForCascade(cid, pollUntilIdle: !isRejection && interactionError == nil)
                }
            }
        }
    }

    // MARK: - Structured Multi-Step Question Actions (`UE10`)

    public func toggleQuestionOption(_ option: String, stepIndex: Int? = nil) {
        let idx = stepIndex ?? activeQuestionStepIndex
        guard questionSteps.indices.contains(idx) else { return }
        if questionSteps[idx].selectedOptions.contains(option) {
            questionSteps[idx].selectedOptions.remove(option)
        } else {
            if !questionSteps[idx].isMultiSelect {
                questionSteps[idx].selectedOptions.removeAll()
            }
            questionSteps[idx].selectedOptions.insert(option)
        }
    }

    public func advanceQuestionStep() {
        guard questionSteps.indices.contains(activeQuestionStepIndex) else { return }
        questionSteps[activeQuestionStepIndex].isCompleted = true
        if activeQuestionStepIndex + 1 < questionSteps.count {
            activeQuestionStepIndex += 1
        } else if let waiting = pendingWaitingStep {
            let combinedOptions = questionSteps.flatMap { Array($0.selectedOptions).sorted() }
            let custom = questionSteps
                .map(\.customWriteIn)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "; ")
            resolveWaitingStep(
                stepIndex: waiting.stepIndex,
                decision: .answerQuestion(
                    selectedOptions: combinedOptions,
                    customWriteIn: custom.isEmpty ? nil : custom
                )
            )
        }
    }

    public func previousQuestionStep() {
        guard activeQuestionStepIndex > 0 else { return }
        activeQuestionStepIndex -= 1
    }

    public func submitFreeformQuestionReply(_ text: String? = nil) {
        let body = (text ?? questionFreeformReplyDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        questionFreeformReplyDraft = ""
        if let waiting = pendingWaitingStep {
            resolveWaitingStep(
                stepIndex: waiting.stepIndex,
                decision: .answerQuestion(selectedOptions: [], customWriteIn: body)
            )
        } else {
            composerDraftText = body
            sendCurrentDraft()
        }
    }

    // MARK: - Implementation Plan Review Actions (`UE11`)

    @discardableResult
    public func addPlanComment(
        targetFilePath: String = "settlement/settlement_test.go",
        quotedSpan: String = "remove the package-level clk variable",
        body: String
    ) -> PlanInlineComment? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let comment = PlanInlineComment(
            authorInitials: "WL",
            authorName: "You",
            statusLabel: "Pending",
            targetFilePath: targetFilePath,
            quotedSpan: quotedSpan,
            body: trimmed
        )
        planComments.append(comment)
        return comment
    }

    public func sendPlanCommentsToAgent() {
        guard !planComments.isEmpty else { return }
        for idx in planComments.indices {
            planComments[idx].statusLabel = "Sent"
        }
        let commentsSnapshot = planComments
        let cid = activeCascadeId
        if let idx = summaries.firstIndex(where: { $0.cascadeId == "cas-flaky-settlement" }) {
            summaries[idx].status = .inProgress
            summaries[idx].statusSubtitle = "Running · Addressing \(commentsSnapshot.count) plan comments"
            summaries[idx].isUnread = false
        }
        activeRoute = .cascadeChat(cid)

        let storeRef = projectionStore
        let clientRef = rpcClient
        let entry = OutboxEntry(
            cascadeId: cid,
            kind: .planComments,
            messageText: "Sent \(commentsSnapshot.count) plan review comments"
        )
        Task {
            await storeRef.enqueueOutbox(entry)
            try? await clientRef?.sendPlanReviewComments(cascadeId: cid, comments: commentsSnapshot)
            await storeRef.removeOutboxEntry(id: entry.id)
        }
    }

    public func approveArtifactPlan(artifactPath: String = "/brain/implementation_plan.md") {
        if let idx = activeArtifacts.firstIndex(where: { $0.artifactPath == artifactPath }) {
            activeArtifacts[idx].requestFeedback = false
            activeArtifacts[idx].summary = "Approved · \(planComments.count) comments addressed"
        }
        if let waiting = pendingWaitingStep {
            resolveWaitingStep(stepIndex: waiting.stepIndex, decision: .allowOnce)
        }
        activeRoute = .cascadeChat(activeCascadeId)
    }

    // MARK: - Turn Diff Line-Level Review Actions (`UE12`)

    public func selectNextDiffFile() {
        guard !activeTurnDiffs.isEmpty else { return }
        selectedDiffFileIndex = (selectedDiffFileIndex + 1) % activeTurnDiffs.count
    }

    public func selectPreviousDiffFile() {
        guard !activeTurnDiffs.isEmpty else { return }
        selectedDiffFileIndex = (selectedDiffFileIndex - 1 + activeTurnDiffs.count) % activeTurnDiffs.count
    }

    public func addDiffComment(filePath: String, lineNumber: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        diffComments.append(
            DiffLineComment(filePath: filePath, lineNumber: lineNumber, body: trimmed, sentToAgent: false)
        )
    }

    public func submitDiffLineComment(sendImmediately: Bool) {
        let trimmed = activeLineCommentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let path = currentDiffFile?.filePath ?? "middleware/ratelimit.go"
        let line = selectedDiffLineNumber ?? 29
        let comment = DiffLineComment(
            filePath: path,
            lineNumber: line,
            body: trimmed,
            sentToAgent: sendImmediately
        )
        diffComments.append(comment)
        activeLineCommentDraft = ""

        if sendImmediately {
            let cid = activeCascadeId
            let clientRef = rpcClient
            let storeRef = projectionStore
            let entry = OutboxEntry(cascadeId: cid, kind: .diffComments, messageText: comment.body)
            Task {
                await storeRef.enqueueOutbox(entry)
                try? await clientRef?.sendDiffReviewComments(cascadeId: cid, comments: [comment])
                await storeRef.removeOutboxEntry(id: entry.id)
            }
        }
    }

    public func toggleDiffFileViewed() {
        guard activeTurnDiffs.indices.contains(selectedDiffFileIndex) else { return }
        activeTurnDiffs[selectedDiffFileIndex].isReviewed.toggle()
    }

    public func acceptCurrentDiffFile() {
        guard activeTurnDiffs.indices.contains(selectedDiffFileIndex) else { return }
        activeTurnDiffs.remove(at: selectedDiffFileIndex)
        if activeTurnDiffs.isEmpty {
            selectedDiffFileIndex = 0
            activeRoute = .cascadeChat(activeCascadeId)
        } else {
            selectedDiffFileIndex = min(selectedDiffFileIndex, activeTurnDiffs.count - 1)
        }
    }

    public func acceptPatchFile(_ filePath: String) {
        if let idx = activeTurnDiffs.firstIndex(where: { $0.filePath == filePath }) {
            selectedDiffFileIndex = idx
            acceptCurrentDiffFile()
        }
    }

    public func revertCurrentDiffHunk() {
        guard let current = currentDiffFile else { return }
        let cid = activeCascadeId
        let clientRef = rpcClient
        Task {
            try? await clientRef?.revertDiffHunk(
                cascadeId: cid,
                filePath: current.filePath,
                hunkHeader: current.hunkHeader
            )
        }
    }

    public func revertCurrentDiffFile() {
        guard activeTurnDiffs.indices.contains(selectedDiffFileIndex) else { return }
        let removed = activeTurnDiffs.remove(at: selectedDiffFileIndex)
        if let sumIdx = summaries.firstIndex(where: { $0.cascadeId == activeCascadeId }) {
            summaries[sumIdx].totalAdditions = max(0, summaries[sumIdx].totalAdditions - removed.additions)
            summaries[sumIdx].totalDeletions = max(0, summaries[sumIdx].totalDeletions - removed.deletions)
        }
        if activeTurnDiffs.isEmpty {
            selectedDiffFileIndex = 0
            activeRoute = .cascadeChat(activeCascadeId)
        } else {
            selectedDiffFileIndex = min(selectedDiffFileIndex, activeTurnDiffs.count - 1)
        }
        let cid = activeCascadeId
        let clientRef = rpcClient
        Task {
            try? await clientRef?.revertDiffHunk(cascadeId: cid, filePath: removed.filePath, hunkHeader: nil)
        }
    }

    public func acceptAllTurnDiffs() {
        activeTurnDiffs.removeAll()
        selectedDiffFileIndex = 0
        activeRoute = .cascadeChat(activeCascadeId)
    }

    // MARK: - Antigravity 2.0 (v2.33) Capabilities (P0 - P2)

    /// Returns the effective permission preset for a conversation (falls back to global preset).
    public func effectivePermissionPreset(for cascadeId: String? = nil) -> AgentPermissionPreset {
        let cid = cascadeId ?? activeCascadeId
        if let explicit = conversationPermissionPresets[cid], explicit != .inheritGlobal {
            return explicit
        }
        return activePermissionPreset
    }

    public func setConversationPermissionPreset(_ preset: AgentPermissionPreset, for cascadeId: String? = nil) {
        let cid = cascadeId ?? activeCascadeId
        if preset == .inheritGlobal {
            conversationPermissionPresets.removeValue(forKey: cid)
        } else {
            conversationPermissionPresets[cid] = preset
        }
        let clientRef = rpcClient
        if !cid.isEmpty {
            Task {
                try? await clientRef?.setConversationPermissionPreset(cascadeId: cid, preset: preset)
            }
        }
    }

    public func addPermissionRule(_ rule: PermissionRuleEntry) {
        if !permissionRules.contains(where: { $0.formattedRule == rule.formattedRule && $0.list == rule.list }) {
            permissionRules.append(rule)
        }
    }

    public func removePermissionRule(id: String) {
        permissionRules.removeAll { $0.id == id }
    }

    // MARK: - Persistent Sidebar Collapse & Appearance Preferences

    public func isProjectCollapsed(_ projectId: String) -> Bool {
        appearancePreferences.collapsedProjectIds.contains(projectId)
    }

    public func toggleProjectCollapsedPersisted(_ projectId: String) {
        if appearancePreferences.collapsedProjectIds.contains(projectId) {
            appearancePreferences.collapsedProjectIds.remove(projectId)
        } else {
            appearancePreferences.collapsedProjectIds.insert(projectId)
        }
        if let idx = projects.firstIndex(where: { $0.id == projectId }) {
            projects[idx].isExpandedInHome = !appearancePreferences.collapsedProjectIds.contains(projectId)
        }
        saveAppearancePreferences()
    }

    public func saveAppearancePreferences() {
        let snapshot = appearancePreferences
        let storeRef = projectionStore
        Task {
            await storeRef.saveAppearancePreferences(snapshot)
        }
    }

    public func loadPersistedV233Preferences() async {
        if let prefs = await projectionStore.loadAppearancePreferences() {
            appearancePreferences = prefs
            for idx in projects.indices {
                projects[idx].isExpandedInHome = !prefs.collapsedProjectIds.contains(projects[idx].id)
            }
        }
        if let quota = await projectionStore.loadUsageQuota() {
            usageQuota = quota
        }
        if let custom = await projectionStore.loadCustomizations() {
            customizations = custom
        }
    }

    // MARK: - Conversation Overview, Subagents & Background Tasks

    public func refreshConversationOverview() async {
        let cid = activeCascadeId
        let steps = activeSteps

        // Extract local fallback overview from live steps & diffs so Overview always works offline or live
        var extractedSubagents: [SubagentPayload] = []
        var extractedPRs: [GitHubPullRequestInfo] = []
        var extractedDocs: [String] = []
        var seenPrIds: Set<String> = []
        for step in steps {
            if let sub = step.subagent {
                extractedSubagents.append(sub)
            }
            if let resp = step.plannerResponse?.response {
                for pr in AntigravityMarkdownParser.extractGitHubPRLinks(from: resp) where seenPrIds.insert(pr.id).inserted {
                    extractedPRs.append(pr)
                }
            }
            for ref in step.plannerResponse?.referencedFiles ?? [] {
                if !extractedDocs.contains(ref) { extractedDocs.append(ref) }
            }
        }

        if let client = rpcClient, !cid.isEmpty, (hasPairedBackend || isLiveBackendConnected) {
            if let remote = try? await client.fetchConversationOverview(cascadeId: cid) {
                var merged = remote
                merged.artifacts = activeArtifacts
                if merged.subagents.isEmpty { merged.subagents = extractedSubagents }
                if merged.pullRequests.isEmpty { merged.pullRequests = extractedPRs }
                if merged.modifiedFiles.isEmpty { merged.modifiedFiles = activeTurnDiffs.map(\.filePath) }
                if merged.reviewAdditions == 0 { merged.reviewAdditions = activeTurnDiffs.reduce(0) { $0 + $1.additions } }
                if merged.reviewDeletions == 0 { merged.reviewDeletions = activeTurnDiffs.reduce(0) { $0 + $1.deletions } }
                conversationOverview = merged
                return
            }
        }

        conversationOverview = ConversationOverviewSnapshot(
            reviewAdditions: activeTurnDiffs.reduce(0) { $0 + $1.additions },
            reviewDeletions: activeTurnDiffs.reduce(0) { $0 + $1.deletions },
            modifiedFiles: activeTurnDiffs.map(\.filePath),
            subagents: extractedSubagents,
            backgroundTasks: conversationOverview.backgroundTasks,
            goals: conversationOverview.goals,
            artifacts: activeArtifacts,
            documentLinks: extractedDocs,
            pullRequests: extractedPRs
        )
    }

    public func cancelBackgroundTask(_ taskId: String) {
        if let idx = conversationOverview.backgroundTasks.firstIndex(where: { $0.id == taskId }) {
            conversationOverview.backgroundTasks[idx].status = .cancelled
            conversationOverview.backgroundTasks[idx].canCancel = false
        }
        let cid = activeCascadeId
        let clientRef = rpcClient
        Task {
            try? await clientRef?.cancelBackgroundTask(cascadeId: cid, taskId: taskId)
        }
    }

    public func stopSubagent(_ subagentId: String) {
        if let idx = conversationOverview.subagents.firstIndex(where: { $0.subagentId == subagentId }) {
            conversationOverview.subagents[idx].status = .cancelled
        }
        let cid = activeCascadeId
        let clientRef = rpcClient
        Task {
            try? await clientRef?.stopSubagent(cascadeId: cid, subagentId: subagentId)
        }
    }

    // MARK: - Multi-Turn /btw Side Questions

    public func openSideQuestion(initialPrompt: String? = nil) {
        if sideQuestionThread.parentCascadeId != activeCascadeId {
            sideQuestionThread = SideQuestionThread(parentCascadeId: activeCascadeId)
        }
        presentedSheet = .sideQuestion
        if let initialPrompt, !initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendSideQuestion(initialPrompt)
        }
    }

    public func sendSideQuestion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if sideQuestionThread.parentCascadeId != activeCascadeId {
            sideQuestionThread = SideQuestionThread(parentCascadeId: activeCascadeId)
        }
        sideQuestionThread.messages.append(SideQuestionMessage(isUser: true, text: trimmed))
        sideQuestionThread.isStreaming = true

        let cid = activeCascadeId
        let threadId = sideQuestionThread.threadId
        let clientRef = rpcClient
        let isLive = (hasPairedBackend || isLiveBackendConnected)

        Task { [weak self] in
            let reply: SideQuestionMessage
            if isLive, let clientRef, !cid.isEmpty,
               let remoteReply = try? await clientRef.sendSideQuestion(cascadeId: cid, question: trimmed, threadId: threadId) {
                reply = remoteReply
            } else {
                reply = SideQuestionMessage(
                    isUser: false,
                    text: "Read-only side analysis (does not mutate main context): `\(trimmed)` — checked current branch `\(self?.activeSummary?.branchName ?? "main")` and \(self?.activeSteps.count ?? 0) conversation steps."
                )
            }
            self?.sideQuestionThread.messages.append(reply)
            self?.sideQuestionThread.isStreaming = false
        }
    }

    public func insertSideQuestionAnswerIntoMain() {
        guard let answer = sideQuestionThread.latestAssistantAnswer, !answer.isEmpty else { return }
        let prefix = composerDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        composerDraftText += "\(prefix)From /btw side note:\n> \(answer)"
        presentedSheet = nil
    }

    public func resetSideQuestionThread() {
        sideQuestionThread = SideQuestionThread(parentCascadeId: activeCascadeId)
    }

    // MARK: - Message Queueing, Conversation Navigator & Revert to Step

    public func enqueueFollowUpMessage(_ text: String, attachments: [ComposerAttachmentChip] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queuedMessages.append(
            QueuedMessageItem(cascadeId: activeCascadeId, text: trimmed, attachments: attachments)
        )
    }

    public func updateQueuedMessage(id: String, newText: String) {
        if let idx = queuedMessages.firstIndex(where: { $0.id == id }) {
            queuedMessages[idx].text = newText
        }
    }

    public func removeQueuedMessage(id: String) {
        queuedMessages.removeAll { $0.id == id }
    }

    public func flushNextQueuedMessageIfIdle() {
        guard !isCascadeStreaming,
              let idx = queuedMessages.firstIndex(where: { $0.cascadeId == activeCascadeId }) else {
            return
        }
        let next = queuedMessages.remove(at: idx)
        composerDraftText = next.text
        composerAttachments = next.attachments
        sendCurrentDraft()
    }

    public var conversationTurns: [ConversationTurnSummary] {
        var turnNumber = 0
        return activeSteps.compactMap { step in
            guard step.type == .userInput, let text = step.userInput, !text.isEmpty else { return nil }
            turnNumber += 1
            return ConversationTurnSummary(
                turnNumber: turnNumber,
                stepIndex: step.stepIndex,
                promptPreview: String(text.prefix(72)),
                timestamp: step.createdAt
            )
        }
    }

    public func revertConversationToStep(_ stepIndex: Int) {
        guard var steps = stepsByCascadeId[activeCascadeId] else { return }
        steps.removeAll { $0.stepIndex > stepIndex }
        stepsByCascadeId[activeCascadeId] = steps
        let cid = activeCascadeId
        let clientRef = rpcClient
        let storeRef = projectionStore
        Task {
            await storeRef.saveProjectedSteps(steps, for: cid)
            try? await clientRef?.revertConversationToStep(cascadeId: cid, stepIndex: stepIndex)
        }
    }

    // MARK: - Live Artifacts, Diff Hydration & Git VCS (Stage / Unstage / Discard / Commit / Push / Quote)

    public func loadLiveArtifactsAndDiffs(for cascadeId: String? = nil) async {
        guard !isVerificationMode, let client = rpcClient else { return }
        let cid = cascadeId ?? activeCascadeId
        guard !cid.isEmpty else { return }

        if let snapshots = try? await client.getArtifactSnapshots(cascadeId: cid), !snapshots.isEmpty {
            activeArtifacts = snapshots
            if !snapshots.contains(where: { $0.artifactPath == selectedArtifactPath }) {
                selectedArtifactPath = snapshots[0].artifactPath
            }
        }
        if let diffs = try? await client.getTurnDiff(
            cascadeId: cid,
            turnNumber: diffCompareMode == .turn ? selectedDiffTurn : nil,
            compareMode: diffCompareMode
        ) {
            if !diffs.isEmpty || (hasPairedBackend || isLiveBackendConnected) {
                activeTurnDiffs = diffs
                selectedDiffFileIndex = min(selectedDiffFileIndex, max(0, diffs.count - 1))
            }
        }
    }

    public func setDiffCompareMode(_ mode: DiffCompareMode) {
        diffCompareMode = mode
        if !isVerificationMode && (hasPairedBackend || isLiveBackendConnected) {
            Task { [weak self] in
                await self?.loadLiveArtifactsAndDiffs()
            }
        }
    }

    public func toggleStageDiffFile(at index: Int? = nil) {
        let idx = index ?? selectedDiffFileIndex
        guard activeTurnDiffs.indices.contains(idx) else { return }
        activeTurnDiffs[idx].isStaged.toggle()
        let filePath = activeTurnDiffs[idx].filePath
        let nowStaged = activeTurnDiffs[idx].isStaged
        let cid = activeCascadeId
        let clientRef = rpcClient
        Task {
            if nowStaged {
                try? await clientRef?.gitStageFile(cascadeId: cid, filePath: filePath)
            } else {
                try? await clientRef?.gitUnstageFile(cascadeId: cid, filePath: filePath)
            }
        }
    }

    public func discardDiffFile(at index: Int? = nil) {
        let idx = index ?? selectedDiffFileIndex
        guard activeTurnDiffs.indices.contains(idx) else { return }
        let removed = activeTurnDiffs.remove(at: idx)
        selectedDiffFileIndex = min(selectedDiffFileIndex, max(0, activeTurnDiffs.count - 1))
        let cid = activeCascadeId
        let clientRef = rpcClient
        Task {
            try? await clientRef?.gitDiscardFile(cascadeId: cid, filePath: removed.filePath)
        }
    }

    public func commitDiffChanges() async -> GitCommitResult? {
        let message = gitCommitDraft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }
        let draft = gitCommitDraft
        let cid = activeCascadeId
        let branch = activeSummary?.branchName ?? "main"
        let result: GitCommitResult
        if let client = rpcClient, (hasPairedBackend || isLiveBackendConnected),
           let remoteResult = try? await client.gitCommitChanges(cascadeId: cid, draft: draft) {
            result = remoteResult
        } else {
            result = GitCommitResult(
                commitSha: String(UUID().uuidString.prefix(7)).lowercased(),
                commitMessage: message,
                branchName: branch,
                pushed: false
            )
        }
        lastCommitResult = result
        gitCommitDraft.message = ""
        if draft.includeUnstaged {
            activeTurnDiffs.removeAll()
        } else {
            activeTurnDiffs.removeAll(where: \.isStaged)
        }
        selectedDiffFileIndex = 0
        return result
    }

    public func pushCurrentDiffBranch() async -> Bool {
        let cid = activeCascadeId
        let branch = activeSummary?.branchName ?? "main"
        let pushed: Bool
        if let client = rpcClient, (hasPairedBackend || isLiveBackendConnected) {
            pushed = (try? await client.gitPushBranch(cascadeId: cid, branchName: branch)) ?? false
        } else {
            pushed = true
        }
        if pushed, var last = lastCommitResult {
            last.pushed = true
            lastCommitResult = last
        }
        return pushed
    }

    public func quoteDiffLinesToComposer(filePath: String, startLine: Int, endLine: Int, snippet: String) {
        let fileName = (filePath as NSString).lastPathComponent
        let rangeLabel = startLine == endLine ? "L\(startLine)" : "L\(startLine)-L\(endLine)"
        let chip = ComposerAttachmentChip(
            kind: .codeQuote,
            label: "\(fileName):\(rangeLabel)",
            targetUri: "\(filePath)#\(rangeLabel)"
        )
        if !composerAttachments.contains(where: { $0.targetUri == chip.targetUri }) {
            composerAttachments.append(chip)
        }
        let cleanSnippet = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSnippet.isEmpty {
            let prefix = composerDraftText.isEmpty ? "" : "\n"
            composerDraftText += "\(prefix)Regarding `\(fileName):\(rangeLabel)`:\n```\n\(cleanSnippet)\n```\n"
        }
        activeRoute = .cascadeChat(activeCascadeId)
    }

    public func addImageRegionComment(_ comment: ImageRegionComment) {
        imageRegionComments.append(comment)
    }

    // MARK: - Live Structured Question Hydration (`UE10`)

    public func syncActiveLiveQuestionFromSteps(stepIndex: Int? = nil) {
        guard !isVerificationMode else { return }
        guard let waiting = waitingStep(at: stepIndex),
              let ask = waiting.effectiveRequestedInteraction?.askQuestion else {
            return
        }
        let stepId = "live-q-\(waiting.stepIndex)"
        if questionSteps.first?.id != stepId {
            questionSteps = [
                StructuredQuestionStepItem(
                    id: stepId,
                    stepNumber: 1,
                    shortTabTitle: "Question",
                    questionTitle: ask.question,
                    options: ask.options,
                    selectedOptions: [],
                    customWriteIn: "",
                    isCompleted: false,
                    isMultiSelect: ask.isMultiSelect
                )
            ]
            activeQuestionStepIndex = 0
        }
    }

    // MARK: - Customizations Hub (Skills, Rules, MCP Servers, Plugins Marketplace, Hooks)

    public func refreshCustomizations() async {
        guard let client = rpcClient, (hasPairedBackend || isLiveBackendConnected) else { return }
        if let fetched = try? await client.fetchCustomizationsCatalog() {
            customizations = fetched
            await projectionStore.saveCustomizations(fetched)
        }
    }

    public func restartMcpServer(_ serverName: String) {
        if let idx = customizations.mcpServers.firstIndex(where: { $0.name == serverName }) {
            customizations.mcpServers[idx].state = .connected
            customizations.mcpServers[idx].errorMessage = nil
        }
        let clientRef = rpcClient
        Task {
            try? await clientRef?.restartMcpServer(serverName: serverName)
        }
    }

    public func togglePlugin(_ pluginId: String, isEnabled: Bool) {
        if let idx = customizations.plugins.firstIndex(where: { $0.id == pluginId }) {
            customizations.plugins[idx].isEnabled = isEnabled
        }
        let snapshot = customizations
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveCustomizations(snapshot)
            try? await clientRef?.togglePlugin(pluginId: pluginId, isEnabled: isEnabled)
        }
    }

    public func installPlugin(_ pluginId: String) {
        if let idx = customizations.plugins.firstIndex(where: { $0.id == pluginId }) {
            customizations.plugins[idx].isInstalled = true
            customizations.plugins[idx].isEnabled = true
        }
        let snapshot = customizations
        let storeRef = projectionStore
        let clientRef = rpcClient
        Task {
            await storeRef.saveCustomizations(snapshot)
            try? await clientRef?.installMarketplacePlugin(pluginId: pluginId)
        }
    }

    // MARK: - Gemini Live Voice Mode

    public func startVoiceMode() {
        voiceModeState.isActive = true
        voiceModeState.isMuted = false
        voiceModeState.startedAt = Date()
        if voiceModeState.activeTurns.isEmpty {
            voiceModeState.activeTurns.append(
                VoiceTranscriptTurn(
                    isUser: false,
                    transcript: "Connected to Gemini Live Voice Mode (\(voiceModeState.selectedVoiceId.capitalized)). How can I help with \(activeSummary?.projectSlug ?? "this workspace")?"
                )
            )
        }
        presentedSheet = .voiceMode
    }

    public func toggleVoiceMute() {
        voiceModeState.isMuted.toggle()
    }

    public func interruptVoiceAgent() {
        voiceModeState.isAgentSpeaking = false
    }

    public func selectVoiceOption(_ voiceId: String) {
        voiceModeState.selectedVoiceId = voiceId
    }

    public func setVoicePlaybackSpeed(_ speed: Double) {
        voiceModeState.playbackSpeed = min(2.0, max(0.75, speed))
    }

    public func appendVoiceTranscriptTurn(isUser: Bool, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        voiceModeState.activeTurns.append(VoiceTranscriptTurn(isUser: isUser, transcript: trimmed))
        if isUser {
            voiceModeState.isAgentSpeaking = true
            let ack = "Got it — queued voice instruction: \"\(trimmed)\" on \(activeSummary?.title ?? "active conversation")."
            voiceModeState.activeTurns.append(VoiceTranscriptTurn(isUser: false, transcript: ack))
            voiceModeState.isAgentSpeaking = false
        }
    }

    public func endVoiceMode() {
        guard voiceModeState.isActive else {
            presentedSheet = nil
            return
        }
        let duration = max(1, Int(Date().timeIntervalSince(voiceModeState.startedAt ?? Date())))
        let turns = voiceModeState.activeTurns
        let userTurnCount = turns.filter(\.isUser).count
        let summary = VoiceCallTranscriptSummary(
            cascadeId: activeCascadeId,
            durationSeconds: duration,
            summaryText: "Voice Mode session (\(duration)s · \(userTurnCount) spoken prompts · \(voiceModeState.selectedVoiceId.capitalized))",
            turns: turns
        )
        voiceModeState.lastCallSummary = summary
        voiceModeState.isActive = false
        voiceModeState.isAgentSpeaking = false
        voiceModeState.activeTurns = []

        if !activeCascadeId.isEmpty {
            var currentSteps = stepsByCascadeId[activeCascadeId] ?? []
            let nextIdx = (currentSteps.map(\.stepIndex).max() ?? 0) + 1
            let callStep = CascadeStep(
                cascadeId: activeCascadeId,
                stepIndex: nextIdx,
                type: .plannerResponse,
                status: .done,
                plannerResponse: PlannerResponsePayload(response: summary.summaryText),
                voiceSummary: summary
            )
            currentSteps.append(callStep)
            stepsByCascadeId[activeCascadeId] = currentSteps
        }
        presentedSheet = nil
    }

    // MARK: - Full-Text Search, Slash Commands & Typo-Tolerant @Mentions

    public func runFullTextConversationSearch(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remoteSearchResults = []
            isSearchingAllConversations = false
            return
        }
        isSearchingAllConversations = true
        defer { isSearchingAllConversations = false }

        if let client = rpcClient, (hasPairedBackend || isLiveBackendConnected),
           let remote = try? await client.searchAllConversations(query: trimmed),
           !remote.isEmpty {
            remoteSearchResults = remote
            return
        }

        // Offline/local full-text fallback across titles, previews, and loaded step contents
        let q = trimmed.lowercased()
        remoteSearchResults = summaries.filter { summary in
            if summary.title.lowercased().contains(q)
                || summary.projectSlug.lowercased().contains(q)
                || summary.statusSubtitle.lowercased().contains(q)
                || (summary.lastMessagePreview?.lowercased().contains(q) ?? false) {
                return true
            }
            if let steps = stepsByCascadeId[summary.cascadeId] {
                return steps.contains { step in
                    (step.userInput?.lowercased().contains(q) ?? false)
                        || (step.plannerResponse?.response.lowercased().contains(q) ?? false)
                }
            }
            return false
        }
    }

    public func filteredSlashCommands(for draft: String) -> [SlashCommandItem] {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return [] }
        let query = String(trimmed.dropFirst()).lowercased()
        let isRemote = activeSummary?.isCloud ?? false
        let all = SlashCommandItem.commands(isRemoteAgent: isRemote, customSkills: customizations.skills)
        guard !query.isEmpty else { return all }
        return all.filter { item in
            item.command.lowercased().contains(query)
                || item.title.lowercased().contains(query)
                || item.summary.lowercased().contains(query)
        }
    }

    public func filteredMentionCandidates(for query: String) -> [ContextCandidateItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return contextCandidates }
        return contextCandidates.filter { candidate in
            let hay = "\(candidate.title) \(candidate.subtitle)".lowercased()
            if hay.contains(q) { return true }
            // Typo-tolerant subsequence match for @ mentions (v2.32.0+)
            var qIdx = q.startIndex
            for ch in hay {
                if qIdx < q.endIndex && ch == q[qIdx] {
                    qIdx = q.index(after: qIdx)
                }
            }
            return qIdx == q.endIndex
        }
    }

    // MARK: - Live Activity & Share Extension Shared Bridge Reconciliation

    public func consumePendingLiveActivityActions() async {
        let actions = await SharedAppGroupBridge.shared.drainLiveActivityActions()
        guard !actions.isEmpty else { return }
        for action in actions {
            if !action.cascadeId.isEmpty {
                activeCascadeId = action.cascadeId
            }
            switch action.kind {
            case .approveWithFaceID:
                approveWaitingCommandWithFaceID(stepIndex: action.stepIndex > 0 ? action.stepIndex : nil)
            case .deny:
                denyWaitingCommand(stepIndex: action.stepIndex > 0 ? action.stepIndex : nil)
            case .stopTurn:
                stopActiveCascadeStreaming()
            }
        }
    }

    public func consumePendingSharePayload(id: String? = nil) async -> Bool {
        guard let payload = await SharedAppGroupBridge.shared.consumeSharePayload(id: id) else {
            return false
        }
        var parts: [String] = []
        if !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(payload.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let urlStr = payload.urlString, !urlStr.isEmpty {
            parts.append(urlStr)
            composerAttachments.append(
                ComposerAttachmentChip(kind: .genericFile, label: urlStr, targetUri: urlStr)
            )
        }
        if let fname = payload.fileName, !fname.isEmpty {
            composerAttachments.append(
                ComposerAttachmentChip(kind: .genericFile, label: fname, targetUri: "share://\(fname)")
            )
        }
        let joined = parts.joined(separator: "\n")
        if !joined.isEmpty {
            composerDraftText = composerDraftText.isEmpty ? joined : "\(composerDraftText)\n\(joined)"
        }
        if activeCascadeId.isEmpty, let first = summaries.first {
            activeCascadeId = first.cascadeId
        }
        if !activeCascadeId.isEmpty {
            activeRoute = .cascadeChat(activeCascadeId)
        }
        return true
    }

    /// Evaluates NotificationPolicy on a status transition and emits a local notification payload when eligible.
    public func evaluateNotificationTransition(
        cascadeId: String,
        title: String,
        previousStatus: CortexStepStatus,
        newStatus: CortexStepStatus
    ) {
        let wasManualStop = manuallyCancelledCascadeIds.contains(cascadeId)
        if NotificationPolicy.shouldNotify(
            previousStatus: previousStatus,
            newStatus: newStatus,
            wasManuallyCancelled: wasManualStop,
            preferences: appearancePreferences
        ) {
            let body: String
            switch newStatus {
            case .waiting: body = "Approval or input required in \(title)"
            case .done: body = "Agent finished working on \(title)"
            case .error: body = "Run encountered an error in \(title)"
            default: body = "Status updated in \(title)"
            }
            lastNotificationEvent = (id: UUID().uuidString, title: title, body: body, cascadeId: cascadeId)
        }
    }

    // MARK: - Deterministic Scene Routing Helper (`UE01` .. `UE13`)

    public func configureForVerifyScene(_ scene: ESDDVerifySceneCase) {
        isVerificationMode = true
        isInitialSessionCheckComplete = true
        presentedSheet = nil
        switch scene {
        case .agentsHome:
            selectedTab = .agents
            activeRoute = .tabRoot
        case .displayOptions:
            selectedTab = .agents
            activeRoute = .tabRoot
            presentedSheet = .displayOptions
            isSortPopoverPresented = true
        case .contextMenuPin:
            selectedTab = .agents
            activeRoute = .tabRoot
            contextMenuTargetCascadeId = "cas-flaky-settlement"
            swipePreviewCascadeId = "cas-upgrade-go"
            presentedSheet = .contextMenuPreview(cascadeId: "cas-flaky-settlement")
        case .projectDetail:
            selectedTab = .agents
            selectedProjectId = "ledger-svc"
            selectedProjectTab = .active
            // Align ledger-svc to Active 3 / Archived 2 (5 conversations) as depicted in UE04
            if let idx = summaries.firstIndex(where: { $0.cascadeId == "cas-idempotency-payouts" }) {
                summaries[idx].isArchived = true
            }
            summaries.removeAll { $0.cascadeId == "cas-pgx-v5-migration" }
            activeRoute = .projectDetail("ledger-svc")
        case .createProject:
            selectedTab = .agents
            activeRoute = .tabRoot
            presentedSheet = .createProject
        case .automations:
            selectedTab = .automations
            activeRoute = .tabRoot
        case .chatAndComposer:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            activeRoute = .cascadeChat("cas-rate-limiter")
        case .addContext:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            activeRoute = .cascadeChat("cas-rate-limiter")
            presentedSheet = .addContext
        case .modelAndMode:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            activeRoute = .cascadeChat("cas-rate-limiter")
            presentedSheet = .modelAndMode
        case .structuredQuestion:
            selectedTab = .agents
            activeCascadeId = "cas-audit-log-admin"
            activeQuestionStepIndex = 1
            activeRoute = .cascadeChat("cas-audit-log-admin")
        case .planReview:
            selectedTab = .agents
            activeCascadeId = "cas-flaky-settlement"
            selectedArtifactPath = "/brain/implementation_plan.md"
            activeRoute = .planReview
        case .turnDiffReview:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            selectedDiffTurn = 3
            selectedDiffFileIndex = 0
            selectedDiffLineNumber = 29
            activeRoute = .turnDiffReview
        case .liveActivitySpec:
            selectedTab = .agents
            activeCascadeId = "cas-rate-limiter"
            activeRoute = .cascadeChat("cas-rate-limiter")
        }
    }

    // MARK: - Deterministic 1:1 UE Fixture Factory (`UE01` .. `UE13`)

    public static func makeESDDVerificationStore() -> AntigravitySessionStore {
        let macHost = RemoteHostInstance(
            instanceId: "macbook-pro-local",
            hostname: "MacBook Pro",
            version: "v2.32.0",
            channel: .directHost,
            endpointURL: URL(string: "https://127.0.0.1:42100")!,
            isOnline: true,
            latencyMs: 6
        )
        let cloudHost = RemoteHostInstance(
            instanceId: "cloud-vm-us-central1",
            hostname: "Cloud",
            version: "v2.32.0",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/cloud-vm-us-central1")!,
            isOnline: true,
            latencyMs: 24
        )

        let projects: [ProjectWorkspace] = [
            ProjectWorkspace(
                id: "ledger-svc",
                name: "ledger-svc",
                pathDisplay: "~/code/ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                runtime: .macBookPro,
                hostName: "MacBook Pro",
                activeBranch: "main",
                worktrees: ["main", "feat/ratelimit", "fix/settlement-clock"],
                isExpandedInHome: true,
                rulesAndSkillsCount: 4
            ),
            ProjectWorkspace(
                id: "web-console",
                name: "web-console",
                pathDisplay: "cloud://acme/web-console",
                workspaceUri: "cloud://acme/web-console",
                runtime: .cloud,
                hostName: "Cloud",
                activeBranch: "main",
                worktrees: ["main", "feat/dark-mode"],
                isExpandedInHome: true,
                rulesAndSkillsCount: 3
            )
        ]

        let workspaces: [WorkspaceInfo] = [
            WorkspaceInfo(
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                displayName: "ledger-svc",
                activeBranch: "main",
                worktrees: ["main", "feat/ratelimit", "fix/settlement-clock"],
                activeCascadeCount: 3,
                indexedFiles: [
                    "internal/middleware/ratelimit.go",
                    "internal/router/transfers.go",
                    "internal/settlement/batch.go",
                    "internal/settlement/settlement_test.go",
                    "load/transfers.txt"
                ]
            ),
            WorkspaceInfo(
                workspaceUri: "cloud://acme/web-console",
                displayName: "web-console",
                activeBranch: "main",
                worktrees: ["main", "feat/dark-mode"],
                activeCascadeCount: 2,
                indexedFiles: [
                    "src/pages/settings/DarkModeToggle.tsx",
                    "src/theme/tokens.ts"
                ]
            )
        ]

        let baseNow = Date(timeIntervalSince1970: 1_762_793_357)
        let summaries: [CascadeSummary] = [
            CascadeSummary(
                cascadeId: "cas-rate-limiter",
                title: "Add rate limiter to /transfers",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .inProgress,
                stepCount: 28,
                currentStepIndex: 4,
                totalSteps: 7,
                updatedAt: baseNow,
                relativeTimeLabel: "now",
                statusSubtitle: "Running · Step 4 of 7 · go test ./internal/...",
                isPinned: true,
                isArchived: false,
                isUnread: false,
                modelLabel: "Gemini 3.1 Pro",
                pendingInteractionTitle: "Approve: vegeta attack...",
                lastMessagePreview: "Plan approved with your 2 comments. Tests pass — next is a load test, which needs your OK.",
                totalAdditions: 128,
                totalDeletions: 14
            ),
            CascadeSummary(
                cascadeId: "cas-flaky-settlement",
                title: "Fix flaky TestSettlementBatch",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .waiting,
                stepCount: 12,
                currentStepIndex: 2,
                totalSteps: 5,
                updatedAt: baseNow.addingTimeInterval(-480),
                relativeTimeLabel: "8m",
                statusSubtitle: "Needs review · Implementation plan ready",
                isPinned: false,
                isArchived: false,
                isUnread: true,
                modelLabel: "Gemini 3.1 Pro",
                pendingInteractionTitle: "Awaiting review · Implementation Plan",
                lastMessagePreview: "The flake comes from a shared fake clock across parallel subtests in settlement_test.go. I wrote a plan to isolate it per test — review it before I change anything?",
                totalAdditions: 0,
                totalDeletions: 0
            ),
            CascadeSummary(
                cascadeId: "cas-release-checklist",
                title: "Release checklist v2.3",
                projectSlug: "web-console",
                workspaceUri: "cloud://acme/web-console",
                branchName: "main",
                status: .done,
                stepCount: 19,
                currentStepIndex: 5,
                totalSteps: 5,
                updatedAt: baseNow.addingTimeInterval(-3500),
                relativeTimeLabel: "1h",
                statusSubtitle: "Done · Walkthrough ready",
                isPinned: true,
                isArchived: false,
                isUnread: false,
                modelLabel: "Gemini 3.8 Flash",
                lastMessagePreview: "All v2.3 release checks succeeded and walkthrough artifact is ready.",
                totalAdditions: 34,
                totalDeletions: 8
            ),
            CascadeSummary(
                cascadeId: "cas-upgrade-go",
                title: "Upgrade to Go 1.25",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .done,
                stepCount: 31,
                currentStepIndex: 6,
                totalSteps: 6,
                updatedAt: baseNow.addingTimeInterval(-3600),
                relativeTimeLabel: "1h",
                statusSubtitle: "Done · 6 files changed",
                isPinned: false,
                isArchived: false,
                isUnread: true,
                modelLabel: "Gemini 3.1 Pro",
                lastMessagePreview: "Updated go.mod toolchain to Go 1.25 across 6 packages.",
                totalAdditions: 42,
                totalDeletions: 31
            ),
            CascadeSummary(
                cascadeId: "cas-dark-mode-cloud",
                title: "Dark mode for settings page",
                projectSlug: "web-console",
                workspaceUri: "cloud://acme/web-console",
                branchName: "feat/dark-mode",
                status: .inProgress,
                stepCount: 9,
                currentStepIndex: 2,
                totalSteps: 5,
                updatedAt: baseNow.addingTimeInterval(-7200),
                relativeTimeLabel: "12:04",
                statusSubtitle: "Running in cloud · Step 2 of 5",
                isPinned: false,
                isArchived: false,
                isUnread: true,
                modelLabel: "Gemini 3.8 Flash",
                lastMessagePreview: "Applying semantic obsidian tokens to SettingsView...",
                totalAdditions: 64,
                totalDeletions: 21
            ),
            CascadeSummary(
                cascadeId: "cas-idempotency-payouts",
                title: "Idempotency keys for payouts",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .done,
                stepCount: 45,
                currentStepIndex: 8,
                totalSteps: 8,
                updatedAt: baseNow.addingTimeInterval(-86400),
                relativeTimeLabel: "Yesterday",
                statusSubtitle: "Done · Merged into main",
                isPinned: false,
                isArchived: false,
                isUnread: false,
                modelLabel: "Gemini 3.1 Pro",
                lastMessagePreview: "Merged payout idempotency key store into main.",
                totalAdditions: 210,
                totalDeletions: 19
            ),
            CascadeSummary(
                cascadeId: "cas-audit-log-admin",
                title: "Audit log for admin actions",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .waiting,
                stepCount: 3,
                currentStepIndex: 2,
                totalSteps: 3,
                updatedAt: baseNow.addingTimeInterval(-172_800),
                relativeTimeLabel: "2d",
                statusSubtitle: "Archived · Planning",
                isPinned: false,
                isArchived: true,
                isUnread: false,
                modelLabel: "Gemini 3.1 Pro",
                lastMessagePreview: "Before I draft the plan I need three decisions. Tap to answer — you can also reply in your own words."
            ),
            CascadeSummary(
                cascadeId: "cas-pgx-v5-migration",
                title: "Migrate settlement store to pgx v5",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/wl/code/ledger-svc",
                branchName: "main",
                status: .done,
                stepCount: 37,
                currentStepIndex: 6,
                totalSteps: 6,
                updatedAt: baseNow.addingTimeInterval(-345_600),
                relativeTimeLabel: "4d",
                statusSubtitle: "Archived · Merged",
                isPinned: false,
                isArchived: true,
                isUnread: false,
                modelLabel: "Gemini 3.1 Pro",
                lastMessagePreview: "Completed pgxpool v5 batch migration."
            )
        ]

        let automations: [AutomationItem] = [
            AutomationItem(
                id: "auto-nightly-audit",
                title: "Nightly dependency audit",
                projectSlug: "ledger-svc",
                scheduleSummary: "ledger-svc · Daily at 02:00 · Flash",
                section: .scheduled,
                nextRunText: "Tonight, 02:00",
                lastRunText: "Succeeded · 22h ago",
                needsReview: false,
                isRunningNow: false
            ),
            AutomationItem(
                id: "auto-weekly-flaky",
                title: "Weekly flaky-test report",
                projectSlug: "ledger-svc",
                scheduleSummary: "ledger-svc · Mondays at 09:00 · Pro",
                section: .scheduled,
                nextRunText: "Mon, 09:00",
                lastRunText: "Needs review · 2d",
                needsReview: true,
                isRunningNow: false
            ),
            AutomationItem(
                id: "auto-pr-triage",
                title: "Triage new pull requests",
                projectSlug: "web-console",
                scheduleSummary: "web-console · On PR opened · Flash Lite",
                section: .alwaysOn,
                nextRunText: "On PR opened",
                lastRunText: "Last run 14m ago",
                needsReview: false,
                isRunningNow: false
            ),
            AutomationItem(
                id: "auto-bundle-size",
                title: "Bundle size watch",
                projectSlug: "web-console",
                scheduleSummary: "web-console · Daily at 08:00 · Flash",
                section: .paused,
                nextRunText: "Paused",
                lastRunText: "Paused · 5d ago",
                needsReview: false,
                isRunningNow: false
            )
        ]

        let contextCandidates: [ContextCandidateItem] = [
            ContextCandidateItem(
                id: "ctx-ratelimit",
                category: .files,
                title: "ratelimit.go",
                subtitle: "internal/middleware · changed this turn",
                chipLabel: "@ratelimit.go",
                isActionTrigger: false,
                isSelected: true
            ),
            ContextCandidateItem(
                id: "ctx-load-folder",
                category: .folder,
                title: "load/",
                subtitle: "Folder · 3 files",
                chipLabel: "@load/",
                isActionTrigger: false,
                isSelected: false
            ),
            ContextCandidateItem(
                id: "ctx-idempotency-conv",
                category: .mentions,
                title: "Idempotency keys for payouts",
                subtitle: "Conversation · ledger-svc",
                chipLabel: "@Idempotency keys for payouts",
                isActionTrigger: false,
                isSelected: true
            ),
            ContextCandidateItem(
                id: "ctx-terminal-last-test",
                category: .mentions,
                title: "Terminal · last test run",
                subtitle: "Output · 214 lines",
                chipLabel: "@terminal:last-test",
                isActionTrigger: false,
                isSelected: false
            ),
            ContextCandidateItem(
                id: "ctx-action-boost",
                category: .actions,
                title: "/boost",
                subtitle: "Action · extra multi-agent reasoning pass",
                chipLabel: "/boost",
                isActionTrigger: true,
                isSelected: false
            ),
            ContextCandidateItem(
                id: "ctx-skill-go-testing",
                category: .skills,
                title: "go-testing",
                subtitle: "Skill · table-driven tests, -race, golden files",
                chipLabel: "Skill · go-testing",
                isActionTrigger: false,
                isSelected: true
            )
        ]

        let questionSteps: [StructuredQuestionStepItem] = [
            StructuredQuestionStepItem(
                id: "q-step-1-storage",
                stepNumber: 1,
                shortTabTitle: "Storage",
                questionTitle: "Where should admin audit events be persisted?",
                options: [
                    "Dedicated audit_events Postgres table",
                    "Append-only Kafka audit topic",
                    "Daily S3 Parquet archive"
                ],
                selectedOptions: ["Dedicated audit_events Postgres table"],
                customWriteIn: "",
                isCompleted: true,
                isMultiSelect: false
            ),
            StructuredQuestionStepItem(
                id: "q-step-2-actions",
                stepNumber: 2,
                shortTabTitle: "Actions",
                questionTitle: "Which admin actions should be audited?",
                options: [
                    "Account freeze / unfreeze",
                    "Limit changes",
                    "Manual ledger adjustments",
                    "Role & permission changes"
                ],
                selectedOptions: [
                    "Account freeze / unfreeze",
                    "Limit changes",
                    "Manual ledger adjustments"
                ],
                customWriteIn: "",
                isCompleted: false,
                isMultiSelect: true
            ),
            StructuredQuestionStepItem(
                id: "q-step-3-retention",
                stepNumber: 3,
                shortTabTitle: "Retention",
                questionTitle: "How long should audit entries be retained?",
                options: [
                    "90 days hot + 7 years cold compliance archive",
                    "1 year hot Postgres",
                    "Indefinite immutable retention"
                ],
                selectedOptions: ["90 days hot + 7 years cold compliance archive"],
                customWriteIn: "",
                isCompleted: false,
                isMultiSelect: false
            )
        ]

        let planChanges: [PlanProposedFileChange] = [
            PlanProposedFileChange(
                id: "plan-change-batch",
                changeKind: "MODIFY",
                filePath: "settlement/batch.go",
                summaryText: "Accept a clock.Clock through BatchOptions instead of calling time.Now() directly.",
                highlightedSpan: "instead of calling time.Now() directly",
                isSelectedForCallout: false
            ),
            PlanProposedFileChange(
                id: "plan-change-test",
                changeKind: "MODIFY",
                filePath: "settlement/settlement_test.go",
                summaryText: "Create one clock per subtest; remove the package-level clk variable.",
                highlightedSpan: "remove the package-level clk variable",
                isSelectedForCallout: true
            ),
            PlanProposedFileChange(
                id: "plan-change-clock",
                changeKind: "NEW",
                filePath: "testutil/clock.go",
                summaryText: "NewTestClock(t) helper, released with t.Cleanup.",
                highlightedSpan: nil,
                isSelectedForCallout: false
            )
        ]

        let planComments: [PlanInlineComment] = [
            PlanInlineComment(
                id: "plan-comment-1",
                authorInitials: "WL",
                authorName: "You",
                statusLabel: "Pending",
                targetFilePath: "settlement/batch.go",
                quotedSpan: "instead of calling time.Now() directly",
                body: "Default to the real clock when Clock is nil, so existing callers don't break."
            ),
            PlanInlineComment(
                id: "plan-comment-2",
                authorInitials: "WL",
                authorName: "You",
                statusLabel: "Pending",
                targetFilePath: "Verification",
                quotedSpan: "go test -race -count=100 ./internal/settlement/...",
                body: "Run with -count=100 and -race to confirm the 3% flake is gone."
            )
        ]

        let vegetaCmd = "vegeta attack -rate=2000/s -duration=30s \\\n  -targets=load/transfers.txt | vegeta report"
        let rateLimiterSteps: [CascadeStep] = [
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 0,
                type: .userInput,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-161),
                userInput: "Add a per-tenant token-bucket rate limiter to POST /transfers and run load tests.",
                attachedMentions: ["@transfers.go", "Skill · go-testing"]
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 1,
                type: .viewFile,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-140),
                viewFile: ViewFilePayload(
                    fileUri: "file:///Users/wl/code/ledger-svc/internal/router/transfers.go",
                    startLine: 1,
                    endLine: 96,
                    totalLines: 148
                )
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 2,
                type: .codeAction,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-95),
                codeAction: CodeActionPayload(
                    targetFileUri: "file:///Users/wl/code/ledger-svc/internal/middleware/ratelimit.go",
                    description: "Add per-tenant sync.Mutex and configurable BucketTTL to Limiter.Allow",
                    additions: 96,
                    deletions: 4,
                    startLine: 18,
                    endLine: 44,
                    diffPreviewLines: [
                        "+    mu     sync.Mutex",
                        "+ const ttl = cfg.BucketTTL",
                        "+    b.mu.Lock(); defer b.mu.Unlock()"
                    ]
                )
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 3,
                type: .plannerResponse,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-35),
                plannerResponse: PlannerResponsePayload(
                    response: "Plan approved with your 2 comments. Tests pass — next is a load test, which needs your OK.",
                    thinking: "Addressed both review comments on Implementation Plan v2 (configurable BucketTTL and per-tenant mutex lock). Ran go test ./internal/... with 42/42 passing. Preparing vegeta load test against load/transfers.txt.",
                    thinkingDurationSeconds: 14.0,
                    referencedFiles: ["/brain/rate_limiter_plan.md", "middleware/ratelimit.go"]
                )
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 4,
                type: .taskBoundary,
                status: .inProgress,
                createdAt: baseNow.addingTimeInterval(-12),
                taskBoundary: TaskBoundaryPayload(
                    taskName: "Task · 4 of 7 done",
                    taskStatus: "Waiting for your approval · Step 5 of 7",
                    taskSummary: "42 unit tests passed; awaiting Face ID confirmation for vegeta load test.",
                    completedCount: 4,
                    totalCount: 7,
                    elapsedLabel: "2m 41s",
                    checklist: [
                        TaskChecklistItem(
                            id: "chk-wire-router",
                            title: "Wire limiter into router",
                            status: .done,
                            trailingBadge: nil
                        ),
                        TaskChecklistItem(
                            id: "chk-go-test",
                            title: "go test ./internal/...",
                            status: .done,
                            trailingBadge: "42 passed"
                        ),
                        TaskChecklistItem(
                            id: "chk-vegeta-load",
                            title: "Load test with vegeta",
                            status: .waiting,
                            trailingBadge: nil
                        )
                    ]
                )
            ),
            CascadeStep(
                cascadeId: "cas-rate-limiter",
                stepIndex: 5,
                type: .runCommand,
                status: .waiting,
                createdAt: baseNow,
                runCommand: RunCommandPayload(
                    commandId: "cmd-vegeta-01",
                    commandLine: vegetaCmd,
                    proposedCommandLine: vegetaCmd,
                    cwd: "~/code/ledger-svc"
                ),
                requestedInteraction: RequestedInteraction(
                    kind: .runCommand,
                    runCommand: RunCommandInteractionSpec(
                        proposedCommandLine: vegetaCmd,
                        cwd: "~/code/ledger-svc",
                        isDaemon: false
                    )
                )
            )
        ]

        let auditQuestionSteps: [CascadeStep] = [
            CascadeStep(
                cascadeId: "cas-audit-log-admin",
                stepIndex: 0,
                type: .userInput,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-600),
                userInput: "Design an immutable audit log for privileged admin actions in ledger-svc."
            ),
            CascadeStep(
                cascadeId: "cas-audit-log-admin",
                stepIndex: 1,
                type: .plannerResponse,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-580),
                plannerResponse: PlannerResponsePayload(
                    response: "Before I draft the plan I need three decisions. Tap to answer — you can also reply in your own words.",
                    thinking: "Identifying storage sink, auditable admin mutations, and compliance retention window.",
                    thinkingDurationSeconds: 6.0
                )
            ),
            CascadeStep(
                cascadeId: "cas-audit-log-admin",
                stepIndex: 2,
                type: .ephemeralMessage,
                status: .waiting,
                createdAt: baseNow.addingTimeInterval(-575),
                requestedInteraction: RequestedInteraction(
                    kind: .askQuestion,
                    askQuestion: AskQuestionInteractionSpec(
                        question: "Which admin actions should be audited?",
                        options: [
                            "Account freeze / unfreeze",
                            "Limit changes",
                            "Manual ledger adjustments",
                            "Role & permission changes"
                        ],
                        isMultiSelect: true
                    )
                )
            )
        ]

        let flakySettlementSteps: [CascadeStep] = [
            CascadeStep(
                cascadeId: "cas-flaky-settlement",
                stepIndex: 0,
                type: .userInput,
                status: .done,
                createdAt: baseNow.addingTimeInterval(-520),
                userInput: "Fix flaky TestSettlementBatch in CI without disabling t.Parallel()."
            ),
            CascadeStep(
                cascadeId: "cas-flaky-settlement",
                stepIndex: 1,
                type: .plannerResponse,
                status: .waiting,
                createdAt: baseNow.addingTimeInterval(-480),
                plannerResponse: PlannerResponsePayload(
                    response: "The flake comes from a shared fake clock across parallel subtests in settlement_test.go. I wrote a plan to isolate it per test — review it before I change anything?",
                    thinking: "Traced ~3% failure in TestSettlementBatch to concurrent Advance() calls on package-level clk.",
                    thinkingDurationSeconds: 9.0,
                    referencedFiles: ["/brain/implementation_plan.md"]
                ),
                requestedInteraction: RequestedInteraction(
                    kind: .filePermission,
                    filePermission: FilePermissionInteractionSpec(
                        absolutePathUri: "file:///brain/implementation_plan.md",
                        isDirectory: false
                    )
                )
            )
        ]

        let artifacts: [ArtifactSnapshot] = [
            ArtifactSnapshot(
                artifactPath: "/brain/implementation_plan.md",
                title: "Implementation Plan",
                summary: "Isolate the fake clock in settlement tests",
                kind: .implementationPlan,
                content: """
                # Isolate the fake clock in settlement tests

                TestSettlementBatch fails in ~3% of CI runs. Parallel subtests share one fake clock, so `Advance()` in one subtest moves time for the others.

                ## Proposed changes
                - **MODIFY** `settlement/batch.go` — Accept a `clock.Clock` through BatchOptions instead of calling time.Now() directly.
                - **MODIFY** `settlement/settlement_test.go` — Create one clock per subtest; remove the package-level clk variable.
                - **NEW** `testutil/clock.go` — NewTestClock(t) helper, released with t.Cleanup.

                ## Verification
                - `go test -race -count=100 ./internal/settlement/...`
                """,
                requestFeedback: true,
                userFacing: true,
                version: 2,
                updatedAt: baseNow.addingTimeInterval(-480)
            ),
            ArtifactSnapshot(
                artifactPath: "/brain/rate_limiter_plan.md",
                title: "Implementation Plan",
                summary: "Approved · 2 comments addressed",
                kind: .implementationPlan,
                content: "# Per-Tenant Rate Limiter Plan\n\nApproved · 2 comments addressed.",
                requestFeedback: false,
                userFacing: true,
                version: 2,
                updatedAt: baseNow.addingTimeInterval(-120)
            ),
            ArtifactSnapshot(
                artifactPath: "/brain/release_walkthrough_v2_3.md",
                title: "Walkthrough · v2.3",
                summary: "Walkthrough ready",
                kind: .walkthrough,
                content: "# Release v2.3 Walkthrough\n\nAll staging verification checks passed.",
                requestFeedback: false,
                userFacing: true,
                version: 1,
                updatedAt: baseNow.addingTimeInterval(-3500)
            )
        ]

        let diffs: [FilePatchDiff] = [
            FilePatchDiff(
                turnNumber: 3,
                filePath: "middleware/ratelimit.go",
                additions: 96,
                deletions: 4,
                hunkHeader: "@@ -18,9 +18,27 @@ Allow",
                isReviewed: false,
                lines: [
                    DiffLine(id: 1, kind: .hunkHeader, text: "@@ -18,9 +18,27 @@ Allow"),
                    DiffLine(id: 18, kind: .context, oldLineNumber: 18, newLineNumber: 18, text: "type bucket struct {"),
                    DiffLine(id: 19, kind: .context, oldLineNumber: 19, newLineNumber: 19, text: "    tokens float64"),
                    DiffLine(id: 20, kind: .context, oldLineNumber: 20, newLineNumber: 20, text: "    last   time.Time"),
                    DiffLine(id: 21, kind: .addition, oldLineNumber: nil, newLineNumber: 21, text: "    mu     sync.Mutex", wordHighlightRange: "sync.Mutex"),
                    DiffLine(id: 22, kind: .context, oldLineNumber: 21, newLineNumber: 22, text: "}"),
                    DiffLine(id: 23, kind: .context, oldLineNumber: 22, newLineNumber: 23, text: ""),
                    DiffLine(id: 240, kind: .deletion, oldLineNumber: 24, newLineNumber: nil, text: "const ttl = 5 * time.Minute", wordHighlightRange: "5 * time.Minute"),
                    DiffLine(id: 241, kind: .addition, oldLineNumber: nil, newLineNumber: 24, text: "const ttl = cfg.BucketTTL", wordHighlightRange: "cfg.BucketTTL"),
                    DiffLine(id: 25, kind: .context, oldLineNumber: 25, newLineNumber: 25, text: ""),
                    DiffLine(id: 26, kind: .context, oldLineNumber: 26, newLineNumber: 26, text: "func (l *Limiter) Allow(tenant string) bool {"),
                    DiffLine(id: 27, kind: .addition, oldLineNumber: nil, newLineNumber: 27, text: "    b := l.bucketFor(tenant)"),
                    DiffLine(id: 28, kind: .addition, oldLineNumber: nil, newLineNumber: 28, text: "    b.mu.Lock(); defer b.mu.Unlock()"),
                    DiffLine(id: 29, kind: .addition, oldLineNumber: nil, newLineNumber: 29, text: "    now := time.Now()"),
                    DiffLine(id: 30, kind: .addition, oldLineNumber: nil, newLineNumber: 30, text: "    elapsed := now.Sub(b.last).Seconds()"),
                    DiffLine(id: 31, kind: .addition, oldLineNumber: nil, newLineNumber: 31, text: "    b.tokens = min(l.burst, b.tokens+elapsed*l.rate)")
                ]
            ),
            FilePatchDiff(
                turnNumber: 3,
                filePath: "router/transfers.go",
                additions: 18,
                deletions: 6,
                hunkHeader: "@@ -42,8 +42,20 @@ RegisterTransferRoutes",
                isReviewed: true,
                lines: [
                    DiffLine(id: 101, kind: .hunkHeader, text: "@@ -42,8 +42,20 @@ RegisterTransferRoutes"),
                    DiffLine(id: 102, kind: .addition, oldLineNumber: nil, newLineNumber: 45, text: "    r.Use(middleware.RateLimit(limiter))")
                ]
            ),
            FilePatchDiff(
                turnNumber: 2,
                filePath: "middleware/ratelimit_test.go",
                additions: 10,
                deletions: 2,
                hunkHeader: "@@ -1,6 +1,14 @@ TestLimiterAllow",
                isReviewed: true,
                lines: [
                    DiffLine(id: 201, kind: .hunkHeader, text: "@@ -1,6 +1,14 @@ TestLimiterAllow"),
                    DiffLine(id: 202, kind: .addition, oldLineNumber: nil, newLineNumber: 12, text: "    require.True(t, lim.Allow(\"tenant-acme\"))")
                ]
            ),
            FilePatchDiff(
                turnNumber: 1,
                filePath: "config/limits.yaml",
                additions: 4,
                deletions: 2,
                hunkHeader: "@@ -8,4 +8,6 @@ transfers:",
                isReviewed: false,
                lines: [
                    DiffLine(id: 301, kind: .hunkHeader, text: "@@ -8,4 +8,6 @@ transfers:"),
                    DiffLine(id: 302, kind: .addition, oldLineNumber: nil, newLineNumber: 10, text: "  bucket_ttl: 10m")
                ]
            )
        ]

        let store = AntigravitySessionStore(
            hosts: [macHost, cloudHost],
            activeHost: macHost,
            projects: projects,
            workspaces: workspaces,
            selectedWorkspaceUri: workspaces[0].workspaceUri,
            summaries: summaries,
            automations: automations,
            contextCandidates: contextCandidates,
            questionSteps: questionSteps,
            activeQuestionStepIndex: 1,
            planChanges: planChanges,
            planComments: planComments,
            activeCascadeId: "cas-rate-limiter",
            stepsByCascadeId: [
                "cas-rate-limiter": rateLimiterSteps,
                "cas-audit-log-admin": auditQuestionSteps,
                "cas-flaky-settlement": flakySettlementSteps
            ],
            activeArtifacts: artifacts,
            activeTurnDiffs: diffs,
            selectedDiffTurn: 3,
            selectedDiffFileIndex: 0,
            activeLineCommentDraft: "Use l.clock.Now() — the plan says to inject the clock so tests can control time.",
            selectedModelConfig: CascadeModelConfig.catalog[0]
        )
        store.isVerificationMode = true
        store.isInitialSessionCheckComplete = true
        store.connectionStatusText = "Demo Sandbox · Offline ESDD Fixtures"
        store.composerAttachments = [
            ComposerAttachmentChip(
                id: "chip-ratelimit",
                kind: .fileMention,
                label: "@ratelimit.go",
                targetUri: "file:///Users/wl/code/ledger-svc/internal/middleware/ratelimit.go"
            )
        ]
        store.composerDraftText = "Use 1000/s instead — staging is smaller than prod."
        return store
    }

    /// Clean, empty production store used on real devices (`launchVerifyCase() == nil`).
    /// Contains zero mock/demo conversations, projects, automations, or context chips.
    public static func makeLiveStore() -> AntigravitySessionStore {
        let placeholderHost = RemoteHostInstance(
            instanceId: "unpaired",
            hostname: "Antigravity Desktop",
            version: "",
            channel: .cloudRelay,
            endpointURL: URL(string: SAPISIDHashGenerator.defaultOrigin)!,
            isOnline: false,
            latencyMs: 0
        )
        let store = AntigravitySessionStore(
            hosts: [],
            activeHost: placeholderHost,
            projects: [],
            workspaces: [],
            selectedWorkspaceUri: "",
            summaries: [],
            automations: [],
            contextCandidates: [],
            questionSteps: [],
            activeQuestionStepIndex: 1,
            planChanges: [],
            planComments: [],
            activeCascadeId: "",
            stepsByCascadeId: [:],
            activeArtifacts: [],
            activeTurnDiffs: [],
            selectedDiffTurn: 1,
            selectedDiffFileIndex: 0,
            activeLineCommentDraft: "",
            selectedModelConfig: CascadeModelConfig.liveDefaultCatalog[0],
            availableModels: CascadeModelConfig.liveDefaultCatalog,
            availableAgents: ["Default"]
        )
        store.isVerificationMode = false
        store.isInitialSessionCheckComplete = false
        store.rpcClient = nil
        store.selectedProjectId = ""
        store.contextMenuTargetCascadeId = ""
        store.swipePreviewCascadeId = ""
        store.selectedArtifactPath = ""
        store.selectedDiffLineNumber = nil
        store.availableGitHubRepos = []
        store.composerAttachments = []
        store.composerDraftText = ""
        store.connectionStatusText = "Not Connected"
        if let rawLocal = UserDefaults.standard.string(forKey: Self.localPermissionDefaultsKey),
           let savedLocal = AgentPermissionPreset(rawValue: rawLocal) {
            store.localPermissionPreset = savedLocal
        }
        if let rawRemote = UserDefaults.standard.string(forKey: Self.remotePermissionDefaultsKey),
           let savedRemote = AgentPermissionPreset(rawValue: rawRemote) {
            store.remotePermissionPreset = savedRemote
        }
        return store
    }
}
