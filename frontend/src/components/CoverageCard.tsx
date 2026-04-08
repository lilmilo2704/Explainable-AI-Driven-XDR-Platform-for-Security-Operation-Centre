import { Link } from "react-router-dom";
import type { CoverageScenario } from "../types/domain";

interface Props {
  item: CoverageScenario;
}

export function CoverageCard({ item }: Props) {
  return (
    <article className="panel coverage-card">
      <div className="row between">
        <h3>{item.name}</h3>
        <span className={`badge ${item.status === "demo-ready" ? "ok" : "neutral"}`}>{item.status}</span>
      </div>
      <p>{item.explanation}</p>
      <p className="subtle">Evidence: {item.evidence_sources.join(" | ")}</p>
      <p className="subtle">Output: {item.detection_output}</p>
      <div className="row gap-sm">
        <span className="badge neutral">Incident: {item.incident_view_available ? "Yes" : "No"}</span>
        <span className="badge neutral">Graph: {item.graph_view_available ? "Yes" : "No"}</span>
        <span className="badge neutral">Response: {item.response_guidance_available ? "Yes" : "No"}</span>
      </div>
      <Link className="text-link" to={`/incidents/${item.example_incident_id}`}>
        Open Example Incident
      </Link>
    </article>
  );
}
