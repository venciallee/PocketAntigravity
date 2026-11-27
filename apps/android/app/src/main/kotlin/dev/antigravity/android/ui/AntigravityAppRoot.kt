package dev.antigravity.android.ui

import android.util.Log
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.util.addPointerInputChange
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
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
import dev.antigravity.android.ui.home.AgentsSidebarDrawerContent
import dev.antigravity.android.ui.home.ConversationContextSheetScreen
import dev.antigravity.android.ui.home.DisplayOptionsOverlayScreen
import dev.antigravity.android.ui.liveprogress.AndroidLiveUpdatesSpecGallery
import dev.antigravity.android.ui.liveprogress.defaultLiveProgressSpecSnapshot
import dev.antigravity.android.ui.pairing.CloudRelaySignInScreen
import dev.antigravity.android.ui.pairing.RemoteControlLinkDialog
import dev.antigravity.android.ui.pairing.SettingsAndCustomizationsScreen
import dev.antigravity.android.ui.pairing.WelcomeAndPairingScreen
import dev.antigravity.android.ui.projects.CreateProjectScreen
import dev.antigravity.android.ui.projects.ProjectRulesAndSkillsScreen
import dev.antigravity.android.ui.review.ImplementationPlanReviewScreen
import dev.antigravity.android.ui.review.TurnDiffReviewScreen
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.domain.EsddVerificationFixtures
import dev.antigravity.shared.model.AppAppearanceMode
import dev.antigravity.shared.model.AppThemePreset
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.EsddVerifySceneCase
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.RemoteHostInstance
import dev.antigravity.shared.protocol.SapisidHashGenerator
import kotlin.math.abs
import kotlinx.coroutines.launch

private sealed interface AppRoute {
    data object NewConversationHome : AppRoute
    data class DisplayOptions(val expandSortMenu: Boolean = false) : AppRoute
    data class ContextMenu(val cascadeId: String) : AppRoute
    data object CreateProject : AppRoute
    data class Automations(val expandedMenuId: String? = null) : AppRoute
    data class AutomationDetail(val automationId: String) : AppRoute
    data class AutomationEdit(val automationId: String) : AppRoute
    data class CascadeChat(val cascadeId: String) : AppRoute
    data class PermissionsPreset(val isRemote: Boolean = false) : AppRoute
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
 * New Conversation Home + Interactive Left Modal Navigation Drawer (with left-to-right swipe open
 * and right-to-left swipe close), v2.33 orchestration sheets, and pairing/settings flows.
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
    val chatState by coordinator.chatState.collectAsState()
    val syncState by coordinator.syncState.collectAsState()
    val workspaceState by coordinator.workspaceStore.state.collectAsState()
    val scope = rememberCoroutineScope()
    val keyboardController = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current

    val appearance = settingsState.appearance
    val resolvedPreset = themePresetOverride ?: appearance.theme
    val resolvedDark = darkThemeOverride ?: when (appearance.appearanceMode) {
        AppAppearanceMode.DARK -> true
        AppAppearanceMode.LIGHT -> false
        AppAppearanceMode.SYSTEM -> isSystemInDarkTheme()
    }

    val startsWithSidebarOpen = initialVerifyScene == EsddVerifySceneCase.SIDEBAR_DRAWER
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
    var chatOriginRoute by remember(initialVerifyScene) { mutableStateOf<AppRoute>(AppRoute.NewConversationHome) }
    var activeChatOverlay by remember(initialVerifyScene) { mutableStateOf(ChatOverlaySheet.NONE) }
    var isDrawerOpen by remember(initialVerifyScene) { mutableStateOf(startsWithSidebarOpen) }
    val drawerProgress = remember(initialVerifyScene) { Animatable(if (startsWithSidebarOpen) 1f else 0f) }
    var dragDrawerProgress by remember(initialVerifyScene) { mutableStateOf<Float?>(null) }
    var showRemoteLinkDialog by remember { mutableStateOf(false) }
    var userExplicitlyOpenedPairing by remember { mutableStateOf(false) }
    var stepSyncRetryNonce by remember { mutableStateOf(0) }

    fun dismissKeyboard() {
        keyboardController?.hide()
        focusManager.clearFocus()
    }

    fun openDrawer(immediate: Boolean = false) {
        dismissKeyboard()
        isDrawerOpen = true
        dragDrawerProgress = null
        if (!coordinator.isVerificationMode) {
            coordinator.scheduleConversationPreload()
        }
        scope.launch {
            if (immediate) {
                drawerProgress.snapTo(1f)
            } else {
                drawerProgress.animateTo(
                    targetValue = 1f,
                    animationSpec = spring(dampingRatio = 0.94f, stiffness = 380f),
                )
            }
        }
    }

    LaunchedEffect(isDrawerOpen) {
        if (isDrawerOpen && !coordinator.isVerificationMode) {
            coordinator.scheduleConversationPreload()
        }
    }

    fun closeDrawer(immediate: Boolean = false) {
        dismissKeyboard()
        isDrawerOpen = false
        dragDrawerProgress = null
        scope.launch {
            if (immediate) {
                drawerProgress.snapTo(0f)
            } else {
                drawerProgress.animateTo(
                    targetValue = 0f,
                    animationSpec = spring(dampingRatio = 0.94f, stiffness = 440f),
                )
            }
        }
    }

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

    fun isCloudConversation(cascadeId: String, summary: CascadeSummary?): Boolean =
        coordinator.isSummaryCloudRuntime(cascadeId, summary)

    LaunchedEffect(chatState.activeCascadeId, currentRoute) {
        val route = currentRoute
        val activeCid = chatState.activeCascadeId
        if (!coordinator.isVerificationMode &&
            route is AppRoute.CascadeChat &&
            activeCid.isNotBlank() &&
            activeCid != route.cascadeId &&
            !chatState.stepsByCascadeId.containsKey(route.cascadeId)
        ) {
            currentRoute = AppRoute.CascadeChat(activeCid)
        }
    }

    val activeChatRouteId = (currentRoute as? AppRoute.CascadeChat)?.cascadeId
    val activeChatSummary = remember(activeChatRouteId, syncState.summaries) {
        if (activeChatRouteId.isNullOrBlank()) null
        else syncState.summaries.firstOrNull { it.cascadeId == activeChatRouteId }
    }
    var lastHandledStepRetryNonce by remember { mutableStateOf(0) }
    LaunchedEffect(
        activeChatRouteId,
        activeChatSummary?.stepCount,
        activeChatSummary?.status,
        stepSyncRetryNonce,
    ) {
        val cid = activeChatRouteId ?: return@LaunchedEffect
        if (coordinator.isVerificationMode || cid.startsWith("cascade-new-")) return@LaunchedEffect
        val isManualRetry = stepSyncRetryNonce != lastHandledStepRetryNonce
        lastHandledStepRetryNonce = stepSyncRetryNonce
        val summary = activeChatSummary
        val resolvedIsCloud = isCloudConversation(cid, summary)
        runCatching {
            if (isManualRetry) {
                coordinator.forceSyncSteps(
                    cascadeId = cid,
                    knownStepCount = summary?.stepCount ?: 0,
                    isCloud = resolvedIsCloud,
                    instanceUuidOverride = summary?.originInstanceUuid,
                )
            } else {
                coordinator.syncSteps(
                    cascadeId = cid,
                    knownStepCount = summary?.stepCount ?: 0,
                    isCloud = resolvedIsCloud,
                    instanceUuidOverride = summary?.originInstanceUuid,
                )
            }
        }
    }

    fun navigateTo(destination: AppRoute, keepDrawerOpen: Boolean = false) {
        dismissKeyboard()
        if (destination is AppRoute.CascadeChat || destination == AppRoute.StructuredQuestion) {
            when (currentRoute) {
                AppRoute.NewConversationHome,
                is AppRoute.Automations,
                is AppRoute.AutomationDetail,
                -> chatOriginRoute = currentRoute

                else -> Unit
            }
        }
        previousRoute = currentRoute
        activeChatOverlay = ChatOverlaySheet.NONE
        if (!keepDrawerOpen && (isDrawerOpen || drawerProgress.value > 0.001f)) {
            closeDrawer(immediate = true)
        }
        if (destination == AppRoute.Pairing) {
            userExplicitlyOpenedPairing = true
        } else if (destination == AppRoute.NewConversationHome) {
            userExplicitlyOpenedPairing = false
        }
        currentRoute = destination
    }

    fun returnToSidebarDrawer() {
        navigateTo(AppRoute.NewConversationHome, keepDrawerOpen = true)
        openDrawer(immediate = true)
    }

    fun openNewConversation(projectId: String = "") {
        val matchedProject = if (projectId.isNotBlank()) {
            coordinator.workspaceStore.selectProject(projectId)
            (workspaceState.projects + syncState.projects).firstOrNull {
                it.id == projectId || it.name == projectId
            }
        } else {
            null
        }
        if (coordinator.isVerificationMode) {
            navigateTo(AppRoute.NewConversationHome)
            return
        }
        val matchedIsCloud = matchedProject?.runtime == ProjectRuntimeTarget.CLOUD
        val draftId = coordinator.createLocalDraftConversation(
            workspaceUri = matchedProject?.workspaceUri.orEmpty(),
            projectSlug = matchedProject?.id ?: projectId,
            isCloud = if (matchedProject != null) matchedIsCloud else null,
            cloudProjectId = matchedProject?.cloudProjectId,
            originInstanceUuid = matchedProject?.originInstanceUuid,
            originHostName = if (matchedIsCloud) "Antigravity" else matchedProject?.hostName,
            branchName = matchedProject?.activeBranch,
        )
        navigateTo(AppRoute.CascadeChat(draftId))
    }

    fun openConversation(cascadeId: String) {
        val shouldPreMarkLoading = !coordinator.isVerificationMode &&
            connectionState.isConnected &&
            connectionState.isDeviceNetworkReachable
        coordinator.chatStore.setActiveCascade(cascadeId, markLoadingIfEmpty = shouldPreMarkLoading)
        if (coordinator.isVerificationMode && cascadeId == "cas-audit-log-admin") {
            navigateTo(AppRoute.StructuredQuestion)
        } else {
            navigateTo(AppRoute.CascadeChat(cascadeId))
        }
    }

    fun navigateBack() {
        if (isDrawerOpen) {
            closeDrawer()
            return
        }
        if (activeChatOverlay != ChatOverlaySheet.NONE) {
            activeChatOverlay = ChatOverlaySheet.NONE
            return
        }
        currentRoute = when (val route = currentRoute) {
            AppRoute.NewConversationHome -> AppRoute.NewConversationHome
            is AppRoute.DisplayOptions,
            is AppRoute.ContextMenu,
            AppRoute.CreateProject,
            is AppRoute.Automations,
            is AppRoute.PermissionsPreset,
            AppRoute.AddContext,
            is AppRoute.SlashMenu,
            AppRoute.ModelAndMode,
            AppRoute.LiveUpdatesSpec,
            AppRoute.Settings,
            AppRoute.Pairing,
            -> AppRoute.NewConversationHome

            is AppRoute.AutomationDetail -> AppRoute.Automations()

            is AppRoute.AutomationEdit -> AppRoute.AutomationDetail(route.automationId)

            is AppRoute.RulesAndSkills -> AppRoute.NewConversationHome

            is AppRoute.CloudRelaySignIn -> AppRoute.Pairing

            is AppRoute.CascadeChat,
            AppRoute.StructuredQuestion,
            -> chatOriginRoute

            AppRoute.PlanReview,
            AppRoute.TurnDiffReview,
            -> AppRoute.CascadeChat(coordinator.chatState.value.activeCascadeId.ifBlank { "cas-rate-limiter" })
        }
    }

    BackHandler(enabled = isDrawerOpen || currentRoute != AppRoute.NewConversationHome || activeChatOverlay != ChatOverlaySheet.NONE) {
        navigateBack()
    }

    val canSwipeOpenDrawer = !isDrawerOpen && when (currentRoute) {
        AppRoute.NewConversationHome,
        is AppRoute.Automations,
        AppRoute.Settings,
        -> true

        else -> false
    }
    val latestIsDrawerOpen by rememberUpdatedState(isDrawerOpen)
    val latestCanSwipeOpen by rememberUpdatedState(canSwipeOpenDrawer)

    AntigravityTheme(
        preset = resolvedPreset,
        darkTheme = resolvedDark,
        useDynamicColor = appearance.useDynamicColor,
        language = appearance.language,
    ) {
        val colors = LocalAntigravityColors.current
        val density = LocalDensity.current
        val isRtl = LocalLayoutDirection.current == LayoutDirection.Rtl

        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.canvasObsidian),
        ) {
            val drawerWidthPx = remember(maxWidth, density) {
                with(density) { (maxWidth * 0.815f).toPx().coerceAtLeast(1f) }
            }
            val leadingEdgeBandPx = remember(density) {
                with(density) { 40.dp.toPx() }
            }

            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(isRtl, drawerWidthPx, leadingEdgeBandPx) {
                        val touchSlop = viewConfiguration.touchSlop
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            val drawerOpenAtDown = latestIsDrawerOpen
                            val canOpenAtDown = latestCanSwipeOpen
                            if (!drawerOpenAtDown && !canOpenAtDown) {
                                return@awaitEachGesture
                            }

                            val leadingStartX = if (isRtl) (size.width - down.position.x) else down.position.x
                            val isLeadingEdgeStart = !drawerOpenAtDown && leadingStartX <= leadingEdgeBandPx
                            val detectPass = if (isLeadingEdgeStart) PointerEventPass.Initial else PointerEventPass.Main

                            var locked = false
                            var startDragX = down.position.x
                            var activePointerId = down.id

                            while (true) {
                                val event = awaitPointerEvent(detectPass)
                                val change = event.changes.firstOrNull { it.id == activePointerId } ?: break
                                if (!change.pressed) {
                                    break
                                }
                                if (!isLeadingEdgeStart && change.isConsumed) {
                                    break
                                }
                                val totalDx = change.position.x - down.position.x
                                val totalDy = change.position.y - down.position.y
                                val signedDx = if (isRtl) -totalDx else totalDx

                                if (abs(totalDy) > touchSlop && abs(totalDy) >= abs(totalDx)) {
                                    // Yield immediately to vertical scrolling.
                                    break
                                }
                                if (abs(totalDx) > touchSlop && abs(totalDx) > abs(totalDy) * 1.15f) {
                                    val matchesDirection = if (drawerOpenAtDown) signedDx < 0f else signedDx > 0f
                                    if (!matchesDirection) {
                                        break
                                    }
                                    locked = true
                                    startDragX = down.position.x
                                    dismissKeyboard()
                                    val baseline = (dragDrawerProgress ?: drawerProgress.value).coerceIn(0f, 1f)
                                    val initialProgress = (baseline + signedDx / drawerWidthPx).coerceIn(0f, 1f)
                                    dragDrawerProgress = initialProgress
                                    change.consume()

                                    val velocityTracker = VelocityTracker()
                                    velocityTracker.addPointerInputChange(down)
                                    velocityTracker.addPointerInputChange(change)

                                    while (true) {
                                        val dragEvent = awaitPointerEvent(detectPass)
                                        val dragChange = dragEvent.changes.firstOrNull { it.id == activePointerId } ?: break
                                        velocityTracker.addPointerInputChange(dragChange)
                                        if (!dragChange.pressed) {
                                            break
                                        }
                                        val dragDelta = dragChange.position.x - startDragX
                                        val signedDragDelta = if (isRtl) -dragDelta else dragDelta
                                        val updatedProgress = (baseline + signedDragDelta / drawerWidthPx).coerceIn(0f, 1f)
                                        dragDrawerProgress = updatedProgress
                                        dragChange.consume()
                                    }

                                    val rawVx = velocityTracker.calculateVelocity().x
                                    val signedVx = if (isRtl) -rawVx else rawVx
                                    val finalProgress = (dragDrawerProgress ?: drawerProgress.value).coerceIn(0f, 1f)
                                    val shouldOpen = if (baseline < 0.5f) {
                                        finalProgress >= 0.28f || (signedVx >= 600f && finalProgress > 0.04f)
                                    } else {
                                        !(finalProgress <= 0.72f || (signedVx <= -600f && finalProgress < 0.96f))
                                    }
                                    isDrawerOpen = shouldOpen
                                    val normalizedVelocity = (signedVx / drawerWidthPx).coerceIn(-12f, 12f)
                                    scope.launch {
                                        drawerProgress.snapTo(finalProgress)
                                        dragDrawerProgress = null
                                        drawerProgress.animateTo(
                                            targetValue = if (shouldOpen) 1f else 0f,
                                            initialVelocity = normalizedVelocity,
                                            animationSpec = spring(dampingRatio = 0.94f, stiffness = 400f),
                                        )
                                    }
                                    break
                                }
                            }
                            if (!locked) {
                                // Tap or vertical scroll: leave gesture unconsumed.
                            }
                        }
                    },
            ) {
                when (val route = currentRoute) {
                    AppRoute.NewConversationHome -> {
                        AgentsHomeScreen(
                            coordinator = coordinator,
                            onOpenSidebar = { openDrawer() },
                            onOpenConversation = { cascadeId -> openConversation(cascadeId) },
                            onOpenAddContext = { navigateTo(AppRoute.AddContext) },
                            onOpenModelPicker = { navigateTo(AppRoute.ModelAndMode) },
                            onOpenPermissionsPreset = { isRemote ->
                                navigateTo(AppRoute.PermissionsPreset(isRemote = isRemote))
                            },
                            onOpenSlashMenu = { navigateTo(AppRoute.SlashMenu(includeSideQuestionPreview = false)) },
                            onOpenVoiceMode = {
                                val targetCascade = coordinator.chatState.value.activeCascadeId
                                    .ifBlank { coordinator.syncState.value.summaries.firstOrNull()?.cascadeId.orEmpty() }
                                    .ifBlank { if (coordinator.isVerificationMode) "cas-rate-limiter" else "" }
                                if (targetCascade.isNotBlank()) {
                                    coordinator.chatStore.setActiveCascade(targetCascade)
                                    currentRoute = AppRoute.CascadeChat(targetCascade)
                                    activeChatOverlay = ChatOverlaySheet.VOICE_MODE
                                }
                            },
                            onOpenReSignIn = {
                                val relayUrl = connectionState.activeHost?.endpointUrl
                                    ?.takeIf { it.startsWith("https://") }
                                    ?: SapisidHashGenerator.DEFAULT_ORIGIN
                                navigateTo(AppRoute.CloudRelaySignIn(relayUrl))
                            },
                            showNeedsApprovalBanner = !startsWithSidebarOpen,
                        )
                    }

                    is AppRoute.DisplayOptions -> {
                        DisplayOptionsOverlayScreen(
                            coordinator = coordinator,
                            onDismiss = { returnToSidebarDrawer() },
                            initialSortMenuExpanded = route.expandSortMenu,
                        )
                    }

                    is AppRoute.ContextMenu -> {
                        ConversationContextSheetScreen(
                            coordinator = coordinator,
                            targetCascadeId = route.cascadeId,
                            onDismiss = { returnToSidebarDrawer() },
                        )
                    }

                    AppRoute.CreateProject -> {
                        CreateProjectScreen(
                            coordinator = coordinator,
                            onDismiss = { returnToSidebarDrawer() },
                            onCreated = { returnToSidebarDrawer() },
                        )
                    }

                    is AppRoute.Automations -> {
                        AutomationsScreen(
                            coordinator = coordinator,
                            onOpenSidebar = { openDrawer() },
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
                                onOpenDiffReview = { navigateTo(AppRoute.TurnDiffReview) },
                                onOpenPlanReview = { navigateTo(AppRoute.PlanReview) },
                                onOpenAddContext = {
                                    dismissKeyboard()
                                    activeChatOverlay = ChatOverlaySheet.ADD_CONTEXT
                                },
                                onOpenModelAndMode = {
                                    dismissKeyboard()
                                    activeChatOverlay = ChatOverlaySheet.MODEL_AND_MODE
                                },
                                onOpenPermissionsPreset = {
                                    dismissKeyboard()
                                    activeChatOverlay = ChatOverlaySheet.PERMISSIONS_PRESET
                                },
                                onOpenOverview = {
                                    dismissKeyboard()
                                    activeChatOverlay = ChatOverlaySheet.OVERVIEW
                                },
                                onOpenSideQuestion = {
                                    dismissKeyboard()
                                    activeChatOverlay = ChatOverlaySheet.SIDE_QUESTION
                                },
                                onOpenSwarmBoard = {
                                    dismissKeyboard()
                                    activeChatOverlay = ChatOverlaySheet.SWARM_BOARD
                                },
                                onOpenVoiceMode = {
                                    dismissKeyboard()
                                    activeChatOverlay = ChatOverlaySheet.VOICE_MODE
                                },
                                onBiometricPrompt = onBiometricPrompt,
                                onRetryLoadSteps = { stepSyncRetryNonce += 1 },
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
                                        isRemote = isCloudConversation(route.cascadeId, activeChatSummary),
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

                    is AppRoute.PermissionsPreset -> {
                        PermissionsPresetOverlayScreen(
                            coordinator = coordinator,
                            onDismiss = { navigateTo(AppRoute.NewConversationHome) },
                            onOpenSettings = { navigateTo(AppRoute.Settings) },
                            isRemote = route.isRemote,
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
                            onBack = { returnToSidebarDrawer() },
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
                                        navigateTo(AppRoute.NewConversationHome)
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

                // Interactive Slide-Over Left Sidebar Drawer Overlay (`UE01B_SIDEBAR_DRAWER`)
                val showDrawerLayer by remember(initialVerifyScene) {
                    derivedStateOf {
                        isDrawerOpen || dragDrawerProgress != null || drawerProgress.value > 0.001f
                    }
                }
                val scrimClickable by remember(initialVerifyScene) {
                    derivedStateOf {
                        isDrawerOpen || (dragDrawerProgress ?: drawerProgress.value) > 0.05f
                    }
                }

                if (showDrawerLayer) {
                    val baseScrimAlpha = if (colors.isDark) 0.62f else 0.36f
                    val scrimInteraction = remember { MutableInteractionSource() }

                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .graphicsLayer {
                                alpha = (dragDrawerProgress ?: drawerProgress.value).coerceIn(0f, 1f)
                            }
                            .background(Color.Black.copy(alpha = baseScrimAlpha))
                            .testTag("sidebar-scrim")
                            .clickable(
                                enabled = scrimClickable,
                                interactionSource = scrimInteraction,
                                indication = null,
                                onClick = { closeDrawer() },
                            ),
                    )

                    Surface(
                        modifier = Modifier
                            .fillMaxHeight()
                            .fillMaxWidth(0.815f)
                            .align(Alignment.CenterStart)
                            .graphicsLayer {
                                val progress = (dragDrawerProgress ?: drawerProgress.value).coerceIn(0f, 1f)
                                val sign = if (isRtl) 1f else -1f
                                translationX = sign * drawerWidthPx * (1f - progress)
                            }
                            .testTag("sidebar-drawer"),
                        shape = RoundedCornerShape(topEnd = 20.dp, bottomEnd = 20.dp),
                        color = colors.surfaceObsidian,
                        border = BorderStroke(1.dp, colors.subtleDivider),
                    ) {
                        AgentsSidebarDrawerContent(
                            coordinator = coordinator,
                            onNewConversation = { projectId ->
                                closeDrawer(immediate = true)
                                openNewConversation(projectId)
                            },
                            onOpenAutomations = {
                                closeDrawer(immediate = true)
                                navigateTo(AppRoute.Automations())
                            },
                            onOpenCustomizations = {
                                closeDrawer(immediate = true)
                                val activeProjName = workspaceState.projects
                                    .firstOrNull { it.id == workspaceState.selectedProjectId }?.name ?: "ledger-svc"
                                navigateTo(AppRoute.RulesAndSkills(activeProjName))
                            },
                            onOpenDisplayOptions = {
                                closeDrawer(immediate = true)
                                navigateTo(AppRoute.DisplayOptions(expandSortMenu = false))
                            },
                            onOpenNewProject = {
                                closeDrawer(immediate = true)
                                navigateTo(AppRoute.CreateProject)
                            },
                            onSelectProject = { projectId ->
                                closeDrawer(immediate = true)
                                coordinator.workspaceStore.selectProject(projectId)
                                navigateTo(AppRoute.NewConversationHome)
                            },
                            onOpenProjectCustomizations = { projectId, projectName ->
                                closeDrawer(immediate = true)
                                coordinator.workspaceStore.selectProject(projectId)
                                navigateTo(AppRoute.RulesAndSkills(projectName))
                            },
                            onRevealProjectInFinder = { projectId ->
                                scope.launch {
                                    runCatching { coordinator.revealProjectInFinder(projectId) }
                                }
                            },
                            onOpenConversation = { cascadeId ->
                                closeDrawer(immediate = true)
                                openConversation(cascadeId)
                            },
                            onLongPressConversation = { cascadeId ->
                                closeDrawer(immediate = true)
                                navigateTo(AppRoute.ContextMenu(cascadeId))
                            },
                            onOpenSettings = {
                                closeDrawer(immediate = true)
                                navigateTo(AppRoute.Settings)
                            },
                            activeHighlightCascadeId = activeChatRouteId ?: "cas-rate-limiter",
                        )
                    }
                }
            }
        }
    }
}

private fun routeForVerifyScene(scene: EsddVerifySceneCase): AppRoute = when (scene) {
    EsddVerifySceneCase.AGENTS_HOME -> AppRoute.NewConversationHome
    EsddVerifySceneCase.SIDEBAR_DRAWER -> AppRoute.NewConversationHome
    EsddVerifySceneCase.DISPLAY_OPTIONS -> AppRoute.DisplayOptions(expandSortMenu = true)
    EsddVerifySceneCase.CONTEXT_MENU_PIN -> AppRoute.ContextMenu("cas-flaky-settlement")
    EsddVerifySceneCase.CREATE_PROJECT -> AppRoute.CreateProject
    EsddVerifySceneCase.AUTOMATIONS -> AppRoute.Automations(expandedMenuId = "auto-nightly-audit")
    EsddVerifySceneCase.AUTOMATION_DETAIL -> AppRoute.AutomationDetail("auto-nightly-audit")
    EsddVerifySceneCase.AUTOMATION_EDIT -> AppRoute.AutomationEdit("auto-nightly-audit")
    EsddVerifySceneCase.CHAT_AND_COMPOSER -> AppRoute.CascadeChat("cas-rate-limiter")
    EsddVerifySceneCase.PERMISSIONS_PRESET -> AppRoute.PermissionsPreset(isRemote = false)
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
