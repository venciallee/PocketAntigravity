import Foundation

// MARK: - Apple Watch Companion Verification & Domain Enums (Forward-Compatible)

/// Deterministic Apple Watch visual verification scenes (`W01` .. `W08`).
public enum WatchVerifySceneCase: String, ResilientStringEnum, CaseIterable, Identifiable {
    case sessions = "W01_SESSIONS"
    case devices = "W02_DEVICES"
    case chatStream = "W03_CHAT_STREAM"
    case artifactSummary = "W04_ARTIFACT_SUMMARY"
    case changedFilesCompact = "W05_CHANGED_FILES_COMPACT"
    case changedFilesGrouped = "W06_CHANGED_FILES_GROUPED"
    case voiceInput = "W07_VOICE_INPUT"
    case approvalNotification = "W08_APPROVAL_NOTIFICATION"

    public var id: String { rawValue }
    public static var unknownFallback: WatchVerifySceneCase { .sessions }
}

/// Session lifecycle badge shown on Apple Watch session rows (`W01`) and chat headers (`W03`).
public enum WatchSessionStatus: String, ResilientStringEnum, CaseIterable {
    case waitingApproval
    case running
    case done
    case error
    case idle

    public static var unknownFallback: WatchSessionStatus { .idle }
}

/// Hardware / runtime icon category for devices listed on `W02_DEVICES`.
public enum WatchDeviceKind: String, ResilientStringEnum, CaseIterable {
    case laptop
    case cloud
    case desktop

    public static var unknownFallback: WatchDeviceKind { .laptop }

    public var sfSymbolName: String {
        switch self {
        case .laptop: return "laptopcomputer"
        case .cloud: return "cloud"
        case .desktop: return "desktopcomputer"
        }
    }
}

/// Inline text span emphasis used inside Watch artifact summary key points (`W04`).
public enum WatchStyledSpanKind: String, ResilientStringEnum, CaseIterable {
    case plain
    case code
    case metricHighlight

    public static var unknownFallback: WatchStyledSpanKind { .plain }
}

/// Compact file diff status letter (`A` / `M` / `D` / `R`) shown in Watch Changed Files (`W05`, `W06`).
public enum WatchFileStatusLetter: String, ResilientStringEnum, CaseIterable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"

    public static var unknownFallback: WatchFileStatusLetter { .modified }
}

/// Deep-link target when handing off a Watch screen to iPhone (`W04`, `W05`, `W06`).
public enum WatchPhoneHandoffTarget: String, ResilientStringEnum, CaseIterable {
    case chat
    case artifact
    case changes

    public static var unknownFallback: WatchPhoneHandoffTarget { .chat }
}

/// Primary CTA shown on Watch Artifact Summary (`W04`): `See changes` (Walkthrough) or `Proceed` (Implementation Plan).
public enum WatchArtifactPrimaryAction: String, ResilientStringEnum, CaseIterable {
    case seeChanges
    case proceed

    public static var unknownFallback: WatchArtifactPrimaryAction { .seeChanges }

    public var buttonTitle: String {
        switch self {
        case .seeChanges: return "See changes"
        case .proceed: return "Proceed"
        }
    }
}

/// Action kinds dispatched from Apple Watch back to the paired iPhone companion over `WatchConnectivity`.
public enum WatchRemoteCommandKind: String, ResilientStringEnum, CaseIterable {
    case selectDevice
    case approveCommand
    case denyCommand
    case sendVoiceReply
    case createVoiceTask
    case proceedPlan
    case acceptAllChanges
    case openOnPhone
    case requestRefresh

    public static var unknownFallback: WatchRemoteCommandKind { .requestRefresh }

    /// Approval-class actions require an unlocked Apple Watch worn on the user's wrist.
    public var requiresWristUnlockApproval: Bool {
        switch self {
        case .approveCommand, .proceedPlan, .acceptAllChanges:
            return true
        case .selectDevice, .denyCommand, .sendVoiceReply, .createVoiceTask, .openOnPhone, .requestRefresh:
            return false
        }
    }
}

/// Pure-Swift authorization contract implemented on watchOS via `LAContext`
/// (`LAPolicy.deviceOwnerAuthenticationWithWristDetection`) so approval actions require
/// an unlocked Apple Watch worn on the user's wrist.
public protocol WatchWristUnlockAuthorizing: Sendable {
    func verifyUnlockedOnWrist(reason: String) async -> Bool
}

/// Deterministic test/verification verifier representing an unlocked Apple Watch on wrist.
public struct AlwaysAuthorizedWristVerifier: WatchWristUnlockAuthorizing {
    public init() {}

    public func verifyUnlockedOnWrist(reason: String) async -> Bool {
        true
    }
}

/// Deterministic test/verification verifier representing a locked or off-wrist Apple Watch.
public struct LockedOffWristVerifier: WatchWristUnlockAuthorizing {
    public init() {}

    public func verifyUnlockedOnWrist(reason: String) async -> Bool {
        false
    }
}

// MARK: - Apple Watch Compact Snapshot Models

/// Paired host or Cloud runtime entry rendered on `W02_DEVICES`.
public struct WatchDeviceSnapshot: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var kind: WatchDeviceKind
    public var isOnline: Bool
    public var runningCount: Int
    public var lastSeenLabel: String?
    public var isSelected: Bool

    public init(
        id: String,
        name: String,
        kind: WatchDeviceKind,
        isOnline: Bool,
        runningCount: Int = 0,
        lastSeenLabel: String? = nil,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isOnline = isOnline
        self.runningCount = runningCount
        self.lastSeenLabel = lastSeenLabel
        self.isSelected = isSelected
    }

    public var subtitleText: String {
        if isOnline {
            if runningCount > 0 {
                return "Online · \(runningCount) running"
            }
            return "Online · Idle"
        }
        if let lastSeenLabel, !lastSeenLabel.isEmpty {
            return "Offline · \(lastSeenLabel)"
        }
        return "Offline"
    }
}

/// Compact chat turn bubble rendered on `W03_CHAT_STREAM`.
public struct WatchChatBubbleItem: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var isUser: Bool
    public var isVoiceInput: Bool
    public var text: String

    public init(
        id: String = UUID().uuidString,
        isUser: Bool,
        isVoiceInput: Bool = false,
        text: String
    ) {
        self.id = id
        self.isUser = isUser
        self.isVoiceInput = isVoiceInput
        self.text = text
    }
}

/// Styled inline span inside a Watch artifact bullet point (`W04`).
public struct WatchStyledTextSpan: Codable, Sendable, Equatable, Hashable {
    public var text: String
    public var kind: WatchStyledSpanKind

    public init(text: String, kind: WatchStyledSpanKind = .plain) {
        self.text = text
        self.kind = kind
    }
}

/// Numbered takeaway item inside `WatchArtifactSummarySnapshot` (`W04`).
public struct WatchArtifactPoint: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var index: Int
    public var spans: [WatchStyledTextSpan]

    public init(
        id: String? = nil,
        index: Int,
        spans: [WatchStyledTextSpan]
    ) {
        self.id = id ?? "pt-\(index)"
        self.index = index
        self.spans = spans
    }

    public var plainText: String {
        spans.map(\.text).joined()
    }
}

/// Distilled walkthrough / implementation-plan artifact summary rendered on `W03` card and `W04` screen.
/// Strictly limited to title + headline + `<= 3` numbered key points + single primary action (`See changes` or `Proceed`).
public struct WatchArtifactSummarySnapshot: Codable, Sendable, Equatable, Identifiable, Hashable {
    public static let maxKeyPoints = 3

    public var id: String
    public var title: String
    public var headline: String
    public var artifactPath: String
    public var points: [WatchArtifactPoint]
    public var primaryAction: WatchArtifactPrimaryAction

    private enum CodingKeys: String, CodingKey {
        case id, title, headline, artifactPath, points, primaryAction
    }

    public init(
        id: String = "artifact-summary",
        title: String = "Walkthrough",
        headline: String,
        artifactPath: String = "/brain/walkthrough.md",
        points: [WatchArtifactPoint],
        primaryAction: WatchArtifactPrimaryAction = .seeChanges
    ) {
        self.id = id
        self.title = title
        self.headline = headline
        self.artifactPath = artifactPath
        self.points = Array(points.prefix(Self.maxKeyPoints))
        self.primaryAction = primaryAction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.headline = try container.decode(String.self, forKey: .headline)
        self.artifactPath = try container.decode(String.self, forKey: .artifactPath)
        let decodedPoints = try container.decode([WatchArtifactPoint].self, forKey: .points)
        self.points = Array(decodedPoints.prefix(Self.maxKeyPoints))
        self.primaryAction = try container.decodeIfPresent(WatchArtifactPrimaryAction.self, forKey: .primaryAction) ?? .seeChanges
    }

    public var pointsCountLabel: String {
        let count = points.count
        return count == 1 ? "1 key point" : "\(count) key points"
    }
}

/// Single changed file row rendered in `W05` (compact list) or `W06` ("WORTH A LOOK" high-signal rows).
public struct WatchChangedFileItem: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var filePath: String
    public var statusLetter: WatchFileStatusLetter
    public var summary: String
    public var additions: Int
    public var deletions: Int
    public var isWorthALook: Bool

    public init(
        id: String? = nil,
        filePath: String,
        statusLetter: WatchFileStatusLetter = .modified,
        summary: String,
        additions: Int = 0,
        deletions: Int = 0,
        isWorthALook: Bool = false
    ) {
        self.id = id ?? filePath
        self.filePath = filePath
        self.statusLetter = statusLetter
        self.summary = summary
        self.additions = additions
        self.deletions = deletions
        self.isWorthALook = isWorthALook
    }

    public var displayName: String {
        let trimmed = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            if isWorthALook && parts.count >= 2 {
                return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
            }
            return String(parts.last ?? Substring(trimmed))
        }
        return trimmed
    }
}

/// Intent-clustered group of mechanical file edits shown under `GROUPED` on `W06`.
public struct WatchFileIntentGroup: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var count: Int
    public var title: String
    public var subtitle: String
    public var filePaths: [String]

    public init(
        id: String,
        count: Int,
        title: String,
        subtitle: String,
        filePaths: [String] = []
    ) {
        self.id = id
        self.count = count
        self.title = title
        self.subtitle = subtitle
        self.filePaths = filePaths
    }
}

/// Complete changed-files triage snapshot driving both `W05` (≤ 5 files AND zero risk items -> Watch `Accept all`)
/// and `W06` (> 5 files OR any risk item -> `WORTH A LOOK` + intent-grouped clusters + iPhone review CTA).
public struct WatchChangesSnapshot: Codable, Sendable, Equatable, Hashable {
    public static let defaultCompactThreshold = 5

    public var totalFiles: Int
    public var totalAdditions: Int
    public var totalDeletions: Int
    public var compactFiles: [WatchChangedFileItem]
    public var worthALookFiles: [WatchChangedFileItem]
    public var intentGroups: [WatchFileIntentGroup]
    public var isGroupedMode: Bool

    public init(
        totalFiles: Int,
        totalAdditions: Int,
        totalDeletions: Int,
        compactFiles: [WatchChangedFileItem] = [],
        worthALookFiles: [WatchChangedFileItem] = [],
        intentGroups: [WatchFileIntentGroup] = [],
        isGroupedMode: Bool? = nil
    ) {
        self.totalFiles = totalFiles
        self.totalAdditions = totalAdditions
        self.totalDeletions = totalDeletions
        self.compactFiles = compactFiles
        self.worthALookFiles = worthALookFiles
        self.intentGroups = intentGroups
        self.isGroupedMode = isGroupedMode
            ?? (totalFiles > Self.defaultCompactThreshold || !worthALookFiles.isEmpty || !intentGroups.isEmpty)
    }

    /// Only allow one-tap `Accept all` on Watch when `totalFiles <= 5`, zero risk items exist,
    /// and all changed files have been explicitly triaged in compact mode.
    public var canAcceptAllOnWatch: Bool {
        !isGroupedMode
            && worthALookFiles.isEmpty
            && !compactFiles.isEmpty
            && totalFiles > 0
            && totalFiles <= Self.defaultCompactThreshold
    }

    public var groupedFileCount: Int {
        let sum = intentGroups.reduce(0) { $0 + $1.count }
        return sum > 0 ? sum : max(0, totalFiles - worthALookFiles.count)
    }
}

/// Pending command approval payload driving both `W08` Watch notification & in-app approval gate.
public struct WatchPendingApproval: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var cascadeId: String
    public var cascadeTitle: String
    public var stepIndex: Int
    public var totalSteps: Int
    public var promptTitle: String
    public var commandLine: String
    public var relativeTimeLabel: String

    public init(
        id: String? = nil,
        cascadeId: String,
        cascadeTitle: String,
        stepIndex: Int,
        totalSteps: Int,
        promptTitle: String = "Run this command?",
        commandLine: String,
        relativeTimeLabel: String = "now"
    ) {
        self.id = id ?? "\(cascadeId)-step-\(stepIndex)"
        self.cascadeId = cascadeId
        self.cascadeTitle = cascadeTitle
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        self.promptTitle = promptTitle
        self.commandLine = commandLine
        self.relativeTimeLabel = relativeTimeLabel
    }

    public var contextSubtitle: String {
        "\(cascadeTitle) · step \(max(1, stepIndex)) of \(max(stepIndex, totalSteps))"
    }
}

/// Compact session projection for Apple Watch (`W01` row + `W03` chat + `W04` artifact + `W05`/`W06` changes).
public struct WatchSessionSnapshot: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String { cascadeId }
    public var cascadeId: String
    public var title: String
    public var status: WatchSessionStatus
    public var isCloud: Bool
    public var currentStepIndex: Int
    public var totalSteps: Int
    public var statusSubtitle: String
    public var additions: Int
    public var deletions: Int
    public var hasUnread: Bool
    public var hostName: String
    public var recentMessages: [WatchChatBubbleItem]
    public var artifactSummary: WatchArtifactSummarySnapshot?
    public var changes: WatchChangesSnapshot?
    public var pendingApproval: WatchPendingApproval?

    public init(
        cascadeId: String,
        title: String,
        status: WatchSessionStatus,
        isCloud: Bool = false,
        currentStepIndex: Int = 1,
        totalSteps: Int = 7,
        statusSubtitle: String = "",
        additions: Int = 0,
        deletions: Int = 0,
        hasUnread: Bool = false,
        hostName: String = "MacBook Pro",
        recentMessages: [WatchChatBubbleItem] = [],
        artifactSummary: WatchArtifactSummarySnapshot? = nil,
        changes: WatchChangesSnapshot? = nil,
        pendingApproval: WatchPendingApproval? = nil
    ) {
        self.cascadeId = cascadeId
        self.title = title
        self.status = status
        self.isCloud = isCloud
        self.currentStepIndex = currentStepIndex
        self.totalSteps = totalSteps
        self.statusSubtitle = statusSubtitle
        self.additions = additions
        self.deletions = deletions
        self.hasUnread = hasUnread
        self.hostName = hostName
        self.recentMessages = recentMessages
        self.artifactSummary = artifactSummary
        self.changes = changes
        self.pendingApproval = pendingApproval
    }

    public var chatHeaderStatusText: String {
        switch status {
        case .running:
            return "Step \(max(1, currentStepIndex)) of \(max(currentStepIndex, totalSteps)) · Running"
        case .waitingApproval:
            return "Step \(max(1, currentStepIndex)) of \(max(currentStepIndex, totalSteps)) · Approve"
        case .done:
            return "Done · \(max(1, totalSteps)) steps"
        case .error:
            return "Needs attention"
        case .idle:
            return "Ready"
        }
    }
}

/// Top-level payload synced from iPhone `AGPocket` → Apple Watch `AGPocketWatch`.
public struct WatchCompanionSnapshot: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var activeDeviceId: String
    public var activeDeviceName: String
    public var activeDeviceKind: WatchDeviceKind
    public var activeDeviceOnline: Bool
    public var devices: [WatchDeviceSnapshot]
    public var sessions: [WatchSessionSnapshot]
    public var activeApproval: WatchPendingApproval?

    public init(
        version: Int = WatchCompanionSnapshot.schemaVersion,
        generatedAt: Date = Date(),
        activeDeviceId: String,
        activeDeviceName: String,
        activeDeviceKind: WatchDeviceKind = .laptop,
        activeDeviceOnline: Bool = true,
        devices: [WatchDeviceSnapshot],
        sessions: [WatchSessionSnapshot],
        activeApproval: WatchPendingApproval? = nil
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.activeDeviceId = activeDeviceId
        self.activeDeviceName = activeDeviceName
        self.activeDeviceKind = activeDeviceKind
        self.activeDeviceOnline = activeDeviceOnline
        self.devices = devices
        self.sessions = sessions
        self.activeApproval = activeApproval
    }
}

/// Command sent from Apple Watch `AGPocketWatch` → iPhone `AGPocket`.
public struct WatchRemoteCommand: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: WatchRemoteCommandKind
    public var deviceId: String?
    public var cascadeId: String?
    public var stepIndex: Int?
    public var artifactPath: String?
    public var text: String?
    public var handoffTarget: WatchPhoneHandoffTarget?
    /// Indicates watchOS verified the watch was unlocked and worn on wrist via
    /// `LAPolicy.deviceOwnerAuthenticationWithWristDetection` before dispatching an approval command.
    public var wristVerified: Bool
    public var createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, kind, deviceId, cascadeId, stepIndex, artifactPath, text, handoffTarget, wristVerified, createdAt
    }

    public init(
        id: String = UUID().uuidString,
        kind: WatchRemoteCommandKind,
        deviceId: String? = nil,
        cascadeId: String? = nil,
        stepIndex: Int? = nil,
        artifactPath: String? = nil,
        text: String? = nil,
        handoffTarget: WatchPhoneHandoffTarget? = nil,
        wristVerified: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.deviceId = deviceId
        self.cascadeId = cascadeId
        self.stepIndex = stepIndex
        self.artifactPath = artifactPath
        self.text = text
        self.handoffTarget = handoffTarget
        self.wristVerified = wristVerified
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.kind = try container.decode(WatchRemoteCommandKind.self, forKey: .kind)
        self.deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId)
        self.cascadeId = try container.decodeIfPresent(String.self, forKey: .cascadeId)
        self.stepIndex = try container.decodeIfPresent(Int.self, forKey: .stepIndex)
        self.artifactPath = try container.decodeIfPresent(String.self, forKey: .artifactPath)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.handoffTarget = try container.decodeIfPresent(WatchPhoneHandoffTarget.self, forKey: .handoffTarget)
        self.wristVerified = try container.decodeIfPresent(Bool.self, forKey: .wristVerified) ?? false
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// Derives a concise task title from a spoken voice prompt when creating a new task from Apple Watch.
    public static func derivedTaskTitle(from prompt: String) -> String {
        let cleaned = prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "New voice task" }
        let words = cleaned.split(whereSeparator: \.isWhitespace)
        let candidate = words.prefix(4).joined(separator: " ")
        if candidate.count <= 28 {
            return candidate
        }
        return String(candidate.prefix(27)) + "…"
    }
}

// MARK: - WatchConnectivity Wire Codec & Notification Constants

public enum WatchConnectivityCodec {
    public static let snapshotKey = "agpocket_watch_snapshot_v1"
    public static let commandKey = "agpocket_watch_command_v1"
    public static let handoffActivityType = "com.thousandtimes.agpocket.handoff"
    public static let approvalNotificationCategory = "AGPOCKET_APPROVAL_REQUEST"
    public static let allowActionIdentifier = "AGPOCKET_APPROVAL_ALLOW"
    public static let denyActionIdentifier = "AGPOCKET_APPROVAL_DENY"
    public static let replyVoiceActionIdentifier = "AGPOCKET_APPROVAL_REPLY_VOICE"

    private static var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private static var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    public static func encodeSnapshot(_ snapshot: WatchCompanionSnapshot) -> Data? {
        try? encoder.encode(snapshot)
    }

    public static func decodeSnapshot(from data: Data) -> WatchCompanionSnapshot? {
        try? decoder.decode(WatchCompanionSnapshot.self, from: data)
    }

    public static func encodeSnapshotPayload(_ snapshot: WatchCompanionSnapshot) -> [String: Any]? {
        guard let data = encodeSnapshot(snapshot) else { return nil }
        return [snapshotKey: data]
    }

    public static func decodeSnapshotPayload(_ payload: [String: Any]) -> WatchCompanionSnapshot? {
        if let data = payload[snapshotKey] as? Data {
            return decodeSnapshot(from: data)
        }
        if let b64 = payload[snapshotKey] as? String, let data = Data(base64Encoded: b64) {
            return decodeSnapshot(from: data)
        }
        return nil
    }

    public static func encodeCommand(_ command: WatchRemoteCommand) -> Data? {
        try? encoder.encode(command)
    }

    public static func decodeCommand(from data: Data) -> WatchRemoteCommand? {
        try? decoder.decode(WatchRemoteCommand.self, from: data)
    }

    public static func encodeCommandPayload(_ command: WatchRemoteCommand) -> [String: Any]? {
        guard let data = encodeCommand(command) else { return nil }
        return [commandKey: data]
    }

    public static func decodeCommandPayload(_ payload: [String: Any]) -> WatchRemoteCommand? {
        if let data = payload[commandKey] as? Data {
            return decodeCommand(from: data)
        }
        if let b64 = payload[commandKey] as? String, let data = Data(base64Encoded: b64) {
            return decodeCommand(from: data)
        }
        return nil
    }

    public static func pendingApproval(fromNotificationUserInfo userInfo: [AnyHashable: Any]) -> WatchPendingApproval? {
        guard let cascadeId = userInfo["cascadeId"] as? String, !cascadeId.isEmpty else {
            return nil
        }
        let cascadeTitle = (userInfo["cascadeTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandLine = (userInfo["commandLine"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptTitle = (userInfo["promptTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stepIndex = (userInfo["stepIndex"] as? Int) ?? 1
        let totalSteps = (userInfo["totalSteps"] as? Int) ?? max(stepIndex, 1)
        return WatchPendingApproval(
            cascadeId: cascadeId,
            cascadeTitle: (cascadeTitle?.isEmpty == false ? cascadeTitle! : "Agent task"),
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            promptTitle: (promptTitle?.isEmpty == false ? promptTitle! : "Run this command?"),
            commandLine: (commandLine?.isEmpty == false ? commandLine! : "Approve pending action"),
            relativeTimeLabel: "now"
        )
    }
}

// MARK: - Watch Diff Intent-Grouping Triage Engine (`W05` / `W06`)

/// Automatically chooses compact per-file listing (`<= 5` files AND zero risk items, `W05`, allowing Watch `Accept all`)
/// or high-signal intent-grouped triage (`> 5` files OR any risk item, `W06`: `WORTH A LOOK` + `GROUPED` clusters + iPhone CTA).
/// Never exposes source code lines on Apple Watch—strictly file path, `A`/`M`/`D` badge, and one-line summary.
public enum WatchDiffTriageEngine {
    private static let highSignalBasenames: Set<String> = [
        "go.mod", "go.sum", "package.json", "package-lock.json", "pnpm-lock.yaml",
        "package.swift", "cargo.toml", "pyproject.toml", "build.gradle.kts",
        "project.yml", "info.plist", "dockerfile"
    ]

    private static let highSignalPathTokens: [String] = [
        "audit", "auth", "security", "crypto", "secret", "keychain", "permission",
        "migration", "schema", "billing", "payment", "policy", "entitlement"
    ]

    public static func buildChangesSnapshot(
        from diffs: [FilePatchDiff],
        compactThreshold: Int = WatchChangesSnapshot.defaultCompactThreshold
    ) -> WatchChangesSnapshot {
        let totalFiles = diffs.count
        let totalAdditions = diffs.reduce(0) { $0 + max(0, $1.additions) }
        let totalDeletions = diffs.reduce(0) { $0 + max(0, $1.deletions) }

        guard !diffs.isEmpty else {
            return WatchChangesSnapshot(
                totalFiles: 0,
                totalAdditions: 0,
                totalDeletions: 0,
                compactFiles: [],
                worthALookFiles: [],
                intentGroups: [],
                isGroupedMode: false
            )
        }

        // Always inspect risk / high-signal items first, even when `totalFiles <= 5`.
        var worthALook: [WatchChangedFileItem] = []
        var remainder: [FilePatchDiff] = []

        for diff in diffs {
            if let riskReason = classifyHighSignalReason(for: diff), worthALook.count < 4 {
                worthALook.append(
                    WatchChangedFileItem(
                        filePath: diff.filePath,
                        statusLetter: mapStatusLetter(diff.statusLetter),
                        summary: riskReason,
                        additions: diff.additions,
                        deletions: diff.deletions,
                        isWorthALook: true
                    )
                )
            } else {
                remainder.append(diff)
            }
        }

        // Only allow compact `Accept all` mode when `<= 5` files AND zero risk items were flagged.
        if totalFiles <= compactThreshold && worthALook.isEmpty {
            let items = diffs.map { diff in
                WatchChangedFileItem(
                    filePath: diff.filePath,
                    statusLetter: mapStatusLetter(diff.statusLetter),
                    summary: inferSummary(for: diff),
                    additions: diff.additions,
                    deletions: diff.deletions,
                    isWorthALook: false
                )
            }
            return WatchChangesSnapshot(
                totalFiles: totalFiles,
                totalAdditions: totalAdditions,
                totalDeletions: totalDeletions,
                compactFiles: items,
                worthALookFiles: [],
                intentGroups: [],
                isGroupedMode: false
            )
        }

        // For large change sets (> 5 files) without explicit risk hits, surface the largest change under WORTH A LOOK.
        if worthALook.isEmpty, let largest = remainder.max(by: { ($0.additions + $0.deletions) < ($1.additions + $1.deletions) }) {
            worthALook.append(
                WatchChangedFileItem(
                    filePath: largest.filePath,
                    statusLetter: mapStatusLetter(largest.statusLetter),
                    summary: inferSummary(for: largest),
                    additions: largest.additions,
                    deletions: largest.deletions,
                    isWorthALook: true
                )
            )
            remainder.removeAll { $0.filePath == largest.filePath }
        }

        let groups = clusterMechanicalDiffs(remainder)
        return WatchChangesSnapshot(
            totalFiles: totalFiles,
            totalAdditions: totalAdditions,
            totalDeletions: totalDeletions,
            compactFiles: [],
            worthALookFiles: worthALook,
            intentGroups: groups,
            isGroupedMode: true
        )
    }

    private static func mapStatusLetter(_ letter: GitFileStatusLetter) -> WatchFileStatusLetter {
        switch letter {
        case .added, .untracked: return .added
        case .modified: return .modified
        case .deleted: return .deleted
        case .renamed: return .renamed
        }
    }

    private static func classifyHighSignalReason(for diff: FilePatchDiff) -> String? {
        let lowerPath = diff.filePath.lowercased()
        let baseName = (lowerPath as NSString).lastPathComponent

        if highSignalBasenames.contains(baseName) {
            if diff.deletions > diff.additions {
                return "Removes a dependency"
            }
            return "Dependency or build config"
        }

        if highSignalPathTokens.contains(where: { lowerPath.contains($0) }) {
            if lowerPath.contains("audit") || lowerPath.contains("log") {
                return "Log field names change"
            }
            if lowerPath.contains("auth") || lowerPath.contains("security") || lowerPath.contains("permission") {
                return "Auth or permission change"
            }
            if lowerPath.contains("migration") || lowerPath.contains("schema") {
                return "Schema or migration edit"
            }
            return "High-impact module change"
        }

        if diff.statusLetter == .deleted && diff.deletions >= 25 {
            return "Deletes \(diff.deletions) lines"
        }

        return nil
    }

    private static func inferSummary(for diff: FilePatchDiff) -> String {
        let cleanedHunk = diff.hunkHeader
            .replacingOccurrences(of: #"@@[^@]+@@"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedHunk.isEmpty && cleanedHunk.count >= 4 {
            return String(cleanedHunk.prefix(34))
        }
        switch diff.statusLetter {
        case .added, .untracked:
            return "New file (+\(diff.additions) lines)"
        case .deleted:
            return "Removed (-\(diff.deletions) lines)"
        case .renamed:
            return "Renamed & updated"
        case .modified:
            return "+\(diff.additions) -\(diff.deletions) lines updated"
        }
    }

    private static func clusterMechanicalDiffs(_ diffs: [FilePatchDiff]) -> [WatchFileIntentGroup] {
        var tests: [FilePatchDiff] = []
        var docs: [FilePatchDiff] = []
        var callSites: [FilePatchDiff] = []

        for diff in diffs {
            let lower = diff.filePath.lowercased()
            if lower.contains("test") || lower.contains("spec") {
                tests.append(diff)
            } else if lower.hasSuffix(".md") || lower.hasSuffix(".txt") || lower.contains("docs/") {
                docs.append(diff)
            } else {
                callSites.append(diff)
            }
        }

        var groups: [WatchFileIntentGroup] = []
        if !callSites.isEmpty {
            let dirs = distinctDirectoryCount(callSites)
            let dirText = dirs <= 1 ? "1 dir" : "\(dirs) dirs"
            groups.append(
                WatchFileIntentGroup(
                    id: "grp-callsites",
                    count: callSites.count,
                    title: "Call sites → updated",
                    subtitle: "Mechanical · \(dirText)",
                    filePaths: callSites.map(\.filePath)
                )
            )
        }
        if !tests.isEmpty {
            let dirs = distinctDirectoryCount(tests)
            let dirText = dirs <= 1 ? "1 dir" : "\(dirs) dirs"
            groups.append(
                WatchFileIntentGroup(
                    id: "grp-tests",
                    count: tests.count,
                    title: "Test suites",
                    subtitle: "Assertions · \(dirText)",
                    filePaths: tests.map(\.filePath)
                )
            )
        }
        if !docs.isEmpty {
            groups.append(
                WatchFileIntentGroup(
                    id: "grp-docs",
                    count: docs.count,
                    title: "Docs & specs",
                    subtitle: "Documentation",
                    filePaths: docs.map(\.filePath)
                )
            )
        }
        return groups
    }

    private static func distinctDirectoryCount(_ diffs: [FilePatchDiff]) -> Int {
        let dirs = Set(diffs.map { ($0.filePath as NSString).deletingLastPathComponent })
        return max(1, dirs.count)
    }
}

// MARK: - Watch Artifact Markdown Summarizer (`W04`)

/// Distills rich Markdown artifacts (`Walkthrough`, `Implementation Plan`) into title + `<= 3` concise numbered points
/// with inline monospace code and emerald performance metric spans plus a single primary action (`See changes` or `Proceed`).
public enum WatchArtifactSummarizer {
    public static func buildSummary(
        from artifact: ArtifactSnapshot,
        maxPoints: Int = WatchArtifactSummarySnapshot.maxKeyPoints
    ) -> WatchArtifactSummarySnapshot {
        let clampedMax = max(1, min(WatchArtifactSummarySnapshot.maxKeyPoints, maxPoints))
        let rawLines = artifact.content.components(separatedBy: .newlines)
        var headline = artifact.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidateBullets: [String] = []

        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                let heading = line.drop(while: { $0 == "#" || $0 == " " })
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if headline.isEmpty && !heading.isEmpty {
                    headline = heading
                }
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !item.isEmpty {
                    candidateBullets.append(item)
                }
                continue
            }
            if let range = line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
                let item = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !item.isEmpty {
                    candidateBullets.append(item)
                }
            }
        }

        if headline.isEmpty {
            headline = artifact.title.isEmpty ? "Summary" : artifact.title
        }

        if candidateBullets.isEmpty {
            let sentences = artifact.content
                .replacingOccurrences(of: "\n", with: " ")
                .split(separator: ".")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 6 }
            candidateBullets = Array(sentences.prefix(clampedMax))
        }

        if candidateBullets.isEmpty && !artifact.summary.isEmpty {
            candidateBullets = [artifact.summary]
        }

        let points = candidateBullets.prefix(clampedMax).enumerated().map { idx, text in
            WatchArtifactPoint(
                index: idx + 1,
                spans: parseInlineSpans(from: text)
            )
        }

        let shortTitle: String = {
            switch artifact.kind {
            case .walkthrough: return "Walkthrough"
            case .implementationPlan: return "Plan"
            case .taskList: return "Tasks"
            default:
                return artifact.title.isEmpty ? "Artifact" : artifact.title
            }
        }()

        let primaryAction: WatchArtifactPrimaryAction = (artifact.kind == .implementationPlan || artifact.requestFeedback)
            ? .proceed
            : .seeChanges

        return WatchArtifactSummarySnapshot(
            id: artifact.id,
            title: shortTitle,
            headline: headline,
            artifactPath: artifact.artifactPath,
            points: points,
            primaryAction: primaryAction
        )
    }

    public static func parseInlineSpans(from rawText: String) -> [WatchStyledTextSpan] {
        let cleaned = rawText
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        // First split by inline backticks (`code`).
        let parts = cleaned.components(separatedBy: "`")
        var spans: [WatchStyledTextSpan] = []

        for (idx, part) in parts.enumerated() {
            guard !part.isEmpty else { continue }
            if idx % 2 == 1 {
                spans.append(WatchStyledTextSpan(text: part, kind: .code))
            } else {
                spans.append(contentsOf: highlightMetrics(in: part))
            }
        }
        return spans.isEmpty ? [WatchStyledTextSpan(text: cleaned, kind: .plain)] : spans
    }

    private static func highlightMetrics(in segment: String) -> [WatchStyledTextSpan] {
        // Highlight compact numeric metrics like `3.8 ms`, `99.9%`, `12ms`, `0.4s`
        let pattern = #"\b\d+(?:\.\d+)?\s?(?:ms|s|%)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [WatchStyledTextSpan(text: segment, kind: .plain)]
        }
        let ns = segment as NSString
        let matches = regex.matches(in: segment, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else {
            return [WatchStyledTextSpan(text: segment, kind: .plain)]
        }

        var result: [WatchStyledTextSpan] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let prefix = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                result.append(WatchStyledTextSpan(text: prefix, kind: .plain))
            }
            let metric = ns.substring(with: match.range)
            result.append(WatchStyledTextSpan(text: metric, kind: .metricHighlight))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result.append(WatchStyledTextSpan(text: ns.substring(from: cursor), kind: .plain))
        }
        return result
    }
}

// MARK: - Live Session Store -> Watch Snapshot Projector

/// Projects live `AntigravitySessionStore` state into a compact, Wire-ready `WatchCompanionSnapshot`.
@MainActor
public enum WatchCompanionProjector {
    public static func project(from store: AntigravitySessionStore, maxSessions: Int = 12) -> WatchCompanionSnapshot {
        // 1. Project Devices (`W02`)
        var devices: [WatchDeviceSnapshot] = []
        let localHosts = store.pairedLocalHosts
        let selectedScope = store.selectedHostScope

        for host in localHosts {
            let scope = AgentsHostFilterScope.localHost(id: host.instanceId, name: host.hostname)
            let online = store.isLocalHostOnline(instanceId: host.instanceId, hostname: host.hostname)
            let isSelected: Bool = {
                switch selectedScope {
                case .localHost(let id, let name):
                    return id == host.instanceId || name == host.hostname
                case .allHosts:
                    return host.instanceId == store.activeHost.instanceId
                case .antigravityCloud:
                    return false
                }
            }()
            let kind: WatchDeviceKind = host.hostname.lowercased().contains("imac")
                || host.hostname.lowercased().contains("studio")
                || host.hostname.lowercased().contains("mini")
                || host.hostname.lowercased().contains("desktop")
                ? .desktop
                : .laptop
            devices.append(
                WatchDeviceSnapshot(
                    id: host.instanceId,
                    name: host.hostname,
                    kind: kind,
                    isOnline: online,
                    runningCount: store.runningCount(for: scope),
                    lastSeenLabel: online ? nil : "seen recently",
                    isSelected: isSelected
                )
            )
        }

        // Always include Cloud runtime entry when Cloud projects/sessions exist or connected via Relay
        let cloudRunning = store.runningCount(for: .antigravityCloud)
        let hasCloudContext = cloudRunning > 0
            || store.summaries.contains(where: \.isCloud)
            || store.projects.contains(where: { $0.runtime == .cloud })
            || store.activeHost.channel == .cloudRelay
        if hasCloudContext {
            let cloudOnline = store.isDeviceNetworkReachable && (store.isLiveBackendConnected || !store.hasPairedBackend)
            let cloudSelected: Bool = {
                if case .antigravityCloud = selectedScope { return true }
                return false
            }()
            devices.append(
                WatchDeviceSnapshot(
                    id: "cloud",
                    name: "Cloud",
                    kind: .cloud,
                    isOnline: cloudOnline,
                    runningCount: cloudRunning,
                    lastSeenLabel: cloudOnline ? nil : "offline",
                    isSelected: cloudSelected
                )
            )
        }

        if devices.isEmpty {
            devices.append(
                WatchDeviceSnapshot(
                    id: store.activeHost.instanceId,
                    name: store.activeHost.hostname,
                    kind: .laptop,
                    isOnline: store.activeHost.isOnline,
                    runningCount: store.runningCount,
                    isSelected: true
                )
            )
        }

        let activeDevice = devices.first(where: \.isSelected) ?? devices[0]

        // 2. Project Sessions (`W01`, `W03`, `W04`, `W05`/`W06`, `W08`)
        let visibleSummaries = store.summaries
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let lp = statusPriority(lhs.status)
                let rp = statusPriority(rhs.status)
                if lp != rp { return lp < rp }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(maxSessions)

        var firstPendingApproval: WatchPendingApproval?
        var projectedSessions: [WatchSessionSnapshot] = []

        for summary in visibleSummaries {
            let steps = store.stepsByCascadeId[summary.cascadeId] ?? []
            let status = mapStatus(summary.status)
            let approval = extractPendingApproval(summary: summary, steps: steps)
            if firstPendingApproval == nil, let approval {
                firstPendingApproval = approval
            }

            let recentMessages = extractRecentMessages(from: steps, fallbackPreview: summary.lastMessagePreview)
            let artifactSummary: WatchArtifactSummarySnapshot? = {
                if summary.cascadeId == store.activeCascadeId,
                   let artifact = store.activeArtifacts.first(where: { $0.kind == .implementationPlan && $0.requestFeedback })
                    ?? store.activeArtifacts.first(where: { $0.kind == .walkthrough })
                    ?? store.activeArtifacts.first {
                    return WatchArtifactSummarizer.buildSummary(from: artifact)
                }
                return nil
            }()

            let changes: WatchChangesSnapshot? = {
                if summary.cascadeId == store.activeCascadeId, !store.activeTurnDiffs.isEmpty {
                    return WatchDiffTriageEngine.buildChangesSnapshot(from: store.activeTurnDiffs)
                }
                if summary.totalAdditions > 0 || summary.totalDeletions > 0 {
                    // Without full per-file risk triage, route to grouped/iPhone review rather than blind Accept all.
                    return WatchChangesSnapshot(
                        totalFiles: max(1, steps.filter { $0.type == .codeAction }.count),
                        totalAdditions: summary.totalAdditions,
                        totalDeletions: summary.totalDeletions,
                        compactFiles: [],
                        worthALookFiles: [],
                        intentGroups: [],
                        isGroupedMode: true
                    )
                }
                return nil
            }()

            let subtitle: String = {
                switch status {
                case .waitingApproval:
                    return summary.pendingInteractionTitle ?? "Approve command"
                case .running:
                    let prefix = summary.isCloud ? "Cloud · " : ""
                    return "\(prefix)\(max(1, summary.currentStepIndex)) of \(max(summary.currentStepIndex, summary.totalSteps))"
                case .done:
                    return "Done"
                case .error:
                    return "Needs attention"
                case .idle:
                    return summary.statusSubtitle.isEmpty ? "Ready" : summary.statusSubtitle
                }
            }()

            projectedSessions.append(
                WatchSessionSnapshot(
                    cascadeId: summary.cascadeId,
                    title: summary.title,
                    status: status,
                    isCloud: summary.isCloud,
                    currentStepIndex: summary.currentStepIndex,
                    totalSteps: summary.totalSteps,
                    statusSubtitle: subtitle,
                    additions: summary.totalAdditions,
                    deletions: summary.totalDeletions,
                    hasUnread: summary.isUnread,
                    hostName: summary.isCloud ? "Cloud" : (summary.originHostName ?? activeDevice.name),
                    recentMessages: recentMessages,
                    artifactSummary: artifactSummary,
                    changes: changes,
                    pendingApproval: approval
                )
            )
        }

        return WatchCompanionSnapshot(
            generatedAt: Date(),
            activeDeviceId: activeDevice.id,
            activeDeviceName: activeDevice.name,
            activeDeviceKind: activeDevice.kind,
            activeDeviceOnline: activeDevice.isOnline,
            devices: devices,
            sessions: projectedSessions,
            activeApproval: firstPendingApproval
        )
    }

    private static func statusPriority(_ status: CortexStepStatus) -> Int {
        switch status {
        case .waiting, .blocked: return 0
        case .inProgress, .pending: return 1
        case .done: return 2
        case .error: return 3
        case .cancelled, .unspecified: return 4
        }
    }

    private static func mapStatus(_ status: CortexStepStatus) -> WatchSessionStatus {
        switch status {
        case .waiting, .blocked: return .waitingApproval
        case .inProgress, .pending: return .running
        case .done: return .done
        case .error: return .error
        case .cancelled, .unspecified: return .idle
        }
    }

    private static func extractPendingApproval(
        summary: CascadeSummary,
        steps: [CascadeStep]
    ) -> WatchPendingApproval? {
        guard summary.status == .waiting || summary.status == .blocked else { return nil }
        let waitingStep = steps.last(where: { $0.status == .waiting || $0.status == .blocked })
        let req = waitingStep?.effectiveRequestedInteraction
        let cmdCandidates: [String?] = [
            waitingStep?.runCommand?.proposedCommandLine,
            waitingStep?.runCommand?.commandLine,
            req?.permission.map { "\($0.action)(\($0.target))" },
            req?.filePermission?.absolutePathUri,
            req?.mcpToolName,
            req?.askQuestion?.question,
            req?.rawSummary,
            summary.pendingInteractionTitle
        ]
        let command = cmdCandidates.compactMap { $0 }.first(where: { !$0.isEmpty }) ?? "Approve pending action"
        return WatchPendingApproval(
            cascadeId: summary.cascadeId,
            cascadeTitle: summary.title,
            stepIndex: waitingStep?.stepIndex ?? max(1, summary.currentStepIndex),
            totalSteps: max(summary.totalSteps, waitingStep?.stepIndex ?? 1),
            promptTitle: "Run this command?",
            commandLine: command,
            relativeTimeLabel: summary.relativeTimeLabel.isEmpty ? "now" : summary.relativeTimeLabel
        )
    }

    private static func extractRecentMessages(
        from steps: [CascadeStep],
        fallbackPreview: String?
    ) -> [WatchChatBubbleItem] {
        var bubbles: [WatchChatBubbleItem] = []
        for step in steps.suffix(12) {
            if step.type == .userInput,
               let text = step.userInput?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                bubbles.append(
                    WatchChatBubbleItem(
                        id: "u-\(step.stepIndex)",
                        isUser: true,
                        isVoiceInput: false,
                        text: String(text.prefix(140))
                    )
                )
            } else if step.type == .plannerResponse,
                      let response = step.plannerResponse?.response.trimmingCharacters(in: .whitespacesAndNewlines),
                      !response.isEmpty {
                let compact = response
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                bubbles.append(
                    WatchChatBubbleItem(
                        id: "a-\(step.stepIndex)",
                        isUser: false,
                        isVoiceInput: false,
                        text: String(compact.prefix(180))
                    )
                )
            }
        }
        if bubbles.isEmpty, let preview = fallbackPreview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            bubbles.append(WatchChatBubbleItem(id: "preview", isUser: false, text: String(preview.prefix(160))))
        }
        return Array(bubbles.suffix(4))
    }
}
