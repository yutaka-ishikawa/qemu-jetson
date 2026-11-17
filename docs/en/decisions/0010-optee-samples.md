# 0010: Additional OP-TEE samples

[日本語](../../decisions/0010-optee-samples.md) | English

Status: the user selected B (2026-11-17, Japan time).

- A (presented as recommended): hello_world, random and secure_storage, covering basic APIs and persistence.
- B (selected): A plus aes and sign_verify, adding crypto APIs and validation scope.
- C: record candidates only and defer importing.

Source: linaro-swg/optee_examples, pinned at 71e8f3f320eef46a9369700bf30b91d67427d535.
Five directories are copied under samples/. Original top-level Makefiles are retained as Makefile.upstream; build wrappers are added.
Sources, licenses and copyright notices are preserved. Archive and original-file hashes are recorded in samples/optee-examples-source.json.

Individual/batch make, host cross-compilation and guest-native ARM64 compilation are provided.
[samples-guide.md](../samples-guide.md) describes 9p sharing, make, TA installation, execution and expected observations.
Checks cover make dry-runs, client C syntax, source hashes, document links and shell syntax.
Toolchain extraction cannot fit in the current environment; actual compilation, TA signing and guest execution remain unverified.
