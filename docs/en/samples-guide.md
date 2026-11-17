# Building and running OP-TEE samples

[日本語](../samples-guide.md) | English

[samples/ftpm-helper-probe](../../samples/ftpm-helper-probe/) builds a Linux client and a test TA relaying calls to the real NVIDIA helper PTA.
It is copied from tests/ftpm-helper-probe, not a replacement for the PTA.
Host cross-compilation and guest-native compilation below are alternatives; there is no need to do both.

## Cross-compile on the host

Complete firmware/client builds and the venv/CROSS_COMPILE configuration in [build-install.md](build-install.md). From the repository root:

```bash
make -C samples/ftpm-helper-probe
```

Default outputs are work/samples/ftpm-helper-probe/ftpm-helper-probe and ta/7fc1d460-5a6c-4a5f-9b9e-6c298d3032a0.ta underneath it.
The build uses install/include, install/lib/aarch64-linux-gnu and install/lib/optee/ta-dev-kit-aarch64.
Override INSTALL_DIR, TA_DEV_KIT_DIR, TA_SIGN_KEY or O as make variables.
The default TA_SIGN_KEY is the repository's publicly available development private key, not a production key.

## Build and run inside QEMU

### 1. Host: prepare the share

Host cross-compilation of the sample is unnecessary, but firmware/client artifacts must already be built and installed.
Configure the cradsec account and sudo using [runtime-guide.md](runtime-guide.md).
From the repository root, run once; inspect existing share contents before repeating.

```bash
mkdir -p work/sample-share/sdk/lib
cp -a samples/ftpm-helper-probe work/sample-share/
cp -a install/include work/sample-share/sdk/
cp -a install/lib/aarch64-linux-gnu work/sample-share/sdk/lib/
mkdir -p work/sample-share/sdk/lib/optee
cp -a install/lib/optee/ta-dev-kit-aarch64 work/sample-share/sdk/lib/optee/
cp optee/optee/optee_os/keys/default_ta.pem work/sample-share/default_ta.pem
chmod -R a+rX work/sample-share
bash scripts/run-ftpm-virt.sh --ssh --share "$PWD/work/sample-share"
```

Share only sources, SDK and the publicly available development TA key, rather than the entire repository.
Do not copy CA/Firmware ID private keys, device identity, provisioning or disks.
If OP-TEE uses a custom TA signing key, supply the corresponding development key locally.

### 2. Guest: mount manually and prepare the build tools

Log in as cradsec over the console or SSH. The share is read-only; copy it into the guest home to build.
Guest internet access is required for apt.

```bash
sudo qemu-mount-host
sudo apt-get update
sudo apt-get install -y build-essential python3 python3-cryptography python3-pycryptodome python3-pyelftools
mkdir -p "$HOME/optee-samples"
cp -a --no-preserve=ownership /mnt/host/. "$HOME/optee-samples/"
cd "$HOME/optee-samples"
make -C ftpm-helper-probe CROSS_COMPILE= INSTALL_DIR="$PWD/sdk" TA_SIGN_KEY="$PWD/default_ta.pem" O="$PWD/build"
```

The ARM64 guest uses native gcc with CROSS_COMPILE empty.
Run make as the regular user, without sudo. Outputs go to ~/optee-samples/build/.
Use a matching SDK, libteec and running OP-TEE configuration.

### 3. Guest: install the TA and run the client

Use normal boot; do not run the probe concurrently with automated tests.
This TA uses the existing test relay's UUID and replaces that test TA if already installed.

```bash
cd "$HOME/optee-samples"
sudo install -m 0644 build/ta/7fc1d460-5a6c-4a5f-9b9e-6c298d3032a0.ta /usr/lib/optee_armtz/
mkdir -p run
cd run
LD_LIBRARY_PATH="$HOME/optee-samples/sdk/lib/aarch64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ../build/ftpm-helper-probe
```

On Ubuntu's merged /usr, tee-supplicant's /lib/optee_armtz resolves to /usr/lib/optee_armtz.
Only TA installation requires sudo; run the client as cradsec.
Check PTA_TEST PASS messages and exit status 0. Certificates, CSRs and signatures are written to run/.
The standalone probe does not cryptographically verify certificate chains or signatures.
For full existing functional tests, see [test-guide.md](test-guide.md).
For TA load errors, check UUID, installation path, the accepted TA signing key and tee-supplicant status.

## Validation status

The original tests copy runs in existing B2 tests. For this sample, make dry-runs (including the TA submake), host-side C syntax checking and documentation shell syntax checks were performed. The cross-compiler is unavailable in the current environment, so compilation, linking and TA signing were not executed.
The new guest apt/make/TA-install/run procedure has not been executed in this development environment; it is not claimed as verified.
