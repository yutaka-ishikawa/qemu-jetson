#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# != 2 ]]; then
    echo "Usage: $0 OPTEE_INSTALL_DIR OUTPUT_TAR" >&2
    exit 2
fi
optee_install=$(cd -- "$1" && pwd)
out_dir=$(dirname -- "$2")
mkdir -p -- "$out_dir"
out_dir=$(cd -- "$out_dir" && pwd)
output="$out_dir/$(basename -- "$2")"
[[ ! -e "$output" ]] || { echo "Output already exists: $output" >&2; exit 1; }
for name in tee-supplicant nvftpm-helper-app; do
    test -f "$optee_install/usr/sbin/$name"
    readelf -h "$optee_install/usr/sbin/$name" | grep -q 'Machine:.*AArch64'
done
command -v docker >/dev/null
command -v readelf >/dev/null
"$repo/scripts/fetch-ubuntu-base.sh"
context=$(mktemp -d "$repo/work/rootfs-context.XXXXXX")
container_id=
cleanup() {
    if [[ -n "$container_id" ]]; then docker rm "$container_id" >/dev/null; fi
    rm -rf -- "$context"
}
trap cleanup EXIT
cp "$repo/work/downloads/ubuntu-base-22.04.5-base-arm64.tar.gz" "$context/"
cp "$repo/configs/rootfs/Dockerfile" "$context/"
cp -a "$repo/configs/rootfs/overlay" "$context/overlay"
if [[ ${FTPM_FUNCTIONAL_PROFILE:-0} == 1 ]]; then
    cp -a "$repo/configs/rootfs/functional-overlay/." "$context/overlay/"
fi
mkdir -p "$context/optee/usr/local/sbin"
cp "$repo/scripts/check-ftpm-guest.sh" "$context/optee/usr/local/sbin/"
mkdir -p "$context/optee/usr/sbin" "$context/optee/usr/lib" "$context/optee/usr/lib/optee_armtz"
for name in tee-supplicant nvftpm-helper-app; do
    cp -a "$optee_install/usr/sbin/$name" "$context/optee/usr/sbin/"
done
shopt -s nullglob
libs=("$optee_install"/usr/lib/libteec.so*)
((${#libs[@]} > 0)) || { echo 'libteec.so is missing' >&2; exit 1; }
cp -a "${libs[@]}" "$context/optee/usr/lib/"
if [[ -n ${KERNEL_MODULES_DIR:-} ]]; then
    cp -a "$KERNEL_MODULES_DIR/lib/modules" "$context/optee/usr/lib/"
fi
# fTPM and its helper are embedded Early TAs; no external fTPM TA is required.
docker build --platform linux/arm64 --tag qemu-jetson-rootfs:jammy "$context"
container_id=$(docker create --platform linux/arm64 qemu-jetson-rootfs:jammy)
docker export "$container_id" -o "$output.part"
mv -- "$output.part" "$output"
sha256sum "$output" > "$output.sha256"
printf 'Created %s\n' "$output"
