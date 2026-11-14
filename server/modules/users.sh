#!/usr/bin/env bash
# User & group administration: groups, accounts from the roster, passwords, ownership and permissions.
. "$(dirname "$0")/../lib/common.sh"

CREDS="$STATE_DIR/initial-passwords.csv"

generate_roster() {
  local n=${1:-100} i depts
  [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] || die "usage: labctl users generate-roster [N]"
  if [ -f "$ROSTER" ] && [ "$LAB_FORCE" != 1 ]; then die "$ROSTER already exists (use --force to overwrite)"; fi
  read -ra depts <<<"$DEPARTMENTS"
  {
    echo "username,fullname,department"
    for ((i = 1; i <= n; i++)); do
      printf 'student%03d,Student %03d,%s\n' "$i" "$i" "${depts[$(( (i - 1) % ${#depts[@]} ))]}"
    done
  } > "$ROSTER"
  ok "wrote $n accounts to $ROSTER (edit it to use real names before running 'users accounts --apply')"
}

step_groups() {
  step "Groups"
  local d; for d in $DEPARTMENTS students; do ensure_group "lab-$d"; done
  [ "$LAB_APPLY" = 1 ] && ok "groups: $(for d in $DEPARTMENTS students; do printf 'lab-%s ' "$d"; done)"
  return 0
}

step_policy() {
  step "Password policy"
  put_file /etc/security/pwquality.conf.d/labserver.conf 644 <<'CONF'
# Managed by labctl users policy
minlen = 10
dcredit = -1
ucredit = -1
lcredit = -1
retry = 3
CONF
  say "  accounts expire passwords every $PASSWORD_MAX_DAYS days (warning 14 days before)"
}

step_accounts() {
  step "Student accounts"
  [ -f "$ROSTER" ] || die "no roster at $ROSTER. Create it (username,fullname,department) or run: labctl users generate-roster 100"
  local u full d pw created=0 existing=0 rows
  rows=$(roster_rows) || die "cannot read roster"
  [ -n "$rows" ] || die "roster has no valid accounts"
  if [ "$LAB_APPLY" = 1 ]; then
    mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR"
    [ -f "$CREDS" ] || { ( umask 077; echo "username,initial_password" > "$CREDS" ); }
  fi
  while IFS='|' read -r u full d; do
    if id "$u" >/dev/null 2>&1; then
      existing=$((existing + 1))
      [ "$(id -gn "$u")" = "lab-$d" ] || run usermod -g "lab-$d" "$u"
      id -nG "$u" | tr ' ' '\n' | grep -qx lab-students || run usermod -aG lab-students "$u"
    else
      created=$((created + 1))
      if [ "$LAB_APPLY" = 1 ]; then
        pw=$(openssl rand -base64 9 | tr '+/' 'xy')
        useradd -m -s /bin/bash -g "lab-$d" -G lab-students -c "$full" "$u" || die "useradd $u failed"
        echo "$u:$pw" | chpasswd
        chage -d 0 -M "$PASSWORD_MAX_DAYS" -W 14 "$u"
        chmod 750 "/home/$u"
        echo "$u,$pw" >> "$CREDS"
      else
        printf '  (plan) useradd -m -g lab-%s -G lab-students "%s" with a random one-time password, forced change at first login\n' "$d" "$u"
      fi
    fi
  done <<<"$rows"
  say "  $created to create, $existing already present"
  [ "$LAB_APPLY" = 1 ] && [ "$created" -gt 0 ] && say "  one-time passwords are in $CREDS (root only). Hand them out, then delete that file."
  return 0
}

step_perms() {
  step "Home directory ownership and permissions"
  local u full d bad=0 seen=0
  while IFS='|' read -r u full d; do
    [ -d "/home/$u" ] || continue
    seen=$((seen + 1))
    if [ "$(stat -c '%a %U:%G' "/home/$u")" != "750 $u:lab-$d" ]; then
      bad=$((bad + 1)); run chown "$u:lab-$d" "/home/$u"; run chmod 750 "/home/$u"
    fi
  done < <(roster_rows)
  if [ "$seen" -eq 0 ]; then skip "no student home directories exist yet"
  elif [ "$bad" -eq 0 ]; then ok "all $seen student homes are 750 and owned by their user"; fi
  return 0
}

main() {
  if [ "${1:-}" = generate-roster ]; then generate_roster "${2:-100}"; return; fi
  need_root_if_apply
  local steps=("$@"); [ ${#steps[@]} -eq 0 ] && steps=(groups policy accounts perms)
  local s
  for s in "${steps[@]}"; do
    case $s in groups|policy|accounts|perms) "step_$s" ;; *) die "unknown step '$s' (groups|policy|accounts|perms|generate-roster)" ;; esac
  done
}
main "$@"
