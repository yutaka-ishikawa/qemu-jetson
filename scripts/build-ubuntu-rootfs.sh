#!/usr/bin/env bash
# Assemble ARM64 Ubuntu directly on the host; no daemon or binfmt registration.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
case $# in
    0) client_source="$install_dir"; output_arg="$repo/work/ftpm-virt/rootfs.tar";;
    1) client_source="$install_dir"; output_arg="$1";;
    2) client_source="$1"; output_arg="$2";;
    *) echo "Usage: $0 [CLIENT_INSTALL_DIR] [OUTPUT_TAR]" >&2; exit 2;;
esac
[[ $EUID == 0 ]] || { echo 'Rootfs assembly preserves guest ownership: run with sudo. See docs/native-host.md.' >&2; exit 1; }
require_commands proot tar readelf depmod curl sha256sum
optee_install=$(cd -- "$client_source" && pwd)
if [[ -d "$optee_install/libexec/aarch64-linux-gnu" ]]; then
    client_bin="$optee_install/libexec/aarch64-linux-gnu"
    client_lib="$optee_install/lib/aarch64-linux-gnu"
else
    [[ ! -d "$optee_install/usr" ]] || optee_install="$optee_install/usr"
    client_bin="$optee_install/sbin"
    client_lib="$optee_install/lib"
fi
mkdir -p -- "$(dirname -- "$output_arg")"
output=$(cd -- "$(dirname -- "$output_arg")" && pwd)/$(basename -- "$output_arg")
[[ ! -e "$output" && ! -e "$output.part" ]] || { echo "Output already exists: $output" >&2; exit 1; }
qemu_args=()
if [[ $(uname -m) != aarch64 ]]; then
    qemu_user=$(command -v qemu-aarch64-static || command -v qemu-aarch64 || true)
    [[ -n $qemu_user ]] || { echo 'Install qemu-user; see docs/native-host.md' >&2; exit 1; }
    qemu_args=(-q "$qemu_user")
fi
for name in tee-supplicant nvftpm-helper-app; do
    readelf -h "$client_bin/$name" | grep -q 'Machine:.*AArch64'
done
"$repo/scripts/fetch-ubuntu-base.sh"
# A public parent is needed when guest apt drops privileges to _apt.
context=$(mktemp -d /tmp/qemu-jetson-rootfs.XXXXXX)
chmod 0755 "$context"
root="$context/root"
mkdir -m 0755 "$root"
trap 'rm -rf -- "$context"; rm -f -- "$output.part"' EXIT
tar --numeric-owner -xpf "$repo/work/downloads/ubuntu-base-22.04.5-base-arm64.tar.gz" -C "$root"
overlay="$context/overlay"
cp -a --no-preserve=ownership "$repo/configs/rootfs/overlay" "$overlay"
if [[ ${FTPM_FUNCTIONAL_PROFILE:-0} == 1 ]]; then
    cp -a --no-preserve=ownership "$repo/configs/rootfs/functional-overlay/." "$overlay/"
fi
find "$overlay" -type d -exec chmod 0755 {} +
cp -a --no-preserve=ownership "$overlay/." "$root/"
install -d -m 0755 "$root/usr/local/sbin" "$root/usr/sbin" "$root/usr/lib/optee_armtz"
install -m 0755 "$repo/scripts/check-ftpm-guest.sh" "$root/usr/local/sbin/"
for name in tee-supplicant nvftpm-helper-app; do
    install -m 0755 "$client_bin/$name" "$root/usr/sbin/"
done
shopt -s nullglob
libs=("$client_lib"/libteec.so*)
((${#libs[@]})) || { echo 'libteec.so missing' >&2; exit 1; }
cp -a --no-preserve=ownership "${libs[@]}" "$root/usr/lib/"
chmod 0644 "$root"/usr/lib/libteec.so*
module_source=${KERNEL_MODULES_DIR:+$KERNEL_MODULES_DIR/lib/modules}
if [[ -z $module_source && -d "$install_dir/lib/modules" ]]; then module_source="$install_dir/lib/modules"; fi
if [[ -n $module_source ]]; then
    cp -a --no-preserve=ownership "$module_source" "$root/usr/lib/"
    find "$root/usr/lib/modules" -type d -exec chmod 0755 {} +
    find "$root/usr/lib/modules" -type f -exec chmod 0644 {} +
fi
cp /etc/resolv.conf "$root/etc/resolv.conf"
install -m 0755 "$repo/configs/rootfs/setup-guest.sh" "$root/usr/local/sbin/qemu-jetson-setup"
if [[ -e "$root/usr/sbin/policy-rc.d" ]]; then
    cp -a "$root/usr/sbin/policy-rc.d" "$context/policy-rc.d"
fi
printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
chmod 0755 "$root/usr/sbin/policy-rc.d"
# Explicit binds: host account databases and home directories never enter guest setup.
proot "${qemu_args[@]}" -r "$root" -w / -b /dev -b /proc -b /sys -b /tmp \
    /usr/local/sbin/qemu-jetson-setup
rm -f "$root/usr/local/sbin/qemu-jetson-setup" "$root/usr/sbin/policy-rc.d"
if [[ -e "$context/policy-rc.d" ]]; then cp -a "$context/policy-rc.d" "$root/usr/sbin/policy-rc.d"; fi
if [[ -d "$root/lib/modules" ]]; then
    for dir in "$root"/lib/modules/*; do depmod -b "$root" -a "${dir##*/}"; done
fi
printf 'nameserver 10.0.2.3\n' > "$root/etc/resolv.conf"
tar --numeric-owner -cpf "$output.part" -C "$root" .
mv -- "$output.part" "$output"
sha256sum "$output" > "$output.sha256"
if [[ -n ${SUDO_UID:-} && -n ${SUDO_GID:-} ]]; then
    chown "$SUDO_UID:$SUDO_GID" "$output" "$output.sha256"
fi
printf 'Created %s\n' "$output"
