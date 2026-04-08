from __future__ import annotations

from app.schemas import AlertIngestPayload, NormalizedAlert


def normalize_alert(payload: AlertIngestPayload) -> NormalizedAlert:
    full_text = f"{payload.rule.description} {payload.full_log} {payload.scenario_type or ''}".lower()
    event_family = "wazuh-auth"
    if "powershell" in full_text or "registry" in full_text:
        event_family = "wazuh-endpoint"
    elif "flood" in full_text or "traffic" in full_text or "requests" in full_text:
        event_family = "wazuh-network"
    elif "sql" in full_text or "injection" in full_text:
        event_family = "wazuh-web"
    elif "archive" in full_text or "exfiltration" in full_text or "transfer" in full_text:
        event_family = "wazuh-data"

    scenario = (payload.scenario_type or "unknown").strip().lower()

    return NormalizedAlert(
        external_rule_id=payload.rule.id,
        severity_hint=payload.rule.level,
        event_family=event_family,
        agent_id=payload.agent.id,
        agent_name=payload.agent.name,
        source_ip=payload.data.srcip,
        full_log=payload.full_log,
        scenario_type=scenario,
        event_timestamp=payload.timestamp,
        features={
            "rule_description": payload.rule.description,
            "log_length": len(payload.full_log),
            "has_source_ip": payload.data.srcip is not None,
            "severity_hint": payload.rule.level,
            "event_family": event_family,
            "scenario_type": scenario,
        },
    )
