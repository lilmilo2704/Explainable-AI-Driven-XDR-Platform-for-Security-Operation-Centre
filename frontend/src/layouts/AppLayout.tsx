import { Outlet } from "react-router-dom";
import { useQueryClient } from "@tanstack/react-query";
import { Header } from "../components/Header";
import { LoadingState } from "../components/LoadingState";
import { Sidebar } from "../components/Sidebar";
import { useHealthQuery } from "../hooks/queries";
import { mockSystemHealth } from "../data/mockData";

export function AppLayout() {
  const queryClient = useQueryClient();
  const healthQuery = useHealthQuery();
  const health = healthQuery.data ?? mockSystemHealth;

  const refreshAll = () => {
    void queryClient.invalidateQueries();
  };

  return (
    <div className="app-shell">
      <Sidebar />
      <div className="main-shell">
        <Header health={health} onRefresh={refreshAll} />
        <main className="page-container">
          {healthQuery.isLoading && !healthQuery.data ? <LoadingState title="Checking System Health" /> : null}
          <Outlet />
        </main>
      </div>
    </div>
  );
}
