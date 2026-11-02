; Echoes key presses in uppercase until no keys are left.
; Keys come from a file:   ./run.sh programs/keys.asm +keys=programs/keys.txt

        .equ IO,          0xFFFF0000
        .equ CONSOLE_OUT, 0x00
        .equ KEY_STATUS,  0x08
        .equ KEY_DATA,    0x0C

        .text
        li   s0, IO
loop:   ld   t0, [s0+KEY_STATUS]
        beqz t0, done               ; no key waiting
        ld   t0, [s0+KEY_DATA]      ; take the key
        li   t1, 'a'
        blt  t0, t1, print
        li   t1, 'z'
        bgt  t0, t1, print
        addi t0, t0, 'A' - 'a'      ; lowercase -> uppercase
print:  st   t0, [s0+CONSOLE_OUT]
        j    loop
done:   halt
