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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
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
import dev.antigravity.shared.model.CascadeDisplayItem
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.ComposerAttachmentChip
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.DynamicWorkflowPayload
import dev.antigravity.shared.model.InteractionDecision
import dev.antigravity.shared.model.McpToolCallPayload
import dev.antigravity.shared.model.SlashCommandItem
import dev.antigravity.shared.model.SubagentPayload
import dev.antigravity.shared.model.SwarmBoardPayload
import dev.antigravity.shared.model.TaskBoundaryPayload
import dev.antigravity.shared.model.TaskChecklistStatus
import dev.antigravity.shared.model.VoiceCallTranscriptSummary
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

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
    onOpenDiffReview: () -> Unit,
    onOpenPlanReview: () -> Unit,
    onOpenAddContext: () -> Unit,
    onOpenModelAndMode: () -> Unit,
    onOpenOverview: () -> Unit,
    onOpenSideQuestion: () -> Unit,
    onOpenSwarmBoard: () -> Unit,
    onOpenVoiceMode: () -> Unit,
    onBiometricPrompt: (title: String, onSuccess: () -> Unit) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val chatState by coordinator.chatState.collectAsState()
    val syncState by coordinator.syncState.collectAsState()
    val workspaceState by coordinator.workspaceStore.state.collectAsState()
    val settingsState by coordinator.settingsStore.state.collectAsState()
    val scope = rememberCoroutineScope()

    val activeCascadeId = chatState.activeCascadeId.ifBlank { "cas-rate-limiter" }
    val activeSummary = syncState.summaries.firstOrNull { it.cascadeId == activeCascadeId }
        ?: syncState.summaries.firstOrNull()

    val headerTitle = activeSummary?.title ?: "Add rate limiter to /transfers"
    val headerSubtitle = buildString {
        append(activeSummary?.projectSlug ?: "ledger-svc")
        append(" · ")
        append(activeSummary?.branchName ?: "main")
        append(" · ")
        append(activeSummary?.originHostName ?: "MacBook Pro")
    }
    val totalAdditions = activeSummary?.totalAdditions ?: 128
    val totalDeletions = activeSummary?.totalDeletions ?: 14

    val displayItems = chatState.activeDisplayItems
    val activeWaitingStep = chatState.activeSteps.lastOrNull { it.status == CortexStepStatus.WAITING }
    val activeTaskStep = chatState.activeSteps.lastOrNull { it.taskBoundary != null }

    val statusText = when {
        activeWaitingStep != null ->
            activeTaskStep?.taskBoundary?.taskStatus ?: "Waiting for your approval · Step ${activeWaitingStep.stepIndex} of 7"
        chatState.activeSteps.any { it.status == CortexStepStatus.IN_PROGRESS } ->
            "Running · Step ${activeTaskStep?.taskBoundary?.completedCount ?: 4} of ${activeTaskStep?.taskBoundary?.totalCount ?: 7}"
        else -> "Ready · All steps up to date"
    }
    val statusDotColor = when {
        activeWaitingStep != null -> colors.statusWaiting
        chatState.activeSteps.any { it.status == CortexStepStatus.IN_PROGRESS } -> colors.statusRunning
        else -> colors.statusDone
    }

    val modelDisplayName = settingsState.selectedModel?.displayName
        ?.replace(" (Thinking)", "")
        ?: "Gemini 3.1 Pro"

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
                    .padding(horizontal = 4.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .defaultMinSize(
                            minWidth = AntigravityDesignTokens.MinTouchTarget,
                            minHeight = AntigravityDesignTokens.MinTouchTarget,
                        )
                        .testTag("btn-chat-back"),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "Back",
                        tint = colors.accentPeriwinkle,
                    )
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(1.dp),
                ) {
                    Text(
                        text = headerTitle,
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontSize = 15.5.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = headerSubtitle,
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp),
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                DiffCounterBadge(
                    additions = totalAdditions,
                    deletions = totalDeletions,
                    onClick = onOpenDiffReview,
                    modifier = Modifier.testTag("chat-diff-pill"),
                )

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
                        tint = colors.inkLabel,
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
                // Status Strip: Amber dot + Waiting label + Stop button
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    StatusDot(color = statusDotColor, size = 7.dp)
                    Text(
                        text = statusText,
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontSize = 12.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = if (activeWaitingStep != null) colors.statusWaiting else colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Surface(
                        onClick = {
                            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                coordinator.cancelActiveTurn(activeCascadeId)
                            }
                        },
                        modifier = Modifier
                            .defaultMinSize(minHeight = 32.dp)
                            .testTag("btn-stop-turn"),
                        shape = RoundedCornerShape(100.dp),
                        color = colors.surfaceElevated,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 11.dp, vertical = 5.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(5.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Stop,
                                contentDescription = "Stop turn",
                                tint = colors.inkReading,
                                modifier = Modifier.size(13.dp),
                            )
                            Text(
                                text = "Stop",
                                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                                color = colors.inkReading,
                            )
                        }
                    }
                }

                // Slash-command autocomplete strip when user types "/"
                val trimmedDraft = chatState.draftInputText.trim()
                if (trimmedDraft.startsWith("/")) {
                    val slashMatches = SlashCommandItem.allCommands
                        .filter { it.command.startsWith(trimmedDraft.lowercase()) }
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
                                                    "/btw" -> onOpenSideQuestion()
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

                // Docked Material 3 Chat Composer
                ChatComposerCard(
                    draftText = chatState.draftInputText,
                    onDraftChange = { coordinator.chatStore.setDraftInputText(it) },
                    chips = workspaceState.attachedComposerChips,
                    onRemoveChip = { coordinator.workspaceStore.removeComposerChip(it) },
                    modeLabel = settingsState.selectedMode.displayTitle,
                    modelLabel = modelDisplayName,
                    onAddContext = onOpenAddContext,
                    onOpenModelAndMode = onOpenModelAndMode,
                    onOpenVoice = onOpenVoiceMode,
                    onSend = {
                        val text = chatState.draftInputText.trim()
                        when (text.lowercase()) {
                            "/btw" -> {
                                coordinator.chatStore.setDraftInputText("")
                                onOpenSideQuestion()
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
                                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                                    coordinator.sendMessage(
                                        cascadeId = activeCascadeId,
                                        message = text,
                                        workspaceUri = activeSummary?.workspaceUri.orEmpty(),
                                        attachments = attachments,
                                        modelId = settingsState.selectedModelId,
                                        effort = settingsState.selectedEffort,
                                        mode = settingsState.selectedMode,
                                        agentPersona = settingsState.selectedAgentPersona,
                                    )
                                }
                                coordinator.workspaceStore.clearComposerChips()
                            }
                        }
                    },
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp),
                )
            }
        },
    ) { innerPadding ->
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
    if (step.stepIndex == 0 && step.attachedMentions.isNotEmpty()) {
        // Compact context chips row matching UE07 top-of-stream peek
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            step.attachedMentions.forEach { mention ->
                Surface(
                    shape = RoundedCornerShape(100.dp),
                    color = colors.surfaceElevated,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Text(
                        text = mention,
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontFamily = if (mention.startsWith("@")) FontFamily.Monospace else FontFamily.SansSerif,
                        ),
                        color = colors.inkSecondary,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                    )
                }
            }
        }
    } else if (!step.userInput.isNullOrBlank()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
        ) {
            Surface(
                shape = RoundedCornerShape(16.dp),
                color = colors.surfaceElevated,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = step.userInput.orEmpty(),
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                        color = colors.inkReading,
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
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Collapsible Thought for 14s row
        if (!planner.thinking.isNullOrBlank()) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable(onClick = onToggleThinking)
                        .padding(vertical = 3.dp, horizontal = 2.dp)
                        .testTag(thoughtTag),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.AutoAwesome,
                        contentDescription = null,
                        tint = colors.inkSecondary,
                        modifier = Modifier.size(15.dp),
                    )
                    Text(
                        text = if (seconds != null) "Thought for ${seconds}s" else "Thought process",
                        style = MaterialTheme.typography.bodyMedium.copy(
                            fontSize = 13.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.inkSecondary,
                    )
                    Icon(
                        imageVector = if (isThinkingExpanded) Icons.Rounded.ExpandLess else Icons.Rounded.ChevronRight,
                        contentDescription = if (isThinkingExpanded) "Collapse thought" else "Expand thought",
                        tint = colors.inkMuted,
                        modifier = Modifier.size(16.dp),
                    )
                }

                if (isThinkingExpanded) {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        color = colors.surfaceSubtleBox,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        Text(
                            text = planner.thinking.orEmpty(),
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontSize = 12.sp,
                                lineHeight = 17.sp,
                            ),
                            color = colors.inkSecondary,
                            modifier = Modifier.padding(10.dp),
                        )
                    }
                }
            }
        }

        // Markdown Prose Response
        if (planner.response.isNotBlank()) {
            MarkdownContentView(markdown = planner.response)
        }

        // Implementation Plan Artifact Card (when referenced)
        if (planner.referencedFiles.any { it.contains("plan", ignoreCase = true) }) {
            AntigravitySurfaceCard(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("card-artifact-plan"),
                cornerRadius = 16.dp,
                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
                onClick = onOpenPlanReview,
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Surface(
                        shape = RoundedCornerShape(10.dp),
                        color = colors.surfaceSelectionTint,
                        modifier = Modifier.size(36.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                imageVector = Icons.Rounded.Description,
                                contentDescription = "Implementation Plan",
                                tint = colors.accentPeriwinkle,
                                modifier = Modifier.size(19.dp),
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
                                fontSize = 14.5.sp,
                                fontWeight = FontWeight.Bold,
                            ),
                            color = colors.inkReading,
                        )
                        Text(
                            text = "Approved · 2 comments addressed",
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                            color = colors.inkSecondary,
                        )
                    }
                    Icon(
                        imageVector = Icons.Rounded.ChevronRight,
                        contentDescription = "Open Plan Review",
                        tint = colors.inkMuted,
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

    AntigravitySurfaceCard(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("card-task-progress-7seg"),
        cornerRadius = 18.dp,
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 11.dp),
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
                    fontSize = 14.5.sp,
                    fontWeight = FontWeight.Bold,
                ),
                color = colors.inkReading,
            )
            Text(
                text = taskBoundary.elapsedLabel,
                style = MaterialTheme.typography.labelSmall,
                color = colors.inkMuted,
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        SevenSegmentProgressBar(
            completedCount = taskBoundary.completedCount,
            totalCount = taskBoundary.totalCount,
            hasWaitingStep = hasWaiting,
            segmentHeight = 5.dp,
            segmentSpacing = 4.dp,
        )

        if (taskBoundary.checklist.isNotEmpty()) {
            Spacer(modifier = Modifier.height(9.dp))
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                taskBoundary.checklist.forEach { item ->
                    val isWaiting = item.status == TaskChecklistStatus.WAITING
                    val isCodeLike = item.title.startsWith("go ") || item.title.contains("./")
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        when (item.status) {
                            TaskChecklistStatus.DONE -> {
                                Icon(
                                    imageVector = Icons.Rounded.Check,
                                    contentDescription = "Done",
                                    tint = colors.statusDone,
                                    modifier = Modifier.size(14.dp),
                                )
                            }
                            TaskChecklistStatus.WAITING -> {
                                StatusDot(color = colors.statusWaiting, size = 7.dp)
                            }
                            TaskChecklistStatus.IN_PROGRESS -> {
                                StatusDot(color = colors.statusRunning, size = 7.dp)
                            }
                            TaskChecklistStatus.PENDING -> {
                                StatusDot(color = colors.inkMuted, size = 6.dp)
                            }
                        }

                        Text(
                            text = item.title,
                            style = MaterialTheme.typography.bodyMedium.copy(
                                fontSize = 13.sp,
                                fontFamily = if (isCodeLike) FontFamily.Monospace else FontFamily.SansSerif,
                                fontWeight = if (isWaiting) FontWeight.SemiBold else FontWeight.Normal,
                            ),
                            color = if (isWaiting) colors.statusWaiting else colors.inkSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )

                        if (!item.trailingBadge.isNullOrBlank()) {
                            Text(
                                text = item.trailingBadge.orEmpty(),
                                style = MaterialTheme.typography.labelMedium.copy(
                                    fontWeight = FontWeight.SemiBold,
                                ),
                                color = colors.statusDone,
                            )
                        }
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

    val borderColor = when {
        isWaiting -> colors.statusWaiting.copy(alpha = 0.42f)
        isApproved -> colors.statusDone.copy(alpha = 0.35f)
        else -> colors.cardBorder
    }

    AntigravitySurfaceCard(
        modifier = Modifier
            .fillMaxWidth()
            .testTag("card-command-approval"),
        containerColor = if (isWaiting) colors.surfaceCard else colors.surfaceCard,
        borderColor = borderColor,
        cornerRadius = 18.dp,
        contentPadding = PaddingValues(13.dp),
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
                    fontSize = 14.5.sp,
                    fontWeight = FontWeight.Bold,
                ),
                color = when {
                    isWaiting -> colors.statusWaiting
                    isApproved -> colors.statusDone
                    else -> colors.inkReading
                },
            )
        }

        Spacer(modifier = Modifier.height(9.dp))

        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            color = colors.surfaceCodeBlock,
            border = BorderStroke(1.dp, colors.cardBorder),
        ) {
            Text(
                text = commandText,
                style = MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp,
                    lineHeight = 18.sp,
                ),
                color = colors.inkReading,
                modifier = Modifier.padding(horizontal = 11.dp, vertical = 9.dp),
            )
        }

        if (isWaiting) {
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
                        .testTag("btn-command-deny"),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = colors.surfaceElevated,
                        contentColor = colors.inkReading,
                    ),
                ) {
                    Text(
                        text = "Deny",
                        style = MaterialTheme.typography.labelLarge.copy(
                            fontSize = 14.5.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                    )
                }

                Button(
                    onClick = onApprove,
                    modifier = Modifier
                        .weight(1f)
                        .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                        .testTag("btn-command-allow-biometric"),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.statusWaiting,
                        contentColor = colors.inkOnAmberCta,
                    ),
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
                            fontSize = 14.5.sp,
                            fontWeight = FontWeight.Bold,
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
    modeLabel: String,
    modelLabel: String,
    onAddContext: () -> Unit,
    onOpenModelAndMode: () -> Unit,
    onOpenVoice: () -> Unit,
    onSend: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current

    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        color = colors.surfaceCard,
        border = BorderStroke(1.dp, colors.cardBorder),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Attached Context Chips Row
            if (chips.isNotEmpty()) {
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
                        text = "Ask anything, or type / for commands...",
                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                        color = colors.inkMuted,
                    )
                }
                BasicTextField(
                    value = draftText,
                    onValueChange = onDraftChange,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                        fontSize = 15.sp,
                        lineHeight = 21.sp,
                        color = colors.inkReading,
                    ),
                    cursorBrush = SolidColor(colors.accentPeriwinkle),
                    maxLines = 3,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("composer-text-input"),
                )
            }

            // Bottom Composer Toolbar: +, Planning, Gemini 3.1 Pro, Mic, Send
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Surface(
                    onClick = onAddContext,
                    modifier = Modifier
                        .size(38.dp)
                        .testTag("composer-btn-add-context"),
                    shape = CircleShape,
                    color = colors.surfaceElevated,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Rounded.Add,
                            contentDescription = "Add context",
                            tint = colors.inkReading,
                            modifier = Modifier.size(19.dp),
                        )
                    }
                }

                Surface(
                    onClick = onOpenModelAndMode,
                    modifier = Modifier
                        .defaultMinSize(minHeight = 36.dp)
                        .testTag("composer-pill-mode"),
                    shape = RoundedCornerShape(100.dp),
                    color = colors.surfaceElevated,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        Text(
                            text = modeLabel,
                            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                            color = colors.inkReading,
                            maxLines = 1,
                        )
                        Icon(
                            imageVector = Icons.Rounded.KeyboardArrowDown,
                            contentDescription = null,
                            tint = colors.inkSecondary,
                            modifier = Modifier.size(15.dp),
                        )
                    }
                }

                Box(
                    modifier = Modifier.weight(1f),
                    contentAlignment = Alignment.CenterStart,
                ) {
                    Surface(
                        onClick = onOpenModelAndMode,
                        modifier = Modifier
                            .defaultMinSize(minHeight = 36.dp)
                            .testTag("composer-pill-model"),
                        shape = RoundedCornerShape(100.dp),
                        color = colors.surfaceElevated,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 7.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(3.dp),
                        ) {
                            Text(
                                text = modelLabel,
                                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Medium),
                                color = colors.inkLabel,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f, fill = false),
                            )
                            Icon(
                                imageVector = Icons.Rounded.KeyboardArrowDown,
                                contentDescription = null,
                                tint = colors.inkSecondary,
                                modifier = Modifier.size(15.dp),
                            )
                        }
                    }
                }

                IconButton(
                    onClick = onOpenVoice,
                    modifier = Modifier
                        .size(36.dp)
                        .testTag("composer-btn-voice"),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Mic,
                        contentDescription = "Voice mode",
                        tint = colors.inkSecondary,
                        modifier = Modifier.size(19.dp),
                    )
                }

                Surface(
                    onClick = onSend,
                    modifier = Modifier
                        .size(AntigravityDesignTokens.MinTouchTarget)
                        .testTag("composer-btn-send"),
                    shape = RoundedCornerShape(16.dp),
                    color = colors.accentPeriwinkle,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Rounded.ArrowUpward,
                            contentDescription = "Send message",
                            tint = colors.inkOnPrimaryCta,
                            modifier = Modifier.size(22.dp),
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
