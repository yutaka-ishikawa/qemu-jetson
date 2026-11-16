#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
cd "$repo"
: "${CROSS_COMPILE:?Set the NVIDIA AArch64 toolchain prefix}"
if [[ -n ${OPTEE_CLIENT_EXPORT:-} ]]; then
    python3 "$repo/scripts/install-artifacts.py" client --client-export "$OPTEE_CLIENT_EXPORT"
fi
[[ -f "$install_dir/include/tee_client_api.h" ]] || { echo 'Run scripts/build-optee-client.sh first' >&2; exit 1; }
devkit="$install_dir/lib/optee/ta-dev-kit-aarch64"
make -C tests/ftpm-helper-probe/ta CROSS_COMPILE="$CROSS_COMPILE" \
    TA_DEV_KIT_DIR="$devkit" TA_SIGN_KEY="${TA_SIGN_KEY:-$repo/optee/optee/optee_os/keys/default_ta.pem}" O="$repo/work/helper-probe/ta"
"${CROSS_COMPILE}gcc" -Wall -Wextra -Werror tests/ftpm-helper-probe/host/probe.c \
    -I"$install_dir/include" \
    -L"$install_dir/lib/aarch64-linux-gnu" -lteec -o work/helper-probe/ftpm-helper-probe

python3 "$repo/scripts/install-artifacts.py" probe
