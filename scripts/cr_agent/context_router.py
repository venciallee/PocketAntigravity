"""Declarative path-to-rule Context Router backed by `.github/review-context.toml` (Firefox iOS pattern)."""
from __future__ import annotations

import fnmatch
import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class RoutedContext:
    high_risk_files: list[str] = field(default_factory=list)
    matched_rule_names: list[str] = field(default_factory=list)
    client_rule_paths: list[str] = field(default_factory=list)
    security_rule_paths: list[str] = field(default_factory=list)
    client_rules_text: str = ""
    security_rules_text: str = ""


def _glob_to_regex(pattern: str) -> re.Pattern[str]:
    """Converts a gitignore/GitHub glob pattern supporting `**/` accurately to regex."""
    norm = pattern.strip().replace("\\", "/")
    i = 0
    n = len(norm)
    out = ["^"]
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


def _normalize_repo_path(path: str) -> str:
    norm = path.strip().replace("\\", "/")
    while norm.startswith("./"):
        norm = norm[2:]
    return norm


def match_glob(path: str, pattern: str) -> bool:
    norm_path = _normalize_repo_path(path)
    if _glob_to_regex(pattern).match(norm_path) is not None:
        return True
    return fnmatch.fnmatch(norm_path, pattern)


def load_review_context_config(repo_root: Path, config_rel: str = ".github/review-context.toml") -> dict[str, Any]:
    config_path = repo_root / config_rel
    if not config_path.exists():
        raise FileNotFoundError(f"Review context config not found: {config_path}")
    with config_path.open("rb") as fh:
        return tomllib.load(fh)


def validate_review_context(repo_root: Path, config_rel: str = ".github/review-context.toml") -> list[str]:
    """Validates `.github/review-context.toml` schema and verifies all referenced rule files exist."""
    errors: list[str] = []
    try:
        cfg = load_review_context_config(repo_root, config_rel)
    except Exception as exc:
        return [f"Failed to parse {config_rel}: {exc}"]

    if cfg.get("version") != 1:
        errors.append(f"{config_rel}: `version` must be 1 (got {cfg.get('version')!r})")

    high_risk = cfg.get("high_risk_paths", {})
    patterns = high_risk.get("patterns", [])
    if not isinstance(patterns, list) or not patterns:
        errors.append(f"{config_rel}: `[high_risk_paths].patterns` must be a non-empty list")

    rules = cfg.get("rules", [])
    if not isinstance(rules, list) or not rules:
        errors.append(f"{config_rel}: `[[rules]]` must contain at least one rule")
        return errors

    for idx, rule in enumerate(rules):
        name = rule.get("name")
        if not name or not isinstance(name, str):
            errors.append(f"{config_rel}: rules[{idx}] missing string `name`")
        specialist = rule.get("specialist", "both")
        if specialist not in ("client", "security", "both"):
            errors.append(f"{config_rel}: rules[{idx}] invalid specialist {specialist!r}")

        when = rule.get("when", {})
        any_file = when.get("any_file", {})
        if not isinstance(any_file, dict) or (not any_file.get("include") and not any_file.get("ext")):
            errors.append(f"{config_rel}: rules[{idx}] ({name}) must specify `when.any_file.include` or `ext`")

        loads = rule.get("load", [])
        if not isinstance(loads, list) or not loads:
            errors.append(f"{config_rel}: rules[{idx}] ({name}) missing `load` entries")
            continue

        for entry in loads:
            rel_path = entry.get("path")
            if not rel_path or not isinstance(rel_path, str):
                errors.append(f"{config_rel}: rules[{idx}] ({name}) load entry missing `path`")
                continue
            if not (repo_root / rel_path).exists():
                errors.append(f"{config_rel}: rules[{idx}] ({name}) references missing file `{rel_path}`")

    return errors


def _rule_matches_files(rule: dict[str, Any], changed_files: list[str]) -> bool:
    any_file = rule.get("when", {}).get("any_file", {})
    includes: list[str] = any_file.get("include", [])
    exts: list[str] = [e.lower() for e in any_file.get("ext", [])]

    for path in changed_files:
        norm = _normalize_repo_path(path)
        include_ok = True if not includes else any(match_glob(norm, pat) for pat in includes)
        ext_ok = True if not exts else any(norm.lower().endswith(ext) for ext in exts)
        if include_ok and ext_ok:
            return True
    return False


def route_context(
    repo_root: Path,
    changed_files: list[str],
    config_rel: str = ".github/review-context.toml",
) -> RoutedContext:
    """Computes high-risk files and dynamically loads only path-matched client & security rulebooks."""
    cfg = load_review_context_config(repo_root, config_rel)
    routed = RoutedContext()

    hr_patterns: list[str] = cfg.get("high_risk_paths", {}).get("patterns", [])
    for path in changed_files:
        norm = _normalize_repo_path(path)
        if any(match_glob(norm, pat) for pat in hr_patterns):
            routed.high_risk_files.append(norm)

    client_paths: list[str] = []
    security_paths: list[str] = []

    for rule in cfg.get("rules", []):
        if not _rule_matches_files(rule, changed_files):
            continue
        routed.matched_rule_names.append(rule["name"])
        specialist = rule.get("specialist", "both")
        for entry in rule.get("load", []):
            p = entry["path"]
            if specialist in ("client", "both") and p not in client_paths:
                client_paths.append(p)
            if specialist in ("security", "both") and p not in security_paths:
                security_paths.append(p)

    routed.client_rule_paths = client_paths
    routed.security_rule_paths = security_paths
    routed.client_rules_text = "\n\n---\n\n".join(
        f"<!-- RULE FILE: {p} -->\n{(repo_root / p).read_text(encoding='utf-8')}"
        for p in client_paths
        if (repo_root / p).exists()
    )
    routed.security_rules_text = "\n\n---\n\n".join(
        f"<!-- RULE FILE: {p} -->\n{(repo_root / p).read_text(encoding='utf-8')}"
        for p in security_paths
        if (repo_root / p).exists()
    )
    return routed
