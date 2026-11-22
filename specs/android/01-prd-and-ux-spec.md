# AG Pocket Android — Product Requirements & Material 3 Expressive UX Specification (v1.0)

- **Status**: Normative Spec (Aligned with iOS `v2.33.0` + KMP Shared Core)
- **Target Platform**: Android 10+ (`minSdk = 29`), `compileSdk = 36`, `targetSdk = 36` (Android 16)
- **UI Framework**: Native Kotlin + Jetpack Compose + Material Design 3 (`1.4.0` / Expressive patterns) + Adaptive `NavigationSuiteScaffold`
- **Baseline Viewport (Visual QA)**: `412×915dp` @ `xxhdpi` (Pixel 9 Portrait) & `800×500dp` (`UE13` Live Updates Spec Gallery)

---

## 1. Design Philosophy: "Antigravity Cosmic Brand × Native Android Material 3"

The Android client MUST preserve 100% brand & mental-model continuity with Antigravity Desktop and iOS while speaking idiomatic **Material Design 3** rather than mimicking iOS HIG / Liquid Glass:

### 1.1 Color & Surface Elevation System
- **Tonal Surface Elevation (No Fake iOS Blur Chrome)**:
  - Dark Mode (Default — **Matte OLED Obsidian**):
    - `background` = `#090A0D`
    - `surfaceContainerLowest` = `#090A0D`
    - `surfaceContainerLow` = `#0F1014`
    - `surfaceContainer` = `#141519` (Grouped Cards)
    - `surfaceContainerHigh` = `#1D1F26` (Elevated Pills / Composer / Dialogs)
    - `surfaceContainerHighest` = `#25272F` (Menus / Active Selection)
    - `outlineVariant` = `#FFFFFF` @ `10%` alpha (`1dp` crisp stroke)
    - `primary` = `#8EB4FF` (Periwinkle CTA), `onPrimary` = `#0A0E17`
  - Light Mode (**Soft Porcelain**):
    - `background` = `#F4F5F8`, `surfaceContainerLowest` = `#FFFFFF`, `surfaceContainer` = `#FFFFFF`, `surfaceContainerHigh` = `#E6E9F2`, `primary` = `#2F66E8`, `onPrimary` = `#FFFFFF` (all WCAG AA >= 4.5:1).
  - **Theme Presets**: `Obsidian` (default), `Nord`, `Everforest Dark`, `Everforest Light`, plus an **opt-in Android 12+ Material You Dynamic Color toggle** (`useDynamicColor: Boolean = false`). When Dynamic Color is enabled, semantic status roles remain **locked** so approval/diff/error signals never shift hue.
- **Locked Semantic Status Palette (Cross-Platform Invariant)**:
  - `statusRunning`: `#7DA7FF` (Dark) / `#2F66E8` (Light)
  - `statusWaiting`: `#EBB365` (Dark) / `#B86E00` (Light) — Biometric Gate & Plan Review Pause
  - `statusDone`: `#57C88A` (Dark) / `#198754` (Light) — Completed & Diff Additions
  - `statusError`: `#F07167` (Dark) / `#CF372E` (Light) — Errors, Destructive Actions, Diff Deletions

### 1.2 Five-Tier Semantic Typography (`sp` Scalable)
Mapped to system sans-serif / `Roboto Flex` + Monospace (`JetBrains Mono` / `FontFamily.Monospace`):

| Tier | Content Scope | Size / Line Height | Weight | Color Role |
| :--- | :--- | :--- | :--- | :--- |
| **1. Reading** | User prompts, Agent Markdown prose | `16sp / 24sp` | `Normal (400)` | `inkReading` (`#F5F6F8` / `#111318`) |
| **2. Evidence** | Filenames, Artifact titles, Diff counters, Card titles | `14sp / 20sp` | `SemiBold (600)` | `inkLabel` (`#D1D5DF` / `#272B36`) |
| **3. Process** | Collapsible Thinking, Tool calls, Terminal output | `13sp / 18sp` | `Normal (400)` | `inkSecondary` (`#8A909E` / `#5B6170`) |
| **4. Metadata** | Step index, elapsed time, model badges, host RTT | `11sp / 14sp` | `Medium (500)` Mono | `inkMuted` (`#6D7485` / `#64748B`) |
| **5. Chrome** | TopAppBar titles, Chips, Composer controls, Buttons | `13sp / 18sp` | `SemiBold (600)` | `inkLabel` / `primary` |

### 1.3 Android Geometry, Accessibility & System Interaction Invariants
- **Minimum Touch Target**: Every interactive button, chip, list row, checkbox, and approval action MUST satisfy Material `>= 48dp × 48dp` (or `>= 48dp` row height) and `0px` unintended horizontal overflow.
- **Edge-to-Edge (`enableEdgeToEdge()`)**: Full edge-to-edge rendering consuming `statusBarsPadding()`, `navigationBarsPadding()`, and `imePadding()`.
- **Adaptive Navigation (`NavigationSuiteScaffold`)**:
  - Compact width (Phone): M3 bottom `NavigationBar` (`Agents` / `Automations` / `Settings`) + squircle `16dp`-radius `FloatingActionButton` (`#8EB4FF` Periwinkle) positioned above the navigation bar.
  - Medium/Expanded width (Foldable / Tablet): Left `NavigationRail` + two-pane `ListDetail` layout.
- **Predictive Back**: All pushed routes, search bars, and modal sheets support Android 14+ predictive back gesture via `BackHandler` / Navigation Compose.
- **Iconography**: 100% Material Symbols (`Icons.Rounded.*` / `Icons.Outlined.*`) mapped from KMP `SemanticIcon` — zero SF Symbols.
- **Biometrics (`BiometricPrompt`)**: Replaces iOS `Face ID` with `BIOMETRIC_STRONG or DEVICE_CREDENTIAL`, rendering dynamic biometric wording/iconography (`Allow` with Fingerprint/Biometric shield icon).

---

## 2. Core Screen Requirements (`UE01`–`UE13`)

| Screen ID | Title | Material 3 Native Implementation & UX Adaptation |
| :--- | :--- | :--- |
| **`UE01_AGENTS_HOME`** | Agents Home | `TopAppBar` (Host Switcher Chip with online dot + `Display Options` & `New Project` icon buttons), M3 Search field, horizontal `FilterChip` bar (`All`, `Running`, `Needs you`, `Unread`), `PINNED` card group, collapsible Project groups (`ledger-svc`, `web-console`) with `SwipeToDismissBox` (Pin/Archive), M3 bottom `NavigationBar` + Periwinkle squircle `FAB`. |
| **`UE02_DISPLAY_OPTIONS`** | Display Options Sheet | `ModalBottomSheet` with drag handle, `Reset` / `Done` actions, `Group By` (`Project`/`Host`/`None`), `Sort Conversations` inline/expanded M3 menu (`Last Updated`, `Date Created`, `Title`, `Newest First`/`Oldest First`), `Auto Pin` & `Archived Only` `Switch` rows, and `Mark All as Read` action with unread counter. |
| **`UE03_CONTEXT_MENU_PIN`** | Context Preview Sheet & Swipe | Long-press `ModalBottomSheet` displaying rich conversation preview card (`Implementation Plan` + `Awaiting review` chips + excerpt), 6 Material action rows (`Pin`, `Mark as Unread`, `Rename`, `Move to Project`, `Archive`, destructive `Delete`), plus inline Swipe Shortcut strip (`Pin` `#8EB4FF` & `Archive`). |
| **`UE04_PROJECT_DETAIL`** | Project Detail | `TopAppBar` with `←` back icon, folder icon + `ledger-svc` title + `~/code/ledger-svc` path, metadata pills (`Local · MacBook Pro`, `main`, `5 conversations`), full-width Periwinkle `New Conversation in Project` CTA button, `PrimaryTabRow` (`Active`, `Archived`, `Automations`), filtered conversation list, and `THIS PROJECT` tools card (`Nightly dependency audit`, `Open on Host`, `Project rules & skills`). |
| **`UE05_CREATE_PROJECT`** | Create New Project | M3 Full-Screen Dialog (`Cancel` / `New Project`), `RUNS ON` segmented toggle (`MacBook Pro` vs `Cloud`), `SOURCE` selectable cards (`GitHub repository` vs `Drive folder`), repo search field & selectable repo list (`acme/ledger-svc`, `acme/web-console`, `acme/design-tokens`), `Branch & worktree`, `Name`, optional Drive links / `env-setup.sh` script, and bottom `Create Project` CTA. |
| **`UE06_AUTOMATIONS`** | Automations Hub | `TopAppBar`, inline natural-language prompt bar (`Every weekday at 9, summarize...` + `Create` CTA), `SCHEDULED` filter chip, grouped cards (`SCHEDULED` with `Next Run` / `Last Run` + `▶ Run Now`, `ALWAYS ON` PR triage, `PAUSED` with `Resume` button), M3 bottom `NavigationBar` + `+` FAB. |
| **`UE07_CHAT_AND_COMPOSER`** | Cascade Chat & Composer | `TopAppBar` (title, project/host subtitle, `+128 -14` diff pill, Overview icon), `LazyColumn` trajectory (User prompt, collapsible `Thought for 14s`, `Implementation Plan` artifact card, `Task · 4 of 7 done` 7-segment progress card, Amber `Run this command?` Biometric approval card with `Deny` / `Allow`, v2.33 multi-agent cards, forward-compatible generic step/gate cards), status strip (`Waiting for your approval · Step 5 of 7` + `Stop`), and docked `ChatComposer` (`@ratelimit.go` chip, `/` & `@` autocomplete overlay, `+` context button, `Planning` mode pill, `Gemini 3.1 Pro` model pill, voice mic, send/queue button). |
| **`UE08_ADD_CONTEXT`** | Add Context Sheet | `ModalBottomSheet` with search input, 5 category tiles (`Files`, `Folder`, `Mentions`, `Actions`, `Skills`), SAF document picker trigger, multi-select rows (`ratelimit.go`, `load/`, `Idempotency keys for payouts`, `Terminal`, `/boost`, `go-testing`) with M3 `Checkbox`, selected count footer & `Add to message` CTA. |
| **`UE09_MODEL_AND_MODE`** | Model, Mode & Agent Sheet | `ModalBottomSheet` (`Done` button), dual selectable mode cards (`Planning` vs `Fast`), 4-level Thinking Effort segmented selector (`Low`, `Medium`, `High`, `Extra`), model rows (`Gemini 4 Neon`, `Gemini 3.1 Pro`, `Gemini 3.8 Flash`, `Claude Opus 5.5`, `Claude Sonnet 5.5`, `Orchestrator` with effort-lock hint), `ModelUsageQuota` card, and `AGENT` persona chips (`Default`, `go-reviewer`, `release-captain`). |
| **`UE10_STRUCTURED_QUESTION`** | Structured Question Card | Chat header + intro prompt + interactive multi-step card with stepper chips (`1 Storage ✓`, `2 Actions`, `3 Retention`), multi-select `Checkbox` / single-select `RadioButton` rows (`>=48dp`), `Something else...` custom write-in field, `Back` / `Next` / `Submit` buttons, and bottom freeform composer. |
| **`UE11_PLAN_REVIEW`** | Implementation Plan Review | Top bar (`Implementation Plan`, subtitle, `[💬 N]` comment badge), Amber paused banner, rendered plan prose with `MODIFY`/`NEW` badges, pending inline comment cards (`WL You · Pending`), selection callout action bar (`Comment` / `Copy`), and docked bottom action bar (`Proceed` + `Send N comments`). |
| **`UE12_TURN_DIFF_REVIEW`** | Turn Diff & Git VCS Review | Top bar (`Review changes`, `Accept all`, `Commit`), `Turn 1..3 / All` + `Turn/Working Tree/Staged/Branch` mode pills, file pager card (`middleware/ratelimit.go`, `File 1 of 4`, `+96 -4`, `M`), `Revert hunk`, monospace syntax-highlighted diff lines with horizontal scroll, inline Line 29 comment composer (`Add to review` / `Send to agent`), Git Stage/Unstage/Discard actions, and bottom bar (`Viewed` checkbox, `Revert file`, `Accept file`). |
| **`UE13_LIVE_ACTIVITY_SPEC`** | Android Live Updates & Progress Spec | **Android Native Adaptation**: Showcases all Android 16 Live Update (`Notification.ProgressStyle` + Status Bar Live Chip) & Multi-Agent Lock Screen / Glance Widget states: (1) Status Chip Running (`4/7`), (2) Status Chip Waiting (`Approve`), (3) Compact Minimized Progress Badge, (4) Status Chip Done (`+128 -14`), (5) Expanded Notification Running (7-segment `ProgressStyle` + `Stop` / `Open`), (6) Expanded Notification Waiting (`Biometric Allow` / `Deny`), (7) Lock Screen & Glance Multi-Agent Card. |

---

## 3. v2.33 Extended Flows & System Integration

1. **Pairing & Settings (`feature-pairing`)**: Welcome screen, CameraX QR Scanner, scoped `WebView` + `CookieManager` Google Cloud Relay Sign-In (`SAPISID` / `__Secure-3PAPISID` + `X-Goog-Api-Key`), Direct LAN/Tailscale manual host setup, Host Capability diagnostics, Appearance & Theme (incl. Material You Dynamic Color), Permissions Preset & Allow/Deny rules, and Customizations Hub (Skills, Rules, MCP Servers w/ Restart, Plugins Marketplace, Hooks).
2. **v2.33 Orchestration Sheets**: `ConversationOverviewSheet`, `SideQuestionSheet` (`/btw` multi-turn + insert into main), `SwarmBoardSheet` (`/swarm` roster + posts + `@member` filter), `VoiceModeSheet` (Gemini Live controls + Call Summary persistence), `QueuedMessagesSheet`, `TurnNavigatorSheet`, and `RichArtifactViewerSheet` (PDF / Jupyter `.ipynb` / Image+Video region commenting / sandboxed HTML GenUI & Mermaid).
3. **Android Share Receiver**: `ACTION_SEND` / `ACTION_SEND_MULTIPLE` intent handler ingesting text, URLs, images, PDFs, and arbitrary files directly into active or new Cascade chats via `ContentResolver`.
4. **Live Progress & Notifications**:
   - **Android 16+ (API 36.1+)**: `NotificationCompat.ProgressStyle` + `setRequestPromotedOngoing(true)` + `setShortCriticalText(...)` (zero custom `RemoteViews`, respects user dismiss via `LiveUpdateDismissReceiver`).
   - **Android 10–15 Fallback**: Foreground Service (`dataSync`) + progress notification + high-priority `WAITING` channel.
   - **Biometric Approval Trampoline**: Transparent activity launched from notification `Allow` action to run `BiometricPrompt` and dispatch `HandleCascadeUserInteraction`.
   - **Manual Cancel Suppression**: Never emit "Task completed" notification when user manually cancels a turn.
