package dev.antigravity.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import dev.antigravity.android.core.platform.CloudRelayCookieBridge
import dev.antigravity.android.core.ui.theme.AntigravityTheme
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.android.ui.automations.AutomationDetailScreen
import dev.antigravity.android.ui.automations.AutomationEditScreen
import dev.antigravity.android.ui.automations.AutomationsScreen
import dev.antigravity.android.ui.chat.AddContextSheetScreen
import dev.antigravity.android.ui.chat.CascadeChatScreen
import dev.antigravity.android.ui.chat.ConversationOverviewSheet
import dev.antigravity.android.ui.chat.ModelAndModeSheetScreen
import dev.antigravity.android.ui.chat.PermissionsPresetOverlayScreen
import dev.antigravity.android.ui.chat.SideQuestionSheet
import dev.antigravity.android.ui.chat.SlashMenuOverlayScreen
import dev.antigravity.android.ui.chat.StructuredQuestionScreen
import dev.antigravity.android.ui.chat.SwarmBoardSheet
import dev.antigravity.android.ui.chat.VoiceModeSheet
import dev.antigravity.android.ui.home.AgentsHomeScreen
import dev.antigravity.android.ui.home.AgentsSidebarDrawerOverlay
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
import dev.antigravity.android.ui.projects.ProjectRulesAndSkillsScreen
import dev.antigravity.android.ui.review.ImplementationPlanReviewScreen
import dev.antigravity.android.ui.review.TurnDiffReviewScreen
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.domain.EsddVerificationFixtures
import dev.antigravity.shared.model.AppAppearanceMode
import dev.antigravity.shared.model.AppThemePreset
import dev.antigravity.shared.model.EsddVerifySceneCase
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.protocol.SapisidHashGenerator
import kotlinx.coroutines.launch

private sealed interface AppRoute {
    data object NewConversationHome : AppRoute
    data object SidebarDrawer : AppRoute
    data class DisplayOptions(val expandSortMenu: Boolean = false) : AppRoute
    data class ContextMenu(val cascadeId: String) : AppRoute
    data class ProjectDetail(val projectId: String) : AppRoute
    data object CreateProject : AppRoute
    data class Automations(val expandedMenuId: String? = null) : AppRoute
    data class AutomationDetail(val automationId: String) : AppRoute
    data class AutomationEdit(val automationId: String) : AppRoute
    data class CascadeChat(val cascadeId: String) : AppRoute
    data object PermissionsPreset : AppRoute
    data object AddContext : AppRoute
    data class SlashMenu(val includeSideQuestionPreview: Boolean = false) : AppRoute
    data object ModelAndMode : AppRoute
    data object StructuredQuestion : AppRoute
    data object PlanReview : AppRoute
    data object TurnDiffReview : AppRoute
    data object LiveUpdatesSpec : AppRoute
    data class RulesAndSkills(val projectName: String = "ledger-svc") : AppRoute
    data object Settings : AppRoute
    data object Pairing : AppRoute
    data class CloudRelaySignIn(val targetRelayUrl: String = SapisidHashGenerator.DEFAULT_ORIGIN) : AppRoute
}

private enum class ChatOverlaySheet {
    NONE,
    ADD_CONTEXT,
    MODEL_AND_MODE,
    PERMISSIONS_PRESET,
    SLASH_MENU,
    OVERVIEW,
    SIDE_QUESTION,
    SWARM_BOARD,
    VOICE_MODE,
}

/**
 * Root Jetpack Compose application shell routing across all 20 aligned UE states (`UE01`..`UE15`),
 * New Conversation Home + Left Modal Navigation Drawer (replacing legacy bottom tab bar),
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
    val workspaceState by coordinator.workspaceStore.state.collectAsState()
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
            AppRoute.NewConversationHome
        }
    }

    var currentRoute by remember(initialVerifyScene) { mutableStateOf(defaultStartRoute) }
    var previousRoute by remember(initialVerifyScene) { mutableStateOf<AppRoute>(AppRoute.NewConversationHome) }
    var activeChatOverlay by remember(initialVerifyScene) { mutableStateOf(ChatOverlaySheet.NONE) }
    var showRemoteLinkDialog by remember { mutableStateOf(false) }
    var userExplicitlyOpenedPairing by remember { mutableStateOf(false) }

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
            currentRoute = AppRoute.NewConversationHome
        }
    }

    fun navigateTo(destination: AppRoute) {
        previousRoute = currentRoute
        activeChatOverlay = ChatOverlaySheet.NONE
        if (destination == AppRoute.Pairing) {
            userExplicitlyOpenedPairing = true
        } else if (destination == AppRoute.NewConversationHome) {
            userExplicitlyOpenedPairing = false
        }
        currentRoute = destination
    }

    fun openNewConversation(projectId: String = "") {
        if (projectId.isNotBlank()) {
            coordinator.workspaceStore.selectProject(projectId)
        }
        if (coordinator.isVerificationMode) {
            navigateTo(AppRoute.NewConversationHome)
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
        currentRoute = when (val route = currentRoute) {
            AppRoute.NewConversationHome -> AppRoute.NewConversationHome
            AppRoute.SidebarDrawer,
            is AppRoute.DisplayOptions,
            is AppRoute.ContextMenu,
            is AppRoute.ProjectDetail,
            AppRoute.CreateProject,
            is AppRoute.Automations,
            AppRoute.PermissionsPreset,
            AppRoute.AddContext,
            is AppRoute.SlashMenu,
            AppRoute.ModelAndMode,
            AppRoute.LiveUpdatesSpec,
            AppRoute.Settings,
            AppRoute.Pairing,
            -> AppRoute.NewConversationHome

            is AppRoute.AutomationDetail -> {
                if (previousRoute is AppRoute.ProjectDetail) previousRoute else AppRoute.Automations()
            }

            is AppRoute.AutomationEdit -> AppRoute.AutomationDetail(route.automationId)

            is AppRoute.RulesAndSkills -> {
                if (previousRoute is AppRoute.ProjectDetail) previousRoute else AppRoute.NewConversationHome
            }

            is AppRoute.CloudRelaySignIn -> AppRoute.Pairing

            is AppRoute.CascadeChat,
            AppRoute.StructuredQuestion,
            -> if (previousRoute is AppRoute.ProjectDetail) previousRoute else AppRoute.NewConversationHome

            AppRoute.PlanReview,
            AppRoute.TurnDiffReview,
            -> AppRoute.CascadeChat(coordinator.chatState.value.activeCascadeId.ifBlank { "cas-rate-limiter" })
        }
    }

    BackHandler(enabled = currentRoute != AppRoute.NewConversationHome || activeChatOverlay != ChatOverlaySheet.NONE) {
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
                AppRoute.NewConversationHome -> {
                    AgentsHomeScreen(
                        coordinator = coordinator,
                        onOpenSidebar = { navigateTo(AppRoute.SidebarDrawer) },
                        onOpenConversation = { cascadeId -> openConversation(cascadeId) },
                        onOpenAddContext = { navigateTo(AppRoute.AddContext) },
                        onOpenModelPicker = { navigateTo(AppRoute.ModelAndMode) },
                        onOpenPermissionsPreset = { navigateTo(AppRoute.PermissionsPreset) },
                        onOpenSlashMenu = { navigateTo(AppRoute.SlashMenu(includeSideQuestionPreview = false)) },
                        onOpenVoiceMode = {
                            coordinator.chatStore.setActiveCascade("cas-rate-limiter")
                            currentRoute = AppRoute.CascadeChat("cas-rate-limiter")
                            activeChatOverlay = ChatOverlaySheet.VOICE_MODE
                        },
                        onOpenReSignIn = {
                            val relayUrl = connectionState.activeHost?.endpointUrl
                                ?.takeIf { it.startsWith("https://") }
                                ?: SapisidHashGenerator.DEFAULT_ORIGIN
                            navigateTo(AppRoute.CloudRelaySignIn(relayUrl))
                        },
                    )
                }

                AppRoute.SidebarDrawer -> {
                    AgentsSidebarDrawerOverlay(
                        coordinator = coordinator,
                        onDismiss = { navigateTo(AppRoute.NewConversationHome) },
                        onNewConversation = { projectId -> openNewConversation(projectId) },
                        onOpenAutomations = { navigateTo(AppRoute.Automations()) },
                        onOpenCustomizations = {
                            val activeProjName = workspaceState.projects
                                .firstOrNull { it.id == workspaceState.selectedProjectId }?.name ?: "ledger-svc"
                            navigateTo(AppRoute.RulesAndSkills(activeProjName))
                        },
                        onOpenDisplayOptions = { navigateTo(AppRoute.DisplayOptions(expandSortMenu = false)) },
                        onOpenNewProject = { navigateTo(AppRoute.CreateProject) },
                        onOpenProjectDetail = { projectId ->
                            coordinator.workspaceStore.selectProject(projectId)
                            navigateTo(AppRoute.ProjectDetail(projectId))
                        },
                        onOpenConversation = { cascadeId -> openConversation(cascadeId) },
                        onLongPressConversation = { cascadeId -> navigateTo(AppRoute.ContextMenu(cascadeId)) },
                        onOpenSettings = { navigateTo(AppRoute.Settings) },
                    )
                }

                is AppRoute.DisplayOptions -> {
                    DisplayOptionsOverlayScreen(
                        coordinator = coordinator,
                        onDismiss = { navigateTo(AppRoute.SidebarDrawer) },
                        initialSortMenuExpanded = route.expandSortMenu,
                    )
                }

                is AppRoute.ContextMenu -> {
                    ConversationContextSheetScreen(
                        coordinator = coordinator,
                        targetCascadeId = route.cascadeId,
                        onDismiss = { navigateTo(AppRoute.SidebarDrawer) },
                    )
                }

                is AppRoute.ProjectDetail -> {
                    val projName = workspaceState.projects.firstOrNull { it.id == route.projectId }?.name ?: route.projectId
                    ProjectDetailScreen(
                        coordinator = coordinator,
                        projectId = route.projectId,
                        onBack = { navigateTo(AppRoute.SidebarDrawer) },
                        onNewConversation = { openNewConversation(projectId = route.projectId) },
                        onOpenConversation = { cascadeId -> openConversation(cascadeId) },
                        onOpenAutomationDetail = { automationId ->
                            coordinator.workspaceStore.selectAutomation(automationId)
                            navigateTo(AppRoute.AutomationDetail(automationId))
                        },
                        onOpenRulesAndSkills = {
                            navigateTo(AppRoute.RulesAndSkills(projectName = projName))
                        },
                    )
                }

                AppRoute.CreateProject -> {
                    CreateProjectScreen(
                        coordinator = coordinator,
                        onDismiss = { navigateTo(AppRoute.SidebarDrawer) },
                        onCreated = { navigateTo(AppRoute.SidebarDrawer) },
                    )
                }

                is AppRoute.Automations -> {
                    AutomationsScreen(
                        coordinator = coordinator,
                        onOpenSidebar = { navigateTo(AppRoute.SidebarDrawer) },
                        onOpenAutomationDetail = { automationId ->
                            coordinator.workspaceStore.selectAutomation(automationId)
                            navigateTo(AppRoute.AutomationDetail(automationId))
                        },
                        onEditAutomation = { automationId ->
                            coordinator.workspaceStore.selectAutomation(automationId)
                            navigateTo(AppRoute.AutomationEdit(automationId))
                        },
                        initialExpandedMenuAutomationId = route.expandedMenuId,
                    )
                }

                is AppRoute.AutomationDetail -> {
                    AutomationDetailScreen(
                        coordinator = coordinator,
                        automationId = route.automationId,
                        onBack = { navigateBack() },
                        onEdit = { aid -> navigateTo(AppRoute.AutomationEdit(aid)) },
                        onOpenConversation = { cascadeId -> openConversation(cascadeId) },
                    )
                }

                is AppRoute.AutomationEdit -> {
                    AutomationEditScreen(
                        coordinator = coordinator,
                        automationId = route.automationId,
                        onDismiss = { navigateTo(AppRoute.AutomationDetail(route.automationId)) },
                        onDeleted = { navigateTo(AppRoute.Automations()) },
                    )
                }

                is AppRoute.CascadeChat -> {
                    Box(modifier = Modifier.fillMaxSize()) {
                        CascadeChatScreen(
                            coordinator = coordinator,
                            onBack = { navigateBack() },
                            onOpenSidebar = { navigateTo(AppRoute.SidebarDrawer) },
                            onOpenDiffReview = { navigateTo(AppRoute.TurnDiffReview) },
                            onOpenPlanReview = { navigateTo(AppRoute.PlanReview) },
                            onOpenAddContext = { activeChatOverlay = ChatOverlaySheet.ADD_CONTEXT },
                            onOpenModelAndMode = { activeChatOverlay = ChatOverlaySheet.MODEL_AND_MODE },
                            onOpenPermissionsPreset = { activeChatOverlay = ChatOverlaySheet.PERMISSIONS_PRESET },
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
                                    showHomeBackdrop = false,
                                )
                            }

                            ChatOverlaySheet.MODEL_AND_MODE -> {
                                ModelAndModeSheetScreen(
                                    coordinator = coordinator,
                                    onDismiss = { activeChatOverlay = ChatOverlaySheet.NONE },
                                    showHomeBackdrop = false,
                                )
                            }

                            ChatOverlaySheet.PERMISSIONS_PRESET -> {
                                PermissionsPresetOverlayScreen(
                                    coordinator = coordinator,
                                    onDismiss = { activeChatOverlay = ChatOverlaySheet.NONE },
                                    onOpenSettings = { navigateTo(AppRoute.Settings) },
                                    showHomeBackdrop = false,
                                )
                            }

                            ChatOverlaySheet.SLASH_MENU -> {
                                SlashMenuOverlayScreen(
                                    coordinator = coordinator,
                                    onSelectCommand = { cmd ->
                                        coordinator.chatStore.setDraftInputText("$cmd ")
                                        activeChatOverlay = ChatOverlaySheet.NONE
                                    },
                                    onDismiss = { activeChatOverlay = ChatOverlaySheet.NONE },
                                    showHomeBackdrop = false,
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

                AppRoute.PermissionsPreset -> {
                    PermissionsPresetOverlayScreen(
                        coordinator = coordinator,
                        onDismiss = { navigateTo(AppRoute.NewConversationHome) },
                        onOpenSettings = { navigateTo(AppRoute.Settings) },
                        showHomeBackdrop = true,
                    )
                }

                AppRoute.AddContext -> {
                    AddContextSheetScreen(
                        coordinator = coordinator,
                        onDismiss = { navigateTo(AppRoute.NewConversationHome) },
                        showHomeBackdrop = true,
                    )
                }

                is AppRoute.SlashMenu -> {
                    SlashMenuOverlayScreen(
                        coordinator = coordinator,
                        onSelectCommand = { cmd ->
                            coordinator.chatStore.setDraftInputText("$cmd ")
                            navigateTo(AppRoute.NewConversationHome)
                        },
                        onDismiss = { navigateTo(AppRoute.NewConversationHome) },
                        includeSideQuestionPreview = route.includeSideQuestionPreview,
                        showHomeBackdrop = true,
                    )
                }

                AppRoute.ModelAndMode -> {
                    ModelAndModeSheetScreen(
                        coordinator = coordinator,
                        onDismiss = { navigateTo(AppRoute.NewConversationHome) },
                        showHomeBackdrop = true,
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

                is AppRoute.RulesAndSkills -> {
                    ProjectRulesAndSkillsScreen(
                        coordinator = coordinator,
                        projectName = route.projectName,
                        onBack = { navigateBack() },
                    )
                }

                AppRoute.Settings -> {
                    SettingsAndCustomizationsScreen(
                        coordinator = coordinator,
                        onOpenPairing = { navigateTo(AppRoute.Pairing) },
                        onBack = { navigateTo(AppRoute.SidebarDrawer) },
                    )
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
                                    navigateTo(AppRoute.NewConversationHome)
                                }
                            }
                        },
                        onContinueDemo = {
                            EsddVerificationFixtures.seedCoordinator(coordinator)
                            navigateTo(AppRoute.NewConversationHome)
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
                                                navigateTo(AppRoute.NewConversationHome)
                                            } else if (result.exceptionOrNull() is dev.antigravity.shared.protocol.AntigravityRpcError.Unauthorized) {
                                                navigateTo(AppRoute.CloudRelaySignIn(relayTarget.canonicalRelayUrlString))
                                            }
                                        }
                                    }
                                } else {
                                    scope.launch {
                                        runCatching {
                                            coordinator.connectWithPairingUri(trimmed)
                                            navigateTo(AppRoute.NewConversationHome)
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
                            currentRoute = AppRoute.Pairing
                            scope.launch {
                                val result = runCatching {
                                    coordinator.connectCloudRelay(
                                        relayUrlString = route.targetRelayUrl,
                                        sessionCookie = captured.cookieHeader,
                                        authUser = captured.authUser,
                                        relayApiKey = captured.relayApiKey,
                                    )
                                }
                                if (result.isSuccess) {
                                    navigateTo(AppRoute.NewConversationHome)
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

private fun routeForVerifyScene(scene: EsddVerifySceneCase): AppRoute = when (scene) {
    EsddVerifySceneCase.AGENTS_HOME -> AppRoute.NewConversationHome
    EsddVerifySceneCase.SIDEBAR_DRAWER -> AppRoute.SidebarDrawer
    EsddVerifySceneCase.DISPLAY_OPTIONS -> AppRoute.DisplayOptions(expandSortMenu = true)
    EsddVerifySceneCase.CONTEXT_MENU_PIN -> AppRoute.ContextMenu("cas-flaky-settlement")
    EsddVerifySceneCase.PROJECT_DETAIL -> AppRoute.ProjectDetail("ledger-svc")
    EsddVerifySceneCase.CREATE_PROJECT -> AppRoute.CreateProject
    EsddVerifySceneCase.AUTOMATIONS -> AppRoute.Automations(expandedMenuId = "auto-nightly-audit")
    EsddVerifySceneCase.AUTOMATION_DETAIL -> AppRoute.AutomationDetail("auto-nightly-audit")
    EsddVerifySceneCase.AUTOMATION_EDIT -> AppRoute.AutomationEdit("auto-nightly-audit")
    EsddVerifySceneCase.CHAT_AND_COMPOSER -> AppRoute.CascadeChat("cas-rate-limiter")
    EsddVerifySceneCase.PERMISSIONS_PRESET -> AppRoute.PermissionsPreset
    EsddVerifySceneCase.ADD_CONTEXT -> AppRoute.AddContext
    EsddVerifySceneCase.SLASH_MENU -> AppRoute.SlashMenu(includeSideQuestionPreview = true)
    EsddVerifySceneCase.MODEL_AND_MODE -> AppRoute.ModelAndMode
    EsddVerifySceneCase.STRUCTURED_QUESTION -> AppRoute.StructuredQuestion
    EsddVerifySceneCase.PLAN_REVIEW -> AppRoute.PlanReview
    EsddVerifySceneCase.TURN_DIFF_REVIEW -> AppRoute.TurnDiffReview
    EsddVerifySceneCase.LIVE_ACTIVITY_SPEC -> AppRoute.LiveUpdatesSpec
    EsddVerifySceneCase.RULES_AND_SKILLS -> AppRoute.RulesAndSkills("ledger-svc")
    EsddVerifySceneCase.SETTINGS -> AppRoute.Settings
}
