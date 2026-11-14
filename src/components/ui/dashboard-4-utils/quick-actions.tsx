import { ChevronRight, Download, HardDrive, ShieldCheck } from "lucide-react";
import { Link } from "react-router-dom";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { useLab } from "@/lib/data";

export function downloadReport(report: string) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([report], { type: "text/plain" }));
  a.download = `lab-health-report-${Date.now()}.txt`; a.click();
}

export function QuickActions() {
  const D = useLab();
  const row = "flex w-full items-center gap-3 rounded-lg p-3 text-left text-sm hover:bg-muted";
  return (
    <Card>
      <CardHeader><CardTitle className="text-lg">Quick actions</CardTitle><CardDescription>Report and shortcuts.</CardDescription></CardHeader>
      <CardContent className="flex flex-col gap-1">
        <button className={row} onClick={() => downloadReport(D.report)}><Download className="size-4" /><span className="flex-1 font-medium">Download report</span><ChevronRight className="size-4" /></button>
        <Link className={row} to="/backups"><HardDrive className="size-4" /><span className="flex-1 font-medium">Backup & recovery</span><ChevronRight className="size-4" /></Link>
        <Link className={row} to="/security"><ShieldCheck className="size-4" /><span className="flex-1 font-medium">Security checks</span><ChevronRight className="size-4" /></Link>
      </CardContent>
    </Card>
  );
}
