#!/usr/bin/env python3
"""macOS Xcode + Apple Watch Simulator Native E2E Runner (`watchos-simulator-runner.py`).

Compiles `AGPocketWatch` (Swift 6 / watchOS 11+) for both:
  1. Apple Watch Simulator (`watchsimulator` targeting Apple Watch Series 10 46mm / 416x496px @2x)
  2. Real Apple Watch Device (`generic/platform=watchOS`, `CODE_SIGNING_ALLOWED=NO`)

Then boots a real watchOS Simulator, installs `AGPocketWatch.app`, launches all 8 deterministic
Watch verification scenes (`W01_SESSIONS` .. `W08_APPROVAL_NOTIFICATION`), captures each native
SwiftUI screenshot via `xcrun simctl io screenshot`, and generates:
  - `WATCH_8_SCREENS_OVERVIEW.png`: 4x2 overview grid of all 8 compiled Watch screens
  - `WATCH_REF_VS_SIM_COMPARISON.png`: 1:1 side-by-side Reference Mockup vs Real watchOS Simulator board
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

WATCH_SCHEME = "AGPocketWatch"
WATCH_BUNDLE_ID = "com.thousandtimes.agpocket.watchkitapp"
WATCH_WRAPPER = "AGPocketWatch.app"

PREFERRED_WATCHES = [
    "Apple Watch Series 10 (46mm)",
    "Apple Watch Series 11 (46mm)",
    "Apple Watch Ultra 3 (49mm)",
    "Apple Watch Ultra 2 (49mm)",
    "Apple Watch Series 10 (42mm)",
    "Apple Watch Series 9 (45mm)",
]

WATCH_SCENES: list[tuple[str, str]] = [
    ("W01_SESSIONS", "W01 Sessions"),
    ("W02_DEVICES", "W02 Devices"),
    ("W03_CHAT_STREAM", "W03 Chat Stream"),
    ("W04_ARTIFACT_SUMMARY", "W04 Artifact Summary"),
    ("W05_CHANGED_FILES_COMPACT", "W05 Changes (Compact)"),
    ("W06_CHANGED_FILES_GROUPED", "W06 Changes (Grouped)"),
    ("W07_VOICE_INPUT", "W07 Voice Input"),
    ("W08_APPROVAL_NOTIFICATION", "W08 Approval"),
]


def _stream_command(cmd: list[str], cwd: Path, log_path: Path) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8") as log_fp:
        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        assert proc.stdout is not None
        tail: list[str] = []
        for line in proc.stdout:
            log_fp.write(line)
            tail.append(line)
            if len(tail) > 80:
                tail.pop(0)
            if any(tok in line for tok in ("error:", "** BUILD", "warning: ", "Compiling ", "Linking ")):
                sys.stdout.write(line)
                sys.stdout.flush()
        rc = proc.wait()
        if rc != 0:
            sys.stderr.write(f"\n[FAIL] Command exited with code {rc}: {' '.join(cmd)}\n")
            sys.stderr.write("".join(tail))
            raise subprocess.CalledProcessError(rc, cmd)


def select_watch_simulator() -> tuple[str, str, str]:
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True
    )
    devices = json.loads(raw)["devices"]
    runtimes = [r for r in sorted(devices.keys(), reverse=True) if "watchOS" in r]

    for preferred in PREFERRED_WATCHES:
        for runtime in runtimes:
            for dev in devices[runtime]:
                if dev.get("isAvailable") and dev.get("name") == preferred:
                    return dev["udid"], dev["name"], runtime

    for runtime in runtimes:
        for dev in devices[runtime]:
            name = dev.get("name", "")
            if dev.get("isAvailable") and "Watch" in name and ("46mm" in name or "45mm" in name or "49mm" in name):
                return dev["udid"], name, runtime

    for runtime in runtimes:
        for dev in devices[runtime]:
            if dev.get("isAvailable") and "Watch" in dev.get("name", ""):
                return dev["udid"], dev["name"], runtime

    raise RuntimeError("No available Apple Watch Simulator found in Xcode.")


def build_watch_overview_sheet(out_dir: Path, device_label: str) -> Path | None:
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("[!] Pillow not installed; skipping Watch overview generation.", flush=True)
        return None

    cols, rows = 4, 2
    cell_w, cell_h = 260, 310
    pad_x, pad_y = 24, 52
    header_h = 96
    canvas_w = pad_x + cols * (cell_w + pad_x)
    canvas_h = header_h + pad_y + rows * (cell_h + pad_y)

    board = Image.new("RGB", (canvas_w, canvas_h), (9, 10, 13))
    draw = ImageDraw.Draw(board)
    draw.text(
        (pad_x, 24),
        f"AG Pocket Watch — Real watchOS Simulator All 8 Native SwiftUI Screens ({device_label})",
        fill=(245, 247, 250),
    )
    draw.text(
        (pad_x, 54),
        "Compiled via xcodebuild (Swift 6 / watchOS 11+) & captured via `xcrun simctl io screenshot`",
        fill=(141, 184, 255),
    )

    for idx, (scene_id, label) in enumerate(WATCH_SCENES):
        shot_path = out_dir / f"{scene_id}.png"
        if not shot_path.exists():
            continue
        r = idx // cols
        c = idx % cols
        x = pad_x + c * (cell_w + pad_x)
        y = header_h + r * (cell_h + pad_y)
        draw.text((x, y), label, fill=(213, 216, 226))
        img = Image.open(shot_path).convert("RGB")
        img.thumbnail((cell_w, cell_h), Image.Resampling.LANCZOS)
        ox = x + (cell_w - img.width) // 2
        oy = y + 24
        board.paste(img, (ox, oy))

    overview_path = out_dir / "WATCH_8_SCREENS_OVERVIEW.png"
    board.save(overview_path, format="PNG")
    print(f"  [OVERVIEW] {overview_path}", flush=True)
    return overview_path


def build_ref_vs_sim_comparison_sheet(
    repo_root: Path, out_dir: Path, device_label: str
) -> Path | None:
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return None

    ref_dir = repo_root / "specs" / "watch" / "reference"
    pairs = [
        (sid, label, ref_dir / f"{sid}.png", out_dir / f"{sid}.png")
        for sid, label in WATCH_SCENES
        if (ref_dir / f"{sid}.png").exists() and (out_dir / f"{sid}.png").exists()
    ]
    if not pairs:
        return None

    thumb_w, thumb_h = 220, 262
    inner_gap = 12
    card_pad = 16
    card_header = 44
    card_w = card_pad * 2 + thumb_w * 2 + inner_gap
    card_h = card_header + thumb_h + card_pad

    cols = 2
    rows = (len(pairs) + cols - 1) // cols
    outer_pad = 24
    pair_gap = 20
    header_h = 88
    canvas_w = outer_pad * 2 + cols * card_w + (cols - 1) * pair_gap
    canvas_h = header_h + outer_pad + rows * card_h + (rows - 1) * pair_gap + outer_pad

    board = Image.new("RGB", (canvas_w, canvas_h), (9, 10, 13))
    draw = ImageDraw.Draw(board)
    draw.text(
        (outer_pad, 22),
        f"AG Pocket Watch — Reference Mockup (Left) vs Real watchOS Simulator (Right) ({device_label})",
        fill=(245, 247, 250),
    )
    draw.text(
        (outer_pad, 52),
        "1:1 visual parity audit across all 8 Apple Watch companion screens (W01..W08)",
        fill=(141, 184, 255),
    )

    for idx, (_sid, label, ref_path, sim_path) in enumerate(pairs):
        r = idx // cols
        c = idx % cols
        cx = outer_pad + c * (card_w + pair_gap)
        cy = header_h + outer_pad + r * (card_h + pair_gap)
        draw.rectangle([cx, cy, cx + card_w, cy + card_h], fill=(20, 21, 25), outline=(44, 47, 56), width=1)
        draw.text((cx + card_pad, cy + 12), f"{label}   [Ref | Sim]", fill=(241, 241, 243))

        for slot, img_path in enumerate((ref_path, sim_path)):
            img = Image.open(img_path).convert("RGB")
            img.thumbnail((thumb_w, thumb_h), Image.Resampling.LANCZOS)
            px = cx + card_pad + slot * (thumb_w + inner_gap) + (thumb_w - img.width) // 2
            py = cy + card_header + (thumb_h - img.height) // 2
            board.paste(img, (px, py))

    out_path = out_dir / "WATCH_REF_VS_SIM_COMPARISON.png"
    board.save(out_path, format="PNG")
    print(f"  [COMPARE] {out_path}", flush=True)
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Real Apple Watch Simulator Build & 8-Screen Visual E2E Runner")
    parser.add_argument(
        "--out-dir",
        default="verification/output/real-simulator/watch",
        help="Directory to write Watch screenshots, logs, and comparison boards",
    )
    parser.add_argument(
        "--skip-device-build",
        action="store_true",
        help="Skip generic/platform=watchOS device build check",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    out_dir = (repo_root / args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    derived_sim = repo_root / ".build" / "DerivedDataWatchSim"
    derived_dev = repo_root / ".build" / "DerivedDataWatchDevice"

    t_start = time.monotonic()
    timings: dict[str, Any] = {}

    if not (repo_root / "PocketAntigravity.xcodeproj").exists():
        print("=== [W0/4] Generating PocketAntigravity.xcodeproj via xcodegen ===", flush=True)
        subprocess.run(["xcodegen", "generate"], cwd=repo_root, check=True)

    udid, sim_name, sim_runtime = select_watch_simulator()
    print(f"=== [W1/4] Booting Apple Watch Simulator ({sim_name} · {sim_runtime}, UDID={udid}) ===", flush=True)
    boot_proc = subprocess.Popen(
        ["xcrun", "simctl", "boot", udid],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    t_build = time.monotonic()
    print(f"=== [W2/5] Building {WATCH_SCHEME} + AGPocketWatchUITests for watchsimulator ({sim_name}) ===", flush=True)
    sim_build_cmd = [
        "xcodebuild",
        "build-for-testing",
        "-project",
        "PocketAntigravity.xcodeproj",
        "-scheme",
        WATCH_SCHEME,
        "-destination",
        f"id={udid}",
        "-derivedDataPath",
        str(derived_sim),
        "CODE_SIGN_IDENTITY=-",
        "CODE_SIGNING_REQUIRED=NO",
        "AD_HOC_CODE_SIGNING_ALLOWED=YES",
    ]
    _stream_command(sim_build_cmd, repo_root, out_dir / "xcodebuild-watchsim.log")
    timings["watchSimBuild"] = round(time.monotonic() - t_build, 2)

    if not args.skip_device_build:
        t_dev = time.monotonic()
        print(f"=== [W2b/5] Verifying watchOS Device (watchos arm64) Compile & Link ===", flush=True)
        dev_build_cmd = [
            "xcodebuild",
            "build",
            "-project",
            "PocketAntigravity.xcodeproj",
            "-scheme",
            WATCH_SCHEME,
            "-configuration",
            "Debug",
            "-destination",
            "generic/platform=watchOS",
            "-derivedDataPath",
            str(derived_dev),
            "CODE_SIGNING_ALLOWED=NO",
            "CODE_SIGNING_REQUIRED=NO",
            "CODE_SIGN_IDENTITY=",
        ]
        _stream_command(dev_build_cmd, repo_root, out_dir / "xcodebuild-watchos.log")
        timings["watchDeviceBuild"] = round(time.monotonic() - t_dev, 2)

    boot_proc.wait()
    subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)

    t_uitest = time.monotonic()
    xcresult_path = out_dir / "AGPocketWatchUITests.xcresult"
    shutil.rmtree(xcresult_path, ignore_errors=True)
    print(f"=== [W3/5] Running Real watchOS XCUITest E2E Suite (AGPocketWatchUITests) on {sim_name} ===", flush=True)
    watch_uitest_cmd = [
        "xcodebuild",
        "test-without-building",
        "-project",
        "PocketAntigravity.xcodeproj",
        "-scheme",
        WATCH_SCHEME,
        "-destination",
        f"id={udid}",
        "-derivedDataPath",
        str(derived_sim),
        "-only-testing:AGPocketWatchUITests",
        "-resultBundlePath",
        str(xcresult_path),
        "CODE_SIGN_IDENTITY=-",
        "CODE_SIGNING_REQUIRED=NO",
        "AD_HOC_CODE_SIGNING_ALLOWED=YES",
    ]
    _stream_command(watch_uitest_cmd, repo_root, out_dir / "watch-uitests.log")
    timings["watchUITests"] = round(time.monotonic() - t_uitest, 2)
    print(f"  [PASS] Real watchOS XCUITest Suite succeeded in {timings['watchUITests']}s.", flush=True)

    app_candidates = list((derived_sim / "Build" / "Products" / "Debug-watchsimulator").glob(WATCH_WRAPPER))
    if not app_candidates:
        raise FileNotFoundError(
            f"Built {WATCH_WRAPPER} not found under {derived_sim / 'Build/Products/Debug-watchsimulator'}"
        )
    watch_app_path = app_candidates[0]
    print(f"=== [W4/5] Installing {watch_app_path.name} onto {sim_name} ===", flush=True)
    subprocess.run(["xcrun", "simctl", "install", udid, str(watch_app_path)], check=True)

    t_shots = time.monotonic()
    captured: list[str] = []
    print(f"=== [W5/5] Capturing all {len(WATCH_SCENES)} Native watchOS SwiftUI Screens ===", flush=True)
    for scene_id, label in WATCH_SCENES:
        subprocess.run(["xcrun", "simctl", "terminate", udid, WATCH_BUNDLE_ID], check=False)
        launch_env = {k: v for k, v in os.environ.items() if not k.startswith("SIMCTL_CHILD_AGPOCKET_")}
        launch_env["SIMCTL_CHILD_AGPOCKET_WATCH_VERIFY"] = scene_id
        subprocess.run(
            [
                "xcrun",
                "simctl",
                "launch",
                udid,
                WATCH_BUNDLE_ID,
                "--watch-verify",
                scene_id,
            ],
            env=launch_env,
            check=True,
        )
        time.sleep(1.8)
        shot_path = out_dir / f"{scene_id}.png"
        subprocess.run(["xcrun", "simctl", "io", udid, "screenshot", str(shot_path)], check=True)
        captured.append(scene_id)
        print(f"  [CAPTURED] {scene_id} ({label}) -> {shot_path}", flush=True)

    device_label = f"{sim_name} · {sim_runtime}"
    build_watch_overview_sheet(out_dir, device_label)
    build_ref_vs_sim_comparison_sheet(repo_root, out_dir, device_label)
    timings["screenshots"] = round(time.monotonic() - t_shots, 2)
    timings["total"] = round(time.monotonic() - t_start, 2)

    manifest = {
        "simulatorName": sim_name,
        "simulatorRuntime": sim_runtime,
        "simulatorUDID": udid,
        "capturedScenes": captured,
        "timingsSec": timings,
    }
    (out_dir / "watch_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(
        f"\n[PASS] Real Apple Watch Simulator E2E Verified ({len(captured)}/{len(WATCH_SCENES)} screens, total={timings['total']}s).",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
