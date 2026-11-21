; Mandelbrot zoom. The program dives into the Mandelbrot set with 24 zoom-ins: it calculates a
; picture, zooms in smoothly by a factor of 1.59 (the picture is stretched while the next one
; is prepared), calculates the next one with that much more detail, and so on. At the end the
; view is 65 000 times closer than the whole set. Every picture is shown row by row as soon as
; it is finished. Then the next dive starts at another place (seahorse valley, a spiral, the
; tendrils at the top, a swirl). Any key skips to the next place, q quits.
;
; To be fast, the picture is calculated for 64 x 48 points and every point is drawn as a block
; of 2 x 2 pixels. The numbers are fixed point with 28 fractional bits (Q4.28): 1.0 = 0x10000000,
; so they cover -8 ... +8. A product x * y in this format is (x * y) >> 28, and mulh gives
; (x * y) >> 32, so mulh followed by a shift left by 4 is almost the same (it loses the 4 lowest
; bits, which is far below what the screen can show). A point is outside the set once
; x*x + y*y reaches 4. The number of iterations until that happens picks the color from the
; palette; points that survive all iterations are in the set (black). Deeper pictures need more
; iterations to show their detail (48 + 7 per level). The iteration count of every point is kept
; in RAM, so the zoom between two pictures only copies points around and calculates nothing.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24
        .equ RANDOM,     0x14
        .equ CELLS,      64 * 48
        .equ ITBUF,      0x1000         ; iteration count of every point (255 = in the set)
        .equ COLTAB,     0x2000         ; zoom: source column of every column of points
        .equ LEVELS,     25             ; pictures per dive: 24 zoom-ins by a factor of 1.59 each
        .equ TARGETS,    4
        .equ STEPS,      32             ; smooth zoom frames per octave
        .equ HOLD,       150            ; frames to look at the last picture

        .data
zoom_inv: ; 256 / 1.59^(k/32) for k = 1 ... 32: source points per screen point, 8.8
        .word 252, 249, 245, 242, 238, 235, 231, 228
        .word 225, 222, 218, 215, 212, 209, 206, 203
        .word 200, 197, 195, 192, 189, 186, 184, 181
        .word 178, 176, 173, 171, 168, 166, 164, 161
targets: ; the points we dive into: x, y
        .word 0xF407975A, 0x022EE5E3  ; seahorse valley
        .word 0xF380FFA7, 0x0241AF7C  ; a spiral
        .word 0xFE7872EE, 0x0F57B6BE  ; tendrils at the top
        .word 0x05C837A7, 0xF5BC73B9  ; a swirl
steps:  ; distance between two points in the pictures 0 ... 24: 3.5 / 64 / 2^(2 level / 3)
        .word 14680064, 9247861, 5825787, 3670016, 2311965, 1456447
        .word 917504, 577991, 364112, 229376, 144498, 91028
        .word 57344, 36124, 22757, 14336, 9031, 5689
        .word 3584, 2258, 1422, 896, 564, 356
        .word 224
pal:    ; color of an iteration count 0 ... 255 (255 = in the set: black); a slow blue / gold loop
        .byte 0x00, 0x00, 0x01, 0x01, 0x01, 0x05, 0x05, 0x06
        .byte 0x06, 0x06, 0x06, 0x0A, 0x0A, 0x2A, 0x2E, 0x2F
        .byte 0x4F, 0x53, 0x53, 0x57, 0x77, 0x77, 0x7B, 0x9B
        .byte 0x9B, 0x9B, 0xBB, 0xBB, 0xDF, 0xDF, 0xDF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFA, 0xFA, 0xFA, 0xF9
        .byte 0xF9, 0xF5, 0xF5, 0xF4, 0xD4, 0xD0, 0xD0, 0xAC
        .byte 0xAC, 0x8C, 0x88, 0x68, 0x64, 0x44, 0x44, 0x44
        .byte 0x44, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00
        .byte 0x00, 0x00, 0x01, 0x01, 0x01, 0x05, 0x05, 0x06
        .byte 0x06, 0x06, 0x06, 0x0A, 0x0A, 0x2A, 0x2E, 0x2F
        .byte 0x4F, 0x53, 0x53, 0x57, 0x77, 0x77, 0x7B, 0x9B
        .byte 0x9B, 0x9B, 0xBB, 0xBB, 0xDF, 0xDF, 0xDF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFA, 0xFA, 0xFA, 0xF9
        .byte 0xF9, 0xF5, 0xF5, 0xF4, 0xD4, 0xD0, 0xD0, 0xAC
        .byte 0xAC, 0x8C, 0x88, 0x68, 0x64, 0x44, 0x44, 0x44
        .byte 0x44, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00
        .byte 0x00, 0x00, 0x01, 0x01, 0x01, 0x05, 0x05, 0x06
        .byte 0x06, 0x06, 0x06, 0x0A, 0x0A, 0x2A, 0x2E, 0x2F
        .byte 0x4F, 0x53, 0x53, 0x57, 0x77, 0x77, 0x7B, 0x9B
        .byte 0x9B, 0x9B, 0xBB, 0xBB, 0xDF, 0xDF, 0xDF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFA, 0xFA, 0xFA, 0xF9
        .byte 0xF9, 0xF5, 0xF5, 0xF4, 0xD4, 0xD0, 0xD0, 0xAC
        .byte 0xAC, 0x8C, 0x88, 0x68, 0x64, 0x44, 0x44, 0x44
        .byte 0x44, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00
        .byte 0x00, 0x00, 0x01, 0x01, 0x01, 0x05, 0x05, 0x06
        .byte 0x06, 0x06, 0x06, 0x0A, 0x0A, 0x2A, 0x2E, 0x2F
        .byte 0x4F, 0x53, 0x53, 0x57, 0x77, 0x77, 0x7B, 0x9B
        .byte 0x9B, 0x9B, 0xBB, 0xBB, 0xDF, 0xDF, 0xDF, 0xFF
        .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFA, 0xFA, 0xFA, 0xF9
        .byte 0xF9, 0xF5, 0xF5, 0xF4, 0xD4, 0xD0, 0xD0, 0xAC
        .byte 0xAC, 0x8C, 0x88, 0x68, 0x64, 0x44, 0x44, 0x44
        .byte 0x44, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00

        .text
start:  li   sp, 0x00040000
        addi sp, sp, -16                ; [sp+0] x of the first column, [sp+4] level,
                                        ; [sp+8] iteration limit, [sp+12] target
        li   t0, IO                     ; start at a random target
        ld   t0, [t0+RANDOM]
        shri t0, t0, 8
        li   t1, TARGETS
        modu t0, t0, t1
        st   t0, [sp+12]
        j    begin

restart:                                ; the next target
        ld   t0, [sp+12]
        addi t0, t0, 1
        li   t1, TARGETS
        modu t0, t0, t1
        st   t0, [sp+12]
begin:  st   r0, [sp+4]

level:  ld   t0, [sp+4]
        shli t1, t0, 2                  ; distance between two points: from the table
        la   t2, steps
        add  t2, t2, t1
        ld   s2, [t2]
        ld   t1, [sp+12]                ; the target
        shli t1, t1, 3
        la   t2, targets
        add  t2, t2, t1
        shli t1, s2, 5                  ; x of the first column: target x - 32 points
        ld   s0, [t2+0]
        sub  s0, s0, t1
        li   t1, 24
        mul  t1, s2, t1                 ; y of the first row: target y - 24 points
        ld   s1, [t2+4]
        sub  s1, s1, t1
        li   t1, 7
        mul  t1, t0, t1
        addi t1, t1, 48
        st   t1, [sp+8]                 ; iteration limit
        st   s0, [sp+0]
        li   s3, 0                      ; pixel number

pixel:  mov  a0, s0
        mov  a1, s1
        call iterate                    ; a0 = iterations, 255 = in the set
        li   t0, ITBUF
        add  t0, t0, s3
        stb  a0, [t0]
        la   t1, pal
        add  t1, t1, a0
        ldbu t2, [t1]
        shli t3, t2, 8                  ; a block of 2 x 2 pixels
        or   t3, t3, t2
        shri t1, s3, 6
        shli t1, t1, 8
        andi t0, s3, 63
        shli t0, t0, 1
        add  t1, t1, t0
        li   t0, FB
        add  t1, t1, t0
        sth  t3, [t1]
        sth  t3, [t1+128]
        add  s0, s0, s2                 ; next column
        addi s3, s3, 1
        andi t0, s3, 63
        bnez t0, pixel

        li   t0, IO                     ; row finished: show it
        st   r0, [t0+FB_SHOW]
        call check_keys
        bnez a0, restart
        ld   s0, [sp+0]                 ; back to the first column, one row down
        add  s1, s1, s2
        li   t0, CELLS
        bne  s3, t0, pixel

        ld   t0, [sp+4]                 ; picture finished
        addi t0, t0, 1
        li   t1, LEVELS
        beq  t0, t1, finished

        li   s3, 0                      ; zoom in by a factor of two, 16 frames
zoom:   la   t0, zoom_inv
        shli t1, s3, 2
        add  t0, t0, t1
        ld   a0, [t0]
        call zoom_frame
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        ld   t1, [t0+VSYNC]
zwait:  ld   t2, [t0+VSYNC]
        beq  t2, t1, zwait
        call check_keys
        bnez a0, restart
        addi s3, s3, 1
        li   t0, STEPS
        bne  s3, t0, zoom
        ld   t0, [sp+4]                 ; next picture, twice the detail
        addi t0, t0, 1
        st   t0, [sp+4]
        j    level

finished:
        li   s3, HOLD
fin:    li   t0, IO
        ld   t1, [t0+VSYNC]
fwait:  ld   t2, [t0+VSYNC]
        beq  t2, t1, fwait
        call check_keys
        bnez a0, restart
        addi s3, s3, -1
        bnez s3, fin
        j    restart

; check_keys: a0 = 1 if a key other than q was pressed, q ends the program
check_keys:
        li   t0, IO
        ld   t1, [t0+KEY_STATUS]
        beqz t1, ck_none
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        beq  t1, t2, ck_quit
        li   a0, 1
        ret
ck_none:
        li   a0, 0
        ret
ck_quit:
        halt

; zoom_frame(a0 = source points per screen point in 8.8): draws the last picture stretched
; around the screen center, picking the color of the nearest point. Clobbers s0-s2.
zoom_frame:
        li   t0, 0                      ; source column of every column of points
        li   t1, COLTAB
zc:     addi t2, t0, -32
        mul  t2, t2, a0
        srai t2, t2, 8
        addi t2, t2, 32
        add  t3, t1, t0
        stb  t2, [t3]
        addi t0, t0, 1
        li   t3, 64
        bne  t0, t3, zc
        li   s0, 0                      ; row of points
        li   s1, FB
        la   s2, pal
zr:     addi t0, s0, -24                ; source row
        mul  t0, t0, a0
        srai t0, t0, 8
        addi t0, t0, 24
        shli t0, t0, 6
        li   t1, ITBUF
        add  t0, t0, t1
        li   t1, COLTAB
        li   t2, 64
zp:     ldbu t3, [t1]
        add  t3, t3, t0
        ldbu t3, [t3]                   ; iterations of the source point
        add  t3, t3, s2
        ldbu t3, [t3]
        shli t4, t3, 8
        or   t3, t3, t4
        sth  t3, [s1]
        sth  t3, [s1+128]
        addi t1, t1, 1
        addi s1, s1, 2
        addi t2, t2, -1
        bnez t2, zp
        addi s1, s1, 128                ; the second pixel row of this row of points is done
        addi s0, s0, 1
        li   t3, 48
        bne  s0, t3, zr
        ret

; iterate(a0 = x, a1 = y) -> a0 = number of iterations until the point escapes, or 255
; z = 0, then z = z*z + (x, y), over and over. Uses only a0-a3 and t0-t4; the iteration
; limit of the level is read from [sp+8].
iterate:
        li   t0, 0                      ; zx
        li   t1, 0                      ; zy
        ld   t2, [sp+8]                 ; iterations left (the limit of this level)
        li   a3, 0x40000000             ; 4.0
it_loop:
        mulh t3, t0, t0                 ; xx = zx * zx
        shli t3, t3, 4
        mulh t4, t1, t1                 ; yy = zy * zy
        shli t4, t4, 4
        add  a2, t3, t4                 ; escaped once xx + yy >= 4
        bgeu a2, a3, escaped
        mulh a2, t0, t1                 ; 2 * zx * zy
        shli a2, a2, 5
        add  t1, a2, a1                 ; new zy = 2 * zx * zy + y
        sub  t0, t3, t4                 ; new zx = xx - yy + x
        add  t0, t0, a0
        addi t2, t2, -1
        bnez t2, it_loop
        li   a0, 255                    ; never escaped: in the set
        ret
escaped:
        ld   a0, [sp+8]
        sub  a0, a0, t2                 ; iterations done
        ret
