import Foundation

// MARK: - AST Models (`Sendable`, Pure Swift 6, Zero UIKit Dependency)

public enum MarkdownAlertKind: String, Sendable, Equatable, CaseIterable {
    case note = "NOTE"
    case tip = "TIP"
    case important = "IMPORTANT"
    case warning = "WARNING"
    case caution = "CAUTION"

    public var displayTitle: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        }
    }

    public var sfSymbolName: String {
        switch self {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.bubble.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "flame.fill"
        }
    }
}

public enum MarkdownListMarker: Sendable, Equatable {
    case bullet
    case ordered(Int)
    case task(checked: Bool)
}

public enum MarkdownTableAlignment: Sendable, Equatable {
    case leading
    case center
    case trailing
}

public enum MarkdownEmbedKind: String, Sendable, Equatable {
    case htmlWidget
    case image
    case svg
    case markdown
    case webURL
    case sidecar
    case generic

    public static func detect(from rawSrc: String) -> MarkdownEmbedKind {
        let trimmed = rawSrc.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("sidecar://") {
            return .sidecar
        }
        let pathNoFragment = lower.split(separator: "#", maxSplits: 1).first.map(String.init) ?? lower
        let pathNoQuery = pathNoFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? pathNoFragment
        if pathNoQuery.hasSuffix(".html") || pathNoQuery.hasSuffix(".htm") {
            return .htmlWidget
        }
        if pathNoQuery.hasSuffix(".svg") {
            return .svg
        }
        if pathNoQuery.hasSuffix(".png")
            || pathNoQuery.hasSuffix(".jpg")
            || pathNoQuery.hasSuffix(".jpeg")
            || pathNoQuery.hasSuffix(".webp")
            || pathNoQuery.hasSuffix(".gif")
            || pathNoQuery.hasSuffix(".heic")
            || lower.hasPrefix("data:image/") {
            return .image
        }
        if pathNoQuery.hasSuffix(".md") || pathNoQuery.hasSuffix(".markdown") {
            return .markdown
        }
        if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
            return .webURL
        }
        return .generic
    }

    public var displayBadge: String {
        switch self {
        case .htmlWidget: return "Interactive Widget"
        case .image: return "Image"
        case .svg: return "SVG Graphic"
        case .markdown: return "Document"
        case .webURL: return "Web Preview"
        case .sidecar: return "UI Extension"
        case .generic: return "Artifact Embed"
        }
    }

    public var sfSymbolName: String {
        switch self {
        case .htmlWidget: return "sparkles.rectangle.stack"
        case .image: return "photo"
        case .svg: return "point.3.connected.trianglepath.dotted"
        case .markdown: return "doc.richtext"
        case .webURL: return "globe"
        case .sidecar: return "puzzlepiece.extension"
        case .generic: return "doc.badge.gearshape"
        }
    }
}

public struct MarkdownFootnoteItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let inlines: [MarkdownInline]

    public init(label: String, inlines: [MarkdownInline]) {
        self.id = label
        self.label = label
        self.inlines = inlines
    }
}

public struct MarkdownFrontmatterEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public indirect enum MarkdownInline: Sendable, Equatable {
    case text(String)
    case softBreak
    case code(String)
    case strong([MarkdownInline])
    case emphasis([MarkdownInline])
    case strikethrough([MarkdownInline])
    case underline([MarkdownInline])
    case highlight([MarkdownInline])
    case superscript(String)
    case subscriptText(String)
    case keyboardKey(String)
    case link(label: [MarkdownInline], destination: String)
    case inlineMath(String)
    case inlineImage(alt: String, src: String)
    case footnoteRef(String)

    /// Plain-text projection used for accessibility, clipboard fallback, and testing.
    public var plainText: String {
        switch self {
        case .text(let s):
            return s
        case .softBreak:
            return "\n"
        case .code(let c):
            return c
        case .strong(let children),
             .emphasis(let children),
             .strikethrough(let children),
             .underline(let children),
             .highlight(let children):
            return children.map(\.plainText).joined()
        case .superscript(let s), .subscriptText(let s), .keyboardKey(let s):
            return s
        case .link(let label, _):
            return label.map(\.plainText).joined()
        case .inlineMath(let latex):
            return latex
        case .inlineImage(let alt, let src):
            return alt.isEmpty ? src : alt
        case .footnoteRef(let label):
            return "[\(label)]"
        }
    }
}

public indirect enum MarkdownBlock: Sendable, Equatable, Identifiable {
    case frontmatter(id: Int, entries: [MarkdownFrontmatterEntry])
    case heading(id: Int, level: Int, inlines: [MarkdownInline])
    case paragraph(id: Int, inlines: [MarkdownInline])
    case codeBlock(id: Int, language: String?, code: String)
    case listItem(id: Int, indentLevel: Int, marker: MarkdownListMarker, inlines: [MarkdownInline])
    case blockquote(id: Int, alert: MarkdownAlertKind?, blocks: [MarkdownBlock])
    case table(id: Int, headers: [[MarkdownInline]], alignments: [MarkdownTableAlignment], rows: [[[MarkdownInline]]])
    case thematicBreak(id: Int)
    case mathBlock(id: Int, latex: String)
    case agentEmbed(id: Int, src: String, title: String?, kind: MarkdownEmbedKind, attributes: [String: String], isStreamingIncomplete: Bool)
    case pluginCard(id: Int, catalogId: String, title: String?)
    case image(id: Int, alt: String, src: String, title: String?)
    case details(id: Int, summary: [MarkdownInline], blocks: [MarkdownBlock], isOpenByDefault: Bool)
    case carousel(id: Int, slides: [[MarkdownBlock]])
    case mermaid(id: Int, source: String)
    case footnoteSection(id: Int, items: [MarkdownFootnoteItem])

    public var id: Int {
        switch self {
        case .frontmatter(let id, _),
             .heading(let id, _, _),
             .paragraph(let id, _),
             .codeBlock(let id, _, _),
             .listItem(let id, _, _, _),
             .blockquote(let id, _, _),
             .table(let id, _, _, _),
             .thematicBreak(let id),
             .mathBlock(let id, _),
             .agentEmbed(let id, _, _, _, _, _),
             .pluginCard(let id, _, _),
             .image(let id, _, _, _),
             .details(let id, _, _, _),
             .carousel(let id, _),
             .mermaid(let id, _),
             .footnoteSection(let id, _):
            return id
        }
    }

    public var isMermaidDiagram: Bool {
        switch self {
        case .mermaid:
            return true
        case .codeBlock(_, let lang, _):
            return lang?.lowercased() == "mermaid"
        default:
            return false
        }
    }

    public var isSVGDiagram: Bool {
        if case .codeBlock(_, let lang, let code) = self {
            let l = lang?.lowercased() ?? ""
            return l == "svg" || (l == "xml" && code.contains("<svg"))
        }
        return false
    }
}

// MARK: - Bounded Thread-Safe LRU AST Cache

private final class MarkdownASTCache: @unchecked Sendable {
    static let shared = MarkdownASTCache(capacity: 128)

    private let lock = NSLock()
    private let capacity: Int
    private var entries: [String: [MarkdownBlock]] = [:]
    private var order: [String] = []

    init(capacity: Int) {
        self.capacity = max(16, capacity)
    }

    func get(_ key: String) -> [MarkdownBlock]? {
        guard key.utf8.count <= 262_144 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return entries[key]
    }

    func set(_ value: [MarkdownBlock], for key: String) {
        guard key.utf8.count <= 262_144 else { return }
        lock.lock()
        defer { lock.unlock() }
        if entries[key] != nil {
            entries[key] = value
            return
        }
        entries[key] = value
        order.append(key)
        while order.count > capacity {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }
}

// MARK: - Universal Antigravity GFM + HTML + Rich Embed Parser (`AntigravityMarkdownParser`)

/// Pure Swift 6 GitHub-Flavored Markdown (GFM), HTML subset, and Antigravity Agent Extension parser:
/// - Standard GFM: ATX & Setext headings, fenced/streaming code blocks, nested/ordered/task lists,
///   GFM pipe & HTML tables, `[!NOTE]`..`[!CAUTION]` alerts, reference links, footnotes, autolinks,
///   intraword-safe `snake_case`, and LaTeX math (`$...$`, `$$...$$`, `\(...\)`, `\[...\]`).
/// - Antigravity Rich Extensions: `<agent-embed src="...">`, `<plugin-card catalog-id="...">`,
///   ```` ````carousel ... <!-- slide --> ... ```` ````, ` ```mermaid `, `<details><summary>`,
///   standalone/inline images (`![alt](url)`, `<img>`, `<figure>`), inline HTML (`<br>`, `<b>`,
///   `<i>`, `<code>`, `<kbd>`, `<mark>`, `<u>`, `<s>`, `<sup>`, `<sub>`, `<a>`), HTML entities,
///   HTML comment stripping, and streaming-safe unclosed tag recovery.
public enum AntigravityMarkdownParser: Sendable {

    private static let asciiPunctuation: Set<Character> = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    private static let knownInlineHTMLTags: Set<String> = [
        "br", "b", "strong", "i", "em", "code", "kbd", "s", "del", "strike",
        "u", "ins", "mark", "sup", "sub", "a", "img", "span", "small", "abbr",
        "q", "cite", "var", "samp", "wbr"
    ]

    private static let knownBlockHTMLTags: Set<String> = [
        "details", "summary", "table", "thead", "tbody", "tfoot", "tr", "th", "td",
        "h1", "h2", "h3", "h4", "h5", "h6", "p", "div", "blockquote", "pre",
        "ul", "ol", "li", "hr", "figure", "figcaption", "section", "article",
        "aside", "header", "footer", "nav", "agent-embed", "plugin-card"
    ]

    private struct ParseContext {
        var referenceLinks: [String: String] = [:]
        var footnoteDefs: [(label: String, body: String)] = []
    }

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        if let cached = MarkdownASTCache.shared.get(markdown) {
            return cached
        }
        var nextId = 0
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        var blocks: [MarkdownBlock] = []
        var bodySource = normalized
        let topLines = normalized.components(separatedBy: "\n")
        if let fm = parseLeadingFrontmatter(lines: topLines) {
            blocks.append(.frontmatter(id: allocateId(&nextId), entries: fm.entries))
            bodySource = topLines.dropFirst(fm.nextIndex).joined(separator: "\n")
        }

        let (cleanedSource, ctx) = extractDefinitions(from: bodySource)
        blocks.append(contentsOf: parseBlocks(from: cleanedSource, nextId: &nextId, context: ctx))

        if !ctx.footnoteDefs.isEmpty {
            let items = ctx.footnoteDefs.map { def in
                MarkdownFootnoteItem(
                    label: def.label,
                    inlines: parseInlines(def.body, referenceLinks: ctx.referenceLinks)
                )
            }
            blocks.append(.footnoteSection(id: allocateId(&nextId), items: items))
        }

        MarkdownASTCache.shared.set(blocks, for: markdown)
        return blocks
    }

    /// Extracts deduplicated GitHub Pull Request links (`https://github.com/<owner>/<repo>/pull/<number>`) from markdown text.
    public static func extractGitHubPRLinks(from text: String) -> [GitHubPullRequestInfo] {
        guard text.contains("github.com/") && text.contains("/pull/") else { return [] }
        let pattern = #"https?://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        var seen: Set<String> = []
        var results: [GitHubPullRequestInfo] = []
        for match in matches where match.numberOfRanges >= 3 {
            let fullUrl = nsText.substring(with: match.range(at: 0))
            let repo = nsText.substring(with: match.range(at: 1))
            let numStr = nsText.substring(with: match.range(at: 2))
            let key = "\(repo)#\(numStr)"
            guard !seen.contains(key), let number = Int(numStr) else { continue }
            seen.insert(key)
            results.append(
                GitHubPullRequestInfo(
                    ownerRepo: repo,
                    number: number,
                    title: "Pull Request #\(number)",
                    state: .open,
                    checksSummary: "Checks pending",
                    url: fullUrl
                )
            )
        }
        return results
    }

    private static func parseLeadingFrontmatter(lines: [String]) -> (entries: [MarkdownFrontmatterEntry], nextIndex: Int)? {
        guard lines.count >= 3 else { return nil }
        guard lines[0].trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var entries: [MarkdownFrontmatterEntry] = []
        let limit = min(lines.count, 40)
        for i in 1..<limit {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                guard !entries.isEmpty else { return nil }
                return (entries, i + 1)
            }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let colonIdx = trimmed.firstIndex(of: ":") else { return nil }
            let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let rawVal = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
                return nil
            }
            let cleanedVal = rawVal.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            entries.append(MarkdownFrontmatterEntry(key: key, value: cleanedVal))
        }
        return nil
    }

    /// Derives a clean human-readable display title from an embed/artifact path or filename
    /// (e.g. `file:///.../fig4-verification-pyramid.html` -> `Fig 4 · Verification Pyramid`).
    public static func humanReadableEmbedTitle(src: String, explicitTitle: String? = nil) -> String {
        if let explicit = explicitTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        var cleaned = src.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("file://") {
            cleaned = String(cleaned.dropFirst("file://".count))
        }
        if let decoded = cleaned.removingPercentEncoding {
            cleaned = decoded
        }
        let noFragment = cleaned.split(separator: "#", maxSplits: 1).first.map(String.init) ?? cleaned
        let noQuery = noFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? noFragment
        let lastComp = (noQuery as NSString).lastPathComponent
        guard !lastComp.isEmpty else { return "Interactive Widget" }

        let stem = (lastComp as NSString).deletingPathExtension
        guard !stem.isEmpty else { return lastComp }

        let rawTokens = stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !rawTokens.isEmpty else { return lastComp }

        var formatted: [String] = []
        for (idx, token) in rawTokens.enumerated() {
            let lower = token.lowercased()
            if idx == 0, lower.hasPrefix("fig"), lower.count > 3,
               lower.dropFirst(3).allSatisfy(\.isNumber) {
                formatted.append("Fig \(lower.dropFirst(3)) ·")
            } else if ["api", "ui", "ux", "sql", "cli", "rpc", "mcp", "cpu", "gpu", "svg", "html", "json", "http", "ts", "go", "ios", "esdd", "gfm", "dag"].contains(lower) {
                formatted.append(lower.uppercased())
            } else {
                formatted.append(token.prefix(1).uppercased() + token.dropFirst())
            }
        }
        return formatted.joined(separator: " ").replacingOccurrences(of: "· ", with: "· ")
    }

    // MARK: - Reference Link & Footnote Pre-Pass

    private static func extractDefinitions(from normalized: String) -> (String, ParseContext) {
        let lines = normalized.components(separatedBy: "\n")
        var keptLines: [String] = []
        var ctx = ParseContext()
        var activeFence: (char: Character, length: Int)? = nil
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let expanded = expandLeadingTabs(line)
            let leadingSpaces = countLeadingSpaces(expanded)
            let trimmedLead = String(expanded.dropFirst(leadingSpaces))
            let trimmed = trimmedLead.trimmingCharacters(in: .whitespaces)

            if let fence = activeFence {
                keptLines.append(line)
                if isClosingCodeFence(trimmed, fenceChar: fence.char, minLength: fence.length) {
                    activeFence = nil
                }
                i += 1
                continue
            }
            if let fence = matchCodeFenceOpening(trimmedLead) {
                activeFence = (fence.char, fence.length)
                keptLines.append(line)
                i += 1
                continue
            }

            if leadingSpaces < 4 {
                if let footnote = matchFootnoteDefinition(trimmedLead) {
                    var bodyLines = [footnote.body]
                    i += 1
                    while i < lines.count {
                        let cont = expandLeadingTabs(lines[i])
                        let contSpaces = countLeadingSpaces(cont)
                        let contTrim = cont.trimmingCharacters(in: .whitespaces)
                        if contSpaces >= 2 && !contTrim.isEmpty {
                            bodyLines.append(contTrim)
                            i += 1
                        } else {
                            break
                        }
                    }
                    ctx.footnoteDefs.append((footnote.label, bodyLines.joined(separator: "\n")))
                    continue
                }
                if let refDef = matchReferenceLinkDefinition(trimmedLead) {
                    ctx.referenceLinks[refDef.key] = refDef.destination
                    i += 1
                    continue
                }
            }

            keptLines.append(line)
            i += 1
        }

        return (keptLines.joined(separator: "\n"), ctx)
    }

    private static func matchReferenceLinkDefinition(_ trimmedLead: String) -> (key: String, destination: String)? {
        guard trimmedLead.hasPrefix("["), !trimmedLead.hasPrefix("[^") else { return nil }
        let chars = Array(trimmedLead)
        guard let closeBracket = findMatchingBracket(chars, openAt: 0, end: chars.count),
              closeBracket + 1 < chars.count,
              chars[closeBracket + 1] == ":" else {
            return nil
        }
        let key = String(chars[1..<closeBracket]).trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        var rest = String(chars[(closeBracket + 2)...]).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }

        if rest.hasPrefix("<"), let gtIdx = rest.firstIndex(of: ">") {
            let dest = String(rest[rest.index(after: rest.startIndex)..<gtIdx]).trimmingCharacters(in: .whitespaces)
            return dest.isEmpty ? nil : (key, dest)
        }
        let firstToken = rest.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard !firstToken.isEmpty,
              firstToken.contains("://") || firstToken.hasPrefix("/") || firstToken.hasPrefix("#") || firstToken.hasPrefix("mailto:") else {
            return nil
        }
        rest = firstToken
        return (key, rest)
    }

    private static func matchFootnoteDefinition(_ trimmedLead: String) -> (label: String, body: String)? {
        guard trimmedLead.hasPrefix("[^") else { return nil }
        let chars = Array(trimmedLead)
        guard let closeIdx = chars.firstIndex(of: "]"),
              closeIdx > 2,
              closeIdx + 1 < chars.count,
              chars[closeIdx + 1] == ":" else {
            return nil
        }
        let label = String(chars[2..<closeIdx]).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !label.contains(where: \.isWhitespace) else { return nil }
        let body = String(chars[(closeIdx + 2)...]).trimmingCharacters(in: .whitespaces)
        return (label, body)
    }

    // MARK: - Block Parsing

    private static func parseBlocks(
        from rawText: String,
        nextId: inout Int,
        context: ParseContext
    ) -> [MarkdownBlock] {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }

        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0
        var listIndentStack: [Int] = []

        while index < lines.count {
            let line = lines[index]
            let expanded = expandLeadingTabs(line)
            let leadingSpaces = countLeadingSpaces(expanded)
            let trimmedLead = String(expanded.dropFirst(leadingSpaces))
            let trimmed = trimmedLead.trimmingCharacters(in: .whitespaces)

            // 1. Blank line
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // 2. HTML Comment Block (`<!-- ... -->`, stripped silently)
            if trimmed.hasPrefix("<!--") {
                if trimmed.contains("-->") {
                    let afterClose = trimmed.components(separatedBy: "-->").dropFirst().joined(separator: "-->").trimmingCharacters(in: .whitespaces)
                    index += 1
                    if !afterClose.isEmpty {
                        let sub = parseBlocks(from: afterClose, nextId: &nextId, context: context)
                        blocks.append(contentsOf: sub)
                    }
                    continue
                } else {
                    index += 1
                    while index < lines.count {
                        if lines[index].contains("-->") {
                            index += 1
                            break
                        }
                        index += 1
                    }
                    continue
                }
            }

            // 3. Fenced Code Block (``` or ~~~, including `carousel` and `mermaid` and streaming unclosed fences)
            if let fence = matchCodeFenceOpening(trimmedLead) {
                listIndentStack.removeAll()
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let candidateExpanded = expandLeadingTabs(lines[index])
                    let candidateTrimmed = candidateExpanded.trimmingCharacters(in: .whitespaces)
                    if isClosingCodeFence(candidateTrimmed, fenceChar: fence.char, minLength: fence.length) {
                        index += 1
                        break
                    }
                    let dedented = stripUpToLeadingSpaces(candidateExpanded, maxSpaces: leadingSpaces)
                    codeLines.append(dedented)
                    index += 1
                }
                let rawBody = codeLines.joined(separator: "\n")
                let lowerLang = fence.language?.lowercased()

                if lowerLang == "carousel" {
                    let slides = parseCarouselSlides(rawBody, nextId: &nextId, context: context)
                    if !slides.isEmpty {
                        blocks.append(.carousel(id: allocateId(&nextId), slides: slides))
                    }
                } else if lowerLang == "mermaid" {
                    blocks.append(.mermaid(id: allocateId(&nextId), source: rawBody))
                } else {
                    blocks.append(
                        .codeBlock(
                            id: allocateId(&nextId),
                            language: fence.language,
                            code: rawBody
                        )
                    )
                }
                continue
            }

            // 4. Antigravity `<agent-embed ...>` Block (single-line, multi-line, self-closing, or streaming unclosed)
            if hasCaseInsensitivePrefix(trimmed, "<agent-embed") {
                listIndentStack.removeAll()
                let parsedEmbed = consumeCustomElementBlock(
                    lines: lines,
                    startIndex: index,
                    tagName: "agent-embed"
                )
                index = parsedEmbed.nextIndex
                let src = parsedEmbed.attributes["src"] ?? parsedEmbed.attributes["href"] ?? parsedEmbed.attributes["url"] ?? ""
                let title = parsedEmbed.attributes["title"] ?? parsedEmbed.attributes["alt"] ?? parsedEmbed.attributes["label"]
                blocks.append(
                    .agentEmbed(
                        id: allocateId(&nextId),
                        src: src,
                        title: title,
                        kind: MarkdownEmbedKind.detect(from: src),
                        attributes: parsedEmbed.attributes,
                        isStreamingIncomplete: parsedEmbed.isIncomplete
                    )
                )
                if !parsedEmbed.trailingRemainder.isEmpty {
                    blocks.append(contentsOf: parseBlocks(from: parsedEmbed.trailingRemainder, nextId: &nextId, context: context))
                }
                continue
            }

            // 5. Antigravity `<plugin-card ...>` Block
            if hasCaseInsensitivePrefix(trimmed, "<plugin-card") {
                listIndentStack.removeAll()
                let parsedCard = consumeCustomElementBlock(
                    lines: lines,
                    startIndex: index,
                    tagName: "plugin-card"
                )
                index = parsedCard.nextIndex
                let catalogId = parsedCard.attributes["catalog-id"]
                    ?? parsedCard.attributes["catalogid"]
                    ?? parsedCard.attributes["id"]
                    ?? "plugin"
                let title = parsedCard.attributes["title"] ?? parsedCard.attributes["name"]
                blocks.append(.pluginCard(id: allocateId(&nextId), catalogId: catalogId, title: title))
                if !parsedCard.trailingRemainder.isEmpty {
                    blocks.append(contentsOf: parseBlocks(from: parsedCard.trailingRemainder, nextId: &nextId, context: context))
                }
                continue
            }

            // 6. Collapsible HTML `<details><summary>...</summary>...</details>` Block
            if hasCaseInsensitivePrefix(trimmed, "<details") {
                listIndentStack.removeAll()
                let parsedDetails = consumeDetailsBlock(lines: lines, startIndex: index)
                index = parsedDetails.nextIndex
                let summaryInlines = parseInlines(
                    parsedDetails.summaryText.isEmpty ? "Details" : parsedDetails.summaryText,
                    referenceLinks: context.referenceLinks
                )
                let innerBlocks = parseBlocks(from: parsedDetails.innerMarkdown, nextId: &nextId, context: context)
                blocks.append(
                    .details(
                        id: allocateId(&nextId),
                        summary: summaryInlines,
                        blocks: innerBlocks,
                        isOpenByDefault: parsedDetails.isOpen
                    )
                )
                continue
            }

            // 7. HTML `<table>...</table>` Block -> Native `.table`
            if hasCaseInsensitivePrefix(trimmed, "<table") {
                let consumed = consumeHTMLTagRegion(lines: lines, startIndex: index, tagName: "table")
                if let htmlTable = parseHTMLTable(consumed.rawHTML, referenceLinks: context.referenceLinks) {
                    listIndentStack.removeAll()
                    index = consumed.nextIndex
                    blocks.append(
                        .table(
                            id: allocateId(&nextId),
                            headers: htmlTable.headers,
                            alignments: htmlTable.alignments,
                            rows: htmlTable.rows
                        )
                    )
                    continue
                }
            }

            // 8. HTML `<pre>...</pre>` Block -> Native `.codeBlock`
            if hasCaseInsensitivePrefix(trimmed, "<pre") {
                listIndentStack.removeAll()
                let consumed = consumeHTMLTagRegion(lines: lines, startIndex: index, tagName: "pre")
                index = consumed.nextIndex
                let (lang, codeText) = extractPreCodeBlock(consumed.rawHTML)
                blocks.append(.codeBlock(id: allocateId(&nextId), language: lang, code: codeText))
                continue
            }

            // 9. HTML `<figure>...</figure>` or Standalone `<img ... />` or Standalone Markdown Image `![alt](src)`
            if hasCaseInsensitivePrefix(trimmed, "<figure") {
                let consumed = consumeHTMLTagRegion(lines: lines, startIndex: index, tagName: "figure")
                if let img = extractImageFromHTML(consumed.rawHTML) {
                    listIndentStack.removeAll()
                    index = consumed.nextIndex
                    blocks.append(.image(id: allocateId(&nextId), alt: img.alt, src: img.src, title: img.title))
                    continue
                }
            }
            if hasCaseInsensitivePrefix(trimmed, "<img"), let img = extractStandaloneHTMLImg(trimmed) {
                listIndentStack.removeAll()
                blocks.append(.image(id: allocateId(&nextId), alt: img.alt, src: img.src, title: img.title))
                index += 1
                continue
            }
            if let mdImage = matchStandaloneMarkdownImage(trimmed, referenceLinks: context.referenceLinks) {
                listIndentStack.removeAll()
                blocks.append(.image(id: allocateId(&nextId), alt: mdImage.alt, src: mdImage.src, title: mdImage.title))
                index += 1
                continue
            }

            // 10. HTML `<hr>` / `<h1..h6>` / `<blockquote>` / `<ul>` / `<ol>` Block Equivalents
            if isHTMLHorizontalRule(trimmed) {
                listIndentStack.removeAll()
                blocks.append(.thematicBreak(id: allocateId(&nextId)))
                index += 1
                continue
            }
            if let htmlHeading = matchHTMLHeadingLine(trimmed) {
                listIndentStack.removeAll()
                blocks.append(
                    .heading(
                        id: allocateId(&nextId),
                        level: htmlHeading.level,
                        inlines: parseInlines(htmlHeading.content, referenceLinks: context.referenceLinks)
                    )
                )
                index += 1
                continue
            }
            if hasCaseInsensitivePrefix(trimmed, "<blockquote") {
                listIndentStack.removeAll()
                let consumed = consumeHTMLTagRegion(lines: lines, startIndex: index, tagName: "blockquote")
                index = consumed.nextIndex
                let inner = stripOuterHTMLTag(consumed.rawHTML, tagName: "blockquote")
                let quoteId = allocateId(&nextId)
                let innerBlocks = parseBlocks(from: inner, nextId: &nextId, context: context)
                blocks.append(.blockquote(id: quoteId, alert: nil, blocks: innerBlocks))
                continue
            }
            if hasCaseInsensitivePrefix(trimmed, "<ul") || hasCaseInsensitivePrefix(trimmed, "<ol") {
                let isOrdered = hasCaseInsensitivePrefix(trimmed, "<ol")
                let tagName = isOrdered ? "ol" : "ul"
                let consumed = consumeHTMLTagRegion(lines: lines, startIndex: index, tagName: tagName)
                let items = extractHTMLListItems(consumed.rawHTML)
                if !items.isEmpty {
                    listIndentStack.removeAll()
                    index = consumed.nextIndex
                    for (itemIdx, itemText) in items.enumerated() {
                        let marker: MarkdownListMarker = isOrdered ? .ordered(itemIdx + 1) : .bullet
                        blocks.append(
                            .listItem(
                                id: allocateId(&nextId),
                                indentLevel: 0,
                                marker: marker,
                                inlines: parseInlines(itemText, referenceLinks: context.referenceLinks)
                            )
                        )
                    }
                    continue
                }
            }

            // 11. Display Math Block (`$$ ... $$` or `\[ ... \]`)
            if trimmed.hasPrefix("$$") || trimmed.hasPrefix("\\[") {
                let closeMarker = trimmed.hasPrefix("$$") ? "$$" : "\\]"
                let afterOpen = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !afterOpen.isEmpty && afterOpen.hasSuffix(closeMarker) && afterOpen.count >= closeMarker.count {
                    listIndentStack.removeAll()
                    let inner = String(afterOpen.dropLast(closeMarker.count)).trimmingCharacters(in: .whitespaces)
                    if !inner.isEmpty {
                        blocks.append(.mathBlock(id: allocateId(&nextId), latex: inner))
                        index += 1
                        continue
                    }
                } else if afterOpen.isEmpty || !afterOpen.contains(closeMarker) {
                    listIndentStack.removeAll()
                    var mathLines: [String] = afterOpen.isEmpty ? [] : [afterOpen]
                    index += 1
                    while index < lines.count {
                        let mLine = lines[index]
                        let mTrim = mLine.trimmingCharacters(in: .whitespaces)
                        if mTrim == closeMarker {
                            index += 1
                            break
                        } else if mTrim.hasSuffix(closeMarker) {
                            let prefix = String(mTrim.dropLast(closeMarker.count)).trimmingCharacters(in: .whitespaces)
                            if !prefix.isEmpty { mathLines.append(prefix) }
                            index += 1
                            break
                        }
                        mathLines.append(mLine)
                        index += 1
                    }
                    blocks.append(.mathBlock(id: allocateId(&nextId), latex: mathLines.joined(separator: "\n")))
                    continue
                }
            }

            // 12. ATX Heading (`#` .. `######`)
            if leadingSpaces < 4, let heading = matchATXHeading(trimmedLead) {
                listIndentStack.removeAll()
                blocks.append(
                    .heading(
                        id: allocateId(&nextId),
                        level: heading.level,
                        inlines: parseInlines(heading.content, referenceLinks: context.referenceLinks)
                    )
                )
                index += 1
                continue
            }

            // 13. Thematic Break (`---`, `***`, `___`)
            if leadingSpaces < 4 && isThematicBreak(trimmed) {
                listIndentStack.removeAll()
                blocks.append(.thematicBreak(id: allocateId(&nextId)))
                index += 1
                continue
            }

            // 14. Blockquote & GitHub Alert (`> ...`, `> [!NOTE]`)
            if leadingSpaces < 4 && trimmedLead.hasPrefix(">") {
                listIndentStack.removeAll()
                var quoteLines: [String] = []
                while index < lines.count {
                    let qExpanded = expandLeadingTabs(lines[index])
                    let qSpaces = countLeadingSpaces(qExpanded)
                    let qTrimLead = String(qExpanded.dropFirst(qSpaces))
                    if qSpaces < 4 && qTrimLead.hasPrefix(">") {
                        var stripped = String(qTrimLead.dropFirst())
                        if stripped.first == " " {
                            stripped.removeFirst()
                        }
                        quoteLines.append(stripped)
                        index += 1
                    } else {
                        break
                    }
                }

                var detectedAlert: MarkdownAlertKind? = nil
                if let firstLine = quoteLines.first {
                    let firstTrim = firstLine.trimmingCharacters(in: .whitespaces)
                    for kind in MarkdownAlertKind.allCases {
                        let tag = "[!\(kind.rawValue)]"
                        if firstTrim.uppercased().hasPrefix(tag) {
                            detectedAlert = kind
                            let remainder = String(firstTrim.dropFirst(tag.count)).trimmingCharacters(in: .whitespaces)
                            if remainder.isEmpty {
                                quoteLines.removeFirst()
                            } else {
                                quoteLines[0] = remainder
                            }
                            break
                        }
                    }
                }

                let blockquoteId = allocateId(&nextId)
                let innerBlocks = parseBlocks(from: quoteLines.joined(separator: "\n"), nextId: &nextId, context: context)
                blocks.append(.blockquote(id: blockquoteId, alert: detectedAlert, blocks: innerBlocks))
                continue
            }

            // 15. GFM Pipe Table (`| col1 | col2 |` followed by delimiter row `| --- | :---: |`)
            if leadingSpaces < 4,
               index + 1 < lines.count,
               trimmed.contains("|"),
               let alignments = parseTableDelimiterRow(lines[index + 1]) {
                let headerCellsRaw = splitTableCells(trimmed)
                if !headerCellsRaw.isEmpty && headerCellsRaw.count == alignments.count {
                    listIndentStack.removeAll()
                    let headers = headerCellsRaw.map { parseInlines($0, referenceLinks: context.referenceLinks) }
                    index += 2
                    var rows: [[[MarkdownInline]]] = []
                    while index < lines.count {
                        let rowTrim = lines[index].trimmingCharacters(in: .whitespaces)
                        if rowTrim.isEmpty || !rowTrim.contains("|") {
                            break
                        }
                        if isBlockOpenerLine(rowTrim, leadingSpaces: 0) {
                            break
                        }
                        var rawCells = splitTableCells(rowTrim)
                        if rawCells.count < headers.count {
                            rawCells.append(contentsOf: Array(repeating: "", count: headers.count - rawCells.count))
                        } else if rawCells.count > headers.count {
                            rawCells = Array(rawCells.prefix(headers.count))
                        }
                        rows.append(rawCells.map { parseInlines($0, referenceLinks: context.referenceLinks) })
                        index += 1
                    }
                    blocks.append(
                        .table(
                            id: allocateId(&nextId),
                            headers: headers,
                            alignments: alignments,
                            rows: rows
                        )
                    )
                    continue
                }
            }

            // 16. List Item (`- `, `* `, `+ `, `1. `, `1) `, `- [x] `, `- [ ] `)
            if let listMatch = matchListItem(trimmedLead) {
                let indentLevel = resolveListIndentLevel(spaces: leadingSpaces, stack: &listIndentStack)
                var itemLines: [String] = [listMatch.content]
                index += 1

                // Absorb indented continuation lines that aren't sub-lists or block openers
                while index < lines.count {
                    let nextRaw = lines[index]
                    let nextExpanded = expandLeadingTabs(nextRaw)
                    let nextSpaces = countLeadingSpaces(nextExpanded)
                    let nextTrimLead = String(nextExpanded.dropFirst(nextSpaces))
                    let nextTrim = nextTrimLead.trimmingCharacters(in: .whitespaces)

                    if nextTrim.isEmpty {
                        break
                    }
                    if isBlockOpenerLine(nextTrimLead, leadingSpaces: 0)
                        || matchListItem(nextTrimLead) != nil {
                        break
                    }
                    if nextSpaces > leadingSpaces {
                        itemLines.append(nextTrim)
                        index += 1
                    } else {
                        break
                    }
                }

                let joinedContent = itemLines.joined(separator: "\n")
                let splitBlocks = splitInlineEmbedBlocks(
                    from: joinedContent,
                    nextId: &nextId,
                    context: context
                ) { textChunk, id in
                    .listItem(
                        id: id,
                        indentLevel: indentLevel,
                        marker: listMatch.marker,
                        inlines: parseInlines(textChunk, referenceLinks: context.referenceLinks)
                    )
                }
                blocks.append(contentsOf: splitBlocks)
                continue
            }

            // 17. Setext Heading (`Heading\n===` or `Subheading\n---`)
            if leadingSpaces < 4,
               index + 1 < lines.count,
               let setextLevel = matchSetextUnderline(lines[index + 1]) {
                listIndentStack.removeAll()
                blocks.append(
                    .heading(
                        id: allocateId(&nextId),
                        level: setextLevel,
                        inlines: parseInlines(trimmed, referenceLinks: context.referenceLinks)
                    )
                )
                index += 2
                continue
            }

            // 18. Paragraph (preserves GFM chat line breaks until blank line or block opener)
            listIndentStack.removeAll()
            var paragraphLines: [String] = [unwrapSimpleHTMLParagraphWrapper(trimmed)]
            index += 1
            while index < lines.count {
                let pExpanded = expandLeadingTabs(lines[index])
                let pSpaces = countLeadingSpaces(pExpanded)
                let pTrimLead = String(pExpanded.dropFirst(pSpaces))
                let pTrim = pTrimLead.trimmingCharacters(in: .whitespaces)

                if pTrim.isEmpty {
                    break
                }
                if isBlockOpenerLine(pTrimLead, leadingSpaces: pSpaces)
                    || matchListItem(pTrimLead) != nil {
                    break
                }
                if pSpaces < 4,
                   index + 1 < lines.count,
                   pTrim.contains("|"),
                   let alignCheck = parseTableDelimiterRow(lines[index + 1]),
                   splitTableCells(pTrim).count == alignCheck.count {
                    break
                }
                if pSpaces < 4, matchSetextUnderline(pTrim) != nil {
                    break
                }
                paragraphLines.append(stripHardBreakSuffix(unwrapSimpleHTMLParagraphWrapper(pTrim)))
                index += 1
            }
            if !paragraphLines.isEmpty {
                paragraphLines[0] = stripHardBreakSuffix(paragraphLines[0])
            }
            let joinedParagraph = paragraphLines.joined(separator: "\n")
            let splitParagraph = splitInlineEmbedBlocks(
                from: joinedParagraph,
                nextId: &nextId,
                context: context
            ) { textChunk, id in
                .paragraph(
                    id: id,
                    inlines: parseInlines(textChunk, referenceLinks: context.referenceLinks)
                )
            }
            blocks.append(contentsOf: splitParagraph)
        }

        return blocks
    }

    /// Detects if an inline paragraph or list item contains embedded `<agent-embed ...>` or `<plugin-card ...>`
    /// tags (even without surrounding blank lines) and promotes them into first-class sibling blocks.
    private static func splitInlineEmbedBlocks(
        from text: String,
        nextId: inout Int,
        context: ParseContext,
        makeTextBlock: (String, Int) -> MarkdownBlock
    ) -> [MarkdownBlock] {
        let lower = text.lowercased()
        guard lower.contains("<agent-embed") || lower.contains("<plugin-card") else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return [makeTextBlock(text, allocateId(&nextId))]
        }

        var result: [MarkdownBlock] = []
        var cursor = text.startIndex
        var emittedPrimary = false

        while cursor < text.endIndex {
            let remaining = text[cursor...]
            let nextEmbed = findNextCustomEmbedTag(in: remaining)
            guard let found = nextEmbed else {
                let tail = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty {
                    let block: MarkdownBlock = emittedPrimary
                        ? .paragraph(id: allocateId(&nextId), inlines: parseInlines(tail, referenceLinks: context.referenceLinks))
                        : makeTextBlock(tail, allocateId(&nextId))
                    result.append(block)
                    emittedPrimary = true
                }
                break
            }

            let prefix = String(text[cursor..<found.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                let block: MarkdownBlock = emittedPrimary
                    ? .paragraph(id: allocateId(&nextId), inlines: parseInlines(prefix, referenceLinks: context.referenceLinks))
                    : makeTextBlock(prefix, allocateId(&nextId))
                result.append(block)
                emittedPrimary = true
            }

            if found.tagName == "agent-embed" {
                let src = found.attributes["src"] ?? found.attributes["href"] ?? found.attributes["url"] ?? ""
                let title = found.attributes["title"] ?? found.attributes["alt"] ?? found.attributes["label"]
                result.append(
                    .agentEmbed(
                        id: allocateId(&nextId),
                        src: src,
                        title: title,
                        kind: MarkdownEmbedKind.detect(from: src),
                        attributes: found.attributes,
                        isStreamingIncomplete: found.isIncomplete
                    )
                )
            } else if found.tagName == "plugin-card" {
                let catalogId = found.attributes["catalog-id"]
                    ?? found.attributes["catalogid"]
                    ?? found.attributes["id"]
                    ?? "plugin"
                let title = found.attributes["title"] ?? found.attributes["name"]
                result.append(.pluginCard(id: allocateId(&nextId), catalogId: catalogId, title: title))
            }

            cursor = found.range.upperBound
        }

        return result
    }

    private static func isBlockOpenerLine(_ trimmedLead: String, leadingSpaces: Int) -> Bool {
        let trimmed = trimmedLead.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        if matchCodeFenceOpening(trimmedLead) != nil { return true }
        if trimmed.hasPrefix("$$") || trimmed.hasPrefix("\\[") { return true }
        if leadingSpaces < 4 && matchATXHeading(trimmedLead) != nil { return true }
        if leadingSpaces < 4 && isThematicBreak(trimmed) { return true }
        if leadingSpaces < 4 && trimmedLead.hasPrefix(">") { return true }
        if hasCaseInsensitivePrefix(trimmed, "<agent-embed")
            || hasCaseInsensitivePrefix(trimmed, "<plugin-card")
            || hasCaseInsensitivePrefix(trimmed, "<details")
            || hasCaseInsensitivePrefix(trimmed, "<table")
            || hasCaseInsensitivePrefix(trimmed, "<pre")
            || hasCaseInsensitivePrefix(trimmed, "<figure")
            || hasCaseInsensitivePrefix(trimmed, "<blockquote")
            || hasCaseInsensitivePrefix(trimmed, "<ul")
            || hasCaseInsensitivePrefix(trimmed, "<ol")
            || trimmed.hasPrefix("<!--")
            || isHTMLHorizontalRule(trimmed)
            || matchHTMLHeadingLine(trimmed) != nil
            || (hasCaseInsensitivePrefix(trimmed, "<img") && extractStandaloneHTMLImg(trimmed) != nil)
            || matchStandaloneMarkdownImage(trimmed, referenceLinks: [:]) != nil {
            return true
        }
        return false
    }

    // MARK: - Inline Parsing

    public static func parseInlines(_ text: String) -> [MarkdownInline] {
        parseInlines(text, referenceLinks: [:])
    }

    private static func parseInlines(_ text: String, referenceLinks: [String: String]) -> [MarkdownInline] {
        guard !text.isEmpty else { return [] }
        let chars = Array(text)
        return coalesceTextNodes(parseInlineSlice(chars, start: 0, end: chars.count, referenceLinks: referenceLinks))
    }

    private static func parseInlineSlice(
        _ chars: [Character],
        start: Int,
        end: Int,
        referenceLinks: [String: String]
    ) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        var i = start

        while i < end {
            let ch = chars[i]

            // 1. Newline -> softBreak
            if ch == "\n" {
                result.append(.softBreak)
                i += 1
                continue
            }

            // 2. Backslash escape (`\*`, `\_`, `\$`, `\[`, etc.) or `\( ... \)` inline math
            if ch == "\\" && i + 1 < end {
                let nextCh = chars[i + 1]
                if nextCh == "(" {
                    if let closeIdx = findSequence(chars, target: ["\\", ")"], from: i + 2, end: end, stopAtNewline: true) {
                        let latex = String(chars[(i + 2)..<closeIdx]).trimmingCharacters(in: .whitespaces)
                        if !latex.isEmpty {
                            result.append(.inlineMath(latex))
                            i = closeIdx + 2
                            continue
                        }
                    }
                }
                if asciiPunctuation.contains(nextCh) {
                    result.append(.text(String(nextCh)))
                    i += 2
                    continue
                }
            }

            // 3. Inline code span (1+ backticks, highest precedence — no HTML/entity decoding inside!)
            if ch == "`" {
                var tickCount = 0
                while i + tickCount < end && chars[i + tickCount] == "`" {
                    tickCount += 1
                }
                let contentStart = i + tickCount
                if let closeStart = findExactBacktickRun(chars, length: tickCount, from: contentStart, end: end) {
                    var codeStr = String(chars[contentStart..<closeStart])
                        .replacingOccurrences(of: "\n", with: " ")
                    if codeStr.count >= 2 && codeStr.first == " " && codeStr.last == " " && !codeStr.allSatisfy({ $0 == " " }) {
                        codeStr.removeFirst()
                        codeStr.removeLast()
                    }
                    result.append(.code(codeStr))
                    i = closeStart + tickCount
                    continue
                } else {
                    result.append(.text(String(repeating: "`", count: tickCount)))
                    i = contentStart
                    continue
                }
            }

            // 4. Inline HTML, Comments, Autolinks `<https://...>` (safely preserves generics like `Array<String>`!)
            if ch == "<" {
                if let htmlResult = parseInlineHTMLOrAutolink(chars, at: i, end: end, referenceLinks: referenceLinks) {
                    result.append(contentsOf: htmlResult.nodes)
                    i = htmlResult.nextIndex
                    continue
                }
            }

            // 5. HTML Entity (`&amp;`, `&lt;`, `&rarr;`, `&#123;`, `&#x2713;`)
            if ch == "&", let entity = decodeHTMLEntity(chars, at: i, end: end) {
                result.append(.text(entity.decoded))
                i = entity.nextIndex
                continue
            }

            // 6. Footnote Reference (`[^1]`)
            if ch == "[", i + 2 < end, chars[i + 1] == "^",
               let closeIdx = findSimpleBracketClose(chars, from: i + 2, end: end) {
                let label = String(chars[(i + 2)..<closeIdx]).trimmingCharacters(in: .whitespaces)
                if !label.isEmpty && !label.contains(where: \.isWhitespace) {
                    result.append(.footnoteRef(label))
                    i = closeIdx + 1
                    continue
                }
            }

            // 7. Image `![alt](src)` or Link `[label](destination)` or Reference Link `[label][ref]`
            if ch == "[" || (ch == "!" && i + 1 < end && chars[i + 1] == "[") {
                let isImage = (ch == "!")
                let openBracket = isImage ? i + 1 : i
                if let closeBracket = findMatchingBracket(chars, openAt: openBracket, end: end) {
                    // 7a. Inline destination `[label](dest)` or `![alt](dest)`
                    if closeBracket + 1 < end,
                       chars[closeBracket + 1] == "(",
                       let parsedDest = parseLinkDestination(chars, openParenAt: closeBracket + 1, end: end) {
                        if isImage {
                            let altText = String(chars[(openBracket + 1)..<closeBracket])
                            result.append(.inlineImage(alt: altText, src: parsedDest.destination))
                        } else {
                            let rawLabelSlice = parseInlineSlice(chars, start: openBracket + 1, end: closeBracket, referenceLinks: referenceLinks)
                            let labelNodes = coalesceTextNodes(rawLabelSlice)
                            let effectiveLabel: [MarkdownInline] = labelNodes.isEmpty ? [.text(parsedDest.destination)] : labelNodes
                            result.append(.link(label: effectiveLabel, destination: parsedDest.destination))
                        }
                        i = parsedDest.nextIndex
                        continue
                    }

                    // 7b. Reference link `[label][ref]` or collapsed `[label][]`
                    if !isImage, !referenceLinks.isEmpty,
                       closeBracket + 1 < end, chars[closeBracket + 1] == "[",
                       let refClose = findMatchingBracket(chars, openAt: closeBracket + 1, end: end) {
                        let rawRef = String(chars[(closeBracket + 2)..<refClose]).trimmingCharacters(in: .whitespaces)
                        let fallbackKey = String(chars[(openBracket + 1)..<closeBracket]).trimmingCharacters(in: .whitespaces)
                        let lookupKey = (rawRef.isEmpty ? fallbackKey : rawRef).lowercased()
                        if let dest = referenceLinks[lookupKey] {
                            let labelNodes = coalesceTextNodes(parseInlineSlice(chars, start: openBracket + 1, end: closeBracket, referenceLinks: referenceLinks))
                            result.append(.link(label: labelNodes.isEmpty ? [.text(dest)] : labelNodes, destination: dest))
                            i = refClose + 1
                            continue
                        }
                    }

                    // 7c. Shortcut reference link `[label]`
                    if !isImage, !referenceLinks.isEmpty {
                        let lookupKey = String(chars[(openBracket + 1)..<closeBracket]).trimmingCharacters(in: .whitespaces).lowercased()
                        if let dest = referenceLinks[lookupKey] {
                            let labelNodes = coalesceTextNodes(parseInlineSlice(chars, start: openBracket + 1, end: closeBracket, referenceLinks: referenceLinks))
                            result.append(.link(label: labelNodes.isEmpty ? [.text(dest)] : labelNodes, destination: dest))
                            i = closeBracket + 1
                            continue
                        }
                    }
                }
            }

            // 8. Bare URL autolink (`https://...` or `http://...`)
            if (ch == "h" || ch == "H"),
               let bareURL = matchBareHTTPURL(chars, at: i, end: end) {
                result.append(.link(label: [.text(bareURL.url)], destination: bareURL.url))
                i = bareURL.nextIndex
                continue
            }

            // 9. Strikethrough (`~~...~~`)
            if ch == "~" && i + 1 < end && chars[i + 1] == "~" {
                let innerStart = i + 2
                if innerStart < end && !chars[innerStart].isWhitespace,
                   let closeIdx = findDelimiterOutsideCode(chars, delimiter: ["~", "~"], from: innerStart, end: end),
                   closeIdx > innerStart,
                   !chars[closeIdx - 1].isWhitespace {
                    let inner = coalesceTextNodes(parseInlineSlice(chars, start: innerStart, end: closeIdx, referenceLinks: referenceLinks))
                    result.append(.strikethrough(inner))
                    i = closeIdx + 2
                    continue
                }
            }

            // 10. Inline Math `$...$` (Pandoc/GFM non-whitespace boundary rules)
            if ch == "$" && !(i + 1 < end && chars[i + 1] == "$") {
                let innerStart = i + 1
                let prevIsDigit = (i > start && chars[i - 1].isNumber)
                if !prevIsDigit && innerStart < end && !chars[innerStart].isWhitespace,
                   let closeIdx = findClosingInlineMathDollar(chars, from: innerStart, end: end) {
                    let afterCloseIsDigit = (closeIdx + 1 < end && chars[closeIdx + 1].isNumber)
                    if !afterCloseIsDigit {
                        let latex = String(chars[innerStart..<closeIdx])
                        result.append(.inlineMath(latex))
                        i = closeIdx + 1
                        continue
                    }
                }
            }

            // 11. Emphasis & Strong (`***`, `**`, `*`, `___`, `__`, `_`)
            if ch == "*" || ch == "_" {
                var runLen = 0
                while i + runLen < end && chars[i + runLen] == ch {
                    runLen += 1
                }
                let prevChar: Character? = i > start ? chars[i - 1] : nil
                let afterRunIdx = i + runLen
                let nextChar: Character? = afterRunIdx < end ? chars[afterRunIdx] : nil

                // GFM intraword underscore protection: `mock_language_server` stays literal text
                let intrawordBlocked = (ch == "_")
                    && (prevChar.map(isWordChar) == true)
                    && (nextChar.map(isWordChar) == true || (i + 1 < end && isWordChar(chars[i + 1])))

                if !intrawordBlocked {
                    if runLen >= 3,
                       afterRunIdx < end,
                       !chars[afterRunIdx].isWhitespace,
                       let closeIdx = findEmphasisClose(chars, marker: ch, count: 3, from: afterRunIdx, end: end) {
                        let inner = coalesceTextNodes(parseInlineSlice(chars, start: afterRunIdx, end: closeIdx, referenceLinks: referenceLinks))
                        result.append(.strong([.emphasis(inner)]))
                        i = closeIdx + 3
                        continue
                    }

                    if runLen == 2,
                       afterRunIdx < end,
                       !chars[afterRunIdx].isWhitespace,
                       let closeIdx = findEmphasisClose(chars, marker: ch, count: 2, from: afterRunIdx, end: end) {
                        let inner = coalesceTextNodes(parseInlineSlice(chars, start: afterRunIdx, end: closeIdx, referenceLinks: referenceLinks))
                        result.append(.strong(inner))
                        i = closeIdx + 2
                        continue
                    }

                    if runLen == 1,
                       afterRunIdx < end,
                       !chars[afterRunIdx].isWhitespace,
                       let closeIdx = findEmphasisClose(chars, marker: ch, count: 1, from: afterRunIdx, end: end) {
                        let inner = coalesceTextNodes(parseInlineSlice(chars, start: afterRunIdx, end: closeIdx, referenceLinks: referenceLinks))
                        result.append(.emphasis(inner))
                        i = closeIdx + 1
                        continue
                    }
                }

                result.append(.text(String(repeating: String(ch), count: runLen)))
                i = afterRunIdx
                continue
            }

            // 12. Plain character
            result.append(.text(String(ch)))
            i += 1
        }

        return result
    }

    // MARK: - Inline HTML, Autolinks & Entities

    private static func parseInlineHTMLOrAutolink(
        _ chars: [Character],
        at start: Int,
        end: Int,
        referenceLinks: [String: String]
    ) -> (nodes: [MarkdownInline], nextIndex: Int)? {
        // 1. Inline HTML comment `<!-- ... -->`
        if start + 4 <= end,
           chars[start + 1] == "!",
           chars[start + 2] == "-",
           chars[start + 3] == "-" {
            if let closeIdx = findSequence(chars, target: ["-", "-", ">"], from: start + 4, end: end, stopAtNewline: false) {
                return ([], closeIdx + 3)
            }
            return nil
        }

        // Find closing `>` respecting quoted attribute values
        guard let gtIdx = findTagClosingBracket(chars, openAt: start, end: end) else {
            return nil
        }
        let rawInside = String(chars[(start + 1)..<gtIdx]).trimmingCharacters(in: .whitespaces)
        guard !rawInside.isEmpty else { return nil }

        // 2. Autolink `<https://...>`, `<http://...>`, `<mailto:...>`
        let lowerInside = rawInside.lowercased()
        if !rawInside.contains(where: \.isWhitespace) {
            if lowerInside.hasPrefix("https://") || lowerInside.hasPrefix("http://") {
                return ([.link(label: [.text(rawInside)], destination: rawInside)], gtIdx + 1)
            }
            if lowerInside.hasPrefix("mailto:") {
                let label = String(rawInside.dropFirst("mailto:".count))
                return ([.link(label: [.text(label.isEmpty ? rawInside : label)], destination: rawInside)], gtIdx + 1)
            }
        }

        // 3. Closing tag (stray `</span>`, `</p>`, etc. — strip only if known HTML or hyphenated custom tag)
        if rawInside.hasPrefix("/") {
            let tag = String(rawInside.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()
            if knownInlineHTMLTags.contains(tag) || knownBlockHTMLTags.contains(tag) || isHyphenatedCustomTagName(tag) {
                return ([], gtIdx + 1)
            }
            return nil
        }

        // 4. Parse opening / self-closing tag name & attributes
        let isSelfClosing = rawInside.hasSuffix("/")
        let tagContent = isSelfClosing ? String(rawInside.dropLast()).trimmingCharacters(in: .whitespaces) : rawInside
        let (tagName, attrs) = parseTagNameAndAttributes(tagContent)
        let lowerTag = tagName.lowercased()
        guard !lowerTag.isEmpty else { return nil }

        // Guard against programming generics (`Array<String>`, `Result<T, Error>`):
        // Require either a known HTML tag OR a lowercase hyphenated custom element (`<foo-bar>`).
        let isKnownInline = knownInlineHTMLTags.contains(lowerTag)
        let isKnownBlock = knownBlockHTMLTags.contains(lowerTag)
        let isCustomElement = isHyphenatedCustomTagName(lowerTag) && tagName == lowerTag
        guard isKnownInline || isKnownBlock || isCustomElement else {
            return nil
        }

        // Void / self-closing tags
        if lowerTag == "br" {
            return ([.softBreak], gtIdx + 1)
        }
        if lowerTag == "wbr" {
            return ([], gtIdx + 1)
        }
        if lowerTag == "img" {
            let src = attrs["src"] ?? ""
            let alt = attrs["alt"] ?? attrs["title"] ?? ""
            guard !src.isEmpty else { return ([], gtIdx + 1) }
            return ([.inlineImage(alt: alt, src: src)], gtIdx + 1)
        }
        if isSelfClosing {
            return ([], gtIdx + 1)
        }

        // Paired inline tags: find matching `</tagName>`
        let bodyStart = gtIdx + 1
        if let closeRange = findClosingHTMLTag(chars, tagName: lowerTag, from: bodyStart, end: end) {
            let innerText = String(chars[bodyStart..<closeRange.openStart])
            let nextIdx = closeRange.afterClose

            switch lowerTag {
            case "b", "strong":
                let children = coalesceTextNodes(parseInlineSlice(chars, start: bodyStart, end: closeRange.openStart, referenceLinks: referenceLinks))
                return ([.strong(children)], nextIdx)
            case "i", "em", "cite", "var":
                let children = coalesceTextNodes(parseInlineSlice(chars, start: bodyStart, end: closeRange.openStart, referenceLinks: referenceLinks))
                return ([.emphasis(children)], nextIdx)
            case "s", "del", "strike":
                let children = coalesceTextNodes(parseInlineSlice(chars, start: bodyStart, end: closeRange.openStart, referenceLinks: referenceLinks))
                return ([.strikethrough(children)], nextIdx)
            case "u", "ins":
                let children = coalesceTextNodes(parseInlineSlice(chars, start: bodyStart, end: closeRange.openStart, referenceLinks: referenceLinks))
                return ([.underline(children)], nextIdx)
            case "mark":
                let children = coalesceTextNodes(parseInlineSlice(chars, start: bodyStart, end: closeRange.openStart, referenceLinks: referenceLinks))
                return ([.highlight(children)], nextIdx)
            case "code", "samp":
                return ([.code(decodeEntitiesInString(innerText))], nextIdx)
            case "kbd":
                return ([.keyboardKey(decodeEntitiesInString(innerText))], nextIdx)
            case "sup":
                return ([.superscript(decodeEntitiesInString(innerText))], nextIdx)
            case "sub":
                return ([.subscriptText(decodeEntitiesInString(innerText))], nextIdx)
            case "a":
                let dest = attrs["href"] ?? ""
                let labelChildren = coalesceTextNodes(parseInlineSlice(chars, start: bodyStart, end: closeRange.openStart, referenceLinks: referenceLinks))
                if !dest.isEmpty {
                    return ([.link(label: labelChildren.isEmpty ? [.text(dest)] : labelChildren, destination: dest)], nextIdx)
                }
                return (labelChildren, nextIdx)
            default:
                // `<span>`, `<small>`, `<abbr>`, `<q>`, or custom wrapper tags -> cleanly preserve inner content
                let children = coalesceTextNodes(parseInlineSlice(chars, start: bodyStart, end: closeRange.openStart, referenceLinks: referenceLinks))
                return (children, nextIdx)
            }
        }

        // Unclosed known wrapper tag (e.g. `<span>` mid-stream) -> strip opening tag cleanly
        if isKnownInline || isKnownBlock {
            return ([], gtIdx + 1)
        }
        return nil
    }

    private static func isHyphenatedCustomTagName(_ name: String) -> Bool {
        guard name.contains("-"), let first = name.first, first.isASCII && first.isLetter else {
            return false
        }
        return name.allSatisfy { ch in
            (ch.isASCII && (ch.isLetter || ch.isNumber)) || ch == "-"
        }
    }

    private static func findTagClosingBracket(_ chars: [Character], openAt: Int, end: Int) -> Int? {
        var i = openAt + 1
        var activeQuote: Character? = nil
        while i < end {
            let ch = chars[i]
            if let q = activeQuote {
                if ch == q { activeQuote = nil }
            } else {
                if ch == "\"" || ch == "'" {
                    activeQuote = ch
                } else if ch == ">" {
                    return i
                } else if ch == "<" {
                    return nil
                }
            }
            i += 1
        }
        return nil
    }

    private static func findClosingHTMLTag(
        _ chars: [Character],
        tagName: String,
        from: Int,
        end: Int
    ) -> (openStart: Int, afterClose: Int)? {
        let lowerTarget = tagName.lowercased()
        var i = from
        var depth = 1

        while i < end {
            if chars[i] == "<", let gtIdx = findTagClosingBracket(chars, openAt: i, end: end) {
                let inside = String(chars[(i + 1)..<gtIdx]).trimmingCharacters(in: .whitespaces)
                if inside.hasPrefix("/") {
                    let closeName = String(inside.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()
                    if closeName == lowerTarget {
                        depth -= 1
                        if depth == 0 {
                            return (i, gtIdx + 1)
                        }
                    }
                } else if !inside.hasSuffix("/") {
                    let (openName, _) = parseTagNameAndAttributes(inside)
                    if openName.lowercased() == lowerTarget {
                        depth += 1
                    }
                }
                i = gtIdx + 1
                continue
            }
            i += 1
        }
        return nil
    }

    private static let namedHTMLEntities: [String: String] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": "\u{00A0}",
        "mdash": "—",
        "ndash": "–",
        "hellip": "…",
        "rarr": "→",
        "larr": "←",
        "harr": "↔",
        "rArr": "⇒",
        "lArr": "⇐",
        "times": "×",
        "divide": "÷",
        "plusmn": "±",
        "le": "≤",
        "ge": "≥",
        "ne": "≠",
        "approx": "≈",
        "infin": "∞",
        "copy": "©",
        "reg": "®",
        "trade": "™",
        "bull": "•",
        "middot": "·",
        "check": "✓",
        "cross": "✗",
    ]

    private static func decodeHTMLEntity(_ chars: [Character], at start: Int, end: Int) -> (decoded: String, nextIndex: Int)? {
        guard chars[start] == "&" else { return nil }
        let limit = min(end, start + 14)
        var semiIdx: Int? = nil
        var i = start + 1
        while i < limit {
            let ch = chars[i]
            if ch == ";" {
                semiIdx = i
                break
            }
            if ch.isWhitespace || ch == "&" || ch == "<" {
                return nil
            }
            i += 1
        }
        guard let semi = semiIdx, semi > start + 1 else { return nil }
        let token = String(chars[(start + 1)..<semi])
        if token.hasPrefix("#") {
            let numPart = String(token.dropFirst())
            let codePoint: UInt32?
            if numPart.hasPrefix("x") || numPart.hasPrefix("X") {
                codePoint = UInt32(numPart.dropFirst(), radix: 16)
            } else {
                codePoint = UInt32(numPart, radix: 10)
            }
            if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                return (String(scalar), semi + 1)
            }
            return nil
        }
        if let mapped = namedHTMLEntities[token] ?? namedHTMLEntities[token.lowercased()] {
            return (mapped, semi + 1)
        }
        return nil
    }

    private static func decodeEntitiesInString(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "&", let decoded = decodeHTMLEntity(chars, at: i, end: chars.count) {
                out.append(decoded.decoded)
                i = decoded.nextIndex
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    // MARK: - Antigravity Custom Tag & HTML Block Helpers

    private static func hasCaseInsensitivePrefix(_ text: String, _ prefix: String) -> Bool {
        guard text.count >= prefix.count else { return false }
        let startMatch = text.prefix(prefix.count).lowercased() == prefix.lowercased()
        guard startMatch else { return false }
        if text.count == prefix.count { return true }
        let nextCh = text[text.index(text.startIndex, offsetBy: prefix.count)]
        return nextCh.isWhitespace || nextCh == ">" || nextCh == "/"
    }

    private static func parseTagNameAndAttributes(_ rawTagContent: String) -> (name: String, attributes: [String: String]) {
        let chars = Array(rawTagContent)
        var i = 0
        while i < chars.count && chars[i].isWhitespace { i += 1 }
        let nameStart = i
        while i < chars.count && !chars[i].isWhitespace && chars[i] != "/" && chars[i] != ">" {
            i += 1
        }
        let tagName = String(chars[nameStart..<i])
        var attrs: [String: String] = [:]

        while i < chars.count {
            while i < chars.count && (chars[i].isWhitespace || chars[i] == "/") { i += 1 }
            guard i < chars.count else { break }
            let keyStart = i
            while i < chars.count && !chars[i].isWhitespace && chars[i] != "=" && chars[i] != "/" && chars[i] != ">" {
                i += 1
            }
            let key = String(chars[keyStart..<i]).lowercased()
            guard !key.isEmpty else {
                i += 1
                continue
            }
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            if i < chars.count && chars[i] == "=" {
                i += 1
                while i < chars.count && chars[i].isWhitespace { i += 1 }
                if i < chars.count && (chars[i] == "\"" || chars[i] == "'") {
                    let quote = chars[i]
                    i += 1
                    let valStart = i
                    while i < chars.count && chars[i] != quote {
                        i += 1
                    }
                    let val = decodeEntitiesInString(String(chars[valStart..<i]))
                    attrs[key] = val
                    if i < chars.count { i += 1 }
                } else {
                    let valStart = i
                    while i < chars.count && !chars[i].isWhitespace && chars[i] != ">" && chars[i] != "/" {
                        i += 1
                    }
                    attrs[key] = decodeEntitiesInString(String(chars[valStart..<i]))
                }
            } else {
                attrs[key] = "true"
            }
        }

        return (tagName, attrs)
    }

    private static func consumeCustomElementBlock(
        lines: [String],
        startIndex: Int,
        tagName: String
    ) -> (attributes: [String: String], nextIndex: Int, isIncomplete: Bool, trailingRemainder: String) {
        let lowerClose = "</\(tagName.lowercased())>"
        var combined = ""
        var idx = startIndex
        var foundOpenEnd = false
        var isSelfClosing = false
        var foundCloseTag = false

        while idx < lines.count {
            if !combined.isEmpty { combined.append("\n") }
            combined.append(lines[idx])
            idx += 1

            let chars = Array(combined)
            if !foundOpenEnd, let openStart = chars.firstIndex(of: "<"),
               let gtIdx = findTagClosingBracket(chars, openAt: openStart, end: chars.count) {
                foundOpenEnd = true
                let openInner = String(chars[(openStart + 1)..<gtIdx]).trimmingCharacters(in: .whitespaces)
                if openInner.hasSuffix("/") {
                    isSelfClosing = true
                    break
                }
                let afterOpen = String(chars[(gtIdx + 1)...])
                if afterOpen.lowercased().contains(lowerClose) {
                    foundCloseTag = true
                    break
                }
            } else if foundOpenEnd {
                if combined.lowercased().contains(lowerClose) {
                    foundCloseTag = true
                    break
                }
            }
            // Prevent runaway scan if an unclosed custom tag appears mid-document before a blank line
            if foundOpenEnd && idx < lines.count && lines[idx].trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
        }

        let chars = Array(combined)
        guard let openStart = chars.firstIndex(of: "<") else {
            return ([:], idx, true, "")
        }

        if let gtIdx = findTagClosingBracket(chars, openAt: openStart, end: chars.count) {
            let rawTag = String(chars[(openStart + 1)..<gtIdx]).trimmingCharacters(in: .whitespaces)
            let cleanedTag = rawTag.hasSuffix("/") ? String(rawTag.dropLast()).trimmingCharacters(in: .whitespaces) : rawTag
            let (_, attrs) = parseTagNameAndAttributes(cleanedTag)

            var remainder = ""
            if isSelfClosing {
                remainder = String(chars[(gtIdx + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if foundCloseTag, let closeRange = combined.range(of: lowerClose, options: .caseInsensitive) {
                remainder = String(combined[closeRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let hasSrc = !(attrs["src"] ?? attrs["href"] ?? attrs["url"] ?? "").isEmpty
            let incomplete = !isSelfClosing && !foundCloseTag && idx == lines.count && !hasSrc
            return (attrs, idx, incomplete, remainder)
        } else {
            // Streaming mid-tag (`<agent-embed src="file:///...` without `>` yet)
            let partial = String(chars[(openStart + 1)...])
            let (_, attrs) = parseTagNameAndAttributes(partial)
            return (attrs, idx, true, "")
        }
    }

    private static func findNextCustomEmbedTag(
        in slice: Substring
    ) -> (tagName: String, range: Range<String.Index>, attributes: [String: String], isIncomplete: Bool)? {
        // Scan character-by-character outside inline backtick code spans so literal `` `<agent-embed>` `` stays code.
        let subStr = String(slice)
        let chars = Array(subStr)
        var i = 0
        var matchedOffset: Int? = nil
        var matchedTagName: String = ""

        while i < chars.count {
            if chars[i] == "`" {
                var ticks = 0
                while i + ticks < chars.count && chars[i + ticks] == "`" { ticks += 1 }
                if let close = findExactBacktickRun(chars, length: ticks, from: i + ticks, end: chars.count) {
                    i = close + ticks
                    continue
                }
                i += ticks
                continue
            }
            if chars[i] == "<" {
                let tail = String(chars[i...])
                if hasCaseInsensitivePrefix(tail, "<agent-embed") {
                    matchedOffset = i
                    matchedTagName = "agent-embed"
                    break
                }
                if hasCaseInsensitivePrefix(tail, "<plugin-card") {
                    matchedOffset = i
                    matchedTagName = "plugin-card"
                    break
                }
            }
            i += 1
        }

        guard let startCharOffset = matchedOffset else { return nil }
        let origStart = slice.index(slice.startIndex, offsetBy: startCharOffset)

        if let gtIdx = findTagClosingBracket(chars, openAt: startCharOffset, end: chars.count) {
            let inside = String(chars[(startCharOffset + 1)..<gtIdx]).trimmingCharacters(in: .whitespaces)
            let isSelfClosing = inside.hasSuffix("/")
            let cleaned = isSelfClosing ? String(inside.dropLast()).trimmingCharacters(in: .whitespaces) : inside
            let (_, attrs) = parseTagNameAndAttributes(cleaned)

            if isSelfClosing {
                let consumed = (gtIdx + 1) - startCharOffset
                let endIdx = slice.index(origStart, offsetBy: consumed, limitedBy: slice.endIndex) ?? slice.endIndex
                return (matchedTagName, origStart..<endIdx, attrs, false)
            }
            let closeToken = "</\(matchedTagName)>"
            let afterOpen = String(chars[(gtIdx + 1)...])
            if let closeRange = afterOpen.range(of: closeToken, options: .caseInsensitive) {
                let closeTailCount = afterOpen.distance(from: afterOpen.startIndex, to: closeRange.upperBound)
                let consumed = ((gtIdx + 1) - startCharOffset) + closeTailCount
                let endIdx = slice.index(origStart, offsetBy: consumed, limitedBy: slice.endIndex) ?? slice.endIndex
                return (matchedTagName, origStart..<endIdx, attrs, false)
            }
            let consumed = (gtIdx + 1) - startCharOffset
            let endIdx = slice.index(origStart, offsetBy: consumed, limitedBy: slice.endIndex) ?? slice.endIndex
            return (matchedTagName, origStart..<endIdx, attrs, false)
        } else {
            // Unclosed streaming tag at end of paragraph
            let (_, attrs) = parseTagNameAndAttributes(String(chars[(startCharOffset + 1)...]))
            return (matchedTagName, origStart..<slice.endIndex, attrs, true)
        }
    }

    private static func consumeDetailsBlock(
        lines: [String],
        startIndex: Int
    ) -> (summaryText: String, innerMarkdown: String, isOpen: Bool, nextIndex: Int) {
        var collected: [String] = []
        var idx = startIndex
        var depth = 0

        while idx < lines.count {
            let line = lines[idx]
            let lower = line.lowercased()
            if lower.contains("<details") { depth += 1 }
            collected.append(line)
            if lower.contains("</details>") {
                depth -= 1
                idx += 1
                if depth <= 0 { break }
            } else {
                idx += 1
            }
        }

        let raw = collected.joined(separator: "\n")
        var isOpen = false
        var inner = raw

        let chars = Array(raw)
        if let openStart = chars.firstIndex(of: "<"),
           let gtIdx = findTagClosingBracket(chars, openAt: openStart, end: chars.count) {
            let tagInside = String(chars[(openStart + 1)..<gtIdx])
            let (_, attrs) = parseTagNameAndAttributes(tagInside)
            isOpen = (attrs["open"] != nil)
            inner = String(chars[(gtIdx + 1)...])
        }
        if let closeRange = inner.range(of: "</details>", options: [.caseInsensitive, .backwards]) {
            inner = String(inner[..<closeRange.lowerBound])
        }

        var summaryText = ""
        if let sumOpen = inner.range(of: "<summary", options: .caseInsensitive) {
            let afterSum = inner[sumOpen.lowerBound...]
            if let gt = afterSum.firstIndex(of: ">") {
                let contentStart = afterSum.index(after: gt)
                if let sumClose = afterSum.range(of: "</summary>", options: .caseInsensitive) {
                    summaryText = String(afterSum[contentStart..<sumClose.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    inner.removeSubrange(sumOpen.lowerBound..<sumClose.upperBound)
                }
            }
        }

        return (summaryText, inner.trimmingCharacters(in: .whitespacesAndNewlines), isOpen, idx)
    }

    private static func consumeHTMLTagRegion(
        lines: [String],
        startIndex: Int,
        tagName: String
    ) -> (rawHTML: String, nextIndex: Int) {
        let openToken = "<\(tagName.lowercased())"
        let closeToken = "</\(tagName.lowercased())>"
        var collected: [String] = []
        var idx = startIndex
        var depth = 0

        while idx < lines.count {
            let line = lines[idx]
            let lower = line.lowercased()
            if lower.contains(openToken) { depth += 1 }
            collected.append(line)
            if lower.contains(closeToken) {
                depth -= 1
                idx += 1
                if depth <= 0 { break }
            } else {
                idx += 1
            }
        }
        return (collected.joined(separator: "\n"), idx)
    }

    private static func parseCarouselSlides(
        _ rawBody: String,
        nextId: inout Int,
        context: ParseContext
    ) -> [[MarkdownBlock]] {
        let lines = rawBody.components(separatedBy: "\n")
        var slideBuffers: [[String]] = [[]]
        var activeNestedFence: (char: Character, length: Int)? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = activeNestedFence {
                slideBuffers[slideBuffers.count - 1].append(line)
                if isClosingCodeFence(trimmed, fenceChar: fence.char, minLength: fence.length) {
                    activeNestedFence = nil
                }
                continue
            }
            if let fence = matchCodeFenceOpening(trimmed) {
                activeNestedFence = (fence.char, fence.length)
                slideBuffers[slideBuffers.count - 1].append(line)
                continue
            }
            let lowerCompact = trimmed.lowercased().replacingOccurrences(of: " ", with: "")
            if lowerCompact == "<!--slide-->" {
                slideBuffers.append([])
            } else {
                slideBuffers[slideBuffers.count - 1].append(line)
            }
        }

        var slides: [[MarkdownBlock]] = []
        for buf in slideBuffers {
            let slideRaw = buf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !slideRaw.isEmpty else { continue }
            let slideBlocks = parseBlocks(from: slideRaw, nextId: &nextId, context: context)
            if !slideBlocks.isEmpty {
                slides.append(slideBlocks)
            }
        }
        return slides
    }

    private static func parseHTMLTable(
        _ rawHTML: String,
        referenceLinks: [String: String]
    ) -> (headers: [[MarkdownInline]], alignments: [MarkdownTableAlignment], rows: [[[MarkdownInline]]])? {
        let trMatches = extractAllTagBodies(in: rawHTML, tagName: "tr")
        guard !trMatches.isEmpty else { return nil }

        var headers: [[MarkdownInline]] = []
        var rows: [[[MarkdownInline]]] = []

        for (rowIdx, trBody) in trMatches.enumerated() {
            let thCells = extractAllTagBodies(in: trBody, tagName: "th")
            let tdCells = extractAllTagBodies(in: trBody, tagName: "td")
            if !thCells.isEmpty && headers.isEmpty {
                headers = thCells.map { parseInlines($0.trimmingCharacters(in: .whitespacesAndNewlines), referenceLinks: referenceLinks) }
            } else if !tdCells.isEmpty {
                let parsedRow = tdCells.map { parseInlines($0.trimmingCharacters(in: .whitespacesAndNewlines), referenceLinks: referenceLinks) }
                if headers.isEmpty && rowIdx == 0 {
                    headers = parsedRow
                } else {
                    rows.append(parsedRow)
                }
            }
        }

        guard !headers.isEmpty else { return nil }
        let colCount = headers.count
        let normalizedRows: [[[MarkdownInline]]] = rows.map { row in
            if row.count < colCount {
                return row + Array(repeating: [], count: colCount - row.count)
            }
            return Array(row.prefix(colCount))
        }
        return (headers, Array(repeating: .leading, count: colCount), normalizedRows)
    }

    private static func extractAllTagBodies(in html: String, tagName: String) -> [String] {
        var results: [String] = []
        let chars = Array(html)
        let target = tagName.lowercased()
        var i = 0

        while i < chars.count {
            if chars[i] == "<", let gt = findTagClosingBracket(chars, openAt: i, end: chars.count) {
                let inside = String(chars[(i + 1)..<gt]).trimmingCharacters(in: .whitespaces)
                if !inside.hasPrefix("/") && !inside.hasSuffix("/") {
                    let (name, _) = parseTagNameAndAttributes(inside)
                    if name.lowercased() == target,
                       let close = findClosingHTMLTag(chars, tagName: target, from: gt + 1, end: chars.count) {
                        results.append(String(chars[(gt + 1)..<close.openStart]))
                        i = close.afterClose
                        continue
                    }
                }
                i = gt + 1
                continue
            }
            i += 1
        }
        return results
    }

    private static func extractPreCodeBlock(_ rawHTML: String) -> (language: String?, code: String) {
        var inner = stripOuterHTMLTag(rawHTML, tagName: "pre")
        var lang: String? = nil
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasCaseInsensitivePrefix(trimmed, "<code") {
            let chars = Array(trimmed)
            if let gt = findTagClosingBracket(chars, openAt: 0, end: chars.count) {
                let (_, attrs) = parseTagNameAndAttributes(String(chars[1..<gt]))
                if let cls = attrs["class"] {
                    for part in cls.split(whereSeparator: \.isWhitespace) {
                        if part.hasPrefix("language-") {
                            lang = String(part.dropFirst("language-".count))
                        } else if part.hasPrefix("lang-") {
                            lang = String(part.dropFirst("lang-".count))
                        }
                    }
                }
                inner = stripOuterHTMLTag(trimmed, tagName: "code")
            }
        }
        return (lang, decodeEntitiesInString(inner))
    }

    private static func extractImageFromHTML(_ rawHTML: String) -> (alt: String, src: String, title: String?)? {
        let chars = Array(rawHTML)
        var i = 0
        var foundImg: (alt: String, src: String, title: String?)? = nil
        while i < chars.count {
            if chars[i] == "<", let gt = findTagClosingBracket(chars, openAt: i, end: chars.count) {
                let inside = String(chars[(i + 1)..<gt]).trimmingCharacters(in: .whitespaces)
                let cleaned = inside.hasSuffix("/") ? String(inside.dropLast()) : inside
                let (name, attrs) = parseTagNameAndAttributes(cleaned)
                if name.lowercased() == "img", let src = attrs["src"], !src.isEmpty {
                    foundImg = (attrs["alt"] ?? "", src, attrs["title"])
                    break
                }
                i = gt + 1
                continue
            }
            i += 1
        }
        guard var img = foundImg else { return nil }
        if let caption = extractAllTagBodies(in: rawHTML, tagName: "figcaption").first {
            let cleanCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanCaption.isEmpty && img.alt.isEmpty {
                img.alt = cleanCaption
            } else if !cleanCaption.isEmpty && img.title == nil {
                img.title = cleanCaption
            }
        }
        return img
    }

    private static func extractStandaloneHTMLImg(_ trimmed: String) -> (alt: String, src: String, title: String?)? {
        let chars = Array(trimmed)
        guard chars.first == "<",
              let gt = findTagClosingBracket(chars, openAt: 0, end: chars.count),
              gt == chars.count - 1 else {
            return nil
        }
        let inside = String(chars[1..<gt]).trimmingCharacters(in: .whitespaces)
        let cleaned = inside.hasSuffix("/") ? String(inside.dropLast()).trimmingCharacters(in: .whitespaces) : inside
        let (name, attrs) = parseTagNameAndAttributes(cleaned)
        guard name.lowercased() == "img", let src = attrs["src"], !src.isEmpty else { return nil }
        return (attrs["alt"] ?? "", src, attrs["title"])
    }

    private static func matchStandaloneMarkdownImage(
        _ trimmed: String,
        referenceLinks: [String: String]
    ) -> (alt: String, src: String, title: String?)? {
        guard trimmed.hasPrefix("![") else { return nil }
        let chars = Array(trimmed)
        guard let closeBracket = findMatchingBracket(chars, openAt: 1, end: chars.count) else { return nil }
        let alt = String(chars[2..<closeBracket])
        if closeBracket + 1 < chars.count,
           chars[closeBracket + 1] == "(",
           let dest = parseLinkDestination(chars, openParenAt: closeBracket + 1, end: chars.count),
           dest.nextIndex == chars.count {
            return (alt, dest.destination, nil)
        }
        if !referenceLinks.isEmpty,
           closeBracket + 1 < chars.count,
           chars[closeBracket + 1] == "[",
           let refClose = findMatchingBracket(chars, openAt: closeBracket + 1, end: chars.count),
           refClose == chars.count - 1 {
            let key = String(chars[(closeBracket + 2)..<refClose]).trimmingCharacters(in: .whitespaces).lowercased()
            if let src = referenceLinks[key.isEmpty ? alt.lowercased() : key] {
                return (alt, src, nil)
            }
        }
        return nil
    }

    private static func isHTMLHorizontalRule(_ trimmed: String) -> Bool {
        let lower = trimmed.lowercased()
        return lower == "<hr>" || lower == "<hr/>" || lower == "<hr />"
    }

    private static func matchHTMLHeadingLine(_ trimmed: String) -> (level: Int, content: String)? {
        let lower = trimmed.lowercased()
        for level in 1...6 {
            let prefix = "<h\(level)"
            let closeTag = "</h\(level)>"
            if hasCaseInsensitivePrefix(lower, prefix), lower.hasSuffix(closeTag) {
                let chars = Array(trimmed)
                if let gt = findTagClosingBracket(chars, openAt: 0, end: chars.count) {
                    let bodyEnd = chars.count - closeTag.count
                    if bodyEnd >= gt + 1 {
                        return (level, String(chars[(gt + 1)..<bodyEnd]).trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        }
        return nil
    }

    private static func extractHTMLListItems(_ rawHTML: String) -> [String] {
        extractAllTagBodies(in: rawHTML, tagName: "li").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func stripOuterHTMLTag(_ rawHTML: String, tagName: String) -> String {
        let trimmed = rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(trimmed)
        var inner = trimmed
        if chars.first == "<", let gt = findTagClosingBracket(chars, openAt: 0, end: chars.count) {
            inner = String(chars[(gt + 1)...])
        }
        let closeToken = "</\(tagName.lowercased())>"
        if let closeRange = inner.range(of: closeToken, options: [.caseInsensitive, .backwards]) {
            inner = String(inner[..<closeRange.lowerBound])
        }
        return inner
    }

    private static func unwrapSimpleHTMLParagraphWrapper(_ trimmed: String) -> String {
        let lower = trimmed.lowercased()
        if hasCaseInsensitivePrefix(lower, "<p") && lower.hasSuffix("</p>") {
            return stripOuterHTMLTag(trimmed, tagName: "p").trimmingCharacters(in: .whitespaces)
        }
        if hasCaseInsensitivePrefix(lower, "<div") && lower.hasSuffix("</div>") {
            return stripOuterHTMLTag(trimmed, tagName: "div").trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private static func matchSetextUnderline(_ rawLine: String) -> Int? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        if trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    // MARK: - Block Helpers

    private static func allocateId(_ counter: inout Int) -> Int {
        defer { counter += 1 }
        return counter
    }

    private static func expandLeadingTabs(_ line: String) -> String {
        var prefix = ""
        var idx = line.startIndex
        while idx < line.endIndex {
            let c = line[idx]
            if c == "\t" {
                prefix.append("    ")
                idx = line.index(after: idx)
            } else if c == " " {
                prefix.append(" ")
                idx = line.index(after: idx)
            } else {
                break
            }
        }
        return prefix + line[idx...]
    }

    private static func countLeadingSpaces(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 } else { break }
        }
        return count
    }

    private static func stripUpToLeadingSpaces(_ line: String, maxSpaces: Int) -> String {
        guard maxSpaces > 0 else { return line }
        var removed = 0
        var idx = line.startIndex
        while idx < line.endIndex && removed < maxSpaces && line[idx] == " " {
            removed += 1
            idx = line.index(after: idx)
        }
        return String(line[idx...])
    }

    private static func stripHardBreakSuffix(_ line: String) -> String {
        if line.hasSuffix("\\") && !line.hasSuffix("\\\\") {
            return String(line.dropLast())
        }
        return line
    }

    private static func matchCodeFenceOpening(_ trimmedLead: String) -> (char: Character, length: Int, language: String?)? {
        guard let first = trimmedLead.first, first == "`" || first == "~" else { return nil }
        var len = 0
        for ch in trimmedLead {
            if ch == first { len += 1 } else { break }
        }
        guard len >= 3 else { return nil }
        let info = String(trimmedLead.dropFirst(len)).trimmingCharacters(in: .whitespaces)
        if first == "`" && info.contains("`") {
            return nil
        }
        let langToken = info.split(whereSeparator: \.isWhitespace).first.map(String.init)
        return (first, len, (langToken?.isEmpty == false) ? langToken : nil)
    }

    private static func isClosingCodeFence(_ trimmed: String, fenceChar: Character, minLength: Int) -> Bool {
        guard trimmed.count >= minLength else { return false }
        var len = 0
        for ch in trimmed {
            if ch == fenceChar { len += 1 } else { return false }
        }
        return len >= minLength
    }

    private static func matchATXHeading(_ trimmedLead: String) -> (level: Int, content: String)? {
        guard trimmedLead.first == "#" else { return nil }
        var level = 0
        for ch in trimmedLead {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = String(trimmedLead.dropFirst(level))
        guard rest.isEmpty || rest.first?.isWhitespace == true else { return nil }
        var cleaned = rest.trimmingCharacters(in: .whitespaces)
        while cleaned.last == "#" {
            let candidate = String(cleaned.dropLast())
            if candidate.isEmpty || candidate.last?.isWhitespace == true {
                cleaned = candidate.trimmingCharacters(in: .whitespaces)
            } else {
                break
            }
        }
        return (level, cleaned)
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else {
            return false
        }
        var markerCount = 0
        for ch in trimmed {
            if ch == first {
                markerCount += 1
            } else if ch == " " || ch == "\t" {
                continue
            } else {
                return false
            }
        }
        return markerCount >= 3
    }

    private static func matchListItem(_ trimmedLead: String) -> (marker: MarkdownListMarker, content: String)? {
        guard !trimmedLead.isEmpty else { return nil }
        let chars = Array(trimmedLead)

        if (chars[0] == "-" || chars[0] == "*" || chars[0] == "+"),
           chars.count >= 2,
           chars[1].isWhitespace {
            if isThematicBreak(trimmedLead.trimmingCharacters(in: .whitespaces)) {
                return nil
            }
            let afterBullet = String(chars.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if afterBullet.count >= 3 && afterBullet.hasPrefix("[") {
                let abChars = Array(afterBullet)
                if abChars.count >= 3 && abChars[2] == "]" && (abChars.count == 3 || abChars[3].isWhitespace) {
                    let box = abChars[1]
                    if box == " " || box == "x" || box == "X" {
                        let taskBody = abChars.count > 4
                            ? String(abChars.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                            : ""
                        return (.task(checked: box != " "), taskBody)
                    }
                }
            }
            return (.bullet, afterBullet)
        }

        var digitCount = 0
        while digitCount < chars.count && digitCount < 9 && chars[digitCount].isASCII && chars[digitCount].isNumber {
            digitCount += 1
        }
        if digitCount > 0,
           digitCount + 1 < chars.count,
           (chars[digitCount] == "." || chars[digitCount] == ")"),
           chars[digitCount + 1].isWhitespace {
            let numberStr = String(chars[0..<digitCount])
            if let num = Int(numberStr) {
                let body = String(chars.dropFirst(digitCount + 2)).trimmingCharacters(in: .whitespaces)
                return (.ordered(num), body)
            }
        }

        return nil
    }

    private static func resolveListIndentLevel(spaces: Int, stack: inout [Int]) -> Int {
        if spaces <= 1 {
            stack = [0]
            return 0
        }
        if stack.isEmpty {
            stack = [0, spaces]
            return 1
        }
        while stack.count > 1 && stack[stack.count - 1] > spaces {
            stack.removeLast()
        }
        if let last = stack.last, spaces > last {
            stack.append(spaces)
        }
        return min(4, max(0, stack.count - 1))
    }

    private static func parseTableDelimiterRow(_ rawLine: String) -> [MarkdownTableAlignment]? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") && trimmed.contains("-") else { return nil }
        let cells = splitTableCells(trimmed)
        guard !cells.isEmpty else { return nil }

        var alignments: [MarkdownTableAlignment] = []
        for cell in cells {
            let c = cell.trimmingCharacters(in: .whitespaces)
            guard !c.isEmpty else { return nil }
            let startsColon = c.hasPrefix(":")
            let endsColon = c.hasSuffix(":")
            var core = c
            if startsColon { core.removeFirst() }
            if endsColon && !core.isEmpty { core.removeLast() }
            guard core.count >= 1 && core.allSatisfy({ $0 == "-" }) else {
                return nil
            }
            if startsColon && endsColon {
                alignments.append(.center)
            } else if endsColon {
                alignments.append(.trailing)
            } else {
                alignments.append(.leading)
            }
        }
        return alignments
    }

    private static func splitTableCells(_ rawLine: String) -> [String] {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("|") {
            line.removeFirst()
        }
        if line.hasSuffix("|") && !line.hasSuffix("\\|") {
            line.removeLast()
        }

        let chars = Array(line)
        var cells: [String] = []
        var current = ""
        var i = 0
        var inCodeTicks = 0

        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" && i + 1 < chars.count && inCodeTicks == 0 {
                if chars[i + 1] == "|" {
                    current.append("|")
                    i += 2
                    continue
                }
                current.append(ch)
                current.append(chars[i + 1])
                i += 2
                continue
            }
            if ch == "`" {
                var ticks = 0
                while i + ticks < chars.count && chars[i + ticks] == "`" {
                    ticks += 1
                }
                if inCodeTicks == 0 {
                    inCodeTicks = ticks
                } else if ticks == inCodeTicks {
                    inCodeTicks = 0
                }
                current.append(String(repeating: "`", count: ticks))
                i += ticks
                continue
            }
            if ch == "|" && inCodeTicks == 0 {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                i += 1
                continue
            }
            current.append(ch)
            i += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    // MARK: - Inline Helpers

    private static func isWordChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber
    }

    private static func coalesceTextNodes(_ nodes: [MarkdownInline]) -> [MarkdownInline] {
        var out: [MarkdownInline] = []
        for node in nodes {
            if case .text(let s) = node, let last = out.last, case .text(let prev) = last {
                out[out.count - 1] = .text(prev + s)
            } else {
                out.append(node)
            }
        }
        return out
    }

    private static func findExactBacktickRun(_ chars: [Character], length: Int, from: Int, end: Int) -> Int? {
        var i = from
        while i < end {
            if chars[i] == "`" {
                var count = 0
                while i + count < end && chars[i + count] == "`" {
                    count += 1
                }
                if count == length {
                    return i
                }
                i += count
            } else {
                i += 1
            }
        }
        return nil
    }

    private static func findSimpleBracketClose(_ chars: [Character], from: Int, end: Int) -> Int? {
        var i = from
        while i < end {
            if chars[i] == "]" { return i }
            if chars[i] == "[" || chars[i] == "\n" { return nil }
            i += 1
        }
        return nil
    }

    private static func findMatchingBracket(_ chars: [Character], openAt: Int, end: Int) -> Int? {
        var depth = 0
        var i = openAt
        while i < end {
            let ch = chars[i]
            if ch == "\n" { return nil }
            if ch == "\\" && i + 1 < end {
                i += 2
                continue
            }
            if ch == "`" {
                var ticks = 0
                while i + ticks < end && chars[i + ticks] == "`" { ticks += 1 }
                if let close = findExactBacktickRun(chars, length: ticks, from: i + ticks, end: end) {
                    i = close + ticks
                    continue
                }
                i += ticks
                continue
            }
            if ch == "[" {
                depth += 1
            } else if ch == "]" {
                depth -= 1
                if depth == 0 {
                    return i
                }
            }
            i += 1
        }
        return nil
    }

    private static func parseLinkDestination(
        _ chars: [Character],
        openParenAt: Int,
        end: Int
    ) -> (destination: String, nextIndex: Int)? {
        var i = openParenAt + 1
        while i < end && (chars[i] == " " || chars[i] == "\t") {
            i += 1
        }
        guard i < end else { return nil }

        if chars[i] == "<" {
            i += 1
            let destStart = i
            while i < end && chars[i] != ">" && chars[i] != "\n" {
                i += 1
            }
            guard i < end && chars[i] == ">" else { return nil }
            let dest = String(chars[destStart..<i])
            i += 1
            while i < end && chars[i] != ")" && chars[i] != "\n" {
                i += 1
            }
            guard i < end && chars[i] == ")" else { return nil }
            return (dest, i + 1)
        }

        let destStart = i
        var parenDepth = 0
        while i < end {
            let ch = chars[i]
            if ch == "\n" { return nil }
            if ch == "\\" && i + 1 < end {
                i += 2
                continue
            }
            if ch == "(" {
                parenDepth += 1
            } else if ch == ")" {
                if parenDepth == 0 {
                    var rawDest = String(chars[destStart..<i]).trimmingCharacters(in: .whitespaces)
                    if rawDest.hasSuffix("\""),
                       let quoteStart = rawDest.dropLast().lastIndex(of: "\""),
                       quoteStart > rawDest.startIndex {
                        let beforeQuote = rawDest[..<quoteStart]
                        if beforeQuote.last?.isWhitespace == true {
                            rawDest = beforeQuote.trimmingCharacters(in: .whitespaces)
                        }
                    }
                    return (rawDest, i + 1)
                }
                parenDepth -= 1
            }
            i += 1
        }
        return nil
    }

    private static func matchBareHTTPURL(_ chars: [Character], at start: Int, end: Int) -> (url: String, nextIndex: Int)? {
        let remaining = end - start
        guard remaining >= 10 else { return nil }
        let prefix8 = String(chars[start..<min(end, start + 8)]).lowercased()
        guard prefix8.hasPrefix("https://") || prefix8.hasPrefix("http://") else { return nil }
        if start > 0 {
            let prev = chars[start - 1]
            if prev.isLetter || prev.isNumber || prev == "/" || prev == "(" || prev == "[" {
                return nil
            }
        }

        var i = start
        while i < end {
            let ch = chars[i]
            if ch.isWhitespace || ch == "<" || ch == ">" || ch == "\"" || ch == "`" {
                break
            }
            i += 1
        }
        let trailingPunct: Set<Character> = Set(".,;:!?)]}。，；：！？）")
        while i > start + 8 && trailingPunct.contains(chars[i - 1]) {
            i -= 1
        }
        guard i > start + 8 else { return nil }
        return (String(chars[start..<i]), i)
    }

    private static func findSequence(
        _ chars: [Character],
        target: [Character],
        from: Int,
        end: Int,
        stopAtNewline: Bool
    ) -> Int? {
        guard !target.isEmpty && from + target.count <= end else { return nil }
        var i = from
        while i + target.count <= end {
            if stopAtNewline && chars[i] == "\n" { return nil }
            var matched = true
            for offset in 0..<target.count {
                if chars[i + offset] != target[offset] {
                    matched = false
                    break
                }
            }
            if matched { return i }
            i += 1
        }
        return nil
    }

    private static func findDelimiterOutsideCode(
        _ chars: [Character],
        delimiter: [Character],
        from: Int,
        end: Int
    ) -> Int? {
        var i = from
        while i + delimiter.count <= end {
            let ch = chars[i]
            if ch == "\\" && i + 1 < end {
                i += 2
                continue
            }
            if ch == "`" {
                var ticks = 0
                while i + ticks < end && chars[i + ticks] == "`" { ticks += 1 }
                if let close = findExactBacktickRun(chars, length: ticks, from: i + ticks, end: end) {
                    i = close + ticks
                    continue
                }
                i += ticks
                continue
            }
            if ch == "[",
               let closeBracket = findMatchingBracket(chars, openAt: i, end: end),
               closeBracket + 1 < end,
               chars[closeBracket + 1] == "(",
               let dest = parseLinkDestination(chars, openParenAt: closeBracket + 1, end: end) {
                i = dest.nextIndex
                continue
            }
            var matched = true
            for offset in 0..<delimiter.count {
                if chars[i + offset] != delimiter[offset] {
                    matched = false
                    break
                }
            }
            if matched {
                return i
            }
            i += 1
        }
        return nil
    }

    private static func findClosingInlineMathDollar(_ chars: [Character], from: Int, end: Int) -> Int? {
        var i = from
        while i < end {
            let ch = chars[i]
            if ch == "\n" || ch == "`" { return nil }
            if ch == "\\" && i + 1 < end {
                i += 2
                continue
            }
            if ch == "$" {
                if i > from && !chars[i - 1].isWhitespace {
                    return i
                }
                return nil
            }
            i += 1
        }
        return nil
    }

    private static func findEmphasisClose(
        _ chars: [Character],
        marker: Character,
        count: Int,
        from: Int,
        end: Int
    ) -> Int? {
        var i = from
        while i + count <= end {
            let ch = chars[i]
            if ch == "\\" && i + 1 < end {
                i += 2
                continue
            }
            if ch == "`" {
                var ticks = 0
                while i + ticks < end && chars[i + ticks] == "`" { ticks += 1 }
                if let close = findExactBacktickRun(chars, length: ticks, from: i + ticks, end: end) {
                    i = close + ticks
                    continue
                }
                i += ticks
                continue
            }
            if ch == "[",
               let closeBracket = findMatchingBracket(chars, openAt: i, end: end),
               closeBracket + 1 < end,
               chars[closeBracket + 1] == "(",
               let dest = parseLinkDestination(chars, openParenAt: closeBracket + 1, end: end) {
                i = dest.nextIndex
                continue
            }
            if ch == marker {
                var run = 0
                while i + run < end && chars[i + run] == marker {
                    run += 1
                }
                if run == count && i > from && !chars[i - 1].isWhitespace {
                    if marker == "_" {
                        let afterIdx = i + count
                        if afterIdx < end && isWordChar(chars[afterIdx]) {
                            i += run
                            continue
                        }
                    }
                    return i
                }
                if count == 2 && run == 3 && i > from && !chars[i - 1].isWhitespace {
                    return i + 1
                }
                i += run
                continue
            }
            i += 1
        }
        return nil
    }
}
