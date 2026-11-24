package dev.antigravity.android.ui.projects

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.android.ui.home.DrawerConversationTrailingIndicator
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.ProjectDetailTab
import dev.antigravity.shared.model.ProjectRuntimeTarget

/**
 * UE04_PROJECT_DETAIL (`and-project.png`): Native Material 3 Project Detail screen with
 * back/overflow bar, hero title + monospace path, 3 outlined metadata chips, underline TabRow,
 * single-line conversation rows, `This project` section (automation + Rules & skills), and Extended FAB.
 */
@Composable
fun ProjectDetailScreen(
    coordinator: AntigravityCoreCoordinator,
    projectId: String = "ledger-svc",
    onBack: () -> Unit,
    onNewConversation: (String) -> Unit,
    onOpenConversation: (String) -> Unit,
    onOpenAutomationDetail: (String) -> Unit = {},
    onOpenRulesAndSkills: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()

    val selectedTab = workspaceState.selectedProjectTab
    var overflowExpanded by remember { mutableStateOf(false) }

    val project = remember(workspaceState.projects, syncState.projects, projectId) {
        (workspaceState.projects + syncState.projects).firstOrNull {
            it.id == projectId || it.name.equals(projectId, ignoreCase = true)
        }
    }

    val isCloud = project?.runtime == ProjectRuntimeTarget.CLOUD
    val displayTitle = project?.name ?: projectId
    val pathDisplay = project?.pathDisplay ?: "~/code/$projectId"
    val hostName = project?.hostName ?: "MacBook Pro"
    val activeBranch = project?.activeBranch ?: "main"
    val rulesCount = project?.rulesAndSkillsCount ?: 4

    val projectSummaries = remember(syncState.summaries, projectId, displayTitle) {
        syncState.summaries.filter {
            it.projectSlug == projectId || it.projectSlug.equals(displayTitle, ignoreCase = true)
        }
    }
    val activeSummaries = remember(projectSummaries) { projectSummaries.filter { !it.isArchived } }
    val archivedSummaries = remember(projectSummaries) { projectSummaries.filter { it.isArchived } }
    val projectAutomations = remember(workspaceState.automations, projectId, displayTitle) {
        workspaceState.automations.filter {
            it.projectSlug == projectId || it.projectSlug.equals(displayTitle, ignoreCase = true)
        }
    }
    val primaryAutomation = projectAutomations.firstOrNull()

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 104.dp),
        ) {
            // Top bar: back arrow + overflow menu
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .size(AntigravityDesignTokens.MinTouchTarget)
                        .testTag("btn-back"),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "Back",
                        tint = colors.inkReading,
                    )
                }

                Spacer(modifier = Modifier.weight(1f))

                Box {
                    IconButton(
                        onClick = { overflowExpanded = true },
                        modifier = Modifier
                            .size(AntigravityDesignTokens.MinTouchTarget)
                            .testTag("project-overflow-btn"),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.MoreVert,
                            contentDescription = "More options",
                            tint = colors.inkReading,
                        )
                    }

                    DropdownMenu(
                        expanded = overflowExpanded,
                        onDismissRequest = { overflowExpanded = false },
                        containerColor = colors.surfacePopover,
                    ) {
                        DropdownMenuItem(
                            text = { Text("Rules & skills ($rulesCount)", color = colors.inkReading) },
                            onClick = {
                                overflowExpanded = false
                                onOpenRulesAndSkills()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("New conversation", color = colors.inkReading) },
                            onClick = {
                                overflowExpanded = false
                                onNewConversation(projectId)
                            },
                        )
                    }
                }
            }

            // Hero project title & monospace path
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 18.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = displayTitle,
                    style = MaterialTheme.typography.headlineLarge.copy(
                        fontSize = 31.sp,
                        fontWeight = FontWeight.Normal,
                        letterSpacing = (-0.5).sp,
                    ),
                    color = colors.inkReading,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = pathDisplay,
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontFamily = FontFamily.Monospace,
                        fontSize = 14.sp,
                    ),
                    color = colors.inkSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            Spacer(modifier = Modifier.height(14.dp))

            // Outlined Metadata Chips: Local · MacBook Pro | main ↑2 | Clean
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 18.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = colors.canvasObsidian,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        StatusDot(color = colors.statusDone, size = 7.dp, glow = false)
                        Text(
                            text = if (isCloud) "Cloud · VM" else "Local · $hostName",
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                            color = colors.inkReading,
                        )
                    }
                }

                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = colors.canvasObsidian,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.AccountTree,
                            contentDescription = null,
                            tint = colors.inkLabel,
                            modifier = Modifier.size(15.dp),
                        )
                        Text(
                            text = buildAnnotatedString {
                                withStyle(SpanStyle(color = colors.inkReading, fontFamily = FontFamily.Monospace)) {
                                    append(activeBranch)
                                }
                                withStyle(SpanStyle(color = colors.accentPeriwinkle, fontFamily = FontFamily.Monospace)) {
                                    append(" ↑2")
                                }
                            },
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                        )
                    }
                }

                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = colors.canvasObsidian,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Text(
                        text = "Clean",
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                        color = colors.inkReading,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    )
                }
            }

            Spacer(modifier = Modifier.height(14.dp))

            // 3-Tab Underline Bar: Active · 4 | Archived · 2 | Automations · 1
            val tabs = listOf(
                ProjectDetailTab.ACTIVE to "Active · ${activeSummaries.size}",
                ProjectDetailTab.ARCHIVED to "Archived · ${archivedSummaries.size}",
                ProjectDetailTab.AUTOMATIONS to "Automations · ${projectAutomations.size.coerceAtMost(1).coerceAtLeast(if (projectAutomations.isEmpty()) 0 else 1)}",
            )
            val selectedTabIndex = tabs.indexOfFirst { it.first == selectedTab }.coerceAtLeast(0)

            PrimaryTabRow(
                selectedTabIndex = selectedTabIndex,
                containerColor = colors.canvasObsidian,
                contentColor = colors.accentPeriwinkle,
                indicator = {
                    TabRowDefaults.PrimaryIndicator(
                        modifier = Modifier.tabIndicatorOffset(selectedTabIndex, matchContentSize = true),
                        width = 56.dp,
                        height = 3.dp,
                        color = colors.accentPeriwinkle,
                    )
                },
                divider = { HorizontalDivider(color = colors.subtleDivider) },
            ) {
                tabs.forEach { (tab, label) ->
                    val isSelected = selectedTab == tab
                    Tab(
                        selected = isSelected,
                        onClick = { coordinator.workspaceStore.selectProjectTab(tab) },
                        modifier = Modifier.testTag("project-tab-${tab.name.lowercase()}"),
                        text = {
                            Text(
                                text = label,
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontSize = 14.sp,
                                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                                ),
                                color = if (isSelected) colors.accentPeriwinkle else colors.inkSecondary,
                                maxLines = 1,
                            )
                        },
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            // Filtered single-line list matching `and-project.png`
            when (selectedTab) {
                ProjectDetailTab.ACTIVE -> {
                    activeSummaries.forEach { summary ->
                        val isTitleLoading = coordinator.isSummaryTitleLoading(summary)
                        val rowTitle = coordinator.displayTitleForSummary(summary)
                        LaunchedEffect(summary.cascadeId, summary.hasResolvedTitle) {
                            if (!coordinator.isVerificationMode) {
                                coordinator.prioritizeConversationPreload(summary.cascadeId)
                            }
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onOpenConversation(summary.cascadeId) }
                                .padding(horizontal = 18.dp, vertical = 16.dp)
                                .testTag("project-conv-${summary.cascadeId}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            if (isTitleLoading) {
                                Row(
                                    modifier = Modifier
                                        .weight(1f)
                                        .testTag("project-conv-loading-${summary.cascadeId}"),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    CircularProgressIndicator(
                                        strokeWidth = 1.8.dp,
                                        color = colors.inkMuted,
                                        modifier = Modifier.size(13.dp),
                                    )
                                    Text(
                                        text = "Loading...",
                                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                                        color = colors.inkMuted,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            } else {
                                Text(
                                    text = rowTitle,
                                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                                    color = colors.inkReading,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                            DrawerConversationTrailingIndicator(summary = summary)
                        }
                    }
                }

                ProjectDetailTab.ARCHIVED -> {
                    archivedSummaries.forEach { summary ->
                        val isTitleLoading = coordinator.isSummaryTitleLoading(summary)
                        val rowTitle = coordinator.displayTitleForSummary(summary)
                        LaunchedEffect(summary.cascadeId, summary.hasResolvedTitle) {
                            if (!coordinator.isVerificationMode) {
                                coordinator.prioritizeConversationPreload(summary.cascadeId)
                            }
                        }
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onOpenConversation(summary.cascadeId) }
                                .padding(horizontal = 18.dp, vertical = 16.dp)
                                .testTag("project-conv-${summary.cascadeId}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            if (isTitleLoading) {
                                Row(
                                    modifier = Modifier
                                        .weight(1f)
                                        .testTag("project-conv-loading-${summary.cascadeId}"),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    CircularProgressIndicator(
                                        strokeWidth = 1.8.dp,
                                        color = colors.inkMuted,
                                        modifier = Modifier.size(13.dp),
                                    )
                                    Text(
                                        text = "Loading...",
                                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                                        color = colors.inkMuted,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            } else {
                                Text(
                                    text = rowTitle,
                                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                                    color = colors.inkSecondary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                            Text(
                                text = summary.relativeTimeLabel,
                                style = MaterialTheme.typography.labelSmall,
                                color = colors.inkMuted,
                            )
                        }
                    }
                }

                ProjectDetailTab.AUTOMATIONS -> {
                    projectAutomations.forEach { automation ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onOpenAutomationDetail(automation.id) }
                                .padding(horizontal = 18.dp, vertical = 16.dp)
                                .testTag("project-auto-${automation.id}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Schedule,
                                contentDescription = null,
                                tint = colors.inkLabel,
                                modifier = Modifier.size(20.dp),
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = automation.title,
                                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                                    color = colors.inkReading,
                                )
                                Text(
                                    text = "${automation.repeatsLabel} · ${automation.nextRunText}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = colors.inkSecondary,
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(14.dp))

            // Blue `This project` section
            Text(
                text = "This project",
                style = MaterialTheme.typography.titleSmall.copy(
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                ),
                color = colors.accentPeriwinkle,
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 8.dp),
            )

            // Automation shortcut row -> UE06B Automation Detail
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        onOpenAutomationDetail(primaryAutomation?.id ?: "auto-nightly-audit")
                    }
                    .padding(horizontal = 18.dp, vertical = 14.dp)
                    .testTag("project-row-automation"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Schedule,
                    contentDescription = null,
                    tint = colors.inkLabel,
                    modifier = Modifier.size(21.dp),
                )
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = primaryAutomation?.title ?: "Nightly dependency audit",
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                        color = colors.inkReading,
                    )
                    Text(
                        text = "Every day · 2:00 AM · next in 6h",
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                        color = colors.inkSecondary,
                    )
                }
            }

            // Project rules & skills row -> UE14 Rules & Skills
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onOpenRulesAndSkills)
                    .padding(horizontal = 18.dp, vertical = 16.dp)
                    .testTag("project-row-rules-skills"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Description,
                    contentDescription = null,
                    tint = colors.inkLabel,
                    modifier = Modifier.size(21.dp),
                )
                Text(
                    text = "Project rules & skills",
                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                    color = colors.inkReading,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = "$rulesCount",
                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                    color = colors.inkSecondary,
                )
            }
        }

        // Bottom-right M3 Extended FAB (`and-project.png`)
        ExtendedFloatingActionButton(
            onClick = { onNewConversation(projectId) },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = 18.dp, bottom = 18.dp)
                .testTag("btn-new-conv-in-project"),
            shape = RoundedCornerShape(16.dp),
            containerColor = colors.surfaceActiveTab,
            contentColor = colors.pillActiveForeground,
            icon = {
                Icon(
                    imageVector = Icons.Rounded.Edit,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
            },
            text = {
                Text(
                    text = "New conversation in project",
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontSize = 14.5.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                )
            },
        )
    }
}
