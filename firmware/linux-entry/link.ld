/* SPDX-License-Identifier: BSD-2-Clause */
ENTRY(_start)
SECTIONS { . = 0x60000000; .text : { *(.text.boot) *(.text*) } /DISCARD/ : { *(.note*) *(.comment) } }
