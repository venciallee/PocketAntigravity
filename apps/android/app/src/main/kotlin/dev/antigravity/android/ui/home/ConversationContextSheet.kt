package dev.antigravity.android.ui.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.DriveFileMove
import androidx.compose.material.icons.rounded.Archive
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.FileUpload
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.RadioButtonChecked
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AppLocalizationFormatter

/**
 * UE03_CONTEXT_MENU_PIN (`and-context-menu.png`): Material 3 Modal Bottom Sheet over
 * dimmed Sidebar Drawer with compact conversation preview card and 7 native action rows.
 */
@Composable
fun ConversationContextSheetScreen(
    coordinator: AntigravityCoreCoordinator,
    targetCascadeId: String = "cas-flaky-settlement",
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val lang = LocalAppLanguage.current
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()

    val targetSummary = remember(syncState.summaries, targetCascadeId) {
        syncState.summaries.firstOrNull { it.cascadeId == targetCascadeId }
    }
    val title = targetSummary?.title ?: "Fix flaky TestSettlementBatch"
    val metadataLine = if (targetSummary != null) {
        "${targetSummary.projectSlug} · ${targetSummary.modelLabel} · ${AppLocalizationFormatter.localizeRelativeTime(targetSummary.relativeTimeLabel, lang)}"
    } else {
        "ledger-svc · Gemini 4 Neon · ${AppLocalizationFormatter.localizeRelativeTime("8m", lang)}"
    }
    val previewExcerpt = targetSummary?.lastMessagePreview?.takeIf { it.isNotBlank() }
        ?: "The flake comes from a shared fake clock across parallel subtests. I wrote a plan to isolate it per test."
    val isPinned = targetSummary?.isPinned == true
    val isUnread = targetSummary?.isUnread == true
    val scrimColor = if (colors.isDark) Color.Black.copy(alpha = 0.56f) else Color.Black.copy(alpha = 0.34f)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
    ) {
        AgentsSidebarDrawerOverlay(
            coordinator = coordinator,
            onDismiss = {},
            onNewConversation = {},
            onOpenAutomations = {},
            onOpenCustomizations = {},
            onOpenDisplayOptions = {},
            onOpenNewProject = {},
            onOpenConversation = {},
            onLongPressConversation = {},
            onOpenSettings = {},
            modifier = Modifier.fillMaxSize(),
        )

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(scrimColor)
                .clickable(onClick = onDismiss),
        )

        Surface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .testTag("context-menu-sheet"),
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
                    .navigationBarsPadding()
                    .padding(bottom = 18.dp),
            ) {
                Box(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .padding(top = 12.dp, bottom = 14.dp)
                        .size(width = 36.dp, height = 4.dp)
                        .clip(RoundedCornerShape(100.dp))
                        .background(colors.sheetHandle),
                )

                // Compact preview card (`and-context-menu.png`)
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .testTag("context-preview-card"),
                    shape = RoundedCornerShape(16.dp),
                    color = colors.surfaceElevated,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            StatusDot(
                                color = colors.statusRunning,
                                size = 8.dp,
                                glow = false,
                            )
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(
                                    text = title,
                                    style = MaterialTheme.typography.titleMedium.copy(
                                        fontSize = 15.5.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    ),
                                    color = colors.inkReading,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                Text(
                                    text = metadataLine,
                                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                                    color = colors.inkSecondary,
                                    maxLines = 1,
                                )
                            }
                        }

                        Text(
                            text = previewExcerpt,
                            style = MaterialTheme.typography.bodyMedium.copy(
                                fontSize = 14.sp,
                                lineHeight = 20.sp,
                            ),
                            color = colors.inkLabel,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))

                ContextSheetActionRow(
                    icon = Icons.Rounded.PushPin,
                    label = if (isPinned) tr("Unpin", "取消置顶") else tr("Pin", "置顶"),
                    onClick = {
                        coordinator.toggleConversationPinned(targetCascadeId)
                        onDismiss()
                    },
                    modifier = Modifier.testTag("action-pin"),
                )
                ContextSheetActionRow(
                    icon = Icons.Rounded.RadioButtonChecked,
                    label = if (isUnread) tr("Mark as read", "标为已读") else tr("Mark as unread", "标为未读"),
                    onClick = {
                        coordinator.toggleConversationUnread(targetCascadeId)
                        onDismiss()
                    },
                    modifier = Modifier.testTag("action-unread"),
                )
                ContextSheetActionRow(
                    icon = Icons.Rounded.Edit,
                    label = tr("Rename", "重命名"),
                    onClick = { onDismiss() },
                    modifier = Modifier.testTag("action-rename"),
                )
                ContextSheetActionRow(
                    icon = Icons.AutoMirrored.Rounded.DriveFileMove,
                    label = tr("Move to project", "移动到项目"),
                    onClick = { onDismiss() },
                    modifier = Modifier.testTag("action-move"),
                )
                ContextSheetActionRow(
                    icon = Icons.Rounded.FileUpload,
                    label = tr("Export summary", "导出摘要"),
                    onClick = { onDismiss() },
                    modifier = Modifier.testTag("action-export"),
                )
                ContextSheetActionRow(
                    icon = Icons.Rounded.Archive,
                    label = tr("Archive", "归档"),
                    onClick = {
                        coordinator.archiveConversation(targetCascadeId)
                        onDismiss()
                    },
                    modifier = Modifier.testTag("action-archive"),
                )
                ContextSheetActionRow(
                    icon = Icons.Rounded.DeleteOutline,
                    label = tr("Delete", "删除"),
                    tint = colors.statusError,
                    onClick = {
                        coordinator.deleteConversation(targetCascadeId)
                        onDismiss()
                    },
                    modifier = Modifier.testTag("action-delete"),
                )
            }
        }
    }
}

@Composable
private fun ContextSheetActionRow(
    icon: ImageVector,
    label: String,
    tint: Color = MaterialTheme.antigravityColors.inkReading,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(21.dp),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
            color = tint,
        )
    }
}
