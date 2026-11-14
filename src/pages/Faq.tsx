import Faqs02 from "@/components/ui/faqs-02";
import TeamTabs from "@/components/ui/team-tabs";
import { GITHUB, TEAM } from "@/lib/lab";

const faqs = [
  { q: "Where do the numbers come from?", a: "Only from the server itself. server/collect.py reads the real machine (hostname, disks, LVM, users, cron, backups, firewall, SSH) and writes public/data.json. The site contains no built-in sample values; anything it cannot read is shown as unavailable." },
  { q: "How do I get fresh numbers?", a: "On the server run: sudo ./server/labctl status. For automatic updates install the schedule once with sudo ./server/labctl cron --apply (it refreshes every 5 minutes by default). The pages re-read the file every 10 seconds." },
  { q: "How do I set the server up?", a: "Edit server/lab.conf, then run ./server/labctl all to see a plan and sudo ./server/labctl all --apply to do it. Order: system (hostname, network, updates, packages), storage (LVM, mounts, shared folders), users, security, backup, cleanup, cron. Every module also runs on its own." },
  { q: "Why is my disk shown smaller than its real size?", a: "Ubuntu’s installer puts the root file system on an LVM volume that often uses only about half of the disk. The rest stays unallocated in the volume group. The Dashboard and Storage pages show this, and sudo ./server/labctl storage root --apply (with EXTEND_ROOT=yes) grows / to use it." },
  { q: "How are student passwords handled?", a: "Each account gets its own random one-time password, written to /var/lib/labserver/initial-passwords.csv (root only), and must be changed at first login. Passwords expire after the number of days in lab.conf and must meet the pwquality rules. Delete the CSV after handing the passwords out." },
  { q: "Who can open which folder?", a: "Only members of that department’s group. Department folders are mode 2770 with a default ACL, so new files stay group-writable. Student home directories are mode 750. See Storage and Security." },
  { q: "How do backups and restores work?", a: "Each run creates a tar.gz with a SHA-256 checksum, tests the gzip stream, verifies the checksum, then restores the whole archive into a scratch folder, compares the entry count and compares random files with the live copies. Only the newest few archives are kept." },
  { q: "What does cleanup delete?", a: "Only files in the lab temp folder (/srv/lab/tmp by default) older than CLEANUP_DAYS, 7 unless you change it. Nothing else is touched." },
  { q: "Can the scripts lock me out or wipe a disk?", a: "They are built not to. Nothing changes without --apply. SSH is allowed in the firewall before it is enabled; password SSH login is only disabled if an admin already has a key; the SSH config is validated and reverted if sshd rejects it; a static IP uses netplan try with a rollback timer; and a disk with partitions or mounts is refused unless you add --force." },
];

export default function Faq() {
  return <div className="pt-12"><Faqs02 faqs={faqs} githubUrl={GITHUB} title="How to use LabServer" intro="The scripts in server/ do the real work; this site displays what they find on the machine." /><TeamTabs members={TEAM} /></div>;
}
