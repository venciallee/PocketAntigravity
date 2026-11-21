"""Client (iOS / Android / KMP) + Security & Compliance GitHub CR Agent."""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

SEVERITY_RANK: dict[str, int] = {"P0": 0, "P1": 1, "P2": 2}
VALID_SEVERITIES = frozenset(SEVERITY_RANK.keys())
STICKY_MARKER = "<!-- client-sec-cr-agent:summary -->"


@dataclass
class Finding:
    id: str
    rule_id: str
    category: str  # "client" | "security" | "compliance"
    severity: str  # "P0" | "P1" | "P2"
    confidence: float
    source: str  # "static" | "ai" | "hybrid"
    file: str
    line: int
    title: str
    evidence: str
    impact: str
    suggestion: str = ""
    in_diff_hunk: bool = True
    tool: str = "cr-agent"

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class Exemption:
    rule_id: str
    file: str
    line: int
    reason: str
    ticket: str
    requires_security_approval: bool = True

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class RiskBrief:
    risk_level: str  # "LOW" | "MEDIUM" | "HIGH"
    impact_level: str  # "LOW" | "MEDIUM" | "HIGH"
    high_risk_paths_touched: list[str] = field(default_factory=list)
    human_focus_areas: list[str] = field(default_factory=list)
    summary: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class ReviewReport:
    schema_version: str = "1.0"
    pr_number: int = 0
    head_sha: str = ""
    ai_status: str = "not_run"
    ai_provider: str = "none"
    risk_brief: RiskBrief = field(default_factory=lambda: RiskBrief("LOW", "LOW"))
    findings: list[Finding] = field(default_factory=list)
    inline_findings: list[Finding] = field(default_factory=list)
    summary_only_findings: list[Finding] = field(default_factory=list)
    exemptions_detected: list[Exemption] = field(default_factory=list)
    previous_issues_status: list[dict[str, str]] = field(default_factory=list)
    layer1_summary: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "pr_number": self.pr_number,
            "head_sha": self.head_sha,
            "ai_status": self.ai_status,
            "ai_provider": self.ai_provider,
            "risk_brief": self.risk_brief.to_dict(),
            "findings": [f.to_dict() for f in self.findings],
            "inline_findings": [f.to_dict() for f in self.inline_findings],
            "summary_only_findings": [f.to_dict() for f in self.summary_only_findings],
            "exemptions_detected": [e.to_dict() for e in self.exemptions_detected],
            "previous_issues_status": self.previous_issues_status,
            "layer1_summary": self.layer1_summary,
        }
