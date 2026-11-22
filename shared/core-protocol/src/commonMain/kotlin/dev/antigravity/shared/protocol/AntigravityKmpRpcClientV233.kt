package dev.antigravity.shared.protocol

import dev.antigravity.shared.model.ArtifactKind
import dev.antigravity.shared.model.ArtifactSnapshot
import dev.antigravity.shared.model.AutomationItem
import dev.antigravity.shared.model.AutomationSectionKind
import dev.antigravity.shared.model.BackgroundTaskItem
import dev.antigravity.shared.model.CascadeExecutionMode
import dev.antigravity.shared.model.CascadeModelConfig
import dev.antigravity.shared.model.CascadeSummary
import dev.antigravity.shared.model.ConversationGoalItem
import dev.antigravity.shared.model.ConversationOverviewSnapshot
import dev.antigravity.shared.model.CortexStepStatus
import dev.antigravity.shared.model.CustomizationsCatalog
import dev.antigravity.shared.model.DiffCompareMode
import dev.antigravity.shared.model.DiffLine
import dev.antigravity.shared.model.DiffLineComment
import dev.antigravity.shared.model.EmbedResourceSource
import dev.antigravity.shared.model.FilePatchDiff
import dev.antigravity.shared.model.GitCommitDraft
import dev.antigravity.shared.model.GitCommitResult
import dev.antigravity.shared.model.GitFileStatusLetter
import dev.antigravity.shared.model.GitHubPullRequestInfo
import dev.antigravity.shared.model.GitHubRepoItem
import dev.antigravity.shared.model.LifecycleHookItem
import dev.antigravity.shared.model.McpServerStatusItem
import dev.antigravity.shared.model.ModelUsageQuota
import dev.antigravity.shared.model.PlanInlineComment
import dev.antigravity.shared.model.PluginCatalogItem
import dev.antigravity.shared.model.ProjectRuntimeTarget
import dev.antigravity.shared.model.ProjectWorkspace
import dev.antigravity.shared.model.ResolvedEmbedResource
import dev.antigravity.shared.model.RuleSummary
import dev.antigravity.shared.model.SkillSummary
import dev.antigravity.shared.model.SubagentPayload
import dev.antigravity.shared.model.ThinkingEffortLevel
import dev.antigravity.shared.model.decodeResilientEnumOrDefault
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import kotlin.math.roundToInt

/**
 * Pure Kotlin Multiplatform JSON codecs & payload builders backing Antigravity 2.0 (v2.33)
 * RPCs on [AntigravityKmpRpcClient] (Model catalog, Artifacts, Plan/Turn Diff Review, Git VCS,
 * Conversation Overview, Side Questions, Customizations, Search, Cloud Projects & Automations).
 */
internal object V233RpcPayloadCodec {

    internal data class DecodedModelCatalogSlice(
        val models: List<CascadeModelConfig>,
        val validIds: Set<String>,
        val defaultModelId: String?,
        val quota: ModelUsageQuota?,
        val inlineAgents: List<String>,
    )

    // MARK: - Models & Dual-Pool Usage Quota

    fun parseClientModelConfigsResponse(obj: JsonObject): DecodedModelCatalogSlice? {
        val configs = obj.arr("clientModelConfigs") ?: return null
        if (configs.isEmpty()) return null

        val quota = (obj.obj("usageQuota") ?: obj.obj("quotaSummary"))?.let { parseUsageQuota(it) }
        val inlineAgents = obj.arr("agents")
            ?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { s -> s.isNotEmpty() } }
            ?: emptyList()

        val parsedModels = mutableListOf<CascadeModelConfig>()
        val validIds = linkedSetOf<String>()
        var defaultModelId: String? = nonEmpty(obj.str("defaultModel"))?.takeIf { it != "MODEL_UNSPECIFIED" }

        for (entry in configs) {
            val cfg = entry as? JsonObject ?: continue
            if (cfg.bool("disabled") == true) continue
            val label = nonEmpty(cfg.str("label")) ?: continue
            val moa = cfg.obj("modelOrAlias")
            val rawModel = nonEmpty(moa?.str("model"))
            val rawAlias = nonEmpty(moa?.str("alias"))
            val isAlias = (rawModel == null || rawModel == "MODEL_UNSPECIFIED") && rawAlias != null
            val modelId = (if (isAlias) rawAlias else rawModel) ?: continue
            if (modelId == "MODEL_UNSPECIFIED" || !validIds.add(modelId)) continue

            val lowerLabel = label.lowercase()
            val isOrchestrator = (cfg.bool("isOrchestrator") == true) || lowerLabel.contains("orchestrator")
            val supportsThinking = (cfg.bool("supportsThoughtCirculation") == true) ||
                (cfg.bool("supportsThinking") == true) ||
                lowerLabel.contains("thinking") ||
                lowerLabel.contains("neon") ||
                lowerLabel.contains("carbon") ||
                lowerLabel.contains("argon") ||
                lowerLabel.contains("hydrogen") ||
                lowerLabel.contains("pro") ||
                lowerLabel.contains("opus")

            val supportedEfforts = parseSupportedEfforts(
                rawEfforts = cfg.arr("supportedEfforts"),
                isOrchestrator = isOrchestrator,
                lowerLabel = lowerLabel,
            )
            val effort = inferDefaultEffort(lowerLabel)
            val rawTag = nonEmpty(cfg.str("tagTitle"))
            val rawDesc = nonEmpty(cfg.str("description"))
            val cleanDesc = rawDesc?.takeUnless { CascadeModelConfig.isGenericBadgeLabel(it) }
            val badgeTitle = rawTag ?: if (rawDesc != null && cleanDesc == null) rawDesc else null
            val baseSubtitle = cleanDesc ?: CascadeModelConfig.descriptiveSubtitle(label)
            val remFrac = cfg.obj("quotaInfo")?.dbl("remainingFraction")
            val desc = if (remFrac != null && remFrac < 0.99) {
                val pct = (remFrac * 100.0).roundToInt().coerceIn(0, 100)
                val suffix = if (pct == 0) "Quota exhausted" else "$pct% quota left"
                "$baseSubtitle · $suffix"
            } else {
                baseSubtitle
            }
            val isNew = (cfg.bool("isNew") == true) || lowerLabel.contains("gemini 4") || isOrchestrator
            val isRecommended = cfg.bool("isRecommended") == true
            if (isRecommended && defaultModelId == null) {
                defaultModelId = modelId
            }

            parsedModels.add(
                CascadeModelConfig(
                    modelId = modelId,
                    displayName = label,
                    subtitle = desc,
                    mode = CascadeExecutionMode.PLANNING,
                    supportsThinking = supportsThinking,
                    isThinkingEnabled = supportsThinking,
                    thinkingEffort = effort,
                    badgeTag = badgeTitle ?: if (isNew) "New" else null,
                    agentPersona = "Default",
                    isDefault = isRecommended || modelId == defaultModelId,
                    isOrchestrator = isOrchestrator,
                    plannerModelName = nonEmpty(cfg.str("plannerModelName")),
                    executorModelName = nonEmpty(cfg.str("executorModelName")),
                    supportedEfforts = supportedEfforts,
                    isNewBadge = isNew,
                    requiresUpgradeNote = nonEmpty(cfg.str("upgradeNote")),
                    isModelAlias = isAlias,
                )
            )
        }

        val overrideMoa = obj.obj("defaultOverrideModelConfig")?.obj("modelOrAlias")
        val overrideModel = nonEmpty(overrideMoa?.str("model"))?.takeIf { it != "MODEL_UNSPECIFIED" }
        val overrideAlias = nonEmpty(overrideMoa?.str("alias"))
        if (overrideModel != null) {
            defaultModelId = overrideModel
        } else if (overrideAlias != null) {
            defaultModelId = overrideAlias
        }

        return DecodedModelCatalogSlice(
            models = parsedModels,
            validIds = validIds,
            defaultModelId = defaultModelId,
            quota = quota,
            inlineAgents = inlineAgents,
        )
    }

    fun parseAvailableModelsResponse(wrapper: JsonObject): DecodedModelCatalogSlice {
        val resp = wrapper.obj("response") ?: wrapper
        val quota = resp.obj("usageQuota")?.let { parseUsageQuota(it) }
        val modelsMap = resp.obj("models")
        if (modelsMap == null || modelsMap.isEmpty()) {
            return DecodedModelCatalogSlice(emptyList(), emptySet(), null, quota, emptyList())
        }

        val orderedKeys = mutableListOf<String>()
        val sorts = resp.arr("agentModelSorts") ?: resp.arr("battleModeModelSorts") ?: JsonArray(emptyList())
        for (sortEl in sorts) {
            val sortObj = sortEl as? JsonObject ?: continue
            for (grpEl in sortObj.arr("groups") ?: JsonArray(emptyList())) {
                val grpObj = grpEl as? JsonObject ?: continue
                for (midEl in grpObj.arr("modelIds") ?: JsonArray(emptyList())) {
                    val mid = nonEmpty((midEl as? JsonPrimitive)?.contentOrNull) ?: continue
                    if (mid !in orderedKeys) orderedKeys.add(mid)
                }
            }
        }
        if (orderedKeys.isEmpty()) {
            orderedKeys.addAll(modelsMap.keys.sorted())
        }

        val parsedModels = mutableListOf<CascadeModelConfig>()
        val validIds = linkedSetOf<String>()
        for (key in orderedKeys) {
            val details = modelsMap.obj(key) ?: continue
            if (details.bool("disabled") == true || details.bool("isInternal") == true) continue
            val displayName = nonEmpty(details.str("displayName")) ?: key
            val protoEnum = nonEmpty(details.str("model"))
            val modelId = if (protoEnum != null && protoEnum != "MODEL_UNSPECIFIED") protoEnum else key
            if (!validIds.add(modelId)) continue

            val lowerLabel = displayName.lowercase()
            val isOrchestrator = (details.bool("isOrchestrator") == true) || lowerLabel.contains("orchestrator")
            val supportsThinking = (details.bool("supportsThinking") == true) ||
                lowerLabel.contains("thinking") ||
                lowerLabel.contains("neon")
            val supportedEfforts = parseSupportedEfforts(
                rawEfforts = details.arr("supportedEfforts"),
                isOrchestrator = isOrchestrator,
                lowerLabel = lowerLabel,
            )
            val effort = inferDefaultEffort(lowerLabel)
            val rawTag = nonEmpty(details.str("tagTitle")) ?: nonEmpty(details.str("badge"))
            val rawDesc = nonEmpty(details.str("description"))
            val cleanDesc = rawDesc?.takeUnless { CascadeModelConfig.isGenericBadgeLabel(it) }
            val badgeTitle = rawTag ?: if (rawDesc != null && cleanDesc == null) rawDesc else null
            val subtitle = cleanDesc ?: CascadeModelConfig.descriptiveSubtitle(displayName)
            val isNew = lowerLabel.contains("gemini 4") || isOrchestrator

            parsedModels.add(
                CascadeModelConfig(
                    modelId = modelId,
                    displayName = displayName,
                    subtitle = subtitle,
                    mode = CascadeExecutionMode.PLANNING,
                    supportsThinking = supportsThinking,
                    isThinkingEnabled = supportsThinking,
                    thinkingEffort = effort,
                    badgeTag = badgeTitle ?: if (isNew) "New" else null,
                    agentPersona = "Default",
                    isDefault = parsedModels.isEmpty(),
                    isOrchestrator = isOrchestrator,
                    supportedEfforts = supportedEfforts,
                    isNewBadge = isNew,
                    isModelAlias = !modelId.startsWith("MODEL_"),
                )
            )
        }
        return DecodedModelCatalogSlice(
            models = parsedModels,
            validIds = validIds,
            defaultModelId = parsedModels.firstOrNull()?.modelId,
            quota = quota,
            inlineAgents = emptyList(),
        )
    }

    fun parseUsageQuota(obj: JsonObject): ModelUsageQuota {
        val geminiWeekly = (obj.dbl("geminiWeeklyRemaining") ?: 0.85).coerceIn(0.0, 1.0)
        val geminiFiveHour = (obj.dbl("geminiFiveHourRemaining") ?: 0.92).coerceIn(0.0, 1.0)
        val partnerWeekly = (obj.dbl("partnerWeeklyRemaining") ?: 0.70).coerceIn(0.0, 1.0)
        val partnerFiveHour = (obj.dbl("partnerFiveHourRemaining") ?: 0.80).coerceIn(0.0, 1.0)
        val overages = obj.bool("aiCreditOveragesEnabled") ?: obj.bool("hasExtraCredits") ?: false
        val planName = nonEmpty(obj.str("planDisplayName"))
            ?: nonEmpty(obj.str("planTier"))
            ?: "Google AI Ultra"
        val usedPct = ((1.0 - geminiWeekly) * 100.0).coerceIn(0.0, 100.0)
        return ModelUsageQuota(
            planTierLabel = planName,
            usedPercent = usedPct,
            refreshCountdownLabel = nonEmpty(obj.str("refreshCountdownLabel")) ?: "",
            creditsRemaining = obj.int("creditsRemaining"),
            isQuotaWarning = geminiWeekly < 0.15 || geminiFiveHour < 0.15,
            updatedAtEpochMs = currentTimeMillis(),
            geminiWeeklyRemaining = geminiWeekly,
            geminiFiveHourRemaining = geminiFiveHour,
            partnerWeeklyRemaining = partnerWeekly,
            partnerFiveHourRemaining = partnerFiveHour,
            aiCreditOveragesEnabled = overages,
        )
    }

    fun parseCustomAgentNames(obj: JsonObject): List<String> {
        val rawAgents = obj.arr("customAgentConfigs")
            ?: obj.arr("agents")
            ?: obj.arr("configs")
            ?: return emptyList()
        val names = mutableListOf<String>()
        for (item in rawAgents) {
            val name = when (item) {
                is JsonPrimitive -> nonEmpty(item.contentOrNull)
                is JsonObject -> nonEmpty(item.str("name"))
                    ?: nonEmpty(item.str("displayName"))
                    ?: nonEmpty(item.str("id"))
                else -> null
            }
            if (name != null && name !in names) {
                names.add(name)
            }
        }
        return names
    }

    private fun parseSupportedEfforts(
        rawEfforts: JsonArray?,
        isOrchestrator: Boolean,
        lowerLabel: String,
    ): List<ThinkingEffortLevel> {
        if (isOrchestrator) return emptyList()
        if (rawEfforts != null) {
            val mapped = rawEfforts.mapNotNull { el ->
                val raw = (el as? JsonPrimitive)?.contentOrNull?.trim()?.lowercase() ?: return@mapNotNull null
                when (raw) {
                    "xhigh", "extra", "x-high" -> ThinkingEffortLevel.EXTRA
                    "high" -> ThinkingEffortLevel.HIGH
                    "medium", "med" -> ThinkingEffortLevel.MEDIUM
                    "low", "minimal" -> ThinkingEffortLevel.LOW
                    else -> null
                }
            }
            if (mapped.isNotEmpty()) return mapped
        }
        return if (lowerLabel.contains("neon") || lowerLabel.contains("hydrogen")) {
            listOf(
                ThinkingEffortLevel.LOW,
                ThinkingEffortLevel.MEDIUM,
                ThinkingEffortLevel.HIGH,
                ThinkingEffortLevel.EXTRA,
            )
        } else {
            listOf(ThinkingEffortLevel.LOW, ThinkingEffortLevel.MEDIUM, ThinkingEffortLevel.HIGH)
        }
    }

    private fun inferDefaultEffort(lowerLabel: String): ThinkingEffortLevel = when {
        lowerLabel.contains("(xhigh)") || lowerLabel.contains("(x-high)") || lowerLabel.contains("(extra") ->
            ThinkingEffortLevel.EXTRA
        lowerLabel.contains("(low)") || lowerLabel.contains("(minimal)") -> ThinkingEffortLevel.LOW
        lowerLabel.contains("(medium)") || lowerLabel.contains("(med)") || lowerLabel.contains("flash") ->
            ThinkingEffortLevel.MEDIUM
        else -> ThinkingEffortLevel.HIGH
    }

    // MARK: - Artifacts & Plan Review

    fun parseArtifactSnapshots(res: JsonObject, nowEpochMs: Long = currentTimeMillis()): List<ArtifactSnapshot> {
        val arr = res.arr("artifacts")
            ?: res.arr("artifactSnapshots")
            ?: res.arr("snapshots")
            ?: return emptyList()

        return arr.mapNotNull { item ->
            val obj = item as? JsonObject ?: return@mapNotNull null
            val path = nonEmpty(obj.str("artifactPath"))
                ?: nonEmpty(obj.str("path"))
                ?: nonEmpty(obj.str("fileUri"))
                ?: nonEmpty(obj.str("uri"))
                ?: return@mapNotNull null

            val rawKindStr = nonEmpty(obj.str("kind"))
            val (kind, rawKindName) = resolveArtifactKind(rawKindStr, path)
            val content = obj.str("content")
                ?: obj.str("textContent")
                ?: obj.str("body")
                ?: ""
            val title = nonEmpty(obj.str("title")) ?: pathBaseName(path)

            ArtifactSnapshot(
                artifactPath = path,
                title = title,
                summary = obj.str("summary") ?: "",
                kind = kind,
                content = content,
                requestFeedback = obj.bool("requestFeedback") ?: false,
                userFacing = obj.bool("userFacing") ?: true,
                version = obj.int("version") ?: 1,
                updatedAtEpochMs = nowEpochMs,
                rawKindName = rawKindName,
            )
        }
    }

    private fun resolveArtifactKind(rawKindStr: String?, path: String): Pair<ArtifactKind, String?> {
        if (rawKindStr != null) {
            val parsed = decodeResilientEnumOrDefault(
                raw = rawKindStr,
                values = ArtifactKind.entries,
                fallback = ArtifactKind.UNKNOWN,
            )
            return parsed to (if (parsed == ArtifactKind.UNKNOWN) rawKindStr else null)
        }
        val lower = path.lowercase()
        val ext = pathExtension(path).lowercase()
        return when {
            lower.endsWith(".pdf") -> ArtifactKind.PDF_DOCUMENT to null
            lower.endsWith(".ipynb") -> ArtifactKind.JUPYTER_NOTEBOOK to null
            lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
                lower.endsWith(".webp") || lower.endsWith(".gif") -> ArtifactKind.IMAGE_ASSET to null
            lower.endsWith(".mp4") || lower.endsWith(".mov") || lower.endsWith(".webm") ->
                ArtifactKind.VIDEO_ASSET to null
            lower.endsWith(".html") || lower.endsWith(".htm") -> ArtifactKind.GENERATIVE_UI_HTML to null
            lower.endsWith(".url.json") -> ArtifactKind.URL_BOOKMARK to null
            lower.contains("walkthrough") && (ext.isEmpty() || ext == "md" || ext == "markdown" || ext == "txt") ->
                ArtifactKind.WALKTHROUGH to null
            lower.contains("task") && (ext.isEmpty() || ext == "md" || ext == "markdown" || ext == "txt") ->
                ArtifactKind.TASK_LIST to null
            ext.isEmpty() || ext == "md" || ext == "markdown" || ext == "txt" ->
                ArtifactKind.IMPLEMENTATION_PLAN to null
            else -> ArtifactKind.UNKNOWN to ext.uppercase().takeIf { it.isNotEmpty() }
        }
    }

    fun parseReadArtifactFileResponse(
        uri: String,
        normalizedTarget: String,
        res: JsonObject,
    ): ResolvedEmbedResource? {
        if (res.bool("ok") == false) return null
        val rawContent = nonEmpty(res.str("content")) ?: return null
        val mime = nonEmpty(res.str("mimeType")) ?: ResolvedEmbedResource.inferredMimeType(uri)
        val encoding = (res.str("encoding") ?: "utf-8").lowercase()
        return if (encoding == "base64") {
            val bytes = CloudRelayJspbCodec.decodeBase64Flexible(rawContent) ?: return null
            val text = if (mime.lowercase().startsWith("text/") || mime.lowercase().contains("svg")) {
                bytes.decodeToString()
            } else {
                null
            }
            ResolvedEmbedResource(
                uri = uri,
                normalizedPath = normalizedTarget,
                mimeType = mime,
                textContent = text,
                binaryData = bytes,
                source = EmbedResourceSource.REMOTE_HOST,
            )
        } else {
            ResolvedEmbedResource(
                uri = uri,
                normalizedPath = normalizedTarget,
                mimeType = mime,
                textContent = rawContent,
                binaryData = rawContent.encodeToByteArray(),
                source = EmbedResourceSource.REMOTE_HOST,
            )
        }
    }

    fun encodePlanReviewCommentsBody(cascadeId: String, comments: List<PlanInlineComment>): JsonObject =
        buildJsonObject {
            put("cascadeId", cascadeId)
            put(
                "comments",
                buildJsonArray {
                    for (c in comments) {
                        add(
                            buildJsonObject {
                                put("id", c.id)
                                put("targetFilePath", c.targetFilePath)
                                put("quotedSpan", c.quotedSpan)
                                put("body", c.body)
                            }
                        )
                    }
                },
            )
        }

    // MARK: - Turn Diff Review & Git VCS

    fun parseFilePatchDiffs(
        response: JsonObject,
        defaultTurn: Int = 1,
        defaultScope: DiffCompareMode = DiffCompareMode.TURN,
    ): List<FilePatchDiff> {
        val rawFiles = response.arr("files") ?: response.arr("diffs") ?: return emptyList()
        return rawFiles.mapNotNull { entry ->
            val obj = entry as? JsonObject ?: return@mapNotNull null
            val path = nonEmpty(obj.str("filePath")) ?: nonEmpty(obj.str("path")) ?: return@mapNotNull null
            val turn = obj.int("turnNumber") ?: defaultTurn
            val rawStatus = (obj.str("statusLetter") ?: obj.str("status") ?: "M").trim().uppercase()
            val statusLetter = GitFileStatusLetter.entries.firstOrNull {
                it.code == rawStatus || it.name.equals(rawStatus, ignoreCase = true)
            } ?: GitFileStatusLetter.MODIFIED
            val isStaged = obj.bool("isStaged") ?: false
            val isReviewed = obj.bool("isReviewed") ?: false
            val rawScope = obj.str("compareScope")
            val scope = if (!rawScope.isNullOrBlank()) {
                decodeResilientEnumOrDefault(
                    raw = rawScope,
                    values = DiffCompareMode.entries,
                    fallback = defaultScope,
                    extraMatcher = { r ->
                        when (r.trim().lowercase()) {
                            "per turn", "this turn", "turn" -> DiffCompareMode.TURN
                            "uncommitted", "working tree" -> DiffCompareMode.WORKING_TREE
                            "staged", "agent edits" -> DiffCompareMode.STAGED
                            "branch", "vs base branch" -> DiffCompareMode.BRANCH_BASE
                            else -> null
                        }
                    },
                )
            } else {
                defaultScope
            }
            val hunkHeader = obj.str("hunkHeader") ?: "@@ -1,1 +1,1 @@"

            val parsedLines = mutableListOf<DiffLine>()
            val rawLines = obj.arr("lines")
            val rawHunks = obj.arr("hunks")
            val rawPatch = obj.str("patch") ?: obj.str("unifiedDiff")

            when {
                rawLines != null -> {
                    rawLines.forEachIndexed { idx, lineVal ->
                        val lObj = lineVal as? JsonObject ?: return@forEachIndexed
                        val lineKind = parseDiffLineKind(lObj.str("kind"))
                        parsedLines.add(
                            DiffLine(
                                id = lObj.int("id") ?: idx,
                                kind = lineKind,
                                oldLineNumber = lObj.int("oldLineNumber"),
                                newLineNumber = lObj.int("newLineNumber"),
                                text = lObj.str("text") ?: "",
                                wordHighlightRange = lObj.str("wordHighlightRange"),
                            )
                        )
                    }
                }
                rawHunks != null -> {
                    var runningId = 0
                    for (hVal in rawHunks) {
                        val hObj = hVal as? JsonObject ?: continue
                        nonEmpty(hObj.str("header"))?.let { hdr ->
                            parsedLines.add(DiffLine(id = runningId++, kind = DiffLine.Kind.HUNK_HEADER, text = hdr))
                        }
                        for (lineVal in hObj.arr("lines") ?: JsonArray(emptyList())) {
                            val lObj = lineVal as? JsonObject ?: continue
                            val lineKind = parseDiffLineKind(lObj.str("kind"))
                            parsedLines.add(
                                DiffLine(
                                    id = runningId++,
                                    kind = lineKind,
                                    oldLineNumber = lObj.int("oldLineNumber"),
                                    newLineNumber = lObj.int("newLineNumber"),
                                    text = lObj.str("text") ?: "",
                                )
                            )
                        }
                    }
                }
                rawPatch != null -> {
                    parsedLines.addAll(parseUnifiedDiffText(rawPatch))
                }
            }

            val additions = obj.int("additions") ?: parsedLines.count { it.kind == DiffLine.Kind.ADDITION }
            val deletions = obj.int("deletions") ?: parsedLines.count { it.kind == DiffLine.Kind.DELETION }

            FilePatchDiff(
                turnNumber = turn,
                filePath = path,
                additions = additions,
                deletions = deletions,
                hunkHeader = hunkHeader,
                isReviewed = isReviewed,
                statusLetter = statusLetter,
                isStaged = isStaged,
                compareScope = scope,
                lines = parsedLines,
            )
        }
    }

    fun parseUnifiedDiffText(unifiedDiff: String): List<DiffLine> {
        val result = mutableListOf<DiffLine>()
        var oldNum = 1
        var newNum = 1
        unifiedDiff.split('\n').forEachIndexed { idx, rawLine ->
            when {
                rawLine.startsWith("@@") -> {
                    result.add(DiffLine(id = idx, kind = DiffLine.Kind.HUNK_HEADER, text = rawLine))
                }
                rawLine.startsWith("+") && !rawLine.startsWith("+++") -> {
                    result.add(
                        DiffLine(
                            id = idx,
                            kind = DiffLine.Kind.ADDITION,
                            oldLineNumber = null,
                            newLineNumber = newNum++,
                            text = rawLine.drop(1),
                        )
                    )
                }
                rawLine.startsWith("-") && !rawLine.startsWith("---") -> {
                    result.add(
                        DiffLine(
                            id = idx,
                            kind = DiffLine.Kind.DELETION,
                            oldLineNumber = oldNum++,
                            newLineNumber = null,
                            text = rawLine.drop(1),
                        )
                    )
                }
                !rawLine.startsWith("---") && !rawLine.startsWith("+++") -> {
                    val content = if (rawLine.startsWith(" ")) rawLine.drop(1) else rawLine
                    result.add(
                        DiffLine(
                            id = idx,
                            kind = DiffLine.Kind.CONTEXT,
                            oldLineNumber = oldNum++,
                            newLineNumber = newNum++,
                            text = content,
                        )
                    )
                }
            }
        }
        return result
    }

    private fun parseDiffLineKind(raw: String?): DiffLine.Kind = when (raw?.trim()?.lowercase()) {
        "addition", "add", "+" -> DiffLine.Kind.ADDITION
        "deletion", "del", "-" -> DiffLine.Kind.DELETION
        "hunkheader", "hunk_header", "hunk" -> DiffLine.Kind.HUNK_HEADER
        else -> DiffLine.Kind.CONTEXT
    }

    fun encodeDiffReviewCommentsBody(cascadeId: String, comments: List<DiffLineComment>): JsonObject =
        buildJsonObject {
            put("cascadeId", cascadeId)
            put(
                "comments",
                buildJsonArray {
                    for (c in comments) {
                        add(
                            buildJsonObject {
                                put("id", c.id)
                                put("filePath", c.filePath)
                                put("lineNumber", c.lineNumber)
                                put("body", c.body)
                            }
                        )
                    }
                },
            )
        }

    fun parseGitCommitResult(res: JsonObject, draft: GitCommitDraft): GitCommitResult {
        val sha = nonEmpty(res.str("commitSha"))
            ?: nonEmpty(res.str("commitHash"))
            ?: AntigravityKmpRpcClient.randomUuidV4().take(7)
        val message = nonEmpty(res.str("commitMessage"))
            ?: nonEmpty(res.str("summary"))
            ?: draft.message
        val branch = nonEmpty(res.str("branchName")) ?: "main"
        val pushed = res.bool("pushed") ?: false
        return GitCommitResult(
            commitHash = sha,
            summary = message,
            pushed = pushed,
            branchName = branch,
        )
    }

    // MARK: - Conversation Overview & Customizations & Search

    fun parseConversationOverview(res: JsonObject): ConversationOverviewSnapshot {
        val subagents = (res.arr("subagents") ?: res.arr("activeSubagents") ?: JsonArray(emptyList()))
            .mapIndexedNotNull { idx, el ->
                val obj = el as? JsonObject ?: return@mapIndexedNotNull null
                SubagentPayload(
                    subagentId = nonEmpty(obj.str("subagentId")) ?: nonEmpty(obj.str("id")) ?: "sub-$idx",
                    role = nonEmpty(obj.str("role")) ?: "Subagent",
                    typeName = nonEmpty(obj.str("typeName")) ?: "self",
                    modelLabel = nonEmpty(obj.str("modelLabel")) ?: "Gemini 4 Hydrogen",
                    status = CortexStepStatus.fromJsonName(obj.str("status") ?: "IN_PROGRESS"),
                    summary = obj.str("summary") ?: "",
                    waitingApprovalTitle = nonEmpty(obj.str("waitingApprovalTitle")),
                )
            }

        val bgTasks = (res.arr("backgroundTasks") ?: JsonArray(emptyList()))
            .mapIndexedNotNull { idx, el ->
                val obj = el as? JsonObject ?: return@mapIndexedNotNull null
                BackgroundTaskItem(
                    id = nonEmpty(obj.str("id")) ?: "bg-$idx",
                    title = nonEmpty(obj.str("title")) ?: "Background Task",
                    commandOrKind = nonEmpty(obj.str("commandSummary")) ?: nonEmpty(obj.str("commandOrKind")) ?: "",
                    status = CortexStepStatus.fromJsonName(obj.str("status") ?: "IN_PROGRESS"),
                    elapsedLabel = obj.str("elapsedLabel") ?: "running",
                )
            }

        val goals = (res.arr("goals") ?: JsonArray(emptyList()))
            .mapIndexedNotNull { idx, el ->
                val obj = el as? JsonObject ?: return@mapIndexedNotNull null
                val status = CortexStepStatus.fromJsonName(obj.str("status") ?: "IN_PROGRESS")
                ConversationGoalItem(
                    id = nonEmpty(obj.str("id")) ?: "goal-$idx",
                    title = nonEmpty(obj.str("title")) ?: "Goal",
                    isCompleted = obj.bool("isCompleted") ?: (status == CortexStepStatus.DONE),
                )
            }

        val prs = (res.arr("pullRequests") ?: res.arr("linkedPullRequests") ?: JsonArray(emptyList()))
            .mapNotNull { el ->
                val obj = el as? JsonObject ?: return@mapNotNull null
                val number = obj.int("number") ?: return@mapNotNull null
                val repo = nonEmpty(obj.str("ownerRepo"))
                val url = nonEmpty(obj.str("url"))
                    ?: if (repo != null) "https://github.com/$repo/pull/$number" else return@mapNotNull null
                GitHubPullRequestInfo(
                    number = number,
                    title = nonEmpty(obj.str("title")) ?: "PR #$number",
                    url = url,
                    state = (obj.str("state") ?: "OPEN").uppercase(),
                    checksStatus = nonEmpty(obj.str("checksSummary")) ?: nonEmpty(obj.str("checksStatus")) ?: "PASSING",
                )
            }

        val modifiedFiles = (res.arr("modifiedFiles") ?: JsonArray(emptyList()))
            .mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.takeIf { s -> s.isNotEmpty() } }
        val docLinks = (res.arr("documentLinks") ?: JsonArray(emptyList()))
            .mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.takeIf { s -> s.isNotEmpty() } }
        val changedCount = res.int("changedFilesCount") ?: modifiedFiles.size
        val additions = res.int("reviewAdditions") ?: res.int("totalAdditions") ?: 0
        val deletions = res.int("reviewDeletions") ?: res.int("totalDeletions") ?: 0

        return ConversationOverviewSnapshot(
            goals = goals,
            activeSubagents = subagents,
            backgroundTasks = bgTasks,
            linkedPullRequests = prs,
            changedFilesCount = changedCount,
            totalAdditions = additions,
            totalDeletions = deletions,
            modifiedFiles = modifiedFiles,
            artifacts = emptyList(),
            documentLinks = docLinks,
        )
    }

    fun parseCustomizationsCatalog(res: JsonObject): CustomizationsCatalog {
        val skills = (res.arr("skills") ?: JsonArray(emptyList())).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val name = nonEmpty(obj.str("name")) ?: return@mapNotNull null
            SkillSummary(
                name = name,
                description = obj.str("description") ?: "",
                scope = nonEmpty(obj.str("scope")) ?: "Workspace",
                isEnabled = obj.bool("isEnabled") ?: true,
            )
        }
        val rules = (res.arr("rules") ?: JsonArray(emptyList())).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val name = nonEmpty(obj.str("name")) ?: return@mapNotNull null
            RuleSummary(
                name = name,
                scope = nonEmpty(obj.str("scope")) ?: "Workspace",
                preview = obj.str("preview") ?: "",
                isActive = obj.bool("isActive") ?: true,
            )
        }
        val agents = (res.arr("customAgents") ?: JsonArray(emptyList()))
            .mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.takeIf { s -> s.isNotBlank() } }
        val servers = (res.arr("mcpServers") ?: JsonArray(emptyList())).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val name = nonEmpty(obj.str("name")) ?: return@mapNotNull null
            val stateStr = (obj.str("state") ?: "connected").lowercase()
            val isConnected = obj.bool("isConnected") ?: (stateStr == "connected")
            McpServerStatusItem(
                name = name,
                transport = nonEmpty(obj.str("transport")) ?: "stdio",
                isConnected = isConnected,
                toolCount = obj.int("toolCount") ?: 0,
                errorMessage = nonEmpty(obj.str("errorMessage")),
                missingCommandHint = nonEmpty(obj.str("missingCommandHint")),
                oauthConnected = obj.bool("oauthConnected") ?: true,
            )
        }
        val plugins = (res.arr("plugins") ?: JsonArray(emptyList())).mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val id = nonEmpty(obj.str("id")) ?: return@mapNotNull null
            val name = nonEmpty(obj.str("name")) ?: return@mapNotNull null
            PluginCatalogItem(
                id = id,
                name = name,
                summary = obj.str("summary") ?: obj.str("description") ?: "",
                isInstalled = obj.bool("isInstalled") ?: false,
                isEnabled = obj.bool("isEnabled") ?: true,
                provider = nonEmpty(obj.str("provider")) ?: name,
                isFeaturedPartner = obj.bool("isFeaturedPartner") ?: false,
                accountSignedIn = obj.bool("accountSignedIn") ?: false,
                mcpStartupError = nonEmpty(obj.str("mcpStartupError")),
                suggestedPrompts = (obj.arr("suggestedPrompts") ?: JsonArray(emptyList()))
                    .mapNotNull { (it as? JsonPrimitive)?.contentOrNull },
            )
        }
        val hooks = (res.arr("hooks") ?: JsonArray(emptyList())).mapIndexedNotNull { idx, el ->
            val obj = el as? JsonObject ?: return@mapIndexedNotNull null
            val event = nonEmpty(obj.str("eventName")) ?: nonEmpty(obj.str("event")) ?: return@mapIndexedNotNull null
            val command = nonEmpty(obj.str("command")) ?: return@mapIndexedNotNull null
            LifecycleHookItem(
                id = nonEmpty(obj.str("id")) ?: "hook-$idx",
                event = event,
                command = command,
                isEnabled = obj.bool("isEnabled") ?: obj.bool("isValid") ?: true,
                matcher = nonEmpty(obj.str("matcher")) ?: "*",
                timeoutSeconds = obj.int("timeoutSeconds") ?: 60,
            )
        }

        if (skills.isEmpty() && rules.isEmpty() && servers.isEmpty() && plugins.isEmpty()) {
            return CustomizationsCatalog.defaultCatalog
        }
        return CustomizationsCatalog(
            skills = skills,
            rules = rules,
            mcpServers = servers,
            plugins = plugins,
            hooks = hooks,
            customAgents = agents.ifEmpty { listOf("Default") },
        )
    }

    fun parseSearchConversations(
        res: JsonObject,
        nowEpochMs: Long = currentTimeMillis(),
        originInstanceUuid: String? = null,
        originHostName: String? = null,
    ): List<CascadeSummary> {
        val list = res.arr("trajectories") ?: res.arr("results") ?: return emptyList()
        return list.mapNotNull { el ->
            val obj = el as? JsonObject ?: return@mapNotNull null
            val id = nonEmpty(obj.str("cascadeId")) ?: return@mapNotNull null
            val title = nonEmpty(obj.str("title")) ?: return@mapNotNull null
            CascadeSummary(
                cascadeId = id,
                title = title,
                projectSlug = nonEmpty(obj.str("projectSlug")) ?: "workspace",
                workspaceUri = obj.str("workspaceUri") ?: "",
                branchName = nonEmpty(obj.str("branchName")) ?: "main",
                status = CortexStepStatus.fromJsonName(obj.str("status") ?: "DONE"),
                stepCount = obj.int("stepCount") ?: 0,
                updatedAtEpochMs = nowEpochMs,
                relativeTimeLabel = nonEmpty(obj.str("relativeTimeLabel")) ?: "now",
                statusSubtitle = nonEmpty(obj.str("snippet")) ?: nonEmpty(obj.str("statusSubtitle")) ?: "",
                originInstanceUuid = originInstanceUuid,
                originHostName = originHostName,
            )
        }
    }

    // MARK: - Cloud Projects & GitHub Repositories

    fun decodeCloudProjectObject(
        projObj: JsonObject,
        fallbackId: String,
        originInstanceUuid: String? = null,
    ): ProjectWorkspace {
        val pid = nonEmpty(projObj.str("id")) ?: fallbackId
        val name = nonEmpty(projObj.str("name")) ?: "Antigravity Cloud"
        val resources = projObj.obj("projectResources")?.arr("resources") ?: JsonArray(emptyList())
        var repoDisplay: String? = null

        for (resEntry in resources) {
            val resObj = resEntry as? JsonObject ?: continue
            val rr = resObj.obj("remoteResource")
                ?: resObj.obj("githubRepo")
                ?: resObj.obj("githubRepository")
                ?: resObj.obj("gitFolder")
                ?: continue
            val dn = listOf(
                rr.str("displayName"),
                rr.str("fullName"),
                rr.str("name"),
                rr.str("uri"),
                rr.str("folderUri"),
            ).firstNotNullOfOrNull { nonEmpty(it) }
            if (dn != null) {
                var normalized = dn
                    .removePrefix("https://github.com/")
                    .removePrefix("http://github.com/")
                    .removePrefix("cloud://")
                    .trim('/')
                if (normalized.endsWith(".git")) normalized = normalized.dropLast(4)
                if (normalized.isNotEmpty()) {
                    repoDisplay = normalized
                    break
                }
            }
        }
        if (repoDisplay == null) {
            val fallbackRepo = nonEmpty(projObj.str("repository")) ?: nonEmpty(projObj.str("repo"))
            if (fallbackRepo != null) {
                repoDisplay = fallbackRepo
                    .removePrefix("https://github.com/")
                    .removePrefix("http://github.com/")
                    .trim('/')
            }
        }
        val cloudSlug = repoDisplay ?: name
        val workspaceUri = "cloud://$cloudSlug"
        return ProjectWorkspace(
            id = pid,
            name = name,
            pathDisplay = workspaceUri,
            workspaceUri = workspaceUri,
            runtime = ProjectRuntimeTarget.CLOUD,
            hostName = "Antigravity",
            activeBranch = "main",
            cloudProjectId = pid,
            originInstanceUuid = originInstanceUuid,
        )
    }

    fun parseCloudGitHubRepos(resp: JsonObject): List<GitHubRepoItem> {
        val resources = resp.arr("resources") ?: return emptyList()
        return resources.mapNotNull { entry ->
            val obj = entry as? JsonObject ?: return@mapNotNull null
            val fullName = nonEmpty(obj.str("displayName")) ?: nonEmpty(obj.str("name")) ?: return@mapNotNull null
            val branch = nonEmpty(obj.str("defaultBranch")) ?: "main"
            GitHubRepoItem(
                id = "repo-$fullName",
                fullName = fullName,
                visibilityLabel = if (obj.bool("isPrivate") == true) "Private" else "GitHub",
                defaultBranch = branch,
            )
        }
    }

    // MARK: - Automations & Sidecar Helpers

    fun makeSidecarId(rawTitle: String): String {
        val parts = mutableListOf<String>()
        val cur = StringBuilder()
        for (ch in rawTitle.lowercase()) {
            if (ch in 'a'..'z' || ch in '0'..'9') {
                cur.append(ch)
            } else if (cur.isNotEmpty()) {
                parts.add(cur.toString())
                cur.clear()
            }
        }
        if (cur.isNotEmpty()) parts.add(cur.toString())
        val joined = parts.take(5).joinToString("-").take(36).trim('-')
        val suffix = AntigravityKmpRpcClient.randomUuidV4().take(6)
        return if (joined.isEmpty()) "auto-$suffix" else "$joined-$suffix"
    }

    fun inferCronAndScheduleLabel(prompt: String): Pair<String, String> {
        val lower = prompt.lowercase()
        return when {
            lower.contains("weekday") || lower.contains("mon-fri") -> "0 9 * * 1-5" to "Weekdays at 09:00"
            lower.contains("weekend") -> "0 9 * * 0,6" to "Weekends at 09:00"
            lower.contains("hourly") || lower.contains("every hour") -> "0 * * * *" to "Hourly"
            lower.contains("monday") -> "0 9 * * 1" to "Mondays at 09:00"
            else -> "0 9 * * *" to "Daily at 09:00"
        }
    }

    fun parseCreatedAutomation(
        res: JsonObject,
        prompt: String,
        projectSlug: String,
        fallbackId: String,
        originInstanceUuid: String? = null,
    ): AutomationItem {
        val autoObj = res.obj("automation") ?: res
        val id = nonEmpty(autoObj.str("id"))
            ?: nonEmpty(res.str("sidecarId"))
            ?: nonEmpty(res.str("sidecar_id"))
            ?: fallbackId
        val title = nonEmpty(autoObj.str("title")) ?: prompt.trim().take(64).ifEmpty { "Scheduled Automation" }
        val slug = nonEmpty(autoObj.str("project"))
            ?: nonEmpty(autoObj.str("projectSlug"))
            ?: projectSlug.ifBlank { "All projects" }
        val (cronExpr, defaultSchedule) = inferCronAndScheduleLabel(prompt)
        val schedule = nonEmpty(autoObj.str("schedule"))
            ?: nonEmpty(autoObj.str("scheduleSummary"))
            ?: defaultSchedule
        val state = (autoObj.str("state") ?: "scheduled").lowercase()
        val section = when {
            state.contains("pause") -> AutomationSectionKind.PAUSED
            state.contains("always") -> AutomationSectionKind.ALWAYS_ON
            else -> AutomationSectionKind.SCHEDULED
        }
        return AutomationItem(
            id = id,
            title = title,
            projectSlug = slug,
            scheduleSummary = schedule,
            section = section,
            nextRunText = nonEmpty(autoObj.str("nextRun")) ?: "Tomorrow, 09:00",
            lastRunText = nonEmpty(autoObj.str("lastRun")) ?: "Created just now",
            prompt = prompt,
            cronExpression = cronExpr,
            modelLabel = nonEmpty(autoObj.str("model")) ?: "Flash",
            originInstanceUuid = originInstanceUuid,
        )
    }

    // MARK: - Internal JSON & Path Helpers

    private fun pathBaseName(rawPath: String): String {
        val clean = ResolvedEmbedResource.normalizePath(rawPath).trimEnd('/')
        return clean.substringAfterLast('/').ifEmpty { clean }
    }

    private fun pathExtension(rawPath: String): String {
        val base = pathBaseName(rawPath)
        val dot = base.lastIndexOf('.')
        return if (dot > 0 && dot < base.length - 1) base.substring(dot + 1) else ""
    }

    private fun nonEmpty(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

    private fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull
    private fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.int(key: String): Int? =
        (this[key] as? JsonPrimitive)?.let { it.intOrNull ?: it.contentOrNull?.toIntOrNull() }
    private fun JsonObject.dbl(key: String): Double? =
        (this[key] as? JsonPrimitive)?.let { it.doubleOrNull ?: it.contentOrNull?.toDoubleOrNull() }
    private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
    private fun JsonObject.arr(key: String): JsonArray? = this[key] as? JsonArray
}
