package dev.antigravity.android.ui.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bolt
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.components.SectionHeaderLabel
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeModelConfig
import dev.antigravity.shared.model.ThinkingEffortLevel

/**
 * UE09_MODEL_AND_MODE: Material 3 Modal Bottom Sheet for choosing execution mode (`Planning` vs `Fast`),
 * 4-step Thinking Effort (`Low`/`Medium`/`High`/`Extra` with Orchestrator effort-lock hint),
 * model catalog + Dual-Pool Usage Quota, and Custom Agent persona chips.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ModelAndModeSheetScreen(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val settingsState by coordinator.settingsStore.state.collectAsState()

    val displayedModels = remember(settingsState.models) {
        selectPrioritizedSheetModels(settingsState.models)
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(colors.canvasObsidian),
    ) {
        // Dimmed backdrop peeking above sheet
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = if (colors.isDark) 0.56f else 0.34f))
                .clickable(onClick = onDismiss),
        )

        // Material 3 Sheet Container
        Surface(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(top = 54.dp),
            shape = RoundedCornerShape(
                topStart = AntigravityDesignTokens.SheetCornerRadius,
                topEnd = AntigravityDesignTokens.SheetCornerRadius,
            ),
            color = colors.surfaceSheet,
            border = BorderStroke(1.dp, colors.cardBorder),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .navigationBarsPadding(),
            ) {
                // Drag Handle
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 10.dp, bottom = 2.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        modifier = Modifier
                            .width(38.dp)
                            .height(4.dp)
                            .clip(RoundedCornerShape(100.dp))
                            .background(colors.sheetHandle),
                    )
                }

                // Header Row: Model & Mode + Done
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 2.dp),
                ) {
                    Text(
                        text = "Model & Mode",
                        style = MaterialTheme.typography.titleMedium.copy(
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                        ),
                        color = colors.inkReading,
                        modifier = Modifier.align(Alignment.Center),
                    )
                    TextButton(
                        onClick = onDismiss,
                        modifier = Modifier
                            .align(Alignment.CenterEnd)
                            .defaultMinSize(
                                minWidth = AntigravityDesignTokens.MinTouchTarget,
                                minHeight = AntigravityDesignTokens.MinTouchTarget,
                            )
                            .testTag("btn-model-done"),
                    ) {
                        Text(
                            text = "Done",
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 15.sp,
                                fontWeight = FontWeight.SemiBold,
                            ),
                            color = colors.accentPeriwinkle,
                        )
                    }
                }

                Column(
                    modifier = Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp, vertical = 6.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    // Dual Mode Cards: Planning vs Fast
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        ExecutionModeCard(
                            title = "Planning",
                            description = "Plans first and writes artifacts for you to review",
                            icon = Icons.Rounded.Description,
                            selected = settingsState.selectedMode == CascadeExecutionMode.PLANNING,
                            onClick = { coordinator.settingsStore.selectMode(CascadeExecutionMode.PLANNING) },
                            modifier = Modifier
                                .weight(1f)
                                .testTag("mode-card-planning"),
                        )
                        ExecutionModeCard(
                            title = "Fast",
                            description = "Acts directly — best for small, local edits",
                            icon = Icons.Rounded.Bolt,
                            selected = settingsState.selectedMode == CascadeExecutionMode.FAST,
                            onClick = { coordinator.settingsStore.selectMode(CascadeExecutionMode.FAST) },
                            modifier = Modifier
                                .weight(1f)
                                .testTag("mode-card-fast"),
                        )
                    }

                    // Compact 4-Step Thinking Effort Selector
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            SectionHeaderLabel(
                                title = "THINKING EFFORT",
                                modifier = Modifier.weight(1f),
                            )
                            if (settingsState.isEffortLockedForOrchestrator) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.Lock,
                                        contentDescription = "Orchestrator locked",
                                        tint = colors.statusWaiting,
                                        modifier = Modifier.size(13.dp),
                                    )
                                    Text(
                                        text = "Managed by Orchestrator",
                                        style = MaterialTheme.typography.labelSmall.copy(
                                            fontFamily = FontFamily.SansSerif,
                                        ),
                                        color = colors.statusWaiting,
                                    )
                                }
                            }
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            ThinkingEffortLevel.entries.forEach { effort ->
                                val isSelected = settingsState.selectedEffort == effort
                                val locked = settingsState.isEffortLockedForOrchestrator
                                Surface(
                                    onClick = {
                                        if (!locked) {
                                            coordinator.settingsStore.selectThinkingEffort(effort)
                                        }
                                    },
                                    enabled = !locked,
                                    modifier = Modifier
                                        .weight(1f)
                                        .defaultMinSize(minHeight = 36.dp)
                                        .testTag("effort-pill-${effort.cliValue}"),
                                    shape = RoundedCornerShape(10.dp),
                                    color = when {
                                        locked -> colors.surfaceSubtleBox.copy(alpha = 0.6f)
                                        isSelected -> colors.surfaceSelectionTint
                                        else -> colors.surfaceElevated
                                    },
                                    border = BorderStroke(
                                        width = 1.dp,
                                        color = when {
                                            locked -> colors.cardBorder
                                            isSelected -> colors.accentPeriwinkle
                                            else -> colors.cardBorder
                                        },
                                    ),
                                ) {
                                    Box(
                                        modifier = Modifier.padding(vertical = 7.dp, horizontal = 4.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(
                                            text = effort.displayTitle,
                                            style = MaterialTheme.typography.labelMedium.copy(
                                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                                            ),
                                            color = when {
                                                locked -> colors.inkMuted
                                                isSelected -> colors.accentPeriwinkle
                                                else -> colors.inkLabel
                                            },
                                            maxLines = 1,
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // MODEL Catalog Group Card
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        SectionHeaderLabel(title = "MODEL")
                        Surface(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(18.dp),
                            color = colors.surfaceSheetGroup,
                            border = BorderStroke(1.dp, colors.cardBorder),
                        ) {
                            Column(modifier = Modifier.fillMaxWidth()) {
                                displayedModels.forEachIndexed { idx, model ->
                                    val isSelected = isModelSelected(
                                        selectedModelId = settingsState.selectedModelId,
                                        model = model,
                                    )
                                    ModelOptionRow(
                                        model = model,
                                        isSelected = isSelected,
                                        onClick = { coordinator.settingsStore.selectModel(model.modelId) },
                                    )
                                    if (idx < displayedModels.lastIndex) {
                                        HorizontalDivider(
                                            color = colors.subtleDivider,
                                            modifier = Modifier.padding(horizontal = 14.dp),
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Compact Dual-Pool Usage Quota Indicator
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .testTag("quota-summary-strip"),
                        shape = RoundedCornerShape(12.dp),
                        color = colors.surfaceCard,
                        border = BorderStroke(1.dp, colors.cardBorder),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Speed,
                                contentDescription = "Usage Quota",
                                tint = colors.accentPeriwinkle,
                                modifier = Modifier.size(16.dp),
                            )
                            Text(
                                text = settingsState.quota.planTierLabel,
                                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                                color = colors.inkReading,
                                maxLines = 1,
                            )
                            Spacer(modifier = Modifier.weight(1f))
                            Text(
                                text = "Gemini ${settingsState.quota.geminiWeeklyPercent}% · Partner ${settingsState.quota.partnerWeeklyPercent}%",
                                style = MaterialTheme.typography.labelSmall,
                                color = colors.inkSecondary,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }

                    // AGENT Persona Chips
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        SectionHeaderLabel(title = "AGENT")
                        val personas = settingsState.availableAgentPersonas.ifEmpty {
                            CascadeModelConfig.availableAgents
                        }
                        FlowRow(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            personas.forEach { persona ->
                                val isSelected = settingsState.selectedAgentPersona == persona
                                val isMono = persona != "Default"
                                Surface(
                                    onClick = { coordinator.settingsStore.selectAgentPersona(persona) },
                                    modifier = Modifier
                                        .defaultMinSize(minHeight = 40.dp)
                                        .testTag(agentPersonaTestTag(persona)),
                                    shape = RoundedCornerShape(100.dp),
                                    color = if (isSelected) colors.pillActiveBackground else colors.surfaceElevated,
                                    border = if (isSelected) null else BorderStroke(1.dp, colors.cardBorder),
                                ) {
                                    Box(
                                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 9.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(
                                            text = persona,
                                            style = MaterialTheme.typography.labelLarge.copy(
                                                fontFamily = if (isMono) FontFamily.Monospace else FontFamily.SansSerif,
                                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Medium,
                                            ),
                                            color = if (isSelected) colors.pillActiveForeground else colors.inkLabel,
                                        )
                                    }
                                }
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(6.dp))
                }
            }
        }
    }
}

@Composable
private fun ExecutionModeCard(
    title: String,
    description: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    Surface(
        onClick = onClick,
        modifier = modifier.defaultMinSize(minHeight = 86.dp),
        shape = RoundedCornerShape(16.dp),
        color = if (selected) colors.surfaceSelectionTint else colors.surfaceElevated,
        border = BorderStroke(
            width = if (selected) 1.5.dp else 1.dp,
            color = if (selected) colors.accentPeriwinkle else colors.cardBorder,
        ),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = title,
                    tint = if (selected) colors.accentPeriwinkle else colors.inkSecondary,
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    color = colors.inkReading,
                )
            }
            Text(
                text = description,
                style = MaterialTheme.typography.bodySmall.copy(
                    fontSize = 12.sp,
                    lineHeight = 16.sp,
                ),
                color = colors.inkSecondary,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun ModelOptionRow(
    model: CascadeModelConfig,
    isSelected: Boolean,
    onClick: () -> Unit,
) {
    val colors = LocalAntigravityColors.current
    val badgeText = when {
        model.displayName.contains("Claude", ignoreCase = true) && model.supportsThinking -> "Thinking"
        model.isOrchestrator -> "Dual"
        model.isNewBadge -> "New"
        else -> null
    }
    val cleanTitle = model.displayName.replace(" (Thinking)", "").trim()
    val subtitleText = model.requiresUpgradeNote?.let { "Requires $it" } ?: model.subtitle

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 52.dp)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp)
            .testTag(modelRowTestTag(model)),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    text = cleanTitle,
                    style = MaterialTheme.typography.titleSmall.copy(
                        fontSize = 14.5.sp,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    color = colors.inkReading,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (badgeText != null) {
                    Surface(
                        shape = RoundedCornerShape(6.dp),
                        color = colors.surfaceBadge,
                    ) {
                        Text(
                            text = badgeText,
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontFamily = FontFamily.SansSerif,
                                fontSize = 10.sp,
                            ),
                            color = colors.inkSecondary,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        )
                    }
                }
            }
            Text(
                text = subtitleText,
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                color = colors.inkSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        if (isSelected) {
            Icon(
                imageVector = Icons.Rounded.Check,
                contentDescription = "Selected",
                tint = colors.accentPeriwinkle,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

private fun selectPrioritizedSheetModels(allModels: List<CascadeModelConfig>): List<CascadeModelConfig> {
    val priorityPredicates: List<(CascadeModelConfig) -> Boolean> = listOf(
        { it.displayName.contains("Gemini 3.1 Pro", ignoreCase = true) || it.modelId == "MODEL_PLACEHOLDER_M37" },
        { it.displayName.contains("Gemini 3.8 Flash", ignoreCase = true) },
        { it.displayName.contains("Claude Opus 5.5", ignoreCase = true) },
        { it.displayName.contains("Claude Sonnet 5.5", ignoreCase = true) },
        { it.displayName.contains("Gemini 4 Neon", ignoreCase = true) },
        { it.modelId == "MODEL_ORCHESTRATOR_NEON" || it.displayName.contains("Orchestrator (Neon)", ignoreCase = true) },
    )
    val picked = mutableListOf<CascadeModelConfig>()
    val seenIds = mutableSetOf<String>()
    for (pred in priorityPredicates) {
        val found = allModels.firstOrNull { pred(it) && it.modelId !in seenIds }
        if (found != null) {
            picked.add(found)
            seenIds.add(found.modelId)
        }
    }
    return picked.ifEmpty { allModels.take(6) }
}

private fun isModelSelected(selectedModelId: String, model: CascadeModelConfig): Boolean {
    if (selectedModelId == model.modelId) return true
    if (selectedModelId == "MODEL_GOOGLE_GEMINI_3_1_PRO" && model.modelId == "MODEL_PLACEHOLDER_M37") return true
    if (selectedModelId == "MODEL_PLACEHOLDER_M37" && model.displayName.contains("Gemini 3.1 Pro", ignoreCase = true)) {
        return true
    }
    return false
}

private fun modelRowTestTag(model: CascadeModelConfig): String {
    val lower = model.displayName.lowercase()
    return when {
        lower.contains("3.1 pro") -> "model-row-gemini-pro"
        lower.contains("3.8 flash") -> "model-row-gemini-flash"
        lower.contains("claude opus") -> "model-row-claude-opus"
        lower.contains("claude sonnet") -> "model-row-claude-sonnet"
        lower.contains("gemini 4 neon") -> "model-row-gemini-4-neon"
        lower.contains("orchestrator") -> "model-row-orchestrator-neon"
        else -> "model-row-${model.modelId.lowercase()}"
    }
}

private fun agentPersonaTestTag(persona: String): String {
    val slug = persona.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')
    return "agent-pill-$slug"
}
