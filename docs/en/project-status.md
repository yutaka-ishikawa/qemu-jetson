# Completion status and remaining work

[日本語](../project-status.md) | English

As of November 17, 2026 (JST). Baseline before this documentation update: c5987359c.
This classifies remaining work; it does not select additional implementation approaches.

## Completed

- NVIDIA fTPM TA, helper TA and helper PTA run on B2 (jetson-ftpm-virt). TPM functionality, persistence and real EK/test-certificate matching were verified. The user reported all tests passing; second/export/bound/bound-reboot logs were also reviewed.
- QEMU-only test CA and virtual identity/provisioning paths are implemented. These do not establish NVIDIA manufacturing trust.
- OP-TEE translation-table capacity increased from 8 to 32, with cause analysis. The observed peak was 9 tables on one CPU.
- Interactive boot, four default CPUs (selectable 1–8), GICv3, non-root public-key SSH, rejection of root/password SSH, manual 9p sharing, QEMU monitor and GDB connections are implemented. Developer tests on an existing disk covered four/eight CPUs and bound tests.
- Native builds without Docker, install/ artifact placement and bilingual installation/runtime/test/upgrade guides are provided. The example username is cradsec.

## Priority remaining work

| Priority | Item | Completion criteria and handling |
| --- | --- | --- |
| High | End-to-end verification of current instructions from a fresh environment | In a separate directory independent of existing work/install, complete clone, builds, privileged rootfs/disk assembly, initial account/key registration, normal boot and tests. Record logs, versions and hashes. Current runtime evidence uses an existing disk. Do not reset existing TPM state |
| Medium | First-run evidence | The original user first PASS log has not been received. Preserve it if available. Otherwise retain the evidence limitation and collect separate first evidence during the fresh-environment test. Never rerun first on the existing disk |
| Medium | Independent host verification of issued certificates | Use public certificates, keys and CSRs to independently verify the chain, Firmware ID signature and EK public-key matching. Current certificate signature evidence relies on guest PASS markers. No private keys, seeds or disk submissions are needed |

The high-priority item is the proposed next task. Keep its state separate from the existing environment.

## Additional validation according to intended use

These are unverified areas, not known defects invalidating current PASS results. Select the required scope before doing the work.

- Run identical TPM/API scenarios on hardware and QEMU and compare externally visible results. No controlled hardware comparison has been performed.
- Measure table high-water usage and stability with four/eight CPUs, multiple ASLR layouts, long runs, concurrent access and multiple TAs. The one-CPU 9/32 observation is not a multicore upper bound.
- Validate the required TPM command coverage, recovery, TPM Clear, OS reinstallation and snapshot lifecycle cases. Use dedicated state for destructive tests.
- Boot-test every supported CPU count from 1 to 8. The current runtime record individually covers four/eight CPUs.

## Work requiring a separate development decision

- Hardware reproduction in jetson-t234-dev: Fuse reads are implemented, but execution stops at SE0 initialization. SE/key slots/OTP writes remain unimplemented. This is separate from the approved B2 functional path and will not resume automatically.
- Measured Boot, INJECT_EPS, the production Secure Boot chain, rollback protection, hardware-equivalent secret protection and NVIDIA manufacturing trust are not provided. Revisit requirements and choose an approach if needed.
- GPU/CUDA execution is outside the user's requirements.

## Evidence

See [final test evidence](final-test-evidence.md), [runtime results](../results/runtime.json),
[hardware differences](hardware-qemu-differences.md) and [page-table analysis](page-table-analysis.md).
Material implementation alternatives still require presenting candidates, obtaining the user's decision and documenting it in both languages.
