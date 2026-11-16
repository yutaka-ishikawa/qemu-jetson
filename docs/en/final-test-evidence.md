# Final test evidence inventory

[日本語](../final-test-evidence.md) | English

Organized on 2026-11-17 (Japan time) for the user's jetson-ftpm-virt B2 environment.
The user reported all tests passed. Distinguish independently checked supplied logs from user-reported stages.
No blanket claim of independent full-workflow log verification is made.

## Evidence inventory

| Stage or event | Evidence | Assessment |
| --- | --- | --- |
| Repeated first | Supplied log.txt: PTA passes, FAIL line=22 | Failure of the first.done absence guard, consistent with an existing completion marker; not the original first PASS log |
| second | Supplied log2.txt | PASS: NV/key persistence, PCR reset, RSA signatures, seal/unseal and helper PTA certificate/CSR/signature markers |
| export | Supplied export.log | PASS: decoded and validated both RSA/ECC public keys; recorded SPKI SHA-256 fingerprints |
| bind/pack/apply | User's all-PASS report | Final output files/logs not supplied |
| bound | User's all-PASS report | Final bound.log absent; independent verification of EK/PTA certificate matching and certificate NV remains pending |
| bound reboot | User's all-PASS report | Final bound-reboot.log absent; persistence and EK stability versus export remain to be independently checked |
| Table exhaustion | Supplied secure-first-native.log | Historical failure: eight tables exhausted and panic, kept separate from successful results |
| Silent timeout | Supplied launch-first.strace | Historical SIGTTOU stop; evidence for the launcher foreground fix |

The [machine-readable inventory](../results/final-user-evidence.json) stores uploaded filenames, original byte counts/full-file SHA-256 hashes and checked markers.
The [excerpt](../results/final-user-evidence-excerpt.txt) retains relevant lines. Original-log hashes are not excerpt hashes.
Full original logs were inspected from uploads and are not copied wholesale into Git. No private keys, seeds or device-secret files are included.
EK fingerprints refer to the user's exported public keys; they need not match a developer's separate virtual device.

## Separate developer results

[Earlier full functional results](../results/ftpm-functional.json), [table-capacity regression](../results/optee-xlat-tables.json),
and [SELinux regression](../results/guest-selinux.json) are from the developer environment and existing disk.
They do not replace missing user logs. Pending wording in older files reflects their original validation scope.
Use this inventory for current received evidence and the user report.

## Remaining evidence

Tests have already been reported successful. Supply existing saved logs without rerunning tests or initializing state:

- work/ftpm-virt/bound.log
- work/ftpm-virt/bound-reboot.log
- work/ftpm-virt/first.log if retained; do not rerun first just to create it

Check both bound logs for PTA certificate/CSR/signature verification, actual EK/PTA certificate matching,
standard certificate NV indices, second PASS, and final EK_TEST: PASS.
Compare RSA/ECC EK_EXPORT values with export.
Independent host-side certificate signature checks additionally use issued public certificates/CSRs and public CA certificates only.
Do not supply CA/Firmware ID private keys, provisioning.bin, device-identity.bin or rootfs.ext4.
The older check-ftpm-functional-results.py requires six logs including first; do not duplicate logs to satisfy missing inputs.

See [test-guide.md](test-guide.md) for execution and [hardware differences](hardware-qemu-differences.md) for scope and limitations.
