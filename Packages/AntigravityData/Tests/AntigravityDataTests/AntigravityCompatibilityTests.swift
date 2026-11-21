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
