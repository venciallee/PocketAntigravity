import Foundation

/// Outcome returned by `AntigravityKmpEnginePort.sendMessage(...)` after KMP Durable Outbox + Ktor RPC dispatch.
public struct KmpSendMessageResult: Sendable, Equatable {
    public let resolvedCascadeId: String
    public let dispatchedLive: Bool
    public let queuedInOutbox: Bool
    public let errorMessage: String?
    public let hostOfflineDetected: Bool

    public init(
        resolvedCascadeId: String,
        dispatchedLive: Bool,
        queuedInOutbox: Bool,
        errorMessage: String? = nil,
        hostOfflineDetected: Bool = false
    ) {
        self.resolvedCascadeId = resolvedCascadeId
        self.dispatchedLive = dispatchedLive
        self.queuedInOutbox = queuedInOutbox
        self.errorMessage = errorMessage
        self.hostOfflineDetected = hostOfflineDetected
    }
}

/// Federated workspace + summary sync result returned by `AntigravityKmpEnginePort.refreshWorkspacesAndSummaries(...)`.
public struct KmpFederatedSyncResult: Sendable, Equatable {
    public let workspaces: [WorkspaceInfo]
    public let summaries: [CascadeSummary]
    public let cloudProjects: [ProjectWorkspace]
    public let cloudWarmingUp: Bool
    public let availableRelayInstances: [RelayInstanceInfo]
    public let succeededInstanceUuids: [String]
    public let cloudSucceeded: Bool
    public let latencyMs: Int

    public init(
        workspaces: [WorkspaceInfo],
        summaries: [CascadeSummary],
        cloudProjects: [ProjectWorkspace] = [],
        cloudWarmingUp: Bool = false,
        availableRelayInstances: [RelayInstanceInfo] = [],
        succeededInstanceUuids: [String] = [],
        cloudSucceeded: Bool = false,
        latencyMs: Int = 0
    ) {
        self.workspaces = workspaces
        self.summaries = summaries
        self.cloudProjects = cloudProjects
        self.cloudWarmingUp = cloudWarmingUp
        self.availableRelayInstances = availableRelayInstances
        self.succeededInstanceUuids = succeededInstanceUuids
        self.cloudSucceeded = cloudSucceeded
        self.latencyMs = latencyMs
    }
}

/// Incremental real-time step and status update delivered by KMP `StreamAgentStateUpdates` or progressive sync.
public struct KmpLiveChatUpdate: Sendable, Equatable {
    public let cascadeId: String
    public let steps: [CascadeStep]
    public let totalLength: Int?
    public let runStatus: String?
    public let isSnapshotComplete: Bool

    public init(
        cascadeId: String,
        steps: [CascadeStep],
        totalLength: Int? = nil,
        runStatus: String? = nil,
        isSnapshotComplete: Bool = false
    ) {
        self.cascadeId = cascadeId
        self.steps = steps
        self.totalLength = totalLength
        self.runStatus = runStatus
        self.isSnapshotComplete = isSnapshotComplete
    }
}

/// Dependency-inverted pure-Swift port for delegating core connection, conversation sync,
/// adaptive binary-first trajectory step loading (Binary Protobuf default + runtime JSON ceiling learning), and PC-side core interactions
/// (`StartCascade`, `SendUserCascadeMessage`, `HandleCascadeUserInteraction`, `CancelCascadeInvocation`)
/// to the Kotlin Multiplatform `AntigravityShared.xcframework` (`Ktor Darwin` + `SKIE` + `AntigravityCoreCoordinator`).
///
/// Keeping this protocol in `AntigravityData` ensures `AGPocketLiveActivity` (WidgetKit 30MB limit)
/// and `AGPocketShare` extensions never link the Kotlin/Native binary, while the main `AGPocket.app`
/// injects `KmpCoreEngineAdapter` at launch.
public protocol AntigravityKmpEnginePort: Sendable {
    var engineName: String { get }

    func connectDirectLan(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String?,
        hostName: String,
        isRestoringSavedSession: Bool
    ) async throws -> BackendHandshakeResult

    func connectCloudRelay(
        relayURLString: String,
        sessionCookie: String,
        authUser: String?,
        resolvedInstanceUuid: String?,
        relayApiKey: String?,
        hostName: String,
        isRestoringSavedSession: Bool,
        strictTargetMatch: Bool
    ) async throws -> BackendHandshakeResult

    func probeHostReachability(allowCrossHostFallback: Bool) async throws -> HostReachabilityProbeResult
    func probeHostReachability(allowCrossHostFallback: Bool, verifyEndToEnd: Bool) async throws -> HostReachabilityProbeResult

    func refreshWorkspacesAndSummaries(
        hostScope: AgentsHostFilterScope,
        skipRelayListRefresh: Bool
    ) async throws -> KmpFederatedSyncResult

    func syncSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep]

    func forceSyncSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep]

    func fetchBinaryStepDelta(
        cascadeId: String,
        startIndex: Int,
        knownStepCount: Int,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep]

    func preloadSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?,
        requireRemoteRefresh: Bool
    ) async throws -> [CascadeStep]

    var supportsNativeLiveChatStream: Bool { get }
    func startLiveChatStream(
        cascadeId: String,
        isCloud: Bool,
        instanceUuidOverride: String?
    )
    func stopLiveChatStream()
    func liveChatUpdatesStream() -> AsyncStream<KmpLiveChatUpdate>

    func startConversation(
        workspaceUri: String,
        initialPrompt: String,
        modelId: String,
        cloudProjectId: String?,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> String

    func sendMessage(
        cascadeId: String,
        message: String,
        workspaceUri: String,
        attachments: [ComposerAttachmentChip],
        modelId: String,
        effort: ThinkingEffortLevel,
        mode: CascadeExecutionMode,
        agentPersona: String,
        isCloud: Bool,
        cloudProjectId: String?,
        permissionPreset: AgentPermissionPreset?,
        instanceUuidOverride: String?,
        isOptimisticDraft: Bool
    ) async throws -> KmpSendMessageResult

    func resolveWaitingInteraction(
        step: CascadeStep,
        decision: InteractionDecision,
        workspaceUri: String?,
        instanceUuidOverride: String?
    ) async throws -> CascadeUserInteractionPayload

    func cancelActiveTurn(
        cascadeId: String,
        instanceUuidOverride: String?
    ) async throws

    func replayPendingOutbox(
        modelId: String,
        effort: ThinkingEffortLevel,
        mode: CascadeExecutionMode
    ) async -> Int

    func switchToRelayInstance(_ instance: RelayInstanceInfo) async

    func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]>

    func onBackground()
    func onForeground() async
    func disconnectAndClearCredentials() async

    /// Fetches the real signed-in user's greeting display name via KMP `GetUserStatus` (`refreshUserProfile`).
    func fetchUserDisplayName() async -> String?

    /// Zero-secret stage-by-stage diagnostic breadcrumb from the active or latest KMP handshake attempt.
    var lastHandshakeDiagnostic: String { get }
}

public extension AntigravityKmpEnginePort {
    var lastHandshakeDiagnostic: String { "" }
    func fetchUserDisplayName() async -> String? { nil }

    func probeHostReachability(
        allowCrossHostFallback: Bool,
        verifyEndToEnd: Bool
    ) async throws -> HostReachabilityProbeResult {
        try await probeHostReachability(allowCrossHostFallback: allowCrossHostFallback)
    }

    func forceSyncSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep] {
        try await syncSteps(
            cascadeId: cascadeId,
            knownStepCount: knownStepCount,
            isCloud: isCloud,
            instanceUuidOverride: instanceUuidOverride
        )
    }

    func fetchBinaryStepDelta(
        cascadeId: String,
        startIndex: Int,
        knownStepCount: Int,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep] {
        []
    }

    var supportsNativeLiveChatStream: Bool { false }

    func startLiveChatStream(
        cascadeId: String,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) {}

    func stopLiveChatStream() {}

    func liveChatUpdatesStream() -> AsyncStream<KmpLiveChatUpdate> {
        AsyncStream { $0.finish() }
    }

    func preloadSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?,
        requireRemoteRefresh: Bool
    ) async throws -> [CascadeStep] {
        try await syncSteps(
            cascadeId: cascadeId,
            knownStepCount: knownStepCount,
            isCloud: isCloud,
            instanceUuidOverride: instanceUuidOverride
        )
    }
}
