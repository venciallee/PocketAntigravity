package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.AntigravityCloudDetector
import dev.antigravity.shared.model.AskQuestionInteractionSpec
import dev.antigravity.shared.model.BrowserUploadInteractionSpec
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeStep
import dev.antigravity.shared.model.CascadeSummary
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
import dev.antigravity.shared.model.WorkspaceInfo
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlin.math.max

/**
 * Pure Kotlin Multiplatform JSON decoders for Antigravity Desktop / Companion / Cloud Relay
 * responses (`GetWorkspaceInfos`, `GetAllCascadeTrajectories`, `GetCascadeTrajectorySteps`,
 * and `JetboxSubscribeToSummaries`).
 */
public object JsonStepAndSummaryDecoder {

    public data class JetboxDecodedEvent(
        public val summaries: List<CascadeSummary>,
        public val removedCascadeIds: List<String> = emptyList(),
    )

    public fun normalizeProtoModelEnum(modelId: String): String {
        val trimmed = modelId.trim()
        if (trimmed.startsWith("MODEL_")) return trimmed
        val lower = trimmed.lowercase()
        if (lower.contains("orchestrator")) {
            return when {
                lower.contains("carbon") -> "MODEL_ORCHESTRATOR_CARBON"
                lower.contains("argon") -> "MODEL_ORCHESTRATOR_ARGON"
                else -> "MODEL_ORCHESTRATOR_NEON"
            }
        }
        return when {
            lower.contains("neon") -> "MODEL_GOOGLE_GEMINI_4_NEON"
            lower.contains("carbon") -> "MODEL_GOOGLE_GEMINI_4_CARBON"
            lower.contains("argon") -> "MODEL_GOOGLE_GEMINI_4_ARGON"
            lower.contains("hydrogen") -> "MODEL_GOOGLE_GEMINI_4_HYDROGEN"
            lower.contains("flash") -> "MODEL_PLACEHOLDER_M18"
            lower.contains("sonnet") -> "MODEL_PLACEHOLDER_M35"
            lower.contains("opus") -> "MODEL_PLACEHOLDER_M26"
            lower.contains("low") -> "MODEL_PLACEHOLDER_M36"
            lower.contains("gemini") || lower.contains("pro") -> "MODEL_PLACEHOLDER_M37"
            else -> "MODEL_PLACEHOLDER_M37"
        }
    }

    public fun decodeWorkspaceInfo(
        element: JsonElement,
        originInstanceUuid: String? = null,
        originHostName: String? = null,
    ): WorkspaceInfo? {
        val obj = element as? JsonObject ?: return null
        val rawUri = obj.str("workspaceUri") ?: obj.str("workspaceFolderAbsoluteUri") ?: return null
        if (AntigravityCloudDetector.isGenericContainerUri(rawUri) ||
            AntigravityCloudDetector.isPlaygroundScratchUri(rawUri)
        ) {
            return null
        }
        val sourceHint = listOfNotNull(obj.str("runtime"), obj.str("source")).joinToString(" ")
        val isCloud = (obj.bool("isCloud") == true) ||
            AntigravityCloudDetector.isCloudWorkspaceUri(rawUri, sourceHint = sourceHint)
        val uri = AntigravityCloudDetector.normalizeWorkspaceUri(rawUri, isCloud = isCloud)
        if (uri.isEmpty()) return null
        val fallbackName = extractWorkspaceDisplayName(uri)
        val name = obj.str("displayName") ?: fallbackName
        if (AntigravityCloudDetector.isNoProjectSlug(name)) return null
        val branch = obj.str("activeBranch") ?: obj.str("gitBranch") ?: "main"
        val files = obj.arr("indexedFiles")?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList()
        return WorkspaceInfo(
            workspaceUri = uri,
            displayName = name,
            activeBranch = branch,
            indexedFiles = files,
            isCloud = isCloud,
            originInstanceUuid = originInstanceUuid,
            originHostName = if (isCloud) "Antigravity" else originHostName,
        )
    }

    public fun decodeTrajectorySummaryEntry(
        cascadeId: String,
        value: JsonElement,
        nowEpochMs: Long = currentTimeMillis(),
        forceCloud: Boolean = false,
        originInstanceUuid: String? = null,
        originHostName: String? = null,
    ): CascadeSummary? {
        val obj = value as? JsonObject ?: return null
        val annotations = obj.obj("annotations") ?: obj.obj("conversationAnnotations")
        val trajMeta = obj.obj("trajectoryMetadata")

        val resolvedTitle = listOf(
            annotations?.str("title"),
            annotations?.str("customTitle"),
            annotations?.str("name"),
            obj.str("summary"),
            obj.str("title"),
            obj.str("displayName"),
            obj.str("name"),
            trajMeta?.str("title"),
            trajMeta?.str("summary"),
            trajMeta?.str("name"),
            obj.str("firstUserInput"),
            obj.str("query"),
        ).firstNotNullOfOrNull { it?.trim()?.takeIf { s -> s.isNotEmpty() } }

        val stepCount = obj.int("stepCount") ?: obj.int("stepTotal") ?: 0
        val cloudProjectId = listOf(
            trajMeta?.str("projectId"),
            trajMeta?.str("project_id"),
            obj.str("projectId"),
            obj.str("project_id"),
            annotations?.str("projectId"),
            obj.obj("projectEnvConfig")?.str("projectId"),
            obj.obj("metadata")?.str("projectId"),
        ).firstNotNullOfOrNull { nonEmpty(it) }

        val explicitCloudBool = (obj.bool("cloud") == true) ||
            (obj.bool("isCloud") == true) ||
            (trajMeta?.bool("isCloud") == true)

        val statusEl = obj["status"] ?: obj["runStatus"] ?: obj["cascadeRunStatus"]
        val statusRaw = (statusEl as? JsonPrimitive)?.contentOrNull ?: "CASCADE_RUN_STATUS_IDLE"
        var status = when (val code = (statusEl as? JsonPrimitive)?.intOrNull) {
            null -> CortexStepStatus.fromJsonName(statusRaw)
            else -> CortexStepStatus.fromCascadeRunStatusCode(code)
        }
        if (status == CortexStepStatus.UNSPECIFIED) {
            if (obj.bool("waitingForUser") == true ||
                obj.bool("hasPendingInteraction") == true ||
                obj.bool("needsUserAction") == true
            ) {
                status = CortexStepStatus.WAITING
            } else if (obj.bool("isRunning") == true || obj.bool("running") == true) {
                status = CortexStepStatus.IN_PROGRESS
            }
        }
        val isActiveRun = status == CortexStepStatus.IN_PROGRESS ||
            status == CortexStepStatus.PENDING ||
            status == CortexStepStatus.WAITING

        if (resolvedTitle == null && stepCount == 0 && !explicitCloudBool && !forceCloud && !isActiveRun) {
            return null
        }
        val title = resolvedTitle ?: "New Conversation"
        val lowerTitle = title.lowercase()
        if (lowerTitle.contains("ios connect-rpc handshake") ||
            lowerTitle.contains("reply in one short sentence confirming ios connect-rpc handshake")
        ) {
            return null
        }

        val workspaceObjects = obj.arr("workspaces")?.mapNotNull { it as? JsonObject } ?: emptyList()
        val allMetaUris = trajMeta?.arr("workspaceUris")?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList()
        val directWsUri = obj.str("workspaceUri")
        val allCandidateUris = workspaceObjects.mapNotNull {
            it.str("workspaceFolderAbsoluteUri") ?: it.str("workspaceUri")
        } + allMetaUris + listOfNotNull(directWsUri)

        val hasCloudWsEntry = allCandidateUris.any { AntigravityCloudDetector.isCloudWorkspaceUri(it) }
        val selectedWorkspace = selectPrimaryWorkspaceObject(workspaceObjects)
        val metaWsUri = allMetaUris.firstOrNull { !AntigravityCloudDetector.isGenericContainerUri(it) }
        val primaryWsUri = selectedWorkspace?.str("workspaceFolderAbsoluteUri") ?: selectedWorkspace?.str("workspaceUri")
        val rawUri = listOfNotNull(primaryWsUri, metaWsUri, directWsUri)
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() && !AntigravityCloudDetector.isGenericContainerUri(it) }
            ?: ""

        val sourceHint = listOfNotNull(
            obj.str("source"),
            obj.str("runtime"),
            obj.str("backend"),
            trajMeta?.str("runtime"),
            trajMeta?.str("environment"),
            trajMeta?.str("executionEnvironment"),
            trajMeta?.str("source"),
        ).joinToString(" ")

        val isForceCloudContainer = forceCloud && run {
            val lowerRaw = rawUri.lowercase()
            lowerRaw.startsWith("file:///workspace/") ||
                lowerRaw.startsWith("file:///workspaces/") ||
                lowerRaw.startsWith("file:///root/")
        }

        val isCloud = explicitCloudBool ||
            hasCloudWsEntry ||
            isForceCloudContainer ||
            AntigravityCloudDetector.isCloudWorkspaceUri(rawUri, cascadeId = cascadeId, sourceHint = sourceHint)

        val isScratch = AntigravityCloudDetector.isPlaygroundScratchUri(rawUri)
        val isUnassigned = cloudProjectId.isNullOrEmpty() && (rawUri.isEmpty() || isScratch)

        val uri = when {
            isUnassigned -> if (isScratch) rawUri else ""
            rawUri.isEmpty() && !cloudProjectId.isNullOrEmpty() -> "cloud://$cloudProjectId"
            else -> AntigravityCloudDetector.normalizeWorkspaceUri(rawUri, isCloud = isCloud)
        }

        val explicitSlug = (obj.str("projectSlug") ?: obj.str("project"))?.trim()
        val slug = when {
            !explicitSlug.isNullOrEmpty() && !AntigravityCloudDetector.isNoProjectSlug(explicitSlug) -> explicitSlug
            isUnassigned -> AntigravityCloudDetector.NO_PROJECT_DISPLAY_NAME
            rawUri.isEmpty() && !cloudProjectId.isNullOrEmpty() -> cloudProjectId
            else -> {
                val derived = extractWorkspaceDisplayName(uri.ifEmpty { rawUri })
                if (derived.isNotEmpty() && !AntigravityCloudDetector.isNoProjectSlug(derived)) {
                    derived
                } else {
                    cloudProjectId ?: AntigravityCloudDetector.NO_PROJECT_DISPLAY_NAME
                }
            }
        }

        val branch = if (isUnassigned) {
            ""
        } else {
            selectedWorkspace?.str("gitBranch")
                ?: selectedWorkspace?.str("branchName")
                ?: obj.str("branchName")
                ?: "main"
        }

        val candidateUpdated = listOfNotNull(
            parseProtoTimestampEpochMs(obj["lastModifiedTime"]),
            parseProtoTimestampEpochMs(obj["updatedAt"]),
            parseProtoTimestampEpochMs(obj["lastStepTime"]),
            parseProtoTimestampEpochMs(obj["lastAgentReplyTime"]),
            parseProtoTimestampEpochMs(obj.obj("latestNotifyUserStep")?.obj("step")?.obj("metadata")?.get("createdAt")),
            parseProtoTimestampEpochMs(obj.obj("latestTaskBoundaryStep")?.obj("step")?.obj("metadata")?.get("createdAt")),
        )
        val updatedEpochMs = candidateUpdated.maxOrNull() ?: parseProtoTimestampEpochMs(obj["createdTime"])
        val lastViewedEpochMs = listOf(
            annotations?.get("lastUserViewTime"),
            annotations?.get("last_user_view_time"),
            annotations?.get("lastViewedTime"),
            annotations?.get("lastReadTime"),
            obj["lastUserViewTime"],
            obj["last_user_view_time"],
            obj["lastViewedTime"],
            trajMeta?.get("lastUserViewTime"),
        ).firstNotNullOfOrNull { parseProtoTimestampEpochMs(it) }

        val finalUpdatedAt = updatedEpochMs ?: nowEpochMs
        val relativeLabel = obj.str("relativeTimeLabel")
            ?: formatRelativeTimeLabel(updatedEpochMs, nowEpochMs)

        val explicitUnread = listOf(
            obj.bool("isUnread"),
            obj.bool("unread"),
            obj.bool("hasUnread"),
            obj.bool("hasUnreadMessages"),
            obj.bool("hasUnseenUpdates"),
            obj.bool("unseen"),
            annotations?.bool("isUnread"),
            annotations?.bool("unread"),
            annotations?.bool("hasUnread"),
            trajMeta?.bool("unread"),
            trajMeta?.bool("isUnread"),
        ).firstOrNull { it != null }

        val isUnread = when {
            explicitUnread != null -> explicitUnread
            status == CortexStepStatus.IN_PROGRESS || status == CortexStepStatus.PENDING -> false
            updatedEpochMs != null && lastViewedEpochMs != null ->
                (updatedEpochMs - lastViewedEpochMs) > 500L ||
                    statusRaw.equals("CASCADE_RUN_STATUS_DONE", ignoreCase = true) ||
                    status == CortexStepStatus.WAITING
            else -> statusRaw.equals("CASCADE_RUN_STATUS_DONE", ignoreCase = true) ||
                status == CortexStepStatus.WAITING
        }

        val isPinned = obj.bool("isPinned")
            ?: annotations?.bool("pinned")
            ?: annotations?.bool("isPinned")
            ?: false
        val isArchived = obj.bool("isArchived")
            ?: annotations?.bool("archived")
            ?: annotations?.bool("isArchived")
            ?: false

        val explicitSubtitle = obj.str("statusSubtitle") ?: obj.str("subtitle")
        val subtitle = buildLiveStatusSubtitle(
            status = status,
            stepCount = stepCount,
            isUnread = isUnread,
            explicitSubtitle = explicitSubtitle,
        )

        val decoded = CascadeSummary(
            cascadeId = cascadeId,
            title = title,
            projectSlug = slug.ifEmpty { AntigravityCloudDetector.NO_PROJECT_DISPLAY_NAME },
            workspaceUri = uri,
            branchName = branch,
            status = status,
            stepCount = stepCount,
            currentStepIndex = obj.int("stepIndex") ?: max(1, stepCount),
            totalSteps = obj.int("stepTotal") ?: max(1, stepCount),
            updatedAtEpochMs = finalUpdatedAt,
            relativeTimeLabel = relativeLabel,
            statusSubtitle = subtitle,
            isPinned = isPinned,
            isArchived = isArchived,
            isUnread = isUnread,
            pendingInteractionTitle = obj.str("pendingInteractionTitle") ?: obj.str("pendingCommand"),
            totalAdditions = obj.int("diffAdditions") ?: obj.int("totalAdditions") ?: 0,
            totalDeletions = obj.int("diffDeletions") ?: obj.int("totalDeletions") ?: 0,
            isCloud = isCloud,
            cloudProjectId = cloudProjectId,
            originInstanceUuid = originInstanceUuid,
            originHostName = if (isCloud) "Antigravity" else originHostName,
            lastUserViewTimeEpochMs = lastViewedEpochMs,
        )
        if (!forceCloud) return decoded
        // Ignore echoed local `file://` workspaces from servers that do not filter by `backend`,
        // while keeping Cloud `No Project` / UUID sessions (`workspaceUri.isEmpty()`) and forcing `isCloud = true`.
        if (decoded.workspaceUri.isNotEmpty() &&
            !AntigravityCloudDetector.isPlaygroundScratchUri(decoded.workspaceUri) &&
            !decoded.isCloud &&
            decoded.cloudProjectId.isNullOrEmpty()
        ) {
            return null
        }
        return decoded.copy(
            isCloud = true,
            originHostName = "Antigravity",
        )
    }

    public fun decodeJetboxSummariesEvent(
        obj: JsonObject,
        nowEpochMs: Long = currentTimeMillis(),
        forceCloud: Boolean = false,
        originInstanceUuid: String? = null,
        originHostName: String? = null,
    ): JetboxDecodedEvent {
        val summaries = mutableListOf<CascadeSummary>()
        val removedIds = mutableListOf<String>()

        // Format 1: Native Jetbox `{"updates": {"<id>": {...}}, "removedCascadeIds": [...]}` or `trajectorySummaries`
        val updatesMap = obj.obj("updates") ?: obj.obj("trajectorySummaries")
        if (updatesMap != null) {
            for ((cid, entry) in updatesMap) {
                val entryObj = entry as? JsonObject
                if (entryObj != null &&
                    entryObj.bool("killed") == true &&
                    (entryObj.str("status") ?: "").contains("UNSPECIFIED")
                ) {
                    continue
                }
                decodeTrajectorySummaryEntry(
                    cascadeId = cid,
                    value = entry,
                    nowEpochMs = nowEpochMs,
                    forceCloud = forceCloud,
                    originInstanceUuid = originInstanceUuid,
                    originHostName = originHostName,
                )?.let { summaries.add(it) }
            }
        }

        // Format 2: Companion / mock `{"summaries": [...]}` or `{"trajectories": [...]}`
        (obj.arr("summaries") ?: obj.arr("trajectories"))?.forEach { item ->
            val itemObj = item as? JsonObject ?: return@forEach
            val cid = itemObj.str("cascadeId") ?: return@forEach
            decodeTrajectorySummaryEntry(
                cascadeId = cid,
                value = itemObj,
                nowEpochMs = nowEpochMs,
                forceCloud = forceCloud,
                originInstanceUuid = originInstanceUuid,
                originHostName = originHostName,
            )?.let { summaries.add(it) }
        }

        // Format 3: Companion / mock single delta `{"delta": {"cascadeId": ..., "status": ...}}`
        obj.obj("delta")?.let { deltaObj ->
            val cid = deltaObj.str("cascadeId")
            if (!cid.isNullOrEmpty()) {
                decodeTrajectorySummaryEntry(
                    cascadeId = cid,
                    value = deltaObj,
                    nowEpochMs = nowEpochMs,
                    forceCloud = forceCloud,
                    originInstanceUuid = originInstanceUuid,
                    originHostName = originHostName,
                )?.let { summaries.add(it) }
            }
        }

        (obj.arr("removedCascadeIds") ?: obj.arr("deletes"))?.forEach { el ->
            (el as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotEmpty() }?.let { removedIds.add(it) }
        }
        return JetboxDecodedEvent(summaries = summaries, removedCascadeIds = removedIds)
    }

    public fun decodeSingleStepJson(
        raw: JsonObject,
        cascadeId: String,
        stepIndex: Int,
        nowEpochMs: Long = currentTimeMillis(),
    ): CascadeStep? = decodeJsonStep(
        element = raw,
        cascadeId = cascadeId,
        fallbackIndex = stepIndex,
        nowEpochMs = nowEpochMs,
    )

    public fun decodeJsonStep(
        element: JsonElement,
        cascadeId: String,
        fallbackIndex: Int,
        nowEpochMs: Long = currentTimeMillis(),
    ): CascadeStep? {
        val obj = element as? JsonObject ?: return null
        val stepIndex = obj.int("stepIndex") ?: fallbackIndex
        val rawTypePrim = obj["type"] as? JsonPrimitive
        var stepType = resolveStepType(rawTypePrim)
        val stepStatus = resolveStepStatus(obj["status"])

        var userText: String? = nonEmpty(obj.str("userInput"))
        val mentions = obj.arr("attachedMentions")
            ?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
            ?.toMutableList()
            ?: mutableListOf()
        var recordedMode: CascadeExecutionMode? = null
        var recordedModelId: String? = null

        obj.obj("userInput")?.let { uiObj ->
            val itemsJoined = uiObj.arr("items")
                ?.mapNotNull { (it as? JsonObject)?.str("text")?.let(::nonEmpty) }
                ?.joinToString("\n")
            userText = nonEmpty(uiObj.str("userResponse"))
                ?: nonEmpty(uiObj.str("query"))
                ?: nonEmpty(uiObj.str("text"))
                ?: nonEmpty(uiObj.str("prompt"))
                ?: nonEmpty(uiObj.str("message"))
                ?: nonEmpty(itemsJoined)

            uiObj.arr("items")?.forEach { itemEl ->
                val fileObj = (itemEl as? JsonObject)?.obj("item")?.obj("file")
                if (fileObj != null) {
                    val label = nonEmpty(fileObj.str("label"))
                    if (label != null) {
                        if (label !in mentions) mentions.add(label)
                    } else {
                        val absUri = nonEmpty(fileObj.str("absoluteUri"))
                        if (absUri != null) {
                            val base = ResolvedEmbedResource.normalizePath(absUri).trimEnd('/').substringAfterLast('/')
                            val chip = if (base.startsWith("@")) base else "@$base"
                            if (base.isNotEmpty() && chip !in mentions) mentions.add(chip)
                        }
                    }
                }
            }

            val userCfg = uiObj.obj("userConfig") ?: uiObj.obj("lastUserConfig")
            userCfg?.obj("plannerConfig")?.let { plannerCfg ->
                plannerCfg.obj("conversational")?.bool("agenticMode")?.let { agentic ->
                    recordedMode = if (agentic) CascadeExecutionMode.PLANNING else CascadeExecutionMode.FAST
                }
                val reqModelObj = plannerCfg.obj("requestedModel")
                val candModel = nonEmpty(reqModelObj?.str("model"))
                    ?: nonEmpty(reqModelObj?.str("alias"))
                    ?: nonEmpty(plannerCfg.str("planModel"))
                if (candModel != null && candModel != "MODEL_UNSPECIFIED") {
                    recordedModelId = candModel
                }
            }
            if (stepType == CortexStepType.UNSPECIFIED && (userText != null || mentions.isNotEmpty())) {
                stepType = CortexStepType.USER_INPUT
            }
        }

        var plannerPayload: PlannerResponsePayload? = null
        val pr = obj.obj("plannerResponse")
        val nu = obj.obj("notifyUser")
        if (pr != null) {
            val text = nonEmpty(pr.str("modifiedResponse"))
                ?: nonEmpty(pr.str("response"))
                ?: nonEmpty(pr.str("text"))
                ?: nonEmpty(pr.str("content"))
                ?: nonEmpty(pr.str("message"))
                ?: ""
            val thinking = nonEmpty(pr.str("thinking"))
            val duration = parseDurationSeconds(pr["thinkingDurationSeconds"] ?: pr["thinkingDuration"])
            if (text.isNotEmpty() || thinking != null ||
                stepStatus == CortexStepStatus.IN_PROGRESS || stepStatus == CortexStepStatus.PENDING
            ) {
                plannerPayload = PlannerResponsePayload(
                    response = text,
                    thinking = thinking,
                    thinkingDurationSeconds = duration,
                )
                if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.PLANNER_RESPONSE
            }
        } else if (nu != null) {
            val notifyText = nonEmpty(nu.str("notificationContent"))
                ?: nonEmpty(nu.str("message"))
                ?: nonEmpty(nu.str("reviewContent"))
            val paths = (nu.arr("pathsToReview") ?: nu.arr("reviewAbsoluteUris"))
                ?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
                ?: emptyList()
            if (notifyText != null || paths.isNotEmpty()) {
                plannerPayload = PlannerResponsePayload(
                    response = notifyText ?: "Ready for your review.",
                    referencedFiles = paths,
                )
                stepType = CortexStepType.NOTIFY_USER
            }
        }

        var runCmdPayload: RunCommandPayload? = null
        val rc = obj.obj("runCommand") ?: obj.obj("shellExec")
        val sci = obj.obj("sendCommandInput")
        if (rc != null) {
            val cmdLine = nonEmpty(rc.str("commandLine"))
                ?: nonEmpty(rc.str("proposedCommandLine"))
                ?: nonEmpty(rc.str("command"))
                ?: nonEmpty(rc.str("CommandLine"))
                ?: ""
            val cwd = nonEmpty(rc.str("cwd")) ?: nonEmpty(rc.str("Cwd")) ?: "~"
            if (cmdLine.isNotEmpty()) {
                runCmdPayload = RunCommandPayload(
                    commandId = rc.str("commandId") ?: "cmd-$stepIndex",
                    commandLine = cmdLine,
                    proposedCommandLine = nonEmpty(rc.str("proposedCommandLine")) ?: cmdLine,
                    cwd = cwd,
                    exitCode = rc.int("exitCode"),
                    outputPreview = nonEmpty(rc.obj("combinedOutput")?.str("full"))
                        ?: nonEmpty(rc.str("outputPreview"))
                        ?: nonEmpty(rc.str("output")),
                )
                if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.RUN_COMMAND
            }
        } else if (sci != null) {
            val inputText = nonEmpty(sci.str("input")) ?: nonEmpty(sci.str("commandLine")) ?: ""
            if (inputText.isNotEmpty()) {
                runCmdPayload = RunCommandPayload(
                    commandId = sci.str("commandId") ?: "stdin-$stepIndex",
                    commandLine = inputText,
                    proposedCommandLine = inputText,
                    cwd = "~",
                )
            }
            if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.SEND_COMMAND_INPUT
        }

        var interaction: RequestedInteraction? = null
        obj.obj("requestedInteraction")?.let { reqInt ->
            interaction = decodeJsonRequestedInteraction(
                reqInt,
                fallbackCommandLine = runCmdPayload?.proposedCommandLine ?: runCmdPayload?.commandLine,
                fallbackCwd = runCmdPayload?.cwd,
            )
            if (interaction?.kind == RequestedInteraction.MemberKind.RUN_COMMAND) {
                val spec = interaction?.runCommand
                if (spec != null) {
                    if (runCmdPayload == null) {
                        runCmdPayload = RunCommandPayload(
                            commandId = "cmd-$stepIndex",
                            commandLine = spec.proposedCommandLine,
                            proposedCommandLine = spec.proposedCommandLine,
                            cwd = spec.cwd,
                        )
                    } else if (runCmdPayload!!.commandLine.isBlank() && spec.proposedCommandLine.isNotEmpty()) {
                        runCmdPayload = runCmdPayload!!.copy(
                            commandLine = spec.proposedCommandLine,
                            proposedCommandLine = spec.proposedCommandLine,
                        )
                    }
                }
            }
        }

        if (interaction == null &&
            (stepStatus == CortexStepStatus.WAITING || stepStatus == CortexStepStatus.BLOCKED) &&
            runCmdPayload != null &&
            stepType == CortexStepType.RUN_COMMAND
        ) {
            interaction = RequestedInteraction(
                kind = RequestedInteraction.MemberKind.RUN_COMMAND,
                runCommand = RunCommandInteractionSpec(
                    proposedCommandLine = runCmdPayload!!.proposedCommandLine ?: runCmdPayload!!.commandLine,
                    cwd = runCmdPayload!!.cwd,
                ),
                rawMemberKey = "runCommand",
            )
        }

        var viewFilePayload: ViewFilePayload? = null
        val vfCandidate = obj.obj("viewFile") ?: obj.obj("viewFileOutline") ?: obj.obj("viewCodeItem")
        val ldCandidate = obj.obj("listDirectory")
        if (vfCandidate != null) {
            val uri = nonEmpty(vfCandidate.str("fileUri"))
                ?: nonEmpty(vfCandidate.str("absolutePathUri"))
                ?: nonEmpty(vfCandidate.str("absolutePath"))
                ?: nonEmpty(vfCandidate.str("path"))
            if (uri != null) {
                val rawContent = nonEmpty(vfCandidate.str("content"))
                val captured = if (ResolvedEmbedResource.isEmbeddableTextArtifactPath(uri) &&
                    rawContent != null && rawContent.encodeToByteArray().size <= 524_288
                ) {
                    rawContent
                } else {
                    null
                }
                viewFilePayload = ViewFilePayload(
                    fileUri = uri,
                    startLine = vfCandidate.int("startLine") ?: 1,
                    endLine = vfCandidate.int("endLine") ?: 120,
                    fileContent = captured,
                )
                if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.VIEW_FILE
            }
        } else if (ldCandidate != null) {
            val uri = nonEmpty(ldCandidate.str("directoryPathUri"))
                ?: nonEmpty(ldCandidate.str("directoryPath"))
                ?: nonEmpty(ldCandidate.str("absolutePathUri"))
                ?: nonEmpty(ldCandidate.str("path"))
            if (uri != null) {
                viewFilePayload = ViewFilePayload(fileUri = uri, startLine = 1, endLine = 1)
                if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.LIST_DIRECTORY
            }
        }

        var searchPayload: SearchPayload? = null
        val searchCandidate = obj.obj("grepSearch") ?: obj.obj("findByName") ?: obj.obj("search")
        if (searchCandidate != null) {
            val query = nonEmpty(searchCandidate.str("query")) ?: nonEmpty(searchCandidate.str("pattern")) ?: "workspace"
            val scope = nonEmpty(searchCandidate.str("searchPath"))
                ?: nonEmpty(searchCandidate.str("searchDirectory"))
                ?: nonEmpty(searchCandidate.str("searchPathUri"))
                ?: "."
            val count = searchCandidate.arr("results")?.size ?: searchCandidate.int("matchCount") ?: 0
            searchPayload = SearchPayload(query = query, scopeDirectory = scope, matchCount = count)
            if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.SEARCH
        }

        var codeActionPayload: CodeActionPayload? = null
        val ca = obj.obj("codeAction")
            ?: obj.obj("replaceFileContent")
            ?: obj.obj("multiReplaceFileContent")
            ?: obj.obj("writeToFile")
            ?: obj.obj("fileChange")
        if (ca != null) {
            val actionSpec = ca.obj("actionSpec")
            val createFileSpec = actionSpec?.obj("createFile")
            val uri = listOf(
                "targetFileUri", "fileUri", "targetFile", "TargetFile",
                "absoluteUri", "absolutePathUri", "absolutePath", "filePath", "path",
            ).firstNotNullOfOrNull { nonEmpty(ca.str(it)) }
                ?: listOf(
                    createFileSpec,
                    actionSpec?.obj("insertBlock"),
                    actionSpec?.obj("editFile"),
                    actionSpec?.obj("replaceFileContent"),
                ).firstNotNullOfOrNull { nonEmpty(it?.obj("path")?.str("absoluteUri")) }

            if (uri != null) {
                val lowerUri = uri.lowercase()
                val isArtifact = (ca["artifactMetadata"] != null) ||
                    (ca.bool("isArtifactFile") == true) ||
                    lowerUri.contains("/.gemini/") ||
                    lowerUri.contains("/brain/")
                val capturedContent = if (isArtifact || ResolvedEmbedResource.isEmbeddableTextArtifactPath(uri)) {
                    listOf(
                        ca.str("codeContent"),
                        ca.str("content"),
                        ca.str("fileContent"),
                        createFileSpec?.str("codeContent"),
                        createFileSpec?.str("content"),
                        createFileSpec?.str("fileContent"),
                        createFileSpec?.str("instruction"),
                    ).firstNotNullOfOrNull { c ->
                        nonEmpty(c)?.takeIf { it.encodeToByteArray().size <= 524_288 }
                    }
                } else {
                    null
                }
                codeActionPayload = CodeActionPayload(
                    targetFileUri = uri,
                    description = nonEmpty(ca.str("description")) ?: nonEmpty(ca.str("instruction")) ?: "Updated file",
                    additions = ca.int("additions") ?: 0,
                    deletions = ca.int("deletions") ?: 0,
                    isArtifactFile = isArtifact,
                    fileContent = capturedContent,
                )
                if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.CODE_ACTION
            }
        }

        var taskBoundaryPayload: TaskBoundaryPayload? = null
        obj.obj("taskBoundary")?.let { tb ->
            taskBoundaryPayload = TaskBoundaryPayload(
                taskName = nonEmpty(tb.str("taskName")) ?: "Task",
                taskStatus = nonEmpty(tb.str("taskStatus")) ?: "",
                taskSummary = nonEmpty(tb.str("taskSummary")) ?: "",
                completedCount = tb.int("completedCount") ?: 0,
                totalCount = tb.int("totalCount") ?: 0,
                elapsedLabel = nonEmpty(tb.str("elapsedLabel")) ?: "",
            )
            if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.TASK_BOUNDARY
        }

        var subagentPayload: SubagentPayload? = null
        (obj.obj("subagentInvocation") ?: obj.obj("subagent"))?.let { sub ->
            subagentPayload = SubagentPayload(
                subagentId = nonEmpty(sub.str("subagentId")) ?: "sub-$stepIndex",
                role = nonEmpty(sub.str("role")) ?: "Subagent",
                typeName = nonEmpty(sub.str("typeName")) ?: "self",
                modelLabel = nonEmpty(sub.str("modelLabel")) ?: "Gemini 4 Hydrogen",
                status = stepStatus,
                summary = nonEmpty(sub.str("summary")) ?: "",
                waitingApprovalTitle = nonEmpty(sub.str("waitingApprovalTitle")),
            )
            if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.SUBAGENT_INVOCATION
        }

        var dynamicWorkflowPayload: DynamicWorkflowPayload? = null
        obj.obj("dynamicWorkflow")?.let { wf ->
            val phaseNames = wf.arr("phaseNames")?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList()
            val phases = phaseNames.mapIndexed { idx, name -> WorkflowPhaseItem("phase-$idx", name) }
            dynamicWorkflowPayload = DynamicWorkflowPayload(
                workflowId = nonEmpty(wf.str("workflowId")) ?: "wf-$stepIndex",
                description = nonEmpty(wf.str("description")) ?: "Dynamic Workflow",
                pythonScript = nonEmpty(wf.str("pythonScript")) ?: "",
                currentPhase = nonEmpty(wf.str("currentPhase")) ?: phaseNames.firstOrNull() ?: "Phase 1",
                completedAgents = wf.int("completedAgents") ?: 0,
                totalAgents = wf.int("totalAgents") ?: max(1, phases.size),
                phases = phases,
            )
            if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.DYNAMIC_WORKFLOW
        }

        var swarmBoardPayload: SwarmBoardPayload? = null
        obj.obj("swarmBoard")?.let { sw ->
            val memberNames = sw.arr("memberNames")?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList()
            swarmBoardPayload = SwarmBoardPayload(
                swarmId = nonEmpty(sw.str("swarmId")) ?: "swarm-$stepIndex",
                title = nonEmpty(sw.str("title")) ?: "Swarm Team",
                members = memberNames.map { SwarmMemberItem(name = it, role = "Specialist", status = stepStatus) },
            )
            if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.SWARM_BOARD
        }

        var mcpToolCallPayload: McpToolCallPayload? = null
        (obj.obj("mcpToolCall") ?: obj.obj("mcp"))?.let { mcp ->
            mcpToolCallPayload = McpToolCallPayload(
                serverName = nonEmpty(mcp.str("serverName")) ?: "mcp",
                toolName = nonEmpty(mcp.str("toolName")) ?: "tool",
                pluginName = nonEmpty(mcp.str("pluginName")),
                argumentsPreview = nonEmpty(mcp.str("argumentsPreview")) ?: "{}",
                resultPreview = nonEmpty(mcp.str("resultPreview")),
                isError = stepStatus == CortexStepStatus.ERROR,
            )
            if (stepType == CortexStepType.UNSPECIFIED) stepType = CortexStepType.MCP_TOOL_CALL
        }

        if ((stepType == CortexStepType.PLANNER_RESPONSE || stepType == CortexStepType.NOTIFY_USER) &&
            plannerPayload == null &&
            (stepStatus == CortexStepStatus.IN_PROGRESS || stepStatus == CortexStepStatus.PENDING)
        ) {
            plannerPayload = PlannerResponsePayload(response = "")
        }

        val createdAtMs = parseProtoTimestampEpochMs(obj.obj("metadata")?.get("createdAt") ?: obj["createdAt"])
            ?: nowEpochMs

        val resolvedRawTypeName: String? = if (stepType == CortexStepType.UNSPECIFIED) {
            val rawInt = rawTypePrim?.intOrNull
            val rawStr = nonEmpty(rawTypePrim?.contentOrNull)
            when {
                rawInt != null && rawInt != 0 -> "STEP_TYPE_$rawInt"
                rawStr != null &&
                    !rawStr.equals("CORTEX_STEP_TYPE_UNSPECIFIED", ignoreCase = true) &&
                    !rawStr.equals("UNSPECIFIED", ignoreCase = true) -> rawStr
                else -> null
            }
        } else {
            null
        }

        val resolvedFallbackSummary: String? = if (stepType == CortexStepType.UNSPECIFIED) {
            extractFallbackSummaryFromUnknownStep(obj)
        } else {
            null
        }

        return CascadeStep(
            cascadeId = cascadeId,
            stepIndex = stepIndex,
            type = stepType,
            status = stepStatus,
            createdAtEpochMs = createdAtMs,
            userInput = userText,
            attachedMentions = mentions,
            plannerResponse = plannerPayload,
            taskBoundary = taskBoundaryPayload,
            runCommand = runCmdPayload,
            codeAction = codeActionPayload,
            viewFile = viewFilePayload,
            search = searchPayload,
            requestedInteraction = interaction,
            recordedExecutionMode = recordedMode,
            recordedModelId = recordedModelId,
            subagent = subagentPayload,
            dynamicWorkflow = dynamicWorkflowPayload,
            swarmBoard = swarmBoardPayload,
            mcpToolCall = mcpToolCallPayload,
            rawTypeName = resolvedRawTypeName,
            fallbackSummary = resolvedFallbackSummary,
        )
    }

    public fun decodeJsonRequestedInteraction(
        obj: JsonObject,
        fallbackCommandLine: String? = null,
        fallbackCwd: String? = null,
    ): RequestedInteraction? {
        obj.obj("runCommand")?.let { rc ->
            val proposed = nonEmpty(rc.str("proposedCommandLine"))
                ?: nonEmpty(rc.str("commandLine"))
                ?: nonEmpty(fallbackCommandLine)
                ?: ""
            val cwd = nonEmpty(rc.str("cwd")) ?: nonEmpty(fallbackCwd) ?: "/workspace"
            return RequestedInteraction(
                kind = RequestedInteraction.MemberKind.RUN_COMMAND,
                runCommand = RunCommandInteractionSpec(
                    proposedCommandLine = proposed,
                    cwd = cwd,
                    isDaemon = rc.bool("isDaemon") ?: false,
                ),
                rawMemberKey = "runCommand",
            )
        }
        obj.obj("permission")?.let { perm ->
            val action = nonEmpty(perm.str("action")) ?: "tool"
            val target = nonEmpty(perm.str("target")) ?: nonEmpty(perm.str("suggestedPersistPattern")) ?: "*"
            val persistRaw = perm.int("persistSuggestionType") ?: 1
            return RequestedInteraction(
                kind = RequestedInteraction.MemberKind.PERMISSION,
                permission = PermissionInteractionSpec(
                    action = action,
                    target = target,
                    suggestedPersistPattern = nonEmpty(perm.str("suggestedPersistPattern")),
                    persistSuggestionType = PersistSuggestionType.fromRaw(persistRaw),
                    reason = nonEmpty(perm.str("reason")),
                    pluginName = nonEmpty(perm.str("pluginName")),
                ),
                pluginName = nonEmpty(perm.str("pluginName")),
                rawMemberKey = "permission",
            )
        }
        obj.obj("filePermission")?.let { fp ->
            return RequestedInteraction(
                kind = RequestedInteraction.MemberKind.FILE_PERMISSION,
                filePermission = FilePermissionInteractionSpec(
                    absolutePathUri = nonEmpty(fp.str("absolutePathUri")) ?: "",
                    isDirectory = fp.bool("isDirectory") ?: false,
                    blockReason = nonEmpty(fp.str("blockReason")),
                ),
                rawMemberKey = "filePermission",
            )
        }
        (obj.obj("askQuestion") ?: obj.obj("elicitation"))?.let { qa ->
            val key = if (obj.containsKey("askQuestion")) "askQuestion" else "elicitation"
            val kind = if (key == "askQuestion") RequestedInteraction.MemberKind.ASK_QUESTION else RequestedInteraction.MemberKind.ELICITATION
            return RequestedInteraction(
                kind = kind,
                askQuestion = AskQuestionInteractionSpec(
                    question = nonEmpty(qa.str("question")) ?: "Clarification needed",
                    options = qa.arr("options")?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList(),
                    isMultiSelect = qa.bool("isMultiSelect") ?: false,
                ),
                rawMemberKey = key,
            )
        }
        obj.obj("executeUrl")?.let { eu ->
            val url = nonEmpty(eu.str("url")) ?: ""
            val domain = nonEmpty(eu.str("domain")) ?: url.substringAfter("://", url).substringBefore('/')
            return RequestedInteraction(
                kind = RequestedInteraction.MemberKind.EXECUTE_URL,
                executeUrl = ExecuteUrlInteractionSpec(url = url, domain = domain, isRedirect = eu.bool("isRedirect") ?: false),
                rawMemberKey = "executeUrl",
            )
        }
        obj.obj("downloadUrl")?.let { du ->
            val url = nonEmpty(du.str("url")) ?: ""
            return RequestedInteraction(
                kind = RequestedInteraction.MemberKind.DOWNLOAD_URL,
                downloadUrl = DownloadUrlInteractionSpec(
                    url = url,
                    origin = nonEmpty(du.str("origin")) ?: url.substringAfter("://", "unknown").substringBefore('/'),
                    fileName = nonEmpty(du.str("fileName")) ?: url.substringAfterLast('/').ifEmpty { "download.bin" },
                    mimeType = nonEmpty(du.str("mimeType")) ?: "application/octet-stream",
                    destinationFolder = nonEmpty(du.str("destinationFolder")) ?: "~/Downloads",
                ),
                rawMemberKey = "downloadUrl",
            )
        }
        obj.obj("browserUpload")?.let { bu ->
            return RequestedInteraction(
                kind = RequestedInteraction.MemberKind.BROWSER_UPLOAD,
                browserUpload = BrowserUploadInteractionSpec(
                    origin = nonEmpty(bu.str("origin")) ?: "https://app.example.com",
                    fileNames = bu.arr("fileNames")?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList(),
                ),
                rawMemberKey = "browserUpload",
            )
        }
        obj.obj("workflowScript")?.let { ws ->
            return RequestedInteraction(
                kind = RequestedInteraction.MemberKind.WORKFLOW_SCRIPT,
                workflowScript = WorkflowScriptInteractionSpec(
                    title = nonEmpty(ws.str("title")) ?: "Dynamic Workflow",
                    pythonScript = nonEmpty(ws.str("pythonScript")) ?: "",
                    phaseNames = ws.arr("phaseNames")?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull } ?: emptyList(),
                ),
                rawMemberKey = "workflowScript",
            )
        }
        obj.obj("mcp")?.let { mcp ->
            return RequestedInteraction(
                kind = RequestedInteraction.MemberKind.MCP,
                mcpServerName = nonEmpty(mcp.str("serverName")) ?: "mcp-server",
                mcpToolName = nonEmpty(mcp.str("toolName")) ?: "invoke_tool",
                pluginName = nonEmpty(mcp.str("pluginName")),
                rawMemberKey = "mcp",
            )
        }
        // Fallback: preserve exact wire key for any other upstream oneof member (`deploy`, `browserAction`, etc.)
        val firstMemberKey = obj.keys.firstOrNull { key -> key != "metadata" && obj[key] is JsonObject }
            ?: obj.keys.firstOrNull { key -> obj[key] is JsonObject }
        if (firstMemberKey != null) {
            val mapped = RequestedInteraction.MemberKind.fromWireKey(firstMemberKey)
                ?: RequestedInteraction.MemberKind.APPROVAL_INTERACTION
            val summary = obj.obj(firstMemberKey)?.let { extractSummaryFromUnknownObject(it) }
            return RequestedInteraction(
                kind = mapped,
                rawMemberKey = firstMemberKey,
                rawSummary = summary,
                rawWireFieldNumber = null,
            )
        }
        return null
    }

    private fun extractFallbackSummaryFromUnknownStep(obj: JsonObject): String? {
        for ((key, value) in obj) {
            if (key == "metadata" || key == "requestedInteraction") continue
            val nested = value as? JsonObject ?: continue
            extractSummaryFromUnknownObject(nested)?.let { return it }
        }
        return extractSummaryFromUnknownObject(obj)
    }

    private fun extractSummaryFromUnknownObject(obj: JsonObject): String? {
        val preferredKeys = listOf("summary", "title", "description", "message", "text", "label", "reason", "prompt", "content", "name")
        for (k in preferredKeys) {
            nonEmpty(obj.str(k))?.let { return it.take(240) }
        }
        for ((key, value) in obj) {
            if (key == "type" || key == "status" || key == "cascadeId" || key == "stepIndex") continue
            val prim = value as? JsonPrimitive ?: continue
            if (prim.isString) {
                nonEmpty(prim.contentOrNull)?.let { return it.take(240) }
            }
        }
        return null
    }

    public fun parseProtoTimestampEpochMs(element: JsonElement?): Long? {
        if (element == null) return null
        if (element is JsonObject) {
            val secs = (element["seconds"] as? JsonPrimitive)?.let { it.longOrNull ?: it.contentOrNull?.toLongOrNull() }
                ?: return null
            val nanos = (element["nanos"] as? JsonPrimitive)?.let { it.longOrNull ?: it.contentOrNull?.toLongOrNull() }
                ?: 0L
            return secs * 1000L + (nanos / 1_000_000L)
        }
        val raw = (element as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        raw.toLongOrNull()?.let { numeric ->
            return if (numeric > 10_000_000_000L) numeric else numeric * 1000L
        }
        return parseRfc3339EpochMs(raw)
    }

    /**
     * Pure Kotlin Multiplatform RFC-3339 parser (`YYYY-MM-DDTHH:MM:SS(.frac)?(Z|±HH:MM)` -> epoch millis).
     */
    public fun parseRfc3339EpochMs(raw: String): Long? {
        val m = RFC3339_REGEX.matchEntire(raw.trim()) ?: return null
        val year = m.groupValues[1].toIntOrNull() ?: return null
        val month = m.groupValues[2].toIntOrNull() ?: return null
        val day = m.groupValues[3].toIntOrNull() ?: return null
        val hour = m.groupValues[4].toIntOrNull() ?: return null
        val minute = m.groupValues[5].toIntOrNull() ?: return null
        val second = m.groupValues[6].toIntOrNull() ?: return null
        if (month !in 1..12 || day !in 1..31 || hour !in 0..23 || minute !in 0..59 || second !in 0..60) return null

        val fracDigits = m.groupValues[7]
        val millis = if (fracDigits.isEmpty()) {
            0L
        } else {
            fracDigits.take(3).padEnd(3, '0').toLongOrNull() ?: 0L
        }

        val tz = m.groupValues[8]
        val tzOffsetSeconds = if (tz.equals("Z", ignoreCase = true)) {
            0L
        } else {
            val sign = if (tz.startsWith("-")) -1L else 1L
            val tzH = tz.substring(1, 3).toLongOrNull() ?: return null
            val tzM = tz.substring(4, 6).toLongOrNull() ?: return null
            sign * (tzH * 3600L + tzM * 60L)
        }

        val days = daysFromCivil(year.toLong(), month.toLong(), day.toLong())
        val totalSeconds = days * 86_400L + hour * 3600L + minute * 60L + second - tzOffsetSeconds
        return totalSeconds * 1000L + millis
    }

    // Howard Hinnant's civil-to-days algorithm (days since 1970-01-01)
    private fun daysFromCivil(year: Long, month: Long, day: Long): Long {
        val y = if (month <= 2) year - 1 else year
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val m = month + if (month > 2) -3 else 9
        val doy = (153 * m + 2) / 5 + day - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public fun formatRelativeTimeLabel(timestampEpochMs: Long?, nowEpochMs: Long = currentTimeMillis()): String {
        if (timestampEpochMs == null || timestampEpochMs <= 0L) return "now"
        val deltaSec = max(0L, (nowEpochMs - timestampEpochMs) / 1000L)
        return when {
            deltaSec < 60L -> "now"
            deltaSec < 3_600L -> "${deltaSec / 60L}m"
            deltaSec < 86_400L -> "${deltaSec / 3_600L}h"
            deltaSec < 172_800L -> "Yesterday"
            deltaSec < 604_800L -> "${deltaSec / 86_400L}d"
            else -> "${deltaSec / 604_800L}w"
        }
    }

    public fun buildLiveStatusSubtitle(
        status: CortexStepStatus,
        stepCount: Int,
        isUnread: Boolean,
        explicitSubtitle: String? = null,
    ): String {
        if (!explicitSubtitle.isNullOrBlank()) return explicitSubtitle.trim()
        return when (status) {
            CortexStepStatus.IN_PROGRESS -> if (stepCount > 0) "Running · Step $stepCount" else "Running..."
            CortexStepStatus.PENDING -> "Queued · Waiting to start"
            CortexStepStatus.WAITING, CortexStepStatus.BLOCKED -> "Needs review · Waiting on you"
            CortexStepStatus.ERROR -> if (stepCount > 0) "Error · Step $stepCount" else "Error"
            CortexStepStatus.CANCELLED -> if (stepCount > 0) "Stopped · $stepCount steps" else "Stopped"
            CortexStepStatus.DONE -> when {
                isUnread -> if (stepCount > 0) "Done · New reply · $stepCount steps" else "Done · New reply"
                else -> if (stepCount > 0) "Done · $stepCount steps" else "Done"
            }
            CortexStepStatus.UNSPECIFIED -> when {
                isUnread -> if (stepCount > 0) "New reply · $stepCount steps" else "New reply"
                else -> if (stepCount > 0) "Idle · $stepCount steps" else "Idle"
            }
        }
    }

    private fun resolveStepType(el: JsonElement?): CortexStepType {
        val prim = el as? JsonPrimitive ?: return CortexStepType.UNSPECIFIED
        prim.intOrNull?.let { return ProtobufStepCodec.decodeStepType(it) }
        val raw = prim.contentOrNull?.trim()?.uppercase() ?: return CortexStepType.UNSPECIFIED
        if (raw.isEmpty()) return CortexStepType.UNSPECIFIED
        CortexStepType.entries.firstOrNull { it.jsonName == raw || it.name == raw }?.let { return it }
        return when {
            raw.contains("USER_INPUT") -> CortexStepType.USER_INPUT
            raw.contains("PLANNER_RESPONSE") -> CortexStepType.PLANNER_RESPONSE
            raw.contains("NOTIFY_USER") -> CortexStepType.NOTIFY_USER
            raw.contains("RUN_COMMAND") || raw.contains("SHELL") -> CortexStepType.RUN_COMMAND
            raw.contains("CODE_ACTION") || raw.contains("REPLACE_FILE") || raw.contains("WRITE_TO_FILE") -> CortexStepType.CODE_ACTION
            raw.contains("VIEW_FILE") -> CortexStepType.VIEW_FILE
            raw.contains("LIST_DIR") -> CortexStepType.LIST_DIRECTORY
            raw.contains("SEARCH") || raw.contains("GREP") || raw.contains("FIND") -> CortexStepType.SEARCH
            raw.contains("TASK_BOUNDARY") -> CortexStepType.TASK_BOUNDARY
            raw.contains("SUBAGENT") -> CortexStepType.SUBAGENT_INVOCATION
            raw.contains("DYNAMIC_WORKFLOW") -> CortexStepType.DYNAMIC_WORKFLOW
            raw.contains("SWARM") -> CortexStepType.SWARM_BOARD
            raw.contains("MCP") -> CortexStepType.MCP_TOOL_CALL
            raw.contains("ASK_QUESTION") || raw.contains("COMMAND_STATUS") -> CortexStepType.COMMAND_STATUS
            else -> CortexStepType.UNSPECIFIED
        }
    }

    private fun resolveStepStatus(el: JsonElement?): CortexStepStatus {
        val prim = el as? JsonPrimitive ?: return CortexStepStatus.DONE
        prim.intOrNull?.let { return ProtobufStepCodec.decodeStepStatus(it) }
        val raw = prim.contentOrNull?.trim()
        return if (!raw.isNullOrEmpty()) CortexStepStatus.fromJsonName(raw) else CortexStepStatus.DONE
    }

    private fun selectPrimaryWorkspaceObject(workspaces: List<JsonObject>): JsonObject? {
        if (workspaces.isEmpty()) return null
        for (entry in workspaces) {
            val raw = (entry.str("workspaceFolderAbsoluteUri") ?: entry.str("workspaceUri") ?: "").trim()
            if (AntigravityCloudDetector.isGenericContainerUri(raw)) continue
            val lower = raw.lowercase()
            if (lower.startsWith("cloud://") ||
                lower.startsWith("vscode-remote://") ||
                lower.startsWith("vscode-vfs://") ||
                lower.startsWith("https://github.com/")
            ) {
                return entry
            }
        }
        return workspaces.firstOrNull { entry ->
            val raw = (entry.str("workspaceFolderAbsoluteUri") ?: entry.str("workspaceUri") ?: "").trim()
            raw.isNotEmpty() && !AntigravityCloudDetector.isGenericContainerUri(raw)
        }
    }

    private fun extractWorkspaceDisplayName(uri: String): String {
        val trimmed = uri.trim()
        if (trimmed.startsWith("cloud://", ignoreCase = true)) {
            val tail = trimmed.drop("cloud://".length).trim('/')
            return tail.substringAfterLast('/').ifEmpty { tail }
        }
        val clean = ResolvedEmbedResource.normalizePath(trimmed).trimEnd('/')
        return clean.substringAfterLast('/').ifEmpty { clean }
    }

    private fun parseDurationSeconds(el: JsonElement?): Double? {
        val prim = el as? JsonPrimitive ?: return null
        prim.doubleOrNull?.let { return it }
        val raw = prim.contentOrNull?.trim()?.removeSuffix("s") ?: return null
        return raw.toDoubleOrNull()
    }

    private fun nonEmpty(value: String?): String? =
        value?.trim()?.takeIf { it.isNotEmpty() }

    private fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.int(key: String): Int? =
        (this[key] as? JsonPrimitive)?.let { it.intOrNull ?: it.contentOrNull?.toIntOrNull() }
    private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
    private fun JsonObject.arr(key: String): JsonArray? = this[key] as? JsonArray

    private val RFC3339_REGEX = Regex(
        """^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?([Zz]|[+-]\d{2}:\d{2})$"""
    )
}
