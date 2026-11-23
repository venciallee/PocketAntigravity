import XCTest
@testable import AntigravityData

final class WatchCompanionTests: XCTestCase {

    // MARK: - W05 / W06 Diff Triage Engine

    func testDiffTriageEngineCompactModeForSmallChangeSet() {
        let diffs: [FilePatchDiff] = [
            FilePatchDiff(filePath: "ratelimit.go", additions: 96, deletions: 0, hunkHeader: "@@ -0,0 +1,96 @@ Per-tenant token bucket", statusLetter: .added, lines: []),
            FilePatchDiff(filePath: "router.go", additions: 12, deletions: 6, hunkHeader: "@@ -10,6 +10,12 @@ Limiter on POST /transfers", statusLetter: .modified, lines: []),
            FilePatchDiff(filePath: "config.go", additions: 14, deletions: 2, hunkHeader: "@@ -4,2 +4,14 @@ Rate, burst, TTL settings", statusLetter: .modified, lines: []),
            FilePatchDiff(filePath: "ratelimit_test.go", additions: 6, deletions: 6, hunkHeader: "@@ -1,6 +1,6 @@ Unit tests", statusLetter: .modified, lines: []),
        ]

        let snapshot = WatchDiffTriageEngine.buildChangesSnapshot(from: diffs)
        XCTAssertFalse(snapshot.isGroupedMode)
        XCTAssertEqual(snapshot.totalFiles, 4)
        XCTAssertEqual(snapshot.totalAdditions, 128)
        XCTAssertEqual(snapshot.totalDeletions, 14)
        XCTAssertEqual(snapshot.compactFiles.count, 4)
        XCTAssertEqual(snapshot.compactFiles[0].statusLetter, .added)
        XCTAssertEqual(snapshot.compactFiles[0].filePath, "ratelimit.go")
        XCTAssertTrue(snapshot.worthALookFiles.isEmpty)
        XCTAssertTrue(snapshot.intentGroups.isEmpty)
    }

    func testDiffTriageEngineIntentGroupedModeForLargeChangeSet() {
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
        XCTAssertEqual(snapshot.totalFiles, 23)
        XCTAssertEqual(snapshot.worthALookFiles.count, 2)
        XCTAssertEqual(snapshot.worthALookFiles.map(\.filePath), ["audit/writer.go", "go.mod"])
        XCTAssertEqual(snapshot.worthALookFiles[0].summary, "Log field names change")
        XCTAssertEqual(snapshot.worthALookFiles[1].summary, "Removes a dependency")
        XCTAssertEqual(snapshot.groupedFileCount, 21)
        XCTAssertEqual(snapshot.intentGroups.first?.count, 16)
        XCTAssertEqual(snapshot.intentGroups.last?.count, 5)
    }

    // MARK: - W04 Artifact Summarizer

    func testArtifactSummarizerExtractsCodeAndMetricSpans() {
        let artifact = ArtifactSnapshot(
            artifactPath: "/brain/walkthrough.md",
            title: "Walkthrough",
            summary: "Per-tenant token bucket",
            kind: .walkthrough,
            content: """
            # Per-tenant token bucket

            - Limiter in `ratelimit.go`, keyed by tenant
            - Rate, burst and TTL come from config
            - p99 3.8 ms at 1000/s
            """
        )

        let summary = WatchArtifactSummarizer.buildSummary(from: artifact)
        XCTAssertEqual(summary.title, "Walkthrough")
        XCTAssertEqual(summary.headline, "Per-tenant token bucket")
        XCTAssertEqual(summary.points.count, 3)
        XCTAssertEqual(summary.pointsCountLabel, "3 key points")
        XCTAssertTrue(summary.points[0].spans.contains(WatchStyledTextSpan(text: "ratelimit.go", kind: .code)))
        XCTAssertTrue(summary.points[2].spans.contains(WatchStyledTextSpan(text: "3.8 ms", kind: .metricHighlight)))
    }

    // MARK: - Wire Codec & Forward-Compatible Enum Resilience

    func testWatchConnectivityCodecRoundTripAndResilientDecoding() throws {
        let original = WatchVerificationFixtures.makeSnapshot(for: .sessions)
        let payload = try XCTUnwrap(WatchConnectivityCodec.encodeSnapshotPayload(original))
        let decoded = try XCTUnwrap(WatchConnectivityCodec.decodeSnapshotPayload(payload))
        XCTAssertEqual(decoded.activeDeviceName, "MacBook Pro")
        XCTAssertEqual(decoded.devices.count, 3)
        XCTAssertEqual(decoded.sessions.count, 3)
        XCTAssertEqual(decoded.activeApproval?.commandLine, "vegeta attack -rate=2000/s -duration=30s")

        let command = WatchRemoteCommand(
            kind: .sendVoiceReply,
            cascadeId: WatchVerificationFixtures.rateLimiterCascadeId,
            text: "Use 1000/s on staging, keep prod at 2000"
        )
        let cmdPayload = try XCTUnwrap(WatchConnectivityCodec.encodeCommandPayload(command))
        let decodedCmd = try XCTUnwrap(WatchConnectivityCodec.decodeCommandPayload(cmdPayload))
        XCTAssertEqual(decodedCmd.kind, .sendVoiceReply)
        XCTAssertEqual(decodedCmd.text, "Use 1000/s on staging, keep prod at 2000")

        // Verify resilient fallback for future unknown Watch enum wire strings
        let unknownStatus = try JSONDecoder().decode(WatchSessionStatus.self, from: Data(#""futureStreamingV9""#.utf8))
        XCTAssertEqual(unknownStatus, .idle)
        let unknownDevice = try JSONDecoder().decode(WatchDeviceKind.self, from: Data(#""visionPro""#.utf8))
        XCTAssertEqual(unknownDevice, .laptop)
        let unknownCommand = try JSONDecoder().decode(WatchRemoteCommandKind.self, from: Data(#""futureGesture""#.utf8))
        XCTAssertEqual(unknownCommand, .requestRefresh)
    }

    // MARK: - Live Store -> Watch Projection

    @MainActor
    func testWatchCompanionProjectorFromSessionStore() {
        let store = AntigravitySessionStore.makeESDDVerificationStore()
        let snapshot = WatchCompanionProjector.project(from: store)

        XCTAssertFalse(snapshot.devices.isEmpty)
        XCTAssertFalse(snapshot.sessions.isEmpty)
        XCTAssertNotNil(snapshot.activeApproval)
        XCTAssertTrue(snapshot.devices.contains(where: { $0.kind == .cloud }))
    }

    // MARK: - All 8 Verification Fixtures Integrity

    func testAllEightWatchVerifyScenesProduceValidSnapshots() {
        for scene in WatchVerifySceneCase.allCases {
            let snap = WatchVerificationFixtures.makeSnapshot(for: scene)
            XCTAssertEqual(snap.devices.count, 3, "Expected 3 devices for \(scene.rawValue)")
            XCTAssertEqual(snap.sessions.count, 3, "Expected 3 sessions for \(scene.rawValue)")
            if scene == .changedFilesGrouped {
                XCTAssertEqual(snap.sessions.first?.changes?.isGroupedMode, true)
                XCTAssertEqual(snap.sessions.first?.changes?.totalFiles, 23)
            } else if scene == .changedFilesCompact {
                XCTAssertEqual(snap.sessions.first?.changes?.isGroupedMode, false)
                XCTAssertEqual(snap.sessions.first?.changes?.totalFiles, 4)
            }
        }
    }
}
