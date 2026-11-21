; Hexrun: a little 3D game. You fly through a hexagonal tunnel, and rows of spikes come
; flying at you along its walls. Your ship stays at the bottom of the screen and the whole
; tunnel turns around you, so you steer by rotating the tunnel until a free wall is under
; you. Left / right (or A / D) turn it as long as you hold the key (it speeds up and slows down
; smoothly, the program reads the held keys from KEYS_HELD). The faster the tunnel comes at
; you, the faster it can turn, so the only limit is how fast you can react. Space stops the
; turning, q quits. Every row of spikes you survive is a point,
; and the longer you live the faster it gets (the bar at the top right shows the speed).
; Between the rows of spikes there are pads on the walls: a green one with a V pointing away
; adds a step of speed, a purple one with a V pointing at you takes one away, for the rest of
; the game (your ship shows the color for a moment); turn your ship onto a pad's wall to use it.
; When you crash, the score goes to the console
; and a new game starts.
;
; The tunnel is a set of hexagon rings. A ring at distance z has the radius 44 * 24 / (z + 24)
; (a table, so no division is needed), and its six corners are the radius times the six
; corner directions of a hexagon. Far rings are small and near rings big, and that is the whole
; perspective. To turn the tunnel by the angle a, the six directions are rotated once per frame
; with the sine and cosine of a (a table with 1024 steps per turn, 14 fractional bits); all
; rings and spikes then use the turned directions. A spike is a pyramid on one wall: a base from
; distance z to z + 8 and the tip pointing at the middle of the tunnel. The rings scroll
; towards you by moving all distances down every frame. The game runs at 60 frames per second.

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

        .equ ANG,        0              ; state block: angle of the tunnel (1024 = a full turn), score,
        .equ SCORE,      4
        .equ SPEED,      8              ; distance the world moves per frame,
        .equ PHASE,      12             ; scrolling of the rings (0-15),
        .equ GAP,        16             ; distance since the last row of spikes appeared,
        .equ I,          20             ; loop counters and temporaries
        .equ K,          24
        .equ F,          28
        .equ TMP0,         32
        .equ TMP1,         36
        .equ TMP2,         40
        .equ TMP3,         44
        .equ TMP4,         48
        .equ SC,         52             ; color of the line being drawn
        .equ SF,         56             ; wall and distance of the spike being drawn
        .equ SZ,         60
        .equ LASTV,      64             ; VSYNC at the end of the last frame
        .equ ROWS,       68             ; 4 rows of spikes: distance (-100 = unused), wall mask
        .equ VB,         100            ; 6 ring corners (x, y)
        .equ V2,         148            ; 6 more corners (the far end of the tunnel)
        .equ PT,         196            ; 7 points (x, y) of a spike or of the ship
        .equ OMEGA,      252            ; turning speed (angle per frame)
        .equ SPDH,       256            ; speed of the world in half steps (2 ... 12), sets how fast you can turn
        .equ RU,         264            ; the 6 corner directions of the turned hexagon (x, y), 8.8
        .equ PADS,       312            ; 3 pads: distance (-100 = unused), wall, kind (1 fast, 2 slow)
        .equ EFFT,       348            ; frames left that your ship shows the color of the last pad
        .equ EFFK,       352            ; ... and its kind
        .equ FRAC,       356            ; half steps of speed that are left over
        .equ PADF,       360            ; 1 once the pad between two rows of spikes exists
        .equ PADOFF,     364            ; steps of speed the pads you drove over added (-3 ... 3)
        .equ STATE_SIZE, 368

        .equ SINTAB,     0x8000         ; 1024 sine values (16 bits), built at the start
        .equ RADTAB,     0x8800         ; 256 ring radii (bytes), built at the start
        .equ SIN1,       0x001921F1     ; sin of one step (1/1024 turn), 28 fractional bits
        .equ COS2,       0x1FFFD886     ; 2 * cos of one step

        .equ NROWS,      4
        .equ GAPZ,       80             ; distance between two rows of spikes
        .equ GAPH,       40             ; a pad appears half way between two rows
        .equ ZSPAWN,     247            ; where new spikes appear: far away, you can see them coming
        .equ PADZ,       245            ; where new pads appear (a pad is 10 long)
        .equ NPADS,      3
        .equ PADTIME,    30             ; frames your ship shows the color of the last pad
        .equ WHITE,      0xFF
        .equ VPER,       4              ; fastest turning: angle per frame for every half step of speed
        .equ HALF,       30             ; half the width of your ship as an angle

        .data
state:  .space STATE_SIZE
ux:     .word 256, 128, -128, -256, -128, 128      ; corners of a hexagon, 8.8 fixed point
uy:     .word 0, 222, 222, 0, -222, -222
ring_shades:  .byte 0xB7, 0x93, 0x6F, 0x6F, 0x4B, 0x4A, 0x4A, 0x26      ; distance / 16, near ... far
              .byte 0x26, 0x25, 0x25, 0x25, 0x01, 0x01, 0x01, 0x01
spike_shades: .byte 0xFD, 0xF8, 0xF0, 0xE8, 0xC8, 0xA4, 0x88, 0x68
              .byte 0x68, 0x64, 0x64, 0x44, 0x44, 0x40, 0x40, 0x20
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
msg:    .string "CRASH! score: "
nl:     .string "\n"

        .text
start:  li   sp, 0x00040000
        la   s0, state
        call build_tables
        call new_game

frame:  call clear
        call turn
        call draw_rings
        call draw_spikes
        call draw_pads
        call draw_player
        call draw_speed
        li   a0, 2
        li   a1, 2
        call draw_score
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        ld   t1, [s0+LASTV]             ; keep 30 frames per second
fwait:  ld   t2, [t0+VSYNC]
        sub  t3, t2, t1
        li   t4, 1                      ; one frame is 1/60 second
        blt  t3, t4, fwait
        st   t2, [s0+LASTV]
        call update
        beqz a0, frame
        li   t0, 1
        beq  a0, t0, quit
        call game_over
        j    frame
quit:   halt

build_tables:                           ; the sine and the ring radius tables, calculated instead of typed in
        li   t0, SINTAB                 ; sin(n / 1024 turn) * 16384: every value is 2 * cos * the
        li   t1, 0                      ; last one - the one before (28 fractional bits inside,
        li   t2, SIN1                   ; so the rounding errors stay below 3 / 16384)
        li   t4, COS2
        li   a0, 1024
bt_sin: srai t3, t1, 14
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
        bnez a0, bt_sin
        li   t0, RADTAB                 ; ring radius for the distance z: 44 * 24 / (z + 24), rounded
        li   t1, 0
bt_rad: addi t3, t1, 24
        li   t4, 2112                   ; 2 * 44 * 24
        divu t4, t4, t3
        addi t4, t4, 1
        shri t4, t4, 1
        stb  t4, [t0]
        addi t0, t0, 1
        addi t1, t1, 1
        li   t3, 256
        bne  t1, t3, bt_rad
        ret

new_game:                               ; score 0, bottom wall, no spikes
        push lr
        st   r0, [s0+ANG]
        st   r0, [s0+OMEGA]
        st   r0, [s0+SCORE]
        li   t0, 2
        st   t0, [s0+SPEED]
        st   r0, [s0+PHASE]
        st   r0, [s0+GAP]
        st   r0, [s0+EFFT]
        st   r0, [s0+PADOFF]
        st   r0, [s0+FRAC]
        li   t0, 2
        st   t0, [s0+SPDH]
        st   r0, [s0+PADF]
        li   t0, -100
        st   t0, [s0+PADS]
        st   t0, [s0+PADS+12]
        st   t0, [s0+PADS+24]
        li   t1, 0
ng_row: shli t2, t1, 3
        add  t2, t2, s0
        st   t0, [t2+ROWS]
        addi t1, t1, 1
        li   t2, NROWS
        bne  t1, t2, ng_row
        li   t0, IO
        ld   t1, [t0+VSYNC]
        st   t1, [s0+LASTV]
        pop  lr
        ret

game_over:                              ; red screen with the score, message to the console
        push lr
        la   a0, msg
        call puts
        ld   t0, [s0+SCORE]
        li   t1, IO
        st   t0, [t1+PRINT_INT]
        la   a0, nl
        call puts
        li   t0, FB
        li   t1, FB + 128 * 96
        li   t2, 0x60606060
go_fill:
        st   t2, [t0]
        addi t0, t0, 4
        bne  t0, t1, go_fill
        li   a0, 52
        li   a1, 40
        call draw_score
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        li   s1, 90                     ; 1.5 seconds
go_wait:
        ld   t1, [t0+VSYNC]
go_w2:  ld   t2, [t0+VSYNC]
        beq  t2, t1, go_w2
        addi s1, s1, -1
        bnez s1, go_wait
go_keys:                                ; throw away the keys pressed in the meantime
        ld   t1, [t0+KEY_STATUS]
        beqz t1, go_end
        ld   t1, [t0+KEY_DATA]
        j    go_keys
go_end: call new_game
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

clear:  li   t0, FB                     ; black screen, 64 bytes per round
        li   t1, FB + 128 * 96
cl_loop:
        st   r0, [t0+0]
        st   r0, [t0+4]
        st   r0, [t0+8]
        st   r0, [t0+12]
        st   r0, [t0+16]
        st   r0, [t0+20]
        st   r0, [t0+24]
        st   r0, [t0+28]
        st   r0, [t0+32]
        st   r0, [t0+36]
        st   r0, [t0+40]
        st   r0, [t0+44]
        st   r0, [t0+48]
        st   r0, [t0+52]
        st   r0, [t0+56]
        st   r0, [t0+60]
        addi t0, t0, 64
        bne  t0, t1, cl_loop
        ret

; update: keys, scrolling, spikes. a0 = 0 normally, 1 if q was pressed, 2 if a spike hit you
update: push lr
        li   t0, IO
up_key: ld   t1, [t0+KEY_STATUS]        ; only q is read from the key queue, turning uses KEYS_HELD
        beqz t1, up_move
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        bne  t1, t2, up_key
        li   a0, 1
        pop  lr
        ret

up_move:
        ld   a2, [s0+SPDH]              ; the faster the tunnel comes, the faster you can turn, so
        shli a2, a2, 2                  ; that the limit is always your reaction, never the ship:
        ld   a3, [s0+SPDH]              ; top turning speed = 4 * speed, speeding up = speed / 2
        shri a3, a3, 1
        bnez a3, up_acc
        li   a3, 1
up_acc: li   t0, IO                     ; turning: the keys held right now give the wanted speed
        ld   t2, [t0+KEYS_HELD]
        li   t1, 0
        andi t3, t2, 8                  ; right
        beqz t3, up_nr
        add  t1, t1, a2
up_nr:  andi t3, t2, 4                  ; left: the tunnel turns the other way round
        beqz t3, up_nl
        sub  t1, t1, a2
up_nl:  andi t3, t2, 16                 ; space: stop turning at once
        beqz t3, up_tgt
        st   r0, [s0+OMEGA]
        li   t1, 0
up_tgt: ld   t0, [s0+OMEGA]
        ble  t0, t1, up_slow            ; omega <= target: speed up
        sub  t0, t0, a3
        bge  t0, t1, up_set
        mov  t0, t1
        j    up_set
up_slow:
        beq  t0, t1, up_set
        add  t0, t0, a3
        ble  t0, t1, up_set
        mov  t0, t1
up_set: st   t0, [s0+OMEGA]
        ld   t1, [s0+ANG]
        add  t1, t1, t0
        andi t1, t1, 1023
        st   t1, [s0+ANG]

        ld   t0, [s0+SCORE]             ; speed in half steps: 2, one more every 10 points (at most 5)
        li   t1, 10
        divu t0, t0, t1
        li   t1, 3
        ble  t0, t1, sp_ok
        li   t0, 3
sp_ok:  addi t0, t0, 2
        ld   t1, [s0+PADOFF]            ; every pad you drove over added or took away one step
        add  t0, t0, t1
        li   t1, 1
        bge  t0, t1, sp_lo
        li   t0, 1
sp_lo:  li   t1, 8
        ble  t0, t1, sp_hi
        li   t0, 8
sp_hi:  ld   t1, [s0+EFFT]              ; (the color of your ship fades back)
        beqz t1, sp_calc
        addi t1, t1, -1
        st   t1, [s0+EFFT]
sp_calc:
        st   t0, [s0+SPDH]
        ld   t1, [s0+FRAC]              ; distance this frame = half steps / 2
        add  t0, t0, t1
        andi t1, t0, 1
        st   t1, [s0+FRAC]
        shri t0, t0, 1
        st   t0, [s0+SPEED]

        ld   t0, [s0+PHASE]             ; rings come closer
        ld   t1, [s0+SPEED]
        sub  t0, t0, t1
        bge  t0, r0, ph_ok
        addi t0, t0, 16
ph_ok:  st   t0, [s0+PHASE]

        st   r0, [s0+I]                 ; move the rows of spikes
up_row: ld   t0, [s0+I]
        shli t3, t0, 3
        add  t3, t3, s0                 ; address of this row
        ld   t0, [t3+ROWS]              ; distance
        li   t1, -50
        ble  t0, t1, up_next            ; unused
        ld   t1, [s0+SPEED]
        sub  t0, t0, t1
        st   t0, [t3+ROWS]
        li   t1, 2
        bgt  t0, t1, up_next            ; still far away
        li   t1, -8
        blt  t0, t1, up_passed
        ld   t1, [s0+ANG]               ; the spikes are passing you: is your wall hit?
        li   t2, 256
        sub  t1, t2, t1                 ; your direction (down) in the turned tunnel
        addi t2, t1, -HALF              ; the left edge of your ship ...
        andi t2, t2, 1023
        li   t4, 6
        mul  t2, t2, t4
        shri t2, t2, 10                 ; ... is on this wall
        ld   t4, [t3+ROWS+4]
        shr  t2, t4, t2
        andi t2, t2, 1
        bnez t2, up_hit
        addi t2, t1, HALF               ; and the right edge on this one
        andi t2, t2, 1023
        li   t1, 6
        mul  t2, t2, t1
        shri t2, t2, 10
        shr  t2, t4, t2
        andi t2, t2, 1
        beqz t2, up_next
up_hit: li   a0, 2
        pop  lr
        ret
up_passed:
        li   t1, -100
        st   t1, [t3+ROWS]
        ld   t1, [s0+SCORE]
        addi t1, t1, 1
        st   t1, [s0+SCORE]
up_next:
        ld   t0, [s0+I]
        addi t0, t0, 1
        st   t0, [s0+I]
        li   t1, NROWS
        bne  t0, t1, up_row

        st   r0, [s0+I]                 ; pads: do they pass under your ship?
up_pad: ld   t0, [s0+I]
        shli t3, t0, 3
        shli t1, t0, 2
        add  t3, t3, t1
        add  t3, t3, s0                 ; address of this pad
        ld   t0, [t3+PADS]
        li   t1, -50
        ble  t0, t1, up_pnext           ; unused
        ld   t1, [s0+SPEED]
        sub  t0, t0, t1
        st   t0, [t3+PADS]
        li   t1, 2
        bgt  t0, t1, up_pnext           ; still far away
        li   t1, -10
        blt  t0, t1, up_pgone
        ld   a0, [t3+PADS+4]            ; is your ship on its wall?
        call on_wall
        beqz a0, up_pnext
        ld   t0, [s0+I]                 ; yes: speed change (the registers were overwritten)
        shli t3, t0, 3
        shli t1, t0, 2
        add  t3, t3, t1
        add  t3, t3, s0
        ld   t1, [t3+PADS+8]
        st   t1, [s0+EFFK]
        li   t2, PADTIME
        st   t2, [s0+EFFT]
        ld   t2, [s0+PADOFF]            ; a fast pad adds a step of speed, a slow pad takes one away
        li   t4, 1
        beq  t1, t4, pd_up
        li   t4, -1
pd_up:  add  t2, t2, t4
        li   t4, 3
        ble  t2, t4, pd_c1
        li   t2, 3
pd_c1:  li   t4, -3
        bge  t2, t4, pd_c2
        li   t2, -3
pd_c2:  st   t2, [s0+PADOFF]
up_pgone:
        li   t1, -100
        st   t1, [t3+PADS]
up_pnext:
        ld   t0, [s0+I]
        addi t0, t0, 1
        st   t0, [s0+I]
        li   t1, NPADS
        bne  t0, t1, up_pad

        ld   t0, [s0+GAP]
        ld   t1, [s0+SPEED]
        add  t0, t0, t1
        st   t0, [s0+GAP]
        li   t1, GAPZ
        bge  t0, t1, up_spawn
        li   t1, GAPH
        blt  t0, t1, up_done
        ld   t2, [s0+PADF]
        bnez t2, up_done
        li   t2, 1
        st   t2, [s0+PADF]
        call spawn_pad
        j    up_done
up_spawn:
        st   r0, [s0+PADF]
        call spawn
up_done:
        li   a0, 0
        pop  lr
        ret

spawn:                                  ; a new row of spikes on random walls (1 to 4 of the 6)
        li   t3, 0
sp_find:
        shli t2, t3, 3
        add  t2, t2, s0
        ld   t0, [t2+ROWS]
        li   t1, -50
        ble  t0, t1, sp_found
        addi t3, t3, 1
        li   t1, NROWS
        bne  t3, t1, sp_find
        ret                             ; no free row
sp_found:
        li   t3, IO
        ld   t1, [t3+RANDOM]
        shri t1, t1, 5
        andi t1, t1, 63                 ; one random bit per wall
sp_cnt: mov  t3, t1                     ; more than 4 walls: remove the lowest one
        li   t4, 0
sp_pop: beqz t3, sp_pd
        addi t0, t3, -1
        and  t3, t3, t0
        addi t4, t4, 1
        j    sp_pop
sp_pd:  li   t0, 4
        ble  t4, t0, sp_few
        addi t0, t1, -1
        and  t1, t1, t0
        j    sp_cnt
sp_few: bnez t1, sp_set                 ; no wall at all: pick one
        li   t3, IO
        ld   t3, [t3+RANDOM]
        shri t3, t3, 9
        li   t4, 6
        modu t3, t3, t4
        li   t1, 1
        shl  t1, t1, t3
sp_set: li   t0, ZSPAWN
        st   t0, [t2+ROWS]
        st   t1, [t2+ROWS+4]
        st   r0, [s0+GAP]
        ret

; on_wall(a0 = wall 0-5) -> a0 = 1 if your ship is (partly) on that wall
on_wall:
        ld   t1, [s0+ANG]
        li   t2, 256
        sub  t1, t2, t1                 ; your direction (down) in the turned tunnel
        addi t2, t1, -HALF              ; the left edge of your ship
        andi t2, t2, 1023
        li   t3, 6
        mul  t2, t2, t3
        shri t2, t2, 10
        beq  t2, a0, ow_yes
        addi t2, t1, HALF               ; the right edge
        andi t2, t2, 1023
        mul  t2, t2, t3
        shri t2, t2, 10
        beq  t2, a0, ow_yes
        li   a0, 0
        ret
ow_yes: li   a0, 1
        ret

spawn_pad:                              ; a pad on a random wall, fast or slow
        li   t3, 0
pf_find:
        shli t2, t3, 3
        shli t1, t3, 2
        add  t2, t2, t1
        add  t2, t2, s0
        ld   t0, [t2+PADS]
        li   t1, -50
        ble  t0, t1, pf_found
        addi t3, t3, 1
        li   t1, NPADS
        bne  t3, t1, pf_find
        ret
pf_found:
        li   t3, IO
        ld   t1, [t3+RANDOM]
        shri t1, t1, 6
        li   t4, 6
        modu t0, t1, t4
        st   t0, [t2+PADS+4]
        ld   t1, [t3+RANDOM]
        shri t1, t1, 11
        andi t1, t1, 1
        addi t1, t1, 1
        st   t1, [t2+PADS+8]
        li   t0, PADZ
        st   t0, [t2+PADS]
        ret

; vert(a0 = corner 0-5, a1 = ring radius) -> (a0, a1) = corner on the screen
vert:   shli t1, a0, 3
        add  t1, t1, s0
        ld   t2, [t1+RU]
        mul  t2, t2, a1
        srai t2, t2, 8
        addi t2, t2, 64
        ld   t0, [t1+RU+4]
        mul  t0, t0, a1
        srai t0, t0, 8
        addi a1, t0, 48
        mov  a0, t2
        ret

; sine(a0 = angle) -> a0 = sine * 16384
sine:   andi a0, a0, 1023
        shli t0, a0, 1
        li   t1, SINTAB
        add  t0, t0, t1
        ldh  a0, [t0]
        ret

; turn: rotate the six corner directions by the angle ANG and store them in RU
turn:   push lr
        ld   a0, [s0+ANG]
        call sine
        st   a0, [s0+TMP0]              ; sin
        ld   a0, [s0+ANG]
        addi a0, a0, 256
        call sine
        st   a0, [s0+TMP1]              ; cos
        li   a3, 0
tn:     shli t0, a3, 2
        la   t1, ux
        add  t1, t1, t0
        ld   a1, [t1]                   ; ux
        la   t1, uy
        add  t1, t1, t0
        ld   a2, [t1]                   ; uy
        ld   t3, [s0+TMP1]
        ld   t4, [s0+TMP0]
        mul  t0, a1, t3                 ; x = (ux * cos - uy * sin) >> 14
        mul  t1, a2, t4
        sub  t0, t0, t1
        srai t0, t0, 14
        mul  t1, a1, t4                 ; y = (ux * sin + uy * cos) >> 14
        mul  t2, a2, t3
        add  t1, t1, t2
        srai t1, t1, 14
        shli t2, a3, 3
        add  t2, t2, s0
        st   t0, [t2+RU]
        st   t1, [t2+RU+4]
        addi a3, a3, 1
        li   t0, 6
        bne  a3, t0, tn
        pop  lr
        ret

radius: li   t0, RADTAB                 ; radius(a0 = distance) -> a0
        add  t0, t0, a0
        ldbu a0, [t0]
        ret

; fv(a0 = corner 0-6 (6 = 0), a1 = distance) -> (a0, a1) = corner of the ring at that distance
fv:     push lr
        st   a0, [s0+TMP0]
        mov  a0, a1
        call radius
        mov  a1, a0
        ld   a0, [s0+TMP0]
        li   t0, 6
        bne  a0, t0, fv_ok
        li   a0, 0
fv_ok:  call vert
        pop  lr
        ret

; fvst(a0 = corner, a1 = distance, a2 = slot offset): like fv, stores the point in the slot
fvst:   push lr
        call fv
        add  t0, s0, a2
        st   a0, [t0+PT]
        st   a1, [t0+PT+4]
        pop  lr
        ret

; ring_verts(a2 = radius, t3 = address where the 6 corners go)
ring_verts:
        push lr
        li   a3, 0
rv:     mov  a0, a3
        mov  a1, a2
        call vert
        st   a0, [t3]
        st   a1, [t3+4]
        addi t3, t3, 8
        addi a3, a3, 1
        li   t4, 6
        bne  a3, t4, rv
        pop  lr
        ret

; ring_lines(s2 = color): the hexagon through the 6 corners in VB
ring_lines:
        push lr
        st   r0, [s0+K]
rl:     ld   t0, [s0+K]
        shli t1, t0, 3
        add  t1, t1, s0
        ld   a0, [t1+VB]
        ld   a1, [t1+VB+4]
        addi t0, t0, 1
        li   t2, 6
        bne  t0, t2, rl_n
        li   t0, 0
rl_n:   shli t1, t0, 3
        add  t1, t1, s0
        ld   a2, [t1+VB]
        ld   a3, [t1+VB+4]
        call line
        ld   t0, [s0+K]
        addi t0, t0, 1
        st   t0, [s0+K]
        li   t1, 6
        bne  t0, t1, rl
        pop  lr
        ret

draw_rings:
        push lr
        st   r0, [s0+I]
dr:     ld   t0, [s0+I]                 ; the rings 8 ... 15 (far away) are only drawn every second time
        li   t1, 8
        blt  t0, t1, dr_draw
        andi t1, t0, 1
        bnez t1, dr_next
dr_draw:
        ld   t0, [s0+I]
        shli t0, t0, 4                  ; distance of this ring
        ld   t1, [s0+PHASE]
        add  t0, t0, t1
        st   t0, [s0+F]
        mov  a0, t0
        call radius
        mov  a2, a0
        addi t3, s0, VB
        call ring_verts
        ld   t0, [s0+F]
        shri t0, t0, 4
        la   t1, ring_shades
        add  t1, t1, t0
        ldbu s2, [t1]
        call ring_lines
dr_next:
        ld   t0, [s0+I]
        addi t0, t0, 1
        st   t0, [s0+I]
        li   t1, 16
        bne  t0, t1, dr

        li   a0, 255                    ; the six edges of the tunnel, from the near to the far end
        call radius
        mov  a2, a0
        addi t3, s0, V2
        call ring_verts
        ld   a0, [s0+PHASE]             ; ... starting at the nearest ring
        call radius
        mov  a2, a0
        addi t3, s0, VB
        call ring_verts
        li   s2, 0x49
        st   r0, [s0+K]
de:     ld   t0, [s0+K]
        shli t1, t0, 3
        add  t1, t1, s0
        ld   a0, [t1+VB]
        ld   a1, [t1+VB+4]
        ld   a2, [t1+V2]
        ld   a3, [t1+V2+4]
        call line
        ld   t0, [s0+K]
        addi t0, t0, 1
        st   t0, [s0+K]
        li   t1, 6
        bne  t0, t1, de
        pop  lr
        ret

; lineslots(a0 = slot, a1 = slot): line between two stored points, in the color SC
lineslots:
        push lr
        add  t0, s0, a0
        add  t1, s0, a1
        ld   a0, [t0+PT]
        ld   a1, [t0+PT+4]
        ld   a2, [t1+PT]
        ld   a3, [t1+PT+4]
        ld   s2, [s0+SC]
        call line
        pop  lr
        ret

; apexc(a0 = 0 for x / 4 for y, a1 = 2 * middle of the screen, a2, a3 = slots of two corners):
; the slot at 48 gets a point on the way from the wall to the middle of the tunnel
apexc:  add  t4, s0, a0
        add  t0, s0, a2
        add  t0, t0, a0
        ld   t0, [t0+PT]
        add  t1, s0, a3
        add  t1, t1, a0
        ld   t1, [t1+PT]
        add  t2, t0, t1
        sub  t2, t2, a1
        srai t2, t2, 1
        li   t3, 166
        mul  t2, t2, t3
        srai t2, t2, 8
        shri t3, a1, 1
        add  t2, t2, t3
        st   t2, [t4+PT+48]
        ret

draw_spikes:
        push lr
        st   r0, [s0+I]
ds_row: ld   t0, [s0+I]
        shli t3, t0, 3
        add  t3, t3, s0
        ld   t0, [t3+ROWS]
        li   t1, -50
        ble  t0, t1, ds_next
        st   r0, [s0+K]
ds_face:
        ld   t3, [s0+I]
        shli t3, t3, 3
        add  t3, t3, s0
        ld   t1, [t3+ROWS+4]
        ld   t2, [s0+K]
        shr  t1, t1, t2
        andi t1, t1, 1
        beqz t1, ds_fnext
        ld   a1, [t3+ROWS]
        ld   a0, [s0+K]
        call draw_spike
ds_fnext:
        ld   t0, [s0+K]
        addi t0, t0, 1
        st   t0, [s0+K]
        li   t1, 6
        bne  t0, t1, ds_face
ds_next:
        ld   t0, [s0+I]
        addi t0, t0, 1
        st   t0, [s0+I]
        li   t1, NROWS
        bne  t0, t1, ds_row
        pop  lr
        ret

; draw_spike(a0 = wall, a1 = distance of its near edge)
draw_spike:
        push lr
        st   a0, [s0+SF]
        bge  a1, r0, dp_z
        li   a1, 0
dp_z:   st   a1, [s0+SZ]
        shri t0, a1, 4
        la   t1, spike_shades
        add  t1, t1, t0
        ldbu t0, [t1]
        st   t0, [s0+SC]
        ld   a0, [s0+SF]                ; the four corners of the base: near and far edge
        ld   a1, [s0+SZ]
        li   a2, 0
        call fvst
        ld   a0, [s0+SF]
        addi a0, a0, 1
        ld   a1, [s0+SZ]
        li   a2, 8
        call fvst
        ld   a0, [s0+SF]
        ld   a1, [s0+SZ]
        addi a1, a1, 8
        li   a2, 16
        call fvst
        ld   a0, [s0+SF]
        addi a0, a0, 1
        ld   a1, [s0+SZ]
        addi a1, a1, 8
        li   a2, 24
        call fvst
        ld   a0, [s0+SF]                ; the middle of the base, to find the tip
        ld   a1, [s0+SZ]
        addi a1, a1, 4
        li   a2, 32
        call fvst
        ld   a0, [s0+SF]
        addi a0, a0, 1
        ld   a1, [s0+SZ]
        addi a1, a1, 4
        li   a2, 40
        call fvst
        li   a0, 0
        li   a1, 128
        li   a2, 32
        li   a3, 40
        call apexc
        li   a0, 4
        li   a1, 96
        li   a2, 32
        li   a3, 40
        call apexc
        li   a0, 0                      ; near edge, then the tip to all four corners
        li   a1, 8
        call lineslots
        li   a0, 48
        li   a1, 0
        call lineslots
        li   a0, 48
        li   a1, 8
        call lineslots
        li   a0, 48
        li   a1, 16
        call lineslots
        li   a0, 48
        li   a1, 24
        call lineslots
        pop  lr
        ret

; midslot(a0 = slot, a1 = slot, a2 = slot): the middle of two stored points
midslot:
        add  t0, s0, a0
        add  t1, s0, a1
        add  t2, s0, a2
        ld   t3, [t0+PT]
        ld   t4, [t1+PT]
        add  t3, t3, t4
        srai t3, t3, 1
        st   t3, [t2+PT]
        ld   t3, [t0+PT+4]
        ld   t4, [t1+PT+4]
        add  t3, t3, t4
        srai t3, t3, 1
        st   t3, [t2+PT+4]
        ret

draw_pads:
        push lr
        st   r0, [s0+I]
dd_pad: ld   t0, [s0+I]
        shli t3, t0, 3
        shli t1, t0, 2
        add  t3, t3, t1
        add  t3, t3, s0
        ld   t0, [t3+PADS]
        li   t1, -50
        ble  t0, t1, dd_next
        ld   a0, [t3+PADS+4]
        mov  a1, t0
        ld   a2, [t3+PADS+8]
        call draw_pad
dd_next:
        ld   t0, [s0+I]
        addi t0, t0, 1
        st   t0, [s0+I]
        li   t1, NPADS
        bne  t0, t1, dd_pad
        pop  lr
        ret

; draw_pad(a0 = wall, a1 = distance of its near edge, a2 = 1 fast / 2 slow): a rectangle on
; the wall with a V in it: pointing away from you = faster, pointing at you = slower
draw_pad:
        push lr
        st   a0, [s0+SF]
        st   a2, [s0+TMP2]
        bge  a1, r0, dq_z
        li   a1, 0
dq_z:   st   a1, [s0+SZ]
        li   t0, 0x1C                   ; green: fast
        li   t1, 1
        beq  a2, t1, dq_col
        li   t0, 0xE3                   ; purple: slow
dq_col: st   t0, [s0+SC]
        ld   a0, [s0+SF]
        ld   a1, [s0+SZ]
        li   a2, 0
        call fvst
        ld   a0, [s0+SF]
        addi a0, a0, 1
        ld   a1, [s0+SZ]
        li   a2, 8
        call fvst
        ld   a0, [s0+SF]
        ld   a1, [s0+SZ]
        addi a1, a1, 10
        li   a2, 16
        call fvst
        ld   a0, [s0+SF]
        addi a0, a0, 1
        ld   a1, [s0+SZ]
        addi a1, a1, 10
        li   a2, 24
        call fvst
        li   a0, 16                     ; middle of the far and of the near edge
        li   a1, 24
        li   a2, 32
        call midslot
        li   a0, 0
        li   a1, 8
        li   a2, 40
        call midslot
        li   a0, 0
        li   a1, 8
        call lineslots
        li   a0, 16
        li   a1, 24
        call lineslots
        li   a0, 0
        li   a1, 16
        call lineslots
        li   a0, 8
        li   a1, 24
        call lineslots
        ld   t0, [s0+TMP2]
        li   t1, 1
        bne  t0, t1, dq_slow
        li   a0, 0                      ; fast: V from the near corners to the middle of the far edge
        li   a1, 32
        call lineslots
        li   a0, 8
        li   a1, 32
        call lineslots
        j    dq_end
dq_slow:
        li   a0, 16                     ; slow: V from the far corners to the middle of the near edge
        li   a1, 40
        call lineslots
        li   a0, 24
        li   a1, 40
        call lineslots
dq_end: pop  lr
        ret

draw_speed:                             ; a bar of small blocks at the top right: the speed
        ld   t0, [s0+SPDH]
        li   t4, WHITE
        ld   t1, [s0+EFFT]
        beqz t1, ds_go
        li   t4, 0x1C                   ; green / purple while the last pad's color shows
        ld   t1, [s0+EFFK]
        li   t2, 1
        beq  t1, t2, ds_go
        li   t4, 0xE3
ds_go:  li   t1, FB
        addi t1, t1, 356                ; x = 100, y = 2
ds_bar: beqz t0, ds_done
        stb  t4, [t1]
        stb  t4, [t1+1]
        stb  t4, [t1+128]
        stb  t4, [t1+129]
        stb  t4, [t1+256]
        stb  t4, [t1+257]
        stb  t4, [t1+384]
        stb  t4, [t1+385]
        addi t1, t1, 3
        addi t0, t0, -1
        j    ds_bar
ds_done:
        ret

draw_player:                            ; your ship: a little triangle at the bottom of the screen
        push lr
        li   t0, 0x1F                   ; cyan, green when a pad makes you faster, purple when slower
        ld   t1, [s0+EFFT]
        beqz t1, dp_col
        li   t0, 0x1C
        ld   t1, [s0+EFFK]
        li   t2, 1
        beq  t1, t2, dp_col
        li   t0, 0xE3
dp_col: st   t0, [s0+SC]
        li   t0, 56
        st   t0, [s0+PT]
        li   t0, 84
        st   t0, [s0+PT+4]
        li   t0, 72
        st   t0, [s0+PT+8]
        li   t0, 84
        st   t0, [s0+PT+12]
        li   t0, 64
        st   t0, [s0+PT+16]
        li   t0, 72
        st   t0, [s0+PT+20]
        li   a0, 0
        li   a1, 8
        call lineslots
        li   a0, 0
        li   a1, 16
        call lineslots
        li   a0, 8
        li   a1, 16
        call lineslots
        pop  lr
        ret

; draw_score(a0 = x, a1 = y): three digits
draw_score:
        push lr
        st   a0, [s0+TMP0]
        st   a1, [s0+TMP1]
        ld   t0, [s0+SCORE]
        li   t1, 100
        divu t2, t0, t1
        li   t3, 9
        ble  t2, t3, sc_h
        li   t2, 9
sc_h:   st   t2, [s0+TMP2]
        modu t0, t0, t1
        li   t1, 10
        divu t2, t0, t1
        st   t2, [s0+TMP3]
        modu t2, t0, t1
        st   t2, [s0+TMP4]
        ld   a0, [s0+TMP0]
        ld   a1, [s0+TMP1]
        ld   a2, [s0+TMP2]
        call digit
        ld   a0, [s0+TMP0]
        addi a0, a0, 8
        ld   a1, [s0+TMP1]
        ld   a2, [s0+TMP3]
        call digit
        ld   a0, [s0+TMP0]
        addi a0, a0, 16
        ld   a1, [s0+TMP1]
        ld   a2, [s0+TMP4]
        call digit
        pop  lr
        ret

; digit(a0 = x, a1 = y, a2 = 0-9): a 3 x 5 digit, every dot is 2 x 2 pixels
digit:  shli t0, a1, 7
        add  t0, t0, a0
        li   t1, FB
        add  t0, t0, t1                 ; screen address of the top left corner
        la   t1, font
        li   t2, 5
        mul  t2, t2, a2
        add  t1, t1, t2                 ; the 5 rows of this digit
        li   a3, 5
dg_row: ldbu t2, [t1]
        li   t3, 4                      ; bit of the leftmost dot
        mov  t4, t0
dg_col: and  a2, t2, t3
        beqz a2, dg_skip
        li   a2, WHITE
        stb  a2, [t4]
        stb  a2, [t4+1]
        stb  a2, [t4+128]
        stb  a2, [t4+129]
dg_skip:
        addi t4, t4, 2
        shri t3, t3, 1
        bnez t3, dg_col
        addi t1, t1, 1
        addi t0, t0, 256
        addi a3, a3, -1
        bnez a3, dg_row
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
