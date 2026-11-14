#!/usr/bin/env bash
# Security: firewall (ufw), SSH hardening, file and directory permissions.
. "$(dirname "$0")/../lib/common.sh"

ssh_port() { sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}'; }
ssh_service() { if systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then echo ssh; else echo sshd; fi; }

# macOS helpers: admins come from the "admin" group, files belong to root:wheel
admin_users() { if [ "$IS_DARWIN" = 1 ]; then dscl . -read /Groups/admin GroupMembership 2>/dev/null | cut -d: -f2; else getent group sudo | cut -d: -f4 | tr ',' ' '; fi; }
home_of() { if [ "$IS_DARWIN" = 1 ]; then dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | awk '{print $2}'; else getent passwd "$1" | cut -d: -f6; fi; }
ROOTGRP=root; [ "$IS_DARWIN" = 1 ] && ROOTGRP=wheel

step_firewall() {
  step "Firewall"
  if [ "$IS_DARWIN" = 1 ]; then
    local sf=/usr/libexec/ApplicationFirewall/socketfilterfw
    [ -x "$sf" ] || { skip "macOS Application Firewall tool not found"; return; }
    say "  macOS filters per application (there are no port rules). Built-in services such as Remote Login stay reachable."
    run "$sf" --setglobalstate on
    run "$sf" --setstealthmode on
    run "$sf" --setallowsigned on
    return 0
  fi
  command -v ufw >/dev/null 2>&1 || { skip "ufw is not installed (run: labctl system packages --apply)"; return; }
  local port p; port=$(ssh_port); port=${port:-22}
  say "  SSH is on port $port; it is always allowed first so you cannot lock yourself out"
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw limit "$port/tcp"
  for p in $FIREWALL_ALLOW_TCP; do
    [[ $p =~ ^[0-9]+$ ]] || die "FIREWALL_ALLOW_TCP: '$p' is not a port number"
    run ufw allow "$p/tcp"
  done
  run ufw --force enable
}

step_ssh() {
  step "SSH access"
  command -v sshd >/dev/null 2>&1 || { skip "OpenSSH server is not installed"; return; }
  local conf=/etc/ssh/sshd_config.d/00-labserver.conf u home keys=0 admins
  admins=$(admin_users)
  if [ "$IS_DARWIN" = 1 ] && ! grep -qs '^Include /etc/ssh/sshd_config.d' /etc/ssh/sshd_config; then
    die "/etc/ssh/sshd_config does not include /etc/ssh/sshd_config.d (old macOS): the hardening file would be ignored"
  fi
  if [ "$SSH_PERMIT_ROOT" = no ] && [ -z "$admins" ]; then
    die "no user is an administrator: disabling root SSH login would lock you out. Create an admin user first."
  fi
  if [ "$SSH_PASSWORD_AUTH" = no ]; then
    for u in $admins; do
      home=$(home_of "$u")
      [ -s "$home/.ssh/authorized_keys" ] && keys=1
    done
    [ "$keys" = 1 ] || die "SSH_PASSWORD_AUTH=no but no admin has an authorized SSH key: you would be locked out. Install a key first."
  fi
  # 00- prefix: sshd uses the FIRST value it sees, and cloud images ship 50-cloud-init.conf
  local tmp; tmp=$(mktemp)
  {
    echo "# Managed by labctl security ssh"
    echo "PermitRootLogin $SSH_PERMIT_ROOT"
    echo "PasswordAuthentication $SSH_PASSWORD_AUTH"
    echo "PubkeyAuthentication yes"
    echo "PermitEmptyPasswords no"
    echo "MaxAuthTries $SSH_MAX_AUTH_TRIES"
    echo "LoginGraceTime 30"
    echo "X11Forwarding no"
    echo "ClientAliveInterval 300"
    echo "ClientAliveCountMax 2"
    [ -n "$SSH_ALLOW_GROUPS" ] && echo "AllowGroups $SSH_ALLOW_GROUPS"
  } > "$tmp"
  if [ -f "$conf" ] && cmp -s "$tmp" "$conf"; then ok "$conf is already up to date"; rm -f "$tmp"; return; fi
  if [ "$LAB_APPLY" != 1 ]; then
    printf '  (plan) write %s:\n' "$conf"; sed 's/^/        | /' "$tmp"; rm -f "$tmp"; return
  fi
  local old=""; [ -f "$conf" ] && { old=$(mktemp); cp "$conf" "$old"; }
  install -m 644 -o root -g "$ROOTGRP" "$tmp" "$conf"; rm -f "$tmp"
  if sshd -t; then
    if [ "$IS_DARWIN" = 1 ]; then ok "SSH hardened (macOS reads the file for every new login; keep this session open and test a new login)"
    else systemctl reload "$(ssh_service)" && ok "SSH hardened and reloaded (keep this session open and test a new login)"; fi
  else
    if [ -n "$old" ]; then cp "$old" "$conf"; else rm -f "$conf"; fi
    die "sshd rejected the new configuration: reverted"
  fi
  [ -n "$old" ] && rm -f "$old"
  return 0
}

step_permissions() {
  step "File and directory permissions"
  local h n=0
  if [ "$IS_DARWIN" = 1 ]; then
    while IFS= read -r h; do
      [ -d "$h" ] || continue
      if [ "$(fmode "$h")" -gt 750 ] 2>/dev/null; then n=$((n + 1)); run chmod 750 "$h"; fi
    done < <(ls -d /Users/*/ 2>/dev/null | sed 's#/$##' | grep -v -e '/Shared$' -e '/Guest$')
  else
    while IFS= read -r h; do
      [ -d "$h" ] || continue
      if [ "$(fmode "$h")" -gt 750 ] 2>/dev/null; then n=$((n + 1)); run chmod 750 "$h"; fi
    done < <(awk -F: '$3>=1000 && $3<60000 && $6 ~ /^\/home\//{print $6}' /etc/passwd)
  fi
  [ "$n" -eq 0 ] && ok "no home directory is readable by others"
  if [ -d "$LAB_BASE/shared" ]; then
    if [ -n "$(find "$LAB_BASE/shared" -perm -o+w ! -type l -print 2>/dev/null | head -n 1)" ]; then
      run find "$LAB_BASE/shared" -perm -o+w ! -type l -exec chmod o-w {} +
    else ok "nothing in $LAB_BASE/shared is writable by others"; fi
  fi
  if [ -d "$LAB_BASE/backups" ]; then
    if [ "$(fmode "$LAB_BASE/backups")" != 700 ]; then run chmod 700 "$LAB_BASE/backups"; else ok "backup folder is 700"; fi
  fi
  if [ "$IS_DARWIN" != 1 ] && [ -e /etc/shadow ] && [ "$(fmode /etc/shadow)" -gt 640 ]; then run chmod 640 /etc/shadow; fi
  return 0
}

main() {
  need_root_if_apply_any
  local steps=("$@"); [ ${#steps[@]} -eq 0 ] && steps=(firewall ssh permissions)
  local s
  for s in "${steps[@]}"; do
    case $s in firewall|ssh|permissions) "step_$s" ;; *) die "unknown step '$s' (firewall|ssh|permissions)" ;; esac
  done
}
main "$@"
