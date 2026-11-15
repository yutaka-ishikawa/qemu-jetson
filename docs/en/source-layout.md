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

Run `scripts/fetch-nvidia-components.sh` to download official distributions and restore the components automatically.
If you already have the nested archives, use the following alternative.

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
These commands alone do not supply the firmware and inputs needed to boot NVIDIA's OP-TEE on the dedicated machine.

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

With Docker, `scripts/build-qemu.sh` creates a dedicated builder image and compiles the bundled sources into `work/qemu-container-build/`.

Use `QEMU_REBUILD_BUILDER=1 scripts/build-qemu.sh` to rebuild the builder image; otherwise the existing named image is reused. The baseline check is `scripts/check-qemu-baseline.py`.

## QEMU baseline test results

November 16, 2026 (Japan time): built the bundled QEMU 11.1.3 AArch64 system emulator;
`scripts/build-qemu.sh` completed with exit code 0 using the Ubuntu 22.04 builder container and minimal-feature configuration above.

`scripts/check-qemu-baseline.py` verified:

- Startup with `virt,secure=on`, TCG, `max` CPU, one core, and 128 MiB RAM.
- Successful QMP capabilities, query-status, CPU model expansion, and quit responses.
- A prelaunch stopped state and CPU model property `pauth` set to true.
- Clean process exit.

This is **only a QEMU baseline test**. No firmware, Linux, OP-TEE, or TPM was booted.
At the time of that baseline test, the dedicated T234 machine, TCU, and EL3 boot code were not implemented.
See the subsequent [Stage A implementation and tests](t234-stage-a.md).
The local Git pack after source import was approximately 387 MiB; builds need additional space.
This environment has an approximately 8 GiB limit, so the reproducible validated rootfs tar and Docker build caches were cleaned up.
Sources, Git history, and the compressed OP-TEE build baseline were preserved.

See [t234-fuse.md](t234-fuse.md) for the current read-only Fuse model and validation results.
