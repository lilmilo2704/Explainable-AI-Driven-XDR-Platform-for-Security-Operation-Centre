from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from fastapi import Body, FastAPI, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from model_runtime import (
    BASE_FEATURES,
    ENGINEERED_FEATURES,
    MODEL_CONFIGS,
    MODEL_VERSION,
    analyze_events,
    is_dos_candidate,
    model_status,
    models_available,
    normalize_rows,
    predict_dataframe,
    predict_events,
    read_csv_rows,
)

app = FastAPI(title="XDR ML Service", version="0.3.0")

FALLBACK_MODEL_VERSION = "mock-intelligence-contract-v1"

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
        "keywords": ["dos", "ddos", "flood", "high traffic", "too many requests", "connection spike"],
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


def event_to_dict(event: NormalizedEvent) -> dict[str, Any]:
    return event.model_dump(mode="json")


def classify_text(text: str) -> dict[str, Any]:
    combined = text.lower()
    for incident_type, rule in ATTACK_RULES.items():
        if any(keyword in combined for keyword in rule["keywords"]):
            return {
                "incident_type": incident_type,
                "confidence": rule["confidence"],
                "severity": rule["severity"],
                "recommended_action": rule["recommended_action"],
                "model_version": FALLBACK_MODEL_VERSION,
                "explanation_summary": f"Keyword pattern matched {incident_type} behavior.",
                "explanation_features": [
                    {"feature": "keyword_signature", "contribution": rule["confidence"], "direction": "up"}
                ],
            }

    return {
        "incident_type": "Unknown",
        "confidence": 0.52,
        "severity": "medium",
        "recommended_action": "Collect more telemetry for analyst triage.",
        "model_version": FALLBACK_MODEL_VERSION,
        "explanation_summary": "No strong suspicious signature was found.",
        "explanation_features": [
            {"feature": "keyword_signature", "contribution": 0.0, "direction": "neutral"}
        ],
    }


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "service": "ml-service",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "trained_model_runtime": model_status(),
    }


@app.get("/models")
def models() -> dict[str, Any]:
    status = model_status()
    return {
        "version": MODEL_VERSION,
        "loaded": status["loaded"],
        "missing": status["missing"],
        "models": [
            {
                "id": name,
                "name": config["display_name"],
                "version": MODEL_VERSION,
                "purpose": "Run-level Benign vs DoS_DDoS detection with EBM or EBM surrogate explanations.",
                "attack_classes_supported": ["Benign", "DoS_DDoS"],
                "required_base_features": BASE_FEATURES,
                "engineered_features": ENGINEERED_FEATURES,
                "explanation_available": name in status["loaded"],
                "global_explanation_plot": config["plot_path"],
                "surrogate_note": config["surrogate_note"],
            }
            for name, config in MODEL_CONFIGS.items()
        ],
    }


@app.post("/predict-event")
def predict_event(request: PredictEventRequest) -> dict[str, Any]:
    event = event_to_dict(request.event)
    if models_available() and is_dos_candidate([event]):
        return predict_events([event], model_name="ebm")

    return classify_text(
        f"{request.event.features.get('rule_description', '')} {request.event.full_log} {request.event.scenario_type}"
    )


@app.post("/analyze-window")
def analyze_window(request: AnalyzeWindowRequest) -> dict[str, Any]:
    events = [event_to_dict(event) for event in request.window]
    if models_available() and is_dos_candidate(events):
        return analyze_events(events, model_name="ebm")

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
    edges = [
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
        for idx in range(1, len(nodes))
    ]

    return {
        "incident_type": incident_type,
        "confidence": confidence,
        "severity": severity,
        "recommended_action": recommended,
        "model_version": FALLBACK_MODEL_VERSION,
        "explanation_summary": explanation,
        "explanation_features": [
            {"feature": "window_correlation", "contribution": confidence, "direction": "up"}
        ],
        "correlated_events": [event.external_rule_id for event, _ in event_results],
        "timeline_events": timeline_events,
        "causal_graph": {"nodes": nodes, "edges": edges},
        "summary_text": (
            f"{incident_type} inferred from {len(event_results)} normalized events with confidence {round(confidence * 100)}%."
        ),
    }


@app.post("/predict-run")
def predict_run(
    payload: Any = Body(..., description="Raw CSV-style row object, list of rows, or {'rows': [...]}"),
    top_n: int | None = Query(10, ge=1, le=50),
) -> JSONResponse:
    raw_df = normalize_rows(payload)
    return JSONResponse(predict_dataframe(raw_df, model_name="ebm", top_n=top_n))


@app.post("/predict-run/{model_name}")
def predict_run_for_model(
    model_name: str,
    payload: Any = Body(..., description="Raw CSV-style row object, list of rows, or {'rows': [...]}"),
    top_n: int | None = Query(10, ge=1, le=50),
) -> JSONResponse:
    raw_df = normalize_rows(payload)
    return JSONResponse(predict_dataframe(raw_df, model_name=model_name, top_n=top_n))


@app.post("/predict-run-csv")
def predict_run_csv(
    csv_text: str = Body(..., media_type="text/csv"),
    top_n: int | None = Query(10, ge=1, le=50),
) -> JSONResponse:
    raw_df = read_csv_rows(csv_text)
    return JSONResponse(predict_dataframe(raw_df, model_name="ebm", top_n=top_n))


@app.post("/predict-run-csv/{model_name}")
def predict_run_csv_for_model(
    model_name: str,
    csv_text: str = Body(..., media_type="text/csv"),
    top_n: int | None = Query(10, ge=1, le=50),
) -> JSONResponse:
    raw_df = read_csv_rows(csv_text)
    return JSONResponse(predict_dataframe(raw_df, model_name=model_name, top_n=top_n))


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
