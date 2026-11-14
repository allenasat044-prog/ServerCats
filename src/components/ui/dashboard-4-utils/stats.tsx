import { Badge } from "@/components/ui/badge";
import { Card } from "@/components/ui/card";
import { fmt } from "@/lib/lab";
import { useLab } from "@/lib/data";

// Real values from server/collect.py
export function DashboardStats() {
  const D = useLab(), r = D.resources;
  const who: string[] = D.who.map((l: string) => l.split(/\s+/)[0]);
  const items = [
    { label: "CPU usage", value: r.cpu.pct == null ? "—" : `${r.cpu.pct}%`, note: `${r.cpu.cores} core(s) · load ${r.cpu.load[0]}` },
    { label: "Memory", value: r.mem.pct == null ? "—" : `${r.mem.pct}%`, note: r.mem.pct == null ? "unavailable" : `${fmt(r.mem.used)} of ${fmt(r.mem.total)}` },
    { label: `Disk space (${r.disk.mount})`, value: `${r.disk.pct}%`, note: `${fmt(r.disk.used)} of ${fmt(r.disk.total)} on this volume` },
    { label: "Logged in now", value: String(who.length), note: who.length ? [...new Set(who)].join(", ") : "nobody" },
  ];
  return (<>{items.map((s) => (
    <Card key={s.label} className="flex flex-col gap-3 p-6">
      <p className="text-sm text-muted-foreground">{s.label}</p>
      <p className="text-3xl font-semibold tracking-tight">{s.value}</p>
      <Badge variant="secondary" className="w-fit max-w-full truncate">{s.note}</Badge>
    </Card>))}</>);
}
