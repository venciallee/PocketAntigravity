package dev.antigravity.shared.markdown

import dev.antigravity.shared.model.ResolvedEmbedResource

/**
 * Pure Kotlin Multiplatform GitHub-Flavored Markdown (GFM), HTML subset, and Antigravity
 * Agent Extension AST parser.
 *
 * Produces an identical [MarkdownBlock] / [MarkdownInline] AST for both iOS (SwiftUI/TextKit)
 * and Android (Jetpack Compose) native renderers.
 */
public object AntigravityMarkdownParser {

    private class IdCounter(var value: Int = 0) {
        fun next(): Int = value++
    }

    private class ParseContext(
        val referenceLinks: MutableMap<String, String> = linkedMapOf(),
        val footnoteDefs: MutableList<Pair<String, String>> = mutableListOf(),
    )

    private val uppercaseAcronyms = setOf(
        "api", "ui", "ux", "sql", "cli", "rpc", "mcp", "cpu", "gpu", "svg",
        "html", "json", "http", "ts", "go", "ios", "esdd", "gfm", "dag", "kmp",
    )

    public fun humanReadableEmbedTitle(src: String, explicitTitle: String? = null): String {
        explicitTitle?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        val cleaned = ResolvedEmbedResource.normalizePath(src).trimEnd('/')
        val lastComp = cleaned.substringAfterLast('/')
        if (lastComp.isEmpty()) return "Interactive Widget"
        val dotIdx = lastComp.lastIndexOf('.')
        val stem = if (dotIdx > 0) lastComp.substring(0, dotIdx) else lastComp
        if (stem.isEmpty()) return lastComp

        val rawTokens = stem.replace('_', ' ').replace('-', ' ')
            .split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (rawTokens.isEmpty()) return lastComp

        val formatted = rawTokens.mapIndexed { idx, token ->
            val lower = token.lowercase()
            when {
                idx == 0 && lower.startsWith("fig") && lower.length > 3 &&
                    lower.drop(3).all { it.isDigit() } -> "Fig ${lower.drop(3)} ·"
                lower in uppercaseAcronyms -> lower.uppercase()
                else -> token.replaceFirstChar { it.uppercaseChar() }
            }
        }
        return formatted.joinToString(" ").replace("· ", "· ")
    }

    public fun parse(markdown: String): List<MarkdownBlock> {
        val normalized = markdown.replace("\r\n", "\n").replace("\r", "\n")
        if (normalized.trim().isEmpty()) return emptyList()

        val idCounter = IdCounter()
        val ctx = ParseContext()
        val blocks = mutableListOf<MarkdownBlock>()

        var rawLines = normalized.split('\n')

        // 1. Optional YAML frontmatter
        if (rawLines.size >= 3 && rawLines[0].trim() == "---") {
            val closeIdx = (1 until rawLines.size).firstOrNull {
                val t = rawLines[it].trim()
                t == "---" || t == "..."
            }
            if (closeIdx != null && closeIdx > 1) {
                val entries = rawLines.subList(1, closeIdx).mapNotNull { line ->
                    val colon = line.indexOf(':')
                    if (colon <= 0) return@mapNotNull null
                    val k = line.substring(0, colon).trim()
                    val v = line.substring(colon + 1).trim().trim('"', '\'')
                    if (k.isNotEmpty()) MarkdownFrontmatterEntry(k, v) else null
                }
                if (entries.isNotEmpty()) {
                    blocks.add(MarkdownBlock.Frontmatter(idCounter.next(), entries))
                    rawLines = rawLines.subList(closeIdx + 1, rawLines.size)
                }
            }
        }

        // 2. Collect link reference definitions & footnote definitions (skipping fenced blocks)
        val filteredLines = extractDefinitions(rawLines, ctx)

        // 3. Parse block stream
        blocks.addAll(parseBlocks(filteredLines, idCounter, ctx))

        // 4. Append footnote section if definitions exist
        if (ctx.footnoteDefs.isNotEmpty()) {
            val items = ctx.footnoteDefs.map { (label, body) ->
                MarkdownFootnoteItem(label = label, inlines = parseInlines(body, ctx))
            }
            blocks.add(MarkdownBlock.FootnoteSection(idCounter.next(), items))
        }

        return blocks
    }

    private fun extractDefinitions(lines: List<String>, ctx: ParseContext): List<String> {
        val out = mutableListOf<String>()
        var inFence = false
        var fenceChar = '`'
        var fenceLen = 3
        val refRegex = Regex("^\\[([^\\]^][^\\]]*)\\]:\\s*(\\S+)(?:\\s+.*)?$")
        val fnRegex = Regex("^\\[\\^([^\\]]+)\\]:\\s*(.*)$")

        for (line in lines) {
            val trimmed = line.trim()
            val fence = matchFenceOpen(trimmed)
            if (!inFence && fence != null) {
                inFence = true
                fenceChar = fence.first
                fenceLen = fence.second
                out.add(line)
                continue
            } else if (inFence) {
                if (isFenceClose(trimmed, fenceChar, fenceLen)) {
                    inFence = false
                }
                out.add(line)
                continue
            }

            val fnMatch = fnRegex.matchEntire(trimmed)
            if (fnMatch != null) {
                ctx.footnoteDefs.add(fnMatch.groupValues[1] to fnMatch.groupValues[2].trim())
                continue
            }
            val refMatch = refRegex.matchEntire(trimmed)
            if (refMatch != null) {
                ctx.referenceLinks[refMatch.groupValues[1].trim().lowercase()] = refMatch.groupValues[2].trim().trim('<', '>')
                continue
            }
            out.add(line)
        }
        return out
    }

    private fun parseBlocks(
        lines: List<String>,
        idCounter: IdCounter,
        ctx: ParseContext,
    ): List<MarkdownBlock> {
        val blocks = mutableListOf<MarkdownBlock>()
        var i = 0
        val n = lines.size

        while (i < n) {
            val line = lines[i]
            val trimmed = line.trim()

            // Blank line
            if (trimmed.isEmpty()) {
                i += 1
                continue
            }

            // Standalone HTML comment (<!-- ... -->)
            if (trimmed.startsWith("<!--")) {
                var endLine = i
                while (endLine < n && !lines[endLine].contains("-->")) endLine += 1
                i = endLine + 1
                continue
            }

            // Fenced code / mermaid / carousel
            val fence = matchFenceOpen(trimmed)
            if (fence != null) {
                val (fChar, fLen, info) = fence
                val lang = info.trim().split(Regex("\\s+")).firstOrNull()?.takeIf { it.isNotEmpty() }
                val bodyLines = mutableListOf<String>()
                i += 1
                while (i < n && !isFenceClose(lines[i].trim(), fChar, fLen)) {
                    bodyLines.add(lines[i])
                    i += 1
                }
                if (i < n) i += 1 // consume closing fence if present
                val body = bodyLines.joinToString("\n")
                when (lang?.lowercase()) {
                    "mermaid" -> blocks.add(MarkdownBlock.Mermaid(idCounter.next(), body))
                    "carousel" -> {
                        val slides = splitCarouselSlides(body).map { slideText ->
                            parseBlocks(slideText.split('\n'), idCounter, ctx)
                        }.filter { it.isNotEmpty() }
                        blocks.add(MarkdownBlock.Carousel(idCounter.next(), slides))
                    }
                    else -> blocks.add(MarkdownBlock.CodeBlock(idCounter.next(), lang, body))
                }
                continue
            }

            // Display math block ($$ ... $$ or \[ ... \])
            if (trimmed.startsWith("$$") || trimmed == "\\[") {
                val isDollar = trimmed.startsWith("$$")
                if (isDollar && trimmed.length > 4 && trimmed.endsWith("$$")) {
                    blocks.add(MarkdownBlock.MathBlock(idCounter.next(), trimmed.drop(2).dropLast(2).trim()))
                    i += 1
                    continue
                }
                val mathLines = mutableListOf<String>()
                val firstRemainder = if (isDollar) trimmed.drop(2).trim() else ""
                if (firstRemainder.isNotEmpty()) mathLines.add(firstRemainder)
                i += 1
                while (i < n) {
                    val t = lines[i].trim()
                    if ((isDollar && t.endsWith("$$")) || (!isDollar && t == "\\]")) {
                        val before = if (isDollar) t.dropLast(2).trim() else ""
                        if (before.isNotEmpty()) mathLines.add(before)
                        i += 1
                        break
                    }
                    mathLines.add(lines[i])
                    i += 1
                }
                blocks.add(MarkdownBlock.MathBlock(idCounter.next(), mathLines.joinToString("\n").trim()))
                continue
            }

            // HTML <details>...</details>
            if (trimmed.lowercase().startsWith("<details")) {
                val openByDefault = Regex("\\bopen\\b", RegexOption.IGNORE_CASE).containsMatchIn(trimmed)
                val collected = mutableListOf(line)
                i += 1
                if (!trimmed.lowercase().contains("</details>")) {
                    while (i < n) {
                        collected.add(lines[i])
                        if (lines[i].lowercase().contains("</details>")) {
                            i += 1
                            break
                        }
                        i += 1
                    }
                }
                val full = collected.joinToString("\n")
                val inner = full
                    .replaceFirst(Regex("^\\s*<details[^>]*>", RegexOption.IGNORE_CASE), "")
                    .replaceFirst(Regex("</details>\\s*$", RegexOption.IGNORE_CASE), "")
                val summaryRegex = Regex("<summary[^>]*>(.*?)</summary>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
                val summaryMatch = summaryRegex.find(inner)
                val summaryInlines = if (summaryMatch != null) {
                    parseInlines(summaryMatch.groupValues[1].trim(), ctx)
                } else {
                    listOf(MarkdownInline.Text("Details"))
                }
                val restBody = if (summaryMatch != null) inner.removeRange(summaryMatch.range) else inner
                val innerBlocks = parseBlocks(restBody.split('\n'), idCounter, ctx)
                blocks.add(MarkdownBlock.Details(idCounter.next(), summaryInlines, innerBlocks, openByDefault))
                continue
            }

            // HTML <table>...</table>
            if (trimmed.lowercase().startsWith("<table")) {
                val collected = mutableListOf(line)
                i += 1
                if (!trimmed.lowercase().contains("</table>")) {
                    while (i < n) {
                        collected.add(lines[i])
                        if (lines[i].lowercase().contains("</table>")) {
                            i += 1
                            break
                        }
                        i += 1
                    }
                }
                parseHtmlTable(collected.joinToString("\n"), idCounter, ctx)?.let { blocks.add(it) }
                continue
            }

            // HTML <pre><code>...</code></pre>
            if (trimmed.lowercase().startsWith("<pre")) {
                val collected = mutableListOf(line)
                i += 1
                if (!trimmed.lowercase().contains("</pre>")) {
                    while (i < n) {
                        collected.add(lines[i])
                        if (lines[i].lowercase().contains("</pre>")) {
                            i += 1
                            break
                        }
                        i += 1
                    }
                }
                val full = collected.joinToString("\n")
                val langMatch = Regex("class=[\"'][^\"']*language-([A-Za-z0-9_+.-]+)", RegexOption.IGNORE_CASE).find(full)
                val lang = langMatch?.groupValues?.get(1)
                val codeInner = full
                    .replaceFirst(Regex("^\\s*<pre[^>]*>(?:\\s*<code[^>]*>)?", RegexOption.IGNORE_CASE), "")
                    .replaceFirst(Regex("(?:</code>\\s*)?</pre>\\s*$", RegexOption.IGNORE_CASE), "")
                blocks.add(MarkdownBlock.CodeBlock(idCounter.next(), lang, decodeHtmlEntities(codeInner)))
                continue
            }

            // HTML <figure>...</figure>
            if (trimmed.lowercase().startsWith("<figure")) {
                val collected = mutableListOf(line)
                i += 1
                if (!trimmed.lowercase().contains("</figure>")) {
                    while (i < n) {
                        collected.add(lines[i])
                        if (lines[i].lowercase().contains("</figure>")) {
                            i += 1
                            break
                        }
                        i += 1
                    }
                }
                val full = collected.joinToString("\n")
                val imgTag = Regex("<img\\b([^>]*)/?>", RegexOption.IGNORE_CASE).find(full)
                if (imgTag != null) {
                    val attrs = parseHtmlAttributes(imgTag.groupValues[1])
                    val caption = Regex("<figcaption[^>]*>(.*?)</figcaption>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
                        .find(full)?.groupValues?.get(1)?.trim()
                    blocks.add(
                        MarkdownBlock.Image(
                            id = idCounter.next(),
                            alt = attrs["alt"].orEmpty(),
                            src = attrs["src"].orEmpty(),
                            title = caption ?: attrs["title"],
                        )
                    )
                    continue
                }
            }

            // Standalone <plugin-card ...>
            if (trimmed.lowercase().startsWith("<plugin-card")) {
                val attrs = parseHtmlAttributes(trimmed)
                val catalogId = attrs["catalog-id"] ?: attrs["catalogid"] ?: ""
                blocks.add(MarkdownBlock.PluginCard(idCounter.next(), catalogId, attrs["title"]))
                i += 1
                continue
            }

            // Standalone <agent-embed ...> (complete or streaming incomplete)
            if (trimmed.lowercase().startsWith("<agent-embed")) {
                val block = parseStandaloneAgentEmbed(trimmed, idCounter)
                blocks.add(block)
                i += 1
                continue
            }

            // Standalone Markdown image: ![alt](src "title")
            val standaloneImg = matchStandaloneMarkdownImage(trimmed)
            if (standaloneImg != null) {
                blocks.add(MarkdownBlock.Image(idCounter.next(), standaloneImg.first, standaloneImg.second, standaloneImg.third))
                i += 1
                continue
            }

            // Standalone HTML <img ... />
            if (trimmed.lowercase().startsWith("<img") && trimmed.endsWith(">")) {
                val attrs = parseHtmlAttributes(trimmed)
                val src = attrs["src"].orEmpty()
                if (src.isNotEmpty()) {
                    blocks.add(MarkdownBlock.Image(idCounter.next(), attrs["alt"].orEmpty(), src, attrs["title"]))
                    i += 1
                    continue
                }
            }

            // ATX Heading (# .. ######)
            val atxMatch = Regex("^(#{1,6})\\s+(.*?)(?:\\s+#+\\s*)?$").matchEntire(trimmed)
            if (atxMatch != null) {
                val level = atxMatch.groupValues[1].length
                blocks.add(MarkdownBlock.Heading(idCounter.next(), level, parseInlines(atxMatch.groupValues[2], ctx)))
                i += 1
                continue
            }

            // Setext Heading (Title followed by === or ---)
            if (i + 1 < n && !isListStart(line) && !trimmed.startsWith(">")) {
                val nextTrimmed = lines[i + 1].trim()
                val setextLevel = when {
                    nextTrimmed.length >= 3 && nextTrimmed.all { it == '=' } -> 1
                    nextTrimmed.length >= 3 && nextTrimmed.all { it == '-' } -> 2
                    else -> null
                }
                if (setextLevel != null) {
                    blocks.add(MarkdownBlock.Heading(idCounter.next(), setextLevel, parseInlines(trimmed, ctx)))
                    i += 2
                    continue
                }
            }

            // Thematic Break (---, ***, ___)
            if (isThematicBreak(trimmed)) {
                blocks.add(MarkdownBlock.ThematicBreak(idCounter.next()))
                i += 1
                continue
            }

            // Blockquote / GitHub Alert Callout
            if (trimmed.startsWith(">")) {
                val quoteLines = mutableListOf<String>()
                while (i < n && lines[i].trim().startsWith(">")) {
                    val stripped = lines[i].trim().removePrefix(">").removePrefix(" ")
                    quoteLines.add(stripped)
                    i += 1
                }
                var alertKind: MarkdownAlertKind? = null
                val contentLines = if (quoteLines.isNotEmpty()) {
                    val alertMatch = Regex("^\\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]\\s*(.*)$", RegexOption.IGNORE_CASE)
                        .matchEntire(quoteLines[0].trim())
                    if (alertMatch != null) {
                        alertKind = MarkdownAlertKind.fromTag(alertMatch.groupValues[1])
                        val remainder = alertMatch.groupValues[2].trim()
                        val rest = quoteLines.drop(1)
                        if (remainder.isNotEmpty()) listOf(remainder) + rest else rest
                    } else {
                        quoteLines
                    }
                } else {
                    quoteLines
                }
                val innerBlocks = parseBlocks(contentLines, idCounter, ctx)
                blocks.add(MarkdownBlock.Blockquote(idCounter.next(), alertKind, innerBlocks))
                continue
            }

            // GFM Pipe Table
            if (i + 1 < n && line.contains('|') && isGfmTableSeparator(lines[i + 1])) {
                val headerCells = splitGfmTableRow(line).map { parseInlines(it, ctx) }
                val alignments = parseGfmTableAlignments(lines[i + 1])
                i += 2
                val rows = mutableListOf<List<List<MarkdownInline>>>()
                while (i < n && lines[i].trim().isNotEmpty() && lines[i].contains('|') && !isBlockBoundary(lines[i])) {
                    rows.add(splitGfmTableRow(lines[i]).map { parseInlines(it, ctx) })
                    i += 1
                }
                blocks.add(MarkdownBlock.Table(idCounter.next(), headerCells, alignments, rows))
                continue
            }

            // List item (bullet, ordered, task)
            val listItem = matchListItem(line)
            if (listItem != null) {
                blocks.add(
                    MarkdownBlock.ListItem(
                        id = idCounter.next(),
                        indentLevel = listItem.indentLevel,
                        marker = listItem.marker,
                        inlines = parseInlines(listItem.content, ctx),
                    )
                )
                i += 1
                continue
            }

            // Paragraph (collect consecutive non-boundary lines)
            val paraLines = mutableListOf(trimmed)
            i += 1
            while (i < n) {
                val candidate = lines[i]
                val candTrim = candidate.trim()
                if (candTrim.isEmpty() || isBlockBoundary(candidate) || isSetextUnderlineAhead(lines, i)) {
                    break
                }
                paraLines.add(candTrim)
                i += 1
            }
            val paraText = paraLines.joinToString("\n")
            blocks.addAll(splitParagraphWithInlineEmbeds(paraText, idCounter, ctx))
        }

        return blocks
    }

    private fun splitParagraphWithInlineEmbeds(
        text: String,
        idCounter: IdCounter,
        ctx: ParseContext,
    ): List<MarkdownBlock> {
        // Protect backticked inline code spans so `<agent-embed>` inside code stays literal
        val segments = mutableListOf<MarkdownBlock>()
        var idx = 0
        val currentText = StringBuilder()

        fun flushText() {
            val s = currentText.toString().trim()
            currentText.clear()
            if (s.isNotEmpty()) {
                segments.add(MarkdownBlock.Paragraph(idCounter.next(), parseInlines(s, ctx)))
            }
        }

        while (idx < text.length) {
            if (text[idx] == '`') {
                var ticks = 0
                while (idx + ticks < text.length && text[idx + ticks] == '`') ticks += 1
                val delim = "`".repeat(ticks)
                val close = text.indexOf(delim, idx + ticks)
                if (close >= 0) {
                    currentText.append(text, idx, close + ticks)
                    idx = close + ticks
                    continue
                }
            }
            if (text.regionMatches(idx, "<agent-embed", 0, "<agent-embed".length, ignoreCase = true)) {
                flushText()
                val closeTag = text.indexOf("</agent-embed>", idx, ignoreCase = true)
                val gtIdx = text.indexOf('>', idx)
                val tagEnd: Int
                val tagRaw: String
                if (gtIdx >= 0 && text.substring(idx, gtIdx + 1).trimEnd().endsWith("/>")) {
                    tagEnd = gtIdx + 1
                    tagRaw = text.substring(idx, tagEnd)
                } else if (closeTag >= 0) {
                    tagEnd = closeTag + "</agent-embed>".length
                    tagRaw = text.substring(idx, tagEnd)
                } else if (gtIdx >= 0) {
                    tagEnd = gtIdx + 1
                    tagRaw = text.substring(idx, tagEnd)
                } else {
                    tagEnd = text.length
                    tagRaw = text.substring(idx)
                }
                segments.add(parseStandaloneAgentEmbed(tagRaw, idCounter))
                idx = tagEnd
                continue
            }
            currentText.append(text[idx])
            idx += 1
        }
        flushText()
        return segments
    }

    private fun parseStandaloneAgentEmbed(raw: String, idCounter: IdCounter): MarkdownBlock.AgentEmbed {
        val trimmed = raw.trim()
        val isComplete = trimmed.endsWith("/>") || trimmed.lowercase().endsWith("</agent-embed>") ||
            (trimmed.contains('>') && !trimmed.substringAfterLast('>').contains('<'))
        val attrs = parseHtmlAttributes(trimmed)
        val src = attrs["src"].orEmpty()
        val title = attrs["title"]?.takeIf { it.isNotEmpty() }
        return MarkdownBlock.AgentEmbed(
            id = idCounter.next(),
            src = src,
            title = title,
            kind = MarkdownEmbedKind.detect(src),
            attributes = attrs,
            isStreamingIncomplete = !isComplete,
        )
    }

    private fun parseHtmlTable(raw: String, idCounter: IdCounter, ctx: ParseContext): MarkdownBlock.Table? {
        val rowRegex = Regex("<tr[^>]*>(.*?)</tr>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        val cellRegex = Regex("<(th|td)[^>]*>(.*?)</\\1>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
        val allRows = rowRegex.findAll(raw).map { rowMatch ->
            cellRegex.findAll(rowMatch.groupValues[1]).map { cell ->
                val isHeader = cell.groupValues[1].equals("th", ignoreCase = true)
                isHeader to parseInlines(cell.groupValues[2].trim(), ctx)
            }.toList()
        }.filter { it.isNotEmpty() }.toList()
        if (allRows.isEmpty()) return null

        val firstIsHeader = allRows[0].all { it.first }
        val headers = if (firstIsHeader) allRows[0].map { it.second } else emptyList()
        val bodyRows = (if (firstIsHeader) allRows.drop(1) else allRows).map { row -> row.map { it.second } }
        val colCount = maxOf(headers.size, bodyRows.maxOfOrNull { it.size } ?: 0)
        val alignments = List(colCount) { MarkdownTableAlignment.LEADING }
        return MarkdownBlock.Table(idCounter.next(), headers, alignments, bodyRows)
    }

    // MARK: - Inline Parser

    private fun parseInlines(raw: String, ctx: ParseContext): List<MarkdownInline> {
        val result = mutableListOf<MarkdownInline>()
        val textBuf = StringBuilder()
        var i = 0
        val n = raw.length

        fun flushText() {
            if (textBuf.isNotEmpty()) {
                result.add(MarkdownInline.Text(decodeHtmlEntities(textBuf.toString())))
                textBuf.clear()
            }
        }

        while (i < n) {
            val ch = raw[i]

            // Newline -> SoftBreak
            if (ch == '\n') {
                flushText()
                result.add(MarkdownInline.SoftBreak)
                i += 1
                continue
            }

            // Backslash escape for ASCII punctuation
            if (ch == '\\' && i + 1 < n) {
                val nxt = raw[i + 1]
                // Inline LaTeX \( ... \)
                if (nxt == '(') {
                    val close = raw.indexOf("\\)", i + 2)
                    if (close >= 0) {
                        flushText()
                        result.add(MarkdownInline.InlineMath(raw.substring(i + 2, close).trim()))
                        i = close + 2
                        continue
                    }
                }
                if (nxt in "!\"#\$%&'()*+,-./:;<=>?@[\\]^_`{|}~") {
                    textBuf.append(nxt)
                    i += 2
                    continue
                }
            }

            // Inline code span (`...` or ``...``)
            if (ch == '`') {
                var ticks = 0
                while (i + ticks < n && raw[i + ticks] == '`') ticks += 1
                val delim = "`".repeat(ticks)
                val close = raw.indexOf(delim, i + ticks)
                if (close >= 0) {
                    flushText()
                    var content = raw.substring(i + ticks, close)
                    if (content.length >= 2 && content.startsWith(' ') && content.endsWith(' ') && content.any { it != ' ' }) {
                        content = content.substring(1, content.length - 1)
                    }
                    result.add(MarkdownInline.Code(content))
                    i = close + ticks
                    continue
                }
            }

            // Inline HTML tags & autolinks (<...>) — preserves programming generics like Array<String>
            if (ch == '<') {
                val autolink = matchAutolink(raw, i)
                if (autolink != null) {
                    flushText()
                    result.add(MarkdownInline.Link(listOf(MarkdownInline.Text(autolink.first)), autolink.first))
                    i = autolink.second
                    continue
                }
                val htmlInline = matchInlineHtml(raw, i, ctx)
                if (htmlInline != null) {
                    flushText()
                    result.add(htmlInline.first)
                    i = htmlInline.second
                    continue
                }
            }

            // Inline image: ![alt](src)
            if (ch == '!' && i + 1 < n && raw[i + 1] == '[') {
                val closeBracket = findMatchingBracket(raw, i + 1)
                if (closeBracket != null && closeBracket + 1 < n && raw[closeBracket + 1] == '(') {
                    val closeParen = findMatchingParen(raw, closeBracket + 1)
                    if (closeParen != null) {
                        flushText()
                        val alt = raw.substring(i + 2, closeBracket)
                        val src = raw.substring(closeBracket + 2, closeParen).trim().substringBefore(' ')
                        result.add(MarkdownInline.InlineImage(alt, src))
                        i = closeParen + 1
                        continue
                    }
                }
            }

            // Footnote reference [^label] or Link [label](dest) / [label][ref]
            if (ch == '[') {
                // Footnote ref [^1]
                if (i + 1 < n && raw[i + 1] == '^') {
                    val close = raw.indexOf(']', i + 2)
                    if (close > i + 2) {
                        val label = raw.substring(i + 2, close)
                        if (!label.any { it.isWhitespace() }) {
                            flushText()
                            result.add(MarkdownInline.FootnoteRef(label))
                            i = close + 1
                            continue
                        }
                    }
                }
                val closeBracket = findMatchingBracket(raw, i)
                if (closeBracket != null) {
                    val labelRaw = raw.substring(i + 1, closeBracket)
                    // Inline link [label](url)
                    if (closeBracket + 1 < n && raw[closeBracket + 1] == '(') {
                        val closeParen = findMatchingParen(raw, closeBracket + 1)
                        if (closeParen != null) {
                            flushText()
                            val dest = raw.substring(closeBracket + 2, closeParen).trim()
                                .substringBefore(' ').trim('<', '>')
                            result.add(MarkdownInline.Link(parseInlines(labelRaw, ctx), dest))
                            i = closeParen + 1
                            continue
                        }
                    }
                    // Reference link [label][ref]
                    if (closeBracket + 1 < n && raw[closeBracket + 1] == '[') {
                        val closeRef = raw.indexOf(']', closeBracket + 2)
                        if (closeRef > closeBracket + 1) {
                            val refKey = raw.substring(closeBracket + 2, closeRef).ifEmpty { labelRaw }.trim().lowercase()
                            val dest = ctx.referenceLinks[refKey]
                            if (dest != null) {
                                flushText()
                                result.add(MarkdownInline.Link(parseInlines(labelRaw, ctx), dest))
                                i = closeRef + 1
                                continue
                            }
                        }
                    }
                }
            }

            // Strikethrough ~~...~~
            if (ch == '~' && i + 1 < n && raw[i + 1] == '~') {
                val close = raw.indexOf("~~", i + 2)
                if (close > i + 2) {
                    flushText()
                    result.add(MarkdownInline.Strikethrough(parseInlines(raw.substring(i + 2, close), ctx)))
                    i = close + 2
                    continue
                }
            }

            // Strong **...** or __...__ (intraword underscore protected!)
            if ((ch == '*' || ch == '_') && i + 1 < n && raw[i + 1] == ch) {
                val canOpen = ch == '*' || (i == 0 || !raw[i - 1].isLetterOrDigit())
                if (canOpen) {
                    val delim = "$ch$ch"
                    val close = findClosingDelim(raw, i + 2, delim, intrawordSafe = (ch == '_'))
                    if (close != null && close > i + 2) {
                        flushText()
                        result.add(MarkdownInline.Strong(parseInlines(raw.substring(i + 2, close), ctx)))
                        i = close + 2
                        continue
                    }
                }
            }

            // Emphasis *...* or _..._ (intraword underscore protected so snake_case stays intact!)
            if (ch == '*' || ch == '_') {
                val canOpen = (ch == '*' || i == 0 || !raw[i - 1].isLetterOrDigit()) &&
                    (i + 1 < n && !raw[i + 1].isWhitespace())
                if (canOpen) {
                    val close = findClosingDelim(raw, i + 1, ch.toString(), intrawordSafe = (ch == '_'))
                    if (close != null && close > i + 1 && !raw[close - 1].isWhitespace()) {
                        flushText()
                        result.add(MarkdownInline.Emphasis(parseInlines(raw.substring(i + 1, close), ctx)))
                        i = close + 1
                        continue
                    }
                }
            }

            // Inline LaTeX $...$
            if (ch == '$' && (i == 0 || raw[i - 1] != '$') && i + 1 < n && raw[i + 1] != '$' && !raw[i + 1].isWhitespace()) {
                val close = raw.indexOf('$', i + 1)
                if (close > i + 1 && !raw[close - 1].isWhitespace() && !raw.substring(i + 1, close).contains('\n')) {
                    flushText()
                    result.add(MarkdownInline.InlineMath(raw.substring(i + 1, close)))
                    i = close + 1
                    continue
                }
            }

            textBuf.append(ch)
            i += 1
        }

        flushText()
        return result
    }

    private fun matchAutolink(raw: String, start: Int): Pair<String, Int>? {
        val close = raw.indexOf('>', start + 1)
        if (close <= start + 1) return null
        val inner = raw.substring(start + 1, close)
        if (inner.any { it.isWhitespace() || it == '<' }) return null
        if (inner.startsWith("https://", ignoreCase = true) || inner.startsWith("http://", ignoreCase = true)) {
            return inner to (close + 1)
        }
        return null
    }

    private fun matchInlineHtml(raw: String, start: Int, ctx: ParseContext): Pair<MarkdownInline, Int>? {
        val gt = raw.indexOf('>', start + 1)
        if (gt <= start + 1) return null
        val tagBody = raw.substring(start + 1, gt).trim()
        if (tagBody.isEmpty() || tagBody.startsWith('/')) return null
        val tagName = tagBody.takeWhile { it.isLetterOrDigit() }.lowercase()

        // Self-closing <br> / <br/>
        if (tagName == "br") {
            return MarkdownInline.SoftBreak to (gt + 1)
        }

        val supportedPaired = setOf("b", "strong", "i", "em", "code", "kbd", "s", "del", "strike", "u", "ins", "mark", "sup", "sub", "a")
        if (tagName !in supportedPaired) return null

        val closeTag = "</$tagName>"
        val closeIdx = raw.indexOf(closeTag, gt + 1, ignoreCase = true)
        if (closeIdx < 0) return null
        val inner = raw.substring(gt + 1, closeIdx)
        val endPos = closeIdx + closeTag.length

        val node: MarkdownInline = when (tagName) {
            "b", "strong" -> MarkdownInline.Strong(parseInlines(inner, ctx))
            "i", "em" -> MarkdownInline.Emphasis(parseInlines(inner, ctx))
            "code" -> MarkdownInline.Code(decodeHtmlEntities(inner))
            "kbd" -> MarkdownInline.KeyboardKey(decodeHtmlEntities(inner))
            "s", "del", "strike" -> MarkdownInline.Strikethrough(parseInlines(inner, ctx))
            "u", "ins" -> MarkdownInline.Underline(parseInlines(inner, ctx))
            "mark" -> MarkdownInline.Highlight(parseInlines(inner, ctx))
            "sup" -> MarkdownInline.Superscript(decodeHtmlEntities(inner))
            "sub" -> MarkdownInline.SubscriptText(decodeHtmlEntities(inner))
            "a" -> {
                val attrs = parseHtmlAttributes(tagBody)
                MarkdownInline.Link(parseInlines(inner, ctx), attrs["href"].orEmpty())
            }
            else -> return null
        }
        return node to endPos
    }

    // MARK: - Block & Helper Utilities

    private fun matchFenceOpen(trimmed: String): Triple<Char, Int, String>? {
        if (trimmed.length < 3) return null
        val ch = trimmed[0]
        if (ch != '`' && ch != '~') return null
        var count = 0
        while (count < trimmed.length && trimmed[count] == ch) count += 1
        if (count < 3) return null
        val info = trimmed.substring(count)
        if (ch == '`' && info.contains('`')) return null
        return Triple(ch, count, info)
    }

    private fun isFenceClose(trimmed: String, fenceChar: Char, minLen: Int): Boolean =
        trimmed.length >= minLen && trimmed.all { it == fenceChar }

    private fun splitCarouselSlides(body: String): List<String> =
        body.split(Regex("<!--\\s*slide\\s*-->", RegexOption.IGNORE_CASE))
            .map { it.trim() }
            .filter { it.isNotEmpty() }

    private fun parseHtmlAttributes(rawTag: String): Map<String, String> {
        val attrs = linkedMapOf<String, String>()
        val attrRegex = Regex("""([a-zA-Z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')""")
        for (m in attrRegex.findAll(rawTag)) {
            val key = m.groupValues[1].lowercase()
            val value = m.groupValues[2].ifEmpty { m.groupValues[3] }
            attrs[key] = decodeHtmlEntities(value)
        }
        return attrs
    }

    private fun matchStandaloneMarkdownImage(trimmed: String): Triple<String, String, String?>? {
        val m = Regex("""^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)$""").matchEntire(trimmed) ?: return null
        return Triple(m.groupValues[1], m.groupValues[2], m.groupValues[3].takeIf { it.isNotEmpty() })
    }

    private fun isThematicBreak(trimmed: String): Boolean {
        val compact = trimmed.filterNot { it.isWhitespace() }
        return compact.length >= 3 && (compact.all { it == '-' } || compact.all { it == '*' } || compact.all { it == '_' })
    }

    private fun isGfmTableSeparator(line: String): Boolean {
        val trimmed = line.trim()
        if (!trimmed.contains('|') && !trimmed.contains('-')) return false
        val cells = splitGfmTableRow(trimmed)
        return cells.isNotEmpty() && cells.all { cell ->
            val c = cell.trim()
            c.isNotEmpty() && c.all { it == '-' || it == ':' } && c.contains('-')
        }
    }

    private fun parseGfmTableAlignments(line: String): List<MarkdownTableAlignment> =
        splitGfmTableRow(line.trim()).map { cell ->
            val c = cell.trim()
            val left = c.startsWith(':')
            val right = c.endsWith(':')
            when {
                left && right -> MarkdownTableAlignment.CENTER
                right -> MarkdownTableAlignment.TRAILING
                else -> MarkdownTableAlignment.LEADING
            }
        }

    private fun splitGfmTableRow(line: String): List<String> {
        var s = line.trim()
        if (s.startsWith('|')) s = s.drop(1)
        if (s.endsWith('|') && !s.endsWith("\\|")) s = s.dropLast(1)
        val cells = mutableListOf<String>()
        val buf = StringBuilder()
        var inCode = false
        var i = 0
        while (i < s.length) {
            val ch = s[i]
            if (ch == '\\' && i + 1 < s.length && s[i + 1] == '|') {
                buf.append('|')
                i += 2
                continue
            }
            if (ch == '`') {
                inCode = !inCode
                buf.append(ch)
                i += 1
                continue
            }
            if (ch == '|' && !inCode) {
                cells.add(buf.toString().trim())
                buf.clear()
                i += 1
                continue
            }
            buf.append(ch)
            i += 1
        }
        cells.add(buf.toString().trim())
        return cells
    }

    private data class ParsedListItem(
        val indentLevel: Int,
        val marker: MarkdownListMarker,
        val content: String,
    )

    private fun isListStart(line: String): Boolean = matchListItem(line) != null

    private fun matchListItem(line: String): ParsedListItem? {
        var spaces = 0
        while (spaces < line.length && (line[spaces] == ' ' || line[spaces] == '\t')) {
            spaces += if (line[spaces] == '\t') 2 else 1
        }
        val indentLevel = spaces / 2
        val rest = line.trimStart()

        // Task list: - [x] / - [ ]
        val taskMatch = Regex("^[-*+]\\s+\\[([ xX])\\]\\s+(.*)$").matchEntire(rest)
        if (taskMatch != null) {
            val checked = taskMatch.groupValues[1].equals("x", ignoreCase = true)
            return ParsedListItem(indentLevel, MarkdownListMarker.Task(checked), taskMatch.groupValues[2])
        }

        // Bullet list: - / * / +
        val bulletMatch = Regex("^[-*+]\\s+(.*)$").matchEntire(rest)
        if (bulletMatch != null) {
            return ParsedListItem(indentLevel, MarkdownListMarker.Bullet, bulletMatch.groupValues[1])
        }

        // Ordered list: 1. / 2)
        val orderedMatch = Regex("^(\\d+)[.)]\\s+(.*)$").matchEntire(rest)
        if (orderedMatch != null) {
            val num = orderedMatch.groupValues[1].toIntOrNull() ?: 1
            return ParsedListItem(indentLevel, MarkdownListMarker.Ordered(num), orderedMatch.groupValues[2])
        }
        return null
    }

    private fun isBlockBoundary(line: String): Boolean {
        val t = line.trim()
        val lower = t.lowercase()
        return matchFenceOpen(t) != null ||
            t.startsWith(">") ||
            t.startsWith("$$") ||
            t == "\\[" ||
            t.startsWith("<!--") ||
            Regex("^#{1,6}\\s+").containsMatchIn(t) ||
            isThematicBreak(t) ||
            isListStart(line) ||
            lower.startsWith("<agent-embed") ||
            lower.startsWith("<plugin-card") ||
            lower.startsWith("<details") ||
            lower.startsWith("<table") ||
            lower.startsWith("<pre") ||
            lower.startsWith("<figure")
    }

    private fun isSetextUnderlineAhead(lines: List<String>, idx: Int): Boolean {
        if (idx + 1 >= lines.size) return false
        val next = lines[idx + 1].trim()
        return next.length >= 3 && (next.all { it == '=' } || next.all { it == '-' })
    }

    private fun findMatchingBracket(s: String, openIdx: Int): Int? {
        var depth = 0
        var i = openIdx
        while (i < s.length) {
            when (s[i]) {
                '\\' -> i += 2
                '`' -> {
                    val end = s.indexOf('`', i + 1)
                    i = if (end >= 0) end + 1 else i + 1
                }
                '[' -> { depth += 1; i += 1 }
                ']' -> {
                    depth -= 1
                    if (depth == 0) return i
                    i += 1
                }
                else -> i += 1
            }
        }
        return null
    }

    private fun findMatchingParen(s: String, openIdx: Int): Int? {
        var depth = 0
        var i = openIdx
        while (i < s.length) {
            when (s[i]) {
                '\\' -> i += 2
                '(' -> { depth += 1; i += 1 }
                ')' -> {
                    depth -= 1
                    if (depth == 0) return i
                    i += 1
                }
                else -> i += 1
            }
        }
        return null
    }

    private fun findClosingDelim(s: String, from: Int, delim: String, intrawordSafe: Boolean): Int? {
        var idx = from
        while (idx <= s.length - delim.length) {
            val found = s.indexOf(delim, idx)
            if (found < 0) return null
            val after = found + delim.length
            if (!intrawordSafe || after >= s.length || !s[after].isLetterOrDigit()) {
                return found
            }
            idx = found + 1
        }
        return null
    }

    private fun decodeHtmlEntities(input: String): String {
        if (!input.contains('&')) return input
        return input
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&apos;", "'")
            .replace("&nbsp;", " ")
            .replace("&rarr;", "→")
            .replace("&larr;", "←")
            .replace("&harr;", "↔")
            .replace("&mdash;", "—")
            .replace("&ndash;", "–")
            .replace("&hellip;", "…")
    }
}
