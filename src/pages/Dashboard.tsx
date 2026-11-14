import { useState } from "react";
import Dashboard from "@/components/ui/dashboard-4";
import { downloadReport } from "@/components/ui/dashboard-4-utils/quick-actions";
import { Button } from "@/components/ui/button";
import { Cmd, NeedsRoot, Page, Panel } from "@/components/ui/lab-ui";
import { fmt } from "@/lib/lab";
import { useLab } from "@/lib/data";

export default function DashboardPage() {
  const D = useLab(), [open, setOpen] = useState(true);
  const rv = D.root_volume, unalloc = rv?.vg_free ?? 0;
  return (
    <Page title="Dashboard" subtitle={`${D.system.os} · up ${D.system.uptime}`}>
      <NeedsRoot root={D.root} />
      {unalloc > 2 ** 30 && (
        <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-4 text-sm space-y-2">
          <p><b>Part of your disk is not in use.</b> The root volume “/” is {fmt(D.resources.disk.total)}, but its volume group {rv.vg} is {fmt(rv.vg_size)} and {fmt(unalloc)} of it is not allocated to any volume. Ubuntu’s installer does this by default (it uses about half of the disk).</p>
          <p>To give “/” all of it, set <code>EXTEND_ROOT=yes</code> in <code>server/lab.conf</code>, then:</p>
          <Cmd>sudo ./server/labctl storage root --apply</Cmd>
        </div>
      )}
      <Dashboard />
      <Panel title="Terminal output" desc="Exactly what server/collect.py printed on its last run.">
        <div className="flex gap-2"><Button onClick={() => setOpen(!open)} variant="secondary">{open ? "Hide output" : "Show output"}</Button><Button onClick={() => downloadReport(D.report)}>Download .txt</Button></div>
        {open && <pre className="overflow-x-auto rounded-lg bg-neutral-900 p-4 font-mono text-xs text-green-300">{D.report}</pre>}
        {D.errors?.length > 0 && <pre className="rounded-lg bg-red-500/10 p-3 text-xs">{D.errors.join("\n")}</pre>}
      </Panel>
    </Page>
  );
}
