#!/usr/bin/env python3
"""Require real success markers and bind exported TPM EKs to test certificates."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import hashes

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('logs',type=Path)
p.add_argument('bound_credentials',type=Path)
p.add_argument('output',type=Path)
args=p.parse_args()
logs={name:(args.logs/(name+'.log')).read_text() for name in ['first','second','export','bound','bound-reboot','accounts-fixed']}
for name,text in logs.items():
    if any(marker in text for marker in ['FTPM_TEST: FAIL','PTA_TEST: FAIL','EK_TEST: FAIL']):
        raise SystemExit('Failed test in '+name)
for name in ['first','second']:
    assert 'FTPM_TEST: PASS phase='+name in logs[name], name
    for marker in ['PTA_TEST: PING_NS READY PASS','PTA_TEST: online mode / version 2.0 PASS',
        'PTA_TEST: certificates/CSR match, CA chains, Firmware ID signature PASS',
        'FTPM_TEST: RSA sign/verify PASS','FTPM_TEST: seal/unseal PASS']:
        assert marker in logs[name],(name,marker)
assert 'FTPM_TEST: NV write/read PASS' in logs['first']
assert 'FTPM_TEST: PCR extend PASS' in logs['first']
assert 'FTPM_TEST: reboot NV/key persistence and PCR reset PASS' in logs['second']
for marker in ['EK_TEST: actual RSA/EC EK keys match PTA certificates PASS',
    'EK_TEST: standard RSA/EC EK certificate NV indices PASS','FTPM_TEST: PASS phase=second','EK_TEST: PASS']:
    assert marker in logs['bound'], marker
    assert marker in logs['bound-reboot'], marker
    assert marker in logs['accounts-fixed'], marker
ca=x509.load_pem_x509_certificate((args.bound_credentials/'ca-cert.pem').read_bytes())
fw=x509.load_der_x509_certificate((args.bound_credentials/'firmware_id-cert.der').read_bytes())
exports={name:dict(re.findall(r'EK_EXPORT: (rsa|ecc) ([A-Za-z0-9+/=]+)',text)) for name,text in logs.items() if name in ['export','bound','bound-reboot','accounts-fixed']}
public_hashes={}
for kind,fixture in [('rsa','fixture_rsa'),('ecc','fixture_ec')]:
    assert exports['export'][kind]==exports['bound'][kind], 'EK changed across boot'
    assert exports['bound'][kind]==exports['bound-reboot'][kind], 'EK changed after certificate NV provisioning'
    assert exports['bound'][kind]==exports['accounts-fixed'][kind], 'EK changed after rootfs account fix'
    pem=base64.b64decode(exports['bound'][kind],validate=True)
    key=serialization.load_pem_public_key(pem)
    spki=key.public_bytes(serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo)
    cert=x509.load_der_x509_certificate((args.bound_credentials/(fixture+'-cert.der')).read_bytes())
    assert cert.public_key().public_bytes(serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo)==spki
    ca.public_key().verify(cert.signature,cert.tbs_certificate_bytes,ec.ECDSA(cert.signature_hash_algorithm))
    csr=x509.load_der_x509_csr((args.bound_credentials/(fixture+'-csr.der')).read_bytes())
    assert csr.public_key().public_bytes(serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo)==spki
    fw.public_key().verify(csr.signature,csr.tbs_certrequest_bytes,ec.ECDSA(hashes.SHA256()))
    public_hashes[kind]=hashlib.sha256(spki).hexdigest()
assert 'FAILED' not in logs['accounts-fixed'], 'Remaining failed units after account fix'
assert 'Create System Users' in logs['accounts-fixed'] and 'Network Name Resolution' in logs['accounts-fixed']
repo=Path(__file__).resolve().parents[1]
baseline=json.loads((repo/'docs/results/ftpm-helper-b2.json').read_text())['checks']['source_unchanged']
source_hashes={name:hashlib.sha256((repo/name).read_bytes()).hexdigest() for name in baseline}
assert source_hashes==baseline, 'NVIDIA TA/PTA source changed'
report={'profile':'jetson-ftpm-virt B2','status':'PASS','trust':'QEMU-only test CA; no NVIDIA manufacturing trust',
    'checks':['full NVIDIA helper PTA readiness, SN, ECID, provisioning mode 2.0',
    'RSA/EC EK certificates, SID/Firmware ID certificates, RSA/EC CSRs',
    'SIGN_EK_CSR verified with Firmware ID public key',
    'invalid signing parameters and disabled INJECT_EPS rejected',
    'TPM GetCapability and 16-byte GetRandom','NV write/read','PCR extend',
    'RSA signing verified with OpenSSL','seal/unseal',
    'cold-boot NV, persistent signing key, sealed-object persistence and PCR reset',
    'actual RSA/EC EK public keys stable across independent QEMU processes',
    'test-CA EK certificates and Firmware-ID-signed CSR public keys match actual EKs',
    'standard TCG EK certificate NV indices written, read back and retained across cold boot'],
    'public_ek_spki_sha256':public_hashes,
    'unchanged_nvidia_source_sha256':source_hashes,
    'rootfs_account_fix':'PASS: sysusers/resolved start; fTPM and bound EK checks pass on preserved disk',
    'log_sha256':{name:hashlib.sha256((args.logs/(name+'.log')).read_bytes()).hexdigest() for name in logs},
    'limitations':['software emulation; host administrator can read secrets',
    'no SE hardware protection or REE filesystem rollback protection',
    'Measured Boot disabled','INJECT_EPS disabled',
    'initial API fixtures were not real EKs; bound boot validates actual EK certificates',
    'test coverage is not exhaustive for every TPM command or OS service']}
args.output.write_text(json.dumps(report,indent=2)+'\n')
print('PASS: fTPM persistence, NVIDIA helper PTA APIs, and actual EK certificate binding')
