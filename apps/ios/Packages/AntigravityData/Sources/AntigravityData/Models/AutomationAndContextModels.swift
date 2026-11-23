import Foundation

// MARK: - Automations Models (UE06)

/// Section grouping in `AutomationsViewController` (`UE06`).
public enum AutomationSectionKind: String, ResilientStringEnum, CaseIterable, Identifiable {
    case scheduled = "SCHEDULED"
    case alwaysOn = "ALWAYS ON"
    case paused = "PAUSED"

    public var id: String { rawValue }
    public static var unknownFallback: AutomationSectionKind { .scheduled }
}

public typealias AutomationCategory = AutomationSectionKind

/// Native Antigravity 2.0 `exa.language_server_pb.SidecarAction` enum values for `ManageSidecar`.
public enum SidecarManageAction: String, ResilientStringEnum, Equatable {
    case unspecified = "SIDECAR_ACTION_UNSPECIFIED"
    case disable = "SIDECAR_ACTION_DISABLE"
    case enable = "SIDECAR_ACTION_ENABLE"
    case delete = "SIDECAR_ACTION_DELETE"
    case restart = "SIDECAR_ACTION_RESTART"
    case create = "SIDECAR_ACTION_CREATE"
    case setProject = "SIDECAR_ACTION_SET_PROJECT"
    case update = "SIDECAR_ACTION_UPDATE"
    case setAllProjects = "SIDECAR_ACTION_SET_ALL_PROJECTS"
    case updateArgs = "SIDECAR_ACTION_UPDATE_ARGS"
    case runNow = "SIDECAR_ACTION_RUN_NOW"

    public static var unknownFallback: SidecarManageAction { .unspecified }
}

/// Decoded event from `exa.language_server_pb.LanguageServerService/GetSidecarEvents`.
public struct SidecarRunEvent: Codable, Sendable, Equatable {
    public var timestampMs: Int64
    public var error: String?
    public var conversationId: String?
    public var prompt: String?

    public init(
        timestampMs: Int64,
        error: String? = nil,
        conversationId: String? = nil,
        prompt: String? = nil
    ) {
        self.timestampMs = timestampMs
        self.error = error
        self.conversationId = conversationId
        self.prompt = prompt
    }
}

/// Outcome status for an individual Automation run (`UE06B`).
public enum AutomationRunStatus: String, ResilientStringEnum, CaseIterable, Identifiable {
    case succeeded = "Succeeded"
    case needsReview = "Needs review"
    case failed = "Failed"
    case running = "Running"

    public var id: String { rawValue }
    public static var unknownFallback: AutomationRunStatus { .succeeded }
}

/// Recent execution row displayed on `AutomationDetailView` (`UE06B`).
public struct AutomationRunRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var status: AutomationRunStatus
    public var relativeTimeLabel: String
    public var summaryText: String
    public var durationLabel: String
    public var cascadeId: String?

    public init(
        id: String,
        status: AutomationRunStatus,
        relativeTimeLabel: String,
        summaryText: String,
        durationLabel: String = "",
        cascadeId: String? = nil
    ) {
        self.id = id
        self.status = status
        self.relativeTimeLabel = relativeTimeLabel
        self.summaryText = summaryText
        self.durationLabel = durationLabel
        self.cascadeId = cascadeId
    }
}

/// Scheduled, event-triggered, or paused background agent automation (`UE04`, `UE06`, `UE06B`, `UE06C`).
/// Maps directly to Antigravity 2.0 native Sidecars (`GetSidecars`, `GetSidecarEvents`, `ManageSidecar`).
public struct AutomationItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var projectSlug: String
    public var scheduleSummary: String
    public var section: AutomationSectionKind
    public var nextRunText: String
    public var lastRunText: String
    public var needsReview: Bool
    public var isRunningNow: Bool

    // Native Antigravity 2.0 Sidecar metadata
    public var descriptionText: String
    public var prompt: String
    public var cronExpression: String
    public var projectId: String?
    public var allProjects: Bool
    public var modelLabel: String?
    public var lastRunCascadeId: String?
    public var lastError: String?
    public var isEnabled: Bool
    public var isScheduleBuiltin: Bool
    public var originInstanceUuid: String?
    public var repeatsLabel: String
    public var timeLabel: String
    public var timezoneLabel: String
    public var recentRuns: [AutomationRunRecord]

    public init(
        id: String,
        title: String,
        projectSlug: String,
        scheduleSummary: String,
        section: AutomationSectionKind,
        nextRunText: String,
        lastRunText: String,
        needsReview: Bool = false,
        isRunningNow: Bool = false,
        descriptionText: String = "",
        prompt: String = "",
        cronExpression: String = "",
        projectId: String? = nil,
        allProjects: Bool = false,
        modelLabel: String? = nil,
        lastRunCascadeId: String? = nil,
        lastError: String? = nil,
        isEnabled: Bool? = nil,
        isScheduleBuiltin: Bool? = nil,
        originInstanceUuid: String? = nil,
        repeatsLabel: String = "Daily",
        timeLabel: String = "02:00",
        timezoneLabel: String = "America/Los_Angeles (PDT)",
        recentRuns: [AutomationRunRecord] = []
    ) {
        self.id = id
        self.title = title
        self.projectSlug = projectSlug
        self.scheduleSummary = scheduleSummary
        self.section = section
        self.nextRunText = nextRunText
        self.lastRunText = lastRunText
        self.needsReview = needsReview
        self.isRunningNow = isRunningNow
        self.descriptionText = descriptionText
        self.prompt = prompt.isEmpty ? title : prompt
        self.cronExpression = cronExpression
        self.projectId = projectId
        self.allProjects = allProjects
        self.modelLabel = modelLabel
        self.lastRunCascadeId = lastRunCascadeId
        self.lastError = lastError
        self.isEnabled = isEnabled ?? (section != .paused)
        self.isScheduleBuiltin = isScheduleBuiltin ?? (section != .alwaysOn)
        self.originInstanceUuid = originInstanceUuid
        self.repeatsLabel = repeatsLabel
        self.timeLabel = timeLabel
        self.timezoneLabel = timezoneLabel
        self.recentRuns = recentRuns
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, projectSlug, scheduleSummary, section, nextRunText, lastRunText
        case needsReview, isRunningNow
        case descriptionText, prompt, cronExpression, projectId, allProjects
        case modelLabel, lastRunCascadeId, lastError, isEnabled, isScheduleBuiltin
        case originInstanceUuid, repeatsLabel, timeLabel, timezoneLabel, recentRuns
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        let decodedTitle = try c.decode(String.self, forKey: .title)
        self.title = decodedTitle
        self.projectSlug = try c.decodeIfPresent(String.self, forKey: .projectSlug) ?? "All projects"
        self.scheduleSummary = try c.decodeIfPresent(String.self, forKey: .scheduleSummary) ?? ""
        let decodedSection = try c.decodeIfPresent(AutomationSectionKind.self, forKey: .section) ?? .scheduled
        self.section = decodedSection
        self.nextRunText = try c.decodeIfPresent(String.self, forKey: .nextRunText) ?? ""
        self.lastRunText = try c.decodeIfPresent(String.self, forKey: .lastRunText) ?? ""
        self.needsReview = try c.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
        self.isRunningNow = try c.decodeIfPresent(Bool.self, forKey: .isRunningNow) ?? false
        self.descriptionText = try c.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        self.prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? decodedTitle
        self.cronExpression = try c.decodeIfPresent(String.self, forKey: .cronExpression) ?? ""
        self.projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        self.allProjects = try c.decodeIfPresent(Bool.self, forKey: .allProjects) ?? false
        self.modelLabel = try c.decodeIfPresent(String.self, forKey: .modelLabel)
        self.lastRunCascadeId = try c.decodeIfPresent(String.self, forKey: .lastRunCascadeId)
        self.lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? (decodedSection != .paused)
        self.isScheduleBuiltin = try c.decodeIfPresent(Bool.self, forKey: .isScheduleBuiltin) ?? (decodedSection != .alwaysOn)
        self.originInstanceUuid = try c.decodeIfPresent(String.self, forKey: .originInstanceUuid)
        self.repeatsLabel = try c.decodeIfPresent(String.self, forKey: .repeatsLabel) ?? "Daily"
        self.timeLabel = try c.decodeIfPresent(String.self, forKey: .timeLabel) ?? "02:00"
        self.timezoneLabel = try c.decodeIfPresent(String.self, forKey: .timezoneLabel) ?? "America/Los_Angeles (PDT)"
        self.recentRuns = try c.decodeIfPresent([AutomationRunRecord].self, forKey: .recentRuns) ?? []
    }

    public var category: AutomationSectionKind {
        get { section }
        set { section = newValue }
    }

    public var nextRunLabel: String {
        get { nextRunText }
        set { nextRunText = newValue }
    }

    public var lastRunLabel: String {
        get { lastRunText }
        set { lastRunText = newValue }
    }
}

/// Pure-Swift codec for Antigravity 2.0 scheduled sidecar `args`, 5-field `CRON_TZ` expressions,
/// human-readable next-run calculation, and natural-language quick-create parsing.
public enum AutomationScheduleCodec: Sendable {
    public struct ParsedNaturalSchedule: Sendable, Equatable {
        public let sidecarId: String
        public let displayName: String
        public let cronExpression: String
        public let prompt: String
        public let humanScheduleLabel: String

        public init(
            sidecarId: String,
            displayName: String,
            cronExpression: String,
            prompt: String,
            humanScheduleLabel: String
        ) {
            self.sidecarId = sidecarId
            self.displayName = displayName
            self.cronExpression = cronExpression
            self.prompt = prompt
            self.humanScheduleLabel = humanScheduleLabel
        }
    }

    /// Generates a filesystem-safe kebab-case sidecar directory ID for `~/.gemini/config/sidecars/<id>/`.
    public static func makeSidecarId(from rawTitle: String, suffix: String? = nil) -> String {
        let lower = rawTitle.lowercased()
        var parts: [String] = []
        var current = ""
        for scalar in lower.unicodeScalars {
            if (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                parts.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            parts.append(current)
        }
        let joined = parts.prefix(5).joined(separator: "-")
        let shortSuffix = suffix ?? String(UUID().uuidString.prefix(6)).lowercased()
        if joined.isEmpty {
            return "auto-\(shortSuffix)"
        }
        let clipped = String(joined.prefix(36)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(clipped)-\(shortSuffix)"
    }

    /// Builds official Antigravity 2.0 `builtin: "schedule"` sidecar `args` array:
    /// `["CRON_TZ=<IANA> <min hour dom mon dow>", "agentapi", "new-conversation", ...flags, "--", "<prompt>"]`.
    public static func buildScheduleArgs(
        cron: String,
        prompt: String,
        modelArg: String? = nil
    ) -> [String] {
        var args: [String] = [cron.trimmingCharacters(in: .whitespacesAndNewlines), "agentapi", "new-conversation"]
        if let modelArg = modelArg?.trimmingCharacters(in: .whitespacesAndNewlines), !modelArg.isEmpty {
            args.append("--model=\(modelArg)")
        }
        args.append("--")
        args.append(prompt.trimmingCharacters(in: .whitespacesAndNewlines))
        return args
    }

    /// Extracts `(cron, prompt, modelLabel)` from both modern (`--` separated) and legacy positional
    /// Antigravity `schedule` sidecar `args`.
    public static func parseScheduleArgs(_ args: [String]) -> (cron: String, prompt: String, modelLabel: String?) {
        guard !args.isEmpty else { return ("", "", nil) }
        let cron = args[0].trimmingCharacters(in: .whitespacesAndNewlines)
        var modelLabel: String? = nil
        var prompt = ""

        if let dashIndex = args.firstIndex(of: "--"), dashIndex + 1 < args.count {
            prompt = args[(dashIndex + 1)...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            for idx in 1..<dashIndex {
                if let m = extractModelLabel(fromArg: args[idx], nextArg: (idx + 1 < dashIndex) ? args[idx + 1] : nil) {
                    modelLabel = m
                }
            }
        } else if args.count >= 4 {
            var i = 1
            if i < args.count && args[i] == "agentapi" { i += 1 }
            if i < args.count && args[i] == "new-conversation" { i += 1 }
            var positional: [String] = []
            while i < args.count {
                let token = args[i]
                if token.hasPrefix("--model=") {
                    modelLabel = formatModelBadge(String(token.dropFirst("--model=".count)))
                    i += 1
                } else if token == "--model", i + 1 < args.count {
                    modelLabel = formatModelBadge(args[i + 1])
                    i += 2
                } else if token.hasPrefix("--title=") {
                    i += 1
                } else if token == "--title", i + 1 < args.count {
                    i += 2
                } else if token.hasPrefix("--") {
                    i += 1
                } else {
                    positional.append(token)
                    i += 1
                }
            }
            prompt = positional.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (cron, prompt, modelLabel)
    }

    private static func extractModelLabel(fromArg arg: String, nextArg: String?) -> String? {
        if arg.hasPrefix("--model=") {
            return formatModelBadge(String(arg.dropFirst("--model=".count)))
        }
        if arg == "--model", let nextArg, !nextArg.isEmpty {
            return formatModelBadge(nextArg)
        }
        return nil
    }

    public static func formatModelBadge(_ raw: String) -> String {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return "Flash" }
        if lower.contains("flash-lite") || lower.contains("flash_lite") || lower.contains("flash lite") {
            return "Flash Lite"
        }
        if lower.contains("flash") { return "Flash" }
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("pro") { return "Pro" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips optional `CRON_TZ=<IANA>` / `TZ=<IANA>` prefix and returns `(timeZone, fiveFieldCron)`.
    public static func splitCronAndTimeZone(_ raw: String) -> (timeZone: TimeZone, cron: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return (TimeZone.current, "") }
        var tz = TimeZone.current
        var startIdx = 0
        if tokens[0].hasPrefix("CRON_TZ=") {
            let tzId = String(tokens[0].dropFirst("CRON_TZ=".count))
            if let parsed = TimeZone(identifier: tzId) {
                tz = parsed
            }
            startIdx = 1
        } else if tokens[0].hasPrefix("TZ=") {
            let tzId = String(tokens[0].dropFirst("TZ=".count))
            if let parsed = TimeZone(identifier: tzId) {
                tz = parsed
            }
            startIdx = 1
        }
        let expr = tokens[startIdx...].joined(separator: " ")
        return (tz, expr)
    }

    /// Formats a 5-field cron expression (with optional `CRON_TZ=`) into concise UE06 cadence text
    /// such as `"Daily at 02:00"`, `"Weekdays at 09:00"`, `"Mondays at 09:00"`, or `"Hourly"`.
    public static func humanReadableSchedule(from rawCron: String) -> String {
        let (_, expr) = splitCronAndTimeZone(rawCron)
        let fields = expr.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count == 5 else {
            return expr.isEmpty ? "Custom schedule" : expr
        }
        let minF = fields[0]
        let hourF = fields[1]
        let domF = fields[2]
        let monF = fields[3]
        let dowF = fields[4]

        if minF.hasPrefix("*/"), hourF == "*", domF == "*", monF == "*", dowF == "*" {
            let step = String(minF.dropFirst(2))
            return "Every \(step)m"
        }
        if hourF == "*", domF == "*", monF == "*", dowF == "*" {
            if minF == "0" || minF == "00" { return "Hourly" }
            if let m = Int(minF) { return String(format: "Hourly at :%02d", m) }
            return "Hourly"
        }
        if hourF.hasPrefix("*/"), domF == "*", monF == "*", dowF == "*" {
            let step = String(hourF.dropFirst(2))
            return "Every \(step)h"
        }

        if let m = Int(minF), let h = Int(hourF), domF == "*", monF == "*" {
            let timeStr = String(format: "%02d:%02d", h, m)
            switch dowF {
            case "*":
                return "Daily at \(timeStr)"
            case "1-5", "MON-FRI", "mon-fri":
                return "Weekdays at \(timeStr)"
            case "0,6", "6,0", "6-7", "SAT,SUN":
                return "Weekends at \(timeStr)"
            case "0", "7", "SUN", "sun":
                return "Sundays at \(timeStr)"
            case "1", "MON", "mon":
                return "Mondays at \(timeStr)"
            case "2", "TUE", "tue":
                return "Tuesdays at \(timeStr)"
            case "3", "WED", "wed":
                return "Wednesdays at \(timeStr)"
            case "4", "THU", "thu":
                return "Thursdays at \(timeStr)"
            case "5", "FRI", "fri":
                return "Fridays at \(timeStr)"
            case "6", "SAT", "sat":
                return "Saturdays at \(timeStr)"
            default:
                return "\(dowF) at \(timeStr)"
            }
        }
        return expr
    }

    /// Computes the next matching firing `Date` for a standard 5-field cron expression.
    public static func nextFireDate(from rawCron: String, after now: Date = Date()) -> Date? {
        let (tz, expr) = splitCronAndTimeZone(rawCron)
        let fields = expr.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count == 5 else { return nil }

        guard let minutes = parseCronField(fields[0], min: 0, max: 59),
              let hours = parseCronField(fields[1], min: 0, max: 23),
              let doms = parseCronField(fields[2], min: 1, max: 31),
              let months = parseCronField(fields[3], min: 1, max: 12),
              let dows = parseCronWeekdayField(fields[4]) else {
            return nil
        }

        let domWildcard = (fields[2] == "*")
        let dowWildcard = (fields[4] == "*")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        // Advance to next whole minute after `now`
        guard let start = cal.date(byAdding: .minute, value: 1, to: now) else { return nil }
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        comps.second = 0
        guard var cursor = cal.date(from: comps) else { return nil }

        // Scan up to 370 days ahead (jumping by day/hour when non-matching for O(1) fast execution)
        let maxIterations = 60 * 24 * 32
        var steps = 0
        while steps < maxIterations {
            steps += 1
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: cursor)
            guard let mon = c.month, let day = c.day, let hr = c.hour, let min = c.minute, let wd = c.weekday else {
                return nil
            }
            if !months.contains(mon) {
                guard let nextMonth = cal.date(byAdding: .month, value: 1, to: cursor) else { return nil }
                var reset = cal.dateComponents([.year, .month], from: nextMonth)
                reset.day = 1; reset.hour = 0; reset.minute = 0; reset.second = 0
                guard let advanced = cal.date(from: reset) else { return nil }
                cursor = advanced
                continue
            }
            // Convert Gregorian weekday (1=Sun..7=Sat) to cron (0=Sun..6=Sat)
            let cronDow = (wd - 1) % 7
            let dayMatches: Bool = {
                if domWildcard && dowWildcard { return true }
                if domWildcard { return dows.contains(cronDow) }
                if dowWildcard { return doms.contains(day) }
                return doms.contains(day) || dows.contains(cronDow)
            }()
            if !dayMatches {
                guard let nextDay = cal.date(byAdding: .day, value: 1, to: cursor) else { return nil }
                var reset = cal.dateComponents([.year, .month, .day], from: nextDay)
                reset.hour = 0; reset.minute = 0; reset.second = 0
                guard let advanced = cal.date(from: reset) else { return nil }
                cursor = advanced
                continue
            }
            if !hours.contains(hr) {
                guard let nextHour = cal.date(byAdding: .hour, value: 1, to: cursor) else { return nil }
                var reset = cal.dateComponents([.year, .month, .day, .hour], from: nextHour)
                reset.minute = 0; reset.second = 0
                guard let advanced = cal.date(from: reset) else { return nil }
                cursor = advanced
                continue
            }
            if minutes.contains(min) {
                return cursor
            }
            guard let nextMin = cal.date(byAdding: .minute, value: 1, to: cursor) else { return nil }
            cursor = nextMin
        }
        return nil
    }

    /// Formats the next fire date into concise UE06 `NEXT RUN` display copy
    /// (`"Today, 14:00"`, `"Tonight, 22:00"`, `"Tomorrow, 09:00"`, `"Mon, 09:00"`).
    public static func nextFireDescription(from rawCron: String, after now: Date = Date()) -> String {
        guard let next = nextFireDate(from: rawCron, after: now) else {
            return humanReadableSchedule(from: rawCron)
        }
        let deltaSec = next.timeIntervalSince(now)
        if deltaSec > 0 && deltaSec < 3600 {
            let mins = max(1, Int(ceil(deltaSec / 60.0)))
            return "In \(mins)m"
        }

        let cal = Calendar.current
        let timeComps = cal.dateComponents([.hour, .minute], from: next)
        let hh = timeComps.hour ?? 0
        let mm = timeComps.minute ?? 0
        let hm = String(format: "%02d:%02d", hh, mm)

        if cal.isDate(next, inSameDayAs: now) {
            return (hh >= 19 || hh < 5) ? "Tonight, \(hm)" : "Today, \(hm)"
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
           cal.isDate(next, inSameDayAs: tomorrow) {
            return (hh < 5) ? "Tonight, \(hm)" : "Tomorrow, \(hm)"
        }
        let weekdayIdx = (cal.component(.weekday, from: next) - 1) % 7
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return "\(names[weekdayIdx]), \(hm)"
    }

    /// Formats a millisecond Unix timestamp into concise relative age (`"just now"`, `"14m ago"`, `"22h ago"`, `"2d"`).
    public static func relativeTimeLabel(from timestampMs: Int64, now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
        let delta = max(0, Int(now.timeIntervalSince(date)))
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(delta / 60)m ago" }
        if delta < 86_400 { return "\(delta / 3600)h ago" }
        return "\(delta / 86_400)d ago"
    }

    /// Parses natural-language English or Chinese schedule input into a native `CRON_TZ` schedule + title + prompt.
    public static func parseNaturalLanguagePrompt(
        _ rawInput: String,
        timeZoneId: String = TimeZone.current.identifier
    ) -> ParsedNaturalSchedule {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Detect time of day (hour + minute)
        var hour = 9
        var minute = 0
        var detectedTime = false

        // Match HH:MM (with optional am/pm)
        if let match = firstRegexMatch(in: lower, pattern: #"(?:at\s+)?(\d{1,2}):(\d{2})\s*(am|pm)?"#),
           match.count >= 3,
           var h = Int(match[1]),
           let m = Int(match[2]),
           h <= 23, m <= 59 {
            let ampm = match.count > 3 ? match[3] : ""
            if ampm == "pm" && h < 12 { h += 12 }
            if ampm == "am" && h == 12 { h = 0 }
            hour = h
            minute = m
            detectedTime = true
        } else if let match = firstRegexMatch(in: lower, pattern: #"(?:at\s+)(\d{1,2})\s*(am|pm)?\b"#),
                  match.count >= 2,
                  var h = Int(match[1]),
                  h <= 23 {
            let ampm = match.count > 2 ? match[2] : ""
            if ampm == "pm" && h < 12 { h += 12 }
            if ampm == "am" && h == 12 { h = 0 }
            hour = h
            minute = 0
            detectedTime = true
        } else if let match = firstRegexMatch(in: lower, pattern: #"\b(\d{1,2})\s*(am|pm)\b"#),
                  match.count >= 3,
                  var h = Int(match[1]),
                  h <= 12 {
            if match[2] == "pm" && h < 12 { h += 12 }
            if match[2] == "am" && h == 12 { h = 0 }
            hour = h
            minute = 0
            detectedTime = true
        } else if let match = firstRegexMatch(in: trimmed, pattern: #"(早上|上午|中午|下午|晚上|凌晨)?\s*(\d{1,2})\s*[点时](?:(\d{1,2})\s*分?|半)?"#),
                  match.count >= 3,
                  var h = Int(match[2]),
                  h <= 23 {
            let period = match[1]
            if (period == "下午" || period == "晚上") && h < 12 { h += 12 }
            if period == "凌晨" && h == 12 { h = 0 }
            var m = 0
            if match[0].contains("半") {
                m = 30
            } else if match.count >= 4, let parsedM = Int(match[3]), parsedM <= 59 {
                m = parsedM
            }
            hour = h
            minute = m
            detectedTime = true
        }

        if !detectedTime {
            if lower.contains("nightly") || lower.contains("midnight") || lower.contains("every night") || trimmed.contains("每晚") || trimmed.contains("凌晨") {
                hour = 2
                minute = 0
            } else if lower.contains("evening") || trimmed.contains("傍晚") {
                hour = 18
                minute = 0
            }
        }

        // 2. Detect cadence / weekday
        let cronFiveField: String
        if let minStepMatch = firstRegexMatch(in: lower, pattern: #"every\s+(\d{1,2})\s*(?:min|mins|minute|minutes)"#),
           minStepMatch.count >= 2, let step = Int(minStepMatch[1]), step >= 1, step <= 59 {
            cronFiveField = "*/\(step) * * * *"
        } else if let zhMinMatch = firstRegexMatch(in: trimmed, pattern: #"每\s*(\d{1,2})\s*分钟"#),
                  zhMinMatch.count >= 2, let step = Int(zhMinMatch[1]), step >= 1, step <= 59 {
            cronFiveField = "*/\(step) * * * *"
        } else if lower.contains("hourly") || lower.contains("every hour") || trimmed.contains("每小时") {
            cronFiveField = "\(minute) * * * *"
        } else if let hourStepMatch = firstRegexMatch(in: lower, pattern: #"every\s+(\d{1,2})\s*(?:h|hr|hrs|hour|hours)"#),
                  hourStepMatch.count >= 2, let step = Int(hourStepMatch[1]), step >= 1, step <= 23 {
            cronFiveField = "\(minute) */\(step) * * *"
        } else if lower.contains("weekday") || lower.contains("mon-fri") || trimmed.contains("工作日") {
            cronFiveField = "\(minute) \(hour) * * 1-5"
        } else if lower.contains("weekend") || trimmed.contains("周末") {
            cronFiveField = "\(minute) \(hour) * * 0,6"
        } else if lower.contains("monday") || trimmed.contains("周一") || trimmed.contains("星期一") {
            cronFiveField = "\(minute) \(hour) * * 1"
        } else if lower.contains("tuesday") || trimmed.contains("周二") || trimmed.contains("星期二") {
            cronFiveField = "\(minute) \(hour) * * 2"
        } else if lower.contains("wednesday") || trimmed.contains("周三") || trimmed.contains("星期三") {
            cronFiveField = "\(minute) \(hour) * * 3"
        } else if lower.contains("thursday") || trimmed.contains("周四") || trimmed.contains("星期四") {
            cronFiveField = "\(minute) \(hour) * * 4"
        } else if lower.contains("friday") || trimmed.contains("周五") || trimmed.contains("星期五") {
            cronFiveField = "\(minute) \(hour) * * 5"
        } else if lower.contains("saturday") || trimmed.contains("周六") || trimmed.contains("星期六") {
            cronFiveField = "\(minute) \(hour) * * 6"
        } else if lower.contains("sunday") || trimmed.contains("周日") || trimmed.contains("星期日") || trimmed.contains("星期天") {
            cronFiveField = "\(minute) \(hour) * * 0"
        } else {
            cronFiveField = "\(minute) \(hour) * * *"
        }

        let cronExpr = "CRON_TZ=\(timeZoneId) \(cronFiveField)"
        let title = trimmed.isEmpty ? "Scheduled Automation" : String(trimmed.prefix(64))
        let sidecarId = makeSidecarId(from: title)
        let human = humanReadableSchedule(from: cronExpr)
        return ParsedNaturalSchedule(
            sidecarId: sidecarId,
            displayName: title,
            cronExpression: cronExpr,
            prompt: trimmed.isEmpty ? title : trimmed,
            humanScheduleLabel: human
        )
    }

    private static func firstRegexMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else { return nil }
        var groups: [String] = []
        for idx in 0..<match.numberOfRanges {
            let r = match.range(at: idx)
            if r.location != NSNotFound, let swiftRange = Range(r, in: text) {
                groups.append(String(text[swiftRange]))
            } else {
                groups.append("")
            }
        }
        return groups
    }

    private static func parseCronWeekdayField(_ field: String) -> Set<Int>? {
        let mapped = field
            .uppercased()
            .replacingOccurrences(of: "SUN", with: "0")
            .replacingOccurrences(of: "MON", with: "1")
            .replacingOccurrences(of: "TUE", with: "2")
            .replacingOccurrences(of: "WED", with: "3")
            .replacingOccurrences(of: "THU", with: "4")
            .replacingOccurrences(of: "FRI", with: "5")
            .replacingOccurrences(of: "SAT", with: "6")
        guard let raw = parseCronField(mapped, min: 0, max: 7) else { return nil }
        var normalized = Set<Int>()
        for v in raw {
            normalized.insert(v == 7 ? 0 : v)
        }
        return normalized
    }

    private static func parseCronField(_ field: String, min: Int, max: Int) -> Set<Int>? {
        var out = Set<Int>()
        for part in field.split(separator: ",") {
            let token = String(part)
            let stepParts = token.split(separator: "/", maxSplits: 1).map(String.init)
            let rangeSpec = stepParts[0]
            let step: Int = {
                if stepParts.count == 2, let s = Int(stepParts[1]), s > 0 { return s }
                return 1
            }()

            if rangeSpec == "*" {
                var v = min
                while v <= max {
                    out.insert(v)
                    v += step
                }
            } else if rangeSpec.contains("-") {
                let bounds = rangeSpec.split(separator: "-", maxSplits: 1).map(String.init)
                guard bounds.count == 2,
                      let lo = Int(bounds[0]),
                      let hi = Int(bounds[1]),
                      lo >= min, hi <= max, lo <= hi else {
                    return nil
                }
                var v = lo
                while v <= hi {
                    out.insert(v)
                    v += step
                }
            } else if let exact = Int(rangeSpec), exact >= min, exact <= max {
                if stepParts.count == 2 {
                    var v = exact
                    while v <= max {
                        out.insert(v)
                        v += step
                    }
                } else {
                    out.insert(exact)
                }
            } else {
                return nil
            }
        }
        return out.isEmpty ? nil : out
    }
}

// MARK: - Add Context Sheet Models (UE08)

/// Category tiles at the top of `AddContextSheetView` (`UE08`).
public enum ContextCategory: String, ResilientStringEnum, CaseIterable, Identifiable {
    case files = "Files"
    case folder = "Folder"
    case mentions = "Mentions"
    case actions = "Actions"
    case skills = "Skills"
    case drive = "Drive"

    public var id: String { rawValue }
    public static var unknownFallback: ContextCategory { .files }
}

/// Selectable file, folder, mention, action, or skill item in `AddContextSheetView` (`UE08`).
public struct ContextCandidateItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var category: ContextCategory
    public var title: String
    public var subtitle: String
    public var chipLabel: String
    public var isActionTrigger: Bool
    public var isSelected: Bool

    public init(
        id: String,
        category: ContextCategory,
        title: String,
        subtitle: String,
        chipLabel: String,
        isActionTrigger: Bool = false,
        isSelected: Bool = false
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.chipLabel = chipLabel
        self.isActionTrigger = isActionTrigger
        self.isSelected = isSelected
    }

    public var attachmentKind: ComposerAttachmentChip.Kind {
        switch category {
        case .files: return .fileMention
        case .folder: return .folder
        case .mentions:
            return title.lowercased().contains("terminal") ? .terminalLog : .conversationMention
        case .actions: return .action
        case .skills: return .skill
        case .drive: return .folder
        }
    }
}
