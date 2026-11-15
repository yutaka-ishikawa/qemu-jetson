# QEMU Jetson OP-TEE / fTPM implementation procedure

[日本語](../implementation-plan.md) | English

Created November 16, 2026 (Japan time). This is a procedure written before implementation.
At planning time, completed work consisted of an unmodified NVIDIA OP-TEE / fTPM build and dependency investigation.
This page records the pre-implementation plan. Stage A was subsequently implemented and tested; see the [results](t234-stage-a.md).

## 1. Baselines and boundaries

- Follow the [design](qemu-boot-design.md).
- NVIDIA baseline: Jetson Linux R36.5.2 and existing T234 build artifacts.
- QEMU baseline: **11.1.3, the latest stable release at the time of investigation**.
- Official Git: https://gitlab.com/qemu-project/qemu.git
- Tag: `v11.1.3`.
- Commit: `005c61c0ef6f6ae615283440b4bb7be51b2c6ddd`.
- Official archive: https://download.qemu.org/qemu-11.1.3.tar.xz
- Official release information: https://www.qemu.org/download/

The official page also lists 11.2.0-rc0 (November 11, 2026).
Because it is a release candidate, this plan selects 11.1.3 (October 28, 2026) as the latest stable version.
The tag's resolved commit was checked using ls-remote against the official Git repository.
If an unreleased version becomes necessary, explicitly revise this baseline.

Initially preserve NVIDIA's OP-TEE / fTPM sources unchanged.
Develop the dedicated QEMU machine and test EL3 firmware in this repository.
Unmodified execution of NVIDIA ATF or the entire MB2 is outside initial implementation.
Start with TCG and one CPU. CUDA/GPU emulation is excluded.

## 2. Planned repository layout

```text
docs/                       Design, build, execution, and validation records
manifests/                  Download URLs, pinned commits, input hashes
scripts/                    Fetch, build, run, and artifact checks
qemu/                       Official QEMU sources, edited directly
optee/                      NVIDIA OP-TEE / fTPM sources
kernel/                     NVIDIA Linux kernel sources
firmware/                   Project-owned test EL3 firmware
configs/                    VM, DT generation, and test Fuse configuration
tests/                      MMIO model, boot, and TPM tests
```

This is a planned layout, not a claim that these directories already exist.
Bundle QEMU sources in this repository and edit qemu/ directly. See the current [source layout](source-layout.md).
Keep NVIDIA distributions, original third-party trees, large build outputs, and virtual-device secret state out of Git.
Preserve licenses and copyright notices for each imported file.

The fresh-clone procedure below is the earlier plan, superseded by bundled sources. Use the build procedure in [source-layout.md](source-layout.md).

## 3. Pin QEMU and establish a baseline

1. Record the official URL, tag, and commit in manifests.
2. Fetch the official tag into the working directory.
3. Verify HEAD matches the pinned commit.
4. Check build dependencies using official documentation and configure.
5. Build unmodified QEMU for AArch64 system emulation.
6. Check its version, available CPUs, and secure=on machine configuration.

Planned fetch/build commands, **not yet executed**:

```bash
git clone --depth 1 --branch v11.1.3 https://gitlab.com/qemu-project/qemu.git work/qemu
git -C work/qemu rev-parse HEAD
mkdir -p work/qemu-build
cd work/qemu-build
../qemu/configure --target-list=aarch64-softmmu --disable-werror
ninja
./qemu-system-aarch64 --version
./qemu-system-aarch64 -machine help
./qemu-system-aarch64 -cpu help
```

Verify configure options and dependencies on the actual host before recording tested execution instructions.
Do not confuse these planned commands with a completed procedure.

## 4. Stage A: first OP-TEE log

### 4.1 Dedicated machine

Add a partial development model provisionally named `jetson-t234-dev`.
Reuse existing Arm CPU, address space, RAM, timer, and other QEMU components while avoiding standard virt's Flash conflicts.

- Select a CPU with Secure EL1 and EL3 and verify PAUTH support.
- Verify that CPU MPIDR agrees with OP-TEE core-position calculations.
- Place Secure RAM using the official build baseline: TZDRAM start `0x80000000`, size `0x03fc0000`.
- Produce a layout for EL3 firmware, OP-TEE, DT, and non-secure RAM and check for overlaps.
- Test protection of Secure RAM from non-secure accesses.
- Log or trace unimplemented MMIO, exceptions, and stopping locations.

### 4.2 TCU model

Add a minimal Combined UART model at `0x0c198000`.
Match the public driver's byte-count, flush, and busy behavior.
Send output to a character backend and define reset state and access widths.
Implement the transmit behavior needed for observation and document missing features.

Unit-test character output, busy clearing, flush, and behavior after reset.

### 4.3 Boot firmware

Add small project-owned EL3 boot code and build it with NVIDIA's toolchain.
Configure required system registers and exception vectors, then enter Secure EL1.
Follow the design's OPTEED contract for initial OP-TEE arguments.
Do not assume QEMU's generic loader alone is sufficient.

- Inspect ELF load segments and tee-raw.bin generation format; load at the correct address and entry point.
- Provide external DT through x2 and check capacity against the build's maximum DT size.
- Record ESR, ELR, FAR, and related exception information, then stop on exceptions.
- If OP-TEE reaches the initialization-complete SMC, do not silently continue with it unhandled.

### 4.4 Execution and acceptance

Have the launch script record input hashes, CPU, machine, memory, and firmware versions.
Run with a timeout and preserve TCU logs and unimplemented-access records.

Pass when the same unmodified OP-TEE emits logs and the next stopping cause can be identified.
Do not count a timeout as success. TPM operation or complete OP-TEE initialization is not required at this stage.

## 5. Stage B: initialization completion

Use Stage A observations to add devices in the order actually needed.

1. Add read-only Fuse access for ECID/SN, BSI, and security mode.
2. Test SN byte order as used in EKB comparisons.
3. Implement required SE commands, key slots, and completion/error reporting from public specifications.
4. Supply randomness from host randomness in response to guest requests; do not return constants as random values.
5. Place EKB, seeds, boot-mode, event logs, and other required inputs in DT and Secure RAM.
6. Provide required SMC handling and verify OP-TEE ENTRY_DONE.

CCC is prebuilt; public C sources do not establish the complete SE specification.
Investigate unknowns using public specifications and observed accesses rather than relying on disassembly.
Dummy success responses for unimplemented SE behavior do not satisfy Stage B.
Check initcall failures, panics, unimplemented MMIO, randomness, and cryptography before accepting the stage.

## 6. Stages C–E: Linux and fTPM

- **C:** Configure a Secure Monitor matching the QEMU layout. Evaluate TF-A OPTEED or equivalent; verify the Linux OP-TEE driver, tee-supplicant, TA invocation, and REE FS persistence.
- **D:** Provide Linux's fTPM TEE driver and tpm2-tools. Exercise GetCapability, PCRs, NV, key generation, seal/unseal, and reuse after reboot.
- **E:** Keep Fuse, seeds, EKB, storage keys, EKs, and certificates consistent per virtual device. Define and test TPM clear, different devices, cloning, and snapshots.

Passing Stage D alone does not demonstrate hardware-equivalent device attestation or Fuse behavior.
When real hardware becomes available, compare using the same L4T release and commands.

## 7. Changes and progress records

At each stage, document and push implementation changes, build instructions, execution commands, input hashes, test results, and missing features.
If NVIDIA source changes become necessary, identify the location and reason, estimate the QEMU-only alternative, and update the design.

Do not automatically upgrade QEMU. When a new stable release appears, port patches and pass all tests for completed stages before updating the baseline commit.

The selected userland is Ubuntu 22.04 ARM64. See the [rootfs procedure](ubuntu-rootfs.md).

The initial Stage B Fuse implementation and tests are recorded in [t234-fuse.md](t234-fuse.md). Stage B is not complete; SE0 is next.
