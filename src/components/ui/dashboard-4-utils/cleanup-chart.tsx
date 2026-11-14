import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from "recharts";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { fmt } from "@/lib/lab";
import { useLab } from "@/lib/data";

export function CleanupChart() {
  const c = useLab().cleanup, last = c.last_run;
  const data = last ? [{ name: `Removed (older than ${last.days} days)`, v: last.removed }, { name: "Kept", v: last.before - last.removed }] : [];
  const empty = !last || last.before === 0;
  return (
    <Card className="md:col-span-2">
      <CardHeader>
        <CardTitle className="text-lg">Last cleanup</CardTitle>
        <CardDescription>{last ? `${last.removed} of ${last.before} files in ${last.dir} removed · ${fmt(last.freed)} freed` : "Cleanup has not run on this server yet."}</CardDescription>
      </CardHeader>
      <CardContent className="h-56">
        {empty ? (
          <p className="text-sm text-muted-foreground">{last ? "The temp folder was empty, so there was nothing to clean." : <>Run <code>sudo ./server/labctl cleanup --apply</code> or let the cron schedule do it.</>}</p>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <PieChart><Tooltip /><Pie data={data} dataKey="v" nameKey="name" innerRadius={55} outerRadius={85} paddingAngle={3} isAnimationActive={false}>
              {data.map((_, i) => <Cell key={i} fill={`var(--chart-${i + 1})`} />)}</Pie></PieChart>
          </ResponsiveContainer>
        )}
      </CardContent>
    </Card>
  );
}
