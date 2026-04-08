import { Link } from "react-router-dom";
import { DataTable, type Column } from "../components/DataTable";
import { EmptyState } from "../components/EmptyState";
import { ErrorState } from "../components/ErrorState";
import { LoadingState } from "../components/LoadingState";
import { StatusBadge } from "../components/StatusBadge";
import { useCasesQuery } from "../hooks/queries";
import type { CaseRecord } from "../types/domain";
import { formatTime } from "../utils/format";

export function CasesPage() {
  const casesQuery = useCasesQuery();

  if (casesQuery.isLoading) return <LoadingState title="Loading Cases" />;
  if (casesQuery.error) return <ErrorState message="Unable to load cases." onRetry={() => void casesQuery.refetch()} />;

  const cases = casesQuery.data ?? [];

  const columns: Column<CaseRecord>[] = [
    { key: "id", header: "Case", render: (row) => row.id },
    { key: "status", header: "Status", render: (row) => <StatusBadge status={row.status} /> },
    { key: "owner", header: "Owner", render: (row) => row.owner },
    { key: "incident", header: "Linked Incident", render: (row) => <Link className="text-link" to={`/incidents/${row.linked_incident_id}`}>{row.linked_incident_id}</Link> },
    { key: "created", header: "Created", render: (row) => formatTime(row.created_at) },
    { key: "notes", header: "Notes", render: (row) => row.notes_preview },
  ];

  return (
    <section className="stack gap-sm">
      <article className="panel">
        <h3>Case Management</h3>
        {cases.length === 0 ? (
          <EmptyState title="No Cases" message="No analyst cases are currently tracked." />
        ) : (
          <DataTable rows={cases} columns={columns} rowKey={(row) => row.id} />
        )}
      </article>

      <article className="panel">
        <h3>Case Detail Snapshot</h3>
        {cases.length === 0 ? (
          <p>No case details to show.</p>
        ) : (
          <div className="grid three-col">
            {cases.slice(0, 3).map((item) => (
              <div key={item.id} className="panel soft">
                <p className="label">{item.id}</p>
                <p><span className="label">Incident:</span> {item.linked_incident_id}</p>
                <p><span className="label">Actions:</span> {item.response_actions.join(" | ")}</p>
                <p><span className="label">Outcome:</span> {item.outcome}</p>
              </div>
            ))}
          </div>
        )}
      </article>
    </section>
  );
}
