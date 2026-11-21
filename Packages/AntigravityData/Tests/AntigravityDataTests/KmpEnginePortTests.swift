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
}
