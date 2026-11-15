#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dest=${1:-"$repo/work/downloads"}
mkdir -p -- "$dest"
dest=$(cd -- "$dest" && pwd)
name=ubuntu-base-22.04.5-base-arm64.tar.gz
url=https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release
if [[ ! -f "$dest/$name" ]]; then
    curl --fail --location --retry 2 "$url/$name" -o "$dest/$name.part"
    mv -- "$dest/$name.part" "$dest/$name"
fi
(cd -- "$dest" && sha256sum --check "$repo/manifests/ubuntu-base-22.04.5-arm64.sha256")
printf '%s\n' "$dest/$name"
