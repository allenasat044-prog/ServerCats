#!/usr/bin/env bash
# Routine cleanup: delete files older than CLEANUP_DAYS in the lab temp folder.
. "$(dirname "$0")/../lib/common.sh"

old_sizes() { # dir days: size in bytes of every file older than that
  if [ "$IS_DARWIN" = 1 ]; then find "$1" -type f -mtime +"$2" -exec stat -f %z {} + 2>/dev/null
  else find "$1" -type f -mtime +"$2" -printf '%s\n'; fi
}

main() {
  need_root_if_apply_any
  trap 'give_to_invoker "$LAB_BASE"' EXIT
  step "Cleanup of $LAB_BASE/tmp (files older than $CLEANUP_DAYS days)"
  local dir="$LAB_BASE/tmp"
  if [ ! -d "$dir" ]; then
    if [ "$IS_DARWIN" = 1 ] && [ "$LAB_APPLY" = 1 ]; then mkdir -p "$dir" && chmod 1777 "$dir" && ok "created $dir"
    elif [ "$IS_DARWIN" = 1 ]; then skip "$dir does not exist yet (it is created when you run: sudo ./server/labctl cleanup --apply)"; return
    else skip "$dir does not exist yet (run: labctl storage shared --apply)"; return; fi
  fi
  local before removed freed
  before=$(find "$dir" -type f | wc -l | tr -d " ")
  read -r removed freed < <(old_sizes "$dir" "$CLEANUP_DAYS" | awk '{n++; s+=$1} END{print n+0, s+0}')
  local cmd="find $dir -type f -mtime +$CLEANUP_DAYS -delete"
  if [ "$LAB_APPLY" = 1 ]; then
    find "$dir" -type f -mtime +"$CLEANUP_DAYS" -delete
    find "$dir" -mindepth 1 -type d -empty -mtime +"$CLEANUP_DAYS" -delete
    ok "removed $removed of $before files, freed $(hb "$freed")"
    write_state cleanup "{\"time\":\"$(now_iso)\",\"dir\":\"$(jesc "$dir")\",\"days\":$CLEANUP_DAYS,\"before\":$before,\"removed\":$removed,\"freed\":$freed,\"cmd\":\"$(jesc "$cmd")\"}"
  else
    printf '  (plan) %s\n  would remove %s of %s files, freeing %s\n' "$cmd" "$removed" "$before" "$(hb "$freed")"
  fi
}
main "$@"
