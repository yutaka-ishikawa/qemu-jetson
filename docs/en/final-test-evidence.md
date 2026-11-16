# Final test evidence inventory

[日本語](../final-test-evidence.md) | English

Organized on 2026-11-17 (Japan time) for the user's jetson-ftpm-virt B2 environment.
The user reported all tests passed. Distinguish independently checked supplied logs from user-reported stages.
Update: supplied bound and bound-reboot logs independently pass all required markers and EK stability checks versus export. The original first PASS log remains unavailable.

## Evidence inventory

| Stage or event | Evidence | Assessment |
| --- | --- | --- |
| Repeated first | Supplied log.txt: PTA passes, FAIL line=22 | Failure of the first.done absence guard, consistent with an existing completion marker; not the original first PASS log |
| second | Supplied log2.txt | PASS: NV/key persistence, PCR reset, RSA signatures, seal/unseal and helper PTA certificate/CSR/signature markers |
| export | Supplied export.log | PASS: decoded and validated both RSA/ECC public keys; recorded SPKI SHA-256 fingerprints |
| bind/pack/apply | User's all-PASS report | Application confirmed by subsequent bound logs; issued certificate files not independently checked on the host |
| bound | Supplied bound.log | PASS: PTA, actual EK/certificate matching, standard NV, second and final EK_TEST |
| bound reboot | Supplied bound-reboot.log | PASS: same markers and identical RSA/ECC EKs across export/bound/reboot |
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

## Verified scope and remaining evidence limits

Both bound logs contain required PTA certificate/CSR/signature, actual EK matching, standard NV, second and final EK_TEST PASS markers, with no test FAIL markers.
Decoded RSA/ECC EK_EXPORT public keys have identical DER SPKI SHA-256 values across export, bound and bound-reboot.
Original log hashes and excerpts are recorded. No rerun or disk reset is needed.
The original first PASS log remains unavailable; do not rerun first just to generate evidence.
Certificate signature validation relies on guest PASS markers; issued public certificate files have not been independently checked on the host.
Private keys, seeds, identity files and disks need not be supplied. Do not duplicate logs to satisfy the older six-log checker.

See [test-guide.md](test-guide.md) for execution and [hardware differences](hardware-qemu-differences.md) for scope and limitations.
