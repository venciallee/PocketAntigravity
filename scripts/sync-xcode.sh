#!/usr/bin/env bash
# ==============================================================================
# PocketAntigravity — Sync KMP AntigravityShared.xcframework & Xcode Project
# ==============================================================================
# Keeps the gitignored local `PocketAntigravity.xcodeproj` and KMP
# `AntigravityShared.xcframework` cleanly synchronized with `project.yml` after
# `git pull` / branch switches / refactors.
#
# Usage (macOS):
#   bash scripts/sync-xcode.sh                  # Build/refresh KMP XCF + regenerate .xcodeproj (preserves local signing)
#   bash scripts/sync-xcode.sh --open           # Sync and open PocketAntigravity.xcodeproj in Xcode
#   bash scripts/sync-xcode.sh --team ABCDE12345 # Save local DEVELOPMENT_TEAM once into gitignored local.signing.xcconfig
#   bash scripts/sync-xcode.sh --clean --open   # Wipe stale .xcodeproj & DerivedData, then sync & open (keeps local signing)
#   bash scripts/sync-xcode.sh --swift-only     # Fast Xcode sync without JDK/Gradle (pure-Swift fallback)
#   bash scripts/sync-xcode.sh --rebuild-kmp    # Force rebuild of KMP AntigravityShared.xcframework
#   bash scripts/sync-xcode.sh --install-hooks  # Auto-sync Xcode project after every `git pull`
#   bash scripts/sync-xcode.sh --self-test      # Run offline unit checks (Linux & macOS)
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

XCF_REL="shared/umbrella/build/XCFrameworks/debug/AntigravityShared.xcframework"
XCF_PATH="$ROOT_DIR/$XCF_REL"
XCODEPROJ_PATH="$ROOT_DIR/PocketAntigravity.xcodeproj"
LEGACY_XCODEPROJ_PATH="$ROOT_DIR/iOSAntigravity.xcodeproj"
LOCAL_SIGNING_XCCONFIG="$ROOT_DIR/local.signing.xcconfig"

OPEN_XCODE=0
REBUILD_KMP=0
SWIFT_ONLY=0
REQUIRE_KMP=0
CLEAN_PROJECT=0
INSTALL_HOOKS=0
SELF_TEST=0
VERIFY_KMP_FOR_XCODE=0
VERIFY_XCODEPROJ_ARG=""
CLI_TEAM_ID=""
CLI_BUNDLE_PREFIX=""

usage() {
  cat <<'EOF'
Usage: bash scripts/sync-xcode.sh [options]

Options:
  --open                         Open PocketAntigravity.xcodeproj in Xcode after syncing
  --team <TEAM_ID>               Persist 10-char Apple DEVELOPMENT_TEAM into gitignored local.signing.xcconfig
  --bundle-prefix <PREFIX>       Persist custom ANTIGRAVITY_BUNDLE_PREFIX into gitignored local.signing.xcconfig
  --clean                        Remove existing PocketAntigravity.xcodeproj and DerivedData before regenerating
  --rebuild-kmp                  Force rebuild of shared/umbrella/build/XCFrameworks/debug/AntigravityShared.xcframework
  --swift-only                   Skip Gradle KMP XCFramework build and generate a pure-Swift Xcode project
  --require-kmp                  Fail instead of falling back to --swift-only if JDK/Gradle cannot build the XCFramework
  --install-hooks                Configure git core.hooksPath=.githooks to auto-sync after git pull / checkout
  --verify-kmp-for-xcode [path]  Xcode pre-build guardrail: fail fast if a linked KMP XCFramework is STALE
  --self-test                    Run offline self-tests (safe on Linux and macOS)
  -h, --help                     Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --open) OPEN_XCODE=1 ;;
    --rebuild-kmp) REBUILD_KMP=1 ;;
    --swift-only) SWIFT_ONLY=1 ;;
    --require-kmp) REQUIRE_KMP=1 ;;
    --clean) CLEAN_PROJECT=1 ;;
    --install-hooks) INSTALL_HOOKS=1 ;;
    --self-test) SELF_TEST=1 ;;
    --team)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        echo "[!] --team requires a 10-character Apple Team ID (e.g. --team ABCDE12345)" >&2
        exit 2
      fi
      CLI_TEAM_ID="$2"
      shift
      ;;
    --team=*)
      CLI_TEAM_ID="${arg#*=}"
      ;;
    --bundle-prefix)
      if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
        echo "[!] --bundle-prefix requires a reverse-DNS identifier (e.g. --bundle-prefix com.yourname.agpocket)" >&2
        exit 2
      fi
      CLI_BUNDLE_PREFIX="$2"
      shift
      ;;
    --bundle-prefix=*)
      CLI_BUNDLE_PREFIX="${arg#*=}"
      ;;
    --verify-kmp-for-xcode)
      VERIFY_KMP_FOR_XCODE=1
      if [[ $# -ge 2 && "$2" != -* ]]; then
        VERIFY_XCODEPROJ_ARG="$2"
        shift
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[!] Unknown option: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

detect_stale_pbxproj() {
  local pbx_path="$1"
  python3 - "$pbx_path" <<'PY'
import re
import sys
from pathlib import Path

pbx = Path(sys.argv[1])
if not pbx.is_file():
    sys.exit(1)

text = pbx.read_text(encoding="utf-8", errors="ignore")

# Legacy pre-monorepo paths that existed before PR #23 (apps/ios/*, tests/ios-ui/*)
# or legacy v1 ViewControllers removed in the v2.0 UE architecture.
legacy_patterns = [
    r'(?:=|repositoryURL\s*=)\s*"?Packages/AntigravityData\b',
    r'(?:=|path\s*=)\s*"?iOS/(?:ViewControllers|Application|Navigation|Services|Views)/',
    r'(?:=|path\s*=)\s*"?Shared/(?:DesignSystem|LiveActivity)/',
    r'(?:=|path\s*=)\s*"?Extensions/(?:LiveActivity|Share)/',
    r'(?:=|path\s*=)\s*"?iOSUITests\b',
    r"WorkspaceHomeViewController\.swift",
    r"TurnDiffViewController\.swift",
    r"ArtifactReviewViewController\.swift",
]
hits = [pat for pat in legacy_patterns if re.search(pat, text)]
if hits:
    print("LEGACY:" + ",".join(hits))
    sys.exit(0)
sys.exit(1)
PY
}

normalize_repo_directory_casing() {
  local repo_root="$1"
  python3 - "$repo_root" <<'PY'
import os
import sys
from pathlib import Path

repo = Path(sys.argv[1])
# Canonical relative directory paths whose actual on-disk casing MUST match project.yml / Gradle / Xcode 26.4+.
# On case-insensitive macOS APFS, checkouts created before PR #23 can retain uppercase `Shared/`
# even though Git now tracks `shared/`, causing Xcode 26.4+ to reject `AntigravityShared.xcframework`.
canonical_dirs = [
    "shared",
    "shared/umbrella",
    "shared/umbrella/build",
    "shared/umbrella/build/XCFrameworks",
    "shared/umbrella/build/XCFrameworks/debug",
    "shared/core-model",
    "shared/core-protocol",
    "shared/core-markdown",
    "shared/core-domain",
    "apps",
    "apps/ios",
    "apps/ios/App",
    "apps/ios/Config",
    "apps/ios/Watch",
    "apps/ios/SharedUI",
    "apps/ios/Extensions",
    "apps/ios/Packages",
    "apps/ios/Packages/AntigravityData",
    "tests",
    "tests/ios-ui",
]

renamed = []
for rel in canonical_dirs:
    parts = rel.split("/")
    parent = repo
    for part in parts[:-1]:
        parent = parent / part
    target_name = parts[-1]
    if not parent.is_dir():
        continue
    try:
        entries = os.listdir(parent)
    except OSError:
        continue
    if target_name in entries:
        continue
    matches = [e for e in entries if e.lower() == target_name.lower() and e != target_name]
    if not matches:
        continue
    actual_name = matches[0]
    src = parent / actual_name
    dst = parent / target_name
    tmp = parent / f".{target_name}-case-fix-{os.getpid()}"
    os.rename(src, tmp)
    os.rename(tmp, dst)
    prefix = "/".join(parts[:-1])
    old_rel = f"{prefix}/{actual_name}" if prefix else actual_name
    renamed.append((old_rel, rel))

for old_rel, new_rel in renamed:
    print(f"RENAMED:{old_rel}->{new_rel}")
PY
}

check_kmp_xcframework_freshness() {
  local repo_root="$1"
  local xcf_dir="$2"
  python3 - "$repo_root" "$xcf_dir" <<'PY'
import os
import plistlib
import sys
from pathlib import Path

repo = Path(sys.argv[1])
xcf = Path(sys.argv[2])
info_plist = xcf / "Info.plist"
if not info_plist.is_file():
    print("MISSING")
    sys.exit(0)

try:
    with info_plist.open("rb") as fp:
        pl = plistlib.load(fp)
    libs = pl.get("AvailableLibraries") or []
    if not libs:
        print("INVALID")
        sys.exit(0)
    for lib in libs:
        lib_id = lib.get("LibraryIdentifier")
        lib_path = lib.get("LibraryPath")
        if not lib_id or not lib_path or not (xcf / lib_id / lib_path).exists():
            print("INCOMPLETE")
            sys.exit(0)
except Exception:
    print("INVALID")
    sys.exit(0)

xcf_mtime = info_plist.stat().st_mtime
watch_files = [
    repo / "build.gradle.kts",
    repo / "settings.gradle.kts",
    repo / "gradle.properties",
]
watch_dirs = [repo / "shared", repo / "gradle"]

for wf in watch_files:
    if wf.is_file() and wf.stat().st_mtime > xcf_mtime:
        print("STALE")
        sys.exit(0)

skip_dirs = {"build", ".gradle", ".kotlin", ".git", "__pycache__"}
for wd in watch_dirs:
    if not wd.is_dir():
        continue
    for dirpath, dirnames, filenames in os.walk(wd):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs]
        for fname in filenames:
            fpath = Path(dirpath) / fname
            try:
                if fpath.stat().st_mtime > xcf_mtime:
                    print("STALE")
                    sys.exit(0)
            except OSError:
                pass

print("FRESH")
PY
}

write_swift_only_spec() {
  local src_spec="$1"
  local dst_spec="$2"
  python3 - "$src_spec" "$dst_spec" <<'PY'
import re
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text(encoding="utf-8")
lines = src.splitlines(keepends=True)
out = []
i = 0
removed = 0
while i < len(lines):
    line = lines[i]
    m = re.match(r"^(\s*)-\s*framework:\s*.*AntigravityShared\.xcframework\s*$", line)
    if m:
        indent = len(m.group(1))
        removed += 1
        i += 1
        # Also skip indented child properties belonging to this framework item (e.g. `embed: false`)
        while i < len(lines):
            nxt = lines[i]
            if nxt.strip() == "":
                break
            nxt_indent = len(nxt) - len(nxt.lstrip(" "))
            if nxt_indent > indent and not nxt.lstrip(" ").startswith("-"):
                i += 1
            else:
                break
        continue
    out.append(line)
    i += 1

if removed == 0:
    sys.stderr.write("[!] Warning: AntigravityShared.xcframework dependency entry not found in project.yml\n")

Path(sys.argv[2]).write_text("".join(out), encoding="utf-8")
PY
}

validate_generated_pbxproj() {
  local pbx_path="$1"
  python3 - "$pbx_path" <<'PY'
import re
import sys
from pathlib import Path

pbx = Path(sys.argv[1])
if not pbx.is_file():
    sys.stderr.write(f"[!] Generated project file missing: {pbx}\n")
    sys.exit(1)

text = pbx.read_text(encoding="utf-8", errors="ignore")
if "apps/ios/Packages/AntigravityData" not in text:
    sys.stderr.write("[!] Generated project.pbxproj is missing apps/ios/Packages/AntigravityData reference.\n")
    sys.exit(1)
if re.search(r"(?<!apps/ios/)Packages/AntigravityData", text):
    sys.stderr.write("[!] Generated project.pbxproj still contains legacy Packages/AntigravityData reference.\n")
    sys.exit(1)
if "LocalSigning.xcconfig" not in text:
    sys.stderr.write("[!] Generated project.pbxproj is missing LocalSigning.xcconfig base configuration reference.\n")
    sys.exit(1)
PY
}

sync_local_signing_config() {
  local pbx_path="$1"
  local local_xcconfig="$2"
  local explicit_team="$3"
  local explicit_prefix="$4"
  local allow_auto_detect="${5:-1}"
  python3 - "$pbx_path" "$local_xcconfig" "$explicit_team" "$explicit_prefix" "$allow_auto_detect" <<'PY'
from collections import Counter
from datetime import datetime, timezone
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_BUNDLE_PREFIX = "com.thousandtimes.agpocket"
TEAM_RE = re.compile(r"^[A-Z0-9]{10}$")
BUNDLE_PREFIX_RE = re.compile(r"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$")
DERIVED_BUNDLE_SUFFIXES = (
    ".watchkitapp.uitests",
    ".watchkitapp",
    ".LiveActivity",
    ".Share",
    ".uitests",
)

pbx_path = Path(sys.argv[1]) if sys.argv[1] else None
xcconfig_path = Path(sys.argv[2])
explicit_team = sys.argv[3].strip().upper()
explicit_prefix = sys.argv[4].strip()
allow_auto_detect = sys.argv[5] == "1"

if explicit_team and not TEAM_RE.fullmatch(explicit_team):
    sys.stderr.write(
        f"[!] Invalid Apple Team ID '{explicit_team}'. Expected 10 uppercase alphanumeric characters (e.g. ABCDE12345).\n"
    )
    sys.exit(2)

if explicit_prefix and not BUNDLE_PREFIX_RE.fullmatch(explicit_prefix):
    sys.stderr.write(
        f"[!] Invalid bundle prefix '{explicit_prefix}'. Expected reverse-DNS format (e.g. com.yourname.agpocket).\n"
    )
    sys.exit(2)


def strip_xcconfig_comment(line: str) -> str:
    idx = line.find("//")
    return line[:idx] if idx >= 0 else line


def parse_local_xcconfig(path: Path) -> tuple[str, str, float]:
    if not path.is_file():
        return "", "", 0.0
    team = ""
    prefix = ""
    text = path.read_text(encoding="utf-8", errors="ignore")
    for raw_line in text.splitlines():
        code = strip_xcconfig_comment(raw_line).strip()
        if not code or "=" not in code:
            continue
        key, val = [part.strip() for part in code.split("=", 1)]
        val = val.strip().strip('"').strip("'").strip()
        if key == "DEVELOPMENT_TEAM" and TEAM_RE.fullmatch(val.upper()):
            team = val.upper()
        elif key == "ANTIGRAVITY_BUNDLE_PREFIX" and BUNDLE_PREFIX_RE.fullmatch(val):
            prefix = val
    return team, prefix, path.stat().st_mtime


def parse_pbxproj_signing(path: Path | None, existing_team: str) -> tuple[str, str, float]:
    if not path or not path.is_file():
        return "", "", 0.0
    text = path.read_text(encoding="utf-8", errors="ignore")
    mtime = path.stat().st_mtime

    team_hits = []
    for pat in (
        r'DEVELOPMENT_TEAM\s*=\s*"?([A-Za-z0-9]{10})"?\s*;',
        r'DevelopmentTeam\s*=\s*"?([A-Za-z0-9]{10})"?\s*;',
    ):
        for m in re.finditer(pat, text):
            tid = m.group(1).upper()
            if TEAM_RE.fullmatch(tid):
                team_hits.append(tid)

    pbx_team = ""
    if team_hits:
        # If user switched a target to a new team inside Xcode GUI, prefer the changed team over the old one.
        changed_hits = [t for t in team_hits if existing_team and t != existing_team]
        pool = changed_hits if changed_hits else team_hits
        pbx_team = Counter(pool).most_common(1)[0][0]

    prefix_hits = []
    for m in re.finditer(r'ANTIGRAVITY_BUNDLE_PREFIX\s*=\s*"?([^";\n]+)"?\s*;', text):
        cand = m.group(1).strip()
        if "$(" in cand or "${" in cand or cand == DEFAULT_BUNDLE_PREFIX:
            continue
        if BUNDLE_PREFIX_RE.fullmatch(cand):
            prefix_hits.append(cand)

    if not prefix_hits:
        for m in re.finditer(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^";\n]+)"?\s*;', text):
            cand = m.group(1).strip()
            if "$(" in cand or "${" in cand or cand == DEFAULT_BUNDLE_PREFIX:
                continue
            if any(cand.endswith(sfx) for sfx in DERIVED_BUNDLE_SUFFIXES):
                continue
            if BUNDLE_PREFIX_RE.fullmatch(cand):
                prefix_hits.append(cand)

    pbx_prefix = Counter(prefix_hits).most_common(1)[0][0] if prefix_hits else ""
    return pbx_team, pbx_prefix, mtime


def auto_detect_xcode_account_team() -> tuple[str, str]:
    """Read signed-in Xcode Accounts (never Keychain-only corporate certs without an Xcode Account)."""
    xcode_prefs = {}
    try:
        raw_plist = subprocess.check_output(
            ["defaults", "export", "com.apple.dt.Xcode", "-"],
            stderr=subprocess.DEVNULL,
        )
        if raw_plist:
            xcode_prefs = plistlib.loads(raw_plist)
    except Exception:
        pass

    if not xcode_prefs:
        plist_path = Path.home() / "Library/Preferences/com.apple.dt.Xcode.plist"
        if plist_path.is_file():
            try:
                xcode_prefs = plistlib.loads(plist_path.read_bytes())
            except Exception:
                xcode_prefs = {}

    if not xcode_prefs:
        return "", ""

    active_apple_ids = set()
    raw_accounts = xcode_prefs.get("DVTDeveloperAccountManagerAppleIDAccounts")
    if isinstance(raw_accounts, list):
        for acc in raw_accounts:
            if isinstance(acc, dict):
                uname = str(acc.get("username") or acc.get("accountName") or "").strip().lower()
                if uname:
                    active_apple_ids.add(uname)

    team_meta: dict[str, dict[str, object]] = {}

    def record_team(entry: dict, account_key: str = "") -> None:
        if not isinstance(entry, dict):
            return
        tid = str(entry.get("teamID") or entry.get("teamId") or entry.get("identifier") or "").strip().upper()
        if not TEAM_RE.fullmatch(tid):
            return
        tname = str(entry.get("teamName") or entry.get("name") or "").strip()
        ttype = str(entry.get("teamType") or "").strip().lower()
        is_free = bool(entry.get("isFreeProvisioningTeam"))
        is_personal = is_free or ("personal" in tname.lower()) or (ttype in ("personal", "free"))
        acct_norm = str(account_key or "").strip().lower()
        is_active = (not active_apple_ids) or (not acct_norm) or (acct_norm in active_apple_ids)
        if not is_active:
            return
        prev = team_meta.get(tid)
        if prev is None:
            team_meta[tid] = {"name": tname, "is_personal": is_personal}
        else:
            prev["is_personal"] = bool(prev["is_personal"]) or is_personal
            if tname and not prev["name"]:
                prev["name"] = tname

    def walk_teams(obj: object, account_hint: str = "") -> None:
        if isinstance(obj, dict):
            if any(k in obj for k in ("teamID", "teamId")):
                record_team(obj, account_hint)
            for k, v in obj.items():
                ks = str(k)
                next_hint = ks if "@" in ks else account_hint
                if isinstance(v, dict) and TEAM_RE.fullmatch(ks.upper()) and any(
                    fld in v for fld in ("teamName", "name", "isFreeProvisioningTeam", "teamType")
                ):
                    merged = dict(v)
                    merged.setdefault("teamID", ks.upper())
                    record_team(merged, next_hint)
                else:
                    walk_teams(v, next_hint)
        elif isinstance(obj, list):
            for item in obj:
                walk_teams(item, account_hint)

    for pref_key, pref_val in xcode_prefs.items():
        ks = str(pref_key)
        if ks.startswith("IDEProvisioning") or ks.startswith("DVTDeveloperAccount"):
            walk_teams(pref_val, "")

    if not team_meta:
        return "", ""

    # Prefer an active Xcode Account team that already has a cached unexpired Development profile for AG Pocket.
    agpocket_profile_teams: set[str] = set()
    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    for pdir in (
        Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
        Path.home() / "Library/MobileDevice/Provisioning Profiles",
    ):
        if not pdir.is_dir():
            continue
        for mp in list(pdir.glob("*.mobileprovision")) + list(pdir.glob("*.provisionprofile")):
            try:
                raw = mp.read_bytes()
                s = raw.find(b"<?xml")
                e = raw.find(b"</plist>")
                if s < 0 or e <= s:
                    continue
                pl = plistlib.loads(raw[s : e + len(b"</plist>")])
                tids = pl.get("TeamIdentifier") or []
                tid = str(tids[0]).strip().upper() if tids else ""
                if tid not in team_meta:
                    continue
                exp = pl.get("ExpirationDate")
                if isinstance(exp, datetime):
                    exp_naive = exp.astimezone(timezone.utc).replace(tzinfo=None) if exp.tzinfo else exp
                    if exp_naive <= now_utc:
                        continue
                ent = pl.get("Entitlements") or {}
                if ent.get("get-task-allow") is not True:
                    continue
                app_id = str(ent.get("application-identifier") or "").lower()
                if "agpocket" in app_id:
                    agpocket_profile_teams.add(tid)
            except Exception:
                continue

    ordered = sorted(
        team_meta.keys(),
        key=lambda tid: (
            0 if tid in agpocket_profile_teams else 1,
            0 if team_meta[tid]["is_personal"] else 1,
            tid,
        ),
    )
    chosen = ordered[0]
    info = team_meta[chosen]
    label = str(info.get("name") or ("Personal Team" if info["is_personal"] else "Xcode Account Team"))
    return chosen, label


def write_local_xcconfig(path: Path, team: str, prefix: str, update_prefix: bool) -> None:
    if path.is_file():
        orig_lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    else:
        orig_lines = [
            "// Machine-local Xcode signing overrides (gitignored; survives `git pull`, `xcodegen`, and `--clean`).",
            "// Update anytime via: bash scripts/sync-xcode.sh --team <TEAM_ID> [--bundle-prefix <PREFIX>]",
        ]

    out_lines = []
    replaced_team = False
    replaced_prefix = False
    for line in orig_lines:
        code = strip_xcconfig_comment(line).strip()
        if code and "=" in code:
            key = code.split("=", 1)[0].strip()
            if key == "DEVELOPMENT_TEAM" and team:
                out_lines.append(f"DEVELOPMENT_TEAM = {team}")
                replaced_team = True
                continue
            if key == "ANTIGRAVITY_BUNDLE_PREFIX" and update_prefix:
                if prefix and prefix != DEFAULT_BUNDLE_PREFIX:
                    out_lines.append(f"ANTIGRAVITY_BUNDLE_PREFIX = {prefix}")
                replaced_prefix = True
                continue
        out_lines.append(line)

    if team and not replaced_team:
        out_lines.append(f"DEVELOPMENT_TEAM = {team}")
    if update_prefix and prefix and prefix != DEFAULT_BUNDLE_PREFIX and not replaced_prefix:
        out_lines.append(f"ANTIGRAVITY_BUNDLE_PREFIX = {prefix}")

    path.write_text("\n".join(out_lines).rstrip() + "\n", encoding="utf-8")


cfg_team, cfg_prefix, cfg_mtime = parse_local_xcconfig(xcconfig_path)
pbx_team, pbx_prefix, pbx_mtime = parse_pbxproj_signing(pbx_path, cfg_team)

final_team = cfg_team
team_source = "local-xcconfig" if cfg_team else ""
if explicit_team:
    final_team = explicit_team
    team_source = "explicit"
elif cfg_team and pbx_team and pbx_team != cfg_team and pbx_mtime > cfg_mtime:
    final_team = pbx_team
    team_source = "xcode-gui"
elif not cfg_team and pbx_team:
    final_team = pbx_team
    team_source = "migrated-pbxproj"
elif not cfg_team and allow_auto_detect and os.environ.get("CI") != "true":
    detected_team, detected_label = auto_detect_xcode_account_team()
    if detected_team:
        final_team = detected_team
        team_source = f"auto-detected ({detected_label})"

final_prefix = cfg_prefix
prefix_source = "local-xcconfig" if cfg_prefix else ""
prefix_changed = False
if explicit_prefix:
    final_prefix = explicit_prefix
    prefix_source = "explicit"
    prefix_changed = (explicit_prefix != cfg_prefix) and not (explicit_prefix == DEFAULT_BUNDLE_PREFIX and not cfg_prefix)
elif cfg_prefix and pbx_prefix and pbx_prefix != cfg_prefix and pbx_mtime > cfg_mtime:
    final_prefix = pbx_prefix
    prefix_source = "xcode-gui"
    prefix_changed = True
elif not cfg_prefix and pbx_prefix:
    final_prefix = pbx_prefix
    prefix_source = "migrated-pbxproj"
    prefix_changed = True

team_changed = bool(final_team) and (final_team != cfg_team or not xcconfig_path.is_file())
should_write = team_changed or prefix_changed

if should_write:
    write_local_xcconfig(
        xcconfig_path,
        team=final_team,
        prefix=final_prefix,
        update_prefix=prefix_changed or bool(explicit_prefix),
    )
    parts = []
    if final_team:
        parts.append(f"DEVELOPMENT_TEAM={final_team}")
    if final_prefix and final_prefix != DEFAULT_BUNDLE_PREFIX:
        parts.append(f"ANTIGRAVITY_BUNDLE_PREFIX={final_prefix}")
    detail = ", ".join(parts) if parts else "defaults"
    src_note = team_source or prefix_source
    print(f"[+] Persisted local Xcode signing ({detail}) to gitignored {xcconfig_path.name} [{src_note}].")
elif final_team:
    extra = f", ANTIGRAVITY_BUNDLE_PREFIX={final_prefix}" if (final_prefix and final_prefix != DEFAULT_BUNDLE_PREFIX) else ""
    print(f"[+] Preserving local Xcode signing from {xcconfig_path.name} (DEVELOPMENT_TEAM={final_team}{extra}).")
elif os.environ.get("CI") != "true":
    print("[i] No local DEVELOPMENT_TEAM saved yet (Xcode will ask for a Team on physical device builds).")
    print("    Save once: bash scripts/sync-xcode.sh --team <YOUR_10_CHAR_TEAM_ID>  (or select Team in Xcode once — next sync remembers it).")
PY
}

java_major_version() {
  local java_bin="$1"
  [[ -x "$java_bin" ]] || return 1
  local raw
  raw="$("$java_bin" -version 2>&1 | head -n 1 || true)"
  python3 - "$raw" <<'PY'
import re
import sys

m = re.search(r'"(\d+)(?:\.(\d+))?', sys.argv[1])
if not m:
    sys.exit(1)
major = int(m.group(1))
if major == 1 and m.group(2):
    major = int(m.group(2))
print(major)
PY
}

find_java_home() {
  local candidates=()
  if [[ -n "${JAVA_HOME:-}" ]]; then
    candidates+=("$JAVA_HOME")
  fi
  if [[ -x "/usr/libexec/java_home" ]]; then
    local jh21 jh17 jhany
    jh21="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
    jh17="$(/usr/libexec/java_home -v 17+ 2>/dev/null || true)"
    jhany="$(/usr/libexec/java_home 2>/dev/null || true)"
    [[ -n "$jh21" ]] && candidates+=("$jh21")
    [[ -n "$jh17" ]] && candidates+=("$jh17")
    [[ -n "$jhany" ]] && candidates+=("$jhany")
  fi
  candidates+=(
    "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
    "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
    "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    "/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
    "/usr/local/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
    "/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    "${HOME}/.sdkman/candidates/java/current"
  )
  if [[ -d "/Library/Java/JavaVirtualMachines" ]]; then
    local jvm_home
    while IFS= read -r jvm_home; do
      [[ -n "$jvm_home" ]] && candidates+=("$jvm_home")
    done < <(find /Library/Java/JavaVirtualMachines -maxdepth 3 -path "*/Contents/Home" -type d 2>/dev/null | sort -r)
  fi

  local cand ver
  for cand in ${candidates[@]+"${candidates[@]}"}; do
    [[ -z "$cand" || "$cand" == "/usr" ]] && continue
    [[ -x "$cand/bin/java" ]] || continue
    ver="$(java_major_version "$cand/bin/java" 2>/dev/null || echo 0)"
    if [[ "$ver" =~ ^[0-9]+$ ]] && [[ "$ver" -ge 17 ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

clean_xcode_derived_data() {
  python3 - "$ROOT_DIR" <<'PY'
import shutil
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
targets = []

xcode_dd = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"
if xcode_dd.is_dir():
    for child in xcode_dd.iterdir():
        if child.is_dir() and child.name.startswith(("PocketAntigravity-", "iOSAntigravity-")):
            targets.append(child)

local_build = repo_root / ".build"
if local_build.is_dir():
    for child in local_build.iterdir():
        if child.is_dir() and child.name.startswith("DerivedData"):
            targets.append(child)

for path in targets:
    shutil.rmtree(path, ignore_errors=True)
    print(f"    cleaned {path}")
PY
}

decide_kmp_xcf_fallback() {
  local xcf_state="$1"
  local require_kmp="$2"
  local rebuild_kmp="$3"
  if [[ "$xcf_state" == "FRESH" && "$rebuild_kmp" -eq 0 ]]; then
    echo "REUSE_KMP"
    return 0
  fi
  if [[ "$require_kmp" -eq 1 ]]; then
    echo "FAIL"
    return 0
  fi
  echo "SWIFT_ONLY"
}

verify_kmp_for_xcode_build() {
  local repo_root="$1"
  local xcf_dir="$2"
  local xcodeproj_path="$3"

  if [[ "${CI:-}" == "true" || "${SKIP_KMP_FRESHNESS_CHECK:-0}" == "1" ]]; then
    return 0
  fi

  local pbxproj=""
  if [[ -n "$xcodeproj_path" && -f "$xcodeproj_path/project.pbxproj" ]]; then
    pbxproj="$xcodeproj_path/project.pbxproj"
  elif [[ -f "$repo_root/PocketAntigravity.xcodeproj/project.pbxproj" ]]; then
    pbxproj="$repo_root/PocketAntigravity.xcodeproj/project.pbxproj"
  fi

  if [[ -n "$pbxproj" ]] && ! grep -q "AntigravityShared\.xcframework" "$pbxproj" 2>/dev/null; then
    # Pure-Swift mode (`--swift-only`): KMP XCFramework is not linked.
    return 0
  fi

  local status
  status="$(check_kmp_xcframework_freshness "$repo_root" "$xcf_dir")"
  if [[ "$status" == "FRESH" ]]; then
    return 0
  fi

  echo "error: AntigravityShared.xcframework is ${status} (out of sync with Kotlin sources in shared/). Run 'bash scripts/sync-xcode.sh --rebuild-kmp' (or 'bash scripts/sync-xcode.sh --swift-only' if JDK 17/21 is unavailable) so Xcode does not link stale KMP networking code." >&2
  return 1
}

run_self_test() {
  echo "=== Running sync-xcode.sh offline self-tests ==="
  SELF_TEST_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agy-sync-xcode-test.XXXXXX")"
  trap 'rm -rf "${SELF_TEST_TMP_DIR:-}"' EXIT
  local tmp_dir="$SELF_TEST_TMP_DIR"

  # 1. Stale legacy pbxproj detection
  cat >"$tmp_dir/stale.pbxproj" <<'EOF'
/* old pre-monorepo project */
repositoryURL = "Packages/AntigravityData";
path = iOS/ViewControllers/Home/WorkspaceHomeViewController.swift;
EOF
  if ! detect_stale_pbxproj "$tmp_dir/stale.pbxproj" >/dev/null; then
    echo "[FAIL] Failed to detect stale legacy project.pbxproj" >&2
    exit 1
  fi

  # 2. Modern monorepo pbxproj should NOT be flagged as stale
  cat >"$tmp_dir/modern.pbxproj" <<'EOF'
/* modern monorepo project */
relativePath = apps/ios/Packages/AntigravityData;
path = apps/ios/Config/LocalSigning.xcconfig;
path = apps/ios/App/ViewControllers/Home/AgentsHomeViewController.swift;
path = tests/ios-ui/AntigravityInteractiveUITests.swift;
EOF
  if detect_stale_pbxproj "$tmp_dir/modern.pbxproj" >/dev/null; then
    echo "[FAIL] False positive stale detection on modern monorepo project.pbxproj" >&2
    exit 1
  fi
  validate_generated_pbxproj "$tmp_dir/modern.pbxproj"

  # 3. Swift-only spec filtering preserves all targets & removes only AntigravityShared.xcframework
  write_swift_only_spec "$ROOT_DIR/project.yml" "$tmp_dir/project.swift-only.yml"
  python3 - "$tmp_dir/project.swift-only.yml" <<'PY'
import sys
from pathlib import Path

txt = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "AntigravityShared.xcframework" not in txt, "XCFramework reference was not stripped"
assert "apps/ios/Packages/AntigravityData" in txt, "AntigravityData package was lost"
assert "apps/ios/Config/LocalSigning.xcconfig" in txt, "LocalSigning.xcconfig configFiles was lost"
assert "target: AGPocketLiveActivity" in txt, "AGPocketLiveActivity target was lost"
assert "target: AGPocketShare" in txt, "AGPocketShare target was lost"
assert "target: AGPocketWatch" in txt, "AGPocketWatch target was lost"
assert "AGPocketUITests:" in txt, "AGPocketUITests target was lost"
PY

  # 4. KMP freshness detection: missing -> fresh -> stale
  local fake_repo="$tmp_dir/repo"
  local fake_xcf="$fake_repo/$XCF_REL"
  mkdir -p "$fake_repo/shared/core-model" "$fake_repo/gradle"
  touch "$fake_repo/shared/core-model/Foo.kt"
  [[ "$(check_kmp_xcframework_freshness "$fake_repo" "$fake_xcf")" == "MISSING" ]] || {
    echo "[FAIL] Expected MISSING for absent XCFramework" >&2
    exit 1
  }
  mkdir -p "$fake_xcf/ios-arm64/AntigravityShared.framework"
  python3 - "$fake_xcf/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
pl = {
    "AvailableLibraries": [
        {"LibraryIdentifier": "ios-arm64", "LibraryPath": "AntigravityShared.framework"}
    ]
}
with Path(sys.argv[1]).open("wb") as fp:
    plistlib.dump(pl, fp)
PY
  # Ensure Info.plist is newer than Foo.kt
  python3 - "$fake_repo/shared/core-model/Foo.kt" "$fake_xcf/Info.plist" <<'PY'
import os, sys, time
now = time.time()
os.utime(sys.argv[1], (now - 10, now - 10))
os.utime(sys.argv[2], (now, now))
PY
  [[ "$(check_kmp_xcframework_freshness "$fake_repo" "$fake_xcf")" == "FRESH" ]] || {
    echo "[FAIL] Expected FRESH for up-to-date XCFramework" >&2
    exit 1
  }
  python3 - "$fake_repo/shared/core-model/Foo.kt" "$fake_xcf/Info.plist" <<'PY'
import os, sys, time
now = time.time()
os.utime(sys.argv[2], (now - 10, now - 10))
os.utime(sys.argv[1], (now, now))
PY
  [[ "$(check_kmp_xcframework_freshness "$fake_repo" "$fake_xcf")" == "STALE" ]] || {
    echo "[FAIL] Expected STALE when Kotlin source is newer than XCFramework" >&2
    exit 1
  }

  # 5. Directory casing normalization (fixes legacy APFS Shared/ -> shared/ mismatch for Xcode 26.4+)
  local case_repo="$tmp_dir/case-repo"
  mkdir -p "$case_repo/Shared/Umbrella/build/XCFrameworks/Debug"
  local rename_out
  rename_out="$(normalize_repo_directory_casing "$case_repo")"
  python3 - "$case_repo" "$rename_out" <<'PY'
import os
import sys
from pathlib import Path

repo = Path(sys.argv[1])
out = sys.argv[2]
assert "RENAMED:Shared->shared" in out, f"Expected Shared->shared rename in output: {out!r}"
assert "shared" in os.listdir(repo), f"Expected lowercase 'shared' in {os.listdir(repo)}"
assert "Shared" not in os.listdir(repo), f"Unexpected uppercase 'Shared' still in {os.listdir(repo)}"
assert "umbrella" in os.listdir(repo / "shared"), f"Expected lowercase 'umbrella' in {os.listdir(repo / 'shared')}"
assert "debug" in os.listdir(repo / "shared" / "umbrella" / "build" / "XCFrameworks"), "Expected lowercase 'debug'"
PY

  # 6. Never reuse a STALE KMP XCFramework when JDK/Gradle is unavailable
  [[ "$(decide_kmp_xcf_fallback "STALE" 0 0)" == "SWIFT_ONLY" ]] || {
    echo "[FAIL] Expected SWIFT_ONLY fallback when XCFramework is STALE without --require-kmp" >&2
    exit 1
  }
  [[ "$(decide_kmp_xcf_fallback "STALE" 1 0)" == "FAIL" ]] || {
    echo "[FAIL] Expected FAIL when XCFramework is STALE with --require-kmp" >&2
    exit 1
  }
  [[ "$(decide_kmp_xcf_fallback "FRESH" 0 0)" == "REUSE_KMP" ]] || {
    echo "[FAIL] Expected REUSE_KMP when XCFramework is FRESH" >&2
    exit 1
  }
  [[ "$(decide_kmp_xcf_fallback "FRESH" 0 1)" == "SWIFT_ONLY" ]] || {
    echo "[FAIL] Expected SWIFT_ONLY when forced --rebuild-kmp fails without --require-kmp" >&2
    exit 1
  }

  # 7. Xcode pre-build freshness guardrail catches STALE linked XCF & skips pure-Swift projects
  local fake_kmp_proj="$tmp_dir/Linked.xcodeproj"
  local fake_swift_proj="$tmp_dir/SwiftOnly.xcodeproj"
  mkdir -p "$fake_kmp_proj" "$fake_swift_proj"
  echo "path = shared/umbrella/build/XCFrameworks/debug/AntigravityShared.xcframework;" >"$fake_kmp_proj/project.pbxproj"
  echo "relativePath = apps/ios/Packages/AntigravityData;" >"$fake_swift_proj/project.pbxproj"

  # fake_repo currently has a STALE XCFramework from test #4
  if CI="" SKIP_KMP_FRESHNESS_CHECK=0 verify_kmp_for_xcode_build "$fake_repo" "$fake_xcf" "$fake_kmp_proj" 2>/dev/null; then
    echo "[FAIL] Expected verify_kmp_for_xcode_build to reject STALE linked XCFramework" >&2
    exit 1
  fi
  if ! CI="" SKIP_KMP_FRESHNESS_CHECK=0 verify_kmp_for_xcode_build "$fake_repo" "$fake_xcf" "$fake_swift_proj"; then
    echo "[FAIL] Expected verify_kmp_for_xcode_build to pass for --swift-only project" >&2
    exit 1
  fi
  # Make XCFramework FRESH again -> linked project must pass
  python3 - "$fake_repo/shared/core-model/Foo.kt" "$fake_xcf/Info.plist" <<'PY'
import os, sys, time
now = time.time()
os.utime(sys.argv[1], (now - 10, now - 10))
os.utime(sys.argv[2], (now, now))
PY
  if ! CI="" SKIP_KMP_FRESHNESS_CHECK=0 verify_kmp_for_xcode_build "$fake_repo" "$fake_xcf" "$fake_kmp_proj"; then
    echo "[FAIL] Expected verify_kmp_for_xcode_build to pass when linked XCFramework is FRESH" >&2
    exit 1
  fi

  # 8. Tracked base LocalSigning.xcconfig sets default prefix & optionally includes gitignored local.signing.xcconfig
  python3 - "$ROOT_DIR/apps/ios/Config/LocalSigning.xcconfig" "$ROOT_DIR/.gitignore" "$ROOT_DIR/project.yml" <<'PY'
import sys
from pathlib import Path

base_xc = Path(sys.argv[1]).read_text(encoding="utf-8")
gitignore = Path(sys.argv[2]).read_text(encoding="utf-8")
proj_yml = Path(sys.argv[3]).read_text(encoding="utf-8")

assert "ANTIGRAVITY_BUNDLE_PREFIX = com.thousandtimes.agpocket" in base_xc, "Base LocalSigning.xcconfig missing default prefix"
assert '#include? "../../../local.signing.xcconfig"' in base_xc, "Base LocalSigning.xcconfig missing optional local include"
assert "local.signing.xcconfig" in gitignore, ".gitignore must ignore local.signing.xcconfig"
assert "apps/ios/Config/LocalSigning.xcconfig" in proj_yml, "project.yml must attach LocalSigning.xcconfig via configFiles"
assert "ANTIGRAVITY_BUNDLE_PREFIX: com.thousandtimes.agpocket" not in proj_yml, "project.yml settings.base must not shadow xcconfig ANTIGRAVITY_BUNDLE_PREFIX"
PY

  # 9. Local signing migration from existing project.pbxproj -> local.signing.xcconfig (survives --clean)
  local sign_dir="$tmp_dir/signing-test"
  mkdir -p "$sign_dir"
  local sign_pbx="$sign_dir/project.pbxproj"
  local sign_xc="$sign_dir/local.signing.xcconfig"
  cat >"$sign_pbx" <<'EOF'
CODE_SIGN_STYLE = Automatic;
DEVELOPMENT_TEAM = AB12CD34EF;
PRODUCT_BUNDLE_IDENTIFIER = com.devuser.agpocket;
PRODUCT_BUNDLE_IDENTIFIER = com.devuser.agpocket.LiveActivity;
EOF
  sync_local_signing_config "$sign_pbx" "$sign_xc" "" "" "0" >/dev/null
  python3 - "$sign_xc" <<'PY'
import sys
from pathlib import Path
txt = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "DEVELOPMENT_TEAM = AB12CD34EF" in txt, f"Team not migrated: {txt}"
assert "ANTIGRAVITY_BUNDLE_PREFIX = com.devuser.agpocket" in txt, f"Custom bundle prefix not migrated: {txt}"
PY

  # 10. Local signing persists when pbxproj is wiped (--clean) and keeps custom user lines
  echo "CUSTOM_LOCAL_FLAG = YES" >>"$sign_xc"
  rm -f "$sign_pbx"
  sync_local_signing_config "$sign_pbx" "$sign_xc" "" "" "0" >/dev/null
  python3 - "$sign_xc" <<'PY'
import sys
from pathlib import Path
txt = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "DEVELOPMENT_TEAM = AB12CD34EF" in txt, "Team lost after pbxproj wipe"
assert "ANTIGRAVITY_BUNDLE_PREFIX = com.devuser.agpocket" in txt, "Bundle prefix lost after pbxproj wipe"
assert "CUSTOM_LOCAL_FLAG = YES" in txt, "Custom user xcconfig line was clobbered"
PY

  # 11. Newer Xcode GUI team switch updates local.signing.xcconfig, and explicit --team overrides both
  cat >"$sign_pbx" <<'EOF'
DEVELOPMENT_TEAM = ZZ99YY88XX;
EOF
  python3 - "$sign_xc" "$sign_pbx" <<'PY'
import os, sys, time
now = time.time()
os.utime(sys.argv[1], (now - 20, now - 20))
os.utime(sys.argv[2], (now, now))
PY
  sync_local_signing_config "$sign_pbx" "$sign_xc" "" "" "0" >/dev/null
  python3 - "$sign_xc" <<'PY'
import sys
from pathlib import Path
txt = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "DEVELOPMENT_TEAM = ZZ99YY88XX" in txt, f"Newer Xcode GUI team not persisted: {txt}"
assert "CUSTOM_LOCAL_FLAG = YES" in txt, "Custom user xcconfig line lost on update"
PY
  sync_local_signing_config "$sign_pbx" "$sign_xc" "QW12ER34TY" "com.thousandtimes.agpocket" "0" >/dev/null
  python3 - "$sign_xc" <<'PY'
import sys
from pathlib import Path
txt = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "DEVELOPMENT_TEAM = QW12ER34TY" in txt, f"Explicit --team did not override: {txt}"
assert "ANTIGRAVITY_BUNDLE_PREFIX =" not in txt, f"Resetting bundle prefix to default should drop override: {txt}"
assert "CUSTOM_LOCAL_FLAG = YES" in txt, "Custom user xcconfig line lost on explicit override"
PY
  if sync_local_signing_config "" "$sign_xc" "BAD_TEAM" "" "0" 2>/dev/null; then
    echo "[FAIL] Expected invalid Team ID to be rejected" >&2
    exit 1
  fi

  echo "[PASS] sync-xcode.sh self-tests passed!"
}

if [[ "$SELF_TEST" -eq 1 ]]; then
  run_self_test
  exit 0
fi

if [[ "$VERIFY_KMP_FOR_XCODE" -eq 1 ]]; then
  verify_kmp_for_xcode_build "$ROOT_DIR" "$XCF_PATH" "$VERIFY_XCODEPROJ_ARG"
  exit $?
fi

if [[ "$INSTALL_HOOKS" -eq 1 ]]; then
  chmod +x "$ROOT_DIR/.githooks/post-merge" "$ROOT_DIR/.githooks/post-checkout" 2>/dev/null || true
  git config core.hooksPath .githooks
  echo "[+] Installed Git hooks (.githooks/post-merge & post-checkout)."
  echo "    Future 'git pull' / branch switches will automatically keep PocketAntigravity.xcodeproj & local signing in sync."
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[!] sync-xcode.sh generates Xcode projects on macOS only (current OS: $(uname -s))."
  exit 0
fi

# 0. Normalize on-disk directory capitalization (fixes legacy APFS `Shared/` -> `shared/` for Xcode 26.4+)
CASE_FIXED=0
CASE_RENAME_OUT="$(normalize_repo_directory_casing "$ROOT_DIR" || true)"
if [[ -n "$CASE_RENAME_OUT" ]]; then
  CASE_FIXED=1
  while IFS= read -r line; do
    [[ -n "$line" ]] && echo "[*] Normalized on-disk directory casing (${line#RENAMED:}) for Xcode 26.4+ compatibility."
  done <<< "$CASE_RENAME_OUT"
fi

# 0b. Preserve/persist local Xcode signing BEFORE any clean/regeneration wipes PocketAntigravity.xcodeproj
EXISTING_PBXPROJ=""
if [[ -f "$XCODEPROJ_PATH/project.pbxproj" ]]; then
  EXISTING_PBXPROJ="$XCODEPROJ_PATH/project.pbxproj"
elif [[ -f "$LEGACY_XCODEPROJ_PATH/project.pbxproj" ]]; then
  EXISTING_PBXPROJ="$LEGACY_XCODEPROJ_PATH/project.pbxproj"
fi
EXPLICIT_TEAM="${CLI_TEAM_ID:-${DEVELOPMENT_TEAM:-${TEAM_ID:-}}}"
EXPLICIT_PREFIX="${CLI_BUNDLE_PREFIX:-${ANTIGRAVITY_BUNDLE_PREFIX:-${BUNDLE_PREFIX:-}}}"
sync_local_signing_config "$EXISTING_PBXPROJ" "$LOCAL_SIGNING_XCCONFIG" "$EXPLICIT_TEAM" "$EXPLICIT_PREFIX" "1"

# 1. Detect & wipe legacy iOSAntigravity.xcodeproj or stale pre-monorepo Xcode project / DerivedData
LEGACY_DETECTED=0
if [[ -d "$LEGACY_XCODEPROJ_PATH" ]]; then
  echo "[*] Migrating legacy iOSAntigravity.xcodeproj -> PocketAntigravity.xcodeproj..."
  rm -rf "$LEGACY_XCODEPROJ_PATH"
  LEGACY_DETECTED=1
fi
if [[ -f "$XCODEPROJ_PATH/project.pbxproj" ]]; then
  if detect_stale_pbxproj "$XCODEPROJ_PATH/project.pbxproj" >/dev/null 2>&1; then
    LEGACY_DETECTED=1
  fi
fi

if [[ "$CLEAN_PROJECT" -eq 1 || "$LEGACY_DETECTED" -eq 1 || "$CASE_FIXED" -eq 1 ]]; then
  if [[ "$LEGACY_DETECTED" -eq 1 ]]; then
    echo "[*] Detected legacy or stale pre-monorepo Xcode project state."
  fi
  if [[ "$CASE_FIXED" -eq 1 ]]; then
    echo "[*] Directory casing changed on disk — wiping cached Xcode project & DerivedData to avoid stale VFS/XCFramework paths..."
  fi
  echo "[*] Cleaning stale PocketAntigravity.xcodeproj and Xcode DerivedData caches..."
  rm -rf "$XCODEPROJ_PATH"
  clean_xcode_derived_data
fi

# 2. Ensure KMP AntigravityShared.xcframework is built & up to date (unless --swift-only)
USE_KMP_XCF=0
if [[ "$SWIFT_ONLY" -eq 1 ]]; then
  echo "[*] --swift-only requested: skipping KMP AntigravityShared.xcframework build (using pure-Swift AntigravityData fallback)."
  USE_KMP_XCF=0
else
  XCF_STATE="$(check_kmp_xcframework_freshness "$ROOT_DIR" "$XCF_PATH")"
  if [[ "$REBUILD_KMP" -eq 1 || "$XCF_STATE" != "FRESH" ]]; then
    REBUILD_NOTE=""
    if [[ "$REBUILD_KMP" -eq 1 ]]; then
      REBUILD_NOTE=" (forced rebuild)"
    fi
    echo "[*] KMP AntigravityShared.xcframework status: ${XCF_STATE}${REBUILD_NOTE}"
    FOUND_JAVA="$(find_java_home || true)"
    if [[ -n "$FOUND_JAVA" ]]; then
      echo "[*] Assembling KMP AntigravityShared.xcframework via Gradle (JAVA_HOME=${FOUND_JAVA})..."
      chmod +x "$ROOT_DIR/gradlew"
      if JAVA_HOME="$FOUND_JAVA" PATH="$FOUND_JAVA/bin:$PATH" \
        "$ROOT_DIR/gradlew" :shared:umbrella:assembleAntigravitySharedDebugXCFramework --no-daemon; then
        POST_BUILD_STATE="$(check_kmp_xcframework_freshness "$ROOT_DIR" "$XCF_PATH")"
        if [[ "$POST_BUILD_STATE" == "FRESH" ]]; then
          USE_KMP_XCF=1
          echo "[+] KMP AntigravityShared.xcframework ready: $XCF_REL"
        else
          echo "[!] Post-build AntigravityShared.xcframework status is ${POST_BUILD_STATE}; refusing to link stale binary." >&2
          if [[ "$REQUIRE_KMP" -eq 1 ]]; then
            exit 1
          fi
          USE_KMP_XCF=0
        fi
      else
        echo "[!] Gradle build for AntigravityShared.xcframework failed." >&2
        FALLBACK_DECISION="$(decide_kmp_xcf_fallback "$XCF_STATE" "$REQUIRE_KMP" "$REBUILD_KMP")"
        if [[ "$FALLBACK_DECISION" == "FAIL" ]]; then
          exit 1
        elif [[ "$FALLBACK_DECISION" == "REUSE_KMP" ]]; then
          echo "[!] Reusing up-to-date (FRESH) AntigravityShared.xcframework on disk."
          USE_KMP_XCF=1
        else
          echo "[!] Refusing to reuse ${XCF_STATE} AntigravityShared.xcframework (would ship stale KMP networking code!)."
          echo "[!] Falling back cleanly to pure-Swift Xcode project (latest AntigravityData engine via #if canImport(AntigravityShared))."
          USE_KMP_XCF=0
        fi
      fi
    else
      FALLBACK_DECISION="$(decide_kmp_xcf_fallback "$XCF_STATE" "$REQUIRE_KMP" "$REBUILD_KMP")"
      if [[ "$FALLBACK_DECISION" == "REUSE_KMP" ]]; then
        echo "[!] JDK 17/21 not found; reusing up-to-date (FRESH) AntigravityShared.xcframework on disk."
        USE_KMP_XCF=1
      elif [[ "$FALLBACK_DECISION" == "FAIL" ]]; then
        echo "[!] JDK 17 or 21 is required to build KMP AntigravityShared.xcframework (current state: ${XCF_STATE})." >&2
        echo "    Install with: brew install openjdk@21" >&2
        exit 1
      else
        if [[ "$XCF_STATE" == "STALE" || "$XCF_STATE" == "INCOMPLETE" || "$XCF_STATE" == "INVALID" ]]; then
          echo "[!] JDK 17/21 not found and on-disk AntigravityShared.xcframework is ${XCF_STATE} — refusing to link stale KMP binary!"
          echo "    Switching Xcode project to latest pure-Swift AntigravityData engine instead."
        else
          echo "[!] JDK 17/21 not detected on this Mac; generating pure-Swift Xcode project (AntigravityData fallback)."
        fi
        echo "    To rebuild and enable the KMP Shared Core XCFramework later, run: brew install openjdk@21 && bash scripts/sync-xcode.sh --rebuild-kmp"
        USE_KMP_XCF=0
      fi
    fi
  else
    echo "[+] KMP AntigravityShared.xcframework is up to date."
    USE_KMP_XCF=1
  fi
fi

# 3. Ensure XcodeGen is installed
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "[*] Installing xcodegen via Homebrew..."
    brew install xcodegen
  else
    echo "[!] xcodegen not found. Install via 'brew install xcodegen' and re-run." >&2
    exit 1
  fi
fi

# 4. Generate fresh PocketAntigravity.xcodeproj from project.yml
TMP_SPEC=""
cleanup_tmp_spec() {
  if [[ -n "${TMP_SPEC:-}" && -f "$TMP_SPEC" ]]; then
    rm -f "$TMP_SPEC"
  fi
}
trap cleanup_tmp_spec EXIT

if [[ "$USE_KMP_XCF" -eq 1 ]]; then
  echo "[*] Generating PocketAntigravity.xcodeproj (with KMP AntigravityShared.xcframework)..."
  xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
else
  TMP_SPEC="$ROOT_DIR/.project.swift-only.tmp.yml"
  write_swift_only_spec "$ROOT_DIR/project.yml" "$TMP_SPEC"
  echo "[*] Generating PocketAntigravity.xcodeproj (pure-Swift mode, without AntigravityShared.xcframework)..."
  xcodegen generate --spec "$TMP_SPEC" --project "$ROOT_DIR"
fi

# 5. Verify generated project points to the monorepo paths
validate_generated_pbxproj "$XCODEPROJ_PATH/project.pbxproj"
echo "[PASS] PocketAntigravity.xcodeproj is synced with the current monorepo layout (apps/ios/*, tests/ios-ui/*)."

if [[ "$LEGACY_DETECTED" -eq 1 || "$CASE_FIXED" -eq 1 ]] && pgrep -x Xcode >/dev/null 2>&1; then
  echo "[!] Note: Xcode is currently running — press Cmd+Q and reopen PocketAntigravity.xcodeproj (or Product -> Clean Build Folder) so Xcode drops any cached path or Package.swift state."
fi

if [[ "$OPEN_XCODE" -eq 1 ]]; then
  echo "[*] Opening PocketAntigravity.xcodeproj in Xcode..."
  open "$XCODEPROJ_PATH"
fi
