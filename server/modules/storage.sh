#!/usr/bin/env bash
# Storage management: grow the root LVM volume, partition + LVM + mount a new disk, shared directories.
. "$(dirname "$0")/../lib/common.sh"

step_root() {
  step "Root volume (LVM)"
  local src vg size free
  src=$(findmnt -no SOURCE /)
  if ! command -v lvs >/dev/null 2>&1; then skip "LVM tools are not installed (run: labctl system packages --apply)"; return; fi
  vg=$(lvs --noheadings -o vg_name "$src" 2>/dev/null | tr -d ' ')
  if [ -z "$vg" ]; then skip "/ ($src) is not on an LVM volume"; return; fi
  size=$(vgs --noheadings --units b --nosuffix -o vg_size "$vg" | tr -d ' ')
  free=$(vgs --noheadings --units b --nosuffix -o vg_free "$vg" | tr -d ' ')
  say "  volume group $vg: $(hb "$size") in total, $(hb "$free") not allocated to any volume"
  if [ "${free:-0}" -lt 1073741824 ]; then ok "no unallocated space: / already uses the whole volume group"; return; fi
  if [ "$EXTEND_ROOT" != yes ]; then skip "EXTEND_ROOT=no. Set it to yes in lab.conf to grow / by $(hb "$free")"; return; fi
  run lvextend -r -l +100%FREE "$src"
}

step_disk() {
  step "Data disk: partition, LVM, filesystem, mount"
  if [ -z "$DATA_DISK" ]; then skip "DATA_DISK is empty in lab.conf"; return; fi
  [ -b "$DATA_DISK" ] || die "$DATA_DISK is not a block device"
  local dev="/dev/$LVM_VG/$LVM_LV" part flag
  if lvs "$LVM_VG/$LVM_LV" >/dev/null 2>&1; then
    ok "logical volume $dev already exists"
  else
    if lsblk -nro MOUNTPOINTS "$DATA_DISK" | grep -q . ; then die "$DATA_DISK (or a partition on it) is mounted: refusing to touch it"; fi
    if lsblk -nro TYPE "$DATA_DISK" | grep -qx part && [ "$LAB_FORCE" != 1 ]; then
      die "$DATA_DISK already has partitions. Refusing to wipe it (use --force if you are sure)"
    fi
    if [[ $LVM_SIZE == *%* ]]; then flag=-l; else flag=-L; fi
    if [ "$LAB_APPLY" = 1 ]; then
      parted -s "$DATA_DISK" mklabel gpt mkpart lablvm 1MiB 100% set 1 lvm on || die "partitioning failed"
      partprobe "$DATA_DISK"; udevadm settle
      part=$(lsblk -nrpo NAME,TYPE "$DATA_DISK" | awk '$2=="part"{print $1; exit}')
      [ -b "$part" ] || die "new partition not found on $DATA_DISK"
      pvcreate -y "$part" || die "pvcreate failed"
      if vgs "$LVM_VG" >/dev/null 2>&1; then vgextend "$LVM_VG" "$part"; else vgcreate "$LVM_VG" "$part"; fi || die "volume group failed"
      lvcreate "$flag" "$LVM_SIZE" -n "$LVM_LV" "$LVM_VG" || die "lvcreate failed"
      ok "created partition $part, volume group $LVM_VG and logical volume $dev"
    else
      printf '  (plan) parted: GPT label and one LVM partition on %s\n  (plan) pvcreate, vgcreate %s, lvcreate %s %s -n %s\n' "$DATA_DISK" "$LVM_VG" "$flag" "$LVM_SIZE" "$LVM_LV"
    fi
  fi
  if [ "$LAB_APPLY" != 1 ] && [ ! -b "$dev" ]; then
    printf '  (plan) mkfs.%s, mount at %s, add an /etc/fstab entry\n' "$LVM_FS" "$LVM_MOUNT"; return
  fi
  if ! blkid "$dev" >/dev/null 2>&1; then run "mkfs.$LVM_FS" -L "$LVM_LV" "$dev"; else ok "$dev already has a filesystem"; fi
  if findmnt -rn "$LVM_MOUNT" >/dev/null 2>&1; then ok "$LVM_MOUNT is already mounted"; return; fi
  if [ -d "$LVM_MOUNT" ] && [ -n "$(ls -A "$LVM_MOUNT" 2>/dev/null)" ]; then
    die "$LVM_MOUNT is not empty: mounting would hide its files. Move them first."
  fi
  run mkdir -p "$LVM_MOUNT"
  if [ "$LAB_APPLY" = 1 ]; then
    grep -qs " $LVM_MOUNT " /etc/fstab || printf 'UUID=%s %s %s defaults,nofail 0 2\n' "$(blkid -s UUID -o value "$dev")" "$LVM_MOUNT" "$LVM_FS" >> /etc/fstab
    mount "$LVM_MOUNT" || die "mount failed"; ok "mounted $dev on $LVM_MOUNT and added it to /etc/fstab"
  else
    printf '  (plan) add %s to /etc/fstab and mount it\n' "$LVM_MOUNT"
  fi
}

step_shared() {
  step "Shared directories"
  local d g p
  run mkdir -p "$LAB_BASE/shared" "$LAB_BASE/tmp" "$LAB_BASE/backups"
  run chmod 755 "$LAB_BASE" "$LAB_BASE/shared"
  run chmod 1777 "$LAB_BASE/tmp"
  run chmod 700 "$LAB_BASE/backups"
  for d in $DEPARTMENTS; do
    g="lab-$d"; p="$LAB_BASE/shared/$d"
    ensure_group "$g"
    run mkdir -p "$p"
    run chown "root:$g" "$p"
    run chmod 2770 "$p"
    if command -v setfacl >/dev/null 2>&1; then
      # setgid keeps the group on new files; the default ACL keeps them group-writable whatever the user's umask is
      run setfacl -m "g:$g:rwx" "$p"
      run setfacl -d -m "g:$g:rwx,o::---" "$p"
    else
      warn "setfacl missing (install the 'acl' package): new files may not be group-writable"
    fi
  done
}

main() {
  need_root_if_apply
  local steps=("$@"); [ ${#steps[@]} -eq 0 ] && steps=(root disk shared)
  local s
  for s in "${steps[@]}"; do
    case $s in root|disk|shared) "step_$s" ;; *) die "unknown step '$s' (root|disk|shared)" ;; esac
  done
}
main "$@"
