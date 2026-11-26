import XCTest
@testable import AntigravityData

final class UserGreetingTests: XCTestCase {

    func testUserGreetingFormatterNormalizationAndFallbacks() {
        // Full names collapse to given name; single-word / CJK / short initials stay clean
        XCTAssertEqual(UserGreetingFormatter.formatGreetingName("Vencial Lee"), "Vencial")
        XCTAssertEqual(UserGreetingFormatter.formatGreetingName("Venciallee"), "Venciallee")
        XCTAssertEqual(UserGreetingFormatter.formatGreetingName("李明"), "李明")
        XCTAssertEqual(UserGreetingFormatter.formatGreetingName("J. Smith"), "J. Smith")

        // Email fallback extracts readable handle and rejects numeric-only addresses
        XCTAssertEqual(
            UserGreetingFormatter.formatGreetingName(nil, fallbackEmail: "venciallee@gmail.com"),
            "Venciallee"
        )
        XCTAssertEqual(
            UserGreetingFormatter.formatGreetingName("", fallbackEmail: "alex.chen+work@company.com"),
            "Alex"
        )
        XCTAssertNil(UserGreetingFormatter.formatGreetingName(nil, fallbackEmail: "12345678@qq.com"))

        // Rejects generic placeholders and raw UUIDs
        XCTAssertNil(UserGreetingFormatter.formatGreetingName("unknown"))
        XCTAssertNil(UserGreetingFormatter.formatGreetingName("Anonymous"))
        XCTAssertNil(UserGreetingFormatter.formatGreetingName("0f5819ac-9308-40d8-a308-98b55122c533"))

        // Greeting copy renders real name when present, or clean nameless fallback
        XCTAssertEqual(
            UserGreetingFormatter.homeHeroGreeting(displayName: "Vencial Lee"),
            "Welcome back,\nVencial. Where\nshould we pick up?"
        )
        XCTAssertEqual(
            UserGreetingFormatter.homeHeroGreeting(displayName: nil),
            "Welcome back.\nWhere should\nwe pick up?"
        )
        XCTAssertEqual(
            UserGreetingFormatter.compactBackdropGreeting(displayName: "Vencial Lee"),
            "Welcome back, Vencial."
        )
        XCTAssertEqual(
            UserGreetingFormatter.compactBackdropGreeting(displayName: nil),
            "Welcome back."
        )
        XCTAssertEqual(
            UserGreetingFormatter.addContextBackdropGreeting(displayName: nil),
            "Welcome back.\nWhere should we pick\nup?"
        )
        // Chinese greeting copy renders real name when present, or clean nameless fallback
        XCTAssertEqual(
            UserGreetingFormatter.homeHeroGreeting(displayName: "Vencial Lee", language: .zhHans),
            "欢迎回来，\nVencial。\n今天从哪里开始？"
        )
        XCTAssertEqual(
            UserGreetingFormatter.homeHeroGreeting(displayName: nil, language: .zhHans),
            "欢迎回来。\n今天从哪里\n开始？"
        )
        XCTAssertEqual(
            UserGreetingFormatter.compactBackdropGreeting(displayName: "Vencial Lee", language: .zhHans),
            "欢迎回来，Vencial。"
        )
        XCTAssertEqual(
            UserGreetingFormatter.compactBackdropGreeting(displayName: nil, language: .zhHans),
            "欢迎回来。"
        )
        XCTAssertEqual(
            UserGreetingFormatter.addContextBackdropGreeting(displayName: nil, language: .zhHans),
            "欢迎回来。\n今天从哪里开始？"
        )
    }

    func testParseUserProfileResponseSupportsMultipleSchemas() {
        let camelPayload: [String: JSONValue] = [
            "userStatus": .object([
                "name": .string("Vencial Lee"),
                "email": .string("venciallee@gmail.com"),
                "userTier": .object(["name": .string("Google AI Ultra")])
            ])
        ]
        let parsed = AntigravityRPCClient.parseUserProfileResponse(camelPayload)
        XCTAssertEqual(parsed?.displayName, "Vencial")
        XCTAssertEqual(parsed?.email, "venciallee@gmail.com")
        XCTAssertEqual(parsed?.planDisplayName, "Google AI Ultra")

        let emailOnlyPayload: [String: JSONValue] = [
            "user_status": .object([
                "email": .string("jane.doe@example.com")
            ])
        ]
        let emailParsed = AntigravityRPCClient.parseUserProfileResponse(emailOnlyPayload)
        XCTAssertEqual(emailParsed?.displayName, "Jane")

        let emptyPayload: [String: JSONValue] = [:]
        XCTAssertNil(AntigravityRPCClient.parseUserProfileResponse(emptyPayload))
    }

    @MainActor
    func testLiveStoreNeverShowsMockAlexAndHydratesPersistedName() async {
        let prefs = InMemoryPreferencesStore()
        let liveStore = AntigravitySessionStore.makeLiveStore(
            secretStore: InMemorySecretStore(),
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(),
            preferencesStore: prefs
        )

        // Fresh live store must NEVER display mock "Alex"
        XCTAssertNil(liveStore.userDisplayName)
        XCTAssertFalse(liveStore.homeHeroGreetingText.contains("Alex"))
        XCTAssertEqual(liveStore.homeHeroGreetingText, "Welcome back.\nWhere should\nwe pick up?")

        // Refreshing via KMP engine populates real name and persists it
        let mockEngine = StubUserProfileKmpEngine(returnedName: "Vencial Lee")
        liveStore.kmpEngine = mockEngine
        liveStore.hasPairedBackend = true
        await liveStore.refreshUserProfile()

        XCTAssertEqual(liveStore.userDisplayName, "Vencial")
        XCTAssertEqual(liveStore.homeHeroGreetingText, "Welcome back,\nVencial. Where\nshould we pick up?")
        XCTAssertFalse(liveStore.homeHeroGreetingText.contains("Alex"))

        // Switching app language updates hero greeting immediately
        liveStore.setAppLanguage(.zhHans)
        XCTAssertEqual(liveStore.homeHeroGreetingText, "欢迎回来，\nVencial。\n今天从哪里开始？")
        liveStore.setAppLanguage(.english)
        XCTAssertEqual(liveStore.homeHeroGreetingText, "Welcome back,\nVencial. Where\nshould we pick up?")

        // Cold-starting a new live store immediately restores the cached real name
        let restarted = AntigravitySessionStore.makeLiveStore(
            secretStore: InMemorySecretStore(),
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(),
            preferencesStore: prefs
        )
        XCTAssertEqual(restarted.userDisplayName, "Vencial")
        XCTAssertEqual(restarted.homeHeroGreetingText, "Welcome back,\nVencial. Where\nshould we pick up?")

        // Disconnect clears cached name cleanly
        await liveStore.disconnectBackendAndClearKeychain()
        XCTAssertNil(liveStore.userDisplayName)
        XCTAssertEqual(liveStore.homeHeroGreetingText, "Welcome back.\nWhere should\nwe pick up?")

        // ESDD verification store keeps deterministic "Alex" fixture
        let verifyStore = AntigravitySessionStore.makeESDDVerificationStore()
        XCTAssertEqual(verifyStore.homeHeroGreetingText, "Welcome back,\nAlex. Where\nshould we pick up?")
    }
}

private final class StubUserProfileKmpEngine: AntigravityKmpEnginePort, @unchecked Sendable {
    let returnedName: String?
    init(returnedName: String?) { self.returnedName = returnedName }

    var engineName: String { "StubKmp" }
    func connectDirectLan(endpointURLString: String, csrfToken: String, certSHA256: String?, hostName: String, isRestoringSavedSession: Bool) async throws -> BackendHandshakeResult { throw AntigravityRPCError.invalidEndpoint }
    func connectCloudRelay(relayURLString: String, sessionCookie: String, authUser: String?, resolvedInstanceUuid: String?, relayApiKey: String?, hostName: String, isRestoringSavedSession: Bool, strictTargetMatch: Bool) async throws -> BackendHandshakeResult { throw AntigravityRPCError.invalidEndpoint }
    func probeHostReachability(allowCrossHostFallback: Bool) async throws -> HostReachabilityProbeResult { throw AntigravityRPCError.invalidEndpoint }
    func refreshWorkspacesAndSummaries(hostScope: AgentsHostFilterScope, skipRelayListRefresh: Bool) async throws -> KmpFederatedSyncResult { KmpFederatedSyncResult(workspaces: [], summaries: []) }
    func syncSteps(cascadeId: String, knownStepCount: Int, isCloud: Bool, instanceUuidOverride: String?) async throws -> [CascadeStep] { [] }
    func startConversation(workspaceUri: String, initialPrompt: String, modelId: String, cloudProjectId: String?, isCloud: Bool, instanceUuidOverride: String?) async throws -> String { "" }
    func sendMessage(cascadeId: String, message: String, workspaceUri: String, attachments: [ComposerAttachmentChip], modelId: String, effort: ThinkingEffortLevel, mode: CascadeExecutionMode, agentPersona: String, isCloud: Bool, cloudProjectId: String?, permissionPreset: AgentPermissionPreset?, instanceUuidOverride: String?, isOptimisticDraft: Bool) async throws -> KmpSendMessageResult { KmpSendMessageResult(resolvedCascadeId: cascadeId, dispatchedLive: false, queuedInOutbox: false) }
    func resolveWaitingInteraction(step: CascadeStep, decision: InteractionDecision, workspaceUri: String?, instanceUuidOverride: String?) async throws -> CascadeUserInteractionPayload { throw AntigravityRPCError.interactionRejected }
    func cancelActiveTurn(cascadeId: String, instanceUuidOverride: String?) async throws {}
    func replayPendingOutbox(modelId: String, effort: ThinkingEffortLevel, mode: CascadeExecutionMode) async -> Int { 0 }
    func switchToRelayInstance(_ instance: RelayInstanceInfo) async {}
    func summaryUpdatesStream() -> AsyncStream<[CascadeSummary]> { AsyncStream { $0.finish() } }
    func onBackground() {}
    func onForeground() async {}
    func disconnectAndClearCredentials() async {}
    func fetchUserDisplayName() async -> String? { returnedName }
}
