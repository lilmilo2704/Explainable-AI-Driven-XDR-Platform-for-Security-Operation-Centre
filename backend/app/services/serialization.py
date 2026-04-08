from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.models import Alert, Incident, IncidentAlertLink, Prediction


def to_iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return dt.astimezone(timezone.utc).isoformat()


def public_incident_id(incident_id: int) -> str:
    return f"INC-{incident_id:06d}"


def parse_public_incident_id(public_id: str) -> int | None:
    if public_id.isdigit():
        return int(public_id)
    if public_id.startswith("INC-"):
        tail = public_id.split("INC-", 1)[1]
        if tail.isdigit():
            return int(tail)
    return None


def serialize_prediction(prediction: Prediction | None) -> dict[str, Any] | None:
    if prediction is None:
        return None
    return {
        "id": prediction.id,
        "alert_id": prediction.alert_id,
        "incident_id": public_incident_id(prediction.incident_id) if prediction.incident_id else None,
        "incident_type": prediction.incident_type,
        "confidence": prediction.confidence,
        "severity": prediction.severity,
        "recommended_action": prediction.recommended_action,
        "model_version": prediction.model_version,
        "explanation_summary": prediction.explanation_summary,
        "created_at": to_iso(prediction.created_at),
    }


def serialize_alert(alert: Alert, include_raw: bool = False) -> dict[str, Any]:
    incident_ids = [public_incident_id(link.incident_id) for link in alert.incident_links]
    data: dict[str, Any] = {
        "id": alert.id,
        "rule_id": alert.rule_id,
        "rule_level": alert.rule_level,
        "rule_description": alert.rule_description,
        "agent_id": alert.agent_id,
        "agent_name": alert.agent_name,
        "source_ip": alert.source_ip,
        "full_log": alert.full_log,
        "event_timestamp": to_iso(alert.event_timestamp),
        "scenario_type": alert.scenario_type,
        "created_at": to_iso(alert.created_at),
        "event_family": alert.normalized_payload.get("event_family", "unknown"),
        "prediction": serialize_prediction(alert.prediction),
        "linked_incident_ids": incident_ids,
        "linked_incident_id": incident_ids[0] if incident_ids else None,
        "normalized": alert.normalized_payload,
    }
    if include_raw:
        data["raw_payload"] = alert.raw_payload
    return data


def serialize_incident_summary(incident: Incident) -> dict[str, Any]:
    assets = sorted({link.alert.agent_name for link in incident.alert_links if link.alert is not None})
    source_ips = sorted(
        {
            link.alert.source_ip
            for link in incident.alert_links
            if link.alert is not None and link.alert.source_ip
        }
    )
    return {
        "id": public_incident_id(incident.id),
        "title": incident.summary_text or f"{incident.incident_type} incident",
        "incident_type": incident.incident_type,
        "severity": incident.severity,
        "confidence": incident.confidence,
        "status": "investigating",
        "attack_story_summary": incident.summary_text or incident.explanation_summary,
        "affected_assets": assets,
        "source_ips": source_ips,
        "related_alert_ids": [link.alert_id for link in incident.alert_links],
        "related_alert_count": len(incident.alert_links),
        "recommendation_preview": incident.recommended_action,
        "created_at": to_iso(incident.created_at),
        "updated_at": to_iso(incident.created_at),
    }


def serialize_incident_detail(incident: Incident) -> dict[str, Any]:
    summary = serialize_incident_summary(incident)
    related_alerts = [serialize_alert(link.alert, include_raw=False) for link in incident.alert_links]
    timeline_events = incident.timeline_events or []
    graph = incident.causal_graph or {"nodes": [], "edges": []}

    return {
        "incident": summary,
        "attack_story": incident.summary_text or incident.explanation_summary,
        "timeline": timeline_events,
        "graph": graph,
        "detection": {
            "predicted_class": incident.incident_type,
            "confidence": incident.confidence,
            "model_version": incident.model_version,
            "class_probabilities": [
                {"class_name": incident.incident_type, "value": incident.confidence}
            ],
            "top_indicators": ["event_family", "severity_hint", "scenario_type"],
        },
        "explanation": {
            "summary": incident.explanation_summary,
            "features": [
                {"feature": "window_correlation", "contribution": incident.confidence, "direction": "up"}
            ],
        },
        "evidence": {
            "related_alert_ids": [alert["id"] for alert in related_alerts],
            "raw_references": [f"alert-{alert['id']}" for alert in related_alerts],
            "linked_assets": summary["affected_assets"],
            "linked_ips": summary["source_ips"],
            "linked_users": [],
            "key_logs": [
                {
                    "timestamp": event.get("timestamp", summary["created_at"]),
                    "source": event.get("asset", "unknown"),
                    "raw_log": event.get("raw_log", event.get("event_type", "event")),
                    "explanation": event.get("explanation", "Correlated into incident narrative."),
                }
                for event in timeline_events
            ],
        },
        "response_guidance": [incident.recommended_action],
        "case_context": {
            "owner": "SOC Analyst",
            "status": "investigating",
            "notes": "Auto-generated from backend orchestration layer.",
            "outcome": "In progress",
            "case_id": None,
        },
    }


def build_dashboard_summary(incidents: list[Incident], alert_count: int, asset_count: int) -> dict[str, Any]:
    from collections import Counter

    type_counter = Counter(incident.incident_type for incident in incidents)
    severity_counter = Counter(incident.severity for incident in incidents)

    recent = sorted(incidents, key=lambda item: item.created_at, reverse=True)[:5]
    latest_attack = recent[0].incident_type if recent else "Unknown"

    return {
        "total_alerts": alert_count,
        "active_incidents": len(incidents),
        "critical_incidents": sum(1 for incident in incidents if incident.severity == "critical"),
        "monitored_assets": asset_count,
        "open_cases": len(incidents),
        "latest_attack_type": latest_attack,
        "incidents_by_type": [
            {"type": key, "count": value} for key, value in sorted(type_counter.items())
        ],
        "severity_distribution": [
            {"severity": severity, "count": count}
            for severity, count in sorted(severity_counter.items())
        ],
        "recent_incidents": [serialize_incident_summary(incident) for incident in recent],
        "active_attack_stories": [
            {
                "incident_id": public_incident_id(incident.id),
                "has_timeline": len(incident.timeline_events or []) > 0,
                "has_graph": bool((incident.causal_graph or {}).get("nodes")),
            }
            for incident in recent
        ],
        "latest_sync": to_iso(datetime.now(timezone.utc)),
    }
