#!/usr/bin/env bash
# Compile NVIDIA's client and management application; install into local prefix.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
cd "$repo"
: "${CROSS_COMPILE:?Set the NVIDIA AArch64 toolchain prefix}"
require_commands make python3 pkg-config "${CROSS_COMPILE}gcc"
out="$repo/work/optee-client"
client="$repo/optee/optee/optee_client"
make -C "$client" CROSS_COMPILE="$CROSS_COMPILE" \
    CC="${CROSS_COMPILE}gcc" AR="${CROSS_COMPILE}ar" \
    PKG_CONFIG="PKG_CONFIG_SYSROOT_DIR=$client PKG_CONFIG_PATH=$client/prebuilt pkg-config" \
    O="$out" DESTDIR="$out/export" -j "${JOBS:-2}"
make -C optee/optee/samples/ftpm-helper/host --no-builtin-variables \
    CC="${CROSS_COMPILE}gcc" STRIP="${CROSS_COMPILE}strip" \
    CROSS_COMPILE="$CROSS_COMPILE" OPTEE_CLIENT_EXPORT="$out/export/usr" \
    O="$out/helper" -j "${JOBS:-2}"
python3 "$repo/scripts/install-artifacts.py" client --client-export "$out/export/usr"
