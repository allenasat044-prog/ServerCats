import { Link } from "react-router-dom";
import Skiper39 from "@/components/ui/skiper39";
import { NAV } from "@/App";

export default function Landing() {
  return (
    <div className="relative h-screen w-full">
      <Skiper39 />
      <div className="pointer-events-none absolute inset-x-0 top-36 z-10 flex flex-col items-center gap-4 px-6 text-center">
        <h1 className="max-w-3xl text-4xl font-semibold tracking-tight text-neutral-900 sm:text-6xl" style={{ letterSpacing: "-0.04em", lineHeight: 1.02 }}>One server. A whole college lab.</h1>
        <p className="max-w-xl text-sm text-neutral-600 sm:text-base">Accounts, storage, automation, backups and security for a whole student lab, run by scripts and shown with real numbers.</p>
        <div className="pointer-events-auto mt-2 flex flex-wrap justify-center gap-2">
          {NAV.slice(1).map(([to, label]) => (
            <Link key={to} to={to} className="rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground shadow-sm transition hover:scale-105">{label}</Link>))}
        </div>
      </div>
    </div>
  );
}
