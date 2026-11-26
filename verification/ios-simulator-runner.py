#!/usr/bin/env python3
"""macOS Xcode + iPhone Simulator Native E2E Runner (`ios-simulator-runner.py`).

Supports both:
  - **Impact-Scoped Mode (`--plan <e2e-plan.json>` / `--mode auto|scoped|build-only`)**:
    Runs only the impacted Xcode build, targeted XCUITest methods (`-only-testing:...`),
    live Connect-RPC handshake (when RPC/connection changed), and impacted native Simulator
    UE screenshots (`UE01`..`UE13`), skipping unaffected cases and avoiding Simulator boot
    entirely in `build-only` mode.
  - **Full / Release Mode (`--mode full|release`, or default when invoked without scope flags)**:
    Assembles KMP `AntigravityShared.xcframework` if absent, compiles `AGPocket.app`
    (+ extensions + `AGPocketUITests`), runs ALL modular XCUITests, verifies Live
    Connect-RPC App Handshake, and captures ALL 13 native SwiftUI screens (`UE01`..`UE13`)
    + composite overview board + Light/Dark appearance comparison sheet.

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

APP_SCHEME = "AGPocket"
APP_BUNDLE_ID = "com.thousandtimes.agpocket"
APP_WRAPPER = "AGPocket.app"
UITEST_TARGET = "AGPocketUITests"
UITEST_TARGET_CLASS = f"{UITEST_TARGET}/AntigravityInteractiveUITests"

# Additional Light & Dark Mode visual verification captures run in full/release mode
# Tuple format: (output_stem, --ui-verify argument, --ui-appearance argument)
APPEARANCE_VARIANT_CAPTURES: list[tuple[str, str, str]] = [
    ("UE01_AGENTS_HOME_LIGHT", "UE01_AGENTS_HOME", "light"),
    ("UE07_CHAT_AND_COMPOSER_LIGHT", "UE07_CHAT_AND_COMPOSER", "light"),
    ("UE12_TURN_DIFF_REVIEW_LIGHT", "UE12_TURN_DIFF_REVIEW", "light"),
    ("SETTINGS_DARK", "settings", "dark"),
    ("SETTINGS_LIGHT", "settings", "light"),
]

# Side-by-side Dark vs Light comparison pairs: (pair_title, dark_stem, light_stem)
LIGHT_DARK_COMPARISON_PAIRS: list[tuple[str, str, str]] = [
    ("Agents Home (UE01)", "UE01_AGENTS_HOME", "UE01_AGENTS_HOME_LIGHT"),
    ("Cascade Chat (UE07)", "UE07_CHAT_AND_COMPOSER", "UE07_CHAT_AND_COMPOSER_LIGHT"),
    ("Turn Diff Review (UE12)", "UE12_TURN_DIFF_REVIEW", "UE12_TURN_DIFF_REVIEW_LIGHT"),
    ("Settings", "SETTINGS_DARK", "SETTINGS_LIGHT"),
]


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
    title_scope = f"All {len(state_ids)} Native SwiftUI Captures" if is_full else f"Impact-Scoped Captures ({len(state_ids)} screen(s))"
    draw.text(
        (pad_x, 28),
        f"PocketAntigravity — Real Xcode iOS Simulator {title_scope} ({device_label})",
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

    filename = f"REAL_SIMULATOR_{len(state_ids)}_SCREENS_OVERVIEW.png" if is_full else "REAL_SIMULATOR_SCOPED_SCREENS_OVERVIEW.png"
    overview_path = out_dir / filename
    board.save(overview_path, format="PNG")
    print(f"  [OVERVIEW] {overview_path}", flush=True)


def build_reference_comparison_sheets(
    out_dir: Path,
    repo_root: Path,
    screen_entries: list[dict[str, Any]],
    captured_state_ids: list[str],
    device_label: str,
) -> list[Path]:
    """Builds 1:1 side-by-side Reference UE (`docs/ue/ios/*.png`) vs Real iOS Simulator comparison PNGs."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("[!] Pillow not installed; skipping reference comparison sheet generation.", flush=True)
        return []

    ref_by_id = {entry["id"]: entry for entry in screen_entries}
    cmp_dir = out_dir / "comparisons"
    cmp_dir.mkdir(parents=True, exist_ok=True)
    generated: list[Path] = []

    for sid in captured_state_ids:
        sim_path = out_dir / f"{sid}.png"
        entry = ref_by_id.get(sid)
        if not sim_path.exists() or not entry:
            continue
        raw_ref = Path(entry.get("referenceUEImage", ""))
        ref_path = raw_ref if raw_ref.is_absolute() else (repo_root / raw_ref)
        if not ref_path.exists():
            continue

        ref_img = Image.open(ref_path).convert("RGB")
        sim_img = Image.open(sim_path).convert("RGB")

        target_h = 1100
        ref_scale = target_h / max(1, ref_img.height)
        sim_scale = target_h / max(1, sim_img.height)
        ref_resized = ref_img.resize((max(1, int(ref_img.width * ref_scale)), target_h), Image.Resampling.LANCZOS)
        sim_resized = sim_img.resize((max(1, int(sim_img.width * sim_scale)), target_h), Image.Resampling.LANCZOS)

        pad = 28
        gap = 28
        header_h = 84
        canvas_w = pad * 2 + ref_resized.width + gap + sim_resized.width
        canvas_h = header_h + target_h + pad

        sheet = Image.new("RGB", (canvas_w, canvas_h), (11, 11, 12))
        draw = ImageDraw.Draw(sheet)
        draw.text((pad, 18), f"{sid} — Reference UE vs Real iOS Simulator ({device_label})", fill=(245, 246, 248))
        draw.text((pad, 48), f"LEFT: Reference ({entry.get('referenceUEImage', '')})", fill=(141, 184, 255))
        draw.text((pad + ref_resized.width + gap, 48), f"RIGHT: Real iOS Simulator ({sid}.png)", fill=(111, 216, 166))

        sheet.paste(ref_resized, (pad, header_h))
        sheet.paste(sim_resized, (pad + ref_resized.width + gap, header_h))

        out_cmp = cmp_dir / f"IOS_CMP_{sid}.png"
        sheet.save(out_cmp, format="PNG")
        generated.append(out_cmp)
        print(f"  [CMP] {out_cmp}", flush=True)

    return generated


def build_light_dark_comparison_sheet(out_dir: Path, device_label: str) -> Path | None:
    """Builds a side-by-side Dark vs Light Mode contact sheet across Home, Chat, Diff & Settings."""
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("[!] Pillow not installed; skipping Light/Dark comparison sheet generation.", flush=True)
        return None

    available_pairs = [
        pair for pair in LIGHT_DARK_COMPARISON_PAIRS
        if (out_dir / f"{pair[1]}.png").exists() or (out_dir / f"{pair[2]}.png").exists()
    ]
    if not available_pairs:
        return None

    thumb_w, thumb_h = 360, 780
    inner_gap = 18
    card_pad = 20
    card_header_h = 56
    card_w = card_pad * 2 + thumb_w * 2 + inner_gap
    card_h = card_header_h + thumb_h + card_pad

    outer_pad = 32
    pair_gap = 28
    header_h = 104
    pair_cols = 2
    pair_rows = (len(available_pairs) + pair_cols - 1) // pair_cols
    canvas_w = outer_pad * 2 + pair_cols * card_w + (pair_cols - 1) * pair_gap
    canvas_h = header_h + outer_pad + pair_rows * card_h + (pair_rows - 1) * pair_gap + outer_pad

    board = Image.new("RGB", (canvas_w, canvas_h), (11, 11, 12))
    draw = ImageDraw.Draw(board)
    draw.text(
        (outer_pad, 26),
        f"PocketAntigravity — Real Simulator Dark vs Light Mode Comparison ({device_label})",
        fill=(245, 247, 250),
    )
    draw.text(
        (outer_pad, 58),
        "Side-by-side Dark vs Light semantic surface, ink contrast & glass chrome verification (Home · Chat · Diff · Settings)",
        fill=(141, 184, 255),
    )

    for idx, (pair_title, dark_stem, light_stem) in enumerate(available_pairs):
        r = idx // pair_cols
        c = idx % pair_cols
        card_x = outer_pad + c * (card_w + pair_gap)
        card_y = header_h + outer_pad + r * (card_h + pair_gap)

        draw.rectangle(
            [card_x, card_y, card_x + card_w, card_y + card_h],
            fill=(20, 20, 22),
            outline=(42, 46, 58),
            width=2,
        )
        draw.text((card_x + card_pad, card_y + 12), pair_title, fill=(245, 247, 250))

        left_x = card_x + card_pad
        right_x = left_x + thumb_w + inner_gap
        slot_y = card_y + card_header_h

        draw.text((left_x, card_y + 34), f"Dark · {dark_stem}", fill=(141, 184, 255))
        draw.text((right_x, card_y + 34), f"Light · {light_stem}", fill=(242, 184, 102))

        for slot_x, stem in ((left_x, dark_stem), (right_x, light_stem)):
            img_path = out_dir / f"{stem}.png"
            if not img_path.exists():
                continue
            img = Image.open(img_path).convert("RGB")
            img.thumbnail((thumb_w, thumb_h), Image.Resampling.LANCZOS)
            ox = slot_x + (thumb_w - img.width) // 2
            oy = slot_y + (thumb_h - img.height) // 2
            board.paste(img, (ox, oy))

    comparison_path = out_dir / "REAL_SIMULATOR_LIGHT_DARK_COMPARISON.png"
    board.save(comparison_path, format="PNG")
    print(f"  [COMPARISON] {comparison_path}", flush=True)
    return comparison_path


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
        run_watchos_sim = bool(gates.get("runWatchOSSim", False))
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
            run_watchos_sim = False
        elif mode == "build-only":
            sim_mode = "build-only"
            xcuitests = []
            screens = []
            run_live_rpc = False
            run_watchos_sim = False
        else:
            sim_mode = "full" if mode in ("full", "release") else "scoped"
            xcuitests = list(planner.ALL_XCUITESTS)
            screens = list(all_state_ids)
            run_live_rpc = True
            run_watchos_sim = True

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
        "totalXcuitests": len(planner.ALL_XCUITESTS),
        "allTestsSelected": all_tests_selected,
        "runLiveAppRPC": run_live_rpc,
        "runWatchOSSim": run_watchos_sim,
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
    parser.add_argument("--release", action="store_true", help="Shorthand for --mode release (mandatory full E2E)")
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
    total_xcuitests = cfg["totalXcuitests"]
    total_screens = len(all_state_ids)

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
        f"isRelease={cfg['isRelease']} | XCUITests={len(cfg['xcuitests'])}/{total_xcuitests} | "
        f"LiveAppRPC={cfg['runLiveAppRPC']} | Screens={len(cfg['screens'])}/{total_screens} ===",
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
            "capturedAppearanceVariants": [],
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

    # Fast path: build-only (compiles AGPocket.app + Extensions for iOS Simulator WITHOUT booting Simulator!)
    if cfg["simMode"] == "build-only":
        t_build = time.monotonic()
        host_arch = platform.machine() or "arm64"
        print(
            f"=== [2/5] Build-Only Mode: Compiling {APP_WRAPPER} for generic iOS Simulator ({host_arch}) — skipping Simulator boot ===",
            flush=True,
        )
        build_cmd = [
            "xcodebuild",
            "build",
            "-project",
            "PocketAntigravity.xcodeproj",
            "-scheme",
            APP_SCHEME,
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
        if cfg.get("runWatchOSSim"):
            t_watch = time.monotonic()
            print("=== [2b/5] Running Apple Watch Simulator E2E (W01–W08) ===", flush=True)
            subprocess.run(
                [
                    sys.executable,
                    str(repo_root / "verification" / "watchos-simulator-runner.py"),
                    "--out-dir",
                    str(out_dir / "watch"),
                ],
                cwd=repo_root,
                check=True,
            )
            timings["watchOSSim"] = round(time.monotonic() - t_watch, 2)
        timings["total"] = round(time.monotonic() - t_start, 2)
        manifest = {
            "mode": cfg["mode"],
            "simMode": "build-only",
            "isRelease": cfg["isRelease"],
            "buildSucceeded": True,
            "ranWatchOSSim": bool(cfg.get("runWatchOSSim")),
            "executedUITests": [],
            "skippedUITests": cfg["skippedXcuitests"],
            "ranLiveConnectRPC": False,
            "capturedStates": [],
            "capturedAppearanceVariants": [],
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
        "PocketAntigravity.xcodeproj",
        "-scheme",
        APP_SCHEME,
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
        xcresult_path = out_dir / f"{UITEST_TARGET}.xcresult"
        shutil.rmtree(xcresult_path, ignore_errors=True)
        if cfg["allTestsSelected"]:
            only_testing_flags = [f"-only-testing:{UITEST_TARGET}"]
            test_desc = f"ALL {len(cfg['xcuitests'])}/{total_xcuitests} XCUITest cases"
        else:
            only_testing_flags = [
                f"-only-testing:{UITEST_TARGET_CLASS}/{method}" for method in cfg["xcuitests"]
            ]
            test_desc = f"{len(cfg['xcuitests'])}/{total_xcuitests} scoped XCUITest case(s): {', '.join(cfg['xcuitests'])}"

        print(f"=== [3c/5] Running Real XCUITest Suite ({test_desc}) on {sim_name} ===", flush=True)
        uitest_cmd = [
            "xcodebuild",
            "test-without-building",
            "-project",
            "PocketAntigravity.xcodeproj",
            "-scheme",
            APP_SCHEME,
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
        print(f"=== [3c/5] Skipping XCUITests (0/{total_xcuitests} impacted by change scope) ===", flush=True)

    app_installed = False

    def ensure_app_installed() -> None:
        nonlocal app_installed
        if not app_installed:
            app_path = next((derived / "Build" / "Products" / "Debug-iphonesimulator").glob(APP_WRAPPER))
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
            launch_env = os.environ.copy()
            launch_env["SIMCTL_CHILD_NO_PROXY"] = "127.0.0.1,localhost,::1"
            launch_env["SIMCTL_CHILD_ANTIGRAVITY_BACKEND_URL"] = f"http://127.0.0.1:{bridge_port}"
            launch_env["SIMCTL_CHILD_ANTIGRAVITY_CSRF_TOKEN"] = csrf_token
            launch_env["SIMCTL_CHILD_ANTIGRAVITY_HOST_NAME"] = "Cloud Mac Runner"
            for attempt in range(2):
                subprocess.run(["xcrun", "simctl", "terminate", udid, APP_BUNDLE_ID], check=False)
                if attempt > 0:
                    time.sleep(1.5)
                subprocess.run(
                    ["xcrun", "simctl", "launch", udid, APP_BUNDLE_ID],
                    env=launch_env,
                    check=True,
                )
                for _ in range(30):
                    if any("GetWorkspaceInfos" in p for p in rpc_hits) and any("GetAllCascadeTrajectories" in p for p in rpc_hits):
                        break
                    time.sleep(0.5)
                if any("GetWorkspaceInfos" in p for p in rpc_hits) and any("GetAllCascadeTrajectories" in p for p in rpc_hits):
                    break
                if attempt == 0:
                    print("  [LIVE RPC] No Connect-RPC hits after 15s; relaunching app once on Simulator...", flush=True)
            time.sleep(1.5)

            live_shot = out_dir / "LIVE_CONNECTED_HOME.png"
            subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(live_shot)], check=True)
            (out_dir / "live_rpc_hits.json").write_text(json.dumps(rpc_hits, indent=2), encoding="utf-8")
            print(f"  [LIVE RPC] App-to-Backend Connect-RPC hits from Simulator: {rpc_hits}", flush=True)
            assert any("GetWorkspaceInfos" in p for p in rpc_hits), (
                f"Expected compiled {APP_WRAPPER} to call GetWorkspaceInfos over Connect-RPC, got: {rpc_hits}"
            )
            assert any("GetAllCascadeTrajectories" in p for p in rpc_hits), (
                f"Expected compiled {APP_WRAPPER} to call GetAllCascadeTrajectories over Connect-RPC, got: {rpc_hits}"
            )
        finally:
            bridge_srv.shutdown()
            bridge_srv.server_close()
        timings["liveRpcHandshake"] = round(time.monotonic() - t_rpc, 2)
    else:
        timings["liveRpcHandshake"] = 0.0
        print("=== [4/5] Skipping Live Connect-RPC App Handshake (unaffected by change scope) ===", flush=True)

    # Step 5: Capture impacted UE screens (or all 20 + Light/Dark visual verification in full/release mode)
    captured_state_ids: list[str] = []
    captured_appearance_variants: list[str] = []
    all_screen_entries = list(ir.get("states", [])) + list(ir.get("extendedScreens", []))
    screens_to_capture = list(cfg["screens"])
    if cfg["allScreensSelected"]:
        for ext in ir.get("extendedScreens", []):
            if ext["id"] not in screens_to_capture:
                screens_to_capture.append(ext["id"])

    if screens_to_capture:
        t_shots = time.monotonic()
        ensure_app_installed()
        print(
            f"=== [5/5] Capturing {len(screens_to_capture)}/{len(all_screen_entries)} Native SwiftUI UE Screen(s) on iOS Simulator ===",
            flush=True,
        )
        for state_id in screens_to_capture:
            captured_state_ids.append(state_id)
            subprocess.run(
                ["xcrun", "simctl", "terminate", udid, APP_BUNDLE_ID],
                check=False,
            )
            clean_env = {k: v for k, v in os.environ.items() if not k.startswith("SIMCTL_CHILD_ANTIGRAVITY_")}
            subprocess.run(
                [
                    "xcrun",
                    "simctl",
                    "launch",
                    udid,
                    APP_BUNDLE_ID,
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
        build_reference_comparison_sheets(
            out_dir=out_dir,
            repo_root=repo_root,
            screen_entries=all_screen_entries,
            captured_state_ids=captured_state_ids,
            device_label=f"{sim_name} · {sim_runtime}",
        )

        # Light & Dark Mode Visual Verification (full/release mode)
        if cfg["allScreensSelected"]:
            t_appearance = time.monotonic()
            print(
                f"=== [5b/5] Capturing {len(APPEARANCE_VARIANT_CAPTURES)} Light & Dark Mode Visual Verification Screen(s) ===",
                flush=True,
            )
            for variant_id, verify_target, appearance_mode in APPEARANCE_VARIANT_CAPTURES:
                captured_appearance_variants.append(variant_id)
                subprocess.run(
                    ["xcrun", "simctl", "terminate", udid, APP_BUNDLE_ID],
                    check=False,
                )
                clean_env = {k: v for k, v in os.environ.items() if not k.startswith("SIMCTL_CHILD_ANTIGRAVITY_")}
                subprocess.run(
                    [
                        "xcrun",
                        "simctl",
                        "launch",
                        udid,
                        APP_BUNDLE_ID,
                        "--ui-verify",
                        verify_target,
                        "--ui-appearance",
                        appearance_mode,
                    ],
                    env=clean_env,
                    check=True,
                )
                time.sleep(1.8)
                shot_path = out_dir / f"{variant_id}.png"
                subprocess.run(
                    ["xcrun", "simctl", "io", udid, "screenshot", str(shot_path)],
                    check=True,
                )
                print(
                    f"  [APPEARANCE] {variant_id} (--ui-verify {verify_target} --ui-appearance {appearance_mode}) -> {shot_path}",
                    flush=True,
                )

            build_light_dark_comparison_sheet(out_dir, f"{sim_name} · {sim_runtime}")
            timings["appearanceScreenshots"] = round(time.monotonic() - t_appearance, 2)

        timings["screenshots"] = round(time.monotonic() - t_shots, 2)
    else:
        timings["screenshots"] = 0.0
        print(f"=== [5/5] Skipping UE Screen Captures (0/{total_screens} screens impacted by change scope) ===", flush=True)

    if cfg.get("runWatchOSSim"):
        t_watch = time.monotonic()
        print("=== [5c/5] Running Real Apple Watch Simulator Build + XCUITests + 8 Native watchOS Screens (W01–W08) ===", flush=True)
        subprocess.run(["xcrun", "simctl", "shutdown", udid], check=False)
        subprocess.run(
            [
                sys.executable,
                str(repo_root / "verification" / "watchos-simulator-runner.py"),
                "--out-dir",
                str(out_dir / "watch"),
                "--preferred-phone-udid",
                udid,
            ],
            cwd=repo_root,
            check=True,
        )
        timings["watchOSSim"] = round(time.monotonic() - t_watch, 2)
    else:
        timings["watchOSSim"] = 0.0

    timings["total"] = round(time.monotonic() - t_start, 2)
    manifest = {
        "mode": cfg["mode"],
        "simMode": cfg["simMode"],
        "isRelease": cfg["isRelease"],
        "simulatorName": sim_name,
        "simulatorRuntime": sim_runtime,
        "simulatorUDID": udid,
        "uiTestsPassed": True,
        "ranWatchOSSim": bool(cfg.get("runWatchOSSim")),
        "executedUITests": cfg["xcuitests"],
        "skippedUITests": cfg["skippedXcuitests"],
        "ranLiveConnectRPC": cfg["runLiveAppRPC"],
        "liveConnectRPCHits": rpc_hits,
        "capturedStates": captured_state_ids,
        "capturedAppearanceVariants": captured_appearance_variants,
        "skippedStates": cfg["skippedScreens"],
        "timingsSec": timings,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(
        f"\n[PASS] iOS Simulator E2E Verified (mode={cfg['mode']}, XCUITests={len(cfg['xcuitests'])}/{total_xcuitests}, "
        f"LiveRPC={cfg['runLiveAppRPC']}, Screens={len(captured_state_ids)}/{total_screens}, "
        f"AppearanceVariants={len(captured_appearance_variants)}, total={timings['total']}s).",
        flush=True,
    )


if __name__ == "__main__":
    main()
