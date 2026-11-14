import { Cmd, Flag, Level, Page, Panel, Row, Tbl } from "@/components/ui/lab-ui";
import { dt, na } from "@/lib/lab";
import { useLab } from "@/lib/data";

export default function System() {
  const s = useLab().system, n = s.network, up = s.updates;
  const installed = s.packages.filter((p: any) => p.version).length;
  return (
    <Page title="System" subtitle="Hostname, network, operating system updates and required software.">
      <div className="grid gap-4 md:grid-cols-2">
        <Panel title="Host">
          <Row k="Hostname" v={s.hostname} /><Row k="Operating system" v={s.os} /><Row k="Kernel" v={s.kernel} />
          <Row k="Time zone" v={na(s.timezone)} /><Row k="Uptime" v={s.uptime} /><Row k="Booted" v={dt(s.booted)} />
          {s.configured_hostname && s.configured_hostname !== s.hostname && <p className="text-amber-600">lab.conf wants “{s.configured_hostname}”. Apply it with <code>sudo ./server/labctl system hostname --apply</code>.</p>}
        </Panel>
        <Panel title="Network settings" desc={n.static_by_labctl ? "Static address configured by labctl (/etc/netplan/60-labserver.yaml)." : "Not configured by labctl: using the existing (automatic) configuration."}>
          <Row k="Default gateway" v={n.gateway ? `${n.gateway.via ?? "none"} via ${n.gateway.dev}` : "none"} />
          <Row k="DNS servers" v={n.dns.length ? n.dns.join(", ") : "none found"} />
          <Tbl head={["Interface", "State", "Addresses"]} rows={n.interfaces.map((i: any) => [i.name, i.state ?? "—", i.addresses.join(", ") || "none"])} empty="No network interfaces found (is the ip command installed?)" />
        </Panel>
        <Panel title="Operating system updates">
          <Row k="Packages that can be upgraded" v={up.pending === null ? "unavailable" : up.pending} />
          <Row k="…of which security updates" v={up.security === null ? "unavailable" : up.security} />
          <Row k="Package lists refreshed" v={dt(up.package_lists)} />
          <Row k="Last upgrade run by labctl" v={dt(up.last_upgrade)} />
          <Row k="Reboot required" v={<Flag ok={up.reboot_required == null ? null : !up.reboot_required} yes="no" no="yes" />} />
          <Cmd>sudo ./server/labctl system update --apply</Cmd>
        </Panel>
        <Panel title="Required software" desc={s.packages.length ? `${installed} of ${s.packages.length} packages from PACKAGES in server/lab.conf are installed.` : "The package list in server/lab.conf is for apt (Ubuntu/Debian) and is not checked on this computer."}>
          <Tbl head={["Package", "Version", "Status"]} rows={s.packages.map((p: any) => [p.name, p.version ?? "—", <Level key={p.name} level={p.version ? "pass" : "fail"} label={p.version ? "installed" : "missing"} />])} />
          {installed < s.packages.length && <Cmd>sudo ./server/labctl system packages --apply</Cmd>}
        </Panel>
      </div>
    </Page>
  );
}
