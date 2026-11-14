import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { Outlet } from "react-router-dom";
import { Card } from "@/components/ui/card";

// The site shows ONLY what server/collect.py wrote to public/data.json. Nothing is bundled or hard-coded.
export type LabData = any;
type State = { data: LabData | null; loading: boolean };
export const LabContext = createContext<State>({ data: null, loading: true });
const URL_ = `${import.meta.env.BASE_URL}data.json`;

export function LabProvider({ children }: { children: ReactNode }) {
  const [s, setS] = useState<State>({ data: null, loading: true });
  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const r = await fetch(`${URL_}?t=${Date.now()}`, { cache: "no-store" });
        const j = r.ok ? await r.json() : null; // a missing file may be answered with index.html: not JSON
        if (alive) setS((p) => ({ data: j ?? p.data, loading: false }));
      } catch {
        if (alive) setS((p) => ({ data: p.data, loading: false })); // keep the last good data on a hiccup
      }
    };
    load();
    const id = setInterval(load, 10000);
    return () => { alive = false; clearInterval(id); };
  }, []);
  return <LabContext.Provider value={s}>{children}</LabContext.Provider>;
}

export const useLab = (): LabData => {
  const { data } = useContext(LabContext);
  if (!data) throw new Error("useLab used outside LabGate");
  return data;
};

// Layout route: renders the page only when real data exists, otherwise explains how to create it.
export function LabGate() {
  const { data, loading } = useContext(LabContext);
  if (loading) return <p className="p-4 pt-28 text-center text-muted-foreground">Loading server data…</p>;
  if (!data)
    return (
      <div className="mx-auto max-w-2xl p-4 pt-28">
        <Card className="space-y-3 p-6">
          <h1 className="text-2xl font-semibold">No server data yet</h1>
          <p className="text-sm text-muted-foreground">This site only shows real measurements, and none have been collected. On the Linux server, in the project folder, run:</p>
          <pre className="overflow-x-auto rounded-lg bg-muted p-3 text-xs">sudo ./server/labctl status</pre>
          <p className="text-sm text-muted-foreground">It reads the machine and writes <code>public/data.json</code>. To keep it fresh automatically, install the schedule with <code>sudo ./server/labctl cron --apply</code>. If the website runs on another computer, copy <code>public/data.json</code> from the server into the same folder here.</p>
        </Card>
      </div>
    );
  const ageMin = Math.round((Date.now() / 1000 - data.generated) / 60);
  return (
    <>
      {ageMin > 15 && (
        <div className="mx-auto max-w-6xl px-4 pt-24 -mb-20">
          <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-3 text-sm">These numbers are {ageMin} minutes old (collected {data.time}). Run <code>sudo ./server/labctl status</code> or check that the cron schedule is installed.</div>
        </div>
      )}
      <Outlet />
    </>
  );
}
