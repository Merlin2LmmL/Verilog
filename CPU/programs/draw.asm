; Draw on the pixel screen with the keyboard: arrow keys or WASD move the pen,
; space changes the color, c clears the screen, q quits.
; The pen is white, and where it was it leaves a dot in the current color.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ CONSOLE,    0x00
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ FB_SHOW,    0x20
        .equ W,          128
        .equ H,          96
        .equ DOT,        2              ; the pen is 2 x 2 pixels
        .equ UP,         0x80           ; key codes of the arrow keys
        .equ DOWN,       0x81
        .equ LEFT,       0x82
        .equ RIGHT,      0x83
        .equ WHITE,      0xFF
        .equ NCOLORS,    7

        .data
colors: .byte 0xE0, 0xF4, 0xFC, 0x1C, 0x1F, 0x03, 0xE3     ; red orange yellow green cyan blue magenta
help:   .string "arrows or WASD: move, space: color, c: clear, q: quit\n"

        .text
start:  li   sp, 0x00040000
        li   s3, IO
        li   s0, W // 2                 ; pen x
        li   s1, H // 2                 ; pen y
        li   s2, 0                      ; number of the color
        call clear
        call show_pen
        la   a0, help
        call print

wait:   ld   t0, [s3+KEY_STATUS]        ; wait for a key
        beqz t0, wait
        ld   t0, [s3+KEY_DATA]
        push t0
        mov  a0, s0                     ; leave a dot in the pen color
        mov  a1, s1
        call pen_color
        call dot
        pop  t0

        li   t1, UP
        beq  t0, t1, up
        li   t1, 'w'
        beq  t0, t1, up
        li   t1, DOWN
        beq  t0, t1, down
        li   t1, 's'
        beq  t0, t1, down
        li   t1, LEFT
        beq  t0, t1, left
        li   t1, 'a'
        beq  t0, t1, left
        li   t1, RIGHT
        beq  t0, t1, right
        li   t1, 'd'
        beq  t0, t1, right
        li   t1, ' '
        beq  t0, t1, next_color
        li   t1, 'c'
        beq  t0, t1, wipe
        li   t1, 'q'
        beq  t0, t1, quit
        j    moved                      ; any other key: nothing happens

up:     addi s1, s1, -DOT               ; move, but not off the screen
        bge  s1, r0, moved
        addi s1, s1, DOT
        j    moved
down:   addi s1, s1, DOT
        li   t1, H - DOT
        ble  s1, t1, moved
        addi s1, s1, -DOT
        j    moved
left:   addi s0, s0, -DOT
        bge  s0, r0, moved
        addi s0, s0, DOT
        j    moved
right:  addi s0, s0, DOT
        li   t1, W - DOT
        ble  s0, t1, moved
        addi s0, s0, -DOT
        j    moved
next_color:
        addi s2, s2, 1
        li   t1, NCOLORS
        blt  s2, t1, moved
        li   s2, 0
        j    moved
wipe:   call clear
moved:  call show_pen
        j    wait
quit:   halt

show_pen:                               ; draw the white pen and show the frame
        push lr
        mov  a0, s0
        mov  a1, s1
        li   a2, WHITE
        call dot
        st   r0, [s3+FB_SHOW]
        pop  lr
        ret

pen_color:                              ; a2 = colors[s2]
        la   t1, colors
        add  t1, t1, s2
        ldbu a2, [t1]
        ret

dot:                                    ; dot(a0 = x, a1 = y, a2 = color), 2 x 2 pixels
        shli t1, a1, 7                  ; y * 128
        add  t1, t1, a0
        li   t2, FB
        add  t1, t1, t2
        stb  a2, [t1]
        stb  a2, [t1+1]
        stb  a2, [t1+W]
        stb  a2, [t1+W+1]
        ret

clear:                                  ; the whole screen black, 4 pixels per store
        li   t1, FB
        li   t2, FB + W * H
clear_loop:
        st   r0, [t1]
        addi t1, t1, 4
        bne  t1, t2, clear_loop
        ret

print:                                  ; print(a0 = string)
        ldbu t1, [a0]
        beqz t1, print_done
        st   t1, [s3+CONSOLE]
        addi a0, a0, 1
        j    print
print_done:
        ret
