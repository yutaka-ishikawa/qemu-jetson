# Build and installation guide

This guide covers host setup, builds, artifact installation, Ubuntu disk creation and boot DTBs.
All test execution starts in [test-guide.md](test-guide.md).

[日本語](../build-install.md) | English

[Decision 0005](decisions/0005-install-prefix.md) makes the repository's install/ the default artifact prefix.
Installation runs as the ordinary user and does not install project binaries system-wide into /usr/local.

```text
install/
├── bin/                         Host QEMU
├── include/                     Public OP-TEE client headers
├── lib/
│   ├── aarch64-linux-gnu/        ARM64 libteec and other .so/.a files
│   │   └── optee_armtz/          fTPM/helper/probe TAs
│   ├── optee/ta-dev-kit-aarch64/ TA headers, libraries and make files
│   └── modules/                 Guest NVIDIA kernel modules
├── libexec/aarch64-linux-gnu/    Guest supplicant, management app and probe
└── share/
    ├── qemu/                    QEMU ROMs/data
    └── qemu-jetson/
        ├── ftpm-virt/           flash.bin, Image, runtime-*.dtb, Linux entry
        ├── optee/               OP-TEE images and debug ELF
        ├── tf-a/                BL1/BL2/BL31 and FIP
        └── t234/                T234 harness firmware
```

Keep host QEMU separate from guest ARM64 programs; guest binaries run inside the guest.
The NVIDIA kernel fetch script also installs its Image and modules after retrieval.
Host dependency libraries such as GLib remain host packages, not redistributed here.

## Start from a fresh clone

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/yutaka-ishikawa/qemu-jetson.git
cd qemu-jetson
```

This guide creates a new environment. If work/ already contains a disk or credentials, use [upgrade-guide.md](upgrade-guide.md).
Fresh rootfs assembly includes runtime services, SSH, sudo and dbus. Do not run the offline runtime updater or guest package installer after a fresh build.

## Explicit build environment setup (x86_64 Ubuntu)

These commands target an **x86_64 Ubuntu 22.04+ host**. Run them from the cloned repository root.
Check that `uname -m` prints `x86_64`. This NVIDIA-distributed toolchain runs on x86_64 and generates ARM64 guest code.

### 1. Host tools including dtc

```bash
sudo bash scripts/install-host-deps.sh
command -v dtc
dtc --version
```

`dtc` is the Device Tree Compiler. The installer includes the host `device-tree-compiler` package.

### 2. NVIDIA-specified cross compiler

The validated toolchain is Bootlin Buildroot 2022.08, GCC 11.3.0.
Download NVIDIA's archive and extract it under work/toolchains/.

```bash
mkdir -p work/downloads work/toolchains
curl -fL --retry 3 \
  https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v3.0/toolchain/aarch64--glibc--stable-2022.08-1.tar.bz2 \
  -o work/downloads/aarch64--glibc--stable-2022.08-1.tar.bz2
printf '%s  %s\n' \
  8af54f268c462b2d0737df8789b5e35db03a2d1ecbec90e20948f66f9244fcdd \
  work/downloads/aarch64--glibc--stable-2022.08-1.tar.bz2 | sha256sum -c -
# Extract once; skip this tar command if already extracted.
tar -xjf work/downloads/aarch64--glibc--stable-2022.08-1.tar.bz2 -C work/toolchains
export CROSS_COMPILE="$PWD/work/toolchains/aarch64--glibc--stable-2022.08-1/bin/aarch64-buildroot-linux-gnu-"
"${CROSS_COMPILE}gcc" --version
"${CROSS_COMPILE}gcc" -dumpmachine
```

CROSS_COMPILE is the compiler path/prefix **including the trailing hyphen**, not the gcc executable itself.
Build scripts append gcc, ar, objcopy, etc.
Expected outputs are GCC 11.3.0 and target aarch64-buildroot-linux-gnu.
If the toolchain is already installed elsewhere, change the directory in the export line.

#### Messages printed during assembly

A successful run can print messages like these near the end. Paths and temporary directory names vary.
This is sample output, not commands to execute.

```text
Executing: /lib/systemd/systemd-sysv-install enable ssh
Usage: tee-supplicant [options] [<device-name>]
        -h, --help: this help
        ...
tool="tpm2_getcap" version="5.2" tctis="libtss2-tctildr" tcti-default=tcti-device
depmod: WARNING: could not open modules.order at /tmp/qemu-jetson-rootfs.XXXXXX/root/lib/modules/5.15.199-tegra: No such file or directory
Created /path/to/qemu-jetson/work/ftpm-virt/rootfs.tar
```

- `systemd-sysv-install enable ssh` is printed when enabling the SSH service.
- The `tee-supplicant` usage text comes from the setup script running `tee-supplicant --help` to check execution. It is not a startup failure caused by invalid arguments.
- The `tpm2_getcap` line is the corresponding `--version` check.
- The `modules.order` warning occurs because the selectively extracted kernel modules do not include that file. This warning alone does not mean rootfs assembly failed.

A final `Created .../rootfs.tar` message and exit status 0 indicate that the tar archive and SHA-256 file were generated.
This does not certify guest boot or fTPM test success. Do not delete or rebuild the rootfs solely because of these messages; continue with adding public verification inputs.
If `Created` is absent or the exit status is nonzero, inspect earlier errors. This guidance does not apply to other `depmod` errors.

### 3. Python venv

```bash
python3 -m venv work/venv
source work/venv/bin/activate
python3 -m pip install -r docs/build-python-requirements.txt
python3 -c 'import sys, cryptography, Crypto, elftools; print(sys.executable); print("OP-TEE Python dependencies: OK")'
```

The venv isolates build Python/packages from system Python.
The interpreter should be work/venv/bin/python3 inside this repository, and the imports must succeed.
pycryptodome provides the Crypto import; pyelftools provides elftools.

In a new terminal, run these two lines again from the same repository root:

```bash
source work/venv/bin/activate
export CROSS_COMPILE="$PWD/work/toolchains/aarch64--glibc--stable-2022.08-1/bin/aarch64-buildroot-linux-gnu-"
```

Do not repeat downloads, extraction or package installation for every build.
Run the build commands below as an ordinary user in that configured shell.
See the [baseline build record](r36.5.2-build.md) for archive provenance, checksum and validated environment details.

## Build and install

Run the following five commands in order in the same shell with the venv and CROSS_COMPILE configured above.

```bash
bash scripts/build-qemu.sh
bash scripts/build-ftpm-virt-firmware.sh
bash scripts/build-optee-client.sh
bash scripts/build-ftpm-helper-probe.sh
python3 scripts/fetch-ftpm-virt-kernel.py
```

Each successful build installs its artifacts. QEMU uses Meson install with the local prefix.
install-artifacts.py copies only known outputs for other components.
Signing private keys are excluded from the installed TA SDK. Probe builds use TA_SIGN_KEY or the repository's development signing key as an input.

To install existing outputs without recompiling:

```bash
python3 scripts/install-artifacts.py firmware
python3 scripts/install-artifacts.py kernel
python3 scripts/install-artifacts.py probe
python3 scripts/install-artifacts.py client --client-export /path/to/optee/install/t234/usr
```

## After the build: initial data, disk and DTB preparation

Once all five build/fetch commands above succeed, prepare the remaining inputs in this order.
These are first-time steps using the default install/ and work/ paths. Run from the repository root with the same venv active.
Reuse existing keys, provisioning image and disk; skip preparation already completed.
Do not delete existing state merely to repeat tests.

### 1. Create QEMU-only test CA, keys and certificates

```bash
source work/venv/bin/activate
python3 scripts/generate-ftpm-test-provisioning.py work/ftpm-test-provisioning
python3 scripts/pack-ftpm-provisioning.py \
  work/ftpm-test-provisioning/manifest.json \
  work/ftpm-virt/device-identity.bin \
  work/ftpm-virt/provisioning.bin
```

Firmware compilation already created device-identity.bin; do not replace it.
Credentials go under work/ftpm-test-provisioning/, and the PTA handoff image is work/ftpm-virt/provisioning.bin.
Initial RSA/EC certificates are API fixtures. Binding certificates to actual fTPM EKs happens later.

### 2. Assemble Ubuntu 22.04 ARM64 rootfs

```bash
sudo env FTPM_FUNCTIONAL_PROFILE=1 bash scripts/build-ubuntu-rootfs.sh
```

Use installed clients, libraries and kernel modules to create work/ftpm-virt/rootfs.tar.
FTPM_FUNCTIONAL_PROFILE=1 includes the boot-time test services.
Host apt/PRoot dependencies are required. A fresh privileged full native rootfs rebuild remains unverified in this execution environment.

### 3. Add public verification inputs and create the disk

```bash
python3 scripts/prepare-ftpm-test-rootfs.py \
  work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
sudo bash scripts/create-ftpm-virt-disk.sh
```

Add public certificates/CSRs and the installed probe, then create work/ftpm-virt/rootfs.ext4.
CA/Firmware ID private keys are not copied into the guest rootfs.
The disk is owned by the user who invoked sudo.

### 4. Generate boot DTBs

```bash
bash scripts/prepare-ftpm-virt-dtb.sh
```

The QEMU guest disables SELinux under option A of [decision 0006](decisions/0006-guest-selinux.md).
DTB bootargs include `lsm=lockdown,yama,integrity,apparmor,bpf`; host SELinux settings are unaffected.


DTBs are installed into install/share/qemu-jetson/ftpm-virt/runtime-*.dtb.

#### Warnings during DTB generation

`prepare-ftpm-virt-dtb.sh` decompiles the QEMU-generated DTB to DTS, adds boot arguments and other properties, then recompiles it to DTB.
During this process, `dtc` may print warnings like these. Line numbers, device ordering and repetition depend on the configuration.
This is sample output, not commands to execute.

```text
work/ftpm-virt/runtime-first.dts:274.3-21: Warning (clocks_property): /pl061@90b0000:clocks: cell 0 is not a phandle reference
work/ftpm-virt/runtime-first.dts:300.3-21: Warning (clocks_property): /pl031@9010000:clocks: cell 0 is not a phandle reference
work/ftpm-virt/runtime-first.dts:325.3-28: Warning (clocks_property): /pl011@9000000:clocks: cell 0 is not a phandle reference
work/ftpm-virt/runtime-first.dts:258.3-30: Warning (gpios_property): /gpio-restart:gpios: cell 0 is not a phandle reference
```

Decompiled DTS represents phandle references as numeric cells instead of `<&label>` expressions, which can trigger reference checks during recompilation.
These warnings alone do not mean DTB generation failed. Boot and fTPM tests have been verified using DTBs produced through this conversion path.

If the command exits with status 0 and installs `runtime-*.dtb` under `install/share/qemu-jetson/ftpm-virt/`, proceed to initial setup or tests.
Treat `Error`, syntax errors, a nonzero exit status or missing output artifacts as failures to investigate.
Do not indiscriminately ignore other warnings. Successful DTB generation and passing guest boot/fTPM tests are separate checks.

Build and installation are complete. For interactive use, continue with [initial account/key setup](runtime-guide.md#initial-setup-console). For functional validation, follow [test-guide.md](test-guide.md) from first. Do not run the same disk concurrently.
For an already tested disk, skip completed stages as directed there.

---

## Override install/build directories

Use the same INSTALL_DIR for builds, launches and DTB generation.

```bash
INSTALL_DIR="$PWD/local-sdk" bash scripts/build-qemu.sh
INSTALL_DIR="$PWD/local-sdk" bash scripts/build-optee-client.sh
INSTALL_DIR="$PWD/local-sdk" bash scripts/prepare-ftpm-virt-dtb.sh
```

INSTALL_DIR defaults to install/; relative paths resolve against the repository.
QEMU_BUILD_DIR changes only compilation intermediates, not the executable selected at launch.
Exclude custom output prefixes from Git yourself; the default install/ is ignored.

## Device state and rootfs

work/ retains intermediates and mutable per-device state.
Installation never copies, regenerates or deletes device-identity.bin, provisioning.bin, CA private keys, seeds or rootfs.ext4.
Launch combines installed binaries/read-only boot payloads with existing work/ftpm-virt/ state.

build-ubuntu-rootfs.sh OUTPUT_TAR changes the output archive.
The previous CLIENT_INSTALL_DIR OUTPUT_TAR form remains supported.
Existing disks/archives are not overwritten. A fresh privileged full rootfs assembly remains unverified in this execution environment.

## Validation

Check installed QEMU with installed ROMs using stock virt.
Compile clients/probe with installed headers, ARM64 libraries and the installed TA SDK.
Boot installed QEMU, firmware, kernel Image and DTB against preserved NV state.
Check secret/state exclusion and a custom install prefix containing spaces.
See the [result](../results/install-layout.json) and [boot excerpts](../results/install-layout-excerpt.txt).

## OP-TEE translation table change and the original failure

For QEMU ARMv8 with CFG_QEMU_JETSON_FTPM, OP-TEE's MAX_XLAT_TABLES was increased from **8 to 32** in
[platform_config.h](../../optee/optee/optee_os/core/arch/arm/plat-vexpress/platform_config.h).
NVIDIA fTPM/helper TA bodies and the physical T234 profile are unchanged.
With eight tables, the user's secure log showed (line numbers refer to that build):

```text
E/TC:0 0 core_mmu_xlat_table_alloc:520 8 xlat tables exhausted
E/TC:0 0 Panic 'Failed to spread pgdir on small tables' at core/mm/core_mmu.c:1922 <core_mmu_map_pages>
```

OP-TEE could not allocate lower-level translation tables for a memory mapping and panicked.
Linux output stopped near serial console handover; the launcher timed out before fTPM tests started.
The cause was identified in work/ftpm-virt/secure-first-native.log, not from the final Linux message alone.
Static table storage increased from 32KiB to 128KiB, an additional 96KiB.
This is compiled into firmware: regenerating DTBs alone is insufficient.
Initial builds already include the change. To update old firmware, stop QEMU and run in the configured build environment:

```bash
bash scripts/build-ftpm-virt-firmware.sh
bash scripts/prepare-ftpm-virt-dtb.sh
```

Installed flash.bin is updated. Linux, rootfs, disks, CA and keys need no recreation.
Select the next test using [test-guide.md](test-guide.md); do not rerun completed first tests.
Local validation passed PTA and second on an existing persistent disk.
On 2026-11-17 (Japan time), the user additionally reported all test-guide.md tests passed.
This final confirmation is user-reported, not independent reinspection of every corresponding log.
See the [local results](../results/optee-xlat-tables.json) and [excerpt](../results/optee-xlat-tables-excerpt.txt).
Update: the analysis linked below measures a path exceeding eight; worst-case demand remains unproven.
QEMU and physical T234 memory layouts differ; this result alone establishes neither failure nor immunity on hardware.

## Document organization decision

At the user request, the former install-layout.md became build-install.md for builds and installation.
Test document candidates were test-guide.md, ftpm-tests.md, testing.md and test-procedures.md; the user selected test-guide.md.
The former ftpm-test-guide.md was renamed and expanded to include the initial test. Both languages use the same separation.

## Related evidence and hardware differences

See [hardware differences](hardware-qemu-differences.md) and [final evidence](final-test-evidence.md).

See the [usage analysis](page-table-analysis.md): controlled ASLR seed probes reached 9/32 tables, leaving 23, and bound passed in that layout. This is not a worst-case guarantee.

See [interactive runtime, SSH, sharing and debugging](runtime-guide.md). The launcher now defaults to normal boot and four CPUs; select tests explicitly. Existing-environment upgrades are in [upgrade-guide.md](upgrade-guide.md).

The current four-guide separation follows option A of [decision 0009](decisions/0009-guide-organization.md): fresh build, normal use, tests and upgrades.
