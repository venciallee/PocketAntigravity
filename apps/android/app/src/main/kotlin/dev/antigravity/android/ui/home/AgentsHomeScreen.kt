package dev.antigravity.android.ui.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.CreateNewFolder
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Hub
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.WorkOutline
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.ConversationSortField
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import kotlinx.coroutines.launch

/**
 * UE01_AGENTS_HOME (`and-new.png`): Native Material 3 New Conversation Home with top hamburger,
 * host switcher pill, search action, centered greeting, needs-approval banner, and bottom
 * project-scoped composer card.
 */
@Composable
fun AgentsHomeScreen(
    coordinator: AntigravityCoreCoordinator,
    onOpenSidebar: () -> Unit,
    onOpenConversation: (String) -> Unit,
    onOpenAddContext: () -> Unit = {},
    onOpenModelPicker: () -> Unit = {},
    onOpenPermissionsPreset: () -> Unit = {},
    onOpenSlashMenu: () -> Unit = {},
    onOpenVoiceMode: () -> Unit = {},
    onOpenReSignIn: () -> Unit = {},
    composerDraftOverride: String? = null,
    highlightAddContextButton: Boolean = false,
    highlightPermissionsPill: Boolean = false,
    showGreeting: Boolean = true,
    showNeedsApprovalBanner: Boolean = true,
    showSearchAction: Boolean = true,
    showHostChevron: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val connectionState by coordinator.connectionState.collectAsStateWithLifecycle()
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val settingsState by coordinator.settingsStore.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var hostMenuExpanded by remember { mutableStateOf(false) }
    var projectMenuExpanded by remember { mutableStateOf(false) }
    var branchMenuExpanded by remember { mutableStateOf(false) }
    var isSearchOpen by rememberSaveable { mutableStateOf(false) }
    var searchQuery by rememberSaveable { mutableStateOf("") }
    var draftText by rememberSaveable(composerDraftOverride) {
        mutableStateOf(composerDraftOverride ?: "")
    }
    var cloudModeEnabled by rememberSaveable { mutableStateOf(false) }
    var selectedBranchLabel by rememberSaveable { mutableStateOf("Repo default") }

    val allProjects = remember(workspaceState.projects, syncState.projects) {
        (workspaceState.projects + syncState.projects).distinctBy { it.id }
    }
    val selectedProject = remember(allProjects, workspaceState.selectedProjectId) {
        allProjects.firstOrNull { it.id == workspaceState.selectedProjectId }
            ?: allProjects.firstOrNull()
    }
    val selectedProjectName = selectedProject?.name ?: "ledger-svc"

    val hostScope = connectionState.selectedHostScope
    val hostDisplayName = remember(hostScope, connectionState.activeHost) {
        when (hostScope) {
            AgentsHostFilterScope.AntigravityCloud -> "Cloud"
            is AgentsHostFilterScope.LocalHost -> hostScope.name.ifBlank { "MacBook Pro" }
            AgentsHostFilterScope.AllHosts ->
                connectionState.activeHost?.hostname?.takeIf { it.isNotBlank() } ?: "MacBook Pro"
        }
    }
    val isHostOnline = remember(hostScope, connectionState) {
        when {
            !connectionState.hasPairedBackend -> true
            hostScope is AgentsHostFilterScope.AntigravityCloud -> connectionState.isDeviceNetworkReachable
            else -> connectionState.isConnected && (connectionState.activeHost?.isOnline != false)
        }
    }

    val needsApprovalSummary = remember(syncState.summaries) {
        syncState.summaries.firstOrNull {
            !it.isArchived && (it.pendingInteractionTitle != null || it.status == CortexStepStatus.WAITING || it.status == CortexStepStatus.BLOCKED)
        } ?: syncState.summaries.firstOrNull { it.cascadeId == "cas-rate-limiter" }
    }

    val selectedModelName = settingsState.selectedModel?.displayName ?: "Gemini 4 Neon"
    val effortLabel = when (settingsState.selectedEffort.displayTitle) {
        "Extra" -> "Extra High"
        else -> settingsState.selectedEffort.displayTitle
    }
    val permissionLabel = when (settingsState.activePermissionPreset.displayTitle) {
        "Default" -> "Default"
        else -> settingsState.activePermissionPreset.displayTitle
    }

    fun submitHomePrompt() {
        val text = draftText.trim()
        if (text.isEmpty()) return
        if (coordinator.isVerificationMode) {
            coordinator.chatStore.setActiveCascade("cas-rate-limiter")
            scope.launch {
                coordinator.sendMessage(
                    cascadeId = "cas-rate-limiter",
                    message = text,
                    isOptimisticDraft = false,
                )
            }
            draftText = ""
            onOpenConversation("cas-rate-limiter")
            return
        }
        val draftId = coordinator.createLocalDraftConversation(
            workspaceUri = selectedProject?.workspaceUri.orEmpty(),
            projectSlug = selectedProject?.id.orEmpty(),
            title = text.take(48),
        )
        scope.launch {
            runCatching {
                coordinator.sendMessage(
                    cascadeId = draftId,
                    message = text,
                    workspaceUri = selectedProject?.workspaceUri.orEmpty(),
                    isOptimisticDraft = true,
                )
            }
        }
        draftText = ""
        onOpenConversation(draftId)
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
                .imePadding(),
        ) {
            // Top bar: Hamburger · Host Pill · Search
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    onClick = onOpenSidebar,
                    modifier = Modifier
                        .size(AntigravityDesignTokens.MinTouchTarget)
                        .testTag("btn-sidebar"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Menu,
                        contentDescription = "Open sidebar",
                        tint = colors.inkReading,
                        modifier = Modifier.size(24.dp),
                    )
                }

                Spacer(modifier = Modifier.weight(1f))

                Box {
                    Surface(
                        onClick = { hostMenuExpanded = true },
                        modifier = Modifier
                            .defaultMinSize(minHeight = 40.dp)
                            .testTag("host-switcher-pill"),
                        shape = RoundedCornerShape(100.dp),
                        color = colors.surfaceCard,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            StatusDot(
                                color = if (isHostOnline) colors.statusDone else colors.statusError,
                                size = 8.dp,
                                glow = false,
                            )
                            Text(
                                text = hostDisplayName,
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Medium,
                                ),
                                color = colors.inkReading,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (showHostChevron) {
                                Icon(
                                    imageVector = Icons.Rounded.KeyboardArrowDown,
                                    contentDescription = "Switch host",
                                    tint = colors.inkSecondary,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        }
                    }

                    DropdownMenu(
                        expanded = hostMenuExpanded,
                        onDismissRequest = { hostMenuExpanded = false },
                        containerColor = colors.surfacePopover,
                    ) {
                        DropdownMenuItem(
                            text = { Text("All Hosts", color = colors.inkReading) },
                            leadingIcon = {
                                Icon(Icons.Rounded.Hub, contentDescription = null, tint = colors.accentPeriwinkle)
                            },
                            trailingIcon = {
                                if (hostScope is AgentsHostFilterScope.AllHosts) {
                                    Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accentPeriwinkle)
                                }
                            },
                            onClick = {
                                hostMenuExpanded = false
                                coordinator.connectionStore.selectHostScope(AgentsHostFilterScope.AllHosts)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Antigravity Cloud", color = colors.inkReading) },
                            leadingIcon = {
                                Icon(Icons.Rounded.Cloud, contentDescription = null, tint = colors.accentPeriwinkle)
                            },
                            trailingIcon = {
                                if (hostScope is AgentsHostFilterScope.AntigravityCloud) {
                                    Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accentPeriwinkle)
                                }
                            },
                            onClick = {
                                hostMenuExpanded = false
                                coordinator.connectionStore.selectHostScope(AgentsHostFilterScope.AntigravityCloud)
                            },
                        )
                        connectionState.knownHosts.forEach { host ->
                            DropdownMenuItem(
                                text = {
                                    Column {
                                        Text(host.hostname, color = colors.inkReading)
                                        Text(
                                            text = if (host.isOnline) "Online · ${host.version}" else "Offline · ${host.version}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = if (host.isOnline) colors.statusDone else colors.inkMuted,
                                        )
                                    }
                                },
                                leadingIcon = {
                                    Icon(Icons.Rounded.Computer, contentDescription = null, tint = colors.inkSecondary)
                                },
                                onClick = {
                                    hostMenuExpanded = false
                                    coordinator.connectionStore.selectHostScope(
                                        AgentsHostFilterScope.LocalHost(host.instanceId, host.hostname),
                                    )
                                },
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.weight(1f))

                if (showSearchAction) {
                    IconButton(
                        onClick = { isSearchOpen = !isSearchOpen },
                        modifier = Modifier
                            .size(AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-search"),
                    ) {
                        Icon(
                            imageVector = if (isSearchOpen) Icons.Rounded.Close else Icons.Rounded.Search,
                            contentDescription = "Search conversations",
                            tint = colors.inkReading,
                            modifier = Modifier.size(24.dp),
                        )
                    }
                } else {
                    Spacer(modifier = Modifier.size(AntigravityDesignTokens.MinTouchTarget))
                }
            }

            if (isSearchOpen) {
                GlobalSearchSection(
                    query = searchQuery,
                    onQueryChange = { searchQuery = it },
                    summaries = syncState.summaries,
                    onSelectConversation = { cascadeId ->
                        isSearchOpen = false
                        onOpenConversation(cascadeId)
                    },
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                )
            } else {
                // Center Greeting Canvas
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(horizontal = 32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (showGreeting) {
                        Text(
                            text = "Welcome back,\nAlex. Where\nshould we pick up?",
                            style = MaterialTheme.typography.headlineMedium.copy(
                                fontSize = 30.sp,
                                lineHeight = 38.sp,
                                fontWeight = FontWeight.Normal,
                                letterSpacing = (-0.4).sp,
                            ),
                            color = colors.inkReading,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.testTag("home-greeting"),
                        )
                    }
                }

                // Needs approval banner directly above composer
                if (showNeedsApprovalBanner && needsApprovalSummary != null) {
                    Surface(
                        onClick = { onOpenConversation(needsApprovalSummary.cascadeId) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp)
                            .padding(bottom = 14.dp)
                            .defaultMinSize(minHeight = 52.dp)
                            .testTag("home-needs-approval-banner"),
                        shape = RoundedCornerShape(18.dp),
                        color = colors.surfaceAmberTint,
                        border = BorderStroke(1.dp, colors.statusWaiting.copy(alpha = 0.22f)),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            StatusDot(
                                color = colors.statusWaiting,
                                size = 8.dp,
                                glow = false,
                            )
                            Text(
                                text = buildAnnotatedString {
                                    withStyle(
                                        SpanStyle(
                                            color = colors.statusWaiting,
                                            fontWeight = FontWeight.SemiBold,
                                        ),
                                    ) {
                                        append("Needs approval")
                                    }
                                    withStyle(SpanStyle(color = colors.inkSecondary)) {
                                        append(" · ")
                                    }
                                    withStyle(SpanStyle(color = colors.inkReading)) {
                                        append(needsApprovalSummary.title)
                                    }
                                },
                                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f),
                            )
                            Icon(
                                imageVector = Icons.Rounded.ChevronRight,
                                contentDescription = "Open approval",
                                tint = colors.inkLabel,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                }

                // Bottom New Conversation Composer Card (`and-new.png`)
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 14.dp)
                        .padding(bottom = 14.dp)
                        .testTag("home-composer-card"),
                    shape = RoundedCornerShape(24.dp),
                    color = colors.surfaceCard,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        // Top project + branch + cloud row
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 11.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(14.dp),
                        ) {
                            Box {
                                Row(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(8.dp))
                                        .clickable { projectMenuExpanded = true }
                                        .padding(vertical = 2.dp)
                                        .testTag("home-project-picker"),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Folder,
                                        contentDescription = null,
                                        tint = colors.inkSecondary,
                                        modifier = Modifier.size(16.dp),
                                    )
                                    Text(
                                        text = selectedProjectName,
                                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                                        color = colors.inkLabel,
                                        maxLines = 1,
                                    )
                                    Icon(
                                        imageVector = Icons.Rounded.KeyboardArrowDown,
                                        contentDescription = null,
                                        tint = colors.inkSecondary,
                                        modifier = Modifier.size(16.dp),
                                    )
                                }

                                DropdownMenu(
                                    expanded = projectMenuExpanded,
                                    onDismissRequest = { projectMenuExpanded = false },
                                    containerColor = colors.surfacePopover,
                                ) {
                                    allProjects.forEach { project ->
                                        DropdownMenuItem(
                                            text = { Text(project.name, color = colors.inkReading) },
                                            onClick = {
                                                projectMenuExpanded = false
                                                coordinator.workspaceStore.selectProject(project.id)
                                            },
                                        )
                                    }
                                }
                            }

                            Box {
                                Row(
                                    modifier = Modifier
                                        .clip(RoundedCornerShape(8.dp))
                                        .clickable { branchMenuExpanded = true }
                                        .padding(vertical = 2.dp)
                                        .testTag("home-branch-picker"),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.AccountTree,
                                        contentDescription = null,
                                        tint = colors.inkSecondary,
                                        modifier = Modifier.size(15.dp),
                                    )
                                    Text(
                                        text = selectedBranchLabel,
                                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                                        color = colors.inkLabel,
                                        maxLines = 1,
                                    )
                                    Icon(
                                        imageVector = Icons.Rounded.KeyboardArrowDown,
                                        contentDescription = null,
                                        tint = colors.inkSecondary,
                                        modifier = Modifier.size(16.dp),
                                    )
                                }

                                DropdownMenu(
                                    expanded = branchMenuExpanded,
                                    onDismissRequest = { branchMenuExpanded = false },
                                    containerColor = colors.surfacePopover,
                                ) {
                                    listOf("Repo default", "main", "New worktree").forEach { branch ->
                                        DropdownMenuItem(
                                            text = { Text(branch, color = colors.inkReading) },
                                            onClick = {
                                                branchMenuExpanded = false
                                                selectedBranchLabel = branch
                                            },
                                        )
                                    }
                                }
                            }

                            Spacer(modifier = Modifier.weight(1f))

                            Icon(
                                imageVector = Icons.Rounded.Cloud,
                                contentDescription = "Toggle Cloud VM",
                                tint = if (cloudModeEnabled) colors.accentPeriwinkle else colors.inkSecondary,
                                modifier = Modifier
                                    .size(20.dp)
                                    .clickable { cloudModeEnabled = !cloudModeEnabled }
                                    .testTag("home-cloud-toggle"),
                            )
                        }

                        // Inner text input + bottom toolbar container
                        Surface(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(start = 6.dp, end = 6.dp, bottom = 6.dp),
                            shape = RoundedCornerShape(18.dp),
                            color = colors.surfaceElevated,
                        ) {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 14.dp, vertical = 12.dp),
                                verticalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                BasicTextField(
                                    value = draftText,
                                    onValueChange = { updated ->
                                        draftText = updated
                                        if (updated == "/") {
                                            onOpenSlashMenu()
                                        }
                                    },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .testTag("home-composer-input"),
                                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                                        fontSize = 16.sp,
                                        color = colors.inkReading,
                                    ),
                                    cursorBrush = SolidColor(colors.accentPeriwinkle),
                                    decorationBox = { inner ->
                                        if (draftText.isEmpty()) {
                                            Text(
                                                text = "Ask anything, @ to mention, / for actions",
                                                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                                                color = colors.inkMuted,
                                            )
                                        }
                                        inner()
                                    },
                                )

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                ) {
                                    // Add context (+) button
                                    Surface(
                                        onClick = onOpenAddContext,
                                        modifier = Modifier
                                            .size(36.dp)
                                            .testTag("btn-add-context"),
                                        shape = CircleShape,
                                        color = if (highlightAddContextButton) colors.surfaceActiveTab else Color.Transparent,
                                    ) {
                                        Box(contentAlignment = Alignment.Center) {
                                            Icon(
                                                imageVector = Icons.Rounded.Add,
                                                contentDescription = "Add context",
                                                tint = colors.inkReading,
                                                modifier = Modifier.size(22.dp),
                                            )
                                        }
                                    }

                                    // Model & effort two-line selector
                                    Row(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(10.dp))
                                            .clickable(onClick = onOpenModelPicker)
                                            .padding(horizontal = 4.dp, vertical = 2.dp)
                                            .testTag("btn-model-picker"),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                                    ) {
                                        Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
                                            Text(
                                                text = selectedModelName,
                                                style = MaterialTheme.typography.labelMedium.copy(
                                                    fontSize = 13.sp,
                                                    fontWeight = FontWeight.Medium,
                                                ),
                                                color = colors.inkReading,
                                                maxLines = 1,
                                            )
                                            Text(
                                                text = effortLabel,
                                                style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp),
                                                color = colors.inkSecondary,
                                                maxLines = 1,
                                            )
                                        }
                                        Icon(
                                            imageVector = Icons.Rounded.KeyboardArrowDown,
                                            contentDescription = "Select model",
                                            tint = colors.inkSecondary,
                                            modifier = Modifier.size(16.dp),
                                        )
                                    }

                                    // Permissions preset pill (`🛡 Default ⌄`)
                                    Surface(
                                        onClick = onOpenPermissionsPreset,
                                        modifier = Modifier.testTag("btn-permissions-preset"),
                                        shape = RoundedCornerShape(10.dp),
                                        color = if (highlightPermissionsPill) colors.surfaceActiveTab else Color.Transparent,
                                    ) {
                                        Row(
                                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                                        ) {
                                            Icon(
                                                imageVector = Icons.Rounded.Shield,
                                                contentDescription = null,
                                                tint = colors.inkLabel,
                                                modifier = Modifier.size(15.dp),
                                            )
                                            Text(
                                                text = permissionLabel,
                                                style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.5.sp),
                                                color = colors.inkReading,
                                                maxLines = 1,
                                            )
                                            Icon(
                                                imageVector = Icons.Rounded.KeyboardArrowDown,
                                                contentDescription = "Permissions",
                                                tint = colors.inkSecondary,
                                                modifier = Modifier.size(16.dp),
                                            )
                                        }
                                    }

                                    Spacer(modifier = Modifier.weight(1f))

                                    IconButton(
                                        onClick = onOpenVoiceMode,
                                        modifier = Modifier
                                            .size(34.dp)
                                            .testTag("btn-voice-mode"),
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.Mic,
                                            contentDescription = "Voice mode",
                                            tint = colors.inkLabel,
                                            modifier = Modifier.size(20.dp),
                                        )
                                    }

                                    val canSend = draftText.isNotBlank()
                                    Surface(
                                        onClick = { submitHomePrompt() },
                                        modifier = Modifier
                                            .size(36.dp)
                                            .testTag("btn-home-send"),
                                        shape = CircleShape,
                                        color = if (canSend) colors.accentPeriwinkle else Color(0xFF2E2E35),
                                    ) {
                                        Box(contentAlignment = Alignment.Center) {
                                            Icon(
                                                imageVector = Icons.AutoMirrored.Rounded.ArrowForward,
                                                contentDescription = "Send",
                                                tint = if (canSend) colors.inkOnPrimaryCta else colors.inkSecondary,
                                                modifier = Modifier.size(18.dp),
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
    }
}

@Composable
private fun GlobalSearchSection(
    query: String,
    onQueryChange: (String) -> Unit,
    summaries: List<CascadeSummary>,
    onSelectConversation: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val filtered = remember(summaries, query) {
        val q = query.trim().lowercase()
        summaries.filter { !it.isArchived }.filter { s ->
            q.isEmpty() ||
                s.title.lowercase().contains(q) ||
                s.projectSlug.lowercase().contains(q) ||
                s.statusSubtitle.lowercase().contains(q)
        }
    }

    Column(
        modifier = modifier.padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp),
            color = colors.surfaceCard,
            border = BorderStroke(1.dp, colors.cardBorder),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.inkSecondary, modifier = Modifier.size(18.dp))
                BasicTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    modifier = Modifier
                        .weight(1f)
                        .testTag("search-input"),
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium.copy(color = colors.inkReading),
                    cursorBrush = SolidColor(colors.accentPeriwinkle),
                    decorationBox = { inner ->
                        if (query.isEmpty()) {
                            Text("Search conversations, projects...", color = colors.inkMuted)
                        }
                        inner()
                    },
                )
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(filtered, key = { it.cascadeId }) { item ->
                Surface(
                    onClick = { onSelectConversation(item.cascadeId) },
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(14.dp),
                    color = colors.surfaceCard,
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(item.title, color = colors.inkReading, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(
                                "${item.projectSlug} · ${item.statusSubtitle}",
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.inkSecondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Text(item.relativeTimeLabel, style = MaterialTheme.typography.labelSmall, color = colors.inkMuted)
                    }
                }
            }
        }
    }
}

/**
 * UE01B_SIDEBAR_DRAWER (`and-home.png`): Left Material 3 Modal Navigation Drawer overlay
 * rendered over the dimmed New Conversation Home screen.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AgentsSidebarDrawerOverlay(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    onNewConversation: (projectId: String) -> Unit,
    onOpenAutomations: () -> Unit,
    onOpenCustomizations: () -> Unit,
    onOpenDisplayOptions: () -> Unit,
    onOpenNewProject: () -> Unit,
    onOpenProjectDetail: (String) -> Unit,
    onOpenConversation: (String) -> Unit,
    onLongPressConversation: (String) -> Unit,
    onOpenSettings: () -> Unit,
    activeHighlightCascadeId: String = "cas-rate-limiter",
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val scrimColor = if (colors.isDark) Color.Black.copy(alpha = 0.62f) else Color.Black.copy(alpha = 0.36f)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
    ) {
        // Underlying New Conversation Home backdrop visible on the right margin
        AgentsHomeScreen(
            coordinator = coordinator,
            onOpenSidebar = {},
            onOpenConversation = {},
            showNeedsApprovalBanner = false,
            modifier = Modifier.fillMaxSize(),
        )

        // Tap-to-dismiss scrim
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(scrimColor)
                .testTag("sidebar-scrim")
                .clickable(onClick = onDismiss),
        )

        // Left-docked Material 3 Navigation Drawer sheet (~81% width)
        Surface(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth(0.815f)
                .align(Alignment.CenterStart)
                .testTag("sidebar-drawer"),
            shape = RoundedCornerShape(topEnd = 20.dp, bottomEnd = 20.dp),
            color = colors.surfaceObsidian,
            border = BorderStroke(1.dp, colors.subtleDivider),
        ) {
            AgentsSidebarDrawerContent(
                coordinator = coordinator,
                onNewConversation = onNewConversation,
                onOpenAutomations = onOpenAutomations,
                onOpenCustomizations = onOpenCustomizations,
                onOpenDisplayOptions = onOpenDisplayOptions,
                onOpenNewProject = onOpenNewProject,
                onOpenProjectDetail = onOpenProjectDetail,
                onOpenConversation = onOpenConversation,
                onLongPressConversation = onLongPressConversation,
                onOpenSettings = onOpenSettings,
                activeHighlightCascadeId = activeHighlightCascadeId,
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AgentsSidebarDrawerContent(
    coordinator: AntigravityCoreCoordinator,
    onNewConversation: (projectId: String) -> Unit,
    onOpenAutomations: () -> Unit,
    onOpenCustomizations: () -> Unit,
    onOpenDisplayOptions: () -> Unit,
    onOpenNewProject: () -> Unit,
    onOpenProjectDetail: (String) -> Unit,
    onOpenConversation: (String) -> Unit,
    onLongPressConversation: (String) -> Unit,
    onOpenSettings: () -> Unit,
    activeHighlightCascadeId: String = "cas-rate-limiter",
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val displayOptions = workspaceState.displayOptions

    val allProjects = remember(workspaceState.projects, syncState.projects) {
        (workspaceState.projects + syncState.projects).distinctBy { it.id }
    }

    val visibleSummaries = remember(syncState.summaries, displayOptions) {
        val filtered = syncState.summaries.filter { s ->
            if (displayOptions.archivedOnly) s.isArchived else !s.isArchived
        }
        val comparator: Comparator<CascadeSummary> = when (displayOptions.sortBy) {
            ConversationSortField.LAST_UPDATED -> compareBy { it.updatedAtEpochMs }
            ConversationSortField.DATE_CREATED -> compareBy { it.updatedAtEpochMs }
            ConversationSortField.TITLE -> compareBy { it.title.lowercase() }
        }
        if (displayOptions.sortBy == ConversationSortField.TITLE) {
            if (displayOptions.newestFirst) filtered.sortedWith(comparator) else filtered.sortedWith(comparator.reversed())
        } else {
            if (displayOptions.newestFirst) filtered.sortedWith(comparator.reversed()) else filtered.sortedWith(comparator)
        }
    }

    // Match `and-home.png`: keep active conversation inside its project group while showing other pinned items in Pinned
    val pinnedItems = remember(visibleSummaries, activeHighlightCascadeId) {
        visibleSummaries.filter { it.isPinned && it.cascadeId != activeHighlightCascadeId }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(top = 18.dp),
    ) {
        // Primary tonal CTA pill: + New Conversation
        Surface(
            onClick = { onNewConversation("") },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
                .defaultMinSize(minHeight = 52.dp)
                .testTag("btn-new-conversation"),
            shape = RoundedCornerShape(16.dp),
            color = colors.surfaceActiveTab,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Add,
                    contentDescription = null,
                    tint = colors.pillActiveForeground,
                    modifier = Modifier.size(22.dp),
                )
                Text(
                    text = "New Conversation",
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontSize = 15.5.sp,
                        fontWeight = FontWeight.Medium,
                    ),
                    color = colors.pillActiveForeground,
                )
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        // Top nav shortcuts: Automations & Customizations
        DrawerNavItem(
            icon = Icons.Rounded.Schedule,
            label = "Automations",
            onClick = onOpenAutomations,
            modifier = Modifier.testTag("drawer-automations"),
        )
        DrawerNavItem(
            icon = Icons.Rounded.WorkOutline,
            label = "Customizations",
            onClick = onOpenCustomizations,
            modifier = Modifier.testTag("drawer-customizations"),
        )

        HorizontalDivider(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
            color = colors.subtleDivider,
        )

        // Scrollable Pinned & Projects list
        LazyColumn(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentPadding = PaddingValues(bottom = 12.dp),
        ) {
            if (pinnedItems.isNotEmpty()) {
                item(key = "section-pinned") {
                    Text(
                        text = "Pinned",
                        style = MaterialTheme.typography.labelMedium.copy(
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.inkSecondary,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                }
                items(pinnedItems, key = { "pinned-${it.cascadeId}" }) { summary ->
                    DrawerConversationRow(
                        summary = summary,
                        isSelected = false,
                        indented = false,
                        onClick = { onOpenConversation(summary.cascadeId) },
                        onLongClick = { onLongPressConversation(summary.cascadeId) },
                    )
                }
            }

            // Projects Section Header with Display Options + Create Project icons
            item(key = "section-projects") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 20.dp, end = 12.dp, top = 12.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Projects",
                        style = MaterialTheme.typography.labelMedium.copy(
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.inkSecondary,
                        modifier = Modifier.weight(1f),
                    )
                    IconButton(
                        onClick = onOpenDisplayOptions,
                        modifier = Modifier
                            .size(38.dp)
                            .testTag("btn-display-options"),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.FilterList,
                            contentDescription = "Display options",
                            tint = colors.inkLabel,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                    IconButton(
                        onClick = onOpenNewProject,
                        modifier = Modifier
                            .size(38.dp)
                            .testTag("btn-create-project"),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.CreateNewFolder,
                            contentDescription = "New project",
                            tint = colors.inkLabel,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            allProjects.forEach { project ->
                val projectItems = visibleSummaries.filter { s ->
                    (s.projectSlug == project.id || s.projectSlug == project.name) &&
                        (!s.isPinned || s.cascadeId == activeHighlightCascadeId)
                }
                item(key = "project-header-${project.id}") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onOpenProjectDetail(project.id) }
                            .padding(start = 20.dp, end = 12.dp, top = 8.dp, bottom = 4.dp)
                            .testTag("project-header-${project.id}"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(
                            imageVector = if (project.runtime == ProjectRuntimeTarget.CLOUD) Icons.Rounded.Cloud else Icons.Rounded.Folder,
                            contentDescription = null,
                            tint = colors.inkSecondary,
                            modifier = Modifier.size(18.dp),
                        )
                        Text(
                            text = if (project.runtime == ProjectRuntimeTarget.CLOUD && !project.name.contains("/")) {
                                "acme/${project.name}"
                            } else {
                                project.name
                            },
                            style = MaterialTheme.typography.bodyMedium.copy(
                                fontSize = 14.5.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.inkSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        IconButton(
                            onClick = { onNewConversation(project.id) },
                            modifier = Modifier
                                .size(34.dp)
                                .testTag("project-add-${project.id}"),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Add,
                                contentDescription = "New conversation in ${project.name}",
                                tint = colors.inkLabel,
                                modifier = Modifier.size(19.dp),
                            )
                        }
                    }
                }

                items(projectItems, key = { "proj-${project.id}-${it.cascadeId}" }) { summary ->
                    DrawerConversationRow(
                        summary = summary,
                        isSelected = summary.cascadeId == activeHighlightCascadeId,
                        indented = true,
                        onClick = { onOpenConversation(summary.cascadeId) },
                        onLongClick = { onLongPressConversation(summary.cascadeId) },
                    )
                }
            }
        }

        // Bottom Settings Footer
        HorizontalDivider(
            modifier = Modifier.padding(horizontal = 16.dp),
            color = colors.subtleDivider,
        )
        DrawerNavItem(
            icon = Icons.Rounded.Settings,
            label = "Settings",
            onClick = onOpenSettings,
            modifier = Modifier
                .padding(vertical = 8.dp)
                .testTag("drawer-settings"),
        )
    }
}

@Composable
private fun DrawerNavItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = colors.inkLabel,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge.copy(
                fontSize = 15.5.sp,
                fontWeight = FontWeight.Medium,
            ),
            color = colors.inkReading,
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DrawerConversationRow(
    summary: CascadeSummary,
    isSelected: Boolean,
    indented: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    val containerModifier = if (isSelected) {
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = 2.dp)
            .clip(RoundedCornerShape(100.dp))
            .background(colors.surfaceActiveTab)
    } else {
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = 1.dp)
            .clip(RoundedCornerShape(12.dp))
    }

    Row(
        modifier = containerModifier
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(
                start = if (indented) 36.dp else 10.dp,
                end = 14.dp,
                top = 12.dp,
                bottom = 12.dp,
            )
            .testTag("conversation-row-${summary.cascadeId}"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = summary.title,
            style = MaterialTheme.typography.bodyMedium.copy(
                fontSize = 15.sp,
                fontWeight = if (isSelected || summary.isUnread) FontWeight.Medium else FontWeight.Normal,
            ),
            color = colors.inkReading,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )

        DrawerConversationTrailingIndicator(summary = summary)
    }
}

@Composable
internal fun DrawerConversationTrailingIndicator(summary: CascadeSummary) {
    val colors = MaterialTheme.antigravityColors
    when {
        summary.pendingInteractionTitle != null ||
            summary.status == CortexStepStatus.WAITING ||
            summary.status == CortexStepStatus.BLOCKED -> {
            if (summary.cascadeId == "cas-flaky-settlement") {
                StatusDot(color = colors.statusRunning, size = 8.dp, glow = false)
            } else {
                StatusDot(color = colors.statusWaiting, size = 8.dp, glow = false)
            }
        }

        summary.status == CortexStepStatus.IN_PROGRESS || summary.status == CortexStepStatus.PENDING -> {
            MiniProgressRing(
                color = colors.statusRunning,
                trackColor = colors.ringTrack,
                size = 15.dp,
            )
        }

        summary.isUnread -> {
            StatusDot(color = colors.statusRunning, size = 8.dp, glow = false)
        }

        else -> {
            Text(
                text = summary.relativeTimeLabel,
                style = MaterialTheme.typography.labelSmall.copy(fontSize = 12.5.sp),
                color = colors.inkMuted,
                maxLines = 1,
            )
        }
    }
}

@Composable
internal fun MiniProgressRing(
    color: Color,
    trackColor: Color,
    size: Dp = 15.dp,
) {
    Canvas(modifier = Modifier.size(size)) {
        val stroke = Stroke(width = 2.2.dp.toPx(), cap = StrokeCap.Round)
        drawCircle(color = trackColor, style = stroke)
        drawArc(
            color = color,
            startAngle = -90f,
            sweepAngle = 120f,
            useCenter = false,
            style = stroke,
        )
    }
}
