package dev.antigravity.android.ui.review

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.PictureAsPdf
import androidx.compose.material.icons.rounded.Public
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.components.AntigravityChip
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.components.MarkdownContentView
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.AntigravityExtendedColors
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.localizedTitle
import dev.antigravity.shared.domain.EsddVerificationFixtures
import dev.antigravity.shared.model.ArtifactKind
import dev.antigravity.shared.model.ArtifactSnapshot
import dev.antigravity.shared.model.DiffCompareMode
import dev.antigravity.shared.model.DiffLine
import dev.antigravity.shared.model.JupyterCellKind
import dev.antigravity.shared.model.JupyterNotebookDocument
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/**
 * UE12_TURN_DIFF_REVIEW: Native Material 3 Turn Diff Line-Level Review & Git VCS Workbench
 * (`Review changes`), with turn/compare-mode chips, file pager card, hunk revert, syntax-highlighted
 * monospace diff lines, inline Line 29 comment composer (`Add to review` / `Send to agent`),
 * and docked `Viewed` + `Revert file` + `Accept file` footer.
 */
@Composable
fun TurnDiffReviewScreen(
    coordinator: AntigravityCoreCoordinator,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val lang = LocalAppLanguage.current
    val reviewState by coordinator.reviewStore.state.collectAsState()
    val chatState by coordinator.chatState.collectAsState()
    val scope = rememberCoroutineScope()

    val activeCascadeId = chatState.activeCascadeId.ifBlank { "cas-rate-limiter" }
    val diffs = reviewState.diffs
    val fileIndex = reviewState.selectedDiffFileIndex.coerceIn(0, (diffs.size - 1).coerceAtLeast(0))
    val activeDiff = diffs.getOrNull(fileIndex)

    var showCompareModeBar by remember { mutableStateOf(false) }
    var isLineCommentOpen by remember { mutableStateOf(true) }
    var lineCommentDraft by remember { mutableStateOf(EsddVerificationFixtures.INITIAL_LINE_COMMENT_DRAFT) }
    var feedbackBanner by remember { mutableStateOf<String?>(null) }

    Scaffold(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
        containerColor = colors.canvasObsidian,
        topBar = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(horizontal = 4.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .defaultMinSize(
                            minWidth = AntigravityDesignTokens.MinTouchTarget,
                            minHeight = AntigravityDesignTokens.MinTouchTarget,
                        )
                        .testTag("btn-back-diff-review"),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = tr("Back", "返回"),
                        tint = colors.accentPeriwinkle,
                    )
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(1.dp),
                ) {
                    Text(
                        text = tr("Review changes", "审查变更"),
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        color = colors.inkReading,
                        maxLines = 1,
                    )
                    Text(
                        text = "Add rate limiter to /transfers",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                Surface(
                    onClick = {
                        coordinator.reviewStore.acceptAllDiffs()
                        feedbackBanner = lang.t("Accepted all ${diffs.size} files", "已接受全部 ${diffs.size} 个文件")
                    },
                    modifier = Modifier
                        .defaultMinSize(minWidth = 86.dp, minHeight = 44.dp)
                        .testTag("btn-accept-all-diffs"),
                    shape = RoundedCornerShape(100.dp),
                    color = colors.surfaceElevated,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Box(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = tr("Accept all", "全部接受"),
                            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                            color = colors.inkReading,
                        )
                    }
                }

                IconButton(
                    onClick = { showCompareModeBar = !showCompareModeBar },
                    modifier = Modifier
                        .defaultMinSize(
                            minWidth = AntigravityDesignTokens.MinTouchTarget,
                            minHeight = AntigravityDesignTokens.MinTouchTarget,
                        )
                        .testTag("btn-toggle-compare-mode"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Tune,
                        contentDescription = tr("Compare mode", "对比模式"),
                        tint = if (showCompareModeBar) colors.accentPeriwinkle else colors.inkLabel,
                    )
                }
            }
        },
        bottomBar = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.canvasObsidian)
                    .navigationBarsPadding()
                    .imePadding(),
            ) {
                HorizontalDivider(color = colors.subtleDivider)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    // Viewed M3 Checkbox
                    Row(
                        modifier = Modifier
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .clickable(role = Role.Checkbox) {
                                activeDiff?.let { coordinator.reviewStore.toggleFileReviewed(it.filePath) }
                            }
                            .padding(end = 6.dp)
                            .testTag("checkbox-viewed"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Checkbox(
                            checked = activeDiff?.isReviewed == true,
                            onCheckedChange = null,
                            colors = CheckboxDefaults.colors(
                                checkedColor = colors.pillActiveBackground,
                                uncheckedColor = colors.inkMuted,
                                checkmarkColor = colors.pillActiveForeground,
                            ),
                        )
                        Text(
                            text = tr("Viewed", "已查看"),
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 14.sp),
                            color = colors.inkReading,
                        )
                    }

                    Spacer(modifier = Modifier.weight(1f))

                    FilledTonalButton(
                        onClick = {
                            activeDiff?.let { diff ->
                                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                    val client = coordinator.connectionStore.activeClient()
                                    coordinator.reviewStore.discardFile(
                                        client = client,
                                        cascadeId = activeCascadeId,
                                        filePath = diff.filePath,
                                    )
                                }
                                feedbackBanner = lang.t("Reverted ${diff.filePath}", "已还原 ${diff.filePath}")
                            }
                        },
                        modifier = Modifier
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-revert-file"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.filledTonalButtonColors(
                            containerColor = colors.surfaceElevated,
                            contentColor = colors.inkReading,
                        ),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                    ) {
                        Text(
                            text = tr("Revert file", "还原文件"),
                            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                        )
                    }

                    Button(
                        onClick = {
                            activeDiff?.let { diff ->
                                if (!diff.isReviewed) {
                                    coordinator.reviewStore.toggleFileReviewed(diff.filePath)
                                }
                                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                    val client = coordinator.connectionStore.activeClient()
                                    coordinator.reviewStore.stageFile(
                                        client = client,
                                        cascadeId = activeCascadeId,
                                        filePath = diff.filePath,
                                    )
                                }
                                feedbackBanner = lang.t("Accepted ${diff.filePath}", "已接受 ${diff.filePath}")
                            }
                        },
                        modifier = Modifier
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-accept-file"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.accentPeriwinkle,
                            contentColor = colors.inkOnPrimaryCta,
                        ),
                        contentPadding = PaddingValues(horizontal = 18.dp, vertical = 10.dp),
                    ) {
                        Text(
                            text = tr("Accept file", "接受文件"),
                            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                        )
                    }
                }
            }
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            // Turn Selector Strip (`Turn 1`, `Turn 2`, `Turn 3 · latest`, `All`)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 14.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                TurnChip(
                    label = tr("Turn 1", "第 1 轮"),
                    selected = reviewState.selectedDiffTurn == 1,
                    onClick = { coordinator.reviewStore.selectDiffTurn(1) },
                    modifier = Modifier.testTag("turn-pill-1"),
                )
                TurnChip(
                    label = tr("Turn 2", "第 2 轮"),
                    selected = reviewState.selectedDiffTurn == 2,
                    onClick = { coordinator.reviewStore.selectDiffTurn(2) },
                    modifier = Modifier.testTag("turn-pill-2"),
                )
                TurnChip(
                    label = tr("Turn 3 · latest", "第 3 轮 · 最新"),
                    selected = reviewState.selectedDiffTurn == 3,
                    onClick = { coordinator.reviewStore.selectDiffTurn(3) },
                    modifier = Modifier.testTag("turn-pill-3-latest"),
                )
                TurnChip(
                    label = tr("All", "全部"),
                    selected = reviewState.selectedDiffTurn == 0,
                    onClick = { coordinator.reviewStore.selectDiffTurn(0) },
                    modifier = Modifier.testTag("turn-pill-all"),
                )
            }

            if (showCompareModeBar) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(horizontal = 14.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    DiffCompareMode.entries.forEach { mode ->
                        AntigravityChip(
                            label = mode.localizedTitle(lang),
                            selected = reviewState.compareMode == mode,
                            onClick = { coordinator.reviewStore.selectDiffMode(mode) },
                        )
                    }
                }
            }

            // File Pager Card (`< middleware/ratelimit.go  File 1 of 4 · +96 -4 >`)
            if (activeDiff != null) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp, vertical = 6.dp)
                        .testTag("file-pager-card"),
                    shape = RoundedCornerShape(16.dp),
                    color = colors.surfaceCard,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 6.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        IconButton(
                            onClick = {
                                if (diffs.isNotEmpty()) {
                                    val prevIdx = if (fileIndex > 0) fileIndex - 1 else diffs.lastIndex
                                    coordinator.reviewStore.selectDiffFile(prevIdx)
                                }
                            },
                            modifier = Modifier.size(38.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.ChevronLeft,
                                contentDescription = tr("Previous file", "上一个文件"),
                                tint = colors.inkSecondary,
                            )
                        }

                        Column(
                            modifier = Modifier.weight(1f),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            Text(
                                text = activeDiff.filePath,
                                style = MaterialTheme.typography.titleSmall.copy(
                                    fontFamily = FontFamily.Monospace,
                                    fontWeight = FontWeight.Bold,
                                ),
                                color = colors.inkReading,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(
                                    text = tr("File ${fileIndex + 1} of ${diffs.size}", "第 ${fileIndex + 1}/${diffs.size} 个文件"),
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        fontFamily = FontFamily.SansSerif,
                                    ),
                                    color = colors.inkSecondary,
                                )
                                Text(
                                    text = "+${activeDiff.additions}",
                                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                                    color = colors.statusDone,
                                )
                                Text(
                                    text = "-${activeDiff.deletions}",
                                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                                    color = colors.statusError,
                                )
                            }
                        }

                        IconButton(
                            onClick = {
                                if (diffs.isNotEmpty()) {
                                    val nextIdx = (fileIndex + 1) % diffs.size
                                    coordinator.reviewStore.selectDiffFile(nextIdx)
                                }
                            },
                            modifier = Modifier.size(38.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.ChevronRight,
                                contentDescription = tr("Next file", "下一个文件"),
                                tint = colors.inkSecondary,
                            )
                        }
                    }
                }

                // Hunk Header Bar
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(colors.surfaceObsidian)
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = activeDiff.hunkHeader,
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.5.sp,
                        ),
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = tr("Revert hunk", "还原代码块"),
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                        color = colors.inkReading,
                        modifier = Modifier
                            .clickable {
                                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                    val client = coordinator.connectionStore.activeClient()
                                    coordinator.reviewStore.revertHunk(
                                        client = client,
                                        cascadeId = activeCascadeId,
                                        filePath = activeDiff.filePath,
                                        hunkHeader = activeDiff.hunkHeader,
                                    )
                                }
                                feedbackBanner = lang.t(
                                    "Reverted hunk in ${activeDiff.filePath}",
                                    "已还原 ${activeDiff.filePath} 中的代码块",
                                )
                            }
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                            .testTag("btn-revert-hunk"),
                    )
                }

                HorizontalDivider(color = colors.subtleDivider)

                // Scrollable Diff Lines + Inline Line 29 Comment Composer
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState()),
                ) {
                    activeDiff.lines
                        .filter { it.kind != DiffLine.Kind.HUNK_HEADER }
                        .forEach { line ->
                            val lineNum = line.displayLineNumber
                            val isSelectedLine29 = lineNum == reviewState.selectedDiffLineNumber
                            DiffCodeLineRow(
                                line = line,
                                isSelected = isSelectedLine29,
                                onClick = {
                                    if (lineNum != null) {
                                        coordinator.reviewStore.selectDiffLine(lineNum)
                                        isLineCommentOpen = true
                                    }
                                },
                                modifier = if (lineNum == 29) Modifier.testTag("diff-line-29") else Modifier,
                            )

                            if (isSelectedLine29 && isLineCommentOpen) {
                                InlineLineCommentComposerCard(
                                    lineNumber = lineNum ?: 29,
                                    draftText = lineCommentDraft,
                                    onDraftChange = { lineCommentDraft = it },
                                    onAddToReview = {
                                        coordinator.reviewStore.addDiffLineComment(
                                            filePath = activeDiff.filePath,
                                            lineNumber = lineNum ?: 29,
                                            body = lineCommentDraft,
                                        )
                                        feedbackBanner = lang.t(
                                            "Added comment on line ${lineNum ?: 29}",
                                            "已在第 ${lineNum ?: 29} 行添加评论",
                                        )
                                    },
                                    onSendToAgent = {
                                        coordinator.reviewStore.addDiffLineComment(
                                            filePath = activeDiff.filePath,
                                            lineNumber = lineNum ?: 29,
                                            body = lineCommentDraft,
                                        )
                                        scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                            val client = coordinator.connectionStore.activeClient()
                                            coordinator.reviewStore.sendDiffLineComments(
                                                client = client,
                                                cascadeId = activeCascadeId,
                                            )
                                        }
                                        feedbackBanner = lang.t(
                                            "Sent line ${lineNum ?: 29} comment to agent",
                                            "已将第 ${lineNum ?: 29} 行的评论发送给智能体",
                                        )
                                    },
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                                )
                            }
                        }

                    if (feedbackBanner != null) {
                        Surface(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 14.dp, vertical = 8.dp),
                            shape = RoundedCornerShape(10.dp),
                            color = colors.statusDone.copy(alpha = 0.14f),
                            border = BorderStroke(1.dp, colors.statusDone.copy(alpha = 0.35f)),
                        ) {
                            Text(
                                text = feedbackBanner.orEmpty(),
                                style = MaterialTheme.typography.labelMedium,
                                color = colors.statusDone,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                            )
                        }
                    }
                }
            } else {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = tr("No file changes in this diff scope.", "当前差异范围内没有文件变更。"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.inkSecondary,
                    )
                }
            }
        }
    }
}

@Composable
private fun TurnChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    Surface(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minHeight = 36.dp),
        shape = RoundedCornerShape(100.dp),
        color = if (selected) colors.pillActiveBackground else colors.surfacePill,
        border = if (selected) null else BorderStroke(1.dp, colors.cardBorder),
    ) {
        Box(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 7.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge.copy(
                    fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                ),
                color = if (selected) colors.pillActiveForeground else colors.inkSecondary,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun DiffCodeLineRow(
    line: DiffLine,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val rowBg = when {
        isSelected -> colors.surfaceSelectionTint
        line.kind == DiffLine.Kind.ADDITION -> colors.surfaceDiffAdd
        line.kind == DiffLine.Kind.DELETION -> colors.surfaceDiffRemove
        else -> Color.Transparent
    }
    val prefixSymbol = when (line.kind) {
        DiffLine.Kind.ADDITION -> "+"
        DiffLine.Kind.DELETION -> "-"
        else -> " "
    }
    val prefixColor = when (line.kind) {
        DiffLine.Kind.ADDITION -> colors.statusDone
        DiffLine.Kind.DELETION -> colors.statusError
        else -> Color.Transparent
    }
    val lineNumColor = when {
        isSelected -> colors.accentPeriwinkle
        line.kind == DiffLine.Kind.ADDITION -> colors.statusDone
        line.kind == DiffLine.Kind.DELETION -> colors.statusError
        else -> colors.inkMuted
    }

    val highlightedCode = remember(line.text, line.wordHighlightRange, line.kind, colors) {
        buildSyntaxHighlightedDiffLine(line, colors)
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(rowBg)
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .width(3.dp)
                .height(if (isSelected) 28.dp else 22.dp)
                .background(if (isSelected) colors.accentPeriwinkle else Color.Transparent),
        )
        Row(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 8.dp, vertical = if (isSelected) 5.dp else 2.5.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = line.displayLineNumber?.toString().orEmpty(),
                style = MaterialTheme.typography.labelSmall.copy(
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.5.sp,
                ),
                color = lineNumColor,
                modifier = Modifier.width(22.dp),
            )
            Text(
                text = prefixSymbol,
                style = MaterialTheme.typography.labelSmall.copy(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Bold,
                    fontSize = 12.sp,
                ),
                color = prefixColor,
                modifier = Modifier.width(10.dp),
            )
            Text(
                text = highlightedCode,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp,
                    lineHeight = 17.sp,
                ),
                color = colors.inkReading,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun InlineLineCommentComposerCard(
    lineNumber: Int,
    draftText: String,
    onDraftChange: (String) -> Unit,
    onAddToReview: () -> Unit,
    onSendToAgent: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    AntigravitySurfaceCard(
        modifier = modifier
            .fillMaxWidth()
            .testTag("line-comment-composer"),
        containerColor = colors.surfaceCard,
        borderColor = colors.cardBorder,
        cornerRadius = 18.dp,
        contentPadding = PaddingValues(13.dp),
    ) {
        Text(
            text = tr("Comment on line $lineNumber", "评论第 $lineNumber 行"),
            style = MaterialTheme.typography.labelMedium,
            color = colors.inkSecondary,
        )
        Spacer(modifier = Modifier.height(6.dp))
        BasicTextField(
            value = draftText,
            onValueChange = onDraftChange,
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                fontSize = 14.sp,
                lineHeight = 20.sp,
                color = colors.inkReading,
            ),
            cursorBrush = SolidColor(colors.accentPeriwinkle),
            modifier = Modifier
                .fillMaxWidth()
                .testTag("line-comment-input"),
        )
        Spacer(modifier = Modifier.height(10.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FilledTonalButton(
                onClick = onAddToReview,
                modifier = Modifier
                    .defaultMinSize(minHeight = 40.dp)
                    .testTag("btn-add-to-review"),
                shape = RoundedCornerShape(100.dp),
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = colors.surfaceElevated,
                    contentColor = colors.inkReading,
                ),
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
            ) {
                Text(
                    text = tr("Add to review", "加入审查"),
                    style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.sp),
                )
            }
            Spacer(modifier = Modifier.width(8.dp))
            Button(
                onClick = onSendToAgent,
                modifier = Modifier
                    .defaultMinSize(minHeight = 40.dp)
                    .testTag("btn-send-to-agent"),
                shape = RoundedCornerShape(100.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.accentPeriwinkle,
                    contentColor = colors.inkOnPrimaryCta,
                ),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            ) {
                Text(
                    text = tr("Send to agent", "发送给智能体"),
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                )
            }
        }
    }
}

private fun buildSyntaxHighlightedDiffLine(
    line: DiffLine,
    colors: AntigravityExtendedColors,
): AnnotatedString = buildAnnotatedString {
    val text = line.text
    val highlight = line.wordHighlightRange
    val highlightStart = if (!highlight.isNullOrEmpty()) text.indexOf(highlight) else -1
    val keywords = setOf("type", "struct", "const", "func", "defer", "return", "if", "var")
    val types = setOf("float64", "string", "bool", "Time", "Mutex", "Limiter")

    var i = 0
    while (i < text.length) {
        if (highlight != null && highlightStart >= 0 && i == highlightStart) {
            val bg = when (line.kind) {
                DiffLine.Kind.DELETION -> colors.statusError.copy(alpha = 0.34f)
                DiffLine.Kind.ADDITION -> colors.statusDone.copy(alpha = 0.32f)
                else -> colors.surfaceSelectionTint
            }
            withStyle(SpanStyle(background = bg, color = colors.inkReading, fontWeight = FontWeight.Medium)) {
                append(highlight)
            }
            i += highlight.length
            continue
        }
        val ch = text[i]
        if (ch.isLetter() || ch == '_') {
            var j = i
            while (j < text.length && (text[j].isLetterOrDigit() || text[j] == '_')) j++
            val token = text.substring(i, j)
            val tint = when {
                token in keywords -> colors.syntaxKeyword
                token in types -> colors.syntaxType
                else -> colors.inkReading
            }
            withStyle(SpanStyle(color = tint)) { append(token) }
            i = j
        } else {
            append(ch)
            i++
        }
    }
}

/**
 * Rich multi-format artifact viewer sheet supporting Markdown, PDF, Jupyter `.ipynb` notebooks,
 * Images/Videos, Generative UI HTML, and forward-compatible unknown artifacts.
 */
@Composable
fun RichArtifactViewerSheet(
    artifact: ArtifactSnapshot,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    var showRawNotebook by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier
            .fillMaxSize()
            .testTag("sheet-rich-artifact-viewer"),
        color = colors.canvasObsidian,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 6.dp),
                ) {
                    Text(
                        text = artifact.title,
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = artifact.artifactPath,
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.inkMuted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                TextButton(onClick = onDismiss) {
                    Text(tr("Done", "完成"), color = colors.accentPeriwinkle)
                }
            }

            HorizontalDivider(color = colors.subtleDivider)

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                when (artifact.kind) {
                    ArtifactKind.JUPYTER_NOTEBOOK -> {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            AntigravityChip(
                                label = tr("Preview", "预览"),
                                selected = !showRawNotebook,
                                onClick = { showRawNotebook = false },
                            )
                            AntigravityChip(
                                label = tr("Raw JSON", "原始 JSON"),
                                selected = showRawNotebook,
                                onClick = { showRawNotebook = true },
                            )
                        }
                        if (showRawNotebook) {
                            Surface(
                                shape = RoundedCornerShape(12.dp),
                                color = colors.surfaceCodeBlock,
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(
                                    text = artifact.content,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = colors.inkLabel,
                                    modifier = Modifier.padding(12.dp),
                                )
                            }
                        } else {
                            val doc = remember(artifact.content) {
                                JupyterNotebookDocument.parse(artifact.content)
                            }
                            if (doc != null) {
                                Text(
                                    text = tr(
                                        "Kernel: ${doc.kernelName} · ${doc.cells.size} cells",
                                        "内核：${doc.kernelName} · ${doc.cells.size} 个单元格",
                                    ),
                                    style = MaterialTheme.typography.labelMedium,
                                    color = colors.accentPeriwinkle,
                                )
                                doc.cells.forEachIndexed { idx, cell ->
                                    AntigravitySurfaceCard(
                                        modifier = Modifier.fillMaxWidth(),
                                        contentPadding = PaddingValues(12.dp),
                                    ) {
                                        Text(
                                            text = if (cell.cellType == JupyterCellKind.CODE) {
                                                "In [${cell.executionCount ?: " "}]:"
                                            } else {
                                                "Markdown #${idx + 1}"
                                            },
                                            style = MaterialTheme.typography.labelSmall,
                                            color = colors.inkMuted,
                                        )
                                        Spacer(modifier = Modifier.height(6.dp))
                                        Text(
                                            text = cell.source,
                                            style = if (cell.cellType == JupyterCellKind.CODE) {
                                                MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace)
                                            } else {
                                                MaterialTheme.typography.bodyMedium
                                            },
                                            color = colors.inkReading,
                                        )
                                        cell.outputs.forEach { out ->
                                            val outputText = out.errorValue?.let { "${out.errorName ?: "Error"}: $it" }
                                                ?: out.text
                                            if (!outputText.isNullOrBlank()) {
                                                Spacer(modifier = Modifier.height(6.dp))
                                                Text(
                                                    text = outputText,
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = if (out.errorValue != null) colors.statusError else colors.statusDone,
                                                )
                                            }
                                        }
                                    }
                                }
                            } else {
                                Text(
                                    text = artifact.content,
                                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                                    color = colors.inkLabel,
                                )
                            }
                        }
                    }

                    ArtifactKind.PDF_DOCUMENT -> {
                        AntigravitySurfaceCard(
                            modifier = Modifier.fillMaxWidth(),
                            contentPadding = PaddingValues(16.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.PictureAsPdf,
                                    contentDescription = tr("PDF Document", "PDF 文档"),
                                    tint = colors.statusError,
                                    modifier = Modifier.size(24.dp),
                                )
                                Column {
                                    Text(
                                        text = artifact.title,
                                        style = MaterialTheme.typography.titleSmall,
                                        color = colors.inkReading,
                                    )
                                    Text(
                                        text = artifact.summary.ifBlank { tr("PDF Document Preview", "PDF 文档预览") },
                                        style = MaterialTheme.typography.bodySmall,
                                        color = colors.inkSecondary,
                                    )
                                }
                            }
                        }
                    }

                    ArtifactKind.IMAGE_ASSET, ArtifactKind.VIDEO_ASSET -> {
                        AntigravitySurfaceCard(
                            modifier = Modifier.fillMaxWidth(),
                            contentPadding = PaddingValues(16.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Image,
                                    contentDescription = tr("Media Asset", "媒体资源"),
                                    tint = colors.accentPeriwinkle,
                                    modifier = Modifier.size(24.dp),
                                )
                                Column {
                                    Text(
                                        text = artifact.title,
                                        style = MaterialTheme.typography.titleSmall,
                                        color = colors.inkReading,
                                    )
                                    Text(
                                        text = artifact.summary.ifBlank { artifact.artifactPath },
                                        style = MaterialTheme.typography.bodySmall,
                                        color = colors.inkSecondary,
                                    )
                                }
                            }
                        }
                    }

                    ArtifactKind.GENERATIVE_UI_HTML, ArtifactKind.URL_BOOKMARK -> {
                        AntigravitySurfaceCard(
                            modifier = Modifier.fillMaxWidth(),
                            contentPadding = PaddingValues(14.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Public,
                                    contentDescription = tr("Interactive HTML", "交互式 HTML"),
                                    tint = colors.accentPeriwinkle,
                                    modifier = Modifier.size(20.dp),
                                )
                                Text(
                                    text = tr("Interactive HTML / Bookmark Artifact", "交互式 HTML / 书签产物"),
                                    style = MaterialTheme.typography.titleSmall,
                                    color = colors.inkReading,
                                )
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = artifact.content.take(1200),
                                style = MaterialTheme.typography.labelSmall,
                                color = colors.inkSecondary,
                            )
                        }
                    }

                    ArtifactKind.UNKNOWN -> {
                        AntigravitySurfaceCard(
                            modifier = Modifier.fillMaxWidth(),
                            contentPadding = PaddingValues(14.dp),
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Code,
                                    contentDescription = tr("Forward-compatible artifact", "前向兼容产物"),
                                    tint = colors.accentPeriwinkle,
                                    modifier = Modifier.size(20.dp),
                                )
                                Text(
                                    text = tr("Artifact Preview (${artifact.rawKindName ?: "Raw"})", "产物预览（${artifact.rawKindName ?: "原始"}）"),
                                    style = MaterialTheme.typography.titleSmall,
                                    color = colors.inkReading,
                                )
                            }
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = artifact.content.ifBlank { artifact.summary },
                                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                                color = colors.inkLabel,
                            )
                        }
                    }

                    ArtifactKind.IMPLEMENTATION_PLAN,
                    ArtifactKind.WALKTHROUGH,
                    ArtifactKind.TASK_LIST,
                    -> {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Description,
                                contentDescription = null,
                                tint = colors.accentPeriwinkle,
                                modifier = Modifier.size(18.dp),
                            )
                            Text(
                                text = "v${artifact.version} · ${artifact.summary}",
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.inkSecondary,
                            )
                        }
                        MarkdownContentView(markdown = artifact.content)
                    }
                }
            }
        }
    }
}
