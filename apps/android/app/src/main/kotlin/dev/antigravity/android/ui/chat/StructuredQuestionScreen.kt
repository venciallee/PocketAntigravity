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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Mic
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.Stop
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.antigravity.android.core.ui.theme.AntigravityDesignTokens
import dev.antigravity.android.core.ui.theme.LocalAntigravityColors
import dev.antigravity.android.core.ui.theme.LocalAppLanguage
import dev.antigravity.android.core.ui.theme.tr
import dev.antigravity.shared.domain.AntigravityCoreCoordinator
import dev.antigravity.shared.model.StructuredQuestionStepItem
import kotlinx.coroutines.launch

/**
 * UE10_STRUCTURED_QUESTION (`and-ask.png`): Native Material 3 multi-step `/plan interview`
 * screen matching `and-ask.png` with user `/plan` bubble, `Gemini 4 Neon` attribution,
 * answered summary pill, 3-segment question card, checkboxes, Back/Next CTAs, and bottom freeform bar.
 */
@Composable
fun StructuredQuestionScreen(
    coordinator: AntigravityCoreCoordinator,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalAntigravityColors.current
    val lang = LocalAppLanguage.current
    val chatState by coordinator.chatState.collectAsState()
    val scope = rememberCoroutineScope()

    val questions = chatState.structuredQuestions.ifEmpty { defaultStructuredQuestionsFallback() }
    val activeIdx = chatState.activeQuestionStepIndex.coerceIn(0, questions.lastIndex)
    val activeQuestion = questions[activeIdx]
    val isLastStep = activeIdx >= questions.lastIndex

    var freeformReply by remember { mutableStateOf("") }
    var submittedBanner by remember { mutableStateOf<String?>(null) }
    val voiceController = rememberVoiceDictationController()

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
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .size(AntigravityDesignTokens.MinTouchTarget)
                        .testTag("btn-question-back"),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = tr("Back", "返回"),
                        tint = colors.inkReading,
                    )
                }

                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(
                        text = "Audit log for admin actions",
                        style = MaterialTheme.typography.titleLarge.copy(fontSize = 19.sp, fontWeight = FontWeight.Normal),
                        color = colors.inkReading,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = tr("ledger-svc · /plan interview", "ledger-svc · /plan 需求访谈"),
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp),
                        color = colors.inkSecondary,
                        maxLines = 1,
                    )
                }

                IconButton(
                    onClick = {},
                    modifier = Modifier.size(AntigravityDesignTokens.MinTouchTarget),
                ) {
                    Icon(Icons.Rounded.MoreVert, contentDescription = tr("More", "更多"), tint = colors.inkReading)
                }
            }
        },
        bottomBar = {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .imePadding()
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                shape = RoundedCornerShape(100.dp),
                color = colors.surfaceCard,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    val freeformHint = tr("Or reply in your own words", "或直接用自己的话回复")
                    BasicTextField(
                        value = freeformReply,
                        onValueChange = { freeformReply = it },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("question-freeform-input"),
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.inkReading),
                        cursorBrush = SolidColor(colors.accentPeriwinkle),
                        decorationBox = { inner ->
                            if (freeformReply.isEmpty()) {
                                Text(
                                    text = freeformHint,
                                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 15.5.sp),
                                    color = colors.inkMuted,
                                )
                            }
                            inner()
                        },
                    )
                    Icon(
                        imageVector = if (voiceController.isRecording) Icons.Rounded.Stop else Icons.Rounded.Mic,
                        contentDescription = if (voiceController.isRecording) tr("Stop voice reply", "停止语音回复") else tr("Voice reply", "语音回复"),
                        tint = if (voiceController.isRecording) colors.statusError else colors.inkLabel,
                        modifier = Modifier
                            .size(21.dp)
                            .clickable {
                                if (freeformReply.isNotBlank() && !voiceController.isRecording && !voiceController.isStarting) {
                                    voiceController.stopRecording()
                                    submittedBanner = lang.t(
                                        "Sent reply: $freeformReply",
                                        "已发送回复：$freeformReply",
                                    )
                                    freeformReply = ""
                                } else {
                                    val contextHint = listOf(freeformReply, activeQuestion.questionTitle)
                                        .map { it.trim() }
                                        .filter { it.isNotEmpty() }
                                        .joinToString(" ")
                                        .ifBlank { null }
                                    voiceController.toggleRecording(
                                        existingDraft = freeformReply,
                                        appLanguage = lang,
                                        contextTextHint = contextHint,
                                    ) { updated ->
                                        freeformReply = updated
                                    }
                                }
                            },
                    )
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
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            // User `/plan` bubble (right-aligned tonal pill)
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Surface(
                    shape = RoundedCornerShape(22.dp),
                    color = colors.surfaceActiveTab,
                ) {
                    Text(
                        text = "/plan Add an audit log for admin actions",
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp),
                        color = colors.pillActiveForeground,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp),
                    )
                }
            }

            // Agent attribution & prompt
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "Gemini 4 Neon",
                    style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.sp),
                    color = colors.inkSecondary,
                )
                Text(
                    text = tr(
                        "Before I draft the plan I need three decisions. Tap to answer — you can also reply in your own words.",
                        "在起草计划前需要你确认三个问题。点选即可作答，也可以直接输入自定义回复。",
                    ),
                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp, lineHeight = 23.sp),
                    color = colors.inkReading,
                )
            }

            // Answered Step 1 pill (`✓ Storage: Postgres table`)
            if (activeIdx > 0) {
                val prevStep = questions.first()
                val answerText = prevStep.selectedOptions.firstOrNull() ?: "Postgres table"
                Surface(
                    onClick = { coordinator.chatStore.setActiveQuestionStepIndex(0) },
                    modifier = Modifier.testTag("question-answered-pill-0"),
                    shape = RoundedCornerShape(10.dp),
                    color = colors.canvasObsidian,
                    border = BorderStroke(1.dp, colors.cardBorder),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Check,
                            contentDescription = null,
                            tint = colors.statusDone,
                            modifier = Modifier.size(16.dp),
                        )
                        Text(
                            text = "${prevStep.shortTabTitle}: $answerText",
                            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp),
                            color = colors.inkReading,
                        )
                    }
                }
            }

            // Main Question Card (`and-ask.png`)
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("structured-question-card"),
                shape = RoundedCornerShape(22.dp),
                color = colors.surfaceCard,
                border = BorderStroke(1.dp, colors.cardBorder),
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    // Header: Question 2 of 3 | Select all that apply
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = tr(
                                "Question ${activeIdx + 1} of ${questions.size}",
                                "第 ${activeIdx + 1} / ${questions.size} 题",
                            ),
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                            color = colors.inkSecondary,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            text = if (activeQuestion.isMultiSelect) {
                                tr("Select all that apply", "可多选")
                            } else {
                                tr("Select one", "单选")
                            },
                            style = MaterialTheme.typography.labelLarge.copy(fontSize = 13.5.sp),
                            color = colors.inkSecondary,
                        )
                    }

                    // 3-segment progress bar
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        questions.indices.forEach { stepIdx ->
                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .height(4.dp)
                                    .clip(RoundedCornerShape(100.dp))
                                    .background(
                                        if (stepIdx <= activeIdx) colors.accentPeriwinkle else colors.ringTrack,
                                    ),
                            )
                        }
                    }

                    // Question Title
                    Text(
                        text = activeQuestion.questionTitle,
                        style = MaterialTheme.typography.titleLarge.copy(
                            fontSize = 20.sp,
                            lineHeight = 27.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = colors.inkReading,
                    )

                    // Options list (4 visible checkboxes matching `and-ask.png`)
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        activeQuestion.options.forEachIndexed { optIdx, option ->
                            val isSelected = option in activeQuestion.selectedOptions
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(10.dp))
                                    .clickable {
                                        coordinator.chatStore.toggleQuestionOption(option = option, stepIndex = activeIdx)
                                    }
                                    .padding(vertical = 4.dp)
                                    .testTag("question-option-$optIdx"),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                if (activeQuestion.isMultiSelect) {
                                    Checkbox(
                                        checked = isSelected,
                                        onCheckedChange = {
                                            coordinator.chatStore.toggleQuestionOption(option = option, stepIndex = activeIdx)
                                        },
                                        colors = CheckboxDefaults.colors(
                                            checkedColor = colors.accentPeriwinkle,
                                            checkmarkColor = colors.inkOnPrimaryCta,
                                            uncheckedColor = colors.inkSecondary,
                                        ),
                                    )
                                } else {
                                    RadioButton(
                                        selected = isSelected,
                                        onClick = {
                                            coordinator.chatStore.toggleQuestionOption(option = option, stepIndex = activeIdx)
                                        },
                                        colors = RadioButtonDefaults.colors(
                                            selectedColor = colors.accentPeriwinkle,
                                            unselectedColor = colors.inkSecondary,
                                        ),
                                    )
                                }
                                Text(
                                    text = option,
                                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 16.sp),
                                    color = colors.inkReading,
                                )
                            }
                        }
                    }

                    // Bottom Card Footer: Back (left text button) | Next · 3 selected (right primary pill)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TextButton(
                            onClick = {
                                if (activeIdx > 0) {
                                    coordinator.chatStore.setActiveQuestionStepIndex(activeIdx - 1)
                                } else {
                                    onBack()
                                }
                            },
                            modifier = Modifier.testTag("btn-question-prev"),
                        ) {
                            Text(
                                text = tr("Back", "上一步"),
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Medium,
                                ),
                                color = colors.accentPeriwinkle,
                            )
                        }

                        Spacer(modifier = Modifier.weight(1f))

                        val count = activeQuestion.selectedOptions.size
                        Button(
                            onClick = {
                                if (!isLastStep) {
                                    coordinator.chatStore.setActiveQuestionStepIndex(activeIdx + 1)
                                } else {
                                    scope.launch {
                                        submittedBanner = lang.t(
                                            "Decisions submitted to Gemini 4 Neon",
                                            "已将选择提交给 Gemini 4 Neon",
                                        )
                                    }
                                    onBack()
                                }
                            },
                            modifier = Modifier
                                .defaultMinSize(minHeight = 46.dp)
                                .testTag("btn-question-next"),
                            shape = RoundedCornerShape(100.dp),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = colors.accentPeriwinkle,
                                contentColor = colors.inkOnPrimaryCta,
                            ),
                            contentPadding = PaddingValues(horizontal = 22.dp, vertical = 12.dp),
                        ) {
                            Text(
                                text = if (isLastStep) {
                                    tr("Submit", "提交")
                                } else if (activeQuestion.isMultiSelect && count > 0) {
                                    tr("Next · $count selected", "下一步 · 已选 $count 项")
                                } else {
                                    tr("Next", "下一步")
                                },
                                style = MaterialTheme.typography.labelLarge.copy(
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.SemiBold,
                                ),
                            )
                        }
                    }
                }
            }

            if (submittedBanner != null) {
                Text(
                    text = submittedBanner.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.statusDone,
                    modifier = Modifier.testTag("question-submitted-banner"),
                )
            }
        }
    }
}

private fun defaultStructuredQuestionsFallback(): List<StructuredQuestionStepItem> = listOf(
    StructuredQuestionStepItem(
        id = "q-storage",
        stepNumber = 1,
        shortTabTitle = "Storage",
        questionTitle = "Where should audit events be persisted?",
        options = listOf("Postgres table", "Append-only S3 bucket", "Kafka topic"),
        isMultiSelect = false,
        selectedOptions = setOf("Postgres table"),
    ),
    StructuredQuestionStepItem(
        id = "q-actions",
        stepNumber = 2,
        shortTabTitle = "Actions",
        questionTitle = "Which admin actions should be audited?",
        options = listOf(
            "Account freeze / unfreeze",
            "Limit changes",
            "Manual ledger adjustments",
            "Role & permission changes",
        ),
        isMultiSelect = true,
        selectedOptions = setOf(
            "Account freeze / unfreeze",
            "Limit changes",
            "Manual ledger adjustments",
        ),
    ),
    StructuredQuestionStepItem(
        id = "q-retention",
        stepNumber = 3,
        shortTabTitle = "Retention",
        questionTitle = "How long should audit logs be retained?",
        options = listOf("90 days", "1 year", "7 years (compliance)"),
        isMultiSelect = false,
        selectedOptions = setOf("7 years (compliance)"),
    ),
)
