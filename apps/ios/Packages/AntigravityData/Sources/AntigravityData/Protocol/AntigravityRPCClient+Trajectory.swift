import Foundation

/// Adaptive trajectory step sync (local-default binary Protobuf + targeted JSON repair + runtime JSON ceiling learning) and conversation lifecycle RPCs.
extension AntigravityRPCClient {
    internal static func isRemoteCloudCascade(cascadeId: String, isCloud: Bool) -> Bool {
        isCloud || AntigravityCloudDetector.isCloudWorkspaceURI("", cascadeId: cascadeId)
    }

    internal func orderedCloudBackendFields(
        for method: String,
        targetUuid: String?
    ) -> [CloudTrajectoryBackendField] {
        let hostKey = capabilityHostKey(for: targetUuid)
        let preferred = preferredCloudBackendFieldByHostAndMethod["\(hostKey)|\(method)"]
        let stripped = capabilityProfilesByHost[hostKey]?.strippedFieldsByMethod[method] ?? []
        let base: [CloudTrajectoryBackendField] = [.backend, .backendType, .none]
        let ordered: [CloudTrajectoryBackendField] = {
            if let preferred {
                return [preferred] + base.filter { $0 != preferred }
            }
            return base
        }()
        let filtered = ordered.filter { field in
            guard let key = field.jsonKey else { return true }
            return !stripped.contains(key)
        }
        return filtered.isEmpty ? [.none] : filtered
    }

    internal func recordPreferredCloudBackendField(
        _ field: CloudTrajectoryBackendField,
        for method: String,
        targetUuid: String?
    ) {
        let hostKey = capabilityHostKey(for: targetUuid)
        preferredCloudBackendFieldByHostAndMethod["\(hostKey)|\(method)"] = field
    }

    internal static func buildTrajectoryRequestBody(
        cascadeId: String,
        cloudField: CloudTrajectoryBackendField?,
        stepOffset: Int = 0
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = ["cascadeId": .string(cascadeId)]
        if stepOffset > 0 {
            body["stepOffset"] = .int(stepOffset)
        }
        if let key = cloudField?.jsonKey {
            body[key] = .string("BACKEND_TYPE_REMOTE_AICODE")
        }
        return body
    }

    /// Wakes a dormant disk/remote trajectory into `language_server` memory (`LoadTrajectory`).
    /// For Antigravity Cloud sessions, negotiates `backend` -> `backendType` -> bare `{cascadeId}`
    /// and caches the accepted variant per host so strict protojson daemons wake cleanly.
    public func loadTrajectory(
        cascadeId: String,
        isCloud: Bool = false,
        instanceUuidOverride: String? = nil
    ) async throws {
        let isRemoteCloud = Self.isRemoteCloudCascade(cascadeId: cascadeId, isCloud: isCloud)
        if !isRemoteCloud {
            _ = try await callUnaryJSON(
                method: "LoadTrajectory",
                body: ["cascadeId": .string(cascadeId)],
                instanceUuidOverride: instanceUuidOverride,
                allowCrossHostFailover: false,
                timeoutInterval: 8.0
            )
            return
        }

        let candidates = orderedCloudBackendFields(for: "LoadTrajectory", targetUuid: instanceUuidOverride)
        var lastError: Error? = nil
        for variant in candidates {
            do {
                _ = try await callUnaryJSON(
                    method: "LoadTrajectory",
                    body: Self.buildTrajectoryRequestBody(cascadeId: cascadeId, cloudField: variant),
                    instanceUuidOverride: instanceUuidOverride,
                    allowCrossHostFailover: true,
                    timeoutInterval: 8.0,
                    allowStripUnknownFields: false
                )
                recordPreferredCloudBackendField(variant, for: "LoadTrajectory", targetUuid: instanceUuidOverride)
                return
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch let AntigravityRPCError.httpError(statusCode, body) {
                lastError = AntigravityRPCError.httpError(statusCode: statusCode, body: body)
                let unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body)
                if let unknownField {
                    mutateCapabilityProfile(for: instanceUuidOverride) { profile in
                        profile.recordStrippedField(unknownField, forMethod: "LoadTrajectory")
                    }
                }
                let retryNext = statusCode == 400
                    || unknownField != nil
                    || ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(statusCode: statusCode, body: body)
                if !retryNext {
                    throw AntigravityRPCError.httpError(statusCode: statusCode, body: body)
                }
            } catch {
                throw error
            }
        }
        if let lastError {
            throw lastError
        }
    }

    // MARK: - Adaptive Binary Protobuf & JSON Ceiling Classifiers (Zero Hardcoded Thresholds)

    /// Extracts an explicit server-advertised JSON truncation ceiling from a `GetCascadeTrajectorySteps` response,
    /// returning `nil` when the server did not advertise truncation.
    internal static func extractJsonTruncationCeiling(
        from response: [String: JSONValue],
        fallbackStepCount: Int
    ) -> Int? {
        if let truncatedVal = response["truncatedAt"] {
            if let intVal = truncatedVal.intValue {
                return intVal > 0 ? intVal : nil
            }
            if let strVal = truncatedVal.stringValue {
                if let parsed = Int(strVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return parsed > 0 ? parsed : nil
                }
                if strVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return nil
                }
                return max(1, fallbackStepCount)
            }
            if case .null = truncatedVal {
                return nil
            }
            return max(1, fallbackStepCount)
        }
        if response["isTruncated"]?.boolValue == true || response["truncated"]?.boolValue == true {
            return max(1, fallbackStepCount)
        }
        return nil
    }

    /// Returns `true` when a JSON trajectory error indicates a server-side payload or step limit (e.g. HTTP 413 / `resource_exhausted`).
    internal static func isJsonPayloadLimitError(_ error: Error) -> Bool {
        if case let AntigravityRPCError.httpError(statusCode, body) = error {
            if statusCode == 413 {
                return true
            }
            let lower = body.lowercased()
            return lower.contains("resource_exhausted")
                || lower.contains("message too large")
                || lower.contains("max message size")
                || lower.contains("payload too large")
                || lower.contains("too many steps")
        }
        let lower = error.localizedDescription.lowercased()
        return lower.contains("resource_exhausted") || lower.contains("message too large")
    }

    /// Returns `true` when a host explicitly rejects `Content-Type: application/proto` on `GetCascadeTrajectorySteps`.
    internal static func isBinaryProtobufUnsupportedError(_ error: Error) -> Bool {
        if case let AntigravityRPCError.httpError(statusCode, body) = error {
            if statusCode == 415 || statusCode == 406 || statusCode == 501 {
                return true
            }
            if statusCode == 400 {
                let lower = body.lowercased()
                return lower.contains("unsupported media")
                    || lower.contains("application/proto")
                    || lower.contains("content-type")
                    || lower.contains("invalid json")
                    || lower.contains("unexpected character")
            }
        }
        return false
    }

    /// Fetches trajectory steps using Binary Protobuf by default on local hosts (with targeted JSON repair for
    /// unknown wire interactions/steps), falling back to JSON with runtime ceiling discovery on Cloud hosts or
    /// hosts that reject `application/proto`.
    public func fetchTrajectorySteps(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = 0,
        instanceUuidOverride: String? = nil
    ) async throws -> [CascadeStep] {
        let isRemoteCloud = Self.isRemoteCloudCascade(cascadeId: cascadeId, isCloud: false)
        if !isRemoteCloud && !isBinaryProtobufStepsUnsupported(for: instanceUuidOverride) {
            do {
                let protoSteps = try await fetchTrajectoryStepsProtobuf(
                    cascadeId: cascadeId,
                    startIndex: startIndex,
                    endIndex: endIndex,
                    instanceUuidOverride: instanceUuidOverride
                )
                if !protoSteps.isEmpty {
                    return protoSteps
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                if Self.isBinaryProtobufUnsupportedError(error) {
                    recordBinaryProtobufStepsUnsupported(for: instanceUuidOverride)
                }
            }
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
        let isRemoteCloud = Self.isRemoteCloudCascade(cascadeId: cascadeId, isCloud: isCloud)
        let pinnedTarget = (channel == .cloudRelay) ? pinnedInstance(for: cascadeId) : nil
        let primaryTarget: String? = {
            if channel == .cloudRelay {
                return selectReachableRelayUuid(
                    preferred: pinnedTarget ?? instanceUuidOverride,
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
                    recordPinnedInstance(for: cascadeId, instanceUuid: primaryTarget)
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
            var probedUuids = Set<String>()
            if let primaryTarget {
                probedUuids.insert(primaryTarget)
            }

            for pass in 0..<2 {
                let instancesToSearch: [RelayInstanceInfo]
                if pass == 0 {
                    instancesToSearch = cachedRelayInstances
                } else {
                    let shouldRefreshInstances: Bool = {
                        if cachedRelayInstances.isEmpty { return true }
                        if let err = primaryError, case let AntigravityRPCError.httpError(code, _) = err {
                            return code == 404 || code == 502 || code == 503 || code == 504
                        }
                        return false
                    }()
                    guard shouldRefreshInstances,
                          let refreshed = try? await listRelayInstances(timeoutInterval: 4.0),
                          !refreshed.isEmpty else {
                        break
                    }
                    self.cachedRelayInstances = refreshed
                    instancesToSearch = refreshed
                }

                guard !instancesToSearch.isEmpty else { continue }
                let seedUuid = primaryTarget ?? instanceUuidOverride ?? resolvedInstanceUuid
                let familySeed = instancesToSearch.first(where: { $0.uuid == seedUuid })?.name
                    ?? (instanceUuidOverride == nil && !Self.isWildcardRelayIdentifier(targetInstanceIdentifier) ? targetInstanceIdentifier : "")
                let peerCandidates = instancesToSearch
                    .filter { inst in
                        guard inst.status.isReachable && !probedUuids.contains(inst.uuid) else { return false }
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
                    probedUuids.insert(peer.uuid)
                    do {
                        let peerSteps = try await fetchStepsFromSingleInstance(
                            cascadeId: cascadeId,
                            knownStepCount: knownStepCount,
                            isCloud: isRemoteCloud,
                            targetUuid: peer.uuid
                        )
                        if !peerSteps.isEmpty {
                            recordPinnedInstance(for: cascadeId, instanceUuid: peer.uuid)
                            if instanceUuidOverride == nil && !isRemoteCloud {
                                self.resolvedInstanceUuid = peer.uuid
                            }
                            return peerSteps
                        }
                    } catch let AntigravityRPCError.unauthorized(msg) {
                        throw AntigravityRPCError.unauthorized(msg)
                    } catch {
                        if primaryError == nil || primaryTarget == nil {
                            primaryError = error
                        }
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
        let isRemoteCloud = Self.isRemoteCloudCascade(cascadeId: cascadeId, isCloud: isCloud)
        let wakeKey = "\(targetUuid ?? "direct")|\(cascadeId)"
        var lastError: Error? = nil

        // Path 0 (Antigravity 2.x Cloud Primary): Remote Cloud (`v1/...`) conversations live on
        // Google's remote backend rather than local `.pb` files, so `GetCascadeTrajectorySteps` /
        // `LoadTrajectory` / `GetCascadeTrajectory` often return `not_found: trajectory not found`
        // even for actively running Cloud chats. `StreamAgentStateUpdates` is the authoritative
        // Antigravity 2.x streaming RPC that delivers live & historical Cloud trajectories.
        if isRemoteCloud {
            do {
                if let streamedSteps = try await fetchStepsViaAgentStateStream(
                    cascadeId: cascadeId,
                    isRemoteCloud: true,
                    targetUuid: targetUuid,
                    timeoutSeconds: 5.0
                ), !streamedSteps.isEmpty {
                    wokenInstanceCascadeKeys.insert(wakeKey)
                    return streamedSteps
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !ProtocolCompatibilityEngine.isMethodUnimplementedError(error) {
                    lastError = error
                }
            }
        }

        // Path 1 (Default for Local PC Hosts): Binary Protobuf (`application/proto`) first.
        // Saves ~65% mobile bandwidth, avoids any server-side JSON step truncation, wakes dormant
        // disk sessions on empty OR 404 `not_found`, and repairs unknown wire interactions via JSON.
        let protoAllowed = !isRemoteCloud && !isBinaryProtobufStepsUnsupported(for: targetUuid)
        if protoAllowed {
            var shouldWakeAndRetryProto = false
            do {
                let protoSteps = try await fetchTrajectoryStepsProtobuf(
                    cascadeId: cascadeId,
                    startIndex: 0,
                    endIndex: knownStepCount,
                    instanceUuidOverride: targetUuid,
                    allowCrossHostFailover: false
                )
                if !protoSteps.isEmpty {
                    wokenInstanceCascadeKeys.insert(wakeKey)
                    return protoSteps
                }
                shouldWakeAndRetryProto = knownStepCount > 0 || !wokenInstanceCascadeKeys.contains(wakeKey)
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                if Self.isBinaryProtobufUnsupportedError(error) {
                    recordBinaryProtobufStepsUnsupported(for: targetUuid)
                } else {
                    lastError = error
                    if ProtocolCompatibilityEngine.isTrajectoryNotFoundError(error) {
                        shouldWakeAndRetryProto = true
                    }
                }
            }

            if shouldWakeAndRetryProto {
                do {
                    try await loadTrajectory(cascadeId: cascadeId, isCloud: false, instanceUuidOverride: targetUuid)
                } catch let AntigravityRPCError.unauthorized(msg) {
                    throw AntigravityRPCError.unauthorized(msg)
                } catch {
                    // Best-effort wake; still retry Binary Protobuf and fall through to Path 2 if needed.
                }
                do {
                    let retryProtoSteps = try await fetchTrajectoryStepsProtobuf(
                        cascadeId: cascadeId,
                        startIndex: 0,
                        endIndex: knownStepCount,
                        instanceUuidOverride: targetUuid,
                        allowCrossHostFailover: false
                    )
                    if !retryProtoSteps.isEmpty {
                        wokenInstanceCascadeKeys.insert(wakeKey)
                        return retryProtoSteps
                    }
                } catch let AntigravityRPCError.unauthorized(msg) {
                    throw AntigravityRPCError.unauthorized(msg)
                } catch {
                    if Self.isBinaryProtobufUnsupportedError(error) {
                        recordBinaryProtobufStepsUnsupported(for: targetUuid)
                    } else {
                        lastError = error
                    }
                }
            }
        }

        // Path 2: JSON (`GetCascadeTrajectorySteps` + `LoadTrajectory` + `GetCascadeTrajectory`)
        // for Cloud fallback or when Binary Protobuf is unsupported/unavailable —
        // with zero hardcoded thresholds and runtime per-host ceiling learning.
        var adaptiveError: Error? = nil
        let adaptiveSteps: [CascadeStep]
        do {
            adaptiveSteps = try await fetchStepsViaAdaptiveJSON(
                cascadeId: cascadeId,
                knownStepCount: knownStepCount,
                isRemoteCloud: isRemoteCloud,
                targetUuid: targetUuid,
                wakeKey: wakeKey,
                initialError: lastError
            )
        } catch let AntigravityRPCError.unauthorized(msg) {
            throw AntigravityRPCError.unauthorized(msg)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            adaptiveError = error
            adaptiveSteps = []
        }

        if !adaptiveSteps.isEmpty {
            return adaptiveSteps
        }

        // Path 3 (Local Antigravity 2.x Fallback): If local checkpoint RPCs failed (`not_found`)
        // or returned empty on a session with live un-checkpointed turns or SQLite-backed state,
        // fall back to `StreamAgentStateUpdates` before surfacing an error.
        if !isRemoteCloud && (adaptiveError != nil || knownStepCount > 0) {
            do {
                if let streamedSteps = try await fetchStepsViaAgentStateStream(
                    cascadeId: cascadeId,
                    isRemoteCloud: false,
                    targetUuid: targetUuid,
                    timeoutSeconds: 3.5
                ), !streamedSteps.isEmpty {
                    wokenInstanceCascadeKeys.insert(wakeKey)
                    return streamedSteps
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Preserve original adaptiveError below.
            }
        }

        if let adaptiveError {
            throw adaptiveError
        }
        return adaptiveSteps
    }

    /// Reads the initial trajectory snapshot from Antigravity 2.x's authoritative
    /// `StreamAgentStateUpdates` server-streaming Connect-RPC (`mainTrajectoryUpdate.stepsUpdate`),
    /// merging sparse `indices` + `steps` up to `totalLength` and immediately closing the stream.
    /// Returns `nil` when this host does not implement `StreamAgentStateUpdates` (negative-cached).
    internal func fetchStepsViaAgentStateStream(
        cascadeId: String,
        isRemoteCloud: Bool,
        targetUuid: String?,
        timeoutSeconds: TimeInterval = 5.0
    ) async throws -> [CascadeStep]? {
        let profile = capabilityProfile(forHostKey: capabilityHostKey(for: targetUuid))
        if profile.isMethodKnownUnsupported("StreamAgentStateUpdates") {
            return nil
        }

        let strippedFields = profile.strippedFieldsByMethod["StreamAgentStateUpdates"] ?? []
        var payloadVariants: [[String: JSONValue]] = [
            [
                "conversationId": .string(cascadeId),
                "subscriberId": .string("pocket-\(UUID().uuidString.lowercased())")
            ]
        ]
        if isRemoteCloud && !strippedFields.contains("backend") {
            payloadVariants.append([
                "conversationId": .string(cascadeId),
                "subscriberId": .string("pocket-\(UUID().uuidString.lowercased())"),
                "backend": .string("BACKEND_TYPE_REMOTE_AICODE")
            ])
        }

        var lastError: Error? = nil
        for variant in payloadVariants {
            do {
                let result = try await readAgentStateSnapshotOnce(
                    cascadeId: cascadeId,
                    requestPayload: variant,
                    isRemoteCloud: isRemoteCloud,
                    targetUuid: targetUuid,
                    timeoutSeconds: timeoutSeconds
                )
                if !result.steps.isEmpty || (result.sawMainTrajectory && result.reportedTotalLength == 0) {
                    mutateCapabilityProfile(for: targetUuid) { p in
                        p.recordMethodSupported("StreamAgentStateUpdates")
                    }
                    return result.steps
                }
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if ProtocolCompatibilityEngine.isMethodUnimplementedError(error) {
                    mutateCapabilityProfile(for: targetUuid) { p in
                        p.recordMethodUnsupported("StreamAgentStateUpdates")
                    }
                    return nil
                }
                if case let AntigravityRPCError.httpError(_, body) = error,
                   let unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body) {
                    mutateCapabilityProfile(for: targetUuid) { p in
                        p.recordStrippedField(unknownField, forMethod: "StreamAgentStateUpdates")
                    }
                }
                lastError = error
                let shouldTryNext: Bool = {
                    if case let AntigravityRPCError.httpError(code, body) = error {
                        return code == 400
                            || ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body) != nil
                            || ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(statusCode: code, body: body)
                    }
                    return false
                }()
                if !shouldTryNext {
                    break
                }
            }
        }
        if let lastError {
            throw lastError
        }
        return []
    }

    private func readAgentStateSnapshotOnce(
        cascadeId: String,
        requestPayload: [String: JSONValue],
        isRemoteCloud: Bool,
        targetUuid: String?,
        timeoutSeconds: TimeInterval
    ) async throws -> (steps: [CascadeStep], sawMainTrajectory: Bool, reportedTotalLength: Int?) {
        let stream = try subscribeEnvelopeStream(
            method: "StreamAgentStateUpdates",
            requestPayload: requestPayload,
            instanceUuidOverride: targetUuid,
            allowCrossHostFailover: isRemoteCloud
        )

        final class SnapshotState: @unchecked Sendable {
            private let lock = NSLock()
            var stepsByIndex: [Int: CascadeStep] = [:]
            var reportedTotalLength: Int? = nil
            var sawMainTrajectory: Bool = false

            func apply(_ update: AgentStateStepsUpdate) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                if update.hasMainTrajectoryUpdate {
                    sawMainTrajectory = true
                }
                if let total = update.totalLength {
                    reportedTotalLength = total
                }
                for step in update.steps {
                    stepsByIndex[step.stepIndex] = step
                }
                if let total = reportedTotalLength, total >= 0 {
                    stepsByIndex = stepsByIndex.filter { $0.key < total }
                }
                if !stepsByIndex.isEmpty {
                    if let total = reportedTotalLength {
                        return stepsByIndex.count >= total
                    }
                    return true
                }
                return sawMainTrajectory && reportedTotalLength == 0
            }

            func snapshot() -> (steps: [CascadeStep], sawMainTrajectory: Bool, reportedTotalLength: Int?) {
                lock.lock()
                defer { lock.unlock() }
                let sorted = stepsByIndex.values.sorted { $0.stepIndex < $1.stepIndex }
                return (sorted, sawMainTrajectory, reportedTotalLength)
            }
        }

        let state = SnapshotState()
        let readerTask = Task<Void, Error> {
            for try await frameObj in stream {
                if Task.isCancelled { break }
                let decoded = Self.decodeAgentStateStepsUpdate(frameObj, cascadeId: cascadeId)
                if state.apply(decoded) {
                    break
                }
            }
        }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0.5, timeoutSeconds) * 1_000_000_000))
            readerTask.cancel()
        }

        defer {
            timeoutTask.cancel()
            readerTask.cancel()
        }

        do {
            try await readerTask.value
        } catch is CancellationError {
            // Bounded snapshot timeout elapsed cleanly; return whatever frames were collected.
        }
        return state.snapshot()
    }

    /// Fetches trajectory steps over JSON with dynamic truncation detection (`truncatedAt`, payload-limit errors,
    /// and pagination stalls) and per-host ceiling learning (`HostCapabilityProfile.learnedJsonStepCeiling`),
    /// negotiating Cloud backend fields (`backend` / `backendType` / bare `{cascadeId}`) and upgrading seamlessly
    /// to Binary Protobuf whenever a server-side JSON cap is encountered.
    internal func fetchStepsViaAdaptiveJSON(
        cascadeId: String,
        knownStepCount: Int,
        isRemoteCloud: Bool,
        targetUuid: String?,
        wakeKey: String,
        initialError: Error? = nil
    ) async throws -> [CascadeStep] {
        var lastError = initialError
        let canUpgradeToProtobuf = !isBinaryProtobufStepsUnsupported(for: targetUuid)

        // Learned fast-path: if this host already revealed a JSON ceiling at or below `knownStepCount`,
        // skip the doomed JSON probe and jump straight to Binary Protobuf.
        if canUpgradeToProtobuf,
           let learnedCeiling = learnedJsonStepCeiling(for: targetUuid),
           knownStepCount >= learnedCeiling {
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
                if Self.isBinaryProtobufUnsupportedError(error) {
                    recordBinaryProtobufStepsUnsupported(for: targetUuid)
                } else {
                    lastError = error
                }
            }
        }

        let cloudCandidates: [CloudTrajectoryBackendField] = isRemoteCloud
            ? orderedCloudBackendFields(for: "GetCascadeTrajectorySteps", targetUuid: targetUuid)
            : []
        var activeCloudField: CloudTrajectoryBackendField? = cloudCandidates.first
        let stepReqBody = Self.buildTrajectoryRequestBody(cascadeId: cascadeId, cloudField: activeCloudField)

        var firstResp: [String: JSONValue]? = nil
        do {
            firstResp = try await callUnaryJSON(
                method: "GetCascadeTrajectorySteps",
                body: stepReqBody,
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: isRemoteCloud,
                timeoutInterval: 10.0,
                allowStripUnknownFields: !isRemoteCloud
            )
            lastError = nil
        } catch let AntigravityRPCError.unauthorized(msg) {
            throw AntigravityRPCError.unauthorized(msg)
        } catch {
            lastError = error
            firstResp = nil
            if isRemoteCloud, case let AntigravityRPCError.httpError(_, body) = error,
               let unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body) {
                mutateCapabilityProfile(for: targetUuid) { profile in
                    profile.recordStrippedField(unknownField, forMethod: "GetCascadeTrajectorySteps")
                }
            }
            if Self.isJsonPayloadLimitError(error) && !isBinaryProtobufStepsUnsupported(for: targetUuid) {
                if let protoSteps = try? await fetchTrajectoryStepsProtobuf(
                    cascadeId: cascadeId,
                    startIndex: 0,
                    endIndex: knownStepCount,
                    instanceUuidOverride: targetUuid,
                    allowCrossHostFailover: isRemoteCloud
                ), !protoSteps.isEmpty {
                    let observed = knownStepCount > 0 ? min(knownStepCount, protoSteps.count) : protoSteps.count
                    recordLearnedJsonStepCeiling(observed, for: targetUuid)
                    wokenInstanceCascadeKeys.insert(wakeKey)
                    return protoSteps
                }
            }
        }

        if let resp = firstResp,
           let ceiling = Self.extractJsonTruncationCeiling(
               from: resp,
               fallbackStepCount: resp["steps"]?.arrayValue?.count ?? knownStepCount
           ) {
            recordLearnedJsonStepCeiling(ceiling, for: targetUuid)
            if !isBinaryProtobufStepsUnsupported(for: targetUuid) {
                let protoSteps = try await fetchTrajectoryStepsProtobuf(
                    cascadeId: cascadeId,
                    startIndex: 0,
                    endIndex: max(knownStepCount, ceiling),
                    instanceUuidOverride: targetUuid,
                    allowCrossHostFailover: isRemoteCloud
                )
                if !protoSteps.isEmpty {
                    wokenInstanceCascadeKeys.insert(wakeKey)
                    return protoSteps
                }
            }
        }

        var rawSteps = firstResp?["steps"]?.arrayValue ?? []
        let alreadyWoken = wokenInstanceCascadeKeys.contains(wakeKey)
        if !rawSteps.isEmpty {
            wokenInstanceCascadeKeys.insert(wakeKey)
            if let activeCloudField {
                recordPreferredCloudBackendField(activeCloudField, for: "GetCascadeTrajectorySteps", targetUuid: targetUuid)
            }
        } else if firstResp == nil || knownStepCount > 0 || !alreadyWoken {
            do {
                try await loadTrajectory(cascadeId: cascadeId, isCloud: isRemoteCloud, instanceUuidOverride: targetUuid)
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                // Best-effort wake; still retry GetCascadeTrajectorySteps and fallbacks below.
            }
            let retryVariants: [CloudTrajectoryBackendField?] = isRemoteCloud
                ? orderedCloudBackendFields(for: "GetCascadeTrajectorySteps", targetUuid: targetUuid).map { Optional($0) }
                : [nil]
            for variant in retryVariants {
                let candidateBody = Self.buildTrajectoryRequestBody(cascadeId: cascadeId, cloudField: variant)
                do {
                    let retryResp = try await callUnaryJSON(
                        method: "GetCascadeTrajectorySteps",
                        body: candidateBody,
                        instanceUuidOverride: targetUuid,
                        allowCrossHostFailover: isRemoteCloud,
                        timeoutInterval: 10.0,
                        allowStripUnknownFields: !isRemoteCloud
                    )
                    lastError = nil
                    if let ceiling = Self.extractJsonTruncationCeiling(
                        from: retryResp,
                        fallbackStepCount: retryResp["steps"]?.arrayValue?.count ?? knownStepCount
                    ) {
                        recordLearnedJsonStepCeiling(ceiling, for: targetUuid)
                        if !isBinaryProtobufStepsUnsupported(for: targetUuid) {
                            let protoSteps = try await fetchTrajectoryStepsProtobuf(
                                cascadeId: cascadeId,
                                startIndex: 0,
                                endIndex: max(knownStepCount, ceiling),
                                instanceUuidOverride: targetUuid,
                                allowCrossHostFailover: isRemoteCloud
                            )
                            if !protoSteps.isEmpty {
                                wokenInstanceCascadeKeys.insert(wakeKey)
                                return protoSteps
                            }
                        }
                    }
                    let candidateSteps = retryResp["steps"]?.arrayValue ?? []
                    if !candidateSteps.isEmpty {
                        rawSteps = candidateSteps
                        activeCloudField = variant
                        wokenInstanceCascadeKeys.insert(wakeKey)
                        if let variant {
                            recordPreferredCloudBackendField(variant, for: "GetCascadeTrajectorySteps", targetUuid: targetUuid)
                        }
                        break
                    } else if !isRemoteCloud {
                        break
                    }
                } catch let AntigravityRPCError.unauthorized(msg) {
                    throw AntigravityRPCError.unauthorized(msg)
                } catch {
                    lastError = error
                    if isRemoteCloud, case let AntigravityRPCError.httpError(_, body) = error,
                       let unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body) {
                        mutateCapabilityProfile(for: targetUuid) { profile in
                            profile.recordStrippedField(unknownField, forMethod: "GetCascadeTrajectorySteps")
                        }
                    }
                    if Self.isJsonPayloadLimitError(error) && !isBinaryProtobufStepsUnsupported(for: targetUuid) {
                        if let protoSteps = try? await fetchTrajectoryStepsProtobuf(
                            cascadeId: cascadeId,
                            startIndex: 0,
                            endIndex: knownStepCount,
                            instanceUuidOverride: targetUuid,
                            allowCrossHostFailover: isRemoteCloud
                        ), !protoSteps.isEmpty {
                            let observed = knownStepCount > 0 ? min(knownStepCount, protoSteps.count) : protoSteps.count
                            recordLearnedJsonStepCeiling(observed, for: targetUuid)
                            wokenInstanceCascadeKeys.insert(wakeKey)
                            return protoSteps
                        }
                    }
                    if !isRemoteCloud { break }
                    let retryNext: Bool = {
                        if case let AntigravityRPCError.httpError(code, body) = error {
                            return code == 400
                                || ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body) != nil
                                || ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(statusCode: code, body: body)
                        }
                        return false
                    }()
                    if !retryNext { break }
                }
            }
        }

        // Fallback A: Query `GetCascadeTrajectory` (`{"trajectory": {"steps": [...]}}`) when `GetCascadeTrajectorySteps`
        // returns empty or `not_found`.
        if rawSteps.isEmpty && (firstResp == nil || lastError != nil || knownStepCount > 0 || !alreadyWoken) {
            let trajVariants: [CloudTrajectoryBackendField?] = isRemoteCloud
                ? orderedCloudBackendFields(for: "GetCascadeTrajectory", targetUuid: targetUuid).map { Optional($0) }
                : [nil]
            for variant in trajVariants {
                let trajBody = Self.buildTrajectoryRequestBody(cascadeId: cascadeId, cloudField: variant)
                do {
                    let trajResp = try await callUnaryJSON(
                        method: "GetCascadeTrajectory",
                        body: trajBody,
                        instanceUuidOverride: targetUuid,
                        allowCrossHostFailover: isRemoteCloud,
                        timeoutInterval: 10.0,
                        allowStripUnknownFields: !isRemoteCloud
                    )
                    let fallbackArr = trajResp["trajectory"]?.objectValue?["steps"]?.arrayValue
                        ?? trajResp["steps"]?.arrayValue
                        ?? []
                    if !fallbackArr.isEmpty {
                        rawSteps = fallbackArr
                        lastError = nil
                        activeCloudField = variant
                        wokenInstanceCascadeKeys.insert(wakeKey)
                        if let variant {
                            recordPreferredCloudBackendField(variant, for: "GetCascadeTrajectory", targetUuid: targetUuid)
                        }
                        break
                    } else if !isRemoteCloud {
                        break
                    }
                } catch let AntigravityRPCError.unauthorized(msg) {
                    throw AntigravityRPCError.unauthorized(msg)
                } catch {
                    if isRemoteCloud, case let AntigravityRPCError.httpError(_, body) = error,
                       let unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body) {
                        mutateCapabilityProfile(for: targetUuid) { profile in
                            profile.recordStrippedField(unknownField, forMethod: "GetCascadeTrajectory")
                        }
                    }
                    if lastError == nil { lastError = error }
                    if !isRemoteCloud { break }
                    let retryNext: Bool = {
                        if case let AntigravityRPCError.httpError(code, body) = error {
                            return code == 400
                                || ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body) != nil
                                || ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(statusCode: code, body: body)
                        }
                        return false
                    }()
                    if !retryNext { break }
                }
            }
        }

        // Fallback B: Try Binary Protobuf if JSON came back empty/failed on a non-empty session
        if rawSteps.isEmpty && (firstResp == nil || lastError != nil || knownStepCount > 0) && !isBinaryProtobufStepsUnsupported(for: targetUuid) {
            if let protoFallback = try? await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: knownStepCount,
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: isRemoteCloud
            ), !protoFallback.isEmpty {
                let observed = knownStepCount > 0 ? min(knownStepCount, protoFallback.count) : protoFallback.count
                recordLearnedJsonStepCeiling(observed, for: targetUuid)
                wokenInstanceCascadeKeys.insert(wakeKey)
                return protoFallback
            }
        }

        if rawSteps.isEmpty, let lastError {
            throw lastError
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

        // If `knownStepCount` was omitted (0) on a host whose JSON ceiling was already learned and we hit that ceiling,
        // probe Binary Protobuf to check whether more steps exist beyond the cap.
        if knownStepCount == 0,
           !isBinaryProtobufStepsUnsupported(for: targetUuid),
           let learnedCeiling = learnedJsonStepCeiling(for: targetUuid),
           collected.count >= learnedCeiling {
            if let protoSteps = try? await fetchTrajectoryStepsProtobuf(
                cascadeId: cascadeId,
                startIndex: 0,
                endIndex: collected.count,
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: isRemoteCloud
            ), protoSteps.count > collected.count {
                wokenInstanceCascadeKeys.insert(wakeKey)
                return protoSteps
            }
        }

        // Dynamic JSON pagination with automatic stall detection (no hardcoded step ceiling)
        var offset = collected.count
        var pagesFetched = 0
        let maxPaginationRounds = 32
        while offset > 0 && knownStepCount > 0 && collected.count < knownStepCount && pagesFetched < maxPaginationRounds {
            pagesFetched += 1
            let pageBody = Self.buildTrajectoryRequestBody(
                cascadeId: cascadeId,
                cloudField: activeCloudField,
                stepOffset: offset
            )
            let pageResp: [String: JSONValue]
            do {
                pageResp = try await callUnaryJSON(
                    method: "GetCascadeTrajectorySteps",
                    body: pageBody,
                    instanceUuidOverride: targetUuid,
                    allowCrossHostFailover: isRemoteCloud
                )
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                if Self.isJsonPayloadLimitError(error) {
                    recordLearnedJsonStepCeiling(max(1, collected.count), for: targetUuid)
                }
                if !isBinaryProtobufStepsUnsupported(for: targetUuid),
                   let protoSteps = try? await fetchTrajectoryStepsProtobuf(
                       cascadeId: cascadeId,
                       startIndex: 0,
                       endIndex: knownStepCount,
                       instanceUuidOverride: targetUuid,
                       allowCrossHostFailover: isRemoteCloud
                   ), protoSteps.count > collected.count {
                    recordLearnedJsonStepCeiling(max(1, collected.count), for: targetUuid)
                    return protoSteps
                }
                break
            }

            if let ceiling = Self.extractJsonTruncationCeiling(from: pageResp, fallbackStepCount: collected.count) {
                recordLearnedJsonStepCeiling(max(collected.count, ceiling), for: targetUuid)
                if !isBinaryProtobufStepsUnsupported(for: targetUuid),
                   let protoSteps = try? await fetchTrajectoryStepsProtobuf(
                       cascadeId: cascadeId,
                       startIndex: 0,
                       endIndex: max(knownStepCount, ceiling),
                       instanceUuidOverride: targetUuid,
                       allowCrossHostFailover: isRemoteCloud
                   ), protoSteps.count >= collected.count {
                    return protoSteps
                }
                break
            }

            let pageSteps = pageResp["steps"]?.arrayValue ?? []
            var addedNew = false
            for (idxOffset, item) in pageSteps.enumerated() {
                if let step = Self.decodeJSONStep(item, cascadeId: cascadeId, fallbackIndex: offset + idxOffset) {
                    if seenIndices.insert(step.stepIndex).inserted {
                        collected.append(step)
                        addedNew = true
                    }
                }
            }
            if pageSteps.isEmpty || !addedNew {
                // Pagination stall: server refused to advance past `collected.count` while `knownStepCount > collected.count`.
                // Learn this host's true JSON ceiling dynamically and upgrade to Binary Protobuf.
                recordLearnedJsonStepCeiling(max(1, collected.count), for: targetUuid)
                if !isBinaryProtobufStepsUnsupported(for: targetUuid),
                   let protoSteps = try? await fetchTrajectoryStepsProtobuf(
                       cascadeId: cascadeId,
                       startIndex: 0,
                       endIndex: knownStepCount,
                       instanceUuidOverride: targetUuid,
                       allowCrossHostFailover: isRemoteCloud
                   ), protoSteps.count > collected.count {
                    return protoSteps
                }
                break
            }
            offset = max(offset + pageSteps.count, collected.count)
        }

        return collected.sorted { $0.stepIndex < $1.stepIndex }
    }

    /// Fetches trajectory steps over JSON (`GetCascadeTrajectorySteps`) with dynamic truncation detection
    /// and automatic upgrade to Binary Protobuf when the server advertises or triggers a JSON ceiling.
    public func fetchTrajectoryStepsJSON(
        cascadeId: String,
        startIndex: Int = 0,
        endIndex: Int = 0,
        instanceUuidOverride: String? = nil
    ) async throws -> [CascadeStep] {
        let isRemoteCloud = Self.isRemoteCloudCascade(cascadeId: cascadeId, isCloud: false)
        let cloudField: CloudTrajectoryBackendField? = isRemoteCloud
            ? orderedCloudBackendFields(for: "GetCascadeTrajectorySteps", targetUuid: instanceUuidOverride).first
            : nil
        let body = Self.buildTrajectoryRequestBody(
            cascadeId: cascadeId,
            cloudField: cloudField,
            stepOffset: startIndex
        )
        let res: [String: JSONValue]
        do {
            res = try await callUnaryJSON(
                method: "GetCascadeTrajectorySteps",
                body: body,
                instanceUuidOverride: instanceUuidOverride,
                allowCrossHostFailover: isRemoteCloud
            )
        } catch {
            if Self.isJsonPayloadLimitError(error) && !isBinaryProtobufStepsUnsupported(for: instanceUuidOverride) {
                let protoSteps = try await fetchTrajectoryStepsProtobuf(
                    cascadeId: cascadeId,
                    startIndex: startIndex,
                    endIndex: endIndex,
                    instanceUuidOverride: instanceUuidOverride,
                    allowCrossHostFailover: isRemoteCloud
                )
                if !protoSteps.isEmpty {
                    let observed = endIndex > 0 ? min(endIndex, protoSteps.count) : protoSteps.count
                    recordLearnedJsonStepCeiling(observed, for: instanceUuidOverride)
                }
                return protoSteps
            }
            throw error
        }
        let rawSteps = res["steps"]?.arrayValue ?? []
        if let ceiling = Self.extractJsonTruncationCeiling(
            from: res,
            fallbackStepCount: max(rawSteps.count, endIndex)
        ) {
            recordLearnedJsonStepCeiling(ceiling, for: instanceUuidOverride)
            if !isBinaryProtobufStepsUnsupported(for: instanceUuidOverride) {
                return try await fetchTrajectoryStepsProtobuf(
                    cascadeId: cascadeId,
                    startIndex: startIndex,
                    endIndex: max(endIndex, ceiling),
                    instanceUuidOverride: instanceUuidOverride,
                    allowCrossHostFailover: isRemoteCloud
                )
            }
        }
        return rawSteps.enumerated().compactMap { offset, item in
            Self.decodeJSONStep(item, cascadeId: cascadeId, fallbackIndex: startIndex + offset)
        }
    }

    /// Fetches trajectory steps using compact Binary Protobuf (`application/proto`) and performs targeted
    /// JSON repair for any unknown wire interaction members or unrecognized future step types.
    public func fetchTrajectoryStepsProtobuf(
        cascadeId: String,
        startIndex: Int,
        endIndex: Int = 0,
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
            let decoded = ProtobufStepCodec.decodeStepsResponse(
                unwrapped,
                cascadeId: cascadeId,
                startingIndex: startIndex
            )
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
            let bodyText = String(data: data, encoding: .utf8) ?? "Binary step fetch failed"
            if status == 401 {
                throw AntigravityRPCError.unauthorized(bodyText)
            }
            throw AntigravityRPCError.httpError(statusCode: status, body: bodyText)
        }
        let unwrapped = Self.unwrapConnectFramedPayloadIfNeeded(data)
        let decoded = ProtobufStepCodec.decodeStepsResponse(
            unwrapped,
            cascadeId: cascadeId,
            startingIndex: startIndex
        )
        return await repairUnrecognizedWireInteractionsIfNeeded(
            decoded,
            cascadeId: cascadeId,
            instanceUuidOverride: instanceUuidOverride,
            allowCrossHostFailover: allowCrossHostFailover
        )
    }

    /// Forward-compatibility repair: if a Binary Protobuf trajectory contains either:
    /// 1. A `WAITING` step whose `RequestedInteraction` used a brand-new wire field number unknown to this build, OR
    /// 2. An unrecognized future `CortexStepType` (`.unspecified` with a non-nil `rawTypeName`),
    /// issues targeted JSON `GetCascadeTrajectorySteps(stepOffset:)` probes to recover exact JSON field names,
    /// `rawMemberKey`, and rich step content without forcing the whole trajectory onto JSON.
    internal func repairUnrecognizedWireInteractionsIfNeeded(
        _ steps: [CascadeStep],
        cascadeId: String,
        instanceUuidOverride: String? = nil,
        allowCrossHostFailover: Bool = false
    ) async -> [CascadeStep] {
        let targets = steps.indices.filter { idx in
            let step = steps[idx]
            let needsInteractionRepair = step.isWaitingForUser
                && step.requestedInteraction?.isUnrecognizedWireMember == true
            let needsStepTypeRepair = step.type == .unspecified && step.rawTypeName != nil
            let needsErrorRepair = step.type == .errorMessage
                && (step.errorMessage?.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return needsInteractionRepair || needsStepTypeRepair || needsErrorRepair
        }
        guard !targets.isEmpty else { return steps }

        var repaired = steps
        for idx in targets.prefix(4) {
            let current = repaired[idx]
            let stepIndex = current.stepIndex
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
            guard let matched = decodedSlice.first(where: { $0.stepIndex == stepIndex }) else {
                continue
            }
            if current.type == .unspecified && current.rawTypeName != nil {
                if matched.type != .unspecified
                    || matched.plannerResponse != nil
                    || matched.errorMessage != nil
                    || matched.requestedInteraction != nil
                    || (matched.fallbackSummary?.isEmpty == false)
                    || (matched.rawTypeName?.isEmpty == false && matched.rawTypeName != current.rawTypeName) {
                    repaired[idx] = matched
                    continue
                }
            }
            if current.type == .errorMessage,
               (current.errorMessage?.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
               !(matched.errorMessage?.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                repaired[idx] = matched
                continue
            }
            if let recoveredInteraction = matched.requestedInteraction,
               !recoveredInteraction.isUnrecognizedWireMember,
               (recoveredInteraction.rawMemberKey?.isEmpty == false || recoveredInteraction.kind != .approvalInteraction) {
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
        let isCloudRequest = isCloud || (cloudProjectId?.isEmpty == false)

        func buildStartPayload(cloudField: CloudTrajectoryBackendField?) -> [String: JSONValue] {
            var payload: [String: JSONValue] = [
                "metadata": .object([
                    "ideName": .string("antigravity-ios"),
                    "ideVersion": .string(Self.clientAppVersion)
                ]),
                "modelId": .string(protoModel)
            ]
            if channel != .cloudRelay {
                payload["cascadeId"] = .string(clientCid)
            }
            if let cloudProjectId, !cloudProjectId.isEmpty {
                if let key = cloudField?.jsonKey {
                    payload[key] = .string("BACKEND_TYPE_REMOTE_AICODE")
                }
                payload["projectEnvConfig"] = .object([
                    "projectId": .string(cloudProjectId),
                    "defaultProjectEnvironment": .object([:])
                ])
            } else if isCloud {
                if let key = cloudField?.jsonKey {
                    payload[key] = .string("BACKEND_TYPE_REMOTE_AICODE")
                }
            } else if !workspaceUri.isEmpty && !AntigravityCloudDetector.isGenericContainerURI(workspaceUri) {
                payload["workspaceUris"] = .array([.string(workspaceUri)])
            }
            if !initialPrompt.isEmpty {
                payload["initialUserInput"] = .string(initialPrompt)
            }
            return payload
        }

        let candidates: [CloudTrajectoryBackendField?] = isCloudRequest
            ? orderedCloudBackendFields(for: "StartCascade", targetUuid: instanceUuidOverride).map { Optional($0) }
            : [nil]

        var lastError: Error? = nil
        var res: [String: JSONValue]? = nil
        for variant in candidates {
            do {
                res = try await callUnaryJSON(
                    method: "StartCascade",
                    body: buildStartPayload(cloudField: variant),
                    instanceUuidOverride: instanceUuidOverride,
                    allowCrossHostFailover: isCloudRequest,
                    timeoutInterval: 45.0,
                    allowStripUnknownFields: !isCloudRequest || variant?.jsonKey == nil
                )
                if let variant {
                    recordPreferredCloudBackendField(variant, for: "StartCascade", targetUuid: instanceUuidOverride)
                }
                break
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch let AntigravityRPCError.httpError(statusCode, errBody) {
                lastError = AntigravityRPCError.httpError(statusCode: statusCode, body: errBody)
                if let unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: errBody) {
                    mutateCapabilityProfile(for: instanceUuidOverride) { profile in
                        profile.recordStrippedField(unknownField, forMethod: "StartCascade")
                    }
                    let isBackendKey = unknownField.caseInsensitiveCompare("backend") == .orderedSame
                        || unknownField.caseInsensitiveCompare("backendType") == .orderedSame
                    if isBackendKey, let variant, variant != .none {
                        continue
                    }
                    if !isBackendKey, isCloudRequest, let variant, variant != .none {
                        res = try await callUnaryJSON(
                            method: "StartCascade",
                            body: buildStartPayload(cloudField: variant),
                            instanceUuidOverride: instanceUuidOverride,
                            allowCrossHostFailover: true,
                            timeoutInterval: 45.0,
                            allowStripUnknownFields: true
                        )
                        recordPreferredCloudBackendField(variant, for: "StartCascade", targetUuid: instanceUuidOverride)
                        break
                    }
                }
                throw AntigravityRPCError.httpError(statusCode: statusCode, body: errBody)
            } catch {
                throw error
            }
        }

        guard let responseObj = res else {
            throw lastError ?? AntigravityRPCError.httpError(statusCode: 502, body: "StartCascade failed")
        }
        if let returnedId = Self.extractServerCascadeId(from: responseObj) {
            return returnedId
        }
        if channel == .cloudRelay {
            throw AntigravityRPCError.httpError(statusCode: 502, body: "StartCascade did not return a conversation ID")
        }
        return clientCid
    }

    private func sendUserCascadeMessageToSingleInstance(
        cascadeId: String,
        baseBody: [String: JSONValue],
        isRemoteCloud: Bool,
        targetUuid: String?,
        allowCrossHostFailover: Bool
    ) async throws {
        do {
            _ = try await callUnaryJSON(
                method: "SendUserCascadeMessage",
                body: baseBody,
                instanceUuidOverride: targetUuid,
                allowCrossHostFailover: allowCrossHostFailover,
                timeoutInterval: 300.0
            )
            return
        } catch let AntigravityRPCError.unauthorized(msg) {
            throw AntigravityRPCError.unauthorized(msg)
        } catch {
            if error is CancellationError || !ProtocolCompatibilityEngine.isTrajectoryNotFoundError(error) {
                throw error
            }
            // Wake dormant disk/remote trajectory into language_server memory before retrying.
            do {
                try await loadTrajectory(
                    cascadeId: cascadeId,
                    isCloud: isRemoteCloud,
                    instanceUuidOverride: targetUuid
                )
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                if error is CancellationError { throw error }
                // Best-effort wake; still retry SendUserCascadeMessage (and Cloud backend variants below).
            }

            var retryError: Error? = nil
            do {
                _ = try await callUnaryJSON(
                    method: "SendUserCascadeMessage",
                    body: baseBody,
                    instanceUuidOverride: targetUuid,
                    allowCrossHostFailover: allowCrossHostFailover,
                    timeoutInterval: 300.0
                )
                return
            } catch let AntigravityRPCError.unauthorized(msg) {
                throw AntigravityRPCError.unauthorized(msg)
            } catch {
                if error is CancellationError || !ProtocolCompatibilityEngine.isTrajectoryNotFoundError(error) {
                    throw error
                }
                retryError = error
            }

            if isRemoteCloud {
                let cloudVariants = orderedCloudBackendFields(for: "SendUserCascadeMessage", targetUuid: targetUuid)
                    .filter { $0.jsonKey != nil }
                for variant in cloudVariants {
                    guard let key = variant.jsonKey else { continue }
                    var taggedBody = baseBody
                    taggedBody[key] = .string("BACKEND_TYPE_REMOTE_AICODE")
                    do {
                        _ = try await callUnaryJSON(
                            method: "SendUserCascadeMessage",
                            body: taggedBody,
                            instanceUuidOverride: targetUuid,
                            allowCrossHostFailover: allowCrossHostFailover,
                            timeoutInterval: 300.0,
                            allowStripUnknownFields: false
                        )
                        recordPreferredCloudBackendField(variant, for: "SendUserCascadeMessage", targetUuid: targetUuid)
                        return
                    } catch let AntigravityRPCError.unauthorized(msg) {
                        throw AntigravityRPCError.unauthorized(msg)
                    } catch let AntigravityRPCError.httpError(statusCode, errBody) {
                        let unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: errBody)
                        if let unknownField {
                            mutateCapabilityProfile(for: targetUuid) { profile in
                                profile.recordStrippedField(unknownField, forMethod: "SendUserCascadeMessage")
                            }
                        }
                        if unknownField != nil
                            || statusCode == 400
                            || ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(statusCode: statusCode, body: errBody) {
                            continue
                        }
                        throw AntigravityRPCError.httpError(statusCode: statusCode, body: errBody)
                    } catch {
                        throw error
                    }
                }
            }
            throw retryError ?? error
        }
    }

    /// Builds the upstream `cascadeConfig.plannerConfig.toolConfig` dictionary for a resolved `AgentPermissionPreset`.
    /// Explicitly encodes local `Auto` (`CASCADE_COMMANDS_AUTO_EXECUTION_AUTO`) distinct from `Default`, `Request Review`, and `Turbo`.
    public static func buildToolConfig(for preset: AgentPermissionPreset) -> [String: JSONValue] {
        switch preset {
        case .requestReview:
            return [
                "runCommand": .object([
                    "autoCommandConfig": .object([
                        "autoExecutionPolicy": .string("CASCADE_COMMANDS_AUTO_EXECUTION_OFF")
                    ])
                ]),
                "notifyUser": .object([
                    "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_ALWAYS")
                ])
            ]
        case .auto:
            return [
                "runCommand": .object([
                    "autoCommandConfig": .object([
                        "autoExecutionPolicy": .string("CASCADE_COMMANDS_AUTO_EXECUTION_AUTO")
                    ])
                ]),
                "notifyUser": .object([
                    "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_AUTO")
                ])
            ]
        case .turbo:
            return [
                "runCommand": .object([
                    "autoCommandConfig": .object([
                        "autoExecutionPolicy": .string("CASCADE_COMMANDS_AUTO_EXECUTION_EAGER")
                    ])
                ]),
                "notifyUser": .object([
                    "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_TURBO")
                ])
            ]
        case .defaultPolicy, .inheritGlobal:
            return [
                "notifyUser": .object([
                    "artifactReviewMode": .string("ARTIFACT_REVIEW_MODE_AUTO")
                ])
            ]
        }
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
        var mediaItems: [JSONValue] = []
        for chip in attachments {
            if let b64 = chip.inlineBase64Data, !b64.isEmpty {
                let resolvedMime: String = {
                    if let explicit = chip.mimeType, !explicit.isEmpty { return explicit }
                    switch chip.kind {
                    case .imageScreenshot: return "image/jpeg"
                    case .pdfDocument: return "application/pdf"
                    case .audioRecording: return "audio/m4a"
                    case .videoClip: return "video/mp4"
                    default: return "application/octet-stream"
                    }
                }()
                var mediaObj: [String: JSONValue] = [
                    "mimeType": .string(resolvedMime),
                    "inlineData": .string(b64)
                ]
                if !chip.label.isEmpty {
                    mediaObj["description"] = .string(chip.label)
                }
                mediaItems.append(.object(mediaObj))
                continue
            }
            switch chip.kind {
            case .imageScreenshot, .audioRecording, .videoClip, .pdfDocument, .archiveZip, .genericFile:
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

        let isRemoteCloud = Self.isRemoteCloudCascade(cascadeId: cascadeId, isCloud: isCloud)
        let effectivePermission = (permissionPreset ?? .inheritGlobal).resolvedForRuntime(isRemote: isRemoteCloud)
        let toolConfig = Self.buildToolConfig(for: effectivePermission)

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

        var requestBody: [String: JSONValue] = [
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
        ]
        if !mediaItems.isEmpty {
            requestBody["media"] = .array(mediaItems)
        }

        if channel != .cloudRelay {
            try await sendUserCascadeMessageToSingleInstance(
                cascadeId: cascadeId,
                baseBody: requestBody,
                isRemoteCloud: isRemoteCloud,
                targetUuid: instanceUuidOverride,
                allowCrossHostFailover: false
            )
            return
        }

        let pinnedTarget = pinnedInstance(for: cascadeId)
        let primaryTarget = selectReachableRelayUuid(
            preferred: pinnedTarget ?? instanceUuidOverride,
            allowCrossHostFailover: isRemoteCloud
        )
        let initialTarget = (primaryTarget?.isEmpty == false) ? primaryTarget : instanceUuidOverride

        let primaryError: Error
        do {
            try await sendUserCascadeMessageToSingleInstance(
                cascadeId: cascadeId,
                baseBody: requestBody,
                isRemoteCloud: isRemoteCloud,
                targetUuid: initialTarget,
                allowCrossHostFailover: isRemoteCloud
            )
            return
        } catch let AntigravityRPCError.unauthorized(msg) {
            throw AntigravityRPCError.unauthorized(msg)
        } catch {
            if error is CancellationError || !ProtocolCompatibilityEngine.isTrajectoryNotFoundError(error) {
                throw error
            }
            primaryError = error
        }

        // Primary instance confirmed `not_found`. Probe reachable peer instances (all reachable
        // peers for Cloud; same-host-family peers for Local).
        let resolvedPrimary = initialTarget ?? resolvedInstanceUuid ?? ""
        var probedUuids: Set<String> = []
        if !resolvedPrimary.isEmpty {
            probedUuids.insert(resolvedPrimary)
        }
        for pass in 0..<2 {
            let instancesToSearch: [RelayInstanceInfo]
            if pass == 0 {
                instancesToSearch = cachedRelayInstances
            } else {
                guard let refreshed = try? await listRelayInstances(timeoutInterval: 4.0),
                      !refreshed.isEmpty else {
                    break
                }
                self.cachedRelayInstances = refreshed
                instancesToSearch = refreshed
            }
            guard !instancesToSearch.isEmpty else { continue }
            let seedUuid = resolvedPrimary.isEmpty ? (instanceUuidOverride ?? resolvedInstanceUuid) : resolvedPrimary
            let familySeed = instancesToSearch.first(where: { $0.uuid == seedUuid })?.name
                ?? (instanceUuidOverride == nil && !Self.isWildcardRelayIdentifier(targetInstanceIdentifier) ? targetInstanceIdentifier : "")
            let peers = instancesToSearch.filter { inst in
                guard inst.status.isReachable && !probedUuids.contains(inst.uuid) else { return false }
                if isRemoteCloud { return true }
                return !familySeed.isEmpty && inst.sameHostFamily(as: familySeed)
            }
            for peer in peers {
                probedUuids.insert(peer.uuid)
                do {
                    try await sendUserCascadeMessageToSingleInstance(
                        cascadeId: cascadeId,
                        baseBody: requestBody,
                        isRemoteCloud: isRemoteCloud,
                        targetUuid: peer.uuid,
                        allowCrossHostFailover: false
                    )
                    recordPinnedInstance(for: cascadeId, instanceUuid: peer.uuid)
                    if instanceUuidOverride == nil && !isRemoteCloud {
                        self.resolvedInstanceUuid = peer.uuid
                    }
                    return
                } catch let AntigravityRPCError.unauthorized(msg) {
                    throw AntigravityRPCError.unauthorized(msg)
                } catch {
                    if error is CancellationError || !ProtocolCompatibilityEngine.isTrajectoryNotFoundError(error) {
                        throw error
                    }
                }
            }
        }

        throw primaryError
    }

    public func handleCascadeUserInteraction(
        _ payload: CascadeUserInteractionPayload,
        instanceUuidOverride: String? = nil
    ) async throws {
        let effectiveInstanceUuid = (channel == .cloudRelay)
            ? (pinnedInstance(for: payload.cascadeId) ?? instanceUuidOverride)
            : instanceUuidOverride
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
                instanceUuidOverride: effectiveInstanceUuid
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
                instanceUuidOverride: effectiveInstanceUuid
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
        let effectiveInstanceUuid = (channel == .cloudRelay)
            ? (pinnedInstance(for: cascadeId) ?? instanceUuidOverride)
            : instanceUuidOverride
        _ = try await callUnaryJSON(
            method: "CancelCascadeInvocation",
            body: ["cascadeId": .string(cascadeId)],
            instanceUuidOverride: effectiveInstanceUuid
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
