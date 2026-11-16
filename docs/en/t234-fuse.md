# Read-only T234 Fuse model

[日本語](../t234-fuse.md) | English

November 16, 2026 (Japan time): added the Fuse model and verified that unmodified OP-TEE passes the Fuse read that aborted in Stage A.
The current stop is during SE0 initialization; complete OP-TEE initialization and fTPM operation remain unverified.
Machine-readable results: [t234-fuse.json](../results/t234-fuse.json).

## Model scope

Select an explicit host test image using the `fuse-image` option of `jetson-t234-dev`.
Without it, Fuse remains unmapped, preserving the [Stage A](t234-stage-a.md) configuration.
The image is loaded once at startup. Guest writes and QMP property changes after initialization are rejected.
Values survive QMP system_reset and are identical in separate processes using the same image contents.
Copying an image creates a virtual device with the same identity; explicitly supply different contents for a different identity.

- MMIO: `0x03810000 / 0x600`, secure-only.
- Access: aligned 4-byte little-endian transactions.
- Supported offsets: `0x1a0, 0x200, 0x204, 0x208, 0x20c, 0x210, 0x214, 0x218, 0x220, 0x268, 0x29c, 0x408, 0x40c`.
- Unsupported reads return a decode error; writes return an access error, causing guest aborts.
- QEMU trace events expose successful reads and rejected writes.

This models selected identifiers and configuration values, not the full Tegra Fuse Controller.
Programming, OTP bit transitions, secret-key fuses, KDK0, and SE key slots are unimplemented.
Setting BSI/security-mode values does not implement Secure Boot or hardware key protection.
Migration and snapshot state compatibility remain unverified.

## Input format

Images are exactly 1536 bytes, with 32-bit little-endian values at register offsets and zeros in unsupported locations.
This is not NVIDIA's manufacturing fuseblob format.
Invalid size and nonzero data in unsupported locations are rejected at startup.

Public synthetic fixtures are `configs/fuse/test-device-a.json` and `test-device-b.json`.
They contain no real-device secrets. Generate images with:

```bash
scripts/make-t234-fuse-image.py configs/fuse/test-device-a.json work/fuse/device-a.bin
scripts/make-t234-fuse-image.py configs/fuse/test-device-b.json work/fuse/device-b.bin
```

The generator checks register completeness, 32-bit range, and base-36 lot digits, and refuses to overwrite different existing images.
Editing the host file after startup does not change values in the running VM.
Preserve the input contents to retain identity across restarts.

## Validation using NVIDIA functions

QEMU does not reimplement the identity conversion logic.
Test firmware directly calls `fuse_generate_ecid()` and `fuse_generate_sn()` in the existing unmodified OP-TEE binary,
using addresses extracted from the matching ELF symbols.
This tests MMIO interoperability with those two functions, not complete OP-TEE initialization.

```bash
export CROSS_COMPILE_AARCH64=/path/to/toolchain/bin/aarch64-buildroot-linux-gnu-
export DTC=/path/to/dtc
export OPTEE_ELF=work/optee-baseline/tee.elf
scripts/build-t234-firmware.sh
scripts/build-qemu.sh

  python3 scripts/check-t234-fuse.py work/qemu-build/qemu-system-aarch64 \
  --optee work/optee-baseline/tee-raw.bin
```

Use ELF and raw images from the same unmodified build. Input hashes follow the [Stage A procedure](t234-stage-a.md).
For rebuilt artifacts, explicitly pass the recorded hash with `--optee-sha256`.
fuse-probe/fuse-reset are generated when `OPTEE_ELF` is set; always set it when building for these tests.

Verified values:

| Field | Device A | Device B |
| --- | --- | --- |
| SN (10 bytes) | `01020123456789abcdef` | `03041032547698badcfe` |
| ECID64 | `82541b1d454a0255` | `82541b1d454e0456` |
| ECID128 (32-bit word order) | `d280956a 1448d159 540420c4 00000002` | `138115ab 148d159e 540420c4 00000002` |

The first two SN bytes encode ODM_INFO in big-endian order; remaining bytes are the little-endian byte sequences of ODMID0/1.
Both images matched their expected identities in two separate process launches each.
Also verified unchanged values after rejected writes, aborts on unsupported reads, rejection of non-secure EL1 access,
invalid-image rejection, identity retention across QMP reset, and rejection of runtime fuse-image changes.
Reset testing also led to wiring the minimal machine's CPU into system_reset.

## Next OP-TEE stop

```bash
  python3 scripts/check-t234-boot.py work/qemu-build/qemu-system-aarch64 \
  --optee work/optee-baseline/tee-raw.bin \
  --fuse-image work/fuse/device-a.bin --output-dir work/t234-fuse-boot-results
```

Using the same OP-TEE SHA-256, execution passed the earlier Fuse abort and produced:

```text
Core data-abort at address 0x86550014
esr 0x96000010
elr 0000000080003cf8
```

The ELF symbol is `tegra_se_ccc_configure_se0`, called by public source `tegra_se_map_device.c:45`.
From the DT and call argument base, the access is inferred to correspond to physical `0x03b50014`.
The CCC library was not disassembled. The SE protocol remains undetermined; no fabricated successful response is provided.

StMM DT initialization failure and the missing TPM event log also remain unresolved.
Logs and JSON are under `work/t234-fuse-results/`; OP-TEE diagnostics are under `work/t234-fuse-boot-results/`.
Next, inspect public SE0 specifications and accesses to define the required behavior.

Additional checks: omitting the Fuse image reproduced the Stage A Fuse abort. Running the NVIDIA-function probe with tracing also recorded 12 successful reads.

Enable read tracing with QEMU arguments `-trace enable=jetson_t234_fuse_read -D work/fuse.trace.log`.
