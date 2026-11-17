# fTPM and EK certificate test guide

[日本語](../test-guide.md) | English

Use the B2 environment prepared with the [build and installation guide](build-install.md), starting with first. These tests use a QEMU-only test CA and provide no NVIDIA manufacturing trust.
The older [functional validation procedure](ftpm-functional-validation.md) covers initial assembly as well; use build-install.md for current assembly and this guide for all test execution.

## Prerequisites and current progress

Run from the repository root with the same Python venv:

```bash
cd /home/ishikawa/work/qemu-jetson
source work/venv/bin/activate
set -o pipefail
```

Adjust cd if cloned elsewhere. Enable pipefail in every shell using tee.
Check each step before continuing. QEMU exit status zero alone is insufficient: require PASS markers and no FAIL markers.
On failure or timeout (usually status 124), stop and preserve normal and secure logs.

| Stage | Purpose | Confirmed in this conversation |
| --- | --- | --- |
| first | Initial NV/PCR/signing/seal tests on a new disk | Existing disk has completion marker; do not rerun |
| second | NV/key/sealed-data persistence and PCR reset | PASS in supplied log |
| export | Obtain actual RSA/ECC EK public keys | PASS in supplied export.log |
| bind / pack | Issue actual-EK certificates with the existing CA and pack data | Result not yet confirmed |
| Apply / bound | Match actual EKs to PTA certificates and verify standard NV indices | Not confirmed |
| bound reboot | Verify EK/certificate NV and existing TPM-state persistence | Not confirmed |

If second and export have passed, continue at step 3 without rerunning them.
If the bound output directory or provisioning backup already exists, inspect the completed stage rather than deleting or regenerating it.
Preserve keys, device-identity.bin, the CA, rootfs.ext4, guest first.done and TPM NV state.
Run first once on a new disk and skip it when completed. Never run multiple QEMU processes against the disk.

## 0. first: initial tests on a new disk

Run only on a newly installed disk. If first already completed on the existing disk, continue at step 1.

```bash
bash scripts/run-ftpm-virt.sh first 2>&1 | tee work/ftpm-virt/first.log
```

Require `FTPM_TEST: PASS phase=first`. This runs PTA certificate/CSR/signature checks, TPM capabilities/random, NV write/read, PCR extend, RSA signatures and seal/unseal, then powers off automatically.
The test creates TPM state for later persistence checks. An existing first.done marker causes a repeated first run to be rejected.
With the current script, FAIL line=22 indicates failure of the completion-marker absence check. Inspect prior progress; do not delete the marker.

## 1. second: persistence tests

```bash
bash scripts/run-ftpm-virt.sh second 2>&1 | tee work/ftpm-virt/second.log
```

Require `FTPM_TEST: PASS phase=second`. Tests cover NV, signing-key and sealed-data persistence, PCR reset, RSA signatures, seal/unseal and PTA APIs.
If second already passed but its log was not saved, it can be rerun for evidence; do not substitute first.

## 2. export: actual EK public keys

```bash
bash scripts/run-ftpm-virt.sh export 2>&1 | tee work/ftpm-virt/export.log
```

Require both `EK_EXPORT: rsa ...` and `EK_EXPORT: ecc ...`, then `EK_TEST: PASS`.
No EK private key is exported. Preserve this log as input to certificate issuance.

## 3. bind: issue certificates using the existing CA

```bash
python3 scripts/bind-ftpm-test-ek.py \
  work/ftpm-test-provisioning \
  work/ftpm-virt/export.log \
  work/ftpm-bound-provisioning
```

Require `Test-only certificates issued for actual fTPM RSA/EC EK public keys; seeds and device keys unchanged.`
The new work/ftpm-bound-provisioning directory contains actual RSA/ECC EK certificates and Firmware-ID-signed CSRs, using existing credentials.
An existing output directory is rejected. Inspect prior progress rather than deleting it to reissue certificates.
Never upload or push CA or Firmware ID private keys.

## 4. pack: prepare PTA provisioning data

```bash
python3 scripts/pack-ftpm-provisioning.py \
  work/ftpm-bound-provisioning/manifest.json \
  work/ftpm-virt/device-identity.bin \
  work/ftpm-bound-provisioning/provisioning.bin
```

Require normal completion and creation of the final output file. Existing output is not overwritten.
This does not yet switch the active provisioning.bin.

## 5. Stop QEMU and apply the data

```bash
pgrep -af '[q]emu-system-aarch64'
```

Ensure no QEMU has this disk open. Preserve the active provisioning image before switching:

```bash
(
  set -e
  test ! -e work/ftpm-virt/provisioning-api-fixture.bin
  cp -p work/ftpm-virt/provisioning.bin \
    work/ftpm-virt/provisioning-api-fixture.bin
  install -m 0600 work/ftpm-bound-provisioning/provisioning.bin \
    work/ftpm-virt/provisioning.bin
)
```

If the backup already exists, stop and inspect prior progress; do not overwrite it.
Seeds and device identity remain unchanged; only provisioning content such as certificates is switched.
Apply public certificates, CSRs and test programs to the stopped existing disk:

```bash
bash scripts/update-ftpm-test-disk.sh work/ftpm-bound-provisioning
```

## 6. Regenerate DTBs and run bound

```bash
bash scripts/prepare-ftpm-virt-dtb.sh
bash scripts/run-ftpm-virt.sh bound 2>&1 | tee work/ftpm-virt/bound.log
```

Require all markers below and no FAIL markers:

```text
PTA_TEST: certificates/CSR match, CA chains, Firmware ID signature PASS
EK_TEST: actual RSA/EC EK keys match PTA certificates PASS
EK_TEST: standard RSA/EC EK certificate NV indices PASS
FTPM_TEST: PASS phase=second
EK_TEST: PASS
```

Standard certificate NV indices are 0x01c00002 for RSA and 0x01c0000a for ECC.
The guest provisions absent indices, reads the contents back and compares them to PTA certificates.
Existing indices are compared without overwriting them. Stop on mismatches; do not delete indices to bypass errors.
The bound phase also runs second to verify the existing TPM state.

## 7. Reboot bound to verify persistence

After the preceding PASS and QEMU exit, retain the same disk, keys and provisioning:

```bash
bash scripts/run-ftpm-virt.sh bound 2>&1 | tee work/ftpm-virt/bound-reboot.log
```

Require all step 6 markers again. RSA/ECC EK_EXPORT values must also match export.log.
This verifies actual EK/certificate matching, standard certificate NV persistence and prior TPM-state persistence across boots.

## Logs and failures

Normal logs are saved by tee. Secure logs are work/ftpm-virt/secure-<phase>-native.log.
Repeating a phase overwrites its secure log; preserve needed evidence under another name first.
After PASS, `ERROR: QEMU System Power off: with GPIO.` is the firmware's poweroff message.
That message, a login prompt, or QEMU exit alone is not proof of success.

The older check-ftpm-functional-results.py requires all six logs: first, second, export, bound, bound-reboot and accounts-fixed.
It is not mandatory for this continuation guide: absent first.log or accounts-fixed.log would cause it to fail.
Do not copy or edit logs to satisfy the checker. Gather the full evidence from the [older complete procedure](ftpm-functional-validation.md) if needed.
These tests do not cover every TPM command, physical eFuse tamper resistance or rollback protection.

## Confirmation after the translation table increase

On 2026-11-17 (Japan time), the user reported all tests in this guide passed. The progress table records the state when the guide was created.
See the [build guide](build-install.md#op-tee-translation-table-change-and-the-original-failure) for the 8-to-32 table change and original panic.

## Related evidence and hardware differences

See [hardware differences](hardware-qemu-differences.md) and [final evidence](final-test-evidence.md).

See [interactive runtime, SSH, sharing and debugging](runtime-guide.md). The launcher now defaults to normal boot and four CPUs; select tests explicitly. That guide includes the old-firmware upgrade steps.
