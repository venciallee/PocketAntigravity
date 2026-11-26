# AG Pocket Android — Technical Architecture, KMP Shared Core Parity & Protocol Upstream Sync (v1.0)

- **Status**: Normative Technical Design
- **Scope**:
  1. KMP Shared Core Parity (`shared/*` ↔ `apps/ios/Packages/AntigravityData`)
  2. Forward-Compatible Protocol & Upstream Sync (`LanguageServerService`)
  3. Android Native App Architecture (`apps/android/*`) & GitHub Actions CI (`ubuntu-latest`)

---

## 1. KMP Shared Core Parity Plan (`shared/`)

### 1.1 Module & Toolchain Alignment
- Preserve Kotlin `2.1.21` + SKIE `0.10.6` + Gradle `8.11.1` so existing iOS `AntigravityShared.xcframework` builds remain 100% green.
- Add AGP `8.9.1`, Compose Compiler plugin `2.1.21`, Compose BOM `2025.10.00` (Material 3 `1.4.0`), `androidx.core:core-ktx:1.17.0` (`NotificationCompat.ProgressStyle` + `setRequestPromotedOngoing`), Robolectric `4.14.1`, and Roborazzi `1.43.1`.
- Android modules consume `:shared:core-model`, `:shared:core-protocol`, `:shared:core-markdown`, `:shared:core-domain`, and `:shared:umbrella` directly via Gradle project dependencies (reusing the JVM/OkHttp TLS-pinned engine in `PlatformHttpClient.jvm.kt` with zero duplicated networking code).

### 1.2 `:shared:core-model` Parity & Forward-Compatibility
- Add `ResilientEnumSerializer` helper so protocol-decoded enums fall back cleanly to safe defaults on unrecognized upstream strings (never throwing `SerializationException`).
- Ensure full model parity with Swift `AntigravityData`:
  - `ArtifactKind.UNKNOWN` fallback for future artifact types.
  - `ContextCandidateCategory`, `ContextCandidateItem`, `SlashCommandItem` (all 15 official App slash commands + remote compatibility flags).
  - `QueuedMessageItem`, `ConversationTurnSummary`, `JupyterNotebookDocument` / `JupyterNotebookCell`, `ImageRegionComment`, `LiveProgressSnapshot` (platform-neutral model driving both iOS `ActivityKit` and Android 16 `ProgressStyle` Live Updates).
  - `AppAppearancePreferences` extended with `useDynamicColor: Boolean = false` (Android Material You opt-in).

### 1.3 `:shared:core-protocol` Parity
1. **`HostCapabilityRegistry.kt` & `ProtocolCompatibilityEngine.kt`** (1:1 port of Swift `HostCapabilityRegistry.swift`):
   - `AntigravitySemVer` parser & comparator.
   - `HostCapability` enum (all 16 capabilities), `coreBaselineMethods` (31 methods), `legacyAliasMethods` (4 methods), `allRegisteredMethods`, and inverse-allowlist `shouldNegativeCacheOnUnimplemented`.
   - `HostCapabilityProfile` tracking `reportedVersion`, `isCompanionBridge`, `bridgeSupportedMethods`, `supportedMethods`, `unsupportedMethods`, `strippedFieldsByMethod`, `downgradedEnumsByMethod`, `passiveSignals`, `learnedJsonStepCeiling`, `binaryProtobufStepsUnsupported`, with automatic cache invalidation when `reportedVersion` changes.
   - `ProtocolCompatibilityEngine`: `isMethodUnimplementedResponse`, `extractUnknownProtoFieldName` (unwrapping JSON errors), `extractInvalidEnumValue`, `downgradedEnumReplacement` (synced 1:1 with Swift & `scripts/mac-companion-bridge.py`), `recursivelyRemoveField` (with rich `codeQuote`/`mention`/`media` folding to readable text), `recursivelyReplaceEnumValue`, `recursivelyRemoveKeysWithValue`, and `applyKnownDowngrades`.
2. **`AntigravityKmpRpcClient.kt` Expansion (~26 RPCs + Capability Engine Wiring)**:
   - Wire `HostCapabilityProfile` & `ProtocolCompatibilityEngine` into both Direct LAN and Cloud Relay unary JSON dispatch (automatic field stripping, enum downgrade retry, Bridge `X-Antigravity-Bridge-Capabilities` header parsing, per-host negative caching on `404/501/unimplemented`).
   - Add missing RPCs:
     - Models & Quota: `fetchModelCatalog(forceRefresh)` (`GetCascadeModelConfigs` / `GetCascadeModelConfigData` / `GetAvailableModels` / `GetUserStatus`)
     - Artifacts & Plan Review: `getArtifactSnapshots`, `fetchRemoteArtifactResource` (`ReadArtifactFile` / `GetRevisionArtifact`), `sendPlanReviewComments`
     - Turn Diff & Git VCS: `getTurnDiff`, `revertDiffHunk`, `sendDiffReviewComments`, `gitStageFile`, `gitUnstageFile`, `gitDiscardFile`, `gitCommitChanges`, `gitPushBranch`
     - v2.33 Orchestration: `fetchConversationOverview`, `cancelBackgroundTask`, `stopSubagent`, `sendSideQuestion`, `revertConversationToStep`, `setConversationPermissionPreset`
     - Customizations & Search: `fetchCustomizationsCatalog`, `restartMcpServer`, `togglePlugin`, `installMarketplacePlugin`, `searchAllConversations`
     - Projects & Automations: `fetchCloudProjects`, `fetchCloudGitHubRepos`, `createAutomation`, `setAutomationPaused`, `moveCascadeToWorkspace`, `listAvailableResources`
     - Streaming: `subscribeCascadeReactiveUpdates` (`StreamCascadeReactiveUpdates` 5-byte Connect-RPC server stream)

### 1.4 `:shared:core-domain` Expansion (7 Cohesive Stores + Shared ESDD Fixtures)
Extend `AntigravityCoreCoordinator` to compose 7 `StateFlow`-backed stores:
1. `ConnectionDomainStore` (existing + `HostCapabilityProfile` snapshot & capability query APIs)
2. `ConversationSyncStore` (existing + Display Options grouping/sorting/unread/auto-pin, collapsed project persistence, `searchAllConversations`)
3. `CascadeChatDomainStore` (existing + queued follow-up messages, turn navigator summaries, `revertToStep`, forward-compatible unknown step/gate handling)
4. `WorkspaceAndAutomationStore` (Project detail state, `CreateProject` draft & submission, Automations CRUD/run/pause-resume, `AddContext` candidates & multi-select)
5. `ReviewAndVcsStore` (Artifact snapshots, Plan inline comments & send/proceed, Turn/WorkingTree/Staged/Branch diffs, line comments, Hunk/File revert, Git stage/unstage/discard/commit/push)
6. `OrchestrationAndSideChannelStore` (Conversation overview, `/btw` multi-turn side questions + insert into main, `/swarm` board filtering, Voice Mode state & call transcript summary)
7. `SettingsAndCustomizationStore` (Model catalog, Mode/Effort/Agent selection with Orchestrator effort lock, Quota, Permission presets & rules, Customizations catalog, Appearance/Theme/DynamicColor preferences)
8. `EsddVerificationFixtures` (canonical deterministic `UE01`..`UE13` dataset shared by Android & iOS verification harnesses)

Every live write operation uses `performLiveCapabilityWrite(...)` with state rollback + user-facing unsupported capability message — zero silent swallowing.

---

## 2. Protocol & Upstream Sync Architecture

1. **Forward-Compatible Step Types**: Unrecognized protobuf `CortexStepType` wire IDs trigger targeted `stepOffset` JSON repair (`repairUnrecognizedWireStepsIfNeeded`), populate `rawTypeName` & `fallbackSummary`, and render via a dedicated `UnknownForwardStepCard` (never dropped, never crashing).
2. **Forward-Compatible Artifact Formats**: Unknown extensions/MIME types fall back to `ArtifactKind.UNKNOWN` with safe monospace text preview (for text payloads) or external `FileProvider` handoff card (for binary payloads).
3. **Forward-Compatible Interaction Gates**: Unknown `RequestedInteraction` oneof fields trigger JSON repair, preserve `rawMemberKey` + `rawSummary`, and render a `GenericFallbackInteractionCard` with Biometric-protected `Allow Once` / `Deny`, dispatching the matching wire member via `InteractionBuilder`.
4. **Static Compatibility Guardrails (`verification/verify_compat_guardrails.py`)**:
   - Guardrail 1: Register every RPC in BOTH `HostCapabilityRegistry.swift` and `HostCapabilityRegistry.kt`.
   - Guardrail 2: Zero silent error swallowing on live write RPCs in Swift `Store/` AND KMP `core-domain/`.
   - Guardrail 3: Resilient enum deserialization in Swift `Models/` AND KMP `core-model/`.
   - Guardrail 4: Three-way enum-downgrade parity across `HostCapabilityRegistry.swift` ↔ `HostCapabilityRegistry.kt` ↔ `scripts/mac-companion-bridge.py`.

---

## 3. Android Native Module Structure (`apps/android/`)

To maintain strict architectural boundaries while keeping Gradle configuration fast on CI:

```text
apps/android/
├── core-ui/         # Material 3 Expressive AntigravityTheme, 5-Tier Typography, SemanticIcon->Material Symbols,
│                    # Streaming Markdown Compose Renderer, Shared Cards, Status Pills, 48dp Geometry helpers
├── core-platform/   # AndroidSecretStore (Keystore + Tink AEAD + DataStore), AndroidNetworkMonitor (ConnectivityManager),
│                    # AndroidPowerStateProvider, AndroidPreferencesStore, AndroidProjectionStorage,
│                    # BiometricApprovalController, AndroidLiveUpdateBuilder (API 36 ProgressStyle + FGS fallback),
│                    # AndroidSharePayloadParser, CloudRelayCookieBridge
└── app/             # Application, AppGraph (pure Kotlin DI), MainActivity (edge-to-edge + deep links),
                     # Adaptive NavigationSuiteScaffold, Feature packages:
                     #   ui/home (UE01-UE03), ui/projects (UE05, UE14), ui/automations (UE06),
                     #   ui/chat (UE07-UE10 + v2.33 Overview/SideQuestion/Swarm/VoiceMode),
                     #   ui/review (UE11-UE12 + RichArtifactViewer), ui/pairing (Welcome/QR/CloudRelay/Settings),
                     #   ui/liveprogress (UE13 Live Updates Service, Receiver, BiometricTrampoline, Glance Widget, UE13 Spec Gallery)
                     # + Unit Tests, Interactive Compose E2E (ATC-01..ATC-18), Roborazzi 13-Screen Screenshot Suite, Emulator E2E
```

---

## 4. Verification & GitHub Actions CI (`ubuntu-latest` + KVM)

- **`.github/workflows/android-verify.yml`** runs on `ubuntu-latest`:
  - **Gate A0**: `verify_compat_guardrails.py` (Swift + KMP + Bridge) + `:apps:android:app:lintDebug`
  - **Gate A1 (Fast JVM)**: KMP JVM tests + Android unit tests + Interactive Compose E2E (`ATC-01`..`ATC-18`) + Roborazzi 13-Screen Screenshot verification (`verifyRoborazziDebug`) + `android_visual_compare.py` side-by-side sheet generation
  - **Gate A2 (KVM Emulator E2E on impacted/release)**: `reactivecircus/android-emulator-runner@v2` (`api-level: 36`, `arch: x86_64`) executing `connectedDebugAndroidTest`
- **`verification/e2e_impact_planner.py`** & **`scripts/verify.py`** gain an `android` lane so Android-only PRs skip macOS Xcode runners while full releases verify iOS + Android + KMP 100%.
