# Platform Support & Feature Status (`AG Pocket` / `PocketAntigravity`)

> **Last updated**: Post-PR `#45` + Apple Watch (`watchOS 11+`) Companion implementation (`feat/apple-watch-companion`).
>
> This document summarizes **which platforms are supported**, **what capabilities are implemented on each platform**, **what is automatically verified in CI**, and **what remains on the roadmap**.

### Status Legend

| Badge | Meaning |
| :---: | :--- |
| ✅ | **Implemented & CI-Verified** — Built, wired end-to-end, and validated by automated unit/E2E/visual tests in GitHub Actions. |
| 🚧 | **Implemented / Simulator CI or Hardware QA Next** — Core UI, state, protocol sync, and local ESDD verification are implemented; final macOS Simulator CI / physical-device hardware QA or OS hook is the next step. |
| 🧭 | **Planned** — Not yet started; tracked on the roadmap. |

---

## 1. Supported Platforms & Targets at a Glance

| Target | Min / Target OS | Tech Stack | Status | Key Highlights |
| :--- | :--- | :--- | :---: | :--- |
| **iOS App** (`apps/ios/`) | **iOS 18.0+** (Xcode 16+ / Swift 6) | SwiftUI + UIKit + SKIE (`AntigravityShared.xcframework`) + Pure-Swift `AntigravityData` | ✅ | All 13 UE screens (`UE01`–`UE13`), Floating Liquid Glass shell, Dynamic Island & Lock Screen Live Activities, Share Extension (<30 MB), Face ID approval gate, live Camera QR scanner, WebView Google Cloud Relay sign-in, native `SFSpeechRecognizer` voice input, Frame-0 instant launch, and `WatchConnectivityBridge` + Handoff. |
| **Apple Watch App** (`apps/ios/Watch/`) | **watchOS 11.0+** (Xcode 16+ / Swift 6) | Native SwiftUI + `WatchConnectivity` + `WKNotificationScene` + `LocalAuthentication` (Wrist Detection) + Handoff + `AntigravityData` | 🚧 | Focused on **3 wrist jobs: glance status, approve, and dispatch voice tasks**. All 8 OLED screens (`W01`–`W08`): `Agents` home (top-left device switcher, top-right voice new task), `Devices` switcher, `Chat Stream`, `Artifact Summary` (title + `≤ 3` key points + single Double-Tap CTA `See changes` / `Proceed`), `Changed Files` (no source code; `≤ 5` files & zero risk items → `Accept all`, otherwise `WORTH A LOOK` + intent-grouped `GROUPED` clusters → `iPhone` Handoff), `Voice Input`, and interactive Long-Look `Approval Notification`. Enforces watchOS `LAPolicy.deviceOwnerAuthenticationWithWristDetection` on all approvals (`Allow`/`Proceed`/`Accept all`). 14/14 Watch ESDD E2E & unit/XCUITest specs complete; macOS Watch Simulator CI & physical watch field QA next. |
| **Android App** (`apps/android/`) | **Android 10–16** (`minSdk 29`, `compileSdk 36`, `targetSdk 36`) | Kotlin 2.1.21 + Jetpack Compose (`BOM 2025.10.00`) + Material 3 (`1.4.0`) + Adaptive `NavigationSuiteScaffold` | ✅ | 3-module architecture (`core-ui`, `core-platform`, `app`) consuming KMP `shared/` directly. All 13 UE screens (`UE01`–`UE13`) adapted idiomatically to Material 3, Android 16 `NotificationCompat.ProgressStyle` Live Updates + Android 10–15 Foreground Service fallback, Jetpack Glance home widget, `BiometricPrompt`, Tink + Keystore encryption, Material You Dynamic Color opt-in, native Share receiver. |
| **KMP Shared Core** (`shared/`) | JVM 21 · Android API 29+ · iOS 18+ (`arm64` / Simulator) | Kotlin Multiplatform (`core-model`, `core-protocol`, `core-markdown`, `core-domain`, `umbrella`) + Ktor + SKIE | ✅ | Single shared source of truth for Connect-RPC (5-byte streaming), Binary-first Protobuf + adaptive JSON fallback, Cloud Relay (`SAPISIDHASH`), 7 `StateFlow` domain stores, `DurableOutbox`, `HostCapabilityRegistry`, `ProtocolCompatibilityEngine`, streaming Markdown AST, and deterministic ESDD fixtures. |
| **Antigravity Host Targets** | Desktop PC · Antigravity Cloud (`v1/...`) · Optional LAN Companion Bridge | Official Cloud Relay (`ApiService/ProxyCommand` & `StreamProxyCommand`) · Direct LAN / Tailscale TLS | ✅ | Bidirectional compatibility across older & newer Desktop versions (`v2.20` .. `v2.33+` and future versions) via per-host capability negotiation, negative caching, resilient enums, and automatic unknown-field stripping/downgrading. |

---

## 2. Detailed Feature Matrix (iOS vs Android vs KMP Shared Core)

### 2.1 Core Screens & Navigation (`UE01`–`UE13`)

Every screen follows the normative ESDD specs ([`specs/`](../specs/) and [`specs/android/`](../specs/android/)) while using platform-idiomatic navigation and visual design (iOS HIG / Floating Liquid Glass on iOS; Material Design 3 Tonal Elevation / `NavigationSuiteScaffold` on Android).

| Screen ID | Capability | iOS (`apps/ios/`) | Android (`apps/android/`) | Shared KMP State (`shared/`) |
| :--- | :--- | :---: | :---: | :--- |
| **`UE01` / `UE01B`** | **New Conversation Home & PC-Aligned Sidebar Drawer** — Welcome greeting, amber Needs Approval jump banner, Host switcher, Search, Left Sidebar Drawer (`+ New Conversation`, `Automations`, `Customizations`, `Pinned`, `Projects`, `Settings`) | ✅ `AgentsHomeViewController` + `AgentsSidebarDrawerView` | ✅ `AgentsHomeScreen` + `ModalNavigationDrawer` | ✅ `ConversationSyncStore` |
| **`UE02`** | **Display Options** — Group by `Project` / `Host` / `None`, Sort Conversations (`Last Updated` / `Date Created` / `Title`), Sort Projects, Filter, Density, Auto Pin, Archived Only, Mark All as Read | ✅ `DisplayOptionsSheetView` | ✅ `DisplayOptionsSheet` | ✅ `ConversationSyncStore` |
| **`UE03`** | **Conversation Context Menu** — Rich preview (`Gemini 4 Neon`), Pin, Mark Unread, Rename, Move to Project, Export Summary, Archive, Delete (+ iOS Swipe Pin/Archive) | ✅ `ConversationContextPreviewMenu` | ✅ `ConversationContextSheet` | ✅ `ConversationSyncStore` |
| **`UE04`** | **Project Detail** — Repo header, `main ↑2`, `Working tree clean`, Active/Archived/Automations tabs, single-line conversation rows, wired `Project rules & skills` & Automation Detail | ✅ `ProjectDetailViewController` | ✅ `ProjectDetailScreen` | ✅ `WorkspaceAndAutomationStore` |
| **`UE05`** | **Create Project** — MacBook Pro vs Cloud runtime, GitHub repo vs Drive folder, branch/worktree configuration | ✅ `CreateProjectSheetView` | ✅ `CreateProjectDialog` | ✅ `WorkspaceAndAutomationStore` |
| **`UE06` / `UE06B` / `UE06C`** | **Automations Hub, Detail & Edit** — NL quick-create, filter chips, Scheduled / Always On / Paused, Run Now, Recent Runs history + Retry, full Edit Schedule & Prompt form | ✅ `AutomationsViewController` + `AutomationDetailView` + `AutomationEditSheetView` | ✅ `AutomationsScreen` + `AutomationDetailScreen` + `AutomationEditDialog` | ✅ `WorkspaceAndAutomationStore` |
| **`UE07` / `UE07B`** | **Cascade Chat, Composer & Permissions Preset** — Streaming Markdown AST, thought/tool/terminal cards, 7-segment task card, inline amber Face ID/Biometric approval, PC-aligned Composer (`+`, `Gemini 4 Neon / Extra High`, anchored `🛡 Default` Permissions Preset popover) | ✅ `CascadeChatViewController` + `ChatComposerView` + `PermissionsSheetView` | ✅ `CascadeChatScreen` + `PermissionsPresetOverlay` | ✅ `CascadeChatDomainStore` + `core-markdown` |
| **`UE08` / `UE08B`** | **Add Context (`+`) & `/` Actions / Skills** — Anchored Add Context menu (`Files`, `Folder`, `Mentions`, `Actions`, `Drive [Set up]`) + categorized `/` Actions (`/plan`, `/goal`, `/schedule`, `/automation`) & Skills (`/go-testing`, `/api-review`) | ✅ `AddContextSheetView` + `ChatComposerView` | ✅ `AddContextSheet` + `SlashCommandOverlay` | ✅ `CascadeChatDomainStore` |
| **`UE09`** | **Model, Orchestrator, Thinking Effort & Usage Quota** — Live Gemini 4 catalog (`Orchestrator`, `Gemini 4 Neon` default, `Carbon`, `Argon`, `Hydrogen`, `Claude Opus 5.5`, `Gemini 3.8 Flash`, `More models`), 4 thinking levels (`Low`/`Medium`/`High`/`Extra High`), 5h/Weekly quota bars (Planning handled via `/plan`) | ✅ `ModelAndModeSheetView` | ✅ `ModelAndModeSheet` | ✅ `CascadeChatDomainStore` + `SettingsAndCustomizationStore` |
| **`UE10`** | **Structured `/plan` Interview Question Wizard** — Multi-step clarification Q&A (`ASK_QUESTION`) with multi-select checkboxes, write-in & freeform reply | ✅ `StructuredQuestionCardView` | ✅ `StructuredQuestionScreen` | ✅ `CascadeChatDomainStore` |
| **`UE11`** | **Implementation Plan Review** — Paused amber banner, `MODIFY`/`NEW` badges, paragraph-level inline comments, `Proceed` / `Send comments` | ✅ `ImplementationPlanReviewViewController` | ✅ `ImplementationPlanReviewScreen` | ✅ `ReviewAndVcsStore` |
| **`UE12`** | **Turn Diff Review** — Turn switcher, file pager, single-column line-number gutter (`v2.34`), word-level diff, inline line-29 comment composer, Git staging & commit | ✅ `TurnDiffReviewViewController` | ✅ `TurnDiffReviewScreen` | ✅ `ReviewAndVcsStore` |
| **`UE13`** | **Live Agent Progress Surface** — Real-time progress & biometric approval outside the app | ✅ Dynamic Island & Lock Screen Live Activity (`ActivityKit`) | ✅ Android 16 `NotificationCompat.ProgressStyle` Live Updates + FGS Fallback + Dark Notification Shade Spec | ✅ `LiveProgressModels` + `AntigravityCoreCoordinator` |

---

### 2.2 Antigravity `v2.33–v2.34` Agent Workflows, Customizations & Settings

| Feature | iOS | Android | KMP Shared Core | Notes |
| :--- | :---: | :---: | :---: | :--- |
| **Conversation Overview Sheet** (Goals, Subagents + Stop, Background Tasks + Cancel, Changed Files, Linked PRs) | ✅ | ✅ | ✅ | Powered by `OrchestrationAndSideChannelStore` & `ReviewAndVcsStore` |
| **`/btw` Side Question Channel** (ask parallel clarification without interrupting running trajectory) | ✅ | ✅ | ✅ | `SideQuestionSheetView` (iOS) · `SideQuestionSheet` (Android) (gated behind feature flag in live `/` menu) |
| **`/swarm` Multi-Agent Board** (agent roster, channel feed, status updates) | ✅ | ✅ | ✅ | `SwarmBoardSheetView` (iOS) · `SwarmBoardSheet` (Android) |
| **Gemini Live Voice Mode & Call Summary** | ✅ | 🚧 | ✅ | iOS wires live `SFSpeechRecognizer`/`AVAudioEngine`; Android ships `VoiceModeSheet` + persisted `VoiceCallTranscriptSummary` |
| **Rich Artifact Viewer** (Markdown, code blocks, images, Jupyter `.ipynb`, image region comments, unknown artifact fallback) | ✅ | ✅ | ✅ | `RichArtifactViewerSheet` on both iOS and Android (`ArtifactKind.UNKNOWN` safe fallback) |
| **Mermaid Diagrams & `<agent-embed>` Cards** | ✅ | ✅ | ✅ | Native rendering on iOS (`MarkdownEmbedAndMermaidViews`); Compose AST & structured card rendering on Android (`AntigravityComponents`) |
| **Slash Commands & Live Model Catalog** | ✅ | ✅ | ✅ | Fetched via KMP `AntigravityKmpRpcClientV233` with graceful fallback on older Desktop versions |
| **Project Rules & Skills (`UE14`)** (Read-only Skills/Rules/Plugins/Agents viewer, loaded token budget, live plugin enable/disable switches) | ✅ | ✅ | ✅ | `CustomizationsSettingsView` (iOS) · `ProjectRulesAndSkillsScreen` (Android); reachable from both Sidebar `Customizations` & Project Detail `Project rules & skills` |
| **Flattened Mobile Settings (`UE15`)** (Remote Control status/QR, Host switcher, Appearance/Theme/Dynamic Color, Language `English`/`简体中文`, Global Permissions Preset, Notifications, About) | ✅ | ✅ | ✅ | `RemotePairingViewController` (iOS) · `SettingsAndCustomizationsScreen` (Android) |

---

### 2.3 Pairing, Networking & Bidirectional Protocol Engine

| Capability | iOS | Android | KMP Shared Core | Details |
| :--- | :---: | :---: | :---: | :--- |
| **Official Cloud Relay Transport (`SAPISIDHASH` + Dynamic API Key Discovery & Rotation)** | ✅ | ✅ | ✅ | Zero hardcoded API keys; cookie-isolated `ApiService/ListInstances`, `ProxyCommand`, and `StreamProxyCommand` in `AntigravityKmpRpcClient` |
| **Interactive Google Cloud Relay Sign-In Sheet** | ✅ | ✅ | ✅ | iOS ships live `CloudRelaySignInSheet` (`WKWebView` + XHR API-key capture); Android ships `CloudRelaySignInScreen` (sanitized-UA `WebView` + `@JavascriptInterface` XHR/fetch API-key capture + `CloudRelayCookieBridge` + 3.5s fallback capture) |
| **Remote Control QR Code Pairing** | ✅ | 🚧 | ✅ | iOS ships live camera `RemoteControlQRScannerSheet`; Android ships `RemoteControlLinkDialog` + system-camera `https://antigravity.google.com/r/` & `agpocket://` deep links with in-app CameraX / ML Kit viewfinder next |
| **Direct LAN / Tailscale Pairing + SHA-256 TLS Pinning / TOFU** | ✅ | ✅ | ✅ | Full support via `connectDirectLan` + Ktor Darwin/OkHttp pinners (`CookieJar.NO_COOKIES`, 25s hard handshake timeout, `cancelPendingConnectionAttempt`) + strict HTTPS (`usesCleartextTraffic="false"`, loopback-only cleartext) |
| **5-Byte Connect-RPC Streaming Envelope** | ✅ | ✅ | ✅ | `[1B flags (raw/gzip/end-trailer) \| 4B BE length \| payload]` for summaries, reactive cascade updates & project streams |
| **Binary-First Protobuf + Adaptive JSON Fallback + Runtime Ceiling Learning** | ✅ | ✅ | ✅ | ~65% bandwidth savings over `application/proto`; zero hardcoded 600-step limits; targeted JSON probe for unknown future fields |
| **Bidirectional Host Capability Registry & Forward Compatibility** | ✅ | ✅ | ✅ | 16 registered `HostCapability` entries, per-host negative caching (`404`/`501`/`UNIMPLEMENTED`), resilient fallback on all 35 enums, unknown future `CortexStep` / `RequestedInteraction` fallback UI cards |
| **Durable Outbox & Per-Host Offline Projection Cache** | ✅ | ✅ | ✅ | Optimistic message queuing with automatic replay on reconnect; offline browsing of cached conversations |

---

### 2.4 Native OS Integrations & Platform Ergonomics

| Capability | iOS (`apps/ios/`) | Android (`apps/android/`) |
| :--- | :--- | :--- |
| **Biometric Approval Gate** | ✅ Face ID / Touch ID (`LocalAuthentication`) | ✅ `BiometricPrompt` + lock-screen `BiometricApprovalTrampolineActivity` |
| **Live Background Progress** | ✅ Dynamic Island + Lock Screen Live Activity (`ActivityKit` / `WidgetKit`) | ✅ Android 16 Promoted Live Updates (`NotificationCompat.ProgressStyle` + status-bar chip) + Android 10–15 `AgentProgressForegroundService` fallback |
| **Home Screen Widget** | ✅ `AntigravityLiveActivityWidget` (`WidgetKit`, <30 MB pure-Swift extension) | ✅ `AntigravityAgentsGlanceWidget` (`Jetpack Glance` multi-agent widget) |
| **System Share Sheet Receiver** | ✅ `AGPocketShare` Extension (text, URLs, images, files) | ✅ Native `ACTION_SEND` & `ACTION_SEND_MULTIPLE` intent filters in `MainActivity` (no 30 MB extension cap) |
| **Encrypted Secret Storage** | ✅ iOS Keychain | ✅ Android Keystore + Tink AEAD + DataStore (`AndroidSecretStore`) |
| **Appearance & Themes** | ✅ System / Dark / Light · Obsidian, Nord, Everforest presets | ✅ System / Dark / Light · Obsidian, Nord, Everforest presets + **Android 12+ Material You Dynamic Color** opt-in (semantic status colors locked) |
| **Startup Performance** | ✅ Frame-0 Conversations launch (`UILaunchScreen` + zero blocking Keychain I/O on main thread) | ✅ Edge-to-edge Compose launch with instant local projection, background `restoreSavedSession()`, & deep-link routing |

---

## 3. Visual QA Overview (iOS Reference UE vs Android Compose Material 3)

All 13 Android Jetpack Compose screens (`UE01`–`UE13`, plus Light Mode checks on `UE01` & `UE07`) are automatically rendered via **Robolectric `GraphicsMode.NATIVE` + Roborazzi** (`412×915dp` Pixel portrait + `800×500dp` Live Updates spec) and paired 1:1 against the canonical iOS UE screenshots by [`verification/android_visual_compare.py`](../verification/android_visual_compare.py):

![Android 13-Screen Visual QA Overview](../verification/output/android/ANDROID_13_SCREENS_OVERVIEW.png)

Individual side-by-side comparison sheets are committed under [`verification/output/android/comparisons/`](../verification/output/android/comparisons/) (`ANDROID_CMP_UE01.png` .. `ANDROID_CMP_UE13.png`).

---

## 4. Automated Verification & CI Coverage

All workflows use impact-scoped routing via [`verification/e2e_impact_planner.py`](../verification/e2e_impact_planner.py) on normal PRs (skipping unaffected platform runners) and automatically enforce **100% full verification** on releases:

| Workflow | Runner | What It Verifies |
| :--- | :--- | :--- |
| [`.github/workflows/macos-xcode-verify.yml`](../.github/workflows/macos-xcode-verify.yml) | `ubuntu-latest` + `macos-26` | Spec-DAG (iOS + Watch Stage W1) & 8-check compat guardrails, Swift 6 `AntigravityData` XCTest (incl. `WatchCompanionTests`), Live Connect-RPC + v2.33 + 3-version Compat Matrix, SKIE `AntigravityShared.xcframework`, real iOS Simulator XCUITest (6 flows), Live App RPC handshake & 13 native iOS Simulator screenshots, plus real Apple Watch Series 10 Simulator build / `AGPocketWatchUITests` / 8-screen capture via `watchos-simulator-runner.py` when Watch files change. |
| [`.github/workflows/android-verify.yml`](../.github/workflows/android-verify.yml) | `ubuntu-latest` (with `/dev/kvm`) | Android Gradle `assembleDebug` + `lintDebug` (0 errors), JVM unit tests + 18 Compose interactive E2E tests (`ATC-01`..`ATC-18`), Roborazzi 13-screen + Light Mode capture & 48dp/0px-overflow audit, iOS↔Android visual comparison generation, and **KVM hardware-accelerated API 35 Pixel 6 Emulator** instrumented E2E (`connectedDebugAndroidTest`). |
| [`.github/workflows/kmp-verify.yml`](../.github/workflows/kmp-verify.yml) | `ubuntu-latest` + `macos-26` | KMP JVM common tests + live mock LanguageServer E2E (Linux), plus KMP iOS Simulator tests & `AntigravityShared.xcframework` build (macOS). |
| [`.github/workflows/cr-agent.yml`](../.github/workflows/cr-agent.yml) & [`zizmor.yml`](../.github/workflows/zizmor.yml) | `ubuntu-latest` | Semgrep OSS security rules, deterministic security gate, Gemini CLI client/security review, advisory runtime hygiene (`verify_advisory_hygiene.py`), and GitHub Actions supply-chain hardening. |

For exact file locations of every iOS, Android (Gradle `src/test` & `src/androidTest`), and KMP test suite, see [`tests/README.md`](../tests/README.md).

---

## 5. Known Gaps & Next Roadmap

1. **Apple Watch Companion (`AGPocketWatch`, `watchOS 11+`) — Final CI & Physical Hardware QA** *(Specs `specs/watch/`, all 8 SwiftUI views `W01`–`W08`, `WatchWristUnlockGuard`, `WatchConnectivityBridge`, `WatchCompanionTests`, `AGPocketWatchUITests`, and 14/14 headless `416×496 @2x` ESDD E2E already implemented)*:
   - **macOS Watch Simulator CI**: Complete real Xcode 26 `watchsimulator` + `watchOS` arm64 build, `AGPocketWatchUITests`, and native Series 10 Simulator 8-screen visual verification once merged via GitHub Actions `macos-26`.
   - **Physical Apple Watch Field Testing**: Validate `WatchConnectivity` latency over Bluetooth/Wi-Fi, Double Tap primary action feel, `LAPolicy.deviceOwnerAuthenticationWithWristDetection` off-wrist locking, Long-Look notifications, and Handoff to iPhone on paired hardware.
2. **Android On-Device Hardware Hooks** (UI, WebView Cloud Relay Sign-In & KMP transport already in place):
   - **CameraX / ML Kit QR Scanner**: In-app live camera viewfinder for scanning Antigravity Desktop Remote Control QR codes directly inside Android (system camera deep links + manual link dialog already work).
   - **Android Live Voice Capture**: Wire `android.speech.SpeechRecognizer` / `AudioRecord` into `VoiceModeSheet` for hands-free live dictation and Gemini Live turns.
3. **Real Physical Device Field Testing**:
   - End-to-end validation of Android 16 promoted Live Updates chips on physical Pixel hardware, foldables/tablets, and background Wi-Fi ↔ 5G network handoffs across both iPhone and Android devices.
4. **Release Packaging & Distribution**:
   - Automated signed release pipelines for iOS + Apple Watch (TestFlight / `.ipa`) and Android (signed `.apk` / `.aab` / Play Store).
5. **Localization (i18n) & Ongoing Upstream Sync**:
   - Multi-language UI strings (English / Chinese / Japanese, etc.) and continuous tracking of new upstream Google Antigravity Desktop `LanguageServerService` step types, artifact formats, and interaction gates.
