# OP-TEE samples

[日本語](README.md) | English

| Sample | Purpose |
| --- | --- |
| [ftpm-helper-probe](ftpm-helper-probe/) | C client exercising the NVIDIA helper PTA through a test relay TA |
| [hello_world](hello_world/) | TA calls and value transfer |
| [random](random/) | TA-side random generation |
| [secure_storage](secure_storage/) | Persistent objects |
| [aes](aes/) | AES encryption/decryption |
| [sign_verify](sign_verify/) | Signing and verification |

See the [sample guide](../docs/en/samples-guide.md) for building, including make and execution inside QEMU.
ftpm-helper-probe is copied from tests/ftpm-helper-probe. Existing automated tests continue to use the tests copy.
See [import candidates](../docs/en/sample-import-candidates.md). The user selected B; all five examples are imported.
