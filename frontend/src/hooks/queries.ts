import { useQuery } from "@tanstack/react-query";
import { api } from "../api/client";

export function useHealthQuery() {
  return useQuery({ queryKey: ["health"], queryFn: api.getHealth, refetchInterval: 30000 });
}

export function useDashboardSummaryQuery() {
  return useQuery({ queryKey: ["dashboard-summary"], queryFn: api.getDashboardSummary });
}

export function useAlertsQuery() {
  return useQuery({ queryKey: ["alerts"], queryFn: api.getAlerts });
}

export function useAlertDetailQuery(alertId: number | null) {
  return useQuery({
    queryKey: ["alerts", "detail", alertId],
    queryFn: () => (alertId ? api.getAlertById(alertId) : Promise.resolve(null)),
    enabled: Boolean(alertId),
  });
}

export function useIncidentsQuery() {
  return useQuery({ queryKey: ["incidents"], queryFn: api.getIncidents });
}

export function useIncidentDetailQuery(incidentId: string | undefined) {
  return useQuery({
    queryKey: ["incidents", "detail", incidentId],
    queryFn: () => (incidentId ? api.getIncidentById(incidentId) : Promise.resolve(null)),
    enabled: Boolean(incidentId),
  });
}

export function useAssetsQuery() {
  return useQuery({ queryKey: ["assets"], queryFn: api.getAssets });
}

export function useCasesQuery() {
  return useQuery({ queryKey: ["cases"], queryFn: api.getCases });
}

export function useCoverageQuery() {
  return useQuery({ queryKey: ["coverage"], queryFn: api.getCoverage });
}

export function useModelsQuery() {
  return useQuery({ queryKey: ["models"], queryFn: api.getModels });
}
