import type { CaseStatus } from "../types/domain";

interface Props {
  status: CaseStatus;
}

export function StatusBadge({ status }: Props) {
  return <span className={`badge status-${status}`}>{status.toUpperCase()}</span>;
}
