import type { ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { useLab } from "@/lib/data";

export function Page({ title, subtitle, children }: { title: string; subtitle?: ReactNode; children: ReactNode }) {
  return (
    <div className="mx-auto max-w-6xl space-y-4 p-4 pt-24 text-foreground">
      <div><h1 className="text-3xl font-semibold tracking-tight">{title}</h1>{subtitle && <p className="text-sm text-muted-foreground">{subtitle}</p>}</div>
      {children}
    </div>
  );
}

export function Panel({ title, desc, className, children }: { title: string; desc?: ReactNode; className?: string; children: ReactNode }) {
  return (
    <Card className={className}>
      <CardHeader><CardTitle className="text-lg">{title}</CardTitle>{desc && <CardDescription>{desc}</CardDescription>}</CardHeader>
      <CardContent className="space-y-3 text-sm">{children}</CardContent>
    </Card>
  );
}

export function Row({ k, v }: { k: string; v: ReactNode }) {
  return <div className="flex justify-between gap-4 border-b border-border/60 py-1.5 last:border-0"><span className="text-muted-foreground">{k}</span><span className="text-right font-medium">{v ?? "unavailable"}</span></div>;
}

export function Stat({ label, value, note }: { label: string; value: ReactNode; note?: ReactNode }) {
  return <Card className="p-5"><p className="text-sm text-muted-foreground">{label}</p><p className="text-3xl font-semibold tracking-tight">{value}</p>{note && <p className="mt-1 truncate text-xs text-muted-foreground">{note}</p>}</Card>;
}

const tone: Record<string, string> = {
  pass: "border-transparent bg-emerald-500/15 text-emerald-700 dark:text-emerald-300",
  warn: "border-transparent bg-amber-500/20 text-amber-700 dark:text-amber-300",
  fail: "border-transparent bg-red-500/15 text-red-700 dark:text-red-300",
  unknown: "border-transparent bg-muted text-muted-foreground",
};
export const Level = ({ level, label }: { level: string; label?: string }) => <Badge className={cn("whitespace-nowrap", tone[level] ?? tone.unknown)}>{label ?? ({ pass: "pass", warn: "warning", fail: "fail", unknown: "unreadable" } as any)[level] ?? level}</Badge>;
export const Flag = ({ ok, yes = "yes", no = "no" }: { ok: boolean | null | undefined; yes?: string; no?: string }) => ok == null ? <Level level="unknown" /> : <Level level={ok ? "pass" : "fail"} label={ok ? yes : no} />;

export function Tbl({ head, rows, empty = "Nothing to show yet." }: { head: string[]; rows: ReactNode[][]; empty?: string }) {
  if (!rows.length) return <p className="text-muted-foreground">{empty}</p>;
  return (
    <div className="overflow-x-auto"><table className="w-full text-left text-sm">
      <thead><tr className="border-b text-xs uppercase tracking-wide text-muted-foreground">{head.map((h) => <th key={h} className="py-2 pr-4 font-medium">{h}</th>)}</tr></thead>
      <tbody>{rows.map((r, i) => <tr key={i} className="border-b border-border/60 last:border-0">{r.map((c, j) => <td key={j} className="py-2 pr-4 align-top">{c}</td>)}</tr>)}</tbody>
    </table></div>
  );
}

export const Cmd = ({ children }: { children: ReactNode }) => <pre className="overflow-x-auto rounded-lg bg-muted p-3 text-xs">{children}</pre>;

export function NeedsRoot({ root }: { root: boolean }) {
  const D = useLab();
  // On a Mac the collector reads what macOS offers without root and the pages label the rest, so no warning is needed
  if (root || D.platform === "darwin") return null;
  return <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-3 text-sm">The collector ran without root, so firewall, SSH, LVM and password details are unavailable. Run <code>sudo ./server/labctl status</code> (or let the cron schedule do it).</div>;
}
