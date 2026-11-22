/* Emulator memory map: 1 MiB RAM from 0, MMIO at 0xFFFD0000 / 0xFFFF0000 */
ENTRY(_start)
SECTIONS
{
    . = 0x0;
    .text   : { *(.text.start) *(.text .text.*) }
    .rodata : { *(.rodata .rodata.* .srodata .srodata.*) }
    .data   : { *(.data .data.* .sdata .sdata.*) }
    .bss    : { *(.bss .bss.* .sbss .sbss.* COMMON) }
}
