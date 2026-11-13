; Snake: steer with the arrow keys or WASD, eat the red food, don't hit the wall or yourself.
; q quits. The score is printed when the game ends.
;
; The playfield is a grid of 32 x 24 cells, every cell is 4 x 4 pixels. The outer ring of
; cells is the wall. The snake is a ring buffer of cell numbers in data memory (at BUF) (oldest cell
; at the tail, newest at the head). Moving only draws the new head and erases the old tail,
; and what is in front of the snake is found by reading the pixel back from the screen:
; black = free, red = food, anything else = crash. One move every STEP screen refreshes.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ CONSOLE,    0x00
        .equ PRINT_INT,  0x04
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ RANDOM,     0x14
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24
        .equ GW,         32             ; grid size in cells
        .equ GH,         24
        .equ STEP,       6              ; screen refreshes per move: 10 moves per second
        .equ RING,       1024           ; ring buffer entries (more than cells on the grid)
        .equ BUF,        0x00020000     ; the ring buffer: RING words of free data memory
        .equ UP,         0x80           ; key codes of the arrow keys
        .equ DOWN,       0x81
        .equ LEFT,       0x82
        .equ RIGHT,      0x83
        .equ WALL,       0x6D           ; grey
        .equ BODY,       0x14           ; dark green
        .equ HEAD,       0x3D           ; light green
        .equ FOOD,       0xE0           ; red

        ; stack frame (s0 = head x, s1 = head y, s2/s3 = direction asked for with the keys)
        .equ HEAD_I,     0              ; ring index of the head
        .equ TAIL_I,     4              ; ring index of the tail
        .equ SCORE,      8
        .equ DEADLINE,   12             ; the refresh at which the next move is due
        .equ MOVE_X,     16             ; direction the snake really moved in last
        .equ MOVE_Y,     20

        .data
over:   .string "game over, score: "

        .text
start:  li   sp, 0x00040000
        addi sp, sp, -32

        li   t0, FB                     ; black screen
        li   t1, FB + 128 * 96
clear:  st   r0, [t0]
        addi t0, t0, 4
        bne  t0, t1, clear

        li   s0, 0                      ; the wall: top and bottom row
wall_x: mov  a0, s0
        li   a1, 0
        li   a2, WALL
        call cell
        mov  a0, s0
        li   a1, GH - 1
        li   a2, WALL
        call cell
        addi s0, s0, 1
        li   t0, GW
        bne  s0, t0, wall_x
        li   s0, 1                      ; left and right column
wall_y: li   a0, 0
        mov  a1, s0
        li   a2, WALL
        call cell
        li   a0, GW - 1
        mov  a1, s0
        li   a2, WALL
        call cell
        addi s0, s0, 1
        li   t0, GH - 1
        bne  s0, t0, wall_y

        li   s0, 14                     ; the snake: 3 cells in the middle, moving right
snake:  addi t0, s0, -14
        shli t0, t0, 2
        li   t1, BUF
        add  t0, t0, t1
        addi t1, s0, 12 * GW
        st   t1, [t0]
        mov  a0, s0
        li   a1, 12
        li   a2, BODY
        call cell
        addi s0, s0, 1
        li   t0, 17
        bne  s0, t0, snake
        li   s0, 16
        li   s1, 12
        li   s2, 1
        li   s3, 0
        mov  a0, s0
        mov  a1, s1
        li   a2, HEAD
        call cell
        li   t0, 2
        st   t0, [sp+HEAD_I]
        st   r0, [sp+TAIL_I]
        st   r0, [sp+SCORE]
        st   s2, [sp+MOVE_X]
        st   s3, [sp+MOVE_Y]
        call place_food
        st   r0, [sp+DEADLINE]
        li   t0, IO
        ld   t1, [t0+VSYNC]
        addi t1, t1, 30                 ; half a second to get ready
        st   t1, [sp+DEADLINE]
        st   r0, [t0+FB_SHOW]

wait:   call read_keys                  ; until the next move is due
        li   t0, IO
        ld   t1, [t0+VSYNC]
        ld   t2, [sp+DEADLINE]
        sub  t1, t1, t2
        blt  t1, r0, wait
        addi t2, t2, STEP
        st   t2, [sp+DEADLINE]

        st   s2, [sp+MOVE_X]            ; this is the direction now
        st   s3, [sp+MOVE_Y]
        mov  a0, s0                     ; the old head becomes body
        mov  a1, s1
        li   a2, BODY
        call cell
        add  s0, s0, s2
        add  s1, s1, s3

        shli a3, s1, 9                  ; what is in the new cell?
        shli t0, s0, 2
        add  a3, a3, t0
        li   t0, FB
        add  a3, a3, t0
        ldbu t4, [a3]                   ; t4 = black, food or something to crash into
        beqz t4, go
        li   t0, FOOD
        bne  t4, t0, game_over

go:     ld   t2, [sp+HEAD_I]            ; add the head to the ring buffer
        addi t2, t2, 1
        andi t2, t2, RING - 1
        st   t2, [sp+HEAD_I]
        shli t3, s1, 5
        add  t3, t3, s0
        shli t2, t2, 2
        li   t0, BUF
        add  t2, t2, t0
        st   t3, [t2]
        mov  a0, s0
        mov  a1, s1
        li   a2, HEAD
        call cell

        beqz t4, shrink
        ld   t0, [sp+SCORE]             ; ate the food: grow by keeping the tail
        addi t0, t0, 1
        st   t0, [sp+SCORE]
        call place_food
        j    shown

shrink: ld   t2, [sp+TAIL_I]            ; erase the tail
        shli t0, t2, 2
        li   t1, BUF
        add  t0, t0, t1
        ld   t3, [t0]
        andi a0, t3, GW - 1
        shri a1, t3, 5
        li   a2, 0
        call cell
        ld   t2, [sp+TAIL_I]
        addi t2, t2, 1
        andi t2, t2, RING - 1
        st   t2, [sp+TAIL_I]

shown:  li   t0, IO
        st   r0, [t0+FB_SHOW]
        j    wait

game_over:
        la   a0, over
        li   t0, IO
print:  ldbu t1, [a0]
        beqz t1, printed
        st   t1, [t0+CONSOLE]
        addi a0, a0, 1
        j    print
printed:
        ld   t1, [sp+SCORE]
        st   t1, [t0+PRINT_INT]
        li   t1, 10
        st   t1, [t0+CONSOLE]
        halt

read_keys:                              ; take all waiting keys, the last good one sets s2/s3
        li   t0, IO
keys:   ld   t1, [t0+KEY_STATUS]
        beqz t1, keys_done
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        beq  t1, t2, game_over
        li   t2, UP
        beq  t1, t2, k_up
        li   t2, 'w'
        beq  t1, t2, k_up
        li   t2, DOWN
        beq  t1, t2, k_down
        li   t2, 's'
        beq  t1, t2, k_down
        li   t2, LEFT
        beq  t1, t2, k_left
        li   t2, 'a'
        beq  t1, t2, k_left
        li   t2, RIGHT
        beq  t1, t2, k_right
        li   t2, 'd'
        beq  t1, t2, k_right
        j    keys
k_up:   li   a0, 0
        li   a1, -1
        j    k_try
k_down: li   a0, 0
        li   a1, 1
        j    k_try
k_left: li   a0, -1
        li   a1, 0
        j    k_try
k_right:
        li   a0, 1
        li   a1, 0
k_try:  ld   t2, [sp+MOVE_X]            ; turning around on the spot is not allowed
        ld   t3, [sp+MOVE_Y]
        add  t2, t2, a0
        add  t3, t3, a1
        or   t2, t2, t3
        beqz t2, keys
        mov  s2, a0
        mov  s3, a1
        j    keys
keys_done:
        ret

cell:                                   ; cell(a0 = x, a1 = y, a2 = color): 4 x 4 pixels
        li   t0, 0x01010101
        mul  a2, a2, t0                 ; the color in all 4 bytes
        shli a3, a1, 9                  ; y * 4 rows * 128
        shli t0, a0, 2
        add  a3, a3, t0
        li   t0, FB
        add  a3, a3, t0
        st   a2, [a3]
        st   a2, [a3+128]
        st   a2, [a3+256]
        st   a2, [a3+384]
        ret

place_food:                             ; a random free cell inside the wall
        push lr
food:   li   t0, IO
        ld   t1, [t0+RANDOM]
        shri t1, t1, 8
        li   t2, GW - 2
        modu a0, t1, t2
        addi a0, a0, 1
        ld   t1, [t0+RANDOM]
        shri t1, t1, 12
        li   t2, GH - 2
        modu a1, t1, t2
        addi a1, a1, 1
        shli a3, a1, 9
        shli t0, a0, 2
        add  a3, a3, t0
        li   t0, FB
        add  a3, a3, t0
        ldbu t1, [a3]
        bnez t1, food                   ; taken by the snake: try again
        li   a2, FOOD
        call cell
        pop  lr
        ret
