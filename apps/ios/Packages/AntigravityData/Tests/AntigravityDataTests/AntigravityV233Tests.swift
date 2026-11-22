import XCTest
@testable import AntigravityData

final class AntigravityV233Tests: XCTestCase {

    // MARK: - Protobuf Wire Test Helpers

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

    // MARK: - TC-17: Cloud Relay Payload Integrity & Real Diff Parser

    func testTC17_CloudRelaySanitizerPreservesV233FieldsAndParsesUnifiedDiff() async throws {
        let host = RemoteHostInstance(
            instanceId: "relay-v233",
            hostname: "Antigravity Cloud",
            channel: .cloudRelay,
            endpointURL: URL(string: "https://antigravity.google.com/r/relay-v233")!,
            isOnline: true
        )
        let client = AntigravityRPCClient(
            host: host,
            sessionCookie: "SAPISID=test-cookie-value"
        )

        let rawMessageBody: [String: JSONValue] = [
            "cascadeId": .string("cas-rate-limiter"),
            "items": .array([
                .object(["text": .string("Run load test")]),
                .object(["file": .object(["absolutePathUri": .string("file:///code/ratelimit.go")])]),
                .object(["media": .object(["mimeType": .string("image/png"), "inlineDataBase64": .string("iVBORw0KGgo=")])]),
                .object(["codeQuote": .object(["filePath": .string("ratelimit.go"), "snippet": .string("const ttl = cfg.BucketTTL")])])
            ]),
            "cascadeConfig": .object([
                "plannerConfig": .object([
                    "requestedModel": .object(["model": .string("MODEL_GOOGLE_GEMINI_4_NEON")]),
                    "thinkingEffort": .string("xhigh"),
                    "agentPersona": .string("go-reviewer"),
                    "permissionPreset": .string("PERMISSION_PRESET_DEFAULT")
                ])
            ])
        ]

        let sanitized = try await client.sanitizeCloudRelayPayload(
            method: "SendUserCascadeMessage",
            body: rawMessageBody
        )
        let items = try XCTUnwrap(sanitized["items"]?.arrayValue)
        XCTAssertEqual(items.count, 4, "Cloud Relay sanitizer must preserve text, file, media, and codeQuote items")
        let plannerCfg = sanitized["cascadeConfig"]?.objectValue?["plannerConfig"]?.objectValue
        XCTAssertEqual(plannerCfg?["thinkingEffort"]?.stringValue, "xhigh")
        XCTAssertEqual(plannerCfg?["agentPersona"]?.stringValue, "go-reviewer")
        XCTAssertEqual(plannerCfg?["permissionPreset"]?.stringValue, "PERMISSION_PRESET_DEFAULT")

        // Local-only OpenWorkspaceInFinder must return HTTP 501 instead of faking {"ok": true}
        do {
            try await client.openWorkspaceInFinder(workspaceUri: "file:///Users/dev/code/ledger-svc")
            XCTFail("OpenWorkspaceInFinder must throw 501 on Cloud Relay")
        } catch AntigravityRPCError.httpError(let statusCode, _) {
            XCTAssertEqual(statusCode, 501)
        } catch {
            XCTFail("Unexpected error for OpenWorkspaceInFinder on Cloud Relay: \(error)")
        }

        // Real unified diff parsing
        let unified = """
        --- a/middleware/ratelimit.go
        +++ b/middleware/ratelimit.go
        @@ -22,4 +22,5 @@ Allow
         func (l *Limiter) Allow(tenant string) bool {
        -    const ttl = 5 * time.Minute
        +    const ttl = cfg.BucketTTL
        +    now := l.clock.Now()
        """
        let lines = AntigravityRPCClient.parseUnifiedDiffText(unified)
        XCTAssertEqual(lines.filter { $0.kind == .hunkHeader }.count, 1)
        XCTAssertEqual(lines.filter { $0.kind == .deletion }.count, 1)
        XCTAssertEqual(lines.filter { $0.kind == .addition }.count, 2)
        XCTAssertEqual(lines.filter { $0.kind == .context }.count, 1)
    }

    // MARK: - TC-18: Gemini 4, Orchestrator, Extra Thinking & Dual-Pool Quota

    func testTC18_Gemini4AndOrchestratorCatalogWithExtraThinkingAndDualQuota() {
        let liveModels = CascadeModelConfig.liveDefaultCatalog
        XCTAssertTrue(liveModels.contains(where: { $0.id == "MODEL_GOOGLE_GEMINI_4_NEON" }))
        XCTAssertTrue(liveModels.contains(where: { $0.id == "MODEL_GOOGLE_GEMINI_4_CARBON" }))
        XCTAssertTrue(liveModels.contains(where: { $0.id == "MODEL_GOOGLE_GEMINI_4_ARGON" }))
        XCTAssertTrue(liveModels.contains(where: { $0.id == "MODEL_GOOGLE_GEMINI_4_HYDROGEN" }))

        let orchestrator = liveModels.first(where: { $0.isOrchestrator })
        XCTAssertNotNil(orchestrator)
        XCTAssertEqual(orchestrator?.plannerModelName, "Gemini 4 Neon")
        XCTAssertEqual(orchestrator?.executorModelName, "Gemini 4 Hydrogen")

        XCTAssertEqual(ThinkingEffortLevel.extra.cliValue, "xhigh")
        XCTAssertEqual(ThinkingEffortLevel.extra.protoWireValue, "XHIGH")
        XCTAssertEqual(ThinkingEffortLevel.allCases.count, 4)

        // Preserve ESDD verification catalog unchanged
        XCTAssertGreaterThanOrEqual(CascadeModelConfig.catalog.count, 3)

        // Dual-pool quota calculation & clamping
        let quota = ModelUsageQuota(
            geminiWeeklyRemaining: 0.84,
            geminiFiveHourRemaining: 1.4,
            partnerWeeklyRemaining: 0.68,
            partnerFiveHourRemaining: -0.2,
            aiCreditOveragesEnabled: true,
            planDisplayName: "Google AI Ultra"
        )
        XCTAssertEqual(quota.geminiWeeklyPercent, 84)
        XCTAssertEqual(quota.geminiFiveHourPercent, 100)
        XCTAssertEqual(quota.partnerWeeklyPercent, 68)
        XCTAssertEqual(quota.partnerFiveHourPercent, 0)
        XCTAssertTrue(quota.aiCreditOveragesEnabled)
    }

    // MARK: - TC-19: Protobuf Step Decoder v2.33 Steps & Real Permission Fields

    func testTC19_ProtobufStepCodecDecodesV233StepsAndRealPermissionInteractions() throws {
        // Step 0: Subagent (field 130) + PermissionInteraction (field 56 -> 21)
        var permSpec = Data()
        permSpec.append(encodeStringField(1, string: "write_file"))
        permSpec.append(encodeStringField(2, string: "/etc/hosts"))
        permSpec.append(encodeStringField(3, string: "Outside workspace"))
        permSpec.append(encodeStringField(4, string: "GitHub"))
        permSpec.append(encodeVarintField(5, value: 1))

        let reqInteractionPerm = encodeLengthField(21, payload: permSpec)

        var subagentMsg = Data()
        subagentMsg.append(encodeStringField(1, string: "sub-01"))
        subagentMsg.append(encodeStringField(2, string: "Security Auditor"))
        subagentMsg.append(encodeStringField(3, string: "research"))
        subagentMsg.append(encodeStringField(4, string: "Auditing CSP headers"))
        subagentMsg.append(encodeStringField(5, string: "Gemini 4 Argon"))

        var step0 = Data()
        step0.append(encodeVarintField(4, value: 9)) // WAITING
        step0.append(encodeLengthField(56, payload: reqInteractionPerm))
        step0.append(encodeLengthField(130, payload: subagentMsg))

        // Step 1: DynamicWorkflow (field 131) + WorkflowScriptInteraction (field 56 -> 27)
        var wfScriptSpec = Data()
        wfScriptSpec.append(encodeStringField(1, string: "Release Pipeline"))
        wfScriptSpec.append(encodeStringField(2, string: "import agy\nagy.run('tests')"))
        wfScriptSpec.append(encodeStringField(3, string: "Build"))
        wfScriptSpec.append(encodeStringField(3, string: "Verify"))

        var wfMsg = Data()
        wfMsg.append(encodeStringField(1, string: "wf-release"))
        wfMsg.append(encodeStringField(2, string: "Multi-phase CI verification"))
        wfMsg.append(encodeStringField(3, string: "import agy\nagy.run('tests')"))
        wfMsg.append(encodeStringField(4, string: "Build"))
        wfMsg.append(encodeStringField(4, string: "Verify"))

        var step1 = Data()
        step1.append(encodeVarintField(4, value: 9)) // WAITING
        step1.append(encodeLengthField(56, payload: encodeLengthField(27, payload: wfScriptSpec)))
        step1.append(encodeLengthField(131, payload: wfMsg))

        // Step 2: SwarmBoard (field 132) + DownloadUrlInteraction (field 56 -> 25)
        var dlSpec = Data()
        dlSpec.append(encodeStringField(1, string: "https://artifacts.example.com/report.pdf"))
        dlSpec.append(encodeStringField(2, string: "artifacts.example.com"))
        dlSpec.append(encodeStringField(3, string: "report.pdf"))
        dlSpec.append(encodeStringField(4, string: "application/pdf"))
        dlSpec.append(encodeStringField(5, string: "~/Downloads"))

        var swarmMsg = Data()
        swarmMsg.append(encodeStringField(1, string: "swarm-1"))
        swarmMsg.append(encodeStringField(2, string: "Checkout Migration Swarm"))
        swarmMsg.append(encodeStringField(3, string: "Frontend Specialist"))
        swarmMsg.append(encodeStringField(3, string: "Security Reviewer"))

        var step2 = Data()
        step2.append(encodeVarintField(4, value: 9)) // WAITING
        step2.append(encodeLengthField(56, payload: encodeLengthField(25, payload: dlSpec)))
        step2.append(encodeLengthField(132, payload: swarmMsg))

        // Step 3: McpToolCall (field 133) + BrowserUploadInteraction (field 56 -> 26)
        var uploadSpec = Data()
        uploadSpec.append(encodeStringField(1, string: "https://portal.example.com"))
        uploadSpec.append(encodeStringField(2, string: "invoice.pdf"))

        var mcpMsg = Data()
        mcpMsg.append(encodeStringField(1, string: "github"))
        mcpMsg.append(encodeStringField(2, string: "create_pull_request"))
        mcpMsg.append(encodeStringField(3, string: "{\"title\":\"v2.33\"}"))
        mcpMsg.append(encodeStringField(4, string: "{\"number\":42}"))
        mcpMsg.append(encodeStringField(5, string: "GitHub"))

        var step3 = Data()
        step3.append(encodeVarintField(4, value: 3)) // DONE
        step3.append(encodeLengthField(56, payload: encodeLengthField(26, payload: uploadSpec)))
        step3.append(encodeLengthField(133, payload: mcpMsg))

        var response = Data()
        response.append(encodeLengthField(1, payload: step0))
        response.append(encodeLengthField(1, payload: step1))
        response.append(encodeLengthField(1, payload: step2))
        response.append(encodeLengthField(1, payload: step3))

        let decoded = ProtobufStepCodec.decodeStepsResponse(response, cascadeId: "cas-v233")
        XCTAssertEqual(decoded.count, 4)

        XCTAssertEqual(decoded[0].type, .subagentInvocation)
        XCTAssertEqual(decoded[0].subagent?.role, "Security Auditor")
        XCTAssertEqual(decoded[0].requestedInteraction?.kind, .permission)
        XCTAssertEqual(decoded[0].requestedInteraction?.permission?.action, "write_file")
        XCTAssertEqual(decoded[0].requestedInteraction?.permission?.target, "/etc/hosts")
        XCTAssertEqual(decoded[0].requestedInteraction?.permission?.pluginName, "GitHub")

        XCTAssertEqual(decoded[1].type, .dynamicWorkflow)
        XCTAssertEqual(decoded[1].dynamicWorkflow?.phases.map(\.name), ["Build", "Verify"])
        XCTAssertEqual(decoded[1].requestedInteraction?.kind, .workflowScript)
        XCTAssertEqual(decoded[1].requestedInteraction?.workflowScript?.title, "Release Pipeline")

        XCTAssertEqual(decoded[2].type, .swarmBoard)
        XCTAssertEqual(decoded[2].swarmBoard?.members.count, 2)
        XCTAssertEqual(decoded[2].requestedInteraction?.kind, .downloadUrl)
        XCTAssertEqual(decoded[2].requestedInteraction?.downloadUrl?.fileName, "report.pdf")

        XCTAssertEqual(decoded[3].type, .mcpToolCall)
        XCTAssertEqual(decoded[3].mcpToolCall?.serverName, "github")
        XCTAssertEqual(decoded[3].mcpToolCall?.toolName, "create_pull_request")
        XCTAssertEqual(decoded[3].requestedInteraction?.kind, .browserUpload)
        XCTAssertEqual(decoded[3].requestedInteraction?.browserUpload?.fileNames, ["invoice.pdf"])
    }

    // MARK: - TC-20: InteractionBuilder Scopes & Non-Auto-Accept Safety

    func testTC20_InteractionBuilderV233ScopesAndSafetyGates() throws {
        let permStep = CascadeStep(
            cascadeId: "cas-perm",
            stepIndex: 3,
            type: .runCommand,
            status: .waiting,
            requestedInteraction: RequestedInteraction(
                kind: .permission,
                permission: PermissionInteractionSpec(
                    action: "write_file",
                    target: "/tmp/out.json",
                    suggestedPersistPattern: "/tmp/*",
                    persistSuggestionType: .suggested
                )
            )
        )
        let convPayload = try XCTUnwrap(InteractionBuilder.buildPayload(step: permStep, decision: .allowInConversation))
        XCTAssertEqual(convPayload.permission?.scope, "PERMISSION_SCOPE_CONVERSATION")
        XCTAssertEqual(convPayload.permission?.grantPatterns, ["write_file(/tmp/*)"])

        let alwaysPayload = try XCTUnwrap(InteractionBuilder.buildPayload(step: permStep, decision: .alwaysAllow))
        XCTAssertEqual(alwaysPayload.permission?.scope, "PERMISSION_SCOPE_ALWAYS")

        // Sensitive v2.33 gates must NEVER auto-accept and browserUpload/workflowScript force ONCE scope
        let dangerousKinds: [RequestedInteraction] = [
            RequestedInteraction(kind: .executeUrl, executeUrl: ExecuteUrlInteractionSpec(url: "https://bank.example", domain: "bank.example")),
            RequestedInteraction(kind: .downloadUrl, downloadUrl: DownloadUrlInteractionSpec(url: "https://x.test/a.dmg", origin: "x.test", fileName: "a.dmg")),
            RequestedInteraction(kind: .browserUpload, browserUpload: BrowserUploadInteractionSpec(origin: "https://x.test", fileNames: ["secret.csv"])),
            RequestedInteraction(kind: .workflowScript, workflowScript: WorkflowScriptInteractionSpec(title: "wf", pythonScript: "print(1)")),
            RequestedInteraction(kind: .mcp, mcpServerName: "github", mcpToolName: "delete_branch")
        ]
        for req in dangerousKinds {
            let step = CascadeStep(
                cascadeId: "cas-safe",
                stepIndex: 4,
                type: .ephemeralMessage,
                status: .waiting,
                requestedInteraction: req
            )
            XCTAssertFalse(
                InteractionBuilder.canSafeAutoAccept(step: step, allowedWorkspaceRoots: ["file:///"]),
                "Kind \(req.kind.rawValue) must NEVER be eligible for Safe Auto-Accept"
            )
        }

        let uploadStep = CascadeStep(
            cascadeId: "cas-up",
            stepIndex: 6,
            type: .ephemeralMessage,
            status: .waiting,
            requestedInteraction: dangerousKinds[2]
        )
        let uploadPayload = try XCTUnwrap(InteractionBuilder.buildPayload(step: uploadStep, decision: .alwaysAllow))
        XCTAssertEqual(uploadPayload.approvalScope, "PERMISSION_SCOPE_ONCE")
    }

    // MARK: - TC-21: Side Questions (/btw), Queued Messages & Revert

    @MainActor
    func testTC21_SideQuestionBTWQueuedMessagesAndRevert() {
        let store = AntigravitySessionStore.makeESDDVerificationStore()
        let initialStepCount = store.activeSteps.count

        // /btw side question must NOT mutate main trajectory
        store.openSideQuestion()
        store.sendSideQuestion("Does Limiter.Allow hold mutex across clock calls?")
        XCTAssertEqual(store.activeSteps.count, initialStepCount)
        XCTAssertFalse(store.sideQuestionThread.messages.isEmpty)

        // Insert side-question answer into composer draft
        store.sideQuestionThread.messages.append(
            SideQuestionMessage(isUser: false, text: "Yes, mutex wraps clock.Now().")
        )
        store.composerDraftText = ""
        store.insertSideQuestionAnswerIntoMain()
        XCTAssertTrue(store.composerDraftText.contains("mutex wraps clock.Now()"))

        // Queued follow-up message edit, remove & flush
        store.enqueueFollowUpMessage("First queued follow-up")
        store.enqueueFollowUpMessage("Second queued follow-up")
        XCTAssertEqual(store.queuedMessages.count, 2)
        let firstId = store.queuedMessages[0].id
        store.updateQueuedMessage(id: firstId, newText: "Edited queued follow-up")
        XCTAssertEqual(store.queuedMessages[0].text, "Edited queued follow-up")
        store.removeQueuedMessage(id: store.queuedMessages[1].id)
        XCTAssertEqual(store.queuedMessages.count, 1)

        // Revert conversation to earlier step index
        store.revertConversationToStep(2)
        XCTAssertTrue(store.activeSteps.allSatisfy { $0.stepIndex <= 2 })
    }

    // MARK: - TC-22: Markdown Frontmatter, Diagrams, Images, GitHub PR Pills & Jupyter Parser

    func testTC22_MarkdownFrontmatterImagesPRLinksAndJupyterParser() throws {
        let md = """
        ---
        title: Settlement Architecture
        owner: platform-core
        ---

        # Overview

        Track PR https://github.com/venciallee/iOSAntigravity/pull/42 before merging.

        ![Latency Graph](https://cdn.example.com/p99.png)

        ```mermaid
        flowchart LR
          A[iOS] --> B[Cloud Relay]
        ```
        """
        let blocks = AntigravityMarkdownParser.parse(md)
        if case .frontmatter(_, let entries) = blocks.first {
            XCTAssertEqual(entries.first?.key, "title")
            XCTAssertEqual(entries.first?.value, "Settlement Architecture")
        } else {
            XCTFail("Expected leading YAML frontmatter block")
        }

        let hasMermaid = blocks.contains(where: \.isMermaidDiagram)
        XCTAssertTrue(hasMermaid)

        let prs = AntigravityMarkdownParser.extractGitHubPRLinks(from: md)
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs[0].ownerRepo, "venciallee/iOSAntigravity")
        XCTAssertEqual(prs[0].number, 42)

        let ipynb = """
        {
          "metadata": { "kernelspec": { "display_name": "Python 3.11" } },
          "cells": [
            { "id": "m1", "cell_type": "markdown", "source": ["# Benchmark"] },
            {
              "id": "c1",
              "cell_type": "code",
              "execution_count": 3,
              "source": ["print(42)\\n"],
              "outputs": [
                { "output_type": "stream", "text": ["42\\n"] }
              ]
            }
          ]
        }
        """
        let doc = try XCTUnwrap(JupyterNotebookDocument.parse(jsonString: ipynb))
        XCTAssertEqual(doc.kernelName, "Python 3.11")
        XCTAssertEqual(doc.cells.count, 2)
        XCTAssertEqual(doc.cells[1].executionCount, 3)
        XCTAssertEqual(doc.cells[1].outputs.first?.text, "42\n")
    }

    // MARK: - TC-23: Slash Commands, Typo-Tolerant Mentions & Persisted Preferences

    @MainActor
    func testTC23_SlashCommandsTypoTolerantMentionsAndLocalProjectionPersistence() async {
        let localCmds = SlashCommandItem.commands(
            isRemoteAgent: false,
            customSkills: [SkillSummary(name: "antigravity-doc-sync", description: "Sync docs", scope: "Workspace")]
        )
        XCTAssertFalse(localCmds.contains(where: { $0.command == "/btw" }))
        XCTAssertTrue(localCmds.contains(where: { $0.command == "/swarm" }))
        XCTAssertTrue(localCmds.contains(where: { $0.command == "/run-workflow" }))
        XCTAssertTrue(localCmds.contains(where: { $0.command == "/voice" }))
        XCTAssertTrue(localCmds.contains(where: { $0.command == "/antigravity-doc-sync" }))

        let store = AntigravitySessionStore.makeESDDVerificationStore()
        // Typo-tolerant subsequence match: "rtlm" matches ratelimit.go
        let matches = store.filteredMentionCandidates(for: "rtlm")
        XCTAssertTrue(matches.contains(where: { $0.title.lowercased().contains("ratelimit") }))

        // LocalProjectionStore persistence round-trip for v2.33 prefs, quota, customizations
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityV233Prefs-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projStore = LocalProjectionStore(storageDirectory: tempDir)
        let prefs = AppAppearancePreferences(
            interfaceLayout: .knowledgeWork,
            theme: .everforestDark,
            fontSizePt: 16,
            collapsedProjectIds: ["ledger-svc"],
            notificationsEnabled: true,
            suppressManualStopNotification: true,
            globalPermissionPreset: .auto,
            terminalSandboxEnabled: true
        )
        await projStore.saveAppearancePreferences(prefs)
        let loadedPrefs = await projStore.loadAppearancePreferences()
        XCTAssertEqual(loadedPrefs, prefs)

        let quota = ModelUsageQuota(geminiWeeklyRemaining: 0.72, partnerWeeklyRemaining: 0.55)
        await projStore.saveUsageQuota(quota)
        let loadedQuota = await projStore.loadUsageQuota()
        XCTAssertEqual(loadedQuota?.geminiWeeklyPercent, 72)
        XCTAssertEqual(loadedQuota?.partnerWeeklyPercent, 55)

        await projStore.saveCustomizations(.defaultCatalog)
        let loadedCatalog = await projStore.loadCustomizations()
        XCTAssertEqual(loadedCatalog?.plugins.count, CustomizationsCatalog.defaultCatalog.plugins.count)
    }

    // MARK: - TC-24: SharedAppGroupBridge Round-Trip (Live Activity & Share Extension)

    func testTC24_SharedAppGroupBridgeLiveActivityAndShareRoundTrip() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravitySharedBridge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bridge = SharedAppGroupBridge(
            suiteName: "group.com.thousandtimes.agpocket.test.\(UUID().uuidString)",
            storageDirectory: tempDir
        )

        let action = PendingLiveActivityAction(
            cascadeId: "cas-rate-limiter",
            stepIndex: 5,
            kind: .approveWithFaceID
        )
        await bridge.enqueueLiveActivityAction(action)
        let drained = await bridge.drainLiveActivityActions()
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained[0].cascadeId, "cas-rate-limiter")
        XCTAssertEqual(drained[0].kind, .approveWithFaceID)
        let drainedAgain = await bridge.drainLiveActivityActions()
        XCTAssertTrue(drainedAgain.isEmpty)

        let share = PendingSharePayload(
            id: "share-42",
            text: "panic: runtime error: slice bounds out of range",
            urlString: "https://github.com/venciallee/iOSAntigravity/pull/42",
            fileName: "crash.log"
        )
        await bridge.saveSharePayload(share)
        let consumed = await bridge.consumeSharePayload(id: "share-42")
        XCTAssertEqual(consumed, share)
        let consumedAgain = await bridge.consumeSharePayload(id: "share-42")
        XCTAssertNil(consumedAgain)
    }

    // MARK: - TC-25: Notification Policy Suppresses Manual Stop & Honors Toggle

    func testTC25_NotificationPolicySuppressesManualStopAndHonorsPreferences() {
        let defaultPrefs = AppAppearancePreferences(
            notificationsEnabled: true,
            suppressManualStopNotification: true
        )
        XCTAssertTrue(
            NotificationPolicy.shouldNotify(
                previousStatus: .inProgress,
                newStatus: .waiting,
                wasManuallyCancelled: false,
                preferences: defaultPrefs
            )
        )
        XCTAssertTrue(
            NotificationPolicy.shouldNotify(
                previousStatus: .inProgress,
                newStatus: .done,
                wasManuallyCancelled: false,
                preferences: defaultPrefs
            )
        )
        XCTAssertFalse(
            NotificationPolicy.shouldNotify(
                previousStatus: .inProgress,
                newStatus: .cancelled,
                wasManuallyCancelled: true,
                preferences: defaultPrefs
            ),
            "Manual Stop must never emit a noisy completion notification"
        )
        XCTAssertFalse(
            NotificationPolicy.shouldNotify(
                previousStatus: .inProgress,
                newStatus: .done,
                wasManuallyCancelled: true,
                preferences: defaultPrefs
            )
        )
        let mutedPrefs = AppAppearancePreferences(notificationsEnabled: false)
        XCTAssertFalse(
            NotificationPolicy.shouldNotify(
                previousStatus: .inProgress,
                newStatus: .waiting,
                wasManuallyCancelled: false,
                preferences: mutedPrefs
            )
        )
    }

    // MARK: - TC-26: Appearance Mode Switching, Cold-Start Persistence & Legacy Migration

    @MainActor
    func testTC26_AppearanceModeSwitchingPersistenceAndLegacyMigration() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AntigravityV233Appearance-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projStore = LocalProjectionStore(storageDirectory: tempDir)

        // 1. Round-trip .system, .dark, .light through LocalProjectionStore
        for mode in [AppAppearanceMode.system, .dark, .light] {
            let prefs = AppAppearancePreferences(
                interfaceLayout: .softwareEngineering,
                appearanceMode: mode,
                theme: .obsidian
            )
            await projStore.saveAppearancePreferences(prefs)
            let loaded = await projStore.loadAppearancePreferences()
            XCTAssertEqual(loaded?.appearanceMode, mode)
            XCTAssertEqual(loaded, prefs)
        }

        // 2. Legacy JSON without `appearanceMode` migrates Everforest Light -> .light and Matte Obsidian -> .system
        let legacyLightJSON = Data("""
        {
          "interfaceLayout": "Software Engineering",
          "theme": "Everforest Light",
          "fontSizePt": 14,
          "collapsedProjectIds": [],
          "notificationsEnabled": true,
          "suppressManualStopNotification": true,
          "globalPermissionPreset": "default",
          "terminalSandboxEnabled": true
        }
        """.utf8)
        let migratedLight = try JSONDecoder().decode(AppAppearancePreferences.self, from: legacyLightJSON)
        XCTAssertEqual(migratedLight.theme, .everforestLight)
        XCTAssertEqual(migratedLight.appearanceMode, .light)

        let legacyObsidianJSON = Data("""
        {
          "interfaceLayout": "Software Engineering",
          "theme": "Matte Obsidian",
          "fontSizePt": 14,
          "collapsedProjectIds": [],
          "notificationsEnabled": true,
          "suppressManualStopNotification": true,
          "globalPermissionPreset": "default",
          "terminalSandboxEnabled": true
        }
        """.utf8)
        let migratedSystem = try JSONDecoder().decode(AppAppearancePreferences.self, from: legacyObsidianJSON)
        XCTAssertEqual(migratedSystem.theme, .obsidian)
        XCTAssertEqual(migratedSystem.appearanceMode, .system)

        // 3. Synchronous persistence & cold-start anti-flash hydration on frame 1
        let prefsStore = InMemoryPreferencesStore()
        let liveStore1 = AntigravitySessionStore.makeLiveStore(
            projectionStore: projStore,
            secretStore: InMemorySecretStore(),
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(),
            preferencesStore: prefsStore
        )
        XCTAssertEqual(liveStore1.appearancePreferences.appearanceMode, .system)

        liveStore1.setAppearanceMode(.light)
        XCTAssertEqual(liveStore1.appearancePreferences.appearanceMode, .light)
        XCTAssertEqual(
            prefsStore.string(forKey: AntigravitySessionStore.appearanceModeDefaultsKey),
            AppAppearanceMode.light.rawValue
        )

        let liveStore2 = AntigravitySessionStore.makeLiveStore(
            projectionStore: projStore,
            secretStore: InMemorySecretStore(),
            networkMonitor: NoopNetworkReachabilityMonitor(),
            powerStateProvider: StaticPowerStateProvider(),
            preferencesStore: prefsStore
        )
        XCTAssertEqual(
            liveStore2.appearancePreferences.appearanceMode,
            .light,
            "Cold-start makeLiveStore must synchronously hydrate .light from preferencesStore on frame 1"
        )

        // 4. Switching .light -> .dark -> .system updates both store and preferencesStore synchronously
        liveStore2.setAppearanceMode(.dark)
        XCTAssertEqual(liveStore2.appearancePreferences.appearanceMode, .dark)
        XCTAssertEqual(
            prefsStore.string(forKey: AntigravitySessionStore.appearanceModeDefaultsKey),
            AppAppearanceMode.dark.rawValue
        )

        liveStore2.setAppearanceMode(.system)
        XCTAssertEqual(liveStore2.appearancePreferences.appearanceMode, .system)
        XCTAssertEqual(
            prefsStore.string(forKey: AntigravitySessionStore.appearanceModeDefaultsKey),
            AppAppearanceMode.system.rawValue
        )
    }
}
