#!/usr/bin/env python3
"""Unified Agent-First & Human-Friendly Verification CLI (`scripts/verify.py`).

Single stateless entrypoint that replaces juggling 5+ disparate scripts and `cd` commands:
  - Works from any working directory (zero `cd`, zero placeholder arguments).
  - Auto-detects host OS & toolchains (Python, Java/Gradle, Swift 6, Xcode/Simulator).
  - Quiet by default (1 line per gate + actionable failure tail); `--json` emits clean
    machine-readable output for coding agents.
  - Preserves a clean git working tree by auto-restoring regenerated `verification/output/`
    artifacts after `esdd` (unless `--keep-artifacts` is passed).

Examples:
  ./scripts/verify.py                     # Fast default gates: spec + rpc + v233 + compat (~7s)
  ./scripts/verify.py --auto              # Impact-scoped ESDD + fast gates (skips unaffected browser TCs)
  ./scripts/verify.py --full              # All available gates: fast + full esdd + kmp + swift + android
  ./scripts/verify.py --json              # Machine-readable JSON report for agents
  ./scripts/verify.py --suite rpc,compat  # Run specific suite(s) only
  ./scripts/verify.py --suite swift       # Run Swift 6 XCTest (stateless `--package-path`)
  ./scripts/verify.py --suite android     # Run Android Roborazzi + JVM tests + iOS visual comparison
  ./scripts/verify.py --suite bridge      # Verify against a running Mac Companion Bridge
  ./scripts/verify.py --list              # Show suites & detected toolchains
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Callable, Optional

REPO_ROOT = Path(__file__).resolve().parent.parent
VERIFICATION_DIR = REPO_ROOT / "verification"
SCRIPTS_DIR = REPO_ROOT / "scripts"

FAST_SUITES = ["spec", "rpc", "v233", "compat"]
AUTO_SUITES = ["spec", "rpc", "v233", "compat", "esdd"]
FULL_SUITES = ["spec", "rpc", "v233", "compat", "esdd", "kmp", "swift", "android"]
ALL_SUITES = ["spec", "rpc", "v233", "compat", "esdd", "kmp", "swift", "android", "bridge", "sim"]

KMP_JVM_TASKS = [
    ":shared:core-model:jvmTest",
    ":shared:core-protocol:jvmTest",
    ":shared:core-markdown:jvmTest",
    ":shared:core-domain:jvmTest",
    ":shared:umbrella:jvmTest",
]

ANDROID_GRADLE_TASKS = [
    ":apps:android:app:recordRoborazziDebug",
    ":apps:android:app:testDebugUnitTest",
]

PY_COMPILE_FILES = [
    "scripts/verify.py",
    "scripts/sync-antigravity-docs.py",
    "scripts/run-doc-sync-agent.py",
    "scripts/mac-companion-bridge.py",
    "verification/mock_language_server.py",
    "verification/verify-live-rpc-flow.py",
    "verification/verify-v233-capabilities.py",
    "verification/verify_compat_guardrails.py",
    "verification/verify_advisory_hygiene.py",
    "verification/verify-compat-matrix.py",
    "verification/e2e_impact_planner.py",
    "verification/watchos-simulator-runner.py",
    "verification/verify_watch_esdd.py",
    "verification/android_visual_compare.py",
    "verification/esdd_inspector.py",
]

# Noisy HTTP access log lines emitted by local mock servers during normal operation
NOISE_LINE_PATTERNS = (
    re.compile(r"^\[Bridge\]\s+127\.0\.0\.1\s+-\s+\"POST\s+/exa\.language_server_pb\."),
    re.compile(r"^127\.0\.0\.1\s+-\s+-\s+\[.*?\]\s+\"(?:GET|POST)\s+"),
)


@dataclass
class GateResult:
    name: str
    status: str  # "passed" | "failed" | "skipped"
    duration_ms: int
    command: str
    summary: str = ""
    reason: Optional[str] = None
    tail_log: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class SuiteSpec:
    name: str
    description: str
    in_fast: bool
    in_full: bool
    requires: tuple[str, ...] = ()


SUITE_SPECS: dict[str, SuiteSpec] = {
    "spec": SuiteSpec(
        name="spec",
        description="Python syntax check + ESDD Spec-DAG, Swift 6 isolation, App Store 5.2.2 & zero-secret hygiene",
        in_fast=True,
        in_full=True,
    ),
    "rpc": SuiteSpec(
        name="rpc",
        description="Self-contained Connect-RPC E2E (Auth 401->200, StartCascade, SendMessage, Face ID, 5B stream, >600 Protobuf)",
        in_fast=True,
        in_full=True,
    ),
    "v233": SuiteSpec(
        name="v233",
        description="Antigravity 2.0 (v2.33–v3.0) capabilities, Cloud Relay, VCS helpers & Doc-Sync self-test",
        in_fast=True,
        in_full=True,
    ),
    "compat": SuiteSpec(
        name="compat",
        description="4-layer bidirectional compatibility static guardrails + 3-version matrix (Legacy v2.31 / Current / Future v2.99)",
        in_fast=True,
        in_full=True,
    ),
    "esdd": SuiteSpec(
        name="esdd",
        description="Full 4-gate ESDD suite (16 Chromium CDP interactive journeys + 13 @3x visual comparisons)",
        in_fast=False,
        in_full=True,
        requires=("chromium",),
    ),
    "kmp": SuiteSpec(
        name="kmp",
        description="Kotlin Multiplatform shared core JVM & Mock LanguageServer E2E tests (Gradle)",
        in_fast=False,
        in_full=True,
        requires=("java",),
    ),
    "swift": SuiteSpec(
        name="swift",
        description="Swift 6 strict-concurrency build & XCTest suite (apps/ios/Packages/AntigravityData)",
        in_fast=False,
        in_full=True,
        requires=("swift",),
    ),
    "android": SuiteSpec(
        name="android",
        description="Android Compose unit/E2E tests + Roborazzi 13-screen capture & iOS visual comparison",
        in_fast=False,
        in_full=True,
        requires=("java", "android"),
    ),
    "bridge": SuiteSpec(
        name="bridge",
        description="Verify live Connect-RPC against a running Mac Companion Bridge (uses env or --bridge-url/--bridge-csrf)",
        in_fast=False,
        in_full=False,
    ),
    "sim": SuiteSpec(
        name="sim",
        description="macOS XcodeGen + xcodebuild + real iOS Simulator AGPocketUITests + 13 native screenshots",
        in_fast=False,
        in_full=False,
        requires=("macos", "xcodebuild", "xcodegen"),
    ),
}


def detect_toolchains() -> dict[str, bool]:
    is_macos = platform.system() == "Darwin"
    has_chromium = any(
        shutil.which(bin_name) is not None
        for bin_name in ("google-chrome", "chromium", "chromium-browser")
    ) or (
        is_macos
        and Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome").exists()
    )
    has_java = shutil.which("java") is not None and (REPO_ROOT / "gradlew").exists()
    android_sdk_env = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT") or ""
    has_android_sdk = bool(android_sdk_env) and Path(android_sdk_env).is_dir()
    if not has_android_sdk:
        local_props = REPO_ROOT / "local.properties"
        if local_props.exists():
            for raw_line in local_props.read_text(encoding="utf-8", errors="ignore").splitlines():
                line = raw_line.strip()
                if line.startswith("sdk.dir="):
                    sdk_val = line.split("=", 1)[1].strip().replace("\\:", ":").replace("\\\\", "\\")
                    if sdk_val and Path(sdk_val).is_dir():
                        has_android_sdk = True
                        break
    has_swift = shutil.which("swift") is not None
    has_xcodebuild = is_macos and shutil.which("xcodebuild") is not None
    has_xcodegen = is_macos and shutil.which("xcodegen") is not None
    return {
        "macos": is_macos,
        "python3": True,
        "chromium": has_chromium,
        "java": has_java,
        "android": has_android_sdk,
        "swift": has_swift,
        "xcodebuild": has_xcodebuild,
        "xcodegen": has_xcodegen,
    }


def missing_requirements(suite: str, toolchains: dict[str, bool]) -> list[str]:
    spec = SUITE_SPECS[suite]
    return [req for req in spec.requires if not toolchains.get(req, False)]


def filter_noise_lines(output: str, keep_noise: bool = False) -> list[str]:
    lines = [line.rstrip() for line in output.splitlines() if line.strip()]
    if keep_noise:
        return lines
    filtered = [
        line
        for line in lines
        if not any(pattern.search(line) for pattern in NOISE_LINE_PATTERNS)
    ]
    return filtered or lines


def run_subprocess(
    cmd: list[str],
    *,
    env: Optional[dict[str, str]] = None,
    timeout: int = 900,
) -> tuple[int, str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    proc = subprocess.run(
        cmd,
        cwd=str(REPO_ROOT),
        env=merged_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    return proc.returncode, proc.stdout or ""


def git_status_verification_output() -> Optional[str]:
    if not (REPO_ROOT / ".git").exists() or shutil.which("git") is None:
        return None
    rc, out = run_subprocess(["git", "status", "--porcelain", "--", "verification/output"])
    return out.strip() if rc == 0 else None


def restore_verification_output() -> bool:
    if not (REPO_ROOT / ".git").exists() or shutil.which("git") is None:
        return False
    rc1, _ = run_subprocess(["git", "checkout", "--", "verification/output"])
    rc2, _ = run_subprocess(["git", "clean", "-fd", "--", "verification/output"])
    return rc1 == 0 and rc2 == 0


def run_spec_gate(args: argparse.Namespace) -> GateResult:
    t0 = time.monotonic()
    py_files = [str(REPO_ROOT / rel) for rel in PY_COMPILE_FILES if (REPO_ROOT / rel).exists()]
    cmd_display = "py_compile + esdd_inspector.inspect_esdd_spec_and_swift_contracts"

    rc, out = run_subprocess([sys.executable, "-m", "py_compile", *py_files])
    if rc != 0:
        return GateResult(
            name="spec",
            status="failed",
            duration_ms=int((time.monotonic() - t0) * 1000),
            command=f"python3 -m py_compile {' '.join(PY_COMPILE_FILES)}",
            summary="Python syntax check failed",
            tail_log=filter_noise_lines(out)[-args.tail_lines :],
        )

    inspect_code = (
        "import json; from pathlib import Path; "
        "from esdd_inspector import inspect_esdd_spec_and_swift_contracts; "
        "res = inspect_esdd_spec_and_swift_contracts(Path('.')); "
        "print(json.dumps(res))"
    )
    rc, out = run_subprocess(
        [sys.executable, "-W", "ignore", "-c", inspect_code],
        env={"PYTHONPATH": str(VERIFICATION_DIR)},
    )
    duration_ms = int((time.monotonic() - t0) * 1000)
    if rc != 0:
        return GateResult(
            name="spec",
            status="failed",
            duration_ms=duration_ms,
            command=cmd_display,
            summary="ESDD spec inspector crashed",
            tail_log=filter_noise_lines(out)[-args.tail_lines :],
        )

    try:
        payload = json.loads(out.strip().splitlines()[-1])
    except Exception:
        return GateResult(
            name="spec",
            status="failed",
            duration_ms=duration_ms,
            command=cmd_display,
            summary="Unable to parse esdd_inspector JSON output",
            tail_log=filter_noise_lines(out)[-args.tail_lines :],
        )

    if not payload.get("passed"):
        errors = payload.get("errors") or ["Unknown ESDD spec violation"]
        return GateResult(
            name="spec",
            status="failed",
            duration_ms=duration_ms,
            command=cmd_display,
            summary=f"{len(errors)} spec/contract error(s)",
            tail_log=[str(e) for e in errors[-args.tail_lines :]],
        )

    planner_path = VERIFICATION_DIR / "e2e_impact_planner.py"
    if planner_path.exists():
        rc, planner_out = run_subprocess([sys.executable, str(planner_path), "--self-test"])
        if rc != 0:
            return GateResult(
                name="spec",
                status="failed",
                duration_ms=int((time.monotonic() - t0) * 1000),
                command="python3 verification/e2e_impact_planner.py --self-test",
                summary="e2e_impact_planner --self-test failed",
                tail_log=filter_noise_lines(planner_out)[-args.tail_lines :],
            )

    watch_esdd_path = VERIFICATION_DIR / "verify_watch_esdd.py"
    if watch_esdd_path.exists():
        w_rc, w_out = run_subprocess([sys.executable, str(watch_esdd_path), "--stage1-only"])
        if w_rc != 0:
            return GateResult(
                name="spec",
                status="failed",
                duration_ms=int((time.monotonic() - t0) * 1000),
                command="python3 verification/verify_watch_esdd.py --stage1-only",
                summary="Watch ESDD Stage W1 contract audit failed",
                tail_log=filter_noise_lines(w_out)[-args.tail_lines :],
            )

    advisory_warnings: list[str] = []
    advisory_path = VERIFICATION_DIR / "verify_advisory_hygiene.py"
    if advisory_path.exists():
        adv_rc, adv_out = run_subprocess([sys.executable, str(advisory_path), "--json"])
        if adv_rc == 0 and adv_out.strip():
            try:
                adv_payload = json.loads(adv_out)
                for w in adv_payload.get("warnings", []):
                    advisory_warnings.append(
                        f"[WARN] [{w.get('check_id', 'advisory')}] {w.get('file', '?')}:{w.get('line', 1)} — {w.get('message', '')}"
                    )
            except Exception:
                pass

    duration_ms = int((time.monotonic() - t0) * 1000)
    adv_suffix = f", {len(advisory_warnings)} advisory warning(s)" if advisory_warnings else ", 0 advisory warnings"
    summary = (
        f"py_compile ({len(py_files)} files) + impact-planner + "
        f"{payload.get('stateCount', 0)} states, "
        f"{payload.get('claimCount', 0)} claims, "
        f"{payload.get('selectorCount', 0)} selectors, "
        f"{payload.get('swiftFileCount', 0)} Swift files, 0 secret hits{adv_suffix}"
    )
    tail = (payload.get("checks", []) if args.verbose else []) + advisory_warnings
    return GateResult(
        name="spec",
        status="passed",
        duration_ms=duration_ms,
        command=cmd_display,
        summary=summary,
        tail_log=tail,
    )


def run_command_gate(
    name: str,
    cmd: list[str],
    args: argparse.Namespace,
    *,
    success_summary: Callable[[list[str]], str],
    timeout: int = 900,
) -> GateResult:
    t0 = time.monotonic()
    cmd_str = " ".join(cmd)
    try:
        rc, out = run_subprocess(cmd, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        duration_ms = int((time.monotonic() - t0) * 1000)
        partial = exc.stdout if isinstance(exc.stdout, str) else ""
        return GateResult(
            name=name,
            status="failed",
            duration_ms=duration_ms,
            command=cmd_str,
            summary=f"Timed out after {timeout}s",
            tail_log=filter_noise_lines(partial)[-args.tail_lines :],
        )

    duration_ms = int((time.monotonic() - t0) * 1000)
    cleaned = filter_noise_lines(out, keep_noise=args.verbose)
    if rc != 0:
        return GateResult(
            name=name,
            status="failed",
            duration_ms=duration_ms,
            command=cmd_str,
            summary=f"Exited with code {rc}",
            tail_log=cleaned[-args.tail_lines :],
        )

    return GateResult(
        name=name,
        status="passed",
        duration_ms=duration_ms,
        command=cmd_str,
        summary=success_summary(cleaned),
        tail_log=cleaned if args.verbose else [],
    )


def run_suite(
    suite: str,
    args: argparse.Namespace,
    toolchains: dict[str, bool],
) -> tuple[GateResult, bool]:
    """Run a single verification suite. Returns (GateResult, git_artifacts_restored)."""
    missing = missing_requirements(suite, toolchains)
    if missing:
        reason = f"missing required toolchain/environment: {', '.join(missing)}"
        return (
            GateResult(
                name=suite,
                status="skipped",
                duration_ms=0,
                command="",
                summary=f"Skipped ({reason})",
                reason=reason,
            ),
            False,
        )

    if suite == "spec":
        return run_spec_gate(args), False

    if suite == "rpc":
        res = run_command_gate(
            "rpc",
            [sys.executable, "verification/verify-live-rpc-flow.py"],
            args,
            success_summary=lambda lines: (
                f"{sum(1 for l in lines if '[PASS]' in l)} live Connect-RPC checks passed"
            ),
        )
        return res, False

    if suite == "v233":
        res = run_command_gate(
            "v233",
            [sys.executable, "verification/verify-v233-capabilities.py"],
            args,
            success_summary=lambda lines: "v2.33–v3.0 capabilities, Cloud Relay & Doc-Sync passed",
        )
        return res, False

    if suite == "compat":
        res = run_command_gate(
            "compat",
            [sys.executable, "verification/verify-compat-matrix.py"],
            args,
            success_summary=lambda lines: "4-layer compat guardrails + 3-version matrix (Legacy/Current/Future) passed",
        )
        return res, False

    if suite == "esdd":
        pre_dirty = git_status_verification_output()
        esdd_flag = "--auto" if getattr(args, "auto", False) else "--full"
        res = run_command_gate(
            "esdd",
            [sys.executable, "verification/esdd-verify.py", esdd_flag],
            args,
            success_summary=lambda lines: (
                f"ESDD ({esdd_flag.lstrip('-')}) passed: "
                f"{sum(1 for l in lines if '[TC-' in l)} interactive TCs + "
                f"{sum(1 for l in lines if '[CLAIM-' in l)} @3x visual claims"
            ),
        )
        restored = False
        # Only auto-restore if verification/output/ was clean beforehand and user didn't ask to keep artifacts
        if not args.keep_artifacts and pre_dirty == "":
            post_dirty = git_status_verification_output()
            if post_dirty:
                restored = restore_verification_output()
        return res, restored

    if suite == "kmp":
        gradlew = str(REPO_ROOT / "gradlew")
        res = run_command_gate(
            "kmp",
            [gradlew, *KMP_JVM_TASKS, "--no-daemon", "--console=plain"],
            args,
            success_summary=lambda lines: f"KMP Gradle JVM tests passed ({len(KMP_JVM_TASKS)} modules)",
            timeout=1200,
        )
        return res, False

    if suite == "swift":
        res = run_command_gate(
            "swift",
            ["swift", "test", "--package-path", "apps/ios/Packages/AntigravityData"],
            args,
            success_summary=lambda lines: next(
                (l for l in reversed(lines) if "Executed " in l or "Test run" in l),
                "Swift 6 AntigravityData XCTest passed",
            ),
            timeout=1200,
        )
        return res, False

    if suite == "android":
        pre_dirty = git_status_verification_output()
        gradlew = str(REPO_ROOT / "gradlew")
        gradle_res = run_command_gate(
            "android",
            [gradlew, *ANDROID_GRADLE_TASKS, "--no-daemon", "--console=plain"],
            args,
            success_summary=lambda lines: "Android Roborazzi capture & JVM unit/Compose E2E tests passed",
            timeout=1800,
        )
        if gradle_res.status != "passed":
            return gradle_res, False

        compare_res = run_command_gate(
            "android",
            [sys.executable, "verification/android_visual_compare.py"],
            args,
            success_summary=lambda lines: "Android Compose unit/E2E tests + Roborazzi 13-screen visual comparison passed",
            timeout=300,
        )
        restored = False
        if not args.keep_artifacts and pre_dirty == "":
            post_dirty = git_status_verification_output()
            if post_dirty:
                restored = restore_verification_output()

        combined_duration_ms = gradle_res.duration_ms + compare_res.duration_ms
        combined_cmd = f"{gradle_res.command} && {compare_res.command}"
        if compare_res.status != "passed":
            return (
                GateResult(
                    name="android",
                    status="failed",
                    duration_ms=combined_duration_ms,
                    command=combined_cmd,
                    summary=f"Visual comparison failed ({compare_res.summary})",
                    reason=compare_res.reason,
                    tail_log=compare_res.tail_log,
                ),
                restored,
            )

        combined_tail = (gradle_res.tail_log + compare_res.tail_log) if args.verbose else []
        return (
            GateResult(
                name="android",
                status="passed",
                duration_ms=combined_duration_ms,
                command=combined_cmd,
                summary=compare_res.summary,
                tail_log=combined_tail,
            ),
            restored,
        )

    if suite == "bridge":
        url = args.bridge_url or os.environ.get("ANTIGRAVITY_BACKEND_URL") or "http://127.0.0.1:8787"
        csrf = args.bridge_csrf or os.environ.get("ANTIGRAVITY_CSRF_TOKEN") or ""
        if not csrf:
            return (
                GateResult(
                    name="bridge",
                    status="failed",
                    duration_ms=0,
                    command="python3 verification/verify-live-rpc-flow.py --url <url> --csrf <token>",
                    summary="Missing CSRF token for live bridge verification",
                    reason="Pass --bridge-csrf <token> or set ANTIGRAVITY_CSRF_TOKEN",
                ),
                False,
            )
        res = run_command_gate(
            "bridge",
            [
                sys.executable,
                "verification/verify-live-rpc-flow.py",
                "--url",
                url,
                "--csrf",
                csrf,
            ],
            args,
            success_summary=lambda lines: f"Live bridge ({url}) Connect-RPC checks passed",
        )
        return res, False

    if suite == "sim":
        res = run_command_gate(
            "sim",
            [sys.executable, "verification/ios-simulator-runner.py"],
            args,
            success_summary=lambda lines: "Real iOS Simulator XCUITest + 13 screenshots passed",
            timeout=1800,
        )
        return res, False

    raise ValueError(f"Unknown suite: {suite}")


def resolve_suites(args: argparse.Namespace) -> tuple[str, list[str]]:
    if args.suite:
        selected: list[str] = []
        for raw in args.suite:
            for item in raw.split(","):
                name = item.strip().lower()
                if not name:
                    continue
                if name not in SUITE_SPECS:
                    raise ValueError(
                        f"Unknown suite '{name}'. Valid choices: {', '.join(ALL_SUITES)}"
                    )
                if name not in selected:
                    selected.append(name)
        if not selected:
            raise ValueError("No valid suites specified via --suite")
        return "custom", selected
    if args.auto:
        return "auto", list(AUTO_SUITES)
    if args.full:
        return "full", list(FULL_SUITES)
    return "fast", list(FAST_SUITES)


def format_duration(ms: int) -> str:
    if ms < 1000:
        return f"{ms}ms"
    return f"{ms / 1000:.2f}s"


def print_list(toolchains: dict[str, bool], as_json: bool) -> int:
    rows = []
    for name in ALL_SUITES:
        spec = SUITE_SPECS[name]
        missing = missing_requirements(name, toolchains)
        rows.append(
            {
                "name": spec.name,
                "description": spec.description,
                "in_fast": spec.in_fast,
                "in_full": spec.in_full,
                "available": len(missing) == 0,
                "missing_requirements": missing,
            }
        )
    if as_json:
        print(
            json.dumps(
                {
                    "platform": platform.system(),
                    "toolchains": toolchains,
                    "suites": rows,
                },
                indent=2,
            )
        )
        return 0

    print(f"Platform: {platform.system()} ({platform.machine()})")
    avail = ", ".join(k for k, v in toolchains.items() if v)
    print(f"Detected toolchains: {avail}\n")
    for row in rows:
        tags = []
        if row["in_fast"]:
            tags.append("fast")
        if row["in_full"]:
            tags.append("full")
        if not tags:
            tags.append("opt-in")
        status = "ready" if row["available"] else f"skip ({', '.join(row['missing_requirements'])})"
        print(f"  {row['name']:<8} [{','.join(tags):<9}] [{status:<22}] {row['description']}")
    return 0


def run_self_test() -> int:
    # Deterministic sanity checks for CI Gate 0
    toolchains = detect_toolchains()
    assert toolchains["python3"] is True
    assert "android" in toolchains
    assert "android" not in FAST_SUITES and "android" in ALL_SUITES and "android" in SUITE_SPECS
    noise = (
        '[Bridge] 127.0.0.1 - "POST /exa.language_server_pb.LanguageServerService/StartCascade HTTP/1.1" 200 -\n'
        "  [PASS] 1. Auth verified\n"
    )
    cleaned = filter_noise_lines(noise)
    assert len(cleaned) == 1 and "[PASS]" in cleaned[0], f"Unexpected noise filter output: {cleaned}"

    parser = build_parser()
    ns_fast = parser.parse_args([])
    assert resolve_suites(ns_fast) == ("fast", FAST_SUITES)
    ns_auto = parser.parse_args(["--auto"])
    assert resolve_suites(ns_auto) == ("auto", AUTO_SUITES)
    ns_full = parser.parse_args(["--full"])
    assert resolve_suites(ns_full) == ("full", FULL_SUITES)
    ns_custom = parser.parse_args(["--suite", "rpc,spec", "--suite", "kmp"])
    assert resolve_suites(ns_custom) == ("custom", ["rpc", "spec", "kmp"])
    ns_android = parser.parse_args(["--suite", "android"])
    assert resolve_suites(ns_android) == ("custom", ["android"])
    print("verify.py --self-test PASSED")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="scripts/verify.py",
        description="Unified Agent-First & Human-Friendly Verification CLI for PocketAntigravity.",
    )
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--fast",
        action="store_true",
        help=f"Run fast default gates ({' + '.join(FAST_SUITES)}; default when no flags given).",
    )
    mode_group.add_argument(
        "--auto",
        action="store_true",
        help="Run fast gates plus impact-scoped ESDD (`esdd-verify.py --auto`).",
    )
    mode_group.add_argument(
        "--full",
        action="store_true",
        help=f"Run all available gates ({' + '.join(FULL_SUITES)}).",
    )
    parser.add_argument(
        "--suite",
        action="append",
        metavar="NAMES",
        help=f"Run specific suite(s), comma-separated or repeated. Choices: {', '.join(ALL_SUITES)}.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit a single machine-readable JSON report to stdout (agent-friendly).",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail (exit 1) if any selected gate is skipped due to missing toolchains.",
    )
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Stop immediately on the first failing gate.",
    )
    parser.add_argument(
        "--keep-artifacts",
        action="store_true",
        help="Keep regenerated verification/output/ files after running `esdd`.",
    )
    parser.add_argument(
        "--tail-lines",
        type=int,
        default=40,
        help="Max non-noise log lines to include on gate failure (default: 40).",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Include full command logs for passing gates too.",
    )
    parser.add_argument(
        "--bridge-url",
        default=None,
        help="Override Companion Bridge URL for `--suite bridge` (or set ANTIGRAVITY_BACKEND_URL).",
    )
    parser.add_argument(
        "--bridge-csrf",
        default=None,
        help="CSRF token for `--suite bridge` (or set ANTIGRAVITY_CSRF_TOKEN).",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List all verification suites and detected local toolchains, then exit.",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Run internal CLI self-tests and exit.",
    )
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.self_test:
        return run_self_test()

    toolchains = detect_toolchains()
    if args.list:
        return print_list(toolchains, as_json=args.json)

    try:
        mode, suites = resolve_suites(args)
    except ValueError as exc:
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc)}, indent=2))
        else:
            print(f"Error: {exc}", file=sys.stderr)
        return 2

    started = time.monotonic()
    results: list[GateResult] = []
    any_restored = False

    if not args.json:
        print(
            f"[verify] mode={mode} platform={platform.system()} suites={','.join(suites)}"
        )

    for suite in suites:
        result, restored = run_suite(suite, args, toolchains)
        any_restored = any_restored or restored
        results.append(result)

        if not args.json:
            badge = {
                "passed": "PASS",
                "failed": "FAIL",
                "skipped": "SKIP",
            }[result.status]
            print(
                f"  [{badge}] {result.name:<7} ({format_duration(result.duration_ms):>7})  {result.summary}"
            )
            if result.status == "failed":
                if result.command:
                    print(f"         cmd: {result.command}")
                if result.reason:
                    print(f"         hint: {result.reason}")
                for line in result.tail_log:
                    print(f"         | {line}")
            elif args.verbose and result.tail_log:
                for line in result.tail_log:
                    print(f"         | {line}")
            elif result.tail_log:
                for line in result.tail_log:
                    if line.startswith("[WARN]"):
                        print(f"         | {line}")

        if result.status == "failed" and args.fail_fast:
            break

    total_ms = int((time.monotonic() - started) * 1000)
    passed_count = sum(1 for r in results if r.status == "passed")
    failed_gates = [r.name for r in results if r.status == "failed"]
    skipped_gates = [r.name for r in results if r.status == "skipped"]
    ok = len(failed_gates) == 0 and (not args.strict or len(skipped_gates) == 0)

    report = {
        "ok": ok,
        "mode": mode,
        "platform": platform.system(),
        "repo_root": str(REPO_ROOT),
        "duration_ms": total_ms,
        "strict": args.strict,
        "git_artifacts_restored": any_restored,
        "summary": {
            "passed": passed_count,
            "failed": len(failed_gates),
            "skipped": len(skipped_gates),
        },
        "failed_gates": failed_gates,
        "skipped_gates": skipped_gates,
        "gates": [asdict(r) for r in results],
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        status_word = "PASSED" if ok else "FAILED"
        extra = " (verification/output/ auto-restored)" if any_restored else ""
        print(
            f"[verify] {status_word} in {format_duration(total_ms)} "
            f"(passed={passed_count}, failed={len(failed_gates)}, skipped={len(skipped_gates)}){extra}"
        )

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
