import { Cmd, Flag, Level, Page, Panel, Stat, Tbl } from "@/components/ui/lab-ui";
import { dt } from "@/lib/lab";
import { useLab } from "@/lib/data";

const yn = (v: string) => (v === "yes" ? true : v === "no" ? false : null);

export default function Testing() {
  const D = useLab(), t = D.testing;
  const rows = (task: string) => (t?.results ?? []).filter((r: any) => r.task === task).map((r: any) => [r.name, <Level key={r.name} level={r.level} />, <span key={r.name + "d"} className="text-muted-foreground">{r.detail}</span>]);
  return (
    <Page title="Testing & Troubleshooting" subtitle="Verify every service, fix simulated faults, and validate the expected outputs.">
      {!t ? (
        <Panel title="No test run recorded yet" desc="Run the tests on the Linux server, then refresh the data.">
          <Cmd>{`sudo ./server/labctl test --apply     # verify + fix simulated faults + validate
sudo ./server/labctl status           # refresh this page`}</Cmd>
        </Panel>
      ) : (<>
        <div className="grid gap-4 sm:grid-cols-4">
          <Stat label="Passed" value={t.pass} /><Stat label="Warnings" value={t.warn} /><Stat label="Failed" value={t.fail} /><Stat label="Last run" value={<span className="text-xl">{dt(t.time)}</span>} />
        </div>
        <Panel title="1. Verify all configured services" desc="Services, network, packages, groups, folders, mounts, schedule and backup."><Tbl head={["Check", "Result", "Detail"]} rows={rows("verify")} empty="Not run." /></Panel>
        <Panel title="2. Resolve simulated system issues" desc="Each fault is created on purpose, detected, repaired and confirmed gone.">
          <Tbl head={["Issue", "Injected", "Detected", "Fixed", "Confirmed gone"]} rows={(t.issues ?? []).map((i: any) => [
            <div key={i.id}><div className="font-medium">{i.title}</div><div className="text-xs text-muted-foreground">{i.what}{i.note ? ` (${i.note})` : ""}</div></div>,
            <Flag key="a" ok={yn(i.injected)} />, <Flag key="b" ok={yn(i.detected)} />, <Flag key="c" ok={yn(i.fixed)} />, <Flag key="d" ok={yn(i.validated)} />])}
            empty={D.platform === "darwin" ? "The fault-fixing demo runs on the Linux lab server (sudo ./server/labctl test --apply)." : "Not run yet: sudo ./server/labctl test troubleshoot --apply"} />
        </Panel>
        <Panel title="3. Validate expected outputs" desc="Values from lab.conf compared with what the system really reports."><Tbl head={["Check", "Result", "Detail"]} rows={rows("validate")} empty="Not run." /></Panel>
        <Panel title="Run it again"><Cmd>{`sudo ./server/labctl test                       # verify + validate (read-only), plan for faults
sudo ./server/labctl test --apply               # also run the fault-fixing demo
sudo ./server/labctl test troubleshoot --apply  # only the demo`}</Cmd></Panel>
      </>)}
    </Page>
  );
}
