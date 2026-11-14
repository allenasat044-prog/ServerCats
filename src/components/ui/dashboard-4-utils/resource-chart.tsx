import { Bar, BarChart, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useLab } from "@/lib/data";

export function ResourceChart() {
  const D = useLab(), r = D.resources;
  const data = [{ name: "CPU", v: r.cpu.pct ?? 0 }, { name: "Memory", v: r.mem.pct ?? 0 }, { name: `Disk (${r.disk.mount})`, v: r.disk.pct }];
  return (
    <Card className="md:col-span-2 lg:col-span-4">
      <CardHeader><CardTitle className="text-lg">Resource usage</CardTitle><CardDescription>Collected {D.time} on {D.system.hostname}</CardDescription></CardHeader>
      <CardContent className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data}>
            <XAxis dataKey="name" tickLine={false} axisLine={false} /><YAxis domain={[0, 100]} unit="%" tickLine={false} axisLine={false} width={44} />
            <Tooltip formatter={(v) => `${v}%`} />
            <Bar dataKey="v" radius={[10, 10, 0, 0]} isAnimationActive={false}>{data.map((_, i) => <Cell key={i} fill={`var(--chart-${i + 1})`} />)}</Bar>
          </BarChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  );
}
