#!/usr/bin/env python3
"""LabServer collector (read-only).

Reads the real state of this machine (system, users, storage, automation, backups, security)
and writes it as JSON for the website, plus a plain-text health report.
Nothing is invented: a value that cannot be read is null and shown as "unavailable".
Run it as root to see everything (firewall, SSH settings, LVM, password states).

    sudo python3 server/collect.py            # writes ../public/data.json and prints the report
    sudo python3 server/collect.py --out /path/data.json
"""
import os, sys

if sys.platform == "win32":
    sys.exit("The collector reads a Linux or macOS machine. On Windows run it inside WSL (Ubuntu):\n"
             "    wsl sudo ./server/labctl status")

import json, time, glob, grp, pwd, re, subprocess, datetime, platform, plistlib

IS_LINUX = sys.platform.startswith("linux")
IS_MAC = sys.platform == "darwin"
HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
IS_ROOT = os.geteuid() == 0

# ----------------------------------------------------------------------------- helpers
def sh(cmd, any_rc=False, timeout=25):
    """Run a command; return stdout, or None when it is missing/fails (unless any_rc)."""
    try:
        r = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, timeout=timeout)
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return None
    return r.stdout if (r.returncode == 0 or any_rc) else None

def read(path):
    try:
        with open(path) as f: return f.read()
    except OSError:
        return None

def read_json(path):
    try:
        with open(path) as f: return json.load(f)
    except (OSError, ValueError):
        return None

def iso(ts): return datetime.datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds")

def load_conf():
    keys = ["LAB_BASE", "STATE_DIR", "DEPARTMENTS", "LAB_HOSTNAME", "NET_ADDRESS", "PACKAGES", "PASSWORD_MAX_DAYS",
            "EXTEND_ROOT", "DATA_DISK", "BACKUP_SOURCES", "BACKUP_KEEP", "CLEANUP_DAYS", "STATUS_CRON", "BACKUP_CRON",
            "CLEANUP_CRON", "UPDATE_CRON", "SSH_PERMIT_ROOT", "SSH_PASSWORD_AUTH", "ROSTER"]
    script = '. "$1/lib/common.sh"; shift; for v in "$@"; do printf "%s=%s\\0" "$v" "${!v-}"; done'
    out = sh(["bash", "-c", script, "_", HERE] + keys) or ""
    return dict(kv.split("=", 1) for kv in out.split("\0") if "=" in kv)

def mode_of(path):
    try: return format(os.stat(path).st_mode & 0o7777, "o")
    except OSError: return None

def owner_of(path):
    try:
        st = os.stat(path)
        try: u = pwd.getpwuid(st.st_uid).pw_name
        except KeyError: u = str(st.st_uid)
        try: g = grp.getgrgid(st.st_gid).gr_name
        except KeyError: g = str(st.st_gid)
        return u, g
    except OSError:
        return None, None

def tree_stats(path, cap=200000):
    """Count files, bytes and world-writable entries below path (symlinks are not followed)."""
    files = size = ww = seen = 0
    for dp, dn, fn in os.walk(path):
        for n in dn + fn:
            seen += 1
            if seen > cap: return {"files": files, "bytes": size, "world_writable": ww, "truncated": True}
            p = os.path.join(dp, n)
            try: st = os.lstat(p)
            except OSError: continue
            if (st.st_mode & 0o002) and not os.path.islink(p): ww += 1
            if n in fn: files += 1; size += st.st_size
    return {"files": files, "bytes": size, "world_writable": ww, "truncated": False}

def dir_info(path):
    if not os.path.isdir(path): return {"path": path, "exists": False}
    u, g = owner_of(path); m = mode_of(path)
    acl = sh(["getfacl", "-p", "-c", path])
    d = {"path": path, "exists": True, "mode": m, "owner": u, "group": g,
         "setgid": bool(os.stat(path).st_mode & 0o2000), "sticky": bool(os.stat(path).st_mode & 0o1000),
         "acl": [l for l in acl.splitlines() if l and not l.startswith("#")] if acl else None}
    d.update(tree_stats(path))
    return d

def section(name, fn, errors):
    try: return fn()
    except Exception as e:  # one failing section must not hide the rest
        errors.append(f"{name}: {e}"); return None

# ----------------------------------------------------------------------------- sections
def cpu_pct():
    def snap():
        v = list(map(int, read("/proc/stat").splitlines()[0].split()[1:])); return sum(v[:8]), v[3] + v[4]
    t1, i1 = snap(); time.sleep(1); t2, i2 = snap()
    return round(100 * (1 - (i2 - i1) / max(t2 - t1, 1)))

# ---- macOS: pure parsers (kept separate so they can be tested with sample output)
_UNIT = {"K": 1024, "M": 2 ** 20, "G": 2 ** 30}

def parse_top_cpu(text):
    m = re.findall(r"CPU usage:\s*[\d.]+% user,\s*[\d.]+% sys,\s*([\d.]+)% idle", text or "")
    return round(100 - float(m[-1])) if m else None

def parse_vm_stat_used(text):
    ps = re.search(r"page size of (\d+) bytes", text or "")
    ps = int(ps.group(1)) if ps else 4096
    pages = {k: int(v) for k, v in re.findall(r"^(Pages [^:]+):\s+(\d+)\.", text or "", re.M)}
    keys = ("Pages active", "Pages wired down", "Pages occupied by compressor")
    return sum(pages.get(k, 0) for k in keys) * ps if pages else None

def parse_swap(text):
    m = re.search(r"total = ([\d.]+)([KMG]).*?used = ([\d.]+)([KMG])", text or "")
    return (int(float(m.group(1)) * _UNIT[m.group(2)]), int(float(m.group(3)) * _UNIT[m.group(4)])) if m else (0, 0)

def parse_boottime(text):
    m = re.search(r"sec = (\d+)", text or ""); return int(m.group(1)) if m else None

def parse_ifconfig(text):
    out, cur = [], None
    for l in (text or "").splitlines():
        h = re.match(r"^(\S+): flags=", l)
        if h: cur = {"name": h.group(1), "state": None, "mac": None, "addresses": []}; out.append(cur); continue
        if cur is None: continue
        m = re.search(r"\sether (\S+)", l)
        if m: cur["mac"] = m.group(1)
        m = re.search(r"\sinet (\S+) netmask (0x[0-9a-fA-F]+)", l)
        if m: cur["addresses"].append(f"{m.group(1)}/{bin(int(m.group(2), 16)).count('1')}")
        m = re.search(r"\sstatus: (\w+)", l)
        if m: cur["state"] = "UP" if m.group(1) == "active" else "DOWN"
    return [i for i in out if i["addresses"] and not i["name"].startswith("lo")]

def parse_route_default(text):
    g = re.search(r"gateway:\s*(\S+)", text or ""); d = re.search(r"interface:\s*(\S+)", text or "")
    return {"via": g.group(1) if g else None, "dev": d.group(1) if d else None} if (g or d) else None

def parse_df(text):
    out = []
    for l in (text or "").splitlines()[1:]:
        p = l.split(None, 8)
        if len(p) < 6 or not p[0].startswith("/dev/"): continue
        mount = p[8] if len(p) > 8 else p[5]
        if mount.startswith("/System/Volumes/") and mount != "/System/Volumes/Data": continue
        size, used, avail = int(p[1]) * 1024, int(p[2]) * 1024, int(p[3]) * 1024
        out.append({"target": mount, "source": p[0], "fstype": "apfs", "size": size, "used": used, "avail": avail,
                    "pct": round(100 * used / max(used + avail, 1)), "options": None})
    return out

def parse_diskutil(data):
    root = plistlib.loads(data)
    disks = []
    for d in root.get("AllDisksAndPartitions", []):
        kids = []
        for part in d.get("Partitions", []):
            kids.append({"name": part["DeviceIdentifier"], "size": part.get("Size", 0), "type": "part", "fstype": part.get("Content"),
                         "mounts": [part["MountPoint"]] if part.get("MountPoint") else [], "model": part.get("VolumeName") or None, "children": []})
        for v in d.get("APFSVolumes", []):
            kids.append({"name": v["DeviceIdentifier"], "size": v.get("CapacityInUse", v.get("Size", 0)), "type": "apfs volume", "fstype": "apfs",
                         "mounts": [v["MountPoint"]] if v.get("MountPoint") else [], "model": v.get("VolumeName") or None, "children": []})
        disks.append({"name": d["DeviceIdentifier"], "size": d.get("Size", 0), "type": "disk", "fstype": d.get("Content"),
                      "mounts": [d["MountPoint"]] if d.get("MountPoint") else [], "model": None, "children": kids})
    return disks

def parse_lsof_listen(text):
    ports = set()
    for l in (text or "").splitlines()[1:]:
        p = l.split()
        if len(p) >= 2 and p[-1] == "(LISTEN)":
            addr, _, port = p[-2].rpartition(":")
            if port.isdigit(): ports.add((addr.strip("[]") or "*", int(port)))
    return sorted(({"address": a, "port": b} for a, b in ports), key=lambda x: (x["port"], x["address"]))

def resources_mac():
    mem_total = int((sh(["sysctl", "-n", "hw.memsize"]) or "0").strip() or 0)
    used = parse_vm_stat_used(sh(["vm_stat"]))
    st_total, st_used = parse_swap(sh(["sysctl", "-n", "vm.swapusage"]))
    path = "/System/Volumes/Data" if os.path.exists("/System/Volumes/Data") else "/"
    st = os.statvfs(path)
    total, dused, avail = st.f_blocks * st.f_frsize, (st.f_blocks - st.f_bfree) * st.f_frsize, st.f_bavail * st.f_frsize
    return {"cpu": {"pct": parse_top_cpu(sh(["top", "-l", "2", "-n", "0", "-s", "1"], timeout=20)), "cores": os.cpu_count(),
                    "load": [round(x, 2) for x in os.getloadavg()]},
            "mem": {"total": mem_total, "used": used, "pct": round(100 * used / mem_total) if used is not None and mem_total else None,
                    "swap_total": st_total, "swap_used": st_used},
            "disk": {"mount": path, "total": total, "used": dused, "avail": avail, "pct": round(100 * dused / max(dused + avail, 1))}}

def system_mac(cfg):
    boot = parse_boottime(sh(["sysctl", "-n", "kern.boottime"]))
    up = int(time.time() - boot) if boot else 0
    d, r = divmod(up, 86400); h, r = divmod(r, 3600); m = r // 60
    name = (sh(["sw_vers", "-productName"]) or "macOS").strip(); ver = (sh(["sw_vers", "-productVersion"]) or "").strip()
    gw = parse_route_default(sh(["route", "-n", "get", "default"]))
    dns = list(dict.fromkeys(re.findall(r"nameserver\[\d+\]\s*:\s*(\S+)", sh(["scutil", "--dns"]) or "")))
    if not dns: dns = [l.split()[1] for l in (read("/etc/resolv.conf") or "").splitlines() if l.startswith("nameserver")]
    tz = os.path.realpath("/etc/localtime"); tz = tz.split("zoneinfo/", 1)[1] if "zoneinfo/" in tz else None
    return {"hostname": platform.node(), "os": f"{name} {ver}".strip(), "kernel": platform.release(), "timezone": tz,
            "uptime_s": up, "uptime": f"{d} days, {h} hours, {m} minutes" if d else f"{h} hours, {m} minutes",
            "booted": iso(boot) if boot else None,
            "network": {"interfaces": parse_ifconfig(sh(["ifconfig"])), "gateway": gw, "dns": dns, "static_by_labctl": False},
            "updates": {"pending": None, "security": None, "package_lists": None, "last_upgrade": None, "reboot_required": None},
            "packages": [], "configured_hostname": cfg.get("LAB_HOSTNAME") or None}

def resources():
    if IS_MAC: return resources_mac()
    mi = {l.split(":")[0]: int(l.split()[1]) * 1024 for l in read("/proc/meminfo").splitlines()}
    mt, mu = mi["MemTotal"], mi["MemTotal"] - mi["MemAvailable"]
    st = os.statvfs("/")
    total, used, avail = st.f_blocks * st.f_frsize, (st.f_blocks - st.f_bfree) * st.f_frsize, st.f_bavail * st.f_frsize
    return {"cpu": {"pct": cpu_pct(), "cores": os.cpu_count(), "load": [round(x, 2) for x in os.getloadavg()]},
            "mem": {"total": mt, "used": mu, "pct": round(100 * mu / mt),
                    "swap_total": mi.get("SwapTotal", 0), "swap_used": mi.get("SwapTotal", 0) - mi.get("SwapFree", 0)},
            "disk": {"mount": "/", "total": total, "used": used, "avail": avail,
                     "pct": round(100 * used / max(used + avail, 1))}}

def lvm():
    def rep(tool, cols, key):
        s = sh([tool, "-o", cols, "--reportformat", "json", "--units", "b", "--nosuffix"])
        if s is None: return None
        rows = json.loads(s)["report"][0][key]
        for r in rows:
            for k, v in r.items():
                if k.endswith(("_size", "_free")) or k.endswith("_count"): r[k] = int(float(v))
        return rows
    pvs = rep("pvs", "pv_name,vg_name,pv_size,pv_free", "pv")
    vgs = rep("vgs", "vg_name,vg_size,vg_free,pv_count,lv_count", "vg")
    lvs = rep("lvs", "lv_name,vg_name,lv_size,lv_attr,lv_path", "lv")
    if pvs is None and vgs is None and lvs is None: return None
    return {"pvs": pvs or [], "vgs": vgs or [], "lvs": lvs or []}

def root_lvm(lv):
    src = (sh(["findmnt", "-no", "SOURCE", "/"]) or "").strip()
    if not lv or not src: return {"source": src or None}
    for l in lv["lvs"]:
        mapper = "/dev/mapper/" + l["vg_name"].replace("-", "--") + "-" + l["lv_name"].replace("-", "--")
        if src in (mapper, l.get("lv_path")):
            vg = next((v for v in lv["vgs"] if v["vg_name"] == l["vg_name"]), {})
            return {"source": src, "lv": l["lv_name"], "lv_size": l["lv_size"], "vg": l["vg_name"],
                    "vg_size": vg.get("vg_size"), "vg_free": vg.get("vg_free")}
    return {"source": src}

def lsblk():
    if IS_MAC:
        raw = sh(["diskutil", "list", "-plist"])
        return parse_diskutil(raw.encode()) if raw else None
    s = sh(["lsblk", "-J", "-b", "-o", "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,ROTA"])
    key = "mountpoints"
    if s is None:
        s = sh(["lsblk", "-J", "-b", "-o", "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,ROTA"]); key = "mountpoint"
    if s is None: return None
    def norm(d):
        mp = d.get(key); mp = mp if isinstance(mp, list) else [mp]
        return {"name": d["name"], "size": int(d["size"]), "type": d["type"], "fstype": d.get("fstype"),
                "mounts": [m for m in mp if m], "model": (d.get("model") or "").strip() or None,
                "children": [norm(c) for c in d.get("children", []) if c["type"] not in ("loop", "rom")]}
    return [norm(d) for d in json.loads(s)["blockdevices"]
            if d["type"] == "disk" and int(d["size"]) > 0 and not d["name"].startswith("zram")]

def mounts():
    if IS_MAC: return parse_df(sh(["df", "-kP"]))
    s = sh(["findmnt", "-J", "-b", "-o", "TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL,OPTIONS"])
    if s is None: return None
    out = []
    def walk(n):
        for f in n:
            src = f.get("source") or ""
            if src.startswith("/dev/") and not src.startswith("/dev/loop"):
                size, used = int(f.get("size") or 0), int(f.get("used") or 0)
                out.append({"target": f["target"], "source": src, "fstype": f["fstype"], "size": size, "used": used,
                            "avail": int(f.get("avail") or 0), "pct": round(100 * used / size) if size else 0,
                            "options": f.get("options")})
            walk(f.get("children", []))
    walk(json.loads(s)["filesystems"])
    return out

def fstab():
    rows = []
    for l in (read("/etc/fstab") or "").splitlines():
        l = l.strip()
        if l and not l.startswith("#"):
            p = l.split()
            if len(p) >= 4: rows.append({"device": p[0], "mount": p[1], "type": p[2], "options": p[3]})
    return rows

def system(cfg):
    if IS_MAC: return system_mac(cfg)
    up = float(read("/proc/uptime").split()[0])
    d, r = divmod(int(up), 86400); h, r = divmod(r, 3600); m = r // 60
    osr = read("/etc/os-release") or ""
    pretty = next((l.split("=", 1)[1].strip().strip('"') for l in osr.splitlines() if l.startswith("PRETTY_NAME=")), platform.platform())
    # network
    ifaces = []
    a = sh(["ip", "-j", "addr"])
    for i in (json.loads(a) if a else []):
        if i["ifname"] == "lo": continue
        ifaces.append({"name": i["ifname"], "state": i.get("operstate"), "mac": i.get("address"),
                       "addresses": [f'{x["local"]}/{x["prefixlen"]}' for x in i.get("addr_info", [])]})
    rt = sh(["ip", "-j", "route", "show", "default"]); gw = None
    if rt and json.loads(rt): g = json.loads(rt)[0]; gw = {"via": g.get("gateway"), "dev": g.get("dev")}
    dns = []
    rd = sh(["resolvectl", "dns"])
    for l in (rd or "").splitlines():
        if ":" in l: dns += l.split(":", 1)[1].split()
    if not dns:
        dns = [l.split()[1] for l in (read("/etc/resolv.conf") or "").splitlines() if l.startswith("nameserver")]
    # updates
    ap = sh("apt list --upgradable 2>/dev/null")
    up_lines = [l for l in (ap or "").splitlines() if "upgradable" in l]
    stamp = next((p for p in ("/var/lib/apt/periodic/update-success-stamp", "/var/lib/apt/lists") if os.path.exists(p)), None)
    upd = read_json(os.path.join(cfg["STATE_DIR"], "update.json"))
    # packages
    names = cfg["PACKAGES"].split()
    out = sh(["dpkg-query", "-W", "-f=${Package}\t${Version}\t${db:Status-Abbrev}\n"] + names, any_rc=True) if names else ""
    have = {}
    for l in (out or "").splitlines():
        p = l.split("\t")
        if len(p) == 3 and p[2].startswith("ii"): have[p[0]] = p[1]
    tz = (sh(["timedatectl", "show", "-p", "Timezone", "--value"]) or read("/etc/timezone") or "").strip() or None
    return {"hostname": platform.node(), "os": pretty, "kernel": platform.release(), "timezone": tz,
            "uptime_s": int(up), "uptime": f"{d} days, {h} hours, {m} minutes" if d else f"{h} hours, {m} minutes",
            "booted": iso(time.time() - up),
            "network": {"interfaces": ifaces, "gateway": gw, "dns": dns,
                        "static_by_labctl": os.path.exists("/etc/netplan/60-labserver.yaml")},
            "updates": {"pending": len(up_lines) if ap is not None else None,
                        "security": sum(1 for l in up_lines if "-security" in l) if ap is not None else None,
                        "package_lists": iso(os.path.getmtime(stamp)) if stamp else None,
                        "last_upgrade": upd.get("time") if upd else None,
                        "reboot_required": os.path.exists("/var/run/reboot-required")},
            "packages": [{"name": n, "version": have.get(n)} for n in names],
            "configured_hostname": cfg.get("LAB_HOSTNAME") or None}

def shadow_map():
    out = {}
    for l in (read("/etc/shadow") or "").splitlines():
        p = l.split(":")
        if len(p) >= 5: out[p[0]] = p
    return out

def users(cfg):
    depts = cfg["DEPARTMENTS"].split()
    shadow = shadow_map() if IS_ROOT else {}
    students = []
    for p in pwd.getpwall():
        if not (1000 <= p.pw_uid < 60000): continue
        try: g = grp.getgrgid(p.pw_gid).gr_name
        except KeyError: continue
        if not g.startswith("lab-") or g == "lab-students": continue
        sp = shadow.get(p.pw_name); state = None; max_days = None
        if sp:
            h = sp[1]
            state = "locked" if h[:1] in ("!", "*") and sp[2] != "0" else "empty" if h == "" else "must change" if sp[2] == "0" else "set"
            max_days = int(sp[4]) if sp[4].isdigit() else None
        students.append({"user": p.pw_name, "uid": p.pw_uid, "name": p.pw_gecos.split(",")[0], "dept": g[4:],
                         "home_mode": mode_of(p.pw_dir), "password": state, "max_days": max_days})
    groups = []
    for g in sorted(grp.getgrall(), key=lambda x: x.gr_name):
        if g.gr_name.startswith("lab-"):
            prim = {p.pw_name for p in pwd.getpwall() if p.pw_gid == g.gr_gid}
            groups.append({"name": g.gr_name, "gid": g.gr_gid, "members": len(prim | set(g.gr_mem))})
    admins = next((g.gr_mem for g in grp.getgrall() if g.gr_name == ("admin" if IS_MAC else "sudo")), [])
    roster_path = cfg.get("ROSTER") or os.path.join(HERE, "students.csv")
    roster = None
    if os.path.isfile(roster_path):
        rows = [l.split(",") for l in read(roster_path).splitlines()[1:] if l.strip()]
        names = {r[0] for r in rows}; have = {s["user"] for s in students}
        roster = {"count": len(names), "missing": sorted(names - have)[:20], "missing_count": len(names - have),
                  "extra": sorted(have - names)[:20], "extra_count": len(have - names)}
    creds = os.path.join(cfg["STATE_DIR"], "initial-passwords.csv")
    pq = read("/etc/security/pwquality.conf.d/labserver.conf")
    return {"students": students, "groups": groups, "admins": admins, "roster": roster,
            "departments": [{"dept": d, "group": f"lab-{d}", "students": sum(1 for s in students if s["dept"] == d)} for d in depts],
            "must_change": sum(1 for s in students if s["password"] == "must change"),
            "locked": sum(1 for s in students if s["password"] == "locked"),
            "empty_password": sum(1 for s in students if s["password"] == "empty"),
            "password_states_readable": bool(shadow),
            "policy": {"pwquality": bool(pq), "minlen": next((int(m.group(1)) for m in [re.search(r"minlen\s*=\s*(\d+)", pq or "")] if m), None),
                       "max_days": int(cfg["PASSWORD_MAX_DAYS"]) if cfg.get("PASSWORD_MAX_DAYS", "").isdigit() else None},
            "initial_passwords_file": creds if os.path.exists(creds) else None}

def storage(cfg, lv):
    base = cfg["LAB_BASE"]
    return {"disks": lsblk(), "lvm": lv, "mounts": mounts(), "fstab": fstab(), "base": base,
            "base_mounted_separately": os.path.ismount(base),
            "shared": [dict(dir_info(os.path.join(base, "shared", d)), dept=d, expected_group=f"lab-{d}") for d in cfg["DEPARTMENTS"].split()],
            "tmp": dir_info(os.path.join(base, "tmp")), "backups_dir": dir_info(os.path.join(base, "backups")),
            "extend_root_enabled": cfg.get("EXTEND_ROOT") == "yes", "data_disk": cfg.get("DATA_DISK") or None}

def cron_describe(cmd):
    for key, label in (("backup", "Backup + verify + restore test"), ("cleanup", "Clean old temp files"),
                       ("system update", "OS update"), ("status", "Refresh website data")):
        if f" {key}" in " " + cmd: return label
    return "Custom task"

def automation(cfg):
    mods = []
    for p in sorted(glob.glob(os.path.join(HERE, "modules", "*.sh"))):
        lines = (read(p) or "").splitlines()
        mods.append({"name": os.path.basename(p), "description": lines[1].lstrip("# ") if len(lines) > 1 else "",
                     "executable": os.access(p, os.X_OK), "modified": iso(os.path.getmtime(p))})
    def parse_cron(text, has_user):
        rows = []
        for l in (text or "").splitlines():
            l = l.strip()
            if not l or l.startswith("#") or re.match(r"^[A-Za-z_]+=", l): continue
            p = l.split(None, 6 if has_user else 5)
            if len(p) < (7 if has_user else 6): continue
            cmd = p[6] if has_user else p[5]
            rows.append({"schedule": " ".join(p[:5]), "user": p[5] if has_user else "root", "command": cmd, "label": cron_describe(cmd)})
        return rows
    cd = parse_cron(read("/etc/cron.d/labserver"), True)
    root_tab = parse_cron(sh(["crontab", "-l"]), False)
    log = "/var/log/labserver.log"; tail = None
    if os.path.exists(log):
        t = read(log); tail = t.splitlines()[-8:] if t is not None else None
    return {"modules": mods, "cron": cd, "root_crontab": root_tab,
            "cron_file": os.path.exists("/etc/cron.d/labserver"),
            "cron_service": (sh(["systemctl", "is-active", "cron"], any_rc=True) or "").strip() or None,
            "log": {"path": log, "exists": os.path.exists(log), "tail": tail,
                    "modified": iso(os.path.getmtime(log)) if os.path.exists(log) else None},
            "labctl": os.path.join(HERE, "labctl")}

def backup(cfg):
    bd = os.path.join(cfg["LAB_BASE"], "backups")
    items = []
    for f in sorted(glob.glob(os.path.join(bd, "lab-backup-*.tar.gz")), key=os.path.getmtime, reverse=True):
        items.append({"file": os.path.basename(f), "size": os.path.getsize(f), "time": iso(os.path.getmtime(f)),
                      "checksum_file": os.path.exists(f + ".sha256")})
    free = None
    if os.path.isdir(bd): st = os.statvfs(bd); free = st.f_bavail * st.f_frsize
    return {"dir": bd, "archives": items, "last_run": read_json(os.path.join(cfg["STATE_DIR"], "backup.json")),
            "sources": cfg["BACKUP_SOURCES"].split(), "keep": int(cfg["BACKUP_KEEP"]), "free": free,
            "total_bytes": sum(i["size"] for i in items)}

def cleanup(cfg):
    tmp = os.path.join(cfg["LAB_BASE"], "tmp"); days = int(cfg["CLEANUP_DAYS"]); now = time.time()
    cur = None
    if os.path.isdir(tmp):
        files = [os.path.join(dp, f) for dp, _, fn in os.walk(tmp) for f in fn]
        old = [f for f in files if os.path.isfile(f) and now - os.path.getmtime(f) > days * 86400]
        cur = {"files": len(files), "waiting": len(old), "waiting_bytes": sum(os.path.getsize(f) for f in old)}
    return {"dir": tmp, "days": days, "current": cur, "last_run": read_json(os.path.join(cfg["STATE_DIR"], "cleanup.json"))}

def security(cfg, usr, stor):
    checks = []
    def add(i, title, level, detail): checks.append({"id": i, "title": title, "level": level, "detail": detail})
    # firewall
    fw = {"installed": bool(sh(["which", "ufw"])), "readable": False, "kind": "ufw"}
    if IS_MAC:
        g = sh(["/usr/libexec/ApplicationFirewall/socketfilterfw", "--getglobalstate"], any_rc=True) or ""
        fw = {"installed": True, "readable": bool(g), "kind": "macos", "active": "enabled" in g.lower(),
              "defaults": "macOS Application Firewall (per-application rules)", "rules": []}
        add("fw", "Firewall active", "pass" if fw["active"] else "warn" if g else "unknown",
            "macOS Application Firewall is " + ("on" if fw["active"] else "off") if g else "could not read the firewall state")
    elif fw["installed"]:
        s = sh(["ufw", "status", "verbose"])
        if s:
            fw["readable"] = True
            fw["active"] = bool(re.search(r"^Status:\s*active", s, re.M))
            m = re.search(r"^Default:\s*(.+)$", s, re.M); fw["defaults"] = m.group(1).strip() if m else None
            rules, seen = [], False
            for l in s.splitlines():
                if l.startswith("--"): seen = True; continue
                if seen and l.strip():
                    p = re.split(r"\s{2,}", l.strip())
                    if len(p) >= 3: rules.append({"to": p[0], "action": p[1], "from": p[2]})
            fw["rules"] = rules
    if IS_MAC: pass
    elif not fw["installed"]: add("fw", "Firewall active", "fail", "ufw is not installed")
    elif not fw["readable"]: add("fw", "Firewall active", "unknown", "run the collector with sudo to read ufw")
    else:
        add("fw", "Firewall active", "pass" if fw["active"] else "fail", "ufw is " + ("active" if fw["active"] else "inactive"))
        if fw["active"]: add("fw-default", "Incoming traffic denied by default", "pass" if "deny (incoming)" in (fw["defaults"] or "") else "fail", fw["defaults"] or "unknown")
    # ssh
    ssh = {"service": None if IS_MAC else (sh(["systemctl", "is-active", "ssh"], any_rc=True) or "").strip() or None, "config": None}
    s = sh(["sshd", "-T"])
    if s:
        c = {}
        for l in s.splitlines():
            k, _, v = l.partition(" "); c.setdefault(k, []).append(v)
        ssh["config"] = {k: ", ".join(c[k]) for k in ("port", "permitrootlogin", "passwordauthentication", "pubkeyauthentication",
                         "permitemptypasswords", "maxauthtries", "logingracetime", "x11forwarding", "allowgroups", "clientaliveinterval") if k in c}
        g = ssh["config"].get
        add("ssh-root", "Root login over SSH disabled", "pass" if g("permitrootlogin") in ("no", "prohibit-password") else "fail", f'PermitRootLogin {g("permitrootlogin")}')
        add("ssh-empty", "Empty passwords refused", "pass" if g("permitemptypasswords") == "no" else "fail", f'PermitEmptyPasswords {g("permitemptypasswords")}')
        add("ssh-tries", "Limited login attempts", "pass" if int(g("maxauthtries", 6)) <= 4 else "warn", f'MaxAuthTries {g("maxauthtries")}')
        add("ssh-pw", "Key-only SSH login", "pass" if g("passwordauthentication") == "no" else "warn",
            "password login is " + ("off" if g("passwordauthentication") == "no" else "on (stronger with keys only; set SSH_PASSWORD_AUTH=no once keys are installed)"))
    else:
        add("ssh", "SSH settings", "unknown", "run the collector with sudo and install openssh-server to read sshd -T")
    # permissions
    sh_dirs = [d for d in stor["shared"] if d["exists"]]
    if not IS_LINUX:
        pass  # shared folders, student homes, backups and /etc/shadow checks belong to the Linux lab server
    elif sh_dirs:
        bad = [d["dept"] for d in sh_dirs if d["mode"] != "2770"]
        add("shared-mode", "Department folders are 2770", "pass" if not bad else "fail", "all correct" if not bad else "wrong mode: " + ", ".join(bad))
        ww = sum(d["world_writable"] for d in sh_dirs)
        add("shared-ww", "Nothing in shared folders is writable by others", "pass" if ww == 0 else "fail", f"{ww} world-writable entries")
    else:
        add("shared-mode", "Department folders exist", "fail", "run: labctl storage shared --apply")
    st = usr["students"]
    if IS_LINUX and st:
        loose = [s["user"] for s in st if s["home_mode"] and int(s["home_mode"], 8) & 0o007]
        add("homes", "Student home directories private", "pass" if not loose else "fail", f"{len(loose)} of {len(st)} readable by others")
    bk = stor["backups_dir"]
    if IS_LINUX and bk["exists"]: add("backup-dir", "Backup folder is root-only (700)", "pass" if bk["mode"] == "700" else "fail", f'mode {bk["mode"]}')
    sm = mode_of("/etc/shadow") if IS_LINUX else None
    if sm: add("shadow", "/etc/shadow not world-readable", "pass" if int(sm, 8) & 0o007 == 0 else "fail", f"mode {sm}")
    if usr["password_states_readable"]:
        add("pw-empty", "No account has an empty password", "pass" if usr["empty_password"] == 0 else "fail", f'{usr["empty_password"]} accounts')
    if usr["initial_passwords_file"]:
        add("pw-file", "One-time password file removed after hand-out", "warn", f'{usr["initial_passwords_file"]} still exists (root only)')
    # listening ports
    ports = []
    if IS_MAC:
        return {"firewall": fw, "ssh": ssh, "checks": checks, "listening": parse_lsof_listen(sh(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN"], any_rc=True))}
    ss = sh(["ss", "-H", "-tln"])
    for l in (ss or "").splitlines():
        p = l.split()
        if len(p) >= 4:
            addr, _, port = p[3].rpartition(":")
            if port.isdigit(): ports.append({"address": addr.strip("[]"), "port": int(port)})
    listening = sorted(({"address": a, "port": p} for a, p in {(x["address"], x["port"]) for x in ports}), key=lambda x: (x["port"], x["address"]))
    return {"firewall": fw, "ssh": ssh, "checks": checks, "listening": listening}

# ----------------------------------------------------------------------------- report
def gb(x): return f"{x / 2**30:.1f} GB"
def hs(x): return f"{x / 2**20:.1f} MB" if x >= 2**20 else (f"{x // 1024} KB" if x >= 1024 else f"{x} B")

def build_report(D):
    s, r, u, st, b, c, sec = D["system"], D["resources"], D["users"], D["storage"], D["backup"], D["cleanup"], D["security"]
    L = ["LAB SERVER HEALTH REPORT" + ("" if IS_LINUX else "  (macOS: Linux-only items are unavailable)"), f'Generated : {D["time"]}', f'Host      : {s["hostname"]} ({s["os"]}, kernel {s["kernel"]})',
         f'Uptime    : {s["uptime"]}', ""]
    L += [f'CPU       : {"unavailable" if r["cpu"]["pct"] is None else str(r["cpu"]["pct"]) + "%"} of {r["cpu"]["cores"]} cores, load {r["cpu"]["load"]}',
          f'Memory    : {"unavailable" if r["mem"]["pct"] is None else gb(r["mem"]["used"]) + " / " + gb(r["mem"]["total"]) + " (" + str(r["mem"]["pct"]) + "%)"}',
          f'Disk ({r["disk"]["mount"]}) : {gb(r["disk"]["used"])} / {gb(r["disk"]["total"])} ({r["disk"]["pct"]}%)']
    rl = D["root_volume"]
    if rl.get("vg"):
        L.append(f'            root volume {rl["lv"]} in volume group {rl["vg"]} ({gb(rl["vg_size"])} total, {gb(rl["vg_free"])} not allocated)')
    if st["disks"]:
        L.append("Disks     : " + ", ".join(f'{d["name"]} {gb(d["size"])}' for d in st["disks"]))
    L += ["", f'Network   : {", ".join(a for i in s["network"]["interfaces"] for a in i["addresses"]) or "no addresses"}'
          f'; gateway {(s["network"]["gateway"] or {}).get("via") or "none"}']
    up = s["updates"]
    L.append(f'Updates   : {up["pending"] if up["pending"] is not None else "unknown"} packages upgradable'
             + (", reboot required" if up["reboot_required"] else ""))
    if s["packages"]:
        ok = sum(1 for p in s["packages"] if p["version"]); L.append(f'Software  : {ok}/{len(s["packages"])} required packages installed')
    L += ["", f'Accounts  : {len(u["students"])} student accounts in {len([g for g in u["groups"] if g["name"] != "lab-students"])} department groups'
          + (f', {u["must_change"]} still need to change their first password' if u["password_states_readable"] else ""),
          "Folders   : " + (", ".join(f'{d["dept"]}({d["mode"]})' for d in st["shared"] if d["exists"]) or "not created yet")]
    lc = c["last_run"]; L.append("Cleanup   : " + (f'removed {lc["removed"]} of {lc["before"]} files, freed {hs(lc["freed"])} ({lc["time"][:16].replace("T", " ")})' if lc else "has not run yet"))
    lb = b["last_run"]
    L.append("Backup    : " + (f'{lb["file"]} ({hs(lb["size"])}), integrity {"OK" if lb["gzip_ok"] and lb["sha_ok"] else "FAILED"}, '
                              f'restore test {"PASSED" if lb["restore_ok"] else "FAILED"} ({lb["restored"]}/{lb["files"]} entries)' if lb else "has not run yet"))
    cnt = {k: sum(1 for x in sec["checks"] if x["level"] == k) for k in ("pass", "warn", "fail", "unknown")}
    L.append(f'Security  : {cnt["pass"]} checks passed, {cnt["warn"]} warnings, {cnt["fail"]} failed, {cnt["unknown"]} unreadable')
    if not IS_ROOT: L += ["", "NOTE: not run as root, so firewall, SSH, LVM and password details are unavailable. Use sudo."]
    return "\n".join(L) + "\n"

def main():
    out = os.path.join(PROJECT, "public", "data.json")
    if "--out" in sys.argv: out = sys.argv[sys.argv.index("--out") + 1]
    cfg = load_conf()
    cfg.setdefault("STATE_DIR", "/var/lib/labserver"); cfg.setdefault("LAB_BASE", "/srv/lab")
    for k, v in (("DEPARTMENTS", "cse ece mech civil"), ("PACKAGES", ""), ("BACKUP_SOURCES", ""), ("BACKUP_KEEP", "7"), ("CLEANUP_DAYS", "7")):
        if not cfg.get(k): cfg[k] = v
    errors = []
    D = {"platform": "linux" if IS_LINUX else "darwin" if IS_MAC else sys.platform, "generated": time.time(), "time": datetime.datetime.now().strftime("%d %b %Y, %H:%M:%S"), "root": IS_ROOT, "errors": errors,
         "config": {k: cfg.get(k) for k in ("LAB_BASE", "DEPARTMENTS", "BACKUP_SOURCES", "BACKUP_KEEP", "CLEANUP_DAYS", "STATUS_CRON",
                                            "BACKUP_CRON", "CLEANUP_CRON", "UPDATE_CRON", "PASSWORD_MAX_DAYS")}}
    D["resources"] = section("resources", resources, errors)
    lv = section("lvm", lvm, errors)
    D["root_volume"] = section("root volume", lambda: root_lvm(lv), errors) or {}
    D["who"] = (sh(["who"]) or "").splitlines()
    D["system"] = section("system", lambda: system(cfg), errors)
    D["users"] = section("users", lambda: users(cfg), errors)
    D["storage"] = section("storage", lambda: storage(cfg, lv), errors)
    D["automation"] = section("automation", lambda: automation(cfg), errors)
    D["backup"] = section("backup", lambda: backup(cfg), errors)
    D["cleanup"] = section("cleanup", lambda: cleanup(cfg), errors)
    D["security"] = section("security", lambda: security(cfg, D["users"], D["storage"]), errors)
    if all(D.get(k) for k in ("resources", "system", "users", "storage", "backup", "cleanup", "security")):
        D["report"] = build_report(D)
    else:
        D["report"] = "Some sections could not be collected:\n" + "\n".join(errors) + "\n"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w") as f: json.dump(D, f, indent=1)
    os.chmod(tmp, 0o644); os.replace(tmp, out)
    print(D["report"], end="")
    if errors: print("\nCollector errors:\n  " + "\n  ".join(errors), file=sys.stderr)

if __name__ == "__main__":
    main()
