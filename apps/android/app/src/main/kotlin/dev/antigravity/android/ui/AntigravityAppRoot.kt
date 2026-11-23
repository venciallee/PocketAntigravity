package dev.antigravity.android.ui

import android.util.Log
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import dev.antigravity.android.core.platform.CloudRelayCookieBridge
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.AntigravityTheme
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.android.ui.automations.AutomationsScreen
import dev.antigravity.android.ui.chat.AddContextSheetScreen
import dev.antigravity.android.ui.chat.CascadeChatScreen
import dev.antigravity.android.ui.chat.ConversationOverviewSheet
import dev.antigravity.android.ui.chat.ModelAndModeSheetScreen
import dev.antigravity.android.ui.chat.SideQuestionSheet
import dev.antigravity.android.ui.chat.StructuredQuestionScreen
import dev.antigravity.android.ui.chat.SwarmBoardSheet
import dev.antigravity.android.ui.chat.VoiceModeSheet
import dev.antigravity.android.ui.home.AgentsHomeScreen
import dev.antigravity.android.ui.home.ConversationContextSheetScreen
import dev.antigravity.android.ui.home.DisplayOptionsOverlayScreen
import dev.antigravity.android.ui.liveprogress.AndroidLiveUpdatesSpecGallery
import dev.antigravity.android.ui.liveprogress.defaultLiveProgressSpecSnapshot
import dev.antigravity.android.ui.pairing.CloudRelaySignInScreen
import dev.antigravity.android.ui.pairing.RemoteControlLinkDialog
import dev.antigravity.android.ui.pairing.SettingsAndCustomizationsScreen
import dev.antigravity.android.ui.pairing.WelcomeAndPairingScreen
import dev.antigravity.android.ui.projects.CreateProjectScreen
import dev.antigravity.android.ui.projects.ProjectDetailScreen
import dev.antigravity.android.ui.review.ImplementationPlanReviewScreen
import dev.antigravity.android.ui.review.TurnDiffReviewScreen
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.domain.EsddVerificationFixtures
import dev.antigravity.shared.model.AppAppearanceMode
import dev.antigravity.shared.model.AppThemePreset
import dev.antigravity.shared.model.EsddVerifySceneCase
import dev.antigravity.shared.model.PrimaryTab
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.protocol.SapisidHashGenerator
import kotlinx.coroutines.launch

private sealed interface AppRoute {
    data class RootTab(val tab: PrimaryTab) : AppRoute
    data class DisplayOptions(val expandSortMenu: Boolean = false) : AppRoute
    data class ContextMenu(val cascadeId: String) : AppRoute
    data class ProjectDetail(val projectId: String) : AppRoute
    data object CreateProject : AppRoute
    data class CascadeChat(val cascadeId: String) : AppRoute
    data object AddContext : AppRoute
    data object ModelAndMode : AppRoute
    data object StructuredQuestion : AppRoute
    data object PlanReview : AppRoute
    data object TurnDiffReview : AppRoute
    data object LiveUpdatesSpec : AppRoute
    data object Pairing : AppRoute
    data class CloudRelaySignIn(val targetRelayUrl: String = SapisidHashGenerator.DEFAULT_ORIGIN) : AppRoute
}

private enum class ChatOverlaySheet {
    NONE,
    ADD_CONTEXT,
    MODEL_AND_MODE,
    OVERVIEW,
    SIDE_QUESTION,
    SWARM_BOARD,
    VOICE_MODE,
}

/**
 * Root Jetpack Compose application shell routing across all 13 canonical UE states (`UE01`..`UE13`),
 * Material 3 bottom `NavigationBar` (`Agents`, `Automations`, `Settings`) + Squircle FABs,
 * v2.33 orchestration sheets, and pairing/settings flows.
 */
@Composable
fun AntigravityAppRoot(
    coordinator: AntigravityCoreCoordinator,
    initialVerifyScene: EsddVerifySceneCase? = null,
    darkThemeOverride: Boolean? = null,
    themePresetOverride: AppThemePreset? = null,
    onBiometricPrompt: (title: String, onSuccess: () -> Unit) -> Unit = { _, onSuccess -> onSuccess() },
) {
    // Synchronously configure coordinator for deterministic ESDD verification scenes before Frame 0
    remember(coordinator, initialVerifyScene) {
        if (initialVerifyScene != null) {
            EsddVerificationFixtures.configureCoordinatorForVerifyScene(coordinator, initialVerifyScene)
        }
        initialVerifyScene
    }

    val settingsState by coordinator.settingsStore.state.collectAsState()
    val connectionState by coordinator.connectionState.collectAsState()
    val syncState by coordinator.syncState.collectAsState()
    val scope = rememberCoroutineScope()

    val appearance = settingsState.appearance
    val resolvedPreset = themePresetOverride ?: appearance.theme
    val resolvedDark = darkThemeOverride ?: when (appearance.appearanceMode) {
        AppAppearanceMode.DARK -> true
        AppAppearanceMode.LIGHT -> false
        AppAppearanceMode.SYSTEM -> isSystemInDarkTheme()
    }

    val defaultStartRoute = remember(initialVerifyScene, connectionState.hasPairedBackend, syncState.summaries.isEmpty()) {
        if (initialVerifyScene != null) {
            routeForVerifyScene(initialVerifyScene)
        } else if (!connectionState.hasPairedBackend && !coordinator.isVerificationMode && syncState.summaries.isEmpty()) {
            AppRoute.Pairing
        } else {
            AppRoute.RootTab(PrimaryTab.AGENTS)
        }
    }

    var currentRoute by remember(initialVerifyScene) { mutableStateOf(defaultStartRoute) }
    var previousRoute by remember(initialVerifyScene) { mutableStateOf<AppRoute>(AppRoute.RootTab(PrimaryTab.AGENTS)) }
    var activeChatOverlay by remember(initialVerifyScene) { mutableStateOf(ChatOverlaySheet.NONE) }
    var showRemoteLinkDialog by remember { mutableStateOf(false) }
    var userExplicitlyOpenedPairing by remember { mutableStateOf(false) }

    // Automatically enter Agents Home once background cold-start cache hydration or saved-session
    // restoration completes (matching iOS Frame-0 instant conversations launch).
    LaunchedEffect(
        initialVerifyScene,
        connectionState.hasPairedBackend,
        connectionState.isConnected,
        syncState.summaries.isNotEmpty(),
    ) {
        if (initialVerifyScene == null &&
            !userExplicitlyOpenedPairing &&
            currentRoute == AppRoute.Pairing &&
            (connectionState.isConnected || connectionState.hasPairedBackend || syncState.summaries.isNotEmpty())
        ) {
            currentRoute = AppRoute.RootTab(PrimaryTab.AGENTS)
        }
    }

    fun navigateTo(destination: AppRoute) {
        previousRoute = currentRoute
        activeChatOverlay = ChatOverlaySheet.NONE
        if (destination == AppRoute.Pairing) {
            userExplicitlyOpenedPairing = true
        } else if (destination is AppRoute.RootTab) {
            userExplicitlyOpenedPairing = false
        }
        currentRoute = destination
    }

    fun openNewConversation(projectId: String = "") {
        if (coordinator.isVerificationMode) {
            coordinator.chatStore.setActiveCascade("cas-rate-limiter")
            navigateTo(AppRoute.CascadeChat("cas-rate-limiter"))
            return
        }
        val draftId = coordinator.createLocalDraftConversation(projectSlug = projectId)
        navigateTo(AppRoute.CascadeChat(draftId))
    }

    fun openConversation(cascadeId: String) {
        coordinator.chatStore.setActiveCascade(cascadeId)
        if (!coordinator.isVerificationMode && !cascadeId.startsWith("cascade-new-")) {
            val summary = syncState.summaries.firstOrNull { it.cascadeId == cascadeId }
            scope.launch {
                runCatching {
                    coordinator.syncSteps(
                        cascadeId = cascadeId,
                        knownStepCount = summary?.stepCount ?: 0,
                        isCloud = summary?.isCloud == true,
                        instanceUuidOverride = summary?.originInstanceUuid,
                    )
                }
            }
        }
        if (coordinator.isVerificationMode && cascadeId == "cas-audit-log-admin") {
            navigateTo(AppRoute.StructuredQuestion)
        } else {
            navigateTo(AppRoute.CascadeChat(cascadeId))
        }
    }

    fun navigateBack() {
        if (activeChatOverlay != ChatOverlaySheet.NONE) {
            activeChatOverlay = ChatOverlaySheet.NONE
            return
        }
        currentRoute = when (currentRoute) {
            is AppRoute.RootTab -> currentRoute
            is AppRoute.CloudRelaySignIn -> AppRoute.Pairing
            is AppRoute.DisplayOptions,
            is AppRoute.ContextMenu,
            is AppRoute.ProjectDetail,
            AppRoute.CreateProject,
            AppRoute.LiveUpdatesSpec,
            AppRoute.Pairing,
            -> AppRoute.RootTab(PrimaryTab.AGENTS)

            is AppRoute.CascadeChat,
            AppRoute.StructuredQuestion,
            -> if (previousRoute is AppRoute.ProjectDetail) previousRoute else AppRoute.RootTab(PrimaryTab.AGENTS)

            AppRoute.AddContext,
            AppRoute.ModelAndMode,
            AppRoute.PlanReview,
            AppRoute.TurnDiffReview,
            -> AppRoute.CascadeChat(coordinator.chatState.value.activeCascadeId.ifBlank { "cas-rate-limiter" })
        }
    }

    BackHandler(enabled = currentRoute !is AppRoute.RootTab || activeChatOverlay != ChatOverlaySheet.NONE) {
        navigateBack()
    }

    AntigravityTheme(
        preset = resolvedPreset,
        darkTheme = resolvedDark,
        useDynamicColor = appearance.useDynamicColor,
    ) {
        val colors = LocalAntigravityColors.current

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.canvasObsidian),
        ) {
            when (val route = currentRoute) {
                is AppRoute.RootTab -> {
                    RootTabScaffold(
                        activeTab = route.tab,
                        onSelectTab = { nextTab -> currentRoute = AppRoute.RootTab(nextTab) },
                        onTapAgentsComposeFab = { openNewConversation() },
                        onTapAutomationsAddFab = {
                            scope.launch {
                                val client = coordinator.connectionStore.activeClient()
                                coordinator.workspaceStore.createAutomationFromPrompt(
                                    client = client,
                                    prompt = "Nightly lint and security audit",
                                )
                            }
                        },
                    ) { contentModifier ->
                        when (route.tab) {
                            PrimaryTab.AGENTS -> {
                                AgentsHomeScreen(
                                    coordinator = coordinator,
                                    onOpenDisplayOptions = { navigateTo(AppRoute.DisplayOptions(expandSortMenu = false)) },
                                    onOpenNewProject = { navigateTo(AppRoute.CreateProject) },
                                    onOpenProjectDetail = { projectId ->
                                        coordinator.workspaceStore.selectProject(projectId)
                                        navigateTo(AppRoute.ProjectDetail(projectId))
                                    },
                                    onOpenConversation = { cascadeId -> openConversation(cascadeId) },
                                    onLongPressConversation = { cascadeId ->
                                        navigateTo(AppRoute.ContextMenu(cascadeId))
                                    },
                                    onTapComposeFab = { openNewConversation() },
                                    onOpenReSignIn = {
                                        val relayUrl = connectionState.activeHost?.endpointUrl
                                            ?.takeIf { it.startsWith("https://") }
                                            ?: SapisidHashGenerator.DEFAULT_ORIGIN
                                        navigateTo(AppRoute.CloudRelaySignIn(relayUrl))
                                    },
                                    modifier = contentModifier,
                                )
                            }

                            PrimaryTab.AUTOMATIONS -> {
                                AutomationsScreen(
                                    coordinator = coordinator,
                                    onTapAddFab = {},
                                    modifier = contentModifier,
                                )
                            }

                            PrimaryTab.SETTINGS -> {
                                SettingsAndCustomizationsScreen(
                                    coordinator = coordinator,
                                    onOpenPairing = { navigateTo(AppRoute.Pairing) },
                                    modifier = contentModifier,
                                )
                            }
                        }
                    }
                }

                is AppRoute.DisplayOptions -> {
                    DisplayOptionsOverlayScreen(
                        coordinator = coordinator,
                        onDismiss = { navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS)) },
                        initialSortMenuExpanded = route.expandSortMenu,
                    )
                }

                is AppRoute.ContextMenu -> {
                    ConversationContextSheetScreen(
                        coordinator = coordinator,
                        targetCascadeId = route.cascadeId,
                        onDismiss = { navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS)) },
                    )
                }

                is AppRoute.ProjectDetail -> {
                    ProjectDetailScreen(
                        coordinator = coordinator,
                        projectId = route.projectId,
                        onBack = { navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS)) },
                        onNewConversation = { openNewConversation(projectId = route.projectId) },
                        onOpenConversation = { cascadeId -> openConversation(cascadeId) },
                        onOpenAutomations = { navigateTo(AppRoute.RootTab(PrimaryTab.AUTOMATIONS)) },
                    )
                }

                AppRoute.CreateProject -> {
                    CreateProjectScreen(
                        coordinator = coordinator,
                        onDismiss = { navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS)) },
                        onCreated = { navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS)) },
                    )
                }

                is AppRoute.CascadeChat -> {
                    Box(modifier = Modifier.fillMaxSize()) {
                        CascadeChatScreen(
                            coordinator = coordinator,
                            onBack = { navigateBack() },
                            onOpenDiffReview = { navigateTo(AppRoute.TurnDiffReview) },
                            onOpenPlanReview = { navigateTo(AppRoute.PlanReview) },
                            onOpenAddContext = { activeChatOverlay = ChatOverlaySheet.ADD_CONTEXT },
                            onOpenModelAndMode = { activeChatOverlay = ChatOverlaySheet.MODEL_AND_MODE },
                            onOpenOverview = { activeChatOverlay = ChatOverlaySheet.OVERVIEW },
                            onOpenSideQuestion = { activeChatOverlay = ChatOverlaySheet.SIDE_QUESTION },
                            onOpenSwarmBoard = { activeChatOverlay = ChatOverlaySheet.SWARM_BOARD },
                            onOpenVoiceMode = { activeChatOverlay = ChatOverlaySheet.VOICE_MODE },
                            onBiometricPrompt = onBiometricPrompt,
                        )

                        when (activeChatOverlay) {
                            ChatOverlaySheet.NONE -> Unit
                            ChatOverlaySheet.ADD_CONTEXT -> {
                                AddContextSheetScreen(
                                    coordinator = coordinator,
                                    onDismiss = { activeChatOverlay = ChatOverlaySheet.NONE },
                                )
                            }

                            ChatOverlaySheet.MODEL_AND_MODE -> {
                                ModelAndModeSheetScreen(
                                    coordinator = coordinator,
                                    onDismiss = { activeChatOverlay = ChatOverlaySheet.NONE },
                                )
                            }

                            ChatOverlaySheet.OVERVIEW -> {
                                ConversationOverviewSheet(
                                    coordinator = coordinator,
                                    onDismiss = { activeChatOverlay = ChatOverlaySheet.NONE },
                                    onOpenDiffReview = { navigateTo(AppRoute.TurnDiffReview) },
                                    onOpenPlanReview = { navigateTo(AppRoute.PlanReview) },
                                )
                            }

                            ChatOverlaySheet.SIDE_QUESTION -> {
                                SideQuestionSheet(
                                    coordinator = coordinator,
                                    onDismiss = { activeChatOverlay = ChatOverlaySheet.NONE },
                                )
                            }

                            ChatOverlaySheet.SWARM_BOARD -> {
                                SwarmBoardSheet(
                                    coordinator = coordinator,
                                    onDismiss = { activeChatOverlay = ChatOverlaySheet.NONE },
                                )
                            }

                            ChatOverlaySheet.VOICE_MODE -> {
                                VoiceModeSheet(
                                    coordinator = coordinator,
                                    onDismiss = { activeChatOverlay = ChatOverlaySheet.NONE },
                                )
                            }
                        }
                    }
                }

                AppRoute.AddContext -> {
                    AddContextSheetScreen(
                        coordinator = coordinator,
                        onDismiss = {
                            navigateTo(
                                AppRoute.CascadeChat(
                                    coordinator.chatState.value.activeCascadeId.ifBlank { "cas-rate-limiter" },
                                ),
                            )
                        },
                    )
                }

                AppRoute.ModelAndMode -> {
                    ModelAndModeSheetScreen(
                        coordinator = coordinator,
                        onDismiss = {
                            navigateTo(
                                AppRoute.CascadeChat(
                                    coordinator.chatState.value.activeCascadeId.ifBlank { "cas-rate-limiter" },
                                ),
                            )
                        },
                    )
                }

                AppRoute.StructuredQuestion -> {
                    StructuredQuestionScreen(
                        coordinator = coordinator,
                        onBack = { navigateBack() },
                    )
                }

                AppRoute.PlanReview -> {
                    ImplementationPlanReviewScreen(
                        coordinator = coordinator,
                        onBack = { navigateBack() },
                        onProceed = { navigateBack() },
                    )
                }

                AppRoute.TurnDiffReview -> {
                    TurnDiffReviewScreen(
                        coordinator = coordinator,
                        onBack = { navigateBack() },
                    )
                }

                AppRoute.LiveUpdatesSpec -> {
                    val liveSnapshot = remember(syncState.summaries) {
                        coordinator.liveProgressSnapshot() ?: defaultLiveProgressSpecSnapshot()
                    }
                    AndroidLiveUpdatesSpecGallery(snapshot = liveSnapshot)
                }

                AppRoute.Pairing -> {
                    WelcomeAndPairingScreen(
                        onScanQr = { showRemoteLinkDialog = true },
                        onCloudRelaySignIn = {
                            navigateTo(AppRoute.CloudRelaySignIn(SapisidHashGenerator.DEFAULT_ORIGIN))
                        },
                        onConnectDirectLan = { endpointUrl, csrf ->
                            scope.launch {
                                runCatching {
                                    coordinator.connectDirectLan(
                                        endpointUrlString = endpointUrl,
                                        csrfToken = csrf,
                                    )
                                    navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS))
                                }
                            }
                        },
                        onContinueDemo = {
                            EsddVerificationFixtures.seedCoordinator(coordinator)
                            navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS))
                        },
                        isConnecting = connectionState.isConnecting,
                        statusText = connectionState.statusText,
                        errorText = connectionState.errorText,
                        onCancelConnecting = { coordinator.cancelPendingConnectionAttempt() },
                    )

                    if (showRemoteLinkDialog) {
                        RemoteControlLinkDialog(
                            onSubmitLink = { rawLink ->
                                showRemoteLinkDialog = false
                                val trimmed = rawLink.trim()
                                val relayTarget = RemoteHostInstance.parseRemoteControlTarget(trimmed)
                                if (relayTarget != null) {
                                    val existingCookie = CloudRelayCookieBridge.extractSessionCookieHeaderForHost(
                                        relayTarget.relayOrigin.removePrefix("https://").removePrefix("http://"),
                                    )
                                    if (existingCookie.isNullOrBlank()) {
                                        navigateTo(AppRoute.CloudRelaySignIn(relayTarget.canonicalRelayUrlString))
                                    } else {
                                        scope.launch {
                                            val result = runCatching {
                                                coordinator.connectCloudRelay(
                                                    relayUrlString = relayTarget.canonicalRelayUrlString,
                                                    sessionCookie = existingCookie,
                                                    authUser = relayTarget.authUser,
                                                )
                                            }
                                            if (result.isSuccess) {
                                                navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS))
                                            } else if (result.exceptionOrNull() is dev.antigravity.shared.protocol.AntigravityRpcError.Unauthorized) {
                                                navigateTo(AppRoute.CloudRelaySignIn(relayTarget.canonicalRelayUrlString))
                                            }
                                        }
                                    }
                                } else {
                                    scope.launch {
                                        runCatching {
                                            coordinator.connectWithPairingUri(trimmed)
                                            navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS))
                                        }
                                    }
                                }
                            },
                            onDismiss = { showRemoteLinkDialog = false },
                        )
                    }
                }

                is AppRoute.CloudRelaySignIn -> {
                    CloudRelaySignInScreen(
                        targetRelayUrl = route.targetRelayUrl,
                        onAuthenticated = { captured ->
                            val effectiveUrl = RemoteHostInstance.resolveEffectiveRelayTarget(
                                scannedInput = route.targetRelayUrl,
                                webViewFinalUrl = captured.finalUrl,
                            )
                            val ckSummary = SapisidHashGenerator.summarizeCookieNames(captured.cookieHeader)
                            val keySummary = captured.relayApiKey?.let { "len:${it.length}" } ?: "none"
                            Log.i(
                                "CloudRelay",
                                "Android handshake start target=$effectiveUrl authUser=${captured.authUser ?: "auto"} key=$keySummary ck=$ckSummary",
                            )
                            currentRoute = AppRoute.Pairing
                            scope.launch {
                                val result = runCatching {
                                    coordinator.connectCloudRelay(
                                        relayUrlString = effectiveUrl,
                                        sessionCookie = captured.cookieHeader,
                                        authUser = captured.authUser,
                                        relayApiKey = captured.relayApiKey,
                                    )
                                }
                                if (result.isSuccess) {
                                    val hs = result.getOrNull()
                                    Log.i(
                                        "CloudRelay",
                                        "Android handshake OK host=${hs?.resolvedHostname} instances=${hs?.availableRelayInstances?.size} latencyMs=${hs?.latencyMs}",
                                    )
                                    navigateTo(AppRoute.RootTab(PrimaryTab.AGENTS))
                                } else {
                                    Log.w(
                                        "CloudRelay",
                                        "Android handshake failed: ${result.exceptionOrNull()?.message}",
                                    )
                                }
                            }
                        },
                        onCancel = { currentRoute = AppRoute.Pairing },
                    )
                }
            }
        }
    }
}

@Composable
private fun RootTabScaffold(
    activeTab: PrimaryTab,
    onSelectTab: (PrimaryTab) -> Unit,
    onTapAgentsComposeFab: () -> Unit,
    onTapAutomationsAddFab: () -> Unit,
    content: @Composable (Modifier) -> Unit,
) {
    val colors = LocalAntigravityColors.current

    Scaffold(
        modifier = Modifier.fillMaxSize(),
        containerColor = colors.canvasObsidian,
        bottomBar = {
            NavigationBar(
                modifier = Modifier.testTag("bottom-nav-bar"),
                containerColor = colors.surfaceObsidian,
                tonalElevation = 0.dp,
            ) {
                NavigationBarItem(
                    selected = activeTab == PrimaryTab.AGENTS,
                    onClick = { onSelectTab(PrimaryTab.AGENTS) },
                    icon = {
                        Icon(
                            imageVector = Icons.Rounded.AutoAwesome,
                            contentDescription = "Agents",
                        )
                    },
                    label = { Text("Agents", style = MaterialTheme.typography.labelMedium) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = colors.accentPeriwinkle,
                        selectedTextColor = colors.accentPeriwinkle,
                        indicatorColor = colors.surfaceSelectionTint,
                        unselectedIconColor = colors.inkSecondary,
                        unselectedTextColor = colors.inkSecondary,
                    ),
                    modifier = Modifier.testTag("nav-tab-agents"),
                )
                NavigationBarItem(
                    selected = activeTab == PrimaryTab.AUTOMATIONS,
                    onClick = { onSelectTab(PrimaryTab.AUTOMATIONS) },
                    icon = {
                        Icon(
                            imageVector = Icons.Rounded.Schedule,
                            contentDescription = "Automations",
                        )
                    },
                    label = { Text("Automations", style = MaterialTheme.typography.labelMedium) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = colors.accentPeriwinkle,
                        selectedTextColor = colors.accentPeriwinkle,
                        indicatorColor = colors.surfaceSelectionTint,
                        unselectedIconColor = colors.inkSecondary,
                        unselectedTextColor = colors.inkSecondary,
                    ),
                    modifier = Modifier.testTag("nav-tab-automations"),
                )
                NavigationBarItem(
                    selected = activeTab == PrimaryTab.SETTINGS,
                    onClick = { onSelectTab(PrimaryTab.SETTINGS) },
                    icon = {
                        Icon(
                            imageVector = Icons.Rounded.Settings,
                            contentDescription = "Settings",
                        )
                    },
                    label = { Text("Settings", style = MaterialTheme.typography.labelMedium) },
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = colors.accentPeriwinkle,
                        selectedTextColor = colors.accentPeriwinkle,
                        indicatorColor = colors.surfaceSelectionTint,
                        unselectedIconColor = colors.inkSecondary,
                        unselectedTextColor = colors.inkSecondary,
                    ),
                    modifier = Modifier.testTag("nav-tab-settings"),
                )
            }
        },
        floatingActionButton = {
            when (activeTab) {
                PrimaryTab.AGENTS -> {
                    FloatingActionButton(
                        onClick = onTapAgentsComposeFab,
                        modifier = Modifier
                            .size(AntigravityDesignTokens.FabSize)
                            .testTag("fab-compose"),
                        shape = RoundedCornerShape(AntigravityDesignTokens.FabCornerRadius),
                        containerColor = colors.accentPeriwinkle,
                        contentColor = colors.inkOnPrimaryCta,
                        elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 4.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Edit,
                            contentDescription = "New Conversation",
                        )
                    }
                }

                PrimaryTab.AUTOMATIONS -> {
                    FloatingActionButton(
                        onClick = onTapAutomationsAddFab,
                        modifier = Modifier
                            .size(AntigravityDesignTokens.FabSize)
                            .testTag("fab-add-automation"),
                        shape = RoundedCornerShape(AntigravityDesignTokens.FabCornerRadius),
                        containerColor = colors.accentPeriwinkle,
                        contentColor = colors.inkOnPrimaryCta,
                        elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 4.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Add,
                            contentDescription = "New Automation",
                        )
                    }
                }

                PrimaryTab.SETTINGS -> Unit
            }
        },
    ) { innerPadding ->
        content(
            Modifier
                .fillMaxSize()
                .padding(innerPadding),
        )
    }
}

private fun routeForVerifyScene(scene: EsddVerifySceneCase): AppRoute = when (scene) {
    EsddVerifySceneCase.AGENTS_HOME -> AppRoute.RootTab(PrimaryTab.AGENTS)
    EsddVerifySceneCase.DISPLAY_OPTIONS -> AppRoute.DisplayOptions(expandSortMenu = true)
    EsddVerifySceneCase.CONTEXT_MENU_PIN -> AppRoute.ContextMenu("cas-flaky-settlement")
    EsddVerifySceneCase.PROJECT_DETAIL -> AppRoute.ProjectDetail("ledger-svc")
    EsddVerifySceneCase.CREATE_PROJECT -> AppRoute.CreateProject
    EsddVerifySceneCase.AUTOMATIONS -> AppRoute.RootTab(PrimaryTab.AUTOMATIONS)
    EsddVerifySceneCase.CHAT_AND_COMPOSER -> AppRoute.CascadeChat("cas-rate-limiter")
    EsddVerifySceneCase.ADD_CONTEXT -> AppRoute.AddContext
    EsddVerifySceneCase.MODEL_AND_MODE -> AppRoute.ModelAndMode
    EsddVerifySceneCase.STRUCTURED_QUESTION -> AppRoute.StructuredQuestion
    EsddVerifySceneCase.PLAN_REVIEW -> AppRoute.PlanReview
    EsddVerifySceneCase.TURN_DIFF_REVIEW -> AppRoute.TurnDiffReview
    EsddVerifySceneCase.LIVE_ACTIVITY_SPEC -> AppRoute.LiveUpdatesSpec
}
