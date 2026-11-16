# NVIDIA fTPM and helper PTA execution validation

[日本語](../ftpm-functional-validation.md) | English

[Decision 0003](decisions/0003-ftpm-provisioning-data.md) approves a QEMU-only test CA, Firmware ID key and certificates.
**fTPM execution and persistence were verified on Ubuntu 22.04 ARM64 without modifying NVIDIA's helper PTA, helper TA, or fTPM TA sources.**
See the [port design](ftpm-helper-port.md).

## Results

| Area | Result |
| --- | --- |
| Helper PTA | READY from PING_NS, SN, ECID, online provisioning mode and API version 2.0 verified |
| Certificate/CSR APIs | Retrieved and compared RSA/EC EK certificates, SID/Firmware ID certificates and RSA/EC CSRs |
| SIGN_EK_CSR | Verified the real PTA's signature with the Firmware ID certificate's public key using OpenSSL |
| Invalid parameters | SIGN_EK_CSR returned BAD_PARAMETERS |
| INJECT_EPS | Disabled as configured; NOT_IMPLEMENTED verified |
| TPM commands | GetCapability, 16-byte GetRandom, NV write/read and PCR extend passed |
| TPM keys | RSA signature verified with OpenSSL; seal/unseal passed |
| Cold-boot persistence | A separate QEMU process reused NV data, signing key and sealed data; PCR reset verified |
| Actual EK binding | Exported actual fTPM RSA/EC EK public keys, issued test-CA certificates, and matched PTA certificate public keys |
| EK certificate NV storage | Used NVIDIA provisioning-script attributes and standard indices 0x01c00002/0x01c0000a; content persisted across reboot |

The [machine-readable report](../results/ftpm-functional.json) and [actual test excerpts](../results/ftpm-functional-excerpt.txt) preserve the evidence.
Logs come from normal/secure UARTs. Each tested QEMU process ended through guest poweroff.
TF-A prints `ERROR: QEMU System Power off: with GPIO` on that poweroff path; it does not indicate test failure.

## Credentials and binding to actual EKs

1. Generate a test CA, Firmware ID/SID keys, seeds, and initial RSA/EC API fixtures once.
2. Initial fixture certificates/CSRs test API plumbing; they are not yet associated with the fTPM's EKs.
3. Run tpm2_createek inside the guest and export only actual EK public keys through the UART. Do not export EK private keys.
4. Issue test-CA certificates and Firmware-ID-signed CSRs for those public keys with bind-ftpm-test-ek.py.
5. Preserve seeds, Firmware ID key, SN, HUK and existing TPM NV state while updating certificate/CSR payloads.
6. In a new QEMU process, verify regenerated EKs match the public keys in the PTA's certificates and CSRs.

CSR signatures use Firmware ID, not the EK ([explanation](ek-csr-signing.md)). Verify using the Firmware ID public key rather than treating them as EK self-signed CSRs.
The generated certificates have no NVIDIA or manufacturer manufacturing trust.

## Reproduction

Requirements: QEMU/NVIDIA build environment, dtc, Python with cryptography, and Docker.
Prepare NVIDIA's kernel Image/matching fTPM module and build its OP-TEE client.
See the [boot instructions](ftpm-virt.md) and [port instructions](ftpm-helper-port.md).

```bash
# Configure CROSS_COMPILE, PATH and OPTEE_CLIENT_EXPORT first.
scripts/build-qemu.sh
scripts/build-ftpm-virt-firmware.sh
scripts/build-ftpm-helper-probe.sh
scripts/fetch-ftpm-virt-kernel.py
python3 scripts/generate-ftpm-test-provisioning.py work/ftpm-test-provisioning
python3 scripts/pack-ftpm-provisioning.py \
  work/ftpm-test-provisioning/manifest.json work/ftpm-virt/device-identity.bin \
  work/ftpm-virt/provisioning.bin
FTPM_FUNCTIONAL_PROFILE=1 KERNEL_MODULES_DIR="$PWD/work/ftpm-virt/modules" \
  scripts/build-ubuntu-rootfs.sh /path/to/optee/install/t234 work/ftpm-virt/rootfs.tar
python3 scripts/prepare-ftpm-test-rootfs.py work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
scripts/create-ftpm-virt-disk.sh
scripts/prepare-ftpm-virt-dtb.sh
# Check success markers and successful process exits.
scripts/run-ftpm-virt.sh first > work/ftpm-virt/first.log 2>&1
scripts/run-ftpm-virt.sh second > work/ftpm-virt/second.log 2>&1
scripts/run-ftpm-virt.sh export > work/ftpm-virt/export.log 2>&1
python3 scripts/bind-ftpm-test-ek.py \
  work/ftpm-test-provisioning work/ftpm-virt/export.log work/ftpm-bound-provisioning
python3 scripts/pack-ftpm-provisioning.py \
  work/ftpm-bound-provisioning/manifest.json work/ftpm-virt/device-identity.bin \
  work/ftpm-bound-provisioning/provisioning.bin
mv work/ftpm-virt/provisioning.bin work/ftpm-virt/provisioning-api-fixture.bin
install -m 0600 work/ftpm-bound-provisioning/provisioning.bin work/ftpm-virt/provisioning.bin
# QEMU must be stopped; update public fixtures and test programs only.
scripts/update-ftpm-test-disk.sh work/ftpm-bound-provisioning
scripts/prepare-ftpm-virt-dtb.sh
scripts/run-ftpm-virt.sh bound > work/ftpm-virt/bound.log 2>&1
scripts/run-ftpm-virt.sh bound > work/ftpm-virt/bound-reboot.log 2>&1
# Final rootfs service-health and fTPM check
scripts/run-ftpm-virt.sh bound > work/ftpm-virt/accounts-fixed.log 2>&1
python3 scripts/check-ftpm-functional-results.py \
  work/ftpm-virt work/ftpm-bound-provisioning work/ftpm-virt/functional-result.json
```

Run the first phase only on a fresh disk. Never regenerate existing keys or reset NV state merely to obtain passing tests.
Keep CA/Firmware ID private keys, seeds, device identity, provisioning images and disks in ignored work/.
Only public certificates, CSRs, verification inputs and test client and TA programs enter the guest.
The relay TA is a test instrument calling the real PTA from user mode, not a replacement PTA.

## Rootfs fixes

- Remove Docker export's /.dockerenv when creating the disk so systemd recognizes a QEMU guest.
- Normalize overlay/client directory modes to 0755 rather than accidentally copying 0700 parent directories.
- Override PRoot -R's host passwd/group bindings with explicit guest-file bindings, avoiding inconsistent guest passwd/group and shadow/gshadow databases.
- Replay the journal with fsck before offline test-disk edits and verify filesystem consistency afterward.

Small Docker VFS environments may require build-cache cleanup.
With libfdt and other runtime libraries on the host, FTPM_NATIVE_QEMU=1 launches the same QEMU binary directly.
work/native-libs is an optional local library directory; Docker remains the default reproduction path.

## Limits

This does not provide physical SE/eFuse tamper resistance, manufacturer certificate trust, or REE filesystem rollback protection.
Measured Boot and INJECT_EPS remain disabled. These tests do not exhaust every TPM command, OS service, or physical-device performance/timing property.
They establish software fTPM/helper PTA functionality and persistence for the listed operations.

With the corrected rootfs accounts, systemd-sysusers/systemd-resolved start successfully and all B2 checks pass again on the preserved TPM state. Native execution requires write access to the disk image.
