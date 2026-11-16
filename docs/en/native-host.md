# Native host environment without Docker

[日本語](../native-host.md) | English

[Decision 0004](decisions/0004-native-host.md) moves project builds, launches, DT generation and disk updates directly onto the host.
Docker, buildx and Docker-group membership are unnecessary.

## Locations and privileges

| Item | Default location | Privileges |
| --- | --- | --- |
| QEMU | install/bin/qemu-system-aarch64 | Build/install/run as ordinary user |
| OP-TEE/TA/client outputs | install/lib/, install/libexec/, install/share/ | Ordinary user |
| Read-only boot images | install/share/qemu-jetson/ | Ordinary user |
| Disk and device keys | work/ftpm-virt/ | Preserve existing keys/state |
| Host dependencies | apt's /usr/bin, /usr/lib, etc. | Administrator for installation |
| Ubuntu rootfs assembly and new ext4 creation | Outputs under work/ftpm-virt/ | Administrator to preserve guest UID/GID |

QEMU is installed into the local prefix using Meson install after compilation. See the [install manual](install-layout.md) for the complete bin/include/lib/libexec/share layout.
INSTALL_DIR=/absolute/path changes the artifact prefix used by all scripts. QEMU_BUILD_DIR changes only build intermediates.
The old work/qemu-container-build/ directory is not deleted automatically; keys and disks are preserved.

## Ubuntu/Debian dependencies

Target hosts are Ubuntu 22.04+ or Debian 12+.

```bash
sudo bash scripts/install-host-deps.sh
bash scripts/build-qemu.sh
```

The installer uses apt only when explicitly invoked. Builds never install packages automatically.
It installs GCC, Python venv, Ninja, pkg-config, GLib/pixman/zlib/libfdt development files, dtc,
PRoot, QEMU user mode, e2fsprogs, kmod, and fakeroot for validation.
Install cryptography, pycryptodome and pyelftools in the OP-TEE Python venv separately.
NVIDIA's required AArch64 cross compiler remains necessary and is not replaced by this installer.

```bash
INSTALL_DIR="$PWD/custom-install" JOBS=4 bash scripts/build-qemu.sh
INSTALL_DIR="$PWD/custom-install" bash scripts/run-ftpm-virt.sh second
```

Use first only on a fresh, untested disk. Do not repeat it on initialized test state.
The second phase also runs tests automatically and powers the guest off on success.
With the default prefix, INSTALL_DIR and the former FTPM_NATIVE_QEMU flag are unnecessary.

## ARM64 Ubuntu rootfs

```bash
sudo env FTPM_FUNCTIONAL_PROFILE=1 \
  KERNEL_MODULES_DIR="$PWD/work/ftpm-virt/modules" \
  bash scripts/build-ubuntu-rootfs.sh /path/to/optee/install/t234 \
  "$PWD/work/ftpm-virt/rootfs.tar"
python3 scripts/prepare-ftpm-test-rootfs.py work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
sudo bash scripts/create-ftpm-virt-disk.sh
```

PRoot runs ARM64 apt. AArch64 hosts omit the user-mode emulator.
Host passwd/group and home directories are not bound into the guest. No host binfmt registration or container daemon is required.
A temporary policy-rc.d prevents guest service startup during assembly.
The temporary rootfs uses a searchable parent under /tmp so apt can drop privileges; it is removed on exit.
Native host depmod generates module dependencies.
The rootfs tar and ext4 output files are returned to the sudo caller's ownership.

## Updating an existing disk

```bash
# Stop QEMU first.
bash scripts/update-ftpm-test-disk.sh work/ftpm-bound-provisioning
```

Host debugfs/e2fsck edit the writable image. Only public fixtures/test programs are updated, with explicit guest root ownership.
The script rejects an image open by QEMU. It does not regenerate private keys, seeds or NV state.

## Validation scope

This environment cannot install system packages or rebuild the full rootfs as host administrator.
Validation dependencies are extracted under work/ instead. Native QEMU compilation, fTPM regression on the existing disk,
and ext4 UID/GID/mode preservation and overwrite refusal passed.
See the [machine-readable result](../results/native-host.json) and [actual log excerpt](../results/native-host-excerpt.txt).
Rootfs shell syntax and privilege errors are checked; a fresh privileged end-to-end rootfs rebuild is unverified.
See [functional validation](ftpm-functional-validation.md) for prior fTPM results.

See the [installation manual](install-layout.md) for the current layout and build/install workflow.
