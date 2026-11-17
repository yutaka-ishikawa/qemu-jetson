# OP-TEE sample import candidates

[日本語](../sample-import-candidates.md) | English

Investigated on 2026-11-17 (Japan time). samples/ftpm-helper-probe was added as requested.
The user selected B; hello_world, random, secure_storage, aes and sign_verify have been imported.

## Recommended source

[linaro-swg/optee_examples](https://github.com/linaro-swg/optee_examples) contains OP-TEE samples.
Its [LICENSE](https://github.com/linaro-swg/optee_examples/blob/master/LICENSE) defaults to BSD-2-Clause, with individual file licenses taking precedence.
The inspected hello_world/host/main.c and secure_storage/ta/secure_storage_ta.c explicitly identify BSD-2-Clause.
On import, pin the source commit and review/preserve licenses and copyright notices for every imported file.
Do not track master blindly; verify build/runtime compatibility with this repository's NVIDIA OP-TEE SDK.

| Candidate | Demonstrates | Benefits and limitations |
| --- | --- | --- |
| hello_world | Sessions and TA commands | Minimal introduction; no TPM-specific functionality |
| random | TA-side random generation and result transfer | Short basic API example; not randomness certification |
| secure_storage | Persistent TA objects | Can test persistence across reboot; current REE filesystem does not establish resistance to host rollback |
| aes | TA-side symmetric encryption | Crypto API introduction; broadens the initial scope |
| sign_verify | TA-side signing and verification | Crypto API without TPM; distinct from EK/Firmware ID signatures |

## Presented alternatives

- A (recommended): hello_world, random and secure_storage, covering basic calls and persistence.
- B: A plus aes and sign_verify, adding crypto API coverage and validation work.
- C: Record candidates only and decide on additional imports later.

Status: the user selected B. All five examples are imported under samples/ from commit 71e8f3f320eef46a9369700bf30b91d67427d535. See samples/optee-examples-source.json for licensing and file hashes. Actual builds and guest execution remain unverified.

## Bundled NVIDIA samples

optee/optee/samples already contains ftpm-helper, hwkey-agent, luks-srv, ms-tpm and pkcs11-sample.
pkcs11-sample/LICENSE has BSD-style terms, but licensing alone does not establish compatibility with B2.
Samples such as hwkey-agent depend on Tegra-specific PTAs/key paths and are not recommended as immediately runnable introductory samples for QEMU B2.
