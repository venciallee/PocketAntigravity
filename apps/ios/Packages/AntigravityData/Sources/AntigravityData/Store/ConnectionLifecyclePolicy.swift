import Foundation
#if canImport(Network)
import Network
#endif

/// Snapshot of device-level IP connectivity reported by `NWPathMonitor`.
public enum NetworkReachabilityStatus: Sendable, Equatable {
    case satisfied(interfaceFingerprint: String, isExpensive: Bool, isConstrained: Bool)
    case unsatisfied

    public var isSatisfied: Bool {
        if case .satisfied = self {
            return true
        }
        return false
    }

    public var isExpensiveOrConstrained: Bool {
        if case let .satisfied(_, isExpensive, isConstrained) = self {
            return isExpensive || isConstrained
        }
        return false
    }

    public var interfaceFingerprint: String? {
        if case let .satisfied(fingerprint, _, _) = self {
            return fingerprint
        }
        return nil
    }
}

/// Lifecycle state of the backend connectivity state machine.
public enum ConnectionLifecyclePhase: Sendable, Equatable {
    case disconnected
    case suspended
    case noNetwork
    case connecting
    case onlineIdle
    case onlineStreaming
    case offlineBackoff(attempt: Int, nextRetrySeconds: TimeInterval)

    public var isOfflineBackoff: Bool {
        if case .offlineBackoff = self {
            return true
        }
        return false
    }
}

/// Centralized, power-aware scheduling policy for mobile heartbeat, step streaming,
/// offline detection debounce, and exponential reconnect backoff.
public enum ConnectionPowerPolicy: Sendable {
    /// Exponential backoff sequence (in seconds) when the paired host is offline while the app is foregrounded.
    public static let offlineBackoffScheduleSeconds: [TimeInterval] = [3.0, 6.0, 12.0, 24.0, 45.0, 60.0]

    /// Maximum offline backoff delay (in seconds) under normal power conditions.
    public static let maxOfflineBackoffSeconds: TimeInterval = 60.0

    /// Maximum offline backoff delay (in seconds) when iOS Low Power Mode is enabled.
    public static let maxLowPowerOfflineBackoffSeconds: TimeInterval = 120.0

    /// Minimum spacing between automatic push-stream reopen attempts to prevent tight reconnect loops.
    public static let minStreamReopenSpacingSeconds: TimeInterval = 3.0

    /// Interval between lightweight reachability heartbeats while online in the foreground.
    /// Deliberately stays well above cellular RRC tail-time (~12s) on Cloud Relay so the 5G modem can sleep.
    public static func onlineHeartbeatInterval(
        channel: RemoteConnectionChannel,
        isLowPowerMode: Bool,
        isExpensiveNetwork: Bool,
        isStreamHealthy: Bool
    ) -> TimeInterval {
        let base: TimeInterval
        switch channel {
        case .cloudRelay:
            if isStreamHealthy {
                base = isExpensiveNetwork ? 45.0 : 30.0
            } else {
                // Stream not connected: still avoid cellular tail-time lock while recovering reasonably fast
                base = isExpensiveNetwork ? 20.0 : 15.0
            }
        case .directHost:
            base = isStreamHealthy ? 15.0 : 8.0
        }
        return isLowPowerMode ? base * 2.0 : base
    }

    /// Interval between full federated workspace/summary reconciliations while online and push-stream healthy.
    public static func onlineFullSyncInterval(
        channel: RemoteConnectionChannel,
        isLowPowerMode: Bool
    ) -> TimeInterval {
        let base: TimeInterval = (channel == .cloudRelay) ? 60.0 : 30.0
        return isLowPowerMode ? base * 2.0 : base
    }

    /// Step polling interval while an active agent turn is streaming (`stillActive == true`).
    public static func activeStreamingStepPollInterval(
        channel: RemoteConnectionChannel,
        isLowPowerMode: Bool
    ) -> TimeInterval {
        switch channel {
        case .cloudRelay:
            return isLowPowerMode ? 1.5 : 1.0
        case .directHost:
            return isLowPowerMode ? 1.0 : 0.5
        }
    }

    /// Fallback step polling interval when viewing an idle chat ONLY if the push stream is unavailable.
    /// When the push stream is healthy, idle chats do NOT poll steps at all (`nil`).
    public static func idleChatFallbackStepPollInterval(
        isStreamHealthy: Bool,
        isLowPowerMode: Bool
    ) -> TimeInterval? {
        guard !isStreamHealthy else { return nil }
        return isLowPowerMode ? 30.0 : 15.0
    }

    /// Deterministic exponential backoff delay (seconds) for offline reconnect attempt `attempt` (0-indexed).
    public static func offlineBackoffBaseDelay(
        attempt: Int,
        isLowPowerMode: Bool
    ) -> TimeInterval {
        let clampedIndex = max(0, min(attempt, offlineBackoffScheduleSeconds.count - 1))
        let base = offlineBackoffScheduleSeconds[clampedIndex]
        if isLowPowerMode {
            return min(base * 2.0, maxLowPowerOfflineBackoffSeconds)
        }
        return min(base, maxOfflineBackoffSeconds)
    }

    /// Exponential backoff delay with optional ±15% jitter (`jitterFactor` in `0.85 ... 1.15`).
    public static func offlineBackoffDelay(
        attempt: Int,
        isLowPowerMode: Bool,
        applyJitter: Bool = true,
        jitterFactor: Double? = nil
    ) -> TimeInterval {
        let base = offlineBackoffBaseDelay(attempt: attempt, isLowPowerMode: isLowPowerMode)
        guard applyJitter else { return base }
        let factor = jitterFactor ?? Double.random(in: 0.85...1.15)
        let cap = isLowPowerMode ? maxLowPowerOfflineBackoffSeconds : maxOfflineBackoffSeconds
        return max(1.0, min(base * factor, cap))
    }

    /// Consecutive sync/probe failure threshold before flipping a paired host to `Host Offline`.
    public static func offlineFailureThreshold(
        channel: RemoteConnectionChannel,
        error: Error
    ) -> Int {
        if let rpcErr = error as? AntigravityRPCError {
            switch rpcErr {
            case .unauthorized, .invalidEndpoint:
                return 1
            case .httpError(let statusCode, let body):
                // Explicit Relay `ListInstances` confirmation that 0 desktop instances are reachable
                if statusCode == 503 && body.localizedCaseInsensitiveContains("no reachable") {
                    return 1
                }
                return (channel == .cloudRelay) ? 2 : 1
            case .decodingError, .interactionRejected:
                return Int.max
            }
        }
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
                return 1
            default:
                return (channel == .cloudRelay) ? 2 : 1
            }
        }
        return (channel == .cloudRelay) ? 2 : 1
    }
}

/// Pure Swift 6 `NWPathMonitor` wrapper (zero `UIKit` dependency) for detecting iPhone network loss
/// and Wi-Fi ↔ 5G interface handoffs.
public final class NetworkPathObserver: NetworkReachabilityMonitoring, @unchecked Sendable {
    #if canImport(Network)
    private let queue = DispatchQueue(label: "dev.antigravity.ios.network-path-observer", qos: .utility)
    private var monitor: NWPathMonitor?
    private var lastStatus: NetworkReachabilityStatus?
    #endif

    public init() {}

    public func start(onChange: @escaping @Sendable (NetworkReachabilityStatus) -> Void) {
        #if canImport(Network)
        queue.async { [weak self] in
            guard let self else { return }
            guard self.monitor == nil else { return }
            let newMonitor = NWPathMonitor()
            newMonitor.pathUpdateHandler = { [weak self] path in
                guard let self else { return }
                let mapped = Self.mapPath(path)
                guard self.lastStatus != mapped else { return }
                self.lastStatus = mapped
                onChange(mapped)
            }
            self.monitor = newMonitor
            newMonitor.start(queue: self.queue)
        }
        #endif
    }

    public func stop() {
        #if canImport(Network)
        queue.async { [weak self] in
            guard let self else { return }
            self.monitor?.cancel()
            self.monitor = nil
            self.lastStatus = nil
        }
        #endif
    }

    deinit {
        #if canImport(Network)
        monitor?.cancel()
        #endif
    }

    #if canImport(Network)
    private static func mapPath(_ path: NWPath) -> NetworkReachabilityStatus {
        guard path.status == .satisfied else {
            return .unsatisfied
        }
        var interfaces: [String] = []
        if path.usesInterfaceType(.wifi) { interfaces.append("wifi") }
        if path.usesInterfaceType(.cellular) { interfaces.append("cellular") }
        if path.usesInterfaceType(.wiredEthernet) { interfaces.append("wired") }
        if path.usesInterfaceType(.loopback) { interfaces.append("loopback") }
        if interfaces.isEmpty { interfaces.append("other") }
        return .satisfied(
            interfaceFingerprint: interfaces.joined(separator: "+"),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }
    #endif
}
