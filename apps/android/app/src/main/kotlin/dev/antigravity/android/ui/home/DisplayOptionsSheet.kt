package dev.antigravity.android.ui.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.ConversationSortField
import dev.antigravity.shared.model.DisplayGroupBy
import dev.antigravity.shared.model.localizedTitle

/**
 * UE02_DISPLAY_OPTIONS (`and-display-options.png`): Material 3 Modal Bottom Sheet over
 * dimmed Sidebar Drawer backdrop with inline floating sort menu, switches, and Mark all as read.
 */
@Composable
fun DisplayOptionsOverlayScreen(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    initialSortMenuExpanded: Boolean = false,
) {
    val colors = MaterialTheme.antigravityColors
    val scrimColor = if (colors.isDark) Color.Black.copy(alpha = 0.56f) else Color.Black.copy(alpha = 0.34f)
    var sortMenuExpanded by remember(initialSortMenuExpanded) {
        mutableStateOf(initialSortMenuExpanded)
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
    ) {
        // Dimmed Sidebar Drawer backdrop matching `and-display-options.png`
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
                .testTag("display-options-scrim")
                .clickable {
                    if (sortMenuExpanded) {
                        sortMenuExpanded = false
                    } else {
                        onDismiss()
                    }
                },
        )

        Surface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .testTag("display-options-sheet"),
            shape = RoundedCornerShape(
                topStart = AntigravityDesignTokens.SheetCornerRadius,
                topEnd = AntigravityDesignTokens.SheetCornerRadius,
            ),
            color = colors.surfaceSheet,
            border = BorderStroke(1.dp, colors.cardBorder),
            tonalElevation = 4.dp,
        ) {
            DisplayOptionsSheetContent(
                coordinator = coordinator,
                onDismiss = onDismiss,
                sortMenuExpanded = sortMenuExpanded,
                onSortMenuExpandedChange = { sortMenuExpanded = it },
                defaultAutoPinChecked = initialSortMenuExpanded,
            )
        }
    }
}

@Composable
fun DisplayOptionsSheetContent(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    sortMenuExpanded: Boolean,
    onSortMenuExpandedChange: (Boolean) -> Unit,
    defaultAutoPinChecked: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val lang = LocalAppLanguage.current
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()
    val options = workspaceState.displayOptions
    val unreadCount = remember(syncState.summaries) {
        syncState.summaries.count { it.isUnread }
    }
    val autoPinEnabled = options.autoPinOnMessage

    Box(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
        ) {
            // Drag Handle
            Box(
                modifier = Modifier
                    .align(Alignment.CenterHorizontally)
                    .padding(top = 12.dp, bottom = 14.dp)
                    .size(width = 36.dp, height = 4.dp)
                    .clip(RoundedCornerShape(100.dp))
                    .background(colors.sheetHandle),
            )

            // Header: Display options (left) + Reset (right)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 24.dp, end = 14.dp, bottom = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = tr("Display options", "显示选项"),
                    style = MaterialTheme.typography.headlineSmall.copy(
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Normal,
                    ),
                    color = colors.inkReading,
                    modifier = Modifier.weight(1f),
                )
                TextButton(
                    onClick = {
                        onSortMenuExpandedChange(false)
                        coordinator.workspaceStore.resetDisplayOptions()
                    },
                    modifier = Modifier.testTag("sheet-reset-btn"),
                ) {
                    Text(
                        text = tr("Reset", "重置"),
                        style = MaterialTheme.typography.titleSmall.copy(
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.accentPeriwinkle,
                    )
                }
            }

            // Group by
            DisplayOptionFlatRow(
                label = tr("Group by", "分组方式"),
                value = options.groupBy.localizedTitle(lang),
                trailingIcon = Icons.Rounded.KeyboardArrowDown,
                onClick = {
                    onSortMenuExpandedChange(false)
                    val values = DisplayGroupBy.entries
                    val next = values[(values.indexOf(options.groupBy) + 1) % values.size]
                    coordinator.workspaceStore.updateDisplayOptions { it.copy(groupBy = next) }
                },
                modifier = Modifier.testTag("option-group-by"),
            )

            // Sort conversations (highlighted when dropdown menu is open)
            DisplayOptionFlatRow(
                label = tr("Sort conversations", "会话排序"),
                value = when (options.sortBy) {
                    ConversationSortField.LAST_UPDATED -> tr("Last updated", "最近更新")
                    ConversationSortField.DATE_CREATED -> tr("Date created", "创建时间")
                    ConversationSortField.TITLE -> tr("Title", "标题")
                },
                trailingIcon = if (sortMenuExpanded) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown,
                highlighted = sortMenuExpanded,
                onClick = { onSortMenuExpandedChange(!sortMenuExpanded) },
                modifier = Modifier.testTag("option-sort-by"),
            )

            // Sort projects
            val localizedProjectsOrder = when (options.sortProjectsOrder) {
                "Custom Order" -> tr("Custom Order", "自定义顺序")
                "Alphabetical" -> tr("Alphabetical", "按字母排序")
                else -> options.sortProjectsOrder
            }
            DisplayOptionFlatRow(
                label = tr("Sort projects", "项目排序"),
                value = if (sortMenuExpanded) "" else localizedProjectsOrder,
                trailingIcon = if (sortMenuExpanded) null else Icons.Rounded.KeyboardArrowDown,
                onClick = {
                    onSortMenuExpandedChange(false)
                    val next = if (options.sortProjectsOrder == "Custom Order") "Alphabetical" else "Custom Order"
                    coordinator.workspaceStore.updateDisplayOptions { it.copy(sortProjectsOrder = next) }
                },
                modifier = Modifier.testTag("option-sort-projects"),
            )

            HorizontalDivider(
                modifier = Modifier.padding(horizontal = 24.dp),
                color = colors.subtleDivider,
            )

            // Filter
            val localizedFilterScope = when (options.filterScopeLabel) {
                "All conversations" -> tr("All conversations", "全部会话")
                "Only Unread" -> tr("Only Unread", "仅未读")
                "Only Automations" -> tr("Only Automations", "仅自动化")
                else -> options.filterScopeLabel
            }
            DisplayOptionFlatRow(
                label = tr("Filter", "筛选"),
                value = if (sortMenuExpanded) "" else localizedFilterScope,
                trailingIcon = if (sortMenuExpanded) null else Icons.Rounded.ChevronRight,
                onClick = {
                    val next = when (options.filterScopeLabel) {
                        "All conversations" -> "Only Unread"
                        "Only Unread" -> "Only Automations"
                        else -> "All conversations"
                    }
                    coordinator.workspaceStore.updateDisplayOptions { it.copy(filterScopeLabel = next) }
                },
                modifier = Modifier.testTag("option-filter"),
            )

            // Display
            DisplayOptionFlatRow(
                label = tr("Display", "密度"),
                value = if (options.densityLabel.contains("Compact", ignoreCase = true)) {
                    tr("Compact", "紧凑")
                } else {
                    tr("Comfortable", "舒适")
                },
                trailingIcon = Icons.Rounded.ChevronRight,
                onClick = {
                    val next = if (options.densityLabel.contains("Compact", ignoreCase = true)) {
                        "Comfortable · Previews"
                    } else {
                        "Compact · Titles only"
                    }
                    coordinator.workspaceStore.updateDisplayOptions { it.copy(densityLabel = next) }
                },
                modifier = Modifier.testTag("option-display"),
            )

            HorizontalDivider(
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 4.dp),
                color = colors.subtleDivider,
            )

            // Auto pin toggle
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        coordinator.workspaceStore.updateDisplayOptions {
                            it.copy(autoPinOnMessage = !it.autoPinOnMessage)
                        }
                    }
                    .padding(horizontal = 24.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = tr("Auto pin", "自动置顶"),
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                        color = colors.inkReading,
                    )
                    Text(
                        text = tr("Pin a conversation when you message it", "发送消息后自动置顶该会话"),
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = colors.inkSecondary,
                    )
                }
                Switch(
                    checked = autoPinEnabled,
                    onCheckedChange = { checked ->
                        coordinator.workspaceStore.updateDisplayOptions { it.copy(autoPinOnMessage = checked) }
                    },
                    modifier = Modifier.testTag("switch-auto-pin"),
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = colors.inkOnPrimaryCta,
                        checkedTrackColor = colors.accentPeriwinkle,
                        uncheckedThumbColor = colors.inkSecondary,
                        uncheckedTrackColor = colors.surfaceElevated,
                        uncheckedBorderColor = colors.inkMuted,
                    ),
                )
            }

            // Archived only toggle
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        coordinator.workspaceStore.updateDisplayOptions {
                            it.copy(archivedOnly = !it.archivedOnly)
                        }
                    }
                    .padding(horizontal = 24.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    text = tr("Archived only", "仅看已归档"),
                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                    color = colors.inkReading,
                    modifier = Modifier.weight(1f),
                )
                Switch(
                    checked = options.archivedOnly,
                    onCheckedChange = { checked ->
                        coordinator.workspaceStore.updateDisplayOptions { it.copy(archivedOnly = checked) }
                    },
                    modifier = Modifier.testTag("switch-archived-only"),
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = colors.inkOnPrimaryCta,
                        checkedTrackColor = colors.accentPeriwinkle,
                        uncheckedThumbColor = colors.inkSecondary,
                        uncheckedTrackColor = colors.surfaceElevated,
                        uncheckedBorderColor = colors.inkMuted,
                    ),
                )
            }

            Spacer(modifier = Modifier.height(10.dp))

            // Footer: 3 unread (left) + tonal pill Mark all as read (right)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = tr("$unreadCount unread", "$unreadCount 条未读"),
                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                    color = colors.inkSecondary,
                    modifier = Modifier.weight(1f),
                )
                Surface(
                    onClick = {
                        coordinator.markAllConversationsRead()
                    },
                    modifier = Modifier
                        .defaultMinSize(minHeight = 42.dp)
                        .testTag("btn-mark-all-read"),
                    shape = RoundedCornerShape(100.dp),
                    color = colors.surfaceActiveTab,
                ) {
                    Box(
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = tr("Mark all as read", "全部标为已读"),
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.pillActiveForeground,
                        )
                    }
                }
            }
        }

        // Anchored M3 Sort Dropdown Popup over `Sort projects` / `Filter` rows (`and-display-options.png`)
        if (sortMenuExpanded) {
            Surface(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 186.dp, end = 22.dp)
                    .width(220.dp)
                    .zIndex(10f)
                    .testTag("sort-dropdown-menu"),
                shape = RoundedCornerShape(14.dp),
                color = colors.surfacePopover,
                border = BorderStroke(1.dp, colors.cardBorder),
                shadowElevation = 10.dp,
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    listOf(
                        ConversationSortField.LAST_UPDATED to tr("Last updated", "最近更新"),
                        ConversationSortField.DATE_CREATED to tr("Date created", "创建时间"),
                        ConversationSortField.TITLE to tr("Title", "标题"),
                    ).forEachIndexed { idx, (field, label) ->
                        val selected = options.sortBy == field
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(if (selected) Color.White.copy(alpha = 0.05f) else Color.Transparent)
                                .clickable {
                                    coordinator.workspaceStore.updateDisplayOptions { it.copy(sortBy = field) }
                                    onSortMenuExpandedChange(false)
                                }
                                .padding(horizontal = 16.dp, vertical = 14.dp)
                                .testTag("sort-option-${field.name.lowercase()}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Box(modifier = Modifier.size(18.dp), contentAlignment = Alignment.Center) {
                                if (selected) {
                                    Icon(
                                        imageVector = Icons.Rounded.Check,
                                        contentDescription = null,
                                        tint = colors.accentPeriwinkle,
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                            }
                            Text(
                                text = label,
                                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp),
                                color = colors.inkReading,
                            )
                        }
                        if (idx == 0) {
                            HorizontalDivider(color = colors.subtleDivider)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DisplayOptionFlatRow(
    label: String,
    value: String,
    trailingIcon: androidx.compose.ui.graphics.vector.ImageVector?,
    highlighted: Boolean = false,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(if (highlighted) colors.surfacePopover else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 15.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
            color = colors.inkReading,
            modifier = Modifier.weight(1f),
        )
        if (value.isNotEmpty()) {
            Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp),
                color = colors.inkSecondary,
            )
            Spacer(modifier = Modifier.width(6.dp))
        }
        if (trailingIcon != null) {
            Icon(
                imageVector = trailingIcon,
                contentDescription = null,
                tint = colors.inkSecondary,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}
