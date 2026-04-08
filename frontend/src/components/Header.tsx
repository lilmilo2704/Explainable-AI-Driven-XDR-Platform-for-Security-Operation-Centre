import { RefreshCcw } from "lucide-react";
import { HealthIndicator } from "./HealthIndicator";
import type { SystemHealth } from "../types/domain";
import { formatTime } from "../utils/format";

interface Props {
  health: SystemHealth;
  onRefresh: () => void;
}

export function Header({ health, onRefresh }: Props) {
  return (
    <header className="header">
      <div>
        <h1>Explainable XDR/SIEM Prototype</h1>
        <div className="row gap-sm">
          <span className="badge neutral">{health.environment}</span>
          <span className="subtle">Latest Sync: {formatTime(health.latest_sync)}</span>
        </div>
      </div>
      <div className="row gap-md wrap">
        {health.services.map((service) => (
          <HealthIndicator key={service.name} service={service} />
        ))}
        <button className="button" onClick={onRefresh}>
          <RefreshCcw size={15} />
          Refresh
        </button>
      </div>
    </header>
  );
}
