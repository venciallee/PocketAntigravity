import XCTest
@testable import AntigravityData

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int = 0
    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
    func read() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private actor RecordingKmpEngineDouble: AntigravityKmpEnginePort {
    nonisolated var engineName: String { "RecordingKmpEngineDouble" }
    nonisolated var lastHandshakeDiagnostic: String { "engine=RecordingKmpEngineDouble trace=mock" }

    var directLanCalls: [(endpoint: String, csrf: String, hostName: String)] = []
    var cloudRelayCalls: [(relayURL: String, cookie: String)] = []
    var refreshCalls: Int = 0
    var syncStepsCalls: [String] = []
    var sentMessages: [(cascadeId: String, message: String)] = []
    var resolvedInteractions: [(cascadeId: String, stepIndex: Int)] = []
    var cancelledCascadeIds: [String] = []
    var disconnectCount: Int = 0
    var foregroundCount: Int = 0
    private let backgroundCounter = LockedCounter()

    var backgroundCount: Int {
        backgroundCounter.read()
    }

    func connectDirectLan(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String?,
        hostName: String,
        isRestoringSavedSession: Bool
    ) async throws -> BackendHandshakeResult {
        directLanCalls.append((endpointURLString, csrfToken, hostName))
        return BackendHandshakeResult(
            latencyMs: 12,
            workspaces: [
                WorkspaceInfo(
                    workspaceUri: "file:///Users/dev/code/ledger-svc",
                    displayName: "ledger-svc",
                    activeBranch: "main"
                )
            ],
            summaries: [
                CascadeSummary(
                    cascadeId: "kmp-live-session-1",
                    title: "KMP Powered Session",
                    projectSlug: "ledger-svc",
                    workspaceUri: "file:///Users/dev/code/ledger-svc",
                    status: .waiting,
                    stepCount: 2,
                    isUnread: true
                )
            ],
            resolvedHostname: hostName,
            isSelectedHostOnline: true
        )
    }

    func connectCloudRelay(
        relayURLString: String,
        sessionCookie: String,
        authUser: String?,
        resolvedInstanceUuid: String?,
        relayApiKey: String?,
        hostName: String,
        isRestoringSavedSession: Bool,
        strictTargetMatch: Bool
    ) async throws -> BackendHandshakeResult {
        cloudRelayCalls.append((relayURLString, sessionCookie))
        return BackendHandshakeResult(
            latencyMs: 34,
            workspaces: [],
            summaries: [],
            resolvedHostname: "golden-star",
            resolvedInstanceUuid: "uuid-golden-star-v2",
            resolvedAuthUser: "2",
            availableRelayInstances: [
                RelayInstanceInfo(uuid: "uuid-golden-star-v2", name: "golden-star", status: .connected)
            ],
            isSelectedHostOnline: true
        )
    }

    func probeHostReachability(allowCrossHostFallback: Bool) async throws -> HostReachabilityProbeResult {
        HostReachabilityProbeResult(latencyMs: 15, isSelectedHostOnline: true)
    }

    func refreshWorkspacesAndSummaries(
        hostScope: AgentsHostFilterScope,
        skipRelayListRefresh: Bool
    ) async throws -> KmpFederatedSyncResult {
        refreshCalls += 1
        return KmpFederatedSyncResult(
            workspaces: [
                WorkspaceInfo(
                    workspaceUri: "file:///Users/dev/code/ledger-svc",
                    displayName: "ledger-svc"
                )
            ],
            summaries: [
                CascadeSummary(
                    cascadeId: "kmp-live-session-1",
                    title: "KMP Refreshed Session",
                    projectSlug: "ledger-svc",
                    workspaceUri: "file:///Users/dev/code/ledger-svc",
                    status: .done,
                    stepCount: 4
                )
            ],
            succeededInstanceUuids: ["direct-127.0.0.1"],
            latencyMs: 14
        )
    }

    func syncSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep] {
        syncStepsCalls.append(cascadeId)
        return [
            CascadeStep(
                cascadeId: cascadeId,
                stepIndex: 0,
                type: .plannerResponse,
                status: .done,
                plannerResponse: PlannerResponsePayload(response: "Loaded via KMP")
            ),
            CascadeStep(
                cascadeId: cascadeId,
                stepIndex: 1,
                type: .runCommand,
                status: .waiting,
                runCommand: RunCommandPayload(commandId: "cmd-1", commandLine: "go test ./...", cwd: "/workspace"),
                requestedInteraction: RequestedInteraction(
                    kind: .runCommand,
                    runCommand: RunCommandInteractionSpec(proposedCommandLine: "go test ./...", cwd: "/workspace"),
                    rawMemberKey: "runCommand"
                )
            )
        ]
    }

    func startConversation(
        workspaceUri: String,
        initialPrompt: String,
        modelId: String,
        cloudProjectId: String?,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> String {
        "real-kmp-cascade-01"
    }

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
    ) async throws -> KmpSendMessageResult {
        sentMessages.append((cascadeId, message))
        return KmpSendMessageResult(resolvedCascadeId: cascadeId, dispatchedLive: true, queuedInOutbox: false)
    }

    func resolveWaitingInteraction(
        step: CascadeStep,
        decision: InteractionDecision,
        workspaceUri: String?,
        instanceUuidOverride: String?
    ) async throws -> CascadeUserInteractionPayload {
        resolvedInteractions.append((step.cascadeId, step.stepIndex))
        guard let payload = InteractionBuilder.buildPayload(step: step, decision: decision, workspaceUri: workspaceUri) else {
            throw AntigravityRPCError.interactionRejected
        }
        return payload
    }

    func cancelActiveTurn(cascadeId: String, instanceUuidOverride: String?) async throws {
        cancelledCascadeIds.append(cascadeId)
    }

    func replayPendingOutbox(
        modelId: String,
        effort: ThinkingEffortLevel,
        mode: CascadeExecutionMode
    ) async -> Int {
        0
    }

    func switchToRelayInstance(_ instance: RelayInstanceInfo) async {}

    nonisolated func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    nonisolated func onBackground() {
        backgroundCounter.increment()
    }

    func onForeground() async {
        foregroundCount += 1
    }

    func disconnectAndClearCredentials() async {
        disconnectCount += 1
    }
}

final class KmpEnginePortTests: XCTestCase {

    @MainActor
    func testSessionStoreDelegatesCoreFlowsToInjectedKmpEngine() async throws {
        let engine = RecordingKmpEngineDouble()
        let store = AntigravitySessionStore.makeLiveStore(kmpEngine: engine)
        XCTAssertTrue(store.isUsingKmpEngine)

        // 1. Direct LAN connect delegates to KMP engine
        let connected = await store.connectDirectLAN(
            endpointURLString: "http://127.0.0.1:18787",
            csrfToken: "csrf-kmp-test",
            hostName: "KMP-MacBook"
        )
        XCTAssertTrue(connected)
        XCTAssertTrue(store.isLiveBackendConnected)
        let directCalls = await engine.directLanCalls
        XCTAssertEqual(directCalls.count, 1)
        XCTAssertEqual(directCalls.first?.csrf, "csrf-kmp-test")
        XCTAssertEqual(store.summaries.first?.cascadeId, "kmp-live-session-1")

        // 2. Refresh workspaces & summaries delegates to KMP engine
        await store.refreshWorkspacesAndSummaries(forceFullSync: true)
        let refreshes = await engine.refreshCalls
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(store.summaries.first?.title, "KMP Refreshed Session")

        // 3. Step sync delegates directly through store.syncStepsForCascade to KMP engine
        store.activeCascadeId = "kmp-live-session-1"
        store.syncStepsForCascade("kmp-live-session-1", pollUntilIdle: false)
        for _ in 0..<20 where (store.stepsByCascadeId["kmp-live-session-1"]?.count ?? 0) < 2 {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let stepSyncCalls = await engine.syncStepsCalls
        XCTAssertTrue(stepSyncCalls.contains("kmp-live-session-1"))
        XCTAssertEqual(store.stepsByCascadeId["kmp-live-session-1"]?.count, 2)

        // 4. Send message & Face ID approval & cancel delegate to KMP engine
        store.composerDraftText = "Verify KMP bridge turn"
        store.sendCurrentDraft()
        store.resolveWaitingStep(stepIndex: 1, decision: .allowWithFaceID)
        store.stopActiveCascadeStreaming()

        for _ in 0..<20 {
            let sent = await engine.sentMessages
            let interactions = await engine.resolvedInteractions
            let cancels = await engine.cancelledCascadeIds
            if !sent.isEmpty && !interactions.isEmpty && !cancels.isEmpty {
                break
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        let sent = await engine.sentMessages
        XCTAssertTrue(sent.contains(where: { $0.message == "Verify KMP bridge turn" }))
        let interactions = await engine.resolvedInteractions
        XCTAssertTrue(interactions.contains(where: { $0.stepIndex == 1 }))
        let cancels = await engine.cancelledCascadeIds
        XCTAssertTrue(cancels.contains("kmp-live-session-1"))

        // 5. Lifecycle & disconnect delegate to KMP engine
        store.suspendNetworkingForBackground()
        let bgCount = await engine.backgroundCount
        XCTAssertEqual(bgCount, 1)

        await store.disconnectBackendAndClearKeychain()
        let disconnects = await engine.disconnectCount
        XCTAssertEqual(disconnects, 1)
    }

    @MainActor
    func testCloudRelayHandshakeWithEmptyInitialSummariesTriggersDeferredBackgroundRefresh() async throws {
        let engine = RecordingKmpEngineDouble()
        let store = AntigravitySessionStore.makeLiveStore(kmpEngine: engine)

        let connected = await store.connectCloudRelay(
            relayURLString: "https://antigravity.google/r/uuid-golden-star-v2",
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyTESTKMPDEFER000000000000000000000",
            hostName: "golden-star"
        )
        XCTAssertTrue(connected)
        XCTAssertTrue(store.isLiveBackendConnected)

        for _ in 0..<25 where (await engine.refreshCalls) == 0 {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let refreshes = await engine.refreshCalls
        XCTAssertGreaterThanOrEqual(refreshes, 1, "Empty initial handshake must trigger deferred background refresh")
    }

    @MainActor
    func testKmpSummaryStreamPreservesMarkAllReadAndTriggersActiveChatSync() async throws {
        let engine = StreamingKmpEngineDouble()
        let store = AntigravitySessionStore.makeLiveStore(kmpEngine: engine)

        let connected = await store.connectDirectLAN(
            endpointURLString: "http://127.0.0.1:18787",
            csrfToken: "csrf-stream-test",
            hostName: "Stream-MacBook"
        )
        XCTAssertTrue(connected)
        XCTAssertEqual(store.unreadCount, 1)

        // Mark all as read -> unread count drops to 0
        store.markAllConversationsAsRead()
        XCTAssertEqual(store.unreadCount, 0)

        // Emit stale snapshot from KMP summary stream -> must NOT re-mark unread
        let baseDate = store.summaries.first?.updatedAt ?? Date()
        engine.emit([
            CascadeSummary(
                cascadeId: "kmp-live-session-1",
                title: "KMP Powered Session",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/dev/code/ledger-svc",
                status: .done,
                stepCount: 2,
                updatedAt: baseDate,
                isUnread: true
            )
        ])
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(store.unreadCount, 0, "Stale KMP stream snapshot must not revert markAllConversationsAsRead")

        // Open active chat, then emit PC stepCount update -> must trigger immediate syncSteps without waiting for fallback timer
        store.activeCascadeId = "kmp-live-session-1"
        store.activeRoute = .cascadeChat("kmp-live-session-1")
        let initialSyncCount = await engine.syncStepsCalls.count

        engine.emit([
            CascadeSummary(
                cascadeId: "kmp-live-session-1",
                title: "KMP Powered Session",
                projectSlug: "ledger-svc",
                workspaceUri: "file:///Users/dev/code/ledger-svc",
                status: .done,
                stepCount: 4,
                updatedAt: baseDate.addingTimeInterval(15),
                isUnread: true
            )
        ])
        for _ in 0..<25 {
            let count = await engine.syncStepsCalls.count
            if count > initialSyncCount { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let finalSyncCount = await engine.syncStepsCalls.count
        XCTAssertGreaterThan(finalSyncCount, initialSyncCount, "KMP stream update advancing active chat stepCount must immediately trigger syncSteps")
        XCTAssertEqual(store.unreadCount, 0, "Activity on the currently viewed active chat must stay marked read")

        // Verify CascadeDisplayItem.id includes step type so index collisions never reuse stale views
        let userStep = CascadeStep(cascadeId: "cid-1", stepIndex: 1, type: .userInput, status: .done, userInput: "hi")
        let plannerStep = CascadeStep(cascadeId: "cid-1", stepIndex: 1, type: .plannerResponse, status: .done, plannerResponse: PlannerResponsePayload(response: "hello"))
        XCTAssertNotEqual(CascadeDisplayItem.single(userStep).id, CascadeDisplayItem.single(plannerStep).id)
    }

    @MainActor
    func testHostScopeSwitchRoutesRefreshThroughKmpEngineAndIsolatesScopedProjects() async throws {
        let engine = MultiHostKmpEngineDouble()
        let store = AntigravitySessionStore.makeLiveStore(kmpEngine: engine)

        let connected = await store.connectCloudRelay(
            relayURLString: "https://antigravity.google/r/uuid-mbp",
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyTESTMULTIHOST0000000000000000000",
            hostName: "MacBook Pro"
        )
        XCTAssertTrue(connected)
        XCTAssertEqual(store.pairedLocalHosts.count, 2)

        // Initially scoped to MacBook Pro: MacBook Pro repo should match, Cloud and Mac mini repos must not
        let mbpScope = AgentsHostFilterScope.localHost(id: "uuid-mbp", name: "MacBook Pro")
        let miniScope = AgentsHostFilterScope.localHost(id: "uuid-macmini", name: "huangjiafandemac-mini-local-swift-vapor")

        // Legacy/untagged project with hostName == "MacBook Pro" must NOT leak into Mac mini scope
        let untaggedMbpProject = ProjectWorkspace(
            id: "legacy-mbp-only",
            name: "legacy-mbp-only",
            pathDisplay: "~/legacy-mbp-only",
            workspaceUri: "file:///Users/mbp/legacy-mbp-only",
            runtime: .macBookPro,
            hostName: "MacBook Pro",
            originInstanceUuid: nil
        )
        XCTAssertTrue(store.projectMatchesHostScope(untaggedMbpProject, scope: mbpScope))
        XCTAssertFalse(
            store.projectMatchesHostScope(untaggedMbpProject, scope: miniScope),
            "Project with hostName='MacBook Pro' must not leak into a different local host when multiple Macs are paired"
        )

        // Switch device to Mac mini -> must route scoped refresh through kmpEngine and update selectedProjectId
        store.selectHostScope(miniScope)
        for _ in 0..<40 {
            let scoped = store.projects.filter { !$0.isNoProject && store.projectMatchesHostScope($0) }
            if scoped.contains(where: { $0.name == "vapor-backend" }) &&
                scoped.contains(where: { $0.id == store.selectedProjectId }) {
                break
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        let refreshedScopes = await engine.refreshedScopes
        XCTAssertTrue(
            refreshedScopes.contains(miniScope),
            "Switching local host must trigger KMP-backed scoped refresh for the target device"
        )
        let miniScopedProjects = store.projects.filter { !$0.isNoProject && store.projectMatchesHostScope($0) }
        XCTAssertEqual(Set(miniScopedProjects.map(\.name)), Set(["vapor-backend", "PocketAntigravity"]))
        XCTAssertTrue(
            miniScopedProjects.contains(where: { $0.id == store.selectedProjectId }),
            "selectedProjectId must update to a repo belonging to the newly selected device"
        )

        // Switch to Antigravity Cloud -> must surface preserved Cloud project and update selectedProjectId
        store.selectHostScope(.antigravityCloud)
        for _ in 0..<40 {
            let cloudScoped = store.projects.filter { !$0.isNoProject && store.projectMatchesHostScope($0) }
            if cloudScoped.contains(where: { $0.name == "venciallee/PocketAntigravity" }) &&
                cloudScoped.contains(where: { $0.id == store.selectedProjectId }) {
                break
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let cloudScopedProjects = store.projects.filter { !$0.isNoProject && store.projectMatchesHostScope($0) }
        XCTAssertTrue(cloudScopedProjects.contains(where: { $0.name == "venciallee/PocketAntigravity" }))
        XCTAssertTrue(cloudScopedProjects.contains(where: { $0.id == store.selectedProjectId }))
    }
}

private actor MultiHostKmpEngineDouble: AntigravityKmpEnginePort {
    nonisolated var engineName: String { "MultiHostKmpEngineDouble" }
    nonisolated var lastHandshakeDiagnostic: String { "engine=MultiHostKmpEngineDouble" }

    private let mbpUuid = "uuid-mbp"
    private let miniUuid = "uuid-macmini"
    private let miniName = "huangjiafandemac-mini-local-swift-vapor"

    var refreshedScopes: [AgentsHostFilterScope] = []
    var switchedInstances: [String] = []

    private var relayList: [RelayInstanceInfo] {
        [
            RelayInstanceInfo(uuid: mbpUuid, name: "MacBook Pro", status: .connected),
            RelayInstanceInfo(uuid: miniUuid, name: miniName, status: .connected)
        ]
    }

    private var cloudProject: ProjectWorkspace {
        ProjectWorkspace(
            id: "cloud:venciallee/PocketAntigravity",
            name: "venciallee/PocketAntigravity",
            pathDisplay: "Cloud · venciallee/PocketAntigravity",
            workspaceUri: "cloud://venciallee/PocketAntigravity",
            runtime: .cloud,
            hostName: "Cloud",
            cloudProjectId: "cloud-pocket-1"
        )
    }

    func connectDirectLan(endpointURLString: String, csrfToken: String, certSHA256: String?, hostName: String, isRestoringSavedSession: Bool) async throws -> BackendHandshakeResult {
        throw AntigravityRPCError.invalidEndpoint
    }

    func connectCloudRelay(
        relayURLString: String,
        sessionCookie: String,
        authUser: String?,
        resolvedInstanceUuid: String?,
        relayApiKey: String?,
        hostName: String,
        isRestoringSavedSession: Bool,
        strictTargetMatch: Bool
    ) async throws -> BackendHandshakeResult {
        BackendHandshakeResult(
            latencyMs: 20,
            workspaces: [
                WorkspaceInfo(
                    workspaceUri: "file:///Users/mbp/ios-app",
                    displayName: "ios-app",
                    isCloud: false,
                    originInstanceUuid: mbpUuid,
                    originHostName: "MacBook Pro"
                )
            ],
            summaries: [
                CascadeSummary(
                    cascadeId: "cas-mbp-1",
                    title: "MBP Build",
                    projectSlug: "ios-app",
                    workspaceUri: "file:///Users/mbp/ios-app",
                    status: .done,
                    stepCount: 2,
                    originInstanceUuid: mbpUuid,
                    originHostName: "MacBook Pro"
                )
            ],
            cloudProjects: [cloudProject],
            resolvedHostname: "MacBook Pro",
            resolvedInstanceUuid: mbpUuid,
            availableRelayInstances: relayList,
            isSelectedHostOnline: true
        )
    }

    func probeHostReachability(allowCrossHostFallback: Bool) async throws -> HostReachabilityProbeResult {
        HostReachabilityProbeResult(latencyMs: 12, availableRelayInstances: relayList, isSelectedHostOnline: true)
    }

    func refreshWorkspacesAndSummaries(
        hostScope: AgentsHostFilterScope,
        skipRelayListRefresh: Bool
    ) async throws -> KmpFederatedSyncResult {
        refreshedScopes.append(hostScope)
        switch hostScope {
        case .localHost(let id, _) where id == miniUuid:
            return KmpFederatedSyncResult(
                workspaces: [
                    WorkspaceInfo(
                        workspaceUri: "file:///Users/mini/vapor-backend",
                        displayName: "vapor-backend",
                        isCloud: false,
                        originInstanceUuid: miniUuid,
                        originHostName: miniName
                    ),
                    WorkspaceInfo(
                        workspaceUri: "file:///Users/mini/PocketAntigravity",
                        displayName: "PocketAntigravity",
                        isCloud: false,
                        originInstanceUuid: miniUuid,
                        originHostName: miniName
                    )
                ],
                summaries: [
                    CascadeSummary(
                        cascadeId: "cas-mini-1",
                        title: "Vapor Migration",
                        projectSlug: "vapor-backend",
                        workspaceUri: "file:///Users/mini/vapor-backend",
                        status: .done,
                        stepCount: 3,
                        originInstanceUuid: miniUuid,
                        originHostName: miniName
                    )
                ],
                cloudProjects: [],
                availableRelayInstances: relayList,
                succeededInstanceUuids: [miniUuid],
                cloudSucceeded: false,
                latencyMs: 18
            )
        case .antigravityCloud:
            return KmpFederatedSyncResult(
                workspaces: [],
                summaries: [],
                cloudProjects: [cloudProject],
                availableRelayInstances: relayList,
                succeededInstanceUuids: [],
                cloudSucceeded: true,
                latencyMs: 15
            )
        default:
            return KmpFederatedSyncResult(
                workspaces: [
                    WorkspaceInfo(
                        workspaceUri: "file:///Users/mbp/ios-app",
                        displayName: "ios-app",
                        isCloud: false,
                        originInstanceUuid: mbpUuid,
                        originHostName: "MacBook Pro"
                    )
                ],
                summaries: [],
                cloudProjects: [cloudProject],
                availableRelayInstances: relayList,
                succeededInstanceUuids: [mbpUuid],
                cloudSucceeded: true,
                latencyMs: 15
            )
        }
    }

    func syncSteps(cascadeId: String, knownStepCount: Int, isCloud: Bool, instanceUuidOverride: String?) async throws -> [CascadeStep] { [] }
    func startConversation(workspaceUri: String, initialPrompt: String, modelId: String, cloudProjectId: String?, isCloud: Bool, instanceUuidOverride: String?) async throws -> String { "cid-new" }
    func sendMessage(cascadeId: String, message: String, workspaceUri: String, attachments: [ComposerAttachmentChip], modelId: String, effort: ThinkingEffortLevel, mode: CascadeExecutionMode, agentPersona: String, isCloud: Bool, cloudProjectId: String?, permissionPreset: AgentPermissionPreset?, instanceUuidOverride: String?, isOptimisticDraft: Bool) async throws -> KmpSendMessageResult {
        KmpSendMessageResult(resolvedCascadeId: cascadeId, dispatchedLive: true, queuedInOutbox: false)
    }
    func resolveWaitingInteraction(step: CascadeStep, decision: InteractionDecision, workspaceUri: String?, instanceUuidOverride: String?) async throws -> CascadeUserInteractionPayload {
        throw AntigravityRPCError.interactionRejected
    }
    func cancelActiveTurn(cascadeId: String, instanceUuidOverride: String?) async throws {}
    func replayPendingOutbox(modelId: String, effort: ThinkingEffortLevel, mode: CascadeExecutionMode) async -> Int { 0 }
    func switchToRelayInstance(_ instance: RelayInstanceInfo) async { switchedInstances.append(instance.uuid) }
    nonisolated func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> { AsyncStream { $0.finish() } }
    nonisolated func onBackground() {}
    func onForeground() async {}
    func disconnectAndClearCredentials() async {}
}

private final class StreamHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<[CascadeSummary]>.Continuation?

    func makeStream() -> AsyncStream<[CascadeSummary]> {
        AsyncStream { cont in
            self.lock.lock()
            self.continuation = cont
            self.lock.unlock()
        }
    }

    func yield(_ summaries: [CascadeSummary]) {
        lock.lock()
        let cont = continuation
        lock.unlock()
        cont?.yield(summaries)
    }
}

private actor StreamingKmpEngineDouble: AntigravityKmpEnginePort {
    nonisolated var engineName: String { "StreamingKmpEngineDouble" }
    nonisolated var lastHandshakeDiagnostic: String { "engine=StreamingKmpEngineDouble trace=mock" }
    private let hub = StreamHub()
    var syncStepsCalls: [String] = []

    nonisolated func emit(_ summaries: [CascadeSummary]) {
        hub.yield(summaries)
    }

    func connectDirectLan(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String?,
        hostName: String,
        isRestoringSavedSession: Bool
    ) async throws -> BackendHandshakeResult {
        BackendHandshakeResult(
            latencyMs: 10,
            workspaces: [WorkspaceInfo(workspaceUri: "file:///Users/dev/code/ledger-svc", displayName: "ledger-svc", activeBranch: "main")],
            summaries: [
                CascadeSummary(
                    cascadeId: "kmp-live-session-1",
                    title: "KMP Powered Session",
                    projectSlug: "ledger-svc",
                    workspaceUri: "file:///Users/dev/code/ledger-svc",
                    status: .done,
                    stepCount: 2,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    isUnread: true
                )
            ],
            resolvedHostname: hostName,
            isSelectedHostOnline: true
        )
    }

    func connectCloudRelay(
        relayURLString: String,
        sessionCookie: String,
        authUser: String?,
        resolvedInstanceUuid: String?,
        relayApiKey: String?,
        hostName: String,
        isRestoringSavedSession: Bool,
        strictTargetMatch: Bool
    ) async throws -> BackendHandshakeResult {
        BackendHandshakeResult(latencyMs: 10, workspaces: [], summaries: [], isSelectedHostOnline: true)
    }

    func probeHostReachability(allowCrossHostFallback: Bool) async throws -> HostReachabilityProbeResult {
        HostReachabilityProbeResult(latencyMs: 10, isSelectedHostOnline: true)
    }

    func refreshWorkspacesAndSummaries(
        hostScope: AgentsHostFilterScope,
        skipRelayListRefresh: Bool
    ) async throws -> KmpFederatedSyncResult {
        KmpFederatedSyncResult(workspaces: [], summaries: [], latencyMs: 10)
    }

    func syncSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep] {
        syncStepsCalls.append(cascadeId)
        return [
            CascadeStep(cascadeId: cascadeId, stepIndex: 0, type: .userInput, status: .done, userInput: "Hello"),
            CascadeStep(cascadeId: cascadeId, stepIndex: 1, type: .plannerResponse, status: .done, plannerResponse: PlannerResponsePayload(response: "World"))
        ]
    }

    func startConversation(
        workspaceUri: String,
        initialPrompt: String,
        modelId: String,
        cloudProjectId: String?,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> String { "cid-stream-created" }

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
    ) async throws -> KmpSendMessageResult {
        KmpSendMessageResult(resolvedCascadeId: cascadeId, dispatchedLive: true, queuedInOutbox: false)
    }

    func resolveWaitingInteraction(
        step: CascadeStep,
        decision: InteractionDecision,
        workspaceUri: String?,
        instanceUuidOverride: String?
    ) async throws -> CascadeUserInteractionPayload {
        throw AntigravityRPCError.interactionRejected
    }

    func cancelActiveTurn(cascadeId: String, instanceUuidOverride: String?) async throws {}
    func replayPendingOutbox(modelId: String, effort: ThinkingEffortLevel, mode: CascadeExecutionMode) async -> Int { 0 }
    func switchToRelayInstance(_ instance: RelayInstanceInfo) async {}
    nonisolated func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> { hub.makeStream() }
    nonisolated func onBackground() {}
    func onForeground() async {}
    func disconnectAndClearCredentials() async {}
}
