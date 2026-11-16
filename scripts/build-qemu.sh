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
    --disable-werror --disable-docs --prefix="$install_dir" --bindir=bin \
    --libdir=lib --libexecdir=libexec --includedir=include --datadir=share
# Build installation targets and their dependencies, without unrelated test binaries.
python3 - "${JOBS:-2}" <<'PY_TARGETS'
import json, os, subprocess, sys
from pathlib import Path
plan=json.loads(Path('meson-info/intro-install_plan.json').read_text())
targets=[os.path.relpath(path) for path in plan.get('targets', {})]
if not targets:
    raise SystemExit('QEMU install plan has no build targets')
subprocess.run(['ninja','-j',sys.argv[1],*targets],check=True)
PY_TARGETS
"$qemu_build_dir/pyvenv/bin/meson" install --no-rebuild --strip
"$qemu_bin" --version
python3 "$repo/scripts/check-qemu-baseline.py" "$qemu_bin" --data-dir "$qemu_data_dir"
