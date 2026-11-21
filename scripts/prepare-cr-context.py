#!/usr/bin/env python3
"""Minimal Context & Gate Helper for Official `google-github-actions/run-gemini-cli` CR Workflow.

Responsibilities (intentionally tiny — zero LLM HTTP client or GitHub comment code!):
1. `--validate-config`: Validates `.github/review-context.toml`, `.gemini/commands/client-security-review.toml`,
   and all referenced `.github/cr-rules/*` files.
2. `--self-test`: Runs fast deterministic checks on config validation, dotfile glob matching, and patch-id invariance.
3. `--check-rebase`: Computes Bluesky-style `git patch-id --verbatim` to skip redundant reviews on pure rebases.
4. `--prepare`: Resolves path-matched rulebooks & `high_risk_paths` from `.github/review-context.toml`,
   bundles read-only Layer 1 Semgrep findings, and writes `.gemini/context.json` for `run-gemini-cli`.
"""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
CONTEXT_CFG_REL = ".github/review-context.toml"
GEMINI_CMD_REL = ".gemini/commands/client-security-review.toml"
SEMGREP_RULES_REL = ".github/cr-rules/semgrep-client-security.yml"


def _norm_path(path: str) -> str:
    norm = path.strip().replace("\\", "/")
    while norm.startswith("./"):
        norm = norm[2:]
    return norm


def _glob_to_regex(pattern: str) -> re.Pattern[str]:
    norm = pattern.strip().replace("\\", "/")
    i, n, out = 0, len(norm), ["^"]
    while i < n:
        c = norm[i]
        if c == "*":
            if i + 1 < n and norm[i + 1] == "*":
                if i + 2 < n and norm[i + 2] == "/":
                    out.append("(?:.*/)?")
                    i += 3
                    continue
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    out.append("$")
    return re.compile("".join(out))


def match_glob(path: str, pattern: str) -> bool:
    norm = _norm_path(path)
    return _glob_to_regex(pattern).match(norm) is not None or fnmatch.fnmatch(norm, pattern)


def validate_configs(repo_root: Path) -> list[str]:
    errors: list[str] = []
    cfg_path = repo_root / CONTEXT_CFG_REL
    if not cfg_path.exists():
        return [f"Missing {CONTEXT_CFG_REL}"]
    try:
        cfg = tomllib.loads(cfg_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"Invalid TOML in {CONTEXT_CFG_REL}: {exc}"]

    if cfg.get("version") != 1:
        errors.append(f"{CONTEXT_CFG_REL}: version must be 1")
    if not cfg.get("high_risk_paths", {}).get("patterns"):
        errors.append(f"{CONTEXT_CFG_REL}: [high_risk_paths].patterns must be non-empty")
    for idx, rule in enumerate(cfg.get("rules", [])):
        for entry in rule.get("load", []):
            rel = entry.get("path", "")
            if not rel or not (repo_root / rel).exists():
                errors.append(f"{CONTEXT_CFG_REL}: rules[{idx}] references missing file `{rel}`")

    cmd_path = repo_root / GEMINI_CMD_REL
    if not cmd_path.exists():
        errors.append(f"Missing {GEMINI_CMD_REL}")
    else:
        try:
            cmd_cfg = tomllib.loads(cmd_path.read_text(encoding="utf-8"))
            if not cmd_cfg.get("prompt"):
                errors.append(f"{GEMINI_CMD_REL}: missing `prompt` field")
        except Exception as exc:
            errors.append(f"Invalid TOML in {GEMINI_CMD_REL}: {exc}")

    if not (repo_root / SEMGREP_RULES_REL).exists():
        errors.append(f"Missing {SEMGREP_RULES_REL}")
    return errors


def compute_patch_id(diff_text: str) -> str:
    if not diff_text.strip():
        return ""
    proc = subprocess.run(["git", "patch-id", "--verbatim"], input=diff_text, capture_output=True, text=True, check=False)
    if proc.returncode == 0 and proc.stdout.strip():
        return proc.stdout.strip().split()[0]
    body = "\n".join(l for l in diff_text.splitlines() if not l.startswith(("diff --git", "index ", "@@ ")))
    return hashlib.sha1(body.encode("utf-8")).hexdigest()


def is_pure_rebase(repo_root: Path, base_ref: str, before_sha: str, after_sha: str) -> bool:
    if not before_sha or not after_sha or before_sha == after_sha:
        return False
    d1 = subprocess.run(["git", "diff", "--no-color", f"{base_ref}...{before_sha}"], cwd=repo_root, capture_output=True, text=True, check=False)
    d2 = subprocess.run(["git", "diff", "--no-color", f"{base_ref}...{after_sha}"], cwd=repo_root, capture_output=True, text=True, check=False)
    if d1.returncode != 0 or d2.returncode != 0:
        return False
    p1, p2 = compute_patch_id(d1.stdout), compute_patch_id(d2.stdout)
    return bool(p1) and p1 == p2


def prepare_gemini_context(
    repo_root: Path,
    repo: str,
    pr_number: str,
    changed_files: list[str],
    semgrep_json_path: Path | None,
    compat_status: str,
    additional_context: str,
) -> dict[str, Any]:
    cfg = tomllib.loads((repo_root / CONTEXT_CFG_REL).read_text(encoding="utf-8"))
    hr_patterns: list[str] = cfg.get("high_risk_paths", {}).get("patterns", [])
    high_risk_touched = [f for f in changed_files if any(match_glob(f, pat) for pat in hr_patterns)]

    matched_rules: list[str] = []
    client_paths: list[str] = []
    sec_paths: list[str] = []
    for rule in cfg.get("rules", []):
        any_file = rule.get("when", {}).get("any_file", {})
        includes = any_file.get("include", [])
        exts = [e.lower() for e in any_file.get("ext", [])]
        hit = any(
            (not includes or any(match_glob(f, p) for p in includes))
            and (not exts or any(f.lower().endswith(e) for e in exts))
            for f in changed_files
        )
        if not hit:
            continue
        matched_rules.append(rule["name"])
        spec = rule.get("specialist", "both")
        for entry in rule.get("load", []):
            p = entry["path"]
            if spec in ("client", "both") and p not in client_paths:
                client_paths.append(p)
            if spec in ("security", "both") and p not in sec_paths:
                sec_paths.append(p)

    layer1_findings: list[dict[str, Any]] = []
    if semgrep_json_path and semgrep_json_path.exists():
        raw = json.loads(semgrep_json_path.read_text(encoding="utf-8"))
        for r in raw.get("results", []):
            extra = r.get("extra", {})
            meta = extra.get("metadata", {})
            layer1_findings.append(
                {
                    "tool": "semgrep",
                    "rule_id": meta.get("rule_id", r.get("check_id")),
                    "severity": meta.get("severity_level", extra.get("severity")),
                    "file": r.get("path"),
                    "line": r.get("start", {}).get("line", 1),
                    "message": extra.get("message", ""),
                }
            )

    return {
        "repository": repo,
        "pull_request_number": pr_number,
        "additional_context": additional_context,
        "changed_files_count": len(changed_files),
        "high_risk_paths_touched": high_risk_touched,
        "matched_rules": matched_rules,
        "client_rules_markdown": "\n\n---\n\n".join(
            (repo_root / p).read_text(encoding="utf-8") for p in client_paths if (repo_root / p).exists()
        ),
        "security_rules_markdown": "\n\n---\n\n".join(
            (repo_root / p).read_text(encoding="utf-8") for p in sec_paths if (repo_root / p).exists()
        ),
        "layer1_static_findings": layer1_findings,
        "compat_guardrails_status": compat_status,
    }


def run_self_test(repo_root: Path) -> int:
    errs = validate_configs(repo_root)
    assert not errs, f"Config validation failed: {errs}"
    ctx = prepare_gemini_context(
        repo_root,
        repo="venciallee/iOSAntigravity",
        pr_number="1",
        changed_files=[
            "apps/ios/Packages/AntigravityData/Sources/AntigravityData/Protocol/PinnedTLSURLSessionDelegate.swift",
            "shared/core-protocol/src/commonMain/kotlin/Rpc.kt",
            "apps/android/app/src/main/AndroidManifest.xml",
            ".github/workflows/cr-agent.yml",
        ],
        semgrep_json_path=None,
        compat_status="passed",
        additional_context="",
    )
    assert ".github/workflows/cr-agent.yml" in ctx["high_risk_paths_touched"], "dotfile high-risk glob failed"
    assert "apps/android/app/src/main/AndroidManifest.xml" in ctx["high_risk_paths_touched"], "AndroidManifest high-risk glob failed"
    assert "CLI-IOS-001" in ctx["client_rules_markdown"], "client-ios rules missing"
    assert "CLI-KMP-001" in ctx["client_rules_markdown"], "client-kmp rules missing"
    assert "SEC-NET-001" in ctx["security_rules_markdown"], "security-compliance rules missing"
    d1 = "diff --git a/x.swift b/x.swift\n--- a/x.swift\n+++ b/x.swift\n@@ -10,0 +10,1 @@\n+let x = 1\n"
    d2 = "diff --git a/x.swift b/x.swift\n--- a/x.swift\n+++ b/x.swift\n@@ -90,0 +90,1 @@\n+let x = 1\n"
    assert compute_patch_id(d1) == compute_patch_id(d2) != "", "git patch-id rebase invariance failed"
    print("[CR-CONTEXT] Self-test PASSED (config schema, monorepo routing, rule bundling & patch-id invariance verified).")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="CR context & gate helper for run-gemini-cli")
    ap.add_argument("--validate-config", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--check-rebase", action="store_true")
    ap.add_argument("--prepare", action="store_true")
    ap.add_argument("--base-ref", default="origin/main")
    ap.add_argument("--before", default="")
    ap.add_argument("--after", default="")
    ap.add_argument("--base", default="origin/main")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--repo", default="")
    ap.add_argument("--pr", default="0")
    ap.add_argument("--semgrep-json", default="")
    ap.add_argument("--compat-status", default="passed")
    ap.add_argument("--additional-context", default="")
    ap.add_argument("--out", default=".gemini/context.json")
    ap.add_argument("--github-output", default="")
    ap.add_argument("--github-step-summary", default="")
    args = ap.parse_args()

    if args.validate_config:
        errs = validate_configs(REPO_ROOT)
        if errs:
            for e in errs:
                print(f"[CR-CONTEXT][ERROR] {e}", file=sys.stderr)
            return 1
        print("[CR-CONTEXT] Config validation PASSED.")

    if args.self_test:
        return run_self_test(REPO_ROOT)

    if args.check_rebase:
        pure = is_pure_rebase(REPO_ROOT, args.base_ref, args.before, args.after)
        if args.github_output:
            with open(args.github_output, "a", encoding="utf-8") as fh:
                fh.write(f"pure_rebase={'true' if pure else 'false'}\n")
        print(f"[CR-CONTEXT] pure_rebase={pure}")
        return 0

    if args.prepare:
        proc = subprocess.run(
            ["git", "diff", "--name-only", f"{args.base}...{args.head}"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            proc = subprocess.run(["git", "diff", "--name-only", args.base, args.head], cwd=REPO_ROOT, capture_output=True, text=True, check=True)
        changed = [_norm_path(line) for line in proc.stdout.splitlines() if line.strip()]
        ctx = prepare_gemini_context(
            REPO_ROOT,
            repo=args.repo,
            pr_number=str(args.pr),
            changed_files=changed,
            semgrep_json_path=Path(args.semgrep_json) if args.semgrep_json else None,
            compat_status=args.compat_status,
            additional_context=args.additional_context,
        )
        out_p = Path(args.out)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps(ctx, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(
            f"[CR-CONTEXT] Prepared {out_p}: files={len(changed)}, "
            f"high_risk={len(ctx['high_risk_paths_touched'])}, "
            f"rules={len(ctx['matched_rules'])}, layer1={len(ctx['layer1_static_findings'])}"
        )
        if args.github_step_summary:
            hr = ctx["high_risk_paths_touched"]
            md = [
                "### 🛡️ Client & Security CR Context Summary",
                f"- **Changed files**: {len(changed)}",
                f"- **Matched rule groups**: {', '.join(ctx['matched_rules']) or 'None'}",
                f"- **Layer 1 Semgrep findings**: {len(ctx['layer1_static_findings'])} | **Compat Guardrails**: `{ctx['compat_guardrails_status']}`",
            ]
            if hr:
                md.append("- **🚨 High-Risk Security/Architecture Paths Touched**:")
                md.extend(f"  - `{p}`" for p in hr)
            with open(args.github_step_summary, "a", encoding="utf-8") as fh:
                fh.write("\n".join(md) + "\n\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
