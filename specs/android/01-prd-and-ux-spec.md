# AG Pocket Android — Product Requirements & Material 3 Expressive UX Specification (v2.1)

- **Status**: Normative Spec (Aligned with Official Google Antigravity `v2.34.0`, `docs/ue/android/`, and KMP Shared Core)
- **Target Platform**: Android 10+ (`minSdk = 29`), `compileSdk = 36`, `targetSdk = 36` (Android 16)
- **UI Framework**: Native Kotlin + Jetpack Compose + Material Design 3 (`1.4.0` / Expressive patterns) + `ModalNavigationDrawer`
- **Baseline Viewport (Visual QA)**: `412×915dp` @ `xxhdpi` (Pixel 9 Portrait — all 20 core + extended UE screens)

See [`specs/04-ue-official-docs-conflict-audit.md`](../04-ue-official-docs-conflict-audit.md) for the official-docs audit reconciling legacy specs with `docs/ue/android/`.

---

## 1. Design Philosophy: "Antigravity PC-Aligned IA × Native Android Material 3"

The Android client shares 100% information architecture with iOS and Antigravity Desktop (`v2.34.0`), rendered using idiomatic **Material Design 3**:

### 1.1 Neutral Dark Obsidian Tonal Surface Elevation
- **Dark Mode (Default — Matte Neutral Obsidian aligned to `docs/ue/android/`)**:
  - `background` / `canvasObsidian` = `#111113`
  - `surfaceContainer` = `#1B1B1E` (Grouped Cards, Drawer, Composer Shell)
  - `surfaceContainerHigh` = `#212125` (Input Box, Host Pill, Elevated Cards)
  - `surfaceContainerHighest` = `#26262B` (Menus, Active Selection, Popovers)
  - `outlineVariant` = `#2E2E34` / `#FFFFFF` @ `10%`
  - `primary` = `#8DB8FF` (Periwinkle CTA), `onPrimary` = `#0A0E17`
- **Light Mode (Soft Porcelain)**:
  - `background` = `#F4F5F8`, `surfaceContainer` = `#FFFFFF`, `surfaceContainerHigh` = `#E6E9F2`, `primary` = `#2F66E8`, `onPrimary` = `#FFFFFF` (WCAG AA >= 4.5:1).
- **Theme Presets & Language**: `Obsidian` (default), `Nord`, `Everforest`, opt-in **Android 12+ Material You Dynamic Color** (`useDynamicColor`, semantic status colors locked), and `Language` (`English` / `简体中文`).
- **Locked Semantic Status Palette**:
  - `statusRunning`: `#7DA7FF` (Dark) / `#2F66E8` (Light)
  - `statusWaiting`: `#F2B866` (Dark) / `#B86E00` (Light) — Biometric Gate & Plan Review Pause
  - `statusDone`: `#6FD8A6` (Dark) / `#198754` (Light) — Completed & Diff Additions
  - `statusError`: `#F07167` (Dark) / `#CF372E` (Light) — Errors, Destructive Actions, Diff Deletions

### 1.2 Navigation Architecture (`ModalNavigationDrawer` + New Conversation Home)
- **Home (`UE01` / `and-new.png`)**: Top App Bar (`☰` Drawer button, centered `● MacBook Pro ⌄` host chip, `🔍` Search), centered greeting `Welcome back, Alex. Where should we pick up?`, tonal amber `Needs approval` quick-jump card, and PC-isomorphic bottom `ChatComposer` (`📁 ledger-svc ⌄`, `🌿 Repo default ⌄`, `☁️`, text input, `+`, `Gemini 4 Neon / Extra High ⌄`, `🛡 Default ⌄`, `🎤`, `→`).
- **Drawer (`UE01B` / `and-home.png`)**: Material 3 `ModalDrawerSheet` (`+ New Conversation` active pill, `Automations`, `Customizations`, divider, `Pinned`, `Projects` with Display Options & New Project icons, collapsible `ledger-svc` & cloud `acme/web-console` with single-line rows & status indicators, bottom divider + `Settings`).
- **No bottom `NavigationBar` or floating compose FAB on Home/Automations**, matching Antigravity Desktop and `docs/ue/android/`.

---

## 2. Core & Extended Screen Requirements (Aligned 1:1 with `docs/ue/android/*.png`)

| Screen ID | UE Board | Material 3 Native Implementation |
| :--- | :--- | :--- |
| **`UE01`** | `and-new.png` | New Conversation Home (`☰`, Host chip, `🔍`, greeting, amber `Needs approval` tonal card, PC-aligned Composer) |
| **`UE01B`** | `and-home.png` | M3 `ModalDrawerSheet` (`+ New Conversation`, `Automations`, `Customizations`, `Pinned`, `Projects`, `Settings`) |
| **`UE02`** | `and-display-options.png` | `Display options` M3 Bottom Sheet (`Reset`, `Group by: Project`, `Sort conversations` dropdown, `Sort projects`, `Filter`, `Display: Comfortable`, `Auto pin` / `Archived only` M3 Switches, `3 unread` + tonal `Mark all as read`) |
| **`UE03`** | `and-context-menu.png` | Conversation Action Bottom Sheet (preview card with `Gemini 4 Neon`, 7 M3 rows: `Pin`, `Mark as unread`, `Rename`, `Move to project`, `Export summary`, `Archive`, coral `Delete`) |
| **`UE04`** | `and-project.png` | Project Detail (`←`, `⋮`, `ledger-svc`, `~/code/ledger-svc`, outlined chips `Local · MacBook Pro` / `main ↑2` / `Clean`, M3 `PrimaryTabRow` `Active · 4 | Archived · 2 | Automations · 1`, single-line rows, `This project` (`Nightly dependency audit` → Detail, `Project rules & skills (4)` → Rules & Skills), bottom-right Extended FAB `New conversation in project`) |
| **`UE05`** | `and-new-project.png` | Full-Screen Dialog (`✕ New project` + filled `Create`, `Runs on` Segmented Button, `Source` FilterChips, Search + RadioButton repo list, `Branch` dropdown + `New worktree` Switch + `Name` OutlinedTextField) |
| **`UE06`** | `and-automations.png` | Automations (`☰`, `🔍`, M3 FilterChips `All / Scheduled 2 / Always on 1 / Paused 1`, `Create with Prompt` card, cards with `⋮` overflow menu `Run Now / Edit Schedule & Prompt / Pause / Restart / Delete`, `Resume` button) |
| **`UE06B/C`** | `and-automation-detail.png`, `and-automation-edit.png` | Automation Detail (`Run now` / `Pause`, `Prompt`, `Next run`, `Runs on`, `Recent runs` with `Retry`) & Full-Screen `Edit automation` Dialog (`Save`, `Name`, `Prompt`, `Project`, `Trigger`, cadence chips, `Time`, `Model` segmented buttons, `Delete automation`) |
| **`UE07`** | `and-chat.png` | Cascade Chat (`☰`, `Add rate limiter / ledger-svc · MacBook Pro`, outlined `+128 -14`, `⋮`; right-aligned user bubble, prose, `Implementation Plan` card, `Task · 4 of 7 done` 7-segment bar, Amber `Run this command?` Biometric `Deny`/`Allow`, PC-aligned Composer) |
| **`UE07B`** | `and-preset.png` | Anchored `Permissions for this conversation` menu (`Request Review`, `Default ✓`, `Auto`, `Turbo`, footer `Default for new turns: Settings > Permissions`) |
| **`UE08`** | `and-add-context.png` | Anchored `Add Context` menu (`Files ›`, `Folder ›`, `Mentions ›`, `Actions ›`, divider, `Drive [Set up]`, footer `Files and folders come from MacBook Pro`), expanding into multi-select picker or `/` overlay |
| **`UE08B`** | `and-slash.png` | `/` Actions (`/plan`, `/goal`, `/schedule`, `/automation`, feature-flagged `/btw`) & Skills (`/go-testing`, `/api-review`) overlay |
| **`UE09`** | `and-model.png` | `Model` Bottom Sheet (`Done`, `Orchestrator`, selected `Gemini 4 Neon [New] ✓` with 4 M3 FilterChips `Low / Medium / High / Extra High`, `Gemini 4 Carbon`, `Argon`, `Hydrogen`, `Claude Opus 5.5`, `Gemini 3.8 Flash`, `More models ⌄`, `Five Hour Limit Remaining` & `Weekly Limit Remaining` bars + `View Usage`) |
| **`UE10`** | `and-ask.png` | `/plan interview` Question screen (user prompt bubble, `Gemini 4 Neon`, `✓ Storage: Postgres table` chip, 3-segment progress bar, 4 M3 checkboxes, `Back` / `Next · 3 selected`, bottom `Or reply in your own words`) |
| **`UE11`** | `and-plan-review.png` | Plan Review (`v2` chip + comment icon badge `2`, paused banner, `Proposed changes`, `MODIFY`/`NEW`, `AL You · Pending`, `Verification`, bottom `[💬 Comment] [Send 2 comments] [Proceed]`) |
| **`UE12`** | `and-diff.png` | Turn Diff (`Accept all`, `Turn 1..3/All` chips, file dropdown card, `Revert hunk`, single-column line gutter with left active indicator on Line 29, inline comment card `Add to review` / `Send to agent`, `Viewed` / `Revert file` / `Accept file`) |
| **`UE13`** | `and-live-update.png` | Dark Android 16 Live Update Notification Shade (`412×915dp`: Running 7-segment `ProgressStyle` + `Stop`/`Open`, Amber `Run this command?` + `Deny`/`Allow`/`Reply`, Cloud `step 2 of 5`, Done `+42 -31` + `Review`, bottom `Manage`/`Clear all`) |
| **`UE14`** | `and-customizations.png` | Project `Rules & skills` (`Loaded every turn · 6.2k tokens`, `Skills 5 | Rules 4 | Plugins 2 | Agents 1` tabs, `Global`/`Workspace`/`Plugin` badges, `Plugins in this project` M3 Switches, desktop-editing footer) |
| **`UE15`** | `and-settings.png`, `and-settings-more.png` | Flattened Material 3 Settings (Connected host card + `Scan New QR`, `Available hosts` radio rows, `Appearance` segmented buttons + `Obsidian`/`Nord`/`Everforest` chips + `Dynamic color` switch, `Language`, `Permissions` radio group, `Notifications` + `Live updates`, `Sign out & disconnect host`, `About AG Pocket`) |
