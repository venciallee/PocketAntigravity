import SwiftUI
import AntigravityData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Native Matte Obsidian Universal Markdown + Rich Embed Renderer (`AntigravityMarkdownView`)

public enum MarkdownRenderVariant: Sendable, Equatable {
    case assistant
    case userBubble
    case thought
    case blockquote

    var baseFontSize: CGFloat {
        switch self {
        case .assistant: return 15.5
        case .userBubble: return 15.0
        case .thought: return 13.0
        case .blockquote: return 14.5
        }
    }

    var textColor: Color {
        switch self {
        case .assistant, .userBubble:
            return AntigravityTheme.inkReading
        case .thought:
            return AntigravityTheme.inkSecondary
        case .blockquote:
            return AntigravityTheme.inkLabel
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .assistant: return 4.0
        case .userBubble: return 2.8
        case .thought: return 2.8
        case .blockquote: return 3.2
        }
    }

    var blockSpacing: CGFloat {
        switch self {
        case .assistant: return 9.0
        case .userBubble: return 6.0
        case .thought: return 6.0
        case .blockquote: return 6.0
        }
    }

    var expandsParagraphWidth: Bool {
        self != .userBubble
    }
}

public struct AntigravityMarkdownView: View {
    public let markdown: String
    public let variant: MarkdownRenderVariant
    public let store: AntigravitySessionStore?

    @State private var copiedRefLabel: String? = nil
    @State private var copyGeneration: Int = 0
    @State private var inspectedArtifactURI: String? = nil

    public init(
        markdown: String,
        variant: MarkdownRenderVariant = .assistant,
        store: AntigravitySessionStore? = nil
    ) {
        self.markdown = markdown
        self.variant = variant
        self.store = store
    }

    public var body: some View {
        let blocks = AntigravityMarkdownParser.parse(markdown)
        VStack(alignment: .leading, spacing: 6) {
            if blocks.isEmpty {
                Text(markdown)
                    .font(.system(size: variant.baseFontSize))
                    .foregroundStyle(variant.textColor)
                    .lineSpacing(variant.lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                AntigravityMarkdownBlocksView(blocks: blocks, variant: variant, store: store)
            }

            if let copiedRefLabel {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AntigravityTheme.statusDone)
                    Text("Copied \(copiedRefLabel)")
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AntigravityTheme.inkLabel)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AntigravityTheme.surfaceElevated)
                .overlay(
                    Capsule()
                        .stroke(AntigravityTheme.glassHairline, lineWidth: 1)
                )
                .clipShape(Capsule())
                .transition(.opacity)
            }
        }
        .tint(AntigravityTheme.accentPeriwinkle)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "antigravity-ref" {
                let targetRef = MarkdownLinkFormatting.extractCopiedReference(from: url)
                let shortBadge = MarkdownLinkFormatting.shortFileBadge(targetRef)
                let isPreviewableArtifact = ResolvedEmbedResource.isEmbeddableTextArtifactPath(targetRef)
                    || MarkdownEmbedKind.detect(from: targetRef) == .image
                let lowerRef = targetRef.lowercased()
                let isInteractiveDoc = lowerRef.hasSuffix(".html") || lowerRef.hasSuffix(".htm") || lowerRef.hasSuffix(".svg")
                Task { @MainActor in
                    if isPreviewableArtifact,
                       let store,
                       (store.cachedEmbedResource(for: targetRef) != nil || isInteractiveDoc) {
                        inspectedArtifactURI = targetRef
                        return
                    }
                    MarkdownClipboardHelper.copyText(targetRef)
                    copyGeneration += 1
                    let currentGen = copyGeneration
                    withAnimation(.easeInOut(duration: 0.16)) {
                        copiedRefLabel = shortBadge
                    }
                    try? await Task.sleep(for: .seconds(1.8))
                    if copyGeneration == currentGen {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            copiedRefLabel = nil
                        }
                    }
                }
                return .handled
            }
            return .systemAction
        })
        .sheet(
            isPresented: Binding(
                get: { inspectedArtifactURI != nil },
                set: { if !$0 { inspectedArtifactURI = nil } }
            )
        ) {
            if let uri = inspectedArtifactURI {
                RemoteArtifactPreviewSheet(uri: uri, store: store)
            }
        }
    }
}

internal struct AntigravityMarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    let variant: MarkdownRenderVariant
    let store: AntigravitySessionStore?

    var body: some View {
        VStack(alignment: .leading, spacing: variant.blockSpacing) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .frontmatter(_, let entries):
            VStack(alignment: .leading, spacing: 4) {
                Text("FRONTMATTER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.key)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AntigravityTheme.inkSecondary)
                        Text(entry.value)
                            .font(.system(size: 12))
                            .foregroundStyle(AntigravityTheme.inkReading)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AntigravityTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(AntigravityTheme.glassHairline, lineWidth: 1))

        case .heading(_, let level, let inlines):
            let size = headingFontSize(for: level)
            let weight: Font.Weight = level <= 2 ? .bold : .semibold
            let color = level <= 4 ? AntigravityTheme.inkReading : AntigravityTheme.inkLabel
            RichMarkdownInlineBlockView(
                inlines: inlines,
                baseSize: size,
                baseWeight: weight,
                defaultColor: color,
                lineSpacing: 2.5,
                expandsToProposedWidth: variant.expandsParagraphWidth
            )
            .padding(.top, level <= 2 ? 4 : 2)

        case .paragraph(_, let inlines):
            RichMarkdownInlineBlockView(
                inlines: inlines,
                baseSize: variant.baseFontSize,
                baseWeight: .regular,
                defaultColor: variant.textColor,
                lineSpacing: variant.lineSpacing,
                expandsToProposedWidth: variant.expandsParagraphWidth
            )

        case .listItem(_, let indentLevel, let marker, let inlines):
            let firstLineHeight = ceil(variant.baseFontSize * 1.32)
            HStack(alignment: .top, spacing: 7) {
                listMarkerView(marker: marker, indentLevel: indentLevel)
                    .frame(height: firstLineHeight, alignment: .center)
                    .padding(.top, 2)
                RichMarkdownInlineBlockView(
                    inlines: inlines,
                    baseSize: variant.baseFontSize,
                    baseWeight: .regular,
                    defaultColor: isCompletedTask(marker) ? AntigravityTheme.inkSecondary : variant.textColor,
                    lineSpacing: max(2.0, variant.lineSpacing - 0.5),
                    expandsToProposedWidth: variant.expandsParagraphWidth
                )
            }
            .padding(.leading, CGFloat(indentLevel) * 16)

        case .codeBlock(_, let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if block.isSVGDiagram {
                    HStack(spacing: 6) {
                        Image(systemName: "scribble.variable")
                            .font(.system(size: 11, weight: .semibold))
                        Text("SVG Graphic")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AntigravityTheme.accentPeriwinkle.opacity(0.14), in: Capsule())
                }
                MarkdownCodeBlockCardView(language: language, code: code)
            }

        case .blockquote(_, let alert, let innerBlocks):
            MarkdownBlockquoteCardView(alert: alert, innerBlocks: innerBlocks, store: store)

        case .table(_, let headers, let alignments, let rows):
            MarkdownTableCardView(headers: headers, alignments: alignments, rows: rows)

        case .thematicBreak:
            Rectangle()
                .fill(AntigravityTheme.subtleDivider)
                .frame(height: 1)
                .padding(.vertical, 4)

        case .mathBlock(_, let latex):
            MarkdownMathBlockCardView(latex: latex)

        case .agentEmbed(_, let src, let title, let kind, _, let isStreamingIncomplete):
            MarkdownAgentEmbedCardView(
                src: src,
                explicitTitle: title,
                kind: kind,
                isStreamingIncomplete: isStreamingIncomplete,
                store: store
            )

        case .pluginCard(_, let catalogId, let title):
            MarkdownPluginCardView(catalogId: catalogId, explicitTitle: title)

        case .image(_, let alt, let src, let title):
            MarkdownImageBlockView(alt: alt, src: src, title: title, store: store)

        case .details(_, let summary, let innerBlocks, let isOpenByDefault):
            MarkdownDetailsCardView(
                summary: summary,
                innerBlocks: innerBlocks,
                isOpenByDefault: isOpenByDefault,
                store: store
            )

        case .carousel(_, let slides):
            MarkdownCarouselCardView(slides: slides, variant: variant, store: store)

        case .mermaid(_, let source):
            MarkdownMermaidCardView(source: source)

        case .footnoteSection(_, let items):
            MarkdownFootnoteSectionView(items: items)
        }
    }

    private func headingFontSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return variant == .thought ? 15.5 : 19.5
        case 2: return variant == .thought ? 14.5 : 17.5
        case 3: return variant == .thought ? 14.0 : 16.0
        case 4: return variant == .thought ? 13.5 : 15.2
        default: return variant == .thought ? 13.0 : 14.5
        }
    }

    private func isCompletedTask(_ marker: MarkdownListMarker) -> Bool {
        if case .task(let checked) = marker {
            return checked
        }
        return false
    }

    @ViewBuilder
    private func listMarkerView(marker: MarkdownListMarker, indentLevel: Int) -> some View {
        switch marker {
        case .bullet:
            let symbol = indentLevel == 0 ? "•" : (indentLevel == 1 ? "◦" : "▪")
            Text(symbol)
                .font(.system(size: variant.baseFontSize, weight: .bold))
                .foregroundStyle(indentLevel == 0 ? AntigravityTheme.accentPeriwinkle : AntigravityTheme.inkSecondary)
                .frame(minWidth: 12, alignment: .center)

        case .ordered(let number):
            Text("\(number).")
                .font(.system(size: max(12.5, variant.baseFontSize - 1.0), weight: .semibold, design: .monospaced))
                .foregroundStyle(AntigravityTheme.accentPeriwinkle)
                .frame(minWidth: 20, alignment: .trailing)

        case .task(let checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: max(13.0, variant.baseFontSize - 1.5), weight: .medium))
                .foregroundStyle(checked ? AntigravityTheme.statusDone : AntigravityTheme.inkSecondary)
                .frame(minWidth: 16, alignment: .center)
        }
    }
}


// MARK: - SwiftUI `AttributedString` Fallback Builder (Zero `\u{200A}` Orphan Spaces)

internal enum MarkdownInlineBuilder {
    struct StyleState {
        var isBold: Bool = false
        var isItalic: Bool = false
        var isStrikethrough: Bool = false
        var isUnderline: Bool = false
        var isHighlight: Bool = false
        var isCode: Bool = false
        var isKeyboardKey: Bool = false
        var isMath: Bool = false
        var baseWeight: Font.Weight = .regular
        var linkDestination: String? = nil

        func resolvedFont(baseSize: CGFloat) -> Font {
            if isKeyboardKey {
                return Font.system(size: max(11.0, baseSize - 2.5), weight: .semibold, design: .monospaced)
            }
            if isCode {
                let codeSize = max(11.5, baseSize - 1.7)
                let codeWeight: Font.Weight = isBold ? .semibold : .medium
                return Font.system(size: codeSize, weight: codeWeight, design: .monospaced)
            }
            if isMath {
                let mathFont = Font.system(size: max(12.5, baseSize - 0.5), weight: isBold ? .semibold : .regular, design: .serif)
                return mathFont.italic()
            }
            let weight: Font.Weight = isBold ? .bold : baseWeight
            let font = Font.system(size: baseSize, weight: weight, design: .default)
            return isItalic ? font.italic() : font
        }

        func resolvedForeground(defaultColor: Color) -> Color {
            if linkDestination != nil {
                return AntigravityTheme.accentPeriwinkle
            }
            if isCode || isMath || isKeyboardKey {
                return AntigravityTheme.inkInlineCode
            }
            if isHighlight {
                return AntigravityTheme.inkMarkHighlight
            }
            return defaultColor
        }

        var resolvedBackground: Color? {
            if isCode || isKeyboardKey {
                if linkDestination != nil {
                    return AntigravityTheme.accentPeriwinkle.opacity(0.14)
                }
                return isKeyboardKey ? AntigravityTheme.surfaceKbd : AntigravityTheme.surfaceInlineCode
            }
            if isHighlight {
                return AntigravityTheme.surfaceMarkHighlight
            }
            return nil
        }

        var resolvedLinkURL: URL? {
            guard let dest = linkDestination else { return nil }
            return MarkdownLinkFormatting.resolvedActionURL(for: dest)
        }
    }

    static func build(
        _ nodes: [MarkdownInline],
        baseSize: CGFloat,
        baseWeight: Font.Weight,
        defaultColor: Color
    ) -> AttributedString {
        var output = AttributedString()
        let initial = StyleState(baseWeight: baseWeight)
        appendNodes(nodes, style: initial, baseSize: baseSize, defaultColor: defaultColor, into: &output)
        return output
    }

    private static func appendNodes(
        _ nodes: [MarkdownInline],
        style: StyleState,
        baseSize: CGFloat,
        defaultColor: Color,
        into output: inout AttributedString
    ) {
        for node in nodes {
            switch node {
            case .text(let s):
                output.append(makeSegment(s, style: style, baseSize: baseSize, defaultColor: defaultColor))
            case .softBreak:
                output.append(makeSegment("\n", style: style, baseSize: baseSize, defaultColor: defaultColor))
            case .code(let codeText):
                var codeStyle = style
                codeStyle.isCode = true
                output.append(makeSegment(codeText, style: codeStyle, baseSize: baseSize, defaultColor: defaultColor))
            case .keyboardKey(let keyText):
                var kbdStyle = style
                kbdStyle.isKeyboardKey = true
                output.append(makeSegment(keyText, style: kbdStyle, baseSize: baseSize, defaultColor: defaultColor))
            case .strong(let children):
                var boldStyle = style
                boldStyle.isBold = true
                appendNodes(children, style: boldStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .emphasis(let children):
                var italicStyle = style
                italicStyle.isItalic = true
                appendNodes(children, style: italicStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .strikethrough(let children):
                var strikeStyle = style
                strikeStyle.isStrikethrough = true
                appendNodes(children, style: strikeStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .underline(let children):
                var underStyle = style
                underStyle.isUnderline = true
                appendNodes(children, style: underStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .highlight(let children):
                var hiStyle = style
                hiStyle.isHighlight = true
                appendNodes(children, style: hiStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .superscript(let text):
                output.append(makeSegment(MarkdownMathNormalizer.toSuperscript(text), style: style, baseSize: baseSize, defaultColor: defaultColor))
            case .subscriptText(let text):
                output.append(makeSegment(MarkdownMathNormalizer.toSubscript(text), style: style, baseSize: baseSize, defaultColor: defaultColor))
            case .link(let labelNodes, let destination):
                var linkStyle = style
                linkStyle.linkDestination = destination
                appendNodes(labelNodes, style: linkStyle, baseSize: baseSize, defaultColor: defaultColor, into: &output)
            case .inlineMath(let latex):
                var mathStyle = style
                mathStyle.isMath = true
                output.append(makeSegment(MarkdownMathNormalizer.prettify(latex), style: mathStyle, baseSize: baseSize, defaultColor: defaultColor))
            case .inlineImage(let alt, let src):
                var imgStyle = style
                imgStyle.linkDestination = src
                let label = alt.isEmpty ? MarkdownLinkFormatting.shortFileBadge(src) : alt
                output.append(makeSegment("🖼 \(label)", style: imgStyle, baseSize: baseSize, defaultColor: defaultColor))
            case .footnoteRef(let label):
                output.append(makeSegment("[\(label)]", style: style, baseSize: max(10, baseSize - 3), defaultColor: AntigravityTheme.accentPeriwinkle))
            }
        }
    }

    private static func makeSegment(
        _ string: String,
        style: StyleState,
        baseSize: CGFloat,
        defaultColor: Color
    ) -> AttributedString {
        var seg = AttributedString(string)
        seg.swiftUI.font = style.resolvedFont(baseSize: baseSize)
        seg.swiftUI.foregroundColor = style.resolvedForeground(defaultColor: defaultColor)
        if let bg = style.resolvedBackground {
            seg.swiftUI.backgroundColor = bg
        }
        if style.isStrikethrough {
            seg.swiftUI.strikethroughStyle = Text.LineStyle.single
        }
        if style.isUnderline {
            seg.swiftUI.underlineStyle = Text.LineStyle.single
        }
        if let url = style.resolvedLinkURL {
            seg.link = url
        }
        return seg
    }
}

// MARK: - Link & Clipboard Helpers

internal enum MarkdownLinkFormatting {
    static func resolvedActionURL(for rawDestination: String) -> URL? {
        let trimmed = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:") || lower.hasPrefix("antigravity://") {
            if let direct = URL(string: trimmed) {
                return direct
            }
        }
        var comps = URLComponents()
        comps.scheme = "antigravity-ref"
        comps.host = "copy"
        comps.queryItems = [URLQueryItem(name: "ref", value: cleanDisplayPath(trimmed))]
        return comps.url
    }

    static func extractCopiedReference(from url: URL) -> String {
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let ref = comps.queryItems?.first(where: { $0.name == "ref" })?.value,
           !ref.isEmpty {
            return ref
        }
        return url.absoluteString
    }

    static func cleanDisplayPath(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("file://") {
            s = String(s.dropFirst("file://".count))
        }
        if let decoded = s.removingPercentEncoding {
            s = decoded
        }
        return s
    }

    static func shortFileBadge(_ raw: String) -> String {
        let cleaned = cleanDisplayPath(raw)
        let parts = cleaned.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = String(parts[0])
        let fragmentSuffix: String
        if parts.count > 1 && !parts[1].isEmpty {
            fragmentSuffix = "#\(parts[1])"
        } else {
            fragmentSuffix = ""
        }
        let base = (pathPart as NSString).lastPathComponent
        let chosen = base.isEmpty ? pathPart : base
        return chosen + fragmentSuffix
    }
}

internal enum MarkdownClipboardHelper {
    @MainActor
    static func copyText(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
}

internal enum MarkdownMathNormalizer {
    private static let replacements: [(String, String)] = [
        ("\\leftrightarrow", "↔"),
        ("\\Leftrightarrow", "⇔"),
        ("\\rightarrow", "→"),
        ("\\Rightarrow", "⇒"),
        ("\\leftarrow", "←"),
        ("\\Leftarrow", "⇐"),
        ("\\implies", "⇒"),
        ("\\mapsto", "↦"),
        ("\\approx", "≈"),
        ("\\equiv", "≡"),
        ("\\propto", "∝"),
        ("\\times", "×"),
        ("\\cdot", "·"),
        ("\\div", "÷"),
        ("\\pm", "±"),
        ("\\mp", "∓"),
        ("\\leq", "≤"),
        ("\\le", "≤"),
        ("\\geq", "≥"),
        ("\\ge", "≥"),
        ("\\neq", "≠"),
        ("\\ne", "≠"),
        ("\\to", "→"),
        ("\\infty", "∞"),
        ("\\partial", "∂"),
        ("\\nabla", "∇"),
        ("\\forall", "∀"),
        ("\\exists", "∃"),
        ("\\notin", "∉"),
        ("\\in", "∈"),
        ("\\subseteq", "⊆"),
        ("\\subset", "⊂"),
        ("\\cup", "∪"),
        ("\\cap", "∩"),
        ("\\emptyset", "∅"),
        ("\\sum", "∑"),
        ("\\prod", "∏"),
        ("\\int", "∫"),
        ("\\sqrt", "√"),
        ("\\alpha", "α"),
        ("\\beta", "β"),
        ("\\gamma", "γ"),
        ("\\Gamma", "Γ"),
        ("\\delta", "δ"),
        ("\\Delta", "Δ"),
        ("\\epsilon", "ε"),
        ("\\theta", "θ"),
        ("\\Theta", "Θ"),
        ("\\lambda", "λ"),
        ("\\Lambda", "Λ"),
        ("\\mu", "μ"),
        ("\\pi", "π"),
        ("\\Pi", "Π"),
        ("\\rho", "ρ"),
        ("\\sigma", "σ"),
        ("\\Sigma", "Σ"),
        ("\\tau", "τ"),
        ("\\phi", "φ"),
        ("\\Phi", "Φ"),
        ("\\omega", "ω"),
        ("\\Omega", "Ω"),
        ("\\mathbb{R}", "ℝ"),
        ("\\mathbb{N}", "ℕ"),
        ("\\mathbb{Z}", "ℤ"),
        ("\\mathbb{Q}", "ℚ"),
        ("\\mathbb{C}", "ℂ"),
        ("\\ldots", "…"),
        ("\\cdots", "⋯"),
    ]

    private static let superscriptMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "n": "ⁿ", "i": "ⁱ"
    ]

    private static let subscriptMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "i": "ᵢ", "j": "ⱼ", "n": "ₙ", "k": "ₖ", "x": "ₓ"
    ]

    static func toSuperscript(_ s: String) -> String {
        String(s.map { superscriptMap[$0] ?? $0 })
    }

    static func toSubscript(_ s: String) -> String {
        String(s.map { subscriptMap[$0] ?? $0 })
    }

    static func prettify(_ raw: String) -> String {
        var out = raw
        // Simplify `\frac{a}{b}` -> `(a)/(b)` and `\text{foo}` -> `foo`
        out = replaceFrac(in: out)
        out = stripUnaryMacro("\\text", in: out)
        out = stripUnaryMacro("\\mathrm", in: out)
        out = stripUnaryMacro("\\mathbf", in: out)
        for (token, symbol) in replacements {
            out = out.replacingOccurrences(of: token, with: symbol)
        }
        out = replaceScripts(in: out)
        return out
    }

    private static func replaceFrac(in text: String) -> String {
        var s = text
        while let range = s.range(of: "\\frac{") {
            let after = range.upperBound
            guard let firstClose = findMatchingBrace(in: s, from: after),
                  s.index(after: firstClose) < s.endIndex,
                  s[s.index(after: firstClose)] == "{",
                  let secondClose = findMatchingBrace(in: s, from: s.index(firstClose, offsetBy: 2)) else {
                break
            }
            let num = String(s[after..<firstClose])
            let den = String(s[s.index(firstClose, offsetBy: 2)..<secondClose])
            let replacement = "\(num)/\(den)"
            s.replaceSubrange(range.lowerBound...secondClose, with: replacement)
        }
        return s
    }

    private static func stripUnaryMacro(_ macro: String, in text: String) -> String {
        var s = text
        let token = "\(macro){"
        while let range = s.range(of: token) {
            guard let closeIdx = findMatchingBrace(in: s, from: range.upperBound) else { break }
            let inner = String(s[range.upperBound..<closeIdx])
            s.replaceSubrange(range.lowerBound...closeIdx, with: inner)
        }
        return s
    }

    private static func findMatchingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 1
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return idx }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private static func replaceScripts(in text: String) -> String {
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if (ch == "^" || ch == "_"), i + 1 < chars.count {
                let isSup = (ch == "^")
                if chars[i + 1] == "{" {
                    var j = i + 2
                    while j < chars.count && chars[j] != "}" { j += 1 }
                    if j < chars.count {
                        let inner = String(chars[(i + 2)..<j])
                        let map = isSup ? superscriptMap : subscriptMap
                        if inner.allSatisfy({ map[$0] != nil }) {
                            out.append(isSup ? toSuperscript(inner) : toSubscript(inner))
                            i = j + 1
                            continue
                        }
                    }
                } else {
                    let next = chars[i + 1]
                    let map = isSup ? superscriptMap : subscriptMap
                    if let mapped = map[next] {
                        out.append(mapped)
                        i += 2
                        continue
                    }
                }
            }
            out.append(ch)
            i += 1
        }
        return out
    }
}
