# 03 — Client + Security & Compliance GitHub CR Agent (`run-gemini-cli` Architecture)

## 1. Overview & Design Principles

This specification defines the **Client (iOS Swift 6 / Android Kotlin / KMP) + Security & Compliance Code Review Agent** for `venciallee/iOSAntigravity`, built on **mature off-the-shelf tools** with zero custom LLM HTTP client or GitHub comment boilerplate:

- **Layer 1 (Deterministic Hard Gate — zero hallucination, non-exemptable by LLM)**:
  - `gitleaks/gitleaks-action` (secret scanning)
  - `actions/dependency-review-action` (High/Critical CVE & `GPL`/`AGPL`/`SSPL` license blocklist)
  - `semgrep` running `.github/cr-rules/semgrep-client-security.yml` with `--baseline-commit` → native **SARIF 2.1.0** uploaded to GitHub Code Scanning Security Tab (`github/codeql-action/upload-sarif@v4`)
  - `verification/verify_compat_guardrails.py` (native bidirectional protocol / enum / live-write guardrails)
  - `zizmorcore/zizmor-action` (`.github/workflows/zizmor.yml` — audits CI workflows themselves)
- **Layer 2 (Contextual Semantic Review — Official Google Gemini CLI + GitHub MCP Server)**:
  - `google-github-actions/run-gemini-cli` (pinned 40-char commit SHA) executing our custom slash command `.gemini/commands/client-security-review.toml` (`/client-security-review`)
  - **Strict Sandbox**: `"tools": { "core": [] }` (zero local shell or file write tools!) paired with official `ghcr.io/github/github-mcp-server` locked to 4 tools (`pull_request_read`, `get_file_contents`, `add_comment_to_pending_review`, `pull_request_review_write`) so Gemini can inspect cross-file callers while remaining completely isolated from runner credentials.
  - **Path-Scoped Context Routing**: `.github/review-context.toml` + lightweight `scripts/prepare-cr-context.py` dynamically loads only the relevant `.github/cr-rules/*.md` rulebooks, high-risk path manifest, and read-only Layer 1 Semgrep findings into `.gemini/context.json`, plus skips pure rebases via `git patch-id --verbatim`.

## 2. Authentication & Identity Setup

### Model Billing / Compute Account (choose one)
1. **Google AI Studio (Fastest / Free Tier)**: Add repository secret `GEMINI_API_KEY` under **Settings → Secrets and variables → Actions**.
2. **Google Cloud Vertex AI (Enterprise / Zero Static Key)**: Set repository variables `GOOGLE_GENAI_USE_VERTEXAI=true`, `GCP_WIF_PROVIDER`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`, and optional `SERVICE_ACCOUNT_EMAIL`.
3. **Gemini Code Assist**: Set `GOOGLE_GENAI_USE_GCA=true`.

> If none of the above are configured, Layer 1 Deterministic Security Gates still run and block `P0` issues while Stage 2 gracefully skips Gemini CLI with a setup notice in Step Summary.

### GitHub Commenting Identity (choose one)
1. **Default Zero-Setup**: Uses `${{ secrets.GITHUB_TOKEN }}` (`github-actions[bot]`).
2. **Optional Custom GitHub App**: Set repository variable `APP_ID` and secret `APP_PRIVATE_KEY` to post reviews under a branded organization bot.

## 3. Rule Taxonomy

- **Client Engineering (`CLI-*`)** — `.github/cr-rules/client-ios.md` & `.github/cr-rules/client-kmp.md`:
  - `CLI-IOS-001`..`008`: Swift 6 concurrency/Sendable safety, MainActor/UI safety, retain cycles & Task cancellation, production force-unwraps (`try!`/`!`), App Extension memory & disallowed APIs, bidirectional Codable/RPC compatibility, silent `try?` write swallowing, presentation races & accessibility.
  - `CLI-AND-001`..`007`: `GlobalScope` & swallowed `CancellationException`, main-thread blocking/ANR, Context/Flow lifecycle leaks, Compose side-effects, Bundle size & `SavedStateHandle`, background/resource leaks, R8/ProGuard `@Keep`.
  - `CLI-KMP-001`..`004`: Cross-platform Flow/SKIE cancellation, Swift/Kotlin/Companion contract parity, `@Throws` boundary & `commonMain` purity, umbrella export bloat.
- **Security (`SEC-*`) & Compliance (`COMP-*`)** — `.github/cr-rules/security-compliance.md` & `.github/cr-rules/semgrep-client-security.yml`:
  - `SEC-DATA-001`..`005`: Hardcoded secrets, plaintext `UserDefaults`/`SharedPreferences` credentials, weak Keychain/backup attributes, sensitive logging/crash context, Lock Screen / Live Activity / clipboard exposure.
  - `SEC-NET-001`..`004`: TLS pinning/trust bypass, ATS/cleartext weakening, weak crypto (MD5/SHA-1/DES/ECB), WebView bridge/origin flaws.
  - `SEC-AUTH-001`..`003`: Face ID/BiometricPrompt bypass or fail-open, incomplete logout/host-switch cleanup, pairing/one-time token TTL & replay gaps.
  - `SEC-IPC-001`..`004`: Deeplink/URL scheme injection & debug route exposure, exported Android components, Share Extension/App Group boundary, SQL/command/path injection.
  - `SEC-CI-001`..`003`: Workflow injection/unpinned actions (`zizmor`), credential hygiene, Prompt Injection defense & Layer 1 immutability.
  - `COMP-PRIV-001`..`004`, `COMP-STORE-001`, `COMP-OSS-001`, `COMP-AUDIT-001`: `PrivacyInfo.xcprivacy` Required Reason API alignment, system permission delta review, telemetry/pre-consent red lines, store private API/dynamic loading checks, copyleft license & CVE blocking, and structured `// cr-ignore: <RULE-ID> reason=<...> ticket=<...>` exemptions guarded by `.github/CODEOWNERS`.

## 4. Local Validation

```bash
python3 scripts/prepare-cr-context.py --validate-config --self-test
```
