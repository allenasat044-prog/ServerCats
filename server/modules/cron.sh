#!/usr/bin/env bash
# Automation: install the cron schedule that runs the routine scripts.
. "$(dirname "$0")/../lib/common.sh"

main() {
  need_root_if_apply
  step "Cron schedule (/etc/cron.d/labserver)"
  command -v cron >/dev/null 2>&1 || warn "cron is not installed (run: labctl system packages --apply)"
  local ctl="$SERVER_DIR/labctl" log=/var/log/labserver.log
  put_file /etc/cron.d/labserver 644 <<CRON
# Managed by labctl cron. Change the schedules in server/lab.conf and run: labctl cron --apply
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$STATUS_CRON root $ctl status >> $log 2>&1
$BACKUP_CRON root $ctl backup --apply >> $log 2>&1
$CLEANUP_CRON root $ctl cleanup --apply >> $log 2>&1
$UPDATE_CRON root $ctl system update --apply >> $log 2>&1
CRON
  put_file /etc/logrotate.d/labserver 644 <<'ROT'
/var/log/labserver.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
ROT
  if [ "$LAB_APPLY" = 1 ] && command -v systemctl >/dev/null 2>&1; then systemctl enable --now cron >/dev/null 2>&1 && ok "cron service is enabled"; fi
  return 0
}
main "$@"
