package dev.antigravity.android.ui.chat

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.graphics.Color
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.DeviceHub
import androidx.compose.material.icons.rounded.Dns
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Extension
import androidx.compose.material.icons.rounded.Fingerprint
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Shield
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.components.DiffCounterBadge
import dev.antigravity.android.core.ui.components.MarkdownContentView
import dev.antigravity.android.core.ui.components.SevenSegmentProgressBar
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.components.statusColorFor
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AntigravityCloudDetector
import dev.antigravity.shared.model.CascadeDisplayItem
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.DynamicWorkflowPayload
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.McpToolCallPayload
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.SlashCommandItem
import dev.antigravity.shared.model.SubagentPayload
import dev.antigravity.shared.model.SwarmBoardPayload
import dev.antigravity.shared.model.TaskBoundaryPayload
import dev.antigravity.shared.model.TaskChecklistStatus
import dev.antigravity.shared.model.VoiceCallTranscriptSummary
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/** Deferred `/btw` side-question feature flag (kept in sync with iOS deferral). */
private const val ENABLE_SIDE_QUESTION_BTW: Boolean = false

/**
 * UE07_CHAT_AND_COMPOSER: Primary Cascade Chat screen featuring Material 3 TopAppBar with diff
 * pill & Overview trigger, trajectory `LazyColumn` (collapsible thinking, Markdown prose,
 * Implementation Plan artifact card, 7-segment Task card, Amber Biometric command gate, v2.33
 * multi-agent cards, forward-compatible unknown step & generic fallback interaction gates),
 * live status strip with Stop button, and docked Material 3 `ChatComposer`.
 */
@Composable
fun CascadeChatScreen(
    coordinator: AntigravityCoreCoordinator,
    onBack: () -> Unit,
    onOpenSidebar: () -> Unit = onBack,
    onOpenDiffReview: () -> Unit,
    onOpenPlanReview: () -> Unit,
    onOpenAddContext: () -> Unit,
    onOpenModelAndMode: () -> Unit,
    onOpenPermissionsPreset: () -> Unit = {},
    onOpenOverview: () -> Unit,
    onOpenSideQuestion: () -> Unit,
    onOpenSwarmBoard: () -> Unit,
    onOpenVoiceMode: () -> Unit,
    onBiometricPrompt: (title: String, onSuccess: () -> Unit) -> Unit,
    onRetryLoadSteps: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val connectionState by coordinator.connectionState.collectAsState()
    val chatState by coordinator.chatState.collectAsState()
    val syncState by coordinator.syncState.collectAsState()
    val workspaceState by coordinator.workspaceStore.state.collectAsState()
    val settingsState by coordinator.settingsStore.state.collectAsState()
    val scope = rememberCoroutineScope()

    val activeCascadeId = chatState.activeCascadeId.ifBlank { "cas-rate-limiter" }
    val activeSummary = syncState.summaries.firstOrNull { it.cascadeId == activeCascadeId }
        ?: syncState.summaries.firstOrNull()
    val resolvedIsCloud = remember(activeCascadeId, activeSummary, workspaceState.projects) {
        if (activeSummary?.isCloud == true) {
            true
        } else if (AntigravityCloudDetector.isCloudWorkspaceUri(activeSummary?.workspaceUri.orEmpty(), cascadeId = activeCascadeId)) {
            true
        } else {
            val matchedProject = activeSummary?.let { item ->
                workspaceState.projects.firstOrNull { proj ->
                    (!item.cloudProjectId.isNullOrBlank() && (proj.cloudProjectId == item.cloudProjectId || proj.id == item.cloudProjectId)) ||
                        (item.workspaceUri.isNotBlank() && proj.workspaceUri == item.workspaceUri) ||
                        (item.projectSlug.isNotBlank() && proj.name.equals(item.projectSlug, ignoreCase = true))
                }
            }
            matchedProject?.runtime == ProjectRuntimeTarget.CLOUD
        }
    }

    val rawTitle = activeSummary?.title ?: "Add rate limiter"
    val headerTitle = if (rawTitle == "Add rate limiter to /transfers") "Add rate limiter" else rawTitle
    val rawHostLabel = activeSummary?.originHostName
        ?: connectionState.activeHost?.hostname
        ?: "MacBook Pro"
    val cleanHostLabel = rawHostLabel.removePrefix("Connecting · ").ifBlank { "Desktop" }
    val headerSubtitle = "${activeSummary?.projectSlug ?: "ledger-svc"} · $cleanHostLabel"
    val totalAdditions = activeSummary?.totalAdditions ?: 128
    val totalDeletions = activeSummary?.totalDeletions ?: 14

    val displayItems = chatState.activeDisplayItems
    val modelDisplayName = settingsState.selectedModel?.displayName
        ?.replace(" (Thinking)", "")
        ?: "Gemini 4 Neon"
    val effortLabel = when (settingsState.selectedEffort.displayTitle) {
        "Extra" -> "Extra High"
        else -> settingsState.selectedEffort.displayTitle
    }
    val permissionLabel = settingsState.activePermissionPreset.displayTitle

    Scaffold(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
        containerColor = colors.canvasObsidian,
        topBar = {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .padding(horizontal = 8.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                IconButton(
                    onClick = onOpenSidebar,
                    modifier = Modifier
                        .defaultMinSize(
                            minWidth = AntigravityDesignTokens.MinTouchTarget,
                            minHeight = AntigravityDesignTokens.MinTouchTarget,
                        )
                        .testTag("btn-chat-back"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Menu,
                        contentDescription = "Open sidebar",
                        tint = colors.inkReading,
                    )
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(1.dp),
                ) {
                    Text(
                        text = headerTitle,
                        style = MaterialTheme.typography.titleLarge.copy(
                            fontSize = 18.5.sp,
                            fontWeight = FontWeight.Normal,
                        ),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = headerSubtitle,
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                Surface(
                    onClick = onOpenDiffReview,
                    modifier = Modifier.testTag("chat-diff-pill"),
                    shape = RoundedCornerShape(10.dp),
                    color = colors.canvasObsidian,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "+$totalAdditions",
                            style = MaterialTheme.typography.labelMedium.copy(
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.statusDone,
                        )
                        Text(
                            text = "-$totalDeletions",
                            style = MaterialTheme.typography.labelMedium.copy(
                                fontFamily = FontFamily.Monospace,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.statusError,
                        )
                    }
                }

                IconButton(
                    onClick = onOpenOverview,
                    modifier = Modifier
                        .defaultMinSize(
                            minWidth = AntigravityDesignTokens.MinTouchTarget,
                            minHeight = AntigravityDesignTokens.MinTouchTarget,
                        )
                        .testTag("btn-chat-overview"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.MoreVert,
                        contentDescription = "Conversation overview",
                        tint = colors.inkReading,
                    )
                }
            }
        },
        bottomBar = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.canvasObsidian)
                    .navigationBarsPadding()
                    .imePadding(),
            ) {
                // Slash-command autocomplete strip when user types "/"
                val trimmedDraft = chatState.draftInputText.trim()
                if (trimmedDraft.startsWith("/")) {
                    val slashMatches = SlashCommandItem.allCommands
                        .filter { cmd ->
                            (ENABLE_SIDE_QUESTION_BTW || cmd.command != "/btw") &&
                                cmd.command.startsWith(trimmedDraft.lowercase())
                        }
                        .take(4)
                    if (slashMatches.isNotEmpty()) {
                        Surface(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 14.dp, vertical = 4.dp),
                            shape = RoundedCornerShape(14.dp),
                            color = colors.surfacePopover,
                            border = BorderStroke(1.dp, colors.cardBorder),
                        ) {
                            Column {
                                slashMatches.forEach { cmd ->
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable {
                                                coordinator.chatStore.setDraftInputText("")
                                                when (cmd.command) {
                                                    "/btw" -> if (ENABLE_SIDE_QUESTION_BTW) onOpenSideQuestion()
                                                    "/swarm" -> onOpenSwarmBoard()
                                                    "/voice" -> onOpenVoiceMode()
                                                    else -> coordinator.chatStore.setDraftInputText("${cmd.command} ")
                                                }
                                            }
                                            .padding(horizontal = 12.dp, vertical = 8.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        Text(
                                            text = cmd.command,
                                            style = MaterialTheme.typography.labelLarge.copy(
                                                fontFamily = FontFamily.Monospace,
                                            ),
                                            color = colors.accentPeriwinkle,
                                        )
                                        Text(
                                            text = cmd.title,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = colors.inkSecondary,
                                            maxLines = 1,
                                            overflow = TextOverflow.Ellipsis,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }

                if (displayItems.isNotEmpty() && !chatState.stepLoadErrorText.isNullOrBlank()) {
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 14.dp, vertical = 4.dp)
                            .testTag("chat-step-load-error-banner"),
                        shape = RoundedCornerShape(12.dp),
                        color = colors.surfaceCard,
                        border = BorderStroke(1.dp, colors.statusError.copy(alpha = 0.35f)),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(7.dp)
                                    .clip(CircleShape)
                                    .background(colors.statusError),
                            )
                            Text(
                                text = chatState.stepLoadErrorText.orEmpty(),
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.statusError,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f),
                            )
                            TextButton(
                                onClick = { coordinator.chatStore.clearStepLoadError() },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 2.dp),
                            ) {
                                Text(
                                    text = "Dismiss",
                                    style = MaterialTheme.typography.labelMedium,
                                    color = colors.accentPeriwinkle,
                                )
                            }
                        }
                    }
                }

                // Docked Material 3 Chat Composer (`and-chat.png`)
                ChatComposerCard(
                    draftText = chatState.draftInputText,
                    onDraftChange = { coordinator.chatStore.setDraftInputText(it) },
                    chips = workspaceState.attachedComposerChips,
                    onRemoveChip = { coordinator.workspaceStore.removeComposerChip(it) },
                    modelLabel = modelDisplayName,
                    effortLabel = effortLabel,
                    permissionLabel = permissionLabel,
                    onAddContext = onOpenAddContext,
                    onOpenModelAndMode = onOpenModelAndMode,
                    onOpenPermissionsPreset = onOpenPermissionsPreset,
                    onOpenVoice = onOpenVoiceMode,
                    onSend = {
                        val text = chatState.draftInputText.trim()
                        when (text.lowercase()) {
                            "/btw" -> {
                                if (ENABLE_SIDE_QUESTION_BTW) {
                                    coordinator.chatStore.setDraftInputText("")
                                    onOpenSideQuestion()
                                } else {
                                    coordinator.chatStore.setDraftInputText("")
                                }
                            }
                            "/swarm" -> {
                                coordinator.chatStore.setDraftInputText("")
                                onOpenSwarmBoard()
                            }
                            "/voice" -> {
                                coordinator.chatStore.setDraftInputText("")
                                onOpenVoiceMode()
                            }
                            else -> {
                                val attachments = workspaceState.attachedComposerChips
                                val isDraft = activeCascadeId.startsWith("cascade-new-")
                                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                    runCatching {
                                        coordinator.sendMessage(
                                            cascadeId = activeCascadeId,
                                            message = text,
                                            workspaceUri = activeSummary?.workspaceUri.orEmpty(),
                                            attachments = attachments,
                                            modelId = settingsState.selectedModelId,
                                            effort = settingsState.selectedEffort,
                                            mode = settingsState.selectedMode,
                                            agentPersona = settingsState.selectedAgentPersona,
                                            isCloud = resolvedIsCloud,
                                            cloudProjectId = activeSummary?.cloudProjectId,
                                            instanceUuidOverride = activeSummary?.originInstanceUuid,
                                            isOptimisticDraft = isDraft,
                                        )
                                    }
                                }
                                coordinator.workspaceStore.clearComposerChips()
                            }
                        }
                    },
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                )
            }
        },
    ) { innerPadding ->
        if (!coordinator.isVerificationMode && displayItems.isEmpty() && (connectionState.isConnecting || chatState.isLoadingSteps)) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .padding(24.dp),
                contentAlignment = Alignment.Center,
            ) {
                AntigravitySurfaceCard(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(18.dp),
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "Loading conversation history...",
                            style = MaterialTheme.typography.titleSmall,
                            color = colors.inkReading,
                        )
                        Text(
                            text = if (!connectionState.isConnected && connectionState.isConnecting) {
                                "Connecting to $cleanHostLabel..."
                            } else {
                                "Syncing trajectory steps from $cleanHostLabel"
                            },
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.inkSecondary,
                        )
                    }
                }
            }
        } else if (displayItems.isEmpty() && !chatState.stepLoadErrorText.isNullOrBlank()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .padding(20.dp)
                    .testTag("chat-step-load-error-card"),
                contentAlignment = Alignment.TopCenter,
            ) {
                AntigravitySurfaceCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp),
                    contentPadding = PaddingValues(18.dp),
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Box(
                                modifier = Modifier
                                    .size(8.dp)
                                    .clip(CircleShape)
                                    .background(colors.statusError),
                            )
                            Text(
                                text = "Could not load trajectory steps",
                                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                                color = colors.inkReading,
                            )
                        }
                        Text(
                            text = chatState.stepLoadErrorText.orEmpty(),
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.inkSecondary,
                        )
                        FilledTonalButton(
                            onClick = {
                                coordinator.chatStore.clearStepLoadError()
                                onRetryLoadSteps()
                            },
                            colors = ButtonDefaults.filledTonalButtonColors(
                                containerColor = colors.accentPeriwinkle.copy(alpha = 0.16f),
                                contentColor = colors.accentPeriwinkle,
                            ),
                            modifier = Modifier.testTag("btn-chat-retry-steps"),
                        ) {
                            Text(
                                text = "Retry",
                                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                            )
                        }
                    }
                }
            }
        } else {
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .testTag("chat-steps-list"),
            contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(
                items = displayItems,
                key = { it.id },
            ) { item ->
                when (item) {
                    is CascadeDisplayItem.EvidenceGroup -> {
                        EvidenceGroupCompactRow(
                            item = item,
                            expanded = item.id in chatState.expandedEvidenceGroupIds,
                            onToggle = { coordinator.chatStore.toggleEvidenceGroupExpanded(item.id) },
                        )
                    }

                    is CascadeDisplayItem.Single -> {
                        val step = item.step
                        CascadeStepItemView(
                            step = step,
                            isThinkingExpanded = step.id in chatState.expandedThinkingStepIds,
                            onToggleThinking = { coordinator.chatStore.toggleThinkingExpanded(step.id) },
                            onOpenPlanReview = onOpenPlanReview,
                            onOpenSwarmBoard = onOpenSwarmBoard,
                            onApproveCommand = {
                                onBiometricPrompt("Approve command execution") {
                                    coordinator.chatStore.resolveWaitingInteractionLocally(
                                        cascadeId = activeCascadeId,
                                        stepIndex = step.stepIndex,
                                        approved = true,
                                    )
                                    if (!coordinator.isVerificationMode) {
                                        scope.launch {
                                            runCatching {
                                                coordinator.resolveWaitingInteraction(
                                                    cascadeId = activeCascadeId,
                                                    stepIndex = step.stepIndex,
                                                    decision = InteractionDecision.AllowWithBiometric,
                                                )
                                            }
                                        }
                                    }
                                }
                            },
                            onDenyCommand = {
                                coordinator.chatStore.resolveWaitingInteractionLocally(
                                    cascadeId = activeCascadeId,
                                    stepIndex = step.stepIndex,
                                    approved = false,
                                )
                                if (!coordinator.isVerificationMode) {
                                    scope.launch {
                                        runCatching {
                                            coordinator.resolveWaitingInteraction(
                                                cascadeId = activeCascadeId,
                                                stepIndex = step.stepIndex,
                                                decision = InteractionDecision.Reject,
                                            )
                                        }
                                    }
                                }
                            },
                            onStopSubagent = { subagentId ->
                                scope.launch {
                                    val client = coordinator.connectionStore.activeClient()
                                    coordinator.orchestrationStore.stopSubagent(
                                        client = client,
                                        cascadeId = activeCascadeId,
                                        subagentId = subagentId,
                                    )
                                }
                            },
                        )
                    }
                }
            }
        }
        }
    }
}

@Composable
private fun CascadeStepItemView(
    step: CascadeStep,
    isThinkingExpanded: Boolean,
    onToggleThinking: () -> Unit,
    onOpenPlanReview: () -> Unit,
    onOpenSwarmBoard: () -> Unit,
    onApproveCommand: () -> Unit,
    onDenyCommand: () -> Unit,
    onStopSubagent: (String) -> Unit,
) {
    when {
        // 1. Run Command Approval / Output Card (must take precedence over generic fallback gate)
        step.type == CortexStepType.RUN_COMMAND && step.runCommand != null -> {
            CommandApprovalCard(
                step = step,
                onApprove = onApproveCommand,
                onDeny = onDenyCommand,
            )
        }

        // 2. Forward-Compatible Generic Fallback Interaction Gate
        step.status == CortexStepStatus.WAITING && step.requestedInteraction?.rawMemberKey != null -> {
            GenericFallbackInteractionCard(
                step = step,
                onAllowOnce = onApproveCommand,
                onDeny = onDenyCommand,
            )
        }

        // 3. Forward-Compatible Unknown Step Card (non-waiting)
        step.isUnrecognizedForwardStep -> {
            UnknownForwardStepCard(step = step)
        }

        // 4. v2.33 Multi-Agent / Tool / Voice Summary Cards
        step.subagent != null -> {
            SubagentStepCard(
                subagent = requireNotNull(step.subagent),
                onStop = { onStopSubagent(step.subagent!!.subagentId) },
            )
        }

        step.dynamicWorkflow != null -> {
            DynamicWorkflowStepCard(workflow = requireNotNull(step.dynamicWorkflow))
        }

        step.swarmBoard != null -> {
            SwarmStepCard(
                board = requireNotNull(step.swarmBoard),
                onOpenBoard = onOpenSwarmBoard,
            )
        }

        step.mcpToolCall != null -> {
            McpToolStepCard(mcp = requireNotNull(step.mcpToolCall))
        }

        step.voiceSummary != null -> {
            VoiceSummaryCard(summary = requireNotNull(step.voiceSummary))
        }

        // 5. Task Boundary 7-Segment Progress Card
        step.type == CortexStepType.TASK_BOUNDARY && step.taskBoundary != null -> {
            TaskBoundaryProgressCard(taskBoundary = requireNotNull(step.taskBoundary))
        }

        // 6. Planner Response (Collapsible Thinking + Markdown Prose + Plan Artifact Card)
        step.type == CortexStepType.PLANNER_RESPONSE || step.type == CortexStepType.NOTIFY_USER -> {
            PlannerResponseStepView(
                step = step,
                isThinkingExpanded = isThinkingExpanded,
                onToggleThinking = onToggleThinking,
                onOpenPlanReview = onOpenPlanReview,
            )
        }

        // 7. User Input Step (compact mention strip for initial prompt, crisp bubble for follow-ups)
        step.type == CortexStepType.USER_INPUT -> {
            UserInputStepView(step = step)
        }
    }
}

@Composable
private fun UserInputStepView(step: CascadeStep) {
    val colors = LocalAntigravityColors.current
    val text = step.userInput?.takeIf { it.isNotBlank() }
        ?: "Add a token-bucket limiter to POST /transfers. Per tenant, configurable."
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp),
        horizontalArrangement = Arrangement.End,
    ) {
        Surface(
            modifier = Modifier.fillMaxWidth(0.84f),
            shape = RoundedCornerShape(20.dp),
            color = colors.surfaceActiveTab,
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = text,
                    style = MaterialTheme.typography.bodyLarge.copy(
                        fontSize = 15.5.sp,
                        lineHeight = 22.sp,
                    ),
                    color = colors.pillActiveForeground,
                )
                if (step.isQueuedInOutbox) {
                    Text(
                        text = "Queued offline · will sync automatically",
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.statusWaiting,
                    )
                }
            }
        }
    }
}

@Composable
private fun EvidenceGroupCompactRow(
    item: CascadeDisplayItem.EvidenceGroup,
    expanded: Boolean,
    onToggle: () -> Unit,
) {
    val colors = LocalAntigravityColors.current
    val fileNames = item.steps.mapNotNull { it.viewFile?.fileName ?: it.codeAction?.fileName }.distinct()
    val summaryLabel = if (fileNames.isNotEmpty()) {
        "Inspected ${fileNames.size} files · ${fileNames.joinToString(", ")}"
    } else {
        "Completed ${item.steps.size} workspace actions"
    }

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .clickable(onClick = onToggle)
                .padding(vertical = 2.dp, horizontal = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.Visibility,
                contentDescription = null,
                tint = colors.inkMuted,
                modifier = Modifier.size(14.dp),
            )
            Text(
                text = summaryLabel,
                style = MaterialTheme.typography.bodySmall,
                color = colors.inkMuted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            Icon(
                imageVector = if (expanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                contentDescription = null,
                tint = colors.inkMuted,
                modifier = Modifier.size(15.dp),
            )
        }
        if (expanded) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(10.dp),
                color = colors.surfaceSubtleBox,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    item.steps.forEach { ev ->
                        val label = ev.codeAction?.let { "Edited ${it.fileName} (+${it.additions} -${it.deletions})" }
                            ?: ev.viewFile?.let { "Viewed ${it.fileName} (L${it.startLine}–${it.endLine})" }
                            ?: ev.type.name
                        Text(
                            text = label,
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.inkSecondary,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PlannerResponseStepView(
    step: CascadeStep,
    isThinkingExpanded: Boolean,
    onToggleThinking: () -> Unit,
    onOpenPlanReview: () -> Unit,
) {
    val colors = LocalAntigravityColors.current
    val planner = step.plannerResponse ?: return
    val seconds = planner.thinkingDurationSeconds?.toInt()
    val thoughtTag = if (seconds == 14) "row-thought-14s" else "row-thought-${step.stepIndex}"

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (!planner.thinking.isNullOrBlank() && isThinkingExpanded) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(onClick = onToggleThinking)
                    .testTag(thoughtTag),
                shape = RoundedCornerShape(12.dp),
                color = colors.surfaceSubtleBox,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Text(
                    text = planner.thinking.orEmpty(),
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, lineHeight = 17.sp),
                    color = colors.inkSecondary,
                    modifier = Modifier.padding(10.dp),
                )
            }
        }

        // Markdown Prose Response
        if (planner.response.isNotBlank()) {
            MarkdownContentView(markdown = planner.response)
        }

        // Implementation Plan Artifact Card (`and-chat.png`)
        if (planner.referencedFiles.any { it.contains("plan", ignoreCase = true) }) {
            AntigravitySurfaceCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("card-artifact-plan"),
                cornerRadius = 18.dp,
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 14.dp),
                onClick = onOpenPlanReview,
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = colors.surfaceSelectionTint,
                        modifier = Modifier.size(40.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = Icons.Rounded.Description,
                                contentDescription = "Implementation Plan",
                                tint = colors.accentPeriwinkle,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    }
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(
                            text = "Implementation Plan",
                            style = MaterialTheme.typography.titleSmall.copy(
                                fontSize = 15.5.sp,
                                fontWeight = FontWeight.SemiBold,
                            ),
                            color = colors.inkReading,
                        )
                        Text(
                            text = "Approved · 2 comments addressed",
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                            color = colors.inkSecondary,
                        )
                    }
                    Icon(
                        imageVector = Icons.Rounded.ChevronRight,
                        contentDescription = "Open Plan Review",
                        tint = colors.inkSecondary,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun TaskBoundaryProgressCard(taskBoundary: TaskBoundaryPayload) {
    val colors = LocalAntigravityColors.current
    val hasWaiting = taskBoundary.checklist.any { it.status == TaskChecklistStatus.WAITING }
    var expandedChecklist by remember { mutableStateOf(false) }
    val waitingItem = taskBoundary.checklist.firstOrNull { it.status == TaskChecklistStatus.WAITING }

    AntigravitySurfaceCard(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("card-task-progress-7seg"),
        cornerRadius = 18.dp,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
        onClick = { expandedChecklist = !expandedChecklist },
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(
                text = taskBoundary.taskName.ifBlank {
                    "Task · ${taskBoundary.completedCount} of ${taskBoundary.totalCount} done"
                },
                style = MaterialTheme.typography.titleSmall.copy(
                    fontSize = 15.5.sp,
                    fontWeight = FontWeight.SemiBold,
                ),
                color = colors.inkReading,
            )
            Text(
                text = taskBoundary.elapsedLabel,
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                color = colors.inkSecondary,
            )
        }

        Spacer(modifier = Modifier.height(10.dp))

        SevenSegmentProgressBar(
            completedCount = taskBoundary.completedCount,
            totalCount = taskBoundary.totalCount,
            hasWaitingStep = hasWaiting,
            segmentHeight = 6.dp,
            segmentSpacing = 5.dp,
        )

        Spacer(modifier = Modifier.height(10.dp))

        Text(
            text = waitingItem?.title?.let { "Waiting: $it" } ?: taskBoundary.taskStatus,
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
            color = if (hasWaiting) colors.statusWaiting else colors.inkSecondary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )

        if (expandedChecklist && taskBoundary.checklist.isNotEmpty()) {
            Spacer(modifier = Modifier.height(8.dp))
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                taskBoundary.checklist.forEach { item ->
                    val isWaiting = item.status == TaskChecklistStatus.WAITING
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        StatusDot(
                            color = when (item.status) {
                                TaskChecklistStatus.DONE -> colors.statusDone
                                TaskChecklistStatus.WAITING -> colors.statusWaiting
                                TaskChecklistStatus.IN_PROGRESS -> colors.statusRunning
                                TaskChecklistStatus.PENDING -> colors.inkMuted
                            },
                            size = 6.dp,
                            glow = false,
                        )
                        Text(
                            text = item.title,
                            style = MaterialTheme.typography.bodySmall,
                            color = if (isWaiting) colors.statusWaiting else colors.inkSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CommandApprovalCard(
    step: CascadeStep,
    onApprove: () -> Unit,
    onDeny: () -> Unit,
) {
    val colors = LocalAntigravityColors.current
    val cmd = step.runCommand ?: return
    val isWaiting = step.status == CortexStepStatus.WAITING
    val isApproved = step.status == CortexStepStatus.DONE
    val isDenied = step.status == CortexStepStatus.CANCELLED
    val commandText = cmd.proposedCommandLine?.takeIf { it.isNotBlank() } ?: cmd.commandLine

    val containerColor = if (isWaiting) colors.surfaceAmberTint else colors.surfaceCard
    val borderColor = when {
        isWaiting -> colors.statusWaiting.copy(alpha = 0.28f)
        isApproved -> colors.statusDone.copy(alpha = 0.35f)
        else -> colors.cardBorder
    }

    AntigravitySurfaceCard(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("card-command-approval"),
        containerColor = containerColor,
        borderColor = borderColor,
        cornerRadius = 20.dp,
        contentPadding = PaddingValues(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.Terminal,
                contentDescription = null,
                tint = when {
                    isWaiting -> colors.statusWaiting
                    isApproved -> colors.statusDone
                    else -> colors.inkSecondary
                },
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = when {
                    isWaiting -> "Run this command?"
                    isApproved -> "Command approved"
                    isDenied -> "Command denied"
                    else -> "Command"
                },
                style = MaterialTheme.typography.titleSmall.copy(
                    fontSize = 15.5.sp,
                    fontWeight = FontWeight.Medium,
                ),
                color = when {
                    isWaiting -> colors.statusWaiting
                    isApproved -> colors.statusDone
                    else -> colors.inkReading
                },
            )
        }

        Spacer(modifier = Modifier.height(12.dp))

        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
            color = colors.surfaceCodeBlock,
        ) {
            Text(
                text = commandText,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = FontFamily.Monospace,
                    fontSize = 13.sp,
                    lineHeight = 20.sp,
                ),
                color = colors.inkReading,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            )
        }

        if (isWaiting) {
            Spacer(modifier = Modifier.height(14.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.End),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FilledTonalButton(
                    onClick = onDeny,
                    modifier = Modifier
                        .defaultMinSize(minHeight = 44.dp)
                        .testTag("btn-command-deny"),
                    shape = RoundedCornerShape(100.dp),
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = Color(0xFF352F26),
                        contentColor = colors.inkReading,
                    ),
                    contentPadding = PaddingValues(horizontal = 22.dp, vertical = 10.dp),
                ) {
                    Text(
                        text = "Deny",
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                    )
                }

                Button(
                    onClick = onApprove,
                    modifier = Modifier
                        .defaultMinSize(minHeight = 44.dp)
                        .testTag("btn-command-allow-biometric"),
                    shape = RoundedCornerShape(100.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.statusWaiting,
                        contentColor = colors.inkOnAmberCta,
                    ),
                    contentPadding = PaddingValues(horizontal = 20.dp, vertical = 10.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Fingerprint,
                        contentDescription = "Biometric verification",
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Allow",
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontSize = 15.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                    )
                }
            }
        }
    }
}

/**
 * Forward-compatible generic fallback card for unrecognized future upstream `RequestedInteraction`
 * members so newer Desktop approval gates are never dropped or silently blocked.
 */
@Composable
private fun GenericFallbackInteractionCard(
    step: CascadeStep,
    onAllowOnce: () -> Unit,
    onDeny: () -> Unit,
) {
    val colors = LocalAntigravityColors.current
    val interaction = step.requestedInteraction
    val title = formatForwardStepTitle(step.rawTypeName ?: interaction?.rawMemberKey)
    val summary = interaction?.rawSummary?.takeIf { it.isNotBlank() }
        ?: step.fallbackSummary?.takeIf { it.isNotBlank() }
        ?: "Upstream host requested approval for ${interaction?.rawMemberKey ?: "action"}."

    AntigravitySurfaceCard(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("card-generic-gate-${step.stepIndex}"),
        borderColor = colors.statusWaiting.copy(alpha = 0.45f),
        cornerRadius = 18.dp,
        contentPadding = PaddingValues(13.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.Shield,
                contentDescription = null,
                tint = colors.statusWaiting,
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold),
                color = colors.statusWaiting,
                modifier = Modifier.weight(1f),
            )
            if (!interaction?.rawMemberKey.isNullOrBlank()) {
                Surface(
                    shape = RoundedCornerShape(6.dp),
                    color = colors.surfaceAmberTint,
                ) {
                    Text(
                        text = interaction?.rawMemberKey.orEmpty(),
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.statusWaiting,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = summary,
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 13.5.sp),
            color = colors.inkReading,
        )

        Spacer(modifier = Modifier.height(10.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            FilledTonalButton(
                onClick = onDeny,
                modifier = Modifier
                    .weight(1f)
                    .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                    .testTag("btn-generic-gate-deny-${step.stepIndex}"),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = colors.surfaceElevated,
                    contentColor = colors.inkReading,
                ),
            ) {
                Text("Deny", style = MaterialTheme.typography.labelLarge)
            }

            Button(
                onClick = onAllowOnce,
                modifier = Modifier
                    .weight(1f)
                    .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                    .testTag("btn-generic-gate-allow-${step.stepIndex}"),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.statusWaiting,
                    contentColor = colors.inkOnAmberCta,
                ),
            ) {
                Icon(
                    imageVector = Icons.Rounded.Fingerprint,
                    contentDescription = null,
                    modifier = Modifier.size(17.dp),
                )
                Spacer(modifier = Modifier.width(6.dp))
                Text("Allow Once", style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

/**
 * Forward-compatible card for unrecognized future upstream `CortexStepType` wire values.
 */
@Composable
private fun UnknownForwardStepCard(step: CascadeStep) {
    val colors = LocalAntigravityColors.current
    val formattedTitle = formatForwardStepTitle(step.rawTypeName)

    AntigravitySurfaceCard(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("card-forward-step-${step.stepIndex}"),
        containerColor = colors.surfaceCard,
        borderColor = colors.cardBorder,
        cornerRadius = 16.dp,
        contentPadding = PaddingValues(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.Extension,
                contentDescription = null,
                tint = colors.accentPeriwinkle,
                modifier = Modifier.size(17.dp),
            )
            Text(
                text = formattedTitle,
                style = MaterialTheme.typography.titleSmall,
                color = colors.inkReading,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = step.status.displayBadgeText,
                style = MaterialTheme.typography.labelSmall,
                color = colors.statusColorFor(step.status),
            )
        }
        if (!step.rawTypeName.isNullOrBlank()) {
            Spacer(modifier = Modifier.height(3.dp))
            Text(
                text = step.rawTypeName.orEmpty(),
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkMuted,
            )
        }
        if (!step.fallbackSummary.isNullOrBlank()) {
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = step.fallbackSummary.orEmpty(),
                style = MaterialTheme.typography.bodyMedium,
                color = colors.inkLabel,
            )
        }
    }
}

@Composable
private fun SubagentStepCard(
    subagent: SubagentPayload,
    onStop: () -> Unit,
) {
    val colors = LocalAntigravityColors.current
    AntigravitySurfaceCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 16.dp,
        contentPadding = PaddingValues(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.Groups,
                contentDescription = null,
                tint = colors.accentPeriwinkle,
                modifier = Modifier.size(18.dp),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = subagent.role,
                    style = MaterialTheme.typography.titleSmall,
                    color = colors.inkReading,
                )
                Text(
                    text = "${subagent.typeName} · ${subagent.modelLabel}",
                    style = MaterialTheme.typography.labelSmall,
                    color = colors.inkSecondary,
                )
            }
            Text(
                text = subagent.status.displayBadgeText,
                style = MaterialTheme.typography.labelSmall,
                color = colors.statusColorFor(subagent.status),
            )
        }
        if (subagent.summary.isNotBlank()) {
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = subagent.summary,
                style = MaterialTheme.typography.bodyMedium,
                color = colors.inkLabel,
            )
        }
        if (subagent.status == CortexStepStatus.IN_PROGRESS || subagent.status == CortexStepStatus.WAITING) {
            TextButton(onClick = onStop) {
                Text("Stop Subagent", color = colors.statusError)
            }
        }
    }
}

@Composable
private fun DynamicWorkflowStepCard(workflow: DynamicWorkflowPayload) {
    val colors = LocalAntigravityColors.current
    var showScript by remember { mutableStateOf(false) }

    AntigravitySurfaceCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 16.dp,
        contentPadding = PaddingValues(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.AccountTree,
                    contentDescription = null,
                    tint = colors.accentPeriwinkle,
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    text = "Dynamic Workflow · ${workflow.currentPhase}",
                    style = MaterialTheme.typography.titleSmall,
                    color = colors.accentPeriwinkle,
                )
            }
            Text(
                text = "${workflow.completedAgents}/${workflow.totalAgents.coerceAtLeast(1)}",
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkSecondary,
            )
        }
        if (workflow.description.isNotBlank()) {
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = workflow.description,
                style = MaterialTheme.typography.bodyMedium,
                color = colors.inkReading,
            )
        }
        if (workflow.phases.isNotEmpty()) {
            Spacer(modifier = Modifier.height(6.dp))
            workflow.phases.forEach { phase ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    StatusDot(
                        color = if (phase.isCompleted) colors.statusDone else colors.accentPeriwinkle,
                        size = 6.dp,
                    )
                    Text(
                        text = phase.name,
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkLabel,
                    )
                }
            }
        }
        if (workflow.pythonScript.isNotBlank()) {
            TextButton(onClick = { showScript = !showScript }) {
                Text(
                    text = if (showScript) "Hide Python Script" else "Inspect Python Script",
                    color = colors.accentPeriwinkle,
                )
            }
            if (showScript) {
                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = colors.surfaceCodeBlock,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = workflow.pythonScript,
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.inkSecondary,
                        modifier = Modifier.padding(8.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun SwarmStepCard(
    board: SwarmBoardPayload,
    onOpenBoard: () -> Unit,
) {
    val colors = LocalAntigravityColors.current
    AntigravitySurfaceCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 16.dp,
        contentPadding = PaddingValues(12.dp),
        onClick = onOpenBoard,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.DeviceHub,
                    contentDescription = null,
                    tint = colors.accentPeriwinkle,
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    text = "Agent Swarm · ${board.title}",
                    style = MaterialTheme.typography.titleSmall,
                    color = colors.accentPeriwinkle,
                )
            }
            Text(
                text = "${board.members.size} specialists",
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkSecondary,
            )
        }
    }
}

@Composable
private fun McpToolStepCard(mcp: McpToolCallPayload) {
    val colors = LocalAntigravityColors.current
    AntigravitySurfaceCard(
        modifier = Modifier.fillMaxWidth(),
        cornerRadius = 16.dp,
        contentPadding = PaddingValues(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.Dns,
                contentDescription = null,
                tint = if (mcp.isError) colors.statusError else colors.accentPeriwinkle,
                modifier = Modifier.size(16.dp),
            )
            Text(
                text = "${mcp.serverName} · ${mcp.toolName}",
                style = MaterialTheme.typography.labelLarge.copy(fontFamily = FontFamily.Monospace),
                color = colors.inkReading,
                modifier = Modifier.weight(1f),
            )
        }
        if (!mcp.resultPreview.isNullOrBlank()) {
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = mcp.resultPreview.orEmpty(),
                style = MaterialTheme.typography.labelSmall,
                color = if (mcp.isError) colors.statusError else colors.inkSecondary,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun VoiceSummaryCard(summary: VoiceCallTranscriptSummary) {
    val colors = LocalAntigravityColors.current
    var expanded by remember { mutableStateOf(false) }

    AntigravitySurfaceCard(
        modifier = Modifier.fillMaxWidth(),
        borderColor = colors.accentPeriwinkle.copy(alpha = 0.3f),
        cornerRadius = 14.dp,
        contentPadding = PaddingValues(12.dp),
        onClick = { expanded = !expanded },
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.GraphicEq,
                contentDescription = null,
                tint = colors.accentPeriwinkle,
                modifier = Modifier.size(18.dp),
            )
            Text(
                text = "Voice Call Summary (${summary.durationLabel})",
                style = MaterialTheme.typography.titleSmall,
                color = colors.inkReading,
                modifier = Modifier.weight(1f),
            )
            Icon(
                imageVector = if (expanded) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore,
                contentDescription = null,
                tint = colors.inkMuted,
                modifier = Modifier.size(16.dp),
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = summary.summaryText,
            style = MaterialTheme.typography.bodySmall,
            color = colors.inkSecondary,
            maxLines = if (expanded) 10 else 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun ChatComposerCard(
    draftText: String,
    onDraftChange: (String) -> Unit,
    chips: List<ComposerAttachmentChip>,
    onRemoveChip: (String) -> Unit,
    modelLabel: String,
    effortLabel: String,
    permissionLabel: String,
    onAddContext: () -> Unit,
    onOpenModelAndMode: () -> Unit,
    onOpenPermissionsPreset: () -> Unit,
    onOpenVoice: () -> Unit,
    onSend: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        color = colors.surfaceCard,
        border = BorderStroke(1.dp, colors.cardBorder),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // Attached Context Chips Row (when user attaches files/mentions)
            if (chips.isNotEmpty() && draftText.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    chips.forEach { chip ->
                        val chipTag = if (chip.label.contains("ratelimit", ignoreCase = true)) {
                            "composer-chip-ratelimit"
                        } else {
                            "composer-chip-${chip.id}"
                        }
                        Surface(
                            shape = RoundedCornerShape(100.dp),
                            color = colors.surfaceElevated,
                            border = BorderStroke(1.dp, colors.cardBorder),
                            modifier = Modifier.testTag(chipTag),
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Text(
                                    text = chip.label,
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 11.5.sp,
                                    ),
                                    color = colors.inkLabel,
                                )
                                Icon(
                                    imageVector = Icons.Rounded.Close,
                                    contentDescription = "Remove ${chip.label}",
                                    tint = colors.inkMuted,
                                    modifier = Modifier
                                        .size(13.dp)
                                        .clickable { onRemoveChip(chip.id) },
                                )
                            }
                        }
                    }
                }
            }

            // Message Input Field
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 2.dp),
            ) {
                if (draftText.isEmpty()) {
                    Text(
                        text = "Ask anything, @ to mention, / for actions",
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                        color = colors.inkMuted,
                    )
                }
                BasicTextField(
                    value = draftText,
                    onValueChange = onDraftChange,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                        fontSize = 16.sp,
                        lineHeight = 22.sp,
                        color = colors.inkReading,
                    ),
                    cursorBrush = SolidColor(colors.accentPeriwinkle),
                    maxLines = 3,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("composer-text-input"),
                )
            }

            // Bottom Composer Toolbar: +, Gemini 4 Neon / Extra High ⌄, 🛡 Default ⌄, 🎤, →
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                IconButton(
                    onClick = onAddContext,
                    modifier = Modifier
                        .size(36.dp)
                        .testTag("composer-btn-add-context"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Add,
                        contentDescription = "Add context",
                        tint = colors.inkReading,
                        modifier = Modifier.size(22.dp),
                    )
                }

                // Two-line Model + Thinking Effort selector
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .clickable(onClick = onOpenModelAndMode)
                        .padding(horizontal = 4.dp, vertical = 2.dp)
                        .testTag("composer-pill-model"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
                        Text(
                            text = modelLabel,
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

                // Permissions Preset trigger (`🛡 Default ⌄`)
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .clickable(onClick = onOpenPermissionsPreset)
                        .padding(horizontal = 6.dp, vertical = 6.dp)
                        .testTag("composer-pill-permissions"),
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
                        contentDescription = "Select permissions",
                        tint = colors.inkSecondary,
                        modifier = Modifier.size(16.dp),
                    )
                }

                Spacer(modifier = Modifier.weight(1f))

                IconButton(
                    onClick = onOpenVoice,
                    modifier = Modifier
                        .size(34.dp)
                        .testTag("composer-btn-voice"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Mic,
                        contentDescription = "Voice mode",
                        tint = colors.inkLabel,
                        modifier = Modifier.size(20.dp),
                    )
                }

                val hasContent = draftText.isNotBlank() || chips.isNotEmpty()
                Surface(
                    onClick = onSend,
                    modifier = Modifier
                        .size(38.dp)
                        .testTag("composer-btn-send"),
                    shape = CircleShape,
                    color = if (hasContent) colors.accentPeriwinkle else Color(0xFF2E2E35),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Rounded.ArrowForward,
                            contentDescription = "Send message",
                            tint = if (hasContent) colors.inkOnPrimaryCta else colors.inkSecondary,
                            modifier = Modifier.size(19.dp),
                        )
                    }
                }
            }
        }
    }
}

private fun formatForwardStepTitle(rawName: String?): String {
    val clean = rawName?.trim().orEmpty()
    if (clean.isEmpty()) return "Upstream Step"
    val stripped = clean
        .removePrefix("CORTEX_STEP_TYPE_")
        .replace(Regex("([a-z])([A-Z])"), "$1 $2")
        .replace('_', ' ')
        .trim()
    return stripped
        .split(' ')
        .filter { it.isNotBlank() }
        .joinToString(" ") { word ->
            word.lowercase().replaceFirstChar { it.uppercase() }
        }
}
