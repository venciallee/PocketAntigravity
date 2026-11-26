package dev.antigravity.android.ui.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.runtime.LaunchedEffect
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
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.android.ui.home.AgentsHomeScreen
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.AppLanguage
import dev.antigravity.shared.model.CascadeModelConfig
import dev.antigravity.shared.model.ThinkingEffortLevel
import kotlinx.coroutines.CancellationException

/**
 * UE09_MODEL_AND_MODE (`and-model.png`): Official Antigravity 2.x Model & Thinking Effort
 * Material 3 bottom sheet — zero legacy Planning/Fast toggle, featuring Orchestrator,
 * grouped model families (one row per model; inline Thinking FilterChips expand ONLY for
 * the selected model using that model's actual `supportedEfforts`), expandable `More models`,
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
    val lang = LocalAppLanguage.current
    val settingsState by coordinator.settingsStore.state.collectAsState()
    val connectionState by coordinator.connectionState.collectAsState()
    var showMoreModels by remember { mutableStateOf(false) }
    var showUsageDetails by remember { mutableStateOf(false) }

    val selectedModelId = settingsState.selectedModelId
    val selectedEffort = settingsState.selectedEffort
    val quota = settingsState.quota

    val catalogModels = remember(settingsState.models) {
        settingsState.models.ifEmpty { CascadeModelConfig.liveDefaultCatalog }
    }
    val orchestratorModels = remember(catalogModels) {
        catalogModels.filter { it.isOrchestrator }
    }
    val activeOrchestrator = remember(orchestratorModels, selectedModelId) {
        orchestratorModels.firstOrNull { it.containsModelId(selectedModelId) }
            ?: orchestratorModels.firstOrNull()
    }
    val partitioned = remember(catalogModels) {
        CascadeModelConfig.partitionPrimaryAndExtraModels(catalogModels)
    }
    val primaryModels = partitioned.first
    val extraModels = partitioned.second

    LaunchedEffect(connectionState.hasPairedBackend, connectionState.isConnected) {
        if (connectionState.hasPairedBackend || connectionState.isConnected) {
            try {
                coordinator.refreshModelCatalog()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // Best-effort live catalog refresh when opening model sheet.
            }
        }
    }

    LaunchedEffect(selectedModelId, extraModels) {
        if (extraModels.any { it.containsModelId(selectedModelId) }) {
            showMoreModels = true
        }
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
                        text = tr("Model", "模型"),
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
                            text = tr("Done", "完成"),
                            style = MaterialTheme.typography.titleSmall.copy(
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                            color = colors.accentPeriwinkle,
                        )
                    }
                }

                // Orchestrator row (with inline planner selector when selected and multiple presets exist)
                if (activeOrchestrator != null) {
                    val orchestratorSelected = settingsState.isEffortLockedForOrchestrator
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(if (orchestratorSelected) colors.surfaceElevated else Color.Transparent)
                            .clickable { coordinator.settingsStore.selectModel(activeOrchestrator.modelId) }
                            .padding(horizontal = 24.dp, vertical = 12.dp)
                            .testTag("model-row-orchestrator"),
                        verticalArrangement = Arrangement.spacedBy(if (orchestratorSelected && orchestratorModels.size > 1) 10.dp else 2.dp),
                    ) {
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    text = tr("Orchestrator", "编排器"),
                                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.5.sp),
                                    color = colors.inkReading,
                                )
                                if (orchestratorSelected) {
                                    Icon(
                                        imageVector = Icons.Rounded.Check,
                                        contentDescription = tr("Selected", "已选"),
                                        tint = colors.accentPeriwinkle,
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                            }
                            Text(
                                text = activeOrchestrator.orchestratorSubtitle,
                                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp),
                                color = colors.inkSecondary,
                            )
                        }

                        if (orchestratorSelected && orchestratorModels.size > 1) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                orchestratorModels.forEach { preset ->
                                    val presetSelected = preset.containsModelId(selectedModelId)
                                    val roleLabel = preset.shortOrchestratorRoleLabel
                                    Surface(
                                        onClick = { coordinator.settingsStore.selectModel(preset.modelId) },
                                        modifier = Modifier.testTag("orchestrator-chip-${roleLabel.lowercase()}"),
                                        shape = RoundedCornerShape(8.dp),
                                        color = if (presetSelected) colors.surfaceActiveTab else Color.Transparent,
                                        border = BorderStroke(
                                            width = 1.dp,
                                            color = if (presetSelected) colors.surfaceActiveTab else colors.cardBorder,
                                        ),
                                    ) {
                                        Row(
                                            modifier = Modifier.padding(horizontal = 11.dp, vertical = 7.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(5.dp),
                                        ) {
                                            if (presetSelected) {
                                                Icon(
                                                    imageVector = Icons.Rounded.Check,
                                                    contentDescription = null,
                                                    tint = colors.pillActiveForeground,
                                                    modifier = Modifier.size(15.dp),
                                                )
                                            }
                                            Text(
                                                text = roleLabel,
                                                style = MaterialTheme.typography.labelLarge.copy(
                                                    fontSize = 13.5.sp,
                                                    fontWeight = FontWeight.Medium,
                                                ),
                                                color = if (presetSelected) colors.pillActiveForeground else colors.inkReading,
                                                maxLines = 1,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Step 1: Primary Models List (one row per model family; Step 2 effort chips expand when selected)
                primaryModels.forEach { model ->
                    ModelPickerRow(
                        model = model,
                        isSelected = model.containsModelId(selectedModelId),
                        selectedEffort = selectedEffort,
                        onSelectModel = { coordinator.settingsStore.selectModel(model.modelId) },
                        onSelectEffort = { level -> coordinator.settingsStore.selectThinkingEffort(level) },
                    )
                }

                // Expandable `More models ⌄`
                if (extraModels.isNotEmpty()) {
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
                            text = if (showMoreModels) tr("Fewer models", "收起更多模型") else tr("More models", "更多模型"),
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
                            ModelPickerRow(
                                model = extra,
                                isSelected = extra.containsModelId(selectedModelId),
                                selectedEffort = selectedEffort,
                                onSelectModel = { coordinator.settingsStore.selectModel(extra.modelId) },
                                onSelectEffort = { level -> coordinator.settingsStore.selectThinkingEffort(level) },
                            )
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
                        label = tr("Five Hour Limit Remaining", "5 小时剩余额度"),
                        trailing = "${quota.geminiFiveHourPercent}% · ${quota.refreshCountdownLabel}",
                        fraction = quota.geminiFiveHourRemaining.toFloat(),
                    )
                    QuotaProgressBarRow(
                        label = tr("Weekly Limit Remaining", "本周剩余额度"),
                        trailing = tr(
                            "${quota.geminiWeeklyPercent}% · resets Mon",
                            "${quota.geminiWeeklyPercent}% · 周一重置",
                        ),
                        fraction = quota.geminiWeeklyRemaining.toFloat(),
                    )

                    Text(
                        text = if (showUsageDetails) {
                            tr(
                                "Hide Usage (${quota.planTierLabel} · Partner ${quota.partnerWeeklyPercent}%)",
                                "收起用量（${quota.planTierLabel} · 合作模型 ${quota.partnerWeeklyPercent}%）",
                            )
                        } else {
                            tr("View Usage", "查看用量")
                        },
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
private fun ModelPickerRow(
    model: CascadeModelConfig,
    isSelected: Boolean,
    selectedEffort: ThinkingEffortLevel,
    onSelectModel: () -> Unit,
    onSelectEffort: (ThinkingEffortLevel) -> Unit,
) {
    val colors = LocalAntigravityColors.current
    val lang = LocalAppLanguage.current
    val cleanName = model.canonicalDisplayName
    val supportsEffort = model.supportsEffortAdjustment
    val isFlagshipNeon = model.modelId == "MODEL_GOOGLE_GEMINI_4_NEON" ||
        cleanName.contains("gemini 4 neon", ignoreCase = true)
    val nonNewTag = model.badgeTag?.takeIf { it.isNotBlank() && !it.equals("New", ignoreCase = true) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(if (isSelected) colors.surfaceElevated else Color.Transparent)
            .clickable(onClick = onSelectModel)
            .padding(horizontal = 24.dp, vertical = 14.dp)
            .testTag("model-row-${model.modelId}"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = cleanName,
                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.5.sp),
                color = colors.inkReading,
            )
            if (model.isNewBadge && isFlagshipNeon) {
                Surface(
                    shape = RoundedCornerShape(6.dp),
                    color = colors.surfaceActiveTab,
                ) {
                    Text(
                        text = tr("New", "新"),
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontSize = 11.5.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.pillActiveForeground,
                        modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
                    )
                }
            } else if (nonNewTag != null) {
                Surface(
                    shape = RoundedCornerShape(6.dp),
                    color = colors.surfaceElevated,
                ) {
                    Text(
                        text = nonNewTag,
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.inkSecondary,
                        modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
                    )
                }
            }
            if (isSelected) {
                Icon(
                    imageVector = Icons.Rounded.Check,
                    contentDescription = tr("Selected", "已选"),
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
                model.supportedEfforts.forEach { level ->
                    val label = effortDisplayLabel(level, lang)
                    val chipSelected = selectedEffort == level
                    Surface(
                        onClick = { onSelectEffort(level) },
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

private fun effortDisplayLabel(level: ThinkingEffortLevel, lang: AppLanguage): String = when (level) {
    ThinkingEffortLevel.LOW -> lang.t("Low", "低")
    ThinkingEffortLevel.MEDIUM -> lang.t("Medium", "中")
    ThinkingEffortLevel.HIGH -> lang.t("High", "高")
    ThinkingEffortLevel.EXTRA -> lang.t("Extra High", "极高")
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
