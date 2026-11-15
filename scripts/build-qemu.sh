#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${QEMU_REBUILD_BUILDER:-0} == 1 ]] || ! docker image inspect qemu-jetson-build:jammy >/dev/null 2>&1; then
    docker build -f "$repo/configs/build/qemu.Dockerfile" -t qemu-jetson-build:jammy "$repo/configs/build"
fi
docker run --rm -v "$repo:/src" -w /src qemu-jetson-build:jammy sh -ec '
    mkdir -p work/qemu-container-build
    cd work/qemu-container-build
    ../../qemu/configure --target-list=aarch64-softmmu --without-default-features --disable-werror --disable-docs
    ninja -j2 qemu-system-aarch64
    ./qemu-system-aarch64 --version
    cd /src
    python3 scripts/check-qemu-baseline.py work/qemu-container-build/qemu-system-aarch64
'
