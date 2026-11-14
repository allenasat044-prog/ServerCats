# LabServer: a Linux server for a college computer lab

Scripts that configure and run an Ubuntu lab server for 100 student accounts, plus a website that
shows the **real** state of that server. Nothing on the site is built in: every number comes from
`server/collect.py`, which reads the machine and writes `public/data.json`.

## Which computer runs what

| Part | Linux server / VM (Ubuntu) | macOS | Windows |
|---|---|---|---|
| **Admin scripts** (`./server/labctl system \| users \| storage \| security \| backup \| cleanup \| cron \| all`) | yes, this is what they are for | **no**: they refuse to run and change nothing | **no**: run them inside WSL or a Linux VM |
| **Collector** (`./server/labctl status`) | full data | partial: real values of the Mac, clearly labelled (no LVM, ufw, cron, apt) | run it inside WSL / the VM |
| **Website** (`npm run dev`) | yes | yes | yes |
| `labctl users generate-roster N` | yes | yes | in WSL / Git Bash |

The lab server is a Linux machine (apt, useradd, LVM, ufw, cron). A Mac or Windows PC is where you can
develop and view the website, and where you can run a Linux VM for the server part.

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

The website has a page for each area (System, Users & Groups, Storage, Automation, Backup & Recovery, Security).

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

A Mac cannot be the lab server (no apt, useradd, LVM or ufw), so the admin scripts stop immediately with
"cannot run on Darwin" and change nothing. What works on a Mac:

```bash
brew install node                              # or download Node.js from nodejs.org
cd ~/labserver
npm install
./server/labctl status                         # real values from THIS Mac, labelled as macOS
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
  modules/*.sh           system, users, storage, security, backup, cleanup, cron
  collect.py             read-only collector -> public/data.json (Linux full, macOS partial)
src/                     React + Tailwind site (pages/, components/ui/, lib/)
```
