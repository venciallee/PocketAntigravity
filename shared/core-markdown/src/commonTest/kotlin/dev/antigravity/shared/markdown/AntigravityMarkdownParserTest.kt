package dev.antigravity.shared.markdown

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AntigravityMarkdownParserTest {

    @Test
    fun testStandardGfmAlertsTablesCodeLinksAndStreamingFence() {
        val md = """
        ### 1. 修复 `Markdown` 渲染

        1. 检查 mock_language_server.py 日志
          - 打开 [`StepCellViews.swift`](file:///Users/dev/StepCellViews.swift#L560-L567)
            - [x] 已验证通过

        > [!WARNING]
        > 请先通过门禁检查

        | 模块 | 表达式 | 状态 |
        | :--- | :---: | ---: |
        | Parser | `a | b` | ~~旧版~~ **通过** |

        ```swift
        let blocks = AntigravityMarkdownParser.parse(prose)
        ```
        """.trimIndent()

        val blocks = AntigravityMarkdownParser.parse(md)
        assertEquals(7, blocks.size)

        val h3 = blocks[0] as MarkdownBlock.Heading
        assertEquals(3, h3.level)
        assertEquals(
            listOf(MarkdownInline.Text("1. 修复 "), MarkdownInline.Code("Markdown"), MarkdownInline.Text(" 渲染")),
            h3.inlines,
        )

        val item0 = blocks[1] as MarkdownBlock.ListItem
        assertEquals(0, item0.indentLevel)
        assertEquals(MarkdownListMarker.Ordered(1), item0.marker)
        assertTrue(item0.inlines.joinToString("") { it.plainText }.contains("mock_language_server.py"))

        val item1 = blocks[2] as MarkdownBlock.ListItem
        assertEquals(1, item1.indentLevel)
        assertEquals(MarkdownListMarker.Bullet, item1.marker)
        assertTrue(
            item1.inlines.contains(
                MarkdownInline.Link(
                    label = listOf(MarkdownInline.Code("StepCellViews.swift")),
                    destination = "file:///Users/dev/StepCellViews.swift#L560-L567",
                )
            )
        )

        val item2 = blocks[3] as MarkdownBlock.ListItem
        assertEquals(2, item2.indentLevel)
        assertEquals(MarkdownListMarker.Task(checked = true), item2.marker)

        val quote = blocks[4] as MarkdownBlock.Blockquote
        assertEquals(MarkdownAlertKind.WARNING, quote.alert)
        assertEquals(1, quote.blocks.size)

        val table = blocks[5] as MarkdownBlock.Table
        assertEquals(3, table.headers.size)
        assertEquals(
            listOf(MarkdownTableAlignment.LEADING, MarkdownTableAlignment.CENTER, MarkdownTableAlignment.TRAILING),
            table.alignments,
        )
        assertEquals(listOf(MarkdownInline.Code("a | b")), table.rows[0][1])
        assertEquals(
            listOf(
                MarkdownInline.Strikethrough(listOf(MarkdownInline.Text("旧版"))),
                MarkdownInline.Text(" "),
                MarkdownInline.Strong(listOf(MarkdownInline.Text("通过"))),
            ),
            table.rows[0][2],
        )

        val codeBlock = blocks[6] as MarkdownBlock.CodeBlock
        assertEquals("swift", codeBlock.language)
        assertEquals("let blocks = AntigravityMarkdownParser.parse(prose)", codeBlock.code)

        // Streaming unclosed fence
        val streaming = AntigravityMarkdownParser.parse("正在执行：\n```bash\ngit pull origin main")
        assertEquals(2, streaming.size)
        val streamCode = streaming[1] as MarkdownBlock.CodeBlock
        assertEquals("bash", streamCode.language)
        assertEquals("git pull origin main", streamCode.code)
    }

    @Test
    fun testAgentEmbedRichHtmlMermaidCarouselAndGenericsParity() {
        // 1. User screenshot with immediate <agent-embed>
        val screenshotMd = """
        ### 2.2 6 层全栈对齐验收矩阵

        - 关键接口（`UserError`、`DomainEvent` 顺序、`Assessor` 判定逻辑）与老服务逐项对齐。
        - 逐表 `SELECT` + `core` 验证，禁止写死 `0`/`409`/`403` 同源头校验。
        - 全量 `go test -race ./...` 通过。
        <agent-embed src="file:///Users/bytedance/.gemini/antigravity/brain/71d80260-b9b2-4f5f-b568-5374f6aebbdd/fig4-verification-pyramid.html"></agent-embed>
        """.trimIndent()

        val screenshotBlocks = AntigravityMarkdownParser.parse(screenshotMd)
        assertEquals(5, screenshotBlocks.size)
        val embed = screenshotBlocks[4] as MarkdownBlock.AgentEmbed
        assertNull(embed.title)
        assertEquals(MarkdownEmbedKind.HTML_WIDGET, embed.kind)
        assertFalse(embed.isStreamingIncomplete)
        assertEquals(
            "Fig 4 · Verification Pyramid",
            AntigravityMarkdownParser.humanReadableEmbedTitle(embed.src, embed.title),
        )

        // 2. Inline <agent-embed> splits cleanly while backticked `<agent-embed>` stays inline code
        val splitBlocks = AntigravityMarkdownParser.parse(
            """使用 `<agent-embed>` 标签渲染组件：见下方 <agent-embed src="file:///brain/chart.html" title="Latency Chart" /> 后继续说明。"""
        )
        assertEquals(3, splitBlocks.size)
        assertTrue((splitBlocks[0] as MarkdownBlock.Paragraph).inlines.contains(MarkdownInline.Code("<agent-embed>")))
        val promoted = splitBlocks[1] as MarkdownBlock.AgentEmbed
        assertEquals("file:///brain/chart.html", promoted.src)
        assertEquals("Latency Chart", promoted.title)

        // 3. Streaming unclosed <agent-embed
        val midStream = AntigravityMarkdownParser.parse("""<agent-embed src="file:///brain/fig5-pending""")
        assertEquals(1, midStream.size)
        assertTrue((midStream[0] as MarkdownBlock.AgentEmbed).isStreamingIncomplete)

        // 4. Full rich document
        val richDoc = """
        <!-- internal comment should be stripped -->
        Overview Heading
        ================

        Generics like Array<String> &amp; Result<Int, Error> stay intact &rarr; <kbd>⌘</kbd>+<kbd>K</kbd> <mark>highlighted</mark> <u>underlined</u> H<sub>2</sub>O x<sup>2</sup> [Ref][doc] [^1].

        <plugin-card catalog-id="github"></plugin-card>

        <details open>
        <summary>验证详情 (<b>6</b> 项)</summary>

        - <a href="https://antigravity.google.com">Antigravity</a>
        - Autolink: <https://example.com/docs>
        </details>

        ````carousel
        ![Slide 1](file:///brain/slide1.png)
        <!-- slide -->
        ```go
        func main() {}
        ```
        ````

        ```mermaid
        flowchart LR
            A[Client] --> B[Bridge]
            B --> C[LanguageServer]
        ```

        <table>
          <tr><th>Layer</th><th>Check</th></tr>
          <tr><td>L1</td><td><code>go test</code><br/>pass</td></tr>
        </table>

        <pre><code class="language-swift">let x = 1 &lt; 2</code></pre>

        <figure>
          <img src="file:///brain/arch.png" alt="Architecture" />
          <figcaption>System Architecture</figcaption>
        </figure>

        [doc]: https://antigravity.google.com/docs
        [^1]: Verified across direct LAN and Cloud Relay.
        """.trimIndent()

        val richBlocks = AntigravityMarkdownParser.parse(richDoc)
        assertTrue(richBlocks.any { it is MarkdownBlock.Heading && it.level == 1 })
        assertTrue(richBlocks.any { it is MarkdownBlock.PluginCard && it.catalogId == "github" })
        assertTrue(richBlocks.any { it is MarkdownBlock.Details && it.isOpenByDefault })
        assertTrue(richBlocks.any { it is MarkdownBlock.Carousel && it.slides.size == 2 })
        assertTrue(richBlocks.any { it is MarkdownBlock.Mermaid && it.source.contains("flowchart LR") })
        assertTrue(richBlocks.any { it is MarkdownBlock.Table && it.headers.size == 2 && it.rows.size == 1 })
        assertTrue(richBlocks.any { it is MarkdownBlock.CodeBlock && it.language == "swift" && it.code == "let x = 1 < 2" })
        assertTrue(richBlocks.any { it is MarkdownBlock.Image && it.alt == "Architecture" && it.title == "System Architecture" })
        assertTrue(richBlocks.any { it is MarkdownBlock.FootnoteSection && it.items.size == 1 && it.items[0].label == "1" })

        val para = richBlocks[1] as MarkdownBlock.Paragraph
        val plain = para.inlines.joinToString("") { it.plainText }
        assertTrue(plain.contains("Array<String> & Result<Int, Error>"))
        assertTrue(plain.contains("→"))
        assertTrue(para.inlines.contains(MarkdownInline.KeyboardKey("⌘")))
        assertTrue(para.inlines.contains(MarkdownInline.Highlight(listOf(MarkdownInline.Text("highlighted")))))
        assertTrue(para.inlines.contains(MarkdownInline.Underline(listOf(MarkdownInline.Text("underlined")))))
        assertTrue(para.inlines.contains(MarkdownInline.SubscriptText("2")))
        assertTrue(para.inlines.contains(MarkdownInline.Superscript("2")))
        assertTrue(para.inlines.contains(MarkdownInline.FootnoteRef("1")))
        assertTrue(
            para.inlines.contains(
                MarkdownInline.Link(listOf(MarkdownInline.Text("Ref")), "https://antigravity.google.com/docs")
            )
        )
    }
}
