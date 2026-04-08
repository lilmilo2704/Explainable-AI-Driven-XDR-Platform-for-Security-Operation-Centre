from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="XDR ML Service", version="0.2.0")

MODEL_VERSION = "mock-intelligence-contract-v1"

ATTACK_RULES: dict[str, dict[str, Any]] = {
    "Account Takeover": {
        "keywords": ["failed login", "authentication failure", "credential stuffing", "multiple login attempts"],
        "severity": "high",
        "confidence": 0.88,
        "recommended_action": "Enforce MFA, rotate credentials, and block offending IPs.",
    },
    "Endpoint Compromise": {
        "keywords": ["powershell", "encoded command", "registry", "persistence", "malware"],
        "severity": "critical",
        "confidence": 0.92,
        "recommended_action": "Isolate endpoint and inspect persistence mechanisms.",
    },
    "DDoS": {
        "keywords": ["flood", "high traffic", "too many requests", "connection spike"],
        "severity": "high",
        "confidence": 0.9,
        "recommended_action": "Enable rate limiting and edge filtering controls.",
    },
    "Data Exfiltration": {
        "keywords": ["archive", "data transfer", "exfiltration", "outbound data", "download"],
        "severity": "critical",
        "confidence": 0.91,
        "recommended_action": "Block suspicious outbound channels and scope data exposure.",
    },
    "Web Attack": {
        "keywords": ["sql", "injection", "union", "web exploit", "or 1=1"],
        "severity": "high",
        "confidence": 0.87,
        "recommended_action": "Block malicious requests and patch vulnerable endpoints.",
    },
}


class NormalizedEvent(BaseModel):
    external_rule_id: str
    severity_hint: int
    event_family: str
    agent_id: str
    agent_name: str
    source_ip: str | None = None
    full_log: str
    scenario_type: str
    event_timestamp: datetime
    features: dict[str, Any]


class PredictEventRequest(BaseModel):
    event: NormalizedEvent


class AnalyzeWindowRequest(BaseModel):
    window: list[NormalizedEvent]


def classify_text(text: str) -> dict[str, Any]:
    combined = text.lower()
    for incident_type, rule in ATTACK_RULES.items():
        if any(keyword in combined for keyword in rule["keywords"]):
            return {
                "incident_type": incident_type,
                "confidence": rule["confidence"],
                "severity": rule["severity"],
                "recommended_action": rule["recommended_action"],
                "model_version": MODEL_VERSION,
                "explanation_summary": f"Keyword pattern matched {incident_type} behavior.",
            }

    return {
        "incident_type": "Unknown",
        "confidence": 0.52,
        "severity": "medium",
        "recommended_action": "Collect more telemetry for analyst triage.",
        "model_version": MODEL_VERSION,
        "explanation_summary": "No strong suspicious signature was found.",
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "service": "ml-service",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/predict-event")
def predict_event(request: PredictEventRequest) -> dict[str, Any]:
    return classify_text(
        f"{request.event.features.get('rule_description', '')} {request.event.full_log} {request.event.scenario_type}"
    )


@app.post("/analyze-window")
def analyze_window(request: AnalyzeWindowRequest) -> dict[str, Any]:
    event_results = []
    observed_types: set[str] = set()

    for event in request.window:
        result = classify_text(
            f"{event.features.get('rule_description', '')} {event.full_log} {event.scenario_type}"
        )
        event_results.append((event, result))
        if result["incident_type"] != "Unknown":
            observed_types.add(result["incident_type"])

    if len(observed_types) >= 2:
        incident_type = "Multi-Stage Attack"
        severity = "critical"
        confidence = 0.95
        recommended = "Initiate cross-domain incident response across identity, endpoint, network, and data teams."
        explanation = f"Mixed suspicious signals observed across categories: {', '.join(sorted(observed_types))}."
    elif len(observed_types) == 1:
        incident_type = next(iter(observed_types))
        base = ATTACK_RULES[incident_type]
        severity = base["severity"]
        confidence = min(base["confidence"] + 0.03, 0.99)
        recommended = base["recommended_action"]
        explanation = f"Window dominated by {incident_type} telemetry signatures."
    else:
        incident_type = "Unknown"
        severity = "medium"
        confidence = 0.5
        recommended = "Collect more events in window for stronger correlation."
        explanation = "No strong suspicious patterns across the provided event window."

    timeline_events = []
    for index, (event, result) in enumerate(event_results, start=1):
        timeline_events.append(
            {
                "id": f"t-{index}",
                "timestamp": event.event_timestamp.astimezone(timezone.utc).isoformat(),
                "event_type": result["incident_type"] if result["incident_type"] != "Unknown" else "Observation",
                "asset": event.agent_name,
                "ip": event.source_ip,
                "raw_log": event.full_log,
                "explanation": result["explanation_summary"],
            }
        )

    nodes = [
        {
            "id": f"n-{idx}",
            "position": {"x": 80 + (idx * 220), "y": 120},
            "data": {
                "label": event.agent_name,
                "category": "service",
                "confidence": result["confidence"],
            },
        }
        for idx, (event, result) in enumerate(event_results)
    ]
    edges = []
    for idx in range(1, len(nodes)):
        edges.append(
            {
                "id": f"e-{idx}",
                "source": nodes[idx - 1]["id"],
                "target": nodes[idx]["id"],
                "label": "correlated progression",
                "data": {
                    "confidence": round(confidence - 0.05, 2),
                    "explanation": "Temporal ordering and shared context indicate progression.",
                },
            }
        )

    return {
        "incident_type": incident_type,
        "confidence": confidence,
        "severity": severity,
        "recommended_action": recommended,
        "model_version": MODEL_VERSION,
        "explanation_summary": explanation,
        "correlated_events": [event.external_rule_id for event, _ in event_results],
        "timeline_events": timeline_events,
        "causal_graph": {"nodes": nodes, "edges": edges},
        "summary_text": (
            f"{incident_type} inferred from {len(event_results)} normalized events with confidence {round(confidence * 100)}%."
        ),
    }


# Backward-compat aliases for earlier skeleton integration.
@app.post("/classify-alert")
def classify_alert_legacy(request: dict[str, Any]) -> dict[str, Any]:
    alert = request.get("alert", {})
    text = f"{alert.get('rule', {}).get('description', '')} {alert.get('full_log', '')} {alert.get('scenario_type', '')}"
    return classify_text(text)


@app.post("/classify-window")
def classify_window_legacy(request: dict[str, Any]) -> dict[str, Any]:
    alerts = request.get("alerts", [])
    window = []
    for item in alerts:
        window.append(
            {
                "external_rule_id": str(item.get("rule", {}).get("id", "legacy")),
                "severity_hint": int(item.get("rule", {}).get("level", 0)),
                "event_family": "legacy",
                "agent_id": str(item.get("agent", {}).get("id", "legacy")),
                "agent_name": str(item.get("agent", {}).get("name", "legacy")),
                "source_ip": item.get("data", {}).get("srcip"),
                "full_log": str(item.get("full_log", "")),
                "scenario_type": str(item.get("scenario_type", "unknown")),
                "event_timestamp": item.get("timestamp") or datetime.now(timezone.utc).isoformat(),
                "features": {"rule_description": str(item.get("rule", {}).get("description", ""))},
            }
        )

    parsed = AnalyzeWindowRequest.model_validate({"window": window})
    return analyze_window(parsed)
