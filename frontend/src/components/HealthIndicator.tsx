import type { ServiceHealth } from "../types/domain";

interface Props {
  service: ServiceHealth;
}

export function HealthIndicator({ service }: Props) {
  return (
    <div className={`health-indicator ${service.status}`}>
      <span className="dot" />
      <span>{service.name}</span>
      {service.latency_ms ? <span className="subtle">{service.latency_ms}ms</span> : null}
    </div>
  );
}
