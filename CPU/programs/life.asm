; Conway's Game of Life on the pixel screen. The world is 64 x 48 cells (every cell is 2 x 2
; pixels) and wraps around at the edges, so a glider that leaves on the right comes back on
; the left. It starts with random cells (the RANDOM register, one cell in three is alive).
; Newborn cells are white, cells that stay alive are green. When the world stops changing
; (or after 900 generations) a new random world is started. Any key starts a new world right
; away, q quits.
;
; Rules: a living cell with 2 or 3 living neighbors survives, a dead cell with exactly 3
; living neighbors is born, everything else is dead in the next generation.
;
; Every grid is a byte per cell (0 or 1) in RAM with a border of one cell around it, 66 x 50
; bytes. After every generation the border is filled with a copy of the opposite edge, which
; makes the wrap-around work without any special cases when the neighbors are counted. Two
; grids take turns: one is read, the other one is written, and then they swap.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ RANDOM,     0x14
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24
        .equ GRID_A,     0x1000
        .equ GRID_B,     0x2000
        .equ STRIDE,     66             ; bytes per row of a grid (64 cells + 2 border cells)
        .equ MAX_GEN,    900
        .equ BORN,       0xFF           ; white
        .equ ALIVE,      0x1C           ; green

        .text
start:  li   sp, 0x00040000
        addi sp, sp, -4                 ; [sp] = generations of this world so far
        li   s0, GRID_A                 ; the grid that is shown now
        li   s1, GRID_B                 ; the grid that is calculated
        call new_world

loop:   mov  a0, s0
        mov  a1, s1
        call step                       ; a0 = number of cells that changed
        mov  s3, a0
        mov  a0, s1
        call wrap
        mov  t0, s0                     ; the new grid is the current one now
        mov  s0, s1
        mov  s1, t0

        li   t0, IO
        st   r0, [t0+FB_SHOW]
        ld   t1, [t0+VSYNC]
wait:   ld   t2, [t0+VSYNC]
        beq  t2, t1, wait

        ld   t1, [t0+KEY_STATUS]        ; a key: q quits, anything else starts a new world
        beqz t1, no_key
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        beq  t1, t2, quit
        call new_world
        j    loop
no_key:
        ld   t1, [sp]                   ; generation counter
        addi t1, t1, 1
        st   t1, [sp]
        li   t2, MAX_GEN
        bge  t1, t2, again
        li   t2, 3                      ; fewer than 3 cells changed: nothing is moving anymore
        bge  s3, t2, moving
        addi s2, s2, 1
        li   t2, 30                     ; ... for 30 generations in a row
        blt  s2, t2, loop
again:  call new_world
        j    loop
moving: li   s2, 0
        j    loop
quit:   halt

new_world:                              ; random cells into the current grid s0, drawn on the screen
        push lr
        mov  a0, s0
        call seed
        mov  a0, s0
        call wrap
        st   r0, [sp+4]                 ; generation counter (the push moved sp by 4)
        li   s2, 0
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        pop  lr
        ret

; seed(a0 = grid): clears the screen, fills the grid with random cells and draws the living ones
seed:   li   t0, FB
        li   t1, FB + 128 * 96
clear:  st   r0, [t0]
        addi t0, t0, 4
        bne  t0, t1, clear
        addi t0, a0, STRIDE + 1         ; first cell of the grid
        li   t1, FB
        li   a3, 48                     ; rows
        li   a1, IO
s_row:  li   t2, 64                     ; cells in this row
s_cell: ld   t3, [a1+RANDOM]
        shri t3, t3, 8                  ; the lowest bits of the random number are not as good
        li   t4, 3
        modu t3, t3, t4
        li   t4, 0                      ; dead
        bnez t3, s_set
        li   t4, 1                      ; one cell in three lives
        li   a2, ALIVE
        stb  a2, [t1]
        stb  a2, [t1+1]
        stb  a2, [t1+128]
        stb  a2, [t1+129]
s_set:  stb  t4, [t0]
        addi t0, t0, 1
        addi t1, t1, 2
        addi t2, t2, -1
        bnez t2, s_cell
        addi t0, t0, 2                  ; skip the border cells at the end and start of a row
        addi t1, t1, 128                ; the next row of cells is 2 pixel rows further down
        addi a3, a3, -1
        bnez a3, s_row
        ret

; wrap(a0 = grid): copies the edges of the grid into the border on the opposite side
wrap:   addi t0, a0, STRIDE + 1         ; row 1 -> row 49 (below the grid)
        addi t1, a0, 49 * STRIDE + 1
        li   t2, 64
w_down: ldbu t3, [t0]
        stb  t3, [t1]
        addi t0, t0, 1
        addi t1, t1, 1
        addi t2, t2, -1
        bnez t2, w_down
        addi t0, a0, 48 * STRIDE + 1    ; row 48 -> row 0 (above the grid)
        addi t1, a0, 1
        li   t2, 64
w_up:   ldbu t3, [t0]
        stb  t3, [t1]
        addi t0, t0, 1
        addi t1, t1, 1
        addi t2, t2, -1
        bnez t2, w_up
        mov  t0, a0                     ; left and right, for all 50 rows (this also does the corners)
        li   t2, 50
w_side: ldbu t3, [t0+64]                ; last column -> border on the left
        stb  t3, [t0]
        ldbu t3, [t0+1]                 ; first column -> border on the right
        stb  t3, [t0+65]
        addi t0, t0, STRIDE
        addi t2, t2, -1
        bnez t2, w_side
        ret

; step(a0 = current grid, a1 = grid to write) -> a0 = number of cells that changed
; Writes the next generation and only draws the cells that changed (and the survivors, which
; turn from white to green).
step:   sub  a1, a1, a0                 ; distance between the two grids
        addi t0, a0, STRIDE + 1         ; current cell
        li   t1, FB                     ; its pixels on the screen
        li   a2, 0                      ; changes
        li   a3, 48                     ; rows left
st_row: li   t2, 64                     ; cells left in this row
st_cell:
        ldbu t3, [t0-STRIDE-1]          ; number of living neighbors in t3
        ldbu t4, [t0-STRIDE]
        add  t3, t3, t4
        ldbu t4, [t0-STRIDE+1]
        add  t3, t3, t4
        ldbu t4, [t0-1]
        add  t3, t3, t4
        ldbu t4, [t0+1]
        add  t3, t3, t4
        ldbu t4, [t0+STRIDE-1]
        add  t3, t3, t4
        ldbu t4, [t0+STRIDE]
        add  t3, t3, t4
        ldbu t4, [t0+STRIDE+1]
        add  t3, t3, t4
        ldbu t4, [t0]                   ; t4 = the cell now, a0 = the cell in the next generation
        li   a0, 0
        addi t3, t3, -3
        beqz t3, st_live                ; 3 neighbors: alive in any case
        addi t3, t3, 1
        bnez t3, st_new                 ; not 2 neighbors either: dead
        mov  a0, t4                     ; 2 neighbors: stays as it is
        j    st_new
st_live:
        li   a0, 1
st_new: add  t3, t0, a1
        stb  a0, [t3]
        beq  a0, t4, st_same
        addi a2, a2, 1
        beqz a0, st_died
        li   t3, BORN
        j    st_paint
st_died:
        li   t3, 0
        j    st_paint
st_same:
        beqz a0, st_next                ; dead and stays dead: nothing to draw
        li   t3, ALIVE
st_paint:
        stb  t3, [t1]                   ; the cell is a block of 2 x 2 pixels
        stb  t3, [t1+1]
        stb  t3, [t1+128]
        stb  t3, [t1+129]
st_next:
        addi t0, t0, 1
        addi t1, t1, 2
        addi t2, t2, -1
        bnez t2, st_cell
        addi t0, t0, 2                  ; skip the border
        addi t1, t1, 128                ; 2 pixel rows further down
        addi a3, a3, -1
        bnez a3, st_row
        mov  a0, a2
        ret
