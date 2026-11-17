# 0008: Interactive boot, SSH, host sharing and CPU count

[日本語](../../decisions/0008-interactive-runtime.md) | English

Status: interactive boot, a man page and configurable CPUs (default four) are requested. SSH authentication and 9p sharing are selected; see the outcome below.
Root is currently locked with no configured password; there is no default password.
Before this change, only first/second/export/bound automatic test modes existed. Add normal boot without automatic tests or poweroff.
Rebuild OP-TEE for up to eight CPUs, matching TF-A capacity, because the existing one-CPU firmware is insufficient for the requested default.
Select one to eight CPUs at launch, default four, and match the DTB CPU topology.

| Choice | A (recommended) | B |
| --- | --- | --- |
| SSH authentication | Root public-key authentication; console password configured locally by the user | Also allow root password authentication, password configured locally |
| Host sharing | 9p, supported by the supplied kernel's 9p/virtio configuration | virtio-fs, requiring kernel rebuilding and virtiofsd |

SSH is optional and uses localhost host forwarding. Sharing exposes only the specified host directory and is mounted manually through a guest command.
Preserve TPM state, seeds, CA and disk. Provide existing-disk service installation/configuration instructions.
After selection, record the outcome and exact commands in bilingual manuals and man pages.

## Selected behavior

The user requires no root SSH, and public-key authentication for regular users only.
Create users and register keys after initial boot. Host sharing uses 9p.
No default password is installed. Only explicit setup mode exposes an initial root console; normal boot and SSH do not use that unauthenticated console.
Sharing defaults to read-only, with explicit --share-rw and manual guest mounting.

### Additional SMP/GIC decision

Four-CPU testing exposed a GICv2 initialization failure in the distributed NVIDIA kernel, followed by ipi_setup/__ipi_send_mask panic.
The source SGI allocation param_count=1 does not match the translation path's parameter requirements.
Option A: align QEMU/TF-A/OP-TEE on GICv3, retaining the distributed kernel.
Option B: patch and rebuild the kernel GICv2 path.
The user selected A. Rebuild firmware for GICv3 and up to eight CPUs; old single-CPU results do not prove four-CPU operation.

### Debugging

Additional requirements add --qemu-console, --monitor-socket, --gdb/--gdb-port and --wait-gdb.
GDB exposes a localhost guest-CPU remote stub, distinct from gdb -p against the QEMU host process.

### DTB 64-bit value alignment

The GICv3 DTB placed secure-chosen/kaslr-seed on a four-byte boundary, causing an alignment fault in the early OP-TEE 64-bit read.
align-optee-dtb.py inserts FDT_NOP to align it to eight bytes, preserving its value and ASLR without NVIDIA source changes.
TF-A builds under work/tf-a-gic3 to avoid mixing old GICv2 intermediates.

Additional implementation findings:
- Upstream QEMU TF-A validates MPIDR for four CPUs per cluster. This profile sets QEMU_JETSON_FTPM=1 to use one eight-CPU cluster matching QEMU GICv3 Aff0=0..7.
- Build TF-A in work/tf-a-ftpm, isolated from old GICv2 intermediates.
- OP-TEE's early kaslr-seed load needs 64-bit alignment. Insert a standard FDT_NOP without changing the seed or NVIDIA's reader function.
- Orderly shutdown issues TPM2_Shutdown and detaches fTPM before stopping the supplicant.
