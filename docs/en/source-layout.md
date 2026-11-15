# Bundled sources and build layout

[日本語](../source-layout.md) | English

## Source locations

- `qemu/`: official QEMU 11.1.3 release sources, modified directly in this tree. It is neither a separate Git repository nor a submodule.
- `optee/`: NVIDIA R36.5.2 OP-TEE package with its internal directory structure preserved.
- `kernel/`: NVIDIA R36.5.2 kernel_src package; the kernel itself is under `kernel/kernel/kernel-jammy-src/`.
- `work/`: builds, downloads, rootfs, and runtime state, excluded from Git.

Download references, hashes, and QEMU's baseline commit are recorded in [source-baselines.json](../../manifests/source-baselines.json).
Import distribution snapshots rather than complete upstream Git histories, and record project changes on top.
The QEMU release archive includes ROM sources and test data and occupies approximately 899 MiB extracted.
Kernel sources occupy approximately 1.3 GiB. Generated build artifacts are not committed.
Separately distributed NVIDIA out-of-tree modules and display drivers are not part of this kernel_src import.

## Separately licensed NVIDIA components

CCC headers and crypto library, some build helpers, and certain documents carry terms separate from the BSD-family code.
Do not republish these collectively in public Git; restore them locally from official archives.
See [optee-excluded-files.json](../../manifests/optee-excluded-files.json).
Treat `kernel/nvcommon_build.sh` in the same way. Original license files are included and their terms preserved.

```bash
scripts/restore-nvidia-components.py \
  /path/to/nvidia-jetson-optee-source.tbz2 \
  /path/to/kernel_src.tbz2
```

Both archives are under `Linux_for_Tegra/source/` in NVIDIA's official R36.5.2 public_sources.tbz2.
The script verifies SHA-256, extracts only listed files, and refuses to overwrite different existing files.
Restored components are Git-ignored; do not push them together with the public sources.
An initial clone therefore does not provide every input for NVIDIA's official T234 build.

## QEMU build

Do not clone the sources again. Use an out-of-tree build directory.
A Linux host needs GCC, Make, Python, venv, Ninja, pkg-config, GLib development files, and other configure-detected dependencies.
Check missing dependencies using the actual configure run.

```bash
mkdir -p work/qemu-build
cd work/qemu-build
../../qemu/configure --target-list=aarch64-softmmu \
  --without-default-features --disable-werror --disable-docs
ninja -j2 qemu-system-aarch64
./qemu-system-aarch64 --version
```

This is a minimal-feature AArch64 system emulator build.
The dedicated Jetson machine has not been added, so these commands alone do not boot NVIDIA's OP-TEE.

## OP-TEE and Linux

Use the existing [OP-TEE build record](r36.5.2-build.md), replacing the working source directory with the bundled `optee/` tree.
Supply the toolchain, StMM, and locally restored components separately.
For Linux/rootfs integration, use [optee-ftpm.config](../../configs/kernel/optee-ftpm.config) and the
[Ubuntu rootfs procedure](ubuntu-rootfs.md).
Kernel configuration, DT, module builds, and QEMU execution tests remain future stages.

## Import verification

November 16, 2026 (Japan time): verified that Git tracks all expected distribution files/symlinks:
78,773 for QEMU, 73,920 for kernel_src, and 4,209 for OP-TEE.
These counts exclude separately licensed files listed above. All filenames are ASCII.
Verified that the seven locally restored files are not tracked.
