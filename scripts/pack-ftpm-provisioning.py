#!/usr/bin/env python3
"""Pack supplied provisioning data; never generate or rotate device keys."""
import argparse
import json
import os
from pathlib import Path
from ftpm_provisioning import FIELDS, pack


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path, help='JSON mapping field names to input files')
    parser.add_argument('identity', type=Path, help='existing JFTPM001 device identity')
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    if set(manifest) - FIELDS.keys():
        parser.error('unknown manifest fields')
    identity = args.identity.read_bytes()
    if len(identity) != 72 or identity[:8] != b'JFTPM001':
        parser.error('invalid device identity')
    values = {FIELDS[name]: (args.manifest.parent / path).read_bytes()
              for name, path in manifest.items()}
    if 91 in values and values[91] != identity[40:50]:
        parser.error('supplied SN does not match virtual device identity')
    values[91] = identity[40:50]
    image = pack(values)
    # Check key/certificate consistency without logging any private values.
    from cryptography import x509
    from cryptography.hazmat.primitives.asymmetric import ec
    key = ec.derive_private_key(int.from_bytes(values[2], 'big'), ec.SECP256R1())
    cert = x509.load_der_x509_certificate(values[3])
    if key.public_key().public_numbers() != cert.public_key().public_numbers():
        parser.error('Firmware ID key does not match certificate')
    for field in ('rsa_ek_cert', 'ec_ek_cert', 'sid_cert'):
        if FIELDS[field] in values:
            x509.load_der_x509_certificate(values[FIELDS[field]])
    for field in ('rsa_ek_csr', 'ec_ek_csr'):
        if FIELDS[field] in values:
            x509.load_der_x509_csr(values[FIELDS[field]])
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as f:
        f.write(image)
    print('Provisioning image written; existing keys and files were not replaced.')


if __name__ == '__main__':
    main()
