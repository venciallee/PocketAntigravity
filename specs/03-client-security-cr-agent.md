# 03 — Client + Security & Compliance GitHub CR Agent Architecture & Rulebook

## 1. Overview & Non-Negotiable Invariants

This specification defines the **Client (iOS Swift 6 / Android Kotlin / KMP) + Security & Compliance Code Review Agent** running on GitHub Actions for `venciallee/iOSAntigravity` (and designed to extract cleanly as an organization-level Reusable Workflow).

It synthesizes production patterns verified across Bitwarden (`bitwarden/ios`, `bitwarden/android`, `bitwarden/ai-plugins`), DuckDuckGo (`duckduckgo/Android`, `duckduckgo/apple-browsers`), Bluesky (`bluesky-social/social-app`), Mozilla (`mozilla-mobile/firefox-ios`), and Sentry (`getsentry/sentry-cocoa`, `getsentry/sentry-java`).

### Four Non-Negotiable Invariants
1. **Deterministic Hard Gate Cannot Be Overridden by LLM**: Secret scanning, license/CVE compliance, SAST rules, ATS/permission/manifest checks, repository guardrails, and CI workflow auditing run deterministically in **Layer 1**. LLM outputs may explain or add findings, never waive a Layer 1 `P0` failure.
2. **Information Isolation Across Specialist Agents**: The Architecture/Risk Brief and Security/Compliance agents receive PR title/description and threat context; the **Client Defect Specialist is strictly diff-only** (no PR description) to prevent author framing from biasing bug detection.
3. **Zero CI/Agent Self-Exposure**: Never check out untrusted PR code under `pull_request_target`. External fork PRs run without LLM secrets. All third-party Actions are pinned to full 40-char commit SHAs and audited by `zizmor`. Before invoking any LLM, a credential hygiene check verifies zero private keys or write tokens reside in readable workspace/temp paths.
4. **High Signal-to-Noise & Auditable Exemptions**: Pure rebases are skipped via `git patch-id --verbatim`. Inline comments are strictly bounded, diff-hunk verified (zero GitHub API `422` errors), and filtered by a dedicated Validator (`confidence >= 0.80` + explicit Do-Not-Report list). Security/compliance exemptions require structured `// cr-ignore: <RULE-ID> reason=<...> ticket=<...>` annotations surfaced in the Sticky Summary and guarded by `CODEOWNERS`.

## 2. Five-Stage Pipeline

1. **Stage 0 — Gatekeeper (`gatekeeper`)**:
   - Validates PR open/draft state and detects external forks (`is_fork`).
   - Computes `git patch-id --verbatim` between `base...before` and `base...after` on `synchronize` to skip pure rebases.
   - Runs `python3 scripts/run-cr-agent.py --validate-config --self-test` to guarantee schema & eval integrity.
2. **Stage 1 — Deterministic Security & Compliance Gate (`deterministic-security-gate`)**:
   - Runs `gitleaks/gitleaks-action` (secret scan), `actions/dependency-review-action` (license & CVE gate), optional Semgrep (`.github/cr-rules/semgrep-client-security.yml`), and `scripts/run-cr-agent.py --layer1-only` (including `verification/verify_compat_guardrails.py`, mobile security/privacy regex/AST checks, and `cr-ignore` exemption auditing).
   - Exports `static-findings.json` and `cr-agent.sarif` (SARIF 2.1.0 uploaded to GitHub Security -> Code Scanning).
3. **Stage 2 — Path-Scoped Context Router**:
   - Reads `.github/review-context.toml` to map changed files to targeted rulebooks and detect `high_risk_paths`.
   - Extracts valid `RIGHT`-side unified diff line numbers per file (`scripts/cr_agent/diff_line_mapper.py`) and existing Sticky Summary issues.
4. **Stage 3 — Information-Isolated Multi-Agent Core (`ai-review-agent`)**:
   - Runs credential hygiene verification (`SEC-CI-002`) and Prompt Injection boundary wrapping (`SEC-CI-003`).
   - Executes 4 passes when an LLM API key (`GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, or `OPENAI_API_KEY`) is present, or falls back cleanly to deterministic Layer 1 + heuristic Risk Brief when no key is configured:
     - **Agent A (Architect & Risk Brief)**: Independent `risk_level` / `impact_level` + human focus checklist.
     - **Agent B (Client Defect Specialist — Diff-Only)**: Swift 6 / UIKit / Extension / KMP / Android defects.
     - **Agent C (Security & Compliance Specialist)**: Semantic auth, crypto flow, privacy, deeplink, IPC, and store compliance defects.
     - **Agent D (Validator & Severity Auditor)**: Refutes false positives, enforces Do-Not-Report list, normalizes `P0/P1/P2`, and preserves all Layer 1 P0 findings.
5. **Stage 4 — Native GitHub Delivery & Governance**:
   - Upserts a single Sticky Summary comment (`<!-- client-sec-cr-agent:summary -->`) with Risk Brief, Layer 1 Gate table, Findings, Previous Issue Status, and Exemption Audit.
   - Submits up to 8 diff-validated Inline Review comments (`P0`/`P1`, `confidence >= 0.80`, with `suggestion` blocks).
   - Supports `CR_AGENT_MODE`: `comment` (default), `shadow` (artifact & step summary only), `label` (requires `ai-review` label), or `enforce` (blocks merge on `P0`).

## 3. Rule Taxonomy

- **Client Engineering (`CLI-*`)**:
  - `CLI-IOS-001`..`008`: Swift 6 concurrency/Sendable safety, MainActor/UI thread safety, retain cycles & Task cancellation, production force-unwraps (`try!`/`!`), App Extension memory & disallowed APIs, bidirectional Codable/RPC compatibility, silent `try?` write swallowing, UI animation/accessibility regressions.
  - `CLI-AND-001`..`007`: Coroutine scope leaks & `CancellationException` swallowing, main-thread blocking/ANR, Context/Flow lifecycle leaks, Compose recomposition/side-effects, Bundle size & `SavedStateHandle`, background/resource leaks, R8/ProGuard `@Keep`.
  - `CLI-KMP-001`..`004`: Cross-platform Flow/SKIE cancellation, Swift/Kotlin/Companion contract parity, `@Throws` boundary & `commonMain` purity, umbrella export bloat.
- **Security (`SEC-*`)**:
  - `SEC-DATA-001`..`005`: Hardcoded secrets, plaintext sensitive storage (`UserDefaults`/`SharedPreferences`), weak Keychain/Keystore attributes, sensitive logging/crash context, Lock Screen / Live Activity / clipboard leakage.
  - `SEC-NET-001`..`004`: TLS pinning/trust bypass, ATS/cleartext weakening, weak crypto/PRNG (MD5/SHA1/DES/ECB), WebView bridge/Origin/file access flaws.
  - `SEC-AUTH-001`..`003`: Face ID/BiometricPrompt bypass or fail-open, incomplete logout/account-switch cleanup, pairing/one-time token TTL & replay gaps.
  - `SEC-IPC-001`..`004`: Deeplink/URL scheme injection & Release exposure of debug routes, exported Android components, Extension/App Group trust boundary, SQL/command/path injection.
  - `SEC-CI-001`..`003`: Workflow injection/unpinned actions (`zizmor`), runner credential hygiene, Prompt Injection isolation.
- **Privacy, Store & Open-Source Compliance (`COMP-*`)**:
  - `COMP-PRIV-001`..`004`: Apple `PrivacyInfo.xcprivacy` Required Reason API alignment, system permission delta & justification, telemetry schema & identifier compliance, pre-consent SDK initialization red line.
  - `COMP-STORE-001`: Private APIs, dynamic executable code loading, foreground service type / 16KB page alignment.
  - `COMP-OSS-001`: Copyleft license blocklist (`GPL`/`AGPL`/`SSPL`), Critical/High CVE gating, `NOTICE`/attribution parity.
  - `COMP-AUDIT-001`: Structured exemption enforcement (`// cr-ignore: <RULE-ID> reason=<...> ticket=<...>`) with `CODEOWNERS` auditability.

## 4. Verification & Eval Harness

Run locally or in CI Gate 0:

```bash
python3 scripts/run-cr-agent.py --validate-config --self-test
```

The built-in eval suite (`scripts/cr_agent/eval_suite.py`) enforces:
- 100% P0 catch rate across representative iOS/Android/Plist/Security fixtures
- 0% false positives on clean compliant fixtures
- Valid structured `cr-ignore` exemption tracking and malformed suppression detection
- Exact unified diff hunk line mapping & out-of-hunk downgrade
- `git patch-id` rebase invariance
- Prompt injection defense & Layer 1 non-exemptability
- Valid SARIF 2.1.0 output schema
