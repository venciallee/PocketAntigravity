import Foundation
import Observation

/// Active navigation destination in `AntigravityShellController` across all 19 UE screens.
public enum AntigravityNavigationRoute: Sendable, Equatable, Hashable {
    case tabRoot
    case cascadeChat(String)
    case automationDetail(String)
    case rulesAndSkills
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
    case automationEdit(automationId: String)
    case permissionsPreset
    case addContext
    case slashMenu
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
        case .automationEdit(let aid): return "automation-edit-\(aid)"
        case .permissionsPreset: return "permissions-preset"
        case .addContext: return "add-context"
        case .slashMenu: return "slash-menu"
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

/// Central `@Observable` state coordinator for `PocketAntigravity` (v2.1 UE Aligned).
/// Drives all 19 UE screens: Agents Home (`UE01`), Sidebar Drawer (`UE01B`), Display Options (`UE02`),
/// Long-Press & Pin (`UE03`), Create New Project (`UE05`), Automations (`UE06`),
/// Automation Detail (`UE06B`), Automation Edit (`UE06C`), Chat & Composer (`UE07`), Permissions Preset (`UE07B`),
/// Add Context (`UE08`), Slash Menu (`UE08B`), Model & Effort (`UE09`), Structured Multi-Step Question (`UE10`),
/// Implementation Plan Review (`UE11`), Turn Diff Line Review (`UE12`), Live Activity (`UE13`),
/// Rules & Skills (`UE14`), and Settings (`UE15`).
@MainActor
@Observable
public final class AntigravitySessionStore {

    // MARK: - Top-Level Navigation & Sheet State
    public var selectedTab: PrimaryTab = .agents
    public var activeRoute: AntigravityNavigationRoute = .tabRoot
    public var presentedSheet: AntigravityModalSheet? = nil
    public var isSidebarPresented: Bool = false
    public var isGlobalSearchPresented: Bool = false

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

    // MARK: - Agents Home, Display Options & Search State (`UE01`, `UE01B`, `UE02`, `UE03`)
    public var quickFilter: AgentsQuickFilter = .all
    public var displayOptions: AgentDisplayOptions = AgentDisplayOptions()
    public var isSortPopoverPresented: Bool = false
    public var searchQuery: String = ""
    public var selectedFilterCategory: SessionFilterCategory = .all
    public var selectedWorktreeFilter: String? = nil
    public var isRefreshingSummaries: Bool = false
    public var hydratingCascadeIds: Set<String> = []
    public var settledEmptyTitleCascadeIds: Set<String> = []
    public var contextMenuTargetCascadeId: String = "cas-flaky-settlement"
    public var swipePreviewCascadeId: String = "cas-upgrade-go"

    // MARK: - Hosts, Projects & Create Project State (`UE01`, `UE05`)
    public var hosts: [RemoteHostInstance]
    public var activeHost: RemoteHostInstance
    public var projects: [ProjectWorkspace]
    public var selectedProjectId: String = "ledger-svc"
    public var newProjectDraft: NewProjectDraft = NewProjectDraft()
    public var availableGitHubRepos: [GitHubRepoItem] = GitHubRepoItem.sampleCatalog
    public var workspaces: [WorkspaceInfo]
    public var selectedWorkspaceUri: String

    // MARK: - Conversations, Automations & Context State (`UE01`, `UE06`, `UE06B`, `UE06C`, `UE08`)
    public var summaries: [CascadeSummary]
    public var automations: [AutomationItem]
    public var selectedAutomationId: String = "auto-nightly-audit"
    public var automationPromptDraft: String = ""
    public var isLoadingAutomations: Bool = false
    public var isMutatingAutomation: Bool = false
    public var automationsErrorText: String? = nil
    public var isAutomationsAuthExpired: Bool = false
    public var contextCandidates: [ContextCandidateItem]
    public var contextSearchQuery: String = ""
    public var selectedContextCategoryFilter: ContextCategory? = nil
    /// Feature-flag override enabling optional side-question entry in slash command popup (false by default in live mode).
    public var includeSideQuestionInSlashMenu: Bool = false

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

    internal static let localPermissionDefaultsKey = "antigravity.ios.permissionPreset.local"
    internal static let remotePermissionDefaultsKey = "antigravity.ios.permissionPreset.remote"
    public static let appearanceModeDefaultsKey = "antigravity.ios.appearanceMode"
    public static let appLanguageDefaultsKey = "antigravity.ios.appLanguage"
    internal var hasModifiedAppearanceModeInSession: Bool = false
    internal var hasModifiedLanguageInSession: Bool = false
    internal var hasModifiedDisplayOptionsInSession: Bool = false

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
                preferencesStore.set(preset.rawValue, forKey: Self.remotePermissionDefaultsKey)
            }
        } else {
            localPermissionPreset = preset
            appearancePreferences.globalPermissionPreset = preset
            appearancePreferences.terminalSandboxEnabled = preset.usesTerminalSandbox
            if !isVerificationMode {
                preferencesStore.set(preset.rawValue, forKey: Self.localPermissionDefaultsKey)
                saveAppearancePreferences()
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
    public var activeAuthUser: String = "0"
    public var userDisplayName: String? = nil
    public var lastScannedRelayURL: String = ""

    /// Resolved greeting display name: uses the deterministic `"Alex"` fixture ONLY in offline
    /// ESDD verification mode; live mode uses the real user's name from `GetUserStatus` (or `nil`
    /// for a clean nameless greeting).
    public var homeGreetingDisplayName: String? {
        if isVerificationMode && !hasPairedBackend && !isLiveBackendConnected {
            return UserGreetingFormatter.formatGreetingName(userDisplayName) ?? "Alex"
        }
        return UserGreetingFormatter.formatGreetingName(userDisplayName)
    }

    public var homeHeroGreetingText: String {
        UserGreetingFormatter.homeHeroGreeting(
            displayName: homeGreetingDisplayName,
            language: appearancePreferences.language
        )
    }

    public var homeAddContextBackdropGreetingText: String {
        UserGreetingFormatter.addContextBackdropGreeting(
            displayName: homeGreetingDisplayName,
            language: appearancePreferences.language
        )
    }

    public var homeCompactBackdropGreetingText: String {
        UserGreetingFormatter.compactBackdropGreeting(
            displayName: homeGreetingDisplayName,
            language: appearancePreferences.language
        )
    }
    public var isLoadingSteps: Bool = false
    public var stepLoadErrorText: String? = nil
    public var cloudAgentWarmingUp: Bool = false
    public var connectionLifecyclePhase: ConnectionLifecyclePhase = .disconnected
    public var isDeviceNetworkReachable: Bool = true
    public var isNetworkingSuspended: Bool = false
    public var reconnectAttemptCount: Int = 0
    public var nextReconnectAt: Date? = nil
    public var pendingOutboxCount: Int = 0
    public var selectedHostScope: AgentsHostFilterScope = .allHosts
    public var isSwitchingHost: Bool = false
    public var refreshingHostScopeKeys: Set<String> = []
    public var hostCapabilitiesByKey: [String: HostCapabilityProfile] = [:]
    public var compatibilityNoticeText: String? = nil

    /// Runtime-discovered compatibility profile for the currently active host.
    public var activeHostCapabilities: HostCapabilityProfile {
        let candidateKeys: [String] = {
            var keys: [String] = []
            if !activeHost.instanceId.isEmpty {
                keys.append(activeHost.instanceId)
            }
            if activeHost.channel == .directHost, let host = activeHost.endpointURL.host {
                if let port = activeHost.endpointURL.port {
                    keys.append("direct:\(host):\(port)")
                }
                keys.append("direct:\(host)")
            }
            return keys
        }()
        for key in candidateKeys {
            if let profile = hostCapabilitiesByKey[key] {
                return profile
            }
        }
        return HostCapabilityProfile(
            hostKey: candidateKeys.first ?? "default",
            reportedVersion: activeHost.version
        )
    }

    /// Returns `false` once runtime discovery has confirmed the active live Desktop host does not support `capability`.
    /// Always returns `true` during offline / ESDD verification mode or before negative proof is observed.
    public func isCapabilitySupportedOnActiveHost(_ capability: HostCapability) -> Bool {
        guard !isVerificationMode, (hasPairedBackend || isLiveBackendConnected) else {
            return true
        }
        return activeHostCapabilities.supportState(for: capability) != .unsupported
    }

    public func dismissCompatibilityNotice() {
        compatibilityNoticeText = nil
    }

    public func refreshHostCapabilitiesFromClient() async {
        guard let client = rpcClient else { return }
        let snapshot = await client.allCapabilityProfiles()
        for (key, profile) in snapshot {
            hostCapabilitiesByKey[key] = profile
        }
        var activeProfile = await client.capabilityProfile()
        if activeProfile.reportedVersion == nil,
           let knownVer = HostCapabilityProfile.normalizedVersionString(activeHost.version) {
            activeProfile.reportedVersion = knownVer
        }
        hostCapabilitiesByKey[activeProfile.hostKey] = activeProfile
        if !activeHost.instanceId.isEmpty {
            hostCapabilitiesByKey[activeHost.instanceId] = activeProfile
        }
        if let version = activeProfile.reportedVersion, !version.isEmpty, activeHost.version != version {
            activeHost.version = version
            if let idx = hosts.firstIndex(where: { $0.instanceId == activeHost.instanceId }) {
                hosts[idx].version = version
            }
        }
    }

    /// True when operating against a real paired live host (always `false` in `--ui-verify` ESDD mode).
    public var isLiveBackendActive: Bool {
        !isVerificationMode && (hasPairedBackend || isLiveBackendConnected)
    }

    internal func handleLiveCapabilityWriteError(
        _ error: Error,
        capability: HostCapability,
        fallbackActionLabel: String
    ) async {
        await refreshHostCapabilitiesFromClient()
        if ProtocolCompatibilityEngine.isMethodUnimplementedError(error) {
            compatibilityNoticeText = activeHostCapabilities.userFacingUnsupportedMessage(for: capability)
        } else {
            compatibilityNoticeText = "\(fallbackActionLabel) failed: \(error.localizedDescription)"
        }
    }

    /// Standardized live-backend write transaction template eliminating ad-hoc `try?` fake successes.
    /// - Executes `optimistic()` immediately on `@MainActor`.
    /// - In offline/ESDD verification mode (`!isLiveBackendActive`), returns `offlineResult()` without network I/O.
    /// - Against a live host, dispatches `remote(client)`; on error, runs `rollback()` and posts an honest
    ///   compatibility or failure notice via `handleLiveCapabilityWriteError`.
    @discardableResult
    public func performLiveCapabilityWrite<ResultValue: Sendable>(
        capability: HostCapability,
        actionLabel: String,
        optimistic: () -> Void = {},
        offlineResult: () -> ResultValue? = { nil },
        remote: @escaping @Sendable (AntigravityRPCClient) async throws -> ResultValue,
        onSuccess: (ResultValue) -> Void = { _ in },
        rollback: () -> Void = {}
    ) async -> ResultValue? {
        optimistic()
        guard isLiveBackendActive, let client = rpcClient else {
            let value = offlineResult()
            if let value { onSuccess(value) }
            return value
        }
        do {
            let value = try await remote(client)
            await refreshHostCapabilitiesFromClient()
            onSuccess(value)
            return value
        } catch {
            rollback()
            await handleLiveCapabilityWriteError(
                error,
                capability: capability,
                fallbackActionLabel: actionLabel
            )
            return nil
        }
    }

    // MARK: - Dependencies
    internal static let selectedHostScopeDefaultsKey = "antigravity.ios.selectedHostScope.v1"
    internal static let pairedHostLaunchHintDefaultsKey = "antigravity.ios.pairedHostLaunchHint.v1"
    internal static let userDisplayNameDefaultsKey = "antigravity.userDisplayName.v1"
    internal let projectionStore: LocalProjectionStore
    internal let secretStore: any SecretStore
    internal let networkMonitor: any NetworkReachabilityMonitoring
    internal let powerStateProvider: any PowerStateProviding
    internal let preferencesStore: any KeyValuePreferencesStore
    public var kmpEngine: (any AntigravityKmpEnginePort)?
    public var isUsingKmpEngine: Bool { kmpEngine != nil }
    internal var kmpSummaryStreamTask: Task<Void, Never>? = nil
    internal var rpcClient: AntigravityRPCClient?
    internal var isOptimisticInitialPairing: Bool = false
    internal var localSummaryStreamTasks: [String: Task<Void, Never>] = [:]
    internal var cloudSummaryStreamTask: Task<Void, Never>? = nil
    internal var hasReceivedLocalStreamEvent: Bool = false
    internal var hasReceivedCloudStreamEvent: Bool = false
    internal var summaryPollingTask: Task<Void, Never>? = nil
    internal var stepPollingTask: Task<Void, Never>? = nil
    internal var conversationPreloadTask: Task<Void, Never>? = nil
    internal var conversationPreloadQueue: [String] = []
    internal var preloadAttemptedAtByCascadeId: [String: Date] = [:]
    internal var preloadPersistDebounceTask: Task<Void, Never>? = nil
    internal var pendingPersistHostKeys: Set<String> = []
    internal var hostSwitchTask: Task<Void, Never>? = nil
    internal var hostSwitchGeneration: UInt64 = 0
    internal var inFlightHostRefreshTasks: [String: Task<Bool, Never>] = [:]
    internal var activeRefreshCount: Int = 0
    internal var locallyViewedAtByCascadeId: [String: Date] = [:]
    internal var optimisticActiveUntilByCascadeId: [String: Date] = [:]
    internal var consecutiveSyncFailures: Int = 0
    internal var backgroundPollCounter: Int = 0
    internal var lastAutomationsSyncAt: Date? = nil
    internal var syncedConfigCascadeIds: Set<String> = []
    internal var locallyCreatedEmptyCascadeIds: Set<String> = []
    internal var stepSyncGeneration: UInt64 = 0
    internal var lastNetworkStatus: NetworkReachabilityStatus? = nil
    internal var isNetworkExpensiveOrConstrained: Bool = false
    internal var lastBackendActivityAt: Date = .distantPast
    internal var lastFullSyncAt: Date = .distantPast
    internal var lastStreamReopenAttemptAt: Date = .distantPast
    internal var isReplayingOutbox: Bool = false
    internal var lowPowerModeOverrideForTesting: Bool? = nil
    internal var hostRefreshExecutorOverrideForTesting: ((AgentsHostFilterScope) async throws -> ScopedWorkspaceSyncResult)? = nil

    internal var summaryStreamGeneration: UInt64 = 0

    internal var isSummaryStreamHealthy: Bool {
        if kmpSummaryStreamTask != nil && hasReceivedLocalStreamEvent {
            return true
        }
        if activeHost.channel == .cloudRelay {
            return (!localSummaryStreamTasks.isEmpty && hasReceivedLocalStreamEvent)
                || (cloudSummaryStreamTask != nil && hasReceivedCloudStreamEvent)
        }
        return !localSummaryStreamTasks.isEmpty && hasReceivedLocalStreamEvent
    }

    internal func cancelAllSummaryStreams() {
        summaryStreamGeneration &+= 1
        kmpSummaryStreamTask?.cancel()
        kmpSummaryStreamTask = nil
        for task in localSummaryStreamTasks.values {
            task.cancel()
        }
        localSummaryStreamTasks.removeAll()
        cloudSummaryStreamTask?.cancel()
        cloudSummaryStreamTask = nil
        hasReceivedLocalStreamEvent = false
        hasReceivedCloudStreamEvent = false
    }

    internal func startKmpSummarySubscriptionIfNeeded() {
        guard let engine = kmpEngine, !isVerificationMode, !isNetworkingSuspended else { return }
        kmpSummaryStreamTask?.cancel()
        let generation = summaryStreamGeneration
        let stream = engine.summaryUpdatesStream()
        kmpSummaryStreamTask = Task { [weak self] in
            for await updatedSummaries in stream {
                guard let self, !Task.isCancelled, self.summaryStreamGeneration == generation else { break }
                guard !updatedSummaries.isEmpty else { continue }
                self.hasReceivedLocalStreamEvent = true
                let now = Date()
                self.lastBackendActivityAt = now
                var byId = Dictionary(uniqueKeysWithValues: self.summaries.map { ($0.cascadeId, $0) })
                var shouldSyncActiveChat = false

                for incoming in updatedSummaries {
                    let cid = incoming.cascadeId
                    if let existing = byId[cid] {
                        var merged = incoming
                        if existing.hasResolvedTitle && !merged.hasResolvedTitle {
                            merged.title = existing.title
                            merged.hasResolvedTitle = true
                        } else if merged.hasResolvedTitle {
                            self.hydratingCascadeIds.remove(cid)
                            self.settledEmptyTitleCascadeIds.remove(cid)
                        }
                        if existing.isCloud && !merged.isCloud {
                            merged.isCloud = true
                            merged.originHostName = "Antigravity"
                        }
                        merged.isPinned = existing.isPinned || incoming.isPinned
                        merged.isArchived = existing.isArchived || incoming.isArchived
                        merged.stepCount = max(existing.stepCount, incoming.stepCount)
                        merged.currentStepIndex = max(1, merged.stepCount)
                        merged.totalSteps = max(1, merged.stepCount)
                        merged.cloudProjectId = incoming.cloudProjectId ?? existing.cloudProjectId

                        if let optimisticExpiry = self.optimisticActiveUntilByCascadeId[cid],
                           optimisticExpiry > now,
                           merged.status != .waiting && merged.status != .blocked && merged.status != .error {
                            merged.status = .inProgress
                        }

                        let latestViewed = [existing.lastUserViewTime, incoming.lastUserViewTime].compactMap { $0 }.max()
                        merged.lastUserViewTime = latestViewed

                        let stepCountAdvanced = merged.stepCount > existing.stepCount
                        let timestampAdvanced = incoming.updatedAt.timeIntervalSince(existing.updatedAt) > 0.5
                        let statusChanged = merged.status != existing.status
                        let hasNewActivity = stepCountAdvanced || timestampAdvanced

                        if hasNewActivity {
                            if self.activeRoute != .cascadeChat(cid) {
                                merged.isUnread = (merged.status != .inProgress && merged.status != .pending)
                                self.locallyViewedAtByCascadeId.removeValue(forKey: cid)
                            } else {
                                merged.isUnread = false
                                self.locallyViewedAtByCascadeId[cid] = max(now, merged.updatedAt)
                            }
                        } else if merged.status == .inProgress || merged.status == .pending {
                            merged.isUnread = false
                        } else if let localViewed = self.locallyViewedAtByCascadeId[cid], merged.updatedAt <= localViewed {
                            merged.isUnread = false
                        } else if let latestViewed, merged.updatedAt <= latestViewed {
                            merged.isUnread = false
                        } else {
                            merged.isUnread = incoming.isUnread
                        }

                        if let localViewed = self.locallyViewedAtByCascadeId[cid], merged.updatedAt <= localViewed {
                            merged.isUnread = false
                        }

                        merged.statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                            status: merged.status,
                            stepCount: merged.stepCount,
                            isUnread: merged.isUnread
                        )
                        byId[cid] = merged

                        if cid == self.activeCascadeId && (stepCountAdvanced || timestampAdvanced || statusChanged) {
                            shouldSyncActiveChat = true
                        }
                    } else {
                        var fresh = incoming
                        if let localViewed = self.locallyViewedAtByCascadeId[cid], fresh.updatedAt <= localViewed {
                            fresh.isUnread = false
                            fresh.statusSubtitle = AntigravityRPCClient.buildLiveStatusSubtitle(
                                status: fresh.status,
                                stepCount: fresh.stepCount,
                                isUnread: false
                            )
                        }
                        byId[cid] = fresh
                        if cid == self.activeCascadeId {
                            shouldSyncActiveChat = true
                        }
                    }
                }

                var nextSummaries = byId.values.sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt {
                        return lhs.updatedAt > rhs.updatedAt
                    }
                    return lhs.cascadeId < rhs.cascadeId
                }
                let existingCloudProjects = self.projects.filter { $0.runtime == .cloud }
                self.projects = Self.reconcileLiveProjects(
                    workspaces: self.workspaces,
                    summaries: &nextSummaries,
                    existingProjects: self.projects,
                    hostName: self.activeHost.hostname,
                    cloudProjects: existingCloudProjects
                )
                self.summaries = nextSummaries

                if self.isLiveBackendConnected && self.activeHost.isOnline {
                    self.connectionLifecyclePhase = self.isCascadeStreaming ? .onlineStreaming : .onlineIdle
                }
                if shouldSyncActiveChat && !self.activeCascadeId.isEmpty {
                    self.syncStepsForCascade(
                        self.activeCascadeId,
                        pollUntilIdle: self.activeRoute == .cascadeChat(self.activeCascadeId)
                    )
                }
            }
        }
    }

    public var isLowPowerModeEnabled: Bool {
        if let override = lowPowerModeOverrideForTesting {
            return override
        }
        return powerStateProvider.isLowPowerModeEnabled
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
        projectionStore: LocalProjectionStore = LocalProjectionStore(),
        secretStore: any SecretStore = KeychainStore.shared,
        networkMonitor: any NetworkReachabilityMonitoring = NetworkPathObserver(),
        powerStateProvider: any PowerStateProviding = SystemPowerStateProvider(),
        preferencesStore: any KeyValuePreferencesStore = UserDefaultsPreferencesStore(),
        kmpEngine: (any AntigravityKmpEnginePort)? = nil,
        createInitialRPCClient: Bool = true
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
        self.secretStore = secretStore
        self.networkMonitor = networkMonitor
        self.powerStateProvider = powerStateProvider
        self.preferencesStore = preferencesStore
        self.kmpEngine = kmpEngine
        if createInitialRPCClient {
            self.rpcClient = AntigravityRPCClient(
                host: activeHost,
                csrfToken: "csrf-antigravity-ios-session-token"
            )
        } else {
            self.rpcClient = nil
        }
        self.harvestEmbedResources(from: activeArtifacts)
        for (_, stepList) in mergedSteps {
            self.harvestEmbedResources(from: stepList)
        }
    }


    /// Clean, empty production store used on real devices (`launchVerifyCase() == nil`).
    /// Contains zero mock/demo conversations, projects, automations, or context chips.
    public static func makeLiveStore(
        projectionStore: LocalProjectionStore = LocalProjectionStore(),
        secretStore: any SecretStore = KeychainStore.shared,
        networkMonitor: any NetworkReachabilityMonitoring = NetworkPathObserver(),
        powerStateProvider: any PowerStateProviding = SystemPowerStateProvider(),
        preferencesStore: any KeyValuePreferencesStore = UserDefaultsPreferencesStore(),
        kmpEngine: (any AntigravityKmpEnginePort)? = nil
    ) -> AntigravitySessionStore {
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
            availableAgents: ["Default"],
            projectionStore: projectionStore,
            secretStore: secretStore,
            networkMonitor: networkMonitor,
            powerStateProvider: powerStateProvider,
            preferencesStore: preferencesStore,
            kmpEngine: kmpEngine,
            createInitialRPCClient: false
        )
        store.isVerificationMode = false
        store.isInitialSessionCheckComplete = false
        store.selectedProjectId = ""
        store.contextMenuTargetCascadeId = ""
        store.swipePreviewCascadeId = ""
        store.selectedArtifactPath = ""
        store.selectedDiffLineNumber = nil
        store.availableGitHubRepos = []
        store.composerAttachments = []
        store.composerDraftText = ""
        store.permissionRules = []
        store.connectionStatusText = "Not Connected"
        if let rawLocal = store.preferencesStore.string(forKey: Self.localPermissionDefaultsKey),
           let savedLocal = AgentPermissionPreset(rawValue: rawLocal) {
            store.localPermissionPreset = savedLocal
            store.appearancePreferences.globalPermissionPreset = savedLocal
            store.appearancePreferences.terminalSandboxEnabled = savedLocal.usesTerminalSandbox
        }
        if let rawRemote = store.preferencesStore.string(forKey: Self.remotePermissionDefaultsKey),
           let savedRemote = AgentPermissionPreset(rawValue: rawRemote) {
            store.remotePermissionPreset = savedRemote
        }
        if let rawAppearance = store.preferencesStore.string(forKey: Self.appearanceModeDefaultsKey),
           let savedAppearance = AppAppearanceMode(rawValue: rawAppearance) {
            store.appearancePreferences.appearanceMode = savedAppearance
        }
        if let rawLanguage = store.preferencesStore.string(forKey: Self.appLanguageDefaultsKey) {
            store.appearancePreferences.language = AppLanguage.fromTag(rawLanguage)
        }
        if let rawUserName = store.preferencesStore.string(forKey: Self.userDisplayNameDefaultsKey),
           let savedUserName = UserGreetingFormatter.formatGreetingName(rawUserName) {
            store.userDisplayName = savedUserName
        }
        return store
    }
}
