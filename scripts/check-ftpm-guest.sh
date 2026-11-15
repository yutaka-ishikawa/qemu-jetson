#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -m) == aarch64 ]] || { echo 'Run inside the ARM64 guest.' >&2; exit 1; }
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 22.04 ]] || { echo 'Ubuntu 22.04 is required.' >&2; exit 1; }
[[ -c /dev/teepriv0 ]] || { echo 'Missing /dev/teepriv0: check OP-TEE firmware, DT and kernel driver.' >&2; exit 1; }
systemctl is-active --quiet jetson-tee-supplicant.service
[[ -c /dev/tpmrm0 ]] || { echo 'Missing /dev/tpmrm0: check the fTPM TEE driver and TA.' >&2; exit 1; }
export TPM2TOOLS_TCTI=device:/dev/tpmrm0
tpm2_getcap properties-fixed
tpm2_pcrread sha256:0
printf 'PASS: basic TPM queries only; persistence and attestation are not tested.\n'
