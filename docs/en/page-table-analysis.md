# OP-TEE translation table usage analysis

[日本語](../page-table-analysis.md) | English

## Conclusion

Diagnostic QEMU B2 runs show that **DTB ASLR seed changes table demand; the observed maximum was 9/32 tables**.
The nine-table layout also passed bound. Observed headroom is 23 tables (92KiB), not a proof for every seed or workload.
Keep the limit at 32; these measurements do not justify reducing it to nine.

The original user failure exhausted eight tables and failed the next allocation.
Here, a controlled layout consumed eight before normal-world handover and requested the ninth for its first nonsecure shared-memory mapping.
The original user DTB was not supplied, so this is not a bit-identical reproduction, but it establishes the same capacity failure condition.

## Scope and method

- jetson-ftpm-virt, Cortex-A57, one CPU, 1GiB RAM, NVIDIA Linux 5.15.199-tegra and B2 OP-TEE.
- CFG_CORE_ASLR=y, CFG_NS_VIRTUALIZATION disabled, MAX_XLAT_TABLES=32.
- Logged allocation count/limit in core_mmu_xlat_table_alloc, split levels/VA/indices in core_mmu_entry_to_finer_grained, and copy events in core_mmu_entry_copy.
- Logged VA, page count and memtype in core_mmu_map_pages. No secret values or mapped contents were printed.
- The [diagnostic patch](../results/xlat-analysis/instrumentation.patch) adds logging only. It was removed after measurement and normal firmware was rebuilt and installed.
- Completed second and bound with the existing DTB; tested five /secure-chosen/kaslr-seed values for six seconds each.
- Additional probes used QEMU -snapshot and a writable TMPDIR, discarding disk writes. Also completed bound with the nine-table seed.
- Restored original DTBs. No identity, CA, device/TPM seeds, provisioning or TPM NV state was regenerated. kaslr-seed controls memory layout, not TPM EPS or device seed material.

## Measurements

Boot usage is the count before `Primary CPU switching to normal world boot`; peak covers the entire captured trace.

| Layout/workload | Boot | Peak | Spare out of 32 | Outcome |
| --- | ---: | ---: | ---: | --- |
| Existing DTB, second | 4 | 5 | 27 | PASS |
| Existing DTB, bound | 4 | 5 | 27 | PASS |
| Secure seed 0x0000000000000001 | 6 | 7 | 25 | Six-second boot probe |
| Secure seed 0x0000000020001000 | 5 | 6 | 26 | Six-second boot probe |
| Secure seed 0x0000000060001000 | 6 | 7 | 25 | Six-second boot probe |
| Secure seed 0x00000000b3b0b000 | 8 | 9 | 23 | Six-second boot probe |
| Secure seed 0x00000000fdf01000 | 7 | 8 | 24 | Six-second boot probe |
| Secure seed 0x00000000b3b0b000, bound | 8 | 9 | 23 | PASS |

Exit status 124 in short probes is intentional termination, not a full fTPM PASS.
The seeded bound run passed PTA checks, actual EK/certificate matching, certificate NV indices, second and final EK_TEST.

### Where the original limit of eight comes from

Measured configuration: CFG_LPAE_ADDR_SPACE_BITS=32, CFG_CORE_ASLR=y, CFG_NS_VIRTUALIZATION=n.
Without the QEMU override, core_mmu_lpae.c's default formula under these conditions is five TEE tables plus three ASLR tables, totaling eight.
This is a default capacity setting, not a proof of sufficient capacity for every virtual layout.
The QEMU fTPM platform now overrides MAX_XLAT_TABLES to 32.
In the nine-table layout, 411 core_mmu_map_pages calls during bound left the peak at nine; no per-call table growth was observed.

## Why eight can be insufficient

1. [boot.c](../../optee/optee/optee_os/core/arch/arm/kernel/boot.c) reads /secure-chosen/kaslr-seed; [core_mmu.c](../../optee/optee/optee_os/core/mm/core_mmu.c) selects virtual layout.
2. Different layouts cross different 1GiB/2MiB boundaries. Total mapped bytes alone do not determine table demand.
3. The nine-table layout generated three L1 splits and six L2 splits, one lower-level table each. No COPY events occurred.
4. Eight were consumed before handover. The first 4KiB MEM_AREA_NSEC_SHM mapping (memtype 13) needed another L3 table covering VA 0xbea00000:

```text
XLAT_MAP va=bea00000 pages=1 type=13
XLAT_SPLIT level=2 va=80000000 idx=501
XLAT_ALLOC used=9 max=32
```

Index 501 in the L2 table based at 0x80000000 splits a 2MiB region into 4KiB pages.
L1-to-L2 splits subdivide 1GiB regions; L2-to-L3 splits subdivide 2MiB regions.
With a limit of eight, [core_mmu_lpae.c](../../optee/optee/optee_os/core/arch/arm/mm/core_mmu_lpae.c) rejects the ninth allocation at `used >= MAX_XLAT_TABLES`, and map_pages panics.
The actual original user log reported:

```text
8 xlat tables exhausted
Panic 'Failed to spread pgdir on small tables'
```

Linux stopping near console handover did not establish a UART fault: the secure-world panic stopped progress until timeout.

## Storage and counter semantics

- One table is 512 entries × 8 bytes = 4096 bytes. Pool capacity grew from 32KiB to 128KiB, an additional 96KiB.
- Nine tables represent 36KiB populated capacity, leaving 92KiB of pool capacity. The whole array is statically reserved; spare capacity is not general-purpose free RAM.
- xlat_tables_used counts pool allocations. In this non-virtualized profile it is a boot high-water count, not decremented for each unmap.
- Base tables, xlat_tables_ul1 and TA tables are separate. Nine is not the total OP-TEE page-table memory footprint.
- Controlled seed changes demonstrate layout dependence rather than merely speculating about fragmentation or leaks. They do not prove leak freedom under untested long-running, multi-TA or all-layout workloads.

## Evidence and reaggregation

See [usage.json](../results/xlat-analysis/usage.json), [summary.json](../results/xlat-analysis/summary.json), secure traces and normal-world excerpts in that directory.

```bash
python3 scripts/analyze-ftpm-xlat-log.py docs/results/xlat-analysis/*.log
```

This reads existing traces without changing keys or disks.
For new measurements, stop QEMU, apply the diagnostic patch and rebuild firmware; normal builds do not need that patch.
Example seed override: `fdtput -t x DTB /secure-chosen kaslr-seed 0 b3b0b000`.
Back up/restore DTBs, use QEMU -snapshot and a writable TMPDIR, and never run concurrent instances against the normal disk.
Physical T234 layouts can require different counts; physical-device requirements need separate measurement.
