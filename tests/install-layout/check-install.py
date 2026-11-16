#!/usr/bin/env python3
"""Check installed architecture layout, isolated prefixes and secret exclusion."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts'))
from install_paths import REPO, install_dir

prefix=install_dir()
required=['bin/qemu-system-aarch64','include/tee_client_api.h',
          'lib/aarch64-linux-gnu/libteec.so',
          'libexec/aarch64-linux-gnu/tee-supplicant',
          'libexec/aarch64-linux-gnu/nvftpm-helper-app',
          'libexec/aarch64-linux-gnu/ftpm-helper-probe',
          'share/qemu-jetson/ftpm-virt/flash.bin','share/qemu-jetson/ftpm-virt/Image',
          'share/qemu-jetson/ftpm-virt/runtime-bound.dtb',
          'lib/optee/ta-dev-kit-aarch64/include/tee_internal_api.h']
for name in required:
    assert (prefix/name).is_file(), name
for name in ['libexec/aarch64-linux-gnu/ftpm-helper-probe','lib/aarch64-linux-gnu/libteec.so']:
    data=(prefix/name).read_bytes()[:20]
    assert data[:4]==b'\x7fELF' and int.from_bytes(data[18:20],'little')==183, name
for path in prefix.rglob('*'):
    assert path.name not in ['device-identity.bin','provisioning.bin','rootfs.ext4'], path
    assert path.suffix not in ['.pem','.key'], path
# A non-default prefix containing spaces must not write into the default prefix.
with tempfile.TemporaryDirectory(prefix='install layout test.',dir=REPO/'work') as tmp:
    custom=Path(tmp)/'custom install'
    env=dict(os.environ,INSTALL_DIR=str(custom))
    subprocess.run([sys.executable,str(REPO/'scripts/install-artifacts.py'),'client',
                    '--client-export',str(prefix)],env=env,check=True)
    assert (custom/'include/tee_client_api.h').is_file()
    assert (custom/'lib/aarch64-linux-gnu/libteec.so').is_file()
    assert (custom/'libexec/aarch64-linux-gnu/tee-supplicant').is_file()
    # Device state is deliberately absent even when a work tree contains it.
    state=REPO/'work/ftpm-virt/device-identity.bin'
    before=state.read_bytes()
    subprocess.run([sys.executable,str(REPO/'scripts/install-artifacts.py'),'probe'],env=env,check=True)
    assert state.read_bytes()==before
    assert not list(custom.rglob('device-identity.bin'))
print('PASS: local install layout, AArch64 libraries, custom prefix and device-secret exclusion')
