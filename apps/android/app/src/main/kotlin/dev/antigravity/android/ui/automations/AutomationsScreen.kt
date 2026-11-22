package dev.antigravity.android.ui.automations

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.components.StatusDot
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.antigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AutomationItem
import dev.antigravity.shared.model.AutomationSectionKind
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch

/**
 * UE06_AUTOMATIONS: Material 3 Automations Hub displaying an inline natural-language quick-create bar
 * alongside SCHEDULED (Next Run / Last Run stat tiles + Run Now), ALWAYS ON, and PAUSED sections.
 */
@Composable
fun AutomationsScreen(
    coordinator: AntigravityCoreCoordinator,
    onTapAddFab: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val colors = MaterialTheme.antigravityColors
    val workspaceState by coordinator.workspaceStore.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    var promptInput by rememberSaveable { mutableStateOf("") }
    var sectionFilter by rememberSaveable { mutableStateOf<AutomationSectionKind?>(null) }
    var filterMenuExpanded by remember { mutableStateOf(false) }

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

    val submitQuickCreate: () -> Unit = {
        val text = promptInput.trim()
        if (text.isNotEmpty()) {
            promptInput = ""
            scope.launch(start = CoroutineStart.UNDISPATCHED) {
                val rpcClient = if (coordinator.isVerificationMode) {
                    null
                } else {
                    coordinator.connectionStore.activeClient()
                }
                coordinator.workspaceStore.createAutomationFromPrompt(
                    client = rpcClient,
                    prompt = text,
                )
            }
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian)
            .verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 104.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // 1. Top Bar: "Automations" Title + Filter Icon
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "Automations",
                style = MaterialTheme.typography.headlineMedium.copy(
                    fontSize = 29.sp,
                    lineHeight = 34.sp,
                    fontWeight = FontWeight.Bold,
                ),
                color = colors.inkReading,
                modifier = Modifier.weight(1f),
                maxLines = 1,
            )

            Box {
                Surface(
                    onClick = { filterMenuExpanded = true },
                    modifier = Modifier
                        .size(AntigravityDesignTokens.MinTouchTarget)
                        .testTag("btn-automations-filter"),
                    shape = CircleShape,
                    color = colors.surfacePill,
                    border = BorderStroke(
                        width = 1.dp,
                        color = if (sectionFilter != null) colors.accentPeriwinkle else colors.cardBorder,
                    ),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Rounded.FilterList,
                            contentDescription = "Filter automations",
                            tint = if (sectionFilter != null) colors.accentPeriwinkle else colors.inkReading,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
                DropdownMenu(
                    expanded = filterMenuExpanded,
                    onDismissRequest = { filterMenuExpanded = false },
                    containerColor = colors.surfacePopover,
                ) {
                    DropdownMenuItem(
                        text = { Text("All Automations", color = colors.inkReading) },
                        trailingIcon = {
                            if (sectionFilter == null) {
                                Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accentPeriwinkle)
                            }
                        },
                        onClick = {
                            sectionFilter = null
                            filterMenuExpanded = false
                        },
                    )
                    AutomationSectionKind.entries.forEach { kind ->
                        DropdownMenuItem(
                            text = { Text(kind.displayTitle, color = colors.inkReading) },
                            trailingIcon = {
                                if (sectionFilter == kind) {
                                    Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accentPeriwinkle)
                                }
                            },
                            onClick = {
                                sectionFilter = kind
                                filterMenuExpanded = false
                            },
                        )
                    }
                }
            }
        }

        // 2. Inline Natural-Language Quick-Create Row
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = promptInput,
                onValueChange = { promptInput = it },
                modifier = Modifier
                    .weight(1f)
                    .testTag("automation-prompt-input"),
                singleLine = true,
                placeholder = {
                    Text(
                        text = "Every weekday at 9, summarize...",
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.sp),
                        color = colors.inkMuted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Rounded.Bolt,
                        contentDescription = null,
                        tint = colors.inkSecondary,
                        modifier = Modifier.size(18.dp),
                    )
                },
                textStyle = MaterialTheme.typography.bodyMedium.copy(
                    fontSize = 14.5.sp,
                    color = colors.inkReading,
                ),
                shape = RoundedCornerShape(16.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = colors.surfaceCard,
                    unfocusedContainerColor = colors.surfaceCard,
                    focusedBorderColor = colors.accentPeriwinkle,
                    unfocusedBorderColor = colors.cardBorder,
                    cursorColor = colors.accentPeriwinkle,
                ),
            )

            FilledTonalButton(
                onClick = submitQuickCreate,
                modifier = Modifier
                    .defaultMinSize(minWidth = 78.dp, minHeight = 52.dp)
                    .testTag("btn-create-automation-inline"),
                shape = RoundedCornerShape(16.dp),
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = if (promptInput.isNotBlank()) colors.accentPeriwinkle else colors.surfaceBadge,
                    contentColor = if (promptInput.isNotBlank()) colors.inkOnPrimaryCta else colors.inkReading,
                ),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            ) {
                Text(
                    text = "Create",
                    style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                    maxLines = 1,
                )
            }
        }

        // 3. SCHEDULED Section
        if ((sectionFilter == null || sectionFilter == AutomationSectionKind.SCHEDULED) && scheduledItems.isNotEmpty()) {
            AutomationSectionHeader(title = "SCHEDULED", count = scheduledItems.size)

            scheduledItems.forEach { item ->
                val cardTag = when (item.id) {
                    "auto-nightly-audit" -> "automation-card-nightly"
                    "auto-weekly-flaky" -> "automation-card-flaky"
                    else -> "automation-card-${item.id}"
                }
                val runTag = when (item.id) {
                    "auto-nightly-audit" -> "btn-run-nightly"
                    "auto-weekly-flaky" -> "btn-run-flaky"
                    else -> "btn-run-${item.id}"
                }
                ScheduledAutomationCard(
                    item = item,
                    cardTag = cardTag,
                    runButtonTag = runTag,
                    onRunNow = {
                        scope.launch(start = CoroutineStart.UNDISPATCHED) {
                            val rpcClient = if (coordinator.isVerificationMode) {
                                null
                            } else {
                                coordinator.connectionStore.activeClient()
                            }
                            coordinator.workspaceStore.runAutomationNow(
                                client = rpcClient,
                                automationId = item.id,
                            )
                        }
                    },
                )
            }
        }

        // 4. ALWAYS ON Section
        if ((sectionFilter == null || sectionFilter == AutomationSectionKind.ALWAYS_ON) && alwaysOnItems.isNotEmpty()) {
            AutomationSectionHeader(title = "ALWAYS ON", count = alwaysOnItems.size)

            alwaysOnItems.forEach { item ->
                val cardTag = if (item.id == "auto-pr-triage") {
                    "automation-card-always-on"
                } else {
                    "automation-card-${item.id}"
                }
                AlwaysOnAutomationCard(
                    item = item,
                    cardTag = cardTag,
                    onClick = onTapAddFab,
                )
            }
        }

        // 5. PAUSED Section
        if ((sectionFilter == null || sectionFilter == AutomationSectionKind.PAUSED) && pausedItems.isNotEmpty()) {
            AutomationSectionHeader(title = "PAUSED", count = pausedItems.size)

            pausedItems.forEach { item ->
                val resumeTag = if (item.id == "auto-bundle-size") {
                    "btn-resume-paused"
                } else {
                    "btn-resume-${item.id}"
                }
                PausedAutomationCard(
                    item = item,
                    resumeButtonTag = resumeTag,
                    onResume = {
                        scope.launch(start = CoroutineStart.UNDISPATCHED) {
                            val rpcClient = if (coordinator.isVerificationMode) {
                                null
                            } else {
                                coordinator.connectionStore.activeClient()
                            }
                            coordinator.workspaceStore.resumeAutomation(
                                client = rpcClient,
                                automationId = item.id,
                            )
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun AutomationSectionHeader(
    title: String,
    count: Int,
) {
    val colors = MaterialTheme.antigravityColors
    Text(
        text = "$title · $count",
        style = MaterialTheme.typography.labelSmall.copy(
            fontFamily = FontFamily.SansSerif,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.9.sp,
        ),
        color = colors.inkMuted,
        modifier = Modifier.padding(start = 2.dp, top = 2.dp),
    )
}

@Composable
private fun ScheduledAutomationCard(
    item: AutomationItem,
    cardTag: String,
    runButtonTag: String,
    onRunNow: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    AntigravitySurfaceCard(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(cardTag),
        contentPadding = PaddingValues(12.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        text = item.title,
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontSize = 15.5.sp,
                            fontWeight = FontWeight.SemiBold,
                        ),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = item.scheduleSummary,
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                Surface(
                    onClick = onRunNow,
                    modifier = Modifier
                        .size(AntigravityDesignTokens.MinTouchTarget)
                        .testTag(runButtonTag),
                    shape = CircleShape,
                    color = if (item.isRunningNow) colors.statusRunning.copy(alpha = 0.24f) else colors.surfaceSelectionTint,
                    border = BorderStroke(
                        width = 1.dp,
                        color = if (item.isRunningNow) colors.statusRunning else colors.accentPeriwinkle.copy(alpha = 0.25f),
                    ),
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Rounded.PlayArrow,
                            contentDescription = "Run ${item.title} now",
                            tint = colors.accentPeriwinkle,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // NEXT RUN Stat Box
                Surface(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                    color = colors.surfaceSubtleBox,
                ) {
                    Column(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(
                            text = "NEXT RUN",
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontFamily = FontFamily.SansSerif,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                letterSpacing = 0.6.sp,
                            ),
                            color = colors.inkMuted,
                        )
                        Text(
                            text = item.nextRunText,
                            style = MaterialTheme.typography.titleSmall.copy(
                                fontSize = 13.5.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.inkReading,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }

                // LAST RUN Stat Box
                val isAmber = item.needsReview && !item.isRunningNow
                Surface(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                    color = if (isAmber) colors.surfaceAmberTint else colors.surfaceSubtleBox,
                    border = if (isAmber) BorderStroke(1.dp, colors.statusWaiting.copy(alpha = 0.28f)) else null,
                ) {
                    Column(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(
                            text = "LAST RUN",
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontFamily = FontFamily.SansSerif,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                letterSpacing = 0.6.sp,
                            ),
                            color = if (isAmber) colors.statusWaiting else colors.inkMuted,
                        )
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            if (!isAmber && !item.isRunningNow) {
                                Icon(
                                    imageVector = Icons.Rounded.Check,
                                    contentDescription = null,
                                    tint = colors.statusDone,
                                    modifier = Modifier.size(13.dp),
                                )
                            } else if (item.isRunningNow) {
                                StatusDot(color = colors.statusRunning, size = 6.dp, glow = true)
                            }
                            Text(
                                text = item.lastRunText,
                                style = MaterialTheme.typography.titleSmall.copy(
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Medium,
                                ),
                                color = when {
                                    isAmber -> colors.statusWaiting
                                    item.isRunningNow -> colors.statusRunning
                                    else -> colors.inkReading
                                },
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AlwaysOnAutomationCard(
    item: AutomationItem,
    cardTag: String,
    onClick: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    AntigravitySurfaceCard(
        modifier = Modifier
            .fillMaxWidth()
            .testTag(cardTag),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 11.dp),
        onClick = onClick,
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            StatusDot(
                color = colors.statusDone,
                size = 9.dp,
                glow = true,
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = item.title,
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    color = colors.inkReading,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = item.scheduleSummary,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = item.lastRunText,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkLabel,
                    maxLines = 1,
                )
            }
            Icon(
                imageVector = Icons.Rounded.ChevronRight,
                contentDescription = null,
                tint = colors.inkMuted,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

@Composable
private fun PausedAutomationCard(
    item: AutomationItem,
    resumeButtonTag: String,
    onResume: () -> Unit,
) {
    val colors = MaterialTheme.antigravityColors
    AntigravitySurfaceCard(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    text = item.title,
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    color = colors.inkSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = item.scheduleSummary,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.inkMuted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            FilledTonalButton(
                onClick = onResume,
                modifier = Modifier
                    .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                    .testTag(resumeButtonTag),
                shape = RoundedCornerShape(AntigravityDesignTokens.PillCornerRadius),
                colors = ButtonDefaults.filledTonalButtonColors(
                    containerColor = colors.surfaceBadge,
                    contentColor = colors.inkReading,
                ),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
            ) {
                Text(
                    text = "Resume",
                    style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                    maxLines = 1,
                )
            }
        }
    }
}
