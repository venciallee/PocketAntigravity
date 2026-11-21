#!/usr/bin/env python3
"""Impact-Scoped E2E Verification Planner & Release Full-E2E Enforcer (`e2e_impact_planner.py`).

Evaluates the exact change set (git diff / PR / push / local working tree) and outputs a
deterministic verification plan:
  - Normal PRs / commits: runs ONLY the gates, Swift tests, XCUITest cases, Simulator UE screens,
    and ESDD interactive test cases impacted by the changed files (skipping unaffected cases).
  - Releases (发版): ALWAYS enforces 100% FULL E2E across all gates (Gate 0..5, all 5 XCUITests,
    Live App Connect-RPC handshake, all 13 Simulator screens, full 16-case / 13-screen ESDD, and
    full KMP verification).
  - Conservative safety fallback: core shared/architecture files, build config, CI runner scripts,
    or unmapped Swift/iOS source files automatically escalate to FULL verification so regressions
    never slip through.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


ALL_XCUITESTS: list[str] = [
    "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
    "testProjectDetailNavigationAndEdgeSwipeBack",
    "testOfflineHostRecoveryAndSettingsAttribution",
    "testAutomationsCreateWithPromptDraftFlow",
    "testComposeFABStartCascadeAndStreamedReply",
]

ALL_UE_STATES: list[str] = [
    "UE01_AGENTS_HOME",
    "UE02_DISPLAY_OPTIONS",
    "UE03_CONTEXT_MENU_PIN",
    "UE04_PROJECT_DETAIL",
    "UE05_CREATE_PROJECT",
    "UE06_AUTOMATIONS",
    "UE07_CHAT_AND_COMPOSER",
    "UE08_ADD_CONTEXT",
    "UE09_MODEL_AND_MODE",
    "UE10_STRUCTURED_QUESTION",
    "UE11_PLAN_REVIEW",
    "UE12_TURN_DIFF_REVIEW",
    "UE13_LIVE_ACTIVITY_SPEC",
]

ALL_ESDD_TCS: list[str] = [f"TC-{i:02d}" for i in range(1, 17)]

RELEASE_LABELS = {"release", "full-e2e", "full-verification"}
VERSION_BUMP_KEYS = (
    "MARKETING_VERSION",
    "CURRENT_PROJECT_VERSION",
    "CFBundleShortVersionString",
    "CFBundleVersion",
)

# Files with app-wide blast radius that automatically escalate to FULL verification.
GLOBAL_FULL_ESCALATION_PATTERNS: list[tuple[str, str]] = [
    ("project.yml", "Xcode project/target/entitlements configuration changed"),
    ("Packages/AntigravityData/Package.swift", "SwiftPM manifest changed"),
    ("iOS/Application/AntigravityApp.swift", "App root entry point changed"),
    ("iOS/Application/DebugSceneFactory.swift", "All 13 --ui-verify scene fixtures registry changed"),
    ("iOS/Navigation/AntigravityShellController.swift", "Root navigation shell, tab capsule, FAB & sheet router changed"),
    ("Shared/DesignSystem/*", "Shared Design System tokens/glass/icons affect all 13 screens"),
    ("Packages/AntigravityData/Sources/AntigravityData/Store/AntigravitySessionStore.swift", "Central session store root state changed"),
    ("Packages/AntigravityData/Sources/AntigravityData/Fixtures/ESDDVerificationFixtures.swift", "Shared ESDD fixtures changed"),
    (".github/workflows/macos-xcode-verify.yml", "macOS E2E CI workflow changed"),
    ("verification/ios-simulator-runner.py", "iOS Simulator E2E runner changed"),
    ("verification/e2e_impact_planner.py", "E2E impact planner changed"),
]


def _empty_impact(domain: str, reason: str) -> dict[str, Any]:
    return {
        "domain": domain,
        "reason": reason,
        "escalate_full": False,
        "gate1_swift_data_tests": False,
        "gate2_live_rpc": False,
        "gate2_v233": False,
        "gate3_ios_build": False,
        "xcuitests": [],
        "run_live_app_rpc": False,
        "simulator_screens": [],
        "esdd_stages": [1],
        "esdd_tcs": [],
        "esdd_screens": [],
        "esdd_full": False,
    }


def classify_file(path: str) -> dict[str, Any]:
    """Maps a repository-relative file path to its conservative E2E blast radius."""
    norm = path.strip().replace("\\", "/")
    if norm.startswith("./"):
        norm = norm[2:]

    # 1. Global core / CI infrastructure -> auto-escalate to full verification
    for pattern, reason in GLOBAL_FULL_ESCALATION_PATTERNS:
        if fnmatch.fnmatch(norm, pattern):
            res = _empty_impact("core-global", reason)
            res["escalate_full"] = True
            return res

    # 2. Pure documentation / legal / repo metadata (zero runtime impact)
    if (
        norm in {"README.md", "AGENTS.md", "NOTICE", "LICENSE", ".gitignore", ".editorconfig"}
        or norm.startswith("docs/")
        or (norm.endswith(".md") and not norm.startswith("specs/"))
    ):
        return _empty_impact("docs-meta", "Documentation or repository metadata only")

    # 3. Specs -> ESDD Stage 1 Spec-DAG & selector parity only
    if norm.startswith("specs/"):
        res = _empty_impact("specs", "ESDD / product specification changed")
        res["esdd_stages"] = [1]
        return res

    # 4. Doc-sync automation & workflow
    if norm in {
        "scripts/sync-antigravity-docs.py",
        "scripts/run-doc-sync-agent.py",
        ".github/workflows/antigravity-doc-sync.yml",
    }:
        res = _empty_impact("doc-sync", "Doc-sync automation script/workflow changed")
        res["gate2_v233"] = True
        return res

    # 5. Companion Bridge / Mock Server / Live RPC & Compat Matrix verifiers (Python backend & protocol harness)
    if norm in {
        "scripts/mac-companion-bridge.py",
        "verification/mock_language_server.py",
        "verification/verify-live-rpc-flow.py",
        "verification/verify-v233-capabilities.py",
        "verification/verify_compat_guardrails.py",
        "verification/verify-compat-matrix.py",
    }:
        res = _empty_impact("python-rpc-bridge", "Connect-RPC companion bridge or protocol mock/verifier changed")
        res["gate2_live_rpc"] = True
        res["gate2_v233"] = True
        res["esdd_stages"] = [1, 2, 3]
        res["esdd_tcs"] = ["TC-15"]
        return res

    # 6. Local ESDD visual/headless verification harness
    if norm in {
        "verification/esdd-verify.py",
        "verification/esdd_inspector.py",
        "verification/ui_renderer.py",
    }:
        res = _empty_impact("esdd-harness", "ESDD headless verification harness changed")
        res["esdd_stages"] = [1, 2, 3, 4]
        res["esdd_tcs"] = list(ALL_ESDD_TCS)
        res["esdd_screens"] = list(ALL_UE_STATES)
        res["esdd_full"] = True
        return res

    # 7. Generated verification outputs / non-iOS helper scripts
    if norm.startswith("verification/output/"):
        return _empty_impact("verification-output", "Verification output artifacts only")

    if norm in {"scripts/install-on-iphone.sh", "scripts/mac-real-env-verify.sh", "scripts/render-brand-icons.py"} or norm.startswith("scripts/assets/"):
        return _empty_impact("helper-scripts", "Developer/local helper script or source SVG asset changed")

    # 8. KMP shared modules & Gradle build (verified by kmp-verify.yml)
    if norm.startswith("shared/umbrella/"):
        res = _empty_impact("kmp-umbrella-facade", "KMP Swift-facing umbrella facade changed (build-only iOS compile check)")
        res["gate3_ios_build"] = True
        return res

    if (
        norm.startswith("shared/")
        or norm.startswith("gradle/")
        or norm in {
            "settings.gradle.kts",
            "build.gradle.kts",
            "gradle.properties",
            "gradlew",
            "gradlew.bat",
            ".github/workflows/kmp-verify.yml",
        }
    ):
        return _empty_impact("kmp-shared", "KMP shared Kotlin/Gradle module (verified by kmp-verify.yml)")

    # 9. Swift unit tests only (App target does not compile SPM test target)
    if norm.startswith("Packages/AntigravityData/Tests/"):
        res = _empty_impact("swift-data-tests", "AntigravityData XCTest unit tests changed")
        res["gate1_swift_data_tests"] = True
        return res

    # 10. Packages/AntigravityData/Sources (pure Swift 6 data/protocol/store layer)
    data_prefix = "Packages/AntigravityData/Sources/AntigravityData/"
    if norm.startswith(data_prefix):
        rel = norm[len(data_prefix):]

        if rel.startswith("Protocol/"):
            res = _empty_impact("data-protocol", "Connect-RPC / Cloud Relay / Protobuf / Capability protocol changed")
            res["gate1_swift_data_tests"] = True
            res["gate2_live_rpc"] = True
            res["gate2_v233"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = [
                "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
                "testOfflineHostRecoveryAndSettingsAttribution",
                "testComposeFABStartCascadeAndStreamedReply",
            ]
            res["run_live_app_rpc"] = True
            res["esdd_stages"] = [1, 2, 3]
            res["esdd_tcs"] = ["TC-08", "TC-15"]
            return res

        if rel == "Models/AntigravityMarkdownParser.swift":
            res = _empty_impact("data-markdown", "Markdown parser changed (verified via swift test + iOS build)")
            res["gate1_swift_data_tests"] = True
            res["gate3_ios_build"] = True
            return res

        if rel == "Models/AutomationAndContextModels.swift":
            res = _empty_impact("data-automations-models", "Automation/context data models changed")
            res["gate1_swift_data_tests"] = True
            res["gate2_v233"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = ["testAutomationsCreateWithPromptDraftFlow"]
            res["esdd_stages"] = [1, 3]
            res["esdd_tcs"] = ["TC-06", "TC-09"]
            return res

        if rel == "Models/WorkspaceModels.swift":
            res = _empty_impact("data-workspace-models", "Workspace/project/host models changed")
            res["gate1_swift_data_tests"] = True
            res["gate2_live_rpc"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = [
                "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
                "testProjectDetailNavigationAndEdgeSwipeBack",
                "testOfflineHostRecoveryAndSettingsAttribution",
            ]
            res["run_live_app_rpc"] = True
            res["esdd_stages"] = [1, 3]
            res["esdd_tcs"] = ["TC-01", "TC-04", "TC-05"]
            return res

        if rel in {"Models/CascadeModels.swift", "Models/InteractionModels.swift"}:
            res = _empty_impact("data-cascade-models", "Cascade step/interaction models changed")
            res["gate1_swift_data_tests"] = True
            res["gate2_live_rpc"] = True
            res["gate2_v233"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = [
                "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
                "testComposeFABStartCascadeAndStreamedReply",
            ]
            res["run_live_app_rpc"] = True
            res["esdd_stages"] = [1, 3]
            res["esdd_tcs"] = ["TC-07", "TC-08", "TC-11", "TC-15"]
            return res

        if rel in {"Models/ArtifactModels.swift", "Models/V233FeatureModels.swift", "Models/SemanticIcon.swift", "Platform/PlatformPorts.swift"}:
            res = _empty_impact("data-models-pure", "Data models/ports changed (verified via swift test + iOS compile)")
            res["gate1_swift_data_tests"] = True
            res["gate2_v233"] = True
            res["gate3_ios_build"] = True
            return res

        if rel in {
            "Store/AntigravitySessionStore+Connection.swift",
            "Store/ConnectionLifecyclePolicy.swift",
            "Store/KeychainStore.swift",
        }:
            res = _empty_impact("store-connection", "Host connection, lifecycle backoff or keychain changed")
            res["gate1_swift_data_tests"] = True
            res["gate2_live_rpc"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = ["testOfflineHostRecoveryAndSettingsAttribution"]
            res["run_live_app_rpc"] = True
            res["esdd_stages"] = [1, 2]
            return res

        if rel in {"Store/AntigravitySessionStore+Sync.swift", "Store/LocalProjectionStore.swift"}:
            res = _empty_impact("store-sync", "Live trajectory sync or local projection store changed")
            res["gate1_swift_data_tests"] = True
            res["gate2_live_rpc"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = [
                "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
                "testOfflineHostRecoveryAndSettingsAttribution",
            ]
            res["run_live_app_rpc"] = True
            res["esdd_stages"] = [1, 2, 3]
            res["esdd_tcs"] = ["TC-01", "TC-02"]
            return res

        if rel == "Store/AntigravitySessionStore+NavigationAndHome.swift":
            res = _empty_impact("store-home-nav", "Agents home filtering/sorting/navigation store changed")
            res["gate1_swift_data_tests"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = [
                "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
                "testProjectDetailNavigationAndEdgeSwipeBack",
            ]
            res["simulator_screens"] = ["UE01_AGENTS_HOME", "UE02_DISPLAY_OPTIONS", "UE03_CONTEXT_MENU_PIN"]
            res["esdd_stages"] = [1, 3, 4]
            res["esdd_tcs"] = ["TC-01", "TC-02", "TC-03"]
            res["esdd_screens"] = ["UE01_AGENTS_HOME", "UE02_DISPLAY_OPTIONS", "UE03_CONTEXT_MENU_PIN"]
            return res

        if rel == "Store/AntigravitySessionStore+ProjectsAndAutomations.swift":
            res = _empty_impact("store-projects-automations", "Projects & Automations store logic changed")
            res["gate1_swift_data_tests"] = True
            res["gate2_live_rpc"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = [
                "testProjectDetailNavigationAndEdgeSwipeBack",
                "testAutomationsCreateWithPromptDraftFlow",
            ]
            res["simulator_screens"] = ["UE04_PROJECT_DETAIL", "UE05_CREATE_PROJECT", "UE06_AUTOMATIONS"]
            res["esdd_stages"] = [1, 2, 3, 4]
            res["esdd_tcs"] = ["TC-04", "TC-05", "TC-06"]
            res["esdd_screens"] = ["UE04_PROJECT_DETAIL", "UE05_CREATE_PROJECT", "UE06_AUTOMATIONS"]
            return res

        if rel == "Store/AntigravitySessionStore+ChatAndInteractions.swift":
            res = _empty_impact("store-chat-interactions", "Chat composer & approval interaction store changed")
            res["gate1_swift_data_tests"] = True
            res["gate2_live_rpc"] = True
            res["gate2_v233"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = [
                "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
                "testComposeFABStartCascadeAndStreamedReply",
            ]
            res["simulator_screens"] = [
                "UE07_CHAT_AND_COMPOSER",
                "UE08_ADD_CONTEXT",
                "UE09_MODEL_AND_MODE",
                "UE10_STRUCTURED_QUESTION",
            ]
            res["esdd_stages"] = [1, 2, 3, 4]
            res["esdd_tcs"] = ["TC-07", "TC-08", "TC-09", "TC-10", "TC-11"]
            res["esdd_screens"] = [
                "UE07_CHAT_AND_COMPOSER",
                "UE08_ADD_CONTEXT",
                "UE09_MODEL_AND_MODE",
                "UE10_STRUCTURED_QUESTION",
            ]
            return res

        if rel == "Store/AntigravitySessionStore+ReviewAndSettings.swift":
            res = _empty_impact("store-review-settings", "Plan/Diff review & Settings store changed")
            res["gate1_swift_data_tests"] = True
            res["gate3_ios_build"] = True
            res["xcuitests"] = ["testOfflineHostRecoveryAndSettingsAttribution"]
            res["simulator_screens"] = ["UE11_PLAN_REVIEW", "UE12_TURN_DIFF_REVIEW"]
            res["esdd_stages"] = [1, 3, 4]
            res["esdd_tcs"] = ["TC-12", "TC-13"]
            res["esdd_screens"] = ["UE11_PLAN_REVIEW", "UE12_TURN_DIFF_REVIEW"]
            return res

        if rel == "Store/SharedAppGroupBridge.swift":
            res = _empty_impact("store-app-group", "App Group Live Activity / Share bridge changed")
            res["gate1_swift_data_tests"] = True
            res["gate3_ios_build"] = True
            res["simulator_screens"] = ["UE13_LIVE_ACTIVITY_SPEC"]
            res["esdd_stages"] = [1, 3, 4]
            res["esdd_tcs"] = ["TC-14"]
            res["esdd_screens"] = ["UE13_LIVE_ACTIVITY_SPEC"]
            return res

        # Unmapped Swift file under AntigravityData -> conservative escalation
        res = _empty_impact("data-unmapped", f"Unmapped AntigravityData source '{norm}' — escalating to full")
        res["escalate_full"] = True
        return res

    # 11. iOS UI ViewControllers, Views, Services & Bridge
    if norm == "iOS/ViewControllers/Home/AgentsHomeViewController.swift":
        res = _empty_impact("ui-home", "Agents Home (UE01) changed")
        res["gate3_ios_build"] = True
        res["xcuitests"] = [
            "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
            "testProjectDetailNavigationAndEdgeSwipeBack",
        ]
        res["simulator_screens"] = ["UE01_AGENTS_HOME"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-01"]
        res["esdd_screens"] = ["UE01_AGENTS_HOME"]
        return res

    if norm == "iOS/ViewControllers/Home/DisplayOptionsSheetView.swift":
        res = _empty_impact("ui-display-options", "Display Options sheet (UE02) changed")
        res["gate3_ios_build"] = True
        res["simulator_screens"] = ["UE02_DISPLAY_OPTIONS"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-02"]
        res["esdd_screens"] = ["UE02_DISPLAY_OPTIONS"]
        return res

    if norm == "iOS/ViewControllers/Home/ConversationContextPreviewMenu.swift":
        res = _empty_impact("ui-context-menu", "Conversation Context Menu (UE03) changed")
        res["gate3_ios_build"] = True
        res["simulator_screens"] = ["UE03_CONTEXT_MENU_PIN"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-03"]
        res["esdd_screens"] = ["UE03_CONTEXT_MENU_PIN"]
        return res

    if norm == "iOS/ViewControllers/Projects/ProjectDetailViewController.swift":
        res = _empty_impact("ui-project-detail", "Project Detail (UE04) changed")
        res["gate3_ios_build"] = True
        res["xcuitests"] = ["testProjectDetailNavigationAndEdgeSwipeBack"]
        res["simulator_screens"] = ["UE04_PROJECT_DETAIL"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-04"]
        res["esdd_screens"] = ["UE04_PROJECT_DETAIL"]
        return res

    if norm == "iOS/ViewControllers/Projects/CreateProjectSheetView.swift":
        res = _empty_impact("ui-create-project", "Create Project sheet (UE05) changed")
        res["gate3_ios_build"] = True
        res["simulator_screens"] = ["UE05_CREATE_PROJECT"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-05"]
        res["esdd_screens"] = ["UE05_CREATE_PROJECT"]
        return res

    if norm == "iOS/ViewControllers/Automations/AutomationsViewController.swift":
        res = _empty_impact("ui-automations", "Automations view (UE06) changed")
        res["gate3_ios_build"] = True
        res["xcuitests"] = ["testAutomationsCreateWithPromptDraftFlow"]
        res["simulator_screens"] = ["UE06_AUTOMATIONS"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-06"]
        res["esdd_screens"] = ["UE06_AUTOMATIONS"]
        return res

    if norm == "iOS/ViewControllers/Cascade/StructuredQuestionCardView.swift":
        res = _empty_impact("ui-structured-question", "Structured Question card (UE10) changed")
        res["gate3_ios_build"] = True
        res["simulator_screens"] = ["UE10_STRUCTURED_QUESTION"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-11"]
        res["esdd_screens"] = ["UE10_STRUCTURED_QUESTION"]
        return res

    if (
        norm in {
            "iOS/ViewControllers/Cascade/CascadeChatViewController.swift",
            "iOS/ViewControllers/Cascade/InteractionGateSheetController.swift",
            "iOS/ViewControllers/Cascade/ConversationOverviewSheetView.swift",
            "iOS/ViewControllers/Cascade/SideQuestionSheetView.swift",
            "iOS/ViewControllers/Cascade/SwarmBoardSheetView.swift",
            "iOS/ViewControllers/Cascade/VoiceModeSheetView.swift",
            "iOS/Services/VoiceInputManager.swift",
        }
        or norm.startswith("iOS/Views/Cascade/")
    ):
        res = _empty_impact("ui-cascade-chat", "Cascade Chat stream, step cards or interaction gate (UE07) changed")
        res["gate3_ios_build"] = True
        res["xcuitests"] = [
            "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
            "testComposeFABStartCascadeAndStreamedReply",
        ]
        res["simulator_screens"] = ["UE07_CHAT_AND_COMPOSER"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-07", "TC-08"]
        res["esdd_screens"] = ["UE07_CHAT_AND_COMPOSER"]
        return res

    if norm in {"iOS/Views/Composer/ChatComposerView.swift", "iOS/Views/Composer/PermissionsSheetView.swift"}:
        res = _empty_impact("ui-composer", "Chat Composer or Permissions sheet (UE07) changed")
        res["gate3_ios_build"] = True
        res["xcuitests"] = [
            "testComposeFABStartCascadeAndStreamedReply",
            "testAutomationsCreateWithPromptDraftFlow",
        ]
        res["simulator_screens"] = ["UE07_CHAT_AND_COMPOSER"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-07", "TC-08"]
        res["esdd_screens"] = ["UE07_CHAT_AND_COMPOSER"]
        return res

    if norm == "iOS/Views/Composer/AddContextSheetView.swift":
        res = _empty_impact("ui-add-context", "Add Context sheet (UE08) changed")
        res["gate3_ios_build"] = True
        res["xcuitests"] = ["testComposeFABStartCascadeAndStreamedReply"]
        res["simulator_screens"] = ["UE08_ADD_CONTEXT"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-09"]
        res["esdd_screens"] = ["UE08_ADD_CONTEXT"]
        return res

    if norm == "iOS/Views/Composer/ModelAndModeSheetView.swift":
        res = _empty_impact("ui-model-mode", "Model & Mode sheet (UE09) changed")
        res["gate3_ios_build"] = True
        res["xcuitests"] = ["testComposeFABStartCascadeAndStreamedReply"]
        res["simulator_screens"] = ["UE09_MODEL_AND_MODE"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-10"]
        res["esdd_screens"] = ["UE09_MODEL_AND_MODE"]
        return res

    if norm in {
        "iOS/ViewControllers/Inspector/ImplementationPlanReviewViewController.swift",
        "iOS/ViewControllers/Inspector/RichArtifactViewerSheet.swift",
    }:
        res = _empty_impact("ui-plan-review", "Implementation Plan & Artifact Review (UE11) changed")
        res["gate3_ios_build"] = True
        res["simulator_screens"] = ["UE11_PLAN_REVIEW"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-12"]
        res["esdd_screens"] = ["UE11_PLAN_REVIEW"]
        return res

    if norm == "iOS/ViewControllers/Inspector/TurnDiffReviewViewController.swift":
        res = _empty_impact("ui-diff-review", "Turn Diff Review (UE12) changed")
        res["gate3_ios_build"] = True
        res["simulator_screens"] = ["UE12_TURN_DIFF_REVIEW"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-13"]
        res["esdd_screens"] = ["UE12_TURN_DIFF_REVIEW"]
        return res

    if norm.startswith("iOS/ViewControllers/Pairing/"):
        res = _empty_impact("ui-pairing-settings", "Pairing, Cloud Relay sign-in & Settings views changed")
        res["gate3_ios_build"] = True
        res["xcuitests"] = ["testOfflineHostRecoveryAndSettingsAttribution"]
        res["run_live_app_rpc"] = True
        return res

    if norm.startswith("iOS/Bridge/"):
        res = _empty_impact("ios-kmp-bridge", "Native iOS <-> KMP shared core bridge changed")
        res["gate1_swift_data_tests"] = True
        res["gate2_live_rpc"] = True
        res["gate3_ios_build"] = True
        res["xcuitests"] = [
            "testHomeCloudLocalBadgesAndChatRealtimeSyncAndApprovalGate",
            "testOfflineHostRecoveryAndSettingsAttribution",
            "testComposeFABStartCascadeAndStreamedReply",
        ]
        res["run_live_app_rpc"] = True
        res["esdd_stages"] = [1, 2]
        return res

    if norm.startswith("iOS/Resources/"):
        res = _empty_impact("ios-resources", "App icons or Asset Catalog changed")
        res["gate3_ios_build"] = True
        res["xcuitests"] = ["testOfflineHostRecoveryAndSettingsAttribution"]
        res["simulator_screens"] = ["UE01_AGENTS_HOME"]
        res["esdd_stages"] = [1, 4]
        res["esdd_screens"] = ["UE01_AGENTS_HOME"]
        return res

    # 12. Extensions & Live Activity
    if (
        norm.startswith("Extensions/LiveActivity/")
        or norm.startswith("Shared/LiveActivity/")
        or norm in {"iOS/Services/LiveActivityCoordinator.swift", "iOS/Services/NotificationCoordinator.swift"}
    ):
        res = _empty_impact("live-activity", "Live Activity / Dynamic Island / Notification (UE13) changed")
        res["gate3_ios_build"] = True
        res["simulator_screens"] = ["UE13_LIVE_ACTIVITY_SPEC"]
        res["esdd_stages"] = [1, 3, 4]
        res["esdd_tcs"] = ["TC-14"]
        res["esdd_screens"] = ["UE13_LIVE_ACTIVITY_SPEC"]
        return res

    if norm.startswith("Extensions/Share/"):
        res = _empty_impact("share-extension", "Share Extension changed (verified via iOS scheme compile)")
        res["gate3_ios_build"] = True
        return res

    # 13. UI Tests harness itself -> run all 5 XCUITests (static 13-screen screenshots unaffected)
    if norm.startswith("iOSUITests/"):
        res = _empty_impact("ios-uitests", "XCUITest suite changed (running all XCUITest cases)")
        res["gate3_ios_build"] = True
        res["xcuitests"] = list(ALL_XCUITESTS)
        return res

    # 14. Conservative fallback for any unmapped file
    res = _empty_impact("unmapped-fallback", f"Unmapped file '{norm}' — escalating to full verification for safety")
    res["escalate_full"] = True
    return res


def detect_release_triggers(
    *,
    force_mode: str = "auto",
    event_name: str = "",
    ref: str = "",
    head_ref: str = "",
    base_ref: str = "",
    labels: list[str] | None = None,
    title_or_commit: str = "",
    version_bump_detected: bool = False,
) -> tuple[bool, list[str]]:
    """Returns (is_release, reasons) indicating whether mandatory FULL Release E2E must run."""
    reasons: list[str] = []
    fm = (force_mode or "auto").strip().lower()
    if fm == "release":
        reasons.append("Explicit release mode requested (`--release` / `verification_mode=release`)")

    ev = (event_name or "").strip().lower()
    if ev == "release":
        reasons.append("GitHub `release` event triggered")

    ref_s = (ref or "").strip()
    if ref_s.startswith("refs/tags/v") or ref_s.startswith("refs/tags/release-") or ref_s.startswith("refs/tags/release/"):
        reasons.append(f"Release Git tag detected (`{ref_s}`)")

    for label_name, rval in (("ref", ref_s), ("head_ref", (head_ref or "").strip()), ("base_ref", (base_ref or "").strip())):
        if rval.startswith("release/") or rval.startswith("refs/heads/release/"):
            reasons.append(f"Release branch detected ({label_name}=`{rval}`)")

    lower_labels = {lbl.strip().lower() for lbl in (labels or []) if lbl.strip()}
    matched_labels = sorted(lower_labels & RELEASE_LABELS)
    if matched_labels:
        reasons.append(f"Release/Full-E2E PR label detected ({', '.join(matched_labels)})")

    text = (title_or_commit or "").strip()
    lower_text = text.lower()
    if (
        "[release]" in lower_text
        or "[full-e2e]" in lower_text
        or re.match(r"^(release|chore\(release\))(\(.+\))?:", lower_text)
    ):
        reasons.append(f"Release/Full-E2E marker in PR title or commit message (`{text[:80]}`)")

    if version_bump_detected:
        reasons.append("App version bump (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`) detected in diff")

    return (len(reasons) > 0), reasons


def detect_version_bump_in_git_diff(
    repo_root: Path,
    base_ref: str | None,
    head_ref: str | None,
    include_working_tree: bool = False,
) -> bool:
    """Checks whether `project.yml` or any `Info.plist` changed a version key in the diff."""
    cmds: list[list[str]] = []
    if base_ref:
        target = f"{base_ref}...{head_ref or 'HEAD'}"
        cmds.append(["git", "diff", "-U0", target, "--", "project.yml", ":(glob)**/Info.plist"])
    if include_working_tree:
        cmds.append(["git", "diff", "-U0", "--", "project.yml", ":(glob)**/Info.plist"])
        cmds.append(["git", "diff", "--cached", "-U0", "--", "project.yml", ":(glob)**/Info.plist"])

    for cmd in cmds:
        try:
            diff_text = subprocess.check_output(
                cmd,
                cwd=repo_root,
                stderr=subprocess.DEVNULL,
                text=True,
            )
        except Exception:
            continue
        for line in diff_text.splitlines():
            if line.startswith(("+", "-")) and not line.startswith(("+++", "---")):
                if any(key in line for key in VERSION_BUMP_KEYS):
                    return True
    return False


def build_verification_plan(
    *,
    changed_files: list[str],
    force_mode: str = "auto",
    event_name: str = "",
    ref: str = "",
    head_ref: str = "",
    base_ref: str = "",
    labels: list[str] | None = None,
    title_or_commit: str = "",
    version_bump_detected: bool = False,
    diff_unavailable: bool = False,
) -> dict[str, Any]:
    """Computes the complete, auditable E2E verification plan."""
    clean_files = sorted({f.strip().replace("\\", "/") for f in changed_files if f and f.strip()})
    fm = (force_mode or "auto").strip().lower()

    is_release, release_reasons = detect_release_triggers(
        force_mode=fm,
        event_name=event_name,
        ref=ref,
        head_ref=head_ref,
        base_ref=base_ref,
        labels=labels,
        title_or_commit=title_or_commit,
        version_bump_detected=version_bump_detected,
    )

    escalation_reasons: list[str] = list(release_reasons)
    mode = "scoped"

    if is_release:
        mode = "release"
    elif fm == "full":
        mode = "full"
        escalation_reasons.append("Explicit full mode requested (`--full` / `verification_mode=full`)")
    elif diff_unavailable:
        mode = "full"
        escalation_reasons.append("Unable to compute git diff base — escalating to full verification for safety")

    file_impacts: list[dict[str, Any]] = []
    domains: set[str] = set()
    gate1 = False
    gate2_live_rpc = False
    gate2_v233 = False
    gate3_ios_build = False
    xcuitests: set[str] = set()
    run_live_app_rpc = False
    simulator_screens: set[str] = set()
    esdd_stages: set[int] = {1}
    esdd_tcs: set[str] = set()
    esdd_screens: set[str] = set()
    esdd_full = False

    for fpath in clean_files:
        imp = classify_file(fpath)
        file_impacts.append({"file": fpath, "domain": imp["domain"], "reason": imp["reason"], "escalateFull": imp["escalate_full"]})
        domains.add(imp["domain"])
        if imp["escalate_full"]:
            escalation_reasons.append(f"{fpath}: {imp['reason']}")
            if mode == "scoped":
                mode = "full"
        gate1 = gate1 or imp["gate1_swift_data_tests"]
        gate2_live_rpc = gate2_live_rpc or imp["gate2_live_rpc"]
        gate2_v233 = gate2_v233 or imp["gate2_v233"]
        gate3_ios_build = gate3_ios_build or imp["gate3_ios_build"]
        xcuitests.update(imp["xcuitests"])
        run_live_app_rpc = run_live_app_rpc or imp["run_live_app_rpc"]
        simulator_screens.update(imp["simulator_screens"])
        esdd_stages.update(imp["esdd_stages"])
        esdd_tcs.update(imp["esdd_tcs"])
        esdd_screens.update(imp["esdd_screens"])
        esdd_full = esdd_full or imp["esdd_full"]

    if mode in ("release", "full"):
        gate1 = True
        gate2_live_rpc = True
        gate2_v233 = True
        gate3_ios_build = True
        ordered_xcuitests = list(ALL_XCUITESTS)
        run_live_app_rpc = True
        ordered_sim_screens = list(ALL_UE_STATES)
        ordered_esdd_stages = [1, 2, 3, 4]
        ordered_esdd_tcs = list(ALL_ESDD_TCS)
        ordered_esdd_screens = list(ALL_UE_STATES)
        esdd_full = True
    else:
        ordered_xcuitests = [t for t in ALL_XCUITESTS if t in xcuitests]
        ordered_sim_screens = [s for s in ALL_UE_STATES if s in simulator_screens]
        ordered_esdd_stages = sorted(esdd_stages)
        ordered_esdd_tcs = [tc for tc in ALL_ESDD_TCS if tc in esdd_tcs]
        ordered_esdd_screens = [s for s in ALL_UE_STATES if s in esdd_screens]
        if ordered_esdd_tcs and 3 not in ordered_esdd_stages:
            ordered_esdd_stages = sorted(set(ordered_esdd_stages) | {3})
        if ordered_esdd_screens and 4 not in ordered_esdd_stages:
            ordered_esdd_stages = sorted(set(ordered_esdd_stages) | {4})

    if not gate3_ios_build:
        ios_simulator_mode = "skip"
    elif mode in ("release", "full"):
        ios_simulator_mode = "full"
    elif not ordered_xcuitests and not run_live_app_rpc and not ordered_sim_screens:
        ios_simulator_mode = "build-only"
    else:
        ios_simulator_mode = "scoped"

    needs_macos = bool(gate1 or gate3_ios_build)
    skipped_xcuitests = [t for t in ALL_XCUITESTS if t not in ordered_xcuitests]
    skipped_sim_screens = [s for s in ALL_UE_STATES if s not in ordered_sim_screens]

    return {
        "mode": mode,
        "isRelease": is_release,
        "escalationReasons": escalation_reasons,
        "changedFiles": clean_files,
        "impactedDomains": sorted(domains),
        "fileImpacts": file_impacts,
        "gates": {
            "gate0DocSync": True,
            "gate1SwiftDataTests": gate1,
            "gate2LiveRPC": gate2_live_rpc,
            "gate2V233Capabilities": gate2_v233,
            "gate3IOSBuild": gate3_ios_build,
            "iosSimulatorMode": ios_simulator_mode,
            "runLiveAppRPC": run_live_app_rpc,
            "needsMacOS": needs_macos,
            "runKmpFullRelease": is_release,
        },
        "xcuitests": ordered_xcuitests,
        "skippedXcuitests": skipped_xcuitests,
        "simulatorScreens": ordered_sim_screens,
        "skippedSimulatorScreens": skipped_sim_screens,
        "esdd": {
            "full": esdd_full,
            "stages": ordered_esdd_stages,
            "testCases": ordered_esdd_tcs,
            "screens": ordered_esdd_screens,
        },
    }


def render_markdown_summary(plan: dict[str, Any]) -> str:
    mode = plan["mode"]
    is_release = plan["isRelease"]
    gates = plan["gates"]

    if is_release:
        badge = "🚀 FULL RELEASE E2E (Mandatory 100% Verification)"
    elif mode == "full":
        badge = "🛡️ FULL E2E (Core/Global Blast Radius Escalation)"
    else:
        badge = "🎯 IMPACT-SCOPED E2E (Unaffected Cases Skipped)"

    lines = [
        f"## E2E Verification Plan — {badge}",
        "",
        f"- **Mode**: `{mode}` (`isRelease={is_release}`)",
        f"- **Changed Files**: `{len(plan['changedFiles'])}`",
        f"- **Impacted Domains**: `{', '.join(plan['impactedDomains']) or 'none'}`",
        f"- **macOS Runner Required**: `{'YES' if gates['needsMacOS'] else 'NO (fast Ubuntu-only verification)'}`",
        f"- **iOS Simulator Mode**: `{gates['iosSimulatorMode']}`",
    ]
    if plan["escalationReasons"]:
        lines.append("- **Full/Release Escalation Reasons**:")
        for r in plan["escalationReasons"]:
            lines.append(f"  - {r}")

    lines.extend(
        [
            "",
            "### Gate Execution Matrix",
            "",
            "| Gate | Action | Detail |",
            "| :--- | :--- | :--- |",
            f"| `[Gate 0]` Script Syntax & Doc-Sync Self-Test | ✅ RUN | Always runs (~1s on Ubuntu) |",
            f"| `[Gate 1]` Swift 6 `AntigravityData` XCTests | {'✅ RUN' if gates['gate1SwiftDataTests'] else '⏭️ SKIP'} | {'Packages/AntigravityData impacted or full' if gates['gate1SwiftDataTests'] else 'Packages/AntigravityData untouched'} |",
            f"| `[Gate 2]` Live Connect-RPC + v2.33 Capabilities | {'✅ RUN' if (gates['gate2LiveRPC'] or gates['gate2V233Capabilities']) else '⏭️ SKIP'} | LiveRPC=`{gates['gate2LiveRPC']}`, v2.33=`{gates['gate2V233Capabilities']}` |",
            f"| `[Gate 3]` Xcode iOS Build (`Antigravity.app`) | {'✅ RUN' if gates['gate3IOSBuild'] else '⏭️ SKIP'} | Mode=`{gates['iosSimulatorMode']}` |",
            f"| `[Gate 3b]` Real Simulator XCUITests | {'✅ RUN (' + str(len(plan['xcuitests'])) + '/' + str(len(ALL_XCUITESTS)) + ')' if plan['xcuitests'] else '⏭️ SKIP (0/' + str(len(ALL_XCUITESTS)) + ')'} | {', '.join(f'`{t}`' for t in plan['xcuitests']) or 'None impacted'} |",
            f"| `[Gate 4]` Live Simulator App Connect-RPC Handshake | {'✅ RUN' if gates['runLiveAppRPC'] else '⏭️ SKIP'} | {'Connection/RPC impacted or full' if gates['runLiveAppRPC'] else 'Unaffected'} |",
            f"| `[Gate 5]` Native Simulator UE Screenshots | {'✅ RUN (' + str(len(plan['simulatorScreens'])) + '/13)' if plan['simulatorScreens'] else '⏭️ SKIP (0/13)'} | {', '.join(f'`{s}`' for s in plan['simulatorScreens']) or 'None impacted'} |",
            f"| `[Release]` Full KMP JVM + XCFramework E2E | {'✅ RUN' if gates['runKmpFullRelease'] else '⏭️ SKIP'} | {'Enforced on release' if gates['runKmpFullRelease'] else 'Handled by kmp-verify.yml when shared/ changes'} |",
            "",
        ]
    )

    if plan["fileImpacts"]:
        lines.extend(
            [
                "### Changed File → Impact Mapping",
                "",
                "| File | Domain | Rationale |",
                "| :--- | :--- | :--- |",
            ]
        )
        for item in plan["fileImpacts"][:40]:
            lines.append(f"| `{item['file']}` | `{item['domain']}` | {item['reason']} |")
        if len(plan["fileImpacts"]) > 40:
            lines.append(f"| *...and {len(plan['fileImpacts']) - 40} more files* | — | — |")
        lines.append("")

    return "\n".join(lines)


def _git_diff_files(repo_root: Path, base_ref: str, head_ref: str) -> list[str] | None:
    try:
        out = subprocess.check_output(
            ["git", "diff", "--name-only", f"{base_ref}...{head_ref}"],
            cwd=repo_root,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        return [line.strip() for line in out.splitlines() if line.strip()]
    except Exception:
        try:
            out = subprocess.check_output(
                ["git", "diff", "--name-only", base_ref, head_ref],
                cwd=repo_root,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            return [line.strip() for line in out.splitlines() if line.strip()]
        except Exception:
            return None


def _git_working_tree_files(repo_root: Path) -> list[str]:
    files: set[str] = set()
    for cmd in (
        ["git", "diff", "--name-only"],
        ["git", "diff", "--cached", "--name-only"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ):
        try:
            out = subprocess.check_output(cmd, cwd=repo_root, stderr=subprocess.DEVNULL, text=True)
            for line in out.splitlines():
                if line.strip():
                    files.add(line.strip())
        except Exception:
            pass
    return sorted(files)


def _read_github_context(repo_root: Path) -> dict[str, Any]:
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    ref = os.environ.get("GITHUB_REF", "")
    head_ref = os.environ.get("GITHUB_HEAD_REF", "")
    base_ref = os.environ.get("GITHUB_BASE_REF", "")
    sha = os.environ.get("GITHUB_SHA", "HEAD")
    event_path = os.environ.get("GITHUB_EVENT_PATH", "")

    labels: list[str] = []
    title_or_commit = ""
    diff_base: str | None = None
    diff_head: str = sha or "HEAD"

    payload: dict[str, Any] = {}
    if event_path and Path(event_path).exists():
        try:
            payload = json.loads(Path(event_path).read_text(encoding="utf-8"))
        except Exception:
            payload = {}

    if event_name == "pull_request" and "pull_request" in payload:
        pr = payload["pull_request"]
        labels = [l.get("name", "") for l in pr.get("labels", []) if isinstance(l, dict)]
        title_or_commit = pr.get("title", "") or ""
        pr_base_sha = (pr.get("base") or {}).get("sha")
        if pr_base_sha:
            diff_base = pr_base_sha
        elif base_ref:
            diff_base = f"origin/{base_ref}"
    elif event_name == "push":
        before = payload.get("before", "")
        if before and before != "0" * 40:
            diff_base = before
        else:
            diff_base = "HEAD~1"
        head_commit = payload.get("head_commit") or {}
        title_or_commit = (head_commit.get("message") or "").splitlines()[0] if head_commit.get("message") else ""
    elif event_name == "workflow_dispatch":
        inputs = payload.get("inputs") or {}
        title_or_commit = f"workflow_dispatch({inputs.get('verification_mode', 'full')})"
        diff_base = "HEAD~1"

    if not title_or_commit:
        try:
            title_or_commit = subprocess.check_output(
                ["git", "log", "-1", "--pretty=%s"],
                cwd=repo_root,
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
        except Exception:
            title_or_commit = ""

    return {
        "event_name": event_name,
        "ref": ref,
        "head_ref": head_ref,
        "base_ref": base_ref,
        "labels": labels,
        "title_or_commit": title_or_commit,
        "diff_base": diff_base,
        "diff_head": diff_head,
    }


def write_github_outputs(github_output_path: Path, plan: dict[str, Any]) -> None:
    gates = plan["gates"]
    esdd = plan["esdd"]
    browser_tcs = [tc for tc in esdd.get("testCases", []) if tc not in ("TC-15", "TC-16")]
    esdd_needs_browser = bool(esdd.get("full") or browser_tcs or esdd.get("screens"))
    kv = {
        "mode": plan["mode"],
        "is_release": "true" if plan["isRelease"] else "false",
        "needs_macos": "true" if gates["needsMacOS"] else "false",
        "run_gate0": "true" if gates["gate0DocSync"] else "false",
        "run_gate1": "true" if gates["gate1SwiftDataTests"] else "false",
        "run_gate2_live_rpc": "true" if gates["gate2LiveRPC"] else "false",
        "run_gate2_v233": "true" if gates["gate2V233Capabilities"] else "false",
        "run_gate3_ios_build": "true" if gates["gate3IOSBuild"] else "false",
        "ios_simulator_mode": gates["iosSimulatorMode"],
        "run_live_app_rpc": "true" if gates["runLiveAppRPC"] else "false",
        "run_kmp_full_release": "true" if gates["runKmpFullRelease"] else "false",
        "esdd_full": "true" if esdd["full"] else "false",
        "esdd_needs_browser": "true" if esdd_needs_browser else "false",
        "xcuitests_csv": ",".join(plan["xcuitests"]),
        "simulator_screens_csv": ",".join(plan["simulatorScreens"]),
        "changed_file_count": str(len(plan["changedFiles"])),
    }
    with github_output_path.open("a", encoding="utf-8") as fp:
        for k, v in kv.items():
            fp.write(f"{k}={v}\n")


def run_self_tests() -> None:
    """Comprehensive deterministic self-test verifying scoped impact mapping and release enforcement."""
    # 1. Docs-only -> fast Ubuntu only, zero macOS runner
    p1 = build_verification_plan(changed_files=["AGENTS.md", "README.md", "docs/images/architecture-dark.svg"])
    assert p1["mode"] == "scoped" and not p1["isRelease"]
    assert p1["gates"]["needsMacOS"] is False
    assert p1["gates"]["gate1SwiftDataTests"] is False
    assert p1["gates"]["gate2LiveRPC"] is False
    assert p1["gates"]["iosSimulatorMode"] == "skip"

    # 2. Companion Bridge / Mock Server only -> Gate 0 + Gate 2 only, no macOS
    p2 = build_verification_plan(changed_files=["scripts/mac-companion-bridge.py"])
    assert p2["mode"] == "scoped"
    assert p2["gates"]["needsMacOS"] is False
    assert p2["gates"]["gate2LiveRPC"] is True and p2["gates"]["gate2V233Capabilities"] is True
    assert p2["gates"]["iosSimulatorMode"] == "skip"

    # 3. Swift XCTests only -> Gate 1 only, skip Xcode/Simulator completely
    p3 = build_verification_plan(changed_files=["Packages/AntigravityData/Tests/AntigravityDataTests/AntigravityProtocolTests.swift"])
    assert p3["mode"] == "scoped"
    assert p3["gates"]["needsMacOS"] is True
    assert p3["gates"]["gate1SwiftDataTests"] is True
    assert p3["gates"]["gate3IOSBuild"] is False
    assert p3["gates"]["iosSimulatorMode"] == "skip"

    # 4. Pure Markdown parser -> Gate 1 + build-only (zero simulator boot!)
    p4 = build_verification_plan(changed_files=["Packages/AntigravityData/Sources/AntigravityData/Models/AntigravityMarkdownParser.swift"])
    assert p4["mode"] == "scoped"
    assert p4["gates"]["gate1SwiftDataTests"] is True
    assert p4["gates"]["iosSimulatorMode"] == "build-only"
    assert p4["xcuitests"] == [] and p4["simulatorScreens"] == []

    # 5. Single UI screen (Automations) -> ONLY Automations XCUITest + UE06 screen!
    p5 = build_verification_plan(changed_files=["iOS/ViewControllers/Automations/AutomationsViewController.swift"])
    assert p5["mode"] == "scoped"
    assert p5["gates"]["gate1SwiftDataTests"] is False
    assert p5["gates"]["gate2LiveRPC"] is False
    assert p5["gates"]["iosSimulatorMode"] == "scoped"
    assert p5["xcuitests"] == ["testAutomationsCreateWithPromptDraftFlow"]
    assert p5["simulatorScreens"] == ["UE06_AUTOMATIONS"]
    assert p5["gates"]["runLiveAppRPC"] is False
    assert p5["esdd"]["testCases"] == ["TC-06"]
    assert p5["esdd"]["screens"] == ["UE06_AUTOMATIONS"]

    # 6. TurnDiffReview only -> build + UE12 screenshot only, zero XCUITests!
    p6 = build_verification_plan(changed_files=["iOS/ViewControllers/Inspector/TurnDiffReviewViewController.swift"])
    assert p6["mode"] == "scoped"
    assert p6["gates"]["iosSimulatorMode"] == "scoped"
    assert p6["xcuitests"] == []
    assert p6["simulatorScreens"] == ["UE12_TURN_DIFF_REVIEW"]

    # 7. Live Activity widget only -> build + UE13 screenshot only
    p7 = build_verification_plan(changed_files=["Extensions/LiveActivity/AntigravityLiveActivityWidget.swift"])
    assert p7["mode"] == "scoped"
    assert p7["xcuitests"] == []
    assert p7["simulatorScreens"] == ["UE13_LIVE_ACTIVITY_SPEC"]

    # 8. Share extension only -> build-only, zero simulator boot
    p8 = build_verification_plan(changed_files=["Extensions/Share/AntigravityShareViewController.swift"])
    assert p8["mode"] == "scoped"
    assert p8["gates"]["iosSimulatorMode"] == "build-only"

    # 9. KMP shared only -> skipped by macOS workflow (verified by kmp-verify.yml); umbrella facade -> build-only
    p9 = build_verification_plan(changed_files=["shared/core-model/src/commonMain/kotlin/dev/antigravity/shared/model/CascadeModels.kt"])
    assert p9["mode"] == "scoped"
    assert p9["gates"]["needsMacOS"] is False
    p9b = build_verification_plan(changed_files=["shared/umbrella/src/commonMain/kotlin/dev/antigravity/shared/AntigravitySharedFacade.kt"])
    assert p9b["mode"] == "scoped"
    assert p9b["gates"]["iosSimulatorMode"] == "build-only"

    # 10. Multi-file union (Automations + Project Detail)
    p10 = build_verification_plan(
        changed_files=[
            "iOS/ViewControllers/Automations/AutomationsViewController.swift",
            "iOS/ViewControllers/Projects/ProjectDetailViewController.swift",
        ]
    )
    assert p10["mode"] == "scoped"
    assert p10["xcuitests"] == [
        "testProjectDetailNavigationAndEdgeSwipeBack",
        "testAutomationsCreateWithPromptDraftFlow",
    ]
    assert p10["simulatorScreens"] == ["UE04_PROJECT_DETAIL", "UE06_AUTOMATIONS"]

    # 11. Core global file -> auto-escalated to full
    p11 = build_verification_plan(changed_files=["Shared/DesignSystem/AntigravityTheme.swift"])
    assert p11["mode"] == "full" and not p11["isRelease"]
    assert p11["xcuitests"] == ALL_XCUITESTS
    assert p11["simulatorScreens"] == ALL_UE_STATES

    # 12. Unmapped new Swift file -> conservative escalation to full
    p12 = build_verification_plan(changed_files=["iOS/NewExperimental/FutureFeature.swift"])
    assert p12["mode"] == "full"
    assert p12["xcuitests"] == ALL_XCUITESTS

    # 13. Release triggers (tag, release branch, GitHub release event, label, commit marker, version bump)
    release_cases = [
        {"changed_files": ["README.md"], "ref": "refs/tags/v2.1.0"},
        {"changed_files": ["README.md"], "ref": "refs/heads/release/2.1.0"},
        {"changed_files": ["README.md"], "event_name": "release"},
        {"changed_files": ["README.md"], "labels": ["release"]},
        {"changed_files": ["README.md"], "title_or_commit": "chore(release): cut v2.1.0"},
        {"changed_files": ["README.md"], "title_or_commit": "fix(ui): polish [full-e2e]"},
        {"changed_files": ["README.md"], "version_bump_detected": True},
        {"changed_files": ["README.md"], "force_mode": "release"},
    ]
    for idx, kwargs in enumerate(release_cases, start=1):
        pr = build_verification_plan(**kwargs)
        assert pr["mode"] == "release" and pr["isRelease"] is True, f"Release case #{idx} failed: {pr}"
        assert pr["gates"]["needsMacOS"] is True
        assert pr["gates"]["gate1SwiftDataTests"] is True
        assert pr["gates"]["gate2LiveRPC"] is True
        assert pr["gates"]["gate2V233Capabilities"] is True
        assert pr["gates"]["iosSimulatorMode"] == "full"
        assert pr["gates"]["runLiveAppRPC"] is True
        assert pr["gates"]["runKmpFullRelease"] is True
        assert pr["xcuitests"] == ALL_XCUITESTS
        assert pr["simulatorScreens"] == ALL_UE_STATES
        assert pr["esdd"]["full"] is True
        assert pr["esdd"]["testCases"] == ALL_ESDD_TCS
        assert pr["esdd"]["screens"] == ALL_UE_STATES

    # 14. Verify ALL_XCUITESTS matches AntigravityInteractiveUITests.swift method names 1:1
    repo_root = Path(__file__).resolve().parents[1]
    uitest_swift = repo_root / "iOSUITests" / "AntigravityInteractiveUITests.swift"
    if uitest_swift.exists():
        swift_methods = re.findall(r"func\s+(test\w+)\s*\(\)", uitest_swift.read_text(encoding="utf-8"))
        assert swift_methods == ALL_XCUITESTS, (
            f"ALL_XCUITESTS drift detected!\n  Swift:   {swift_methods}\n  Planner: {ALL_XCUITESTS}"
        )

    print("✓ e2e_impact_planner self-test PASSED (14/14 scenarios + 8/8 release triggers + XCUITest parity verified)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Impact-Scoped E2E Planner & Release Full-E2E Enforcer")
    parser.add_argument("--self-test", action="store_true", help="Run built-in unit self-tests")
    parser.add_argument("--mode", choices=["auto", "full", "release"], default=os.environ.get("ANTIGRAVITY_E2E_MODE", "auto"))
    parser.add_argument("--release", action="store_true", help="Shorthand for --mode release")
    parser.add_argument("--full", action="store_true", help="Shorthand for --mode full")
    parser.add_argument("--base", default=None, help="Git base ref/SHA for diff")
    parser.add_argument("--head", default=None, help="Git head ref/SHA for diff")
    parser.add_argument("--include-working-tree", action="store_true", help="Include uncommitted local changes")
    parser.add_argument("--changed-files", nargs="*", default=None, help="Explicit list of changed files (overrides git diff)")
    parser.add_argument("--plan-out", default=None, help="Write JSON verification plan to path")
    parser.add_argument("--markdown-out", default=None, help="Write Markdown summary to path")
    parser.add_argument("--github-output", default=None, help="Append key=value outputs to GITHUB_OUTPUT")
    parser.add_argument("--github-step-summary", default=None, help="Append Markdown summary to GITHUB_STEP_SUMMARY")
    parser.add_argument("--quiet", action="store_true", help="Do not print plan JSON to stdout")
    args = parser.parse_args()

    if args.self_test:
        run_self_tests()
        return 0

    repo_root = Path(__file__).resolve().parents[1]
    force_mode = "release" if args.release else ("full" if args.full else args.mode)
    gh = _read_github_context(repo_root)

    # On manual workflow_dispatch, respect verification_mode input if provided via env
    wf_input_mode = os.environ.get("VERIFICATION_MODE_INPUT", "").strip().lower()
    if wf_input_mode in ("auto", "full", "release") and force_mode == "auto":
        force_mode = wf_input_mode

    diff_base = args.base or gh["diff_base"]
    diff_head = args.head or gh["diff_head"]
    diff_unavailable = False
    version_bump = False

    if args.changed_files is not None:
        changed_files = list(args.changed_files)
    else:
        if not diff_base:
            # Local invocation fallback: diff against origin/main if present, else HEAD~1
            for candidate in ("origin/main", "main", "HEAD~1"):
                try:
                    subprocess.check_output(["git", "rev-parse", "--verify", candidate], cwd=repo_root, stderr=subprocess.DEVNULL)
                    diff_base = candidate
                    break
                except Exception:
                    continue
        if diff_base:
            diff_files = _git_diff_files(repo_root, diff_base, diff_head)
            if diff_files is None:
                diff_unavailable = True
                changed_files = []
            else:
                changed_files = diff_files
                version_bump = detect_version_bump_in_git_diff(
                    repo_root,
                    diff_base,
                    diff_head,
                    include_working_tree=args.include_working_tree,
                )
        else:
            diff_unavailable = True
            changed_files = []

        if args.include_working_tree:
            changed_files = sorted(set(changed_files) | set(_git_working_tree_files(repo_root)))

    plan = build_verification_plan(
        changed_files=changed_files,
        force_mode=force_mode,
        event_name=gh["event_name"],
        ref=gh["ref"],
        head_ref=gh["head_ref"],
        base_ref=gh["base_ref"],
        labels=gh["labels"],
        title_or_commit=gh["title_or_commit"],
        version_bump_detected=version_bump,
        diff_unavailable=diff_unavailable and force_mode == "auto" and not changed_files,
    )

    md = render_markdown_summary(plan)

    if args.plan_out:
        out_p = Path(args.plan_out)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        out_p.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")

    if args.markdown_out:
        md_p = Path(args.markdown_out)
        md_p.parent.mkdir(parents=True, exist_ok=True)
        md_p.write_text(md + "\n", encoding="utf-8")

    if args.github_output:
        write_github_outputs(Path(args.github_output), plan)

    if args.github_step_summary:
        with Path(args.github_step_summary).open("a", encoding="utf-8") as fp:
            fp.write(md + "\n")

    if not args.quiet:
        print(md)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
