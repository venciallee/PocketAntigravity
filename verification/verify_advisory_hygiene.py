#!/usr/bin/env python3
"""Advisory Runtime & Cross-Boundary Hygiene Checks (`verify_advisory_hygiene.py`).

Non-blocking (warning-only by default; ALWAYS exits 0 unless `--strict` is explicitly passed).
Surfaces early warnings locally (`[WARN]`) and as GitHub Actions annotations (`::warning::`)
for four recurring physical-device / cross-boundary regression classes:

1. KMP / SKIE Exception Boundary Safety (`kmp-throws-and-coroutine-safety`):
   - Public `suspend fun` methods in Swift-facing KMP coordinator/stores/umbrella missing `@Throws(...)`
     (without `@Throws(Throwable::class)`, non-cancellation Kotlin exceptions abort iOS with SIGABRT).
   - `CoroutineScope(...)` created without `CoroutineExceptionHandler`, or unguarded `scope.launch`.
2. iOS Launch & Frame 0 Blocking Hygiene (`launch-frame0-hygiene`):
   - `project.yml` regressing `UILaunchScreen` back to `{}` (white flash) or dropping `ENABLE_DEBUG_DYLIB: NO`.
   - Synchronous Keychain XPC (`peekSavedHostLaunchHintSync` / `SecItemCopyMatching`) in
     `prepareFastLaunchSessionState()`, or synchronous `createDirectory` in `LocalProjectionStore.init`.
3. Cloud Relay Explicit Cookie Isolation (`cloud-relay-cookie-isolation`):
   - Ktor Darwin (`PlatformHttpClient.ios.kt`) or Swift `URLSession` (`AntigravityRPCClient.swift`)
     leaving automatic cookie storage enabled, which can clobber explicit `Cookie` + `SAPISIDHASH` headers.
4. Composer Live vs ESDD Parity & Disabled `/btw` Guard (`composer-ui-and-esdd-parity`):
   - Unconditional `if !store.isVerificationMode {` blocks in `ChatComposerView.swift` that hide
     persistent Live-mode controls from ESDD visual verification.
   - Re-introducing `"/btw"` into `SlashCommandItem` lists while `/btw` remains disabled.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


@dataclass
class AdvisoryWarning:
    check_id: str
    file: str
    line: int
    message: str


def _extract_brace_block(lines: list[str], start_idx: int) -> tuple[int, list[tuple[int, str]]]:
    """Extracts a brace-balanced block starting at `start_idx` (0-based). Returns (end_idx, [(1-based line, text)])."""
    depth = 0
    seen_open = False
    collected: list[tuple[int, str]] = []
    idx = start_idx
    while idx < len(lines):
        text = lines[idx]
        collected.append((idx + 1, text))
        opens = text.count("{")
        closes = text.count("}")
        if opens > 0:
            seen_open = True
        depth += opens - closes
        if seen_open and depth <= 0:
            break
        idx += 1
    return idx, collected


def _check_kmp_throws_and_coroutines(repo_root: Path) -> tuple[list[str], list[AdvisoryWarning]]:
    checks: list[str] = []
    warnings: list[AdvisoryWarning] = []

    domain_dir = repo_root / "shared" / "core-domain" / "src" / "commonMain" / "kotlin" / "dev" / "antigravity" / "shared" / "domain"
    umbrella_dir = repo_root / "shared" / "umbrella" / "src" / "commonMain"

    coordinator_files: list[Path] = []
    store_files: list[Path] = []
    if domain_dir.exists():
        coord = domain_dir / "AntigravityCoreCoordinator.kt"
        if coord.exists():
            coordinator_files.append(coord)
        for name in ("ConnectionDomainStore.kt", "ConversationSyncStore.kt", "CascadeChatDomainStore.kt"):
            p = domain_dir / name
            if p.exists():
                store_files.append(p)
    if umbrella_dir.exists():
        coordinator_files.extend(sorted(umbrella_dir.rglob("*.kt")))

    checked_suspend_count = 0
    suspend_re = re.compile(r"^\s*public\s+suspend\s+fun\s+([A-Za-z0-9_]+)\s*\(")

    def inspect_suspend_file(path: Path, require_expression_body: bool) -> None:
        nonlocal checked_suspend_count
        lines = path.read_text(encoding="utf-8").splitlines()
        rel = str(path.relative_to(repo_root))
        for idx, line in enumerate(lines):
            m = suspend_re.match(line)
            if not m:
                continue
            fn_name = m.group(1)
            if "advisory-ignore" in line:
                continue
            # For domain stores, skip one-line mutex expression getters (e.g. `= clientMutex.withLock { ... }`)
            if not require_expression_body and " = " in line and "{" not in line.split("=", 1)[0]:
                continue
            checked_suspend_count += 1
            lookback_start = max(0, idx - 4)
            preamble = "\n".join(lines[lookback_start : idx + 1])
            if "@Throws(" not in preamble and "advisory-ignore" not in preamble:
                warnings.append(
                    AdvisoryWarning(
                        check_id="kmp-throws-and-coroutine-safety",
                        file=rel,
                        line=idx + 1,
                        message=(
                            f"Public KMP suspend fun `{fn_name}` lacks `@Throws(Throwable::class)`; "
                            "non-cancellation Kotlin exceptions will abort iOS via SKIE/Kotlin-Native SIGABRT."
                        ),
                    )
                )

    for cf in coordinator_files:
        inspect_suspend_file(cf, require_expression_body=True)
    for sf in store_files:
        inspect_suspend_file(sf, require_expression_body=False)

    # Check CoroutineScope(...) & scope.launch in shared/core-domain/
    scope_count = 0
    launch_count = 0
    if domain_dir.exists():
        for kf in sorted(domain_dir.glob("*.kt")):
            lines = kf.read_text(encoding="utf-8").splitlines()
            rel = str(kf.relative_to(repo_root))
            for idx, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("*"):
                    continue
                if "CoroutineScope(" in line and "advisory-ignore" not in line:
                    scope_count += 1
                    window = "\n".join(lines[idx : min(len(lines), idx + 8)])
                    if "CoroutineExceptionHandler" not in window:
                        warnings.append(
                            AdvisoryWarning(
                                check_id="kmp-throws-and-coroutine-safety",
                                file=rel,
                                line=idx + 1,
                                message=(
                                    "CoroutineScope constructed without a `CoroutineExceptionHandler`; "
                                    "uncaught child coroutine failures can terminate Kotlin/Native."
                                ),
                            )
                        )
                if re.search(r"\bscope\.launch\b", line) and "advisory-ignore" not in line:
                    launch_count += 1
                    window = "\n".join(lines[idx : min(len(lines), idx + 8)])
                    if "try {" not in window and "runCatching" not in window:
                        warnings.append(
                            AdvisoryWarning(
                                check_id="kmp-throws-and-coroutine-safety",
                                file=rel,
                                line=idx + 1,
                                message=(
                                    "Background `scope.launch` lacks an immediate `try { ... }` guard "
                                    "(remember to catch `Throwable` and rethrow `CancellationException`)."
                                ),
                            )
                        )

    if not warnings:
        checks.append(
            f"KMP/SKIE exception boundary clean ({checked_suspend_count} suspend funs with @Throws, "
            f"{scope_count} CoroutineScope(s), {launch_count} guarded scope.launch call(s))"
        )
    return checks, warnings


def _check_launch_frame0_hygiene(repo_root: Path) -> tuple[list[str], list[AdvisoryWarning]]:
    checks: list[str] = []
    warnings: list[AdvisoryWarning] = []

    project_yml = repo_root / "project.yml"
    if project_yml.exists():
        lines = project_yml.read_text(encoding="utf-8").splitlines()
        full_text = "\n".join(lines)
        for idx, line in enumerate(lines):
            if re.match(r"^\s*UILaunchScreen:\s*\{\s*\}\s*$", line):
                warnings.append(
                    AdvisoryWarning(
                        check_id="launch-frame0-hygiene",
                        file="project.yml",
                        line=idx + 1,
                        message="Empty `UILaunchScreen: {}` causes a pure-white launch flash; set `UIColorName: LaunchBackground`.",
                    )
                )
        if "UIColorName:" not in full_text:
            warnings.append(
                AdvisoryWarning(
                    check_id="launch-frame0-hygiene",
                    file="project.yml",
                    line=1,
                    message="`project.yml` is missing `UILaunchScreen.UIColorName` (adaptive launch canvas color).",
                )
            )
        if not re.search(r"^\s*ENABLE_DEBUG_DYLIB:\s*NO\b", full_text, flags=re.MULTILINE):
            warnings.append(
                AdvisoryWarning(
                    check_id="launch-frame0-hygiene",
                    file="project.yml",
                    line=1,
                    message=(
                        "`project.yml` is missing `ENABLE_DEBUG_DYLIB: NO`, which can cause slow cold-start / "
                        "relaunch stalls on physical iPhones under Xcode 16/26."
                    ),
                )
            )

    conn_swift = (
        repo_root
        / "apps"
        / "ios"
        / "Packages"
        / "AntigravityData"
        / "Sources"
        / "AntigravityData"
        / "Store"
        / "AntigravitySessionStore+Connection.swift"
    )
    if conn_swift.exists():
        lines = conn_swift.read_text(encoding="utf-8").splitlines()
        rel = str(conn_swift.relative_to(repo_root))
        for idx, line in enumerate(lines):
            if "func prepareFastLaunchSessionState(" in line:
                _, block = _extract_brace_block(lines, idx)
                for lineno, btext in block:
                    stripped = btext.strip()
                    if stripped.startswith("//") or "advisory-ignore" in btext:
                        continue
                    if "peekSavedHostLaunchHintSync" in btext or "SecItemCopyMatching" in btext:
                        warnings.append(
                            AdvisoryWarning(
                                check_id="launch-frame0-hygiene",
                                file=rel,
                                line=lineno,
                                message=(
                                    "Synchronous Keychain XPC inside `prepareFastLaunchSessionState()` blocks Frame 0 launch; "
                                    "hydrate asynchronously in `hydrateSavedSessionFromDisk()` instead."
                                ),
                            )
                        )
                break

    proj_swift = (
        repo_root
        / "apps"
        / "ios"
        / "Packages"
        / "AntigravityData"
        / "Sources"
        / "AntigravityData"
        / "Store"
        / "LocalProjectionStore.swift"
    )
    if proj_swift.exists():
        lines = proj_swift.read_text(encoding="utf-8").splitlines()
        rel = str(proj_swift.relative_to(repo_root))
        for idx, line in enumerate(lines):
            if "public init(storageDirectory:" in line:
                _, block = _extract_brace_block(lines, idx)
                for lineno, btext in block:
                    stripped = btext.strip()
                    if stripped.startswith("//") or "advisory-ignore" in btext:
                        continue
                    if "createDirectory(" in btext:
                        warnings.append(
                            AdvisoryWarning(
                                check_id="launch-frame0-hygiene",
                                file=rel,
                                line=lineno,
                                message=(
                                    "Synchronous `createDirectory` inside `LocalProjectionStore.init()` blocks Frame 0 startup; "
                                    "create directories lazily on first actor-isolated write."
                                ),
                            )
                        )
                break

    if not warnings:
        checks.append("Launch & Frame 0 baseline clean (LaunchBackground, ENABLE_DEBUG_DYLIB=NO, zero sync Keychain/disk init)")
    return checks, warnings


def _check_cloud_relay_cookie_isolation(repo_root: Path) -> tuple[list[str], list[AdvisoryWarning]]:
    checks: list[str] = []
    warnings: list[AdvisoryWarning] = []

    ios_ktor = (
        repo_root
        / "shared"
        / "core-protocol"
        / "src"
        / "iosMain"
        / "kotlin"
        / "dev"
        / "antigravity"
        / "shared"
        / "protocol"
        / "PlatformHttpClient.ios.kt"
    )
    if ios_ktor.exists():
        text = ios_ktor.read_text(encoding="utf-8")
        if "HTTPShouldSetCookies = false" not in text or "HTTPCookieStorage = null" not in text:
            warnings.append(
                AdvisoryWarning(
                    check_id="cloud-relay-cookie-isolation",
                    file=str(ios_ktor.relative_to(repo_root)),
                    line=1,
                    message=(
                        "Ktor Darwin session should disable automatic cookies (`HTTPShouldSetCookies = false`, "
                        "`HTTPCookieStorage = null`) so system cookies cannot conflict with explicit `SAPISIDHASH` headers."
                    ),
                )
            )

    swift_rpc = (
        repo_root
        / "apps"
        / "ios"
        / "Packages"
        / "AntigravityData"
        / "Sources"
        / "AntigravityData"
        / "Protocol"
        / "AntigravityRPCClient.swift"
    )
    if swift_rpc.exists():
        text = swift_rpc.read_text(encoding="utf-8")
        if "httpShouldSetCookies = false" not in text or "httpCookieStorage = nil" not in text:
            warnings.append(
                AdvisoryWarning(
                    check_id="cloud-relay-cookie-isolation",
                    file=str(swift_rpc.relative_to(repo_root)),
                    line=1,
                    message=(
                        "Swift URLSession should disable automatic cookies (`httpShouldSetCookies = false`, "
                        "`httpCookieStorage = nil`) so explicit Cloud Relay `Cookie` headers are never overwritten."
                    ),
                )
            )

    if not warnings:
        checks.append("Cloud Relay explicit cookie isolation clean (Ktor Darwin & Swift URLSession automatic cookie storage disabled)")
    return checks, warnings


def _check_composer_ui_and_esdd_parity(repo_root: Path) -> tuple[list[str], list[AdvisoryWarning]]:
    checks: list[str] = []
    warnings: list[AdvisoryWarning] = []

    composer = repo_root / "apps" / "ios" / "App" / "Views" / "Composer" / "ChatComposerView.swift"
    if composer.exists():
        lines = composer.read_text(encoding="utf-8").splitlines()
        rel = str(composer.relative_to(repo_root))
        for idx, line in enumerate(lines):
            if "advisory-ignore" in line:
                continue
            # Flag unconditional `if !store.isVerificationMode {` layout strips that hide persistent UI from ESDD
            if re.match(r"^\s*if\s+!store\.isVerificationMode\s*\{\s*$", line):
                warnings.append(
                    AdvisoryWarning(
                        check_id="composer-ui-and-esdd-parity",
                        file=rel,
                        line=idx + 1,
                        message=(
                            "Unconditional `if !store.isVerificationMode {` block in `ChatComposerView` hides Live UI "
                            "from ESDD visual regression checks; keep composer chrome consistent across modes."
                        ),
                    )
                )

    slash_model_files = [
        repo_root / "apps" / "ios" / "Packages" / "AntigravityData" / "Sources" / "AntigravityData" / "Models" / "WorkspaceModels.swift",
        repo_root / "shared" / "core-model" / "src" / "commonMain" / "kotlin" / "dev" / "antigravity" / "shared" / "model" / "WorkspaceModels.kt",
    ]
    for mf in slash_model_files:
        if not mf.exists():
            continue
        lines = mf.read_text(encoding="utf-8").splitlines()
        rel = str(mf.relative_to(repo_root))
        for idx, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("*") or "advisory-ignore" in line or "feature-flag" in line.lower():
                continue
            if '"/btw"' in line:
                warnings.append(
                    AdvisoryWarning(
                        check_id="composer-ui-and-esdd-parity",
                        file=rel,
                        line=idx + 1,
                        message=(
                            "`/btw` slash command detected in command catalog while `/btw` is deferred; "
                            "gate behind a feature flag or add `feature-flag` comment when officially enabling."
                        ),
                    )
                )

    if not warnings:
        checks.append("Composer ESDD/Live parity & `/btw` deferral hygiene clean")
    return checks, warnings


def inspect_advisory_hygiene(repo_root: Path = ROOT) -> dict:
    checks: list[str] = []
    warnings: list[AdvisoryWarning] = []

    for fn in (
        _check_kmp_throws_and_coroutines,
        _check_launch_frame0_hygiene,
        _check_cloud_relay_cookie_isolation,
        _check_composer_ui_and_esdd_parity,
    ):
        c, w = fn(repo_root)
        checks.extend(c)
        warnings.extend(w)

    return {
        "advisory_only": True,
        "warning_count": len(warnings),
        "checks": checks,
        "warnings": [asdict(w) for w in warnings],
    }


def _run_self_test() -> int:
    # 1. Verify current repo runs cleanly and produces valid JSON shape.
    live_res = inspect_advisory_hygiene(ROOT)
    assert isinstance(live_res["warning_count"], int)
    assert live_res["advisory_only"] is True

    # 2. Verify synthetic regressions trigger all 4 advisory categories without crashing.
    with tempfile.TemporaryDirectory(prefix="ag-advisory-test-") as tmp:
        root = Path(tmp)
        coord = root / "shared/core-domain/src/commonMain/kotlin/dev/antigravity/shared/domain/AntigravityCoreCoordinator.kt"
        coord.parent.mkdir(parents=True, exist_ok=True)
        coord.write_text(
            "class AntigravityCoreCoordinator(\n"
            "    val scope: CoroutineScope = CoroutineScope(SupervisorJob())\n"
            ") {\n"
            "    public suspend fun riskyCall() {\n"
            "        scope.launch {\n"
            "            doWork()\n"
            "        }\n"
            "    }\n"
            "}\n",
            encoding="utf-8",
        )
        (root / "project.yml").write_text("targets:\n  Antigravity:\n    info:\n      properties:\n        UILaunchScreen: {}\n", encoding="utf-8")
        conn = root / "apps/ios/Packages/AntigravityData/Sources/AntigravityData/Store/AntigravitySessionStore+Connection.swift"
        conn.parent.mkdir(parents=True, exist_ok=True)
        conn.write_text(
            "func prepareFastLaunchSessionState() {\n"
            "    _ = KeychainStore.peekSavedHostLaunchHintSync()\n"
            "}\n",
            encoding="utf-8",
        )
        proj = root / "apps/ios/Packages/AntigravityData/Sources/AntigravityData/Store/LocalProjectionStore.swift"
        proj.write_text(
            "public init(storageDirectory: URL? = nil) {\n"
            "    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)\n"
            "}\n",
            encoding="utf-8",
        )
        ios_ktor = root / "shared/core-protocol/src/iosMain/kotlin/dev/antigravity/shared/protocol/PlatformHttpClient.ios.kt"
        ios_ktor.parent.mkdir(parents=True, exist_ok=True)
        ios_ktor.write_text("configureSession { timeoutIntervalForRequest = 15.0 }\n", encoding="utf-8")
        composer = root / "apps/ios/App/Views/Composer/ChatComposerView.swift"
        composer.parent.mkdir(parents=True, exist_ok=True)
        composer.write_text("if !store.isVerificationMode {\n    HStack {}\n}\n", encoding="utf-8")
        ws_model = root / "apps/ios/Packages/AntigravityData/Sources/AntigravityData/Models/WorkspaceModels.swift"
        ws_model.parent.mkdir(parents=True, exist_ok=True)
        ws_model.write_text('let cmd = "/btw"\n', encoding="utf-8")

        res = inspect_advisory_hygiene(root)
        ids = {w["check_id"] for w in res["warnings"]}
        expected = {
            "kmp-throws-and-coroutine-safety",
            "launch-frame0-hygiene",
            "cloud-relay-cookie-isolation",
            "composer-ui-and-esdd-parity",
        }
        assert expected.issubset(ids), f"Missing expected advisory IDs: {expected - ids}"
        assert res["warning_count"] >= 7, f"Expected >= 7 synthetic warnings, got {res['warning_count']}"

    print("verify_advisory_hygiene.py --self-test PASSED")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Non-blocking (warning-only) runtime & cross-boundary hygiene checks."
    )
    parser.add_argument("--json", action="store_true", help="Print JSON output.")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Opt-in strict mode: exit 1 if any advisory warnings are reported (default: always exit 0).",
    )
    parser.add_argument("--self-test", action="store_true", help="Run built-in self-tests and exit.")
    args = parser.parse_args(argv)

    if args.self_test:
        return _run_self_test()

    result = inspect_advisory_hygiene(ROOT)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print("=== Advisory Runtime & Cross-Boundary Hygiene Checks (Warning-Only) ===")
        for item in result["checks"]:
            print(f"  ✓ {item}")
        is_gha = os.environ.get("GITHUB_ACTIONS", "").lower() == "true"
        for w in result["warnings"]:
            print(f"  [WARN] [{w['check_id']}] {w['file']}:{w['line']} — {w['message']}")
            if is_gha:
                print(
                    f"::warning file={w['file']},line={w['line']},title=Advisory Hygiene ({w['check_id']})::{w['message']}"
                )
        if result["warning_count"] == 0:
            print("ADVISORY HYGIENE CHECKS CLEAN (0 warnings).")
        else:
            print(
                f"ADVISORY HYGIENE COMPLETED WITH {result['warning_count']} WARNING(S) "
                "(non-blocking; pass --strict to fail on warnings)."
            )

    if args.strict and result["warning_count"] > 0:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
