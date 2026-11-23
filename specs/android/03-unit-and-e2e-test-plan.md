# AG Pocket Android — Unit Test, Interactive E2E & Visual Screenshot Comparison Plan (v2.1)

## 1. Four-Layer Verification Strategy

1. **Layer 1 — KMP Unit & Protocol Compatibility Matrix (`:shared:core-model`, `:shared:core-protocol`, `:shared:core-domain`)**:
   - Pure Kotlin Multiplatform unit tests (`commonTest`) for SemVer, `HostCapabilityRegistry`, `ProtocolCompatibilityEngine`, resilient enums (`AppLanguage`, `ContextCandidateCategory.DRIVE`, etc.), all 7 domain stores, automation edit/delete/restart, plugin toggles, live-write rollback, and updated `EsddVerificationFixtures` (`Gemini 4 Neon` default).
   - Live Connect-RPC E2E (`jvmTest`) against `verification/mock_language_server.py` covering v2.33–v2.34 RPCs + 3-version compatibility matrix.
2. **Layer 2 — Android Design System, Platform & Live Updates Unit Tests (`DesignSystemAndPlatformUnitTest`)**:
   - Neutral Obsidian Dark / Light / Theme presets, Material You semantic-status locking, `SemanticIcon` → Material Symbols mapping, `AndroidLiveUpdateBuilder` (`ProgressStyle`, `shortCriticalText`, dismiss & manual-cancel suppression), and platform adapters.
3. **Layer 3 — Android Interactive Compose E2E Suite (`ATC-01` .. `ATC-22`)**:
   - Real Compose tap, drawer, text-input, filter, toggle, multi-select, approval, edit, and sheet interactions via Robolectric + `ComposeTestRule` (`AndroidInteractiveE2eTest`) and KVM Android Emulator (`AndroidEmulatorE2eTest`).
4. **Layer 4 — 20-Screen Real Compose Screenshot Capture & Strict Target-UE Visual Comparison (`AndroidUeScreenshotTest` + `android_visual_compare.py`)**:
   - Captures pixel-accurate PNGs of ALL **13 core screens (`UE01`..`UE13`) + 7 extended screens (`UE01B`, `UE06B`, `UE06C`, `UE07B`, `UE08B`, `UE14`, `UE15`) + Light Mode spot checks** via Roborazzi (`GraphicsMode.NATIVE`, `412×915dp` Pixel portrait).
   - Enforces Material `>= 48dp` touch target bounds and `0px` horizontal overflow.
   - Generates 20 side-by-side comparison sheets (**LEFT: `docs/ue/android/*.png` Target UE** vs **RIGHT: Real Android Jetpack Compose Render**) + master overview gallery (`ANDROID_13_SCREENS_OVERVIEW.png` & `ANDROID_20_SCREENS_OVERVIEW.png`).

---

## 2. Executable Test Case Matrix (`ATC-01` .. `ATC-22`)

| Test ID | Target Screen / Domain | Test Action | Expected Assertion |
| :--- | :--- | :--- | :--- |
| **`ATC-01`** | `UE01_AGENTS_HOME` (`and-new`) | Render New Conversation Home; verify `☰`, `MacBook Pro` host pill, `🔍`, greeting, amber `Needs approval` banner, Composer (`ledger-svc`, `Repo default`, `Gemini 4 Neon / Extra High`, `Default`). Tap `Needs approval` | Routes directly into `Add rate limiter to /transfers` (`UE07`) with `>=48dp` targets & `0px` overflow |
| **`ATC-02`** | `UE01B_SIDEBAR_DRAWER` (`and-home`) | Open Drawer; verify `+ New Conversation`, `Automations`, `Customizations`, `Pinned`, `Projects` (`ledger-svc`, `acme/web-console`), `Settings`. Tap `Automations` / `Customizations` / `ledger-svc` | Each drawer entry routes cleanly to its destination without bottom tab bar |
| **`ATC-03`** | `UE02_DISPLAY_OPTIONS` | Open Display Options sheet; change sort field, toggle `Auto pin` & `Archived only`, tap `Mark all as read`, then `Reset` | Unread count drops `3 -> 0`; `Reset` restores defaults |
| **`ATC-04`** | `UE03_CONTEXT_MENU_PIN` | Open Context Action Sheet for `Fix flaky TestSettlementBatch`; verify `Gemini 4 Neon` preview card & all 7 actions; tap `Pin` | Toggles pinned state on `cas-flaky-settlement` |
| **`ATC-05`** | `UE04_PROJECT_DETAIL` | Navigate to `ledger-svc`; verify `main ↑2`, `Clean`, `Active · 4 / Archived · 2 / Automations · 1` tabs, `This project` tools; tap `Project rules & skills` and Extended FAB `New conversation in project` | Routes to `UE14` Rules & Skills and Cascade Chat cleanly |
| **`ATC-06`** | `UE05_CREATE_PROJECT` | Open `New project` full-screen dialog; toggle `Cloud` + `GitHub repository`, pick `acme/ledger-svc`, enter name, tap `Create` | Adds new project to `WorkspaceAndAutomationStore` |
| **`ATC-07`** | `UE06_AUTOMATIONS` | Open `Automations`; tap `Scheduled` / `Paused` filter chips, enter NL prompt + tap `Create`, open `⋮` overflow menu (`Run Now`), tap `Resume` on `Bundle size watch` | Filters list accurately, creates automation, triggers run, resumes paused item |
| **`ATC-08`** | `UE06B` & `UE06C` (`Automation Detail` & `Edit`) | Open `Nightly dependency audit` detail; tap `Retry` on Failed run, tap `Pause`, open `Edit automation`, modify prompt/cadence/model, tap `Save` | Updates run status, pauses automation, and saves edited schedule & prompt |
| **`ATC-09`** | `UE07_CHAT_AND_COMPOSER` | Render `Add rate limiter`; assert `+128 -14`, `Implementation Plan`, `Task · 4 of 7 done` 7-segment bar, Amber `Run this command?` card, and Composer (`Gemini 4 Neon`, `Default`) | 4 blue + 1 amber + 2 neutral segments and biometric approval buttons render cleanly |
| **`ATC-10`** | `UE07` & `UE07B` (`Approval`, `Send` & `Preset`) | Tap Biometric `Allow` on `vegeta attack`; tap `Default` preset pill → pick `Auto`; enter draft text & tap `→` Send | Resolves waiting interaction (`DONE`), updates permission preset, appends user turn |
| **`ATC-11`** | `UE08_ADD_CONTEXT` | Tap `+` → verify anchored `Add Context` menu (`Files`, `Folder`, `Mentions`, `Actions`, `Drive [Set up]`); tap `Files`, select `ratelimit.go`, tap `Add to message` | Injects `@ratelimit.go` chip into Composer |
| **`ATC-12`** | `UE08B_SLASH_MENU` | Type `/` in Composer → verify `Actions` (`/plan`, `/goal`, `/schedule`, `/automation`) and `Skills` (`/go-testing`, `/api-review`); tap `/plan` | Inserts `/plan ` into Composer draft |
| **`ATC-13`** | `UE09_MODEL_AND_MODE` | Open `Model` sheet (verify zero Planning/Fast cards); tap `Low`/`Medium`/`High`/`Extra High` chips, select `Orchestrator` (verifying effort lock), expand `More models`, verify 5h/Weekly quota bars, tap `Done` | Updates active model & effort in `SettingsAndCustomizationStore` |
| **`ATC-14`** | `UE10_STRUCTURED_QUESTION` | On `/plan interview` (`Audit log for admin actions`), toggle multi-select checkboxes, tap `Next · 3 selected` → Step 3 → `Submit` | Advances progress indicator to Step 3 and submits `AskQuestionAnswer` |
| **`ATC-15`** | `UE11_PLAN_REVIEW` | Open `Implementation Plan` (`v2`); verify paused banner, pending comment (`AL You · Pending`), add inline comment, tap `Send comments` / `Proceed` | Increments comment badge count and dispatches plan review comments |
| **`ATC-16`** | `UE12_TURN_DIFF_REVIEW` | Open `Review changes` (`Turn 3 · latest`, `middleware/ratelimit.go`); tap Line `29`, enter comment, tap `Send to agent`, toggle `Viewed`, tap `Accept file` | Attaches line-29 comment, toggles reviewed flag, accepts file |
| **`ATC-17`** | `UE13_LIVE_ACTIVITY_SPEC` | Render dark Android 16 Live Update Notification Shade (`412×915dp`) & unit-test `AndroidLiveUpdateBuilder` | Verifies Running (`ProgressStyle`), Waiting (Biometric `Allow`), Cloud, Done (`Review`), dismiss & manual-cancel suppression |
| **`ATC-18`** | `UE14_RULES_AND_SKILLS` | Render Project `Rules & skills`; verify `6.2k tokens` bar, switch `Skills`/`Rules`/`Plugins`/`Agents` tabs, toggle `Firebase` & `Datadog` switches | Filters items by tab and toggles plugin enabled state cleanly |
| **`ATC-19`** | `UE15_SETTINGS` | Render flattened M3 `Settings`; verify zero Desktop Customizations clutter, switch `System`/`Dark`/`Light`, `Obsidian`/`Nord`/`Everforest`, toggle `Dynamic color`, switch `Language` (`English` ↔ `简体中文`), change Permission preset | Persists all appearance, language, and permission preferences |
| **`ATC-20`** | **KMP Binary Protobuf & 3-Version Compat Matrix** | Run KMP RPC client against `mock_language_server.py` (605-step binary + Legacy/Current/Future matrix + static guardrails) | All 605 steps decode; negative caching, unknown field strip, and resilient enums pass |
| **`ATC-21`** | **v2.33 Extended Flows** | Interact with `ConversationOverviewSheet`, `/btw` `SideQuestionSheet`, `/swarm` `SwarmBoardSheet`, `VoiceModeSheet` (Call Summary), and `RichArtifactViewerSheet` | All v2.33 sheets open, update domain store state cleanly, and persist call summary |
| **`ATC-22`** | **Forward-Compatible Unknown Step & Gate** | Inject unrecognized future `CortexStepType.UNSPECIFIED` and unrecognized `WAITING` interaction gate | Renders `UnknownForwardStepCard` and `GenericFallbackInteractionCard` with working `Allow Once` / `Deny` |
