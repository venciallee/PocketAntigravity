package dev.antigravity.android.ui.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.android.ui.home.AgentsHomeScreen
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.CascadeModelConfig
import dev.antigravity.shared.model.ThinkingEffortLevel

/**
 * UE09_MODEL_AND_MODE (`and-model.png`): Official Antigravity 2.x Model & Thinking Effort
 * Material 3 bottom sheet — zero legacy Planning/Fast toggle, featuring Orchestrator,
 * Gemini 4 Neon + 4-level Thinking FilterChips (`Low`/`Medium`/`High`/`Extra High`),
 * Carbon/Argon/Hydrogen/Claude Opus 5.5/Gemini 3.8 Flash, expandable `More models`,
 * and Five Hour / Weekly quota bars + `View Usage`.
 */
@Composable
fun ModelAndModeSheetScreen(
    coordinator: AntigravityCoreCoordinator,
    onDismiss: () -> Unit,
    showHomeBackdrop: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val settingsState by coordinator.settingsStore.state.collectAsState()
    var showMoreModels by remember { mutableStateOf(false) }
    var showUsageDetails by remember { mutableStateOf(false) }

    val selectedModelId = settingsState.selectedModelId
    val selectedEffort = settingsState.selectedEffort
    val quota = settingsState.quota

    val primaryModels = remember(settingsState.models) {
        buildPrimaryModelList(settingsState.models)
    }
    val extraModels = remember(settingsState.models, primaryModels) {
        val primaryIds = primaryModels.map { it.modelId }.toSet()
        settingsState.models.filterNot { it.modelId in primaryIds }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(if (showHomeBackdrop) colors.canvasObsidian else Color.Transparent),
    ) {
        if (showHomeBackdrop) {
            AgentsHomeScreen(
                coordinator = coordinator,
                onOpenSidebar = {},
                onOpenConversation = {},
                showGreeting = false,
                showNeedsApprovalBanner = false,
                showSearchAction = false,
                showHostChevron = false,
                modifier = Modifier.fillMaxSize(),
            )
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = if (colors.isDark) 0.56f else 0.34f))
                .clickable(onClick = onDismiss),
        )

        Surface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .testTag("model-picker-sheet"),
            shape = RoundedCornerShape(
                topStart = AntigravityDesignTokens.SheetCornerRadius,
                topEnd = AntigravityDesignTokens.SheetCornerRadius,
            ),
            color = colors.surfaceSheet,
            border = BorderStroke(1.dp, colors.cardBorder),
            tonalElevation = 4.dp,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .verticalScroll(rememberScrollState())
                    .padding(bottom = 22.dp),
            ) {
                // Drag Handle
                Box(
                    modifier = Modifier
                        .align(Alignment.CenterHorizontally)
                        .padding(top = 12.dp, bottom = 10.dp)
                        .size(width = 36.dp, height = 4.dp)
                        .clip(RoundedCornerShape(100.dp))
                        .background(colors.sheetHandle),
                )

                // Header: Model (left) + Done (right)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 24.dp, end = 14.dp, bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Model",
                        style = MaterialTheme.typography.headlineSmall.copy(
                            fontSize = 23.sp,
                            fontWeight = FontWeight.Normal,
                        ),
                        color = colors.inkReading,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(
                        onClick = onDismiss,
                        modifier = Modifier.testTag("btn-model-done"),
                    ) {
                        Text(
                            text = "Done",
                            style = MaterialTheme.typography.titleSmall.copy(
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.accentPeriwinkle,
                        )
                    }
                }

                // Orchestrator row
                val orchestratorSelected = selectedModelId.contains("ORCHESTRATOR", ignoreCase = true)
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(if (orchestratorSelected) colors.surfaceElevated else Color.Transparent)
                        .clickable { coordinator.settingsStore.selectModel("MODEL_ORCHESTRATOR_NEON") }
                        .padding(horizontal = 24.dp, vertical = 12.dp)
                        .testTag("model-row-orchestrator"),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            text = "Orchestrator",
                            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.5.sp),
                            color = colors.inkReading,
                        )
                        if (orchestratorSelected) {
                            Icon(
                                imageVector = Icons.Rounded.Check,
                                contentDescription = "Selected",
                                tint = colors.accentPeriwinkle,
                                modifier = Modifier.size(18.dp),
                            )
                        }
                    }
                    Text(
                        text = "Neon plans · Hydrogen executes",
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                        color = colors.inkSecondary,
                    )
                }

                // Primary Models List (`Gemini 4 Neon` expanded with 4 FilterChips when selected)
                primaryModels.forEach { model ->
                    val isSelected = selectedModelId == model.modelId
                    val supportsEffort = model.supportedEfforts.isNotEmpty()
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(if (isSelected) colors.surfaceElevated else Color.Transparent)
                            .clickable { coordinator.settingsStore.selectModel(model.modelId) }
                            .padding(horizontal = 24.dp, vertical = 14.dp)
                            .testTag("model-row-${model.modelId}"),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Text(
                                text = model.displayName,
                                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.5.sp),
                                color = colors.inkReading,
                            )
                            if (model.displayName == "Gemini 4 Neon") {
                                Surface(
                                    shape = RoundedCornerShape(6.dp),
                                    color = colors.surfaceActiveTab,
                                ) {
                                    Text(
                                        text = "New",
                                        style = MaterialTheme.typography.labelSmall.copy(
                                            fontSize = 11.5.sp,
                                            fontWeight = FontWeight.Medium,
                                        ),
                                        color = colors.pillActiveForeground,
                                        modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
                                    )
                                }
                            }
                            if (isSelected) {
                                Icon(
                                    imageVector = Icons.Rounded.Check,
                                    contentDescription = "Selected",
                                    tint = colors.accentPeriwinkle,
                                    modifier = Modifier.size(19.dp),
                                )
                            }
                        }

                        if (isSelected && supportsEffort) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                listOf(
                                    ThinkingEffortLevel.LOW to "Low",
                                    ThinkingEffortLevel.MEDIUM to "Medium",
                                    ThinkingEffortLevel.HIGH to "High",
                                    ThinkingEffortLevel.EXTRA to "Extra High",
                                ).forEach { (level, label) ->
                                    val chipSelected = selectedEffort == level
                                    Surface(
                                        onClick = { coordinator.settingsStore.selectThinkingEffort(level) },
                                        modifier = Modifier.testTag("effort-chip-${level.name.lowercase()}"),
                                        shape = RoundedCornerShape(8.dp),
                                        color = if (chipSelected) colors.surfaceActiveTab else Color.Transparent,
                                        border = BorderStroke(
                                            width = 1.dp,
                                            color = if (chipSelected) colors.surfaceActiveTab else colors.cardBorder,
                                        ),
                                    ) {
                                        Row(
                                            modifier = Modifier.padding(horizontal = 11.dp, vertical = 7.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(5.dp),
                                        ) {
                                            if (chipSelected) {
                                                Icon(
                                                    imageVector = Icons.Rounded.Check,
                                                    contentDescription = null,
                                                    tint = colors.pillActiveForeground,
                                                    modifier = Modifier.size(15.dp),
                                                )
                                            }
                                            Text(
                                                text = label,
                                                style = MaterialTheme.typography.labelLarge.copy(
                                                    fontSize = 13.5.sp,
                                                    fontWeight = FontWeight.Medium,
                                                ),
                                                color = if (chipSelected) colors.pillActiveForeground else colors.inkReading,
                                                maxLines = 1,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Expandable `More models ⌄`
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { showMoreModels = !showMoreModels }
                        .padding(horizontal = 24.dp, vertical = 14.dp)
                        .testTag("btn-more-models"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        text = "More models",
                        style = MaterialTheme.typography.titleSmall.copy(fontSize = 14.5.sp, fontWeight = FontWeight.Medium),
                        color = colors.accentPeriwinkle,
                    )
                    Icon(
                        imageVector = if (showMoreModels) Icons.Rounded.KeyboardArrowUp else Icons.Rounded.KeyboardArrowDown,
                        contentDescription = null,
                        tint = colors.accentPeriwinkle,
                        modifier = Modifier.size(18.dp),
                    )
                }

                if (showMoreModels) {
                    extraModels.forEach { extra ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { coordinator.settingsStore.selectModel(extra.modelId) }
                                .padding(horizontal = 24.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                text = extra.displayName,
                                style = MaterialTheme.typography.bodyMedium,
                                color = colors.inkLabel,
                                modifier = Modifier.weight(1f),
                            )
                            if (selectedModelId == extra.modelId) {
                                Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.accentPeriwinkle, modifier = Modifier.size(18.dp))
                            }
                        }
                    }
                }

                HorizontalDivider(
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
                    color = colors.subtleDivider,
                )

                // Quota Bars: Five Hour Limit Remaining & Weekly Limit Remaining
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp, vertical = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    QuotaProgressBarRow(
                        label = "Five Hour Limit Remaining",
                        trailing = "${quota.geminiFiveHourPercent}% · ${quota.refreshCountdownLabel}",
                        fraction = quota.geminiFiveHourRemaining.toFloat(),
                    )
                    QuotaProgressBarRow(
                        label = "Weekly Limit Remaining",
                        trailing = "${quota.geminiWeeklyPercent}% · resets Mon",
                        fraction = quota.geminiWeeklyRemaining.toFloat(),
                    )

                    Text(
                        text = if (showUsageDetails) "Hide Usage (${quota.planTierLabel} · Partner ${quota.partnerWeeklyPercent}%)" else "View Usage",
                        style = MaterialTheme.typography.titleSmall.copy(
                            fontSize = 14.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.accentPeriwinkle,
                        modifier = Modifier
                            .clickable { showUsageDetails = !showUsageDetails }
                            .padding(top = 4.dp)
                            .testTag("btn-view-usage"),
                    )
                }
            }
        }
    }
}

@Composable
private fun QuotaProgressBarRow(
    label: String,
    trailing: String,
    fraction: Float,
) {
    val colors = LocalAntigravityColors.current
    val clamped = fraction.coerceIn(0f, 1f)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                color = colors.inkSecondary,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = trailing,
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                color = colors.inkSecondary,
            )
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(4.dp)
                .clip(RoundedCornerShape(100.dp))
                .background(colors.ringTrack),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(clamped)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(100.dp))
                    .background(colors.accentPeriwinkle),
            )
        }
    }
}

private fun buildPrimaryModelList(catalog: List<CascadeModelConfig>): List<CascadeModelConfig> {
    val preferredIds = listOf(
        "MODEL_GOOGLE_GEMINI_4_NEON",
        "MODEL_GOOGLE_GEMINI_4_CARBON",
        "MODEL_GOOGLE_GEMINI_4_ARGON",
        "MODEL_GOOGLE_GEMINI_4_HYDROGEN",
        "MODEL_CLAUDE_5_5_OPUS_THINKING",
        "MODEL_GOOGLE_GEMINI_3_8_FLASH",
    )
    val byId = catalog.associateBy { it.modelId }
    val resolved = preferredIds.mapNotNull { byId[it] }
    if (resolved.isNotEmpty()) return resolved
    return CascadeModelConfig.liveDefaultCatalog.filterNot { it.isOrchestrator }.take(6)
}
