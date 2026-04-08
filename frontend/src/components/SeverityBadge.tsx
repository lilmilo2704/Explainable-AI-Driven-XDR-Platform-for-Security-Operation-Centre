import type { Severity } from "../types/domain";

interface Props {
  severity: Severity;
}

export function SeverityBadge({ severity }: Props) {
  return <span className={`badge severity-${severity}`}>{severity.toUpperCase()}</span>;
}
