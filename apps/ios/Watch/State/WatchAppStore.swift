import Foundation
import Observation
import AntigravityData
#if canImport(WatchConnectivity) && os(watchOS)
import WatchConnectivity
#endif

/// Navigation routes pushed onto `NavigationStack` inside `AGPocketWatch`.
public enum WatchNavigationDestination: Hashable, Sendable {
    case devices
    case chat(cascadeId: String)
    case artifact(cascadeId: String)
    case changes(cascadeId: String)
}

/// Central `@Observable` Watch state coordinator handling `WatchConnectivity` sync with iPhone,
/// local offline snapshot persistence, Handoff (`NSUserActivity`), voice reply target selection,
/// and deterministic `--watch-verify` / `AGPOCKET_WATCH_VERIFY` scene launching.
@MainActor
@Observable
public final class WatchAppStore {
    public static let cachedSnapshotDefaultsKey = "agpocket.watch.cached_snapshot.v1"

    // MARK: - Synced Data State
    public var snapshot: WatchCompanionSnapshot
    public var isPhoneReachable: Bool = false
    public var isVerificationMode: Bool = false
    public var activeVerifyScene: WatchVerifySceneCase? = nil
    public var statusToastMessage: String? = nil

    // MARK: - Navigation & Sheet State
    public var navigationPath: [WatchNavigationDestination] = []
    public var isVoiceSheetPresented: Bool = false
    public var voiceTargetCascadeId: String? = nil
    public var voiceCommittedText: String = ""
    public var voicePartialWord: String = ""
    public var isVoiceListening: Bool = false
    public var activeApprovalSheet: WatchPendingApproval? = nil
    public var acceptedChangesCascadeIds: Set<String> = []

    // MARK: - Handoff Activity & Connectivity Proxy
    private var currentHandoffActivity: NSUserActivity?
    private var toastClearTask: Task<Void, Never>?
    #if canImport(WatchConnectivity) && os(watchOS)
    private var sessionDelegateProxy: WatchSessionDelegateProxy?
    #endif

    public init() {
        let launchScene = Self.detectLaunchVerifyScene()
        if let launchScene {
            self.snapshot = WatchVerificationFixtures.makeSnapshot(for: launchScene)
            self.isVerificationMode = true
            self.activeVerifyScene = launchScene
        } else if let cached = Self.loadCachedSnapshot() {
            self.snapshot = cached
            self.isVerificationMode = false
        } else {
            self.snapshot = WatchVerificationFixtures.makeSnapshot(for: .sessions)
            self.isVerificationMode = false
        }

        if let launchScene {
            configureForVerifyScene(launchScene)
        } else {
            activateWatchConnectivity()
        }
    }

    // MARK: - Launch Verification Detection (`--watch-verify` or `AGPOCKET_WATCH_VERIFY`)

    public static func detectLaunchVerifyScene() -> WatchVerifySceneCase? {
        if let envVal = ProcessInfo.processInfo.environment["AGPOCKET_WATCH_VERIFY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !envVal.isEmpty {
            return parseSceneCase(envVal)
        }
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--watch-verify"), idx + 1 < args.count {
            return parseSceneCase(args[idx + 1])
        }
        return nil
    }

    public static func parseSceneCase(_ raw: String) -> WatchVerifySceneCase? {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let exact = WatchVerifySceneCase(rawValue: upper) {
            return exact
        }
        switch upper {
        case "W01", "SESSIONS": return .sessions
        case "W02", "DEVICES": return .devices
        case "W03", "CHAT", "CHAT_STREAM": return .chatStream
        case "W04", "ARTIFACT", "ARTIFACT_SUMMARY": return .artifactSummary
        case "W05", "CHANGES", "CHANGES_COMPACT": return .changedFilesCompact
        case "W06", "CHANGES_GROUPED", "GROUPED": return .changedFilesGrouped
        case "W07", "VOICE", "VOICE_INPUT": return .voiceInput
        case "W08", "APPROVAL", "NOTIFICATION": return .approvalNotification
        default: return nil
        }
    }

    public func configureForVerifyScene(_ scene: WatchVerifySceneCase) {
        isVerificationMode = true
        activeVerifyScene = scene
        snapshot = WatchVerificationFixtures.makeSnapshot(for: scene)
        navigationPath = []
        isVoiceSheetPresented = false
        activeApprovalSheet = nil

        switch scene {
        case .sessions:
            break
        case .devices:
            navigationPath = [.devices]
        case .chatStream:
            navigationPath = [.chat(cascadeId: WatchVerificationFixtures.rateLimiterCascadeId)]
        case .artifactSummary:
            navigationPath = [
                .chat(cascadeId: WatchVerificationFixtures.rateLimiterCascadeId),
                .artifact(cascadeId: WatchVerificationFixtures.rateLimiterCascadeId)
            ]
        case .changedFilesCompact, .changedFilesGrouped:
            navigationPath = [
                .chat(cascadeId: WatchVerificationFixtures.rateLimiterCascadeId),
                .changes(cascadeId: WatchVerificationFixtures.rateLimiterCascadeId)
            ]
        case .voiceInput:
            voiceTargetCascadeId = WatchVerificationFixtures.rateLimiterCascadeId
            voiceCommittedText = WatchVerificationFixtures.sampleVoiceCommittedTranscript
            voicePartialWord = WatchVerificationFixtures.sampleVoicePartialWord
            isVoiceListening = true
            isVoiceSheetPresented = true
        case .approvalNotification:
            activeApprovalSheet = snapshot.activeApproval ?? WatchVerificationFixtures.makePendingApproval()
        }
    }

    // MARK: - Derived Lookups

    public func session(for cascadeId: String) -> WatchSessionSnapshot? {
        snapshot.sessions.first(where: { $0.cascadeId == cascadeId })
    }

    public var voiceTargetSession: WatchSessionSnapshot? {
        if let id = voiceTargetCascadeId, let match = session(for: id) {
            return match
        }
        return snapshot.sessions.first
    }

    public var combinedVoiceDraftText: String {
        (voiceCommittedText + voicePartialWord).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - User Actions (Optimistic Local Update + WatchConnectivity Dispatch)

    public func selectDevice(_ device: WatchDeviceSnapshot) {
        guard device.isOnline || isVerificationMode else {
            showToast("\(device.name) is offline")
            WatchHaptics.failure()
            return
        }
        snapshot.activeDeviceId = device.id
        snapshot.activeDeviceName = device.name
        snapshot.activeDeviceKind = device.kind
        snapshot.activeDeviceOnline = device.isOnline
        for idx in snapshot.devices.indices {
            snapshot.devices[idx].isSelected = (snapshot.devices[idx].id == device.id)
        }
        persistCachedSnapshot()
        sendCommand(WatchRemoteCommand(kind: .selectDevice, deviceId: device.id))
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }

    public func openVoiceInput(for cascadeId: String? = nil) {
        voiceTargetCascadeId = cascadeId ?? snapshot.sessions.first?.cascadeId
        if !isVerificationMode {
            voiceCommittedText = ""
            voicePartialWord = ""
            isVoiceListening = true
        }
        isVoiceSheetPresented = true
    }

    public func cycleVoiceTargetSession() {
        guard snapshot.sessions.count > 1 else { return }
        let currentId = voiceTargetSession?.cascadeId
        if let idx = snapshot.sessions.firstIndex(where: { $0.cascadeId == currentId }) {
            let nextIdx = (idx + 1) % snapshot.sessions.count
            voiceTargetCascadeId = snapshot.sessions[nextIdx].cascadeId
        } else {
            voiceTargetCascadeId = snapshot.sessions.first?.cascadeId
        }
    }

    public func submitVoiceReply() {
        let text = combinedVoiceDraftText
        guard !text.isEmpty else {
            isVoiceSheetPresented = false
            return
        }
        let targetId = voiceTargetSession?.cascadeId ?? WatchVerificationFixtures.rateLimiterCascadeId
        if let idx = snapshot.sessions.firstIndex(where: { $0.cascadeId == targetId }) {
            snapshot.sessions[idx].recentMessages.append(
                WatchChatBubbleItem(isUser: true, isVoiceInput: true, text: text)
            )
            snapshot.sessions[idx].status = .running
            snapshot.sessions[idx].statusSubtitle = "Running"
        }
        isVoiceListening = false
        voiceCommittedText = ""
        voicePartialWord = ""
        isVoiceSheetPresented = false
        WatchHaptics.success()
        persistCachedSnapshot()
        sendCommand(WatchRemoteCommand(kind: .sendVoiceReply, cascadeId: targetId, text: text))
        showToast("Sent")
    }

    public func approveCommand(_ approval: WatchPendingApproval) {
        if let idx = snapshot.sessions.firstIndex(where: { $0.cascadeId == approval.cascadeId }) {
            snapshot.sessions[idx].status = .running
            snapshot.sessions[idx].currentStepIndex = min(
                snapshot.sessions[idx].totalSteps,
                approval.stepIndex + 1
            )
            snapshot.sessions[idx].statusSubtitle = "Step \(snapshot.sessions[idx].currentStepIndex) of \(snapshot.sessions[idx].totalSteps)"
            snapshot.sessions[idx].pendingApproval = nil
        }
        if snapshot.activeApproval?.id == approval.id {
            snapshot.activeApproval = nil
        }
        activeApprovalSheet = nil
        WatchHaptics.success()
        persistCachedSnapshot()
        sendCommand(
            WatchRemoteCommand(
                kind: .approveCommand,
                cascadeId: approval.cascadeId,
                stepIndex: approval.stepIndex
            )
        )
        showToast("Allowed")
    }

    public func denyCommand(_ approval: WatchPendingApproval) {
        if let idx = snapshot.sessions.firstIndex(where: { $0.cascadeId == approval.cascadeId }) {
            snapshot.sessions[idx].status = .idle
            snapshot.sessions[idx].statusSubtitle = "Denied"
            snapshot.sessions[idx].pendingApproval = nil
        }
        if snapshot.activeApproval?.id == approval.id {
            snapshot.activeApproval = nil
        }
        activeApprovalSheet = nil
        WatchHaptics.click()
        persistCachedSnapshot()
        sendCommand(
            WatchRemoteCommand(
                kind: .denyCommand,
                cascadeId: approval.cascadeId,
                stepIndex: approval.stepIndex
            )
        )
        showToast("Denied")
    }

    public func replyByVoice(for approval: WatchPendingApproval) {
        activeApprovalSheet = nil
        openVoiceInput(for: approval.cascadeId)
    }

    public func acceptAllChanges(for cascadeId: String) {
        acceptedChangesCascadeIds.insert(cascadeId)
        if let idx = snapshot.sessions.firstIndex(where: { $0.cascadeId == cascadeId }) {
            snapshot.sessions[idx].status = .done
            snapshot.sessions[idx].statusSubtitle = "Done"
        }
        WatchHaptics.success()
        persistCachedSnapshot()
        sendCommand(WatchRemoteCommand(kind: .acceptAllChanges, cascadeId: cascadeId))
        showToast("Accepted all")
    }

    public func openOnPhone(cascadeId: String, target: WatchPhoneHandoffTarget) {
        WatchHaptics.click()
        advertiseHandoff(cascadeId: cascadeId, target: target)
        sendCommand(
            WatchRemoteCommand(
                kind: .openOnPhone,
                cascadeId: cascadeId,
                handoffTarget: target
            )
        )
        showToast("Opened on iPhone")
    }

    public func requestRefreshFromPhone() {
        sendCommand(WatchRemoteCommand(kind: .requestRefresh))
    }

    public func advertiseHandoff(cascadeId: String, target: WatchPhoneHandoffTarget) {
        let activity = NSUserActivity(activityType: WatchConnectivityCodec.handoffActivityType)
        activity.title = "Continue in AG Pocket"
        activity.isEligibleForHandoff = true
        activity.userInfo = [
            "cascadeId": cascadeId,
            "target": target.rawValue
        ]
        activity.becomeCurrent()
        currentHandoffActivity = activity
    }

    public func showToast(_ message: String) {
        toastClearTask?.cancel()
        statusToastMessage = message
        toastClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.statusToastMessage = nil
        }
    }

    // MARK: - WatchConnectivity Session Management

    private func activateWatchConnectivity() {
        #if canImport(WatchConnectivity) && os(watchOS)
        guard WCSession.isSupported() else { return }
        let proxy = WatchSessionDelegateProxy(store: self)
        self.sessionDelegateProxy = proxy
        let session = WCSession.default
        session.delegate = proxy
        session.activate()
        if let existing = WatchConnectivityCodec.decodeSnapshotPayload(session.receivedApplicationContext) {
            applyReceivedSnapshot(existing)
        }
        #endif
    }

    private func sendCommand(_ command: WatchRemoteCommand) {
        guard !isVerificationMode else { return }
        #if canImport(WatchConnectivity) && os(watchOS)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              let data = WatchConnectivityCodec.encodeCommand(command) else { return }
        let payload: [String: Any] = [WatchConnectivityCodec.commandKey: data]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                WCSession.default.transferUserInfo([WatchConnectivityCodec.commandKey: data])
            }
        } else {
            session.transferUserInfo(payload)
        }
        #endif
    }

    fileprivate func applyReceivedSnapshot(_ nextSnapshot: WatchCompanionSnapshot) {
        guard !isVerificationMode else { return }
        self.snapshot = nextSnapshot
        persistCachedSnapshot()
    }

    // MARK: - Local Snapshot Cache

    private func persistCachedSnapshot() {
        guard !isVerificationMode,
              let data = WatchConnectivityCodec.encodeSnapshot(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.cachedSnapshotDefaultsKey)
    }

    private static func loadCachedSnapshot() -> WatchCompanionSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedSnapshotDefaultsKey) else {
            return nil
        }
        return WatchConnectivityCodec.decodeSnapshot(from: data)
    }
}

#if canImport(WatchConnectivity) && os(watchOS)
private final class WatchSessionDelegateProxy: NSObject, WCSessionDelegate, @unchecked Sendable {
    private weak var store: WatchAppStore?

    init(store: WatchAppStore) {
        self.store = store
        super.init()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let reachable = session.isReachable
        let existingSnapshot = WatchConnectivityCodec.decodeSnapshotPayload(session.receivedApplicationContext)
        let weakStore = store
        Task { @MainActor in
            guard let weakStore else { return }
            weakStore.isPhoneReachable = reachable
            if let existingSnapshot {
                weakStore.applyReceivedSnapshot(existingSnapshot)
            }
            if activationState == .activated {
                weakStore.requestRefreshFromPhone()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        let weakStore = store
        Task { @MainActor in
            weakStore?.isPhoneReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let decoded = WatchConnectivityCodec.decodeSnapshotPayload(applicationContext) else { return }
        let weakStore = store
        Task { @MainActor in
            weakStore?.applyReceivedSnapshot(decoded)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = WatchConnectivityCodec.decodeSnapshotPayload(message) else { return }
        let weakStore = store
        Task { @MainActor in
            weakStore?.applyReceivedSnapshot(decoded)
        }
    }
}
#endif
