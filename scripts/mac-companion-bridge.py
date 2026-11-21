#!/usr/bin/env python3
"""Antigravity iOS — Mac Companion Bridge (`scripts/mac-companion-bridge.py`).

Bridges `iOSAntigravity` (on iPhone / iPad / Xcode Simulator over LAN or Tailscale)
to all live running Antigravity Desktop `language_server` / `agy --hub` processes
(`exa.language_server_pb.LanguageServerService`).

What it does automatically on macOS:
1. Scans `ps aux` + `lsof` for ALL running Antigravity `language_server`, `antigravity_tools`,
   and `agy --hub` (`--hub-port=<port>`) processes, extracting their dynamic `--csrf_token`
   and loopback HTTPS/HTTP Connect-RPC ports, and re-discovers periodically.
2. Subscribes in the background to `JetboxSubscribeToSummaries` (Antigravity 2.0.11+ Jetbox
   all-time conversation stream) and `ProjectUpdatesStream` + `ReadProject` (plus
   `~/.gemini/config/projects/*.json` and `~/Library/Application Support/Antigravity/config/projects/*.json`),
   so ALL local and cloud (`☁️ owner/repo`) project conversations appear on iOS and update in real time.
3. Federates `GetWorkspaceInfos` and `GetAllCascadeTrajectories` across all discovered backends
   and Jetbox streams, while filtering out synthetic `iOS Connect-RPC Handshake` probe sessions.
4. Proxies `StartCascade`, `SendUserCascadeMessage`, `GetCascadeTrajectorySteps` (auto-calling
   `LoadTrajectory` if a historical Jetbox session is not yet loaded in memory),
   `HandleCascadeUserInteraction`, `CancelCascadeInvocation`, and `JetboxSubscribeToSummaries`.
5. Implements Mac-local companion RPCs (`OpenWorkspaceInFinder`, `GetTurnDiff` via
   `git diff`, `CreateProjectWorkspace`, and `Automations` persistence).
6. Supports `--standalone-sandbox` when testing without Antigravity Desktop open.
"""

import argparse
import html
import json
import os
import plistlib
import re
import secrets
import socket
import ssl
import struct
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SERVICE_PREFIX = "/exa.language_server_pb.LanguageServerService/"

BRIDGE_CAPABILITY_METHODS = (
    "OpenWorkspaceInFinder",
    "ReadArtifactFile",
    "CreateProjectWorkspace",
    "GetTurnDiff",
    "GitStageFile",
    "GitUnstageFile",
    "GitDiscardFile",
    "GitCommit",
    "GitPush",
    "GetCustomizationsCatalog",
    "ListAutomations",
    "CreateAutomation",
    "TriggerAutomationNow",
    "SetAutomationPaused",
)

BRIDGE_ENUM_DOWNGRADES = {
    "XHIGH": "HIGH",
    "xhigh": "high",
    "EXTRA": "HIGH",
    "extra": "high",
    "THINKING_EFFORT_EXTRA": "THINKING_EFFORT_HIGH",
    "THINKING_EFFORT_XHIGH": "THINKING_EFFORT_HIGH",
    "PERMISSION_SCOPE_CONVERSATION": "PERMISSION_SCOPE_TURN",
    "PERMISSION_SCOPE_ALWAYS": "PERMISSION_SCOPE_TURN",
    "PERMISSION_SCOPE_TURN": "PERMISSION_SCOPE_ONCE",
    "ARTIFACT_REVIEW_MODE_TURBO": "ARTIFACT_REVIEW_MODE_AUTO",
    "CASCADE_COMMANDS_AUTO_EXECUTION_EAGER": "CASCADE_COMMANDS_AUTO_EXECUTION_AUTO",
    "PERMISSION_PRESET_DEFAULT": "PERMISSION_PRESET_AUTO",
}


def detect_desktop_version_from_command(cmd_line: str) -> str:
    """Infers the installed Antigravity Desktop version without modifying upstream binaries.

    Inspects:
    1. CLI version arguments (`--ide_version`, `--extension_version`, `--app_version`)
    2. Enclosing macOS `.app/Contents/Info.plist` (`CFBundleShortVersionString`)
    3. Neighboring `product.json` or `package.json` near the binary path
    """
    if not cmd_line:
        return ""
    arg_match = re.search(
        r"--(?:ide_version|extension_version|app_version|antigravity_version)[=\s]+v?(\d+\.\d+(?:\.\d+)?(?:-[A-Za-z0-9.\-]+)?)",
        cmd_line,
    )
    if arg_match:
        return f"v{arg_match.group(1)}"

    # Extract candidate executable path from ps aux command line
    app_match = re.search(r"(/[^:\n]*?\.app)/Contents/", cmd_line)
    if app_match:
        info_plist = Path(app_match.group(1)) / "Contents" / "Info.plist"
        if info_plist.is_file():
            try:
                with info_plist.open("rb") as f:
                    plist_data = plistlib.load(f)
                ver = str(plist_data.get("CFBundleShortVersionString") or "").strip()
                if re.match(r"^v?\d+\.\d+", ver):
                    return ver if ver.startswith("v") else f"v{ver}"
            except Exception:
                pass

    path_match = re.search(r"(/[^\s]+?(?:language_server|antigravity_tools|agy)[^\s]*)", cmd_line)
    if path_match:
        bin_path = Path(path_match.group(1))
        for parent in list(bin_path.parents)[:6]:
            for meta_name in ("product.json", "package.json"):
                meta_file = parent / meta_name
                if meta_file.is_file():
                    try:
                        obj = json.loads(meta_file.read_text(encoding="utf-8"))
                        ver = str(obj.get("version") or obj.get("antigravityVersion") or "").strip()
                        if re.match(r"^v?\d+\.\d+", ver):
                            return ver if ver.startswith("v") else f"v{ver}"
                    except Exception:
                        continue
    return ""


def recursively_strip_field(obj, field_name: str) -> tuple[object, bool]:
    """Recursively strips `field_name` from nested dicts/lists, folding stripped rich items into text."""
    if isinstance(obj, dict):
        removed = False
        new_dict = {}
        for k, v in obj.items():
            if k == field_name:
                removed = True
                continue
            if k == "items" and isinstance(v, list) and field_name in ("codeQuote", "mention", "media"):
                new_items = []
                for entry in v:
                    if isinstance(entry, dict):
                        container = entry.get("item") if isinstance(entry.get("item"), dict) else entry
                        if isinstance(container, dict) and isinstance(container.get(field_name), dict):
                            sub = container[field_name]
                            label = sub.get("label") or sub.get("uri") or sub.get("targetUri") or sub.get("filePath") or field_name
                            snippet = sub.get("snippet") or ""
                            if snippet:
                                new_items.append({"text": f"[Context: {label}]\n{snippet}"})
                            else:
                                new_items.append({"text": f"[Attached {field_name}: {label}]"})
                            removed = True
                            continue
                    cleaned_entry, r_entry = recursively_strip_field(entry, field_name)
                    if r_entry:
                        removed = True
                    new_items.append(cleaned_entry)
                new_dict[k] = new_items
            else:
                cleaned_val, r_val = recursively_strip_field(v, field_name)
                if r_val:
                    removed = True
                new_dict[k] = cleaned_val
        return new_dict, removed
    if isinstance(obj, list):
        removed = False
        new_list = []
        for elem in obj:
            cleaned_elem, r_elem = recursively_strip_field(elem, field_name)
            if r_elem:
                removed = True
            new_list.append(cleaned_elem)
        return new_list, removed
    return obj, False


def recursively_downgrade_enum(obj, invalid_val: str, replacement: str) -> tuple[object, bool]:
    """Recursively replaces exact string occurrences of `invalid_val` with `replacement`."""
    if isinstance(obj, str):
        if obj == invalid_val:
            return replacement, True
        return obj, False
    if isinstance(obj, dict):
        replaced = False
        out = {}
        for k, v in obj.items():
            nv, r = recursively_downgrade_enum(v, invalid_val, replacement)
            if r:
                replaced = True
            out[k] = nv
        return out, replaced
    if isinstance(obj, list):
        replaced = False
        out = []
        for elem in obj:
            ne, r = recursively_downgrade_enum(elem, invalid_val, replacement)
            if r:
                replaced = True
            out.append(ne)
        return out, replaced
    return obj, False


def recursively_strip_keys_with_value(obj, target_val: str) -> tuple[object, bool]:
    """Secondary fallback for unknown future enum values not present in BRIDGE_ENUM_DOWNGRADES:
    recursively removes any dict key whose string value equals `target_val` so older Desktop hosts
    fall back to protobuf defaults."""
    if isinstance(obj, dict):
        removed = False
        out = {}
        for k, v in obj.items():
            if isinstance(v, str) and v == target_val:
                removed = True
                continue
            nv, r = recursively_strip_keys_with_value(v, target_val)
            if r:
                removed = True
            out[k] = nv
        return out, removed
    if isinstance(obj, list):
        removed = False
        out = []
        for elem in obj:
            ne, r = recursively_strip_keys_with_value(elem, target_val)
            if r:
                removed = True
            out.append(ne)
        return out, removed
    return obj, False


SYNTHETIC_PROBE_PATTERNS = (
    "ios connect-rpc handshake",
    "reply in one short sentence confirming ios connect-rpc handshake",
    "verify ios remote control connection",
)


def make_unverified_ssl_context() -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def urlopen_direct(req: urllib.request.Request, timeout: float = 15.0, ssl_ctx: ssl.SSLContext = None):
    """Opens HTTP/HTTPS requests while bypassing system/env HTTP proxies for loopback (`127.0.0.1`/`localhost`)."""
    parsed = urllib.parse.urlparse(req.full_url)
    host = (parsed.hostname or "").lower()
    handlers = []
    if host in ("127.0.0.1", "localhost", "::1"):
        handlers.append(urllib.request.ProxyHandler({}))
    if parsed.scheme == "https" and ssl_ctx is not None:
        handlers.append(urllib.request.HTTPSHandler(context=ssl_ctx))
    opener = urllib.request.build_opener(*handlers)
    return opener.open(req, timeout=timeout)


def detect_lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"


def is_synthetic_probe_summary(summary_obj: dict) -> bool:
    """Returns True if a trajectory summary is a leftover synthetic CLI verification probe."""
    if not isinstance(summary_obj, dict):
        return False
    ann = summary_obj.get("annotations") if isinstance(summary_obj.get("annotations"), dict) else {}
    candidates = [
        summary_obj.get("summary"),
        summary_obj.get("title"),
        ann.get("title"),
    ]
    for text in candidates:
        if isinstance(text, str) and text.strip():
            lower = text.strip().lower()
            if any(pat in lower for pat in SYNTHETIC_PROBE_PATTERNS):
                return True
    return False


def discover_all_local_language_servers() -> list[dict]:
    """Discovers ALL running Antigravity `language_server`, `antigravity_tools`, and `agy --hub` backends."""
    try:
        ps_out = subprocess.check_output(
            ["ps", "aux"], text=True, stderr=subprocess.DEVNULL, timeout=2.5
        )
    except Exception:
        return []

    candidates = []
    for line in ps_out.splitlines():
        if "mac-companion-bridge" in line or "verify-live-rpc-flow" in line:
            continue
        csrf_match = re.search(r"--csrf_token[=\s]+([A-Za-z0-9_\-]+)", line)
        if not csrf_match:
            continue
        is_target_proc = (
            "language_server" in line
            or "antigravity_tools" in line
            or "--subclient_type" in line
            or "--hub-port" in line
            or re.search(r"(?:^|/|\\)agy(?:\.exe)?\b", line) is not None
        )
        if not is_target_proc:
            continue
        parts = line.split()
        if len(parts) < 2 or not parts[1].isdigit():
            continue
        pid = int(parts[1])
        csrf_token = csrf_match.group(1)
        is_hub = (
            "--subclient_type hub" in line
            or "--subclient_type=hub" in line
            or "--hub-port" in line
            or ("--standalone" in line and "--workspace_id" not in line)
        )
        ws_id_m = re.search(r"--workspace_id[=\s]+([^\s]+)", line)
        ws_id = ws_id_m.group(1) if ws_id_m else ""
        ws_id_lower = ws_id.lower()
        is_remote_ws = any(
            marker in ws_id_lower
            for marker in (
                "vscode_remote",
                "vscode-remote",
                "vscode_vfs",
                "vscode-vfs",
                "ssh_remote",
                "ssh-remote",
                "tunnel",
                "codespace",
                "dev_container",
                "dev-container",
                "antigravity_cloud",
                "antigravity-cloud",
                "jetski",
            )
        ) or (
            sys.platform == "darwin"
            and ws_id_lower.startswith(("file_home_", "file_root_", "file_workspace_", "file_workspaces_"))
        )
        hinted_ports = [
            int(p)
            for p in re.findall(r"--(?:hub[-_]|extension_server_)?[A-Za-z0-9_]*port[=\s]+(\d+)", line)
            if 1024 <= int(p) <= 65535
        ]
        desktop_ver = detect_desktop_version_from_command(line)
        candidates.append((0 if is_hub else 1, pid, csrf_token, hinted_ports, is_hub, ws_id, is_remote_ws, desktop_ver))

    candidates.sort(key=lambda item: (item[0], item[1]))
    ctx = make_unverified_ssl_context()
    deadline = time.monotonic() + 7.5
    discovered = []
    seen_urls = set()

    for _, pid, csrf_token, hinted_ports, is_hub, ws_id, is_remote_ws, desktop_ver in candidates:
        if time.monotonic() > deadline:
            break
        ports = list(dict.fromkeys(hinted_ports))
        try:
            lsof_out = subprocess.check_output(
                ["lsof", "-nP", "-a", "-p", str(pid), "-iTCP", "-sTCP:LISTEN"],
                text=True,
                stderr=subprocess.DEVNULL,
                timeout=2.0,
            )
            for row in lsof_out.splitlines():
                m = re.search(r":(\d+)\s+\(LISTEN\)", row)
                if m:
                    p = int(m.group(1))
                    if p not in ports:
                        ports.append(p)
        except Exception:
            pass

        schemes = ("http", "https") if is_hub else ("https", "http")
        probe_methods = ("GetAllCascadeTrajectories", "GetUserStatus", "GetUnleashData")

        found_for_pid = False
        for port in ports:
            if time.monotonic() > deadline or found_for_pid:
                break
            for scheme in schemes:
                base_url = f"{scheme}://127.0.0.1:{port}"
                if base_url in seen_urls:
                    continue
                for probe_method in probe_methods:
                    probe_url = f"{base_url}{SERVICE_PREFIX}{probe_method}"
                    req = urllib.request.Request(
                        probe_url,
                        data=b"{}",
                        method="POST",
                        headers={
                            "Content-Type": "application/json",
                            "Connect-Protocol-Version": "1",
                            "x-codeium-csrf-token": csrf_token,
                        },
                    )
                    try:
                        with urlopen_direct(
                            req,
                            timeout=0.75,
                            ssl_ctx=ctx if scheme == "https" else None,
                        ) as resp:
                            if 200 <= resp.status < 300:
                                seen_urls.add(base_url)
                                discovered.append(
                                    {
                                        "pid": pid,
                                        "upstream_url": base_url,
                                        "upstream_csrf": csrf_token,
                                        "is_hub": is_hub,
                                        "workspace_id": ws_id,
                                        "is_remote_workspace": is_remote_ws,
                                        "desktop_version": desktop_ver,
                                    }
                                )
                                found_for_pid = True
                                break
                    except Exception:
                        continue
                if found_for_pid:
                    break
    return discovered


def discover_local_language_server():
    """Returns the primary (Hub-preferred) running Antigravity backend."""
    backends = discover_all_local_language_servers()
    return backends[0] if backends else None


def encode_connect_frame(payload: bytes, flags: int = 0x00) -> bytes:
    return struct.pack(">BI", flags, len(payload)) + payload


def encode_varint(value: int) -> bytes:
    if value == 0:
        return b"\x00"
    out = bytearray()
    while value > 0x7F:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value & 0x7F)
    return bytes(out)


def encode_ld(field_no: int, payload: bytes) -> bytes:
    return encode_varint((field_no << 3) | 2) + encode_varint(len(payload)) + payload


def encode_varint_field(field_no: int, value: int) -> bytes:
    return encode_varint((field_no << 3) | 0) + encode_varint(value)


def decode_varint(buf: bytes, offset: int) -> tuple[int, int] | None:
    """Decodes an unsigned Protobuf LEB128 varint starting at `offset`."""
    result = 0
    shift = 0
    n = len(buf)
    while offset < n:
        b = buf[offset]
        offset += 1
        result |= (b & 0x7F) << shift
        if (b & 0x80) == 0:
            return result, offset
        shift += 7
        if shift >= 64:
            return None
    return None


def decode_get_steps_protobuf_request(raw_body: bytes) -> tuple[str, int, int]:
    """Parses a binary Protobuf `GetCascadeTrajectoryStepsRequest`.

    Fields:
      1 (LD string): cascade_id
      2 (varint):    step_offset (default 0)
      3 (varint):    optional legacy count_hint (default 0)
    """
    cascade_id = ""
    step_offset = 0
    count_hint = 0
    offset = 0
    n = len(raw_body)
    while offset < n:
        parsed_tag = decode_varint(raw_body, offset)
        if parsed_tag is None:
            break
        tag, offset = parsed_tag
        field_no = tag >> 3
        wire_type = tag & 0x07
        if wire_type == 0:
            parsed_val = decode_varint(raw_body, offset)
            if parsed_val is None:
                break
            val, offset = parsed_val
            if field_no == 2:
                step_offset = max(0, int(val))
            elif field_no == 3:
                count_hint = max(0, int(val))
        elif wire_type == 2:
            parsed_len = decode_varint(raw_body, offset)
            if parsed_len is None:
                break
            length, offset = parsed_len
            if offset + length > n:
                break
            payload = raw_body[offset : offset + length]
            offset += length
            if field_no == 1:
                cascade_id = payload.decode("utf-8", errors="ignore")
        elif wire_type == 1:
            offset = min(n, offset + 8)
        elif wire_type == 5:
            offset = min(n, offset + 4)
        else:
            break
    return cascade_id, step_offset, count_hint


CLOUD_URI_PREFIXES = (
    "cloud://",
    "https://github.com/",
    "http://github.com/",
    "vscode-remote://",
    "vscode-vfs://",
    "ssh://",
    "remote://",
    "jetski://",
    "antigravity-cloud://",
    "antigravity-remote://",
    "devbox://",
    "codespace://",
)

GENERIC_CLOUD_CONTAINER_ROOTS = {
    "/home/antigravity",
    "/workspace",
    "/workspaces",
    "/root",
}


def read_desktop_remote_workspaces() -> dict[str, str]:
    """Reads Antigravity Desktop `workspaceStorage/*/workspace.json` to map remote workspace paths/names to their remote URI."""
    remote_by_key: dict[str, str] = {}
    local_basenames: set[str] = set()
    candidate_dirs = [
        Path.home() / "Library/Application Support/Antigravity/User/workspaceStorage",
        Path.home() / ".config/Antigravity/User/workspaceStorage",
    ]
    for root_dir in candidate_dirs:
        try:
            if not root_dir.is_dir():
                continue
            for ws_json in root_dir.glob("*/workspace.json"):
                try:
                    obj = json.loads(ws_json.read_text(encoding="utf-8", errors="ignore"))
                    folder = str(obj.get("folder") or obj.get("workspace") or "").strip()
                    if not folder:
                        continue
                    decoded = urllib.parse.unquote(folder).rstrip("/")
                    if decoded.startswith("file://"):
                        local_path = decoded[len("file://") :]
                        if os.path.exists(local_path):
                            local_basenames.add(Path(local_path).name.lower())
                        continue
                    parsed = urllib.parse.urlparse(decoded)
                    if parsed.scheme and parsed.scheme != "file":
                        path_part = parsed.path.rstrip("/")
                        if path_part:
                            remote_by_key[f"path:{path_part.lower()}"] = folder
                            base = Path(path_part).name.lower()
                            if base:
                                remote_by_key.setdefault(f"name:{base}", folder)
                except Exception:
                    continue
        except Exception:
            continue

    for base in local_basenames:
        remote_by_key.pop(f"name:{base}", None)
    return remote_by_key


def extract_github_repo_slug(raw_value: str) -> str:
    text = (raw_value or "").strip()
    if not text:
        return ""
    m = re.search(r"github\.com[:/]+([A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-]+?)(?:\.git)?/?$", text)
    if m:
        return m.group(1)
    if re.match(r"^[A-Za-z0-9_.\-]+/[A-Za-z0-9_.\-]+$", text):
        return text
    return ""


def classify_workspace_uri(
    uri: str,
    cascade_id: str = "",
    source: str = "",
    backend: dict | None = None,
    remote_ws_index: dict[str, str] | None = None,
    is_live_darwin: bool | None = None,
) -> tuple[bool, str, str]:
    """Returns `(is_cloud, normalized_uri, slug_hint)` for a workspace URI and session metadata."""
    raw_uri = (uri or "").strip()
    decoded_uri = urllib.parse.unquote(raw_uri).rstrip("/")
    cid_lower = (cascade_id or "").strip().lower()
    src_lower = (source or "").strip().lower()
    check_darwin = (sys.platform == "darwin") if is_live_darwin is None else is_live_darwin

    is_cloud = False
    if (
        cid_lower.startswith("v1/")
        or "jetski_remote_agents" in cid_lower
        or "remote_agent" in cid_lower
        or any(tok in src_lower for tok in ("cloud", "remote", "jetski", "github"))
        or bool((backend or {}).get("is_remote_workspace"))
    ):
        is_cloud = True

    lower_uri = decoded_uri.lower()
    if lower_uri.startswith(CLOUD_URI_PREFIXES):
        is_cloud = True
        if lower_uri.startswith(("https://github.com/", "http://github.com/")):
            gh_slug = extract_github_repo_slug(decoded_uri)
            if gh_slug:
                return True, f"cloud://{gh_slug}", gh_slug.split("/")[-1]
        if lower_uri.startswith("cloud://"):
            tail = decoded_uri[len("cloud://") :].strip("/")
            slug = tail.split("/")[-1] if tail else "cloud"
            return True, f"cloud://{tail}" if tail else "cloud://workspace", slug
        if lower_uri.startswith("vscode-vfs://"):
            parsed = urllib.parse.urlparse(decoded_uri)
            parts = [p for p in parsed.path.split("/") if p]
            if len(parts) >= 2:
                gh_slug = f"{parts[0]}/{parts[1]}"
                return True, f"cloud://{gh_slug}", parts[1]
        parsed = urllib.parse.urlparse(decoded_uri)
        slug = Path(parsed.path.rstrip("/")).name or parsed.netloc or "cloud"
        return True, raw_uri, slug

    if decoded_uri.startswith("file://"):
        fs_path = decoded_uri[len("file://") :].rstrip("/")
        # Antigravity Cloud VM container filesystem (`/home/antigravity/<owner>/<repo>`)
        if fs_path == "/home/antigravity" or fs_path.startswith("/home/antigravity/"):
            rel = fs_path[len("/home/antigravity") :].strip("/")
            parts = [p for p in rel.split("/") if p]
            if len(parts) >= 2:
                repo_slug = f"{parts[0]}/{parts[1]}"
                return True, f"cloud://{repo_slug}", parts[1]
            if len(parts) == 1:
                return True, f"cloud://{parts[0]}", parts[0]
            return True, "cloud://antigravity", "antigravity"

        if remote_ws_index:
            matched_remote = remote_ws_index.get(f"path:{fs_path.lower()}")
            if not matched_remote and not os.path.exists(fs_path):
                base = Path(fs_path).name.lower()
                matched_remote = remote_ws_index.get(f"name:{base}")
            if matched_remote:
                return classify_workspace_uri(
                    matched_remote,
                    cascade_id=cascade_id,
                    source=source,
                    backend=backend,
                    remote_ws_index=None,
                    is_live_darwin=check_darwin,
                )

        if check_darwin and fs_path.startswith(("/home/", "/root/", "/workspace/", "/workspaces/")):
            if not os.path.exists(fs_path):
                slug = Path(fs_path).name or "cloud"
                parts = [p for p in fs_path.strip("/").split("/") if p]
                if len(parts) >= 3 and parts[0] in ("home", "workspace", "workspaces"):
                    repo_slug = f"{parts[-2]}/{parts[-1]}"
                    return True, f"cloud://{repo_slug}", slug
                return True, f"cloud://{slug}", slug

        slug = Path(fs_path).name or "workspace"
        if is_cloud:
            return True, f"cloud://{slug}", slug
        return False, raw_uri, slug

    if raw_uri:
        gh_slug = extract_github_repo_slug(raw_uri)
        if gh_slug:
            return True, f"cloud://{gh_slug}", gh_slug.split("/")[-1]
        if is_cloud:
            clean = raw_uri.strip("/")
            return True, f"cloud://{clean}", clean.split("/")[-1]
        return False, raw_uri, Path(raw_uri.rstrip("/")).name or raw_uri

    return is_cloud, "", ""


def select_primary_workspace_entry(workspaces: list) -> dict | None:
    """Picks the most specific repository workspace entry, skipping generic Cloud VM container roots like `/home/antigravity`."""
    if not isinstance(workspaces, list):
        return None
    valid_entries = []
    for entry in workspaces:
        if not isinstance(entry, dict):
            continue
        uri = (entry.get("workspaceFolderAbsoluteUri") or entry.get("workspaceUri") or "").strip()
        if uri:
            valid_entries.append((uri, entry))
    if not valid_entries:
        return None

    for uri, entry in valid_entries:
        decoded = urllib.parse.unquote(uri).rstrip("/")
        if decoded.startswith("cloud://") or decoded.startswith("vscode-remote://") or decoded.startswith("vscode-vfs://"):
            return entry

    for uri, entry in valid_entries:
        decoded = urllib.parse.unquote(uri).rstrip("/")
        fs_path = decoded[len("file://") :].rstrip("/") if decoded.startswith("file://") else decoded
        if fs_path not in GENERIC_CLOUD_CONTAINER_ROOTS:
            return entry

    return valid_entries[0][1]


def parse_local_project_entry(p_obj: dict, is_live_darwin: bool | None = None) -> dict | None:
    """Normalizes a project definition from `ReadProject` or `~/.gemini/config/projects/*.json`."""
    if not isinstance(p_obj, dict):
        return None
    proj_id = str(p_obj.get("id") or p_obj.get("projectId") or "").strip()
    name = str(p_obj.get("name") or p_obj.get("displayName") or p_obj.get("title") or "").strip()
    folder_uri = ""
    is_cloud = bool(p_obj.get("isCloud") or p_obj.get("cloud"))
    has_local_folder = False
    branch = str(p_obj.get("activeBranch") or p_obj.get("gitBranch") or p_obj.get("defaultBranch") or "main").strip() or "main"

    for meta_key in ("runtime", "environment", "executionEnvironment", "hostType", "projectType", "target"):
        meta_val = str(p_obj.get(meta_key) or "").strip().lower()
        if any(tok in meta_val for tok in ("cloud", "remote", "jetski", "vm", "github")):
            is_cloud = True

    raw_resources = p_obj.get("projectResources")
    if isinstance(raw_resources, dict):
        resources = raw_resources.get("resources") or []
    elif isinstance(raw_resources, list):
        resources = raw_resources
    else:
        resources = p_obj.get("resources") or []

    cloud_repo_slug = ""
    for res in resources:
        if not isinstance(res, dict):
            continue
        git_folder = res.get("gitFolder") or res.get("localFolder") or res.get("workspaceFolder") or {}
        if isinstance(git_folder, dict) and (git_folder.get("folderUri") or git_folder.get("workspaceUri") or git_folder.get("path")):
            candidate_uri = str(git_folder.get("folderUri") or git_folder.get("workspaceUri") or git_folder.get("path")).strip()
            if candidate_uri.startswith("/"):
                candidate_uri = f"file://{candidate_uri}"
            if git_folder.get("gitBranch") or git_folder.get("branch"):
                branch = str(git_folder.get("gitBranch") or git_folder.get("branch"))
            c_cloud, norm_uri, _ = classify_workspace_uri(candidate_uri, is_live_darwin=is_live_darwin)
            if c_cloud:
                is_cloud = True
                folder_uri = norm_uri
            else:
                has_local_folder = True
                folder_uri = norm_uri or candidate_uri
                break

        for gh_key in ("githubRepo", "githubRepository", "remoteRepo", "github", "repository", "repo", "pluginResource", "cloudResource"):
            gh_repo = res.get(gh_key)
            if isinstance(gh_repo, str):
                slug = extract_github_repo_slug(gh_repo)
                if slug:
                    cloud_repo_slug = slug
                    is_cloud = True
            elif isinstance(gh_repo, dict):
                owner = str(gh_repo.get("owner") or gh_repo.get("org") or "").strip()
                repo_name = str(
                    gh_repo.get("name")
                    or gh_repo.get("repo")
                    or gh_repo.get("repoName")
                    or gh_repo.get("repositoryName")
                    or ""
                ).strip()
                full_name = (
                    extract_github_repo_slug(str(gh_repo.get("fullName") or ""))
                    or extract_github_repo_slug(str(gh_repo.get("repository") or ""))
                    or extract_github_repo_slug(str(gh_repo.get("resourceId") or ""))
                    or extract_github_repo_slug(str(gh_repo.get("url") or gh_repo.get("htmlUrl") or gh_repo.get("cloneUrl") or gh_repo.get("remoteUrl") or ""))
                    or (f"{owner}/{repo_name}".strip("/") if (owner and repo_name) else "")
                )
                if gh_repo.get("defaultBranch") or gh_repo.get("branch"):
                    branch = str(gh_repo.get("defaultBranch") or gh_repo.get("branch"))
                if full_name:
                    cloud_repo_slug = full_name
                    is_cloud = True
                elif repo_name:
                    cloud_repo_slug = repo_name
                    is_cloud = True

        # Also inspect top-level resource url / uri / repo / resourceId
        res_uri = str(res.get("uri") or res.get("url") or res.get("repository") or res.get("repo") or res.get("resourceId") or "").strip()
        slug_from_res = extract_github_repo_slug(res_uri)
        if slug_from_res:
            cloud_repo_slug = cloud_repo_slug or slug_from_res
            is_cloud = True

    if not folder_uri and not cloud_repo_slug:
        top_repo = extract_github_repo_slug(
            str(p_obj.get("repository") or p_obj.get("githubRepo") or p_obj.get("repoUrl") or "")
        )
        if top_repo:
            cloud_repo_slug = top_repo
            is_cloud = True

    if not folder_uri:
        raw_uri = str(p_obj.get("folderUri") or p_obj.get("workspaceUri") or p_obj.get("path") or "").strip()
        if raw_uri:
            if raw_uri.startswith("/"):
                raw_uri = f"file://{raw_uri}"
            c_cloud, norm_uri, _ = classify_workspace_uri(raw_uri, is_live_darwin=is_live_darwin)
            if c_cloud:
                is_cloud = True
                folder_uri = norm_uri
            else:
                has_local_folder = True
                folder_uri = norm_uri or raw_uri

    if cloud_repo_slug and not has_local_folder:
        is_cloud = True
        folder_uri = f"cloud://{cloud_repo_slug}"
        if not name:
            name = cloud_repo_slug.split("/")[-1]

    if name and "/" in name and not has_local_folder:
        is_cloud = True
        if not folder_uri:
            folder_uri = f"cloud://{name}"

    if not has_local_folder and not folder_uri:
        # Projects registered in Antigravity `ReadProject` without a local gitFolder run in Cloud!
        is_cloud = True
        target_slug = cloud_repo_slug or name or proj_id
        if target_slug:
            folder_uri = f"cloud://{target_slug}"

    if folder_uri and not has_local_folder:
        c_cloud, norm_uri, _ = classify_workspace_uri(folder_uri, is_live_darwin=is_live_darwin)
        if c_cloud:
            is_cloud = True
            folder_uri = norm_uri

    if not name and folder_uri:
        clean = folder_uri.replace("file://", "").replace("cloud://", "").rstrip("/")
        name = Path(clean).name if clean else ""

    if not proj_id and not name:
        return None

    display_name = name or proj_id
    if display_name and "/" in display_name and is_cloud and not p_obj.get("name"):
        display_name = display_name.split("/")[-1]

    return {
        "id": proj_id or display_name,
        "name": display_name,
        "workspaceUri": folder_uri,
        "workspaceFolderAbsoluteUri": folder_uri,
        "displayName": display_name,
        "activeBranch": branch,
        "isCloud": is_cloud,
    }


def read_disk_project_configs() -> dict[str, dict]:
    """Reads Antigravity 2.0 project registry files (`~/.gemini/config/projects/*.json`, etc.)."""
    out: dict[str, dict] = {}
    candidate_dirs = [
        Path.home() / ".gemini/config/projects",
        Path.home() / "Library/Application Support/Antigravity/config/projects",
        Path.home() / ".config/gemini/config/projects",
    ]
    env_home = os.environ.get("GEMINI_HOME", "").strip()
    if env_home:
        candidate_dirs.insert(0, Path(env_home) / "config/projects")

    for d in candidate_dirs:
        try:
            if not d.is_dir():
                continue
            for jf in sorted(d.glob("*.json")):
                try:
                    raw = json.loads(jf.read_text(encoding="utf-8", errors="ignore"))
                    parsed = parse_local_project_entry(raw)
                    if parsed:
                        out[parsed["id"]] = parsed
                except Exception:
                    continue
        except Exception:
            continue
    return out


ARTIFACT_MIME_TYPES = {
    ".html": "text/html",
    ".htm": "text/html",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".gif": "image/gif",
    ".md": "text/markdown",
    ".markdown": "text/markdown",
    ".json": "application/json",
    ".txt": "text/plain",
    ".mmd": "text/plain",
    ".mermaid": "text/plain",
}

FORBIDDEN_ARTIFACT_BASENAMES = {
    ".env",
    ".netrc",
    ".gitcookies",
    "id_rsa",
    "id_ed25519",
    "state.vscdb",
    "state.vscdb.backup",
}

MAX_ARTIFACT_FILE_BYTES = 4 * 1024 * 1024  # 4 MB hard ceiling


def read_trusted_artifact_file(
    raw_uri_or_path: str,
    workspace_roots: list[str] | None = None,
    extra_trusted_roots: list[str] | None = None,
) -> tuple[int, dict]:
    """Reads an `<agent-embed>` or artifact file strictly inside trusted Antigravity brain or workspace roots."""
    import base64

    raw = (raw_uri_or_path or "").strip()
    if not raw:
        return 400, {"ok": False, "error": "Missing uri or path"}

    if raw.lower().startswith("file://"):
        raw = urllib.parse.unquote(raw[len("file://") :])
    else:
        raw = urllib.parse.unquote(raw)

    raw = raw.split("#", 1)[0].split("?", 1)[0]
    if not raw:
        return 400, {"ok": False, "error": "Empty path after normalization"}

    try:
        resolved = os.path.realpath(os.path.expanduser(raw))
    except Exception as exc:
        return 400, {"ok": False, "error": f"Invalid path: {exc}"}

    base_name = os.path.basename(resolved).lower()
    if (
        base_name in FORBIDDEN_ARTIFACT_BASENAMES
        or base_name.startswith(".env.")
        or "/.ssh/" in resolved.replace("\\", "/")
    ):
        return 403, {"ok": False, "error": "Access to sensitive file denied"}

    trusted_roots: list[str] = [
        os.path.realpath(os.path.expanduser("~/.gemini")),
        os.path.realpath(os.path.expanduser("~/Library/Application Support/Antigravity")),
    ]
    env_home = os.environ.get("GEMINI_HOME", "").strip()
    if env_home:
        trusted_roots.append(os.path.realpath(os.path.expanduser(env_home)))
    for ws in workspace_roots or []:
        clean_ws = (ws or "").strip()
        if clean_ws.lower().startswith("file://"):
            clean_ws = urllib.parse.unquote(clean_ws[len("file://") :])
        if clean_ws and os.path.isdir(clean_ws):
            trusted_roots.append(os.path.realpath(clean_ws))
    for extra in extra_trusted_roots or []:
        if extra:
            trusted_roots.append(os.path.realpath(os.path.expanduser(extra)))

    allowed = False
    for root in trusted_roots:
        try:
            if os.path.commonpath([resolved, root]) == root:
                allowed = True
                break
        except ValueError:
            continue

    if not allowed:
        return 403, {"ok": False, "error": "Path is outside trusted Antigravity artifact & workspace roots"}

    if not os.path.isfile(resolved):
        return 404, {"ok": False, "error": "Artifact file not found"}

    size_bytes = os.path.getsize(resolved)
    if size_bytes > MAX_ARTIFACT_FILE_BYTES:
        return 413, {"ok": False, "error": f"Artifact file exceeds {MAX_ARTIFACT_FILE_BYTES} byte limit"}

    ext = Path(resolved).suffix.lower()
    mime = ARTIFACT_MIME_TYPES.get(ext, "application/octet-stream")
    data = Path(resolved).read_bytes()
    is_text = mime.startswith("text/") or mime in ("image/svg+xml", "application/json")
    if is_text:
        try:
            text_val = data.decode("utf-8")
            return 200, {
                "ok": True,
                "path": resolved,
                "mimeType": mime,
                "encoding": "utf-8",
                "content": text_val,
                "sizeBytes": len(data),
            }
        except UnicodeDecodeError:
            pass

    return 200, {
        "ok": True,
        "path": resolved,
        "mimeType": mime,
        "encoding": "base64",
        "content": base64.b64encode(data).decode("ascii"),
        "sizeBytes": len(data),
    }


class CompanionState:
    """Stateful companion store for Automations, Jetbox live cache, and Standalone Sandbox testing."""

    def __init__(self, workspace_root: str, is_live_proxy: bool = False):
        self.lock = threading.Lock()
        self.workspace_root = workspace_root
        self.is_live_proxy = is_live_proxy
        slug = Path(workspace_root).name or "iOSAntigravity"
        uri = f"file://{workspace_root}"
        self.workspaces = [
            {
                "workspaceUri": uri,
                "displayName": slug,
                "activeBranch": "main",
                "indexedFiles": [
                    "apps/ios/App/Application/AntigravityApp.swift",
                    "apps/ios/Packages/AntigravityData/Sources/AntigravityData/Protocol/AntigravityRPCClient.swift",
                    "apps/ios/Packages/AntigravityData/Sources/AntigravityData/Store/AntigravitySessionStore.swift",
                ],
            }
        ]
        self.trajectories = {
            "cas-live-welcome": {
                "cascadeId": "cas-live-welcome",
                "title": f"Connected to {socket.gethostname()}",
                "projectSlug": slug,
                "workspaceUri": uri,
                "branchName": "main",
                "status": "CORTEX_STEP_STATUS_DONE",
                "stepCount": 2,
                "statusSubtitle": "Done · Ready for live prompts",
                "isPinned": True,
                "isArchived": False,
                "isUnread": False,
            }
        }
        self.steps_by_cascade = {
            "cas-live-welcome": [
                {
                    "stepIndex": 0,
                    "type": "CORTEX_STEP_TYPE_USER_INPUT",
                    "status": "CORTEX_STEP_STATUS_DONE",
                    "userInput": {"userResponse": "Verify iOS Remote Control connection."},
                },
                {
                    "stepIndex": 1,
                    "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
                    "status": "CORTEX_STEP_STATUS_DONE",
                    "plannerResponse": {
                        "thinking": "Verified Connect-RPC v1 header and x-codeium-csrf-token.",
                        "thinkingDurationSeconds": 1.2,
                        "response": f"Live Connect-RPC link established with `{socket.gethostname()}` (`{uri}`). You can create new sessions (`StartCascade`) and send messages (`SendUserCascadeMessage`) now.",
                    },
                },
            ]
        }
        self.automations = (
            []
            if is_live_proxy
            else [
                {
                    "id": "auto-nightly-audit",
                    "title": "Nightly dependency & security audit",
                    "projectSlug": slug,
                    "scheduleSummary": f"{slug} · Daily at 02:00 · Flash",
                    "section": "SCHEDULED",
                    "nextRunText": "Tonight, 02:00",
                    "lastRunText": "Succeeded · 6h ago",
                }
            ]
        )
        # Live Jetbox & multi-backend federation caches
        self.jetbox_summaries: dict[str, dict] = {}
        self.projects_by_id: dict[str, dict] = read_disk_project_configs() if is_live_proxy else {}
        self.cascade_to_backend: dict[str, dict] = {}
        self.loaded_trajectories: set[str] = set()

    def build_binary_steps(self, cascade_id: str, count: int = 605) -> bytes:
        out = bytearray()
        for idx in range(count):
            step_buf = bytearray()
            if idx == count - 1:
                step_buf += encode_varint_field(1, 21)  # RUN_COMMAND
                step_buf += encode_varint_field(4, 9)   # WAITING
                cmd_spec = encode_ld(1, b"swift test --package-path apps/ios/Packages/AntigravityData")
                step_buf += encode_ld(56, encode_ld(23, cmd_spec))
            else:
                step_buf += encode_varint_field(1, 15)  # PLANNER_RESPONSE
                step_buf += encode_varint_field(4, 3)   # DONE
                planner = encode_ld(1, f"Step {idx} decoded over binary application/proto.".encode("utf-8"))
                step_buf += encode_ld(20, planner)
            out += encode_ld(1, bytes(step_buf))
        return bytes(out)

    def encode_live_steps_protobuf(self, steps: list[dict]) -> bytes:
        """Encodes live sandbox/companion step dicts into binary Protobuf `GetCascadeTrajectoryStepsResponse`.

        Wire numbers match `ProtobufStepDecoder.swift` and `ProtobufStepCodec.kt` verbatim:
          - Response: repeated field 1 (LD) = Step
          - Step: field 1 (varint) = CortexStepType, field 4 (varint) = CortexStepStatus
          - USER_INPUT (14): field 19 (LD) = {2: userResponse, 3: repeated TextOrScopeItem{1: text, 2: {1: {1: uri}}}}
          - PLANNER_RESPONSE (15): field 20 (LD) = {1: response, 3: thinking, 11: Duration{1: sec, 2: nanos}}
          - RUN_COMMAND (21): field 28 (LD) = {2: cwd, 4: output, 6: exitCode, 13: commandId, 23: commandLine, 25: proposedCommandLine}
          - TASK_BOUNDARY (81): field 93 (LD) = {1: taskName, 2: taskStatus, 3: taskSummary}
          - NOTIFY_USER (82): field 94 (LD) = {1: repeated reviewUris, 2: notificationContent/message}
          - RequestedInteraction (field 56): field 3 (LD) = CascadeRunCommandInteractionSpec{1: cwd, 2: proposedCommandLine}
        """
        step_type_map = {
            "CORTEX_STEP_TYPE_USER_INPUT": 14,
            "CORTEX_STEP_TYPE_PLANNER_RESPONSE": 15,
            "CORTEX_STEP_TYPE_RUN_COMMAND": 21,
            "CORTEX_STEP_TYPE_TASK_BOUNDARY": 81,
            "CORTEX_STEP_TYPE_NOTIFY_USER": 82,
        }
        step_status_map = {
            "CORTEX_STEP_STATUS_UNSPECIFIED": 0,
            "CORTEX_STEP_STATUS_PENDING": 1,
            "CORTEX_STEP_STATUS_IN_PROGRESS": 2,
            "CORTEX_STEP_STATUS_RUNNING": 2,
            "CORTEX_STEP_STATUS_DONE": 3,
            "CORTEX_STEP_STATUS_ERROR": 4,
            "CORTEX_STEP_STATUS_CANCELLED": 6,
            "CORTEX_STEP_STATUS_CANCELED": 6,
            "CORTEX_STEP_STATUS_BLOCKED": 7,
            "CORTEX_STEP_STATUS_WAITING": 9,
        }

        out = bytearray()
        for step in steps:
            if not isinstance(step, dict):
                continue
            raw_type = step.get("type")
            if isinstance(raw_type, int):
                step_type_id = raw_type
            else:
                step_type_id = step_type_map.get(str(raw_type or ""), 15)

            raw_status = step.get("status")
            if isinstance(raw_status, int):
                step_status_id = raw_status
            else:
                step_status_id = step_status_map.get(str(raw_status or ""), 3)

            step_buf = bytearray()
            step_buf += encode_varint_field(1, step_type_id)
            step_buf += encode_varint_field(4, step_status_id)

            if step_type_id == 14:  # USER_INPUT
                user_input = step.get("userInput") if isinstance(step.get("userInput"), dict) else {}
                ui_buf = bytearray()
                user_resp = user_input.get("userResponse") or ""
                if user_resp:
                    ui_buf += encode_ld(2, str(user_resp).encode("utf-8"))
                encoded_file_item = False
                for item in user_input.get("items") or []:
                    if not isinstance(item, dict):
                        continue
                    item_buf = bytearray()
                    txt = item.get("text")
                    if isinstance(txt, str) and txt:
                        item_buf += encode_ld(1, txt.encode("utf-8"))
                    scope = item.get("item")
                    if isinstance(scope, dict):
                        file_info = scope.get("file")
                        if isinstance(file_info, dict):
                            file_uri = (
                                file_info.get("absoluteUri")
                                or file_info.get("uri")
                                or file_info.get("label")
                                or ""
                            )
                            clean_uri = str(file_uri).strip().lstrip("@")
                            if clean_uri:
                                item_buf += encode_ld(
                                    2,
                                    encode_ld(1, encode_ld(1, clean_uri.encode("utf-8"))),
                                )
                                encoded_file_item = True
                    if item_buf:
                        ui_buf += encode_ld(3, bytes(item_buf))
                if not encoded_file_item:
                    for mention in step.get("attachedMentions") or []:
                        if isinstance(mention, str) and mention.strip():
                            clean_mention = mention.strip().lstrip("@")
                            if clean_mention:
                                ui_buf += encode_ld(
                                    3,
                                    encode_ld(
                                        2,
                                        encode_ld(1, encode_ld(1, clean_mention.encode("utf-8"))),
                                    ),
                                )
                if ui_buf:
                    step_buf += encode_ld(19, bytes(ui_buf))

            elif step_type_id == 15:  # PLANNER_RESPONSE
                planner = step.get("plannerResponse") if isinstance(step.get("plannerResponse"), dict) else {}
                pr_buf = bytearray()
                resp_text = planner.get("response") or ""
                thinking_text = planner.get("thinking") or ""
                if resp_text:
                    pr_buf += encode_ld(1, str(resp_text).encode("utf-8"))
                if thinking_text:
                    pr_buf += encode_ld(3, str(thinking_text).encode("utf-8"))
                dur_val = planner.get("thinkingDurationSeconds")
                if dur_val is not None:
                    try:
                        total_sec = float(dur_val)
                        if total_sec > 0:
                            secs = int(total_sec)
                            nanos = int(round((total_sec - secs) * 1_000_000_000))
                            if nanos >= 1_000_000_000:
                                secs += 1
                                nanos -= 1_000_000_000
                            dur_buf = bytearray()
                            if secs > 0:
                                dur_buf += encode_varint_field(1, secs)
                            if nanos > 0:
                                dur_buf += encode_varint_field(2, nanos)
                            if dur_buf:
                                pr_buf += encode_ld(11, bytes(dur_buf))
                    except (TypeError, ValueError):
                        pass
                if pr_buf:
                    step_buf += encode_ld(20, bytes(pr_buf))

            elif step_type_id == 21:  # RUN_COMMAND
                rc = step.get("runCommand") if isinstance(step.get("runCommand"), dict) else {}
                rc_buf = bytearray()
                if rc.get("cwd"):
                    rc_buf += encode_ld(2, str(rc["cwd"]).encode("utf-8"))
                if rc.get("outputPreview"):
                    rc_buf += encode_ld(4, str(rc["outputPreview"]).encode("utf-8"))
                if rc.get("exitCode") is not None:
                    try:
                        rc_buf += encode_varint_field(6, int(rc["exitCode"]) & 0xFFFFFFFF)
                    except (TypeError, ValueError):
                        pass
                if rc.get("commandId"):
                    rc_buf += encode_ld(13, str(rc["commandId"]).encode("utf-8"))
                if rc.get("commandLine"):
                    rc_buf += encode_ld(23, str(rc["commandLine"]).encode("utf-8"))
                if rc.get("proposedCommandLine"):
                    rc_buf += encode_ld(25, str(rc["proposedCommandLine"]).encode("utf-8"))
                if rc_buf:
                    step_buf += encode_ld(28, bytes(rc_buf))

            elif step_type_id == 81:  # TASK_BOUNDARY
                tb = step.get("taskBoundary") if isinstance(step.get("taskBoundary"), dict) else {}
                tb_buf = bytearray()
                if tb.get("taskName"):
                    tb_buf += encode_ld(1, str(tb["taskName"]).encode("utf-8"))
                if tb.get("taskStatus"):
                    tb_buf += encode_ld(2, str(tb["taskStatus"]).encode("utf-8"))
                if tb.get("taskSummary"):
                    tb_buf += encode_ld(3, str(tb["taskSummary"]).encode("utf-8"))
                if tb_buf:
                    step_buf += encode_ld(93, bytes(tb_buf))

            elif step_type_id == 82:  # NOTIFY_USER
                nu = step.get("notifyUser") if isinstance(step.get("notifyUser"), dict) else {}
                nu_buf = bytearray()
                for uri in nu.get("pathsToReview") or nu.get("reviewUris") or []:
                    if isinstance(uri, str) and uri:
                        nu_buf += encode_ld(1, uri.encode("utf-8"))
                msg = (
                    nu.get("notificationContent")
                    or nu.get("message")
                    or nu.get("content")
                    or step.get("notificationContent")
                    or step.get("message")
                    or ""
                )
                if msg:
                    nu_buf += encode_ld(2, str(msg).encode("utf-8"))
                if nu_buf:
                    step_buf += encode_ld(94, bytes(nu_buf))

            req_int = step.get("requestedInteraction")
            if isinstance(req_int, dict) and isinstance(req_int.get("runCommand"), dict):
                rc_int = req_int["runCommand"]
                proposed_cmd = rc_int.get("proposedCommandLine") or rc_int.get("commandLine") or ""
                cwd_val = rc_int.get("cwd") or "/workspace"
                spec_buf = encode_ld(1, str(cwd_val).encode("utf-8"))
                if proposed_cmd:
                    spec_buf += encode_ld(2, str(proposed_cmd).encode("utf-8"))
                step_buf += encode_ld(56, encode_ld(3, spec_buf))

            out += encode_ld(1, bytes(step_buf))
        return bytes(out)



def discover_desktop_oauth_token() -> str:
    """Extracts the active OAuth access token (`ya29.*`) from Antigravity Desktop's `state.vscdb` (read-only)."""
    env_key = os.environ.get("ANTIGRAVITY_API_KEY", "").strip()
    if env_key:
        return env_key
    if sys.platform != "darwin":
        return ""
    db_path = Path.home() / "Library/Application Support/Antigravity/User/globalStorage/state.vscdb"
    if not db_path.exists():
        return ""
    try:
        import base64
        import sqlite3

        uri = f"file:{urllib.parse.quote(str(db_path))}?mode=ro"
        conn = sqlite3.connect(uri, uri=True, timeout=1.5)
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT value FROM ItemTable WHERE key IN ("
                "'antigravityUnifiedStateSync.oauthToken', "
                "'jetskiStateSync.agentManagerInitState'"
                ")"
            )
            rows = cur.fetchall()
        finally:
            conn.close()

        for (val,) in rows:
            if not val:
                continue
            text = val if isinstance(val, str) else val.decode("utf-8", errors="ignore")
            m = re.search(r"(ya29\.[A-Za-z0-9._\-]+)", text)
            if m:
                return m.group(1)
            try:
                decoded = base64.b64decode(text).decode("utf-8", errors="ignore")
                m2 = re.search(r"(ya29\.[A-Za-z0-9._\-]+)", decoded)
                if m2:
                    return m2.group(1)
            except Exception:
                continue
    except Exception:
        return ""
    return ""


def query_upstream_default_model(upstream_url: str, upstream_csrf: str, api_key: str) -> tuple[str, set[str]]:
    """Queries `GetCascadeModelConfigData` on real `language_server` to resolve valid model enum IDs."""
    if not upstream_url:
        return "", set()
    ctx = make_unverified_ssl_context()
    meta = {"ideName": "antigravity", "extensionName": "antigravity", "locale": "en"}
    if api_key:
        meta["apiKey"] = api_key
    req = urllib.request.Request(
        f"{upstream_url}{SERVICE_PREFIX}GetCascadeModelConfigData",
        data=json.dumps({"metadata": meta}).encode("utf-8"),
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
            "x-codeium-csrf-token": upstream_csrf,
        },
    )
    try:
        with urlopen_direct(
            req,
            timeout=1.5,
            ssl_ctx=ctx if upstream_url.startswith("https://") else None,
        ) as resp:
            obj = json.loads(resp.read().decode("utf-8") or "{}")
            valid_models = set()
            for cfg in obj.get("clientModelConfigs") or []:
                m = (cfg.get("modelOrAlias") or {}).get("model")
                if m:
                    valid_models.add(m)
            default_model = (
                ((obj.get("defaultOverrideModelConfig") or {}).get("modelOrAlias") or {}).get("model")
                or (next(iter(valid_models)) if valid_models else "")
            )
            return default_model, valid_models
    except Exception:
        return "", set()


def read_desktop_annotation_pbtxt(cascade_id: str) -> dict:
    """Reads Antigravity Desktop per-session annotations (`~/.gemini/antigravity/annotations/<id>.pbtxt`) if present."""
    if not cascade_id or "/" in cascade_id or ".." in cascade_id:
        return {}
    candidates = [
        Path.home() / ".gemini/antigravity/annotations" / f"{cascade_id}.pbtxt",
        Path.home() / ".gemini/antigravity-cli/annotations" / f"{cascade_id}.pbtxt",
        Path.home() / ".codeium/windsurf/annotations" / f"{cascade_id}.pbtxt",
    ]
    for p in candidates:
        try:
            if not p.is_file():
                continue
            raw = p.read_text(encoding="utf-8", errors="ignore")
            out = {}
            title_m = re.search(r'(?:^|\n)\s*title\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"', raw)
            if title_m:
                out["title"] = bytes(title_m.group(1), "utf-8").decode("unicode_escape", errors="ignore")
            view_block = re.search(r"last_user_view_time\s*\{([^}]*)\}", raw, re.DOTALL)
            if view_block:
                sec_m = re.search(r"seconds\s*:\s*(\d+)", view_block.group(1))
                nano_m = re.search(r"nanos\s*:\s*(\d+)", view_block.group(1))
                if sec_m:
                    secs = int(sec_m.group(1))
                    nanos = int(nano_m.group(1)) if nano_m else 0
                    dt = datetime.fromtimestamp(secs + nanos / 1_000_000_000.0, tz=timezone.utc)
                    out["lastUserViewTime"] = dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
            if re.search(r"(?:^|\n)\s*(?:pinned|is_pinned)\s*:\s*true\b", raw):
                out["pinned"] = True
            if re.search(r"(?:^|\n)\s*(?:archived|is_archived)\s*:\s*true\b", raw):
                out["archived"] = True
            if out:
                return out
        except Exception:
            continue
    return {}


class UpstreamFederationManager:
    """Manages multi-backend (`agy --hub` + `language_server`) discovery, Jetbox summary streaming, and project resolution."""

    def __init__(
        self,
        state: CompanionState,
        ssl_ctx: ssl.SSLContext,
        explicit_url: str = None,
        explicit_csrf: str = None,
        extra_backends: list[dict] = None,
        auto_discover: bool = True,
    ):
        self.state = state
        self.ssl_ctx = ssl_ctx
        self.explicit_url = explicit_url
        self.explicit_csrf = explicit_csrf
        self.auto_discover = auto_discover
        self.lock = threading.Lock()
        self.backends: list[dict] = []
        self.last_scan_ts = 0.0
        self.jetbox_threads: dict[str, threading.Thread] = {}
        self.project_threads: dict[str, threading.Thread] = {}

        if explicit_url:
            self.backends.append(
                {
                    "pid": 0,
                    "upstream_url": explicit_url.rstrip("/"),
                    "upstream_csrf": explicit_csrf or "",
                    "is_hub": True,
                }
            )
        if extra_backends:
            for b in extra_backends:
                if isinstance(b, dict) and b.get("upstream_url"):
                    self.backends.append(
                        {
                            "pid": int(b.get("pid", 0)),
                            "upstream_url": b["upstream_url"].rstrip("/"),
                            "upstream_csrf": b.get("upstream_csrf", ""),
                            "is_hub": bool(b.get("is_hub", False)),
                        }
                    )
        self.refresh_backends(force=True)

    def get_backends(self) -> list[dict]:
        self.refresh_backends(force=False)
        with self.lock:
            return list(self.backends)

    def get_primary_backend(self) -> dict | None:
        backends = self.get_backends()
        return backends[0] if backends else None

    def refresh_backends(self, force: bool = False):
        now = time.monotonic()
        with self.lock:
            if not force and (now - self.last_scan_ts) < 2.5 and self.backends:
                return
            self.last_scan_ts = now

        if self.auto_discover and not self.explicit_url:
            discovered = discover_all_local_language_servers()
            with self.lock:
                self.backends = discovered

        with self.lock:
            current_backends = list(self.backends)
            if current_backends:
                self.state.is_live_proxy = True

        for b in current_backends:
            url = b["upstream_url"]
            if url not in self.jetbox_threads or not self.jetbox_threads[url].is_alive():
                t = threading.Thread(
                    target=self._run_jetbox_summary_subscriber,
                    args=(b,),
                    daemon=True,
                )
                self.jetbox_threads[url] = t
                t.start()
            if url not in self.project_threads or not self.project_threads[url].is_alive():
                pt = threading.Thread(
                    target=self._run_project_updates_subscriber,
                    args=(b,),
                    daemon=True,
                )
                self.project_threads[url] = pt
                pt.start()

    def call_backend_json(self, backend: dict, method: str, body: dict, timeout: float = 4.0) -> dict | None:
        target = f"{backend['upstream_url']}{SERVICE_PREFIX}{method}"
        is_https = target.startswith("https://")
        req = urllib.request.Request(
            target,
            data=json.dumps(body).encode("utf-8"),
            method="POST",
            headers={
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1",
                "x-codeium-csrf-token": backend.get("upstream_csrf") or "",
            },
        )
        try:
            with urlopen_direct(req, timeout=timeout, ssl_ctx=self.ssl_ctx if is_https else None) as resp:
                raw = resp.read()
                return json.loads(raw.decode("utf-8")) if raw else {}
        except Exception:
            return None

    def is_backend_alive(self, backend: dict, timeout: float = 1.5) -> bool:
        """Returns True if the upstream backend's TCP/HTTP server is reachable (even if an optional method returns 404)."""
        target = f"{backend['upstream_url']}{SERVICE_PREFIX}GetAllCascadeTrajectories"
        is_https = target.startswith("https://")
        req = urllib.request.Request(
            target,
            data=b"{}",
            method="POST",
            headers={
                "Content-Type": "application/json",
                "Connect-Protocol-Version": "1",
                "x-codeium-csrf-token": backend.get("upstream_csrf") or "",
            },
        )
        try:
            with urlopen_direct(req, timeout=timeout, ssl_ctx=self.ssl_ctx if is_https else None) as resp:
                return 200 <= resp.status < 500
        except urllib.error.HTTPError as http_err:
            return http_err.code < 500
        except Exception:
            return False

    def resolve_project_by_id(self, backend: dict, project_id: str) -> dict | None:
        if not project_id or project_id == "outside-of-project":
            return None
        with self.state.lock:
            if project_id in self.state.projects_by_id:
                return self.state.projects_by_id[project_id]

        disk_projects = read_disk_project_configs()
        if project_id in disk_projects:
            with self.state.lock:
                self.state.projects_by_id.update(disk_projects)
            return disk_projects[project_id]

        res = self.call_backend_json(backend, "ReadProject", {"id": project_id}, timeout=2.0)
        if isinstance(res, dict) and isinstance(res.get("project"), dict):
            parsed = parse_local_project_entry(res["project"])
            if parsed:
                with self.state.lock:
                    self.state.projects_by_id[project_id] = parsed
                return parsed
        return None

    def _run_jetbox_summary_subscriber(self, backend: dict):
        """Maintains a Connect-RPC stream to `JetboxSubscribeToSummaries` on `backend` to capture all-time & live updates."""
        url = f"{backend['upstream_url']}{SERVICE_PREFIX}JetboxSubscribeToSummaries"
        is_https = url.startswith("https://")
        envelope = encode_connect_frame(b"{}", flags=0x00)
        req = urllib.request.Request(
            url,
            data=envelope,
            method="POST",
            headers={
                "Content-Type": "application/connect+json",
                "Connect-Protocol-Version": "1",
                "x-codeium-csrf-token": backend.get("upstream_csrf") or "",
            },
        )
        try:
            with urlopen_direct(req, timeout=60.0, ssl_ctx=self.ssl_ctx if is_https else None) as resp:
                if resp.status >= 400:
                    return
                buf = bytearray()
                while True:
                    chunk = resp.read(1)
                    if not chunk:
                        break
                    buf.extend(chunk)
                    while len(buf) >= 5:
                        flag = buf[0]
                        msg_len = struct.unpack(">I", buf[1:5])[0]
                        if msg_len > len(buf) - 5:
                            needed = (5 + msg_len) - len(buf)
                            more = resp.read(needed)
                            if not more:
                                return
                            buf.extend(more)
                        if len(buf) < 5 + msg_len:
                            break
                        payload = bytes(buf[5 : 5 + msg_len])
                        del buf[: 5 + msg_len]
                        if flag != 0x00:
                            continue
                        try:
                            frame = json.loads(payload.decode("utf-8"))
                        except Exception:
                            continue
                        self._apply_jetbox_frame(backend, frame)
        except Exception:
            return

    def _apply_jetbox_frame(self, backend: dict, frame: dict):
        if not isinstance(frame, dict):
            return
        updates = frame.get("updates")
        deletes = frame.get("deletes")
        if isinstance(updates, dict):
            for cid, summary_obj in updates.items():
                if not isinstance(summary_obj, dict):
                    continue
                if is_synthetic_probe_summary(summary_obj):
                    continue
                proj_id = (summary_obj.get("trajectoryMetadata") or {}).get("projectId")
                if proj_id:
                    self.resolve_project_by_id(backend, proj_id)
                with self.state.lock:
                    self.state.jetbox_summaries[cid] = summary_obj
                    self.state.cascade_to_backend[cid] = backend
        elif isinstance(frame.get("cascadeId"), str):
            cid = frame["cascadeId"]
            if not is_synthetic_probe_summary(frame):
                with self.state.lock:
                    existing = dict(self.state.jetbox_summaries.get(cid) or {})
                    existing.update(frame)
                    self.state.jetbox_summaries[cid] = existing
                    self.state.cascade_to_backend[cid] = backend
        if isinstance(deletes, list):
            with self.state.lock:
                for cid in deletes:
                    self.state.jetbox_summaries.pop(cid, None)

    def _run_project_updates_subscriber(self, backend: dict):
        """Subscribes to `ProjectUpdatesStream` on `backend` and resolves each project via `ReadProject`."""
        url = f"{backend['upstream_url']}{SERVICE_PREFIX}ProjectUpdatesStream"
        is_https = url.startswith("https://")
        envelope = encode_connect_frame(b"{}", flags=0x00)
        req = urllib.request.Request(
            url,
            data=envelope,
            method="POST",
            headers={
                "Content-Type": "application/connect+json",
                "Connect-Protocol-Version": "1",
                "x-codeium-csrf-token": backend.get("upstream_csrf") or "",
            },
        )
        try:
            with urlopen_direct(req, timeout=60.0, ssl_ctx=self.ssl_ctx if is_https else None) as resp:
                if resp.status >= 400:
                    return
                buf = bytearray()
                while True:
                    chunk = resp.read(1)
                    if not chunk:
                        break
                    buf.extend(chunk)
                    while len(buf) >= 5:
                        flag = buf[0]
                        msg_len = struct.unpack(">I", buf[1:5])[0]
                        if msg_len > len(buf) - 5:
                            needed = (5 + msg_len) - len(buf)
                            more = resp.read(needed)
                            if not more:
                                return
                            buf.extend(more)
                        if len(buf) < 5 + msg_len:
                            break
                        payload = bytes(buf[5 : 5 + msg_len])
                        del buf[: 5 + msg_len]
                        if flag != 0x00:
                            continue
                        try:
                            frame = json.loads(payload.decode("utf-8"))
                        except Exception:
                            continue
                        proj_ids = []
                        if isinstance(frame.get("projectList"), dict):
                            proj_ids.extend(frame["projectList"].get("projectIds") or [])
                        if isinstance(frame.get("projectUpdatedId"), str):
                            proj_ids.append(frame["projectUpdatedId"])
                        for pid in proj_ids:
                            if isinstance(pid, str) and pid:
                                self.resolve_project_by_id(backend, pid)
        except Exception:
            return


def enrich_summary_entry(
    cid: str,
    summary_obj: dict,
    projects_by_id: dict[str, dict],
    backend: dict | None = None,
    remote_ws_index: dict[str, str] | None = None,
) -> dict:
    """Enriches a trajectory summary with `.pbtxt` annotations, Cloud VM / Remote URI classification, and `ReadProject` metadata."""
    enriched = dict(summary_obj)
    pbtxt_ann = read_desktop_annotation_pbtxt(cid)
    if pbtxt_ann:
        ann = dict(enriched.get("annotations") or {})
        for k, v in pbtxt_ann.items():
            ann.setdefault(k, v)
        enriched["annotations"] = ann

    traj_meta = enriched.get("trajectoryMetadata") if isinstance(enriched.get("trajectoryMetadata"), dict) else {}
    proj_id = traj_meta.get("projectId")
    proj = projects_by_id.get(proj_id) if proj_id else None

    workspaces = enriched.get("workspaces")
    primary_ws = select_primary_workspace_entry(workspaces)
    raw_ws_uri = ""
    branch = "main"
    if isinstance(primary_ws, dict):
        raw_ws_uri = str(primary_ws.get("workspaceFolderAbsoluteUri") or primary_ws.get("workspaceUri") or "").strip()
        branch = str(primary_ws.get("gitBranch") or primary_ws.get("branchName") or "main").strip() or "main"

    if not raw_ws_uri and proj:
        raw_ws_uri = str(proj.get("workspaceUri") or "").strip()
        branch = str(proj.get("activeBranch") or branch or "main")

    source_str = " ".join(
        str(x)
        for x in (
            enriched.get("source"),
            enriched.get("runtime"),
            traj_meta.get("runtime"),
            traj_meta.get("environment"),
            traj_meta.get("executionEnvironment"),
            traj_meta.get("source"),
        )
        if x
    )
    ws_is_cloud, norm_uri, slug_hint = classify_workspace_uri(
        raw_ws_uri,
        cascade_id=cid,
        source=source_str,
        backend=backend,
        remote_ws_index=remote_ws_index,
    )
    explicit_cloud = (
        bool(enriched.get("isCloud"))
        or bool(traj_meta.get("isCloud"))
        or bool(proj and proj.get("isCloud"))
        or ws_is_cloud
    )

    if proj:
        proj_name = str(proj.get("displayName") or proj.get("name") or "").strip()
        if proj_name:
            enriched.setdefault("projectSlug", proj_name)
        if proj.get("isCloud") and proj.get("workspaceUri"):
            proj_uri = str(proj["workspaceUri"])
            if not norm_uri or not norm_uri.startswith("cloud://") or ("/" in proj_uri[len("cloud://") :] and "/" not in norm_uri.replace("cloud://", "")):
                norm_uri = proj_uri

    if explicit_cloud:
        enriched["isCloud"] = True
        enriched["runtime"] = "cloud"
        final_uri = norm_uri or (proj.get("workspaceUri") if proj else "") or raw_ws_uri
        if final_uri and not final_uri.lower().startswith(CLOUD_URI_PREFIXES):
            fallback_slug = slug_hint or (proj.get("displayName") if proj else "") or "cloud"
            final_uri = f"cloud://{fallback_slug}"
        if final_uri:
            enriched["workspaceUri"] = final_uri
            primary_entry = dict(primary_ws) if isinstance(primary_ws, dict) else {}
            primary_entry["workspaceFolderAbsoluteUri"] = final_uri
            primary_entry["workspaceUri"] = final_uri
            primary_entry.setdefault("gitBranch", branch)
            other_entries = [
                w
                for w in (workspaces if isinstance(workspaces, list) else [])
                if isinstance(w, dict) and w is not primary_ws
            ]
            enriched["workspaces"] = [primary_entry] + other_entries
        if slug_hint and slug_hint != "antigravity":
            enriched.setdefault("projectSlug", slug_hint)
    elif proj and not primary_ws and proj.get("workspaceUri"):
        enriched["workspaces"] = [
            {
                "workspaceFolderAbsoluteUri": proj["workspaceUri"],
                "workspaceUri": proj["workspaceUri"],
                "gitBranch": proj.get("activeBranch", "main"),
            }
        ]
    elif isinstance(primary_ws, dict) and isinstance(workspaces, list) and len(workspaces) > 1 and workspaces[0] is not primary_ws:
        other_entries = [w for w in workspaces if isinstance(w, dict) and w is not primary_ws]
        enriched["workspaces"] = [primary_ws] + other_entries

    return enriched


def create_bridge_server(
    bind_host: str,
    bind_port: int,
    bridge_csrf: str,
    upstream_url: str = None,
    upstream_csrf: str = None,
    workspace_root: str = None,
    extra_backends: list[dict] = None,
    auto_discover: bool = None,
):
    has_upstream = bool(upstream_url) or bool(extra_backends)
    state = CompanionState(workspace_root or os.getcwd(), is_live_proxy=has_upstream)
    ssl_ctx = make_unverified_ssl_context()
    should_auto_discover = (auto_discover is True) if auto_discover is not None else False
    federation = UpstreamFederationManager(
        state=state,
        ssl_ctx=ssl_ctx,
        explicit_url=upstream_url,
        explicit_csrf=upstream_csrf or bridge_csrf,
        extra_backends=extra_backends,
        auto_discover=should_auto_discover,
    )
    primary = federation.get_primary_backend()
    desktop_api_key = discover_desktop_oauth_token() if primary else ""
    upstream_default_model, upstream_valid_models = (
        query_upstream_default_model(
            primary["upstream_url"],
            primary.get("upstream_csrf") or bridge_csrf,
            desktop_api_key,
        )
        if primary
        else ("", set())
    )

    class BridgeHandler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            sys.stderr.write(f"[Bridge] {self.address_string()} - {fmt % args}\n")

        def _send_cors(self):
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header(
                "Access-Control-Allow-Headers",
                "Content-Type, Connect-Protocol-Version, x-codeium-csrf-token, Accept, Cookie",
            )
            self.send_header(
                "Access-Control-Expose-Headers",
                "X-Antigravity-Bridge-Capabilities, X-Antigravity-Desktop-Version",
            )
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header(
                "X-Antigravity-Bridge-Capabilities",
                ",".join(BRIDGE_CAPABILITY_METHODS),
            )
            detected_ver = next(
                (
                    b.get("desktop_version")
                    for b in federation.get_backends()
                    if b.get("desktop_version")
                ),
                "",
            )
            if detected_ver:
                self.send_header("X-Antigravity-Desktop-Version", detected_ver)

        def do_OPTIONS(self):
            self.send_response(204)
            self._send_cors()
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_GET(self):
            parsed_path = urllib.parse.urlparse(self.path).path
            if parsed_path == "/health":
                backends = federation.get_backends()
                if state.is_live_proxy:
                    live_upstreams = [
                        b
                        for b in backends
                        if federation.call_backend_json(b, "GetAllCascadeTrajectories", {}, timeout=1.5) is not None
                        or federation.call_backend_json(b, "GetUnleashData", {}, timeout=1.2) is not None
                    ]
                    if not live_upstreams:
                        federation.refresh_backends(force=True)
                        backends = federation.get_backends()
                        live_upstreams = [
                            b
                            for b in backends
                            if federation.call_backend_json(b, "GetAllCascadeTrajectories", {}, timeout=1.5) is not None
                            or federation.call_backend_json(b, "GetUnleashData", {}, timeout=1.2) is not None
                        ]
                    if not live_upstreams:
                        self._write_json(
                            503,
                            {
                                "ok": False,
                                "hostname": socket.gethostname(),
                                "mode": "desktop_offline",
                                "message": "Antigravity Desktop is offline",
                                "upstream": None,
                                "upstreams": [],
                                "desktopAuthDetected": bool(desktop_api_key),
                            },
                        )
                        return
                    backends = live_upstreams
                self._write_json(
                    200,
                    {
                        "ok": True,
                        "hostname": socket.gethostname(),
                        "mode": "upstream_proxy" if backends else "standalone_sandbox",
                        "upstream": backends[0]["upstream_url"] if backends else None,
                        "upstreams": [b["upstream_url"] for b in backends],
                        "desktopAuthDetected": bool(desktop_api_key),
                    },
                )
                return

            if parsed_path in ("/", "/pair"):
                host_hdr = self.headers.get("Host") or f"{detect_lan_ip()}:{self.server.server_port}"
                endpoint = f"http://{host_hdr}"
                hostname = socket.gethostname()
                pair_uri = (
                    f"antigravity://pair?"
                    f"url={urllib.parse.quote(endpoint, safe='')}"
                    f"&csrf={urllib.parse.quote(bridge_csrf, safe='')}"
                    f"&name={urllib.parse.quote(hostname, safe='')}"
                )
                backends = federation.get_backends()
                mode_badge = f"LIVE DESKTOP PROXY ({len(backends)} BACKEND{'S' if len(backends) != 1 else ''})" if backends else "COMPANION SANDBOX"
                page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Pair Antigravity iOS · {html.escape(hostname)}</title>
<style>
  body {{
    margin: 0; padding: 28px 18px; background: #090A0D; color: #F5F7FA;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
  }}
  .card {{
    max-width: 440px; margin: 0 auto; background: #14161C; border: 1px solid rgba(255,255,255,0.09);
    border-radius: 22px; padding: 22px 18px;
  }}
  .badge {{
    display: inline-flex; align-items: center; gap: 7px; font-size: 12px; font-weight: 600;
    color: #57C88A; background: rgba(87,200,138,0.12); padding: 5px 11px; border-radius: 999px;
  }}
  .dot {{ width: 8px; height: 8px; border-radius: 50%; background: #57C88A; }}
  h1 {{ font-size: 24px; margin: 14px 0 6px; letter-spacing: -0.4px; }}
  p {{ font-size: 14px; color: #8E93A2; line-height: 1.45; margin: 0 0 18px; }}
  .cta {{
    display: block; text-align: center; text-decoration: none; background: #8EB4FF; color: #0A0E17;
    font-size: 16px; font-weight: 700; padding: 15px 18px; border-radius: 16px; margin-bottom: 18px;
  }}
  .field {{
    background: #1B1D23; border-radius: 12px; padding: 10px 12px; margin-top: 9px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12.5px; word-break: break-all;
  }}
  .label {{ font-size: 10.5px; color: #7C8190; text-transform: uppercase; letter-spacing: 0.6px; margin-bottom: 4px; }}
</style>
</head>
<body>
  <div class="card">
    <div class="badge"><span class="dot"></span>{html.escape(mode_badge)}</div>
    <h1>Pair with {html.escape(hostname)}</h1>
    <p>Install <strong>Antigravity</strong> on this iPhone via Xcode, then tap the button below to connect over Wi-Fi and sync your Mac workspaces.</p>
    <a class="cta" href="{html.escape(pair_uri)}">Open &amp; Pair in Antigravity iOS</a>
    <div class="field"><div class="label">Host Endpoint</div>{html.escape(endpoint)}</div>
    <div class="field"><div class="label">x-codeium-csrf-token</div>{html.escape(bridge_csrf)}</div>
  </div>
</body>
</html>"""
                body_bytes = page.encode("utf-8")
                self.send_response(200)
                self._send_cors()
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body_bytes)))
                self.end_headers()
                self.wfile.write(body_bytes)
                return

            self._write_json(404, {"error": "Not found"})

        def do_POST(self):
            # 1. Enforce `x-codeium-csrf-token` authentication
            client_csrf = self.headers.get("x-codeium-csrf-token", "")
            if bridge_csrf and client_csrf != bridge_csrf:
                self._write_json(
                    401,
                    {
                        "code": "unauthenticated",
                        "message": "Missing or invalid x-codeium-csrf-token",
                    },
                )
                return

            length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(length) if length > 0 else b""
            parsed_path = urllib.parse.urlparse(self.path).path
            if not parsed_path.startswith(SERVICE_PREFIX):
                self._write_json(404, {"error": f"Unknown service path {parsed_path}"})
                return

            method = parsed_path[len(SERVICE_PREFIX) :]
            content_type = self.headers.get("Content-Type", "application/json")

            # 2. Companion-handled local Mac operations
            if method == "OpenWorkspaceInFinder":
                req_obj = self._parse_json(raw_body)
                uri = req_obj.get("workspaceUri", "").replace("file://", "")
                if sys.platform == "darwin" and uri:
                    subprocess.Popen(["open", uri])
                self._write_json(200, {"ok": True})
                return

            if method == "ReadArtifactFile":
                req_obj = self._parse_json(raw_body)
                target_uri = req_obj.get("uri") or req_obj.get("path") or ""
                with state.lock:
                    ws_roots = [state.workspace_root] + [
                        w.get("workspaceUri") or "" for w in state.workspaces if isinstance(w, dict)
                    ]
                status_code, payload_obj = read_trusted_artifact_file(
                    target_uri,
                    workspace_roots=ws_roots,
                )
                self._write_json(status_code, payload_obj)
                return

            if method == "CreateProjectWorkspace":
                req_obj = self._parse_json(raw_body)
                name = req_obj.get("name") or "new-project"
                runtime = req_obj.get("runtime") or "Local"
                repo = req_obj.get("repository") or name
                ws_uri = f"cloud://{repo}" if runtime == "Cloud" else f"file://{Path(state.workspace_root).parent / name}"
                with state.lock:
                    state.workspaces.append(
                        {
                            "workspaceUri": ws_uri,
                            "workspaceFolderAbsoluteUri": ws_uri,
                            "displayName": name,
                            "activeBranch": "main",
                            "indexedFiles": [],
                        }
                    )
                self._write_json(200, {"ok": True, "workspaceUri": ws_uri, "name": name})
                return

            if method == "GetTurnDiff":
                req_obj = self._parse_json(raw_body)
                compare_mode = str(req_obj.get("compareMode") or "Per Turn")
                files = []
                try:
                    status_out = subprocess.check_output(
                        ["git", "status", "--porcelain"],
                        cwd=state.workspace_root,
                        text=True,
                        stderr=subprocess.DEVNULL,
                    )
                    for row in status_out.splitlines():
                        if len(row) < 4:
                            continue
                        x_flag = row[0]
                        y_flag = row[1]
                        file_path = row[3:].strip()
                        if not file_path:
                            continue
                        is_staged = x_flag not in (" ", "?")
                        letter = "U" if (x_flag == "?" and y_flag == "?") else (x_flag if x_flag not in (" ", "?") else y_flag)
                        diff_args = ["git", "diff", "-U3"]
                        if is_staged and y_flag == " ":
                            diff_args.append("--cached")
                        diff_args.extend(["--", file_path])
                        try:
                            patch_text = subprocess.check_output(
                                diff_args,
                                cwd=state.workspace_root,
                                text=True,
                                stderr=subprocess.DEVNULL,
                            )
                        except Exception:
                            patch_text = ""
                        add_c = sum(1 for l in patch_text.splitlines() if l.startswith("+") and not l.startswith("+++"))
                        del_c = sum(1 for l in patch_text.splitlines() if l.startswith("-") and not l.startswith("---"))
                        files.append(
                            {
                                "turnNumber": req_obj.get("turnNumber") or 1,
                                "filePath": file_path,
                                "additions": add_c,
                                "deletions": del_c,
                                "statusLetter": letter if letter in ("M", "A", "U", "D", "R") else "M",
                                "isStaged": is_staged,
                                "compareScope": compare_mode,
                                "patch": patch_text,
                            }
                        )
                except Exception:
                    pass
                self._write_json(200, {"files": files, "compareMode": compare_mode})
                return

            if method in ("GitStageFile", "GitUnstageFile", "GitDiscardFile"):
                req_obj = self._parse_json(raw_body)
                rel_path = str(req_obj.get("filePath") or "").strip()
                if not rel_path or rel_path.startswith("/") or ".." in Path(rel_path).parts:
                    self._write_json(400, {"ok": False, "error": "Invalid workspace-relative filePath"})
                    return
                cmd_map = {
                    "GitStageFile": ["git", "add", "--", rel_path],
                    "GitUnstageFile": ["git", "reset", "HEAD", "--", rel_path],
                    "GitDiscardFile": ["git", "checkout", "--", rel_path],
                }
                try:
                    subprocess.check_call(cmd_map[method], cwd=state.workspace_root, stderr=subprocess.DEVNULL)
                    self._write_json(200, {"ok": True, "filePath": rel_path})
                except Exception as exc:
                    self._write_json(500, {"ok": False, "error": str(exc)})
                return

            if method == "GitCommit":
                req_obj = self._parse_json(raw_body)
                msg = str(req_obj.get("message") or "").strip()
                if not msg:
                    self._write_json(400, {"ok": False, "error": "Commit message is required"})
                    return
                try:
                    if req_obj.get("includeUnstaged"):
                        subprocess.check_call(["git", "add", "-A"], cwd=state.workspace_root, stderr=subprocess.DEVNULL)
                    args = ["git", "commit", "-m", msg]
                    if req_obj.get("amend"):
                        args.append("--amend")
                    subprocess.check_call(args, cwd=state.workspace_root, stderr=subprocess.DEVNULL)
                    sha = subprocess.check_output(
                        ["git", "rev-parse", "--short", "HEAD"],
                        cwd=state.workspace_root,
                        text=True,
                    ).strip()
                    branch = subprocess.check_output(
                        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                        cwd=state.workspace_root,
                        text=True,
                    ).strip()
                    self._write_json(200, {"ok": True, "commitSha": sha, "commitMessage": msg, "branchName": branch, "pushed": False})
                except Exception as exc:
                    self._write_json(500, {"ok": False, "error": str(exc)})
                return

            if method == "GitPush":
                req_obj = self._parse_json(raw_body)
                branch = str(req_obj.get("branchName") or "").strip()
                try:
                    args = ["git", "push", "origin", branch] if branch else ["git", "push"]
                    subprocess.check_call(args, cwd=state.workspace_root, stderr=subprocess.DEVNULL)
                    self._write_json(200, {"ok": True, "pushed": True, "branchName": branch})
                except Exception as exc:
                    self._write_json(500, {"ok": False, "error": str(exc)})
                return

            if method == "GetCustomizationsCatalog":
                skills_dir = Path(state.workspace_root) / ".agents" / "skills"
                skills = []
                if skills_dir.is_dir():
                    for p in sorted(skills_dir.glob("*/SKILL.md")):
                        skills.append({"name": p.parent.name, "description": "Workspace project skill", "scope": "Workspace", "isEnabled": True})
                self._write_json(
                    200,
                    {
                        "skills": skills,
                        "rules": [{"name": "AGENTS.md", "scope": "Workspace", "preview": "Workspace engineering rules", "isActive": True}],
                        "customAgents": ["Default"],
                        "mcpServers": [],
                        "plugins": [],
                        "hooks": [],
                    },
                )
                return

            if method == "ListAutomations":
                with state.lock:
                    self._write_json(200, {"automations": list(state.automations)})
                return

            if method == "CreateAutomation":
                req_obj = self._parse_json(raw_body)
                proj_slug = req_obj.get("projectSlug", "workspace")
                item = {
                    "id": f"auto-{uuid.uuid4().hex[:8]}",
                    "title": req_obj.get("prompt", "Scheduled Automation"),
                    "projectSlug": proj_slug,
                    "scheduleSummary": f"{proj_slug} · Daily at 09:00 · Flash",
                    "section": "SCHEDULED",
                    "nextRunText": "Tomorrow, 09:00",
                    "lastRunText": "Created just now",
                }
                with state.lock:
                    state.automations.insert(0, item)
                self._write_json(200, item)
                return

            if method == "TriggerAutomationNow":
                req_obj = self._parse_json(raw_body)
                aid = req_obj.get("automationId", "")
                with state.lock:
                    for a in state.automations:
                        if a["id"] == aid:
                            a["lastRunText"] = "Running now..."
                            a["isRunningNow"] = True
                self._write_json(200, {"ok": True, "automationId": aid})
                return

            if method == "SetAutomationPaused":
                req_obj = self._parse_json(raw_body)
                aid = req_obj.get("automationId", "")
                is_paused = bool(req_obj.get("isPaused", False))
                with state.lock:
                    for a in state.automations:
                        if a["id"] == aid:
                            a["section"] = "PAUSED" if is_paused else "SCHEDULED"
                            a["lastRunText"] = "Paused" if is_paused else "Resumed · just now"
                self._write_json(200, {"ok": True, "automationId": aid})
                return

            backends = federation.get_backends()
            if not backends and state.is_live_proxy:
                federation.refresh_backends(force=True)
                backends = federation.get_backends()
                if not backends:
                    self._write_json(
                        503,
                        {
                            "code": "unavailable",
                            "message": "Antigravity Desktop is offline",
                        },
                    )
                    return

            if method == "JetboxSubscribeToSummaries":
                self._handle_jetbox_subscribe_stream(backends)
                return

            # 3. Forward / Federate across real Desktop `language_server` / `agy --hub` backends when available!
            if backends:
                if method == "GetWorkspaceInfos":
                    self._handle_federated_workspaces(backends)
                    return
                if method == "GetAllCascadeTrajectories":
                    self._handle_federated_trajectories(backends)
                    return
                self._proxy_to_upstream(backends, method, raw_body, content_type)
                return

            # 4. Standalone Sandbox Mode (full live Connect-RPC state machine!)
            self._handle_standalone_rpc(method, raw_body, content_type)

        def _handle_jetbox_subscribe_stream(self, backends: list[dict]):
            """Emits a Connect 5-byte framed snapshot of current summaries (both `updates` map and `cascadeId` event)."""
            if backends:
                merged_map, reachable_count = self._collect_federated_summaries_map(backends)
                if reachable_count == 0 and state.is_live_proxy:
                    federation.refresh_backends(force=True)
                    refreshed = federation.get_backends()
                    if refreshed:
                        merged_map, reachable_count = self._collect_federated_summaries_map(refreshed)
                    if reachable_count == 0:
                        self._write_json(
                            503,
                            {
                                "code": "unavailable",
                                "message": "Antigravity Desktop is offline",
                            },
                        )
                        return
                if merged_map:
                    first_cid, first_obj = next(iter(merged_map.items()))
                    ann = first_obj.get("annotations") if isinstance(first_obj.get("annotations"), dict) else {}
                    title = ann.get("title") or first_obj.get("summary") or first_obj.get("title") or "Session"
                    frame1 = encode_connect_frame(
                        json.dumps(
                            {
                                "cascadeId": first_cid,
                                "title": title,
                                "status": first_obj.get("status", "CASCADE_RUN_STATUS_IDLE"),
                                "stepCount": first_obj.get("stepCount", 0),
                                "summary": first_obj.get("summary", title),
                                "updates": merged_map,
                            }
                        ).encode("utf-8"),
                        flags=0x00,
                    )
                else:
                    frame1 = encode_connect_frame(
                        json.dumps({"cascadeId": "cas-live-sync", "updates": {}}).encode("utf-8"),
                        flags=0x00,
                    )
                end_frame = encode_connect_frame(b"{}", flags=0x02)
                payload = frame1 + end_frame
                self.send_response(200)
                self._send_cors()
                self.send_header("Content-Type", "application/connect+json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return

            self._handle_standalone_rpc("JetboxSubscribeToSummaries", b"{}", "application/connect+json")

        def _handle_federated_workspaces(self, backends: list[dict]):
            seen_uris = set()
            normalized = []
            remote_ws_index = read_desktop_remote_workspaces()
            reachable_count = 0

            def query_workspaces_from(target_backends: list[dict]) -> int:
                alive = 0
                for b in target_backends:
                    res = federation.call_backend_json(b, "GetWorkspaceInfos", {}, timeout=3.0)
                    if isinstance(res, dict):
                        alive += 1
                    else:
                        if federation.is_backend_alive(b, timeout=1.5):
                            alive += 1
                        continue
                    raw_items = res.get("workspaceInfos") or res.get("workspaces") or []
                    for item in raw_items:
                        if not isinstance(item, dict):
                            continue
                        raw_uri = item.get("workspaceUri") or item.get("workspaceFolderAbsoluteUri") or ""
                        if not raw_uri:
                            continue
                        decoded_raw = urllib.parse.unquote(raw_uri).rstrip("/")
                        if decoded_raw.startswith("file://") and decoded_raw[len("file://") :] in GENERIC_CLOUD_CONTAINER_ROOTS:
                            continue
                        is_cloud, norm_uri, slug_hint = classify_workspace_uri(
                            raw_uri,
                            source=str(item.get("runtime") or item.get("source") or ""),
                            backend=b,
                            remote_ws_index=remote_ws_index,
                        )
                        is_cloud = is_cloud or bool(item.get("isCloud"))
                        final_uri = norm_uri or raw_uri
                        dedup_key = urllib.parse.unquote(final_uri).rstrip("/").lower()
                        if dedup_key in seen_uris:
                            continue
                        seen_uris.add(dedup_key)
                        clean_path = final_uri.replace("file://", "").replace("cloud://", "").rstrip("/")
                        default_name = slug_hint or (Path(clean_path).name or "workspace")
                        enriched = dict(item)
                        enriched["workspaceUri"] = final_uri
                        enriched["workspaceFolderAbsoluteUri"] = final_uri
                        enriched["displayName"] = item.get("displayName") or default_name
                        enriched["activeBranch"] = item.get("gitBranch") or item.get("activeBranch") or "main"
                        enriched["isCloud"] = is_cloud
                        normalized.append(enriched)
                return alive

            reachable_count = query_workspaces_from(backends)
            if reachable_count == 0:
                federation.refresh_backends(force=True)
                refreshed = federation.get_backends()
                if refreshed:
                    reachable_count = query_workspaces_from(refreshed)
                if reachable_count == 0:
                    self._write_json(
                        503,
                        {
                            "code": "unavailable",
                            "message": "Antigravity Desktop is offline",
                        },
                    )
                    return

            disk_projects = read_disk_project_configs()
            with state.lock:
                state.projects_by_id.update(disk_projects)
                known_projects = list(state.projects_by_id.values())

            for proj in known_projects:
                uri = proj.get("workspaceUri") or ""
                if not uri:
                    continue
                dedup_key = urllib.parse.unquote(uri).rstrip("/").lower()
                if dedup_key in seen_uris:
                    continue
                seen_uris.add(dedup_key)
                normalized.append(
                    {
                        "workspaceUri": uri,
                        "workspaceFolderAbsoluteUri": uri,
                        "displayName": proj.get("displayName") or proj.get("name") or "workspace",
                        "activeBranch": proj.get("activeBranch") or "main",
                        "isCloud": bool(proj.get("isCloud")),
                        "indexedFiles": [],
                    }
                )

            self._write_json(200, {"workspaces": normalized, "workspaceInfos": normalized})

        def _collect_federated_summaries_map(self, backends: list[dict]) -> tuple[dict[str, dict], int]:
            merged_summaries: dict[str, dict] = {}
            remote_ws_index = read_desktop_remote_workspaces()
            disk_projects = read_disk_project_configs()
            with state.lock:
                state.projects_by_id.update(disk_projects)
                projects_snapshot = dict(state.projects_by_id)
                jetbox_snapshot = dict(state.jetbox_summaries)

            # 1. Seed with Jetbox all-time summaries
            for cid, s_obj in jetbox_snapshot.items():
                if not isinstance(s_obj, dict) or is_synthetic_probe_summary(s_obj):
                    continue
                merged_summaries[cid] = enrich_summary_entry(
                    cid,
                    s_obj,
                    projects_snapshot,
                    remote_ws_index=remote_ws_index,
                )

            # 2. Query every discovered backend (`agy --hub` + `language_server` instances)
            reachable_count = 0
            for b in backends:
                res = federation.call_backend_json(b, "GetAllCascadeTrajectories", {}, timeout=3.5)
                if not isinstance(res, dict):
                    continue
                reachable_count += 1
                b_map = res.get("trajectorySummaries") or {}
                if isinstance(b_map, dict):
                    for cid, s_obj in b_map.items():
                        if not isinstance(s_obj, dict):
                            continue
                        with state.lock:
                            is_local_session = cid in state.trajectories and cid != "cas-live-welcome"
                        if is_synthetic_probe_summary(s_obj) and not is_local_session:
                            continue
                        proj_id = (s_obj.get("trajectoryMetadata") or {}).get("projectId")
                        if proj_id and proj_id not in projects_snapshot:
                            resolved_p = federation.resolve_project_by_id(b, proj_id)
                            if resolved_p:
                                projects_snapshot[proj_id] = resolved_p
                        enriched = enrich_summary_entry(
                            cid,
                            s_obj,
                            projects_snapshot,
                            backend=b,
                            remote_ws_index=remote_ws_index,
                        )
                        prev = merged_summaries.get(cid)
                        if prev is None:
                            merged_summaries[cid] = enriched
                        else:
                            prev_steps = int(prev.get("stepCount") or 0)
                            new_steps = int(enriched.get("stepCount") or 0)
                            new_status = str(enriched.get("status") or "").upper()
                            if (
                                new_steps >= prev_steps
                                or "RUNNING" in new_status
                                or "IN_PROGRESS" in new_status
                                or "WAITING" in new_status
                                or (enriched.get("isCloud") and not prev.get("isCloud"))
                            ):
                                merged_summaries[cid] = enriched
                        with state.lock:
                            state.cascade_to_backend[cid] = b

            # 3. Merge any optimistic iOS-created sessions not yet reported by upstream
            with state.lock:
                for cid, t in state.trajectories.items():
                    if cid == "cas-live-welcome":
                        continue
                    merged_summaries.setdefault(
                        cid,
                        enrich_summary_entry(
                            cid,
                            {
                                "summary": t["title"],
                                "stepCount": t["stepCount"],
                                "status": t["status"],
                                "workspaces": [{"workspaceFolderAbsoluteUri": t["workspaceUri"]}],
                            },
                            projects_snapshot,
                            remote_ws_index=remote_ws_index,
                        ),
                    )
            return merged_summaries, reachable_count

        def _handle_federated_trajectories(self, backends: list[dict]):
            merged_summaries, reachable_count = self._collect_federated_summaries_map(backends)
            if reachable_count == 0:
                federation.refresh_backends(force=True)
                refreshed = federation.get_backends()
                if refreshed:
                    merged_summaries, reachable_count = self._collect_federated_summaries_map(refreshed)
                if reachable_count == 0:
                    self._write_json(
                        503,
                        {
                            "code": "unavailable",
                            "message": "Antigravity Desktop is offline",
                        },
                    )
                    return
            self._write_json(200, {"trajectorySummaries": merged_summaries})

        def _build_upstream_metadata(self, existing: dict) -> dict:
            meta = {}
            meta["ideName"] = "antigravity"
            meta["extensionName"] = "antigravity"
            meta["locale"] = existing.get("locale") or "en"
            if existing.get("ideVersion"):
                meta["ideVersion"] = existing["ideVersion"]
            api_key = existing.get("apiKey") or desktop_api_key or discover_desktop_oauth_token()
            if api_key:
                meta["apiKey"] = api_key
            return meta

        def _sanitize_for_upstream(self, method: str, req_obj: dict) -> tuple[int, dict]:
            """Sanitizes companion JSON extensions into strict `exa.language_server_pb` protojson."""
            if method == "StartCascade":
                sanitized = {
                    "metadata": self._build_upstream_metadata(req_obj.get("metadata") or {}),
                    "source": req_obj.get("source") or "CORTEX_TRAJECTORY_SOURCE_CASCADE_CLIENT",
                }
                if req_obj.get("workspaceUris"):
                    sanitized["workspaceUris"] = req_obj["workspaceUris"]
                return 200, sanitized

            if method == "SendUserCascadeMessage":
                fallback_text = req_obj.get("userResponse", "")
                clean_items = []
                for entry in req_obj.get("items") or []:
                    if not isinstance(entry, dict):
                        continue
                    if "text" in entry:
                        clean_items.append({"text": entry["text"]})
                    elif isinstance(entry.get("item"), dict) and isinstance(entry["item"].get("file"), dict):
                        abs_uri = entry["item"]["file"].get("absoluteUri", "")
                        local_path = abs_uri.replace("file://", "") if abs_uri.startswith("file://") else ""
                        if abs_uri and (not local_path or os.path.exists(local_path)):
                            clean_items.append({"item": {"file": {"absoluteUri": abs_uri}}})
                if not clean_items and fallback_text:
                    clean_items.append({"text": fallback_text})

                sanitized = {
                    "cascadeId": req_obj.get("cascadeId", ""),
                    "items": clean_items,
                    "metadata": self._build_upstream_metadata(req_obj.get("metadata") or {}),
                }
                cascade_cfg = json.loads(json.dumps(req_obj.get("cascadeConfig") or {}))
                planner_cfg = cascade_cfg.get("plannerConfig")
                if isinstance(planner_cfg, dict):
                    req_model = (planner_cfg.get("requestedModel") or {}).get("model", "")
                    if upstream_valid_models and req_model not in upstream_valid_models:
                        if upstream_default_model:
                            planner_cfg["requestedModel"] = {"model": upstream_default_model}
                        else:
                            planner_cfg.pop("requestedModel", None)
                    elif not upstream_valid_models and (" " in req_model or not req_model.startswith("MODEL_")):
                        if upstream_default_model:
                            planner_cfg["requestedModel"] = {"model": upstream_default_model}
                        else:
                            planner_cfg.pop("requestedModel", None)
                    sanitized["cascadeConfig"] = cascade_cfg
                return 200, sanitized

            if method == "HandleCascadeUserInteraction":
                cloned = json.loads(json.dumps(req_obj))
                interaction = cloned.get("interaction") or {}
                rc = interaction.get("runCommand")
                if isinstance(rc, dict):
                    if rc.get("confirm") and rc.get("faceIdVerified") is False:
                        return 403, {"accepted": False, "reason": "Face ID verification required"}
                    rc.pop("faceIdVerified", None)
                return 200, cloned

            return 200, req_obj

        def _select_backend_for_request(self, backends: list[dict], method: str, req_obj: dict) -> dict:
            cid = (
                req_obj.get("cascadeId")
                or (req_obj.get("interaction") or {}).get("trajectoryId")
                or ""
            )
            if cid:
                with state.lock:
                    mapped = state.cascade_to_backend.get(cid)
                if mapped:
                    return mapped
            return backends[0]

        def _proxy_to_upstream(self, backends: list[dict], method: str, raw_body: bytes, content_type: str):
            is_json = "json" in content_type.lower() and "connect+" not in content_type.lower()
            forward_body = raw_body
            req_obj = {}

            if is_json:
                req_obj = self._parse_json(raw_body)
                gate_status, sanitized = self._sanitize_for_upstream(method, req_obj)
                if gate_status != 200:
                    self._write_json(gate_status, sanitized)
                    return
                req_obj = sanitized
                forward_body = json.dumps(req_obj).encode("utf-8")
            elif method == "GetCascadeTrajectorySteps" and "application/proto" in content_type.lower():
                req_cid, _, _ = decode_get_steps_protobuf_request(raw_body)
                if req_cid:
                    req_obj = {"cascadeId": req_cid}

            chosen_backend = self._select_backend_for_request(backends, method, req_obj)
            target = f"{chosen_backend['upstream_url']}{SERVICE_PREFIX}{method}"

            headers = {
                "Content-Type": content_type,
                "Connect-Protocol-Version": self.headers.get("Connect-Protocol-Version", "1"),
                "x-codeium-csrf-token": chosen_backend.get("upstream_csrf") or bridge_csrf,
            }
            if "Accept" in self.headers:
                headers["Accept"] = self.headers["Accept"]

            is_https = target.startswith("https://")
            attempts = 0
            while True:
                attempts += 1
                req = urllib.request.Request(target, data=forward_body, method="POST", headers=headers)
                try:
                    with urlopen_direct(
                        req,
                        timeout=30,
                        ssl_ctx=ssl_ctx if is_https else None,
                    ) as resp:
                        resp_bytes = resp.read()
                        resp_ct = resp.headers.get("Content-Type", "application/json")
                        if is_json and method == "StartCascade":
                            sc_obj = self._parse_json(resp_bytes)
                            new_cid = sc_obj.get("cascadeId")
                            if new_cid:
                                uris = req_obj.get("workspaceUris") or []
                                ws_uri = uris[0] if uris else state.workspaces[0]["workspaceUri"]
                                slug = Path(ws_uri.replace("file://", "")).name or "workspace"
                                with state.lock:
                                    state.cascade_to_backend[new_cid] = chosen_backend
                                    state.trajectories.setdefault(
                                        new_cid,
                                        {
                                            "cascadeId": new_cid,
                                            "title": "New iOS Remote Session",
                                            "projectSlug": slug,
                                            "workspaceUri": ws_uri,
                                            "branchName": "main",
                                            "status": "CORTEX_STEP_STATUS_DONE",
                                            "stepCount": 0,
                                            "statusSubtitle": "Ready for instructions",
                                            "isPinned": False,
                                            "isArchived": False,
                                            "isUnread": False,
                                        },
                                    )
                                    state.steps_by_cascade.setdefault(new_cid, [])
                        elif is_json and method == "SendUserCascadeMessage":
                            cid = req_obj.get("cascadeId", "")
                            if cid:
                                items = req_obj.get("items") or []
                                text_val = next(
                                    (i.get("text", "") for i in items if isinstance(i, dict) and "text" in i),
                                    "",
                                )
                                with state.lock:
                                    state.cascade_to_backend[cid] = chosen_backend
                                    local_steps = state.steps_by_cascade.setdefault(cid, [])
                                    if not local_steps and text_val:
                                        local_steps.append(
                                            {
                                                "stepIndex": 0,
                                                "type": "CORTEX_STEP_TYPE_USER_INPUT",
                                                "status": "CORTEX_STEP_STATUS_DONE",
                                                "userInput": {"userResponse": text_val, "items": items},
                                            }
                                        )
                                    if cid in state.trajectories:
                                        if text_val and state.trajectories[cid]["title"].startswith("New "):
                                            state.trajectories[cid]["title"] = text_val[:48]
                                        state.trajectories[cid]["stepCount"] = max(
                                            state.trajectories[cid]["stepCount"], len(local_steps)
                                        )
                        elif is_json and method == "GetCascadeTrajectorySteps":
                            resp_bytes = self._ensure_loaded_and_merge_steps(
                                chosen_backend, backends, req_obj, resp_bytes
                            )
                        self.send_response(resp.status)
                        self._send_cors()
                        self.send_header("Content-Type", resp_ct)
                        self.send_header("Content-Length", str(len(resp_bytes)))
                        self.end_headers()
                        self.wfile.write(resp_bytes)
                        return
                except urllib.error.HTTPError as e:
                    err_body = e.read()
                    err_text = err_body.decode("utf-8", errors="ignore")
                    if is_json and e.code == 400 and attempts <= 4:
                        err_search = err_text
                        try:
                            err_json = json.loads(err_text)
                            if isinstance(err_json, dict):
                                for err_k in ("message", "error", "detail"):
                                    if isinstance(err_json.get(err_k), str) and err_json[err_k]:
                                        err_search = err_json[err_k]
                                        break
                        except Exception:
                            pass
                        err_search = err_search.replace('\\"', '"')
                        field_m = re.search(
                            r'(?:unknown field|no such field|unrecognized field)\s+["\'`]+([A-Za-z0-9_]+)["\'`]+',
                            err_search,
                            re.IGNORECASE,
                        )
                        if field_m:
                            updated_obj, did_remove = recursively_strip_field(req_obj, field_m.group(1))
                            if did_remove and isinstance(updated_obj, dict):
                                req_obj = updated_obj
                                forward_body = json.dumps(req_obj).encode("utf-8")
                                continue
                        enum_m = re.search(
                            r'(?:invalid value for enum|unknown enum value|invalid enum value)[^"\'`]*["\'`]+([A-Za-z0-9_\-]+)["\'`]+',
                            err_search,
                            re.IGNORECASE,
                        )
                        if enum_m:
                            invalid_enum = enum_m.group(1)
                            if invalid_enum in BRIDGE_ENUM_DOWNGRADES:
                                replacement = BRIDGE_ENUM_DOWNGRADES[invalid_enum]
                                updated_obj, did_replace = recursively_downgrade_enum(req_obj, invalid_enum, replacement)
                                if did_replace and isinstance(updated_obj, dict):
                                    req_obj = updated_obj
                                    forward_body = json.dumps(req_obj).encode("utf-8")
                                    continue
                            updated_obj, did_strip_enum = recursively_strip_keys_with_value(req_obj, invalid_enum)
                            if did_strip_enum and isinstance(updated_obj, dict):
                                req_obj = updated_obj
                                forward_body = json.dumps(req_obj).encode("utf-8")
                                continue
                    if is_json and method in ("StartCascade", "SendUserCascadeMessage") and e.code in (
                        400,
                        401,
                        403,
                        404,
                        500,
                        502,
                        503,
                    ):
                        sys.stderr.write(
                            f"[Bridge] Upstream {method} returned HTTP {e.code} ({err_text[:120]}); falling back to companion session store.\n"
                        )
                        self._handle_standalone_rpc(method, raw_body, content_type)
                        return
                    self.send_response(e.code)
                    self._send_cors()
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(err_body)))
                    self.end_headers()
                    self.wfile.write(err_body)
                    return
                except Exception as exc:
                    if is_json and method in ("StartCascade", "SendUserCascadeMessage"):
                        sys.stderr.write(
                            f"[Bridge] Upstream {method} transport error ({exc}); falling back to companion session store.\n"
                        )
                        self._handle_standalone_rpc(method, raw_body, content_type)
                        return
                    self._write_json(502, {"error": f"Upstream language_server error: {exc}"})
                    return

        def _ensure_loaded_and_merge_steps(
            self,
            chosen_backend: dict,
            backends: list[dict],
            req_obj: dict,
            resp_bytes: bytes,
        ) -> bytes:
            obj = self._parse_json(resp_bytes)
            cid = req_obj.get("cascadeId", "")
            steps = obj.get("steps") or []
            if not steps and cid:
                # 1. Try `LoadTrajectory` on `chosen_backend` (and any secondary backends) to wake up dormant disk sessions
                with state.lock:
                    already_loaded = cid in state.loaded_trajectories
                    if not already_loaded:
                        state.loaded_trajectories.add(cid)
                if not already_loaded:
                    for b in [chosen_backend] + [x for x in backends if x != chosen_backend]:
                        federation.call_backend_json(b, "LoadTrajectory", {"cascadeId": cid}, timeout=2.5)
                        retry_res = federation.call_backend_json(b, "GetCascadeTrajectorySteps", req_obj, timeout=4.0)
                        if isinstance(retry_res, dict) and retry_res.get("steps"):
                            obj["steps"] = retry_res["steps"]
                            steps = obj["steps"]
                            with state.lock:
                                state.cascade_to_backend[cid] = b
                            break
                # 2. Fallback to local companion steps if still empty
                if not steps:
                    with state.lock:
                        local_steps = state.steps_by_cascade.get(cid)
                        if local_steps:
                            obj["steps"] = list(local_steps)
            return json.dumps(obj).encode("utf-8")

        def _handle_standalone_rpc(self, method: str, raw_body: bytes, content_type: str):
            if method == "JetboxSubscribeToSummaries":
                with state.lock:
                    first = next(iter(state.trajectories.values()), {})
                frame1 = encode_connect_frame(
                    json.dumps(
                        {
                            "cascadeId": first.get("cascadeId", "cas-live-welcome"),
                            "title": first.get("title", "Session"),
                            "status": first.get("status", "CORTEX_STEP_STATUS_DONE"),
                            "stepCount": first.get("stepCount", 2),
                            "summary": first.get("statusSubtitle", "Ready"),
                        }
                    ).encode("utf-8"),
                    flags=0x00,
                )
                end_frame = encode_connect_frame(b"{}", flags=0x02)
                payload = frame1 + end_frame
                self.send_response(200)
                self._send_cors()
                self.send_header("Content-Type", "application/connect+json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return

            if method == "GetCascadeTrajectorySteps" and "application/proto" in content_type.lower():
                req_cid, step_offset, count_hint = decode_get_steps_protobuf_request(raw_body)
                with state.lock:
                    live_steps = (
                        list(state.steps_by_cascade[req_cid])
                        if req_cid and req_cid in state.steps_by_cascade
                        else None
                    )
                if count_hint > 0 or not req_cid or live_steps is None:
                    proto_bytes = state.build_binary_steps(
                        req_cid or "cas-live-welcome",
                        count=max(count_hint, 605),
                    )
                else:
                    proto_bytes = state.encode_live_steps_protobuf(live_steps[step_offset:])
                self.send_response(200)
                self._send_cors()
                self.send_header("Content-Type", "application/proto")
                self.send_header("Content-Length", str(len(proto_bytes)))
                self.end_headers()
                self.wfile.write(proto_bytes)
                return

            req_obj = self._parse_json(raw_body)

            if method == "GetWorkspaceInfos":
                with state.lock:
                    self._write_json(200, {"workspaces": list(state.workspaces)})
                return

            if method == "GetAllCascadeTrajectories":
                with state.lock:
                    trajectories_list = list(state.trajectories.values())
                    summaries_map = {
                        cid: {
                            "summary": t["title"],
                            "stepCount": t["stepCount"],
                            "status": t["status"],
                            "workspaces": [{"workspaceFolderAbsoluteUri": t["workspaceUri"]}],
                        }
                        for cid, t in state.trajectories.items()
                    }
                self._write_json(
                    200,
                    {
                        "trajectories": trajectories_list,
                        "trajectorySummaries": summaries_map,
                    },
                )
                return

            if method == "StartCascade":
                uris = req_obj.get("workspaceUris") or []
                ws_uri = uris[0] if uris else state.workspaces[0]["workspaceUri"]
                slug = Path(ws_uri.replace("file://", "")).name or "workspace"
                initial_input = req_obj.get("initialUserInput", "").strip()
                new_cid = f"cas-{uuid.uuid4().hex[:8]}"
                title = initial_input[:48] if initial_input else "New iOS Remote Session"
                with state.lock:
                    state.trajectories[new_cid] = {
                        "cascadeId": new_cid,
                        "title": title,
                        "projectSlug": slug,
                        "workspaceUri": ws_uri,
                        "branchName": "main",
                        "status": "CORTEX_STEP_STATUS_DONE",
                        "stepCount": 0,
                        "statusSubtitle": "Ready for instructions",
                        "isPinned": False,
                        "isArchived": False,
                        "isUnread": False,
                    }
                    state.steps_by_cascade[new_cid] = []
                self._write_json(200, {"cascadeId": new_cid})
                return

            if method == "SendUserCascadeMessage":
                cid = req_obj.get("cascadeId") or "cas-live-welcome"
                user_text = req_obj.get("userResponse", "")
                mentions = []
                for item in req_obj.get("items", []):
                    if isinstance(item, dict):
                        if "text" in item and not user_text:
                            user_text = item["text"]
                        file_info = item.get("item", {}).get("file", {})
                        if file_info.get("label"):
                            mentions.append(file_info["label"])
                model_cfg = req_obj.get("modelConfig", {})
                mode_name = model_cfg.get("mode", "PLANNING")
                model_id = (
                    req_obj.get("cascadeConfig", {})
                    .get("plannerConfig", {})
                    .get("requestedModel", {})
                    .get("model")
                    or model_cfg.get("modelId", "Gemini 3.1 Pro")
                )

                with state.lock:
                    steps = state.steps_by_cascade.setdefault(cid, [])
                    idx_user = len(steps)
                    steps.append(
                        {
                            "stepIndex": idx_user,
                            "type": "CORTEX_STEP_TYPE_USER_INPUT",
                            "status": "CORTEX_STEP_STATUS_DONE",
                            "attachedMentions": mentions,
                            "userInput": {
                                "userResponse": user_text,
                                "items": req_obj.get("items", [{"text": user_text}]),
                            },
                        }
                    )
                    if "vegeta" in user_text.lower() or "run_command" in user_text.lower():
                        steps.append(
                            {
                                "stepIndex": idx_user + 1,
                                "type": "CORTEX_STEP_TYPE_RUN_COMMAND",
                                "status": "CORTEX_STEP_STATUS_WAITING",
                                "runCommand": {
                                    "commandId": f"cmd-{idx_user + 1}",
                                    "commandLine": "go test -v ./...",
                                    "proposedCommandLine": "go test -v ./...",
                                    "cwd": state.workspace_root,
                                },
                                "requestedInteraction": {
                                    "runCommand": {
                                        "proposedCommandLine": "go test -v ./...",
                                        "cwd": state.workspace_root,
                                    }
                                },
                            }
                        )
                        new_status = "CORTEX_STEP_STATUS_WAITING"
                        subtitle = "Waiting for Face ID approval"
                    else:
                        steps.append(
                            {
                                "stepIndex": idx_user + 1,
                                "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
                                "status": "CORTEX_STEP_STATUS_DONE",
                                "plannerResponse": {
                                    "thinking": f"Processed message in {mode_name} mode with model {model_id} and {len(mentions)} attached context chips.",
                                    "thinkingDurationSeconds": 2.4,
                                    "response": f"Received on `{socket.gethostname()}`: **\"{user_text}\"** (mentions: `{mentions or ['none']}`, model: `{model_id}`).",
                                },
                            }
                        )
                        new_status = "CORTEX_STEP_STATUS_DONE"
                        subtitle = f"Done · {len(steps)} steps"

                    if cid in state.trajectories:
                        if state.trajectories[cid]["title"].startswith("New "):
                            state.trajectories[cid]["title"] = user_text[:48] or "New Session"
                        state.trajectories[cid]["stepCount"] = len(steps)
                        state.trajectories[cid]["status"] = new_status
                        state.trajectories[cid]["statusSubtitle"] = subtitle

                self._write_json(200, {"ok": True, "cascadeId": cid})
                return

            if method == "GetCascadeTrajectorySteps":
                cid = req_obj.get("cascadeId") or "cas-live-welcome"
                start_idx = int(req_obj.get("stepOffset", req_obj.get("startIndex", 0)))
                end_idx = int(req_obj.get("endIndex", start_idx + 200))
                with state.lock:
                    steps = state.steps_by_cascade.get(cid, [])[start_idx:end_idx]
                self._write_json(200, {"steps": steps})
                return

            if method == "HandleCascadeUserInteraction":
                interaction = req_obj.get("interaction", {})
                cid = interaction.get("trajectoryId", "cas-live-welcome")
                step_idx = int(interaction.get("stepIndex", 0))
                rc = interaction.get("runCommand")
                if rc and rc.get("confirm") and not rc.get("faceIdVerified"):
                    self._write_json(
                        403,
                        {"accepted": False, "reason": "Face ID verification required"},
                    )
                    return
                with state.lock:
                    steps = state.steps_by_cascade.get(cid, [])
                    for s in steps:
                        if s.get("stepIndex") == step_idx:
                            s["status"] = "CORTEX_STEP_STATUS_DONE"
                    steps.append(
                        {
                            "stepIndex": len(steps),
                            "type": "CORTEX_STEP_TYPE_PLANNER_RESPONSE",
                            "status": "CORTEX_STEP_STATUS_DONE",
                            "plannerResponse": {
                                "thinking": "Face ID approval verified via HandleCascadeUserInteraction.",
                                "thinkingDurationSeconds": 1.1,
                                "response": "Command approved and executed (`0` exit code).",
                            },
                        }
                    )
                    if cid in state.trajectories:
                        state.trajectories[cid]["status"] = "CORTEX_STEP_STATUS_DONE"
                        state.trajectories[cid]["stepCount"] = len(steps)
                self._write_json(200, {"accepted": True, "cascadeId": cid, "stepIndex": step_idx})
                return

            if method == "CancelCascadeInvocation":
                cid = req_obj.get("cascadeId", "")
                with state.lock:
                    if cid in state.trajectories:
                        state.trajectories[cid]["status"] = "CORTEX_STEP_STATUS_CANCELLED"
                self._write_json(200, {"ok": True, "cascadeId": cid})
                return

            if method == "GetSidecars":
                with state.lock:
                    sidecars = []
                    for a in state.automations:
                        cron_expr = a.get("cronExpression") or "0 9 * * 1-5"
                        prompt_text = a.get("prompt") or a.get("title") or "Scheduled Automation"
                        enabled = a.get("section", "SCHEDULED") != "PAUSED"
                        sidecars.append(
                            {
                                "sidecarId": a["id"],
                                "status": "SIDECAR_STATUS_RUNNING" if enabled else "SIDECAR_STATUS_STOPPED",
                                "config": {
                                    "builtin": "schedule",
                                    "restartPolicy": "always",
                                    "displayName": a.get("title", a["id"]),
                                    "description": a.get("descriptionText", ""),
                                    "args": [cron_expr, "agentapi", "new-conversation", "--", prompt_text],
                                },
                                "userConfig": {
                                    "enabled": enabled,
                                    "projectId": a.get("projectSlug", ""),
                                    "allProjects": bool(a.get("allProjects", False)),
                                },
                            }
                        )
                self._write_json(200, {"sidecars": sidecars})
                return

            if method == "GetSidecarEvents":
                sid = req_obj.get("sidecarId", "")
                events = []
                with state.lock:
                    for a in state.automations:
                        if a["id"] == sid and a.get("lastRunCascadeId"):
                            events.append(
                                {
                                    "timestampMs": str(int(time.time() * 1000)),
                                    "payload": {
                                        "newConversation": {
                                            "conversationId": a["lastRunCascadeId"],
                                            "prompt": a.get("prompt") or a.get("title") or "",
                                        }
                                    },
                                }
                            )
                self._write_json(200, {"events": events})
                return

            if method == "ManageSidecar":
                sid = req_obj.get("sidecarId") or f"auto-{uuid.uuid4().hex[:8]}"
                action = str(req_obj.get("action", "")).upper()
                cfg = req_obj.get("config") or {}
                args = cfg.get("args") or []
                cron_expr = args[0] if args else "0 9 * * 1-5"
                prompt_text = args[-1] if args else cfg.get("displayName", "Scheduled Automation")
                with state.lock:
                    existing = next((a for a in state.automations if a["id"] == sid), None)
                    if action == "SIDECAR_ACTION_CREATE":
                        proj_slug = req_obj.get("projectId") or ("All projects" if req_obj.get("allProjects") else "This Computer")
                        item = {
                            "id": sid,
                            "title": cfg.get("displayName") or prompt_text,
                            "projectSlug": proj_slug,
                            "scheduleSummary": f"{proj_slug} · Scheduled · Flash",
                            "section": "SCHEDULED",
                            "nextRunText": "Tomorrow, 09:00",
                            "lastRunText": "Created just now",
                            "cronExpression": cron_expr,
                            "prompt": prompt_text,
                            "descriptionText": cfg.get("description", ""),
                            "allProjects": bool(req_obj.get("allProjects", False)),
                        }
                        state.automations = [a for a in state.automations if a["id"] != sid]
                        state.automations.insert(0, item)
                    elif action == "SIDECAR_ACTION_UPDATE" and existing is not None:
                        existing["title"] = cfg.get("displayName") or existing["title"]
                        existing["cronExpression"] = cron_expr
                        existing["prompt"] = prompt_text
                        existing["descriptionText"] = cfg.get("description", existing.get("descriptionText", ""))
                    elif action == "SIDECAR_ACTION_SET_PROJECT" and existing is not None:
                        existing["projectSlug"] = req_obj.get("projectId") or existing["projectSlug"]
                        existing["allProjects"] = False
                    elif action == "SIDECAR_ACTION_SET_ALL_PROJECTS" and existing is not None:
                        existing["allProjects"] = bool(req_obj.get("allProjects", True))
                        if existing["allProjects"]:
                            existing["projectSlug"] = "All projects"
                    elif action == "SIDECAR_ACTION_DISABLE" and existing is not None:
                        existing["section"] = "PAUSED"
                        existing["lastRunText"] = "Paused"
                    elif action == "SIDECAR_ACTION_ENABLE" and existing is not None:
                        existing["section"] = "SCHEDULED"
                        existing["lastRunText"] = "Resumed · just now"
                    elif action == "SIDECAR_ACTION_DELETE":
                        state.automations = [a for a in state.automations if a["id"] != sid]
                    elif action == "SIDECAR_ACTION_RUN_NOW" and existing is not None:
                        existing["isRunningNow"] = True
                        existing["lastRunText"] = "Running now..."
                        first_cid = next(iter(state.trajectories.keys()), None)
                        if first_cid:
                            existing["lastRunCascadeId"] = first_cid
                self._write_json(200, {"sidecarId": sid, "ok": True})
                return

            self._write_json(200, {"ok": True, "method": method})

        def _parse_json(self, raw_body: bytes) -> dict:
            if not raw_body:
                return {}
            try:
                return json.loads(raw_body.decode("utf-8"))
            except Exception:
                return {}

        def _write_json(self, status: int, data: dict):
            encoded = json.dumps(data).encode("utf-8")
            self.send_response(status)
            self._send_cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    class ReusableThreadingHTTPServer(ThreadingHTTPServer):
        allow_reuse_address = True
        daemon_threads = True

    return ReusableThreadingHTTPServer((bind_host, bind_port), BridgeHandler)


def main():
    parser = argparse.ArgumentParser(description="Antigravity iOS — Mac Companion Bridge")
    parser.add_argument("--bind", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8787, help="Port to expose (default: 8787)")
    parser.add_argument("--csrf", default=None, help="Override x-codeium-csrf-token")
    parser.add_argument("--upstream-url", default=None, help="Explicit upstream language_server URL")
    parser.add_argument("--upstream-csrf", default=None, help="Explicit upstream language_server CSRF token")
    parser.add_argument(
        "--standalone-sandbox",
        action="store_true",
        help="Run built-in stateful LanguageServerService when Antigravity Desktop is not running",
    )
    args = parser.parse_args()

    upstream_url = args.upstream_url
    upstream_csrf = args.upstream_csrf
    extra_backends = []

    if not args.standalone_sandbox and not upstream_url:
        print("[*] Scanning for local Antigravity Desktop `language_server` / `agy --hub` backends...", flush=True)
        discovered_all = discover_all_local_language_servers()
        if discovered_all:
            primary = discovered_all[0]
            upstream_url = primary["upstream_url"]
            upstream_csrf = primary["upstream_csrf"]
            extra_backends = discovered_all[1:]
            for idx, b in enumerate(discovered_all):
                role = "HUB" if b.get("is_hub") else "LS"
                print(
                    f"[+] Auto-discovered Antigravity {role} #{idx + 1} (PID {b['pid']}) at {b['upstream_url']}",
                    flush=True,
                )
        else:
            print(
                "[!] No running Antigravity Desktop `language_server` detected; starting in Stateful Companion Sandbox mode.",
                flush=True,
            )
            print(
                "    (Open Antigravity Desktop on macOS and re-run to proxy real desktop sessions automatically.)",
                flush=True,
            )

    bridge_csrf = args.csrf or upstream_csrf or f"agy-ios-{secrets.token_hex(12)}"
    lan_ip = detect_lan_ip()
    endpoint = f"http://{lan_ip}:{args.port}"
    hostname = socket.gethostname()
    pair_uri = (
        f"antigravity://pair?"
        f"url={urllib.parse.quote(endpoint, safe='')}"
        f"&csrf={urllib.parse.quote(bridge_csrf, safe='')}"
        f"&name={urllib.parse.quote(hostname, safe='')}"
    )

    server = create_bridge_server(
        bind_host=args.bind,
        bind_port=args.port,
        bridge_csrf=bridge_csrf,
        upstream_url=upstream_url,
        upstream_csrf=upstream_csrf,
        extra_backends=extra_backends,
        auto_discover=(not args.standalone_sandbox and not args.upstream_url),
    )

    total_upstreams = (1 if upstream_url else 0) + len(extra_backends)
    print("\n" + "=" * 74, flush=True)
    print("  iOSAntigravity — Connect-RPC Backend Bridge Ready", flush=True)
    print("=" * 74, flush=True)
    print(
        f"  Mode          : {'LIVE DESKTOP PROXY (' + str(total_upstreams) + ' backend(s), primary -> ' + upstream_url + ')' if upstream_url else 'STATEFUL SANDBOX'}",
        flush=True,
    )
    print(f"  LAN Endpoint  : {endpoint}", flush=True)
    print(f"  CSRF Token    : {bridge_csrf}", flush=True)
    print(f"  iPhone Safari : {endpoint}/pair   (1-Tap Pair on Physical iPhone)", flush=True)
    print(f"  iOS Deep Link : {pair_uri}", flush=True)
    print("-" * 74, flush=True)
    print("  Quick CLI Verification:", flush=True)
    print(f"    python3 verification/verify-live-rpc-flow.py --url {endpoint} --csrf {bridge_csrf} --read-only", flush=True)
    print("=" * 74 + "\n", flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down bridge...", flush=True)
        server.shutdown()


if __name__ == "__main__":
    main()
