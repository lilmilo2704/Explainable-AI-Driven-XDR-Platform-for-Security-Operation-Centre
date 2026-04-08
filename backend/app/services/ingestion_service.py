from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.models import Alert, Incident, IncidentAlertLink, Prediction
from app.schemas import AlertIngestPayload, MLEventRequest
from app.services.ml_client import MLClient
from app.services.normalization_service import normalize_alert
from app.services.windowing_service import build_window_request


def ingest_single_alert(db: Session, payload: AlertIngestPayload, ml_client: MLClient) -> tuple[Alert, Prediction, Incident | None]:
    normalized = normalize_alert(payload)

    alert = Alert(
        rule_id=payload.rule.id,
        rule_level=payload.rule.level,
        rule_description=payload.rule.description,
        agent_id=payload.agent.id,
        agent_name=payload.agent.name,
        source_ip=payload.data.srcip,
        full_log=payload.full_log,
        raw_payload=payload.model_dump(mode="json"),
        normalized_payload=normalized.model_dump(mode="json"),
        event_timestamp=payload.timestamp,
        scenario_type=payload.scenario_type,
    )
    db.add(alert)
    db.flush()

    prediction_data = ml_client.predict_event(MLEventRequest(event=normalized))
    prediction = Prediction(
        alert_id=alert.id,
        incident_type=prediction_data.incident_type,
        confidence=float(prediction_data.confidence),
        severity=prediction_data.severity,
        recommended_action=prediction_data.recommended_action,
        model_version=prediction_data.model_version,
        explanation_summary=prediction_data.explanation_summary,
    )
    db.add(prediction)

    incident: Incident | None = None
    if prediction.incident_type != "Unknown":
        incident = Incident(
            incident_type=prediction.incident_type,
            confidence=prediction.confidence,
            severity=prediction.severity,
            recommended_action=prediction.recommended_action,
            model_version=prediction.model_version,
            explanation_summary=prediction.explanation_summary,
            summary_text=prediction.explanation_summary,
            timeline_events=[
                {
                    "id": f"event-{alert.id}",
                    "timestamp": alert.event_timestamp.astimezone(timezone.utc).isoformat(),
                    "event_type": "Alert Ingested",
                    "asset": alert.agent_name,
                    "ip": alert.source_ip,
                    "raw_log": alert.full_log,
                    "explanation": "Normalized Wazuh-style event mapped to incident candidate.",
                }
            ],
            causal_graph={
                "nodes": [
                    {
                        "id": "alert-event",
                        "position": {"x": 40, "y": 80},
                        "data": {
                            "label": alert.rule_description,
                            "category": "service",
                            "confidence": prediction.confidence,
                        },
                    }
                ],
                "edges": [],
            },
            correlated_event_ids=[alert.id],
        )
        db.add(incident)
        db.flush()

        prediction.incident_id = incident.id
        db.add(IncidentAlertLink(incident_id=incident.id, alert_id=alert.id))

    db.commit()
    db.refresh(alert)
    db.refresh(prediction)
    if incident is not None:
        db.refresh(incident)

    return alert, prediction, incident


def ingest_window_incident(
    db: Session,
    payloads: list[AlertIngestPayload],
    ml_client: MLClient,
) -> Incident:
    alerts: list[Alert] = []
    normalized_events = []

    for payload in payloads:
        normalized = normalize_alert(payload)
        normalized_events.append(normalized)
        alert = Alert(
            rule_id=payload.rule.id,
            rule_level=payload.rule.level,
            rule_description=payload.rule.description,
            agent_id=payload.agent.id,
            agent_name=payload.agent.name,
            source_ip=payload.data.srcip,
            full_log=payload.full_log,
            raw_payload=payload.model_dump(mode="json"),
            normalized_payload=normalized.model_dump(mode="json"),
            event_timestamp=payload.timestamp,
            scenario_type=payload.scenario_type,
        )
        db.add(alert)
        db.flush()
        alerts.append(alert)

    window_request = build_window_request(normalized_events)
    analysis = ml_client.analyze_window(window_request)

    timeline_events = analysis.timeline_events or [
        {
            "id": f"window-{idx}",
            "timestamp": alert.event_timestamp.astimezone(timezone.utc).isoformat(),
            "event_type": "Window Event",
            "asset": alert.agent_name,
            "ip": alert.source_ip,
            "raw_log": alert.full_log,
            "explanation": "Included in correlated window.",
        }
        for idx, alert in enumerate(alerts, start=1)
    ]

    incident = Incident(
        incident_type=analysis.incident_type,
        confidence=float(analysis.confidence),
        severity=analysis.severity,
        recommended_action=analysis.recommended_action,
        model_version=analysis.model_version,
        explanation_summary=analysis.explanation_summary,
        summary_text=analysis.summary_text or analysis.explanation_summary,
        timeline_events=timeline_events,
        causal_graph=analysis.causal_graph,
        correlated_event_ids=[alert.id for alert in alerts],
    )
    db.add(incident)
    db.flush()

    for alert in alerts:
        db.add(IncidentAlertLink(incident_id=incident.id, alert_id=alert.id))
        prediction = Prediction(
            alert_id=alert.id,
            incident_id=incident.id,
            incident_type=analysis.incident_type,
            confidence=float(analysis.confidence),
            severity=analysis.severity,
            recommended_action=analysis.recommended_action,
            model_version=analysis.model_version,
            explanation_summary=analysis.explanation_summary,
        )
        db.add(prediction)

    db.commit()
    db.refresh(incident)
    return incident


def clear_demo_data(db: Session) -> dict[str, int]:
    deleted_links = db.query(IncidentAlertLink).delete()
    deleted_predictions = db.query(Prediction).delete()
    deleted_alerts = db.query(Alert).delete()
    deleted_incidents = db.query(Incident).delete()
    db.commit()
    return {
        "deleted_links": deleted_links,
        "deleted_predictions": deleted_predictions,
        "deleted_alerts": deleted_alerts,
        "deleted_incidents": deleted_incidents,
    }
