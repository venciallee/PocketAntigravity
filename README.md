<div align="center">

# AG Pocket (`PocketAntigravity`)

**Native iOS, Apple Watch & Android Client for Google Antigravity Remote Control**

[![Platforms](https://img.shields.io/badge/Platforms-iOS%2018%2B%20%7C%20watchOS%2011%2B%20%7C%20Android%2010%E2%80%9316-5B8DEF?style=flat-square)](#2-current-status--supported-platforms)
[![Shared Core](https://img.shields.io/badge/Shared%20Core-KMP%20%2B%20Swift%206%20%2B%20Compose-7C6EE6?style=flat-square)](#5-overall-architecture)
[![Protocol](https://img.shields.io/badge/Protocol-Connect--RPC%20%2B%20Cloud%20Relay-2E9679?style=flat-square)](#4-core-principle--how-it-interacts-with-antigravity)
[![Status](https://img.shields.io/badge/Status-iOS%20%26%20Android%20Ready%20%7C%20Apple%20Watch%20Preview-3FB950?style=flat-square)](docs/PLATFORM_STATUS.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-EBB365?style=flat-square)](LICENSE)

</div>

---

## 1. What Is This Project?

**AG Pocket (`PocketAntigravity`)** is an open-source **native iOS, Apple Watch, and Android client** for **Google Antigravity**, enabling **one-tap pairing and real-time remote control** of your Antigravity PC / Desktop and Cloud agent sessions straight from your phone or wrist. Built with 100% native UI (Swift 6 SwiftUI/UIKit on iOS & watchOS and Kotlin Jetpack Compose Material 3 on Android) backed by a shared Kotlin Multiplatform (KMP) protocol & domain core, it speaks directly to Antigravity's `LanguageServerService` with zero web-bundle overhead.

---

## 2. Current Status & Supported Platforms

Both **native iOS** and **native Android** clients are implemented and verified continuously in GitHub Actions on top of the shared **KMP core**, and the **native Apple Watch companion (`watchOS 11+`)** is now implemented across all 8 screens (`W01`–`W08`) and advancing through final Watch Simulator CI & physical-device QA.

| Platform / Layer | Support Range | Status | Highlights |
| :--- | :--- | :---: | :--- |
| **iOS** ([`apps/ios/`](apps/ios/)) | **iOS 18.0+** (Swift 6 · Xcode 16+) | **Implemented & CI-Verified** | All 13 UE screens (`UE01`–`UE13`) + v2.33 sheets, Floating Liquid Glass shell, Dynamic Island & Lock Screen Live Activities, Face ID gate, Share Extension (<30 MB), live Camera QR scanner, WebView Google Cloud Relay sign-in, native `SFSpeechRecognizer` voice input, Frame-0 launch, and `WatchConnectivity` / Handoff companion bridge. |
| **Apple Watch** ([`apps/ios/Watch/`](apps/ios/Watch/)) | **watchOS 11.0+** (Swift 6 · SwiftUI · Series 10 46mm baseline) | **Implemented · Simulator CI & Device QA Next** | Purpose-built for **3 wrist jobs: glance status, approve, and dispatch voice tasks**. All 8 OLED screens (`W01`–`W08`): `Agents` home (top-left device switcher, top-right voice new task), `Devices` (PC/Cloud), `Chat Stream`, `Artifact Summary` (title + `≤ 3` key points + single Double-Tap CTA `See changes` / `Proceed`), `Changed Files` (zero source code; `≤ 5` files with zero risk items → `Accept all`, otherwise `WORTH A LOOK` + intent-grouped `GROUPED` clusters → `iPhone` Handoff), `Voice Input`, and interactive Long-Look `Approval Notification`. Supports watchOS 11 **Double Tap** primary actions and enforces **unlocked + on-wrist verification** (`LAPolicy.deviceOwnerAuthenticationWithWristDetection`) on every approval (`Allow` / `Proceed` / `Accept all`). Specs (`specs/watch/`), Swift 6 views, unit/XCUITests & 14/14 headless `416×496 @2x` ESDD E2E complete; macOS Watch Simulator CI & physical Apple Watch QA next. |
| **Android** ([`apps/android/`](apps/android/README.md)) | **Android 10–16** (`minSdk 29` / `targetSdk 36`, Jetpack Compose + Material 3) | **Implemented & CI-Verified** | All 13 UE screens (`UE01`–`UE13`) adapted idiomatically to Material 3 + v2.33 sheets, Android 16 `NotificationCompat.ProgressStyle` Live Updates + Android 10–15 Foreground Service fallback, Jetpack Glance widget, `BiometricPrompt`, Tink + Keystore encryption, Material You Dynamic Color opt-in, native Share receiver, verified via Roborazzi 13-screen visual QA & KVM API 35 Emulator E2E. *(On-device CameraX QR viewfinder & live `SpeechRecognizer` mic capture are next.)* |
| **KMP Shared Core** ([`shared/`](shared/)) | JVM · Android · iOS (`AntigravityShared.xcframework`) | **Full Parity & CI-Verified** | 5 shared modules (`core-model`, `core-protocol`, `core-markdown`, `core-domain`, `umbrella`) providing Connect-RPC 5-byte streaming, Binary-first Protobuf + adaptive JSON fallback, `SAPISIDHASH` Cloud Relay, 7 `StateFlow` domain stores, `DurableOutbox`, `HostCapabilityRegistry`, `ProtocolCompatibilityEngine`, and forward-compatible resilient enums. |
| **Antigravity Hosts** | Desktop PC · Antigravity Cloud (`v1/...`) · LAN / Tailscale | **Bidirectional Compat** | Connects over Official Cloud Relay or Direct LAN/Tailscale TLS, automatically negotiating host capabilities across older and newer Desktop versions (`v2.20`–`v2.33+` and future step/interaction/artifact types). |

> **Full Screen-by-Screen & Feature Breakdown**: See **[`docs/PLATFORM_STATUS.md`](docs/PLATFORM_STATUS.md)** (and **[`specs/watch/`](specs/watch/)** for Apple Watch PRD, architecture & 14-case E2E plan) for the complete platform matrix, visual QA status, and roadmap.

---

## 3. Why I Built This

With the recent leap in **Gemini**'s reasoning and coding capabilities, Antigravity quickly became my daily driver for software engineering. I love using its **Remote Control** workflow to launch tasks, monitor progress, review implementation plans, and approve terminal commands while away from my desk — yet I was surprised to discover that Antigravity had **no official native mobile app** for iOS or Android. Relying on a desktop web wrapper on a phone felt sluggish and disconnected from real mobile ergonomics (Face ID / `BiometricPrompt` approvals, Dynamic Island & Android 16 Live Updates, offline resilience, and fluid native gestures), so I built this native app from the ground up.

---

## 4. Core Principle — How It Interacts with Antigravity

Rather than embedding a mobile browser or wrapping the ~9 MB desktop React bundle, the client speaks Antigravity's native **Connect-RPC wire protocol** (`exa.language_server_pb.LanguageServerService`) directly over the **Official Cloud Relay** — working seamlessly across Wi-Fi and 5G with zero desktop scripts or network configuration:

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/core-principle-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/core-principle-light.svg">
    <img alt="Core Principle: How Native iOS and Android Clients Interact with Antigravity PC" src="docs/images/core-principle-light.svg" width="100%">
  </picture>
</p>

### One-Tap Pairing & Cloud Relay Tunnel

1. **Scan the Desktop Remote Control QR**: Open **Remote Control** in Antigravity Desktop (`https://antigravity.google.com/r/<instance-id>`) and scan the QR code (or paste the link) on your phone.
2. **One-Time Sign-In & Live Host Discovery**: Sign in once with your Google account — credentials stay strictly inside **iOS Keychain / Android Keystore**. The client dynamically discovers the Relay Web API key (zero hardcoded keys in source), signs requests with `SAPISIDHASH`, and calls `devtools_jetski_boq_api_proto.ApiService/ListInstances` (auto-probing multi-account `X-Goog-AuthUser` + live reachability) to resolve your online PC host UUID.
3. **Direct Connect-RPC Tunneling**: All unary and streaming `LanguageServerService` RPCs tunnel transparently through `ApiService/ProxyCommand` and `ApiService/StreamProxyCommand`, completely bypassing the ~9 MB desktop web bundle.

### Wire Protocol & Interaction Lifecycle

1. **5-Byte Connect Streaming Envelope**: Real-time push streams (`JetboxSubscribeToSummaries`, `StreamCascadeReactiveUpdates`, `ProjectUpdatesStream`) frame every chunk with a 5-byte prefix (`[1B flags (0x00 raw / 0x01 gzip / 0x02 end-trailer) | 4B big-endian length | payload]`).
2. **Binary-First Adaptive Trajectory Sync (Zero Hardcoded Limits)**:
   - **Binary Protobuf Default (~65% Bandwidth Savings)**: Local PC sessions default directly to compact raw Binary Protobuf (`Content-Type: application/proto`) via `ProtobufStepDecoder` / `ProtobufStepCodec`, saving ~65% bandwidth and avoiding upstream JSON step truncation altogether.
   - **Targeted JSON Unknown-Field Probe**: Whenever a binary trajectory encounters an unrecognized future wire interaction (`field 56`) or unknown `CortexStepType`, the client issues a targeted JSON `stepOffset` probe only for those steps to recover exact JSON field names and metadata without pulling the entire trajectory over JSON.
   - **Adaptive JSON Fallback & Runtime Ceiling Discovery**: On Antigravity Cloud (`v1/...`) sessions or hosts that reject `application/proto` (HTTP `415`), the client seamlessly falls back to adaptive JSON and dynamically discovers and learns each host's true truncation ceiling at runtime (`truncatedAt`, HTTP `413` / `resource_exhausted`, or pagination stalls) — with zero hardcoded `600`-step thresholds, automatically resetting whenever the host updates its version.
3. **Biometric Approval Gate & Durable Outbox**: Whenever a remote PC agent pauses in `CORTEX_STEP_STATUS_WAITING (9)` (shell command execution, file permission, plan review, or multi-step structured question), the app surfaces an inline amber approval card and Dynamic Island / notification action gated by **Face ID / BiometricPrompt**, then dispatches the exact matching oneof via `HandleCascadeUserInteraction`. Outgoing prompts (`StartCascade`, `SendUserCascadeMessage`) queue locally in a per-host **Durable Outbox** for instant optimistic UI and automatic replay upon reconnection.

---

## 5. Overall Architecture

The codebase follows a strict **three-layer architecture** designed to keep platform UI 100% native while maximizing shared protocol, model, and rendering logic across iOS and Android via **Kotlin Multiplatform (KMP)**.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/architecture-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/architecture-light.svg">
    <img alt="Three-Layer Architecture: Application, Capability, and Core Layers" src="docs/images/architecture-light.svg" width="100%">
  </picture>
</p>

### Layer Breakdown

| Layer | Responsibility | Key Modules & Paths |
| :--- | :--- | :--- |
| **Layer 1 · Application Layer** | **100% Native UI, Navigation & OS Extensions.** Owns all visual surfaces, gestures, haptics, and platform extensions while observing state unidirectionally. | • **iOS (`apps/ios/App/`, `apps/ios/SharedUI/`, `apps/ios/Extensions/`)**: Swift 6 + SwiftUI/UIKit implementing all 13 UE screens (`UE01`–`UE13`) + v2.33 sheets, Floating Liquid Glass shell, `KmpCoreEngineAdapter` SKIE bridge, Dynamic Island & Lock Screen Live Activity, Share Extension, Face ID, Camera QR scanner, WebView Cloud Relay sign-in, Voice Input, and `WatchConnectivityBridge`.<br>• **Apple Watch (`apps/ios/Watch/`)**: Native watchOS 11+ SwiftUI companion (`AGPocketWatch`) implementing 8 OLED screens (`W01`–`W08`), Double Tap primary actions (`.handGestureShortcut(.primaryAction)`), interactive Long-Look approval notifications (`WKNotificationScene`), Handoff, and hardware wrist-detection unlock guard (`WatchWristUnlockGuard`).<br>• **Android (`apps/android/app/`, `apps/android/core-ui/`, `apps/android/core-platform/`)**: Native Kotlin + Jetpack Compose + Material 3 (`1.4.0`) implementing all 13 UE screens (`UE01`–`UE13`) + v2.33 sheets, adaptive `NavigationSuiteScaffold`, Android 16 `NotificationCompat.ProgressStyle` Live Updates + Android 10–15 Foreground Service fallback, Jetpack Glance widget, `BiometricPrompt`, Material You Dynamic Color opt-in, and native Share receiver.<br>• **Design System**: Matte Obsidian (`#090A0D`) / Watch OLED (`#000000`), Periwinkle CTA (`#8EB4FF`), Biometric Amber (`#EBB365`), Light/Dark/Theme presets, and cross-platform `SemanticIcon` tokens. |
| **Layer 2 · Capability Layer** | **Domain Orchestration, Offline Continuity & Universal Rendering.** Coordinates multi-host state, offline storage, streaming rich content, and OS services. | • **Shared Domain Orchestration (`shared/core-domain/`)**: 7 `StateFlow`-backed stores (`ConnectionDomainStore`, `ConversationSyncStore`, `CascadeChatDomainStore`, `WorkspaceAndAutomationStore`, `ReviewAndVcsStore`, `OrchestrationAndSideChannelStore`, `SettingsAndCustomizationStore`), `DurableOutbox`, `EsddVerificationFixtures`, and `AntigravityCoreCoordinator` exported to iOS via SKIE (`async/await` & `AsyncSequence`) and consumed directly on Android.<br>• **iOS & Watch Session Adapter (`apps/ios/Packages/AntigravityData/`)**: `@Observable` `AntigravitySessionStore` delegating live connection, sync, step loading, and PC interactions via pure-Swift `AntigravityKmpEnginePort` + per-host sharded `LocalProjectionStore`, plus shared `WatchCompanionModels`, `WatchDiffTriageEngine`, `WatchArtifactSummarizer`, and `WatchCompanionProjector`.<br>• **Universal Rendering & Review (`shared/core-markdown/`, `apps/ios/App/Views/Cascade/`, `apps/android/core-ui/`)**: Streaming Markdown AST, code pills, Mermaid diagrams, `<agent-embed>` previews, Implementation Plan inline comments, line-level Turn Diff review, and Rich Artifact viewer.<br>• **Approvals & OS Coordinators (`apps/ios/App/Services/`, `apps/android/core-platform/`)**: Face ID / `BiometricPrompt` / Watch wrist-unlock gate, structured Q&A wizard, `LiveActivityCoordinator` / `AndroidLiveUpdateBuilder`, `AgentProgressForegroundService`, `NotificationCoordinator`, `WatchConnectivityBridge`, and `VoiceInputManager`. |
| **Layer 3 · Core Layer** | **Cross-Platform Shared Core, Wire Protocol & Platform Ports.** Pure, UI-free protocol and model engine compiled for both iOS and Android. | • **KMP Shared Core (`shared/`)**: `:shared:core-model` (canonical models + resilient forward-compatible enums), `:shared:core-protocol` (Ktor OkHttp/Darwin + SHA-256 TLS pinning, 5B Connect framing, Binary-first Protobuf codec, `SAPISIDHASH` Cloud Relay, `HostCapabilityRegistry`, `ProtocolCompatibilityEngine`, ~26 v2.33 RPCs), `:shared:core-markdown` (AST parser), `:shared:core-domain` (7 StateFlow stores), and `:shared:umbrella` (SKIE-enhanced static `AntigravityShared.xcframework` + JVM/Android).<br>• **Extension- & Watch-Safe Pure Swift 6 Data Package (`apps/ios/Packages/AntigravityData/`)**: Zero-UIKit / zero-KMP-binary Swift package supporting iOS, macOS tests, and `watchOS 11+`, keeping WidgetKit & Share extensions safely under the 30 MB memory ceiling.<br>• **Platform Ports (`PlatformPorts`)**: `expect`/`actual` & protocol contracts abstracting `SecretStore` (iOS Keychain / Android Keystore + Tink AEAD), `NetworkReachabilityMonitoring` (`NWPathMonitor` / `ConnectivityManager`), `PowerStateProviding`, `KeyValuePreferencesStore`, and Biometrics. |

### Repository Layout (KMP Monorepo)

```text
.
├── apps/
│   ├── ios/                        # Native Swift 6 iOS (iOS 18+) & Apple Watch (watchOS 11+) clients
│   │   ├── App/                    #   13 iOS UE screens + v2.33 sheets, shell, KMP SKIE bridge (Bridge/), pairing, WatchConnectivityBridge
│   │   ├── Watch/                  #   Native watchOS 11+ SwiftUI companion (`AGPocketWatch`, W01–W08, wrist-unlock guard)
│   │   ├── Extensions/             #   WidgetKit Dynamic Island / Live Activity & Share Extension
│   │   ├── SharedUI/               #   iOS-only Design System tokens, Liquid Glass & Live Activity models
│   │   └── Packages/
│   │       └── AntigravityData/    #   Pure Swift 6 store, Watch models/triage engine, port protocols & extension-safe RPC package
│   └── android/                    # Native Kotlin + Jetpack Compose Material 3 client (Android 10–16)
│       ├── app/                    #   13 UE screens + v2.33 sheets, FGS Live Updates, Glance widget
│       │   ├── src/test/           #     Compose interactive E2E (ATC-01..18), Roborazzi 13-screen & unit tests
│       │   └── src/androidTest/    #     Android KVM Emulator instrumented E2E (standard Gradle layout)
│       ├── core-ui/                #   Material 3 theme (Dark/Light/Material You), SemanticIcon mapper & Markdown components
│       ├── core-platform/          #   AndroidLiveUpdateBuilder, BiometricPrompt, Tink+Keystore SecretStore & OS adapters
│       └── README.md               #   Android build, Roborazzi visual QA & KVM Emulator E2E guide
├── shared/                         # Kotlin Multiplatform (KMP) shared core for iOS & Android
│   ├── core-model/                 #   Canonical Cascade, Workspace, Artifact, LiveProgress & resilient-enum models
│   ├── core-protocol/              #   Ktor (OkHttp/Darwin), TLS Pinning, 5B Connect, Binary Protobuf, Cloud Relay & Compat Engine
│   ├── core-markdown/              #   Cross-platform streaming Markdown AST parser
│   ├── core-domain/                #   7 StateFlow domain stores, DurableOutbox & shared ESDD verification fixtures
│   └── umbrella/                   #   SKIE facade exporting AntigravityShared.xcframework & JVM/Android
├── tests/
│   ├── ios-ui/                     # Native iOS XCUITest interactive tap & flow suite (AGPocketUITests)
│   ├── watchos-ui/                 # Native watchOS XCUITest suite (AGPocketWatchUITests, WTC-01..WTC-14)
│   └── README.md                   # Cross-platform test & E2E directory map (iOS, Watch, Android Gradle layout & KMP)
├── project.yml                     # Root XcodeGen spec assembling iOS, Watch (`AGPocketWatch`), Extensions & UI tests
├── docs/                           # Platform feature matrix (PLATFORM_STATUS.md), architecture SVGs & upstream snapshots
├── scripts/                        # Unified verify CLI, Xcode sync, icon renderer & upstream doc-sync automation
├── specs/                          # Normative iOS, Watch (specs/watch/) & Android (specs/android/) ESDD specs
└── verification/                   # ESDD verifiers (iOS + Watch 14-TC), Android Roborazzi comparer, compat guardrails & Simulator runners
```

---

## 6. How to Contribute

Contributions of all kinds are welcome — from Apple Watch & Android hardware field testing to upstream protocol sync, release packaging, localization, and accessibility!

### Prerequisites

- **iOS & Apple Watch Development**: macOS with Xcode 16+ (Swift 6, watchOS 11+ SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- **Android Development**: JDK 21 and Android SDK (`compileSdk 36`, `ANDROID_HOME` or `local.properties`) / Android Studio.
- **KMP Shared Core**: JDK 21 and Gradle (`./gradlew` included).
- **Protocol & ESDD Verification**: Python 3.10+ (zero external server dependencies for mock RPC tests).

### Building & Running iOS & Apple Watch in Xcode (macOS)

`PocketAntigravity.xcodeproj` and `AntigravityShared.xcframework` are generated locally and excluded from Git. Machine-local Xcode signing (`DEVELOPMENT_TEAM` and optional `ANTIGRAVITY_BUNDLE_PREFIX`) is stored in gitignored `local.signing.xcconfig` (included via [`apps/ios/Config/LocalSigning.xcconfig`](apps/ios/Config/LocalSigning.xcconfig)), so your Team selection persists automatically across `git pull`, `xcodegen`, and `--clean`.

```bash
# 1. Build/refresh KMP XCFramework + regenerate PocketAntigravity.xcodeproj and open Xcode
#    (Includes both `AGPocket` iOS and `AGPocketWatch` watchOS 11+ schemes; auto-preserves/detects local signing)
bash scripts/sync-xcode.sh --open

# (Optional) Persist your Apple Team ID (and optional custom Bundle Prefix) explicitly once
bash scripts/sync-xcode.sh --team YOUR_10_CHAR_TEAM_ID

# (Optional) Install git hooks so future `git pull` / branch switches auto-sync Xcode without losing signing
bash scripts/sync-xcode.sh --install-hooks

# (Optional) Wipe stale pre-monorepo .xcodeproj & DerivedData, or build pure-Swift without JDK
bash scripts/sync-xcode.sh --clean --open
bash scripts/sync-xcode.sh --swift-only --open

# Build, sign & install directly onto a connected physical iPhone (also saves working signing to local.signing.xcconfig)
bash scripts/install-on-iphone.sh
```

### Building & Verifying Android (Linux / macOS / Windows)

`settings.gradle.kts` automatically includes `:apps:android:*` whenever an Android SDK is detected (`ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `local.properties`). See [`apps/android/README.md`](apps/android/README.md) for the complete Android developer guide:

```bash
# Build debug APK, run Android Lint, record 13-screen Roborazzi screenshots & run JVM unit + Compose E2E tests
./gradlew \
  :apps:android:app:assembleDebug \
  :apps:android:app:lintDebug \
  :apps:android:app:recordRoborazziDebug \
  :apps:android:app:testDebugUnitTest \
  --no-daemon

# Run Android Roborazzi + JVM E2E + 1:1 iOS↔Android visual comparison via unified CLI
./scripts/verify.py --suite android --keep-artifacts

# Run instrumented E2E on a connected Android device or running API 35 Emulator
./gradlew :apps:android:app:connectedDebugAndroidTest --no-daemon
```

### Local Verification CLI (Human & Coding-Agent Friendly)

Use the single stateless [`scripts/verify.py`](scripts/verify.py) CLI from any directory — it auto-detects available toolchains on Linux/macOS (including Android SDK & Xcode), suppresses noisy HTTP logs, keeps `git status` clean, and supports machine-readable `--json` output:

```bash
# Fast default gates: Spec-DAG (iOS + Watch) + live mock Connect-RPC + v2.33 + 3-version compat matrix (~7s)
./scripts/verify.py

# Impact-scoped mode: fast gates + change-scoped ESDD (`e2e_impact_planner`)
./scripts/verify.py --auto

# Full available suite: adds full Chromium ESDD 16-TC/@3x audit, KMP JVM tests & Swift 6 XCTest
./scripts/verify.py --full

# Apple Watch 14-TC interactive ESDD & 8-screen 416x496 @2x visual audit
python3 verification/verify_watch_esdd.py

# Machine-readable JSON report (ideal for coding agents & CI tooling)
./scripts/verify.py --json

# Run specific suite(s) only: spec | rpc | v233 | compat | esdd | kmp | swift | android | bridge | sim
./scripts/verify.py --suite rpc,compat,kmp
./scripts/verify.py --list

# Assemble SKIE iOS XCFramework & run Swift 6 strict-concurrency XCTest directly (macOS)
./gradlew :shared:umbrella:assembleAntigravitySharedDebugXCFramework --no-daemon
swift test --package-path apps/ios/Packages/AntigravityData
```

### Pull Request Workflow

1. **Fork** the repository and create a clean branch off `main` (`feat/<topic>`, `fix/<topic>`, or `docs/<topic>`).
2. Follow the architectural boundaries and ESDD guidelines documented in [`AGENTS.md`](AGENTS.md) and [`specs/`](specs/).
3. Ensure zero hardcoded secrets/API keys and verify all local gates pass.
4. Open a **Pull Request** targeting `main` with a concise summary and verification checklist. GitHub Actions automatically runs impact-scoped verification on PRs (`macos-xcode-verify.yml` skips macOS entirely on pure docs/Android/KMP-only PRs and runs Watch Simulator checks via `watchos-simulator-runner.py` when Watch files change; `android-verify.yml` runs Lint, Roborazzi 13-screen visual compare & KVM Emulator E2E on `apps/android/**` / `shared/**` changes; `kmp-verify.yml` runs when `shared/**` changes; releases always enforce 100% full E2E across all platforms).

### Great Areas to Help Out

- **Apple Watch Companion Field Testing**: Real-device validation of `WatchConnectivity` sync over Bluetooth/Wi-Fi, watchOS 11 Double Tap ergonomics (`Allow` / `Send` / `Proceed`), `LAPolicy.deviceOwnerAuthenticationWithWristDetection` wrist-lock behavior, Long-Look approval notifications, and Handoff to iPhone.
- **Android On-Device Hardware Hooks**: Wiring CameraX / ML Kit live QR scanning and live `SpeechRecognizer` audio capture inside `VoiceModeSheet`.
- **Real-Device Field Testing & Distribution**: Testing Android 16 promoted Live Updates on physical Pixel devices, tablets/foldables, Wi-Fi ↔ 5G handoffs, and automating signed TestFlight / APK / Play Store releases.
- **Protocol & Upstream Sync**: Tracking newly introduced upstream Google Antigravity `LanguageServerService` step types, artifact formats, and interaction gates across Swift + KMP + Companion Bridge.
- **UX, Localization & Accessibility**: Multi-language localization (i18n), screen-reader polish (VoiceOver / TalkBack), and edge-case coverage.

---

## 7. License & Declarations

### Open-Source License

This project is open-sourced under the **[MIT License](LICENSE)**. You are free to use, modify, and distribute this software in accordance with the terms of the MIT License.

### Original Creation & Copyright Declaration

- **Copyright © 2026 PocketAntigravity Contributors.**
- All client source code, multiplatform architecture, protocol implementations, companion scripts, diagrams, and the original 7-segment Orbital Terminal app icon (**`AG Pocket`**, [`scripts/assets/ag-pocket-original-icon.svg`](scripts/assets/ag-pocket-original-icon.svg)) are **100% original works** authored by the creator and contributors of this repository.
- This repository contains **zero** official Google graphic assets, icons, or proprietary brand files, designed for full compliance with Apple App Store Review Guidelines 5.2.2 and 4.1.

### Unofficial Companion & Trademark Disclaimer

- **AG Pocket (`PocketAntigravity`)** is an independent, unofficial third-party companion client. It is **not** affiliated with, endorsed by, sponsored by, or officially connected to **Google LLC**.
- *"Google"*, *"Gemini"*, *"Google Antigravity"*, and *"Antigravity"* are trademarks of **Google LLC**, referenced solely under nominative fair use to describe protocol interoperability with user-managed Antigravity environments (see [`NOTICE`](NOTICE)).
