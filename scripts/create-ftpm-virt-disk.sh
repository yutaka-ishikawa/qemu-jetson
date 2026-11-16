#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
cd "$repo"
[[ $EUID == 0 ]] || { echo 'Run with sudo to preserve guest file ownership. See docs/native-host.md.' >&2; exit 1; }
require_commands python3 tar mke2fs truncate
out=${FTPM_IMAGE_DIR:-work/ftpm-virt}
python3 "$repo/scripts/rootfs_validation.py" "$out/rootfs.tar"
[[ ! -e "$out/rootfs.ext4" && ! -e "$out/rootfs.ext4.part" ]] || { echo 'Refusing to overwrite persistent disk' >&2; exit 1; }
root=$(mktemp -d "$repo/work/ftpm-disk.XXXXXX")
trap 'rm -rf -- "$root"; rm -f -- "$out/rootfs.ext4.part"' EXIT
tar --numeric-owner -xpf "$out/rootfs.tar" -C "$root"
rm -f "$root/.dockerenv"
chmod 0755 "$root" "$root/usr/lib" "$root/usr/sbin" "$root/usr/lib/optee_armtz"
for overlay in "$repo/configs/rootfs/overlay" "$repo/configs/rootfs/functional-overlay"; do
    while IFS= read -r dir; do
        relative=${dir#"$overlay"}
        [[ ! -d "$root$relative" ]] || chmod 0755 "$root$relative"
    done < <(find "$overlay" -type d)
done
truncate -s 768M "$out/rootfs.ext4.part"
mke2fs -t ext4 -q -F -E lazy_itable_init=0,lazy_journal_init=0 -d "$root" "$out/rootfs.ext4.part"
mv -- "$out/rootfs.ext4.part" "$out/rootfs.ext4"
if [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]]; then chown "$SUDO_UID:$SUDO_GID" "$out/rootfs.ext4"; fi
chmod 0600 "$out/rootfs.ext4"
