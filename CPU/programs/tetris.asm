; Tetris on the pixel screen. The field is 10 x 20 cells in the middle (every cell is 4 x 4
; pixels, drawn as 3 x 3 so you can see the grid), the next piece is shown on the right and
; three numbers on the left: score (white), cleared lines (green) and level (yellow).
;
; Keys: left / A and right / D move the piece, up / W turns it, down / S drops it one step,
; space drops it all the way, q quits. After game over, any key starts a new game. Holding
; left, right or down repeats it quickly, without the usual pause of the keyboard (KEYS_HELD).
;
; Every level (10 lines) makes the pieces fall faster. Clearing 1, 2, 3 or 4 lines at once is
; worth 100, 300, 500 or 800 points, times the level.
;
; The 7 pieces with their 4 turns are bitmasks of a 4 x 4 box (bit = row * 4 + column), 16 bits
; each, so one piece position is read with a single ldhu. The field is a byte per cell in RAM
; (0 = empty, otherwise the color of the piece that landed there); the falling piece is not
; part of it until it lands. A move is tried first with fits() and only done if it works.
;
; s0 points to the state block and is never changed. s1-s3 are only used as local variables
; inside one function (that never calls another function using them).

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ CONSOLE,    0x00
        .equ PRINT_INT,  0x04
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ RANDOM,     0x14
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24
        .equ KEYS_HELD,  0x28

        .equ TYPE,       0              ; state block: the falling piece (type 0-6, turn 0-3,
        .equ ROT,        4              ; position of its 4 x 4 box in cells), the next type,
        .equ PX,         8              ; score, lines, level, frames since the last drop,
        .equ PY,         12             ; and 1 after game over
        .equ NEXT,       16
        .equ SCORE,      20
        .equ LINES,      24
        .equ LEVEL,      28
        .equ TIMER,      32
        .equ OVER,       36
        .equ HPREV,      40             ; KEYS_HELD of the last frame and the frames until
        .equ RL,         44             ; left, right and down repeat while held
        .equ RR,         48
        .equ RD,         52

        .equ DAS,        9              ; frames before a held left / right repeats, then every ARR
        .equ ARR,        2
        .equ DAS_DOWN,   3              ; the same for down
        .equ ARR_DOWN,   2

        .equ BOARD,      0x1000         ; the field: 10 x 20 bytes
        .equ X0,         44             ; top left corner of the field on the screen
        .equ Y0,         8
        .equ GRAY,       0x6D
        .equ WHITE,      0xFF
        .equ GREEN,      0x1C
        .equ YELLOW,     0xFC
        .equ RED,        0xE0

        .data
pieces: ; 7 pieces x 4 turns x 16 bits (low byte first): I O T S Z J L
        .byte 0xF0, 0x00, 0x44, 0x44, 0x00, 0x0F, 0x22, 0x22   ; I
        .byte 0x66, 0x00, 0x66, 0x00, 0x66, 0x00, 0x66, 0x00   ; O
        .byte 0x72, 0x00, 0x62, 0x02, 0x70, 0x02, 0x32, 0x02   ; T
        .byte 0x36, 0x00, 0x62, 0x04, 0x60, 0x03, 0x31, 0x02   ; S
        .byte 0x63, 0x00, 0x64, 0x02, 0x30, 0x06, 0x32, 0x01   ; Z
        .byte 0x71, 0x00, 0x26, 0x02, 0x70, 0x04, 0x22, 0x03   ; J
        .byte 0x74, 0x00, 0x22, 0x06, 0x70, 0x01, 0x23, 0x02   ; L
points: .word 0, 100, 300, 500, 800     ; score for 0-4 lines at once
state:  .space 56                       ; (a word aligned address: after the two tables of words)
colors: .byte 0x1F, 0xFC, 0xE3, 0x1C, 0xE0, 0x2F, 0xEC    ; I O T S Z J L
font:   .byte 7, 5, 5, 5, 7             ; digits 0-9, every row is 3 pixels (bits 2..0)
        .byte 2, 6, 2, 2, 7
        .byte 7, 1, 7, 4, 7
        .byte 7, 1, 7, 1, 7
        .byte 5, 5, 7, 1, 1
        .byte 7, 4, 7, 1, 7
        .byte 7, 4, 7, 5, 7
        .byte 7, 1, 1, 1, 1
        .byte 7, 5, 7, 5, 7
        .byte 7, 5, 7, 1, 7
msg_over: .string "GAME OVER, score "

        .text
start:  li   sp, 0x00040000
        la   s0, state
        call new_game

loop:   call read_keys
        bnez a0, quit
        call gravity
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        ld   t1, [t0+VSYNC]
wait:   ld   t2, [t0+VSYNC]
        beq  t2, t1, wait
        j    loop
quit:   halt

; ---------------------------------------------------------------- game flow

new_game:
        push lr
        li   t0, FB                     ; black screen
        li   t1, FB + 128 * 96
ng_clr: st   r0, [t0]
        addi t0, t0, 4
        bne  t0, t1, ng_clr
        li   t0, BOARD                  ; empty field
        li   t1, BOARD + 200
ng_brd: st   r0, [t0]
        addi t0, t0, 4
        bne  t0, t1, ng_brd
        li   t4, GRAY                   ; walls
        li   a0, X0 - 2
        li   a1, Y0
        li   a2, 2
        li   a3, 80
        call rect
        li   t4, GRAY
        li   a0, X0 + 40
        li   a1, Y0
        li   a2, 2
        li   a3, 80
        call rect
        li   t4, GRAY
        li   a0, X0 - 2
        li   a1, Y0 + 80
        li   a2, 44
        li   a3, 2
        call rect
        st   r0, [s0+SCORE]
        st   r0, [s0+LINES]
        st   r0, [s0+OVER]
        li   t0, 1
        st   t0, [s0+LEVEL]
        call rand_piece
        st   a0, [s0+NEXT]
        call new_piece
        call draw_stats
        pop  lr
        ret

rand_piece:                             ; a0 = random piece type 0-6
        li   t0, IO
        ld   t1, [t0+RANDOM]
        shri t1, t1, 8
        li   t2, 7
        modu a0, t1, t2
        ret

new_piece:                              ; the next piece falls, a new next piece is chosen
        push lr
        ld   t0, [s0+NEXT]
        st   t0, [s0+TYPE]
        st   r0, [s0+ROT]
        st   r0, [s0+PY]
        st   r0, [s0+TIMER]
        li   t0, 3
        st   t0, [s0+PX]
        call rand_piece
        ld   t1, [s0+TYPE]
        bne  a0, t1, np_new
        call rand_piece                 ; the same piece twice: roll once more
np_new: st   a0, [s0+NEXT]
        li   t4, 0                      ; show the next piece on the right
        li   a0, 90
        li   a1, 18
        li   a2, 22
        li   a3, 20
        call rect
        ld   a0, [s0+NEXT]
        li   a1, 0
        call mask_of
        ld   t0, [s0+NEXT]
        la   t1, colors
        add  t1, t1, t0
        ldbu a3, [t1]
        li   a1, 12                     ; cells right of the field
        li   a2, 3
        call draw_mask
        ld   a0, [s0+TYPE]              ; room for it?
        li   a1, 0
        li   a2, 3
        li   a3, 0
        call fits
        beqz a0, np_over
        li   a0, 0
        call paint
        pop  lr
        ret
np_over:
        call game_over
        pop  lr
        ret

game_over:
        push lr
        li   t0, 1
        st   t0, [s0+OVER]
        li   t4, RED
        li   a0, X0 - 2
        li   a1, Y0 + 36
        li   a2, 44
        li   a3, 4
        call rect
        la   a0, msg_over
        call puts
        li   t0, IO
        ld   t1, [s0+SCORE]
        st   t1, [t0+PRINT_INT]
        li   t1, '\n'
        st   t1, [t0+CONSOLE]
        pop  lr
        ret

puts:                                   ; puts(a0 = zero-terminated string) to the console
        li   t1, IO
pu_loop:
        ldbu t0, [a0]
        beqz t0, pu_done
        st   t0, [t1+CONSOLE]
        addi a0, a0, 1
        j    pu_loop
pu_done:
        ret

gravity:                                ; every few frames the piece falls one step
        push lr
        ld   t0, [s0+OVER]
        bnez t0, gr_done
        ld   t0, [s0+TIMER]
        addi t0, t0, 1
        ld   t1, [s0+LEVEL]
        shli t1, t1, 2
        li   t2, 42
        sub  t1, t2, t1                 ; frames per step: 38, 34, ... never below 6
        li   t2, 6
        bge  t1, t2, gr_cmp
        li   t1, 6
gr_cmp: blt  t0, t1, gr_wait
        li   t0, 0
        st   t0, [s0+TIMER]
        call drop_step
        j    gr_done
gr_wait:
        st   t0, [s0+TIMER]
gr_done:
        pop  lr
        ret

drop_step:                              ; one step down, or land if that is not possible
        push lr
        li   a0, 0
        li   a1, 1
        li   a2, 0
        call move_piece
        bnez a0, ds_done
        call land
ds_done:
        pop  lr
        ret

land:                                   ; the piece is part of the field now
        push lr
        call lock_piece
        call clear_lines
        call add_score
        call new_piece
        pop  lr
        ret

; Keys come in two ways: KEY_DATA gives every press (also the computer's own repeats of a
; held key, which come only after a pause), KEYS_HELD tells which keys are down right now. A
; key from KEY_DATA only counts if its KEYS_HELD bit was not already set in the last frame, so
; the computer's repeats are ignored. While left, right or down stay held, the program repeats
; them itself: after DAS frames once, then every ARR frames.
read_keys:                              ; a0 = 1 if q was pressed
        addi sp, sp, -12
        st   lr, [sp+8]
        li   t0, IO
        ld   t1, [t0+KEYS_HELD]
        st   t1, [sp+0]                 ; the keys held now
rk_next:
        li   t0, IO
        ld   t1, [t0+KEY_STATUS]
        beqz t1, rk_held
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        beq  t1, t2, rk_quit
        mov  a0, t1
        call key_bit
        ld   t2, [s0+HPREV]
        and  t2, t2, a0
        bnez t2, rk_next                ; a repeat of a key that is held: ignore
        ld   t0, [s0+OVER]
        beqz t0, rk_play
        call new_game                   ; after game over any key starts a new game
        j    rk_next
rk_play:
        li   t2, 4
        beq  a0, t2, rk_left
        li   t2, 8
        beq  a0, t2, rk_right
        li   t2, 1
        beq  a0, t2, rk_turn
        li   t2, 2
        beq  a0, t2, rk_down
        li   t2, 16
        beq  a0, t2, rk_drop
        j    rk_next
rk_left:
        li   t0, DAS
        st   t0, [s0+RL]
        li   a0, -1
        li   a1, 0
        li   a2, 0
        call move_piece
        j    rk_next
rk_right:
        li   t0, DAS
        st   t0, [s0+RR]
        li   a0, 1
        li   a1, 0
        li   a2, 0
        call move_piece
        j    rk_next
rk_turn:
        li   a0, 0
        li   a1, 0
        li   a2, 1
        call move_piece
        bnez a0, rk_next
        li   a0, -1                     ; blocked: try one cell to the left or right, then two
        li   a1, 0
        li   a2, 1
        call move_piece
        bnez a0, rk_next
        li   a0, 1
        li   a1, 0
        li   a2, 1
        call move_piece
        bnez a0, rk_next
        li   a0, -2                     ; the long piece needs up to two
        li   a1, 0
        li   a2, 1
        call move_piece
        bnez a0, rk_next
        li   a0, 2
        li   a1, 0
        li   a2, 1
        call move_piece
        j    rk_next
rk_down:
        li   t0, DAS_DOWN
        st   t0, [s0+RD]
        call drop_step
        st   r0, [s0+TIMER]
        j    rk_next
rk_drop:
rk_fall:
        li   a0, 0
        li   a1, 1
        li   a2, 0
        call move_piece
        bnez a0, rk_fall
        call land
        j    rk_next

rk_held:                                ; keys held in this and the last frame repeat
        ld   t0, [s0+OVER]
        bnez t0, rk_save
        ld   t1, [sp+0]
        ld   t2, [s0+HPREV]
        and  t1, t1, t2
        st   t1, [sp+4]
        andi t0, t1, 4                  ; left
        beqz t0, rh_right
        ld   t0, [s0+RL]
        addi t0, t0, -1
        st   t0, [s0+RL]
        bnez t0, rh_right
        li   t0, ARR
        st   t0, [s0+RL]
        li   a0, -1
        li   a1, 0
        li   a2, 0
        call move_piece
rh_right:
        ld   t1, [sp+4]
        andi t0, t1, 8
        beqz t0, rh_down
        ld   t0, [s0+RR]
        addi t0, t0, -1
        st   t0, [s0+RR]
        bnez t0, rh_down
        li   t0, ARR
        st   t0, [s0+RR]
        li   a0, 1
        li   a1, 0
        li   a2, 0
        call move_piece
rh_down:
        ld   t1, [sp+4]
        andi t0, t1, 2
        beqz t0, rk_save
        ld   t0, [s0+RD]
        addi t0, t0, -1
        st   t0, [s0+RD]
        bnez t0, rk_save
        li   t0, ARR_DOWN
        st   t0, [s0+RD]
        call drop_step
        st   r0, [s0+TIMER]
rk_save:
        ld   t1, [sp+0]
        st   t1, [s0+HPREV]
        li   a0, 0
        j    rk_ret
rk_quit:
        li   a0, 1
rk_ret: ld   lr, [sp+8]
        addi sp, sp, 12
        ret

key_bit:                                ; key_bit(a0 = key) -> a0 = its KEYS_HELD bit, 0 if none
        li   t2, 0x82                   ; left
        beq  a0, t2, kb_left
        li   t2, 'a'
        beq  a0, t2, kb_left
        li   t2, 0x83                   ; right
        beq  a0, t2, kb_right
        li   t2, 'd'
        beq  a0, t2, kb_right
        li   t2, 0x80                   ; up
        beq  a0, t2, kb_up
        li   t2, 'w'
        beq  a0, t2, kb_up
        li   t2, 0x81                   ; down
        beq  a0, t2, kb_down
        li   t2, 's'
        beq  a0, t2, kb_down
        li   t2, ' '
        beq  a0, t2, kb_space
        li   a0, 0
        ret
kb_up:  li   a0, 1
        ret
kb_down:
        li   a0, 2
        ret
kb_left:
        li   a0, 4
        ret
kb_right:
        li   a0, 8
        ret
kb_space:
        li   a0, 16
        ret

; ---------------------------------------------------------------- pieces and field

mask_of:                                ; mask_of(a0 = type, a1 = turn) -> a0 = 16-bit mask
        shli t0, a0, 2
        add  t0, t0, a1
        shli t0, t0, 1
        la   t1, pieces
        add  t0, t0, t1
        ldhu a0, [t0]
        ret

; fits(a0 = type, a1 = turn, a2 = x, a3 = y) -> a0 = 1 if the piece is inside the field and
; does not overlap anything there
fits:   shli t0, a0, 2
        add  t0, t0, a1
        shli t0, t0, 1
        la   t1, pieces
        add  t0, t0, t1
        ldhu t3, [t0]
        li   t2, 0                      ; bit number 0-15
f_loop: shr  t0, t3, t2
        andi t0, t0, 1
        beqz t0, f_next
        andi t0, t2, 3                  ; x of this cell
        add  t0, t0, a2
        shri t1, t2, 2                  ; y of this cell
        add  t1, t1, a3
        blt  t0, r0, f_no
        li   t4, 10
        bge  t0, t4, f_no
        li   t4, 20
        bge  t1, t4, f_no
        blt  t1, r0, f_next
        li   t4, 10
        mul  t1, t1, t4
        add  t1, t1, t0
        li   t4, BOARD
        add  t1, t1, t4
        ldbu t1, [t1]
        bnez t1, f_no
f_next: addi t2, t2, 1
        li   t0, 16
        bne  t2, t0, f_loop
        li   a0, 1
        ret
f_no:   li   a0, 0
        ret

; move_piece(a0 = dx, a1 = dy, a2 = turns) -> a0 = 1 if it moved (otherwise nothing changes)
move_piece:
        addi sp, sp, -20
        st   lr, [sp+16]
        ld   t0, [s0+ROT]
        add  t0, t0, a2
        andi t0, t0, 3
        st   t0, [sp+0]                 ; new turn
        ld   t0, [s0+PX]
        add  t0, t0, a0
        st   t0, [sp+4]                 ; new x
        ld   t0, [s0+PY]
        add  t0, t0, a1
        st   t0, [sp+8]                 ; new y
        ld   a0, [s0+TYPE]
        ld   a1, [sp+0]
        ld   a2, [sp+4]
        ld   a3, [sp+8]
        call fits
        beqz a0, mp_no
        li   a0, 1
        call paint                      ; erase at the old place
        ld   t0, [sp+0]
        st   t0, [s0+ROT]
        ld   t0, [sp+4]
        st   t0, [s0+PX]
        ld   t0, [sp+8]
        st   t0, [s0+PY]
        li   a0, 0
        call paint                      ; draw at the new one
        li   a0, 1
        j    mp_ret
mp_no:  li   a0, 0
mp_ret: ld   lr, [sp+16]
        addi sp, sp, 20
        ret

paint:                                  ; paint(a0 = 1 to erase, 0 to draw) the falling piece
        addi sp, sp, -4
        st   lr, [sp]
        ld   t0, [s0+TYPE]
        la   t1, colors
        add  t1, t1, t0
        ldbu a3, [t1]
        beqz a0, pt_go
        li   a3, 0
pt_go:  ld   a0, [s0+TYPE]
        ld   a1, [s0+ROT]
        call mask_of
        ld   a1, [s0+PX]
        ld   a2, [s0+PY]
        call draw_mask
        ld   lr, [sp]
        addi sp, sp, 4
        ret

; draw_mask(a0 = mask, a1 = x, a2 = y, a3 = color): the cells of a 4 x 4 mask at field cell (x, y)
draw_mask:
        addi sp, sp, -16
        st   lr, [sp+12]
        st   a1, [sp+0]
        st   a2, [sp+4]
        st   a3, [sp+8]
        mov  s1, a0
        li   s2, 0
dm_loop:
        shr  t0, s1, s2
        andi t0, t0, 1
        beqz t0, dm_next
        ld   t1, [sp+0]
        andi t2, s2, 3
        add  a0, t1, t2
        ld   t1, [sp+4]
        shri t2, s2, 2
        add  a1, t1, t2
        blt  a1, r0, dm_next
        ld   a2, [sp+8]
        call cell
dm_next:
        addi s2, s2, 1
        li   t0, 16
        bne  s2, t0, dm_loop
        ld   lr, [sp+12]
        addi sp, sp, 16
        ret

cell:                                   ; cell(a0 = x, a1 = y, a2 = color) in field cells
        shli a0, a0, 2
        addi a0, a0, X0
        shli a1, a1, 2
        addi a1, a1, Y0
        mov  t4, a2
        li   a2, 3
        li   a3, 3
        j    rect                       ; (rect returns to our caller)

lock_piece:                             ; the piece's cells become part of the field
        push lr
        ld   a0, [s0+TYPE]
        ld   a1, [s0+ROT]
        call mask_of
        mov  t3, a0
        ld   t0, [s0+TYPE]
        la   t1, colors
        add  t1, t1, t0
        ldbu a3, [t1]
        li   t2, 0
lk_loop:
        shr  t0, t3, t2
        andi t0, t0, 1
        beqz t0, lk_next
        andi t0, t2, 3
        ld   t1, [s0+PX]
        add  t0, t0, t1                 ; x
        shri t1, t2, 2
        ld   a1, [s0+PY]
        add  t1, t1, a1                 ; y
        blt  t1, r0, lk_next
        li   a1, 10
        mul  t1, t1, a1
        add  t1, t1, t0
        li   a1, BOARD
        add  t1, t1, a1
        stb  a3, [t1]
lk_next:
        addi t2, t2, 1
        li   t0, 16
        bne  t2, t0, lk_loop
        pop  lr
        ret

clear_lines:                            ; removes the full rows -> a0 = how many
        li   a2, 0                      ; rows removed
        li   a3, 19                     ; row being checked, from the bottom
cl_row: li   t0, 10
        mul  t1, a3, t0
        li   t2, BOARD
        add  t1, t1, t2                 ; first byte of the row
        li   t3, 0
cl_chk: add  t4, t1, t3
        ldbu t4, [t4]
        beqz t4, cl_next                ; a gap: not full
        addi t3, t3, 1
        li   t4, 10
        bne  t3, t4, cl_chk
        addi t3, t1, 9                  ; full: everything above moves down one row
        li   t2, BOARD + 10
cl_mv:  blt  t3, t2, cl_top
        ldbu t4, [t3-10]
        stb  t4, [t3]
        addi t3, t3, -1
        j    cl_mv
cl_top: li   t3, BOARD                  ; the top row is empty now
cl_z:   stb  r0, [t3]
        addi t3, t3, 1
        li   t4, BOARD + 10
        bne  t3, t4, cl_z
        addi a2, a2, 1
        j    cl_row                     ; the same row again: what came down may be full too
cl_next:
        addi a3, a3, -1
        bge  a3, r0, cl_row
        mov  a0, a2
        ret

add_score:                              ; add_score(a0 = lines removed): score, level, new picture
        push lr
        beqz a0, as_done
        ld   t0, [s0+LINES]
        add  t0, t0, a0
        st   t0, [s0+LINES]
        li   t1, 10
        divu t1, t0, t1
        addi t1, t1, 1
        st   t1, [s0+LEVEL]
        la   t2, points
        shli t3, a0, 2
        add  t2, t2, t3
        ld   t3, [t2]
        mul  t3, t3, t1                 ; points * level
        ld   t0, [s0+SCORE]
        add  t0, t0, t3
        st   t0, [s0+SCORE]
        call draw_board
        call draw_stats
as_done:
        pop  lr
        ret

; ---------------------------------------------------------------- drawing

draw_board:                             ; the whole field again
        push lr
        li   t4, 0
        li   a0, X0
        li   a1, Y0
        li   a2, 40
        li   a3, 80
        call rect
        li   s1, 0
db_loop:
        li   t0, BOARD
        add  t0, t0, s1
        ldbu a2, [t0]
        beqz a2, db_next
        li   t1, 10
        modu a0, s1, t1
        divu a1, s1, t1
        call cell
db_next:
        addi s1, s1, 1
        li   t0, 200
        bne  s1, t0, db_loop
        pop  lr
        ret

draw_stats:
        push lr
        li   a0, 4
        li   a1, 8
        ld   a2, [s0+SCORE]
        li   a3, WHITE
        call number
        li   a0, 4
        li   a1, 26
        ld   a2, [s0+LINES]
        li   a3, GREEN
        call number
        li   a0, 4
        li   a1, 44
        ld   a2, [s0+LEVEL]
        li   a3, YELLOW
        call number
        pop  lr
        ret

; number(a0 = x, a1 = y, a2 = value, a3 = color): 5 digits with leading zeros
number: addi sp, sp, -16
        st   lr, [sp+12]
        st   a0, [sp+0]
        st   a1, [sp+4]
        st   a3, [sp+8]
        mov  s1, a2
        li   t4, 0                      ; clear the old number
        li   a2, 34
        li   a3, 10
        call rect
        li   s2, 4                      ; digit positions, from the right
nm_loop:
        li   t0, 10
        modu a2, s1, t0
        divu s1, s1, t0
        li   t0, 7
        mul  t0, t0, s2
        ld   a0, [sp+0]
        add  a0, a0, t0
        ld   a1, [sp+4]
        ld   a3, [sp+8]
        call digit
        addi s2, s2, -1
        bge  s2, r0, nm_loop
        ld   lr, [sp+12]
        addi sp, sp, 16
        ret

; digit(a0 = x, a1 = y, a2 = 0-9, a3 = color): a 3 x 5 digit, every dot is 2 x 2 pixels
digit:  shli t0, a1, 7
        add  t0, t0, a0
        li   t1, FB
        add  t0, t0, t1                 ; screen address of the top left corner
        la   t1, font
        li   t2, 5
        mul  t2, t2, a2
        add  t1, t1, t2                 ; the 5 rows of this digit
        li   a1, 5
dg_row: ldbu t2, [t1]
        li   t3, 4                      ; bit of the leftmost dot
        mov  t4, t0
dg_col: and  a0, t2, t3
        beqz a0, dg_skip
        stb  a3, [t4]
        stb  a3, [t4+1]
        stb  a3, [t4+128]
        stb  a3, [t4+129]
dg_skip:
        addi t4, t4, 2
        shri t3, t3, 1
        bnez t3, dg_col
        addi t1, t1, 1
        addi t0, t0, 256
        addi a1, a1, -1
        bnez a1, dg_row
        ret

; rect(a0 = x, a1 = y, a2 = width, a3 = height, t4 = color)
rect:   shli t0, a1, 7
        add  t0, t0, a0
        li   t1, FB
        add  t0, t0, t1                 ; address of the top left pixel
rc_row: mov  t1, t0
        mov  t2, a2
rc_px:  stb  t4, [t1]
        addi t1, t1, 1
        addi t2, t2, -1
        bnez t2, rc_px
        addi t0, t0, 128
        addi a3, a3, -1
        bnez a3, rc_row
        ret
