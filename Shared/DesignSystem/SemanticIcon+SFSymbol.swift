import AntigravityData

/// Maps platform-neutral `AntigravityData.SemanticIcon` identifiers to iOS SF Symbol names.
public extension SemanticIcon {
    var sfSymbolName: String {
        switch self {
        // Markdown Alert Callouts
        case .alertInfo: return "info.circle.fill"
        case .alertTip: return "lightbulb.fill"
        case .alertImportant: return "exclamationmark.bubble.fill"
        case .alertWarning: return "exclamationmark.triangle.fill"
        case .alertCaution: return "flame.fill"

        // Markdown Embed Kinds
        case .embedHtmlWidget: return "sparkles.rectangle.stack"
        case .embedImage: return "photo"
        case .embedSvg: return "point.3.connected.trianglepath.dotted"
        case .embedMarkdown: return "doc.richtext"
        case .embedWebLink: return "globe"
        case .embedSidecar: return "puzzlepiece.extension"
        case .embedArtifact: return "doc.badge.gearshape"

        // Permission Presets
        case .permissionReview: return "eye"
        case .permissionSandbox: return "lock"
        case .permissionAuto: return "checkmark.shield"
        case .permissionTurbo: return "exclamationmark.shield"
        case .permissionInheritGlobal: return "slider.horizontal.3"

        // Slash Commands
        case .commandPlan: return "doc.text.magnifyingglass"
        case .commandGrillMe: return "questionmark.bubble.fill"
        case .commandGoal: return "flag.checkered.2.crossed"
        case .commandBoost: return "bolt.fill"
        case .commandSwarm: return "hexagon.fill"
        case .commandTeamwork: return "person.3.sequence.fill"
        case .commandWorkflow: return "flowchart.fill"
        case .commandSideQuestion: return "bubble.left.and.text.bubble.right.fill"
        case .commandSchedule: return "clock.badge.checkmark"
        case .commandBrowser: return "safari.fill"
        case .commandLearn: return "sparkles"
        case .commandCustomizations: return "slider.horizontal.3"
        case .commandGuide: return "book.fill"
        case .commandAutomation: return "clock.arrow.circlepath"
        case .commandGenerativeUI: return "wand.and.stars"
        case .commandVoice: return "waveform.circle"
        case .commandCustomSkill: return "cube"
        }
    }
}
