<div align="center">

# AG Orbit (`iOSAntigravity`)

**Native iOS & Android Mobile Client for Google Antigravity Remote Control**

[![Platforms](https://img.shields.io/badge/Platforms-iOS%2018%2B%20%7C%20Android-5B8DEF?style=flat-square)](#4-overall-architecture)
[![Shared Core](https://img.shields.io/badge/Shared%20Core-Kotlin%20Multiplatform%20%2B%20Swift%206-7C6EE6?style=flat-square)](#4-overall-architecture)
[![Protocol](https://img.shields.io/badge/Protocol-Connect--RPC%20%2B%20Cloud%20Relay-2E9679?style=flat-square)](#3-core-principle--how-it-interacts-with-antigravity)
[![License: MIT](https://img.shields.io/badge/License-MIT-EBB365?style=flat-square)](LICENSE)

</div>

---

## 1. What Is This Project?

**AG Orbit (`iOSAntigravity`)** is an open-source **native iOS and Android client** for **Google Antigravity**, enabling **one-tap pairing and real-time remote control** of your Antigravity PC / Desktop and Cloud agent sessions straight from your phone. Built with 100% native mobile UI (Swift 6 SwiftUI/UIKit on iOS and Kotlin Jetpack Compose on Android) backed by a Kotlin Multiplatform (KMP) protocol core, it speaks directly to Antigravity's `LanguageServerService` with zero web-bundle overhead.

---

## 2. Why I Built This

With the recent leap in **Gemini**'s reasoning and coding capabilities, Antigravity quickly became my daily driver for software engineering. I love using its **Remote Control** workflow to launch tasks, monitor progress, review implementation plans, and approve terminal commands while away from my desk — yet I was surprised to discover that Antigravity had **no official native mobile app** for iOS or Android. Relying on a desktop web wrapper on a phone felt sluggish and disconnected from real mobile ergonomics (Face ID / biometric approvals, Dynamic Island & Live Activities, offline resilience, and fluid native gestures), so I built this native app from the ground up.

---

## 3. Core Principle — How It Interacts with Antigravity

Rather than embedding a mobile browser or wrapping the ~9 MB desktop React bundle, the client implements Antigravity's native **Connect-RPC wire protocol** (`exa.language_server_pb.LanguageServerService`) directly on-device and supports **two zero-wrapper transport channels**:

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/core-principle-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="docs/images/core-principle-light.svg">
    <img alt="Core Principle: How Native iOS and Android Clients Interact with Antigravity PC" src="docs/images/core-principle-light.svg" width="100%">
  </picture>
</p>

### Dual Native Transport Channels

- **Channel A — Official Cloud Relay (Recommended · Any Network: Wi-Fi / 5G)**
  1. Open **Remote Control** in Antigravity Desktop to reveal your pairing QR code (`https://antigravity.google.com/r/<instance-id>`).
  2. Scan the QR code (or paste the `/r/<id>` URL) on mobile and sign in once with your Google account; session credentials are persisted strictly inside **iOS Keychain / Android Keystore**.
  3. The client dynamically discovers the Relay Web API key (zero hardcoded keys in source), signs requests with `SAPISIDHASH`, resolves your online PC host UUID via `devtools_jetski_boq_api_proto.ApiService/ListInstances` (auto-probing multi-account `X-Goog-AuthUser` + live reachability), and tunnels all unary & streaming `LanguageServerService` RPCs through `ApiService/ProxyCommand` and `ApiService/StreamProxyCommand`.
- **Channel B — Direct LAN / Tailscale Companion Bridge (Optional Local-Only Fallback)**
  1. Run the zero-dependency [`scripts/mac-companion-bridge.py`](scripts/mac-companion-bridge.py) on your desktop to auto-discover running `language_server` / `agy --hub` loopback ports and dynamic `--csrf_token` values.
  2. Pair directly over LAN or Tailscale with SHA-256 TLS pinning / local self-signed TOFU trust and the `x-codeium-csrf-token` header.

### Wire Protocol & Interaction Lifecycle

1. **5-Byte Connect Streaming Envelope**: Real-time push streams (`JetboxSubscribeToSummaries`, `StreamCascadeReactiveUpdates`, `ProjectUpdatesStream`) frame every chunk with a 5-byte prefix (`[1B flags (0x00 raw / 0x01 gzip / 0x02 end-trailer) | 4B big-endian length | payload]`).
2. **Dual-Mode Trajectory Decoding (`< 600` JSON / `≥ 600` Binary Protobuf)**: Upstream JSON responses truncate trajectories above 600 steps. The client seamlessly switches to raw binary Protobuf (`Content-Type: application/proto`) at `≥ 600` steps via `ProtobufStepDecoder` / `ProtobufStepCodec`, decoding all 21 `CORTEX_STEP_TYPE_*` step kinds and field 56 (`requestedInteraction`) without data loss.
3. **Biometric Approval Gate & Durable Outbox**: Whenever a remote PC agent pauses in `CORTEX_STEP_STATUS_WAITING (9)` (shell command execution, file permission, plan review, or multi-step structured question), the app surfaces an inline amber approval card and Dynamic Island / notification action gated by **Face ID / BiometricPrompt**, then dispatches the exact matching oneof via `HandleCascadeUserInteraction`. Outgoing prompts (`StartCascade`, `SendUserCascadeMessage`) queue locally in a per-host **Durable Outbox** for instant optimistic UI and automatic replay upon reconnection.

---

## 4. Overall Architecture

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
| **Layer 1 · Application Layer** | **100% Native UI, Navigation & OS Extensions.** Owns all visual surfaces, gestures, haptics, and platform extensions while observing state unidirectionally. | • **iOS (`iOS/`, `Shared/`, `Extensions/`)**: Swift 6 + SwiftUI/UIKit implementing all 13 UE screens (`UE01`–`UE13`), Floating Liquid Glass shell, Dynamic Island & Lock Screen Live Activity, Share Extension, Face ID, and Voice Input.<br>• **Android (Kotlin / Jetpack Compose)**: Native Material 3 UI, `BiometricPrompt`, and live progress notifications consuming the KMP `shared/` JVM/Android modules.<br>• **Design System**: Matte Obsidian (`#090A0D`), Periwinkle CTA (`#8EB4FF`), Face ID Amber (`#EBB365`), and cross-platform `SemanticIcon` tokens. |
| **Layer 2 · Capability Layer** | **Domain Orchestration, Offline Continuity & Universal Rendering.** Coordinates multi-host state, offline storage, streaming rich content, and OS services. | • **Session & Multi-Host Sync (`AntigravitySessionStore`)**: Multi-host isolation, host switcher, live reachability probing, workspaces/projects, and automations.<br>• **Offline Cache & Outbox (`LocalProjectionStore`)**: Per-host sharded local snapshots preserving offline hosts, instant cold-start reads, and Durable Outbox replay.<br>• **Universal Rendering & Review (`shared/core-markdown`, `iOS/Views/Cascade/`, `iOS/ViewControllers/Inspector/`)**: Streaming Markdown AST, TextKit code pills, Mermaid diagrams, `<agent-embed>` previews, Implementation Plan inline comments, and line-level Turn Diff review.<br>• **Approvals & Coordinators (`iOS/Services/`)**: Biometric interaction gate, structured Q&A wizard, `LiveActivityCoordinator`, `NotificationCoordinator`, and `VoiceInputManager`. |
| **Layer 3 · Core Layer** | **Cross-Platform Shared Core, Wire Protocol & Platform Ports.** Pure, UI-free protocol and model engine compiled for both iOS and Android. | • **KMP Shared Core (`shared/`)**: `:shared:core-model` (canonical models), `:shared:core-protocol` (5B Connect framing, binary Protobuf codec, `SAPISIDHASH` Cloud Relay, `InteractionBuilder`, lifecycle policy), `:shared:core-markdown` (AST parser), and `:shared:umbrella` (`AntigravityShared.xcframework` + Android/JVM artifacts).<br>• **Pure Swift 6 Data Package (`Packages/AntigravityData/`)**: Zero-UIKit Connect-RPC & Cloud Relay engine keeping iOS WidgetKit & Share extensions safely under the 30 MB memory ceiling.<br>• **Platform Ports (`PlatformPorts`)**: `expect`/`actual` & protocol contracts abstracting `SecretStore` (Keychain / Keystore), `NetworkReachabilityMonitoring` (`NWPathMonitor` / `ConnectivityManager`), `PowerStateProviding`, `KeyValuePreferencesStore`, and Biometrics. |

### Repository Layout

```text
.
├── iOS/                        # Native Swift 6 iOS app (13 UE screens, shell, pairing, services)
├── Extensions/                 # iOS WidgetKit Dynamic Island / Live Activity & Share Extension
├── Shared/                     # Native iOS Design System tokens, Liquid Glass & Live Activity models
├── Packages/AntigravityData/   # Pure Swift 6 protocol & store package (zero UIKit)
├── shared/                     # Kotlin Multiplatform (KMP) shared core for Android & iOS
│   ├── core-model/             #   Canonical Cascade, Workspace, Artifact & Interaction models
│   ├── core-protocol/          #   5B Connect framing, Binary Protobuf, Cloud Relay & PlatformPorts
│   ├── core-markdown/          #   Cross-platform streaming Markdown AST parser
│   └── umbrella/               #   Unified facade exporting AntigravityShared.xcframework & JVM/Android
├── scripts/                    # Mac Companion Bridge, icon renderer & upstream doc-sync automation
├── specs/                      # Normative ESDD product, protocol & E2E test specifications
└── verification/               # 4-gate ESDD verifier, mock LanguageServer & Simulator E2E runner
```

---

## 5. How to Contribute

Contributions of all kinds are welcome — from Android Jetpack Compose screens and KMP core parity to upstream protocol features, bug fixes, accessibility improvements, and documentation!

### Prerequisites

- **iOS Development**: macOS with Xcode 16+ (Swift 6) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- **KMP / Android Shared Core**: JDK 21 and Gradle (`./gradlew` included).
- **Protocol & ESDD Verification**: Python 3.10+ (zero external server dependencies for mock RPC tests).

### Local Verification Commands

Before opening a pull request, run the relevant test suites locally:

```bash
# 1. Live Connect-RPC E2E tests (Auth, StartCascade, SendMessage, Binary Protobuf >=600 steps, Face ID Gate)
python3 verification/verify-live-rpc-flow.py
python3 verification/verify-v233-capabilities.py

# 2. Full 4-gate ESDD verification suite (Spec-DAG, 16 E2E journeys, secret hygiene & HIG audit)
python3 verification/esdd-verify.py

# 3. KMP shared core tests (JVM + Mock LanguageServer E2E — runs on Linux, macOS & Windows)
./gradlew :shared:core-model:jvmTest :shared:core-protocol:jvmTest :shared:core-markdown:jvmTest :shared:umbrella:jvmTest --no-daemon

# 4. Swift 6 strict-concurrency XCTest suite (macOS)
swift test --package-path Packages/AntigravityData
```

### Pull Request Workflow

1. **Fork** the repository and create a clean branch off `main` (`feat/<topic>`, `fix/<topic>`, or `docs/<topic>`).
2. Follow the architectural boundaries and ESDD guidelines documented in [`AGENTS.md`](AGENTS.md) and [`specs/`](specs/).
3. Ensure zero hardcoded secrets/API keys and verify all local gates pass.
4. Open a **Pull Request** targeting `main` with a concise summary and verification checklist. GitHub Actions automatically executes the full `macos-15` Xcode / iOS Simulator E2E pipeline and KMP verification workflows on every PR.

### Great Areas to Help Out

- **Android Native UI**: Building out the native Jetpack Compose screens (`UE01`–`UE13`) and foreground progress notifications on top of `shared/`.
- **KMP Shared Core Parity**: Expanding `:shared:core-protocol` and domain stores for full iOS + Android feature parity.
- **Protocol & Upstream Sync**: Supporting newly introduced `LanguageServerService` step types, artifact formats, and interaction gates.
- **UX, Localization & Testing**: Improving accessibility, localization, and real-device edge-case coverage.

---

## 6. License & Declarations

### Open-Source License

This project is open-sourced under the **[MIT License](LICENSE)**. You are free to use, modify, and distribute this software in accordance with the terms of the MIT License.

### Original Creation & Copyright Declaration

- **Copyright © 2026 iOSAntigravity Contributors.**
- All client source code, multiplatform architecture, protocol implementations, companion scripts, diagrams, and the original 7-segment Orbital Terminal app icon (**`AG Orbit`**, [`scripts/assets/ag-orbit-original-icon.svg`](scripts/assets/ag-orbit-original-icon.svg)) are **100% original works** authored by the creator and contributors of this repository.
- This repository contains **zero** official Google graphic assets, icons, or proprietary brand files, designed for full compliance with Apple App Store Review Guidelines 5.2.2 and 4.1.

### Unofficial Companion & Trademark Disclaimer

- **AG Orbit (`iOSAntigravity`)** is an independent, unofficial third-party companion client. It is **not** affiliated with, endorsed by, sponsored by, or officially connected to **Google LLC**.
- *"Google"*, *"Gemini"*, *"Google Antigravity"*, and *"Antigravity"* are trademarks of **Google LLC**, referenced solely under nominative fair use to describe protocol interoperability with user-managed Antigravity environments (see [`NOTICE`](NOTICE)).
