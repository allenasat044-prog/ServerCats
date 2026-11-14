import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useLab } from "@/lib/data";

export function DepartmentChart() {
  const u = useLab().users, max = Math.max(...u.departments.map((d: any) => d.students), 1);
  return (
    <Card>
      <CardHeader><CardTitle className="text-lg">Students by department</CardTitle><CardDescription>{u.students.length} student accounts</CardDescription></CardHeader>
      <CardContent className="flex flex-col gap-3">
        {u.departments.map((f: any, i: number) => (
          <div key={f.dept}>
            <div className="flex justify-between text-sm"><span className="font-medium uppercase">{f.dept}</span><span className="text-muted-foreground">{f.students}</span></div>
            <div className="h-2 rounded-full bg-muted"><div className="h-2 rounded-full" style={{ width: `${(f.students / max) * 100}%`, background: `var(--chart-${(i % 5) + 1})` }} /></div>
          </div>))}
      </CardContent>
    </Card>
  );
}
