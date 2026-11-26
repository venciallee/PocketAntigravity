# Antigravity iOS App — Product Requirements & Native Swift 6 Technical Architecture (v2.1 UE & Official v2.34 Aligned)

## 1. Product Overview & Design System Alignment

Aligned with the official Google Antigravity 2.0 App (`v2.34.0`) and the canonical iOS UE boards under `docs/ue/ios/`, **AG Pocket (iOS)** delivers a zero-compromise native mobile companion ("Watch · Approve · Direct") synchronized across **Local Desktop Hosts (`MacBook Pro` via Remote Control Cloud Relay / LAN Connect-RPC)** and **Cloud VMs (`Cloud` autonomous sandboxes)**.

See [`specs/04-ue-official-docs-conflict-audit.md`](04-ue-official-docs-conflict-audit.md) for the authoritative resolution of all legacy spec conflicts against live Google Antigravity documentation.

### 1.1 Visual & Interaction Design Tokens
- **Canvas & Surfaces (Neutral Matte Obsidian)**:
  - Background Canvas: `#0B0B0C` (Pure OLED Neutral Obsidian)
  - Grouped Card / Composer Shell: `#141416` (`18–26pt` continuous corner radius, `1px` `#222226` / `rgba(255,255,255,0.08)` border)
  - Elevated Input / Sheet Surface: `#1D1D20` / `#1A1A1D` (`28–34pt` sheet corner radius with top grabber)
  - Popover / Grouped Row Card: `#26262B`
- **Brand & Semantic Colors**:
  - **Primary Brand CTA (`accentPeriwinkle`)**: `#8DB8FF` with `#0A0E17` dark bold label ink
  - **Active Pill / Stepper**: Pure White `#FFFFFF` fill with `#0B0B0C` bold text
  - **Running (`运行中`)**: `#7DA7FF` (spinning progress arc)
  - **Needs You / Awaiting Approval (`等你处理`)**: `#F2B866` Warm Amber (dot, amber-tinted approval card `#1E1A14`, and solid `#F2B866` Face ID `Allow` CTA)
  - **Done / Additions (`完成`)**: `#6FD8A6` Emerald (`+128`, `42 passed`, `NEW`)
  - **Deletions / Destructive**: `#F07167` Coral (`-14`, `Delete`)
- **Global Navigation Architecture (PC-Aligned Sidebar Drawer + New Conversation Home)**:
  - Root screen (`UE01`) is **New Conversation Home** (`Welcome back, Alex. Where should we pick up?`, top bar with Sidebar button, Host Switcher pill, Search button; amber `Needs approval` quick-jump banner; PC-isomorphic bottom Composer).
  - Left slide-over **Sidebar Drawer (`UE01B`)** mirrors Antigravity Desktop's sidebar: `+ New Conversation`, `Automations`, `Customizations`, `Pinned`, `Projects` (with Display Options filter & New Project `+` icon buttons), collapsible local/cloud project groups with single-line conversation rows (amber dot / blue unread dot / spinning arc / relative time), and bottom `Settings`.

---

## 2. Functional Requirements Across Core (`UE01`–`UE13`) & Extended (`UE01B`, `UE06B/C`, `UE07B`, `UE08B`, `UE14`, `UE15`) Screens

| Screen ID | UE Board | Core Product Requirements | Connect-RPC / Data Binding |
| :--- | :--- | :--- | :--- |
| **`UE01`** | `Main.png` | **New Conversation Home**: Sidebar button, Host switcher pill (`● MacBook Pro ⌄`), Search button, centered greeting, amber `Needs approval · Add rate limiter to /transfers ›` card, PC-isomorphic bottom Composer (`📁 ledger-svc ⌄`, `🌿 Repo default ⌄`, `☁️`, `+`, `Gemini 4 Neon / Extra High ⌄`, `🛡 Default ⌄`, `🎤`, `→`) | `JetboxSubscribeToSummaries` + `StartCascade` + `SendUserCascadeMessage` |
| **`UE01B`** | `ios-drawer.png` | **Sidebar Drawer**: `+ New Conversation`, `Automations`, `Customizations`, `Pinned` (`Release checklist v2.3`), `Projects` (Display Options + New Project buttons), `ledger-svc` & cloud `acme/web-console` groups with single-line rows & status indicators, bottom `Settings` | `GetWorkspaceInfos` + `LocalProjectionStore` |
| **`UE02`** | `ios-display-options.png` | **Display Options**: `Reset` / `Done`, `Group By` (`Project`/`Host`/`None`), `Sort Conversations` (`Last Updated`/`Date Created`/`Title` + `Newest First`/`Oldest First`), `Sort Projects` (`Custom Order`), `Filter` (`All conversations`), `Display` (`Comfortable · Previews`), `Auto Pin` & `Archived Only` toggles, `Mark All as Read (3 unread)` | Persisted `AgentDisplayOptions` driving sidebar sorting/grouping/filtering |
| **`UE03`** | `ios-pin-menu.png` | **Long-Press Context Preview & Swipe**: Preview card (`Fix flaky TestSettlementBatch`, `ledger-svc · Gemini 4 Neon · 8m`, `Implementation Plan` + `Awaiting review`), 6 actions (`Pin`, `Mark as Unread`, `Rename`, `Move to Project`, `Archive`, `Delete`), left-swipe `Pin` (`#8DB8FF`) + `Archive` | `PinCascade`, `RenameCascade`, `MoveCascadeToWorkspace`, `ArchiveCascade`, `DeleteCascade` |
| **`UE04`** | `ios-project-detail.png` | **Project Detail (`ledger-svc`)**: `< Projects`, `⋯`, `~/code/ledger-svc`, pills (`Local · MacBook Pro`, `main ↑2`, `Working tree clean`), `New Conversation in Project` CTA, `Active 4 / Archived 2 / Automations 1` underline tabs, single-line rows, `THIS PROJECT` (`Nightly dependency audit` → Detail, `Project rules & skills 4 ›` → Rules & Skills, `Reveal in Finder on Mac`) | `StartCascade` scoped to `workspaceUri` + `OpenWorkspaceInFinder` |
| **`UE05`** | `ios-new-project.png` | **Create New Project**: `RUNS ON` (`MacBook Pro` vs `Cloud`), `SOURCE` (`GitHub repository` vs `Drive folder`), repo search + list (`acme/ledger-svc`, `acme/web-console`, `acme/design-tokens`), `Branch & worktree`, `Name`, `Create Project` CTA | `CreateProjectWorkspace` |
| **`UE06`** | `ios-automations.png` | **Automations Hub** (Sidebar-navigated, no bottom tab bar/FAB): Sidebar + Filter buttons, NL create bar (`Every weekday at 9, summarize` + `Create`), `SCHEDULED · 2` with `▶` & `NEXT RUN`/`LAST RUN`, `ALWAYS ON · 1`, `PAUSED · 1` (`Resume`) | `ListAutomations`, `CreateAutomation`, `TriggerAutomationNow`, `SetAutomationPaused` |
| **`UE06B/C`** | `ios-automation-detail.png`, `ios-automation-edit.png` | **Automation Detail & Edit**: Status badge, `Run Now` / `Pause`, `PROMPT`, Trigger/Repeats/Next run, `RECENT RUNS` (Succeeded / Needs review / Failed + `Retry`), `Edit` → `Edit Schedule & Prompt` form (`Name`, `Prompt`, `Project`, `Trigger`, `Repeats`, `Time`, `Model`, `Delete Automation`) | `ManageSidecar` (`RUN_NOW`, `UPDATE`, `DISABLE`, `DELETE`) |
| **`UE07`** | `ios-chat.png` | **Chat & Composer**: Top bar (`Back`, title + `ledger-svc · main · MacBook Pro`, `+128 -14`, `⋯`), `Thought for 14s ›`, `Implementation Plan` card, `Task · 4 of 7 done (2m 41s)` 7-segment progress card, Amber `Run this command?` card (`Deny` + Face ID `Allow`), status bar (`Waiting for your approval · Step 5 of 7` + `Stop`), Composer (`@ratelimit.go ×`, `+`, `Gemini 4 Neon / Extra High ⌄`, `🛡 Default ⌄`, `🎤`, `→`) | `GetCascadeTrajectorySteps`, `HandleCascadeUserInteraction`, `SendUserCascadeMessage`, `CancelCascadeInvocation` |
| **`UE07B`** | `ios-preset.png` | **Permissions Preset Popover**: Anchored above `🛡 Default ⌄`: `Request Review`, `Default ✓`, `Auto`, `Turbo`, footer `Default for new turns: Settings > Permissions ›` | `SetConversationPermissionPreset` |
| **`UE08`** | `ios-add-context.png` | **Add Context Menu**: Anchored above `+`: `Files`, `Folder`, `Mentions`, `Actions`, `Drive [Set up]` (selecting Files/Folder/Mentions opens multi-select attachment picker; selecting Actions opens `/`) | Attaches `ContextItem` chips to `ChatComposerView` |
| **`UE08B`** | `ios-slash.png` | **`/` Actions & Skills Overlay**: `Actions` (`/plan`, `/goal`, `/schedule`, `/automation`, feature-flagged `/btw`) + `Skills` (`/go-testing`, `/api-review`) — zero deprecated Workflows | `SlashCommandItem` + workspace/global `Skills` |
| **`UE09`** | `ios-model.png` | **Model Picker** (No Planning/Fast): `Orchestrator (Neon plans · Hydrogen executes ›)`, `Gemini 4 Neon [New] ✓` with inline 4-level thinking segmented control (`Low` / `Medium` / `High` / `Extra High`), `Gemini 4 Carbon`, `Gemini 4 Argon`, `Gemini 4 Hydrogen`, `Claude Opus 5.5`, `Gemini 3.8 Flash`, `More models ›`, `Five Hour Limit Remaining` + `View Usage` & `Weekly Limit Remaining` bars | `GetModelCatalog` + `CascadeModelConfig` (`modelId`, `thinkingEffort`) |
| **`UE10`** | `ios-ask.png` | **`/plan` Interview Structured Question**: `ledger-svc · /plan interview · Gemini 4 Neon`, 3-step pills (`✓ 1 Storage`, `2 Actions`, `3 Retention`), multi-select checkbox cards, `Something else...`, `Back` / centered `Next`, bottom `Reply in your own words` composer | `HandleCascadeUserInteraction` (`askQuestion`) |
| **`UE11`** | `ios-plan-review.png` | **Implementation Plan Review**: `[💬 2]` badge, amber paused banner, rendered Markdown with `MODIFY`/`NEW` badges, inline pending comment (`WL You Pending`), selection `[💬 Comment | Copy]` callout, `Proceed` / `Send 2 comments` bar | `GetArtifactSnapshots` + `HandleCascadeUserInteraction` |
| **`UE12`** | `ios-diff.png` | **Turn Diff Review**: `Accept all`, `Turn 1..3/All` pills, `middleware/ratelimit.go (File 1 of 4 · +96 -4)` pager, `Revert hunk`, single-column line gutter with syntax diff + word emphasis, Line 29 inline comment composer (`Add to review` / `Send to agent`), `Viewed` + `Revert file` + `Accept file` | `GetTurnDiff` + `RevertDiffHunk` + `SendDiffReviewComments` |
| **`UE13`** | `live-activity.png` | **Dynamic Island & Live Activity**: 7 WidgetKit states (Compact Running/Waiting/Done, Minimal Ring, Expanded Running/Waiting Face ID, Lock Screen Multi-Agent card) | `ActivityKit` + `ApproveWaitingStepIntent` |
| **`UE14`** | `ios-customizations.png` | **Rules & Skills (Lightweight Customizations)**: `< ledger-svc`, `Loaded every turn · 6.2k tokens` stacked bar (Rules/Skills/Plugins), segmented tabs (`Skills 5 | Rules 4 | Plugins 2 | Agents 1`), `Global`/`Workspace`/`Plugin` badges, `PLUGINS IN THIS PROJECT` toggles (`Firebase`, `Datadog`), desktop-editing footer | `FetchCustomizationsCatalog` + `TogglePlugin` |
| **`UE15`** | `ios-settings.png`, `ios-settings-more.png` | **Settings**: Connected host card + `Scan New QR`, `Available hosts` (`Refresh`), `Appearance` (`System`/`Dark`/`Light` + `Obsidian`/`Nord`/`Everforest`), `Language` (`English` / `简体中文`), `Permissions` (4 presets), `Notifications` (`Approval & Completion Alerts`, `Quiet on Manual Stop`), `Sign Out & Disconnect Host`, `About AG Pocket` | `AppAppearancePreferences` + `ConnectionDomainStore` |

---

## 3. Normative Swift 6 Public API Contract (Shared Across Modules)

1. **Top-Level Navigation & Scene Enumeration**:
   - `ESDDVerifySceneCase` preserves all 13 canonical cases (`UE01_AGENTS_HOME` .. `UE13_LIVE_ACTIVITY_SPEC`) plus extended deterministic scenes (`UE01B_SIDEBAR_DRAWER`, `UE06B_AUTOMATION_DETAIL`, `UE06C_AUTOMATION_EDIT`, `UE07B_PERMISSIONS_PRESET`, `UE08B_SLASH_MENU`, `UE14_RULES_AND_SKILLS`, `UE15_SETTINGS`) routable via `--ui-verify` and `agpocket://verify/<case>`.
2. **Core Domain Models (`Packages/AntigravityData/Sources/AntigravityData/Models/` & `shared/core-model/`)**:
   - `AppLanguage` (`english`, `zhHans`) added to `AppAppearancePreferences`.
   - `CascadeModelConfig` default model = `MODEL_GOOGLE_GEMINI_4_NEON` (`Gemini 4 Neon`, `ThinkingEffortLevel.extra` / `Extra High`).
   - `AutomationRunRecord` & automation edit/delete/restart mutations on `WorkspaceAndAutomationStore` and `AntigravitySessionStore`.
   - `ContextCandidateCategory` includes `.drive` alongside `.files`, `.folder`, `.mentions`, `.actions` (and `.skills` retained for backward compatibility).
   - `CustomizationsCatalog` exposes token budget metrics (`loadedTokensLabel = "6.2k tokens"`) and live plugin toggle state.
