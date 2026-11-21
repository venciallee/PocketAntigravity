package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.AskQuestionInteractionSpec
import dev.antigravity.shared.model.BrowserUploadInteractionSpec
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CodeActionPayload
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CortexStepType
import dev.antigravity.shared.model.DownloadUrlInteractionSpec
import dev.antigravity.shared.model.DynamicWorkflowPayload
import dev.antigravity.shared.model.ExecuteUrlInteractionSpec
import dev.antigravity.shared.model.FilePermissionInteractionSpec
import dev.antigravity.shared.model.McpToolCallPayload
import dev.antigravity.shared.model.PermissionInteractionSpec
import dev.antigravity.shared.model.PersistSuggestionType
import dev.antigravity.shared.model.PlannerResponsePayload
import dev.antigravity.shared.model.RequestedInteraction
import dev.antigravity.shared.model.ResolvedEmbedResource
import dev.antigravity.shared.model.RunCommandInteractionSpec
import dev.antigravity.shared.model.RunCommandPayload
import dev.antigravity.shared.model.SearchPayload
import dev.antigravity.shared.model.SubagentPayload
import dev.antigravity.shared.model.SwarmBoardPayload
import dev.antigravity.shared.model.SwarmMemberItem
import dev.antigravity.shared.model.TaskBoundaryPayload
import dev.antigravity.shared.model.ViewFilePayload
import dev.antigravity.shared.model.WorkflowPhaseItem
import dev.antigravity.shared.model.WorkflowScriptInteractionSpec
import kotlin.math.max

/**
 * Encodes and decodes binary Protobuf payloads for `GetCascadeTrajectorySteps`.
 *
 * Why binary Protobuf is the default transport on local hosts:
 * Sending `Content-Type: application/proto` reduces payload size by ~65% over mobile connections
 * and dynamically bypasses any server-side JSON truncation ceiling without hardcoded step thresholds,
 * while targeted JSON `stepOffset` repair recovers rich metadata for unrecognized future wire
 * step types and waiting interactions.
 */
public object ProtobufStepCodec {

    private class Cursor(var offset: Int = 0)

    /**
     * Encodes a `GetCascadeTrajectoryStepsRequest` (`cascade_id=1`, `step_offset=2`).
     */
    public fun encodeGetStepsRequest(cascadeId: String, startIndex: Int, endIndex: Int = 0): ByteArray {
        @Suppress("UNUSED_VARIABLE")
        val unused = endIndex
        val idBytes = cascadeId.encodeToByteArray()
        val idLenVarint = encodeVarint(idBytes.size.toULong())
        val offsetVarint = encodeVarint(max(0, startIndex).toULong())

        val out = ByteArray(1 + idLenVarint.size + idBytes.size + 1 + offsetVarint.size)
        var pos = 0
        out[pos++] = 0x0A // field 1 (cascade_id), wire type 2
        idLenVarint.copyInto(out, pos); pos += idLenVarint.size
        idBytes.copyInto(out, pos); pos += idBytes.size
        out[pos++] = 0x10 // field 2 (step_offset), wire type 0
        offsetVarint.copyInto(out, pos)
        return out
    }

    public fun encodeVarint(value: ULong): ByteArray {
        if (value == 0UL) return byteArrayOf(0)
        var v = value
        val bytes = ArrayList<Byte>(10)
        while (v > 0x7FUL) {
            bytes.add(((v and 0x7FUL) or 0x80UL).toByte())
            v = v shr 7
        }
        bytes.add((v and 0x7FUL).toByte())
        return bytes.toByteArray()
    }

    public fun readVarint(data: ByteArray, offsetRef: IntArray): ULong? {
        var result = 0UL
        var shift = 0
        var offset = offsetRef[0]
        while (offset < data.size) {
            val byte = data[offset].toInt() and 0xFF
            offset += 1
            result = result or ((byte and 0x7F).toULong() shl shift)
            if ((byte and 0x80) == 0) {
                offsetRef[0] = offset
                return result
            }
            shift += 7
            if (shift >= 64) {
                offsetRef[0] = offset
                return null
            }
        }
        offsetRef[0] = offset
        return null
    }

    private fun readVarint(data: ByteArray, cursor: Cursor): ULong? {
        var result = 0UL
        var shift = 0
        while (cursor.offset < data.size) {
            val byte = data[cursor.offset].toInt() and 0xFF
            cursor.offset += 1
            result = result or ((byte and 0x7F).toULong() shl shift)
            if ((byte and 0x80) == 0) {
                return result
            }
            shift += 7
            if (shift >= 64) return null
        }
        return null
    }

    public fun decodeStepStatus(raw: Int): CortexStepStatus = when (raw) {
        0, 5 -> CortexStepStatus.UNSPECIFIED
        1, 11 -> CortexStepStatus.PENDING
        2, 8 -> CortexStepStatus.IN_PROGRESS
        3 -> CortexStepStatus.DONE
        4, 7 -> CortexStepStatus.ERROR
        6, 12 -> CortexStepStatus.CANCELLED
        9 -> CortexStepStatus.WAITING
        else -> CortexStepStatus.fromRaw(raw)
    }

    public fun decodeStepType(raw: Int): CortexStepType = when (raw) {
        5, 24, 86 -> CortexStepType.CODE_ACTION
        7, 25, 33, 73, 84 -> CortexStepType.SEARCH
        8, 13, 47 -> CortexStepType.VIEW_FILE
        9 -> CortexStepType.LIST_DIRECTORY
        14 -> CortexStepType.USER_INPUT
        15 -> CortexStepType.PLANNER_RESPONSE
        21, 112 -> CortexStepType.RUN_COMMAND
        23, 1, 2, 3, 27, 29, 34, 55, 98 -> CortexStepType.CHECKPOINT
        28 -> CortexStepType.COMMAND_STATUS
        31 -> CortexStepType.READ_URL_CONTENT
        32 -> CortexStepType.VIEW_CONTENT_CHUNK
        81 -> CortexStepType.TASK_BOUNDARY
        82 -> CortexStepType.NOTIFY_USER
        83 -> CortexStepType.CODE_ACKNOWLEDGEMENT
        85 -> CortexStepType.BROWSER_SUBAGENT
        90 -> CortexStepType.EPHEMERAL_MESSAGE
        91 -> CortexStepType.GENERATE_IMAGE
        99 -> CortexStepType.KNOWLEDGE_ARTIFACTS
        100 -> CortexStepType.SEND_COMMAND_INPUT
        122 -> CortexStepType.WORKSPACE_API
        130 -> CortexStepType.SUBAGENT_INVOCATION
        131 -> CortexStepType.DYNAMIC_WORKFLOW
        132 -> CortexStepType.SWARM_BOARD
        133 -> CortexStepType.MCP_TOOL_CALL
        134 -> CortexStepType.BACKGROUND_TASK
        135 -> CortexStepType.SIDE_QUESTION
        else -> CortexStepType.fromRaw(raw)
    }

    public fun modelEnumName(protoInt: Int): String? {
        if (protoInt <= 0) return null
        if (protoInt in 1000..1200) return "MODEL_PLACEHOLDER_M${protoInt - 1000}"
        return when (protoInt) {
            246 -> "MODEL_GOOGLE_GEMINI_2_5_PRO"
            281 -> "MODEL_CLAUDE_4_SONNET"
            282 -> "MODEL_CLAUDE_4_SONNET_THINKING"
            290 -> "MODEL_CLAUDE_4_OPUS"
            291 -> "MODEL_CLAUDE_4_OPUS_THINKING"
            312 -> "MODEL_GOOGLE_GEMINI_2_5_FLASH"
            313 -> "MODEL_GOOGLE_GEMINI_2_5_FLASH_THINKING"
            330 -> "MODEL_GOOGLE_GEMINI_2_5_FLASH_LITE"
            333 -> "MODEL_CLAUDE_4_5_SONNET"
            334 -> "MODEL_CLAUDE_4_5_SONNET_THINKING"
            340 -> "MODEL_CLAUDE_4_5_HAIKU"
            341 -> "MODEL_CLAUDE_4_5_HAIKU_THINKING"
            342 -> "MODEL_OPENAI_GPT_OSS_120B_MEDIUM"
            401 -> "MODEL_GOOGLE_GEMINI_4_NEON"
            402 -> "MODEL_GOOGLE_GEMINI_4_CARBON"
            403 -> "MODEL_GOOGLE_GEMINI_4_ARGON"
            404 -> "MODEL_GOOGLE_GEMINI_4_HYDROGEN"
            411 -> "MODEL_ORCHESTRATOR_NEON"
            412 -> "MODEL_ORCHESTRATOR_CARBON"
            413 -> "MODEL_ORCHESTRATOR_ARGON"
            else -> null
        }
    }

    /**
     * Decodes a binary `GetCascadeTrajectoryStepsResponse` (`repeated Step steps = 1`).
     */
    public fun decodeStepsResponse(
        data: ByteArray,
        cascadeId: String,
        startingIndex: Int = 0,
    ): List<CascadeStep> {
        val cursor = Cursor()
        val steps = mutableListOf<CascadeStep>()
        var index = startingIndex

        while (cursor.offset < data.size) {
            val tag = readVarint(data, cursor) ?: break
            val fieldNumber = (tag shr 3).toInt()
            val wireType = (tag and 0x07UL).toInt()

            if (fieldNumber == 1 && wireType == 2) {
                val sub = readLengthDelimited(data, cursor) ?: break
                decodeSingleStep(sub, cascadeId, index)?.let {
                    steps.add(it)
                    index += 1
                }
            } else {
                skipField(wireType, data, cursor)
            }
        }
        return steps
    }

    private fun decodeSingleStep(
        data: ByteArray,
        cascadeId: String,
        defaultIndex: Int,
    ): CascadeStep? {
        val cursor = Cursor()
        var rawType = 0
        var rawTypeName: String? = null
        var fallbackSummary: String? = null
        var stepType = CortexStepType.UNSPECIFIED
        var stepStatus = CortexStepStatus.UNSPECIFIED
        var createdAtEpochMs = 0L

        var userInputText: String? = null
        var attachedMentions: List<String> = emptyList()
        var recordedMode: CascadeExecutionMode? = null
        var recordedModelId: String? = null

        var plannerPayload: PlannerResponsePayload? = null
        var taskBoundaryPayload: TaskBoundaryPayload? = null
        var runCommandPayload: RunCommandPayload? = null
        var codeActionPayload: CodeActionPayload? = null
        var viewFilePayload: ViewFilePayload? = null
        var searchPayload: SearchPayload? = null
        var requestedInteraction: RequestedInteraction? = null
        var subagentPayload: SubagentPayload? = null
        var dynamicWorkflowPayload: DynamicWorkflowPayload? = null
        var swarmBoardPayload: SwarmBoardPayload? = null
        var mcpToolCallPayload: McpToolCallPayload? = null

        while (cursor.offset < data.size) {
            val tag = readVarint(data, cursor) ?: break
            val fieldNumber = (tag shr 3).toInt()
            val wireType = (tag and 0x07UL).toInt()

            when {
                fieldNumber == 1 && wireType == 0 -> {
                    readVarint(data, cursor)?.let { raw ->
                        rawType = raw.toInt()
                        stepType = decodeStepType(rawType)
                        if (rawType != 0 && stepType == CortexStepType.UNSPECIFIED) {
                            rawTypeName = "STEP_TYPE_$rawType"
                        }
                    }
                }
                fieldNumber == 4 && wireType == 0 -> {
                    readVarint(data, cursor)?.let { raw ->
                        stepStatus = decodeStepStatus(raw.toInt())
                    }
                }
                fieldNumber == 5 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        extractTimestampEpochMs(nested, targetField = 1)?.let { createdAtEpochMs = it }
                    }
                }
                (fieldNumber == 10 || fieldNumber == 23 || fieldNumber == 98) && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        val uri = nonEmpty(extractStringField(nested, 1))
                            ?: nonEmpty(extractNestedStringField(nested, 1, 1))
                            ?: "workspace/file"
                        val desc = nonEmpty(extractStringField(nested, 4))
                            ?: nonEmpty(extractStringField(nested, 2))
                            ?: "Modified file"
                        val lowerUri = uri.lowercase()
                        val isArtifact = lowerUri.contains("/.gemini/") || lowerUri.contains("/brain/")
                        var capturedContent: String? = null
                        if (ResolvedEmbedResource.isEmbeddableTextArtifactPath(uri) || isArtifact) {
                            val candidates = listOf(
                                extractStringField(nested, 2),
                                extractStringField(nested, 3),
                                extractNestedStringField(nested, 1, 2),
                                extractNestedStringField(nested, 1, 3),
                                extractNestedStringField(nested, 2, 2),
                            )
                            for (cand in candidates) {
                                if (cand != null && cand.encodeToByteArray().size <= 524_288 && looksLikeArtifactDocument(cand, uri)) {
                                    capturedContent = cand
                                    break
                                }
                            }
                        }
                        codeActionPayload = CodeActionPayload(
                            targetFileUri = uri,
                            description = desc,
                            additions = 0,
                            deletions = 0,
                            isArtifactFile = isArtifact,
                            fileContent = capturedContent,
                        )
                        if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.CODE_ACTION
                    }
                }
                (fieldNumber == 13 || fieldNumber == 34 || fieldNumber == 42 || fieldNumber == 85) && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        val q = nonEmpty(extractStringField(nested, 3))
                            ?: nonEmpty(extractStringField(nested, 1))
                            ?: nonEmpty(extractStringField(nested, 2))
                            ?: "search"
                        val scope = nonEmpty(extractStringField(nested, 1)) ?: "workspace"
                        searchPayload = SearchPayload(query = q, scopeDirectory = scope, matchCount = 0)
                        if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.SEARCH
                    }
                }
                (fieldNumber == 14 || fieldNumber == 22 || fieldNumber == 58) && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        nonEmpty(extractStringField(nested, 1))?.let { uri ->
                            viewFilePayload = ViewFilePayload(fileUri = uri)
                            if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.VIEW_FILE
                        }
                    }
                }
                fieldNumber == 15 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        nonEmpty(extractStringField(nested, 1))?.let { uri ->
                            viewFilePayload = ViewFilePayload(fileUri = uri)
                            if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.LIST_DIRECTORY
                        }
                    }
                }
                fieldNumber == 19 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        val parsed = decodeUserInput(nested)
                        userInputText = parsed.text
                        attachedMentions = parsed.mentions
                        recordedMode = parsed.mode
                        recordedModelId = parsed.modelId
                        if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.USER_INPUT
                    }
                }
                fieldNumber == 20 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        plannerPayload = decodePlannerResponse(nested)
                        if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.PLANNER_RESPONSE
                    }
                }
                fieldNumber == 24 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        val errMsg = nonEmpty(extractStringField(nested, 1))
                            ?: nonEmpty(extractNestedStringField(nested, 1, 1))
                        if (errMsg != null) {
                            plannerPayload = PlannerResponsePayload(response = "⚠️ $errMsg")
                            stepType = CortexStepType.PLANNER_RESPONSE
                            stepStatus = CortexStepStatus.ERROR
                        }
                    }
                }
                fieldNumber == 28 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        runCommandPayload = decodeRunCommand(nested, defaultIndex)
                        if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.RUN_COMMAND
                    }
                }
                fieldNumber == 56 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        requestedInteraction = decodeRequestedInteraction(nested, stepType)
                        if (requestedInteraction?.kind == RequestedInteraction.MemberKind.RUN_COMMAND &&
                            runCommandPayload == null
                        ) {
                            val spec = requestedInteraction?.runCommand
                            if (spec != null) {
                                runCommandPayload = RunCommandPayload(
                                    commandId = "cmd-$defaultIndex",
                                    commandLine = spec.proposedCommandLine,
                                    proposedCommandLine = spec.proposedCommandLine,
                                    cwd = spec.cwd,
                                )
                            }
                        }
                    }
                }
                fieldNumber == 93 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        val tName = nonEmpty(extractStringField(nested, 1)) ?: "Task Progress"
                        val tStatus = nonEmpty(extractStringField(nested, 2)) ?: ""
                        val tSummary = nonEmpty(extractStringField(nested, 3)) ?: tStatus
                        taskBoundaryPayload = TaskBoundaryPayload(
                            taskName = tName,
                            taskStatus = tStatus,
                            taskSummary = tSummary,
                            completedCount = 0,
                            totalCount = 0,
                            elapsedLabel = "",
                        )
                        stepType = CortexStepType.TASK_BOUNDARY
                    }
                }
                fieldNumber == 94 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        val reviewUris = extractRepeatedStringField(nested, 1)
                        val content = nonEmpty(extractStringField(nested, 2)) ?: ""
                        if (content.isNotEmpty() || reviewUris.isNotEmpty()) {
                            plannerPayload = PlannerResponsePayload(
                                response = content.ifEmpty { "Ready for review." },
                                referencedFiles = reviewUris,
                            )
                            stepType = CortexStepType.NOTIFY_USER
                        }
                    }
                }
                fieldNumber == 130 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        subagentPayload = SubagentPayload(
                            subagentId = nonEmpty(extractStringField(nested, 1)) ?: "sub-$defaultIndex",
                            role = nonEmpty(extractStringField(nested, 2)) ?: "Subagent",
                            typeName = nonEmpty(extractStringField(nested, 3)) ?: "self",
                            modelLabel = nonEmpty(extractStringField(nested, 5)) ?: "Gemini 4 Hydrogen",
                            status = when (stepStatus) {
                                CortexStepStatus.DONE -> CortexStepStatus.DONE
                                CortexStepStatus.ERROR -> CortexStepStatus.ERROR
                                else -> CortexStepStatus.IN_PROGRESS
                            },
                            summary = nonEmpty(extractStringField(nested, 4)) ?: "",
                            waitingApprovalTitle = nonEmpty(extractStringField(nested, 6)),
                        )
                        stepType = CortexStepType.SUBAGENT_INVOCATION
                    }
                }
                fieldNumber == 131 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        val phaseNames = extractRepeatedStringField(nested, 4)
                        dynamicWorkflowPayload = DynamicWorkflowPayload(
                            workflowId = nonEmpty(extractStringField(nested, 1)) ?: "wf-$defaultIndex",
                            description = nonEmpty(extractStringField(nested, 2)) ?: "Dynamic Workflow",
                            pythonScript = nonEmpty(extractStringField(nested, 3)) ?: "",
                            currentPhase = phaseNames.firstOrNull() ?: "Phase 1",
                            completedAgents = 0,
                            totalAgents = max(1, phaseNames.size),
                            phases = phaseNames.mapIndexed { idx, name -> WorkflowPhaseItem("phase-$idx", name) },
                        )
                        stepType = CortexStepType.DYNAMIC_WORKFLOW
                    }
                }
                fieldNumber == 132 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        val memberNames = extractRepeatedStringField(nested, 3)
                        swarmBoardPayload = SwarmBoardPayload(
                            swarmId = nonEmpty(extractStringField(nested, 1)) ?: "swarm-$defaultIndex",
                            title = nonEmpty(extractStringField(nested, 2)) ?: "Swarm Team",
                            members = memberNames.map { SwarmMemberItem(name = it, role = "Specialist") },
                        )
                        stepType = CortexStepType.SWARM_BOARD
                    }
                }
                fieldNumber == 133 && wireType == 2 -> {
                    readLengthDelimited(data, cursor)?.let { nested ->
                        mcpToolCallPayload = McpToolCallPayload(
                            serverName = nonEmpty(extractStringField(nested, 1)) ?: "mcp",
                            toolName = nonEmpty(extractStringField(nested, 2)) ?: "call",
                            pluginName = nonEmpty(extractStringField(nested, 5)),
                            argumentsPreview = nonEmpty(extractStringField(nested, 3)) ?: "{}",
                            resultPreview = nonEmpty(extractStringField(nested, 4)),
                            isError = stepStatus == CortexStepStatus.ERROR,
                        )
                        stepType = CortexStepType.MCP_TOOL_CALL
                    }
                }
                else -> {
                    if (wireType == 2 && fieldNumber >= 10 && fallbackSummary == null) {
                        val nested = readLengthDelimited(data, cursor) ?: break
                        val extracted = nonEmpty(extractStringField(nested, 1))
                            ?: nonEmpty(extractStringField(nested, 2))
                        if (extracted != null) {
                            fallbackSummary = extracted.take(240)
                        }
                    } else {
                        skipField(wireType, data, cursor)
                    }
                }
            }
        }

        if (rawType == 17 && plannerPayload == null) {
            stepType = CortexStepType.GENERATE_IMAGE
        }
        if ((stepType == CortexStepType.PLANNER_RESPONSE || stepType == CortexStepType.NOTIFY_USER) &&
            plannerPayload == null &&
            (stepStatus == CortexStepStatus.IN_PROGRESS || stepStatus == CortexStepStatus.PENDING)
        ) {
            plannerPayload = PlannerResponsePayload(response = "")
        }

        val finalRawTypeName = if (stepType == CortexStepType.UNSPECIFIED) rawTypeName else null
        val finalFallbackSummary = if (stepType == CortexStepType.UNSPECIFIED && plannerPayload == null) {
            fallbackSummary
        } else {
            null
        }

        return CascadeStep(
            cascadeId = cascadeId,
            stepIndex = defaultIndex,
            type = stepType,
            status = stepStatus,
            createdAtEpochMs = createdAtEpochMs,
            userInput = userInputText,
            attachedMentions = attachedMentions,
            plannerResponse = plannerPayload,
            taskBoundary = taskBoundaryPayload,
            runCommand = runCommandPayload,
            codeAction = codeActionPayload,
            viewFile = viewFilePayload,
            search = searchPayload,
            requestedInteraction = requestedInteraction,
            recordedExecutionMode = recordedMode,
            recordedModelId = recordedModelId,
            subagent = subagentPayload,
            dynamicWorkflow = dynamicWorkflowPayload,
            swarmBoard = swarmBoardPayload,
            mcpToolCall = mcpToolCallPayload,
            rawTypeName = finalRawTypeName,
            fallbackSummary = finalFallbackSummary,
        )
    }

    private data class ParsedUserInput(
        val text: String?,
        val mentions: List<String>,
        val mode: CascadeExecutionMode?,
        val modelId: String?,
    )

    private fun decodeUserInput(data: ByteArray): ParsedUserInput {
        val cursor = Cursor()
        var queryText: String? = null
        var userResponseText: String? = null
        val itemTexts = mutableListOf<String>()
        val mentions = mutableListOf<String>()
        var recordedMode: CascadeExecutionMode? = null
        var recordedModelId: String? = null

        while (cursor.offset < data.size) {
            val tag = readVarint(data, cursor) ?: break
            val fieldNumber = (tag shr 3).toInt()
            val wireType = (tag and 0x07UL).toInt()
            when {
                fieldNumber == 1 && wireType == 2 ->
                    readLengthDelimited(data, cursor)?.let { nonEmpty(it.decodeToString())?.let { s -> queryText = s } }
                fieldNumber == 2 && wireType == 2 ->
                    readLengthDelimited(data, cursor)?.let { nonEmpty(it.decodeToString())?.let { s -> userResponseText = s } }
                fieldNumber == 3 && wireType == 2 ->
                    readLengthDelimited(data, cursor)?.let { itemData ->
                        nonEmpty(extractStringField(itemData, 1))?.let { itemTexts.add(it) }
                        val scopeData = extractMessageField(itemData, 2)
                        val fileData = scopeData?.let { extractMessageField(it, 1) }
                        val fileUri = fileData?.let { nonEmpty(extractStringField(it, 1)) }
                        if (fileUri != null) {
                            val name = ResolvedEmbedResource.normalizePath(fileUri).trimEnd('/').substringAfterLast('/')
                            if (name.isNotEmpty()) mentions.add("@$name")
                        }
                    }
                (fieldNumber == 12 || fieldNumber == 13) && wireType == 2 ->
                    readLengthDelimited(data, cursor)?.let { cfgData ->
                        val (m, mid) = decodeCascadeConfig(cfgData)
                        if (m != null) recordedMode = m
                        if (mid != null) recordedModelId = mid
                    }
                else -> skipField(wireType, data, cursor)
            }
        }
        val joinedItems = nonEmpty(itemTexts.joinToString("\n"))
        return ParsedUserInput(userResponseText ?: joinedItems ?: queryText, mentions, recordedMode, recordedModelId)
    }

    private fun decodeCascadeConfig(data: ByteArray): Pair<CascadeExecutionMode?, String?> {
        val plannerData = extractMessageField(data, 1) ?: return null to null
        var mode: CascadeExecutionMode? = null
        var modelId: String? = null

        extractMessageField(plannerData, 2)?.let { convData ->
            val agenticVal = extractVarintField(convData, 14)
            mode = if (agenticVal != null && agenticVal != 0UL) CascadeExecutionMode.PLANNING else CascadeExecutionMode.FAST
        }
        extractMessageField(plannerData, 15)?.let { reqModelData ->
            val modelInt = extractVarintField(reqModelData, 1)?.toInt()
            modelId = modelInt?.let { modelEnumName(it) } ?: nonEmpty(extractStringField(reqModelData, 2))
        }
        if (modelId == null) {
            extractVarintField(plannerData, 1)?.toInt()?.let { modelId = modelEnumName(it) }
        }
        return mode to modelId
    }

    private fun decodePlannerResponse(data: ByteArray): PlannerResponsePayload? {
        val cursor = Cursor()
        var responseText: String? = null
        var modifiedResponseText: String? = null
        var thinkingText: String? = null
        var durationSeconds: Double? = null

        while (cursor.offset < data.size) {
            val tag = readVarint(data, cursor) ?: break
            val fieldNumber = (tag shr 3).toInt()
            val wireType = (tag and 0x07UL).toInt()
            when {
                fieldNumber == 1 && wireType == 2 ->
                    readLengthDelimited(data, cursor)?.let { nonEmpty(it.decodeToString())?.let { s -> responseText = s } }
                fieldNumber == 3 && wireType == 2 ->
                    readLengthDelimited(data, cursor)?.let { nonEmpty(it.decodeToString())?.let { s -> thinkingText = s } }
                fieldNumber == 8 && wireType == 2 ->
                    readLengthDelimited(data, cursor)?.let { nonEmpty(it.decodeToString())?.let { s -> modifiedResponseText = s } }
                fieldNumber == 11 && wireType == 2 ->
                    readLengthDelimited(data, cursor)?.let { durData ->
                        val secs = (extractVarintField(durData, 1) ?: 0UL).toDouble()
                        val nanos = (extractVarintField(durData, 2) ?: 0UL).toDouble() / 1_000_000_000.0
                        val total = secs + nanos
                        if (total > 0.0) durationSeconds = total
                    }
                else -> skipField(wireType, data, cursor)
            }
        }
        val finalResponse = modifiedResponseText ?: responseText ?: ""
        if (finalResponse.isEmpty() && thinkingText == null) return null
        return PlannerResponsePayload(response = finalResponse, thinking = thinkingText, thinkingDurationSeconds = durationSeconds)
    }

    private fun decodeRunCommand(data: ByteArray, fallbackStepIndex: Int): RunCommandPayload {
        val cmdLine = nonEmpty(extractStringField(data, 23))
            ?: nonEmpty(extractStringField(data, 25))
            ?: nonEmpty(extractStringField(data, 1))
            ?: ""
        val proposed = nonEmpty(extractStringField(data, 25)) ?: cmdLine
        val cwd = nonEmpty(extractStringField(data, 2)) ?: ""
        val cmdId = nonEmpty(extractStringField(data, 13)) ?: "cmd-$fallbackStepIndex"
        val exitCode = extractVarintField(data, 6)?.toInt()
        val stdout = nonEmpty(extractStringField(data, 4))
            ?: nonEmpty(extractStringField(data, 7))
            ?: nonEmpty(extractNestedStringField(data, 21, 1))
            ?: ""
        val stderr = nonEmpty(extractStringField(data, 5))
            ?: nonEmpty(extractStringField(data, 8))
            ?: ""
        val combined = listOf(stdout, stderr).filter { it.isNotEmpty() }.joinToString("\n")
        return RunCommandPayload(
            commandId = cmdId,
            commandLine = cmdLine,
            proposedCommandLine = proposed,
            cwd = cwd,
            exitCode = exitCode,
            outputPreview = combined.take(2000),
        )
    }

    private fun decodeRequestedInteraction(
        data: ByteArray,
        hintStepType: CortexStepType,
    ): RequestedInteraction? {
        val cursor = Cursor()
        while (cursor.offset < data.size) {
            val tag = readVarint(data, cursor) ?: break
            val fieldNumber = (tag shr 3).toInt()
            val wireType = (tag and 0x07UL).toInt()
            if (wireType != 2) {
                skipField(wireType, data, cursor)
                continue
            }
            val nested = readLengthDelimited(data, cursor) ?: break
            return when (fieldNumber) {
                2 -> RequestedInteraction(kind = RequestedInteraction.MemberKind.DEPLOY)
                3 -> {
                    val cmd = nonEmpty(extractStringField(nested, 2)) ?: nonEmpty(extractStringField(nested, 1)) ?: ""
                    val cwd = nonEmpty(extractStringField(nested, 1)) ?: "/workspace"
                    RequestedInteraction(
                        kind = RequestedInteraction.MemberKind.RUN_COMMAND,
                        runCommand = RunCommandInteractionSpec(proposedCommandLine = cmd.ifEmpty { cwd }, cwd = cwd),
                    )
                }
                4, 10 -> {
                    val url = nonEmpty(extractStringField(nested, 1)) ?: ""
                    val domain = nonEmpty(extractStringField(nested, 2)) ?: url.substringAfter("://", url).substringBefore('/')
                    val isRedirect = (extractVarintField(nested, 3) ?: 0UL) != 0UL
                    RequestedInteraction(
                        kind = RequestedInteraction.MemberKind.EXECUTE_URL,
                        executeUrl = ExecuteUrlInteractionSpec(url = url, domain = domain, isRedirect = isRedirect),
                    )
                }
                18 -> RequestedInteraction(
                    kind = RequestedInteraction.MemberKind.MCP,
                    mcpServerName = nonEmpty(extractStringField(nested, 1)) ?: "mcp-server",
                    mcpToolName = nonEmpty(extractStringField(nested, 2)) ?: "invoke_tool",
                    pluginName = nonEmpty(extractStringField(nested, 3)),
                )
                19 -> RequestedInteraction(
                    kind = RequestedInteraction.MemberKind.FILE_PERMISSION,
                    filePermission = FilePermissionInteractionSpec(
                        absolutePathUri = extractStringField(nested, 1) ?: "",
                        isDirectory = (extractVarintField(nested, 2) ?: 0UL) != 0UL,
                        blockReason = nonEmpty(extractStringField(nested, 3)),
                    ),
                )
                21 -> {
                    val action = nonEmpty(extractStringField(nested, 1)) ?: "read"
                    val pattern = nonEmpty(extractStringField(nested, 2))
                    val reason = nonEmpty(extractStringField(nested, 3))
                    val plugin = nonEmpty(extractStringField(nested, 4))
                    val persistRaw = (extractVarintField(nested, 5) ?: 1UL).toInt()
                    RequestedInteraction(
                        kind = RequestedInteraction.MemberKind.PERMISSION,
                        permission = PermissionInteractionSpec(
                            action = action,
                            target = pattern ?: "*",
                            suggestedPersistPattern = pattern,
                            persistSuggestionType = PersistSuggestionType.fromRaw(persistRaw),
                            reason = reason,
                            pluginName = plugin,
                        ),
                        pluginName = plugin,
                    )
                }
                22, 24 -> RequestedInteraction(
                    kind = RequestedInteraction.MemberKind.ASK_QUESTION,
                    askQuestion = AskQuestionInteractionSpec(
                        question = extractStringField(nested, 1) ?: "Clarification needed",
                        options = extractRepeatedStringField(nested, 2),
                        isMultiSelect = (extractVarintField(nested, 3) ?: 0UL) != 0UL,
                    ),
                )
                23 -> {
                    val cmd = if (hintStepType == CortexStepType.RUN_COMMAND) nonEmpty(extractStringField(nested, 1)) else null
                    if (cmd != null) {
                        RequestedInteraction(
                            kind = RequestedInteraction.MemberKind.RUN_COMMAND,
                            runCommand = RunCommandInteractionSpec(proposedCommandLine = cmd, cwd = "/workspace"),
                        )
                    } else {
                        RequestedInteraction(kind = RequestedInteraction.MemberKind.APPROVAL_INTERACTION)
                    }
                }
                25 -> {
                    val url = nonEmpty(extractStringField(nested, 1)) ?: ""
                    val host = url.substringAfter("://", "unknown").substringBefore('/')
                    val lastSeg = url.substringAfterLast('/').ifEmpty { "download.bin" }
                    RequestedInteraction(
                        kind = RequestedInteraction.MemberKind.DOWNLOAD_URL,
                        downloadUrl = DownloadUrlInteractionSpec(
                            url = url,
                            origin = nonEmpty(extractStringField(nested, 2)) ?: host,
                            fileName = nonEmpty(extractStringField(nested, 3)) ?: lastSeg,
                            mimeType = nonEmpty(extractStringField(nested, 4)) ?: "application/octet-stream",
                            destinationFolder = nonEmpty(extractStringField(nested, 5)) ?: "~/Downloads",
                        ),
                    )
                }
                26 -> RequestedInteraction(
                    kind = RequestedInteraction.MemberKind.BROWSER_UPLOAD,
                    browserUpload = BrowserUploadInteractionSpec(
                        origin = nonEmpty(extractStringField(nested, 1)) ?: "https://app.example.com",
                        fileNames = extractRepeatedStringField(nested, 2),
                    ),
                )
                27 -> RequestedInteraction(
                    kind = RequestedInteraction.MemberKind.WORKFLOW_SCRIPT,
                    workflowScript = WorkflowScriptInteractionSpec(
                        title = nonEmpty(extractStringField(nested, 1)) ?: "Dynamic Workflow",
                        pythonScript = nonEmpty(extractStringField(nested, 2)) ?: "",
                        phaseNames = extractRepeatedStringField(nested, 3),
                    ),
                )
                else -> RequestedInteraction(
                    kind = RequestedInteraction.MemberKind.APPROVAL_INTERACTION,
                    rawSummary = nonEmpty(extractStringField(nested, 1)) ?: nonEmpty(extractStringField(nested, 2)),
                    rawWireFieldNumber = fieldNumber,
                )
            }
        }
        return null
    }

    private fun nonEmpty(value: String?): String? =
        value?.takeIf { it.trim().isNotEmpty() }

    private fun looksLikeArtifactDocument(content: String, uri: String): Boolean {
        val trimmed = content.trim()
        if (trimmed.length < 16) return false
        val lowerUri = ResolvedEmbedResource.normalizePath(uri).lowercase()
        val lowerBody = trimmed.lowercase()
        if (lowerUri.endsWith(".html") || lowerUri.endsWith(".htm")) {
            return lowerBody.contains("<html") || lowerBody.contains("<!doctype") ||
                lowerBody.contains("<div") || lowerBody.contains("<svg") ||
                lowerBody.contains("<style") || lowerBody.contains("<script")
        }
        if (lowerUri.endsWith(".svg")) return lowerBody.contains("<svg")
        if (lowerUri.endsWith(".json")) return trimmed.startsWith("{") || trimmed.startsWith("[")
        return trimmed.contains("\n") || trimmed.length >= 48
    }

    private fun readLengthDelimited(data: ByteArray, cursor: Cursor): ByteArray? {
        val length = readVarint(data, cursor)?.toInt() ?: return null
        if (length < 0 || cursor.offset + length > data.size) return null
        val slice = data.copyOfRange(cursor.offset, cursor.offset + length)
        cursor.offset += length
        return slice
    }

    private fun extractMessageField(data: ByteArray, targetField: Int): ByteArray? {
        val cursor = Cursor()
        while (cursor.offset < data.size) {
            val tag = readVarint(data, cursor) ?: break
            val fieldNumber = (tag shr 3).toInt()
            val wireType = (tag and 0x07UL).toInt()
            if (fieldNumber == targetField && wireType == 2) {
                return readLengthDelimited(data, cursor)
            }
            skipField(wireType, data, cursor)
        }
        return null
    }

    private fun extractVarintField(data: ByteArray, targetField: Int): ULong? {
        val cursor = Cursor()
        while (cursor.offset < data.size) {
            val tag = readVarint(data, cursor) ?: break
            val fieldNumber = (tag shr 3).toInt()
            val wireType = (tag and 0x07UL).toInt()
            if (fieldNumber == targetField && wireType == 0) {
                return readVarint(data, cursor)
            }
            skipField(wireType, data, cursor)
        }
        return null
    }

    private fun extractTimestampEpochMs(data: ByteArray, targetField: Int): Long? {
        val tsData = extractMessageField(data, targetField) ?: return null
        val secs = extractVarintField(tsData, 1)?.toLong() ?: return null
        if (secs <= 946_684_800L) return null
        val nanos = extractVarintField(tsData, 2)?.toLong() ?: 0L
        return secs * 1000L + nanos / 1_000_000L
    }

    private fun extractNestedStringField(data: ByteArray, outerField: Int, innerField: Int): String? =
        extractMessageField(data, outerField)?.let { extractStringField(it, innerField) }

    private fun extractStringField(data: ByteArray, targetField: Int): String? {
        val cursor = Cursor()
        while (cursor.offset < data.size) {
            val tag = readVarint(data, cursor) ?: break
            val fieldNumber = (tag shr 3).toInt()
            val wireType = (tag and 0x07UL).toInt()
            if (fieldNumber == targetField && wireType == 2) {
                return readLengthDelimited(data, cursor)?.decodeToString()
            }
            skipField(wireType, data, cursor)
        }
        return null
    }

    private fun extractRepeatedStringField(data: ByteArray, targetField: Int): List<String> {
        val cursor = Cursor()
        val results = mutableListOf<String>()
        while (cursor.offset < data.size) {
            val tag = readVarint(data, cursor) ?: break
            val fieldNumber = (tag shr 3).toInt()
            val wireType = (tag and 0x07UL).toInt()
            if (fieldNumber == targetField && wireType == 2) {
                val str = readLengthDelimited(data, cursor)?.decodeToString()
                if (!str.isNullOrEmpty()) results.add(str)
            } else {
                skipField(wireType, data, cursor)
            }
        }
        return results
    }

    private fun skipField(wireType: Int, data: ByteArray, cursor: Cursor) {
        when (wireType) {
            0 -> readVarint(data, cursor)
            1 -> cursor.offset = minOf(data.size, cursor.offset + 8)
            2 -> {
                val len = readVarint(data, cursor)?.toInt() ?: (data.size - cursor.offset)
                cursor.offset = minOf(data.size, cursor.offset + max(0, len))
            }
            5 -> cursor.offset = minOf(data.size, cursor.offset + 4)
            else -> cursor.offset = data.size
        }
    }
}
