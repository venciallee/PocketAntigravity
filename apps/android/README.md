# AG Pocket — Android Client (Kotlin + Jetpack Compose + Material 3)

Native Android client for **PocketAntigravity** (`minSdk = 29`, `compileSdk = 36`, `targetSdk = 36`), built with **Kotlin 2.1.21**, **Jetpack Compose** (`compose-bom 2025.10.00`), and **Material 3** (Expressive dark Matte Obsidian `#090A0D` / Periwinkle `#8EB4FF` / Amber Approval `#EBB365`, plus optional Material You Dynamic Color).

See the cross-platform capability matrix in [`docs/PLATFORM_STATUS.md`](../../docs/PLATFORM_STATUS.md) and the normative specifications in [`specs/android/`](../../specs/android/):
- [`01-prd-and-ux-spec.md`](../../specs/android/01-prd-and-ux-spec.md) — Product requirements & Material 3 UX parity across `UE01`..`UE13`
- [`02-tech-architecture-and-kmp-parity.md`](../../specs/android/02-tech-architecture-and-kmp-parity.md) — KMP parity, protocol forward compatibility, and Android module design
- [`03-unit-and-e2e-test-plan.md`](../../specs/android/03-unit-and-e2e-test-plan.md) — 4-layer test matrix (`ATC-01`..`ATC-18`) & Roborazzi visual QA plan

---

## 1. Three-Module Android Architecture

`settings.gradle.kts` automatically includes the Android modules whenever an Android SDK is detected via `ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `local.properties` (`sdk.dir`), allowing macOS-only iOS XCFramework runners without an Android SDK to stay green.

| Module | Gradle Path | Responsibilities |
| :--- | :--- | :--- |
| **Core UI** | `:apps:android:core-ui` | Material 3 `AntigravityTheme` (Dark/Light/Theme presets + Material You opt-in), 5-tier typography, `SemanticIcon` → Material Symbols mapping, streaming Compose Markdown renderer, shared cards, status pills, and `>=48dp` touch-target geometry helpers. |
| **Core Platform** | `:apps:android:core-platform` | Android-native adapters: `AndroidSecretStore` (Android Keystore + Tink AEAD + DataStore), `AndroidNetworkMonitor` (`ConnectivityManager`), `AndroidPowerStateProvider`, `AndroidPreferencesStore`, `AndroidProjectionStorage`, `BiometricApprovalController` (`BiometricPrompt`), `AndroidLiveUpdateBuilder` (Android 16 `NotificationCompat.ProgressStyle` Live Updates + FGS fallback), `AndroidSharePayloadParser`, and `CloudRelayCookieBridge`. |
| **App** | `:apps:android:app` | `Application`, pure-Kotlin DI graph, edge-to-edge `MainActivity` + deep-link routing, adaptive `NavigationSuiteScaffold`, and all 13 UE screens & sheets (`UE01`..`UE13` + v2.33 Overview / `/btw` Side Question / `/swarm` Board / Voice Mode / Rich Artifact Viewer / Glance Widget), plus JVM unit tests, interactive Compose E2E (`ATC-01`..`ATC-18`), Roborazzi screenshots, and instrumented emulator E2E. |

---

## 2. KMP Shared Core Integration

`:apps:android:app` consumes all five Kotlin Multiplatform shared core modules directly as Gradle project dependencies with zero duplicated networking or state-machine code:

- **`:shared:core-model`** — Canonical Cascade, Workspace, Artifact, Interaction, Context, Slash-Command, and `LiveProgressSnapshot` models with forward-compatible resilient enum deserialization.
- **`:shared:core-protocol`** — Ktor OkHttp engine (SHA-256 TLS pinning / LAN TOFU), 5-byte Connect-RPC streaming, Binary-first Protobuf with adaptive JSON fallback, Google Cloud Relay (`SAPISIDHASH`), `HostCapabilityRegistry`, and `ProtocolCompatibilityEngine` (unknown-field stripping, enum downgrades, per-host negative caching).
- **`:shared:core-markdown`** — Cross-platform streaming Markdown AST parser.
- **`:shared:core-domain`** — `AntigravityCoreCoordinator` composing 7 `StateFlow`-backed domain stores (`ConnectionDomainStore`, `ConversationSyncStore`, `CascadeChatDomainStore`, `WorkspaceAndAutomationStore`, `ReviewAndVcsStore`, `OrchestrationAndSideChannelStore`, `SettingsAndCustomizationStore`) plus shared deterministic `EsddVerificationFixtures`.
- **`:shared:umbrella`** — Unified shared facade and parity exports.

---

## 3. Local Verification Commands

Ensure JDK 21 and an Android SDK (`ANDROID_HOME` or `local.properties`) are configured, then run from the repository root:

```bash
# Unified CLI: inspect detected toolchains (includes `android` SDK detection)
./scripts/verify.py --list

# Fast default gates (~7s; Python/ESDD/RPC/Compat — Android excluded to stay fast)
./scripts/verify.py

# Android suite: Roborazzi capture + JVM unit/Compose E2E + iOS↔Android visual comparison
./scripts/verify.py --suite android --keep-artifacts

# Direct Gradle build, Lint, Roborazzi 13-screen capture, and JVM tests
./gradlew \
  :apps:android:app:assembleDebug \
  :apps:android:app:lintDebug \
  :apps:android:app:recordRoborazziDebug \
  :apps:android:app:testDebugUnitTest \
  --no-daemon

# Instrumented E2E on a connected Android device or running Emulator
./gradlew :apps:android:app:connectedDebugAndroidTest --no-daemon

# Standalone bidirectional compatibility guardrails (Swift + KMP + Companion Bridge)
python3 verification/verify_compat_guardrails.py
```

---

## 4. Roborazzi 13-Screen Visual Comparison vs iOS UE

`AndroidUeScreenshotTest` renders all 13 native Jetpack Compose screens (`UE01_AGENTS_HOME` .. `UE13_LIVE_ACTIVITY_SPEC`) under Robolectric `GraphicsMode.NATIVE` + Roborazzi (`412×915dp` Pixel portrait + `800×500dp` `UE13` Live Updates spec) into `apps/android/app/build/outputs/android_ue/`.

Running `verification/android_visual_compare.py` pairs each Compose render 1:1 against the canonical iOS reference screenshots under `verification/output/screenshots/`:

```bash
python3 verification/android_visual_compare.py
```

Generated artifacts under `verification/output/android/`:
- `comparisons/ANDROID_CMP_UE01.png` .. `comparisons/ANDROID_CMP_UE13.png` — Side-by-side (**LEFT**: iOS Reference UE vs **RIGHT**: Android Native Jetpack Compose Material 3)
- `ANDROID_13_SCREENS_OVERVIEW.png` — 13-screen master visual QA gallery
- `android_visual_report.json` — Structured completeness and pixel-dimension report

---

## 5. GitHub Actions CI Pipeline (`ubuntu-latest`)

Android verification runs entirely on Linux (`ubuntu-latest`) via [`.github/workflows/android-verify.yml`](../../.github/workflows/android-verify.yml), integrated with [`verification/e2e_impact_planner.py`](../../verification/e2e_impact_planner.py):

- **Impact-Scoped Routing**:
  - Pure `apps/android/**` and `specs/android/**` PRs set `needs_macos=false` and `needs_android=true`, skipping expensive macOS Xcode Simulator runners completely.
  - `shared/**` changes run both KMP verification and Android JVM/Lint/Roborazzi checks.
  - Releases (`is_release=true`) enforce 100% full verification across iOS, Android (JVM + Roborazzi + KVM Emulator E2E), and KMP.
- **Job 1 (`android-jvm-and-roborazzi`, timeout 25m)**:
  - Evaluates blast radius via `e2e_impact_planner.py`, runs `verify_compat_guardrails.py`, executes `:apps:android:app:assembleDebug :apps:android:app:lintDebug :apps:android:app:recordRoborazziDebug :apps:android:app:testDebugUnitTest --no-daemon`, generates all 13 `ANDROID_CMP_UE01..UE13.png` + `ANDROID_13_SCREENS_OVERVIEW.png` sheets, and uploads the `android-visual-comparisons` artifact.
- **Job 2 (`android-emulator-e2e`, timeout 35m)**:
  - Runs after Job 1 on `release`, `workflow_dispatch`, `push` to `main`, or PRs touching `apps/android/**`.
  - Enables `/dev/kvm` udev permissions and launches a headless API 35 (`google_apis`, `x86_64`, `pixel_6`) emulator via `reactivecircus/android-emulator-runner@v2` to execute `:apps:android:app:connectedDebugAndroidTest --no-daemon`.
