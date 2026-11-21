"""Deterministic Layer 1 Mobile Security, Client Safety & Compliance Scanner + SARIF 2.1.0 Exporter.

Layer 1 findings are deterministic, cannot be hallucinated, and CANNOT be waived by LLM output.
Structured exemptions require `// cr-ignore: <RULE-ID> reason=<...> ticket=<...>` and are
audited in the PR summary for Security CODEOWNERS visibility.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from . import Exemption, Finding
from .diff_line_mapper import FileDiff

# Structured exemption annotation parser (standalone comment or trailing inline comment; ignores quoted strings/backticks)
CR_IGNORE_VALID_RE = re.compile(
    r"(?:^|\s)(?://|#)\s*cr-ignore:\s*([A-Z]+-[A-Z]+-\d{3})\s+reason=([^\s`\"'].*?)\s+ticket=([A-Za-z0-9_#/-]+)\s*$"
)
CR_IGNORE_ANY_RE = re.compile(r"(?:^|\s)(?://|#)\s*cr-ignore(?::|\s|$)", re.IGNORECASE)
BARE_SUPPRESSION_RE = re.compile(
    r"(?:^|\s)(?://\s*swiftlint:disable\b(?!.*reason=)|@Suppress\(\"[^\"]*Security[^\"]*\"\))"
)

TEST_OR_FIXTURE_MARKERS = (
    "/tests/",
    "tests/",
    "iosuitests/",
    "/fixtures/",
    "fixtures/",
    "/test/",
    "src/test/",
    "src/commontest/",
    "src/jvmtest/",
    "src/androidtest/",
    "eval_suite.py",
    "verification/mock_",
)

PLACEHOLDER_SECRET_MARKERS = (
    "example",
    "placeholder",
    "dummy",
    "mock",
    "sample",
    "changeme",
    "your_",
    "redacted",
    "xxxx",
    "test-token",
    "test_token",
    "fake",
)


@dataclass(frozen=True)
class PatternRule:
    rule_id: str
    category: str
    severity: str
    title: str
    impact: str
    regex: re.Pattern[str]
    extensions: tuple[str, ...]
    exclude_tests: bool = True
    path_prefix: str = ""
    suggestion: str = ""


STATIC_RULES: tuple[PatternRule, ...] = (
    # --- SEC-DATA-001: Hardcoded secrets / private keys ---
    PatternRule(
        rule_id="SEC-DATA-001",
        category="security",
        severity="P0",
        title="Private key material detected in source diff",
        impact="Committing private keys compromises transport/signing trust and requires immediate rotation.",
        regex=re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----"),
        extensions=(),
        exclude_tests=False,
    ),
    PatternRule(
        rule_id="SEC-DATA-001",
        category="security",
        severity="P0",
        title="High-confidence provider API key or GitHub token literal detected",
        impact="Hardcoded live tokens in client binaries or repositories can be extracted and abused.",
        regex=re.compile(r"\b(?:AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{24,}|AIza[0-9A-Za-z\-_]{35})\b"),
        extensions=(),
        exclude_tests=True,
    ),
    # --- SEC-DATA-002: Plaintext sensitive persistence ---
    PatternRule(
        rule_id="SEC-DATA-002",
        category="security",
        severity="P0",
        title="Sensitive credential stored in plaintext UserDefaults",
        impact="UserDefaults is stored unencrypted in app plist containers and included in device backups.",
        regex=re.compile(
            r'UserDefaults\.(?:standard|init\([^)]*\))\.set\([^,\n]+,\s*forKey:\s*"[^"]*(?:token|secret|password|passwd|pin|apikey|api_key|privatekey|csrf|credential)[^"]*"',
            re.IGNORECASE,
        ),
        extensions=(".swift",),
        suggestion="Store credentials via KeychainStore with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.",
    ),
    PatternRule(
        rule_id="SEC-DATA-002",
        category="security",
        severity="P0",
        title="Sensitive credential stored in plaintext SharedPreferences",
        impact="Plaintext SharedPreferences XML files can be extracted on rooted devices or via backups.",
        regex=re.compile(
            r'putString\(\s*"[^"]*(?:token|secret|password|passwd|pin|apikey|api_key|private_key|csrf|credential)[^"]*"',
            re.IGNORECASE,
        ),
        extensions=(".kt", ".java"),
        suggestion="Use EncryptedSharedPreferences backed by AndroidKeyStore.",
    ),
    # --- SEC-DATA-003: Weak Keychain / Android Backup attributes ---
    PatternRule(
        rule_id="SEC-DATA-003",
        category="security",
        severity="P0",
        title="Over-permissive Keychain accessibility attribute (kSecAttrAccessibleAlways*)",
        impact="Allows reading Keychain items while device is locked and is deprecated by Apple for security reasons.",
        regex=re.compile(r"\bkSecAttrAccessibleAlways(?:ThisDeviceOnly)?\b"),
        extensions=(".swift", ".m", ".mm"),
        suggestion="Use kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly or kSecAttrAccessibleWhenUnlockedThisDeviceOnly.",
    ),
    PatternRule(
        rule_id="SEC-DATA-003",
        category="security",
        severity="P1",
        title="Android manifest enables full app backup (`android:allowBackup=\"true\"`)",
        impact="Full backups can exfiltrate local app state unless strict dataExtractionRules exclude sensitive stores.",
        regex=re.compile(r'android:allowBackup\s*=\s*"true"'),
        extensions=(".xml",),
    ),
    # --- SEC-DATA-004: Sensitive logging ---
    PatternRule(
        rule_id="SEC-DATA-004",
        category="security",
        severity="P0",
        title="Potential secret/token interpolation in log output",
        impact="System logs and crash diagnostics are readable by attached tools and leak active user credentials.",
        regex=re.compile(
            r"(?:print|debugPrint|NSLog)\([^)\n]*\\\(\s*[^)\n]*(?:password|secret|csrfToken|authToken|apiKey|privateKey|bearerToken)\b",
            re.IGNORECASE,
        ),
        extensions=(".swift",),
    ),
    PatternRule(
        rule_id="SEC-DATA-004",
        category="security",
        severity="P0",
        title="Potential secret/token logged via Android Log.*",
        impact="Logcat output can expose credentials to debug tools or bug reports.",
        regex=re.compile(
            r'Log\.[dviwe]\([^)\n]*(?:\$|\+\s*)(?:password|secret|csrfToken|authToken|apiKey|privateKey|bearerToken|pin)\b',
            re.IGNORECASE,
        ),
        extensions=(".kt", ".java"),
    ),
    # --- SEC-NET-001: TLS verification bypass ---
    PatternRule(
        rule_id="SEC-NET-001",
        category="security",
        severity="P0",
        title="Unconditional TLS server trust acceptance bypasses certificate verification",
        impact="Disables TLS certificate validation and exposes the client to man-in-the-middle (MITM) attacks.",
        regex=re.compile(
            r"completionHandler\(\s*\.useCredential\s*,\s*URLCredential\(\s*trust:\s*challenge\.protectionSpace\.serverTrust!"
        ),
        extensions=(".swift",),
    ),
    PatternRule(
        rule_id="SEC-NET-001",
        category="security",
        severity="P0",
        title="Android HostnameVerifier blindly accepts all hostnames",
        impact="Disables TLS hostname verification, enabling MITM attacks with any valid CA certificate.",
        regex=re.compile(r"HostnameVerifier\s*\{\s*_?\s*,\s*_?\s*->\s*true\s*\}"),
        extensions=(".kt", ".java"),
    ),
    # --- SEC-NET-002: ATS / Cleartext weakening ---
    PatternRule(
        rule_id="SEC-NET-002",
        category="security",
        severity="P0",
        title="App Transport Security disabled globally (`NSAllowsArbitraryLoads: true`)",
        impact="Allows unencrypted HTTP traffic to arbitrary hosts and risks App Store security review rejection.",
        regex=re.compile(r"(?:NSAllowsArbitraryLoads\s*:\s*true|<key>NSAllowsArbitraryLoads</key>\s*<true\s*/>)", re.IGNORECASE),
        extensions=(".yml", ".yaml", ".plist"),
    ),
    PatternRule(
        rule_id="SEC-NET-002",
        category="security",
        severity="P0",
        title="Android cleartext traffic enabled (`usesCleartextTraffic=\"true\"`)",
        impact="Permits unencrypted HTTP network requests across the app.",
        regex=re.compile(r'android:usesCleartextTraffic\s*=\s*"true"'),
        extensions=(".xml",),
    ),
    # --- SEC-NET-003: Weak cryptography ---
    PatternRule(
        rule_id="SEC-NET-003",
        category="security",
        severity="P0",
        title="Weak cryptographic primitive (MD5 / SHA-1 / ECB) in Swift",
        impact="MD5, SHA-1, and ECB mode are cryptographically broken for integrity/confidentiality guarantees.",
        regex=re.compile(r"\b(?:Insecure\.(?:MD5|SHA1)|CC_MD5|CC_SHA1|kCCOptionECBMode)\b"),
        extensions=(".swift", ".m", ".mm"),
    ),
    PatternRule(
        rule_id="SEC-NET-003",
        category="security",
        severity="P0",
        title="Weak cryptographic algorithm (MD5 / SHA-1 / DES / RC4 / ECB) in Kotlin/Java",
        impact="Broken hash or cipher modes compromise confidentiality and tamper resistance.",
        regex=re.compile(
            r'(?:MessageDigest\.getInstance\(\s*"(?:MD5|SHA-?1)"\s*\)|Cipher\.getInstance\(\s*"[^"]*(?:DES|RC4|ECB)[^"]*"\s*\))'
        ),
        extensions=(".kt", ".java"),
    ),
    # --- SEC-CI-001: GitHub Actions injection / dangerous triggers ---
    PatternRule(
        rule_id="SEC-CI-001",
        category="security",
        severity="P0",
        title="Dangerous `pull_request_target` workflow trigger detected",
        impact="Checking out untrusted fork PR code under `pull_request_target` allows repository secret exfiltration.",
        regex=re.compile(r"^\s*pull_request_target\s*:"),
        extensions=(".yml", ".yaml"),
        exclude_tests=False,
        path_prefix=".github/workflows/",
    ),
    PatternRule(
        rule_id="SEC-CI-001",
        category="security",
        severity="P0",
        title="Untrusted GitHub event field interpolated directly in workflow shell",
        impact="Attacker-controlled PR title/body/branch names can execute arbitrary shell commands in CI.",
        regex=re.compile(r"\$\{\{\s*github\.event\.(?:pull_request|issue|comment)\.(?:title|body|head\.ref)\s*\}\}"),
        extensions=(".yml", ".yaml"),
        exclude_tests=False,
        path_prefix=".github/workflows/",
    ),
    # --- CLI-IOS-001 / CLI-IOS-004 / CLI-AND-001: Deterministic client defects ---
    PatternRule(
        rule_id="CLI-IOS-001",
        category="client",
        severity="P1",
        title="Unchecked Swift 6 concurrency bypass (`@unchecked Sendable` / `nonisolated(unsafe)`)",
        impact="Bypasses compiler data-race checking; requires verified lock synchronization or actor isolation.",
        regex=re.compile(r"(?:@unchecked\s+Sendable|\bnonisolated\s*\(\s*unsafe\s*\))"),
        extensions=(".swift",),
    ),
    PatternRule(
        rule_id="CLI-IOS-004",
        category="client",
        severity="P1",
        title="Force-try (`try!`) in production Swift path",
        impact="Any thrown runtime error immediately crashes the app process.",
        regex=re.compile(r"\btry!\s+"),
        extensions=(".swift",),
    ),
    PatternRule(
        rule_id="CLI-AND-001",
        category="client",
        severity="P1",
        title="Unstructured `GlobalScope` coroutine in production Kotlin code",
        impact="Coroutines launched on GlobalScope leak past lifecycle boundaries and cannot be cancelled cleanly.",
        regex=re.compile(r"\bGlobalScope\.(?:launch|async)\b"),
        extensions=(".kt",),
    ),
    # --- COMP-PRIV-002 / COMP-STORE-001: Privacy & Store Compliance ---
    PatternRule(
        rule_id="COMP-PRIV-002",
        category="compliance",
        severity="P1",
        title="New iOS/Android system permission declaration requires privacy review",
        impact="Adding permissions expands privacy surface and must pass least-privilege & App Store/Play Store disclosure checks.",
        regex=re.compile(r'(?:\bNS[A-Z][A-Za-z]+UsageDescription\s*:|<uses-permission\s+android:name=)'),
        extensions=(".yml", ".yaml", ".plist", ".xml"),
        exclude_tests=False,
    ),
    PatternRule(
        rule_id="COMP-STORE-001",
        category="compliance",
        severity="P0",
        title="Potential Apple private API or dynamic executable loading detected",
        impact="Using private selectors or dynamic `dlopen` of non-system binaries triggers App Store rejection.",
        regex=re.compile(r'(?:NSSelectorFromString\(\s*"_[A-Za-z]|dlopen\()'),
        extensions=(".swift", ".m", ".mm"),
    ),
)


def _is_test_or_fixture_path(path: str) -> bool:
    low = path.lower().replace("\\", "/")
    return any(marker in low for marker in TEST_OR_FIXTURE_MARKERS)


def _is_placeholder_line(line: str) -> bool:
    low = line.lower()
    return any(marker in low for marker in PLACEHOLDER_SECRET_MARKERS)


def _extract_comment_portion(line: str) -> str:
    """Returns the comment portion of a line outside string literals and backticks."""
    stripped = line.lstrip()
    if stripped.startswith(("//", "#")):
        return stripped
    in_quote: str | None = None
    escaped = False
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if escaped:
            escaped = False
            i += 1
            continue
        if ch == "\\" and in_quote is not None:
            escaped = True
            i += 1
            continue
        if in_quote is not None:
            if ch == in_quote:
                in_quote = None
            i += 1
            continue
        if ch in ('"', "'", "`"):
            in_quote = ch
            i += 1
            continue
        if ch == "#":
            return line[i:]
        if ch == "/" and i + 1 < n and line[i + 1] == "/":
            return line[i:]
        i += 1
    return ""


def _find_exemption_for_line(
    file_diff: FileDiff,
    line_no: int,
    rule_id: str,
) -> Exemption | None:
    """Checks current line and immediately preceding added line for structured `cr-ignore` exemption."""
    for candidate_line in (line_no, line_no - 1):
        comment_part = _extract_comment_portion(file_diff.added_lines.get(candidate_line, ""))
        if not comment_part:
            continue
        m = CR_IGNORE_VALID_RE.search(comment_part)
        if m and m.group(1) == rule_id:
            return Exemption(
                rule_id=rule_id,
                file=file_diff.path,
                line=candidate_line,
                reason=m.group(2).strip(),
                ticket=m.group(3).strip(),
                requires_security_approval=rule_id.startswith(("SEC-", "COMP-")),
            )
    return None


def scan_diff_static(
    file_diffs: dict[str, FileDiff],
    repo_root: Path | None = None,
    run_repo_guardrails: bool = True,
) -> tuple[list[Finding], list[Exemption], dict[str, Any]]:
    """Executes deterministic Layer 1 checks strictly on added diff lines + repo guardrails."""
    findings: list[Finding] = []
    exemptions: list[Exemption] = []
    seen_exemptions: set[tuple[str, str, int]] = set()
    counter = 0

    def next_id() -> str:
        nonlocal counter
        counter += 1
        return f"L1-{counter:03d}"

    for path, fdiff in sorted(file_diffs.items()):
        low_path = path.lower()
        is_test = _is_test_or_fixture_path(path)

        # 1. Audit structured exemptions & bare suppressions (COMP-AUDIT-001)
        for line_no, line_text in sorted(fdiff.added_lines.items()):
            comment_part = _extract_comment_portion(line_text)
            if comment_part and CR_IGNORE_ANY_RE.search(comment_part):
                m = CR_IGNORE_VALID_RE.search(comment_part)
                if m:
                    key = (m.group(1), path, line_no)
                    if key not in seen_exemptions:
                        seen_exemptions.add(key)
                        exemptions.append(
                            Exemption(
                                rule_id=m.group(1),
                                file=path,
                                line=line_no,
                                reason=m.group(2).strip(),
                                ticket=m.group(3).strip(),
                                requires_security_approval=m.group(1).startswith(("SEC-", "COMP-")),
                            )
                        )
                elif not is_test and not path.endswith(".md"):
                    findings.append(
                        Finding(
                            id=next_id(),
                            rule_id="COMP-AUDIT-001",
                            category="compliance",
                            severity="P1",
                            confidence=1.0,
                            source="static",
                            file=path,
                            line=line_no,
                            title="Malformed `cr-ignore` exemption annotation",
                            evidence=line_text.strip()[:200],
                            impact="Exemptions without `reason=` and `ticket=` cannot be audited by Security CODEOWNERS.",
                            suggestion="Use format: // cr-ignore: <RULE-ID> reason=<justification> ticket=<ISSUE-REF>",
                            tool="cr-agent-static",
                        )
                    )

            if not is_test and not path.endswith(".md") and (
                (comment_part and BARE_SUPPRESSION_RE.search(comment_part))
                or '@Suppress("' in line_text and BARE_SUPPRESSION_RE.search(line_text)
            ):
                findings.append(
                    Finding(
                        id=next_id(),
                        rule_id="COMP-AUDIT-001",
                        category="compliance",
                        severity="P1",
                        confidence=0.95,
                        source="static",
                        file=path,
                        line=line_no,
                        title="Unjustified linter/security suppression directive",
                        evidence=line_text.strip()[:200],
                        impact="Bare suppression directives bypass static checks without traceable justification.",
                        suggestion="Add an explicit justification (`reason=...`) or fix the underlying violation.",
                        tool="cr-agent-static",
                    )
                )

        # 2. Run deterministic pattern rules strictly on added lines
        for rule in STATIC_RULES:
            if rule.exclude_tests and is_test:
                continue
            if rule.path_prefix and not path.startswith(rule.path_prefix):
                continue
            if rule.extensions and not any(low_path.endswith(ext) for ext in rule.extensions):
                continue
            # Never flag documentation markdown prose on code pattern rules
            if low_path.endswith(".md") and rule.rule_id != "SEC-DATA-001":
                continue

            for line_no, line_text in sorted(fdiff.added_lines.items()):
                stripped = line_text.strip()
                if stripped.startswith(("//", "/*", "*", "#")) and rule.rule_id not in ("SEC-DATA-001", "SEC-CI-001"):
                    continue
                if rule.rule_id == "SEC-DATA-001" and _is_placeholder_line(line_text):
                    continue
                if not rule.regex.search(line_text):
                    continue

                ex = _find_exemption_for_line(fdiff, line_no, rule.rule_id)
                if ex is not None:
                    key = (ex.rule_id, ex.file, ex.line)
                    if key not in seen_exemptions:
                        seen_exemptions.add(key)
                        exemptions.append(ex)
                    continue

                findings.append(
                    Finding(
                        id=next_id(),
                        rule_id=rule.rule_id,
                        category=rule.category,
                        severity=rule.severity,
                        confidence=1.0,
                        source="static",
                        file=path,
                        line=line_no,
                        title=rule.title,
                        evidence=stripped[:220],
                        impact=rule.impact,
                        suggestion=rule.suggestion,
                        tool="cr-agent-static",
                    )
                )

    # 3. Integrate repository's native compatibility guardrails if present
    compat_status = "skipped"
    if run_repo_guardrails and repo_root is not None:
        guardrail_script = repo_root / "verification" / "verify_compat_guardrails.py"
        if guardrail_script.exists():
            proc = subprocess.run(
                [sys.executable, str(guardrail_script)],
                cwd=repo_root,
                capture_output=True,
                text=True,
                check=False,
            )
            if proc.returncode == 0:
                compat_status = "passed"
            else:
                compat_status = "failed"
                combined = (proc.stdout + "\n" + proc.stderr).strip()
                for line in combined.splitlines():
                    if "FAIL" in line or "error" in line.lower() or "❌" in line:
                        findings.append(
                            Finding(
                                id=next_id(),
                                rule_id="CLI-IOS-006",
                                category="client",
                                severity="P0",
                                confidence=1.0,
                                source="static",
                                file="Packages/AntigravityData/Sources/AntigravityData/Protocol/HostCapabilityRegistry.swift",
                                line=1,
                                title="Bidirectional compatibility guardrail violation",
                                evidence=line.strip()[:220],
                                impact="Violates repository RPC registration, resilient enum, live-write rollback, or bridge parity invariants.",
                                tool="verify_compat_guardrails",
                            )
                        )

    summary = {
        "files_scanned": len(file_diffs),
        "static_findings_total": len(findings),
        "static_p0_count": sum(1 for f in findings if f.severity == "P0"),
        "static_p1_count": sum(1 for f in findings if f.severity == "P1"),
        "exemptions_count": len(exemptions),
        "compat_guardrails_status": compat_status,
    }
    return findings, exemptions, summary


def ingest_semgrep_json(semgrep_path: Path, existing: list[Finding]) -> list[Finding]:
    """Ingests external Semgrep JSON output into unified Finding list with deduplication."""
    if not semgrep_path.exists():
        return []
    data = json.loads(semgrep_path.read_text(encoding="utf-8"))
    seen = {(f.rule_id, f.file, f.line) for f in existing}
    imported: list[Finding] = []
    idx = len(existing)
    for res in data.get("results", []):
        extra = res.get("extra", {})
        meta = extra.get("metadata", {})
        rule_id = str(meta.get("rule_id") or res.get("check_id", "SEC-SAST-000"))
        path = str(res.get("path", "")).lstrip("./")
        line = int(res.get("start", {}).get("line", 1))
        if (rule_id, path, line) in seen:
            continue
        seen.add((rule_id, path, line))
        sev_raw = str(meta.get("severity_level") or ("P0" if extra.get("severity") == "ERROR" else "P1"))
        sev = sev_raw if sev_raw in ("P0", "P1", "P2") else "P1"
        idx += 1
        imported.append(
            Finding(
                id=f"SG-{idx:03d}",
                rule_id=rule_id,
                category=str(meta.get("category", "security")),
                severity=sev,
                confidence=1.0,
                source="static",
                file=path,
                line=line,
                title=str(extra.get("message", rule_id))[:140],
                evidence=str(extra.get("lines", "")).strip()[:220],
                impact="Detected deterministically by Semgrep client security rules.",
                tool="semgrep",
            )
        )
    return imported


def export_sarif(findings: list[Finding], output_path: Path) -> dict[str, Any]:
    """Exports findings to SARIF 2.1.0 for GitHub Security -> Code Scanning Alerts."""
    level_map = {"P0": "error", "P1": "warning", "P2": "note"}
    rules_by_id: dict[str, dict[str, Any]] = {}
    results: list[dict[str, Any]] = []

    for f in findings:
        if f.rule_id not in rules_by_id:
            rules_by_id[f.rule_id] = {
                "id": f.rule_id,
                "name": f.rule_id,
                "shortDescription": {"text": f.title},
                "fullDescription": {"text": f.impact or f.title},
                "defaultConfiguration": {"level": level_map.get(f.severity, "warning")},
                "properties": {"tags": ["mobile", f.category, f.severity]},
            }
        results.append(
            {
                "ruleId": f.rule_id,
                "level": level_map.get(f.severity, "warning"),
                "message": {"text": f"[{f.severity}] {f.title}: {f.impact}"},
                "locations": [
                    {
                        "physicalLocation": {
                            "artifactLocation": {"uri": f.file},
                            "region": {"startLine": max(1, int(f.line))},
                        }
                    }
                ],
                "properties": {
                    "finding_id": f.id,
                    "source": f.source,
                    "confidence": f.confidence,
                    "tool": f.tool,
                },
            }
        )

    sarif = {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": "iOSAntigravity Client & Security CR Agent",
                        "version": "1.0.0",
                        "rules": list(rules_by_id.values()),
                    }
                },
                "results": results,
            }
        ],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(sarif, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return sarif
