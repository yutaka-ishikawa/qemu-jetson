# 0002: fTPM helper PTA for the QEMU profile

[日本語](../../decisions/0002-ftpm-helper-pta.md) | English

Status: awaiting the user's decision. This does not reverse approved option B in decision 0001.

## Evidence

NVIDIA's fTPM TA calls `FTPM_HELPER_PTA_CMD_PING_NS` during initialization.
Its target UUID is `6c879517-2dfc-4663-863d-4896e8ccbe3a`.
The NVIDIA OP-TEE QEMU platform does not include this PTA.
A real boot also failed to load this UUID with `0xffff0008` (ITEM_NOT_FOUND).
Keeping the TA unchanged requires a decision about the OP-TEE implementation scope.

| Alternative | Implementation | Benefits | Limitations |
| --- | --- | --- | --- |
| B1 (recommended) | Add a QEMU-specific PTA for normal-world readiness notification | Preserves the TA source and advances TPM command/persistence tests with limited NVIDIA changes | Does not provide all manufacturing, certificate, or provisioning helper APIs; unsupported commands must return explicit errors |
| B2 | Port the complete NVIDIA helper PTA and its dependencies | Targets broader helper API compatibility | Depends on Tegra Fuse, key management and provisioning, increasing scope; physical SE key protection still requires separate work |

B1 would report the actual REE state, following NVIDIA's implementation, rather than hardcode a ready response.
Neither implementation starts before the user chooses.
