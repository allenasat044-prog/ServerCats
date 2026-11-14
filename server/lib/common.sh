#!/usr/bin/env bash
# Shared helpers for every LabServer module. Sourced, never run directly.
# Safety model: modules only PRINT a plan unless LAB_APPLY=1 (labctl --apply).

SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_CONF="${LAB_CONF:-$SERVER_DIR/lab.conf}"
# shellcheck disable=SC1090
[ -f "$LAB_CONF" ] && . "$LAB_CONF"

: "${LAB_BASE:=/srv/lab}" "${STATE_DIR:=/var/lib/labserver}" "${DEPARTMENTS:=cse ece mech civil}"
: "${LAB_HOSTNAME:=}" "${NET_IFACE:=}" "${NET_ADDRESS:=}" "${NET_GATEWAY:=}" "${NET_DNS:=}"
: "${PACKAGES:=}" "${PASSWORD_MAX_DAYS:=180}" "${EXTEND_ROOT:=no}" "${DATA_DISK:=}"
: "${LVM_VG:=labvg}" "${LVM_LV:=labdata}" "${LVM_SIZE:=100%FREE}" "${LVM_FS:=ext4}" "${LVM_MOUNT:=$LAB_BASE}"
: "${BACKUP_SOURCES:=$LAB_BASE/shared /home}" "${BACKUP_KEEP:=7}" "${CLEANUP_DAYS:=7}"
: "${STATUS_CRON:=*/5 * * * *}" "${BACKUP_CRON:=30 1 * * *}" "${CLEANUP_CRON:=0 3 * * *}" "${UPDATE_CRON:=0 4 * * 0}"
: "${FIREWALL_ALLOW_TCP:=}" "${SSH_PERMIT_ROOT:=no}" "${SSH_PASSWORD_AUTH:=yes}"
: "${SSH_MAX_AUTH_TRIES:=3}" "${SSH_ALLOW_GROUPS:=}"
ROSTER="${ROSTER:-$SERVER_DIR/students.csv}"
LAB_APPLY="${LAB_APPLY:-0}"
LAB_FORCE="${LAB_FORCE:-0}"
export DEBIAN_FRONTEND=noninteractive

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '  [ok]   %s\n' "$*"; }
skip() { printf '  [skip] %s\n' "$*"; }
warn() { printf '  [warn] %s\n' "$*" >&2; }
die()  { printf '  [FAIL] %s\n' "$*" >&2; exit 1; }

require_linux() {
  [ "$(uname -s)" = Linux ] || die "this module configures a Linux server (Ubuntu/Debian); it cannot run on $(uname -s). Nothing was changed."
}

need_root_if_apply() {
  require_linux
  if [ "$LAB_APPLY" = 1 ] && [ "$(id -u)" -ne 0 ]; then die "--apply needs root: run with sudo"; fi
}

# run <command...>: execute with --apply, otherwise only show it.
run() {
  if [ "$LAB_APPLY" = 1 ]; then printf '  + %s\n' "$*"; "$@"; else printf '  (plan) %s\n' "$*"; fi
}

# put_file <path> <mode>  (content on stdin): write only when the content changes.
put_file() {
  local path=$1 mode=$2 tmp
  tmp=$(mktemp)
  cat > "$tmp"
  if [ -f "$path" ] && cmp -s "$tmp" "$path"; then
    ok "$path is already up to date"
  elif [ "$LAB_APPLY" = 1 ]; then
    mkdir -p "$(dirname "$path")"
    install -m "$mode" -o root -g root "$tmp" "$path" && ok "wrote $path"
  else
    printf '  (plan) write %s (mode %s):\n' "$path" "$mode"; sed 's/^/        | /' "$tmp"
  fi
  rm -f "$tmp"
}

ensure_group() { getent group "$1" >/dev/null 2>&1 || run groupadd "$1"; }

# hb <bytes>: human readable size
hb() { awk -v x="${1:-0}" 'BEGIN{ split("B KB MB GB TB",u," "); i=1; while (x>=1024 && i<5) {x/=1024; i++}; printf (i==1 ? "%d %s" : "%.1f %s"), x, u[i] }'; }

jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# write_state <name> <json>: record of a real run, read by collect.py for the website.
write_state() {
  [ "$LAB_APPLY" = 1 ] || return 0
  mkdir -p "$STATE_DIR" && printf '%s\n' "$2" > "$STATE_DIR/$1.json.tmp" && mv "$STATE_DIR/$1.json.tmp" "$STATE_DIR/$1.json"
}

# roster_rows: prints user|full name|department for every valid line of the roster.
roster_rows() {
  [ -f "$ROSTER" ] || return 1
  local u full d n=0
  while IFS=, read -r u full d; do
    n=$((n+1)); [ "$n" -eq 1 ] && continue
    [ -z "$u" ] && continue
    if ! [[ $u =~ ^[a-z][a-z0-9_-]{0,31}$ ]]; then warn "roster line $n: bad username '$u', skipped"; continue; fi
    if ! [[ " $DEPARTMENTS " == *" $d "* ]]; then warn "roster line $n: unknown department '$d', skipped"; continue; fi
    printf '%s|%s|%s\n' "$u" "$full" "$d"
  done < "$ROSTER"
}
