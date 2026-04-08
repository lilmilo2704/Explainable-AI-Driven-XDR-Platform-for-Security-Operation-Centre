export type Severity = "low" | "medium" | "high" | "critical";

export type IncidentType =
  | "Account Takeover"
  | "Endpoint Compromise"
  | "DDoS"
  | "Data Exfiltration"
  | "Web Attack"
  | "Multi-Stage Attack";

export type CaseStatus = "new" | "investigating" | "contained" | "closed";

export interface AlertPrediction {
  id?: number;
  alert_id?: number;
  incident_type: IncidentType;
  confidence: number;
  severity: Severity;
  recommended_action: string;
  model_version: string;
  explanation_summary: string;
  created_at?: string;
}

export interface AlertRecord {
  id: number;
  rule_id: string;
  rule_level?: number;
  rule_description: string;
  agent_id?: string;
  agent_name: string;
  source_ip?: string | null;
  full_log: string;
  raw_payload?: Record<string, unknown>;
  event_timestamp: string;
  scenario_type?: string | null;
  mapped_incident_type?: IncidentType;
  prediction?: AlertPrediction | null;
  linked_incident_id?: string;
}

export interface IncidentRecord {
  id: string;
  title: string;
  incident_type: IncidentType;
  severity: Severity;
  confidence: number;
  status: CaseStatus;
  attack_story_summary: string;
  affected_assets: string[];
  source_ips: string[];
  related_alert_ids: number[];
  related_alert_count: number;
  recommendation_preview: string;
  created_at: string;
  updated_at: string;
  case_id?: string;
}

export interface TimelineEvent {
  id: string;
  timestamp: string;
  event_type: string;
  asset: string;
  user?: string;
  ip?: string;
  explanation: string;
}

export interface GraphNodeData {
  label: string;
  category: "identity" | "endpoint" | "network" | "application" | "data" | "service";
  confidence?: number;
}

export interface GraphNode {
  id: string;
  position: { x: number; y: number };
  data: GraphNodeData;
}

export interface GraphEdgeData {
  confidence: number;
  explanation: string;
}

export interface GraphEdge {
  id: string;
  source: string;
  target: string;
  label: string;
  data: GraphEdgeData;
}

export interface ExplanationFeature {
  feature: string;
  contribution: number;
  direction: "up" | "down";
}

export interface IncidentDetail {
  incident: IncidentRecord;
  attack_story: string;
  timeline: TimelineEvent[];
  graph: {
    nodes: GraphNode[];
    edges: GraphEdge[];
  };
  detection: {
    predicted_class: IncidentType;
    confidence: number;
    model_version: string;
    class_probabilities: Array<{ class_name: IncidentType; value: number }>;
    top_indicators: string[];
  };
  explanation: {
    summary: string;
    features: ExplanationFeature[];
  };
  evidence: {
    related_alert_ids: number[];
    raw_references: string[];
    linked_assets: string[];
    linked_ips: string[];
    linked_users: string[];
    key_logs: Array<{
      timestamp: string;
      source: string;
      raw_log: string;
      explanation: string;
    }>;
  };
  response_guidance: string[];
  case_context: {
    owner: string;
    status: CaseStatus;
    notes: string;
    outcome: string;
    case_id?: string;
  };
}

export interface AssetRecord {
  id: string;
  name: string;
  host_role: string;
  operating_system: string;
  agent_status: "online" | "degraded" | "offline";
  last_seen: string;
  event_volume_24h: number;
  incident_count: number;
  risk: Severity;
  related_incident_ids: string[];
  related_alert_ids: number[];
}

export interface CaseRecord {
  id: string;
  status: CaseStatus;
  owner: string;
  linked_incident_id: string;
  created_at: string;
  notes_preview: string;
  response_actions: string[];
  outcome: string;
}

export interface CoverageScenario {
  id: string;
  name: string;
  status: "covered" | "demo-ready";
  evidence_sources: string[];
  detection_output: string;
  incident_view_available: boolean;
  graph_view_available: boolean;
  response_guidance_available: boolean;
  explanation: string;
  example_incident_id: string;
}

export interface ModelRecord {
  id: string;
  name: string;
  version: string;
  purpose: string;
  attack_classes_supported: IncidentType[];
  latest_inference_time: string;
  explanation_available: boolean;
}

export interface ModelMapping {
  source_model: string;
  product_surface: string;
}

export interface ModelSummary {
  models: ModelRecord[];
  dominant_features_by_class: Array<{ class_name: IncidentType; features: string[] }>;
  class_level_scores: Array<{ class_name: IncidentType; average_confidence: number }>;
  mappings: ModelMapping[];
  note: string;
}

export interface DashboardSummary {
  total_alerts: number;
  active_incidents: number;
  critical_incidents: number;
  monitored_assets: number;
  open_cases: number;
  latest_attack_type: IncidentType;
  incidents_by_type: Array<{ type: IncidentType; count: number }>;
  severity_distribution: Array<{ severity: Severity; count: number }>;
  recent_incidents: IncidentRecord[];
  active_attack_stories: Array<{ incident_id: string; has_timeline: boolean; has_graph: boolean }>;
  latest_sync: string;
}

export interface ServiceHealth {
  name: "Backend" | "ML Service" | "Database";
  status: "healthy" | "degraded" | "offline";
  latency_ms?: number;
}

export interface SystemHealth {
  environment: string;
  services: ServiceHealth[];
  latest_sync: string;
}
