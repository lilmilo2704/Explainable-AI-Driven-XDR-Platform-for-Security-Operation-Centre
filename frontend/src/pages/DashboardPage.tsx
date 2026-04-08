import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip, BarChart, Bar, XAxis, YAxis } from "recharts";
import { Link, useNavigate } from "react-router-dom";
import { api } from "../api/client";
import { EmptyState } from "../components/EmptyState";
import { ErrorState } from "../components/ErrorState";
import { IncidentTypeBadge } from "../components/IncidentTypeBadge";
import { LoadingState } from "../components/LoadingState";
import { SeverityBadge } from "../components/SeverityBadge";
import { SummaryCard } from "../components/SummaryCard";
import { useDashboardSummaryQuery, useIncidentsQuery } from "../hooks/queries";
import { formatTime, pct } from "../utils/format";

const severityColors: Record<string, string> = {
  low: "#6aa7ff",
  medium: "#f6c85f",
  high: "#ff7d57",
  critical: "#ff4d6d",
};

const typeColors = ["#53b3cb", "#7bc86c", "#f6c85f", "#ff7d57", "#fb6376", "#9b8cff"];

export function DashboardPage() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const summaryQuery = useDashboardSummaryQuery();
  const incidentsQuery = useIncidentsQuery();

  const seedMutation = useMutation({
    mutationFn: api.seedDemoData,
    onSuccess: async () => {
      await queryClient.invalidateQueries();
    },
  });

  const clearMutation = useMutation({
    mutationFn: api.clearDemoData,
    onSuccess: async () => {
      await queryClient.invalidateQueries();
    },
  });

  if (summaryQuery.isLoading) return <LoadingState title="Loading Dashboard" message="Calculating XDR status..." />;
  if (summaryQuery.error) return <ErrorState message="Could not load dashboard summary." onRetry={() => void summaryQuery.refetch()} />;

  const summary = summaryQuery.data;
  const incidents = incidentsQuery.data ?? [];
  if (!summary) return <EmptyState title="No Dashboard Data" message="Seed demo data to initialize the SOC view." />;

  const latestIncident = incidents[0];

  return (
    <div className="page-grid">
      <section className="summary-grid">
        <SummaryCard title="Total Alerts" value={summary.total_alerts} />
        <SummaryCard title="Active Incidents" value={summary.active_incidents} />
        <SummaryCard title="Critical Incidents" value={summary.critical_incidents} />
        <SummaryCard title="Monitored Assets" value={summary.monitored_assets} />
        <SummaryCard title="Open Cases" value={summary.open_cases} />
        <SummaryCard title="Latest Attack Type" value={summary.latest_attack_type} subtitle={`Sync: ${formatTime(summary.latest_sync)}`} />
      </section>

      <section className="grid two-col">
        <article className="panel">
          <h3>Incidents by Type</h3>
          <div className="chart-wrap">
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={summary.incidents_by_type}>
                <XAxis dataKey="type" interval={0} angle={-20} height={80} textAnchor="end" />
                <YAxis />
                <Tooltip />
                <Bar dataKey="count">
                  {summary.incidents_by_type.map((item, idx) => (
                    <Cell key={item.type} fill={typeColors[idx % typeColors.length]} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </article>

        <article className="panel">
          <h3>Severity Distribution</h3>
          <div className="chart-wrap">
            <ResponsiveContainer width="100%" height={260}>
              <PieChart>
                <Pie data={summary.severity_distribution} dataKey="count" nameKey="severity" outerRadius={95} label>
                  {summary.severity_distribution.map((entry) => (
                    <Cell key={entry.severity} fill={severityColors[entry.severity]} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </article>
      </section>

      <section className="grid two-col">
        <article className="panel">
          <div className="row between">
            <h3>Recent Incidents</h3>
            <Link to="/incidents" className="text-link">View all</Link>
          </div>
          {summary.recent_incidents.length === 0 ? (
            <EmptyState title="No Incidents" message="No incidents are currently available." />
          ) : (
            <div className="stack gap-sm">
              {summary.recent_incidents.map((incident) => (
                <Link key={incident.id} className="list-row" to={`/incidents/${incident.id}`}>
                  <div>
                    <p className="label">{incident.id}</p>
                    <p>{incident.title}</p>
                  </div>
                  <div className="row gap-sm">
                    <IncidentTypeBadge type={incident.incident_type} />
                    <SeverityBadge severity={incident.severity} />
                    <span className="subtle">{pct(incident.confidence)}</span>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </article>

        <article className="panel">
          <h3>Active Attack Stories</h3>
          <div className="stack gap-sm">
            {summary.active_attack_stories.map((story) => (
              <Link key={story.incident_id} className="list-row" to={`/incidents/${story.incident_id}`}>
                <p>{story.incident_id}</p>
                <div className="row gap-sm">
                  <span className={`badge ${story.has_timeline ? "ok" : "neutral"}`}>Timeline</span>
                  <span className={`badge ${story.has_graph ? "ok" : "neutral"}`}>Graph</span>
                </div>
              </Link>
            ))}
          </div>
        </article>
      </section>

      <section className="panel">
        <h3>Quick Actions</h3>
        <div className="row gap-sm wrap">
          <button className="button" onClick={() => seedMutation.mutate()} disabled={seedMutation.isPending}>Seed Demo Data</button>
          <button className="button secondary" onClick={() => void queryClient.invalidateQueries()}>Refresh Data</button>
          <button className="button danger" onClick={() => clearMutation.mutate()} disabled={clearMutation.isPending}>Clear Demo Data</button>
          <button className="button secondary" onClick={() => latestIncident && navigate(`/incidents/${latestIncident.id}`)} disabled={!latestIncident}>Open Latest Incident</button>
        </div>
      </section>
    </div>
  );
}
