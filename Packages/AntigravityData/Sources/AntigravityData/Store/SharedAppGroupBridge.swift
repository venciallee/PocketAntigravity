import Foundation

/// Queued command submitted by a Live Activity `AppIntent` (Approve / Deny / Stop)
/// when direct background RPC dispatch requires main-app reconciliation.
public struct PendingLiveActivityAction: Codable, Sendable, Equatable, Identifiable {
    public enum ActionKind: String, Codable, Sendable {
        case approveWithFaceID
        case deny
        case stopTurn
    }

    public var id: String
    public var cascadeId: String
    public var stepIndex: Int
    public var kind: ActionKind
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        cascadeId: String,
        stepIndex: Int = 0,
        kind: ActionKind,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cascadeId = cascadeId
        self.stepIndex = stepIndex
        self.kind = kind
        self.createdAt = createdAt
    }
}

/// Payload persisted by `AntigravityShare` Extension and consumed by `AntigravityApp` via `antigravity://share/<id>`.
public struct PendingSharePayload: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var urlString: String?
    public var fileName: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        text: String,
        urlString: String? = nil,
        fileName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.urlString = urlString
        self.fileName = fileName
        self.createdAt = createdAt
    }
}

/// Credential-free shared queue bridging `AntigravityLiveActivity`, `AntigravityShare`, and the main app.
/// Uses the App Group suite when provisioned and gracefully falls back to a local file store in tests/simulator.
public actor SharedAppGroupBridge {
    public static let shared = SharedAppGroupBridge()
    public static let appGroupSuiteName = "group.dev.antigravity.ios.shared"

    private static let actionsKey = "antigravity.pending_live_activity_actions.v1"
    private static let sharesKey = "antigravity.pending_share_payloads.v1"

    private let storageDirectory: URL
    private let suiteName: String

    public init(
        suiteName: String = SharedAppGroupBridge.appGroupSuiteName,
        storageDirectory: URL? = nil
    ) {
        self.suiteName = suiteName
        if let storageDirectory {
            self.storageDirectory = storageDirectory
        } else if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            self.storageDirectory = groupURL.appendingPathComponent("SharedBridge", isDirectory: true)
        } else {
            let fallback = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.storageDirectory = fallback.appendingPathComponent("AntigravitySharedBridge", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        storageDirectory.appendingPathComponent("\(key).json")
    }

    private func loadArray<T: Decodable>(key: String, as type: [T].Type) -> [T] {
        let url = fileURL(for: key)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(type, from: data) {
            return decoded
        }
        if let defaults = UserDefaults(suiteName: suiteName),
           let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(type, from: data) {
            return decoded
        }
        return []
    }

    private func saveArray<T: Encodable>(_ items: [T], key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        let url = fileURL(for: key)
        try? data.write(to: url, options: .atomic)
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.set(data, forKey: key)
        }
    }

    public func enqueueLiveActivityAction(_ action: PendingLiveActivityAction) {
        var existing = loadArray(key: Self.actionsKey, as: [PendingLiveActivityAction].self)
        if !existing.contains(where: { $0.id == action.id }) {
            existing.append(action)
            saveArray(existing, key: Self.actionsKey)
        }
    }

    public func drainLiveActivityActions() -> [PendingLiveActivityAction] {
        let existing = loadArray(key: Self.actionsKey, as: [PendingLiveActivityAction].self)
        if !existing.isEmpty {
            saveArray([PendingLiveActivityAction](), key: Self.actionsKey)
        }
        return existing
    }

    public func saveSharePayload(_ payload: PendingSharePayload) {
        var existing = loadArray(key: Self.sharesKey, as: [PendingSharePayload].self)
        existing.removeAll { $0.id == payload.id }
        existing.append(payload)
        saveArray(existing, key: Self.sharesKey)
    }

    public func consumeSharePayload(id: String? = nil) -> PendingSharePayload? {
        var existing = loadArray(key: Self.sharesKey, as: [PendingSharePayload].self)
        guard !existing.isEmpty else { return nil }
        let chosen: PendingSharePayload?
        if let id, !id.isEmpty, let idx = existing.firstIndex(where: { $0.id == id }) {
            chosen = existing.remove(at: idx)
        } else {
            chosen = existing.removeLast()
        }
        saveArray(existing, key: Self.sharesKey)
        return chosen
    }
}
