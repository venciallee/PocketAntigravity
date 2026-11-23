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
import re
import select
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
    "Apple Watch Series 11 (42mm)",
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


def _stream_command(
    cmd: list[str],
    cwd: Path,
    log_path: Path,
    *,
    timeout_sec: int = 600,
    finish_grace_sec: int = 25,
    watch_test_markers: bool = False,
) -> None:
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
        fd = proc.stdout.fileno()
        tail: list[str] = []
        started_at = time.monotonic()
        marker_result: str | None = None
        marker_seen_at: float | None = None

        while True:
            now = time.monotonic()
            if now - started_at > timeout_sec:
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                sys.stderr.write(f"\n[FAIL] Command timed out after {timeout_sec}s: {' '.join(cmd)}\n")
                sys.stderr.write("".join(tail))
                raise subprocess.TimeoutExpired(cmd, timeout_sec)

            if marker_seen_at is not None and (now - marker_seen_at) >= finish_grace_sec:
                # Xcode 26.6 watchOS `test-without-building` can occasionally linger after
                # printing `** TEST SUCCEEDED **` under CI load; exit cleanly once grace elapses.
                print(
                    f"  [INFO] xcodebuild lingered {finish_grace_sec}s after {marker_result}; terminating cleanly.",
                    flush=True,
                )
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
                if marker_result == "SUCCEEDED":
                    return
                raise subprocess.CalledProcessError(65, cmd)

            ready, _, _ = select.select([fd], [], [], 1.0)
            if ready:
                line = proc.stdout.readline()
                if line == "":
                    break
                log_fp.write(line)
                log_fp.flush()
                tail.append(line)
                if len(tail) > 80:
                    tail.pop(0)
                if any(
                    tok in line
                    for tok in (
                        "error:",
                        "** BUILD",
                        "** TEST",
                        "Test Case ",
                        "warning: ",
                        "Compiling ",
                        "Linking ",
                    )
                ):
                    sys.stdout.write(line)
                    sys.stdout.flush()
                if watch_test_markers and marker_result is None:
                    if "** TEST SUCCEEDED **" in line:
                        marker_result = "SUCCEEDED"
                        marker_seen_at = time.monotonic()
                    elif "** TEST FAILED **" in line:
                        marker_result = "FAILED"
                        marker_seen_at = time.monotonic()
            elif proc.poll() is not None:
                # Drain any remaining buffered lines.
                for line in proc.stdout:
                    log_fp.write(line)
                    tail.append(line)
                    if len(tail) > 80:
                        tail.pop(0)
                break

        rc = proc.wait()
        if rc != 0:
            if watch_test_markers and marker_result == "SUCCEEDED":
                return
            sys.stderr.write(f"\n[FAIL] Command exited with code {rc}: {' '.join(cmd)}\n")
            sys.stderr.write("".join(tail))
            raise subprocess.CalledProcessError(rc, cmd)


def _runtime_version_key(runtime_id: str) -> str:
    """Extract numeric version suffix like '26-5' from a CoreSimulator runtime ID."""
    m = re.search(r"(\d+-\d+(?:-\d+)?)$", runtime_id)
    return m.group(1) if m else ""


def _list_simulators_and_pairs() -> tuple[dict[str, list[dict[str, Any]]], dict[str, dict[str, Any]]]:
    dev_raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "-j"], text=True
    )
    devices = json.loads(dev_raw).get("devices", {})
    pair_raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "pairs", "-j"], text=True
    )
    pairs = json.loads(pair_raw).get("pairs", {})
    return devices, pairs


def select_and_pair_watch_simulator(
    preferred_phone_udid: str | None = None,
) -> tuple[str, str, str, str | None, str | None]:
    """Select the best available Apple Watch Simulator and ensure it is paired with an iPhone Simulator.

    Companion watchOS apps that declare `WKCompanionAppBundleIdentifier` require a paired
    Apple Watch + iPhone simulator pair for `xcodebuild` to expose concrete watchOS Simulator
    destinations on fresh CI runners (which often ship without pre-configured pairs).
    """
    devices, pairs = _list_simulators_and_pairs()

    watch_runtimes = [r for r in sorted(devices.keys(), reverse=True) if "watchOS" in r]
    ios_runtimes = [r for r in sorted(devices.keys(), reverse=True) if "SimRuntime.iOS" in r]

    watch_by_udid: dict[str, tuple[str, str, str]] = {}
    ordered_watches: list[tuple[str, str, str]] = []
    for runtime in watch_runtimes:
        for dev in devices[runtime]:
            if dev.get("isAvailable") and "Watch" in dev.get("name", ""):
                entry = (dev["udid"], dev["name"], runtime)
                watch_by_udid[dev["udid"]] = entry
                ordered_watches.append(entry)

    if not ordered_watches:
        raise RuntimeError("No available Apple Watch Simulator found in Xcode.")

    phone_by_udid: dict[str, tuple[str, str, str, str]] = {}
    ordered_phones: list[tuple[str, str, str, str]] = []
    for runtime in ios_runtimes:
        for dev in devices[runtime]:
            if dev.get("isAvailable") and "iPhone" in dev.get("name", ""):
                entry = (dev["udid"], dev["name"], runtime, dev.get("state", "Shutdown"))
                phone_by_udid[dev["udid"]] = entry
                ordered_phones.append(entry)

    # Map existing valid pairs (watch_udid -> (pair_id, phone_udid))
    watch_to_phone: dict[str, tuple[str, str]] = {}
    paired_phone_udids: set[str] = set()
    for pair_id, pinfo in pairs.items():
        w_udid = (pinfo.get("watch") or {}).get("udid")
        p_udid = (pinfo.get("phone") or {}).get("udid")
        if w_udid in watch_by_udid and p_udid in phone_by_udid:
            watch_to_phone[w_udid] = (pair_id, p_udid)
            paired_phone_udids.add(p_udid)

    def watch_rank(entry: tuple[str, str, str]) -> tuple[int, int, int]:
        udid, name, runtime = entry
        is_paired = 0 if udid in watch_to_phone else 1
        rt_idx = watch_runtimes.index(runtime) if runtime in watch_runtimes else 99
        if name in PREFERRED_WATCHES:
            model_idx = PREFERRED_WATCHES.index(name)
        elif any(sz in name for sz in ("46mm", "45mm", "49mm")):
            model_idx = len(PREFERRED_WATCHES) + 1
        else:
            model_idx = len(PREFERRED_WATCHES) + 2
        return (rt_idx, is_paired, model_idx)

    # Prefer newest watchOS runtime, already-paired preferred large-face watch first.
    best_watch = sorted(ordered_watches, key=watch_rank)[0]
    w_udid, w_name, w_runtime = best_watch

    if w_udid in watch_to_phone:
        pair_id, p_udid = watch_to_phone[w_udid]
        p_name = phone_by_udid[p_udid][1]
        print(
            f"  [PAIR] Reusing existing Watch+iPhone pair {pair_id}: {w_name} ({w_udid}) <-> {p_name} ({p_udid})",
            flush=True,
        )
        return w_udid, w_name, w_runtime, p_udid, p_name

    # Pick an available iPhone simulator to pair with this Watch before booting.
    w_ver = _runtime_version_key(w_runtime)

    def phone_rank(entry: tuple[str, str, str, str]) -> tuple[int, int, int, int]:
        p_udid, p_name, p_runtime, p_state = entry
        ver_match = 0 if (w_ver and _runtime_version_key(p_runtime) == w_ver) else 1
        unpaired = 0 if p_udid not in paired_phone_udids else 1
        preferred = 0 if (preferred_phone_udid and p_udid == preferred_phone_udid) else 1
        is_shutdown = 0 if p_state == "Shutdown" else 1
        return (ver_match, unpaired, preferred, is_shutdown)

    if ordered_phones:
        p_udid, p_name, p_runtime, p_state = sorted(ordered_phones, key=phone_rank)[0]
        if p_state != "Shutdown":
            subprocess.run(["xcrun", "simctl", "shutdown", p_udid], check=False)
        print(
            f"  [PAIR] Pairing {w_name} ({w_udid}) with {p_name} ({p_udid}, {p_runtime})...",
            flush=True,
        )
        pair_proc = subprocess.run(
            ["xcrun", "simctl", "pair", w_udid, p_udid],
            capture_output=True,
            text=True,
        )
        if pair_proc.returncode == 0:
            pair_id = pair_proc.stdout.strip()
            print(f"  [PAIR] Created active Watch+iPhone pair: {pair_id}", flush=True)
            return w_udid, w_name, w_runtime, p_udid, p_name
        else:
            print(
                f"  [WARN] simctl pair failed ({pair_proc.returncode}): {pair_proc.stderr.strip()}",
                flush=True,
            )

    return w_udid, w_name, w_runtime, None, None


def discover_xcode_watch_destinations(repo_root: Path) -> list[dict[str, str]]:
    """Query `xcodebuild -showdestinations` for concrete watchOS Simulator destinations."""
    proc = subprocess.run(
        [
            "xcodebuild",
            "-showdestinations",
            "-project",
            "PocketAntigravity.xcodeproj",
            "-scheme",
            WATCH_SCHEME,
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
    )
    output = (proc.stdout or "") + "\n" + (proc.stderr or "")
    concrete: list[dict[str, str]] = []
    for line in output.splitlines():
        if "watchOS" in line:
            print(f"  [DEST] {line.strip()}", flush=True)
        if "platform:watchOS Simulator" in line and "placeholder" not in line:
            m_id = re.search(r"id:([^,}\s]+)", line)
            m_name = re.search(r"name:([^}]+)", line)
            m_os = re.search(r"OS:([^,\s}]+)", line)
            if m_id:
                concrete.append(
                    {
                        "id": m_id.group(1).strip(),
                        "name": (m_name.group(1).strip() if m_name else "Apple Watch"),
                        "os": (m_os.group(1).strip() if m_os else ""),
                    }
                )
    return concrete


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
        "--preferred-phone-udid",
        default=None,
        help="Optional iPhone Simulator UDID to pair with the Apple Watch Simulator when unpaired",
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
        print("=== [W0/5] Generating PocketAntigravity.xcodeproj via xcodegen ===", flush=True)
        subprocess.run(["xcodegen", "generate"], cwd=repo_root, check=True)

    print("=== [W1/5] Selecting & Pairing Apple Watch Simulator ===", flush=True)
    udid, sim_name, sim_runtime, phone_udid, phone_name = select_and_pair_watch_simulator(
        preferred_phone_udid=args.preferred_phone_udid
    )
    # Refresh CoreSimulator registry before querying xcodebuild destinations.
    subprocess.run(["xcrun", "simctl", "list"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    pairs_text = subprocess.run(["xcrun", "simctl", "list", "pairs"], capture_output=True, text=True)
    for pline in (pairs_text.stdout or "").splitlines()[:20]:
        if pline.strip():
            print(f"  [PAIRS] {pline}", flush=True)

    print(
        f"  [BOOT] Apple Watch Simulator ({sim_name} · {sim_runtime}, UDID={udid})"
        + (f" paired with {phone_name} ({phone_udid})" if phone_udid else " (standalone)"),
        flush=True,
    )
    phone_boot_proc = None
    if phone_udid:
        phone_boot_proc = subprocess.Popen(
            ["xcrun", "simctl", "boot", phone_udid],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    watch_boot_proc = subprocess.Popen(
        ["xcrun", "simctl", "boot", udid],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    concrete_dests = discover_xcode_watch_destinations(repo_root)
    if not concrete_dests:
        print("  [INFO] Waiting for Watch+iPhone bootstatus before re-checking xcodebuild destinations...", flush=True)
        if phone_boot_proc is not None:
            phone_boot_proc.wait()
            subprocess.run(["xcrun", "simctl", "bootstatus", phone_udid, "-b"], check=False)
        watch_boot_proc.wait()
        subprocess.run(["xcrun", "simctl", "bootstatus", udid, "-b"], check=True)
        subprocess.run(["xcrun", "simctl", "list"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        concrete_dests = discover_xcode_watch_destinations(repo_root)

    concrete_ids = {d["id"] for d in concrete_dests}
    if udid in concrete_ids:
        sim_build_dest = f"platform=watchOS Simulator,id={udid}"
    elif concrete_dests:
        adopted = concrete_dests[0]
        print(
            f"  [INFO] Adopting xcodebuild-visible Watch destination {adopted['name']} ({adopted['id']}) over {udid}",
            flush=True,
        )
        udid = adopted["id"]
        sim_name = adopted["name"]
        sim_runtime = f"watchOS {adopted['os']}" if adopted.get("os") else sim_runtime
        watch_boot_proc = subprocess.Popen(
            ["xcrun", "simctl", "boot", udid],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        sim_build_dest = f"platform=watchOS Simulator,id={udid}"
    else:
        print(
            "  [WARN] No concrete watchOS Simulator listed by -showdestinations; building with generic/platform=watchOS Simulator.",
            flush=True,
        )
        sim_build_dest = "generic/platform=watchOS Simulator"

    t_build = time.monotonic()
    print(
        f"=== [W2/5] Building {WATCH_SCHEME} + AGPocketWatchUITests for watchsimulator ({sim_build_dest}) ===",
        flush=True,
    )
    sim_build_cmd = [
        "xcodebuild",
        "build-for-testing",
        "-project",
        "PocketAntigravity.xcodeproj",
        "-scheme",
        WATCH_SCHEME,
        "-destination",
        sim_build_dest,
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
        print("=== [W2b/5] Verifying watchOS Device (watchos arm64) Compile & Link ===", flush=True)
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

    if phone_boot_proc is not None and phone_udid:
        phone_boot_proc.wait()
        subprocess.run(["xcrun", "simctl", "bootstatus", phone_udid, "-b"], check=False)
    watch_boot_proc.wait()
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
        f"platform=watchOS Simulator,id={udid}",
        "-derivedDataPath",
        str(derived_sim),
        "-only-testing:AGPocketWatchUITests",
        "-resultBundlePath",
        str(xcresult_path),
        "CODE_SIGN_IDENTITY=-",
        "CODE_SIGNING_REQUIRED=NO",
        "AD_HOC_CODE_SIGNING_ALLOWED=YES",
    ]
    _stream_command(
        watch_uitest_cmd,
        repo_root,
        out_dir / "watch-uitests.log",
        timeout_sec=480,
        finish_grace_sec=25,
        watch_test_markers=True,
    )
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
        time.sleep(2.0)
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
        "pairedPhoneName": phone_name,
        "pairedPhoneUDID": phone_udid,
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
