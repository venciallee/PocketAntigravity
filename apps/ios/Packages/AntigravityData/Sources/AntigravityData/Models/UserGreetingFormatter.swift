import Foundation

/// Signed-in user profile snapshot extracted from Antigravity Language Server `GetUserStatus`.
public struct LiveUserProfile: Codable, Sendable, Equatable {
    public let displayName: String?
    public let email: String?
    public let planDisplayName: String?

    public init(
        displayName: String? = nil,
        email: String? = nil,
        planDisplayName: String? = nil
    ) {
        self.displayName = displayName
        self.email = email
        self.planDisplayName = planDisplayName
    }
}

/// Cross-platform home hero greeting & user display-name sanitizer mirrored 1:1 with KMP `UserGreetingFormatter`.
///
/// Ensures live mode displays the real signed-in user's name from `GetUserStatus` (or a clean
/// nameless greeting when unavailable) and never leaks static design-mockup placeholder names.
public enum UserGreetingFormatter: Sendable {
    private static let maxGreetingNameLength = 24

    private static let placeholderNames: Set<String> = [
        "unknown",
        "anonymous",
        "user",
        "guest",
        "default",
        "antigravity",
        "none",
        "null",
        "n/a",
        "me",
        "self"
    ]

    /// Normalizes a raw display name (with optional email fallback) into a concise, friendly
    /// greeting name suitable for `"Welcome back, <name>."`, or `nil` if no usable name exists.
    public static func formatGreetingName(
        _ rawName: String?,
        fallbackEmail: String? = nil
    ) -> String? {
        if let clean = normalizeCandidate(rawName) {
            return clean
        }
        return extractFromEmail(fallbackEmail)
    }

    /// Builds the centered Home (`UE01`) hero greeting copy.
    public static func homeHeroGreeting(
        displayName: String?,
        language: AppLanguage = .english
    ) -> String {
        let clean = formatGreetingName(displayName)
        if language.isChinese {
            if let clean {
                return "欢迎回来，\n\(clean)。\n今天从哪里开始？"
            }
            return "欢迎回来。\n今天从哪里\n开始？"
        }
        if let clean {
            return "Welcome back,\n\(clean). Where\nshould we pick up?"
        }
        return "Welcome back.\nWhere should\nwe pick up?"
    }

    /// Builds the dimmed Add Context popover backdrop greeting copy.
    public static func addContextBackdropGreeting(
        displayName: String?,
        language: AppLanguage = .english
    ) -> String {
        let clean = formatGreetingName(displayName)
        if language.isChinese {
            if let clean {
                return "欢迎回来，\(clean)。\n今天从哪里开始？"
            }
            return "欢迎回来。\n今天从哪里开始？"
        }
        if let clean {
            return "Welcome back, \(clean).\nWhere should we pick\nup?"
        }
        return "Welcome back.\nWhere should we pick\nup?"
    }

    /// Builds the compact dimmed Permissions Preset popover backdrop greeting copy.
    public static func compactBackdropGreeting(
        displayName: String?,
        language: AppLanguage = .english
    ) -> String {
        let clean = formatGreetingName(displayName)
        if language.isChinese {
            if let clean {
                return "欢迎回来，\(clean)。"
            }
            return "欢迎回来。"
        }
        if let clean {
            return "Welcome back, \(clean)."
        }
        return "Welcome back."
    }

    private static func normalizeCandidate(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("@") {
            return extractFromEmail(trimmed)
        }
        let tokens = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        let collapsed = tokens.joined(separator: " ")
        guard !isDisallowedToken(collapsed) else { return nil }

        let chosen: String
        if tokens.count > 1 {
            let first = tokens[0]
            let isShortInitial = first.count <= 1 || (first.count == 2 && first.hasSuffix("."))
            chosen = isShortInitial ? collapsed : first
        } else {
            chosen = collapsed
        }

        guard !chosen.isEmpty, chosen.count <= maxGreetingNameLength else { return nil }
        guard !isDisallowedToken(chosen) else { return nil }
        guard chosen.contains(where: \.isLetter) else { return nil }
        return chosen
    }

    private static func extractFromEmail(_ rawEmail: String?) -> String? {
        let trimmed = rawEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let atIdx = trimmed.firstIndex(of: "@"), atIdx > trimmed.startIndex else {
            return nil
        }
        let rawLocal = String(trimmed[..<atIdx])
        let localPart = rawLocal
            .split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !localPart.isEmpty else { return nil }

        let segments = localPart
            .components(separatedBy: CharacterSet(charactersIn: "._-"))
            .filter { !$0.isEmpty }
        guard let chosen = segments.first(where: { seg in
            seg.count <= maxGreetingNameLength
                && seg.contains(where: \.isLetter)
                && !isDisallowedToken(seg)
        }) else {
            return nil
        }

        let isAllLowerAscii = chosen.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57)
        }
        if isAllLowerAscii,
           let first = chosen.first,
           let scalar = first.unicodeScalars.first,
           scalar.value >= 97 && scalar.value <= 122 {
            return String(first).uppercased() + String(chosen.dropFirst())
        }
        return chosen
    }

    private static func isDisallowedToken(_ value: String) -> Bool {
        if placeholderNames.contains(value.lowercased()) {
            return true
        }
        if UUID(uuidString: value) != nil {
            return true
        }
        if value.count >= 16 && value.allSatisfy({ $0.isHexDigit || $0 == "-" }) {
            return true
        }
        return false
    }
}
