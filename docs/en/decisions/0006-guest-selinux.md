# 0006: SELinux configuration for the Ubuntu QEMU guest

[日本語](../../decisions/0006-guest-selinux.md) | English

Status: approved by the user. Option A selected. Add `selinux=0` to all four QEMU-specific DTB phases.

## Observations

The user log reaches Linux, the OP-TEE driver and Ubuntu init.
However, `/etc/selinux/default/policy/policy.33` is absent and systemd cannot initialize SELinux labeling.
Journald and udev sockets fail with `Failed to determine SELinux label: No data available`.
fTPM PASS is unconfirmed. Adding policycoreutils resolved the restorecon execution failure; it did not provide a complete SELinux policy and labeled filesystem.

| Option | Implementation | Benefits | Limitations |
| --- | --- | --- | --- |
| A (recommended) | Add selinux=0 to Linux bootargs in the QEMU-specific DTBs | No kernel or NVIDIA OP-TEE/TA changes; retains the existing rootfs and disk | Guest SELinux access control is disabled; host SELinux is unaffected |
| B | Install a guest SELinux policy, label the filesystem and define service access rules | Supports SELinux operation inside the guest | Requires rootfs changes, persistent labels, and policy design and validation for OP-TEE/fTPM |

Option A is a guest security configuration change and must be documented as such.
Distinguish this from TPM command functionality, OP-TEE secure-world isolation, and CA trust.
Either option requires confirming journald/udev operation and first/second PASS after implementation.
Existing keys, provisioning and NV state must not be discarded to manufacture a passing result.

## Applying the change

After QEMU exits, retain the existing disk, keys and provisioning and run:

```bash
git pull --ff-only
bash scripts/prepare-ftpm-virt-dtb.sh
bash scripts/run-ftpm-virt.sh first
```

If first has already passed, run second instead of rerunning first.
DTBs are automatically staged into install/. No QEMU, kernel, OP-TEE or rootfs rebuild is needed.
Confirm `selinux=0` appears in Linux's `Kernel command line`.
After first passes, run second using the same disk to verify persistence.

## Validation

Decompiled all four installed DTBs and verified their bootargs.
Booted the existing persistent test disk through second: journald/udev started, PTA tests passed, and `FTPM_TEST: PASS phase=second` was followed by poweroff.
No SELinux label socket creation errors occurred. First on the user newly built rootfs still requires confirmation.
See the [log excerpt](../../results/guest-selinux-excerpt.txt) and [result](../../results/guest-selinux.json).
