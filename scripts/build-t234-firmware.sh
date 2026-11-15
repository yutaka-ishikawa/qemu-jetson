#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
: "${CROSS_COMPILE_AARCH64:?Set CROSS_COMPILE_AARCH64 to the NVIDIA AArch64 compiler prefix}"
out="$repo/work/t234-firmware"
mkdir -p "$out"
for variant in boot selftest isolation; do
    flags=()
    if [[ $variant == selftest ]]; then flags+=(-DBOOT_SELF_TEST); fi
    if [[ $variant == isolation ]]; then flags+=(-DBOOT_NS_TEST); fi
    "${CROSS_COMPILE_AARCH64}gcc" -nostdlib -nostartfiles -ffreestanding -static -no-pie \
        -Wl,--build-id=none -Wl,-T,"$repo/firmware/t234-boot/link.ld" \
        "${flags[@]}" "$repo/firmware/t234-boot/boot.S" -o "$out/$variant.elf"
    "${CROSS_COMPILE_AARCH64}objcopy" -O binary "$out/$variant.elf" "$out/$variant.bin"
done
"${DTC:-dtc}" -I dts -O dtb -p 4096 "$repo/configs/t234-boot.dts" -o "$out/optee.dtb"
sha256sum "$out"/*.bin "$out/optee.dtb"
