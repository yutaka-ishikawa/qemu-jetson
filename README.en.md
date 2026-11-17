# qemu-jetson

Build and run without Docker. Start with [native host setup](docs/en/native-host.md). QEMU is installed into install/bin/; build intermediates remain in work/qemu-build/. See the [build and installation guide](docs/en/build-install.md).

[日本語](README.md) | English

QEMU for NVIDIA Jetson Orin Nano.

This project aims to run NVIDIA's OP-TEE and fTPM with minimal changes to NVIDIA-provided sources.

## Estimated disk space

### Measured usage after build and installation

On 2026-11-17 (Japan time), the user reported **5.4G** from `du -sh qemu-jetson` after build and installation.
Major directories from the same environment's `du -sh *` output are listed below, preserving du's units and rounding.

| Directory | Measured usage |
| --- | ---: |
| work/ | 2.4G |
| kernel/ | 1.3G |
| qemu/ | 882M |
| install/ | 486M |
| optee/ | 54M |
| firmware/ | 38M |
| samples/ | 436K |

The 5.4G figure is the repository's post-build disk usage, a measured example below the estimates that follow.
Peak usage, including temporary build/extraction directories and space outside the repository, has not been measured.
`du -sh *` excludes hidden entries such as .git, so these excerpts are not a complete breakdown to sum against the total.
This measurement alone does not establish peak usage during the full test sequence or the minimum required free space.

### Capacity planning including temporary space (estimate)

For a fresh build and the full test sequence, **allow at least 30GB of free space; 50GB is recommended for headroom**.
If you retain an existing environment and build in another directory, reserve this space in addition to the existing environment.

| Purpose | Estimate |
| --- | ---: |
| Git metadata and bundled sources | 3–5GB |
| Toolchain and downloaded archives | 2–5GB |
| QEMU, OP-TEE, TF-A and other build intermediates | 2–4GB |
| Installed artifacts under install/ | 0.5–1GB |
| Ubuntu rootfs, tar archive and virtual disk | 5–10GB |
| Temporary extraction/assembly space, logs, etc. | 3–5GB |
| **Total (rounded estimate)** | **About 16–30GB** |

These estimates cover the current configuration that downloads NVIDIA's prebuilt kernel; they are not measured peak usage from a complete fresh build.
If you also build the Linux kernel from source, allow another 10–20GB and reserve at least 50GB of free space.

## Documentation index

Start with build-install.md for a new environment. The table also lists design documents, validation records and decisions.

| Category | Contents | Document |
| --- | --- | --- |
| Usage | Fresh clone, environment setup, builds, disk and DTBs | [build-install.md](docs/en/build-install.md) |
| Usage | Initial account/key setup, normal boot, SSH, 9p and debugging | [runtime-guide.md](docs/en/runtime-guide.md) |
| Usage | first/second, EK certificates and persistence tests | [test-guide.md](docs/en/test-guide.md) |
| Usage | Update existing environments/disks and apply fixes | [upgrade-guide.md](docs/en/upgrade-guide.md) |
| Usage | Sample host cross-build, guest-native make and execution | [samples-guide.md](docs/en/samples-guide.md) |
| Environment/build | Native host environment without Docker | [native-host.md](docs/en/native-host.md) |
| Environment/build | Bundled sources and build layout | [source-layout.md](docs/en/source-layout.md) |
| Environment/build | Ubuntu 22.04 ARM64 rootfs | [ubuntu-rootfs.md](docs/en/ubuntu-rootfs.md) |
| Status/validation | Completion status and remaining work | [project-status.md](docs/en/project-status.md) |
| Status/validation | Differences between physical Jetson hardware and QEMU | [hardware-qemu-differences.md](docs/en/hardware-qemu-differences.md) |
| Status/validation | Final test evidence inventory | [final-test-evidence.md](docs/en/final-test-evidence.md) |
| Status/validation | OP-TEE translation table usage analysis | [page-table-analysis.md](docs/en/page-table-analysis.md) |
| Status/validation | Historical fTPM/helper PTA validation and reproduction record | [ftpm-functional-validation.md](docs/en/ftpm-functional-validation.md) |
| Design/research | Goals and staged approach | [requirements.md](docs/en/requirements.md) |
| Design/research | QEMU boot design for unmodified T234 OP-TEE | [qemu-boot-design.md](docs/en/qemu-boot-design.md) |
| Design/research | T234 implementation plan and staged validation record | [implementation-plan.md](docs/en/implementation-plan.md) |
| Design/research | Option B: NVIDIA fTPM functional QEMU profile | [ftpm-virt.md](docs/en/ftpm-virt.md) |
| Design/research | B2: porting the complete NVIDIA helper PTA | [ftpm-helper-port.md](docs/en/ftpm-helper-port.md) |
| Design/research | Comparing OP-TEE daemons, TAs, PTAs and services | [optee-service-comparison.md](docs/en/optee-service-comparison.md) |
| Design/research | SIGN_EK_CSR signing key versus the EK | [ek-csr-signing.md](docs/en/ek-csr-signing.md) |
| Design/research | OP-TEE sample import candidates | [sample-import-candidates.md](docs/en/sample-import-candidates.md) |
| T234 validation | Read-only T234 Fuse model | [t234-fuse.md](docs/en/t234-fuse.md) |
| T234 validation | Stage A: first OP-TEE log | [t234-stage-a.md](docs/en/t234-stage-a.md) |
| Release research | Jetson Linux release candidates | [release-candidates.md](docs/en/release-candidates.md) |
| Release research | R36.5.2 OP-TEE / fTPM source investigation | [r36.5.2-source-investigation.md](docs/en/r36.5.2-source-investigation.md) |
| Release research | R36.5.2 unmodified build record | [r36.5.2-build.md](docs/en/r36.5.2-build.md) |
| Reference | Launcher man pages | [English](docs/man/run-ftpm-virt.1) / [日本語](docs/ja/man/run-ftpm-virt.1) |
| Decisions | 0001: fTPM execution path | [0001-ftpm-execution-path.md](docs/en/decisions/0001-ftpm-execution-path.md) |
| Decisions | 0002: fTPM helper PTA for the QEMU profile | [0002-ftpm-helper-pta.md](docs/en/decisions/0002-ftpm-helper-pta.md) |
| Decisions | 0003: Provisioning data for B2 validation | [0003-ftpm-provisioning-data.md](docs/en/decisions/0003-ftpm-provisioning-data.md) |
| Decisions | 0004: Build and run without Docker | [0004-native-host.md](docs/en/decisions/0004-native-host.md) |
| Decisions | 0005: Consolidate built artifacts under install/ | [0005-install-prefix.md](docs/en/decisions/0005-install-prefix.md) |
| Decisions | 0006: SELinux configuration for the Ubuntu QEMU guest | [0006-guest-selinux.md](docs/en/decisions/0006-guest-selinux.md) |
| Decisions | 0007: udev and ttyAMA0 boot waits | [0007-boot-device-wait.md](docs/en/decisions/0007-boot-device-wait.md) |
| Decisions | 0008: Interactive boot, SSH, host sharing and CPU count | [0008-interactive-runtime.md](docs/en/decisions/0008-interactive-runtime.md) |
| Decisions | 0009: Separate fresh build, normal use, tests and upgrades | [0009-guide-organization.md](docs/en/decisions/0009-guide-organization.md) |
| Decisions | 0010: Additional OP-TEE samples | [0010-optee-samples.md](docs/en/decisions/0010-optee-samples.md) |

## Current implementation status

The QEMU implementation baseline is **11.1.3**, the latest stable release verified on November 16, 2026 (Japan time).
The unmodified T234 build of NVIDIA's OP-TEE and fTPM has succeeded.
Unmodified OP-TEE emits its first logs on the dedicated QEMU machine. A read-only Fuse model now passes Fuse initialization; execution stops in the unimplemented SE0 configuration function.
SE0 emulation remains incomplete in the T234-specific profile. The separate B2 functional profile now runs NVIDIA helper PTA/fTPM TA with Ubuntu 22.04 ARM64 and verifies TPM commands, persistence and test certificates bound to actual EKs.
See [execution results and reproduction](docs/en/ftpm-functional-validation.md).

## Documentation policy

Maintain both Japanese and English versions of every project documentation page, with English filenames and directory names.
Update both versions together and preserve technical values, commands, and verification status.
The Python dependency file is shared by both languages.

Push changes directly to `main` without creating pull requests.

Preserve original upstream documentation and licenses inside bundled source trees.

Present material design/compatibility alternatives to the user, then record the selected decision in both languages and push it.
[Selected fTPM execution path](docs/en/decisions/0001-ftpm-execution-path.md).

See the [functional profile](docs/en/ftpm-virt.md) for option-B build, boot, and persistence tests.

B2 integrates the [complete NVIDIA helper PTA](docs/en/ftpm-helper-port.md). See also [SIGN_EK_CSR versus the EK](docs/en/ek-csr-signing.md).

**Installation manual:** [docs/en/build-install.md](docs/en/build-install.md). Binaries, headers and libraries default to the local install/ prefix.
