package dev.antigravity.android.ui.home

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Cloud
import androidx.compose.material.icons.rounded.Computer
import androidx.compose.material.icons.rounded.CreateNewFolder
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Hub
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.components.HostSwitcherPill
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.AgentsQuickFilter
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.ConversationSortField
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.DisplayGroupBy
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace

/**
 * UE01_AGENTS_HOME: Native Material 3 Agents Hub displaying the active host switcher,
 * display/project actions, search input, live status filter chips, pinned conversations card,
 * and collapsible project conversation groups.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AgentsHomeScreen(
    coordinator: AntigravityCoreCoordinator,
    onOpenDisplayOptions: () -> Unit,
    onOpenNewProject: () -> Unit,
    onOpenProjectDetail: (String) -> Unit,
    onOpenConversation: (String) -> Unit,
    onLongPressConversation: (String) -> Unit,
    onTapComposeFab: () -> Unit = {},
    onOpenReSignIn: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val connectionState by coordinator.connectionState.collectAsStateWithLifecycle()
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()

    var searchQuery by rememberSaveable { mutableStateOf("") }
    var selectedFilter by rememberSaveable { mutableStateOf(AgentsQuickFilter.ALL) }
    var hostMenuExpanded by remember { mutableStateOf(false) }

    val displayOptions = workspaceState.displayOptions
    val collapsedProjectIds = workspaceState.collapsedProjectIds
    val allProjects = remember(workspaceState.projects, syncState.projects) {
        (workspaceState.projects + syncState.projects).distinctBy { it.id }
    }

    val hostScope = connectionState.selectedHostScope
    val hostDisplayName = remember(
        hostScope,
        connectionState.activeHost,
        connectionState.knownHosts,
        coordinator.isVerificationMode,
    ) {
        when (hostScope) {
            AgentsHostFilterScope.AntigravityCloud -> "Antigravity Cloud"
            is AgentsHostFilterScope.LocalHost -> hostScope.name.ifBlank { "MacBook Pro" }
            AgentsHostFilterScope.AllHosts -> {
                val localHostCount = connectionState.knownHosts.count {
                    it.channel == dev.antigravity.shared.model.RemoteConnectionChannel.DIRECT_HOST
                }
                if (!coordinator.isVerificationMode && connectionState.hasPairedBackend && localHostCount > 1) {
                    "All Hosts"
                } else {
                    connectionState.activeHost?.hostname?.takeIf { it.isNotBlank() } ?: "MacBook Pro"
                }
            }
        }
    }
    val isHostOnline = remember(hostScope, connectionState) {
        when {
            !connectionState.hasPairedBackend -> true
            hostScope is AgentsHostFilterScope.AntigravityCloud -> connectionState.isDeviceNetworkReachable
            else -> connectionState.isConnected && (connectionState.activeHost?.isOnline != false)
        }
    }

    // Apply archived-only & host scope filter first for accurate filter chip counts
    val scopeFilteredSummaries = remember(syncState.summaries, hostScope, displayOptions.archivedOnly) {
        syncState.summaries.filter { summary ->
            val archiveMatches = if (displayOptions.archivedOnly) summary.isArchived else !summary.isArchived
            if (!archiveMatches) return@filter false
            when (hostScope) {
                AgentsHostFilterScope.AllHosts -> true
                AgentsHostFilterScope.AntigravityCloud -> summary.isCloud
                is AgentsHostFilterScope.LocalHost -> !summary.isCloud &&
                    (summary.originInstanceUuid == hostScope.id || summary.originHostName == hostScope.name || summary.originInstanceUuid == null)
            }
        }
    }

    val runningCount = remember(scopeFilteredSummaries) {
        scopeFilteredSummaries.count {
            it.status == CortexStepStatus.IN_PROGRESS || it.status == CortexStepStatus.PENDING
        }
    }
    val needsYouCount = remember(scopeFilteredSummaries) {
        scopeFilteredSummaries.count {
            it.status == CortexStepStatus.WAITING || it.status == CortexStepStatus.BLOCKED
        }
    }
    val unreadCount = remember(scopeFilteredSummaries) {
        scopeFilteredSummaries.count { it.isUnread }
    }

    val visibleSummaries = remember(
        scopeFilteredSummaries,
        selectedFilter,
        searchQuery,
        displayOptions.sortBy,
        displayOptions.newestFirst,
    ) {
        val trimmedQuery = searchQuery.trim().lowercase()
        val filtered = scopeFilteredSummaries.filter { summary ->
            val matchesQuickFilter = when (selectedFilter) {
                AgentsQuickFilter.ALL -> true
                AgentsQuickFilter.RUNNING ->
                    summary.status == CortexStepStatus.IN_PROGRESS || summary.status == CortexStepStatus.PENDING
                AgentsQuickFilter.NEEDS_YOU ->
                    summary.status == CortexStepStatus.WAITING || summary.status == CortexStepStatus.BLOCKED
                AgentsQuickFilter.UNREAD -> summary.isUnread
            }
            if (!matchesQuickFilter) return@filter false
            if (trimmedQuery.isEmpty()) {
                true
            } else {
                summary.title.lowercase().contains(trimmedQuery) ||
                    summary.projectSlug.lowercase().contains(trimmedQuery) ||
                    summary.statusSubtitle.lowercase().contains(trimmedQuery)
            }
        }
        val comparator: Comparator<CascadeSummary> = when (displayOptions.sortBy) {
            ConversationSortField.LAST_UPDATED -> compareBy { it.updatedAtEpochMs }
            ConversationSortField.DATE_CREATED -> compareBy { it.updatedAtEpochMs }
            ConversationSortField.TITLE -> compareBy { it.title.lowercase() }
        }
        if (displayOptions.sortBy == ConversationSortField.TITLE) {
            if (displayOptions.newestFirst) filtered.sortedWith(comparator)
            else filtered.sortedWith(comparator.reversed())
        } else {
            if (displayOptions.newestFirst) filtered.sortedWith(comparator.reversed())
            else filtered.sortedWith(comparator)
        }
    }

    val pinnedSummaries = remember(visibleSummaries) {
        visibleSummaries.filter { it.isPinned }
    }
    val unpinnedSummaries = remember(visibleSummaries) {
        visibleSummaries.filterNot { it.isPinned }
    }

    val projectGroups = remember(allProjects, unpinnedSummaries, displayOptions.groupBy, selectedFilter, searchQuery) {
        val groupedBySlug = unpinnedSummaries.groupBy { it.projectSlug.ifBlank { "ledger-svc" } }
        val knownProjects = allProjects.mapNotNull { project ->
            val items = groupedBySlug[project.id].orEmpty() +
                if (project.name != project.id) groupedBySlug[project.name].orEmpty() else emptyList()
            val deduped = items.distinctBy { it.cascadeId }
            val showEmptyProject = selectedFilter == AgentsQuickFilter.ALL && searchQuery.isBlank()
            if (deduped.isEmpty() && !showEmptyProject) null else project to deduped
        }
        val representedSlugs = allProjects.flatMap { listOf(it.id, it.name) }.toSet()
        val extraGroups = groupedBySlug.entries
            .filter { (slug, items) -> slug !in representedSlugs && items.isNotEmpty() }
            .map { (slug, items) ->
                val sample = items.first()
                ProjectWorkspace(
                    id = slug,
                    name = slug,
                    pathDisplay = sample.workspaceUri.removePrefix("file://").ifBlank { "~/code/$slug" },
                    workspaceUri = sample.workspaceUri,
                    runtime = if (sample.isCloud) ProjectRuntimeTarget.CLOUD else ProjectRuntimeTarget.MAC_BOOK_PRO,
                    hostName = sample.originHostName ?: "MacBook Pro",
                    activeBranch = sample.branchName,
                ) to items
            }
        knownProjects + extraGroups
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 104.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // 1. Top Bar: Host Switcher + Display Options + New Project
        item(key = "home-top-bar") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box {
                    HostSwitcherPill(
                        hostName = hostDisplayName,
                        isOnline = isHostOnline,
                        isCloud = hostScope is AgentsHostFilterScope.AntigravityCloud,
                        modifier = Modifier.testTag("host-switcher-pill"),
                        onClick = { hostMenuExpanded = true },
                    )
                    DropdownMenu(
                        expanded = hostMenuExpanded,
                        onDismissRequest = { hostMenuExpanded = false },
                        containerColor = colors.surfacePopover,
                    ) {
                        DropdownMenuItem(
                            text = { Text("All Hosts", color = colors.inkReading) },
                            leadingIcon = {
                                Icon(Icons.Rounded.Hub, contentDescription = null, tint = colors.inkSecondary)
                            },
                            trailingIcon = {
                                if (hostScope is AgentsHostFilterScope.AllHosts) {
                                    Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accentPeriwinkle)
                                }
                            },
                            onClick = {
                                coordinator.selectHostScope(AgentsHostFilterScope.AllHosts)
                                hostMenuExpanded = false
                            },
                        )
                        val macName = connectionState.activeHost?.hostname?.takeIf { it.isNotBlank() } ?: "MacBook Pro"
                        val macId = connectionState.activeHost?.instanceId ?: "host-macbook-pro"
                        DropdownMenuItem(
                            text = { Text(macName, color = colors.inkReading) },
                            leadingIcon = {
                                Icon(Icons.Rounded.Computer, contentDescription = null, tint = colors.statusDone)
                            },
                            trailingIcon = {
                                if (hostScope is AgentsHostFilterScope.LocalHost && hostScope.name == macName) {
                                    Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accentPeriwinkle)
                                }
                            },
                            onClick = {
                                coordinator.selectHostScope(AgentsHostFilterScope.LocalHost(macId, macName))
                                hostMenuExpanded = false
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
                                coordinator.selectHostScope(AgentsHostFilterScope.AntigravityCloud)
                                hostMenuExpanded = false
                            },
                        )
                    }
                }

                Spacer(modifier = Modifier.weight(1f))

                TopBarActionIconButton(
                    icon = Icons.Rounded.FilterList,
                    contentDescription = "Display Options",
                    testTag = "btn-display-options",
                    onClick = onOpenDisplayOptions,
                )

                TopBarActionIconButton(
                    icon = Icons.Rounded.CreateNewFolder,
                    contentDescription = "New Project",
                    testTag = "btn-new-project",
                    onClick = onOpenNewProject,
                )
            }
        }

        // 2. Large Title ("Agents") + Search Bar
        item(key = "home-title-and-search") {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    text = "Agents",
                    style = MaterialTheme.typography.headlineMedium.copy(
                        fontSize = 30.sp,
                        lineHeight = 36.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    color = colors.inkReading,
                    maxLines = 1,
                )

                AgentsSearchField(
                    query = searchQuery,
                    onQueryChange = { searchQuery = it },
                )
            }
        }

        // 3. Horizontal Material 3 FilterChip Strip
        item(key = "home-filter-chips") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AgentsQuickFilterChip(
                    label = "All",
                    selected = selectedFilter == AgentsQuickFilter.ALL,
                    leadingDotColor = null,
                    testTag = "filter-pill-all",
                    onClick = { selectedFilter = AgentsQuickFilter.ALL },
                )
                AgentsQuickFilterChip(
                    label = if (runningCount > 0) "Running $runningCount" else "Running",
                    selected = selectedFilter == AgentsQuickFilter.RUNNING,
                    leadingDotColor = colors.statusRunning,
                    testTag = "filter-pill-running",
                    onClick = { selectedFilter = AgentsQuickFilter.RUNNING },
                )
                AgentsQuickFilterChip(
                    label = if (needsYouCount > 0) "Needs you $needsYouCount" else "Needs you",
                    selected = selectedFilter == AgentsQuickFilter.NEEDS_YOU,
                    leadingDotColor = colors.statusWaiting,
                    testTag = "filter-pill-needs-you",
                    onClick = { selectedFilter = AgentsQuickFilter.NEEDS_YOU },
                )
                AgentsQuickFilterChip(
                    label = if (unreadCount > 0) "Unread $unreadCount" else "Unread",
                    selected = selectedFilter == AgentsQuickFilter.UNREAD,
                    leadingDotColor = null,
                    testTag = "filter-pill-unread",
                    onClick = { selectedFilter = AgentsQuickFilter.UNREAD },
                )
            }
        }

        // 3b. Live Connecting / Auth-Expired Recovery Banner (suppressed in offline ESDD mode)
        if (!coordinator.isVerificationMode && (connectionState.isConnecting || !connectionState.errorText.isNullOrBlank())) {
            item(key = "home-live-connection-status") {
                if (connectionState.isConnecting) {
                    AntigravitySurfaceCard(
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("home-connecting-banner"),
                        borderColor = colors.accentPeriwinkle.copy(alpha = 0.4f),
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = colors.accentPeriwinkle,
                            )
                            Text(
                                text = connectionState.statusText.ifBlank { "Connecting to $hostDisplayName..." },
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.inkReading,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(
                                onClick = { coordinator.cancelPendingConnectionAttempt() },
                                modifier = Modifier.testTag("btn-home-cancel-connecting"),
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
                            ) {
                                Text("Cancel", color = colors.accentPeriwinkle)
                            }
                        }
                    }
                } else {
                    val err = connectionState.errorText.orEmpty()
                    AntigravitySurfaceCard(
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("home-connection-error-banner"),
                        containerColor = colors.surfaceAmberTint,
                        borderColor = colors.statusWaiting.copy(alpha = 0.45f),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Warning,
                                contentDescription = null,
                                tint = colors.statusWaiting,
                                modifier = Modifier.size(18.dp),
                            )
                            Text(
                                text = err,
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.inkReading,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(
                                onClick = onOpenReSignIn,
                                modifier = Modifier.testTag("btn-home-resign-in"),
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
                            ) {
                                Text("Sign In", color = colors.statusWaiting)
                            }
                        }
                    }
                }
            }
        }

        // 4. PINNED Section
        if (pinnedSummaries.isNotEmpty()) {
            item(key = "home-pinned-section") {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.padding(start = 2.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.PushPin,
                            contentDescription = null,
                            tint = colors.inkMuted,
                            modifier = Modifier.size(13.dp),
                        )
                        Text(
                            text = "PINNED",
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontFamily = FontFamily.SansSerif,
                                fontWeight = FontWeight.SemiBold,
                                letterSpacing = 0.9.sp,
                            ),
                            color = colors.inkMuted,
                        )
                    }

                    AntigravitySurfaceCard(
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("pinned-section-card"),
                        contentPadding = PaddingValues(0.dp),
                    ) {
                        pinnedSummaries.forEachIndexed { index, summary ->
                            ConversationSummaryRow(
                                summary = summary,
                                showProjectSlug = true,
                                onClick = { onOpenConversation(summary.cascadeId) },
                                onLongClick = { onLongPressConversation(summary.cascadeId) },
                            )
                            if (index < pinnedSummaries.lastIndex) {
                                HorizontalDivider(
                                    modifier = Modifier.padding(start = 42.dp),
                                    thickness = 1.dp,
                                    color = colors.subtleDivider,
                                )
                            }
                        }
                    }
                }
            }
        }

        // 5. Collapsible Project Groups (or flat list when Group By == NONE)
        if (displayOptions.groupBy == DisplayGroupBy.NONE) {
            if (unpinnedSummaries.isNotEmpty()) {
                item(key = "home-flat-conversations") {
                    AntigravitySurfaceCard(
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(0.dp),
                    ) {
                        unpinnedSummaries.forEachIndexed { index, summary ->
                            ConversationSummaryRow(
                                summary = summary,
                                showProjectSlug = true,
                                onClick = { onOpenConversation(summary.cascadeId) },
                                onLongClick = { onLongPressConversation(summary.cascadeId) },
                            )
                            if (index < unpinnedSummaries.lastIndex) {
                                HorizontalDivider(
                                    modifier = Modifier.padding(start = 42.dp),
                                    thickness = 1.dp,
                                    color = colors.subtleDivider,
                                )
                            }
                        }
                    }
                }
            }
        } else {
            items(
                items = projectGroups,
                key = { (project, _) -> "project-${project.id}" },
            ) { (project, conversations) ->
                val isCollapsed = project.id in collapsedProjectIds
                ProjectConversationGroup(
                    project = project,
                    conversations = conversations,
                    isHostOnline = isHostOnline,
                    isCollapsed = isCollapsed,
                    onToggleCollapse = {
                        coordinator.workspaceStore.toggleProjectExpanded(project.id)
                    },
                    onOpenProjectDetail = { onOpenProjectDetail(project.id) },
                    onNewConversationInProject = { onOpenConversation("new-${project.id}") },
                    onOpenConversation = onOpenConversation,
                    onLongPressConversation = onLongPressConversation,
                )
            }
        }

        // 6. Empty State when filter or search yields no conversations
        if (pinnedSummaries.isEmpty() && projectGroups.isEmpty()) {
            item(key = "home-empty-state") {
                AntigravitySurfaceCard(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(20.dp),
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = if (searchQuery.isNotBlank()) "No matching conversations" else "No conversations here",
                            style = MaterialTheme.typography.titleMedium,
                            color = colors.inkReading,
                        )
                        Text(
                            text = "Adjust your filter or start a fresh agent session.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.inkSecondary,
                        )
                        TextButton(onClick = onTapComposeFab) {
                            Text("Start New Conversation", color = colors.accentPeriwinkle)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TopBarActionIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    testTag: String,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    Surface(
        onClick = onClick,
        modifier = Modifier
            .size(AntigravityDesignTokens.MinTouchTarget)
            .testTag(testTag),
        shape = CircleShape,
        color = colors.surfacePill,
        border = BorderStroke(1.dp, colors.cardBorder),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                imageVector = icon,
                contentDescription = contentDescription,
                tint = colors.inkReading,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
private fun AgentsSearchField(
    query: String,
    onQueryChange: (String) -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget),
        shape = RoundedCornerShape(16.dp),
        color = colors.surfaceCard,
        border = BorderStroke(1.dp, colors.cardBorder),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.Search,
                contentDescription = null,
                tint = colors.inkMuted,
                modifier = Modifier.size(19.dp),
            )
            Box(
                modifier = Modifier.weight(1f),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (query.isEmpty()) {
                    Text(
                        text = "Search conversations",
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                        color = colors.inkMuted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                BasicTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                        fontSize = 15.sp,
                        color = colors.inkReading,
                    ),
                    cursorBrush = SolidColor(colors.accentPeriwinkle),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("agents-search-input"),
                )
            }
            if (query.isNotEmpty()) {
                IconButton(
                    onClick = { onQueryChange("") },
                    modifier = Modifier.size(32.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Close,
                        contentDescription = "Clear search",
                        tint = colors.inkSecondary,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun AgentsQuickFilterChip(
    label: String,
    selected: Boolean,
    leadingDotColor: Color?,
    testTag: String,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    FilterChip(
        selected = selected,
        onClick = onClick,
        modifier = Modifier
            .defaultMinSize(minHeight = 40.dp)
            .testTag(testTag),
        shape = RoundedCornerShape(AntigravityDesignTokens.PillCornerRadius),
        label = {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 1,
                softWrap = false,
            )
        },
        leadingIcon = if (leadingDotColor != null) {
            {
                StatusDot(
                    color = if (selected) colors.pillActiveForeground else leadingDotColor,
                    size = 7.dp,
                )
            }
        } else {
            null
        },
        colors = FilterChipDefaults.filterChipColors(
            containerColor = colors.surfacePill,
            labelColor = colors.inkLabel,
            selectedContainerColor = colors.pillActiveBackground,
            selectedLabelColor = colors.pillActiveForeground,
        ),
        border = FilterChipDefaults.filterChipBorder(
            enabled = true,
            selected = selected,
            borderColor = colors.cardBorder,
            selectedBorderColor = Color.Transparent,
            borderWidth = 1.dp,
        ),
    )
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ProjectConversationGroup(
    project: ProjectWorkspace,
    conversations: List<CascadeSummary>,
    isHostOnline: Boolean,
    isCollapsed: Boolean,
    onToggleCollapse: () -> Unit,
    onOpenProjectDetail: () -> Unit,
    onNewConversationInProject: () -> Unit,
    onOpenConversation: (String) -> Unit,
    onLongPressConversation: (String) -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    val isCloud = project.runtime == ProjectRuntimeTarget.CLOUD

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("project-group-${project.id}"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Project Group Header Row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(12.dp))
                    .combinedClickable(
                        role = Role.Button,
                        onClick = onOpenProjectDetail,
                    )
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Surface(
                    modifier = Modifier.size(36.dp),
                    shape = RoundedCornerShape(10.dp),
                    color = colors.surfacePill,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = if (isCloud) Icons.Rounded.Cloud else Icons.Rounded.Folder,
                            contentDescription = null,
                            tint = colors.inkLabel,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = project.name,
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = project.homeSubtitle(isHostOnline = isHostOnline),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            IconButton(
                onClick = onNewConversationInProject,
                modifier = Modifier.size(AntigravityDesignTokens.MinTouchTarget),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Add,
                    contentDescription = "New conversation in ${project.name}",
                    tint = colors.inkLabel,
                    modifier = Modifier.size(20.dp),
                )
            }

            IconButton(
                onClick = onToggleCollapse,
                modifier = Modifier.size(AntigravityDesignTokens.MinTouchTarget),
            ) {
                Icon(
                    imageVector = if (isCollapsed) Icons.Rounded.ExpandMore else Icons.Rounded.ExpandLess,
                    contentDescription = if (isCollapsed) "Expand ${project.name}" else "Collapse ${project.name}",
                    tint = colors.inkSecondary,
                    modifier = Modifier.size(20.dp),
                )
            }
        }

        // Grouped Conversations Card
        if (!isCollapsed && conversations.isNotEmpty()) {
            AntigravitySurfaceCard(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(0.dp),
            ) {
                conversations.forEachIndexed { index, summary ->
                    ConversationSummaryRow(
                        summary = summary,
                        showProjectSlug = false,
                        onClick = { onOpenConversation(summary.cascadeId) },
                        onLongClick = { onLongPressConversation(summary.cascadeId) },
                    )
                    if (index < conversations.lastIndex) {
                        HorizontalDivider(
                            modifier = Modifier.padding(start = 42.dp),
                            thickness = 1.dp,
                            color = colors.subtleDivider,
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun ConversationSummaryRow(
    summary: CascadeSummary,
    showProjectSlug: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier,
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
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 58.dp)
            .combinedClickable(
                onClick = onClick,
                onLongClick = onLongClick,
            )
            .padding(horizontal = 14.dp, vertical = 12.dp),
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
                isRunning -> RunningProgressArc(color = colors.statusRunning, trackColor = colors.ringTrack)
                isWaiting -> StatusDot(color = colors.statusWaiting, size = 8.dp, glow = true)
                summary.isUnread -> StatusDot(color = colors.statusRunning, size = 8.dp, glow = false)
                else -> Spacer(modifier = Modifier.size(8.dp))
            }
        }

        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = summary.title,
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontSize = 15.5.sp,
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
                    softWrap = false,
                )
            }

            val subtitleText = buildAnnotatedString {
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
                text = subtitleText,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            if (showProjectSlug && summary.projectSlug.isNotBlank()) {
                Text(
                    text = summary.projectSlug,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkMuted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
internal fun RunningProgressArc(
    color: Color,
    trackColor: Color,
    size: Dp = 15.dp,
    strokeWidth: Dp = 2.dp,
) {
    Canvas(modifier = Modifier.size(size)) {
        val stroke = Stroke(width = strokeWidth.toPx(), cap = StrokeCap.Round)
        drawArc(
            color = trackColor,
            startAngle = 0f,
            sweepAngle = 360f,
            useCenter = false,
            style = stroke,
        )
        drawArc(
            color = color,
            startAngle = -90f,
            sweepAngle = 215f,
            useCenter = false,
            style = stroke,
        )
    }
}
