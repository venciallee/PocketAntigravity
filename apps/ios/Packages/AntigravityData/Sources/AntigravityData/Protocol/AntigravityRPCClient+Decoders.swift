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
        if upper.contains("SEND_COMMAND_INPUT") { return .sendCommandInput }
        if upper.contains("COMMAND_STATUS") { return .commandStatus }
        if upper.contains("RUN_COMMAND") || upper.contains("SHELL_EXEC") { return .runCommand }
        if upper.contains("VIEW_CONTENT_CHUNK") { return .viewContentChunk }
        if upper.contains("VIEW_FILE") || upper.contains("VIEW_CODE") { return .viewFile }
        if upper.contains("GREP_SEARCH") || upper.contains("FIND_BY_NAME") || upper.contains("SEARCH") { return .search }
        if upper.contains("LIST_DIRECTORY") { return .listDirectory }
        if upper.contains("READ_URL_CONTENT") { return .readUrlContent }
        if upper.contains("BROWSER_SUBAGENT") || upper.contains("BROWSER_") { return .browserSubagent }
        if upper.contains("SUBAGENT") { return .subagentInvocation }
        if upper.contains("WORKFLOW") { return .dynamicWorkflow }
        if upper.contains("SWARM") { return .swarmBoard }
        if upper.contains("MCP") { return .mcpToolCall }
        if upper.contains("CHECKPOINT") { return .checkpoint }
        if upper.contains("EPHEMERAL_MESSAGE") { return .ephemeralMessage }
        if upper.contains("CODE_ACTION")
            || upper.contains("REPLACE_FILE")
            || upper.contains("MULTI_REPLACE_FILE")
            || upper.contains("WRITE_TO_FILE")
            || upper.contains("FILE_CHANGE")
            || upper.contains("PROPOSE_CODE") {
            return .codeAction
        }
        return .unspecified
    }

    internal static func extractReadableSummary(from value: JSONValue?) -> String? {
        guard let value else { return nil }
        if let s = nonEmptyString(value.stringValue) {
            return s
        }
        guard let obj = value.objectValue else { return nil }
        let preferredKeys = [
            "proposedCommandLine", "commandLine", "command", "input",
            "absolutePathUri", "fileUri", "targetFileUri", "path", "target",
            "url", "domain", "question", "title", "reason", "description",
            "message", "action", "toolName", "serverName", "summary", "query"
        ]
        for key in preferredKeys {
            if let s = nonEmptyString(obj[key]?.stringValue) {
                return s
            }
        }
        for key in obj.keys.sorted() {
            if let s = nonEmptyString(obj[key]?.stringValue) {
                return s
            }
        }
        return nil
    }

    internal static func decodePersistSuggestionType(_ value: JSONValue?) -> PersistSuggestionType {
        if let raw = value?.intValue, let parsed = PersistSuggestionType(rawValue: raw) {
            return parsed
        }
        if let str = value?.stringValue?.uppercased() {
            if str.contains("BLOCKED") { return .blocked }
            if str.contains("SUGGESTED") { return .suggested }
            if str.contains("UNSPECIFIED") { return .unspecified }
        }
        return .suggested
    }

    internal static func decodeJSONRequestedInteraction(
        _ reqInt: [String: JSONValue],
        fallbackCommandLine: String?,
        fallbackCwd: String?
    ) -> RequestedInteraction? {
        if let rcInt = (reqInt["runCommand"] ?? reqInt["run_command"])?.objectValue {
            let cmd = nonEmptyString(rcInt["proposedCommandLine"]?.stringValue)
                ?? nonEmptyString(rcInt["commandLine"]?.stringValue)
                ?? nonEmptyString(rcInt["command"]?.stringValue)
                ?? fallbackCommandLine
                ?? ""
            let cwd = nonEmptyString(rcInt["cwd"]?.stringValue)
                ?? fallbackCwd
                ?? "~"
            return RequestedInteraction(
                kind: .runCommand,
                runCommand: RunCommandInteractionSpec(
                    proposedCommandLine: cmd,
                    cwd: cwd,
                    isDaemon: rcInt["isDaemon"]?.boolValue ?? false
                ),
                rawMemberKey: "runCommand"
            )
        }
        if let permInt = reqInt["permission"]?.objectValue {
            let action = nonEmptyString(permInt["action"]?.stringValue)
                ?? nonEmptyString(permInt["toolName"]?.stringValue)
                ?? nonEmptyString(permInt["permissionType"]?.stringValue)
                ?? "tool"
            let pattern = nonEmptyString(permInt["suggestedPersistPattern"]?.stringValue)
                ?? nonEmptyString(permInt["persistPattern"]?.stringValue)
            let targetKeys = ["target", "resource", "path", "absolutePathUri", "command"]
            var resolvedTarget: String? = nil
            for key in targetKeys {
                if let candidate = nonEmptyString(permInt[key]?.stringValue) {
                    resolvedTarget = candidate
                    break
                }
            }
            let target = resolvedTarget ?? pattern ?? "*"
            let reason = nonEmptyString(permInt["reason"]?.stringValue)
                ?? nonEmptyString(permInt["description"]?.stringValue)
                ?? nonEmptyString(permInt["message"]?.stringValue)
            let plugin = nonEmptyString(permInt["pluginName"]?.stringValue)
                ?? nonEmptyString(permInt["serverName"]?.stringValue)
            let persistType = decodePersistSuggestionType(permInt["persistSuggestionType"])
            return RequestedInteraction(
                kind: .permission,
                permission: PermissionInteractionSpec(
                    action: action,
                    target: target,
                    suggestedPersistPattern: pattern ?? target,
                    persistSuggestionType: persistType,
                    reason: reason,
                    pluginName: plugin,
                    toolIconName: nonEmptyString(permInt["toolIconName"]?.stringValue)
                ),
                pluginName: plugin,
                rawMemberKey: "permission",
                rawSummary: reason ?? "\(action)(\(target))"
            )
        }
        if let fpInt = (reqInt["filePermission"] ?? reqInt["file_permission"])?.objectValue {
            let uri = nonEmptyString(fpInt["absolutePathUri"]?.stringValue)
                ?? nonEmptyString(fpInt["fileUri"]?.stringValue)
                ?? nonEmptyString(fpInt["absolutePath"]?.stringValue)
                ?? nonEmptyString(fpInt["path"]?.stringValue)
                ?? ""
            return RequestedInteraction(
                kind: .filePermission,
                filePermission: FilePermissionInteractionSpec(
                    absolutePathUri: uri,
                    isDirectory: fpInt["isDirectory"]?.boolValue ?? false,
                    blockReason: nonEmptyString(fpInt["blockReason"]?.stringValue)
                        ?? nonEmptyString(fpInt["reason"]?.stringValue)
                ),
                rawMemberKey: "filePermission",
                rawSummary: uri.isEmpty ? nil : uri
            )
        }
        if let qaInt = (reqInt["askQuestion"] ?? reqInt["ask_question"] ?? reqInt["elicitation"])?.objectValue {
            let isElicitation = (reqInt["askQuestion"] == nil && reqInt["ask_question"] == nil && reqInt["elicitation"] != nil)
            let primaryQ = qaInt["questions"]?.arrayValue?.first?.objectValue ?? qaInt
            let rawOptions = primaryQ["options"]?.arrayValue ?? []
            let options: [String] = rawOptions.compactMap { item in
                if let s = nonEmptyString(item.stringValue) { return s }
                if let o = item.objectValue {
                    return nonEmptyString(o["label"]?.stringValue)
                        ?? nonEmptyString(o["text"]?.stringValue)
                        ?? nonEmptyString(o["title"]?.stringValue)
                        ?? nonEmptyString(o["value"]?.stringValue)
                }
                return nil
            }
            let questionText = nonEmptyString(primaryQ["question"]?.stringValue)
                ?? nonEmptyString(qaInt["question"]?.stringValue)
                ?? nonEmptyString(qaInt["prompt"]?.stringValue)
                ?? nonEmptyString(qaInt["message"]?.stringValue)
                ?? "Input required"
            return RequestedInteraction(
                kind: isElicitation ? .elicitation : .askQuestion,
                askQuestion: AskQuestionInteractionSpec(
                    question: questionText,
                    options: options,
                    isMultiSelect: primaryQ["isMultiSelect"]?.boolValue ?? qaInt["isMultiSelect"]?.boolValue ?? false
                ),
                rawMemberKey: isElicitation ? "elicitation" : "askQuestion",
                rawSummary: questionText
            )
        }
        if let mcpInt = reqInt["mcp"]?.objectValue {
            let server = nonEmptyString(mcpInt["serverName"]?.stringValue)
                ?? nonEmptyString(mcpInt["mcpServerName"]?.stringValue)
                ?? "mcp-server"
            let tool = nonEmptyString(mcpInt["toolName"]?.stringValue)
                ?? nonEmptyString(mcpInt["mcpToolName"]?.stringValue)
                ?? "invoke_tool"
            let plugin = nonEmptyString(mcpInt["pluginName"]?.stringValue)
            return RequestedInteraction(
                kind: .mcp,
                mcpServerName: server,
                mcpToolName: tool,
                pluginName: plugin,
                rawMemberKey: "mcp",
                rawSummary: "\(server): \(tool)"
            )
        }
        if let sciInt = (reqInt["sendCommandInput"] ?? reqInt["send_command_input"])?.objectValue {
            let summary = nonEmptyString(sciInt["input"]?.stringValue)
                ?? nonEmptyString(sciInt["commandLine"]?.stringValue)
                ?? nonEmptyString(sciInt["commandId"]?.stringValue)
            return RequestedInteraction(
                kind: .sendCommandInput,
                rawMemberKey: "sendCommandInput",
                rawSummary: summary
            )
        }
        if let dlInt = (reqInt["downloadUrl"] ?? reqInt["download_url"])?.objectValue {
            let url = nonEmptyString(dlInt["url"]?.stringValue) ?? ""
            let origin = nonEmptyString(dlInt["origin"]?.stringValue) ?? (URL(string: url)?.host ?? "external")
            let fileName = nonEmptyString(dlInt["fileName"]?.stringValue) ?? (URL(string: url)?.lastPathComponent ?? "download")
            return RequestedInteraction(
                kind: .downloadUrl,
                downloadUrl: DownloadUrlInteractionSpec(
                    url: url,
                    origin: origin,
                    fileName: fileName,
                    mimeType: nonEmptyString(dlInt["mimeType"]?.stringValue) ?? "application/octet-stream",
                    destinationFolder: nonEmptyString(dlInt["destinationFolder"]?.stringValue) ?? "~/Downloads"
                ),
                rawMemberKey: "downloadUrl"
            )
        }
        if let upInt = (reqInt["browserUpload"] ?? reqInt["browser_upload"])?.objectValue {
            let origin = nonEmptyString(upInt["origin"]?.stringValue) ?? "external site"
            let files = upInt["fileNames"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return RequestedInteraction(
                kind: .browserUpload,
                browserUpload: BrowserUploadInteractionSpec(origin: origin, fileNames: files),
                rawMemberKey: "browserUpload"
            )
        }
        if let wfInt = (reqInt["workflowScript"] ?? reqInt["workflow_script"])?.objectValue {
            return RequestedInteraction(
                kind: .workflowScript,
                workflowScript: WorkflowScriptInteractionSpec(
                    title: nonEmptyString(wfInt["title"]?.stringValue) ?? "Dynamic Workflow",
                    pythonScript: nonEmptyString(wfInt["pythonScript"]?.stringValue) ?? "",
                    phaseNames: wfInt["phaseNames"]?.arrayValue?.compactMap(\.stringValue) ?? []
                ),
                rawMemberKey: "workflowScript"
            )
        }
        let browserMembers: [(String, RequestedInteraction.MemberKind)] = [
            ("executeUrl", .executeUrl),
            ("openBrowserUrl", .openBrowserUrl),
            ("browserAction", .browserAction),
            ("executeBrowserJavascript", .executeBrowserJavascript),
            ("captureBrowserScreenshot", .captureBrowserScreenshot),
            ("clickBrowserPixel", .clickBrowserPixel),
            ("openBrowserSetup", .openBrowserSetup),
            ("confirmBrowserSetup", .confirmBrowserSetup)
        ]
        for (key, kind) in browserMembers {
            if let bObj = reqInt[key]?.objectValue {
                let url = nonEmptyString(bObj["url"]?.stringValue) ?? ""
                let domain = nonEmptyString(bObj["domain"]?.stringValue)
                    ?? URL(string: url)?.host
                    ?? (url.isEmpty ? nil : url)
                return RequestedInteraction(
                    kind: kind,
                    executeUrl: url.isEmpty ? nil : ExecuteUrlInteractionSpec(
                        url: url,
                        domain: domain ?? "external site",
                        isRedirect: bObj["isRedirect"]?.boolValue ?? false
                    ),
                    rawMemberKey: key,
                    rawSummary: extractReadableSummary(from: .object(bObj))
                )
            }
        }
        if let readUrlObj = reqInt["readUrlContent"]?.objectValue {
            return RequestedInteraction(
                kind: .readUrlContent,
                rawMemberKey: "readUrlContent",
                rawSummary: nonEmptyString(readUrlObj["url"]?.stringValue)
                    ?? extractReadableSummary(from: .object(readUrlObj))
            )
        }
        if let deployVal = reqInt["deploy"] {
            return RequestedInteraction(
                kind: .deploy,
                rawMemberKey: "deploy",
                rawSummary: extractReadableSummary(from: deployVal)
            )
        }
        if let extVal = reqInt["runExtensionCode"] {
            return RequestedInteraction(
                kind: .runExtensionCode,
                rawMemberKey: "runExtensionCode",
                rawSummary: extractReadableSummary(from: extVal)
            )
        }
        if let appVal = reqInt["approvalInteraction"] {
            return RequestedInteraction(
                kind: .approvalInteraction,
                rawMemberKey: "approvalInteraction",
                rawSummary: extractReadableSummary(from: appVal)
            )
        }
        // Preserve any unrecognized future server interaction oneof key verbatim
        let ignoredMetaKeys: Set<String> = ["trajectoryId", "stepIndex", "id", "metadata"]
        if let unknownKey = reqInt.keys.sorted().first(where: { !ignoredMetaKeys.contains($0) }) {
            let memberVal = reqInt[unknownKey]
            return RequestedInteraction(
                kind: .approvalInteraction,
                rawMemberKey: unknownKey,
                rawSummary: extractReadableSummary(from: memberVal)
            )
        }
        return nil
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
        let rawTypeInputString = nonEmptyString(obj["type"]?.stringValue)
        let rawTypeInputInt = obj["type"]?.intValue
        var stepType: CortexStepType = {
            if let typeName = rawTypeInputString {
                return resolveStepType(typeName)
            }
            if let typeInt = rawTypeInputInt {
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
            if let mediaArr = uiObj["media"]?.arrayValue {
                for (idx, mediaVal) in mediaArr.enumerated() {
                    guard let mediaObj = mediaVal.objectValue else { continue }
                    let label = nonEmptyString(mediaObj["description"]?.stringValue)
                        ?? nonEmptyString(mediaObj["uri"]?.stringValue).map { ($0 as NSString).lastPathComponent }
                        ?? ((mediaObj["mimeType"]?.stringValue ?? "").hasPrefix("image/") ? "image-\(idx + 1)" : "media-\(idx + 1)")
                    if !label.isEmpty && !mentions.contains(label) {
                        mentions.append(label)
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
            let paths = (nu["pathsToReview"]?.arrayValue ?? nu["reviewAbsoluteUris"]?.arrayValue)?
                .compactMap(\.stringValue) ?? []
            if notifyText != nil || !paths.isEmpty {
                plannerPayload = PlannerResponsePayload(
                    response: notifyText ?? "Ready for your review.",
                    referencedFiles: paths
                )
                stepType = .notifyUser
            }
        }

        // Decode runCommand / shellExec + sendCommandInput + requestedInteraction
        var runCmdPayload: RunCommandPayload?
        var interaction: RequestedInteraction?
        if let rc = (obj["runCommand"] ?? obj["shellExec"])?.objectValue {
            let cmdLine = nonEmptyString(rc["commandLine"]?.stringValue)
                ?? nonEmptyString(rc["proposedCommandLine"]?.stringValue)
                ?? nonEmptyString(rc["command"]?.stringValue)
                ?? nonEmptyString(rc["CommandLine"]?.stringValue)
                ?? ""
            let cwd = nonEmptyString(rc["cwd"]?.stringValue)
                ?? nonEmptyString(rc["Cwd"]?.stringValue)
                ?? "~"
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
        } else if let sci = obj["sendCommandInput"]?.objectValue {
            let inputText = nonEmptyString(sci["input"]?.stringValue)
                ?? nonEmptyString(sci["commandLine"]?.stringValue)
                ?? ""
            if !inputText.isEmpty {
                runCmdPayload = RunCommandPayload(
                    commandId: sci["commandId"]?.stringValue ?? "stdin-\(stepIndex)",
                    commandLine: inputText,
                    proposedCommandLine: inputText,
                    cwd: "~"
                )
            }
            if stepType == .unspecified {
                stepType = .sendCommandInput
            }
        }

        if let reqInt = obj["requestedInteraction"]?.objectValue {
            interaction = decodeJSONRequestedInteraction(
                reqInt,
                fallbackCommandLine: runCmdPayload?.proposedCommandLine ?? runCmdPayload?.commandLine,
                fallbackCwd: runCmdPayload?.cwd
            )
            if interaction?.kind == .runCommand, let spec = interaction?.runCommand {
                if runCmdPayload == nil {
                    runCmdPayload = RunCommandPayload(
                        commandId: "cmd-\(stepIndex)",
                        commandLine: spec.proposedCommandLine,
                        proposedCommandLine: spec.proposedCommandLine,
                        cwd: spec.cwd
                    )
                } else if runCmdPayload?.commandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
                          !spec.proposedCommandLine.isEmpty {
                    runCmdPayload?.commandLine = spec.proposedCommandLine
                    runCmdPayload?.proposedCommandLine = spec.proposedCommandLine
                }
            }
        }

        if interaction == nil && (stepStatus == .waiting || stepStatus == .blocked),
           let rc = runCmdPayload,
           stepType == .runCommand {
            interaction = RequestedInteraction(
                kind: .runCommand,
                runCommand: RunCommandInteractionSpec(
                    proposedCommandLine: rc.proposedCommandLine ?? rc.commandLine,
                    cwd: rc.cwd
                ),
                rawMemberKey: "runCommand"
            )
        }

        var viewFilePayload: ViewFilePayload?
        let vfCandidate = obj["viewFile"]?.objectValue
            ?? obj["viewFileOutline"]?.objectValue
            ?? obj["viewCodeItem"]?.objectValue
        if let vf = vfCandidate,
           let uri = nonEmptyString(vf["fileUri"]?.stringValue)
            ?? nonEmptyString(vf["absolutePathUri"]?.stringValue)
            ?? nonEmptyString(vf["absolutePath"]?.stringValue)
            ?? nonEmptyString(vf["path"]?.stringValue) {
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
        } else if let ld = obj["listDirectory"]?.objectValue,
                  let uri = nonEmptyString(ld["directoryPathUri"]?.stringValue)
                    ?? nonEmptyString(ld["directoryPath"]?.stringValue)
                    ?? nonEmptyString(ld["absolutePathUri"]?.stringValue)
                    ?? nonEmptyString(ld["path"]?.stringValue) {
            viewFilePayload = ViewFilePayload(fileUri: uri, startLine: 1, endLine: 1)
            if stepType == .unspecified { stepType = .listDirectory }
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
                ?? nonEmptyString(sc["searchPathUri"]?.stringValue)
                ?? "."
            let count = sc["results"]?.arrayValue?.count ?? sc["matchCount"]?.intValue ?? 0
            searchPayload = SearchPayload(query: query, scopeDirectory: scope, matchCount: count)
            if stepType == .unspecified { stepType = .search }
        }

        var codeActionPayload: CodeActionPayload?
        let caCandidate: [String: JSONValue]? = [
            obj["codeAction"],
            obj["replaceFileContent"],
            obj["multiReplaceFileContent"],
            obj["writeToFile"],
            obj["fileChange"]
        ].compactMap { $0?.objectValue }.first
        if let ca = caCandidate {
            let actionSpec = ca["actionSpec"]?.objectValue
            let createFileSpec = actionSpec?["createFile"]?.objectValue
            let directUriKeys = [
                "targetFileUri", "fileUri", "targetFile", "TargetFile",
                "absoluteUri", "absolutePathUri", "absolutePath", "filePath", "path"
            ]
            var uri: String? = nil
            for key in directUriKeys {
                if let candidate = nonEmptyString(ca[key]?.stringValue) {
                    uri = candidate
                    break
                }
            }
            if uri == nil {
                let specObjects: [[String: JSONValue]?] = [
                    createFileSpec,
                    actionSpec?["insertBlock"]?.objectValue,
                    actionSpec?["editFile"]?.objectValue,
                    actionSpec?["replaceFileContent"]?.objectValue
                ]
                for spec in specObjects {
                    if let candidate = nonEmptyString(spec?["path"]?.objectValue?["absoluteUri"]?.stringValue) {
                        uri = candidate
                        break
                    }
                }
            }
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

        var subagentPayload: SubagentPayload?
        if let sub = (obj["subagentInvocation"] ?? obj["subagent"])?.objectValue {
            subagentPayload = SubagentPayload(
                subagentId: nonEmptyString(sub["subagentId"]?.stringValue) ?? "sub-\(stepIndex)",
                role: nonEmptyString(sub["role"]?.stringValue) ?? "Subagent",
                typeName: nonEmptyString(sub["typeName"]?.stringValue) ?? "self",
                modelLabel: nonEmptyString(sub["modelLabel"]?.stringValue) ?? "Gemini 4 Hydrogen",
                status: stepStatus,
                summary: nonEmptyString(sub["summary"]?.stringValue) ?? "",
                waitingApprovalTitle: nonEmptyString(sub["waitingApprovalTitle"]?.stringValue)
            )
            if stepType == .unspecified { stepType = .subagentInvocation }
        }

        var dynamicWorkflowPayload: DynamicWorkflowPayload?
        if let wf = obj["dynamicWorkflow"]?.objectValue {
            let phaseNames = wf["phaseNames"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let phases = phaseNames.enumerated().map { idx, name in
                WorkflowPhaseItem(id: "phase-\(idx)", name: name, isCompleted: false)
            }
            dynamicWorkflowPayload = DynamicWorkflowPayload(
                workflowId: nonEmptyString(wf["workflowId"]?.stringValue) ?? "wf-\(stepIndex)",
                description: nonEmptyString(wf["description"]?.stringValue) ?? "Dynamic Workflow",
                pythonScript: nonEmptyString(wf["pythonScript"]?.stringValue) ?? "",
                currentPhase: nonEmptyString(wf["currentPhase"]?.stringValue) ?? phaseNames.first ?? "Phase 1",
                completedAgents: wf["completedAgents"]?.intValue ?? 0,
                totalAgents: wf["totalAgents"]?.intValue ?? max(1, phases.count),
                phases: phases,
                requiresScriptApproval: stepStatus == .waiting || stepStatus == .blocked
            )
            if stepType == .unspecified { stepType = .dynamicWorkflow }
        }

        var swarmBoardPayload: SwarmBoardPayload?
        if let sw = obj["swarmBoard"]?.objectValue {
            let memberNames = sw["memberNames"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let members = memberNames.map { SwarmMemberItem(name: $0, role: "Specialist", status: stepStatus) }
            swarmBoardPayload = SwarmBoardPayload(
                swarmId: nonEmptyString(sw["swarmId"]?.stringValue) ?? "swarm-\(stepIndex)",
                title: nonEmptyString(sw["title"]?.stringValue) ?? "Swarm Team",
                status: stepStatus,
                members: members,
                posts: []
            )
            if stepType == .unspecified { stepType = .swarmBoard }
        }

        var mcpToolCallPayload: McpToolCallPayload?
        if let mcp = (obj["mcpToolCall"] ?? obj["mcp"])?.objectValue {
            mcpToolCallPayload = McpToolCallPayload(
                serverName: nonEmptyString(mcp["serverName"]?.stringValue) ?? "mcp",
                toolName: nonEmptyString(mcp["toolName"]?.stringValue) ?? "tool",
                pluginName: nonEmptyString(mcp["pluginName"]?.stringValue),
                argumentsPreview: nonEmptyString(mcp["argumentsPreview"]?.stringValue) ?? "{}",
                resultPreview: nonEmptyString(mcp["resultPreview"]?.stringValue),
                isError: stepStatus == .error
            )
            if stepType == .unspecified { stepType = .mcpToolCall }
        }

        if (stepType == .plannerResponse || stepType == .notifyUser)
            && plannerPayload == nil
            && (stepStatus == .inProgress || stepStatus == .pending) {
            plannerPayload = PlannerResponsePayload(response: "")
        }

        let createdDate = Self.parseProtoTimestamp(obj["metadata"]?.objectValue?["createdAt"] ?? obj["createdAt"]) ?? Date()

        // Forward compatibility: if a newer Desktop host emits a step type we don't recognize yet,
        // preserve its raw type name & extract a readable fallback summary from any unknown sub-object.
        var rawTypeName: String? = nil
        var fallbackSummary: String? = nil
        if stepType == .unspecified {
            let ignoredHousekeeping: Set<String> = [
                "CORTEX_STEP_TYPE_UNSPECIFIED",
                "UNSPECIFIED",
                "CORTEX_STEP_TYPE_CHECKPOINT",
                "CORTEX_STEP_TYPE_EPHEMERAL_MESSAGE",
                "CORTEX_STEP_TYPE_CONVERSATION_HISTORY"
            ]
            if let rawStr = rawTypeInputString, !ignoredHousekeeping.contains(rawStr.uppercased()) {
                rawTypeName = rawStr
            } else if let rawInt = rawTypeInputInt, rawInt > 0 {
                rawTypeName = "STEP_TYPE_\(rawInt)"
            }
            if plannerPayload == nil {
                let ignoredStepKeys: Set<String> = [
                    "type", "status", "stepIndex", "metadata", "createdAt",
                    "requestedInteraction", "id", "cascadeId", "trajectoryId"
                ]
                for key in obj.keys.sorted() where !ignoredStepKeys.contains(key) {
                    if let summary = extractReadableSummary(from: obj[key]) {
                        fallbackSummary = summary
                        if rawTypeName == nil {
                            rawTypeName = key
                        }
                        break
                    }
                }
            }
        }

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
            recordedModelId: recordedModelId,
            subagent: subagentPayload,
            dynamicWorkflow: dynamicWorkflowPayload,
            swarmBoard: swarmBoardPayload,
            mcpToolCall: mcpToolCallPayload,
            rawTypeName: rawTypeName,
            fallbackSummary: fallbackSummary
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

        let nestedUserTitle = Self.extractSummaryStepUserPrompt(obj["firstUserInputStep"]?.objectValue)
            ?? Self.extractSummaryStepUserPrompt(obj["latestUserInputStep"]?.objectValue)
        let nestedTaskName = obj["latestTaskBoundaryStep"]?.objectValue?["step"]?.objectValue?["taskBoundary"]?.objectValue?["taskName"]?.stringValue

        let candidateTitles: [String?] = [
            annotations?["title"]?.stringValue,
            annotations?["customTitle"]?.stringValue,
            annotations?["name"]?.stringValue,
            annotations?["summary"]?.stringValue,
            obj["summary"]?.stringValue,
            obj["title"]?.stringValue,
            obj["displayName"]?.stringValue,
            obj["name"]?.stringValue,
            obj["conversationTitle"]?.stringValue,
            obj["sessionTitle"]?.stringValue,
            trajMeta?["title"]?.stringValue,
            trajMeta?["summary"]?.stringValue,
            trajMeta?["name"]?.stringValue,
            obj["firstUserInput"]?.stringValue,
            obj["query"]?.stringValue,
            obj["prompt"]?.stringValue,
            nestedUserTitle,
            nestedTaskName
        ]
        let resolvedTitle = candidateTitles
            .compactMap { CascadeSummaryTitleResolver.cleanSingleLine($0) }
            .first(where: { !CascadeSummaryTitleResolver.isPlaceholderTitle($0) })

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
        let hasResolvedTitle = (resolvedTitle != nil)
        let title = resolvedTitle.map { CascadeSummaryTitleResolver.truncateTitle($0, maxLength: 96) }
            ?? CascadeSummaryTitleResolver.placeholderTitle
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
            lastUserViewTime: lastViewedDate,
            hasResolvedTitle: hasResolvedTitle
        )
    }

    private static func extractSummaryStepUserPrompt(_ wrapper: [String: JSONValue]?) -> String? {
        guard let wrapper else { return nil }
        let stepObj = wrapper["step"]?.objectValue ?? wrapper
        guard let userInput = stepObj["userInput"]?.objectValue else { return nil }
        let direct = userInput["userResponse"]?.stringValue
            ?? userInput["query"]?.stringValue
            ?? userInput["text"]?.stringValue
        if let direct, !direct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return direct
        }
        guard let items = userInput["items"]?.arrayValue else { return nil }
        for item in items {
            if let text = item.objectValue?["text"]?.stringValue,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
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

    public struct AgentStateStepsUpdate: Sendable {
        public let steps: [CascadeStep]
        public let totalLength: Int?
        public let hasMainTrajectoryUpdate: Bool
        public let runStatus: String?

        public init(
            steps: [CascadeStep] = [],
            totalLength: Int? = nil,
            hasMainTrajectoryUpdate: Bool = false,
            runStatus: String? = nil
        ) {
            self.steps = steps
            self.totalLength = totalLength
            self.hasMainTrajectoryUpdate = hasMainTrajectoryUpdate
            self.runStatus = runStatus
        }
    }

    /// Decodes a `StreamAgentStateUpdatesResponse` frame (`update.mainTrajectoryUpdate.stepsUpdate`
    /// with sparse `indices`, `steps`, and `totalLength`, plus defensive fallback layouts).
    public static func decodeAgentStateStepsUpdate(
        _ event: [String: JSONValue],
        cascadeId: String
    ) -> AgentStateStepsUpdate {
        let updateObj = event["update"]?.objectValue ?? event
        let runStatus = nonEmptyString(updateObj["status"]?.stringValue)
            ?? nonEmptyString(updateObj["executableStatus"]?.stringValue)
            ?? nonEmptyString(updateObj["executable_status"]?.stringValue)

        let mainTraj = updateObj["mainTrajectoryUpdate"]?.objectValue
            ?? updateObj["main_trajectory_update"]?.objectValue
        let stepsUpdate = mainTraj?["stepsUpdate"]?.objectValue
            ?? mainTraj?["steps_update"]?.objectValue
            ?? updateObj["stepsUpdate"]?.objectValue
            ?? updateObj["steps_update"]?.objectValue

        let hasMainTrajectoryUpdate = mainTraj != nil
            || stepsUpdate != nil
            || updateObj["trajectory"]?.objectValue != nil
            || updateObj["steps"]?.arrayValue != nil

        let rawSteps = stepsUpdate?["steps"]?.arrayValue
            ?? mainTraj?["steps"]?.arrayValue
            ?? updateObj["trajectory"]?.objectValue?["steps"]?.arrayValue
            ?? updateObj["steps"]?.arrayValue
            ?? []

        let indices: [Int] = (stepsUpdate?["indices"]?.arrayValue ?? []).compactMap { val in
            if let i = val.intValue { return i }
            if let s = val.stringValue { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return nil
        }

        func parseIntValue(_ value: JSONValue?) -> Int? {
            if let i = value?.intValue { return i }
            if let s = value?.stringValue { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return nil
        }

        let totalLength = parseIntValue(stepsUpdate?["totalLength"])
            ?? parseIntValue(stepsUpdate?["total_length"])
            ?? parseIntValue(mainTraj?["totalLength"])
            ?? parseIntValue(mainTraj?["total_length"])

        let useExplicitIndices = !indices.isEmpty && indices.count == rawSteps.count
        var decoded: [CascadeStep] = []
        decoded.reserveCapacity(rawSteps.count)
        for (idx, stepVal) in rawSteps.enumerated() {
            let targetIdx = useExplicitIndices ? indices[idx] : idx
            if var step = decodeJSONStep(stepVal, cascadeId: cascadeId, fallbackIndex: targetIdx) {
                if useExplicitIndices && step.stepIndex != targetIdx {
                    step.stepIndex = targetIdx
                }
                decoded.append(step)
            }
        }

        return AgentStateStepsUpdate(
            steps: decoded,
            totalLength: totalLength,
            hasMainTrajectoryUpdate: hasMainTrajectoryUpdate,
            runStatus: runStatus
        )
    }
}
