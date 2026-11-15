# Ubuntu 22.04 ARM64 rootfs

[日本語](../ubuntu-rootfs.md) | English

## Selected configuration

Use Ubuntu 22.04 ARM64 userland without requiring NVIDIA's entire Sample Root Filesystem.
Pin official Ubuntu Base 22.04.5, then install required packages from jammy, updates, and security.
Use the OP-TEE client built from NVIDIA R36.5.2. fTPM and its Helper TA are Secure World Early TAs, not Ubuntu packages.

- Import `tee-supplicant`, `libteec.so.2`, and `nvftpm-helper-app` from the existing OP-TEE install directory.
- Install systemd, udev, kmod, tpm2-tools, the device TCTI library, OpenSSL, and dependencies from Ubuntu.
- Use `/data/tee` for REE FS storage and preserve it per virtual device.
- The fTPM driver is Linux kernel `CONFIG_TCG_FTPM_TEE`, separate from userland services.

Rootfs archives, downloads, and build contexts live under Git-ignored `work/`.
QEMU, OP-TEE, and Linux sources were subsequently bundled. See the [source layout](source-layout.md).

## Build

The host needs Docker, Bash, curl, sha256sum, readelf, and tar.
PRoot and QEMU user-mode run inside the build container, without host binfmt registration or privileged containers.

```bash
scripts/fetch-ubuntu-base.sh
scripts/build-ubuntu-rootfs.sh \
  /workspace/work/nvidia-r36.5.2/optee/optee/install/t234 \
  work/ubuntu-jammy-arm64-rootfs.tar
```

Replace the OP-TEE install path with your build location.
Existing output archives are not overwritten. The build produces Docker image `qemu-jetson-rootfs:jammy` and a rootfs tar.
The final image excludes the build-only PRoot and QEMU tools.
Downloads are checked against the [pinned SHA-256](../../manifests/ubuntu-base-22.04.5-arm64.sha256).
Official checksums: https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/SHA256SUMS .
This does not claim separate verification of Ubuntu signatures.
APT installs updates available at build time and records versions in `/usr/share/qemu-jetson/packages.tsv`.
APT repositories and the builder Ubuntu image are not snapshot-pinned; bit-for-bit reproducibility is not guaranteed.

## Kernel and boot prerequisites

Merge the [configuration fragment](../../configs/kernel/optee-ftpm.config) into the target kernel configuration and inspect the result after olddefconfig.
It is not a full Jetson/QEMU defconfig: CPU, interrupts, storage, console, and networking need additional configuration.
Install matching modules for `CONFIG_TCG_FTPM_TEE=m` into `/lib/modules/<kernel-release>/` and run depmod.
The modules-load configuration loads `tpm_ftpm_tee` during boot.
A working OP-TEE DT node, SMC path, and Secure World fTPM TA are required.

`jetson-tee-supplicant.service` runs in the foreground and retries on failure.
Its TA search path is `/lib/optee_armtz`. fTPM and Helper TA are embedded, so do not add duplicate external copies.
Rootfs construction does not provision or clear the TPM.

The exported tar is not yet a bootable disk image.
A later step must populate ext4 or another filesystem preserving root ownership and permissions, and configure the kernel, root=, init=/sbin/init, and console.
DNS defaults to `10.0.2.3` for QEMU user networking; adjust it for other network setups.
No default login password or SSH service is added.

## Guest check

Run as root inside the guest; only read-only TPM queries are issued.

```bash
/usr/local/sbin/check-ftpm-guest.sh
```

The script checks Ubuntu/CPU, `/dev/teepriv0`, the supplicant service, and `/dev/tpmrm0`,
then runs `tpm2_getcap properties-fixed` and `tpm2_pcrread sha256:0`.
These checks do not establish NV persistence, seal/unseal, Fuse-derived identity, or certificate equivalence.

## Validation status

Record download, build, and execution results below. Distinguish userland execution inside the rootfs
from OP-TEE/TPM testing under QEMU system emulation.

November 16, 2026 (Japan time): construction using Docker/PRoot/QEMU user-mode completed with exit code 0.
Verified Ubuntu 22.04.5 LTS ARM64, NVIDIA's `tee-supplicant --help`, and `tpm2_getcap --version` (5.2).
Inspected the exported tar for ARM64 ELF files, libteec, the guest check script, service enablement link,
0700 permissions on `/data/tee`, and absence of the build-only QEMU executable.
Also checked Bash syntax and relative documentation links.

- Rootfs tar size: 272,271,872 bytes (approximately 260 MiB).
- This rootfs SHA-256: `00daf6ca3c24e0eaf4264d722cda81da5659b1debb18b9eb43b2898b3fddd803`.
- The supplicant SHA-256 matches the existing unmodified build record.
- Actual systemd boot, kernel modules, OP-TEE connectivity, and TPM queries remain untested.
