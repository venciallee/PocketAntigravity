# Test Plan — Antigravity 2.0 (`v2.33.0` P0–P2 Capabilities & Cloud Auto-Sync)

## 1. Automated Verification Layers

1. **Layer 1 — Pure-Cloud Doc Subscription Self-Test (`scripts/sync-antigravity-docs.py --self-test`)**:
   - Validates HTML noise stripping → canonical Markdown, monotonic semver protection (rejecting stale CDN `v2.28.1` when manifest is `v2.33.0`), semantic delta generation, iOS-relevance filtering, and Tier 1 / Tier 2 / Tier 3 classification.
2. **Layer 2 — Swift 6 Package Unit Tests (`Packages/AntigravityData/Tests/AntigravityDataTests/AntigravityV233Tests.swift` via `swift test`)**:
   - Executed on real `macos-15` Xcode 16 / Swift 6 toolchain in GitHub Actions (`macos-xcode-verify.yml`).
3. **Layer 3 — Live & Mock Connect-RPC + Binary Protobuf E2E (`verification/verify-v233-capabilities.py` + `verification/verify-live-rpc-flow.py`)**:
   - Runs against both `mock_language_server.py` and `scripts/mac-companion-bridge.py --standalone-sandbox`.
4. **Layer 4 — Existing 4-Gate ESDD Regression (`verification/esdd-verify.py`) + Real iOS Simulator `XCUITest` (`AntigravityInteractiveUITests.swift`)**:
   - Guarantees zero regressions across `UE01`..`UE13`, `TC-01`..`TC-16`, `CLAIM-01`..`CLAIM-13`, pure Swift 6 isolation, and real iPhone Simulator UI flows.

---

## 2. Executable Test Case Matrix (`TC-17` .. `TC-30`)

| Test ID | Target Req | Scenario | Expected Verification Outcome |
| :--- | :--- | :--- | :--- |
| **`TC-17`** | `FR-P0-01` | Call `GetTurnDiff`, `GetArtifactSnapshots`, `ListAutomations` over both Direct Bridge and Cloud Relay (`ProxyCommand`) | Returns parsed `FilePatchDiff` entries with real hunks/lines/status letters, artifact snapshots, and automations without silent empty short-circuit. |
| **`TC-18`** | `FR-P0-02` | Bind live `AntigravitySessionStore` steps (`askQuestion`, live `ArtifactSnapshot`, live `FilePatchDiff`) into `UE10` / `UE11` / `UE12` | Live views render dynamic server data; submitting answers/comments dispatches real RPCs while verification mode retains deterministic UE fixtures. |
| **`TC-19`** | `FR-P0-03` | Enqueue Live Activity Approve/Deny/Stop and Share Extension payload in `SharedAppGroupBridge` and reconcile in `AntigravitySessionStore` | Pending actions replay idempotently, update step status / outbox, and route `antigravity://share/<id>` directly into composer attachments. |
| **`TC-20`** | `FR-P0-04` | Send Cloud Relay `SendUserCascadeMessage` with `ThinkingEffortLevel.extra`, `agentPersona: "go-reviewer"`, `permissionPreset: .auto`, and rich attachments | `sanitizeCloudRelayPayload` preserves effort, agent persona, permission preset, and file/quote/media items without dropping fields. |
| **`TC-21`** | `FR-P0-05` | Transition session from `.inProgress` → `.waiting` → `.done`, plus manual `.cancelled` | Notification policy emits alert for `.waiting` and `.done`, and suppresses alert when user manually stops turn. |
| **`TC-22`** | `FR-P1-01` | Fetch `GetCascadeModelConfigs` with Gemini 4 Neon / Carbon / Argon / Hydrogen, Orchestrator (Neon/Carbon/Argon), 4 efforts, and dual-pool quota | Catalog populates Gemini 4 & Orchestrator metadata, `ThinkingEffortLevel.extra` (`xhigh`) maps cleanly, and `ModelUsageQuota` exposes Gemini & Claude/GPT Weekly + 5h percentages. |
| **`TC-23`** | `FR-P1-02` | Filter `SlashCommandItem.allCommands` in Local vs Remote Agent context | Exposes all 15 official App commands; marks/filters `/btw` and local-only commands properly in Remote Agent mode. |
| **`TC-24`** | `FR-P1-03` | Decode Binary Protobuf `RequestedInteraction` for `permission` (non-read action + plugin attribution), `executeUrl`, `downloadUrl`, `browserUpload`, `workflowScript`, and `mcp`; build payloads via `InteractionBuilder` | Preserves real action/target/URL/filename/script metadata and constructs matching `HandleCascadeUserInteraction` oneof payloads for `allowOnce`, `allowInConversation`, `alwaysAllow`, and `reject`. |
| **`TC-25`** | `FR-P1-04` | Decode & fetch `GetConversationOverview`, `SubagentInvocation`, `DynamicWorkflow`, `SwarmBoard`, `McpToolCall`, and `GitHubPullRequestInfo`; cancel background task & stop subagent | Overview lists subagents, tasks, goals, PRs, artifacts; cancel/stop RPCs update status cleanly. |
| **`TC-26`** | `FR-P1-05` | Ask multi-turn `/btw` side question via `SendSideQuestion` and invoke `insertSideQuestionAnswerIntoMain` | Side thread stays isolated from main steps until explicitly inserted into composer/main conversation. |
| **`TC-27`** | `FR-P2-01` | Execute Git VCS flow (`Stage` → `Commit` with auto-generated message → `Push`, plus `Unstage`/`Discard`) | Updates `FilePatchDiff.isStaged`, returns generated commit SHA/message, and pushes branch cleanly. |
| **`TC-28`** | `FR-P2-02` | Parse Markdown with YAML Frontmatter, inline image, Mermaid diagram, and GitHub PR URL; validate Jupyter `.ipynb` JSON parser & Image Region Comment model | Extracts structured frontmatter key-value pairs, image nodes, Mermaid code flag, PR pill metadata, and notebook cell outputs. |
| **`TC-29`** | `FR-P2-03..06` | Exercise Voice Mode transcript summary lifecycle, Customizations MCP Restart & Plugin Toggle, Queued Message edit, Turn Revert, Appearance/Layout persistence (`LocalProjectionStore`), and Full-Text Search | All state transitions persist cleanly across reload and round-trip against mock backend. |
| **`TC-30`** | **Auto-Sync** | Run `python3 scripts/sync-antigravity-docs.py --self-test` and `python3 scripts/run-doc-sync-agent.py --dry-run` | Verifies monotonic semver guard, HTML→Markdown normalization, Tier 1/2/3 triage, and GitHub Actions workflow syntax validity. |
