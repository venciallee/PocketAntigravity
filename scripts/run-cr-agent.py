#!/usr/bin/env python3
"""Headless Client (iOS / Android / KMP) + Security & Compliance GitHub CR Agent CLI.

Examples:
  # Validate `.github/review-context.toml` & run full offline eval suite (CI Gate 0)
  python3 scripts/run-cr-agent.py --validate-config --self-test

  # Check whether a synchronize push is a pure rebase (Bluesky `git patch-id` pattern)
  python3 scripts/run-cr-agent.py --check-rebase --base-ref main --before <sha1> --after <sha2>

  # Run deterministic Layer 1 security & compliance scan + SARIF export
  python3 scripts/run-cr-agent.py --layer1-only --base origin/main --head HEAD \
      --json-out /tmp/static-findings.json --sarif-out /tmp/cr-agent.sarif

  # Run full Layer 1 + Layer 2 multi-agent review & publish Sticky Summary + Inline Comments
  python3 scripts/run-cr-agent.py --base <base_sha> --head <head_sha> --pr 42 \
      --repo venciallee/iOSAntigravity --mode comment --publish --fail-on P0
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "scripts"))

from cr_agent import Finding, ReviewReport, SEVERITY_RANK  # noqa: E402
from cr_agent.context_router import route_context, validate_review_context  # noqa: E402
from cr_agent.diff_line_mapper import (  # noqa: E402
    get_git_diff,
    is_pure_rebase,
    map_findings_to_diff,
    parse_unified_diff,
)
from cr_agent.eval_suite import run_eval_suite  # noqa: E402
from cr_agent.github_publisher import publish_to_github, render_sticky_summary  # noqa: E402
from cr_agent.llm_reviewer import run_multi_agent_review  # noqa: E402
from cr_agent.static_scanner import export_sarif, ingest_semgrep_json, scan_diff_static  # noqa: E402


def _load_findings_json(path: Path) -> list[Finding]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    items = data.get("findings", []) if isinstance(data, dict) else data
    out: list[Finding] = []
    for raw in items:
        if isinstance(raw, dict):
            out.append(Finding(**raw))
    return out


def _write_github_output(output_path: str, pairs: dict[str, str]) -> None:
    if not output_path:
        return
    with open(output_path, "a", encoding="utf-8") as fh:
        for k, v in pairs.items():
            fh.write(f"{k}={v}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Client + Security/Compliance GitHub CR Agent")
    parser.add_argument("--validate-config", action="store_true", help="Validate .github/review-context.toml and rulebooks")
    parser.add_argument("--self-test", action="store_true", help="Run offline unit & eval regression suite")
    parser.add_argument("--check-rebase", action="store_true", help="Check if before->after is a pure rebase via git patch-id")
    parser.add_argument("--base-ref", default="origin/main", help="Base branch ref for rebase check")
    parser.add_argument("--before", default="", help="Before commit SHA on synchronize event")
    parser.add_argument("--after", default="", help="After commit SHA on synchronize event")
    parser.add_argument("--base", default="origin/main", help="Base ref/SHA for PR diff")
    parser.add_argument("--head", default="HEAD", help="Head ref/SHA for PR diff")
    parser.add_argument("--pr", type=int, default=0, help="Pull request number")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""), help="GitHub owner/repo")
    parser.add_argument("--pr-title", default=os.environ.get("PR_TITLE", ""), help="PR title (treated as untrusted data)")
    parser.add_argument("--pr-body", default=os.environ.get("PR_BODY", ""), help="PR body (treated as untrusted data)")
    parser.add_argument("--layer1-only", action="store_true", help="Run deterministic Layer 1 scan only (no LLM)")
    parser.add_argument("--dry-run", action="store_true", help="Skip external LLM API calls and GitHub publishing")
    parser.add_argument("--semgrep-json", default="", help="Optional path to external Semgrep JSON output")
    parser.add_argument("--static-findings-in", default="", help="Optional precomputed Layer 1 JSON path")
    parser.add_argument("--json-out", default="", help="Path to write structured JSON report")
    parser.add_argument("--sarif-out", default="", help="Path to write SARIF 2.1.0 report")
    parser.add_argument("--summary-md-out", default="", help="Path to write Markdown sticky summary")
    parser.add_argument("--github-output", default="", help="Path to $GITHUB_OUTPUT file")
    parser.add_argument("--github-step-summary", default="", help="Path to $GITHUB_STEP_SUMMARY file")
    parser.add_argument("--mode", choices=["shadow", "comment", "enforce"], default="comment", help="Publishing & gating mode")
    parser.add_argument("--publish", action="store_true", help="Publish Sticky Summary & Inline Comments to GitHub PR")
    parser.add_argument("--fail-on", choices=["none", "P0", "P1"], default="P0", help="Severity threshold that exits non-zero")
    args = parser.parse_args()

    # 1. Config validation
    if args.validate_config:
        errors = validate_review_context(REPO_ROOT)
        semgrep_cfg = REPO_ROOT / ".github" / "cr-rules" / "semgrep-client-security.yml"
        if not semgrep_cfg.exists():
            errors.append("Missing .github/cr-rules/semgrep-client-security.yml")
        if errors:
            for err in errors:
                print(f"[CR-AGENT][CONFIG ERROR] {err}", file=sys.stderr)
            return 1
        print("[CR-AGENT] Config validation PASSED (.github/review-context.toml + rulebooks verified).")

    # 2. Offline eval suite
    if args.self_test:
        eval_res = run_eval_suite(REPO_ROOT)
        for case in eval_res["cases"]:
            status = "PASS" if case["passed"] else "FAIL"
            print(f"  [{status}] {case['name']} — {case['detail']}")
        print(
            f"[CR-AGENT] Eval Suite: {eval_res['passed']}/{eval_res['total']} passed "
            f"(P0 Catch Rate: {eval_res['p0_catch_rate'] * 100:.1f}%)"
        )
        if not eval_res["all_passed"]:
            return 1
        if not args.check_rebase and not args.layer1_only and not args.json_out and not args.publish:
            return 0

    if args.validate_config and not args.self_test and not args.check_rebase and not args.layer1_only and not args.json_out and not args.publish:
        return 0

    # 3. Pure rebase detection (Bluesky `git patch-id` pattern)
    if args.check_rebase:
        pure = is_pure_rebase(REPO_ROOT, args.base_ref, args.before, args.after)
        changed = "false" if pure else "true"
        print(f"[CR-AGENT] Rebase check: diff_changed={changed} (pure_rebase={pure})")
        _write_github_output(args.github_output, {"diff_changed": changed, "pure_rebase": str(pure).lower()})
        return 0

    # 4. Parse PR diff & route context
    diff_text = get_git_diff(REPO_ROOT, args.base, args.head)
    file_diffs = parse_unified_diff(diff_text)
    changed_files = sorted(file_diffs.keys())
    routed = route_context(REPO_ROOT, changed_files)

    # 5. Layer 1 Deterministic Scan
    if args.static_findings_in and Path(args.static_findings_in).exists():
        static_path = Path(args.static_findings_in)
        raw_static = json.loads(static_path.read_text(encoding="utf-8"))
        static_findings = _load_findings_json(static_path)
        _, exemptions, layer1_summary = scan_diff_static(file_diffs, repo_root=REPO_ROOT, run_repo_guardrails=False)
        if isinstance(raw_static, dict) and isinstance(raw_static.get("layer1_summary"), dict):
            layer1_summary = raw_static["layer1_summary"]
    else:
        static_findings, exemptions, layer1_summary = scan_diff_static(file_diffs, repo_root=REPO_ROOT)

    if args.semgrep_json:
        semgrep_imported = ingest_semgrep_json(Path(args.semgrep_json), static_findings)
        static_findings.extend(semgrep_imported)
        layer1_summary["semgrep_imported"] = len(semgrep_imported)
        layer1_summary["static_findings_total"] = len(static_findings)
        layer1_summary["static_p0_count"] = sum(1 for f in static_findings if f.severity == "P0")

    # 6. Layer 2 Multi-Agent Review (or deterministic fallback)
    risk_brief, all_findings, ai_status, ai_provider = run_multi_agent_review(
        repo_root=REPO_ROOT,
        file_diffs=file_diffs,
        routed=routed,
        static_findings=static_findings,
        pr_title=args.pr_title,
        pr_body=args.pr_body,
        dry_run=args.dry_run or args.layer1_only,
    )

    inline_findings, summary_only_findings = map_findings_to_diff(all_findings, file_diffs)

    report = ReviewReport(
        pr_number=args.pr,
        head_sha=args.head,
        ai_status=ai_status,
        ai_provider=ai_provider,
        risk_brief=risk_brief,
        findings=inline_findings + summary_only_findings,
        inline_findings=inline_findings,
        summary_only_findings=summary_only_findings,
        exemptions_detected=exemptions,
        layer1_summary=layer1_summary,
    )

    # 7. Write outputs (JSON / SARIF / Markdown / Step Summary)
    if args.json_out:
        out_p = Path(args.json_out)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps(report.to_dict(), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if args.sarif_out:
        export_sarif(report.findings, Path(args.sarif_out))

    summary_md = render_sticky_summary(report)
    if args.summary_md_out:
        md_p = Path(args.summary_md_out)
        md_p.parent.mkdir(parents=True, exist_ok=True)
        md_p.write_text(summary_md, encoding="utf-8")

    if args.github_step_summary:
        with open(args.github_step_summary, "a", encoding="utf-8") as fh:
            fh.write(summary_md + "\n")

    # 8. Publish to GitHub PR when requested
    if args.publish and not args.dry_run and args.repo and args.pr > 0:
        pub = publish_to_github(report, args.repo, args.pr, args.head, mode=args.mode)
        print(f"[CR-AGENT] GitHub publish result: {json.dumps(pub)}")

    p0_count = sum(1 for f in report.findings if f.severity == "P0")
    p1_count = sum(1 for f in report.findings if f.severity == "P1")
    print(
        f"[CR-AGENT] Complete: files={len(changed_files)}, findings={len(report.findings)} "
        f"(P0={p0_count}, P1={p1_count}), inline={len(inline_findings)}, "
        f"exemptions={len(exemptions)}, ai={ai_provider}/{ai_status}"
    )
    _write_github_output(
        args.github_output,
        {
            "p0_count": str(p0_count),
            "p1_count": str(p1_count),
            "total_findings": str(len(report.findings)),
            "high_risk_count": str(len(routed.high_risk_files)),
        },
    )

    # 9. Gate exit code
    if args.fail_on != "none":
        threshold = SEVERITY_RANK[args.fail_on]
        blocking = [f for f in report.findings if SEVERITY_RANK.get(f.severity, 9) <= threshold]
        if blocking:
            print(f"[CR-AGENT] FAIL: {len(blocking)} finding(s) at or above severity {args.fail_on}.", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
