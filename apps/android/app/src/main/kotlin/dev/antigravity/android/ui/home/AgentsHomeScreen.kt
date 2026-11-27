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
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.WorkOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.android.ui.chat.ComposerAttachmentsStrip
import dev.antigravity.android.ui.chat.VoiceLanguageDropdownMenu
import dev.antigravity.android.ui.chat.VoiceListeningLanguageBar
import dev.antigravity.android.ui.chat.formatComposerModelPillName
import dev.antigravity.android.ui.chat.rememberVoiceDictationController
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AgentsHostFilterScope
import dev.antigravity.shared.model.AntigravityCloudDetector
import dev.antigravity.shared.model.AppLocalizationFormatter
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.ConversationSortField
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.model.UserGreetingFormatter
import dev.antigravity.shared.model.localizedTitle
import dev.antigravity.shared.protocol.ConnectionLifecyclePhase
import kotlinx.coroutines.CancellationException
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
    onOpenPermissionsPreset: (Boolean) -> Unit = {},
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
    val lang = LocalAppLanguage.current
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
    var selectedBranchLabel by rememberSaveable { mutableStateOf("Repo default") }

    val hostScope = connectionState.selectedHostScope
    val pairedLocalHosts = remember(connectionState.knownHosts) {
        connectionState.knownHosts
            .filter { it.instanceId != "unpaired" && !it.hostname.equals("cloud", ignoreCase = true) }
            .distinctBy { it.instanceId }
    }

    val allProjects = remember(
        workspaceState.projects,
        syncState.projects,
        hostScope,
        connectionState.knownHosts,
        connectionState.activeHost,
    ) {
        (workspaceState.projects + syncState.projects)
            .distinctBy { it.id }
            .filter { project ->
                !project.isNoProject && coordinator.projectMatchesHostScope(project, hostScope)
            }
    }
    val selectedProject = remember(allProjects, workspaceState.selectedProjectId, hostScope) {
        allProjects.firstOrNull { it.id == workspaceState.selectedProjectId }
            ?: when (hostScope) {
                AgentsHostFilterScope.AntigravityCloud ->
                    allProjects.firstOrNull { it.runtime == ProjectRuntimeTarget.CLOUD }
                        ?: allProjects.firstOrNull()
                else ->
                    allProjects.firstOrNull { it.runtime != ProjectRuntimeTarget.CLOUD }
                        ?: allProjects.firstOrNull()
            }
    }
    val selectedProjectName = selectedProject?.name ?: when {
        !coordinator.isVerificationMode && syncState.isRefreshing -> tr("Loading...", "加载中…")
        !coordinator.isVerificationMode -> tr(AntigravityCloudDetector.NO_PROJECT_DISPLAY_NAME, "未选项目")
        else -> "ledger-svc"
    }
    var cloudModeEnabled by rememberSaveable {
        mutableStateOf(
            selectedProject?.let { it.runtime == ProjectRuntimeTarget.CLOUD }
                ?: (hostScope is AgentsHostFilterScope.AntigravityCloud),
        )
    }
    LaunchedEffect(selectedProject?.id, selectedProject?.runtime, hostScope) {
        val targetProject = selectedProject
        if (targetProject != null) {
            cloudModeEnabled = targetProject.runtime == ProjectRuntimeTarget.CLOUD
            if (workspaceState.selectedProjectId != targetProject.id) {
                coordinator.workspaceStore.selectProject(targetProject.id)
            }
        } else {
            cloudModeEnabled = hostScope is AgentsHostFilterScope.AntigravityCloud
        }
    }

    val isConnectingToHost = !coordinator.isVerificationMode &&
        connectionState.hasPairedBackend &&
        connectionState.isDeviceNetworkReachable &&
        !connectionState.isConnected &&
        (connectionState.isConnecting || connectionState.lifecyclePhase is ConnectionLifecyclePhase.Connecting)

    val isHostOnline = remember(hostScope, connectionState) {
        connectionState.isHostScopeOnline(hostScope)
    }

    val hostDisplayName = remember(hostScope, connectionState, pairedLocalHosts, isHostOnline, isConnectingToHost, lang, coordinator.isVerificationMode) {
        if (!coordinator.isVerificationMode && connectionState.hasPairedBackend && !connectionState.isDeviceNetworkReachable) {
            return@remember lang.t("No Network", "无网络")
        }
        when (hostScope) {
            AgentsHostFilterScope.AntigravityCloud -> lang.t("Cloud", "云端")
            is AgentsHostFilterScope.LocalHost -> {
                val baseName = hostScope.name.ifBlank { "MacBook Pro" }
                if (!coordinator.isVerificationMode && connectionState.hasPairedBackend && !isConnectingToHost && !isHostOnline) {
                    lang.t("$baseName · Offline", "$baseName · 离线")
                } else {
                    baseName
                }
            }
            AgentsHostFilterScope.AllHosts -> {
                if (coordinator.isVerificationMode) {
                    connectionState.activeHost?.hostname?.takeIf { it.isNotBlank() } ?: "MacBook Pro"
                } else if (connectionState.hasPairedBackend) {
                    if (pairedLocalHosts.size > 1) {
                        if (isConnectingToHost || isHostOnline) {
                            lang.t("All Hosts", "全部主机")
                        } else {
                            lang.t("All Hosts · Offline", "全部主机 · 离线")
                        }
                    } else {
                        val activeName = connectionState.activeHost?.hostname?.takeIf { it.isNotBlank() } ?: "MacBook Pro"
                        if (isConnectingToHost || isHostOnline) {
                            activeName
                        } else {
                            lang.t("$activeName · Offline", "$activeName · 离线")
                        }
                    }
                } else {
                    "MacBook Pro"
                }
            }
        }
    }

    val hostDotColor = when (hostScope) {
        AgentsHostFilterScope.AntigravityCloud -> if (isHostOnline) colors.accentPeriwinkle else colors.statusError
        else -> if (isHostOnline) colors.statusDone else colors.statusError
    }

    val scopedSummaries = remember(
        syncState.summaries,
        hostScope,
        connectionState.knownHosts,
        connectionState.activeHost,
    ) {
        syncState.summaries.filter { coordinator.summaryMatchesHostScope(it, hostScope) }
    }

    val needsApprovalSummary = remember(scopedSummaries, coordinator.isVerificationMode) {
        scopedSummaries.firstOrNull {
            !it.isArchived && (it.pendingInteractionTitle != null || it.status == CortexStepStatus.WAITING || it.status == CortexStepStatus.BLOCKED)
        } ?: if (coordinator.isVerificationMode) {
            scopedSummaries.firstOrNull { it.cascadeId == "cas-rate-limiter" }
        } else {
            null
        }
    }

    val voiceController = rememberVoiceDictationController()
    val selectedModelName = formatComposerModelPillName(settingsState.selectedModel?.displayName)
    val activePermissionPreset = settingsState.permissionPresetFor(isRemote = cloudModeEnabled)
    val permissionLabel = activePermissionPreset.localizedTitle(lang)

    fun submitHomePrompt() {
        voiceController.stopRecording()
        val text = draftText.trim()
        val attachments = workspaceState.attachedComposerChips
        if (text.isEmpty() && attachments.isEmpty()) return
        if (coordinator.isVerificationMode) {
            coordinator.chatStore.setActiveCascade("cas-rate-limiter")
            scope.launch {
                coordinator.sendMessage(
                    cascadeId = "cas-rate-limiter",
                    message = text,
                    attachments = attachments,
                    modelId = settingsState.selectedModelId,
                    effort = settingsState.selectedEffort,
                    mode = settingsState.selectedMode,
                    agentPersona = settingsState.selectedAgentPersona,
                    isCloud = cloudModeEnabled,
                    permissionPreset = activePermissionPreset,
                    isOptimisticDraft = false,
                )
            }
            draftText = ""
            coordinator.workspaceStore.clearComposerChips()
            onOpenConversation("cas-rate-limiter")
            return
        }
        val titleCandidate = text.take(48).ifBlank { attachments.firstOrNull()?.label ?: "New Conversation" }
        val draftId = coordinator.createLocalDraftConversation(
            workspaceUri = selectedProject?.workspaceUri.orEmpty(),
            projectSlug = selectedProject?.id.orEmpty(),
            title = titleCandidate,
            isCloud = cloudModeEnabled,
            cloudProjectId = selectedProject?.cloudProjectId,
            originInstanceUuid = selectedProject?.originInstanceUuid,
            originHostName = if (cloudModeEnabled) "Antigravity" else selectedProject?.hostName,
            branchName = selectedProject?.activeBranch,
        )
        scope.launch {
            runCatching {
                coordinator.sendMessage(
                    cascadeId = draftId,
                    message = text,
                    workspaceUri = selectedProject?.workspaceUri.orEmpty(),
                    attachments = attachments,
                    modelId = settingsState.selectedModelId,
                    effort = settingsState.selectedEffort,
                    mode = settingsState.selectedMode,
                    agentPersona = settingsState.selectedAgentPersona,
                    isCloud = cloudModeEnabled,
                    cloudProjectId = selectedProject?.cloudProjectId,
                    permissionPreset = activePermissionPreset,
                    instanceUuidOverride = selectedProject?.originInstanceUuid,
                    isOptimisticDraft = true,
                )
            }
        }
        draftText = ""
        coordinator.workspaceStore.clearComposerChips()
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
            // Top bar: Hamburger · Bounded Centered Host Pill · Search
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
                        contentDescription = tr("Open sidebar", "打开侧边栏"),
                        tint = colors.inkReading,
                        modifier = Modifier.size(24.dp),
                    )
                }

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 8.dp),
                    contentAlignment = Alignment.Center,
                ) {
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
                                if (isConnectingToHost) {
                                    CircularProgressIndicator(
                                        strokeWidth = 1.8.dp,
                                        color = colors.accentPeriwinkle,
                                        modifier = Modifier.size(10.dp),
                                    )
                                } else {
                                    StatusDot(
                                        color = hostDotColor,
                                        size = 8.dp,
                                        glow = false,
                                    )
                                }
                                Text(
                                    text = hostDisplayName,
                                    style = MaterialTheme.typography.labelLarge.copy(
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Medium,
                                    ),
                                    color = colors.inkReading,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.weight(1f, fill = false),
                                )
                                if (showHostChevron) {
                                    Icon(
                                        imageVector = Icons.Rounded.KeyboardArrowDown,
                                        contentDescription = tr("Switch host", "切换主机"),
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
                            if (!coordinator.isVerificationMode && connectionState.hasPairedBackend) {
                                DropdownMenuItem(
                                    text = {
                                        Text(
                                            text = if (isHostOnline) {
                                                tr("Sync Now", "立即同步")
                                            } else {
                                                tr("Reconnect Now", "立即重连")
                                            },
                                            color = colors.accentPeriwinkle,
                                            fontWeight = FontWeight.Medium,
                                        )
                                    },
                                    leadingIcon = {
                                        Icon(
                                            imageVector = Icons.Rounded.Refresh,
                                            contentDescription = null,
                                            tint = colors.accentPeriwinkle,
                                        )
                                    },
                                    onClick = {
                                        hostMenuExpanded = false
                                        scope.launch {
                                            try {
                                                if (isHostOnline) {
                                                    coordinator.refreshAvailableRelayHosts(verifyEndToEnd = true)
                                                    coordinator.refreshWorkspacesAndSummaries(skipRelayListRefresh = true)
                                                } else {
                                                    coordinator.reconnectNow()
                                                }
                                            } catch (e: CancellationException) {
                                                throw e
                                            } catch (_: Throwable) {
                                                // Error state is reflected in connectionState.
                                            }
                                        }
                                    },
                                    modifier = Modifier.testTag("host-option-sync-now"),
                                )
                                HorizontalDivider(color = colors.cardBorder.copy(alpha = 0.6f))
                            }
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        tr("All Hosts (Cloud & Local)", "所有主机（云端与本地）"),
                                        color = colors.inkReading,
                                    )
                                },
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
                                    coordinator.selectHostScope(AgentsHostFilterScope.AllHosts)
                                },
                                modifier = Modifier.testTag("host-option-all"),
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        tr("Antigravity (Cloud)", "Antigravity（云端）"),
                                        color = colors.inkReading,
                                    )
                                },
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
                                    coordinator.selectHostScope(AgentsHostFilterScope.AntigravityCloud)
                                },
                                modifier = Modifier.testTag("host-option-cloud"),
                            )
                            pairedLocalHosts.forEach { host ->
                                val isSelectedHost = hostScope is AgentsHostFilterScope.LocalHost &&
                                    (hostScope.id == host.instanceId || hostScope.name == host.hostname)
                                val hostOnline = connectionState.isLocalHostOnline(host.instanceId, host.hostname)
                                DropdownMenuItem(
                                    text = {
                                        Column {
                                            Text(
                                                host.hostname,
                                                color = colors.inkReading,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                            val stateLabel = if (hostOnline) tr("Online", "在线") else tr("Offline", "离线")
                                            Text(
                                                text = "$stateLabel · ${host.version}",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = if (hostOnline) colors.statusDone else colors.statusError,
                                            )
                                        }
                                    },
                                    leadingIcon = {
                                        Icon(
                                            imageVector = Icons.Rounded.Computer,
                                            contentDescription = null,
                                            tint = if (hostOnline) colors.inkSecondary else colors.inkMuted,
                                        )
                                    },
                                    trailingIcon = {
                                        if (isSelectedHost) {
                                            Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accentPeriwinkle)
                                        }
                                    },
                                    onClick = {
                                        hostMenuExpanded = false
                                        coordinator.selectHostScope(
                                            AgentsHostFilterScope.LocalHost(host.instanceId, host.hostname),
                                        )
                                    },
                                    modifier = Modifier.testTag("host-option-${host.instanceId}"),
                                )
                            }
                        }
                    }
                }

                if (showSearchAction) {
                    IconButton(
                        onClick = { isSearchOpen = !isSearchOpen },
                        modifier = Modifier
                            .size(AntigravityDesignTokens.MinTouchTarget)
                            .testTag("btn-search"),
                    ) {
                        Icon(
                            imageVector = if (isSearchOpen) Icons.Rounded.Close else Icons.Rounded.Search,
                            contentDescription = tr("Search conversations", "搜索会话"),
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
                    coordinator = coordinator,
                    query = searchQuery,
                    onQueryChange = { searchQuery = it },
                    summaries = scopedSummaries,
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
                        val greetingDisplayName = if (coordinator.isVerificationMode) {
                            connectionState.userDisplayName ?: "Alex"
                        } else {
                            connectionState.userDisplayName
                        }
                        val heroGreetingText = remember(greetingDisplayName, lang) {
                            UserGreetingFormatter.homeHeroGreeting(greetingDisplayName, language = lang)
                        }
                        Text(
                            text = heroGreetingText,
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
                    val needsApprovalText = tr("Needs approval", "等待审批")
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
                                        append(needsApprovalText)
                                    }
                                    withStyle(SpanStyle(color = colors.inkSecondary)) {
                                        append(" · ")
                                    }
                                    withStyle(SpanStyle(color = colors.inkReading)) {
                                        append(coordinator.displayTitleForSummary(needsApprovalSummary))
                                    }
                                },
                                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f),
                            )
                            Icon(
                                imageVector = Icons.Rounded.ChevronRight,
                                contentDescription = tr("Open approval", "打开审批"),
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
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Row(
                                modifier = Modifier.weight(1f),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(14.dp),
                            ) {
                                Box(modifier = Modifier.weight(1f, fill = false)) {
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
                                            imageVector = if (cloudModeEnabled) Icons.Rounded.Cloud else Icons.Rounded.Folder,
                                            contentDescription = null,
                                            tint = colors.inkSecondary,
                                            modifier = Modifier.size(16.dp),
                                        )
                                        Text(
                                            text = selectedProjectName,
                                            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                                            color = colors.inkLabel,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                            modifier = Modifier.weight(1f, fill = false),
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
                                        if (allProjects.isEmpty() && !coordinator.isVerificationMode) {
                                            DropdownMenuItem(
                                                text = {
                                                    Text(
                                                        text = if (syncState.isRefreshing) {
                                                            tr("Syncing repositories...", "正在同步仓库…")
                                                        } else {
                                                            tr(
                                                                "No repositories on $hostDisplayName",
                                                                "$hostDisplayName 上暂无仓库",
                                                            )
                                                        },
                                                        color = colors.inkSecondary,
                                                    )
                                                },
                                                enabled = false,
                                                onClick = {},
                                            )
                                            DropdownMenuItem(
                                                text = { Text(tr("Sync Repositories", "同步仓库"), color = colors.inkReading) },
                                                leadingIcon = {
                                                    Icon(Icons.Rounded.Refresh, contentDescription = null, tint = colors.accentPeriwinkle)
                                                },
                                                onClick = {
                                                    projectMenuExpanded = false
                                                    scope.launch {
                                                        try {
                                                            coordinator.refreshWorkspacesAndSummaries(
                                                                hostScope = hostScope,
                                                                skipRelayListRefresh = false,
                                                            )
                                                        } catch (e: CancellationException) {
                                                            throw e
                                                        } catch (_: Throwable) {
                                                            // Best-effort manual refresh; error state is tracked in syncStore.
                                                        }
                                                    }
                                                },
                                            )
                                        } else {
                                            allProjects.forEach { project ->
                                                DropdownMenuItem(
                                                    text = {
                                                        Text(
                                                            project.name,
                                                            color = colors.inkReading,
                                                            maxLines = 1,
                                                            overflow = TextOverflow.Ellipsis,
                                                        )
                                                    },
                                                    trailingIcon = {
                                                        if (project.id == selectedProject?.id) {
                                                            Icon(
                                                                Icons.Rounded.Check,
                                                                contentDescription = null,
                                                                tint = colors.accentPeriwinkle,
                                                            )
                                                        }
                                                    },
                                                    onClick = {
                                                        projectMenuExpanded = false
                                                        coordinator.workspaceStore.selectProject(project.id)
                                                        cloudModeEnabled = project.runtime == ProjectRuntimeTarget.CLOUD
                                                    },
                                                    modifier = Modifier.testTag("home-project-option-${project.id}"),
                                                )
                                            }
                                        }
                                    }
                                }

                                Box {
                                    val localizedBranchLabel = when (selectedBranchLabel) {
                                        "Repo default" -> tr("Repo default", "仓库默认")
                                        "New worktree" -> tr("New worktree", "新建工作树")
                                        else -> selectedBranchLabel
                                    }
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
                                            text = localizedBranchLabel,
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
                                        listOf(
                                            "Repo default" to tr("Repo default", "仓库默认"),
                                            "main" to "main",
                                            "New worktree" to tr("New worktree", "新建工作树"),
                                        ).forEach { (branchKey, branchDisplay) ->
                                            DropdownMenuItem(
                                                text = { Text(branchDisplay, color = colors.inkReading) },
                                                onClick = {
                                                    branchMenuExpanded = false
                                                    selectedBranchLabel = branchKey
                                                },
                                            )
                                        }
                                    }
                                }
                            }

                            Icon(
                                imageVector = if (cloudModeEnabled) Icons.Rounded.Cloud else Icons.Rounded.Computer,
                                contentDescription = if (cloudModeEnabled) {
                                    tr("Cloud runtime selected", "已选择云端运行环境")
                                } else {
                                    tr("Local runtime selected", "已选择本地运行环境")
                                },
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
                                if (workspaceState.attachedComposerChips.isNotEmpty()) {
                                    ComposerAttachmentsStrip(
                                        chips = workspaceState.attachedComposerChips,
                                        onRemoveChip = { coordinator.workspaceStore.removeComposerChip(it) },
                                    )
                                }

                                val placeholderCopy = tr(
                                    "Ask anything, @ to mention, / for actions",
                                    "随便问点什么，输入 @ 引用，/ 调用指令",
                                )

                                VoiceListeningLanguageBar(
                                    controller = voiceController,
                                    existingDraft = draftText,
                                    onDraftUpdated = { draftText = it },
                                )

                                voiceController.errorMessage?.let { voiceErr ->
                                    Text(
                                        text = voiceErr,
                                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp),
                                        color = colors.statusWaiting,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable { voiceController.clearError() }
                                            .testTag("home-voice-error"),
                                    )
                                }

                                BasicTextField(
                                    value = draftText,
                                    onValueChange = { updated ->
                                        draftText = updated
                                        if (updated.isNotEmpty() && !voiceController.isRecording && voiceController.errorMessage != null) {
                                            voiceController.clearError()
                                        }
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
                                                text = placeholderCopy,
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
                                                contentDescription = tr("Add context", "添加上下文"),
                                                tint = colors.inkReading,
                                                modifier = Modifier.size(22.dp),
                                            )
                                        }
                                    }

                                    // Single-line model selector (`Gemini 4 Neon ⌄`); thinking effort shown inside sheet
                                    Row(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(10.dp))
                                            .clickable(onClick = onOpenModelPicker)
                                            .padding(horizontal = 4.dp, vertical = 6.dp)
                                            .testTag("btn-model-picker"),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                                    ) {
                                        Text(
                                            text = selectedModelName,
                                            style = MaterialTheme.typography.labelMedium.copy(
                                                fontSize = 13.5.sp,
                                                fontWeight = FontWeight.Medium,
                                            ),
                                            color = colors.inkReading,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                        Icon(
                                            imageVector = Icons.Rounded.KeyboardArrowDown,
                                            contentDescription = tr("Select model", "选择模型"),
                                            tint = colors.inkSecondary,
                                            modifier = Modifier.size(16.dp),
                                        )
                                    }

                                    // Permissions preset pill (`🛡 Default ⌄`)
                                    Surface(
                                        onClick = { onOpenPermissionsPreset(cloudModeEnabled) },
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
                                                contentDescription = tr("Permissions", "权限"),
                                                tint = colors.inkSecondary,
                                                modifier = Modifier.size(16.dp),
                                            )
                                        }
                                    }

                                    Spacer(modifier = Modifier.weight(1f))

                                    val homeVoiceContextHint = remember(draftText, scopedSummaries) {
                                        buildList {
                                            draftText.trim().takeIf { it.isNotEmpty() }?.let(::add)
                                            scopedSummaries.take(3)
                                                .map { it.title.trim() }
                                                .filter { it.isNotEmpty() && it != "New Conversation" }
                                                .forEach(::add)
                                        }.joinToString(" ").ifBlank { null }
                                    }

                                    var homeVoiceMenuExpanded by remember { mutableStateOf(false) }
                                    Box {
                                        Box(
                                            modifier = Modifier
                                                .size(34.dp)
                                                .clip(CircleShape)
                                                .combinedClickable(
                                                    onClick = {
                                                        voiceController.toggleRecording(
                                                            existingDraft = draftText,
                                                            appLanguage = lang,
                                                            contextTextHint = homeVoiceContextHint,
                                                        ) { updated ->
                                                            draftText = updated
                                                        }
                                                    },
                                                    onLongClick = { homeVoiceMenuExpanded = true },
                                                )
                                                .testTag("btn-voice-mode"),
                                            contentAlignment = Alignment.Center,
                                        ) {
                                            Icon(
                                                imageVector = if (voiceController.isRecording) Icons.Rounded.Stop else Icons.Rounded.Mic,
                                                contentDescription = if (voiceController.isRecording) tr("Stop dictation", "停止听写") else tr("Dictate message", "语音听写"),
                                                tint = when {
                                                    voiceController.isRecording -> colors.statusError
                                                    voiceController.isStarting -> colors.accentPeriwinkle
                                                    else -> colors.inkLabel
                                                },
                                                modifier = Modifier.size(if (voiceController.isRecording) 17.dp else 20.dp),
                                            )
                                        }
                                        VoiceLanguageDropdownMenu(
                                            expanded = homeVoiceMenuExpanded,
                                            selectedLanguage = voiceController.preferredLanguage,
                                            onDismiss = { homeVoiceMenuExpanded = false },
                                            onSelect = { chosen ->
                                                homeVoiceMenuExpanded = false
                                                voiceController.selectLanguage(
                                                    language = chosen,
                                                    appLanguage = lang,
                                                    existingDraft = draftText,
                                                    contextTextHint = homeVoiceContextHint,
                                                    onDraftUpdated = { draftText = it },
                                                )
                                            },
                                        )
                                    }

                                    val canSend = draftText.isNotBlank() || workspaceState.attachedComposerChips.isNotEmpty()
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
                                                contentDescription = tr("Send", "发送"),
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
    coordinator: AntigravityCoreCoordinator,
    query: String,
    onQueryChange: (String) -> Unit,
    summaries: List<CascadeSummary>,
    onSelectConversation: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val lang = LocalAppLanguage.current
    val filtered = remember(summaries, query) {
        val q = query.trim().lowercase()
        summaries.filter { !it.isArchived }.filter { s ->
            q.isEmpty() ||
                coordinator.displayTitleForSummary(s).lowercase().contains(q) ||
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
                val searchPlaceholder = tr("Search conversations, projects...", "搜索会话、项目…")
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
                            Text(searchPlaceholder, color = colors.inkMuted)
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
                val isTitleLoading = coordinator.isSummaryTitleLoading(item)
                val displayTitle = coordinator.displayTitleForSummary(item)
                LaunchedEffect(item.cascadeId, item.hasResolvedTitle) {
                    if (!coordinator.isVerificationMode) {
                        coordinator.prioritizeConversationPreload(item.cascadeId)
                    }
                }
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
                            if (isTitleLoading) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    CircularProgressIndicator(
                                        strokeWidth = 1.8.dp,
                                        color = colors.inkMuted,
                                        modifier = Modifier.size(13.dp),
                                    )
                                    Text(
                                        text = tr("Loading...", "加载中…"),
                                        color = colors.inkMuted,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            } else {
                                Text(displayTitle, color = colors.inkReading, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            Text(
                                "${item.projectSlug} · ${item.statusSubtitle}",
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.inkSecondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Text(
                            AppLocalizationFormatter.localizeRelativeTime(item.relativeTimeLabel, lang),
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.inkMuted,
                        )
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
    onSelectProject: (String) -> Unit = {},
    onOpenProjectCustomizations: (projectId: String, projectName: String) -> Unit = { _, _ -> },
    onRevealProjectInFinder: (String) -> Unit = {},
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
                onSelectProject = onSelectProject,
                onOpenProjectCustomizations = onOpenProjectCustomizations,
                onRevealProjectInFinder = onRevealProjectInFinder,
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
    onSelectProject: (String) -> Unit = {},
    onOpenProjectCustomizations: (projectId: String, projectName: String) -> Unit = { _, _ -> },
    onRevealProjectInFinder: (String) -> Unit = {},
    onOpenConversation: (String) -> Unit,
    onLongPressConversation: (String) -> Unit,
    onOpenSettings: () -> Unit,
    activeHighlightCascadeId: String = "cas-rate-limiter",
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val connectionState by coordinator.connectionState.collectAsStateWithLifecycle()
    val syncState by coordinator.syncState.collectAsStateWithLifecycle()
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val displayOptions = workspaceState.displayOptions
    val hostScope = connectionState.selectedHostScope

    val allProjects = remember(
        workspaceState.projects,
        syncState.projects,
        hostScope,
        connectionState.knownHosts,
        connectionState.activeHost,
    ) {
        (workspaceState.projects + syncState.projects)
            .distinctBy { it.id }
            .filter { coordinator.projectMatchesHostScope(it, hostScope) }
    }

    val visibleSummaries = remember(
        syncState.summaries,
        displayOptions,
        hostScope,
        connectionState.knownHosts,
        connectionState.activeHost,
    ) {
        val filtered = syncState.summaries
            .distinctBy { it.cascadeId }
            .filter { s ->
                coordinator.summaryMatchesHostScope(s, hostScope) &&
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
                    text = tr("New Conversation", "新建会话"),
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
            label = tr("Automations", "自动化"),
            onClick = onOpenAutomations,
            modifier = Modifier.testTag("drawer-automations"),
        )
        DrawerNavItem(
            icon = Icons.Rounded.WorkOutline,
            label = tr("Customizations", "自定义配置"),
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
                        text = tr("Pinned", "已置顶"),
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
                        isTitleLoading = coordinator.isSummaryTitleLoading(summary),
                        displayTitle = coordinator.displayTitleForSummary(summary),
                        onVisible = {
                            if (!coordinator.isVerificationMode) {
                                coordinator.prioritizeConversationPreload(summary.cascadeId)
                            }
                        },
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
                        text = tr("Projects", "项目"),
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
                            contentDescription = tr("Display options", "显示选项"),
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
                            contentDescription = tr("New project", "新建项目"),
                            tint = colors.inkLabel,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            val consumedIds = mutableSetOf<String>()
            val rawGroups = allProjects.map { project ->
                val projIsCloud = project.runtime == ProjectRuntimeTarget.CLOUD
                val projectItems = visibleSummaries.filter { s ->
                    if (s.cascadeId in consumedIds) return@filter false
                    val sameHostForFallback = projIsCloud ||
                        project.originInstanceUuid.isNullOrBlank() ||
                        s.originInstanceUuid.isNullOrBlank() ||
                        s.originInstanceUuid == project.originInstanceUuid
                    val matchesProject = s.projectSlug == project.id ||
                        (s.projectSlug == project.name && s.isCloud == projIsCloud && sameHostForFallback)
                    matchesProject && (!s.isPinned || s.cascadeId == activeHighlightCascadeId)
                }
                projectItems.forEach { consumedIds.add(it.cascadeId) }
                project to projectItems
            }
            val populatedNames = rawGroups
                .filter { (_, items) -> items.isNotEmpty() }
                .map { (proj, _) -> proj.name }
                .toSet()
            val dedupedGroups = rawGroups.filterNot { (proj, items) ->
                items.isEmpty() && proj.name in populatedNames
            }

            dedupedGroups.forEach { (project, projectItems) ->
                val isCollapsed = project.id in workspaceState.collapsedProjectIds
                val isNoProjectGroup = project.isNoProject || AntigravityCloudDetector.isNoProjectSlug(project.id)
                val isLocalProject = project.runtime != ProjectRuntimeTarget.CLOUD && !isNoProjectGroup
                item(key = "project-header-${project.id}") {
                    var projectMenuExpanded by remember(project.id) { mutableStateOf(false) }
                    Box(modifier = Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .combinedClickable(
                                    onClick = {
                                        if (projectItems.isNotEmpty()) {
                                            coordinator.workspaceStore.toggleProjectExpanded(
                                                projectId = project.id,
                                                persist = !coordinator.isVerificationMode,
                                            )
                                        } else {
                                            onSelectProject(project.id)
                                        }
                                    },
                                    onLongClick = { projectMenuExpanded = true },
                                )
                                .padding(start = 20.dp, end = 12.dp, top = 8.dp, bottom = 4.dp)
                                .testTag("project-header-${project.id}"),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                imageVector = if (project.runtime == ProjectRuntimeTarget.CLOUD) Icons.Rounded.Cloud else Icons.Rounded.Folder,
                                contentDescription = null,
                                tint = colors.inkSecondary,
                                modifier = Modifier.size(18.dp),
                            )
                            Text(
                                text = if (coordinator.isVerificationMode && project.runtime == ProjectRuntimeTarget.CLOUD && !project.name.contains("/")) {
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
                            if (isCollapsed && projectItems.isNotEmpty()) {
                                Surface(
                                    shape = RoundedCornerShape(100.dp),
                                    color = colors.surfaceActiveTab,
                                    modifier = Modifier.testTag("project-collapsed-count-${project.id}"),
                                ) {
                                    Text(
                                        text = "${projectItems.size}",
                                        style = MaterialTheme.typography.labelSmall.copy(
                                            fontSize = 11.5.sp,
                                            fontWeight = FontWeight.Medium,
                                        ),
                                        color = colors.inkMuted,
                                        modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
                                    )
                                }
                            }
                            if (projectItems.isNotEmpty()) {
                                IconButton(
                                    onClick = {
                                        coordinator.workspaceStore.toggleProjectExpanded(
                                            projectId = project.id,
                                            persist = !coordinator.isVerificationMode,
                                        )
                                    },
                                    modifier = Modifier
                                        .size(34.dp)
                                        .testTag("project-toggle-${project.id}"),
                                ) {
                                    Icon(
                                        imageVector = if (isCollapsed) Icons.Rounded.ChevronRight else Icons.Rounded.KeyboardArrowDown,
                                        contentDescription = if (isCollapsed) {
                                            tr("Expand ${project.name}", "展开 ${project.name}")
                                        } else {
                                            tr("Collapse ${project.name}", "收起 ${project.name}")
                                        },
                                        tint = colors.inkMuted,
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                            }
                            IconButton(
                                onClick = { onNewConversation(project.id) },
                                modifier = Modifier
                                    .size(34.dp)
                                    .testTag("project-add-${project.id}"),
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.Add,
                                    contentDescription = tr("New conversation in ${project.name}", "在 ${project.name} 中新建会话"),
                                    tint = colors.inkLabel,
                                    modifier = Modifier.size(19.dp),
                                )
                            }
                        }

                        DropdownMenu(
                            expanded = projectMenuExpanded,
                            onDismissRequest = { projectMenuExpanded = false },
                            containerColor = colors.surfacePopover,
                            modifier = Modifier.testTag("project-context-menu-${project.id}"),
                        ) {
                            DropdownMenuItem(
                                text = { Text(tr("New conversation in project", "在项目中新建会话"), color = colors.inkReading) },
                                leadingIcon = {
                                    Icon(
                                        imageVector = Icons.Rounded.Add,
                                        contentDescription = null,
                                        tint = colors.inkSecondary,
                                        modifier = Modifier.size(18.dp),
                                    )
                                },
                                onClick = {
                                    projectMenuExpanded = false
                                    onNewConversation(project.id)
                                },
                                modifier = Modifier.testTag("project-menu-new-conv-${project.id}"),
                            )
                            if (!isNoProjectGroup) {
                                DropdownMenuItem(
                                    text = { Text(tr("Project rules & skills", "项目规则与技能"), color = colors.inkReading) },
                                    leadingIcon = {
                                        Icon(
                                            imageVector = Icons.Rounded.Hub,
                                            contentDescription = null,
                                            tint = colors.inkSecondary,
                                            modifier = Modifier.size(18.dp),
                                        )
                                    },
                                    onClick = {
                                        projectMenuExpanded = false
                                        onOpenProjectCustomizations(project.id, project.name)
                                    },
                                    modifier = Modifier.testTag("project-menu-rules-skills-${project.id}"),
                                )
                                if (isLocalProject) {
                                    DropdownMenuItem(
                                        text = { Text(tr("Reveal in Finder on Mac", "在 Mac 访达中显示"), color = colors.inkReading) },
                                        leadingIcon = {
                                            Icon(
                                                imageVector = Icons.Rounded.Computer,
                                                contentDescription = null,
                                                tint = colors.inkSecondary,
                                                modifier = Modifier.size(18.dp),
                                            )
                                        },
                                        onClick = {
                                            projectMenuExpanded = false
                                            onRevealProjectInFinder(project.id)
                                        },
                                        modifier = Modifier.testTag("project-menu-reveal-finder-${project.id}"),
                                    )
                                }
                            }
                        }
                    }
                }

                if (!isCollapsed) {
                    items(projectItems, key = { "proj-${project.id}-${it.cascadeId}" }) { summary ->
                        DrawerConversationRow(
                            summary = summary,
                            isSelected = summary.cascadeId == activeHighlightCascadeId,
                            indented = true,
                            isTitleLoading = coordinator.isSummaryTitleLoading(summary),
                            displayTitle = coordinator.displayTitleForSummary(summary),
                            onVisible = {
                                if (!coordinator.isVerificationMode) {
                                    coordinator.prioritizeConversationPreload(summary.cascadeId)
                                }
                            },
                            onClick = { onOpenConversation(summary.cascadeId) },
                            onLongClick = { onLongPressConversation(summary.cascadeId) },
                        )
                    }
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
            label = tr("Settings", "设置"),
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
    isTitleLoading: Boolean = false,
    displayTitle: String = summary.title,
    onVisible: () -> Unit = {},
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    LaunchedEffect(summary.cascadeId, summary.hasResolvedTitle) {
        onVisible()
    }
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
        if (isTitleLoading) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .testTag("conversation-loading-${summary.cascadeId}"),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                CircularProgressIndicator(
                    strokeWidth = 1.8.dp,
                    color = colors.inkMuted,
                    modifier = Modifier.size(13.dp),
                )
                Text(
                    text = tr("Loading...", "加载中…"),
                    style = MaterialTheme.typography.bodyMedium.copy(
                        fontSize = 14.5.sp,
                        fontWeight = FontWeight.Normal,
                    ),
                    color = colors.inkMuted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        } else {
            Text(
                text = displayTitle,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontSize = 15.sp,
                    fontWeight = if (isSelected || summary.isUnread) FontWeight.Medium else FontWeight.Normal,
                ),
                color = colors.inkReading,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
        }

        DrawerConversationTrailingIndicator(summary = summary)
    }
}

@Composable
internal fun DrawerConversationTrailingIndicator(summary: CascadeSummary) {
    val colors = MaterialTheme.antigravityColors
    val lang = LocalAppLanguage.current
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
                text = AppLocalizationFormatter.localizeRelativeTime(summary.relativeTimeLabel, lang),
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
