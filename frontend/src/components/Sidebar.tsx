import { NavLink } from "react-router-dom";
import { Activity, AlertTriangle, Boxes, Cpu, Gauge, LayoutDashboard, Shield, Workflow } from "lucide-react";

const links = [
  { to: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { to: "/alerts", label: "Alerts", icon: AlertTriangle },
  { to: "/incidents", label: "Incidents", icon: Shield },
  { to: "/assets", label: "Assets", icon: Boxes },
  { to: "/cases", label: "Cases", icon: Workflow },
  { to: "/coverage", label: "Coverage", icon: Gauge },
  { to: "/models", label: "Models", icon: Cpu },
];

export function Sidebar() {
  return (
    <aside className="sidebar">
      <div className="brand">
        <Activity size={18} />
        <span>XDR Console</span>
      </div>
      <nav className="nav-list">
        {links.map((link) => {
          const Icon = link.icon;
          return (
            <NavLink key={link.to} to={link.to} className={({ isActive }) => `nav-link ${isActive ? "active" : ""}`}>
              <Icon size={16} />
              <span>{link.label}</span>
            </NavLink>
          );
        })}
      </nav>
    </aside>
  );
}
