; Paint with the mouse or a finger: hold the button (or touch) and drag to draw.
; The strip at the top picks the color, the white square on its right clears the
; screen. The keys c (clear) and q (quit) work too.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24
        .equ POINTER_X,  0x2C
        .equ POINTER_Y,  0x30
        .equ POINTER_BTN,0x34           ; bit 0: button or finger is down
        .equ W,          128
        .equ H,          96
        .equ BAR,        10             ; the color strip is the top 10 rows
        .equ CELL,       16             ; 8 cells of 16 pixels: 7 colors and "clear"
        .equ NCOLORS,    7
        .equ WHITE,      0xFF

        .data
colors: .byte 0xE0, 0xF4, 0xFC, 0x1C, 0x1F, 0x03, 0xE3     ; red orange yellow green cyan blue magenta

        .text
start:  li   sp, 0x00040000
        li   s3, IO
        li   s2, 3                      ; number of the color: green
        call wipe
        ld   s1, [s3+VSYNC]

frame:  ld   t0, [s3+KEY_STATUS]        ; keys: c clears, q quits
        beqz t0, tick
        ld   t0, [s3+KEY_DATA]
        li   t1, 'q'
        beq  t0, t1, quit
        li   t1, 'c'
        bne  t0, t1, tick
        call wipe
tick:   ld   t0, [s3+VSYNC]             ; one step per screen refresh
        beq  t0, s1, frame
        mov  s1, t0
        ld   t0, [s3+POINTER_BTN]
        andi t0, t0, 1
        beqz t0, frame                  ; nothing is touching the screen
        ld   a0, [s3+POINTER_X]
        ld   a1, [s3+POINTER_Y]
        li   t1, BAR
        blt  a1, t1, pick
        li   t1, W - 2                  ; the pen is 2 x 2 pixels, keep it on the screen
        ble  a0, t1, x_ok
        mov  a0, t1
x_ok:   li   t1, H - 2
        ble  a1, t1, y_ok
        mov  a1, t1
y_ok:   la   t1, colors
        add  t1, t1, s2
        ldbu a2, [t1]
        li   a3, 2
        call fill_wh
        st   r0, [s3+FB_SHOW]
        j    frame

pick:   shri t0, a0, 4                  ; which cell of the strip
        li   t1, NCOLORS
        bne  t0, t1, chosen
        call wipe                       ; the last cell clears the screen
        j    frame
chosen: mov  s2, t0
        call bar
        st   r0, [s3+FB_SHOW]
        j    frame
quit:   halt

wipe:   push lr                         ; black screen, then the color strip
        li   t1, FB
        li   t2, FB + W * H
wipe_loop:
        st   r0, [t1]
        addi t1, t1, 4
        bne  t1, t2, wipe_loop
        call bar
        st   r0, [s3+FB_SHOW]
        pop  lr
        ret

bar:    push lr                         ; the 7 colors, the white clear cell, and a white line
        push s0                         ; under the color that is selected
        li   s0, 0
bar_loop:
        shli a0, s0, 4
        li   a1, 0
        li   t1, NCOLORS
        li   a2, WHITE
        beq  s0, t1, bar_cell
        la   t1, colors
        add  t1, t1, s0
        ldbu a2, [t1]
bar_cell:
        call fill_cell
        addi s0, s0, 1
        li   t1, NCOLORS + 1
        bne  s0, t1, bar_loop
        shli a0, s2, 4                  ; the marker: 16 x 1 pixels in row 8
        li   a1, BAR - 2
        li   a2, WHITE
        li   a3, CELL
        call fill_row
        pop  s0
        pop  lr
        ret

fill_cell:                              ; a 14 x 8 cell at (a0, a1), color a2
        push lr
        li   a3, 14
        li   t3, 8
        call fill
        pop  lr
        ret

fill_row:                               ; a1 high, width a3, one row
        push lr
        li   t3, 1
        call fill
        pop  lr
        ret

fill_wh:                                ; a 2 x 2 square at (a0, a1)
        push lr
        li   t3, 2
        call fill
        pop  lr
        ret

fill:                                   ; fill(a0 = x, a1 = y, a2 = color, a3 = width, t3 = height)
        shli t1, a1, 7
        add  t1, t1, a0
        li   t2, FB
        add  t1, t1, t2
fill_y: li   t0, 0
fill_x: add  t2, t1, t0
        stb  a2, [t2]
        addi t0, t0, 1
        bne  t0, a3, fill_x
        addi t1, t1, W
        addi t3, t3, -1
        bnez t3, fill_y
        ret
