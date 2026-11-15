# Goals and staged approach

[日本語](../requirements.md) | English

## Agreed requirements

- Target NVIDIA Jetson Orin Nano (Tegra234).
- Run code compiled using NVIDIA-provided development tools.
- Target NVIDIA-provided OP-TEE and fTPM TA.
- Minimize changes to NVIDIA sources for QEMU support.
- Running CUDA GPU code is not required.
- Provide fTPM functionality equivalent to real hardware from the user's perspective; detailed comparison criteria remain to be defined.
- Manage source code, build procedures, and investigation results in this repository.
- Work step by step, checking the result of each stage.

## Initial status

At the time these requirements were recorded, JetPack / Jetson Linux (L4T) had not been selected and the build/runtime environment was not prepared.
Execution of NVIDIA's OP-TEE / fTPM on QEMU had not been verified.
For subsequent progress, see the [build record](r36.5.2-build.md) and [implementation procedure](implementation-plan.md).

## Step 1: select a target release

Check official documentation and propose candidates based on:

1. Jetson Orin Nano support.
2. Availability of OP-TEE and fTPM TA sources, build instructions, and matching toolchains.
3. Relationships between source tags/commits and distributions, and licensing conditions.

Record official URLs and verified versions rather than assuming which release is latest.

## Subsequent work

1. Obtain the selected sources and toolchain and pin their versions.
2. Inspect Tegra-specific dependencies required for OP-TEE boot and fTPM.
3. Compare NVIDIA source changes with QEMU implementation effort and define the minimum scope.
4. Verify boot, TA loading, TPM commands, and persistence in that order.

## eFuse investigation

- Register access paths for identifiers and configuration values.
- Secret-dependent key derivation, crypto engines, and key slots.
- Services accessed through other firmware.
- Relationships with secure storage, persistent TPM state, EKs, and certificates.

Do not assume that implementing eFuse registers alone is sufficient.
Consider persistent test secrets and identifiers for each virtual device; copying real-device secrets is not a prerequisite.
Specify which state survives reboot, TPM clear, OS reinstallation, VM cloning, and snapshots.

## Open questions

- Must original Jetson binaries run unchanged, or is rebuilding the same source acceptable?
- Is the entire boot chain required, or is running OP-TEE / fTPM sufficient?
- What constitutes TPM equivalence: PCRs, NV, keys, seal/unseal, EK certificates, attestation, etc.?
- Host OS/CPU, available resources, and access to hardware for comparison testing.

## Constraints

QEMU's standard AArch64 virt machine does not emulate Tegra234.
Compilation with NVIDIA's toolchain and execution of real-device binaries require separate verification.
Functional virtual eFuse emulation does not reproduce hardware protection on the real device.
