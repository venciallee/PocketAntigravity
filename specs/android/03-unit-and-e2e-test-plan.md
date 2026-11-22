# AG Pocket Android — Unit Test, Interactive E2E & Visual Screenshot Comparison Plan (v1.0)

## 1. Four-Layer Verification Strategy

1. **Layer 1 — KMP Unit & Protocol Compatibility Matrix (`:shared:core-model`, `:shared:core-protocol`, `:shared:core-domain`)**:
   - Pure Kotlin Multiplatform unit tests (`commonTest`) for SemVer, `HostCapabilityRegistry`, `ProtocolCompatibilityEngine` (unknown proto field stripping, rich item folding, enum downgrade & removal fallback), resilient enums, forward-compatible unknown steps/interactions, all 7 domain stores, live-write rollback, and deterministic `EsddVerificationFixtures`.
   - Real HTTP/Connect-RPC E2E (`jvmTest`) against `verification/mock_language_server.py` covering all v2.33 RPCs + Legacy/Current/Future 3-version compatibility matrix.
2. **Layer 2 — Android Design System, Platform & Live Updates Unit Tests (`DesignSystemAndPlatformUnitTest`)**:
   - Dark/Light/Theme preset contrast tokens & Material You semantic-status locking.
   - 100% `SemanticIcon` → Material Symbols mapping coverage.
   - Android 16 `LiveUpdateNotificationBuilder` validation (7-segment `ProgressStyle`, `shortCriticalText` for Running/Waiting/Done, zero custom `RemoteViews`, dismiss suppression, manual-cancel notification suppression).
   - Platform adapter behavior (`AndroidPreferencesStore`, `AndroidProjectionStorage`, `AndroidSharePayloadParser`, `BiometricApprovalPolicy`).
3. **Layer 3 — Android Interactive Compose E2E Suite (`ATC-01` .. `ATC-18`)**:
   - Executes real Compose tap, text-input, toggle, multi-select, filter, navigation, approval, and sheet interactions via Robolectric + `ComposeTestRule` (`AndroidInteractiveE2eTest`) and on KVM Android Emulator (`AndroidEmulatorE2eTest`).
4. **Layer 4 — 13-Screen Real Compose Screenshot Capture & iOS↔Android Visual Comparison (`AndroidUeScreenshotTest` + `android_visual_compare.py`)**:
   - Captures pixel-accurate PNGs of ALL 13 native Jetpack Compose screens (`UE01`..`UE13`) via Roborazzi (`GraphicsMode.NATIVE`, `412×915dp` Pixel portrait + `800×500dp` `UE13` Live Updates spec sheet + Light Mode spot checks for `UE01` & `UE07`).
   - Enforces Material `>= 48dp` touch target bounds and `0px` horizontal overflow.
   - Generates 13 side-by-side comparison sheets (`ANDROID_CMP_UE01.png` .. `ANDROID_CMP_UE13.png`, **LEFT: iOS Reference UE** vs **RIGHT: Android Native Material 3 Compose**) + master gallery (`ANDROID_13_SCREENS_OVERVIEW.png`) for direct visual QA inspection.

---

## 2. Executable Test Case Matrix (`ATC-01` .. `ATC-18`)

| Test ID | Target Screen / Domain | Test Action | Expected Assertion |
| :--- | :--- | :--- | :--- |
| **`ATC-01`** | `UE01_AGENTS_HOME` | Render Agents Home; assert Host pill (`MacBook Pro`), Pinned section, `ledger-svc` & `web-console` groups; tap `Needs you` filter chip | Filters list to `Fix flaky TestSettlementBatch`, preserves bottom `NavigationBar` & Compose `FAB` with `>=48dp` targets |
| **`ATC-02`** | `UE02_DISPLAY_OPTIONS` | Open Display Options sheet; change sort field, toggle `Auto Pin` & `Archived Only`, tap `Mark All as Read`, then `Reset` | Unread count drops `3 -> 0`; `Reset` restores defaults |
| **`ATC-03`** | `UE03_CONTEXT_MENU_PIN` | Open Context Preview Sheet for `Fix flaky TestSettlementBatch`; assert preview card (`Implementation Plan`, `Awaiting review`) and tap `Pin` | Toggles pinned state on `cas-flaky-settlement` and renders all 6 actions + swipe shortcut strip |
| **`ATC-04`** | `UE04_PROJECT_DETAIL` | Navigate to `ledger-svc`; switch `Active` / `Archived` / `Automations` tabs; tap `New Conversation in Project` | Displays `~/code/ledger-svc`, metadata pills, project tools, and routes to Cascade Chat |
| **`ATC-05`** | `UE05_CREATE_PROJECT` | Open `New Project` full-screen dialog; toggle `Cloud` + `GitHub repository`, pick `acme/ledger-svc`, enter name, tap `Create Project` | Adds new project `ledger-svc-cloud` to `WorkspaceAndAutomationStore` |
| **`ATC-06`** | `UE06_AUTOMATIONS` | Switch to `Automations`; enter NL prompt + tap `Create`; tap `Run` on `Nightly dependency audit`; tap `Resume` on `Bundle size watch` | Appends scheduled automation, triggers run state, moves paused automation to active |
| **`ATC-07`** | `UE07_CHAT_AND_COMPOSER` | Render `Add rate limiter to /transfers`; assert `+128 -14` badge, tap `Thought for 14s`, inspect `Implementation Plan` & `Task · 4 of 7 done` 7-segment bar | Expands thinking trace; renders 4 blue + 1 amber + 2 neutral segments accurately |
| **`ATC-08`** | `UE07_CHAT_AND_COMPOSER` | Tap `Allow` (Biometric) on `vegeta attack` command card; also enter draft text & tap `Send` | Resolves waiting interaction (`status -> DONE`) and appends user message while clearing `@ratelimit.go` chip |
| **`ATC-09`** | `UE08_ADD_CONTEXT` | Open `Add Context`; filter by category, toggle `ratelimit.go` + `go-testing`, tap `Add to message` | Injects selected chips into `ChatComposer` |
| **`ATC-10`** | `UE09_MODEL_AND_MODE` | Open `Model & Mode`; toggle `Fast` vs `Planning`, pick `Extra (xhigh)` effort, pick `Orchestrator` (verifying effort lock), pick `Claude Opus 5.5` + `go-reviewer`, tap `Done` | Updates Composer mode/model/agent pills and locks effort when Orchestrator is active |
| **`ATC-11`** | `UE10_STRUCTURED_QUESTION` | On `Audit log for admin actions`, toggle multi-select checkboxes, enter `Something else...`, tap `Next` -> `3 Retention` -> `Submit` | Advances stepper to Step 3 and submits `AskQuestionAnswer` |
| **`ATC-12`** | `UE11_PLAN_REVIEW` | Open `Implementation Plan` (`v2`); inspect paused amber banner, existing pending comments, add inline comment, tap `Send comments` / `Proceed` | Increments comment badge count and dispatches plan review comments |
| **`ATC-13`** | `UE12_TURN_DIFF_REVIEW` | Open `Review changes` (`Turn 3`, `middleware/ratelimit.go`); tap line `29`, enter comment, tap `Send to agent`, toggle `Viewed`, tap `Stage` & `Accept file` | Attaches line-29 comment, updates reviewed/staged flags, opens Git Commit sheet |
| **`ATC-14`** | `UE13_LIVE_ACTIVITY_SPEC` | Render Android Live Updates Spec & test `AndroidLiveUpdateBuilder` for Running (`4/7`), Waiting (`Approve`), Done (`+128 -14`), and Multi-Agent states | Verifies all 7 Android Live Update visual cards + `ProgressStyle` metadata + dismiss/cancel rules |
| **`ATC-15`** | **KMP Binary Protobuf & >600-Step Ceiling** | Request 605-step trajectory via `AntigravityKmpRpcClient` against `mock_language_server.py` | Decodes all 605 steps over `application/proto` bypassing JSON ceiling |
| **`ATC-16`** | **3-Version Compat Matrix & Guardrails** | Run KMP RPC client against Legacy (`v2.31`), Current (`v2.33`), and Future (`v2.99`) mock behaviors + `verify_compat_guardrails.py` | Negative caching, unknown field auto-strip, enum downgrade, and unknown enum fallback all pass with zero crashes |
| **`ATC-17`** | **v2.33 Extended Flows** | Interact with `ConversationOverviewSheet`, `/btw` `SideQuestionSheet` (insert into main), `/swarm` `SwarmBoardSheet`, `VoiceModeSheet` (end -> Call Summary), and `CustomizationsSettings` | All v2.33 sheets open, update domain store state cleanly, and persist call summary |
| **`ATC-18`** | **Forward-Compatible Unknown Step & Gate** | Inject an unrecognized future `CortexStepType.UNSPECIFIED` (with `rawTypeName`/`fallbackSummary`) and an unrecognized `WAITING` interaction gate | Renders `UnknownForwardStepCard` and `GenericFallbackInteractionCard` with working `Allow Once` / `Deny` actions |
