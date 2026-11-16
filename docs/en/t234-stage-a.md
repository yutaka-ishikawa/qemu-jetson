# Stage A: first OP-TEE log

[日本語](../t234-stage-a.md) | English

November 16, 2026 (Japan time): **unmodified NVIDIA OP-TEE produced its first logs on the dedicated QEMU machine.**
This does not establish completed OP-TEE initialization, Linux boot, or fTPM functionality.
Machine-readable results: [t234-stage-a.json](../results/t234-stage-a.json).

This is the Stage A record; see the [subsequent Fuse implementation](t234-fuse.md). Omitting a Fuse image still selects this configuration.

## Implementation

- Added `jetson-t234-dev` in QEMU `hw/arm/jetson-t234-dev.c`.
- Restricted to TCG, the `max` CPU, one core, and 128 MiB non-secure RAM.
- Placed ROM and RAM in a secure-only address space, separate from non-secure accesses.
- Added a transmit TCU model at `0x0c198000`, handling 1–3 bytes, flush, and synchronous busy clearing.
- Added EL3 initialization, entry into Secure EL1, exception diagnostics, and test termination in `firmware/t234-boot/`.
- NVIDIA OP-TEE / fTPM sources are unchanged.

TCU is a minimal transmit-only model. Receive, interrupts, the real remote processor, and timed backpressure are not implemented.
Fuse, SE, RNG1, GIC, QSPI, Scratch, and the hardware boot chain are also unimplemented.
Migration and snapshot compatibility have not been verified.

## Memory and input contract

| Region | Placement | Purpose |
| --- | --- | --- |
| Secure ROM | `0x00000000 / 0x10000` | EL3 test firmware |
| Secure RAM | `0x80000000 / 0x04000000` | OP-TEE and reserved test area |
| OP-TEE range | `0x80000000 / 0x03fc0000` | Official T234 TZDRAM configuration |
| DT | `0x83ff0000 / maximum 0x10000` | OP-TEE DT input |
| EL3 stack | Top at `0x83fe0000` | Outside the OP-TEE range |
| Non-secure RAM | `0x90000000 / 0x08000000` | Future non-secure software; currently isolation testing |

Load `-bios` into ROM, the raw `-kernel` image into the OP-TEE range, and `-dtb` into the DT area.
This is a machine-specific contract, not standard Linux-style `-kernel` boot.
EL3 sets x0=0, x1=`0x83fc0000`, x2=`0x83ff0000`, x3=0 before entering Secure EL1.
ROM and Secure RAM are loaded through QEMU's secure address space.

## Reproduce

Provide NVIDIA's specified AArch64 toolchain, dtc, and [native host tools](native-host.md).

```bash
export CROSS_COMPILE_AARCH64=/path/to/toolchain/bin/aarch64-buildroot-linux-gnu-
# Only needed when dtc is not on PATH
export DTC=/path/to/dtc
scripts/build-t234-firmware.sh
scripts/build-qemu.sh
```

This generates boot, selftest, and isolation ELF/raw images and a DTB under `work/t234-firmware/`.
Place the existing unmodified `tee-raw.bin` at `work/optee-baseline/tee-raw.bin`.
A fresh clone does not include that artifact; see the [OP-TEE build record](r36.5.2-build.md).

```bash
  python3 scripts/check-t234-boot.py \
  work/qemu-build/qemu-system-aarch64 \
  --optee work/optee-baseline/tee-raw.bin
```

Omit `--optee` to run only the harness tests.
By default, the OP-TEE input SHA-256 must match the existing build:
`96bcd44d8a4ceee39fa8a4ffd97b5bc0e193c6b3d5fc6cdc2208b806aeb9beb9`.
Rebuilds may differ because of timestamps and other metadata; explicitly provide the hash recorded for your rebuild using
`--optee-sha256 <hash>`. A matching hash alone does not prove source provenance.

Test firmware uses QEMU semihosting for termination. This is a development mechanism, not an implementation of hardware OPTEED or a production Secure Monitor.
Unknown EL3 exceptions/SMCs print registers and stop; they do not fabricate successful OP-TEE service responses.

## Verified results

1. EL3 → Secure EL1 → SMC → EL3 produced `BOOT: SELFTEST PASS` and exit code 0.
2. Verified single-character output, the three-byte `ABC` packet, busy clearing, and flush.
3. A non-secure EL1 read of `0x80000000` caused an abort with ESR_EL1=`0x96000010`, FAR_EL1=`0x80000000`; `BOOT: NS isolation PASS` and exit code 0 were observed.
4. Unsupported 256 MiB RAM and two-core configurations were rejected by machine constraints.
5. Unmodified OP-TEE emitted:

```text
BOOT: EL3 entry
I/TC: OP-TEE version: 4.2 ... aarch64
I/TC: Primary CPU initializing
E/TC:00 00 Core data-abort at address 0x86210200
E/TC:00 00  esr 0x96000010
```

The fault ELR is `0x8002e850`. addr2line against the matching ELF resolves it to
`io_read32()` inside `fuse_generate_ecid()`, `tegra_driver_fuse.c:30`.
Using the DT and driver mapping, this corresponds to reading physical `0x03810200`, `FUSE_OPT_VENDOR_CODE_0`.
With no Fuse model, the data abort repeats.

Also observed a missing TPM event-log node message and a failed `stmm_sp_parse_dt()` initcall with the minimal DT.
These remain unresolved; initialization is not clean.

After observing the first data abort, the script requests QEMU termination to bound log growth.
`stop_reason=observed_data_abort` does not mean normal boot or a successful timeout.
Logs, commands, and termination reasons are stored under `work/t234-results/`, with
`initialization_verified=false` and `tpm_verified=false`.

## Next stage

Add a read-only Fuse model and verify identifiers, SN values, and byte order.
Then investigate SE/randomness and unresolved DT inputs. Linux/fTPM execution testing follows those steps.
