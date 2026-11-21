import Foundation

/// Platform-neutral semantic icon identifier shared across domain models.
///
/// Each native UI layer maps `SemanticIcon` to its platform iconography:
/// - iOS: SF Symbols (`Shared/DesignSystem/SemanticIcon+SFSymbol.swift`)
/// - Android (KMP Phase 1+): Material Symbols / Compose vector icons
public enum SemanticIcon: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    // Markdown Alert Callouts
    case alertInfo
    case alertTip
    case alertImportant
    case alertWarning
    case alertCaution

    // Markdown Embed Kinds
    case embedHtmlWidget
    case embedImage
    case embedSvg
    case embedMarkdown
    case embedWebLink
    case embedSidecar
    case embedArtifact

    // Permission Presets
    case permissionReview
    case permissionSandbox
    case permissionAuto
    case permissionTurbo
    case permissionInheritGlobal

    // Slash Commands
    case commandPlan
    case commandGrillMe
    case commandGoal
    case commandBoost
    case commandSwarm
    case commandTeamwork
    case commandWorkflow
    case commandSideQuestion
    case commandSchedule
    case commandBrowser
    case commandLearn
    case commandCustomizations
    case commandGuide
    case commandAutomation
    case commandGenerativeUI
    case commandVoice
    case commandCustomSkill
}
