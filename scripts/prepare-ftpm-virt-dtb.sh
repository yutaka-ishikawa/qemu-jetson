#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
out=work/ftpm-virt
docker run --rm -v "$repo:/src" -w /src qemu-jetson-build:jammy \
    work/qemu-container-build/qemu-system-aarch64 \
    -machine jetson-ftpm-virt,secure=on,gic-version=2,identity-file="$out/device-identity.bin",dumpdtb="$out/virt.dtb" \
    -cpu cortex-a57 -smp 1 -m 1024M -display none -monitor none -bios "$out/flash.bin"
dtc -I dtb -O dts -o "$out/virt.dts" "$out/virt.dtb"
python3 - "$out" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
s = (out/'virt.dts').read_text()
# Reserve TF-A/OP-TEE secure RAM from Linux early allocation.
s = s.replace('/dts-v1/;', '/dts-v1/;\n/memreserve/ 0x0e000000 0x01000000;')
s = s.replace('\n\tchosen {', '\n\tftpm { compatible = "microsoft,ftpm"; };\n\tchosen {', 1)
# TF-A provides PSCI, but the loaded external DT must describe its interface.
if 'arm,psci-0.2' not in s:
    s = s.replace('\n\tchosen {', '\n\tpsci { compatible = "arm,psci-0.2"; method = "smc"; };\n\tchosen {', 1)
for phase in ('first', 'second'):
    text = s.replace('\n\tchosen {', '\n\tchosen {\n bootargs = "console=ttyAMA0,115200 earlycon root=/dev/vda rw rootwait panic=5 systemd.log_target=console ftpm.test=' + phase + '";', 1)
    (out/f'runtime-{phase}.dts').write_text(text)
PY
for phase in first second; do
    dtc -I dts -O dtb -p 16384 -o "$out/runtime-$phase.dtb" "$out/runtime-$phase.dts"
done
