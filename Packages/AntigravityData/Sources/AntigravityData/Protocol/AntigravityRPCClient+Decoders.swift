import Foundation

/// JSON step decoders and desktop trajectory summary / timestamp normalization helpers.
extension AntigravityRPCClient {
    // MARK: - JSON Step Decoder (`language_server` + Companion Schema)

    internal static func nonEmptyString(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : raw
    }

    internal static func resolveStepType(_ typeName: String) -> CortexStepType {
        if let exact = CortexStepType.allCases.first(where: { $0.jsonName == typeName }) {
            return exact
        }
        let upper = typeName.uppercased()
        if upper.contains("USER_INPUT") { return .userInput }
        if upper.contains("PLANNER_RESPONSE") { return .plannerResponse }
        if upper.contains("NOTIFY_USER") { return .notifyUser }
        if upper.contains("TASK_BOUNDARY") { return .taskBoundary }
        if upper.contains("RUN_COMMAND") { return .runCommand }
        if upper.contains("VIEW_FILE") || upper.contains("VIEW_CODE") { return .viewFile }
        if upper.contains("GREP_SEARCH") || upper.contains("FIND_BY_NAME") || upper.contains("SEARCH") { return .search }
        if upper.contains("LIST_DIRECTORY") { return .listDirectory }
        if upper.contains("CODE_ACTION") || upper.contains("REPLACE_FILE") || upper.contains("WRITE_TO_FILE") {
            return .codeAction
        }
        return .unspecified
    }

    internal static func parseDurationSeconds(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        if let d = value.doubleValue { return d }
        if let obj = value.objectValue {
            let secs = obj["seconds"]?.doubleValue ?? Double(obj["seconds"]?.stringValue ?? "") ?? 0
            let nanos = obj["nanos"]?.doubleValue ?? Double(obj["nanos"]?.stringValue ?? "") ?? 0
            let total = secs + (nanos / 1_000_000_000.0)
            return total > 0 ? total : nil
        }
        if let str = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let numeric = str.hasSuffix("s") ? String(str.dropLast()) : str
            return Double(numeric)
        }
        return nil
    }

    public static func decodeJSONStep(
        _ value: JSONValue,
        cascadeId: String,
        fallbackIndex: Int
    ) -> CascadeStep? {
        guard let obj = value.objectValue else { return nil }
        let stepIndex = obj["stepIndex"]?.intValue ?? fallbackIndex
        var stepType: CortexStepType = {
            if let typeName = obj["type"]?.stringValue, !typeName.isEmpty {
                return resolveStepType(typeName)
            }
            if let typeInt = obj["type"]?.intValue {
                return ProtobufStepCodec.decodeStepType(typeInt)
            }
            return .unspecified
        }()
        let stepStatus: CortexStepStatus = {
            if let statusName = obj["status"]?.stringValue, !statusName.isEmpty {
                return CortexStepStatus.from(jsonName: statusName)
            }
            if let statusInt = obj["status"]?.intValue {
                return ProtobufStepCodec.decodeStepStatus(statusInt)
            }
            return .done
        }()

        // Decode userInput (string or nested object `{"userResponse": ...}` / `{"items": [{"text": ...}]}`)
        var userText: String? = nonEmptyString(obj["userInput"]?.stringValue)
        var mentions: [String] = obj["attachedMentions"]?.arrayValue?.compactMap(\.stringValue) ?? []
        var recordedMode: CascadeExecutionMode?
        var recordedModelId: String?

        if let uiObj = obj["userInput"]?.objectValue {
            let itemsJoined = uiObj["items"]?.arrayValue?
                .compactMap { nonEmptyString($0.objectValue?["text"]?.stringValue) }
                .joined(separator: "\n")
            userText = nonEmptyString(uiObj["userResponse"]?.stringValue)
                ?? nonEmptyString(uiObj["query"]?.stringValue)
                ?? nonEmptyString(uiObj["text"]?.stringValue)
                ?? nonEmptyString(uiObj["prompt"]?.stringValue)
                ?? nonEmptyString(uiObj["message"]?.stringValue)
                ?? nonEmptyString(itemsJoined)
            if let itemArr = uiObj["items"]?.arrayValue {
                for item in itemArr {
                    if let fileObj = item.objectValue?["item"]?.objectValue?["file"]?.objectValue {
                        if let fileLabel = nonEmptyString(fileObj["label"]?.stringValue) {
                            if !mentions.contains(fileLabel) { mentions.append(fileLabel) }
                        } else if let uri = nonEmptyString(fileObj["absoluteUri"]?.stringValue) {
                            let base = (uri.replacingOccurrences(of: "file://", with: "") as NSString).lastPathComponent
                            let chip = base.hasPrefix("@") ? base : "@\(base)"
                            if !base.isEmpty && !mentions.contains(chip) { mentions.append(chip) }
                        }
                    }
                }
            }
            if let userCfg = (uiObj["userConfig"] ?? uiObj["lastUserConfig"])?.objectValue,
               let plannerCfg = userCfg["plannerConfig"]?.objectValue {
                if let convObj = plannerCfg["conversational"]?.objectValue {
                    if let agentic = convObj["agenticMode"]?.boolValue {
                        recordedMode = agentic ? .planning : .fast
                    }
                }
                let reqModelObj = plannerCfg["requestedModel"]?.objectValue
                recordedModelId = nonEmptyString(reqModelObj?["model"]?.stringValue)
                    ?? nonEmptyString(reqModelObj?["alias"]?.stringValue)
                    ?? nonEmptyString(plannerCfg["planModel"]?.stringValue)
                if recordedModelId == "MODEL_UNSPECIFIED" {
                    recordedModelId = nil
                }
            }
            if stepType == .unspecified && (userText != nil || !mentions.isEmpty) {
                stepType = .userInput
            }
        }

        // Decode plannerResponse & notifyUser
        var plannerPayload: PlannerResponsePayload?
        if let pr = obj["plannerResponse"]?.objectValue {
            let text = nonEmptyString(pr["modifiedResponse"]?.stringValue)
                ?? nonEmptyString(pr["response"]?.stringValue)
                ?? nonEmptyString(pr["text"]?.stringValue)
                ?? nonEmptyString(pr["content"]?.stringValue)
                ?? nonEmptyString(pr["message"]?.stringValue)
                ?? ""
            let thinking = nonEmptyString(pr["thinking"]?.stringValue)
            let duration = parseDurationSeconds(pr["thinkingDurationSeconds"] ?? pr["thinkingDuration"])
            if !text.isEmpty || thinking != nil || stepStatus == .inProgress || stepStatus == .pending {
                plannerPayload = PlannerResponsePayload(
                    response: text,
                    thinking: thinking,
                    thinkingDurationSeconds: duration
                )
                if stepType == .unspecified {
                    stepType = .plannerResponse
                }
            }
        } else if let nu = obj["notifyUser"]?.objectValue {
            let notifyText = nonEmptyString(nu["notificationContent"]?.stringValue)
                ?? nonEmptyString(nu["message"]?.stringValue)
                ?? nonEmptyString(nu["reviewContent"]?.stringValue)
            if let notifyText {
                let paths = (nu["pathsToReview"]?.arrayValue ?? nu["reviewAbsoluteUris"]?.arrayValue)?
                    .compactMap(\.stringValue) ?? []
                plannerPayload = PlannerResponsePayload(
                    response: notifyText,
                    referencedFiles: paths
                )
                stepType = .notifyUser
            }
        }

        // Decode runCommand + requestedInteraction
        var runCmdPayload: RunCommandPayload?
        var interaction: RequestedInteraction?
        if let rc = obj["runCommand"]?.objectValue {
            let cmdLine = nonEmptyString(rc["commandLine"]?.stringValue)
                ?? nonEmptyString(rc["proposedCommandLine"]?.stringValue)
                ?? nonEmptyString(rc["command"]?.stringValue)
                ?? ""
            let cwd = nonEmptyString(rc["cwd"]?.stringValue) ?? "~"
            if !cmdLine.isEmpty {
                runCmdPayload = RunCommandPayload(
                    commandId: rc["commandId"]?.stringValue ?? "cmd-\(stepIndex)",
                    commandLine: cmdLine,
                    proposedCommandLine: nonEmptyString(rc["proposedCommandLine"]?.stringValue) ?? cmdLine,
                    cwd: cwd,
                    exitCode: rc["exitCode"]?.intValue,
                    outputPreview: nonEmptyString(rc["combinedOutput"]?.objectValue?["full"]?.stringValue)
                        ?? nonEmptyString(rc["outputPreview"]?.stringValue)
                        ?? nonEmptyString(rc["output"]?.stringValue)
                )
                if stepType == .unspecified {
                    stepType = .runCommand
                }
            }
            if stepStatus == .waiting {
                interaction = RequestedInteraction(
                    kind: .runCommand,
                    runCommand: RunCommandInteractionSpec(proposedCommandLine: cmdLine, cwd: cwd)
                )
            }
        }

        if let reqInt = obj["requestedInteraction"]?.objectValue {
            if let rcInt = reqInt["runCommand"]?.objectValue {
                let cmd = nonEmptyString(rcInt["proposedCommandLine"]?.stringValue) ?? runCmdPayload?.commandLine ?? ""
                interaction = RequestedInteraction(
                    kind: .runCommand,
                    runCommand: RunCommandInteractionSpec(
                        proposedCommandLine: cmd,
                        cwd: nonEmptyString(rcInt["cwd"]?.stringValue) ?? "~"
                    )
                )
            } else if let qaInt = reqInt["askQuestion"]?.objectValue {
                interaction = RequestedInteraction(
                    kind: .askQuestion,
                    askQuestion: AskQuestionInteractionSpec(
                        question: nonEmptyString(qaInt["question"]?.stringValue) ?? "Input required",
                        options: qaInt["options"]?.arrayValue?.compactMap(\.stringValue) ?? [],
                        isMultiSelect: qaInt["isMultiSelect"]?.boolValue ?? false
                    )
                )
            } else if let fpInt = reqInt["filePermission"]?.objectValue {
                interaction = RequestedInteraction(
                    kind: .filePermission,
                    filePermission: FilePermissionInteractionSpec(
                        absolutePathUri: fpInt["absolutePathUri"]?.stringValue ?? ""
                    )
                )
            }
        }

        var viewFilePayload: ViewFilePayload?
        let vfCandidate = obj["viewFile"]?.objectValue
            ?? obj["viewFileOutline"]?.objectValue
            ?? obj["viewCodeItem"]?.objectValue
        if let vf = vfCandidate,
           let uri = nonEmptyString(vf["fileUri"]?.stringValue)
            ?? nonEmptyString(vf["absolutePathUri"]?.stringValue)
            ?? nonEmptyString(vf["absolutePath"]?.stringValue) {
            var capturedViewContent: String? = nil
            if ResolvedEmbedResource.isEmbeddableTextArtifactPath(uri),
               let rawContent = nonEmptyString(vf["content"]?.stringValue),
               rawContent.utf8.count <= 524_288 {
                capturedViewContent = rawContent
            }
            viewFilePayload = ViewFilePayload(
                fileUri: uri,
                startLine: vf["startLine"]?.intValue ?? 1,
                endLine: vf["endLine"]?.intValue ?? 120,
                fileContent: capturedViewContent
            )
            if stepType == .unspecified { stepType = .viewFile }
        }

        var searchPayload: SearchPayload?
        let searchCandidate = obj["grepSearch"]?.objectValue
            ?? obj["findByName"]?.objectValue
            ?? obj["search"]?.objectValue
        if let sc = searchCandidate {
            let query = nonEmptyString(sc["query"]?.stringValue)
                ?? nonEmptyString(sc["pattern"]?.stringValue)
                ?? "workspace"
            let scope = nonEmptyString(sc["searchPath"]?.stringValue)
                ?? nonEmptyString(sc["searchDirectory"]?.stringValue)
                ?? "."
            let count = sc["results"]?.arrayValue?.count ?? sc["matchCount"]?.intValue ?? 0
            searchPayload = SearchPayload(query: query, scopeDirectory: scope, matchCount: count)
            if stepType == .unspecified { stepType = .search }
        }

        var codeActionPayload: CodeActionPayload?
        let caCandidate = obj["codeAction"]?.objectValue
            ?? obj["replaceFileContent"]?.objectValue
            ?? obj["writeToFile"]?.objectValue
        if let ca = caCandidate {
            let actionSpec = ca["actionSpec"]?.objectValue
            let createFileSpec = actionSpec?["createFile"]?.objectValue
            let uri = nonEmptyString(ca["targetFileUri"]?.stringValue)
                ?? nonEmptyString(ca["fileUri"]?.stringValue)
                ?? nonEmptyString(ca["targetFile"]?.stringValue)
                ?? nonEmptyString(createFileSpec?["path"]?.objectValue?["absoluteUri"]?.stringValue)
                ?? nonEmptyString(actionSpec?["insertBlock"]?.objectValue?["path"]?.objectValue?["absoluteUri"]?.stringValue)
            if let uri {
                let lowerUri = uri.lowercased()
                let isArtifact = (ca["artifactMetadata"] != nil)
                    || (ca["isArtifactFile"]?.boolValue == true)
                    || lowerUri.contains("/.gemini/")
                    || lowerUri.contains("/brain/")
                var capturedContent: String? = nil
                if isArtifact || ResolvedEmbedResource.isEmbeddableTextArtifactPath(uri) {
                    let directCandidates: [String?] = [
                        ca["codeContent"]?.stringValue,
                        ca["content"]?.stringValue,
                        ca["fileContent"]?.stringValue,
                        createFileSpec?["codeContent"]?.stringValue,
                        createFileSpec?["content"]?.stringValue,
                        createFileSpec?["fileContent"]?.stringValue,
                        createFileSpec?["instruction"]?.stringValue
                    ]
                    for cand in directCandidates {
                        if let c = nonEmptyString(cand), c.utf8.count <= 524_288 {
                            capturedContent = c
                            break
                        }
                    }
                    // Fallback: reconstruct newly created artifact content from `actionResult.edit.diff.unifiedDiff.lines`
                    if capturedContent == nil,
                       let diffLines = ca["actionResult"]?.objectValue?["edit"]?.objectValue?["diff"]?.objectValue?["unifiedDiff"]?.objectValue?["lines"]?.arrayValue {
                        var addedLines: [String] = []
                        var hasRemoved = false
                        for lineItem in diffLines {
                            if let lineObj = lineItem.objectValue {
                                let lineText = lineObj["text"]?.stringValue ?? ""
                                let kind = (lineObj["type"]?.stringValue ?? "").uppercased()
                                if kind.contains("DELETE") || kind.contains("REMOVE") {
                                    hasRemoved = true
                                } else {
                                    addedLines.append(lineText)
                                }
                            } else if let rawLine = lineItem.stringValue {
                                if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                                    addedLines.append(String(rawLine.dropFirst()))
                                } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                                    hasRemoved = true
                                }
                            }
                        }
                        if !hasRemoved && !addedLines.isEmpty {
                            let joined = addedLines.joined(separator: "\n")
                            if joined.utf8.count <= 524_288 {
                                capturedContent = joined
                            }
                        }
                    }
                }

                codeActionPayload = CodeActionPayload(
                    targetFileUri: uri,
                    description: nonEmptyString(ca["description"]?.stringValue)
                        ?? nonEmptyString(ca["instruction"]?.stringValue)
                        ?? "Updated file",
                    additions: ca["additions"]?.intValue ?? 0,
                    deletions: ca["deletions"]?.intValue ?? 0,
                    isArtifactFile: isArtifact,
                    fileContent: capturedContent
                )
                if stepType == .unspecified { stepType = .codeAction }
            }
        }

        // Decode generateImage / readUrlContent / browserSubagent into lightweight display payloads
        if plannerPayload == nil {
            if let genImg = obj["generateImage"]?.objectValue {
                let imgPath = nonEmptyString(genImg["imagePath"]?.stringValue)
                    ?? nonEmptyString(genImg["outputPath"]?.stringValue)
                    ?? nonEmptyString(genImg["savedPath"]?.stringValue)
                    ?? nonEmptyString(genImg["artifactUri"]?.stringValue)
                let prompt = nonEmptyString(genImg["prompt"]?.stringValue) ?? "Generated image"
                if let imgPath {
                    let fileURI = imgPath.contains("://") ? imgPath : "file://\(imgPath)"
                    plannerPayload = PlannerResponsePayload(
                        response: "![\(prompt)](\(fileURI))",
                        referencedFiles: [fileURI]
                    )
                    stepType = .generateImage
                }
            } else if let readUrl = obj["readUrlContent"]?.objectValue {
                let targetUrl = nonEmptyString(readUrl["url"]?.stringValue) ?? nonEmptyString(readUrl["uri"]?.stringValue)
                if let targetUrl {
                    plannerPayload = PlannerResponsePayload(response: targetUrl)
                    stepType = .readUrlContent
                }
            } else if let browser = obj["browserSubagent"]?.objectValue {
                let taskSummary = nonEmptyString(browser["taskName"]?.stringValue)
                    ?? nonEmptyString(browser["task"]?.stringValue)
                    ?? "Browser automation task"
                plannerPayload = PlannerResponsePayload(response: taskSummary)
                stepType = .browserSubagent
            }
        }

        var taskBoundaryPayload: TaskBoundaryPayload?
        if let tb = obj["taskBoundary"]?.objectValue {
            taskBoundaryPayload = TaskBoundaryPayload(
                taskName: nonEmptyString(tb["taskName"]?.stringValue) ?? "Task",
                taskStatus: nonEmptyString(tb["taskStatus"]?.stringValue) ?? "",
                taskSummary: nonEmptyString(tb["taskSummary"]?.stringValue) ?? "",
                completedCount: tb["completedCount"]?.intValue ?? 0,
                totalCount: tb["totalCount"]?.intValue ?? 0,
                elapsedLabel: nonEmptyString(tb["elapsedLabel"]?.stringValue) ?? ""
            )
            if stepType == .unspecified { stepType = .taskBoundary }
        }

        if (stepType == .plannerResponse || stepType == .notifyUser)
            && plannerPayload == nil
            && (stepStatus == .inProgress || stepStatus == .pending) {
            plannerPayload = PlannerResponsePayload(response: "")
        }

        let createdDate = Self.parseProtoTimestamp(obj["metadata"]?.objectValue?["createdAt"] ?? obj["createdAt"]) ?? Date()

        return CascadeStep(
            cascadeId: cascadeId,
            stepIndex: stepIndex,
            type: stepType,
            status: stepStatus,
            createdAt: createdDate,
            userInput: userText,
            attachedMentions: mentions,
            plannerResponse: plannerPayload,
            taskBoundary: taskBoundaryPayload,
            runCommand: runCmdPayload,
            codeAction: codeActionPayload,
            viewFile: viewFilePayload,
            search: searchPayload,
            requestedInteraction: interaction,
            recordedExecutionMode: recordedMode,
            recordedModelId: recordedModelId
        )
    }

    // MARK: - Live Desktop Summary & Timestamp Helpers

    /// Decodes a single entry from `GetAllCascadeTrajectories.trajectorySummaries` or `JetboxSubscribeToSummaries.updates`,
    /// filtering out blank 0-step unused Desktop tabs and computing accurate Cloud/local/`No Project`/unread/status fields.
    public static func decodeTrajectorySummaryEntry(
        cascadeId: String,
        value: JSONValue,
        now: Date = Date(),
        forceCloud: Bool = false
    ) -> CascadeSummary? {
        guard let obj = value.objectValue else { return nil }
        let annotations = obj["annotations"]?.objectValue ?? obj["conversationAnnotations"]?.objectValue
        let trajMeta = obj["trajectoryMetadata"]?.objectValue

        let candidateTitles: [String?] = [
            annotations?["title"]?.stringValue,
            annotations?["customTitle"]?.stringValue,
            annotations?["name"]?.stringValue,
            obj["summary"]?.stringValue,
            obj["title"]?.stringValue,
            obj["displayName"]?.stringValue,
            obj["name"]?.stringValue,
            trajMeta?["title"]?.stringValue,
            trajMeta?["summary"]?.stringValue,
            trajMeta?["name"]?.stringValue,
            obj["firstUserInput"]?.stringValue,
            obj["query"]?.stringValue
        ]
        let resolvedTitle = candidateTitles
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        let stepCount = obj["stepCount"]?.intValue
            ?? Int(obj["stepCount"]?.stringValue ?? "")
            ?? 0

        let projectIdCandidates: [String?] = [
            trajMeta?["projectId"]?.stringValue,
            trajMeta?["project_id"]?.stringValue,
            obj["projectId"]?.stringValue,
            obj["project_id"]?.stringValue,
            annotations?["projectId"]?.stringValue,
            obj["projectEnvConfig"]?.objectValue?["projectId"]?.stringValue,
            obj["metadata"]?.objectValue?["projectId"]?.stringValue
        ]
        let cloudProjectId = projectIdCandidates.compactMap(Self.nonEmptyString).first
        let explicitCloudBool = (obj["cloud"]?.boolValue == true)
            || (obj["isCloud"]?.boolValue == true)
            || (trajMeta?["isCloud"]?.boolValue == true)

        let statusValue = obj["status"] ?? obj["runStatus"] ?? obj["cascadeRunStatus"]
        let statusRaw = statusValue?.stringValue ?? "CASCADE_RUN_STATUS_IDLE"
        var status: CortexStepStatus
        if let statusCode = statusValue?.intValue {
            status = CortexStepStatus.from(cascadeRunStatusCode: statusCode)
        } else {
            status = CortexStepStatus.from(jsonName: statusRaw)
        }
        if status == .unspecified {
            if obj["waitingForUser"]?.boolValue == true
                || obj["hasPendingInteraction"]?.boolValue == true
                || obj["needsUserAction"]?.boolValue == true {
                status = .waiting
            } else if obj["isRunning"]?.boolValue == true || obj["running"]?.boolValue == true {
                status = .inProgress
            }
        }
        let isActiveRun = status == .inProgress || status == .pending || status == .waiting

        // Antigravity Desktop keeps unused 0-step local New Chat placeholders in `trajectorySummaries`
        // without a title/summary and hides them in its sidebar. Filter them out cleanly (unless Cloud or active).
        if resolvedTitle == nil && stepCount == 0 && !explicitCloudBool && !forceCloud && !isActiveRun {
            return nil
        }
        let title = resolvedTitle ?? "New Conversation"
        let lowerTitle = title.lowercased()
        if lowerTitle.contains("ios connect-rpc handshake")
            || lowerTitle.contains("reply in one short sentence confirming ios connect-rpc handshake") {
            return nil
        }

        let workspaceObjects = (obj["workspaces"]?.arrayValue ?? []).compactMap(\.objectValue)
        let allMetaUris = trajMeta?["workspaceUris"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let directWsUri = obj["workspaceUri"]?.stringValue
        let allCandidateUris: [String] = workspaceObjects.compactMap {
            $0["workspaceFolderAbsoluteUri"]?.stringValue ?? $0["workspaceUri"]?.stringValue
        } + allMetaUris + [directWsUri].compactMap { $0 }
        let hasCloudWorkspaceEntry = allCandidateUris.contains { AntigravityCloudDetector.isCloudWorkspaceURI($0) }

        let selectedWorkspace = Self.selectPrimaryWorkspaceObject(from: workspaceObjects)
        let metaWorkspaceUri = allMetaUris.first {
            !AntigravityCloudDetector.isGenericContainerURI($0)
        }
        let primaryWsUri: String? = selectedWorkspace?["workspaceFolderAbsoluteUri"]?.stringValue
            ?? selectedWorkspace?["workspaceUri"]?.stringValue
        let rawUri: String = [primaryWsUri, metaWorkspaceUri, directWsUri]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !AntigravityCloudDetector.isGenericContainerURI($0) })
            ?? ""

        let sourceHint = [
            obj["source"]?.stringValue,
            obj["runtime"]?.stringValue,
            obj["backend"]?.stringValue,
            trajMeta?["runtime"]?.stringValue,
            trajMeta?["environment"]?.stringValue,
            trajMeta?["executionEnvironment"]?.stringValue,
            trajMeta?["source"]?.stringValue
        ]
            .compactMap { $0 }
            .joined(separator: " ")

        let isForceCloudContainerPath: Bool = {
            guard forceCloud else { return false }
            let lowerRaw = (rawUri.removingPercentEncoding ?? rawUri).lowercased()
            return lowerRaw.hasPrefix("file:///workspace/")
                || lowerRaw.hasPrefix("file:///workspaces/")
                || lowerRaw.hasPrefix("file:///root/")
        }()

        let isCloud = explicitCloudBool
            || hasCloudWorkspaceEntry
            || isForceCloudContainerPath
            || AntigravityCloudDetector.isCloudWorkspaceURI(rawUri, cascadeId: cascadeId, sourceHint: sourceHint)

        let isScratchPlayground = AntigravityCloudDetector.isPlaygroundScratchURI(rawUri)
        let isUnassigned = (cloudProjectId ?? "").isEmpty && (rawUri.isEmpty || isScratchPlayground)

        let uri: String
        if isUnassigned {
            uri = isScratchPlayground ? rawUri : ""
        } else if rawUri.isEmpty, let cpid = cloudProjectId, !cpid.isEmpty {
            uri = "cloud://\(cpid)"
        } else {
            uri = AntigravityCloudDetector.normalizeWorkspaceURI(rawUri, isCloud: isCloud)
        }

        let explicitSlug = (obj["projectSlug"]?.stringValue ?? obj["project"]?.stringValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let slug: String
        if let explicitSlug, !explicitSlug.isEmpty, !AntigravityCloudDetector.isNoProjectSlug(explicitSlug) {
            slug = explicitSlug
        } else if isUnassigned {
            slug = AntigravityCloudDetector.noProjectDisplayName
        } else if rawUri.isEmpty, let cpid = cloudProjectId, !cpid.isEmpty {
            slug = cpid
        } else if rawUri.hasPrefix("cloud://") {
            let trimmedCloud = rawUri.replacingOccurrences(of: "cloud://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            slug = trimmedCloud.isEmpty || AntigravityCloudDetector.isNoProjectSlug(trimmedCloud)
                ? (cloudProjectId ?? AntigravityCloudDetector.noProjectDisplayName)
                : trimmedCloud
        } else if rawUri.hasPrefix("https://github.com/") {
            let trimmedGH = rawUri.replacingOccurrences(of: "https://github.com/", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            slug = trimmedGH.isEmpty ? AntigravityCloudDetector.noProjectDisplayName : trimmedGH
        } else if rawUri.contains("://") && !rawUri.hasPrefix("file://") {
            let decodedRaw = rawUri.removingPercentEncoding ?? rawUri
            let lastComp = ((URL(string: decodedRaw)?.path ?? decodedRaw) as NSString).lastPathComponent
            slug = lastComp.isEmpty || AntigravityCloudDetector.isNoProjectSlug(lastComp)
                ? (cloudProjectId ?? AntigravityCloudDetector.noProjectDisplayName)
                : lastComp
        } else {
            let cleanPath = (rawUri.removingPercentEncoding ?? rawUri)
                .replacingOccurrences(of: "file://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let lastComp = (cleanPath as NSString).lastPathComponent
            if !lastComp.isEmpty && !AntigravityCloudDetector.isNoProjectSlug(lastComp) {
                slug = lastComp
            } else {
                slug = cloudProjectId ?? AntigravityCloudDetector.noProjectDisplayName
            }
        }

        let branch: String
        if isUnassigned {
            branch = ""
        } else {
            branch = selectedWorkspace?["gitBranch"]?.stringValue
                ?? selectedWorkspace?["branchName"]?.stringValue
                ?? obj["branchName"]?.stringValue
                ?? "main"
        }

        let candidateUpdateDates: [Date] = [
            Self.parseProtoTimestamp(obj["lastModifiedTime"]),
            Self.parseProtoTimestamp(obj["updatedAt"]),
            Self.parseProtoTimestamp(obj["lastStepTime"]),
            Self.parseProtoTimestamp(obj["lastAgentReplyTime"]),
            Self.parseProtoTimestamp(
                obj["latestNotifyUserStep"]?.objectValue?["step"]?.objectValue?["metadata"]?.objectValue?["createdAt"]
            ),
            Self.parseProtoTimestamp(
                obj["latestTaskBoundaryStep"]?.objectValue?["step"]?.objectValue?["metadata"]?.objectValue?["createdAt"]
            )
        ].compactMap { $0 }
        let updatedDate = candidateUpdateDates.max() ?? Self.parseProtoTimestamp(obj["createdTime"])
        let lastViewedCandidates: [JSONValue?] = [
            annotations?["lastUserViewTime"],
            annotations?["last_user_view_time"],
            annotations?["lastViewedTime"],
            annotations?["lastReadTime"],
            obj["lastUserViewTime"],
            obj["last_user_view_time"],
            obj["lastViewedTime"],
            trajMeta?["lastUserViewTime"]
        ]
        let lastViewedDate = lastViewedCandidates.compactMap { Self.parseProtoTimestamp($0) }.first
        let updatedAt = updatedDate ?? now
        let relativeLabel = Self.formatRelativeTimeLabel(from: updatedDate, now: now)

        let unreadCandidates: [Bool?] = [
            obj["isUnread"]?.boolValue,
            obj["unread"]?.boolValue,
            obj["hasUnread"]?.boolValue,
            obj["hasUnreadMessages"]?.boolValue,
            obj["hasUnseenUpdates"]?.boolValue,
            obj["unseen"]?.boolValue,
            annotations?["isUnread"]?.boolValue,
            annotations?["unread"]?.boolValue,
            annotations?["hasUnread"]?.boolValue,
            trajMeta?["unread"]?.boolValue,
            trajMeta?["isUnread"]?.boolValue
        ]
        let explicitUnread: Bool? = unreadCandidates.compactMap { $0 }.first

        let isUnread: Bool
        if let explicitUnread {
            isUnread = explicitUnread
        } else if status == .inProgress || status == .pending {
            isUnread = false
        } else if let updatedDate, let lastViewedDate {
            isUnread = updatedDate.timeIntervalSince(lastViewedDate) > 0.5
                || statusRaw.uppercased() == "CASCADE_RUN_STATUS_DONE"
                || status == .waiting
        } else {
            isUnread = statusRaw.uppercased() == "CASCADE_RUN_STATUS_DONE" || status == .waiting
        }

        let isPinned = obj["isPinned"]?.boolValue
            ?? annotations?["pinned"]?.boolValue
            ?? annotations?["isPinned"]?.boolValue
            ?? false
        let isArchived = obj["isArchived"]?.boolValue
            ?? annotations?["archived"]?.boolValue
            ?? annotations?["isArchived"]?.boolValue
            ?? false

        let explicitSubtitle = obj["statusSubtitle"]?.stringValue
        let subtitle = Self.buildLiveStatusSubtitle(
            status: status,
            stepCount: stepCount,
            isUnread: isUnread,
            explicitSubtitle: explicitSubtitle
        )

        return CascadeSummary(
            cascadeId: cascadeId,
            title: title,
            projectSlug: slug.isEmpty ? AntigravityCloudDetector.noProjectDisplayName : slug,
            workspaceUri: uri,
            branchName: branch,
            status: status,
            stepCount: stepCount,
            currentStepIndex: max(1, stepCount),
            totalSteps: max(1, stepCount),
            updatedAt: updatedAt,
            relativeTimeLabel: relativeLabel,
            statusSubtitle: subtitle,
            isPinned: isPinned,
            isArchived: isArchived,
            isUnread: isUnread,
            isCloud: isCloud,
            cloudProjectId: cloudProjectId,
            originHostName: isCloud ? "Antigravity" : nil,
            lastUserViewTime: lastViewedDate
        )
    }

    internal static func selectPrimaryWorkspaceObject(
        from workspaces: [[String: JSONValue]]
    ) -> [String: JSONValue]? {
        guard !workspaces.isEmpty else { return nil }
        for entry in workspaces {
            let raw = (entry["workspaceFolderAbsoluteUri"]?.stringValue ?? entry["workspaceUri"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !AntigravityCloudDetector.isGenericContainerURI(raw) else { continue }
            let lower = raw.lowercased()
            if lower.hasPrefix("cloud://")
                || lower.hasPrefix("vscode-remote://")
                || lower.hasPrefix("vscode-vfs://")
                || lower.hasPrefix("https://github.com/") {
                return entry
            }
        }
        for entry in workspaces {
            let raw = (entry["workspaceFolderAbsoluteUri"]?.stringValue ?? entry["workspaceUri"]?.stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !AntigravityCloudDetector.isGenericContainerURI(raw) else { continue }
            return entry
        }
        return nil
    }

    /// Parses Protobuf `google.protobuf.Timestamp` values encoded either as RFC3339 strings
    /// (including 1–9 fractional nanosecond digits) or `{"seconds": ..., "nanos": ...}` objects.
    public static func parseProtoTimestamp(_ value: JSONValue?) -> Date? {
        guard let value else { return nil }

        if let tsObj = value.objectValue {
            let secs: Double? = tsObj["seconds"]?.doubleValue
                ?? Double(tsObj["seconds"]?.stringValue ?? "")
            if let secs {
                let nanos = tsObj["nanos"]?.doubleValue
                    ?? Double(tsObj["nanos"]?.stringValue ?? "")
                    ?? 0
                return Date(timeIntervalSince1970: secs + (nanos / 1_000_000_000.0))
            }
            return nil
        }

        guard let rawString = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawString.isEmpty else {
            return nil
        }

        if let dotIdx = rawString.firstIndex(of: ".") {
            let fracStart = rawString.index(after: dotIdx)
            var fracEnd = fracStart
            while fracEnd < rawString.endIndex && rawString[fracEnd].isNumber {
                fracEnd = rawString.index(after: fracEnd)
            }
            let digits = rawString[fracStart..<fracEnd]
            if !digits.isEmpty {
                let millis = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
                let normalized = "\(rawString[..<dotIdx]).\(millis)\(rawString[fracEnd...])"
                let fracFormatter = ISO8601DateFormatter()
                fracFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = fracFormatter.date(from: normalized) {
                    return parsed
                }
            }
        }

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        return plainFormatter.date(from: rawString)
    }

    /// Formats a compact mobile relative timestamp (`now`, `8m`, `2h`, `Yesterday`, `4d`, `2w`).
    public static func formatRelativeTimeLabel(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "now" }
        let delta = max(0, now.timeIntervalSince(date))
        if delta < 60 {
            return "now"
        } else if delta < 3_600 {
            return "\(Int(delta / 60))m"
        } else if delta < 86_400 {
            return "\(Int(delta / 3_600))h"
        } else if delta < 172_800 {
            return "Yesterday"
        } else if delta < 604_800 {
            return "\(Int(delta / 86_400))d"
        } else {
            return "\(Int(delta / 604_800))w"
        }
    }

    public static func buildLiveStatusSubtitle(
        status: CortexStepStatus,
        stepCount: Int,
        isUnread: Bool,
        explicitSubtitle: String? = nil
    ) -> String {
        if let explicitSubtitle, !explicitSubtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitSubtitle
        }
        switch status {
        case .inProgress:
            return stepCount > 0 ? "Running · Step \(stepCount)" : "Running..."
        case .pending:
            return "Queued · Waiting to start"
        case .waiting, .blocked:
            return "Needs review · Waiting on you"
        case .error:
            return stepCount > 0 ? "Error · Step \(stepCount)" : "Error"
        case .cancelled:
            return stepCount > 0 ? "Stopped · \(stepCount) steps" : "Stopped"
        case .done:
            if isUnread {
                return stepCount > 0 ? "Done · New reply · \(stepCount) steps" : "Done · New reply"
            }
            return stepCount > 0 ? "Done · \(stepCount) steps" : "Done"
        case .unspecified:
            if isUnread {
                return stepCount > 0 ? "New reply · \(stepCount) steps" : "New reply"
            }
            return stepCount > 0 ? "Idle · \(stepCount) steps" : "Idle"
        }
    }
}
