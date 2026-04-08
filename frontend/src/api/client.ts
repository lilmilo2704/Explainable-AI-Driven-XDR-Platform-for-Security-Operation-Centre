import { clearMockStore, mockStore, resetMockStore } from "../data/mockData";
import type {
  AlertRecord,
  AssetRecord,
  CaseRecord,
  CoverageScenario,
  DashboardSummary,
  IncidentDetail,
  IncidentRecord,
  ModelSummary,
  SystemHealth,
} from "../types/domain";

const API_BASE = import.meta.env.VITE_API_BASE_URL ?? "http://localhost:8000";

async function tryFetch<T>(path: string): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`);
  if (!response.ok) {
    throw new Error(`${path} request failed (${response.status})`);
  }
  return (await response.json()) as T;
}

async function withFallback<T>(run: () => Promise<T>, fallback: () => T): Promise<T> {
  try {
    return await run();
  } catch {
    return fallback();
  }
}

function mapApiAlert(alert: Record<string, unknown>): AlertRecord {
  const prediction = (alert.prediction ?? null) as AlertRecord["prediction"];
  const incidentType = prediction?.incident_type;
  return {
    id: Number(alert.id),
    rule_id: String(alert.rule_id ?? ""),
    rule_level: typeof alert.rule_level === "number" ? alert.rule_level : undefined,
    rule_description: String(alert.rule_description ?? ""),
    agent_id: alert.agent_id ? String(alert.agent_id) : undefined,
    agent_name: String(alert.agent_name ?? "unknown-agent"),
    source_ip: alert.source_ip ? String(alert.source_ip) : null,
    full_log: String(alert.full_log ?? ""),
    raw_payload: (alert.raw_payload ?? undefined) as Record<string, unknown> | undefined,
    event_timestamp: String(alert.event_timestamp ?? new Date().toISOString()),
    scenario_type: alert.scenario_type ? String(alert.scenario_type) : null,
    mapped_incident_type: incidentType,
    linked_incident_id: alert.linked_incident_id ? String(alert.linked_incident_id) : undefined,
    prediction,
  };
}

function mapApiIncident(incident: Record<string, unknown>): IncidentRecord {
  return {
    id: String(incident.id),
    title: String(incident.title ?? `${incident.incident_type ?? "Incident"}`),
    incident_type: incident.incident_type as IncidentRecord["incident_type"],
    severity: incident.severity as IncidentRecord["severity"],
    confidence: Number(incident.confidence ?? 0),
    status: (incident.status as IncidentRecord["status"]) ?? "investigating",
    attack_story_summary: String(incident.attack_story_summary ?? incident.explanation_summary ?? ""),
    affected_assets: (incident.affected_assets as string[] | undefined) ?? [],
    source_ips: (incident.source_ips as string[] | undefined) ?? [],
    related_alert_ids: (incident.related_alert_ids as number[] | undefined) ?? [],
    related_alert_count: Number(incident.related_alert_count ?? 0),
    recommendation_preview: String(incident.recommendation_preview ?? ""),
    created_at: String(incident.created_at ?? new Date().toISOString()),
    updated_at: String(incident.updated_at ?? incident.created_at ?? new Date().toISOString()),
    case_id: incident.case_id ? String(incident.case_id) : undefined,
  };
}

export const api = {
  async getHealth(): Promise<SystemHealth> {
    return withFallback(
      async () => {
        const backend = await tryFetch<{ status: string; timestamp?: string; database?: string; ml_service?: string }>("/health");
        return {
          environment: "Local Demo",
          services: [
            { name: "Backend", status: backend.status === "ok" ? "healthy" : "degraded", latency_ms: 32 },
            { name: "ML Service", status: backend.ml_service === "ok" ? "healthy" : "degraded", latency_ms: 48 },
            { name: "Database", status: backend.database === "ok" ? "healthy" : "degraded", latency_ms: 57 },
          ],
          latest_sync: backend.timestamp ?? new Date().toISOString(),
        };
      },
      () => mockStore.health,
    );
  },

  async getAlerts(): Promise<AlertRecord[]> {
    return withFallback(
      async () => {
        const data = await tryFetch<Record<string, unknown>[]>("/api/alerts");
        return data.map(mapApiAlert);
      },
      () => mockStore.alerts,
    );
  },

  async getAlertById(id: number): Promise<AlertRecord | null> {
    return withFallback(
      async () => {
        const data = await tryFetch<Record<string, unknown>>(`/api/alerts/${id}`);
        return mapApiAlert(data);
      },
      () => mockStore.alerts.find((alert) => alert.id === id) ?? null,
    );
  },

  async getIncidents(): Promise<IncidentRecord[]> {
    return withFallback(
      async () => {
        const data = await tryFetch<Record<string, unknown>[]>("/api/incidents");
        return data.map(mapApiIncident);
      },
      () => mockStore.incidents,
    );
  },

  async getIncidentById(id: string): Promise<IncidentDetail | null> {
    return withFallback(
      async () => {
        const data = await tryFetch<Record<string, unknown>>(`/api/incidents/${id}`);
        const incident = mapApiIncident(data.incident as Record<string, unknown>);
        const detail: IncidentDetail = {
          incident,
          attack_story: String(data.attack_story ?? incident.attack_story_summary),
          timeline: (data.timeline as IncidentDetail["timeline"] | undefined) ?? [],
          graph: (data.graph as IncidentDetail["graph"] | undefined) ?? { nodes: [], edges: [] },
          detection: (data.detection as IncidentDetail["detection"] | undefined) ?? {
            predicted_class: incident.incident_type,
            confidence: incident.confidence,
            model_version: "unknown",
            class_probabilities: [{ class_name: incident.incident_type, value: incident.confidence }],
            top_indicators: [],
          },
          explanation: (data.explanation as IncidentDetail["explanation"] | undefined) ?? {
            summary: incident.attack_story_summary,
            features: [],
          },
          evidence: (data.evidence as IncidentDetail["evidence"] | undefined) ?? {
            related_alert_ids: incident.related_alert_ids,
            raw_references: incident.related_alert_ids.map((alertId) => `alert-${alertId}`),
            linked_assets: incident.affected_assets,
            linked_ips: incident.source_ips,
            linked_users: [],
            key_logs: [],
          },
          response_guidance: (data.response_guidance as string[] | undefined) ?? [incident.recommendation_preview],
          case_context: (data.case_context as IncidentDetail["case_context"] | undefined) ?? {
            owner: "SOC Analyst",
            status: incident.status,
            notes: "Auto-generated case context",
            outcome: "In progress",
          },
        };
        return detail;
      },
      () => mockStore.incidentDetails[id] ?? null,
    );
  },

  async getAssets(): Promise<AssetRecord[]> {
    return withFallback(
      async () => {
        const data = await tryFetch<AssetRecord[]>("/api/assets");
        return data;
      },
      () => mockStore.assets,
    );
  },

  async getCases(): Promise<CaseRecord[]> {
    return withFallback(
      async () => {
        const data = await tryFetch<CaseRecord[]>("/api/cases");
        return data;
      },
      () => mockStore.cases,
    );
  },

  async getCoverage(): Promise<CoverageScenario[]> {
    return Promise.resolve(mockStore.coverage);
  },

  async getModels(): Promise<ModelSummary> {
    return withFallback(
      async () => {
        const data = await tryFetch<ModelSummary>("/api/models");
        return {
          ...mockStore.models,
          ...data,
          dominant_features_by_class: mockStore.models.dominant_features_by_class,
          class_level_scores: mockStore.models.class_level_scores,
          mappings: mockStore.models.mappings,
          note: mockStore.models.note,
        };
      },
      () => mockStore.models,
    );
  },

  async getDashboardSummary(): Promise<DashboardSummary> {
    return withFallback(
      async () => {
        const data = await tryFetch<DashboardSummary>("/api/dashboard/summary");
        return data;
      },
      () => mockStore.dashboard,
    );
  },

  async seedDemoData(): Promise<void> {
    await withFallback(
      async () => {
        const response = await fetch(`${API_BASE}/api/mock/seed`, { method: "POST" });
        if (!response.ok) throw new Error("seed failed");
      },
      () => {
        resetMockStore();
      },
    );
    resetMockStore();
  },

  async clearDemoData(): Promise<void> {
    await withFallback(
      async () => {
        const response = await fetch(`${API_BASE}/api/reset`, { method: "DELETE" });
        if (!response.ok) throw new Error("clear failed");
      },
      () => {
        clearMockStore();
      },
    );
    clearMockStore();
  },
};
