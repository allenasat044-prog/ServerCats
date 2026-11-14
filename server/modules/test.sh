#!/usr/bin/env bash
# Testing & troubleshooting:
#   verify          check that every configured service and setting is in place (read-only)
#   troubleshoot    break things on purpose, detect each fault, fix it, prove it is fixed (needs --apply)
#   validate        compare expected values from lab.conf with what the system really reports (read-only)
# Without --apply, verify and validate still run (they only read); troubleshoot prints its plan.
. "$(dirname "$0")/../lib/common.sh"

MOD_DIR="$(cd "$(dirname "$0")" && pwd)"
BK="$LAB_BASE/backups"
T=$'\t'
RES=(); ISS=()
N_PASS=0; N_WARN=0; N_FAIL=0
CUR_TASK=verify
SKIP=""
IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1

# ---- recording ---------------------------------------------------------------
rec() { # level name [detail]
  local lvl=$1 name=$2 detail=${3:-}
  RES+=("$CUR_TASK$T$lvl$T$name$T$detail")
  case $lvl in
    pass) N_PASS=$((N_PASS + 1)) ;;
    warn) N_WARN=$((N_WARN + 1)) ;;
    fail) N_FAIL=$((N_FAIL + 1)) ;;
  esac
  printf '  [%-4s] %s%s\n' "$lvl" "$name" "${detail:+  ($detail)}"
}
expect() { # name expected actual
  if [ "$2" = "$3" ]; then rec pass "$1" "expected $2, got $3"; else rec fail "$1" "expected $2, got ${3:-nothing}"; fi
}

ssh_service() { if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then echo ssh; else echo sshd; fi; }
svc_active() { systemctl is-active --quiet "$1" 2>/dev/null; }
latest_backup() { ls -1t "$BK"/lab-backup-*.tar.gz 2>/dev/null | head -1; }
first_dept() { set -- $DEPARTMENTS; echo "${1:-}"; }

# ---- 7.1 verify all configured services -------------------------------------
step_verify() {
  step "Task 7.1  Verify all configured services"
  CUR_TASK=verify
  local s d p missing="" n=0 have=0 u f

  s=$(ssh_service)
  if svc_active "$s"; then rec pass "SSH service ($s)" "active"; else rec fail "SSH service ($s)" "not running: systemctl start $s"; fi
  if svc_active cron; then rec pass "Cron service" "active"; else rec fail "Cron service" "not running: systemctl start cron"; fi

  if ! command -v ufw >/dev/null 2>&1; then rec fail "Firewall (ufw)" "ufw is not installed"
  elif [ "$IS_ROOT" -ne 1 ]; then rec warn "Firewall (ufw)" "run with sudo to read the firewall state"
  elif ufw status 2>/dev/null | grep -q '^Status: active'; then rec pass "Firewall (ufw)" "active"
  else rec fail "Firewall (ufw)" "inactive: sudo labctl security firewall --apply"; fi

  if [ -n "$LAB_HOSTNAME" ]; then expect "Hostname" "$LAB_HOSTNAME" "$(hostname)"; else rec pass "Hostname" "$(hostname) (LAB_HOSTNAME not set)"; fi

  if ip route 2>/dev/null | grep -q '^default'; then rec pass "Network" "default route via $(ip route | awk '/^default/{print $3; exit}')"; else rec fail "Network" "no default route"; fi
  if [ -n "$NET_ADDRESS" ]; then
    if ip -4 addr 2>/dev/null | grep -qF "${NET_ADDRESS%%/*}"; then rec pass "Static address" "$NET_ADDRESS present"; else rec fail "Static address" "$NET_ADDRESS not on any interface"; fi
  fi

  if [ -n "$PACKAGES" ]; then
    for p in $PACKAGES; do n=$((n + 1)); if dpkg -s "$p" >/dev/null 2>&1; then have=$((have + 1)); else missing="$missing $p"; fi; done
    if [ -z "$missing" ]; then rec pass "Required packages" "all $n installed"; else rec fail "Required packages" "$have of $n installed; missing:$missing"; fi
  fi

  missing=""
  for d in $DEPARTMENTS students; do getent group "lab-$d" >/dev/null 2>&1 || missing="$missing lab-$d"; done
  if [ -z "$missing" ]; then rec pass "Lab groups" "all exist"; else rec fail "Lab groups" "missing:$missing"; fi

  missing=""
  for d in $DEPARTMENTS; do [ -d "$LAB_BASE/shared/$d" ] || missing="$missing $d"; done
  if [ -z "$missing" ]; then rec pass "Shared directories" "all exist under $LAB_BASE/shared"; else rec fail "Shared directories" "missing:$missing"; fi

  if mountpoint -q "$LVM_MOUNT" 2>/dev/null; then rec pass "Lab volume mounted" "$LVM_MOUNT"
  elif [ -n "$DATA_DISK" ]; then rec fail "Lab volume mounted" "$LVM_MOUNT is not a mount point"
  else rec pass "Lab volume" "$LVM_MOUNT lives on the root filesystem (no DATA_DISK configured)"; fi

  if [ -f /etc/cron.d/labserver ]; then rec pass "Cron schedule installed" "/etc/cron.d/labserver"; else rec fail "Cron schedule installed" "run: sudo labctl cron --apply"; fi

  f=$(latest_backup)
  if [ -z "$f" ]; then rec fail "Latest backup" "none found in $BK: run sudo labctl backup --apply"
  elif gzip -t "$f" 2>/dev/null && (cd "$BK" && sha256sum -c --status "$(basename "$f").sha256" 2>/dev/null); then rec pass "Latest backup" "$(basename "$f") passes gzip and SHA-256 checks"
  else rec fail "Latest backup" "$(basename "$f") failed its integrity check"; fi

  if [ -f "$ROSTER" ]; then
    n=0; have=0
    while IFS='|' read -r u _; do n=$((n + 1)); getent passwd "$u" >/dev/null 2>&1 && have=$((have + 1)); done < <(roster_rows 2>/dev/null)
    if [ "$n" -eq 0 ]; then rec warn "Student accounts" "roster has no valid rows"
    elif [ "$n" -eq "$have" ]; then rec pass "Student accounts" "all $n roster users exist"
    else rec fail "Student accounts" "$have of $n roster users exist: run sudo labctl users accounts --apply"; fi
  fi
}

# ---- 7.2 resolve simulated system issues ------------------------------------
# Every scenario has: pre_X (can it run?), inject_X, detect_X (0 = problem present), fix_X.
DEPT=$(first_dept); DDIR="$LAB_BASE/shared/$DEPT"
ORIG_MODE=""; CRON_WAS=0; UFW_WAS=0; BADCOPY="$BK/.labtest-corrupt.tar.gz"

pre_stale() { [ -d "$LAB_BASE/tmp" ] || { SKIP="$LAB_BASE/tmp does not exist (run labctl storage shared --apply)"; return 1; }; }
inject_stale() { local i f; for i in 1 2 3; do f="$LAB_BASE/tmp/.labtest-stale-$i"; echo test > "$f"; touch -d "$((CLEANUP_DAYS + 5)) days ago" "$f"; done; }
detect_stale() { [ -n "$(find "$LAB_BASE/tmp" -maxdepth 1 -name '.labtest-stale-*' -mtime +"$CLEANUP_DAYS" -print -quit 2>/dev/null)" ]; }
fix_stale() { LAB_APPLY=1 bash "$MOD_DIR/cleanup.sh" >/dev/null 2>&1; }

pre_perm() { [ -n "$DEPT" ] && [ -d "$DDIR" ] || { SKIP="shared folder $DDIR does not exist"; return 1; }; }
inject_perm() { ORIG_MODE=$(stat -c %a "$DDIR"); chmod o+w "$DDIR"; }
detect_perm() { [ -n "$(find "$DDIR" -maxdepth 0 -perm -o+w -print 2>/dev/null)" ]; }
fix_perm() { LAB_APPLY=1 bash "$MOD_DIR/security.sh" permissions >/dev/null 2>&1; }

pre_owner() { [ -n "$DEPT" ] && [ -d "$DDIR" ] || { SKIP="shared folder $DDIR does not exist"; return 1; }; getent group "lab-$DEPT" >/dev/null || { SKIP="group lab-$DEPT is missing"; return 1; }; }
inject_owner() { mkdir -p "$DDIR/.labtest-owner" && chown nobody "$DDIR/.labtest-owner"; }
detect_owner() { [ "$(stat -c %U "$DDIR/.labtest-owner" 2>/dev/null)" != root ]; }
fix_owner() { chown "root:lab-$DEPT" "$DDIR/.labtest-owner"; }

pre_cron() { command -v systemctl >/dev/null 2>&1 && svc_active cron || { SKIP="cron service is not running or not installed"; return 1; }; CRON_WAS=1; }
inject_cron() { systemctl stop cron; }
detect_cron() { ! svc_active cron; }
fix_cron() { systemctl start cron; sleep 1; }

pre_ufw() { command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active' || { SKIP="ufw is not installed or not active (run labctl security firewall --apply)"; return 1; }; UFW_WAS=1; }
inject_ufw() { ufw disable >/dev/null 2>&1; }
detect_ufw() { ! ufw status 2>/dev/null | grep -q '^Status: active'; }
fix_ufw() { ufw --force enable >/dev/null 2>&1; }

pre_backup() { [ -n "$(latest_backup)" ] || { SKIP="no backup yet (run labctl backup --apply)"; return 1; }; }
inject_backup() { cp "$(latest_backup)" "$BADCOPY" && truncate -s "$(( $(stat -c %s "$BADCOPY") / 2 ))" "$BADCOPY"; }
detect_backup() { ! gzip -t "$BADCOPY" 2>/dev/null; }
fix_backup() { cp -f "$(ls -1t "$BK"/lab-backup-*.tar.gz | head -1)" "$BADCOPY"; }   # recover the damaged copy from the good archive

restore_everything() {
  rm -f "$LAB_BASE"/tmp/.labtest-stale-* "$BADCOPY" 2>/dev/null
  rm -rf "$DDIR/.labtest-owner" 2>/dev/null
  [ -n "$ORIG_MODE" ] && [ -d "$DDIR" ] && chmod "$ORIG_MODE" "$DDIR"
  [ "$CRON_WAS" = 1 ] && ! svc_active cron && systemctl start cron
  [ "$UFW_WAS" = 1 ] && ! ufw status 2>/dev/null | grep -q '^Status: active' && ufw --force enable >/dev/null 2>&1
  return 0
}

run_scenario() { # id title what-it-simulates
  local id=$1 title=$2 what=$3 inj=no det=no fix=no val=no note=""
  if [ "$LAB_APPLY" != 1 ]; then printf '  (plan) %s: %s\n' "$title" "$what"; return; fi
  printf '\n  -- %s\n     %s\n' "$title" "$what"
  SKIP=""
  if ! "pre_$id"; then
    rec warn "Resolve: $title" "skipped: $SKIP"
    ISS+=("$id$T$title$T$what${T}skipped${T}skipped${T}skipped${T}skipped$T$SKIP"); return
  fi
  "inject_$id" && inj=yes
  if [ "$inj" = yes ] && "detect_$id"; then det=yes; fi
  if [ "$det" = yes ] && "fix_$id"; then fix=yes; fi
  if [ "$fix" = yes ] && ! "detect_$id"; then val=yes; fi
  printf '     fault injected: %s   detected: %s   fixed: %s   confirmed gone: %s\n' "$inj" "$det" "$fix" "$val"
  if [ "$val" = yes ]; then rec pass "Resolve: $title" "injected, detected, fixed, confirmed gone"
  else
    [ "$inj" != yes ] && note="could not inject the fault"
    [ -z "$note" ] && [ "$det" != yes ] && note="fault was not detected"
    [ -z "$note" ] && [ "$fix" != yes ] && note="fix command failed"
    [ -z "$note" ] && note="fault still present after the fix"
    rec fail "Resolve: $title" "$note"
  fi
  ISS+=("$id$T$title$T$what$T$inj$T$det$T$fix$T$val$T$note")
}

step_troubleshoot() {
  step "Task 7.2  Resolve simulated system issues"
  CUR_TASK=troubleshoot
  [ "$LAB_APPLY" = 1 ] && trap restore_everything EXIT
  [ "$LAB_APPLY" = 1 ] && say "  Each fault is created on purpose, detected, repaired and re-checked. Test files are removed afterwards."
  run_scenario stale   "Old files piling up in the temp folder" "three files older than $CLEANUP_DAYS days are created, then labctl cleanup removes them"
  run_scenario perm    "Shared folder writable by everyone"    "o+w is set on $DDIR, then labctl security permissions closes it"
  run_scenario owner   "Wrong owner on a shared file"          "a folder in $DDIR is given to user nobody, then chown puts root:lab-$DEPT back"
  run_scenario cron    "Cron service stopped"                  "cron is stopped (scheduled jobs would silently not run), then started again"
  run_scenario ufw     "Firewall switched off"                 "ufw is disabled, then re-enabled"
  run_scenario backup  "Corrupted backup archive"              "a copy of the newest archive is cut in half, gzip -t catches it, and it is restored from the good archive"
  if [ "$LAB_APPLY" != 1 ]; then say "  (plan) nothing was changed. Run: sudo ./server/labctl test troubleshoot --apply"; fi
}

# ---- 7.3 validate expected outputs ------------------------------------------
step_validate() {
  step "Task 7.3  Validate expected outputs"
  CUR_TASK=validate
  local d u act exp f c fail_sched=""

  if command -v sshd >/dev/null 2>&1 && [ "$IS_ROOT" -eq 1 ]; then
    c=$(sshd -T 2>/dev/null)
    expect "sshd PermitRootLogin" "$SSH_PERMIT_ROOT" "$(awk '$1=="permitrootlogin"{print $2}' <<<"$c")"
    expect "sshd MaxAuthTries" "$SSH_MAX_AUTH_TRIES" "$(awk '$1=="maxauthtries"{print $2}' <<<"$c")"
    expect "sshd PasswordAuthentication" "$SSH_PASSWORD_AUTH" "$(awk '$1=="passwordauthentication"{print $2}' <<<"$c")"
    expect "sshd PermitEmptyPasswords" "no" "$(awk '$1=="permitemptypasswords"{print $2}' <<<"$c")"
  else rec warn "SSH settings" "needs root and openssh-server (run with sudo)"; fi

  if command -v ufw >/dev/null 2>&1 && [ "$IS_ROOT" -eq 1 ]; then
    if ufw status verbose 2>/dev/null | grep -q '^Default:.*deny (incoming)'; then rec pass "Firewall default for incoming traffic" "expected deny, got deny"
    else rec fail "Firewall default for incoming traffic" "expected deny (incoming)"; fi
  else rec warn "Firewall defaults" "needs root and ufw (run with sudo)"; fi

  for d in $DEPARTMENTS; do
    [ -d "$LAB_BASE/shared/$d" ] || { rec fail "Shared folder $d" "missing"; continue; }
    expect "Shared folder $d (mode owner:group)" "2770 root:lab-$d" "$(stat -c '%a %U:%G' "$LAB_BASE/shared/$d")"
  done
  [ -d "$LAB_BASE/tmp" ] && expect "Temp folder mode" "1777" "$(stat -c %a "$LAB_BASE/tmp")"
  [ -d "$BK" ] && expect "Backup folder mode" "700" "$(stat -c %a "$BK")"

  if [ -f /etc/cron.d/labserver ]; then
    for exp in "$STATUS_CRON" "$BACKUP_CRON" "$CLEANUP_CRON" "$UPDATE_CRON"; do
      grep -qF "$exp root" /etc/cron.d/labserver || fail_sched="$fail_sched [$exp]"
    done
    if [ -z "$fail_sched" ]; then rec pass "Cron schedules match lab.conf" "4 of 4 present"; else rec fail "Cron schedules match lab.conf" "missing:$fail_sched"; fi
  else rec fail "Cron schedules match lab.conf" "/etc/cron.d/labserver does not exist"; fi

  if [ "$IS_ROOT" -eq 1 ] && [ -f "$ROSTER" ]; then
    u=$(roster_rows 2>/dev/null | head -1 | cut -d'|' -f1)
    if [ -n "$u" ] && getent passwd "$u" >/dev/null 2>&1; then
      expect "Password max age for $u (days)" "$PASSWORD_MAX_DAYS" "$(getent shadow "$u" | cut -d: -f5)"
      d=$(roster_rows | head -1 | cut -d'|' -f3)
      expect "Primary group of $u" "lab-$d" "$(id -gn "$u" 2>/dev/null)"
      expect "Home directory mode of $u" "750" "$(stat -c %a "$(getent passwd "$u" | cut -d: -f6)" 2>/dev/null)"
    else rec warn "Account checks" "roster user '$u' does not exist yet"; fi
  else rec warn "Account checks" "needs root and a roster (run with sudo)"; fi

  f=$(latest_backup)
  if [ -n "$f" ] && [ -f "$f.sha256" ]; then
    act=$(cd "$BK" && sha256sum "$(basename "$f")" | cut -d' ' -f1); exp=$(cut -d' ' -f1 < "$f.sha256")
    expect "Backup SHA-256 matches the recorded value" "${exp:0:16}..." "${act:0:16}..."
  else rec warn "Backup checksum" "no backup with a .sha256 file yet"; fi
}

# ---- state for the website ---------------------------------------------------
json_state() {
  local r task lvl name detail first=1 id title what inj det fix val note
  printf '{"time":"%s","apply":%s,"pass":%s,"warn":%s,"fail":%s,"results":[' "$(date -Is)" "$([ "$LAB_APPLY" = 1 ] && echo true || echo false)" "$N_PASS" "$N_WARN" "$N_FAIL"
  for r in "${RES[@]}"; do
    IFS=$'\t' read -r task lvl name detail <<<"$r"
    [ $first = 1 ] || printf ','; first=0
    printf '{"task":"%s","level":"%s","name":"%s","detail":"%s"}' "$task" "$lvl" "$(jesc "$name")" "$(jesc "${detail:-}")"
  done
  printf '],"issues":['; first=1
  for r in "${ISS[@]}"; do
    IFS=$'\t' read -r id title what inj det fix val note <<<"$r"
    [ $first = 1 ] || printf ','; first=0
    printf '{"id":"%s","title":"%s","what":"%s","injected":"%s","detected":"%s","fixed":"%s","validated":"%s","note":"%s"}' "$id" "$(jesc "$title")" "$(jesc "$what")" "$inj" "$det" "$fix" "$val" "$(jesc "${note:-}")"
  done
  printf ']}'
}

main() {
  need_root_if_apply
  local steps=("$@"); [ ${#steps[@]} -eq 0 ] && steps=(verify troubleshoot validate)
  local s
  for s in "${steps[@]}"; do
    case $s in verify|troubleshoot|validate) "step_$s" ;; *) die "unknown step '$s' (verify|troubleshoot|validate)" ;; esac
  done
  step "Summary"
  say "  $N_PASS passed, $N_WARN warnings, $N_FAIL failed"
  write_state tests "$(json_state)"
  [ "$LAB_APPLY" = 1 ] && say "  recorded in $STATE_DIR/tests.json (shown on the website's Testing page after: sudo ./server/labctl status)"
  [ "$N_FAIL" -eq 0 ] || exit 1
}
main "$@"
