#!/usr/bin/env python3
"""Android Native Material 3 Compose vs Official Android UE Board Side-by-Side Visual Comparison Builder.

Reads real Jetpack Compose PNG screenshots produced by `AndroidUeScreenshotTest` (Roborazzi)
under `apps/android/app/build/outputs/android_ue/` and compares every screen 1:1 against the
official Android UE boards under `docs/ue/android/*.png`:
  - Generates `ANDROID_CMP_<STATE_ID>.png` (and canonical `ANDROID_CMP_UE01..UE13.png`) for all 20 screens
  - Generates `ANDROID_20_SCREENS_OVERVIEW.png` and `ANDROID_13_SCREENS_OVERVIEW.png`
  - Emits structured `android_visual_report.json` with dimensions & pass/fail completeness checks
"""
from __future__ import annotations

import argparse
import json
import math
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
    label_prefix: str,
    state_id: str,
    title: str,
    ref_png: Path,
    android_png: Path,
    out_png: Path,
) -> dict:
    font_title = _load_font(20)
    font_sub = _load_font(15)

    panel_w, panel_h = 540, 1200
    pad = 24
    header_h = 76
    canvas_w = pad * 3 + panel_w * 2
    canvas_h = header_h + pad * 2 + panel_h

    canvas = Image.new("RGB", (canvas_w, canvas_h), (14, 14, 17))
    draw = ImageDraw.Draw(canvas)

    draw.text(
        (pad, 14),
        f"{label_prefix} · {state_id} — {title}",
        fill=(242, 242, 245),
        font=font_title,
    )
    draw.text(
        (pad, 44),
        f"LEFT: Official Android UE ({ref_png.name})",
        fill=(154, 154, 163),
        font=font_sub,
    )
    draw.text(
        (pad * 2 + panel_w, 44),
        "RIGHT: Android Native Jetpack Compose (Material 3)",
        fill=(141, 184, 255),
        font=font_sub,
    )

    with Image.open(ref_png) as ref_im:
        ref_size = ref_im.size
        ref_rgb = ref_im.convert("RGB").resize((panel_w, panel_h), Image.Resampling.LANCZOS)
    canvas.paste(ref_rgb, (pad, header_h + pad))
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
        outline=(141, 184, 255),
        width=2,
    )

    out_png.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_png, format="PNG")
    return {
        "stateId": state_id,
        "referenceUePng": str(ref_png.relative_to(REPO_ROOT)),
        "referenceSizePx": list(ref_size),
        "androidSizePx": list(android_size),
        "comparisonPng": str(out_png.relative_to(REPO_ROOT)),
    }


def build_master_overview(entries: list[tuple[str, Path]], output_path: Path, title_text: str) -> None:
    font_hdr = _load_font(26)
    font_lbl = _load_font(14)

    cols = 5 if len(entries) > 13 else 5
    rows = math.ceil(len(entries) / cols)
    thumb_w, thumb_h = 300, 666
    pad = 20
    label_h = 28
    header_h = 80

    canvas_w = cols * thumb_w + (cols + 1) * pad
    canvas_h = header_h + rows * (thumb_h + label_h + pad) + pad

    grid = Image.new("RGB", (canvas_w, canvas_h), (14, 14, 17))
    draw = ImageDraw.Draw(grid)
    draw.text((pad, 24), title_text, fill=(242, 242, 245), font=font_hdr)

    for idx, (state_id, img_path) in enumerate(entries):
        r = idx // cols
        c = idx % cols
        x = pad + c * (thumb_w + pad)
        y = header_h + r * (thumb_h + label_h + pad)
        with Image.open(img_path) as im:
            resized = im.convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        grid.paste(resized, (x, y))
        draw.rectangle([x - 1, y - 1, x + thumb_w, y + thumb_h], outline=(55, 62, 78), width=1)
        draw.text((x, y + thumb_h + 6), state_id, fill=(141, 184, 255), font=font_lbl)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    grid.save(output_path, format="PNG")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Android UE vs Compose visual comparison sheets.")
    parser.add_argument("--android-shots", type=Path, default=DEFAULT_ANDROID_SHOTS_DIR)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args()

    spec = json.loads(ANDROID_SPEC_PATH.read_text(encoding="utf-8"))
    canonical_states = spec["states"]
    extended_states = spec.get("extendedScreens", [])
    all_states = list(canonical_states) + list(extended_states)

    cmp_dir = args.out_dir / "comparisons"
    cmp_dir.mkdir(parents=True, exist_ok=True)

    missing: list[str] = []
    results: list[dict] = []
    canonical_entries: list[tuple[str, Path]] = []
    all_entries: list[tuple[str, Path]] = []

    for idx, state in enumerate(all_states, start=1):
        state_id = state["id"]
        ref_rel = state.get("androidReferencePng") or state.get("iosReferencePng")
        ref_png = REPO_ROOT / ref_rel
        android_png = args.android_shots / f"{state_id}.png"
        if not ref_png.exists():
            missing.append(f"Missing Android UE reference: {ref_png}")
            continue
        if not android_png.exists():
            missing.append(f"Missing Android Compose render: {android_png}")
            continue

        is_canonical = idx <= len(canonical_states)
        ue_code = state_id.split("_", 1)[0]
        out_name = f"ANDROID_CMP_{ue_code}.png" if is_canonical else f"ANDROID_CMP_{state_id}.png"
        out_cmp = cmp_dir / out_name
        label_prefix = f"ANDROID_CMP_{ue_code}" if is_canonical else f"ANDROID_CMP_{state_id}"
        entry = build_side_by_side(
            label_prefix=label_prefix,
            state_id=state_id,
            title=state["title"],
            ref_png=ref_png,
            android_png=android_png,
            out_png=out_cmp,
        )
        results.append(entry)
        all_entries.append((state_id, android_png))
        if is_canonical:
            canonical_entries.append((state_id, android_png))

    if missing:
        for m in missing:
            print(f"[ERROR] {m}", file=sys.stderr)
        return 1

    canonical_count = len(canonical_entries)
    total_count = len(all_entries)
    overview_canonical = args.out_dir / f"ANDROID_{canonical_count}_SCREENS_OVERVIEW.png"
    build_master_overview(
        canonical_entries,
        overview_canonical,
        f"AG Pocket Android — {canonical_count} Canonical Material 3 Jetpack Compose Gallery (UE01..UE13)",
    )
    overview_all = args.out_dir / f"ANDROID_{total_count}_SCREENS_OVERVIEW.png"
    build_master_overview(
        all_entries,
        overview_all,
        f"AG Pocket Android — {total_count}-Screen Native Material 3 Jetpack Compose Gallery (UE01..UE15)",
    )

    report = {
        "totalScreens": len(results),
        "canonicalScreens": canonical_count,
        "extendedScreens": total_count - canonical_count,
        "overviewPng": str(overview_canonical.relative_to(REPO_ROOT)),
        "overviewAllPng": str(overview_all.relative_to(REPO_ROOT)),
        "comparisons": results,
    }
    report_path = args.out_dir / "android_visual_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"[OK] Generated {len(results)}/{len(all_states)} Android UE vs Compose side-by-side comparisons -> {cmp_dir.relative_to(REPO_ROOT)}")
    print(f"[OK] Generated {total_count}-screen master gallery -> {overview_all.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
