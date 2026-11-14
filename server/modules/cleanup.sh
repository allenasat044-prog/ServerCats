#!/usr/bin/env bash
# Routine cleanup: delete files older than CLEANUP_DAYS in the lab temp folder.
. "$(dirname "$0")/../lib/common.sh"

main() {
  need_root_if_apply
  step "Cleanup of $LAB_BASE/tmp (files older than $CLEANUP_DAYS days)"
  local dir="$LAB_BASE/tmp"
  [ -d "$dir" ] || { skip "$dir does not exist yet (run: labctl storage shared --apply)"; return; }
  local before removed freed
  before=$(find "$dir" -type f | wc -l)
  read -r removed freed < <(find "$dir" -type f -mtime +"$CLEANUP_DAYS" -printf '%s\n' | awk '{n++; s+=$1} END{print n+0, s+0}')
  local cmd="find $dir -type f -mtime +$CLEANUP_DAYS -delete"
  if [ "$LAB_APPLY" = 1 ]; then
    find "$dir" -type f -mtime +"$CLEANUP_DAYS" -delete
    find "$dir" -mindepth 1 -type d -empty -mtime +"$CLEANUP_DAYS" -delete
    ok "removed $removed of $before files, freed $(hb "$freed")"
    write_state cleanup "{\"time\":\"$(date -Is)\",\"dir\":\"$(jesc "$dir")\",\"days\":$CLEANUP_DAYS,\"before\":$before,\"removed\":$removed,\"freed\":$freed,\"cmd\":\"$(jesc "$cmd")\"}"
  else
    printf '  (plan) %s\n  would remove %s of %s files, freeing %s\n' "$cmd" "$removed" "$before" "$(hb "$freed")"
  fi
}
main "$@"
