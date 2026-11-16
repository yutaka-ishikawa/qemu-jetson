#!/usr/bin/env python3
"""Update an exported test rootfs tar with public fixtures and test-only probes."""
import argparse
import hashlib
import io
from pathlib import Path
import tarfile
from install_paths import guest_bin_dir, guest_lib_dir

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('tar', type=Path)
parser.add_argument('fixtures', type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
out = repo/'work/ftpm-virt'
identity = (out/'device-identity.bin').read_bytes()
public = ['ca-cert.pem', 'firmware_id-cert.der', 'fixture_rsa-cert.der', 'fixture_ec-cert.der',
          'sid-cert.der', 'fixture_rsa-csr.der', 'fixture_ec-csr.der', 'validation-epoch.txt']
public += [name for name in ['fixture_rsa-csr-tbs.der', 'fixture_ec-csr-tbs.der',
    'fixture_rsa-csr-signature.der', 'fixture_ec-csr-signature.der'] if (args.fixtures/name).exists()]
with tarfile.open(args.tar, 'a') as tar:
    def add_file(source, target, mode):
        info = tar.gettarinfo(str(source), target)
        info.uid = info.gid = 0
        info.uname = info.gname = 'root'
        info.mode = mode
        if info.isfile():
            with source.open('rb') as f: tar.addfile(info, f)
        else: tar.addfile(info)
    for p in (repo/'configs/rootfs/functional-overlay').rglob('*'):
        if not p.is_dir():
            target = str(p.relative_to(repo/'configs/rootfs/functional-overlay'))
            add_file(p, target, 0o755 if '/sbin/' in target else 0o644)
    for name in public:
        add_file(args.fixtures/name, 'usr/share/qemu-ftpm-test/'+name, 0o644)
    for name, data in [('sn.bin', identity[40:50]), ('ecid.bin', identity[50:58])]:
        info = tarfile.TarInfo('usr/share/qemu-ftpm-test/'+name)
        info.uid = info.gid = 0; info.mode = 0o644; info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
    add_file(guest_bin_dir()/'ftpm-helper-probe', 'usr/local/sbin/ftpm-helper-probe', 0o755)
    add_file(guest_lib_dir()/'optee_armtz/7fc1d460-5a6c-4a5f-9b9e-6c298d3032a0.ta',
             'usr/lib/optee_armtz/7fc1d460-5a6c-4a5f-9b9e-6c298d3032a0.ta', 0o644)
digest = hashlib.sha256()
with args.tar.open('rb') as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b''):
        digest.update(chunk)
args.tar.with_suffix(args.tar.suffix+'.sha256').write_text(
    digest.hexdigest()+'  '+args.tar.name+'\n')
print('Test overlay and public-only fixtures added; no private credentials copied.')
