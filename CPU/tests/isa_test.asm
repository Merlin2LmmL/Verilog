; Tests every instruction, prints PASS or the check that failed
; every check: result in t3, expected value in t4, then "call check"
; on a fail it prints the address of that call -> look it up in build/isa_test.lst

        .equ IO,          0xFFFF0000
        .equ CONSOLE_OUT, 0x00
        .equ PRINT_INT,   0x04

        .data
words:      .word 0x11223344, 0x80000001
bytes:      .byte 0x7F, 0x80, 0xFF, 0x01
buf:        .space 16
msg_pass1:  .string "PASS: all "
msg_pass2:  .string " checks passed\n"
msg_fail:   .string "FAIL: check #"
msg_at:     .string " at "
msg_got:    .string ": got "
msg_exp:    .string ", expected "

        .text
start:  li   sp, 0x00040000
        li   s0, IO
        li   s3, 1                  ; number of the next check
        li   r1, 7
        li   r2, -3

; ---------------- ALU, register ----------------
        add  t3, r1, r2
        li   t4, 4
        call check
        sub  t3, r1, r2
        li   t4, 10
        call check
        sub  t3, r2, r1
        li   t4, -10
        call check
        li   r3, 0xF0F0F0F0
        li   r4, 0x0FF00FF0
        and  t3, r3, r4
        li   t4, 0x00F000F0
        call check
        or   t3, r3, r4
        li   t4, 0xFFF0FFF0
        call check
        xor  t3, r3, r4
        li   t4, 0xFF00FF00
        call check
        li   r5, 0x80000001
        li   r6, 4
        shl  t3, r5, r6
        li   t4, 0x00000010
        call check
        shr  t3, r5, r6
        li   t4, 0x08000000
        call check
        sra  t3, r5, r6
        li   t4, 0xF8000000
        call check
        li   r6, 33                 ; only the low 5 bits count: shift by 1
        shl  t3, r5, r6
        li   t4, 2
        call check
        slt  t3, r2, r1             ; -3 < 7
        li   t4, 1
        call check
        slt  t3, r1, r2
        li   t4, 0
        call check
        sltu t3, r2, r1             ; 0xFFFFFFFD < 7 is false unsigned
        li   t4, 0
        call check
        sltu t3, r1, r2
        li   t4, 1
        call check

; ---------------- ALU, immediate ----------------
        addi t3, r1, -10
        li   t4, -3
        call check
        andi t3, r3, 0xFFFF         ; zero-extended mask
        li   t4, 0x0000F0F0
        call check
        ori  t3, r0, 0x8000         ; zero-extended: not 0xFFFF8000
        li   t4, 0x00008000
        call check
        xori t3, r3, 0xFFFF
        li   t4, 0xF0F00F0F
        call check
        li   r5, 1
        shli t3, r5, 31
        li   t4, 0x80000000
        call check
        li   r5, 0x80000000
        shri t3, r5, 31
        li   t4, 1
        call check
        srai t3, r5, 31
        li   t4, -1
        call check
        slti t3, r2, -2             ; -3 < -2
        li   t4, 1
        call check
        slti t3, r2, -3
        li   t4, 0
        call check
        sltiu t3, r1, -1            ; 7 < 0xFFFFFFFF
        li   t4, 1
        call check
        sltiu t3, r2, 5             ; 0xFFFFFFFD < 5 is false
        li   t4, 0
        call check
        lui  t3, 0x1234
        li   r5, 0x1234
        shli t4, r5, 16
        call check
        li   r5, 0xDEADBEEF         ; li with a 32-bit value = lui + ori
        shri t3, r5, 16
        li   t4, 0xDEAD
        call check
        andi t3, r5, 0xFFFF
        li   t4, 0xBEEF
        call check
        addi r0, r0, 5              ; writes to r0 are ignored
        add  t3, r0, r0
        li   t4, 0
        call check

; ---------------- multiply / divide ----------------
        mul  t3, r1, r2             ; 7 * -3
        li   t4, -21
        call check
        li   r5, 0x10000
        mul  t3, r5, r5             ; 2^32: only the low 32 bits are kept
        li   t4, 0
        call check
        li   r5, 123456
        li   r6, 789
        mul  t3, r5, r6
        li   t4, 97406784
        call check
        li   r5, -21
        li   r6, 4
        div  t3, r5, r6             ; rounds toward zero
        li   t4, -5
        call check
        mod  t3, r5, r6             ; sign follows the dividend
        li   t4, -1
        call check
        li   r5, 21
        li   r6, -4
        div  t3, r5, r6
        li   t4, -5
        call check
        mod  t3, r5, r6
        li   t4, 1
        call check
        li   r5, 0xFFFFFFFE
        li   r6, 2
        divu t3, r5, r6
        li   t4, 0x7FFFFFFF
        call check
        li   r5, 0xFFFFFFFF
        li   r6, 10
        modu t3, r5, r6             ; 4294967295 % 10
        li   t4, 5
        call check
        li   r5, -21                ; division by zero
        div  t3, r5, r0
        li   t4, -1
        call check
        divu t3, r5, r0
        li   t4, -1
        call check
        mod  t3, r5, r0
        li   t4, -21
        call check
        modu t3, r5, r0
        li   t4, -21
        call check
        li   r5, 0x80000000         ; overflow: -2^31 / -1
        li   r6, -1
        div  t3, r5, r6
        li   t4, 0x80000000
        call check
        mod  t3, r5, r6
        li   t4, 0
        call check

; ---------------- loads and stores ----------------
        la   r5, words
        ld   t3, [r5]
        li   t4, 0x11223344
        call check
        ld   t3, [r5+4]
        li   t4, 0x80000001
        call check
        ld   t3, [words]            ; absolute address (base r0)
        li   t4, 0x11223344
        call check
        la   r5, bytes
        ldbu t3, [r5+1]
        li   t4, 0x80
        call check
        ldb  t3, [r5+1]             ; sign-extended
        li   t4, -128
        call check
        ldb  t3, [r5+0]
        li   t4, 0x7F
        call check
        la   r5, words              ; little-endian: lowest byte first
        ldbu t3, [r5+0]
        li   t4, 0x44
        call check
        ldbu t3, [r5+3]
        li   t4, 0x11
        call check
        la   r5, buf
        li   r6, 0xCAFEBABE
        st   r6, [r5]
        ld   t3, [r5]
        mov  t4, r6
        call check
        st   r0, [r5+4]
        li   r6, 0xAA
        stb  r6, [r5+5]
        li   r6, 0x155              ; only the low byte (0x55) is stored
        stb  r6, [r5+7]
        ld   t3, [r5+4]
        li   t4, 0x5500AA00
        call check
        addi r6, r5, 8
        ld   t3, [r6-4]             ; negative offset
        li   t4, 0x5500AA00
        call check
        ld   t3, [r5]               ; the byte stores left the word before alone
        li   t4, 0xCAFEBABE
        call check

; ---------------- stack ----------------
        push r1                     ; 7
        push r2                     ; -3
        pop  t3
        li   t4, -3
        call check
        pop  t3
        li   t4, 7
        call check
        mov  t3, sp                 ; push/pop left sp where it was
        li   t4, 0x00040000
        call check

; ---------------- branches: t3 = 1 if the branch was taken ----------------
        li   t3, 1
        beq  r1, r1, br1
        li   t3, 0
br1:    li   t4, 1
        call check
        li   t3, 1
        beq  r1, r2, br2
        li   t3, 0
br2:    li   t4, 0
        call check
        li   t3, 1
        bne  r1, r2, br3
        li   t3, 0
br3:    li   t4, 1
        call check
        li   t3, 1
        bne  r1, r1, br4
        li   t3, 0
br4:    li   t4, 0
        call check
        li   t3, 1
        blt  r2, r1, br5            ; -3 < 7
        li   t3, 0
br5:    li   t4, 1
        call check
        li   t3, 1
        blt  r1, r2, br6
        li   t3, 0
br6:    li   t4, 0
        call check
        li   t3, 1
        blt  r1, r1, br7
        li   t3, 0
br7:    li   t4, 0
        call check
        li   t3, 1
        bge  r1, r2, br8
        li   t3, 0
br8:    li   t4, 1
        call check
        li   t3, 1
        bge  r1, r1, br9
        li   t3, 0
br9:    li   t4, 1
        call check
        li   t3, 1
        bge  r2, r1, br10
        li   t3, 0
br10:   li   t4, 0
        call check
        li   t3, 1
        bltu r1, r2, br11           ; 7 < 0xFFFFFFFD unsigned
        li   t3, 0
br11:   li   t4, 1
        call check
        li   t3, 1
        bltu r2, r1, br12
        li   t3, 0
br12:   li   t4, 0
        call check
        li   t3, 1
        bgeu r2, r1, br13
        li   t3, 0
br13:   li   t4, 1
        call check
        li   t3, 1
        bgeu r1, r2, br14
        li   t3, 0
br14:   li   t4, 0
        call check
        li   t3, 1
        bgt  r1, r2, br15           ; pseudo: blt r2, r1
        li   t3, 0
br15:   li   t4, 1
        call check
        li   t3, 1
        ble  r1, r2, br16           ; pseudo: bge r2, r1
        li   t3, 0
br16:   li   t4, 0
        call check
        li   t3, 1
        ble  r1, r1, br17
        li   t3, 0
br17:   li   t4, 1
        call check
        li   t3, 1
        beqz r0, br18
        li   t3, 0
br18:   li   t4, 1
        call check
        li   t3, 1
        bnez r1, br19
        li   t3, 0
br19:   li   t4, 1
        call check
        li   t3, 1
        bnez r0, br20
        li   t3, 0
br20:   li   t4, 0
        call check
        li   t3, 0                  ; backward branch: 1 + 2 + ... + 10
        li   r5, 1
        li   r6, 10
sum:    add  t3, t3, r5
        addi r5, r5, 1
        ble  r5, r6, sum
        li   t4, 55
        call check

; ---------------- jumps ----------------
        jal  t3, jal1               ; t3 = address of the next instruction
jal1:   la   t4, jal1
        call check
        la   r5, jalr1
        jalr t3, r5, 0
jalr0:  li   t3, 0                  ; only reached if jalr did not jump
        li   t4, 1
        call check
jalr1:  la   t4, jalr0              ; t3 = return address = jalr0
        call check
        li   t3, 1
        la   r5, jalr2
        addi r5, r5, -8
        jalr r0, r5, 8              ; target = r5 + 8
        li   t3, 0
jalr2:  li   t4, 1
        call check
        li   t3, 1
        la   r5, jalr3
        addi r5, r5, 2              ; the low two bits of the target are cleared
        jalr r0, r5, 0
        li   t3, 0
jalr3:  li   t4, 1
        call check
        la   lr, jalr5              ; jalr lr, lr: jumps to the old lr
        jalr lr, lr, 0
jalr4:  li   t3, 0                  ; only reached if jalr did not jump
        li   t4, 1
        call check
jalr5:  mov  t3, lr
        la   t4, jalr4
        call check
        li   a0, 10                 ; recursive calls with the stack
        call fact
        mov  t3, a0
        li   t4, 3628800
        call check

; ---------------- other pseudo-instructions ----------------
        li   r5, 0x0F0F0F0F
        not  t3, r5
        li   t4, 0xF0F0F0F0
        call check
        not  r5, r5                 ; also works when rd = rs
        mov  t3, r5
        call check
        li   r5, 5
        neg  t3, r5
        li   t4, -5
        call check
        nop

; ---------------- all passed ----------------
        la   a0, msg_pass1
        call print_str
        addi t0, s3, -1
        st   t0, [s0+PRINT_INT]
        la   a0, msg_pass2
        call print_str
        halt

; ---------------- helpers ----------------
check:                              ; compare t3 (result) with t4 (expected)
        bne  t3, t4, fail
        addi s3, s3, 1
        ret

fail:                               ; lr = return address of the failed check
        addi s1, lr, -4             ; address of its "call check"
        la   a0, msg_fail
        call print_str
        st   s3, [s0+PRINT_INT]
        la   a0, msg_at
        call print_str
        mov  a0, s1
        call print_hex
        la   a0, msg_got
        call print_str
        mov  a0, t3
        call print_hex
        la   a0, msg_exp
        call print_str
        mov  a0, t4
        call print_hex
        li   t0, '\n'
        st   t0, [s0+CONSOLE_OUT]
        halt

fact:                               ; a0 = a0!   (recursive)
        li   t0, 2
        blt  a0, t0, fact_one
        push lr
        push a0
        addi a0, a0, -1
        call fact                   ; a0 = (n-1)!
        pop  t0                     ; t0 = n
        pop  lr
        mul  a0, a0, t0
        ret
fact_one:
        li   a0, 1
        ret

print_str:                          ; print the 0-terminated string at a0 (uses a0, t0)
        ldbu t0, [a0]
        beqz t0, print_str_done
        st   t0, [s0+CONSOLE_OUT]
        addi a0, a0, 1
        j    print_str
print_str_done:
        ret

print_hex:                          ; print a0 as 8 hex digits (uses t0, t1, t2)
        li   t1, 28
print_hex_loop:
        shr  t0, a0, t1
        andi t0, t0, 0xF
        slti t2, t0, 10
        bnez t2, print_hex_digit
        addi t0, t0, 'A' - '0' - 10
print_hex_digit:
        addi t0, t0, '0'
        st   t0, [s0+CONSOLE_OUT]
        addi t1, t1, -4
        bge  t1, r0, print_hex_loop
        ret
