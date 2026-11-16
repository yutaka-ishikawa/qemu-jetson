#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
: "${CROSS_COMPILE_AARCH64:?Set CROSS_COMPILE_AARCH64 to the NVIDIA AArch64 compiler prefix}"
out="$repo/work/t234-firmware"
mkdir -p "$out"
variants=(boot selftest isolation fuse-write fuse-bad-read fuse-isolation)
if [[ -n ${OPTEE_ELF:-} ]]; then
    ecid_addr=$("${CROSS_COMPILE_AARCH64}nm" --defined-only "$OPTEE_ELF" | awk '$3 == "fuse_generate_ecid" { print "0x" $1 }')
    sn_addr=$("${CROSS_COMPILE_AARCH64}nm" --defined-only "$OPTEE_ELF" | awk '$3 == "fuse_generate_sn" { print "0x" $1 }')
    [[ -n $ecid_addr && -n $sn_addr ]] || { echo 'Fuse symbols missing in OPTEE_ELF' >&2; exit 1; }
    variants+=(fuse-probe fuse-reset)
fi
for variant in "${variants[@]}"; do
    flags=()
    if [[ $variant == selftest ]]; then flags+=(-DBOOT_SELF_TEST); fi
    if [[ $variant == isolation ]]; then flags+=(-DBOOT_NS_TEST); fi
    if [[ $variant == fuse-isolation ]]; then flags+=(-DBOOT_NS_TEST -DNS_PROBE_ADDR=0x03810200); fi
    if [[ $variant == fuse-write ]]; then flags+=(-DBOOT_FUSE_WRITE_TEST); fi
    if [[ $variant == fuse-bad-read ]]; then flags+=(-DBOOT_FUSE_BAD_READ_TEST); fi
    if [[ $variant == fuse-probe || $variant == fuse-reset ]]; then
        flags+=(-DBOOT_FUSE_PROBE "-DFUSE_GENERATE_ECID_ADDR=$ecid_addr" "-DFUSE_GENERATE_SN_ADDR=$sn_addr")
    fi
    if [[ $variant == fuse-reset ]]; then flags+=(-DBOOT_FUSE_WAIT_RESET); fi
    "${CROSS_COMPILE_AARCH64}gcc" -nostdlib -nostartfiles -ffreestanding -static -no-pie \
        -Wl,--build-id=none -Wl,-T,"$repo/firmware/t234-boot/link.ld" \
        "${flags[@]}" "$repo/firmware/t234-boot/boot.S" -o "$out/$variant.elf"
    "${CROSS_COMPILE_AARCH64}objcopy" -O binary "$out/$variant.elf" "$out/$variant.bin"
done
"${DTC:-dtc}" -I dts -O dtb -p 4096 "$repo/configs/t234-boot.dts" -o "$out/optee.dtb"
sha256sum "$out"/*.bin "$out/optee.dtb"

python3 "$repo/scripts/install-artifacts.py" t234
