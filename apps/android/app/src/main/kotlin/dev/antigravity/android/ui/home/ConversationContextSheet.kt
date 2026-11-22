package dev.antigravity.android.ui.home

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Archive
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.automirrored.rounded.DriveFileMove
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.MarkChatRead
import androidx.compose.material.icons.rounded.MarkChatUnread
import androidx.compose.material.icons.rounded.PushPin
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.components.statusColorFor
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.CortexStepStatus

/**
 * UE03_CONTEXT_MENU_PIN: Material 3 long-press context preview sheet over a dimmed scrim,
 * showing the rich conversation preview card (Implementation Plan + Awaiting review chips),
 * 6 Material action rows, and a bottom Swipe Shortcut demonstration strip.
 */
@Composable
fun ConversationContextSheetScreen(
    coordinator: AntigravityCoreCoordinator,
    targetCascadeId: String = "cas-flaky-settlement",
    swipePreviewCascadeId: String = "cas-upgrade-go",
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()

    val targetSummary = remember(syncState.summaries, targetCascadeId) {
        syncState.summaries.firstOrNull { it.cascadeId == targetCascadeId }
    }
    val swipeSummary = remember(syncState.summaries, swipePreviewCascadeId) {
        syncState.summaries.firstOrNull { it.cascadeId == swipePreviewCascadeId }
    }

    var localSwipeArchived by remember(swipeSummary?.isArchived) {
        mutableStateOf(swipeSummary?.isArchived == true)
    }

    val title = targetSummary?.title ?: "Fix flaky TestSettlementBatch"
    val metadataLine = if (targetSummary != null) {
        "${targetSummary.projectSlug} · ${targetSummary.modelLabel} · ${targetSummary.relativeTimeLabel}"
    } else {
        "ledger-svc · Gemini 3.1 Pro · 8m"
    }
    val previewExcerpt = targetSummary?.lastMessagePreview?.takeIf { it.isNotBlank() }
        ?: "The flake comes from a shared fake clock across parallel subtests in settlement_test.go. I wrote a plan to isolate it per test — review it before I change anything?"
    val isPinned = targetSummary?.isPinned == true
    val isUnread = targetSummary?.isUnread == true
    val swipePinned = swipeSummary?.isPinned == true
    val statusDotColor = targetSummary?.let { colors.statusColorFor(it.status) } ?: colors.statusWaiting
    val statusGlow = targetSummary == null ||
        targetSummary.status == CortexStepStatus.WAITING ||
        targetSummary.status == CortexStepStatus.IN_PROGRESS

    val scrimColor = if (colors.isDark) Color.Black.copy(alpha = 0.72f) else Color.Black.copy(alpha = 0.42f)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
    ) {
        // Real dimmed Agents Home backdrop visible behind the Material 3 bottom sheet scrim
        AgentsHomeScreen(
            coordinator = coordinator,
            onOpenDisplayOptions = {},
            onOpenNewProject = {},
            onOpenProjectDetail = {},
            onOpenConversation = {},
            onLongPressConversation = {},
            modifier = Modifier.fillMaxSize(),
        )

        // Subtle dimmed backdrop scrim
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(scrimColor)
                .clickable(onClick = onDismiss),
        )

        // Material 3 Long-Press Bottom Sheet Container
        Surface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(top = 56.dp),
            shape = RoundedCornerShape(
                topStart = AntigravityDesignTokens.SheetCornerRadius,
                topEnd = AntigravityDesignTokens.SheetCornerRadius,
            ),
            color = colors.surfaceSheet,
            border = BorderStroke(1.dp, colors.cardBorder),
            tonalElevation = 4.dp,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp)
                    .padding(top = 10.dp, bottom = 22.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                // Centered M3 Sheet Drag Handle
                Box(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .size(width = 36.dp, height = 4.dp)
                        .clip(RoundedCornerShape(100.dp))
                        .background(colors.sheetHandle),
                )

                // 1. Rich Preview Card
                AntigravitySurfaceCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("context-preview-card"),
                    containerColor = colors.surfaceCard,
                    borderColor = colors.cardBorder,
                    cornerRadius = 22.dp,
                    contentPadding = PaddingValues(16.dp),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            StatusDot(
                                color = statusDotColor,
                                size = 9.dp,
                                glow = statusGlow,
                            )
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(2.dp),
                            ) {
                                Text(
                                    text = title,
                                    style = MaterialTheme.typography.titleMedium.copy(
                                        fontSize = 16.5.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    ),
                                    color = colors.inkReading,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    text = metadataLine,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = colors.inkSecondary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }

                        Text(
                            text = previewExcerpt,
                            style = MaterialTheme.typography.bodyLarge.copy(
                                fontSize = 14.5.sp,
                                lineHeight = 21.sp,
                            ),
                            color = colors.inkLabel,
                        )

                        Row(
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Surface(
                                onClick = onDismiss,
                                modifier = Modifier
                                    .defaultMinSize(minHeight = 40.dp)
                                    .testTag("chip-implementation-plan"),
                                shape = RoundedCornerShape(12.dp),
                                color = colors.surfaceBadge,
                                border = BorderStroke(1.dp, colors.cardBorder),
                            ) {
                                Row(
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Description,
                                        contentDescription = null,
                                        tint = colors.inkLabel,
                                        modifier = Modifier.size(16.dp),
                                    )
                                    Text(
                                        text = "Implementation Plan",
                                        style = MaterialTheme.typography.labelLarge,
                                        color = colors.inkReading,
                                        maxLines = 1,
                                        softWrap = false,
                                    )
                                }
                            }

                            Surface(
                                onClick = onDismiss,
                                modifier = Modifier
                                    .defaultMinSize(minHeight = 40.dp)
                                    .testTag("chip-awaiting-review"),
                                shape = RoundedCornerShape(12.dp),
                                color = colors.surfaceAmberTint,
                                border = BorderStroke(1.dp, colors.statusWaiting.copy(alpha = 0.30f)),
                            ) {
                                Box(
                                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        text = "Awaiting review",
                                        style = MaterialTheme.typography.labelLarge,
                                        color = colors.statusWaiting,
                                        maxLines = 1,
                                        softWrap = false,
                                    )
                                }
                            }
                        }
                    }
                }

                // 2. Material 3 Action List Card (6 Actions)
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(20.dp),
                    color = colors.surfacePopover,
                    border = BorderStroke(1.dp, colors.cardBorder),
                    tonalElevation = 2.dp,
                ) {
                    Column(modifier = Modifier.fillMaxWidth()) {
                        ContextMenuActionRow(
                            title = if (isPinned) "Unpin" else "Pin",
                            icon = Icons.Rounded.PushPin,
                            highlighted = true,
                            destructive = false,
                            modifier = Modifier.testTag("menu-action-pin"),
                            onClick = { coordinator.toggleConversationPinned(targetCascadeId) },
                        )
                        HorizontalDivider(color = colors.subtleDivider)

                        ContextMenuActionRow(
                            title = if (isUnread) "Mark as Read" else "Mark as Unread",
                            icon = if (isUnread) Icons.Rounded.MarkChatRead else Icons.Rounded.MarkChatUnread,
                            highlighted = false,
                            destructive = false,
                            modifier = Modifier.testTag("menu-action-unread"),
                            onClick = { coordinator.toggleConversationUnread(targetCascadeId) },
                        )
                        HorizontalDivider(color = colors.subtleDivider)

                        ContextMenuActionRow(
                            title = "Rename",
                            icon = Icons.Rounded.Edit,
                            highlighted = false,
                            destructive = false,
                            modifier = Modifier.testTag("menu-action-rename"),
                            onClick = onDismiss,
                        )
                        HorizontalDivider(color = colors.subtleDivider)

                        ContextMenuActionRow(
                            title = "Move to Project",
                            icon = Icons.AutoMirrored.Rounded.DriveFileMove,
                            trailingIcon = Icons.Rounded.ChevronRight,
                            highlighted = false,
                            destructive = false,
                            modifier = Modifier.testTag("menu-action-move"),
                            onClick = onDismiss,
                        )

                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(6.dp)
                                .background(colors.surfaceElevated),
                        )

                        ContextMenuActionRow(
                            title = "Archive",
                            icon = Icons.Rounded.Archive,
                            highlighted = false,
                            destructive = false,
                            modifier = Modifier.testTag("menu-action-archive"),
                            onClick = {
                                coordinator.archiveConversation(targetCascadeId)
                                onDismiss()
                            },
                        )
                        HorizontalDivider(color = colors.subtleDivider)

                        ContextMenuActionRow(
                            title = "Delete",
                            icon = Icons.Rounded.DeleteOutline,
                            highlighted = false,
                            destructive = true,
                            modifier = Modifier.testTag("menu-action-delete"),
                            onClick = {
                                coordinator.deleteConversation(targetCascadeId)
                                onDismiss()
                            },
                        )
                    }
                }

                // 3. Bottom SWIPE SHORTCUT Strip
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = "SWIPE SHORTCUT",
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontFamily = FontFamily.SansSerif,
                            fontWeight = FontWeight.SemiBold,
                            letterSpacing = 0.9.sp,
                        ),
                        color = colors.inkMuted,
                        modifier = Modifier.padding(start = 2.dp),
                    )

                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(16.dp),
                        color = colors.surfaceCard,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(68.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(
                                modifier = Modifier
                                    .weight(1f)
                                    .padding(horizontal = 14.dp),
                                verticalArrangement = Arrangement.spacedBy(3.dp),
                            ) {
                                Text(
                                    text = swipeSummary?.title ?: "Upgrade to Go 1.25",
                                    style = MaterialTheme.typography.titleMedium.copy(
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    ),
                                    color = colors.inkReading,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    text = if (localSwipeArchived) {
                                        "Archived · ${swipeSummary?.relativeTimeLabel ?: "1h"}"
                                    } else {
                                        "Done · ${swipeSummary?.relativeTimeLabel ?: "1h"}"
                                    },
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = colors.inkMuted,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }

                            // Periwinkle Pin Tile
                            Box(
                                modifier = Modifier
                                    .width(78.dp)
                                    .height(68.dp)
                                    .background(colors.accentPeriwinkle)
                                    .clickable {
                                        coordinator.toggleConversationPinned(swipePreviewCascadeId)
                                    }
                                    .testTag("swipe-action-pin"),
                                contentAlignment = Alignment.Center,
                            ) {
                                Column(
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.PushPin,
                                        contentDescription = "Pin",
                                        tint = colors.inkOnPrimaryCta,
                                        modifier = Modifier.size(18.dp),
                                    )
                                    Text(
                                        text = if (swipePinned) "Pinned" else "Pin",
                                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
                                        color = colors.inkOnPrimaryCta,
                                        maxLines = 1,
                                    )
                                }
                            }

                            // Neutral Archive Tile
                            Box(
                                modifier = Modifier
                                    .width(78.dp)
                                    .height(68.dp)
                                    .background(colors.surfaceActiveTab)
                                    .clickable {
                                        localSwipeArchived = !localSwipeArchived
                                        swipeSummary?.let { current ->
                                            coordinator.conversationSyncStore.upsertSummary(
                                                current.copy(isArchived = localSwipeArchived),
                                            )
                                        }
                                    }
                                    .testTag("swipe-action-archive"),
                                contentAlignment = Alignment.Center,
                            ) {
                                Column(
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Archive,
                                        contentDescription = "Archive",
                                        tint = colors.inkReading,
                                        modifier = Modifier.size(18.dp),
                                    )
                                    Text(
                                        text = "Archive",
                                        style = MaterialTheme.typography.labelLarge,
                                        color = colors.inkReading,
                                        maxLines = 1,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ContextMenuActionRow(
    title: String,
    icon: ImageVector,
    highlighted: Boolean,
    destructive: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    trailingIcon: ImageVector? = null,
) {
    val colors = MaterialTheme.antigravityColors
    val fgColor = if (destructive) colors.statusError else colors.inkReading
    val iconColor = if (destructive) colors.statusError else colors.inkLabel

    Row(
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
            .background(if (highlighted) colors.surfaceElevated.copy(alpha = 0.65f) else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = iconColor,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge.copy(
                fontSize = 15.5.sp,
                fontWeight = if (destructive) FontWeight.Medium else FontWeight.Normal,
            ),
            color = fgColor,
            modifier = Modifier.weight(1f),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (trailingIcon != null) {
            Icon(
                imageVector = trailingIcon,
                contentDescription = null,
                tint = colors.inkMuted,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}
