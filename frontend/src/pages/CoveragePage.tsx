import { Link } from "react-router-dom";
import { CoverageCard } from "../components/CoverageCard";
import { ErrorState } from "../components/ErrorState";
import { LoadingState } from "../components/LoadingState";
import { useCoverageQuery, useIncidentsQuery } from "../hooks/queries";

export function CoveragePage() {
  const coverageQuery = useCoverageQuery();
  const incidentsQuery = useIncidentsQuery();

  if (coverageQuery.isLoading) return <LoadingState title="Loading Coverage" />;
  if (coverageQuery.error) return <ErrorState message="Unable to load scenario coverage." onRetry={() => void coverageQuery.refetch()} />;

  const coverage = coverageQuery.data ?? [];
  const incidents = incidentsQuery.data ?? [];
  const latestScenario = coverage.find((item) => item.example_incident_id === incidents[0]?.id) ?? coverage[0];

  return (
    <section className="stack gap-sm">
      <article className="panel">
        <h3>Scenario Coverage Dashboard</h3>
        <div className="grid three-col">
          <div className="panel soft">
            <p className="label">Total Scenarios</p>
            <p>{coverage.length}</p>
          </div>
          <div className="panel soft">
            <p className="label">Demo Ready</p>
            <p>{coverage.filter((item) => item.status === "demo-ready").length}</p>
          </div>
          <div className="panel soft">
            <p className="label">Latest Demo Scenario</p>
            <p>{latestScenario?.name ?? "N/A"}</p>
          </div>
        </div>
      </article>

      <section className="grid two-col">
        {coverage.map((item) => (
          <CoverageCard key={item.id} item={item} />
        ))}
      </section>

      <article className="panel">
        <h3>Scenario Quick Links</h3>
        <div className="row wrap gap-sm">
          {coverage.map((item) => (
            <Link key={item.id} className="button secondary" to={`/incidents/${item.example_incident_id}`}>
              {item.name}
            </Link>
          ))}
        </div>
      </article>
    </section>
  );
}
