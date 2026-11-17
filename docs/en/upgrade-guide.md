# Upgrade an existing QEMU environment

[日本語](../upgrade-guide.md) | English

This guide updates an existing disk while preserving accounts, authorized keys, SSH host keys, device identity, seeds, CA and TPM NV state.
For a fresh clone and new disk, use [build-install.md](build-install.md), not this guide.
Stop QEMU before host-side disk updates. Stop on errors; do not recreate the disk or regenerate credentials to work around failures.

## Upgrade an existing environment once

Stop QEMU. Run at the repository root, checking each command succeeds. Preserve the disk, identity, seeds and CA.
New host dependencies include libslirp-dev and libattr1-dev.

```bash
git pull --ff-only
sudo bash scripts/install-host-deps.sh
# Configure NVIDIA CROSS_COMPILE, dtc and the Python venv per build-install.md.
bash scripts/build-qemu.sh
bash scripts/build-ftpm-virt-firmware.sh
sudo bash scripts/install-ftpm-runtime-overlay.sh
python3 scripts/install-artifacts.py manual
```

QEMU is rebuilt with 9p and user networking; firmware uses GICv3 and supports up to eight CPUs.
Only files are updated on an existing disk: do not recreate rootfs.tar/rootfs.ext4.
Run the disk updater with sudo; it rejects a disk used by QEMU. Disk ownership is preserved, and a newly created lock is assigned to the disk owner so normal launches remain unprivileged.


## Install missing services inside an older guest

Skip this section if openssh-server, sudo, dbus and the runtime configuration are already installed.
For a disk created before interactive-runtime support, stage the public runtime installer files:

```bash
mkdir -p work/runtime-share/scripts work/runtime-share/configs/rootfs
cp scripts/setup-ftpm-runtime-guest.sh work/runtime-share/scripts/
cp -a configs/rootfs/runtime-overlay work/runtime-share/configs/rootfs/
bash scripts/run-ftpm-virt.sh setup --ssh --share "$PWD/work/runtime-share"
```

At the guest root setup console:

```bash
qemu-mount-host
bash /mnt/host/scripts/setup-ftpm-runtime-guest.sh
poweroff
```

This downloads guest packages and needs working guest Internet access (or an explicitly configured proxy).
It does not recreate accounts or register keys. For a new regular user or key, continue with [runtime initial setup](runtime-guide.md#initial-setup-console).
If accounts/keys already exist, proceed directly to normal boot in [runtime-guide.md](runtime-guide.md).

## Missing serial login in normal mode

Normal mode allows regular-user login on ttyAMA0. --ssh does not disable serial login.
The old setup unit had Conflicts=serial-getty@ttyAMA0.service. systemd resolved this conflict even when the setup unit's condition was false, suppressing normal serial getty.
The corrected unit removes Conflicts and selects setup/getty using opposite ConditionKernelCommandLine conditions.
Stop QEMU, then run:

```bash
git pull --ff-only
sudo bash scripts/install-ftpm-runtime-overlay.sh
bash scripts/run-ftpm-virt.sh --ssh
```

No rebuild, account recreation or key registration is needed. This does not enable normal root login: use the existing regular account and its local password.

## Recovering an archive containing only test files

If disk creation fails because `usr/sbin` is missing and the tar contains only about 22 test entries, the Ubuntu base is absent.
The old `prepare-ftpm-test-rootfs.py` used tar append mode, which silently created a new archive when the input did not exist.
These contents alone do not establish whether Ubuntu assembly was skipped or failed.
The corrected scripts check for Ubuntu and OP-TEE client contents before appending files or creating a disk.

Run these commands at the repository root to preserve the incomplete archive and checksum, then rebuild Ubuntu.
Keys, certificates, device identity, provisioning and existing disks are preserved.

```bash
git pull --ff-only
source work/venv/bin/activate
backup=$(mktemp -d "$PWD/work/ftpm-rootfs-backup.XXXXXX")
sudo mv -- work/ftpm-virt/rootfs.tar "$backup/"
if [ -f work/ftpm-virt/rootfs.tar.sha256 ]; then
  sudo mv -- work/ftpm-virt/rootfs.tar.sha256 "$backup/"
fi
sudo env FTPM_FUNCTIONAL_PROFILE=1 bash scripts/build-ubuntu-rootfs.sh
```

Stop and inspect the error if the last command fails. Continue only after it succeeds.

```bash
python3 scripts/prepare-ftpm-test-rootfs.py \
  work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
sudo bash scripts/create-ftpm-virt-disk.sh
bash scripts/prepare-ftpm-virt-dtb.sh
```

Do not overwrite an existing disk. Continue testing using [test-guide.md](test-guide.md).

