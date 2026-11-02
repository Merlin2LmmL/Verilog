; Prints a string from data memory with a function call.

        .equ IO, 0xFFFF0000         ; CONSOLE_OUT is at offset 0

        .data
message: .string "Hello, World!\n"

        .text
start:  li   sp, 0x00040000
        la   a0, message
        call print
        halt

print:                              ; print(a0 = address of a 0-terminated string)
        li   t1, IO
next:   ldbu t0, [a0]               ; load one character
        beqz t0, done               ; 0 marks the end
        st   t0, [t1]               ; CONSOLE_OUT
        addi a0, a0, 1
        j    next
done:   ret
