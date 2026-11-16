# 0006: SELinux configuration for the Ubuntu QEMU guest

[日本語](../../decisions/0006-guest-selinux.md) | English

Status: awaiting user selection. Option A recommended. No dependent implementation before selection.

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
