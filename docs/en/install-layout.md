# Local install layout for built artifacts

[日本語](../install-layout.md) | English

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

```bash
bash scripts/build-qemu.sh
# Run in the shell configured above.
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

## After the build: first boot and tests

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

DTBs are installed into install/share/qemu-jetson/ftpm-virt/runtime-*.dtb.

### 5. Run the initial test

```bash
bash scripts/run-ftpm-virt.sh first
```

This boots automatic guest tests rather than an interactive login session.
PTA_TEST verifies signing/certificate APIs; FTPM_TEST checks NV, PCR, signing and seal/unseal.
Success prints FTPM_TEST: PASS phase=first and powers the guest off.
Check failures/timeouts before proceeding; neither counts as success.

### 6. Run reboot/persistence tests on the same disk

Run only after the first phase passes. Do not repeat first.

```bash
bash scripts/run-ftpm-virt.sh second
```

Reuse the same keys/disk and check NV data, signing key and sealed-data persistence plus PCR reset.
Success prints FTPM_TEST: PASS phase=second and powers off.
Normal-world logs go to the terminal; secure logs go to work/ftpm-virt/secure-<phase>-native.log.

Actual EK certificate binding and standard certificate NV-index verification follow through export, bind-ftpm-test-ek.py and bound.
See the [full reproduction commands](ftpm-functional-validation.md#reproduction).

## Override install/build directories

```bash
INSTALL_DIR="$PWD/local-sdk" bash scripts/build-qemu.sh
INSTALL_DIR="$PWD/local-sdk" bash scripts/build-optee-client.sh
INSTALL_DIR="$PWD/local-sdk" bash scripts/prepare-ftpm-virt-dtb.sh
INSTALL_DIR="$PWD/local-sdk" bash scripts/run-ftpm-virt.sh second
```

INSTALL_DIR defaults to install/; relative paths resolve against the repository.
QEMU_BUILD_DIR changes only compilation intermediates, not the executable selected at launch.
Exclude custom output prefixes from Git yourself; the default install/ is ignored.

## Device state and rootfs

work/ retains intermediates and mutable per-device state.
Installation never copies, regenerates or deletes device-identity.bin, provisioning.bin, CA private keys, seeds or rootfs.ext4.
Launch combines installed binaries/read-only boot payloads with existing work/ftpm-virt/ state.

Rootfs assembly defaults to installed guest clients, libraries and modules.

```bash
sudo env FTPM_FUNCTIONAL_PROFILE=1 bash scripts/build-ubuntu-rootfs.sh
python3 scripts/prepare-ftpm-test-rootfs.py work/ftpm-virt/rootfs.tar work/ftpm-test-provisioning
sudo bash scripts/create-ftpm-virt-disk.sh
```

build-ubuntu-rootfs.sh OUTPUT_TAR changes the output archive.
The previous CLIENT_INSTALL_DIR OUTPUT_TAR form remains supported.
Existing disks/archives are not overwritten. A fresh privileged full rootfs assembly remains unverified in this execution environment.

## Validation

Check installed QEMU with installed ROMs using stock virt.
Compile clients/probe with installed headers, ARM64 libraries and the installed TA SDK.
Boot installed QEMU, firmware, kernel Image and DTB against preserved NV state.
Check secret/state exclusion and a custom install prefix containing spaces.
See the [result](../results/install-layout.json) and [boot excerpts](../results/install-layout-excerpt.txt).
