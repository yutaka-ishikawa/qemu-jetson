/* SPDX-License-Identifier: BSD-2-Clause */
ENTRY(_start)
SECTIONS {
    . = 0;
    .text : { *(.text.boot) *(.text*) }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
