import { Cmd, Flag, Page, Panel, Row, Tbl } from "@/components/ui/lab-ui";
import { dt } from "@/lib/lab";
import { useLab } from "@/lib/data";

export default function Automation() {
  const D = useLab(), a = D.automation, last = (x: any) => dt(x?.time);
  return (
    <Page title="Automation" subtitle="Shell scripts for routine administration, run on a schedule by cron.">
      <div className="grid gap-4 md:grid-cols-2">
        <Panel title="Scheduled tasks" desc="/etc/cron.d/labserver, written by labctl cron from the schedules in server/lab.conf.">
          <Row k="Cron service" v={<Flag ok={a.cron_service ? a.cron_service === "active" : null} yes="running" no={a.cron_service ?? "stopped"} />} />
          <Row k="Schedule file installed" v={<Flag ok={a.cron_file} />} />
          <Tbl head={["When (m h dom mon dow)", "Task", "Command"]} rows={a.cron.map((c: any) => [<code key={c.command}>{c.schedule}</code>, c.label, <code key={c.command + "c"} className="break-all text-xs">{c.command}</code>])}
            empty="No schedule installed yet." />
          {!a.cron_file && <Cmd>sudo ./server/labctl cron --apply</Cmd>}
          {a.root_crontab.length > 0 && <><p className="pt-2 text-xs uppercase tracking-wide text-muted-foreground">root’s own crontab</p>
            <Tbl head={["When", "Command"]} rows={a.root_crontab.map((c: any) => [<code key={c.command}>{c.schedule}</code>, <code key={c.command + "c"} className="break-all text-xs">{c.command}</code>])} /></>}
        </Panel>
        <Panel title="Last runs" desc="Recorded by the scripts themselves in /var/lib/labserver.">
          <Row k="Website data refreshed" v={D.time} />
          <Row k="Backup" v={last(D.backup.last_run)} />
          <Row k="Cleanup" v={last(D.cleanup.last_run)} />
          <Row k="OS upgrade" v={dt(D.system.updates.last_upgrade)} />
          <Row k="Log file" v={a.log.exists ? `${a.log.path} (last write ${dt(a.log.modified)})` : "not created yet"} />
          {a.log.tail && <pre className="max-h-48 overflow-auto rounded-lg bg-neutral-900 p-3 text-[11px] text-green-300">{a.log.tail.join("\n")}</pre>}
        </Panel>
      </div>
      <Panel title="Administration scripts" desc="Every script prints a plan by default and only changes the system with --apply.">
        <Tbl head={["Script", "What it does", "Run it"]} rows={a.modules.map((m: any) => [<code key={m.name}>{m.name}</code>, m.description || "—", <code key={m.name + "r"} className="text-xs">sudo ./server/labctl {m.name.replace(".sh", "")} --apply</code>])} />
        <Cmd>{`./server/labctl all            # dry-run of everything, in the right order
sudo ./server/labctl all --apply`}</Cmd>
      </Panel>
    </Page>
  );
}
