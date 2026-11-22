package dev.antigravity.android.ui.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Reply
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.DeviceHub
import androidx.compose.material.icons.rounded.Forum
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MicOff
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Terminal
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import dev.antigravity.android.core.ui.components.AntigravityChip
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.components.DiffCounterBadge
import dev.antigravity.android.core.ui.components.SectionHeaderLabel
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.components.statusColorFor
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.CortexStepStatus
import kotlinx.coroutines.launch

/**
 * v2.33 Conversation Overview Sheet surfacing Goals, Subagents (with Stop), Background Tasks
 * (with Cancel), Changed Files, and linked GitHub Pull Requests.
 */
@Composable
fun ConversationOverviewSheet(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    onOpenDiffReview: () -> Unit = {},
    onOpenPlanReview: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val orchState by coordinator.orchestrationStore.state.collectAsState()
    val chatState by coordinator.chatState.collectAsState()
    val scope = rememberCoroutineScope()
    val overview = orchState.overview
    val activeCascadeId = chatState.activeCascadeId.ifBlank { "cas-rate-limiter" }

    Surface(
        modifier = modifier
            .fillMaxSize()
            .testTag("sheet-conversation-overview"),
        color = colors.canvasObsidian,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            // Top Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "Conversation Overview",
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    color = colors.inkReading,
                    modifier = Modifier.padding(start = 6.dp),
                )
                TextButton(
                    onClick = onDismiss,
                    modifier = Modifier
                        .defaultMinSize(
                            minWidth = AntigravityDesignTokens.MinTouchTarget,
                            minHeight = AntigravityDesignTokens.MinTouchTarget,
                        )
                        .testTag("btn-close-overview"),
                ) {
                    Text(
                        text = "Done",
                        style = MaterialTheme.typography.labelLarge,
                        color = colors.accentPeriwinkle,
                    )
                }
            }

            HorizontalDivider(color = colors.subtleDivider)

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                // Review & Diffs Summary Card
                AntigravitySurfaceCard(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(14.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Description,
                                contentDescription = null,
                                tint = colors.accentPeriwinkle,
                                modifier = Modifier.size(18.dp),
                            )
                            Text(
                                text = "Review & Diffs (${overview.changedFilesCount} files)",
                                style = MaterialTheme.typography.titleSmall,
                                color = colors.inkReading,
                            )
                        }
                        DiffCounterBadge(
                            additions = overview.totalAdditions,
                            deletions = overview.totalDeletions,
                        )
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Button(
                            onClick = {
                                onDismiss()
                                onOpenDiffReview()
                            },
                            modifier = Modifier
                                .weight(1f)
                                .defaultMinSize(minHeight = 44.dp),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = colors.accentPeriwinkle,
                                contentColor = colors.inkOnPrimaryCta,
                            ),
                        ) {
                            Text("Diff Review", style = MaterialTheme.typography.labelLarge)
                        }
                        FilledTonalButton(
                            onClick = {
                                onDismiss()
                                onOpenPlanReview()
                            },
                            modifier = Modifier
                                .weight(1f)
                                .defaultMinSize(minHeight = 44.dp),
                            shape = RoundedCornerShape(12.dp),
                            colors = ButtonDefaults.filledTonalButtonColors(
                                containerColor = colors.surfaceElevated,
                                contentColor = colors.inkReading,
                            ),
                        ) {
                            Text("Plan Review", style = MaterialTheme.typography.labelLarge)
                        }
                    }
                }

                // Goals
                if (overview.goals.isNotEmpty()) {
                    AntigravitySurfaceCard(
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(14.dp),
                    ) {
                        SectionHeaderLabel(title = "GOALS", count = overview.goals.size)
                        Spacer(modifier = Modifier.height(10.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            overview.goals.forEach { goal ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                                ) {
                                    Icon(
                                        imageVector = if (goal.isCompleted) {
                                            Icons.Rounded.CheckCircle
                                        } else {
                                            Icons.Rounded.RadioButtonUnchecked
                                        },
                                        contentDescription = null,
                                        tint = if (goal.isCompleted) colors.statusDone else colors.accentPeriwinkle,
                                        modifier = Modifier.size(18.dp),
                                    )
                                    Text(
                                        text = goal.title,
                                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                                        color = colors.inkReading,
                                        modifier = Modifier.weight(1f),
                                    )
                                }
                            }
                        }
                    }
                }

                // Subagents with Stop action
                AntigravitySurfaceCard(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(14.dp),
                ) {
                    SectionHeaderLabel(title = "SUBAGENTS", count = overview.activeSubagents.size)
                    Spacer(modifier = Modifier.height(10.dp))
                    if (overview.activeSubagents.isEmpty()) {
                        Text(
                            text = "No active subagents spawned in this conversation.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.inkSecondary,
                        )
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            overview.activeSubagents.forEach { sub ->
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = colors.surfaceElevated,
                                ) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(10.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.Groups,
                                            contentDescription = null,
                                            tint = colors.accentPeriwinkle,
                                            modifier = Modifier.size(18.dp),
                                        )
                                        Column(modifier = Modifier.weight(1f)) {
                                            Row(
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                            ) {
                                                Text(
                                                    text = sub.role,
                                                    style = MaterialTheme.typography.titleSmall,
                                                    color = colors.inkReading,
                                                )
                                                Text(
                                                    text = sub.status.displayBadgeText,
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = colors.statusColorFor(sub.status),
                                                )
                                            }
                                            if (sub.summary.isNotBlank()) {
                                                Text(
                                                    text = sub.summary,
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color = colors.inkSecondary,
                                                    maxLines = 2,
                                                    overflow = TextOverflow.Ellipsis,
                                                )
                                            }
                                        }
                                        if (sub.status == CortexStepStatus.IN_PROGRESS || sub.status == CortexStepStatus.WAITING) {
                                            TextButton(
                                                onClick = {
                                                    scope.launch {
                                                        val client = coordinator.connectionStore.activeClient()
                                                        coordinator.orchestrationStore.stopSubagent(
                                                            client = client,
                                                            cascadeId = activeCascadeId,
                                                            subagentId = sub.subagentId,
                                                        )
                                                    }
                                                },
                                                modifier = Modifier.testTag("btn-stop-subagent-${sub.subagentId}"),
                                            ) {
                                                Text("Stop", color = colors.statusError)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Background Tasks with Cancel action
                AntigravitySurfaceCard(
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(14.dp),
                ) {
                    SectionHeaderLabel(title = "BACKGROUND TASKS", count = overview.backgroundTasks.size)
                    Spacer(modifier = Modifier.height(10.dp))
                    if (overview.backgroundTasks.isEmpty()) {
                        Text(
                            text = "No background shell or daemon tasks running.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.inkSecondary,
                        )
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            overview.backgroundTasks.forEach { task ->
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = colors.surfaceElevated,
                                ) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(10.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    ) {
                                        Icon(
                                            imageVector = Icons.Rounded.Terminal,
                                            contentDescription = null,
                                            tint = colors.statusColorFor(task.status),
                                            modifier = Modifier.size(18.dp),
                                        )
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = task.title,
                                                style = MaterialTheme.typography.titleSmall,
                                                color = colors.inkReading,
                                            )
                                            Text(
                                                text = "${task.commandOrKind} · ${task.elapsedLabel}",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = colors.inkSecondary,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                        }
                                        if (task.status == CortexStepStatus.IN_PROGRESS) {
                                            TextButton(
                                                onClick = {
                                                    scope.launch {
                                                        val client = coordinator.connectionStore.activeClient()
                                                        coordinator.orchestrationStore.cancelBackgroundTask(
                                                            client = client,
                                                            cascadeId = activeCascadeId,
                                                            taskId = task.id,
                                                        )
                                                    }
                                                },
                                                modifier = Modifier.testTag("btn-cancel-bg-task-${task.id}"),
                                            ) {
                                                Text("Cancel", color = colors.statusError)
                                            }
                                        } else {
                                            Text(
                                                text = task.status.displayBadgeText,
                                                style = MaterialTheme.typography.labelSmall,
                                                color = colors.inkMuted,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Changed Files
                if (overview.modifiedFiles.isNotEmpty()) {
                    AntigravitySurfaceCard(
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(14.dp),
                    ) {
                        SectionHeaderLabel(title = "CHANGED FILES", count = overview.modifiedFiles.size)
                        Spacer(modifier = Modifier.height(8.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            overview.modifiedFiles.forEach { filePath ->
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Code,
                                        contentDescription = null,
                                        tint = colors.inkMuted,
                                        modifier = Modifier.size(15.dp),
                                    )
                                    Text(
                                        text = filePath,
                                        style = MaterialTheme.typography.bodyMedium.copy(
                                            fontFamily = FontFamily.Monospace,
                                        ),
                                        color = colors.inkLabel,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
                    }
                }

                // Linked Pull Requests
                if (overview.linkedPullRequests.isNotEmpty()) {
                    AntigravitySurfaceCard(
                        modifier = Modifier.fillMaxWidth(),
                        contentPadding = PaddingValues(14.dp),
                    ) {
                        SectionHeaderLabel(title = "PULL REQUESTS", count = overview.linkedPullRequests.size)
                        Spacer(modifier = Modifier.height(8.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            overview.linkedPullRequests.forEach { pr ->
                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = colors.surfaceElevated,
                                ) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(10.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                                    ) {
                                        StatusDot(
                                            color = if (pr.state.equals("OPEN", ignoreCase = true)) {
                                                colors.statusDone
                                            } else {
                                                colors.accentPeriwinkle
                                            },
                                            size = 8.dp,
                                        )
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                text = "#${pr.number} ${pr.title}",
                                                style = MaterialTheme.typography.titleSmall,
                                                color = colors.inkReading,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                            )
                                            Text(
                                                text = "${pr.state} · Checks: ${pr.checksStatus}",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = colors.inkSecondary,
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

/**
 * Multi-turn `/btw` Read-Only Side Question sheet with "Insert into main conversation".
 */
@Composable
fun SideQuestionSheet(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val orchState by coordinator.orchestrationStore.state.collectAsState()
    val chatState by coordinator.chatState.collectAsState()
    val scope = rememberCoroutineScope()

    val activeCascadeId = chatState.activeCascadeId.ifBlank { "cas-rate-limiter" }
    LaunchedEffect(activeCascadeId) {
        coordinator.orchestrationStore.openSideQuestion(activeCascadeId)
    }

    var draft by remember { mutableStateOf("") }
    val thread = orchState.sideQuestionThread

    Surface(
        modifier = modifier
            .fillMaxSize()
            .testTag("sheet-side-question"),
        color = colors.canvasObsidian,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding(),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(start = 6.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Forum,
                        contentDescription = null,
                        tint = colors.accentPeriwinkle,
                    )
                    Text(
                        text = "/btw Side Question",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                        color = colors.inkReading,
                    )
                }
                TextButton(onClick = onDismiss) {
                    Text("Done", color = colors.accentPeriwinkle)
                }
            }

            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = colors.surfaceObsidian,
            ) {
                Text(
                    text = "Read-only side thread · Keeps main conversation context clean",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (thread.messages.isEmpty()) {
                    Text(
                        text = "Ask a quick /btw question to inspect code or clarify edge cases without interrupting the active agent turn.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.inkSecondary,
                    )
                } else {
                    thread.messages.forEach { msg ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = if (msg.isUser) Arrangement.End else Arrangement.Start,
                        ) {
                            Surface(
                                shape = RoundedCornerShape(14.dp),
                                color = if (msg.isUser) colors.accentPeriwinkle else colors.surfaceCard,
                                border = if (msg.isUser) null else BorderStroke(1.dp, colors.cardBorder),
                                modifier = Modifier.widthIn(max = 310.dp),
                            ) {
                                Text(
                                    text = msg.text,
                                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                                    color = if (msg.isUser) colors.inkOnPrimaryCta else colors.inkReading,
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                                )
                            }
                        }
                    }
                }
            }

            if (thread.messages.any { !it.isUser }) {
                Button(
                    onClick = {
                        val snippet = coordinator.orchestrationStore.insertSideQuestionIntoMain()
                        if (!snippet.isNullOrBlank()) {
                            coordinator.chatStore.setDraftInputText(snippet)
                        }
                        onDismiss()
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 6.dp)
                        .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                        .testTag("btn-insert-btw-into-main"),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.accentPeriwinkle,
                        contentColor = colors.inkOnPrimaryCta,
                    ),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.Reply,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.size(8.dp))
                    Text("Insert into main conversation", style = MaterialTheme.typography.labelLarge)
                }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surfaceObsidian)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Surface(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(14.dp),
                    color = colors.surfaceCard,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Box(modifier = Modifier.padding(horizontal = 12.dp, vertical = 11.dp)) {
                        if (draft.isEmpty()) {
                            Text(
                                text = "Ask a side question...",
                                style = MaterialTheme.typography.bodyMedium,
                                color = colors.inkMuted,
                            )
                        }
                        BasicTextField(
                            value = draft,
                            onValueChange = { draft = it },
                            textStyle = MaterialTheme.typography.bodyMedium.copy(
                                fontSize = 14.sp,
                                color = colors.inkReading,
                            ),
                            cursorBrush = SolidColor(colors.accentPeriwinkle),
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("input-side-question"),
                        )
                    }
                }
                Surface(
                    onClick = {
                        val text = draft.trim()
                        if (text.isNotEmpty()) {
                            draft = ""
                            scope.launch {
                                val client = coordinator.connectionStore.activeClient()
                                coordinator.orchestrationStore.sendSideQuestion(
                                    client = client,
                                    prompt = text,
                                    cascadeId = activeCascadeId,
                                )
                            }
                        }
                    },
                    modifier = Modifier
                        .size(44.dp)
                        .testTag("btn-send-side-question"),
                    shape = CircleShape,
                    color = if (draft.isNotBlank()) colors.accentPeriwinkle else colors.surfaceElevated,
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Rounded.ArrowUpward,
                            contentDescription = "Send side question",
                            tint = if (draft.isNotBlank()) colors.inkOnPrimaryCta else colors.inkMuted,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }
        }
    }
}

/**
 * `/swarm` Agent Swarm Board Sheet surfacing Specialist Roster, `@member` filter pills, and posts.
 */
@Composable
fun SwarmBoardSheet(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val orchState by coordinator.orchestrationStore.state.collectAsState()
    val board = orchState.swarmBoard
    val memberFilter = orchState.swarmMemberFilter

    Surface(
        modifier = modifier
            .fillMaxSize()
            .testTag("sheet-swarm-board"),
        color = colors.canvasObsidian,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(start = 6.dp),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.DeviceHub,
                        contentDescription = null,
                        tint = colors.accentPeriwinkle,
                    )
                    Text(
                        text = board?.title ?: "Agent Swarm Board",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                TextButton(onClick = onDismiss) {
                    Text("Done", color = colors.accentPeriwinkle)
                }
            }

            HorizontalDivider(color = colors.subtleDivider)

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                if (board == null) {
                    Text(
                        text = "No active Agent Swarm board in this conversation.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.inkSecondary,
                    )
                } else {
                    SectionHeaderLabel(title = "SWARM ROSTER", count = board.members.size)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        AntigravityChip(
                            label = "All",
                            selected = memberFilter == null,
                            onClick = { coordinator.orchestrationStore.setSwarmMemberFilter(null) },
                        )
                        board.members.forEach { member ->
                            val isSelected = memberFilter == member.name
                            AntigravityChip(
                                label = "@${member.name} · ${member.role}",
                                selected = isSelected,
                                leadingDotColor = colors.statusColorFor(member.status),
                                onClick = {
                                    coordinator.orchestrationStore.setSwarmMemberFilter(
                                        if (isSelected) null else member.name,
                                    )
                                },
                                modifier = Modifier.testTag("swarm-member-${member.name}"),
                            )
                        }
                    }

                    val filteredPosts = board.posts.filter { post ->
                        memberFilter == null ||
                            post.author.equals(memberFilter, ignoreCase = true) ||
                            post.body.contains("@$memberFilter", ignoreCase = true)
                    }

                    SectionHeaderLabel(title = "DISCUSSION BOARD", count = filteredPosts.size)
                    if (filteredPosts.isEmpty()) {
                        Text(
                            text = "No swarm posts matching @$memberFilter.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.inkSecondary,
                        )
                    } else {
                        filteredPosts.forEach { post ->
                            AntigravitySurfaceCard(
                                modifier = Modifier.fillMaxWidth(),
                                contentPadding = PaddingValues(12.dp),
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        text = "@${post.author} · #${post.channel}",
                                        style = MaterialTheme.typography.labelLarge.copy(
                                            fontFamily = FontFamily.Monospace,
                                        ),
                                        color = colors.accentPeriwinkle,
                                    )
                                    Text(
                                        text = post.timestampLabel,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = colors.inkMuted,
                                    )
                                }
                                Spacer(modifier = Modifier.height(6.dp))
                                Text(
                                    text = post.body,
                                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                                    color = colors.inkReading,
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
 * Gemini Live Voice Mode Sheet with voice selector, mute/unmute, live turn entry, and
 * End Call -> persisted `VoiceCallTranscriptSummary`.
 */
@Composable
fun VoiceModeSheet(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val orchState by coordinator.orchestrationStore.state.collectAsState()
    val voiceState = orchState.voiceState

    LaunchedEffect(Unit) {
        if (!voiceState.isActive) {
            coordinator.orchestrationStore.startVoiceMode()
        }
    }

    var turnDraft by remember { mutableStateOf("") }
    val voices = listOf("Kore", "Aoede", "Puck", "Charon", "Fenrir")

    Surface(
        modifier = modifier
            .fillMaxSize()
            .testTag("sheet-voice-mode"),
        color = colors.canvasObsidian,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .imePadding()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = "Gemini Live Voice Mode",
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                    color = colors.inkReading,
                )
                TextButton(
                    onClick = {
                        coordinator.orchestrationStore.endVoiceMode()
                        onDismiss()
                    },
                    modifier = Modifier.testTag("btn-end-voice-mode"),
                ) {
                    Text("End Call", color = colors.statusError, fontWeight = FontWeight.SemiBold)
                }
            }

            AntigravitySurfaceCard(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(18.dp),
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(76.dp)
                            .clip(CircleShape)
                            .background(
                                if (voiceState.isMuted) {
                                    colors.statusError.copy(alpha = 0.16f)
                                } else {
                                    colors.accentPeriwinkle.copy(alpha = 0.2f)
                                },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = if (voiceState.isMuted) Icons.Rounded.MicOff else Icons.Rounded.GraphicEq,
                            contentDescription = voiceState.statusLabel,
                            tint = if (voiceState.isMuted) colors.statusError else colors.accentPeriwinkle,
                            modifier = Modifier.size(34.dp),
                        )
                    }
                    Text(
                        text = voiceState.statusLabel,
                        style = MaterialTheme.typography.titleSmall,
                        color = colors.inkReading,
                    )
                    Row(
                        modifier = Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        voices.forEach { voice ->
                            AntigravityChip(
                                label = voice,
                                selected = voiceState.selectedVoice == voice,
                                onClick = { coordinator.orchestrationStore.setVoiceOption(voice) },
                            )
                        }
                    }
                }
            }

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (orchState.voiceTranscriptTurns.isEmpty()) {
                    Text(
                        text = "Speak or type a live turn below. Ending the call saves a collapsible Call Summary card to the conversation.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.inkSecondary,
                    )
                } else {
                    orchState.voiceTranscriptTurns.forEach { turn ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = if (turn.isUser) Arrangement.End else Arrangement.Start,
                        ) {
                            Surface(
                                shape = RoundedCornerShape(14.dp),
                                color = if (turn.isUser) colors.accentPeriwinkle else colors.surfaceCard,
                            ) {
                                Text(
                                    text = turn.text,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = if (turn.isUser) colors.inkOnPrimaryCta else colors.inkReading,
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 9.dp),
                                )
                            }
                        }
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Surface(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(14.dp),
                    color = colors.surfaceCard,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Box(modifier = Modifier.padding(horizontal = 12.dp, vertical = 11.dp)) {
                        if (turnDraft.isEmpty()) {
                            Text(
                                text = "Type a live voice turn...",
                                style = MaterialTheme.typography.bodyMedium,
                                color = colors.inkMuted,
                            )
                        }
                        BasicTextField(
                            value = turnDraft,
                            onValueChange = { turnDraft = it },
                            textStyle = MaterialTheme.typography.bodyMedium.copy(color = colors.inkReading),
                            cursorBrush = SolidColor(colors.accentPeriwinkle),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
                Button(
                    onClick = {
                        val t = turnDraft.trim()
                        if (t.isNotEmpty()) {
                            turnDraft = ""
                            coordinator.orchestrationStore.appendVoiceTurn(isUser = true, text = t)
                        }
                    },
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.accentPeriwinkle,
                        contentColor = colors.inkOnPrimaryCta,
                    ),
                ) {
                    Text("Send")
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                FilledTonalButton(
                    onClick = { coordinator.orchestrationStore.toggleVoiceMute() },
                    modifier = Modifier
                        .weight(1f)
                        .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = colors.surfaceElevated,
                        contentColor = colors.inkReading,
                    ),
                ) {
                    Icon(
                        imageVector = if (voiceState.isMuted) Icons.Rounded.MicOff else Icons.Rounded.Mic,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.size(6.dp))
                    Text(if (voiceState.isMuted) "Unmute" else "Mute")
                }
                Button(
                    onClick = {
                        coordinator.orchestrationStore.endVoiceMode()
                        onDismiss()
                    },
                    modifier = Modifier
                        .weight(1f)
                        .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.statusError,
                        contentColor = colors.inkOnPrimaryCta,
                    ),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Close,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.size(6.dp))
                    Text("End & Summarize")
                }
            }
        }
    }
}
