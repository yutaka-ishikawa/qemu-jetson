# qemu-jetson

Build and run without Docker. Start with [native host setup](docs/en/native-host.md). QEMU is installed into install/bin/; build intermediates remain in work/qemu-build/. See the [build and installation guide](docs/en/build-install.md).

[日本語](README.md) | English

QEMU for NVIDIA Jetson Orin Nano.

This project aims to run NVIDIA's OP-TEE and fTPM with minimal changes to NVIDIA-provided sources.

- [fTPM and EK certificate test guide](docs/en/test-guide.md)

## Design and procedures

- [Interactive boot, SSH, 9p and debugging](docs/en/runtime-guide.md)

- [Physical hardware versus QEMU](docs/en/hardware-qemu-differences.md)
- [Final test evidence](docs/en/final-test-evidence.md)
- [OP-TEE page-table usage analysis](docs/en/page-table-analysis.md)


- [Fuse model and validation](docs/en/t234-fuse.md)
- [Stage A: first OP-TEE log](docs/en/t234-stage-a.md)
- [Bundled sources and build layout](docs/en/source-layout.md)
- [Ubuntu 22.04 ARM64 rootfs build](docs/en/ubuntu-rootfs.md)
- [Requirements and approach](docs/en/requirements.md)
- [QEMU boot design](docs/en/qemu-boot-design.md)
- [Implementation procedure](docs/en/implementation-plan.md)
- [L4T release candidates](docs/en/release-candidates.md)
- [R36.5.2 source investigation](docs/en/r36.5.2-source-investigation.md)
- [R36.5.2 unmodified build results](docs/en/r36.5.2-build.md)

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
