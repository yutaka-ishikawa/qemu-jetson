#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
[[ $# == 1 ]] || { echo 'Usage: update-ftpm-test-disk.sh PUBLIC_FIXTURE_DIRECTORY' >&2; exit 2; }
fixtures=$(cd "$1" && pwd)
case "$fixtures/" in "$repo/work/"*) ;; *) echo 'Fixtures must be inside the repository work directory' >&2; exit 1;; esac
[[ $(docker ps -q --filter ancestor=qemu-jetson-build:jammy | wc -l) == 0 ]] || { echo 'Stop QEMU before editing the disk' >&2; exit 1; }
python3 - "$repo" "$fixtures" <<'PY'
from pathlib import Path
import sys, os, tarfile
repo, fixtures = map(Path, sys.argv[1:])
disk = (repo/'work/ftpm-virt/rootfs.ext4').resolve()
for process in Path('/proc').iterdir():
    if not process.name.isdigit():
        continue
    try:
        if not (process/'comm').read_text().startswith('qemu-system'):
            continue
        for descriptor in (process/'fd').iterdir():
            if descriptor.resolve() == disk:
                raise SystemExit('Stop native QEMU before editing the disk')
    except (PermissionError, FileNotFoundError, ProcessLookupError):
        continue
lines = ['rm /.dockerenv', 'set_inode_field / mode 040755']
base = repo/'configs/rootfs/functional-overlay'
for d in sorted(base.rglob('*'), key=lambda p: len(p.parts)):
    target = '/'+str(d.relative_to(base))
    if d.is_dir():
        lines += ['mkdir '+target, 'set_inode_field '+target+' mode 040755']
    elif d.is_symlink():
        lines += ['rm '+target, 'symlink '+target+' '+str(d.readlink())]
    else:
        mode = '0100755' if '/sbin/' in target else '0100644'
        lines += ['rm '+target, 'write '+str(d).replace(str(repo),'/src',1)+' '+target,
                  'set_inode_field '+target+' mode '+mode]
for path in ['/usr/lib','/usr/sbin','/usr/lib/optee_armtz']:
    lines += ['set_inode_field '+path+' mode 040755']
public = ['ca-cert.pem', 'firmware_id-cert.der', 'fixture_rsa-cert.der', 'fixture_ec-cert.der',
          'sid-cert.der','fixture_rsa-csr.der','fixture_ec-csr.der','validation-epoch.txt',
          'fixture_rsa-csr-tbs.der','fixture_ec-csr-tbs.der',
          'fixture_rsa-csr-signature.der','fixture_ec-csr-signature.der']
for name in public:
    if (fixtures/name).exists():
        target='/usr/share/qemu-ftpm-test/'+name
        lines += ['rm '+target, 'write '+str(fixtures/name).replace(str(repo),'/src',1)+' '+target,
                  'set_inode_field '+target+' mode 0100644']
if os.environ.get('FTPM_UPDATE_ACCOUNTS') == '1':
    accounts = repo/'work/ftpm-virt/accounts'
    accounts.mkdir(mode=0o700,exist_ok=True)
    with tarfile.open(repo/'work/ftpm-virt/rootfs.tar') as tar:
        for name in ['passwd','group','shadow','gshadow']:
            source=accounts/name
            source.write_bytes(tar.extractfile('etc/'+name).read())
            source.chmod(0o600)
            mode='0100640' if name in ['shadow','gshadow'] else '0100644'
            gid=42 if name in ['shadow','gshadow'] else 0
            lines += ['rm /etc/'+name, 'write '+str(source).replace(str(repo),'/src',1)+' /etc/'+name,
                      'set_inode_field /etc/'+name+' mode '+mode,
                      'set_inode_field /etc/'+name+' gid '+str(gid)]
(repo/'work/ftpm-virt/update-test.debugfs').write_text('\n'.join(lines)+'\n')
PY
docker run --rm -v "$repo:/src" ubuntu:22.04 sh -ec '
 apt-get update >/dev/null
 apt-get install -y --no-install-recommends e2fsprogs >/dev/null
 (e2fsck -fy /src/work/ftpm-virt/rootfs.ext4 || [ "$?" -eq 1 ])
 debugfs -w -f /src/work/ftpm-virt/update-test.debugfs /src/work/ftpm-virt/rootfs.ext4
 (e2fsck -fy /src/work/ftpm-virt/rootfs.ext4 || [ "$?" -eq 1 ])
 e2fsck -fn /src/work/ftpm-virt/rootfs.ext4
'
