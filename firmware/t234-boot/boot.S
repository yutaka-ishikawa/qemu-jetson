/* Minimal development monitor, not a production Secure Monitor.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#ifndef NS_PROBE_ADDR
#define NS_PROBE_ADDR 0x80000000
#endif

.section .text.boot, "ax"
.global _start
_start:
    msr daifset, #0xf
    ldr x0, =0x83fe0000
    mov sp, x0
    adr x0, el3_vectors
    msr vbar_el3, x0
    isb
    adr x0, msg_el3
    bl puts
    mrs x0, CurrentEL
    cmp x0, #12
    b.ne fail

#ifdef BOOT_NS_TEST
    /* Put a probe in NS RAM; secure RAM must not be visible to it. */
    ldr x0, =0x80000000
    ldr x1, =0x1122334455667788
    str x1, [x0]
    adr x0, ns_probe_start
    adr x1, ns_probe_end
    ldr x2, =0x90010000
1:  ldrb w3, [x0], #1
    strb w3, [x2], #1
    cmp x0, x1
    b.lo 1b
    dsb sy
    adr x0, ns_vectors
    adr x1, ns_probe_start
    sub x0, x0, x1
    ldr x1, =0x90010000
    add x0, x0, x1
    msr vbar_el1, x0
#endif
#if defined(BOOT_FUSE_WRITE_TEST)
    ldr x0, =0x03810200
    mov w1, #-1
    str w1, [x0]
    b fail
#elif defined(BOOT_FUSE_BAD_READ_TEST)
    ldr x0, =0x03810000
    ldr w1, [x0]
    b fail
#endif
    /* AArch64 Secure EL1, secure timer and PAUTH access allowed. */
    ldr x0, =0x30c30
#ifdef BOOT_NS_TEST
    orr x0, x0, #1
#endif
    msr scr_el3, x0
    msr cptr_el3, xzr
#ifdef BOOT_NS_TEST
    mov x0, #(1 << 31)
    msr hcr_el2, x0
#endif
    ldr x0, =0x30d00800
    msr sctlr_el1, x0
#ifdef BOOT_NS_TEST
    ldr x0, =0x90020000
#else
    ldr x0, =0x83fd0000
#endif
    msr sp_el1, x0
    ldr x0, =0x3c5
    msr spsr_el3, x0
#ifdef BOOT_SELF_TEST
    adr x0, self_test_el1
#elif defined(BOOT_FUSE_PROBE)
    adr x0, fuse_probe_el1
#elif defined(BOOT_NS_TEST)
    ldr x0, =0x90010000
#else
    ldr x0, =0x80000000
#endif
    msr elr_el3, x0
    isb
    mov x0, #0
    ldr x1, =0x83fc0000
    ldr x2, =0x83ff0000
    mov x3, #0
    eret

#ifdef BOOT_SELF_TEST
self_test_el1:
    adr x0, msg_el1
    bl puts
    mrs x0, CurrentEL
    cmp x0, #4
    b.ne fail
    /* Exercise 3-byte packet and synchronous busy clear. */
    ldr x4, =0x0c198000
    ldr w5, =0x83434241
    str w5, [x4]
    ldr w5, [x4]
    tbnz w5, #31, fail
    ldr w5, =0x84000000
    str w5, [x4]
    mov x0, #10
    bl putc
    ldr x0, =0xc2000001
    smc #0
    b fail
#endif

#ifdef BOOT_FUSE_PROBE
fuse_probe_el1:
    ldr x0, =0x03810000
    ldr x1, =0x83fc1000
    ldr x2, =0x83fc1020
    ldr x3, =FUSE_GENERATE_ECID_ADDR
    blr x3
    cbnz w0, fail
    adr x0, msg_ecid128
    bl puts
    ldr x19, =0x83fc1000
    mov x20, #4
1:  ldr w0, [x19], #4
    bl hex
    mov x0, #' '
    bl putc
    subs x20, x20, #1
    b.ne 1b
    mov x0, #10
    bl putc
    adr x0, msg_ecid64
    bl puts
    ldr x0, =0x83fc1020
    ldr x0, [x0]
    bl hex
    mov x0, #10
    bl putc

    ldr x2, =0x83fc1040
    mov w0, #10
    str w0, [x2]
    ldr x0, =0x03810000
    ldr x1, =0x83fc1030
    ldr x3, =FUSE_GENERATE_SN_ADDR
    blr x3
    cbnz w0, fail
    ldr x0, =0x83fc1040
    ldr w0, [x0]
    cmp w0, #10
    b.ne fail
    adr x0, msg_sn
    bl puts
    ldr x19, =0x83fc1030
    mov x20, #10
1:  ldrb w21, [x19], #1
    lsr x0, x21, #4
    bl nibble
    and x0, x21, #0xf
    bl nibble
    subs x20, x20, #1
    b.ne 1b
    mov x0, #10
    bl putc
    ldr x0, =0xc2000004
    smc #0
    b fail
nibble:
    cmp x0, #10
    add x0, x0, #'0'
    b.lo 1f
    add x0, x0, #7
1:  b putc
#endif

/* Each vector keeps a slot number without destroying x0-x3. */
.balign 2048
el3_vectors:
.macro vector slot
.balign 128
    mov x14, #\slot
    b exception
.endm
    vector 0
    vector 1
    vector 2
    vector 3
    vector 4
    vector 5
    vector 6
    vector 7
    vector 8
    vector 9
    vector 10
    vector 11
    vector 12
    vector 13
    vector 14
    vector 15
.balign 128
exception:
    mov x19, x0
    mov x20, x1
    mov x21, x2
    adr x0, msg_exception
    bl puts
    mrs x0, esr_el3
    bl hex
    adr x0, msg_elr
    bl puts
    mrs x0, elr_el3
    bl hex
    adr x0, msg_far
    bl puts
    mrs x0, far_el3
    bl hex
    adr x0, msg_x0
    bl puts
    mov x0, x19
    bl hex
    mov x0, #10
    bl putc
#ifdef BOOT_SELF_TEST
    ldr x0, =0xc2000001
    cmp x19, x0
    b.ne fail
    mrs x0, esr_el3
    lsr x0, x0, #26
    cmp x0, #0x17
    b.ne fail
    adr x0, msg_pass
    bl puts
    mov x0, #0
    b exit
#elif defined(BOOT_NS_TEST)
    ldr x0, =0xc2000002
    cmp x19, x0
    b.ne fail
    lsr x0, x20, #26
    cmp x0, #0x25
    b.ne fail
    ldr x0, =NS_PROBE_ADDR
    cmp x21, x0
    b.ne fail
    adr x0, msg_ns_pass
    bl puts
    mov x0, x20
    bl hex
    mov x0, #' '
    bl putc
    mov x0, x21
    bl hex
    mov x0, #10
    bl putc
    mov x0, #0
    b exit
#elif defined(BOOT_FUSE_PROBE)
    ldr x0, =0xc2000004
    cmp x19, x0
    b.ne fail
    mrs x0, esr_el3
    lsr x0, x0, #26
    cmp x0, #0x17
    b.ne fail
    adr x0, msg_fuse_pass
    bl puts
#ifdef BOOT_FUSE_WAIT_RESET
1:  wfi
    b 1b
#else
    mov x0, #0
    b exit
#endif
#elif defined(BOOT_FUSE_WRITE_TEST) || defined(BOOT_FUSE_BAD_READ_TEST)
    mrs x0, esr_el3
    lsr x1, x0, #26
    cmp x1, #0x25
    b.ne fail
#ifdef BOOT_FUSE_WRITE_TEST
    tbz x0, #6, fail
    mrs x0, far_el3
    ldr x1, =0x03810200
    cmp x0, x1
    b.ne fail
    ldr w19, [x1]
    adr x0, msg_fuse_write
    bl puts
    mov x0, x19
    bl hex
#else
    tbnz x0, #6, fail
    mrs x0, far_el3
    ldr x1, =0x03810000
    cmp x0, x1
    b.ne fail
    adr x0, msg_fuse_bad_read
    bl puts
#endif
    mov x0, #10
    bl putc
    mov x0, #0
    b exit
#else
    /* Only report; do not pretend to implement OPTEED services. */
    adr x0, msg_stop
    bl puts
    mov x0, #2
    b exit
#endif
fail:
    adr x0, msg_fail
    bl puts
    mov x0, #1
exit:
    /* QEMU AArch64 semihosting SYS_EXIT_EXTENDED. */
    mov x2, x0
    sub sp, sp, #16
    ldr x1, =0x20026
    stp x1, x2, [sp]
    mov x1, sp
    mov x0, #0x20
    hlt #0xf000
1:  wfi
    b 1b

/* Leaf routines use x4-x8; puts/hex save the link register. */
putc:
    ldr x4, =0x0c198000
    ldr w5, =0x81000000
    and w6, w0, #0xff
    orr w5, w5, w6
    str w5, [x4]
    ret
puts:
    mov x7, x30
    mov x8, x0
1:  ldrb w0, [x8], #1
    cbz w0, 2f
    bl putc
    b 1b
2:  ret x7
hex:
    mov x7, x30
    mov x8, x0
    mov x9, #60
1:  lsrv x0, x8, x9
    and x0, x0, #0xf
    cmp x0, #10
    add x0, x0, #'0'
    b.lo 2f
    add x0, x0, #7
2:  bl putc
    subs x9, x9, #4
    b.ge 1b
    ret x7
.ltorg
#ifdef BOOT_NS_TEST
.balign 2048
ns_probe_start:
    ldr x0, =NS_PROBE_ADDR
    ldr x1, [x0]
    ldr x0, =0xc2000003
    smc #0
1:  wfi
    b 1b
.balign 2048
ns_vectors:
.rept 16
.balign 128
    b ns_fault
.endr
.balign 128
ns_fault:
    mrs x1, esr_el1
    mrs x2, far_el1
    ldr x0, =0xc2000002
    smc #0
1:  wfi
    b 1b
.ltorg
ns_probe_end:
#endif
.section .rodata
msg_el3: .asciz "BOOT: EL3 entry\n"
msg_el1: .asciz "BOOT: Secure EL1 entry\nTCU: "
msg_exception: .asciz "BOOT: EL3 exception ESR="
msg_elr: .asciz " ELR="
msg_far: .asciz " FAR="
msg_x0: .asciz " X0="
msg_pass: .asciz "BOOT: SELFTEST PASS\n"
msg_fail: .asciz "BOOT: SELFTEST FAIL\n"
msg_stop: .asciz "BOOT: STOP (monitor service not implemented)\n"

msg_ns_pass: .asciz "BOOT: NS isolation PASS ESR_EL1/FAR_EL1="

msg_ecid128: .asciz "FUSE: ECID128="
msg_ecid64: .asciz "FUSE: ECID64="
msg_sn: .asciz "FUSE: SN="
msg_fuse_pass: .asciz "BOOT: FUSE probe PASS\n"
msg_fuse_write: .asciz "BOOT: FUSE write rejected, vendor="
msg_fuse_bad_read: .asciz "BOOT: FUSE unsupported read rejected"
