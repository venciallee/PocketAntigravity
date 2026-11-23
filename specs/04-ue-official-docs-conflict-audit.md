# Official Docs Conflict Audit: Legacy `specs/` vs New `docs/ue/` Canvas (v2.34.0 Ground Truth)

> **Audit Date**: 2026-11-23  
> **Official Source of Truth**: Google Antigravity 2.0 Documentation (`https://antigravity.google/docs/*`, verified through App `v2.34.0` / Nov 20, 2026)  
> **Compared Artifacts**: Existing `specs/` + `docs/PLATFORM_STATUS.md` vs synced concept canvas `docs/ue/` (PR #46)

---

## Executive Verdict Summary

Out of **10 conflicts** identified between the legacy `specs/` / `docs/PLATFORM_STATUS.md` and the new `docs/ue/` canvas:

- **7 are outdated legacy `specs/` / doc defects** where the new `docs/ue/` canvas matches current Google Antigravity 2.0+ official documentation (`v2.30`–`v2.34`).
- **2 are minor discrepancies inside `docs/ue/` (notes vs boards or exact copy)** that we reconcile cleanly against official docs.
- **1 is an OS/platform scope boundary** (Android 16 `Notification.ProgressStyle` native shade vs WatchOS / WidgetKit extensions).

---

## Detailed Conflict Resolution Matrix

### 1. UE09: `Planning` vs `Fast` Mode Cards & Model Catalog
- **Conflict**:
  - Legacy `specs/esdd-ir.json`, `specs/android/esdd-android-ir.json`, `specs/01-ue-product-and-tech-spec.md`, `specs/android/01-prd-and-ux-spec.md`, `specs/02-esdd-e2e-test-plan.md` (`TC-10`), and `docs/PLATFORM_STATUS.md` specify `Planning` vs `Fast` toggle cards (`mode-card-planning` / `mode-card-fast`), default `Gemini 3.1 Pro`, and `Agent` persona pills inside UE09.
  - New `docs/ue/` (`ios-model`, `and-model`) removes `Planning`/`Fast`, sets title to `Model`, lists `Orchestrator (Neon plans · Hydrogen executes)`, `Gemini 4 Neon [New]` (default) with 4 inline thinking levels (`Low` / `Medium` / `High` / `Extra High`), `Gemini 4 Carbon`, `Gemini 4 Argon`, `Gemini 4 Hydrogen`, `Claude Opus 5.5`, `Gemini 3.8 Flash`, `More models ›`, and `Five Hour Limit Remaining` / `Weekly Limit Remaining` bars + `View Usage`.
  - PR #46's author suspected `Gemini 4 Neon / Carbon / Argon / Hydrogen` might be concept placeholder names.
- **Official Documentation Evidence**:
  - [`https://antigravity.google/docs/models/`](https://antigravity.google/docs/models/) & [`https://antigravity.google/docs/changelog/`](https://antigravity.google/docs/changelog/) (`v2.34.0`, Nov 18–20, 2026):
    - **Gemini 4 Neon** is the real official default reasoning model (512K context, 4 thinking levels: `Low`, `Medium`, `High`, `Extra` / `xhigh`).
    - **Gemini 4 Carbon**, **Gemini 4 Argon**, **Gemini 4 Hydrogen** (4 levels), **Orchestrator** (pairing Neon/Carbon/Argon/Claude Opus 5.5 as Planner with Hydrogen/Claude Sonnet 5.5 as Executor), **Claude Opus 5.5 (Thinking)**, **Claude Sonnet 5.5 (Thinking)**, and **Gemini 3.8 Flash** are the exact official models. `Gemini 3.1 Pro` is Enterprise-only.
    - The official Model selector footer literally displays **View Usage** with **Five Hour Limit Remaining** and **Weekly Limit Remaining**.
  - [`https://antigravity.google/docs/plan/`](https://antigravity.google/docs/plan/):
    - In Antigravity App 2.x, planning is invoked via the **`/plan` slash command** (and interactive discovery interview), **not** a `Planning` vs `Fast` mode toggle in the model picker.
- **Verdict**: **Legacy `specs/` problem (outdated).**
- **Resolution**:
  - Update `specs/esdd-ir.json`, `specs/android/esdd-android-ir.json`, UE specs, and both iOS & Android UE09 + Composer to remove `Planning`/`Fast` UI controls, default to `Gemini 4 Neon` (`Extra High`), render `Orchestrator`, Gemini 4 family, `More models`, 4-level thinking selector (`Low` / `Medium` / `High` / `Extra High`), and 5h/Weekly quota bars.
  - Retain `CascadeExecutionMode` enum in `shared/core-model` & `AntigravityData` strictly for backward wire compatibility with legacy Desktop `v2.20`–`v2.31` hosts.

---

### 2. UE01 & Global Navigation IA: Sidebar Drawer + New Conversation Home vs Floating Tab Bar + Agents Feed
- **Conflict**:
  - Legacy `specs/` used a 3-tab bottom bar (`Agents` | `Automations` | `Settings`) + detached compose FAB, opening onto a conversation list feed (`Agents Home`).
  - New `docs/ue/` (`Main` / `and-new` + `ios-drawer` / `and-home`) adopts Antigravity Desktop's information architecture: Home is **New Conversation** (`Welcome back, Alex. Where should we pick up?` + amber `Needs approval` jump banner + PC-isomorphic bottom composer), while a **left Sidebar Drawer** (iOS slide-over drawer / Android M3 `ModalNavigationDrawer`) hosts `+ New Conversation`, `Automations`, `Customizations`, `Pinned`, `Projects` (with Display Options filter & New Project `+`), single-line conversation rows, and bottom `Settings`.
- **Official Documentation Evidence**:
  - [`https://antigravity.google/docs/getting-started/`](https://antigravity.google/docs/getting-started/), [`https://antigravity.google/docs/settings/`](https://antigravity.google/docs/settings/), [`https://antigravity.google/docs/remote-agents/`](https://antigravity.google/docs/remote-agents/):
    - Official Antigravity App opens on Home / New Conversation with project/worktree selector & prompt box, with a left sidebar containing New Conversation, Automations, Customizations, Projects (`+` New Project), conversation list, and Settings pinned to the bottom of the sidebar.
- **Verdict**: **Legacy `specs/` problem (diverged from Antigravity App 2.x IA).**
- **Resolution**:
  - Align both iOS and Android to the PC-isomorphic **New Conversation Home (`UE01_AGENTS_HOME`) + Left Sidebar Drawer (`UE01B_SIDEBAR_DRAWER`)** architecture, removing the bottom tab bar and floating compose FAB.

---

### 3. UE02: Display Options Grouping (`Project` vs `Workspace/Status/Date`) & Filter/Sort Options
- **Conflict**:
  - `docs/PLATFORM_STATUS.md:37` claimed UE02 was "Group by Workspace/Status/Date".
  - Both existing code (`DisplayGroupBy = Project | Host | None`) and `docs/ue/` (`ios-display-options`, `and-display-options`) use **`Group By: Project`**, `Sort Conversations: Last Updated`, `Sort Projects: Custom Order`, `Filter: All conversations`, `Display: Comfortable · Previews`, `Auto Pin`, `Archived Only`, and `Mark All as Read (3 unread)`.
- **Official Documentation Evidence**:
  - [`https://antigravity.google/docs/projects/`](https://antigravity.google/docs/projects/) ("Key differences: workspace vs. projects"): Antigravity 2.x replaced the single-repo "Workspace" model with multi-folder **Projects**.
  - [`https://antigravity.google/docs/search/`](https://antigravity.google/docs/search/) ("Sort and filter conversations", v2.26.0+): Official sort/filter controls support `Sort Conversations` (`Last Updated`, `Last Prompt`) and `Filter` (`Only Unread`, `Only Archived`, `Only Automations`).
- **Verdict**: **`docs/PLATFORM_STATUS.md` doc bug.**
- **Resolution**: Fix `docs/PLATFORM_STATUS.md`, keep `Project` as default `Group By` (preserving `Host` / `None` in the picker for multi-host mobile), and align the UE02 sheet layout strictly to `ios-display-options` and `and-display-options`.

---

### 4. UE08: Legacy `Workflows` Deprecated → `Skills`; `Add Context` Menu (`Drive`) vs `/` Actions & Skills Popup
- **Conflict**:
  - Legacy `specs/` & `docs/PLATFORM_STATUS.md` still mentioned `Workflows` alongside `Rules`/`Skills`, placed `Skills` as a tile inside the full-height `Add Context` sheet (`tile-skills`), and did not distinguish the `+` Add Context popover from the `/` Actions & Skills popup.
  - New `docs/ue/` splits them into:
    1. **`Add Context` (`ios-add-context` / `and-add-context`)**: Compact popover above `+` with `Files`, `Folder`, `Mentions`, `Actions`, and `Drive [Set up]`.
    2. **`/` Slash Menu (`ios-slash` / `and-slash`)**: Categorized into **Actions** (`/plan`, `/goal`, `/schedule`, `/automation`, `/btw`) and **Skills** (`/go-testing`, `/api-review`). Zero legacy `Workflows`.
- **Official Documentation Evidence**:
  - [`https://antigravity.google/docs/migration/workflows-to-skills/`](https://antigravity.google/docs/migration/workflows-to-skills/): *"Workflows are deprecated... migrate to Agent Skills. The new workflows system is Dynamic Workflows (`/run-workflow`)"*.
  - [`https://antigravity.google/docs/skills/`](https://antigravity.google/docs/skills/): Skills are invoked manually via `/<skill-name>` slash commands in the message box.
  - [`https://antigravity.google/docs/at-mentions/`](https://antigravity.google/docs/at-mentions/): *"To start a mention without typing `@`, click Add Context (`+`) in the message box and select Mentions."*
  - [`https://antigravity.google/docs/remote-agents/`](https://antigravity.google/docs/remote-agents/): Google Drive is a first-class resource alongside Files/Folders.
- **Verdict**: **Legacy `specs/` & `docs/PLATFORM_STATUS.md` problem (outdated).**
- **Resolution**:
  - Remove all legacy `Workflows` references from specs, docs, and UI comments (retaining `/run-workflow` exclusively as Dynamic Workflows).
  - Replace `Skills` tile in UE08 Add Context with `Drive [Set up]` and align UE08 to the anchored `Add Context` popover (expanding into the interactive multi-select file/folder/mention picker when a category is tapped), paired with the categorized `/` Actions & Skills overlay (`UE08B_SLASH_MENU`).
  - Keep `/btw` gated behind the shared `enableSideQuestionBtw` feature flag in live default catalogs per `verify_advisory_hygiene.py`, enabled in the verification scene to keep screenshot parity.

---

### 5. Customizations (`Rules & skills`): Entry Point & Mobile Scope (**Internal UE Note Conflict Reconciled**)
- **Conflict**:
  - `docs/PLATFORM_STATUS.md:63` claimed iOS `CustomizationsSettingsView` covered full Rules/Skills/Workflows/MCP, which became false after PR #44 flattened Settings. Android `SettingsAndCustomizationsScreen` still bundled collapsible Desktop Customizations panels inside Settings. Both platforms' `ProjectDetail` row `project-row-skills` (`Project rules & skills (4)`) was a dead no-op button.
  - **Internal conflict inside `docs/ue/`**: Designer note `custBrief` in `canvas.json` wrote *"入口：项目详情 → Project rules & skills（不单独占侧栏）"*, **contradicting** the visual boards `ios-drawer.png` and `and-home.png`, which **both** display a `Customizations` navigation item directly under `Automations` in the left sidebar!
- **Official Documentation Evidence**:
  - [`https://antigravity.google/docs/settings/`](https://antigravity.google/docs/settings/) & [`https://antigravity.google/docs/customization-discovery/`](https://antigravity.google/docs/customization-discovery/):
    - Official Antigravity App exposes **`Customizations` in the left sidebar** (*"open Customizations in the left sidebar instead of Settings"*) **AND** per-project Customizations inside Project settings (*"Under Projects, select the project... Scroll to the Customizations section"*). Settings does **not** duplicate Customizations.
- **Verdict**: **Both legacy `PLATFORM_STATUS.md`/Android Settings AND the `custBrief` text note conflicted with official docs — whereas the visual UE boards (`ios-drawer`/`and-home` + `ios-project-detail`/`and-project` + `ios-customizations`/`and-customizations`) match official docs!**
- **Resolution**:
  - Implement dedicated `ProjectRulesAndSkillsView` (iOS) and `ProjectRulesAndSkillsScreen` (Android) matching `ios-customizations.png` / `and-customizations.png` (token budget bar `Loaded every turn · 6.2k tokens`, `Skills / Rules / Plugins / Agents` tabs, `Global` / `Workspace` / `Plugin` badges, live plugin enable/disable switches, and desktop-editing footer note).
  - Wire **both** the Sidebar Drawer `Customizations` item AND `ProjectDetail` `project-row-skills` to open this screen.
  - Flatten Android Settings to match `and-settings.png` & `and-settings-more.png` (matching iOS PR #44) and add the `Language` (`English` / `简体中文`) setting across KMP, iOS, and Android.

---

### 6. UE07: Composer Chrome & Message-Box Permissions Preset (`🛡 Default ⌄`)
- **Conflict**:
  - Legacy `specs/` placed `Planning ⌄` and `Gemini 3.1 Pro ⌄` pills in the chat composer, burying Permissions in an overflow menu.
  - New `docs/ue/` (`Main`/`and-new`, `ios-chat`/`and-chat`, `ios-preset`/`and-preset`) places `[+] [Gemini 4 Neon / Extra High ⌄] [🛡 Default ⌄] [🎤] [→]` in the composer, with `🛡 Default ⌄` opening the anchored `Permissions for this conversation` popover (`Request Review`, `Default ✓`, `Auto`, `Turbo`, plus `Default for new turns: Settings > Permissions ›`).
- **Official Documentation Evidence**:
  - [`https://antigravity.google/docs/settings/`](https://antigravity.google/docs/settings/) & [`https://antigravity.google/docs/sandbox/`](https://antigravity.google/docs/sandbox/): *"You can also choose a preset from the permissions picker in the message box composer (`v2.23.0+`): Request Review, Default, Auto, or Turbo."*
- **Verdict**: **Legacy `specs/` problem (outdated).**
- **Resolution**: Replace `Planning ⌄` with the anchored `🛡 Default ⌄` Permission Preset picker across iOS & Android composers and add `UE07B_PERMISSIONS_PRESET` verification coverage.

---

### 7. UE06: Automations List, Detail, Edit & Unattended Model Labels
- **Conflict**:
  - Legacy `specs/` had bottom tab bar + `+` FAB on Automations, no Automation Detail or Edit screens, and Android lacked filter chips & per-card overflow menu (`Run Now`, `Edit Schedule & Prompt`, `Pause`, `Restart`, `Delete`).
  - New `docs/ue/` removes tab bar/FAB, adds `ios-automation-detail`/`and-automation-detail` (`Run Now`, `Pause`, `PROMPT`, `Trigger/Repeats/Next run`, `RECENT RUNS` with `Retry`) and `ios-automation-edit`/`and-automation-edit` (`Edit Schedule & Prompt` / `Edit automation`).
- **Official Documentation Evidence**:
  - [`https://antigravity.google/docs/sidecars/`](https://antigravity.google/docs/sidecars/) & [`https://antigravity.google/docs/commands/automation/`](https://antigravity.google/docs/commands/automation/): Confirms `Create with Prompt`, `Each run opens a new conversation`, IANA timezone pinning (`CRON_TZ`), `Pause`/`Resume`, and unattended execution.
- **Verdict**: **Legacy `specs/` incomplete.** (Note: `Flash` / `Pro` / `Flash Lite` labels on automation schedule cards are shorthand tier labels for `Gemini 3.8 Flash` / `Gemini 4 Neon` / `Flash Lite`.)
- **Resolution**: Remove bottom chrome from Automations, align list screens to `ios-automations`/`and-automations`, and build full interactive Detail & Edit screens on both iOS and Android (`UE06B_AUTOMATION_DETAIL`, `UE06C_AUTOMATION_EDIT`).

---

### 8. UE10: Structured Question Copy & Button Alignment (**Minor UE HTML Bug Caught**)
- **Conflict**:
  - Legacy `specs/` showed header `ledger-svc · Planning · Gemini 3.1 Pro`; new `docs/ue/` updates this to `ledger-svc · /plan interview · Gemini 4 Neon`.
  - Visual inspection of `docs/ue/ios/ios-ask.png` caught a CSS typo in `docs/ue/source/ios-ask.dc.html`: the primary `Next` pill label is left-aligned instead of centered (`text-align: inherit` on `<button>`).
- **Official Documentation Evidence**:
  - [`https://antigravity.google/docs/plan/`](https://antigravity.google/docs/plan/) confirms `/plan` conducts an interactive clarification interview before drafting the plan.
- **Verdict**: **Spec header outdated; minor CSS alignment bug in `ios-ask.dc.html` fixed in native iOS implementation (centered `Next` button).**

---

### 9. UE12: Turn Diff Single-Column Line-Number Gutter
- **Conflict**:
  - Legacy `specs/` used a dual old/new gutter in places; new `docs/ue/` (`ios-diff`, `and-diff`) uses a compact single-column line-number gutter with color-coded change strips and left blue active-line bar on Line 29.
- **Official Documentation Evidence**:
  - [`https://antigravity.google/docs/changelog/`](https://antigravity.google/docs/changelog/) (`v2.34.0`, Nov 20, 2026): *"Diff views now use a single-column line-number gutter with color-coded change strips, giving code more horizontal room before wrapping."*
- **Verdict**: **New `docs/ue/` matches official `v2.34.0`!**
- **Resolution**: Align both iOS and Android `TurnDiffReview` views to single-column line-number gutter + color-coded strips.

---

### 10. UE13: Live Activity (iOS) vs Live Update Notification Shade (Android)
- **Conflict**:
  - Legacy Android `UE13_LIVE_ACTIVITY_SPEC` mimicked iOS's `800×500` light-background Dynamic Island poster.
  - New `docs/ue/android/and-live-update.png` is a `412×915` native dark Android 16 notification shade showcasing Running (`ProgressStyle` 7-segment bar + `Stop`/`Open`), Amber Approval (`Deny` / Biometric `Allow` / `Reply`), Cloud progress (`step 2 of 5`), Done (`+42 -31` + `Review`), and `Manage` / `Clear all`.
- **Verdict**: **Android UE13 spec should follow native Android 16 notification shade (`and-live-update.png`)**, while iOS UE13 stays aligned with `docs/ue/ios/live-activity.png`.
- **Out-of-scope note**: Apple Watch boards (`docs/ue/watch/*`) remain concept-only (no `watchOS` target in repository); iOS Home/Lock Screen Widget (`ios-widget`) is tracked separately from `AGPocketLiveActivity` (Android already ships `AntigravityAgentsGlanceWidget`).
