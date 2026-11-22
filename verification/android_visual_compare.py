#!/usr/bin/env python3
"""Android Native Material 3 Compose vs iOS Reference UE Side-by-Side Visual Comparison Builder.

Reads real Jetpack Compose PNG screenshots produced by `AndroidUeScreenshotTest` (Roborazzi)
under `apps/android/app/build/outputs/android_ue/` and compares every screen 1:1 against the
official iOS Reference UE screenshots under `verification/output/screenshots/`:
  - Generates `ANDROID_CMP_UE01.png` .. `ANDROID_CMP_UE13.png`
  - Generates `ANDROID_13_SCREENS_OVERVIEW.png`
  - Emits structured `android_visual_report.json` with dimensions & pass/fail completeness checks
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
ANDROID_SPEC_PATH = REPO_ROOT / "specs" / "android" / "esdd-android-ir.json"
DEFAULT_ANDROID_SHOTS_DIR = REPO_ROOT / "apps" / "android" / "app" / "build" / "outputs" / "android_ue"
DEFAULT_OUT_DIR = REPO_ROOT / "verification" / "output" / "android"


def _load_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]
    for path in candidates:
        p = Path(path)
        if p.exists():
            try:
                return ImageFont.truetype(str(p), size)
            except OSError:
                pass
    return ImageFont.load_default()


def build_side_by_side(
    idx_1based: int,
    state_id: str,
    title: str,
    ios_png: Path,
    android_png: Path,
    out_png: Path,
    is_landscape: bool = False,
) -> dict:
    font_title = _load_font(20)
    font_sub = _load_font(15)

    panel_w, panel_h = (960, 600) if is_landscape else (590, 1308)
    pad = 24
    header_h = 76
    canvas_w = pad * 3 + panel_w * 2
    canvas_h = header_h + pad * 2 + panel_h

    canvas = Image.new("RGB", (canvas_w, canvas_h), (12, 13, 18))
    draw = ImageDraw.Draw(canvas)

    draw.text(
        (pad, 14),
        f"ANDROID_CMP_UE{idx_1based:02d} · {state_id} — {title}",
        fill=(245, 247, 250),
        font=font_title,
    )
    draw.text(
        (pad, 44),
        "LEFT: iOS Reference UE (HIG / Liquid Glass)",
        fill=(157, 162, 176),
        font=font_sub,
    )
    draw.text(
        (pad * 2 + panel_w, 44),
        "RIGHT: Android Native Jetpack Compose (Material 3)",
        fill=(142, 180, 255),
        font=font_sub,
    )

    with Image.open(ios_png) as ios_im:
        ios_size = ios_im.size
        ios_rgb = ios_im.convert("RGB").resize((panel_w, panel_h), Image.Resampling.LANCZOS)
    canvas.paste(ios_rgb, (pad, header_h + pad))
    draw.rectangle(
        [pad - 1, header_h + pad - 1, pad + panel_w, header_h + pad + panel_h],
        outline=(75, 80, 94),
        width=2,
    )

    with Image.open(android_png) as and_im:
        android_size = and_im.size
        and_rgb = and_im.convert("RGB").resize((panel_w, panel_h), Image.Resampling.LANCZOS)
    canvas.paste(and_rgb, (pad * 2 + panel_w, header_h + pad))
    draw.rectangle(
        [pad * 2 + panel_w - 1, header_h + pad - 1, pad * 2 + panel_w * 2, header_h + pad + panel_h],
        outline=(142, 180, 255),
        width=2,
    )

    out_png.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_png, format="PNG")
    return {
        "stateId": state_id,
        "iosSizePx": list(ios_size),
        "androidSizePx": list(android_size),
        "comparisonPng": str(out_png.relative_to(REPO_ROOT)),
    }


def build_master_overview(entries: list[tuple[str, Path]], output_path: Path) -> None:
    font_hdr = _load_font(26)
    font_lbl = _load_font(14)

    cols = 6
    thumb_w, thumb_h = 314, 696
    pad = 22
    label_h = 28
    header_h = 84

    mobile_entries = entries[:12]
    spec_entry = entries[12]
    spec_w, spec_h = 1120, 700

    canvas_w = cols * thumb_w + (cols + 1) * pad
    canvas_h = header_h + 2 * (thumb_h + label_h + pad) + spec_h + label_h + pad * 2

    grid = Image.new("RGB", (canvas_w, canvas_h), (9, 10, 13))
    draw = ImageDraw.Draw(grid)
    draw.text(
        (pad, 26),
        "AG Pocket Android — 13-Screen Native Material 3 Jetpack Compose Gallery (UE01..UE13)",
        fill=(245, 247, 250),
        font=font_hdr,
    )

    for idx, (state_id, img_path) in enumerate(mobile_entries):
        r = idx // cols
        c = idx % cols
        x = pad + c * (thumb_w + pad)
        y = header_h + r * (thumb_h + label_h + pad)
        with Image.open(img_path) as im:
            resized = im.convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        grid.paste(resized, (x, y))
        draw.rectangle([x - 1, y - 1, x + thumb_w, y + thumb_h], outline=(55, 62, 78), width=1)
        draw.text((x, y + thumb_h + 6), state_id, fill=(142, 180, 255), font=font_lbl)

    spec_x = (canvas_w - spec_w) // 2
    spec_y = header_h + 2 * (thumb_h + label_h + pad)
    with Image.open(spec_entry[1]) as sim:
        spec_resized = sim.convert("RGB").resize((spec_w, spec_h), Image.Resampling.LANCZOS)
    grid.paste(spec_resized, (spec_x, spec_y))
    draw.rectangle([spec_x - 1, spec_y - 1, spec_x + spec_w, spec_y + spec_h], outline=(142, 180, 255), width=2)
    draw.text((spec_x, spec_y + spec_h + 6), f"{spec_entry[0]} (Android 16 Live Updates Spec)", fill=(142, 180, 255), font=font_lbl)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    grid.save(output_path, format="PNG")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build iOS vs Android Compose visual comparison sheets.")
    parser.add_argument("--android-shots", type=Path, default=DEFAULT_ANDROID_SHOTS_DIR)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args()

    spec = json.loads(ANDROID_SPEC_PATH.read_text(encoding="utf-8"))
    states = spec["states"]
    cmp_dir = args.out_dir / "comparisons"
    cmp_dir.mkdir(parents=True, exist_ok=True)

    missing: list[str] = []
    results: list[dict] = []
    overview_entries: list[tuple[str, Path]] = []

    for idx, state in enumerate(states, start=1):
        state_id = state["id"]
        ios_png = REPO_ROOT / state["iosReferencePng"]
        android_png = args.android_shots / f"{state_id}.png"
        if not ios_png.exists():
            missing.append(f"Missing iOS reference: {ios_png}")
            continue
        if not android_png.exists():
            missing.append(f"Missing Android Compose render: {android_png}")
            continue

        is_landscape = "viewportOverrideDp" in state
        out_cmp = cmp_dir / f"ANDROID_CMP_UE{idx:02d}.png"
        entry = build_side_by_side(
            idx_1based=idx,
            state_id=state_id,
            title=state["title"],
            ios_png=ios_png,
            android_png=android_png,
            out_png=out_cmp,
            is_landscape=is_landscape,
        )
        results.append(entry)
        overview_entries.append((state_id, android_png))

    if missing:
        for m in missing:
            print(f"[ERROR] {m}", file=sys.stderr)
        return 1

    overview_path = args.out_dir / "ANDROID_13_SCREENS_OVERVIEW.png"
    build_master_overview(overview_entries, overview_path)

    report = {
        "totalScreens": len(results),
        "overviewPng": str(overview_path.relative_to(REPO_ROOT)),
        "comparisons": results,
    }
    report_path = args.out_dir / "android_visual_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"[OK] Generated {len(results)}/13 iOS vs Android side-by-side comparisons -> {cmp_dir.relative_to(REPO_ROOT)}")
    print(f"[OK] Generated master gallery -> {overview_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
