"""Unified diff parser, GitHub RIGHT-side line mapper, and git patch-id rebase detector."""
from __future__ import annotations

import hashlib
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

from . import Finding, SEVERITY_RANK

HUNK_HEADER_RE = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


@dataclass
class FileDiff:
    path: str
    valid_right_lines: set[int] = field(default_factory=set)
    added_lines: dict[int, str] = field(default_factory=dict)
    patch_lines: list[str] = field(default_factory=list)

    @property
    def patch_text(self) -> str:
        return "\n".join(self.patch_lines)


def parse_unified_diff(diff_text: str) -> dict[str, FileDiff]:
    """Parses `git diff --unified=3` output into per-file commentable RIGHT lines and added lines."""
    files: dict[str, FileDiff] = {}
    current: FileDiff | None = None
    right_line = 0
    in_hunk = False

    for raw_line in diff_text.splitlines():
        if raw_line.startswith("diff --git "):
            current = None
            in_hunk = False
            continue
        if raw_line.startswith("+++ "):
            target = raw_line[4:].strip()
            if target == "/dev/null":
                current = None
                in_hunk = False
                continue
            if target.startswith("b/"):
                target = target[2:]
            # Handle git quoted paths cleanly
            if target.startswith('"') and target.endswith('"'):
                target = target[1:-1]
            current = files.setdefault(target, FileDiff(path=target))
            current.patch_lines.append(raw_line)
            in_hunk = False
            continue
        if raw_line.startswith("--- "):
            continue

        if current is None:
            continue

        m = HUNK_HEADER_RE.match(raw_line)
        if m:
            right_line = int(m.group(3))
            in_hunk = True
            current.patch_lines.append(raw_line)
            continue

        if not in_hunk:
            continue

        current.patch_lines.append(raw_line)
        if raw_line.startswith("+") and not raw_line.startswith("+++"):
            current.valid_right_lines.add(right_line)
            current.added_lines[right_line] = raw_line[1:]
            right_line += 1
        elif raw_line.startswith(" "):
            current.valid_right_lines.add(right_line)
            right_line += 1
        elif raw_line.startswith("-"):
            # Deleted line does not advance RIGHT line number
            continue
        elif raw_line.startswith("\\ No newline at end of file"):
            continue

    return files


def get_git_diff(repo_root: Path, base_ref: str, head_ref: str) -> str:
    """Computes unified diff between `base_ref` and `head_ref` (uses three-dot merge-base when possible)."""
    cmd = ["git", "diff", "--no-color", "--unified=3", f"{base_ref}...{head_ref}"]
    proc = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        # Fallback to two-dot diff when refs share no merge-base or are raw SHAs
        cmd_fallback = ["git", "diff", "--no-color", "--unified=3", base_ref, head_ref]
        proc = subprocess.run(cmd_fallback, cwd=repo_root, capture_output=True, text=True, check=True)
    return proc.stdout


def compute_patch_id(diff_text: str) -> str:
    """Computes a rebase-invariant patch ID using `git patch-id --verbatim` (Bluesky pattern)."""
    if not diff_text.strip():
        return ""
    proc = subprocess.run(
        ["git", "patch-id", "--verbatim"],
        input=diff_text,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode == 0 and proc.stdout.strip():
        return proc.stdout.strip().split()[0]

    # Deterministic pure-Python fallback if git patch-id is unavailable
    normalized: list[str] = []
    for line in diff_text.splitlines():
        if line.startswith(("diff --git", "index ", "@@ ")):
            continue
        normalized.append(line)
    return hashlib.sha1("\n".join(normalized).encode("utf-8")).hexdigest()


def is_pure_rebase(repo_root: Path, base_ref: str, before_sha: str, after_sha: str) -> bool:
    """Returns True when `base_ref...before_sha` and `base_ref...after_sha` have identical patch-id."""
    if not before_sha or not after_sha or before_sha == after_sha:
        return False
    try:
        before_diff = get_git_diff(repo_root, base_ref, before_sha)
        after_diff = get_git_diff(repo_root, base_ref, after_sha)
    except subprocess.CalledProcessError:
        return False
    before_id = compute_patch_id(before_diff)
    after_id = compute_patch_id(after_diff)
    return bool(before_id) and before_id == after_id


def map_findings_to_diff(
    findings: list[Finding],
    file_diffs: dict[str, FileDiff],
    max_inline: int = 8,
    min_inline_confidence: float = 0.80,
) -> tuple[list[Finding], list[Finding]]:
    """Splits findings into diff-validated inline comments (P0/P1, bounded) vs summary-only notes.

    Guarantees GitHub PR Review API will never receive an out-of-hunk line number (preventing HTTP 422).
    """
    sorted_findings = sorted(
        findings,
        key=lambda f: (
            SEVERITY_RANK.get(f.severity, 9),
            0 if f.source == "static" else 1,
            -f.confidence,
            f.file,
            f.line,
        ),
    )

    inline_eligible: list[Finding] = []
    summary_only: list[Finding] = []

    for finding in sorted_findings:
        fd = file_diffs.get(finding.file)
        in_hunk = bool(fd and finding.line in fd.valid_right_lines)
        finding.in_diff_hunk = in_hunk

        can_inline = (
            in_hunk
            and finding.severity in ("P0", "P1")
            and finding.confidence >= min_inline_confidence
            and len(inline_eligible) < max_inline
        )
        if can_inline:
            inline_eligible.append(finding)
        else:
            summary_only.append(finding)

    return inline_eligible, summary_only
