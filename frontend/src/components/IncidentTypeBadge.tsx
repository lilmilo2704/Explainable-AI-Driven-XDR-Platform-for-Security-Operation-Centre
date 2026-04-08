import type { IncidentType } from "../types/domain";

interface Props {
  type: IncidentType;
}

export function IncidentTypeBadge({ type }: Props) {
  const normalized = type.toLowerCase().replace(/[^a-z]+/g, "-");
  return <span className={`badge incident-type ${normalized}`}>{type}</span>;
}
