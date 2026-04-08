import { useMemo, useState } from "react";
import { DataTable, type Column } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { ErrorState } from "../components/ErrorState";
import { IncidentTypeBadge } from "../components/IncidentTypeBadge";
import { LoadingState } from "../components/LoadingState";
import { SearchFilterBar } from "../components/SearchFilterBar";
import { SeverityBadge } from "../components/SeverityBadge";
import { useAlertDetailQuery, useAlertsQuery } from "../hooks/queries";
import type { AlertRecord } from "../types/domain";
import { formatTime } from "../utils/format";

export function AlertsPage() {
  const alertsQuery = useAlertsQuery();
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const detailQuery = useAlertDetailQuery(selectedId);

  const [search, setSearch] = useState("");
  const [severity, setSeverity] = useState("all");
  const [scenario, setScenario] = useState("all");
  const [asset, setAsset] = useState("all");
  const [dateRange, setDateRange] = useState("all");

  const alerts = alertsQuery.data ?? [];

  const filtered = useMemo(() => {
    const now = Date.now();
    return alerts.filter((alert) => {
      const joined = `${alert.rule_description} ${alert.agent_name} ${alert.source_ip ?? ""} ${alert.id}`.toLowerCase();
      const matchedSearch = search.trim() === "" || joined.includes(search.toLowerCase());
      const matchedSeverity = severity === "all" || alert.prediction?.severity === severity;
      const matchedScenario = scenario === "all" || (alert.scenario_type ?? "Unknown") === scenario;
      const matchedAsset = asset === "all" || alert.agent_name === asset;
      const ageHours = (now - new Date(alert.event_timestamp).getTime()) / 36e5;
      const matchedDate =
        dateRange === "all" ||
        (dateRange === "1h" && ageHours <= 1) ||
        (dateRange === "24h" && ageHours <= 24) ||
        (dateRange === "7d" && ageHours <= 24 * 7);
      return matchedSearch && matchedSeverity && matchedScenario && matchedAsset && matchedDate;
    });
  }, [alerts, search, severity, scenario, asset, dateRange]);

  const scenarioOptions = Array.from(new Set(alerts.map((a) => a.scenario_type ?? "Unknown")));
  const assetOptions = Array.from(new Set(alerts.map((a) => a.agent_name)));

  const columns: Column<AlertRecord>[] = [
    { key: "id", header: "Alert ID", render: (row) => row.id },
    { key: "time", header: "Timestamp", render: (row) => formatTime(row.event_timestamp) },
    { key: "rule", header: "Rule ID", render: (row) => row.rule_id },
    { key: "description", header: "Rule Description", render: (row) => row.rule_description },
    { key: "asset", header: "Agent / Asset", render: (row) => row.agent_name },
    { key: "ip", header: "Source IP", render: (row) => row.source_ip ?? "n/a" },
    { key: "scenario", header: "Scenario Type", render: (row) => row.scenario_type ?? "Unknown" },
    {
      key: "mapped",
      header: "Mapped Incident",
      render: (row) =>
        row.mapped_incident_type ? <IncidentTypeBadge type={row.mapped_incident_type} /> : <span className="subtle">Unmapped</span>,
    },
    {
      key: "severity",
      header: "Severity",
      render: (row) =>
        row.prediction?.severity ? <SeverityBadge severity={row.prediction.severity} /> : <span className="subtle">n/a</span>,
    },
  ];

  if (alertsQuery.isLoading) return <LoadingState title="Loading Alerts" message="Ingesting evidence stream..." />;
  if (alertsQuery.error) return <ErrorState message="Unable to load alerts." onRetry={() => void alertsQuery.refetch()} />;

  return (
    <div className="grid detail-layout">
      <section className="stack gap-sm">
        <SearchFilterBar
          search={search}
          onSearchChange={setSearch}
          filters={[
            {
              key: "severity",
              value: severity,
              label: "Severity",
              options: [{ label: "All", value: "all" }, { label: "Low", value: "low" }, { label: "Medium", value: "medium" }, { label: "High", value: "high" }, { label: "Critical", value: "critical" }],
              onChange: setSeverity,
            },
            {
              key: "scenario",
              value: scenario,
              label: "Scenario",
              options: [{ label: "All", value: "all" }, ...scenarioOptions.map((value) => ({ label: value, value }))],
              onChange: setScenario,
            },
            {
              key: "asset",
              value: asset,
              label: "Asset",
              options: [{ label: "All", value: "all" }, ...assetOptions.map((value) => ({ label: value, value }))],
              onChange: setAsset,
            },
            {
              key: "date",
              value: dateRange,
              label: "Date",
              options: [{ label: "Any", value: "all" }, { label: "Last 1h", value: "1h" }, { label: "Last 24h", value: "24h" }, { label: "Last 7d", value: "7d" }],
              onChange: setDateRange,
            },
          ]}
        />
        <article className="panel">
          <h3>Alert Intake Evidence</h3>
          {filtered.length === 0 ? (
            <EmptyState title="No Alerts Found" message="Adjust filters or seed demo data." />
          ) : (
            <DataTable rows={filtered} columns={columns} rowKey={(row) => String(row.id)} onRowClick={(row) => setSelectedId(row.id)} />
          )}
        </article>
      </section>

      <aside className="panel sticky-side">
        <h3>Alert Detail</h3>
        {selectedId === null ? <p>Select an alert to inspect evidence and normalized fields.</p> : null}
        {detailQuery.isLoading ? <LoadingState title="Loading Alert Detail" /> : null}
        {!detailQuery.isLoading && detailQuery.data ? (
          <div className="stack gap-sm">
            <div>
              <p className="label">Alert ID</p>
              <p>{detailQuery.data.id}</p>
            </div>
            <div>
              <p className="label">Source / Family</p>
              <p>{detailQuery.data.agent_name} | {detailQuery.data.rule_id}</p>
            </div>
            <div>
              <p className="label">Raw Payload Summary</p>
              <pre>{JSON.stringify(detailQuery.data.raw_payload ?? {}, null, 2)}</pre>
            </div>
            <div>
              <p className="label">Full Log</p>
              <pre>{detailQuery.data.full_log}</pre>
            </div>
            <div>
              <p className="label">Normalized Fields</p>
              <p>Scenario: {detailQuery.data.scenario_type ?? "Unknown"}</p>
              <p>Mapped Incident: {detailQuery.data.mapped_incident_type ?? "Unmapped"}</p>
              <p>Asset: {detailQuery.data.agent_name}</p>
              <p>Source IP: {detailQuery.data.source_ip ?? "n/a"}</p>
              <p>Linked Incident: {detailQuery.data.linked_incident_id ?? "Not Linked"}</p>
            </div>
          </div>
        ) : null}
      </aside>
    </div>
  );
}
