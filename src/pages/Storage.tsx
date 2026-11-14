import { Cmd, Flag, Page, Panel, Row, Tbl } from "@/components/ui/lab-ui";
import { fmt } from "@/lib/lab";
import { useLab } from "@/lib/data";

function flat(devs: any[], depth = 0): any[] {
  return devs.flatMap((d) => [{ ...d, depth }, ...flat(d.children, depth + 1)]);
}

export default function Storage() {
  const D = useLab(), s = D.storage, rv = D.root_volume, lvm = s.lvm;
  const disks = s.disks ? flat(s.disks) : null;
  return (
    <Page title="Storage" subtitle="Disks, partitions, LVM, mounted file systems and the shared department folders.">
      {rv?.vg_free > 2 ** 30 && (
        <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-4 text-sm space-y-2">
          <p><b>{fmt(rv.vg_free)} of volume group {rv.vg} is unallocated.</b> “/” ({rv.lv}) is only {fmt(rv.lv_size)} of {fmt(rv.vg_size)}.</p>
          <Cmd>{`# in server/lab.conf:  EXTEND_ROOT=yes
sudo ./server/labctl storage root --apply`}</Cmd>
        </div>
      )}
      <Panel title="Disks and partitions" desc="Straight from lsblk: the physical size of each disk, not just the file system on it.">
        <Tbl head={["Device", "Type", "Size", "File system", "Mounted at"]}
          rows={(disks ?? []).map((d) => [<span key={d.name} style={{ paddingLeft: d.depth * 16 }}>{d.depth ? "└ " : ""}{d.name}{d.model ? ` (${d.model})` : ""}</span>, d.type, fmt(d.size), d.fstype ?? "—", d.mounts.join(", ") || "—"])}
          empty="lsblk is not available." />
      </Panel>
      <div className="grid gap-4 md:grid-cols-2">
        <Panel title="LVM" desc="Physical volumes → volume groups → logical volumes.">
          {lvm ? (<>
            <Tbl head={["Volume group", "Size", "Unallocated", "PVs", "LVs"]} rows={lvm.vgs.map((v: any) => [v.vg_name, fmt(v.vg_size), fmt(v.vg_free), v.pv_count, v.lv_count])} empty="No volume groups." />
            <Tbl head={["Logical volume", "Group", "Size"]} rows={lvm.lvs.map((l: any) => [l.lv_name, l.vg_name, fmt(l.lv_size)])} empty="No logical volumes." />
            <Tbl head={["Physical volume", "Group", "Size"]} rows={lvm.pvs.map((p: any) => [p.pv_name, p.vg_name || "—", fmt(p.pv_size)])} empty="No physical volumes." />
          </>) : <p className="text-muted-foreground">Unavailable: needs root and the lvm2 package.</p>}
          {s.data_disk && <p>Data disk configured in lab.conf: <code>{s.data_disk}</code> (apply with <code>sudo ./server/labctl storage disk --apply</code>).</p>}
        </Panel>
        <Panel title="Mounted file systems">
          <Tbl head={["Mount", "Device", "Type", "Used"]} rows={(s.mounts ?? []).map((m: any) => [m.target, m.source, m.fstype, `${fmt(m.used)} / ${fmt(m.size)} (${m.pct}%)`])} empty="No block-device mounts found." />
          <p className="pt-2 text-xs uppercase tracking-wide text-muted-foreground">/etc/fstab (mounted at boot)</p>
          <Tbl head={["Device", "Mount", "Type", "Options"]} rows={s.fstab.map((f: any) => [f.device, f.mount, f.type, f.options])} empty="fstab is empty." />
        </Panel>
      </div>
      <Panel title="Shared department folders" desc={`Under ${s.base}${s.base_mounted_separately ? " (its own mounted volume)" : " (same volume as /)"}. Mode 2770: only the department group can enter, setgid makes new files inherit the group, and a default ACL keeps them group-writable.`}>
        {s.shared.every((d: any) => !d.exists) && <><p className="text-muted-foreground">The folders do not exist yet.</p><Cmd>sudo ./server/labctl storage shared --apply</Cmd></>}
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {s.shared.filter((d: any) => d.exists).map((d: any) => (
            <div key={d.dept} className="rounded-xl border border-border p-4">
              <h3 className="text-lg font-semibold uppercase">{d.dept}</h3>
              <Row k="Mode" v={<>{d.mode} <Flag ok={d.mode === "2770"} yes="correct" no="expected 2770" /></>} />
              <Row k="Owner:group" v={`${d.owner}:${d.group}`} /><Row k="Setgid" v={d.setgid ? "yes" : "no"} />
              <Row k="Files" v={`${d.files} (${fmt(d.bytes)})`} />
              <code className="mt-2 block break-all text-xs text-muted-foreground">{d.path}</code>
              {d.acl && <pre className="mt-2 overflow-x-auto rounded bg-muted p-2 text-[11px]">{d.acl.join("\n")}</pre>}
            </div>))}
        </div>
        <div className="grid gap-3 sm:grid-cols-2 pt-2">
          {[["Lab temp folder (cleaned automatically)", s.tmp], ["Backup folder", s.backups_dir]].map(([t, d]: any) => (
            <div key={t} className="rounded-xl border border-border p-4"><h3 className="font-semibold">{t}</h3>
              {d.exists ? (<><Row k="Mode" v={d.mode} /><Row k="Owner:group" v={`${d.owner}:${d.group}`} /><Row k="Files" v={`${d.files} (${fmt(d.bytes)})`} /></>) : <p className="text-muted-foreground">does not exist yet</p>}</div>))}
        </div>
      </Panel>
    </Page>
  );
}
