# AG Orbit — Android Client (Planned · Phase 3)

This directory is reserved for the native **Android** application built with **Kotlin + Jetpack Compose + Material 3**.

## Shared Core Integration

The Android app consumes the repository's Kotlin Multiplatform shared core modules directly as Gradle project dependencies:

- `:shared:core-model` — Canonical Cascade, Workspace, Artifact & Interaction data models.
- `:shared:core-protocol` — Ktor OkHttp engine (with SHA-256 TLS pinning / LAN TOFU), 5-byte Connect-RPC streaming, Binary Protobuf (`>= 600` steps), and Google Cloud Relay (`SAPISIDHASH`).
- `:shared:core-markdown` — Cross-platform streaming Markdown AST parser.
- `:shared:core-domain` — `StateFlow`-backed `ConnectionDomainStore`, `ConversationSyncStore`, `CascadeChatDomainStore`, `DurableOutbox`, and `AntigravityCoreCoordinator`.

## Android-Native Platform Adapters (To Be Implemented)

- `SecretStore` → Android Keystore + EncryptedSharedPreferences
- `NetworkReachabilityMonitoring` → `ConnectivityManager.NetworkCallback`
- `PowerStateProviding` → `PowerManager.isPowerSaveMode`
- Biometric Approval Gate → `androidx.biometric.BiometricPrompt`
- Live Progress Surfaces → Android Ongoing Notifications / Live Updates
