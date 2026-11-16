# Option B: NVIDIA fTPM functional QEMU profile

[日本語](../ftpm-virt.md) | English

> Current status: B2 helper PTA APIs, fTPM commands, persistence and test certificates bound to actual EKs verified. See [results and current reproduction steps](ftpm-functional-validation.md).


See [alternatives and decision](decisions/0001-ftpm-execution-path.md). The QEMU `jetson-ftpm-virt` machine derives from `virt`.
It uses the `vexpress-qemu_armv8a` platform in NVIDIA R36.5.2 OP-TEE and builds the NVIDIA fTPM TA for ARM64 without modifying its source.
The T234-specific `jetson-t234-dev` machine and Fuse model remain available separately.

## Boot path

QEMU → NVIDIA-bundled TF-A 2.8 (existing QEMU platform) → OP-TEE → Linux entry shim → NVIDIA Linux 5.15.199-tegra → Ubuntu 22.04 ARM64.
TF-A is included under `firmware/tf-a`; the small Linux entry shim is under `firmware/linux-entry`.
The Linux Image and matching fTPM kernel module are unmodified NVIDIA BSP binaries.
Linux is loaded at `0x60200000`. The shim places the DT address `0x40000000` in x0 and jumps to Linux.
The fTPM TA is embedded as an Early TA. A `microsoft,ftpm` DT node binds the Linux driver.

## Replacement for physical eFuses

This functional profile uses a persistent 72-byte file, mapped into a secure-only read-only page at `0x0c200000`, instead of reproducing Fuse registers.
The format is eight bytes `JFTPM001`, 32 secret random bytes, and 32 public device-ID bytes.
The file is generated once with mode 0600 and never automatically replaced.
The current OP-TEE HUK API consumes the first 16 secret bytes; the remainder is reserved.
Only `CFG_QEMU_DEVICE_IDENTITY=y` enables the additional OTP implementation.
B2 replaces the prototype HUK-derived EPS with the original NVIDIA helper PTA EPS path ([details](ftpm-helper-port.md)).
No shared constant HUK is used. The TA's EPS retrieval code remains unchanged.

Keep `work/ftpm-virt/device-identity.bin`, `provisioning.bin`, and `rootfs.ext4` together. The disk includes the encrypted REE filesystem under `/data/tee`.
Neither belongs in Git. Copying them clones the TPM identity; create new state for a different device.
This profile does not protect secrets from the host administrator, resist physical tampering, or prevent storage rollback.

## Reproduction

Requirements: native host tools, Python3, NVIDIA's AArch64 GCC, dtc, and the cryptography, pycryptodome and pyelftools Python packages.
See the [implementation plan](implementation-plan.md) for restoring NVIDIA components and building its OP-TEE client.

```bash
scripts/build-qemu.sh
# Configure the NVIDIA toolchain prefix and dtc/Python environment.
export CROSS_COMPILE=/path/to/aarch64-buildroot-linux-gnu-
scripts/build-ftpm-virt-firmware.sh
scripts/fetch-ftpm-virt-kernel.py
sudo env FTPM_FUNCTIONAL_PROFILE=1 KERNEL_MODULES_DIR="$PWD/work/ftpm-virt/modules" \
  scripts/build-ubuntu-rootfs.sh /path/to/optee/install/t234 work/ftpm-virt/rootfs.tar
sudo bash scripts/create-ftpm-virt-disk.sh
# For B2, select key/certificate data and pack provisioning.bin as documented in ftpm-helper-port.md.
scripts/prepare-ftpm-virt-dtb.sh
scripts/run-ftpm-virt.sh first 2>&1 | tee work/ftpm-virt/first.log
scripts/run-ftpm-virt.sh second 2>&1 | tee work/ftpm-virt/second.log
```

Run the first phase only on a fresh disk. The second starts a separate QEMU process with the same identity file and disk.
Success prints `FTPM_TEST: PASS phase=first` or `second`, then powers off the guest.
A timeout or failure is not success. Do not delete an existing test disk to rerun the first phase.
The functional-test systemd service runs only with the dedicated profile and the `ftpm.test` kernel argument.

## Test scope and limitations

The tests cover GetCapability, GetRandom, NV read/write, RSA signing with OpenSSL verification, seal/unseal, PCR extend,
and NV/key/sealed-object persistence with PCR reset after fully stopping QEMU.
Tegra SE, hardware key slots, manufacturing EK certificates, and Measured Boot are outside this functional profile.
It uses `CFG_TA_MEASURED_BOOT=n`. PCR command functionality does not demonstrate boot measurement equivalence.

## Boot results before the B2 port

The [machine-readable result](../results/ftpm-virt-boot.json) and [actual log excerpt](../results/ftpm-virt-boot-excerpt.txt) are preserved.
Linux's OP-TEE driver, Ubuntu multi-user target, and tee-supplicant start successfully.
The helper PTA load returns `ITEM_NOT_FOUND`; fTPM functionality is therefore not claimed.
[The complete PTA port was selected](decisions/0002-ftpm-helper-pta.md) to address this absence. This log preserves the pre-port history.
Ubuntu systemd-sysusers and systemd-resolved service failures also remain; overall Ubuntu service health is unverified.
The DT reserves all secure RAM using memreserve so Linux cannot allocate it.

See the [service comparison](optee-service-comparison.md) for daemon/TA/PTA roles and B1/B2 API differences.
