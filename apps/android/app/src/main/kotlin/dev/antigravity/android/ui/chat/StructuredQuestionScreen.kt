package dev.antigravity.android.ui.chat

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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.components.AntigravitySurfaceCard
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.StructuredQuestionStepItem
import kotlinx.coroutines.launch

/**
 * UE10_STRUCTURED_QUESTION: Native Material 3 multi-step interactive structured question screen
 * (`Audit log for admin actions`), supporting multi-select checkboxes, single-select radio rows,
 * custom write-in ("Something else..."), stepper chips, and freeform reply fallback.
 */
@Composable
fun StructuredQuestionScreen(
    coordinator: AntigravityCoreCoordinator,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val chatState by coordinator.chatState.collectAsState()
    val scope = rememberCoroutineScope()

    val questions = chatState.structuredQuestions.ifEmpty { defaultStructuredQuestionsFallback() }
    val activeIdx = chatState.activeQuestionStepIndex.coerceIn(0, questions.lastIndex)
    val activeQuestion = questions[activeIdx]
    val isLastStep = activeIdx >= questions.lastIndex

    var freeformReply by remember { mutableStateOf("") }
    var submittedBanner by remember { mutableStateOf<String?>(null) }

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
                    .padding(horizontal = 6.dp, vertical = 6.dp),
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
                        .testTag("btn-back-structured-question"),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "Back",
                        tint = colors.accentPeriwinkle,
                    )
                }

                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        text = "Audit log for admin actions",
                        style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Bold),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = "ledger-svc · Planning · Gemini 3.1 Pro",
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.inkSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }

                IconButton(
                    onClick = {},
                    modifier = Modifier.defaultMinSize(
                        minWidth = AntigravityDesignTokens.MinTouchTarget,
                        minHeight = AntigravityDesignTokens.MinTouchTarget,
                    ),
                ) {
                    Icon(
                        imageVector = Icons.Rounded.MoreVert,
                        contentDescription = "Options",
                        tint = colors.inkSecondary,
                    )
                }
            }
        },
        bottomBar = {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .imePadding()
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                shape = RoundedCornerShape(26.dp),
                color = colors.surfaceCard,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .defaultMinSize(minHeight = 52.dp)
                        .padding(start = 16.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(modifier = Modifier.weight(1f)) {
                        if (freeformReply.isEmpty()) {
                            Text(
                                text = "Reply in your own words",
                                style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                                color = colors.inkMuted,
                            )
                        }
                        BasicTextField(
                            value = freeformReply,
                            onValueChange = { freeformReply = it },
                            textStyle = MaterialTheme.typography.bodyLarge.copy(
                                fontSize = 15.sp,
                                color = colors.inkReading,
                            ),
                            cursorBrush = SolidColor(colors.accentPeriwinkle),
                            singleLine = true,
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("composer-freeform-reply"),
                        )
                    }

                    if (freeformReply.isNotBlank()) {
                        Surface(
                            onClick = {
                                val text = freeformReply.trim()
                                freeformReply = ""
                                scope.launch {
                                    coordinator.sendMessage(
                                        cascadeId = chatState.activeCascadeId.ifBlank { "cas-audit-log" },
                                        message = text,
                                    )
                                }
                                submittedBanner = "Reply sent to agent"
                            },
                            modifier = Modifier.size(38.dp),
                            shape = CircleShape,
                            color = colors.accentPeriwinkle,
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    imageVector = Icons.Rounded.ArrowUpward,
                                    contentDescription = "Send reply",
                                    tint = colors.inkOnPrimaryCta,
                                    modifier = Modifier.size(20.dp),
                                )
                            }
                        }
                    } else {
                        Surface(
                            onClick = {},
                            modifier = Modifier.size(38.dp),
                            shape = CircleShape,
                            color = colors.surfaceElevated,
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    imageVector = Icons.Rounded.Mic,
                                    contentDescription = "Voice reply",
                                    tint = colors.inkSecondary,
                                    modifier = Modifier.size(19.dp),
                                )
                            }
                        }
                    }
                }
            }
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Agent intro prompt
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(
                    imageVector = Icons.Rounded.AutoAwesome,
                    contentDescription = null,
                    tint = colors.accentPeriwinkle,
                    modifier = Modifier
                        .padding(top = 3.dp)
                        .size(18.dp),
                )
                Text(
                    text = "Before I draft the plan I need three decisions. Tap to answer — you can also reply in your own words.",
                    style = MaterialTheme.typography.bodyLarge.copy(
                        fontSize = 15.5.sp,
                        lineHeight = 23.sp,
                    ),
                    color = colors.inkReading,
                    modifier = Modifier.weight(1f),
                )
            }

            // Interactive M3 Question Card
            AntigravitySurfaceCard(
                modifier = Modifier.fillMaxWidth(),
                containerColor = colors.surfaceCard,
                borderColor = colors.cardBorder,
                cornerRadius = 22.dp,
                contentPadding = PaddingValues(16.dp),
            ) {
                // Stepper Chips Row
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    questions.forEachIndexed { idx, step ->
                        val isActive = idx == activeIdx
                        val stepTag = questionStepTag(step, idx)
                        val chipBg = if (isActive) colors.pillActiveBackground else colors.surfaceElevated
                        val chipFg = if (isActive) colors.pillActiveForeground else colors.inkSecondary

                        Surface(
                            onClick = { coordinator.chatStore.setActiveQuestionStepIndex(idx) },
                            modifier = Modifier
                                .weight(1f)
                                .defaultMinSize(minHeight = 38.dp)
                                .testTag(stepTag),
                            shape = RoundedCornerShape(100.dp),
                            color = chipBg,
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.Center,
                            ) {
                                if (step.isCompleted && !isActive) {
                                    Icon(
                                        imageVector = Icons.Rounded.Check,
                                        contentDescription = "Completed",
                                        tint = colors.statusDone,
                                        modifier = Modifier
                                            .padding(end = 4.dp)
                                            .size(14.dp),
                                    )
                                }
                                Text(
                                    text = "${step.stepNumber} ${step.shortTabTitle}",
                                    style = MaterialTheme.typography.labelMedium.copy(
                                        fontWeight = if (isActive) FontWeight.Bold else FontWeight.SemiBold,
                                    ),
                                    color = chipFg,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Question Metadata & Heading
                Text(
                    text = "Question ${activeQuestion.stepNumber} of ${questions.size} · ${
                        if (activeQuestion.isMultiSelect) "Select all that apply" else "Select one"
                    }",
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.inkSecondary,
                )

                Spacer(modifier = Modifier.height(6.dp))

                Text(
                    text = activeQuestion.questionTitle,
                    style = MaterialTheme.typography.titleLarge.copy(
                        fontSize = 20.sp,
                        lineHeight = 26.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    color = colors.inkReading,
                )

                Spacer(modifier = Modifier.height(16.dp))

                // Option Rows (Checkbox for multi-select, RadioButton for single-select)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    activeQuestion.options.forEach { option ->
                        val isSelected = option in activeQuestion.selectedOptions
                        val optionTag = questionOptionTag(option)
                        Surface(
                            modifier = Modifier
                                .fillMaxWidth()
                                .defaultMinSize(minHeight = 54.dp)
                                .clip(RoundedCornerShape(14.dp))
                                .clickable(role = if (activeQuestion.isMultiSelect) Role.Checkbox else Role.RadioButton) {
                                    coordinator.chatStore.toggleQuestionOption(option, activeIdx)
                                }
                                .testTag(optionTag),
                            shape = RoundedCornerShape(14.dp),
                            color = if (isSelected) colors.surfaceSelectionTint else colors.surfaceSubtleBox,
                            border = BorderStroke(
                                width = if (isSelected) 1.25.dp else 1.dp,
                                color = if (isSelected) colors.accentPeriwinkle.copy(alpha = 0.72f) else colors.cardBorder,
                            ),
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 12.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                if (activeQuestion.isMultiSelect) {
                                    Checkbox(
                                        checked = isSelected,
                                        onCheckedChange = null,
                                        colors = CheckboxDefaults.colors(
                                            checkedColor = colors.accentPeriwinkle,
                                            uncheckedColor = colors.inkMuted,
                                            checkmarkColor = colors.inkOnPrimaryCta,
                                        ),
                                    )
                                } else {
                                    RadioButton(
                                        selected = isSelected,
                                        onClick = null,
                                        colors = RadioButtonDefaults.colors(
                                            selectedColor = colors.accentPeriwinkle,
                                            unselectedColor = colors.inkMuted,
                                        ),
                                    )
                                }
                                Text(
                                    text = option,
                                    style = MaterialTheme.typography.titleSmall.copy(
                                        fontSize = 15.sp,
                                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                                    ),
                                    color = colors.inkReading,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }

                    // Custom write-in field ("Something else...")
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .defaultMinSize(minHeight = 52.dp),
                        shape = RoundedCornerShape(14.dp),
                        color = colors.surfaceObsidian,
                        border = BorderStroke(1.dp, colors.inkMuted.copy(alpha = 0.35f)),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Edit,
                                contentDescription = "Custom answer",
                                tint = colors.inkMuted,
                                modifier = Modifier.size(18.dp),
                            )
                            Box(modifier = Modifier.weight(1f)) {
                                if (activeQuestion.customWriteIn.isEmpty()) {
                                    Text(
                                        text = "Something else...",
                                        style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.sp),
                                        color = colors.inkMuted,
                                    )
                                }
                                BasicTextField(
                                    value = activeQuestion.customWriteIn,
                                    onValueChange = { text ->
                                        coordinator.chatStore.setQuestionCustomWriteIn(text, activeIdx)
                                    },
                                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                                        fontSize = 15.sp,
                                        color = colors.inkReading,
                                    ),
                                    cursorBrush = SolidColor(colors.accentPeriwinkle),
                                    singleLine = true,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .testTag("q-input-something-else"),
                                )
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(18.dp))

                // Card Footer Buttons: Back + Next / Submit
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    FilledTonalButton(
                        onClick = { coordinator.chatStore.previousQuestionStep() },
                        modifier = Modifier
                            .defaultMinSize(minWidth = 92.dp, minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .testTag("q-btn-back"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.filledTonalButtonColors(
                            containerColor = colors.surfaceElevated,
                            contentColor = colors.inkReading,
                        ),
                    ) {
                        Text(
                            text = "Back",
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                            ),
                        )
                    }

                    Button(
                        onClick = {
                            if (isLastStep) {
                                val summary = questions.joinToString("; ") { q ->
                                    val chosen = (q.selectedOptions.toList() + listOfNotNull(
                                        q.customWriteIn.takeIf { it.isNotBlank() },
                                    )).joinToString(", ")
                                    "${q.shortTabTitle}: ${chosen.ifBlank { "default" }}"
                                }
                                scope.launch {
                                    coordinator.sendMessage(
                                        cascadeId = chatState.activeCascadeId.ifBlank { "cas-audit-log" },
                                        message = "Decisions confirmed — $summary",
                                    )
                                }
                                submittedBanner = "Answers submitted to agent"
                            } else {
                                coordinator.chatStore.advanceQuestionStep()
                            }
                        },
                        modifier = Modifier
                            .weight(1f)
                            .defaultMinSize(minHeight = AntigravityDesignTokens.MinTouchTarget)
                            .testTag("q-btn-next"),
                        shape = RoundedCornerShape(100.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = colors.accentPeriwinkle,
                            contentColor = colors.inkOnPrimaryCta,
                        ),
                    ) {
                        Text(
                            text = if (isLastStep) "Submit" else "Next",
                            style = MaterialTheme.typography.labelLarge.copy(
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Bold,
                            ),
                        )
                    }
                }
            }

            if (submittedBanner != null) {
                Surface(
                    shape = RoundedCornerShape(12.dp),
                    color = colors.statusDone.copy(alpha = 0.14f),
                    border = BorderStroke(1.dp, colors.statusDone.copy(alpha = 0.35f)),
                ) {
                    Text(
                        text = submittedBanner.orEmpty(),
                        style = MaterialTheme.typography.labelLarge,
                        color = colors.statusDone,
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                    )
                }
            }
        }
    }
}

private fun questionStepTag(step: StructuredQuestionStepItem, idx: Int): String {
    val slug = step.shortTabTitle.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')
    return "q-step-${step.stepNumber}-$slug".ifBlank { "q-step-${idx + 1}" }
}

private fun questionOptionTag(option: String): String {
    val lower = option.lowercase()
    return when {
        lower.contains("freeze") -> "q-opt-freeze"
        lower.contains("limit") -> "q-opt-limit"
        lower.contains("adjustment") || lower.contains("ledger") -> "q-opt-adjustments"
        lower.contains("role") || lower.contains("permission") -> "q-opt-role"
        else -> "q-opt-${lower.replace(Regex("[^a-z0-9]+"), "-").trim('-')}"
    }
}

private fun defaultStructuredQuestionsFallback(): List<StructuredQuestionStepItem> = listOf(
    StructuredQuestionStepItem(
        id = "q-1",
        stepNumber = 1,
        shortTabTitle = "Storage",
        questionTitle = "Where should audit events be stored?",
        options = listOf("Append-only Postgres table", "Dedicated BigQuery sink", "Encrypted S3 parquet"),
        selectedOptions = setOf("Append-only Postgres table"),
        isCompleted = true,
        isMultiSelect = false,
    ),
    StructuredQuestionStepItem(
        id = "q-2",
        stepNumber = 2,
        shortTabTitle = "Actions",
        questionTitle = "Which admin actions should be audited?",
        options = listOf(
            "Account freeze / unfreeze",
            "Limit changes",
            "Manual ledger adjustments",
            "Role & permission changes",
        ),
        selectedOptions = setOf(
            "Account freeze / unfreeze",
            "Limit changes",
            "Manual ledger adjustments",
        ),
        isCompleted = false,
        isMultiSelect = true,
    ),
    StructuredQuestionStepItem(
        id = "q-3",
        stepNumber = 3,
        shortTabTitle = "Retention",
        questionTitle = "How long should audit logs be retained?",
        options = listOf("90 days hot + 7 years cold", "1 year hot", "Indefinite immutable archive"),
        selectedOptions = setOf("90 days hot + 7 years cold"),
        isCompleted = false,
        isMultiSelect = false,
    ),
)
