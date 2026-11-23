# Cross-Platform Test & E2E Directory Map

This repository keeps each platform's test suites in the directory convention expected by its native build system (**XcodeGen / SwiftPM** on iOS and **Gradle / AGP** on Android & KMP):

- **iOS UI E2E (`XCUITest`)** lives here under [`tests/ios-ui/`](ios-ui/) because `AGPocketUITests` is a standalone black-box Xcode target declared in [`project.yml`](../project.yml).
- **Android UI & Emulator E2E** lives inside the `:apps:android:app` Gradle module (`src/androidTest/` and `src/test/`) following standard Android Gradle Plugin (AGP) layout so Android Studio and `./gradlew` discover all instrumented, Compose, and Roborazzi tests with zero custom `sourceSets` remapping.

---

## Complete Test Inventory

| Platform / Layer | Suite Type | Location | How to Run |
| :--- | :--- | :--- | :--- |
| **iOS** | Real Simulator XCUITest (`AGPocketUITests`) | [`tests/ios-ui/AntigravityInteractiveUITests.swift`](ios-ui/AntigravityInteractiveUITests.swift) | `python3 verification/ios-simulator-runner.py` (macOS + Xcode) |
| **iOS** | Swift 6 Data Package Unit Tests | [`apps/ios/Packages/AntigravityData/Tests/AntigravityDataTests/`](../apps/ios/Packages/AntigravityData/Tests/AntigravityDataTests/) | `swift test --package-path apps/ios/Packages/AntigravityData` |
| **Android** | KVM Emulator Instrumented E2E (API 35 Pixel 6) | [`apps/android/app/src/androidTest/kotlin/dev/antigravity/android/AndroidEmulatorE2eTest.kt`](../apps/android/app/src/androidTest/kotlin/dev/antigravity/android/AndroidEmulatorE2eTest.kt) | `./gradlew :apps:android:app:connectedDebugAndroidTest --no-daemon` |
| **Android** | Compose Interactive E2E (`ATC-01`–`ATC-18`) | [`apps/android/app/src/test/kotlin/dev/antigravity/android/AndroidInteractiveE2eTest.kt`](../apps/android/app/src/test/kotlin/dev/antigravity/android/AndroidInteractiveE2eTest.kt) | `./gradlew :apps:android:app:testDebugUnitTest --no-daemon` |
| **Android** | Roborazzi 13-Screen Pixel Capture & Geometry Audit | [`apps/android/app/src/test/kotlin/dev/antigravity/android/AndroidUeScreenshotTest.kt`](../apps/android/app/src/test/kotlin/dev/antigravity/android/AndroidUeScreenshotTest.kt) | `./scripts/verify.py --suite android --keep-artifacts` |
| **Android** | Design System & Platform Unit Tests | [`apps/android/app/src/test/kotlin/dev/antigravity/android/DesignSystemAndPlatformUnitTest.kt`](../apps/android/app/src/test/kotlin/dev/antigravity/android/DesignSystemAndPlatformUnitTest.kt) | `./gradlew :apps:android:app:testDebugUnitTest --no-daemon` |
| **KMP Shared Core** | Common Unit & Domain Store Tests | [`shared/core-model/src/commonTest/`](../shared/core-model/src/commonTest/), [`shared/core-protocol/src/commonTest/`](../shared/core-protocol/src/commonTest/), [`shared/core-markdown/src/commonTest/`](../shared/core-markdown/src/commonTest/), [`shared/core-domain/src/commonTest/`](../shared/core-domain/src/commonTest/), [`shared/umbrella/src/commonTest/`](../shared/umbrella/src/commonTest/) | `./gradlew :shared:core-model:jvmTest :shared:core-protocol:jvmTest :shared:core-markdown:jvmTest :shared:core-domain:jvmTest :shared:umbrella:jvmTest --no-daemon` |
| **KMP Shared Core** | Live Mock LanguageServer & 3-Version Compat E2E | [`shared/core-protocol/src/jvmTest/kotlin/dev/antigravity/shared/protocol/V233AndCompatMatrixE2eTest.kt`](../shared/core-protocol/src/jvmTest/kotlin/dev/antigravity/shared/protocol/V233AndCompatMatrixE2eTest.kt) | `./scripts/verify.py --suite kmp` |
| **Protocol & ESDD** | Spec-DAG, Mock Connect-RPC, v2.33, 3-Version Compat Matrix, Guardrails & Visual Comparison | [`verification/`](../verification/) | `./scripts/verify.py` (fast) · `./scripts/verify.py --full` |

See [`docs/PLATFORM_STATUS.md`](../docs/PLATFORM_STATUS.md) for the full CI workflow coverage matrix across iOS, Android, and KMP.
