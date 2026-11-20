# PRD & Capability Gap Specification — Google Antigravity 2.0 (`v2.21+ / v2.29+ → v2.33.0`)

- **Baseline Version**: `v2.33.0` (App) / `v1.5.11` (CLI) / Gemini 4 Neon & Orchestrator (`2026-11-18`)
- **Target Project**: `iOSAntigravity` (`AG Orbit` — Native Swift 6 iOS 18+ Companion)
- **Scope**: Complete **P0** (Live Wire & Mock Remediation), **P1** (v2.29–v2.33 Core Protocol & Multi-Agent Orchestration), and **P2** (VCS, Multimodal Viewers, Voice Mode, Customizations, UX Parity)

---

## 1. P0 — Live Wire & Mock Remediation (Zero-Stub End-to-End Parity)

| Req ID | Capability | Acceptance Criteria |
| :--- | :--- | :--- |
| **`FR-P0-01`** | **Cloud Relay Real RPC Passthrough & `GetTurnDiff` Parsing** | Remove silent fake `{"ok": true}` / `[]` short-circuits in `AntigravityRPCClient.callCloudRelayUnaryJSON`; attempt upstream RPC candidates cleanly with graceful fallback; parse real `GetTurnDiff` JSON payload (files, hunks, lines, additions, deletions, git status letters, staged state) into `[FilePatchDiff]`. |
| **`FR-P0-02`** | **Live Data Binding for `UE10` / `UE11` / `UE12`** | Preserve 1:1 ESDD verification fixtures under `--ui-verify`, while live connected sessions dynamically render `store.questionSteps` / `step.requestedInteraction.askQuestion` in `StructuredQuestionCardView`, `store.activeArtifacts` + Markdown + live inline comments in `ImplementationPlanReviewViewController`, and `store.activeTurnDiffs` in `TurnDiffReviewViewController`. |
| **`FR-P0-03`** | **Live Activity Lifecycle, Working AppIntents & Share Extension** | Add `LiveActivityCoordinator` (`ActivityKit` `.request`/`.update`/`.end`) and `SharedAppGroupBridge`; make `ApproveWaitingStepIntent` (Face ID), `DenyWaitingStepIntent`, and `StopCascadeTurnIntent` dispatch real RPCs via shared Keychain credentials + App Group fallback queue; parse real `NSExtensionContext` items in `AntigravityShareExtensionViewController` and consume `antigravity://share/<id>` in `AntigravityApp`. |
| **`FR-P0-04`** | **Composer Real Dictation, `/` `@` Suggestion Popups & Relay Field Fidelity** | Wire `ChatComposerView` mic button to real `SFSpeechRecognizer` + `AVAudioEngine` dictation (`VoiceInputManager`); render `/` slash command and typo-tolerant `@` mention popups above composer; update `sanitizeCloudRelayPayload` so `thinkingEffort`, custom `agentPersona`, per-conversation `permissionPreset`, and rich attachment items survive Cloud Relay dispatch. |
| **`FR-P0-05`** | **Proactive Local & Background-Ready Notifications** | Add `NotificationCoordinator` (`UNUserNotificationCenter`) notifying on agent completion or `WAITING` approval/question state, while suppressing notifications on manual user cancel (matching v2.22+ desktop behavior). |

---

## 2. P1 — v2.29–v2.33 Core Models, Commands, Permissions & Multi-Agent Orchestration

| Req ID | Capability | Acceptance Criteria |
| :--- | :--- | :--- |
| **`FR-P1-01`** | **Gemini 4 Family, Orchestrator, 4-Level Thinking & Dual-Pool Quota** | Support `Gemini 4 Neon` (default), `Gemini 4 Carbon`, `Gemini 4 Argon`, `Gemini 4 Hydrogen`, and `Orchestrator (Neon / Carbon / Argon)`; add `ThinkingEffortLevel.extra` (`xhigh`) with UI picker in `ModelAndModeSheetView` (auto-locked with explanation for Orchestrator), Refresh Models action, and `ModelUsageQuota` card showing Gemini & Claude/GPT Weekly + 5-Hour remaining limits. |
| **`FR-P1-02`** | **All 15 Official App Slash Commands** | Expand `SlashCommandItem.allCommands` to all 15 official App commands (`/plan`, `/grill-me`, `/goal`, `/boost`, `/swarm`, `/teamwork`, `/run-workflow`, `/btw`, `/schedule`, `/browser`, `/learn`, `/automation`, `/generative_ui`, `/agy-customizations`, `/antigravity-guide`) with Remote-Agent compatibility metadata and dynamic Skill command merging. |
| **`FR-P1-03`** | **Fine-Grained Permission Engine & New Interaction Approvals** | Support 4 permission presets (`Request Review`, `Default` sandboxed, `Auto`, `Turbo`) + `Use Global Settings` in composer & settings; decode real `action`/`target`/`pluginName` on `PermissionInteractionSpec` plus `execute_url`, `download_url`, `browserUpload`, `workflowScript`, and `mcp` tool interaction specs; render tool-specific approval cards with Allow Once / In Conversation / Always options. |
| **`FR-P1-04`** | **Conversation Overview Sheet & Multi-Agent Step Cards** | Add `ConversationOverviewSheetView` aggregating `Review`, `Files`, `Subagents`, `Background Tasks` (with Cancel), `Goals`, `Documents`, `Artifacts`, `Links`, and `Pull Requests`; render `SubagentStepCard`, `DynamicWorkflowStepCard` (expandable script, phases, logs, agent cards), `SwarmBoardSheetView` (Roster + Posts + `@member` filter), `McpToolStepCard`, and live `GitHubPRStatusPill`. |
| **`FR-P1-05`** | **Multi-Turn `/btw` Side Question Sheet** | Add `SideQuestionSheetView` supporting read-only multi-turn follow-up questions without interrupting the main conversation, plus `Insert into main conversation` action (v2.32.2 / v2.33.0). |

---

## 3. P2 — Git VCS, Multimodal Previews, Voice Mode, Customizations & UX Parity

| Req ID | Capability | Acceptance Criteria |
| :--- | :--- | :--- |
| **`FR-P2-01`** | **Git VCS Workflow in Review Pane** | Support `Turn` / `Uncommitted` / `Branch` / `Agent Edits` diff views, file status letters (`M`/`A`/`U`/`D`/`R`), Stage / Unstage / Discard (with confirm guard), and Commit Sheet (manual or AI-generated commit message, Include unstaged, Amend, Push) plus line-range `Quote` (`file#L13-16`) back to composer. |
| **`FR-P2-02`** | **Multimodal Attachments & Rich Viewers (PDF, Jupyter, Media, GenUI)** | Support attaching arbitrary files (`.zip`, `.pdf`, `.csv`, `.json`), images, videos, and audio (`.wav`/`.mp3`/`.m4a`/`.aac`/`.flac`/`.opus`/`.amr`); add `RichArtifactViewerSheet` supporting `PDFKit` PDF viewer with comment/quote, Jupyter `.ipynb` viewer (Markdown/Code/Outputs + Preview/Raw + cell comments), Fullscreen Image/Video viewer with drag-region image comments, and sandboxed `WKWebView` for Generative UI (`/generative_ui`) & URL Artifacts; upgrade `AntigravityMarkdownParser` with YAML frontmatter, inline images, Mermaid/SVG blocks, and PR pills. |
| **`FR-P2-03`** | **Voice Mode (Gemini Live Two-Way UI & Call Summary)** | Add `VoiceModeSheetView` supporting real-time spoken interaction controls, 9 Gemini Live voices, `0.75x–2.0x` playback speed, mute/interrupt, spoken approval relay, multi-question voice progression, and automatic Call Summary Transcript card persisted on call end. |
| **`FR-P2-04`** | **Customizations Hub & Cloud Resources** | Expand `Settings` with `CustomizationsSettingsView` (collapsible counts for Skills, Rules, Custom Agents, MCP Servers with startup error hints & Restart, Plugins Marketplace with Featured partner badges & OAuth status, Lifecycle Hooks); extend `CreateProjectSheetView` with Google Drive links, uploaded file resources, `Configure on GitHub`, and `env-setup.sh` environment setup editor. |
| **`FR-P2-05`** | **Conversation Navigator, Queued Messages & Turn Revert** | Add Turn jump navigator for long chats (v2.28.1), queued message inspection/editing modal while agent runs, and Turn Revert action via message context menu. |
| **`FR-P2-06`** | **Appearance, Layouts, Persistence & Search** | Support `Software Engineering` vs `Knowledge Work` layout (v2.30.0), Themes (`Obsidian`, `Nord`, `Everforest Dark`, `Everforest Light`), Font Size (`12`/`14`/`16 pt`), persisted collapsed sidebar folders, `Scheduled` automations filter chip, and cross-conversation full-text search. |
