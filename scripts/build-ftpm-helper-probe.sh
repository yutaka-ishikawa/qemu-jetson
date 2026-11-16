#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
: "${CROSS_COMPILE:?Set the NVIDIA AArch64 toolchain prefix}"
: "${OPTEE_CLIENT_EXPORT:?Set the NVIDIA client install usr directory}"
osout="$repo/work/optee-virt"
make -C tests/ftpm-helper-probe/ta CROSS_COMPILE="$CROSS_COMPILE" \
    TA_DEV_KIT_DIR="$osout/export-ta_arm64" O="$repo/work/helper-probe/ta"
"${CROSS_COMPILE}gcc" -Wall -Wextra -Werror tests/ftpm-helper-probe/host/probe.c \
    -Ioptee/optee/optee_client/libteec/include -Ioptee/optee/optee_os/lib/libutee/include \
    -L"$OPTEE_CLIENT_EXPORT/lib" -lteec -o work/helper-probe/ftpm-helper-probe
