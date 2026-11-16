# B2: porting the complete NVIDIA helper PTA

[日本語](../ftpm-helper-port.md) | English

The user selected B2 in [decision 0002](decisions/0002-ftpm-helper-pta.md).
Integrate NVIDIA's unchanged `jetson_ftpm_helper_pta.c`, helper TA, and fTPM TA with virtual platform providers.
See also [CSR signing versus the EK](ek-csr-signing.md).

## Implementation boundary

- `CFG_QEMU_JETSON_FTPM=y` enables NVIDIA's helper PTA and REE state tracking.
- Exclude the vexpress EPS property implementation and use the original NVIDIA PTA's EPS implementation.
- `qemu_ftpm_platform.c` provides SN, 64-bit ECID and fTPM EKB-property APIs.
- Embed the helper TA and fTPM TA as Early TAs.
- QEMU loads `provisioning-file` into 64 KiB of secure-only RAM at `0x0c400000`.
  Use RAM so the PTA can erase seed/Firmware ID handoff data after copying it.
  Each reset restores the same initially loaded contents; the host file is not modified.

This does not port Tegra's encrypted EKB container or SE driver.
It supplies data consumed by the unchanged helper PTA through the virtual platform.
Guest Linux access is restricted; the host administrator is not excluded.
An NVIDIA encrypted EKB file cannot be passed directly as `provisioning-file`.

The SN is the first ten bytes of the existing JFTPM001 device ID; the next eight bytes form the 64-bit ECID.
These are functional-profile conventions, not T234 physical Fuse bit-field conversion.
The HUK still uses the existing device identity file, but B2's EPS uses NVIDIA's original HKDF path with seeds and SN.
This differs from the earlier B prototype's EPS derivation; do not assume migration of existing TPM state.

## Handoff format

`JFPRV001` is project-specific and little-endian.
It contains an eight-byte magic, 32-bit total size, 32-bit entry count, and space for sixteen directory entries.
Each entry contains four 32-bit fields: ID, offset, length, and reserved (zero).
Payload starts at offset 272 or later. Reject overlap, out-of-bounds entries, and invalid lengths.

| Manifest field | ID | Content |
| --- | --- | --- |
| `ftpm_seed` | 1 | 32-byte fTPM seed |
| `firmware_id_key` | 2 | 32-byte EC P-256 private scalar |
| `firmware_id_cert` | 3 | Matching Firmware ID certificate, DER |
| `sn` | 91 | Ten bytes; filled from device ID when omitted |
| `eps_seed` | 92 | 32-byte EPS seed |
| `rsa_ek_cert` / `ec_ek_cert` | 93 / 94 | EK certificates, DER |
| `sid_cert` | 95 | SID certificate, DER |
| `rsa_ek_csr` / `ec_ek_csr` | 96 / 97 | EK CSRs, DER |

The original PTA chooses offline mode when both EK certificates exist, or online mode when the SID certificate and both EK CSRs exist.
If both sets exist, online mode takes precedence because of the original PTA's execution order.
Keep secret data, manifests and input files under ignored `work/`, outside Git.

The manifest is JSON mapping field names to input-file paths relative to the manifest.
`pack-ftpm-provisioning.py` reads existing keys without generating them and refuses to overwrite output.
It checks SN/device-ID consistency, matching Firmware ID key/certificate public keys, formats and lengths.
Certificate-chain trust and correspondence between EK data and the actual fTPM key require separate validation.

```bash
python3 scripts/check-ftpm-provisioning.py
# Use a Python environment with cryptography installed.
python3 scripts/pack-ftpm-provisioning.py \
  work/provisioning/manifest.json work/ftpm-virt/device-identity.bin \
  work/ftpm-virt/provisioning.bin
scripts/prepare-ftpm-virt-dtb.sh
```

The DT describes `nvidia,ftpm-contents` and handoff addresses for the seed, Firmware ID key and certificate.
It contains no secret bytes. The original PTA's DT handling copies and erases the handoff data.

## Validation status

The OP-TEE build including NVIDIA's helper PTA, helper TA, and fTPM TA succeeded.
Nine handoff-format bounds tests passed; these are not cryptographic key/certificate execution tests.
The [source of key/certificate test data](decisions/0003-ftpm-provisioning-data.md) awaits the user.
Successful signing, all PTA APIs, TPM commands, and persistence are not yet claimed.
`INJECT_EPS` remains disabled by its original build option; an API definition does not imply it is enabled.

The [machine-readable result](../results/ftpm-helper-b2.json) and [actual boot excerpt](../results/ftpm-helper-b2-boot-excerpt.txt) are preserved.
OP-TEE with the full PTA reaches Linux. This diagnostic boot intentionally has no provisioning data or root disk; missing-provisioning diagnostics and a root-device wait are expected.
QEMU build and the existing virt regression check passed. Provisioned execution and reset-time data restoration remain unverified.
