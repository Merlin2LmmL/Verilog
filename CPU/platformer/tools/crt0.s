# Minimal start-up for the emulator build only (the real CPU brings its own).
# Memory is zero on reset in tools/rv32emu, so .bss needs no clearing here.
    .section .text.start, "ax"
    .globl _start
_start:
    li   sp, 0x00100000
    call main
1:  j    1b
