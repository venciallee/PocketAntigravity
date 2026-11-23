import Foundation
import AntigravityData
#if canImport(WatchConnectivity) && os(iOS)
import WatchConnectivity
#endif

/// Synchronizes live `AntigravitySessionStore` state from iPhone (`AGPocket`) to Apple Watch (`AGPocketWatch`)
/// over `WatchConnectivity`, and executes Watch remote actions (device switching, approval allow/deny,
/// voice reply, accept-all changes, and iPhone Handoff) directly on the live session store.
@MainActor
public final class WatchConnectivityBridge: NSObject {
    public static let shared = WatchConnectivityBridge()

    private weak var attachedStore: AntigravitySessionStore?
    private var lastEncodedSnapshotHash: Int?
    private var debounceTask: Task<Void, Never>?
    private var isActivated: Bool = false

    private override init() {
        super.init()
    }

    public func attach(store: AntigravitySessionStore) {
        self.attachedStore = store
        activateIfNeeded()
        sync(with: store, immediate: true)
    }

    public func activateIfNeeded() {
        guard !isActivated else { return }
        #if canImport(WatchConnectivity) && os(iOS)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        isActivated = true
        #endif
    }

    public func sync(with store: AntigravitySessionStore, immediate: Bool = false) {
        self.attachedStore = store
        guard !store.isVerificationMode else { return }
        activateIfNeeded()

        debounceTask?.cancel()
        if immediate {
            pushSnapshotNow(from: store)
            return
        }
        debounceTask = Task { @MainActor [weak self, weak store] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let store else { return }
            self.pushSnapshotNow(from: store)
        }
    }

    private func pushSnapshotNow(from store: AntigravitySessionStore) {
        let snapshot = WatchCompanionProjector.project(from: store)
        guard let data = WatchConnectivityCodec.encodeSnapshot(snapshot) else { return }
        let hash = data.hashValue
        guard hash != lastEncodedSnapshotHash else { return }
        lastEncodedSnapshotHash = hash

        #if canImport(WatchConnectivity) && os(iOS)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }

        let payload: [String: Any] = [WatchConnectivityCodec.snapshotKey: data]
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        #endif
    }

    /// Applies an incoming `WatchRemoteCommand` from Apple Watch onto the attached `AntigravitySessionStore`.
    public func handleIncomingCommand(_ command: WatchRemoteCommand) {
        guard let store = attachedStore else { return }

        switch command.kind {
        case .selectDevice:
            if let deviceId = command.deviceId, !deviceId.isEmpty {
                if deviceId.lowercased() == "cloud" {
                    store.selectHostScope(.antigravityCloud)
                } else if deviceId.lowercased() == "all" {
                    store.selectHostScope(.allHosts)
                } else if let host = store.pairedLocalHosts.first(where: { $0.instanceId == deviceId || $0.hostname == deviceId }) {
                    store.selectHostScope(.localHost(id: host.instanceId, name: host.hostname))
                } else {
                    store.selectHostScope(.localHost(id: deviceId, name: deviceId))
                }
            }

        case .approveCommand:
            if let cascadeId = command.cascadeId, !cascadeId.isEmpty, store.activeCascadeId != cascadeId {
                store.selectCascade(cascadeId)
            }
            store.approveWaitingCommandWithFaceID(stepIndex: command.stepIndex)

        case .denyCommand:
            if let cascadeId = command.cascadeId, !cascadeId.isEmpty, store.activeCascadeId != cascadeId {
                store.selectCascade(cascadeId)
            }
            store.denyWaitingCommand(stepIndex: command.stepIndex)

        case .sendVoiceReply:
            let trimmed = command.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            if let cascadeId = command.cascadeId, !cascadeId.isEmpty, store.activeCascadeId != cascadeId {
                store.selectCascade(cascadeId)
            }
            store.composerDraftText = trimmed
            store.sendCurrentDraft()

        case .acceptAllChanges:
            if let cascadeId = command.cascadeId, !cascadeId.isEmpty, store.activeCascadeId != cascadeId {
                store.selectCascade(cascadeId)
            }
            store.acceptAllTurnDiffs()

        case .openOnPhone:
            if let cascadeId = command.cascadeId, !cascadeId.isEmpty {
                store.selectCascade(cascadeId)
                switch command.handoffTarget ?? .chat {
                case .chat:
                    store.activeRoute = .cascadeChat(cascadeId)
                case .artifact:
                    store.activeRoute = .planReview
                case .changes:
                    store.activeRoute = .turnDiffReview
                }
            }

        case .requestRefresh:
            Task { @MainActor [weak self, weak store] in
                guard let self, let store else { return }
                await store.refreshWorkspacesAndSummaries(forceFullSync: true)
                self.lastEncodedSnapshotHash = nil
                self.pushSnapshotNow(from: store)
            }
            return
        }

        // Push updated state back to Apple Watch immediately after applying mutation.
        lastEncodedSnapshotHash = nil
        pushSnapshotNow(from: store)
    }

    /// Handles Handoff (`NSUserActivity`) opened on iPhone from Apple Watch ("Open on iPhone").
    public func handleHandoffUserInfo(_ userInfo: [AnyHashable: Any], in store: AntigravitySessionStore) {
        guard let cascadeId = userInfo["cascadeId"] as? String, !cascadeId.isEmpty else { return }
        let targetRaw = (userInfo["target"] as? String) ?? WatchPhoneHandoffTarget.chat.rawValue
        let target = WatchPhoneHandoffTarget(rawValue: targetRaw) ?? .chat
        store.selectCascade(cascadeId)
        switch target {
        case .chat:
            store.activeRoute = .cascadeChat(cascadeId)
        case .artifact:
            store.activeRoute = .planReview
        case .changes:
            store.activeRoute = .turnDiffReview
        }
    }
}

#if canImport(WatchConnectivity) && os(iOS)
extension WatchConnectivityBridge: WCSessionDelegate {
    public nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            if let store = WatchConnectivityBridge.shared.attachedStore {
                WatchConnectivityBridge.shared.lastEncodedSnapshotHash = nil
                WatchConnectivityBridge.shared.sync(with: store, immediate: true)
            }
        }
    }

    public nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    public nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    public nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in
            if let store = WatchConnectivityBridge.shared.attachedStore {
                WatchConnectivityBridge.shared.lastEncodedSnapshotHash = nil
                WatchConnectivityBridge.shared.sync(with: store, immediate: true)
            }
        }
    }

    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let command = WatchConnectivityCodec.decodeCommandPayload(message) else { return }
        Task { @MainActor in
            WatchConnectivityBridge.shared.handleIncomingCommand(command)
        }
    }

    public nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let command = WatchConnectivityCodec.decodeCommandPayload(message)
        if let command {
            Task { @MainActor in
                WatchConnectivityBridge.shared.handleIncomingCommand(command)
            }
            replyHandler(["ack": true])
        } else {
            replyHandler(["ack": false])
        }
    }

    public nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let command = WatchConnectivityCodec.decodeCommandPayload(userInfo) else { return }
        Task { @MainActor in
            WatchConnectivityBridge.shared.handleIncomingCommand(command)
        }
    }
}
#endif
