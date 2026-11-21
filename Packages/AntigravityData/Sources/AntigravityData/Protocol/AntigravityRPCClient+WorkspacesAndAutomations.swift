import Foundation

/// Workspace/Project operations and Antigravity 2.0 native Automations sidecar RPCs.
extension AntigravityRPCClient {
    // MARK: - Workspace & Project Operations (`UE01`, `UE04`, `UE05`)

    public func getWorkspaceInfos(
        instanceUuidOverride: String? = nil,
        originHostName: String? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> [WorkspaceInfo] {
        let res = try await callUnaryJSON(
            method: "GetWorkspaceInfos",
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: timeoutInterval
        )
        let items = res["workspaces"]?.arrayValue ?? res["workspaceInfos"]?.arrayValue ?? []
        return items.compactMap { item -> WorkspaceInfo? in
            guard let obj = item.objectValue else { return nil }
            guard let rawUri = obj["workspaceUri"]?.stringValue
                ?? obj["workspaceFolderAbsoluteUri"]?.stringValue else { return nil }
            if AntigravityCloudDetector.isGenericContainerURI(rawUri)
                || AntigravityCloudDetector.isPlaygroundScratchURI(rawUri) {
                return nil
            }
            let sourceHint = [obj["runtime"]?.stringValue, obj["source"]?.stringValue]
                .compactMap { $0 }
                .joined(separator: " ")
            let isCloud = (obj["isCloud"]?.boolValue ?? false)
                || AntigravityCloudDetector.isCloudWorkspaceURI(rawUri, sourceHint: sourceHint)
            let uri = AntigravityCloudDetector.normalizeWorkspaceURI(rawUri, isCloud: isCloud)
            guard !uri.isEmpty else { return nil }
            let fallbackName: String
            if uri.hasPrefix("cloud://") {
                let tail = uri.replacingOccurrences(of: "cloud://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                fallbackName = (tail as NSString).lastPathComponent.isEmpty ? tail : (tail as NSString).lastPathComponent
            } else if uri.contains("://"), let parsedURL = URL(string: uri), !parsedURL.lastPathComponent.isEmpty {
                fallbackName = parsedURL.lastPathComponent
            } else {
                fallbackName = (uri.replacingOccurrences(of: "file://", with: "") as NSString).lastPathComponent
            }
            let name = obj["displayName"]?.stringValue ?? fallbackName
            guard !AntigravityCloudDetector.isNoProjectSlug(name) else { return nil }
            let branch = obj["activeBranch"]?.stringValue ?? obj["gitBranch"]?.stringValue ?? "main"
            let files = obj["indexedFiles"]?.arrayValue?.compactMap(\.stringValue) ?? []
            return WorkspaceInfo(
                workspaceUri: uri,
                displayName: name,
                activeBranch: branch,
                indexedFiles: files,
                isCloud: isCloud,
                originInstanceUuid: instanceUuidOverride ?? resolvedInstanceUuid,
                originHostName: isCloud ? "Antigravity" : originHostName
            )
        }
    }

    public func createProjectWorkspace(draft: NewProjectDraft) async throws -> ProjectWorkspace {
        let repoName = draft.selectedRepo?.fullName ?? draft.projectName
        if channel == .cloudRelay && draft.runsOn == .cloud {
            let newProjectId = UUID().uuidString.lowercased()
            var projectObj: [String: JSONValue] = [
                "id": .string(newProjectId),
                "name": .string(draft.projectName),
                "backendType": .string("BACKEND_TYPE_REMOTE_AICODE")
            ]
            var resourceEntries: [JSONValue] = []
            if let repo = draft.selectedRepo {
                resourceEntries.append(
                    .object([
                        "remoteResource": .object([
                            "type": .string("github"),
                            "name": .string(repo.fullName),
                            "displayName": .string(repo.fullName)
                        ])
                    ])
                )
            }
            for link in draft.driveResourceLinks where !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resourceEntries.append(
                    .object([
                        "remoteResource": .object([
                            "type": .string("google_drive"),
                            "name": .string(link),
                            "displayName": .string(link)
                        ])
                    ])
                )
            }
            if !resourceEntries.isEmpty {
                projectObj["projectResources"] = .object(["resources": .array(resourceEntries)])
            }
            if !draft.envSetupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                projectObj["envSetupScript"] = .string(draft.envSetupScript)
            }
            let res = try await callUnaryJSON(
                method: "CreateProject",
                body: [
                    "backend": .string("BACKEND_TYPE_REMOTE_AICODE"),
                    "project": .object(projectObj)
                ]
            )
            let returnedProj = res["project"]?.objectValue
            let finalId = Self.nonEmptyString(returnedProj?["id"]?.stringValue) ?? newProjectId
            let finalName = Self.nonEmptyString(returnedProj?["name"]?.stringValue) ?? draft.projectName
            let cloudUri = "cloud://\(repoName)"
            let created = ProjectWorkspace(
                id: finalId,
                name: finalName,
                pathDisplay: cloudUri,
                workspaceUri: cloudUri,
                runtime: .cloud,
                hostName: "Antigravity",
                activeBranch: draft.selectedRepo?.defaultBranch ?? "main",
                cloudProjectId: finalId,
                originInstanceUuid: resolvedInstanceUuid
            )
            cachedCloudProjectsById[finalId] = created
            return created
        }

        var body: [String: JSONValue] = [
            "name": .string(draft.projectName),
            "runtime": .string(draft.runsOn.rawValue),
            "source": .string(draft.source.rawValue),
            "repository": .string(repoName),
            "branchWorktree": .string(draft.branchWorktree)
        ]
        if !draft.driveResourceLinks.isEmpty {
            body["googleDriveLinks"] = .array(draft.driveResourceLinks.map(JSONValue.string))
        }
        if !draft.uploadedFilePaths.isEmpty {
            body["uploadedFilePaths"] = .array(draft.uploadedFilePaths.map(JSONValue.string))
        }
        if !draft.envSetupScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["envSetupScript"] = .string(draft.envSetupScript)
        }
        let res = try await callUnaryJSON(
            method: "CreateProjectWorkspace",
            body: body
        )
        let workspaceUri = res["workspaceUri"]?.stringValue
            ?? (draft.runsOn == .cloud ? "cloud://\(repoName)" : "file:///Users/wl/code/\(draft.projectName)")
        return ProjectWorkspace(
            id: draft.projectName,
            name: draft.projectName,
            pathDisplay: draft.runsOn == .cloud ? "cloud://\(repoName)" : "~/code/\(draft.projectName)",
            workspaceUri: workspaceUri,
            runtime: draft.runsOn,
            hostName: draft.runsOn == .cloud ? "Antigravity" : draft.runsOn.rawValue,
            activeBranch: draft.selectedRepo?.defaultBranch ?? "main"
        )
    }

    public func openWorkspaceInFinder(workspaceUri: String) async throws {
        _ = try await callUnaryJSON(
            method: "OpenWorkspaceInFinder",
            body: ["workspaceUri": .string(workspaceUri)]
        )
    }

    // MARK: - Automations RPC (`UE06` — Native Antigravity 2.0 Sidecars)

    internal static func isMethodUnimplementedError(_ error: Error) -> Bool {
        guard case let AntigravityRPCError.httpError(code, body) = error else { return false }
        if code == 404 || code == 501 { return true }
        let lower = body.lowercased()
        return lower.contains("unimplemented") || lower.contains("unknown method") || lower.contains("method not found")
    }

    public static func parseInt64Millis(_ value: JSONValue?) -> Int64? {
        guard let value else { return nil }
        switch value {
        case .int(let i):
            return Int64(i)
        case .double(let d):
            return Int64(d)
        case .string(let s):
            return Int64(s.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    internal static func normalizeSidecarStatus(_ value: JSONValue?) -> String {
        guard let value else { return "UNSPECIFIED" }
        if let raw = value.stringValue?.uppercased() {
            if raw.contains("RUNNING") { return "RUNNING" }
            if raw.contains("STOPPED") { return "STOPPED" }
            if raw.contains("ERROR") { return "ERRORED" }
            if raw.contains("BACKOFF") { return "BACKOFF" }
            if raw.contains("STARTING") { return "STARTING" }
            return raw
        }
        if let code = value.intValue {
            switch code {
            case 1: return "RUNNING"
            case 2: return "STOPPED"
            case 3: return "ERRORED"
            case 4: return "BACKOFF"
            case 5: return "STARTING"
            default: return "UNSPECIFIED"
            }
        }
        return "UNSPECIFIED"
    }

    /// Refreshes local Antigravity Desktop `Project.id <-> Project.name` mapping via `ListProjects({})` + `ReadProject`.
    internal func ensureLocalProjectIndex(forceRefresh: Bool = false) async {
        if !forceRefresh,
           let last = lastLocalProjectFetchAt,
           Date().timeIntervalSince(last) < 30.0,
           !cachedLocalProjectNameById.isEmpty {
            return
        }
        lastLocalProjectFetchAt = Date()
        guard let listResp = try? await callUnaryJSON(method: "ListProjects", body: [:], timeoutInterval: 6.0),
              let ids = (listResp["projectIds"] ?? listResp["project_ids"])?.arrayValue?.compactMap(\.stringValue).filter({ !$0.isEmpty }),
              !ids.isEmpty else {
            return
        }
        for pid in ids.prefix(32) {
            guard let readResp = try? await callUnaryJSON(method: "ReadProject", body: ["id": .string(pid)], timeoutInterval: 5.0),
                  let projObj = readResp["project"]?.objectValue else {
                continue
            }
            let resolvedId = Self.nonEmptyString(projObj["id"]?.stringValue) ?? pid
            let name = Self.nonEmptyString(projObj["name"]?.stringValue) ?? resolvedId
            cachedLocalProjectNameById[resolvedId] = name
            cachedLocalProjectIdByName[name.lowercased()] = resolvedId
        }
    }

    /// Decodes a single `exa.cortex_pb.SidecarStatusInfo` JSON object into an `AutomationItem`.
    /// Returns `nil` for pure auxiliary Web UI panel sidecars (`hasWebUi: true`) or bundled non-schedule sidecars.
    public static func decodeSidecarStatusInfo(
        _ obj: [String: JSONValue],
        projectNameById: [String: String] = [:],
        originInstanceUuid: String? = nil,
        now: Date = Date()
    ) -> AutomationItem? {
        guard let sidecarId = nonEmptyString(obj["sidecarId"]?.stringValue)
            ?? nonEmptyString(obj["sidecar_id"]?.stringValue)
            ?? nonEmptyString(obj["id"]?.stringValue) else {
            return nil
        }

        let cfg = obj["config"]?.objectValue ?? [:]
        let uiCfg = obj["uiConfig"]?.objectValue ?? obj["ui_config"]?.objectValue
            ?? cfg["uiConfig"]?.objectValue ?? cfg["ui_config"]?.objectValue
        let uiViews = uiCfg?["views"]?.arrayValue ?? []
        let hasWebUI = (cfg["hasWebUi"]?.boolValue ?? cfg["has_web_ui"]?.boolValue ?? false) || !uiViews.isEmpty
        let isBundled = obj["isBundled"]?.boolValue ?? obj["is_bundled"]?.boolValue ?? false

        let builtin = (nonEmptyString(cfg["builtin"]?.stringValue) ?? nonEmptyString(obj["builtin"]?.stringValue) ?? "").lowercased()
        let command = nonEmptyString(cfg["command"]?.stringValue) ?? ""
        let args = cfg["args"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let invokesAgentApi = args.count >= 3 && args.contains("agentapi") && args.contains("new-conversation")
        let isSchedule = (builtin == "schedule") || invokesAgentApi

        // Exclude Auxiliary Pane Web UI widgets and internal bundled daemons unless they are scheduled automations.
        if !isSchedule && (hasWebUI || isBundled) {
            return nil
        }

        let displayName = nonEmptyString(cfg["displayName"]?.stringValue)
            ?? nonEmptyString(cfg["display_name"]?.stringValue)
            ?? nonEmptyString(obj["name"]?.stringValue)
            ?? sidecarId
        let descriptionText = nonEmptyString(cfg["description"]?.stringValue)
            ?? nonEmptyString(obj["description"]?.stringValue)
            ?? ""

        let statusNorm = normalizeSidecarStatus(obj["status"])
        let lastError = nonEmptyString(obj["lastError"]?.stringValue) ?? nonEmptyString(obj["last_error"]?.stringValue)

        let userCfg = obj["userConfig"]?.objectValue ?? obj["user_config"]?.objectValue
        let userProjectId = nonEmptyString(userCfg?["projectId"]?.stringValue) ?? nonEmptyString(userCfg?["project_id"]?.stringValue)
        let allProjects = userCfg?["allProjects"]?.boolValue ?? userCfg?["all_projects"]?.boolValue ?? false
        let configDisabled = cfg["disabled"]?.boolValue ?? false

        // Proto3 JSON omits scalar `bool enabled = false`, so combine explicit `userConfig.enabled` with runtime `status`.
        let isEnabled: Bool = {
            if let explicitEnabled = userCfg?["enabled"]?.boolValue {
                return explicitEnabled
            }
            if configDisabled {
                return false
            }
            if statusNorm == "RUNNING" || statusNorm == "STARTING" {
                return true
            }
            if userCfg != nil {
                return false
            }
            return statusNorm != "STOPPED"
        }()

        let section: AutomationSectionKind = {
            if !isEnabled { return .paused }
            return isSchedule ? .scheduled : .alwaysOn
        }()

        let parsedArgs: (cron: String, prompt: String, modelLabel: String?) = isSchedule
            ? AutomationScheduleCodec.parseScheduleArgs(args)
            : (cron: "", prompt: "", modelLabel: nil)
        let cronExpr = parsedArgs.cron
        let promptText = parsedArgs.prompt.isEmpty ? (descriptionText.isEmpty ? displayName : descriptionText) : parsedArgs.prompt
        let modelBadge = parsedArgs.modelLabel ?? (isSchedule ? "Flash" : nil)

        // Resolve human-readable project label from `projectId`, `agentPermissions.workspaceUris`, or `allProjects`.
        let agentPerms = cfg["agentPermissions"]?.objectValue ?? cfg["agent_permissions"]?.objectValue
        let permWorkspaceUris = (agentPerms?["workspaceUris"] ?? agentPerms?["workspace_uris"])?.arrayValue?.compactMap(\.stringValue) ?? []
        let projectSlug: String = {
            if let pid = userProjectId, !pid.isEmpty {
                if let resolved = projectNameById[pid], !resolved.isEmpty {
                    return resolved
                }
                return pid
            }
            if let firstUri = permWorkspaceUris.first, !firstUri.isEmpty {
                let cleaned = firstUri.replacingOccurrences(of: "file://", with: "")
                let base = (cleaned as NSString).lastPathComponent
                if !base.isEmpty && base != "/" {
                    return base
                }
            }
            return allProjects ? "All projects" : "This Computer"
        }()

        let humanSchedule = isSchedule
            ? AutomationScheduleCodec.humanReadableSchedule(from: cronExpr)
            : (command.isEmpty ? "Background listener" : (command as NSString).lastPathComponent)

        let scheduleSummary: String = {
            if isSchedule {
                return "\(projectSlug) · \(humanSchedule) · \(modelBadge ?? "Flash")"
            }
            return "\(projectSlug) · Always On · \(humanSchedule)"
        }()

        let nextRunText: String = {
            if section == .paused { return "Paused" }
            if isSchedule {
                return AutomationScheduleCodec.nextFireDescription(from: cronExpr, after: now)
            }
            switch statusNorm {
            case "RUNNING": return "Listening"
            case "STARTING": return "Starting..."
            case "ERRORED", "BACKOFF": return "Error"
            default: return "Active"
            }
        }()

        let hasRuntimeError = (statusNorm == "ERRORED" || statusNorm == "BACKOFF") || (lastError != nil)
        let lastRunText: String = {
            if let lastError, !lastError.isEmpty {
                return "Error · \(String(lastError.prefix(28)))"
            }
            if statusNorm == "ERRORED" || statusNorm == "BACKOFF" {
                return "Failed · Needs review"
            }
            if section == .paused {
                return "Paused"
            }
            if let startMs = parseInt64Millis(obj["startTimeMs"] ?? obj["start_time_ms"]), startMs > 0 {
                return isSchedule ? "Scheduled · Ready" : "Running · \(AutomationScheduleCodec.relativeTimeLabel(from: startMs, now: now))"
            }
            return isSchedule ? "Scheduled · Ready" : "Active"
        }()

        return AutomationItem(
            id: sidecarId,
            title: displayName,
            projectSlug: projectSlug,
            scheduleSummary: scheduleSummary,
            section: section,
            nextRunText: nextRunText,
            lastRunText: lastRunText,
            needsReview: hasRuntimeError,
            isRunningNow: false,
            descriptionText: descriptionText,
            prompt: promptText,
            cronExpression: cronExpr,
            projectId: userProjectId,
            allProjects: allProjects,
            modelLabel: modelBadge,
            lastRunCascadeId: nil,
            lastError: lastError,
            isEnabled: isEnabled,
            isScheduleBuiltin: isSchedule,
            originInstanceUuid: originInstanceUuid
        )
    }

    public static func decodeSidecarEvent(_ obj: [String: JSONValue]) -> SidecarRunEvent? {
        let ts = parseInt64Millis(obj["timestampMs"] ?? obj["timestamp_ms"])
            ?? parseInt64Millis(obj["commandInvocationTimestampMs"] ?? obj["command_invocation_timestamp_ms"])
            ?? 0
        let err = nonEmptyString(obj["error"]?.stringValue)
        let payload = obj["payload"]?.objectValue
        let newConv = payload?["newConversation"]?.objectValue ?? payload?["new_conversation"]?.objectValue
        let convId = nonEmptyString(newConv?["conversationId"]?.stringValue)
            ?? nonEmptyString(newConv?["conversation_id"]?.stringValue)
        let prompt = nonEmptyString(newConv?["prompt"]?.stringValue)
        guard ts > 0 || convId != nil || err != nil else { return nil }
        return SidecarRunEvent(
            timestampMs: ts,
            error: err,
            conversationId: convId,
            prompt: prompt
        )
    }

    /// Builds a native `ManageSidecarRequest` (`SIDECAR_ACTION_CREATE` or `SIDECAR_ACTION_UPDATE`) JSON body.
    public static func buildManageSidecarConfigBody(
        sidecarId: String,
        action: SidecarManageAction,
        displayName: String,
        prompt: String,
        cronExpression: String,
        description: String = "",
        projectId: String? = nil,
        allProjects: Bool = false,
        modelArg: String? = nil
    ) -> [String: JSONValue] {
        let args = AutomationScheduleCodec.buildScheduleArgs(
            cron: cronExpression,
            prompt: prompt,
            modelArg: modelArg
        )
        var configObj: [String: JSONValue] = [
            "builtin": .string("schedule"),
            "restartPolicy": .string("always"),
            "displayName": .string(displayName),
            "args": .array(args.map { .string($0) })
        ]
        if !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configObj["description"] = .string(description.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var body: [String: JSONValue] = [
            "sidecarId": .string(sidecarId),
            "action": .string(action.rawValue),
            "config": .object(configObj)
        ]
        if let projectId = nonEmptyString(projectId) {
            body["projectId"] = .string(projectId)
        } else if allProjects {
            body["allProjects"] = .bool(true)
        }
        return body
    }

    public func getSidecarEvents(
        sidecarId: String,
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval = 5.0
    ) async throws -> [SidecarRunEvent] {
        let res = try await callUnaryJSON(
            method: "GetSidecarEvents",
            body: ["sidecarId": .string(sidecarId)],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: timeoutInterval
        )
        guard let arr = res["events"]?.arrayValue else { return [] }
        return arr.compactMap { entry -> SidecarRunEvent? in
            guard let obj = entry.objectValue else { return nil }
            return Self.decodeSidecarEvent(obj)
        }
        .sorted { $0.timestampMs > $1.timestampMs }
    }

    public func listAutomations(timeoutInterval: TimeInterval? = nil) async throws -> [AutomationItem] {
        await ensureLocalProjectIndex()
        var projectNameById = cachedLocalProjectNameById
        for (pid, proj) in cachedCloudProjectsById where projectNameById[pid] == nil {
            projectNameById[pid] = proj.name
        }

        do {
            let res = try await callUnaryJSON(
                method: "GetSidecars",
                body: [:],
                timeoutInterval: timeoutInterval ?? 10.0
            )
            let activeOrigin = resolvedInstanceUuid
            let rawSidecars = res["sidecars"]?.arrayValue ?? []
            var items: [AutomationItem] = rawSidecars.compactMap { entry in
                guard let obj = entry.objectValue else { return nil }
                return Self.decodeSidecarStatusInfo(
                    obj,
                    projectNameById: projectNameById,
                    originInstanceUuid: activeOrigin
                )
            }

            // Enrich top automations with real run history (`lastRunText` & `lastRunCascadeId`) via `GetSidecarEvents`.
            if !items.isEmpty {
                let targetIds = items.prefix(20).map(\.id)
                let eventsById: [String: SidecarRunEvent] = await withTaskGroup(of: (String, SidecarRunEvent?).self) { group in
                    for sid in targetIds {
                        group.addTask {
                            let events = (try? await self.getSidecarEvents(
                                sidecarId: sid,
                                instanceUuidOverride: activeOrigin,
                                timeoutInterval: 4.5
                            )) ?? []
                            return (sid, events.first)
                        }
                    }
                    var map: [String: SidecarRunEvent] = [:]
                    for await (sid, latest) in group {
                        if let latest {
                            map[sid] = latest
                        }
                    }
                    return map
                }

                let now = Date()
                for idx in items.indices {
                    guard let latest = eventsById[items[idx].id] else { continue }
                    if let cid = latest.conversationId, !cid.isEmpty {
                        items[idx].lastRunCascadeId = cid
                    }
                    let rel = latest.timestampMs > 0
                        ? AutomationScheduleCodec.relativeTimeLabel(from: latest.timestampMs, now: now)
                        : "recently"
                    if let err = latest.error, !err.isEmpty {
                        items[idx].lastError = err
                        items[idx].needsReview = true
                        items[idx].lastRunText = "Failed · \(rel)"
                    } else if items[idx].lastError == nil {
                        items[idx].lastRunText = "Succeeded · \(rel)"
                    }
                }
            }

            items.sort { lhs, rhs in
                if lhs.section != rhs.section {
                    let rank: (AutomationSectionKind) -> Int = { s in
                        switch s {
                        case .scheduled: return 0
                        case .alwaysOn: return 1
                        case .paused: return 2
                        }
                    }
                    return rank(lhs.section) < rank(rhs.section)
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return items
        } catch {
            // Only fall back to legacy `ListAutomations` on direct LAN mock/sandbox servers that don't expose `GetSidecars`.
            if channel == .directHost && Self.isMethodUnimplementedError(error) {
                return try await listLegacyCompanionAutomations()
            }
            throw error
        }
    }

    internal func listLegacyCompanionAutomations() async throws -> [AutomationItem] {
        let res = try await callUnaryJSON(method: "ListAutomations")
        guard let arr = res["automations"]?.arrayValue else { return [] }
        return arr.compactMap { item -> AutomationItem? in
            guard let obj = item.objectValue,
                  let id = obj["id"]?.stringValue,
                  let title = obj["title"]?.stringValue else { return nil }
            let slug = obj["projectSlug"]?.stringValue ?? "ledger-svc"
            let summary = obj["scheduleSummary"]?.stringValue ?? "\(slug) · Daily · Flash"
            let sectionRaw = (obj["section"]?.stringValue ?? AutomationSectionKind.scheduled.rawValue).uppercased()
            let section = AutomationSectionKind(rawValue: sectionRaw) ?? .scheduled
            return AutomationItem(
                id: id,
                title: title,
                projectSlug: slug,
                scheduleSummary: summary,
                section: section,
                nextRunText: obj["nextRunText"]?.stringValue ?? "Tonight, 02:00",
                lastRunText: obj["lastRunText"]?.stringValue ?? "Scheduled",
                needsReview: obj["needsReview"]?.boolValue ?? false,
                isRunningNow: obj["isRunningNow"]?.boolValue ?? false
            )
        }
    }

    public func createAutomation(prompt: String, projectSlug: String) async throws -> AutomationItem {
        let parsed = AutomationScheduleCodec.parseNaturalLanguagePrompt(prompt)
        return try await createAutomation(
            displayName: parsed.displayName,
            prompt: parsed.prompt,
            cronExpression: parsed.cronExpression,
            projectSlug: projectSlug,
            projectId: nil,
            allProjects: projectSlug.isEmpty || projectSlug == "All projects",
            modelArg: nil,
            description: "\(parsed.humanScheduleLabel): \(parsed.prompt)",
            enableImmediately: true
        )
    }

    public func createAutomation(
        displayName: String,
        prompt: String,
        cronExpression: String,
        projectSlug: String,
        projectId: String? = nil,
        allProjects: Bool = false,
        modelArg: String? = nil,
        description: String = "",
        enableImmediately: Bool = true
    ) async throws -> AutomationItem {
        await ensureLocalProjectIndex()
        let resolvedLocalProjectId: String? = {
            if let explicit = Self.nonEmptyString(projectId),
               cachedLocalProjectNameById[explicit] != nil || !explicit.hasPrefix("projects/") {
                return explicit
            }
            let normalizedSlug = projectSlug
                .replacingOccurrences(of: "cloud:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !normalizedSlug.isEmpty, let match = cachedLocalProjectIdByName[normalizedSlug] {
                return match
            }
            return nil
        }()

        let sidecarId = AutomationScheduleCodec.makeSidecarId(from: displayName)
        let createBody = Self.buildManageSidecarConfigBody(
            sidecarId: sidecarId,
            action: .create,
            displayName: displayName,
            prompt: prompt,
            cronExpression: cronExpression,
            description: description,
            projectId: resolvedLocalProjectId,
            allProjects: resolvedLocalProjectId == nil && allProjects,
            modelArg: modelArg
        )

        do {
            let createResp = try await callUnaryJSON(
                method: "ManageSidecar",
                body: createBody,
                timeoutInterval: 15.0
            )
            let createdId = Self.nonEmptyString(createResp["sidecarId"]?.stringValue)
                ?? Self.nonEmptyString(createResp["sidecar_id"]?.stringValue)
                ?? sidecarId

            // Bind target project explicitly via `SIDECAR_ACTION_SET_PROJECT` so Desktop honors it even when
            // `jetski-sidecar-declared-permissions` omits project binding on initial CREATE.
            if let pid = resolvedLocalProjectId, !pid.isEmpty {
                _ = try? await callUnaryJSON(
                    method: "ManageSidecar",
                    body: [
                        "sidecarId": .string(createdId),
                        "action": .string(SidecarManageAction.setProject.rawValue),
                        "projectId": .string(pid)
                    ],
                    timeoutInterval: 10.0
                )
            } else if allProjects {
                _ = try? await callUnaryJSON(
                    method: "ManageSidecar",
                    body: [
                        "sidecarId": .string(createdId),
                        "action": .string(SidecarManageAction.setAllProjects.rawValue),
                        "allProjects": .bool(true)
                    ],
                    timeoutInterval: 10.0
                )
            }

            if enableImmediately {
                _ = try? await callUnaryJSON(
                    method: "ManageSidecar",
                    body: [
                        "sidecarId": .string(createdId),
                        "action": .string(SidecarManageAction.enable.rawValue)
                    ],
                    timeoutInterval: 10.0
                )
            }

            let humanSched = AutomationScheduleCodec.humanReadableSchedule(from: cronExpression)
            let modelBadge = AutomationScheduleCodec.formatModelBadge(modelArg ?? "Flash")
            let slugLabel = projectSlug.isEmpty ? (allProjects ? "All projects" : "This Computer") : projectSlug
            return AutomationItem(
                id: createdId,
                title: displayName,
                projectSlug: slugLabel,
                scheduleSummary: "\(slugLabel) · \(humanSched) · \(modelBadge)",
                section: enableImmediately ? .scheduled : .paused,
                nextRunText: enableImmediately ? AutomationScheduleCodec.nextFireDescription(from: cronExpression) : "Paused",
                lastRunText: enableImmediately ? "Created just now" : "Paused · New",
                needsReview: false,
                isRunningNow: false,
                descriptionText: description,
                prompt: prompt,
                cronExpression: cronExpression,
                projectId: resolvedLocalProjectId,
                allProjects: resolvedLocalProjectId == nil && allProjects,
                modelLabel: modelBadge,
                isEnabled: enableImmediately,
                isScheduleBuiltin: true,
                originInstanceUuid: resolvedInstanceUuid
            )
        } catch {
            if channel == .directHost && Self.isMethodUnimplementedError(error) {
                let res = try await callUnaryJSON(
                    method: "CreateAutomation",
                    body: [
                        "prompt": .string(prompt),
                        "projectSlug": .string(projectSlug)
                    ]
                )
                let id = res["id"]?.stringValue ?? sidecarId
                return AutomationItem(
                    id: id,
                    title: displayName,
                    projectSlug: projectSlug,
                    scheduleSummary: "\(projectSlug) · \(AutomationScheduleCodec.humanReadableSchedule(from: cronExpression)) · Flash",
                    section: .scheduled,
                    nextRunText: AutomationScheduleCodec.nextFireDescription(from: cronExpression),
                    lastRunText: "Created just now",
                    prompt: prompt,
                    cronExpression: cronExpression
                )
            }
            throw error
        }
    }

    public func updateAutomation(
        automationId: String,
        displayName: String,
        prompt: String,
        cronExpression: String,
        projectSlug: String,
        projectId: String? = nil,
        allProjects: Bool = false,
        modelArg: String? = nil,
        description: String = "",
        instanceUuidOverride: String? = nil
    ) async throws {
        await ensureLocalProjectIndex()
        let resolvedLocalProjectId: String? = {
            if let explicit = Self.nonEmptyString(projectId) { return explicit }
            let key = projectSlug.replacingOccurrences(of: "cloud:", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return cachedLocalProjectIdByName[key]
        }()

        let body = Self.buildManageSidecarConfigBody(
            sidecarId: automationId,
            action: .update,
            displayName: displayName,
            prompt: prompt,
            cronExpression: cronExpression,
            description: description,
            projectId: resolvedLocalProjectId,
            allProjects: resolvedLocalProjectId == nil && allProjects,
            modelArg: modelArg
        )
        _ = try await callUnaryJSON(
            method: "ManageSidecar",
            body: body,
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 15.0
        )
        if let pid = resolvedLocalProjectId, !pid.isEmpty {
            _ = try? await callUnaryJSON(
                method: "ManageSidecar",
                body: [
                    "sidecarId": .string(automationId),
                    "action": .string(SidecarManageAction.setProject.rawValue),
                    "projectId": .string(pid)
                ],
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: 10.0
            )
        } else if allProjects {
            _ = try? await callUnaryJSON(
                method: "ManageSidecar",
                body: [
                    "sidecarId": .string(automationId),
                    "action": .string(SidecarManageAction.setAllProjects.rawValue),
                    "allProjects": .bool(true)
                ],
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: 10.0
            )
        }
    }

    public func triggerAutomationNow(
        automationId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        do {
            _ = try await callUnaryJSON(
                method: "ManageSidecar",
                body: [
                    "sidecarId": .string(automationId),
                    "action": .string(SidecarManageAction.runNow.rawValue)
                ],
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: 15.0
            )
        } catch {
            if channel == .directHost && Self.isMethodUnimplementedError(error) {
                _ = try await callUnaryJSON(
                    method: "TriggerAutomationNow",
                    body: ["automationId": .string(automationId)]
                )
                return
            }
            throw error
        }
    }

    public func setAutomationPaused(
        automationId: String,
        isPaused: Bool,
        instanceUuidOverride: String? = nil
    ) async throws {
        let action: SidecarManageAction = isPaused ? .disable : .enable
        do {
            _ = try await callUnaryJSON(
                method: "ManageSidecar",
                body: [
                    "sidecarId": .string(automationId),
                    "action": .string(action.rawValue)
                ],
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: 12.0
            )
        } catch {
            if channel == .directHost && Self.isMethodUnimplementedError(error) {
                _ = try await callUnaryJSON(
                    method: "SetAutomationPaused",
                    body: [
                        "automationId": .string(automationId),
                        "isPaused": .bool(isPaused)
                    ]
                )
                return
            }
            throw error
        }
    }

    public func deleteAutomation(
        automationId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        _ = try await callUnaryJSON(
            method: "ManageSidecar",
            body: [
                "sidecarId": .string(automationId),
                "action": .string(SidecarManageAction.delete.rawValue)
            ],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 12.0
        )
    }

    public func restartAutomation(
        automationId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        _ = try await callUnaryJSON(
            method: "ManageSidecar",
            body: [
                "sidecarId": .string(automationId),
                "action": .string(SidecarManageAction.restart.rawValue)
            ],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 12.0
        )
    }
}
