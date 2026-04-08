import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { DataTable, type Column } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { ErrorState } from "../components/ErrorState";
import { IncidentTypeBadge } from "../components/IncidentTypeBadge";
import { LoadingState } from "../components/LoadingState";
import { SearchFilterBar } from "../components/SearchFilterBar";
import { SeverityBadge } from "../components/SeverityBadge";
import { StatusBadge } from "../components/StatusBadge";
import { useIncidentsQuery } from "../hooks/queries";
import type { IncidentRecord } from "../types/domain";
import { formatTime, pct, severityRank } from "../utils/format";

export function IncidentsPage() {
  const incidentsQuery = useIncidentsQuery();
  const [search, setSearch] = useState("");
  const [type, setType] = useState("all");
  const [severity, setSeverity] = useState("all");
  const [status, setStatus] = useState("all");
  const [asset, setAsset] = useState("all");
  const [sortBy, setSortBy] = useState("newest");

  const incidents = incidentsQuery.data ?? [];
  const typeOptions = Array.from(new Set(incidents.map((incident) => incident.incident_type)));
  const assetOptions = Array.from(new Set(incidents.flatMap((incident) => incident.affected_assets)));

  const filtered = useMemo(() => {
    const value = incidents.filter((incident) => {
      const joined = `${incident.id} ${incident.title} ${incident.attack_story_summary} ${incident.affected_assets.join(" ")}`.toLowerCase();
      const matchedSearch = search.trim() === "" || joined.includes(search.toLowerCase());
      const matchedType = type === "all" || incident.incident_type === type;
      const matchedSeverity = severity === "all" || incident.severity === severity;
      const matchedStatus = status === "all" || incident.status === status;
      const matchedAsset = asset === "all" || incident.affected_assets.includes(asset);
      return matchedSearch && matchedType && matchedSeverity && matchedStatus && matchedAsset;
    });

    if (sortBy === "highest-severity") {
      value.sort((a, b) => severityRank(a.severity) - severityRank(b.severity));
    } else if (sortBy === "highest-confidence") {
      value.sort((a, b) => b.confidence - a.confidence);
    } else {
      value.sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
    }

    return value;
  }, [incidents, search, type, severity, status, asset, sortBy]);

  const columns: Column<IncidentRecord>[] = [
    { key: "id", header: "Incident ID", render: (row) => <Link to={`/incidents/${row.id}`} className="text-link">{row.id}</Link> },
    { key: "type", header: "Type", render: (row) => <IncidentTypeBadge type={row.incident_type} /> },
    { key: "severity", header: "Severity", render: (row) => <SeverityBadge severity={row.severity} /> },
    { key: "confidence", header: "Confidence", render: (row) => pct(row.confidence) },
    { key: "story", header: "Attack Story", render: (row) => row.attack_story_summary },
    { key: "assets", header: "Affected Assets", render: (row) => row.affected_assets.join(", ") },
    { key: "alerts", header: "Related Alerts", render: (row) => row.related_alert_count },
    { key: "created", header: "Created", render: (row) => formatTime(row.created_at) },
    { key: "case", header: "Case Status", render: (row) => <StatusBadge status={row.status} /> },
    { key: "recommendation", header: "Recommendation", render: (row) => row.recommendation_preview },
  ];

  if (incidentsQuery.isLoading) return <LoadingState title="Loading Incidents" />;
  if (incidentsQuery.error) {
    return (
      <ErrorState
        message="Unable to load incidents."
        onRetry={() => void incidentsQuery.refetch()}
      />
    );
  }

  return (
    <section className="stack gap-sm">
      <SearchFilterBar
        search={search}
        onSearchChange={setSearch}
        filters={[
          { key: "type", value: type, label: "Incident Type", options: [{ label: "All", value: "all" }, ...typeOptions.map((v) => ({ label: v, value: v }))], onChange: setType },
          { key: "severity", value: severity, label: "Severity", options: [{ label: "All", value: "all" }, { label: "Low", value: "low" }, { label: "Medium", value: "medium" }, { label: "High", value: "high" }, { label: "Critical", value: "critical" }], onChange: setSeverity },
          { key: "status", value: status, label: "Status", options: [{ label: "All", value: "all" }, { label: "New", value: "new" }, { label: "Investigating", value: "investigating" }, { label: "Contained", value: "contained" }, { label: "Closed", value: "closed" }], onChange: setStatus },
          { key: "asset", value: asset, label: "Asset", options: [{ label: "All", value: "all" }, ...assetOptions.map((v) => ({ label: v, value: v }))], onChange: setAsset },
          { key: "sort", value: sortBy, label: "Sort", options: [{ label: "Newest", value: "newest" }, { label: "Highest Severity", value: "highest-severity" }, { label: "Highest Confidence", value: "highest-confidence" }], onChange: setSortBy },
        ]}
      />
      <article className="panel">
        <h3>Incident Objects</h3>
        {filtered.length === 0 ? (
          <EmptyState title="No Incidents" message="No incidents match the selected filters." />
        ) : (
          <DataTable rows={filtered} columns={columns} rowKey={(row) => row.id} />
        )}
      </article>
    </section>
  );
}
