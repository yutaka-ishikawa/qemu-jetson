#!/usr/bin/env bash
# Build the full NVIDIA helper PTA and unchanged TAs (decisions 0001/0002).
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
: "${CROSS_COMPILE:?Set CROSS_COMPILE to the NVIDIA AArch64 compiler prefix}"
command -v "${CROSS_COMPILE}gcc" >/dev/null
command -v dtc >/dev/null
python3 -c 'import cryptography, Crypto, elftools'
out="$repo/work/ftpm-virt"
osout="$repo/work/optee-virt"
mkdir -p "$out"
python3 - "$out/device-identity.bin" <<'PY'
import os, sys
path = sys.argv[1]
try:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
except FileExistsError:
    data = open(path, 'rb').read()
    if len(data) != 72 or data[:8] != b'JFTPM001':
        raise SystemExit('Invalid existing identity; refusing to replace it')
else:
    with os.fdopen(fd, 'wb') as f:
        f.write(b'JFTPM001' + os.urandom(64))
PY
args=(PLATFORM=vexpress-qemu_armv8a CFG_ARM64_core=y CFG_USER_TA_TARGETS=ta_arm64
    CFG_TEE_CORE_NB_CORE=1 CFG_WITH_PAGER=n CFG_DT_DRIVER_EMBEDDED_TEST=n
    CFG_CORE_ASYNC_NOTIF=n CFG_PKCS11_TA=n CFG_QEMU_DEVICE_IDENTITY=y
    CFG_QEMU_JETSON_FTPM=y
    CFG_TEE_TA_LOG_LEVEL=2 CROSS_COMPILE64="$CROSS_COMPILE" O="$osout")
make -C optee/optee/optee_os "${args[@]}" -j "${JOBS:-2}"
make -C optee/optee/samples/ftpm-helper/ta CROSS_COMPILE="$CROSS_COMPILE" \
    TA_DEV_KIT_DIR="$osout/export-ta_arm64" \
    O="$osout/early_ta/ftpm-helper" -j "${JOBS:-2}"
make -C optee/optee/samples/ms-tpm-20-ref/Samples/ARM32-FirmwareTPM/optee_ta \
    CROSS_COMPILE="$CROSS_COMPILE" TA_DEV_KIT_DIR="$osout/export-ta_arm64" \
    OPTEE_OS_DIR="$repo/optee/optee/optee_os" CFG_USE_PLATFORM_EPS=y \
    CFG_TA_MEASURED_BOOT=n O="$osout" -j "${JOBS:-2}"
make -C optee/optee/optee_os "${args[@]}" CFG_EARLY_TA=y \
    EARLY_TA_PATHS="$osout/early_ta/ms-tpm/bc50d971-d4c9-42c4-82cb-343fb7f37896.stripped.elf $osout/early_ta/ftpm-helper/a6a3a74a-77cb-433a-990c-1dfb8a3fbc4c.stripped.elf" \
    -j "${JOBS:-2}"
"${CROSS_COMPILE}gcc" -nostdlib -static -no-pie -Wl,--build-id=none \
    -T firmware/linux-entry/link.ld firmware/linux-entry/entry.S -o "$out/linux-entry.elf"
"${CROSS_COMPILE}objcopy" -O binary "$out/linux-entry.elf" "$out/linux-entry.bin"
make -C firmware/tf-a PLAT=qemu ARCH=aarch64 SPD=opteed BL32_RAM_LOCATION=tdram \
    ARM_LINUX_KERNEL_AS_BL33=1 CROSS_COMPILE="$CROSS_COMPILE" \
    BL32="$osout/core/tee-header_v2.bin" BL32_EXTRA1="$osout/core/tee-pager_v2.bin" \
    BL32_EXTRA2="$osout/core/tee-pageable_v2.bin" BL33="$out/linux-entry.bin" \
    BUILD_BASE="$repo/work/tf-a" DEBUG=0 WERROR=0 -j "${JOBS:-2}" all fip
python3 - "$repo" <<'PY'
import pathlib, sys
repo = pathlib.Path(sys.argv[1])
with (repo/'work/ftpm-virt/flash.bin').open('wb') as f:
    f.truncate(64 * 1024 * 1024)
    f.write((repo/'work/tf-a/qemu/release/bl1.bin').read_bytes())
    f.seek(0x40000)
    f.write((repo/'work/tf-a/qemu/release/fip.bin').read_bytes())
PY
