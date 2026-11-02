; Prints the first 20 Fibonacci numbers, one per line.

        .equ IO,          0xFFFF0000
        .equ CONSOLE_OUT, 0x00
        .equ PRINT_INT,   0x04

        .text
        li   s0, IO                 ; I/O base address
        li   r1, 0                  ; a = 0
        li   r2, 1                  ; b = 1
        li   r3, 20                 ; counter
loop:
        st   r1, [s0+PRINT_INT]     ; print a
        li   r4, '\n'
        st   r4, [s0+CONSOLE_OUT]   ; newline
        add  r4, r1, r2             ; t = a + b
        mov  r1, r2                 ; a = b
        mov  r2, r4                 ; b = t
        addi r3, r3, -1             ; counter--
        bnez r3, loop
        halt
