/*
 * Copyright (c) 2021-2022, Arm Limited. All rights reserved.
 * Copyright (c) 2023, NVIDIA Corporation. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <arch.h>
#include <asm_macros.S>
#include <common/bl_common.h>
#include <neoverse_v2.h>
#include <cpu_macros.S>
#include <plat_macros.S>
#include "wa_cve_2022_23960_bhb_vector.S"

/* Hardware handled coherency */
#if HW_ASSISTED_COHERENCY == 0
#error "Neoverse V2 must be compiled with HW_ASSISTED_COHERENCY enabled"
#endif

/* 64-bit only core */
#if CTX_INCLUDE_AARCH32_REGS == 1
#error "Neoverse V2 supports only AArch64. Compile with CTX_INCLUDE_AARCH32_REGS=0"
#endif

#if WORKAROUND_CVE_2022_23960
	wa_cve_2022_23960_bhb_vector_table NEOVERSE_V2_BHB_LOOP_COUNT, neoverse_v2
#endif /* WORKAROUND_CVE_2022_23960 */

/* -------------------------------------------------------
 * Errata Workaround for for Neoverse V2 Erratum 2394277.
 * This applies to revisions applies to revisions < r0p1
 *
 * x0: variant[4:7] and revision[0:3] of current cpu.
 *
 * Shall clobber: x0-x17
 * -------------------------------------------------------
 */
func errata_v2_2394277
	/* Compare x0 against revisions r0p0 */
	mov	x17, x30
	bl	check_errata_2394277
	cbz	x0, 1f

	/* Set bit CPUACTLR6_EL1[41] to 'b1 */
	mrs	x0, NEOVERSE_V2_CPUACTLR2_EL1
	orr	x0, x0, #NEOVERSE_V2_CPUACTLR2_EL1_BIT_40
	msr	NEOVERSE_V2_CPUACTLR2_EL1, x0
1:
	ret	x17
endfunc errata_v2_2394277

func check_errata_2394277
	/* Applies to revisions < r0p1. */
	mov	x1, #CPU_REV(0, 0)
	b	cpu_rev_var_ls
endfunc check_errata_2394277

/* -------------------------------------------------------
 * Errata Workaround for for Neoverse V2 Erratum 2644884.
 * This applies to revisions applies to revisions < r0p2
 *
 * x0: variant[4:7] and revision[0:3] of current cpu.
 *
 * Shall clobber: x0-x17
 * -------------------------------------------------------
 */
func errata_v2_2644884
	/* Compare x0 against revisions r0p0 - r0p1 */
	mov	x17, x30
	bl	check_errata_2644884
	cbz	x0, 1f

	/* Set bit CPUACTLR6_EL1[41] to 'b1 */
	mrs	x0, NEOVERSE_V2_CPUACTLR6_EL1
	orr	x0, x0, #NEOVERSE_V2_CPUACTLR6_EL1_BIT_41
	msr	NEOVERSE_V2_CPUACTLR6_EL1, x0
1:
	ret	x17
endfunc errata_v2_2644884

func check_errata_2644884
	/* Applies to revisions < r0p2. */
	mov	x1, #CPU_REV(0, 0)
	mov	x2, #CPU_REV(0, 1)
	b	cpu_rev_var_range
endfunc check_errata_2644884

/* -------------------------------------------------------
 * Errata Workaround for for Neoverse V2 Erratum 2719105
 * This applies to revisions applies to revisions < r0p2
 * Fixed in r0p2.
 *
 * x0: variant[4:7] and revision[0:3] of current cpu.
 *
 * Shall clobber: x0-x17
 * -------------------------------------------------------
 */
func errata_v2_2719105
        /* Compare x0 against revisions r0p0 - r0p1 */
        mov     x17, x30
        bl      check_errata_2719105
        cbz     x0, 1f

        /* Set bit CPUACTLR2_EL1[0] to 'b1 */
        mrs     x0, NEOVERSE_V2_CPUACTLR2_EL1
        orr     x0, x0, #NEOVERSE_V2_CPUACTLR2_EL1_BIT_0
        msr     NEOVERSE_V2_CPUACTLR2_EL1, x0
1:
        ret     x17
endfunc errata_v2_2719105

func check_errata_2719105
        /* Applies to revisions < r0p2. */
        mov     x1, #CPU_REV(0, 0)
        mov     x2, #CPU_REV(0, 1)
        b       cpu_rev_var_range
endfunc check_errata_2719105


/* -------------------------------------------------------
 * Errata Workaround for for Neoverse V2 Erratum 2743011.
 * This applies to revisions applies to revisions < r0p2
 * x0: variant[4:7] and revision[0:3] of current cpu.
 * Shall clobber: x0-x17
 * -------------------------------------------------------
 */
func errata_v2_2743011
        /* Compare x0 against revisions r0p0 - r0p1 */
        mov     x17, x30
        bl      check_errata_2743011
        cbz     x0, 1f

        /* Set bit [56:55]=b'01 in CPUACTLR5 */
        mrs     x0, NEOVERSE_V2_ACTLR5_EL1
        orr     x0, x0, #NEOVERSE_V2_ACTLR5_EL1_BIT_55
        bic     x0, x0, #NEOVERSE_V2_ACTLR5_EL1_BIT_56
        msr     NEOVERSE_V2_ACTLR5_EL1, x0
1:
        ret     x17
endfunc errata_v2_2743011

func check_errata_2743011
        /* Applies to revisions < r0p2. */
        mov     x1, #CPU_REV(0, 0)
        mov     x2, #CPU_REV(0, 1)
        b       cpu_rev_var_range
endfunc check_errata_2743011

/* -------------------------------------------------------
 * Errata Workaround for Neoverse V2 Erratum 2743088.
 * This applies to revisions r0p0 and r0p1.
 * x0: variant[4:7] and revision[0:3] of current cpu.
 * Shall clobber: x0-x17
 * -------------------------------------------------------
 */
func errata_v2_2743088_wa
	mov	x17, x30
	bl	check_errata_2743088
	cbz	x0, 1f

	/* dsb before isb of power down sequence */
	dsb	sy
1:
	ret	x17
endfunc errata_v2_2743088_wa

func check_errata_2743088
	/* Applies to <=r0p1 */
	mov	x1, #0x01
	b	cpu_rev_var_ls
endfunc check_errata_2743088


/* -------------------------------------------------------
 * Errata Workaround for Neoverse V2 Erratum 2779510.
 * This applies to revisions r0p0, r0p1 and r0p2.
 * x0: variant[4:7] and revision[0:3] of current cpu.
 * Shall clobber: x0-x17
 * -------------------------------------------------------
 */
func errata_v2_2779510_wa
        mov     x17, x30
        bl      check_errata_2779510
        cbz     x0, 1f

        /* set CPUACTLR3_EL1[47] */
        mrs	x1, NEOVERSE_V2_CPUACTLR3_EL1
	orr	x1, x1, NEOVERSE_V2_CPUACTLR3_EL1_BIT_47
	msr	NEOVERSE_V2_CPUACTLR3_EL1, x1
1:
        ret     x17
endfunc errata_v2_2779510_wa

func check_errata_2779510
        /* Applies to <=r0p2 */
        mov     x1, #0x02
        b       cpu_rev_var_ls
endfunc check_errata_2779510


	/* ----------------------------------------------------
	 * HW will do the cache maintenance while powering down
	 * ----------------------------------------------------
	 */
func neoverse_v2_core_pwr_dwn
	/* ---------------------------------------------------
	 * Enable CPU power down bit in power control register
	 * ---------------------------------------------------
	 */
	mrs	x0, NEOVERSE_V2_CPUPWRCTLR_EL1
	orr	x0, x0, #NEOVERSE_V2_CPUPWRCTLR_EL1_CORE_PWRDN_BIT
	msr	NEOVERSE_V2_CPUPWRCTLR_EL1, x0
#if ERRATA_V2_2743088
	mov	x15, x30
	bl	cpu_get_rev_var
	bl	errata_v2_2743088_wa
	mov	x30, x15
#endif /* ERRATA_V2_2743088 */
	isb
	ret
endfunc neoverse_v2_core_pwr_dwn

func check_errata_cve_2022_23960
#if WORKAROUND_CVE_2022_23960
	mov	x0, #ERRATA_APPLIES
#else
	mov	x0, #ERRATA_MISSING
#endif
	ret
endfunc check_errata_cve_2022_23960

func check_errata_cve_2024_5660
#if WORKAROUND_CVE_2024_5660
	mov	x0, #ERRATA_APPLIES
#else
	mov	x0, #ERRATA_MISSING
#endif
	ret
endfunc check_errata_cve_2024_5660

#if WORKAROUND_CVE_2024_5660
/* --------------------------------------------------
 * Errata Workaround for CVE-2024-5660.
 * This applies to all the revision of Neoverse V2.
 * Inputs: None
 * Shall clobber: x0
 * --------------------------------------------------
 */
func errata_v2_cve_2024_5660_wa
	/* --------------------------------------------------------
	 * Disable the hardware page aggregation
	 * by setting the CPUECTLR_EL1[46] to 1.
	 * --------------------------------------------------------
	 */
	mrs	x0, NEOVERSE_V2_CPUECTLR_EL1
	orr	x0, x0, #NEOVERSE_V2_CPUECTLR_EL1_BIT_46
	msr	NEOVERSE_V2_CPUECTLR_EL1, x0

	ret
endfunc errata_v2_cve_2024_5660_wa
#endif

func neoverse_v2_reset_func
	mov	x19, x30

	/* Disable speculative loads */
	msr	SSBS, xzr

	/* Get the CPU revision and stash it in x18. */
	bl	cpu_get_rev_var
	mov	x18, x0

#if ERRATA_DSU_2313941
	bl	errata_dsu_2313941_wa
#endif

#if ERRATA_V2_2394277
	mov	x0, x18
	bl	errata_v2_2394277
#endif

#if ERRATA_V2_2644884
	mov	x0, x18
	bl	errata_v2_2644884
#endif

#if ERRATA_V2_2719105
        mov     x0, x18
        bl      errata_v2_2719105
#endif

#if ERRATA_V2_2743011
	mov	x0, x18
	bl	errata_v2_2743011
#endif /* ERRATA_V2_2743011 */

#if ERRATA_V2_2779510
	mov	x0, x18
	bl	errata_v2_2779510_wa
#endif /* ERRATA_V2_2779510 */

#if IMAGE_BL31 && WORKAROUND_CVE_2022_23960
	/*
	 * The Neoverse V2 vectors are overridden to apply
	 * errata mitigation on exception entry from lower ELs.
	 */
	adr	x0, wa_cve_vbar_neoverse_v2
	msr	vbar_el3, x0
#endif /* IMAGE_BL31 && WORKAROUND_CVE_2022_23960 */

#if WORKAROUND_CVE_2024_5660
	bl	errata_v2_cve_2024_5660_wa
#endif

	isb
	ret	x19
endfunc neoverse_v2_reset_func

#if REPORT_ERRATA
/*
 * Errata printing function for Neoverse V2. Must follow AAPCS.
 */
func neoverse_v2_errata_report
	stp	x8, x30, [sp, #-16]!

	bl	cpu_get_rev_var
	mov	x8, x0

	/*
	 * Report all errata. The revision-variant information is passed to
	 * checking functions of each errata.
	 */
	report_errata ERRATA_V2_2394277, neoverse_v2, 2394277
	report_errata ERRATA_V2_2644884, neoverse_v2, 2644884
	report_errata ERRATA_V2_2719105, neoverse_v2, 2719105
	report_errata ERRATA_V2_2743088, neoverse_v2, 2743011
	report_errata ERRATA_V2_2743088, neoverse_v2, 2743088
	report_errata ERRATA_V2_2779510, neoverse_v2, 2779510
	report_errata WORKAROUND_CVE_2022_23960, neoverse_v2, cve_2022_23960
	report_errata WORKAROUND_CVE_2024_5660, neoverse_v2, cve_2024_5660
	report_errata ERRATA_DSU_2313941, neoverse_v2, dsu_2313941

	ldp	x8, x30, [sp], #16
	ret
endfunc neoverse_v2_errata_report
#endif

	/* ---------------------------------------------
	 * This function provides Neoverse V2-
	 * specific register information for crash
	 * reporting. It needs to return with x6
	 * pointing to a list of register names in ascii
	 * and x8 - x15 having values of registers to be
	 * reported.
	 * ---------------------------------------------
	 */
.section .rodata.neoverse_v2_regs, "aS"
neoverse_v2_regs:  /* The ascii list of register names to be reported */
	.asciz	"cpuectlr_el1", ""

func neoverse_v2_cpu_reg_dump
	adr	x6, neoverse_v2_regs
	mrs	x8, NEOVERSE_V2_CPUECTLR_EL1
	ret
endfunc neoverse_v2_cpu_reg_dump

declare_cpu_ops neoverse_v2, NEOVERSE_V2_MIDR, \
	neoverse_v2_reset_func, \
	neoverse_v2_core_pwr_dwn
