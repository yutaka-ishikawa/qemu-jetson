# SIGN_EK_CSR signing key versus the EK

[日本語](../ek-csr-signing.md) | English

NVIDIA's helper PTA `SIGN_EK_CSR` does not sign with the EK itself.
It signs the digest of an EK certificate signing request (CSR) with a Firmware ID private key.
It also differs from the manufacturer's CA signature on an EK certificate.

| Operation | Signed content | Private key | Meaning |
| --- | --- | --- | --- |
| Helper PTA `SIGN_EK_CSR` | 32-byte SHA-256 digest of EK CSR content | Firmware ID EC P-256 private key | Signs the EK certificate request using possession of the Firmware ID key |
| EK certificate issuance | To-be-signed certificate content including EK public key | Manufacturer or test CA private key | CA certifies the EK public key and certificate attributes |
| Ordinary TPM signing, such as `TPM2_Sign` | Digest specified by the command | Selected TPM signing object's private key | Signature by that TPM signing key |

An EK using a typical TCG EK template is a restricted decrypt key, not an ordinary signing key.
TPM possession can instead be checked using an AK and mechanisms such as MakeCredential/ActivateCredential.
These general TPM mechanisms are distinct from NVIDIA's CSR-signing path.

## Confirmed NVIDIA implementation

1. The helper TA hashes the CSR's CertificateRequestInfo content.
2. It calls `FTPM_HELPER_PTA_CMD_SIGN_EK_CSR` on the helper PTA.
3. The PTA's `sign_ek_csr_digest()` requires a 32-byte SHA-256 digest and an 80-byte output buffer.
4. It calls `crypto_acipher_ecc_sign(TEE_ALG_ECDSA_SHA256, &ftpm_property.fw_id_key, ...)`. It does not pass an EK.
5. The helper TA converts the returned r/s signature to ASN.1 form and updates the CSR signature.

The PTA allocates the Firmware ID key as NIST P-256. Its private scalar is loaded from the 32 bytes referenced by
`nvidia,ftpm-firmware-id-privkey` in the DT used by the secure side.
The matching certificate is obtained through `nvidia,ftpm-firmware-id-certificate`.
`SIGN_EK_CSR` neither derives this private key from the TPM's EK nor calls TPM2_Sign.

Verify this signature with the Firmware ID public key, not the EK public key inside the CSR.
Trust in the Firmware ID certificate issuer and proof that the TPM actually possesses the requested EK require separate validation.
This API alone does not establish EK possession or physical-device hardware protection.

## QEMU option B2

[Decision 0002](decisions/0002-ftpm-helper-pta.md) selects the complete NVIDIA helper PTA.
Document the origin and validation scope of QEMU provisioning data, including the Firmware ID key and certificate.
Treat the EK, Firmware ID key, and CA key as distinct key roles.

## Sources

- [Helper PTA signing and Firmware ID key loading](../../optee/optee/optee_os/core/pta/tegra/jetson_ftpm_helper_pta.c)
- [Helper TA CSR hashing, signing call and ASN.1 conversion](../../optee/optee/samples/ftpm-helper/ta/ftpm_helper_ta.c)
- [PTA command definitions](../../optee/optee/optee_os/lib/libutee/include/pta_jetson_ftpm_helper.h)
