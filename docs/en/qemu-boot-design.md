# QEMU boot design for unmodified T234 OP-TEE

[日本語](../qemu-boot-design.md) | English

Investigation date: November 16, 2026 (Japan time). This is a design proposal based on source inspection.
At design time, QEMU implementation, boot tests, and TPM execution tests had not been performed.
See the subsequent [Stage A implementation and test results](t234-stage-a.md).
Mapping an address alone does not establish device behavior.

## Proposed approach

Preserve NVIDIA's T234 OP-TEE / fTPM sources and the previously built artifacts, and **add a dedicated QEMU machine model and boot firmware**.
Reuse existing QEMU CPU, interrupt controller, timer, and other components.
The initial goal is OP-TEE log output, a separate milestone from fTPM functionality or complete Jetson emulation.

Running NVIDIA's ATF unchanged is not an initial goal.
Requiring that as well as unmodified OP-TEE would add investigation of MC, MCE/ARI, power, reset, and other dependencies.
This proposal preserves NVIDIA's OP-TEE / fTPM sources; it does not demonstrate support for every kind of code compiled in NVIDIA's development environment.

## Differences from standard virt

The implementation baseline is **QEMU 11.1.3**, the latest stable release at the time of investigation.
Official tag `v11.1.3` resolves to commit `005c61c0ef6f6ae615283440b4bb7be51b2c6ddd`.
The following layout was rechecked in [hw/arm/virt.c for that version](https://gitlab.com/qemu-project/qemu/-/blob/v11.1.3/hw/arm/virt.c).
The official download page also lists 11.2.0-rc0, but this project selects the stable release.
Pin a tag and commit rather than the moving master or stable branch tip.
For upgrades, verify the latest stable release and record the baseline, changes, and tests before migrating.

- virt Flash occupies `0x00000000–0x07ffffff`, overlapping T234 Fuse, SE, RNG1, and QSPI addresses.
- virt Secure RAM is 16 MiB at `0x0e000000`; the T234 build sets TZDRAM to `0x80000000` with size `0x03fc0000` (63.75 MiB). It cannot simply be placed in default Secure RAM.
- TCU at `0x0c198000` lies inside virt's platform bus region, requiring an explicit integration/overlap strategy.
- GIC placement differs: NVIDIA's ATF uses GICD `0x0f400000` and GICR `0x0f440000`.

OP-TEE supports physical relocation, but the first test will place Secure RAM according to the build baseline to avoid introducing relocation issues alongside machine modeling.
Check placement of EL3 firmware, DT, OP-TEE, and shared memory for overlaps during implementation.

## Contract for entering OP-TEE

NVIDIA's ATF sources were also extracted from official public_sources.
The nested `atf_src.tbz2` SHA-256 is
`dd79c4e9dd82f54ff2c3fa9c520530a4d5b7ef3b965f641036ddb9d1ecf1e1ad`.
Its SHA-1 `4787ede3d1c2721f2c3c744b9b4534062f91d9e0` matches the included value.

ATF `services/spd/opteed/opteed_main.c` and `opteed_common.c` show that BL32 entry arguments are not in the same order as OP-TEE entry registers:

| BL32 entry information | OPTEED interpretation | Initial OP-TEE entry |
| --- | --- | --- |
| arg0 | AArch32/AArch64 selection | Used to configure execution state |
| arg1 | pageable_part | x0 |
| arg2 | mem_limit | x1 |
| arg3 | DT address | x2 |

This OP-TEE build disables Pager and Transfer List.
`boot_save_args()` in `core/arch/arm/kernel/boot.c` saves the external DT from x2.
A Linux-style `-kernel tee-raw.bin` boot does not establish this contract or Secure EL1 state.
Setting the PC through a generic loader is also insufficient because it provides no EL3 SMC return handler.

Initial test firmware handles EL3 initialization, entry into Secure EL1, and exception reporting.
Reaching initialization completion also requires handling OP-TEE's ENTRY_DONE SMC.
For Linux integration, move to a normal Secure Monitor configuration using a verified dispatcher such as TF-A OPTEED.
Do not treat the minimal custom loader as a production Secure Monitor.

## MMIO and boot dependencies

Sources refer to the R36.5.2 OP-TEE package; unless stated otherwise, paths are under `optee/optee_os/`.

| Region | Base / size | Required behavior and evidence |
| --- | --- | --- |
| Combined UART (TCU) | `0x0c198000 / 0x1000` | `core/drivers/tegra_combined_uart.c`: bit31 is busy/trigger, bit24 indicates one byte, bit26 requests flush; busy clearing and character output are the first observation point |
| Fuse | `0x03810000 / 0x600` | `core/drivers/tegra/t234/tegra_fuse.c` and common code read identifiers, BSI, and security mode |
| SE0 | `0x03b50000 / 0x30000` | Official DT and T234 SE driver; involved in CCC initialization, AES, key slots, and random generation |
| RNG1 | `0x03b70000 / 0x10000` | Mapped during CCC initialization; T234's exposed rng_get_random path calls `tegra_se_ccc_aes_genrnd()`, so implementing RNG1 alone is not established as sufficient |
| QSPI | `0x03270000 / 0x10000` | Registered by plat-tegra/main.c and mapped for StMM; actual boot accesses remain unverified |
| Scratch | `0x0c390000` | main.c registers `0x1000`; StMM DT requests two pages. Distinguish mapped ranges from actual accesses |

The official build links a prebuilt CCC library, so public C code alone does not define the entire SE MMIO protocol.
The library has not been disassembled.
Investigate public specifications and QEMU access traces; SE implementation effort remains uncertain.
Returning zero for unknown registers and pretending success cannot establish correct cryptography, randomness, or persistence.

### Initial Fuse model

Start with a read-only test Fuse image configured by the host and preserved across ordinary reboots.
Programming/burning behavior is outside initial tests.

Confirmed read offsets:

- Security mode: `0x1a0`.
- Vendor/fab/lot/wafer/coordinates/reserved: `0x200, 0x204, 0x208, 0x20c, 0x210, 0x214, 0x218, 0x220`.
- Boot Security Info: `0x268`; OEM key valid mask: `0x200`.
- ODM_INFO: `0x29c`; ODMID0: `0x408`; ODMID1: `0x40c`.

SN is 10 bytes. `core/drivers/tegra/common/tegra_driver_fuse.c:fuse_generate_sn()`
handles ODM_INFO and ODMID byte order differently.
Simply concatenating numeric representations does not ensure agreement with EKB SN.
Define concrete test values and expected byte sequences before implementation.

With existing `CFG_TEGRA_SE_USE_TEST_KEYS=y`, a zero OEM key valid bit in BSI causes CCC to receive all-zero test OEM keys.
That operation itself still requires SE behavior; it does not eliminate eFuse dependencies.

## Passing MB2 outputs through DT

Inspected comments in official `optee/tegra234-optee.dts` and its consumers.
Before attempting to run all of MB2, test firmware will construct equivalent input structures.

- Describe non-secure memory with `device_type = "memory"` and reg, without overlapping Secure RAM.
- Supply compatible, reg, and secure-status for Fuse/SE/RNG1.
- Pass EKB through reg in `jetson-ekb-blob`; its consumer copies and then erases the original, so writable RAM is required.
- Place fTPM seed, Firmware ID private key, and certificate in Secure RAM and describe them through the corresponding node reg properties.
- Configure TPM event log and boot-mode according to the implementation stage.

Do not enable unimplemented DT nodes to create fictitious healthy state during initial log testing.
Before fTPM testing, verify consistency of EKB, storage keys, and Fuse SN.

## Stages and acceptance criteria

| Stage | Implementation | Acceptance criteria |
| --- | --- | --- |
| A: first log | Dedicated machine, Secure CPU/RAM, TCU, minimal EL3 boot, test DT | Unmodified tee-raw.bin prints OP-TEE logs; stopping location and unimplemented MMIO can be recorded |
| B: initialization complete | Fuse, SE/randomness, required DT inputs, SMC return | Reaches OP-TEE ENTRY_DONE; evaluate initcall failures, panics, and unimplemented MMIO rather than ignoring them |
| C: Linux integration | Secure Monitor, non-secure Linux, OP-TEE driver, tee-supplicant | TA invocation and persistent REE FS work |
| D: basic fTPM | fTPM driver, tpm2-tools, virtual-device state persistence | Verify GetCapability, PCR operations, NV, keys, seal/unseal, and reuse after reboot |
| E: device identity | Consistent Fuse/seed/EKB/EK certificates | Stable keys for one virtual device, isolation between devices, and defined clear/clone/snapshot behavior |

Stage A implementation and tests are recorded in [t234-stage-a.md](t234-stage-a.md); Stage B is next. For the initial configuration, Start with one TCG CPU and verify Pointer Authentication support.
Do not assume exact Cortex-A78AE or 12-core emulation.
Stage A log output alone must not be reported as successful OP-TEE initialization or equivalent fTPM behavior.

See the [implementation procedure](implementation-plan.md) for work order, code layout, checks, and completion criteria.

See [t234-fuse.md](t234-fuse.md) for the current read-only Fuse model and validation results.
