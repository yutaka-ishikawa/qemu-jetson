# 0001: fTPM execution path

[日本語](../../decisions/0001-ftpm-execution-path.md) | English

Status: approved by the user. Date: November 16, 2026 (Japan time).

## Context

Unmodified T234 OP-TEE passes Fuse initialization but aborts in the unimplemented SE0 configuration function.
There are two candidate paths toward working fTPM.

| Option | Approach | Benefits | Constraints |
| --- | --- | --- | --- |
| A | Keep the T234 configuration and implement SE0, randomness, and key slots in QEMU | Prioritizes preserving T234 binaries and hardware execution paths | Public specifications are incomplete; implementation scope is undetermined |
| B | Use the existing QEMU platform in the bundled NVIDIA OP-TEE source with the unchanged NVIDIA fTPM TA | Enables earlier verification of TPM commands and persistence without TA changes | Requires a small addition for virtual-device keys in OP-TEE; does not reproduce T234 SE/eFuse execution paths |

## Decision

The user selected B. Preserve the existing T234 harness and Fuse model while adding a functional test configuration.
Make OP-TEE additions explicitly opt-in, retaining the existing platform defaults.
Persist per-device identity in a host file rather than using a shared fixed HUK.
Do not modify the NVIDIA fTPM TA. Use Ubuntu 22.04 ARM64 userland.

This does not establish complete T234 SE emulation, hardware key protection, or manufacturing certificate trust.
Report TPM commands, persistence, and missing hardware-specific behavior separately.

## Future decisions

Present material design, compatibility, or implementation choices to the user with alternatives, benefits, constraints, and a recommendation.
Wait for selection before dependent implementation, then document alternatives and the decision in Japanese and English and push directly to main.
