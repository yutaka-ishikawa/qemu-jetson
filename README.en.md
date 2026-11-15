# qemu-jetson

[日本語](README.md) | English

QEMU for NVIDIA Jetson Orin Nano.

This project aims to run NVIDIA's OP-TEE and fTPM with minimal changes to NVIDIA-provided sources.

## Design and procedures

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
Unmodified OP-TEE emits its first logs on the dedicated QEMU machine and currently stops at an unimplemented Fuse read.
Complete OP-TEE initialization, Linux boot, and TPM functionality remain unverified.

## Documentation policy

Maintain both Japanese and English versions of every project documentation page, with English filenames and directory names.
Update both versions together and preserve technical values, commands, and verification status.
The Python dependency file is shared by both languages.

Push changes directly to `main` without creating pull requests.

Preserve original upstream documentation and licenses inside bundled source trees.
