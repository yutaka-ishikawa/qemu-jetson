#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
docker build -f "$repo/configs/build/qemu.Dockerfile" -t qemu-jetson-build:jammy "$repo/configs/build"
docker run --rm -v "$repo:/src" -w /src qemu-jetson-build:jammy sh -ec '
    mkdir -p work/qemu-container-build
    cd work/qemu-container-build
    ../../qemu/configure --target-list=aarch64-softmmu --without-default-features --disable-werror --disable-docs
    ninja -j2 qemu-system-aarch64
    ./qemu-system-aarch64 --version
'
