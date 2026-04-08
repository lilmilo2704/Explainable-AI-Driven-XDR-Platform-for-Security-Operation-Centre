import type { CaseStatus, IncidentType, Severity } from "../types/domain";

export const incidentTypeOrder: IncidentType[] = [
  "Account Takeover",
  "Endpoint Compromise",
  "DDoS",
  "Data Exfiltration",
  "Web Attack",
  "Multi-Stage Attack",
];

export const severityOrder: Severity[] = ["critical", "high", "medium", "low"];

export const caseStatusOrder: CaseStatus[] = ["new", "investigating", "contained", "closed"];

export function formatTime(value: string): string {
  return new Date(value).toLocaleString();
}

export function pct(value: number): string {
  return `${Math.round(value * 100)}%`;
}

export function titleCase(value: string): string {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

export function severityRank(value: Severity): number {
  return severityOrder.indexOf(value);
}
