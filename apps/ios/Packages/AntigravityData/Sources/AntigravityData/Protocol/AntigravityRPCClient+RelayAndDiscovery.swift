import Foundation

/// Cloud Relay instance discovery, handshake/probe, federated summaries, model catalog, and Cloud projects.
extension AntigravityRPCClient {
    // MARK: - Cloud Relay `ApiService/ListInstances` & Instance Resolution

    /// Queries `POST /$rpc/devtools_jetski_boq_api_proto.ApiService/ListInstances` for a given `X-Goog-AuthUser`.
    public func listRelayInstances(
        authUserOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> [RelayInstanceInfo] {
        let activeAuthUser = authUserOverride ?? authUser
        let urlString = "\(SAPISIDHashGenerator.normalizeOrigin(relayOriginURL.absoluteString))\(SAPISIDHashGenerator.apiServicePrefix)/ListInstances"
        guard let url = URL(string: urlString) else {
            throw AntigravityRPCError.invalidEndpoint
        }
        let listStart = Date()
        let primaryTimeout = timeoutInterval ?? 7.0
        func performRequest(apiKey: String?, attemptTimeout: TimeInterval = primaryTimeout) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = attemptTimeout
            #if os(iOS) || os(macOS)
            request.assumesHTTP3Capable = false
            #endif
            SAPISIDHashGenerator.applyApiServiceHeaders(
                to: &request,
                cookieHeader: sessionCookie ?? "",
                origin: relayOriginURL.absoluteString,
                authUser: activeAuthUser,
                apiKey: apiKey
            )
            request.httpBody = CloudRelayJSPBCodec.encodeListInstancesRequest()

            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AntigravityRPCError.invalidEndpoint
            }
            return (data, http)
        }

        var activeApiKey = await resolveRelayApiKey()
        var triedKeys = Set<String>([activeApiKey ?? ""])
        handshakeDiagBox.record("list(u=\(activeAuthUser)):req")
        var (data, http): (Data, HTTPURLResponse)
        do {
            (data, http) = try await performRequest(apiKey: activeApiKey)
        } catch {
            handshakeDiagBox.record("list(u=\(activeAuthUser)):err")
            throw error
        }
        handshakeDiagBox.record("list(u=\(activeAuthUser)):http\(http.statusCode)")

        if http.statusCode == 400 || http.statusCode == 403 {
            let unwrapped = CloudRelayJSPBCodec.unwrapGoogleRPCBody(data, responseHeaders: http.allHeaderFields)
            let text = String(data: unwrapped, encoding: .utf8)
                ?? String(data: data, encoding: .utf8)
                ?? ""
            let isExplicitKeyError = SAPISIDHashGenerator.isInvalidApiKeyError(statusCode: http.statusCode, responseBody: text)
            let shouldRotate = (activeApiKey?.isEmpty != false)
                || isExplicitKeyError
                || http.statusCode == 403
            if shouldRotate {
                let originStr = SAPISIDHashGenerator.normalizeOrigin(relayOriginURL.absoluteString)
                var candidates = await discoverRelayWebApiKeysFromOrigin(originStr: originStr, forceRefresh: false)
                let hasUntried = candidates.contains { !$0.isEmpty && !triedKeys.contains($0) }
                if !hasUntried && isExplicitKeyError && !didForceRefreshInvalidApiKey {
                    didForceRefreshInvalidApiKey = true
                    candidates = await discoverRelayWebApiKeysFromOrigin(originStr: originStr, forceRefresh: true)
                }
                var rotationAttempts = 0
                for candidateKey in candidates {
                    if rotationAttempts >= 2 { break }
                    if Date().timeIntervalSince(listStart) >= 11.0 { break }
                    guard !candidateKey.isEmpty, triedKeys.insert(candidateKey).inserted else { continue }
                    rotationAttempts += 1
                    handshakeDiagBox.record("list(u=\(activeAuthUser)):rot\(rotationAttempts)")
                    let retry = try await performRequest(apiKey: candidateKey, attemptTimeout: min(primaryTimeout, 3.5))
                    data = retry.0
                    http = retry.1
                    activeApiKey = candidateKey
                    handshakeDiagBox.record("list(u=\(activeAuthUser)):rot\(rotationAttempts)_http\(http.statusCode)")
                    if (200..<300).contains(http.statusCode) {
                        relayApiKey = candidateKey
                        handshakeDiagBox.setKeySource("rotated(len=\(candidateKey.count))")
                        if !SAPISIDHashGenerator.isLoopbackOrigin(originStr) {
                            await KeychainStore.shared.saveRelayWebApiKey(candidateKey, forOrigin: originStr)
                        }
                        break
                    }
                    if http.statusCode != 400 && http.statusCode != 403 {
                        break
                    }
                }
            }
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            let unwrapped = CloudRelayJSPBCodec.unwrapGoogleRPCBody(data, responseHeaders: http.allHeaderFields)
            let text = String(data: unwrapped, encoding: .utf8)
                ?? String(data: data, encoding: .utf8)
                ?? "Google session expired or unauthorized"
            let keyLen = activeApiKey?.isEmpty == false ? "len:\(activeApiKey!.count)" : "none"
            let ck = SAPISIDHashGenerator.summarizeCookieNames(sessionCookie ?? "")
            throw AntigravityRPCError.unauthorized("HTTP \(http.statusCode) [ListInstances u=\(activeAuthUser) key=\(keyLen) ck=\(ck)]: \(text)")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AntigravityRPCError.httpError(statusCode: http.statusCode, body: text)
        }
        let decodedInstances = try CloudRelayJSPBCodec.decodeListInstancesResponse(
            data,
            responseHeaders: http.allHeaderFields
        )
        for inst in decodedInstances {
            mutateCapabilityProfile(for: inst.uuid) { profile in
                if !inst.version.isEmpty {
                    profile.updateReportedVersion(inst.version)
                }
                profile.recordPassiveSignal(.streamChunking, state: inst.supportsChunking ? .supported : .unsupported)
            }
        }
        return decodedInstances
    }

    /// Returns the currently active reachable Cloud Relay instance, if resolved.
    public func currentActiveRelayInstance() -> RelayInstanceInfo? {
        if let resUuid = resolvedInstanceUuid,
           let matched = cachedRelayInstances.first(where: { $0.uuid == resUuid && $0.status.isReachable }) {
            return matched
        }
        if !Self.isWildcardRelayIdentifier(targetInstanceIdentifier),
           let matched = cachedRelayInstances.first(where: { $0.matches(identifier: targetInstanceIdentifier) && $0.status.isReachable }) {
            return matched
        }
        return nil
    }

    /// Looks up a cached Cloud Relay instance by UUID or hostname slug (including offline instances).
    public func relayInstance(matching identifier: String) -> RelayInstanceInfo? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return cachedRelayInstances.first(where: { $0.uuid == trimmed || $0.matches(identifier: trimmed) })
    }

    /// Rebinds this Cloud Relay client's preferred target device without discarding auth cookies or cached instances.
    public func setTargetRelayInstance(uuid: String, name: String) {
        let trimmedUuid = uuid.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUuid.isEmpty && !Self.isWildcardRelayIdentifier(trimmedUuid) {
            self.resolvedInstanceUuid = trimmedUuid
            self.targetInstanceIdentifier = trimmedUuid
        } else if !trimmedName.isEmpty {
            self.targetInstanceIdentifier = trimmedName
        }
    }

    internal static func isWildcardRelayIdentifier(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty
            || trimmed == "r"
            || trimmed == "auto"
            || trimmed == "unpaired"
            || trimmed == "macbook-pro-local"
    }

    internal static func isTransportOrTimeoutFailure(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }
        if case let AntigravityRPCError.httpError(code, _) = error {
            return code == 504 || code == -1
        }
        return !(error is AntigravityRPCError)
    }

    /// Returns the latest Cloud Relay instance list observed from `ApiService/ListInstances`.
    public func currentCachedRelayInstances() -> [RelayInstanceInfo] {
        cachedRelayInstances
    }

    /// Returns the latest cached `ListInstances` snapshot together with the active reachable instance.
    public func currentRelayInstancesSnapshot() -> (instances: [RelayInstanceInfo], active: RelayInstanceInfo?) {
        (cachedRelayInstances, currentActiveRelayInstance())
    }

    /// Resolves a scanned Remote Control device slug (`lt74xt6l0m-golden-star`) or UUID (`0f5819ac-...-v2`)
    /// to a `RelayInstanceInfo`. When `allowCrossHostFallback == false`, an offline explicit target returns
    /// its own offline `RelayInstanceInfo` instead of silently hijacking a different online Mac.
    public func resolveCloudRelayInstance(
        preferredIdentifier: String? = nil,
        allowCrossHostFallback: Bool = true,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> (selected: RelayInstanceInfo, allInstances: [RelayInstanceInfo], matchedAuthUser: String) {
        let rawTarget = (preferredIdentifier ?? targetInstanceIdentifier).trimmingCharacters(in: .whitespacesAndNewlines)
        let isWildcardTarget = Self.isWildcardRelayIdentifier(rawTarget)
        let fallbackFamilyName: String? = {
            let trimmed = initialHostName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.caseInsensitiveCompare("Antigravity Desktop") != .orderedSame,
                  trimmed.caseInsensitiveCompare("MacBook Pro") != .orderedSame,
                  !Self.isWildcardRelayIdentifier(trimmed),
                  trimmed.caseInsensitiveCompare(rawTarget) != .orderedSame else {
                return nil
            }
            return trimmed
        }()

        var candidateAuthUsers: [String] = []
        if let explicitAuthUser, !explicitAuthUser.isEmpty {
            candidateAuthUsers.append(explicitAuthUser)
        }
        for fallbackIdx in ["0", "1", "2", "3", "4"] where !candidateAuthUsers.contains(fallbackIdx) {
            candidateAuthUsers.append(fallbackIdx)
        }

        var firstNonEmptyResult: (instances: [RelayInstanceInfo], authUser: String)? = nil
        var bestReachableFallback: (selected: RelayInstanceInfo, instances: [RelayInstanceInfo], authUser: String)? = nil
        var bestOfflineMatch: (selected: RelayInstanceInfo, instances: [RelayInstanceInfo], authUser: String)? = nil
        var anySucceededCall = false
        var primaryError: Error? = nil
        var lastError: Error? = nil

        func evaluateCandidate(
            candidateUser: String,
            instances: [RelayInstanceInfo]
        ) -> (selected: RelayInstanceInfo, allInstances: [RelayInstanceInfo], matchedAuthUser: String)? {
            anySucceededCall = true
            if instances.isEmpty { return nil }
            if firstNonEmptyResult == nil {
                firstNonEmptyResult = (instances, candidateUser)
            }
            if !isWildcardTarget {
                if let exactOnline = instances.first(where: { $0.matches(identifier: rawTarget) && $0.status.isReachable }) {
                    self.authUser = candidateUser
                    self.resolvedInstanceUuid = exactOnline.uuid
                    self.cachedRelayInstances = instances
                    return (exactOnline, instances, candidateUser)
                }
                if let familyOnline = instances.first(where: { $0.sameHostFamily(as: rawTarget) && $0.status.isReachable }) {
                    self.authUser = candidateUser
                    self.resolvedInstanceUuid = familyOnline.uuid
                    self.cachedRelayInstances = instances
                    return (familyOnline, instances, candidateUser)
                }
                if let fallbackFamilyName,
                   let hostFamilyOnline = instances.first(where: { $0.sameHostFamily(as: fallbackFamilyName) && $0.status.isReachable }) {
                    self.authUser = candidateUser
                    self.resolvedInstanceUuid = hostFamilyOnline.uuid
                    self.cachedRelayInstances = instances
                    return (hostFamilyOnline, instances, candidateUser)
                }
                let exactTargetMatch = instances.first(where: { $0.matches(identifier: rawTarget) })
                let familyOfflineMatch = instances.first(where: { $0.sameHostFamily(as: rawTarget) })
                    ?? fallbackFamilyName.flatMap { fam in instances.first(where: { $0.sameHostFamily(as: fam) }) }
                if bestOfflineMatch == nil,
                   let offlineMatch = exactTargetMatch ?? familyOfflineMatch {
                    bestOfflineMatch = (offlineMatch, instances, candidateUser)
                }
                if bestReachableFallback == nil,
                   let anyOnline = instances.first(where: \.status.isReachable) {
                    bestReachableFallback = (anyOnline, instances, candidateUser)
                }
            } else if let online = instances.first(where: \.status.isReachable) {
                self.authUser = candidateUser
                self.resolvedInstanceUuid = online.uuid
                self.cachedRelayInstances = instances
                return (online, instances, candidateUser)
            }
            return nil
        }

        // 1. Probe primary authUser first (fastest single-RTT happy path + primes API key discovery once).
        let primaryUser = candidateAuthUsers[0]
        var stopFallbacks = false
        do {
            let primaryTimeout = min(timeoutInterval ?? 7.0, 7.0)
            let primaryInstances = try await listRelayInstances(
                authUserOverride: primaryUser,
                timeoutInterval: primaryTimeout
            )
            if let matched = evaluateCandidate(candidateUser: primaryUser, instances: primaryInstances) {
                handshakeDiagBox.record("resolve:ok(u=\(primaryUser),n=\(primaryInstances.count))")
                return matched
            }
            if !isWildcardTarget && primaryInstances.contains(where: { $0.matches(identifier: rawTarget) }) {
                stopFallbacks = true
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            primaryError = error
            lastError = error
            // Fail fast on network/timeout errors: probing authUser=1..4 cannot fix an unreachable relay/VPN.
            if Self.isTransportOrTimeoutFailure(error) {
                handshakeDiagBox.record("resolve:failFast(u=\(primaryUser))")
                stopFallbacks = true
            }
        }

        // 2. Probe remaining multi-login slots IN PARALLEL with a tight 4.5s timeout instead of 4 sequential retries.
        let fallbackUsers = stopFallbacks ? [] : Array(candidateAuthUsers.dropFirst())
        if !fallbackUsers.isEmpty {
            handshakeDiagBox.record("resolve:fallback(\(fallbackUsers.joined(separator: ",")))")
            let fallbackTimeout = min(timeoutInterval ?? 4.5, 4.5)
            var outcomesByIndex: [(Int, String, Result<[RelayInstanceInfo], Error>)] = []
            await withTaskGroup(of: (Int, String, Result<[RelayInstanceInfo], Error>).self) { group in
                for (idx, candidateUser) in fallbackUsers.enumerated() {
                    group.addTask {
                        do {
                            let list = try await self.listRelayInstances(
                                authUserOverride: candidateUser,
                                timeoutInterval: fallbackTimeout
                            )
                            return (idx, candidateUser, .success(list))
                        } catch {
                            return (idx, candidateUser, .failure(error))
                        }
                    }
                }
                for await outcome in group {
                    outcomesByIndex.append(outcome)
                }
            }
            for (_, candidateUser, result) in outcomesByIndex.sorted(by: { $0.0 < $1.0 }) {
                switch result {
                case .success(let instances):
                    if let matched = evaluateCandidate(candidateUser: candidateUser, instances: instances) {
                        handshakeDiagBox.record("resolve:ok(u=\(candidateUser),n=\(instances.count))")
                        return matched
                    }
                    if !isWildcardTarget && instances.contains(where: { $0.matches(identifier: rawTarget) }) {
                        break
                    }
                case .failure(let error):
                    if error is CancellationError {
                        throw error
                    }
                    if primaryError == nil { primaryError = error }
                    lastError = error
                }
            }
        }

        if !allowCrossHostFallback, let offline = bestOfflineMatch {
            self.authUser = offline.authUser
            self.resolvedInstanceUuid = offline.selected.uuid
            self.cachedRelayInstances = offline.instances
            handshakeDiagBox.record("resolve:offlineMatch(u=\(offline.authUser))")
            return (offline.selected, offline.instances, offline.authUser)
        }

        if allowCrossHostFallback, let reachable = bestReachableFallback {
            self.authUser = reachable.authUser
            self.resolvedInstanceUuid = reachable.selected.uuid
            self.cachedRelayInstances = reachable.instances
            handshakeDiagBox.record("resolve:crossHost(u=\(reachable.authUser))")
            return (reachable.selected, reachable.instances, reachable.authUser)
        }

        if let offline = bestOfflineMatch {
            self.authUser = offline.authUser
            self.resolvedInstanceUuid = offline.selected.uuid
            self.cachedRelayInstances = offline.instances
            handshakeDiagBox.record("resolve:offline(u=\(offline.authUser))")
            return (offline.selected, offline.instances, offline.authUser)
        }

        if !allowCrossHostFallback && !isWildcardTarget, let existing = firstNonEmptyResult {
            let syntheticOffline = RelayInstanceInfo(
                uuid: rawTarget,
                name: fallbackFamilyName ?? rawTarget,
                version: "",
                status: .disconnected
            )
            self.authUser = existing.authUser
            self.resolvedInstanceUuid = rawTarget
            self.cachedRelayInstances = existing.instances
            handshakeDiagBox.record("resolve:targetOffline")
            return (syntheticOffline, existing.instances, existing.authUser)
        }

        if let fallback = firstNonEmptyResult,
           let chosen = fallback.instances.first(where: \.status.isReachable) ?? fallback.instances.first {
            self.authUser = fallback.authUser
            self.resolvedInstanceUuid = chosen.uuid
            self.cachedRelayInstances = fallback.instances
            handshakeDiagBox.record("resolve:firstNonEmpty(u=\(fallback.authUser))")
            return (chosen, fallback.instances, fallback.authUser)
        }

        // Only allow direct-UUID fallback when ListInstances genuinely succeeded (HTTP 200) with empty results,
        // AND prove liveness via a short ProxyCommand probe so an unregistered/offline host is never fabricated as `.connected`.
        if anySucceededCall && lastError == nil && firstNonEmptyResult == nil && !isWildcardTarget && (rawTarget.hasSuffix("-v2") || rawTarget.count >= 32) {
            let isAlive = await probeRelayInstanceLiveness(instanceUuid: rawTarget, timeoutInterval: 4.0)
            let directInfo = RelayInstanceInfo(
                uuid: rawTarget,
                name: fallbackFamilyName ?? rawTarget,
                version: "",
                status: isAlive ? .connected : .disconnected
            )
            self.resolvedInstanceUuid = rawTarget
            self.cachedRelayInstances = [directInfo]
            handshakeDiagBox.record(isAlive ? "resolve:directUuid:live" : "resolve:directUuid:offline")
            return (directInfo, [directInfo], authUser)
        }

        if anySucceededCall && primaryError == nil && lastError == nil {
            handshakeDiagBox.record("resolve:empty200")
            throw AntigravityRPCError.httpError(
                statusCode: 404,
                body: "Signed in to Google, but no online Antigravity Desktop instances were found on this account. Enable Remote Control in Antigravity Desktop and verify both devices use the same Google account."
            )
        }

        handshakeDiagBox.record("resolve:failed")
        if let err = primaryError ?? lastError {
            throw err
        }
        throw AntigravityRPCError.unauthorized(
            "No online Antigravity Desktop instances found for this Google account. Ensure Remote Control is enabled on your Mac/PC."
        )
    }

    internal func isRelayInstanceRecentlyVerified(_ uuid: String, now: Date = Date()) -> Bool {
        guard let verifiedAt = lastEndToEndVerifiedAtByUuid[uuid] else { return false }
        let elapsed = now.timeIntervalSince(verifiedAt)
        return elapsed >= 0 && elapsed < Self.endToEndFreshnessWindowSeconds
    }

    internal func probeRelayInstanceLiveness(
        instanceUuid: String,
        timeoutInterval: TimeInterval = 4.0
    ) async -> Bool {
        do {
            _ = try await callCloudRelayProxyCommand(
                method: "GetWorkspaceInfos",
                payload: Data("{}".utf8),
                contentType: "application/json",
                instanceUuidOverride: instanceUuid,
                allowCrossHostFailover: false,
                timeoutInterval: timeoutInterval,
                ignoreCachedOfflineStatus: true
            )
            lastEndToEndVerifiedAtByUuid[instanceUuid] = Date()
            return true
        } catch let AntigravityRPCError.httpError(code, body) {
            let alive = code == 404 && !ProtocolCompatibilityEngine.isInstanceNotRegisteredResponse(statusCode: code, body: body)
            if alive {
                lastEndToEndVerifiedAtByUuid[instanceUuid] = Date()
            } else {
                lastEndToEndVerifiedAtByUuid.removeValue(forKey: instanceUuid)
            }
            return alive
        } catch {
            lastEndToEndVerifiedAtByUuid.removeValue(forKey: instanceUuid)
            return false
        }
    }

    /// Non-fatal read-only probe against native upstream `GetUserStatus` on direct LAN hosts
    /// when neither `ListInstances` nor Companion Bridge headers supplied a version string.
    internal func probeDirectServerVersionIfNeeded(timeoutInterval: TimeInterval = 2.0) async {
        guard channel == .directHost else { return }
        if capabilityProfile().reportedVersion != nil {
            return
        }
        if let resp = try? await callUnaryJSON(
            method: "GetUserStatus",
            body: [:],
            timeoutInterval: timeoutInterval,
            respectNegativeCache: false
        ), let detected = ProtocolCompatibilityEngine.extractVersionFromHeadersOrBody(headers: [:], body: resp) {
            mutateCapabilityProfile(for: nil) { profile in
                profile.updateReportedVersion(detected)
            }
        }
    }

    /// Parses signed-in user identity (display name, email, plan tier) from an upstream `GetUserStatus` JSON payload.
    public static func parseUserProfileResponse(_ obj: [String: JSONValue]) -> LiveUserProfile? {
        let statusObj = obj["userStatus"]?.objectValue ?? obj["user_status"]?.objectValue
        var containers: [[String: JSONValue]] = []
        if let statusObj {
            containers.append(statusObj)
            if let u = statusObj["user"]?.objectValue { containers.append(u) }
            if let p = statusObj["profile"]?.objectValue { containers.append(p) }
            if let a = statusObj["account"]?.objectValue { containers.append(a) }
        }
        if let u = obj["user"]?.objectValue { containers.append(u) }
        if let p = obj["profile"]?.objectValue { containers.append(p) }
        if let a = obj["account"]?.objectValue { containers.append(a) }
        containers.append(obj)

        let givenNameKeys = ["givenName", "given_name", "firstName", "first_name"]
        let fullNameKeys = [
            "name",
            "displayName",
            "display_name",
            "fullName",
            "full_name",
            "userName",
            "user_name",
            "accountName",
            "account_name"
        ]
        let emailKeys = ["email", "userEmail", "user_email", "accountEmail", "account_email"]

        func firstString(_ keys: [String]) -> String? {
            for container in containers {
                for key in keys {
                    if let raw = container[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !raw.isEmpty {
                        return raw
                    }
                }
            }
            return nil
        }

        let rawName = firstString(givenNameKeys) ?? firstString(fullNameKeys)
        let rawEmail = firstString(emailKeys)
        let tierObj = statusObj?["userTier"]?.objectValue
            ?? statusObj?["user_tier"]?.objectValue
            ?? obj["userTier"]?.objectValue
        let planInfoObj = statusObj?["planStatus"]?.objectValue?["planInfo"]?.objectValue
            ?? statusObj?["plan_status"]?.objectValue?["plan_info"]?.objectValue
            ?? obj["planStatus"]?.objectValue?["planInfo"]?.objectValue
        let planDisplayName = Self.nonEmptyString(tierObj?["name"]?.stringValue)
            ?? Self.nonEmptyString(planInfoObj?["planName"]?.stringValue)
            ?? Self.nonEmptyString(planInfoObj?["plan_name"]?.stringValue)

        let displayName = UserGreetingFormatter.formatGreetingName(rawName, fallbackEmail: rawEmail)
        if displayName == nil && rawEmail == nil && planDisplayName == nil {
            return nil
        }
        return LiveUserProfile(
            displayName: displayName,
            email: rawEmail,
            planDisplayName: planDisplayName
        )
    }

    /// Queries upstream `GetUserStatus` (over Direct LAN or Cloud Relay `ProxyCommand`) for the
    /// real signed-in user's profile without blocking or failing the connection handshake.
    public func fetchUserProfile(
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval = 5.0
    ) async -> LiveUserProfile? {
        let metaReq: [String: JSONValue] = [
            "metadata": .object([
                "ideName": .string("antigravity"),
                "extensionName": .string("antigravity"),
                "locale": .string("en")
            ])
        ]
        guard let resp = try? await callUnaryJSON(
            method: "GetUserStatus",
            body: metaReq,
            instanceUuidOverride: instanceUuidOverride,
            timeoutInterval: timeoutInterval,
            respectNegativeCache: false
        ) else {
            return nil
        }
        return Self.parseUserProfileResponse(resp)
    }

    // MARK: - Handshake & Login Verification

    /// Verifies authentication (`SAPISIDHASH` + `ApiService/ListInstances` + `ProxyCommand`, or `x-codeium-csrf-token`)
    /// and hydrates initial local + Antigravity Cloud workspaces & trajectories across reachable instances.
    public func verifyConnection(
        timeoutInterval: TimeInterval = 4.0,
        allowCrossHostFallback: Bool = true
    ) async throws -> BackendHandshakeResult {
        handshakeDiagBox.reset()
        handshakeDiagBox.record("verify:start")
        let start = Date()
        let effectiveTimeout = (channel == .cloudRelay) ? max(timeoutInterval, 7.0) : timeoutInterval
        var resolvedName: String? = nil
        var selectedUuid: String? = resolvedInstanceUuid
        var isSelectedHostOnline = true
        var serverVersion = ""
        var allRelayInstances: [RelayInstanceInfo] = []

        if channel == .cloudRelay {
            let preferred = (resolvedInstanceUuid?.isEmpty == false) ? resolvedInstanceUuid : targetInstanceIdentifier
            let resolution = try await resolveCloudRelayInstance(
                preferredIdentifier: preferred,
                allowCrossHostFallback: allowCrossHostFallback,
                timeoutInterval: effectiveTimeout
            )
            resolvedName = resolution.selected.name
            selectedUuid = resolution.selected.uuid
            isSelectedHostOnline = resolution.selected.status.isReachable
            serverVersion = resolution.selected.version
            allRelayInstances = resolution.allInstances
            self.resolvedInstanceUuid = resolution.selected.uuid
        }

        var initialSyncCompleted = false
        let federated: (
            workspaces: [WorkspaceInfo],
            summaries: [CascadeSummary],
            cloudProjects: [ProjectWorkspace],
            cloudWarmingUp: Bool,
            availableRelayInstances: [RelayInstanceInfo],
            succeededInstanceUuids: Set<String>,
            cloudSucceeded: Bool
        )
        if channel == .cloudRelay {
            let resolveElapsed = max(0.0, Date().timeIntervalSince(start))
            let initialSyncBudget = min(6.5, max(2.5, 17.0 - resolveElapsed))
            let capturedInstances = allRelayInstances
            let targetUuidForSync = (!allowCrossHostFallback && isSelectedHostOnline) ? selectedUuid : nil
            let includeLocalForSync = isSelectedHostOnline || allowCrossHostFallback
            handshakeDiagBox.record("sync:start(\(Int(initialSyncBudget * 1000))ms)")
            enum SoftSyncOutcome: Sendable {
                case completed((
                    workspaces: [WorkspaceInfo],
                    summaries: [CascadeSummary],
                    cloudProjects: [ProjectWorkspace],
                    cloudWarmingUp: Bool,
                    availableRelayInstances: [RelayInstanceInfo],
                    succeededInstanceUuids: Set<String>,
                    cloudSucceeded: Bool
                ))
                case unregistered
                case deferred
            }
            let softOutcome = try await withThrowingTaskGroup(of: SoftSyncOutcome.self) { group in
                group.addTask {
                    do {
                        let res = try await self.fetchFederatedWorkspacesAndSummaries(
                            timeoutInterval: initialSyncBudget,
                            skipRelayListRefresh: !capturedInstances.isEmpty,
                            targetInstanceUuid: targetUuidForSync,
                            includeLocal: includeLocalForSync,
                            includeCloud: true,
                            includeJetboxSnapshot: false
                        )
                        return .completed(res)
                    } catch let err as AntigravityRPCError {
                        if case .unauthorized = err { throw err }
                        if ProtocolCompatibilityEngine.isInstanceNotRegisteredError(err) {
                            return .unregistered
                        }
                        return .deferred
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return .deferred
                    }
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(initialSyncBudget * 1_000_000_000))
                    return .deferred
                }
                let first = try await group.next() ?? .deferred
                group.cancelAll()
                return first
            }
            switch softOutcome {
            case .completed(let softResult):
                initialSyncCompleted = !softResult.succeededInstanceUuids.isEmpty || softResult.cloudSucceeded
                handshakeDiagBox.record("sync:ok(sum=\(softResult.summaries.count),ws=\(softResult.workspaces.count))")
                if let currentSelected = selectedUuid,
                   !softResult.succeededInstanceUuids.contains(currentSelected),
                   softResult.availableRelayInstances.contains(where: { $0.uuid == currentSelected && !$0.status.isReachable }) {
                    isSelectedHostOnline = false
                }
                federated = softResult
            case .unregistered:
                if let currentSelected = selectedUuid {
                    self.cachedRelayInstances = self.cachedRelayInstances.map { inst in
                        inst.uuid == currentSelected ? inst.withStatus(.disconnected) : inst
                    }
                    allRelayInstances = allRelayInstances.map { inst in
                        inst.uuid == currentSelected ? inst.withStatus(.disconnected) : inst
                    }
                    isSelectedHostOnline = false
                }
                handshakeDiagBox.record("sync:unregistered")
                federated = ([], [], [], false, cachedRelayInstances.isEmpty ? allRelayInstances : cachedRelayInstances, [], false)
            case .deferred:
                handshakeDiagBox.record("sync:deferred")
                federated = ([], [], [], false, allRelayInstances, [], false)
            }
        } else {
            initialSyncCompleted = true
            federated = try await fetchFederatedWorkspacesAndSummaries(
                timeoutInterval: effectiveTimeout,
                skipRelayListRefresh: false,
                targetInstanceUuid: nil,
                includeLocal: true,
                includeCloud: true,
                includeJetboxSnapshot: false
            )
        }
        if let selectedUuid, channel == .cloudRelay {
            self.resolvedInstanceUuid = selectedUuid
        }
        if channel == .directHost {
            await probeDirectServerVersionIfNeeded(timeoutInterval: min(timeoutInterval, 2.0))
        }
        let latestInstances = federated.availableRelayInstances.isEmpty
            ? (cachedRelayInstances.isEmpty ? allRelayInstances : cachedRelayInstances)
            : federated.availableRelayInstances
        let latestActive = currentActiveRelayInstance()
        let effectiveUuid = latestActive?.uuid.isEmpty == false ? latestActive?.uuid : (selectedUuid ?? resolvedInstanceUuid)
        if channel == .cloudRelay,
           let effectiveUuid,
           let matchedInLatest = latestInstances.first(where: { $0.uuid == effectiveUuid }),
           !matchedInLatest.status.isReachable {
            isSelectedHostOnline = false
        }
        let activeProfile = capabilityProfile(forHostKey: effectiveUuid)
        let resolvedVersion: String = {
            if let v = latestActive?.version, !v.isEmpty { return v }
            if !serverVersion.isEmpty { return serverVersion }
            return activeProfile.reportedVersion ?? ""
        }()
        let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
        handshakeDiagBox.record("verify:done")
        return BackendHandshakeResult(
            latencyMs: elapsedMs,
            workspaces: federated.workspaces,
            summaries: federated.summaries,
            cloudProjects: federated.cloudProjects,
            serverVersion: resolvedVersion,
            resolvedHostname: latestActive?.name ?? resolvedName,
            resolvedInstanceUuid: effectiveUuid,
            resolvedAuthUser: channel == .cloudRelay ? authUser : nil,
            resolvedRelayApiKey: channel == .cloudRelay ? relayApiKey : nil,
            availableRelayInstances: latestInstances,
            isSelectedHostOnline: isSelectedHostOnline,
            hostCapabilities: activeProfile,
            succeededInstanceUuids: Array(federated.succeededInstanceUuids).sorted(),
            initialSyncCompleted: initialSyncCompleted
        )
    }

    /// Single-request lightweight reachability probe used by foreground idle heartbeats
    /// and exponential-backoff offline recovery so mobile radios avoid multi-RPC fan-out.
    /// - Cloud Relay (`verifyEndToEnd == false`): sends only `ApiService/ListInstances` (a few hundred bytes, zero `ProxyCommand` fan-out),
    ///   automatically escalating to a single short-timeout liveness probe if a previously disconnected/zombie instance reappears as CONNECTED.
    /// - Cloud Relay (`verifyEndToEnd == true`, e.g. Settings refresh / offline recovery): verifies each `status.isReachable` Relay instance
    ///   end-to-end with a short-timeout `GetWorkspaceInfos` `ProxyCommand` (`allowCrossHostFailover: false`) so stale/zombie
    ///   Relay entries are truthfully downgraded to `.disconnected`.
    /// - Direct LAN: sends a single short-timeout `GetWorkspaceInfos` probe (HTTP 404 still proves server + auth liveness).
    public func probeHostReachability(
        timeoutInterval: TimeInterval? = nil,
        allowCrossHostFallback: Bool = false,
        verifyEndToEnd: Bool = false
    ) async throws -> HostReachabilityProbeResult {
        let start = Date()
        if channel == .cloudRelay {
            let effectiveTimeout = timeoutInterval ?? 8.0
            let prevReachableIds = Set(cachedRelayInstances.filter(\.status.isReachable).map(\.uuid))
            let prevDisconnectedIds = Set(cachedRelayInstances.filter { !$0.status.isReachable }.map(\.uuid))
            let prevNamesByUuid = Dictionary(
                cachedRelayInstances.map { ($0.uuid, $0.name) },
                uniquingKeysWith: { _, latest in latest }
            )
            let prevActiveUuid = resolvedInstanceUuid

            var instances = try await listRelayInstances(timeoutInterval: effectiveTimeout)
            let reachableNowIds = Set(instances.filter(\.status.isReachable).map(\.uuid))
            for key in Array(lastEndToEndVerifiedAtByUuid.keys) where !reachableNowIds.contains(key) {
                lastEndToEndVerifiedAtByUuid.removeValue(forKey: key)
            }
            let instancesToVerify: [RelayInstanceInfo] = {
                guard !instances.isEmpty else { return [] }
                let candidateReachable = instances.filter(\.status.isReachable)
                if verifyEndToEnd {
                    return candidateReachable
                }
                return candidateReachable.filter { inst in
                    prevDisconnectedIds.contains(inst.uuid) || !isRelayInstanceRecentlyVerified(inst.uuid, now: start)
                }
            }()
            if !instancesToVerify.isEmpty {
                let perHostTimeout = min(effectiveTimeout, 4.5)
                var failedUuids = Set<String>()
                await withTaskGroup(of: (String, Bool).self) { group in
                    for inst in instancesToVerify {
                        group.addTask {
                            let alive = await self.probeRelayInstanceLiveness(
                                instanceUuid: inst.uuid,
                                timeoutInterval: perHostTimeout
                            )
                            return (inst.uuid, alive)
                        }
                    }
                    for await (uuid, ok) in group where !ok {
                        failedUuids.insert(uuid)
                    }
                }
                if !failedUuids.isEmpty {
                    instances = instances.map { inst in
                        failedUuids.contains(inst.uuid) ? inst.withStatus(.disconnected) : inst
                    }
                }
            }

            if !instances.isEmpty {
                self.cachedRelayInstances = instances
            }

            let reachable = instances.filter(\.status.isReachable)
            if reachable.isEmpty {
                if instances.isEmpty, let directUuid = resolvedInstanceUuid, !directUuid.isEmpty {
                    let isAlive = await probeRelayInstanceLiveness(
                        instanceUuid: directUuid,
                        timeoutInterval: min(effectiveTimeout, 4.5)
                    )
                    if isAlive {
                        let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
                        return HostReachabilityProbeResult(
                            latencyMs: elapsedMs,
                            availableRelayInstances: cachedRelayInstances,
                            activeRelayInstance: currentActiveRelayInstance(),
                            relayTopologyChanged: false,
                            relayMetadataChanged: false,
                            isSelectedHostOnline: true
                        )
                    }
                    self.cachedRelayInstances = self.cachedRelayInstances.map { inst in
                        inst.uuid == directUuid ? inst.withStatus(.disconnected) : inst
                    }
                }
                throw AntigravityRPCError.httpError(
                    statusCode: 503,
                    body: "No reachable Antigravity Desktop instances online"
                )
            }

            let newNamesByUuid = Dictionary(
                instances.map { ($0.uuid, $0.name) },
                uniquingKeysWith: { _, latest in latest }
            )
            let metadataChanged = (newNamesByUuid != prevNamesByUuid)

            let isWildcardTarget = Self.isWildcardRelayIdentifier(targetInstanceIdentifier)
            let prevActiveName = instances.first(where: { $0.uuid == prevActiveUuid })?.name
            let familySeed = prevActiveName ?? (isWildcardTarget ? "" : targetInstanceIdentifier)

            let onlineTargetMatch: RelayInstanceInfo? = {
                if let prevActiveUuid,
                   let stillOnline = reachable.first(where: { $0.uuid == prevActiveUuid }) {
                    return stillOnline
                }
                if !isWildcardTarget,
                   let exact = reachable.first(where: { $0.matches(identifier: targetInstanceIdentifier) }) {
                    return exact
                }
                if !familySeed.isEmpty,
                   let sameFamily = reachable.first(where: { $0.sameHostFamily(as: familySeed) }) {
                    return sameFamily
                }
                return nil
            }()

            if let chosen = onlineTargetMatch {
                self.resolvedInstanceUuid = chosen.uuid
                let newReachableIds = Set(reachable.map(\.uuid))
                let topologyChanged = (newReachableIds != prevReachableIds) || (chosen.uuid != prevActiveUuid)
                let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
                return HostReachabilityProbeResult(
                    latencyMs: elapsedMs,
                    availableRelayInstances: instances,
                    activeRelayInstance: chosen,
                    relayTopologyChanged: topologyChanged,
                    relayMetadataChanged: metadataChanged,
                    isSelectedHostOnline: true
                )
            }

            if allowCrossHostFallback || isWildcardTarget {
                let chosen = reachable[0]
                self.resolvedInstanceUuid = chosen.uuid
                let newReachableIds = Set(reachable.map(\.uuid))
                let topologyChanged = (newReachableIds != prevReachableIds) || (chosen.uuid != prevActiveUuid)
                let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
                return HostReachabilityProbeResult(
                    latencyMs: elapsedMs,
                    availableRelayInstances: instances,
                    activeRelayInstance: chosen,
                    relayTopologyChanged: topologyChanged,
                    relayMetadataChanged: metadataChanged,
                    isSelectedHostOnline: true
                )
            }

            // Explicit local device is offline while another Mac is online: report offline WITHOUT hijacking activeHost.
            let offlineTarget = instances.first(where: { $0.uuid == prevActiveUuid })
                ?? instances.first(where: { $0.matches(identifier: targetInstanceIdentifier) })
                ?? (!familySeed.isEmpty ? instances.first(where: { $0.sameHostFamily(as: familySeed) }) : nil)
            let newReachableIds = Set(reachable.map(\.uuid))
            let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
            return HostReachabilityProbeResult(
                latencyMs: elapsedMs,
                availableRelayInstances: instances,
                activeRelayInstance: offlineTarget,
                relayTopologyChanged: newReachableIds != prevReachableIds,
                relayMetadataChanged: metadataChanged,
                isSelectedHostOnline: false
            )
        }

        let effectiveTimeout = timeoutInterval ?? 3.0
        _ = try await getWorkspaceInfosOptional(timeoutInterval: effectiveTimeout)
        let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
        return HostReachabilityProbeResult(latencyMs: elapsedMs, isSelectedHostOnline: true)
    }

    /// Returns all currently reachable Cloud Relay Desktop instances (falling back to the resolved instance).
    public func currentReachableRelayInstances() -> [RelayInstanceInfo] {
        guard channel == .cloudRelay else { return [] }
        let reachable = cachedRelayInstances.filter(\.status.isReachable)
        if !reachable.isEmpty {
            return reachable
        }
        if let uuid = resolvedInstanceUuid, !uuid.isEmpty, cachedRelayInstances.isEmpty {
            return [RelayInstanceInfo(uuid: uuid, name: targetInstanceIdentifier.isEmpty ? "Mac" : targetInstanceIdentifier, status: .connected)]
        }
        return []
    }

    /// Returns the reachable Cloud Relay instance that most recently served Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) RPCs.
    public func currentPreferredCloudInstanceUuid() -> String? {
        if let pref = preferredCloudInstanceUuid, !pref.isEmpty {
            if cachedRelayInstances.isEmpty
                || cachedRelayInstances.contains(where: { $0.uuid == pref && $0.status.isReachable }) {
                return pref
            }
        }
        return selectReachableRelayUuid(preferred: resolvedInstanceUuid, allowCrossHostFailover: true)
    }

    /// Refreshes `ListInstances` (when on `.cloudRelay`), queries either a specific targeted local host
    /// (`targetInstanceUuid`) or all reachable hosts (`targetInstanceUuid == nil`) in deterministic priority order,
    /// and optionally queries Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) projects & conversations.
    public func fetchFederatedWorkspacesAndSummaries(
        timeoutInterval: TimeInterval? = nil,
        lightweightPoll: Bool = false,
        skipRelayListRefresh: Bool = false,
        targetInstanceUuid: String? = nil,
        includeLocal: Bool = true,
        includeCloud: Bool = true,
        includeJetboxSnapshot: Bool = true
    ) async throws -> (
        workspaces: [WorkspaceInfo],
        summaries: [CascadeSummary],
        cloudProjects: [ProjectWorkspace],
        cloudWarmingUp: Bool,
        availableRelayInstances: [RelayInstanceInfo],
        succeededInstanceUuids: Set<String>,
        cloudSucceeded: Bool
    ) {
        if channel == .cloudRelay && !skipRelayListRefresh {
            if let refreshed = try? await listRelayInstances(timeoutInterval: timeoutInterval), !refreshed.isEmpty {
                self.cachedRelayInstances = refreshed
                if let currentUuid = resolvedInstanceUuid,
                   !refreshed.contains(where: { $0.uuid == currentUuid && $0.status.isReachable }) {
                    let familySeed = refreshed.first(where: { $0.uuid == currentUuid })?.name ?? targetInstanceIdentifier
                    if !Self.isWildcardRelayIdentifier(familySeed),
                       let sameFamilyOnline = refreshed.first(where: { $0.status.isReachable && $0.sameHostFamily(as: familySeed) }) {
                        self.resolvedInstanceUuid = sameFamilyOnline.uuid
                    } else if Self.isWildcardRelayIdentifier(targetInstanceIdentifier),
                              let fallback = refreshed.first(where: { $0.status.isReachable }) {
                        self.resolvedInstanceUuid = fallback.uuid
                    }
                }
            }
        }

        let preferredUuid = (targetInstanceUuid?.isEmpty == false) ? targetInstanceUuid : resolvedInstanceUuid

        let reachableInstances: [RelayInstanceInfo] = {
            guard channel == .cloudRelay else { return [] }
            let raw = currentReachableRelayInstances()
            return raw.sorted { lhs, rhs in
                if let preferredUuid {
                    if lhs.uuid == preferredUuid && rhs.uuid != preferredUuid { return true }
                    if rhs.uuid == preferredUuid && lhs.uuid != preferredUuid { return false }
                }
                return lhs.uuid < rhs.uuid
            }
        }()

        let localInstancesToQuery: [RelayInstanceInfo] = {
            guard channel == .cloudRelay, includeLocal else { return [] }
            if let targetUuid = targetInstanceUuid, !targetUuid.isEmpty {
                if let exact = reachableInstances.first(where: { $0.uuid == targetUuid }) {
                    return [exact]
                }
                let familySeed = cachedRelayInstances.first(where: { $0.uuid == targetUuid })?.name ?? targetInstanceIdentifier
                if !Self.isWildcardRelayIdentifier(familySeed),
                   let sameFamily = reachableInstances.first(where: { $0.sameHostFamily(as: familySeed) }) {
                    return [sameFamily]
                }
                return []
            }
            return reachableInstances
        }()

        // 1. Kick off Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) projects fetch concurrently
        //    so Cloud project listing never blocks local Mac workspace/trajectory queries.
        let cachedCloudValues = Array(cachedCloudProjectsById.values)
        let shouldQueryCloudProjects = includeCloud && !(lightweightPoll && !cachedCloudValues.isEmpty)
        async let cloudProjectsTask: (projects: [ProjectWorkspace], warmingUp: Bool) = shouldQueryCloudProjects
            ? self.fetchCloudProjects(
                candidateInstances: reachableInstances,
                timeoutInterval: timeoutInterval
            )
            : (cachedCloudValues, false)

        var mergedWorkspacesByKey: [String: WorkspaceInfo] = [:]
        var mergedSummariesById: [String: CascadeSummary] = [:]
        var succeededInstanceUuids = Set<String>()
        var cloudSucceeded = false
        let cloudProjectOutcome: (projects: [ProjectWorkspace], warmingUp: Bool)

        if channel == .cloudRelay {
            var anyInstanceSucceeded = false

            // Order Cloud candidate instances with the instance that served Cloud projects first
            let preferredCloudUuid = self.preferredCloudInstanceUuid
            let orderedCloudCandidates: [RelayInstanceInfo] = {
                guard let preferredCloudUuid,
                      let prefInst = reachableInstances.first(where: { $0.uuid == preferredCloudUuid }) else {
                    return reachableInstances
                }
                return [prefInst] + reachableInstances.filter { $0.uuid != preferredCloudUuid }
            }()

            // Run Cloud (`BACKEND_TYPE_REMOTE_AICODE`) summary fetch concurrently when requested
            let shouldFetchCloud = includeCloud && !orderedCloudCandidates.isEmpty
            async let cloudOutcomeTask: (summaries: [CascadeSummary], succeeded: Bool) = shouldFetchCloud
                ? self.fetchCloudSummariesAcrossInstances(
                    candidates: orderedCloudCandidates,
                    timeoutInterval: timeoutInterval,
                    includeJetboxSnapshot: includeJetboxSnapshot
                )
                : ([], false)

            var resultsByUuid: [String: (ok: Bool, ws: [WorkspaceInfo], mem: [CascadeSummary], jb: [CascadeSummary])] = [:]
            if !localInstancesToQuery.isEmpty {
                await withTaskGroup(of: (String, Bool, [WorkspaceInfo], [CascadeSummary], [CascadeSummary]).self) { group in
                    for inst in localInstancesToQuery {
                        group.addTask {
                            async let wsOutcomeTask = self.fetchWorkspaceInfosOutcome(
                                instanceUuidOverride: inst.uuid,
                                originHostName: inst.name,
                                timeoutInterval: timeoutInterval
                            )
                            async let memTask = self.getAllCascadeTrajectories(
                                instanceUuidOverride: inst.uuid,
                                originHostName: inst.name,
                                timeoutInterval: timeoutInterval
                            )
                            async let jbLocalTask: [CascadeSummary] = includeJetboxSnapshot
                                ? self.fetchJetboxSummariesSnapshot(
                                    cloud: false,
                                    instanceUuidOverride: inst.uuid,
                                    originHostName: inst.name,
                                    snapshotTimeout: 2.0
                                )
                                : []

                            let wsOutcome = await wsOutcomeTask
                            let memResult = try? await memTask
                            let jbLocal = await jbLocalTask
                            let instOk = wsOutcome.ok || memResult != nil || !jbLocal.isEmpty
                            return (inst.uuid, instOk, wsOutcome.ws, memResult ?? [], jbLocal)
                        }
                    }

                    for await (instUuid, instOk, wsList, memList, jbLocalList) in group {
                        resultsByUuid[instUuid] = (instOk, wsList, memList, jbLocalList)
                    }
                }
            }

            cloudProjectOutcome = await cloudProjectsTask
            let cloudProjects = cloudProjectOutcome.projects
            if includeCloud {
                for cp in cloudProjects {
                    let wsKey = "cloud|\(cp.workspaceUri)"
                    mergedWorkspacesByKey[wsKey] = WorkspaceInfo(
                        workspaceUri: cp.workspaceUri,
                        displayName: cp.name,
                        activeBranch: cp.activeBranch,
                        isCloud: true,
                        originInstanceUuid: cp.originInstanceUuid,
                        originHostName: "Antigravity"
                    )
                }
            }

            let cloudOutcome = await cloudOutcomeTask
            let updatedCloudProjects = self.cachedCloudProjectsById

            if !localInstancesToQuery.isEmpty {
                // Merge in deterministic priority order (`preferredUuid` first) so shared-disk windows on the same Mac
                // never randomly steal `originInstanceUuid` from the active host.
                var failedLocalUuids = Set<String>()
                for inst in localInstancesToQuery {
                    guard let entry = resultsByUuid[inst.uuid] else { continue }
                    if entry.ok {
                        anyInstanceSucceeded = true
                        succeededInstanceUuids.insert(inst.uuid)
                    } else {
                        failedLocalUuids.insert(inst.uuid)
                    }
                    for ws in entry.ws {
                        let wsKey = "\(ws.isCloud ? "cloud" : (ws.originInstanceUuid ?? inst.uuid))|\(ws.workspaceUri)"
                        if mergedWorkspacesByKey[wsKey] == nil {
                            mergedWorkspacesByKey[wsKey] = ws
                        }
                    }
                    for s in entry.mem + entry.jb {
                        Self.mergeSummaryEntry(
                            s,
                            into: &mergedSummariesById,
                            cloudProjectsById: updatedCloudProjects,
                            preferredInstanceUuid: preferredUuid
                        )
                    }
                }
                if !failedLocalUuids.isEmpty {
                    for uuid in failedLocalUuids {
                        self.lastEndToEndVerifiedAtByUuid.removeValue(forKey: uuid)
                    }
                    if !self.cachedRelayInstances.isEmpty {
                        self.cachedRelayInstances = self.cachedRelayInstances.map { inst in
                            failedLocalUuids.contains(inst.uuid) ? inst.withStatus(.disconnected) : inst
                        }
                    }
                }
            }

            if includeCloud && (cloudOutcome.succeeded || !cloudOutcome.summaries.isEmpty || !cloudProjects.isEmpty) {
                cloudSucceeded = true
                if !cloudOutcome.summaries.isEmpty {
                    anyInstanceSucceeded = true
                    for s in cloudOutcome.summaries {
                        Self.mergeSummaryEntry(
                            s,
                            into: &mergedSummariesById,
                            cloudProjectsById: updatedCloudProjects,
                            preferredInstanceUuid: preferredUuid
                        )
                    }
                }
            }

            if targetInstanceUuid == nil && includeLocal && !anyInstanceSucceeded && cloudProjects.isEmpty && !reachableInstances.isEmpty {
                let ws = try await getWorkspaceInfosOptional(timeoutInterval: timeoutInterval)
                let sums = try await getAllCascadeTrajectories(timeoutInterval: timeoutInterval)
                if let fallbackUuid = resolvedInstanceUuid {
                    succeededInstanceUuids.insert(fallbackUuid)
                }
                for w in ws {
                    let wsKey = "\(w.isCloud ? "cloud" : (w.originInstanceUuid ?? "local"))|\(w.workspaceUri)"
                    mergedWorkspacesByKey[wsKey] = w
                }
                for s in sums {
                    Self.mergeSummaryEntry(
                        s,
                        into: &mergedSummariesById,
                        cloudProjectsById: updatedCloudProjects,
                        preferredInstanceUuid: preferredUuid
                    )
                }
            }
        } else {
            // Direct LAN / Companion / Mock server mode
            async let workspacesTask = getWorkspaceInfosOptional(timeoutInterval: timeoutInterval)
            async let summariesTask = getAllCascadeTrajectories(timeoutInterval: timeoutInterval)
            async let cloudSummariesTask: [CascadeSummary] = (includeCloud && includeJetboxSnapshot)
                ? self.fetchJetboxSummariesSnapshot(
                    cloud: true,
                    originHostName: "Antigravity",
                    snapshotTimeout: 1.5
                )
                : []
            let workspaces = try await workspacesTask
            let summaries = try await summariesTask
            cloudProjectOutcome = await cloudProjectsTask
            let cloudProjects = cloudProjectOutcome.projects
            if includeCloud {
                for cp in cloudProjects {
                    let wsKey = "cloud|\(cp.workspaceUri)"
                    mergedWorkspacesByKey[wsKey] = WorkspaceInfo(
                        workspaceUri: cp.workspaceUri,
                        displayName: cp.name,
                        activeBranch: cp.activeBranch,
                        isCloud: true,
                        originInstanceUuid: cp.originInstanceUuid,
                        originHostName: "Antigravity"
                    )
                }
            }
            let cloudSummaries = await cloudSummariesTask
            cloudSucceeded = includeCloud && (!cloudSummaries.isEmpty || !cloudProjects.isEmpty)
            let cloudProjectsSnapshot = self.cachedCloudProjectsById
            for w in workspaces {
                let wsKey = "\(w.isCloud ? "cloud" : "direct")|\(w.workspaceUri)"
                if mergedWorkspacesByKey[wsKey] == nil {
                    mergedWorkspacesByKey[wsKey] = w
                }
            }
            for s in summaries + cloudSummaries {
                Self.mergeSummaryEntry(
                    s,
                    into: &mergedSummariesById,
                    cloudProjectsById: cloudProjectsSnapshot,
                    preferredInstanceUuid: preferredUuid
                )
            }
        }
        let cloudProjects = cloudProjectOutcome.projects

        Self.reconcileBatchUnreadStates(&mergedSummariesById)

        let sortedSummaries = mergedSummariesById.values.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.cascadeId < rhs.cascadeId
        }
        let sortedWorkspaces = Array(mergedWorkspacesByKey.values).sorted { $0.displayName < $1.displayName }
        return (
            sortedWorkspaces,
            sortedSummaries,
            cloudProjects,
            cloudProjectOutcome.warmingUp,
            cachedRelayInstances,
            succeededInstanceUuids,
            cloudSucceeded
        )
    }

    private func fetchWorkspaceInfosOutcome(
        instanceUuidOverride: String?,
        originHostName: String?,
        timeoutInterval: TimeInterval?
    ) async -> (ok: Bool, ws: [WorkspaceInfo]) {
        do {
            let ws = try await getWorkspaceInfos(
                instanceUuidOverride: instanceUuidOverride,
                originHostName: originHostName,
                timeoutInterval: timeoutInterval
            )
            return (true, ws)
        } catch let AntigravityRPCError.httpError(code, body)
            where code == 404 && !ProtocolCompatibilityEngine.isInstanceNotRegisteredResponse(statusCode: code, body: body) {
            return (true, [])
        } catch {
            return (false, [])
        }
    }

    /// Refreshes workspaces & conversation summaries scoped to a single `AgentsHostFilterScope` target:
    /// - `.localHost(id, name)`: queries ONLY that specific Mac/PC (`allowCrossHostFailover: false`) and reconciles its live reachability.
    /// - `.antigravityCloud`: queries ONLY Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) projects & sessions.
    /// - `.allHosts`: runs full multi-host + Cloud federation and reports exactly which local hosts succeeded.
    public func fetchScopedWorkspacesAndSummaries(
        target: AgentsHostFilterScope,
        timeoutInterval: TimeInterval? = nil,
        lightweightPoll: Bool = false,
        skipRelayListRefresh: Bool = false
    ) async throws -> ScopedWorkspaceSyncResult {
        let start = Date()
        switch target {
        case .allHosts:
            let federated = try await fetchFederatedWorkspacesAndSummaries(
                timeoutInterval: timeoutInterval,
                lightweightPoll: lightweightPoll,
                skipRelayListRefresh: skipRelayListRefresh,
                targetInstanceUuid: nil,
                includeLocal: true,
                includeCloud: true
            )
            let refreshedNames = Set(
                federated.availableRelayInstances
                    .filter { federated.succeededInstanceUuids.contains($0.uuid) }
                    .map(\.name)
            )
            let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
            let anyTargetReachable = (channel != .cloudRelay)
                || !federated.succeededInstanceUuids.isEmpty
                || federated.cloudSucceeded
            return ScopedWorkspaceSyncResult(
                workspaces: federated.workspaces,
                summaries: federated.summaries,
                cloudProjects: federated.cloudProjects,
                cloudWarmingUp: federated.cloudWarmingUp,
                relayInstances: federated.availableRelayInstances,
                refreshedLocalHostUuids: federated.succeededInstanceUuids,
                refreshedLocalHostNames: refreshedNames,
                refreshedCloud: federated.cloudSucceeded,
                targetReachable: anyTargetReachable,
                latencyMs: elapsedMs
            )

        case .antigravityCloud:
            let federated = try await fetchFederatedWorkspacesAndSummaries(
                timeoutInterval: timeoutInterval,
                lightweightPoll: lightweightPoll,
                skipRelayListRefresh: skipRelayListRefresh,
                targetInstanceUuid: nil,
                includeLocal: false,
                includeCloud: true
            )
            let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
            return ScopedWorkspaceSyncResult(
                workspaces: federated.workspaces,
                summaries: federated.summaries,
                cloudProjects: federated.cloudProjects,
                cloudWarmingUp: federated.cloudWarmingUp,
                relayInstances: federated.availableRelayInstances,
                refreshedLocalHostUuids: [],
                refreshedLocalHostNames: [],
                refreshedCloud: federated.cloudSucceeded,
                targetReachable: federated.cloudSucceeded,
                latencyMs: elapsedMs
            )

        case .localHost(let requestedId, let requestedName):
            if channel == .cloudRelay {
                if !skipRelayListRefresh {
                    if let refreshed = try? await listRelayInstances(timeoutInterval: min(timeoutInterval ?? 8.0, 8.0)),
                       !refreshed.isEmpty {
                        self.cachedRelayInstances = refreshed
                    }
                }
                let matchedInst = cachedRelayInstances.first(where: { $0.uuid == requestedId })
                    ?? cachedRelayInstances.first(where: { $0.name == requestedName })
                let resolvedUuid = matchedInst?.uuid ?? requestedId
                let resolvedName = matchedInst?.name ?? requestedName
                let perHostTimeout = min(timeoutInterval ?? 8.0, 8.0)

                var instOk = false
                var authError: AntigravityRPCError? = nil
                let wsList: [WorkspaceInfo]
                do {
                    wsList = try await getWorkspaceInfos(
                        instanceUuidOverride: resolvedUuid,
                        originHostName: resolvedName,
                        timeoutInterval: perHostTimeout
                    )
                    instOk = true
                } catch let err as AntigravityRPCError {
                    if case .unauthorized = err {
                        authError = err
                    } else if case .httpError(let code, _) = err, code == 404 {
                        instOk = true
                    }
                    wsList = []
                } catch {
                    wsList = []
                }

                if let authError {
                    throw authError
                }

                async let memTask = self.fetchTrajectoriesResult(
                    instanceUuidOverride: resolvedUuid,
                    originHostName: resolvedName,
                    timeoutInterval: perHostTimeout
                )
                async let jbLocalTask = self.fetchJetboxSummariesSnapshot(
                    cloud: false,
                    instanceUuidOverride: resolvedUuid,
                    originHostName: resolvedName,
                    snapshotTimeout: min(perHostTimeout, 4.0)
                )

                let memOutcome = await memTask
                let jbLocal = await jbLocalTask
                let memList: [CascadeSummary]
                switch memOutcome {
                case .success(let list):
                    memList = list
                    instOk = true
                case .failure(let err):
                    if case AntigravityRPCError.unauthorized = err {
                        throw err
                    }
                    memList = []
                }
                if !jbLocal.isEmpty {
                    instOk = true
                }

                if !cachedRelayInstances.isEmpty {
                    self.cachedRelayInstances = self.cachedRelayInstances.map { inst in
                        guard inst.uuid == resolvedUuid else { return inst }
                        if instOk {
                            return inst.status.isReachable ? inst : inst.withStatus(.connected)
                        } else {
                            return inst.status.isReachable ? inst.withStatus(.disconnected) : inst
                        }
                    }
                }

                let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
                guard instOk else {
                    return ScopedWorkspaceSyncResult(
                        workspaces: [],
                        summaries: [],
                        cloudProjects: [],
                        cloudWarmingUp: false,
                        relayInstances: cachedRelayInstances,
                        refreshedLocalHostUuids: [],
                        refreshedLocalHostNames: [],
                        refreshedCloud: false,
                        targetReachable: false,
                        latencyMs: elapsedMs
                    )
                }

                var mergedWorkspacesByKey: [String: WorkspaceInfo] = [:]
                for ws in wsList where !ws.isCloud {
                    let key = "\(ws.originInstanceUuid ?? resolvedUuid)|\(ws.workspaceUri)"
                    if mergedWorkspacesByKey[key] == nil {
                        mergedWorkspacesByKey[key] = ws
                    }
                }
                var mergedSummariesById: [String: CascadeSummary] = [:]
                let cloudProjectsSnapshot = self.cachedCloudProjectsById
                for s in (memList + jbLocal) where !s.isCloud {
                    Self.mergeSummaryEntry(
                        s,
                        into: &mergedSummariesById,
                        cloudProjectsById: cloudProjectsSnapshot,
                        preferredInstanceUuid: resolvedUuid
                    )
                }
                Self.reconcileBatchUnreadStates(&mergedSummariesById)
                let sortedSummaries = mergedSummariesById.values.sorted { lhs, rhs in
                    if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                    return lhs.cascadeId < rhs.cascadeId
                }
                let sortedWorkspaces = Array(mergedWorkspacesByKey.values).sorted { $0.displayName < $1.displayName }
                return ScopedWorkspaceSyncResult(
                    workspaces: sortedWorkspaces,
                    summaries: sortedSummaries,
                    cloudProjects: [],
                    cloudWarmingUp: false,
                    relayInstances: cachedRelayInstances,
                    refreshedLocalHostUuids: [resolvedUuid],
                    refreshedLocalHostNames: [resolvedName],
                    refreshedCloud: false,
                    targetReachable: true,
                    latencyMs: elapsedMs
                )
            } else {
                let federated = try await fetchFederatedWorkspacesAndSummaries(
                    timeoutInterval: timeoutInterval,
                    lightweightPoll: lightweightPoll,
                    skipRelayListRefresh: true,
                    targetInstanceUuid: requestedId,
                    includeLocal: true,
                    includeCloud: false
                )
                let elapsedMs = max(1, Int(Date().timeIntervalSince(start) * 1000.0))
                return ScopedWorkspaceSyncResult(
                    workspaces: federated.workspaces.filter { !$0.isCloud },
                    summaries: federated.summaries.filter { !$0.isCloud },
                    cloudProjects: [],
                    cloudWarmingUp: false,
                    relayInstances: federated.availableRelayInstances,
                    refreshedLocalHostUuids: [requestedId],
                    refreshedLocalHostNames: [requestedName],
                    refreshedCloud: false,
                    targetReachable: true,
                    latencyMs: elapsedMs
                )
            }
        }
    }

    internal func fetchTrajectoriesResult(
        instanceUuidOverride: String?,
        originHostName: String?,
        timeoutInterval: TimeInterval?
    ) async -> Result<[CascadeSummary], Error> {
        do {
            let list = try await getAllCascadeTrajectories(
                instanceUuidOverride: instanceUuidOverride,
                originHostName: originHostName,
                timeoutInterval: timeoutInterval
            )
            return .success(list)
        } catch {
            return .failure(error)
        }
    }

    internal func fetchCloudSummariesAcrossInstances(
        candidates: [RelayInstanceInfo],
        timeoutInterval: TimeInterval?,
        includeJetboxSnapshot: Bool = true
    ) async -> (summaries: [CascadeSummary], succeeded: Bool) {
        let cloudProjectsSnapshot = self.cachedCloudProjectsById
        for inst in candidates {
            async let jbTask: [CascadeSummary] = includeJetboxSnapshot
                ? fetchJetboxSummariesSnapshot(
                    cloud: true,
                    instanceUuidOverride: inst.uuid,
                    originHostName: "Antigravity",
                    snapshotTimeout: 2.5
                )
                : []
            async let unaryTask = getAllCascadeTrajectoriesCloud(
                instanceUuidOverride: inst.uuid,
                timeoutInterval: timeoutInterval ?? 8.0
            )
            let jbCloud = await jbTask
            let unaryCloud = await unaryTask
            var combined: [String: CascadeSummary] = [:]
            for s in unaryCloud + jbCloud {
                Self.mergeSummaryEntry(s, into: &combined, cloudProjectsById: cloudProjectsSnapshot)
            }
            if !combined.isEmpty {
                self.preferredCloudInstanceUuid = inst.uuid
                return (Array(combined.values), true)
            }
        }
        return ([], false)
    }

    /// Resolves the canonical Antigravity Cloud `ProjectWorkspace` matching `summary` by:
    /// 1. Exact or `projects/`-normalized `cloudProjectId`,
    /// 2. Case-insensitive `workspaceUri` (`cloud://owner/repo`),
    /// 3. Normalized Cloud location label (`owner/repo`), or
    /// 4. Unique repo short-name suffix when `summary.isCloud == true`.
    internal static func matchCloudProject(
        for summary: CascadeSummary,
        cloudProjects: [ProjectWorkspace]
    ) -> ProjectWorkspace? {
        guard !cloudProjects.isEmpty else { return nil }

        func normalizeProjectId(_ raw: String) -> String {
            var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("projects/") {
                trimmed = String(trimmed.dropFirst("projects/".count))
            }
            return trimmed
        }

        if let rawCpid = summary.cloudProjectId, !rawCpid.isEmpty {
            let normCpid = normalizeProjectId(rawCpid)
            if let exact = cloudProjects.first(where: { cp in
                let cpId = cp.cloudProjectId ?? cp.id
                return cpId == rawCpid || cp.id == rawCpid
                    || normalizeProjectId(cpId) == normCpid
                    || normalizeProjectId(cp.id) == normCpid
            }) {
                return exact
            }
        }

        if !summary.workspaceUri.isEmpty {
            if let byUri = cloudProjects.first(where: {
                !$0.workspaceUri.isEmpty
                    && $0.workspaceUri.caseInsensitiveCompare(summary.workspaceUri) == .orderedSame
            }) {
                return byUri
            }
            if let summaryLabel = AntigravityCloudDetector.extractCloudLocationLabel(summary.workspaceUri) {
                if let byLabel = cloudProjects.first(where: { cp in
                    if let cpLabel = AntigravityCloudDetector.extractCloudLocationLabel(cp.workspaceUri),
                       cpLabel.caseInsensitiveCompare(summaryLabel) == .orderedSame {
                        return true
                    }
                    return cp.name.caseInsensitiveCompare(summaryLabel) == .orderedSame
                }) {
                    return byLabel
                }
            }
        }

        if summary.isCloud && !AntigravityCloudDetector.isNoProjectSlug(summary.projectSlug) {
            let cleanSlug = summary.projectSlug.lowercased().hasPrefix("cloud:")
                ? String(summary.projectSlug.dropFirst("cloud:".count))
                : summary.projectSlug
            if let exactName = cloudProjects.first(where: {
                $0.name.caseInsensitiveCompare(cleanSlug) == .orderedSame
            }) {
                return exactName
            }
            let suffixMatches = cloudProjects.filter { cp in
                let repoFromName = cp.name.split(separator: "/").last.map(String.init) ?? cp.name
                let repoFromUri = AntigravityCloudDetector.extractCloudLocationLabel(cp.workspaceUri)?
                    .split(separator: "/").last.map(String.init)
                return repoFromName.caseInsensitiveCompare(cleanSlug) == .orderedSame
                    || (repoFromUri?.caseInsensitiveCompare(cleanSlug) == .orderedSame)
            }
            if suffixMatches.count == 1 {
                return suffixMatches[0]
            }
        }

        return nil
    }

    internal static func summaryStatusPriority(_ status: CortexStepStatus) -> Int {
        switch status {
        case .waiting, .blocked: return 4
        case .inProgress, .pending: return 3
        case .error, .cancelled: return 2
        case .done: return 1
        case .unspecified: return 0
        }
    }

    internal static func mergeSummaryEntry(
        _ incoming: CascadeSummary,
        into map: inout [String: CascadeSummary],
        cloudProjectsById: [String: ProjectWorkspace],
        preferredInstanceUuid: String? = nil
    ) {
        let allCloudProjects = Array(cloudProjectsById.values)
        var resolved = incoming
        if let cp = matchCloudProject(for: resolved, cloudProjects: allCloudProjects) {
            resolved.isCloud = true
            resolved.cloudProjectId = cp.cloudProjectId ?? cp.id
            resolved.projectSlug = cp.name
            resolved.workspaceUri = cp.workspaceUri
            resolved.originHostName = "Antigravity"
        }

        guard let existing = map[resolved.cascadeId] else {
            map[resolved.cascadeId] = resolved
            return
        }

        var merged = resolved.stepCount >= existing.stepCount && resolved.updatedAt >= existing.updatedAt
            ? resolved
            : existing

        // 1. Title: never let an unresolved placeholder overwrite a real/hydrated title
        if existing.hasResolvedTitle && !resolved.hasResolvedTitle {
            merged.title = existing.title
            merged.hasResolvedTitle = true
        } else if resolved.hasResolvedTitle && !existing.hasResolvedTitle {
            merged.title = resolved.title
            merged.hasResolvedTitle = true
        } else if resolved.hasResolvedTitle && resolved.updatedAt >= existing.updatedAt {
            merged.title = resolved.title
            merged.hasResolvedTitle = true
        } else {
            merged.title = existing.title
            merged.hasResolvedTitle = existing.hasResolvedTitle || resolved.hasResolvedTitle
        }

        // 2. Cloud identity & canonical project binding
        merged.isCloud = existing.isCloud || resolved.isCloud
        merged.cloudProjectId = nonEmptyString(resolved.cloudProjectId) ?? nonEmptyString(existing.cloudProjectId)
        if merged.isCloud {
            merged.originHostName = "Antigravity"
        }
        if !AntigravityCloudDetector.isNoProjectSlug(existing.projectSlug)
            && AntigravityCloudDetector.isNoProjectSlug(merged.projectSlug) {
            merged.projectSlug = existing.projectSlug
            if merged.workspaceUri.isEmpty {
                merged.workspaceUri = existing.workspaceUri
            }
        }
        if !AntigravityCloudDetector.isNoProjectSlug(resolved.projectSlug)
            && AntigravityCloudDetector.isNoProjectSlug(merged.projectSlug) {
            merged.projectSlug = resolved.projectSlug
            if merged.workspaceUri.isEmpty {
                merged.workspaceUri = resolved.workspaceUri
            }
        }
        if let cp = matchCloudProject(for: merged, cloudProjects: allCloudProjects) {
            merged.isCloud = true
            merged.cloudProjectId = cp.cloudProjectId ?? cp.id
            merged.projectSlug = cp.name
            merged.workspaceUri = cp.workspaceUri
            merged.originHostName = "Antigravity"
        }

        // 3. Step count & timestamps
        merged.stepCount = max(existing.stepCount, resolved.stepCount)
        merged.currentStepIndex = max(1, merged.stepCount)
        merged.totalSteps = max(1, merged.stepCount)
        if resolved.updatedAt >= existing.updatedAt {
            merged.updatedAt = resolved.updatedAt
            merged.relativeTimeLabel = resolved.relativeTimeLabel
        } else {
            merged.updatedAt = existing.updatedAt
            merged.relativeTimeLabel = existing.relativeTimeLabel
        }

        // 4. Status: prioritize live RUNNING / WAITING over stale IDLE across multi-window & Jetbox merges
        let chosenStatus: CortexStepStatus
        if resolved.stepCount > existing.stepCount {
            if resolved.status == .unspecified
                && (existing.status == .waiting || existing.status == .blocked)
                && resolved.updatedAt <= existing.updatedAt {
                chosenStatus = existing.status
            } else {
                chosenStatus = resolved.status
            }
        } else if existing.stepCount > resolved.stepCount {
            if existing.status == .unspecified
                && (resolved.status == .waiting || resolved.status == .blocked)
                && resolved.updatedAt >= existing.updatedAt {
                chosenStatus = resolved.status
            } else {
                chosenStatus = existing.status
            }
        } else {
            let pResolved = summaryStatusPriority(resolved.status)
            let pExisting = summaryStatusPriority(existing.status)
            if pResolved > pExisting {
                if (resolved.status == .inProgress || resolved.status == .pending)
                    && existing.updatedAt > resolved.updatedAt.addingTimeInterval(2.0) {
                    chosenStatus = existing.status
                } else {
                    chosenStatus = resolved.status
                }
            } else if pExisting > pResolved {
                if (existing.status == .waiting || existing.status == .blocked
                    || existing.status == .inProgress || existing.status == .pending)
                    && resolved.updatedAt <= existing.updatedAt.addingTimeInterval(2.0) {
                    chosenStatus = existing.status
                } else {
                    chosenStatus = resolved.updatedAt >= existing.updatedAt ? resolved.status : existing.status
                }
            } else {
                chosenStatus = resolved.updatedAt >= existing.updatedAt ? resolved.status : existing.status
            }
        }
        merged.status = chosenStatus

        // 5. Route origin instance to whichever peer owns the active run or higher step count,
        //    preserving `preferredInstanceUuid` when two windows on the same Mac report equal state.
        if !merged.isCloud {
            let resolvedIsMoreActive = summaryStatusPriority(resolved.status) > summaryStatusPriority(existing.status)
                || resolved.stepCount > existing.stepCount
            let existingIsMoreActive = summaryStatusPriority(existing.status) > summaryStatusPriority(resolved.status)
                || existing.stepCount > resolved.stepCount
            if resolvedIsMoreActive, let rUuid = resolved.originInstanceUuid, !rUuid.isEmpty {
                merged.originInstanceUuid = rUuid
                merged.originHostName = resolved.originHostName ?? existing.originHostName
            } else if existingIsMoreActive, let eUuid = existing.originInstanceUuid, !eUuid.isEmpty {
                merged.originInstanceUuid = eUuid
                merged.originHostName = existing.originHostName ?? resolved.originHostName
            } else if let pref = preferredInstanceUuid, !pref.isEmpty, existing.originInstanceUuid == pref {
                merged.originInstanceUuid = existing.originInstanceUuid
                merged.originHostName = existing.originHostName ?? resolved.originHostName
            } else if let pref = preferredInstanceUuid, !pref.isEmpty, resolved.originInstanceUuid == pref {
                merged.originInstanceUuid = resolved.originInstanceUuid
                merged.originHostName = resolved.originHostName ?? existing.originHostName
            } else if let eUuid = existing.originInstanceUuid, !eUuid.isEmpty {
                merged.originInstanceUuid = eUuid
                merged.originHostName = existing.originHostName ?? resolved.originHostName
            } else {
                merged.originInstanceUuid = resolved.originInstanceUuid ?? existing.originInstanceUuid
                merged.originHostName = resolved.originHostName ?? existing.originHostName
            }
        } else {
            merged.originInstanceUuid = resolved.originInstanceUuid ?? existing.originInstanceUuid
            merged.originHostName = "Antigravity"
        }

        // 6. Annotations (`isPinned`, `isArchived`, `lastUserViewTime`, `isUnread`)
        merged.isPinned = existing.isPinned || resolved.isPinned
        merged.isArchived = existing.isArchived || resolved.isArchived
        let latestViewed = [existing.lastUserViewTime, resolved.lastUserViewTime].compactMap { $0 }.max()
        merged.lastUserViewTime = latestViewed

        if merged.status == .inProgress || merged.status == .pending {
            merged.isUnread = false
        } else if let latestViewed {
            merged.isUnread = merged.updatedAt.timeIntervalSince(latestViewed) > 0.5
                || merged.status == .waiting
                || merged.status == .blocked
        } else {
            merged.isUnread = existing.isUnread || resolved.isUnread
                || merged.status == .waiting
                || merged.status == .blocked
        }

        merged.statusSubtitle = Self.buildLiveStatusSubtitle(
            status: merged.status,
            stepCount: merged.stepCount,
            isUnread: merged.isUnread
        )
        map[resolved.cascadeId] = merged
    }

    /// Reconciles unread flags per host/cloud bucket when Desktop emits `lastUserViewTime` on viewed
    /// conversations and omits `lastUserViewTime` on newly completed conversations never opened yet.
    internal static func reconcileBatchUnreadStates(
        _ map: inout [String: CascadeSummary],
        now: Date = Date()
    ) {
        var buckets: [String: [String]] = [:]
        for (cid, summary) in map {
            let bucketKey = summary.isCloud ? "__cloud__" : (summary.originInstanceUuid ?? "__local__")
            buckets[bucketKey, default: []].append(cid)
        }
        let maxInferredUnreadAgeSeconds: TimeInterval = 7 * 86_400
        for (_, cids) in buckets {
            let bucketTracksViewTime = cids.contains { map[$0]?.lastUserViewTime != nil }
            guard bucketTracksViewTime else { continue }
            for cid in cids {
                guard var s = map[cid] else { continue }
                guard s.lastUserViewTime == nil,
                      !s.isUnread,
                      !s.isArchived,
                      s.stepCount > 0,
                      s.status != .inProgress,
                      s.status != .pending,
                      s.status != .cancelled,
                      now.timeIntervalSince(s.updatedAt) <= maxInferredUnreadAgeSeconds else {
                    continue
                }
                s.isUnread = true
                s.statusSubtitle = Self.buildLiveStatusSubtitle(
                    status: s.status,
                    stepCount: s.stepCount,
                    isUnread: true
                )
                map[cid] = s
            }
        }
    }

    internal func getWorkspaceInfosOptional(timeoutInterval: TimeInterval?) async throws -> [WorkspaceInfo] {
        do {
            return try await getWorkspaceInfos(timeoutInterval: timeoutInterval)
        } catch let AntigravityRPCError.httpError(statusCode, _) where statusCode == 404 {
            return []
        } catch {
            if channel == .cloudRelay {
                return []
            }
            throw error
        }
    }


    // MARK: - Antigravity Cloud (`BACKEND_TYPE_REMOTE_AICODE`) Projects & Summaries

    /// Lists and reads Antigravity Cloud ("Remote Agents") projects via `ListProjects` + `ReadProject`.
    public func fetchCloudProjects(
        candidateInstances: [RelayInstanceInfo] = [],
        timeoutInterval: TimeInterval? = nil
    ) async -> (projects: [ProjectWorkspace], warmingUp: Bool) {
        let targetUuids: [String?] = {
            if channel == .cloudRelay && !candidateInstances.isEmpty {
                if let pref = preferredCloudInstanceUuid,
                   candidateInstances.contains(where: { $0.uuid == pref }) {
                    let rest = candidateInstances.filter { $0.uuid != pref }.map { Optional($0.uuid) }
                    return [Optional(pref)] + rest
                }
                return candidateInstances.map { Optional($0.uuid) }
            }
            return [nil]
        }()

        var sawWarmingUp = false
        for targetUuid in targetUuids {
            do {
                let listResp = try await callUnaryJSON(
                    method: "ListProjects",
                    body: ["backend": .string("BACKEND_TYPE_REMOTE_AICODE")],
                    instanceUuidOverride: targetUuid,
                    timeoutInterval: timeoutInterval ?? 8.0
                )
                let ids = listResp["projectIds"]?.arrayValue?.compactMap(\.stringValue).filter { !$0.isEmpty } ?? []
                guard !ids.isEmpty else { continue }

                var loadedByIndex: [Int: ProjectWorkspace] = [:]
                let readTimeout = timeoutInterval ?? 8.0
                await withTaskGroup(of: (Int, ProjectWorkspace?).self) { group in
                    for (idx, pid) in ids.enumerated() {
                        group.addTask {
                            guard let readResp = try? await self.callUnaryJSON(
                                method: "ReadProject",
                                body: ["id": .string(pid)],
                                instanceUuidOverride: targetUuid,
                                timeoutInterval: readTimeout
                            ),
                            let projObj = readResp["project"]?.objectValue else {
                                return (idx, nil)
                            }
                            let parsed = Self.decodeCloudProjectObject(
                                projObj,
                                fallbackId: pid,
                                originInstanceUuid: targetUuid
                            )
                            return (idx, parsed)
                        }
                    }
                    for await (idx, parsed) in group {
                        if let parsed {
                            loadedByIndex[idx] = parsed
                        }
                    }
                }
                var loaded: [ProjectWorkspace] = []
                for idx in ids.indices {
                    if let parsed = loadedByIndex[idx] {
                        cachedCloudProjectsById[parsed.id] = parsed
                        loaded.append(parsed)
                    }
                }
                if !loaded.isEmpty {
                    if let effectiveUuid = targetUuid ?? resolvedInstanceUuid, !effectiveUuid.isEmpty {
                        self.preferredCloudInstanceUuid = effectiveUuid
                    }
                    return (loaded, false)
                }
            } catch let AntigravityRPCError.httpError(_, body) {
                let lower = body.lowercased()
                if lower.contains("failed_precondition") || lower.contains("not enabled") || lower.contains("precondition") {
                    sawWarmingUp = true
                }
            } catch {
                continue
            }
        }
        return ([], sawWarmingUp)
    }

    internal static func decodeCloudProjectObject(
        _ projObj: [String: JSONValue],
        fallbackId: String,
        originInstanceUuid: String?
    ) -> ProjectWorkspace {
        let pid = nonEmptyString(projObj["id"]?.stringValue) ?? fallbackId
        let name = nonEmptyString(projObj["name"]?.stringValue) ?? "Antigravity Cloud"
        let resources = projObj["projectResources"]?.objectValue?["resources"]?.arrayValue ?? []
        var repoDisplay: String? = nil
        for resEntry in resources {
            guard let resObj = resEntry.objectValue else { continue }
            let nestedCandidates: [[String: JSONValue]?] = [
                resObj["remoteResource"]?.objectValue,
                resObj["githubRepo"]?.objectValue,
                resObj["githubRepository"]?.objectValue,
                resObj["gitFolder"]?.objectValue
            ]
            if let rr = nestedCandidates.compactMap({ $0 }).first {
                let displayNameCandidates: [String?] = [
                    rr["displayName"]?.stringValue,
                    rr["fullName"]?.stringValue,
                    rr["name"]?.stringValue,
                    rr["uri"]?.stringValue,
                    rr["folderUri"]?.stringValue
                ]
                if let dn = displayNameCandidates.compactMap(nonEmptyString).first {
                    var normalized = dn
                        .replacingOccurrences(of: "https://github.com/", with: "")
                        .replacingOccurrences(of: "http://github.com/", with: "")
                        .replacingOccurrences(of: "cloud://", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    if normalized.hasSuffix(".git") {
                        normalized = String(normalized.dropLast(4))
                    }
                    if !normalized.isEmpty {
                        repoDisplay = normalized
                        break
                    }
                }
            }
        }
        if repoDisplay == nil {
            if let fallbackRepo = nonEmptyString(projObj["repository"]?.stringValue)
                ?? nonEmptyString(projObj["repo"]?.stringValue) {
                repoDisplay = fallbackRepo
                    .replacingOccurrences(of: "https://github.com/", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }
        let cloudSlug = repoDisplay ?? name
        let workspaceUri = "cloud://\(cloudSlug)"
        return ProjectWorkspace(
            id: pid,
            name: name,
            pathDisplay: workspaceUri,
            workspaceUri: workspaceUri,
            runtime: .cloud,
            hostName: "Antigravity",
            activeBranch: "main",
            cloudProjectId: pid,
            originInstanceUuid: originInstanceUuid
        )
    }

    /// Queries connected GitHub repositories available to Antigravity Cloud (`ListAvailableResources`).
    public func fetchCloudGitHubRepos() async -> [GitHubRepoItem] {
        guard let resp = try? await callUnaryJSON(
            method: "ListAvailableResources",
            body: [
                "backend": .string("BACKEND_TYPE_REMOTE_AICODE"),
                "type": .string("github")
            ],
            timeoutInterval: 8.0
        ),
        let resources = resp["resources"]?.arrayValue else {
            return []
        }
        return resources.compactMap { entry -> GitHubRepoItem? in
            guard let obj = entry.objectValue else { return nil }
            guard let fullName = Self.nonEmptyString(obj["displayName"]?.stringValue)
                ?? Self.nonEmptyString(obj["name"]?.stringValue) else {
                return nil
            }
            let branch = Self.nonEmptyString(obj["defaultBranch"]?.stringValue) ?? "main"
            return GitHubRepoItem(
                id: "repo-\(fullName)",
                fullName: fullName,
                visibilityLabel: obj["isPrivate"]?.boolValue == true ? "Private" : "GitHub",
                defaultBranch: branch
            )
        }
    }

    internal actor JetboxSnapshotAccumulator {
        private var byId: [String: CascadeSummary] = [:]
        private var finished: Bool = false
        private var recordedError: Error? = nil

        func merge(_ items: [CascadeSummary], cloudProjectsById: [String: ProjectWorkspace]) {
            for item in items {
                AntigravityRPCClient.mergeSummaryEntry(item, into: &byId, cloudProjectsById: cloudProjectsById)
            }
        }

        func markFinished(error: Error? = nil) {
            finished = true
            if let error, recordedError == nil {
                recordedError = error
            }
        }

        func status() -> (hasEntries: Bool, isFinished: Bool, error: Error?) {
            (!byId.isEmpty, finished, recordedError)
        }

        func values() -> [CascadeSummary] {
            Array(byId.values)
        }
    }

    /// Unary Cloud companion query (`GetAllCascadeTrajectories` with `BACKEND_TYPE_REMOTE_AICODE`).
    /// Never silently strips `backend` so local-only trajectories cannot leak into Cloud results.
    internal func getAllCascadeTrajectoriesCloud(
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async -> [CascadeSummary] {
        let candidatePayloads: [[String: JSONValue]] = [
            ["backend": .string("BACKEND_TYPE_REMOTE_AICODE")],
            ["backendType": .string("BACKEND_TYPE_REMOTE_AICODE")]
        ]
        let cloudProjectsSnapshot = self.cachedCloudProjectsById
        let allCloudProjects = Array(cloudProjectsSnapshot.values)
        let effectiveUuid = instanceUuidOverride ?? resolvedInstanceUuid

        for (idx, payload) in candidatePayloads.enumerated() {
            do {
                let res: [String: JSONValue]
                if channel == .cloudRelay {
                    res = try await callCloudRelayUnaryJSON(
                        method: "GetAllCascadeTrajectories",
                        body: payload,
                        instanceUuidOverride: instanceUuidOverride,
                        timeoutInterval: timeoutInterval ?? 8.0,
                        allowStripUnknownFields: false
                    )
                } else {
                    res = try await callUnaryJSON(
                        method: "GetAllCascadeTrajectories",
                        body: payload,
                        instanceUuidOverride: instanceUuidOverride,
                        timeoutInterval: timeoutInterval ?? 4.0,
                        allowStripUnknownFields: false
                    )
                }
                let decoded = Self.decodeJetboxSummariesEvent(
                    res,
                    forceCloud: true,
                    originInstanceUuid: effectiveUuid,
                    originHostName: "Antigravity",
                    cloudProjectsById: cloudProjectsSnapshot
                ).upserts.map { item -> CascadeSummary in
                    var copy = item
                    if let cp = Self.matchCloudProject(for: copy, cloudProjects: allCloudProjects) {
                        copy.isCloud = true
                        copy.cloudProjectId = cp.cloudProjectId ?? cp.id
                        copy.projectSlug = cp.name
                        copy.workspaceUri = cp.workspaceUri
                        copy.originHostName = "Antigravity"
                    }
                    return copy
                }
                return decoded
            } catch let AntigravityRPCError.httpError(statusCode, body) {
                let unknownField = ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body)
                if idx == 0 && (unknownField?.lowercased() == "backend" || statusCode == 400) {
                    continue
                }
                return []
            } catch {
                return []
            }
        }
        return []
    }

    internal func readJetboxSnapshotOnce(
        requestPayload: [String: JSONValue],
        cloud: Bool,
        instanceUuidOverride: String?,
        originHostName: String?,
        snapshotTimeout: TimeInterval,
        cloudProjectsSnapshot: [String: ProjectWorkspace]
    ) async throws -> [CascadeSummary] {
        let stream = try subscribeEnvelopeStream(
            method: "JetboxSubscribeToSummaries",
            requestPayload: requestPayload,
            instanceUuidOverride: instanceUuidOverride,
            allowCrossHostFailover: cloud
        )
        let accumulator = JetboxSnapshotAccumulator()
        let readerTask = Task {
            do {
                for try await event in stream {
                    let parsed = Self.decodeJetboxSummariesEvent(
                        event,
                        forceCloud: cloud,
                        originInstanceUuid: instanceUuidOverride,
                        originHostName: originHostName,
                        cloudProjectsById: cloudProjectsSnapshot
                    )
                    if !parsed.upserts.isEmpty {
                        await accumulator.merge(parsed.upserts, cloudProjectsById: cloudProjectsSnapshot)
                    }
                }
                await accumulator.markFinished()
            } catch {
                await accumulator.markFinished(error: error)
            }
        }
        defer { readerTask.cancel() }

        let deadline = Date().addingTimeInterval(max(0.5, snapshotTimeout))
        while Date() < deadline {
            let st = await accumulator.status()
            if st.hasEntries {
                // Allow a brief settle window so any back-to-back initial snapshot frames arrive together
                let remaining = deadline.timeIntervalSinceNow
                if !st.isFinished && remaining > 0.05 {
                    let settleSeconds = min(0.22, remaining)
                    try? await Task.sleep(nanoseconds: UInt64(settleSeconds * 1_000_000_000))
                }
                return await accumulator.values()
            }
            if st.isFinished {
                if let err = st.error {
                    throw err
                }
                return await accumulator.values()
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return await accumulator.values()
    }

    /// Reads the initial snapshot frame(s) emitted by `JetboxSubscribeToSummaries` (either local or `BACKEND_TYPE_REMOTE_AICODE` Cloud),
    /// skipping empty initial ack frames and retrying `backendType` if the server rejects `"backend"`, then closes the temporary stream.
    public func fetchJetboxSummariesSnapshot(
        cloud: Bool,
        instanceUuidOverride: String? = nil,
        originHostName: String? = nil,
        snapshotTimeout: TimeInterval = 4.0
    ) async -> [CascadeSummary] {
        let cloudProjectsSnapshot = self.cachedCloudProjectsById
        let primaryPayload: [String: JSONValue] = cloud
            ? ["backend": .string("BACKEND_TYPE_REMOTE_AICODE")]
            : [:]
        do {
            let primary = try await readJetboxSnapshotOnce(
                requestPayload: primaryPayload,
                cloud: cloud,
                instanceUuidOverride: instanceUuidOverride,
                originHostName: originHostName,
                snapshotTimeout: snapshotTimeout,
                cloudProjectsSnapshot: cloudProjectsSnapshot
            )
            if !primary.isEmpty || !cloud {
                return primary
            }
        } catch let AntigravityRPCError.httpError(_, body)
            where cloud && ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: body)?.lowercased() == "backend" {
            if let fallback = try? await readJetboxSnapshotOnce(
                requestPayload: ["backendType": .string("BACKEND_TYPE_REMOTE_AICODE")],
                cloud: true,
                instanceUuidOverride: instanceUuidOverride,
                originHostName: originHostName,
                snapshotTimeout: snapshotTimeout,
                cloudProjectsSnapshot: cloudProjectsSnapshot
            ) {
                return fallback
            }
        } catch {
            return []
        }
        return []
    }

    /// Decodes a `JetboxSubscribeToSummariesResponse` (`updates` map + `deletes` array, `trajectorySummaries` map, or mock `summaries` array).
    public static func decodeJetboxSummariesEvent(
        _ event: [String: JSONValue],
        forceCloud: Bool = false,
        originInstanceUuid: String? = nil,
        originHostName: String? = nil,
        cloudProjectsById: [String: ProjectWorkspace] = [:]
    ) -> (upserts: [CascadeSummary], deletes: [String]) {
        let now = Date()
        var upserts: [CascadeSummary] = []
        let deletes = event["deletes"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let allCloudProjects = Array(cloudProjectsById.values)

        func finalizeDecodedSummary(_ rawSummary: CascadeSummary) -> CascadeSummary? {
            var summary = rawSummary
            if forceCloud {
                // Ignore local `file://` workspaces echoed by older/mock servers that do not filter by `backend`,
                // while keeping Cloud `No Project` sessions (`summary.workspaceUri.isEmpty`).
                if !summary.workspaceUri.isEmpty
                    && !AntigravityCloudDetector.isPlaygroundScratchURI(summary.workspaceUri)
                    && !summary.isCloud
                    && (summary.cloudProjectId ?? "").isEmpty {
                    return nil
                }
                summary.isCloud = true
                summary.originHostName = "Antigravity"
            } else if !summary.isCloud {
                summary.originHostName = originHostName
            }
            summary.originInstanceUuid = originInstanceUuid
            if let cp = Self.matchCloudProject(for: summary, cloudProjects: allCloudProjects) {
                summary.isCloud = true
                summary.cloudProjectId = cp.cloudProjectId ?? cp.id
                summary.projectSlug = cp.name
                summary.workspaceUri = cp.workspaceUri
                summary.originHostName = "Antigravity"
            }
            return summary
        }

        if let updatesMap = event["updates"]?.objectValue ?? event["trajectorySummaries"]?.objectValue {
            for (cid, val) in updatesMap {
                if let obj = val.objectValue,
                   obj["killed"]?.boolValue == true,
                   (obj["status"]?.stringValue ?? "").contains("UNSPECIFIED") {
                    continue
                }
                if let decoded = Self.decodeTrajectorySummaryEntry(
                    cascadeId: cid,
                    value: val,
                    now: now,
                    forceCloud: forceCloud
                ), let finalized = finalizeDecodedSummary(decoded) {
                    upserts.append(finalized)
                }
            }
        } else if let summariesArr = event["summaries"]?.arrayValue ?? event["trajectories"]?.arrayValue {
            for val in summariesArr {
                guard let cid = val.objectValue?["cascadeId"]?.stringValue else { continue }
                if let decoded = Self.decodeTrajectorySummaryEntry(
                    cascadeId: cid,
                    value: val,
                    now: now,
                    forceCloud: forceCloud
                ), let finalized = finalizeDecodedSummary(decoded) {
                    upserts.append(finalized)
                }
            }
        }
        return (upserts, deletes)
    }

    internal static func extractUnknownProtoFieldName(from message: String) -> String? {
        guard let markerRange = message.range(of: "unknown field \"") else { return nil }
        let rest = message[markerRange.upperBound...]
        guard let endQuote = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<endQuote])
    }

}
