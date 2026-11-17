#!/usr/bin/env bash
# Native QEMU launcher. Normal boot is interactive; test phases remain explicit.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
cd "$repo"
usage() {
    cat <<'HELP'
Usage: bash scripts/run-ftpm-virt.sh [normal|setup|first|second|export|bound] [OPTIONS]
  --setup              Initial setup console (root shell; not SSH)
  --cpus N             1..8 CPUs (default: 4; rebuild firmware before use)
  --ssh                User networking and SSH forwarding, 127.0.0.1:2222
  --ssh-port PORT      Enable SSH forwarding on another localhost TCP port
  --share DIRECTORY    Export one host directory as 9p tag hostshare (read-only)
  --share-rw           Make that export writable (guest mount also needs --rw)
  --qemu-console       Multiplex QEMU monitor and guest serial on stdio (Ctrl-a c)
  --monitor-socket PATH  QEMU monitor UNIX socket for a separate terminal
  --gdb                Guest GDB server on 127.0.0.1:1234
  --gdb-port PORT      Guest GDB server on another localhost TCP port
  --wait-gdb           Enable GDB and halt CPUs before firmware starts
  --timeout SECONDS    0 = unlimited; default normal/setup: 0, tests: FTPM_TIMEOUT/300
  -h, --help           Show help; see docs/runtime-guide.md and run-ftpm-virt(1)
SSH requires a guest user and registered public key. Root SSH/password auth are disabled.
HELP
}
phase=normal
cpus=4
ssh_enabled=0
ssh_port=2222
share_dir=
share_rw=0
timeout_arg=
phase_set=0
qemu_console=0
monitor_socket=
gdb_enabled=0
gdb_port=1234
wait_gdb=0
while (($#)); do
    case $1 in
        -h|--help) usage; exit 0;;
        --setup) ((phase_set == 0)) || { echo "Specify one boot mode" >&2; exit 2; }; phase=setup; phase_set=1; shift;;
        normal|setup|first|second|export|bound)
            ((phase_set == 0)) || { echo 'Specify one boot mode' >&2; exit 2; }
            phase=$1; phase_set=1; shift;;
        --cpus|--ssh-port|--share|--timeout|--monitor-socket|--gdb-port)
            (($# >= 2)) || { echo "Missing value: $1" >&2; exit 2; }
            case $1 in
                --cpus) cpus=$2;;
                --ssh-port) ssh_port=$2; ssh_enabled=1;;
                --share) share_dir=$2;;
                --timeout) timeout_arg=$2;;
                --monitor-socket) monitor_socket=$2;;
                --gdb-port) gdb_port=$2; gdb_enabled=1;;
            esac
            shift 2;;
        --qemu-console) qemu_console=1; shift;;
        --gdb) gdb_enabled=1; shift;;
        --wait-gdb) gdb_enabled=1; wait_gdb=1; shift;;
        --ssh) ssh_enabled=1; shift;;
        --share-rw) share_rw=1; shift;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2;;
    esac
done
[[ $cpus =~ ^[1-8]$ ]] || { echo 'CPU count must be 1..8' >&2; exit 2; }
[[ $ssh_port =~ ^[0-9]{1,5}$ ]] && ((10#$ssh_port >= 1 && 10#$ssh_port <= 65535)) || { echo 'Invalid SSH port' >&2; exit 2; }
if ((ssh_enabled)) && [[ $phase != normal && $phase != setup ]]; then
    echo 'SSH is supported in normal/setup modes' >&2; exit 2
fi
((share_rw == 0)) || [[ -n $share_dir ]] || { echo '--share-rw needs --share' >&2; exit 2; }
if [[ -n $share_dir ]]; then
    [[ -d $share_dir ]] || { echo "Not a directory: $share_dir" >&2; exit 2; }
    share_dir=$(realpath -- "$share_dir")
    [[ $share_dir != *$'\n'* && $share_dir != *$'\r'* ]] || exit 2
fi
if [[ -z $timeout_arg ]]; then
    if [[ $phase == normal || $phase == setup ]]; then timeout_arg=0; else timeout_arg=${FTPM_TIMEOUT:-300}; fi
fi
[[ $timeout_arg =~ ^[0-9]+$ ]] || { echo 'Timeout must be a nonnegative integer (seconds)' >&2; exit 2; }
[[ $gdb_port =~ ^[0-9]{1,5}$ ]] && ((10#$gdb_port >= 1 && 10#$gdb_port <= 65535)) || { echo 'Invalid GDB port' >&2; exit 2; }
((qemu_console == 0)) || [[ -z $monitor_socket ]] || { echo 'Choose --qemu-console or --monitor-socket' >&2; exit 2; }
if [[ -n $monitor_socket ]]; then
    monitor_socket=$(realpath -m -- "$monitor_socket")
    [[ ! -e $monitor_socket && ! -L $monitor_socket && $monitor_socket != *$'\n'* ]] || { echo 'Monitor path already exists or is invalid' >&2; exit 2; }
    [[ -d $(dirname -- "$monitor_socket") ]] || { echo 'Monitor socket parent must exist' >&2; exit 2; }
fi
out=work/ftpm-virt
for file in device-identity.bin provisioning.bin rootfs.ext4; do
    [[ -f $out/$file ]] || { echo "Missing: $out/$file" >&2; exit 1; }
done
[[ -w $out/rootfs.ext4 ]] || { echo 'Disk is not writable' >&2; exit 1; }
require_commands python3 dtc flock
exec 9>"$out/runtime.lock"
flock -n 9 || { echo "Another launcher is using this device. Stop QEMU first." >&2; exit 1; }
[[ -x $qemu_bin ]] || { echo 'Run scripts/build-qemu.sh first' >&2; exit 1; }
max_cpus=1
[[ ! -f $ftpm_boot_dir/firmware-cpus.txt ]] || max_cpus=$(cat "$ftpm_boot_dir/firmware-cpus.txt")
[[ $max_cpus =~ ^[1-8]$ ]] || { echo 'Invalid firmware CPU metadata' >&2; exit 1; }
((cpus <= max_cpus)) || { echo 'Rebuild firmware with scripts/build-ftpm-virt-firmware.sh for multi-core support' >&2; exit 1; }
[[ -f $ftpm_boot_dir/firmware-gic.txt && $(cat "$ftpm_boot_dir/firmware-gic.txt") == 3 ]] || { echo 'Rebuild firmware for GICv3 with scripts/build-ftpm-virt-firmware.sh' >&2; exit 1; }
for file in flash.bin Image; do
    [[ -f $ftpm_boot_dir/$file ]] || { echo "Missing installed artifact: $file" >&2; exit 1; }
done
# CPU topology and SSH flags must match this exact invocation, not a stale DTB.
dtb_options=(--cpus "$cpus")
((ssh_enabled == 0)) || dtb_options+=(--ssh)
bash "$repo/scripts/prepare-ftpm-virt-dtb.sh" "${dtb_options[@]}"
secure_log=${FTPM_SECURE_LOG:-$out/secure-$phase-native.log}
args=("$qemu_bin" -L "$qemu_data_dir"
    -machine "jetson-ftpm-virt,secure=on,gic-version=3,identity-file=$out/device-identity.bin,provisioning-file=$out/provisioning.bin"
    -cpu cortex-a57 -smp "$cpus" -m 1024M -display none
    -bios "$ftpm_boot_dir/flash.bin" -dtb "$ftpm_boot_dir/runtime-$phase.dtb"
    -device "loader,file=$ftpm_boot_dir/Image,addr=0x60200000,force-raw=on"
    -drive "if=none,id=root,file=$out/rootfs.ext4,format=raw" -device virtio-blk-device,drive=root
    -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-device,rng=rng0)
if ((qemu_console)); then
    args+=(-chardev stdio,id=console,mux=on,signal=off -serial chardev:console -object monitor-hmp,id=hmp,chardev=console,readline=on)
else
    args+=(-serial stdio)
    if [[ -n $monitor_socket ]]; then
        monitor_path=${monitor_socket//,/,,}
        args+=(-chardev "socket,id=qmon,path=$monitor_path,server=on,wait=off" -object monitor-hmp,id=hmp,chardev=qmon,readline=on)
    else args+=(-monitor none)
    fi
fi
args+=(-serial "file:$secure_log")
if ((gdb_enabled)); then args+=(-gdb "tcp:127.0.0.1:$gdb_port"); fi
if ((wait_gdb)); then args+=(-S); fi
if ((ssh_enabled)); then
    args+=(-netdev "user,id=net0,hostfwd=tcp:127.0.0.1:$ssh_port-:22" -device virtio-net-device,netdev=net0)
else args+=(-nic none)
fi
if [[ -n $share_dir ]]; then
    # QEMU's comma-separated option parser escapes literal commas by doubling them.
    share_path=${share_dir//,/,,}
    fsdev="local,id=hostshare,path=$share_path,security_model=mapped-xattr"
    ((share_rw)) || fsdev+=,readonly=on
    args+=(-fsdev "$fsdev" -device virtio-9p-device,fsdev=hostshare,mount_tag=hostshare)
fi
if ((10#$timeout_arg == 0)); then
    exec "${args[@]}"
else
    require_commands timeout
    exec timeout --foreground "$timeout_arg" "${args[@]}"
fi
