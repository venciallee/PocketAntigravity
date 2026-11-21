import Foundation

/// Trajectory step pagination (JSON <600 / binary Protobuf >=600) and conversation lifecycle RPCs.
extension AntigravityRPCClient {
    /// Wakes a dormant disk trajectory into `language_server` memory (`LoadTrajectory`).
    public func loadTrajectory(
        cascadeId: String,
        isCloud: Bool = false,
        instanceUuidOverride: String? = nil
    ) async throws {
        let isRemoteCloud = isCloud || cascadeId.hasPrefix("v1/")
        var body: [String: JSONValue] = ["cascadeId": .string(cascadeId)]
        if isRemoteCloud {
            body["backend"] = .string("BACKEND_TYPE_REMOTE_AICODE")
        }
        _ = try await callUnaryJSON(
            method: "LoadTrajectory",
            body: body,
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 8.0
        )
    }

    /// Fetches trajectory steps, automatically switching from JSON (`0..<600`) to Binary Protobuf (`>=600`).
    public func fetchTrajectorySteps(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = 200,
        instanceUuidOverride: String? = nil
    ) async throws -> [CascadeStep] {
        if endIndex >= Self.protobufStepThreshold {
            return try await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: startIndex,
                endIndex: endIndex,
                instanceUuidOverride: instanceUuidOverride
            )
        }
        return try await fetchTrajectoryStepsJSON(
            cascadeId: cascadeId,
            startIndex: startIndex,
            endIndex: endIndex,
            instanceUuidOverride: instanceUuidOverride
        )
    }

    /// Fetches the complete trajectory for a live or historical session using upstream `GetCascadeTrajectorySteps`,
    /// waking dormant trajectories via `LoadTrajectory`, falling back to `GetCascadeTrajectory` / Binary Protobuf,
    /// and failing over across reachable Cloud Relay instances when a conversation lives in a peer window.
    public func fetchAllTrajectorySteps(
        cascadeId: String,
        knownStepCount: Int = 0,
        isCloud: Bool = false,
        instanceUuidOverride: String? = nil
    ) async throws -> [CascadeStep] {
        let isRemoteCloud = isCloud || cascadeId.hasPrefix("v1/")
        let primaryTarget: String? = {
            if channel == .cloudRelay {
                return selectReachableRelayUuid(
                    preferred: instanceUuidOverride,
                    allowCrossHostFailover: isRemoteCloud
                )
            }
            return instanceUuidOverride
        }()

        var primaryError: Error? = nil
        if channel != .cloudRelay || primaryTarget != nil {
            do {
                let steps = try await fetchStepsFromSingleInstance(
                    cascadeId: cascadeId,
                    knownStepCount: knownStepCount,
                    isCloud: isRemoteCloud,
                    targetUuid: primaryTarget
                )
                if !steps.isEmpty {
                    return steps
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                primaryError = error
            }
        } else {
            primaryError = AntigravityRPCError.httpError(
                statusCode: 503,
                body: "Selected Antigravity Desktop host is offline"
            )
        }

        // Multi-window Cloud Relay failover:
        // - For local conversations: ONLY probe peer windows on the SAME Mac (`sameHostFamily`).
        // - For Antigravity Cloud (`isRemoteCloud`): any reachable host can proxy remote steps.
        if channel == .cloudRelay {
            if cachedRelayInstances.isEmpty,
               let refreshed = try? await listRelayInstances(timeoutInterval: 6.0),
               !refreshed.isEmpty {
                self.cachedRelayInstances = refreshed
            }
            let seedUuid = primaryTarget ?? instanceUuidOverride ?? resolvedInstanceUuid
            let familySeed = cachedRelayInstances.first(where: { $0.uuid == seedUuid })?.name
                ?? (instanceUuidOverride == nil && !Self.isWildcardRelayIdentifier(targetInstanceIdentifier) ? targetInstanceIdentifier : "")
            let peerCandidates = cachedRelayInstances
                .filter { inst in
                    guard inst.status.isReachable && inst.uuid != primaryTarget else { return false }
                    if isRemoteCloud { return true }
                    return !familySeed.isEmpty && inst.sameHostFamily(as: familySeed)
                }
                .sorted { lhs, rhs in
                    let lFam = !familySeed.isEmpty && lhs.sameHostFamily(as: familySeed)
                    let rFam = !familySeed.isEmpty && rhs.sameHostFamily(as: familySeed)
                    if lFam != rFam { return lFam && !rFam }
                    return lhs.uuid < rhs.uuid
                }

            for peer in peerCandidates {
                do {
                    let peerSteps = try await fetchStepsFromSingleInstance(
                        cascadeId: cascadeId,
                        knownStepCount: knownStepCount,
                        isCloud: isRemoteCloud,
                        targetUuid: peer.uuid
                    )
                    if !peerSteps.isEmpty {
                        if instanceUuidOverride == nil && !isRemoteCloud {
                            self.resolvedInstanceUuid = peer.uuid
                        }
                        return peerSteps
                    }
                } catch let AntigravityRPCError.unauthorized(msg) {
                    throw AntigravityRPCError.unauthorized(msg)
                } catch {
                    if primaryError == nil {
                        primaryError = error
                    }
                }
            }
        }

        if let primaryError {
            throw primaryError
        }
        return []
    }

    internal func fetchStepsFromSingleInstance(
        cascadeId: String,
        knownStepCount: Int,
        isCloud: Bool,
        targetUuid: String?
    ) async throws -> [CascadeStep] {
        let isRemoteCloud = isCloud || cascadeId.hasPrefix("v1/")
        let wakeKey = "\(targetUuid ?? "direct")|\(cascadeId)"
        var lastError: Error? = nil

        if knownStepCount >= Self.protobufStepThreshold {
            do {
                let protoSteps = try await fetchTrajectoryStepsProtobuf(
                    cascadeId: cascadeId,
                    startIndex: 0,
                    endIndex: knownStepCount,
                    instanceUuidOverride: targetUuid,
                    allowCrossHostFailover: isRemoteCloud
                )
                if !protoSteps.isEmpty {
                    wokenInstanceCascadeKeys.insert(wakeKey)
                    return protoSteps
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                lastError = error
            }
            try? await loadTrajectory(cascadeId: cascadeId, isCloud: isRemoteCloud, instanceUuidOverride: targetUuid)
            let retryProtoSteps = try await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: knownStepCount,
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: isRemoteCloud
            )
            if !retryProtoSteps.isEmpty {
                wokenInstanceCascadeKeys.insert(wakeKey)
            }
            return retryProtoSteps
        }

        var stepReqBody: [String: JSONValue] = ["cascadeId": .string(cascadeId)]
        if isRemoteCloud {
            stepReqBody["backend"] = .string("BACKEND_TYPE_REMOTE_AICODE")
        }

        var firstResp: [String: JSONValue]? = nil
        do {
            firstResp = try await callUnaryJSON(
                method: "GetCascadeTrajectorySteps",
                body: stepReqBody,
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: isRemoteCloud,
                timeoutInterval: 10.0
            )
            lastError = nil
        } catch let AntigravityRPCError.unauthorized(msg) {
            throw AntigravityRPCError.unauthorized(msg)
        } catch {
            lastError = error
            firstResp = nil
        }

        if let resp = firstResp, resp["truncatedAt"] != nil {
            let protoSteps = try await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: max(knownStepCount, Self.protobufStepThreshold),
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: isRemoteCloud
            )
            if !protoSteps.isEmpty {
                wokenInstanceCascadeKeys.insert(wakeKey)
            }
            return protoSteps
        }

        var rawSteps = firstResp?["steps"]?.arrayValue ?? []
        if !rawSteps.isEmpty {
            wokenInstanceCascadeKeys.insert(wakeKey)
        } else if firstResp == nil || knownStepCount > 0 || !wokenInstanceCascadeKeys.contains(wakeKey) {
            try? await loadTrajectory(cascadeId: cascadeId, isCloud: isRemoteCloud, instanceUuidOverride: targetUuid)
            do {
                let retryResp = try await callUnaryJSON(
                    method: "GetCascadeTrajectorySteps",
                    body: stepReqBody,
                    instanceUuidOverride: targetUuid,
                    allowCrossHostFailover: isRemoteCloud,
                    timeoutInterval: 10.0
                )
                lastError = nil
                if retryResp["truncatedAt"] != nil {
                    let protoSteps = try await fetchTrajectoryStepsProtobuf(
                        cascadeId: cascadeId,
                        startIndex: 0,
                        endIndex: max(knownStepCount, Self.protobufStepThreshold),
                        instanceUuidOverride: targetUuid,
                        allowCrossHostFailover: isRemoteCloud
                    )
                    if !protoSteps.isEmpty {
                        wokenInstanceCascadeKeys.insert(wakeKey)
                    }
                    return protoSteps
                }
                rawSteps = retryResp["steps"]?.arrayValue ?? []
                if !rawSteps.isEmpty {
                    wokenInstanceCascadeKeys.insert(wakeKey)
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                lastError = error
            }
        }

        // Fallback A: Query `GetCascadeTrajectory` (`{"trajectory": {"steps": [...]}}`) when `GetCascadeTrajectorySteps` returns empty
        if rawSteps.isEmpty && !wokenInstanceCascadeKeys.contains(wakeKey) {
            do {
                let trajResp = try await callUnaryJSON(
                    method: "GetCascadeTrajectory",
                    body: stepReqBody,
                    instanceUuidOverride: targetUuid,
                    allowCrossHostFailover: isRemoteCloud,
                    timeoutInterval: 10.0
                )
                let fallbackArr = trajResp["trajectory"]?.objectValue?["steps"]?.arrayValue
                    ?? trajResp["steps"]?.arrayValue
                    ?? []
                if !fallbackArr.isEmpty {
                    rawSteps = fallbackArr
                    lastError = nil
                    wokenInstanceCascadeKeys.insert(wakeKey)
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                if lastError == nil { lastError = error }
            }
        }

        // Fallback B: Binary Protobuf (`application/proto`) when a >600-step dormant session omitted `stepCount` in summaries
        if rawSteps.isEmpty && (firstResp == nil || lastError != nil || knownStepCount > 0) {
            if let protoFallback = try? await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: max(knownStepCount, Self.protobufStepThreshold),
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: isRemoteCloud
            ), !protoFallback.isEmpty {
                wokenInstanceCascadeKeys.insert(wakeKey)
                return protoFallback
            }
        }

        if rawSteps.isEmpty, let lastError {
            throw lastError
        }

        if rawSteps.count >= 590 {
            if let protoSteps = try? await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: max(knownStepCount, rawSteps.count),
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: isRemoteCloud
            ), protoSteps.count >= rawSteps.count {
                wokenInstanceCascadeKeys.insert(wakeKey)
                return protoSteps
            }
        }

        var seenIndices = Set<Int>()
        var collected: [CascadeStep] = []
        for (idxOffset, item) in rawSteps.enumerated() {
            if let step = Self.decodeJSONStep(item, cascadeId: cascadeId, fallbackIndex: idxOffset) {
                if seenIndices.insert(step.stepIndex).inserted {
                    collected.append(step)
                }
            }
        }

        var offset = rawSteps.count
        while offset > 0 && offset < knownStepCount && offset < Self.protobufStepThreshold {
            var pageBody = stepReqBody
            pageBody["stepOffset"] = .int(offset)
            let pageResp = try await callUnaryJSON(
                method: "GetCascadeTrajectorySteps",
                body: pageBody,
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: isRemoteCloud
            )
            guard let pageSteps = pageResp["steps"]?.arrayValue, !pageSteps.isEmpty else {
                break
            }
            var addedNew = false
            for (idxOffset, item) in pageSteps.enumerated() {
                if let step = Self.decodeJSONStep(item, cascadeId: cascadeId, fallbackIndex: offset + idxOffset) {
                    if seenIndices.insert(step.stepIndex).inserted {
                        collected.append(step)
                        addedNew = true
                    }
                }
            }
            if !addedNew {
                break
            }
            offset += pageSteps.count
        }

        return collected.sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Fetches trajectory steps over JSON (`GetCascadeTrajectorySteps`) for conversations under 600 steps.
    /// Supports both native Desktop `language_server` step JSON (`stepOffset`) and companion/mock step schemas.
    public func fetchTrajectoryStepsJSON(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = 200,
        instanceUuidOverride: String? = nil
    ) async throws -> [CascadeStep] {
        var body: [String: JSONValue] = ["cascadeId": .string(cascadeId)]
        if startIndex > 0 {
            body["stepOffset"] = .int(startIndex)
        }
        let res = try await callUnaryJSON(
            method: "GetCascadeTrajectorySteps",
            body: body,
            instanceUuidOverride: instanceUuidOverride
        )
        if res["truncatedAt"] != nil {
            return try await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: startIndex,
                endIndex: max(endIndex, Self.protobufStepThreshold),
                instanceUuidOverride: instanceUuidOverride
            )
        }
        guard let rawSteps = res["steps"]?.arrayValue else { return [] }
        return rawSteps.enumerated().compactMap { offset, item in
            Self.decodeJSONStep(item, cascadeId: cascadeId, fallbackIndex: startIndex + offset)
        }
    }

    /// Fetches trajectory steps using binary Protobuf (`application/proto`) to bypass the 600-step JSON ceiling.
    public func fetchTrajectoryStepsProtobuf(
        cascadeId: String,
        startIndex: Int,
        endIndex: Int,
        instanceUuidOverride: String? = nil,
        allowCrossHostFailover: Bool = false
    ) async throws -> [CascadeStep] {
        let protoReqBytes = ProtobufStepCodec.encodeGetStepsRequest(
            cascadeId: cascadeId,
            startIndex: startIndex,
            endIndex: endIndex
        )
        if channel == .cloudRelay {
            let (rawBytes, _) = try await callCloudRelayProxyCommand(
                method: "GetCascadeTrajectorySteps",
                payload: protoReqBytes,
                contentType: "application/proto",
                instanceUuidOverride: instanceUuidOverride,
                allowCrossHostFailover: allowCrossHostFailover
            )
            let unwrapped = Self.unwrapConnectFramedPayloadIfNeeded(rawBytes)
            let decoded = ProtobufStepCodec.decodeStepsResponse(unwrapped, cascadeId: cascadeId)
            return await repairUnrecognizedWireInteractionsIfNeeded(
                decoded,
                cascadeId: cascadeId,
                instanceUuidOverride: instanceUuidOverride,
                allowCrossHostFailover: allowCrossHostFailover
            )
        }

        let url = endpointURL.appendingPathComponent("\(Self.servicePrefix)/GetCascadeTrajectorySteps")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/proto", forHTTPHeaderField: "Content-Type")
        request.setValue("application/proto", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        applyAuthHeaders(to: &request)
        request.httpBody = protoReqBytes

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AntigravityRPCError.httpError(statusCode: status, body: "Binary step fetch failed")
        }
        let unwrapped = Self.unwrapConnectFramedPayloadIfNeeded(data)
        let decoded = ProtobufStepCodec.decodeStepsResponse(unwrapped, cascadeId: cascadeId)
        return await repairUnrecognizedWireInteractionsIfNeeded(
            decoded,
            cascadeId: cascadeId,
            instanceUuidOverride: instanceUuidOverride,
            allowCrossHostFailover: allowCrossHostFailover
        )
    }

    /// Forward-compatibility repair: if a >600-step binary Protobuf trajectory contains a `WAITING` step
    /// whose `RequestedInteraction` used a brand-new wire field number unknown to this build, issues a
    /// single targeted JSON `GetCascadeTrajectorySteps(stepOffset:)` call to recover the exact JSON
    /// `rawMemberKey` and full human-readable summary.
    internal func repairUnrecognizedWireInteractionsIfNeeded(
        _ steps: [CascadeStep],
        cascadeId: String,
        instanceUuidOverride: String? = nil,
        allowCrossHostFailover: Bool = false
    ) async -> [CascadeStep] {
        let targets = steps.indices.filter { idx in
            steps[idx].isWaitingForUser && steps[idx].requestedInteraction?.isUnrecognizedWireMember == true
        }
        guard !targets.isEmpty else { return steps }

        var repaired = steps
        for idx in targets.prefix(2) {
            let stepIndex = repaired[idx].stepIndex
            var reqBody: [String: JSONValue] = [
                "cascadeId": .string(cascadeId),
                "stepOffset": .int(stepIndex)
            ]
            if cascadeId.hasPrefix("v1/") {
                reqBody["backend"] = .string("BACKEND_TYPE_REMOTE_AICODE")
            }
            guard let jsonResp = try? await callUnaryJSON(
                method: "GetCascadeTrajectorySteps",
                body: reqBody,
                instanceUuidOverride: instanceUuidOverride,
                allowCrossHostFailover: allowCrossHostFailover,
                timeoutInterval: 5.0
            ),
            let rawSteps = jsonResp["steps"]?.arrayValue,
            !rawSteps.isEmpty else {
                continue
            }
            let decodedSlice = rawSteps.enumerated().compactMap { offset, item in
                Self.decodeJSONStep(item, cascadeId: cascadeId, fallbackIndex: stepIndex + offset)
            }
            if let matched = decodedSlice.first(where: { $0.stepIndex == stepIndex }),
               let recoveredInteraction = matched.requestedInteraction,
               !recoveredInteraction.isUnrecognizedWireMember,
               let key = recoveredInteraction.rawMemberKey, !key.isEmpty {
                repaired[idx].requestedInteraction = recoveredInteraction
            }
        }
        return repaired
    }


    // MARK: - Conversation & Trajectory Operations (`UE01`, `UE03`, `UE07`)

    /// Fetches all sessions from either Desktop `language_server` (`trajectorySummaries` map)
    /// or Companion/Mock (`trajectories` array).
    public func getAllCascadeTrajectories(
        instanceUuidOverride: String? = nil,
        originHostName: String? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> [CascadeSummary] {
        let res = try await callUnaryJSON(
            method: "GetAllCascadeTrajectories",
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: timeoutInterval
        )
        let now = Date()
        let allCloudProjects = Array(self.cachedCloudProjectsById.values)
        let effectiveUuid = instanceUuidOverride ?? resolvedInstanceUuid

        // Format A: Native Desktop `language_server` map `{"trajectorySummaries": {"<cascadeId>": {...}}}`
        if let summaryMap = res["trajectorySummaries"]?.objectValue {
            let decoded = summaryMap.compactMap { cascadeId, value -> CascadeSummary? in
                guard var s = Self.decodeTrajectorySummaryEntry(cascadeId: cascadeId, value: value, now: now) else {
                    return nil
                }
                s.originInstanceUuid = effectiveUuid
                s.originHostName = s.isCloud ? "Antigravity" : originHostName
                if let cp = Self.matchCloudProject(for: s, cloudProjects: allCloudProjects) {
                    s.isCloud = true
                    s.cloudProjectId = cp.cloudProjectId ?? cp.id
                    s.projectSlug = cp.name
                    s.workspaceUri = cp.workspaceUri
                    s.originHostName = "Antigravity"
                }
                return s
            }
            return decoded.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.cascadeId < rhs.cascadeId
            }
        }

        // Format B: Array `{"trajectories": [...]}`
        guard let list = res["trajectories"]?.arrayValue else { return [] }
        return list.compactMap { item -> CascadeSummary? in
            guard let obj = item.objectValue,
                  let id = obj["cascadeId"]?.stringValue,
                  let title = obj["title"]?.stringValue else { return nil }
            let rawUri = (obj["workspaceUri"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceHint = [obj["runtime"]?.stringValue, obj["source"]?.stringValue]
                .compactMap { $0 }
                .joined(separator: " ")
            let isCloud = (obj["isCloud"]?.boolValue ?? false)
                || (obj["cloud"]?.boolValue ?? false)
                || AntigravityCloudDetector.isCloudWorkspaceURI(rawUri, cascadeId: id, sourceHint: sourceHint)
            let isUnassigned = rawUri.isEmpty
                || AntigravityCloudDetector.isGenericContainerURI(rawUri)
                || AntigravityCloudDetector.isPlaygroundScratchURI(rawUri)
            let uri = isUnassigned
                ? (AntigravityCloudDetector.isPlaygroundScratchURI(rawUri) ? rawUri : "")
                : AntigravityCloudDetector.normalizeWorkspaceURI(rawUri, isCloud: isCloud)
            let explicitSlug = obj["projectSlug"]?.stringValue ?? obj["project"]?.stringValue
            let slug: String
            if let explicitSlug, !AntigravityCloudDetector.isNoProjectSlug(explicitSlug) {
                slug = explicitSlug
            } else if isUnassigned {
                slug = AntigravityCloudDetector.noProjectDisplayName
            } else {
                slug = (rawUri as NSString).lastPathComponent
            }
            let statusName = obj["status"]?.stringValue ?? "CORTEX_STEP_STATUS_DONE"
            let stepCount = obj["stepCount"]?.intValue ?? 0
            let branch = isUnassigned ? "" : (obj["branchName"]?.stringValue ?? "main")
            let subtitle = obj["statusSubtitle"]?.stringValue ?? ""
            let updatedAt = Self.parseProtoTimestamp(obj["updatedAt"] ?? obj["lastModifiedTime"]) ?? now
            let relativeLabel = obj["relativeTimeLabel"]?.stringValue ?? Self.formatRelativeTimeLabel(from: updatedAt, now: now)
            return CascadeSummary(
                cascadeId: id,
                title: title,
                projectSlug: slug,
                workspaceUri: uri,
                branchName: branch,
                status: CortexStepStatus.from(jsonName: statusName),
                stepCount: stepCount,
                updatedAt: updatedAt,
                relativeTimeLabel: relativeLabel,
                statusSubtitle: subtitle,
                isPinned: obj["isPinned"]?.boolValue ?? false,
                isArchived: obj["isArchived"]?.boolValue ?? false,
                isUnread: obj["isUnread"]?.boolValue ?? false,
                isCloud: isCloud,
                originInstanceUuid: effectiveUuid,
                originHostName: isCloud ? "Antigravity" : originHostName
            )
        }
    }

    public static func normalizeProtoModelEnum(_ modelId: String) -> String {
        let trimmed = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("MODEL_") {
            return trimmed
        }
        let lower = trimmed.lowercased()
        if lower.contains("orchestrator") {
            if lower.contains("carbon") { return "MODEL_ORCHESTRATOR_CARBON" }
            if lower.contains("argon") { return "MODEL_ORCHESTRATOR_ARGON" }
            return "MODEL_ORCHESTRATOR_NEON"
        }
        if lower.contains("neon") { return "MODEL_GOOGLE_GEMINI_4_NEON" }
        if lower.contains("carbon") { return "MODEL_GOOGLE_GEMINI_4_CARBON" }
        if lower.contains("argon") { return "MODEL_GOOGLE_GEMINI_4_ARGON" }
        if lower.contains("hydrogen") { return "MODEL_GOOGLE_GEMINI_4_HYDROGEN" }
        if lower.contains("flash") {
            return "MODEL_PLACEHOLDER_M18"
        }
        if lower.contains("sonnet") {
            return "MODEL_PLACEHOLDER_M35"
        }
        if lower.contains("opus") {
            return "MODEL_PLACEHOLDER_M26"
        }
        if lower.contains("low") {
            return "MODEL_PLACEHOLDER_M36"
        }
        if lower.contains("gemini") || lower.contains("pro") {
            return "MODEL_PLACEHOLDER_M37"
        }
        return "MODEL_PLACEHOLDER_M37"
    }

    /// Creates a new Cascade session (`StartCascade`) on either Local or Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`),
    /// supporting both project-bound workspaces and unassigned `No Project` sessions.
    public func startCascade(
        workspaceUri: String,
        initialPrompt: String = "",
        modelId: String = "MODEL_PLACEHOLDER_M37",
        cloudProjectId: String? = nil,
        isCloud: Bool = false,
        instanceUuidOverride: String? = nil
    ) async throws -> String {
        let protoModel = Self.normalizeProtoModelEnum(modelId)
        let clientCid = UUID().uuidString.lowercased()
        var payload: [String: JSONValue] = [
            "cascadeId": .string(clientCid),
            "metadata": .object([
                "ideName": .string("antigravity-ios"),
                "ideVersion": .string(Self.clientAppVersion)
            ]),
            "modelId": .string(protoModel)
        ]
        if let cloudProjectId, !cloudProjectId.isEmpty {
            payload["backend"] = .string("BACKEND_TYPE_REMOTE_AICODE")
            payload["projectEnvConfig"] = .object([
                "projectId": .string(cloudProjectId),
                "defaultProjectEnvironment": .object([:])
            ])
        } else if isCloud {
            payload["backend"] = .string("BACKEND_TYPE_REMOTE_AICODE")
        } else if !workspaceUri.isEmpty && !AntigravityCloudDetector.isGenericContainerURI(workspaceUri) {
            payload["workspaceUris"] = .array([.string(workspaceUri)])
        }
        if !initialPrompt.isEmpty {
            payload["initialUserInput"] = .string(initialPrompt)
        }
        let res = try await callUnaryJSON(
            method: "StartCascade",
            body: payload,
            instanceUuidOverride: instanceUuidOverride
        )
        if let returnedId = Self.nonEmptyString(res["cascadeId"]?.stringValue) {
            return returnedId
        }
        return clientCid
    }

    /// Sends a user prompt + rich multimodal/context items + model/mode/effort/permission config (`SendUserCascadeMessage`).
    /// Encodes `Planning` vs `Fast` via `conversational.agenticMode` (`CONVERSATIONAL_PLANNER_MODE_DEFAULT`),
    /// applies the selected `AgentPermissionPreset` via `plannerConfig.toolConfig`,
    /// and sets `planModel` alongside `requestedModel` for Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) sessions.
    public func sendUserCascadeMessage(
        cascadeId: String,
        message: String,
        attachments: [ComposerAttachmentChip] = [],
        modelId: String,
        effort: ThinkingEffortLevel = .high,
        mode: CascadeExecutionMode = .planning,
        agentPersona: String = "Default",
        isModelAlias: Bool = false,
        isCloud: Bool = false,
        permissionPreset: AgentPermissionPreset? = nil,
        instanceUuidOverride: String? = nil
    ) async throws {
        var items: [JSONValue] = [.object(["text": .string(message)])]
        for chip in attachments {
            switch chip.kind {
            case .imageScreenshot, .audioRecording, .videoClip, .pdfDocument, .archiveZip, .genericFile:
                if let b64 = chip.inlineBase64Data, !b64.isEmpty {
                    items.append(
                        .object([
                            "item": .object([
                                "media": .object([
                                    "uri": .string(chip.targetUri),
                                    "label": .string(chip.label),
                                    "mimeType": .string(chip.mimeType ?? "application/octet-stream"),
                                    "inlineBase64Data": .string(b64),
                                    "kind": .string(chip.kind.rawValue)
                                ])
                            ])
                        ])
                    )
                } else {
                    items.append(
                        .object([
                            "item": .object([
                                "file": .object([
                                    "absoluteUri": .string(chip.targetUri),
                                    "label": .string(chip.label)
                                ])
                            ])
                        ])
                    )
                }
            case .codeQuote:
                items.append(
                    .object([
                        "item": .object([
                            "codeQuote": .object([
                                "uri": .string(chip.targetUri),
                                "label": .string(chip.label)
                            ])
                        ])
                    ])
                )
            case .pluginMention, .skill, .conversationMention, .action:
                items.append(
                    .object([
                        "item": .object([
                            "mention": .object([
                                "kind": .string(chip.kind.rawValue),
                                "targetUri": .string(chip.targetUri),
                                "label": .string(chip.label)
                            ])
                        ])
                    ])
                )
            case .fileMention, .folder, .terminalLog:
                items.append(
                    .object([
                        "item": .object([
                            "file": .object([
                                "absoluteUri": .string(chip.targetUri),
                                "label": .string(chip.label)
                            ])
                        ])
                    ])
                )
            }
        }

        let protoModel = Self.normalizeProtoModelEnum(modelId)
        let requestedModelPayload: JSONValue = isModelAlias
            ? .object(["alias": .string(modelId)])
            : .object(["model": .string(protoModel)])

        let effectivePermission: AgentPermissionPreset = {
            if let preset = permissionPreset, preset != .inheritGlobal {
                return preset
            }
            return AgentPermissionPreset.defaultPreset(isRemote: isCloud || cascadeId.hasPrefix("v1/"))
        }()
        var toolConfig: [String: JSONValue] = [
            "code": .object(["allowEditGitignore": .bool(true)]),
            "viewFile": .object(["allowViewGitignore": .bool(true)]),
            "grep": .object(["allowAccessGitignore": .bool(true)])
        ]
        switch effectivePermission {
        case .requestReview:
            toolConfig["runCommand"] = .object([
                "autoCommandConfig": .object([
                    "autoExecutionPolicy": .string("CASCADE_COMMANDS_AUTO_EXECUTION_OFF")
                ])
            ])
            toolConfig["notifyUser"] = .object([
                "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_ALWAYS")
            ])
        case .defaultPolicy, .auto, .inheritGlobal:
            toolConfig["notifyUser"] = .object([
                "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_AUTO")
            ])
        case .turbo:
            toolConfig["runCommand"] = .object([
                "autoCommandConfig": .object([
                    "autoExecutionPolicy": .string("CASCADE_COMMANDS_AUTO_EXECUTION_EAGER")
                ])
            ])
            toolConfig["notifyUser"] = .object([
                "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_TURBO")
            ])
        }

        var plannerConfig: [String: JSONValue] = [
            "conversational": .object([
                "plannerMode": .string("CONVERSATIONAL_PLANNER_MODE_DEFAULT"),
                "agenticMode": .bool(mode == .planning)
            ]),
            "toolConfig": .object(toolConfig),
            "requestedModel": requestedModelPayload,
            "thinkingEffort": .string(effort.protoWireValue)
        ]
        if agentPersona != "Default" && !agentPersona.isEmpty {
            plannerConfig["agentPersona"] = .string(agentPersona)
        }
        plannerConfig["permissionPreset"] = .string(effectivePermission.rawValue)
        let isRemoteCloud = isCloud || cascadeId.hasPrefix("v1/")
        if isRemoteCloud && !isModelAlias && protoModel.hasPrefix("MODEL_") {
            plannerConfig["planModel"] = .string(protoModel)
        }

        let modelCfgObj: [String: JSONValue] = [
            "modelId": .string(modelId),
            "thinkingEffort": .string(effort.protoWireValue),
            "mode": .string(mode.rawValue.uppercased()),
            "agentPersona": .string(agentPersona),
            "permissionPreset": .string(effectivePermission.rawValue)
        ]

        _ = try await callUnaryJSON(
            method: "SendUserCascadeMessage",
            body: [
                "cascadeId": .string(cascadeId),
                "items": .array(items),
                "userResponse": .string(message),
                "metadata": .object([
                    "ideName": .string("antigravity-ios"),
                    "ideVersion": .string(Self.clientAppVersion)
                ]),
                "cascadeConfig": .object([
                    "plannerConfig": .object(plannerConfig)
                ]),
                "modelConfig": .object(modelCfgObj)
            ],
            instanceUuidOverride: instanceUuidOverride,
            allowCrossHostFailover: isRemoteCloud,
            timeoutInterval: 300.0
        )
    }

    public func handleCascadeUserInteraction(
        _ payload: CascadeUserInteractionPayload,
        instanceUuidOverride: String? = nil
    ) async throws {
        var interactionObj: [String: JSONValue] = [
            "trajectoryId": .string(payload.cascadeId),
            "stepIndex": .int(payload.stepIndex)
        ]

        if let rc = payload.runCommand {
            interactionObj["runCommand"] = .object([
                "confirm": .bool(rc.confirm),
                "proposedCommandLine": .string(rc.proposedCommandLine),
                "submittedCommandLine": .string(rc.submittedCommandLine),
                "faceIdVerified": .bool(rc.faceIdVerified)
            ])
        } else if let perm = payload.permission {
            interactionObj["permission"] = .object([
                "allow": .bool(perm.allow),
                "scope": .string(perm.scope),
                "turnGrants": .object([
                    "allow": .array(perm.grantPatterns.map(JSONValue.string)),
                    "deny": .array([])
                ])
            ])
        } else if let fp = payload.filePermission {
            var fpObj: [String: JSONValue] = [
                "allow": .bool(fp.allow),
                "scope": .string(fp.scope)
            ]
            if let uri = fp.absolutePathUri, !uri.isEmpty {
                fpObj["absolutePathUri"] = .string(uri)
            }
            interactionObj["filePermission"] = .object(fpObj)
        } else if let qa = payload.askQuestion {
            var qaObj: [String: JSONValue] = [
                "selectedOptions": .array(qa.selectedOptions.map(JSONValue.string))
            ]
            if let custom = qa.customResponse {
                qaObj["customResponse"] = .string(custom)
            }
            interactionObj["askQuestion"] = .object(qaObj)
        } else if let confirm = payload.genericConfirm {
            let memberKey = payload.rawMemberKey ?? payload.kind.rawValue
            if payload.kind == .deploy {
                interactionObj[memberKey] = .object(["cancel": .bool(!confirm)])
            } else {
                var genericObj: [String: JSONValue] = ["confirm": .bool(confirm)]
                if let scope = payload.approvalScope {
                    genericObj["scope"] = .string(scope)
                }
                interactionObj[memberKey] = .object(genericObj)
            }
        }

        do {
            _ = try await callUnaryJSON(
                method: "HandleCascadeUserInteraction",
                body: ["interaction": .object(interactionObj)],
                instanceUuidOverride: instanceUuidOverride
            )
        } catch let AntigravityRPCError.httpError(statusCode, errorBody)
            where statusCode == 400
                || errorBody.lowercased().contains("unknown field")
                || errorBody.lowercased().contains("invalid_argument") {
            // Retry with strict upstream-minimal proto3 fields (e.g., Desktop servers whose protojson rejects optional `scope` or expects `allow`)
            var fallbackObj: [String: JSONValue] = [
                "trajectoryId": .string(payload.cascadeId),
                "stepIndex": .int(payload.stepIndex)
            ]
            if let perm = payload.permission {
                var minPerm: [String: JSONValue] = ["allow": .bool(perm.allow)]
                if !perm.grantPatterns.isEmpty {
                    minPerm["turnGrants"] = .object([
                        "allow": .array(perm.grantPatterns.map(JSONValue.string)),
                        "deny": .array([])
                    ])
                }
                fallbackObj["permission"] = .object(minPerm)
            } else if let fp = payload.filePermission {
                let compatScope = (fp.scope == "PERMISSION_SCOPE_CONVERSATION" || fp.scope == "PERMISSION_SCOPE_ALWAYS")
                    ? "PERMISSION_SCOPE_TURN"
                    : "PERMISSION_SCOPE_ONCE"
                var minFp: [String: JSONValue] = [
                    "allow": .bool(fp.allow),
                    "scope": .string(compatScope)
                ]
                if let uri = fp.absolutePathUri, !uri.isEmpty {
                    minFp["absolutePathUri"] = .string(uri)
                }
                fallbackObj["filePermission"] = .object(minFp)
            } else if let confirm = payload.genericConfirm {
                let memberKey = payload.rawMemberKey ?? payload.kind.rawValue
                let useAllowKey = errorBody.lowercased().contains("\"confirm\"")
                fallbackObj[memberKey] = .object([
                    (useAllowKey ? "allow" : "confirm"): .bool(confirm)
                ])
            } else {
                throw AntigravityRPCError.httpError(statusCode: statusCode, body: errorBody)
            }

            _ = try await callUnaryJSON(
                method: "HandleCascadeUserInteraction",
                body: ["interaction": .object(fallbackObj)],
                instanceUuidOverride: instanceUuidOverride
            )
        }
    }

    public func handleCascadeUserInteraction(
        step: CascadeStep,
        decision: InteractionDecision,
        instanceUuidOverride: String? = nil
    ) async throws {
        guard let payload = InteractionBuilder.buildPayload(step: step, decision: decision) else {
            throw AntigravityRPCError.interactionRejected
        }
        try await handleCascadeUserInteraction(payload, instanceUuidOverride: instanceUuidOverride)
    }

    public func cancelCascadeInvocation(
        cascadeId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        _ = try await callUnaryJSON(
            method: "CancelCascadeInvocation",
            body: ["cascadeId": .string(cascadeId)],
            instanceUuidOverride: instanceUuidOverride
        )
    }

    public func pinCascade(
        cascadeId: String,
        isPinned: Bool,
        instanceUuidOverride: String? = nil
    ) async throws {
        let annotationsBody: [String: JSONValue] = [
            "cascadeId": .string(cascadeId),
            "annotations": .object(["pinned": .bool(isPinned)]),
            "mergeAnnotations": .bool(true)
        ]
        if channel == .cloudRelay {
            _ = try await callUnaryJSON(
                method: "UpdateConversationAnnotations",
                body: annotationsBody,
                instanceUuidOverride: instanceUuidOverride
            )
            return
        }
        do {
            _ = try await callUnaryJSON(
                method: "PinCascade",
                body: [
                    "cascadeId": .string(cascadeId),
                    "isPinned": .bool(isPinned)
                ],
                instanceUuidOverride: instanceUuidOverride
            )
        } catch where ProtocolCompatibilityEngine.isMethodUnimplementedError(error) {
            _ = try await callUnaryJSON(
                method: "UpdateConversationAnnotations",
                body: annotationsBody,
                instanceUuidOverride: instanceUuidOverride
            )
        }
    }

    public func renameCascade(
        cascadeId: String,
        newTitle: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        let annotationsBody: [String: JSONValue] = [
            "cascadeId": .string(cascadeId),
            "annotations": .object(["title": .string(newTitle)]),
            "mergeAnnotations": .bool(true)
        ]
        if channel == .cloudRelay {
            _ = try await callUnaryJSON(
                method: "UpdateConversationAnnotations",
                body: annotationsBody,
                instanceUuidOverride: instanceUuidOverride
            )
            return
        }
        do {
            _ = try await callUnaryJSON(
                method: "RenameCascade",
                body: [
                    "cascadeId": .string(cascadeId),
                    "title": .string(newTitle)
                ],
                instanceUuidOverride: instanceUuidOverride
            )
        } catch where ProtocolCompatibilityEngine.isMethodUnimplementedError(error) {
            _ = try await callUnaryJSON(
                method: "UpdateConversationAnnotations",
                body: annotationsBody,
                instanceUuidOverride: instanceUuidOverride
            )
        }
    }

    public func moveCascadeToWorkspace(
        cascadeId: String,
        workspaceUri: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        _ = try await callUnaryJSON(
            method: "MoveCascadeToWorkspace",
            body: [
                "cascadeId": .string(cascadeId),
                "workspaceUri": .string(workspaceUri)
            ],
            instanceUuidOverride: instanceUuidOverride
        )
    }

    public func archiveCascade(
        cascadeId: String,
        isArchived: Bool = true,
        instanceUuidOverride: String? = nil
    ) async throws {
        let annotationsBody: [String: JSONValue] = [
            "cascadeId": .string(cascadeId),
            "annotations": .object(["archived": .bool(isArchived)]),
            "mergeAnnotations": .bool(true)
        ]
        if channel == .cloudRelay {
            _ = try await callUnaryJSON(
                method: "UpdateConversationAnnotations",
                body: annotationsBody,
                instanceUuidOverride: instanceUuidOverride
            )
            return
        }
        do {
            _ = try await callUnaryJSON(
                method: "ArchiveCascade",
                body: [
                    "cascadeId": .string(cascadeId),
                    "isArchived": .bool(isArchived)
                ],
                instanceUuidOverride: instanceUuidOverride
            )
        } catch where ProtocolCompatibilityEngine.isMethodUnimplementedError(error) {
            _ = try await callUnaryJSON(
                method: "UpdateConversationAnnotations",
                body: annotationsBody,
                instanceUuidOverride: instanceUuidOverride
            )
        }
    }

    public func deleteCascade(
        cascadeId: String,
        instanceUuidOverride: String? = nil
    ) async throws {
        if channel == .cloudRelay {
            _ = try await callUnaryJSON(
                method: "DeleteCascadeTrajectory",
                body: ["cascadeId": .string(cascadeId)],
                instanceUuidOverride: instanceUuidOverride
            )
            return
        }
        do {
            _ = try await callUnaryJSON(
                method: "DeleteCascade",
                body: ["cascadeId": .string(cascadeId)],
                instanceUuidOverride: instanceUuidOverride
            )
        } catch where ProtocolCompatibilityEngine.isMethodUnimplementedError(error) {
            _ = try await callUnaryJSON(
                method: "DeleteCascadeTrajectory",
                body: ["cascadeId": .string(cascadeId)],
                instanceUuidOverride: instanceUuidOverride
            )
        }
    }

    /// Updates `annotations.lastUserViewTime` on Antigravity Desktop (`UpdateConversationAnnotations`)
    /// so opening or marking a conversation as read on iOS clears the unread indicator on Desktop too.
    public func markCascadeViewed(
        cascadeId: String,
        viewedAt: Date = Date(),
        instanceUuidOverride: String? = nil
    ) async throws {
        guard !cascadeId.isEmpty else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: viewedAt)
        _ = try await callUnaryJSON(
            method: "UpdateConversationAnnotations",
            body: [
                "cascadeId": .string(cascadeId),
                "annotations": .object(["lastUserViewTime": .string(timestamp)]),
                "mergeAnnotations": .bool(true)
            ],
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: 6.0
        )
    }

}
