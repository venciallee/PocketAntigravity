#!/usr/bin/env python3
"""Google Antigravity 2.0 Official Documentation & Changelog Sync Watcher (`scripts/sync-antigravity-docs.py`).

Pure Python 3.11+ standard-library implementation designed for pure-cloud GitHub Actions:
1. Subscribes to official multi-source Google Antigravity 2.0 endpoints:
   - https://antigravity.google/docs/changelog
   - 16 core https://antigravity.google/docs/* feature guides
   - https://raw.githubusercontent.com/google-antigravity/antigravity-cli/main/CHANGELOG.md
   - https://github.com/google-antigravity/antigravity-cli/releases.atom
   - https://github.com/google-antigravity/antigravity-sdk-python/releases.atom
2. Strips navigation/theme/footer chrome from HTML pages into normalized Markdown snapshots.
3. Enforces a strict **monotonic semantic-version guard** so stale regional CDN nodes
   (e.g., returning v2.28.1 when manifest is already v2.33.0) never cause false rollbacks.
4. Classifies detected deltas by iOS relevance and 3-tier delivery risk:
   - Tier 1 (Auto Ready PR): Models, Thinking levels, Slash commands, Markdown/UI/Themes, Specs.
   - Tier 2 (Auto Draft PR + Protocol Probe): New LanguageServer RPCs, Protobuf step/interaction fields, VCS/MCP/Overview.
   - Tier 3 (RFC Issue / PRD+Tech+Test Only): Heavy native framework / infra work (WebRTC Voice Live, SwiftNIO SSH, APNs Server).
5. Supports `--self-test` for zero-network deterministic CI verification.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import html
import json
import re
import sys
import tempfile
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

REPO_ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT_DIR = REPO_ROOT / "docs" / "upstream-snapshots"
MANIFEST_PATH = SNAPSHOT_DIR / "manifest.json"

OFFICIAL_SOURCES: dict[str, dict[str, str]] = {
    "changelog": {
        "url": "https://antigravity.google/docs/changelog",
        "kind": "html",
        "snapshot": "changelog.md",
    },
    "cli_changelog": {
        "url": "https://raw.githubusercontent.com/google-antigravity/antigravity-cli/main/CHANGELOG.md",
        "kind": "markdown",
        "snapshot": "cli-changelog.md",
    },
    "cli_releases_atom": {
        "url": "https://github.com/google-antigravity/antigravity-cli/releases.atom",
        "kind": "atom",
        "snapshot": "cli-releases.md",
    },
    "sdk_releases_atom": {
        "url": "https://github.com/google-antigravity/antigravity-sdk-python/releases.atom",
        "kind": "atom",
        "snapshot": "sdk-releases.md",
    },
}

CORE_DOC_SLUGS: list[str] = [
    "features",
    "models",
    "permissions",
    "remote-control",
    "remote-agents",
    "review-changes",
    "side-panel",
    "voice-mode",
    "browser",
    "ssh",
    "dynamic-workflows",
    "swarm",
    "teamwork",
    "plugins",
    "mcp",
    "sidecars",
]

DESKTOP_ONLY_NOISE_PATTERNS = (
    r"\bwindows\s*(?:10|11|installer|defender|credential|powershell|git\.exe)\b",
    r"\b(?:on|for)\s+windows\b",
    r"\bon\s+linux\b",
    r"\bantivirus\b",
    r"\bmacos\s+installer\b",
    r"\bdock\s+icon\b",
    r"\bwindow\s+title\s+bar\b",
    r"\bwindow\s+minimize,\s*maximize\b",
    r"\belectron\b",
    r"\bchrome\s+tab\s+groups?\s+on\s+linux\b",
    r"\bctrl\+d\s+on\s+windows\b",
    r"\bkey-release\s+events?\s+reported\s+by\s+the\s+console\b",
    r"\bhyper-v\b|\bwsl2\b",
)

TIER3_KEYWORDS = (
    "webrtc",
    "gemini live",
    "voice mode",
    "connect over ssh",
    "openssh",
    "webusb",
    "webhid",
    "web serial",
    "apns",
    "push notification",
    "built-in browser agent",
)

TIER2_KEYWORDS = (
    "rpc",
    "protobuf",
    "language_server",
    "requestedinteraction",
    "permission preset",
    "download_url",
    "execute_url",
    "mcp",
    "plugin",
    "oauth",
    "workflow",
    "/run-workflow",
    "/swarm",
    "/btw",
    "subagent",
    "remote agent",
    "remote control",
    "pull request",
    "git commit",
    "worktree",
    "automation",
    "sidecar",
)

TIER1_KEYWORDS = (
    "model",
    "gemini 4",
    "orchestrator",
    "thinking level",
    "xhigh",
    "slash command",
    "theme",
    "font size",
    "markdown",
    "frontmatter",
    "mermaid",
    "layout",
    "knowledge work",
    "navigator",
    "sidebar",
    "quota",
    "usage",
    "badge",
)

SEMVER_RE = re.compile(r"\bv?(\d+)\.(\d+)\.(\d+)\b")


def parse_semver(ver: str) -> tuple[int, int, int]:
    m = SEMVER_RE.search(ver or "")
    if not m:
        return (0, 0, 0)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3)))


def format_semver(tup: tuple[int, int, int]) -> str:
    return f"v{tup[0]}.{tup[1]}.{tup[2]}"


class _MainContentHTMLStripper(HTMLParser):
    """Extracts clean readable Markdown-like text from HTML while dropping nav/script/style chrome."""

    SKIP_TAGS = {"head", "title", "script", "style", "noscript", "nav", "header", "footer", "aside", "button", "svg", "template"}
    BLOCK_TAGS = {"h1", "h2", "h3", "h4", "p", "li", "tr", "section", "article", "div", "pre", "blockquote"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._skip_depth = 0
        self._in_main = False
        self._seen_main = False
        self._tag_stack: list[str] = []
        self._chunks: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        t = tag.lower()
        self._tag_stack.append(t)
        if t == "main" or t == "article":
            if not self._seen_main:
                self._chunks.clear()
            self._in_main = True
            self._seen_main = True
        if t in self.SKIP_TAGS:
            self._skip_depth += 1
            return
        if self._skip_depth > 0:
            return
        if t in ("h1", "h2", "h3", "h4"):
            level = int(t[1])
            self._chunks.append(f"\n{'#' * level} ")
        elif t == "li":
            self._chunks.append("\n- ")
        elif t in ("p", "tr", "pre", "blockquote"):
            self._chunks.append("\n")

    def handle_endtag(self, tag: str) -> None:
        t = tag.lower()
        if self._tag_stack and self._tag_stack[-1] == t:
            self._tag_stack.pop()
        if t in self.SKIP_TAGS and self._skip_depth > 0:
            self._skip_depth -= 1
            return
        if t in ("main", "article") and self._in_main:
            self._in_main = False
        if self._skip_depth == 0 and t in self.BLOCK_TAGS:
            self._chunks.append("\n")

    def handle_data(self, data: str) -> None:
        if self._skip_depth > 0:
            return
        if self._seen_main and not self._in_main:
            return
        text = re.sub(r"\s+", " ", data)
        if text.strip():
            self._chunks.append(text)

    def get_markdown(self) -> str:
        raw = "".join(self._chunks)
        lines = []
        for line in raw.splitlines():
            cleaned = line.strip()
            if not cleaned:
                if lines and lines[-1] != "":
                    lines.append("")
                continue
            # Drop recurring site chrome noise
            if cleaned in (
                "Skip to content",
                "Copy Markdown",
                "View Markdown",
                "Expand all",
                "Dark Light Auto",
                "Select theme",
                "Open web app Download",
            ):
                continue
            lines.append(cleaned)
        return "\n".join(lines).strip() + "\n"


def normalize_html_to_markdown(raw_html: str) -> str:
    parser = _MainContentHTMLStripper()
    parser.feed(raw_html)
    return parser.get_markdown()


def normalize_atom_to_markdown(raw_xml: str) -> str:
    entries = re.findall(r"<entry>(.*?)</entry>", raw_xml, flags=re.DOTALL)
    lines = ["# Releases Feed", ""]
    for entry in entries[:20]:
        title_m = re.search(r"<title[^>]*>(.*?)</title>", entry, flags=re.DOTALL)
        updated_m = re.search(r"<updated>(.*?)</updated>", entry, flags=re.DOTALL)
        link_m = re.search(r'<link[^>]+href="([^"]+)"', entry)
        title = html.unescape(title_m.group(1).strip()) if title_m else "Release"
        updated = updated_m.group(1).strip() if updated_m else ""
        link = link_m.group(1).strip() if link_m else ""
        lines.append(f"- **{title}** ({updated}) {link}".strip())
    return "\n".join(lines) + "\n"


def extract_app_versions(text: str) -> list[tuple[int, int, int]]:
    """Extracts Antigravity App versions >= v2.0.0 (e.g. v2.33.0, v3.0.0+, filtering out v0.x/v1.x CLI tags)."""
    found: set[tuple[int, int, int]] = set()
    for m in re.finditer(r"\bv(\d+\.\d+\.\d+)\b", text):
        ver = parse_semver(m.group(1))
        if ver[0] >= 2:
            found.add(ver)
    return sorted(found, reverse=True)


def extract_cli_versions(text: str) -> list[tuple[int, int, int]]:
    found: set[tuple[int, int, int]] = set()
    for m in re.finditer(r"\bv?(1\.\d+\.\d+)\b", text):
        found.add(parse_semver(m.group(1)))
    return sorted(found, reverse=True)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def is_desktop_only_noise(line: str) -> bool:
    low = line.lower()
    return any(re.search(pat, low) for pat in DESKTOP_ONLY_NOISE_PATTERNS)


def classify_delta_line(line: str) -> tuple[str, str]:
    """Classifies a changelog/doc delta item into (tier, rationale)."""
    low = line.lower()
    if is_desktop_only_noise(low):
        return ("ignore", "Desktop OS / Electron-specific fix with no iOS companion impact")
    for kw in TIER3_KEYWORDS:
        if kw in low:
            return ("tier3", f"Matched heavy native/infra keyword `{kw}` (RFC + Design + Test Plan only)")
    for kw in TIER2_KEYWORDS:
        if kw in low:
            return ("tier2", f"Matched protocol/RPC/orchestration keyword `{kw}` (Draft PR + Protocol Probe)")
    for kw in TIER1_KEYWORDS:
        if kw in low:
            return ("tier1", f"Matched client/catalog/UI keyword `{kw}` (Auto-implementable Ready PR)")
    return ("tier1", "General Antigravity 2.0 capability or UX update")


@dataclass
class DeltaItem:
    source: str
    summary: str
    tier: str
    rationale: str


@dataclass
class SyncReport:
    checked_at_utc: str
    previous_app_version: str
    detected_app_version: str
    previous_cli_version: str
    detected_cli_version: str
    stale_cdn_detected: bool = False
    has_meaningful_delta: bool = False
    max_tier: str = "none"
    changed_sources: list[str] = field(default_factory=list)
    skipped_sources: list[str] = field(default_factory=list)
    items: list[DeltaItem] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def _extract_meta_refresh_url(raw_html: str) -> str | None:
    """Extracts the target URL from an HTML `<meta http-equiv="refresh" content="...;url=...">` tag."""
    for tag_m in re.finditer(r"<meta\b[^>]*>", raw_html, flags=re.IGNORECASE):
        tag = tag_m.group(0)
        if not re.search(r'http-equiv\s*=\s*["\']?refresh["\']?', tag, flags=re.IGNORECASE):
            continue
        content_m = re.search(r'content\s*=\s*(["\'])(.*?)\1', tag, flags=re.IGNORECASE)
        if not content_m:
            continue
        url_m = re.search(r"url\s*=\s*([^;\s\"']+)", content_m.group(2), flags=re.IGNORECASE)
        if url_m:
            return html.unescape(url_m.group(1).strip())
    return None


def fetch_url(url: str, timeout: float = 20.0, _max_meta_redirects: int = 2) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "PocketAntigravity-DocSync/2.33 (+https://github.com/venciallee/PocketAntigravity)",
            "Accept": "text/html,application/xhtml+xml,text/markdown,application/atom+xml;q=0.9,*/*;q=0.8",
            "Cache-Control": "no-cache",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        final_url = resp.geturl() or url
        raw = resp.read().decode("utf-8", errors="replace")

    if _max_meta_redirects > 0:
        meta_target = _extract_meta_refresh_url(raw)
        if meta_target:
            resolved = urljoin(final_url, meta_target)
            if resolved != final_url:
                return fetch_url(resolved, timeout=timeout, _max_meta_redirects=_max_meta_redirects - 1)
    return raw


def compute_semantic_delta(
    source_key: str,
    old_text: str,
    new_text: str,
) -> list[DeltaItem]:
    if old_text == new_text:
        return []
    old_lines = old_text.splitlines()
    new_lines = new_text.splitlines()
    diff = list(difflib.unified_diff(old_lines, new_lines, lineterm="", n=0))
    items: list[DeltaItem] = []
    seen: set[str] = set()
    for line in diff:
        if not line.startswith("+") or line.startswith("+++"):
            continue
        cleaned = line[1:].strip().lstrip("-*• ").strip()
        if len(cleaned) < 16 or cleaned in seen:
            continue
        low_c = cleaned.lower()
        if (
            cleaned.startswith("<!--")
            or cleaned.endswith("-->")
            or cleaned.startswith("#")
            or cleaned.startswith("<a ")
            or cleaned.startswith("http://")
            or cleaned.startswith("https://")
            or "redirecting to:" in low_c
            or "redirecting from" in low_c
            or low_c.startswith("section titled ")
            or set(cleaned) <= set("-_=*` ")
        ):
            continue
        seen.add(cleaned)
        tier, rationale = classify_delta_line(cleaned)
        if tier == "ignore":
            continue
        items.append(DeltaItem(source=source_key, summary=cleaned[:260], tier=tier, rationale=rationale))
    return items


def max_tier_of(items: list[DeltaItem]) -> str:
    order = {"none": 0, "tier1": 1, "tier2": 2, "tier3": 3}
    best = "none"
    for item in items:
        if order.get(item.tier, 0) > order[best]:
            best = item.tier
    return best


def load_manifest(manifest_path: Path) -> dict[str, Any]:
    if manifest_path.exists():
        return json.loads(manifest_path.read_text(encoding="utf-8"))
    return {
        "schemaVersion": "1.0.0",
        "latestAppVersion": "v2.33.0",
        "latestCliVersion": "v1.5.11",
        "syncedAtUtc": datetime.now(timezone.utc).isoformat(),
        "pageHashes": {},
    }


def render_delta_markdown(report: SyncReport) -> str:
    lines = [
        f"# Antigravity Upstream Documentation Delta ({report.previous_app_version} → {report.detected_app_version})",
        "",
        f"- **Checked (UTC)**: `{report.checked_at_utc}`",
        f"- **App Version**: `{report.previous_app_version}` → `{report.detected_app_version}`",
        f"- **CLI Version**: `{report.previous_cli_version}` → `{report.detected_cli_version}`",
        f"- **Stale CDN Guard Triggered**: `{report.stale_cdn_detected}`",
        f"- **Meaningful Delta**: `{report.has_meaningful_delta}` (max tier: `{report.max_tier}`)",
        f"- **Changed Sources**: {', '.join(f'`{s}`' for s in report.changed_sources) or 'None'}",
        "",
    ]
    if report.items:
        lines.extend(["## Classified Requirements Delta", "", "| Tier | Source | Summary | Rationale |", "| :--- | :--- | :--- | :--- |"])
        for it in report.items[:60]:
            safe_summary = it.summary.replace("|", "\\|")
            safe_rat = it.rationale.replace("|", "\\|")
            lines.append(f"| `{it.tier.upper()}` | `{it.source}` | {safe_summary} | {safe_rat} |")
        lines.append("")
    if report.errors:
        lines.extend(["## Fetch Warnings / Errors", ""])
        for err in report.errors:
            lines.append(f"- {err}")
        lines.append("")
    return "\n".join(lines)


def run_sync(
    snapshot_dir: Path,
    output_dir: Path,
    apply_snapshots: bool = False,
    include_core_docs: bool = True,
    fetch_fn=fetch_url,
) -> SyncReport:
    manifest_path = snapshot_dir / "manifest.json"
    manifest = load_manifest(manifest_path)
    prev_app = manifest.get("latestAppVersion", "v2.33.0")
    prev_cli = manifest.get("latestCliVersion", "v1.5.11")
    prev_app_t = parse_semver(prev_app)
    prev_cli_t = parse_semver(prev_cli)

    report = SyncReport(
        checked_at_utc=datetime.now(timezone.utc).isoformat(),
        previous_app_version=prev_app,
        detected_app_version=prev_app,
        previous_cli_version=prev_cli,
        detected_cli_version=prev_cli,
    )

    sources = dict(OFFICIAL_SOURCES)
    if include_core_docs:
        for slug in CORE_DOC_SLUGS:
            sources[f"docs/{slug}"] = {
                "url": f"https://antigravity.google/docs/{slug}/",
                "kind": "html",
                "snapshot": f"features/{slug}.md",
            }

    pending_writes: dict[Path, str] = {}
    new_hashes = dict(manifest.get("pageHashes", {}))

    for key, spec in sources.items():
        try:
            raw = fetch_fn(spec["url"])
        except Exception as exc:
            report.errors.append(f"{key} ({spec['url']}): {exc}")
            report.skipped_sources.append(key)
            continue

        kind = spec["kind"]
        if kind == "html":
            normalized = normalize_html_to_markdown(raw)
        elif kind == "atom":
            normalized = normalize_atom_to_markdown(raw)
        else:
            normalized = raw.strip() + "\n"

        # Monotonic semver guard for official changelog (prevents CDN stale rollback)
        if key == "changelog":
            versions = extract_app_versions(normalized)
            if versions:
                highest = versions[0]
                if highest < prev_app_t:
                    report.stale_cdn_detected = True
                    report.errors.append(
                        f"Stale CDN cache detected on {spec['url']}: highest={format_semver(highest)} < manifest={prev_app}. Skipping snapshot overwrite."
                    )
                    report.skipped_sources.append(key)
                    continue
                if highest > parse_semver(report.detected_app_version):
                    report.detected_app_version = format_semver(highest)

        if key in ("cli_changelog", "cli_releases_atom"):
            cli_versions = extract_cli_versions(normalized)
            if cli_versions:
                highest_cli = cli_versions[0]
                if highest_cli > parse_semver(report.detected_cli_version):
                    report.detected_cli_version = format_semver(highest_cli)

        snap_file = snapshot_dir / spec["snapshot"]
        old_text = snap_file.read_text(encoding="utf-8") if snap_file.exists() else ""
        digest = sha256_text(normalized)
        prev_digest = new_hashes.get(key)

        if digest != prev_digest and normalized != old_text:
            items = compute_semantic_delta(key, old_text, normalized)
            if items or not old_text:
                report.changed_sources.append(key)
                report.items.extend(items)
                pending_writes[snap_file] = normalized
                new_hashes[key] = digest

    app_upgraded = parse_semver(report.detected_app_version) > prev_app_t
    cli_upgraded = parse_semver(report.detected_cli_version) > prev_cli_t
    report.max_tier = max_tier_of(report.items)
    report.has_meaningful_delta = bool(
        (not report.stale_cdn_detected)
        and (app_upgraded or cli_upgraded or len(report.items) > 0)
    )

    if apply_snapshots and pending_writes and not report.stale_cdn_detected:
        for path, content in pending_writes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
        updated_manifest = {
            "schemaVersion": "1.0.0",
            "latestAppVersion": report.detected_app_version,
            "latestCliVersion": report.detected_cli_version,
            "syncedAtUtc": report.checked_at_utc,
            "pageHashes": new_hashes,
        }
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(updated_manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "delta-report.json").write_text(
        json.dumps(asdict(report), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (output_dir / "delta-summary.md").write_text(
        render_delta_markdown(report),
        encoding="utf-8",
    )
    return report


def run_self_test() -> None:
    """Deterministic zero-network unit & integration verification for sync-antigravity-docs.py."""
    print("=== [Self-Test] sync-antigravity-docs.py ===")

    # 1. Monotonic CDN stale-cache protection test
    with tempfile.TemporaryDirectory() as tmp:
        snap_dir = Path(tmp) / "snapshots"
        out_dir = Path(tmp) / "out"
        snap_dir.mkdir(parents=True)
        (snap_dir / "manifest.json").write_text(
            json.dumps(
                {
                    "schemaVersion": "1.0.0",
                    "latestAppVersion": "v2.33.0",
                    "latestCliVersion": "v1.5.11",
                    "syncedAtUtc": "2026-11-20T00:00:00+00:00",
                    "pageHashes": {},
                }
            ),
            encoding="utf-8",
        )
        (snap_dir / "changelog.md").write_text("# Changelog\n## v2.33.0\n- Connect over SSH\n", encoding="utf-8")

        def stale_fetcher(url: str) -> str:
            if "changelog" in url and "github" not in url:
                return "<main><h1>Changelog</h1><h2>v2.28.1</h2><p>Conversation navigator</p></main>"
            return ""

        stale_report = run_sync(
            snapshot_dir=snap_dir,
            output_dir=out_dir,
            apply_snapshots=True,
            include_core_docs=False,
            fetch_fn=stale_fetcher,
        )
        assert stale_report.stale_cdn_detected is True, "Expected stale CDN guard to trigger"
        assert stale_report.detected_app_version == "v2.33.0", "Expected version NOT to regress"
        assert stale_report.has_meaningful_delta is False, "Stale cache must not trigger sync"
        print("  [PASS] 1. Monotonic semver guard blocked stale CDN cache (v2.28.1 < v2.33.0)")

        # 2. Genuine v2.34.0 upgrade with Tier 1 / Tier 2 / Tier 3 + Desktop noise filtering
        def upgrade_fetcher(url: str) -> str:
            if "changelog" in url and "github" not in url:
                return (
                    "<nav>Dark Light Auto</nav><main><h1>Changelog</h1>"
                    "<h2>v2.34.0</h2>"
                    "<ul>"
                    "<li>Added Gemini 4 Xenon model with Extra thinking level and Solarized theme.</li>"
                    "<li>Added /review-pr slash command and new MCP OAuth token refresh RPC.</li>"
                    "<li>Fixed Windows 11 antivirus dark blank screen crash on startup.</li>"
                    "<li>Expanded Gemini Live Voice Mode with real-time WebRTC audio streaming.</li>"
                    "</ul></main>"
                )
            if "CHANGELOG.md" in url:
                return "# CLI Changelog\n## v1.5.12\n- Added /usage quota breakdown.\n"
            if "releases.atom" in url:
                return "<feed><entry><title>v1.5.12</title><updated>2026-11-25T00:00:00Z</updated></entry></feed>"
            return "<main><p>Unchanged</p></main>"

        up_report = run_sync(
            snapshot_dir=snap_dir,
            output_dir=out_dir,
            apply_snapshots=True,
            include_core_docs=False,
            fetch_fn=upgrade_fetcher,
        )
        assert up_report.stale_cdn_detected is False
        assert up_report.has_meaningful_delta is True
        assert up_report.detected_app_version == "v2.34.0"
        assert up_report.detected_cli_version == "v1.5.12"
        tiers = {it.tier for it in up_report.items}
        assert "tier1" in tiers and "tier2" in tiers and "tier3" in tiers, f"Unexpected tiers: {tiers}"
        assert not any("antivirus" in it.summary.lower() for it in up_report.items), "Windows noise must be filtered"
        updated_manifest = json.loads((snap_dir / "manifest.json").read_text(encoding="utf-8"))
        assert updated_manifest["latestAppVersion"] == "v2.34.0"
        assert (out_dir / "delta-report.json").exists() and (out_dir / "delta-summary.md").exists()
        print("  [PASS] 2. Detected v2.33.0 -> v2.34.0 delta, filtered Windows noise, classified Tier 1/2/3 & persisted snapshots")

        # 3. Major version upgrade (Google Antigravity 3.0: v2.34.0 -> v3.0.0) + meta-refresh + noise filtering
        meta_html = '<html><head><meta http-equiv="refresh" content="0;url=/docs/changelog"></head><body>Redirecting to: /docs/changelog</body></html>'
        assert _extract_meta_refresh_url(meta_html) == "/docs/changelog", "Expected meta-refresh URL extraction"

        def v3_fetcher(url: str) -> str:
            if "changelog" in url and "github" not in url:
                return (
                    "<main><h1>Changelog</h1>"
                    "<h2>v3.0.0 — Google Antigravity 3.0</h2>"
                    "<ul>"
                    "<li>Introduced Gemini 5 Aurora model with Adaptive Thinking budget controls.</li>"
                    "<li>Added multi-cluster Remote Agent orchestration RPC and signed session handoff.</li>"
                    "</ul></main>"
                )
            if "CHANGELOG.md" in url:
                return (
                    "# CLI Changelog\n"
                    "<!-- Release notes below -->\n"
                    "## v1.5.12\n"
                    "- Added /usage quota breakdown.\n"
                    "- Redirecting to: /docs/changelog\n"
                )
            if "releases.atom" in url:
                return "<feed><entry><title>v1.5.12</title><updated>2026-11-25T00:00:00Z</updated></entry></feed>"
            return "<main><p>Unchanged</p></main>"

        v3_report = run_sync(
            snapshot_dir=snap_dir,
            output_dir=out_dir,
            apply_snapshots=True,
            include_core_docs=False,
            fetch_fn=v3_fetcher,
        )
        assert v3_report.stale_cdn_detected is False
        assert v3_report.has_meaningful_delta is True
        assert v3_report.previous_app_version == "v2.34.0"
        assert v3_report.detected_app_version == "v3.0.0", f"Expected v3.0.0, got {v3_report.detected_app_version}"
        assert not any("<!--" in it.summary or "redirecting to:" in it.summary.lower() for it in v3_report.items), (
            "HTML comments & redirect stubs must be filtered from delta items"
        )
        v3_manifest = json.loads((snap_dir / "manifest.json").read_text(encoding="utf-8"))
        assert v3_manifest["latestAppVersion"] == "v3.0.0"
        print("  [PASS] 3. Detected major upgrade v2.34.0 -> v3.0.0 (Antigravity 3.0), meta-refresh parsing & noise filtering")

    print("ALL DOC-SYNC SELF-TESTS PASSED.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Google Antigravity 2.0 Official Docs Subscription & Delta Watcher")
    parser.add_argument("--check", action="store_true", help="Fetch upstream docs and emit delta report")
    parser.add_argument("--apply", action="store_true", help="Write updated normalized snapshots & manifest.json")
    parser.add_argument("--no-core-docs", action="store_true", help="Only check changelog + GitHub CLI/SDK feeds")
    parser.add_argument("--output-dir", type=Path, default=REPO_ROOT / "verification" / "output" / "doc-sync")
    parser.add_argument("--github-output", type=Path, default=None, help="Path to $GITHUB_OUTPUT file")
    parser.add_argument("--self-test", action="store_true", help="Run zero-network deterministic self-tests")
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
        return 0

    report = run_sync(
        snapshot_dir=SNAPSHOT_DIR,
        output_dir=args.output_dir,
        apply_snapshots=args.apply,
        include_core_docs=not args.no_core_docs,
    )
    print(render_delta_markdown(report))

    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as fh:
            fh.write(f"has_delta={'true' if report.has_meaningful_delta else 'false'}\n")
            fh.write(f"stale_cdn={'true' if report.stale_cdn_detected else 'false'}\n")
            fh.write(f"previous_version={report.previous_app_version}\n")
            fh.write(f"new_version={report.detected_app_version}\n")
            fh.write(f"max_tier={report.max_tier}\n")
            fh.write(f"item_count={len(report.items)}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
