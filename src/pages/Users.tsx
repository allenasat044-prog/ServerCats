import { Cmd, Level, Page, Panel, Row, Stat, Tbl } from "@/components/ui/lab-ui";
import { na } from "@/lib/lab";
import { useLab } from "@/lib/data";

const pw: Record<string, [string, string]> = { set: ["pass", "set"], "must change": ["warn", "must change at first login"], locked: ["fail", "locked"], empty: ["fail", "EMPTY"] };

export default function Users() {
  const u = useLab().users, p = u.policy;
  return (
    <Page title="Users & Groups" subtitle="Accounts, groups, passwords and who owns what.">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Student accounts" value={u.students.length} note={u.roster ? `${u.roster.count} in the roster` : "no roster file yet"} />
        <Stat label="Groups" value={u.groups.length} note="lab-* groups" />
        <Stat label="Must change password" value={u.password_states_readable ? u.must_change : "—"} note={u.password_states_readable ? "have not logged in yet" : "needs root to read"} />
        <Stat label="Administrators" value={u.admins.length} note={u.admins.join(", ") || "sudo group is empty"} />
      </div>
      {u.students.length === 0 && (
        <Panel title="No student accounts yet">
          <p>Create the roster, review it, then create the accounts:</p>
          <Cmd>{`./server/labctl users generate-roster 100     # or write server/students.csv yourself
sudo ./server/labctl storage shared --apply     # groups + shared folders
sudo ./server/labctl users --apply`}</Cmd>
        </Panel>
      )}
      <div className="grid gap-4 md:grid-cols-2">
        <Panel title="Groups" desc="One group per department, plus lab-students for everyone.">
          <Tbl head={["Group", "GID", "Members"]} rows={u.groups.map((g: any) => [g.name, g.gid, g.members])} empty="No lab-* groups exist yet." />
        </Panel>
        <Panel title="Password policy">
          <Row k="Initial password" v="random per account, forced change at first login" />
          <Row k="Maximum age" v={p.max_days ? `${p.max_days} days` : "unavailable"} />
          <Row k="Complexity (pwquality)" v={p.pwquality ? `minimum length ${na(p.minlen)}, needs digit, upper and lower case` : "not configured"} />
          <Row k="Locked accounts" v={u.password_states_readable ? u.locked : "unavailable"} />
          {u.initial_passwords_file && <p className="text-amber-600">One-time passwords are still stored in <code>{u.initial_passwords_file}</code>. Hand them out, then delete the file.</p>}
        </Panel>
      </div>
      {u.roster && (u.roster.missing_count > 0 || u.roster.extra_count > 0) && (
        <Panel title="Roster differences">
          {u.roster.missing_count > 0 && <p>{u.roster.missing_count} in server/students.csv but no account yet: {u.roster.missing.join(", ")}{u.roster.missing_count > 20 ? " …" : ""}</p>}
          {u.roster.extra_count > 0 && <p>{u.roster.extra_count} accounts exist that are not in the roster: {u.roster.extra.join(", ")}{u.roster.extra_count > 20 ? " …" : ""}</p>}
        </Panel>
      )}
      <Panel title="Student accounts" desc="Home directories are mode 750: owner and group only.">
        <div className="max-h-96 overflow-y-auto">
          <Tbl head={["User", "Name", "Department", "Home mode", "Password"]}
            rows={u.students.map((s: any) => [s.user, s.name, s.dept.toUpperCase(), s.home_mode ?? "—", s.password ? <Level key={s.user} level={pw[s.password][0]} label={pw[s.password][1]} /> : "unavailable"])} />
        </div>
      </Panel>
    </Page>
  );
}
