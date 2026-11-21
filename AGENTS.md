# iOSAntigravity Engineering & ESDD Guidelines (v2.0 UE Aligned)

1. **Architecture**:
   - `Packages/AntigravityData` is a pure Swift 6 package containing the Connect-RPC client (`exa.language_server_pb.LanguageServerService`), 5-byte streaming envelope parser (`ConnectEnvelope`), binary protobuf step decoder (`ProtobufStepDecoder`), local display projection (`LocalProjectionStore`), Durable Outbox, Keychain store, and central `AntigravitySessionStore`. It never imports `UIKit`.
   - `iOS/` owns all 13 native UE controllers & sheets: `AntigravityShellController` (Floating Liquid Glass 3-Tab Capsule + detached `#8EB4FF` Periwinkle FAB), `AgentsHomeViewController` (`UE01`), `DisplayOptionsSheetView` (`UE02`), `ConversationContextPreviewMenu` (`UE03`), `ProjectDetailViewController` (`UE04`), `CreateProjectSheetView` (`UE05`), `AutomationsViewController` (`UE06`), `CascadeChatViewController` + `ChatComposerView` (`UE07`), `AddContextSheetView` (`UE08`), `ModelAndModeSheetView` (`UE09`), `StructuredQuestionCardView` (`UE10`), `ImplementationPlanReviewViewController` (`UE11`), and `TurnDiffReviewViewController` (`UE12`).
   - `Shared/` & `Extensions/` own `AntigravityTheme` (`#090A0D` Matte Obsidian, `#8EB4FF` Periwinkle CTA, `#EBB365` Face ID Amber Approval), `AntigravityGlass`, `AntigravityActivityAttributes`, and `AntigravityLiveActivityWidget` (`UE13` 7-state Dynamic Island & Multi-Agent Lock Screen).

2. **ESDD (Executable Spec Driven Development) Verification**:
   - All 13 UE states (`UE01_AGENTS_HOME` .. `UE13_LIVE_ACTIVITY_SPEC`), 13 navigation transitions (`E01` .. `E13`), and 13 claims (`CLAIM-01` .. `CLAIM-13`) are declared in `specs/esdd-ir.json`, alongside 16 interactive E2E test cases (`TC-01` .. `TC-16`) in `specs/02-esdd-e2e-test-plan.md`.
   - Offline deterministic fixtures are registered in `iOS/Application/DebugSceneFactory.swift` and routable via `antigravity://verify/<case>` with `--ui-verify`.
   - Run `python3 verification/esdd-verify.py` to execute the full 4-gate E2E suite:
     1. Mechanical Spec-DAG & Swift 6 Source Contract completeness validation.
     2. Connect-RPC 5-byte envelope, >600-step Binary Protobuf, Face ID Interaction, Project, and Automation E2E tests against `verification/mock_language_server.py`.
     3. 16 Interactive E2E user-journey flows (`TC-01` .. `TC-16`) in headless `393×852pt @3x` viewport.
     4. Pixel-accurate `@3x` screenshot rendering, HIG geometry audit (`0px` horizontal overflow), and 1:1 Side-by-Side Reference UE vs Implemented comparison sheets (`verification/output/comparisons/CMP_UE01..CMP_UE13.png`).

3. **End-to-End Autonomous Delivery & macOS Xcode / iOS Simulator CI Verification (Mandatory for Every Development Task)**:
   - This repository is a **Swift 6 / iOS 18** native Xcode project (`project.yml`, `Packages/AntigravityData`, `iOS/`, `Shared/`, `Extensions/`, `iOSUITests/`). Remote Linux agent VMs do **not** have `swiftc`, `xcodebuild`, or the iOS Simulator installed.
   - **Never stop at local-only edits or Linux-only static/Python checks.** Unless the user explicitly requests a draft/no-merge workflow (e.g. "先别合" / "draft PR only"), every development task (bug fixes, features, refactors, config/rule updates) **MUST** automatically execute the complete closed-loop delivery pipeline without waiting for the user to ask:
     1. **Sync & Branch**: Fetch latest `origin/main` and branch cleanly off `origin/main` (e.g. `fix/<topic>`, `feat/<topic>`, or `chore/<topic>`). Never push directly to `main`.
     2. **Local Fast Verification**: Run local gates first (`python3 verification/esdd-verify.py`, `python3 verification/verify-live-rpc-flow.py`, `python3 verification/verify-v233-capabilities.py`, and `python3 verification/verify-compat-matrix.py`), and restore any unmodified regenerated artifacts under `verification/output/` before committing unless intentionally updated.
     3. **Auto Commit & Push**: Commit all verified changes with a clear conventional commit message and push the branch to `origin` (`git push -u origin <branch>`).
     4. **Auto Open PR (MR)**: Open a Pull Request targeting `main` (`gh pr create -R venciallee/iOSAntigravity --base main --head <branch> --title "..." --body "..."`), which automatically triggers `.github/workflows/macos-xcode-verify.yml` on **GitHub Actions `macos-15`**.
     5. **Watch All 5 macOS Gates to Completion**: Monitor the `macos-15` workflow run until completion — prefer low-frequency GraphQL status checks (every 45–60s) or `gh run watch -i 30` to avoid exhausting GitHub REST API rate limits — and verify **all 5 macOS gates** pass green:
        - `[Gate 0]` Script syntax, Doc-Sync watcher self-test, & static compatibility guardrails (`verify_compat_guardrails.py`).
        - `[Gate 1]` `swift test --package-path Packages/AntigravityData` (Swift 6 strict concurrency compilation & full `XCTest` suite).
        - `[Gate 2]` `python3 verification/verify-live-rpc-flow.py`, `python3 verification/verify-v233-capabilities.py`, & `python3 verification/verify-compat-matrix.py`.
        - `[Gate 3-5]` `python3 verification/ios-simulator-runner.py` (`xcodegen` + `xcodebuild` + real iOS Simulator `AntigravityUITests` + live Connect-RPC app handshake + 13 native simulator screenshots).
     6. **Automatic Failure Repair Loop**: If **any** macOS gate fails (Swift 6 compiler/type-check/concurrency error, `XCTest` failure, `xcodebuild` failure, real Simulator `XCUITest` failure, or merge conflict with `origin/main`), inspect the exact failure logs (`gh run view <run-id> -R venciallee/iOSAntigravity --log-failed`), fix the root cause (or merge latest `origin/main`), commit, push to the same PR branch, and re-run until **all gates pass 100% green**.
     7. **Auto Merge into `main`**: Once all CI checks are `SUCCESS` and the PR is `MERGEABLE`, automatically squash-merge the PR into `main` (`gh pr merge <pr-number> -R venciallee/iOSAntigravity --squash --delete-branch`), fast-forward local `main`, and report the merged PR link, `main` commit SHA, and green CI run link to the user.
     8. **Visual Screenshot Inspection (Optional)**: When verifying visual iOS rendering changes, you may also download the `real-ios-simulator-verification` workflow artifact (`gh run download <run-id> -n real-ios-simulator-verification`) to inspect real iOS Simulator screenshots directly.


4. **PR / MR Merge Conflict Auto-Detection & Resolution (Mandatory Before Handoff)**:
   - Whenever you create or update a Pull Request targeting `main`, you **MUST** verify the PR has zero merge conflicts **both immediately after creating/updating the PR AND again right after macOS CI completes** (since other PRs may merge into `main` while CI is running):
     1. Run `git fetch origin` and check `gh pr view <pr-number> -R venciallee/iOSAntigravity --json mergeable,mergeStateStatus` (re-check briefly if `mergeable` is still `"UNKNOWN"` while GitHub computes the merge preview).
     2. If `mergeable == "CONFLICTING"` or `mergeStateStatus == "DIRTY"` (or `origin/main` has new commits conflicting with the PR):
        - Automatically run `git merge origin/main`, resolve all conflicts cleanly (preserving both `origin/main` fixes and this PR's changes), commit, and push to the PR branch.
        - Re-run local fast verification (`esdd-verify.py` / `verify-live-rpc-flow.py` / `verify-compat-matrix.py`) and wait for the updated `macos-15` CI workflow run on the new merge commit to pass 100% green.
        - Re-check `gh pr view <pr-number> --json mergeable,mergeStateStatus` until `mergeable == "MERGEABLE"` and `mergeStateStatus` is `"CLEAN"` (or `"UNSTABLE"`/`"BLOCKED"` only if non-conflict policy applies — never `"DIRTY"`).
     3. Never hand off a PR to the user for merge while `mergeable == "CONFLICTING"` or `mergeStateStatus == "DIRTY"`.

5. **Automated Bidirectional Compatibility Guardrails (Mandatory for Every Feature Iteration)**:
   - Mobile ↔ Desktop compatibility (both newer mobile → older PC and newer PC → older mobile, with zero upstream Desktop changes) is mechanically enforced by `verification/verify_compat_guardrails.py` (Gate 0 & ESDD Stage 1) and `verification/verify-compat-matrix.py` (Gate 2):
     1. **Register every Connect-RPC method**: Whenever adding a new RPC call under `Packages/AntigravityData/Sources/AntigravityData/Protocol/`, register it in `HostCapabilityRegistry.swift` (`HostCapability.rpcMethods`, `coreBaselineMethods`, or `legacyAliasMethods`). Non-core RPCs automatically receive per-host negative caching on `404/501/unimplemented`.
     2. **Resilient forward-compatible enums**: Every `String`-backed `Codable` enum in `Packages/AntigravityData/Sources/AntigravityData/Models/` MUST conform to `ResilientStringEnum` (or implement a custom fallback `init(from:)`) so future PC enum values never throw `DecodingError`.
     3. **No silent `try?` fake successes on live writes**: Never wrap mutating RPC calls in `Store/*.swift` with silent `try?`; use `performLiveCapabilityWrite(...)` or explicit `do/catch` + `handleLiveCapabilityWriteError(...)` with state rollback on live backends (while preserving offline ESDD mode).
     4. **Keep Swift & Companion Bridge enum downgrades in sync**: Any new entry added to `ProtocolCompatibilityEngine.downgradedEnumReplacement` must also be added to `BRIDGE_ENUM_DOWNGRADES` in `scripts/mac-companion-bridge.py` (unmapped future enums automatically fall back to stripping the holding key).

