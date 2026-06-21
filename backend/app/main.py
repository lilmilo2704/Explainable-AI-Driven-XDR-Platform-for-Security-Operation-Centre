from __future__ import annotations

import json
import secrets
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import desc, text
from sqlalchemy.orm import Session, selectinload

from app.core.config import (
    ML_SERVICE_URL,
    SEED_ALERTS_PATH,
    SEED_MULTI_STAGE_PATH,
    XDR_DEMO_API_TOKEN,
    XDR_DEMO_IMPORT_ENABLED,
)
from app.db import engine, get_db
from app.models import Alert, Base, Incident, IncidentAlertLink
from app.schemas import AlertIngestPayload, IncidentWindowPayload, OfficialRunImportRequest
from app.services.ingestion_service import clear_demo_data, ingest_single_alert, ingest_window_incident
from app.services.ml_client import MLClient
from app.services.official_run_import_service import (
    OfficialRunRejection,
    official_run_import_service,
)
from app.services.serialization import (
    build_dashboard_summary,
    parse_public_incident_id,
    serialize_alert,
    serialize_incident_detail,
    serialize_incident_summary,
)

app = FastAPI(title="XDR Backend Prototype", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

ml_client = MLClient()


def run_schema_bootstrap() -> None:
    # Prototype-safe bootstrap for incremental local runs without full migrations.
    ddl_statements = [
        """
        ALTER TABLE alerts
        ADD COLUMN IF NOT EXISTS normalized_payload JSONB DEFAULT '{}'::jsonb
        """,
        """
        ALTER TABLE predictions
        ADD COLUMN IF NOT EXISTS incident_id INTEGER
        """,
        """
        ALTER TABLE predictions
        ADD COLUMN IF NOT EXISTS explanation_features JSONB DEFAULT '[]'::jsonb
        """,
        """
        ALTER TABLE incidents
        ADD COLUMN IF NOT EXISTS summary_text TEXT DEFAULT ''
        """,
        """
        ALTER TABLE incidents
        ADD COLUMN IF NOT EXISTS explanation_features JSONB DEFAULT '[]'::jsonb
        """,
        """
        ALTER TABLE incidents
        ADD COLUMN IF NOT EXISTS timeline_events JSONB DEFAULT '[]'::jsonb
        """,
        """
        ALTER TABLE incidents
        ADD COLUMN IF NOT EXISTS causal_graph JSONB DEFAULT '{}'::jsonb
        """,
        """
        ALTER TABLE incidents
        ADD COLUMN IF NOT EXISTS correlated_event_ids JSONB DEFAULT '[]'::jsonb
        """,
        """
        CREATE TABLE IF NOT EXISTS incident_alert_links (
            id SERIAL PRIMARY KEY,
            incident_id INTEGER NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
            alert_id INTEGER NOT NULL REFERENCES alerts(id) ON DELETE CASCADE
        )
        """,
        """
        CREATE INDEX IF NOT EXISTS ix_incident_alert_links_incident_id
        ON incident_alert_links (incident_id)
        """,
        """
        CREATE INDEX IF NOT EXISTS ix_incident_alert_links_alert_id
        ON incident_alert_links (alert_id)
        """,
    ]

    with engine.begin() as connection:
        for statement in ddl_statements:
            connection.execute(text(statement))


@app.on_event("startup")
def startup_event() -> None:
    Base.metadata.create_all(bind=engine)
    run_schema_bootstrap()


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _extract_bearer_token(authorization: str | None) -> str | None:
    if not authorization:
        return None
    scheme, _, value = authorization.partition(" ")
    if scheme.lower() != "bearer" or not value:
        return None
    return value.strip()


def require_demo_import_auth(
    authorization: str | None = Header(default=None),
    x_xdr_demo_api_token: str | None = Header(default=None, alias="X-XDR-Demo-API-Token"),
) -> None:
    if not XDR_DEMO_IMPORT_ENABLED:
        raise HTTPException(
            status_code=403,
            detail={
                "state": "rejected",
                "verified": False,
                "rejection": {
                    "code": "demo_import_disabled",
                    "message": "Official run import verification is disabled.",
                },
            },
        )
    if not XDR_DEMO_API_TOKEN:
        raise HTTPException(
            status_code=403,
            detail={
                "state": "rejected",
                "verified": False,
                "rejection": {
                    "code": "demo_import_token_not_configured",
                    "message": "Official run import verification token is not configured.",
                },
            },
        )

    supplied_token = _extract_bearer_token(authorization) or x_xdr_demo_api_token
    if not supplied_token:
        raise HTTPException(
            status_code=401,
            detail={
                "state": "rejected",
                "verified": False,
                "rejection": {
                    "code": "demo_import_token_missing",
                    "message": "Official run import verification token is required.",
                },
            },
        )
    if not secrets.compare_digest(supplied_token, XDR_DEMO_API_TOKEN):
        raise HTTPException(
            status_code=403,
            detail={
                "state": "rejected",
                "verified": False,
                "rejection": {
                    "code": "demo_import_token_invalid",
                    "message": "Official run import verification token is invalid.",
                },
            },
        )


@app.get("/health")
def health(db: Session = Depends(get_db)) -> dict[str, Any]:
    db_status = "ok"
    ml_status = "ok"

    try:
        db.execute(text("SELECT 1"))
    except Exception:
        db_status = "error"

    try:
        with httpx.Client(timeout=3.0) as client:
            res = client.get(f"{ML_SERVICE_URL}/health")
            if res.status_code != 200:
                ml_status = "error"
    except Exception:
        ml_status = "error"

    overall = "ok" if db_status == "ok" and ml_status == "ok" else "degraded"
    return {
        "status": overall,
        "service": "backend",
        "database": db_status,
        "ml_service": ml_status,
        "timestamp": now_iso(),
    }


@app.post("/api/official-runs/import", response_model=None)
def verify_official_run_route(
    payload: OfficialRunImportRequest,
    _: None = Depends(require_demo_import_auth),
) -> Any:
    try:
        return official_run_import_service.verify(payload.release_id, payload.run_id)
    except OfficialRunRejection as exc:
        return JSONResponse(
            status_code=exc.status_code,
            content=exc.as_response(payload.release_id, payload.run_id),
        )


@app.post("/api/alerts/ingest")
def ingest_alert_route(payload: AlertIngestPayload, db: Session = Depends(get_db)) -> dict[str, Any]:
    alert, prediction, incident = ingest_single_alert(db, payload, ml_client)
    return {
        "message": "alert_ingested",
        "alert": serialize_alert(alert, include_raw=True),
        "prediction": {
            "incident_type": prediction.incident_type,
            "confidence": prediction.confidence,
            "severity": prediction.severity,
            "recommended_action": prediction.recommended_action,
            "model_version": prediction.model_version,
            "explanation_summary": prediction.explanation_summary,
            "explanation_features": prediction.explanation_features,
        },
        "incident_id": f"INC-{incident.id:06d}" if incident else None,
    }


@app.post("/api/incidents/ingest-window")
def ingest_window_route(payload: IncidentWindowPayload, db: Session = Depends(get_db)) -> dict[str, Any]:
    incident = ingest_window_incident(db, payload.alerts, ml_client)
    incident_with_links = (
        db.query(Incident)
        .options(selectinload(Incident.alert_links).selectinload(IncidentAlertLink.alert))
        .filter(Incident.id == incident.id)
        .first()
    )
    if incident_with_links is None:
        raise HTTPException(status_code=500, detail="Incident not found after creation")

    return {
        "message": "incident_classified",
        "incident": serialize_incident_summary(incident_with_links),
    }


@app.get("/api/alerts")
def list_alerts(db: Session = Depends(get_db)) -> list[dict[str, Any]]:
    alerts = (
        db.query(Alert)
        .options(selectinload(Alert.prediction), selectinload(Alert.incident_links))
        .order_by(desc(Alert.event_timestamp))
        .all()
    )
    return [serialize_alert(alert) for alert in alerts]


@app.get("/api/alerts/{alert_id}")
def get_alert(alert_id: int, db: Session = Depends(get_db)) -> dict[str, Any]:
    alert = (
        db.query(Alert)
        .options(selectinload(Alert.prediction), selectinload(Alert.incident_links))
        .filter(Alert.id == alert_id)
        .first()
    )
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    return serialize_alert(alert, include_raw=True)


@app.get("/api/incidents")
def list_incidents(db: Session = Depends(get_db)) -> list[dict[str, Any]]:
    incidents = (
        db.query(Incident)
        .options(selectinload(Incident.alert_links).selectinload(IncidentAlertLink.alert))
        .order_by(desc(Incident.created_at))
        .all()
    )
    return [serialize_incident_summary(incident) for incident in incidents]


@app.get("/api/incidents/{incident_id}")
def get_incident(incident_id: str, db: Session = Depends(get_db)) -> dict[str, Any]:
    internal_id = parse_public_incident_id(incident_id)
    if internal_id is None:
        raise HTTPException(status_code=400, detail="Invalid incident id format")

    incident = (
        db.query(Incident)
        .options(selectinload(Incident.alert_links).selectinload(IncidentAlertLink.alert))
        .filter(Incident.id == internal_id)
        .first()
    )
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found")

    return serialize_incident_detail(incident)


@app.get("/api/dashboard/summary")
def dashboard_summary(db: Session = Depends(get_db)) -> dict[str, Any]:
    incidents = (
        db.query(Incident)
        .options(selectinload(Incident.alert_links).selectinload(IncidentAlertLink.alert))
        .order_by(desc(Incident.created_at))
        .all()
    )
    alert_count = db.query(Alert).count()
    asset_names = {
        row[0]
        for row in db.query(Alert.agent_name).distinct().all()
        if row and row[0]
    }
    return build_dashboard_summary(incidents, alert_count, len(asset_names))


@app.get("/api/models")
def models() -> dict[str, Any]:
    return {
        "models": [
            {
                "id": "xdr-run-level-ebm",
                "name": "Run-Level EBM DDoS Detector",
                "version": "xdr-run-level-dos-ebm-surrogate-v1",
                "purpose": "Run-level Benign vs DoS_DDoS detection with native EBM explanations",
                "attack_classes_supported": [
                    "Benign",
                    "DoS_DDoS",
                ],
                "latest_inference_time": now_iso(),
                "explanation_available": True,
            },
            {
                "id": "xdr-run-level-teachers",
                "name": "Teacher Models With EBM Surrogates",
                "version": "xdr-run-level-dos-ebm-surrogate-v1",
                "purpose": "XGBoost, Random Forest, SVM, and MLP teachers explained by EBM surrogates",
                "attack_classes_supported": [
                    "Benign",
                    "DoS_DDoS",
                ],
                "latest_inference_time": now_iso(),
                "explanation_available": True,
                "class_level_scores": [
                    {"class_name": "Benign", "f1_score": 0.96},
                    {"class_name": "DoS_DDoS", "f1_score": 0.96},
                ],
                "dominant_features_by_class": {
                    "DoS_DDoS": [
                        "request_rate_per_second",
                        "peak_request_rate_per_second",
                        "search_request_ratio",
                        "request_repeat_ratio",
                    ],
                    "Benign": [
                        "health_check_ratio",
                        "avg_response_time_ms",
                        "p95_avg_latency_ratio",
                    ],
                },
                "note": "Legacy keyword models remain as fallbacks for non-DDoS demo scenarios.",
            },
        ]
    }


@app.get("/api/assets")
def assets(db: Session = Depends(get_db)) -> list[dict[str, Any]]:
    severity_rank = {"low": 1, "medium": 2, "high": 3, "critical": 4}
    grouped: dict[str, dict[str, Any]] = {}
    alerts = db.query(Alert).order_by(desc(Alert.event_timestamp)).all()
    for alert in alerts:
        entry = grouped.setdefault(
            alert.agent_name,
            {
                "id": f"asset-{alert.agent_name}",
                "name": alert.agent_name,
                "host_role": "Monitored Endpoint",
                "operating_system": "Unknown",
                "agent_status": "online",
                "last_seen": alert.event_timestamp.astimezone(timezone.utc).isoformat(),
                "event_volume_24h": 0,
                "incident_count": 0,
                "risk": "medium",
                "related_incident_ids": [],
                "related_alert_ids": [],
            },
        )
        entry["event_volume_24h"] += 1
        entry["related_alert_ids"].append(alert.id)

    incidents = db.query(Incident).options(selectinload(Incident.alert_links)).all()
    for incident in incidents:
        for link in incident.alert_links:
            alert = next((a for a in alerts if a.id == link.alert_id), None)
            if alert and alert.agent_name in grouped:
                grouped[alert.agent_name]["incident_count"] += 1
                incident_public_id = f"INC-{incident.id:06d}"
                if incident_public_id not in grouped[alert.agent_name]["related_incident_ids"]:
                    grouped[alert.agent_name]["related_incident_ids"].append(incident_public_id)
                current_risk = grouped[alert.agent_name]["risk"]
                if severity_rank.get(incident.severity, 0) > severity_rank.get(current_risk, 0):
                    grouped[alert.agent_name]["risk"] = incident.severity

    return list(grouped.values())


@app.get("/api/cases")
def cases(db: Session = Depends(get_db)) -> list[dict[str, Any]]:
    incidents = db.query(Incident).order_by(desc(Incident.created_at)).limit(20).all()
    return [
        {
            "id": f"CASE-{incident.id:05d}",
            "status": "investigating",
            "owner": "SOC Analyst",
            "linked_incident_id": f"INC-{incident.id:06d}",
            "created_at": incident.created_at.astimezone(timezone.utc).isoformat(),
            "notes_preview": incident.explanation_summary,
            "response_actions": [incident.recommended_action],
            "outcome": "In progress",
        }
        for incident in incidents
    ]


@app.post("/api/mock/seed")
def seed_data(db: Session = Depends(get_db)) -> dict[str, Any]:
    if not SEED_ALERTS_PATH.exists() or not SEED_MULTI_STAGE_PATH.exists():
        raise HTTPException(status_code=500, detail="Seed files are missing")

    # Keep seed deterministic for demos and repeated local runs.
    clear_demo_data(db)

    with SEED_ALERTS_PATH.open("r", encoding="utf-8") as seed_file:
        seed_alerts = json.load(seed_file)

    inserted_alerts = 0
    for item in seed_alerts:
        payload = AlertIngestPayload.model_validate(item)
        ingest_single_alert(db, payload, ml_client)
        inserted_alerts += 1

    with SEED_MULTI_STAGE_PATH.open("r", encoding="utf-8") as window_file:
        window_payload = IncidentWindowPayload.model_validate(json.load(window_file))

    incident = ingest_window_incident(db, window_payload.alerts, ml_client)

    return {
        "message": "seed_completed",
        "alerts_inserted": inserted_alerts,
        "incident_seeded": f"INC-{incident.id:06d}",
    }


@app.delete("/api/reset")
def reset_data(db: Session = Depends(get_db)) -> dict[str, Any]:
    result = clear_demo_data(db)
    return {"message": "database_cleared", **result}


@app.delete("/api/alerts")
def clear_alerts_compat(db: Session = Depends(get_db)) -> dict[str, Any]:
    result = clear_demo_data(db)
    return {"message": "database_cleared", **result}
