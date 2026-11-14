import { Cmd, Flag, Page, Panel, Row, Tbl } from "@/components/ui/lab-ui";
import { dt, fmt } from "@/lib/lab";
import { useLab } from "@/lib/data";

export default function Backups() {
  const D = useLab(), b = D.backup, r = b.last_run, c = D.cleanup, cl = c.last_run;
  const sched = D.automation.cron.find((x: any) => x.label.startsWith("Backup"));
  return (
    <Page title="Backup & Recovery" subtitle="Automated archives, integrity verification, proof that a restore works, and cleanup of old temp files.">
      <div className="grid gap-4 md:grid-cols-2">
        <Panel title="Latest backup run" desc={r ? `Finished ${dt(r.time)} in ${r.seconds} s` : "No backup has run on this server yet."}>
          {r ? (<>
            <Row k="Archive" v={r.file} /><Row k="Size" v={fmt(r.size)} /><Row k="Entries archived" v={r.files} />
            <Row k="SHA-256" v={<code className="break-all text-xs">{r.sha256}</code>} />
            <p className="pt-2 text-xs uppercase tracking-wide text-muted-foreground">Integrity verification</p>
            <Row k="gzip stream is intact" v={<Flag ok={r.gzip_ok} yes="passed" no="failed" />} />
            <Row k="Matches recorded SHA-256" v={<Flag ok={r.sha_ok} yes="passed" no="failed" />} />
            <p className="pt-2 text-xs uppercase tracking-wide text-muted-foreground">Restore demonstration</p>
            <Row k="Restored into a scratch folder" v={`${r.restored} of ${r.files} entries`} />
            <Row k="Random files compared with live copies" v={`${r.sampled} checked, ${r.mismatch} different`} />
            <Row k="Restore test" v={<Flag ok={r.restore_ok} yes="PASSED" no="FAILED" />} />
          </>) : <Cmd>sudo ./server/labctl backup --apply</Cmd>}
        </Panel>
        <Panel title="Configuration">
          <Row k="Backed up" v={b.sources.join(", ")} /><Row k="Stored in" v={b.dir} />
          <Row k="Schedule" v={sched ? <code>{sched.schedule}</code> : "not scheduled (sudo ./server/labctl cron --apply)"} />
          <Row k="Archives kept" v={`newest ${b.keep}`} />
          <Row k="Space used by archives" v={fmt(b.total_bytes)} /><Row k="Free space there" v={b.free === null ? "folder does not exist" : fmt(b.free)} />
          <p className="pt-2 text-xs uppercase tracking-wide text-muted-foreground">Do it by hand</p>
          <Cmd>{`sudo ./server/labctl backup --apply                       # backup + verify + restore test
sudo ./server/labctl backup verify                         # re-check the newest archive
sudo ./server/labctl backup restore FILE /some/dir --apply # restore for real`}</Cmd>
        </Panel>
      </div>
      <Panel title="Archives on disk"><Tbl head={["File", "Size", "Created", "Checksum file"]} rows={b.archives.map((a: any) => [a.file, fmt(a.size), dt(a.time), <Flag key={a.file} ok={a.checksum_file} />])} empty="No archives yet." /></Panel>
      <Panel title="Cleanup of old temp files" desc={`Files in ${c.dir} older than ${c.days} days are deleted.`}>
        <Row k="Last run" v={cl ? dt(cl.time) : "has not run yet"} />
        {cl && <Row k="Result" v={`${cl.removed} of ${cl.before} files removed, ${fmt(cl.freed)} freed`} />}
        <Row k="Waiting for the next run" v={c.current ? `${c.current.waiting} of ${c.current.files} files (${fmt(c.current.waiting_bytes)})` : "temp folder does not exist yet"} />
        <Cmd>sudo ./server/labctl cleanup --apply</Cmd>
      </Panel>
    </Page>
  );
}
