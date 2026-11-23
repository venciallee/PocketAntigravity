import XCTest
@testable import AntigravityData

final class WatchCompanionTests: XCTestCase {

    // MARK: - WTC-10: W05 / W06 Diff Risk & Scale Triage Engine (<= 5 files AND zero risk items)

    func testWTC10_DiffTriageEngineCompactModeForSafeSmallChangeSet() {
        let diffs: [FilePatchDiff] = [
            FilePatchDiff(filePath: "ratelimit.go", additions: 96, deletions: 0, hunkHeader: "@@ -0,0 +1,96 @@ Per-tenant token bucket", statusLetter: .added, lines: []),
            FilePatchDiff(filePath: "router.go", additions: 12, deletions: 6, hunkHeader: "@@ -10,6 +10,12 @@ Limiter on POST /transfers", statusLetter: .modified, lines: []),
            FilePatchDiff(filePath: "config.go", additions: 14, deletions: 2, hunkHeader: "@@ -4,2 +4,14 @@ Rate, burst, TTL settings", statusLetter: .modified, lines: []),
            FilePatchDiff(filePath: "ratelimit_test.go", additions: 6, deletions: 6, hunkHeader: "@@ -1,6 +1,6 @@ Unit tests", statusLetter: .modified, lines: []),
            FilePatchDiff(filePath: "metrics.go", additions: 8, deletions: 1, hunkHeader: "@@ -1,1 +1,8 @@ Export burst counters", statusLetter: .modified, lines: []),
        ]

        XCTAssertEqual(WatchChangesSnapshot.defaultCompactThreshold, 5)
        let snapshot = WatchDiffTriageEngine.buildChangesSnapshot(from: diffs)
        XCTAssertFalse(snapshot.isGroupedMode)
        XCTAssertTrue(snapshot.canAcceptAllOnWatch)
        XCTAssertEqual(snapshot.totalFiles, 5)
        XCTAssertEqual(snapshot.totalAdditions, 136)
        XCTAssertEqual(snapshot.totalDeletions, 15)
        XCTAssertEqual(snapshot.compactFiles.count, 5)
        XCTAssertEqual(snapshot.compactFiles[0].statusLetter, .added)
        XCTAssertEqual(snapshot.compactFiles[0].filePath, "ratelimit.go")
        XCTAssertTrue(snapshot.worthALookFiles.isEmpty)
        XCTAssertTrue(snapshot.intentGroups.isEmpty)
    }

    func testWTC10_DiffTriageEngineForcesGroupedModeWhenSmallSetHasRiskItem() {
        // Even with <= 5 files (3 files), touching a dependency or security/audit file MUST force WORTH A LOOK + iPhone review.
        let riskySmallDiffs: [FilePatchDiff] = [
            FilePatchDiff(filePath: "go.mod", additions: 1, deletions: 8, statusLetter: .modified, lines: []),
            FilePatchDiff(filePath: "router.go", additions: 10, deletions: 2, statusLetter: .modified, lines: []),
            FilePatchDiff(filePath: "router_test.go", additions: 12, deletions: 0, statusLetter: .added, lines: []),
        ]

        let snapshot = WatchDiffTriageEngine.buildChangesSnapshot(from: riskySmallDiffs)
        XCTAssertTrue(snapshot.isGroupedMode)
        XCTAssertFalse(snapshot.canAcceptAllOnWatch)
        XCTAssertEqual(snapshot.totalFiles, 3)
        XCTAssertEqual(snapshot.worthALookFiles.map(\.filePath), ["go.mod"])
        XCTAssertEqual(snapshot.worthALookFiles.first?.summary, "Removes a dependency")
        XCTAssertEqual(snapshot.groupedFileCount, 2)
    }

    func testWTC10_DiffTriageEngineForcesGroupedModeAtSixSafeFiles() {
        let sixSafeDiffs = (1...6).map { idx in
            FilePatchDiff(filePath: "internal/handler_\(idx).go", additions: 5, deletions: 1, statusLetter: .modified, lines: [])
        }
        let snapshot = WatchDiffTriageEngine.buildChangesSnapshot(from: sixSafeDiffs)
        XCTAssertTrue(snapshot.isGroupedMode)
        XCTAssertFalse(snapshot.canAcceptAllOnWatch)
        XCTAssertEqual(snapshot.totalFiles, 6)
        XCTAssertFalse(snapshot.worthALookFiles.isEmpty)
    }

    func testWTC10_DiffTriageEngineIntentGroupedModeForLargeChangeSet() {
        var diffs: [FilePatchDiff] = [
            FilePatchDiff(filePath: "audit/writer.go", additions: 34, deletions: 18, statusLetter: .modified, lines: []),
            FilePatchDiff(filePath: "go.mod", additions: 2, deletions: 14, statusLetter: .modified, lines: []),
        ]
        for idx in 1...16 {
            diffs.append(
                FilePatchDiff(
                    filePath: "internal/svc\(idx % 9)/handler_\(idx).go",
                    additions: 15,
                    deletions: 7,
                    statusLetter: .modified,
                    lines: []
                )
            )
        }
        for idx in 1...5 {
            diffs.append(
                FilePatchDiff(
                    filePath: "tests/pkg\(idx)/service_test.go",
                    additions: 27,
                    deletions: 11,
                    statusLetter: .modified,
                    lines: []
                )
            )
        }

        let snapshot = WatchDiffTriageEngine.buildChangesSnapshot(from: diffs)
        XCTAssertTrue(snapshot.isGroupedMode)
        XCTAssertFalse(snapshot.canAcceptAllOnWatch)
        XCTAssertEqual(snapshot.totalFiles, 23)
        XCTAssertEqual(snapshot.worthALookFiles.count, 2)
        XCTAssertEqual(snapshot.worthALookFiles.map(\.filePath), ["audit/writer.go", "go.mod"])
        XCTAssertEqual(snapshot.worthALookFiles[0].summary, "Log field names change")
        XCTAssertEqual(snapshot.worthALookFiles[1].summary, "Removes a dependency")
        XCTAssertEqual(snapshot.groupedFileCount, 21)
        XCTAssertEqual(snapshot.intentGroups.first?.count, 16)
        XCTAssertEqual(snapshot.intentGroups.last?.count, 5)
    }

    // MARK: - W04 Artifact Summarizer (<= 3 key points + single primary action)

    func testArtifactSummarizerClampsToThreePointsAndSelectsPrimaryAction() {
        let walkthrough = ArtifactSnapshot(
            artifactPath: "/brain/walkthrough.md",
            title: "Walkthrough",
            summary: "Per-tenant token bucket",
            kind: .walkthrough,
            content: """
            # Per-tenant token bucket

            - Limiter in `ratelimit.go`, keyed by tenant
            - Rate, burst and TTL come from config
            - p99 3.8 ms at 1000/s
            - Fourth point must be dropped on Apple Watch
            - Fifth point must also be dropped
            """
        )

        let summary = WatchArtifactSummarizer.buildSummary(from: walkthrough, maxPoints: 5)
        XCTAssertEqual(summary.title, "Walkthrough")
        XCTAssertEqual(summary.headline, "Per-tenant token bucket")
        XCTAssertEqual(summary.points.count, 3)
        XCTAssertEqual(summary.pointsCountLabel, "3 key points")
        XCTAssertEqual(summary.primaryAction, .seeChanges)
        XCTAssertTrue(summary.points[0].spans.contains(WatchStyledTextSpan(text: "ratelimit.go", kind: .code)))
        XCTAssertTrue(summary.points[2].spans.contains(WatchStyledTextSpan(text: "3.8 ms", kind: .metricHighlight)))

        let plan = ArtifactSnapshot(
            artifactPath: "/brain/implementation_plan.md",
            title: "Implementation Plan",
            summary: "Add token bucket middleware",
            kind: .implementationPlan,
            requestFeedback: true,
            content: """
            - Add `ratelimit.go`
            - Register on `POST /transfers`
            - Keep p99 under 5 ms
            - Extra item clamped
            """
        )
        let planSummary = WatchArtifactSummarizer.buildSummary(from: plan)
        XCTAssertEqual(planSummary.title, "Plan")
        XCTAssertEqual(planSummary.points.count, 3)
        XCTAssertEqual(planSummary.primaryAction, .proceed)
        XCTAssertEqual(planSummary.primaryAction.buttonTitle, "Proceed")
    }

    // MARK: - WTC-11: Wire Codec, Wrist-Unlock Flags & Forward-Compatible Enum Resilience

    func testWTC11_WatchConnectivityCodecRoundTripAndResilientDecoding() async throws {
        let original = WatchVerificationFixtures.makeSnapshot(for: .sessions)
        let data = try XCTUnwrap(WatchConnectivityCodec.encodeSnapshot(original))
        // Verify compact wire budget (< 32KB, safely within WCSession 65KB applicationContext cap)
        XCTAssertLessThan(data.count, 32_768)

        let payload = try XCTUnwrap(WatchConnectivityCodec.encodeSnapshotPayload(original))
        let decoded = try XCTUnwrap(WatchConnectivityCodec.decodeSnapshotPayload(payload))
        XCTAssertEqual(decoded.activeDeviceName, "MacBook Pro")
        XCTAssertEqual(decoded.devices.count, 3)
        XCTAssertEqual(decoded.sessions.count, 3)
        XCTAssertEqual(decoded.activeApproval?.commandLine, "vegeta attack -rate=2000/s -duration=30s")

        // Verify approval command carries wristVerified and requiresWristUnlockApproval
        let approveCmd = WatchRemoteCommand(
            kind: .approveCommand,
            cascadeId: WatchVerificationFixtures.rateLimiterCascadeId,
            stepIndex: 5,
            wristVerified: true
        )
        XCTAssertTrue(approveCmd.kind.requiresWristUnlockApproval)
        XCTAssertTrue(WatchRemoteCommandKind.proceedPlan.requiresWristUnlockApproval)
        XCTAssertTrue(WatchRemoteCommandKind.acceptAllChanges.requiresWristUnlockApproval)
        XCTAssertFalse(WatchRemoteCommandKind.createVoiceTask.requiresWristUnlockApproval)
        XCTAssertFalse(WatchRemoteCommandKind.sendVoiceReply.requiresWristUnlockApproval)

        let approvePayload = try XCTUnwrap(WatchConnectivityCodec.encodeCommandPayload(approveCmd))
        let decodedApprove = try XCTUnwrap(WatchConnectivityCodec.decodeCommandPayload(approvePayload))
        XCTAssertEqual(decodedApprove.kind, .approveCommand)
        XCTAssertTrue(decodedApprove.wristVerified)

        // Verify backward compatibility when legacy command JSON omits wristVerified (defaults safely to false)
        let legacyJson = Data(#"{"id":"legacy-1","kind":"approveCommand","cascadeId":"cas-1","createdAt":"2026-01-01T00:00:00Z"}"#.utf8)
        let decodedLegacy = try XCTUnwrap(WatchConnectivityCodec.decodeCommand(from: legacyJson))
        XCTAssertFalse(decodedLegacy.wristVerified)

        // Verify deterministic wrist verifiers
        let unlockedOk = await AlwaysAuthorizedWristVerifier().verifyUnlockedOnWrist(reason: "Test")
        let lockedOk = await LockedOffWristVerifier().verifyUnlockedOnWrist(reason: "Test")
        XCTAssertTrue(unlockedOk)
        XCTAssertFalse(lockedOk)

        // Verify createVoiceTask title derivation
        let newTaskCmd = WatchRemoteCommand(
            kind: .createVoiceTask,
            deviceId: "macbook-pro",
            text: "Fix flaky webhook retries on staging"
        )
        let newTaskPayload = try XCTUnwrap(WatchConnectivityCodec.encodeCommandPayload(newTaskCmd))
        let decodedNewTask = try XCTUnwrap(WatchConnectivityCodec.decodeCommandPayload(newTaskPayload))
        XCTAssertEqual(decodedNewTask.kind, .createVoiceTask)
        XCTAssertEqual(WatchRemoteCommand.derivedTaskTitle(from: decodedNewTask.text ?? ""), "Fix flaky webhook retries")

        // Verify notification userInfo parsing for Watch W08 Long-Look scene
        let notifInfo: [AnyHashable: Any] = [
            "cascadeId": WatchVerificationFixtures.rateLimiterCascadeId,
            "cascadeTitle": "Rate limiter",
            "stepIndex": 5,
            "totalSteps": 7,
            "promptTitle": "Run this command?",
            "commandLine": "vegeta attack -rate=2000/s -duration=30s",
        ]
        let parsedApproval = try XCTUnwrap(WatchConnectivityCodec.pendingApproval(fromNotificationUserInfo: notifInfo))
        XCTAssertEqual(parsedApproval.cascadeId, WatchVerificationFixtures.rateLimiterCascadeId)
        XCTAssertEqual(parsedApproval.contextSubtitle, "Rate limiter · step 5 of 7")
        XCTAssertEqual(parsedApproval.commandLine, "vegeta attack -rate=2000/s -duration=30s")

        // Verify resilient fallback for future unknown Watch enum wire strings
        let unknownStatus = try JSONDecoder().decode(WatchSessionStatus.self, from: Data(#""futureStreamingV9""#.utf8))
        XCTAssertEqual(unknownStatus, .idle)
        let unknownDevice = try JSONDecoder().decode(WatchDeviceKind.self, from: Data(#""visionPro""#.utf8))
        XCTAssertEqual(unknownDevice, .laptop)
        let unknownCommand = try JSONDecoder().decode(WatchRemoteCommandKind.self, from: Data(#""futureGesture""#.utf8))
        XCTAssertEqual(unknownCommand, .requestRefresh)
        let unknownTarget = try JSONDecoder().decode(WatchPhoneHandoffTarget.self, from: Data(#""swarmBoard""#.utf8))
        XCTAssertEqual(unknownTarget, .chat)
        let unknownAction = try JSONDecoder().decode(WatchArtifactPrimaryAction.self, from: Data(#""futureAction""#.utf8))
        XCTAssertEqual(unknownAction, .seeChanges)
    }

    // MARK: - WTC-12: End-to-End iPhone Store <-> Watch Projection & Action Loop

    @MainActor
    func testWTC12_EndToEndStoreProjectionAndWatchCommandLoop() {
        let store = AntigravitySessionStore.makeESDDVerificationStore()
        let initialSnapshot = WatchCompanionProjector.project(from: store)

        XCTAssertFalse(initialSnapshot.devices.isEmpty)
        XCTAssertFalse(initialSnapshot.sessions.isEmpty)
        XCTAssertNotNil(initialSnapshot.activeApproval)
        XCTAssertTrue(initialSnapshot.devices.contains(where: { $0.kind == .cloud }))

        // 1. Switch device to Cloud from Watch -> iOS selectedHostScope updates -> re-projected snapshot marks Cloud selected
        store.selectHostScope(.antigravityCloud)
        let afterDeviceSwitch = WatchCompanionProjector.project(from: store)
        XCTAssertEqual(afterDeviceSwitch.activeDeviceKind, .cloud)
        XCTAssertTrue(afterDeviceSwitch.devices.first(where: { $0.id == "cloud" })?.isSelected == true)

        // 2. Approve waiting command from Watch -> waiting step resolves -> re-projected approval clears for active cascade
        if let waitingApproval = initialSnapshot.activeApproval {
            store.selectCascade(waitingApproval.cascadeId)
            store.approveWaitingCommandWithFaceID(stepIndex: waitingApproval.stepIndex)
            let afterApprove = WatchCompanionProjector.project(from: store)
            let updatedSession = afterApprove.sessions.first(where: { $0.cascadeId == waitingApproval.cascadeId })
            XCTAssertNotEqual(updatedSession?.status, .waitingApproval)
        }

        // 3. Create new voice task from Watch top-right mic -> creates new running cascade on iOS store
        let countBeforeNewTask = store.summaries.count
        store.createNewCascade(
            title: WatchRemoteCommand.derivedTaskTitle(from: WatchVerificationFixtures.sampleNewTaskVoiceTranscript),
            initialPrompt: WatchVerificationFixtures.sampleNewTaskVoiceTranscript
        )
        XCTAssertEqual(store.summaries.count, countBeforeNewTask + 1)
        let afterNewTask = WatchCompanionProjector.project(from: store)
        XCTAssertTrue(afterNewTask.sessions.contains(where: { $0.title == "Fix flaky webhook retries" }))

        // 4. Send voice reply from Watch -> appends user message into active conversation
        let targetCascade = store.activeCascadeId
        let stepCountBefore = store.stepsByCascadeId[targetCascade]?.count ?? 0
        store.composerDraftText = "Use 1000/s on staging, keep prod at 2000"
        store.sendCurrentDraft()
        let stepCountAfter = store.stepsByCascadeId[targetCascade]?.count ?? 0
        XCTAssertGreaterThan(stepCountAfter, stepCountBefore)
        let afterVoice = WatchCompanionProjector.project(from: store)
        let voiceSession = afterVoice.sessions.first(where: { $0.cascadeId == targetCascade })
        XCTAssertTrue(voiceSession?.recentMessages.contains(where: { $0.text.contains("Use 1000/s on staging") }) == true)

        // 5. Accept all changes from Watch -> clears activeTurnDiffs on iOS store
        XCTAssertFalse(store.activeTurnDiffs.isEmpty)
        store.acceptAllTurnDiffs()
        XCTAssertTrue(store.activeTurnDiffs.isEmpty)
    }

    // MARK: - All 8 Verification Fixtures Integrity

    func testAllEightWatchVerifyScenesProduceValidSnapshots() {
        for scene in WatchVerifySceneCase.allCases {
            let snap = WatchVerificationFixtures.makeSnapshot(for: scene)
            XCTAssertEqual(snap.devices.count, 3, "Expected 3 devices for \(scene.rawValue)")
            XCTAssertEqual(snap.sessions.count, 3, "Expected 3 sessions for \(scene.rawValue)")
            if let summary = snap.sessions.first?.artifactSummary {
                XCTAssertLessThanOrEqual(summary.points.count, 3)
            }
            if scene == .changedFilesGrouped {
                XCTAssertEqual(snap.sessions.first?.changes?.isGroupedMode, true)
                XCTAssertEqual(snap.sessions.first?.changes?.canAcceptAllOnWatch, false)
                XCTAssertEqual(snap.sessions.first?.changes?.totalFiles, 23)
            } else if scene == .changedFilesCompact {
                XCTAssertEqual(snap.sessions.first?.changes?.isGroupedMode, false)
                XCTAssertEqual(snap.sessions.first?.changes?.canAcceptAllOnWatch, true)
                XCTAssertEqual(snap.sessions.first?.changes?.totalFiles, 4)
            }
        }
    }
}
