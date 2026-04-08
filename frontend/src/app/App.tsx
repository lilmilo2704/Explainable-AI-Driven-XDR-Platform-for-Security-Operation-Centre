import { Navigate, RouterProvider, createBrowserRouter } from "react-router-dom";
import { AppLayout } from "../layouts/AppLayout";
import { AlertsPage } from "../pages/AlertsPage";
import { AssetsPage } from "../pages/AssetsPage";
import { CasesPage } from "../pages/CasesPage";
import { CoveragePage } from "../pages/CoveragePage";
import { DashboardPage } from "../pages/DashboardPage";
import { IncidentDetailPage } from "../pages/IncidentDetailPage";
import { IncidentsPage } from "../pages/IncidentsPage";
import { ModelsPage } from "../pages/ModelsPage";

const router = createBrowserRouter([
  {
    path: "/",
    element: <AppLayout />,
    children: [
      { index: true, element: <Navigate to="/dashboard" replace /> },
      { path: "dashboard", element: <DashboardPage /> },
      { path: "alerts", element: <AlertsPage /> },
      { path: "incidents", element: <IncidentsPage /> },
      { path: "incidents/:id", element: <IncidentDetailPage /> },
      { path: "assets", element: <AssetsPage /> },
      { path: "cases", element: <CasesPage /> },
      { path: "coverage", element: <CoveragePage /> },
      { path: "models", element: <ModelsPage /> },
      { path: "*", element: <Navigate to="/dashboard" replace /> },
    ],
  },
]);

export function App() {
  return <RouterProvider router={router} />;
}
