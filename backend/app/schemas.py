from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class RulePayload(BaseModel):
    id: str
    level: int
    description: str


class AgentPayload(BaseModel):
    id: str
    name: str


class DataPayload(BaseModel):
    srcip: str | None = None


class AlertIngestPayload(BaseModel):
    model_config = ConfigDict(extra="allow")

    rule: RulePayload
    agent: AgentPayload
    data: DataPayload = Field(default_factory=DataPayload)
    full_log: str
    timestamp: datetime
    scenario_type: str | None = None


class IncidentWindowPayload(BaseModel):
    alerts: list[AlertIngestPayload]


class NormalizedAlert(BaseModel):
    external_rule_id: str
    severity_hint: int
    event_family: str
    agent_id: str
    agent_name: str
    source_ip: str | None
    full_log: str
    scenario_type: str
    event_timestamp: datetime
    features: dict[str, Any]


class MLEventRequest(BaseModel):
    event: NormalizedAlert


class MLWindowRequest(BaseModel):
    window: list[NormalizedAlert]


class MLPrediction(BaseModel):
    incident_type: str
    confidence: float
    severity: str
    recommended_action: str
    model_version: str
    explanation_summary: str


class MLWindowAnalysis(MLPrediction):
    correlated_events: list[str] = Field(default_factory=list)
    timeline_events: list[dict[str, Any]] = Field(default_factory=list)
    causal_graph: dict[str, Any] = Field(default_factory=lambda: {"nodes": [], "edges": []})
    summary_text: str = ""
