import { Cmd, Level, Page, Panel, Row, Stat, Tbl } from "@/components/ui/lab-ui";
import { NeedsRoot } from "@/components/ui/lab-ui";
import { useLab } from "@/lib/data";

export default function Security() {
  const D = useLab(), s = D.security, fw = s.firewall, ssh = s.ssh;
  const n = (l: string) => s.checks.filter((c: any) => c.level === l).length;
  return (
    <Page title="Security" subtitle="Firewall, SSH access and file permissions, checked on the live system.">
      <NeedsRoot root={D.root} />
      <div className="grid gap-4 sm:grid-cols-4">
        <Stat label="Passed" value={n("pass")} /><Stat label="Warnings" value={n("warn")} /><Stat label="Failed" value={n("fail")} /><Stat label="Unreadable" value={n("unknown")} />
      </div>
      <Panel title="Checks">
        <Tbl head={["Check", "Result", "Detail"]} rows={s.checks.map((c: any) => [c.title, <Level key={c.id} level={c.level} />, <span key={c.id + "d"} className="text-muted-foreground">{c.detail}</span>])} />
        {(n("fail") > 0 || n("warn") > 0) && <Cmd>{`./server/labctl security             # see what would change
sudo ./server/labctl security --apply`}</Cmd>}
      </Panel>
      <div className="grid gap-4 md:grid-cols-2">
        <Panel title={fw.kind === "macos" ? "Firewall (macOS)" : "Firewall (ufw)"}>
          {!fw.installed ? <p>ufw is not installed. <code>sudo ./server/labctl system packages --apply</code></p> : !fw.readable ? <p className="text-muted-foreground">Unreadable without root.</p> : (<>
            <Row k="Status" v={<Level level={fw.active ? "pass" : fw.kind === "macos" ? "warn" : "fail"} label={fw.kind === "macos" ? (fw.active ? "on" : "off") : fw.active ? "active" : "inactive"} />} /><Row k="Defaults" v={fw.defaults ?? "unavailable"} />
            {fw.kind === "macos" ? <p className="text-muted-foreground">macOS filters per application rather than by port rules.</p> : <Tbl head={["To", "Action", "From"]} rows={(fw.rules ?? []).map((r: any) => [r.to, r.action, r.from])} empty="No rules." />}
          </>)}
        </Panel>
        <Panel title={D.platform === "darwin" ? "SSH server (Remote Login)" : "SSH server"} desc={`Effective settings from ${ssh.source ?? "sshd -T"} (hardening lives in /etc/ssh/sshd_config.d/00-labserver.conf).`}>
          <Row k="Service" v={ssh.service ?? "unavailable"} />
          {ssh.config ? Object.entries(ssh.config).map(([k, v]) => <Row key={k} k={k} v={String(v)} />) : <p className="text-muted-foreground">Unavailable: needs root and openssh-server.</p>}
        </Panel>
      </div>
      <Panel title="Listening TCP ports" desc="Everything on this machine that accepts connections.">
        <Tbl head={["Address", "Port"]} rows={s.listening.map((p: any) => [p.address, p.port])} empty="Unavailable (the ss command is missing) or nothing is listening." />
      </Panel>
    </Page>
  );
}
