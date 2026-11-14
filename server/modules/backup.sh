#!/usr/bin/env bash
# Backup & recovery: automated archive, integrity verification, restore demonstration, retention.
. "$(dirname "$0")/../lib/common.sh"

BK="$LAB_BASE/backups"
FILE=""; STARTED=0
GZ_OK=false; SHA_OK=false; LISTED=0
RESTORED=0; SAMPLED=0; MISMATCH=0; RESTORE_OK=false

latest_backup() { ls -1t "$BK"/lab-backup-*.tar.gz 2>/dev/null | head -1; }

verify_archive() {
  local f=$1
  GZ_OK=false; SHA_OK=false; LISTED=0
  gzip -t "$f" 2>/dev/null && GZ_OK=true
  if [ -f "$f.sha256" ] && (cd "$(dirname "$f")" && sha256sum -c --status "$(basename "$f").sha256"); then SHA_OK=true; fi
  LISTED=$(tar -tzf "$f" 2>/dev/null | grep -vc '/$')
}

# Restore the whole archive into a scratch folder, count what came back and
# compare up to 20 random files with the live copies (only files not modified since the backup started).
restore_test() {
  local f=$1 started=$2 dest rf live
  RESTORED=0; SAMPLED=0; MISMATCH=0; RESTORE_OK=false
  dest=$(mktemp -d "$BK/.restore-test.XXXXXX") || return 1
  if tar -xzf "$f" -C "$dest"; then
    RESTORED=$(find "$dest" ! -type d | wc -l)
    while IFS= read -r rf; do
      live="${rf#"$dest"}"
      [ -f "$live" ] && [ "$(stat -c %Y "$live")" -lt "$started" ] || continue
      SAMPLED=$((SAMPLED + 1))
      cmp -s "$rf" "$live" || MISMATCH=$((MISMATCH + 1))
    done < <(find "$dest" -type f | shuf -n 20)
    if [ "$RESTORED" -eq "$LISTED" ] && [ "$MISMATCH" -eq 0 ]; then RESTORE_OK=true; fi
  fi
  rm -rf "$dest"
}

step_create() {
  step "Create backup"
  local s rel=() ts rc
  for s in $BACKUP_SOURCES; do
    if [ -e "$s" ]; then rel+=("${s#/}"); else warn "backup source $s does not exist, skipped"; fi
  done
  [ ${#rel[@]} -gt 0 ] || die "none of the BACKUP_SOURCES exist"
  ts=$(date +%Y%m%d-%H%M%S); FILE="$BK/lab-backup-$ts.tar.gz"
  if [ "$LAB_APPLY" != 1 ]; then
    printf '  (plan) tar -czf %s of: %s\n' "$FILE" "${rel[*]}"
    printf '  (plan) then: sha256sum, gzip -t, tar -tzf, restore into a temp folder and compare, keep newest %s\n' "$BACKUP_KEEP"
    FILE=""; return
  fi
  mkdir -p "$BK"; chmod 700 "$BK"
  STARTED=$(date +%s)
  tar --warning=no-file-changed --exclude='*/.cache' -czf "$FILE" -C / "${rel[@]}"; rc=$?
  [ "$rc" -le 1 ] || die "tar failed (exit $rc)"
  (cd "$BK" && sha256sum "$(basename "$FILE")" > "$(basename "$FILE").sha256")
  ok "created $FILE ($(hb "$(stat -c %s "$FILE")"))"
}

step_verify() {
  step "Verify backup integrity"
  local f=${1:-$FILE}; [ -n "$f" ] || f=$(latest_backup)
  [ -f "$f" ] || { skip "no backup archive found in $BK"; return 1; }
  verify_archive "$f"
  say "  archive: $(basename "$f")"
  say "  gzip test: $GZ_OK   sha256 matches recorded checksum: $SHA_OK   entries: $LISTED"
  [ "$GZ_OK" = true ] && [ "$SHA_OK" = true ]
}

step_restore_demo() {
  step "Restore demonstration"
  restore_test "$FILE" "$STARTED"
  say "  restored $RESTORED of $LISTED entries; compared $SAMPLED random files with the live copies, $MISMATCH differ"
  say "  restore test: $([ "$RESTORE_OK" = true ] && echo PASSED || echo FAILED)"
}

step_prune() {
  step "Retention (keep newest $BACKUP_KEEP)"
  local f old
  old=$(ls -1t "$BK"/lab-backup-*.tar.gz 2>/dev/null | tail -n +$((BACKUP_KEEP + 1)))
  [ -n "$old" ] || { ok "nothing to delete"; return; }
  for f in $old; do run rm -f "$f" "$f.sha256"; done
}

# labctl backup restore [FILE] [DIR]: really restore an archive into a folder.
do_restore() {
  local f=${1:-} dest=${2:-}
  [ -n "$f" ] || f=$(latest_backup)
  [ -f "$f" ] || die "no backup archive found in $BK"
  [ -n "$dest" ] || dest="$LAB_BASE/restored-$(date +%Y%m%d-%H%M%S)"
  step "Restore $(basename "$f") into $dest"
  if [ -d "$dest" ] && [ -n "$(ls -A "$dest")" ]; then die "$dest is not empty"; fi
  run mkdir -p "$dest"
  run tar -xzf "$f" -C "$dest"
  [ "$LAB_APPLY" = 1 ] && { say "  restored $(find "$dest" ! -type d | wc -l) files. Top level:"; ls -1 "$dest" | sed 's/^/    /'; }
  return 0
}

full_run() {
  local t0 sha; t0=$(date +%s)
  step_create
  [ -n "$FILE" ] || return 0
  local verified=true
  step_verify "$FILE" || verified=false
  step_restore_demo
  sha=$(cut -d' ' -f1 < "$FILE.sha256")
  write_state backup "{\"file\":\"$(basename "$FILE")\",\"time\":\"$(date -Is)\",\"size\":$(stat -c %s "$FILE"),\"sha256\":\"$sha\",\"files\":$LISTED,\"restored\":$RESTORED,\"gzip_ok\":$GZ_OK,\"sha_ok\":$SHA_OK,\"restore_ok\":$RESTORE_OK,\"sampled\":$SAMPLED,\"mismatch\":$MISMATCH,\"seconds\":$(( $(date +%s) - t0 )),\"sources\":\"$(jesc "$BACKUP_SOURCES")\",\"keep\":$BACKUP_KEEP}"
  step_prune
  if [ "$verified" != true ] || [ "$RESTORE_OK" != true ]; then die "backup verification FAILED"; fi
}

main() {
  need_root_if_apply
  case "${1:-}" in
    "")      full_run; if [ "$LAB_APPLY" != 1 ]; then step_prune; fi ;;
    create)  step_create ;;
    verify)  step_verify "${2:-}" ;;
    restore) do_restore "${2:-}" "${3:-}" ;;
    *)       die "unknown step '$1' (create|verify|restore [FILE] [DIR])" ;;
  esac
}
main "$@"
