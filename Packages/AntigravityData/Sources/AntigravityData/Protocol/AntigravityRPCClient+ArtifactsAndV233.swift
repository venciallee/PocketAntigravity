import Foundation

/// Artifacts, Plan/Diff review comments, Git VCS, Overview, Side Questions, Permissions, and Customizations RPCs.
extension AntigravityRPCClient {
    // MARK: - Artifacts & Turn Diff RPC (`UE11`, `UE12` + Git VCS)

    public func getArtifactSnapshots(cascadeId: String, instanceUuidOverride: String? = nil) async throws -> [ArtifactSnapshot] {
        let res = try await callUnaryJSON(
            method: "GetArtifactSnapshots",
            body: ["cascadeId": .string(cascadeId)],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 8.0
        )
        let arr = res["artifacts"]?.arrayValue
            ?? res["artifactSnapshots"]?.arrayValue
            ?? res["snapshots"]?.arrayValue
            ?? []
        return arr.compactMap { item -> ArtifactSnapshot? in
            guard let obj = item.objectValue else { return nil }
            let path = obj["artifactPath"]?.stringValue
                ?? obj["path"]?.stringValue
                ?? obj["fileUri"]?.stringValue
                ?? obj["uri"]?.stringValue
            guard let path, !path.isEmpty else { return nil }
            let kind: ArtifactKind = {
                if let rawKind = obj["kind"]?.stringValue,
                   let parsed = ArtifactKind(rawValue: rawKind) {
                    return parsed
                }
                let lower = path.lowercased()
                if lower.hasSuffix(".pdf") { return .pdfDocument }
                if lower.hasSuffix(".ipynb") { return .jupyterNotebook }
                if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".webp") {
                    return .imageAsset
                }
                if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".webm") {
                    return .videoAsset
                }
                if lower.hasSuffix(".html") || lower.hasSuffix(".htm") { return .generativeUIHTML }
                if lower.hasSuffix(".url.json") { return .urlBookmark }
                if lower.contains("walkthrough") { return .walkthrough }
                if lower.contains("task") { return .taskList }
                return .implementationPlan
            }()
            let content = obj["content"]?.stringValue
                ?? obj["textContent"]?.stringValue
                ?? obj["body"]?.stringValue
                ?? ""
            return ArtifactSnapshot(
                artifactPath: path,
                title: obj["title"]?.stringValue ?? (path as NSString).lastPathComponent,
                summary: obj["summary"]?.stringValue ?? "",
                kind: kind,
                content: content,
                requestFeedback: obj["requestFeedback"]?.boolValue ?? false,
                userFacing: obj["userFacing"]?.boolValue ?? true,
                version: obj["version"]?.intValue ?? 1
            )
        }
    }

    /// Resolves a host-local `file:///...` artifact (such as an `<agent-embed src="file:///.../fig4.html">`
    /// widget or generated image) through Companion Bridge `ReadArtifactFile`, `GetArtifactSnapshots`,
    /// or `GetRevisionArtifact` across both Direct LAN and Cloud Relay channels.
    public func fetchRemoteArtifactResource(
        uri: String,
        cascadeId: String,
        instanceUuidOverride: String? = nil
    ) async -> ResolvedEmbedResource? {
        let normalizedTarget = ResolvedEmbedResource.normalizePath(uri)
        let targetBaseName = (normalizedTarget as NSString).lastPathComponent.lowercased()
        guard !normalizedTarget.isEmpty else { return nil }

        // 1. Companion Bridge / Direct LAN `ReadArtifactFile` (supports HTML, SVG, MD, PNG/JPG/WebP/GIF)
        if channel == .directHost {
            if let res = try? await callUnaryJSON(
                method: "ReadArtifactFile",
                body: [
                    "uri": .string(uri),
                    "path": .string(normalizedTarget),
                    "cascadeId": .string(cascadeId)
                ],
                timeoutInterval: 8.0
            ), res["ok"]?.boolValue != false,
               let rawContent = res["content"]?.stringValue,
               !rawContent.isEmpty {
                let mime = res["mimeType"]?.stringValue ?? ResolvedEmbedResource.inferredMimeType(for: uri)
                let encoding = (res["encoding"]?.stringValue ?? "utf-8").lowercased()
                if encoding == "base64", let data = Data(base64Encoded: rawContent, options: .ignoreUnknownCharacters) {
                    let text = mime.lowercased().hasPrefix("text/") || mime.lowercased().contains("svg")
                        ? String(data: data, encoding: .utf8)
                        : nil
                    return ResolvedEmbedResource(
                        uri: uri,
                        normalizedPath: normalizedTarget,
                        mimeType: mime,
                        textContent: text,
                        binaryData: data,
                        source: .remoteHost
                    )
                } else {
                    return ResolvedEmbedResource(
                        uri: uri,
                        normalizedPath: normalizedTarget,
                        mimeType: mime,
                        textContent: rawContent,
                        binaryData: Data(rawContent.utf8),
                        source: .remoteHost
                    )
                }
            }
        }

        // 2. Upstream `LanguageServerService/GetArtifactSnapshots` (works over Direct LAN & Official Cloud Relay!)
        if !cascadeId.isEmpty,
           let snapshots = try? await getArtifactSnapshots(cascadeId: cascadeId, instanceUuidOverride: instanceUuidOverride) {
            if let matched = snapshots.first(where: { snap in
                let snapNorm = ResolvedEmbedResource.normalizePath(snap.artifactPath)
                if snapNorm == normalizedTarget { return true }
                if !targetBaseName.isEmpty && (snapNorm as NSString).lastPathComponent.lowercased() == targetBaseName {
                    return true
                }
                return false
            }), !matched.content.isEmpty {
                return ResolvedEmbedResource(
                    uri: uri,
                    normalizedPath: normalizedTarget,
                    mimeType: ResolvedEmbedResource.inferredMimeType(for: uri),
                    textContent: matched.content,
                    binaryData: Data(matched.content.utf8),
                    source: .artifactSnapshot
                )
            }
        }

        // 3. Upstream `LanguageServerService/GetRevisionArtifact` fallback
        if !cascadeId.isEmpty {
            let revBodies: [[String: JSONValue]] = [
                ["cascadeId": .string(cascadeId), "artifactPath": .string(normalizedTarget)],
                ["trajectoryId": .string(cascadeId), "fileUri": .string(uri)]
            ]
            for reqBody in revBodies {
                if let res = try? await callUnaryJSON(
                    method: "GetRevisionArtifact",
                    body: reqBody,
                    instanceUuidOverride: instanceUuidOverride,
                    timeoutInterval: 6.0
                ) {
                    let content = res["content"]?.stringValue
                        ?? res["artifact"]?.objectValue?["content"]?.stringValue
                        ?? res["text"]?.stringValue
                    if let content, !content.isEmpty {
                        return ResolvedEmbedResource(
                            uri: uri,
                            normalizedPath: normalizedTarget,
                            mimeType: ResolvedEmbedResource.inferredMimeType(for: uri),
                            textContent: content,
                            binaryData: Data(content.utf8),
                            source: .artifactSnapshot
                        )
                    }
                }
            }
        }

        return nil
    }

    public func sendPlanReviewComments(cascadeId: String, comments: [PlanInlineComment]) async throws {
        let encodedComments: [JSONValue] = comments.map { c in
            .object([
                "id": .string(c.id),
                "targetFilePath": .string(c.targetFilePath),
                "quotedSpan": .string(c.quotedSpan),
                "body": .string(c.body)
            ])
        }
        _ = try await callUnaryJSON(
            method: "SendPlanReviewComments",
            body: [
                "cascadeId": .string(cascadeId),
                "comments": .array(encodedComments)
            ]
        )
    }

    public func getTurnDiff(
        cascadeId: String,
        turnNumber: Int?,
        compareMode: DiffCompareMode = .turn
    ) async throws -> [FilePatchDiff] {
        var body: [String: JSONValue] = [
            "cascadeId": .string(cascadeId),
            "compareMode": .string(compareMode.rawValue)
        ]
        if let turnNumber {
            body["turnNumber"] = .int(turnNumber)
        }
        let res = try await callUnaryJSON(method: "GetTurnDiff", body: body)
        return Self.parseFilePatchDiffs(from: res, defaultTurn: turnNumber ?? 1, defaultScope: compareMode)
    }

    internal static func parseFilePatchDiffs(
        from response: [String: JSONValue],
        defaultTurn: Int = 1,
        defaultScope: DiffCompareMode = .turn
    ) -> [FilePatchDiff] {
        guard let rawFiles = response["files"]?.arrayValue ?? response["diffs"]?.arrayValue else {
            return []
        }
        return rawFiles.compactMap { entry -> FilePatchDiff? in
            guard let obj = entry.objectValue,
                  let path = nonEmptyString(obj["filePath"]?.stringValue ?? obj["path"]?.stringValue) else {
                return nil
            }
            let turn = obj["turnNumber"]?.intValue ?? defaultTurn
            let statusLetter = GitFileStatusLetter(
                rawValue: (obj["statusLetter"]?.stringValue ?? obj["status"]?.stringValue ?? "M").uppercased()
            ) ?? .modified
            let isStaged = obj["isStaged"]?.boolValue ?? false
            let isReviewed = obj["isReviewed"]?.boolValue ?? false
            let scope = DiffCompareMode(rawValue: obj["compareScope"]?.stringValue ?? "") ?? defaultScope
            let hunkHeader = obj["hunkHeader"]?.stringValue ?? "@@ -1,1 +1,1 @@"

            var parsedLines: [DiffLine] = []
            if let rawLines = obj["lines"]?.arrayValue {
                for (idx, lineVal) in rawLines.enumerated() {
                    guard let lObj = lineVal.objectValue else { continue }
                    let kindStr = (lObj["kind"]?.stringValue ?? "context").lowercased()
                    let lineKind: DiffLine.Kind
                    switch kindStr {
                    case "addition", "add", "+": lineKind = .addition
                    case "deletion", "del", "-": lineKind = .deletion
                    case "hunkheader", "hunk": lineKind = .hunkHeader
                    default: lineKind = .context
                    }
                    parsedLines.append(
                        DiffLine(
                            id: lObj["id"]?.intValue ?? idx,
                            kind: lineKind,
                            oldLineNumber: lObj["oldLineNumber"]?.intValue,
                            newLineNumber: lObj["newLineNumber"]?.intValue,
                            text: lObj["text"]?.stringValue ?? "",
                            wordHighlightRange: lObj["wordHighlightRange"]?.stringValue
                        )
                    )
                }
            } else if let rawHunks = obj["hunks"]?.arrayValue {
                var runningId = 0
                for hVal in rawHunks {
                    guard let hObj = hVal.objectValue else { continue }
                    if let hdr = nonEmptyString(hObj["header"]?.stringValue) {
                        parsedLines.append(DiffLine(id: runningId, kind: .hunkHeader, text: hdr))
                        runningId += 1
                    }
                    for lineVal in hObj["lines"]?.arrayValue ?? [] {
                        guard let lObj = lineVal.objectValue else { continue }
                        let kindStr = (lObj["kind"]?.stringValue ?? "context").lowercased()
                        let lineKind: DiffLine.Kind = (kindStr == "addition" || kindStr == "+")
                            ? .addition
                            : ((kindStr == "deletion" || kindStr == "-") ? .deletion : .context)
                        parsedLines.append(
                            DiffLine(
                                id: runningId,
                                kind: lineKind,
                                oldLineNumber: lObj["oldLineNumber"]?.intValue,
                                newLineNumber: lObj["newLineNumber"]?.intValue,
                                text: lObj["text"]?.stringValue ?? ""
                            )
                        )
                        runningId += 1
                    }
                }
            } else if let rawPatch = obj["patch"]?.stringValue ?? obj["unifiedDiff"]?.stringValue {
                parsedLines = parseUnifiedDiffText(rawPatch)
            }

            let additions = obj["additions"]?.intValue ?? parsedLines.filter { $0.kind == .addition }.count
            let deletions = obj["deletions"]?.intValue ?? parsedLines.filter { $0.kind == .deletion }.count

            return FilePatchDiff(
                turnNumber: turn,
                filePath: path,
                additions: additions,
                deletions: deletions,
                hunkHeader: hunkHeader,
                isReviewed: isReviewed,
                statusLetter: statusLetter,
                isStaged: isStaged,
                compareScope: scope,
                lines: parsedLines
            )
        }
    }

    internal static func parseUnifiedDiffText(_ unifiedDiff: String) -> [DiffLine] {
        var result: [DiffLine] = []
        var oldNum = 1
        var newNum = 1
        for (idx, rawLine) in unifiedDiff.components(separatedBy: "\n").enumerated() {
            if rawLine.hasPrefix("@@") {
                result.append(DiffLine(id: idx, kind: .hunkHeader, text: rawLine))
            } else if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                result.append(DiffLine(id: idx, kind: .addition, oldLineNumber: nil, newLineNumber: newNum, text: String(rawLine.dropFirst())))
                newNum += 1
            } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                result.append(DiffLine(id: idx, kind: .deletion, oldLineNumber: oldNum, newLineNumber: nil, text: String(rawLine.dropFirst())))
                oldNum += 1
            } else if !rawLine.hasPrefix("---") && !rawLine.hasPrefix("+++") {
                let content = rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine
                result.append(DiffLine(id: idx, kind: .context, oldLineNumber: oldNum, newLineNumber: newNum, text: content))
                oldNum += 1
                newNum += 1
            }
        }
        return result
    }

    public func revertDiffHunk(cascadeId: String, filePath: String, hunkHeader: String? = nil) async throws {
        var body: [String: JSONValue] = [
            "cascadeId": .string(cascadeId),
            "filePath": .string(filePath)
        ]
        if let hunkHeader {
            body["hunkHeader"] = .string(hunkHeader)
        }
        _ = try await callUnaryJSON(method: "RevertDiffHunk", body: body)
    }

    public func sendDiffReviewComments(cascadeId: String, comments: [DiffLineComment]) async throws {
        let encoded: [JSONValue] = comments.map { c in
            .object([
                "id": .string(c.id),
                "filePath": .string(c.filePath),
                "lineNumber": .int(c.lineNumber),
                "body": .string(c.body)
            ])
        }
        _ = try await callUnaryJSON(
            method: "SendDiffReviewComments",
            body: [
                "cascadeId": .string(cascadeId),
                "comments": .array(encoded)
            ]
        )
    }

    // MARK: - Antigravity 2.0 (v2.33) Git VCS, Overview, Side Question, Permissions & Customizations RPCs

    public func gitStageFile(cascadeId: String, filePath: String) async throws {
        _ = try await callUnaryJSON(
            method: "GitStageFile",
            body: ["cascadeId": .string(cascadeId), "filePath": .string(filePath)]
        )
    }

    public func gitUnstageFile(cascadeId: String, filePath: String) async throws {
        _ = try await callUnaryJSON(
            method: "GitUnstageFile",
            body: ["cascadeId": .string(cascadeId), "filePath": .string(filePath)]
        )
    }

    public func gitDiscardFile(cascadeId: String, filePath: String) async throws {
        _ = try await callUnaryJSON(
            method: "GitDiscardFile",
            body: ["cascadeId": .string(cascadeId), "filePath": .string(filePath)]
        )
    }

    public func gitCommitChanges(cascadeId: String, draft: GitCommitDraft) async throws -> GitCommitResult {
        let res = try await callUnaryJSON(
            method: "GitCommit",
            body: [
                "cascadeId": .string(cascadeId),
                "message": .string(draft.message),
                "includeUnstaged": .bool(draft.includeUnstaged),
                "amend": .bool(draft.amend)
            ]
        )
        return GitCommitResult(
            commitSha: res["commitSha"]?.stringValue ?? String(UUID().uuidString.prefix(7)).lowercased(),
            commitMessage: res["commitMessage"]?.stringValue ?? draft.message,
            branchName: res["branchName"]?.stringValue ?? "main",
            pushed: res["pushed"]?.boolValue ?? false
        )
    }

    public func gitPushBranch(cascadeId: String, branchName: String) async throws -> Bool {
        let res = try await callUnaryJSON(
            method: "GitPush",
            body: ["cascadeId": .string(cascadeId), "branchName": .string(branchName)]
        )
        return res["pushed"]?.boolValue ?? res["ok"]?.boolValue ?? true
    }

    public func fetchConversationOverview(cascadeId: String) async throws -> ConversationOverviewSnapshot {
        let res = try await callUnaryJSON(
            method: "GetConversationOverview",
            body: ["cascadeId": .string(cascadeId)]
        )
        let subagents: [SubagentPayload] = (res["subagents"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue else { return nil }
            return SubagentPayload(
                subagentId: obj["subagentId"]?.stringValue ?? obj["id"]?.stringValue ?? UUID().uuidString,
                role: obj["role"]?.stringValue ?? "Subagent",
                typeName: obj["typeName"]?.stringValue ?? "self",
                modelLabel: obj["modelLabel"]?.stringValue ?? "Gemini 4 Hydrogen",
                status: CortexStepStatus.from(jsonName: obj["status"]?.stringValue ?? "IN_PROGRESS"),
                summary: obj["summary"]?.stringValue ?? "",
                waitingApprovalTitle: obj["waitingApprovalTitle"]?.stringValue
            )
        }
        let bgTasks: [BackgroundTaskItem] = (res["backgroundTasks"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue else { return nil }
            return BackgroundTaskItem(
                id: obj["id"]?.stringValue ?? UUID().uuidString,
                title: obj["title"]?.stringValue ?? "Background Task",
                commandSummary: obj["commandSummary"]?.stringValue ?? "",
                status: CortexStepStatus.from(jsonName: obj["status"]?.stringValue ?? "IN_PROGRESS"),
                elapsedLabel: obj["elapsedLabel"]?.stringValue ?? "running",
                canCancel: obj["canCancel"]?.boolValue ?? true
            )
        }
        let goals: [ConversationGoalItem] = (res["goals"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue else { return nil }
            return ConversationGoalItem(
                id: obj["id"]?.stringValue ?? UUID().uuidString,
                title: obj["title"]?.stringValue ?? "Goal",
                status: CortexStepStatus.from(jsonName: obj["status"]?.stringValue ?? "IN_PROGRESS"),
                progressText: obj["progressText"]?.stringValue ?? "Active"
            )
        }
        let prs: [GitHubPullRequestInfo] = (res["pullRequests"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue,
                  let repo = obj["ownerRepo"]?.stringValue,
                  let num = obj["number"]?.intValue else { return nil }
            return GitHubPullRequestInfo(
                ownerRepo: repo,
                number: num,
                title: obj["title"]?.stringValue ?? "PR #\(num)",
                state: GitHubPullRequestInfo.PRState(rawValue: (obj["state"]?.stringValue ?? "open").lowercased()) ?? .open,
                checksSummary: obj["checksSummary"]?.stringValue ?? "Checks passing",
                url: obj["url"]?.stringValue ?? "https://github.com/\(repo)/pull/\(num)",
                additions: obj["additions"]?.intValue ?? 0,
                deletions: obj["deletions"]?.intValue ?? 0
            )
        }
        let modifiedFiles = (res["modifiedFiles"]?.arrayValue ?? []).compactMap(\.stringValue)
        let docLinks = (res["documentLinks"]?.arrayValue ?? []).compactMap(\.stringValue)

        return ConversationOverviewSnapshot(
            reviewAdditions: res["reviewAdditions"]?.intValue ?? 0,
            reviewDeletions: res["reviewDeletions"]?.intValue ?? 0,
            modifiedFiles: modifiedFiles,
            subagents: subagents,
            backgroundTasks: bgTasks,
            goals: goals,
            artifacts: [],
            documentLinks: docLinks,
            pullRequests: prs
        )
    }

    public func cancelBackgroundTask(cascadeId: String, taskId: String) async throws {
        _ = try await callUnaryJSON(
            method: "CancelBackgroundTask",
            body: ["cascadeId": .string(cascadeId), "taskId": .string(taskId)]
        )
    }

    public func stopSubagent(cascadeId: String, subagentId: String) async throws {
        _ = try await callUnaryJSON(
            method: "StopSubagent",
            body: ["cascadeId": .string(cascadeId), "subagentId": .string(subagentId)]
        )
    }

    public func sendSideQuestion(
        cascadeId: String,
        question: String,
        threadId: String
    ) async throws -> SideQuestionMessage {
        let res = try await callUnaryJSON(
            method: "SendSideQuestion",
            body: [
                "cascadeId": .string(cascadeId),
                "threadId": .string(threadId),
                "question": .string(question)
            ]
        )
        let answer = Self.nonEmptyString(res["answer"]?.stringValue)
            ?? Self.nonEmptyString(res["response"]?.stringValue)
            ?? "Read-only side answer for: \(question)"
        return SideQuestionMessage(isUser: false, text: answer)
    }

    public func revertConversationToStep(cascadeId: String, stepIndex: Int) async throws {
        _ = try await callUnaryJSON(
            method: "RevertConversationToStep",
            body: [
                "cascadeId": .string(cascadeId),
                "stepIndex": .int(stepIndex)
            ]
        )
    }

    public func setConversationPermissionPreset(cascadeId: String, preset: AgentPermissionPreset) async throws {
        _ = try await callUnaryJSON(
            method: "SetPermissionPreset",
            body: [
                "cascadeId": .string(cascadeId),
                "preset": .string(preset.wireValue),
                "label": .string(preset.rawValue)
            ]
        )
    }

    public func fetchCustomizationsCatalog() async throws -> CustomizationsCatalog {
        let res = try await callUnaryJSON(method: "GetCustomizationsCatalog", body: [:])
        let skills: [SkillSummary] = (res["skills"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue, let name = obj["name"]?.stringValue else { return nil }
            return SkillSummary(
                name: name,
                description: obj["description"]?.stringValue ?? "",
                scope: obj["scope"]?.stringValue ?? "Workspace",
                isEnabled: obj["isEnabled"]?.boolValue ?? true
            )
        }
        let rules: [RuleSummary] = (res["rules"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue, let name = obj["name"]?.stringValue else { return nil }
            return RuleSummary(
                name: name,
                scope: obj["scope"]?.stringValue ?? "Workspace",
                preview: obj["preview"]?.stringValue ?? "",
                isActive: obj["isActive"]?.boolValue ?? true
            )
        }
        let agents = (res["customAgents"]?.arrayValue ?? []).compactMap(\.stringValue)
        let servers: [McpServerStatusItem] = (res["mcpServers"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue, let name = obj["name"]?.stringValue else { return nil }
            let state = McpServerStatusItem.ConnectionState(rawValue: (obj["state"]?.stringValue ?? "connected").lowercased()) ?? .connected
            return McpServerStatusItem(
                name: name,
                transport: obj["transport"]?.stringValue ?? "stdio",
                state: state,
                toolCount: obj["toolCount"]?.intValue ?? 0,
                errorMessage: obj["errorMessage"]?.stringValue,
                missingCommandHint: obj["missingCommandHint"]?.stringValue,
                oauthConnected: obj["oauthConnected"]?.boolValue ?? true
            )
        }
        let plugins: [PluginCatalogItem] = (res["plugins"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue,
                  let id = obj["id"]?.stringValue,
                  let name = obj["name"]?.stringValue else { return nil }
            return PluginCatalogItem(
                id: id,
                name: name,
                provider: obj["provider"]?.stringValue ?? name,
                description: obj["description"]?.stringValue ?? "",
                isInstalled: obj["isInstalled"]?.boolValue ?? false,
                isEnabled: obj["isEnabled"]?.boolValue ?? true,
                isFeaturedPartner: obj["isFeaturedPartner"]?.boolValue ?? false,
                accountSignedIn: obj["accountSignedIn"]?.boolValue ?? false,
                mcpStartupError: obj["mcpStartupError"]?.stringValue,
                suggestedPrompts: (obj["suggestedPrompts"]?.arrayValue ?? []).compactMap(\.stringValue)
            )
        }
        let hooks: [LifecycleHookItem] = (res["hooks"]?.arrayValue ?? []).compactMap { val in
            guard let obj = val.objectValue,
                  let eventName = obj["eventName"]?.stringValue,
                  let cmd = obj["command"]?.stringValue else { return nil }
            return LifecycleHookItem(
                id: obj["id"]?.stringValue ?? UUID().uuidString,
                eventName: eventName,
                matcher: obj["matcher"]?.stringValue ?? "*",
                command: cmd,
                timeoutSeconds: obj["timeoutSeconds"]?.intValue ?? 60,
                isValid: obj["isValid"]?.boolValue ?? true
            )
        }
        if skills.isEmpty && rules.isEmpty && servers.isEmpty && plugins.isEmpty {
            return CustomizationsCatalog.defaultCatalog
        }
        return CustomizationsCatalog(
            skills: skills,
            rules: rules,
            customAgents: agents.isEmpty ? ["Default"] : agents,
            mcpServers: servers,
            plugins: plugins,
            hooks: hooks
        )
    }

    public func restartMcpServer(serverName: String) async throws {
        _ = try await callUnaryJSON(
            method: "RestartMcpServer",
            body: ["serverName": .string(serverName)]
        )
    }

    public func togglePlugin(pluginId: String, isEnabled: Bool) async throws {
        _ = try await callUnaryJSON(
            method: "TogglePlugin",
            body: ["pluginId": .string(pluginId), "isEnabled": .bool(isEnabled)]
        )
    }

    public func installMarketplacePlugin(pluginId: String) async throws {
        _ = try await callUnaryJSON(
            method: "InstallPlugin",
            body: ["pluginId": .string(pluginId)]
        )
    }

    public func searchAllConversations(query: String) async throws -> [CascadeSummary] {
        let res = try await callUnaryJSON(
            method: "SearchAllConversations",
            body: ["query": .string(query)]
        )
        guard let list = res["trajectories"]?.arrayValue ?? res["results"]?.arrayValue else {
            return []
        }
        let now = Date()
        return list.compactMap { item -> CascadeSummary? in
            guard let obj = item.objectValue,
                  let id = obj["cascadeId"]?.stringValue,
                  let title = obj["title"]?.stringValue else { return nil }
            return CascadeSummary(
                cascadeId: id,
                title: title,
                projectSlug: obj["projectSlug"]?.stringValue ?? "workspace",
                workspaceUri: obj["workspaceUri"]?.stringValue ?? "",
                branchName: obj["branchName"]?.stringValue ?? "main",
                status: CortexStepStatus.from(jsonName: obj["status"]?.stringValue ?? "DONE"),
                stepCount: obj["stepCount"]?.intValue ?? 0,
                updatedAt: now,
                relativeTimeLabel: obj["relativeTimeLabel"]?.stringValue ?? "now",
                statusSubtitle: obj["snippet"]?.stringValue ?? obj["statusSubtitle"]?.stringValue ?? ""
            )
        }
    }
}
