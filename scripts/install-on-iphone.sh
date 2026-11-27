#!/usr/bin/env bash
# ==============================================================================
# PocketAntigravity — Build, Sign & Install on Physical iPhone + Start Live Bridge
# Usage on your Mac (with iPhone connected via USB or same Wi-Fi):
#   bash scripts/install-on-iphone.sh
# Optional overrides:
#   TEAM_ID=ABCDE12345 BUNDLE_PREFIX=com.thousandtimes.agpocket bash scripts/install-on-iphone.sh
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WITH_BRIDGE=0
SYNC_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --with-bridge) WITH_BRIDGE=1 ;;
    --swift-only|--rebuild-kmp|--clean|--require-kmp) SYNC_ARGS+=("$arg") ;;
  esac
done

bash "$ROOT_DIR/scripts/sync-xcode.sh" ${SYNC_ARGS[@]+"${SYNC_ARGS[@]}"}

# 1. Detect connected physical iPhone FIRST (excluding Xcode 26/27 DeviceHub Simulators!)
IPHONE_INFO_FILE="$(mktemp "${TMPDIR:-/tmp}/agy-iphone.XXXXXX")"
SIM_LIST_FILE="$(mktemp "${TMPDIR:-/tmp}/agy-sims.XXXXXX")"
DEST_INFO_FILE="$(mktemp "${TMPDIR:-/tmp}/agy-dests.XXXXXX")"
SIGN_PLAN_FILE="$(mktemp "${TMPDIR:-/tmp}/agy-signplan.XXXXXX")"
SETTINGS_JSON_FILE=""
trap 'rm -f "$IPHONE_INFO_FILE" "$SIM_LIST_FILE" "$DEST_INFO_FILE" "$SIGN_PLAN_FILE" ${SETTINGS_JSON_FILE:+"$SETTINGS_JSON_FILE"}' EXIT

xcrun devicectl list devices --json-output "$IPHONE_INFO_FILE" >/dev/null 2>&1 || true
xcrun simctl list devices -j >"$SIM_LIST_FILE" 2>/dev/null || true

DEVICE_REPORT="$(python3 - "$IPHONE_INFO_FILE" "$SIM_LIST_FILE" <<'PY'
import json
import sys

devicectl_path, simctl_path = sys.argv[1], sys.argv[2]

sim_udids = set()
try:
    sim_data = json.load(open(simctl_path, "r", encoding="utf-8"))
    for runtime_devs in (sim_data.get("devices") or {}).values():
        for sdev in runtime_devs or []:
            u = str(sdev.get("udid") or "").strip().lower()
            if u:
                sim_udids.add(u)
except Exception:
    pass

try:
    data = json.load(open(devicectl_path, "r", encoding="utf-8"))
except Exception:
    sys.exit(0)

candidates = []
unavailable_notes = []

for dev in data.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties") or {}
    conn = dev.get("connectionProperties") or {}
    props = dev.get("deviceProperties") or {}

    platform = str(hw.get("platform") or "")
    reality = str(hw.get("reality") or "").strip().lower()
    udid = str(hw.get("udid") or dev.get("identifier") or "").strip()
    core_id = str(dev.get("identifier") or udid).strip()
    transport = str(conn.get("transportType") or "").strip().lower()
    pairing = str(conn.get("pairingState") or "").strip().lower()
    tunnel = str(conn.get("tunnelState") or "").strip().lower()
    name = str(props.get("name") or "iPhone").strip()

    # Strictly exclude Xcode 26/27 DeviceHub Simulators (`reality == "simulated"` or present in `simctl`)
    if reality and reality != "physical":
        continue
    if udid.lower() in sim_udids or core_id.lower() in sim_udids:
        continue
    if transport in ("local", "simulated", "simulator"):
        continue
    if platform != "iOS" or not udid:
        continue

    dev_type = str(hw.get("deviceType") or hw.get("productType") or "")
    is_iphone = ("iphone" in dev_type.lower()) or ("iphone" in name.lower())

    # Note: In CoreDevice (`devicectl`), an idle USB/Wi-Fi connected physical iPhone (`available (paired)`)
    # reports `tunnelState == "disconnected"` until devicectl/xcodebuild opens the DDI tunnel on demand.
    # Only `tunnelState == "unavailable"` means the device is offline / unplugged.
    is_reachable = (pairing == "paired" and tunnel not in ("unavailable", ""))
    if is_reachable:
        is_wired = transport in ("wired", "usb")
        prio = (
            0 if is_iphone else 1,
            0 if is_wired else 1,
            0 if tunnel == "connected" else 1,
        )
        candidates.append((prio, udid, core_id, name, transport or tunnel))
    else:
        unavailable_notes.append(f"{name} (pairing={pairing or 'unknown'}, tunnel={tunnel or 'unknown'}, transport={transport or 'none'})")

if candidates:
    candidates.sort(key=lambda item: item[0])
    _, udid, core_id, name, via = candidates[0]
    print(f"READY|{udid}|{core_id}|{name}|{via}")
elif unavailable_notes:
    print("UNAVAILABLE|" + "; ".join(unavailable_notes))
PY
)"

DEVICE_LINE=""
if [[ "$DEVICE_REPORT" == READY\|* ]]; then
  DEVICE_LINE="${DEVICE_REPORT#READY|}"
fi

# 2. Build ordered list of Signing Plans: (TEAM_ID, BUNDLE_PREFIX, REASON)
#    - Auto-reads Xcode Accounts (`IDEProvisioningTeams` / `IDEProvisioningTeamByIdentifier`) via live `defaults export`
#      and prioritizes your Personal Team (`isFreeProvisioningTeam` / `(Personal Team)`) FIRST!
#    - Prevents corporate Keychain-only certs (e.g. `CG2SCM6AV5` with no Xcode Account) from blocking Personal Team signing.
#    - Avoids shared corporate username collisions (e.g. `id -un == bytedance` -> `com.bytedance.*` rejected by Personal Team)
#    - Reuses cached unexpired exact/wildcard `.mobileprovision` profiles covering DEVICE_UDID when available.
PROBE_UDID=""
if [[ -n "$DEVICE_LINE" ]]; then
  IFS='|' read -r PROBE_UDID _ _ _ <<< "$DEVICE_LINE"
fi

python3 - "$PROBE_UDID" "${TEAM_ID:-}" "${BUNDLE_PREFIX:-}" "$ROOT_DIR/local.signing.xcconfig" >"$SIGN_PLAN_FILE" <<'PY'
from datetime import datetime, timezone
import hashlib
import os
import plistlib
import re
import socket
import subprocess
import sys
from pathlib import Path

device_udid, env_team, env_prefix = sys.argv[1].strip(), sys.argv[2].strip(), sys.argv[3].strip()
local_xcconfig_path = Path(sys.argv[4])

saved_team = ""
saved_prefix = ""
if local_xcconfig_path.is_file():
    for raw_line in local_xcconfig_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        code = raw_line.split("//", 1)[0].strip()
        if not code or "=" not in code:
            continue
        k, v = [p.strip() for p in code.split("=", 1)]
        v = v.strip().strip('"').strip("'").strip()
        if k == "DEVELOPMENT_TEAM" and re.fullmatch(r"[A-Z0-9]{10}", v.upper()):
            saved_team = v.upper()
        elif k == "ANTIGRAVITY_BUNDLE_PREFIX" and re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+", v):
            saved_prefix = v

# Derive a deterministic per-Mac unique prefix (`io.agy.dev<8hex>`) that never collides with corporate namespaces
hw_seed = ""
try:
    ioreg_out = subprocess.check_output(
        ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    m = re.search(r'"IOPlatformUUID"\s*=\s*"([^"]+)"', ioreg_out)
    if m:
        hw_seed = m.group(1)
except Exception:
    pass
if not hw_seed:
    hw_seed = f"{socket.gethostname()}:{os.path.expanduser('~')}"

mac_hash = hashlib.sha256(hw_seed.encode("utf-8")).hexdigest()[:8]
default_prefix = env_prefix or saved_prefix or f"com.thousandtimes.agpocket.dev{mac_hash}"

if env_team and env_prefix:
    print(f"{env_team}|{env_prefix}|explicit TEAM_ID & BUNDLE_PREFIX")
    sys.exit(0)

# 2a. Read signed-in Xcode Accounts & Personal Teams from live cfprefsd (`defaults export`) or Xcode plist
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

active_apple_ids = set()
raw_accounts = xcode_prefs.get("DVTDeveloperAccountManagerAppleIDAccounts")
if isinstance(raw_accounts, list):
    for acc in raw_accounts:
        if isinstance(acc, dict):
            uname = str(acc.get("username") or acc.get("accountName") or "").strip().lower()
            if uname:
                active_apple_ids.add(uname)

team_meta = {}  # tid -> {"name": str, "is_personal": bool, "active_account": bool, "account": str}

def record_xcode_team(entry: dict, account_key: str = ""):
    if not isinstance(entry, dict):
        return
    tid = str(entry.get("teamID") or entry.get("teamId") or entry.get("identifier") or "").strip()
    if not re.fullmatch(r"[A-Z0-9]{10}", tid):
        return
    if env_team and tid != env_team:
        return
    tname = str(entry.get("teamName") or entry.get("name") or "").strip()
    ttype = str(entry.get("teamType") or "").strip().lower()
    is_free = bool(entry.get("isFreeProvisioningTeam"))
    is_personal = is_free or ("personal" in tname.lower()) or (ttype in ("personal", "free"))
    acct_norm = str(account_key or "").strip().lower()
    is_active = (not active_apple_ids) or (not acct_norm) or (acct_norm in active_apple_ids)

    prev = team_meta.get(tid)
    if prev is None:
        team_meta[tid] = {
            "name": tname,
            "is_personal": is_personal,
            "active_account": is_active,
            "account": str(account_key or "").strip(),
        }
    else:
        prev["is_personal"] = prev["is_personal"] or is_personal
        prev["active_account"] = prev["active_account"] or is_active
        if tname and not prev["name"]:
            prev["name"] = tname
        if account_key and not prev["account"]:
            prev["account"] = str(account_key).strip()

def walk_xcode_teams(obj, account_hint: str = ""):
    if isinstance(obj, dict):
        if any(k in obj for k in ("teamID", "teamId")):
            record_xcode_team(obj, account_hint)
        for k, v in obj.items():
            ks = str(k)
            next_hint = ks if "@" in ks else account_hint
            if isinstance(v, dict) and re.fullmatch(r"[A-Z0-9]{10}", ks) and any(
                fld in v for fld in ("teamName", "name", "isFreeProvisioningTeam", "teamType")
            ):
                merged = dict(v)
                merged.setdefault("teamID", ks)
                record_xcode_team(merged, next_hint)
            else:
                walk_xcode_teams(v, next_hint)
    elif isinstance(obj, list):
        for item in obj:
            walk_xcode_teams(item, account_hint)

for pref_key, pref_val in xcode_prefs.items():
    ks = str(pref_key)
    if ks.startswith("IDEProvisioning") or ks.startswith("DVTDeveloperAccount"):
        walk_xcode_teams(pref_val, "")

# 2b. Enumerate unlocked codesigning Team IDs from Keychain (Apple Development / iPhone Developer first)
dev_teams = []
other_teams = []
try:
    sec_out = subprocess.check_output(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    for line in sec_out.splitlines():
        m = re.search(r'"([^"]*\(([A-Z0-9]{10})\))"', line)
        if not m:
            continue
        label, tid = m.group(1), m.group(2)
        if env_team and tid != env_team:
            continue
        is_dev = ("Apple Development" in label) or ("iPhone Developer" in label)
        target_list = dev_teams if is_dev else other_teams
        if tid not in dev_teams and tid not in other_teams:
            target_list.append(tid)
except Exception:
    pass

# 2c. Inspect local cached Provisioning Profiles (Xcode 16/26/27 UserData + Legacy MobileDevice)
#     Also captures Personal Team IDs from cached profile `TeamName` (`(Personal Team)`) even if plist schema changed.
profile_dirs = [
    Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
    Path.home() / "Library/MobileDevice/Provisioning Profiles",
]
now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
parsed_profiles = []
for pdir in profile_dirs:
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
        except Exception:
            continue
        tids = pl.get("TeamIdentifier") or []
        tid = str(tids[0]).strip() if tids else ""
        if not re.fullmatch(r"[A-Z0-9]{10}", tid):
            continue
        if env_team and tid != env_team:
            continue
        tname = str(pl.get("TeamName") or "").strip()
        if "personal" in tname.lower():
            record_xcode_team({"teamID": tid, "teamName": tname, "isFreeProvisioningTeam": True}, "")
        parsed_profiles.append((tid, pl))

xcode_personal_teams = sorted(
    [tid for tid, info in team_meta.items() if info["is_personal"]],
    key=lambda t: (0 if team_meta[t]["active_account"] else 1, t),
)
xcode_other_account_teams = sorted(
    [tid for tid, info in team_meta.items() if not info["is_personal"]],
    key=lambda t: (0 if team_meta[t]["active_account"] else 1, t),
)
xcode_account_team_set = set(xcode_personal_teams) | set(xcode_other_account_teams)
keychain_only_teams = [t for t in (dev_teams + other_teams) if t not in xcode_account_team_set]

all_teams = []
if saved_team and (not env_team or env_team == saved_team):
    all_teams.append(saved_team)
for tid in (xcode_personal_teams + xcode_other_account_teams + keychain_only_teams):
    if tid not in all_teams:
        all_teams.append(tid)
if env_team and env_team not in all_teams:
    all_teams = [env_team]
if not all_teams:
    sys.exit(0)

team_active_profile_count = {t: 0 for t in all_teams}
exact_prefixes_by_team = {}  # (team, prefix) -> set of matched suffixes ("", ".LiveActivity", ".Share")
wildcard_plans_by_team = {}  # team -> list[(rank, cand_prefix, reason)]

for tid, pl in parsed_profiles:
    if tid not in all_teams:
        continue

    exp = pl.get("ExpirationDate")
    if isinstance(exp, datetime):
        exp_naive = exp.astimezone(timezone.utc).replace(tzinfo=None) if exp.tzinfo else exp
        if exp_naive <= now_utc:
            continue

    ent = pl.get("Entitlements") or {}
    # Only Development profiles (`get-task-allow == True`) can sign Debug iphoneos builds
    if ent.get("get-task-allow") is not True:
        continue

    team_active_profile_count[tid] = team_active_profile_count.get(tid, 0) + 1

    prov_devs = [str(d).strip().lower() for d in (pl.get("ProvisionedDevices") or [])]
    if device_udid and device_udid.lower() not in prov_devs:
        continue

    app_id = str(ent.get("application-identifier") or "")
    if not app_id.startswith(f"{tid}."):
        continue
    pattern = app_id[len(tid) + 1 :]

    if pattern == "*":
        cand_prefix = env_prefix or default_prefix
        wildcard_plans_by_team.setdefault(tid, []).append((0, cand_prefix, "cached '*' wildcard profile"))
    elif pattern.endswith(".*"):
        ns = pattern[:-2]
        if not env_prefix:
            cand_prefix = f"{ns}.agpocket{mac_hash[:6]}"
            wildcard_plans_by_team.setdefault(tid, []).append((1, cand_prefix, f"cached '{ns}.*' wildcard profile"))
        elif env_prefix.startswith(ns + "."):
            wildcard_plans_by_team.setdefault(tid, []).append((1, env_prefix, f"cached '{ns}.*' wildcard profile"))
    else:
        matched_ext = False
        for suffix in (".LiveActivity", ".Share"):
            if pattern.endswith(suffix):
                base_p = pattern[: -len(suffix)]
                if not env_prefix or env_prefix == base_p:
                    exact_prefixes_by_team.setdefault((tid, base_p), set()).add(suffix)
                matched_ext = True
                break
        if not matched_ext:
            base_p = pattern
            if not env_prefix or env_prefix == base_p:
                exact_prefixes_by_team.setdefault((tid, base_p), set()).add("")

plans = []
seen = set()

def add_plan(t: str, p: str, reason: str):
    if (t, p) not in seen:
        seen.add((t, p))
        plans.append((t, p, reason))

def describe_team(tid: str, fallback: str) -> str:
    info = team_meta.get(tid)
    if info and info.get("name"):
        return f"{fallback} · {info['name']}"
    return fallback

def enqueue_team_plans(tid: str, tier_label: str):
    # Exact cached 3-target profiles for this team first
    for (t, base_p), suffixes in exact_prefixes_by_team.items():
        if t == tid and {"", ".LiveActivity", ".Share"}.issubset(suffixes):
            add_plan(tid, base_p, describe_team(tid, f"{tier_label} · cached exact profiles"))
    # Wildcard profiles for this team
    for _, cand_p, reason in sorted(wildcard_plans_by_team.get(tid, []), key=lambda x: x[0]):
        add_plan(tid, cand_p, describe_team(tid, f"{tier_label} · {reason}"))
    # Automatic signing with unique per-Mac prefix
    add_plan(tid, default_prefix, describe_team(tid, f"{tier_label} · Automatic Signing"))

# Priority 0: Saved machine-local signing in local.signing.xcconfig (if not overridden by conflicting env TEAM_ID)
if saved_team and (not env_team or env_team == saved_team):
    saved_first_prefix = env_prefix or saved_prefix or "com.thousandtimes.agpocket"
    add_plan(saved_team, saved_first_prefix, describe_team(saved_team, "Saved local.signing.xcconfig"))
    if not env_prefix and saved_first_prefix == "com.thousandtimes.agpocket":
        add_plan(saved_team, f"com.thousandtimes.agpocket.dev{mac_hash}", describe_team(saved_team, "Saved Team · per-Mac Bundle ID"))

# Priority 1: Signed-in Xcode Personal Teams (auto-read from Xcode Accounts — avoids corporate Keychain collisions!)
for tid in xcode_personal_teams:
    enqueue_team_plans(tid, "Xcode Personal Team")

# Priority 2: Other signed-in Xcode Account Teams (paid Individual / Organization accounts)
sorted_other_xcode = sorted(
    xcode_other_account_teams,
    key=lambda t: (0 if team_meta[t]["active_account"] else 1, -team_active_profile_count.get(t, 0), t),
)
for tid in sorted_other_xcode:
    enqueue_team_plans(tid, "Xcode Account Team")

# Priority 3: Keychain-only Teams without an active Xcode Account (last-resort offline fallback)
sorted_keychain_only = sorted(
    keychain_only_teams,
    key=lambda t: (0 if t in dev_teams else 1, -team_active_profile_count.get(t, 0)),
)
for tid in sorted_keychain_only:
    enqueue_team_plans(tid, "Keychain-only Team")

# Explicit TEAM_ID override if not already in the discovered lists
if env_team and env_team not in (xcode_personal_teams + xcode_other_account_teams + keychain_only_teams):
    enqueue_team_plans(env_team, "Explicit TEAM_ID")

for tid, cand_p, reason in plans:
    print(f"{tid}|{cand_p}|{reason}")
PY

persist_local_signing_xcconfig() {
  local target_team="$1"
  local target_prefix="$2"
  local only_if_missing="${3:-0}"
  python3 - "$ROOT_DIR/local.signing.xcconfig" "$target_team" "$target_prefix" "$only_if_missing" <<'PY'
import re
import sys
from pathlib import Path

DEFAULT_PREFIX = "com.thousandtimes.agpocket"
xcconfig_path = Path(sys.argv[1])
team_id = sys.argv[2].strip().upper()
bundle_prefix = sys.argv[3].strip()
only_if_missing = sys.argv[4] == "1"

if not re.fullmatch(r"[A-Z0-9]{10}", team_id):
    sys.exit(0)

if xcconfig_path.is_file():
    orig_lines = xcconfig_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    if only_if_missing:
        for line in orig_lines:
            code = line.split("//", 1)[0].strip()
            if code.startswith("DEVELOPMENT_TEAM") and "=" in code:
                existing = code.split("=", 1)[1].strip().strip('"').strip("'")
                if re.fullmatch(r"[A-Z0-9]{10}", existing.upper()):
                    sys.exit(0)
else:
    orig_lines = [
        "// Machine-local Xcode signing overrides (gitignored; survives `git pull`, `xcodegen`, and `--clean`).",
        "// Update anytime via: bash scripts/sync-xcode.sh --team <TEAM_ID> [--bundle-prefix <PREFIX>]",
    ]

out_lines = []
replaced_team = False
replaced_prefix = False
for line in orig_lines:
    code = line.split("//", 1)[0].strip()
    if code and "=" in code:
        key = code.split("=", 1)[0].strip()
        if key == "DEVELOPMENT_TEAM":
            out_lines.append(f"DEVELOPMENT_TEAM = {team_id}")
            replaced_team = True
            continue
        if key == "ANTIGRAVITY_BUNDLE_PREFIX":
            if bundle_prefix and bundle_prefix != DEFAULT_PREFIX:
                out_lines.append(f"ANTIGRAVITY_BUNDLE_PREFIX = {bundle_prefix}")
            replaced_prefix = True
            continue
    out_lines.append(line)

if not replaced_team:
    out_lines.append(f"DEVELOPMENT_TEAM = {team_id}")
if bundle_prefix and bundle_prefix != DEFAULT_PREFIX and not replaced_prefix:
    out_lines.append(f"ANTIGRAVITY_BUNDLE_PREFIX = {bundle_prefix}")

xcconfig_path.write_text("\n".join(out_lines).rstrip() + "\n", encoding="utf-8")
PY
}

FIRST_PLAN="$(head -n 1 "$SIGN_PLAN_FILE" || true)"
if [[ -z "$FIRST_PLAN" ]]; then
  echo "[!] 未检测到 Xcode 已登录的 Personal Team 或本地签名证书。"
  echo "    正在打开 PocketAntigravity.xcodeproj —— 请按 Cmd + , 打开 Xcode Settings -> Accounts 登录你的 Apple ID，"
  echo "    然后重新运行 'bash scripts/install-on-iphone.sh'（脚本将自动读取你的 Personal Team），或在 Xcode 顶部选你的 iPhone 按 Cmd + R。"
  open PocketAntigravity.xcodeproj
  if [[ "$WITH_BRIDGE" -eq 1 ]]; then
    exec python3 -u scripts/mac-companion-bridge.py
  fi
  exit 0
fi

IFS='|' read -r FIRST_TEAM_ID FIRST_BUNDLE_PREFIX _ <<< "$FIRST_PLAN"
TEAM_ID="$FIRST_TEAM_ID"
BUNDLE_PREFIX="$FIRST_BUNDLE_PREFIX"
persist_local_signing_xcconfig "$TEAM_ID" "$BUNDLE_PREFIX" 1

if [[ -z "$DEVICE_LINE" ]]; then
  echo "[!] No reachable paired physical iPhone detected."
  if [[ "$DEVICE_REPORT" == UNAVAILABLE\|* ]]; then
    echo "    Seen offline/unpaired iOS hardware: ${DEVICE_REPORT#UNAVAILABLE|}"
  fi
  xcodebuild -project PocketAntigravity.xcodeproj -scheme AGPocket -showdestinations >"$DEST_INFO_FILE" 2>&1 || true
  grep -E "platform:iOS[, }]" "$DEST_INFO_FILE" | grep -v "DVTiPhonePlaceholder" | sed 's/^/    Xcode destination: /' || true
  echo ""
  echo "    Please plug in & unlock your physical iPhone (trust this Mac + enable Settings > Privacy & Security > Developer Mode),"
  echo "    then re-run 'bash scripts/install-on-iphone.sh', or select your iPhone in Xcode (opening project now)..."
  open PocketAntigravity.xcodeproj
  if [[ "$WITH_BRIDGE" -eq 1 ]]; then
    exec python3 -u scripts/mac-companion-bridge.py
  fi
  exit 0
fi

IFS='|' read -r DEVICE_UDID CORE_DEVICE_ID DEVICE_NAME DEVICE_VIA <<< "$DEVICE_LINE"
echo "[+] Detected Physical iPhone: ${DEVICE_NAME} (UDID=${DEVICE_UDID}, via=${DEVICE_VIA})"

mkdir -p "$ROOT_DIR/.build"
DERIVED_DATA="$ROOT_DIR/.build/DerivedDataDevice"
BUILD_LOG="$ROOT_DIR/.build/xcodebuild-device.log"
ATTEMPT_LOG="$ROOT_DIR/.build/xcodebuild-attempt.log"

: >"$BUILD_LOG"
BUILD_SUCCEEDED=0
while IFS='|' read -r -u 3 CAND_TEAM CAND_PREFIX CAND_REASON; do
  [[ -z "$CAND_TEAM" ]] && continue
  TEAM_ID="$CAND_TEAM"
  BUNDLE_PREFIX="$CAND_PREFIX"
  echo "[*] Trying Team ${TEAM_ID} · Bundle ${BUNDLE_PREFIX} (${CAND_REASON})..."

  : >"$ATTEMPT_LOG"
  if xcodebuild \
    -project PocketAntigravity.xcodeproj \
    -scheme AGPocket \
    -configuration Debug \
    -sdk iphoneos \
    -destination "platform=iOS,id=${DEVICE_UDID}" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ANTIGRAVITY_BUNDLE_PREFIX="$BUNDLE_PREFIX" \
    ENABLE_DEBUG_DYLIB=NO \
    build </dev/null >"$ATTEMPT_LOG" 2>&1; then
    cat "$ATTEMPT_LOG" >>"$BUILD_LOG"
    BUILD_SUCCEEDED=1
    persist_local_signing_xcconfig "$TEAM_ID" "$BUNDLE_PREFIX" 0
    echo "[+] Saved working signing settings (TEAM=${TEAM_ID}, BUNDLE_PREFIX=${BUNDLE_PREFIX}) to gitignored local.signing.xcconfig."
    break
  else
    cat "$ATTEMPT_LOG" >>"$BUILD_LOG"
    FIRST_ERR="$(grep -m 1 -E "error: " "$ATTEMPT_LOG" | sed 's/.*error: //' || true)"
    if [[ -n "$FIRST_ERR" ]]; then
      echo "    [x] Team ${TEAM_ID} (${BUNDLE_PREFIX}) failed: ${FIRST_ERR}"
    else
      echo "    [x] Signing/build attempt with Team ${TEAM_ID} (${BUNDLE_PREFIX}) did not succeed."
    fi
  fi
done 3< "$SIGN_PLAN_FILE"
rm -f "$ATTEMPT_LOG"

if [[ "$BUILD_SUCCEEDED" -ne 1 ]]; then
  # Ensure local.signing.xcconfig is seeded (if empty) with top-priority team before opening Xcode
  persist_local_signing_xcconfig "$FIRST_TEAM_ID" "$FIRST_BUNDLE_PREFIX" 1
  echo ""
  EXPIRED_ACCOUNT="$(sed -n "s/.*Unable to log in with account '\([^']*\)'.*/\1/p" "$BUILD_LOG" | head -n 1 || true)"
  if [[ -n "$EXPIRED_ACCOUNT" ]]; then
    echo "[!] Xcode Apple ID 登录会话已过期 (${EXPIRED_ACCOUNT})，无法自动向 Apple 申请真机描述文件。"
    echo "    工程已自动预填唯一 Bundle ID (${FIRST_BUNDLE_PREFIX}) 与 Team (${FIRST_TEAM_ID})，只需两步即可恢复："
    echo "      1. 在即将弹出的 Xcode 中按 Cmd + , 打开 Settings -> Accounts"
    echo "      2. 选中 '${EXPIRED_ACCOUNT}'，点击 'Sign In Again' 重新输入 Apple ID 密码完成登录"
    echo "      3. 重新执行: bash scripts/install-on-iphone.sh （或直接在 Xcode 顶部选中 ${DEVICE_NAME} 按 Cmd + R）"
    open PocketAntigravity.xcodeproj
    exit 1
  fi

  if grep -qE "maximum number of App IDs|App ID limit|cannot be registered to your development team" "$BUILD_LOG"; then
    echo "[!] 免费 Personal Team 的 7 天 App ID 配额受限或 Bundle ID 冲突。"
    echo "    请换一个未占用的自定义前缀重试，例如："
    echo "      BUNDLE_PREFIX=com.thousandtimes.agpocket.personal1 bash scripts/install-on-iphone.sh"
    exit 1
  fi

  MISSING_TEAM="$(sed -n 's/.*No Account for Team "\([^"]*\)".*/\1/p' "$BUILD_LOG" | head -n 1 || true)"
  if [[ -n "$MISSING_TEAM" ]]; then
    echo "[!] Xcode Accounts 中未登录 Team '${MISSING_TEAM}' 对应的 Apple ID（也未找到可用的 Personal Team 登录态）。"
    echo "    请按以下步骤登录你的个人 Apple ID（Personal Team）："
    echo "      1. 在即将弹出的 Xcode 中按 Cmd + , 打开 Settings -> Accounts -> 左下角 '+' -> Apple Account"
    echo "      2. 登录你的个人 Apple ID 后等待 Personal Team 出现"
    echo "      3. 回到终端重新执行: bash scripts/install-on-iphone.sh（脚本会自动读取并优先使用你的 Personal Team）"
    open PocketAntigravity.xcodeproj
    exit 1
  fi

  echo "[!] xcodebuild failed for physical iPhone (${DEVICE_NAME}). Key errors:"
  grep -E "error:|warning:.*Provisioning|No profiles|Developer Mode" "$BUILD_LOG" | tail -n 30 || true
  echo "    --- Tail of $BUILD_LOG ---"
  tail -n 50 "$BUILD_LOG" || true
  exit 1
fi

# Resolve actual AGPocket.app output location (handles Xcode Custom/Legacy Build Locations & Xcode 27 layouts)
SETTINGS_JSON_FILE="$(mktemp "${TMPDIR:-/tmp}/agy-buildsettings.XXXXXX")"
if ! xcodebuild \
  -project PocketAntigravity.xcodeproj \
  -scheme AGPocket \
  -configuration Debug \
  -sdk iphoneos \
  -destination "platform=iOS,id=${DEVICE_UDID}" \
  -derivedDataPath "$DERIVED_DATA" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ANTIGRAVITY_BUNDLE_PREFIX="$BUNDLE_PREFIX" \
  -showBuildSettings \
  -json >"$SETTINGS_JSON_FILE" 2>/dev/null; then
  xcodebuild \
    -project PocketAntigravity.xcodeproj \
    -scheme AGPocket \
    -configuration Debug \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ANTIGRAVITY_BUNDLE_PREFIX="$BUNDLE_PREFIX" \
    -showBuildSettings \
    -json >"$SETTINGS_JSON_FILE" 2>/dev/null || true
fi

APP_PATH="$(python3 - "$SETTINGS_JSON_FILE" "$DERIVED_DATA" "$ROOT_DIR" <<'PY'
import json
import os
import plistlib
import sys
from pathlib import Path

settings_path, derived_data, root_dir = sys.argv[1], sys.argv[2], sys.argv[3]

def is_iphoneos_app(app_dir: str) -> bool:
    if not app_dir or not os.path.isdir(app_dir):
        return False
    info_plist = os.path.join(app_dir, "Info.plist")
    if not os.path.isfile(info_plist):
        return False
    try:
        with open(info_plist, "rb") as fp:
            pl = plistlib.load(fp)
        platform_name = str(pl.get("DTPlatformName", "")).lower()
        if platform_name and platform_name != "iphoneos":
            return False
        return True
    except Exception:
        return True

# 1. Exact path reported by xcodebuild -showBuildSettings -json
try:
    raw = Path(settings_path).read_text(encoding="utf-8", errors="ignore")
    bracket_idx = raw.find("[")
    if bracket_idx >= 0:
        entries = json.loads(raw[bracket_idx:])
        for entry in entries:
            bs = entry.get("buildSettings") or {}
            target = entry.get("target", "")
            wrapper = bs.get("WRAPPER_NAME") or bs.get("FULL_PRODUCT_NAME") or "AGPocket.app"
            product_type = bs.get("PRODUCT_TYPE", "")
            if target == "AGPocket" or (product_type == "com.apple.product-type.application" and wrapper == "AGPocket.app"):
                for cand in (
                    bs.get("CODESIGNING_FOLDER_PATH"),
                    os.path.join(bs.get("TARGET_BUILD_DIR", ""), wrapper) if bs.get("TARGET_BUILD_DIR") else None,
                    os.path.join(bs.get("BUILT_PRODUCTS_DIR", ""), wrapper) if bs.get("BUILT_PRODUCTS_DIR") else None,
                ):
                    if cand and cand.endswith(".app") and is_iphoneos_app(cand):
                        print(cand)
                        sys.exit(0)
except Exception:
    pass

# 2. Fallback: scan DerivedData, project build dirs, and Xcode custom build locations
search_roots = [
    (os.path.join(derived_data, "Build", "Products"), False),
    (derived_data, False),
    (os.path.join(root_dir, "Build", "Products"), False),
    (os.path.join(root_dir, "build"), False),
]
xcode_prefs = os.path.expanduser("~/Library/Preferences/com.apple.dt.Xcode.plist")
if os.path.isfile(xcode_prefs):
    try:
        with open(xcode_prefs, "rb") as fp:
            prefs = plistlib.load(fp)
        for key in ("IDECustomBuildProductsPath", "IDECustomDerivedDataLocation"):
            val = prefs.get(key)
            if isinstance(val, str) and val.strip():
                expanded = os.path.expanduser(val.strip())
                if not os.path.isabs(expanded):
                    expanded = os.path.join(root_dir, expanded)
                search_roots.append((expanded, key == "IDECustomDerivedDataLocation"))
    except Exception:
        pass
search_roots.append((os.path.expanduser("~/Library/Developer/Xcode/DerivedData"), True))

found = []
seen = set()
for root, filter_project_prefix in search_roots:
    if not os.path.isdir(root):
        continue
    direct = os.path.join(root, "Debug-iphoneos", "AGPocket.app")
    if direct not in seen and is_iphoneos_app(direct):
        seen.add(direct)
        found.append((os.path.getmtime(direct), direct))
    for dirpath, dirnames, _ in os.walk(root):
        if filter_project_prefix and os.path.abspath(dirpath) == os.path.abspath(root):
            dirnames[:] = [
                d for d in dirnames
                if d.lower().startswith("pocketantigravity") or d in ("Build", "Products", "Debug-iphoneos")
            ]
        else:
            dirnames[:] = [
                d for d in dirnames
                if d not in ("Intermediates.noindex", "Index.noindex", "SourcePackages", "Logs", ".git")
                and not d.endswith(".xctest")
                and not d.endswith(".appex")
            ]
        if "AGPocket.app" in dirnames:
            cand = os.path.join(dirpath, "AGPocket.app")
            dirnames.remove("AGPocket.app")
            if cand not in seen and is_iphoneos_app(cand):
                seen.add(cand)
                found.append((os.path.getmtime(cand), cand))

if found:
    found.sort(key=lambda item: item[0], reverse=True)
    print(found[0][1])
PY
)"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "[!] Could not locate built iphoneos AGPocket.app bundle after xcodebuild succeeded."
  grep -E '"(CODESIGNING_FOLDER_PATH|TARGET_BUILD_DIR|EFFECTIVE_PLATFORM_NAME)"' "$SETTINGS_JSON_FILE" | head -n 12 || true
  if [[ -d "$DERIVED_DATA" ]]; then
    echo "    App bundles currently inside $DERIVED_DATA:"
    find "$DERIVED_DATA" -maxdepth 5 -name "*.app" 2>/dev/null || true
  fi
  echo "    Last lines of $BUILD_LOG:"
  tail -n 50 "$BUILD_LOG" || true
  exit 1
fi
rm -f "$SETTINGS_JSON_FILE"

ACTUAL_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist" 2>/dev/null || echo "${BUNDLE_PREFIX}")"
echo "[+] Built app bundle  : ${APP_PATH} (${ACTUAL_BUNDLE_ID})"
echo "[*] Installing AGPocket.app onto ${DEVICE_NAME}..."
xcrun devicectl device install app --device "$CORE_DEVICE_ID" "$APP_PATH"
if ! xcrun devicectl device process launch --device "$CORE_DEVICE_ID" "$ACTUAL_BUNDLE_ID" >/dev/null 2>&1; then
  echo "[!] Installed on ${DEVICE_NAME}! If launch was blocked by iOS first-time signing trust:"
  echo "    On iPhone, open Settings > General > VPN & Device Management -> trust your Apple ID certificate, then tap AG Pocket."
fi

echo ""
echo "[PASS] AGPocket.app installed on ${DEVICE_NAME}!"
echo "       1. In Antigravity Desktop on your Mac/PC, click 'Remote Control' to open the QR code."
echo "       2. On your iPhone -> Settings tab -> tap 'Scan Remote Control QR Code' and sign in with Google."
echo "       (No bridge script or Tailscale needed — works over Wi-Fi and 5G cellular!)"
if [[ "$WITH_BRIDGE" -eq 1 ]]; then
  echo ""
  echo "[*] Starting optional Mac Companion Bridge (--with-bridge)..."
  exec python3 -u scripts/mac-companion-bridge.py
fi
