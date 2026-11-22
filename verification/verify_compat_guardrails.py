#!/usr/bin/env python3
"""Mechanical Bidirectional Compatibility Static Guardrails (`verify_compat_guardrails.py`).

Prevents compatibility regressions automatically during future feature iterations:
1. RPC Registration Completeness (Swift + KMP):
   - Every Connect-RPC `method: "<Name>"` invoked under `apps/ios/Packages/AntigravityData/Sources/AntigravityData/Protocol/`
     must be registered in `HostCapabilityRegistry.swift` (`coreBaselineMethods`, `legacyAliasMethods`, or `HostCapability.rpcMethods`).
   - Every Connect-RPC method invoked under `shared/core-protocol/src/*Main/**/*.kt` must be registered in
     `shared/core-protocol/.../HostCapabilityRegistry.kt`.
2. Zero Silent Error Swallowing on Live Write RPCs (Swift + KMP):
   - Store code under `apps/ios/Packages/AntigravityData/Sources/AntigravityData/Store/` must never swallow errors from
     mutating RPC calls with `try? await client.<writeMethod>(...)`; use `performLiveCapabilityWrite(...)` or
     `handleLiveCapabilityWriteError(...)` instead.
   - Domain stores under `shared/core-domain/src/commonMain/**/*.kt` must never swallow mutating RPC calls with
     `runCatching { client.<writeMethod>(...) }`; use `performLiveCapabilityWrite(...)` instead.
3. Resilient Forward-Compatible Enums (Swift + KMP):
   - Every `String`-backed `Codable`/`Decodable` enum in `apps/ios/Packages/AntigravityData/Sources/AntigravityData/Models/`
     must conform to `ResilientStringEnum` or implement a custom fallback `init(from:)`.
   - Every `@Serializable enum class` in `shared/core-model/src/commonMain/**/*.kt` must specify a custom resilient
     serializer via `@Serializable(with = ...)` (unless explicitly allowlisted as non-wire UI-only).
4. Three-Way Enum-Downgrade Map Parity (Swift <-> KMP <-> Companion Bridge):
   - Every enum downgrade key in `HostCapabilityRegistry.swift`, `HostCapabilityRegistry.kt`, and
     `BRIDGE_ENUM_DOWNGRADES` in `scripts/mac-companion-bridge.py` must stay 1:1 in sync.
"""
from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

READ_ONLY_RPC_PREFIXES = (
    "fetch",
    "get",
    "list",
    "search",
    "probe",
    "subscribe",
    "read",
    "load",
    "ping",
    "verify",
    "check",
    "resolve",
    "allCapabilityProfiles",
    "capabilityProfile",
    "selectReachable",
)

KMP_NON_WIRE_ENUM_ALLOWLIST: set[str] = set()


def _extract_swift_block(text: str, anchor: str, stop_marker: str) -> str:
    start = text.find(anchor)
    if start < 0:
        return ""
    end = text.find(stop_marker, start + len(anchor))
    return text[start:end] if end > start else text[start:]


def _parse_registered_rpc_methods(registry_path: Path) -> set[str]:
    text = registry_path.read_text(encoding="utf-8")
    registered: set[str] = set()

    # 1. HostCapability.rpcMethods switch block
    rpc_block = _extract_swift_block(text, "public var rpcMethods: [String]", "public static func capability(forMethod")
    registered.update(re.findall(r'"([A-Z][A-Za-z0-9_]+)"', rpc_block))

    # 2. coreBaselineMethods set
    core_block = _extract_swift_block(text, "public static let coreBaselineMethods: Set<String>", "public static let legacyAliasMethods")
    registered.update(re.findall(r'"([A-Z][A-Za-z0-9_]+)"', core_block))

    # 3. legacyAliasMethods set
    legacy_block = _extract_swift_block(text, "public static let legacyAliasMethods: Set<String>", "public static var allRegisteredMethods")
    registered.update(re.findall(r'"([A-Z][A-Za-z0-9_]+)"', legacy_block))

    return registered


def _parse_kmp_registered_rpc_methods(kt_registry_path: Path) -> set[str]:
    text = kt_registry_path.read_text(encoding="utf-8")
    registered: set[str] = set()

    # 1. HostCapability enum entries: rpcMethods = listOf(...)
    for m in re.finditer(r"rpcMethods\s*=\s*listOf\(([^)]*)\)", text, re.S):
        registered.update(re.findall(r'"([A-Z][A-Za-z0-9_]+)"', m.group(1)))

    # 2. coreBaselineMethods set
    core_match = re.search(r"coreBaselineMethods\s*:\s*Set<String>\s*=\s*setOf\(([^)]*)\)", text, re.S)
    if core_match:
        registered.update(re.findall(r'"([A-Z][A-Za-z0-9_]+)"', core_match.group(1)))

    # 3. legacyAliasMethods set
    legacy_match = re.search(r"legacyAliasMethods\s*:\s*Set<String>\s*=\s*setOf\(([^)]*)\)", text, re.S)
    if legacy_match:
        registered.update(re.findall(r'"([A-Z][A-Za-z0-9_]+)"', legacy_match.group(1)))

    return registered


def _parse_kmp_used_rpc_methods(kmp_protocol_src_root: Path, repo_root: Path) -> dict[str, list[str]]:
    used_methods: dict[str, list[str]] = {}
    patterns = (
        re.compile(r'\bcallUnaryJson\s*\(\s*"([A-Z][A-Za-z0-9_]+)"'),
        re.compile(r'\bsubscribeEnvelopeStream\s*\(\s*"([A-Z][A-Za-z0-9_]+)"'),
        re.compile(r'\bcallCloudRelayProxyCommand\s*\(\s*"([A-Z][A-Za-z0-9_]+)"'),
        re.compile(r'\bmethod\s*=\s*"([A-Z][A-Za-z0-9_]+)"'),
        re.compile(r'\$SERVICE_PREFIX/([A-Z][A-Za-z0-9_]+)'),
    )
    list_loop_re = re.compile(r'for\s*\(\s*method\s+in\s+listOf\s*\(([^)]+)\)')

    for kf in sorted(kmp_protocol_src_root.rglob("*.kt")):
        rel_parts = kf.relative_to(kmp_protocol_src_root).parts
        if rel_parts and "Test" in rel_parts[0]:
            continue
        if kf.name == "HostCapabilityRegistry.kt":
            continue
        for lineno, line in enumerate(kf.read_text(encoding="utf-8").splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
                continue
            loc = f"{kf.relative_to(repo_root)}:{lineno}"
            for pat in patterns:
                for m in pat.finditer(line):
                    used_methods.setdefault(m.group(1), []).append(loc)
            for lm in list_loop_re.finditer(line):
                for method_name in re.findall(r'"([A-Z][A-Za-z0-9_]+)"', lm.group(1)):
                    used_methods.setdefault(method_name, []).append(loc)
    return used_methods


def _parse_swift_enum_downgrades(registry_path: Path) -> dict[str, str]:
    text = registry_path.read_text(encoding="utf-8")
    block = _extract_swift_block(
        text,
        "public static func downgradedEnumReplacement(for invalidValue: String)",
        "public static func recursivelyRemoveField",
    )
    mapping: dict[str, str] = {}
    for line in block.splitlines():
        m = re.search(r'case\s+([^:]+):\s*return\s+"([^"]+)"', line)
        if not m:
            continue
        keys = re.findall(r'"([^"]+)"', m.group(1))
        target = m.group(2)
        for k in keys:
            mapping[k] = target
    return mapping


def _parse_kmp_enum_downgrades(kt_registry_path: Path) -> dict[str, str]:
    text = kt_registry_path.read_text(encoding="utf-8")
    block = _extract_swift_block(
        text,
        "public fun downgradedEnumReplacement(",
        "public fun recursivelyRemoveField(",
    )
    mapping: dict[str, str] = {}
    for line in block.splitlines():
        m = re.search(r'((?:"[^"]+"\s*,?\s*)+)->\s*"([^"]+)"', line)
        if not m:
            continue
        keys = re.findall(r'"([^"]+)"', m.group(1))
        target = m.group(2)
        for k in keys:
            mapping[k] = target
    return mapping


def _parse_bridge_enum_downgrades(bridge_path: Path) -> dict[str, str]:
    tree = ast.parse(bridge_path.read_text(encoding="utf-8"), filename=str(bridge_path))
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "BRIDGE_ENUM_DOWNGRADES":
                    value = ast.literal_eval(node.value)
                    if isinstance(value, dict):
                        return {str(k): str(v) for k, v in value.items()}
    return {}


def inspect_compatibility_guardrails(repo_root: Path = ROOT) -> dict:
    errors: list[str] = []
    checks: list[str] = []

    pkg_src = repo_root / "apps" / "ios" / "Packages" / "AntigravityData" / "Sources" / "AntigravityData"
    protocol_dir = pkg_src / "Protocol"
    store_dir = pkg_src / "Store"
    models_dir = pkg_src / "Models"
    registry_path = protocol_dir / "HostCapabilityRegistry.swift"
    bridge_path = repo_root / "scripts" / "mac-companion-bridge.py"

    kmp_protocol_src = repo_root / "shared" / "core-protocol" / "src"
    kmp_registry_path = (
        kmp_protocol_src / "commonMain" / "kotlin" / "dev" / "antigravity" / "shared" / "protocol" / "HostCapabilityRegistry.kt"
    )
    kmp_model_dir = repo_root / "shared" / "core-model" / "src" / "commonMain"
    kmp_domain_dir = repo_root / "shared" / "core-domain" / "src" / "commonMain"

    # --- Guardrail 1: Complete RPC Method Registration (Swift) ---
    registered_methods = _parse_registered_rpc_methods(registry_path)
    used_methods: dict[str, list[str]] = {}
    for pf in sorted(protocol_dir.glob("*.swift")):
        if pf.name == "HostCapabilityRegistry.swift":
            continue
        for lineno, line in enumerate(pf.read_text(encoding="utf-8").splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for m in re.finditer(r'\bmethod:\s*"([A-Z][A-Za-z0-9_]+)"', line):
                method_name = m.group(1)
                used_methods.setdefault(method_name, []).append(f"{pf.relative_to(repo_root)}:{lineno}")

    unregistered = sorted(set(used_methods.keys()) - registered_methods)
    if unregistered:
        details = [f"{m} ({used_methods[m][0]})" for m in unregistered]
        errors.append(
            "Unregistered Connect-RPC method(s) not declared in HostCapabilityRegistry.swift "
            f"(add to HostCapability.rpcMethods, coreBaselineMethods, or legacyAliasMethods): {details}"
        )
    else:
        checks.append(
            f"RPC registration guardrail passed: all {len(used_methods)} Connect-RPC methods registered in HostCapabilityRegistry.swift"
        )

    # --- Guardrail 1b: Complete RPC Method Registration (KMP) ---
    kmp_registered_methods: set[str] = set()
    kmp_used_methods: dict[str, list[str]] = {}
    if kmp_registry_path.exists():
        kmp_registered_methods = _parse_kmp_registered_rpc_methods(kmp_registry_path)
        kmp_used_methods = _parse_kmp_used_rpc_methods(kmp_protocol_src, repo_root)
        kmp_unregistered = sorted(set(kmp_used_methods.keys()) - kmp_registered_methods)
        if kmp_unregistered:
            details = [f"{m} ({kmp_used_methods[m][0]})" for m in kmp_unregistered]
            errors.append(
                "Unregistered KMP Connect-RPC method(s) not declared in HostCapabilityRegistry.kt "
                f"(add to HostCapability.rpcMethods, coreBaselineMethods, or legacyAliasMethods): {details}"
            )
        else:
            checks.append(
                f"KMP RPC registration guardrail passed: all {len(kmp_used_methods)} Connect-RPC methods registered in HostCapabilityRegistry.kt"
            )
    else:
        errors.append(f"Missing KMP HostCapabilityRegistry.kt at {kmp_registry_path.relative_to(repo_root)}")

    # --- Guardrail 2: Zero Silent `try?` on Live Write RPCs in Store/*.swift ---
    silent_write_hits: list[str] = []
    try_rpc_re = re.compile(r"try\?\s+await\s+(?:self\.)?(?:rpcClient|client|clientRef)\s*\??\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(")
    for sf in sorted(store_dir.glob("*.swift")):
        for lineno, line in enumerate(sf.read_text(encoding="utf-8").splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for m in try_rpc_re.finditer(line):
                fn_name = m.group(1)
                if not fn_name.startswith(READ_ONLY_RPC_PREFIXES):
                    silent_write_hits.append(f"{sf.relative_to(repo_root)}:{lineno} (`try? await ...{fn_name}(...)`)")

    if silent_write_hits:
        errors.append(
            "Silent `try?` detected on mutating RPC call(s) in Store/ (use `performLiveCapabilityWrite` or "
            f"`handleLiveCapabilityWriteError` so older PCs never fake-succeed): {silent_write_hits}"
        )
    else:
        checks.append("Zero silent `try?` mutating RPC calls in AntigravitySessionStore verified")

    # --- Guardrail 2b: Zero Silent `runCatching` on Live Write RPCs in KMP core-domain ---
    kmp_silent_write_hits: list[str] = []
    kmp_runcatching_re = re.compile(
        r"runCatching\s*\{[^}]*\b(?:rpcClient|client|rpc)\s*\??\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\("
    )
    if kmp_domain_dir.exists():
        for df in sorted(kmp_domain_dir.rglob("*.kt")):
            for lineno, line in enumerate(df.read_text(encoding="utf-8").splitlines(), start=1):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
                    continue
                for m in kmp_runcatching_re.finditer(line):
                    fn_name = m.group(1)
                    if not fn_name.startswith(READ_ONLY_RPC_PREFIXES):
                        kmp_silent_write_hits.append(
                            f"{df.relative_to(repo_root)}:{lineno} (`runCatching {{ ...{fn_name}(...) }}`)"
                        )
    if kmp_silent_write_hits:
        errors.append(
            "Silent `runCatching` detected on mutating RPC call(s) in shared/core-domain/ "
            f"(use `performLiveCapabilityWrite` with rollback instead): {kmp_silent_write_hits}"
        )
    else:
        checks.append("Zero silent `runCatching` mutating RPC calls in shared/core-domain/ verified")

    # --- Guardrail 3: 100% Resilient String Codable Enums in Models/*.swift ---
    fragile_enums: list[str] = []
    resilient_count = 0
    enum_decl_re = re.compile(r"public\s+enum\s+([A-Za-z0-9_]+)\s*:\s*String\s*,([^{]+)\{")
    for mf in sorted(models_dir.glob("*.swift")):
        lines = mf.read_text(encoding="utf-8").splitlines()
        for idx, line in enumerate(lines):
            m = enum_decl_re.search(line)
            if not m:
                continue
            enum_name = m.group(1)
            conformances = m.group(2)
            if "ResilientStringEnum" in conformances:
                resilient_count += 1
                continue
            if "Codable" not in conformances and "Decodable" not in conformances:
                continue
            # Scan enum body (brace-balanced) for custom `init(from`
            depth = line.count("{") - line.count("}")
            body_lines = [line]
            j = idx + 1
            while j < len(lines) and depth > 0:
                body_lines.append(lines[j])
                depth += lines[j].count("{") - lines[j].count("}")
                j += 1
            body_text = "\n".join(body_lines)
            if "init(from " in body_text or "init(from:" in body_text:
                resilient_count += 1
            else:
                fragile_enums.append(f"{mf.relative_to(repo_root)}:{idx + 1} (`{enum_name}`)")

    if fragile_enums:
        errors.append(
            "Non-resilient String Codable enum(s) in Models/ will throw DecodingError on future PC enum values "
            f"(conform to `ResilientStringEnum` or implement custom `init(from:)`): {fragile_enums}"
        )
    else:
        checks.append(
            f"Forward-compatible enum guardrail passed: all {resilient_count} String Codable enums in Models/ are resilient"
        )

    # --- Guardrail 3b: 100% Resilient `@Serializable enum class` in shared/core-model/**/*.kt ---
    kmp_fragile_enums: list[str] = []
    kmp_resilient_count = 0
    kt_enum_decl_re = re.compile(r"\benum\s+class\s+([A-Za-z0-9_]+)")
    if kmp_model_dir.exists():
        for mf in sorted(kmp_model_dir.rglob("*.kt")):
            lines = mf.read_text(encoding="utf-8").splitlines()
            for idx, line in enumerate(lines):
                stripped = line.strip()
                if stripped.startswith("//") or stripped.startswith("/*") or stripped.startswith("*"):
                    continue
                m = kt_enum_decl_re.search(line)
                if not m:
                    continue
                enum_name = m.group(1)
                if enum_name in KMP_NON_WIRE_ENUM_ALLOWLIST:
                    continue
                # Inspect contiguous annotation lines immediately above (and on) the enum declaration
                annotation_lines = [line]
                k = idx - 1
                while k >= 0:
                    prev_s = lines[k].strip()
                    if not prev_s or prev_s.startswith("@"):
                        annotation_lines.append(prev_s)
                        k -= 1
                    else:
                        break
                annotation_block = "\n".join(annotation_lines)
                if "@Serializable" not in annotation_block:
                    continue
                if re.search(r"@Serializable\s*\(\s*with\s*=", annotation_block):
                    kmp_resilient_count += 1
                else:
                    kmp_fragile_enums.append(f"{mf.relative_to(repo_root)}:{idx + 1} (`{enum_name}`)")

    if kmp_fragile_enums:
        errors.append(
            "Non-resilient `@Serializable enum class` in shared/core-model/ will throw SerializationException "
            f"on future PC enum values (use `@Serializable(with = ...ResilientEnumSerializer)`): {kmp_fragile_enums}"
        )
    else:
        checks.append(
            f"KMP forward-compatible enum guardrail passed: all {kmp_resilient_count} @Serializable enums in shared/core-model/ use resilient serializers"
        )

    # --- Guardrail 4 + 4b: Swift <-> KMP <-> Companion Bridge Enum Downgrade Parity ---
    swift_downgrades = _parse_swift_enum_downgrades(registry_path)
    bridge_downgrades = _parse_bridge_enum_downgrades(bridge_path)
    kmp_downgrades = _parse_kmp_enum_downgrades(kmp_registry_path) if kmp_registry_path.exists() else {}

    if not swift_downgrades:
        errors.append("Failed to parse downgradedEnumReplacement entries from HostCapabilityRegistry.swift")
    elif swift_downgrades != bridge_downgrades:
        swift_only = sorted(set(swift_downgrades.items()) - set(bridge_downgrades.items()))
        bridge_only = sorted(set(bridge_downgrades.items()) - set(swift_downgrades.items()))
        errors.append(
            f"Swift/Bridge enum downgrade map drift detected: swift_only={swift_only}, bridge_only={bridge_only}"
        )
    else:
        checks.append(
            f"Swift <-> Companion Bridge enum downgrade parity verified ({len(swift_downgrades)} mappings in sync)"
        )

    if not kmp_downgrades:
        errors.append("Failed to parse downgradedEnumReplacement entries from HostCapabilityRegistry.kt")
    elif kmp_downgrades != swift_downgrades or kmp_downgrades != bridge_downgrades:
        kmp_only = sorted(set(kmp_downgrades.items()) - set(swift_downgrades.items()))
        swift_only = sorted(set(swift_downgrades.items()) - set(kmp_downgrades.items()))
        bridge_only = sorted(set(bridge_downgrades.items()) - set(kmp_downgrades.items()))
        errors.append(
            "Three-way Swift/KMP/Bridge enum downgrade map drift detected: "
            f"kmp_only={kmp_only}, swift_only={swift_only}, bridge_only={bridge_only}"
        )
    else:
        checks.append(
            f"Three-way Swift <-> KMP <-> Companion Bridge enum downgrade parity verified ({len(kmp_downgrades)} mappings in sync)"
        )

    return {
        "passed": len(errors) == 0,
        "checks": checks,
        "errors": errors,
        "registeredMethodCount": len(registered_methods),
        "usedMethodCount": len(used_methods),
        "resilientEnumCount": resilient_count,
        "kmpRegisteredMethodCount": len(kmp_registered_methods),
        "kmpUsedMethodCount": len(kmp_used_methods),
        "kmpResilientEnumCount": kmp_resilient_count,
    }


def main() -> int:
    result = inspect_compatibility_guardrails(ROOT)
    print("=== Bidirectional Compatibility Static Guardrails ===")
    for item in result["checks"]:
        print(f"  ✓ {item}")
    for err in result["errors"]:
        print(f"  ✗ {err}", file=sys.stderr)
    if not result["passed"]:
        return 1
    print("ALL COMPATIBILITY STATIC GUARDRAILS PASSED.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
