import Foundation
import XCTest
@testable import AntigravityData

final class AntigravityProtocolTests: XCTestCase {

    func testConnectEnvelopeRoundTripAndChunkedStreamParsing() {
        let message1 = Data("{\"stepIndex\":1,\"status\":\"RUNNING\"}".utf8)
        let message2 = Data("{\"stepIndex\":2,\"status\":\"WAITING\"}".utf8)

        let frame1 = ConnectEnvelope.encode(payload: message1, flags: [])
        let frame2 = ConnectEnvelope.encode(payload: message2, flags: [.endStream])

        var combined = Data()
        combined.append(frame1)
        combined.append(frame2)

        var parser = ConnectStreamParser()
        let firstHalf = combined.prefix(7)
        let secondHalf = combined.dropFirst(7)

        let partial = parser.feed(Data(firstHalf))
        XCTAssertTrue(partial.isEmpty, "Partial frame should wait for remaining bytes")

        let decodedFrames = parser.feed(Data(secondHalf))
        XCTAssertEqual(decodedFrames.count, 2)
        XCTAssertEqual(decodedFrames[0].payload, message1)
        XCTAssertFalse(decodedFrames[0].isEndStream)
        XCTAssertEqual(decodedFrames[1].payload, message2)
        XCTAssertTrue(decodedFrames[1].isEndStream)
    }

    func testProtobufStepRequestEncodingAndJSONValueCodable() throws {
        let encodedReq = ProtobufStepCodec.encodeGetStepsRequest(
            cascadeId: "cas-rate-limiter",
            startIndex: 0,
            endIndex: 750
        )
        XCTAssertEqual(encodedReq.first, 0x0A)
        XCTAssertGreaterThan(encodedReq.count, 18)

        let sample: [String: JSONValue] = [
            "cascadeId": .string("cas-rate-limiter"),
            "stepCount": .int(28),
            "thinkingDurationSeconds": .double(14.5),
            "verified": .bool(true),
            "tags": .array([.string("go"), .string("ratelimit")])
        ]
        let raw = try JSONEncoder().encode(sample)
        let roundTrip = try JSONDecoder().decode([String: JSONValue].self, from: raw)
        XCTAssertEqual(roundTrip, sample)
        XCTAssertEqual(roundTrip["thinkingDurationSeconds"]?.doubleValue, 14.5)
        XCTAssertEqual(roundTrip["stepCount"]?.doubleValue, 28.0)
    }

    func testInteractionBuilderMatchesRequestedOneofFaceIDAndSafeAutoAccept() throws {
        let cmd = "vegeta attack -rate=2000/s -duration=30s -targets=load/transfers.txt | vegeta report"
        let step = CascadeStep(
            cascadeId: "cas-rate-limiter",
            stepIndex: 5,
            type: .runCommand,
            status: .waiting,
            runCommand: RunCommandPayload(
                commandId: "cmd-vegeta-01",
                commandLine: cmd,
                proposedCommandLine: cmd,
                cwd: "~/code/ledger-svc"
            ),
            requestedInteraction: RequestedInteraction(
                kind: .runCommand,
                runCommand: RunCommandInteractionSpec(
                    proposedCommandLine: cmd,
                    cwd: "~/code/ledger-svc"
                )
            )
        )

        let payload = try XCTUnwrap(
            InteractionBuilder.buildPayload(
                step: step,
                decision: .allowWithFaceID,
                workspaceUri: "file:///Users/wl/code/ledger-svc"
            )
        )
        XCTAssertEqual(payload.cascadeId, "cas-rate-limiter")
        XCTAssertEqual(payload.stepIndex, 5)
        XCTAssertEqual(payload.runCommand?.confirm, true)
        XCTAssertEqual(payload.runCommand?.faceIdVerified, true)
        XCTAssertEqual(payload.runCommand?.proposedCommandLine, cmd)

        XCTAssertTrue(SafeAutoAcceptPolicy.isSafeReadOnlyCommand("git status -s"))
        XCTAssertFalse(SafeAutoAcceptPolicy.isSafeReadOnlyCommand("rm -rf /tmp/build"))
        XCTAssertFalse(SafeAutoAcceptPolicy.isSafeReadOnlyCommand(cmd))
    }

    @MainActor
    func testAgentsHomeDisplayOptionsAndContextMenuMutations() {
        let store = AntigravitySessionStore.makeESDDVerificationStore()

        // UE01 badge counts: Running 2, Needs you 1, Unread 3, Pinned 2
        XCTAssertEqual(store.runningCount, 2)
        XCTAssertEqual(store.needsYouCount, 1)
        XCTAssertEqual(store.unreadCount, 3)
        XCTAssertEqual(store.pinnedSummaries.count, 2)
        XCTAssertEqual(store.unpinnedSummaries(forProject: "ledger-svc").count, 3)

        // UE01 quick filters
        store.quickFilter = .needsYou
        XCTAssertEqual(store.filteredSummaries.count, 1)
        XCTAssertEqual(store.filteredSummaries.first?.cascadeId, "cas-flaky-settlement")

        store.quickFilter = .all
        store.displayOptions.sortBy = .title
        store.displayOptions.newestFirst = false
        store.resetDisplayOptions()
        XCTAssertEqual(store.displayOptions, AgentDisplayOptions())

        // UE02 Mark All as Read
        store.markAllConversationsAsRead()
        XCTAssertEqual(store.unreadCount, 0)

        // UE03 Pin / Unread / Rename / Move / Archive / Delete
        store.togglePinCascade("cas-upgrade-go")
        XCTAssertEqual(store.pinnedSummaries.count, 3)

        store.toggleUnreadCascade("cas-upgrade-go")
        XCTAssertEqual(store.unreadCount, 1)

        store.renameCascade("cas-upgrade-go", newTitle: "Upgrade toolchain to Go 1.25.1")
        XCTAssertEqual(
            store.summaries.first(where: { $0.cascadeId == "cas-upgrade-go" })?.title,
            "Upgrade toolchain to Go 1.25.1"
        )

        store.moveCascade("cas-upgrade-go", toProject: "web-console")
        XCTAssertEqual(
            store.summaries.first(where: { $0.cascadeId == "cas-upgrade-go" })?.projectSlug,
            "web-console"
        )

        store.archiveCascade("cas-upgrade-go")
        XCTAssertTrue(store.summaries.first(where: { $0.cascadeId == "cas-upgrade-go" })?.isArchived == true)

        store.deleteCascade("cas-upgrade-go")
        XCTAssertNil(store.summaries.first(where: { $0.cascadeId == "cas-upgrade-go" }))
    }

    @MainActor
    func testDisplayOptionsDefaultPopoverStateAndPersistence() async {
        // Live store & non-UE02 verification scenes must default the Sort popover to closed
        let freshDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ag-display-opts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: freshDir) }

        let placeholderHost = RemoteHostInstance(
            instanceId: "test-display-options-host",
            hostname: "MacBook Pro",
            channel: .directHost,
            endpointURL: URL(string: "https://127.0.0.1:42100")!,
            isOnline: true
        )
        let projection = LocalProjectionStore(storageDirectory: freshDir)
        let liveStore = AntigravitySessionStore(
            hosts: [placeholderHost],
            activeHost: placeholderHost,
            projectionStore: projection,
            createInitialRPCClient: false
        )
        XCTAssertFalse(liveStore.isSortPopoverPresented)

        let verifyStore = AntigravitySessionStore.makeESDDVerificationStore()
        XCTAssertFalse(verifyStore.isSortPopoverPresented)
        verifyStore.configureForVerifyScene(.displayOptions)
        XCTAssertTrue(verifyStore.isSortPopoverPresented)
        verifyStore.configureForVerifyScene(.agentsHome)
        XCTAssertFalse(verifyStore.isSortPopoverPresented)

        // Updating Display Options on a live store persists asynchronously to LocalProjectionStore
        liveStore.updateDisplayOptions { opts in
            opts.groupBy = .host
            opts.sortBy = .title
            opts.newestFirst = false
            opts.sortProjectsOrder = "Alphabetical"
            opts.filterScopeLabel = "Active only"
            opts.densityLabel = "Compact · Titles only"
            opts.autoPinOnMessage = true
            opts.archivedOnly = true
        }
        XCTAssertEqual(liveStore.displayOptions.groupBy, .host)
        XCTAssertEqual(liveStore.displayOptions.sortBy, .title)
        XCTAssertFalse(liveStore.displayOptions.newestFirst)
        XCTAssertTrue(liveStore.displayOptions.autoPinOnMessage)
        XCTAssertTrue(liveStore.displayOptions.archivedOnly)

        // Wait briefly for the detached save task to flush to disk
        var saved: AgentDisplayOptions?
        for _ in 0..<40 {
            if let loaded = await projection.loadDisplayOptions(), loaded.sortBy == .title {
                saved = loaded
                break
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(saved, liveStore.displayOptions)

        // Hydrating a brand-new store restores persisted Display Options
        let hydratedStore = AntigravitySessionStore(
            hosts: [placeholderHost],
            activeHost: placeholderHost,
            projectionStore: projection,
            createInitialRPCClient: false
        )
        await hydratedStore.loadPersistedV233Preferences()
        XCTAssertEqual(hydratedStore.displayOptions, liveStore.displayOptions)

        // Reset restores defaults and persists back to disk
        hydratedStore.resetDisplayOptions()
        XCTAssertEqual(hydratedStore.displayOptions, AgentDisplayOptions())
        var resetSaved: AgentDisplayOptions?
        for _ in 0..<40 {
            if let loaded = await projection.loadDisplayOptions(), loaded == AgentDisplayOptions() {
                resetSaved = loaded
                break
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(resetSaved, AgentDisplayOptions())
    }

    @MainActor
    func testCreateProjectScopedConversationAndAutomations() {
        let store = AntigravitySessionStore.makeESDDVerificationStore()

        // UE05 Create New Project (Cloud + GitHub acme/ledger-svc -> ledger-svc-cloud)
        let createdProject = store.createNewProject()
        XCTAssertEqual(createdProject.id, "ledger-svc-cloud")
        XCTAssertEqual(createdProject.runtime, .cloud)
        XCTAssertEqual(store.selectedProjectId, "ledger-svc-cloud")
        XCTAssertEqual(store.activeRoute, .tabRoot)

        // New Conversation in Project (direct from sidebar '+' or context menu)
        let convId = store.createConversationInProject("ledger-svc", title: "Verify settlement metrics")
        XCTAssertEqual(store.activeCascadeId, convId)
        XCTAssertEqual(store.activeRoute, .cascadeChat(convId))

        // UE06 Automations: Scheduled 2, Always On 1, Paused 1
        XCTAssertEqual(store.scheduledAutomations.count, 2)
        XCTAssertEqual(store.alwaysOnAutomations.count, 1)
        XCTAssertEqual(store.pausedAutomations.count, 1)

        let createdAuto = store.createAutomationFromPrompt("Every weekday at 9, summarize")
        XCTAssertNotNil(createdAuto)
        XCTAssertEqual(store.scheduledAutomations.count, 3)

        store.triggerAutomationNow("auto-nightly-audit")
        XCTAssertTrue(store.automations.first(where: { $0.id == "auto-nightly-audit" })?.isRunningNow == true)

        store.resumeAutomation("auto-bundle-size")
        XCTAssertEqual(store.pausedAutomations.count, 0)
        XCTAssertEqual(store.scheduledAutomations.count, 4)
    }

    @MainActor
    func testChat7SegmentTaskFaceIDGateAddContextAndModelCatalog() {
        let store = AntigravitySessionStore.makeESDDVerificationStore()

        // UE07 7-Segment Task Checklist + Evidence Grouping + Face ID Gate
        XCTAssertEqual(store.activeTaskBoundary?.completedCount, 4)
        XCTAssertEqual(store.activeTaskBoundary?.totalCount, 7)
        XCTAssertEqual(store.activeTaskBoundary?.elapsedLabel, "2m 41s")
        XCTAssertEqual(store.activeTaskBoundary?.checklist.count, 3)

        let hasEvidenceGroup = store.displayItems.contains { item in
            if case .evidenceGroup(_, let grouped) = item {
                return grouped.count == 2
            }
            return false
        }
        XCTAssertTrue(hasEvidenceGroup)

        // UE08 Add Context (3 selected -> Add to message)
        XCTAssertEqual(store.selectedContextCount, 3)
        store.applySelectedContextToComposer()
        XCTAssertTrue(store.composerAttachments.contains(where: { $0.label == "Skill · go-testing" }))

        // UE09 Model & Persona Catalog
        XCTAssertEqual(CascadeModelConfig.catalog.map(\.displayName), [
            "Gemini 3.1 Pro",
            "Gemini 3.8 Flash",
            "Claude Opus 5.5",
            "Claude Sonnet 5.5"
        ])
        XCTAssertEqual(CascadeModelConfig.availableAgents, ["Default", "go-reviewer", "release-captain"])

        // Approve Step 5 vegeta load test with Face ID
        store.approveWaitingCommandWithFaceID(stepIndex: 5)
        XCTAssertEqual(store.lastDispatchedInteraction?.runCommand?.faceIdVerified, true)
        XCTAssertEqual(store.activeTaskBoundary?.completedCount, 5)
    }

    @MainActor
    func testStructuredQuestionsPlanCommentsAndTurnDiffReview() {
        let store = AntigravitySessionStore.makeESDDVerificationStore()

        // UE10 Multi-Step Structured Question (1 Storage -> 2 Actions -> 3 Retention)
        store.configureForVerifyScene(.structuredQuestion)
        XCTAssertEqual(store.activeQuestionStepIndex, 1)
        XCTAssertEqual(store.currentQuestionStep?.shortTabTitle, "Actions")

        store.previousQuestionStep()
        XCTAssertEqual(store.activeQuestionStepIndex, 0)
        store.advanceQuestionStep()
        XCTAssertEqual(store.activeQuestionStepIndex, 1)
        store.advanceQuestionStep()
        XCTAssertEqual(store.activeQuestionStepIndex, 2)

        // UE11 Implementation Plan Review & Inline Comments
        store.configureForVerifyScene(.planReview)
        XCTAssertEqual(store.planChanges.count, 3)
        XCTAssertEqual(store.planComments.count, 2)
        store.addPlanComment(body: "Ensure NewTestClock registers t.Cleanup automatically.")
        XCTAssertEqual(store.planComments.count, 3)
        store.sendPlanCommentsToAgent()
        XCTAssertTrue(store.planComments.allSatisfy { $0.statusLabel == "Sent" })

        // UE12 Turn Diff Line-Level Review (+128 -14 across 4 files)
        store.configureForVerifyScene(.turnDiffReview)
        XCTAssertEqual(store.totalDiffAdditions, 128)
        XCTAssertEqual(store.totalDiffDeletions, 14)
        XCTAssertEqual(store.activeTurnDiffs.count, 4)
        XCTAssertEqual(store.currentDiffFile?.filePath, "middleware/ratelimit.go")

        store.submitDiffLineComment(sendImmediately: true)
        XCTAssertEqual(store.diffComments.count, 1)
        XCTAssertEqual(store.diffComments.first?.lineNumber, 29)
        XCTAssertEqual(store.diffComments.first?.sentToAgent, true)

        store.toggleDiffFileViewed()
        XCTAssertEqual(store.currentDiffFile?.isReviewed, true)

        store.acceptCurrentDiffFile()
        XCTAssertEqual(store.activeTurnDiffs.count, 3)

        store.revertCurrentDiffFile()
        XCTAssertEqual(store.activeTurnDiffs.count, 2)

        store.acceptAllTurnDiffs()
        XCTAssertTrue(store.activeTurnDiffs.isEmpty)

        // Verify all 13 ESDD scenes configure cleanly
        for scene in ESDDVerifySceneCase.allCases {
            let fresh = AntigravitySessionStore.makeESDDVerificationStore()
            fresh.configureForVerifyScene(scene)
            XCTAssertNotNil(fresh.activeHost)
        }
    }

    func testDesktopLiveTrajectoryStatusUnreadTimestampAndEmptyFilter() throws {
        // 1. Verify all Antigravity Desktop `CASCADE_RUN_STATUS_*` enum strings map accurately
        XCTAssertEqual(CortexStepStatus.from(jsonName: "CASCADE_RUN_STATUS_RUNNING"), .inProgress)
        XCTAssertEqual(CortexStepStatus.from(jsonName: "CASCADE_RUN_STATUS_WAITING_FOR_USER"), .waiting)
        XCTAssertEqual(CortexStepStatus.from(jsonName: "CASCADE_RUN_STATUS_DONE"), .done)
        XCTAssertEqual(CortexStepStatus.from(jsonName: "CASCADE_RUN_STATUS_IDLE"), .unspecified)
        XCTAssertEqual(CortexStepStatus.from(jsonName: "CASCADE_RUN_STATUS_CANCELLED"), .cancelled)

        let refNow = try XCTUnwrap(
            AntigravityRPCClient.parseProtoTimestamp(.string("2026-11-11T09:00:00.000000000Z"))
        )

        // 2. Unused 0-step blank New Chat placeholder -> filtered out (`nil`)
        let blankPlaceholder: JSONValue = .object([
            "stepCount": .int(0),
            "status": .string("CASCADE_RUN_STATUS_IDLE"),
            "workspaces": .array([
                .object(["workspaceFolderAbsoluteUri": .string("file:///Users/dev/slardar_app_ai")])
            ])
        ])
        XCTAssertNil(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "empty-0-step-tab",
                value: blankPlaceholder,
                now: refNow
            )
        )

        // 3. Completed turn with `CASCADE_RUN_STATUS_DONE` & nanosecond RFC3339 timestamp -> Unread = true
        let unreadDoneEntry: JSONValue = .object([
            "summary": .string("Slardar Tag Code Review"),
            "stepCount": .int(18),
            "status": .string("CASCADE_RUN_STATUS_DONE"),
            "lastModifiedTime": .string("2026-11-11T08:47:30.839201442Z"),
            "annotations": .object([
                "lastUserViewTime": .string("2026-11-11T08:30:00.100000Z")
            ]),
            "workspaces": .array([
                .object(["workspaceFolderAbsoluteUri": .string("file:///Users/dev/slardar_app_ai")])
            ])
        ])
        let decodedUnread = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "cid-slardar-code-review",
                value: unreadDoneEntry,
                now: refNow
            )
        )
        XCTAssertEqual(decodedUnread.title, "Slardar Tag Code Review")
        XCTAssertEqual(decodedUnread.projectSlug, "slardar_app_ai")
        XCTAssertEqual(decodedUnread.status, .done)
        XCTAssertTrue(decodedUnread.isUnread)
        XCTAssertEqual(decodedUnread.relativeTimeLabel, "12m")
        XCTAssertEqual(decodedUnread.statusSubtitle, "Done · New reply · 18 steps")

        // 4. Viewed idle session (`CASCADE_RUN_STATUS_IDLE`, `lastModifiedTime <= lastUserViewTime`) -> Unread = false
        let viewedIdleEntry: JSONValue = .object([
            "summary": .string("Slardar App AI 埋点梳理"),
            "stepCount": .int(11),
            "status": .string("CASCADE_RUN_STATUS_IDLE"),
            "lastModifiedTime": .string("2026-11-11T06:55:00Z"),
            "annotations": .object([
                "lastUserViewTime": .string("2026-11-11T07:05:00Z")
            ]),
            "workspaces": .array([
                .object(["workspaceFolderAbsoluteUri": .string("file:///Users/dev/slardar_app_ai")])
            ])
        ])
        let decodedIdle = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "cid-slardar-tracking",
                value: viewedIdleEntry,
                now: refNow
            )
        )
        XCTAssertEqual(decodedIdle.status, .unspecified)
        XCTAssertFalse(decodedIdle.isUnread)
        XCTAssertEqual(decodedIdle.relativeTimeLabel, "2h")
        XCTAssertEqual(decodedIdle.statusSubtitle, "Idle · 11 steps")

        // 5. Synthetic probe session (`iOS Connect-RPC Handshake`) -> filtered out (`nil`)
        let syntheticProbeEntry: JSONValue = .object([
            "summary": .string("Reply in one short sentence confirming iOS Connect-RPC handshake."),
            "stepCount": .int(1),
            "status": .string("CASCADE_RUN_STATUS_DONE"),
            "workspaces": .array([
                .object(["workspaceFolderAbsoluteUri": .string("file:///Users/dev/iOSAntigravity")])
            ])
        ])
        XCTAssertNil(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "cid-probe-handshake",
                value: syntheticProbeEntry,
                now: refNow
            )
        )

        // 6. Cloud project (`cloud://venciallee/iOSAntigravity`) preserves `owner/repo` projectSlug & running status
        let cloudRunningEntry: JSONValue = .object([
            "summary": .string("Antigravity iOS App Architecture Research"),
            "stepCount": .int(7),
            "status": .string("CASCADE_RUN_STATUS_RUNNING"),
            "lastModifiedTime": .string("2026-11-11T08:59:55Z"),
            "workspaces": .array([
                .object(["workspaceFolderAbsoluteUri": .string("cloud://venciallee/iOSAntigravity")])
            ])
        ])
        let decodedCloudRunning = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "cid-arch-research",
                value: cloudRunningEntry,
                now: refNow
            )
        )
        XCTAssertEqual(decodedCloudRunning.projectSlug, "venciallee/iOSAntigravity")
        XCTAssertEqual(decodedCloudRunning.status, .inProgress)
    }

    @MainActor
    func testDesktopStepDecodingAndLiveRouteSelection() throws {
        // 1. UserInput where `userResponse` is empty string "" and `items` carries prompt + file URI
        let rawUserStep: JSONValue = .object([
            "stepIndex": .int(0),
            "type": .string("CORTEX_STEP_TYPE_USER_INPUT"),
            "status": .string("CORTEX_STEP_STATUS_DONE"),
            "userInput": .object([
                "userResponse": .string(""),
                "items": .array([
                    .object(["text": .string("请帮我梳理 Slardar Tag 核心逻辑")]),
                    .object([
                        "item": .object([
                            "file": .object([
                                "absoluteUri": .string("file:///Users/dev/slardar_app_ai/internal/tag/manager.go")
                            ])
                        ])
                    ])
                ])
            ])
        ])
        let userStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(rawUserStep, cascadeId: "cid-1", fallbackIndex: 0)
        )
        XCTAssertEqual(userStep.type, .userInput)
        XCTAssertEqual(userStep.userInput, "请帮我梳理 Slardar Tag 核心逻辑")
        XCTAssertEqual(userStep.attachedMentions, ["@manager.go"])
        XCTAssertTrue(userStep.hasRenderableChatContent)

        // 2. Housekeeping `CORTEX_STEP_TYPE_CHECKPOINT` should be excluded from displayItems
        let rawCheckpoint: JSONValue = .object([
            "stepIndex": .int(1),
            "type": .string("CORTEX_STEP_TYPE_CHECKPOINT"),
            "status": .string("CORTEX_STEP_STATUS_DONE")
        ])
        let checkpointStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(rawCheckpoint, cascadeId: "cid-1", fallbackIndex: 1)
        )
        XCTAssertFalse(checkpointStep.hasRenderableChatContent)

        // 3. PlannerResponse where `modifiedResponse` is "" must NOT shadow `response`
        let rawPlanner: JSONValue = .object([
            "stepIndex": .int(2),
            "type": .string("CORTEX_STEP_TYPE_PLANNER_RESPONSE"),
            "status": .string("CORTEX_STEP_STATUS_DONE"),
            "plannerResponse": .object([
                "modifiedResponse": .string(""),
                "response": .string("已完成梳理：Tag 校验链路位于 RegisterTagValidator。"),
                "thinking": .string("Inspected manager.go and validator registry."),
                "thinkingDuration": .string("6.4s")
            ])
        ])
        let plannerStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(rawPlanner, cascadeId: "cid-1", fallbackIndex: 2)
        )
        XCTAssertEqual(plannerStep.type, .plannerResponse)
        XCTAssertEqual(plannerStep.plannerResponse?.response, "已完成梳理：Tag 校验链路位于 RegisterTagValidator。")
        XCTAssertEqual(plannerStep.plannerResponse?.thinkingDurationSeconds ?? 0, 6.4, accuracy: 0.01)

        // 4. `CORTEX_STEP_TYPE_NOTIFY_USER` renders as assistant message
        let rawNotify: JSONValue = .object([
            "stepIndex": .int(3),
            "type": .string("CORTEX_STEP_TYPE_NOTIFY_USER"),
            "status": .string("CORTEX_STEP_STATUS_DONE"),
            "notifyUser": .object([
                "notificationContent": .string("Implementation plan is ready for review.")
            ])
        ])
        let notifyStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(rawNotify, cascadeId: "cid-1", fallbackIndex: 3)
        )
        XCTAssertEqual(notifyStep.type, .notifyUser)
        XCTAssertTrue(notifyStep.hasRenderableChatContent)

        let items = CascadeDisplayItem.buildDisplayItems(from: [userStep, checkpointStep, plannerStep, notifyStep])
        XCTAssertEqual(items.count, 3, "Housekeeping checkpoint step must be filtered out of displayItems")

        // 5. Selecting a cascade updates activeRoute to .cascadeChat(id) and clears unread badge
        let store = AntigravitySessionStore.makeESDDVerificationStore()
        store.selectCascade("cas-upgrade-go")
        XCTAssertEqual(store.activeRoute, .cascadeChat("cas-upgrade-go"))
        XCTAssertEqual(store.summaries.first(where: { $0.cascadeId == "cas-upgrade-go" })?.isUnread, false)
    }

    @MainActor
    func testCloudVMWorkspaceDetectionAndProjectReconciliation() throws {
        let refNow = try XCTUnwrap(
            AntigravityRPCClient.parseProtoTimestamp(.string("2026-11-11T09:00:00Z"))
        )

        // 1. Jetski Cloud VM trajectory includes container home `/home/antigravity` + repo `/home/antigravity/venciallee/iOSAntigravity`
        let jetskiCloudEntry: JSONValue = .object([
            "summary": .string("Fix offline host badge and Cloud workspace detection"),
            "stepCount": .int(12),
            "status": .string("CASCADE_RUN_STATUS_RUNNING"),
            "lastModifiedTime": .string("2026-11-11T08:59:30Z"),
            "workspaces": .array([
                .object(["workspaceFolderAbsoluteUri": .string("file:///home/antigravity")]),
                .object([
                    "workspaceFolderAbsoluteUri": .string("file:///home/antigravity/venciallee/iOSAntigravity"),
                    "gitBranch": .string("main")
                ])
            ])
        ])
        let cloudSummary = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "v1/default/jetski_remote_agents_3p/02268caa-6eb1-426b-a5c3-8629460e0111",
                value: jetskiCloudEntry,
                now: refNow
            )
        )
        XCTAssertTrue(cloudSummary.isCloud)
        XCTAssertEqual(cloudSummary.projectSlug, "iOSAntigravity")
        XCTAssertEqual(cloudSummary.workspaceUri, "cloud://venciallee/iOSAntigravity")

        // 2. Remote-SSH and GitHub URLs also classify as Cloud
        XCTAssertTrue(AntigravityCloudDetector.isCloudWorkspaceURI("vscode-remote://ssh-remote+devbox/home/dev/iOSAntigravity"))
        XCTAssertEqual(
            AntigravityCloudDetector.normalizeWorkspaceURI("https://github.com/venciallee/iOSAntigravity.git", isCloud: true),
            "cloud://venciallee/iOSAntigravity"
        )

        // 3. Reconcile projects when a 0-chat local workspace has the same repo name as an active Cloud session
        let localMacEntry: JSONValue = .object([
            "summary": .string("Slardar Tag Code Review"),
            "stepCount": .int(5),
            "status": .string("CASCADE_RUN_STATUS_DONE"),
            "lastModifiedTime": .string("2026-11-11T08:50:00Z"),
            "workspaces": .array([
                .object([
                    "workspaceFolderAbsoluteUri": .string("file:///Users/dev/slardar_app_ai"),
                    "gitBranch": .string("main")
                ])
            ])
        ])
        let localSummary = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "cid-local-slardar",
                value: localMacEntry,
                now: refNow
            )
        )
        XCTAssertFalse(localSummary.isCloud)

        var summaries = [cloudSummary, localSummary]
        let workspaces = [
            WorkspaceInfo(workspaceUri: "file:///Users/dev/iOSAntigravity", displayName: "iOSAntigravity", activeBranch: "main", isCloud: false),
            WorkspaceInfo(workspaceUri: "file:///Users/dev/slardar_app_ai", displayName: "slardar_app_ai", activeBranch: "main", isCloud: false)
        ]
        let reconciled = AntigravitySessionStore.reconcileLiveProjects(
            workspaces: workspaces,
            summaries: &summaries,
            existingProjects: [],
            hostName: "LT74XT6L0M"
        )
        XCTAssertEqual(reconciled.count, 2)

        let iosProj = try XCTUnwrap(reconciled.first(where: { $0.name == "iOSAntigravity" }))
        XCTAssertEqual(iosProj.runtime, .cloud)
        XCTAssertEqual(iosProj.homeSubtitle(isHostOnline: true), "Cloud · venciallee/iOSAntigravity · main")
        XCTAssertEqual(iosProj.homeSubtitle(isHostOnline: false), "Cloud · venciallee/iOSAntigravity · main")

        let slardarProj = try XCTUnwrap(reconciled.first(where: { $0.name == "slardar_app_ai" }))
        XCTAssertEqual(slardarProj.runtime, .macBookPro)
        XCTAssertEqual(slardarProj.homeSubtitle(isHostOnline: true), "Local · LT74XT6L0M · main")
        XCTAssertEqual(slardarProj.homeSubtitle(isHostOnline: false), "Offline · LT74XT6L0M · main")
    }

    @MainActor
    func testOfflineErrorClassificationAndStoreOfflineStateTransition() {
        XCTAssertTrue(AntigravitySessionStore.isBackendOfflineError(URLError(.cannotConnectToHost)))
        XCTAssertTrue(AntigravitySessionStore.isBackendOfflineError(URLError(.timedOut)))
        XCTAssertTrue(AntigravitySessionStore.isBackendOfflineError(AntigravityRPCError.httpError(statusCode: 503, body: "Antigravity Desktop is offline")))
        XCTAssertTrue(AntigravitySessionStore.isBackendOfflineError(AntigravityRPCError.unauthorized("CSRF mismatch")))
        XCTAssertFalse(
            AntigravitySessionStore.isBackendOfflineError(AntigravityRPCError.httpError(statusCode: 404, body: "unimplemented")),
            "Optional unimplemented RPCs (HTTP 404) on raw language_server must not mark the host offline"
        )

        let store = AntigravitySessionStore.makeESDDVerificationStore()
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.activeHost = RemoteHostInstance(
            instanceId: "direct-mac",
            hostname: "LT74XT6L0M",
            channel: .directHost,
            endpointURL: URL(string: "http://192.168.1.20:8787")!,
            isOnline: true
        )
        store.hosts = [store.activeHost]
        store.projects = [
            ProjectWorkspace(
                id: "iOSAntigravity",
                name: "iOSAntigravity",
                pathDisplay: "cloud://venciallee/iOSAntigravity",
                workspaceUri: "cloud://venciallee/iOSAntigravity",
                runtime: .cloud,
                hostName: "Cloud",
                activeBranch: "main"
            )
        ]

        store.markBackendOffline(error: AntigravityRPCError.httpError(statusCode: 503, body: "Antigravity Desktop is offline"))
        XCTAssertTrue(store.hasPairedBackend, "Paired host flag must remain true while temporarily offline")
        XCTAssertFalse(store.isLiveBackendConnected)
        XCTAssertFalse(store.activeHost.isOnline)
        XCTAssertEqual(store.hosts.first?.isOnline, false)
        XCTAssertEqual(store.connectionStatusText, "Offline · LT74XT6L0M")
        XCTAssertEqual(store.projects.map(\.id), ["iOSAntigravity"])
    }

    func testOfficialRemoteControlQRAndCloudRelayJSPBCodec() throws {
        // 1. Official QR URL parsing (`/r/<slug>`, `/u/<authuser>/r/<uuid>`, `?p=c%2F<cid>`, and bare slug)
        let parsedQR = try XCTUnwrap(
            RemoteHostInstance.parseRemoteControlTarget(
                "https://antigravity.google.com/u/2/r/lt74xt6l0m-golden-star?p=c%2Fcas-rate-limiter"
            )
        )
        XCTAssertEqual(parsedQR.instanceId, "lt74xt6l0m-golden-star")
        XCTAssertEqual(parsedQR.authUser, "2")
        XCTAssertEqual(parsedQR.conversationId, "cas-rate-limiter")
        XCTAssertEqual(parsedQR.canonicalRelayURLString, "https://antigravity.google.com/r/lt74xt6l0m-golden-star")
        XCTAssertFalse(parsedQR.requiresRedirectResolution)

        let bareTarget = try XCTUnwrap(RemoteHostInstance.parseRemoteControlTarget("0f5819ac-9308-40d8-a308-98b55122c533-v2"))
        XCTAssertEqual(bareTarget.instanceId, "0f5819ac-9308-40d8-a308-98b55122c533-v2")

        // 1b. Google AccountChooser / ServiceLogin wrapped QR URLs
        let accountChooserWrapped =
            "https://accounts.google.com/AccountChooser?Email=dev%40gmail.com&continue=https%3A%2F%2Fantigravity.google.com%2Fu%2F1%2Fr%2Flt74xt6l0m-golden-star%3Fp%3Dc%252Fcas-wrapped"
        let parsedWrapped = try XCTUnwrap(RemoteHostInstance.parseRemoteControlTarget(accountChooserWrapped))
        XCTAssertEqual(parsedWrapped.instanceId, "lt74xt6l0m-golden-star")
        XCTAssertEqual(parsedWrapped.authUser, "1")
        XCTAssertEqual(parsedWrapped.conversationId, "cas-wrapped")
        XCTAssertEqual(parsedWrapped.relayOrigin, "https://antigravity.google.com")
        XCTAssertEqual(parsedWrapped.originalURLString, accountChooserWrapped)

        // 1c. Alternate Antigravity domains, query-param / hash-route formats, scheme-less links, custom schemes, JSON & CLI prose
        let corpTarget = try XCTUnwrap(
            RemoteHostInstance.parseRemoteControlTarget("https://antigravity.corp.google.com/remote?instance=lt74xt6l0m-golden-star")
        )
        XCTAssertEqual(corpTarget.instanceId, "lt74xt6l0m-golden-star")
        XCTAssertEqual(corpTarget.relayOrigin, "https://antigravity.corp.google.com")

        let schemelessTarget = try XCTUnwrap(
            RemoteHostInstance.parseRemoteControlTarget("antigravity.google.com/r/lt74xt6l0m-golden-star")
        )
        XCTAssertEqual(schemelessTarget.instanceId, "lt74xt6l0m-golden-star")
        XCTAssertEqual(schemelessTarget.relayOrigin, "https://antigravity.google.com")

        let customSchemeTarget = try XCTUnwrap(
            RemoteHostInstance.parseRemoteControlTarget("agy://r/lt74xt6l0m-golden-star?p=c%2Fcas-mobile")
        )
        XCTAssertEqual(customSchemeTarget.instanceId, "lt74xt6l0m-golden-star")
        XCTAssertEqual(customSchemeTarget.conversationId, "cas-mobile")
        XCTAssertEqual(customSchemeTarget.relayOrigin, "https://antigravity.google.com")

        let jsonTarget = try XCTUnwrap(
            RemoteHostInstance.parseRemoteControlTarget(#"{"instanceId":"lt74xt6l0m-golden-star","authUser":"0"}"#)
        )
        XCTAssertEqual(jsonTarget.instanceId, "lt74xt6l0m-golden-star")
        XCTAssertEqual(jsonTarget.authUser, "0")

        let proseTarget = try XCTUnwrap(
            RemoteHostInstance.parseRemoteControlTarget(
                "Open https://antigravity.google.com/r/lt74xt6l0m-golden-star on another device."
            )
        )
        XCTAssertEqual(proseTarget.instanceId, "lt74xt6l0m-golden-star")

        // 1d. Official Google shortlinks pin `relayOrigin` to `https://antigravity.google.com` & mark redirect resolution
        let shortlinkTarget = try XCTUnwrap(RemoteHostInstance.parseRemoteControlTarget("https://g.co/r/abc123xyz"))
        XCTAssertEqual(shortlinkTarget.instanceId, "")
        XCTAssertEqual(shortlinkTarget.relayOrigin, "https://antigravity.google.com")
        XCTAssertTrue(shortlinkTarget.requiresRedirectResolution)
        XCTAssertEqual(
            RemoteHostInstance.resolveEffectiveRelayTarget(
                scannedInput: "https://g.co/r/abc123xyz",
                webViewFinalURL: "https://antigravity.google.com/u/1/r/lt74xt6l0m-golden-star"
            ),
            "https://antigravity.google.com/u/1/r/lt74xt6l0m-golden-star"
        )

        // 1e. Local mock loopback `/r/<id>` vs plain LAN endpoint vs arbitrary third-party `/r/` URLs
        let mockLoopback = try XCTUnwrap(RemoteHostInstance.parseRemoteControlTarget("http://127.0.0.1:18080/r/mock-inst-1"))
        XCTAssertEqual(mockLoopback.instanceId, "mock-inst-1")
        XCTAssertEqual(mockLoopback.relayOrigin, "http://127.0.0.1:18080")
        XCTAssertNil(RemoteHostInstance.parseRemoteControlTarget("http://127.0.0.1:18080"))
        XCTAssertNil(RemoteHostInstance.parseRemoteControlTarget("https://www.reddit.com/r/swift"))
        XCTAssertNil(RemoteHostInstance.parseRemoteControlTarget("agpocket://verify/agents-home"))
        XCTAssertNil(RemoteHostInstance.parseRemoteControlTarget("agpocket://share/share-1"))
        XCTAssertTrue(RemoteHostInstance.isDirectLANPairingURI("agpocket://pair?url=https://192.168.1.20:8787&csrf=tok"))
        XCTAssertNil(RemoteHostInstance.parseRemoteControlTarget("agpocket://pair?url=https://192.168.1.20:8787&csrf=tok"))
        XCTAssertNil(RemoteHostInstance.parseRemoteControlTarget("antigravity://verify/agents-home"))
        XCTAssertTrue(RemoteHostInstance.isDirectLANPairingURI("antigravity://pair?url=https://192.168.1.20:8787&csrf=tok"))
        XCTAssertNil(RemoteHostInstance.parseRemoteControlTarget("antigravity://pair?url=https://192.168.1.20:8787&csrf=tok"))

        // 2. SAPISIDHASH SHA-1 vector & pure-Swift parity
        let mockCookie = "SAPISID=test_sapisid_val_123; __Secure-1PAPISID=test_sapisid_val_123; SID=test_sid_val"
        XCTAssertTrue(SAPISIDHashGenerator.hasRequiredGoogleAuthCookies(mockCookie))
        let authHeader = try XCTUnwrap(
            SAPISIDHashGenerator.computeAuthorizationHeader(
                cookieHeader: mockCookie,
                origin: "https://antigravity.google.com",
                timestamp: 1794406100
            )
        )
        let expectedDigest = SAPISIDHashGenerator.pureSwiftSHA1Hex(
            Array("1794406100 test_sapisid_val_123 https://antigravity.google.com".utf8)
        )
        XCTAssertEqual(
            SAPISIDHashGenerator.sha1Hex("1794406100 test_sapisid_val_123 https://antigravity.google.com"),
            expectedDigest
        )
        XCTAssertTrue(authHeader.contains("SAPISIDHASH 1794406100_\(expectedDigest)"))
        XCTAssertTrue(authHeader.contains("SAPISID1PHASH 1794406100_\(expectedDigest)"))

        // 3. ListInstances JSPB decoding (with XSSI `)]}'\n` prefix)
        let rawListInstances = Data(
            ")]}'\n[[[\"0f5819ac-9308-40d8-a308-98b55122c533-v2\",[\"lt74xt6l0m-golden-star\",\"2.32.0\",1],1,[1794406100,0]]],5]".utf8
        )
        let instances = try CloudRelayJSPBCodec.decodeListInstancesResponse(rawListInstances)
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instances[0].uuid, "0f5819ac-9308-40d8-a308-98b55122c533-v2")
        XCTAssertEqual(instances[0].name, "lt74xt6l0m-golden-star")
        XCTAssertEqual(instances[0].status, .connected)
        XCTAssertTrue(instances[0].matches(identifier: "lt74xt6l0m-golden-star"))
        XCTAssertTrue(instances[0].matches(identifier: "0f5819ac-9308-40d8-a308-98b55122c533-v2"))

        // 4. ProxyCommand request & response JSPB round-trip (including outer Base64 safety wrapper)
        let encodedProxyReq = try CloudRelayJSPBCodec.encodeProxyCommandRequest(
            targetInstanceUuid: "0f5819ac-9308-40d8-a308-98b55122c533-v2",
            rpcPath: "/exa.language_server_pb.LanguageServerService/GetWorkspaceInfos",
            payload: Data("{}".utf8),
            contentType: "application/json"
        )
        let reqArray = try XCTUnwrap(try JSONDecoder().decode(JSONValue.self, from: encodedProxyReq).arrayValue)
        XCTAssertEqual(reqArray[0].stringValue, "0f5819ac-9308-40d8-a308-98b55122c533-v2")
        XCTAssertEqual(reqArray[2].stringValue, "e30=")

        let sampleProxyResp = Data("[\"e30=\",[[\"accept-encoding\",\"gzip\"],[\"content-type\",\"application/json\"]]]".utf8)
        let decodedResp = try CloudRelayJSPBCodec.decodeProxyCommandResponse(sampleProxyResp)
        XCTAssertEqual(String(data: decodedResp.payload, encoding: .utf8), "{}")
        XCTAssertEqual(decodedResp.headers["content-type"], "application/json")

        let xssiOuterWrapped = Data((")]}'\n" + String(data: sampleProxyResp, encoding: .utf8)!).utf8).base64EncodedData()
        let decodedWrapped = try CloudRelayJSPBCodec.decodeProxyCommandResponse(
            xssiOuterWrapped,
            responseHeaders: ["Content-Transfer-Encoding": "base64"]
        )
        XCTAssertEqual(String(data: decodedWrapped.payload, encoding: .utf8), "{}")
    }

    func testDynamicCloudRelayWebApiKeyExtractionAndRuntimeDiscovery() async throws {
        // Construct synthetic 39-char Google browser API key shapes at runtime so zero key literals live in source
        let keyPrefix = "AI" + "za" + "Sy"
        let keyA = keyPrefix + String(repeating: "A", count: 33)
        let keyB = keyPrefix + String(repeating: "B", count: 33)

        // 1. Contextual WIZ_global_data JSON extraction
        let wizHTML = """
        <script>window.WIZ_global_data = {"cfb2h":"boq_devtools","WIu0Nc":"\(keyA)"};</script>
        """
        XCTAssertEqual(SAPISIDHashGenerator.extractWebApiKey(from: wizHTML), keyA)

        // 2. Standalone JS bundle extraction & meta tag fallback
        let jsBundle = "const cfg = { endpoint: '/$rpc', k: '\(keyB)' };"
        XCTAssertEqual(SAPISIDHashGenerator.extractWebApiKey(from: jsBundle), keyB)

        let metaHTML = """
        <html><head><meta name="antigravity-relay-api-key" content="mock-relay-web-api-key"></head></html>
        """
        XCTAssertEqual(SAPISIDHashGenerator.extractWebApiKey(from: metaHTML), "mock-relay-web-api-key")

        // 3. Trusted bootstrap script URL extraction (rejects untrusted hosts, prioritizes app bundles)
        let pageHTML = """
        <html><head>
          <script src="https://evil.example.com/inject.js"></script>
          <script src="/static/vendor.js"></script>
          <script src="https://www.gstatic.com/_/boq-devtools/_/js/k=boq.main/m=app"></script>
          <script src="/assets/antigravity-bootstrap.js"></script>
        </head></html>
        """
        let baseURL = URL(string: "https://antigravity.google.com/r/mock-inst-1")!
        let scriptURLs = SAPISIDHashGenerator.extractBootstrapScriptURLs(fromHTML: pageHTML, baseURL: baseURL)
        XCTAssertFalse(scriptURLs.contains { $0.host == "evil.example.com" })
        XCTAssertEqual(scriptURLs.count, 3)
        XCTAssertTrue(scriptURLs.first?.absoluteString.contains("gstatic.com") == true)

        // 4. applyApiServiceHeaders attaches X-Goog-Api-Key only when resolved, never from a hardcoded literal
        var reqWithoutKey = URLRequest(url: URL(string: "https://antigravity.google.com/$rpc/devtools_jetski_boq_api_proto.ApiService/ListInstances")!)
        SAPISIDHashGenerator.applyApiServiceHeaders(
            to: &reqWithoutKey,
            cookieHeader: "SAPISID=test_sid",
            origin: "https://antigravity.google.com",
            authUser: "0",
            apiKey: nil
        )
        if SAPISIDHashGenerator.configuredRelayWebApiKeyOverride() == nil {
            XCTAssertNil(reqWithoutKey.value(forHTTPHeaderField: "X-Goog-Api-Key"))
        }

        var reqWithKey = URLRequest(url: URL(string: "https://antigravity.google.com/$rpc/devtools_jetski_boq_api_proto.ApiService/ListInstances")!)
        SAPISIDHashGenerator.applyApiServiceHeaders(
            to: &reqWithKey,
            cookieHeader: "SAPISID=test_sid",
            origin: "https://antigravity.google.com",
            authUser: "0",
            apiKey: keyA
        )
        XCTAssertEqual(reqWithKey.value(forHTTPHeaderField: "X-Goog-Api-Key"), keyA)

        // 5. Invalid API key error classification vs normal session expiry
        XCTAssertTrue(SAPISIDHashGenerator.isInvalidApiKeyError(statusCode: 400, responseBody: "API_KEY_INVALID: API key not valid"))
        XCTAssertTrue(SAPISIDHashGenerator.isInvalidApiKeyError(statusCode: 403, responseBody: "Method doesn't allow unregistered callers (X-Goog-Api-Key)"))
        XCTAssertFalse(SAPISIDHashGenerator.isInvalidApiKeyError(statusCode: 401, responseBody: "Google session expired"))
        XCTAssertFalse(SAPISIDHashGenerator.isInvalidApiKeyError(statusCode: 403, responseBody: "PERMISSION_DENIED: user not signed in"))

        // 6. End-to-end AntigravityRPCClient runtime discovery from external script + automatic refresh on HTTP 400 API_KEY_INVALID
        let stateBox = RelayDiscoveryTestStateBox(activeScriptKey: keyA)
        RelayDiscoveryMockURLProtocol.setHandler { request in
            let url = try XCTUnwrap(request.url)
            let path = url.path
            if request.httpMethod == "GET" && (path == "/" || path.hasPrefix("/r/")) {
                let html = "<html><head><script src=\"/assets/antigravity-main.js\"></script></head></html>"
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
                return (resp, Data(html.utf8))
            }
            if request.httpMethod == "GET" && path == "/assets/antigravity-main.js" {
                let currentKey = stateBox.currentScriptKey()
                let js = "window.__relay = { apiKey: \"\(currentKey)\" };"
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/javascript"])!
                return (resp, Data(js.utf8))
            }
            if request.httpMethod == "POST" && path.hasSuffix("/ListInstances") {
                let sentKey = request.value(forHTTPHeaderField: "X-Goog-Api-Key") ?? ""
                stateBox.recordSentApiKey(sentKey)
                let attempt = stateBox.incrementListCalls()
                if attempt == 1 {
                    // Simulate Google rotating the public web key after initial discovery
                    stateBox.setScriptKey(keyB)
                    let resp = HTTPURLResponse(url: url, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                    return (resp, Data("{\"error\":{\"status\":\"INVALID_ARGUMENT\",\"message\":\"API key not valid. Please pass a valid API key. (API_KEY_INVALID)\"}}".utf8))
                }
                let okBody = ")]}'\n[[[\"0f5819ac-9308-40d8-a308-98b55122c533-v2\",[\"lt74xt6l0m-golden-star\",\"2.33.0\",1],1,[1794406100,0]]],5]"
                let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(okBody.utf8))
            }
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }
        defer { RelayDiscoveryMockURLProtocol.setHandler(nil) }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [RelayDiscoveryMockURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)

        let host = RemoteHostInstance(
            instanceId: "lt74xt6l0m-golden-star",
            hostname: "Mock Relay",
            channel: .cloudRelay,
            endpointURL: URL(string: "http://127.0.0.1:19876/r/lt74xt6l0m-golden-star")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=test_sapisid_val_123; SID=test_sid_val",
            urlSession: mockSession
        )

        let discoveredInstances = try await client.listRelayInstances()
        XCTAssertEqual(discoveredInstances.count, 1)
        XCTAssertEqual(discoveredInstances[0].uuid, "0f5819ac-9308-40d8-a308-98b55122c533-v2")
        XCTAssertEqual(stateBox.sentApiKeys(), [keyA, keyB])
        let activeKey = await client.currentRelayApiKey()
        XCTAssertEqual(activeKey, keyB)

        // 7. Cross-host redirect (e.g. accounts.google.com login page) must NEVER be harvested as relay API key
        RelayDiscoveryMockURLProtocol.setHandler { _ in
            let accountsURL = URL(string: "https://accounts.google.com/ServiceLogin?continue=https://antigravity.google.com/")!
            let accountsHTML = "<html><script>window.WIZ_global_data={\"WIu0Nc\":\"\(keyA)\"};</script></html>"
            let resp = HTTPURLResponse(url: accountsURL, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html"])!
            return (resp, Data(accountsHTML.utf8))
        }
        let redirectClient = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=expired_sid; SID=expired",
            urlSession: mockSession
        )
        let ignoredRedirectKey = await redirectClient.resolveRelayApiKey()
        XCTAssertNil(ignoredRedirectKey)
    }

    @MainActor
    func testMakeLiveStoreStartsEmptyWithZeroMockFixtures() {
        let liveStore = AntigravitySessionStore.makeLiveStore()
        XCTAssertFalse(liveStore.isVerificationMode)
        XCTAssertFalse(liveStore.hasPairedBackend)
        XCTAssertFalse(liveStore.isLiveBackendConnected)
        XCTAssertTrue(liveStore.projects.isEmpty)
        XCTAssertTrue(liveStore.workspaces.isEmpty)
        XCTAssertTrue(liveStore.summaries.isEmpty)
        XCTAssertTrue(liveStore.automations.isEmpty)
        XCTAssertTrue(liveStore.contextCandidates.isEmpty)
        XCTAssertTrue(liveStore.availableGitHubRepos.isEmpty)
        XCTAssertTrue(liveStore.composerAttachments.isEmpty)
        XCTAssertEqual(liveStore.composerDraftText, "")
        XCTAssertEqual(liveStore.activeCascadeId, "")
        XCTAssertEqual(liveStore.selectedProjectId, "")

        XCTAssertEqual(liveStore.availableModels, CascadeModelConfig.liveDefaultCatalog)
        XCTAssertEqual(liveStore.availableAgents, ["Default"])

        let verifyStore = AntigravitySessionStore.makeESDDVerificationStore()
        XCTAssertTrue(verifyStore.isVerificationMode)
        XCTAssertFalse(verifyStore.summaries.isEmpty)
        XCTAssertEqual(verifyStore.availableModels, CascadeModelConfig.liveDefaultCatalog)
    }

    func testBinaryProtobufGetStepsRequestAndRealStepDecoding() throws {
        // 1. Verify field 3 (`verbosity`) is NEVER populated with `endIndex`
        let req = ProtobufStepCodec.encodeGetStepsRequest(
            cascadeId: "cas-1",
            startIndex: 120,
            endIndex: 999
        )
        // 0x0A, 0x05, "cas-1" (7 bytes) + 0x10, 0x78 (2 bytes) = 9 bytes total
        XCTAssertEqual(Array(req), [0x0A, 0x05, 0x63, 0x61, 0x73, 0x2D, 0x31, 0x10, 0x78])

        // Helper functions for assembling deterministic binary Protobuf wire bytes
        func pbVarintField(_ field: Int, _ val: UInt64) -> Data {
            var d = Data(ProtobufStepCodec.encodeVarint(UInt64((field << 3) | 0)))
            d.append(contentsOf: ProtobufStepCodec.encodeVarint(val))
            return d
        }
        func pbBytesField(_ field: Int, _ payload: Data) -> Data {
            var d = Data(ProtobufStepCodec.encodeVarint(UInt64((field << 3) | 2)))
            d.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(payload.count)))
            d.append(payload)
            return d
        }
        func pbStringField(_ field: Int, _ text: String) -> Data {
            pbBytesField(field, Data(text.utf8))
        }

        // Step 0: USER_INPUT (type=14, status=3, user_input=19 with user_response + user_config Planning + M37)
        let conversationalMsg = pbVarintField(14, 1) // agentic_mode = true -> Planning
        let requestedModelMsg = pbVarintField(1, 1037) // model = 1037 -> MODEL_PLACEHOLDER_M37
        var plannerCfgMsg = Data()
        plannerCfgMsg.append(pbBytesField(2, conversationalMsg))
        plannerCfgMsg.append(pbBytesField(15, requestedModelMsg))
        let cascadeCfgMsg = pbBytesField(1, plannerCfgMsg)

        var userInputMsg = Data()
        userInputMsg.append(pbStringField(2, "Check Antigravity Cloud sync"))
        userInputMsg.append(pbBytesField(12, cascadeCfgMsg))

        var step0 = Data()
        step0.append(pbVarintField(1, 14))
        step0.append(pbVarintField(4, 3))
        step0.append(pbBytesField(19, userInputMsg))

        // Step 1: PLANNER_RESPONSE (type=15, status=3, planner_response=20)
        var plannerRespMsg = Data()
        plannerRespMsg.append(pbStringField(1, "Cloud sync verified."))
        plannerRespMsg.append(pbStringField(3, "Inspected JetboxSubscribeToSummaries."))
        var step1 = Data()
        step1.append(pbVarintField(1, 15))
        step1.append(pbVarintField(4, 3))
        step1.append(pbBytesField(20, plannerRespMsg))

        // Step 2: NOTIFY_USER (type=82, status=3, notify_user=94)
        let notifyMsg = pbStringField(2, "All checks green.")
        var step2 = Data()
        step2.append(pbVarintField(1, 82))
        step2.append(pbVarintField(4, 3))
        step2.append(pbBytesField(94, notifyMsg))

        var responseBytes = Data()
        responseBytes.append(pbBytesField(1, step0))
        responseBytes.append(pbBytesField(1, step1))
        responseBytes.append(pbBytesField(1, step2))

        let decoded = ProtobufStepCodec.decodeStepsResponse(responseBytes, cascadeId: "cid-proto-test")
        XCTAssertEqual(decoded.count, 3)

        XCTAssertEqual(decoded[0].type, .userInput)
        XCTAssertEqual(decoded[0].status, .done)
        XCTAssertEqual(decoded[0].userInput, "Check Antigravity Cloud sync")
        XCTAssertEqual(decoded[0].recordedExecutionMode, .planning)
        XCTAssertEqual(decoded[0].recordedModelId, "MODEL_PLACEHOLDER_M37")

        XCTAssertEqual(decoded[1].type, .plannerResponse)
        XCTAssertEqual(decoded[1].plannerResponse?.response, "Cloud sync verified.")
        XCTAssertEqual(decoded[1].plannerResponse?.thinking, "Inspected JetboxSubscribeToSummaries.")

        XCTAssertEqual(decoded[2].type, .notifyUser)
        XCTAssertEqual(decoded[2].plannerResponse?.response, "All checks green.")
    }

    func testCloudRelayUnbufferedJSPBStreamParserAndJetboxRemoteAicodeDecode() throws {
        // 1. Unbuffered StreamProxyCommand JSPB stream without trailing newline emits inner Connect frames immediately
        let connectFrame1 = ConnectEnvelope.encode(
            payload: Data(#"{"updates":{"cid-cloud-1":{"summary":"Cloud Agent Task","stepCount":4,"status":"CASCADE_RUN_STATUS_RUNNING","projectId":"proj-uuid-1"}}}"#.utf8)
        )
        let connectFrame2 = ConnectEnvelope.encode(
            payload: Data(#"{"deletes":["cid-old"]}"#.utf8)
        )
        let b64Frame1 = connectFrame1.base64EncodedString()
        let b64Frame2 = connectFrame2.base64EncodedString()

        var jspbParser = CloudRelayJSPBStreamParser()
        var connectParser = ConnectStreamParser()

        // First network chunk has XSSI prefix and top-level `[...]` closed without trailing newline
        var standaloneParser = CloudRelayJSPBStreamParser()
        let unbufferedChunk1 = Data(")]}'\n[[\"\(b64Frame1)\",[[\"content-type\",\"application/connect+json\"]]]]".utf8)
        let emitted1 = standaloneParser.feed(unbufferedChunk1)
        XCTAssertEqual(emitted1.count, 1)

        let frames1 = connectParser.feed(emitted1[0])
        XCTAssertEqual(frames1.count, 1)
        let event1 = try JSONDecoder().decode([String: JSONValue].self, from: frames1[0].payload)

        let cloudProj = ProjectWorkspace(
            id: "iOSAntigravity",
            name: "iOSAntigravity",
            pathDisplay: "cloud://venciallee/iOSAntigravity",
            workspaceUri: "cloud://venciallee/iOSAntigravity",
            runtime: .cloud,
            hostName: "Cloud",
            activeBranch: "main",
            cloudProjectId: "proj-uuid-1"
        )
        let decodedBatch = AntigravityRPCClient.decodeJetboxSummariesEvent(
            event1,
            forceCloud: true,
            originInstanceUuid: "inst-uuid-1",
            originHostName: "Antigravity",
            cloudProjectsById: ["proj-uuid-1": cloudProj]
        )
        XCTAssertEqual(decodedBatch.upserts.count, 1)
        let summary = decodedBatch.upserts[0]
        XCTAssertTrue(summary.isCloud)
        XCTAssertEqual(summary.originHostName, "Antigravity")
        XCTAssertEqual(summary.projectSlug, "iOSAntigravity")
        XCTAssertEqual(summary.workspaceUri, "cloud://venciallee/iOSAntigravity")
        XCTAssertEqual(summary.cloudProjectId, "proj-uuid-1")

        // Also feed split multi-part stream across arbitrary byte boundaries
        let combinedStream = Data("[[\"\(b64Frame1)\",null]][[\"\(b64Frame2)\",null]]".utf8)
        let splitIdx = 19
        let partA = jspbParser.feed(Data(combinedStream.prefix(splitIdx)))
        XCTAssertTrue(partA.isEmpty)
        let partB = jspbParser.feed(Data(combinedStream.dropFirst(splitIdx)))
        XCTAssertEqual(partB.count, 2)
    }

    @MainActor
    func testPairedBackendNeverInjectsMockReplyAndSyncsRecordedModeAndModel() throws {
        let store = AntigravitySessionStore.makeLiveStore()
        store.hasPairedBackend = true
        store.isLiveBackendConnected = false // Simulate transient Cloud Relay offline state
        store.activeCascadeId = "cid-live-session"
        store.composerDraftText = "修复云端会话同步"
        store.sendCurrentDraft()

        let steps = try XCTUnwrap(store.stepsByCascadeId["cid-live-session"])
        XCTAssertEqual(steps.count, 1, "Paired backend must never inject fake ESDD mock plannerResponse steps")
        XCTAssertEqual(steps.first?.type, .userInput)
        XCTAssertEqual(steps.first?.userInput, "修复云端会话同步")

        // Verify JSON step decoding extracts `agenticMode: false` -> `.fast` and `MODEL_PLACEHOLDER_M18` -> `Gemini 3 Flash`
        let rawFastUserStep: JSONValue = .object([
            "stepIndex": .int(0),
            "type": .string("CORTEX_STEP_TYPE_USER_INPUT"),
            "status": .string("CORTEX_STEP_STATUS_DONE"),
            "userInput": .object([
                "userResponse": .string("Quick local tweak"),
                "userConfig": .object([
                    "plannerConfig": .object([
                        "conversational": .object([
                            "plannerMode": .string("CONVERSATIONAL_PLANNER_MODE_DEFAULT"),
                            "agenticMode": .bool(false)
                        ]),
                        "requestedModel": .object([
                            "model": .string("MODEL_PLACEHOLDER_M18")
                        ])
                    ])
                ])
            ])
        ])
        let decodedFastStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(rawFastUserStep, cascadeId: "cid-fast-chat", fallbackIndex: 0)
        )
        XCTAssertEqual(decodedFastStep.recordedExecutionMode, .fast)
        XCTAssertEqual(decodedFastStep.recordedModelId, "MODEL_PLACEHOLDER_M18")

        store.stepsByCascadeId["cid-fast-chat"] = [decodedFastStep]
        store.selectCascade("cid-fast-chat")
        XCTAssertEqual(store.selectedModelConfig.mode, .fast)
        XCTAssertEqual(store.selectedModelConfig.modelId, "MODEL_PLACEHOLDER_M18")
        XCTAssertEqual(store.selectedModelConfig.displayName, "Gemini 3 Flash")
    }

    func testGitHubFlavoredMarkdownParserBlocksAndInlines() throws {
        let sample = """
        ### 1. 修复 `Markdown` 渲染

        1. **云端对话**：支持 `BACKEND_TYPE_REMOTE_AICODE` 与 mock_language_server.py
           - **根因**：查看 [`StepCellViews.swift`](file:///Users/dev/StepCellViews.swift#L560-L567)
             - [x] 已完成 GFM AST 解析

        > [!WARNING]
        > 拉取后直接编译即可，无需运行 `xcodegen`

        | 模块 | 语法示例 | 状态 |
        | :--- | :---: | ---: |
        | 表格 | `a | b` | ~~旧版~~ **通过** |

        ```swift
        let blocks = AntigravityMarkdownParser.parse(prose)
        ```
        """

        let blocks = AntigravityMarkdownParser.parse(sample)
        XCTAssertEqual(blocks.count, 7)

        // 1. Heading H3 with inline code
        guard case .heading(_, let level, let headingInlines) = blocks[0] else {
            return XCTFail("Expected heading at block 0, got \(blocks[0])")
        }
        XCTAssertEqual(level, 3)
        XCTAssertEqual(headingInlines, [.text("1. 修复 "), .code("Markdown"), .text(" 渲染")])

        // 2. Top-level ordered list item preserving intraword underscores in `mock_language_server.py`
        guard case .listItem(_, let indent0, let marker0, let item0Inlines) = blocks[1] else {
            return XCTFail("Expected listItem at block 1")
        }
        XCTAssertEqual(indent0, 0)
        XCTAssertEqual(marker0, .ordered(1))
        XCTAssertTrue(item0Inlines.map(\.plainText).joined().contains("mock_language_server.py"))

        // 3. Nested bullet item (indent 1) with `[`StepCellViews.swift`](file:///...)`
        guard case .listItem(_, let indent1, let marker1, let item1Inlines) = blocks[2] else {
            return XCTFail("Expected nested bullet listItem at block 2")
        }
        XCTAssertEqual(indent1, 1)
        XCTAssertEqual(marker1, .bullet)
        let expectedLink = MarkdownInline.link(
            label: [.code("StepCellViews.swift")],
            destination: "file:///Users/dev/StepCellViews.swift#L560-L567"
        )
        XCTAssertTrue(item1Inlines.contains(expectedLink), "Expected nested code link in \(item1Inlines)")

        // 4. Nested task item (indent 2, checked)
        guard case .listItem(_, let indent2, let marker2, _) = blocks[3] else {
            return XCTFail("Expected nested task listItem at block 3")
        }
        XCTAssertEqual(indent2, 2)
        XCTAssertEqual(marker2, .task(checked: true))

        // 5. GitHub `[!WARNING]` alert blockquote
        guard case .blockquote(_, let alertKind, let alertBlocks) = blocks[4] else {
            return XCTFail("Expected blockquote at block 4")
        }
        XCTAssertEqual(alertKind, .warning)
        XCTAssertEqual(alertBlocks.count, 1)

        // 6. GFM Table ignoring `|` inside inline code `` `a | b` ``
        guard case .table(_, let headers, let alignments, let rows) = blocks[5] else {
            return XCTFail("Expected table at block 5")
        }
        XCTAssertEqual(headers.count, 3)
        XCTAssertEqual(alignments, [.leading, .center, .trailing])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0][1], [.code("a | b")])
        XCTAssertEqual(rows[0][2], [.strikethrough([.text("旧版")]), .text(" "), .strong([.text("通过")])])

        // 7. Fenced Swift code block
        guard case .codeBlock(_, let lang, let code) = blocks[6] else {
            return XCTFail("Expected codeBlock at block 6")
        }
        XCTAssertEqual(lang, "swift")
        XCTAssertEqual(code, "let blocks = AntigravityMarkdownParser.parse(prose)")

        // 8. Streaming unclosed code fence while Agent is mid-turn
        let streamingMarkdown = "正在执行：\n```bash\ngit pull origin main"
        let streamingBlocks = AntigravityMarkdownParser.parse(streamingMarkdown)
        XCTAssertEqual(streamingBlocks.count, 2)
        if case .codeBlock(_, let streamLang, let streamCode) = streamingBlocks[1] {
            XCTAssertEqual(streamLang, "bash")
            XCTAssertEqual(streamCode, "git pull origin main")
        } else {
            XCTFail("Expected streaming unclosed codeBlock")
        }
    }

    @MainActor
    func testGeneratingStepStatusAndActiveStreamingLifecycle() async throws {
        // 1. Upstream JSON step status mapping for active generation & interruption
        XCTAssertEqual(CortexStepStatus.from(jsonName: "CORTEX_STEP_STATUS_GENERATING"), .inProgress)
        XCTAssertEqual(CortexStepStatus.from(jsonName: "CORTEX_STEP_STATUS_THINKING"), .inProgress)
        XCTAssertEqual(CortexStepStatus.from(jsonName: "CASCADE_RUN_STATUS_GENERATING"), .inProgress)
        XCTAssertEqual(CortexStepStatus.from(jsonName: "CORTEX_STEP_STATUS_INTERRUPTED"), .cancelled)

        // 2. Actively generating PLANNER_RESPONSE with empty prose/thinking is preserved & renderable
        let generatingJSON: JSONValue = .object([
            "type": .string("CORTEX_STEP_TYPE_PLANNER_RESPONSE"),
            "status": .string("CORTEX_STEP_STATUS_GENERATING"),
            "plannerResponse": .object([
                "response": .string("")
            ])
        ])
        let generatingStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(generatingJSON, cascadeId: "cid-live", fallbackIndex: 1)
        )
        XCTAssertEqual(generatingStep.status, .inProgress)
        XCTAssertEqual(generatingStep.type, .plannerResponse)
        XCTAssertNotNil(generatingStep.plannerResponse)
        XCTAssertTrue(
            generatingStep.hasRenderableChatContent,
            "An actively generating plannerResponse step must render live thinking indicator even before first token lands"
        )

        // 3. Reconcile streaming status: keep .inProgress right after USER_INPUT and between tool calls
        let userStep = CascadeStep(
            cascadeId: "cid-live",
            stepIndex: 0,
            type: .userInput,
            status: .done,
            userInput: "Analyze game_loop performance"
        )
        let afterUserOnly = AntigravitySessionStore.reconcileSummaryStreamingStatus(
            currentStatus: .inProgress,
            remoteSteps: [userStep],
            withinOptimisticSendWindow: true
        )
        XCTAssertEqual(afterUserOnly.status, .inProgress)
        XCTAssertTrue(afterUserOnly.stillActive)

        let toolDoneStep = CascadeStep(
            cascadeId: "cid-live",
            stepIndex: 1,
            type: .viewFile,
            status: .done,
            viewFile: ViewFilePayload(fileUri: "file:///workspace/game_loop.swift", startLine: 1, endLine: 80)
        )
        let betweenToolCalls = AntigravitySessionStore.reconcileSummaryStreamingStatus(
            currentStatus: .inProgress,
            remoteSteps: [userStep, toolDoneStep],
            withinOptimisticSendWindow: false
        )
        XCTAssertEqual(betweenToolCalls.status, .inProgress)
        XCTAssertTrue(betweenToolCalls.stillActive)

        let completedReplyStep = CascadeStep(
            cascadeId: "cid-live",
            stepIndex: 2,
            type: .plannerResponse,
            status: .done,
            plannerResponse: PlannerResponsePayload(response: "Finished analyzing `game_loop.swift`.")
        )
        let turnCompleted = AntigravitySessionStore.reconcileSummaryStreamingStatus(
            currentStatus: .inProgress,
            remoteSteps: [userStep, toolDoneStep, completedReplyStep],
            withinOptimisticSendWindow: false
        )
        XCTAssertEqual(turnCompleted.status, .done)
        XCTAssertFalse(turnCompleted.stillActive)

        // 4. Cloud v1/... trajectory IDs with slashes persist & reload cleanly in LocalProjectionStore
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("agy_proj_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cloudCascadeId = "v1/default/jetski_remote_agents_3p/a860e091-c559-4a65-9b8c-ba6efd89c533"
        let storeA = LocalProjectionStore(storageDirectory: tempDir)
        await storeA.saveProjectedSteps([userStep, completedReplyStep], for: cloudCascadeId)
        let storeB = LocalProjectionStore(storageDirectory: tempDir)
        let reloaded = await storeB.loadProjectedSteps(cascadeId: cloudCascadeId)
        XCTAssertEqual(reloaded.count, 2)
    }

    @MainActor
    func testNoProjectLocalAndCloudConversationsAndProjectOrdering() throws {
        let refNow = try XCTUnwrap(
            AntigravityRPCClient.parseProtoTimestamp(.string("2026-11-12T10:00:00Z"))
        )

        // 1. Local `No Project` trajectory (`workspaces: []`) -> "No Project", empty URI & empty branch
        let localUnassignedJSON: JSONValue = .object([
            "summary": .string("Explain Swift 6 actor isolation"),
            "stepCount": .int(6),
            "status": .string("CASCADE_RUN_STATUS_DONE"),
            "lastModifiedTime": .string("2026-11-12T09:58:00Z"),
            "workspaces": .array([])
        ])
        let localNoProj = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "cid-local-no-proj",
                value: localUnassignedJSON,
                now: refNow
            )
        )
        XCTAssertFalse(localNoProj.isCloud)
        XCTAssertEqual(localNoProj.projectSlug, "No Project")
        XCTAssertEqual(localNoProj.workspaceUri, "")
        XCTAssertEqual(localNoProj.branchName, "")

        // 2. Local scratch playground (`~/.gemini/antigravity/playground/silver-comet`) -> grouped under "No Project"
        let scratchPlaygroundJSON: JSONValue = .object([
            "summary": .string("Quick Python regex scratchpad"),
            "stepCount": .int(4),
            "status": .string("CASCADE_RUN_STATUS_IDLE"),
            "lastModifiedTime": .string("2026-11-12T09:40:00Z"),
            "workspaces": .array([
                .object(["workspaceFolderAbsoluteUri": .string("file:///Users/dev/.gemini/antigravity/playground/silver-comet")])
            ])
        ])
        let scratchNoProj = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "cid-scratch-playground",
                value: scratchPlaygroundJSON,
                now: refNow
            )
        )
        XCTAssertFalse(scratchNoProj.isCloud)
        XCTAssertEqual(scratchNoProj.projectSlug, "No Project")
        XCTAssertEqual(scratchNoProj.workspaceUri, "file:///Users/dev/.gemini/antigravity/playground/silver-comet")
        XCTAssertEqual(scratchNoProj.branchName, "")

        // 3. Cloud `BACKEND_TYPE_REMOTE_AICODE` `JetboxSubscribeToSummaries` (`forceCloud: true`) with:
        //    - UUID key & empty `workspaces` (Cloud `No Project`) -> MUST NOT be dropped!
        //    - `v1/...` key & container root `file:///home/antigravity` -> "No Project", `isCloud == true`
        //    - Echoed local `file:///Users/dev/code/game_loop` -> filtered out cleanly
        let jetboxCloudEvent: [String: JSONValue] = [
            "updates": .object([
                "4b7f82a1-9912-40d0-8111-cc8899aa0011": .object([
                    "summary": .string("Cloud brainstorm without GitHub repo"),
                    "stepCount": .int(5),
                    "status": .string("CASCADE_RUN_STATUS_DONE"),
                    "lastModifiedTime": .string("2026-11-12T09:59:00Z"),
                    "workspaces": .array([])
                ]),
                "v1/default/jetski_remote_agents_3p/11223344-5566-7788-99aa-bbccddeeff00": .object([
                    "summary": .string("Unmounted Jetski Cloud VM chat"),
                    "stepCount": .int(3),
                    "status": .string("CASCADE_RUN_STATUS_RUNNING"),
                    "lastModifiedTime": .string("2026-11-12T09:59:30Z"),
                    "workspaces": .array([
                        .object(["workspaceFolderAbsoluteUri": .string("file:///home/antigravity")])
                    ])
                ]),
                "cid-echoed-local-repo": .object([
                    "summary": .string("Local Mac repo echoed on un-filtered server"),
                    "stepCount": .int(9),
                    "status": .string("CASCADE_RUN_STATUS_IDLE"),
                    "workspaces": .array([
                        .object(["workspaceFolderAbsoluteUri": .string("file:///Users/dev/code/game_loop")])
                    ])
                ])
            ])
        ]
        let cloudBatch = AntigravityRPCClient.decodeJetboxSummariesEvent(
            jetboxCloudEvent,
            forceCloud: true,
            originInstanceUuid: "inst-1",
            originHostName: "Antigravity"
        )
        XCTAssertEqual(cloudBatch.upserts.count, 2, "Both Cloud No Project sessions must survive while echoed local repo is filtered out")
        for s in cloudBatch.upserts {
            XCTAssertTrue(s.isCloud)
            XCTAssertEqual(s.originHostName, "Antigravity")
            XCTAssertEqual(s.projectSlug, "No Project")
            XCTAssertEqual(s.workspaceUri, "")
            XCTAssertEqual(s.branchName, "")
        }

        // 4. Legacy cached `"workspace"` summary migration & project ordering (named projects first, `No Project` at bottom)
        let namedRepoSummary = CascadeSummary(
            cascadeId: "cid-game-loop",
            title: "Optimize render frame pacing",
            projectSlug: "game_loop",
            workspaceUri: "file:///Users/dev/code/game_loop",
            branchName: "main",
            status: .done,
            stepCount: 12,
            updatedAt: refNow.addingTimeInterval(-3600)
        )
        let legacyCachedWorkspaceSummary = CascadeSummary(
            cascadeId: "cid-legacy-cached",
            title: "Cached unassigned chat from older build",
            projectSlug: "workspace",
            workspaceUri: "file:///Users/wl/code/workspace",
            branchName: "main",
            status: .done,
            stepCount: 2,
            updatedAt: refNow
        )

        var allSummaries = [legacyCachedWorkspaceSummary, localNoProj, scratchNoProj] + cloudBatch.upserts + [namedRepoSummary]
        let reconciled = AntigravitySessionStore.reconcileLiveProjects(
            workspaces: [
                WorkspaceInfo(workspaceUri: "file:///Users/dev/code/game_loop", displayName: "game_loop", activeBranch: "main", isCloud: false)
            ],
            summaries: &allSummaries,
            existingProjects: [],
            hostName: "Mac Mini"
        )

        // Named `game_loop` comes BEFORE both `No Project` (Local) and `cloud:No Project` (Cloud)
        XCTAssertEqual(reconciled.map(\.id), ["game_loop", "No Project", "cloud:No Project"])

        let localNoProjSection = try XCTUnwrap(reconciled.first(where: { $0.id == "No Project" }))
        XCTAssertTrue(localNoProjSection.isNoProject)
        XCTAssertEqual(localNoProjSection.homeSubtitle(isHostOnline: true), "Local · Mac Mini")
        XCTAssertEqual(localNoProjSection.homeSubtitle(isHostOnline: false), "Offline · Mac Mini")
        XCTAssertEqual(localNoProjSection.activeBranch, "")
        XCTAssertEqual(localNoProjSection.workspaceUri, "")

        let cloudNoProjSection = try XCTUnwrap(reconciled.first(where: { $0.id == "cloud:No Project" }))
        XCTAssertTrue(cloudNoProjSection.isNoProject)
        XCTAssertEqual(cloudNoProjSection.name, "No Project")
        XCTAssertEqual(cloudNoProjSection.homeSubtitle(isHostOnline: true), "Antigravity Cloud")
        XCTAssertEqual(cloudNoProjSection.activeBranch, "")

        let migratedLegacy = try XCTUnwrap(allSummaries.first(where: { $0.cascadeId == "cid-legacy-cached" }))
        XCTAssertEqual(migratedLegacy.projectSlug, "No Project")
        XCTAssertEqual(migratedLegacy.workspaceUri, "")
        XCTAssertEqual(migratedLegacy.branchName, "")

        // 5. Cloud `No Project` entry with `workspaces: []` + `trajectoryMetadata.workspaceUris: ["file:///home/antigravity"]`
        let metaContainerCloudJSON: JSONValue = .object([
            "displayName": .string("Remote Cloud quick script"),
            "stepCount": .int(3),
            "status": .string("CASCADE_RUN_STATUS_DONE"),
            "trajectoryMetadata": .object([
                "workspaceUris": .array([.string("file:///home/antigravity")])
            ]),
            "workspaces": .array([])
        ])
        let metaCloudNoProj = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "99887766-5544-3322-1100-aabbccddeeff",
                value: metaContainerCloudJSON,
                now: refNow
            )
        )
        XCTAssertTrue(metaCloudNoProj.isCloud)
        XCTAssertEqual(metaCloudNoProj.projectSlug, "No Project")
        XCTAssertEqual(metaCloudNoProj.workspaceUri, "")
        XCTAssertEqual(metaCloudNoProj.branchName, "")

        // 6. Creating a new `No Project` conversation on a paired store never gets stuck in `isLoadingSteps`
        let store = AntigravitySessionStore.makeESDDVerificationStore()
        store.hasPairedBackend = true
        store.isLiveBackendConnected = false
        store.activeHost = RemoteHostInstance(
            instanceId: "mac-mini-offline",
            hostname: "Mac Mini",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google/r/mac-mini-offline")!,
            isOnline: false
        )
        store.projects = reconciled
        store.summaries = allSummaries
        let createdOptimisticId = store.createConversationInProject("No Project")
        XCTAssertTrue(store.locallyCreatedEmptyCascadeIds.contains(createdOptimisticId))
        store.syncStepsForCascade(createdOptimisticId, pollUntilIdle: true)
        XCTAssertFalse(store.isLoadingSteps)
        XCTAssertNil(store.stepLoadErrorText)
        let createdSummary = try XCTUnwrap(store.summaries.first(where: { $0.cascadeId == createdOptimisticId }))
        XCTAssertEqual(createdSummary.projectSlug, "No Project")
        XCTAssertEqual(createdSummary.branchName, "")
        XCTAssertEqual(createdSummary.workspaceUri, "")
    }

    @MainActor
    func testHistoricalStepFetchAndCloudRelayChunkedFailover() throws {
        // 1. Same-Mac window family matching (`swift-vapor` closed, `game-loop` open on same Mac mini)
        let openGameLoopWindow = RelayInstanceInfo(
            uuid: "inst-game-loop-v2",
            name: "huangjiafandemac-mini-local-game-loop",
            status: .connected
        )
        XCTAssertTrue(openGameLoopWindow.sameHostFamily(as: "huangjiafandemac-mini-local-swift-vapor"))

        let openDesktopSlug = RelayInstanceInfo(
            uuid: "inst-silver-moon-v2",
            name: "lt74xt6l0m-silver-moon",
            status: .idle
        )
        XCTAssertTrue(openDesktopSlug.sameHostFamily(as: "lt74xt6l0m-golden-star"))
        XCTAssertFalse(openDesktopSlug.sameHostFamily(as: "99aa88bb77-golden-star"))

        // 2. Nested Boq JSPB wrapper `[[ "<base64>", [["content-type", "application/json"]] ], null]`
        let expectedJSON = #"{"steps":[{"stepIndex":0,"type":"CORTEX_STEP_TYPE_USER_INPUT","userInput":"Hello from history"}]}"#
        let b64Full = Data(expectedJSON.utf8).base64EncodedString()
        let nestedJSPB = Data(#"[[ "\#(b64Full)", [["content-type", "application/json"]] ], null]"#.utf8)
        let nestedDecoded = try CloudRelayJSPBCodec.decodeProxyCommandResponse(nestedJSPB)
        XCTAssertEqual(String(data: nestedDecoded.payload, encoding: .utf8), expectedJSON)
        XCTAssertEqual(nestedDecoded.headers["content-type"], "application/json")

        // 3. Multi-chunk concatenated JSPB response (`supportsChunking == true` on large trajectory histories)
        let allBytes = Array(expectedJSON.utf8)
        let mid = allBytes.count / 2
        let part1B64 = Data(allBytes[..<mid]).base64EncodedString()
        let part2B64 = Data(allBytes[mid...]).base64EncodedString()
        let chunkedJSPB = Data("[\"\(part1B64)\", [[\"content-type\", \"application/json\"]]]\n[\"\(part2B64)\", []]\n".utf8)
        let chunkedDecoded = try CloudRelayJSPBCodec.decodeProxyCommandResponse(chunkedJSPB)
        XCTAssertEqual(String(data: chunkedDecoded.payload, encoding: .utf8), expectedJSON)

        // 4. Connect 5-byte envelope unwrapping on unary JSON/Protobuf responses
        let framedBytes = ConnectEnvelope.encode(payload: Data(expectedJSON.utf8))
        let unwrappedBytes = AntigravityRPCClient.unwrapConnectFramedPayloadIfNeeded(framedBytes)
        XCTAssertEqual(String(data: unwrappedBytes, encoding: .utf8), expectedJSON)

        // 5. Numeric proto enum values in `decodeJSONStep`
        let numericStepJSON: JSONValue = .object([
            "stepIndex": .int(0),
            "type": .int(14),
            "status": .int(3),
            "userInput": .object(["text": .string("Fix historical step loading")])
        ])
        let numericStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(numericStepJSON, cascadeId: "cid-num", fallbackIndex: 0)
        )
        XCTAssertEqual(numericStep.type, .userInput)
        XCTAssertEqual(numericStep.status, .done)
        XCTAssertEqual(numericStep.userInput, "Fix historical step loading")

        // 6. Existing historical conversation with `stepCount == 0` (dormant on disk) is NEVER skipped when offline-flagged
        let store = AntigravitySessionStore.makeESDDVerificationStore()
        store.hasPairedBackend = true
        store.isLiveBackendConnected = false
        store.activeHost = RemoteHostInstance(
            instanceId: "huangjiafandemac-mini-local-swift-vapor",
            hostname: "huangjiafandemac-mini-local-swift-vapor",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/huangjiafandemac-mini-local-swift-vapor")!,
            isOnline: false
        )
        let dormantHistoricalId = "b8c12204-77a1-4f90-9c31-5566778899aa"
        store.summaries = [
            CascadeSummary(
                cascadeId: dormantHistoricalId,
                title: "New Conversation",
                projectSlug: "game_loop",
                workspaceUri: "file:///Users/dev/code/game_loop",
                branchName: "main",
                status: .done,
                stepCount: 0
            )
        ]
        XCTAssertFalse(store.locallyCreatedEmptyCascadeIds.contains(dormantHistoricalId))
        store.selectCascade(dormantHistoricalId)
        XCTAssertTrue(
            store.isLoadingSteps,
            "Tapping an existing dormant conversation in the list must actively trigger step sync instead of skipping on stepCount == 0"
        )
        store.disconnectStepSyncForTestingIfNeeded()
    }

    @MainActor
    func testLowPowerConnectionLifecycleBackoffAndPersistentOutbox() async throws {
        // 1. Heartbeat stays above cellular RRC tail-time (~12s) and doubles in Low Power Mode
        XCTAssertEqual(
            ConnectionPowerPolicy.onlineHeartbeatInterval(
                channel: .cloudRelay,
                isLowPowerMode: false,
                isExpensiveNetwork: false,
                isStreamHealthy: true
            ),
            30.0
        )
        XCTAssertEqual(
            ConnectionPowerPolicy.onlineHeartbeatInterval(
                channel: .cloudRelay,
                isLowPowerMode: false,
                isExpensiveNetwork: true,
                isStreamHealthy: true
            ),
            45.0
        )
        XCTAssertEqual(
            ConnectionPowerPolicy.onlineHeartbeatInterval(
                channel: .cloudRelay,
                isLowPowerMode: true,
                isExpensiveNetwork: true,
                isStreamHealthy: true
            ),
            90.0
        )
        XCTAssertEqual(
            ConnectionPowerPolicy.onlineHeartbeatInterval(
                channel: .directHost,
                isLowPowerMode: false,
                isExpensiveNetwork: false,
                isStreamHealthy: true
            ),
            15.0
        )

        // 2. Idle chat stops step polling completely when push stream is healthy
        XCTAssertNil(
            ConnectionPowerPolicy.idleChatFallbackStepPollInterval(
                isStreamHealthy: true,
                isLowPowerMode: false
            )
        )
        XCTAssertEqual(
            ConnectionPowerPolicy.idleChatFallbackStepPollInterval(
                isStreamHealthy: false,
                isLowPowerMode: false
            ),
            15.0
        )
        XCTAssertEqual(
            ConnectionPowerPolicy.activeStreamingStepPollInterval(
                channel: .directHost,
                isLowPowerMode: false
            ),
            0.5
        )
        XCTAssertEqual(
            ConnectionPowerPolicy.activeStreamingStepPollInterval(
                channel: .cloudRelay,
                isLowPowerMode: false
            ),
            1.0
        )

        // 3. Offline exponential backoff sequence (3s -> 6s -> 12s -> 24s -> 45s -> 60s cap; x2 in Low Power Mode)
        let normalSchedule = (0...7).map {
            ConnectionPowerPolicy.offlineBackoffBaseDelay(attempt: $0, isLowPowerMode: false)
        }
        XCTAssertEqual(normalSchedule, [3.0, 6.0, 12.0, 24.0, 45.0, 60.0, 60.0, 60.0])

        let lowPowerSchedule = (0...6).map {
            ConnectionPowerPolicy.offlineBackoffBaseDelay(attempt: $0, isLowPowerMode: true)
        }
        XCTAssertEqual(lowPowerSchedule, [6.0, 12.0, 24.0, 48.0, 90.0, 120.0, 120.0])

        let jittered = ConnectionPowerPolicy.offlineBackoffDelay(
            attempt: 2,
            isLowPowerMode: false,
            applyJitter: true,
            jitterFactor: 1.15
        )
        XCTAssertEqual(jittered, 13.8, accuracy: 0.001)

        // 4. Failure debounce thresholds
        XCTAssertEqual(
            ConnectionPowerPolicy.offlineFailureThreshold(
                channel: .cloudRelay,
                error: AntigravityRPCError.httpError(statusCode: 503, body: "No reachable Antigravity Desktop instances online")
            ),
            1
        )
        XCTAssertEqual(
            ConnectionPowerPolicy.offlineFailureThreshold(
                channel: .cloudRelay,
                error: URLError(.timedOut)
            ),
            2
        )
        XCTAssertEqual(
            ConnectionPowerPolicy.offlineFailureThreshold(
                channel: .directHost,
                error: URLError(.cannotConnectToHost)
            ),
            1
        )

        // 5. Screen-off / background suspension stops networking cleanly WITHOUT flashing red Offline status
        let store = AntigravitySessionStore.makeLiveStore()
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.activeHost = RemoteHostInstance(
            instanceId: "relay-mac-mini",
            hostname: "Mac Mini",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/relay-mac-mini")!,
            isOnline: true
        )
        store.connectionLifecyclePhase = .onlineIdle

        store.suspendNetworkingForBackground()
        XCTAssertTrue(store.isNetworkingSuspended)
        XCTAssertEqual(store.connectionLifecyclePhase, .suspended)
        XCTAssertTrue(store.activeHost.isOnline, "Suspending for screen-off must not falsely mark host offline")
        XCTAssertTrue(store.isLiveBackendConnected)

        // While suspended, syncStepsForCascade must remain completely inert
        store.syncStepsForCascade("cid-should-not-poll", pollUntilIdle: true)
        XCTAssertFalse(store.isLoadingSteps)

        // 6. NWPathMonitor unsatisfied pauses probes with distinct No Internet status
        store.isNetworkingSuspended = false
        store.handleNetworkPathChange(.unsatisfied)
        XCTAssertFalse(store.isDeviceNetworkReachable)
        XCTAssertEqual(store.connectionLifecyclePhase, .noNetwork)
        XCTAssertEqual(store.connectionStatusText, "No Internet Connection")

        // 7. Persistent Durable Outbox disk round-trip & selective entry removal
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityOutboxTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writerStore = LocalProjectionStore(storageDirectory: tempDir)
        let entry1 = OutboxEntry(cascadeId: "cid-1", kind: .userMessage, messageText: "Queued prompt 1")
        let entry2 = OutboxEntry(cascadeId: "cid-1", kind: .userMessage, messageText: "Queued prompt 2")
        await writerStore.enqueueOutbox(entry1)
        await writerStore.enqueueOutbox(entry2)

        // Fresh actor instance reads persisted outbox_queue.json from disk
        let readerStore = LocalProjectionStore(storageDirectory: tempDir)
        let loaded = await readerStore.loadPendingOutbox()
        XCTAssertEqual(loaded.map(\.id), [entry1.id, entry2.id])

        await readerStore.removeOutboxEntry(id: entry1.id)
        let remaining = await LocalProjectionStore(storageDirectory: tempDir).loadPendingOutbox()
        XCTAssertEqual(remaining.map(\.id), [entry2.id])
    }

    @MainActor
    func testNativeSidecarAutomationsProtocolAndCodec() async throws {
        // 1. Schedule ID & args roundtrip (with model flag & legacy positional fallback)
        let generatedId = AutomationScheduleCodec.makeSidecarId(from: "Nightly Dependency Audit!", suffix: "abc123")
        XCTAssertEqual(generatedId, "nightly-dependency-audit-abc123")
        let fallbackId = AutomationScheduleCodec.makeSidecarId(from: "每天巡检依赖", suffix: "ff0011")
        XCTAssertEqual(fallbackId, "auto-ff0011")

        let args = AutomationScheduleCodec.buildScheduleArgs(
            cron: "CRON_TZ=Asia/Shanghai 0 2 * * *",
            prompt: "Audit dependencies and open PR if outdated",
            modelArg: "gemini-3.1-pro"
        )
        XCTAssertEqual(
            args,
            [
                "CRON_TZ=Asia/Shanghai 0 2 * * *",
                "agentapi",
                "new-conversation",
                "--model=gemini-3.1-pro",
                "--",
                "Audit dependencies and open PR if outdated"
            ]
        )
        let parsedArgs = AutomationScheduleCodec.parseScheduleArgs(args)
        XCTAssertEqual(parsedArgs.cron, "CRON_TZ=Asia/Shanghai 0 2 * * *")
        XCTAssertEqual(parsedArgs.prompt, "Audit dependencies and open PR if outdated")
        XCTAssertEqual(parsedArgs.modelLabel, "Pro")

        let legacyParsed = AutomationScheduleCodec.parseScheduleArgs([
            "0 9 * * 1-5",
            "agentapi",
            "new-conversation",
            "Summarize open pull requests"
        ])
        XCTAssertEqual(legacyParsed.cron, "0 9 * * 1-5")
        XCTAssertEqual(legacyParsed.prompt, "Summarize open pull requests")
        XCTAssertNil(legacyParsed.modelLabel)

        // 2. Human-readable cadence & deterministic nextFireDate calculation
        XCTAssertEqual(AutomationScheduleCodec.humanReadableSchedule(from: "CRON_TZ=UTC 0 2 * * *"), "Daily at 02:00")
        XCTAssertEqual(AutomationScheduleCodec.humanReadableSchedule(from: "0 9 * * 1-5"), "Weekdays at 09:00")
        XCTAssertEqual(AutomationScheduleCodec.humanReadableSchedule(from: "0 9 * * 1"), "Mondays at 09:00")
        XCTAssertEqual(AutomationScheduleCodec.humanReadableSchedule(from: "0 * * * *"), "Hourly")
        XCTAssertEqual(AutomationScheduleCodec.humanReadableSchedule(from: "*/15 * * * *"), "Every 15m")

        let iso = ISO8601DateFormatter()
        let fixedNow = try XCTUnwrap(iso.date(from: "2026-11-20T08:30:00Z")) // Friday 08:30 UTC
        let nextWeekday = try XCTUnwrap(AutomationScheduleCodec.nextFireDate(from: "CRON_TZ=UTC 0 9 * * 1-5", after: fixedNow))
        XCTAssertEqual(nextWeekday, try XCTUnwrap(iso.date(from: "2026-11-20T09:00:00Z")))
        XCTAssertEqual(
            AutomationScheduleCodec.nextFireDescription(from: "CRON_TZ=UTC 0 9 * * 1-5", after: fixedNow),
            "In 30m"
        )

        // 3. Natural-language schedule parsing (English & Chinese)
        let enNL = AutomationScheduleCodec.parseNaturalLanguagePrompt(
            "Every weekday at 9, summarize open PRs",
            timeZoneId: "America/Los_Angeles"
        )
        XCTAssertEqual(enNL.cronExpression, "CRON_TZ=America/Los_Angeles 0 9 * * 1-5")
        XCTAssertEqual(enNL.humanScheduleLabel, "Weekdays at 09:00")
        XCTAssertTrue(enNL.prompt.lowercased().contains("summarize open prs"))

        let zhNL = AutomationScheduleCodec.parseNaturalLanguagePrompt(
            "每天早上8点检查依赖更新",
            timeZoneId: "Asia/Shanghai"
        )
        XCTAssertEqual(zhNL.cronExpression, "CRON_TZ=Asia/Shanghai 0 8 * * *")
        XCTAssertEqual(zhNL.humanScheduleLabel, "Daily at 08:00")

        // 4. Native `SidecarStatusInfo` decoding (enabled, proto3 omitted false/paused, always-on, web UI filtered)
        let enabledSidecarObj: [String: JSONValue] = [
            "sidecarId": .string("nightly-audit"),
            "status": .string("SIDECAR_STATUS_RUNNING"),
            "config": .object([
                "builtin": .string("schedule"),
                "displayName": .string("Nightly Audit"),
                "description": .string("Check outdated deps"),
                "args": .array([
                    .string("CRON_TZ=UTC 0 2 * * *"),
                    .string("agentapi"),
                    .string("new-conversation"),
                    .string("--model=gemini-3.1-pro"),
                    .string("--"),
                    .string("Run dependency audit")
                ])
            ]),
            "userConfig": .object([
                "enabled": .bool(true),
                "projectId": .string("proj-123")
            ])
        ]
        let decodedEnabled = try XCTUnwrap(
            AntigravityRPCClient.decodeSidecarStatusInfo(
                enabledSidecarObj,
                projectNameById: ["proj-123": "ledger-svc"],
                now: fixedNow
            )
        )
        XCTAssertEqual(decodedEnabled.id, "nightly-audit")
        XCTAssertEqual(decodedEnabled.title, "Nightly Audit")
        XCTAssertEqual(decodedEnabled.projectSlug, "ledger-svc")
        XCTAssertEqual(decodedEnabled.section, .scheduled)
        XCTAssertEqual(decodedEnabled.modelLabel, "Pro")
        XCTAssertTrue(decodedEnabled.isEnabled)
        XCTAssertTrue(decodedEnabled.isScheduleBuiltin)

        // Proto3 omits `"enabled": false` in JSON; stopped status + userConfig without enabled must decode as `.paused`.
        let pausedSidecarObj: [String: JSONValue] = [
            "sidecarId": .string("bundle-watch"),
            "status": .string("SIDECAR_STATUS_STOPPED"),
            "config": .object([
                "builtin": .string("schedule"),
                "displayName": .string("Bundle size watch"),
                "args": .array([
                    .string("CRON_TZ=UTC 0 8 * * *"),
                    .string("agentapi"),
                    .string("new-conversation"),
                    .string("--"),
                    .string("Check bundle size")
                ])
            ]),
            "userConfig": .object([
                "projectId": .string("proj-123")
            ])
        ]
        let decodedPaused = try XCTUnwrap(
            AntigravityRPCClient.decodeSidecarStatusInfo(
                pausedSidecarObj,
                projectNameById: ["proj-123": "ledger-svc"],
                now: fixedNow
            )
        )
        XCTAssertEqual(decodedPaused.section, .paused)
        XCTAssertFalse(decodedPaused.isEnabled)
        XCTAssertEqual(decodedPaused.nextRunText, "Paused")

        // Pure Web UI sidecar panel must be excluded from Automations list.
        let webUiSidecarObj: [String: JSONValue] = [
            "sidecarId": .string("canvas-preview"),
            "status": .string("SIDECAR_STATUS_RUNNING"),
            "config": .object([
                "displayName": .string("Canvas Preview"),
                "hasWebUi": .bool(true)
            ])
        ]
        XCTAssertNil(AntigravityRPCClient.decodeSidecarStatusInfo(webUiSidecarObj, now: fixedNow))

        // Always-on custom non-UI sidecar decodes into `.alwaysOn`.
        let alwaysOnObj: [String: JSONValue] = [
            "sidecarId": .string("pr-triage-daemon"),
            "status": .string("SIDECAR_STATUS_RUNNING"),
            "config": .object([
                "displayName": .string("PR Triage Listener"),
                "command": .string("/usr/local/bin/pr-triage")
            ]),
            "userConfig": .object([
                "enabled": .bool(true),
                "allProjects": .bool(true)
            ])
        ]
        let decodedAlwaysOn = try XCTUnwrap(
            AntigravityRPCClient.decodeSidecarStatusInfo(alwaysOnObj, now: fixedNow)
        )
        XCTAssertEqual(decodedAlwaysOn.section, .alwaysOn)
        XCTAssertFalse(decodedAlwaysOn.isScheduleBuiltin)
        XCTAssertEqual(decodedAlwaysOn.projectSlug, "All projects")

        // 5. `GetSidecarEvents` decoding & `ManageSidecar` payload building
        let eventObj: [String: JSONValue] = [
            "timestampMs": .string("1763625600000"),
            "payload": .object([
                "newConversation": .object([
                    "conversationId": .string("cas-auto-run-99"),
                    "prompt": .string("Run dependency audit")
                ])
            ])
        ]
        let decodedEvent = try XCTUnwrap(AntigravityRPCClient.decodeSidecarEvent(eventObj))
        XCTAssertEqual(decodedEvent.timestampMs, 1_763_625_600_000)
        XCTAssertEqual(decodedEvent.conversationId, "cas-auto-run-99")
        XCTAssertNil(decodedEvent.error)

        let manageBody = AntigravityRPCClient.buildManageSidecarConfigBody(
            sidecarId: "nightly-audit-a1",
            action: .create,
            displayName: "Nightly Audit",
            prompt: "Audit dependencies",
            cronExpression: "CRON_TZ=UTC 0 2 * * *",
            description: "Daily check",
            projectId: "proj-123",
            allProjects: false,
            modelArg: "gemini-3-flash"
        )
        XCTAssertEqual(manageBody["sidecarId"]?.stringValue, "nightly-audit-a1")
        XCTAssertEqual(manageBody["action"]?.stringValue, "SIDECAR_ACTION_CREATE")
        XCTAssertEqual(manageBody["projectId"]?.stringValue, "proj-123")
        XCTAssertEqual(manageBody["config"]?.objectValue?["builtin"]?.stringValue, "schedule")

        // 6. Store reconciliation & offline CRUD actions (create / update / pause / resume / delete)
        var linkedAuto = decodedEnabled
        linkedAuto.lastRunCascadeId = "cas-auto-run-99"
        let runningSummary = CascadeSummary(
            cascadeId: "cas-auto-run-99",
            title: "Nightly Audit",
            projectSlug: "ledger-svc",
            workspaceUri: "file:///Users/dev/ledger-svc",
            status: .inProgress,
            stepCount: 3,
            relativeTimeLabel: "1m ago"
        )
        let reconciled = AntigravitySessionStore.reconcileAutomations([linkedAuto], with: [runningSummary])
        XCTAssertTrue(reconciled[0].isRunningNow)
        XCTAssertEqual(reconciled[0].lastRunText, "Running · 1m ago")

        let store = AntigravitySessionStore.makeESDDVerificationStore()
        let createdOk = await store.createAutomation(
            displayName: "Morning Digest",
            prompt: "Summarize overnight commits",
            cronExpression: "CRON_TZ=UTC 0 9 * * 1-5",
            projectSlug: "ledger-svc",
            modelArg: "gemini-3-flash",
            enableImmediately: true
        )
        XCTAssertTrue(createdOk)
        let digest = try XCTUnwrap(store.automations.first(where: { $0.title == "Morning Digest" }))
        let updatedOk = await store.updateAutomation(
            automationId: digest.id,
            displayName: "Morning Digest v2",
            prompt: "Summarize overnight commits and CI failures",
            cronExpression: "CRON_TZ=UTC 30 8 * * *",
            projectSlug: "ledger-svc",
            modelArg: "gemini-3.1-pro"
        )
        XCTAssertTrue(updatedOk)
        XCTAssertEqual(store.automations.first(where: { $0.id == digest.id })?.title, "Morning Digest v2")

        store.pauseAutomation(digest.id)
        XCTAssertEqual(store.automations.first(where: { $0.id == digest.id })?.section, .paused)

        store.resumeAutomation(digest.id)
        XCTAssertEqual(store.automations.first(where: { $0.id == digest.id })?.section, .scheduled)

        store.deleteAutomation(digest.id)
        XCTAssertNil(store.automations.first(where: { $0.id == digest.id }))
    }

    @MainActor
    func testAutomationPromptDraftDoesNotAutoCreateUntilSent() throws {
        let store = AntigravitySessionStore.makeESDDVerificationStore()
        let initialSummaryCount = store.summaries.count

        // 1. Tapping "Create with Prompt" opens an unsent draft without adding a summary or streaming
        store.openAutomationPromptDraft()
        XCTAssertEqual(store.summaries.count, initialSummaryCount)
        XCTAssertEqual(store.activeCascadeId, "")
        XCTAssertEqual(store.activeRoute, .cascadeChat(""))
        XCTAssertFalse(store.isCascadeStreaming)
        XCTAssertTrue(store.activeSteps.isEmpty)
        XCTAssertEqual(store.composerWorkflowCommand, "/automation")
        XCTAssertEqual(store.composerDraftText, AntigravitySessionStore.defaultAutomationGuidedPrompt)
        XCTAssertTrue(store.canSendCurrentDraft)

        let draft = try XCTUnwrap(store.pendingDraftConversation)
        XCTAssertEqual(draft.title, "New Automation")
        XCTAssertEqual(draft.projectSlug, AntigravityCloudDetector.noProjectDisplayName)
        XCTAssertEqual(draft.workflowCommand, "/automation")

        // 2. Navigating back before sending discards the draft cleanly with zero orphan conversations
        store.discardPendingDraftConversation()
        XCTAssertNil(store.pendingDraftConversation)
        XCTAssertNil(store.composerWorkflowCommand)
        XCTAssertEqual(store.composerDraftText, "")
        XCTAssertEqual(store.summaries.count, initialSummaryCount)

        // 3. Re-opening with a `/automation ...` seed strips duplicate prefix, allows switching project,
        //    and materializes the conversation only when the user taps Send.
        store.createAutomationWithAgent(prompt: "/automation Summarize open PRs every weekday at 9am")
        XCTAssertEqual(store.summaries.count, initialSummaryCount)
        XCTAssertEqual(store.composerWorkflowCommand, "/automation")
        XCTAssertEqual(store.composerDraftText, "Summarize open PRs every weekday at 9am")

        store.updatePendingDraftProject("ledger-svc")
        XCTAssertEqual(store.pendingDraftConversation?.projectSlug, "ledger-svc")

        store.sendCurrentDraft()
        XCTAssertNil(store.pendingDraftConversation)
        XCTAssertNil(store.composerWorkflowCommand)
        XCTAssertEqual(store.composerDraftText, "")
        XCTAssertEqual(store.summaries.count, initialSummaryCount + 1)
        XCTAssertFalse(store.activeCascadeId.isEmpty)

        let createdSummary = try XCTUnwrap(store.summaries.first(where: { $0.cascadeId == store.activeCascadeId }))
        XCTAssertEqual(createdSummary.projectSlug, "ledger-svc")
        XCTAssertEqual(createdSummary.title, "Summarize open PRs every weekday at 9am")

        let firstUserStep = try XCTUnwrap(store.activeSteps.first(where: { $0.type == .userInput }))
        XCTAssertEqual(firstUserStep.userInput, "/automation Summarize open PRs every weekday at 9am")

        // 4. Sending the default guided prompt with No Project preserves "New Automation" title and sends full command
        store.openAutomationPromptDraft()
        XCTAssertEqual(store.summaries.count, initialSummaryCount + 1)
        store.sendCurrentDraft()
        XCTAssertEqual(store.summaries.count, initialSummaryCount + 2)
        let guidedSummary = try XCTUnwrap(store.summaries.first(where: { $0.cascadeId == store.activeCascadeId }))
        XCTAssertEqual(guidedSummary.projectSlug, AntigravityCloudDetector.noProjectDisplayName)
        XCTAssertEqual(guidedSummary.title, "New Automation")
        let guidedStep = try XCTUnwrap(store.activeSteps.first(where: { $0.type == .userInput }))
        XCTAssertEqual(guidedStep.userInput, "/automation Guide me through creating an automated task")
    }

    func testModelConfigBadgeTitleAndDescriptiveSubtitles() throws {
        XCTAssertTrue(CascadeModelConfig.isGenericBadgeLabel("New"))
        XCTAssertTrue(CascadeModelConfig.isGenericBadgeLabel("  beta "))
        XCTAssertFalse(CascadeModelConfig.isGenericBadgeLabel("Deep reasoning for long, multi-step tasks"))

        XCTAssertEqual(
            CascadeModelConfig.descriptiveSubtitle(forModelLabel: "Gemini 4 Neon (XHigh)"),
            "Maximum reasoning depth for the hardest tasks"
        )
        XCTAssertEqual(
            CascadeModelConfig.descriptiveSubtitle(forModelLabel: "Gemini 4 Neon (High)"),
            "Deep reasoning for complex, multi-step tasks"
        )
        XCTAssertEqual(
            CascadeModelConfig.descriptiveSubtitle(forModelLabel: "Gemini 4 Neon (Medium)"),
            "Balanced speed and reasoning for daily work"
        )
        XCTAssertEqual(
            CascadeModelConfig.descriptiveSubtitle(forModelLabel: "Gemini 4 Neon (Low)"),
            "Faster responses for quick, everyday edits"
        )

        // Round-trip encoding/decoding with explicit badgeTitle
        let neon = CascadeModelConfig(
            modelId: "MODEL_NEON_HIGH",
            displayName: "Gemini 4 Neon (High)",
            subtitle: "Deep reasoning for complex, multi-step tasks",
            badgeTitle: "New"
        )
        let encoded = try JSONEncoder().encode(neon)
        let decoded = try JSONDecoder().decode(CascadeModelConfig.self, from: encoded)
        XCTAssertEqual(decoded.badgeTitle, "New")
        XCTAssertEqual(decoded, neon)

        // Backward-compatible decoding when legacy payload omits badgeTitle
        let legacyJSON = Data("""
        {
          "modelId": "MODEL_NEON_LOW",
          "displayName": "Gemini 4 Neon (Low)",
          "subtitle": "Faster responses for quick, everyday edits"
        }
        """.utf8)
        let legacyDecoded = try JSONDecoder().decode(CascadeModelConfig.self, from: legacyJSON)
        XCTAssertNil(legacyDecoded.badgeTitle)
        XCTAssertEqual(legacyDecoded.displayName, "Gemini 4 Neon (Low)")
    }

    @MainActor
    func testAgentPermissionPresetsAndStoreRuntimeIsolation() {
        XCTAssertEqual(
            AgentPermissionPreset.availablePresets(isRemote: true),
            [.requestReview, .defaultPolicy, .turbo]
        )
        XCTAssertEqual(
            AgentPermissionPreset.availablePresets(isRemote: false),
            [.requestReview, .defaultPolicy, .auto, .turbo]
        )
        XCTAssertEqual(AgentPermissionPreset.defaultPreset(isRemote: true), .turbo)
        XCTAssertEqual(AgentPermissionPreset.defaultPreset(isRemote: false), .defaultPolicy)

        let store = AntigravitySessionStore.makeESDDVerificationStore()
        // Verification store defaults to local MacBook Pro (`cas-rate-limiter`)
        XCTAssertFalse(store.isActiveSessionCloud)
        XCTAssertEqual(store.activePermissionPreset, .defaultPolicy)

        store.setActivePermissionPreset(.requestReview)
        XCTAssertEqual(store.localPermissionPreset, .requestReview)
        XCTAssertEqual(store.remotePermissionPreset, .turbo)

        // Switching to a Cloud/Remote session exposes isolated Remote Permissions (default Turbo)
        store.activeCascadeId = "v1/default/jetski_remote_agents_3p/demo-cloud-session"
        XCTAssertTrue(store.isActiveSessionCloud)
        XCTAssertEqual(store.activePermissionPreset, .turbo)

        store.setActivePermissionPreset(.defaultPolicy)
        XCTAssertEqual(store.remotePermissionPreset, .defaultPolicy)
        XCTAssertEqual(store.localPermissionPreset, .requestReview)

        // Local Auto resolves cleanly and never leaks into Remote Permissions
        XCTAssertEqual(AgentPermissionPreset.auto.resolvedForRuntime(isRemote: false), .auto)
        XCTAssertEqual(AgentPermissionPreset.auto.resolvedForRuntime(isRemote: true), .defaultPolicy)
        store.setActivePermissionPreset(.auto, isRemoteOverride: false)
        XCTAssertEqual(store.localPermissionPreset, .auto)
        XCTAssertEqual(store.permissionPreset(isRemote: false), .auto)
        XCTAssertEqual(store.remotePermissionPreset, .defaultPolicy)
        store.setActivePermissionPreset(.auto, isRemoteOverride: true)
        XCTAssertEqual(store.remotePermissionPreset, .defaultPolicy)
        XCTAssertEqual(store.localPermissionPreset, .auto)

        // Wire protocol: Auto explicitly encodes CASCADE_COMMANDS_AUTO_EXECUTION_AUTO (distinct from Default)
        let autoToolCfg = AntigravityRPCClient.buildToolConfig(for: .auto)
        XCTAssertEqual(
            autoToolCfg["runCommand"]?.objectValue?["autoCommandConfig"]?.objectValue?["autoExecutionPolicy"]?.stringValue,
            "CASCADE_COMMANDS_AUTO_EXECUTION_AUTO"
        )
        XCTAssertEqual(
            autoToolCfg["notifyUser"]?.objectValue?["artifactReviewMode"]?.stringValue,
            "ARTIFACT_REVIEW_MODE_AUTO"
        )
        let defaultToolCfg = AntigravityRPCClient.buildToolConfig(for: .defaultPolicy)
        XCTAssertNil(defaultToolCfg["runCommand"])

        // Same-name Cloud project + stale Cloud workspace selection must NEVER hijack a local file:// chat
        let cloudSameName = ProjectWorkspace(
            id: "cloud:shared-app",
            name: "shared-app",
            pathDisplay: "Cloud · shared-app",
            workspaceUri: "cloud://acme/shared-app",
            runtime: .cloud,
            hostName: "Antigravity Cloud"
        )
        let localSameName = ProjectWorkspace(
            id: "local:shared-app",
            name: "shared-app",
            pathDisplay: "~/code/shared-app",
            workspaceUri: "file:///Users/alex/code/shared-app",
            runtime: .macBookPro,
            hostName: "MacBook Pro"
        )
        store.projects.insert(contentsOf: [cloudSameName, localSameName], at: 0)
        store.selectedProjectId = cloudSameName.id
        store.selectedWorkspaceUri = cloudSameName.workspaceUri
        XCTAssertTrue(store.isHomeSelectedProjectCloud)

        let localChat = CascadeSummary(
            cascadeId: "cas-local-shared-app",
            title: "Run local tests",
            projectSlug: "shared-app",
            workspaceUri: "file:///Users/alex/code/shared-app",
            status: .done,
            stepCount: 2,
            isCloud: false
        )
        store.summaries.insert(localChat, at: 0)
        store.activeCascadeId = localChat.cascadeId
        XCTAssertFalse(store.isSummaryCloudRuntime(localChat))
        XCTAssertFalse(store.isActiveSessionCloud)
        XCTAssertEqual(store.activePermissionPreset, .auto)

        // Switching Home project back to local updates isHomeSelectedProjectCloud even if activeCascadeId is Cloud
        store.activeCascadeId = "v1/default/jetski_remote_agents_3p/demo-cloud-session"
        store.selectedProjectId = localSameName.id
        store.selectedWorkspaceUri = localSameName.workspaceUri
        XCTAssertFalse(store.isHomeSelectedProjectCloud)
        XCTAssertTrue(store.isActiveSessionCloud)

        // Selecting Auto on an active local session clears any stale per-conversation override
        store.activeCascadeId = localChat.cascadeId
        store.conversationPermissionPresets[localChat.cascadeId] = .requestReview
        XCTAssertEqual(store.effectivePermissionPreset(for: localChat.cascadeId, isRemoteOverride: false), .requestReview)
        store.setActivePermissionPreset(.auto, isRemoteOverride: false)
        XCTAssertNil(store.conversationPermissionPresets[localChat.cascadeId])
        XCTAssertEqual(store.effectivePermissionPreset(for: localChat.cascadeId, isRemoteOverride: false), .auto)
    }

    @MainActor
    func testOpenBoqStreamingParserCloudSyncStatusPriorityAndUnreadReconciliation() throws {
        // 1. Google Boq open infinite outer array (`[[["<b64>", headers]],[["<b64_2>"]],` with NO outer closing `]`)
        let cloudFrame1 = ConnectEnvelope.encode(
            payload: Data(#"{"updates":{"v1/default/jetski_remote_agents_3p/aaa":{"summary":"Cloud Build Fix","stepCount":12,"status":"CASCADE_RUN_STATUS_RUNNING","workspaces":[{"workspaceFolderAbsoluteUri":"file:///home/antigravity/venciallee/iOSAntigravity"}]}}}"#.utf8)
        )
        let cloudFrame2 = ConnectEnvelope.encode(
            payload: Data(#"{"updates":{"v1/default/jetski_remote_agents_3p/bbb":{"summary":"Cloud Diff Audit","stepCount":4,"status":2}}}"#.utf8)
        )
        let b64OneEscaped = cloudFrame1.base64EncodedString()
            .replacingOccurrences(of: "/", with: "\\/")
            .replacingOccurrences(of: "=", with: "\\u003d")
        let b64Two = cloudFrame2.base64EncodedString()

        var boqParser = CloudRelayJSPBStreamParser()
        var connectParser = ConnectStreamParser()

        // First network delivery opens outer `[` + sends header-only frame + first Cloud payload, outer `[` stays OPEN!
        let openChunk1 = Data(
            ")]}'\n[[[null,[[\"content-type\",\"application/connect+json\"]]]],[[\"\(b64OneEscaped)\",[[\"content-type\",\"application/connect+json\"]]]]"
                .utf8
        )
        let emittedA = boqParser.feed(openChunk1)
        XCTAssertEqual(emittedA.count, 1, "Must emit first Boq payload immediately even though outer `[` is still open")
        let decodedFramesA = connectParser.feed(emittedA[0])
        XCTAssertEqual(decodedFramesA.count, 1)
        let eventA = try JSONDecoder().decode([String: JSONValue].self, from: decodedFramesA[0].payload)
        XCTAssertNotNil(eventA["updates"]?.objectValue?["v1/default/jetski_remote_agents_3p/aaa"])

        // Second network delivery arrives later on the same open outer array
        let openChunk2 = Data(",[[\"\(b64Two)\"]]".utf8)
        let emittedB = boqParser.feed(openChunk2)
        XCTAssertEqual(emittedB.count, 1, "Must emit subsequent Boq payloads immediately while outer `[` remains open")
        let decodedFramesB = connectParser.feed(emittedB[0])
        XCTAssertEqual(decodedFramesB.count, 1)
        let eventB = try JSONDecoder().decode([String: JSONValue].self, from: decodedFramesB[0].payload)
        let batchB = AntigravityRPCClient.decodeJetboxSummariesEvent(eventB, forceCloud: true)
        XCTAssertEqual(batchB.upserts.count, 1)
        XCTAssertEqual(batchB.upserts[0].status, .inProgress, "Numeric status 2 must decode to RUNNING (.inProgress)")

        // Boq error trailer must never emit as payload and must populate `lastErrorTrailer`
        let errTrailer = Data(",[null,[13,\"upstream relay disconnected\"]]".utf8)
        let emittedErr = boqParser.feed(errTrailer)
        XCTAssertTrue(emittedErr.isEmpty)
        XCTAssertEqual(boqParser.lastErrorTrailer, "Boq status 13: upstream relay disconnected")

        // 2. StreamingBase64Decoder incrementally decodes outer Base64-wrapped Boq streams
        let rawOpenStream = ")]}'\n[[\"\(b64Two)\",null],"
        let b64WrappedStream = Data(Data(rawOpenStream.utf8).base64EncodedString().utf8)
        var b64Decoder = StreamingBase64Decoder()
        var innerParser = CloudRelayJSPBStreamParser()
        var decodedPayloads: [Data] = []
        for byte in b64WrappedStream {
            if let chunk = b64Decoder.feedByte(byte) {
                decodedPayloads.append(contentsOf: innerParser.feed(chunk))
            }
        }
        decodedPayloads.append(contentsOf: innerParser.feed(b64Decoder.flush()))
        XCTAssertEqual(decodedPayloads.count, 1)
        XCTAssertEqual(decodedPayloads[0], cloudFrame2)

        // 3. `mergeSummaryEntry` must NEVER let stale IDLE or stripped annotations clobber RUNNING / WAITING / isUnread
        let refNow = try XCTUnwrap(AntigravityRPCClient.parseProtoTimestamp(.string("2026-11-20T10:00:00Z")))
        let dshUnreadJSON: JSONValue = .object([
            "summary": .string("Go Version Of DSH Superagent"),
            "stepCount": .int(69),
            "status": .string("CASCADE_RUN_STATUS_IDLE"),
            "lastModifiedTime": .string("2026-11-20T09:00:00Z"),
            "annotations": .object([
                "lastUserViewTime": .string("2026-11-20T08:45:00Z")
            ]),
            "workspaces": .array([
                .object(["workspaceFolderAbsoluteUri": .string("file:///Users/dev/dsh-superagent-prototype")])
            ])
        ])
        let dshUnread = try XCTUnwrap(
            AntigravityRPCClient.decodeTrajectorySummaryEntry(
                cascadeId: "cid-dsh-go",
                value: dshUnreadJSON,
                now: refNow
            )
        )
        XCTAssertEqual(dshUnread.status, .unspecified)
        XCTAssertTrue(dshUnread.isUnread, "Idle conversation modified after lastUserViewTime must be marked unread")
        XCTAssertEqual(dshUnread.statusSubtitle, "New reply · 69 steps")

        // Annotation-stripped Jetbox frame with same stepCount must NOT clear unread or lastUserViewTime
        let dshStripped = CascadeSummary(
            cascadeId: "cid-dsh-go",
            title: "Go Version Of DSH Superagent",
            projectSlug: "dsh-superagent-prototype",
            workspaceUri: "file:///Users/dev/dsh-superagent-prototype",
            status: .unspecified,
            stepCount: 69,
            updatedAt: refNow.addingTimeInterval(-3600),
            isUnread: false,
            lastUserViewTime: nil
        )
        var mergedMap: [String: CascadeSummary] = [:]
        AntigravityRPCClient.mergeSummaryEntry(dshUnread, into: &mergedMap, cloudProjectsById: [:])
        AntigravityRPCClient.mergeSummaryEntry(dshStripped, into: &mergedMap, cloudProjectsById: [:])
        let mergedDsh = try XCTUnwrap(mergedMap["cid-dsh-go"])
        XCTAssertTrue(mergedDsh.isUnread)
        XCTAssertNotNil(mergedDsh.lastUserViewTime)
        XCTAssertEqual(mergedDsh.statusSubtitle, "New reply · 69 steps")

        // Active RUNNING session must NOT be clobbered by stale IDLE entry at equal stepCount
        let runningSummary = CascadeSummary(
            cascadeId: "cid-running-agent",
            title: "Build iOS Sync Fix",
            projectSlug: "iOSAntigravity",
            workspaceUri: "cloud://venciallee/iOSAntigravity",
            status: .inProgress,
            stepCount: 15,
            updatedAt: refNow,
            isCloud: true
        )
        let staleIdleSummary = CascadeSummary(
            cascadeId: "cid-running-agent",
            title: "Build iOS Sync Fix",
            projectSlug: "iOSAntigravity",
            workspaceUri: "cloud://venciallee/iOSAntigravity",
            status: .unspecified,
            stepCount: 15,
            updatedAt: refNow,
            isCloud: true
        )
        AntigravityRPCClient.mergeSummaryEntry(runningSummary, into: &mergedMap, cloudProjectsById: [:])
        AntigravityRPCClient.mergeSummaryEntry(staleIdleSummary, into: &mergedMap, cloudProjectsById: [:])
        XCTAssertEqual(mergedMap["cid-running-agent"]?.status, .inProgress)

        // 4. Per-instance `reconcileBatchUnreadStates` marks recent never-viewed IDLE conversation unread when siblings have lastUserViewTime
        let viewedSibling = CascadeSummary(
            cascadeId: "cid-viewed-sib",
            title: "Viewed Chat",
            projectSlug: "dsh-superagent-prototype",
            workspaceUri: "file:///Users/dev/dsh-superagent-prototype",
            status: .unspecified,
            stepCount: 10,
            updatedAt: refNow.addingTimeInterval(-7200),
            isUnread: false,
            originInstanceUuid: "mac-1",
            lastUserViewTime: refNow.addingTimeInterval(-3600)
        )
        let unviewedRecent = CascadeSummary(
            cascadeId: "cid-unviewed-recent",
            title: "Unopened Reply",
            projectSlug: "dsh-superagent-prototype",
            workspaceUri: "file:///Users/dev/dsh-superagent-prototype",
            status: .unspecified,
            stepCount: 22,
            updatedAt: refNow.addingTimeInterval(-1800),
            isUnread: false,
            originInstanceUuid: "mac-1",
            lastUserViewTime: nil
        )
        var batchMap: [String: CascadeSummary] = [
            viewedSibling.cascadeId: viewedSibling,
            unviewedRecent.cascadeId: unviewedRecent
        ]
        AntigravityRPCClient.reconcileBatchUnreadStates(&batchMap, now: refNow)
        XCTAssertFalse(batchMap["cid-viewed-sib"]?.isUnread ?? true)
        XCTAssertTrue(batchMap["cid-unviewed-recent"]?.isUnread ?? false)
        XCTAssertEqual(batchMap["cid-unviewed-recent"]?.statusSubtitle, "New reply · 22 steps")

        // 5. Cloud summary (`file:///home/antigravity/venciallee/iOSAntigravity`, no projectId) links directly to `venciallee/iOSAntigravity` Cloud project
        let cloudProject = ProjectWorkspace(
            id: "cloud-proj-uuid-ios",
            name: "venciallee/iOSAntigravity",
            pathDisplay: "cloud://venciallee/iOSAntigravity",
            workspaceUri: "cloud://venciallee/iOSAntigravity",
            runtime: .cloud,
            hostName: "Antigravity",
            activeBranch: "main",
            cloudProjectId: "cloud-proj-uuid-ios"
        )
        let decodedCloud = AntigravityRPCClient.decodeJetboxSummariesEvent(
            eventA,
            forceCloud: true,
            originInstanceUuid: "inst-1",
            originHostName: "Antigravity",
            cloudProjectsById: [cloudProject.id: cloudProject]
        )
        XCTAssertEqual(decodedCloud.upserts.count, 1)
        var cloudSummaries = decodedCloud.upserts
        let reconciledProjects = AntigravitySessionStore.reconcileLiveProjects(
            workspaces: [],
            summaries: &cloudSummaries,
            existingProjects: [],
            hostName: "lt74xt6l0m-golden-star",
            cloudProjects: [cloudProject]
        )
        XCTAssertEqual(reconciledProjects.count, 1, "Must NOT duplicate Cloud project into both venciallee/iOSAntigravity and iOSAntigravity")
        XCTAssertEqual(reconciledProjects[0].name, "venciallee/iOSAntigravity")
        XCTAssertEqual(cloudSummaries[0].projectSlug, "venciallee/iOSAntigravity")
        XCTAssertEqual(cloudSummaries[0].cloudProjectId, "cloud-proj-uuid-ios")
        XCTAssertEqual(cloudSummaries[0].status, .inProgress)
    }

    @MainActor
    func testJSONStepRequestedInteractionDecodingAndFallbackApprovals() throws {
        // 1. Outside-workspace listDirectory step with `requestedInteraction.permission` (exact live Desktop pattern)
        let permStepJSON: JSONValue = .object([
            "stepIndex": .int(77),
            "type": .string("CORTEX_STEP_TYPE_LIST_DIRECTORY"),
            "status": .string("CORTEX_STEP_STATUS_WAITING"),
            "listDirectory": .object([
                "directoryPathUri": .string("file:///Users/bytedance/Documents/workspace/dsh-superagent")
            ]),
            "requestedInteraction": .object([
                "permission": .object([
                    "action": .string("list_dir"),
                    "target": .string("/Users/bytedance/Documents/workspace/dsh-superagent"),
                    "suggestedPersistPattern": .string("/Users/bytedance/Documents/workspace/*"),
                    "reason": .string("Directory is outside current workspace")
                ])
            ])
        ])
        let permStep = try XCTUnwrap(AntigravityRPCClient.decodeJSONStep(permStepJSON, cascadeId: "cid-dsh", fallbackIndex: 77))
        XCTAssertEqual(permStep.type, .listDirectory)
        XCTAssertEqual(permStep.status, .waiting)
        XCTAssertTrue(permStep.isWaitingForUser)
        XCTAssertEqual(permStep.requestedInteraction?.kind, .permission)
        XCTAssertEqual(permStep.requestedInteraction?.permission?.action, "list_dir")
        XCTAssertEqual(permStep.requestedInteraction?.permission?.target, "/Users/bytedance/Documents/workspace/dsh-superagent")
        XCTAssertEqual(permStep.requestedInteraction?.rawMemberKey, "permission")
        XCTAssertTrue(permStep.hasRenderableChatContent)

        // Waiting evidence step MUST NOT be collapsed into an evidenceGroup
        let items = CascadeDisplayItem.buildDisplayItems(from: [permStep])
        XCTAssertEqual(items.count, 1)
        if case .single(let singleStep) = items[0] {
            XCTAssertEqual(singleStep.stepIndex, 77)
        } else {
            XCTFail("Waiting listDirectory step must remain standalone .single display item")
        }

        let permPayload = try XCTUnwrap(InteractionBuilder.buildPayload(step: permStep, decision: .allowOnce))
        XCTAssertEqual(permPayload.stepIndex, 77)
        XCTAssertEqual(permPayload.permission?.allow, true)

        // 2. Waiting runCommand where commandLine only lives inside requestedInteraction.runCommand
        let cmdStepJSON: JSONValue = .object([
            "stepIndex": .int(78),
            "type": .string("CORTEX_STEP_TYPE_RUN_COMMAND"),
            "status": .string("CORTEX_STEP_STATUS_WAITING"),
            "requestedInteraction": .object([
                "runCommand": .object([
                    "proposedCommandLine": .string("go test ./..."),
                    "cwd": .string("/Users/bytedance/Documents/workspace/dsh-superagent-prototype")
                ])
            ])
        ])
        let cmdStep = try XCTUnwrap(AntigravityRPCClient.decodeJSONStep(cmdStepJSON, cascadeId: "cid-dsh", fallbackIndex: 78))
        XCTAssertEqual(cmdStep.runCommand?.commandLine, "go test ./...")
        XCTAssertEqual(cmdStep.requestedInteraction?.kind, .runCommand)

        // 3. Unknown future interaction key preserves rawMemberKey & rawSummary verbatim
        let futureStepJSON: JSONValue = .object([
            "stepIndex": .int(79),
            "type": .string("CORTEX_STEP_TYPE_EPHEMERAL_MESSAGE"),
            "status": .string("CORTEX_STEP_STATUS_WAITING"),
            "requestedInteraction": .object([
                "customFutureGate": .object([
                    "reason": .string("Confirm external deployment trigger")
                ])
            ])
        ])
        let futureStep = try XCTUnwrap(AntigravityRPCClient.decodeJSONStep(futureStepJSON, cascadeId: "cid-dsh", fallbackIndex: 79))
        XCTAssertEqual(futureStep.requestedInteraction?.kind, .approvalInteraction)
        XCTAssertEqual(futureStep.requestedInteraction?.rawMemberKey, "customFutureGate")
        XCTAssertEqual(futureStep.requestedInteraction?.rawSummary, "Confirm external deployment trigger")
        let futurePayload = try XCTUnwrap(InteractionBuilder.buildPayload(step: futureStep, decision: .allowOnce))
        XCTAssertEqual(futurePayload.rawMemberKey, "customFutureGate")
        XCTAssertEqual(futurePayload.genericConfirm, true)

        // 4. Waiting step with NO requestedInteraction still synthesizes effectiveRequestedInteraction & payload
        let bareWaitingNotify = CascadeStep(
            cascadeId: "cid-dsh",
            stepIndex: 80,
            type: .notifyUser,
            status: .waiting,
            plannerResponse: PlannerResponsePayload(response: "Please review the architecture plan.")
        )
        XCTAssertEqual(bareWaitingNotify.effectiveRequestedInteraction?.kind, .approvalInteraction)
        let barePayload = try XCTUnwrap(InteractionBuilder.buildPayload(step: bareWaitingNotify, decision: .allowOnce))
        XCTAssertEqual(barePayload.genericConfirm, true)
        XCTAssertEqual(barePayload.stepIndex, 80)

        // 5. Store pendingWaitingStep picks latest waiting step and waitingStep(at:) matches explicit index
        let store = AntigravitySessionStore.makeESDDVerificationStore()
        store.activeCascadeId = "cid-dsh"
        store.stepsByCascadeId["cid-dsh"] = [permStep, bareWaitingNotify]
        XCTAssertEqual(store.pendingWaitingStep?.stepIndex, 80)
        XCTAssertEqual(store.waitingStep(at: 77)?.stepIndex, 77)
    }

    @MainActor
    func testPerDeviceRelayOnlineOfflineReconciliation() {
        let store = AntigravitySessionStore.makeLiveStore()
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        let initialSlugHost = RemoteHostInstance(
            instanceId: "lt74xt6l0m-golden-star",
            hostname: "lt74xt6l0m-golden-star",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/lt74xt6l0m-golden-star")!,
            isOnline: true
        )
        store.activeHost = initialSlugHost
        store.hosts = [initialSlugHost]

        let onlineHost = RelayInstanceInfo(
            uuid: "uuid-golden-star-v2",
            name: "lt74xt6l0m-golden-star",
            version: "v2.32.0",
            status: .connected
        )
        let offlineHost = RelayInstanceInfo(
            uuid: "uuid-mac-mini-v2",
            name: "huangjiafandemac-mini-local-swift-vapor",
            version: "v2.32.0",
            status: .disconnected
        )

        // 1. Reconcile snapshot with one online + one offline device; stale slug entry must be replaced without duplication
        store.syncRelayInstancesToHosts(
            [onlineHost, offlineHost],
            latencyMs: 24,
            preferredActiveInstance: onlineHost
        )
        XCTAssertEqual(store.hosts.count, 2)
        XCTAssertEqual(store.hosts.first(where: { $0.instanceId == "uuid-golden-star-v2" })?.isOnline, true)
        XCTAssertEqual(store.hosts.first(where: { $0.instanceId == "uuid-mac-mini-v2" })?.isOnline, false)
        XCTAssertEqual(store.activeHost.instanceId, "uuid-golden-star-v2")
        XCTAssertTrue(store.activeHost.isOnline)

        // 2. If a previously online host disappears from ListInstances, it must be marked offline
        let onlineMacMini = RelayInstanceInfo(
            uuid: "uuid-mac-mini-v2",
            name: "huangjiafandemac-mini-local-swift-vapor",
            version: "v2.32.0",
            status: .idle
        )
        store.syncRelayInstancesToHosts(
            [onlineMacMini],
            latencyMs: 31,
            preferredActiveInstance: onlineMacMini
        )
        XCTAssertEqual(store.hosts.first(where: { $0.instanceId == "uuid-golden-star-v2" })?.isOnline, false)
        XCTAssertEqual(store.hosts.first(where: { $0.instanceId == "uuid-mac-mini-v2" })?.isOnline, true)
        XCTAssertEqual(store.activeHost.instanceId, "uuid-mac-mini-v2")

        // 3. When the Cloud Relay backend goes offline, all Cloud Relay devices & availableRelayInstances must flip offline
        store.markBackendOffline(error: AntigravityRPCError.httpError(statusCode: 503, body: "No reachable Antigravity Desktop instances online"))
        XCTAssertTrue(store.hosts.allSatisfy { !$0.isOnline })
        XCTAssertTrue(store.availableRelayInstances.allSatisfy { !$0.status.isReachable })
    }

    func testUniversalMarkdownAgentEmbedRichHTMLMermaidCarouselAndUserScreenshotParity() throws {
        // 1. Reproduce the exact user screenshot message with inline code tokens & immediate `<agent-embed>`
        let screenshotMarkdown = """
        ### 2.2 6 层全栈对齐验收矩阵

        - 关键接口（`UserError`、`DomainEvent` 顺序、`Assessor` 判定逻辑）与老服务逐项对齐。
        - 逐表 `SELECT` + `core` 验证，禁止写死 `0`/`409`/`403` 同源头校验。
        - 全量 `go test -race ./...` 通过。
        <agent-embed src="file:///Users/bytedance/.gemini/antigravity/brain/71d80260-b9b2-4f5f-b568-5374f6aebbdd/fig4-verification-pyramid.html"></agent-embed>
        """

        let screenshotBlocks = AntigravityMarkdownParser.parse(screenshotMarkdown)
        XCTAssertEqual(screenshotBlocks.count, 5)
        if case .heading(_, let level, _) = screenshotBlocks[0] {
            XCTAssertEqual(level, 3)
        } else {
            XCTFail("Expected H3 heading at index 0")
        }
        if case .agentEmbed(_, let src, let title, let kind, _, let isIncomplete) = screenshotBlocks[4] {
            XCTAssertEqual(
                src,
                "file:///Users/bytedance/.gemini/antigravity/brain/71d80260-b9b2-4f5f-b568-5374f6aebbdd/fig4-verification-pyramid.html"
            )
            XCTAssertNil(title)
            XCTAssertEqual(kind, .htmlWidget)
            XCTAssertFalse(isIncomplete)
            XCTAssertEqual(
                AntigravityMarkdownParser.humanReadableEmbedTitle(src: src, explicitTitle: title),
                "Fig 4 · Verification Pyramid"
            )
        } else {
            XCTFail("Expected .agentEmbed at index 4, got \(screenshotBlocks[4])")
        }

        // 2. Inline `<agent-embed>` mid-paragraph splits cleanly while backticked `` `<agent-embed>` `` stays inline code
        let inlineSplit = """
        使用 `<agent-embed>` 标签渲染组件：见下方 <agent-embed src="file:///brain/chart.html" title="Latency Chart" /> 后继续说明。
        """
        let splitBlocks = AntigravityMarkdownParser.parse(inlineSplit)
        XCTAssertEqual(splitBlocks.count, 3)
        if case .paragraph(_, let leadInlines) = splitBlocks[0] {
            XCTAssertTrue(leadInlines.contains(.code("<agent-embed>")))
        } else {
            XCTFail("Expected leading paragraph with literal `<agent-embed>` code span")
        }
        if case .agentEmbed(_, let embedSrc, let embedTitle, let embedKind, _, let incomplete) = splitBlocks[1] {
            XCTAssertEqual(embedSrc, "file:///brain/chart.html")
            XCTAssertEqual(embedTitle, "Latency Chart")
            XCTAssertEqual(embedKind, .htmlWidget)
            XCTAssertFalse(incomplete)
        } else {
            XCTFail("Expected promoted .agentEmbed block")
        }

        // 3. Streaming unclosed `<agent-embed` tag mid-token does not dump raw markup
        let midStream = AntigravityMarkdownParser.parse("<agent-embed src=\"file:///brain/fig5-pending")
        XCTAssertEqual(midStream.count, 1)
        if case .agentEmbed(_, _, _, _, _, let isStreaming) = midStream[0] {
            XCTAssertTrue(isStreaming)
        } else {
            XCTFail("Expected streaming .agentEmbed placeholder")
        }

        // 4. Full universal rich blocks: plugin-card, details, carousel, mermaid, HTML table, <pre>, images, footnotes, generics
        let richDoc = """
        <!-- internal comment should be stripped -->
        Overview Heading
        ================

        Generics like Array<String> &amp; Result<Int, Error> stay intact &rarr; <kbd>⌘</kbd>+<kbd>K</kbd> <mark>highlighted</mark> <u>underlined</u> H<sub>2</sub>O x<sup>2</sup> [Ref][doc] [^1].

        <plugin-card catalog-id="github"></plugin-card>

        <details open>
        <summary>验证详情 (<b>6</b> 项)</summary>

        - <a href="https://antigravity.google.com">Antigravity</a>
        - Autolink: <https://example.com/docs>
        </details>

        ````carousel
        ![Slide 1](file:///brain/slide1.png)
        <!-- slide -->
        ```go
        func main() {}
        ```
        ````

        ```mermaid
        flowchart LR
            A[Client] --> B[Bridge]
            B --> C[LanguageServer]
        ```

        <table>
          <tr><th>Layer</th><th>Check</th></tr>
          <tr><td>L1</td><td><code>go test</code><br/>pass</td></tr>
        </table>

        <pre><code class="language-swift">let x = 1 &lt; 2</code></pre>

        <figure>
          <img src="file:///brain/arch.png" alt="Architecture" />
          <figcaption>System Architecture</figcaption>
        </figure>

        [doc]: https://antigravity.google.com/docs
        [^1]: Verified across direct LAN and Cloud Relay.
        """

        let richBlocks = AntigravityMarkdownParser.parse(richDoc)
        XCTAssertTrue(richBlocks.contains { if case .heading(_, 1, _) = $0 { return true }; return false })
        XCTAssertTrue(richBlocks.contains { if case .pluginCard(_, "github", _) = $0 { return true }; return false })
        XCTAssertTrue(richBlocks.contains { if case .details(_, _, _, true) = $0 { return true }; return false })
        XCTAssertTrue(richBlocks.contains { if case .carousel(_, let slides) = $0 { return slides.count == 2 }; return false })
        XCTAssertTrue(richBlocks.contains { if case .mermaid(_, let src) = $0 { return src.contains("flowchart LR") }; return false })
        XCTAssertTrue(richBlocks.contains { if case .table(_, let headers, _, let rows) = $0 { return headers.count == 2 && rows.count == 1 }; return false })
        XCTAssertTrue(richBlocks.contains { if case .codeBlock(_, "swift", "let x = 1 < 2") = $0 { return true }; return false })
        XCTAssertTrue(richBlocks.contains { if case .image(_, "Architecture", "file:///brain/arch.png", "System Architecture") = $0 { return true }; return false })
        XCTAssertTrue(richBlocks.contains { if case .footnoteSection(_, let items) = $0 { return items.count == 1 && items[0].label == "1" }; return false })

        // Verify programming generics were NOT stripped and inline HTML tags parsed cleanly
        if case .paragraph(_, let pInlines) = richBlocks[1] {
            let plain = pInlines.map(\.plainText).joined()
            XCTAssertTrue(plain.contains("Array<String> & Result<Int, Error>"))
            XCTAssertTrue(plain.contains("→"))
            XCTAssertTrue(pInlines.contains(.keyboardKey("⌘")))
            XCTAssertTrue(pInlines.contains(.highlight([.text("highlighted")])))
            XCTAssertTrue(pInlines.contains(.underline([.text("underlined")])))
            XCTAssertTrue(pInlines.contains(.subscriptText("2")))
            XCTAssertTrue(pInlines.contains(.superscript("2")))
            XCTAssertTrue(pInlines.contains(.footnoteRef("1")))
            XCTAssertTrue(pInlines.contains(.link(label: [.text("Ref")], destination: "https://antigravity.google.com/docs")))
        } else {
            XCTFail("Expected paragraph with generics and inline HTML at index 1")
        }
    }

    @MainActor
    func testEmbedArtifactHarvestingAndFourTierResourceResolution() async throws {
        // 1. JSON `decodeJSONStep` harvests newly created HTML artifact from `actionResult.edit.diff.unifiedDiff.lines`
        let htmlArtifactURI = "file:///Users/bytedance/.gemini/antigravity/brain/71d80260-b9b2-4f5f-b568-5374f6aebbdd/fig4-verification-pyramid.html"
        let createArtifactStepJSON: JSONValue = .object([
            "stepIndex": .int(5),
            "type": .string("CORTEX_STEP_TYPE_CODE_ACTION"),
            "status": .string("CORTEX_STEP_STATUS_DONE"),
            "codeAction": .object([
                "targetFileUri": .string(htmlArtifactURI),
                "description": .string("Create verification pyramid interactive diagram"),
                "actionResult": .object([
                    "edit": .object([
                        "diff": .object([
                            "unifiedDiff": .object([
                                "lines": .array([
                                    .object(["text": .string("<!doctype html>"), "type": .string("DIFF_LINE_TYPE_INSERT")]),
                                    .object(["text": .string("<html><body><h1>Verification Pyramid</h1></body></html>"), "type": .string("DIFF_LINE_TYPE_INSERT")])
                                ])
                            ])
                        ])
                    ])
                ])
            ])
        ])
        let decodedArtifactStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(createArtifactStepJSON, cascadeId: "cid-pyramid", fallbackIndex: 5)
        )
        XCTAssertEqual(decodedArtifactStep.codeAction?.isArtifactFile, true)
        XCTAssertTrue(decodedArtifactStep.codeAction?.fileContent?.contains("Verification Pyramid") == true)

        // 2. Live `taskBoundary` JSON & Protobuf decoding does NOT inject fake `1/4` or `4/7` fixture counts
        let liveTaskJSON: JSONValue = .object([
            "stepIndex": .int(6),
            "type": .string("CORTEX_STEP_TYPE_TASK_BOUNDARY"),
            "status": .string("CORTEX_STEP_STATUS_IN_PROGRESS"),
            "taskBoundary": .object([
                "taskName": .string("Running 6-layer verification"),
                "taskStatus": .string("Executing go test -race"),
                "taskSummary": .string("Checking SQL parity across 12 tables")
            ])
        ])
        let decodedTask = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(liveTaskJSON, cascadeId: "cid-pyramid", fallbackIndex: 6)
        )
        XCTAssertEqual(decodedTask.taskBoundary?.completedCount, 0)
        XCTAssertEqual(decodedTask.taskBoundary?.totalCount, 0)
        XCTAssertEqual(decodedTask.taskBoundary?.elapsedLabel, "")

        // 3. AntigravitySessionStore harvests trajectory steps and resolves via 4-tier pipeline
        let store = AntigravitySessionStore.makeLiveStore()
        store.harvestEmbedResources(from: [decodedArtifactStep])

        // Tier 1a: exact URI match
        let resolvedExact = await store.resolveEmbedResource(uri: htmlArtifactURI)
        XCTAssertEqual(resolvedExact?.source, .trajectoryStep)
        XCTAssertEqual(resolvedExact?.isHTML, true)
        XCTAssertTrue(resolvedExact?.textContent?.contains("Verification Pyramid") == true)

        // Tier 1b: cross-host home prefix match (`/brain/.../<filename>`)
        let resolvedCrossHost = await store.resolveEmbedResource(
            uri: "file:///home/antigravity/.gemini/antigravity/brain/other-id/fig4-verification-pyramid.html"
        )
        XCTAssertEqual(resolvedCrossHost?.source, .trajectoryStep)

        // Tier 2: inline `data:` URI (base64 SVG)
        let svgB64 = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><circle r=\"10\"/></svg>".utf8).base64EncodedString()
        let resolvedData = await store.resolveEmbedResource(uri: "data:image/svg+xml;base64,\(svgB64)")
        XCTAssertEqual(resolvedData?.source, .inlineDataURI)
        XCTAssertEqual(resolvedData?.isSVG, true)
        XCTAssertTrue(resolvedData?.textContent?.contains("<svg") == true)

        // Tier 3: direct HTTPS URL
        let resolvedHTTP = await store.resolveEmbedResource(uri: "https://antigravity.google.com/preview/widget")
        XCTAssertEqual(resolvedHTTP?.source, .directNetwork)
    }

    @MainActor
    func testRelayDeviceRenamePropagationAndFastSync() async throws {
        // 1. Decode renamed JSPB ListInstances payload and protojson object fallback with explicit deviceName
        let renamedJSPB = Data(
            ")]}'\n[[[\"uuid-macbook\",[\"Venciallee\",\"2.34.0\",1],1,[1794406200,0]],[\"uuid-macmini\",[\"huangjiafandemac-mini-local-swift-vapor\",\"2.34.0\",1],2,[1794406100,0]]],5]".utf8
        )
        let decodedJSPB = try CloudRelayJSPBCodec.decodeListInstancesResponse(renamedJSPB)
        XCTAssertEqual(decodedJSPB.count, 2)
        XCTAssertEqual(decodedJSPB[0].name, "Venciallee")
        XCTAssertEqual(decodedJSPB[0].version, "2.34.0")
        XCTAssertEqual(decodedJSPB[0].status, .connected)
        XCTAssertEqual(decodedJSPB[1].status, .disconnected)

        let protoJSONObject = Data("""
        {
          "instances": [
            {
              "instanceId": "uuid-macbook",
              "metadata": {
                "hostname": "lt74xt6l0m-golden-star",
                "deviceName": "Venciallee",
                "version": "2.34.0",
                "supportsChunking": true
              },
              "status": "CONNECTED"
            }
          ]
        }
        """.utf8)
        let decodedObj = try CloudRelayJSPBCodec.decodeListInstancesResponse(protoJSONObject)
        XCTAssertEqual(decodedObj.count, 1)
        XCTAssertEqual(decodedObj[0].name, "Venciallee")
        XCTAssertEqual(decodedObj[0].status, .connected)

        // 2. End-to-end RPC client: ListInstances rename triggers relayMetadataChanged & propagates to workspaces
        let currentDeviceName = AtomicTestString("lt74xt6l0m-golden-star")
        MockRelayURLProtocol.state.setResponder { urlString, _, body in
            if urlString.contains("/ListInstances") {
                let deviceName = currentDeviceName.get()
                let payload = ")]}'\n[[[\"uuid-macbook\",[\"\(deviceName)\",\"2.34.0\",1],1,[1794406200,0]],[\"uuid-macmini\",[\"huangjiafandemac-mini-local-swift-vapor\",\"2.34.0\",1],2,[1794406100,0]]],5]"
                return (200, ["Content-Type": "application/json+protobuf"], Data(payload.utf8))
            }
            if urlString.contains("/ProxyCommand") {
                let bodyText = String(data: body, encoding: .utf8) ?? ""
                let innerJSON: String
                if bodyText.contains("GetWorkspaceInfos") {
                    innerJSON = #"{"workspaceInfos":[{"workspaceFolderAbsoluteUri":"file:///Users/dev/code/iOSAntigravity","gitBranch":"main"}]}"#
                } else if bodyText.contains("GetAllCascadeTrajectories") {
                    innerJSON = #"{"trajectorySummaries":{"cas-sync-1":{"summary":"Sync test","stepCount":2,"status":"CASCADE_RUN_STATUS_DONE","workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/dev/code/iOSAntigravity"}]}}}"#
                } else {
                    innerJSON = "{}"
                }
                let encodedInner = Data(innerJSON.utf8).base64EncodedString()
                let jspb = ")]}'\n[\"\(encodedInner)\",[[\"content-type\",\"application/json\"]]]"
                return (200, ["Content-Type": "application/json+protobuf"], Data(jspb.utf8))
            }
            return (200, ["Content-Type": "application/json"], Data("{}".utf8))
        }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockRelayURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        defer {
            MockRelayURLProtocol.state.setResponder(nil)
            mockSession.invalidateAndCancel()
        }

        let initialHost = RemoteHostInstance(
            instanceId: "uuid-macbook",
            hostname: "lt74xt6l0m-golden-star",
            version: "2.34.0",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/uuid-macbook")!,
            isOnline: true
        )
        let rpcClient = AntigravityRPCClient(
            host: initialHost,
            sessionCookie: "SAPISID=test_sid; SID=test_sid",
            authUser: "0",
            resolvedInstanceUuid: "uuid-macbook",
            urlSession: mockSession
        )

        let firstProbe = try await rpcClient.probeHostReachability(timeoutInterval: 5.0)
        XCTAssertEqual(firstProbe.activeRelayInstance?.name, "lt74xt6l0m-golden-star")

        currentDeviceName.set("Venciallee")
        let renamedProbe = try await rpcClient.probeHostReachability(timeoutInterval: 5.0)
        XCTAssertEqual(renamedProbe.activeRelayInstance?.name, "Venciallee")
        XCTAssertFalse(renamedProbe.relayTopologyChanged)
        XCTAssertTrue(renamedProbe.relayMetadataChanged)

        let federated = try await rpcClient.fetchFederatedWorkspacesAndSummaries(
            timeoutInterval: 5.0,
            skipRelayListRefresh: true
        )
        let snapshot = await rpcClient.currentRelayInstancesSnapshot()
        XCTAssertEqual(snapshot.active?.name, "Venciallee")
        XCTAssertEqual(snapshot.instances.first(where: { $0.uuid == "uuid-macbook" })?.name, "Venciallee")
        XCTAssertEqual(federated.workspaces.first?.originHostName, "Venciallee")

        // 3. AntigravitySessionStore in-place rename propagates to activeHost, hosts, projects, summaries & workspaces
        let store = AntigravitySessionStore.makeLiveStore()
        store.isVerificationMode = true
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.activeHost = initialHost
        let peerMiniHost = RemoteHostInstance(
            instanceId: "uuid-macmini",
            hostname: "huangjiafandemac-mini-local-swift-vapor",
            version: "2.34.0",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/uuid-macmini")!,
            isOnline: false
        )
        store.hosts = [initialHost, peerMiniHost]
        store.workspaces = [
            WorkspaceInfo(
                workspaceUri: "file:///Users/dev/code/iOSAntigravity",
                displayName: "iOSAntigravity",
                activeBranch: "main",
                isCloud: false,
                originInstanceUuid: "uuid-macbook",
                originHostName: "lt74xt6l0m-golden-star"
            )
        ]
        store.projects = [
            ProjectWorkspace(
                id: "iOSAntigravity",
                name: "iOSAntigravity",
                pathDisplay: "/Users/dev/code/iOSAntigravity",
                workspaceUri: "file:///Users/dev/code/iOSAntigravity",
                runtime: .macBookPro,
                hostName: "lt74xt6l0m-golden-star",
                originInstanceUuid: "uuid-macbook"
            ),
            ProjectWorkspace(
                id: "mini-project",
                name: "mini-project",
                pathDisplay: "/Users/mini/code/mini-project",
                workspaceUri: "file:///Users/mini/code/mini-project",
                runtime: .macBookPro,
                hostName: "huangjiafandemac-mini-local-swift-vapor",
                originInstanceUuid: "uuid-macmini"
            )
        ]
        store.summaries = [
            CascadeSummary(
                cascadeId: "cas-macbook-1",
                title: "Fix rename sync",
                projectSlug: "iOSAntigravity",
                workspaceUri: "file:///Users/dev/code/iOSAntigravity",
                status: .done,
                stepCount: 4,
                isCloud: false,
                originInstanceUuid: "uuid-macbook",
                originHostName: "lt74xt6l0m-golden-star"
            ),
            CascadeSummary(
                cascadeId: "cas-macmini-1",
                title: "Mini task",
                projectSlug: "mini-project",
                workspaceUri: "file:///Users/mini/code/mini-project",
                status: .done,
                stepCount: 2,
                isCloud: false,
                originInstanceUuid: "uuid-macmini",
                originHostName: "huangjiafandemac-mini-local-swift-vapor"
            )
        ]

        store.syncRelayInstancesToHosts(
            snapshot.instances,
            latencyMs: 24,
            preferredActiveInstance: snapshot.active,
            persistKeychainIfChanged: false
        )

        XCTAssertEqual(store.activeHost.hostname, "Venciallee")
        XCTAssertEqual(store.resolvedHostName(forInstanceUuid: "uuid-macbook"), "Venciallee")
        XCTAssertTrue(store.isHostOnline(forInstanceUuid: "uuid-macbook"))
        XCTAssertFalse(store.isHostOnline(forInstanceUuid: "uuid-macmini"))
        XCTAssertEqual(store.projects[0].hostName, "Venciallee")
        XCTAssertEqual(store.projects[1].hostName, "huangjiafandemac-mini-local-swift-vapor")
        XCTAssertEqual(store.summaries[0].originHostName, "Venciallee")
        XCTAssertEqual(store.summaries[1].originHostName, "huangjiafandemac-mini-local-swift-vapor")
        XCTAssertEqual(store.workspaces[0].originHostName, "Venciallee")

        // 4. UUID-rotated rename remaps active local models cleanly without clobbering peer Mac
        let rotatedInstances = [
            RelayInstanceInfo(uuid: "uuid-venciallee-v2", name: "Venciallee-Pro", version: "2.34.0", status: .connected),
            RelayInstanceInfo(uuid: "uuid-macmini", name: "huangjiafandemac-mini-local-swift-vapor", version: "2.34.0", status: .disconnected)
        ]
        store.syncRelayInstancesToHosts(
            rotatedInstances,
            latencyMs: 19,
            preferredActiveInstance: rotatedInstances[0],
            persistKeychainIfChanged: false
        )

        XCTAssertEqual(store.activeHost.instanceId, "uuid-venciallee-v2")
        XCTAssertEqual(store.activeHost.hostname, "Venciallee-Pro")
        XCTAssertEqual(store.hosts.first(where: { $0.instanceId == "uuid-macbook" })?.isOnline, false)
        XCTAssertEqual(store.projects[0].originInstanceUuid, "uuid-venciallee-v2")
        XCTAssertEqual(store.projects[0].hostName, "Venciallee-Pro")
        XCTAssertEqual(store.summaries[0].originInstanceUuid, "uuid-venciallee-v2")
        XCTAssertEqual(store.summaries[0].originHostName, "Venciallee-Pro")
        XCTAssertEqual(store.projects[1].originInstanceUuid, "uuid-macmini")
        XCTAssertEqual(store.projects[1].hostName, "huangjiafandemac-mini-local-swift-vapor")
    }

    @MainActor
    func testMultiHostProjectIsolationAndScopedCounters() throws {
        XCTAssertEqual(AntigravityCloudDetector.stripProjectScopePrefix("host:uuid-1:No Project"), "No Project")
        XCTAssertEqual(AntigravityCloudDetector.stripProjectScopePrefix("host:uuid-1:iOSAntigravity"), "iOSAntigravity")
        XCTAssertEqual(AntigravityCloudDetector.stripProjectScopePrefix("cloud:No Project"), "No Project")
        XCTAssertTrue(AntigravityCloudDetector.isNoProjectSlug("host:uuid-1:No Project"))
        XCTAssertFalse(AntigravityCloudDetector.isNoProjectSlug("host:uuid-1:iOSAntigravity"))

        let now = Date()
        let miniUuid = "uuid-mac-mini-v2"
        let miniName = "huangjiafandemac-mini-local-swift-vapor"
        let goldenUuid = "uuid-golden-star-v2"
        let goldenName = "lt74xt6l0m-golden-star"

        let workspaces: [WorkspaceInfo] = [
            WorkspaceInfo(
                workspaceUri: "file:///Users/dev/iOSAntigravity",
                displayName: "iOSAntigravity",
                activeBranch: "main",
                isCloud: false,
                originInstanceUuid: miniUuid,
                originHostName: miniName
            ),
            WorkspaceInfo(
                workspaceUri: "file:///Users/dev/iOSAntigravity",
                displayName: "iOSAntigravity",
                activeBranch: "feature/host-switch",
                isCloud: false,
                originInstanceUuid: goldenUuid,
                originHostName: goldenName
            )
        ]

        var summaries: [CascadeSummary] = [
            CascadeSummary(
                cascadeId: "cid-mini-running",
                title: "Mac mini running build",
                projectSlug: "iOSAntigravity",
                workspaceUri: "file:///Users/dev/iOSAntigravity",
                branchName: "main",
                status: .inProgress,
                stepCount: 5,
                updatedAt: now,
                isUnread: false,
                isCloud: false,
                originInstanceUuid: miniUuid,
                originHostName: miniName
            ),
            CascadeSummary(
                cascadeId: "cid-mini-noproj",
                title: "Mac mini waiting command",
                projectSlug: "No Project",
                workspaceUri: "",
                branchName: "",
                status: .waiting,
                stepCount: 3,
                updatedAt: now.addingTimeInterval(-60),
                isUnread: false,
                isCloud: false,
                originInstanceUuid: miniUuid,
                originHostName: miniName
            ),
            CascadeSummary(
                cascadeId: "cid-golden-done",
                title: "Golden Star completed refactor",
                projectSlug: "iOSAntigravity",
                workspaceUri: "file:///Users/dev/iOSAntigravity",
                branchName: "feature/host-switch",
                status: .done,
                stepCount: 8,
                updatedAt: now.addingTimeInterval(-120),
                isUnread: true,
                isCloud: false,
                originInstanceUuid: goldenUuid,
                originHostName: goldenName
            ),
            CascadeSummary(
                cascadeId: "cid-golden-noproj",
                title: "Golden Star scratch chat",
                projectSlug: "No Project",
                workspaceUri: "",
                branchName: "",
                status: .done,
                stepCount: 2,
                updatedAt: now.addingTimeInterval(-180),
                isUnread: false,
                isCloud: false,
                originInstanceUuid: goldenUuid,
                originHostName: goldenName
            ),
            CascadeSummary(
                cascadeId: "cid-cloud-noproj",
                title: "Cloud quick task",
                projectSlug: "No Project",
                workspaceUri: "",
                branchName: "",
                status: .done,
                stepCount: 4,
                updatedAt: now.addingTimeInterval(-240),
                isUnread: true,
                isCloud: true,
                originInstanceUuid: miniUuid,
                originHostName: "Antigravity"
            )
        ]

        let reconciled = AntigravitySessionStore.reconcileLiveProjects(
            workspaces: workspaces,
            summaries: &summaries,
            existingProjects: [],
            hostName: miniName
        )

        let miniProj = try XCTUnwrap(reconciled.first(where: { $0.id == "host:\(miniUuid):iOSAntigravity" }))
        let goldenProj = try XCTUnwrap(reconciled.first(where: { $0.id == "host:\(goldenUuid):iOSAntigravity" }))
        let miniNoProj = try XCTUnwrap(reconciled.first(where: { $0.id == "host:\(miniUuid):No Project" }))
        let goldenNoProj = try XCTUnwrap(reconciled.first(where: { $0.id == "host:\(goldenUuid):No Project" }))
        let cloudNoProj = try XCTUnwrap(reconciled.first(where: { $0.id == "cloud:No Project" }))

        XCTAssertEqual(miniProj.name, "iOSAntigravity")
        XCTAssertEqual(miniProj.hostName, miniName)
        XCTAssertEqual(goldenProj.name, "iOSAntigravity")
        XCTAssertEqual(goldenProj.hostName, goldenName)
        XCTAssertEqual(goldenProj.activeBranch, "feature/host-switch")
        XCTAssertEqual(miniNoProj.hostName, miniName)
        XCTAssertEqual(goldenNoProj.hostName, goldenName)
        XCTAssertEqual(cloudNoProj.runtime, .cloud)

        let store = AntigravitySessionStore.makeESDDVerificationStore()
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        let miniHost = RemoteHostInstance(
            instanceId: miniUuid,
            hostname: miniName,
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(miniUuid)")!,
            isOnline: true
        )
        let goldenHost = RemoteHostInstance(
            instanceId: goldenUuid,
            hostname: goldenName,
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(goldenUuid)")!,
            isOnline: false
        )
        store.hosts = [miniHost, goldenHost]
        store.activeHost = miniHost
        store.projects = reconciled
        store.summaries = summaries

        let goldenScope = AgentsHostFilterScope.localHost(id: goldenUuid, name: goldenName)
        let miniScope = AgentsHostFilterScope.localHost(id: miniUuid, name: miniName)

        // Switching to Golden Star must NOT leak Mac mini's Running 1 or Needs you 1 badges or projects
        XCTAssertEqual(store.runningCount(for: goldenScope), 0)
        XCTAssertEqual(store.needsYouCount(for: goldenScope), 0)
        XCTAssertEqual(store.unreadCount(for: goldenScope), 1)
        XCTAssertEqual(
            Set(store.summaries.filter { store.summaryMatchesHostScope($0, scope: goldenScope) }.map(\.cascadeId)),
            ["cid-golden-done", "cid-golden-noproj"]
        )
        XCTAssertEqual(
            Set(store.projects.filter { store.projectMatchesHostScope($0, scope: goldenScope) }.map(\.id)),
            [goldenProj.id, goldenNoProj.id]
        )

        // Mac mini scope keeps its own running/needs-you badges cleanly
        XCTAssertEqual(store.runningCount(for: miniScope), 1)
        XCTAssertEqual(store.needsYouCount(for: miniScope), 1)
        XCTAssertEqual(store.unreadCount(for: miniScope), 0)

        // Cloud scope keeps only Cloud sessions
        XCTAssertEqual(store.runningCount(for: .antigravityCloud), 0)
        XCTAssertEqual(store.unreadCount(for: .antigravityCloud), 1)
        XCTAssertEqual(
            store.summaries.filter { store.summaryMatchesHostScope($0, scope: .antigravityCloud) }.map(\.cascadeId),
            ["cid-cloud-noproj"]
        )

        // Per-host online status is independent of activeHost
        XCTAssertTrue(store.isLocalHostOnline(instanceId: miniUuid, hostname: miniName))
        XCTAssertFalse(store.isLocalHostOnline(instanceId: goldenUuid, hostname: goldenName))
    }

    func testCloudRelayStrictHostIsolationNoCrossHostFailover() async throws {
        let miniUuid = "uuid-mac-mini-v2"
        let miniName = "huangjiafandemac-mini-local-swift-vapor"
        let goldenUuid = "uuid-golden-star-v2"
        let goldenName = "lt74xt6l0m-golden-star"

        let goldenOnlineFlag = AtomicTestFlag(initialValue: false)
        defer { HostIsolationMockRelayURLProtocol.storage.setHandler(nil) }

        HostIsolationMockRelayURLProtocol.storage.setHandler { request in
            let url = request.url ?? URL(string: "https://antigravity.google.com")!
            let path = url.path

            func makeResponse(status: Int, contentType: String = "application/json+protobuf") -> HTTPURLResponse {
                HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": contentType]
                )!
            }

            if path.hasSuffix("/ListInstances") {
                let goldenStatus = goldenOnlineFlag.get() ? 1 : 2
                let body = """
                [[["\(miniUuid)",["\(miniName)","v2.32.0",true],1,["1700000000",0]],["\(goldenUuid)",["\(goldenName)","v2.32.0",true],\(goldenStatus),["1700000000",0]]],10]
                """
                return (makeResponse(status: 200), Data(body.utf8))
            }

            if path.hasSuffix("/StreamProxyCommand") {
                return (makeResponse(status: 404, contentType: "text/plain"), Data("stream unsupported in unit test".utf8))
            }

            if path.hasSuffix("/ProxyCommand") {
                let reqData = HostIsolationMockRelayURLProtocol.readBody(from: request)
                let decoded = try JSONDecoder().decode(JSONValue.self, from: reqData)
                let arr = decoded.arrayValue ?? []
                let targetUuid = arr.count > 0 ? (arr[0].stringValue ?? "") : ""
                let rpcPath = arr.count > 1 ? (arr[1].stringValue ?? "") : ""

                if targetUuid == goldenUuid {
                    if !goldenOnlineFlag.get() {
                        return (makeResponse(status: 503, contentType: "text/plain"), Data("target host offline".utf8))
                    }
                    if rpcPath.contains("GetWorkspaceInfos") {
                        return (makeResponse(status: 404, contentType: "text/plain"), Data("method not implemented".utf8))
                    }
                    if rpcPath.contains("GetAllCascadeTrajectories") {
                        let json = #"{"trajectorySummaries":{"cid-golden-only":{"summary":"Golden Star Session","stepCount":4,"status":"CASCADE_RUN_STATUS_IDLE","workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/dev/iOSAntigravity"}]}}}"#
                        let b64 = Data(json.utf8).base64EncodedString()
                        let jspb = #"["\#(b64)",[["content-type","application/json"]]]"#
                        return (makeResponse(status: 200), Data(jspb.utf8))
                    }
                }

                if targetUuid == miniUuid {
                    if rpcPath.contains("GetWorkspaceInfos") {
                        let json = #"{"workspaceInfos":[{"workspaceUri":"file:///Users/dev/iOSAntigravity","branchName":"main"}]}"#
                        let b64 = Data(json.utf8).base64EncodedString()
                        let jspb = #"["\#(b64)",[["content-type","application/json"]]]"#
                        return (makeResponse(status: 200), Data(jspb.utf8))
                    }
                    if rpcPath.contains("GetAllCascadeTrajectories") {
                        let json = #"{"trajectorySummaries":{"cid-mini-only":{"summary":"Mac Mini Session","stepCount":7,"status":"CASCADE_RUN_STATUS_RUNNING","workspaces":[{"workspaceFolderAbsoluteUri":"file:///Users/dev/iOSAntigravity"}]}}}"#
                        let b64 = Data(json.utf8).base64EncodedString()
                        let jspb = #"["\#(b64)",[["content-type","application/json"]]]"#
                        return (makeResponse(status: 200), Data(jspb.utf8))
                    }
                }
            }

            return (makeResponse(status: 404, contentType: "text/plain"), Data("not found".utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HostIsolationMockRelayURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        defer { mockSession.invalidateAndCancel() }

        let goldenHost = RemoteHostInstance(
            instanceId: goldenUuid,
            hostname: goldenName,
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(goldenUuid)")!,
            isOnline: false
        )
        let client = AntigravityRPCClient(
            host: goldenHost,
            sessionCookie: "SAPISID=test-sapisid-token; __Secure-3PAPISID=test-sapisid-token",
            authUser: "0",
            resolvedInstanceUuid: goldenUuid,
            urlSession: mockSession
        )

        // 1. Offline explicit target must NOT hijack to online Mac mini when allowCrossHostFallback == false
        let resolution = try await client.resolveCloudRelayInstance(
            preferredIdentifier: goldenName,
            allowCrossHostFallback: false
        )
        XCTAssertEqual(resolution.selected.uuid, goldenUuid)
        XCTAssertFalse(resolution.selected.status.isReachable)
        XCTAssertEqual(resolution.allInstances.count, 2)

        // 2. Heartbeat probe reports isSelectedHostOnline == false while preserving goldenUuid
        let offlineProbe = try await client.probeHostReachability(allowCrossHostFallback: false)
        XCTAssertFalse(offlineProbe.isSelectedHostOnline)
        XCTAssertEqual(offlineProbe.activeRelayInstance?.uuid, goldenUuid)
        XCTAssertEqual(offlineProbe.availableRelayInstances.count, 2)

        // 3. Trajectory fetch for offline goldenUuid must throw instead of failing over to Mac mini
        do {
            _ = try await client.getAllCascadeTrajectories(
                instanceUuidOverride: goldenUuid,
                originHostName: goldenName
            )
            XCTFail("Offline host fetch must throw rather than returning peer host trajectories")
        } catch {
            // Expected 503 error
        }

        // 4. When goldenUuid comes online and GetWorkspaceInfos returns HTTP 404,
        //    targeted sync must NEVER fail over to Mac mini and must return ONLY goldenUuid's session.
        goldenOnlineFlag.set(true)
        await client.setTargetRelayInstance(uuid: goldenUuid, name: goldenName)
        let targeted = try await client.fetchFederatedWorkspacesAndSummaries(
            targetInstanceUuid: goldenUuid,
            includeLocal: true,
            includeCloud: false
        )
        XCTAssertEqual(targeted.succeededInstanceUuids, [goldenUuid])
        XCTAssertEqual(targeted.summaries.map(\.cascadeId), ["cid-golden-only"])
        XCTAssertEqual(targeted.summaries.first?.originInstanceUuid, goldenUuid)
        XCTAssertEqual(targeted.summaries.first?.originHostName, goldenName)
        let activeAfter = await client.currentActiveRelayInstance()
        XCTAssertEqual(activeAfter?.uuid, goldenUuid)
    }

    func testRelayOmittedStatusAndEndToEndProbeDowngradesOfflineHost() async throws {
        // 1. Omitted status column in JSPB ListInstances (row.count == 2) MUST decode as `.unknown` (not reachable)
        let omittedStatusJSPB = #"[[["uuid-omitted-v2","huangjiafandemac"]]]"#
        let decoded = try CloudRelayJSPBCodec.decodeListInstancesResponse(Data(omittedStatusJSPB.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].uuid, "uuid-omitted-v2")
        XCTAssertEqual(decoded[0].status, .unknown)
        XCTAssertFalse(decoded[0].status.isReachable)

        // 2. End-to-end probe (`verifyEndToEnd: true`) downgrades zombie/stale CONNECTED Mac returning HTTP 503
        let onlineUuid = "11111111-online-mini-v2"
        let zombieUuid = "22222222-zombie-mac-v2"
        let onlineName = "huangjiafandemac-mini"
        let zombieName = "huangjiafandemac"

        defer { HostIsolationMockRelayURLProtocol.storage.setHandler(nil) }
        HostIsolationMockRelayURLProtocol.storage.setHandler { request in
            let url = request.url ?? URL(string: "https://antigravity.google.com")!
            let path = url.path
            func makeResponse(status: Int, contentType: String = "application/json+protobuf") -> HTTPURLResponse {
                HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": contentType]
                )!
            }

            if path.contains("ListInstances") {
                // Both instances appear CONNECTED in stale ListInstances metadata
                let payload = #"[[["\#(onlineUuid)","\#(onlineName)",1,[1760000000,0],"2.34.0"],["\#(zombieUuid)","\#(zombieName)",1,[1760000000,0],"2.29.0"]]]"#
                return (makeResponse(status: 200), Data(payload.utf8))
            }

            if path.contains("ProxyCommand") {
                let body = HostIsolationMockRelayURLProtocol.readBody(from: request)
                let bodyText = String(data: body, encoding: .utf8) ?? ""
                if bodyText.contains(zombieUuid) {
                    return (makeResponse(status: 503, contentType: "text/plain"), Data("zombie host offline".utf8))
                }
                if bodyText.contains(onlineUuid) {
                    let json = #"{"workspaceInfos":[{"workspaceUri":"file:///Users/dev/iOSAntigravity","branchName":"main"}]}"#
                    let b64 = Data(json.utf8).base64EncodedString()
                    let jspb = #"["\#(b64)",[["content-type","application/json"]]]"#
                    return (makeResponse(status: 200), Data(jspb.utf8))
                }
            }

            return (makeResponse(status: 404, contentType: "text/plain"), Data("not found".utf8))
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HostIsolationMockRelayURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        defer { mockSession.invalidateAndCancel() }

        let host = RemoteHostInstance(
            instanceId: onlineUuid,
            hostname: onlineName,
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(onlineUuid)")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=test-sapisid-token; __Secure-3PAPISID=test-sapisid-token",
            authUser: "0",
            resolvedInstanceUuid: onlineUuid,
            urlSession: mockSession
        )

        let probe = try await client.probeHostReachability(
            allowCrossHostFallback: false,
            verifyEndToEnd: true
        )
        let probedOnline = try XCTUnwrap(probe.availableRelayInstances.first(where: { $0.uuid == onlineUuid }))
        let probedZombie = try XCTUnwrap(probe.availableRelayInstances.first(where: { $0.uuid == zombieUuid }))
        XCTAssertTrue(probedOnline.status.isReachable)
        XCTAssertEqual(probedZombie.status, .disconnected, "Zombie Relay instance returning 503 must be downgraded to .disconnected")
        XCTAssertFalse(probedZombie.status.isReachable)
    }

    @MainActor
    func testHostSwitchRefreshCoalescingAndPerHostCachePreservation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityCoalesceTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let hostAUuid = "aaaa1111-workstation-v2"
        let hostBUuid = "bbbb2222-macmini-v2"
        let hostAName = "workstation-mac"
        let hostBName = "huangjiafandemac-mini"

        let hostA = RemoteHostInstance(
            instanceId: hostAUuid,
            hostname: hostAName,
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(hostAUuid)")!,
            isOnline: true
        )
        let hostB = RemoteHostInstance(
            instanceId: hostBUuid,
            hostname: hostBName,
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(hostBUuid)")!,
            isOnline: true
        )

        let projection = LocalProjectionStore(storageDirectory: tempDir)
        let store = AntigravitySessionStore(
            hosts: [hostA, hostB],
            activeHost: hostA,
            projectionStore: projection
        )
        store.isVerificationMode = false
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.availableRelayInstances = [
            RelayInstanceInfo(uuid: hostAUuid, name: hostAName, version: "2.34.0-v2", status: .connected),
            RelayInstanceInfo(uuid: hostBUuid, name: hostBName, version: "2.34.0-v2", status: .connected)
        ]

        var initialSummaries: [CascadeSummary] = [
            CascadeSummary(
                cascadeId: "cid-a-old",
                title: "Old Host A Chat",
                projectSlug: "dsh-superagent-prototype",
                workspaceUri: "file:///Users/work/dsh-superagent-prototype",
                status: .done,
                stepCount: 3,
                isCloud: false,
                originInstanceUuid: hostAUuid,
                originHostName: hostAName
            ),
            CascadeSummary(
                cascadeId: "cid-b-cached",
                title: "Cached Host B Chat",
                projectSlug: "game_loop",
                workspaceUri: "file:///Users/mini/game_loop",
                status: .done,
                stepCount: 5,
                isCloud: false,
                originInstanceUuid: hostBUuid,
                originHostName: hostBName
            )
        ]
        store.projects = AntigravitySessionStore.reconcileLiveProjects(
            workspaces: [],
            summaries: &initialSummaries,
            existingProjects: [],
            hostName: hostAName
        )
        store.summaries = initialSummaries

        let scopeA = AgentsHostFilterScope.localHost(id: hostAUuid, name: hostAName)
        let scopeB = AgentsHostFilterScope.localHost(id: hostBUuid, name: hostBName)
        let coordinator = HostRefreshTestCoordinator(pausedKeys: [scopeA.id, scopeB.id])

        store.hostRefreshExecutorOverrideForTesting = { target in
            await coordinator.enterAndWait(key: target.id)
            switch target {
            case .localHost(let id, let name) where id == hostAUuid:
                return ScopedWorkspaceSyncResult(
                    workspaces: [
                        WorkspaceInfo(
                            workspaceUri: "file:///Users/work/dsh-superagent-prototype",
                            displayName: "dsh-superagent-prototype",
                            activeBranch: "main",
                            isCloud: false,
                            originInstanceUuid: hostAUuid,
                            originHostName: hostAName
                        )
                    ],
                    summaries: [
                        CascadeSummary(
                            cascadeId: "cid-a-fresh",
                            title: "Fresh Host A Chat",
                            projectSlug: "dsh-superagent-prototype",
                            workspaceUri: "file:///Users/work/dsh-superagent-prototype",
                            status: .inProgress,
                            stepCount: 9,
                            isCloud: false,
                            originInstanceUuid: id,
                            originHostName: name
                        )
                    ],
                    refreshedLocalHostUuids: [hostAUuid],
                    refreshedLocalHostNames: [hostAName],
                    refreshedCloud: false,
                    targetReachable: true,
                    latencyMs: 14
                )
            case .localHost(let id, let name) where id == hostBUuid:
                return ScopedWorkspaceSyncResult(
                    workspaces: [
                        WorkspaceInfo(
                            workspaceUri: "file:///Users/mini/game_loop",
                            displayName: "game_loop",
                            activeBranch: "main",
                            isCloud: false,
                            originInstanceUuid: hostBUuid,
                            originHostName: hostBName
                        )
                    ],
                    summaries: [
                        CascadeSummary(
                            cascadeId: "cid-b-fresh",
                            title: "Fresh Host B Chat",
                            projectSlug: "game_loop",
                            workspaceUri: "file:///Users/mini/game_loop",
                            status: .done,
                            stepCount: 8,
                            isCloud: false,
                            originInstanceUuid: id,
                            originHostName: name
                        )
                    ],
                    refreshedLocalHostUuids: [hostBUuid],
                    refreshedLocalHostNames: [hostBName],
                    refreshedCloud: false,
                    targetReachable: true,
                    latencyMs: 19
                )
            default:
                return ScopedWorkspaceSyncResult(workspaces: [], summaries: [])
            }
        }

        // Fire rapid A -> A -> B -> A concurrent refreshes: same-device requests MUST coalesce!
        async let reqA1 = store.refreshConversationsForHostScope(scopeA, forceFullSync: true)
        async let reqA2 = store.refreshConversationsForHostScope(scopeA, forceFullSync: true)
        async let reqB1 = store.refreshConversationsForHostScope(scopeB, forceFullSync: true)
        async let reqA3 = store.refreshConversationsForHostScope(scopeA, forceFullSync: true)

        await coordinator.waitUntilEntered(key: scopeA.id)
        await coordinator.waitUntilEntered(key: scopeB.id)
        XCTAssertTrue(store.isRefreshingHost(instanceId: hostAUuid, hostname: hostAName))
        XCTAssertTrue(store.isRefreshingHost(instanceId: hostBUuid, hostname: hostBName))

        await coordinator.release(key: scopeA.id)
        let (okA1, okA2, okA3) = await (reqA1, reqA2, reqA3)
        XCTAssertTrue(okA1 && okA2 && okA3)

        // After ONLY Host A finishes, Host A updated to cid-a-fresh while Host B's cached cid-b-cached is untouched!
        XCTAssertTrue(store.summaries.contains(where: { $0.cascadeId == "cid-a-fresh" }))
        XCTAssertFalse(store.summaries.contains(where: { $0.cascadeId == "cid-a-old" }))
        XCTAssertTrue(store.summaries.contains(where: { $0.cascadeId == "cid-b-cached" }))

        await coordinator.release(key: scopeB.id)
        let okB1 = await reqB1
        XCTAssertTrue(okB1)

        // Exactly 1 RPC executed for Host A (3 concurrent callers coalesced) and 1 for Host B!
        let countA = await coordinator.count(for: scopeA.id)
        let countB = await coordinator.count(for: scopeB.id)
        XCTAssertEqual(countA, 1, "Rapid repeated switches to Host A must coalesce into a single in-flight RPC")
        XCTAssertEqual(countB, 1, "Independent Host B refresh must run once without cancelling Host A")
        XCTAssertEqual(Set(store.summaries.map(\.cascadeId)), ["cid-a-fresh", "cid-b-fresh"])
    }

    @MainActor
    func testPerHostShardedDiskCacheColdStartHydrationAndOfflineStepReading() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityShardedCacheTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let hostAUuid = "11111111-aaaa-4444-8888-workstation-v2"
        let hostBUuid = "22222222-bbbb-4444-8888-macmini-v2"
        let hostAName = "workstation-mac"
        let hostBName = "huangjiafandemac-mini"

        let hostA = RemoteHostInstance(
            instanceId: hostAUuid,
            hostname: hostAName,
            version: "2.34.0-v2",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(hostAUuid)")!,
            isOnline: true
        )
        let hostB = RemoteHostInstance(
            instanceId: hostBUuid,
            hostname: hostBName,
            version: "2.29.0-v2",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(hostBUuid)")!,
            isOnline: false
        )

        // 1. Seed per-host disk shards for online Mac A, offline Mac B, and Antigravity Cloud + cached steps for Mac B
        let projection1 = LocalProjectionStore(storageDirectory: tempDir)
        let store1 = AntigravitySessionStore(
            hosts: [hostA, hostB],
            activeHost: hostA,
            projectionStore: projection1
        )
        store1.isVerificationMode = false
        store1.hasPairedBackend = true
        store1.isLiveBackendConnected = true
        store1.availableRelayInstances = [
            RelayInstanceInfo(uuid: hostAUuid, name: hostAName, version: "2.34.0-v2", status: .connected),
            RelayInstanceInfo(uuid: hostBUuid, name: hostBName, version: "2.29.0-v2", status: .disconnected)
        ]

        var seedSummaries: [CascadeSummary] = [
            CascadeSummary(
                cascadeId: "cid-a-1",
                title: "Workstation Initial Chat",
                projectSlug: "dsh-superagent-prototype",
                workspaceUri: "file:///Users/work/dsh-superagent-prototype",
                status: .done,
                stepCount: 4,
                isCloud: false,
                originInstanceUuid: hostAUuid,
                originHostName: hostAName
            ),
            CascadeSummary(
                cascadeId: "cid-b-cached",
                title: "Mac Mini Cached Transcript",
                projectSlug: "game_loop",
                workspaceUri: "file:///Users/mini/game_loop",
                status: .done,
                stepCount: 2,
                isCloud: false,
                originInstanceUuid: hostBUuid,
                originHostName: hostBName
            ),
            CascadeSummary(
                cascadeId: "cid-b-uncached",
                title: "Mac Mini Uncached Transcript",
                projectSlug: "game_loop",
                workspaceUri: "file:///Users/mini/game_loop",
                status: .done,
                stepCount: 6,
                isCloud: false,
                originInstanceUuid: hostBUuid,
                originHostName: hostBName
            ),
            CascadeSummary(
                cascadeId: "v1/default/jetski_remote_agents_3p/cid-cloud-1",
                title: "Cloud Remote Session",
                projectSlug: "iOSAntigravity",
                workspaceUri: "cloud://venciallee/iOSAntigravity",
                status: .done,
                stepCount: 3,
                isCloud: true,
                originHostName: "Antigravity"
            )
        ]
        store1.projects = AntigravitySessionStore.reconcileLiveProjects(
            workspaces: [],
            summaries: &seedSummaries,
            existingProjects: [],
            hostName: hostAName
        )
        store1.summaries = seedSummaries
        await store1.persistHostProjections()

        let cachedMiniSteps: [CascadeStep] = [
            CascadeStep(
                cascadeId: "cid-b-cached",
                stepIndex: 0,
                type: .userInput,
                status: .done,
                userInput: "Summarize swift-vapor build status"
            ),
            CascadeStep(
                cascadeId: "cid-b-cached",
                stepIndex: 1,
                type: .plannerResponse,
                status: .done,
                plannerResponse: PlannerResponsePayload(
                    response: "All Vapor routes compiled cleanly on Mac mini."
                )
            )
        ]
        await projection1.saveProjectedSteps(cachedMiniSteps, for: "cid-b-cached")

        let loadedInitialShardB = await projection1.loadHostProjection(hostKey: "host:\(hostBUuid)")
        let initialShardB = try XCTUnwrap(loadedInitialShardB)
        XCTAssertEqual(Set(initialShardB.summaries.map(\.cascadeId)), ["cid-b-cached", "cid-b-uncached"])

        // 2. Refresh ONLY online Mac A while Mac B is offline -> Mac A's shard updates, Mac B's shard on disk stays untouched!
        store1.hostRefreshExecutorOverrideForTesting = { target in
            XCTAssertEqual(target, .localHost(id: hostAUuid, name: hostAName))
            let updatedA = CascadeSummary(
                cascadeId: "cid-a-2",
                title: "Workstation Fresh Chat",
                projectSlug: "dsh-superagent-prototype",
                workspaceUri: "file:///Users/work/dsh-superagent-prototype",
                status: .inProgress,
                stepCount: 11,
                isCloud: false,
                originInstanceUuid: hostAUuid,
                originHostName: hostAName
            )
            return ScopedWorkspaceSyncResult(
                workspaces: [
                    WorkspaceInfo(
                        workspaceUri: "file:///Users/work/dsh-superagent-prototype",
                        displayName: "dsh-superagent-prototype",
                        activeBranch: "main",
                        isCloud: false,
                        originInstanceUuid: hostAUuid,
                        originHostName: hostAName
                    )
                ],
                summaries: [updatedA],
                relayInstances: [
                    RelayInstanceInfo(uuid: hostAUuid, name: hostAName, version: "2.34.0-v2", status: .connected),
                    RelayInstanceInfo(uuid: hostBUuid, name: hostBName, version: "2.29.0-v2", status: .disconnected)
                ],
                refreshedLocalHostUuids: [hostAUuid],
                refreshedLocalHostNames: [hostAName],
                refreshedCloud: false,
                targetReachable: true,
                latencyMs: 18
            )
        }
        let refreshedA = await store1.refreshConversationsForHostScope(.localHost(id: hostAUuid, name: hostAName))
        XCTAssertTrue(refreshedA)

        // Verify disk shards independently via a fresh LocalProjectionStore instance (cold disk read)
        let coldProjection = LocalProjectionStore(storageDirectory: tempDir)
        let coldShards = await coldProjection.loadAllHostProjections()
        XCTAssertEqual(Set(coldShards.map(\.hostKey)), ["host:\(hostAUuid)", "host:\(hostBUuid)", "cloud"])
        let loadedShardAOnDisk = await coldProjection.loadHostProjection(hostKey: "host:\(hostAUuid)")
        let loadedShardBOnDisk = await coldProjection.loadHostProjection(hostKey: "host:\(hostBUuid)")
        let shardAOnDisk = try XCTUnwrap(loadedShardAOnDisk)
        let shardBOnDisk = try XCTUnwrap(loadedShardBOnDisk)
        XCTAssertEqual(shardAOnDisk.summaries.map(\.cascadeId), ["cid-a-2"])
        XCTAssertEqual(Set(shardBOnDisk.summaries.map(\.cascadeId)), ["cid-b-cached", "cid-b-uncached"])
        XCTAssertEqual(
            shardBOnDisk.updatedAt.timeIntervalSinceReferenceDate,
            initialShardB.updatedAt.timeIntervalSinceReferenceDate,
            accuracy: 0.001,
            "Refreshing online Mac A must not rewrite offline Mac B's shard file"
        )

        // 3. Cold Launch Simulation (brand-new store with empty memory): instant disk hydration BEFORE any network call!
        let placeholder = RemoteHostInstance(
            instanceId: "unpaired",
            hostname: "Antigravity Desktop",
            channel: .cloudRelay,
            endpointURL: URL(string: SAPISIDHashGenerator.defaultOrigin)!,
            isOnline: false
        )
        let coldStore = AntigravitySessionStore(
            hosts: [],
            activeHost: placeholder,
            projectionStore: coldProjection
        )
        coldStore.isVerificationMode = false

        let savedCreds = SavedBackendCredentials(
            endpointURLString: "https://antigravity.google.com/r/\(hostAUuid)",
            channel: .cloudRelay,
            hostname: hostAName,
            sessionCookie: "SAPISID=test",
            authUser: "0",
            resolvedInstanceUuid: hostAUuid
        )
        await coldStore.hydratePersistedHostProjectionsIfNeeded(savedCredentials: savedCreds)

        XCTAssertTrue(coldStore.hasPairedBackend)
        XCTAssertTrue(coldStore.isInitialSessionCheckComplete, "Cold-start hydration must unblock Home immediately before handshake finishes")
        XCTAssertFalse(coldStore.isLiveBackendConnected)
        XCTAssertEqual(Set(coldStore.pairedLocalHosts.map(\.instanceId)), [hostAUuid, hostBUuid])
        XCTAssertTrue(coldStore.pairedLocalHosts.allSatisfy { !$0.isOnline }, "Hosts stay Offline until live handshake confirms reachability")
        XCTAssertEqual(
            Set(coldStore.summaries.map(\.cascadeId)),
            ["cid-a-2", "cid-b-cached", "cid-b-uncached", "v1/default/jetski_remote_agents_3p/cid-cloud-1"]
        )
        XCTAssertTrue(coldStore.projects.contains(where: { $0.name == "game_loop" }))
        XCTAssertTrue(coldStore.projects.contains(where: { $0.name == "dsh-superagent-prototype" }))

        // 4. Online Mac A connects while Mac B stays offline -> opening Mac B's cached conversation reads disk steps cleanly!
        coldStore.isLiveBackendConnected = true
        coldStore.syncRelayInstancesToHosts(
            [
                RelayInstanceInfo(uuid: hostAUuid, name: hostAName, version: "2.34.0-v2", status: .connected),
                RelayInstanceInfo(uuid: hostBUuid, name: hostBName, version: "2.29.0-v2", status: .disconnected)
            ],
            latencyMs: 22,
            persistKeychainIfChanged: false
        )
        let sumA = try XCTUnwrap(coldStore.summaries.first(where: { $0.cascadeId == "cid-a-2" }))
        let sumBCached = try XCTUnwrap(coldStore.summaries.first(where: { $0.cascadeId == "cid-b-cached" }))
        XCTAssertTrue(coldStore.isSummaryHostOnline(sumA))
        XCTAssertFalse(coldStore.isSummaryHostOnline(sumBCached))

        coldStore.selectCascade("cid-b-cached")
        for _ in 0..<200 where (coldStore.stepsByCascadeId["cid-b-cached"] ?? []).isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(coldStore.stepsByCascadeId["cid-b-cached"]?.count, 2, "Cached transcript for offline Mac B must load from disk cleanly")
        XCTAssertNil(coldStore.stepLoadErrorText, "Viewing cached transcript on an offline Mac must not show an error banner")
        XCTAssertFalse(coldStore.isLoadingSteps)

        // Opening an uncached conversation on offline Mac B shows clear offline guidance without cross-host failover
        coldStore.selectCascade("cid-b-uncached")
        for _ in 0..<200 where coldStore.stepLoadErrorText == nil {
            await Task.yield()
        }
        XCTAssertTrue(coldStore.stepLoadErrorText?.contains(hostBName) == true)
        XCTAssertFalse(coldStore.isLoadingSteps)

        // 5. Legacy single-file migration & explicit sign-out cleanup
        let legacyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityLegacyMigrate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: legacyDir) }
        let legacyWriter = LocalProjectionStore(storageDirectory: legacyDir)
        await legacyWriter.saveProjectedSummaries(seedSummaries)
        await legacyWriter.saveProjects(store1.projects)
        let legacyReader = LocalProjectionStore(storageDirectory: legacyDir)
        let migratedShards = await legacyReader.loadAllHostProjections()
        XCTAssertEqual(Set(migratedShards.map(\.hostKey)), ["host:\(hostAUuid)", "host:\(hostBUuid)", "cloud"])

        await coldProjection.clearCachedProjections()
        let postClearShards = await coldProjection.loadAllHostProjections()
        let postClearHosts = await coldProjection.loadKnownHosts()
        let postClearSteps = await coldProjection.loadProjectedSteps(cascadeId: "cid-b-cached")
        XCTAssertTrue(postClearShards.isEmpty)
        XCTAssertTrue(postClearHosts.isEmpty)
        XCTAssertTrue(postClearSteps.isEmpty)
    }

    @MainActor
    func testPlatformPortsInjectedIntoSessionStore() async {
        let secretStore = InMemorySecretStore()
        let prefs = InMemoryPreferencesStore()
        let power = StaticPowerStateProvider(isLowPowerModeEnabled: true)
        let monitor = NoopNetworkReachabilityMonitor()

        let store = AntigravitySessionStore.makeLiveStore(
            secretStore: secretStore,
            networkMonitor: monitor,
            powerStateProvider: power,
            preferencesStore: prefs
        )

        // 1. Power state comes from injected PowerStateProviding & live store starts without hardcoded sample rules
        XCTAssertTrue(store.isLowPowerModeEnabled)
        XCTAssertTrue(store.permissionRules.isEmpty)

        // 2. Permission presets persist via injected KeyValuePreferencesStore (zero UserDefaults coupling)
        store.setActivePermissionPreset(.auto, isRemoteOverride: false)
        store.setActivePermissionPreset(.requestReview, isRemoteOverride: true)
        XCTAssertEqual(store.appearancePreferences.globalPermissionPreset, .auto)
        XCTAssertTrue(store.appearancePreferences.terminalSandboxEnabled)
        XCTAssertEqual(prefs.string(forKey: "antigravity.ios.permissionPreset.local"), AgentPermissionPreset.auto.rawValue)
        XCTAssertEqual(prefs.string(forKey: "antigravity.ios.permissionPreset.remote"), AgentPermissionPreset.requestReview.rawValue)

        let reloaded = AntigravitySessionStore.makeLiveStore(
            secretStore: secretStore,
            networkMonitor: monitor,
            powerStateProvider: StaticPowerStateProvider(isLowPowerModeEnabled: false),
            preferencesStore: prefs
        )
        XCTAssertEqual(reloaded.localPermissionPreset, .auto)
        XCTAssertEqual(reloaded.appearancePreferences.globalPermissionPreset, .auto)
        XCTAssertTrue(reloaded.appearancePreferences.terminalSandboxEnabled)
        XCTAssertEqual(reloaded.remotePermissionPreset, .requestReview)
        XCTAssertTrue(reloaded.permissionRules.isEmpty)
        XCTAssertFalse(reloaded.isLowPowerModeEnabled)

        // 3. Credentials & Relay API keys route via injected SecretStore (zero Keychain coupling)
        await secretStore.saveRelayWebApiKey("test-relay-key-123", forOrigin: "https://antigravity.google.com/")
        let cachedRelayKey = await secretStore.loadRelayWebApiKey(forOrigin: "https://antigravity.google.com")
        XCTAssertEqual(cachedRelayKey, "test-relay-key-123")
        await secretStore.clearRelayWebApiKey(forOrigin: "https://antigravity.google.com")
        let clearedRelayKey = await secretStore.loadRelayWebApiKey(forOrigin: "https://antigravity.google.com")
        XCTAssertNil(clearedRelayKey)

        await secretStore.saveCredentials(
            SavedBackendCredentials(
                endpointURLString: "http://127.0.0.1:8787",
                channel: .directHost,
                hostname: "Test Mac",
                csrfToken: "tok-123"
            )
        )
        let savedBefore = await secretStore.loadCredentials()
        XCTAssertEqual(savedBefore?.hostname, "Test Mac")
        await store.disconnectBackendAndClearKeychain()
        let savedAfter = await secretStore.loadCredentials()
        XCTAssertNil(savedAfter)
    }

    func testSemanticIconDecouplingAcrossDataModels() {
        XCTAssertEqual(Set(MarkdownAlertKind.allCases.map(\.semanticIcon)).count, MarkdownAlertKind.allCases.count)
        XCTAssertEqual(
            Set([
                MarkdownEmbedKind.htmlWidget, .image, .svg, .markdown, .webURL, .sidecar, .generic
            ].map(\.semanticIcon)).count,
            7
        )
        XCTAssertEqual(Set(AgentPermissionPreset.allCases.map(\.semanticIcon)).count, AgentPermissionPreset.allCases.count)
        XCTAssertFalse(SlashCommandItem.allCommands.isEmpty)
        XCTAssertEqual(
            SlashCommandItem.allCommands.first(where: { $0.command == "/plan" })?.icon,
            .commandPlan
        )
        let customCmds = SlashCommandItem.commands(
            isRemoteAgent: false,
            customSkills: [SkillSummary(name: "deploy-kmp", description: "Build KMP", isEnabled: true)]
        )
        XCTAssertEqual(
            customCmds.first(where: { $0.command == "/deploy-kmp" })?.icon,
            .commandCustomSkill
        )
    }

    @MainActor
    func testFastLaunchEntersConversationsOnFrameZeroForPairedAndEnvLaunches() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityFastLaunchTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let prefs = InMemoryPreferencesStore()
        let secretStore = InMemorySecretStore()
        let projection = LocalProjectionStore(storageDirectory: tempDir)

        // 1. Brand-new unpaired install resolves synchronously without stalling on "Checking saved connection..."
        let freshStore = AntigravitySessionStore.makeLiveStore(
            projectionStore: projection,
            secretStore: secretStore,
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(isLowPowerModeEnabled: false),
            preferencesStore: prefs
        )
        freshStore.prepareFastLaunchSessionState(environment: [:])
        XCTAssertFalse(freshStore.hasPairedBackend)
        XCTAssertFalse(freshStore.isConnectingToBackend)
        XCTAssertTrue(freshStore.isInitialSessionCheckComplete)

        // 2. Environment-configured launch enters Conversations on Frame 0 with connecting loading state
        let envStore = AntigravitySessionStore.makeLiveStore(
            projectionStore: projection,
            secretStore: secretStore,
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(isLowPowerModeEnabled: false),
            preferencesStore: prefs
        )
        envStore.prepareFastLaunchSessionState(environment: [
            "ANTIGRAVITY_BACKEND_URL": "http://127.0.0.1:18787",
            "ANTIGRAVITY_HOST_NAME": "Dev-MacBook"
        ])
        XCTAssertTrue(envStore.hasPairedBackend)
        XCTAssertTrue(envStore.isInitialSessionCheckComplete)
        XCTAssertTrue(envStore.isConnectingToBackend)
        XCTAssertEqual(envStore.connectionLifecyclePhase, .connecting)
        XCTAssertEqual(envStore.activeHost.hostname, "Dev-MacBook")

        // 3. Previously paired session persists non-secret launch hint -> next cold launch enters Conversations on Frame 0!
        let savedCreds = SavedBackendCredentials(
            endpointURLString: "https://antigravity.google.com/r/uuid-work-mac",
            channel: .cloudRelay,
            hostname: "Work-MacBook",
            sessionCookie: "SAPISID=test-cookie",
            authUser: "0",
            resolvedInstanceUuid: "uuid-work-mac"
        )
        await secretStore.saveCredentials(savedCreds)
        await freshStore.hydratePersistedHostProjectionsIfNeeded(savedCredentials: savedCreds)

        let coldPairedStore = AntigravitySessionStore.makeLiveStore(
            projectionStore: projection,
            secretStore: secretStore,
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(isLowPowerModeEnabled: false),
            preferencesStore: prefs
        )
        coldPairedStore.prepareFastLaunchSessionState(environment: [:])
        XCTAssertTrue(coldPairedStore.hasPairedBackend, "Returning paired user must enter Conversations on Frame 0")
        XCTAssertTrue(coldPairedStore.isInitialSessionCheckComplete)
        XCTAssertTrue(coldPairedStore.isConnectingToBackend)
        XCTAssertEqual(coldPairedStore.connectionLifecyclePhase, .connecting)
        XCTAssertEqual(coldPairedStore.activeHost.hostname, "Work-MacBook")

        // Opening an uncached conversation during cold-start connecting shows loading instead of a false offline error
        coldPairedStore.selectCascade("cid-uncached-during-connect")
        XCTAssertTrue(coldPairedStore.isLoadingSteps)
        XCTAssertNil(coldPairedStore.stepLoadErrorText)

        // Hydrating from disk returns the saved credentials cleanly
        let hydratedCreds = await coldPairedStore.hydrateSavedSessionFromDisk()
        XCTAssertEqual(hydratedCreds?.hostname, "Work-MacBook")

        // 4. Stale launch hint without Keychain credentials (e.g. device migration) cleanly reverts to Welcome screen
        await secretStore.clearCredentials()
        let staleHintStore = AntigravitySessionStore.makeLiveStore(
            projectionStore: projection,
            secretStore: secretStore,
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(isLowPowerModeEnabled: false),
            preferencesStore: prefs
        )
        staleHintStore.prepareFastLaunchSessionState(environment: [:])
        XCTAssertTrue(staleHintStore.hasPairedBackend)
        let missingCreds = await staleHintStore.hydrateSavedSessionFromDisk()
        XCTAssertNil(missingCreds)
        XCTAssertFalse(staleHintStore.hasPairedBackend)
        XCTAssertFalse(staleHintStore.isConnectingToBackend)
        XCTAssertTrue(staleHintStore.isInitialSessionCheckComplete)

        // 5. Optimistic initial pairing enters Conversations immediately, and rolls back cleanly on empty cookie
        staleHintStore.beginOptimisticConnectingSession(
            hostName: "New-Mac",
            channel: .cloudRelay,
            endpointURLString: "https://antigravity.google.com/r/new-mac"
        )
        XCTAssertTrue(staleHintStore.hasPairedBackend)
        XCTAssertTrue(staleHintStore.isConnectingToBackend)
        let ok = await staleHintStore.connectCloudRelay(
            relayURLString: "https://antigravity.google.com/r/new-mac",
            sessionCookie: ""
        )
        XCTAssertFalse(ok)
        XCTAssertFalse(staleHintStore.hasPairedBackend, "Failed optimistic initial pairing must roll back cleanly to Welcome")
        XCTAssertFalse(staleHintStore.isConnectingToBackend)

        // 6. Explicit disconnect clears launch hint so subsequent cold launch starts unpaired
        await secretStore.saveCredentials(savedCreds)
        await coldPairedStore.hydratePersistedHostProjectionsIfNeeded(savedCredentials: savedCreds)
        await coldPairedStore.disconnectBackendAndClearKeychain()
        let postDisconnectStore = AntigravitySessionStore.makeLiveStore(
            projectionStore: projection,
            secretStore: secretStore,
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(isLowPowerModeEnabled: false),
            preferencesStore: prefs
        )
        postDisconnectStore.prepareFastLaunchSessionState(environment: [:])
        XCTAssertFalse(postDisconnectStore.hasPairedBackend)
        XCTAssertTrue(postDisconnectStore.isInitialSessionCheckComplete)
    }

    func testCookieDomainFilteringExcludesSiblingSubdomainsAndDeduplicatesByName() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let future = now.addingTimeInterval(3600)
        let past = now.addingTimeInterval(-60)

        let descriptors: [SAPISIDHashGenerator.RelayCookieDescriptor] = [
            // Valid parent `.google.com` auth cookies
            .init(name: "SAPISID", value: "parent-sapisid", domain: ".google.com", path: "/", expiresDate: future),
            .init(name: "SID", value: "parent-sid", domain: ".google.com", path: "/", expiresDate: future),
            // Exact host cookie should override `.google.com` for the same name
            .init(name: "SAPISID", value: "exact-sapisid", domain: "antigravity.google.com", path: "/", expiresDate: future),
            // Sibling subdomain cookie MUST be excluded so it cannot corrupt SAPISID/SID
            .init(name: "SAPISID", value: "accounts-wrong-sapisid", domain: "accounts.google.com", path: "/", expiresDate: future),
            .init(name: "ACCOUNT_ONLY", value: "secret", domain: "accounts.google.com", path: "/", expiresDate: future),
            // Expired cookie MUST be excluded
            .init(name: "__Secure-1PAPISID", value: "expired-val", domain: ".google.com", path: "/", expiresDate: past)
        ]

        let header = SAPISIDHashGenerator.buildCookieHeader(
            from: descriptors,
            forHost: "antigravity.google.com",
            now: now
        )
        XCTAssertNotNil(header)
        let parsed = SAPISIDHashGenerator.parseCookies(header ?? "")
        XCTAssertEqual(parsed["SAPISID"], "exact-sapisid")
        XCTAssertEqual(parsed["SID"], "parent-sid")
        XCTAssertNil(parsed["ACCOUNT_ONLY"], "Sibling subdomain cookies must never leak into antigravity.google.com Cookie header")
        XCTAssertNil(parsed["__Secure-1PAPISID"], "Expired cookies must be dropped")
        XCTAssertFalse(SAPISIDHashGenerator.cookieDomain("accounts.google.com", appliesToHost: "antigravity.google.com"))
        XCTAssertTrue(SAPISIDHashGenerator.cookieDomain(".google.com", appliesToHost: "antigravity.google.com"))
        XCTAssertTrue(SAPISIDHashGenerator.cookieDomain("antigravity.google.com", appliesToHost: "antigravity.google.com"))
    }

    func testSwiftResolveCloudRelayInstanceThrowsUnauthorizedInsteadOfFabricatingUuidHost() async {
        let rawUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
        HostIsolationMockRelayURLProtocol.storage.setHandler { request in
            let url = request.url ?? URL(string: "https://antigravity.google.com")!
            let resp = HTTPURLResponse(
                url: url,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, Data("{\"error\":{\"message\":\"Google session expired\"}}".utf8))
        }
        defer { HostIsolationMockRelayURLProtocol.storage.setHandler(nil) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HostIsolationMockRelayURLProtocol.self]
        let session = URLSession(configuration: config)

        let host = RemoteHostInstance(
            instanceId: rawUuid,
            hostname: rawUuid,
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(rawUuid)")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=expired-cookie; SID=expired-sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        do {
            _ = try await client.resolveCloudRelayInstance(preferredIdentifier: rawUuid, allowCrossHostFallback: true)
            XCTFail("resolveCloudRelayInstance must throw Unauthorized instead of fabricating a fake connected UUID host")
        } catch let AntigravityRPCError.unauthorized(reason) {
            XCTAssertFalse(reason.isEmpty)
        } catch {
            XCTFail("Expected AntigravityRPCError.unauthorized, got: \(error)")
        }
    }

    func testCookiePathFilteringExcludesSlashRScopedCookiesAndExtractAllWebApiKeysFindsMultipleKeys() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let future = now.addingTimeInterval(3600)

        let descriptors: [SAPISIDHashGenerator.RelayCookieDescriptor] = [
            .init(name: "SAPISID", value: "root-sapisid", domain: ".google.com", path: "/", expiresDate: future),
            .init(name: "SID", value: "root-sid", domain: ".google.com", path: "/", expiresDate: future),
            // A `/r`-scoped cookie MUST NOT shadow a root `/` cookie for `/$rpc` requests
            .init(name: "SAPISID", value: "wrong-slash-r-sapisid", domain: "antigravity.google.com", path: "/r", expiresDate: future)
        ]

        let header = SAPISIDHashGenerator.buildCookieHeader(
            from: descriptors,
            forHost: "antigravity.google.com",
            now: now
        )
        let parsed = SAPISIDHashGenerator.parseCookies(header ?? "")
        XCTAssertEqual(parsed["SAPISID"], "root-sapisid")
        XCTAssertFalse(SAPISIDHashGenerator.cookiePath("/r", appliesToRequestPath: "/$rpc"))
        XCTAssertTrue(SAPISIDHashGenerator.cookiePath("/", appliesToRequestPath: "/$rpc"))

        let key1 = "AI" + "zaSyFIRSTOGSKEY0000000000000000000000"
        let key2 = "AI" + "zaSySECONDAPISVC111111111111111111111"
        let html = """
            <html><head>
            <script>window.WIZ_global_data = {"a":"\(key1)","x-goog-api-key":"\(key2)"};</script>
            <link rel="modulepreload" href="/_/boq/app_entry.mjs">
            </head></html>
            """
        let keys = SAPISIDHashGenerator.extractAllWebApiKeys(from: html)
        XCTAssertEqual(keys.first, key2, "Contextual x-goog-api-key must be prioritized ahead of generic keys")
        XCTAssertTrue(keys.contains(key1))
        XCTAssertTrue(keys.contains(key2))

        let scripts = SAPISIDHashGenerator.extractBootstrapScriptURLs(
            fromHTML: html,
            baseURL: URL(string: "https://antigravity.google.com/r/test")!
        )
        XCTAssertTrue(scripts.contains(where: { $0.absoluteString.hasSuffix("/_/boq/app_entry.mjs") }))

        XCTAssertTrue(
            SAPISIDHashGenerator.isInvalidApiKeyError(
                statusCode: 403,
                responseBody: "[7,\"Requests to this API devtools_jetski_boq_api_proto.ApiService method ListInstances are blocked.\"]"
            )
        )
    }

    @MainActor
    func testCancelPendingConnectionAttemptClearsConnectingPhase() {
        let store = AntigravitySessionStore.makeLiveStore()
        store.beginOptimisticConnectingSession(
            hostName: "Studio Mac",
            channel: .cloudRelay,
            endpointURLString: "https://antigravity.google.com/r/0f5819ac-9308-40d8-a308-98b55122c533-v2",
            instanceId: "0f5819ac-9308-40d8-a308-98b55122c533-v2"
        )
        XCTAssertTrue(store.isConnectingToBackend)
        XCTAssertEqual(store.connectionLifecyclePhase, .connecting)

        store.cancelPendingConnectionAttempt()
        XCTAssertFalse(store.isConnectingToBackend)
        XCTAssertFalse(store.hasPairedBackend)
        XCTAssertEqual(store.connectionLifecyclePhase, .disconnected)
    }

    func testAntigravityRPCErrorProvidesLocalizedDescriptions() {
        let httpErr = AntigravityRPCError.httpError(statusCode: 503, body: "No active backend connection")
        XCTAssertTrue(httpErr.localizedDescription.contains("HTTP 503"))
        XCTAssertTrue(httpErr.localizedDescription.contains("No active backend connection"))
        XCTAssertFalse(httpErr.localizedDescription.contains("The operation couldn't be completed"))

        let authErr = AntigravityRPCError.unauthorized("HTTP 403 [ListInstances]")
        XCTAssertTrue(authErr.localizedDescription.contains("HTTP 403"))
        XCTAssertFalse(authErr.localizedDescription.contains("The operation couldn't be completed"))

        let emptyHttpErr = AntigravityRPCError.httpError(statusCode: 502, body: "   ")
        XCTAssertEqual(emptyHttpErr.localizedDescription, "HTTP 502")
    }

    func testCloudRelayCanonicalizesVanityOriginSetsMobileUserAgentAndExposesZeroSecretDiagnostic() {
        // 1. Vanity `antigravity.google` host canonicalizes to `antigravity.google.com`
        XCTAssertEqual(RemoteHostInstance.canonicalRelayHost("antigravity.google"), "antigravity.google.com")
        XCTAssertEqual(RemoteHostInstance.canonicalRelayHost("staging.antigravity.google"), "staging.antigravity.google.com")
        let target = RemoteHostInstance.parseRemoteControlTarget("https://antigravity.google/r/0f5819ac-9308-40d8-a308-98b55122c533-v2")
        XCTAssertEqual(target?.canonicalRelayURLString, "https://antigravity.google.com/r/0f5819ac-9308-40d8-a308-98b55122c533-v2")
        XCTAssertEqual(
            SAPISIDHashGenerator.normalizeOrigin("https://antigravity.google/r/0f5819ac-9308-40d8-a308-98b55122c533-v2"),
            "https://antigravity.google.com"
        )

        // 2. Boq ApiService headers include explicit mobile Safari User-Agent and canonical Origin
        let testKey = "AI" + "zaSySWIFTHEADER0000000000000000000000"
        var req = URLRequest(url: URL(string: "https://antigravity.google.com/$rpc/devtools_jetski_boq_api_proto.ApiService/ListInstances")!)
        SAPISIDHashGenerator.applyApiServiceHeaders(
            to: &req,
            cookieHeader: "SAPISID=secret_sapisid_val; SID=secret_sid_val",
            origin: "https://antigravity.google/r/0f5819ac-9308-40d8-a308-98b55122c533-v2",
            authUser: "0",
            apiKey: testKey
        )
        XCTAssertEqual(req.value(forHTTPHeaderField: "User-Agent"), SAPISIDHashGenerator.mobileRemoteUserAgent)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Origin"), "https://antigravity.google.com")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Referer"), "https://antigravity.google.com/")

        // 3. Cookie summary & RPC client handshake diagnostic never leak secrets
        let cookieSummary = SAPISIDHashGenerator.summarizeCookieNames("SAPISID=secret_sapisid_val; SID=secret_sid_val")
        XCTAssertTrue(cookieSummary.contains("SAPISID"))
        XCTAssertFalse(cookieSummary.contains("secret_sapisid_val"))

        let host = RemoteHostInstance(
            instanceId: "0f5819ac-9308-40d8-a308-98b55122c533-v2",
            hostname: "MacBook Pro",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google/r/0f5819ac-9308-40d8-a308-98b55122c533-v2")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=secret_sapisid_val; SID=secret_sid_val",
            relayApiKey: testKey
        )
        let diag = client.currentHandshakeDiagnostic()
        XCTAssertTrue(diag.contains("engine=Swift-URLSession"))
        XCTAssertTrue(diag.contains("origin=antigravity.google.com"))
        XCTAssertFalse(diag.contains("secret_sapisid_val"))
        XCTAssertFalse(diag.contains(testKey))
    }

    func testSwiftResolveCloudRelayInstanceFailsFastOnPrimary504AndHidesSecretCookieValues() async {
        let validKey = "AI" + "zaSySWIFTFAILFAST00000000000000000000"
        let secretCookie = "SWIFT_SECRET_SAPISID_VALUE_504"
        let probedAuthUsers = AtomicTestString("")

        MockRelayURLProtocol.state.setResponder { urlString, authUser, _ in
            if urlString.contains("/ListInstances") {
                let prev = probedAuthUsers.get()
                let next = prev.isEmpty ? (authUser ?? "nil") : "\(prev),\(authUser ?? "nil")"
                probedAuthUsers.set(next)
                return (504, ["Content-Type": "text/plain"], Data("Gateway Timeout".utf8))
            }
            return (404, [:], Data())
        }
        defer { MockRelayURLProtocol.state.setResponder(nil) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRelayURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        let host = RemoteHostInstance(
            instanceId: "lt74xt6l0m-golden-star",
            hostname: "Antigravity Desktop",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/lt74xt6l0m-golden-star")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=\(secretCookie); SID=sid_504",
            relayApiKey: validKey,
            urlSession: mockSession
        )

        do {
            _ = try await client.resolveCloudRelayInstance(allowCrossHostFallback: true)
            XCTFail("Expected HTTP 504 fail-fast error")
        } catch let AntigravityRPCError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 504)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        XCTAssertEqual(
            probedAuthUsers.get(),
            "0",
            "Primary HTTP 504 must fail fast instead of burning timeout probing authUser=1..4"
        )
        let diag = client.currentHandshakeDiagnostic()
        XCTAssertTrue(diag.contains("resolve:failFast"), "Expected resolve:failFast trace in diagnostic: \(diag)")
        XCTAssertFalse(diag.contains(secretCookie), "Diagnostic must never leak raw cookie values")
        XCTAssertFalse(diag.contains(validKey), "Diagnostic must never leak full API key")
    }

    func testSwiftResolveCloudRelayEmptyHttp200Throws404AndVerifyConnectionSurvivesSlowProxyCommand() async throws {
        let validKey = "AI" + "zaSySWIFTEMPTY20000000000000000000000"
        let rawUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"

        // 1. Empty HTTP 200 ListInstances on a short slug must throw actionable HTTP 404 (not Unauthorized)
        MockRelayURLProtocol.state.setResponder { urlString, _, _ in
            if urlString.contains("/ListInstances") {
                return (200, ["Content-Type": "application/json+protobuf"], Data(")]}'\n[[],5]".utf8))
            }
            return (404, [:], Data())
        }
        defer { MockRelayURLProtocol.state.setResponder(nil) }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRelayURLProtocol.self]
        let mockSession = URLSession(configuration: config)

        let emptyHost = RemoteHostInstance(
            instanceId: "golden-star",
            hostname: "Antigravity Desktop",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/golden-star")!,
            isOnline: true
        )
        let emptyClient = AntigravityRPCClient(
            host: emptyHost,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: validKey,
            urlSession: mockSession
        )

        do {
            _ = try await emptyClient.resolveCloudRelayInstance(allowCrossHostFallback: true)
            XCTFail("Expected HTTP 404 when ListInstances returns empty array")
        } catch let AntigravityRPCError.httpError(statusCode, _) {
            XCTAssertEqual(statusCode, 404)
        } catch {
            XCTFail("Expected AntigravityRPCError.httpError(404), got \(error)")
        }

        // 2. verifyConnection succeeds even when initial ProxyCommand fails with HTTP 504
        MockRelayURLProtocol.state.setResponder { urlString, _, _ in
            if urlString.contains("/ListInstances") {
                let payload = ")]}'\n[[[\"\(rawUuid)\",[\"MacBook Pro\",\"2.33.0\",1],1,[1740000000,0]]],5]"
                return (200, ["Content-Type": "application/json+protobuf"], Data(payload.utf8))
            }
            if urlString.contains("/ProxyCommand") {
                return (504, ["Content-Type": "text/plain"], Data("Gateway Timeout".utf8))
            }
            return (404, [:], Data())
        }

        let onlineHost = RemoteHostInstance(
            instanceId: rawUuid,
            hostname: "Antigravity Desktop",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(rawUuid)")!,
            isOnline: true
        )
        let onlineClient = AntigravityRPCClient(
            host: onlineHost,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: validKey,
            urlSession: mockSession
        )

        let handshake = try await onlineClient.verifyConnection(allowCrossHostFallback: true)
        XCTAssertEqual(handshake.resolvedHostname, "MacBook Pro")
        XCTAssertEqual(handshake.resolvedInstanceUuid, rawUuid)
        XCTAssertTrue(handshake.isSelectedHostOnline)
        XCTAssertTrue(handshake.summaries.isEmpty)
    }

    @MainActor
    func testDeviceConnectionStatusAccuracyAcrossDisappearedActiveHostAndStaleHeartbeat() async throws {
        // 1. Swift AntigravityRPCClient.probeHostReachability(verifyEndToEnd: false) auto-verifies
        //    unverified stale CONNECTED zombie Macs and downgrades them to .disconnected.
        let liveUuid = "1111-live-macbook-v2"
        let zombieUuid = "2222-zombie-imac-v2"
        let removedUuid = "3333-removed-mini-v2"
        let validKey = "AI" + "zaSySWIFTSTATUS0000000000000000000000"
        let liveProbeCounter = AtomicTestInt(0)
        let zombieProbeCounter = AtomicTestInt(0)

        MockRelayURLProtocol.state.setResponder { urlString, _, body in
            if urlString.contains("/ListInstances") {
                let payload = ")]}'\n[[[\"\(liveUuid)\",[\"MacBook Pro\",\"2.34.0\",1],1,[1740000000,0]],[\"\(zombieUuid)\",[\"Office iMac\",\"2.34.0\",1],1,[1740000000,0]]],5]"
                return (200, ["Content-Type": "application/json+protobuf"], Data(payload.utf8))
            }
            if urlString.contains("/ProxyCommand") {
                let bodyText = String(data: body, encoding: .utf8) ?? ""
                if bodyText.contains(zombieUuid) {
                    _ = zombieProbeCounter.increment()
                    let errBody = #"[9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo","INSTANCE_NOT_REGISTERED"]]]"#
                    return (400, ["Content-Type": "application/json+protobuf"], Data(errBody.utf8))
                }
                _ = liveProbeCounter.increment()
                let encodedInner = Data("{}".utf8).base64EncodedString()
                let jspb = ")]}'\n[\"\(encodedInner)\",[[\"content-type\",\"application/json\"]]]"
                return (200, ["Content-Type": "application/json+protobuf"], Data(jspb.utf8))
            }
            return (404, [:], Data())
        }
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockRelayURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        defer {
            MockRelayURLProtocol.state.setResponder(nil)
            mockSession.invalidateAndCancel()
        }

        let liveHost = RemoteHostInstance(
            instanceId: liveUuid,
            hostname: "MacBook Pro",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(liveUuid)")!,
            isOnline: true
        )
        let rpcClient = AntigravityRPCClient(
            host: liveHost,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            authUser: "0",
            resolvedInstanceUuid: liveUuid,
            relayApiKey: validKey,
            urlSession: mockSession
        )

        let firstProbe = try await rpcClient.probeHostReachability(allowCrossHostFallback: false, verifyEndToEnd: false)
        XCTAssertTrue(firstProbe.isSelectedHostOnline)
        XCTAssertEqual(liveProbeCounter.get(), 1)
        XCTAssertEqual(zombieProbeCounter.get(), 1)
        XCTAssertEqual(firstProbe.availableRelayInstances.first(where: { $0.uuid == liveUuid })?.status, .connected)
        XCTAssertEqual(firstProbe.availableRelayInstances.first(where: { $0.uuid == zombieUuid })?.status, .disconnected)

        // Immediate second lightweight probe skips redundant ProxyCommand for freshly verified live host
        let secondProbe = try await rpcClient.probeHostReachability(allowCrossHostFallback: false, verifyEndToEnd: false)
        XCTAssertTrue(secondProbe.isSelectedHostOnline)
        XCTAssertEqual(liveProbeCounter.get(), 1)
        XCTAssertEqual(zombieProbeCounter.get(), 2)

        // 2. syncRelayInstancesToHosts marks disappeared activeHost offline & clears isLiveBackendConnected
        let store = AntigravitySessionStore.makeLiveStore()
        store.isVerificationMode = true
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.isDeviceNetworkReachable = true
        let removedHost = RemoteHostInstance(
            instanceId: removedUuid,
            hostname: "Old Mac mini",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(removedUuid)")!,
            isOnline: true
        )
        store.activeHost = removedHost
        store.hosts = [removedHost, liveHost]

        store.syncRelayInstancesToHosts(
            [
                RelayInstanceInfo(uuid: liveUuid, name: "MacBook Pro", version: "2.34.0", status: .connected),
                RelayInstanceInfo(uuid: zombieUuid, name: "Office iMac", version: "2.34.0", status: .disconnected)
            ],
            latencyMs: 25,
            persistKeychainIfChanged: false
        )
        XCTAssertFalse(store.activeHost.isOnline, "Active host absent from ListInstances must be marked offline")
        XCTAssertFalse(store.isLiveBackendConnected)
        XCTAssertEqual(store.connectionStatusText, "Offline · Old Mac mini")
        XCTAssertFalse(store.isLocalHostOnline(instanceId: removedUuid, hostname: "Old Mac mini"))
        XCTAssertTrue(store.isLocalHostOnline(instanceId: liveUuid, hostname: "MacBook Pro"))
        XCTAssertTrue(store.isHostOnline(forInstanceUuid: liveUuid), "isHostOnline must match isLocalHostOnline for healthy peers")
        XCTAssertFalse(store.isHostOnline(forInstanceUuid: zombieUuid))

        // 3. applyScopedHostRefreshResult in .allHosts promotes activeHost to responding peer instead of
        //    falsely marking the offline activeHost back to isOnline = true
        let scopedResult = ScopedWorkspaceSyncResult(
            workspaces: [],
            summaries: [],
            cloudProjects: [],
            cloudWarmingUp: false,
            relayInstances: [
                RelayInstanceInfo(uuid: liveUuid, name: "MacBook Pro", version: "2.34.0", status: .connected),
                RelayInstanceInfo(uuid: zombieUuid, name: "Office iMac", version: "2.34.0", status: .disconnected)
            ],
            refreshedLocalHostUuids: [liveUuid],
            refreshedLocalHostNames: ["MacBook Pro"],
            refreshedCloud: false,
            targetReachable: true,
            latencyMs: 18
        )
        await store.applyScopedHostRefreshResult(scopedResult, for: .allHosts)
        XCTAssertEqual(store.activeHost.instanceId, liveUuid)
        XCTAssertTrue(store.activeHost.isOnline)
        XCTAssertTrue(store.isLiveBackendConnected)
        XCTAssertFalse(store.hosts.first(where: { $0.instanceId == removedUuid })?.isOnline ?? true)
        XCTAssertFalse(store.isLocalHostOnline(instanceId: removedUuid, hostname: "Old Mac mini"))
    }

    func testEmptyBodyProxyCommandTupleDecodesWithoutFalse502AndListInstancesOnlineAliases() throws {
        // 1. Empty-body JSPB tuple `[null, [["content-type","application/json"]]]` must decode cleanly (NOT throw HTTP 502)
        let emptyWithHeaders = ")]}'\n" + #"[null,[["content-type","application/json"],["x-test","ok"]]]"#
        let decodedWithHeaders = try CloudRelayJSPBCodec.decodeProxyCommandResponse(Data(emptyWithHeaders.utf8))
        XCTAssertTrue(decodedWithHeaders.payload.isEmpty)
        XCTAssertEqual(decodedWithHeaders.headers["content-type"], "application/json")
        XCTAssertEqual(decodedWithHeaders.headers["x-test"], "ok")

        let emptyNoHeaders = ")]}'\n[null,[]]"
        let decodedEmpty = try CloudRelayJSPBCodec.decodeProxyCommandResponse(Data(emptyNoHeaders.utf8))
        XCTAssertTrue(decodedEmpty.payload.isEmpty)
        XCTAssertTrue(decodedEmpty.headers.isEmpty)

        // 2. Real Boq error trailer `[null, [9, "instance not registered"]]` must still throw HTTP 502
        let boqError = ")]}'\n" + #"[null,[9,"instance not registered"]]"#
        XCTAssertThrowsError(try CloudRelayJSPBCodec.decodeProxyCommandResponse(Data(boqError.utf8))) { error in
            guard case AntigravityRPCError.httpError(let code, _) = error else {
                XCTFail("Expected HTTP 502 error, got \(error)")
                return
            }
            XCTAssertEqual(code, 502)
        }

        // 3. Forward-compatible ListInstances online status aliases & string-form metadata
        let aliasList = ")]}'\n" + #"[[["uuid-online","Venciallee","ONLINE",null,"2.34.0"],["uuid-active",["dark-ray","2.34.0",true],"ACTIVE",null],["uuid-offline",["old-mac","2.34.0",true],"OFFLINE",null]],5]"#
        let instances = try CloudRelayJSPBCodec.decodeListInstancesResponse(Data(aliasList.utf8))
        XCTAssertEqual(instances.count, 3)
        XCTAssertEqual(instances[0].name, "Venciallee")
        XCTAssertEqual(instances[0].version, "2.34.0")
        XCTAssertEqual(instances[0].status, .connected)
        XCTAssertEqual(instances[1].status, .connected)
        XCTAssertEqual(instances[2].status, .disconnected)
    }

    func testRelayProbeToleratesTransient504EmptyBodyDesktop501AndPropagates401() async throws {
        let miniUuid = "1111-mac-mini-v2"
        let vencialleeUuid = "2222-venciallee-v2"
        let darkRayUuid = "3333-dark-ray-v2"
        let validKey = "AI" + "zaSyTRANSIENTPROBE0000000000000000000"
        let darkRayMode = AtomicTestString("504")
        let darkRayAttempts = AtomicTestInt(0)

        MockRelayURLProtocol.state.setResponder { urlString, _, body in
            if urlString.contains("/ListInstances") {
                let payload = ")]}'\n[[[\"\(miniUuid)\",[\"mac-mini\",\"2.34.0\",1],1,[1740000000,0]],[\"\(vencialleeUuid)\",[\"Venciallee\",\"2.34.0\",1],1,[1740000000,0]],[\"\(darkRayUuid)\",[\"dark-ray\",\"2.34.0\",1],1,[1740000000,0]]],5]"
                return (200, ["Content-Type": "application/json+protobuf"], Data(payload.utf8))
            }
            if urlString.contains("/ProxyCommand") {
                let bodyText = String(data: body, encoding: .utf8) ?? ""
                if bodyText.contains(vencialleeUuid) {
                    // Empty-body JSPB header tuple on first probe (valid Desktop empty response)
                    return (200, ["Content-Type": "application/json+protobuf"], Data(")]}'\n[null,[[\"content-type\",\"application/json\"]]]".utf8))
                }
                if bodyText.contains(darkRayUuid) {
                    let count = darkRayAttempts.increment()
                    let mode = darkRayMode.get()
                    if mode == "401" {
                        return (401, ["Content-Type": "application/json+protobuf"], Data("UNAUTHENTICATED".utf8))
                    }
                    if mode == "501" {
                        return (501, ["Content-Type": "application/json+protobuf"], Data("unimplemented".utf8))
                    }
                    if mode == "flaky-then-ok" && count % 2 == 0 {
                        let b64 = Data("{}".utf8).base64EncodedString()
                        return (200, ["Content-Type": "application/json+protobuf"], Data(")]}'\n[\"\(b64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                    }
                    return (504, ["Content-Type": "application/json+protobuf"], Data("gateway timeout".utf8))
                }
                let b64 = Data("{}".utf8).base64EncodedString()
                return (200, ["Content-Type": "application/json+protobuf"], Data(")]}'\n[\"\(b64)\",[[\"content-type\",\"application/json\"]]]".utf8))
            }
            return (404, [:], Data())
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockRelayURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        defer {
            MockRelayURLProtocol.state.setResponder(nil)
            mockSession.invalidateAndCancel()
        }

        let miniHost = RemoteHostInstance(
            instanceId: miniUuid,
            hostname: "mac-mini",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(miniUuid)")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: miniHost,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            authUser: "0",
            resolvedInstanceUuid: miniUuid,
            relayApiKey: validKey,
            urlSession: mockSession
        )

        // 1. Lightweight heartbeat strike 1: venciallee (empty body) is CONNECTED, dark-ray (1 transient 504) stays CONNECTED
        let strike1 = try await client.probeHostReachability(allowCrossHostFallback: false, verifyEndToEnd: false)
        XCTAssertEqual(strike1.availableRelayInstances.first(where: { $0.uuid == miniUuid })?.status, .connected)
        XCTAssertEqual(strike1.availableRelayInstances.first(where: { $0.uuid == vencialleeUuid })?.status, .connected)
        XCTAssertEqual(strike1.availableRelayInstances.first(where: { $0.uuid == darkRayUuid })?.status, .connected)

        // 2. Lightweight heartbeat strike 2: 2nd consecutive 504 downgrades silent dark-ray to DISCONNECTED
        let strike2 = try await client.probeHostReachability(allowCrossHostFallback: false, verifyEndToEnd: false)
        XCTAssertEqual(strike2.availableRelayInstances.first(where: { $0.uuid == darkRayUuid })?.status, .disconnected)

        // 3. Desktop HTTP 501 proves tunnel liveness and brings dark-ray back to CONNECTED
        darkRayMode.set("501")
        let recovered = try await client.probeHostReachability(allowCrossHostFallback: false, verifyEndToEnd: false)
        XCTAssertEqual(recovered.availableRelayInstances.first(where: { $0.uuid == darkRayUuid })?.status, .connected)

        // 4. Explicit verifyEndToEnd = true retries once on transient 504 and keeps dark-ray CONNECTED when retry succeeds
        darkRayMode.set("flaky-then-ok")
        // Ensure next attempt is odd (fails) followed by even (succeeds)
        if darkRayAttempts.get() % 2 == 1 {
            _ = darkRayAttempts.increment()
        }
        let verifiedAfterRetry = try await client.probeHostReachability(allowCrossHostFallback: false, verifyEndToEnd: true)
        XCTAssertEqual(verifiedAfterRetry.availableRelayInstances.first(where: { $0.uuid == darkRayUuid })?.status, .connected)

        // 5. HTTP 401 Unauthorized must propagate instead of silently marking dark-ray disconnected
        darkRayMode.set("401")
        do {
            _ = try await client.probeHostReachability(allowCrossHostFallback: false, verifyEndToEnd: true)
            XCTFail("Expected AntigravityRPCError.unauthorized to propagate")
        } catch AntigravityRPCError.unauthorized {
            // Expected
        }
    }

    @MainActor
    func testFederatedSyncTimeoutPreservesOnlinePeersAndStoreHandlesDuplicateNamesAndTransientRefresh() async throws {
        let miniUuid = "1111-fed-mini-v2"
        let slowPeerUuid = "2222-fed-slow-v2"
        let unregPeerUuid = "3333-fed-unreg-v2"
        let validKey = "AI" + "zaSyFEDTIMEOUT00000000000000000000000"
        let failListWith504 = AtomicTestInt(0)

        MockRelayURLProtocol.state.setResponder { urlString, _, body in
            if urlString.contains("/ListInstances") {
                if failListWith504.get() == 1 {
                    return (504, ["Content-Type": "application/json+protobuf"], Data("list timeout".utf8))
                }
                let payload = ")]}'\n[[[\"\(miniUuid)\",[\"mac-mini\",\"2.34.0\",1],1,[1740000000,0]],[\"\(slowPeerUuid)\",[\"Venciallee\",\"2.34.0\",1],1,[1740000000,0]],[\"\(unregPeerUuid)\",[\"dead-mac\",\"2.34.0\",1],1,[1740000000,0]]],5]"
                return (200, ["Content-Type": "application/json+protobuf"], Data(payload.utf8))
            }
            if urlString.contains("/ProxyCommand") {
                let bodyText = String(data: body, encoding: .utf8) ?? ""
                if bodyText.contains(slowPeerUuid) {
                    return (504, ["Content-Type": "application/json+protobuf"], Data("upstream timeout".utf8))
                }
                if bodyText.contains(unregPeerUuid) {
                    let errBody = #"[9,"instance not registered",[["type.googleapis.com/google.rpc.ErrorInfo","INSTANCE_NOT_REGISTERED"]]]"#
                    return (400, ["Content-Type": "application/json+protobuf"], Data(errBody.utf8))
                }
                let b64 = Data(#"{"workspaces":[],"trajectorySummaries":{}}"#.utf8).base64EncodedString()
                return (200, ["Content-Type": "application/json+protobuf"], Data(")]}'\n[\"\(b64)\",[[\"content-type\",\"application/json\"]]]".utf8))
            }
            return (404, [:], Data())
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockRelayURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)
        defer {
            MockRelayURLProtocol.state.setResponder(nil)
            mockSession.invalidateAndCancel()
        }

        let miniHost = RemoteHostInstance(
            instanceId: miniUuid,
            hostname: "mac-mini",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(miniUuid)")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: miniHost,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            authUser: "0",
            resolvedInstanceUuid: miniUuid,
            relayApiKey: validKey,
            urlSession: mockSession
        )

        // 1. Federated sync: slow peer hitting 504 stays CONNECTED while INSTANCE_NOT_REGISTERED peer becomes DISCONNECTED
        let federated = try await client.fetchFederatedWorkspacesAndSummaries(
            timeoutInterval: 5.0,
            includeLocal: true,
            includeCloud: false,
            includeJetboxSnapshot: false
        )
        XCTAssertTrue(federated.succeededInstanceUuids.contains(miniUuid))
        XCTAssertEqual(federated.availableRelayInstances.first(where: { $0.uuid == slowPeerUuid })?.status, .connected)
        XCTAssertEqual(federated.availableRelayInstances.first(where: { $0.uuid == unregPeerUuid })?.status, .disconnected)

        // 2. Store isLocalHostOnline prefers reachable instance when duplicate hostname entries exist
        let store = AntigravitySessionStore.makeLiveStore()
        store.isVerificationMode = false
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.isDeviceNetworkReachable = true
        store.activeHost = miniHost
        store.rpcClient = client
        store.hosts = [
            miniHost,
            RemoteHostInstance(instanceId: "old-venciallee", hostname: "Venciallee", channel: .cloudRelay, endpointURL: miniHost.endpointURL, isOnline: false),
            RemoteHostInstance(instanceId: slowPeerUuid, hostname: "Venciallee", channel: .cloudRelay, endpointURL: miniHost.endpointURL, isOnline: true)
        ]
        store.availableRelayInstances = [
            RelayInstanceInfo(uuid: miniUuid, name: "mac-mini", version: "2.34.0", status: .connected),
            RelayInstanceInfo(uuid: "old-venciallee", name: "Venciallee", version: "2.34.0", status: .disconnected),
            RelayInstanceInfo(uuid: slowPeerUuid, name: "Venciallee", version: "2.34.0", status: .connected)
        ]
        XCTAssertTrue(store.isLocalHostOnline(instanceId: nil, hostname: "Venciallee"))

        // 3. Single transient 504 during refreshAvailableRelayHosts must NOT wipe online hosts offline on strike 1
        _ = failListWith504.increment()
        await store.refreshAvailableRelayHosts(verifyEndToEnd: true)
        XCTAssertTrue(store.isLiveBackendConnected)
        XCTAssertTrue(store.activeHost.isOnline)
        XCTAssertTrue(store.isLocalHostOnline(instanceId: miniUuid, hostname: "mac-mini"))
        XCTAssertTrue(store.isLocalHostOnline(instanceId: slowPeerUuid, hostname: "Venciallee"))
    }

    @MainActor
    func testTC25_ActiveChatStepSyncForegroundAndReentryRecovery() async {
        MockRelayURLProtocol.state.setResponder { urlString, _, _ in
            if urlString.contains("/ProxyCommand") || urlString.contains("GetCascadeTrajectorySteps") {
                let inner = Data("{\"steps\":[]}".utf8).base64EncodedString()
                let jspb = ")]}'\n[\"\(inner)\",[[\"content-type\",\"application/json\"]]]"
                return (200, ["Content-Type": "application/json+protobuf"], Data(jspb.utf8))
            }
            return (200, [:], Data())
        }
        defer { MockRelayURLProtocol.state.setResponder(nil) }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockRelayURLProtocol.self]
        let mockSession = URLSession(configuration: sessionConfig)

        let store = AntigravitySessionStore.makeLiveStore()
        defer {
            store.suspendNetworkingForBackground()
        }
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.isDeviceNetworkReachable = true
        store.isNetworkingSuspended = false
        store.activeHost = RemoteHostInstance(
            instanceId: "rec-uuid-1",
            hostname: "Antigravity",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/rec-uuid-1")!,
            isOnline: true
        )
        store.rpcClient = AntigravityRPCClient(
            host: store.activeHost,
            sessionCookie: "SAPISID=test",
            authUser: "0",
            resolvedInstanceUuid: "rec-uuid-1",
            relayApiKey: "AIzaSyTestKey0000000000000000000000000",
            urlSession: mockSession
        )

        let cid = "cid-sync-recovery"
        let summary = CascadeSummary(
            cascadeId: cid,
            title: "Recovery Test Chat",
            projectSlug: "ledger-svc",
            workspaceUri: "cloud://ledger-svc",
            status: .done,
            stepCount: 5,
            isCloud: true,
            originInstanceUuid: "rec-uuid-1",
            originHostName: "Antigravity"
        )
        store.summaries = [summary]
        store.activeCascadeId = cid
        store.activeRoute = .cascadeChat(cid)
        store.stepsByCascadeId.removeValue(forKey: cid)

        // 1. Entering a conversation with empty steps sets isLoadingSteps = true
        store.syncStepsForCascade(cid, pollUntilIdle: true)
        XCTAssertTrue(store.isLoadingSteps, "Entering unhydrated conversation must display loading indicator")

        // 2. Backgrounding suspends networking and stops polling task
        store.suspendNetworkingForBackground()
        XCTAssertTrue(store.isNetworkingSuspended)

        // 3. Foregrounding while viewing cascadeChat must immediately restart step sync and mark isLoadingSteps
        await store.resumeNetworkingFromForeground()
        XCTAssertFalse(store.isNetworkingSuspended)
        XCTAssertTrue(store.isLoadingSteps, "Resuming from background while in chat must immediately restore step loading")

        // 4. Calling syncStepsForCascade with empty steps must force refresh rather than stalling
        store.syncStepsForCascade(cid, pollUntilIdle: true)
        XCTAssertTrue(store.isLoadingSteps, "Re-entering must keep step loading alive when steps are empty")
        store.suspendNetworkingForBackground()
    }
}

private final class AtomicTestInt: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int

    init(_ initial: Int) {
        self.value = initial
    }

    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private final class AtomicTestString: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String

    init(_ initial: String) {
        self.value = initial
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: String) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

private final class MockRelayURLProtocol: URLProtocol {
    typealias Responder = @Sendable (_ urlString: String, _ authUser: String?, _ body: Data) -> (statusCode: Int, headers: [String: String], body: Data)

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var responder: Responder?

        func setResponder(_ newResponder: Responder?) {
            lock.lock()
            defer { lock.unlock() }
            responder = newResponder
        }

        func invoke(urlString: String, authUser: String?, body: Data) -> (statusCode: Int, headers: [String: String], body: Data) {
            lock.lock()
            let current = responder
            lock.unlock()
            return current?(urlString, authUser, body) ?? (404, [:], Data())
        }
    }

    static let state = State()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    private static func readBody(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount > 0 {
                data.append(buffer, count: readCount)
            } else {
                break
            }
        }
        return data
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let authUser = request.value(forHTTPHeaderField: "X-Goog-AuthUser")
        let body = Self.readBody(from: request)
        let reply = Self.state.invoke(urlString: url.absoluteString, authUser: authUser, body: body)
        if let httpResp = HTTPURLResponse(
            url: url,
            statusCode: reply.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        ) {
            client?.urlProtocol(self, didReceive: httpResp, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class AtomicTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(initialValue: Bool) {
        self.value = initialValue
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ next: Bool) {
        lock.lock()
        value = next
        lock.unlock()
    }
}

private final class HostIsolationMockRelayBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    func setHandler(_ newHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    func getHandler() -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}

private final class HostIsolationMockRelayURLProtocol: URLProtocol, @unchecked Sendable {
    static let storage = HostIsolationMockRelayBox()

    static func readBody(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            collected.append(buffer, count: count)
        }
        return collected
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.storage.getHandler() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension AntigravitySessionStore {
    func disconnectStepSyncForTestingIfNeeded() {
        syncStepsForCascade("", pollUntilIdle: false)
    }
}

private final class RelayDiscoveryTestStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var scriptKey: String
    private var listCallCount: Int = 0
    private var recordedApiKeys: [String] = []

    init(activeScriptKey: String) {
        self.scriptKey = activeScriptKey
    }

    func currentScriptKey() -> String {
        lock.lock()
        defer { lock.unlock() }
        return scriptKey
    }

    func setScriptKey(_ newKey: String) {
        lock.lock()
        defer { lock.unlock() }
        scriptKey = newKey
    }

    func incrementListCalls() -> Int {
        lock.lock()
        defer { lock.unlock() }
        listCallCount += 1
        return listCallCount
    }

    func recordSentApiKey(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedApiKeys.append(key)
    }

    func sentApiKeys() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedApiKeys
    }
}

private final class RelayDiscoveryMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func setHandler(_ newHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?) {
        lock.lock()
        defer { lock.unlock() }
        handler = newHandler
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let currentHandler = Self.handler
        Self.lock.unlock()
        guard let currentHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try currentHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor HostRefreshTestCoordinator {
    private var pausedKeys: Set<String>
    private var counts: [String: Int] = [:]
    private var releaseWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var entryWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(pausedKeys: Set<String>) {
        self.pausedKeys = pausedKeys
    }

    func enterAndWait(key: String) async {
        counts[key, default: 0] += 1
        if let waiters = entryWaiters.removeValue(forKey: key) {
            for waiter in waiters {
                waiter.resume()
            }
        }
        guard pausedKeys.contains(key) else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters[key, default: []].append(continuation)
        }
    }

    func waitUntilEntered(key: String) async {
        if counts[key, default: 0] > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            entryWaiters[key, default: []].append(continuation)
        }
    }

    func release(key: String) {
        pausedKeys.remove(key)
        let waiters = releaseWaiters.removeValue(forKey: key) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func count(for key: String) -> Int {
        counts[key, default: 0]
    }
}

