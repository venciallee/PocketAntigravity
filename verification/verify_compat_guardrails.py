#!/usr/bin/env python3
"""Mechanical Bidirectional Compatibility Static Guardrails (`verify_compat_guardrails.py`).

Prevents compatibility regressions automatically during future feature iterations:
1. RPC Registration Completeness:
   Every Connect-RPC `method: "<Name>"` invoked under `apps/ios/Packages/AntigravityData/Sources/AntigravityData/Protocol/`
   must be registered in `HostCapabilityRegistry.swift` (`coreBaselineMethods`, `legacyAliasMethods`, or `HostCapability.rpcMethods`).
2. Zero Silent `try?` on Live Write RPCs:
   Store code under `apps/ios/Packages/AntigravityData/Sources/AntigravityData/Store/` must never swallow errors from
   mutating RPC calls with `try? await client.<writeMethod>(...)`; use `performLiveCapabilityWrite(...)` or
   `handleLiveCapabilityWriteError(...)` instead.
3. Resilient Forward-Compatible String Enums:
   Every `String`-backed `Codable`/`Decodable` enum in `apps/ios/Packages/AntigravityData/Sources/AntigravityData/Models/`
   must conform to `ResilientStringEnum` or implement a custom fallback `init(from:)`.
4. Swift <-> Companion Bridge Enum-Downgrade Map Parity:
   Every enum downgrade key in `ProtocolCompatibilityEngine.downgradedEnumReplacement` must match
   `BRIDGE_ENUM_DOWNGRADES` in `scripts/mac-companion-bridge.py`.
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

    # --- Guardrail 1: Complete RPC Method Registration ---
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

    # --- Guardrail 4: Swift <-> Bridge Enum Downgrade Parity ---
    swift_downgrades = _parse_swift_enum_downgrades(registry_path)
    bridge_downgrades = _parse_bridge_enum_downgrades(bridge_path)
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

    return {
        "passed": len(errors) == 0,
        "checks": checks,
        "errors": errors,
        "registeredMethodCount": len(registered_methods),
        "usedMethodCount": len(used_methods),
        "resilientEnumCount": resilient_count,
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
