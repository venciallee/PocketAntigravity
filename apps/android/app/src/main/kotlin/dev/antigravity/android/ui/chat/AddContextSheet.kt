package dev.antigravity.android.ui.chat

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
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AlternateEmail
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.ChatBubbleOutline
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material.icons.rounded.ViewInAr
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.components.SectionHeaderLabel
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.ContextCandidateCategory
import dev.antigravity.shared.model.ContextCandidateItem

/**
 * UE08_ADD_CONTEXT: Material 3 Modal Bottom Sheet for searching and multi-selecting Files, Folders,
 * Conversation/Terminal Mentions, Slash Actions, and Workspace Skills to attach to `ChatComposer`.
 */
@Composable
fun AddContextSheetScreen(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val workspaceState by coordinator.workspaceStore.state.collectAsState()

    var searchQuery by remember { mutableStateOf("") }
    var activeCategory by remember { mutableStateOf<ContextCandidateCategory?>(null) }

    val allCandidates = workspaceState.contextCandidates
    val filteredCandidates = remember(allCandidates, searchQuery, activeCategory) {
        val q = searchQuery.trim().lowercase()
        allCandidates.filter { item ->
            val categoryMatch = activeCategory == null || item.category == activeCategory
            val queryMatch = q.isEmpty() ||
                item.title.lowercase().contains(q) ||
                item.subtitle.lowercase().contains(q) ||
                item.chipLabel.lowercase().contains(q)
            categoryMatch && queryMatch
        }
    }

    val filesAndFolders = filteredCandidates.filter {
        it.category == ContextCandidateCategory.FILES || it.category == ContextCandidateCategory.FOLDER
    }
    val mentions = filteredCandidates.filter { it.category == ContextCandidateCategory.MENTIONS }
    val actionsAndSkills = filteredCandidates.filter {
        it.category == ContextCandidateCategory.ACTIONS || it.category == ContextCandidateCategory.SKILLS
    }
    val selectedCount = allCandidates.count { it.isSelected }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
    ) {
        // Subtle dimmed backdrop behind bottom sheet
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = if (colors.isDark) 0.54f else 0.34f))
                .clickable(onClick = onDismiss),
        )

        // Material 3 Bottom Sheet Container
        Surface(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(top = 34.dp),
            shape = RoundedCornerShape(
                topStart = AntigravityDesignTokens.SheetCornerRadius,
                topEnd = AntigravityDesignTokens.SheetCornerRadius,
            ),
            color = colors.surfaceSheet,
            border = BorderStroke(1.dp, colors.cardBorder),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .navigationBarsPadding(),
            ) {
                // Drag Handle
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 10.dp, bottom = 4.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        modifier = Modifier
                            .width(38.dp)
                            .height(4.dp)
                            .clip(RoundedCornerShape(100.dp))
                            .background(colors.sheetHandle),
                    )
                }

                // Header Bar: centered title + close X
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp),
                ) {
                    Text(
                        text = "Add Context",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        color = colors.inkReading,
                        modifier = Modifier.align(Alignment.Center),
                    )
                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier
                            .align(Alignment.CenterEnd)
                            .defaultMinSize(
                                minWidth = AntigravityDesignTokens.MinTouchTarget,
                                minHeight = AntigravityDesignTokens.MinTouchTarget,
                            )
                            .testTag("btn-close-add-context"),
                    ) {
                        Surface(
                            shape = CircleShape,
                            color = colors.surfaceElevated,
                            modifier = Modifier.size(34.dp),
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    imageVector = Icons.Rounded.Close,
                                    contentDescription = "Close",
                                    tint = colors.inkLabel,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                    }
                }

                // Search Bar
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .defaultMinSize(minHeight = 46.dp),
                    shape = RoundedCornerShape(14.dp),
                    color = colors.surfaceElevated,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Search,
                            contentDescription = "Search",
                            tint = colors.inkMuted,
                            modifier = Modifier.size(18.dp),
                        )
                        Box(modifier = Modifier.weight(1f)) {
                            if (searchQuery.isEmpty()) {
                                Text(
                                    text = "Search files, folders, skills...",
                                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                                    color = colors.inkMuted,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            BasicTextField(
                                value = searchQuery,
                                onValueChange = { searchQuery = it },
                                textStyle = MaterialTheme.typography.bodyLarge.copy(
                                    fontSize = 15.sp,
                                    color = colors.inkReading,
                                ),
                                cursorBrush = SolidColor(colors.accentPeriwinkle),
                                singleLine = true,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .testTag("context-search-input"),
                            )
                        }
                        if (searchQuery.isNotEmpty()) {
                            Icon(
                                imageVector = Icons.Rounded.Close,
                                contentDescription = "Clear search",
                                tint = colors.inkSecondary,
                                modifier = Modifier
                                    .size(18.dp)
                                    .clickable { searchQuery = "" },
                            )
                        }
                    }
                }

                // 5 Category Tiles Row
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    ContextCategoryTile(
                        label = "Files",
                        icon = Icons.Rounded.Description,
                        selected = activeCategory == ContextCandidateCategory.FILES,
                        onClick = {
                            activeCategory = if (activeCategory == ContextCandidateCategory.FILES) {
                                null
                            } else {
                                ContextCandidateCategory.FILES
                            }
                        },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("tile-files"),
                    )
                    ContextCategoryTile(
                        label = "Folder",
                        icon = Icons.Rounded.Folder,
                        selected = activeCategory == ContextCandidateCategory.FOLDER,
                        onClick = {
                            activeCategory = if (activeCategory == ContextCandidateCategory.FOLDER) {
                                null
                            } else {
                                ContextCandidateCategory.FOLDER
                            }
                        },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("tile-folder"),
                    )
                    ContextCategoryTile(
                        label = "Mentions",
                        icon = Icons.Rounded.AlternateEmail,
                        selected = activeCategory == ContextCandidateCategory.MENTIONS,
                        onClick = {
                            activeCategory = if (activeCategory == ContextCandidateCategory.MENTIONS) {
                                null
                            } else {
                                ContextCandidateCategory.MENTIONS
                            }
                        },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("tile-mentions"),
                    )
                    ContextCategoryTile(
                        label = "Actions",
                        icon = Icons.Rounded.Bolt,
                        selected = activeCategory == ContextCandidateCategory.ACTIONS,
                        onClick = {
                            activeCategory = if (activeCategory == ContextCandidateCategory.ACTIONS) {
                                null
                            } else {
                                ContextCandidateCategory.ACTIONS
                            }
                        },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("tile-actions"),
                    )
                    ContextCategoryTile(
                        label = "Skills",
                        icon = Icons.Rounded.ViewInAr,
                        selected = activeCategory == ContextCandidateCategory.SKILLS,
                        onClick = {
                            activeCategory = if (activeCategory == ContextCandidateCategory.SKILLS) {
                                null
                            } else {
                                ContextCandidateCategory.SKILLS
                            }
                        },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("tile-skills"),
                    )
                }

                // Scrollable Grouped Candidates
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    if (filesAndFolders.isNotEmpty()) {
                        ContextCandidateGroupCard(
                            sectionTitle = "FILES & FOLDERS",
                            items = filesAndFolders,
                            onToggle = { coordinator.workspaceStore.toggleContextCandidate(it.id) },
                        )
                    }
                    if (mentions.isNotEmpty()) {
                        ContextCandidateGroupCard(
                            sectionTitle = "MENTIONS",
                            items = mentions,
                            onToggle = { coordinator.workspaceStore.toggleContextCandidate(it.id) },
                        )
                    }
                    if (actionsAndSkills.isNotEmpty()) {
                        ContextCandidateGroupCard(
                            sectionTitle = "ACTIONS & SKILLS",
                            items = actionsAndSkills,
                            onToggle = { coordinator.workspaceStore.toggleContextCandidate(it.id) },
                        )
                    }
                    if (filteredCandidates.isEmpty()) {
                        Text(
                            text = "No matching context items found.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.inkSecondary,
                            modifier = Modifier.padding(vertical = 24.dp),
                        )
                    }
                }

                HorizontalDivider(color = colors.subtleDivider)

                // Footer Bar: Selected count + Add to message CTA
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = "$selectedCount selected",
                        style = MaterialTheme.typography.bodyLarge.copy(
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.inkSecondary,
                    )
                    Button(
                        onClick = {
                            coordinator.workspaceStore.applySelectedContextToComposer()
                            onDismiss()
                        },
                        modifier = Modifier
                            .defaultMinSize(minWidth = 156.dp, minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-add-to-message"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.accentPeriwinkle,
                            contentColor = colors.inkOnPrimaryCta,
                        ),
                    ) {
                        Text(
                            text = "Add to message",
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 14.5.sp,
                                fontWeight = FontWeight.Bold,
                            ),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ContextCategoryTile(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    Surface(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minHeight = 62.dp),
        shape = RoundedCornerShape(14.dp),
        color = if (selected) colors.surfaceSelectionTint else colors.surfaceElevated,
        border = BorderStroke(
            width = 1.dp,
            color = if (selected) colors.accentPeriwinkle else colors.cardBorder,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 10.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = if (selected) colors.accentPeriwinkle else colors.inkLabel,
                modifier = Modifier.size(19.dp),
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall.copy(
                    fontFamily = FontFamily.SansSerif,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 11.sp,
                ),
                color = if (selected) colors.accentPeriwinkle else colors.inkReading,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun ContextCandidateGroupCard(
    sectionTitle: String,
    items: List<ContextCandidateItem>,
    onToggle: (ContextCandidateItem) -> Unit,
) {
    val colors = LocalAntigravityColors.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeaderLabel(title = sectionTitle)
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(18.dp),
            color = colors.surfaceSheetGroup,
            border = BorderStroke(1.dp, colors.cardBorder),
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                items.forEachIndexed { idx, item ->
                    ContextCandidateRow(
                        item = item,
                        onToggle = { onToggle(item) },
                    )
                    if (idx < items.lastIndex) {
                        HorizontalDivider(
                            color = colors.subtleDivider,
                            modifier = Modifier.padding(horizontal = 14.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ContextCandidateRow(
    item: ContextCandidateItem,
    onToggle: () -> Unit,
) {
    val colors = LocalAntigravityColors.current
    val rowTag = contextCandidateTestTag(item)
    val icon = when (item.category) {
        ContextCandidateCategory.FILES -> Icons.Rounded.Description
        ContextCandidateCategory.FOLDER -> Icons.Rounded.Folder
        ContextCandidateCategory.MENTIONS ->
            if (item.title.lowercase().contains("terminal")) Icons.Rounded.Terminal else Icons.Rounded.ChatBubbleOutline
        ContextCandidateCategory.ACTIONS -> Icons.Rounded.Bolt
        ContextCandidateCategory.SKILLS -> Icons.Rounded.ViewInAr
    }
    val isCodeStyleTitle = item.category == ContextCandidateCategory.FILES ||
        item.category == ContextCandidateCategory.FOLDER ||
        item.category == ContextCandidateCategory.ACTIONS

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 58.dp)
            .clickable(onClick = onToggle)
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .testTag(rowTag),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (item.isSelected) colors.accentPeriwinkle else colors.inkSecondary,
            modifier = Modifier.size(19.dp),
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.titleSmall.copy(
                    fontSize = 14.5.sp,
                    fontFamily = if (isCodeStyleTitle) FontFamily.Monospace else FontFamily.SansSerif,
                ),
                color = colors.inkReading,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = item.subtitle,
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                color = colors.inkSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (item.isActionTrigger && !item.isSelected) {
            Icon(
                imageVector = Icons.Rounded.Add,
                contentDescription = "Add action",
                tint = colors.inkSecondary,
                modifier = Modifier.size(22.dp),
            )
        } else {
            Checkbox(
                checked = item.isSelected,
                onCheckedChange = null,
                colors = CheckboxDefaults.colors(
                    checkedColor = colors.accentPeriwinkle,
                    uncheckedColor = colors.inkMuted,
                    checkmarkColor = colors.inkOnPrimaryCta,
                ),
            )
        }
    }
}

private fun contextCandidateTestTag(item: ContextCandidateItem): String {
    val lower = item.title.lowercase()
    return when {
        lower.contains("ratelimit") -> "ctx-row-ratelimit"
        lower.contains("go-testing") -> "ctx-row-go-testing"
        else -> "ctx-row-${item.id}"
    }
}
