#!/usr/bin/env bash
# Explicit host package installation; never called automatically by a build.
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo "Run: sudo bash scripts/install-host-deps.sh" >&2; exit 1; }
source /etc/os-release
case "${ID:-} ${ID_LIKE:-}" in *ubuntu*|*debian*) ;; *) echo 'See docs/native-host.md for required packages' >&2; exit 1;; esac
apt-get update
apt-get install -y --no-install-recommends \
    build-essential python3-venv python3-pip python3-tomli ninja-build pkg-config \
    libglib2.0-dev libpixman-1-dev zlib1g-dev libfdt-dev device-tree-compiler \
    proot qemu-user e2fsprogs kmod fakeroot git curl ca-certificates xz-utils bzip2
