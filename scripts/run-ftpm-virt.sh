#!/usr/bin/env bash
# Launch an already-built option-B image. Identity and disk are persistent.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
phase=${1:-first}
[[ $phase == first || $phase == second ]] || exit 2
out=work/ftpm-virt
for file in flash.bin Image device-identity.bin provisioning.bin rootfs.ext4 "runtime-$phase.dtb"; do
    test -f "$out/$file" || { echo "Missing: $out/$file" >&2; exit 1; }
done
docker run --rm -v "$repo:/src" -w /src qemu-jetson-build:jammy \
    timeout "${FTPM_TIMEOUT:-300}" work/qemu-container-build/qemu-system-aarch64 \
    -machine jetson-ftpm-virt,secure=on,gic-version=2,identity-file="$out/device-identity.bin",provisioning-file="$out/provisioning.bin" \
    -cpu cortex-a57 -smp 1 -m 1024M -display none -monitor none -nic none \
    -serial stdio -serial "file:$out/secure-$phase.log" \
    -bios "$out/flash.bin" -dtb "$out/runtime-$phase.dtb" \
    -device loader,file="$out/Image",addr=0x60200000,force-raw=on \
    -drive if=none,id=root,file="$out/rootfs.ext4",format=raw \
    -device virtio-blk-device,drive=root \
    -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-device,rng=rng0
