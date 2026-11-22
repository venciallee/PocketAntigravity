import Foundation
import SwiftUI
import AntigravityData

/// Extends `AntigravityData.ESDDVerifySceneCase` with ESDD state & claim metadata.
public extension ESDDVerifySceneCase {
    var stateId: String {
        rawValue
    }

    var claimId: String {
        switch self {
        case .agentsHome:         return "CLAIM-01"
        case .displayOptions:     return "CLAIM-02"
        case .contextMenuPin:     return "CLAIM-03"
        case .projectDetail:      return "CLAIM-04"
        case .createProject:      return "CLAIM-05"
        case .automations:        return "CLAIM-06"
        case .chatAndComposer:    return "CLAIM-07"
        case .addContext:         return "CLAIM-08"
        case .modelAndMode:       return "CLAIM-09"
        case .structuredQuestion: return "CLAIM-10"
        case .planReview:         return "CLAIM-11"
        case .turnDiffReview:     return "CLAIM-12"
        case .liveActivitySpec:   return "CLAIM-13"
        }
    }
}

/// Resolves `agpocket://verify/<case>` (and legacy `antigravity://verify/<case>`) deep links
/// and `--ui-verify` CLI arguments into deterministic offline scenes without requiring external network credentials.
public enum DebugSceneFactory {
    public static func resolveDeepLink(_ url: URL) -> ESDDVerifySceneCase? {
        guard let scheme = url.scheme?.lowercased(),
              (scheme == "agpocket" || scheme == "antigravity"),
              url.host?.lowercased() == "verify" else {
            return nil
        }
        let slug = url.lastPathComponent
        return resolveIdentifier(slug)
    }

    public static func launchVerifyCase(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> ESDDVerifySceneCase? {
        for (index, arg) in arguments.enumerated() {
            if arg == "--ui-verify", index + 1 < arguments.count {
                if let resolved = resolveIdentifier(arguments[index + 1]) {
                    return resolved
                }
            } else if arg.hasPrefix("--ui-verify=") {
                let value = String(arg.dropFirst("--ui-verify=".count))
                if let resolved = resolveIdentifier(value) {
                    return resolved
                }
            }
        }
        return nil
    }

    public static func resolveIdentifier(_ rawSlug: String) -> ESDDVerifySceneCase? {
        let trimmed = rawSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = ESDDVerifySceneCase(rawValue: trimmed) {
            return exact
        }
        if let upper = ESDDVerifySceneCase(rawValue: trimmed.uppercased()) {
            return upper
        }

        switch trimmed.lowercased() {
        case "ue01", "agents-home", "workspace-home":
            return .agentsHome
        case "ue02", "display-options":
            return .displayOptions
        case "ue03", "context-menu-pin", "context-menu":
            return .contextMenuPin
        case "ue04", "project-detail":
            return .projectDetail
        case "ue05", "create-project", "new-project":
            return .createProject
        case "ue06", "automations":
            return .automations
        case "ue07", "chat-and-composer", "cascade-streaming":
            return .chatAndComposer
        case "ue08", "add-context":
            return .addContext
        case "ue09", "model-and-mode":
            return .modelAndMode
        case "ue10", "structured-question", "ask-question":
            return .structuredQuestion
        case "ue11", "plan-review", "artifact-plan":
            return .planReview
        case "ue12", "turn-diff-review", "turn-diff":
            return .turnDiffReview
        case "ue13", "live-activity-spec", "live-activity":
            return .liveActivitySpec
        default:
            return nil
        }
    }

    /// Detects `--ui-verify settings` (offline Settings tab capture for Light/Dark visual verification).
    public static func isVerifySettingsLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        for (index, arg) in arguments.enumerated() {
            if arg == "--ui-verify", index + 1 < arguments.count {
                let val = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if val == "settings" || val == "pairing-settings" {
                    return true
                }
            } else if arg.hasPrefix("--ui-verify=") {
                let val = String(arg.dropFirst("--ui-verify=".count)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if val == "settings" || val == "pairing-settings" {
                    return true
                }
            }
        }
        return false
    }

    /// Resolves optional `--ui-appearance dark|light|system` CLI argument or `ANTIGRAVITY_UI_APPEARANCE` env var.
    public static func launchAppearanceOverride(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppAppearanceMode? {
        for (index, arg) in arguments.enumerated() {
            if arg == "--ui-appearance", index + 1 < arguments.count {
                if let parsed = parseAppearanceMode(arguments[index + 1]) {
                    return parsed
                }
            } else if arg.hasPrefix("--ui-appearance=") {
                let value = String(arg.dropFirst("--ui-appearance=".count))
                if let parsed = parseAppearanceMode(value) {
                    return parsed
                }
            }
        }
        if let envVal = environment["ANTIGRAVITY_UI_APPEARANCE"],
           let parsed = parseAppearanceMode(envVal) {
            return parsed
        }
        return nil
    }

    /// Resolves optional `?appearance=light|dark|system` query item on `antigravity://verify/<case>` deep links.
    public static func resolveDeepLinkAppearance(_ url: URL) -> AppAppearanceMode? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let item = components.queryItems?.first(where: { $0.name.lowercased() == "appearance" }),
              let raw = item.value else {
            return nil
        }
        return parseAppearanceMode(raw)
    }

    public static func parseAppearanceMode(_ raw: String) -> AppAppearanceMode? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "system", "auto":
            return .system
        case "dark":
            return .dark
        case "light":
            return .light
        default:
            return nil
        }
    }
}
