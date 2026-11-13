; Pixel screen demo: a color gradient, all 256 colors in a strip at the bottom and a
; square bouncing around. The background is drawn once; every frame only paints the
; background over the old square, draws the new one, shows the frame and waits for the
; next screen refresh (VSYNC), so it moves at 60 frames per second.

        .equ FB,          0xFFFD0000    ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,          0xFFFF0000
        .equ FB_SHOW,     0x20
        .equ VSYNC,       0x24          ; counts screen refreshes, 60 per second
        .equ W,           128
        .equ H,           96
        .equ STRIP,       H - 8         ; first row of the color strip
        .equ SIZE,        10            ; the square is SIZE x SIZE pixels
        .equ BALL,        0xFC          ; yellow: red 7, green 7, blue 0
        .equ FRAMES,      300           ; 5 seconds

        .text
start:  li   sp, 0x00040000

        ; background: every row gets one color, 4 pixels per store
        li   s1, 0                      ; y
bg_row: mov  a0, s1
        call bg_color
        li   t0, 0x01010101
        mul  a0, a0, t0                 ; the same color in all 4 bytes
        shli t0, s1, 7                  ; y * 128
        li   t1, FB
        add  t0, t0, t1                 ; first pixel of the row
        addi t1, t0, W                  ; first pixel of the next row
bg_px:  st   a0, [t0]
        addi t0, t0, 4
        bne  t0, t1, bg_px
        addi s1, s1, 1
        li   t0, STRIP
        bne  s1, t0, bg_row

        ; color strip: pixel x shows color x (upper 4 rows) or 128 + x (lower 4 rows)
strip_row:
        addi t0, s1, -STRIP
        shri t0, t0, 2
        shli t0, t0, 7                  ; first color of the row, 0 or 128
        li   t1, 0x01010101
        mul  t2, t0, t1
        li   t1, 0x03020100
        add  t2, t2, t1                 ; colors of the first 4 pixels
        li   t3, 0x04040404             ; the next 4 pixels are 4 colors further
        shli t0, s1, 7
        li   t1, FB
        add  t0, t0, t1
        addi t1, t0, W
strip_px:
        st   t2, [t0]
        add  t2, t2, t3
        addi t0, t0, 4
        bne  t0, t1, strip_px
        addi s1, s1, 1
        li   t0, H
        bne  s1, t0, strip_row

        li   s0, 20                     ; x
        li   s1, 10                     ; y
        li   s2, 2                      ; dx
        li   s3, 1                      ; dy
        li   t0, FRAMES
        push t0                         ; frames left (no saved register left for it)
frame:
        mov  a0, s0                     ; paint the background over the old square
        mov  a1, s1
        li   a2, -1
        call square

        add  s0, s0, s2                 ; move, bounce at the edges
        ble  s0, r0, flip_x
        li   t0, W - SIZE
        blt  s0, t0, x_ok
flip_x: neg  s2, s2
x_ok:   add  s1, s1, s3
        ble  s1, r0, flip_y
        li   t0, STRIP - SIZE
        blt  s1, t0, y_ok
flip_y: neg  s3, s3
y_ok:
        mov  a0, s0                     ; draw the square
        mov  a1, s1
        li   a2, BALL
        call square

        li   t0, IO
        st   r0, [t0+FB_SHOW]           ; show the frame
        ld   t1, [t0+VSYNC]             ; wait for the next screen refresh
wait:   ld   t2, [t0+VSYNC]
        beq  t2, t1, wait

        ld   t0, [sp]
        addi t0, t0, -1
        st   t0, [sp]
        bnez t0, frame
        halt

square:                                 ; square(a0 = x, a1 = y, a2 = color), color -1 = background
        push lr
        mov  a3, a0                     ; x
        addi t4, a1, SIZE               ; the row below the square
sq_row: mov  a0, a2                     ; color of this row
        bge  a2, r0, sq_draw
        mov  a0, a1
        call bg_color                   ; erasing: background color of row a1
sq_draw:
        shli t2, a1, 7                  ; y * 128
        add  t2, t2, a3                 ; + x
        li   t3, FB
        add  t2, t2, t3                 ; address of the first pixel
        addi t3, t2, SIZE
sq_px:  stb  a0, [t2]
        addi t2, t2, 1
        bne  t2, t3, sq_px
        addi a1, a1, 1
        bne  a1, t4, sq_row
        pop  lr
        ret

bg_color:                               ; a0 = background color of row a0 (only changes t0, t1)
        shri t0, a0, 5                  ; 0 at the top ... 2 at the bottom
        shri t1, a0, 4
        shli t1, t1, 5                  ; red: more towards the bottom
        ori  t1, t1, 1 << 2             ; green: 1
        li   a0, 3
        sub  a0, a0, t0                 ; blue: less towards the bottom
        or   a0, a0, t1
        ret
