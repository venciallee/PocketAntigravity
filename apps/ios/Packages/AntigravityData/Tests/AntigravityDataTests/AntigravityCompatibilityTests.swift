import XCTest
@testable import AntigravityData

final class AntigravityCompatibilityTests: XCTestCase {

    // MARK: - Protobuf Test Encoders

    private func encodeVarintField(_ fieldNumber: Int, value: UInt64) -> Data {
        var out = Data()
        let tag = UInt64((fieldNumber << 3) | 0)
        out.append(contentsOf: ProtobufStepCodec.encodeVarint(tag))
        out.append(contentsOf: ProtobufStepCodec.encodeVarint(value))
        return out
    }

    private func encodeLengthField(_ fieldNumber: Int, payload: Data) -> Data {
        var out = Data()
        let tag = UInt64((fieldNumber << 3) | 2)
        out.append(contentsOf: ProtobufStepCodec.encodeVarint(tag))
        out.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(payload.count)))
        out.append(payload)
        return out
    }

    private func encodeStringField(_ fieldNumber: Int, string: String) -> Data {
        encodeLengthField(fieldNumber, payload: Data(string.utf8))
    }

    private func makeMockSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        CompatMockURLProtocol.storage.setHandler(handler)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CompatMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        CompatMockURLProtocol.storage.setHandler(nil)
        super.tearDown()
    }

    // MARK: - 1. SemVer, Header Parsing & HostCapabilityProfile

    func testSemVerParsingComparisonAndVersionResetInvalidatesNegativeCache() {
        let v231 = AntigravitySemVer.parse("v2.31.4")
        let v232 = AntigravitySemVer.parse("2.32.0")
        let v233Beta = AntigravitySemVer.parse("v2.33.0-beta.1")
        let v233 = AntigravitySemVer.parse("v2.33.0")
        let v300 = AntigravitySemVer.parse("3.0.0")

        XCTAssertNotNil(v231)
        XCTAssertNotNil(v232)
        XCTAssertNotNil(v233Beta)
        XCTAssertNotNil(v233)
        XCTAssertNotNil(v300)
        XCTAssertNil(AntigravitySemVer.parse(""))
        XCTAssertNil(AntigravitySemVer.parse("unknown"))

        XCTAssertTrue(v231! < v232!)
        XCTAssertTrue(v232! < v233Beta!)
        XCTAssertTrue(v233Beta! < v233!)
        XCTAssertTrue(v233! < v300!)

        var profile = HostCapabilityProfile(hostKey: "host-a", reportedVersion: "v2.31.0")
        profile.recordMethodUnsupported("GitCommit")
        XCTAssertEqual(profile.supportState(for: .gitVcs), .unsupported)
        XCTAssertTrue(profile.isMethodKnownUnsupported("GitCommit"))
        XCTAssertTrue(profile.userFacingUnsupportedMessage(for: .gitVcs).contains("v2.31.0"))

        // Bridge polyfill overrides negative cache cleanly
        profile.recordBridgeCapabilities(["GitCommit", "GetTurnDiff"])
        XCTAssertTrue(profile.isCompanionBridge)
        XCTAssertFalse(profile.isMethodKnownUnsupported("GitCommit"))
        XCTAssertEqual(profile.supportState(for: .gitVcs), .supported)

        // Upgrading Desktop version clears stale negative cache entries
        profile.recordMethodUnsupported("SendSideQuestion")
        XCTAssertTrue(profile.isMethodKnownUnsupported("SendSideQuestion"))
        profile.updateReportedVersion("v2.33.0")
        XCTAssertFalse(profile.isMethodKnownUnsupported("SendSideQuestion"))
        XCTAssertEqual(profile.supportState(for: .sideQuestion), .unknown)
    }

    // MARK: - 2. Recursive Field Stripping, Rich Attachment Folding & Enum Downgrade

    func testRecursiveFieldStripFoldsRichAttachmentsAndDowngradesEnums() {
        let payload: [String: JSONValue] = [
            "cascadeId": .string("cas-compat"),
            "items": .array([
                .object(["text": .string("Inspect this")]),
                .object([
                    "item": .object([
                        "codeQuote": .object([
                            "label": .string("ratelimit.go:L22-L26"),
                            "snippet": .string("const ttl = cfg.BucketTTL")
                        ])
                    ])
                ])
            ]),
            "cascadeConfig": .object([
                "plannerConfig": .object([
                    "thinkingEffort": .string("XHIGH"),
                    "permissionPreset": .string("PERMISSION_PRESET_DEFAULT")
                ])
            ])
        ]

        // 1. Strip nested `codeQuote` -> folds into readable plain text item instead of dropping context
        let (afterQuoteStrip, removedQuote) = ProtocolCompatibilityEngine.recursivelyRemoveField("codeQuote", from: payload)
        XCTAssertTrue(removedQuote)
        let foldedText = afterQuoteStrip["items"]?.arrayValue?[1].objectValue?["text"]?.stringValue ?? ""
        XCTAssertTrue(foldedText.contains("ratelimit.go:L22-L26"))
        XCTAssertTrue(foldedText.contains("cfg.BucketTTL"))

        // 1b. JSON-wrapped Connect-RPC error bodies with escaped quotes (`\"...\"`)
        XCTAssertEqual(
            ProtocolCompatibilityEngine.extractUnknownProtoFieldName(
                from: "{\"code\":\"invalid_argument\",\"message\":\"unknown field \\\"permissionPreset\\\"\"}"
            ),
            "permissionPreset"
        )
        XCTAssertEqual(
            ProtocolCompatibilityEngine.extractInvalidEnumValue(
                from: "{\"code\":\"invalid_argument\",\"message\":\"invalid value for enum type ThinkingEffort: \\\"XHIGH\\\"\"}"
            ),
            "XHIGH"
        )

        // 2. Enum extraction & downgrade (`XHIGH` -> `HIGH`)
        let invalidEnum = ProtocolCompatibilityEngine.extractInvalidEnumValue(
            from: "invalid_argument: invalid value for enum type exa.cortex_pb.ThinkingEffort: \"XHIGH\""
        )
        XCTAssertEqual(invalidEnum, "XHIGH")
        let replacement = ProtocolCompatibilityEngine.downgradedEnumReplacement(for: "XHIGH")
        XCTAssertEqual(replacement, "HIGH")

        let (downgraded, didReplace) = ProtocolCompatibilityEngine.recursivelyReplaceEnumValue(
            "XHIGH",
            with: "HIGH",
            in: afterQuoteStrip
        )
        XCTAssertTrue(didReplace)
        let effort = downgraded["cascadeConfig"]?.objectValue?["plannerConfig"]?.objectValue?["thinkingEffort"]?.stringValue
        XCTAssertEqual(effort, "HIGH")
    }

    // MARK: - 3. Direction 1: Direct LAN Self-Healing Retry, Negative Cache & Bridge Header Discovery

    func testDirectLANSelfHealsNestedUnknownFieldsAndEnumsAndCachesDowngrades() async throws {
        let counter = CompatRequestCounter()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            let bodyObj = (try? JSONDecoder().decode([String: JSONValue].self, from: bodyData)) ?? [:]
            counter.record(path: path)

            if path.hasSuffix("/SendUserCascadeMessage") {
                let planner = bodyObj["cascadeConfig"]?.objectValue?["plannerConfig"]?.objectValue
                if planner?["permissionPreset"] != nil {
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, Data("{\"code\":\"invalid_argument\",\"message\":\"unknown field \\\"permissionPreset\\\"\"}".utf8))
                }
                if planner?["thinkingEffort"]?.stringValue == "XHIGH" {
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, Data("{\"code\":\"invalid_argument\",\"message\":\"invalid value for enum type ThinkingEffort: \\\"XHIGH\\\"\"}".utf8))
                }
                let resp = HTTPURLResponse(
                    url: req.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "X-Antigravity-Desktop-Version": "v2.31.2",
                        "X-Antigravity-Bridge-Capabilities": "GetTurnDiff,GitCommit"
                    ]
                )!
                return (resp, Data("{\"ok\":true}".utf8))
            }

            if path.hasSuffix("/SendSideQuestion") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data("{\"code\":\"unimplemented\",\"message\":\"unknown method SendSideQuestion\"}".utf8))
            }

            if path.hasSuffix("/RevertConversationToStep") {
                // Transient 503 must NOT poison negative capability cache
                let resp = HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data("{\"code\":\"unavailable\",\"message\":\"Desktop temporarily offline\"}".utf8))
            }

            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "direct-old-mac",
            hostname: "Old MacBook",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18787")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        // First call heals unknown `permissionPreset` AND invalid enum `XHIGH` -> `HIGH` in 3 wire attempts
        try await client.sendUserCascadeMessage(
            cascadeId: "cas-1",
            message: "Hello older PC",
            modelId: "MODEL_PLACEHOLDER_M37",
            effort: .extra,
            mode: .planning
        )
        XCTAssertEqual(counter.count(forSuffix: "/SendUserCascadeMessage"), 3)

        // Second call reuses learned downgrades -> succeeds on the VERY FIRST attempt (+1 total = 4)
        try await client.sendUserCascadeMessage(
            cascadeId: "cas-1",
            message: "Second turn",
            modelId: "MODEL_PLACEHOLDER_M37",
            effort: .extra,
            mode: .planning
        )
        XCTAssertEqual(counter.count(forSuffix: "/SendUserCascadeMessage"), 4)

        let profile = await client.capabilityProfile()
        XCTAssertEqual(profile.reportedVersion, "v2.31.2")
        XCTAssertTrue(profile.isCompanionBridge)
        XCTAssertTrue(profile.bridgeSupportedMethods.contains("GitCommit"))
        XCTAssertEqual(profile.supportState(for: .gitVcs), .supported)

        // 404 method is negatively cached -> second call short-circuits with ZERO additional HTTP traffic
        do {
            _ = try await client.sendSideQuestion(cascadeId: "cas-1", question: "test", threadId: "t1")
            XCTFail("Expected 404 unimplemented")
        } catch {
            XCTAssertTrue(ProtocolCompatibilityEngine.isMethodUnimplementedError(error))
        }
        XCTAssertEqual(counter.count(forSuffix: "/SendSideQuestion"), 1)

        do {
            _ = try await client.sendSideQuestion(cascadeId: "cas-1", question: "test 2", threadId: "t1")
            XCTFail("Expected cached 501 unimplemented")
        } catch {
            XCTAssertTrue(ProtocolCompatibilityEngine.isMethodUnimplementedError(error))
        }
        XCTAssertEqual(counter.count(forSuffix: "/SendSideQuestion"), 1, "Cached unsupported RPC must not hit network again")

        // 503 offline error must NOT be cached as unsupported
        do {
            try await client.revertConversationToStep(cascadeId: "cas-1", stepIndex: 1)
            XCTFail("Expected 503")
        } catch {}
        let updatedProfile = await client.capabilityProfile()
        XCTAssertFalse(updatedProfile.isMethodKnownUnsupported("RevertConversationToStep"))
    }

    func testDirectLANPinAndDeleteFallbackToUpstreamAnnotationMethods() async throws {
        let counter = CompatRequestCounter()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            counter.record(path: path)
            if path.hasSuffix("/PinCascade") || path.hasSuffix("/DeleteCascade") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data("{\"code\":\"unimplemented\",\"message\":\"method not found\"}".utf8))
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "direct-native-ls",
            hostname: "Native Desktop",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18788")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        try await client.pinCascade(cascadeId: "cas-pin", isPinned: true)
        try await client.deleteCascade(cascadeId: "cas-del")

        XCTAssertEqual(counter.count(forSuffix: "/UpdateConversationAnnotations"), 1)
        XCTAssertEqual(counter.count(forSuffix: "/DeleteCascadeTrajectory"), 1)
    }

    // MARK: - 4. Honest Write-Operation Rollback on Live Older PC (Zero Fake Success)

    @MainActor
    func testLiveWriteOperationsRollBackAndShowHonestNoticeOn404Unimplemented() async throws {
        let session = makeMockSession { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{\"code\":\"unimplemented\",\"message\":\"unknown method\"}".utf8))
        }
        let host = RemoteHostInstance(
            instanceId: "old-desktop-uuid",
            hostname: "Legacy Mac",
            version: "v2.31.0",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18789")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        let store = AntigravitySessionStore.makeESDDVerificationStore()
        store.isVerificationMode = false
        store.hasPairedBackend = true
        store.isLiveBackendConnected = true
        store.activeHost = host
        store.rpcClient = client
        store.activeTurnDiffs = [
            FilePatchDiff(turnNumber: 1, filePath: "main.go", additions: 3, deletions: 1, isStaged: false, lines: [])
        ]
        store.gitCommitDraft.message = "feat: real commit"

        // 1. Git Commit must return nil and MUST NOT wipe activeTurnDiffs or fabricate a commitSha
        let commitResult = await store.commitDiffChanges()
        XCTAssertNil(commitResult)
        XCTAssertEqual(store.activeTurnDiffs.count, 1)
        XCTAssertEqual(store.gitCommitDraft.message, "feat: real commit")
        XCTAssertFalse(store.isCapabilitySupportedOnActiveHost(.gitVcs))
        XCTAssertNotNil(store.compatibilityNoticeText)

        // 2. Stage & Discard must roll back cleanly
        store.toggleStageDiffFile(at: 0)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(store.activeTurnDiffs[0].isStaged)

        store.discardDiffFile(at: 0)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(store.activeTurnDiffs.count, 1)

        // 3. Revert to Step must restore original steps
        let originalSteps = store.activeSteps
        store.revertConversationToStep(0)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(store.activeSteps.count, originalSteps.count)

        // 4. /btw Side Question must report honest warning instead of fake local analysis
        store.sendSideQuestion("What does Allow do?")
        try await Task.sleep(nanoseconds: 150_000_000)
        let latestReply = store.sideQuestionThread.latestAssistantAnswer ?? ""
        XCTAssertTrue(latestReply.contains("⚠️"))
        XCTAssertFalse(latestReply.contains("Read-only side analysis"))
    }

    // MARK: - 5. Direction 2: Forward Compatibility (Newer PC -> Older Mobile)

    func testUnknownFutureJSONAndProtobufStepsStayVisibleWithFallbackSummary() throws {
        // 1. Unknown JSON step type
        let futureJSON: JSONValue = .object([
            "stepIndex": .int(12),
            "type": .string("CORTEX_STEP_TYPE_FUTURE_CANVAS_RENDER"),
            "status": .string("CORTEX_STEP_STATUS_DONE"),
            "futureCanvasRender": .object([
                "title": .string("Interactive Architecture Map"),
                "summary": .string("Rendered 14 microservices")
            ])
        ])
        let jsonStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(futureJSON, cascadeId: "cas-fwd", fallbackIndex: 12)
        )
        XCTAssertEqual(jsonStep.type, .unspecified)
        XCTAssertEqual(jsonStep.rawTypeName, "CORTEX_STEP_TYPE_FUTURE_CANVAS_RENDER")
        XCTAssertEqual(jsonStep.fallbackSummary, "Interactive Architecture Map")
        XCTAssertTrue(jsonStep.isUnrecognizedForwardStep)
        XCTAssertTrue(jsonStep.hasRenderableChatContent)

        // 2. Unknown Binary Protobuf step type (rawType 199 + unknown submessage at field 199)
        var futureSubmsg = Data()
        futureSubmsg.append(encodeStringField(1, string: "Quantum Debugger Snapshot"))
        var stepBytes = Data()
        stepBytes.append(encodeVarintField(1, value: 199)) // Unknown CortexStepType 199
        stepBytes.append(encodeVarintField(4, value: 3))   // DONE
        stepBytes.append(encodeLengthField(199, payload: futureSubmsg))

        let responseBytes = encodeLengthField(1, payload: stepBytes)
        let protoSteps = ProtobufStepCodec.decodeStepsResponse(responseBytes, cascadeId: "cas-fwd", startingIndex: 5)
        XCTAssertEqual(protoSteps.count, 1)
        XCTAssertEqual(protoSteps[0].type, .unspecified)
        XCTAssertEqual(protoSteps[0].rawTypeName, "STEP_TYPE_199")
        XCTAssertEqual(protoSteps[0].fallbackSummary, "Quantum Debugger Snapshot")
        XCTAssertTrue(protoSteps[0].isUnrecognizedForwardStep)
        XCTAssertTrue(protoSteps[0].hasRenderableChatContent)

        // 3. Unknown JSON step with 2-level nested payload still extracts readable summary
        let deepNestedJSON: JSONValue = .object([
            "stepIndex": .int(13),
            "type": .string("CORTEX_STEP_TYPE_FUTURE_DEEP_TOOL"),
            "status": .string("CORTEX_STEP_STATUS_DONE"),
            "futureDeepTool": .object([
                "enabled": .bool(true),
                "details": .object([
                    "message": .string("Deep nested payload rendered")
                ])
            ])
        ])
        let deepStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(deepNestedJSON, cascadeId: "cas-fwd", fallbackIndex: 13)
        )
        XCTAssertEqual(deepStep.type, .unspecified)
        XCTAssertTrue(deepStep.isUnrecognizedForwardStep)
        XCTAssertEqual(deepStep.fallbackSummary, "Deep nested payload rendered")
    }

    @MainActor
    func testErrorMessageStepDecodesNestedJsonProtobufLegacyCacheAndReconcilesStreaming() throws {
        // 1. Upstream JSON CORTEX_STEP_TYPE_ERROR_MESSAGE with nested errorMessage.error and status DONE
        let nestedErrJSON: JSONValue = .object([
            "stepIndex": .int(1),
            "type": .string("CORTEX_STEP_TYPE_ERROR_MESSAGE"),
            "status": .string("CORTEX_STEP_STATUS_DONE"),
            "errorMessage": .object([
                "shouldShowModel": .bool(true),
                "error": .object([
                    "userErrorMessage": .string("Model quota reached for Gemini 4 Neon."),
                    "shortError": .string("RESOURCE_EXHAUSTED"),
                    "fullError": .string("rpc error: code = ResourceExhausted desc = quota exhausted"),
                    "httpStatusCode": .int(429)
                ])
            ])
        ])
        let errStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(nestedErrJSON, cascadeId: "cas-err", fallbackIndex: 1)
        )
        XCTAssertEqual(errStep.type, .errorMessage)
        XCTAssertEqual(errStep.status, .error)
        XCTAssertTrue(errStep.isErrorMessageStep)
        XCTAssertFalse(errStep.isUnrecognizedForwardStep)
        XCTAssertTrue(errStep.hasRenderableChatContent)
        XCTAssertEqual(errStep.errorMessage?.message, "Model quota reached for Gemini 4 Neon.")
        XCTAssertEqual(errStep.errorMessage?.detail, "rpc error: code = ResourceExhausted desc = quota exhausted")
        XCTAssertEqual(errStep.errorMessage?.errorCode, "HTTP 429")

        // 2. Empty errorMessage payload still decodes as .errorMessage + .error (never UnknownStepFallbackCard)
        let emptyErrJSON: JSONValue = .object([
            "stepIndex": .int(2),
            "type": .string("CORTEX_STEP_TYPE_ERROR_MESSAGE"),
            "status": .string("CORTEX_STEP_STATUS_DONE"),
            "errorMessage": .object([:])
        ])
        let emptyErrStep = try XCTUnwrap(
            AntigravityRPCClient.decodeJSONStep(emptyErrJSON, cascadeId: "cas-err", fallbackIndex: 2)
        )
        XCTAssertEqual(emptyErrStep.type, .errorMessage)
        XCTAssertEqual(emptyErrStep.status, .error)
        XCTAssertTrue(emptyErrStep.isErrorMessageStep)
        XCTAssertFalse(emptyErrStep.isUnrecognizedForwardStep)
        XCTAssertTrue(emptyErrStep.hasRenderableChatContent)
        XCTAssertNotNil(emptyErrStep.errorMessage)

        // 3. Legacy offline-cached step from older build (type = .unspecified, rawTypeName = CORTEX_STEP_TYPE_ERROR_MESSAGE)
        let legacyCached = CascadeStep(
            cascadeId: "cas-err",
            stepIndex: 3,
            type: .unspecified,
            status: .done,
            rawTypeName: "CORTEX_STEP_TYPE_ERROR_MESSAGE"
        )
        XCTAssertTrue(legacyCached.isErrorMessageStep)
        XCTAssertFalse(legacyCached.isUnrecognizedForwardStep)
        XCTAssertTrue(legacyCached.hasRenderableChatContent)

        // 4. Binary Protobuf field 24 (CortexStepErrorMessage) with nested CortexErrorDetails submessage at field 1
        var innerDetails = Data()
        innerDetails.append(encodeStringField(1, string: "Upstream model timed out"))
        innerDetails.append(encodeStringField(2, string: "DEADLINE_EXCEEDED after 60s"))
        let errSubmsg = encodeLengthField(1, payload: innerDetails)
        var protoStepBytes = Data()
        protoStepBytes.append(encodeVarintField(1, value: 17)) // CORTEX_STEP_TYPE_ERROR_MESSAGE
        protoStepBytes.append(encodeVarintField(4, value: 3))  // DONE
        protoStepBytes.append(encodeLengthField(24, payload: errSubmsg))
        let decodedProto = ProtobufStepCodec.decodeStepsResponse(
            encodeLengthField(1, payload: protoStepBytes),
            cascadeId: "cas-err",
            startingIndex: 4
        )
        XCTAssertEqual(decodedProto.count, 1)
        XCTAssertEqual(decodedProto[0].type, .errorMessage)
        XCTAssertEqual(decodedProto[0].status, .error)
        XCTAssertTrue(decodedProto[0].isErrorMessageStep)
        XCTAssertEqual(decodedProto[0].errorMessage?.message, "Upstream model timed out")
        XCTAssertEqual(decodedProto[0].errorMessage?.detail, "DEADLINE_EXCEEDED after 60s")

        // 5. Summary streaming reconciliation terminates cleanly to .error when last step is ERROR_MESSAGE
        let userStep = CascadeStep(cascadeId: "cas-err", stepIndex: 0, type: .userInput, status: .done, userInput: "hi")
        let reconciled = AntigravitySessionStore.reconcileSummaryStreamingStatus(
            currentStatus: .inProgress,
            remoteSteps: [userStep, errStep],
            withinOptimisticSendWindow: true
        )
        XCTAssertEqual(reconciled.status, .error)
        XCTAssertFalse(reconciled.stillActive)
    }

    func testUnknownProtobufRequestedInteractionGuardsUnsafeApproveAndRepairsViaJSON() async throws {
        // Binary step with unknown RequestedInteraction field 99
        var unknownSpec = Data()
        unknownSpec.append(encodeStringField(1, string: "Deploy cluster prod-us-east1"))
        let reqInteractionBytes = encodeLengthField(99, payload: unknownSpec)

        var stepBytes = Data()
        stepBytes.append(encodeVarintField(1, value: 82)) // NOTIFY_USER
        stepBytes.append(encodeVarintField(4, value: 9))  // WAITING
        stepBytes.append(encodeLengthField(56, payload: reqInteractionBytes))
        let protoRespBytes = encodeLengthField(1, payload: stepBytes)

        // 1. Pure Protobuf decode flags `isUnrecognizedWireMember = true` and refuses unsafe payload fabrication
        let decodedDirect = ProtobufStepCodec.decodeStepsResponse(protoRespBytes, cascadeId: "cas-proto-fwd", startingIndex: 604)
        XCTAssertEqual(decodedDirect.count, 1)
        let req = try XCTUnwrap(decodedDirect[0].requestedInteraction)
        XCTAssertTrue(req.isUnrecognizedWireMember)
        XCTAssertEqual(req.rawWireFieldNumber, 99)
        XCTAssertNil(req.rawMemberKey)
        XCTAssertEqual(req.rawSummary, "Deploy cluster prod-us-east1")
        XCTAssertNil(InteractionBuilder.buildPayload(step: decodedDirect[0], decision: .allowOnce))
        XCTAssertFalse(InteractionBuilder.canSafeAutoAccept(step: decodedDirect[0], allowedWorkspaceRoots: ["/"]))

        // 2. When fetched through AntigravityRPCClient, targeted JSON repair recovers exact `rawMemberKey`
        let session = makeMockSession { req in
            let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            if contentType.contains("application/proto") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, protoRespBytes)
            }
            // Targeted JSON repair response for stepOffset 0 (startingIndex default 0 in fetchTrajectoryStepsProtobuf)
            let repairedJSON = """
            {
              "steps": [
                {
                  "stepIndex": 0,
                  "type": "CORTEX_STEP_TYPE_NOTIFY_USER",
                  "status": "CORTEX_STEP_STATUS_WAITING",
                  "requestedInteraction": {
                    "futureClusterDeploy": {
                      "summary": "Deploy cluster prod-us-east1"
                    }
                  }
                }
              ]
            }
            """
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data(repairedJSON.utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "new-desktop-proto",
            hostname: "Future Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18790")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)
        let fetched = try await client.fetchTrajectoryStepsProtobuf(
            cascadeId: "cas-proto-fwd",
            startIndex: 0,
            endIndex: 605
        )
        XCTAssertEqual(fetched.count, 1)
        let repairedReq = try XCTUnwrap(fetched[0].requestedInteraction)
        XCTAssertFalse(repairedReq.isUnrecognizedWireMember)
        XCTAssertEqual(repairedReq.rawMemberKey, "futureClusterDeploy")

        let safePayload = try XCTUnwrap(InteractionBuilder.buildPayload(step: fetched[0], decision: .allowOnce))
        XCTAssertEqual(safePayload.rawMemberKey, "futureClusterDeploy")
    }

    func testUnknownFutureArtifactKindDecodesSafelyWithoutCrashing() async throws {
        // 1. Direct Codable decoding of unknown ArtifactKind string
        let futureSnapshotJSON = """
        {
          "artifactPath": "/brain/scene.agcanvas",
          "title": "3D Mesh Scene",
          "summary": "Generated mesh",
          "kind": "future3DCanvas",
          "content": "binary-placeholder",
          "requestFeedback": false,
          "userFacing": true,
          "version": 1
        }
        """
        let decoded = try JSONDecoder().decode(ArtifactSnapshot.self, from: Data(futureSnapshotJSON.utf8))
        XCTAssertEqual(decoded.kind, .unsupportedAsset)

        // 2. RPC `GetArtifactSnapshots` maps unknown kind & unknown extension to `.unsupportedAsset` with `rawKindName`
        let session = makeMockSession { req in
            let body = """
            {
              "artifacts": [
                {
                  "artifactPath": "/brain/deck.pptx",
                  "title": "Launch Deck",
                  "summary": "Slides"
                },
                {
                  "artifactPath": "/brain/model.glb",
                  "title": "Mesh",
                  "kind": "future3DMesh"
                }
              ]
            }
            """
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data(body.utf8))
        }
        let host = RemoteHostInstance(
            instanceId: "future-artifacts",
            hostname: "Future Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18791")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)
        let artifacts = try await client.getArtifactSnapshots(cascadeId: "cas-art")
        XCTAssertEqual(artifacts.count, 2)
        XCTAssertEqual(artifacts[0].kind, .unsupportedAsset)
        XCTAssertEqual(artifacts[0].rawKindName, "PPTX")
        XCTAssertEqual(artifacts[1].kind, .unsupportedAsset)
        XCTAssertEqual(artifacts[1].rawKindName, "future3DMesh")
    }

    // MARK: - 6. Automated Compatibility Guardrails (ResilientStringEnum, Unknown-Enum Strip, Inverse Allowlist, Live Write Helper)

    func testResilientStringEnumsDecodeUnknownFutureStringsWithoutThrowing() throws {
        struct Box<T: Decodable>: Decodable { let v: T }
        func decodeUnknown<T: ResilientStringEnum>(_ type: T.Type) throws -> T {
            let data = Data("{\"v\":\"BRAND_NEW_FUTURE_ENUM_V99\"}".utf8)
            return try JSONDecoder().decode(Box<T>.self, from: data).v
        }

        XCTAssertEqual(try decodeUnknown(ArtifactKind.self), .unsupportedAsset)
        XCTAssertEqual(try decodeUnknown(ThinkingEffortLevel.self), .high)
        XCTAssertEqual(try decodeUnknown(CascadeExecutionMode.self), .planning)
        XCTAssertEqual(try decodeUnknown(AgentPermissionPreset.self), .auto)
        XCTAssertEqual(try decodeUnknown(RequestedInteraction.MemberKind.self), .approvalInteraction)
        XCTAssertEqual(try decodeUnknown(TaskChecklistStatus.self), .pending)
        XCTAssertEqual(try decodeUnknown(GitFileStatusLetter.self), .modified)
        XCTAssertEqual(try decodeUnknown(GitHubPullRequestInfo.PRState.self), .open)
        XCTAssertEqual(try decodeUnknown(McpServerStatusItem.ConnectionState.self), .stopped)
        XCTAssertEqual(try decodeUnknown(CapabilitySupportState.self), .unknown)
        XCTAssertEqual(try decodeUnknown(SemanticIcon.self), .embedArtifact)
        XCTAssertEqual(try decodeUnknown(PrimaryTab.self), .agents)
        XCTAssertEqual(try decodeUnknown(AppThemePreset.self), .obsidian)
        XCTAssertEqual(try decodeUnknown(AppAppearanceMode.self), .system)
    }

    func testUnknownFutureEnumTriggersSecondaryKeyStripFallbackAndCaches() async throws {
        let counter = CompatRequestCounter()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            let bodyObj = (try? JSONDecoder().decode([String: JSONValue].self, from: bodyData)) ?? [:]
            counter.record(path: path)

            if path.hasSuffix("/SendUserCascadeMessage") {
                let planner = bodyObj["cascadeConfig"]?.objectValue?["plannerConfig"]?.objectValue
                if planner?["experimentalEffort"]?.stringValue == "THINKING_EFFORT_ULTRA" {
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, Data("{\"code\":\"invalid_argument\",\"message\":\"invalid value for enum type ThinkingEffort: \\\"THINKING_EFFORT_ULTRA\\\"\"}".utf8))
                }
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data("{\"ok\":true}".utf8))
            }

            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "legacy-unknown-enum-strip",
            hostname: "Legacy Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18792")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        let payload: [String: JSONValue] = [
            "cascadeId": .string("cas-ultra"),
            "cascadeConfig": .object([
                "plannerConfig": .object([
                    "experimentalEffort": .string("THINKING_EFFORT_ULTRA")
                ])
            ])
        ]

        // 1st call: 400 on unmapped enum -> strips `experimentalEffort` key -> succeeds on attempt 2
        _ = try await client.callUnaryJSON(method: "SendUserCascadeMessage", body: payload)
        XCTAssertEqual(counter.count(forSuffix: "/SendUserCascadeMessage"), 2)

        // 2nd call: cached stripped key is pre-applied -> succeeds on attempt 1 (total 3)
        _ = try await client.callUnaryJSON(method: "SendUserCascadeMessage", body: payload)
        XCTAssertEqual(counter.count(forSuffix: "/SendUserCascadeMessage"), 3)

        let profile = await client.capabilityProfile()
        XCTAssertTrue(profile.strippedFieldsByMethod["SendUserCascadeMessage"]?.contains("experimentalEffort") == true)
    }

    func testInverseAllowlistCachesUnregisteredFutureOptionalRPCButNeverCoreBaseline() async throws {
        let counter = CompatRequestCounter()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            counter.record(path: path)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{\"code\":\"unimplemented\",\"message\":\"unknown method\"}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "legacy-inverse-allowlist",
            hostname: "Legacy Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18793")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        // 1. Future unregistered optional RPC (`CreateWorktree`) IS negatively cached automatically
        XCTAssertTrue(HostCapability.shouldNegativeCacheOnUnimplemented("CreateWorktree"))
        do { _ = try await client.callUnaryJSON(method: "CreateWorktree", body: [:]) } catch {}
        do { _ = try await client.callUnaryJSON(method: "CreateWorktree", body: [:]) } catch {}
        XCTAssertEqual(counter.count(forSuffix: "/CreateWorktree"), 1, "Unregistered optional RPC must short-circuit on 2nd call")

        // 2. Core baseline probe (`GetWorkspaceInfos`) is NEVER permanently cached as unsupported
        XCTAssertFalse(HostCapability.shouldNegativeCacheOnUnimplemented("GetWorkspaceInfos"))
        do { _ = try await client.callUnaryJSON(method: "GetWorkspaceInfos", body: [:]) } catch {}
        do { _ = try await client.callUnaryJSON(method: "GetWorkspaceInfos", body: [:]) } catch {}
        XCTAssertEqual(counter.count(forSuffix: "/GetWorkspaceInfos"), 2, "Core baseline RPC must not be permanently cached")
    }

    @MainActor
    func testPerformLiveCapabilityWriteTransactionOfflineSuccessAndRollback() async {
        // 1. Offline ESDD mode passes through cleanly without remote RPC
        let offlineStore = AntigravitySessionStore.makeESDDVerificationStore()
        var value = "initial"
        var rolledBack = false
        let offlineRes = await offlineStore.performLiveCapabilityWrite(
            capability: .gitVcs,
            actionLabel: "Test write",
            optimistic: { value = "optimistic" },
            offlineResult: { "offline-ok" },
            remote: { _ in "remote-ok" },
            onSuccess: { res in value = res },
            rollback: { rolledBack = true }
        )
        XCTAssertEqual(offlineRes, "offline-ok")
        XCTAssertEqual(value, "offline-ok")
        XCTAssertFalse(rolledBack)

        // 2. Live host returning 404 rolls back automatically & posts honest compatibility notice
        let session = makeMockSession { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{\"code\":\"unimplemented\",\"message\":\"unknown method GitPush\"}".utf8))
        }
        let host = RemoteHostInstance(
            instanceId: "live-tx-rollback",
            hostname: "Old Mac",
            version: "v2.31.0",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18794")!,
            isOnline: true
        )
        let liveStore = AntigravitySessionStore.makeESDDVerificationStore()
        liveStore.isVerificationMode = false
        liveStore.hasPairedBackend = true
        liveStore.isLiveBackendConnected = true
        liveStore.activeHost = host
        liveStore.rpcClient = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        var stateFlag = false
        let liveRes: Bool? = await liveStore.performLiveCapabilityWrite(
            capability: .gitVcs,
            actionLabel: "Git push",
            optimistic: { stateFlag = true },
            offlineResult: { true },
            remote: { client in
                try await client.gitPushBranch(cascadeId: "cas-1", branchName: "main")
            },
            rollback: { stateFlag = false }
        )
        XCTAssertNil(liveRes)
        XCTAssertFalse(stateFlag, "Failed live capability write must invoke rollback")
        XCTAssertNotNil(liveStore.compatibilityNoticeText)
        XCTAssertFalse(liveStore.isCapabilitySupportedOnActiveHost(.gitVcs))
    }

    // MARK: - 7. Binary-First Adaptive Trajectory Sync (Zero Hardcoded Thresholds)

    private func makeBinaryPlannerSteps(count: Int, prefix: String = "Binary step") -> Data {
        var out = Data()
        for idx in 0..<count {
            var stepBytes = Data()
            stepBytes.append(encodeVarintField(1, value: 15)) // PLANNER_RESPONSE
            stepBytes.append(encodeVarintField(4, value: 3))  // DONE
            let planner = encodeStringField(1, string: "\(prefix) \(idx)")
            stepBytes.append(encodeLengthField(20, payload: planner))
            out.append(encodeLengthField(1, payload: stepBytes))
        }
        return out
    }

    private func makeJSONPlannerStepsPayload(range: Range<Int>, truncatedAt: Int? = nil) -> Data {
        let stepsJSON = range.map { idx in
            """
            {"stepIndex":\(idx),"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"JSON step \(idx)"}}
            """
        }.joined(separator: ",")
        if let truncatedAt {
            return Data("{\"steps\":[\(stepsJSON)],\"truncatedAt\":\(truncatedAt)}".utf8)
        }
        return Data("{\"steps\":[\(stepsJSON)]}".utf8)
    }

    func testLocalHostDefaultsToBinaryProtobufAndRepairsUnknownStepTypeViaTargetedJSON() async throws {
        let normalProtoBytes = makeBinaryPlannerSteps(count: 1, prefix: "Binary-first local reply")

        var futureSubmsg = Data()
        futureSubmsg.append(encodeStringField(1, string: "Binary Preview"))
        var unknownStepBytes = Data()
        unknownStepBytes.append(encodeVarintField(1, value: 199)) // Unknown CortexStepType 199
        unknownStepBytes.append(encodeVarintField(4, value: 3))   // DONE
        unknownStepBytes.append(encodeLengthField(199, payload: futureSubmsg))
        let unknownProtoBytes = encodeLengthField(1, payload: unknownStepBytes)

        let repairedStepJSON = Data("""
        {
          "steps": [
            {
              "stepIndex": 0,
              "type": "CORTEX_STEP_TYPE_FUTURE_CANVAS_RENDER",
              "status": "CORTEX_STEP_STATUS_DONE",
              "futureCanvasRender": {
                "title": "Interactive Architecture Map",
                "summary": "Rendered 14 microservices"
              }
            }
          ]
        }
        """.utf8)

        let probe = CompatTrajectoryProbeState()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            if path.hasSuffix("/GetCascadeTrajectorySteps") {
                if contentType.contains("application/proto") {
                    probe.recordProto()
                    let payload = probe.shouldReturnUnknownStep() ? unknownProtoBytes : normalProtoBytes
                    let resp = HTTPURLResponse(
                        url: req.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/proto"]
                    )!
                    return (resp, payload)
                } else {
                    let bodyData = CompatMockURLProtocol.readBody(from: req)
                    let bodyObj = (try? JSONDecoder().decode([String: JSONValue].self, from: bodyData)) ?? [:]
                    probe.recordJSON(stepOffset: bodyObj["stepOffset"]?.intValue)
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, repairedStepJSON)
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "local-binary-default",
            hostname: "Local Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18795")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        // 1. Normal binary step fetch on local direct host -> 1 application/proto request, 0 JSON requests
        let normalSteps = try await client.fetchAllTrajectorySteps(
            cascadeId: "cas-local-binary",
            knownStepCount: 1
        )
        XCTAssertEqual(normalSteps.count, 1)
        XCTAssertEqual(normalSteps[0].type, .plannerResponse)
        XCTAssertEqual(normalSteps[0].plannerResponse?.response, "Binary-first local reply 0")
        XCTAssertEqual(probe.protoCount(), 1)
        XCTAssertEqual(probe.jsonCount(), 0)

        // 2. Binary unknown step type 199 triggers targeted JSON stepOffset repair and recovers exact metadata
        probe.resetCounts()
        probe.setReturnUnknownStep(true)
        let repairedSteps = try await client.fetchAllTrajectorySteps(
            cascadeId: "cas-local-binary",
            knownStepCount: 1
        )
        XCTAssertEqual(repairedSteps.count, 1)
        XCTAssertEqual(repairedSteps[0].type, .unspecified)
        XCTAssertEqual(repairedSteps[0].rawTypeName, "CORTEX_STEP_TYPE_FUTURE_CANVAS_RENDER")
        XCTAssertEqual(repairedSteps[0].fallbackSummary, "Interactive Architecture Map")
        XCTAssertEqual(probe.protoCount(), 1)
        XCTAssertEqual(probe.jsonCount(), 1)
        XCTAssertEqual(probe.lastJsonStepOffset(), 0)
    }

    func testBinaryProtobuf415FallsBackToJSONCachesAndResetsOnHostVersionChange() async throws {
        let jsonFallbackBytes = makeJSONPlannerStepsPayload(range: 0..<1)
        let probe = CompatTrajectoryProbeState()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            if path.hasSuffix("/GetCascadeTrajectorySteps") {
                if contentType.contains("application/proto") {
                    probe.recordProto()
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 415, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, Data("{\"code\":\"unimplemented\",\"message\":\"unsupported media type application/proto\"}".utf8))
                } else {
                    probe.recordJSON(stepOffset: nil)
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, jsonFallbackBytes)
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "local-proto-415",
            hostname: "JSON-Only Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18796")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        // 1. First fetch gets 415 on application/proto and falls back cleanly to JSON
        let firstSteps = try await client.fetchAllTrajectorySteps(
            cascadeId: "cas-415",
            knownStepCount: 1
        )
        XCTAssertEqual(firstSteps.count, 1)
        XCTAssertEqual(firstSteps[0].plannerResponse?.response, "JSON step 0")
        XCTAssertEqual(probe.protoCount(), 1)
        XCTAssertEqual(probe.jsonCount(), 1)
        let cachedProfile = await client.capabilityProfile()
        XCTAssertTrue(cachedProfile.binaryProtobufStepsUnsupported)

        // 2. Second fetch skips application/proto completely (0 proto requests)
        probe.resetCounts()
        let secondSteps = try await client.fetchAllTrajectorySteps(
            cascadeId: "cas-415",
            knownStepCount: 1
        )
        XCTAssertEqual(secondSteps.count, 1)
        XCTAssertEqual(probe.protoCount(), 0, "Cached binaryProtobufStepsUnsupported must skip application/proto")
        XCTAssertEqual(probe.jsonCount(), 1)

        // 3. Host version change clears both binaryProtobufStepsUnsupported and learnedJsonStepCeiling
        var mutableProfile = HostCapabilityProfile(hostKey: "host-ver-reset", reportedVersion: "v2.34.0")
        mutableProfile.recordBinaryProtobufStepsUnsupported()
        mutableProfile.recordJsonStepCeiling(240)
        XCTAssertTrue(mutableProfile.binaryProtobufStepsUnsupported)
        XCTAssertEqual(mutableProfile.learnedJsonStepCeiling, 240)

        mutableProfile.updateReportedVersion("2.35.0")
        XCTAssertFalse(mutableProfile.binaryProtobufStepsUnsupported)
        XCTAssertNil(mutableProfile.learnedJsonStepCeiling)
        XCTAssertEqual(mutableProfile.reportedVersion, "2.35.0")

        // 4. Legacy persisted HostCapabilityProfile JSON without the new fields still decodes cleanly
        let legacyProfileJSON = Data("""
        {
          "hostKey": "legacy-host",
          "reportedVersion": "v2.32.0",
          "isCompanionBridge": false,
          "bridgeSupportedMethods": [],
          "supportedMethods": ["GetWorkspaceInfos"],
          "unsupportedMethods": [],
          "strippedFieldsByMethod": {},
          "downgradedEnumsByMethod": {},
          "passiveSignals": [],
          "updatedAt": 0
        }
        """.utf8)
        let decodedLegacy = try JSONDecoder().decode(HostCapabilityProfile.self, from: legacyProfileJSON)
        XCTAssertEqual(decodedLegacy.hostKey, "legacy-host")
        XCTAssertNil(decodedLegacy.learnedJsonStepCeiling)
        XCTAssertFalse(decodedLegacy.binaryProtobufStepsUnsupported)
    }

    func testAdaptiveJsonLearnsArbitraryTruncatedAtCeilingWithoutHardcoded600() async throws {
        let truncatedJsonBytes = makeJSONPlannerStepsPayload(range: 0..<2, truncatedAt: 240)
        let smallJsonBytes = makeJSONPlannerStepsPayload(range: 0..<100)
        let fullProtoBytes = makeBinaryPlannerSteps(count: 5, prefix: "Cloud binary step")

        let probe = CompatTrajectoryProbeState()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            if path.hasSuffix("/GetCascadeTrajectorySteps") {
                if contentType.contains("application/proto") {
                    probe.recordProto()
                    let resp = HTTPURLResponse(
                        url: req.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/proto"]
                    )!
                    return (resp, fullProtoBytes)
                } else {
                    let bodyData = CompatMockURLProtocol.readBody(from: req)
                    let bodyObj = (try? JSONDecoder().decode([String: JSONValue].self, from: bodyData)) ?? [:]
                    let cid = bodyObj["cascadeId"]?.stringValue ?? ""
                    probe.recordJSON(stepOffset: bodyObj["stepOffset"]?.intValue)
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    if cid == "v1/cas-cloud-small-100" {
                        return (resp, smallJsonBytes)
                    }
                    return (resp, truncatedJsonBytes)
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "cloud-ceiling-240",
            hostname: "Cloud Proxy Host",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18797")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        // 1. First Cloud fetch observes JSON `truncatedAt: 240` -> learns ceiling 240 and upgrades to Binary Protobuf
        let firstSteps = try await client.fetchAllTrajectorySteps(
            cascadeId: "v1/cas-cloud-240",
            knownStepCount: 250,
            isCloud: true
        )
        XCTAssertEqual(firstSteps.count, 5)
        let learnedCeiling = await client.learnedJsonTrajectoryStepCeiling()
        XCTAssertEqual(learnedCeiling, 240)
        XCTAssertEqual(probe.jsonCount(), 1)
        XCTAssertEqual(probe.protoCount(), 1)

        // 2. Next fetch with knownStepCount 250 (>= 240) hits learned fast-path -> 0 JSON calls, 1 Protobuf call
        probe.resetCounts()
        let fastPathSteps = try await client.fetchAllTrajectorySteps(
            cascadeId: "v1/cas-cloud-240",
            knownStepCount: 250,
            isCloud: true
        )
        XCTAssertEqual(fastPathSteps.count, 5)
        XCTAssertEqual(probe.jsonCount(), 0, "Learned ceiling 240 must skip JSON when knownStepCount >= 240")
        XCTAssertEqual(probe.protoCount(), 1)

        // 3. Smaller fetch with knownStepCount 100 (< learned 240) uses JSON normally without forcing Protobuf
        probe.resetCounts()
        let smallSteps = try await client.fetchAllTrajectorySteps(
            cascadeId: "v1/cas-cloud-small-100",
            knownStepCount: 100,
            isCloud: true
        )
        XCTAssertEqual(smallSteps.count, 100)
        XCTAssertEqual(probe.jsonCount(), 1)
        XCTAssertEqual(probe.protoCount(), 0)
    }

    func testAdaptiveJsonDetectsSilentPaginationStallAndLearnsCeiling() async throws {
        let firstPageJson = makeJSONPlannerStepsPayload(range: 0..<5)
        let emptyPageJson = Data("{\"steps\":[]}".utf8)
        let fullProtoBytes = makeBinaryPlannerSteps(count: 12, prefix: "Recovered stall step")

        let probe = CompatTrajectoryProbeState()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            if path.hasSuffix("/GetCascadeTrajectorySteps") {
                if contentType.contains("application/proto") {
                    probe.recordProto()
                    let resp = HTTPURLResponse(
                        url: req.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/proto"]
                    )!
                    return (resp, fullProtoBytes)
                } else {
                    let bodyData = CompatMockURLProtocol.readBody(from: req)
                    let bodyObj = (try? JSONDecoder().decode([String: JSONValue].self, from: bodyData)) ?? [:]
                    let stepOffset = bodyObj["stepOffset"]?.intValue ?? 0
                    probe.recordJSON(stepOffset: stepOffset)
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, stepOffset == 0 ? firstPageJson : emptyPageJson)
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "cloud-stall-host",
            hostname: "Stalling Cloud Host",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18798")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        let steps = try await client.fetchAllTrajectorySteps(
            cascadeId: "v1/cas-cloud-stall",
            knownStepCount: 12,
            isCloud: true
        )
        XCTAssertEqual(steps.count, 12)
        let learnedCeiling = await client.learnedJsonTrajectoryStepCeiling()
        XCTAssertEqual(learnedCeiling, 5)
        XCTAssertEqual(probe.jsonCount(), 2)
        XCTAssertEqual(probe.protoCount(), 1)
    }

    func testAdaptiveJsonUpgradesToProtobufOnHttp413PayloadLimit() async throws {
        let fullProtoBytes = makeBinaryPlannerSteps(count: 42, prefix: "Recovered 413 step")
        let probe = CompatTrajectoryProbeState()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            if path.hasSuffix("/GetCascadeTrajectorySteps") {
                if contentType.contains("application/proto") {
                    probe.recordProto()
                    let resp = HTTPURLResponse(
                        url: req.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/proto"]
                    )!
                    return (resp, fullProtoBytes)
                } else {
                    probe.recordJSON(stepOffset: nil)
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 413, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, Data("{\"code\":\"resource_exhausted\",\"message\":\"Payload Too Large\"}".utf8))
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "cloud-413-host",
            hostname: "Payload-Limited Host",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18799")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        let steps = try await client.fetchAllTrajectorySteps(
            cascadeId: "v1/cas-cloud-413",
            knownStepCount: 42,
            isCloud: true
        )
        XCTAssertEqual(steps.count, 42)
        let learnedCeiling = await client.learnedJsonTrajectoryStepCeiling()
        XCTAssertEqual(learnedCeiling, 42)
        XCTAssertEqual(probe.jsonCount(), 1)
        XCTAssertEqual(probe.protoCount(), 1)
    }

    // MARK: - 10. Historical Dormant Cloud/Local Trajectory Wake & Boq Error Unwrapping

    func testCloudRelayDormantHistoricalCloudTrajectoryWakesViaBareLoadTrajectoryAndSkipsExtraListInstances() async throws {
        let instanceUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
        let state = CompatCloudWakeProbeState()

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            if path.hasSuffix("/ListInstances") {
                state.recordListInstances()
                let resp = HTTPURLResponse(
                    url: req.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json+protobuf"]
                )!
                let listJson = "[[[\"\(instanceUuid)\",[\"MacBook Pro\",\"2.33.0\",true],1,[1740000000,0]]],5]"
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/ProxyCommand") {
                let arr = (try? JSONDecoder().decode([JSONValue].self, from: bodyData)) ?? []
                let rpcPath = arr.count > 1 ? (arr[1].stringValue ?? "") : ""
                let method = rpcPath.split(separator: "/").last.map(String.init) ?? ""
                let b64Payload = arr.count > 2 ? (arr[2].stringValue ?? "") : ""
                let innerData = CloudRelayJSPBCodec.decodeBase64Flexible(b64Payload) ?? Data()
                let innerObj = (try? JSONDecoder().decode([String: JSONValue].self, from: innerData)) ?? [:]
                let cid = innerObj["cascadeId"]?.stringValue ?? ""

                if method == "LoadTrajectory" {
                    state.recordLoadPayload(innerObj)
                    if innerObj["backend"] != nil {
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("[3,\"invalid_argument: unknown field \\\"backend\\\"\"]".utf8))
                    }
                    if innerObj["backendType"] != nil {
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("[3,\"invalid_argument: unknown field \\\"backendType\\\"\"]".utf8))
                    }
                    state.markWoken(cid)
                    let okB64 = Data("{}".utf8).base64EncodedString()
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, Data("[\"\(okB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                }

                if method == "GetCascadeTrajectorySteps" {
                    if state.isWoken(cid) {
                        let stepsJson = """
                        {"steps":[
                            {"stepIndex":0,"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"items":[{"text":"Sync mobile"}]}},
                            {"stepIndex":1,"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Synced!"}}
                        ]}
                        """
                        let okB64 = Data(stepsJson.utf8).base64EncodedString()
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("[\"\(okB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                    } else {
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("[5,\"not_found: trajectory not found (error ID: 721ffeb9b0bb4fb6b2a971dfa56087e2)\"]".utf8))
                    }
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let host = RemoteHostInstance(
            instanceId: instanceUuid,
            hostname: "MacBook Pro",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(instanceUuid)")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        let steps1 = try await client.fetchAllTrajectorySteps(
            cascadeId: "v1/sync-mobile-concept",
            knownStepCount: 2,
            isCloud: true
        )
        XCTAssertEqual(steps1.count, 2)
        XCTAssertEqual(state.listInstancesCount(), 1, "Trajectory-level 404 must not trigger extra ListInstances RTT")
        let firstLoads = state.loadPayloads()
        XCTAssertEqual(firstLoads.count, 3)
        XCTAssertNil(firstLoads.last?["backend"])
        XCTAssertNil(firstLoads.last?["backendType"])

        // Second dormant Cloud chat reuses cached bare `{cascadeId}` in 1 RTT
        state.clearLoadPayloads()
        let steps2 = try await client.fetchAllTrajectorySteps(
            cascadeId: "v1/sync-mobile-concept-2",
            knownStepCount: 2,
            isCloud: true
        )
        XCTAssertEqual(steps2.count, 2)
        XCTAssertEqual(state.loadPayloads().count, 1)
        XCTAssertEqual(state.listInstancesCount(), 1)
    }

    func testLocalDormantTrajectoryWakesOnBinaryProtobuf404NotFound() async throws {
        let fullProtoBytes = makeBinaryPlannerSteps(count: 3, prefix: "Woken local step")
        let state = CompatCloudWakeProbeState()
        let probe = CompatTrajectoryProbeState()

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let contentType = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            if path.hasSuffix("/LoadTrajectory") {
                state.markWoken("cas-dormant-local")
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data("{}".utf8))
            }
            if path.hasSuffix("/GetCascadeTrajectorySteps") {
                if contentType.contains("application/proto") {
                    probe.recordProto()
                    if state.isWoken("cas-dormant-local") {
                        let resp = HTTPURLResponse(
                            url: req.url!,
                            statusCode: 200,
                            httpVersion: "HTTP/1.1",
                            headerFields: ["Content-Type": "application/proto"]
                        )!
                        return (resp, fullProtoBytes)
                    } else {
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("{\"code\":\"not_found\",\"message\":\"trajectory not found\"}".utf8))
                    }
                } else {
                    probe.recordJSON(stepOffset: nil)
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{\"steps\":[]}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "local-dormant-404",
            hostname: "Local Dormant Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18800")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        let steps = try await client.fetchAllTrajectorySteps(
            cascadeId: "cas-dormant-local",
            knownStepCount: 3,
            isCloud: false
        )
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(probe.protoCount(), 2, "Must retry Binary Protobuf directly after LoadTrajectory")
        XCTAssertEqual(probe.jsonCount(), 0, "Must not fall back to JSON GetCascadeTrajectorySteps")
    }

    func testBoqErrorUnwrappingTrajectory404AndFormattedUserFacingError() {
        let boqUnknownBackend = "[3,\"invalid_argument: unknown field \\\"backend\\\"\"]"
        XCTAssertEqual(
            ProtocolCompatibilityEngine.extractUnknownProtoFieldName(from: boqUnknownBackend),
            "backend"
        )

        let boqNotFound = "[5,\"not_found: trajectory not found (error ID: 721ffeb9b0bb4fb6b2a971dfa56087e2)\"]"
        XCTAssertTrue(ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(statusCode: 404, body: boqNotFound))
        XCTAssertFalse(
            ProtocolCompatibilityEngine.isMethodUnimplementedResponse(statusCode: 404, body: boqNotFound),
            "Trajectory-level 404 must not poison negative capability cache"
        )

        let stripped = ProtocolCompatibilityEngine.stripRedundantHttpPrefix(
            from: "HTTP 404: HTTP 404: \(boqNotFound)",
            statusCode: 404
        )
        XCTAssertEqual(stripped, boqNotFound)

        let formatted = ProtocolCompatibilityEngine.formatUserFacingRpcError(
            AntigravityRPCError.httpError(statusCode: 404, body: "HTTP 404: \(boqNotFound)")
        )
        XCTAssertFalse(formatted.contains("HTTP 404: HTTP 404:"))
        XCTAssertFalse(formatted.contains("[5,"))
        XCTAssertTrue(formatted.contains("not_found: trajectory not found"))
    }

    func testCloudStreamAgentStateUpdatesLoadsActiveCloudTrajectoryWhenLegacyStepsReturns404() async throws {
        let instanceUuid = "0f5819ac-9308-40d8-a308-98b55122c533-v2"
        let cloudCascadeId = "v1/default/jetski_remote_agents_3p_devbox/356aa3f9-503f-447a-8319-3e1baae4c634"
        let counter = CompatRequestCounter()

        let metaFrameJson = """
        {"update":{"conversationId":"\(cloudCascadeId)","status":"CASCADE_RUN_STATUS_RUNNING"}}
        """
        let stepsFrameJson = """
        {"update":{"conversationId":"\(cloudCascadeId)","status":"CASCADE_RUN_STATUS_RUNNING","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0,1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"items":[{"text":"聊天记录加载优化建议"}]}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_IN_PROGRESS","plannerResponse":{"response":"正在分析聊天记录加载路径..."}}]}}}}
        """
        let endFrame = ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream)
        var connectStreamBytes = Data()
        connectStreamBytes.append(ConnectEnvelope.encode(payload: Data(metaFrameJson.utf8)))
        connectStreamBytes.append(ConnectEnvelope.encode(payload: Data(stepsFrameJson.utf8)))
        connectStreamBytes.append(endFrame)
        let boqChunk = "[\"\(connectStreamBytes.base64EncodedString())\",[[\"content-type\",\"application/connect+json\"]]]"

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            counter.record(path: path)
            if path.hasSuffix("/ListInstances") {
                let resp = HTTPURLResponse(
                    url: req.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json+protobuf"]
                )!
                let listJson = "[[[\"\(instanceUuid)\",[\"MacBook Pro\",\"2.34.0\",true],1,[1740000000,0]]],5]"
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/StreamProxyCommand") {
                let resp = HTTPURLResponse(
                    url: req.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json+protobuf"]
                )!
                return (resp, Data(boqChunk.utf8))
            }
            if path.hasSuffix("/ProxyCommand") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (resp, Data("[5,\"not_found: trajectory not found (error ID: 356aa3f9503f447a83193e1baae4c634)\"]".utf8))
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let host = RemoteHostInstance(
            instanceId: instanceUuid,
            hostname: "MacBook Pro",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(instanceUuid)")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        let steps = try await client.fetchAllTrajectorySteps(
            cascadeId: cloudCascadeId,
            knownStepCount: 2,
            isCloud: true
        )
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].stepIndex, 0)
        XCTAssertEqual(steps[0].userInput, "聊天记录加载优化建议")
        XCTAssertEqual(steps[1].stepIndex, 1)
        XCTAssertEqual(steps[1].plannerResponse?.response, "正在分析聊天记录加载路径...")
        XCTAssertEqual(counter.count(forSuffix: "/StreamProxyCommand"), 1)
        XCTAssertEqual(counter.count(forSuffix: "/ProxyCommand"), 0, "Cloud primary StreamAgentStateUpdates should succeed without calling doomed GetCascadeTrajectorySteps")
    }

    func testLocalTrajectoryFallsBackToStreamAgentStateUpdatesWhenLegacyStepsReturns404() async throws {
        let localCid = "cas-local-sqlite-234"
        let frame1Json = """
        {"update":{"conversationId":"\(localCid)","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Inspect live turn"}}]}}}}
        """
        let frame2Json = """
        {"update":{"conversationId":"\(localCid)","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Recovered via StreamAgentStateUpdates"}}]}}}}
        """
        var streamBytes = Data()
        streamBytes.append(ConnectEnvelope.encode(payload: Data(frame1Json.utf8)))
        streamBytes.append(ConnectEnvelope.encode(payload: Data(frame2Json.utf8)))
        streamBytes.append(ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream))
        let streamPayload = streamBytes

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/StreamAgentStateUpdates") {
                let resp = HTTPURLResponse(
                    url: req.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/connect+json"]
                )!
                return (resp, streamPayload)
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("{\"code\":\"not_found\",\"message\":\"trajectory not found\"}".utf8))
        }

        let host = RemoteHostInstance(
            instanceId: "local-234-stream-fallback",
            hostname: "Local Mac 2.34",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18801")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        let steps = try await client.fetchAllTrajectorySteps(
            cascadeId: localCid,
            knownStepCount: 2,
            isCloud: false
        )
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].stepIndex, 0)
        XCTAssertEqual(steps[0].userInput, "Inspect live turn")
        XCTAssertEqual(steps[1].stepIndex, 1)
        XCTAssertEqual(steps[1].plannerResponse?.response, "Recovered via StreamAgentStateUpdates")
    }

    func testSendUserCascadeMessageWakesDormantTrajectoryAndProbesCloudRelayPeer() async throws {
        let primaryUuid = "inst-primary-swift-1"
        let peerUuid = "inst-peer-swift-2"
        let cloudCascadeId = "v1/cloud-peer-pinned-swift"
        let state = CompatSendRecoveryProbeState()

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            if path.hasSuffix("/ListInstances") {
                let listJson = "[[[\"\(primaryUuid)\",[\"MacBook Pro\",\"2.34.0\",true],1,[1740000000,0]],[\"\(peerUuid)\",[\"Studio Relay\",\"2.34.0\",true],1,[1740000001,0]]],5]"
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/ProxyCommand") {
                let arr = (try? JSONDecoder().decode([JSONValue].self, from: bodyData)) ?? []
                let targetUuid = arr.count > 0 ? (arr[0].stringValue ?? "") : ""
                let rpcPath = arr.count > 1 ? (arr[1].stringValue ?? "") : ""
                let method = rpcPath.split(separator: "/").last.map(String.init) ?? ""
                let b64Payload = arr.count > 2 ? (arr[2].stringValue ?? "") : ""
                let innerData = CloudRelayJSPBCodec.decodeBase64Flexible(b64Payload) ?? Data()
                let innerObj = (try? JSONDecoder().decode([String: JSONValue].self, from: innerData)) ?? [:]
                let cid = innerObj["cascadeId"]?.stringValue ?? ""

                if method == "LoadTrajectory" {
                    if targetUuid == peerUuid {
                        state.markWoken(cid)
                        let okB64 = Data("{}".utf8).base64EncodedString()
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("[\"\(okB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                    } else {
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("[5,\"not_found: session not found\"]".utf8))
                    }
                }
                if method == "SendUserCascadeMessage" {
                    state.recordSendTarget(targetUuid)
                    if targetUuid == peerUuid && state.isWoken(cid) {
                        let okB64 = Data("{}".utf8).base64EncodedString()
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("[\"\(okB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                    } else {
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("[5,\"not_found: trajectory not found\"]".utf8))
                    }
                }
                if method == "CancelCascadeInvocation" {
                    state.recordCancelTarget(targetUuid)
                    let okB64 = Data("{}".utf8).base64EncodedString()
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, Data("[\"\(okB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let host = RemoteHostInstance(
            instanceId: primaryUuid,
            hostname: "MacBook Pro",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(primaryUuid)")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        try await client.sendUserCascadeMessage(
            cascadeId: cloudCascadeId,
            message: "First message",
            modelId: "MODEL_PLACEHOLDER_M37",
            isCloud: true
        )
        XCTAssertTrue(state.sendTargets().contains(peerUuid))

        state.clearTargets()
        try await client.sendUserCascadeMessage(
            cascadeId: cloudCascadeId,
            message: "Second message",
            modelId: "MODEL_PLACEHOLDER_M37",
            isCloud: true
        )
        try await client.cancelCascadeInvocation(cascadeId: cloudCascadeId)
        XCTAssertEqual(state.sendTargets(), [peerUuid], "Subsequent send should route directly to pinned peer")
        XCTAssertEqual(state.cancelTargets(), [peerUuid], "Cancel should route directly to pinned peer")
    }

    func testStartCascadeOverCloudRelayOmitsClientIdAndNegotiatesBackendType() async throws {
        let instanceUuid = "inst-cloud-start-swift"
        let state = CompatCloudWakeProbeState()

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            if path.hasSuffix("/ListInstances") {
                let listJson = "[[[\"\(instanceUuid)\",[\"MacBook Pro\",\"2.34.0\",true],1,[1740000000,0]]],5]"
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/ProxyCommand") {
                let arr = (try? JSONDecoder().decode([JSONValue].self, from: bodyData)) ?? []
                let rpcPath = arr.count > 1 ? (arr[1].stringValue ?? "") : ""
                let method = rpcPath.split(separator: "/").last.map(String.init) ?? ""
                let b64Payload = arr.count > 2 ? (arr[2].stringValue ?? "") : ""
                let innerData = CloudRelayJSPBCodec.decodeBase64Flexible(b64Payload) ?? Data()
                let innerObj = (try? JSONDecoder().decode([String: JSONValue].self, from: innerData)) ?? [:]

                if method == "StartCascade" {
                    state.recordLoadPayload(innerObj)
                    if innerObj["backend"] != nil {
                        let resp = HTTPURLResponse(url: req.url!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!
                        return (resp, Data("[3,\"invalid_argument: unknown field \\\"backend\\\"\"]".utf8))
                    }
                    let okB64 = Data("{\"cascadeId\":\"v1/cloud-minted-swift\"}".utf8).base64EncodedString()
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                    return (resp, Data("[\"\(okB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let host = RemoteHostInstance(
            instanceId: instanceUuid,
            hostname: "MacBook Pro",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(instanceUuid)")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        let minted = try await client.startCascade(
            workspaceUri: "cloud://slardar_app_ai",
            cloudProjectId: "cp-slardar",
            isCloud: true
        )
        XCTAssertEqual(minted, "v1/cloud-minted-swift")
        let payloads = state.loadPayloads()
        XCTAssertFalse(payloads.isEmpty)
        XCTAssertTrue(payloads.allSatisfy { $0["cascadeId"] == nil }, "Cloud Relay StartCascade must not send client-invented cascadeId")
        XCTAssertEqual(payloads.last?["backendType"]?.stringValue, "BACKEND_TYPE_REMOTE_AICODE")
    }

    func testSendErrorFormattingRecognizesSessionNotFoundAndIsIdempotent() {
        XCTAssertTrue(
            ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(
                statusCode: 404,
                body: "{\"code\":\"not_found\",\"message\":\"session not found\"}"
            )
        )
        XCTAssertTrue(
            ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(
                statusCode: 404,
                body: "agent state for cas-123 not found"
            )
        )
        XCTAssertFalse(
            ProtocolCompatibilityEngine.isTrajectoryNotFoundResponse(
                statusCode: 401,
                body: "Google sign-in session not found"
            )
        )

        let err = AntigravityRPCError.httpError(
            statusCode: 404,
            body: "[5,\"not_found: session not found\"]"
        )
        let formatted = ProtocolCompatibilityEngine.formatUserFacingSendError(err)
        XCTAssertTrue(formatted.contains("This conversation was not found on this host"))
        XCTAssertTrue(formatted.contains("session not found"))
        XCTAssertTrue(formatted.contains("Tap Retry or start a new chat."))

        let reWrapped = ProtocolCompatibilityEngine.formatUserFacingRpcError(
            AntigravityRPCError.httpError(statusCode: 500, body: formatted)
        )
        XCTAssertEqual(reWrapped, formatted)
        XCTAssertFalse(reWrapped.contains("HTTP 500"))
    }

    // MARK: - 11. Fast Conversation Load Optimizations (Repair Reuse/Cache, Incremental Binary Delta, Relay Gzip)

    func testSwiftSingleSliceJsonRepairReusesTailAndCachesSubsequentLoads() async throws {
        var binaryPayload = Data()
        func appendStep(_ bytes: Data) {
            binaryPayload.append(contentsOf: ProtobufStepCodec.encodeVarint((1 << 3) | 2))
            binaryPayload.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(bytes.count)))
            binaryPayload.append(bytes)
        }
        func makeVarintField(_ field: UInt64, _ val: UInt64) -> Data {
            var d = Data()
            d.append(contentsOf: ProtobufStepCodec.encodeVarint((field << 3) | 0))
            d.append(contentsOf: ProtobufStepCodec.encodeVarint(val))
            return d
        }
        func makeLdField(_ field: UInt64, _ payload: Data) -> Data {
            var d = Data()
            d.append(contentsOf: ProtobufStepCodec.encodeVarint((field << 3) | 2))
            d.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(payload.count)))
            d.append(payload)
            return d
        }

        appendStep(makeVarintField(1, 14) + makeVarintField(4, 3) + makeLdField(19, makeLdField(1, Data("Open dashboard".utf8))))
        appendStep(makeVarintField(1, 991) + makeVarintField(4, 3) + makeLdField(91, Data("future-1".utf8)))
        appendStep(makeVarintField(1, 992) + makeVarintField(4, 3) + makeLdField(92, Data("future-2".utf8)))

        let probe = CompatTrajectoryProbeState()
        let frozenBinary = binaryPayload

        let session = makeMockSession { req in
            let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            if ct.contains("application/proto") {
                probe.recordProto()
                let resp = HTTPURLResponse(
                    url: req.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/proto"]
                )!
                return (resp, frozenBinary)
            } else {
                let body = CompatMockURLProtocol.readBody(from: req)
                let obj = (try? JSONDecoder().decode([String: JSONValue].self, from: body)) ?? [:]
                let offset = obj["stepOffset"]?.intValue ?? 0
                probe.recordJSON(stepOffset: offset)
                let stepsJson = """
                {"steps":[
                    {"type":"CORTEX_STEP_TYPE_FUTURE_WIDGET_A","status":"CORTEX_STEP_STATUS_DONE","futureWidgetA":{"summary":"Swift Widget A"}},
                    {"type":"CORTEX_STEP_TYPE_FUTURE_WIDGET_B","status":"CORTEX_STEP_STATUS_DONE","futureWidgetB":{"summary":"Swift Widget B"}}
                ]}
                """
                let resp = HTTPURLResponse(
                    url: req.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (resp, Data(stepsJson.utf8))
            }
        }

        let host = RemoteHostInstance(
            instanceId: "swift-repair-reuse",
            hostname: "Swift Reuse Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18802")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)

        let first = try await client.fetchAllTrajectorySteps(cascadeId: "cas-swift-reuse", knownStepCount: 3)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first[1].fallbackSummary, "Swift Widget A")
        XCTAssertEqual(first[2].fallbackSummary, "Swift Widget B")
        XCTAssertEqual(probe.protoCount(), 1)
        XCTAssertEqual(probe.jsonCount(), 1, "Single tail-slice JSON probe must repair both unrecognized steps in 1 RTT")

        probe.resetCounts()
        let second = try await client.fetchAllTrajectorySteps(cascadeId: "cas-swift-reuse", knownStepCount: 3)
        XCTAssertEqual(second.count, 3)
        XCTAssertEqual(second[1].fallbackSummary, "Swift Widget A")
        XCTAssertEqual(second[2].fallbackSummary, "Swift Widget B")
        XCTAssertEqual(probe.protoCount(), 1)
        XCTAssertEqual(probe.jsonCount(), 0, "Cached repaired steps must emit 0 JSON repair RPCs on repeat loads")
    }

    func testSwiftIncrementalBinaryDeltaSyncMergesTailSteps() async throws {
        let makeSlice: @Sendable (Range<Int>) -> Data = { range in
            var out = Data()
            for i in range {
                var step = Data()
                if i % 2 == 0 {
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint((1 << 3) | 0))
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint(14))
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint((4 << 3) | 0))
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint(3))
                    let txt = Data("User #\(i)".utf8)
                    var inner = Data()
                    inner.append(contentsOf: ProtobufStepCodec.encodeVarint((1 << 3) | 2))
                    inner.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(txt.count)))
                    inner.append(txt)
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint((19 << 3) | 2))
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(inner.count)))
                    step.append(inner)
                } else {
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint((1 << 3) | 0))
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint(15))
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint((4 << 3) | 0))
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint(3))
                    let txt = Data("Answer #\(i)".utf8)
                    var inner = Data()
                    inner.append(contentsOf: ProtobufStepCodec.encodeVarint((1 << 3) | 2))
                    inner.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(txt.count)))
                    inner.append(txt)
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint((20 << 3) | 2))
                    step.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(inner.count)))
                    step.append(inner)
                }
                out.append(contentsOf: ProtobufStepCodec.encodeVarint((1 << 3) | 2))
                out.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(step.count)))
                out.append(step)
            }
            return out
        }

        let decodeOffset: @Sendable (Data) -> Int = { body in
            var pos = 0
            while pos < body.count {
                guard let tag = ProtobufStepCodec.readVarint(from: body, offset: &pos) else { break }
                let field = tag >> 3
                let wire = tag & 0x07
                if wire == 0 {
                    guard let val = ProtobufStepCodec.readVarint(from: body, offset: &pos) else { break }
                    if field == 2 { return Int(val) }
                } else if wire == 2 {
                    guard let len = ProtobufStepCodec.readVarint(from: body, offset: &pos) else { break }
                    pos += Int(len)
                } else {
                    break
                }
            }
            return 0
        }

        let probe = CompatTrajectoryProbeState()
        let session = makeMockSession { req in
            let body = CompatMockURLProtocol.readBody(from: req)
            let offset = decodeOffset(body)
            probe.recordProto()
            probe.recordJSON(stepOffset: offset)
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/proto"]
            )!
            return (resp, makeSlice(offset..<6))
        }

        let host = RemoteHostInstance(
            instanceId: "swift-delta-mac",
            hostname: "Swift Delta Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18803")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)
        let initialFour = ProtobufStepCodec.decodeStepsResponse(makeSlice(0..<4), cascadeId: "cas-swift-delta")
        XCTAssertEqual(initialFour.count, 4)

        let merged = try await client.fetchAllTrajectorySteps(
            cascadeId: "cas-swift-delta",
            knownStepCount: 6,
            existingSteps: initialFour
        )
        XCTAssertEqual(merged.count, 6)
        XCTAssertEqual(probe.protoCount(), 1)
        XCTAssertEqual(probe.lastJsonStepOffset(), 3)
        XCTAssertEqual(merged[0].userInput, "User #0")
        XCTAssertEqual(merged[4].userInput, "User #4")
        XCTAssertEqual(merged[5].plannerResponse?.response, "Answer #5")
    }

    func testCloudRelayProxyRequestIncludesGzipAndProtoAcceptHeaders() throws {
        let encoded = try CloudRelayJSPBCodec.encodeProxyCommandRequest(
            targetInstanceUuid: "uuid-test",
            rpcPath: "/exa.language_server_pb.LanguageServerService/GetCascadeTrajectorySteps",
            payload: Data([0x0A, 0x01, 0x61]),
            contentType: "application/proto"
        )
        let text = (String(data: encoded, encoding: .utf8) ?? "").replacingOccurrences(of: "\\/", with: "/")
        XCTAssertTrue(text.contains("[\"accept-encoding\",\"gzip\"]"), "Missing gzip accept-encoding header: \(text)")
        XCTAssertTrue(text.contains("[\"accept\",\"application/proto\"]"), "Missing application/proto accept header: \(text)")

        let streamEncoded = try CloudRelayJSPBCodec.encodeProxyCommandRequest(
            targetInstanceUuid: "uuid-test",
            rpcPath: "/exa.language_server_pb.LanguageServerService/StreamAgentStateUpdates",
            payload: ConnectEnvelope.encode(payload: Data("{\"conversationId\":\"v1/c\"}".utf8)),
            contentType: "application/connect+json",
            isStreaming: true
        )
        let streamText = (String(data: streamEncoded, encoding: .utf8) ?? "").replacingOccurrences(of: "\\/", with: "/")
        XCTAssertFalse(streamText.contains("[\"accept-encoding\",\"gzip\"]"), "Streaming StreamProxyCommand must NOT send accept-encoding:gzip: \(streamText)")
    }

    func testSwiftCloudRelayProtoJsonErrorInside200OkFallsBackAndCachesUnsupported() async throws {
        let instanceUuid = "inst-swift-proto-415"
        let probe = CompatTrajectoryProbeState()

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            if path.hasSuffix("/ListInstances") {
                let listJson = "[[[\"\(instanceUuid)\",[\"MacBook Pro\",\"2.34.0\",true],1,[1740000000,0]]],5]"
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/ProxyCommand") {
                let bodyText = (String(data: bodyData, encoding: .utf8) ?? "").replacingOccurrences(of: "\\/", with: "/")
                if bodyText.contains("\"content-type\",\"application/proto\"") {
                    probe.recordProto()
                    let errB64 = Data("{\"code\":\"invalid_argument\",\"message\":\"unsupported media type application/proto\"}".utf8).base64EncodedString()
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                    return (resp, Data("[\"\(errB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                } else {
                    probe.recordJSON(stepOffset: 0)
                    let okJson = "{\"steps\":[{\"type\":\"CORTEX_STEP_TYPE_USER_INPUT\",\"status\":\"CORTEX_STEP_STATUS_DONE\",\"userInput\":{\"text\":\"Hello\"}},{\"type\":\"CORTEX_STEP_TYPE_PLANNER_RESPONSE\",\"status\":\"CORTEX_STEP_STATUS_DONE\",\"plannerResponse\":{\"response\":\"World\"}}]}"
                    let okB64 = Data(okJson.utf8).base64EncodedString()
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                    return (resp, Data("[\"\(okB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let host = RemoteHostInstance(
            instanceId: instanceUuid,
            hostname: "MacBook Pro",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/\(instanceUuid)")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        let first = try await client.fetchAllTrajectorySteps(cascadeId: "cas-swift-415-1", knownStepCount: 2, isCloud: false)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(probe.protoCount(), 1)
        XCTAssertEqual(probe.jsonCount(), 1)

        probe.resetCounts()
        let second = try await client.fetchAllTrajectorySteps(cascadeId: "cas-swift-415-2", knownStepCount: 2, isCloud: false)
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(probe.protoCount(), 0, "Unsupported binary protobuf over Cloud Relay must be cached per host")
        XCTAssertEqual(probe.jsonCount(), 1)
    }

    func testSwiftLargeHistoricalBinaryTrajectorySkipsFullTailJsonRepair() async throws {
        var binaryPayload = Data()
        func makeVarint(_ field: UInt64, _ val: UInt64) -> Data {
            var d = Data()
            d.append(contentsOf: ProtobufStepCodec.encodeVarint((field << 3) | 0))
            d.append(contentsOf: ProtobufStepCodec.encodeVarint(val))
            return d
        }
        func makeLd(_ field: UInt64, _ payload: Data) -> Data {
            var d = Data()
            d.append(contentsOf: ProtobufStepCodec.encodeVarint((field << 3) | 2))
            d.append(contentsOf: ProtobufStepCodec.encodeVarint(UInt64(payload.count)))
            d.append(payload)
            return d
        }
        for i in 0..<40 {
            let step: Data
            if i == 2 {
                step = makeVarint(1, 995) + makeVarint(4, 3) + makeLd(95, Data("hk".utf8))
            } else if i % 2 == 0 {
                step = makeVarint(1, 14) + makeVarint(4, 3) + makeLd(19, makeLd(1, Data("User #\(i)".utf8)))
            } else {
                step = makeVarint(1, 15) + makeVarint(4, 3) + makeLd(20, makeLd(1, Data("Reply #\(i)".utf8)))
            }
            binaryPayload.append(makeLd(1, step))
        }
        let frozen = binaryPayload
        let probe = CompatTrajectoryProbeState()

        let session = makeMockSession { req in
            let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            if ct.contains("application/proto") {
                probe.recordProto()
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/proto"])!
                return (resp, frozen)
            } else {
                probe.recordJSON(stepOffset: 0)
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return (resp, Data("{\"steps\":[]}".utf8))
            }
        }

        let host = RemoteHostInstance(
            instanceId: "swift-large-bounded",
            hostname: "Swift Bounded Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18809")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)
        let steps = try await client.fetchAllTrajectorySteps(cascadeId: "cas-swift-40", knownStepCount: 40)
        XCTAssertEqual(steps.count, 40)
        XCTAssertEqual(probe.protoCount(), 1)
        XCTAssertEqual(probe.jsonCount(), 0, "Large historical trajectory must skip blocking full-tail JSON repair")
    }

    func testSwiftLocal2xDormantTrajectoryShortCircuitsToStreamWithoutDuplicateWake() async throws {
        let localCid = "cas-swift-local-2x-fast"
        let frameJson = "{\"update\":{\"conversationId\":\"\(localCid)\",\"mainTrajectoryUpdate\":{\"stepsUpdate\":{\"indices\":[0,1],\"totalLength\":2,\"steps\":[{\"type\":\"CORTEX_STEP_TYPE_USER_INPUT\",\"status\":\"CORTEX_STEP_STATUS_DONE\",\"userInput\":{\"text\":\"Fast load\"}},{\"type\":\"CORTEX_STEP_TYPE_PLANNER_RESPONSE\",\"status\":\"CORTEX_STEP_STATUS_DONE\",\"plannerResponse\":{\"response\":\"Streamed directly\"}}]}}}}"
        var streamBytes = Data()
        streamBytes.append(ConnectEnvelope.encode(payload: Data(frameJson.utf8)))
        streamBytes.append(ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream))
        let frozenStream = streamBytes

        let counter = CompatRequestCounter()
        let probe = CompatTrajectoryProbeState()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let ct = req.value(forHTTPHeaderField: "Content-Type") ?? ""
            counter.record(path: path)
            if path.hasSuffix("/LoadTrajectory") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return (resp, Data("{}".utf8))
            }
            if path.hasSuffix("/GetCascadeTrajectorySteps") {
                if ct.contains("application/proto") {
                    probe.recordProto()
                } else {
                    probe.recordJSON(stepOffset: 0)
                }
                let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                return (resp, Data("{\"code\":\"not_found\",\"message\":\"trajectory not found\"}".utf8))
            }
            if path.hasSuffix("/StreamAgentStateUpdates") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/connect+json"])!
                return (resp, frozenStream)
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let host = RemoteHostInstance(
            instanceId: "swift-local-2x-fast",
            hostname: "Swift 2.x Mac",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18810")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)
        let steps = try await client.fetchAllTrajectorySteps(cascadeId: localCid, knownStepCount: 2, isCloud: false)
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[1].plannerResponse?.response, "Streamed directly")
        XCTAssertEqual(counter.count(forSuffix: "/LoadTrajectory"), 1, "Must not call LoadTrajectory twice")
        XCTAssertEqual(probe.jsonCount(), 0, "Must skip doomed JSON GetCascadeTrajectorySteps probes")
        XCTAssertEqual(counter.count(forSuffix: "/StreamAgentStateUpdates"), 1)
    }

    func testSwiftCloudAuthoritativeEmptyStreamSkipsLegacyFallback() async throws {
        let cloudCid = "v1/swift-cloud-empty"
        let emptyJson = "{\"update\":{\"conversationId\":\"\(cloudCid)\",\"mainTrajectoryUpdate\":{\"stepsUpdate\":{\"indices\":[],\"totalLength\":0,\"steps\":[]}}}}"
        var streamBytes = Data()
        streamBytes.append(ConnectEnvelope.encode(payload: Data(emptyJson.utf8)))
        streamBytes.append(ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream))
        let frozenStream = streamBytes

        let counter = CompatRequestCounter()
        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            counter.record(path: path)
            if path.hasSuffix("/StreamAgentStateUpdates") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/connect+json"])!
                return (resp, frozenStream)
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let host = RemoteHostInstance(
            instanceId: "swift-cloud-empty-host",
            hostname: "Cloud Host",
            channel: .directHost,
            endpointURL: URL(string: "http://127.0.0.1:18811")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(host: host, csrfToken: "test-csrf", urlSession: session)
        let steps = try await client.fetchAllTrajectorySteps(cascadeId: cloudCid, knownStepCount: 0, isCloud: true)
        XCTAssertTrue(steps.isEmpty)
        XCTAssertEqual(counter.count(forSuffix: "/StreamAgentStateUpdates"), 2, "Cloud empty stub on Variant #1 probes Variant #2 backend before settling authoritative empty")
        XCTAssertEqual(counter.count(forSuffix: "/GetCascadeTrajectorySteps"), 0)
        XCTAssertEqual(counter.count(forSuffix: "/LoadTrajectory"), 0)
    }

    func testCloudStreamAgentStateUpdatesDoesNotAbortOnEmptyZeroStubAndTriesBackendVariant() async throws {
        let instanceUuid = "inst-swift-cloud-stub"
        let cloudCascadeId = "v1/default/jetski_remote_agents_3p_devbox/xcode-signing-swift"
        let probe = CompatCloudWakeProbeState()

        let emptyStubFrame = """
        {"update":{"conversationId":"\(cloudCascadeId)","mainTrajectoryUpdate":{"stepsUpdate":{"totalLength":0}}}}
        """
        var emptyStreamBytes = Data()
        emptyStreamBytes.append(ConnectEnvelope.encode(payload: Data(emptyStubFrame.utf8)))
        emptyStreamBytes.append(ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream))
        let emptyBoqChunk = "[\"\(emptyStreamBytes.base64EncodedString())\",[[\"content-type\",\"application/connect+json\"]]]"

        let realStepsFrame = """
        {"update":{"conversationId":"\(cloudCascadeId)","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0,1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Xcode签名丢失原因分析"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"根因是自动签名配置被覆盖。"}}]}}}}
        """
        var realStreamBytes = Data()
        realStreamBytes.append(ConnectEnvelope.encode(payload: Data(realStepsFrame.utf8)))
        realStreamBytes.append(ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream))
        let realBoqChunk = "[\"\(realStreamBytes.base64EncodedString())\",[[\"content-type\",\"application/connect+json\"]]]"

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            if path.hasSuffix("/ListInstances") {
                let listJson = "[[[\"\(instanceUuid)\",[\"MacBook Pro\",\"2.34.0\",true],1,[1740000000,0]]],5]"
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/StreamProxyCommand") {
                let arr = (try? JSONDecoder().decode([JSONValue].self, from: bodyData)) ?? []
                let b64Inner = arr.count > 2 ? (arr[2].stringValue ?? "") : ""
                let framed = CloudRelayJSPBCodec.decodeBase64Flexible(b64Inner) ?? Data()
                let innerData = framed.count > 5 ? framed.subdata(in: 5..<framed.count) : Data("{}".utf8)
                let innerObj = (try? JSONDecoder().decode([String: JSONValue].self, from: innerData)) ?? [:]
                probe.recordLoadPayload(innerObj)
                let isRemoteTag = innerObj["backend"]?.stringValue == "BACKEND_TYPE_REMOTE_AICODE"
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data((isRemoteTag ? realBoqChunk : emptyBoqChunk).utf8))
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let client = AntigravityRPCClient(
            host: RemoteHostInstance(
                instanceId: instanceUuid,
                hostname: "MacBook Pro",
                channel: .cloudRelay,
                endpointURL: URL(string: "https://antigravity.google.com/r/\(instanceUuid)")!,
                isOnline: true
            ),
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        let steps = try await client.fetchAllTrajectorySteps(
            cascadeId: cloudCascadeId,
            knownStepCount: 2,
            isCloud: true
        )
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].userInput, "Xcode签名丢失原因分析")
        XCTAssertEqual(steps[1].plannerResponse?.response, "根因是自动签名配置被覆盖。")
        XCTAssertEqual(probe.loadPayloads().count, 2)
        XCTAssertNil(probe.loadPayloads().first?["backend"])
        XCTAssertEqual(probe.loadPayloads().last?["backend"]?.stringValue, "BACKEND_TYPE_REMOTE_AICODE")
    }

    func testDormantCloudTrajectoryRetriesStreamAgentStateUpdatesAfterLoadTrajectoryWake() async throws {
        let instanceUuid = "inst-swift-cloud-wake"
        let cloudCascadeId = "v1/default/jetski_remote_agents_3p_devbox/dormant-swift-wake"
        let state = CompatSendRecoveryProbeState()
        let counter = CompatRequestCounter()

        let emptyStreamBytes = ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream)
        let emptyBoqChunk = "[\"\(emptyStreamBytes.base64EncodedString())\",[[\"content-type\",\"application/connect+json\"]]]"

        let wokeFrame = """
        {"update":{"conversationId":"\(cloudCascadeId)","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0,1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"唤醒云端历史对话"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"云端历史已恢复。"}}]}}}}
        """
        var wokeStreamBytes = Data()
        wokeStreamBytes.append(ConnectEnvelope.encode(payload: Data(wokeFrame.utf8)))
        wokeStreamBytes.append(ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream))
        let wokeBoqChunk = "[\"\(wokeStreamBytes.base64EncodedString())\",[[\"content-type\",\"application/connect+json\"]]]"

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            counter.record(path: path)
            if path.hasSuffix("/ListInstances") {
                let listJson = "[[[\"\(instanceUuid)\",[\"MacBook Pro\",\"2.34.0\",true],1,[1740000000,0]]],5]"
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/StreamProxyCommand") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                let body = state.isWoken(cloudCascadeId) ? wokeBoqChunk : emptyBoqChunk
                return (resp, Data(body.utf8))
            }
            if path.hasSuffix("/ProxyCommand") {
                let arr = (try? JSONDecoder().decode([JSONValue].self, from: bodyData)) ?? []
                let rpcPath = arr.count > 1 ? (arr[1].stringValue ?? "") : ""
                if rpcPath.hasSuffix("/LoadTrajectory") {
                    state.markWoken(cloudCascadeId)
                    let okB64 = Data("{}".utf8).base64EncodedString()
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                    return (resp, Data("[\"\(okB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                }
                let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data("[5,\"not_found: trajectory not found\"]".utf8))
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let client = AntigravityRPCClient(
            host: RemoteHostInstance(
                instanceId: instanceUuid,
                hostname: "MacBook Pro",
                channel: .cloudRelay,
                endpointURL: URL(string: "https://antigravity.google.com/r/\(instanceUuid)")!,
                isOnline: true
            ),
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        let steps = try await client.fetchAllTrajectorySteps(
            cascadeId: cloudCascadeId,
            knownStepCount: 2,
            isCloud: true
        )
        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(steps[0].userInput, "唤醒云端历史对话")
        XCTAssertEqual(steps[1].plannerResponse?.response, "云端历史已恢复。")
        XCTAssertGreaterThanOrEqual(counter.count(forSuffix: "/StreamProxyCommand"), 2)
    }

    func testDecodeAgentStateStepsUpdateHandlesAlternativeWrappersAndSnakeCaseSteps() throws {
        let rawJSON = """
        {
          "agentStateUpdate": {
            "mainTrajectory": {
              "trajectory": {
                "total_length": 4,
                "steps": [
                  {"type": "CORTEX_STEP_TYPE_USER_INPUT", "status": "CORTEX_STEP_STATUS_DONE", "user_input": {"items": [{"item": {"text": "为什么进来显示空白"}}]}},
                  {"type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE", "status": "CORTEX_STEP_STATUS_DONE", "planner_response": {"modified_response": "已定位根因并修复"}}
                ]
              }
            }
          }
        }
        """
        let decodedMap = try JSONDecoder().decode([String: JSONValue].self, from: Data(rawJSON.utf8))
        let update = AntigravityRPCClient.decodeAgentStateStepsUpdate(decodedMap, cascadeId: "v1/alt")
        XCTAssertTrue(update.hasMainTrajectoryUpdate)
        XCTAssertEqual(update.totalLength, 4)
        XCTAssertEqual(update.steps.count, 2)
        XCTAssertEqual(update.steps[0].userInput, "为什么进来显示空白")
        XCTAssertEqual(update.steps[1].plannerResponse?.response, "已定位根因并修复")
    }

    func testSwiftCloudStreamRequestsProdUiEmptyMetadataAndConnectGzipAndDecodesPageBounds() async throws {
        let instanceUuid = "inst-swift-prod-ui"
        let cloudCid = "v1/default/jetski_remote_agents_3p_devbox/swift-prod-ui"
        let probe = CompatCloudWakeProbeState()

        // Verify streaming request carries connect-accept-encoding:gzip and NOT accept-encoding:gzip
        let encodedStream = try CloudRelayJSPBCodec.encodeProxyCommandRequest(
            targetInstanceUuid: instanceUuid,
            rpcPath: "/exa.language_server_pb.LanguageServerService/StreamAgentStateUpdates",
            payload: ConnectEnvelope.encode(payload: Data("{\"conversationId\":\"\(cloudCid)\"}".utf8)),
            contentType: "application/connect+json",
            isStreaming: true
        )
        let streamText = (String(data: encodedStream, encoding: .utf8) ?? "").replacingOccurrences(of: "\\/", with: "/")
        XCTAssertTrue(streamText.contains("[\"connect-accept-encoding\",\"gzip\"]"), "Streaming proxy request should advertise connect-accept-encoding:gzip")
        XCTAssertFalse(streamText.contains("[\"accept-encoding\",\"gzip\"]"), "Streaming proxy request must NOT send HTTP accept-encoding:gzip")

        // Verify decodeAgentStateStepsUpdate honors pageBounds.startIndex when indices array is omitted
        let pagedFrame = """
        {"update":{"conversationId":"\(cloudCid)","mainTrajectoryUpdate":{"stepsUpdate":{"pageBounds":{"startIndex":50},"totalLength":52,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Tail 50"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Tail 51"}}]}}}}
        """
        let pagedObj = try JSONDecoder().decode([String: JSONValue].self, from: Data(pagedFrame.utf8))
        let pagedUpdate = AntigravityRPCClient.decodeAgentStateStepsUpdate(pagedObj, cascadeId: cloudCid)
        XCTAssertEqual(pagedUpdate.steps.count, 2)
        XCTAssertEqual(pagedUpdate.steps[0].stepIndex, 50)
        XCTAssertEqual(pagedUpdate.steps[1].stepIndex, 51)

        // Verify live Cloud StreamAgentStateUpdates sends PROD_UI verbosity + empty metadata page bounds
        let okFrame = """
        {"update":{"conversationId":"\(cloudCid)","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0,1],"totalLength":2,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Fast Cloud load"}},{"type":"CORTEX_STEP_TYPE_PLANNER_RESPONSE","status":"CORTEX_STEP_STATUS_DONE","plannerResponse":{"response":"Opened in 2s"}}]}}}}
        """
        var streamBytes = Data()
        streamBytes.append(ConnectEnvelope.encode(payload: Data(okFrame.utf8)))
        streamBytes.append(ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream))
        let okBoq = "[\"\(streamBytes.base64EncodedString())\",[[\"content-type\",\"application/connect+json\"]]]"

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            if path.hasSuffix("/ListInstances") {
                let listJson = "[[[\"\(instanceUuid)\",[\"MacBook Pro\",\"2.33.0\",true],1,[1740000000,0]]],5]"
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/StreamProxyCommand") {
                let arr = (try? JSONDecoder().decode([JSONValue].self, from: bodyData)) ?? []
                let b64Inner = arr.count > 2 ? (arr[2].stringValue ?? "") : ""
                let framed = CloudRelayJSPBCodec.decodeBase64Flexible(b64Inner) ?? Data()
                let innerData = framed.count > 5 ? framed.subdata(in: 5..<framed.count) : Data("{}".utf8)
                let innerObj = (try? JSONDecoder().decode([String: JSONValue].self, from: innerData)) ?? [:]
                probe.recordLoadPayload(innerObj)
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(okBoq.utf8))
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let client = AntigravityRPCClient(
            host: RemoteHostInstance(
                instanceId: instanceUuid,
                hostname: "MacBook Pro",
                channel: .cloudRelay,
                endpointURL: URL(string: "https://antigravity.google.com/r/\(instanceUuid)")!,
                isOnline: true
            ),
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        let steps = try await client.fetchAllTrajectorySteps(cascadeId: cloudCid, knownStepCount: 2, isCloud: true)
        XCTAssertEqual(steps.count, 2)
        let reqPayload = try XCTUnwrap(probe.loadPayloads().first)
        XCTAssertEqual(reqPayload["trajectoryVerbosity"]?.stringValue, "CLIENT_TRAJECTORY_VERBOSITY_PROD_UI")
        XCTAssertEqual(reqPayload["initialGeneratorMetadatasPageBounds"]?.objectValue?["endIndexExclusive"]?.intValue, 0)
        XCTAssertEqual(reqPayload["initialExecutorMetadatasPageBounds"]?.objectValue?["endIndexExclusive"]?.intValue, 0)
    }

    func testSwiftCloudStreamSelfHealsUnknownOptionalFieldsFromDirectJsonError() async throws {
        let instanceUuid = "inst-swift-self-heal"
        let cloudCid = "v1/default/jetski_remote_agents_3p_devbox/swift-older-schema"
        let counter = CompatRequestCounter()

        let okFrame = """
        {"update":{"conversationId":"\(cloudCid)","mainTrajectoryUpdate":{"stepsUpdate":{"indices":[0],"totalLength":1,"steps":[{"type":"CORTEX_STEP_TYPE_USER_INPUT","status":"CORTEX_STEP_STATUS_DONE","userInput":{"text":"Swift self-healed"}}]}}}}
        """
        var okStream = Data()
        okStream.append(ConnectEnvelope.encode(payload: Data(okFrame.utf8)))
        okStream.append(ConnectEnvelope.encode(payload: Data("{}".utf8), flags: .endStream))
        let okBoq = "[\"\(okStream.base64EncodedString())\",[[\"content-type\",\"application/connect+json\"]]]"

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            counter.record(path: path)
            if path.hasSuffix("/ListInstances") {
                let listJson = "[[[\"\(instanceUuid)\",[\"Older Mac\",\"2.26.0\",true],1,[1740000000,0]]],5]"
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/StreamProxyCommand") {
                let arr = (try? JSONDecoder().decode([JSONValue].self, from: bodyData)) ?? []
                let b64Inner = arr.count > 2 ? (arr[2].stringValue ?? "") : ""
                let framed = CloudRelayJSPBCodec.decodeBase64Flexible(b64Inner) ?? Data()
                let innerData = framed.count > 5 ? framed.subdata(in: 5..<framed.count) : Data("{}".utf8)
                let innerObj = (try? JSONDecoder().decode([String: JSONValue].self, from: innerData)) ?? [:]
                let rejected = ["initialGeneratorMetadatasPageBounds", "initialExecutorMetadatasPageBounds", "trajectoryVerbosity"]
                    .first(where: { innerObj[$0] != nil })
                if let rejected {
                    let errJson = "{\"code\":\"invalid_argument\",\"message\":\"unknown field \\\"\(rejected)\\\"\"}"
                    let errB64 = Data(errJson.utf8).base64EncodedString()
                    let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                    return (resp, Data("[\"\(errB64)\",[[\"content-type\",\"application/json\"]]]".utf8))
                }
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(okBoq.utf8))
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let client = AntigravityRPCClient(
            host: RemoteHostInstance(
                instanceId: instanceUuid,
                hostname: "Older Mac",
                channel: .cloudRelay,
                endpointURL: URL(string: "https://antigravity.google.com/r/\(instanceUuid)")!,
                isOnline: true
            ),
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        let steps = try await client.fetchAllTrajectorySteps(cascadeId: cloudCid, knownStepCount: 1, isCloud: true)
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].userInput, "Swift self-healed")
        XCTAssertEqual(counter.count(forSuffix: "/StreamProxyCommand"), 4)
    }

    func testSwiftCloudStreamGrpcWeb80TrailerAndInnerHeaderErrorAndPreservesCloudDiagnostics() async throws {
        // 1. Inner header error capture in CloudRelayJSPBStreamParser
        var headerParser = CloudRelayJSPBStreamParser()
        let innerErrBytes = Data("[[null,[[\":status\",\"503\"],[\"grpc-status\",\"14\"],[\"grpc-message\",\"relay%20overloaded\"]]]]".utf8)
        XCTAssertTrue(headerParser.feed(innerErrBytes).isEmpty)
        if case let .httpError(statusCode, body)? = headerParser.lastInnerHeaderError() {
            XCTAssertEqual(statusCode, 503)
            XCTAssertEqual(body, "relay overloaded")
        } else {
            XCTFail("Expected HTTP 503 inner header error")
        }

        // 2. gRPC-Web 0x80 trailer inside StreamProxyCommand surfaces true 500 error over local 404 fallback
        let instanceUuid = "inst-swift-grpc-80"
        let cloudCid = "v1/default/jetski_remote_agents_3p_devbox/swift-grpc-diag"
        let counter = CompatRequestCounter()
        let probe = CompatTrajectoryProbeState()

        let grpcTrailer = ConnectEnvelope.encode(
            payload: Data("grpc-status: 13\r\ngrpc-message: remote%20agent%20proxy%20failed\r\n".utf8),
            flags: .grpcWebTrailer
        )
        let grpcBoq = "[\"\(grpcTrailer.base64EncodedString())\",[[\"content-type\",\"application/grpc-web+json\"]]]"

        let session = makeMockSession { req in
            let path = req.url?.path ?? ""
            let bodyData = CompatMockURLProtocol.readBody(from: req)
            counter.record(path: path)
            if path.hasSuffix("/ListInstances") {
                let listJson = "[[[\"\(instanceUuid)\",[\"MacBook Pro\",\"2.33.0\",true],1,[1740000000,0]]],5]"
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(listJson.utf8))
            }
            if path.hasSuffix("/StreamProxyCommand") {
                let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data(grpcBoq.utf8))
            }
            if path.hasSuffix("/ProxyCommand") {
                let bodyText = String(data: bodyData, encoding: .utf8) ?? ""
                if bodyText.contains("application/proto") {
                    probe.recordProto()
                }
                let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json+protobuf"])!
                return (resp, Data("[5,\"not_found: trajectory not found\"]".utf8))
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data())
        }

        let client = AntigravityRPCClient(
            host: RemoteHostInstance(
                instanceId: instanceUuid,
                hostname: "MacBook Pro",
                channel: .cloudRelay,
                endpointURL: URL(string: "https://antigravity.google.com/r/\(instanceUuid)")!,
                isOnline: true
            ),
            sessionCookie: "SAPISID=test_sapisid; SID=test_sid",
            relayApiKey: "AI" + "zaSyVALIDKEY0000000000000000000000000",
            urlSession: session
        )

        _ = try await client.resolveCloudRelayInstance()
        XCTAssertEqual(counter.count(forSuffix: "/ListInstances"), 1)

        do {
            _ = try await client.fetchAllTrajectorySteps(cascadeId: cloudCid, knownStepCount: 10, isCloud: true)
            XCTFail("Expected Cloud gRPC-Web 500 error to be thrown")
        } catch let AntigravityRPCError.httpError(code, body) {
            XCTAssertEqual(code, 500, "Must preserve gRPC-Web 0x80 internal error instead of local 404")
            XCTAssertTrue(body.contains("remote agent proxy failed"), "Unexpected body: \(body)")
        }
        XCTAssertEqual(probe.protoCount(), 0, "Cloud fallback must NOT invoke Binary Protobuf Fallback B")
        XCTAssertEqual(counter.count(forSuffix: "/ListInstances"), 1, "Must NOT trigger extra ListInstances refresh on Cloud trajectory 404/500")
    }
}

// MARK: - Swift 6 Strict-Concurrency Mock URLProtocol Helpers

private final class CompatMockHandlerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    func setHandler(_ newHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?) {
        lock.lock()
        defer { lock.unlock() }
        handler = newHandler
    }

    func getHandler() -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}

private final class CompatRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func record(path: String) {
        lock.lock()
        defer { lock.unlock() }
        paths.append(path)
    }

    func count(forSuffix suffix: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return paths.filter { $0.hasSuffix(suffix) }.count
    }
}

private final class CompatTrajectoryProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private var protoRequests: Int = 0
    private var jsonRequests: Int = 0
    private var returnUnknownStep: Bool = false
    private var recordedJsonStepOffset: Int? = nil

    func recordProto() {
        lock.lock()
        defer { lock.unlock() }
        protoRequests += 1
    }

    func recordJSON(stepOffset: Int?) {
        lock.lock()
        defer { lock.unlock() }
        jsonRequests += 1
        recordedJsonStepOffset = stepOffset
    }

    func protoCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return protoRequests
    }

    func jsonCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return jsonRequests
    }

    func lastJsonStepOffset() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return recordedJsonStepOffset
    }

    func resetCounts() {
        lock.lock()
        defer { lock.unlock() }
        protoRequests = 0
        jsonRequests = 0
        recordedJsonStepOffset = nil
    }

    func setReturnUnknownStep(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        returnUnknownStep = enabled
    }

    func shouldReturnUnknownStep() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return returnUnknownStep
    }
}

private final class CompatMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let storage = CompatMockHandlerBox()

    static func readBody(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
        }
        return out
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.storage.getHandler() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class CompatCloudWakeProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private var listInstancesCalls: Int = 0
    private var wokenCascadeIds = Set<String>()
    private var recordedLoadPayloads: [[String: JSONValue]] = []

    func recordListInstances() {
        lock.lock()
        defer { lock.unlock() }
        listInstancesCalls += 1
    }

    func listInstancesCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return listInstancesCalls
    }

    func markWoken(_ cascadeId: String) {
        lock.lock()
        defer { lock.unlock() }
        wokenCascadeIds.insert(cascadeId)
    }

    func isWoken(_ cascadeId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return wokenCascadeIds.contains(cascadeId)
    }

    func recordLoadPayload(_ payload: [String: JSONValue]) {
        lock.lock()
        defer { lock.unlock() }
        recordedLoadPayloads.append(payload)
    }

    func loadPayloads() -> [[String: JSONValue]] {
        lock.lock()
        defer { lock.unlock() }
        return recordedLoadPayloads
    }

    func clearLoadPayloads() {
        lock.lock()
        defer { lock.unlock() }
        recordedLoadPayloads.removeAll()
    }
}

private final class CompatSendRecoveryProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private var wokenCascadeIds = Set<String>()
    private var recordedSendTargets: [String] = []
    private var recordedCancelTargets: [String] = []

    func markWoken(_ cascadeId: String) {
        lock.lock()
        defer { lock.unlock() }
        wokenCascadeIds.insert(cascadeId)
    }

    func isWoken(_ cascadeId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return wokenCascadeIds.contains(cascadeId)
    }

    func recordSendTarget(_ uuid: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedSendTargets.append(uuid)
    }

    func recordCancelTarget(_ uuid: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedCancelTargets.append(uuid)
    }

    func sendTargets() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSendTargets
    }

    func cancelTargets() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCancelTargets
    }

    func clearTargets() {
        lock.lock()
        defer { lock.unlock() }
        recordedSendTargets.removeAll()
        recordedCancelTargets.removeAll()
    }
}
