# iOSAntigravity Engineering & ESDD Guidelines (v2.0 UE Aligned)

1. **Architecture (KMP Monorepo)**:
   - `shared/` is the Kotlin Multiplatform shared core (`:shared:core-model`, `:shared:core-protocol`, `:shared:core-markdown`, `:shared:core-domain`, `:shared:umbrella`), providing Ktor (OkHttp/Darwin) Connect-RPC & Cloud Relay networking, 5-byte framing, Binary Protobuf decoding, `StateFlow` domain stores, and SKIE-exported `AntigravityShared.xcframework`.
   - `apps/ios/Packages/AntigravityData` is a pure Swift 6 package containing the `@Observable` `AntigravitySessionStore`, pure-Swift `AntigravityKmpEnginePort`, local display projection (`LocalProjectionStore`), Durable Outbox, Keychain store, and extension-safe Connect-RPC client. It never imports `UIKit` or `AntigravityShared` (keeping WidgetKit & Share extensions safely under 30MB).
   - `apps/ios/App/` owns all 13 native UE controllers & sheets plus the main-app SKIE bridge (`apps/ios/App/Bridge/`): `AntigravityShellController`, `AgentsHomeViewController` (`UE01`), `DisplayOptionsSheetView` (`UE02`), `ConversationContextPreviewMenu` (`UE03`), `ProjectDetailViewController` (`UE04`), `CreateProjectSheetView` (`UE05`), `AutomationsViewController` (`UE06`), `CascadeChatViewController` + `ChatComposerView` (`UE07`), `AddContextSheetView` (`UE08`), `ModelAndModeSheetView` (`UE09`), `StructuredQuestionCardView` (`UE10`), `ImplementationPlanReviewViewController` (`UE11`), and `TurnDiffReviewViewController` (`UE12`).
   - `apps/ios/SharedUI/` & `apps/ios/Extensions/` own iOS-only `AntigravityTheme` (`#090A0D` Matte Obsidian, `#8EB4FF` Periwinkle CTA, `#EBB365` Face ID Amber Approval), `AntigravityGlass`, `AntigravityActivityAttributes`, `AntigravityLiveActivityWidget` (`UE13`), and `AntigravityShare`.
   - `apps/android/` is reserved for the upcoming native Kotlin / Jetpack Compose Android client consuming `shared/`.
   - `tests/ios-ui/` owns the native XCUITest suite (`AntigravityUITests`).

2. **ESDD (Executable Spec Driven Development) Verification**:
   - All 13 UE states (`UE01_AGENTS_HOME` .. `UE13_LIVE_ACTIVITY_SPEC`), 13 navigation transitions (`E01` .. `E13`), and 13 claims (`CLAIM-01` .. `CLAIM-13`) are declared in `specs/esdd-ir.json`, alongside 16 interactive E2E test cases (`TC-01` .. `TC-16`) in `specs/02-esdd-e2e-test-plan.md`.
   - Offline deterministic fixtures are registered in `apps/ios/App/Application/DebugSceneFactory.swift` and routable via `antigravity://verify/<case>` with `--ui-verify`.
   - Run `python3 verification/esdd-verify.py` to execute the full 4-gate E2E suite:
     1. Mechanical Spec-DAG & Swift 6 Source Contract completeness validation.
     2. Connect-RPC 5-byte envelope, >600-step Binary Protobuf, Face ID Interaction, Project, and Automation E2E tests against `verification/mock_language_server.py`.
     3. 16 Interactive E2E user-journey flows (`TC-01` .. `TC-16`) in headless `393×852pt @3x` viewport.
     4. Pixel-accurate `@3x` screenshot rendering, HIG geometry audit (`0px` horizontal overflow), and 1:1 Side-by-Side Reference UE vs Implemented comparison sheets (`verification/output/comparisons/CMP_UE01..CMP_UE13.png`).

3. **End-to-End Autonomous Delivery & macOS Xcode / iOS Simulator CI Verification (Mandatory for Code/Config Changes)**:
   - This repository is a **KMP + Swift 6 / iOS 18** Monorepo (`project.yml`, `shared/`, `apps/ios/`, `apps/android/`, `tests/ios-ui/`). Remote Linux agent VMs do **not** have `swiftc`, `xcodebuild`, or the iOS Simulator installed.
   - Pure documentation changes (`**.md`, `docs/**`, `LICENSE`, `NOTICE`) automatically skip `macos-xcode-verify.yml` via `paths-ignore` to conserve macOS runner capacity.
   - **Never stop at local-only edits or Linux-only static/Python checks for code/config/build changes.** Unless the user explicitly requests a draft/no-merge workflow (e.g. "先别合" / "draft PR only"), every development task **MUST** automatically execute the complete closed-loop delivery pipeline without waiting for the user to ask:
     1. **Sync & Branch**: Fetch latest `origin/main` and branch cleanly off `origin/main` (e.g. `fix/<topic>`, `feat/<topic>`, or `chore/<topic>`). Never push directly to `main`.
     2. **Local Fast Verification**: Run local gates first (`python3 verification/esdd-verify.py`, `python3 verification/verify-live-rpc-flow.py`, `python3 verification/verify-v233-capabilities.py`, and `./gradlew :shared:core-model:jvmTest :shared:core-protocol:jvmTest :shared:core-markdown:jvmTest :shared:core-domain:jvmTest :shared:umbrella:jvmTest --no-daemon` when `shared/` is touched), and restore any unmodified regenerated artifacts under `verification/output/` before committing unless intentionally updated.
     3. **Auto Commit & Push**: Commit all verified changes with a clear conventional commit message and push the branch to `origin` (`git push -u origin <branch>`).
     4. **Auto Open PR (MR)**: Open a Pull Request targeting `main` (`gh pr create -R venciallee/iOSAntigravity --base main --head <branch> --title "..." --body "..."`), which triggers `.github/workflows/macos-xcode-verify.yml` (and `.github/workflows/kmp-verify.yml` when `shared/**` changes).
     5. **Watch All macOS & KMP Gates to Completion**: Monitor the workflow run(s) until completion — prefer low-frequency checks (`gh run watch -i 45`) to avoid exhausting GitHub REST API rate limits — and verify **all triggered gates** pass green:
        - `[Gate 0]` Script syntax & Doc-Sync watcher self-test.
        - `[Gate 1]` `swift test --package-path apps/ios/Packages/AntigravityData` (Swift 6 strict concurrency compilation & full `XCTest` suite).
        - `[Gate 2]` `python3 verification/verify-live-rpc-flow.py` & `python3 verification/verify-v233-capabilities.py`.
        - `[Gate 2.5]` `./gradlew :shared:umbrella:assembleAntigravitySharedDebugXCFramework --no-daemon`.
        - `[Gate 3-5]` `python3 verification/ios-simulator-runner.py` (`xcodegen` + `xcodebuild` + real iOS Simulator `AntigravityUITests` + live Connect-RPC app handshake + 13 native simulator screenshots).
     6. **Automatic Failure Repair Loop**: If **any** macOS or KMP gate fails (Kotlin/Native, SKIE, Swift 6 compiler/type-check/concurrency error, `XCTest` failure, `xcodebuild` failure, real Simulator `XCUITest` failure, or merge conflict with `origin/main`), inspect the exact failure logs (`gh run view <run-id> -R venciallee/iOSAntigravity --log-failed`), fix the root cause (or merge latest `origin/main`), commit, push to the same PR branch, and re-run until **all gates pass 100% green**.
     7. **Auto Merge into `main`**: Once all CI checks are `SUCCESS` and the PR is `MERGEABLE`, automatically squash-merge the PR into `main` (`gh pr merge <pr-number> -R venciallee/iOSAntigravity --squash --delete-branch`), fast-forward local `main`, and report the merged PR link, `main` commit SHA, and green CI run link to the user.
     8. **Visual Screenshot Inspection (Optional)**: When verifying visual iOS rendering changes, you may also download the `real-ios-simulator-verification` workflow artifact (`gh run download <run-id> -n real-ios-simulator-verification`) to inspect real iOS Simulator screenshots directly.


4. **PR / MR Merge Conflict Auto-Detection & Resolution (Mandatory Before Handoff)**:
   - Whenever you create or update a Pull Request targeting `main`, you **MUST** verify the PR has zero merge conflicts **both immediately after creating/updating the PR AND again right after macOS CI completes** (since other PRs may merge into `main` while CI is running):
     1. Run `git fetch origin` and check `gh pr view <pr-number> -R venciallee/iOSAntigravity --json mergeable,mergeStateStatus` (re-check briefly if `mergeable` is still `"UNKNOWN"` while GitHub computes the merge preview).
     2. If `mergeable == "CONFLICTING"` or `mergeStateStatus == "DIRTY"` (or `origin/main` has new commits conflicting with the PR):
        - Automatically run `git merge origin/main`, resolve all conflicts cleanly (preserving both `origin/main` fixes and this PR's changes), commit, and push to the PR branch.
        - Re-run local fast verification (`esdd-verify.py` / `verify-live-rpc-flow.py`) and wait for the updated `macos-15` CI workflow run on the new merge commit to pass 100% green.
        - Re-check `gh pr view <pr-number> --json mergeable,mergeStateStatus` until `mergeable == "MERGEABLE"` and `mergeStateStatus` is `"CLEAN"` (or `"UNSTABLE"`/`"BLOCKED"` only if non-conflict policy applies — never `"DIRTY"`).
     3. Never hand off a PR to the user for merge while `mergeable == "CONFLICTING"` or `mergeStateStatus == "DIRTY"`.
