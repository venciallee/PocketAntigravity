#!/usr/bin/env python3
"""Headless Cloud Agent Orchestrator for Antigravity Doc Sync (`scripts/run-doc-sync-agent.py`).

Invoked by `.github/workflows/antigravity-doc-sync.yml` when `sync-antigravity-docs.py`
detects a meaningful upstream delta.

Execution priority:
1. `--dry-run`: Deterministically scaffolds `specs/deltas/<version>/01-prd-gap-analysis.md`,
   `02-tech-design.md`, and `03-test-plan.md` from `delta-report.json` without external LLM calls.
2. Live Cloud CI mode:
   - Prefers official Antigravity CLI headless mode (`agy -p <prompt>`) when `agy` is installed.
   - Falls back to `google-antigravity` Python SDK (`Agent` + `LocalAgentConfig`) when `GEMINI_API_KEY`
     or Vertex AI ADC is present.
   - Enforces the 3-tier delivery guardrail (`max_tier`: `tier1` -> Ready PR, `tier2` -> Draft PR,
     `tier3` -> RFC Issue / Specs Only).
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SKILL_PATH = REPO_ROOT / ".agents" / "skills" / "antigravity-doc-sync" / "SKILL.md"


def resolve_spec_target_dir(delta_report: dict, output_root: Path) -> tuple[str, Path]:
    """Resolves a non-clobbering specs directory so existing handcrafted release specs are never overwritten."""
    raw_ver = (
        delta_report.get("detected_app_version")
        or delta_report.get("latest_version")
        or "v-dry-run"
    )
    version = f"v{raw_ver}" if raw_ver and raw_ver[0].isdigit() else raw_ver
    target_dir = output_root / version
    if (target_dir / "01-prd-gap-analysis.md").exists():
        prev_cli = delta_report.get("previous_cli_version") or ""
        det_cli = delta_report.get("detected_cli_version") or ""
        if det_cli and det_cli != prev_cli:
            return version, output_root / f"{version}-cli-{det_cli}"
        checked = (delta_report.get("checked_at_utc") or "")[:10].replace("-", "")
        suffix = checked if len(checked) == 8 else datetime.now(timezone.utc).strftime("%Y%m%d")
        return version, output_root / f"{version}-delta-{suffix}"
    return version, target_dir


def build_agent_prompt(delta_report: dict, delta_summary_md: str, max_tier: str) -> str:
    version, target_dir = resolve_spec_target_dir(delta_report, REPO_ROOT / "specs" / "deltas")
    try:
        target_rel = target_dir.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        target_rel = f"specs/deltas/{version}"
    skill_text = SKILL_PATH.read_text(encoding="utf-8") if SKILL_PATH.exists() else ""
    return f"""You are running in automated pure-cloud GitHub Actions Doc-Sync mode for `venciallee/iOSAntigravity`.

Follow EVERY rule in `.agents/skills/antigravity-doc-sync/SKILL.md` and `AGENTS.md`:

<SKILL>
{skill_text}
</SKILL>

<UPSTREAM_DELTA_SUMMARY>
{delta_summary_md}
</UPSTREAM_DELTA_SUMMARY>

Target Release: `{version}`
Allowed Implementation Ceiling: `{max_tier}`

Execute the 4 stages strictly in order:
1. Write `{target_rel}/01-prd-gap-analysis.md` (with Tier 1 / Tier 2 / Tier 3 classification).
2. Write `{target_rel}/02-tech-design.md` (pure Swift 6 in `Packages/AntigravityData`, zero UIKit/WebKit/AVFoundation imports, preserving 13 states in `specs/esdd-ir.json`).
3. Write `{target_rel}/03-test-plan.md` (XCTest + mock Connect-RPC + ESDD test cases).
4. Implement all items at or below `{max_tier}` (leave Tier 3 items as RFC specs only), update unit & mock tests, and run:
   - `python3 verification/verify-live-rpc-flow.py`
   - `python3 verification/verify-v233-capabilities.py`
   - `python3 verification/esdd-verify.py`
Do not commit broken code. Summarize exact changed files and verification results when finished.
"""


def scaffold_dry_run_specs(delta_report: dict, delta_summary_md: str, output_root: Path) -> Path:
    version, target_dir = resolve_spec_target_dir(delta_report, output_root)
    target_dir.mkdir(parents=True, exist_ok=True)
    items = delta_report.get("items", [])

    tier1 = [i for i in items if i.get("tier") == "tier1"]
    tier2 = [i for i in items if i.get("tier") == "tier2"]
    tier3 = [i for i in items if i.get("tier") == "tier3"]

    prd = [
        f"# Auto-Generated PRD & Gap Analysis — Antigravity {version}",
        "",
        delta_summary_md.strip(),
        "",
        "## Delivery Triage Summary",
        f"- **Tier 1 (Auto Ready PR)**: {len(tier1)} item(s)",
        f"- **Tier 2 (Draft PR + Protocol Probe)**: {len(tier2)} item(s)",
        f"- **Tier 3 (RFC Issue Only)**: {len(tier3)} item(s)",
        "",
    ]
    (target_dir / "01-prd-gap-analysis.md").write_text("\n".join(prd), encoding="utf-8")

    tech = [
        f"# Auto-Generated Technical Design — Antigravity {version}",
        "",
        "## Module Mapping",
        "- `Packages/AntigravityData/`: Pure Swift 6 domain models, RPC payloads, Protobuf decoding (zero UIKit/WebKit/AVFoundation).",
        "- `iOS/`: SwiftUI views & sheets bound to `AntigravitySessionStore` (dual-track live vs `--ui-verify`).",
        "- `verification/`: `mock_language_server.py`, `verify-v233-capabilities.py`, and `esdd-verify.py`.",
        "",
        "## Tier 2 Protocol Probe Checklist",
        *[f"- [ ] Capture live `LanguageServerService` schema for: {it['summary']}" for it in tier2],
        *(["- None required for this release."] if not tier2 else []),
        "",
    ]
    (target_dir / "02-tech-design.md").write_text("\n".join(tech), encoding="utf-8")

    test_plan = [
        f"# Auto-Generated Test Plan — Antigravity {version}",
        "",
        "## Verification Gates",
        "1. `python3 scripts/sync-antigravity-docs.py --self-test`",
        "2. `python3 verification/verify-live-rpc-flow.py`",
        "3. `python3 verification/verify-v233-capabilities.py`",
        "4. `python3 verification/esdd-verify.py`",
        "5. GitHub Actions `macos-15` `swift test` + `xcodebuild` + `XCUITest` (`macos-xcode-verify.yml`)",
        "",
    ]
    (target_dir / "03-test-plan.md").write_text("\n".join(test_plan), encoding="utf-8")
    return target_dir


async def run_with_python_sdk(prompt: str) -> int:
    from google.antigravity import Agent, LocalAgentConfig  # type: ignore

    use_vertex = os.environ.get("GOOGLE_GENAI_USE_VERTEXAI", "").lower() in ("1", "true", "yes")
    api_key = os.environ.get("GEMINI_API_KEY")
    cfg = LocalAgentConfig(
        vertex=use_vertex,
        api_key=api_key,
        system_instructions="You are an expert Swift 6 iOS & Connect-RPC engineer maintaining iOSAntigravity.",
    )
    async with Agent(cfg) as agent:
        response = await agent.chat(prompt)
        print(await response.text())
    return 0


def run_with_agy_cli(prompt: str) -> int:
    agy_bin = shutil.which("agy")
    if not agy_bin:
        return -1
    cmd = [agy_bin, "-p", prompt]
    proc = subprocess.run(cmd, cwd=REPO_ROOT, check=False)
    return proc.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="Run headless cloud doc-sync agent")
    parser.add_argument("--delta-json", type=Path, required=True)
    parser.add_argument("--delta-md", type=Path, required=True)
    parser.add_argument("--max-tier", choices=["tier1", "tier2"], default="tier1")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--dry-run-out", type=Path, default=REPO_ROOT / "verification" / "output" / "doc-sync-dry-run")
    args = parser.parse_args()

    delta_report = json.loads(args.delta_json.read_text(encoding="utf-8"))
    delta_md = args.delta_md.read_text(encoding="utf-8")

    if args.dry_run:
        out_dir = scaffold_dry_run_specs(delta_report, delta_md, args.dry_run_out)
        print(f"[DRY-RUN] Generated structured PRD/Tech/Test delta specs in {out_dir}")
        return 0

    prompt = build_agent_prompt(delta_report, delta_md, args.max_tier)
    if shutil.which("agy"):
        print("[*] Running headless Antigravity CLI (`agy -p`)...")
        return run_with_agy_cli(prompt)

    try:
        print("[*] Running Google Antigravity Python SDK (`google-antigravity`)...")
        return asyncio.run(run_with_python_sdk(prompt))
    except ImportError:
        print(
            "[!] Neither `agy` CLI nor `google-antigravity` Python SDK is installed; falling back to deterministic spec scaffolding.",
            file=sys.stderr,
        )
        out_dir = scaffold_dry_run_specs(delta_report, delta_md, REPO_ROOT / "specs" / "deltas")
        print(f"[FALLBACK] Generated delta specs in {out_dir}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
