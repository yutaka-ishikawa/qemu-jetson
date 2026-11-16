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

## Build and install

```bash
bash scripts/build-qemu.sh
# Configure NVIDIA CROSS_COMPILE, dtc and the Python venv first.
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
