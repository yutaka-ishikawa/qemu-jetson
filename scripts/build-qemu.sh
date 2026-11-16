#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
require_commands cc make python3 ninja pkg-config
if ! pkg-config --exists 'glib-2.0 >= 2.66' pixman-1 zlib; then
    echo 'QEMU development libraries are missing. See docs/native-host.md.' >&2
    exit 1
fi
mkdir -p "$qemu_build_dir"
cd "$qemu_build_dir"
"$repo/qemu/configure" --target-list=aarch64-softmmu --without-default-features \
    --disable-werror --disable-docs
ninja -j "${JOBS:-2}" qemu-system-aarch64
./qemu-system-aarch64 --version
python3 "$repo/scripts/check-qemu-baseline.py" "$qemu_build_dir/qemu-system-aarch64"
