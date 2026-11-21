# Client Code Review Rules — iOS / Swift 6 / UIKit / Extensions

You are reviewing Swift 6 / iOS 18 client changes. Report ONLY concrete, reachable defects introduced by this PR.

## Mandatory Defect Checks

### `CLI-IOS-001` — Swift 6 Concurrency, Actor Reentrancy & Sendable Integrity (`P0`/`P1`)
- Flag `@unchecked Sendable` or `nonisolated(unsafe)` guarding mutable state without a lock (`OSAllocatedUnfairLock`, `NSLock`, or serial queue).
- Flag actor methods that mutate state before and after an `await` suspension point where reentrancy can overwrite newer state or duplicate side effects.
- Flag `Task.detached` capturing mutable UI/store references without isolation boundaries.

### `CLI-IOS-002` — Main-Thread Safety & UI Blocking (`P0`/`P1`)
- Flag UIKit / SwiftUI state updates invoked off `@MainActor`.
- Flag synchronous disk I/O, large JSON/Protobuf parsing, `DispatchSemaphore.wait()`, or blocking locks on `@MainActor`.

### `CLI-IOS-003` — Retain Cycles & Lifecycle Leaks (`P1`)
- Flag escaping closures, `Timer`, `NotificationCenter`, Combine `AnyCancellable`, or long-lived `Task` / `AsyncStream` loops strongly capturing `self` (ViewController, Coordinator, ViewModel, or Store) without `[weak self]` or cancellation on teardown (`deinit` / `viewDidDisappear`).

### `CLI-IOS-004` — Production Crash Hazards (`P0`/`P1`)
- Exclude unit/UI test targets (`Tests/`, `iOSUITests/`).
- Flag force unwraps (`!`), `try!`, `as!`, unchecked array subscripting, or reachable `fatalError()` on network, user, deeplink, or persisted data.

### `CLI-IOS-005` — App Extension Memory & Sandbox Limits (`P0`)
- Under `Extensions/` (`LiveActivity`, `Share`) and `Shared/LiveActivity/`:
  - Flag un-downsampled image decoding, unbounded cache/history loading, or heavy allocations risking the 24–64 MB iOS extension memory ceiling.
  - Flag APIs unavailable in extensions (`UIApplication.shared`, background network assumptions without background session).

### `CLI-IOS-006` — Bidirectional Protocol & Storage Compatibility (`P1`)
- New `String`-backed `Codable` enums in `Packages/AntigravityData/Sources/AntigravityData/Models/` must conform to `ResilientStringEnum` or implement a resilient `init(from:)` fallback.
- New Connect-RPC methods in `Protocol/` must be registered in `HostCapabilityRegistry.swift`.
- Local persistence / projection schema changes must handle older on-disk files gracefully without crashing or wiping state.

### `CLI-IOS-007` — Silent `try?` Swallowing Live Write RPCs (`P1`)
- Under `Packages/AntigravityData/Sources/AntigravityData/Store/`, flag `try? await` on mutating RPC calls that silently leave optimistic local state diverged from the host; require `performLiveCapabilityWrite(...)` or explicit rollback error handling.

### `CLI-IOS-008` — Presentation Races & Accessibility Regressions (`P2`)
- Flag dismissing a sheet/alert and immediately presenting another without waiting for the dismiss completion callback.
- Flag interactive controls missing `accessibilityLabel` or fixed-height text containers that clip under Dynamic Type.

## Do-Not-Report List (Strict Noise Suppression)
Do NOT report:
- Style, formatting, naming preferences, or comment nitpicks without a defect.
- Pre-existing issues in untouched code merely moved or re-indented by this PR.
- Speculative "future breakage" without a concrete caller/input/failure path.
- Missing tests alone, unless a high-risk defect path is demonstrably broken.
- Micro-optimizations without demonstrated hot-path cost.
- Diff summaries, praise, or restating compiler/linter errors already caught by CI.
