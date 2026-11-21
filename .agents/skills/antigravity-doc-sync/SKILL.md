---
name: antigravity-doc-sync
description: Automatically analyze Google Antigravity 2.0 official documentation/changelog updates, author structured PRD, Technical Design, and Test Plan specs under specs/deltas/<version>/, implement Tier 1/Tier 2 Swift 6 + Mock updates, and pass all ESDD & Xcode CI gates before opening a PR.
---

# Antigravity 2.0 Official Docs Auto-Sync Skill

Use this skill whenever `scripts/sync-antigravity-docs.py` detects a new Google Antigravity 2.0 release or feature guide delta.

## Mandatory 4-Stage Pipeline

### Stage 1 — Requirement Analysis (`specs/deltas/<version>/01-prd-gap-analysis.md`)
1. Read `delta-report.json` and `delta-summary.md`.
2. Filter out non-iOS noise (Windows/Linux installer fixes, Electron window quirks, CLI-only TUI keybindings).
3. Cross-check every remaining feature against:
   - `Packages/AntigravityData/Sources/AntigravityData/Protocol/AntigravityRPCClient.swift`
   - `Packages/AntigravityData/Sources/AntigravityData/Protocol/ProtobufStepDecoder.swift`
   - `Packages/AntigravityData/Sources/AntigravityData/Models/WorkspaceModels.swift`
   - `iOS/` view controllers & views.
4. Classify each gap strictly into one of 3 tiers:
   - **Tier 1 (Ready PR)**: Model catalog / thinking levels, slash commands, Markdown/frontmatter/UI enhancements, theme/layout settings, ESDD test & spec parity.
   - **Tier 2 (Draft PR + Protocol Probe Checklist)**: Features requiring new `exa.language_server_pb.LanguageServerService` RPCs or binary Protobuf step/interaction field numbers (never fabricate unverified upstream field numbers without marking them for live capture).
   - **Tier 3 (RFC Issue Only)**: Heavy native frameworks or backend infrastructure (e.g., WebRTC live audio, SwiftNIO SSH client, APNs relay server).

### Stage 2 — Technical Design (`specs/deltas/<version>/02-tech-design.md`)
- Respect all `AGENTS.md` invariants:
  - `Packages/AntigravityData` is pure Swift 6 and **NEVER** imports `UIKit`, `WebKit`, or `AVFoundation`.
  - All shared state models must conform to `Sendable`, `Equatable`, and `Codable` where persisted.
  - Preserve all 13 UE states, 13 transitions, 13 claims, 10 color tokens, and 5 typography tiers in `specs/esdd-ir.json`.
  - Gate live-only UI changes safely so `--ui-verify` deterministic UE screenshots remain 1:1 compliant.

### Stage 3 — Executable Test Plan (`specs/deltas/<version>/03-test-plan.md`)
- Define concrete acceptance test cases covering:
  - Pure Swift 6 `XCTest` cases in `Packages/AntigravityData/Tests/AntigravityDataTests/`
  - Mock Connect-RPC & Binary Protobuf flows in `verification/mock_language_server.py`, `scripts/mac-companion-bridge.py`, and `verification/verify-v233-capabilities.py`
  - Real Simulator UI assertions in `iOSUITests/AntigravityInteractiveUITests.swift`.

### Stage 4 — Synchronous Implementation & Verification Gates
1. Implement all approved items (within the configured `max_tier`).
2. Update `docs/upstream-snapshots/` via `python3 scripts/sync-antigravity-docs.py --apply`.
3. Run ALL local verification gates and confirm exit code `0`:
   ```bash
   python3 scripts/sync-antigravity-docs.py --self-test
   python3 verification/verify-live-rpc-flow.py
   python3 verification/verify-v233-capabilities.py
   python3 verification/esdd-verify.py
   ```
4. Open a Pull Request (Ready for Tier 1, Draft for Tier 2) so `.github/workflows/macos-xcode-verify.yml` runs real `macos-15` Swift 6 `swift test`, `XcodeGen`, `xcodebuild`, and iOS Simulator `XCUITest`. Never push directly to `main`.
