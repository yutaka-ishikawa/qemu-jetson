#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cache="$repo/work/downloads/nvidia-r36.5.2"
mkdir -p "$cache"
if [[ ! -f "$cache/nvidia-jetson-optee-source.tbz2" || ! -f "$cache/kernel_src.tbz2" ]]; then
    archive="$cache/public_sources.tbz2"
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --retry 2 \
            https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.2/sources/public_sources.tbz2 \
            -o "$archive.part"
        mv "$archive.part" "$archive"
    fi
    printf '%s  %s\n' 4347a718e828edebee0d776d2110870d02a1d5766665d06c0abd3f325b1801d5 "$archive" | sha256sum --check -
    tar -xjf "$archive" -C "$cache" --strip-components=2 \
        Linux_for_Tegra/source/nvidia-jetson-optee-source.tbz2 \
        Linux_for_Tegra/source/kernel_src.tbz2
fi
python3 "$repo/scripts/restore-nvidia-components.py" \
    "$cache/nvidia-jetson-optee-source.tbz2" "$cache/kernel_src.tbz2"
