# Client Code Review Rules — KMP / Kotlin / Android / Swift Bridge

You are reviewing Kotlin Multiplatform (`shared/`), Swift-KMP bridge (`iOS/Bridge/`), or Android (`android/`) changes. Report ONLY concrete, reachable defects introduced by this PR.

## KMP & Cross-Platform Bridge Rules (`CLI-KMP-*`)

### `CLI-KMP-001` — Cross-Platform Flow / Coroutine Cancellation & Threading (`P1`)
- Flag Kotlin `StateFlow` / `Flow` / `suspend` functions bridged to Swift (via SKIE / ObjC) without proper cancellation lifecycle binding (`Task` cancellation or closeable subscription handle).
- Flag mismatched threading assumptions across Ktor Darwin / JVM / Swift `@MainActor`.

### `CLI-KMP-002` — Swift <-> Kotlin <-> Companion Bridge Contract Parity (`P1`)
- Flag protocol DTO, enum raw value, RPC method name, or enum-downgrade map changes made on one side (`shared/core-model`, `shared/core-protocol`, `Packages/AntigravityData`, `scripts/mac-companion-bridge.py`) without updating its mirror counterpart.

### `CLI-KMP-003` — Exception Boundary & `commonMain` Purity (`P1`)
- Flag Kotlin `suspend` or throwing functions exposed to Swift without `@Throws` where Swift expects structured errors (uncaught Kotlin exceptions terminate the iOS process).
- Flag platform-specific types or blocking calls leaking into `commonMain`.

### `CLI-KMP-004` — Umbrella Export & Binary Size Bloat (`P2`)
- Flag unnecessary `export(...)` additions in `shared/umbrella/build.gradle.kts` that expose internal transitive dependencies into `AntigravityShared.xcframework`.

## Android / Kotlin Rules (`CLI-AND-*`)

### `CLI-AND-001` — Coroutine Scope Leaks & Swallowed `CancellationException` (`P0`/`P1`)
- Flag `GlobalScope.launch` / `GlobalScope.async` in production code.
- Flag broad `catch (e: Exception)` or `catch (t: Throwable)` inside `suspend` blocks that fail to rethrow `CancellationException`.

### `CLI-AND-002` — Main Thread Blocking & ANR Hazards (`P0`/`P1`)
- Flag `runBlocking` on UI/main threads, synchronous `SharedPreferences.commit()`, or disk/network I/O on `Dispatchers.Main`.

### `CLI-AND-003` — Context Leaks & Flow Lifecycle Collection (`P1`)
- Flag static/singleton references to `Activity` or `View` `Context`.
- Flag UI `Flow` collection without `repeatOnLifecycle` / `collectAsStateWithLifecycle`.

### `CLI-AND-004` — Jetpack Compose Side Effects & Hot-Path Recomposition (`P1`/`P2`)
- Flag side effects (network/storage writes) executed directly inside Composable body instead of `LaunchedEffect` / `SideEffect`.

### `CLI-AND-005` — Process Death & Binder Limits (`P1`)
- Flag large lists/payloads put into `Bundle` / `Intent` (`TransactionTooLargeException`) or critical flow state missing `SavedStateHandle`.

### `CLI-AND-006` — Background Restrictions & Resource Leaks (`P1`)
- Flag Android 12+ background foreground-service launches without exception handling, or unclosed `Cursor` / `WakeLock` / streams outside `use {}` / `finally`.

### `CLI-AND-007` — R8 / ProGuard Obfuscation Safety (`P1`)
- Flag new reflection/JNI/Gson/Moshi serialized models missing `@Keep` or consumer ProGuard keep rules.

## Do-Not-Report List
Omit pure style/naming nitpicks, pre-existing untouched code, speculative issues without concrete failure paths, and praise/summaries.
