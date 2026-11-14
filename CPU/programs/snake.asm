; Snake: steer with the arrow keys or WASD, eat the apples, don't hit the wall or yourself.
; q quits. The score is printed when the game ends. If the snake fills the whole playfield
; you win (YOU WIN on the screen), and you land in the menu again.
;
; Menu: before every round you can change the size of the playfield (columns and rows), the
; speed and the number of apples. Up/down (W/S) picks a line, left/right (A/D) changes it,
; space or Enter starts. The settings are words at the start of data memory (settings:), so
; they can also be changed there, and they are kept for the next round.
;
; The playfield is a grid of cells, every cell is 5 x 5 pixels (so 25 x 19 is the most that
; fits on the screen), centered on the screen. The outer ring of cells is the wall. The snake
; is a ring buffer of cell numbers in data memory (at BUF): oldest cell at the tail, newest
; at the head. A move draws the new head (with eyes that look where it goes), erases the old
; tail and colors the whole body again, from dark green at the tail to bright at the head, so
; you can see which part goes next. What is in front of the snake is found by reading the
; middle pixel of the cell back from the screen: black = free, red = apple, else = crash.
;
; Keys are put in a small queue (up to 3 turns), so two quick key presses become two turns
; on two moves instead of the second one replacing the first.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ CONSOLE,    0x00
        .equ PRINT_INT,  0x04
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ RANDOM,     0x14
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24
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
        .equ WHITE,      0xFF
        .equ GREY,       0x92

        ; settings (in data memory, one word each, in the order of the menu lines)
        .equ S_COLS,     0              ; columns of the playfield
        .equ S_ROWS,     4
        .equ S_LEVEL,    8              ; speed 1 (slow) to 10 (fast)
        .equ S_APPLES,   12             ; apples on the playfield at all times
        .equ S_SEL,      16             ; the menu line that is selected
        .equ S_BASE,     20             ; address of the top left pixel of the playfield

        ; stack frame (s0 = head x, s1 = head y, s2/s3 = the last turn that was asked for)
        .equ HEAD_I,     0              ; ring index of the head
        .equ TAIL_I,     4              ; ring index of the tail
        .equ SCORE,      8
        .equ DEADLINE,   12             ; the refresh at which the next move is due
        .equ MOVE_X,     16             ; direction the snake moves in
        .equ MOVE_Y,     20
        .equ QN,         24             ; turns waiting in the queue
        .equ Q,          28             ; the queue: 3 x (dx, dy)
        .equ STEPV,      52             ; screen refreshes per move
        .equ TMP,        56

        ; glyph numbers of the little font (3 x 5 pixels), digits are their own number
        .equ G_A,        10
        .equ G_C,        11
        .equ G_D,        12
        .equ G_E,        13
        .equ G_K,        14
        .equ G_L,        15
        .equ G_N,        16
        .equ G_O,        17
        .equ G_P,        18
        .equ G_R,        19
        .equ G_S,        20
        .equ G_T,        21
        .equ G_W,        22
        .equ G_GT,       23             ; the > in front of the selected line
        .equ G_SP,       24             ; blank
        .equ G_Y,        25
        .equ G_U,        26
        .equ G_I,        27

        .data
settings:
        .word 25, 19, 5, 1, 0, 0        ; columns, rows, speed, apples, selected line, S_BASE
limits: .byte 8, 25,  8, 19,  1, 10,  1, 9    ; (smallest, biggest) of each line
shades: .byte 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x5C      ; tail ... head
font:   .byte 7, 5, 5, 5, 7             ; 0
        .byte 2, 6, 2, 2, 7             ; 1
        .byte 7, 1, 7, 4, 7             ; 2
        .byte 7, 1, 7, 1, 7             ; 3
        .byte 5, 5, 7, 1, 1             ; 4
        .byte 7, 4, 7, 1, 7             ; 5
        .byte 7, 4, 7, 5, 7             ; 6
        .byte 7, 1, 1, 1, 1             ; 7
        .byte 7, 5, 7, 5, 7             ; 8
        .byte 7, 5, 7, 1, 7             ; 9
        .byte 2, 5, 7, 5, 5             ; A
        .byte 7, 4, 4, 4, 7             ; C
        .byte 6, 5, 5, 5, 6             ; D
        .byte 7, 4, 6, 4, 7             ; E
        .byte 5, 5, 6, 5, 5             ; K
        .byte 4, 4, 4, 4, 7             ; L
        .byte 7, 5, 5, 5, 5             ; N
        .byte 7, 5, 5, 5, 7             ; O
        .byte 7, 5, 7, 4, 4             ; P
        .byte 6, 5, 6, 5, 5             ; R
        .byte 7, 4, 7, 1, 7             ; S
        .byte 7, 2, 2, 2, 2             ; T
        .byte 5, 5, 7, 7, 5             ; W
        .byte 4, 2, 1, 2, 4             ; >
        .byte 0, 0, 0, 0, 0             ; blank
        .byte 5, 5, 2, 2, 2             ; Y
        .byte 5, 5, 5, 5, 7             ; U
        .byte 7, 2, 2, 2, 7             ; I
t_snake:  .byte G_S, G_N, G_A, G_K, G_E, 255
t_cols:   .byte G_C, G_O, G_L, G_S, 255
t_rows:   .byte G_R, G_O, G_W, G_S, 255
t_speed:  .byte G_S, G_P, G_E, G_E, G_D, 255
t_apples: .byte G_A, G_P, G_P, G_L, G_E, G_S, 255
t_start:  .byte G_S, G_P, G_A, G_C, G_E, G_SP, G_S, G_T, G_A, G_R, G_T, 255
t_win:    .byte G_Y, G_O, G_U, G_SP, G_W, G_I, G_N, 255
over:   .string "game over, score: "
won:    .string "you win, score: "

        .text
start:  li   sp, 0x00040000
        addi sp, sp, -64

menu:   li   t0, IO                     ; throw away keys pressed before (or while dying)
mdrain: ld   t1, [t0+KEY_STATUS]
        beqz t1, menu_draw
        ld   t1, [t0+KEY_DATA]
        j    mdrain
menu_draw:
        call draw_menu
menu_wait:
        li   t0, IO
        ld   t1, [t0+KEY_STATUS]
        beqz t1, menu_wait
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        beq  t1, t2, menu_quit
        li   t2, ' '
        beq  t1, t2, play
        li   t2, 10
        beq  t1, t2, play
        la   t3, settings
        ld   t4, [t3+S_SEL]
        li   t2, UP
        beq  t1, t2, m_up
        li   t2, 'w'
        beq  t1, t2, m_up
        li   t2, DOWN
        beq  t1, t2, m_down
        li   t2, 's'
        beq  t1, t2, m_down
        li   t2, LEFT
        beq  t1, t2, m_left
        li   t2, 'a'
        beq  t1, t2, m_left
        li   t2, RIGHT
        beq  t1, t2, m_right
        li   t2, 'd'
        beq  t1, t2, m_right
        j    menu_wait
m_up:   addi t4, t4, 3                  ; one line up = three lines down, around 4 lines
        j    m_sel
m_down: addi t4, t4, 1
m_sel:  andi t4, t4, 3
        st   t4, [t3+S_SEL]
        j    menu_draw
m_left: li   a0, -1
        call adjust
        j    menu_draw
m_right:
        li   a0, 1
        call adjust
        j    menu_draw
menu_quit:
        halt

play:   la   s0, settings               ; the playfield is centered: work out where it starts
        ld   t0, [s0+S_COLS]
        ld   t1, [s0+S_ROWS]
        li   t2, 5
        mul  t0, t0, t2
        li   t3, 128
        sub  t3, t3, t0
        shri t3, t3, 1                  ; x offset in pixels
        mul  t1, t1, t2
        li   t4, 96
        sub  t4, t4, t1
        shri t4, t4, 1                  ; y offset in pixels
        shli t4, t4, 7
        add  t3, t3, t4
        li   t0, FB
        add  t3, t3, t0
        st   t3, [s0+S_BASE]
        ld   t0, [s0+S_LEVEL]           ; speed 1 to 10 = 11 to 2 screen refreshes per move
        li   t1, 12
        sub  t1, t1, t0
        st   t1, [sp+STEPV]

        li   t0, FB                     ; black screen
        li   t1, FB + 128 * 96
clear:  st   r0, [t0]
        addi t0, t0, 4
        bne  t0, t1, clear

        ld   s2, [s0+S_COLS]
        ld   s3, [s0+S_ROWS]
        li   s0, 0                      ; the wall: top and bottom row
wall_x: mov  a0, s0
        li   a1, 0
        li   a2, WALL
        call cell
        mov  a0, s0
        addi a1, s3, -1
        li   a2, WALL
        call cell
        addi s0, s0, 1
        bne  s0, s2, wall_x
        li   s0, 1                      ; left and right column
wall_y: li   a0, 0
        mov  a1, s0
        li   a2, WALL
        call cell
        addi a0, s2, -1
        mov  a1, s0
        li   a2, WALL
        call cell
        addi s0, s0, 1
        addi t0, s3, -1
        bne  s0, t0, wall_y

        shri s1, s2, 1                  ; the snake: 3 cells in the middle, moving right
        addi s0, s1, -2
snake:  sub  t0, s0, s1
        addi t0, t0, 2
        shli t0, t0, 2
        li   t1, BUF
        add  t0, t0, t1
        shri t1, s3, 1
        shli t1, t1, 8
        add  t1, t1, s0                 ; cell number: y * 256 + x
        st   t1, [t0]
        mov  a0, s0
        shri a1, s3, 1
        li   a2, 0x04
        call cell
        addi s0, s0, 1
        addi t0, s1, 1
        bne  s0, t0, snake
        mov  s0, s1
        shri s1, s3, 1
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
        la   t0, settings               ; the apples
        ld   t0, [t0+S_APPLES]
        st   t0, [sp+TMP]
apples: call place_food
        ld   t0, [sp+TMP]
        addi t0, t0, -1
        st   t0, [sp+TMP]
        bnez t0, apples
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        ld   t1, [t0+VSYNC]
        ld   t2, [sp+STEPV]
        add  t1, t1, t2
        st   t1, [sp+DEADLINE]

wait:   call read_keys                  ; until the next move is due
        li   t0, IO
        ld   t1, [t0+VSYNC]
        ld   t2, [sp+DEADLINE]
        sub  t1, t1, t2
        blt  t1, r0, wait
        ld   t3, [sp+STEPV]
        add  t2, t2, t3
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
        ld   t0, [sp+SCORE]             ; ate an apple: grow by keeping the tail
        addi t0, t0, 1
        st   t0, [sp+SCORE]
        ld   t1, [sp+HEAD_I]            ; is the whole playfield full of snake? then you won
        ld   t2, [sp+TAIL_I]
        sub  t1, t1, t2
        addi t1, t1, 1
        andi t1, t1, RING - 1           ; length of the snake
        la   t2, settings
        ld   t3, [t2+S_COLS]
        addi t3, t3, -2
        ld   t4, [t2+S_ROWS]
        addi t4, t4, -2
        mul  t3, t3, t4                 ; cells inside the wall
        beq  t1, t3, win
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

win:    call fade
        li   a0, 50
        li   a1, 44
        la   a2, t_win
        li   a3, 0xFC                   ; yellow
        call draw_text
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        la   a0, won
        j    ended

crash:  la   a0, over                   ; show the crash for a second, then back to the menu
ended:  call print_score
        li   t0, IO
        ld   t1, [t0+VSYNC]
        addi t1, t1, 60
crash_wait:
        ld   t2, [t0+VSYNC]
        sub  t2, t2, t1
        blt  t2, r0, crash_wait
        j    start

quit:   la   a0, over
        call print_score
        halt

print_score:                            ; prints the text in a0 and the score
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
        la   t0, settings
        ld   t0, [t0+S_BASE]            ; where the playfield starts on the screen
        add  a3, a3, t0
        ret

cell:                                   ; cell(a0 = x, a1 = y, a2 = color): 5 x 5 pixels
        li   t0, 5 * 128
        mul  a3, a1, t0
        shli t0, a0, 2
        add  t0, t0, a0
        add  a3, a3, t0
        la   t0, settings
        ld   t0, [t0+S_BASE]
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
        li   t4, 64                     ; random tries, then look at every cell
food:   la   t3, settings
        li   t0, IO
        ld   t1, [t0+RANDOM]
        shri t1, t1, 8
        ld   t2, [t3+S_COLS]
        addi t2, t2, -2
        modu a0, t1, t2
        addi a0, a0, 1
        ld   t1, [t0+RANDOM]
        shri t1, t1, 12
        ld   t2, [t3+S_ROWS]
        addi t2, t2, -2
        modu a1, t1, t2
        addi a1, a1, 1
        call cell_addr
        ldbu t1, [a3+2*128+2]
        beqz t1, place
        addi t4, t4, -1                 ; taken by the snake: try again
        bnez t4, food
        la   t3, settings               ; nearly full: take the first free cell
        ld   t2, [t3+S_COLS]
        addi t2, t2, -1                 ; the wall column
        ld   t3, [t3+S_ROWS]
        addi t3, t3, -1                 ; the wall row
        li   a1, 1
scan_y: li   a0, 1
scan_x: call cell_addr
        ldbu t1, [a3+2*128+2]
        beqz t1, place
        addi a0, a0, 1
        bne  a0, t2, scan_x
        addi a1, a1, 1
        bne  a1, t3, scan_y
        pop  lr                         ; no free cell at all: no more apples
        ret
place:  call draw_apple
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

; ---------- the menu ----------

adjust:                                 ; change the selected setting by a0 (-1 or 1), within its limits
        la   t0, settings
        ld   t1, [t0+S_SEL]
        shli t2, t1, 2
        add  t2, t2, t0                 ; t2 = address of the value
        ld   t3, [t2]
        add  t3, t3, a0
        la   t0, limits
        shli t1, t1, 1
        add  t0, t0, t1                 ; t0 = (smallest, biggest) of this line
        ldbu t4, [t0]
        bge  t3, t4, adj_hi
        mov  t3, t4
adj_hi: ldbu t4, [t0+1]
        ble  t3, t4, adj_set
        mov  t3, t4
adj_set:
        st   t3, [t2]
        ret

draw_menu:
        push lr
        li   t0, FB                     ; black screen
        li   t1, FB + 128 * 96
dm_clear:
        st   r0, [t0]
        addi t0, t0, 4
        bne  t0, t1, dm_clear
        li   a0, 54
        li   a1, 6
        la   a2, t_snake
        li   a3, LEAF
        call draw_text
        li   a1, 22
        la   a2, t_cols
        li   a3, 0
        call menu_row
        li   a1, 34
        la   a2, t_rows
        li   a3, 1
        call menu_row
        li   a1, 46
        la   a2, t_speed
        li   a3, 2
        call menu_row
        li   a1, 58
        la   a2, t_apples
        li   a3, 3
        call menu_row
        li   a0, 42
        li   a1, 82
        la   a2, t_start
        li   a3, STEM
        call draw_text
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        pop  lr
        ret

menu_row:                               ; a1 = y, a2 = label, a3 = number of the line
        push lr
        push s0
        push s1
        mov  s0, a1
        mov  s1, a3
        la   t0, settings
        ld   t1, [t0+S_SEL]
        li   a3, GREY
        bne  t1, s1, mr_text
        li   a3, WHITE                  ; the selected line is white, with a > in front
        push a2
        li   a0, 1
        li   a2, G_GT
        call draw_glyph
        pop  a2
mr_text:
        li   a0, 8
        mov  a1, s0
        call draw_text
        la   t0, settings
        shli t1, s1, 2
        add  t1, t1, t0
        ld   a2, [t1]
        li   a0, 92
        mov  a1, s0
        call draw_num
        pop  s1
        pop  s0
        pop  lr
        ret

draw_text:                              ; a0 = x, a1 = y, a2 = glyph numbers ending with 255, a3 = color
        push lr
        push s0
        mov  s0, a2
dt_loop:
        ldbu a2, [s0]
        li   t0, 255
        beq  a2, t0, dt_done
        call draw_glyph
        addi a0, a0, 4
        addi s0, s0, 1
        j    dt_loop
dt_done:
        pop  s0
        pop  lr
        ret

draw_num:                               ; a0 = x, a1 = y, a2 = number 0 to 99, a3 = color
        push lr
        push s0
        li   t0, 10
        modu s0, a2, t0                 ; the ones
        divu a2, a2, t0                 ; the tens (nothing is drawn when it is 0)
        beqz a2, dn_ones
        call draw_glyph
dn_ones:
        addi a0, a0, 4
        mov  a2, s0
        call draw_glyph
        pop  s0
        pop  lr
        ret

draw_glyph:                             ; a0 = x, a1 = y (in pixels), a2 = glyph number, a3 = color
        shli t0, a1, 7
        add  t0, t0, a0
        li   t1, FB
        add  t0, t0, t1                 ; t0 = the top left pixel
        shli t2, a2, 2
        add  t2, t2, a2                 ; 5 bytes per glyph
        la   t1, font
        add  t1, t1, t2
        li   t2, 5                      ; rows
g_row:  ldbu t3, [t1]
        andi t4, t3, 4
        beqz t4, g_1
        stb  a3, [t0]
g_1:    andi t4, t3, 2
        beqz t4, g_2
        stb  a3, [t0+1]
g_2:    andi t4, t3, 1
        beqz t4, g_3
        stb  a3, [t0+2]
g_3:    addi t1, t1, 1
        addi t0, t0, 128
        addi t2, t2, -1
        bnez t2, g_row
        ret
