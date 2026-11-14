# LabServer: a Linux server for a college computer lab

Scripts that configure and run an Ubuntu lab server for 100 student accounts, plus a website that
shows the **real** state of that server. Nothing on the site is built in: every number comes from
`server/collect.py`, which reads the machine and writes `public/data.json`.

## Which computer runs what

| Part | Linux server / VM (Ubuntu) | macOS | Windows |
|---|---|---|---|
| **Admin scripts** `system`, `users`, `storage`, `cron` | yes, this is what they are for | **no**: they refuse to run and change nothing | **no**: run them inside WSL or a Linux VM |
| **Admin scripts** `security`, `backup`, `cleanup` | yes | **yes**, macOS versions (macOS firewall, SSH hardening, tar backup in `/Users/Shared/lab`) | run them inside WSL or a Linux VM |
| **`labctl all`** | plan / apply everything, then verify + validate | security + backup + cleanup, then tests this Mac and collects data | run it inside WSL / the VM |
| **`labctl test`** | verify services, fix simulated faults, validate outputs | read-only checks of this Mac and the website | run it inside WSL / the VM |
| **Collector** (`labctl status`) | full data | real values of the Mac (firewall, Remote Login/SSH, disks, network), Linux-only items shown as unavailable | run it inside WSL / the VM |
| **Website** (`npm run dev`) | yes | yes | yes |
| `labctl users generate-roster N` | yes | yes | in WSL / Git Bash |

The lab server is a Linux machine (apt, useradd, LVM, ufw, cron). A Mac or Windows PC is where you can
develop and view the website, and where you can run a Linux VM for the server part.

## Command cheat sheet: Windows, Linux, macOS

The commands are almost the same; only the shell and the package manager differ.
`<project>` is the folder you cloned or unzipped (for example `~/labserver`).

| Task | Linux (Ubuntu server) | macOS (Terminal) | Windows (PowerShell) |
|---|---|---|---|
| Install Node.js | `sudo apt install nodejs npm` | `brew install node` | `winget install OpenJS.NodeJS.LTS` |
| Go to the project | `cd ~/labserver` | `cd ~/labserver` | `cd $HOME\labserver` |
| Install website deps | `npm install` | `npm install` | `npm install` |
| Collect real data | `sudo ./server/labctl status` | `./server/labctl status` | `wsl sudo ./server/labctl status` |
| Run the checks | `sudo ./server/labctl test` | `./server/labctl test` | `wsl sudo ./server/labctl test` |
| Everything, dry run | `./server/labctl all` | `./server/labctl all` (read-only) | `wsl ./server/labctl all` |
| Everything, for real | `sudo ./server/labctl all --apply` | `sudo ./server/labctl all --apply` (security, backup, cleanup only) | `wsl sudo ./server/labctl all --apply` |
| Backup now | `sudo ./server/labctl backup --apply` | `sudo ./server/labctl backup --apply` | `wsl sudo ./server/labctl backup --apply` |
| Harden (firewall, SSH) | `sudo ./server/labctl security --apply` | `sudo ./server/labctl security --apply` | `wsl sudo ./server/labctl security --apply` |
| Fault-fixing demo | `sudo ./server/labctl test --apply` | not possible (use a VM) | `wsl sudo ./server/labctl test --apply` |
| Start the website | `npm run dev -- --host` | `npm run dev` | `npm run dev` |
| Open the website | `http://<server-ip>:5173` | `http://localhost:5173` | `http://localhost:5173` |
| Make scripts executable | `chmod +x server/labctl server/modules/*.sh` | `chmod +x server/labctl server/modules/*.sh` | not needed (WSL: same as Linux) |
| Fix `^M` line endings | `sed -i 's/\r$//' server/labctl server/lib/*.sh server/modules/*.sh` | `sed -i '' 's/\r$//' server/labctl server/lib/*.sh server/modules/*.sh` | run the Linux command inside WSL |

Windows: the `wsl ...` commands need WSL2 with Ubuntu and the project inside the Linux file system (see the Windows section below).

## What is covered

| Area | What it does | Where |
|---|---|---|
| **System configuration** | hostname, static network (netplan, with rollback timer), OS update, required packages | `labctl system [hostname\|network\|update\|packages]` |
| **Users & groups** | `lab-<dept>` groups + `lab-students`, accounts from a roster, random one-time passwords with forced change, password ageing and complexity (pwquality), ownership and 750 homes | `labctl users [groups\|policy\|accounts\|perms]` |
| **Storage** | grow `/` into unallocated LVM space, partition + LVM + filesystem + mount (+ `/etc/fstab`) for a new disk, shared department folders (setgid, 2770, default ACL) | `labctl storage [root\|disk\|shared]` |
| **Automation** | the scripts themselves, and a cron schedule (`/etc/cron.d/labserver`) for status, backup, cleanup, OS updates | `labctl cron` |
| **Backup & recovery** | tar.gz + SHA-256, gzip test, checksum verification, full restore into a scratch folder and comparison, retention, manual restore | `labctl backup [create\|verify\|restore]` |
| **Security** | ufw firewall (SSH always allowed first, rate-limited), SSH hardening (validated, auto-reverted on error), file/home/backup permissions | `labctl security [firewall\|ssh\|permissions]` |
| **Routine cleanup** | deletes files older than N days in the lab temp folder | `labctl cleanup` |
| **Testing & troubleshooting** | verifies every service, creates six simulated faults (stale temp files, open permissions, wrong owner, cron stopped, firewall off, corrupt backup), detects and fixes each, then validates outputs against `lab.conf` | `labctl test [verify\|troubleshoot\|validate]` |

The website has a page for each area (System, Users & Groups, Storage, Automation, Backup & Recovery, Security, Testing).

---

## Linux (the real server, Ubuntu 24.04)

```bash
git clone https://github.com/allenasat044-prog/ServerCats.git labserver     # or copy the folder over
cd labserver
nano server/lab.conf                          # departments, packages, schedules, security options...
./server/labctl users generate-roster 100     # or write server/students.csv yourself (username,fullname,department)
./server/labctl all                           # DRY RUN: prints exactly what would change
sudo ./server/labctl all --apply              # do it
sudo ./server/labctl status                   # collect real data -> public/data.json
```

Every module prints a plan unless you pass `--apply`, and each can be run on its own
(`./server/labctl help`). An empty value in `lab.conf` means "leave that alone", so nothing is applied
that you did not configure (hostname, static IP, data disk and `EXTEND_ROOT` are all off by default).
`sudo ./server/labctl cron --apply` (part of `all`) refreshes the website data every 5 minutes.

Website on the server (needs Node.js 18+: `sudo apt install nodejs npm`):
```bash
npm install && npm run dev -- --host          # open http://<server-ip>:5173
```
If the firewall is on, open that port first: set `FIREWALL_ALLOW_TCP="5173"` in `lab.conf` and run
`sudo ./server/labctl security firewall --apply`.

## macOS

A Mac cannot be the lab server (no apt, useradd, LVM or cron), so `system`, `users`, `storage` and `cron`
stop immediately with "cannot run on Darwin" and change nothing. These work on a Mac:

| Command (use `sudo` with `--apply`) | What it does on macOS |
|---|---|
| `labctl security --apply` | turns the macOS firewall and stealth mode on, installs the SSH hardening file `/etc/ssh/sshd_config.d/00-labserver.conf` (checked with `sshd -t`, reverted on error), closes home folders to 750 |
| `labctl backup --apply` | tar.gz of this project (set `MAC_BACKUP_SOURCES` in `lab.conf` to change it) into `/Users/Shared/lab/backups`, SHA-256, gzip test, restore test, retention |
| `labctl cleanup --apply` | deletes files older than `CLEANUP_DAYS` in `/Users/Shared/lab/tmp` |
| `labctl all --apply` | the three above, then the tests and the data collector |
| `labctl test`, `labctl status` | read-only checks and data for the website |

Run `labctl backup` (without `--apply`) first to see the plan. Mac lab files live in `/Users/Shared/lab`, because `/srv` and `/var/lib` are not usable on macOS.
Not provided on a Mac: scheduled runs (cron); run the commands by hand or use a Linux VM. What works on a Mac:

```bash
brew install node                              # or download Node.js from nodejs.org
cd ~/labserver
npm install
./server/labctl status                         # real values from THIS Mac, labelled as macOS
./server/labctl test                           # read-only checks of this Mac -> Testing page
npm run dev                                    # http://localhost:5173
```

To run the real server part on a Mac, use an Ubuntu VM ([Multipass](https://multipass.run); on Apple
Silicon it runs Ubuntu for ARM, which is fine). UTM or VirtualBox work too.

```bash
brew install --cask multipass
multipass launch 24.04 --name labserver --cpus 2 --memory 4G --disk 40G
multipass mount ~/labserver labserver:/home/ubuntu/labserver
multipass shell labserver
# ---- now inside the Ubuntu VM ----
cd ~/labserver
./server/labctl users generate-roster 100
./server/labctl all                            # dry run
sudo ./server/labctl all --apply
sudo ./server/labctl status                    # writes public/data.json into the mounted folder
```
Because the project folder is mounted, the website running on the Mac (`npm run dev`) picks up the VM's
`public/data.json` automatically. (If the mount misbehaves, use `multipass transfer` or `git pull` inside
the VM instead.)

## Windows

The website runs natively; the server part needs Linux, either in a VM or in WSL.

Website (PowerShell):
```powershell
winget install OpenJS.NodeJS.LTS
cd $HOME\labserver
npm install
npm run dev                                    # http://localhost:5173
```

Server part, option A (recommended): an Ubuntu VM with Multipass (needs Hyper-V or VirtualBox)
```powershell
winget install Canonical.Multipass
multipass launch 24.04 --name labserver --cpus 2 --memory 4G --disk 40G
multipass mount $HOME\labserver labserver:/home/ubuntu/labserver
multipass shell labserver
```
then run the same commands as in the macOS section ("inside the Ubuntu VM"). A VirtualBox/Hyper-V VM with
the Ubuntu Server 24.04 ISO works the same way.

Server part, option B: WSL2 (good for trying users, backups and cleanup; it has no real disks, so skip
`storage disk/root` and the firewall)
```powershell
wsl --install -d Ubuntu-24.04
```
In the Ubuntu window (enable systemd once so cron and ssh work):
```bash
printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf      # then run: wsl --shutdown  (in PowerShell) and reopen Ubuntu
git clone https://github.com/allenasat044-prog/ServerCats.git ~/labserver     # keep it inside Linux, not under /mnt/c
cd ~/labserver
./server/labctl users generate-roster 100
./server/labctl all
sudo ./server/labctl all --apply
sudo ./server/labctl status
```
Copy the data to the Windows copy of the site:
`copy \\wsl$\Ubuntu-24.04\home\<your-linux-user>\labserver\public\data.json .\public\`

Windows tips: `.gitattributes` forces Unix line endings for the scripts. If you ever see
`bad interpreter: /bin/bash^M`, run `sed -i 's/\r$//' server/labctl server/lab.conf server/lib/*.sh server/modules/*.sh`.
If `./server/labctl` says permission denied, run `chmod +x server/labctl` or call it as `bash server/labctl`.

---

## Safety built in
* Nothing changes without `--apply`, and the admin scripts refuse to run on anything but Linux.
* SSH is allowed in the firewall *before* the firewall is enabled.
* Password SSH login is only disabled if an admin already has an `authorized_keys`, root SSH login is only
  disabled if a sudo user exists, and the new sshd config is validated with `sshd -t` and reverted on failure.
* A static IP is applied with `netplan try` (rolls back after 60 s unless you confirm).
* A disk that has partitions or mounts is refused unless you pass `--force`; the OS disk is never touched.
* Student passwords are random per account (no shared default). They are stored in
  `/var/lib/labserver/initial-passwords.csv` (root only): hand them out, then delete that file.

## Why can `df` show 252 GB on a 512 GB disk?
Ubuntu's installer builds `/` on an LVM volume that often uses only about half of the disk. The rest sits
unallocated in the volume group. The Dashboard/Storage pages show this (physical disks, volume group,
unallocated space). To give `/` the rest: set `EXTEND_ROOT=yes` in `server/lab.conf`, then
`sudo ./server/labctl storage root --apply` (online, no reboot).

## Website notes
Pages re-read `public/data.json` every 10 seconds. Without root the collector still works but cannot read the
firewall, SSH settings, LVM or password states, and says so. `public/data.json` and `server/students.csv`
are git-ignored on purpose (real machine data and the roster).

## Layout
```
server/
  labctl                 entry point
  lab.conf               all settings
  lib/common.sh          shared helpers (plan/apply logic, Linux guard)
  modules/*.sh           system, users, storage, security, backup, cleanup, cron, test (test_mac.sh on macOS)
  collect.py             read-only collector -> public/data.json (Linux full, macOS partial)
src/                     React + Tailwind site (pages/, components/ui/, lib/)
```
