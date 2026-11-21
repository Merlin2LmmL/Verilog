; Plasma: a swirling, colorful pattern that is made of sine waves. Space switches between
; three color schemes (rainbow, fire, ocean), q quits.
;
; The screen is 64 x 48 plasma cells of 2 x 2 pixels (sth writes two pixels at once, once for
; the upper and once for the lower pixel row of the cell). The color of a cell is the sum of
; three waves, looked up in a table of 256 sine values (0-255):
;   - a wave along x, that moves left or right over time
;   - a wave along y, that moves the other way
;   - a wave of the distance to the middle of the screen (circles), that moves outwards
; The sum picks an entry of the palette; shifting the palette a little every frame makes
; the colors flow. The distance of every cell is worked out once at the start: a table with
; the integer square root (times 6) of every squared distance 0-1680, then one lookup per
; cell (RAD). The x wave is the same for a whole column, so it is worked out once per frame
; (COL) and the y wave once per row.
; One frame takes about 60000 cycles, so the plasma runs at 30 frames per second.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24

        .equ COL,        0x1000         ; wave along x for the 64 columns (RAM, filled every frame)
        .equ PALCUR,     0x1100         ; the palette in use: a copy of one of the three below
        .equ RAD,        0x2000         ; 64 x 48 bytes: distance from the middle, times 6
        .equ SQRT,       0x3000         ; 6 * integer square root of 0-1680
        .equ SINTAB,     0x1200         ; 127.5 + 127.5 * sin(angle) for the angles 0-255, built at the start
        .equ SIN1,       0x00648558     ; sin of one step (1/256 turn), 28 fractional bits
        .equ COS2,       0x1FFD8861     ; 2 * cos of one step

        .equ TX,         0              ; state block: time offsets of the waves and the palette
        .equ TY,         4
        .equ TR,         8
        .equ TP,         12
        .equ PAL,        16             ; which of the 3 palettes

        .data
stops:  ; the 3 palettes as color stops: 28 bytes each, the number of segments, then (red, green, blue)
        ; for every stop (the colors in between are blended): rainbow, fire (up and back down), ocean
.byte 6, 255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0
        .byte 0, 255, 255, 0, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0
.byte 8, 0, 0, 0, 128, 0, 0, 255, 0, 0, 255, 160, 0, 255
        .byte 255, 0, 255, 160, 0, 255, 0, 0, 128, 0, 0, 0, 0, 0
.byte 6, 0, 0, 64, 0, 64, 192, 0, 192, 255, 220, 255, 255, 0
        .byte 192, 255, 0, 64, 192, 0, 0, 64, 0, 0, 0, 0, 0, 0
state:  .space 20

        .text
start:  li   sp, 0x00040000
        la   s0, state
        call build_sin
        call init_rad
        call set_palette

frame:  ld   t0, [s0+TX]                ; move the waves
        addi t0, t0, 3
        andi t0, t0, 255
        st   t0, [s0+TX]
        ld   t0, [s0+TY]
        addi t0, t0, -2
        andi t0, t0, 255
        st   t0, [s0+TY]
        ld   t0, [s0+TR]
        addi t0, t0, 2
        andi t0, t0, 255
        st   t0, [s0+TR]
        ld   t0, [s0+TP]
        addi t0, t0, 2
        andi t0, t0, 255
        st   t0, [s0+TP]

        ld   t1, [s0+TX]                ; wave along x for every column, 4 angle units per column
        li   t2, 0
fx:     andi t3, t1, 255
        ldbu t3, [t3+SINTAB]
        stb  t3, [t2+COL]
        addi t1, t1, 4
        addi t2, t2, 1
        li   t3, 64
        bne  t2, t3, fx

        ld   s2, [s0+TR]
        ld   s3, [s0+TP]
        ld   t3, [s0+TY]                ; angle of the y wave in the first row
        li   t2, 48                     ; rows left
        li   a0, FB
        li   a1, RAD
row:    andi t0, t3, 255
        ldbu s1, [t0+SINTAB]            ; the y wave of this row
        addi t3, t3, 4
        li   a2, COL
        li   a3, 64
cell:   ldbu t0, [a2]                   ; x wave
        ldbu t1, [a1]                   ; distance
        add  t1, t1, s2
        andi t1, t1, 255
        ldbu t1, [t1+SINTAB]            ; circle wave
        add  t0, t0, t1
        add  t0, t0, s1                 ; sum of 3 waves, 0-765
        shri t0, t0, 1
        add  t0, t0, s3                 ; + palette shift
        andi t0, t0, 255
        ldbu t0, [t0+PALCUR]
        shli t1, t0, 8
        or   t0, t0, t1                 ; the color twice: two pixels
        sth  t0, [a0]
        sth  t0, [a0+128]
        addi a0, a0, 2
        addi a1, a1, 1
        addi a2, a2, 1
        addi a3, a3, -1
        bnez a3, cell
        addi a0, a0, 128                ; the next cell row is 2 pixel rows down (we moved 1 row already)
        addi t2, t2, -1
        bnez t2, row

        li   t0, IO
        st   r0, [t0+FB_SHOW]
        ld   t1, [t0+VSYNC]
wait:   ld   t2, [t0+VSYNC]
        beq  t2, t1, wait
keys:   li   t0, IO
        ld   t1, [t0+KEY_STATUS]
        beqz t1, frame
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        beq  t1, t2, quit
        li   t2, ' '
        bne  t1, t2, keys
        ld   t0, [s0+PAL]               ; space: next palette
        addi t0, t0, 1
        li   t1, 3
        bne  t0, t1, pal_ok
        li   t0, 0
pal_ok: st   t0, [s0+PAL]
        call set_palette
        j    keys
quit:   halt

build_sin:                              ; SINTAB: 127.5 + 127.5 * sin(n / 256 turn), calculated instead of typed
        li   t0, SINTAB                 ; in: every sine value is 2 * cos * the last one - the one before
        li   t1, 0                      ; (28 fractional bits inside, the error stays below 1)
        li   t2, SIN1
        li   t4, COS2
        li   a0, 256
bs_loop:
        srai t3, t1, 14                 ; sine * 16384 -> 0 ... 255
        addi t3, t3, 16448
        shri t3, t3, 7
        li   a1, 255
        ble  t3, a1, bs_ok
        li   t3, 255
bs_ok:  stb  t3, [t0]
        addi t0, t0, 1
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

set_palette:                            ; PALCUR = the chosen palette: 256 colors blended from its stops
        ld   t0, [s0+PAL]
        li   t1, 28
        mul  t0, t0, t1
        la   a0, stops
        add  a0, a0, t0
        ldbu a1, [a0]                   ; number of segments
        addi a0, a0, 1                  ; the stops
        li   a2, PALCUR
        li   a3, 0                      ; color number
sp_loop:
        mul  t0, a3, a1                 ; position = number * segments / 256: segment, then how far
        shri t1, t0, 8
        andi t0, t0, 255
        shli t2, t1, 1
        add  t2, t2, t1
        add  t2, t2, a0                 ; this stop (3 bytes); the next one follows
        ldbu t3, [t2]                   ; red: blend, keep the top 3 bits
        ldbu t4, [t2+3]
        sub  t4, t4, t3
        mul  t4, t4, t0
        srai t4, t4, 8
        add  t3, t3, t4
        shri t3, t3, 5
        shli s1, t3, 5
        ldbu t3, [t2+1]                 ; green: top 3 bits
        ldbu t4, [t2+4]
        sub  t4, t4, t3
        mul  t4, t4, t0
        srai t4, t4, 8
        add  t3, t3, t4
        shri t3, t3, 5
        shli t3, t3, 2
        or   s1, s1, t3
        ldbu t3, [t2+2]                 ; blue: top 2 bits
        ldbu t4, [t2+5]
        sub  t4, t4, t3
        mul  t4, t4, t0
        srai t4, t4, 8
        add  t3, t3, t4
        shri t3, t3, 6
        or   s1, s1, t3
        add  t3, a2, a3
        stb  s1, [t3]
        addi a3, a3, 1
        li   t3, 256
        bne  a3, t3, sp_loop
        ret

init_rad:                               ; SQRT[i] = 6 * floor(sqrt(i)), then RAD for every cell
        li   t0, 0                      ; r
sq_r:   mul  t2, t0, t0                 ; the numbers r*r ... (r+1)*(r+1)-1 have the root r
        addi t3, t0, 1
        mul  t3, t3, t3
        li   t4, 6
        mul  t4, t4, t0
sq_i:   stb  t4, [t2+SQRT]
        addi t2, t2, 1
        bne  t2, t3, sq_i
        addi t0, t0, 1
        li   t1, 41
        bne  t0, t1, sq_r
        li   s1, 0                      ; cell row
        li   a0, RAD
rd_y:   addi t0, s1, -24
        mul  t0, t0, t0                 ; dy squared
        li   s2, 0                      ; cell column
rd_x:   addi t1, s2, -32
        mul  t1, t1, t1
        add  t1, t1, t0                 ; dx squared + dy squared
        ldbu t1, [t1+SQRT]
        stb  t1, [a0]
        addi a0, a0, 1
        addi s2, s2, 1
        li   t2, 64
        bne  s2, t2, rd_x
        addi s1, s1, 1
        li   t2, 48
        bne  s1, t2, rd_y
        ret
