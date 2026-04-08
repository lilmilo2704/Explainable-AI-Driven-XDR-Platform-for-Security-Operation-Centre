import { Bar, BarChart, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { useParams } from "react-router-dom";
import { CausalGraphPanel } from "../components/CausalGraphPanel";
import { EmptyState } from "../components/EmptyState";
import { ErrorState } from "../components/ErrorState";
import { EvidencePanel } from "../components/EvidencePanel";
import { ExplanationCard } from "../components/ExplanationCard";
import { IncidentTypeBadge } from "../components/IncidentTypeBadge";
import { LoadingState } from "../components/LoadingState";
import { ResponseGuidanceCard } from "../components/ResponseGuidanceCard";
import { SeverityBadge } from "../components/SeverityBadge";
import { StatusBadge } from "../components/StatusBadge";
import { TimelineView } from "../components/TimelineView";
import { useIncidentDetailQuery } from "../hooks/queries";
import { formatTime, pct } from "../utils/format";

export function IncidentDetailPage() {
  const params = useParams();
  const incidentQuery = useIncidentDetailQuery(params.id);

  if (incidentQuery.isLoading) return <LoadingState title="Loading Incident" message="Building attack story and graph..." />;
  if (incidentQuery.error) return <ErrorState message="Unable to load incident detail." onRetry={() => void incidentQuery.refetch()} />;

  const detail = incidentQuery.data;
  if (!detail) return <EmptyState title="Incident Not Found" message="This incident ID is not available." />;

  const incident = detail.incident;

  return (
    <section className="stack gap-sm">
      <article className="panel">
        <div className="row between wrap">
          <div>
            <p className="label">{incident.id}</p>
            <h2>{incident.title}</h2>
            <div className="row gap-sm wrap">
              <IncidentTypeBadge type={incident.incident_type} />
              <SeverityBadge severity={incident.severity} />
              <StatusBadge status={incident.status} />
              <span className="badge neutral">Confidence {pct(incident.confidence)}</span>
            </div>
          </div>
          <div className="row gap-sm wrap">
            <button className="button secondary">Create / Link Case</button>
            <button className="button secondary">Mark Investigating</button>
            <button className="button secondary">Mark Contained</button>
            <button className="button">Export Summary</button>
          </div>
        </div>
        <div className="grid three-col meta-grid">
          <div><p className="label">Created</p><p>{formatTime(incident.created_at)}</p></div>
          <div><p className="label">Affected Assets</p><p>{incident.affected_assets.join(", ")}</p></div>
          <div><p className="label">Source IPs</p><p>{incident.source_ips.join(", ")}</p></div>
        </div>
      </article>

      <article className="panel">
        <h3>Attack Story Summary</h3>
        <p>{detail.attack_story}</p>
      </article>

      <section className="grid two-col">
        <TimelineView events={detail.timeline} />
        <CausalGraphPanel nodes={detail.graph.nodes} edges={detail.graph.edges} />
      </section>

      <section className="grid two-col">
        <article className="panel">
          <h3>Detection / Model Panel</h3>
          <p><span className="label">Predicted Class:</span> {detail.detection.predicted_class}</p>
          <p><span className="label">Confidence:</span> {pct(detail.detection.confidence)}</p>
          <p><span className="label">Model Version:</span> {detail.detection.model_version}</p>
          <p><span className="label">Top Indicators:</span> {detail.detection.top_indicators.join(", ")}</p>
          <div className="chart-wrap short">
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={detail.detection.class_probabilities}>
                <XAxis dataKey="class_name" interval={0} angle={-20} height={70} textAnchor="end" />
                <YAxis />
                <Tooltip />
                <Bar dataKey="value">
                  {detail.detection.class_probabilities.map((entry) => (
                    <Cell key={entry.class_name} fill={entry.class_name === detail.detection.predicted_class ? "#2bc48a" : "#3b4b70"} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </article>

        <ExplanationCard explanation={detail.explanation} />
      </section>

      <section className="grid two-col">
        <EvidencePanel evidence={detail.evidence} />
        <ResponseGuidanceCard title="Response Guidance" items={detail.response_guidance} />
      </section>

      <article className="panel">
        <h3>Case Panel</h3>
        <div className="grid four-col">
          <div>
            <p className="label">Case ID</p>
            <p>{detail.case_context.case_id ?? "Not linked"}</p>
          </div>
          <div>
            <p className="label">Owner</p>
            <p>{detail.case_context.owner}</p>
          </div>
          <div>
            <p className="label">Status</p>
            <StatusBadge status={detail.case_context.status} />
          </div>
          <div>
            <p className="label">Outcome</p>
            <p>{detail.case_context.outcome}</p>
          </div>
        </div>
        <p className="subtle">Notes: {detail.case_context.notes}</p>
        <button className="button secondary">Open / Create Case</button>
      </article>
    </section>
  );
}
