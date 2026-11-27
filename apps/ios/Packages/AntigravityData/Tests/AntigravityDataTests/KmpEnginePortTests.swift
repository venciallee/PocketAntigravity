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

    @MainActor
    func testConversationPreloadLoadingTitleDiskCacheWarmupAndReconnectPreservation() async throws {
        // 1. Verify decoder distinguishes unresolved/placeholder titles from resolved titles & nested prompts
        let missingSummaryEntry: JSONValue = .object([
            "stepCount": .int(4),
            "status": .string("CASCADE_RUN_STATUS_IDLE")
        ])
        let decodedUnresolved = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "8b52c910-1111-4000-8000-000000000001",
                value: missingSummaryEntry
            )
        )
        XCTAssertFalse(decodedUnresolved.hasResolvedTitle)
        XCTAssertTrue(decodedUnresolved.needsTitleHydration)

        let nestedSummaryEntry: JSONValue = .object([
            "stepCount": .int(3),
            "firstUserInputStep": .object([
                "step": .object([
                    "userInput": .object([
                        "userResponse": .string("Investigate Slardar cold start\nperformance")
                    ])
                ])
            ])
        ])
        let decodedNested = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "8b52c910-1111-4000-8000-000000000002",
                value: nestedSummaryEntry
            )
        )
        XCTAssertTrue(decodedNested.hasResolvedTitle)
        XCTAssertEqual(decodedNested.title, "Investigate Slardar cold start performance")

        // 2. Verify live store shows Loading... (never "New Conversation") for unhydrated remote conversations,
        //    preloads & caches steps to disk, and survives reconnect + cold start
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityPreloadTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectionStore = LocalProjectionStore(storageDirectory: tempDir)
        let unhydratedId = "8b52c910-1111-4000-8000-000000000001"
        let engine = PreloadTestingKmpEngineDouble(unhydratedCascadeId: unhydratedId)
        let prefs = InMemoryPreferencesStore()
        let store = AntigravitySessionStore.makeLiveStore(
            projectionStore: projectionStore,
            secretStore: InMemorySecretStore(),
            preferencesStore: prefs,
            kmpEngine: engine
        )

        // Before connecting, an unhydrated server summary falls back to Untitled (never "New Conversation"),
        // and while connecting / hydrating displays "Loading..."
        let previewUnresolved = CascadeSummary(
            cascadeId: unhydratedId,
            title: "New Conversation",
            projectSlug: "slardar_app_ai",
            workspaceUri: "file:///Users/dev/slardar_app_ai",
            status: .done,
            stepCount: 2,
            hasResolvedTitle: false
        )
        XCTAssertFalse(store.isSummaryTitleLoading(previewUnresolved))
        XCTAssertEqual(store.displayTitle(for: previewUnresolved), "Untitled conversation")
        store.isConnectingToBackend = true
        XCTAssertTrue(store.isSummaryTitleLoading(previewUnresolved))
        XCTAssertEqual(store.displayTitle(for: previewUnresolved), "Loading...")
        store.isConnectingToBackend = false

        let connected = await store.connectDirectLAN(
            endpointURLString: "http://127.0.0.1:18787",
            csrfToken: "csrf-preload-test",
            hostName: "MacBook-Pro"
        )
        XCTAssertTrue(connected)

        // Wait for background preloader to hydrate title and persist debounced projection shard
        for _ in 0..<40 {
            let summary = store.summaries.first(where: { $0.cascadeId == unhydratedId })
            if summary?.hasResolvedTitle == true && !(store.stepsByCascadeId[unhydratedId] ?? []).isEmpty {
                break
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        let hydratedSummary = try XCTUnwrap(store.summaries.first(where: { $0.cascadeId == unhydratedId }))
        XCTAssertTrue(hydratedSummary.hasResolvedTitle)
        XCTAssertEqual(hydratedSummary.title, "Fix Slardar startup tracing")
        XCTAssertFalse(store.isSummaryTitleLoading(hydratedSummary))
        XCTAssertEqual(store.stepsByCascadeId[unhydratedId]?.count, 2)
        let preloadCalls = await engine.preloadCalls
        XCTAssertTrue(preloadCalls.contains(unhydratedId))

        // Wait briefly for debounced shard persistence to flush to disk
        try? await Task.sleep(nanoseconds: 450_000_000)
        let diskCachedSteps = await projectionStore.loadProjectedSteps(cascadeId: unhydratedId)
        XCTAssertEqual(diskCachedSteps.count, 2)

        // 3. Reconnecting with raw unhydrated server payload must NEVER revert hydrated title back to "New Conversation"
        let reconnected = await store.connectDirectLAN(
            endpointURLString: "http://127.0.0.1:18787",
            csrfToken: "csrf-preload-test",
            hostName: "MacBook-Pro"
        )
        XCTAssertTrue(reconnected)
        let afterReconnect = try XCTUnwrap(store.summaries.first(where: { $0.cascadeId == unhydratedId }))
        XCTAssertTrue(afterReconnect.hasResolvedTitle)
        XCTAssertEqual(afterReconnect.title, "Fix Slardar startup tracing")

        // 4. Persist project collapse state & verify cold-start store restores both cached steps/title and collapsed project
        XCTAssertFalse(store.isProjectCollapsed("slardar_app_ai"))
        store.toggleProjectCollapsedPersisted("slardar_app_ai")
        XCTAssertTrue(store.isProjectCollapsed("slardar_app_ai"))
        try? await Task.sleep(nanoseconds: 100_000_000)

        let coldStore = AntigravitySessionStore.makeLiveStore(
            projectionStore: projectionStore,
            secretStore: InMemorySecretStore(),
            preferencesStore: prefs
        )
        await coldStore.hydratePersistedHostProjectionsIfNeeded()
        await coldStore.loadPersistedV233Preferences()

        let restoredSummary = try XCTUnwrap(coldStore.summaries.first(where: { $0.cascadeId == unhydratedId }))
        XCTAssertEqual(restoredSummary.title, "Fix Slardar startup tracing")
        XCTAssertTrue(restoredSummary.hasResolvedTitle)
        XCTAssertEqual(coldStore.stepsByCascadeId[unhydratedId]?.count, 2)
        XCTAssertTrue(coldStore.isProjectCollapsed("slardar_app_ai"))

        // Selecting a cached conversation renders immediately without blocking loading state
        coldStore.selectCascade(unhydratedId)
        XCTAssertFalse(coldStore.isLoadingSteps)
        XCTAssertEqual(coldStore.activeSteps.count, 2)

        // Locally created new draft still displays without loading spinner
        let draftId = coldStore.createConversationInProject("slardar_app_ai")
        let draftSummary = try XCTUnwrap(coldStore.summaries.first(where: { $0.cascadeId == draftId }))
        XCTAssertFalse(coldStore.isSummaryTitleLoading(draftSummary))
    }

    @MainActor
    func testUnregisteredRelayErrorClassificationPreservesCachedProjectsAndQueuesCleanlyOnSend() async throws {
        let boqBody = """
        [9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo","INSTANCE_NOT_REGISTERED","antigravity.googleapis.com"]]]
        """
        XCTAssertTrue(ProtocolCompatibilityEngine.isInstanceNotRegisteredResponse(statusCode: 400, body: boqBody))
        XCTAssertFalse(ProtocolCompatibilityEngine.isMethodUnimplementedResponse(statusCode: 400, body: boqBody))
        let err400 = AntigravityRPCError.httpError(statusCode: 400, body: boqBody)
        XCTAssertTrue(AntigravitySessionStore.isBackendOfflineError(err400))
        let formatted = ProtocolCompatibilityEngine.formatUserFacingRpcError(err400)
        XCTAssertTrue(formatted.lowercased().contains("offline"))
        XCTAssertFalse(formatted.contains("type.googleapis.com"))
        XCTAssertFalse(formatted.contains("[9,"))

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ag-unregistered-relay-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectionStore = LocalProjectionStore(storageDirectory: tempRoot)

        let hostUuid = "huangjiafandemac-mini-local-swift-vapor"
        await projectionStore.saveHostProjections([
            HostProjectionSnapshot(
                hostKey: "host:\(hostUuid)",
                instanceId: hostUuid,
                hostname: hostUuid,
                isCloud: false,
                summaries: [
                    CascadeSummary(
                        cascadeId: "cas-cached-mini",
                        title: "Cached Mini Thread",
                        projectSlug: "PocketAntigravity",
                        workspaceUri: "file:///Users/mini/PocketAntigravity",
                        status: .done,
                        stepCount: 2,
                        originInstanceUuid: hostUuid,
                        originHostName: hostUuid
                    )
                ],
                projects: [
                    ProjectWorkspace(
                        id: "PocketAntigravity",
                        name: "PocketAntigravity",
                        pathDisplay: "Local · \(hostUuid)",
                        workspaceUri: "file:///Users/mini/PocketAntigravity",
                        runtime: .macBookPro,
                        hostName: hostUuid,
                        activeBranch: "main",
                        originInstanceUuid: hostUuid
                    )
                ]
            )
        ])

        let engine = UnregisteredRelayKmpEngineDouble(hostUuid: hostUuid)
        let store = AntigravitySessionStore.makeLiveStore(
            projectionStore: projectionStore,
            secretStore: InMemorySecretStore(),
            preferencesStore: InMemoryPreferencesStore(),
            kmpEngine: engine
        )
        await store.hydratePersistedHostProjectionsIfNeeded()

        // 1. Handshake with initialSyncCompleted=false & offline host MUST NOT wipe cached projects/summaries
        let connected = await store.connectCloudRelay(
            relayURLString: "https://antigravity.google.com/r/\(hostUuid)",
            sessionCookie: "SAPISID=test; SID=test",
            hostName: hostUuid,
            strictTargetMatch: true
        )
        XCTAssertTrue(connected)
        XCTAssertFalse(store.activeHost.isOnline)
        XCTAssertTrue(store.projects.contains(where: { $0.name == "PocketAntigravity" }))
        XCTAssertTrue(store.summaries.contains(where: { $0.cascadeId == "cas-cached-mini" }))

        // 2. Sending prompt + photo from Home must materialize user bubble synchronously, never call
        //    startConversation twice, queue into outbox without raw HTTP 400 toast, and stop streaming.
        let photoChip = ComposerAttachmentChip(
            id: "photo-chip-offline",
            kind: .imageScreenshot,
            label: "photo-1.jpg",
            targetUri: "attachment://photo/photo-chip-offline/photo-1.jpg",
            mimeType: "image/jpeg",
            byteSize: 16,
            inlineBase64Data: "iVBORw0KGgo="
        )
        let newId = store.createConversationInProject(
            AntigravityCloudDetector.noProjectDisplayName,
            title: "没拉到任何 project 啊",
            initialPrompt: "没拉到任何 project 啊",
            initialAttachments: [photoChip]
        )
        let immediateSteps = store.stepsByCascadeId[newId] ?? []
        XCTAssertEqual(immediateSteps.count, 1, "User bubble must appear immediately without flashing an empty card")
        XCTAssertEqual(immediateSteps.first?.type, .userInput)
        XCTAssertTrue(immediateSteps.first?.attachedMentions.contains("photo-1.jpg") == true)

        for _ in 0..<40 {
            if store.summaries.first(where: { $0.cascadeId == newId })?.status == .pending {
                break
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        let startCalls = await engine.startConversationCalls
        let sendCalls = await engine.sendMessageCalls
        XCTAssertEqual(startCalls, 0, "Home send must route solely through sendMessage without duplicate startConversation")
        XCTAssertEqual(sendCalls, 1)
        XCTAssertFalse(store.activeHost.isOnline)
        XCTAssertFalse(store.isCascadeStreaming, "Offline queued turn must never show Stop button or thinking bar")
        XCTAssertEqual(store.summaries.first(where: { $0.cascadeId == newId })?.status, .pending)
        for text in [store.compatibilityNoticeText, store.stepLoadErrorText, store.connectionErrorText].compactMap({ $0 }) {
            XCTAssertFalse(text.contains("type.googleapis.com"), "Raw protobuf @type leaked into UI error: \(text)")
            XCTAssertFalse(text.contains("HTTP 400"), "Raw HTTP 400 leaked into UI error: \(text)")
        }
    }

    @MainActor
    func testSyncStepsCoalescesDuplicateCallsSkipsFreshIdleCacheAndSupportsForceRefresh() async throws {
        let engine = SlowStepKmpEngineDouble()
        let store = AntigravitySessionStore.makeLiveStore(kmpEngine: engine)
        let connected = await store.connectDirectLAN(
            endpointURLString: "http://127.0.0.1:18789",
            csrfToken: "csrf-coalesce-test",
            hostName: "Coalesce-MacBook"
        )
        XCTAssertTrue(connected)

        // 1. Trigger selectCascade + immediate duplicate syncStepsForCascade (as SwiftUI .task would) -> must coalesce to 1 RPC!
        store.selectCascade("kmp-coalesce-1")
        XCTAssertTrue(store.hasActiveStepSync(for: "kmp-coalesce-1"))
        store.syncStepsForCascade("kmp-coalesce-1", pollUntilIdle: true)

        for _ in 0..<40 where (store.stepsByCascadeId["kmp-coalesce-1"]?.count ?? 0) < 2 {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let callsAfterFirstOpen = await engine.syncStepsCalls.count
        XCTAssertEqual(callsAfterFirstOpen, 1, "Duplicate syncStepsForCascade while already in-flight must coalesce into 1 RPC")
        XCTAssertEqual(store.stepsByCascadeId["kmp-coalesce-1"]?.count, 2)

        // 2. Display items memoize and stay accurate on step mutation
        let itemsBefore = store.displayItems
        XCTAssertEqual(itemsBefore.count, 2)
        let itemsCached = store.displayItems
        XCTAssertEqual(itemsCached.count, 2)

        // 3. Re-entering settled idle conversation with matching stepCount uses 0-RTT idle cache fast-path
        store.syncStepsForCascade("kmp-coalesce-1", pollUntilIdle: false)
        try? await Task.sleep(nanoseconds: 80_000_000)
        let callsAfterIdleReentry = await engine.syncStepsCalls.count
        XCTAssertEqual(callsAfterIdleReentry, 1, "Idle terminal cached conversation must skip redundant RPC on re-entry")

        // 4. Explicit forceRefresh bypasses 0-RTT cache and routes through forceSyncSteps
        store.syncStepsForCascade("kmp-coalesce-1", pollUntilIdle: false, forceRefresh: true)
        for _ in 0..<40 where (await engine.forceSyncStepsCalls.count) < 1 {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let forcedCalls = await engine.forceSyncStepsCalls.count
        XCTAssertEqual(forcedCalls, 1, "forceRefresh: true must bypass idle cache and invoke forceSyncSteps")

        // 5. Mutating stepsByCascadeId invalidates cached displayItems immediately
        var updated = store.stepsByCascadeId["kmp-coalesce-1"] ?? []
        updated.append(
            CascadeStep(
                cascadeId: "kmp-coalesce-1",
                stepIndex: 2,
                type: .plannerResponse,
                status: .done,
                plannerResponse: PlannerResponsePayload(response: "Follow-up")
            )
        )
        store.stepsByCascadeId["kmp-coalesce-1"] = updated
        XCTAssertEqual(store.displayItems.count, 3)
    }

    @MainActor
    func testRefreshAvailableRelayHostsUsesKmpEngineAndReconcilesOfflineRecovery() async throws {
        let hostUuid = "probe-kmp-macbook-v2"
        let engine = ProbeStateToggleKmpEngineDouble(hostUuid: hostUuid)
        let store = AntigravitySessionStore.makeLiveStore(kmpEngine: engine)
        defer { store.suspendNetworkingForBackground() }
        store.isVerificationMode = false
        store.isNetworkingSuspended = false
        store.isDeviceNetworkReachable = true
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.activeHost = RemoteHostInstance(
            instanceId: hostUuid,
            hostname: "MacBook Pro",
            version: "2.34.0",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(hostUuid)")!,
            isOnline: true
        )
        store.hosts = [store.activeHost]
        store.selectedHostScope = .localHost(id: hostUuid, name: "MacBook Pro")

        // 1. Host goes offline -> refreshAvailableRelayHosts routes through kmpEngine with verifyEndToEnd=true
        //    and flips BOTH activeHost.isOnline AND isLiveBackendConnected to false.
        await engine.setOnline(false)
        await store.refreshAvailableRelayHosts(verifyEndToEnd: true)
        let verifyFlag1 = await engine.lastVerifyEndToEnd
        XCTAssertEqual(verifyFlag1, true)
        XCTAssertFalse(store.activeHost.isOnline)
        XCTAssertFalse(store.isLiveBackendConnected)
        XCTAssertEqual(store.connectionStatusText, "Offline · MacBook Pro")

        // 2. Host comes back online -> refreshAvailableRelayHosts flips BOTH activeHost.isOnline AND
        //    isLiveBackendConnected back to true so Settings Hero Card and Available Hosts stay in sync.
        await engine.setOnline(true)
        await store.refreshAvailableRelayHosts(verifyEndToEnd: true)
        let probeCalls = await engine.probeCallCount
        XCTAssertEqual(probeCalls, 2)
        XCTAssertTrue(store.activeHost.isOnline)
        XCTAssertTrue(store.isLiveBackendConnected)
        XCTAssertTrue(store.connectionStatusText.hasPrefix("Connected · MacBook Pro"))
    }

    @MainActor
    func testKmpSendFailureAvoidsDoubleFormattingMigratesRecoveredIdAndRetriesCleanly() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ag-send-retry-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let projectionStore = LocalProjectionStore(storageDirectory: tempRoot)

        let engine = SendRecoveryKmpEngineDouble()
        let store = AntigravitySessionStore.makeLiveStore(
            projectionStore: projectionStore,
            secretStore: InMemorySecretStore(),
            preferencesStore: InMemoryPreferencesStore(),
            kmpEngine: engine
        )
        _ = await store.connectCloudRelay(
            relayURLString: "https://antigravity.google.com/r/host-recovery",
            sessionCookie: "SAPISID=test; SID=test",
            hostName: "MacBook Pro"
        )

        let originalId = "v1/evicted-cloud-session"
        store.summaries = [
            CascadeSummary(
                cascadeId: originalId,
                title: "介绍下这个仓库",
                projectSlug: "slardar_app_ai",
                workspaceUri: "cloud://slardar_app_ai",
                branchName: "feat/support_slardar_pc",
                status: .done,
                stepCount: 1,
                isCloud: true,
                cloudProjectId: "cp-slardar",
                originHostName: "Antigravity"
            )
        ]
        store.stepsByCascadeId[originalId] = [
            CascadeStep(cascadeId: originalId, stepIndex: 0, type: .userInput, status: .done, userInput: "介绍下这个仓库")
        ]
        store.activeCascadeId = originalId
        store.activeRoute = .cascadeChat(originalId)

        // 1. First send fails via KMP outcome with formatted user-facing message -> MUST NOT get wrapped in "HTTP 500:"
        await engine.setNextResult(
            KmpSendMessageResult(
                resolvedCascadeId: originalId,
                dispatchedLive: false,
                queuedInOutbox: false,
                errorMessage: "This conversation was not found on this host (session not found). Tap Retry or start a new chat."
            )
        )
        store.composerDraftText = "Who is the most violent"
        store.sendCurrentDraft()

        for _ in 0..<40 {
            if store.stepLoadErrorText != nil { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let errText = try XCTUnwrap(store.stepLoadErrorText)
        XCTAssertTrue(errText.contains("This conversation was not found on this host (session not found)"))
        XCTAssertFalse(errText.contains("HTTP 500"), "Pre-formatted KMP send error must never be double-wrapped with HTTP 500: \(errText)")
        XCTAssertNotNil(store.activeFailedSend)

        // 2. User starts typing a new draft, then taps Retry; KMP recovers with a fresh server cascadeId
        let recoveredId = "v1/recovered-cloud-session-2"
        await engine.setNextResult(
            KmpSendMessageResult(
                resolvedCascadeId: recoveredId,
                dispatchedLive: true,
                queuedInOutbox: false
            )
        )
        store.composerDraftText = "Keep my draft!"
        store.retryLastFailedSend()

        // Preserves user's unrelated composer draft immediately
        XCTAssertEqual(store.composerDraftText, "Keep my draft!")

        for _ in 0..<40 {
            if store.activeCascadeId == recoveredId { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(store.activeCascadeId, recoveredId, "Non-optimistic recovered cascadeId must migrate activeCascadeId")
        XCTAssertEqual(store.activeRoute, .cascadeChat(recoveredId))
        XCTAssertTrue(store.summaries.contains(where: { $0.cascadeId == recoveredId }))
        XCTAssertNil(store.stepLoadErrorText)
        XCTAssertNil(store.activeFailedSend)
        let migratedSteps = store.stepsByCascadeId[recoveredId] ?? []
        XCTAssertEqual(
            migratedSteps.filter { $0.userInput == "Who is the most violent" }.count,
            1,
            "Retrying a failed send must not duplicate the user bubble"
        )
    }

    @MainActor
    func testColdStartWithAttachedKmpEngineDoesNotReturnFakeEmptyStepsBeforeHandshake() async throws {
        let engine = RecordingKmpEngineDouble()
        let store = AntigravitySessionStore.makeLiveStore(kmpEngine: engine)
        defer { store.suspendNetworkingForBackground() }

        let cloudId = "v1/default/jetski_remote_agents_3p_devbox/xcode-signing"
        store.summaries = [
            CascadeSummary(
                cascadeId: cloudId,
                title: "Xcode签名丢失原因分析",
                projectSlug: "venciallee/PocketAntigravity",
                workspaceUri: "cloud://venciallee/PocketAntigravity",
                branchName: "main",
                status: .done,
                stepCount: 5,
                currentStepIndex: 5,
                totalSteps: 5,
                updatedAt: Date(),
                relativeTimeLabel: "5m",
                statusSubtitle: "Done · 5 steps",
                isCloud: true,
                originHostName: "Antigravity",
                hasResolvedTitle: true
            )
        ]

        // 1. Pre-handshake connecting state with kmpEngine attached (just like AntigravityApp cold launch):
        // must keep `isLoadingSteps == true` and NOT invoke `kmpEngine.syncSteps` before handshake finishes.
        store.hasPairedBackend = true
        store.isLiveBackendConnected = false
        store.isConnectingToBackend = true
        store.connectionLifecyclePhase = .connecting
        store.selectCascade(cloudId)
        try? await Task.sleep(nanoseconds: 80_000_000)

        let callsDuringConnect = await engine.syncStepsCalls.count
        XCTAssertEqual(callsDuringConnect, 0, "Pre-handshake cold start must not call kmpEngine.syncSteps while activeClient is nil")
        XCTAssertTrue(store.isLoadingSteps, "Uncached Cloud conversation must remain in loading state while connecting")
        XCTAssertNil(store.stepLoadErrorText)

        // 2. Once connecting settles to offline (all Desktop Relay hosts offline), opening uncached Cloud chat
        // must surface an explicit offline error instead of clearing loading into a silent blank screen.
        store.isConnectingToBackend = false
        store.connectionLifecyclePhase = .offlineBackoff(attempt: 1, nextRetrySeconds: 5)
        store.syncStepsForCascade(cloudId, pollUntilIdle: true, forceRefresh: true)
        for _ in 0..<40 where store.stepLoadErrorText == nil {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(store.isLoadingSteps)
        XCTAssertTrue(
            store.stepLoadErrorText?.lowercased().contains("offline") == true,
            "Uncached Cloud conversation while all hosts are offline must show offline guidance, got: \(String(describing: store.stepLoadErrorText))"
        )
    }

    @MainActor
    func testKmpIncrementalDeltaSyncAndLiveChatUpdateStatusReconciliation() async throws {
        let cid = "kmp-ios-delta-live-1"
        let baseDate = Date(timeIntervalSince1970: 1_740_000_000)
        let cachedSteps: [CascadeStep] = [
            CascadeStep(
                cascadeId: cid,
                stepIndex: 0,
                type: .userInput,
                status: .done,
                createdAt: baseDate,
                userInput: "Question 0"
            ),
            CascadeStep(
                cascadeId: cid,
                stepIndex: 1,
                type: .plannerResponse,
                status: .done,
                createdAt: baseDate.addingTimeInterval(2),
                plannerResponse: PlannerResponsePayload(response: "Answer 1")
            ),
            CascadeStep(
                cascadeId: cid,
                stepIndex: 2,
                type: .userInput,
                status: .done,
                createdAt: baseDate.addingTimeInterval(4),
                userInput: "Follow up 2"
            )
        ]
        let deltaTail: [CascadeStep] = [
            cachedSteps[2],
            CascadeStep(
                cascadeId: cid,
                stepIndex: 3,
                type: .plannerResponse,
                status: .done,
                createdAt: baseDate.addingTimeInterval(6),
                plannerResponse: PlannerResponsePayload(response: "Delta Answer 3")
            )
        ]

        let engine = DeltaAndLiveStreamKmpEngineDouble(deltaToReturn: deltaTail)
        let store = AntigravitySessionStore.makeLiveStore(kmpEngine: engine)
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.isDeviceNetworkReachable = true
        let host = RemoteHostInstance(
            instanceId: "mac-delta-1",
            hostname: "MacBook Pro",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:42421")!,
            isOnline: true
        )
        store.activeHost = host
        store.hosts = [host]
        store.summaries = [
            CascadeSummary(
                cascadeId: cid,
                title: "Question 0",
                projectSlug: "app",
                workspaceUri: "file:///Users/dev/app",
                status: .inProgress,
                stepCount: 4,
                updatedAt: baseDate.addingTimeInterval(6),
                originInstanceUuid: "mac-delta-1",
                originHostName: "MacBook Pro"
            )
        ]
        store.stepsByCascadeId[cid] = cachedSteps
        store.activeCascadeId = cid

        // 1. Syncing with cached 3 steps must use fetchBinaryStepDelta(startIndex: 2) and skip full syncSteps!
        store.syncStepsForCascade(cid, pollUntilIdle: false)
        for _ in 0..<40 {
            if (store.stepsByCascadeId[cid]?.count ?? 0) == 4 { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        let deltaOffsets = await engine.deltaStartIndices
        let fullCalls = await engine.fullSyncCalls
        XCTAssertEqual(deltaOffsets, [2], "Cold-start incremental sync must request delta starting at anchor stepIndex 2")
        XCTAssertEqual(fullCalls, 0, "Successful incremental delta must avoid full syncSteps reload")
        XCTAssertEqual(store.stepsByCascadeId[cid]?.count, 4)
        XCTAssertEqual(store.stepsByCascadeId[cid]?.last?.plannerResponse?.response, "Delta Answer 3")

        // 2. Real-time KmpLiveChatUpdate preserves cached prefix on tail slice and updates live runStatus immediately
        let tailSliceUpdate = KmpLiveChatUpdate(
            cascadeId: cid,
            steps: [
                CascadeStep(
                    cascadeId: cid,
                    stepIndex: 4,
                    type: .plannerResponse,
                    status: .inProgress,
                    createdAt: baseDate.addingTimeInterval(8),
                    plannerResponse: PlannerResponsePayload(response: "Streaming token...")
                )
            ],
            totalLength: 5,
            runStatus: "CASCADE_RUN_STATUS_RUNNING",
            isSnapshotComplete: false
        )
        store.applyKmpLiveChatUpdate(tailSliceUpdate)
        XCTAssertEqual(store.stepsByCascadeId[cid]?.count, 5, "Tail slice must merge onto cached prefix without dropping steps 0..3")
        XCTAssertEqual(store.stepsByCascadeId[cid]?.first?.userInput, "Question 0")
        XCTAssertEqual(store.stepsByCascadeId[cid]?.last?.plannerResponse?.response, "Streaming token...")
        XCTAssertEqual(store.summaries.first(where: { $0.cascadeId == cid })?.status, .inProgress)
        XCTAssertFalse(store.isLoadingSteps)
    }
}

private actor DeltaAndLiveStreamKmpEngineDouble: AntigravityKmpEnginePort {
    nonisolated var engineName: String { "DeltaAndLiveStreamKmpEngineDouble" }
    let deltaToReturn: [CascadeStep]
    var deltaStartIndices: [Int] = []
    var fullSyncCalls: Int = 0

    init(deltaToReturn: [CascadeStep]) {
        self.deltaToReturn = deltaToReturn
    }

    func connectDirectLan(endpointURLString: String, csrfToken: String, certSHA256: String?, hostName: String, isRestoringSavedSession: Bool) async throws -> BackendHandshakeResult {
        throw AntigravityRPCError.invalidEndpoint
    }
    func connectCloudRelay(relayURLString: String, sessionCookie: String, authUser: String?, resolvedInstanceUuid: String?, relayApiKey: String?, hostName: String, isRestoringSavedSession: Bool, strictTargetMatch: Bool) async throws -> BackendHandshakeResult {
        throw AntigravityRPCError.invalidEndpoint
    }
    func probeHostReachability(allowCrossHostFallback: Bool) async throws -> HostReachabilityProbeResult {
        HostReachabilityProbeResult(latencyMs: 5, availableRelayInstances: [], activeRelayInstance: nil, isSelectedHostOnline: true)
    }
    func refreshWorkspacesAndSummaries(hostScope: AgentsHostFilterScope, skipRelayListRefresh: Bool) async throws -> KmpFederatedSyncResult {
        KmpFederatedSyncResult(workspaces: [], summaries: [])
    }
    func syncSteps(cascadeId: String, knownStepCount: Int, isCloud: Bool, instanceUuidOverride: String?) async throws -> [CascadeStep] {
        fullSyncCalls += 1
        return []
    }
    func fetchBinaryStepDelta(cascadeId: String, startIndex: Int, knownStepCount: Int, instanceUuidOverride: String?) async throws -> [CascadeStep] {
        deltaStartIndices.append(startIndex)
        return deltaToReturn
    }
    func startConversation(workspaceUri: String, initialPrompt: String, modelId: String, cloudProjectId: String?, isCloud: Bool, instanceUuidOverride: String?) async throws -> String { "" }
    func sendMessage(cascadeId: String, message: String, workspaceUri: String, attachments: [ComposerAttachmentChip], modelId: String, effort: ThinkingEffortLevel, mode: CascadeExecutionMode, agentPersona: String, isCloud: Bool, cloudProjectId: String?, permissionPreset: AgentPermissionPreset?, instanceUuidOverride: String?, isOptimisticDraft: Bool) async throws -> KmpSendMessageResult {
        KmpSendMessageResult(resolvedCascadeId: cascadeId, dispatchedLive: true, queuedInOutbox: false)
    }
    func resolveWaitingInteraction(step: CascadeStep, decision: InteractionDecision, workspaceUri: String?, instanceUuidOverride: String?) async throws -> CascadeUserInteractionPayload {
        throw AntigravityRPCError.interactionRejected
    }
    func cancelActiveTurn(cascadeId: String, instanceUuidOverride: String?) async throws {}
    func replayPendingOutbox(modelId: String, effort: ThinkingEffortLevel, mode: CascadeExecutionMode) async -> Int { 0 }
    func switchToRelayInstance(_ instance: RelayInstanceInfo) async {}
    nonisolated func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> { AsyncStream { _ in } }
    nonisolated func onBackground() {}
    func onForeground() async {}
    func disconnectAndClearCredentials() async {}
}

private actor UnregisteredRelayKmpEngineDouble: AntigravityKmpEnginePort {
    nonisolated var engineName: String { "UnregisteredRelayKmpEngineDouble" }
    nonisolated var lastHandshakeDiagnostic: String { "engine=UnregisteredRelayKmpEngineDouble" }

    let hostUuid: String
    var startConversationCalls = 0
    var sendMessageCalls = 0

    init(hostUuid: String) {
        self.hostUuid = hostUuid
    }

    func connectDirectLan(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String?,
        hostName: String,
        isRestoringSavedSession: Bool
    ) async throws -> BackendHandshakeResult {
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
            latencyMs: 120,
            workspaces: [],
            summaries: [],
            resolvedHostname: hostUuid,
            resolvedInstanceUuid: hostUuid,
            availableRelayInstances: [
                RelayInstanceInfo(uuid: hostUuid, name: hostUuid, status: .disconnected)
            ],
            isSelectedHostOnline: false,
            succeededInstanceUuids: [],
            initialSyncCompleted: false
        )
    }

    func probeHostReachability(allowCrossHostFallback: Bool) async throws -> HostReachabilityProbeResult {
        try await probeHostReachability(allowCrossHostFallback: allowCrossHostFallback, verifyEndToEnd: false)
    }

    func probeHostReachability(allowCrossHostFallback: Bool, verifyEndToEnd: Bool) async throws -> HostReachabilityProbeResult {
        let offlineInst = RelayInstanceInfo(uuid: hostUuid, name: hostUuid, status: .disconnected)
        return HostReachabilityProbeResult(
            latencyMs: 90,
            availableRelayInstances: [offlineInst],
            activeRelayInstance: offlineInst,
            isSelectedHostOnline: false
        )
    }

    func refreshWorkspacesAndSummaries(
        hostScope: AgentsHostFilterScope,
        skipRelayListRefresh: Bool
    ) async throws -> KmpFederatedSyncResult {
        throw AntigravityRPCError.httpError(
            statusCode: 400,
            body: """
            [9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo","INSTANCE_NOT_REGISTERED"]]]
            """
        )
    }

    func syncSteps(cascadeId: String, knownStepCount: Int, isCloud: Bool, instanceUuidOverride: String?) async throws -> [CascadeStep] {
        []
    }

    func startConversation(
        workspaceUri: String,
        initialPrompt: String,
        modelId: String,
        cloudProjectId: String?,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> String {
        startConversationCalls += 1
        throw AntigravityRPCError.httpError(statusCode: 400, body: """
        [9,"instance not registered"]
        """)
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
        sendMessageCalls += 1
        return KmpSendMessageResult(
            resolvedCascadeId: cascadeId,
            dispatchedLive: false,
            queuedInOutbox: true,
            errorMessage: "Desktop instance is offline or no longer registered with Cloud Relay.",
            hostOfflineDetected: true
        )
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
    nonisolated func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> { AsyncStream { $0.finish() } }
    nonisolated func onBackground() {}
    func onForeground() async {}
    func disconnectAndClearCredentials() async {}
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

private actor PreloadTestingKmpEngineDouble: AntigravityKmpEnginePort {
    nonisolated var engineName: String { "PreloadTestingKmpEngineDouble" }
    nonisolated var lastHandshakeDiagnostic: String { "engine=PreloadTestingKmpEngineDouble" }

    let unhydratedCascadeId: String
    var preloadCalls: [String] = []

    init(unhydratedCascadeId: String) {
        self.unhydratedCascadeId = unhydratedCascadeId
    }

    func connectDirectLan(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String?,
        hostName: String,
        isRestoringSavedSession: Bool
    ) async throws -> BackendHandshakeResult {
        BackendHandshakeResult(
            latencyMs: 12,
            workspaces: [
                WorkspaceInfo(
                    workspaceUri: "file:///Users/dev/slardar_app_ai",
                    displayName: "slardar_app_ai",
                    activeBranch: "main"
                )
            ],
            summaries: [
                CascadeSummary(
                    cascadeId: unhydratedCascadeId,
                    title: "New Conversation",
                    projectSlug: "slardar_app_ai",
                    workspaceUri: "file:///Users/dev/slardar_app_ai",
                    status: .done,
                    stepCount: 2,
                    hasResolvedTitle: false
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
        [
            CascadeStep(
                cascadeId: cascadeId,
                stepIndex: 0,
                type: .userInput,
                status: .done,
                userInput: "Fix Slardar startup tracing"
            ),
            CascadeStep(
                cascadeId: cascadeId,
                stepIndex: 1,
                type: .plannerResponse,
                status: .done,
                plannerResponse: PlannerResponsePayload(response: "Tracing optimized and cached.")
            )
        ]
    }

    func preloadSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?,
        requireRemoteRefresh: Bool
    ) async throws -> [CascadeStep] {
        preloadCalls.append(cascadeId)
        return try await syncSteps(
            cascadeId: cascadeId,
            knownStepCount: knownStepCount,
            isCloud: isCloud,
            instanceUuidOverride: instanceUuidOverride
        )
    }

    func startConversation(
        workspaceUri: String,
        initialPrompt: String,
        modelId: String,
        cloudProjectId: String?,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> String { "cid-preload-created" }

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
    nonisolated func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> {
        AsyncStream { $0.finish() }
    }
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

private actor SlowStepKmpEngineDouble: AntigravityKmpEnginePort {
    nonisolated var engineName: String { "SlowStepKmpEngineDouble" }
    nonisolated var lastHandshakeDiagnostic: String { "engine=SlowStepKmpEngineDouble" }

    var syncStepsCalls: [String] = []
    var forceSyncStepsCalls: [String] = []

    func connectDirectLan(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String?,
        hostName: String,
        isRestoringSavedSession: Bool
    ) async throws -> BackendHandshakeResult {
        BackendHandshakeResult(
            latencyMs: 10,
            workspaces: [WorkspaceInfo(workspaceUri: "file:///Users/dev/code/app", displayName: "app", activeBranch: "main")],
            summaries: [
                CascadeSummary(
                    cascadeId: "kmp-coalesce-1",
                    title: "Settled Idle Chat",
                    projectSlug: "app",
                    workspaceUri: "file:///Users/dev/code/app",
                    status: .done,
                    stepCount: 2,
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    isUnread: false
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
        try? await Task.sleep(nanoseconds: 90_000_000)
        return [
            CascadeStep(cascadeId: cascadeId, stepIndex: 0, type: .userInput, status: .done, userInput: "Hello"),
            CascadeStep(cascadeId: cascadeId, stepIndex: 1, type: .plannerResponse, status: .done, plannerResponse: PlannerResponsePayload(response: "World"))
        ]
    }

    func forceSyncSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep] {
        forceSyncStepsCalls.append(cascadeId)
        return [
            CascadeStep(cascadeId: cascadeId, stepIndex: 0, type: .userInput, status: .done, userInput: "Hello"),
            CascadeStep(cascadeId: cascadeId, stepIndex: 1, type: .plannerResponse, status: .done, plannerResponse: PlannerResponsePayload(response: "Force Refreshed"))
        ]
    }

    func startConversation(
        workspaceUri: String,
        initialPrompt: String,
        modelId: String,
        cloudProjectId: String?,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> String { "cid-coalesce-created" }

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
    nonisolated func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> { AsyncStream { $0.finish() } }
    nonisolated func onBackground() {}
    func onForeground() async {}
    func disconnectAndClearCredentials() async {}
}

private actor ProbeStateToggleKmpEngineDouble: AntigravityKmpEnginePort {
    nonisolated var engineName: String { "ProbeStateToggleKmpEngineDouble" }
    nonisolated var lastHandshakeDiagnostic: String { "engine=ProbeStateToggleKmpEngineDouble" }

    let hostUuid: String
    private var online: Bool = true
    var probeCallCount: Int = 0
    var lastVerifyEndToEnd: Bool? = nil

    init(hostUuid: String) {
        self.hostUuid = hostUuid
    }

    func setOnline(_ value: Bool) {
        online = value
    }

    func connectDirectLan(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String?,
        hostName: String,
        isRestoringSavedSession: Bool
    ) async throws -> BackendHandshakeResult {
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
        throw AntigravityRPCError.invalidEndpoint
    }

    func probeHostReachability(allowCrossHostFallback: Bool) async throws -> HostReachabilityProbeResult {
        try await probeHostReachability(allowCrossHostFallback: allowCrossHostFallback, verifyEndToEnd: false)
    }

    func probeHostReachability(
        allowCrossHostFallback: Bool,
        verifyEndToEnd: Bool
    ) async throws -> HostReachabilityProbeResult {
        probeCallCount += 1
        lastVerifyEndToEnd = verifyEndToEnd
        let inst = RelayInstanceInfo(
            uuid: hostUuid,
            name: "MacBook Pro",
            version: "2.34.0",
            status: online ? .connected : .disconnected
        )
        return HostReachabilityProbeResult(
            latencyMs: 28,
            availableRelayInstances: [inst],
            activeRelayInstance: inst,
            relayTopologyChanged: false,
            relayMetadataChanged: false,
            isSelectedHostOnline: online
        )
    }

    func refreshWorkspacesAndSummaries(
        hostScope: AgentsHostFilterScope,
        skipRelayListRefresh: Bool
    ) async throws -> KmpFederatedSyncResult {
        KmpFederatedSyncResult(workspaces: [], summaries: [])
    }

    func syncSteps(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> [CascadeStep] {
        []
    }

    func startConversation(
        workspaceUri: String,
        initialPrompt: String,
        modelId: String,
        cloudProjectId: String?,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> String {
        "cid-probe-test"
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
    nonisolated func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> { AsyncStream { $0.finish() } }
    nonisolated func onBackground() {}
    func onForeground() async {}
    func disconnectAndClearCredentials() async {}
}

private actor SendRecoveryKmpEngineDouble: AntigravityKmpEnginePort {
    nonisolated var engineName: String { "SendRecoveryKmpEngineDouble" }
    nonisolated var lastHandshakeDiagnostic: String { "engine=SendRecoveryKmpEngineDouble" }

    private var nextResult: KmpSendMessageResult?

    func setNextResult(_ result: KmpSendMessageResult) {
        self.nextResult = result
    }

    func connectDirectLan(
        endpointURLString: String,
        csrfToken: String,
        certSHA256: String?,
        hostName: String,
        isRestoringSavedSession: Bool
    ) async throws -> BackendHandshakeResult {
        BackendHandshakeResult(latencyMs: 10, workspaces: [], summaries: [], isSelectedHostOnline: true)
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
            latencyMs: 10,
            workspaces: [],
            summaries: [],
            resolvedHostname: hostName,
            resolvedInstanceUuid: "host-recovery",
            availableRelayInstances: [
                RelayInstanceInfo(uuid: "host-recovery", name: hostName, status: .connected)
            ],
            isSelectedHostOnline: true,
            succeededInstanceUuids: ["host-recovery"],
            initialSyncCompleted: true
        )
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
        []
    }

    func startConversation(
        workspaceUri: String,
        initialPrompt: String,
        modelId: String,
        cloudProjectId: String?,
        isCloud: Bool,
        instanceUuidOverride: String?
    ) async throws -> String {
        "v1/start-created"
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
        if let configured = nextResult {
            return configured
        }
        return KmpSendMessageResult(resolvedCascadeId: cascadeId, dispatchedLive: true, queuedInOutbox: false)
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
    nonisolated func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> { AsyncStream { _ in } }
    nonisolated func onBackground() {}
    func onForeground() async {}
    func disconnectAndClearCredentials() async {}
}
