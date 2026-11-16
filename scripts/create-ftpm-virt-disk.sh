#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
test -f work/ftpm-virt/rootfs.tar
[[ ! -e work/ftpm-virt/rootfs.ext4 ]] || { echo 'Refusing to overwrite persistent disk' >&2; exit 1; }
docker run --rm -v "$repo:/src" ubuntu:22.04 sh -ec '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >/dev/null
    apt-get install -y --no-install-recommends e2fsprogs >/dev/null
    root=$(mktemp -d /src/work/ftpm-virt/root.XXXXXX)
    trap '\''rm -rf "$root"'\'' EXIT
    tar --numeric-owner -xpf /src/work/ftpm-virt/rootfs.tar -C "$root"
    rm -f "$root/.dockerenv"
    chmod 0755 "$root" "$root/usr/lib" "$root/usr/sbin" "$root/usr/lib/optee_armtz"
    for overlay in /src/configs/rootfs/overlay /src/configs/rootfs/functional-overlay; do
        find "$overlay" -type d | while IFS= read -r dir; do
            relative=${dir#"$overlay"}
            if [ -d "$root$relative" ]; then chmod 0755 "$root$relative"; fi
        done
    done
    truncate -s 768M /src/work/ftpm-virt/rootfs.ext4.part
    mkfs.ext4 -q -F -d "$root" /src/work/ftpm-virt/rootfs.ext4.part
    mv /src/work/ftpm-virt/rootfs.ext4.part /src/work/ftpm-virt/rootfs.ext4
'
