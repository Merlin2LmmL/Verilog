; A wireframe cube that spins in 3D and bounces around the pixel screen. Edges that are
; closer to you are brighter, far ones fade into blue. q quits.
;
; The 8 corners are (+-S, +-S, +-S). Every frame they are turned around the x, y and z axes by
; the angles ax, ay and az, which grow a little every frame (256 units = one full turn).
; Sine and cosine come from a table of 256 signed 16-bit values (ldh reads one entry),
; scaled by 2^14, so every product is shifted right by 14 bits (srai) afterwards. Then the
; perspective: the further away a corner is (larger z), the closer it moves to the middle,
; screen = center + x * D / (z + ZOFF). The 12 edges between the corners are drawn with
; Bresenham's line algorithm. All of that takes about 25000 cycles, so it fits into one
; screen refresh (41666 cycles) and the cube runs at 60 frames per second.
;
; s0 points to the state block. s1-s3 are only local variables of one function each.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24

        .equ AX,         0              ; state block: the three angles,
        .equ AY,         4
        .equ AZ,         8
        .equ CX,         12             ; the middle of the cube on the screen, and its speed
        .equ CY,         16
        .equ VX,         20
        .equ VY,         24
        .equ SINX,       28             ; sine and cosine of the three angles, calculated every frame
        .equ COSX,       32
        .equ SINY,       36
        .equ COSY,       40
        .equ SINZ,       44
        .equ COSZ,       48

        .equ CORNERS,    0x2000         ; 8 corners x (screen x, screen y, depth) = 12 bytes each
        .equ SIZE,       16             ; half the edge length
        .equ ZOFF,       90             ; distance of the cube's middle from the eye
        .equ DIST,       60             ; strength of the perspective
        .equ SINTAB,     0x3000         ; 256 sine values (16 bits), built at the start
        .equ SIN1,       0x00648558     ; sin of one step (1/256 turn), 28 fractional bits
        .equ COS2,       0x1FFD8861     ; 2 * cos of one step

        .data
edges:  .byte 0, 1, 2, 3, 4, 5, 6, 7    ; the 12 edges as pairs of corners (corner bits: x, y, z)
        .byte 0, 2, 1, 3, 4, 6, 5, 7
        .byte 0, 4, 1, 5, 2, 6, 3, 7
shades: .byte 0xFF, 0xDF, 0x9F, 0x5F, 0x3F, 0x1F, 0x17, 0x0F   ; near ... far
state:  .space 52

        .text
start:  li   sp, 0x00040000
        la   s0, state
        call build_sin
        li   t0, 64                     ; start in the middle, moving diagonally
        st   t0, [s0+CX]
        li   t0, 48
        st   t0, [s0+CY]
        li   t0, 1
        st   t0, [s0+VX]
        st   t0, [s0+VY]

frame:  call clear
        call trig
        call corners
        call draw_edges
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        ld   t1, [t0+VSYNC]
wait:   ld   t2, [t0+VSYNC]
        beq  t2, t1, wait
        call update
        li   t0, IO
        ld   t1, [t0+KEY_STATUS]
        beqz t1, frame
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        bne  t1, t2, frame
        halt

clear:  li   t0, FB
        li   t1, FB + 128 * 96
cl_loop:
        st   r0, [t0]
        addi t0, t0, 4
        bne  t0, t1, cl_loop
        ret

update:                                 ; turn a little and move; bounce at the edges
        ld   t0, [s0+AX]
        addi t0, t0, 1
        andi t0, t0, 255
        st   t0, [s0+AX]
        ld   t0, [s0+AY]
        addi t0, t0, 2
        andi t0, t0, 255
        st   t0, [s0+AY]
        ld   t0, [s0+AZ]
        addi t0, t0, 1
        andi t0, t0, 255
        st   t0, [s0+AZ]
        ld   t0, [s0+CX]                ; the cube is about 56 pixels wide, 30 ... 98 keeps it inside
        ld   t1, [s0+VX]
        add  t0, t0, t1
        st   t0, [s0+CX]
        li   t2, 30
        blt  t0, t2, up_flip_x
        li   t2, 98
        ble  t0, t2, up_x_ok
up_flip_x:
        sub  t1, r0, t1
        st   t1, [s0+VX]
up_x_ok:
        ld   t0, [s0+CY]
        ld   t1, [s0+VY]
        add  t0, t0, t1
        st   t0, [s0+CY]
        li   t2, 30
        blt  t0, t2, up_flip_y
        li   t2, 66
        ble  t0, t2, up_y_ok
up_flip_y:
        sub  t1, r0, t1
        st   t1, [s0+VY]
up_y_ok:
        ret

build_sin:                              ; sin(n / 256 turn) * 16384, calculated instead of typed in:
        li   t0, SINTAB                 ; every value is 2 * cos * the last one - the one before
        li   t1, 0                      ; (28 fractional bits inside, so the error stays below 2)
        li   t2, SIN1
        li   t4, COS2
        li   a0, 256
bs_loop:
        srai t3, t1, 14
        sth  t3, [t0]
        addi t0, t0, 2
        mulh t3, t2, t4                 ; (cos2 * s) >> 28
        mul  a1, t2, t4
        shli t3, t3, 4
        shri a1, a1, 28
        or   t3, t3, a1
        sub  t3, t3, t1
        mov  t1, t2
        mov  t2, t3
        addi a0, a0, -1
        bnez a0, bs_loop
        ret

sin:    andi a0, a0, 255                ; sin(a0 = angle) -> a0 = sine * 16384
        shli a0, a0, 1
        li   t0, SINTAB
        add  a0, a0, t0
        ldh  a0, [a0]
        ret

trig:   push lr                         ; sine and cosine of the three angles (cos x = sin (x + 90 degrees))
        ld   s1, [s0+AX]
        mov  a0, s1
        call sin
        st   a0, [s0+SINX]
        addi a0, s1, 64
        call sin
        st   a0, [s0+COSX]
        ld   s1, [s0+AY]
        mov  a0, s1
        call sin
        st   a0, [s0+SINY]
        addi a0, s1, 64
        call sin
        st   a0, [s0+COSY]
        ld   s1, [s0+AZ]
        mov  a0, s1
        call sin
        st   a0, [s0+SINZ]
        addi a0, s1, 64
        call sin
        st   a0, [s0+COSZ]
        pop  lr
        ret

; corners: turn the 8 corners, project them and store (screen x, screen y, depth) in CORNERS
corners:
        li   s1, 0                      ; corner number: bit 0 = x, bit 1 = y, bit 2 = z (0 = -SIZE, 1 = +SIZE)
co_loop:
        andi t0, s1, 1
        shli t0, t0, 1
        addi t0, t0, -1                 ; -1 or +1
        li   t1, SIZE
        mul  a0, t0, t1                 ; x
        shri t0, s1, 1
        andi t0, t0, 1
        shli t0, t0, 1
        addi t0, t0, -1
        mul  a1, t0, t1                 ; y
        shri t0, s1, 2
        andi t0, t0, 1
        shli t0, t0, 1
        addi t0, t0, -1
        mul  a2, t0, t1                 ; z

        ld   t0, [s0+COSX]              ; around the x axis: y' = y cos - z sin, z' = y sin + z cos
        ld   t1, [s0+SINX]
        mul  t2, a1, t0
        mul  t3, a2, t1
        sub  t2, t2, t3
        srai t2, t2, 14
        mul  t3, a1, t1
        mul  t4, a2, t0
        add  t3, t3, t4
        srai t3, t3, 14
        mov  a1, t2
        mov  a2, t3

        ld   t0, [s0+COSY]              ; around the y axis: x' = x cos + z sin, z' = z cos - x sin
        ld   t1, [s0+SINY]
        mul  t2, a0, t0
        mul  t3, a2, t1
        add  t2, t2, t3
        srai t2, t2, 14
        mul  t3, a2, t0
        mul  t4, a0, t1
        sub  t3, t3, t4
        srai t3, t3, 14
        mov  a0, t2
        mov  a2, t3

        ld   t0, [s0+COSZ]              ; around the z axis: x' = x cos - y sin, y' = x sin + y cos
        ld   t1, [s0+SINZ]
        mul  t2, a0, t0
        mul  t3, a1, t1
        sub  t2, t2, t3
        srai t2, t2, 14
        mul  t3, a0, t1
        mul  t4, a1, t0
        add  t3, t3, t4
        srai t3, t3, 14
        mov  a0, t2
        mov  a1, t3

        addi a2, a2, ZOFF               ; perspective: screen = center + x * DIST / depth
        li   t0, DIST
        mul  t1, a0, t0
        div  t1, t1, a2
        ld   t2, [s0+CX]
        add  t1, t1, t2
        mul  t3, a1, t0
        div  t3, t3, a2
        ld   t2, [s0+CY]
        add  t3, t3, t2

        li   t0, CORNERS
        li   t4, 12
        mul  t4, t4, s1
        add  t0, t0, t4
        st   t1, [t0+0]
        st   t3, [t0+4]
        st   a2, [t0+8]
        addi s1, s1, 1
        li   t0, 8
        bne  s1, t0, co_loop
        ret

draw_edges:
        addi sp, sp, -8
        st   lr, [sp+4]
        st   r0, [sp+0]                 ; edge number
de_loop:
        ld   t0, [sp+0]
        shli t0, t0, 1
        la   t1, edges
        add  t0, t0, t1
        ldbu t1, [t0+0]                 ; the two corners
        ldbu t2, [t0+1]
        li   t3, 12
        mul  t1, t1, t3
        mul  t2, t2, t3
        li   t3, CORNERS
        add  t1, t1, t3
        add  t2, t2, t3
        ld   a0, [t1+0]
        ld   a1, [t1+4]
        ld   a2, [t2+0]
        ld   a3, [t2+4]
        ld   t3, [t1+8]                 ; color from the average depth: 62 ... 118 -> 0 ... 7
        ld   t4, [t2+8]
        add  t3, t3, t4
        shri t3, t3, 1
        addi t3, t3, -60
        srai t3, t3, 3
        bge  t3, r0, de_lo
        li   t3, 0
de_lo:  li   t4, 7
        ble  t3, t4, de_hi
        li   t3, 7
de_hi:  la   t4, shades
        add  t3, t3, t4
        ldbu s2, [t3]
        call line
        ld   t0, [sp+0]
        addi t0, t0, 1
        st   t0, [sp+0]
        li   t1, 12
        bne  t0, t1, de_loop
        ld   lr, [sp+4]
        addi sp, sp, 8
        ret

; line(a0 = x0, a1 = y0, a2 = x1, a3 = y1, s2 = color): Bresenham, one pixel per step
line:   sub  t0, a2, a0                 ; t0 = dx = |x1 - x0|, t2 = step in x
        li   t2, 1
        bge  t0, r0, ln_dx
        sub  t0, r0, t0
        li   t2, -1
ln_dx:  sub  t1, a3, a1                 ; t1 = dy = -|y1 - y0|, t3 = step in y
        blt  t1, r0, ln_up
        li   t3, 1
        sub  t1, r0, t1
        j    ln_dy
ln_up:  li   t3, -1
ln_dy:  add  t4, t0, t1                 ; t4 = error
        li   s3, FB
ln_loop:
        shli s1, a1, 7                  ; plot (x, y)
        add  s1, s1, a0
        add  s1, s1, s3
        stb  s2, [s1]
        bne  a0, a2, ln_go
        beq  a1, a3, ln_done
ln_go:  shli s1, t4, 1                  ; s1 = 2 * error
        blt  s1, t1, ln_no_x
        add  t4, t4, t1
        add  a0, a0, t2
ln_no_x:
        bgt  s1, t0, ln_loop
        add  t4, t4, t0
        add  a1, a1, t3
        j    ln_loop
ln_done:
        ret
