package dev.antigravity.android.ui.projects

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRowDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
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
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.components.SectionHeaderLabel
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AutomationItem
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.ProjectDetailTab
import dev.antigravity.shared.model.ProjectRuntimeTarget

/**
 * UE04_PROJECT_DETAIL: Native Material 3 Project Detail screen with TopAppBar, hero identity,
 * metadata AssistChips, Periwinkle CTA, PrimaryTabRow (Active / Archived / Automations),
 * filtered conversation list card, and THIS PROJECT tools section.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProjectDetailScreen(
    coordinator: AntigravityCoreCoordinator,
    projectId: String = "ledger-svc",
    onBack: () -> Unit,
    onNewConversation: (String) -> Unit,
    onOpenConversation: (String) -> Unit,
    onOpenAutomations: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()

    val selectedTab = workspaceState.selectedProjectTab
    var overflowExpanded by remember { mutableStateOf(false) }
    var hostActionStatus by remember { mutableStateOf<String?>(null) }

    val project = remember(workspaceState.projects, syncState.projects, projectId) {
        (workspaceState.projects + syncState.projects).firstOrNull {
            it.id == projectId || it.name.equals(projectId, ignoreCase = true)
        }
    }

    val isCloud = project?.runtime == ProjectRuntimeTarget.CLOUD
    val displayTitle = project?.name ?: projectId
    val pathDisplay = project?.pathDisplay ?: "~/code/$projectId"
    val branchName = project?.activeBranch?.ifBlank { "main" } ?: "main"
    val hostName = project?.hostName?.ifBlank { "MacBook Pro" } ?: "MacBook Pro"
    val rulesAndSkillsCount = project?.rulesAndSkillsCount ?: 4

    val projectSummaries = remember(syncState.summaries, projectId, displayTitle) {
        syncState.summaries.filter { s ->
            s.projectSlug.equals(projectId, ignoreCase = true) ||
                s.projectSlug.equals(displayTitle, ignoreCase = true)
        }
    }
    val activeSummaries = remember(projectSummaries) {
        projectSummaries.filterNot { it.isArchived }
    }
    val archivedSummaries = remember(projectSummaries) {
        projectSummaries.filter { it.isArchived }
    }
    val projectAutomations = remember(workspaceState.automations, projectId, displayTitle) {
        workspaceState.automations.filter { item ->
            item.projectSlug.equals(projectId, ignoreCase = true) ||
                item.projectSlug.equals(displayTitle, ignoreCase = true) ||
                item.projectId == projectId
        }
    }

    val totalConversations = (activeSummaries.size + archivedSummaries.size).coerceAtLeast(1)
    val featuredAutomation = projectAutomations.firstOrNull()

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
    ) {
        // 1. Native Material 3 TopAppBar
        TopAppBar(
            title = {},
            navigationIcon = {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .size(AntigravityDesignTokens.MinTouchTarget)
                        .testTag("btn-back-agents"),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "Back to Agents",
                        tint = colors.inkReading,
                    )
                }
            },
            actions = {
                Box {
                    IconButton(
                        onClick = { overflowExpanded = true },
                        modifier = Modifier
                            .size(AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-project-more"),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.MoreVert,
                            contentDescription = "Project actions",
                            tint = colors.inkReading,
                        )
                    }
                    DropdownMenu(
                        expanded = overflowExpanded,
                        onDismissRequest = { overflowExpanded = false },
                        containerColor = colors.surfacePopover,
                    ) {
                        DropdownMenuItem(
                            text = { Text("Open workspace on Host", color = colors.inkReading) },
                            leadingIcon = {
                                Icon(Icons.Rounded.Computer, contentDescription = null, tint = colors.inkSecondary)
                            },
                            onClick = {
                                hostActionStatus = "Opened $displayTitle on $hostName"
                                overflowExpanded = false
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("View Automations", color = colors.inkReading) },
                            leadingIcon = {
                                Icon(Icons.Rounded.History, contentDescription = null, tint = colors.inkSecondary)
                            },
                            onClick = {
                                overflowExpanded = false
                                onOpenAutomations()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("New Conversation", color = colors.inkReading) },
                            leadingIcon = {
                                Icon(Icons.Rounded.Edit, contentDescription = null, tint = colors.accentPeriwinkle)
                            },
                            onClick = {
                                overflowExpanded = false
                                onNewConversation(project?.id ?: projectId)
                            },
                        )
                    }
                }
            },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = colors.canvasObsidian,
                navigationIconContentColor = colors.inkReading,
                actionIconContentColor = colors.inkReading,
            ),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // 2. Hero Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Surface(
                    modifier = Modifier.size(54.dp),
                    shape = RoundedCornerShape(16.dp),
                    color = colors.surfacePill,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = if (isCloud) Icons.Rounded.Cloud else Icons.Rounded.Folder,
                            contentDescription = null,
                            tint = colors.inkLabel,
                            modifier = Modifier.size(24.dp),
                        )
                    }
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        text = displayTitle,
                        style = MaterialTheme.typography.headlineMedium.copy(
                            fontSize = 27.sp,
                            lineHeight = 32.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.testTag("project-hero-title"),
                    )
                    Text(
                        text = pathDisplay,
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontFamily = FontFamily.Monospace,
                        ),
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            // 3. Metadata AssistChips Row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AssistChip(
                    onClick = {},
                    label = {
                        Text(
                            text = if (isCloud) "Cloud · $hostName" else "Local · $hostName",
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1,
                            softWrap = false,
                        )
                    },
                    leadingIcon = {
                        StatusDot(
                            color = if (isCloud) colors.accentPeriwinkle else colors.statusDone,
                            size = 7.dp,
                        )
                    },
                    shape = RoundedCornerShape(AntigravityDesignTokens.PillCornerRadius),
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = colors.surfacePill,
                        labelColor = colors.inkLabel,
                    ),
                    border = BorderStroke(1.dp, colors.cardBorder),
                )

                AssistChip(
                    onClick = {},
                    label = {
                        Text(
                            text = branchName,
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1,
                            softWrap = false,
                        )
                    },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Rounded.AccountTree,
                            contentDescription = null,
                            tint = colors.inkSecondary,
                            modifier = Modifier.size(15.dp),
                        )
                    },
                    shape = RoundedCornerShape(AntigravityDesignTokens.PillCornerRadius),
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = colors.surfacePill,
                        labelColor = colors.inkLabel,
                    ),
                    border = BorderStroke(1.dp, colors.cardBorder),
                )

                AssistChip(
                    onClick = {},
                    label = {
                        Text(
                            text = "$totalConversations conversations",
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1,
                            softWrap = false,
                        )
                    },
                    shape = RoundedCornerShape(AntigravityDesignTokens.PillCornerRadius),
                    colors = AssistChipDefaults.assistChipColors(
                        containerColor = colors.surfacePill,
                        labelColor = colors.inkLabel,
                    ),
                    border = BorderStroke(1.dp, colors.cardBorder),
                )
            }

            // 4. Full-Width Periwinkle CTA Button
            Button(
                onClick = { onNewConversation(project?.id ?: projectId) },
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 50.dp)
                    .testTag("btn-new-conv-in-project"),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.accentPeriwinkle,
                    contentColor = colors.inkOnPrimaryCta,
                ),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Edit,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "New Conversation in Project",
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontSize = 15.5.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    maxLines = 1,
                )
            }

            // 5. Material 3 PrimaryTabRow (Active / Archived / Automations)
            val tabs = listOf(
                Triple(ProjectDetailTab.ACTIVE, "Active ${activeSummaries.size}", "project-tab-active"),
                Triple(ProjectDetailTab.ARCHIVED, "Archived ${archivedSummaries.size}", "project-tab-archived"),
                Triple(ProjectDetailTab.AUTOMATIONS, "Automations ${projectAutomations.size}", "project-tab-automations"),
            )
            val selectedTabIndex = ProjectDetailTab.entries.indexOf(selectedTab).coerceAtLeast(0)

            PrimaryTabRow(
                selectedTabIndex = selectedTabIndex,
                containerColor = Color.Transparent,
                contentColor = colors.inkReading,
                indicator = {
                    TabRowDefaults.PrimaryIndicator(
                        modifier = Modifier.tabIndicatorOffset(selectedTabIndex),
                        color = colors.accentPeriwinkle,
                    )
                },
                divider = { HorizontalDivider(color = colors.subtleDivider) },
            ) {
                tabs.forEach { (tab, label, tag) ->
                    val isSelected = selectedTab == tab
                    Tab(
                        selected = isSelected,
                        onClick = { coordinator.workspaceStore.selectProjectTab(tab) },
                        modifier = Modifier.testTag(tag),
                        text = {
                            Text(
                                text = label,
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                                ),
                                color = if (isSelected) colors.inkReading else colors.inkMuted,
                                maxLines = 1,
                                softWrap = false,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                    )
                }
            }

            // 6. Filtered Tab Body Card
            AntigravitySurfaceCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("project-conv-list"),
                contentPadding = PaddingValues(0.dp),
            ) {
                when (selectedTab) {
                    ProjectDetailTab.ACTIVE -> {
                        if (activeSummaries.isEmpty()) {
                            ProjectEmptyListMessage("No active conversations in $displayTitle.")
                        } else {
                            activeSummaries.forEachIndexed { index, summary ->
                                ProjectConversationRow(
                                    summary = summary,
                                    onClick = { onOpenConversation(summary.cascadeId) },
                                )
                                if (index < activeSummaries.lastIndex) {
                                    HorizontalDivider(
                                        modifier = Modifier.padding(start = 42.dp),
                                        color = colors.subtleDivider,
                                    )
                                }
                            }
                        }
                    }

                    ProjectDetailTab.ARCHIVED -> {
                        if (archivedSummaries.isEmpty()) {
                            ProjectEmptyListMessage("No archived conversations in $displayTitle.")
                        } else {
                            archivedSummaries.forEachIndexed { index, summary ->
                                ProjectConversationRow(
                                    summary = summary,
                                    onClick = { onOpenConversation(summary.cascadeId) },
                                )
                                if (index < archivedSummaries.lastIndex) {
                                    HorizontalDivider(
                                        modifier = Modifier.padding(start = 42.dp),
                                        color = colors.subtleDivider,
                                    )
                                }
                            }
                        }
                    }

                    ProjectDetailTab.AUTOMATIONS -> {
                        if (projectAutomations.isEmpty()) {
                            ProjectEmptyListMessage("No automations configured for $displayTitle yet.")
                        } else {
                            projectAutomations.forEachIndexed { index, automation ->
                                ProjectAutomationRow(
                                    automation = automation,
                                    onClick = onOpenAutomations,
                                )
                                if (index < projectAutomations.lastIndex) {
                                    HorizontalDivider(
                                        modifier = Modifier.padding(start = 16.dp),
                                        color = colors.subtleDivider,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // 7. THIS PROJECT Section Card
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SectionHeaderLabel(
                    title = "THIS PROJECT",
                    modifier = Modifier.padding(start = 2.dp),
                )

                AntigravitySurfaceCard(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(0.dp),
                ) {
                    // Row 1: Featured Automation
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = 56.dp)
                            .clickable(onClick = onOpenAutomations)
                            .padding(horizontal = 14.dp, vertical = 11.dp)
                            .testTag("project-row-automation"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.History,
                            contentDescription = null,
                            tint = colors.inkLabel,
                            modifier = Modifier.size(20.dp),
                        )
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            Text(
                                text = featuredAutomation?.title ?: "Nightly dependency audit",
                                style = MaterialTheme.typography.titleSmall.copy(
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.SemiBold,
                                ),
                                color = colors.inkReading,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                text = featuredAutomation?.let { "${it.scheduleSummary} · Next ${it.nextRunText}" }
                                    ?: "Daily 02:00 · Next run in 6h",
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.inkSecondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Icon(
                            imageVector = Icons.Rounded.ChevronRight,
                            contentDescription = null,
                            tint = colors.inkMuted,
                            modifier = Modifier.size(18.dp),
                        )
                    }

                    HorizontalDivider(
                        modifier = Modifier.padding(start = 46.dp),
                        color = colors.subtleDivider,
                    )

                    // Row 2: Open workspace on Host
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .clickable {
                                hostActionStatus = "Opened on $hostName"
                            }
                            .padding(horizontal = 14.dp, vertical = 12.dp)
                            .testTag("project-row-open-host"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Computer,
                            contentDescription = null,
                            tint = colors.inkLabel,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = hostActionStatus ?: "Open workspace on Host",
                            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                            color = if (hostActionStatus != null) colors.accentPeriwinkle else colors.inkReading,
                            modifier = Modifier.weight(1f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }

                    HorizontalDivider(
                        modifier = Modifier.padding(start = 46.dp),
                        color = colors.subtleDivider,
                    )

                    // Row 3: Project rules & skills
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .clickable {}
                            .padding(horizontal = 14.dp, vertical = 12.dp)
                            .testTag("project-row-skills"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Description,
                            contentDescription = null,
                            tint = colors.inkLabel,
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = "Project rules & skills",
                            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                            color = colors.inkReading,
                            modifier = Modifier.weight(1f),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Surface(
                            shape = CircleShape,
                            color = colors.surfaceBadge,
                        ) {
                            Text(
                                text = rulesAndSkillsCount.toString(),
                                style = MaterialTheme.typography.labelSmall,
                                color = colors.inkSecondary,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ProjectConversationRow(
    summary: CascadeSummary,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    val isRunning = summary.status == CortexStepStatus.IN_PROGRESS || summary.status == CortexStepStatus.PENDING
    val isWaiting = summary.status == CortexStepStatus.WAITING || summary.status == CortexStepStatus.BLOCKED
    val subtitleColor = when {
        isRunning -> colors.statusRunning
        isWaiting -> colors.statusWaiting
        else -> colors.inkSecondary
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 56.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            modifier = Modifier
                .width(18.dp)
                .padding(top = 3.dp),
            contentAlignment = Alignment.Center,
        ) {
            when {
                isRunning -> {
                    Canvas(modifier = Modifier.size(15.dp)) {
                        val stroke = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round)
                        drawArc(colors.ringTrack, 0f, 360f, false, style = stroke)
                        drawArc(colors.statusRunning, -90f, 215f, false, style = stroke)
                    }
                }
                isWaiting -> StatusDot(color = colors.statusWaiting, size = 8.dp, glow = true)
                summary.isUnread -> StatusDot(color = colors.statusRunning, size = 8.dp, glow = false)
                else -> Spacer(modifier = Modifier.size(8.dp))
            }
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = summary.title,
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    color = colors.inkReading,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = summary.relativeTimeLabel,
                    style = MaterialTheme.typography.labelMedium,
                    color = colors.inkMuted,
                    maxLines = 1,
                )
            }
            val subtitle = buildAnnotatedString {
                withStyle(SpanStyle(color = subtitleColor)) {
                    append(summary.statusSubtitle.ifBlank { summary.status.displayBadgeText })
                }
                if (summary.totalAdditions > 0 || summary.totalDeletions > 0) {
                    append(" ")
                    withStyle(
                        SpanStyle(
                            color = colors.statusDone,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 12.sp,
                        ),
                    ) {
                        append("+${summary.totalAdditions}")
                    }
                    append(" ")
                    withStyle(
                        SpanStyle(
                            color = colors.statusError,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 12.sp,
                        ),
                    ) {
                        append("-${summary.totalDeletions}")
                    }
                }
            }
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun ProjectAutomationRow(
    automation: AutomationItem,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 56.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = automation.title,
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 15.sp),
                color = colors.inkReading,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = "${automation.scheduleSummary} · ${automation.lastRunText}",
                style = MaterialTheme.typography.bodySmall,
                color = if (automation.needsReview) colors.statusWaiting else colors.inkSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Surface(
            shape = CircleShape,
            color = colors.surfaceSelectionTint,
            modifier = Modifier.size(36.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    imageVector = Icons.Rounded.PlayArrow,
                    contentDescription = "Open automation",
                    tint = colors.accentPeriwinkle,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

@Composable
private fun ProjectEmptyListMessage(text: String) {
    val colors = MaterialTheme.antigravityColors
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = colors.inkSecondary,
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
    )
}
