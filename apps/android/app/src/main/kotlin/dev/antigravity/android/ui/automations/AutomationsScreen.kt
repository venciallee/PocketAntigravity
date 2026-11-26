package dev.antigravity.android.ui.automations

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AutomationItem
import dev.antigravity.shared.model.AutomationRunStatus
import dev.antigravity.shared.model.AutomationSectionKind
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/**
 * UE06_AUTOMATIONS (`and-automations.png`): Native Material 3 Automations Hub with
 * hamburger top bar, filter chips, Create with Prompt card, Scheduled/Always on/Paused sections,
 * and anchored overflow action menu.
 */
@Composable
fun AutomationsScreen(
    coordinator: AntigravityCoreCoordinator,
    onOpenSidebar: () -> Unit = {},
    onOpenAutomationDetail: (String) -> Unit = {},
    onEditAutomation: (String) -> Unit = {},
    initialExpandedMenuAutomationId: String? = null,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var promptInput by rememberSaveable { mutableStateOf("") }
    var sectionFilter by rememberSaveable { mutableStateOf<AutomationSectionKind?>(null) }
    var expandedMenuAutomationId by remember(initialExpandedMenuAutomationId) {
        mutableStateOf(initialExpandedMenuAutomationId)
    }

    val automations = workspaceState.automations
    val scheduledItems = remember(automations) {
        automations.filter { it.section == AutomationSectionKind.SCHEDULED }
    }
    val alwaysOnItems = remember(automations) {
        automations.filter { it.section == AutomationSectionKind.ALWAYS_ON }
    }
    val pausedItems = remember(automations) {
        automations.filter { it.section == AutomationSectionKind.PAUSED }
    }

    fun submitQuickCreate() {
        val text = promptInput.trim()
        if (text.isEmpty()) return
        promptInput = ""
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            val rpcClient = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
            coordinator.workspaceStore.createAutomationFromPrompt(client = rpcClient, prompt = text)
        }
    }

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
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // 1. Top Bar: Hamburger | Automations | Search
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                IconButton(
                    onClick = onOpenSidebar,
                    modifier = Modifier
                        .size(AntigravityDesignTokens.MinTouchTarget)
                        .testTag("btn-sidebar"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Menu,
                        contentDescription = tr("Open sidebar", "打开侧边栏"),
                        tint = colors.inkReading,
                    )
                }
                Text(
                    text = tr("Automations", "自动化"),
                    style = MaterialTheme.typography.headlineSmall.copy(
                        fontSize = 23.sp,
                        fontWeight = FontWeight.Normal,
                    ),
                    color = colors.inkReading,
                    modifier = Modifier.weight(1f),
                )
                IconButton(
                    onClick = {},
                    modifier = Modifier
                        .size(AntigravityDesignTokens.MinTouchTarget)
                        .testTag("btn-automations-search"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Search,
                        contentDescription = tr("Search automations", "搜索自动化"),
                        tint = colors.inkReading,
                    )
                }
            }

            // 2. Single-line FilterChip strip (`All`, `Scheduled 2`, `Always on 1`, `Paused 1`)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                AutomationFilterChip(
                    label = tr("All", "全部"),
                    selected = sectionFilter == null,
                    onClick = { sectionFilter = null },
                    modifier = Modifier.testTag("filter-auto-all"),
                )
                AutomationFilterChip(
                    label = tr("Scheduled ${scheduledItems.size}", "定时 ${scheduledItems.size}"),
                    selected = sectionFilter == AutomationSectionKind.SCHEDULED,
                    onClick = { sectionFilter = AutomationSectionKind.SCHEDULED },
                    modifier = Modifier.testTag("filter-auto-scheduled"),
                )
                AutomationFilterChip(
                    label = tr("Always on ${alwaysOnItems.size}", "持续运行 ${alwaysOnItems.size}"),
                    selected = sectionFilter == AutomationSectionKind.ALWAYS_ON,
                    onClick = { sectionFilter = AutomationSectionKind.ALWAYS_ON },
                    modifier = Modifier.testTag("filter-auto-always-on"),
                )
                AutomationFilterChip(
                    label = tr("Paused ${pausedItems.size}", "已暂停 ${pausedItems.size}"),
                    selected = sectionFilter == AutomationSectionKind.PAUSED,
                    onClick = { sectionFilter = AutomationSectionKind.PAUSED },
                    modifier = Modifier.testTag("filter-auto-paused"),
                )
            }

            // 3. Create with Prompt card (`and-automations.png`)
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("automation-create-card"),
                shape = RoundedCornerShape(20.dp),
                color = colors.surfaceCard,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Text(
                        text = tr("Create with Prompt", "通过提示词创建"),
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                        color = colors.inkSecondary,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Surface(
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(100.dp),
                            color = colors.surfaceElevated,
                        ) {
                            BasicTextField(
                                value = promptInput,
                                onValueChange = { promptInput = it },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 13.dp)
                                    .testTag("input-automation-prompt"),
                                singleLine = true,
                                textStyle = MaterialTheme.typography.bodyMedium.copy(
                                    fontSize = 14.5.sp,
                                    color = colors.inkReading,
                                ),
                                cursorBrush = SolidColor(colors.accentPeriwinkle),
                                decorationBox = { inner ->
                                    if (promptInput.isEmpty()) {
                                        Text(
                                            text = tr("Every weekday at 9, summarize...", "每个工作日 9 点总结..."),
                                            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp),
                                            color = colors.inkMuted,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                    inner()
                                },
                            )
                        }

                        Button(
                            onClick = { submitQuickCreate() },
                            modifier = Modifier
                                .defaultMinSize(minHeight = 44.dp)
                                .testTag("btn-create-automation"),
                            shape = RoundedCornerShape(100.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = colors.accentPeriwinkle,
                                contentColor = colors.inkOnPrimaryCta,
                            ),
                            contentPadding = PaddingValues(horizontal = 18.dp, vertical = 10.dp),
                        ) {
                            Text(
                                text = tr("Create", "创建"),
                                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                            )
                        }
                    }
                }
            }

            // 4. Scheduled Section
            if (sectionFilter == null || sectionFilter == AutomationSectionKind.SCHEDULED) {
                Text(
                    text = tr("Scheduled · ${scheduledItems.size}", "定时运行 · ${scheduledItems.size}"),
                    style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
                    color = colors.accentPeriwinkle,
                    modifier = Modifier.padding(top = 4.dp),
                )
                scheduledItems.forEach { item ->
                    ScheduledAutomationCard(
                        item = item,
                        onOpenDetail = { onOpenAutomationDetail(item.id) },
                        onOpenOverflow = { expandedMenuAutomationId = item.id },
                    )
                }
            }

            // 5. Always on Section
            if (sectionFilter == null || sectionFilter == AutomationSectionKind.ALWAYS_ON) {
                Text(
                    text = tr("Always on · ${alwaysOnItems.size}", "持续运行 · ${alwaysOnItems.size}"),
                    style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
                    color = colors.accentPeriwinkle,
                    modifier = Modifier.padding(top = 4.dp),
                )
                alwaysOnItems.forEach { item ->
                    Surface(
                        onClick = { onOpenAutomationDetail(item.id) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("automation-card-${item.id}"),
                        shape = RoundedCornerShape(18.dp),
                        color = colors.surfaceCard,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(
                                    text = item.title,
                                    style = MaterialTheme.typography.titleMedium.copy(
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    ),
                                    color = colors.inkReading,
                                )
                                Text(
                                    text = "${item.scheduleSummary} · ${item.lastRunText}",
                                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                                    color = colors.inkSecondary,
                                )
                            }
                            Surface(
                                shape = RoundedCornerShape(100.dp),
                                color = colors.statusDone.copy(alpha = 0.14f),
                            ) {
                                Text(
                                    text = tr("Listening", "监听中"),
                                    style = MaterialTheme.typography.labelMedium,
                                    color = colors.statusDone,
                                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                                )
                            }
                        }
                    }
                }
            }

            // 6. Paused Section
            if (sectionFilter == null || sectionFilter == AutomationSectionKind.PAUSED) {
                Text(
                    text = tr("Paused · ${pausedItems.size}", "已暂停 · ${pausedItems.size}"),
                    style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
                    color = colors.accentPeriwinkle,
                    modifier = Modifier.padding(top = 4.dp),
                )
                pausedItems.forEach { item ->
                    Surface(
                        onClick = { onOpenAutomationDetail(item.id) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("automation-card-${item.id}"),
                        shape = RoundedCornerShape(18.dp),
                        color = colors.surfaceCard,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(
                                    text = item.title,
                                    style = MaterialTheme.typography.titleMedium.copy(
                                        fontSize = 16.sp,
                                        fontWeight = FontWeight.SemiBold,
                                    ),
                                    color = colors.inkReading,
                                )
                                Text(
                                    text = item.scheduleSummary,
                                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                                    color = colors.inkSecondary,
                                )
                            }
                            OutlinedButton(
                                onClick = {
                                    scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                        val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                                        coordinator.workspaceStore.resumeAutomation(client = rpc, automationId = item.id)
                                    }
                                },
                                modifier = Modifier.testTag("btn-resume-${item.id}"),
                                shape = RoundedCornerShape(100.dp),
                                border = BorderStroke(1.dp, colors.cardBorder),
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            ) {
                                Text(
                                    text = tr("Resume", "恢复"),
                                    style = MaterialTheme.typography.labelLarge,
                                    color = colors.accentPeriwinkle,
                                )
                            }
                        }
                    }
                }
            }
        }

        // Anchored M3 Overflow Menu (`and-automations.png`: Run Now, Edit Schedule & Prompt, Pause, Restart, Delete)
        val menuTargetId = expandedMenuAutomationId
        if (menuTargetId != null) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable { expandedMenuAutomationId = null },
            )
            Surface(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .statusBarsPadding()
                    .padding(top = 310.dp, end = 24.dp)
                    .width(248.dp)
                    .zIndex(12f)
                    .testTag("automation-overflow-menu"),
                shape = RoundedCornerShape(16.dp),
                color = colors.surfacePopover,
                border = BorderStroke(1.dp, colors.cardBorder),
                shadowElevation = 10.dp,
            ) {
                Column(modifier = Modifier.padding(vertical = 8.dp)) {
                    OverflowMenuRow(
                        icon = Icons.Rounded.PlayArrow,
                        label = tr("Run Now", "立即运行"),
                        onClick = {
                            expandedMenuAutomationId = null
                            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                                coordinator.workspaceStore.runAutomationNow(client = rpc, automationId = menuTargetId)
                            }
                        },
                        modifier = Modifier.testTag("menu-run-now"),
                    )
                    OverflowMenuRow(
                        icon = Icons.Rounded.Edit,
                        label = tr("Edit Schedule &\nPrompt", "编辑计划与\n提示词"),
                        onClick = {
                            expandedMenuAutomationId = null
                            onEditAutomation(menuTargetId)
                        },
                        modifier = Modifier.testTag("menu-edit-automation"),
                    )
                    OverflowMenuRow(
                        icon = Icons.Rounded.Pause,
                        label = tr("Pause", "暂停"),
                        onClick = {
                            expandedMenuAutomationId = null
                            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                                coordinator.workspaceStore.pauseAutomation(client = rpc, automationId = menuTargetId)
                            }
                        },
                        modifier = Modifier.testTag("menu-pause-automation"),
                    )
                    OverflowMenuRow(
                        icon = Icons.Rounded.Refresh,
                        label = tr("Restart", "重新运行"),
                        onClick = {
                            expandedMenuAutomationId = null
                            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                                coordinator.workspaceStore.runAutomationNow(client = rpc, automationId = menuTargetId)
                            }
                        },
                        modifier = Modifier.testTag("menu-restart-automation"),
                    )
                    HorizontalDivider(
                        modifier = Modifier.padding(vertical = 6.dp),
                        color = colors.subtleDivider,
                    )
                    OverflowMenuRow(
                        icon = Icons.Rounded.DeleteOutline,
                        label = tr("Delete", "删除"),
                        tint = colors.statusError,
                        onClick = {
                            expandedMenuAutomationId = null
                            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                                coordinator.workspaceStore.deleteAutomation(client = rpc, automationId = menuTargetId)
                            }
                        },
                        modifier = Modifier.testTag("menu-delete-automation"),
                    )
                }
            }
        }
    }
}

@Composable
private fun AutomationFilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    FilterChip(
        selected = selected,
        onClick = onClick,
        modifier = modifier,
        label = {
            Text(
                text = label,
                maxLines = 1,
                softWrap = false,
            )
        },
        leadingIcon = if (selected) {
            { Icon(Icons.Rounded.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
        } else null,
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = colors.surfaceActiveTab,
            selectedLabelColor = colors.pillActiveForeground,
            selectedLeadingIconColor = colors.pillActiveForeground,
            containerColor = colors.canvasObsidian,
            labelColor = colors.inkReading,
        ),
        border = FilterChipDefaults.filterChipBorder(
            enabled = true,
            selected = selected,
            borderColor = colors.cardBorder,
            selectedBorderColor = colors.surfaceActiveTab,
        ),
    )
}

@Composable
private fun ScheduledAutomationCard(
    item: AutomationItem,
    onOpenDetail: () -> Unit,
    onOpenOverflow: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    Surface(
        onClick = onOpenDetail,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("automation-card-${item.id}"),
        shape = RoundedCornerShape(18.dp),
        color = colors.surfaceCard,
        border = BorderStroke(1.dp, colors.cardBorder),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        text = item.title,
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = item.scheduleSummary,
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                Surface(
                    onClick = onOpenOverflow,
                    modifier = Modifier
                        .size(38.dp)
                        .testTag("btn-overflow-${item.id}"),
                    shape = CircleShape,
                    color = colors.surfaceElevated,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Rounded.MoreVert,
                            contentDescription = tr("Automation actions", "自动化操作"),
                            tint = colors.inkReading,
                            modifier = Modifier.size(19.dp),
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = tr("NEXT RUN", "下次运行"),
                        style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, letterSpacing = 0.5.sp),
                        color = colors.inkMuted,
                    )
                    Text(
                        text = item.nextRunText,
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                        color = colors.inkReading,
                    )
                }

                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        text = tr("LAST RUN", "上次运行"),
                        style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, letterSpacing = 0.5.sp),
                        color = colors.inkMuted,
                    )
                    Text(
                        text = if (item.isRunningNow) tr("Running now...", "正在运行...") else item.lastRunText,
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                        color = when {
                            item.isRunningNow -> colors.statusRunning
                            item.needsReview -> colors.statusWaiting
                            else -> colors.statusDone
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun OverflowMenuRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    tint: Color = MaterialTheme.antigravityColors.inkReading,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(19.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp),
            color = tint,
        )
    }
}

/**
 * UE06B_AUTOMATION_DETAIL (`and-automation-detail.png`): Full-screen Automation Detail view
 * showing status badges, Run now / Pause primary pills, Prompt card, Next run & Runs on metadata,
 * and Recent runs history with Retry action on failed runs.
 */
@Composable
fun AutomationDetailScreen(
    coordinator: AntigravityCoreCoordinator,
    automationId: String = "auto-nightly-audit",
    onBack: () -> Unit,
    onEdit: (String) -> Unit,
    onOpenConversation: (String) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    val automation = remember(workspaceState.automations, automationId) {
        workspaceState.automations.firstOrNull { it.id == automationId }
            ?: workspaceState.automations.firstOrNull()
    }
    if (automation == null) {
        Box(modifier = modifier.fillMaxSize().background(colors.canvasObsidian))
        return
    }
    val isPaused = automation.section == AutomationSectionKind.PAUSED

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .statusBarsPadding()
            .navigationBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 28.dp),
    ) {
        // Top App Bar: Back | Title + subtitle | Edit doc icon + Overflow
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier
                    .size(AntigravityDesignTokens.MinTouchTarget)
                    .testTag("btn-back"),
            ) {
                Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = tr("Back", "返回"), tint = colors.inkReading)
            }

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(
                    text = automation.title,
                    style = MaterialTheme.typography.titleLarge.copy(fontSize = 19.sp, fontWeight = FontWeight.Normal),
                    color = colors.inkReading,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = "${automation.projectSlug} · ${automation.modelLabel}",
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                    color = colors.inkSecondary,
                )
            }

            IconButton(
                onClick = { onEdit(automation.id) },
                modifier = Modifier
                    .size(AntigravityDesignTokens.MinTouchTarget)
                    .testTag("btn-edit-automation"),
            ) {
                Icon(Icons.Rounded.Description, contentDescription = tr("Edit automation", "编辑自动化"), tint = colors.inkReading, modifier = Modifier.size(21.dp))
            }

            IconButton(
                onClick = { onEdit(automation.id) },
                modifier = Modifier.size(AntigravityDesignTokens.MinTouchTarget),
            ) {
                Icon(Icons.Rounded.MoreVert, contentDescription = tr("More options", "更多选项"), tint = colors.inkReading)
            }
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Status pills row: ● Scheduled · Active | Every day · 2:00 AM
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = if (isPaused) colors.surfaceElevated else Color(0xFF15291E),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(7.dp),
                    ) {
                        StatusDot(
                            color = if (isPaused) colors.inkMuted else colors.statusDone,
                            size = 7.dp,
                            glow = false,
                        )
                        Text(
                            text = if (isPaused) tr("Paused", "已暂停") else tr("Scheduled · Active", "定时运行 · 已启用"),
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                            color = if (isPaused) colors.inkSecondary else colors.statusDone,
                        )
                    }
                }

                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = colors.canvasObsidian,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Text(
                        text = automation.repeatsLabel,
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                        color = colors.inkReading,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 7.dp),
                    )
                }
            }

            // Primary Dual Pill CTAs: Run now | Pause/Resume
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Button(
                    onClick = {
                        scope.launch(start = CoroutineStart.UNDISPATCHED) {
                            val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                            coordinator.workspaceStore.runAutomationNow(client = rpc, automationId = automation.id)
                        }
                    },
                    modifier = Modifier
                        .weight(1f)
                        .height(48.dp)
                        .testTag("btn-automation-run-now"),
                    shape = RoundedCornerShape(100.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.accentPeriwinkle,
                        contentColor = colors.inkOnPrimaryCta,
                    ),
                ) {
                    Text(
                        text = if (automation.isRunningNow) tr("Running...", "运行中...") else tr("Run now", "立即运行"),
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
                    )
                }

                Button(
                    onClick = {
                        scope.launch(start = CoroutineStart.UNDISPATCHED) {
                            val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                            if (isPaused) {
                                coordinator.workspaceStore.resumeAutomation(client = rpc, automationId = automation.id)
                            } else {
                                coordinator.workspaceStore.pauseAutomation(client = rpc, automationId = automation.id)
                            }
                        }
                    },
                    modifier = Modifier
                        .weight(1f)
                        .height(48.dp)
                        .testTag("btn-automation-pause-resume"),
                    shape = RoundedCornerShape(100.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.surfaceActiveTab,
                        contentColor = colors.pillActiveForeground,
                    ),
                ) {
                    Text(
                        text = if (isPaused) tr("Resume", "恢复") else tr("Pause", "暂停"),
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
                    )
                }
            }

            // Prompt Card
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("automation-prompt-card"),
                shape = RoundedCornerShape(18.dp),
                color = colors.surfaceCard,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = tr("Prompt", "提示词"),
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                        color = colors.accentPeriwinkle,
                    )
                    Text(
                        text = automation.prompt,
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp, lineHeight = 22.sp),
                        color = colors.inkReading,
                    )
                }
            }

            // Schedule metadata rows: Next run + Runs on
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Icon(Icons.Rounded.Schedule, contentDescription = null, tint = colors.inkLabel, modifier = Modifier.size(21.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(tr("Next run", "下次运行"), style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp), color = colors.inkReading)
                        Text(
                            text = tr(
                                "Tonight, ${automation.timeLabel} (${automation.timezoneLabel})",
                                "今晚 ${automation.timeLabel}（${automation.timezoneLabel}）",
                            ),
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                            color = colors.inkSecondary,
                        )
                    }
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Icon(Icons.Rounded.Computer, contentDescription = null, tint = colors.inkLabel, modifier = Modifier.size(21.dp))
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(tr("Runs on", "运行主机"), style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp), color = colors.inkReading)
                        Text(
                            text = tr("MacBook Pro · new conversation per run", "MacBook Pro · 每次运行新建对话"),
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                            color = colors.inkSecondary,
                        )
                    }
                }
            }

            // Recent runs header
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = tr("Recent runs", "最近运行"),
                    style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
                    color = colors.accentPeriwinkle,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = tr("Each run opens a conversation", "每次运行都会创建新对话"),
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp),
                    color = colors.inkSecondary,
                )
            }

            // Recent run rows
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                automation.recentRuns.forEach { run ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onOpenConversation(automation.lastRunCascadeId ?: "cas-upgrade-go")
                            }
                            .testTag("automation-run-${run.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Box(modifier = Modifier.size(22.dp), contentAlignment = Alignment.Center) {
                            when (run.status) {
                                AutomationRunStatus.SUCCEEDED -> Icon(
                                    Icons.Rounded.Check,
                                    contentDescription = null,
                                    tint = colors.statusDone,
                                    modifier = Modifier.size(20.dp),
                                )
                                AutomationRunStatus.NEEDS_REVIEW -> StatusDot(color = colors.statusWaiting, size = 10.dp, glow = false)
                                AutomationRunStatus.FAILED -> Icon(
                                    Icons.Rounded.Close,
                                    contentDescription = null,
                                    tint = colors.statusError,
                                    modifier = Modifier.size(20.dp),
                                )
                                AutomationRunStatus.RUNNING -> StatusDot(color = colors.statusRunning, size = 10.dp, glow = true)
                            }
                        }

                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                text = run.timestampLabel,
                                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp),
                                color = when (run.status) {
                                    AutomationRunStatus.NEEDS_REVIEW -> colors.statusWaiting
                                    AutomationRunStatus.FAILED -> colors.statusError
                                    else -> colors.inkReading
                                },
                            )
                            Text(
                                text = run.summary,
                                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                                color = colors.inkSecondary,
                            )
                        }

                        if (run.canRetry) {
                            OutlinedButton(
                                onClick = {
                                    scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                        val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                                        coordinator.workspaceStore.retryAutomationRun(
                                            client = rpc,
                                            automationId = automation.id,
                                            runId = run.id,
                                        )
                                    }
                                },
                                modifier = Modifier.testTag("btn-retry-${run.id}"),
                                shape = RoundedCornerShape(100.dp),
                                border = BorderStroke(1.dp, colors.cardBorder),
                                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 6.dp),
                            ) {
                                Text(
                                    text = tr("Retry", "重试"),
                                    style = MaterialTheme.typography.labelLarge,
                                    color = colors.accentPeriwinkle,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/**
 * UE06C_AUTOMATION_EDIT (`and-automation-edit.png`): Full-screen Material 3 Edit Automation
 * dialog with Name/Prompt/Project OutlinedTextFields, Trigger SegmentedButton + Repeat FilterChips,
 * Time row, Model SegmentedButton, unattended footer, and Delete automation button.
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AutomationEditScreen(
    coordinator: AntigravityCoreCoordinator,
    automationId: String = "auto-nightly-audit",
    onDismiss: () -> Unit,
    onDeleted: () -> Unit = onDismiss,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    val automation = remember(workspaceState.automations, automationId) {
        workspaceState.automations.firstOrNull { it.id == automationId }
            ?: workspaceState.automations.firstOrNull()
    }

    var name by remember(automationId) { mutableStateOf(automation?.title ?: "Nightly dependency audit") }
    var prompt by remember(automationId) {
        mutableStateOf(
            automation?.prompt
                ?: "Check go.mod for outdated or vulnerable modules. Open a PR for patch bumps only and summarize the rest.",
        )
    }
    var projectSlug by remember(automationId) { mutableStateOf(automation?.projectSlug ?: "ledger-svc") }
    var projectMenuExpanded by remember { mutableStateOf(false) }
    var isScheduleTrigger by remember(automationId) {
        mutableStateOf(automation?.section != AutomationSectionKind.ALWAYS_ON)
    }
    var repeatCadence by remember(automationId) { mutableStateOf("Every day") }
    var timeLabel by remember(automationId) { mutableStateOf(automation?.timeLabel ?: "2:00 AM") }
    var modelChoice by remember(automationId) { mutableStateOf(automation?.modelLabel ?: "Flash") }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        // Top Header: X | Edit automation | [Save]
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            IconButton(
                onClick = onDismiss,
                modifier = Modifier
                    .size(AntigravityDesignTokens.MinTouchTarget)
                    .testTag("btn-close-edit-automation"),
            ) {
                Icon(Icons.Rounded.Close, contentDescription = tr("Close", "关闭"), tint = colors.inkReading)
            }

            Text(
                text = tr("Edit automation", "编辑自动化"),
                style = MaterialTheme.typography.headlineSmall.copy(fontSize = 21.sp, fontWeight = FontWeight.Normal),
                color = colors.inkReading,
                modifier = Modifier.weight(1f),
            )

            Button(
                onClick = {
                    scope.launch(start = CoroutineStart.UNDISPATCHED) {
                        val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                        coordinator.workspaceStore.updateAutomation(
                            client = rpc,
                            automationId = automationId,
                            title = name,
                            prompt = prompt,
                            projectSlug = projectSlug,
                            section = if (isScheduleTrigger) AutomationSectionKind.SCHEDULED else AutomationSectionKind.ALWAYS_ON,
                            repeatsLabel = repeatCadence,
                            timeLabel = timeLabel,
                            modelLabel = modelChoice,
                        )
                    }
                    onDismiss()
                },
                modifier = Modifier
                    .defaultMinSize(minHeight = 42.dp)
                    .testTag("btn-save-automation"),
                shape = RoundedCornerShape(100.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.accentPeriwinkle,
                    contentColor = colors.inkOnPrimaryCta,
                ),
            ) {
                Text(tr("Save", "保存"), style = MaterialTheme.typography.labelLarge.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold))
            }
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp, vertical = 6.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(tr("Name", "名称")) },
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("input-edit-automation-name"),
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.inkReading),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = colors.accentPeriwinkle,
                    unfocusedBorderColor = colors.cardBorder,
                    focusedLabelColor = colors.accentPeriwinkle,
                    unfocusedLabelColor = colors.inkSecondary,
                ),
            )

            OutlinedTextField(
                value = prompt,
                onValueChange = { prompt = it },
                label = { Text(tr("Prompt", "提示词")) },
                minLines = 3,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("input-edit-automation-prompt"),
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.inkReading, lineHeight = 22.sp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = colors.accentPeriwinkle,
                    unfocusedBorderColor = colors.accentPeriwinkle,
                    focusedLabelColor = colors.accentPeriwinkle,
                    unfocusedLabelColor = colors.accentPeriwinkle,
                ),
            )

            Box(modifier = Modifier.fillMaxWidth()) {
                OutlinedTextField(
                    value = projectSlug,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(tr("Project", "项目")) },
                    leadingIcon = { Icon(Icons.Rounded.Folder, contentDescription = null, tint = colors.inkSecondary, modifier = Modifier.size(18.dp)) },
                    trailingIcon = { Icon(Icons.Rounded.ArrowDropDown, contentDescription = null, tint = colors.inkSecondary) },
                    modifier = Modifier.fillMaxWidth(),
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.inkReading),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = colors.accentPeriwinkle,
                        unfocusedBorderColor = colors.cardBorder,
                        focusedLabelColor = colors.accentPeriwinkle,
                        unfocusedLabelColor = colors.inkSecondary,
                    ),
                )
                Box(modifier = Modifier.matchParentSize().clickable { projectMenuExpanded = true })
                DropdownMenu(
                    expanded = projectMenuExpanded,
                    onDismissRequest = { projectMenuExpanded = false },
                    containerColor = colors.surfacePopover,
                ) {
                    listOf("ledger-svc", "web-console").forEach { slug ->
                        DropdownMenuItem(
                            text = { Text(slug, color = colors.inkReading) },
                            onClick = {
                                projectSlug = slug
                                projectMenuExpanded = false
                            },
                        )
                    }
                }
            }

            Text(
                text = tr("Trigger", "触发方式"),
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                color = colors.accentPeriwinkle,
            )

            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = isScheduleTrigger,
                    onClick = { isScheduleTrigger = true },
                    shape = SegmentedButtonDefaults.itemShape(0, 2),
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = colors.surfaceActiveTab,
                        activeContentColor = colors.pillActiveForeground,
                        inactiveContainerColor = colors.canvasObsidian,
                        inactiveContentColor = colors.inkReading,
                        activeBorderColor = colors.cardBorder,
                        inactiveBorderColor = colors.cardBorder,
                    ),
                ) { Text(tr("Schedule", "定时")) }

                SegmentedButton(
                    selected = !isScheduleTrigger,
                    onClick = { isScheduleTrigger = false },
                    shape = SegmentedButtonDefaults.itemShape(1, 2),
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = colors.surfaceActiveTab,
                        activeContentColor = colors.pillActiveForeground,
                        inactiveContainerColor = colors.canvasObsidian,
                        inactiveContentColor = colors.inkReading,
                        activeBorderColor = colors.cardBorder,
                        inactiveBorderColor = colors.cardBorder,
                    ),
                ) { Text(tr("Always on", "持续运行")) }
            }

            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                listOf(
                    "Every hour" to tr("Every hour", "每小时"),
                    "Every day" to tr("Every day", "每天"),
                    "Weekdays" to tr("Weekdays", "工作日"),
                    "Every week" to tr("Every week", "每周"),
                ).forEach { (option, displayLabel) ->
                    val selected = repeatCadence == option
                    FilterChip(
                        selected = selected,
                        onClick = { repeatCadence = option },
                        label = { Text(displayLabel) },
                        leadingIcon = if (selected) {
                            { Icon(Icons.Rounded.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
                        } else null,
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = colors.surfaceActiveTab,
                            selectedLabelColor = colors.pillActiveForeground,
                            selectedLeadingIconColor = colors.pillActiveForeground,
                            containerColor = colors.canvasObsidian,
                            labelColor = colors.inkReading,
                        ),
                        border = FilterChipDefaults.filterChipBorder(
                            enabled = true,
                            selected = selected,
                            borderColor = colors.cardBorder,
                            selectedBorderColor = colors.surfaceActiveTab,
                        ),
                    )
                }
            }

            // Time row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        timeLabel = if (timeLabel == "2:00 AM") "9:00 AM" else "2:00 AM"
                    }
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Icon(Icons.Rounded.Schedule, contentDescription = null, tint = colors.inkLabel, modifier = Modifier.size(21.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(tr("Time", "时间"), style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp), color = colors.inkReading)
                    Text(
                        text = tr(
                            "${automation?.timezoneLabel ?: "GMT+8:00"} · from this phone",
                            "${automation?.timezoneLabel ?: "GMT+8:00"} · 来自本机时区",
                        ),
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = colors.inkSecondary,
                    )
                }
                Text(
                    text = timeLabel,
                    style = MaterialTheme.typography.titleMedium.copy(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
                    color = colors.inkReading,
                )
            }

            Text(
                text = tr("Model", "模型"),
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                color = colors.accentPeriwinkle,
            )

            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                val choices = listOf("Flash Lite", "Flash", "Pro")
                choices.forEachIndexed { idx, label ->
                    SegmentedButton(
                        selected = modelChoice == label,
                        onClick = { modelChoice = label },
                        shape = SegmentedButtonDefaults.itemShape(idx, choices.size),
                        colors = SegmentedButtonDefaults.colors(
                            activeContainerColor = colors.surfaceActiveTab,
                            activeContentColor = colors.pillActiveForeground,
                            inactiveContainerColor = colors.canvasObsidian,
                            inactiveContentColor = colors.inkReading,
                            activeBorderColor = colors.cardBorder,
                            inactiveBorderColor = colors.cardBorder,
                        ),
                    ) { Text(label) }
                }
            }

            Text(
                text = tr(
                    "Runs unattended: anything that needs approval is denied automatically and the run shows up as Needs review.",
                    "无人值守运行：需要审批的操作将自动拒绝，本次运行会标记为「待审查」。",
                ),
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp, lineHeight = 19.sp),
                color = colors.inkSecondary,
            )

            TextButton(
                onClick = {
                    scope.launch(start = CoroutineStart.UNDISPATCHED) {
                        val rpc = if (coordinator.isVerificationMode) null else coordinator.connectionStore.activeClient()
                        coordinator.workspaceStore.deleteAutomation(client = rpc, automationId = automationId)
                    }
                    onDeleted()
                },
                modifier = Modifier.testTag("btn-delete-automation"),
                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 8.dp),
            ) {
                Text(
                    text = tr("Delete automation", "删除自动化"),
                    style = MaterialTheme.typography.titleSmall.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium),
                    color = colors.statusError,
                )
            }
        }
    }
}
