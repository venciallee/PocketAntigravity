package dev.antigravity.android.ui.review

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ChatBubbleOutline
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.PlanInlineComment
import dev.antigravity.shared.model.PlanProposedFileChange
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/**
 * UE11_PLAN_REVIEW: Native Material 3 Implementation Plan Review screen featuring Amber paused
 * review banner, MODIFY/NEW proposed file change badges, highlighted review spans, pending inline
 * comment cards, Material 3 floating text-selection action pill (`Comment` / `Copy`), and docked
 * `Proceed` + `Send N comments` decision bar.
 */
@Composable
fun ImplementationPlanReviewScreen(
    coordinator: AntigravityCoreCoordinator,
    onBack: () -> Unit,
    onProceed: () -> Unit = onBack,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val reviewState by coordinator.reviewStore.state.collectAsState()
    val chatState by coordinator.chatState.collectAsState()
    val scope = rememberCoroutineScope()

    val activeCascadeId = chatState.activeCascadeId.ifBlank { "cas-flaky-settlement" }
    val planChanges = reviewState.planChanges
    val planComments = reviewState.planComments
    val pendingCount = planComments.count { !it.statusLabel.equals("Sent", ignoreCase = true) }
        .let { if (it == 0 && planComments.isNotEmpty()) planComments.size else it }

    var showCommentComposer by remember { mutableStateOf(false) }
    var newCommentText by remember { mutableStateOf("") }
    var statusNotice by remember { mutableStateOf<String?>(null) }

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
                        .testTag("btn-back-from-plan"),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "Back",
                        tint = colors.accentPeriwinkle,
                    )
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(1.dp),
                ) {
                    Text(
                        text = "Implementation Plan",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = "Fix flaky TestSettlementBatch · v${reviewState.selectedArtifact?.version ?: 2}",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                // Comment Counter Pill `[💬 N]`
                Surface(
                    onClick = { showCommentComposer = !showCommentComposer },
                    modifier = Modifier
                        .defaultMinSize(minWidth = 54.dp, minHeight = 36.dp)
                        .testTag("plan-comments-badge"),
                    shape = RoundedCornerShape(100.dp),
                    color = colors.surfacePill,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.ChatBubbleOutline,
                            contentDescription = "Comments",
                            tint = colors.inkReading,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            text = planComments.size.toString(),
                            style = MaterialTheme.typography.labelLarge,
                            color = colors.inkReading,
                        )
                    }
                }

                IconButton(
                    onClick = {},
                    modifier = Modifier.defaultMinSize(
                        minWidth = AntigravityDesignTokens.MinTouchTarget,
                        minHeight = AntigravityDesignTokens.MinTouchTarget,
                    ),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.MoreVert,
                        contentDescription = "More options",
                        tint = colors.inkSecondary,
                    )
                }
            }
        },
        bottomBar = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.canvasObsidian)
                    .navigationBarsPadding(),
            ) {
                HorizontalDivider(color = colors.subtleDivider)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    FilledTonalButton(
                        onClick = {
                            coordinator.reviewStore.proceedPlan()
                            onProceed()
                        },
                        modifier = Modifier
                            .weight(1f)
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-plan-proceed"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.filledTonalButtonColors(
                            containerColor = colors.surfaceElevated,
                            contentColor = colors.inkReading,
                        ),
                    ) {
                        Text(
                            text = "Proceed",
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                            ),
                        )
                    }

                    Button(
                        onClick = {
                            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                val client = coordinator.connectionStore.activeClient()
                                coordinator.reviewStore.sendPlanComments(
                                    client = client,
                                    cascadeId = activeCascadeId,
                                )
                            }
                            statusNotice = "Sent $pendingCount review comments to agent"
                        },
                        modifier = Modifier
                            .weight(1.25f)
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-plan-send-comments"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.accentPeriwinkle,
                            contentColor = colors.inkOnPrimaryCta,
                        ),
                    ) {
                        Text(
                            text = "Send $pendingCount comments",
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 14.5.sp,
                                fontWeight = FontWeight.Bold,
                            ),
                            maxLines = 1,
                        )
                    }
                }
            }
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(13.dp),
        ) {
            // 1. Amber Paused Review Banner
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("plan-paused-banner"),
                shape = RoundedCornerShape(14.dp),
                color = colors.surfaceCard,
                border = BorderStroke(1.dp, colors.statusWaiting.copy(alpha = 0.32f)),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(colors.surfaceAmberTint)
                        .padding(horizontal = 14.dp, vertical = 11.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    StatusDot(color = colors.statusWaiting, size = 8.dp)
                    Text(
                        text = "Agent is paused until you review. Tap or select any text to comment.",
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.statusWaiting,
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            // 2. Plan Heading & Problem Summary
            Text(
                text = "Isolate the fake clock in settlement tests",
                style = MaterialTheme.typography.headlineSmall.copy(
                    fontSize = 22.sp,
                    lineHeight = 28.sp,
                    fontWeight = FontWeight.Bold,
                ),
                color = colors.inkReading,
            )

            Text(
                text = buildAnnotatedString {
                    append("TestSettlementBatch fails in ~3% of CI runs. Parallel subtests share one fake clock, so ")
                    withStyle(
                        SpanStyle(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 14.sp,
                            color = colors.inkInlineCode,
                            background = colors.surfaceInlineCode,
                        ),
                    ) {
                        append(" Advance() ")
                    }
                    append(" in one subtest moves time for the others.")
                },
                style = MaterialTheme.typography.bodyLarge.copy(
                    fontSize = 14.5.sp,
                    lineHeight = 22.sp,
                ),
                color = colors.inkLabel,
            )

            // 3. Proposed Changes Section
            Text(
                text = "Proposed changes",
                style = MaterialTheme.typography.titleMedium.copy(
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                ),
                color = colors.inkReading,
            )

            val firstChange = planChanges.getOrNull(0)
            val secondChange = planChanges.getOrNull(1)
            val thirdChange = planChanges.getOrNull(2)
            val primaryComment = planComments.firstOrNull()

            // Change 1: MODIFY settlement/batch.go + highlighted span + WL You Pending Card
            if (firstChange != null) {
                PlanChangeRowView(
                    change = firstChange,
                    highlightTint = colors.statusWaiting,
                )
            }
            if (primaryComment != null) {
                PendingInlineCommentCard(
                    comment = primaryComment,
                    modifier = Modifier.testTag("plan-pending-comment-card"),
                )
            }

            // Floating Material 3 Selection Action Pill (`Comment` | `Copy`)
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = colors.pillActiveBackground,
                    shadowElevation = 6.dp,
                ) {
                    Row(
                        modifier = Modifier.height(42.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Row(
                            modifier = Modifier
                                .clickable { showCommentComposer = true }
                                .padding(horizontal = 16.dp, vertical = 10.dp)
                                .testTag("selection-callout-comment"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.ChatBubbleOutline,
                                contentDescription = "Add comment",
                                tint = colors.pillActiveForeground,
                                modifier = Modifier.size(16.dp),
                            )
                            Text(
                                text = "Comment",
                                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                                color = colors.pillActiveForeground,
                            )
                        }
                        VerticalDivider(
                            modifier = Modifier.height(22.dp),
                            color = colors.pillActiveForeground.copy(alpha = 0.2f),
                        )
                        Box(
                            modifier = Modifier
                                .clickable { statusNotice = "Copied selected plan snippet" }
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                text = "Copy",
                                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                                color = colors.pillActiveForeground,
                            )
                        }
                    }
                }
            }

            // Change 2: MODIFY settlement/settlement_test.go + blue selection highlight
            if (secondChange != null) {
                PlanChangeRowView(
                    change = secondChange,
                    highlightTint = colors.accentPeriwinkle,
                )
            }

            // Inline Comment Composer (toggled when user taps Comment or badge)
            if (showCommentComposer) {
                AntigravitySurfaceCard(
                    modifier = Modifier.fillMaxWidth(),
                    borderColor = colors.accentPeriwinkle.copy(alpha = 0.55f),
                    contentPadding = PaddingValues(12.dp),
                ) {
                    Text(
                        text = "New comment on settlement/settlement_test.go",
                        style = MaterialTheme.typography.labelMedium,
                        color = colors.accentPeriwinkle,
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Box(modifier = Modifier.fillMaxWidth()) {
                        if (newCommentText.isEmpty()) {
                            Text(
                                text = "Write your review feedback...",
                                style = MaterialTheme.typography.bodyMedium,
                                color = colors.inkMuted,
                            )
                        }
                        BasicTextField(
                            value = newCommentText,
                            onValueChange = { newCommentText = it },
                            textStyle = MaterialTheme.typography.bodyMedium.copy(
                                fontSize = 14.sp,
                                color = colors.inkReading,
                            ),
                            cursorBrush = SolidColor(colors.accentPeriwinkle),
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("plan-new-comment-input"),
                        )
                    }
                    Spacer(modifier = Modifier.height(8.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Button(
                            onClick = {
                                val text = newCommentText.trim()
                                if (text.isNotEmpty()) {
                                    coordinator.reviewStore.addPlanComment(
                                        targetFilePath = "settlement/settlement_test.go",
                                        quotedSpan = "remove the package-level clk variable",
                                        body = text,
                                    )
                                    newCommentText = ""
                                    showCommentComposer = false
                                }
                            },
                            shape = RoundedCornerShape(100.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = colors.accentPeriwinkle,
                                contentColor = colors.inkOnPrimaryCta,
                            ),
                        ) {
                            Text("Add comment")
                        }
                    }
                }
            }

            // Change 3: NEW testutil/clock.go
            if (thirdChange != null) {
                PlanChangeRowView(
                    change = thirdChange,
                    highlightTint = colors.statusDone,
                )
            }

            // 4. Verification Section
            Text(
                text = "Verification",
                style = MaterialTheme.typography.titleMedium.copy(
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                ),
                color = colors.inkReading,
                modifier = Modifier.padding(top = 2.dp),
            )
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                color = colors.surfaceCodeBlock,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Text(
                    text = "go test -race -count=100 ./internal/settlement/...",
                    style = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    color = colors.inkInlineCode,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                )
            }

            if (statusNotice != null) {
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = colors.statusDone.copy(alpha = 0.14f),
                    border = BorderStroke(1.dp, colors.statusDone.copy(alpha = 0.35f)),
                ) {
                    Text(
                        text = statusNotice.orEmpty(),
                        style = MaterialTheme.typography.labelLarge,
                        color = colors.statusDone,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun PlanChangeRowView(
    change: PlanProposedFileChange,
    highlightTint: Color,
) {
    val colors = LocalAntigravityColors.current
    val isNew = change.changeKind.equals("NEW", ignoreCase = true)
    val badgeColor = if (isNew) colors.statusDone else colors.statusWaiting

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Surface(
                shape = RoundedCornerShape(6.dp),
                color = badgeColor.copy(alpha = 0.16f),
            ) {
                Text(
                    text = change.changeKind.uppercase(),
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontWeight = FontWeight.Bold,
                        fontSize = 10.5.sp,
                    ),
                    color = badgeColor,
                    modifier = Modifier.padding(horizontal = 7.dp, vertical = 3.dp),
                )
            }
            Text(
                text = change.filePath,
                style = MaterialTheme.typography.titleSmall.copy(
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.Medium,
                ),
                color = colors.inkReading,
            )
        }

        val span = change.highlightedSpan
        val annotated = buildAnnotatedString {
            val full = change.summaryText
            val idx = if (!span.isNullOrBlank()) full.indexOf(span) else -1
            if (idx >= 0 && span != null) {
                append(full.substring(0, idx))
                withStyle(
                    SpanStyle(
                        color = colors.inkReading,
                        background = highlightTint.copy(alpha = 0.22f),
                        textDecoration = if (highlightTint == colors.statusWaiting) TextDecoration.Underline else TextDecoration.None,
                    ),
                ) {
                    append(span)
                }
                append(full.substring(idx + span.length))
            } else {
                append(full)
            }
        }

        Text(
            text = annotated,
            style = MaterialTheme.typography.bodyLarge.copy(
                fontSize = 14.5.sp,
                lineHeight = 21.sp,
            ),
            color = colors.inkLabel,
        )
    }
}

@Composable
private fun PendingInlineCommentCard(
    comment: PlanInlineComment,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    AntigravitySurfaceCard(
        modifier = modifier.fillMaxWidth(),
        containerColor = colors.surfaceCard,
        borderColor = colors.cardBorder,
        cornerRadius = 16.dp,
        contentPadding = PaddingValues(13.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(24.dp)
                    .clip(CircleShape)
                    .background(colors.surfaceElevated),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = comment.authorInitials,
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontFamily = FontFamily.SansSerif,
                        fontWeight = FontWeight.Bold,
                        fontSize = 10.sp,
                    ),
                    color = colors.inkReading,
                )
            }
            Text(
                text = comment.authorName,
                style = MaterialTheme.typography.titleSmall,
                color = colors.inkReading,
            )
            Text(
                text = comment.statusLabel,
                style = MaterialTheme.typography.bodySmall,
                color = if (comment.statusLabel.equals("Sent", ignoreCase = true)) {
                    colors.statusDone
                } else {
                    colors.inkMuted
                },
            )
        }
        Spacer(modifier = Modifier.height(7.dp))
        Text(
            text = comment.body,
            style = MaterialTheme.typography.bodyMedium.copy(
                fontSize = 14.sp,
                lineHeight = 20.sp,
            ),
            color = colors.inkLabel,
        )
    }
}
