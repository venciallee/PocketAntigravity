# Technical Design Specification — Antigravity 2.0 (`v2.33.0` P0–P2 Parity + Cloud Auto-Sync)

## 1. Architecture & Module Invariants

All changes strictly preserve `AGENTS.md` architectural boundaries and `esdd_inspector.py` mechanical gates:

1. **`Packages/AntigravityData` (Pure Swift 6, Zero `UIKit` / `WebKit` / `AVFoundation`)**:
   - `Models/V233FeatureModels.swift`: Domain types for `ModelUsageQuota`, `AgentPermissionPreset`, `PermissionRuleEntry`, `SubagentPayload`, `DynamicWorkflowPayload`, `SwarmBoardPayload`, `McpToolCallPayload`, `BackgroundTaskItem`, `ConversationGoalItem`, `GitHubPullRequestInfo`, `SideQuestionThread`, `ConversationOverviewSnapshot`, `DiffCompareMode`, `GitCommitDraft`, `JupyterNotebookDocument`, `ImageRegionComment`, `VoiceModeState`, `CustomizationsCatalog`, `AppAppearancePreferences`, `QueuedMessageItem`, `ConversationTurnSummary`.
   - `Models/WorkspaceModels.swift`: Extend `ThinkingEffortLevel` (`+ .extra`), `CascadeModelConfig` (`isOrchestrator`, `supportedEfforts`, `liveDefaultCatalog` updated to Gemini 4 + Orchestrator), `SlashCommandItem` (15 App commands + `availableInRemoteAgent`), `ComposerAttachmentChip` (generic file / PDF / zip / audio / video / quote / plugin), `NewProjectDraft` (Drive links, uploaded files, `envSetupScript`).
   - `Models/CascadeModels.swift`: Extend `CortexStepType` (`+ .subagentInvocation, .dynamicWorkflow, .swarmBoard, .mcpToolCall, .backgroundTask, .sideQuestion`) and `CascadeStep` optional payloads (`subagent`, `workflow`, `swarm`, `mcpTool`, `prLinks`).
   - `Models/InteractionModels.swift`: Add typed specs (`ExecuteUrlInteractionSpec`, `DownloadUrlInteractionSpec`, `BrowserUploadInteractionSpec`, `WorkflowScriptInteractionSpec`, `McpToolInteractionSpec`), extend `PermissionInteractionSpec` (`pluginName`, `toolIconName`), extend `InteractionDecision` (`+ .allowInConversation, .alwaysAllow`).
   - `Models/ArtifactModels.swift`: Extend `ArtifactKind` (`+ .pdfDocument, .jupyterNotebook, .imageAsset, .videoAsset`) and `FilePatchDiff` (`statusLetter`, `isStaged`, `compareScope`).
   - `Models/AntigravityMarkdownParser.swift`: Add YAML frontmatter block (`MarkdownBlock.frontmatter`), inline image (`MarkdownInline.image`), Mermaid/SVG code-block helpers, and GitHub PR link extraction (`AntigravityMarkdownParser.extractGitHubPRLinks(_:)`).
   - `Store/SharedAppGroupBridge.swift`: Pure Foundation shared container (`group.dev.antigravity.ios.shared` with fallback) bridging Live Activity `AppIntent` commands and Share Extension payloads cleanly across process boundaries.
   - `Store/KeychainStore.swift`: Support optional shared Keychain access group while preserving existing standalone Keychain behavior.
   - `Store/LocalProjectionStore.swift`: Persist `AppAppearancePreferences` (including `collapsedProjectIds`), `ModelUsageQuota`, `AgentPermissionPreset`, and `CustomizationsCatalog`.
   - `Protocol/ProtobufStepDecoder.swift` & `Protocol/InteractionBuilder.swift`: Decode Gemini 4 / Orchestrator model enums, real permission action/target/plugin fields, browser/download/upload/workflow/MCP interaction specs, and multi-agent step types; build authoritative `HandleCascadeUserInteraction` payloads.
   - `Protocol/AntigravityRPCClient.swift`:
     - Replace silent Cloud Relay `companionOnlyMethods` stubs with upstream-first candidate RPC dispatch + graceful capability fallback;
     - Implement full `GetTurnDiff` JSON decoder returning `[FilePatchDiff]`;
     - Preserve `thinkingEffort`, `agentPersona`, `permissionPreset`, and rich `items` in `sanitizeCloudRelayPayload`;
     - Add RPC methods for Quota refresh, Overview, Side Question (`/btw`), Background Task / Subagent cancellation, Turn Revert, Git VCS (Stage/Unstage/Discard/Commit/Push), Permission Preset sync, Customizations & MCP Restart / Plugin toggle, and Full-Text Search.
   - `Store/AntigravitySessionStore.swift`: Central `@MainActor @Observable` state + optimistic mutations + live sync for all P0–P2 workflows, keeping `makeESDDVerificationStore()` 100% deterministic for `UE01..UE13`.

2. **`iOS/` (SwiftUI / UIKit Native Layer)**:
   - `Services/VoiceInputManager.swift`: Real `SFSpeechRecognizer` + `AVAudioEngine` live dictation.
   - `Services/LiveActivityCoordinator.swift`: Real `ActivityKit` lifecycle synchronization.
   - `Services/NotificationCoordinator.swift`: Real `UNUserNotificationCenter` proactive notifications.
   - `ViewControllers/Cascade/ConversationOverviewSheetView.swift`: Conversation Overview drawer (`Review`, `Files`, `Subagents`, `Background Tasks`, `Goals`, `Documents`, `Artifacts`, `Links`, `Pull Requests`).
   - `ViewControllers/Cascade/SideQuestionSheetView.swift`: Multi-turn `/btw` Side Question sheet + "Insert into main conversation".
   - `ViewControllers/Cascade/SwarmBoardSheetView.swift`: `/swarm` Roster + Message Board + `@member` filter.
   - `ViewControllers/Cascade/VoiceModeSheetView.swift`: Gemini Live Voice Mode call sheet + Call Summary card.
   - `ViewControllers/Inspector/RichArtifactViewerSheet.swift`: Native `PDFKit`, Jupyter `.ipynb`, Fullscreen Media + image region commenting, and sandboxed `WKWebView` Generative UI / URL previewer.
   - `ViewControllers/Pairing/CustomizationsSettingsView.swift`: Permissions, Customizations (Skills/Rules/MCP/Plugins/Hooks), and Appearance/Layout settings.
   - Dual-track live binding updates in `StructuredQuestionCardView.swift`, `ImplementationPlanReviewViewController.swift`, `TurnDiffReviewViewController.swift`, `ChatComposerView.swift`, `ModelAndModeSheetView.swift`, `CascadeChatViewController.swift`, `StepCellViews.swift`, `AgentsHomeViewController.swift`, `CreateProjectSheetView.swift`, `RemotePairingViewController.swift`, `AntigravityApp.swift`.

3. **`Extensions/`**:
   - `Extensions/LiveActivity/AntigravityLiveActivityWidget.swift`: `ApproveWaitingStepIntent`, `DenyWaitingStepIntent`, and `StopCascadeTurnIntent` execute live `AntigravityRPCClient` calls via `KeychainStore` + enqueue fallback reconciliation via `SharedAppGroupBridge`.
   - `Extensions/Share/AntigravityShareViewController.swift`: Extract `NSExtensionContext` text/URLs/files into `SharedAppGroupBridge` and open `antigravity://share/<id>`.

4. **Mock Server, Mac Companion Bridge & Pure-Cloud GitHub Actions Auto-Sync**:
   - `scripts/mac-companion-bridge.py` & `verification/mock_language_server.py`: Implement full v2.33 mock & companion RPC surface (`GetTurnDiff` with hunks/lines, `GitStageFile`/`GitUnstageFile`/`GitDiscardFile`/`GitCommit`/`GitPush`, `GetArtifactSnapshots`, `GetConversationOverview`, `SendSideQuestion`, `RevertConversationToStep`, `GetCustomizationsCatalog`, `RestartMcpServer`, `TogglePlugin`, `SetPermissionPreset`, `CancelBackgroundTask`, `StopSubagent`, `GetCascadeModelConfigs` with Gemini 4 + Orchestrator + quota).
   - `scripts/sync-antigravity-docs.py`, `scripts/run-doc-sync-agent.py`, `.agents/skills/antigravity-doc-sync/SKILL.md`, `.github/workflows/antigravity-doc-sync.yml`, `docs/upstream-snapshots/`: Pure-cloud GitHub Actions subscription, monotonic semver guard, semantic diffing, Tier 1/2/3 triage, headless Antigravity CLI/SDK execution, and automated PR / Issue creation triggering `macos-xcode-verify.yml`.

## 2. Backward Compatibility & ESDD Preservation

- `specs/esdd-ir.json` preserves exact 13 states (`UE01`..`UE13`), 13 transitions (`E01`..`E13`), 13 claims (`CLAIM-01`..`CLAIM-13`), 10 design tokens, and 5 typography tiers so Stage 1–4 of `verification/esdd-verify.py` stay 100% green.
- All live UI upgrades gate behind `!store.isVerificationMode || store.hasPairedBackend || store.isLiveBackendConnected` where needed so the 13 reference UE screenshots remain pixel-stable.
- `project.yml` adds `NSSpeechRecognitionUsageDescription` without adding paid-provisioning entitlements that would break unsigned `iphonesimulator` CI builds on `macos-15`.
