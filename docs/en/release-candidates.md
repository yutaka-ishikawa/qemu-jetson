# Jetson Linux release candidates

[日本語](../release-candidates.md) | English

Investigation date: November 16, 2026 (Japan time). This record describes the initial review of official web documentation.
At that stage, source extraction, per-file license review, builds, and QEMU execution had not been performed.

## Candidates and recommendation

| Priority | JetPack / L4T | Officially confirmed information | Assessment |
| --- | --- | --- | --- |
| First candidate | 6.2.3 / R36.5.2 | Orin Nano support; Ubuntu 22.04, Linux 5.15, OP-TEE; BSP source and Bootlin GCC 11.3 links; fTPM build/provisioning instructions | Recommended starting point for source investigation, incorporating fixes in the R36 series |
| Comparison | 6.2.1 / R36.4.4 | Orin Nano support; Ubuntu 22.04, Linux 5.15; OP-TEE/fTPM documentation; BSP source and Bootlin GCC 11.3 links | Baseline for comparing the earlier fTPM implementation if relevant differences arise |
| New series | 7.2.1 / R39.2.1 | Orin support; Ubuntu 24.04, Linux 6.8; BSP source and Crosstool-NG links; fTPM documentation explicitly includes Orin Nano | Viable for a new environment, but fTPM implementation and EK compatibility changes require evaluation |

R35.7 / JetPack 5.1.8 also supports Orin Nano and OP-TEE, but the FirmwareTPM.html URL checked returned 404.
This does not prove fTPM is unsupported. Without an existing JetPack 5 compatibility requirement, it is not a priority.
The official archive leaves Orin Nano support blank for R38, so that series is excluded.

No release had yet been demonstrated to minimize NVIDIA source changes.
Recommending R36.5.2 as a starting point was neither a QEMU compatibility guarantee nor a final selection.

## fTPM differences between series

The R39.2.1 fTPM documentation compares R36.4.4 GA with R38.4 GA and later:

- R36.4.4: ms-tpm-20-ref commit `e9fc7b89d865536c46deb63f9c7d0121a3ded49c`, TPM specification Revision 1.59, TA in Samples.
- R38.4 and later: specification Revision 1.84, TA moved to OP-TEE/optee_ftpm.
- RSA EK generation is incompatible with the earlier implementation.
- Upgrading to OP-TEE 4.4.0 changes the default REE FS location from `/data/tee` to `/var/lib/tee/`.

Do not infer the internal R36.5.2 commit from this comparison; inspect the distribution.
User-visible fTPM equivalence requires a fixed target release.

## Important eFuse findings

The R36.5.2 fTPM documentation describes this flow:

1. Derive Silicon_ID from KDK0 and Device_SN at the PSCBL layer.
2. Derive the fTPM Seed and Silicon ID Key Seed at the MB2 layer.
3. Pass the fTPM Seed to OP-TEE through encrypted TZ memory.
4. The fTPM Helper PTA derives EPS using that value and EPS_Seed from EKB, among other inputs.
5. Inject EPS into the fTPM TA on first initialization and store it in NV.

Key generation involves TZ-SE and key slots inaccessible to the CPU.
Reproducing Fuse register values alone cannot yet be considered sufficient.
Inspect sources to determine how much real boot behavior must be reproduced and whether QEMU can construct equivalent input state while preserving NVIDIA code.

## Next step at this stage

Inspect `nvidia-jetson-optee-source.tbz2`, `atf_and_optee_README.txt`, fTPM sources, and build configuration from the official R36.5.2 BSP source distribution.
Official OP-TEE instructions point to this nested archive and README.
Record hashes, source versions, and individual licenses before building; check redistribution conditions before importing third-party sources.

## Official references

- [Jetson Linux Archive](https://developer.nvidia.com/embedded/jetson-linux-archive)
- [R36.5.2 release and downloads](https://developer.nvidia.com/embedded/jetson-linux-r3652)
- [R36.5.2 OP-TEE](https://docs.nvidia.com/jetson/archives/r36.5.2/DeveloperGuide/SD/Security/OpTee.html)
- [R36.5.2 fTPM](https://docs.nvidia.com/jetson/archives/r36.5.2/DeveloperGuide/SD/Security/FirmwareTPM.html)
- [R36.4.4 release and downloads](https://developer.nvidia.com/embedded/jetson-linux-r3644)
- [R36.4.4 fTPM](https://docs.nvidia.com/jetson/archives/r36.4.4/DeveloperGuide/SD/Security/FirmwareTPM.html)
- [JetPack 7.2.1 / R39.2.1 downloads](https://developer.nvidia.com/embedded/jetpack/downloads/archive-7.2.1)
- [R39.2.1 fTPM compatibility notes](https://docs.nvidia.com/jetson/archives/r39.2.1/DeveloperGuide/SD/Security/FirmwareTPM.html)
- [R35.7 release](https://developer.nvidia.com/embedded/jetson-linux-r357)
