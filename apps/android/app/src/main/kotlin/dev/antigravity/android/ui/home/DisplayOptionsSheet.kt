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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.UnfoldMore
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.ConversationSortField
import dev.antigravity.shared.model.DisplayGroupBy

/**
 * UE02_DISPLAY_OPTIONS: Docked Material 3 Modal Bottom Sheet overlay over dimmed Agents Home backdrop,
 * used for visual verification (`UE02_DISPLAY_OPTIONS`) and standalone sheet presentation.
 */
@Composable
fun DisplayOptionsOverlayScreen(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val scrimColor = if (colors.isDark) Color.Black.copy(alpha = 0.58f) else Color.Black.copy(alpha = 0.36f)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
    ) {
        // Dimmed Agents Home backdrop
        AgentsHomeScreen(
            coordinator = coordinator,
            onOpenDisplayOptions = {},
            onOpenNewProject = {},
            onOpenProjectDetail = {},
            onOpenConversation = {},
            onLongPressConversation = {},
            modifier = Modifier.fillMaxSize(),
        )

        // Material 3 scrim
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(scrimColor)
                .clickable(onClick = onDismiss),
        )

        // Docked Material 3 Bottom Sheet surface
        Surface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(top = 84.dp),
            shape = RoundedCornerShape(
                topStart = AntigravityDesignTokens.SheetCornerRadius,
                topEnd = AntigravityDesignTokens.SheetCornerRadius,
            ),
            color = colors.surfaceSheet,
            border = BorderStroke(1.dp, colors.cardBorder),
            tonalElevation = 3.dp,
        ) {
            DisplayOptionsSheetContent(
                coordinator = coordinator,
                onDismiss = onDismiss,
            )
        }
    }
}

/**
 * UE02_DISPLAY_OPTIONS: Material 3 bottom sheet content for grouping, sorting, auto-pin,
 * archived-only filtering, and marking all conversations read.
 */
@Composable
fun DisplayOptionsSheetContent(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()

    val options = workspaceState.displayOptions
    val unreadCount = remember(syncState.summaries) {
        syncState.summaries.count { it.isUnread }
    }
    var sortMenuExpanded by remember { mutableStateOf(true) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Material 3 Centered Drag Handle
        Box(
            modifier = Modifier
                .padding(top = 10.dp, bottom = 4.dp)
                .size(width = 36.dp, height = 4.dp)
                .clip(RoundedCornerShape(100.dp))
                .background(colors.sheetHandle),
        )

        // Header Row: Reset / Display Options / Done
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            TextButton(
                onClick = { coordinator.workspaceStore.resetDisplayOptions() },
                modifier = Modifier
                    .defaultMinSize(minWidth = 64.dp, minHeight = AntigravityDesignTokens.MinTouchTarget)
                    .testTag("sheet-reset-btn"),
            ) {
                Text(
                    text = "Reset",
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    color = colors.inkSecondary,
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Text(
                text = "Display Options",
                style = MaterialTheme.typography.titleMedium.copy(
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                ),
                color = colors.inkReading,
                maxLines = 1,
            )

            Spacer(modifier = Modifier.weight(1f))

            TextButton(
                onClick = onDismiss,
                modifier = Modifier
                    .defaultMinSize(minWidth = 64.dp, minHeight = AntigravityDesignTokens.MinTouchTarget)
                    .testTag("sheet-done-btn"),
            ) {
                Text(
                    text = "Done",
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    color = colors.accentPeriwinkle,
                )
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // Card 1: Group By + Sort Conversations (+ inline M3 sort menu) + Sort Projects
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                color = colors.surfaceSheetGroup,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    DisplayOptionValueRow(
                        label = "Group By",
                        value = options.groupBy.displayTitle,
                        showSelectorArrows = true,
                        modifier = Modifier.testTag("row-group-by"),
                        onClick = {
                            val entries = DisplayGroupBy.entries
                            val next = entries[(entries.indexOf(options.groupBy) + 1) % entries.size]
                            coordinator.workspaceStore.updateDisplayOptions { it.copy(groupBy = next) }
                        },
                    )

                    HorizontalDivider(color = colors.subtleDivider)

                    DisplayOptionValueRow(
                        label = "Sort Conversations",
                        value = options.sortBy.displayTitle,
                        showSelectorArrows = true,
                        highlighted = sortMenuExpanded,
                        modifier = Modifier.testTag("row-sort-conversations"),
                        onClick = { sortMenuExpanded = !sortMenuExpanded },
                    )

                    if (sortMenuExpanded) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                        ) {
                            SortOptionsMenuCard(
                                selectedField = options.sortBy,
                                newestFirst = options.newestFirst,
                                onSelectField = { field ->
                                    coordinator.workspaceStore.updateDisplayOptions { it.copy(sortBy = field) }
                                },
                                onSelectNewestFirst = { newest ->
                                    coordinator.workspaceStore.updateDisplayOptions { it.copy(newestFirst = newest) }
                                },
                            )
                        }
                    }

                    HorizontalDivider(color = colors.subtleDivider)

                    DisplayOptionValueRow(
                        label = "Sort Projects",
                        value = options.sortProjectsOrder,
                        showSelectorArrows = true,
                        onClick = {
                            val nextOrder = if (options.sortProjectsOrder == "Custom Order") {
                                "Alphabetical"
                            } else {
                                "Custom Order"
                            }
                            coordinator.workspaceStore.updateDisplayOptions {
                                it.copy(sortProjectsOrder = nextOrder)
                            }
                        },
                    )
                }
            }

            // Card 2: Filter & Display Summary Rows
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                color = colors.surfaceSheetGroup,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    DisplayOptionValueRow(
                        label = "Filter",
                        value = options.filterScopeLabel,
                        showSelectorArrows = false,
                        onClick = {
                            val nextFilter = if (options.filterScopeLabel == "All conversations") {
                                "Active only"
                            } else {
                                "All conversations"
                            }
                            coordinator.workspaceStore.updateDisplayOptions {
                                it.copy(filterScopeLabel = nextFilter)
                            }
                        },
                    )

                    HorizontalDivider(color = colors.subtleDivider)

                    DisplayOptionValueRow(
                        label = "Display",
                        value = options.densityLabel,
                        showSelectorArrows = false,
                        onClick = {
                            val nextDensity = if (options.densityLabel.startsWith("Comfortable")) {
                                "Compact · Titles only"
                            } else {
                                "Comfortable · Previews"
                            }
                            coordinator.workspaceStore.updateDisplayOptions {
                                it.copy(densityLabel = nextDensity)
                            }
                        },
                    )
                }
            }

            // Card 3: Auto Pin & Archived Only M3 Switch Toggles
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(18.dp),
                color = colors.surfaceSheetGroup,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    DisplayOptionSwitchRow(
                        title = "Auto Pin",
                        subtitle = "Pin a conversation when you message it",
                        checked = options.autoPinOnMessage,
                        switchTag = "toggle-auto-pin",
                        onCheckedChange = { checked ->
                            coordinator.workspaceStore.updateDisplayOptions {
                                it.copy(autoPinOnMessage = checked)
                            }
                        },
                    )

                    HorizontalDivider(color = colors.subtleDivider)

                    DisplayOptionSwitchRow(
                        title = "Archived Only",
                        subtitle = "Show only archived conversations",
                        checked = options.archivedOnly,
                        switchTag = "toggle-archived-only",
                        onCheckedChange = { checked ->
                            coordinator.workspaceStore.updateDisplayOptions {
                                it.copy(archivedOnly = checked)
                            }
                        },
                    )
                }
            }

            // Card 4: Mark All as Read Full-Width Action Card
            Surface(
                onClick = { coordinator.markAllConversationsRead() },
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 52.dp)
                    .testTag("btn-mark-all-read"),
                shape = RoundedCornerShape(18.dp),
                color = colors.surfaceSheetGroup,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Mark All as Read",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontSize = 15.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.accentPeriwinkle,
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        text = "$unreadCount unread",
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                        color = colors.inkSecondary,
                    )
                }
            }
        }
    }
}

@Composable
private fun DisplayOptionValueRow(
    label: String,
    value: String,
    showSelectorArrows: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    highlighted: Boolean = false,
) {
    val colors = MaterialTheme.antigravityColors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
            .background(if (highlighted) colors.surfaceElevated.copy(alpha = 0.65f) else Color.Transparent)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp),
            color = colors.inkReading,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(modifier = Modifier.weight(1f))
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp),
            color = colors.inkSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Icon(
            imageVector = if (showSelectorArrows) Icons.Rounded.UnfoldMore else Icons.Rounded.ChevronRight,
            contentDescription = null,
            tint = colors.inkMuted,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun SortOptionsMenuCard(
    selectedField: ConversationSortField,
    newestFirst: Boolean,
    onSelectField: (ConversationSortField) -> Unit,
    onSelectNewestFirst: (Boolean) -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("sort-options-menu"),
        shape = RoundedCornerShape(16.dp),
        color = colors.surfacePopover,
        border = BorderStroke(1.dp, colors.cardBorder),
        tonalElevation = 4.dp,
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            ConversationSortField.entries.forEachIndexed { index, field ->
                SortOptionItemRow(
                    label = field.displayTitle,
                    selected = selectedField == field,
                    onClick = { onSelectField(field) },
                )
                if (index < ConversationSortField.entries.lastIndex) {
                    HorizontalDivider(color = colors.subtleDivider)
                }
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(6.dp)
                    .background(colors.surfaceElevated),
            )

            SortOptionItemRow(
                label = "Newest First",
                selected = newestFirst,
                onClick = { onSelectNewestFirst(true) },
            )
            HorizontalDivider(color = colors.subtleDivider)
            SortOptionItemRow(
                label = "Oldest First",
                selected = !newestFirst,
                onClick = { onSelectNewestFirst(false) },
            )
        }
    }
}

@Composable
private fun SortOptionItemRow(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 42.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier.size(18.dp),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) {
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = "Selected",
                    tint = colors.accentPeriwinkle,
                    modifier = Modifier.size(17.dp),
                )
            }
        }
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge.copy(
                fontSize = 15.sp,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            ),
            color = if (selected) colors.inkReading else colors.inkLabel,
            maxLines = 1,
        )
    }
}

@Composable
private fun DisplayOptionSwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    switchTag: String,
    onCheckedChange: (Boolean) -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 58.dp)
            .clickable { onCheckedChange(!checked) }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp),
                color = colors.inkReading,
                maxLines = 1,
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            modifier = Modifier.testTag(switchTag),
            colors = SwitchDefaults.colors(
                checkedThumbColor = colors.inkOnPrimaryCta,
                checkedTrackColor = colors.accentPeriwinkle,
                uncheckedThumbColor = colors.inkLabel,
                uncheckedTrackColor = colors.surfaceElevated,
                uncheckedBorderColor = colors.cardBorder,
            ),
        )
    }
}
