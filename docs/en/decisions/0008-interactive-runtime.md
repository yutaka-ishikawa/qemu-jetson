# 0008: Interactive boot, SSH, host sharing and CPU count

[日本語](../../decisions/0008-interactive-runtime.md) | English

Status: interactive boot, a man page and configurable CPUs (default four) are requested. SSH authentication and sharing transport await selection.
Root is currently locked with no configured password; there is no default password.
Current first/second/export/bound phases are automatic tests. Add normal boot without automatic tests or poweroff.
Rebuild OP-TEE for up to eight CPUs, matching TF-A capacity, because the existing one-CPU firmware is insufficient for the requested default.
Select one to eight CPUs at launch, default four, and match the DTB CPU topology.

| Choice | A (recommended) | B |
| --- | --- | --- |
| SSH authentication | Root public-key authentication; console password configured locally by the user | Also allow root password authentication, password configured locally |
| Host sharing | 9p, supported by the supplied kernel's 9p/virtio configuration | virtio-fs, requiring kernel rebuilding and virtiofsd |

SSH is optional and uses localhost host forwarding. Sharing exposes only the specified host directory and is mounted manually through a guest command.
Preserve TPM state, seeds, CA and disk. Provide existing-disk service installation/configuration instructions.
After selection, record the outcome and exact commands in bilingual manuals and man pages.
