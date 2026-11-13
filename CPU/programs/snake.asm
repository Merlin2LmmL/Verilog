; Snake: steer with the arrow keys or WASD, eat the red food, don't hit the wall or yourself.
; q quits. The game starts when you press a key, and after a crash it starts over and waits
; for a key again. The score is printed when the game ends.
;
; The playfield is a grid of 25 x 19 cells, every cell is 5 x 5 pixels. The outer ring of
; cells is the wall. The snake is a ring buffer of cell numbers in data memory (at BUF):
; oldest cell at the tail, newest at the head. A move draws the new head (with eyes that
; look where it goes), erases the old tail and colors the whole body again, from dark green
; at the tail to bright at the head, so you can see which part goes next. What is in front
; of the snake is found by reading the middle pixel of the cell back from the screen: black =
; free, red = apple, else = crash.
;
; Keys are put in a small queue (up to 3 turns), so two quick key presses become two turns
; on two moves instead of the second one replacing the first. One move every STEP screen
; refreshes.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ CONSOLE,    0x00
        .equ PRINT_INT,  0x04
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ RANDOM,     0x14
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24
        .equ GW,         25             ; grid size in cells
        .equ GH,         19
        .equ STEP,       7              ; screen refreshes per move: 8.6 moves per second
        .equ RING,       512            ; ring buffer entries (more than cells on the grid)
        .equ BUF,        0x00020000     ; the ring buffer: RING words of free data memory
        .equ UP,         0x80           ; key codes of the arrow keys
        .equ DOWN,       0x81
        .equ LEFT,       0x82
        .equ RIGHT,      0x83
        .equ WALL,       0x6D           ; grey
        .equ HEAD,       0x7C           ; yellow green
        .equ EYE,        0xFF           ; white (the pupils are black)
        .equ FOOD,       0xE0           ; red
        .equ SHINE,      0xF6           ; light red: the shine on the apple
        .equ STEM,       0x64           ; brown
        .equ LEAF,       0x1C           ; green

        ; stack frame (s0 = head x, s1 = head y, s2/s3 = the last turn that was asked for)
        .equ HEAD_I,     0              ; ring index of the head
        .equ TAIL_I,     4              ; ring index of the tail
        .equ SCORE,      8
        .equ DEADLINE,   12             ; the refresh at which the next move is due
        .equ MOVE_X,     16             ; direction the snake moves in
        .equ MOVE_Y,     20
        .equ QN,         24             ; turns waiting in the queue
        .equ Q,          28             ; the queue: 3 x (dx, dy)

        .data
shades: .byte 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x5C      ; tail ... head
over:   .string "game over, score: "

        .text
start:  li   sp, 0x00040000
        addi sp, sp, -64

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

        li   s0, 11                     ; the snake: 3 cells in the middle, moving right
snake:  addi t0, s0, -11
        shli t0, t0, 2
        li   t1, BUF
        add  t0, t0, t1
        addi t1, s0, 9 << 8             ; cell number: y * 256 + x
        st   t1, [t0]
        mov  a0, s0
        li   a1, 9
        li   a2, 0x04
        call cell
        addi s0, s0, 1
        li   t0, 14
        bne  s0, t0, snake
        li   s0, 13
        li   s1, 9
        li   s2, 1
        li   s3, 0
        li   t0, 2
        st   t0, [sp+HEAD_I]
        st   r0, [sp+TAIL_I]
        st   r0, [sp+SCORE]
        st   r0, [sp+QN]
        st   s2, [sp+MOVE_X]
        st   s3, [sp+MOVE_Y]
        call draw_head
        call fade
        call place_food
        li   t0, IO
        st   r0, [t0+FB_SHOW]
drain:  ld   t1, [t0+KEY_STATUS]        ; throw away keys pressed before (or while dying)
        beqz t1, ready
        ld   t1, [t0+KEY_DATA]
        j    drain
ready:  ld   t1, [t0+KEY_STATUS]        ; the game starts with the next key
        beqz t1, ready
        call read_keys                  ; that key may already be the first turn (q quits)
        li   t0, IO
        ld   t1, [t0+VSYNC]
        addi t1, t1, STEP
        st   t1, [sp+DEADLINE]

wait:   call read_keys                  ; until the next move is due
        li   t0, IO
        ld   t1, [t0+VSYNC]
        ld   t2, [sp+DEADLINE]
        sub  t1, t1, t2
        blt  t1, r0, wait
        addi t2, t2, STEP
        st   t2, [sp+DEADLINE]

        ld   t0, [sp+QN]                ; take the next turn from the queue
        beqz t0, moving
        addi t0, t0, -1
        st   t0, [sp+QN]
        ld   t1, [sp+Q]
        ld   t2, [sp+Q+4]
        st   t1, [sp+MOVE_X]
        st   t2, [sp+MOVE_Y]
        ld   t1, [sp+Q+8]
        ld   t2, [sp+Q+12]
        st   t1, [sp+Q]
        st   t2, [sp+Q+4]
        ld   t1, [sp+Q+16]
        ld   t2, [sp+Q+20]
        st   t1, [sp+Q+8]
        st   t2, [sp+Q+12]

moving: ld   t0, [sp+MOVE_X]
        ld   t1, [sp+MOVE_Y]
        add  s0, s0, t0
        add  s1, s1, t1

        mov  a0, s0                     ; what is in the new cell?
        mov  a1, s1
        call cell_addr
        ldbu t4, [a3+2*128+2]           ; the middle pixel: t4 = black, food or something to crash into
        beqz t4, go
        li   t0, FOOD
        bne  t4, t0, crash

go:     ld   t2, [sp+HEAD_I]            ; add the head to the ring buffer
        addi t2, t2, 1
        andi t2, t2, RING - 1
        st   t2, [sp+HEAD_I]
        shli t3, s1, 8
        add  t3, t3, s0
        shli t2, t2, 2
        li   t0, BUF
        add  t2, t2, t0
        st   t3, [t2]
        mov  a0, s0
        mov  a1, s1
        call draw_head

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
        andi a0, t3, 255
        shri a1, t3, 8
        li   a2, 0
        call cell
        ld   t2, [sp+TAIL_I]
        addi t2, t2, 1
        andi t2, t2, RING - 1
        st   t2, [sp+TAIL_I]

shown:  call fade
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        j    wait

crash:  call print_score                ; show the crash for a second, then start over
        li   t0, IO
        ld   t1, [t0+VSYNC]
        addi t1, t1, 60
crash_wait:
        ld   t2, [t0+VSYNC]
        sub  t2, t2, t1
        blt  t2, r0, crash_wait
        j    start

quit:   call print_score
        halt

print_score:
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
        ret

read_keys:                              ; take all waiting keys and queue the turns
        li   t0, IO
keys:   ld   t1, [t0+KEY_STATUS]
        beqz t1, keys_done
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        beq  t1, t2, quit
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
k_try:  ld   t2, [sp+QN]
        li   t3, 3
        bge  t2, t3, keys               ; the queue is full
        add  t3, s2, a0                 ; turning around on the spot is not allowed
        add  t4, s3, a1
        or   t3, t3, t4
        beqz t3, keys
        sub  t3, a0, s2                 ; neither is asking for the same direction again
        sub  t4, a1, s3
        or   t3, t3, t4
        beqz t3, keys
        shli t3, t2, 3                  ; put it at the end of the queue
        add  t3, t3, sp
        st   a0, [t3+Q]
        st   a1, [t3+Q+4]
        addi t2, t2, 1
        st   t2, [sp+QN]
        mov  s2, a0
        mov  s3, a1
        j    keys
keys_done:
        ret

cell_addr:                              ; a3 = address of the top left pixel of cell (a0, a1)
        li   t0, 5 * 128
        mul  a3, a1, t0
        shli t0, a0, 2
        add  t0, t0, a0                 ; x * 5
        add  a3, a3, t0
        li   t0, FB
        add  a3, a3, t0
        ret

cell:                                   ; cell(a0 = x, a1 = y, a2 = color): 5 x 5 pixels
        li   t0, 5 * 128
        mul  a3, a1, t0
        shli t0, a0, 2
        add  t0, t0, a0
        add  a3, a3, t0
        li   t0, FB
        add  a3, a3, t0                 ; a3 = the cell's top left pixel, stays
        mov  t2, a3
        li   t1, 5                      ; rows
cell_row:
        stb  a2, [t2]
        stb  a2, [t2+1]
        stb  a2, [t2+2]
        stb  a2, [t2+3]
        stb  a2, [t2+4]
        addi t2, t2, 128
        addi t1, t1, -1
        bnez t1, cell_row
        ret

draw_head:                              ; the head cell (a0, a1) with two eyes looking ahead
        push lr                         ; (so the frame is 4 bytes further away from sp here)
        li   a2, HEAD
        call cell                       ; leaves the cell's address in a3
        ld   t0, [sp+MOVE_X+4]          ; dx
        ld   t1, [sp+MOVE_Y+4]          ; dy
        shli t2, t0, 7
        add  t2, t2, t1                 ; one pixel to the side: (dy, dx)
        shli t3, t1, 7
        add  t3, t3, t0                 ; one pixel ahead: (dx, dy)
        addi a0, a3, 2 * 128 + 2        ; the middle of the cell (t4 must stay as it is: it holds what was in front)
        add  t0, a0, t2                 ; the white of the eyes: one pixel left and right of the middle
        sub  t1, a0, t2
        li   a2, EYE
        stb  a2, [t0]
        stb  a2, [t1]
        add  t0, t0, t3                 ; the pupils: one pixel further ahead, black
        add  t1, t1, t3
        stb  r0, [t0]
        stb  r0, [t1]
        pop  lr
        ret

fade:                                   ; color the body from dark (tail) to bright (next to the head)
        push lr
        push r0                         ; [sp] = k, the cell k after the tail
fade_loop:
        ld   t0, [sp]
        ld   t1, [sp+8+HEAD_I]
        ld   t2, [sp+8+TAIL_I]
        sub  t1, t1, t2
        andi t1, t1, RING - 1           ; cells between the tail and the head
        bge  t0, t1, fade_done          ; never the head itself
        add  t2, t2, t0
        andi t2, t2, RING - 1
        shli t2, t2, 2
        li   t3, BUF
        add  t2, t2, t3
        ld   t3, [t2]                   ; the cell number
        shli t4, t0, 3
        divu t4, t4, t1                 ; shade number 0 to 7: k * 8 / cells
        la   t2, shades
        add  t2, t2, t4
        ldbu a2, [t2]
        andi a0, t3, 255
        shri a1, t3, 8
        call cell
        ld   t0, [sp]
        addi t0, t0, 1
        st   t0, [sp]
        j    fade_loop
fade_done:
        pop  t0
        pop  lr
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
        call cell_addr
        ldbu t1, [a3+2*128+2]
        bnez t1, food                   ; taken by the snake: try again
        call draw_apple
        pop  lr
        ret

draw_apple:                             ; an apple in cell (a0, a1), 5 x 5 pixels:
        push lr                         ;     . . S L .      S = stem, L = leaf
        li   a2, FOOD                   ;     . s R R .      s = shine
        call cell                       ;     R R R R R
        stb  r0, [a3]                   ;     R R R R R
        stb  r0, [a3+1]                 ;     . R R R .
        stb  r0, [a3+4]                 ; (the corners get cut off, black)
        stb  r0, [a3+128]
        stb  r0, [a3+132]
        stb  r0, [a3+4*128]
        stb  r0, [a3+4*128+4]
        li   t0, STEM
        stb  t0, [a3+2]
        li   t0, LEAF
        stb  t0, [a3+3]
        li   t0, SHINE
        stb  t0, [a3+128+1]
        pop  lr
        ret
