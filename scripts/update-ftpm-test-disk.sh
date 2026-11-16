#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/host-common.sh"
require_commands python3 e2fsck debugfs
cd "$repo"
[[ $# == 1 ]] || { echo 'Usage: update-ftpm-test-disk.sh PUBLIC_FIXTURE_DIRECTORY' >&2; exit 2; }
fixtures=$(cd "$1" && pwd)
case "$fixtures/" in "$repo/work/"*) ;; *) echo 'Fixtures must be inside the repository work directory' >&2; exit 1;; esac
PYTHONPATH="$repo/scripts${PYTHONPATH:+:$PYTHONPATH}" python3 - "$repo" "$fixtures" <<'PY'
from pathlib import Path
import sys, os, tarfile
from install_paths import guest_bin_dir, guest_lib_dir
repo, fixtures = map(Path, sys.argv[1:])
def quote_path(path):
    text = str(path)
    if '\n' in text or '\r' in text:
        raise SystemExit('Newlines in disk-update paths are unsupported')
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'
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
lines = ['set_inode_field / mode 040755']
base = repo/'configs/rootfs/functional-overlay'
for d in sorted(base.rglob('*'), key=lambda p: len(p.parts)):
    target = '/'+str(d.relative_to(base))
    if d.is_dir():
        lines += ['mkdir '+target, 'set_inode_field '+target+' mode 040755']
    elif d.is_symlink():
        lines += ['rm '+target, 'symlink '+target+' '+str(d.readlink())]
    else:
        mode = '0100755' if '/sbin/' in target else '0100644'
        lines += ['rm '+target, 'write '+quote_path(d)+' '+target,
                  'set_inode_field '+target+' mode '+mode, 'set_inode_field '+target+' uid 0', 'set_inode_field '+target+' gid 0']
    lines += ['set_inode_field '+target+' uid 0', 'set_inode_field '+target+' gid 0']
for path in ['/usr/lib','/usr/sbin','/usr/lib/optee_armtz']:
    lines += ['set_inode_field '+path+' mode 040755']
public = ['ca-cert.pem', 'firmware_id-cert.der', 'fixture_rsa-cert.der', 'fixture_ec-cert.der',
          'sid-cert.der','fixture_rsa-csr.der','fixture_ec-csr.der','validation-epoch.txt',
          'fixture_rsa-csr-tbs.der','fixture_ec-csr-tbs.der',
          'fixture_rsa-csr-signature.der','fixture_ec-csr-signature.der']
for name in public:
    if (fixtures/name).exists():
        target='/usr/share/qemu-ftpm-test/'+name
        lines += ['rm '+target, 'write '+quote_path(fixtures/name)+' '+target,
                  'set_inode_field '+target+' mode 0100644', 'set_inode_field '+target+' uid 0', 'set_inode_field '+target+' gid 0']
# Deploy the newly built, installed guest client and test probe while offline.
for name in ['tee-supplicant','nvftpm-helper-app','ftpm-helper-probe']:
    source=guest_bin_dir()/name
    if not source.is_file(): raise SystemExit('Missing installed guest program: '+str(source))
    target=('/usr/local/sbin/' if name=='ftpm-helper-probe' else '/usr/sbin/')+name
    lines += ['rm '+target, 'write '+quote_path(source)+' '+target,
              'set_inode_field '+target+' mode 0100755', 'set_inode_field '+target+' uid 0', 'set_inode_field '+target+' gid 0']
for source in sorted(guest_lib_dir().glob('*.so*')):
    target='/usr/lib/'+source.name
    lines += ['rm '+target]
    if source.is_symlink():
        lines += ['symlink '+target+' '+str(source.readlink())]
    else:
        lines += ['write '+quote_path(source)+' '+target, 'set_inode_field '+target+' mode 0100644']
    lines += ['set_inode_field '+target+' uid 0', 'set_inode_field '+target+' gid 0']
source=guest_lib_dir()/'optee_armtz/7fc1d460-5a6c-4a5f-9b9e-6c298d3032a0.ta'
if not source.is_file(): raise SystemExit('Build and install the helper probe TA first')
target='/usr/lib/optee_armtz/'+source.name
lines += ['rm '+target,'write '+quote_path(source)+' '+target,'set_inode_field '+target+' mode 0100644',
          'set_inode_field '+target+' uid 0','set_inode_field '+target+' gid 0']
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
            lines += ['rm /etc/'+name, 'write '+quote_path(source)+' /etc/'+name,
                      'set_inode_field /etc/'+name+' mode '+mode,
                      'set_inode_field /etc/'+name+' uid 0', 'set_inode_field /etc/'+name+' gid '+str(gid)]
(repo/'work/ftpm-virt/update-test.debugfs').write_text('\n'.join(lines)+'\n')
PY
disk="$repo/work/ftpm-virt/rootfs.ext4"
[[ -w "$disk" ]] || { echo "Disk is not writable: $disk" >&2; exit 1; }
repair() { local status=0; e2fsck -fy "$disk" || status=$?; ((status <= 1)); }
repair
debugfs -w -f "$repo/work/ftpm-virt/update-test.debugfs" "$disk"
repair
e2fsck -fn "$disk"
