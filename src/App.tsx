import { NavLink, Route, Routes, useLocation } from "react-router-dom";
import { FloatingPathsBackground } from "@/components/ui/floating-paths";
import Landing from "@/pages/Landing";
import Dashboard from "@/pages/Dashboard";
import System from "@/pages/System";
import Automation from "@/pages/Automation";
import Security from "@/pages/Security";
import Backups from "@/pages/Backups";
import { LabGate } from "@/lib/data";
import Storage from "@/pages/Storage";
import Users from "@/pages/Users";
import Faq from "@/pages/Faq";
import { cn } from "@/lib/utils";

export const NAV = [["/", "Home"], ["/dashboard", "Dashboard"], ["/system", "System"], ["/users", "Users & Groups"], ["/storage", "Storage"], ["/automation", "Automation"], ["/backups", "Backup & Recovery"], ["/security", "Security"], ["/faq", "FAQ"]] as const;

// Animated paths behind every page except the landing page
function PageBackground() {
  return (
    <div className="pointer-events-none fixed inset-0 -z-10 bg-background">
      <FloatingPathsBackground position={1} className="absolute inset-0" pathClassName="text-teal-700 dark:text-teal-300" />
      <FloatingPathsBackground position={-1} className="absolute inset-0" pathClassName="text-cyan-700 dark:text-cyan-300" />
    </div>
  );
}

export default function App() {
  const { pathname } = useLocation();
  return (
    <>
      {pathname !== "/" && <PageBackground />}
      <nav className="fixed inset-x-0 top-0 z-50 flex flex-wrap justify-center gap-1.5 border-b border-border bg-background/80 p-3 backdrop-blur">
        {NAV.map(([to, label]) => (
          <NavLink key={to} to={to} end className={({ isActive }) => cn("rounded-full border-2 border-transparent px-4 py-1.5 text-sm font-semibold transition hover:border-primary", isActive && "bg-primary text-primary-foreground")}>{label}</NavLink>
        ))}
      </nav>
      <Routes>
        <Route path="/" element={<Landing />} />
        <Route element={<LabGate />}>
          <Route path="/dashboard" element={<Dashboard />} /><Route path="/system" element={<System />} />
          <Route path="/users" element={<Users />} /><Route path="/storage" element={<Storage />} />
          <Route path="/automation" element={<Automation />} /><Route path="/backups" element={<Backups />} />
          <Route path="/security" element={<Security />} />
        </Route>
        <Route path="/faq" element={<Faq />} />
      </Routes>
    </>
  );
}
