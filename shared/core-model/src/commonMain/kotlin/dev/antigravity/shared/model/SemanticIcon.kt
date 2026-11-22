package dev.antigravity.shared.model

import kotlinx.serialization.Serializable

/**
 * Platform-neutral semantic icon identifier shared across domain models.
 *
 * Each native UI layer maps [SemanticIcon] to its platform iconography:
 * - iOS: SF Symbols (`Shared/DesignSystem/SemanticIcon+SFSymbol.swift`)
 * - Android: Material Symbols / Compose vector icons
 */
@Serializable(with = SemanticIconSerializer::class)
public enum class SemanticIcon {
    // Markdown Alert Callouts
    ALERT_INFO,
    ALERT_TIP,
    ALERT_IMPORTANT,
    ALERT_WARNING,
    ALERT_CAUTION,

    // Markdown Embed Kinds
    EMBED_HTML_WIDGET,
    EMBED_IMAGE,
    EMBED_SVG,
    EMBED_MARKDOWN,
    EMBED_WEB_LINK,
    EMBED_SIDECAR,
    EMBED_ARTIFACT,

    // Permission Presets
    PERMISSION_REVIEW,
    PERMISSION_SANDBOX,
    PERMISSION_AUTO,
    PERMISSION_TURBO,
    PERMISSION_INHERIT_GLOBAL,

    // Slash Commands
    COMMAND_PLAN,
    COMMAND_GRILL_ME,
    COMMAND_GOAL,
    COMMAND_BOOST,
    COMMAND_SWARM,
    COMMAND_TEAMWORK,
    COMMAND_WORKFLOW,
    COMMAND_SIDE_QUESTION,
    COMMAND_SCHEDULE,
    COMMAND_BROWSER,
    COMMAND_LEARN,
    COMMAND_CUSTOMIZATIONS,
    COMMAND_GUIDE,
    COMMAND_AUTOMATION,
    COMMAND_GENERATIVE_UI,
    COMMAND_VOICE,
    COMMAND_CUSTOM_SKILL,
}

public object SemanticIconSerializer : ResilientEnumSerializer<SemanticIcon>(
    serialName = "dev.antigravity.shared.model.SemanticIcon",
    entriesProvider = { SemanticIcon.entries },
    fallbackProvider = { SemanticIcon.EMBED_ARTIFACT },
)
