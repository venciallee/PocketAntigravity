package dev.antigravity.shared.markdown

import dev.antigravity.shared.model.SemanticIcon

public enum class MarkdownAlertKind(
    public val tag: String,
    public val displayTitle: String,
    public val semanticIcon: SemanticIcon,
) {
    NOTE("NOTE", "Note", SemanticIcon.ALERT_INFO),
    TIP("TIP", "Tip", SemanticIcon.ALERT_TIP),
    IMPORTANT("IMPORTANT", "Important", SemanticIcon.ALERT_IMPORTANT),
    WARNING("WARNING", "Warning", SemanticIcon.ALERT_WARNING),
    CAUTION("CAUTION", "Caution", SemanticIcon.ALERT_CAUTION);

    public companion object {
        public fun fromTag(raw: String): MarkdownAlertKind? =
            entries.firstOrNull { it.tag.equals(raw.trim(), ignoreCase = true) }
    }
}

public sealed interface MarkdownListMarker {
    public data object Bullet : MarkdownListMarker
    public data class Ordered(public val number: Int) : MarkdownListMarker
    public data class Task(public val checked: Boolean) : MarkdownListMarker
}

public enum class MarkdownTableAlignment {
    LEADING,
    CENTER,
    TRAILING,
}

public enum class MarkdownEmbedKind(
    public val displayBadge: String,
    public val semanticIcon: SemanticIcon,
) {
    HTML_WIDGET("Interactive Widget", SemanticIcon.EMBED_HTML_WIDGET),
    IMAGE("Image", SemanticIcon.EMBED_IMAGE),
    SVG("SVG Graphic", SemanticIcon.EMBED_SVG),
    MARKDOWN("Document", SemanticIcon.EMBED_MARKDOWN),
    WEB_URL("Web Preview", SemanticIcon.EMBED_WEB_LINK),
    SIDECAR("UI Extension", SemanticIcon.EMBED_SIDECAR),
    GENERIC("Artifact Embed", SemanticIcon.EMBED_ARTIFACT);

    public companion object {
        public fun detect(rawSrc: String): MarkdownEmbedKind {
            val lower = rawSrc.trim().lowercase()
            if (lower.startsWith("sidecar://")) return SIDECAR
            val pathNoFragment = lower.substringBefore('#')
            val pathNoQuery = pathNoFragment.substringBefore('?')
            return when {
                pathNoQuery.endsWith(".html") || pathNoQuery.endsWith(".htm") -> HTML_WIDGET
                pathNoQuery.endsWith(".svg") -> SVG
                pathNoQuery.endsWith(".png") || pathNoQuery.endsWith(".jpg") ||
                    pathNoQuery.endsWith(".jpeg") || pathNoQuery.endsWith(".webp") ||
                    pathNoQuery.endsWith(".gif") || pathNoQuery.endsWith(".heic") ||
                    lower.startsWith("data:image/") -> IMAGE
                pathNoQuery.endsWith(".md") || pathNoQuery.endsWith(".markdown") -> MARKDOWN
                lower.startsWith("https://") || lower.startsWith("http://") -> WEB_URL
                else -> GENERIC
            }
        }
    }
}

public data class MarkdownFootnoteItem(
    public val label: String,
    public val inlines: List<MarkdownInline>,
) {
    public val id: String get() = label
}

public data class MarkdownFrontmatterEntry(
    public val key: String,
    public val value: String,
) {
    public val id: String get() = key
}

public sealed interface MarkdownInline {
    public val plainText: String

    public data class Text(public val value: String) : MarkdownInline {
        override val plainText: String get() = value
    }

    public data object SoftBreak : MarkdownInline {
        override val plainText: String get() = "\n"
    }

    public data class Code(public val value: String) : MarkdownInline {
        override val plainText: String get() = value
    }

    public data class Strong(public val children: List<MarkdownInline>) : MarkdownInline {
        override val plainText: String get() = children.joinToString("") { it.plainText }
    }

    public data class Emphasis(public val children: List<MarkdownInline>) : MarkdownInline {
        override val plainText: String get() = children.joinToString("") { it.plainText }
    }

    public data class Strikethrough(public val children: List<MarkdownInline>) : MarkdownInline {
        override val plainText: String get() = children.joinToString("") { it.plainText }
    }

    public data class Underline(public val children: List<MarkdownInline>) : MarkdownInline {
        override val plainText: String get() = children.joinToString("") { it.plainText }
    }

    public data class Highlight(public val children: List<MarkdownInline>) : MarkdownInline {
        override val plainText: String get() = children.joinToString("") { it.plainText }
    }

    public data class Superscript(public val value: String) : MarkdownInline {
        override val plainText: String get() = value
    }

    public data class SubscriptText(public val value: String) : MarkdownInline {
        override val plainText: String get() = value
    }

    public data class KeyboardKey(public val value: String) : MarkdownInline {
        override val plainText: String get() = value
    }

    public data class Link(
        public val label: List<MarkdownInline>,
        public val destination: String,
    ) : MarkdownInline {
        override val plainText: String get() = label.joinToString("") { it.plainText }
    }

    public data class InlineMath(public val latex: String) : MarkdownInline {
        override val plainText: String get() = latex
    }

    public data class InlineImage(
        public val alt: String,
        public val src: String,
    ) : MarkdownInline {
        override val plainText: String get() = alt.ifEmpty { src }
    }

    public data class FootnoteRef(public val label: String) : MarkdownInline {
        override val plainText: String get() = "[$label]"
    }
}

public sealed interface MarkdownBlock {
    public val id: Int

    public data class Frontmatter(
        override val id: Int,
        public val entries: List<MarkdownFrontmatterEntry>,
    ) : MarkdownBlock

    public data class Heading(
        override val id: Int,
        public val level: Int,
        public val inlines: List<MarkdownInline>,
    ) : MarkdownBlock

    public data class Paragraph(
        override val id: Int,
        public val inlines: List<MarkdownInline>,
    ) : MarkdownBlock

    public data class CodeBlock(
        override val id: Int,
        public val language: String?,
        public val code: String,
    ) : MarkdownBlock

    public data class ListItem(
        override val id: Int,
        public val indentLevel: Int,
        public val marker: MarkdownListMarker,
        public val inlines: List<MarkdownInline>,
    ) : MarkdownBlock

    public data class Blockquote(
        override val id: Int,
        public val alert: MarkdownAlertKind?,
        public val blocks: List<MarkdownBlock>,
    ) : MarkdownBlock

    public data class Table(
        override val id: Int,
        public val headers: List<List<MarkdownInline>>,
        public val alignments: List<MarkdownTableAlignment>,
        public val rows: List<List<List<MarkdownInline>>>,
    ) : MarkdownBlock

    public data class ThematicBreak(
        override val id: Int,
    ) : MarkdownBlock

    public data class MathBlock(
        override val id: Int,
        public val latex: String,
    ) : MarkdownBlock

    public data class AgentEmbed(
        override val id: Int,
        public val src: String,
        public val title: String?,
        public val kind: MarkdownEmbedKind,
        public val attributes: Map<String, String>,
        public val isStreamingIncomplete: Boolean,
    ) : MarkdownBlock

    public data class PluginCard(
        override val id: Int,
        public val catalogId: String,
        public val title: String?,
    ) : MarkdownBlock

    public data class Image(
        override val id: Int,
        public val alt: String,
        public val src: String,
        public val title: String?,
    ) : MarkdownBlock

    public data class Details(
        override val id: Int,
        public val summary: List<MarkdownInline>,
        public val blocks: List<MarkdownBlock>,
        public val isOpenByDefault: Boolean,
    ) : MarkdownBlock

    public data class Carousel(
        override val id: Int,
        public val slides: List<List<MarkdownBlock>>,
    ) : MarkdownBlock

    public data class Mermaid(
        override val id: Int,
        public val source: String,
    ) : MarkdownBlock

    public data class FootnoteSection(
        override val id: Int,
        public val items: List<MarkdownFootnoteItem>,
    ) : MarkdownBlock

    public val isMermaidDiagram: Boolean
        get() = this is Mermaid || (this is CodeBlock && language?.lowercase() == "mermaid")

    public val isSvgDiagram: Boolean
        get() = this is CodeBlock && (
            language?.lowercase() == "svg" ||
                (language?.lowercase() == "xml" && code.contains("<svg"))
            )
}
