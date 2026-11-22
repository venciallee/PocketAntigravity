# 03 — Client + Security & Compliance GitHub CR Agent (`run-gemini-cli` Architecture)

## 1. Overview & Design Principles

This specification defines the **Client (`apps/ios` Swift 6 / `apps/android` Kotlin / `shared/` KMP) + Security & Compliance Code Review Agent** for `venciallee/PocketAntigravity`, streamlined for a **personal GitHub repository** using mature off-the-shelf tools:

- **Layer 1 (Deterministic Hard Gate — 100% free on public repos, non-exemptable by LLM)**:
  - `gitleaks/gitleaks-action` — secret scanning
  - `actions/dependency-review-action` — High/Critical CVE & `GPL`/`AGPL`/`SSPL` license blocklist
  - `semgrep` running `.github/cr-rules/semgrep-client-security.yml` with `--baseline-commit` → native **SARIF 2.1.0** uploaded to GitHub Code Scanning Security Tab (`github/codeql-action/upload-sarif@v4`)
  - `verification/verify_compat_guardrails.py` — bidirectional RPC / resilient enum / live-write guardrails
  - `zizmorcore/zizmor-action` (`.github/workflows/zizmor.yml`) — audits CI workflows themselves
- **Layer 2 (Contextual Semantic Review — Official Google Gemini CLI + GitHub MCP Server)**:
  - `google-github-actions/run-gemini-cli` (pinned 40-char commit SHA) executing `.gemini/commands/client-security-review.toml` (`/client-security-review`)
  - **Strict Sandbox**: `"tools": { "core": [] }` (zero local shell or file write tools) paired with official `ghcr.io/github/github-mcp-server` locked to 4 tools (`pull_request_read`, `get_file_contents`, `add_comment_to_pending_review`, `pull_request_review_write`).
  - **Path-Scoped Context Routing**: `.github/review-context.toml` + `scripts/prepare-cr-context.py` dynamically routes changed paths (`apps/ios/**`, `apps/android/**`, `shared/**`, `project.yml`, `.github/workflows/**`) to the relevant `.github/cr-rules/*.md` checklists + high-risk paths + read-only Layer 1 Semgrep findings, and skips pure rebases via `git patch-id --verbatim`.

## 2. Personal Account Setup (2 Minutes)

- **GitHub Identity**: Uses built-in `${{ secrets.GITHUB_TOKEN }}` (`github-actions[bot]`) — **zero extra GitHub account or GitHub App needed**.
- **Model Key**:
  1. Sign in to [Google AI Studio](https://aistudio.google.com/app/apikey) with your Google account and create an API key (note: since June 2026, personal browser OAuth / Antigravity subscriptions do not run headless in `run-gemini-cli`; a Google AI Studio `GEMINI_API_KEY` is required).
  2. Add it under **Settings → Secrets and variables → Actions → New repository secret**:
     - Name: `GEMINI_API_KEY`
     - Value: `<your key>`
  3. Optional: add repository variable `GEMINI_MODEL` (default `gemini-2.5-pro`; set `gemini-2.5-flash` for minimal API cost).

> Without `GEMINI_API_KEY`, Layer 1 deterministic security/compliance checks still run and block `P0` issues while Stage 2 gracefully skips Gemini CLI.

## 3. Rule Taxonomy

- **Client (`CLI-*`)** — `.github/cr-rules/client-ios.md` & `.github/cr-rules/client-kmp.md` (`CLI-IOS-001..008`, `CLI-AND-001..007`, `CLI-KMP-001..004`)
- **Security (`SEC-*`) & Compliance (`COMP-*`)** — `.github/cr-rules/security-compliance.md` & `.github/cr-rules/semgrep-client-security.yml` (`SEC-DATA/NET/AUTH/IPC/CI-*`, `COMP-PRIV/STORE/OSS/AUDIT-*`)

## 4. Local Validation

```bash
python3 scripts/prepare-cr-context.py --validate-config --self-test
```
