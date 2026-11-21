import Foundation

/// Pure Swift 6 Connect-RPC & Google Cloud Relay client for `exa.language_server_pb.LanguageServerService`.
///
/// Connects either to:
/// 1. Official Antigravity Remote Control Relay (`https://antigravity.google.com/r/<instance-id>` via `devtools_jetski_boq_api_proto.ApiService`)
/// 2. Direct LAN / Tailscale `language_server` or Mac Companion Bridge (`https://<host>:<port>`) with `x-codeium-csrf-token`
public actor AntigravityRPCClient {
    public static let servicePrefix = "/exa.language_server_pb.LanguageServerService"
    public static let protobufStepThreshold = 600

    internal let channel: RemoteConnectionChannel
    internal let endpointURL: URL
    internal let relayOriginURL: URL
    internal let csrfToken: String?
    internal let sessionCookie: String?
    internal let explicitAuthUser: String?
    internal var authUser: String
    internal var targetInstanceIdentifier: String
    internal var resolvedInstanceUuid: String?
    internal var preferredCloudInstanceUuid: String? = nil
    internal var cachedRelayInstances: [RelayInstanceInfo] = []
    internal var cachedCloudProjectsById: [String: ProjectWorkspace] = [:]
    internal var cachedLocalProjectNameById: [String: String] = [:]
    internal var cachedLocalProjectIdByName: [String: String] = [:]
    internal var lastLocalProjectFetchAt: Date? = nil
    internal var wokenInstanceCascadeKeys: Set<String> = []
    internal var cachedValidUpstreamModels: Set<String>?
    internal var cachedDefaultUpstreamModel: String?
    internal let urlSession: URLSession
    internal let streamingURLSession: URLSession

    public struct LiveModelCatalogResult: Sendable, Equatable {
        public let models: [CascadeModelConfig]
        public let defaultModelId: String?
        public let agents: [String]
        public let usageQuota: ModelUsageQuota?

        public init(
            models: [CascadeModelConfig],
            defaultModelId: String? = nil,
            agents: [String] = ["Default"],
            usageQuota: ModelUsageQuota? = nil
        ) {
            self.models = models
            self.defaultModelId = defaultModelId
            self.agents = agents
            self.usageQuota = usageQuota
        }
    }

    /// Only true local-OS-only desktop commands (like revealing a local folder in macOS Finder
    /// or Companion Bridge's sandboxed `ReadArtifactFile`) are local-only; all upstream data & review RPCs forward over Cloud Relay.
    internal static let localDesktopOnlyMethods: Set<String> = [
        "OpenWorkspaceInFinder",
        "ReadArtifactFile"
    ]

    public init(
        host: RemoteHostInstance,
        csrfToken: String? = nil,
        sessionCookie: String? = nil,
        authUser: String? = nil,
        resolvedInstanceUuid: String? = nil,
        pinnedFingerprintSHA256: String? = nil,
        urlSession: URLSession? = nil
    ) {
        self.channel = host.channel
        self.endpointURL = host.endpointURL
        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(host.endpointURL.absoluteString)
        self.relayOriginURL = URL(string: parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin)
            ?? host.endpointURL
        let extractedId = parsedTarget?.instanceId.isEmpty == false ? parsedTarget!.instanceId : host.instanceId
        self.targetInstanceIdentifier = extractedId
        self.resolvedInstanceUuid = resolvedInstanceUuid
        let effectiveAuthUser = authUser ?? parsedTarget?.authUser
        self.explicitAuthUser = effectiveAuthUser
        self.authUser = effectiveAuthUser ?? "0"
        self.csrfToken = csrfToken
        self.sessionCookie = sessionCookie
        if let urlSession {
            self.urlSession = urlSession
            self.streamingURLSession = urlSession
        } else {
            self.urlSession = Self.makeDefaultURLSession(
                for: host.endpointURL,
                pinnedFingerprintSHA256: pinnedFingerprintSHA256,
                allowLocalSelfSignedTOFU: host.channel == .directHost,
                requestTimeout: 20,
                resourceTimeout: 300
            )
            self.streamingURLSession = Self.makeDefaultURLSession(
                for: host.endpointURL,
                pinnedFingerprintSHA256: pinnedFingerprintSHA256,
                allowLocalSelfSignedTOFU: host.channel == .directHost,
                requestTimeout: 300,
                resourceTimeout: 3600
            )
        }
    }

    public init(
        baseURL: URL,
        csrfToken: String? = nil,
        sessionCookie: String? = nil,
        authUser: String? = nil,
        resolvedInstanceUuid: String? = nil,
        pinnedFingerprintSHA256: String? = nil,
        urlSession: URLSession? = nil
    ) {
        let parsedTarget = RemoteHostInstance.parseRemoteControlTarget(baseURL.absoluteString)
        let isRelay = parsedTarget != nil && (csrfToken == nil || csrfToken?.isEmpty == true) && (sessionCookie?.isEmpty == false)
        self.channel = isRelay ? .cloudRelay : .directHost
        self.endpointURL = baseURL
        self.relayOriginURL = URL(string: parsedTarget?.relayOrigin ?? SAPISIDHashGenerator.defaultOrigin) ?? baseURL
        self.targetInstanceIdentifier = parsedTarget?.instanceId ?? ""
        self.resolvedInstanceUuid = resolvedInstanceUuid
        let effectiveAuthUser = authUser ?? parsedTarget?.authUser
        self.explicitAuthUser = effectiveAuthUser
        self.authUser = effectiveAuthUser ?? "0"
        self.csrfToken = csrfToken
        self.sessionCookie = sessionCookie
        if let urlSession {
            self.urlSession = urlSession
            self.streamingURLSession = urlSession
        } else {
            self.urlSession = Self.makeDefaultURLSession(
                for: baseURL,
                pinnedFingerprintSHA256: pinnedFingerprintSHA256,
                allowLocalSelfSignedTOFU: true,
                requestTimeout: 20,
                resourceTimeout: 300
            )
            self.streamingURLSession = Self.makeDefaultURLSession(
                for: baseURL,
                pinnedFingerprintSHA256: pinnedFingerprintSHA256,
                allowLocalSelfSignedTOFU: true,
                requestTimeout: 300,
                resourceTimeout: 3600
            )
        }
    }

    nonisolated private static func makeDefaultURLSession(
        for endpointURL: URL,
        pinnedFingerprintSHA256: String?,
        allowLocalSelfSignedTOFU: Bool,
        requestTimeout: TimeInterval = 20,
        resourceTimeout: TimeInterval = 300
    ) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        let host = (endpointURL.host ?? "").lowercased()
        let isLocalOrPrivateHost =
            host == "localhost" ||
            host == "127.0.0.1" ||
            host == "::1" ||
            host.hasSuffix(".local") ||
            host.hasSuffix(".ts.net") ||
            host.hasPrefix("192.168.") ||
            host.hasPrefix("10.") ||
            host.hasPrefix("100.") ||
            host.hasPrefix("172.")
        if isLocalOrPrivateHost {
            config.connectionProxyDictionary = [:]
        }
        let delegate = PinnedTLSURLSessionDelegate(
            pinnedFingerprintSHA256: pinnedFingerprintSHA256,
            allowLocalSelfSignedTOFU: allowLocalSelfSignedTOFU
        )
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Core Unary RPC (`Sendable` JSONValue & Binary Protobuf)

    public func callUnaryJSON(
        method: String,
        body: [String: JSONValue] = [:],
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> [String: JSONValue] {
        if channel == .cloudRelay {
            let relayTimeout = timeoutInterval.map { max($0, 10.0) }
            return try await callCloudRelayUnaryJSON(
                method: method,
                body: body,
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: relayTimeout
            )
        }

        let url = endpointURL.appendingPathComponent("\(Self.servicePrefix)/\(method)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        applyAuthHeaders(to: &request)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AntigravityRPCError.invalidEndpoint
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            let text = String(data: data, encoding: .utf8) ?? "Unauthorized"
            throw AntigravityRPCError.unauthorized(text)
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw AntigravityRPCError.httpError(statusCode: http.statusCode, body: text)
        }
        if data.isEmpty {
            return [:]
        }
        guard let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            throw AntigravityRPCError.decodingError("Expected JSON object from \(method)")
        }
        return decoded
    }

    internal func callCloudRelayUnaryJSON(
        method: String,
        body: [String: JSONValue],
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil,
        allowStripUnknownFields: Bool = true
    ) async throws -> [String: JSONValue] {
        if Self.localDesktopOnlyMethods.contains(method) {
            throw AntigravityRPCError.httpError(
                statusCode: 501,
                body: "\(method) is only available when connected directly to a local desktop workspace."
            )
        }

        var workingBody = try await sanitizeCloudRelayPayload(method: method, body: body)
        for attempt in 1...4 {
            let encodedPayload = workingBody.isEmpty ? Data("{}".utf8) : try JSONEncoder().encode(workingBody)
            let (rawRespData, _) = try await callCloudRelayProxyCommand(
                method: method,
                payload: encodedPayload,
                contentType: "application/json",
                instanceUuidOverride: instanceUuidOverride,
                timeoutInterval: timeoutInterval
            )
            let respData = Self.unwrapConnectFramedPayloadIfNeeded(rawRespData)
            if respData.isEmpty {
                return [:]
            }
            if let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: respData) {
                if let code = decoded["code"]?.stringValue,
                   let message = decoded["message"]?.stringValue,
                   decoded.count <= 3 {
                    if allowStripUnknownFields, attempt < 4, let unknownField = Self.extractUnknownProtoFieldName(from: message) {
                        if workingBody[unknownField] != nil {
                            workingBody.removeValue(forKey: unknownField)
                            continue
                        }
                        if var cascadeCfg = workingBody["cascadeConfig"]?.objectValue,
                           var plannerCfg = cascadeCfg["plannerConfig"]?.objectValue,
                           plannerCfg[unknownField] != nil {
                            plannerCfg.removeValue(forKey: unknownField)
                            cascadeCfg["plannerConfig"] = .object(plannerCfg)
                            workingBody["cascadeConfig"] = .object(cascadeCfg)
                            continue
                        }
                    }
                    throw AntigravityRPCError.httpError(statusCode: 400, body: "\(code): \(message)")
                }
                return decoded
            }
            let rawText = String(data: respData, encoding: .utf8) ?? ""
            if allowStripUnknownFields, attempt < 4,
               let unknownField = Self.extractUnknownProtoFieldName(from: rawText),
               workingBody[unknownField] != nil {
                workingBody.removeValue(forKey: unknownField)
                continue
            }
            throw AntigravityRPCError.decodingError("Expected JSON object from Cloud Relay \(method)")
        }
        return [:]
    }

    internal static func unwrapConnectFramedPayloadIfNeeded(_ data: Data) -> Data {
        guard data.count >= 5 else { return data }
        let firstByte = data[data.startIndex]
        guard firstByte == 0x00 || firstByte == 0x01 else { return data }
        var parser = ConnectStreamParser()
        let frames = parser.feed(data)
        let nonTrailerFrames = frames.filter { !$0.isEndStream }
        guard !nonTrailerFrames.isEmpty else { return data }
        var out = Data()
        for frame in nonTrailerFrames {
            let decoded = frame.isCompressed
                ? CloudRelayJSPBCodec.decompressPayloadIfNeeded(frame.payload)
                : frame.payload
            out.append(decoded)
        }
        return out.isEmpty ? data : out
    }

    internal func selectReachableRelayUuid(preferred: String?) -> String? {
        let candidate = (preferred?.isEmpty == false) ? preferred : resolvedInstanceUuid
        guard !cachedRelayInstances.isEmpty else { return candidate }
        if let candidate,
           cachedRelayInstances.contains(where: { $0.uuid == candidate && $0.status.isReachable }) {
            return candidate
        }
        let familySeed = cachedRelayInstances.first(where: { $0.uuid == candidate })?.name ?? targetInstanceIdentifier
        let familyOnline = cachedRelayInstances.first(where: {
            $0.status.isReachable && $0.sameHostFamily(as: familySeed)
        })
        let preferredResolved = resolvedInstanceUuid.flatMap { resUuid in
            cachedRelayInstances.contains(where: { $0.uuid == resUuid && $0.status.isReachable }) ? resUuid : nil
        }
        let anyOnline = cachedRelayInstances.first(where: \.status.isReachable)
        if let liveBest = familyOnline?.uuid ?? preferredResolved ?? anyOnline?.uuid {
            if resolvedInstanceUuid == nil
                || !cachedRelayInstances.contains(where: { $0.uuid == resolvedInstanceUuid && $0.status.isReachable }) {
                self.resolvedInstanceUuid = liveBest
            }
            return liveBest
        }
        return candidate
    }

    internal func callCloudRelayProxyCommand(
        method: String,
        payload: Data,
        contentType: String,
        instanceUuidOverride: String? = nil,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> (payload: Data, headers: [String: String]) {
        if instanceUuidOverride == nil && resolvedInstanceUuid == nil {
            _ = try await resolveCloudRelayInstance(
                preferredIdentifier: targetInstanceIdentifier,
                timeoutInterval: timeoutInterval
            )
        } else if cachedRelayInstances.isEmpty {
            if let refreshed = try? await listRelayInstances(timeoutInterval: min(timeoutInterval ?? 6.0, 6.0)),
               !refreshed.isEmpty {
                self.cachedRelayInstances = refreshed
            }
        }

        guard let initialTargetUuid = selectReachableRelayUuid(preferred: instanceUuidOverride),
              !initialTargetUuid.isEmpty else {
            throw AntigravityRPCError.invalidEndpoint
        }

        let originStr = SAPISIDHashGenerator.normalizeOrigin(relayOriginURL.absoluteString)
        guard var comps = URLComponents(string: "\(originStr)\(SAPISIDHashGenerator.apiServicePrefix)/ProxyCommand") else {
            throw AntigravityRPCError.invalidEndpoint
        }
        comps.queryItems = [URLQueryItem(name: "$unique", value: method)]
        guard let url = comps.url else {
            throw AntigravityRPCError.invalidEndpoint
        }

        let currentCookie = sessionCookie ?? ""
        let currentAuthUser = authUser
        let session = urlSession

        func sendOnce(to targetUuid: String, authUserOverride: String? = nil) async throws -> (payload: Data, headers: [String: String]) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            if let timeoutInterval {
                request.timeoutInterval = timeoutInterval
            }
            SAPISIDHashGenerator.applyApiServiceHeaders(
                to: &request,
                cookieHeader: currentCookie,
                origin: originStr,
                authUser: authUserOverride ?? currentAuthUser,
                isStreaming: false
            )
            request.httpBody = try CloudRelayJSPBCodec.encodeProxyCommandRequest(
                targetInstanceUuid: targetUuid,
                rpcPath: "\(Self.servicePrefix)/\(method)",
                payload: payload,
                contentType: contentType,
                isStreaming: false
            )

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AntigravityRPCError.invalidEndpoint
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                let text = String(data: data, encoding: .utf8) ?? "Unauthorized"
                throw AntigravityRPCError.unauthorized(text)
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw AntigravityRPCError.httpError(statusCode: http.statusCode, body: text)
            }
            return try CloudRelayJSPBCodec.decodeProxyCommandResponse(
                data,
                responseHeaders: http.allHeaderFields
            )
        }

        do {
            return try await sendOnce(to: initialTargetUuid)
        } catch let AntigravityRPCError.unauthorized(msg) {
            if let resolved = try? await resolveCloudRelayInstance(
                preferredIdentifier: targetInstanceIdentifier,
                timeoutInterval: 6.0
            ), (resolved.matchedAuthUser != currentAuthUser || resolved.selected.uuid != initialTargetUuid) {
                return try await sendOnce(to: resolved.selected.uuid, authUserOverride: resolved.matchedAuthUser)
            }
            throw AntigravityRPCError.unauthorized(msg)
        } catch {
            let shouldFailover: Bool = {
                if error is URLError { return true }
                if case let AntigravityRPCError.httpError(code, _) = error {
                    return code == 404 || code == 502 || code == 503 || code == 504
                }
                return false
            }()
            if shouldFailover,
               let refreshed = try? await listRelayInstances(timeoutInterval: 6.0),
               !refreshed.isEmpty {
                self.cachedRelayInstances = refreshed
                let familySeed = refreshed.first(where: { $0.uuid == initialTargetUuid })?.name ?? targetInstanceIdentifier
                if let altInst = refreshed.first(where: {
                    $0.uuid != initialTargetUuid && $0.status.isReachable && $0.sameHostFamily(as: familySeed)
                }) ?? refreshed.first(where: {
                    $0.uuid != initialTargetUuid && $0.status.isReachable
                }) {
                    self.resolvedInstanceUuid = altInst.uuid
                    return try await sendOnce(to: altInst.uuid)
                }
            }
            throw error
        }
    }

    internal func sanitizeCloudRelayPayload(
        method: String,
        body: [String: JSONValue]
    ) async throws -> [String: JSONValue] {
        let desktopMetadata: JSONValue = .object([
            "ideName": .string("antigravity"),
            "extensionName": .string("antigravity"),
            "locale": .string("en")
        ])

        switch method {
        case "StartCascade":
            var clean: [String: JSONValue] = [
                "metadata": desktopMetadata,
                "source": .string("CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT")
            ]
            if let cid = body["cascadeId"]?.stringValue, !cid.isEmpty {
                clean["cascadeId"] = .string(cid)
            }
            if let backend = body["backend"]?.stringValue, !backend.isEmpty {
                clean["backend"] = .string(backend)
            }
            if let projEnv = body["projectEnvConfig"] {
                clean["projectEnvConfig"] = projEnv
            } else if let uris = body["workspaceUris"], uris.arrayValue?.isEmpty == false {
                clean["workspaceUris"] = uris
            }
            return clean

        case "SendUserCascadeMessage":
            var cleanItems: [JSONValue] = []
            if let rawItems = body["items"]?.arrayValue {
                for entry in rawItems {
                    guard let obj = entry.objectValue else { continue }
                    if let text = obj["text"]?.stringValue {
                        cleanItems.append(.object(["text": .string(text)]))
                    } else {
                        let itemObj = obj["item"]?.objectValue ?? obj
                        if let fileObj = itemObj["file"]?.objectValue,
                           let absUri = fileObj["absoluteUri"]?.stringValue ?? fileObj["absolutePathUri"]?.stringValue,
                           !absUri.isEmpty {
                            var cleanFile: [String: JSONValue] = ["absoluteUri": .string(absUri)]
                            if let label = fileObj["label"]?.stringValue, !label.isEmpty {
                                cleanFile["label"] = .string(label)
                            }
                            cleanItems.append(.object(["item": .object(["file": .object(cleanFile)])]))
                        } else if let mediaObj = itemObj["media"]?.objectValue {
                            cleanItems.append(.object(["item": .object(["media": .object(mediaObj)])]))
                        } else if let quoteObj = itemObj["codeQuote"]?.objectValue {
                            cleanItems.append(.object(["item": .object(["codeQuote": .object(quoteObj)])]))
                        } else if let mentionObj = itemObj["mention"]?.objectValue {
                            cleanItems.append(.object(["item": .object(["mention": .object(mentionObj)])]))
                        }
                    }
                }
            }
            if cleanItems.isEmpty, let fallbackText = body["userResponse"]?.stringValue, !fallbackText.isEmpty {
                cleanItems.append(.object(["text": .string(fallbackText)]))
            }

            var clean: [String: JSONValue] = [
                "cascadeId": body["cascadeId"] ?? .string(""),
                "items": .array(cleanItems),
                "metadata": desktopMetadata
            ]

            if var cascadeCfg = body["cascadeConfig"]?.objectValue,
               var plannerCfg = cascadeCfg["plannerConfig"]?.objectValue {
                // Ensure conversational.plannerMode is ALWAYS valid upstream enum (`CONVERSATIONAL_PLANNER_MODE_DEFAULT`)
                if var convObj = plannerCfg["conversational"]?.objectValue {
                    let rawMode = convObj["plannerMode"]?.stringValue ?? ""
                    if rawMode != "CONVERSATIONAL_PLANNER_MODE_DEFAULT" && rawMode != "CONVERSATIONAL_PLANNER_MODE_READ_ONLY" {
                        convObj["plannerMode"] = .string("CONVERSATIONAL_PLANNER_MODE_DEFAULT")
                    }
                    plannerCfg["conversational"] = .object(convObj)
                }

                // Preserve thinkingEffort, agentPersona, and permissionPreset on Cloud Relay
                if let modelCfgObj = body["modelConfig"]?.objectValue {
                    if let effort = modelCfgObj["thinkingEffort"]?.stringValue, !effort.isEmpty {
                        plannerCfg["thinkingEffort"] = .string(effort)
                    }
                    if let persona = modelCfgObj["agentPersona"]?.stringValue,
                       !persona.isEmpty, persona != "Default" {
                        plannerCfg["agentPersona"] = .string(persona)
                    }
                    if let permPreset = modelCfgObj["permissionPreset"]?.stringValue, !permPreset.isEmpty {
                        plannerCfg["permissionPreset"] = .string(permPreset)
                    }
                }

                let reqModelObj = plannerCfg["requestedModel"]?.objectValue
                let requestedModel = reqModelObj?["model"]?.stringValue ?? reqModelObj?["alias"]?.stringValue ?? ""
                let isAlias = (reqModelObj?["alias"]?.stringValue != nil)
                let (defaultModel, validModels) = await ensureUpstreamModelCatalog()

                if !validModels.isEmpty && !validModels.contains(requestedModel) {
                    if let defaultModel, !defaultModel.isEmpty {
                        plannerCfg["requestedModel"] = .object(["model": .string(defaultModel)])
                        if plannerCfg["planModel"] != nil && defaultModel.hasPrefix("MODEL_") {
                            plannerCfg["planModel"] = .string(defaultModel)
                        }
                    } else {
                        plannerCfg.removeValue(forKey: "requestedModel")
                        plannerCfg.removeValue(forKey: "planModel")
                    }
                } else if validModels.isEmpty && !isAlias && (!requestedModel.hasPrefix("MODEL_") || requestedModel.contains(" ")) {
                    if let defaultModel, !defaultModel.isEmpty {
                        plannerCfg["requestedModel"] = .object(["model": .string(defaultModel)])
                    } else {
                        plannerCfg.removeValue(forKey: "requestedModel")
                        plannerCfg.removeValue(forKey: "planModel")
                    }
                }
                cascadeCfg["plannerConfig"] = .object(plannerCfg)
                clean["cascadeConfig"] = .object(cascadeCfg)
            }
            return clean

        case "HandleCascadeUserInteraction":
            guard var interaction = body["interaction"]?.objectValue else {
                return body
            }
            if var rc = interaction["runCommand"]?.objectValue {
                if rc["confirm"]?.boolValue == true && rc["faceIdVerified"]?.boolValue == false {
                    throw AntigravityRPCError.unauthorized("Face ID verification required before approving command")
                }
                rc.removeValue(forKey: "faceIdVerified")
                interaction["runCommand"] = .object(rc)
            }
            return ["interaction": .object(interaction)]

        default:
            return body
        }
    }

    // MARK: - Server-Streaming Envelope Subscription

    internal static func hasBase64TransferHeader(_ headers: [AnyHashable: Any]) -> Bool {
        headers.contains { key, val in
            let lowerKey = String(describing: key).lowercased()
            guard lowerKey == "x-goog-safety-encoding" || lowerKey == "content-transfer-encoding" else {
                return false
            }
            return String(describing: val).lowercased().contains("base64")
        }
    }

    internal static func extractConnectEndStreamError(from data: Data, decoder: JSONDecoder) -> String? {
        guard !data.isEmpty,
              let obj = try? decoder.decode([String: JSONValue].self, from: data) else {
            return nil
        }
        if let errObj = obj["error"]?.objectValue {
            let code = nonEmptyString(errObj["code"]?.stringValue)
            let msg = nonEmptyString(errObj["message"]?.stringValue)
            if code != nil || msg != nil {
                return [code, msg].compactMap { $0 }.joined(separator: ": ")
            }
        }
        if let code = nonEmptyString(obj["code"]?.stringValue),
           let msg = nonEmptyString(obj["message"]?.stringValue) {
            return "\(code): \(msg)"
        }
        return nil
    }

    /// Subscribes to a Connect-RPC server-streaming method (`JetboxSubscribeToSummaries`, `StreamCascadeReactiveUpdates`, etc.)
    public func subscribeEnvelopeStream(
        method: String,
        requestPayload: [String: JSONValue] = [:],
        instanceUuidOverride: String? = nil
    ) throws -> AsyncThrowingStream<[String: JSONValue], Error> {
        let rawJSON = requestPayload.isEmpty ? Data("{}".utf8) : try JSONEncoder().encode(requestPayload)
        let framedPayload = ConnectEnvelopeFrame(flags: [], payload: rawJSON).encode()

        if channel == .cloudRelay {
            var effectiveUuid = (instanceUuidOverride?.isEmpty == false) ? instanceUuidOverride : resolvedInstanceUuid
            if let candidate = effectiveUuid,
               !cachedRelayInstances.isEmpty,
               !cachedRelayInstances.contains(where: { $0.uuid == candidate && $0.status.isReachable }),
               let fallbackOnline = cachedRelayInstances.first(where: { $0.status.isReachable }) {
                let preferredResolved = resolvedInstanceUuid.flatMap { resUuid in
                    cachedRelayInstances.contains(where: { $0.uuid == resUuid && $0.status.isReachable }) ? resUuid : nil
                }
                effectiveUuid = preferredResolved ?? fallbackOnline.uuid
            }
            guard let targetUuid = effectiveUuid, !targetUuid.isEmpty else {
                return AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
            let originStr = SAPISIDHashGenerator.normalizeOrigin(relayOriginURL.absoluteString)
            guard var comps = URLComponents(string: "\(originStr)\(SAPISIDHashGenerator.apiServicePrefix)/StreamProxyCommand") else {
                throw AntigravityRPCError.invalidEndpoint
            }
            comps.queryItems = [URLQueryItem(name: "$unique", value: "\(method)-\(UUID().uuidString.prefix(8))")]
            guard let relayURL = comps.url else {
                throw AntigravityRPCError.invalidEndpoint
            }
            var relayRequest = URLRequest(url: relayURL)
            relayRequest.httpMethod = "POST"
            relayRequest.timeoutInterval = 300
            SAPISIDHashGenerator.applyApiServiceHeaders(
                to: &relayRequest,
                cookieHeader: sessionCookie ?? "",
                origin: originStr,
                authUser: authUser,
                isStreaming: true
            )
            relayRequest.httpBody = try CloudRelayJSPBCodec.encodeProxyCommandRequest(
                targetInstanceUuid: targetUuid,
                rpcPath: "\(Self.servicePrefix)/\(method)",
                payload: framedPayload,
                contentType: "application/connect+json",
                isStreaming: true
            )

            let session = self.streamingURLSession
            let immutableRelayReq = relayRequest
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let (bytes, response) = try await session.bytes(for: immutableRelayReq)
                        guard let http = response as? HTTPURLResponse else {
                            throw AntigravityRPCError.invalidEndpoint
                        }
                        if http.statusCode == 401 || http.statusCode == 403 {
                            throw AntigravityRPCError.unauthorized("StreamProxyCommand HTTP \(http.statusCode)")
                        }
                        guard (200..<300).contains(http.statusCode) else {
                            throw AntigravityRPCError.httpError(
                                statusCode: http.statusCode,
                                body: "StreamProxyCommand HTTP \(http.statusCode)"
                            )
                        }

                        let decoder = JSONDecoder()
                        var jspbStreamParser = CloudRelayJSPBStreamParser()
                        var connectParser = ConnectStreamParser()
                        var outerB64Decoder = StreamingBase64Decoder()
                        // 0 = auto-detect outer base64 vs raw UTF-8 JSPB, 1 = raw, 2 = base64
                        var outerMode: Int = Self.hasBase64TransferHeader(http.allHeaderFields) ? 2 : 0
                        var sniffBuffer: [UInt8] = []
                        var yieldedAny = false

                        func processStreamByte(_ decodedByte: UInt8) throws -> Bool {
                            guard let chunks = jspbStreamParser.feedByte(decodedByte) else {
                                return true
                            }
                            for rawChunk in chunks {
                                let chunkData = CloudRelayJSPBCodec.decompressPayloadIfNeeded(rawChunk)
                                if !connectParser.hasBufferedBytes,
                                   chunkData.first == UInt8(ascii: "{"),
                                   let obj = try? decoder.decode([String: JSONValue].self, from: chunkData) {
                                    yieldedAny = true
                                    continuation.yield(obj)
                                } else {
                                    for frame in connectParser.feed(chunkData) {
                                        let frameBytes = frame.isCompressed
                                            ? CloudRelayJSPBCodec.decompressPayloadIfNeeded(frame.payload)
                                            : frame.payload
                                        if frame.flags.contains(.endStream) {
                                            if let errMsg = Self.extractConnectEndStreamError(from: frameBytes, decoder: decoder) {
                                                throw AntigravityRPCError.httpError(statusCode: 400, body: errMsg)
                                            }
                                            continuation.finish()
                                            return false
                                        }
                                        if let obj = try? decoder.decode([String: JSONValue].self, from: frameBytes) {
                                            yieldedAny = true
                                            continuation.yield(obj)
                                        }
                                    }
                                }
                            }
                            return true
                        }

                        for try await byte in bytes {
                            if outerMode == 1 {
                                if !(try processStreamByte(byte)) { return }
                            } else if outerMode == 2 {
                                if let decodedChunk = outerB64Decoder.feedByte(byte) {
                                    for db in decodedChunk {
                                        if !(try processStreamByte(db)) { return }
                                    }
                                }
                            } else {
                                if sniffBuffer.isEmpty,
                                   byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
                                    || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\n") {
                                    continue
                                }
                                if sniffBuffer.isEmpty,
                                   byte == UInt8(ascii: "[") || byte == UInt8(ascii: "{")
                                    || byte == UInt8(ascii: ")") || byte == UInt8(ascii: "(")
                                    || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) {
                                    outerMode = 1
                                    if !(try processStreamByte(byte)) { return }
                                } else {
                                    sniffBuffer.append(byte)
                                    if sniffBuffer.count == 4 {
                                        let candidateStr = String(decoding: sniffBuffer, as: UTF8.self)
                                        if let decodedPrefix = CloudRelayJSPBCodec.decodeBase64Flexible(candidateStr),
                                           let firstByte = decodedPrefix.first,
                                           firstByte == UInt8(ascii: ")") || firstByte == UInt8(ascii: "[")
                                            || firstByte == UInt8(ascii: "{") || firstByte == UInt8(ascii: " ")
                                            || firstByte == UInt8(ascii: "\n") {
                                            outerMode = 2
                                            for db in decodedPrefix {
                                                if !(try processStreamByte(db)) { return }
                                            }
                                        } else {
                                            outerMode = 1
                                            for rb in sniffBuffer {
                                                if !(try processStreamByte(rb)) { return }
                                            }
                                        }
                                        sniffBuffer.removeAll(keepingCapacity: false)
                                    }
                                }
                            }
                        }

                        if outerMode == 2 {
                            let trailing = outerB64Decoder.flush()
                            for db in trailing {
                                if !(try processStreamByte(db)) { return }
                            }
                        } else if !sniffBuffer.isEmpty {
                            for rb in sniffBuffer {
                                if !(try processStreamByte(rb)) { return }
                            }
                        }

                        if !yieldedAny, let boqErr = jspbStreamParser.lastErrorTrailer {
                            throw AntigravityRPCError.httpError(statusCode: 502, body: boqErr)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        let url = endpointURL.appendingPathComponent("\(Self.servicePrefix)/\(method)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/connect+json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        applyAuthHeaders(to: &request)
        request.httpBody = framedPayload

        let session = self.streamingURLSession
        let immutableRequest = request
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: immutableRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw AntigravityRPCError.invalidEndpoint
                    }
                    if http.statusCode == 401 || http.statusCode == 403 {
                        throw AntigravityRPCError.unauthorized("Stream HTTP \(http.statusCode)")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw AntigravityRPCError.httpError(
                            statusCode: http.statusCode,
                            body: "Stream HTTP \(http.statusCode)"
                        )
                    }
                    var parser = ConnectStreamParser()
                    let decoder = JSONDecoder()
                    for try await byte in bytes {
                        if let frame = parser.feedByte(byte) {
                            let frameBytes = frame.isCompressed
                                ? CloudRelayJSPBCodec.decompressPayloadIfNeeded(frame.payload)
                                : frame.payload
                            if frame.flags.contains(.endStream) {
                                if let errMsg = Self.extractConnectEndStreamError(from: frameBytes, decoder: decoder) {
                                    throw AntigravityRPCError.httpError(statusCode: 400, body: errMsg)
                                }
                                continuation.finish()
                                return
                            }
                            if let obj = try? decoder.decode([String: JSONValue].self, from: frameBytes) {
                                continuation.yield(obj)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    internal func applyAuthHeaders(to request: inout URLRequest) {
        if let csrfToken, !csrfToken.isEmpty {
            request.setValue(csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        }
        if let sessionCookie, !sessionCookie.isEmpty {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
    }
}
