#!/usr/bin/env bash
# Testing on macOS (read-only): checks this Mac and the website. Nothing is changed.
# The Linux lab server uses test.sh (services, simulated faults, validation); a Mac has none of
# cron/ufw/LVM/useradd, so this is the macOS equivalent of "verify" and "validate".
# Works with the bash 3.2 that macOS ships.
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$HERE/../.." && pwd)"
OUT="$PROJECT/.labstate/tests.json"
T=$'\t'
RES=(); N_PASS=0; N_WARN=0; N_FAIL=0; CUR_TASK=verify

rec() { # level name [detail]
  RES+=("$CUR_TASK$T$1$T$2$T${3:-}")
  case $1 in pass) N_PASS=$((N_PASS + 1)) ;; warn) N_WARN=$((N_WARN + 1)) ;; fail) N_FAIL=$((N_FAIL + 1)) ;; esac
  printf '  [%-4s] %s%s\n' "$1" "$2" "${3:+  ($3)}"
}
expect() { if [ "$2" = "$3" ]; then rec pass "$1" "expected $2, got $3"; else rec fail "$1" "expected $2, got ${3:-nothing}"; fi; }
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

if [ "$(uname -s)" = Darwin ]; then fmode() { stat -f %Lp "$1"; }; fmtime() { stat -f %m "$1"; }; else fmode() { stat -c %a "$1"; }; fmtime() { stat -c %Y "$1"; }; fi

# first value wins, like sshd; files in sshd_config.d come first on macOS
ssh_value() { # key default
  local v
  v=$(cat /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null | awk -v k="$(echo "$1" | tr 'A-Z' 'a-z')" 'tolower($1)=="match"{exit} tolower($1)==k{print $2; exit}')
  echo "${v:-$2}"
}

printf '\n== Task 7.1  Verify (macOS)\n'
CUR_TASK=verify
[ "$(uname -s)" = Darwin ] && rec pass "Operating system" "macOS $(sw_vers -productVersion 2>/dev/null)" || rec fail "Operating system" "this script is for macOS"
rec pass "Hostname" "$(scutil --get ComputerName 2>/dev/null || hostname)"
gw=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
if [ -n "$gw" ]; then rec pass "Network" "default gateway $gw"; else rec fail "Network" "no default route"; fi
fw=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)
case "$fw" in *enabled*) rec pass "macOS firewall" "on" ;; *disabled*) rec warn "macOS firewall" "off: System Settings > Network > Firewall" ;; *) rec warn "macOS firewall" "could not read the state" ;; esac
if nc -z -w 1 127.0.0.1 22 >/dev/null 2>&1; then rec warn "Remote Login (SSH)" "on; turn it off in Sharing settings if not needed"; else rec pass "Remote Login (SSH)" "off, nothing can log in remotely"; fi
used=$(df -k / | awk 'NR==2{gsub("%","",$5); print $5}')
if [ "${used:-0}" -lt 90 ]; then rec pass "Disk space" "${used}% used"; else rec fail "Disk space" "${used}% used"; fi
command -v node >/dev/null 2>&1 && rec pass "Node.js (for the website)" "$(node -v)" || rec fail "Node.js (for the website)" "install it: brew install node"
command -v python3 >/dev/null 2>&1 && rec pass "Python 3 (for the collector)" "$(python3 -V 2>&1)" || rec fail "Python 3 (for the collector)" "missing"
[ -d "$PROJECT/node_modules" ] && rec pass "Website dependencies" "node_modules present" || rec warn "Website dependencies" "run: npm install"
D="$PROJECT/public/data.json"
if [ -f "$D" ]; then
  age=$(( ( $(date +%s) - $(fmtime "$D") ) / 60 ))
  if [ "$age" -le 15 ]; then rec pass "Website data" "public/data.json is ${age} min old"; else rec warn "Website data" "${age} min old: run ./server/labctl status"; fi
else rec fail "Website data" "missing: run ./server/labctl status"; fi

printf '\n== Task 7.3  Validate expected outputs (macOS)\n'
CUR_TASK=validate
rl=$(ssh_value PermitRootLogin prohibit-password)
case "$rl" in no|prohibit-password|without-password) rec pass "SSH PermitRootLogin" "$rl (root cannot log in with a password)" ;; *) rec fail "SSH PermitRootLogin" "$rl (should be no or prohibit-password)" ;; esac
expect "SSH PermitEmptyPasswords" "no" "$(ssh_value PermitEmptyPasswords no)"
tries=$(ssh_value MaxAuthTries 6)
if [ "$tries" -le 4 ] 2>/dev/null; then rec pass "SSH MaxAuthTries" "$tries"; else rec warn "SSH MaxAuthTries" "$tries (4 or less is stricter)"; fi
if [ -f "$D" ]; then
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('platform')=='darwin' and d.get('security') else 1)" "$D" \
    && rec pass "data.json is a valid macOS report" "platform darwin, security section present" || rec fail "data.json is a valid macOS report" "unexpected content"
fi
hm=$(fmode "$HOME")
case "$hm" in *0) rec pass "Home folder closed to other users" "mode $hm" ;; *) rec fail "Home folder closed to other users" "mode $hm lets others in: chmod 750 ~" ;; esac

printf '\n== Summary\n  %s passed, %s warnings, %s failed\n' "$N_PASS" "$N_WARN" "$N_FAIL"
mkdir -p "$PROJECT/.labstate"
{
  printf '{"time":"%s","apply":false,"mac":true,"pass":%s,"warn":%s,"fail":%s,"results":[' "$(date +%Y-%m-%dT%H:%M:%S)" "$N_PASS" "$N_WARN" "$N_FAIL"
  first=1
  for r in "${RES[@]}"; do
    IFS=$'\t' read -r task lvl name detail <<<"$r"
    [ $first = 1 ] || printf ','; first=0
    printf '{"task":"%s","level":"%s","name":"%s","detail":"%s"}' "$task" "$lvl" "$(jesc "$name")" "$(jesc "${detail:-}")"
  done
  printf '],"issues":[]}\n'
} > "$OUT"
echo "  recorded in .labstate/tests.json (shown on the Testing page after: ./server/labctl status)"
[ "$N_FAIL" -eq 0 ]
