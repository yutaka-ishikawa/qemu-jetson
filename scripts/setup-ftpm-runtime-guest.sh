#!/usr/bin/env bash
# Run INSIDE the existing guest, normally through a read-only 9p repository share.
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run inside the guest as root (or sudo).' >&2; exit 1; }
[[ $(uname -m) == aarch64 && -c /dev/tee0 ]] || { echo 'This script is for the running QEMU ARM64 OP-TEE guest.' >&2; exit 1; }
grep -aq 'linux,dummy-virt' /proc/device-tree/compatible || { echo 'Expected the QEMU virt guest.' >&2; exit 1; }
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
overlay="$repo/configs/rootfs/runtime-overlay"
# Enable DHCP first so packages can be installed on an existing offline rootfs.
cp -a --no-preserve=ownership "$overlay/." /
chmod 0755 /
find "$overlay" -mindepth 1 -type d -print0 | while IFS= read -r -d '' path; do chmod 0755 "/${path#"$overlay/"}"; done
# Runtime configuration files are public, unlike account/key files.
find "$overlay" -type f -print0 | while IFS= read -r -d '' path; do
    target="/${path#"$overlay/"}"
    if [[ $target == /usr/local/sbin/* ]]; then chmod 0755 "$target"; else chmod 0644 "$target"; fi
done
systemctl daemon-reload
systemctl enable --now systemd-networkd.service
for ((i=0; i<60; i++)); do ip -4 route show default | grep -q . && break; sleep 1; done
ip -4 route show default | grep -q . || { echo 'No DHCP route. Launch setup with --ssh.' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Languages=none -o APT::Update::Error-Mode=any update
apt-get install -y --no-install-recommends openssh-server sudo dbus
systemctl enable ssh.service qemu-guest-setup.service
sshd -t -f /etc/ssh/sshd_config_qemu
systemctl restart ssh.service
echo 'Runtime installed. Create a regular user with adduser, add it to sudo, and register its public key.'
echo 'No account password, authorized key, TPM state or CA was replaced.'
