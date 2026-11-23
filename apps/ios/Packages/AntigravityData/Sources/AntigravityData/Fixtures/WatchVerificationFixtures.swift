import Foundation

/// Deterministic Apple Watch verification fixtures aligned 1:1 with the 8 reference Watch UE mockups:
/// - `W01_SESSIONS`: Watch · 会话列表
/// - `W02_DEVICES`: Watch · 在线设备
/// - `W03_CHAT_STREAM`: Watch · 对话流
/// - `W04_ARTIFACT_SUMMARY`: Watch · 产物摘要
/// - `W05_CHANGED_FILES_COMPACT`: Watch · 改动文件（少量）
/// - `W06_CHANGED_FILES_GROUPED`: Watch · 改动文件（大量，按意图分组）
/// - `W07_VOICE_INPUT`: Watch · 语音输入
/// - `W08_APPROVAL_NOTIFICATION`: Watch · 通知（待批准）
public enum WatchVerificationFixtures {
    public static let rateLimiterCascadeId = "cas-rate-limiter"
    public static let darkModeCascadeId = "cas-dark-mode-settings"
    public static let upgradeGoCascadeId = "cas-upgrade-go-125"

    public static func makeDevices() -> [WatchDeviceSnapshot] {
        [
            WatchDeviceSnapshot(
                id: "macbook-pro",
                name: "MacBook Pro",
                kind: .laptop,
                isOnline: true,
                runningCount: 1,
                lastSeenLabel: nil,
                isSelected: true
            ),
            WatchDeviceSnapshot(
                id: "cloud",
                name: "Cloud",
                kind: .cloud,
                isOnline: true,
                runningCount: 1,
                lastSeenLabel: nil,
                isSelected: false
            ),
            WatchDeviceSnapshot(
                id: "office-imac",
                name: "Office iMac",
                kind: .desktop,
                isOnline: false,
                runningCount: 0,
                lastSeenLabel: "seen 3h ago",
                isSelected: false
            ),
        ]
    }

    public static func makeWalkthroughSummary() -> WatchArtifactSummarySnapshot {
        WatchArtifactSummarySnapshot(
            id: "walkthrough-rate-limiter",
            title: "Walkthrough",
            headline: "Per-tenant token bucket",
            artifactPath: "/brain/walkthrough.md",
            points: [
                WatchArtifactPoint(
                    index: 1,
                    spans: [
                        WatchStyledTextSpan(text: "Limiter in ", kind: .plain),
                        WatchStyledTextSpan(text: "ratelimit.go", kind: .code),
                        WatchStyledTextSpan(text: ", keyed by tenant", kind: .plain),
                    ]
                ),
                WatchArtifactPoint(
                    index: 2,
                    spans: [
                        WatchStyledTextSpan(text: "Rate, burst and TTL come from config", kind: .plain),
                    ]
                ),
                WatchArtifactPoint(
                    index: 3,
                    spans: [
                        WatchStyledTextSpan(text: "p99 ", kind: .plain),
                        WatchStyledTextSpan(text: "3.8 ms", kind: .metricHighlight),
                        WatchStyledTextSpan(text: " at 1000/s", kind: .plain),
                    ]
                ),
            ]
        )
    }

    public static func makeCompactChanges() -> WatchChangesSnapshot {
        WatchChangesSnapshot(
            totalFiles: 4,
            totalAdditions: 128,
            totalDeletions: 14,
            compactFiles: [
                WatchChangedFileItem(
                    filePath: "ratelimit.go",
                    statusLetter: .added,
                    summary: "Per-tenant token bucket",
                    additions: 96,
                    deletions: 0
                ),
                WatchChangedFileItem(
                    filePath: "router.go",
                    statusLetter: .modified,
                    summary: "Limiter on POST /transfers",
                    additions: 12,
                    deletions: 6
                ),
                WatchChangedFileItem(
                    filePath: "config.go",
                    statusLetter: .modified,
                    summary: "Rate, burst, TTL settings",
                    additions: 14,
                    deletions: 2
                ),
                WatchChangedFileItem(
                    filePath: "ratelimit_test.go",
                    statusLetter: .added,
                    summary: "Burst & eviction unit tests",
                    additions: 6,
                    deletions: 6
                ),
            ],
            worthALookFiles: [],
            intentGroups: [],
            isGroupedMode: false
        )
    }

    public static func makeGroupedChanges() -> WatchChangesSnapshot {
        WatchChangesSnapshot(
            totalFiles: 23,
            totalAdditions: 412,
            totalDeletions: 198,
            compactFiles: [],
            worthALookFiles: [
                WatchChangedFileItem(
                    filePath: "audit/writer.go",
                    statusLetter: .modified,
                    summary: "Log field names change",
                    additions: 34,
                    deletions: 18,
                    isWorthALook: true
                ),
                WatchChangedFileItem(
                    filePath: "go.mod",
                    statusLetter: .modified,
                    summary: "Removes a dependency",
                    additions: 2,
                    deletions: 14,
                    isWorthALook: true
                ),
            ],
            intentGroups: [
                WatchFileIntentGroup(
                    id: "grp-callsites",
                    count: 16,
                    title: "Call sites → updated",
                    subtitle: "Mechanical · 9 dirs",
                    filePaths: (1...16).map { "internal/svc\($0)/handler.go" }
                ),
                WatchFileIntentGroup(
                    id: "grp-tests",
                    count: 5,
                    title: "Test fixtures",
                    subtitle: "Mechanical · 3 dirs",
                    filePaths: (1...5).map { "tests/suite\($0)_test.go" }
                ),
            ],
            isGroupedMode: true
        )
    }

    public static func makePendingApproval() -> WatchPendingApproval {
        WatchPendingApproval(
            id: "approval-vegeta-step5",
            cascadeId: rateLimiterCascadeId,
            cascadeTitle: "Rate limiter",
            stepIndex: 5,
            totalSteps: 7,
            promptTitle: "Run this command?",
            commandLine: "vegeta attack -rate=2000/s -duration=30s",
            relativeTimeLabel: "now"
        )
    }

    /// Canonical Watch snapshot matching the 8 reference mockups (`W01`..`W08`).
    public static func makeSnapshot(for scene: WatchVerifySceneCase = .sessions) -> WatchCompanionSnapshot {
        let rateLimiterStatus: WatchSessionStatus = (scene == .chatStream) ? .running : .waitingApproval
        let rateLimiterChanges = (scene == .changedFilesGrouped) ? makeGroupedChanges() : makeCompactChanges()
        let approval = makePendingApproval()

        let sessions: [WatchSessionSnapshot] = [
            WatchSessionSnapshot(
                cascadeId: rateLimiterCascadeId,
                title: "Rate limiter",
                status: rateLimiterStatus,
                isCloud: false,
                currentStepIndex: 6,
                totalSteps: 7,
                statusSubtitle: "Approve command",
                additions: rateLimiterChanges.totalAdditions,
                deletions: rateLimiterChanges.totalDeletions,
                hasUnread: true,
                hostName: "MacBook Pro",
                recentMessages: [
                    WatchChatBubbleItem(
                        id: "msg-user-voice-1",
                        isUser: true,
                        isVoiceInput: true,
                        text: "Use 1000/s on staging"
                    ),
                    WatchChatBubbleItem(
                        id: "msg-agent-1",
                        isUser: false,
                        isVoiceInput: false,
                        text: "Load test passed. p99 is 3.8 ms at 1000/s."
                    ),
                ],
                artifactSummary: makeWalkthroughSummary(),
                changes: rateLimiterChanges,
                pendingApproval: (scene == .chatStream) ? nil : approval
            ),
            WatchSessionSnapshot(
                cascadeId: darkModeCascadeId,
                title: "Dark mode settings",
                status: .running,
                isCloud: true,
                currentStepIndex: 2,
                totalSteps: 5,
                statusSubtitle: "Cloud · 2 of 5",
                additions: 54,
                deletions: 12,
                hasUnread: false,
                hostName: "Cloud",
                recentMessages: [
                    WatchChatBubbleItem(
                        id: "msg-dm-1",
                        isUser: true,
                        isVoiceInput: false,
                        text: "Sync system appearance across tabs"
                    ),
                    WatchChatBubbleItem(
                        id: "msg-dm-2",
                        isUser: false,
                        isVoiceInput: false,
                        text: "Updating theme tokens and verifying WCAG contrast."
                    ),
                ],
                artifactSummary: nil,
                changes: nil,
                pendingApproval: nil
            ),
            WatchSessionSnapshot(
                cascadeId: upgradeGoCascadeId,
                title: "Upgrade to Go 1.25",
                status: .done,
                isCloud: false,
                currentStepIndex: 4,
                totalSteps: 4,
                statusSubtitle: "Done",
                additions: 42,
                deletions: 31,
                hasUnread: true,
                hostName: "MacBook Pro",
                recentMessages: [
                    WatchChatBubbleItem(
                        id: "msg-go-1",
                        isUser: false,
                        isVoiceInput: false,
                        text: "Updated go.mod and CI toolchain to Go 1.25. All tests pass."
                    ),
                ],
                artifactSummary: nil,
                changes: makeGroupedChanges(),
                pendingApproval: nil
            ),
        ]

        return WatchCompanionSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_760_000_000),
            activeDeviceId: "macbook-pro",
            activeDeviceName: "MacBook Pro",
            activeDeviceKind: .laptop,
            activeDeviceOnline: true,
            devices: makeDevices(),
            sessions: sessions,
            activeApproval: approval
        )
    }

    /// Sample Implementation Plan summary demonstrating `<= 3` points + `Proceed` primary CTA (Double Tap + wrist-unlock gated).
    public static func makeImplementationPlanSummary() -> WatchArtifactSummarySnapshot {
        WatchArtifactSummarySnapshot(
            id: "plan-rate-limiter",
            title: "Plan",
            headline: "Per-tenant rate limiter",
            artifactPath: "/brain/implementation_plan.md",
            points: [
                WatchArtifactPoint(
                    index: 1,
                    spans: [
                        WatchStyledTextSpan(text: "Add token bucket in ", kind: .plain),
                        WatchStyledTextSpan(text: "ratelimit.go", kind: .code),
                    ]
                ),
                WatchArtifactPoint(
                    index: 2,
                    spans: [
                        WatchStyledTextSpan(text: "Wire middleware on ", kind: .plain),
                        WatchStyledTextSpan(text: "POST /transfers", kind: .code),
                    ]
                ),
                WatchArtifactPoint(
                    index: 3,
                    spans: [
                        WatchStyledTextSpan(text: "Target p99 under ", kind: .plain),
                        WatchStyledTextSpan(text: "5 ms", kind: .metricHighlight),
                    ]
                ),
            ],
            primaryAction: .proceed
        )
    }

    public static let sampleVoiceCommittedTranscript = "Use 1000/s on staging, keep prod at "
    public static let sampleVoicePartialWord = "2000"
    public static let sampleNewTaskVoiceTranscript = "Fix flaky webhook retries on staging"
}
