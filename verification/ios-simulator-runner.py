#!/usr/bin/env python3
"""macOS Xcode + iPhone Simulator Native E2E Runner (`ios-simulator-runner.py`).

Supports both:
  - **Impact-Scoped Mode (`--plan <e2e-plan.json>` / `--mode auto|scoped|build-only`)**:
    Runs only the impacted Xcode build, targeted XCUITest methods (`-only-testing:...`),
    live Connect-RPC handshake (when RPC/connection changed), and impacted native Simulator
    UE screenshots (`UE01`..`UE13`), skipping unaffected cases and avoiding Simulator boot
    entirely in `build-only` mode.
  - **Full / Release Mode (`--mode full|release`, or default when invoked without scope flags)**:
    Assembles KMP `AntigravityShared.xcframework` if absent, compiles `Antigravity.app`
    (+ extensions + `AntigravityUITests`), runs ALL 5 modular XCUITests, verifies Live
    Connect-RPC App Handshake, and captures ALL 13 native SwiftUI screens (`UE01`..`UE13`)
    + composite overview board.

Performance optimization:
  When the Simulator is needed, `xcrun simctl boot <udid>` starts asynchronously in the
  background *before* `xcodebuild build-for-testing` / `build`, overlapping Simulator cold
  boot with Swift 6 compilation, and only awaits `simctl bootstatus -b` right before running
  `test-without-building` / app launch.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import platform
import secrets
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any


PREFERRED_IPHONES = [
    "iPhone 16 Pro",
    "iPhone 16",
    "iPhone 15 Pro",
    "iPhone 15",
]

UITEST_TARGET_CLASS = "AntigravityUITests/AntigravityInteractiveUITests"


def select_iphone_simulator() -> tuple[str, str, str]:
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True
    )
    devices = json.loads(raw)["devices"]
    runtimes = [r for r in sorted(devices.keys(), reverse=True) if "iOS" in r]

    for preferred in PREFERRED_IPHONES:
        for runtime in runtimes:
            for dev in devices[runtime]:
                if dev.get("isAvailable") and dev.get("name") == preferred:
                    return dev["udid"], dev["name"], runtime

    for runtime in runtimes:
        for dev in devices[runtime]:
            name = dev.get("name", "")
            if dev.get("isAvailable") and "iPhone" in name and "SE" not in name:
                return dev["udid"], name, runtime

    for runtime in runtimes:
        for dev in devices[runtime]:
            if dev.get("isAvailable") and "iPhone" in dev.get("name", ""):
                return dev["udid"], dev["name"], runtime

    raise RuntimeError("No available iPhone Simulator found in Xcode.")


def build_overview_sheet(out_dir: Path, state_ids: list[str], device_label: str, is_full: bool) -> None:
    if not state_ids:
        return
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("[!] Pillow not installed; skipping composite overview generation.", flush=True)
        return

    cols = min(4, max(1, len(state_ids)))
    rows = (len(state_ids) + cols - 1) // cols
    thumb_w, thumb_h = 360, 780
    pad_x, pad_y = 32, 72
    header_h = 110
    canvas_w = pad_x + cols * (thumb_w + pad_x)
    canvas_h = header_h + pad_y + rows * (thumb_h + pad_y)

    board = Image.new("RGB", (canvas_w, canvas_h), (9, 10, 13))
    draw = ImageDraw.Draw(board)
    title_scope = "All 13 Native SwiftUI Captures" if is_full else f"Impact-Scoped Captures ({len(state_ids)} screen(s))"
    draw.text(
        (pad_x, 28),
        f"iOSAntigravity — Real Xcode iOS Simulator {title_scope} ({device_label})",
        fill=(245, 247, 250),
    )
    draw.text(
        (pad_x, 60),
        f"Compiled via xcodebuild (-swift-version 6) & captured via `xcrun simctl io screenshot` ({', '.join(state_ids)})",
        fill=(142, 180, 255),
    )

    for idx, sid in enumerate(state_ids):
        p = out_dir / f"{sid}.png"
        if not p.exists():
            continue
        r = idx // cols
        c = idx % cols
        x = pad_x + c * (thumb_w + pad_x)
        y = header_h + r * (thumb_h + pad_y)
        img = Image.open(p).convert("RGB")
        img.thumbnail((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        ox = x + (thumb_w - img.width) // 2
        oy = y + 28
        draw.text((x, y), sid, fill=(213, 216, 226))
        board.paste(img, (ox, oy))

    filename = "REAL_SIMULATOR_13_SCREENS_OVERVIEW.png" if is_full else "REAL_SIMULATOR_SCOPED_SCREENS_OVERVIEW.png"
    overview_path = out_dir / filename
    board.save(overview_path, format="PNG")
    print(f"  [OVERVIEW] {overview_path}", flush=True)


def _stream_command(cmd: list[str], cwd: Path, log_path: Path) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8") as log_fp:
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        assert proc.stdout is not None
        for line in proc.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            log_fp.write(line)
        ret = proc.wait()
        if ret != 0:
            raise subprocess.CalledProcessError(ret, cmd)


def _resolve_execution_config(args: argparse.Namespace, repo_root: Path, all_state_ids: list[str]) -> dict[str, Any]:
    sys.path.insert(0, str(repo_root / "verification"))
    import e2e_impact_planner as planner

    plan: dict[str, Any] | None = None
    if args.plan:
        plan = json.loads(Path(args.plan).read_text(encoding="utf-8"))
    elif args.mode == "auto":
        cmd = [sys.executable, str(repo_root / "verification" / "e2e_impact_planner.py"), "--quiet", "--plan-out", str(repo_root / "verification" / "output" / "e2e-plan.json")]
        if args.base:
            cmd.extend(["--base", args.base])
        if args.head:
            cmd.extend(["--head", args.head])
        subprocess.run(cmd, cwd=repo_root, check=True)
        plan = json.loads((repo_root / "verification" / "output" / "e2e-plan.json").read_text(encoding="utf-8"))

    if plan is not None:
        gates = plan["gates"]
        sim_mode = gates["iosSimulatorMode"]
        xcuitests = list(plan.get("xcuitests", []))
        screens = list(plan.get("simulatorScreens", []))
        run_live_rpc = bool(gates.get("runLiveAppRPC", False))
        is_release = bool(plan.get("isRelease", False))
        mode = plan.get("mode", "scoped")
    else:
        mode = args.mode or "full"
        is_release = mode == "release"
        if mode == "skip":
            sim_mode = "skip"
            xcuitests = []
            screens = []
            run_live_rpc = False
        elif mode == "build-only":
            sim_mode = "build-only"
            xcuitests = []
            screens = []
            run_live_rpc = False
        else:
            sim_mode = "full" if mode in ("full", "release") else "scoped"
            xcuitests = list(planner.ALL_XCUITESTS)
            screens = list(all_state_ids)
            run_live_rpc = True

    # CLI overrides
    if args.only_testing is not None:
        raw_tests = [t.strip() for chunk in args.only_testing for t in chunk.split(",") if t.strip()]
        if raw_tests == ["none"]:
            xcuitests = []
        elif raw_tests == ["all"]:
            xcuitests = list(planner.ALL_XCUITESTS)
        else:
            xcuitests = raw_tests

    if args.screens is not None:
        s_val = args.screens.strip()
        if s_val.lower() == "none":
            screens = []
        elif s_val.lower() == "all":
            screens = list(all_state_ids)
        else:
            screens = [s.strip() for s in s_val.split(",") if s.strip()]

    if args.skip_live_rpc:
        run_live_rpc = False
    elif args.run_live_rpc:
        run_live_rpc = True

    if sim_mode != "skip" and not xcuitests and not run_live_rpc and not screens:
        sim_mode = "build-only"

    all_tests_selected = set(xcuitests) >= set(planner.ALL_XCUITESTS)
    all_screens_selected = set(screens) >= set(all_state_ids)

    return {
        "mode": mode,
        "isRelease": is_release,
        "simMode": sim_mode,
        "xcuitests": xcuitests,
        "skippedXcuitests": [t for t in planner.ALL_XCUITESTS if t not in xcuitests],
        "allTestsSelected": all_tests_selected,
        "runLiveAppRPC": run_live_rpc,
        "screens": screens,
        "skippedScreens": [s for s in all_state_ids if s not in screens],
        "allScreensSelected": all_screens_selected,
    }


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(line_buffering=True)

    parser = argparse.ArgumentParser(description="macOS Xcode & iOS Simulator Native E2E Runner")
    parser.add_argument("--plan", default=None, help="Path to JSON plan generated by e2e_impact_planner.py")
    parser.add_argument(
        "--mode",
        choices=["auto", "full", "release", "scoped", "build-only", "skip"],
        default=None,
        help="Execution mode (defaults to 'full' when neither --plan nor --mode is specified)",
    )
    parser.add_argument("--release", action="store_true", help="Shorthand for --mode release (mandatory 100% full E2E)")
    parser.add_argument("--only-testing", action="append", default=None, help="Comma-separated XCUITest method name(s), 'all', or 'none'")
    parser.add_argument("--screens", default=None, help="Comma-separated UE state IDs, 'all', or 'none'")
    parser.add_argument("--skip-live-rpc", action="store_true", help="Skip Step 4 Live Connect-RPC App Handshake")
    parser.add_argument("--run-live-rpc", action="store_true", help="Force Step 4 Live Connect-RPC App Handshake")
    parser.add_argument("--base", default=None, help="Git base ref when using --mode auto")
    parser.add_argument("--head", default=None, help="Git head ref when using --mode auto")
    args = parser.parse_args()

    if args.release:
        args.mode = "release"

    repo_root = Path(__file__).resolve().parents[1]
    ir = json.loads((repo_root / "specs" / "esdd-ir.json").read_text(encoding="utf-8"))
    all_state_ids = [s["id"] for s in ir["states"]]
    cfg = _resolve_execution_config(args, repo_root, all_state_ids)

    if platform.system() != "Darwin":
        print("Note: macOS / xcrun not detected; delegating to cross-platform esdd-verify.py", flush=True)
        esdd_cmd = [sys.executable, str(repo_root / "verification" / "esdd-verify.py")]
        if args.plan:
            esdd_cmd.extend(["--plan", args.plan])
        elif cfg["isRelease"]:
            esdd_cmd.append("--release")
        subprocess.run(esdd_cmd, check=True)
        return

    t_start = time.monotonic()
    timings: dict[str, float] = {}
    out_dir = repo_root / "verification" / "output" / "real-simulator"
    out_dir.mkdir(parents=True, exist_ok=True)

    print(
        f"=== iOS Simulator Runner Plan: mode={cfg['mode']} | simMode={cfg['simMode']} | "
        f"isRelease={cfg['isRelease']} | XCUITests={len(cfg['xcuitests'])}/5 | "
        f"LiveAppRPC={cfg['runLiveAppRPC']} | Screens={len(cfg['screens'])}/13 ===",
        flush=True,
    )

    if cfg["simMode"] == "skip":
        manifest = {
            "mode": cfg["mode"],
            "simMode": "skip",
            "isRelease": cfg["isRelease"],
            "skipped": True,
            "executedUITests": [],
            "skippedUITests": cfg["skippedXcuitests"],
            "ranLiveConnectRPC": False,
            "capturedStates": [],
            "skippedStates": cfg["skippedScreens"],
            "timingsSec": {"total": round(time.monotonic() - t_start, 2)},
        }
        (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print("  [SKIP] No iOS/Xcode build or simulator verification required for this change set.", flush=True)
        return

    xcf_path = repo_root / "shared" / "umbrella" / "build" / "XCFrameworks" / "debug" / "AntigravityShared.xcframework"
    if not xcf_path.exists():
        t_xcf = time.monotonic()
        print("=== [0/5] Building KMP AntigravityShared.xcframework via Gradle ===", flush=True)
        subprocess.run(
            ["./gradlew", ":shared:umbrella:assembleAntigravitySharedDebugXCFramework", "--no-daemon"],
            cwd=repo_root,
            check=True,
        )
        timings["kmpXcframework"] = round(time.monotonic() - t_xcf, 2)

    t0 = time.monotonic()
    print("=== [1/5] Generating Xcode Project via XcodeGen ===", flush=True)
    subprocess.run(["xcodegen", "generate"], cwd=repo_root, check=True)
    timings["xcodegen"] = round(time.monotonic() - t0, 2)

    derived = repo_root / ".build" / "DerivedData"

    # Fast path: build-only (compiles Antigravity.app + Extensions for iOS Simulator WITHOUT booting Simulator!)
    if cfg["simMode"] == "build-only":
        t_build = time.monotonic()
        host_arch = platform.machine() or "arm64"
        print(
            f"=== [2/5] Build-Only Mode: Compiling Antigravity.app for generic iOS Simulator ({host_arch}) — skipping Simulator boot ===",
            flush=True,
        )
        build_cmd = [
            "xcodebuild",
            "build",
            "-project",
            "iOSAntigravity.xcodeproj",
            "-scheme",
            "Antigravity",
            "-sdk",
            "iphonesimulator",
            "-destination",
            "generic/platform=iOS Simulator",
            "-derivedDataPath",
            str(derived),
            f"ARCHS={host_arch}",
            "ONLY_ACTIVE_ARCH=YES",
            "CODE_SIGN_IDENTITY=-",
            "CODE_SIGNING_REQUIRED=NO",
            "AD_HOC_CODE_SIGNING_ALLOWED=YES",
        ]
        _stream_command(build_cmd, repo_root, out_dir / "xcodebuild-only.log")
        timings["xcodeBuild"] = round(time.monotonic() - t_build, 2)
        timings["total"] = round(time.monotonic() - t_start, 2)
        manifest = {
            "mode": cfg["mode"],
            "simMode": "build-only",
            "isRelease": cfg["isRelease"],
            "buildSucceeded": True,
            "executedUITests": [],
            "skippedUITests": cfg["skippedXcuitests"],
            "ranLiveConnectRPC": False,
            "capturedStates": [],
            "skippedStates": cfg["skippedScreens"],
            "timingsSec": timings,
        }
        (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print(
            f"\n[PASS] Build-only Swift 6 iOS Simulator compilation succeeded in {timings['total']}s (Simulator boot & unaffected E2E skipped).",
            flush=True,
        )
        return

    # Simulator-backed path (`scoped` or `full` or `release`)
    udid, sim_name, sim_runtime = select_iphone_simulator()
    print(
        f"=== [2/5] Starting Async Simulator Boot ({sim_name} · {sim_runtime}, UDID={udid}) in Parallel with Xcode Build ===",
        flush=True,
    )
    boot_proc = subprocess.Popen(
        ["xcrun", "simctl", "boot", udid],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    t_build = time.monotonic()
    has_xcuitests = len(cfg["xcuitests"]) > 0
    xcode_action = "build-for-testing" if has_xcuitests else "build"
    print(
        f"=== [3a/5] Running `xcodebuild {xcode_action}` for {sim_name} (overlapping with Simulator boot) ===",
        flush=True,
    )
    build_cmd = [
        "xcodebuild",
        xcode_action,
        "-project",
        "iOSAntigravity.xcodeproj",
        "-scheme",
        "Antigravity",
        "-sdk",
        "iphonesimulator",
        "-destination",
        f"id={udid}",
        "-derivedDataPath",
        str(derived),
        "CODE_SIGN_IDENTITY=-",
        "CODE_SIGNING_REQUIRED=NO",
        "AD_HOC_CODE_SIGNING_ALLOWED=YES",
    ]
    _stream_command(build_cmd, repo_root, out_dir / "xcodebuild.log")
    timings["xcodeBuild"] = round(time.monotonic() - t_build, 2)

    t_boot_wait = time.monotonic()
    print(f"=== [3b/5] Waiting for Simulator Boot Completion ({sim_name}) ===", flush=True)
    boot_proc.wait()
    subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)
    subprocess.run(
        [
            "xcrun",
            "simctl",
            "status_bar",
            udid,
            "override",
            "--time",
            "9:41",
            "--batteryState",
            "charged",
            "--batteryLevel",
            "100",
            "--wifiBars",
            "3",
            "--cellularMode",
            "active",
            "--cellularBars",
            "4",
        ],
        check=False,
    )
    timings["simBootWaitAfterBuild"] = round(time.monotonic() - t_boot_wait, 2)

    # Step 3c: Run selected XCUITests (or skip if none impacted)
    if has_xcuitests:
        t_uitest = time.monotonic()
        xcresult_path = out_dir / "AntigravityUITests.xcresult"
        shutil.rmtree(xcresult_path, ignore_errors=True)
        if cfg["allTestsSelected"]:
            only_testing_flags = ["-only-testing:AntigravityUITests"]
            test_desc = f"ALL {len(cfg['xcuitests'])} XCUITest cases"
        else:
            only_testing_flags = [
                f"-only-testing:{UITEST_TARGET_CLASS}/{method}" for method in cfg["xcuitests"]
            ]
            test_desc = f"{len(cfg['xcuitests'])}/5 scoped XCUITest case(s): {', '.join(cfg['xcuitests'])}"

        print(f"=== [3c/5] Running Real XCUITest Suite ({test_desc}) on {sim_name} ===", flush=True)
        uitest_cmd = [
            "xcodebuild",
            "test-without-building",
            "-project",
            "iOSAntigravity.xcodeproj",
            "-scheme",
            "Antigravity",
            "-sdk",
            "iphonesimulator",
            "-destination",
            f"id={udid}",
            "-derivedDataPath",
            str(derived),
            *only_testing_flags,
            "-resultBundlePath",
            str(xcresult_path),
            "CODE_SIGN_IDENTITY=-",
            "CODE_SIGNING_REQUIRED=NO",
            "AD_HOC_CODE_SIGNING_ALLOWED=YES",
        ]
        _stream_command(uitest_cmd, repo_root, out_dir / "uitests.log")
        timings["xcuitests"] = round(time.monotonic() - t_uitest, 2)
        print(f"  [PASS] Real XCUITest Suite ({test_desc}) succeeded in {timings['xcuitests']}s.", flush=True)
    else:
        timings["xcuitests"] = 0.0
        print("=== [3c/5] Skipping XCUITests (0/5 impacted by change scope) ===", flush=True)

    app_installed = False

    def ensure_app_installed() -> None:
        nonlocal app_installed
        if not app_installed:
            app_path = next((derived / "Build" / "Products" / "Debug-iphonesimulator").glob("Antigravity.app"))
            subprocess.run(["xcrun", "simctl", "install", udid, str(app_path)], check=True)
            app_installed = True

    # Step 4: Live Connect-RPC App Handshake (only when impacted or full/release)
    rpc_hits: list[str] = []
    if cfg["runLiveAppRPC"]:
        t_rpc = time.monotonic()
        print(f"=== [4/5] Verifying Live Connect-RPC App Handshake on {sim_name} ===", flush=True)
        ensure_app_installed()

        spec = importlib.util.spec_from_file_location("bridge", repo_root / "scripts" / "mac-companion-bridge.py")
        assert spec and spec.loader
        bridge_mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge_mod)

        csrf_token = f"sim-live-{secrets.token_hex(8)}"
        bridge_srv = bridge_mod.create_bridge_server(
            bind_host="127.0.0.1",
            bind_port=0,
            bridge_csrf=csrf_token,
            workspace_root=str(repo_root),
        )
        orig_do_post = bridge_srv.RequestHandlerClass.do_POST

        def tracked_do_post(self):
            rpc_hits.append(self.path)
            return orig_do_post(self)

        bridge_srv.RequestHandlerClass.do_POST = tracked_do_post
        bridge_port = bridge_srv.server_port
        threading.Thread(target=bridge_srv.serve_forever, daemon=True).start()

        try:
            subprocess.run(["xcrun", "simctl", "terminate", udid, "dev.antigravity.ios.app"], check=False)
            launch_env = os.environ.copy()
            launch_env["SIMCTL_CHILD_NO_PROXY"] = "127.0.0.1,localhost,::1"
            launch_env["SIMCTL_CHILD_ANTIGRAVITY_BACKEND_URL"] = f"http://127.0.0.1:{bridge_port}"
            launch_env["SIMCTL_CHILD_ANTIGRAVITY_CSRF_TOKEN"] = csrf_token
            launch_env["SIMCTL_CHILD_ANTIGRAVITY_HOST_NAME"] = "Cloud Mac Runner"
            subprocess.run(
                ["xcrun", "simctl", "launch", udid, "dev.antigravity.ios.app"],
                env=launch_env,
                check=True,
            )
            for _ in range(20):
                if any("GetWorkspaceInfos" in p for p in rpc_hits) and any("GetAllCascadeTrajectories" in p for p in rpc_hits):
                    break
                time.sleep(0.5)
            time.sleep(1.5)

            live_shot = out_dir / "LIVE_CONNECTED_HOME.png"
            subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(live_shot)], check=True)
            (out_dir / "live_rpc_hits.json").write_text(json.dumps(rpc_hits, indent=2), encoding="utf-8")
            print(f"  [LIVE RPC] App-to-Backend Connect-RPC hits from Simulator: {rpc_hits}", flush=True)
            assert any("GetWorkspaceInfos" in p for p in rpc_hits), (
                f"Expected compiled Antigravity.app to call GetWorkspaceInfos over Connect-RPC, got: {rpc_hits}"
            )
            assert any("GetAllCascadeTrajectories" in p for p in rpc_hits), (
                f"Expected compiled Antigravity.app to call GetAllCascadeTrajectories over Connect-RPC, got: {rpc_hits}"
            )
        finally:
            bridge_srv.shutdown()
            bridge_srv.server_close()
        timings["liveRpcHandshake"] = round(time.monotonic() - t_rpc, 2)
    else:
        timings["liveRpcHandshake"] = 0.0
        print("=== [4/5] Skipping Live Connect-RPC App Handshake (unaffected by change scope) ===", flush=True)

    # Step 5: Capture impacted UE screens (or all 13 in full/release mode)
    captured_state_ids: list[str] = []
    if cfg["screens"]:
        t_shots = time.monotonic()
        ensure_app_installed()
        print(
            f"=== [5/5] Capturing {len(cfg['screens'])}/13 Native SwiftUI UE Screen(s) on iOS Simulator ===",
            flush=True,
        )
        for state_id in cfg["screens"]:
            captured_state_ids.append(state_id)
            subprocess.run(
                ["xcrun", "simctl", "terminate", udid, "dev.antigravity.ios.app"],
                check=False,
            )
            clean_env = {k: v for k, v in os.environ.items() if not k.startswith("SIMCTL_CHILD_ANTIGRAVITY_")}
            subprocess.run(
                [
                    "xcrun",
                    "simctl",
                    "launch",
                    udid,
                    "dev.antigravity.ios.app",
                    "--ui-verify",
                    state_id,
                ],
                env=clean_env,
                check=True,
            )
            time.sleep(1.8)
            shot_path = out_dir / f"{state_id}.png"
            subprocess.run(
                ["xcrun", "simctl", "io", udid, "screenshot", str(shot_path)],
                check=True,
            )
            print(f"  [CAPTURED] {state_id} -> {shot_path}", flush=True)

        build_overview_sheet(
            out_dir,
            captured_state_ids,
            f"{sim_name} · {sim_runtime}",
            is_full=cfg["allScreensSelected"],
        )
        timings["screenshots"] = round(time.monotonic() - t_shots, 2)
    else:
        timings["screenshots"] = 0.0
        print("=== [5/5] Skipping UE Screen Captures (0/13 screens impacted by change scope) ===", flush=True)

    timings["total"] = round(time.monotonic() - t_start, 2)
    manifest = {
        "mode": cfg["mode"],
        "simMode": cfg["simMode"],
        "isRelease": cfg["isRelease"],
        "simulatorName": sim_name,
        "simulatorRuntime": sim_runtime,
        "simulatorUDID": udid,
        "uiTestsPassed": True,
        "executedUITests": cfg["xcuitests"],
        "skippedUITests": cfg["skippedXcuitests"],
        "ranLiveConnectRPC": cfg["runLiveAppRPC"],
        "liveConnectRPCHits": rpc_hits,
        "capturedStates": captured_state_ids,
        "skippedStates": cfg["skippedScreens"],
        "timingsSec": timings,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(
        f"\n[PASS] iOS Simulator E2E Verified (mode={cfg['mode']}, XCUITests={len(cfg['xcuitests'])}/5, "
        f"LiveRPC={cfg['runLiveAppRPC']}, Screens={len(captured_state_ids)}/13, total={timings['total']}s).",
        flush=True,
    )


if __name__ == "__main__":
    main()
