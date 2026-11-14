#!/usr/bin/env bash
# System configuration: hostname, network settings, OS update, required software.
. "$(dirname "$0")/../lib/common.sh"

step_hostname() {
  step "Hostname"
  local cur; cur=$(hostname)
  if [ -z "$LAB_HOSTNAME" ]; then skip "LAB_HOSTNAME is empty in lab.conf (current hostname: $cur)"; return; fi
  [[ $LAB_HOSTNAME =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || die "invalid hostname '$LAB_HOSTNAME'"
  if [ "$cur" = "$LAB_HOSTNAME" ]; then ok "hostname is already $cur"; return; fi
  run hostnamectl set-hostname "$LAB_HOSTNAME"
  if [ "$LAB_APPLY" = 1 ]; then
    if grep -q '^127\.0\.1\.1' /etc/hosts; then sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $LAB_HOSTNAME/" /etc/hosts
    else echo "127.0.1.1 $LAB_HOSTNAME" >> /etc/hosts; fi
    ok "/etc/hosts now maps 127.0.1.1 to $LAB_HOSTNAME"
  else
    printf '  (plan) point 127.0.1.1 in /etc/hosts at %s\n' "$LAB_HOSTNAME"
  fi
}

step_network() {
  step "Network settings"
  if command -v ip >/dev/null 2>&1; then
    say "  current addresses:"; ip -br addr | sed 's/^/    /'
    say "  default route: $(ip route show default | head -1)"
  fi
  if [ -z "$NET_ADDRESS" ]; then skip "NET_ADDRESS is empty in lab.conf: keeping the current network configuration"; return; fi
  [ -n "$NET_IFACE" ] && [ -n "$NET_GATEWAY" ] && [ -n "$NET_DNS" ] \
    || die "a static IP needs NET_IFACE, NET_ADDRESS (CIDR), NET_GATEWAY and NET_DNS"
  [[ $NET_ADDRESS == */* ]] || die "NET_ADDRESS must be in CIDR form (address/prefix)"
  local dns; dns=$(echo "$NET_DNS" | tr -s ' ,' ',' | sed 's/^,//; s/,$//; s/,/, /g')
  put_file /etc/netplan/60-labserver.yaml 600 <<YAML
# Managed by labctl system network
network:
  version: 2
  ethernets:
    $NET_IFACE:
      dhcp4: false
      addresses: [$NET_ADDRESS]
      routes:
        - to: default
          via: $NET_GATEWAY
      nameservers:
        addresses: [$dns]
YAML
  if [ "$LAB_APPLY" = 1 ]; then
    netplan generate || die "netplan rejected the configuration (removing it)"
    say "  Applying with a 60 second safety timer: press ENTER to keep it, otherwise it rolls back."
    netplan try --timeout 60
  fi
}

step_update() {
  step "Operating system update"
  if [ "$LAB_APPLY" != 1 ]; then
    local n; n=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
    printf '  (plan) apt-get update && apt-get upgrade  (%s packages upgradable according to the current package lists)\n' "$n"
  else
    apt-get update -q || die "apt-get update failed"
    apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold upgrade || die "apt-get upgrade failed"
    write_state update "{\"time\":\"$(date -Is)\",\"ok\":true}"
    ok "system is up to date"
  fi
  [ -f /var/run/reboot-required ] && warn "a reboot is required to finish the update"
  return 0
}

step_packages() {
  step "Required software packages"
  local p missing=()
  for p in $PACKAGES; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if [ ${#missing[@]} -eq 0 ]; then ok "all $(echo "$PACKAGES" | wc -w) packages are installed"; return; fi
  say "  missing: ${missing[*]}"
  run apt-get update -q
  run apt-get install -y -q "${missing[@]}"
}

main() {
  need_root_if_apply
  local steps=("$@"); [ ${#steps[@]} -eq 0 ] && steps=(hostname network update packages)
  local s
  for s in "${steps[@]}"; do
    case $s in hostname|network|update|packages) "step_$s" ;; *) die "unknown step '$s' (hostname|network|update|packages)" ;; esac
  done
}
main "$@"
