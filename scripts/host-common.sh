#!/usr/bin/env bash
# Shared native-host paths. Source from project scripts.
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$PATH:/usr/sbin:/sbin"
qemu_build_dir=${QEMU_BUILD_DIR:-$repo/work/qemu-build}
[[ $qemu_build_dir == /* ]] || qemu_build_dir="$repo/$qemu_build_dir"
if [[ -d "$repo/work/native-libs" ]]; then
    export LD_LIBRARY_PATH="$repo/work/native-libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
require_commands() {
    local missing=() name
    for name in "$@"; do command -v "$name" >/dev/null || missing+=("$name"); done
    if ((${#missing[@]})); then
        printf 'Missing host tools: %s\n' "${missing[*]}" >&2
        echo 'See docs/native-host.md; on Ubuntu/Debian: sudo bash scripts/install-host-deps.sh' >&2
        return 1
    fi
}
