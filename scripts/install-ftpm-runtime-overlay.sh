#!/usr/bin/env bash
# Offline install of console/network/SSH configuration, preserving all device state.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
cd "$repo"
require_commands python3 debugfs e2fsck
python3 - "$repo" <<'PY'
import fcntl
from pathlib import Path
import os, subprocess, sys, tempfile
repo=Path(sys.argv[1]); disk=(repo/'work/ftpm-virt/rootfs.ext4').resolve()
lock=(repo/'work/ftpm-virt/runtime.lock').open('a')
try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError: raise SystemExit('Stop QEMU before updating the disk')
if not disk.is_file() or not os.access(disk, os.W_OK):
    raise SystemExit('Existing writable rootfs.ext4 is required')
# Refuse an image currently used by QEMU.
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit(): continue
    try:
        if not (proc/'comm').read_text().startswith('qemu-system'): continue
        if any(fd.resolve()==disk for fd in (proc/'fd').iterdir()):
            raise SystemExit('Stop QEMU before updating the disk')
    except PermissionError:
        raise SystemExit('Cannot inspect a QEMU process; stop it or run the updater with sufficient permissions')
    except (FileNotFoundError,ProcessLookupError): pass

def repair():
    status=subprocess.run(['e2fsck','-fy',str(disk)]).returncode
    if status not in (0,1): raise SystemExit('Filesystem check failed')

def quote(path):
    s=str(path)
    if '\n' in s or '\r' in s: raise SystemExit('Newlines in paths unsupported')
    return '"'+s.replace('\\','\\\\').replace('"','\\"')+'"'

base=repo/'configs/rootfs/runtime-overlay'
lines=['set_inode_field / mode 040755']
for p in sorted(base.rglob('*'),key=lambda p:(len(p.parts),str(p))):
    target='/'+str(p.relative_to(base))
    if p.is_symlink():
        lines += ['rm '+target,'symlink '+target+' '+str(p.readlink())]
    elif p.is_dir():
        lines += ['mkdir '+target,'set_inode_field '+target+' mode 040755']
    else:
        mode='0100755' if '/sbin/' in target else '0100644'
        lines += ['rm '+target,'write '+quote(p)+' '+target,'set_inode_field '+target+' mode '+mode]
    lines += ['set_inode_field '+target+' uid 0','set_inode_field '+target+' gid 0']
repair()
with tempfile.NamedTemporaryFile(mode='w',prefix='runtime-',suffix='.debugfs',dir=repo/'work') as f:
    f.write('\n'.join(lines)+'\n'); f.flush()
    subprocess.run(['debugfs','-w','-f',f.name,str(disk)],check=True)
repair()
subprocess.run(['e2fsck','-fn',str(disk)],check=True)
# Verify content, since debugfs may report individual command errors with status 0.
for p in base.rglob('*'):
    if not p.is_file() or p.is_symlink(): continue
    result=subprocess.run(['debugfs','-R','cat '+quote('/'+str(p.relative_to(base))),str(disk)],capture_output=True,check=True)
    if result.stdout != p.read_bytes():
        raise SystemExit('Installed file verification failed: '+str(p))
print('Runtime overlay installed; accounts, keys, TPM state and CA preserved.')
PY
