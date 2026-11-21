import Foundation

// MARK: - SemVer Parsing (`AntigravitySemVer`)

/// Semantic version parsed from Antigravity Desktop / Cloud Relay metadata (`"v2.32.0"`, `"2.33.1-beta.1"`, `"3.0.0"`).
/// Returns `nil` when a host does not advertise a parseable version (never fabricates a fake default).
public struct AntigravitySemVer: Codable, Sendable, Equatable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses a version string such as `"v2.32.0"`, `"2.33.1-rc.1"`, or `"Antigravity 3.0.0"`.
    public static func parse(_ raw: String?) -> AntigravitySemVer? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower == "unknown" || lower == "n/a" || lower == "none" {
            return nil
        }

        // Extract the first `major.minor(.patch)?(-prerelease)?` token
        let pattern = #"(?:^|[^0-9])v?(\d+)\.(\d+)(?:\.(\d+))?(?:-([A-Za-z0-9.\-]+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let majRange = Range(match.range(at: 1), in: trimmed),
              let minRange = Range(match.range(at: 2), in: trimmed),
              let major = Int(trimmed[majRange]),
              let minor = Int(trimmed[minRange]) else {
            return nil
        }
        let patch: Int = {
            if let r = Range(match.range(at: 3), in: trimmed), let p = Int(trimmed[r]) {
                return p
            }
            return 0
        }()
        let prerelease: String? = {
            if let r = Range(match.range(at: 4), in: trimmed) {
                let s = String(trimmed[r])
                return s.isEmpty ? nil : s
            }
            return nil
        }()
        return AntigravitySemVer(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    public var description: String {
        if let prerelease, !prerelease.isEmpty {
            return "v\(major).\(minor).\(patch)-\(prerelease)"
        }
        return "v\(major).\(minor).\(patch)"
    }

    public static func < (lhs: AntigravitySemVer, rhs: AntigravitySemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (_?, nil): return true   // prerelease < stable release
        case (nil, _?): return false
        case (let l?, let r?): return l.localizedStandardCompare(r) == .orderedAscending
        }
    }
}

// MARK: - Host Capabilities & Per-Host Profile

/// Runtime-discovered capabilities of a paired Antigravity Desktop / Companion Bridge host.
///
/// Designed for **zero upstream cooperation**: capabilities are discovered via passive response
/// fingerprinting (`ListInstances`, `GetCascadeModelConfigs`, Bridge headers) and lazy
/// error-classification negative caching (`404 / 501 / unimplemented`), with optional SemVer
/// priors only as a non-blocking hint.
public enum HostCapability: String, Codable, Sendable, CaseIterable, Hashable {
    case jetboxSummaries
    case sidecarAutomations
    case conversationAnnotations
    case turnDiff
    case gitVcs
    case conversationOverview
    case sideQuestion
    case revertToStep
    case permissionPreset
    case customizationsCatalog
    case fullTextSearch
    case backgroundTaskControl
    case thinkingEffortExtra
    case orchestratorModels
    case usageQuota
    case streamChunking

    public var displayTitle: String {
        switch self {
        case .jetboxSummaries: return "Real-time Conversation Stream"
        case .sidecarAutomations: return "Native Sidecar Automations"
        case .conversationAnnotations: return "Conversation Annotations"
        case .turnDiff: return "Turn Diff Review"
        case .gitVcs: return "Git Stage, Commit & Push"
        case .conversationOverview: return "Conversation Overview"
        case .sideQuestion: return "/btw Side Questions"
        case .revertToStep: return "Revert Conversation to Step"
        case .permissionPreset: return "Per-Conversation Permission Preset"
        case .customizationsCatalog: return "Customizations & MCP Controls"
        case .fullTextSearch: return "Server Full-Text Search"
        case .backgroundTaskControl: return "Background Task & Subagent Control"
        case .thinkingEffortExtra: return "Extra Thinking Effort (XHigh)"
        case .orchestratorModels: return "Orchestrator Models"
        case .usageQuota: return "Model Usage Quota"
        case .streamChunking: return "Chunked Relay Streaming"
        }
    }

    /// Suggested minimum Antigravity Desktop version hint (advisory only; runtime probing is authoritative).
    public var minimumRecommendedVersion: AntigravitySemVer? {
        switch self {
        case .jetboxSummaries: return AntigravitySemVer(major: 2, minor: 0, patch: 11)
        case .sidecarAutomations: return AntigravitySemVer(major: 2, minor: 20, patch: 0)
        case .conversationAnnotations: return AntigravitySemVer(major: 2, minor: 10, patch: 0)
        case .turnDiff, .gitVcs, .conversationOverview, .sideQuestion,
             .revertToStep, .permissionPreset, .customizationsCatalog,
             .fullTextSearch, .backgroundTaskControl, .thinkingEffortExtra,
             .orchestratorModels, .usageQuota:
            return AntigravitySemVer(major: 2, minor: 33, patch: 0)
        case .streamChunking:
            return AntigravitySemVer(major: 2, minor: 0, patch: 0)
        }
    }

    /// Primary RPC method names associated with this capability.
    public var rpcMethods: [String] {
        switch self {
        case .jetboxSummaries: return ["JetboxSubscribeToSummaries"]
        case .sidecarAutomations: return ["GetSidecars", "ManageSidecar", "GetSidecarEvents"]
        case .conversationAnnotations: return ["UpdateConversationAnnotations", "DeleteCascadeTrajectory"]
        case .turnDiff: return ["GetTurnDiff", "RevertDiffHunk", "SendDiffReviewComments"]
        case .gitVcs: return ["GitStageFile", "GitUnstageFile", "GitDiscardFile", "GitCommit", "GitPush"]
        case .conversationOverview: return ["GetConversationOverview"]
        case .sideQuestion: return ["SendSideQuestion"]
        case .revertToStep: return ["RevertConversationToStep"]
        case .permissionPreset: return ["SetPermissionPreset"]
        case .customizationsCatalog: return ["GetCustomizationsCatalog", "RestartMcpServer", "TogglePlugin", "InstallPlugin"]
        case .fullTextSearch: return ["SearchAllConversations"]
        case .backgroundTaskControl: return ["CancelBackgroundTask", "StopSubagent"]
        case .thinkingEffortExtra, .orchestratorModels, .usageQuota, .streamChunking:
            return []
        }
    }

    public static func capability(forMethod method: String) -> HostCapability? {
        switch method {
        case "JetboxSubscribeToSummaries":
            return .jetboxSummaries
        case "GetSidecars", "ManageSidecar", "GetSidecarEvents":
            return .sidecarAutomations
        case "UpdateConversationAnnotations", "DeleteCascadeTrajectory":
            return .conversationAnnotations
        case "GetTurnDiff", "RevertDiffHunk", "SendDiffReviewComments":
            return .turnDiff
        case "GitStageFile", "GitUnstageFile", "GitDiscardFile", "GitCommit", "GitPush":
            return .gitVcs
        case "GetConversationOverview":
            return .conversationOverview
        case "SendSideQuestion":
            return .sideQuestion
        case "RevertConversationToStep":
            return .revertToStep
        case "SetPermissionPreset":
            return .permissionPreset
        case "GetCustomizationsCatalog", "RestartMcpServer", "TogglePlugin", "InstallPlugin":
            return .customizationsCatalog
        case "SearchAllConversations":
            return .fullTextSearch
        case "CancelBackgroundTask", "StopSubagent":
            return .backgroundTaskControl
        default:
            return nil
        }
    }
}

/// Tri-state capability support status discovered for a host.
public enum CapabilitySupportState: String, Codable, Sendable, Equatable {
    case unknown
    case supported
    case unsupported
}

/// Per-host runtime compatibility profile tracking version, Bridge polyfills,
/// positive/negative RPC method caches, stripped unknown proto fields, and enum downgrades.
public struct HostCapabilityProfile: Codable, Sendable, Equatable {
    public var hostKey: String
    /// Raw version advertised by `ListInstances`, Companion Bridge headers, or upstream status RPC. `nil` if unknown.
    public var reportedVersion: String?
    public var isCompanionBridge: Bool
    public var bridgeSupportedMethods: Set<String>
    public var supportedMethods: Set<String>
    public var unsupportedMethods: Set<String>
    public var strippedFieldsByMethod: [String: Set<String>]
    public var downgradedEnumsByMethod: [String: [String: String]]
    public var passiveSignals: [HostCapability: CapabilitySupportState]
    public var updatedAt: Date

    public init(
        hostKey: String = "default",
        reportedVersion: String? = nil,
        isCompanionBridge: Bool = false,
        bridgeSupportedMethods: Set<String> = [],
        supportedMethods: Set<String> = [],
        unsupportedMethods: Set<String> = [],
        strippedFieldsByMethod: [String: Set<String>] = [:],
        downgradedEnumsByMethod: [String: [String: String]] = [:],
        passiveSignals: [HostCapability: CapabilitySupportState] = [:],
        updatedAt: Date = Date()
    ) {
        self.hostKey = hostKey
        self.reportedVersion = Self.normalizedVersionString(reportedVersion)
        self.isCompanionBridge = isCompanionBridge
        self.bridgeSupportedMethods = bridgeSupportedMethods
        self.supportedMethods = supportedMethods
        self.unsupportedMethods = unsupportedMethods
        self.strippedFieldsByMethod = strippedFieldsByMethod
        self.downgradedEnumsByMethod = downgradedEnumsByMethod
        self.passiveSignals = passiveSignals
        self.updatedAt = updatedAt
    }

    public static func normalizedVersionString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower == "unknown" || lower == "n/a" || lower == "none" {
            return nil
        }
        return trimmed
    }

    public var parsedVersion: AntigravitySemVer? {
        AntigravitySemVer.parse(reportedVersion)
    }

    public var displayVersionLabel: String {
        if let parsed = parsedVersion {
            return parsed.description
        }
        if let reportedVersion, !reportedVersion.isEmpty {
            return reportedVersion
        }
        return "Version unknown"
    }

    /// Updates reported version; if the host upgraded/downgraded to a different version,
    /// clears stale negative caches so newly added methods are re-probed automatically.
    public mutating func updateReportedVersion(_ newVersion: String?) {
        let normalized = Self.normalizedVersionString(newVersion)
        guard let normalized else { return }
        if let existing = reportedVersion, existing != normalized {
            unsupportedMethods.removeAll()
            strippedFieldsByMethod.removeAll()
            downgradedEnumsByMethod.removeAll()
            passiveSignals.removeAll()
        }
        reportedVersion = normalized
        updatedAt = Date()
    }

    public mutating func recordMethodSupported(_ method: String) {
        supportedMethods.insert(method)
        unsupportedMethods.remove(method)
        if let cap = HostCapability.capability(forMethod: method) {
            passiveSignals[cap] = .supported
        }
        updatedAt = Date()
    }

    public mutating func recordMethodUnsupported(_ method: String) {
        guard !bridgeSupportedMethods.contains(method) else { return }
        unsupportedMethods.insert(method)
        supportedMethods.remove(method)
        if let cap = HostCapability.capability(forMethod: method) {
            let anySupported = cap.rpcMethods.contains {
                supportedMethods.contains($0) || bridgeSupportedMethods.contains($0)
            }
            if !anySupported {
                passiveSignals[cap] = .unsupported
            }
        }
        updatedAt = Date()
    }

    public mutating func recordBridgeCapabilities(_ methods: Set<String>) {
        guard !methods.isEmpty else { return }
        isCompanionBridge = true
        bridgeSupportedMethods.formUnion(methods)
        unsupportedMethods.subtract(methods)
        for method in methods {
            if let cap = HostCapability.capability(forMethod: method) {
                passiveSignals[cap] = .supported
            }
        }
        updatedAt = Date()
    }

    public mutating func recordStrippedField(_ fieldName: String, forMethod method: String) {
        strippedFieldsByMethod[method, default: []].insert(fieldName)
        updatedAt = Date()
    }

    public mutating func recordDowngradedEnum(from invalidValue: String, to replacement: String, forMethod method: String) {
        downgradedEnumsByMethod[method, default: [:]][invalidValue] = replacement
        updatedAt = Date()
    }

    public mutating func recordPassiveSignal(_ capability: HostCapability, state: CapabilitySupportState) {
        passiveSignals[capability] = state
        updatedAt = Date()
    }

    public func isMethodKnownUnsupported(_ method: String) -> Bool {
        unsupportedMethods.contains(method) && !bridgeSupportedMethods.contains(method)
    }

    /// Evaluates authoritative runtime support state for `capability`.
    /// Runtime observations and Bridge declarations always supersede version priors.
    public func supportState(for capability: HostCapability) -> CapabilitySupportState {
        let methods = capability.rpcMethods
        if methods.contains(where: { bridgeSupportedMethods.contains($0) || supportedMethods.contains($0) }) {
            return .supported
        }
        if let signal = passiveSignals[capability], signal != .unknown {
            return signal
        }
        if !methods.isEmpty && methods.contains(where: { unsupportedMethods.contains($0) }) {
            return .unsupported
        }
        return .unknown
    }

    /// Advisory version-prior hint (true when a known older SemVer predates the capability and
    /// neither the host nor a Companion Bridge has confirmed support).
    public func isOlderThanRecommendedVersion(for capability: HostCapability) -> Bool {
        guard supportState(for: capability) != .supported,
              let parsed = parsedVersion,
              let minVer = capability.minimumRecommendedVersion else {
            return false
        }
        return parsed < minVer
    }

    /// Honest user-facing explanation when an older PC rejects a newer mobile feature.
    public func userFacingUnsupportedMessage(for capability: HostCapability) -> String {
        let versionPart: String = {
            if let parsed = parsedVersion {
                return " (\(parsed.description))"
            }
            if let reportedVersion, !reportedVersion.isEmpty {
                return " (\(reportedVersion))"
            }
            return ""
        }()
        let minHint: String = {
            if let minVer = capability.minimumRecommendedVersion {
                return " Upgrade Antigravity Desktop to \(minVer.description)+ or connect via Mac Companion Bridge."
            }
            return " Upgrade Antigravity Desktop or connect via Mac Companion Bridge."
        }()
        return "\(capability.displayTitle) isn't supported by this Desktop host\(versionPart).\(minHint)"
    }
}

// MARK: - Protocol Compatibility Engine (Zero-Upstream Self-Healing Helpers)

/// Stateless protocol compatibility utilities shared by **both** Direct LAN and Official Cloud Relay channels.
public enum ProtocolCompatibilityEngine: Sendable {

    /// Returns `true` when an error indicates the remote `language_server` does not implement the requested RPC method.
    public static func isMethodUnimplementedError(_ error: Error) -> Bool {
        guard case let AntigravityRPCError.httpError(code, body) = error else { return false }
        return isMethodUnimplementedResponse(statusCode: code, body: body)
    }

    public static func isMethodUnimplementedResponse(statusCode: Int, body: String) -> Bool {
        if statusCode == 404 || statusCode == 501 {
            return true
        }
        let lower = body.lowercased()
        return lower.contains("unimplemented")
            || lower.contains("unknown method")
            || lower.contains("method not found")
            || lower.contains("not implemented")
    }

    /// Unwraps JSON error payloads (`{"message": "..."}` / `{"error": "..."}`) and normalizes
    /// JSON-escaped quotes (`\"`) so protojson field/enum error extractors work on both raw HTTP
    /// Connect-RPC bodies and already-unwrapped error strings.
    private static func candidateErrorStrings(from raw: String) -> [String] {
        var candidates: [String] = []
        if let data = raw.data(using: .utf8),
           let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
            for key in ["message", "error", "detail", "details"] {
                if let msg = obj[key]?.stringValue, !msg.isEmpty {
                    candidates.append(msg)
                    if msg.contains("\\\"") {
                        candidates.append(msg.replacingOccurrences(of: "\\\"", with: "\""))
                    }
                }
            }
        }
        candidates.append(raw)
        if raw.contains("\\\"") {
            candidates.append(raw.replacingOccurrences(of: "\\\"", with: "\""))
        }
        return candidates
    }

    /// Extracts an unknown protobuf JSON field name from Connect-RPC / protojson error messages, e.g.:
    /// - `unknown field "thinkingEffort"`
    /// - `{"code":"invalid_argument","message":"unknown field \"permissionPreset\""}`
    /// - `no such field "agentPersona"`
    public static func extractUnknownProtoFieldName(from message: String) -> String? {
        let patterns = [
            #"unknown field\s+["'`]+([A-Za-z0-9_]+)["'`]+"#,
            #"no such field\s+["'`]+([A-Za-z0-9_]+)["'`]+"#,
            #"unrecognized field\s+["'`]+([A-Za-z0-9_]+)["'`]+"#
        ]
        for candidate in candidateErrorStrings(from: message) {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)),
                   let range = Range(match.range(at: 1), in: candidate) {
                    let field = String(candidate[range])
                    if !field.isEmpty {
                        return field
                    }
                }
            }
        }
        return nil
    }

    /// Extracts a rejected protobuf enum value string from Connect-RPC / protojson error messages, e.g.:
    /// - `invalid value for enum type exa.cortex_pb.ThinkingEffort: "XHIGH"`
    /// - `{"code":"invalid_argument","message":"invalid value for enum type ThinkingEffort: \"XHIGH\""}`
    /// - `unknown enum value "PERMISSION_SCOPE_CONVERSATION"`
    public static func extractInvalidEnumValue(from message: String) -> String? {
        let patterns = [
            #"invalid value for enum[^"'`]*["'`]+([A-Za-z0-9_\-]+)["'`]+"#,
            #"unknown enum value[^"'`]*["'`]+([A-Za-z0-9_\-]+)["'`]+"#,
            #"invalid enum value[^"'`]*["'`]+([A-Za-z0-9_\-]+)["'`]+"#
        ]
        for candidate in candidateErrorStrings(from: message) {
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)),
                   let range = Range(match.range(at: 1), in: candidate) {
                    let enumVal = String(candidate[range])
                    if !enumVal.isEmpty {
                        return enumVal
                    }
                }
            }
        }
        return nil
    }

    /// Deterministic enum downgrade map when a newer mobile client talks to an older Desktop `language_server`.
    public static func downgradedEnumReplacement(for invalidValue: String) -> String? {
        switch invalidValue {
        case "XHIGH": return "HIGH"
        case "xhigh": return "high"
        case "EXTRA": return "HIGH"
        case "extra": return "high"
        case "THINKING_EFFORT_EXTRA", "THINKING_EFFORT_XHIGH": return "THINKING_EFFORT_HIGH"
        case "PERMISSION_SCOPE_CONVERSATION", "PERMISSION_SCOPE_ALWAYS": return "PERMISSION_SCOPE_TURN"
        case "PERMISSION_SCOPE_TURN": return "PERMISSION_SCOPE_ONCE"
        case "ARTIFACT_REVIEW_MODE_TURBO": return "ARTIFACT_REVIEW_MODE_AUTO"
        case "CASCADE_COMMANDS_AUTO_EXECUTION_EAGER": return "CASCADE_COMMANDS_AUTO_EXECUTION_AUTO"
        case "PERMISSION_PRESET_DEFAULT": return "PERMISSION_PRESET_AUTO"
        default:
            return nil
        }
    }

    /// Recursively removes `fieldName` anywhere inside a JSON object/array tree.
    /// When stripping a rich `SendUserCascadeMessage` item subtype (`codeQuote`, `mention`, `media`),
    /// preserves user intent by folding its readable label/URI/snippet into a plain `{"text": ...}` item.
    public static func recursivelyRemoveField(
        _ fieldName: String,
        from object: [String: JSONValue]
    ) -> (updated: [String: JSONValue], didRemove: Bool) {
        var copy = object
        var didRemove = false

        if copy.removeValue(forKey: fieldName) != nil {
            didRemove = true
        }

        for (key, value) in copy {
            if key == "items", let arr = value.arrayValue {
                var newItems: [JSONValue] = []
                var itemsMutated = false
                for entry in arr {
                    if let folded = foldRichItemIfStripping(entry, fieldName: fieldName) {
                        newItems.append(folded)
                        itemsMutated = true
                    } else {
                        let (cleanedVal, removedInside) = recursivelyRemoveField(fieldName, fromValue: entry)
                        if removedInside { itemsMutated = true }
                        newItems.append(cleanedVal)
                    }
                }
                if itemsMutated {
                    copy[key] = .array(newItems)
                    didRemove = true
                }
            } else {
                let (cleanedVal, removedInside) = recursivelyRemoveField(fieldName, fromValue: value)
                if removedInside {
                    copy[key] = cleanedVal
                    didRemove = true
                }
            }
        }
        return (copy, didRemove)
    }

    private static func foldRichItemIfStripping(_ entry: JSONValue, fieldName: String) -> JSONValue? {
        guard fieldName == "codeQuote" || fieldName == "mention" || fieldName == "media",
              let entryObj = entry.objectValue else {
            return nil
        }
        let container = entryObj["item"]?.objectValue ?? entryObj
        guard let strippedObj = container[fieldName]?.objectValue else {
            return nil
        }
        let label = strippedObj["label"]?.stringValue
            ?? strippedObj["uri"]?.stringValue
            ?? strippedObj["targetUri"]?.stringValue
            ?? strippedObj["filePath"]?.stringValue
            ?? fieldName
        if let snippet = strippedObj["snippet"]?.stringValue, !snippet.isEmpty {
            return .object(["text": .string("[Context: \(label)]\n\(snippet)")])
        }
        return .object(["text": .string("[Attached \(fieldName): \(label)]")])
    }

    private static func recursivelyRemoveField(
        _ fieldName: String,
        fromValue value: JSONValue
    ) -> (updated: JSONValue, didRemove: Bool) {
        switch value {
        case .object(let dict):
            let (updated, removed) = recursivelyRemoveField(fieldName, from: dict)
            return (.object(updated), removed)
        case .array(let arr):
            var didRemove = false
            let mapped = arr.map { elem -> JSONValue in
                let (u, r) = recursivelyRemoveField(fieldName, fromValue: elem)
                if r { didRemove = true }
                return u
            }
            return (.array(mapped), didRemove)
        default:
            return (value, false)
        }
    }

    /// Recursively replaces exact string occurrences of `invalidValue` with `replacement`.
    public static func recursivelyReplaceEnumValue(
        _ invalidValue: String,
        with replacement: String,
        in object: [String: JSONValue]
    ) -> (updated: [String: JSONValue], didReplace: Bool) {
        var copy = object
        var didReplace = false
        for (key, value) in copy {
            let (updated, replaced) = recursivelyReplaceEnumValue(invalidValue, with: replacement, inValue: value)
            if replaced {
                copy[key] = updated
                didReplace = true
            }
        }
        return (copy, didReplace)
    }

    private static func recursivelyReplaceEnumValue(
        _ invalidValue: String,
        with replacement: String,
        inValue value: JSONValue
    ) -> (updated: JSONValue, didReplace: Bool) {
        switch value {
        case .string(let s) where s == invalidValue:
            return (.string(replacement), true)
        case .object(let dict):
            let (u, r) = recursivelyReplaceEnumValue(invalidValue, with: replacement, in: dict)
            return (.object(u), r)
        case .array(let arr):
            var didReplace = false
            let mapped = arr.map { elem -> JSONValue in
                let (u, r) = recursivelyReplaceEnumValue(invalidValue, with: replacement, inValue: elem)
                if r { didReplace = true }
                return u
            }
            return (.array(mapped), didReplace)
        default:
            return (value, false)
        }
    }

    /// Pre-applies cached field strips and enum downgrades learned for this host + method
    /// so subsequent RPC calls succeed on the first round-trip.
    public static func applyKnownDowngrades(
        to body: [String: JSONValue],
        method: String,
        profile: HostCapabilityProfile
    ) -> [String: JSONValue] {
        var working = body
        if let fieldsToStrip = profile.strippedFieldsByMethod[method] {
            for field in fieldsToStrip.sorted() {
                working = recursivelyRemoveField(field, from: working).updated
            }
        }
        if let enumMap = profile.downgradedEnumsByMethod[method] {
            for (invalidVal, replacement) in enumMap.sorted(by: { $0.key < $1.key }) {
                working = recursivelyReplaceEnumValue(invalidVal, with: replacement, in: working).updated
            }
        }
        return working
    }

    /// Extracts a reported Desktop / LanguageServer version from HTTP response headers or an upstream JSON body.
    public static func extractVersionFromHeadersOrBody(
        headers: [AnyHashable: Any],
        body: [String: JSONValue]? = nil
    ) -> String? {
        let versionHeaderKeys: Set<String> = [
            "x-antigravity-desktop-version",
            "x-antigravity-server-version",
            "x-codeium-server-version",
            "x-language-server-version"
        ]
        for (rawKey, rawVal) in headers {
            let key = String(describing: rawKey).lowercased()
            if versionHeaderKeys.contains(key) {
                let value = String(describing: rawVal).trimmingCharacters(in: .whitespacesAndNewlines)
                if let normalized = HostCapabilityProfile.normalizedVersionString(value) {
                    return normalized
                }
            }
        }

        if let body {
            let directKeys = ["serverVersion", "desktopVersion", "appVersion", "languageServerVersion", "version"]
            for key in directKeys {
                if let val = HostCapabilityProfile.normalizedVersionString(body[key]?.stringValue),
                   AntigravitySemVer.parse(val) != nil {
                    return val
                }
            }
            let nestedContainers = ["serverInfo", "userStatus", "host", "metadata", "status"]
            for containerKey in nestedContainers {
                if let nested = body[containerKey]?.objectValue {
                    for key in directKeys {
                        if let val = HostCapabilityProfile.normalizedVersionString(nested[key]?.stringValue),
                           AntigravitySemVer.parse(val) != nil {
                            return val
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Extracts comma-separated method names polyfilled by `scripts/mac-companion-bridge.py`.
    public static func extractBridgeCapabilities(from headers: [AnyHashable: Any]) -> Set<String> {
        for (rawKey, rawVal) in headers {
            let key = String(describing: rawKey).lowercased()
            if key == "x-antigravity-bridge-capabilities" {
                let raw = String(describing: rawVal)
                let methods = raw
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                return Set(methods)
            }
        }
        return []
    }
}
