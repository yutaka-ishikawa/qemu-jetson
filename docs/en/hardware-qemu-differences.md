# Differences between physical Jetson hardware and QEMU

[日本語](../hardware-qemu-differences.md) | English

This compares Jetson Orin Nano (T234) with this repository's B2 functional profile, jetson-ftpm-virt.

**B2** names the approach that **ports the complete NVIDIA helper PTA and its dependencies**, within [option B (decision 0001)](decisions/0001-ftpm-execution-path.md), which runs fTPM using the NVIDIA OP-TEE QEMU configuration.
See [the B2 definition and selection rationale (decision 0002)](decisions/0002-ftpm-helper-pta.md). It is not an NVIDIA product or release name.
The [helper PTA port design](ftpm-helper-port.md) describes the implementation scope.

Passing QEMU tests does not establish identical hardware, every TPM command, or security strength.
No controlled physical-device comparison has been performed. Hardware protection depends on product configuration and manufacturing provisioning.

## Is QEMU itself modified?

**Yes.** This repository directly modifies the vendored QEMU 11.1.3 sources.
This is not an unmodified upstream QEMU configured solely through command-line options.

The principal B2 addition is [jetson-ftpm-virt.c](../../qemu/hw/arm/jetson-ftpm-virt.c),
which registers jetson-ftpm-virt as a subclass of the upstream virt machine.

| Addition | Behavior |
| --- | --- |
| identity-file | Validates a 72-byte JFTPM001 image and exposes it in a 4KiB ROM region at secure address 0x0c200000 |
| provisioning-file | Validates JFPRV001 input and provides 64KiB RAM at secure address 0x0c400000, allowing the PTA to copy and erase handoff data |
| Reset | Restores provisioning RAM from the retained initial image; QEMU does not rewrite the host input file |
| Configuration restrictions | Rejects identity-file/provisioning-file changes after initialization |
| Build integration | Adds the custom machine source in [meson.build](../../qemu/hw/arm/meson.build) |

This supplies virtual identity and provisioning data; it does not reproduce the physical Fuse Controller or SE.
Secure address-space placement separates guest access, not protection against the host administrator.
TPM commands are handled by the NVIDIA fTPM TA inside the guest, not replaced by another TPM implementation in QEMU.
The current [launcher](../../scripts/run-ftpm-virt.sh) uses neither QEMU -tpmdev nor swtpm.

There are also custom T234 hardware-model changes including [jetson-t234-dev.c](../../qemu/hw/arm/jetson-t234-dev.c).
That fuse-model path must be distinguished from the passing B2 profile.
OP-TEE additionally has QEMU platform adaptations and the [table-capacity change](page-table-analysis.md).
Keeping NVIDIA TA/PTA bodies minimally changed does not imply unmodified QEMU or OP-TEE platform code.

## Platform and software

| Item | Physical Jetson | Current QEMU B2 |
| --- | --- | --- |
| CPU and peripherals | Orin Nano Cortex-A78AE and Tegra peripherals | virt-based machine; launcher selects Cortex-A57, default four CPUs (1..8 selectable), 1GiB RAM and GICv3 |
| NVIDIA development tools | Jetson cross-build environment | Rebuilds target software using NVIDIA's toolchain; arbitrary unmodified Jetson binary execution is not guaranteed |
| Linux | Matching L4T kernel and Tegra drivers | NVIDIA L4T R36.5.2 Image, 5.15.199-tegra, and matching fTPM modules; Tegra peripherals are only partially modeled |
| Userland | Depends on distribution image and packages | Ubuntu 22.04 ARM64 base plus required services/tools; not a complete Jetson userland clone |
| OP-TEE | T234 platform | vexpress-qemu_armv8a with the NVIDIA helper PTA and adapted data providers |
| fTPM/helper TAs | NVIDIA TAs | Rebuilt NVIDIA sources. Existing hash checks verify the tested TA/PTA bodies; platform code is adapted |
| GPU/CUDA | Physical GPU | Not provided; outside current requirements |
| Boot | Jetson product boot chain | QEMU TF-A, OP-TEE and Linux entry shim; not a reproduction of BootROM, MB1/MB2 or the complete product Secure Boot chain |
| I/O and timing | Physical storage and interrupts | virtio-blk and virtual UARTs; performance, concurrency, timeouts and real-time equivalence are unverified |
| Networking | Device configuration | Default -nic none; --ssh enables virtio-net/user networking and localhost forwarding for regular-user public-key SSH |

## eFuse, keys, certificates and persistence

| Item | Physical Jetson | Current QEMU B2 |
| --- | --- | --- |
| eFuse | OTP identity, settings and secrets with hardware-specific programming/protection | File-backed identity/secrets and provisioning supplied to the PTA; no irreversible OTP semantics |
| SE and key slots | Tegra cryptographic hardware and hardware key paths | Does not reproduce the full SE, physical key slots or hardware non-extractability |
| Identity and seeds | Manufacturing/provisioning paths | Persistent device-identity.bin, provisioning.bin and related work files; host administrators can read, replace or clone them |
| SN and ECID | Read and derived from physical fuses | Test values supplied through B2 APIs, not a manufacturing identity |
| EK certificates | Product-specific issuer and trust chain | QEMU-only test CA; actual virtual fTPM EK matching and NV readback are tested, without NVIDIA manufacturing trust |
| SIGN_EK_CSR | NVIDIA helper Firmware ID signing path | Verified with a test Firmware ID key; distinct from EK-private-key signatures and manufacturing CA certificate issuance |
| TPM access | OP-TEE, kernel driver and clients | Tests TPM commands through /dev/tpmrm0 and helper PTA APIs; exhaustive command equivalence is unverified |
| Persistence | Depends on product storage configuration | NV, keys, sealed data and EK certificates tested across separate QEMU processes using the same disk, identity and seeds |
| Protection and rollback | Depends on hardware and storage configuration | REE filesystem; no protection against host disk rollback, secret extraction or VM cloning |
| Randomness | Hardware random/crypto services | QEMU uses host /dev/urandom and virtio-rng; no claim of physical entropy-source or certification equivalence |

Not exporting an EK private key through guest TPM APIs does not imply protection against the host administrator.
Copying identity, seeds and disk together can clone virtual TPM state.
All combinations of TPM Clear, OS reinstall, snapshots and live migration remain unverified.

## Functional and configuration limits

- PCR extend and reboot reset are tested, but Measured Boot is disabled. Physical boot measurements and event logs are not reproduced.
- INJECT_EPS is disabled; rejection is tested.
- Guest SELinux is omitted from the selected LSM list under approved option A. Host SELinux is unchanged; this is not equivalent to a product access-control configuration.
- Only the QEMU fTPM profile increases OP-TEE MAX_XLAT_TABLES from 8 to 32. The original limit caused a table-exhaustion panic.
  Tests pass with 32; worst-case headroom is unmeasured. Physical memory layout and table requirements must not be assumed identical.
- Coverage includes capabilities, randomness, NV, PCR, RSA signatures, seal/unseal, helper APIs, certificates/CSRs/Firmware ID signatures, actual EK matching and standard certificate NV indices.
  It is not exhaustive for every TPM command, OS service, remote authentication or physical attack resistance.

## Separate jetson-t234-dev profile

The [read-only fuse model](t234-fuse.md) belongs to the separate jetson-t234-dev hardware-emulation profile.
Supported register reads and NVIDIA SN/ECID conversion functions are tested; OTP programming, secret fuses and SE are not implemented, and boot stops at SE0 initialization.
B2 fTPM PASS does not imply completion of the T234 profile.

## Evidence and intended use

See [build/install](build-install.md), [tests](test-guide.md), [helper PTA port](ftpm-helper-port.md),
[CSR signing](ek-csr-signing.md), and [earlier functional results](ftpm-functional-validation.md).
Use this environment to develop and test NVIDIA fTPM/helper software functions, API integration, persistence and certificate processing.
It does not replace product trust/protection or final verification on physical hardware.

[Table measurements](page-table-analysis.md) reached 9/32 on QEMU; this is not a physical-device usage measurement.

See [interactive runtime](runtime-guide.md) for SSH, 9p and debugging. Earlier table measurements used one CPU and do not establish four/eight-CPU worst-case usage.
