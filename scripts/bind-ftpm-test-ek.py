#!/usr/bin/env python3
"""Issue test-only certificates/CSRs for EK public keys exported by the real fTPM."""
import argparse
import base64
import datetime as dt
import json
import os
from pathlib import Path
import re
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID, ObjectIdentifier


def der(tag, data):
    length = len(data)
    size = bytes([length]) if length < 128 else bytes([0x80 + (length.bit_length()+7)//8]) + length.to_bytes((length.bit_length()+7)//8, 'big')
    return bytes([tag]) + size + data


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('credentials', type=Path)
    p.add_argument('export_log', type=Path)
    p.add_argument('output', type=Path)
    args = p.parse_args()
    text = args.export_log.read_text()
    if 'EK_TEST: PASS' not in text or 'EK_TEST: FAIL' in text:
        p.error('EK export did not pass')
    exported = dict(re.findall(r'EK_EXPORT: (rsa|ecc) ([A-Za-z0-9+/=]+)', text))
    if set(exported) != {'rsa', 'ecc'}:
        p.error('missing real TPM EK public key exports')
    os.umask(0o077)
    args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
    src, out = args.credentials.resolve(), args.output.resolve()
    ca = x509.load_pem_x509_certificate((src/'ca-cert.pem').read_bytes())
    ca_key = serialization.load_pem_private_key((src/'ca-key.pem').read_bytes(), None)
    fw_key = serialization.load_pem_private_key((src/'firmware_id-key.pem').read_bytes(), None)
    manifest = json.loads((src/'manifest.json').read_text())
    manifest = {k: os.path.relpath(src/v, out) for k,v in manifest.items()}
    now = dt.datetime.now(dt.timezone.utc)
    for kind, fixture in [('rsa', 'fixture_rsa'), ('ecc', 'fixture_ec')]:
        pem = base64.b64decode(exported[kind], validate=True)
        key = serialization.load_pem_public_key(pem)
        name = x509.Name([x509.NameAttribute(NameOID.ORGANIZATION_NAME, 'QEMU Jetson TEST ONLY'),
                          x509.NameAttribute(NameOID.COMMON_NAME, 'QEMU TEST ONLY actual '+kind+' EK')])
        cert = x509.CertificateBuilder().subject_name(name).issuer_name(ca.subject).public_key(key) \
            .serial_number(x509.random_serial_number()).not_valid_before(now-dt.timedelta(days=1)) \
            .not_valid_after(now+dt.timedelta(days=3650)) \
            .add_extension(x509.BasicConstraints(ca=False,path_length=None),True) \
            .add_extension(x509.ExtendedKeyUsage([ObjectIdentifier('2.23.133.8.1')]),False) \
            .sign(ca_key,hashes.SHA256())
        spki=key.public_bytes(serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo)
        tbs=der(0x30, b'\x02\x01\x00'+name.public_bytes()+spki+b'\xa0\x00')
        sig=fw_key.sign(tbs,ec.ECDSA(hashes.SHA256()))
        # NVIDIA's intended Firmware ID-signed CSR: the signing key differs from its EK SPKI.
        csr=der(0x30,tbs+b'\x30\x0a\x06\x08\x2a\x86\x48\xce\x3d\x04\x03\x02'+der(3,b'\0'+sig))
        loaded=x509.load_der_x509_csr(csr)
        fw_key.public_key().verify(loaded.signature,loaded.tbs_certrequest_bytes,ec.ECDSA(hashes.SHA256()))
        assert loaded.public_key().public_bytes(serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo)==spki
        (out/(fixture+'-cert.der')).write_bytes(cert.public_bytes(serialization.Encoding.DER))
        (out/(fixture+'-csr.der')).write_bytes(csr)
        (out/(fixture+'-csr-tbs.der')).write_bytes(tbs)
        (out/(fixture+'-csr-signature.der')).write_bytes(sig)
        (out/(kind+'-ek-public.pem')).write_bytes(pem)
        prefix='rsa' if kind=='rsa' else 'ec'
        manifest[prefix+'_ek_cert']=fixture+'-cert.der'
        manifest[prefix+'_ek_csr']=fixture+'-csr.der'
    for filename in ['ca-cert.pem','firmware_id-cert.der','sid-cert.der','validation-epoch.txt']:
        (out/filename).write_bytes((src/filename).read_bytes())
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (out/'README.txt').write_text('TEST ONLY: certificates bind to actual fTPM-exported EK public keys.\n'
        'CSR signatures use Firmware ID, not EK. No EK private keys were exported.\n')
    print('Test-only certificates issued for actual fTPM RSA/EC EK public keys; seeds and device keys unchanged.')


if __name__=='__main__': main()
