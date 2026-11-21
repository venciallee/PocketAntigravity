import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Carousel Card (` ````carousel ... <!-- slide --> ... ```` `)

internal struct MarkdownCarouselCardView: View {
    let slides: [[MarkdownBlock]]
    let variant: MarkdownRenderVariant
    let store: AntigravitySessionStore?
    @State private var activeIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StepCardPalette.periwinkle)
                Text("Carousel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkLabel)
                Spacer()
                Text("\(min(activeIndex + 1, max(1, slides.count))) / \(slides.count)")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.03))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            if !slides.isEmpty {
                let safeIdx = min(max(0, activeIndex), slides.count - 1)
                AnyView(AntigravityMarkdownBlocksView(blocks: slides[safeIdx], variant: variant, store: store))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if slides.count > 1 {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                activeIndex = max(0, activeIndex - 1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(activeIndex > 0 ? StepCardPalette.periwinkle : AntigravityTheme.inkSecondary.opacity(0.4))
                                .frame(width: 30, height: 28)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(activeIndex == 0)

                        Spacer()

                        HStack(spacing: 5) {
                            ForEach(0..<slides.count, id: \.self) { idx in
                                Circle()
                                    .fill(idx == activeIndex ? StepCardPalette.periwinkle : Color.white.opacity(0.22))
                                    .frame(width: idx == activeIndex ? 7 : 5, height: idx == activeIndex ? 7 : 5)
                            }
                        }

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                activeIndex = min(slides.count - 1, activeIndex + 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(activeIndex + 1 < slides.count ? StepCardPalette.periwinkle : AntigravityTheme.inkSecondary.opacity(0.4))
                                .frame(width: 30, height: 28)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(activeIndex + 1 >= slides.count)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
        }
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Collapsible `<details>` Disclosure Card

internal struct MarkdownDetailsCardView: View {
    let summary: [MarkdownInline]
    let innerBlocks: [MarkdownBlock]
    let store: AntigravitySessionStore?
    @State private var isExpanded: Bool

    init(
        summary: [MarkdownInline],
        innerBlocks: [MarkdownBlock],
        isOpenByDefault: Bool,
        store: AntigravitySessionStore?
    ) {
        self.summary = summary
        self.innerBlocks = innerBlocks
        self.store = store
        self._isExpanded = State(initialValue: isOpenByDefault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(StepCardPalette.periwinkle)
                        .frame(width: 14)
                    Text(
                        MarkdownInlineBuilder.build(
                            summary,
                            baseSize: 14.0,
                            baseWeight: .semibold,
                            defaultColor: AntigravityTheme.inkReading
                        )
                    )
                    .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !innerBlocks.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)

                AnyView(AntigravityMarkdownBlocksView(blocks: innerBlocks, variant: .blockquote, store: store))
                    .padding(12)
            }
        }
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - `<plugin-card>` Connection Card

internal struct MarkdownPluginCardView: View {
    let catalogId: String
    let explicitTitle: String?

    private var displayTitle: String {
        if let explicitTitle, !explicitTitle.isEmpty { return explicitTitle }
        return catalogId
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(StepCardPalette.softViolet.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(StepCardPalette.softViolet)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(AntigravityTheme.inkReading)
                Text("Plugin · Connect in Antigravity Customizations")
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            }

            Spacer()
        }
        .padding(12)
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(StepCardPalette.softViolet.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Standalone Image Block (`![alt](url)` & `<img src="..." />`)

internal struct MarkdownImageBlockView: View {
    let alt: String
    let src: String
    let title: String?
    let store: AntigravitySessionStore?

    @State private var resolved: ResolvedEmbedResource? = nil
    @State private var isLoading: Bool = false
    @State private var showFullScreen: Bool = false

    private var captionText: String {
        let primary = !alt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? alt
            : (title ?? MarkdownLinkFormatting.shortFileBadge(src))
        return primary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let lower = src.lowercased()
        VStack(alignment: .leading, spacing: 6) {
            if lower.hasPrefix("https://") || lower.hasPrefix("http://"), let url = URL(string: src) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        fallbackImageCard
                    case .empty:
                        HStack(spacing: 8) {
                            ProgressView().tint(StepCardPalette.periwinkle)
                            Text("Loading image…")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AntigravityTheme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .background(StepCardPalette.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    @unknown default:
                        fallbackImageCard
                    }
                }
            } else if let res = resolved, res.isSVG, res.textContent != nil {
                MarkdownAgentEmbedCardView(
                    src: src,
                    explicitTitle: captionText,
                    kind: .svg,
                    isStreamingIncomplete: false,
                    store: store
                )
            } else if let data = resolved?.binaryData {
                #if canImport(UIKit)
                if let uiImg = UIImage(data: data) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture { showFullScreen = true }
                } else {
                    fallbackImageCard
                }
                #else
                fallbackImageCard
                #endif
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView().tint(StepCardPalette.periwinkle)
                    Text("Loading \(MarkdownLinkFormatting.shortFileBadge(src))…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(StepCardPalette.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                fallbackImageCard
            }

            if !captionText.isEmpty {
                Text(captionText)
                    .font(.system(size: 12))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
            }
        }
        .task(id: src) {
            guard !lower.hasPrefix("https://") && !lower.hasPrefix("http://") else { return }
            isLoading = true
            defer { isLoading = false }
            if let store {
                resolved = await store.resolveEmbedResource(uri: src)
            } else if lower.hasPrefix("data:") {
                resolved = ResolvedEmbedResource.decodeDataURI(src)
            }
        }
        .sheet(isPresented: $showFullScreen) {
            EmbedFullScreenModalView(title: captionText.isEmpty ? "Image" : captionText, src: src, resolved: resolved)
        }
    }

    private var fallbackImageCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(StepCardPalette.periwinkle)
            VStack(alignment: .leading, spacing: 2) {
                Text(captionText.isEmpty ? "Host Image" : captionText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(AntigravityTheme.inkReading)
                    .lineLimit(1)
                Text(MarkdownLinkFormatting.shortFileBadge(src))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Copy") {
                MarkdownClipboardHelper.copyText(MarkdownLinkFormatting.cleanDisplayPath(src))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(StepCardPalette.periwinkle)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Footnote Section View

internal struct MarkdownFootnoteSectionView: View {
    let items: [MarkdownFootnoteItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: 1)
                .padding(.vertical, 2)

            ForEach(items) { item in
                HStack(alignment: .top, spacing: 6) {
                    Text("[\(item.label)]")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StepCardPalette.periwinkle)
                        .padding(.top, 2)
                    RichMarkdownInlineBlockView(
                        inlines: item.inlines,
                        baseSize: 12.5,
                        baseWeight: .regular,
                        defaultColor: AntigravityTheme.inkSecondary,
                        lineSpacing: 2.0
                    )
                }
            }
        }
    }
}

// MARK: - Fenced Code Block Card (Syntax Highlighting + Wrap Toggle + Copy + Diff Coloring)

internal struct MarkdownCodeBlockCardView: View {
    let language: String?
    let code: String
    @State private var didCopy: Bool = false
    @State private var wrapLines: Bool = false

    private var normalizedLanguage: String {
        let trimmed = (language ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "code" : trimmed.lowercased()
    }

    private var isDiffBlock: Bool {
        normalizedLanguage == "diff" || normalizedLanguage == "patch"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(normalizedLanguage)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.inkSecondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        wrapLines.toggle()
                    }
                } label: {
                    Text(wrapLines ? "Scroll" : "Wrap")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AntigravityTheme.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    MarkdownClipboardHelper.copyText(code)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        didCopy = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.easeInOut(duration: 0.15)) {
                            didCopy = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(didCopy ? "Copied" : "Copy")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(didCopy ? StepCardPalette.emeraldDone : StepCardPalette.periwinkle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            if wrapLines {
                codeBodyView
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    codeBodyView
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StepCardPalette.codeBlockBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var codeBodyView: some View {
        if isDiffBlock {
            diffColoredCodeBody
                .padding(12)
        } else {
            Text(MarkdownSyntaxHighlighter.highlight(code: code.isEmpty ? " " : code, language: normalizedLanguage))
                .lineSpacing(2.5)
                .textSelection(.enabled)
                .padding(12)
        }
    }

    private var diffColoredCodeBody: some View {
        let lines = code.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(diffLineColor(line))
                    .textSelection(.enabled)
            }
        }
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return AntigravityTheme.inkSecondary
        } else if line.hasPrefix("+") {
            return StepCardPalette.emeraldDone
        } else if line.hasPrefix("-") {
            return StepCardPalette.coralError
        } else if line.hasPrefix("@@") {
            return StepCardPalette.periwinkle
        }
        return AntigravityTheme.inkReading
    }
}

/// Zero-dependency Matte Obsidian single-pass syntax highlighter for common languages.
internal enum MarkdownSyntaxHighlighter {
    private static let commentColor = Color(red: 0x6E / 255.0, green: 0x76 / 255.0, blue: 0x8A / 255.0)
    private static let monoFont = Font.system(size: 12.5, weight: .regular, design: .monospaced)

    private static let commonKeywords: Set<String> = [
        "func", "let", "var", "struct", "class", "enum", "actor", "protocol", "extension",
        "import", "public", "private", "internal", "fileprivate", "static", "final", "override",
        "async", "await", "throws", "throw", "try", "catch", "return", "guard", "if", "else",
        "switch", "case", "default", "for", "while", "in", "where", "do", "break", "continue",
        "defer", "init", "self", "Self", "nil", "true", "false", "some", "any", "nonisolated",
        "package", "type", "interface", "go", "chan", "select", "range", "map", "make", "new",
        "const", "function", "export", "from", "as", "typeof", "keyof", "readonly", "void",
        "def", "lambda", "with", "yield", "pass", "None", "True", "False", "and", "or", "not",
        "fn", "mut", "pub", "impl", "trait", "match", "use", "mod", "crate", "ref",
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "CREATE", "TABLE",
        "JOIN", "LEFT", "INNER", "ON", "GROUP", "ORDER", "BY", "LIMIT", "AS", "AND", "OR", "NOT"
    ]

    static func highlight(code: String, language: String) -> AttributedString {
        guard code.count <= 12_000 else {
            var plain = AttributedString(code)
            plain.swiftUI.font = monoFont
            plain.swiftUI.foregroundColor = AntigravityTheme.inkReading
            return plain
        }

        let hashComments = ["python", "py", "bash", "sh", "zsh", "shell", "yaml", "yml", "ruby", "toml"].contains(language)
        let slashComments = !hashComments && language != "sql"
        let dashComments = (language == "sql")

        let chars = Array(code)
        var out = AttributedString()
        var i = 0

        func appendToken(_ str: String, color: Color, italic: Bool = false) {
            var seg = AttributedString(str)
            seg.swiftUI.font = italic ? monoFont.italic() : monoFont
            seg.swiftUI.foregroundColor = color
            out.append(seg)
        }

        while i < chars.count {
            let ch = chars[i]

            // Line comments (`//`, `#`, `--`)
            if (slashComments && ch == "/" && i + 1 < chars.count && chars[i + 1] == "/")
                || (hashComments && ch == "#")
                || (dashComments && ch == "-" && i + 1 < chars.count && chars[i + 1] == "-") {
                let start = i
                while i < chars.count && chars[i] != "\n" { i += 1 }
                appendToken(String(chars[start..<i]), color: commentColor, italic: true)
                continue
            }

            // Block comment (`/* ... */`)
            if slashComments && ch == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                let start = i
                i += 2
                while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i = min(chars.count, i + 2)
                appendToken(String(chars[start..<i]), color: commentColor, italic: true)
                continue
            }

            // String literal (`"..."` or `'...'`)
            if ch == "\"" || ch == "'" {
                let quote = ch
                let start = i
                i += 1
                while i < chars.count && chars[i] != "\n" {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        i += 2
                        continue
                    }
                    if chars[i] == quote {
                        i += 1
                        break
                    }
                    i += 1
                }
                appendToken(String(chars[start..<i]), color: StepCardPalette.emeraldDone)
                continue
            }

            // Decorator / Swift attribute (`@MainActor`, `@Observable`, `@testable`)
            if ch == "@" && i + 1 < chars.count && chars[i + 1].isLetter {
                let start = i
                i += 1
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") { i += 1 }
                appendToken(String(chars[start..<i]), color: StepCardPalette.softViolet)
                continue
            }

            // Number literal
            if ch.isASCII && ch.isNumber {
                let start = i
                while i < chars.count && (chars[i].isHexDigit || chars[i] == "." || chars[i] == "_" || chars[i] == "x" || chars[i] == "X") {
                    i += 1
                }
                appendToken(String(chars[start..<i]), color: StepCardPalette.warmAmber)
                continue
            }

            // Identifier / Keyword / PascalCase Type
            if ch.isLetter || ch == "_" {
                let start = i
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") { i += 1 }
                let word = String(chars[start..<i])
                if commonKeywords.contains(word) || (language == "sql" && commonKeywords.contains(word.uppercased())) {
                    appendToken(word, color: StepCardPalette.periwinkle)
                } else if let first = word.first, first.isASCII && first.isUppercase && word.count >= 2 {
                    appendToken(word, color: StepCardPalette.softViolet)
                } else {
                    appendToken(word, color: AntigravityTheme.inkReading)
                }
                continue
            }

            // Batch plain punctuation / whitespace
            let start = i
            i += 1
            while i < chars.count {
                let c = chars[i]
                if c.isLetter || c == "_" || (c.isASCII && c.isNumber) || c == "\"" || c == "'" || c == "/" || c == "#" || c == "@" || (dashComments && c == "-") {
                    break
                }
                i += 1
            }
            appendToken(String(chars[start..<i]), color: AntigravityTheme.inkReading)
        }

        return out
    }
}

// MARK: - Blockquote & GitHub Alert Callout Card (`[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`)

internal struct MarkdownBlockquoteCardView: View {
    let alert: MarkdownAlertKind?
    let innerBlocks: [MarkdownBlock]
    let store: AntigravitySessionStore?

    var body: some View {
        if let alert {
            let accent = alertAccent(for: alert)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: alert.semanticIcon.sfSymbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(alert.displayTitle)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(accent)
                }

                if !innerBlocks.isEmpty {
                    AnyView(AntigravityMarkdownBlocksView(blocks: innerBlocks, variant: .blockquote, store: store))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.08))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.24), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(StepCardPalette.periwinkle.opacity(0.55))
                    .frame(width: 3)

                AnyView(AntigravityMarkdownBlocksView(blocks: innerBlocks, variant: .blockquote, store: store))
                    .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func alertAccent(for kind: MarkdownAlertKind) -> Color {
        switch kind {
        case .note: return StepCardPalette.periwinkle
        case .tip: return StepCardPalette.emeraldDone
        case .important: return StepCardPalette.softViolet
        case .warning: return StepCardPalette.warmAmber
        case .caution: return StepCardPalette.coralError
        }
    }
}

// MARK: - GFM Pipe & HTML Table Card (Horizontal Scroll + Column Alignment + `<br>` Support)

internal struct MarkdownTableCardView: View {
    let headers: [[MarkdownInline]]
    let alignments: [MarkdownTableAlignment]
    let rows: [[[MarkdownInline]]]

    private var columnCount: Int {
        headers.count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { colIdx in
                        RichMarkdownInlineBlockView(
                            inlines: headers[colIdx],
                            baseSize: 13.0,
                            baseWeight: .semibold,
                            defaultColor: AntigravityTheme.inkReading,
                            lineSpacing: 2.0,
                            textAlignment: textAlignment(for: colIdx),
                            expandsToProposedWidth: false
                        )
                        .frame(maxWidth: 260, alignment: frameAlignment(for: colIdx))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .gridColumnAlignment(horizontalAlignment(for: colIdx))
                    }
                }
                .background(Color.white.opacity(0.05))

                Rectangle()
                    .fill(Color.white.opacity(0.09))
                    .frame(height: 1)

                ForEach(0..<rows.count, id: \.self) { rowIdx in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { colIdx in
                            let cellInlines: [MarkdownInline] = colIdx < rows[rowIdx].count ? rows[rowIdx][colIdx] : []
                            RichMarkdownInlineBlockView(
                                inlines: cellInlines,
                                baseSize: 13.0,
                                baseWeight: .regular,
                                defaultColor: AntigravityTheme.inkLabel,
                                lineSpacing: 2.0,
                                textAlignment: textAlignment(for: colIdx),
                                expandsToProposedWidth: false
                            )
                            .frame(maxWidth: 260, alignment: frameAlignment(for: colIdx))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                    }
                    .background(rowIdx.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.02))

                    if rowIdx + 1 < rows.count {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StepCardPalette.cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func horizontalAlignment(for colIdx: Int) -> HorizontalAlignment {
        guard colIdx < alignments.count else { return .leading }
        switch alignments[colIdx] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(for colIdx: Int) -> TextAlignment {
        guard colIdx < alignments.count else { return .leading }
        switch alignments[colIdx] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func frameAlignment(for colIdx: Int) -> Alignment {
        guard colIdx < alignments.count else { return .leading }
        switch alignments[colIdx] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Display Math Block Card (`$$ ... $$` / `\[ ... \]`)

internal struct MarkdownMathBlockCardView: View {
    let latex: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(MarkdownMathNormalizer.prettify(latex))
                .font(.system(size: 13.5, weight: .regular, design: .serif).italic())
                .foregroundStyle(StepCardPalette.inlineCodeInk)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StepCardPalette.codeBlockBg)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
