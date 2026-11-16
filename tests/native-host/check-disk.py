#!/usr/bin/env python3
"""Check native disk creation retains guest IDs and protects existing disks."""
import io
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

repo = Path(__file__).resolve().parents[2]
for name in ('fakeroot', 'mke2fs', 'debugfs'):
    if not shutil.which(name):
        raise SystemExit('Missing test tool: '+name+'; see docs/native-host.md')
with tempfile.TemporaryDirectory(prefix='native-disk-test.', dir=repo/'work') as tmp:
    out = Path(tmp)
    with tarfile.open(out/'rootfs.tar', 'w') as tar:
        for name in ('.','usr','usr/lib','usr/sbin','usr/lib/optee_armtz','etc'):
            info = tarfile.TarInfo(name)
            info.type = tarfile.DIRTYPE; info.mode = 0o755
            info.uid = info.gid = 0
            tar.addfile(info)
        info = tarfile.TarInfo('etc/ownership-check')
        info.uid = 0; info.gid = 42; info.mode = 0o640
        data = b'guest ownership metadata\n'; info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
    env = dict(os.environ, FTPM_IMAGE_DIR=str(out), FAKEROOTDONTTRYCHOWN='1')
    subprocess.run(['fakeroot','bash',str(repo/'scripts/create-ftpm-virt-disk.sh')], env=env, check=True)
    disk = out/'rootfs.ext4'
    result = subprocess.run(['debugfs','-R','stat /etc/ownership-check',str(disk)],
                            capture_output=True,text=True,check=True)
    assert re.search(r'User:\s+0\s+Group:\s+42',result.stdout), result.stdout
    assert '0640' in result.stdout, result.stdout
    before = (disk.stat().st_ino, disk.stat().st_mtime_ns)
    result = subprocess.run(['fakeroot','bash',str(repo/'scripts/create-ftpm-virt-disk.sh')],
                            env=env,capture_output=True,text=True)
    assert result.returncode != 0 and 'Refusing to overwrite' in result.stderr
    assert before == (disk.stat().st_ino,disk.stat().st_mtime_ns)
print('PASS: native disk preserves guest UID/GID/mode and refuses an existing disk')
