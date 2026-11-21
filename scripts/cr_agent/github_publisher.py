"""GitHub Sticky Summary Comment renderer and bounded Inline Review publisher."""
from __future__ import annotations

import json
import re
import subprocess
from typing import Any

from . import Finding, ReviewReport, STICKY_MARKER

PREV_FINDING_RE = re.compile(r"`([A-Z0-9]+-\d{3})`\s*\|\s*`([A-Z]+-[A-Z]+-\d{3})`\s*\|\s*`([^`]+):(\d+)`")

RISK_EMOJI = {"LOW": "🟢 LOW", "MEDIUM": "🟡 MEDIUM", "HIGH": "🔴 HIGH"}
SEV_BADGE = {"P0": "🚨 **P0 Blocker**", "P1": "⚠️ **P1 High**", "P2": "ℹ️ **P2 Medium**"}


def track_previous_issues(previous_comment_body: str, current_findings: list[Finding]) -> list[dict[str, str]]:
    """Compares previous sticky comment findings against current findings to track resolution status."""
    if not previous_comment_body:
        return []
    current_keys = {(f.rule_id, f.file, str(f.line)) for f in current_findings}
    current_rule_files = {(f.rule_id, f.file) for f in current_findings}
    statuses: list[dict[str, str]] = []
    seen: set[tuple[str, str, str]] = set()

    for m in PREV_FINDING_RE.finditer(previous_comment_body):
        fid, rule_id, fpath, fline = m.group(1), m.group(2), m.group(3), m.group(4)
        key = (rule_id, fpath, fline)
        if key in seen:
            continue
        seen.add(key)
        if key in current_keys or (rule_id, fpath) in current_rule_files:
            statuses.append({"id": fid, "rule_id": rule_id, "location": f"{fpath}:{fline}", "status": "open"})
        else:
            statuses.append({"id": fid, "rule_id": rule_id, "location": f"{fpath}:{fline}", "status": "resolved"})
    return statuses


def render_sticky_summary(report: ReviewReport) -> str:
    """Renders the single Sticky Summary Markdown comment updated in place on each PR push."""
    rb = report.risk_brief
    p0 = [f for f in report.findings if f.severity == "P0"]
    p1 = [f for f in report.findings if f.severity == "P1"]
    p2 = [f for f in report.findings if f.severity == "P2"]

    gate_status = "❌ **BLOCKED (P0 findings present)**" if p0 else "✅ **PASS (No P0 blockers)**"

    lines: list[str] = [
        STICKY_MARKER,
        "## 🛡️ Client & Security/Compliance CR Agent Report",
        "",
        f"| Gate Status | Risk | Impact | P0 / P1 / P2 | AI Review Engine | Commit |",
        "| :--- | :--- | :--- | :--- | :--- | :--- |",
        (
            f"| {gate_status} | {RISK_EMOJI.get(rb.risk_level, rb.risk_level)} | "
            f"{RISK_EMOJI.get(rb.impact_level, rb.impact_level)} | "
            f"**{len(p0)}** / **{len(p1)}** / **{len(p2)}** | "
            f"`{report.ai_provider}` (`{report.ai_status}`) | `{report.head_sha[:7] or 'local'}` |"
        ),
        "",
    ]

    if rb.summary:
        lines.extend([f"> {rb.summary}", ""])

    # High-risk paths touched (Sentry pattern)
    if rb.high_risk_paths_touched:
        lines.append("### 🚨 High-Risk Mobile Security / Architecture Paths Touched")
        lines.append("Changes to these surfaces require careful human verification:")
        for p in rb.high_risk_paths_touched:
            lines.append(f"- [ ] `{p}`")
        lines.append("")

    # Reviewer brief focus areas (Bluesky pattern)
    if rb.human_focus_areas:
        lines.append("### 🎯 Human Reviewer Focus Areas")
        for item in rb.human_focus_areas:
            lines.append(f"- {item}")
        lines.append("")

    # Findings table
    if report.findings:
        lines.append("### 🔍 Findings")
        lines.append("| ID | Rule | Location | Severity | Source | Summary |")
        lines.append("| :--- | :--- | :--- | :--- | :--- | :--- |")
        for f in report.findings:
            loc_suffix = "" if f.in_diff_hunk else " *(summary-only: outside diff hunk)*"
            safe_title = f.title.replace("|", "\\|")
            lines.append(
                f"| `{f.id}` | `{f.rule_id}` | `{f.file}:{f.line}`{loc_suffix} | "
                f"{SEV_BADGE.get(f.severity, f.severity)} | `{f.source}/{f.tool}` | {safe_title} |"
            )
        lines.append("")
    else:
        lines.extend(["### ✅ Findings", "No P0/P1/P2 client, security, or compliance defects detected in this diff.", ""])

    # Summary-only / downgraded findings details
    if report.summary_only_findings:
        lines.append("<details>")
        lines.append(f"<summary>📋 Detailed Notes for Summary-Only Findings ({len(report.summary_only_findings)})</summary>")
        lines.append("")
        for f in report.summary_only_findings:
            lines.append(f"- **`{f.id}` [{f.severity}] `{f.rule_id}`** at `{f.file}:{f.line}` — {f.title}")
            if f.impact:
                lines.append(f"  - **Impact**: {f.impact}")
            if f.evidence:
                lines.append(f"  - **Evidence**: `{f.evidence}`")
            if f.suggestion:
                lines.append(f"  - **Suggested Fix**: `{f.suggestion}`")
        lines.append("</details>")
        lines.append("")

    # Previous issues tracking (Bitwarden pattern)
    if report.previous_issues_status:
        lines.append("<details>")
        lines.append(f"<summary>🔄 Status of Previously Identified Issues ({len(report.previous_issues_status)})</summary>")
        lines.append("")
        for st in report.previous_issues_status:
            icon = "✅ Resolved" if st["status"] == "resolved" else "⏳ Still Open"
            lines.append(f"- {icon}: `{st['id']}` (`{st['rule_id']}`) at `{st['location']}`")
        lines.append("</details>")
        lines.append("")

    # Structured exemptions audit table (COMP-AUDIT-001)
    if report.exemptions_detected:
        lines.append("### ⚖️ Compliance Exemptions Detected (Security Sign-Off Required)")
        lines.append("| Rule | Location | Reason | Ticket | Security Approval |")
        lines.append("| :--- | :--- | :--- | :--- | :--- |")
        for ex in report.exemptions_detected:
            req = "🔐 Required (`CODEOWNERS`)" if ex.requires_security_approval else "Optional"
            safe_reason = ex.reason.replace("|", "\\|")
            lines.append(f"| `{ex.rule_id}` | `{ex.file}:{ex.line}` | {safe_reason} | `{ex.ticket}` | {req} |")
        lines.append("")

    l1 = report.layer1_summary
    if l1:
        lines.append(
            f"<sub>Layer 1 Deterministic Scan: {l1.get('files_scanned', 0)} file(s), "
            f"P0={l1.get('static_p0_count', 0)}, P1={l1.get('static_p1_count', 0)}, "
            f"Compat Guardrails=`{l1.get('compat_guardrails_status', 'n/a')}`</sub>"
        )
    return "\n".join(lines).strip() + "\n"


def format_inline_comment_body(finding: Finding) -> str:
    parts = [
        f"{SEV_BADGE.get(finding.severity, finding.severity)} · `{finding.rule_id}` (`{finding.source}/{finding.tool}`)",
        "",
        f"**{finding.title}**",
    ]
    if finding.impact:
        parts.extend(["", f"**Impact**: {finding.impact}"])
    if finding.evidence:
        parts.extend(["", f"**Evidence**: `{finding.evidence}`"])
    if finding.suggestion:
        if "\n" in finding.suggestion or any(tok in finding.suggestion for tok in ("guard ", "let ", "val ", "func ", "if ")):
            parts.extend(["", "```suggestion", finding.suggestion, "```"])
        else:
            parts.extend(["", f"**Recommended Fix**: {finding.suggestion}"])
    return "\n".join(parts)


def _gh_api_json(endpoint: str, method: str = "GET", payload: dict[str, Any] | None = None) -> Any:
    cmd = ["gh", "api", endpoint]
    if method != "GET":
        cmd.extend(["--method", method])
    if payload is not None:
        cmd.extend(["--input", "-"])
        proc = subprocess.run(cmd, input=json.dumps(payload), capture_output=True, text=True, check=False)
    else:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"gh api {method} {endpoint} failed: {proc.stderr.strip()}")
    return json.loads(proc.stdout) if proc.stdout.strip() else {}


def fetch_existing_sticky_comment(repo: str, pr_number: int) -> tuple[int | None, str]:
    comments = _gh_api_json(f"repos/{repo}/issues/{pr_number}/comments?per_page=100")
    if isinstance(comments, list):
        for c in comments:
            body = str(c.get("body", ""))
            if STICKY_MARKER in body:
                return int(c["id"]), body
    return None, ""


def publish_to_github(
    report: ReviewReport,
    repo: str,
    pr_number: int,
    head_sha: str,
    mode: str = "comment",
) -> dict[str, Any]:
    """Publishes Sticky Summary + deduplicated diff-valid Inline Comments to GitHub PR."""
    if mode == "shadow":
        return {"published": False, "mode": "shadow", "inline_posted": 0}

    sticky_id, prev_body = fetch_existing_sticky_comment(repo, pr_number)
    if prev_body:
        report.previous_issues_status = track_previous_issues(prev_body, report.findings)

    summary_md = render_sticky_summary(report)
    if sticky_id is not None:
        _gh_api_json(f"repos/{repo}/issues/comments/{sticky_id}", method="PATCH", payload={"body": summary_md})
    else:
        _gh_api_json(f"repos/{repo}/issues/{pr_number}/comments", method="POST", payload={"body": summary_md})

    # Avoid re-posting identical inline comments already present on the PR
    existing_inline = _gh_api_json(f"repos/{repo}/pulls/{pr_number}/comments?per_page=100")
    existing_keys: set[tuple[str, int, str]] = set()
    if isinstance(existing_inline, list):
        for c in existing_inline:
            c_path = str(c.get("path", ""))
            c_line = int(c.get("line") or c.get("original_line") or 0)
            c_body = str(c.get("body", ""))
            m = re.search(r"`([A-Z]+-[A-Z]+-\d{3})`", c_body)
            if m and c_path and c_line:
                existing_keys.add((c_path, c_line, m.group(1)))

    review_comments: list[dict[str, Any]] = []
    for f in report.inline_findings:
        if (f.file, f.line, f.rule_id) in existing_keys:
            continue
        review_comments.append(
            {
                "path": f.file,
                "line": f.line,
                "side": "RIGHT",
                "body": format_inline_comment_body(f),
            }
        )

    inline_posted = 0
    if review_comments:
        payload: dict[str, Any] = {
            "event": "COMMENT",
            "body": f"Client & Security CR Agent posted {len(review_comments)} inline finding(s) for `{head_sha[:7]}`.",
            "comments": review_comments,
        }
        if head_sha:
            payload["commit_id"] = head_sha
        _gh_api_json(f"repos/{repo}/pulls/{pr_number}/reviews", method="POST", payload=payload)
        inline_posted = len(review_comments)

    return {"published": True, "mode": mode, "sticky_updated": sticky_id is not None, "inline_posted": inline_posted}
