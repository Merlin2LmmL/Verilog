; Text screen demo: a title and a ball bouncing around for 150 frames.
; Every frame: erase the ball, move it, draw it, show the screen, wait.

        .equ SCREEN,      0xFFFE0000    ; 40 x 25 cells, one word each
        .equ IO,          0xFFFF0000
        .equ TIMER,       0x10
        .equ SCREEN_SHOW, 0x18
        .equ COLS,        40
        .equ ROWS,        25
        .equ TOP,         3             ; the ball stays below the title
        .equ FRAME_DELAY, 2500          ; clock cycles per frame
        .equ BALL,        0x0900 | 'O'  ; bright red 'O' (fg 9) on black (bg 0)

        .data
title:  .string " Hello from my CPU! "
dx:     .word 1                         ; ball direction
dy:     .word 1
frames: .word 150                       ; frames left

        .text
start:  li   sp, 0x00040000
        li   s0, IO
        li   s1, SCREEN

        la   a0, title                  ; print_at(text, x, y, colors)
        li   a1, 10
        li   a2, 1
        li   a3, 0x4B00                 ; bright yellow (fg 11) on blue (bg 4)
        call print_at

        li   s2, 5                      ; ball x
        li   s3, TOP                    ; ball y
frame:
        mov  a0, s2                     ; erase the ball
        mov  a1, s3
        li   a2, ' '
        call put

        ld   t0, [dx]                   ; x += dx, bounce at the left/right edge
        add  s2, s2, t0
        beqz s2, flip_x
        li   t1, COLS - 1
        bne  s2, t1, x_ok
flip_x: neg  t0, t0
        st   t0, [dx]
x_ok:
        ld   t0, [dy]                   ; y += dy, bounce at the top/bottom
        add  s3, s3, t0
        li   t1, TOP
        beq  s3, t1, flip_y
        li   t1, ROWS - 1
        bne  s3, t1, y_ok
flip_y: neg  t0, t0
        st   t0, [dy]
y_ok:
        mov  a0, s2                     ; draw the ball
        mov  a1, s3
        li   a2, BALL
        call put
        st   r0, [s0+SCREEN_SHOW]       ; show the frame

        ld   t0, [s0+TIMER]             ; wait FRAME_DELAY cycles
wait:   ld   t1, [s0+TIMER]
        sub  t1, t1, t0
        li   t2, FRAME_DELAY
        blt  t1, t2, wait

        ld   t0, [frames]
        addi t0, t0, -1
        st   t0, [frames]
        bnez t0, frame
        halt

put:                                    ; put(a0 = x, a1 = y, a2 = cell value)
        li   t0, COLS
        mul  t0, a1, t0                 ; y * 40
        add  t0, t0, a0                 ; + x
        shli t0, t0, 2                  ; * 4 bytes per cell
        add  t0, t0, s1
        st   a2, [t0]
        ret

print_at:                               ; print_at(a0 = string, a1 = x, a2 = y, a3 = colors)
        li   t0, COLS
        mul  t0, a2, t0
        add  t0, t0, a1
        shli t0, t0, 2
        add  t0, t0, s1                 ; t0 = address of the first cell
print_at_loop:
        ldbu t1, [a0]
        beqz t1, print_at_done
        or   t1, t1, a3                 ; character + colors
        st   t1, [t0]
        addi a0, a0, 1
        addi t0, t0, 4
        j    print_at_loop
print_at_done:
        ret
