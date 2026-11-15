/* SPDX-License-Identifier: BSD-2-Clause */
.section .text.boot,"ax"
.global _start
_start:
    ldr x0, =0x40000000
    mov x1, #0
    mov x2, #0
    mov x3, #0
    ldr x4, =0x60200000
    br x4
.ltorg
