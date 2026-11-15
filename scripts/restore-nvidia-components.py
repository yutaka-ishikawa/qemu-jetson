#!/usr/bin/env python3
"""Restore excluded NVIDIA files locally; never overwrite an existing file."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

repo = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('optee_archive', type=Path)
parser.add_argument('kernel_archive', type=Path)
args = parser.parse_args()
manifest = json.loads((repo / 'manifests/optee-excluded-files.json').read_text())
inputs = [
    (args.optee_archive, manifest['archive_sha256'], repo / 'optee', manifest['excluded']),
    (args.kernel_archive, '2a26015d13a2c4551c1266c8ec7503fc27b487d1cf74ccf3965d0633dacced1d', repo / 'kernel', ['nvcommon_build.sh']),
]
# Verify every input before writing anything.
for archive, expected, _, _ in inputs:
    with archive.open('rb') as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
        actual = digest.hexdigest()
    if actual != expected:
        raise SystemExit(f'Archive hash mismatch: {archive}')
for archive, _, target, names in inputs:
    with tarfile.open(archive, 'r:bz2') as source:
        members = {m.name.removeprefix('./'): m for m in source}
        for name in names:
            member = members[name]
            if not member.isfile():
                raise SystemExit(f'Expected a regular file: {name}')
            destination = target / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            data = source.extractfile(member).read()
            if destination.exists():
                if destination.is_symlink() or destination.read_bytes() != data:
                    raise SystemExit(f'Refusing to overwrite: {destination}')
                continue
            with destination.open('xb') as stream:
                stream.write(data)
            destination.chmod(member.mode & 0o777)
            print(f'Restored locally: {destination.relative_to(repo)}')
