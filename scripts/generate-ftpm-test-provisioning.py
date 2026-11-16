#!/usr/bin/env python3
"""Generate QEMU-only test credentials, never NVIDIA manufacturing credentials."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.x509.oid import NameOID, ObjectIdentifier


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
    out = args.output
    now = dt.datetime.now(dt.timezone.utc)
    keys = {'ca': ec.generate_private_key(ec.SECP256R1()),
            'firmware_id': ec.generate_private_key(ec.SECP256R1()),
            'sid': ec.generate_private_key(ec.SECP256R1()),
            'fixture_rsa': rsa.generate_private_key(public_exponent=65537, key_size=2048),
            'fixture_ec': ec.generate_private_key(ec.SECP256R1())}
    names = {role: x509.Name([x509.NameAttribute(NameOID.ORGANIZATION_NAME, 'QEMU Jetson TEST ONLY'),
                              x509.NameAttribute(NameOID.COMMON_NAME, 'QEMU TEST ONLY ' + role)])
             for role in keys}
    certs = {}
    for role, key in keys.items():
        (out/(role + '-key.pem')).write_bytes(key.private_bytes(serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        builder = x509.CertificateBuilder().subject_name(names[role]).issuer_name(names['ca']) \
            .public_key(key.public_key()).serial_number(x509.random_serial_number()) \
            .not_valid_before(now - dt.timedelta(days=1)).not_valid_after(now + dt.timedelta(days=3650)) \
            .add_extension(x509.BasicConstraints(ca=role == 'ca', path_length=0 if role == 'ca' else None), True)
        if role.startswith('fixture_'):
            builder = builder.add_extension(x509.ExtendedKeyUsage([ObjectIdentifier('2.23.133.8.1')]), False)
        cert = builder.sign(keys['ca'], hashes.SHA256())
        certs[role] = cert
        (out/(role + '-cert.der')).write_bytes(cert.public_bytes(serialization.Encoding.DER))
        (out/(role + '-cert.pem')).write_bytes(cert.public_bytes(serialization.Encoding.PEM))
        (out/(role + '-public.pem')).write_bytes(key.public_key().public_bytes(
            serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
    (out/'firmware-id-scalar.bin').write_bytes(keys['firmware_id'].private_numbers().private_value.to_bytes(32, 'big'))
    for seed in ('ftpm-seed.bin', 'eps-seed.bin'):
        (out/seed).write_bytes(os.urandom(32))
    for role in ('fixture_rsa', 'fixture_ec'):
        csr = x509.CertificateSigningRequestBuilder().subject_name(names[role]).sign(keys[role], hashes.SHA256())
        (out/(role + '-csr.der')).write_bytes(csr.public_bytes(serialization.Encoding.DER))
    manifest = {'ftpm_seed': 'ftpm-seed.bin', 'firmware_id_key': 'firmware-id-scalar.bin',
                'firmware_id_cert': 'firmware_id-cert.der', 'eps_seed': 'eps-seed.bin',
                'rsa_ek_cert': 'fixture_rsa-cert.der', 'ec_ek_cert': 'fixture_ec-cert.der',
                'sid_cert': 'sid-cert.der', 'rsa_ek_csr': 'fixture_rsa-csr.der',
                'ec_ek_csr': 'fixture_ec-csr.der'}
    (out/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    (out/'validation-epoch.txt').write_text(str(int(now.timestamp()))+'\n')
    (out/'README.txt').write_text('QEMU TEST ONLY. No NVIDIA/manufacturer trust.\n'
        'fixture_rsa/ec are API fixtures, NOT verified TPM EKs.\n'
        'Actual fTPM EK public keys must be exported and certified separately before claiming EK binding.\n')
    print('QEMU-only test credentials created; no existing state replaced.')


if __name__ == '__main__':
    main()
