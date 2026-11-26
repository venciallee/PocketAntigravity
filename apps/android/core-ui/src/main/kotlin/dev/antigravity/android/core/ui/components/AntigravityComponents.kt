package dev.antigravity.android.core.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.CheckBox
import androidx.compose.material.icons.rounded.CheckBoxOutlineBlank
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.icons.toMaterialIcon
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.AntigravityExtendedColors
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.shared.markdown.AntigravityMarkdownParser
import dev.antigravity.shared.markdown.MarkdownAlertKind
import dev.antigravity.shared.markdown.MarkdownBlock
import dev.antigravity.shared.markdown.MarkdownInline
import dev.antigravity.shared.markdown.MarkdownListMarker
import dev.antigravity.shared.markdown.MarkdownTableAlignment
import dev.antigravity.shared.model.CortexStepStatus

/**
 * Resolves the locked semantic status color for a KMP [CortexStepStatus].
 */
fun AntigravityExtendedColors.statusColorFor(status: CortexStepStatus): Color = when (status) {
    CortexStepStatus.IN_PROGRESS, CortexStepStatus.PENDING -> statusRunning
    CortexStepStatus.WAITING, CortexStepStatus.BLOCKED -> statusWaiting
    CortexStepStatus.DONE -> statusDone
    CortexStepStatus.ERROR -> statusError
    CortexStepStatus.CANCELLED, CortexStepStatus.UNSPECIFIED -> inkMuted
}

/**
 * Material 3 tonal surface container card with crisp 1dp border matching Antigravity UE cards.
 */
@Composable
fun AntigravitySurfaceCard(
    modifier: Modifier = Modifier,
    containerColor: Color = LocalAntigravityColors.current.surfaceCard,
    borderColor: Color = LocalAntigravityColors.current.cardBorder,
    cornerRadius: Dp = AntigravityDesignTokens.CardCornerRadius,
    contentPadding: PaddingValues = PaddingValues(16.dp),
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(cornerRadius)
    val border = BorderStroke(1.dp, borderColor)
    if (onClick != null) {
        Surface(
            onClick = onClick,
            modifier = modifier.defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget),
            shape = shape,
            color = containerColor,
            border = border,
        ) {
            Column(
                modifier = Modifier.padding(contentPadding),
                content = content,
            )
        }
    } else {
        Surface(
            modifier = modifier,
            shape = shape,
            color = containerColor,
            border = border,
        ) {
            Column(
                modifier = Modifier.padding(contentPadding),
                content = content,
            )
        }
    }
}

/**
 * Circular semantic status indicator dot with optional soft halo glow.
 */
@Composable
fun StatusDot(
    color: Color,
    modifier: Modifier = Modifier,
    size: Dp = 8.dp,
    glow: Boolean = false,
) {
    if (glow) {
        Box(
            modifier = modifier
                .size(size + 6.dp)
                .clip(CircleShape)
                .background(color.copy(alpha = 0.22f)),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(size)
                    .clip(CircleShape)
                    .background(color),
            )
        }
    } else {
        Box(
            modifier = modifier
                .size(size)
                .clip(CircleShape)
                .background(color),
        )
    }
}

/**
 * Convenience [StatusDot] overload bound directly to [CortexStepStatus].
 */
@Composable
fun StatusDot(
    status: CortexStepStatus,
    modifier: Modifier = Modifier,
    size: Dp = 8.dp,
    glow: Boolean = status == CortexStepStatus.IN_PROGRESS || status == CortexStepStatus.WAITING,
) {
    val colors = LocalAntigravityColors.current
    StatusDot(
        color = colors.statusColorFor(status),
        modifier = modifier,
        size = size,
        glow = glow,
    )
}

/**
 * Monospace `+additions -deletions` diff counter badge rendered in locked Emerald & Coral hues.
 */
@Composable
fun DiffCounterBadge(
    additions: Int,
    deletions: Int,
    modifier: Modifier = Modifier,
    showBackground: Boolean = true,
    onClick: (() -> Unit)? = null,
) {
    val colors = LocalAntigravityColors.current
    val content: @Composable () -> Unit = {
        Row(
            modifier = Modifier.padding(
                horizontal = if (showBackground) 10.dp else 0.dp,
                vertical = if (showBackground) 5.dp else 0.dp,
            ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(
                text = "+${additions.coerceAtLeast(0)}",
                style = MaterialTheme.typography.labelSmall.copy(
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                ),
                color = colors.statusDone,
                maxLines = 1,
                softWrap = false,
            )
            Text(
                text = "-${deletions.coerceAtLeast(0)}",
                style = MaterialTheme.typography.labelSmall.copy(
                    fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace,
                ),
                color = colors.statusError,
                maxLines = 1,
                softWrap = false,
            )
        }
    }

    if (!showBackground && onClick == null) {
        Box(modifier = modifier) { content() }
        return
    }

    val shape = RoundedCornerShape(AntigravityDesignTokens.PillCornerRadius)
    val bg = if (showBackground) colors.surfacePill else Color.Transparent
    val border = if (showBackground) BorderStroke(1.dp, colors.cardBorder) else null
    if (onClick != null) {
        Surface(
            onClick = onClick,
            modifier = modifier,
            shape = shape,
            color = bg,
            border = border,
        ) {
            content()
        }
    } else {
        Surface(
            modifier = modifier,
            shape = shape,
            color = bg,
            border = border,
        ) {
            content()
        }
    }
}

/**
 * Segmented progress bar aligned with UE07 Task cards and UE13 Android 16 Live Update segments.
 */
@Composable
fun SevenSegmentProgressBar(
    completedCount: Int,
    totalCount: Int,
    hasWaitingStep: Boolean = false,
    modifier: Modifier = Modifier,
    segmentHeight: Dp = 6.dp,
    segmentSpacing: Dp = 4.dp,
) {
    val colors = LocalAntigravityColors.current
    val segments = totalCount.coerceIn(1, 12)
    val clampedCompleted = completedCount.coerceIn(0, segments)
    val allComplete = clampedCompleted >= segments && !hasWaitingStep

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(segmentSpacing),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        for (index in 0 until segments) {
            val segmentColor = when {
                allComplete -> colors.statusDone
                index < clampedCompleted -> colors.statusRunning
                index == clampedCompleted && hasWaitingStep -> colors.statusWaiting
                index == clampedCompleted && clampedCompleted < segments -> colors.statusRunning.copy(alpha = 0.45f)
                else -> colors.ringTrack
            }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(segmentHeight)
                    .clip(RoundedCornerShape(100.dp))
                    .background(segmentColor),
            )
        }
    }
}

/**
 * Uppercase tracked section header label (`PINNED`, `PROJECTS`, `SCHEDULED`, `THIS PROJECT`).
 */
@Composable
fun SectionHeaderLabel(
    title: String,
    modifier: Modifier = Modifier,
    count: Int? = null,
    trailingContent: (@Composable RowScope.() -> Unit)? = null,
) {
    val colors = LocalAntigravityColors.current
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = title.uppercase(),
            style = MaterialTheme.typography.labelSmall.copy(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 0.9.sp,
            ),
            color = colors.inkMuted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (count != null) {
            Text(
                text = count.toString(),
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkMuted,
                maxLines = 1,
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        if (trailingContent != null) {
            trailingContent()
        }
    }
}

/**
 * Rounded Antigravity filter/metadata/action pill chip honoring 48dp interactive target rules.
 */
@Composable
fun AntigravityChip(
    label: String,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    leadingIcon: ImageVector? = null,
    leadingDotColor: Color? = null,
    badgeCount: Int? = null,
    containerColor: Color? = null,
    contentColor: Color? = null,
    borderColor: Color? = null,
    onClick: (() -> Unit)? = null,
) {
    val colors = LocalAntigravityColors.current
    val resolvedContainer = containerColor ?: if (selected) colors.pillActiveBackground else colors.surfacePill
    val resolvedContent = contentColor ?: if (selected) colors.pillActiveForeground else colors.inkLabel
    val resolvedBorder = borderColor ?: if (selected) Color.Transparent else colors.cardBorder
    val shape = RoundedCornerShape(AntigravityDesignTokens.PillCornerRadius)

    val inner: @Composable () -> Unit = {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (leadingDotColor != null) {
                StatusDot(color = leadingDotColor, size = 7.dp)
            }
            if (leadingIcon != null) {
                Icon(
                    imageVector = leadingIcon,
                    contentDescription = null,
                    tint = resolvedContent,
                    modifier = Modifier.size(15.dp),
                )
            }
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                color = resolvedContent,
                maxLines = 1,
                softWrap = false,
                overflow = TextOverflow.Ellipsis,
            )
            if (badgeCount != null && badgeCount > 0) {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(100.dp))
                        .background(
                            if (selected) resolvedContent.copy(alpha = 0.16f) else colors.surfaceElevated,
                        )
                        .padding(horizontal = 6.dp, vertical = 1.dp),
                ) {
                    Text(
                        text = badgeCount.toString(),
                        style = MaterialTheme.typography.labelSmall,
                        color = resolvedContent,
                        maxLines = 1,
                    )
                }
            }
        }
    }

    if (onClick != null) {
        Surface(
            onClick = onClick,
            modifier = modifier,
            shape = shape,
            color = resolvedContainer,
            border = if (resolvedBorder != Color.Transparent) BorderStroke(1.dp, resolvedBorder) else null,
        ) {
            inner()
        }
    } else {
        Surface(
            modifier = modifier,
            shape = shape,
            color = resolvedContainer,
            border = if (resolvedBorder != Color.Transparent) BorderStroke(1.dp, resolvedBorder) else null,
        ) {
            inner()
        }
    }
}

/**
 * TopAppBar Host Switcher Pill (`UE01`) displaying active Mac/Cloud host name, live reachability dot,
 * and dropdown chevron with guaranteed >= 48dp minimum touch target.
 */
@Composable
fun HostSwitcherPill(
    hostName: String,
    isOnline: Boolean,
    modifier: Modifier = Modifier,
    isCloud: Boolean = false,
    subtitle: String? = null,
    onClick: () -> Unit = {},
) {
    val colors = LocalAntigravityColors.current
    Surface(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget),
        shape = RoundedCornerShape(AntigravityDesignTokens.PillCornerRadius),
        color = colors.surfacePill,
        border = BorderStroke(1.dp, colors.cardBorder),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            StatusDot(
                color = if (isOnline) colors.statusDone else colors.statusWaiting,
                size = 8.dp,
                glow = isOnline,
            )
            Icon(
                imageVector = if (isCloud) Icons.Rounded.Cloud else Icons.Rounded.Computer,
                contentDescription = null,
                tint = colors.inkSecondary,
                modifier = Modifier.size(16.dp),
            )
            Column(
                modifier = Modifier.widthIn(max = 176.dp),
                verticalArrangement = Arrangement.Center,
            ) {
                Text(
                    text = hostName,
                    style = MaterialTheme.typography.labelLarge,
                    color = colors.inkReading,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (!subtitle.isNullOrBlank()) {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.inkMuted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Icon(
                imageVector = Icons.Rounded.KeyboardArrowDown,
                contentDescription = tr("Switch host", "切换主机"),
                tint = colors.inkSecondary,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

/**
 * Convenience overload parsing raw Markdown via KMP [AntigravityMarkdownParser] before rendering.
 */
@Composable
fun MarkdownContentView(
    markdown: String,
    modifier: Modifier = Modifier,
    onLinkClick: (String) -> Unit = {},
) {
    val blocks = remember(markdown) { AntigravityMarkdownParser.parse(markdown) }
    MarkdownContentView(
        blocks = blocks,
        modifier = modifier,
        onLinkClick = onLinkClick,
    )
}

/**
 * Native Jetpack Compose renderer for the KMP [MarkdownBlock] / [MarkdownInline] AST.
 * Supports headings, rich inline paragraphs (bold/italic/code/strikethrough/underline/highlight/
 * sup/sub/kbd/links/math/footnotes), syntax-framed code blocks, blockquotes & GitHub alerts
 * (`NOTE`/`TIP`/`IMPORTANT`/`WARNING`/`CAUTION`), bullet/ordered/task lists, horizontally scrollable
 * tables, YAML frontmatter pills, Mermaid/embed/plugin/image preview cards, details accordions,
 * carousels, and horizontal rules.
 */
@Composable
fun MarkdownContentView(
    blocks: List<MarkdownBlock>,
    modifier: Modifier = Modifier,
    onLinkClick: (String) -> Unit = {},
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        blocks.forEach { block ->
            MarkdownBlockItem(
                block = block,
                onLinkClick = onLinkClick,
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MarkdownBlockItem(
    block: MarkdownBlock,
    onLinkClick: (String) -> Unit,
) {
    val colors = LocalAntigravityColors.current
    when (block) {
        is MarkdownBlock.Frontmatter -> {
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                block.entries.forEach { entry ->
                    Surface(
                        shape = RoundedCornerShape(8.dp),
                        color = colors.surfacePill,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = "${entry.key}:",
                                style = MaterialTheme.typography.labelSmall,
                                color = colors.inkMuted,
                            )
                            Text(
                                text = entry.value,
                                style = MaterialTheme.typography.labelSmall,
                                color = colors.inkLabel,
                            )
                        }
                    }
                }
            }
        }

        is MarkdownBlock.Heading -> {
            val style = when (block.level) {
                1 -> MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold)
                2 -> MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold)
                3 -> MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold)
                else -> MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold)
            }
            val annotated = buildInlineAnnotatedString(block.inlines, colors, onLinkClick)
            Text(
                text = annotated,
                style = style,
                color = colors.inkReading,
                modifier = Modifier.padding(top = if (block.level <= 2) 4.dp else 2.dp),
            )
        }

        is MarkdownBlock.Paragraph -> {
            val annotated = buildInlineAnnotatedString(block.inlines, colors, onLinkClick)
            Text(
                text = annotated,
                style = MaterialTheme.typography.bodyLarge,
                color = colors.inkReading,
            )
        }

        is MarkdownBlock.CodeBlock -> {
            if (block.isMermaidDiagram) {
                MermaidPreviewCard(source = block.code)
            } else {
                CodeBlockCard(
                    language = block.language,
                    code = block.code,
                )
            }
        }

        is MarkdownBlock.ListItem -> {
            val indentDp = (block.indentLevel.coerceIn(0, 6) * 16).dp
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = indentDp),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                when (val marker = block.marker) {
                    MarkdownListMarker.Bullet -> {
                        Text(
                            text = "•",
                            style = MaterialTheme.typography.bodyLarge,
                            color = colors.inkSecondary,
                        )
                    }

                    is MarkdownListMarker.Ordered -> {
                        Text(
                            text = "${marker.number}.",
                            style = MaterialTheme.typography.bodyMedium.copy(
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.inkSecondary,
                            modifier = Modifier.padding(top = 3.dp),
                        )
                    }

                    is MarkdownListMarker.Task -> {
                        Icon(
                            imageVector = if (marker.checked) {
                                Icons.Rounded.CheckBox
                            } else {
                                Icons.Rounded.CheckBoxOutlineBlank
                            },
                            contentDescription = if (marker.checked) "Completed" else "Incomplete",
                            tint = if (marker.checked) colors.statusDone else colors.inkMuted,
                            modifier = Modifier
                                .padding(top = 3.dp)
                                .size(18.dp),
                        )
                    }
                }
                val annotated = buildInlineAnnotatedString(block.inlines, colors, onLinkClick)
                Text(
                    text = annotated,
                    style = MaterialTheme.typography.bodyLarge,
                    color = colors.inkReading,
                    modifier = Modifier.weight(1f),
                )
            }
        }

        is MarkdownBlock.Blockquote -> {
            val alert = block.alert
            if (alert != null) {
                val accent = when (alert) {
                    MarkdownAlertKind.NOTE -> colors.accentPeriwinkle
                    MarkdownAlertKind.TIP -> colors.statusDone
                    MarkdownAlertKind.IMPORTANT -> colors.syntaxKeyword
                    MarkdownAlertKind.WARNING -> colors.statusWaiting
                    MarkdownAlertKind.CAUTION -> colors.statusError
                }
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(14.dp),
                    color = accent.copy(alpha = if (colors.isDark) 0.11f else 0.08f),
                    border = BorderStroke(1.dp, accent.copy(alpha = 0.35f)),
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .drawBehind {
                                drawRoundRect(
                                    color = accent,
                                    topLeft = Offset.Zero,
                                    size = Size(3.5.dp.toPx(), size.height),
                                    cornerRadius = CornerRadius(2.dp.toPx(), 2.dp.toPx()),
                                )
                            }
                            .padding(start = 14.dp, top = 10.dp, end = 12.dp, bottom = 10.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Icon(
                                imageVector = alert.semanticIcon.toMaterialIcon(),
                                contentDescription = alert.displayTitle,
                                tint = accent,
                                modifier = Modifier.size(16.dp),
                            )
                            Text(
                                text = alert.displayTitle,
                                style = MaterialTheme.typography.labelLarge,
                                color = accent,
                            )
                        }
                        MarkdownContentView(
                            blocks = block.blocks,
                            onLinkClick = onLinkClick,
                        )
                    }
                }
            } else {
                val barColor = colors.inkMuted.copy(alpha = 0.55f)
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .drawBehind {
                            drawRoundRect(
                                color = barColor,
                                topLeft = Offset.Zero,
                                size = Size(3.dp.toPx(), size.height),
                                cornerRadius = CornerRadius(2.dp.toPx(), 2.dp.toPx()),
                            )
                        }
                        .padding(start = 12.dp, top = 2.dp, bottom = 2.dp),
                ) {
                    MarkdownContentView(
                        blocks = block.blocks,
                        onLinkClick = onLinkClick,
                    )
                }
            }
        }

        is MarkdownBlock.Table -> {
            MarkdownTableCard(
                table = block,
                onLinkClick = onLinkClick,
            )
        }

        is MarkdownBlock.ThematicBreak -> {
            HorizontalDivider(
                modifier = Modifier.padding(vertical = 4.dp),
                thickness = 1.dp,
                color = colors.subtleDivider,
            )
        }

        is MarkdownBlock.MathBlock -> {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                color = colors.surfaceCodeBlock,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 14.dp, vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = block.latex,
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontFamily = FontFamily.Monospace,
                            fontStyle = FontStyle.Italic,
                        ),
                        color = colors.inkInlineCode,
                    )
                }
            }
        }

        is MarkdownBlock.AgentEmbed -> {
            val title = AntigravityMarkdownParser.humanReadableEmbedTitle(block.src, block.title)
            AntigravitySurfaceCard(
                containerColor = colors.surfaceSubtleBox,
                cornerRadius = 14.dp,
                contentPadding = PaddingValues(12.dp),
                onClick = { onLinkClick(block.src) },
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        imageVector = block.kind.semanticIcon.toMaterialIcon(),
                        contentDescription = block.kind.displayBadge,
                        tint = colors.accentPeriwinkle,
                        modifier = Modifier.size(20.dp),
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = title,
                            style = MaterialTheme.typography.titleSmall,
                            color = colors.inkReading,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = if (block.isStreamingIncomplete) {
                                tr("${block.kind.displayBadge} · Streaming…", "${block.kind.displayBadge} · 流式传输中…")
                            } else {
                                block.kind.displayBadge
                            },
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.inkMuted,
                            maxLines = 1,
                        )
                    }
                    Icon(
                        imageVector = Icons.Rounded.Link,
                        contentDescription = tr("Open embed", "打开嵌入内容"),
                        tint = colors.inkSecondary,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }

        is MarkdownBlock.PluginCard -> {
            AntigravitySurfaceCard(
                containerColor = colors.surfaceCard,
                cornerRadius = 14.dp,
                contentPadding = PaddingValues(12.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Extension,
                        contentDescription = tr("Plugin", "插件"),
                        tint = colors.accentPeriwinkle,
                        modifier = Modifier.size(20.dp),
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = block.title?.takeIf { it.isNotBlank() } ?: block.catalogId,
                            style = MaterialTheme.typography.titleSmall,
                            color = colors.inkReading,
                        )
                        Text(
                            text = tr("Plugin · ${block.catalogId}", "插件 · ${block.catalogId}"),
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.inkMuted,
                        )
                    }
                }
            }
        }

        is MarkdownBlock.Image -> {
            val label = block.title?.takeIf { it.isNotBlank() }
                ?: block.alt.takeIf { it.isNotBlank() }
                ?: block.src
            AntigravitySurfaceCard(
                containerColor = colors.surfaceSubtleBox,
                cornerRadius = 14.dp,
                contentPadding = PaddingValues(12.dp),
                onClick = { onLinkClick(block.src) },
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Image,
                        contentDescription = tr("Image", "图片"),
                        tint = colors.accentPeriwinkle,
                        modifier = Modifier.size(20.dp),
                    )
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = label,
                            style = MaterialTheme.typography.titleSmall,
                            color = colors.inkReading,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = block.src,
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.inkMuted,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }

        is MarkdownBlock.Details -> {
            var expanded by remember(block.id) { mutableStateOf(block.isOpenByDefault) }
            val summaryText = buildInlineAnnotatedString(block.summary, colors, onLinkClick)
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = colors.surfaceSubtleBox,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .clickable { expanded = !expanded }
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = if (expanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                            contentDescription = if (expanded) tr("Collapse", "收起") else tr("Expand", "展开"),
                            tint = colors.inkSecondary,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            text = summaryText,
                            style = MaterialTheme.typography.titleSmall,
                            color = colors.inkLabel,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    if (expanded && block.blocks.isNotEmpty()) {
                        HorizontalDivider(color = colors.subtleDivider)
                        Box(modifier = Modifier.padding(12.dp)) {
                            MarkdownContentView(
                                blocks = block.blocks,
                                onLinkClick = onLinkClick,
                            )
                        }
                    }
                }
            }
        }

        is MarkdownBlock.Carousel -> {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                block.slides.forEach { slideBlocks ->
                    AntigravitySurfaceCard(
                        modifier = Modifier.widthIn(min = 240.dp, max = 320.dp),
                        containerColor = colors.surfaceSubtleBox,
                        cornerRadius = 14.dp,
                        contentPadding = PaddingValues(12.dp),
                    ) {
                        MarkdownContentView(
                            blocks = slideBlocks,
                            onLinkClick = onLinkClick,
                        )
                    }
                }
            }
        }

        is MarkdownBlock.Mermaid -> {
            MermaidPreviewCard(source = block.source)
        }

        is MarkdownBlock.FootnoteSection -> {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                HorizontalDivider(color = colors.subtleDivider)
                block.items.forEach { item ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Text(
                            text = "[${item.label}]",
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.accentPeriwinkle,
                        )
                        Text(
                            text = buildInlineAnnotatedString(item.inlines, colors, onLinkClick),
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.inkSecondary,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CodeBlockCard(
    language: String?,
    code: String,
) {
    val colors = LocalAntigravityColors.current
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = colors.surfaceCodeBlock,
        border = BorderStroke(1.dp, colors.cardBorder),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surfaceElevated.copy(alpha = 0.55f))
                    .padding(horizontal = 12.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Code,
                    contentDescription = null,
                    tint = colors.inkMuted,
                    modifier = Modifier.size(14.dp),
                )
                Text(
                    text = language?.takeIf { it.isNotBlank() }?.lowercase() ?: "code",
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.inkSecondary,
                )
            }
            HorizontalDivider(color = colors.subtleDivider)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(12.dp),
            ) {
                Text(
                    text = code.trimEnd('\n'),
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontFamily = FontFamily.Monospace,
                        lineHeight = 19.sp,
                    ),
                    color = colors.inkLabel,
                )
            }
        }
    }
}

@Composable
private fun MermaidPreviewCard(source: String) {
    val colors = LocalAntigravityColors.current
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        color = colors.surfaceCodeBlock,
        border = BorderStroke(1.dp, colors.cardBorder),
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surfaceSelectionTint.copy(alpha = 0.7f))
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.AccountTree,
                    contentDescription = tr("Mermaid Diagram", "Mermaid 图表"),
                    tint = colors.accentPeriwinkle,
                    modifier = Modifier.size(15.dp),
                )
                Text(
                    text = tr("Mermaid Diagram", "Mermaid 图表"),
                    style = MaterialTheme.typography.labelLarge,
                    color = colors.inkLabel,
                )
            }
            HorizontalDivider(color = colors.subtleDivider)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(12.dp),
            ) {
                Text(
                    text = source.trim(),
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontFamily = FontFamily.Monospace,
                    ),
                    color = colors.inkSecondary,
                )
            }
        }
    }
}

@Composable
private fun MarkdownTableCard(
    table: MarkdownBlock.Table,
    onLinkClick: (String) -> Unit,
) {
    val colors = LocalAntigravityColors.current
    val columnCount = maxOf(
        table.headers.size,
        table.rows.maxOfOrNull { it.size } ?: 0,
    ).coerceAtLeast(1)

    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = colors.surfaceCard,
        border = BorderStroke(1.dp, colors.cardBorder),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
        ) {
            if (table.headers.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .background(colors.surfaceElevated)
                        .padding(vertical = 8.dp),
                ) {
                    for (col in 0 until columnCount) {
                        val cellInlines = table.headers.getOrNull(col).orEmpty()
                        val align = table.alignments.getOrNull(col).toTextAlign()
                        Text(
                            text = buildInlineAnnotatedString(cellInlines, colors, onLinkClick),
                            style = MaterialTheme.typography.titleSmall,
                            color = colors.inkReading,
                            textAlign = align,
                            modifier = Modifier
                                .width(136.dp)
                                .padding(horizontal = 10.dp),
                        )
                    }
                }
                HorizontalDivider(color = colors.subtleDivider)
            }

            table.rows.forEachIndexed { rowIndex, rowCells ->
                val rowBg = if (rowIndex % 2 == 1) {
                    colors.surfaceSubtleBox.copy(alpha = 0.55f)
                } else {
                    Color.Transparent
                }
                Row(
                    modifier = Modifier
                        .background(rowBg)
                        .padding(vertical = 7.dp),
                ) {
                    for (col in 0 until columnCount) {
                        val cellInlines = rowCells.getOrNull(col).orEmpty()
                        val align = table.alignments.getOrNull(col).toTextAlign()
                        Text(
                            text = buildInlineAnnotatedString(cellInlines, colors, onLinkClick),
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.inkLabel,
                            textAlign = align,
                            modifier = Modifier
                                .width(136.dp)
                                .padding(horizontal = 10.dp),
                        )
                    }
                }
                if (rowIndex < table.rows.lastIndex) {
                    HorizontalDivider(color = colors.subtleDivider.copy(alpha = 0.65f))
                }
            }
        }
    }
}

private fun MarkdownTableAlignment?.toTextAlign(): TextAlign = when (this) {
    MarkdownTableAlignment.CENTER -> TextAlign.Center
    MarkdownTableAlignment.TRAILING -> TextAlign.End
    MarkdownTableAlignment.LEADING, null -> TextAlign.Start
}

private fun buildInlineAnnotatedString(
    inlines: List<MarkdownInline>,
    colors: AntigravityExtendedColors,
    onLinkClick: (String) -> Unit,
): AnnotatedString = buildAnnotatedString {
    appendMarkdownInlines(inlines, colors, onLinkClick)
}

private fun AnnotatedString.Builder.appendMarkdownInlines(
    inlines: List<MarkdownInline>,
    colors: AntigravityExtendedColors,
    onLinkClick: (String) -> Unit,
) {
    for (inline in inlines) {
        when (inline) {
            is MarkdownInline.Text -> append(inline.value)

            MarkdownInline.SoftBreak -> append("\n")

            is MarkdownInline.Code -> {
                withStyle(
                    SpanStyle(
                        fontFamily = FontFamily.Monospace,
                        fontSize = 14.sp,
                        color = colors.inkInlineCode,
                        background = colors.surfaceInlineCode,
                    ),
                ) {
                    append(" ${inline.value} ")
                }
            }

            is MarkdownInline.Strong -> {
                withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) {
                    appendMarkdownInlines(inline.children, colors, onLinkClick)
                }
            }

            is MarkdownInline.Emphasis -> {
                withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                    appendMarkdownInlines(inline.children, colors, onLinkClick)
                }
            }

            is MarkdownInline.Strikethrough -> {
                withStyle(
                    SpanStyle(
                        textDecoration = TextDecoration.LineThrough,
                        color = colors.inkSecondary,
                    ),
                ) {
                    appendMarkdownInlines(inline.children, colors, onLinkClick)
                }
            }

            is MarkdownInline.Underline -> {
                withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) {
                    appendMarkdownInlines(inline.children, colors, onLinkClick)
                }
            }

            is MarkdownInline.Highlight -> {
                withStyle(
                    SpanStyle(
                        color = colors.inkMarkHighlight,
                        background = colors.surfaceMarkHighlight,
                    ),
                ) {
                    appendMarkdownInlines(inline.children, colors, onLinkClick)
                }
            }

            is MarkdownInline.Superscript -> {
                withStyle(
                    SpanStyle(
                        baselineShift = BaselineShift.Superscript,
                        fontSize = 11.sp,
                    ),
                ) {
                    append(inline.value)
                }
            }

            is MarkdownInline.SubscriptText -> {
                withStyle(
                    SpanStyle(
                        baselineShift = BaselineShift.Subscript,
                        fontSize = 11.sp,
                    ),
                ) {
                    append(inline.value)
                }
            }

            is MarkdownInline.KeyboardKey -> {
                withStyle(
                    SpanStyle(
                        fontFamily = FontFamily.Monospace,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = colors.inkKbd,
                        background = colors.surfaceKbd,
                    ),
                ) {
                    append(" ${inline.value} ")
                }
            }

            is MarkdownInline.Link -> {
                withLink(
                    LinkAnnotation.Clickable(
                        tag = inline.destination,
                        styles = TextLinkStyles(
                            style = SpanStyle(
                                color = colors.accentPeriwinkle,
                                textDecoration = TextDecoration.Underline,
                            ),
                        ),
                        linkInteractionListener = {
                            onLinkClick(inline.destination)
                        },
                    ),
                ) {
                    appendMarkdownInlines(inline.label, colors, onLinkClick)
                }
            }

            is MarkdownInline.InlineMath -> {
                withStyle(
                    SpanStyle(
                        fontFamily = FontFamily.Monospace,
                        fontStyle = FontStyle.Italic,
                        color = colors.inkInlineCode,
                    ),
                ) {
                    append(inline.latex)
                }
            }

            is MarkdownInline.InlineImage -> {
                withStyle(
                    SpanStyle(
                        color = colors.accentPeriwinkle,
                        background = colors.surfacePill,
                    ),
                ) {
                    append(" [${inline.alt.ifBlank { inline.src }}] ")
                }
            }

            is MarkdownInline.FootnoteRef -> {
                withStyle(
                    SpanStyle(
                        baselineShift = BaselineShift.Superscript,
                        fontSize = 11.sp,
                        color = colors.accentPeriwinkle,
                        fontWeight = FontWeight.SemiBold,
                    ),
                ) {
                    append("[${inline.label}]")
                }
            }
        }
    }
}
