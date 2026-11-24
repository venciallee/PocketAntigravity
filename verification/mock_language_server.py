#!/usr/bin/env python3
"""Mock Antigravity LanguageServer (`exa.language_server_pb.LanguageServerService`).

Supports the full Connect-RPC & Binary Protobuf E2E surface for PocketAntigravity v2.0:
1. 5-byte Connect streaming envelope (`[flags:1B][length:4B BE][payload]`) for
   `JetboxSubscribeToSummaries` and `StreamCascadeReactiveUpdates`.
2. Binary Protobuf (`Content-Type: application/proto`) for `GetCascadeTrajectorySteps`
   with >600 steps (605 steps default), including field 56 (`requestedInteraction` oneof).
3. Face ID-signed `HandleCascadeUserInteraction` (`runCommand`, `askQuestion`,
   `filePermission`, `permission`, `planReview`).
4. Workspace & Automation RPCs: `CreateProjectWorkspace` (MacBook Pro / Cloud),
   `TriggerAutomationNow`, `CreateAutomation`, `ResumeAutomation`,
   `SendUserCascadeMessage`, `SubmitReviewComments`, and `MarkAllConversationsRead`.
5. CORS headers (`Access-Control-Allow-Origin: *`) so interactive mobile viewport E2E
   tests (`TC-01`..`TC-16`) can dispatch live `fetch()` RPCs directly from the UI.
"""
import json
import socketserver
import struct
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


def encode_varint(value: int) -> bytes:
    if value == 0:
        return b"\x00"
    out = bytearray()
    while value > 0x7F:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value & 0x7F)
    return bytes(out)


def decode_varint(buf: bytes, offset: int = 0):
    result = 0
    shift = 0
    while offset < len(buf):
        b = buf[offset]
        offset += 1
        result |= (b & 0x7F) << shift
        if (b & 0x80) == 0:
            return result, offset
        shift += 7
    raise ValueError("Truncated varint")


def encode_ld(field_number: int, payload: bytes) -> bytes:
    tag = (field_number << 3) | 2
    return encode_varint(tag) + encode_varint(len(payload)) + payload


def encode_varint_field(field_number: int, value: int) -> bytes:
    tag = (field_number << 3) | 0
    return encode_varint(tag) + encode_varint(value)


def encode_connect_envelope(payload: bytes, flags: int = 0x00) -> bytes:
    return struct.pack(">BI", flags, len(payload)) + payload


def parse_connect_envelopes(raw: bytes):
    offset = 0
    frames = []
    while offset + 5 <= len(raw):
        flags, length = struct.unpack(">BI", raw[offset : offset + 5])
        offset += 5
        payload = raw[offset : offset + length]
        offset += length
        frames.append((flags, payload))
    return frames


def build_sample_binary_steps_response(total_steps: int = 605) -> bytes:
    """Builds a binary Protobuf GetCascadeTrajectoryStepsResponse with >600 steps."""
    out = bytearray()
    for idx in range(total_steps):
        step_buf = bytearray()
        if idx == total_steps - 1:
            # WAITING step (status=9) with requestedInteraction.runCommand (field 23 inside field 56)
            step_buf += encode_varint_field(1, 21)  # CORTEX_STEP_TYPE_RUN_COMMAND
            step_buf += encode_varint_field(4, 9)   # CORTEX_STEP_STATUS_WAITING
            cmd_spec = encode_ld(
                1,
                b"vegeta attack -rate=2000/s -duration=30s -targets=load/transfers.txt | vegeta report",
            )
            req_interaction = encode_ld(23, cmd_spec)
            step_buf += encode_ld(56, req_interaction)
        elif idx == total_steps - 2:
            # Structured ask_question step (field 24 inside field 56)
            step_buf += encode_varint_field(1, 28)  # CORTEX_STEP_TYPE_ASK_QUESTION
            step_buf += encode_varint_field(4, 3)   # CORTEX_STEP_STATUS_DONE
            q_spec = encode_ld(1, b"Which admin actions should be audited?")
            step_buf += encode_ld(56, encode_ld(24, q_spec))
        else:
            step_buf += encode_varint_field(1, 15)  # CORTEX_STEP_TYPE_PLANNER_RESPONSE
            step_buf += encode_varint_field(4, 3)   # CORTEX_STEP_STATUS_DONE
            planner = encode_ld(1, f"Step {idx} completed.".encode("utf-8")) + encode_ld(
                3, b"Isolating fake clock & verifying rate limiter"
            )
            step_buf += encode_ld(20, planner)
        out += encode_ld(1, bytes(step_buf))
    return bytes(out)


class MockServerState:
    def __init__(self):
        self.lock = threading.Lock()
        self.rpc_log = []
        self.unread_count = 3
        self.projects = [
            {
                "id": "proj-ledger-svc",
                "name": "ledger-svc",
                "path": "~/code/ledger-svc",
                "runtime": "macbook_pro",
                "sourceType": "github",
                "repository": "acme/ledger-svc",
                "branch": "main",
                "conversationCount": 5,
            },
            {
                "id": "proj-web-console",
                "name": "web-console",
                "path": "cloud://acme/web-console",
                "runtime": "cloud",
                "sourceType": "github",
                "repository": "acme/web-console",
                "branch": "main",
                "conversationCount": 3,
            },
        ]
        self.automations = [
            {
                "id": "auto-nightly-audit",
                "title": "Nightly dependency audit",
                "project": "ledger-svc",
                "schedule": "Daily at 02:00",
                "model": "Flash",
                "state": "scheduled",
                "nextRun": "Tonight, 02:00",
                "lastRun": "Succeeded · 22h ago",
                "runCount": 14,
            },
            {
                "id": "auto-weekly-flaky",
                "title": "Weekly flaky-test report",
                "project": "ledger-svc",
                "schedule": "Mondays at 09:00",
                "model": "Pro",
                "state": "scheduled",
                "nextRun": "Mon, 09:00",
                "lastRun": "Needs review · 2d",
                "runCount": 6,
            },
            {
                "id": "auto-pr-triage",
                "title": "Triage new pull requests",
                "project": "web-console",
                "schedule": "On PR opened",
                "model": "Flash Lite",
                "state": "always_on",
                "lastRun": "Last run 14m ago",
                "runCount": 42,
            },
            {
                "id": "auto-bundle-watch",
                "title": "Bundle size watch",
                "project": "web-console",
                "schedule": "Daily at 08:00",
                "model": "Flash",
                "state": "paused",
                "lastRun": "Paused 3d ago",
                "runCount": 9,
            },
        ]
        self.interactions = []
        self.messages = []
        self.reviews = []

    def record(self, method: str, payload: dict):
        with self.lock:
            self.rpc_log.append({"method": method, "payload": payload})


class _FastThreadingHTTPServer(ThreadingHTTPServer):
    """ThreadingHTTPServer that skips socket.getfqdn() in server_bind() to avoid 5s+ macOS reverse-DNS stalls on 127.0.0.1."""

    allow_reuse_address = True

    def server_bind(self):
        # Call TCPServer.server_bind directly to skip HTTPServer's blocking socket.getfqdn(host)
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = int(port)


class LiveMockServer:
    def __init__(self, host: str = "127.0.0.1", port: int = 0):
        self._bind_host = host
        self._bind_port = port
        self.state = MockServerState()
        outer_state = self.state

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, fmt, *args):
                pass

            def _send_cors_headers(self):
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header(
                    "Access-Control-Allow-Methods", "GET, POST, OPTIONS"
                )
                self.send_header(
                    "Access-Control-Allow-Headers",
                    "Content-Type, Accept, Connect-Protocol-Version, X-FaceID-Signature",
                )

            def do_OPTIONS(self):
                self.send_response(204)
                self._send_cors_headers()
                self.send_header("Content-Length", "0")
                self.end_headers()

            def do_GET(self):
                req_path = urlparse(self.path).path
                if req_path == "/__mock_state":
                    with outer_state.lock:
                        snapshot = {
                            "unreadCount": outer_state.unread_count,
                            "projectCount": len(outer_state.projects),
                            "projects": list(outer_state.projects),
                            "automations": list(outer_state.automations),
                            "interactionCount": len(outer_state.interactions),
                            "messageCount": len(outer_state.messages),
                            "reviewCount": len(outer_state.reviews),
                            "rpcLog": list(outer_state.rpc_log),
                        }
                    self._send_json(200, snapshot)
                    return
                if req_path == "/" or req_path.startswith("/r/"):
                    html = (
                        "<!doctype html><html><head>"
                        '<meta name="antigravity-relay-api-key" content="mock-relay-web-api-key">'
                        "</head><body>Antigravity Mock Cloud Relay</body></html>"
                    ).encode("utf-8")
                    self.send_response(200)
                    self._send_cors_headers()
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.send_header("X-Goog-Api-Key", "mock-relay-web-api-key")
                    self.send_header("Content-Length", str(len(html)))
                    self.end_headers()
                    self.wfile.write(html)
                    return
                self._send_json(404, {"error": "Not found"})

            def _verify_sapisidhash(self) -> bool:
                import hashlib

                auth_hdr = self.headers.get("Authorization", "")
                cookie_hdr = self.headers.get("Cookie", "")
                origin = self.headers.get("Origin") or "https://antigravity.google.com"
                if not auth_hdr.startswith("SAPISIDHASH ") or "SAPISID=" not in cookie_hdr:
                    return False
                sapisid = ""
                for part in cookie_hdr.split(";"):
                    part = part.strip()
                    if part.startswith("SAPISID="):
                        sapisid = part[len("SAPISID=") :]
                        break
                if not sapisid:
                    return False
                first_tok = auth_hdr.split()[1] if len(auth_hdr.split()) >= 2 else ""
                if "_" not in first_tok:
                    return False
                ts_str, digest = first_tok.split("_", 1)
                expected = hashlib.sha1(f"{ts_str} {sapisid} {origin}".encode("utf-8")).hexdigest()
                return digest == expected

            def _send_jspb(self, status: int, jspb_obj):
                raw = (")]}'\n" + json.dumps(jspb_obj)).encode("utf-8")
                self.send_response(status)
                self._send_cors_headers()
                self.send_header("Content-Type", "application/json+protobuf; charset=utf-8")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def do_POST(self):
                import base64

                path = urlparse(self.path).path
                content_len = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(content_len) if content_len > 0 else b""
                prefix = "/exa.language_server_pb.LanguageServerService/"
                relay_prefix = "/$rpc/devtools_jetski_boq_api_proto.ApiService/"

                if path.startswith(relay_prefix):
                    relay_method = path[len(relay_prefix) :]
                    if not self._verify_sapisidhash():
                        self._send_json(401, {"error": "Missing or invalid SAPISIDHASH Authorization"})
                        return

                    auth_user = self.headers.get("X-Goog-AuthUser", "0")
                    if relay_method == "ListInstances":
                        outer_state.record("ApiService/ListInstances", {"authUser": auth_user})
                        # Simulate multi-account session where authuser=2 owns the active Desktop instance
                        if auth_user == "2":
                            instances_jspb = [
                                [
                                    [
                                        "0f5819ac-9308-40d8-a308-98b55122c533-v2",
                                        ["lt74xt6l0m-golden-star", "2.32.0", 1],
                                        1,
                                        [1794406100, 0],
                                    ]
                                ],
                                5,
                            ]
                        else:
                            instances_jspb = [[], 5]
                        self._send_jspb(200, instances_jspb)
                        return

                    if relay_method == "ProxyCommand":
                        arr = json.loads(body.decode("utf-8"))
                        target_uuid = arr[0]
                        rpc_path = arr[1]
                        inner_b64 = arr[2] or ""
                        inner_headers = {k.lower(): v for k, v in (arr[3] or [])}
                        if target_uuid != "0f5819ac-9308-40d8-a308-98b55122c533-v2":
                            self._send_json(404, {"error": f"Unknown instance UUID {target_uuid}"})
                            return
                        inner_method = rpc_path[len(prefix) :] if rpc_path.startswith(prefix) else rpc_path
                        inner_bytes = base64.b64decode(inner_b64) if inner_b64 else b""
                        inner_ct = inner_headers.get("content-type", "application/json")
                        outer_state.record(f"ApiService/ProxyCommand:{inner_method}", {"contentType": inner_ct})

                        if inner_method == "GetCascadeTrajectorySteps" and "application/proto" in inner_ct:
                            proto_out = build_sample_binary_steps_response(total_steps=605)
                            self._send_jspb(
                                200,
                                [
                                    base64.b64encode(proto_out).decode("ascii"),
                                    [["content-type", "application/proto"]],
                                ],
                            )
                            return

                        inner_req = json.loads(inner_bytes.decode("utf-8")) if inner_bytes else {}
                        outer_state.record(f"ApiService/ProxyCommand:{inner_method}:req", inner_req)
                        if inner_method == "GetWorkspaceInfos":
                            payload_obj = {
                                "workspaceInfos": [
                                    {
                                        "workspaceFolderAbsoluteUri": "file:///Users/dev/code/ledger-svc",
                                        "gitBranch": "main",
                                    }
                                ]
                            }
                        elif inner_method == "GetAllCascadeTrajectories":
                            payload_obj = {
                                "trajectorySummaries": {
                                    "cas-rate-limiter": {
                                        "summary": "Add rate limiter to /transfers",
                                        "stepCount": 7,
                                        "status": "CASCADE_RUN_STATUS_RUNNING",
                                        "workspaces": [
                                            {"workspaceFolderAbsoluteUri": "file:///Users/dev/code/ledger-svc"}
                                        ],
                                    }
                                }
                            }
                        elif inner_method == "GetUserStatus":
                            payload_obj = {
                                "serverInfo": {"version": "v2.33.0"},
                                "userStatus": {
                                    "name": "Vencial Lee",
                                    "email": "venciallee@gmail.com",
                                    "userTier": {"id": "g1-ultra-tier", "name": "Google AI Ultra"},
                                },
                            }
                        elif inner_method == "StartCascade":
                            # Enforce strict protojson (reject companion-only unknown fields)
                            if "modelId" in inner_req or "initialUserInput" in inner_req:
                                self._send_json(400, {"code": "invalid_argument", "message": 'unknown field "modelId"'})
                                return
                            payload_obj = {"cascadeId": "cas-cloud-relay-01"}
                        elif inner_method == "GetCascadeModelConfigs":
                            payload_obj = {
                                "defaultModel": "MODEL_GOOGLE_GEMINI_4_NEON",
                                "agents": ["Default", "go-reviewer", "release-captain"],
                                "clientModelConfigs": [
                                    {
                                        "label": "Gemini 4 Neon",
                                        "modelOrAlias": {"model": "MODEL_GOOGLE_GEMINI_4_NEON"},
                                        "description": "Flagship coding & reasoning with Low/Medium/High/Extra thinking",
                                        "supportsThinking": True,
                                        "isRecommended": True,
                                        "isNew": True,
                                        "supportedEfforts": ["low", "medium", "high", "xhigh"],
                                    },
                                    {
                                        "label": "Orchestrator (Gemini 4 Neon)",
                                        "modelOrAlias": {"model": "MODEL_ORCHESTRATOR_NEON"},
                                        "description": "Dual-model Planner (Neon) + Executor (Argon)",
                                        "supportsThinking": True,
                                        "isOrchestrator": True,
                                        "plannerModelName": "Gemini 4 Neon",
                                        "executorModelName": "Gemini 4 Argon",
                                        "isNew": True,
                                        "supportedEfforts": ["high"],
                                    },
                                ],
                                "usageQuota": {
                                    "geminiWeeklyRemaining": 0.84,
                                    "geminiFiveHourRemaining": 0.91,
                                    "partnerWeeklyRemaining": 0.68,
                                    "partnerFiveHourRemaining": 0.77,
                                    "aiCreditOveragesEnabled": True,
                                    "planDisplayName": "Google AI Ultra",
                                },
                            }
                        elif inner_method == "GetTurnDiff":
                            compare_mode = inner_req.get("compareMode", "Per Turn")
                            payload_obj = {
                                "compareMode": compare_mode,
                                "files": [
                                    {
                                        "turnNumber": inner_req.get("turnNumber", 3),
                                        "filePath": "middleware/ratelimit.go",
                                        "additions": 2,
                                        "deletions": 1,
                                        "statusLetter": "M",
                                        "isStaged": False,
                                        "compareScope": compare_mode,
                                        "hunkHeader": "@@ -22,4 +22,5 @@ Allow",
                                        "lines": [
                                            {"id": 1, "kind": "context", "oldLineNumber": 22, "newLineNumber": 22, "text": "func (l *Limiter) Allow(tenant string) bool {"},
                                            {"id": 2, "kind": "deletion", "oldLineNumber": 23, "text": "    const ttl = 5 * time.Minute"},
                                            {"id": 3, "kind": "addition", "newLineNumber": 23, "text": "    const ttl = cfg.BucketTTL"},
                                            {"id": 4, "kind": "addition", "newLineNumber": 24, "text": "    now := l.clock.Now()"},
                                        ],
                                    }
                                ],
                            }
                        elif inner_method == "GetArtifactSnapshots":
                            payload_obj = {
                                "artifacts": [
                                    {
                                        "artifactPath": "/brain/implementation_plan.md",
                                        "title": "Rate Limiter Plan",
                                        "summary": "Token bucket per tenant with fake clock injection",
                                        "kind": "implementationPlan",
                                        "content": "---\ntitle: Rate Limiter Plan\n---\n# Rate Limiter Plan\nSee https://github.com/venciallee/iOSAntigravity/pull/42",
                                        "requestFeedback": True,
                                        "version": 2,
                                    },
                                    {
                                        "artifactPath": "/Users/bytedance/.gemini/antigravity/brain/71d80260-b9b2-4f5f-b568-5374f6aebbdd/fig4-verification-pyramid.html",
                                        "title": "Fig 4 · Verification Pyramid",
                                        "kind": "generativeUIHTML",
                                        "content": "<!doctype html><html><body><h3>6-Layer Verification Pyramid</h3></body></html>",
                                    },
                                ]
                            }
                        elif inner_method == "GetConversationOverview":
                            payload_obj = {
                                "reviewAdditions": 128,
                                "reviewDeletions": 14,
                                "modifiedFiles": ["middleware/ratelimit.go"],
                                "subagents": [
                                    {
                                        "subagentId": "sub-bench-1",
                                        "role": "Load Benchmark Runner",
                                        "typeName": "self",
                                        "modelLabel": "Gemini 4 Argon",
                                        "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                                        "summary": "Running vegeta 2000 req/s verification",
                                    }
                                ],
                                "backgroundTasks": [
                                    {
                                        "id": "bg-vegeta-1",
                                        "title": "Vegeta Load Runner",
                                        "commandSummary": "vegeta attack -rate=2000/s",
                                        "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                                        "elapsedLabel": "14s",
                                        "canCancel": True,
                                    }
                                ],
                                "goals": [
                                    {
                                        "id": "goal-1",
                                        "title": "Zero dropped requests at 2,000 req/s",
                                        "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                                        "progressText": "4 of 7 steps",
                                    }
                                ],
                                "pullRequests": [
                                    {
                                        "ownerRepo": "venciallee/iOSAntigravity",
                                        "number": 42,
                                        "title": "feat: per-tenant rate limiter",
                                        "state": "open",
                                        "checksSummary": "4/4 checks passing",
                                        "url": "https://github.com/venciallee/iOSAntigravity/pull/42",
                                        "additions": 128,
                                        "deletions": 14,
                                    }
                                ],
                            }
                        elif inner_method == "SendSideQuestion":
                            q = inner_req.get("question", "")
                            payload_obj = {
                                "ok": True,
                                "threadId": inner_req.get("threadId", "btw-cloud-1"),
                                "answer": f"Cloud Relay /btw answer for '{q}'",
                            }
                        elif inner_method == "GetCustomizationsCatalog":
                            payload_obj = {
                                "skills": [
                                    {"name": "antigravity-doc-sync", "description": "Sync Antigravity 2.0 docs", "scope": "Workspace", "isEnabled": True}
                                ],
                                "rules": [
                                    {"name": "AGENTS.md", "scope": "Workspace", "preview": "Pure Swift 6 & ESDD invariants", "isActive": True}
                                ],
                                "customAgents": ["Default", "go-reviewer"],
                                "mcpServers": [
                                    {"name": "github", "transport": "remote-oauth", "state": "connected", "toolCount": 18, "oauthConnected": True}
                                ],
                                "plugins": [
                                    {"id": "plugin-github", "name": "GitHub", "provider": "GitHub", "description": "PRs, Issues & Actions", "isInstalled": True, "isEnabled": True, "isFeaturedPartner": True, "accountSignedIn": True}
                                ],
                                "hooks": [
                                    {"id": "hook-1", "eventName": "PreToolUse", "matcher": "run_command", "command": "scripts/verify-safe-cmd.sh", "timeoutSeconds": 30, "isValid": True}
                                ],
                            }
                        elif inner_method == "GitCommit":
                            payload_obj = {
                                "ok": True,
                                "commitSha": "e7f8a90",
                                "commitMessage": inner_req.get("message", "Cloud commit"),
                                "branchName": "main",
                                "pushed": False,
                            }
                        elif inner_method == "GitPush":
                            payload_obj = {"ok": True, "pushed": True, "branchName": inner_req.get("branchName", "main")}
                        elif inner_method == "SendUserCascadeMessage":
                            with outer_state.lock:
                                outer_state.messages.append(inner_req)
                            payload_obj = {"ok": True, "turnId": len(outer_state.messages), "echoed": inner_req}
                        elif inner_method == "SearchAllConversations":
                            q = (inner_req.get("query") or "").lower()
                            payload_obj = {
                                "trajectories": [
                                    {
                                        "cascadeId": "cas-rate-limiter",
                                        "title": "Add rate limiter to /transfers",
                                        "projectSlug": "ledger-svc",
                                        "workspaceUri": "file:///Users/dev/code/ledger-svc",
                                        "branchName": "main",
                                        "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                                        "stepCount": 7,
                                        "snippet": f"Cloud matched '{q}'",
                                    }
                                ]
                            }
                        else:
                            payload_obj = {"ok": True, "method": inner_method}

                        encoded_inner = base64.b64encode(json.dumps(payload_obj).encode("utf-8")).decode("ascii")
                        self._send_jspb(
                            200,
                            [
                                encoded_inner,
                                [["accept-encoding", "gzip"], ["content-type", "application/json"]],
                            ],
                        )
                        return

                if not path.startswith(prefix):
                    self._send_json(404, {"error": f"Unknown service path: {path}"})
                    return

                method = path[len(prefix) :]

                if method == "JetboxSubscribeToSummaries":
                    outer_state.record(method, {"framedBytes": len(body)})
                    snapshot = {
                        "host": {"name": "MacBook Pro", "online": True, "version": "v2.30.0"},
                        "summaries": [
                            {
                                "cascadeId": "cas-rate-limiter",
                                "title": "Add rate limiter to /transfers",
                                "project": "ledger-svc",
                                "workspaceUri": "file:///Users/dev/code/ledger-svc",
                                "branchName": "main",
                                "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                                "stepIndex": 4,
                                "stepTotal": 7,
                                "currentCommand": "go test ./internal/...",
                                "isPinned": True,
                                "unread": False,
                                "diffAdditions": 128,
                                "diffDeletions": 14,
                            },
                            {
                                "cascadeId": "cas-release-v23",
                                "title": "Release checklist v2.3",
                                "project": "web-console",
                                "workspaceUri": "cloud://acme/web-console",
                                "branchName": "main",
                                "status": "CORTEX_STEP_STATUS_DONE",
                                "subtitle": "Done · Walkthrough ready",
                                "isPinned": True,
                                "unread": False,
                            },
                            {
                                "cascadeId": "cas-flaky-settlement",
                                "title": "Fix flaky TestSettlementBatch",
                                "project": "ledger-svc",
                                "workspaceUri": "file:///Users/dev/code/ledger-svc",
                                "branchName": "main",
                                "status": "CORTEX_STEP_STATUS_WAITING",
                                "pendingInteractionTitle": "Needs review · Implementation plan ready",
                                "isPinned": False,
                                "unread": True,
                            },
                            {
                                "cascadeId": "cas-go-125",
                                "title": "Upgrade to Go 1.25",
                                "project": "ledger-svc",
                                "workspaceUri": "file:///Users/dev/code/ledger-svc",
                                "branchName": "main",
                                "status": "CORTEX_STEP_STATUS_DONE",
                                "diffAdditions": 42,
                                "diffDeletions": 31,
                                "isPinned": False,
                                "unread": True,
                            },
                            {
                                "cascadeId": "cas-idempotency",
                                "title": "Idempotency keys for payouts",
                                "project": "ledger-svc",
                                "workspaceUri": "file:///Users/dev/code/ledger-svc",
                                "branchName": "main",
                                "status": "CORTEX_STEP_STATUS_DONE",
                                "subtitle": "Done · Merged into main",
                                "isPinned": False,
                                "unread": True,
                            },
                        ],
                    }
                    delta = {
                        "delta": {
                            "cascadeId": "cas-rate-limiter",
                            "stepIndex": 5,
                            "stepTotal": 7,
                            "status": "CORTEX_STEP_STATUS_WAITING",
                            "pendingCommand": "vegeta attack -rate=2000/s -duration=30s",
                        }
                    }
                    stream_bytes = (
                        encode_connect_envelope(
                            json.dumps(snapshot).encode("utf-8"), flags=0x00
                        )
                        + encode_connect_envelope(
                            json.dumps(delta).encode("utf-8"), flags=0x00
                        )
                        + encode_connect_envelope(b"{}", flags=0x02)
                    )
                    self.send_response(200)
                    self._send_cors_headers()
                    self.send_header("Content-Type", "application/connect+json")
                    self.send_header("Content-Length", str(len(stream_bytes)))
                    self.end_headers()
                    self.wfile.write(stream_bytes)
                    return

                if method == "GetCascadeTrajectorySteps":
                    content_type = self.headers.get("Content-Type", "")
                    outer_state.record(method, {"contentType": content_type})
                    if "application/proto" in content_type:
                        proto_bytes = build_sample_binary_steps_response(total_steps=605)
                        self.send_response(200)
                        self._send_cors_headers()
                        self.send_header("Content-Type", "application/proto")
                        self.send_header("Content-Length", str(len(proto_bytes)))
                        self.end_headers()
                        self.wfile.write(proto_bytes)
                    else:
                        self._send_json(200, {"steps": [], "truncatedAt": 600})
                    return

                req = {}
                if body:
                    try:
                        req = json.loads(body.decode("utf-8"))
                    except Exception:
                        req = {}

                if method == "HandleCascadeUserInteraction":
                    interaction = req.get("interaction", {})
                    valid_members = {
                        "permission",
                        "filePermission",
                        "runCommand",
                        "askQuestion",
                        "planReview",
                        "deploy",
                        "executeUrl",
                        "downloadUrl",
                        "browserUpload",
                        "workflowScript",
                        "mcp",
                        "approvalInteraction",
                    }
                    matched = sorted(valid_members.intersection(interaction.keys()))
                    if not matched:
                        self._send_json(
                            400,
                            {
                                "accepted": False,
                                "reason": "Missing authoritative requestedInteraction oneof member",
                            },
                        )
                        return

                    oneof_name = matched[0]
                    faceid_sig = (
                        self.headers.get("X-FaceID-Signature")
                        or interaction.get("faceIdSignature")
                        or ("LAContext-biometric-ok" if interaction.get("biometricConfirmed") else None)
                        or ("LAContext-biometric-ok" if interaction.get("runCommand", {}).get("faceIdVerified") else None)
                    )

                    if oneof_name == "runCommand":
                        rc = interaction["runCommand"]
                        if rc.get("confirm") is True and not faceid_sig:
                            self._send_json(
                                403,
                                {
                                    "accepted": False,
                                    "reason": "Face ID hardware presence signature required for command approval",
                                },
                            )
                            return

                    ack = {
                        "accepted": True,
                        "matchedOneof": oneof_name,
                        "faceIdVerified": bool(faceid_sig),
                        "trajectoryId": interaction.get("trajectoryId", "cas-rate-limiter"),
                        "stepIndex": interaction.get("stepIndex", 5),
                        "newStatus": "CORTEX_STEP_STATUS_RUNNING",
                    }
                    with outer_state.lock:
                        outer_state.interactions.append(ack)
                    outer_state.record(method, req)
                    self._send_json(200, ack)
                    return

                if method == "GetUserStatus":
                    outer_state.record(method, req)
                    self._send_json(
                        200,
                        {
                            "serverInfo": {"version": "v2.33.0"},
                            "userStatus": {
                                "name": "Vencial Lee",
                                "email": "venciallee@gmail.com",
                                "userTier": {"id": "g1-ultra-tier", "name": "Google AI Ultra"},
                            },
                        },
                    )
                    return

                if method == "GetCascadeModelConfigs":
                    outer_state.record(method, req)
                    self._send_json(
                        200,
                        {
                            "clientModelConfigs": [
                                {
                                    "label": "Gemini 4 Neon",
                                    "modelOrAlias": {"model": "MODEL_GOOGLE_GEMINI_4_NEON"},
                                    "description": "Frontier Gemini 4 reasoning with Extra (xhigh) thinking",
                                    "supportsThinking": True,
                                    "isRecommended": True,
                                    "isNew": True,
                                    "supportedEfforts": ["low", "medium", "high", "xhigh"],
                                },
                                {
                                    "label": "Gemini 4 Carbon",
                                    "modelOrAlias": {"model": "MODEL_GOOGLE_GEMINI_4_CARBON"},
                                    "description": "Balanced Gemini 4 daily engineering & research",
                                    "supportsThinking": True,
                                    "isNew": True,
                                    "supportedEfforts": ["low", "medium", "high"],
                                },
                                {
                                    "label": "Gemini 4 Argon",
                                    "modelOrAlias": {"model": "MODEL_GOOGLE_GEMINI_4_ARGON"},
                                    "description": "Ultra-fast Gemini 4 edits & live iterations",
                                    "supportsThinking": True,
                                    "isNew": True,
                                    "supportedEfforts": ["low", "medium", "high"],
                                },
                                {
                                    "label": "Gemini 4 Hydrogen",
                                    "modelOrAlias": {"model": "MODEL_GOOGLE_GEMINI_4_HYDROGEN"},
                                    "description": "Deep scientific & systems reasoning with Extra thinking",
                                    "supportsThinking": True,
                                    "isNew": True,
                                    "supportedEfforts": ["low", "medium", "high", "xhigh"],
                                },
                                {
                                    "label": "Orchestrator (Gemini 4 Neon)",
                                    "modelOrAlias": {"model": "MODEL_ORCHESTRATOR_NEON"},
                                    "description": "Dual-model Planner (Neon) + Executor (Argon)",
                                    "supportsThinking": True,
                                    "isOrchestrator": True,
                                    "plannerModelName": "Gemini 4 Neon",
                                    "executorModelName": "Gemini 4 Argon",
                                    "isNew": True,
                                    "supportedEfforts": ["high"],
                                },
                            ],
                            "usageQuota": {
                                "geminiWeeklyRemaining": 0.84,
                                "geminiFiveHourRemaining": 0.91,
                                "partnerWeeklyRemaining": 0.68,
                                "partnerFiveHourRemaining": 0.77,
                                "aiCreditOveragesEnabled": True,
                                "planDisplayName": "Google AI Ultra",
                            },
                        },
                    )
                    return

                if method == "GetTurnDiff":
                    outer_state.record(method, req)
                    compare_mode = req.get("compareMode", "Per Turn")
                    self._send_json(
                        200,
                        {
                            "compareMode": compare_mode,
                            "files": [
                                {
                                    "turnNumber": req.get("turnNumber", 3),
                                    "filePath": "middleware/ratelimit.go",
                                    "additions": 2,
                                    "deletions": 1,
                                    "statusLetter": "M",
                                    "isStaged": False,
                                    "compareScope": compare_mode,
                                    "hunkHeader": "@@ -22,4 +22,5 @@ Allow",
                                    "lines": [
                                        {"id": 1, "kind": "context", "oldLineNumber": 22, "newLineNumber": 22, "text": "func (l *Limiter) Allow(tenant string) bool {"},
                                        {"id": 2, "kind": "deletion", "oldLineNumber": 23, "text": "    const ttl = 5 * time.Minute"},
                                        {"id": 3, "kind": "addition", "newLineNumber": 23, "text": "    const ttl = cfg.BucketTTL"},
                                        {"id": 4, "kind": "addition", "newLineNumber": 24, "text": "    now := l.clock.Now()"},
                                    ],
                                }
                            ],
                        },
                    )
                    return

                if method in ("GitStageFile", "GitUnstageFile", "GitDiscardFile"):
                    outer_state.record(method, req)
                    self._send_json(200, {"ok": True, "method": method, "filePath": req.get("filePath", "")})
                    return

                if method == "GitCommit":
                    outer_state.record(method, req)
                    self._send_json(
                        200,
                        {
                            "ok": True,
                            "commitSha": "a1b2c3d",
                            "commitMessage": req.get("message", "Update rate limiter"),
                            "branchName": "main",
                            "pushed": False,
                        },
                    )
                    return

                if method == "GitPush":
                    outer_state.record(method, req)
                    self._send_json(200, {"ok": True, "pushed": True, "branchName": req.get("branchName", "main")})
                    return

                if method == "GetArtifactSnapshots":
                    outer_state.record(method, req)
                    sample_ipynb = json.dumps(
                        {
                            "metadata": {"kernelspec": {"display_name": "Python 3.11"}},
                            "cells": [
                                {"id": "c1", "cell_type": "markdown", "source": ["# Benchmark Analysis"]},
                                {
                                    "id": "c2",
                                    "cell_type": "code",
                                    "execution_count": 1,
                                    "source": ["print('p99 = 4.2ms')"],
                                    "outputs": [{"output_type": "stream", "text": ["p99 = 4.2ms\n"]}],
                                },
                            ],
                        }
                    )
                    self._send_json(
                        200,
                        {
                            "artifacts": [
                                {
                                    "artifactPath": "/brain/implementation_plan.md",
                                    "title": "Rate Limiter Plan",
                                    "summary": "Token bucket per tenant with fake clock injection",
                                    "kind": "implementationPlan",
                                    "content": "---\ntitle: Rate Limiter Plan\nversion: 2\n---\n\n# Rate Limiter Plan\n\nInject `clock.Clock` and see https://github.com/venciallee/iOSAntigravity/pull/42",
                                    "requestFeedback": True,
                                    "version": 2,
                                },
                                {
                                    "artifactPath": "/brain/latency_report.ipynb",
                                    "title": "Latency Benchmark Notebook",
                                    "summary": "p99 benchmark notebook",
                                    "kind": "jupyterNotebook",
                                    "content": sample_ipynb,
                                },
                                {
                                    "artifactPath": "/brain/chart_widget.html",
                                    "title": "Throughput Chart",
                                    "summary": "Generative UI chart",
                                    "kind": "generativeUIHTML",
                                    "content": "<html><body style='background:#090A0D;color:#F5F6F8'><h3>2,000 req/s</h3></body></html>",
                                },
                                {
                                    "artifactPath": "/Users/bytedance/.gemini/antigravity/brain/71d80260-b9b2-4f5f-b568-5374f6aebbdd/fig4-verification-pyramid.html",
                                    "title": "Fig 4 · Verification Pyramid",
                                    "summary": "6-Layer Full-Stack Verification Pyramid",
                                    "kind": "generativeUIHTML",
                                    "content": "<!doctype html><html><body style='background:#090A0D;color:#F5F7FA;font-family:-apple-system,sans-serif;padding:16px'><h3 style='margin:0 0 8px;color:#8EB4FF'>6-Layer Verification Pyramid</h3><div style='background:#141519;border:1px solid rgba(255,255,255,0.1);border-radius:10px;padding:10px'>L1–L6 Parity Verified</div></body></html>",
                                },
                            ]
                        },
                    )
                    return

                if method == "GetConversationOverview":
                    outer_state.record(method, req)
                    self._send_json(
                        200,
                        {
                            "reviewAdditions": 128,
                            "reviewDeletions": 14,
                            "modifiedFiles": ["middleware/ratelimit.go", "internal/router/transfers.go"],
                            "subagents": [
                                {
                                    "subagentId": "sub-bench-1",
                                    "role": "Load Benchmark Runner",
                                    "typeName": "self",
                                    "modelLabel": "Gemini 4 Argon",
                                    "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                                    "summary": "Running vegeta 2000 req/s verification",
                                }
                            ],
                            "backgroundTasks": [
                                {
                                    "id": "bg-vegeta-1",
                                    "title": "Vegeta Load Runner",
                                    "commandSummary": "vegeta attack -rate=2000/s",
                                    "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                                    "elapsedLabel": "14s",
                                    "canCancel": True,
                                }
                            ],
                            "goals": [
                                {
                                    "id": "goal-1",
                                    "title": "Zero dropped requests at 2,000 req/s",
                                    "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                                    "progressText": "4 of 7 steps",
                                }
                            ],
                            "pullRequests": [
                                {
                                    "ownerRepo": "venciallee/iOSAntigravity",
                                    "number": 42,
                                    "title": "feat: per-tenant rate limiter",
                                    "state": "open",
                                    "checksSummary": "4/4 checks passing",
                                    "url": "https://github.com/venciallee/iOSAntigravity/pull/42",
                                    "additions": 128,
                                    "deletions": 14,
                                }
                            ],
                        },
                    )
                    return

                if method in ("CancelBackgroundTask", "StopSubagent", "RevertConversationToStep", "SetPermissionPreset"):
                    outer_state.record(method, req)
                    self._send_json(200, {"ok": True, "method": method})
                    return

                if method == "SendSideQuestion":
                    outer_state.record(method, req)
                    q = req.get("question", "")
                    self._send_json(
                        200,
                        {
                            "ok": True,
                            "threadId": req.get("threadId", "btw-1"),
                            "answer": f"Read-only /btw answer: checked token bucket mutex for '{q}' without mutating main context.",
                        },
                    )
                    return

                if method == "GetCustomizationsCatalog":
                    outer_state.record(method, req)
                    self._send_json(
                        200,
                        {
                            "skills": [
                                {"name": "antigravity-doc-sync", "description": "Sync Antigravity 2.0 docs", "scope": "Workspace", "isEnabled": True},
                                {"name": "go-testing", "description": "Table-driven Go tests", "scope": "Workspace", "isEnabled": True},
                            ],
                            "rules": [
                                {"name": "AGENTS.md", "scope": "Workspace", "preview": "Pure Swift 6 & ESDD invariants", "isActive": True}
                            ],
                            "customAgents": ["Default", "go-reviewer", "release-captain"],
                            "mcpServers": [
                                {"name": "github", "transport": "remote-oauth", "state": "connected", "toolCount": 18, "oauthConnected": True},
                                {"name": "postgres-dev", "transport": "stdio", "state": "error", "toolCount": 6, "errorMessage": "Connection refused", "oauthConnected": False},
                            ],
                            "plugins": [
                                {
                                    "id": "plugin-github",
                                    "name": "GitHub",
                                    "provider": "GitHub",
                                    "description": "PRs, Issues & Actions",
                                    "isInstalled": True,
                                    "isEnabled": True,
                                    "isFeaturedPartner": True,
                                    "accountSignedIn": True,
                                },
                                {
                                    "id": "plugin-figma",
                                    "name": "Figma",
                                    "provider": "Figma",
                                    "description": "Inspect design tokens",
                                    "isInstalled": False,
                                    "isEnabled": False,
                                    "isFeaturedPartner": True,
                                    "accountSignedIn": False,
                                },
                            ],
                            "hooks": [
                                {"id": "hook-1", "eventName": "PreToolUse", "matcher": "run_command", "command": "scripts/verify-safe-cmd.sh", "timeoutSeconds": 30, "isValid": True}
                            ],
                        },
                    )
                    return

                if method in ("RestartMcpServer", "TogglePlugin", "InstallPlugin"):
                    outer_state.record(method, req)
                    self._send_json(200, {"ok": True, "method": method})
                    return

                if method == "SearchAllConversations":
                    outer_state.record(method, req)
                    q = (req.get("query") or "").lower()
                    matches = [
                        {
                            "cascadeId": "cas-rate-limiter",
                            "title": "Add rate limiter to /transfers",
                            "projectSlug": "ledger-svc",
                            "workspaceUri": "file:///Users/dev/code/ledger-svc",
                            "branchName": "main",
                            "status": "CORTEX_STEP_STATUS_IN_PROGRESS",
                            "stepCount": 7,
                            "snippet": f"Matched query '{q}' in middleware/ratelimit.go",
                        }
                    ]
                    self._send_json(200, {"trajectories": matches})
                    return

                if method == "CreateProjectWorkspace":
                    runtime = req.get("runtime", "cloud")
                    source_type = req.get("sourceType", "github")
                    repo_name = req.get("repository", "acme/ledger-svc")
                    proj_name = req.get("name") or (
                        f"{repo_name.split('/')[-1]}-cloud"
                        if runtime == "cloud"
                        else repo_name.split("/")[-1]
                    )
                    new_proj = {
                        "id": f"proj-{proj_name}",
                        "name": proj_name,
                        "path": f"cloud://{repo_name}" if runtime == "cloud" else f"~/code/{proj_name}",
                        "runtime": runtime,
                        "sourceType": source_type,
                        "repository": repo_name,
                        "branch": req.get("branch", "main"),
                        "worktree": req.get("worktree", "new"),
                        "googleDriveLinks": req.get("googleDriveLinks", []),
                        "envSetupScript": req.get("envSetupScript", ""),
                        "conversationCount": 0,
                    }
                    with outer_state.lock:
                        outer_state.projects.append(new_proj)
                    outer_state.record(method, req)
                    self._send_json(200, {"ok": True, "project": new_proj})
                    return

                if method == "TriggerAutomationNow":
                    auto_id = req.get("automationId", "auto-nightly-audit")
                    triggered = None
                    with outer_state.lock:
                        for item in outer_state.automations:
                            if item["id"] == auto_id:
                                item["lastRun"] = "Running now · triggered"
                                item["runCount"] = item.get("runCount", 0) + 1
                                triggered = dict(item)
                                break
                    outer_state.record(method, req)
                    self._send_json(
                        200,
                        {
                            "ok": True,
                            "automationId": auto_id,
                            "status": "RUNNING",
                            "automation": triggered,
                        },
                    )
                    return

                if method == "CreateAutomation":
                    prompt = req.get("prompt", "Every weekday at 9, summarize")
                    created = {
                        "id": f"auto-custom-{len(outer_state.automations) + 1}",
                        "title": prompt,
                        "project": req.get("project", "ledger-svc"),
                        "schedule": req.get("schedule", "Weekdays at 09:00"),
                        "model": req.get("model", "Flash"),
                        "state": "scheduled",
                        "nextRun": "Tomorrow, 09:00",
                        "lastRun": "Just created",
                        "runCount": 0,
                    }
                    with outer_state.lock:
                        outer_state.automations.insert(0, created)
                    outer_state.record(method, req)
                    self._send_json(200, {"ok": True, "automation": created})
                    return

                if method == "ResumeAutomation":
                    auto_id = req.get("automationId", "auto-bundle-watch")
                    resumed = None
                    with outer_state.lock:
                        for item in outer_state.automations:
                            if item["id"] == auto_id:
                                item["state"] = "scheduled"
                                item["lastRun"] = "Resumed · Ready"
                                resumed = dict(item)
                                break
                    outer_state.record(method, req)
                    self._send_json(200, {"ok": True, "automation": resumed})
                    return

                if method == "MarkAllConversationsRead":
                    with outer_state.lock:
                        outer_state.unread_count = 0
                    outer_state.record(method, req)
                    self._send_json(200, {"ok": True, "unreadCount": 0})
                    return

                if method == "SendUserCascadeMessage":
                    msg = {
                        "cascadeId": req.get("cascadeId", "cas-rate-limiter"),
                        "text": req.get("text", req.get("userResponse", "")),
                        "items": req.get("items", []),
                        "media": req.get("media", []),
                        "contextChips": req.get("contextChips", []),
                        "mode": req.get("mode", "Planning"),
                        "model": req.get("model", "Gemini 4 Neon"),
                        "modelConfig": req.get("modelConfig", {}),
                        "cascadeConfig": req.get("cascadeConfig", {}),
                    }
                    with outer_state.lock:
                        outer_state.messages.append(msg)
                    outer_state.record(method, req)
                    self._send_json(200, {"ok": True, "turnId": len(outer_state.messages), "message": msg})
                    return

                if method == "SubmitReviewComments":
                    with outer_state.lock:
                        outer_state.reviews.append(req)
                    outer_state.record(method, req)
                    self._send_json(
                        200,
                        {
                            "ok": True,
                            "submittedCount": len(req.get("comments", [])) or 1,
                        },
                    )
                    return

                if method in ("ReadArtifactFile", "GetArtifactSnapshots"):
                    outer_state.record(method, req)
                    sample_html = (
                        "<!doctype html><html><body style='background:#090A0D;color:#F5F7FA;font-family:-apple-system,sans-serif;padding:16px'>"
                        "<h3 style='margin:0 0 8px;color:#8EB4FF'>6-Layer Verification Pyramid</h3>"
                        "<div style='background:#141519;border:1px solid rgba(255,255,255,0.1);border-radius:10px;padding:10px'>L1–L6 Parity Verified</div>"
                        "</body></html>"
                    )
                    if method == "ReadArtifactFile":
                        self._send_json(
                            200,
                            {
                                "ok": True,
                                "mimeType": "text/html",
                                "encoding": "utf-8",
                                "content": sample_html,
                                "sizeBytes": len(sample_html.encode("utf-8")),
                            },
                        )
                    else:
                        self._send_json(
                            200,
                            {
                                "artifacts": [
                                    {
                                        "artifactPath": "/Users/bytedance/.gemini/antigravity/brain/71d80260-b9b2-4f5f-b568-5374f6aebbdd/fig4-verification-pyramid.html",
                                        "title": "Fig 4 · Verification Pyramid",
                                        "content": sample_html,
                                    }
                                ]
                            },
                        )
                    return

                if method == "GetWorkspaceInfos":
                    outer_state.record(method, req)
                    self._send_json(
                        200,
                        {
                            "workspaceInfos": [
                                {
                                    "workspaceUri": "file:///Users/wl/code/ledger-svc",
                                    "displayName": "ledger-svc",
                                    "activeBranch": "main",
                                },
                                {
                                    "workspaceUri": "cloud://acme/web-console",
                                    "displayName": "web-console",
                                    "activeBranch": "main",
                                },
                            ]
                        },
                    )
                    return

                if method.startswith("FutureUnimplemented"):
                    outer_state.record(method, req)
                    self._send_json(
                        501,
                        {
                            "code": "unimplemented",
                            "message": f"unknown method {method}",
                        },
                    )
                    return

                outer_state.record(method, req)
                self._send_json(200, {"ok": True, "method": method})

            def _send_json(self, status: int, data: dict):
                raw = json.dumps(data).encode("utf-8")
                self.send_response(status)
                self._send_cors_headers()
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

        bind_host = getattr(self, "_bind_host", "127.0.0.1")
        bind_port = getattr(self, "_bind_port", 0)
        self.server = _FastThreadingHTTPServer((bind_host, bind_port), Handler)
        self.port = self.server.server_port
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.server.shutdown()
        self.server.server_close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run PocketAntigravity Mock Language Server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--csrf", default="")
    args = parser.parse_args()

    srv = LiveMockServer(host=args.host, port=args.port)
    print(f"MockLanguageServer listening on http://{args.host}:{srv.port}", flush=True)
    try:
        srv.server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server.server_close()
