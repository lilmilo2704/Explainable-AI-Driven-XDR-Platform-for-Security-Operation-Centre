import { useMemo, useState } from "react";
import { DataTable, type Column } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { ErrorState } from "../components/ErrorState";
import { LoadingState } from "../components/LoadingState";
import { SearchFilterBar } from "../components/SearchFilterBar";
import { SeverityBadge } from "../components/SeverityBadge";
import { useAssetsQuery } from "../hooks/queries";
import type { AssetRecord } from "../types/domain";
import { formatTime } from "../utils/format";

export function AssetsPage() {
  const assetsQuery = useAssetsQuery();
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("all");
  const [selected, setSelected] = useState<AssetRecord | null>(null);

  const assets = assetsQuery.data ?? [];
  const filtered = useMemo(
    () =>
      assets.filter((asset) => {
        const q = `${asset.name} ${asset.host_role} ${asset.operating_system}`.toLowerCase();
        const bySearch = search.trim() === "" || q.includes(search.toLowerCase());
        const byStatus = status === "all" || asset.agent_status === status;
        return bySearch && byStatus;
      }),
    [assets, search, status],
  );

  const columns: Column<AssetRecord>[] = [
    { key: "name", header: "Asset", render: (row) => row.name },
    { key: "role", header: "Host Role", render: (row) => row.host_role },
    { key: "os", header: "Operating System", render: (row) => row.operating_system },
    { key: "agent", header: "Agent Status", render: (row) => <span className={`badge ${row.agent_status === "online" ? "ok" : row.agent_status === "degraded" ? "warn" : "danger"}`}>{row.agent_status}</span> },
    { key: "seen", header: "Last Seen", render: (row) => formatTime(row.last_seen) },
    { key: "volume", header: "Event Volume", render: (row) => row.event_volume_24h.toLocaleString() },
    { key: "incidents", header: "Incident Count", render: (row) => row.incident_count },
    { key: "risk", header: "Risk", render: (row) => <SeverityBadge severity={row.risk} /> },
  ];

  if (assetsQuery.isLoading) return <LoadingState title="Loading Assets" />;
  if (assetsQuery.error) {
    return (
      <ErrorState
        message="Unable to load assets."
        onRetry={() => void assetsQuery.refetch()}
      />
    );
  }

  return (
    <div className="grid detail-layout">
      <section className="stack gap-sm">
        <SearchFilterBar
          search={search}
          onSearchChange={setSearch}
          filters={[
            {
              key: "status",
              value: status,
              label: "Agent Status",
              options: [
                { label: "All", value: "all" },
                { label: "Online", value: "online" },
                { label: "Degraded", value: "degraded" },
                { label: "Offline", value: "offline" },
              ],
              onChange: setStatus,
            },
          ]}
        />
        <article className="panel">
          <h3>Monitored Assets</h3>
          {filtered.length === 0 ? (
            <EmptyState title="No Assets" message="No assets match the selected filters." />
          ) : (
            <DataTable rows={filtered} columns={columns} rowKey={(row) => row.id} onRowClick={setSelected} />
          )}
        </article>
      </section>

      <aside className="panel sticky-side">
        <h3>Asset Detail</h3>
        {!selected ? <p>Select an asset for related incident and alert context.</p> : null}
        {selected ? (
          <div className="stack gap-sm">
            <p><span className="label">Asset:</span> {selected.name}</p>
            <p><span className="label">Role:</span> {selected.host_role}</p>
            <p><span className="label">Related Incidents:</span> {selected.related_incident_ids.join(", ")}</p>
            <p><span className="label">Related Alerts:</span> {selected.related_alert_ids.join(", ")}</p>
            <p><span className="label">Recent Activity:</span> {selected.event_volume_24h.toLocaleString()} events in 24h</p>
          </div>
        ) : null}
      </aside>
    </div>
  );
}
