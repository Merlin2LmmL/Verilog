; Benchmark: an endless loop with a mix of instructions (add, multiply, xor, shift,
; modulo, store, load and a jump). It never halts, so run it with +max_cycles=N,
; see tools/bench.sh. One pass of the loop is 11 instructions = 11 cycles.

        .data
buf:    .space 16

        .text
        li   r1, 1
        li   r2, 3
        li   r3, 0
        li   r4, 0              ; address of buf
loop:   add  r1, r1, r2
        mul  r5, r1, r2
        xor  r3, r3, r5
        shri r6, r3, 3
        st   r6, [r4+0]
        ld   r7, [r4+0]
        add  r3, r3, r7
        andi r8, r3, 255
        modu r9, r3, r2
        add  r1, r1, r9
        j    loop
