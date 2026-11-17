#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
cd "$repo"
cpus=4
ssh_enabled=0
while (($#)); do
    case $1 in
        --cpus) [[ $# -ge 2 ]] || exit 2; cpus=$2; shift 2;;
        --ssh) ssh_enabled=1; shift;;
        *) echo "Usage: $0 [--cpus 1..8] [--ssh]" >&2; exit 2;;
    esac
done
[[ $cpus =~ ^[1-8]$ ]] || { echo 'CPU count must be 1..8' >&2; exit 2; }
out=work/ftpm-virt
test -f "$out/provisioning.bin" || { echo 'Provisioning data is required for B2 tests' >&2; exit 1; }
require_commands python3 dtc
[[ -x "$qemu_bin" ]] || { echo 'Run scripts/build-qemu.sh first' >&2; exit 1; }
rm -f -- "$out/virt.dtb"
"$qemu_bin" -L "$qemu_data_dir" \
    -machine jetson-ftpm-virt,secure=on,gic-version=3,identity-file="$out/device-identity.bin",provisioning-file="$out/provisioning.bin",dumpdtb="$out/virt.dtb" \
    -cpu cortex-a57 -smp "$cpus" -m 1024M -display none -monitor none -bios "$ftpm_boot_dir/flash.bin"
dtc -I dtb -O dts -o "$out/virt.dts" "$out/virt.dtb"
PYTHONPATH="$repo/scripts${PYTHONPATH:+:$PYTHONPATH}" python3 - "$out" "$ssh_enabled" <<'PY'
import pathlib, sys
from ftpm_provisioning import dt_nodes
out = pathlib.Path(sys.argv[1])
s = (out/'virt.dts').read_text()
# Reserve TF-A/OP-TEE secure RAM from Linux early allocation.
s = s.replace('/dts-v1/;', '/dts-v1/;\n/memreserve/ 0x0e000000 0x01000000;')
s = s.replace('\n\tchosen {', '\n\tftpm { compatible = "microsoft,ftpm"; };\n\tchosen {', 1)
s = s.replace('\n\tchosen {', '\n\t' + dt_nodes((out/'provisioning.bin').read_bytes()) + '\n\tchosen {', 1)
# TF-A provides PSCI, but the loaded external DT must describe its interface.
if 'arm,psci-0.2' not in s:
    s = s.replace('\n\tchosen {', '\n\tpsci { compatible = "arm,psci-0.2"; method = "smc"; };\n\tchosen {', 1)
# Decision 0006: Ubuntu test rootfs has no SELinux policy or file labels.
for phase in ('normal', 'setup', 'first', 'second', 'export', 'bound'):
    args = "console=ttyAMA0,115200 earlycon root=/dev/vda rw rootwait panic=5 lsm=lockdown,yama,integrity,apparmor,bpf systemd.log_target=console"
    if phase in ('first', 'second'):
        args += ' ftpm.test=' + phase
    elif phase in ('export', 'bound'):
        args += ' ftpm.identity_test=' + phase
    if phase == 'setup':
        args += ' qemu.setup=1'
    if sys.argv[2] == '1' and phase in ('normal', 'setup'):
        args += ' qemu.net=1 qemu.ssh=1'
    text = s.replace('\n\tchosen {', '\n\tchosen {\n bootargs = "' + args + '";', 1)
    (out/f'runtime-{phase}.dts').write_text(text)
PY
for phase in normal setup first second export bound; do
    dtc -I dts -O dtb -p 16384 -o "$out/runtime-$phase.dtb" "$out/runtime-$phase.dts"
done

# OP-TEE reads this 64-bit seed before enabling its MMU with alignment checks on.
python3 "$repo/scripts/align-optee-dtb.py" "$out"/runtime-*.dtb
python3 "$repo/scripts/install-artifacts.py" dtb
