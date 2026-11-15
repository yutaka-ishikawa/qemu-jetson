#!/usr/bin/env python3

# Copyright (c) 2024, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: BSD-2-Clause

#
# Required Python modules:
#	sudo apt-get update
#	sudo apt-get install python3-pip
# 	python3 -m pip install asn1crypto (version 1.5.1)
#	python3 -m pip install oscrypto (version 1.3.0)
#

import argparse
import datetime
import os
import sys
import textwrap

from asn1crypto import csr, pem, util, x509
from oscrypto import asymmetric, errors

class fTPM_CA_Sign_Silicon_ID_CSR:
    def __init__(self, sid_csr, ca_cert, ca_priv_key, sid_cert_file_prefix, out_path):
        # Loading the Silicon ID CSR
        self.sid_csr = csr.CertificationRequest.load(sid_csr)
        self.sid_csr_cri = self.sid_csr['certification_request_info']
        self.sid_pub_key = asymmetric.load_public_key(self.sid_csr_cri['subject_pk_info'])
        self.sid_key_algo = self.sid_pub_key.algorithm

        # Loading CA properties
        if pem.detect(ca_cert):
            _, _, _ca_cert_der = pem.unarmor(ca_cert)
        else:
            _ca_cert_der = ca_cert
        self.ca_cert = x509.Certificate.load(_ca_cert_der)
        self.ca_priv_key = asymmetric.load_private_key(ca_priv_key)

        # Preparing the Silicon ID cert file
        self.sid_cert_file = out_path + "/" + sid_cert_file_prefix + ".der"
        self.sid_cert_fout = open(self.sid_cert_file, "wb")

    def verify_sid_csr(self):
        _sig = self.sid_csr['signature'].native

        if self.sid_key_algo == 'rsa':
            verify_func = asymmetric.rsa_pkcs1v15_verify
        elif self.sid_key_algo == 'ec':
            verify_func = asymmetric.ecdsa_verify
        else:
            raise Exception("[CA Sim]: *** fTPM Manufacturer CA simulation: The Silicon ID CSR public key is invalid!!")

        try:
            verify_func(self.sid_pub_key, _sig, self.sid_csr_cri.dump(), "sha256")
        except(errors.SignatureError):
            raise Exception("[CA Sim]: *** fTPM Manufacturer CA simulation: The Silicon CSR verification failed!!")

    def gen_sid_cert(self):
        # Subject name
        _sid_subject = self.sid_csr_cri['subject']
        # Public key info
        _sid_pk_info = self.sid_csr_cri['subject_pk_info']
        # Authority key identifier
        _ca_key_id = self.ca_cert.key_identifier_value

        # Extensions
        _extensions = self.sid_csr_cri['attributes'][0]['values'][0]
        _ext = []
        for i in range(len(_extensions)):
            _extn_value = _extensions[i]['extn_value'].native

            _ext.append({
                "extn_id" : _extensions[i]['extn_id'].native,
                "critical" : _extensions[i]['critical'].native,
                "extn_value": _extn_value
            })

        _ext.extend([
            {
                "extn_id" : "authority_key_identifier",
                "extn_value" : { "key_identifier" : _ca_key_id },
            }
        ])

        # Signature Algorithm
        if self.ca_priv_key.algorithm == 'rsa':
            _sig_algo = "sha256_rsa"
        elif self.ca_priv_key.algorithm == 'ec':
            _sig_algo = "sha256_ecdsa"
        else:
            raise Exception("Error: The CA private key is invalid.")

        _sid_tbs = x509.TbsCertificate(
            {
                "version" : "v3",
                "serial_number" : util.int_from_bytes(_sid_subject.sha1),
                "signature" : { "algorithm" : _sig_algo },
                "issuer" : self.ca_cert.subject,
                "validity" : {
                    "not_before" : x509.UTCTime(datetime.datetime(2023, 6, 1, 0, 0, tzinfo=datetime.timezone.utc)),
                    "not_after" : x509.GeneralizedTime(datetime.datetime(2050, 12, 31, 23, 59, 59, tzinfo=datetime.timezone.utc)),
                },
                "subject" : _sid_subject,
                "subject_public_key_info" : _sid_pk_info,
                "extensions" : _ext,
            }
        )

        # Signing the certificate
        if self.ca_priv_key.algorithm == 'rsa':
           sign_func = asymmetric.rsa_pkcs1v15_sign
        elif self.ca_priv_key.algorithm == 'ec':
            sign_func = asymmetric.ecdsa_sign

        _signature = sign_func(self.ca_priv_key, _sid_tbs.dump(), "sha256")

        self.sid_cert = x509.Certificate(
            {
                "tbs_certificate" : _sid_tbs,
                "signature_algorithm" : { "algorithm" : _sig_algo },
                "signature_value" : _signature,
            }
        )

        self.sid_cert_fout.write(self.sid_cert.dump())
        self.sid_cert_fout.close()

        return self.sid_cert_file

def main():
    parser = argparse.ArgumentParser(formatter_class=argparse.RawDescriptionHelpFormatter,
    description=textwrap.dedent('''
    fTPM Manufacturer CA Simulator for signing the Device Silicon ID CSR.
            * Input: The Silicon ID CSR.
            * Input: The CA Certificate.
            * Input: The CA private key.
            * Input: The output path to store the Silicon ID certificate.
            * Output: The Silicon ID certificate.
    '''))

    parser.add_argument('--sid_csr', type=str, required=True, help="The Silicon ID CSR hex string in DER format.")
    parser.add_argument('--ca_cert', type=str, required=True, help="The CA certificate file in PEM format.")
    parser.add_argument('--ca_private_key', type=str, required=True, help="The fTPM CA private key.")
    parser.add_argument('--sid_cert', type=str, required=True, help="The prefix of Silicon ID certificate file name. This outputs the certificate in DER format.")
    parser.add_argument('--out_path', type=str, required=True, help="The output folder of the result.")

    args = parser.parse_args()

    if not os.path.exists(args.out_path):
        os.makedirs(args.out_path)

    ftpm_ca = fTPM_CA_Sign_Silicon_ID_CSR(sid_csr = bytes.fromhex(args.sid_csr),
                                          ca_cert = open(args.ca_cert, "rb").read(),
                                          ca_priv_key = open(args.ca_private_key, "rb").read(),
                                          sid_cert_file_prefix = args.sid_cert,
                                          out_path = args.out_path)
    ftpm_ca.verify_sid_csr()

    output_sid_cert_file = ftpm_ca.gen_sid_cert()
    sys.stdout.write(output_sid_cert_file)

if __name__ == "__main__":
    main()
