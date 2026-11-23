; Pong against the computer. You are the green paddle on the left, the computer is the red one
; on the right. First to 7 points wins.
;
; Keys: up / W moves your paddle up, down / S moves it down, q quits. The paddle moves exactly
; as long as you hold the key: the program reads the keys that are down right now from the
; KEYS_HELD register, so it stops the moment you let go and can be placed precisely.
; In the playground you can also hold the mouse button (or a finger) on the screen: the
; paddle follows its height, at most 4 pixels per frame.
;
; Where the ball hits the paddle decides where it goes next: the center sends it straight back,
; the edges send it away at an angle. Every hit makes it a little faster. The computer follows
; the ball at a speed of one pixel per frame, so a steep shot can get past it.
;
; The ball position and speed are fixed point numbers with 8 fractional bits (256 = 1 pixel,
; so the speed 320 is 1.25 pixels per frame). All variables are words in the state block, s0
; points to it. Every frame: erase the ball and paddles at their old place, read keys, move
; everything, draw the center line, the scores, the paddles and the ball, show, wait for VSYNC.

        .equ FB,         0xFFFD0000     ; 128 x 96 pixels, one byte each (RGB332)
        .equ IO,         0xFFFF0000
        .equ CONSOLE,    0x00
        .equ KEY_STATUS, 0x08
        .equ KEY_DATA,   0x0C
        .equ RANDOM,     0x14
        .equ FB_SHOW,    0x20
        .equ VSYNC,      0x24
        .equ KEYS_HELD,  0x28
        .equ POINTER_Y,  0x30
        .equ POINTER_BTN,0x34

        .equ BX,         0              ; state block: ball x and y (8.8), ball speed x and y
        .equ BY,         4
        .equ VX,         8
        .equ VY,         12
        .equ PY,         16             ; top of the player's paddle and the computer's paddle
        .equ CY,         20
        .equ SCORE_P,    28
        .equ SCORE_C,    32
        .equ TIMER,      36             ; frames until the ball starts moving after a serve

        .equ PH,         16             ; paddle height
        .equ PH_HALF,    8
        .equ PX,         3              ; x of the player's paddle (2 pixels wide)
        .equ CX,         123            ; x of the computer's paddle
        .equ WIN,        7
        .equ GREEN,      0x1C
        .equ RED,        0xE0
        .equ GRAY,       0x49
        .equ WHITE,      0xFF

        .data
state:  .space 44
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
msg_win:  .string "YOU WIN\n"
msg_lose: .string "CPU WINS\n"

        .text
start:  li   sp, 0x00040000
        la   s0, state
        call new_match

loop:   call erase
        call read_keys
        bnez a0, quit
        call update
        call draw
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        ld   t1, [t0+VSYNC]
wait:   ld   t2, [t0+VSYNC]
        beq  t2, t1, wait
        ld   t0, [s0+SCORE_P]
        li   t1, WIN
        bge  t0, t1, won
        ld   t0, [s0+SCORE_C]
        bge  t0, t1, lost
        j    loop
won:    li   a0, 1
        call game_over
        j    loop
lost:   li   a0, 0
        call game_over
        j    loop
quit:   halt

new_match:                              ; scores 0, paddles in the middle, black screen, serve
        push lr
        st   r0, [s0+SCORE_P]
        st   r0, [s0+SCORE_C]
        li   t0, 40
        st   t0, [s0+PY]
        st   t0, [s0+CY]
        li   t0, FB
        li   t1, FB + 128 * 96
nm_clr: st   r0, [t0]
        addi t0, t0, 4
        bne  t0, t1, nm_clr
        li   a0, 1
        call serve
        pop  lr
        ret

serve:                                  ; serve(a0 = direction): ball in the middle, a short pause
        li   t0, 62 << 8
        st   t0, [s0+BX]
        li   t0, 47 << 8
        st   t0, [s0+BY]
        li   t0, 320
        mul  t0, t0, a0
        st   t0, [s0+VX]
        li   t1, IO
        ld   t1, [t1+RANDOM]
        shri t1, t1, 8
        li   t2, 385
        modu t1, t1, t2
        addi t1, t1, -192               ; -192 ... 192 = up to 0.75 pixels per frame sideways
        st   t1, [s0+VY]
        li   t0, 50
        st   t0, [s0+TIMER]
        ret

game_over:                              ; game_over(a0 = 1 if the player won): bars, message, pause
        push lr
        li   t4, RED
        la   a1, msg_lose
        beqz a0, go_show
        li   t4, GREEN
        la   a1, msg_win
go_show:
        mov  s1, a1
        li   a0, 0
        li   a1, 0
        li   a2, 128
        li   a3, 3
        call rect
        li   a0, 0
        li   a1, 93
        li   a2, 128
        li   a3, 3
        call rect
        mov  a0, s1
        call puts
        li   t0, IO
        st   r0, [t0+FB_SHOW]
        li   s1, 150                    ; 2.5 seconds
go_wait:
        ld   t1, [t0+VSYNC]
go_w2:  ld   t2, [t0+VSYNC]
        beq  t2, t1, go_w2
        addi s1, s1, -1
        bnez s1, go_wait
        call new_match
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

erase:  push lr                         ; black over the ball and both paddles
        li   t4, 0
        ld   a0, [s0+BX]
        srai a0, a0, 8
        ld   a1, [s0+BY]
        srai a1, a1, 8
        li   a2, 3
        li   a3, 3
        call rect
        li   t4, 0
        li   a0, PX
        ld   a1, [s0+PY]
        li   a2, 2
        li   a3, PH
        call rect
        li   t4, 0
        li   a0, CX
        ld   a1, [s0+CY]
        li   a2, 2
        li   a3, PH
        call rect
        pop  lr
        ret

draw:   push lr
        li   s1, 0                      ; dotted line in the middle
dr_line:
        li   t4, GRAY
        li   a0, 63
        mov  a1, s1
        li   a2, 2
        li   a3, 4
        call rect
        addi s1, s1, 8
        li   t0, 96
        blt  s1, t0, dr_line
        li   t4, 0                      ; the scores: clear the old digit, draw the new one
        li   a0, 48
        li   a1, 4
        li   a2, 6
        li   a3, 10
        call rect
        li   a0, 48
        li   a1, 4
        ld   a2, [s0+SCORE_P]
        call digit
        li   t4, 0
        li   a0, 74
        li   a1, 4
        li   a2, 6
        li   a3, 10
        call rect
        li   a0, 74
        li   a1, 4
        ld   a2, [s0+SCORE_C]
        call digit
        li   t4, GREEN
        li   a0, PX
        ld   a1, [s0+PY]
        li   a2, 2
        li   a3, PH
        call rect
        li   t4, RED
        li   a0, CX
        ld   a1, [s0+CY]
        li   a2, 2
        li   a3, PH
        call rect
        li   t4, WHITE
        ld   a0, [s0+BX]
        srai a0, a0, 8
        ld   a1, [s0+BY]
        srai a1, a1, 8
        li   a2, 3
        li   a3, 3
        call rect
        pop  lr
        ret

read_keys:                              ; a0 = 1 if q was pressed (the paddle uses KEYS_HELD)
        li   t0, IO
rk_next:
        ld   t1, [t0+KEY_STATUS]
        beqz t1, rk_done
        ld   t1, [t0+KEY_DATA]
        li   t2, 'q'
        bne  t1, t2, rk_next
        li   a0, 1
        ret
rk_done:
        li   a0, 0
        ret

update: push lr
        li   t2, IO                     ; your paddle: moves while up or down is held
        ld   t2, [t2+KEYS_HELD]
        li   t1, 0
        andi t3, t2, 1                  ; up
        beqz t3, pk_nu
        addi t1, t1, -1
pk_nu:  andi t3, t2, 2                  ; down
        beqz t3, pk_nd
        addi t1, t1, 1
pk_nd:  ld   t0, [s0+PY]
        shli t1, t1, 1                  ; 2 pixels per frame
        add  t0, t0, t1
        li   t2, IO                     ; mouse or finger down: follow it, at most 4 pixels per frame
        ld   t3, [t2+POINTER_BTN]
        andi t3, t3, 1
        beqz t3, pk_clamp
        ld   t3, [t2+POINTER_Y]
        addi t3, t3, -PH_HALF           ; the paddle's center goes to the pointer
        sub  t3, t3, t0
        li   t4, 4
        ble  t3, t4, pk_dhi
        mov  t3, t4
pk_dhi: sub  t4, r0, t4
        bge  t3, t4, pk_dlo
        mov  t3, t4
pk_dlo: add  t0, t0, t3
pk_clamp:
        call clamp
        st   t0, [s0+PY]

        ld   t0, [s0+CY]                ; the computer's paddle
        ld   t1, [s0+VX]
        ble  t1, r0, ai_idle            ; ball goes away from it: back to the middle
        ld   t1, [s0+BX]
        srai t1, t1, 8
        li   t2, 50
        blt  t1, t2, ai_idle            ; ball is still far away
        ld   t2, [s0+BY]
        srai t2, t2, 8
        addi t2, t2, 1                  ; center of the ball
        j    ai_go
ai_idle:
        li   t2, 48
ai_go:  addi t3, t0, PH_HALF             ; center of the paddle
        sub  t4, t2, t3
        li   t1, 3                      ; 3 pixels of slack, so it does not jitter
        ble  t4, t1, ai_up
        addi t0, t0, 1
        j    ai_done
ai_up:  li   t1, -3
        bge  t4, t1, ai_done
        addi t0, t0, -1
ai_done:
        call clamp
        st   t0, [s0+CY]

        ld   t0, [s0+TIMER]             ; the ball waits after a serve
        beqz t0, move_ball
        addi t0, t0, -1
        st   t0, [s0+TIMER]
        pop  lr
        ret

move_ball:
        ld   s1, [s0+BX]
        srai s2, s1, 8                  ; s2 = x before the move
        ld   t0, [s0+VX]
        add  s1, s1, t0                 ; s1 = new x
        ld   t1, [s0+BY]
        ld   t2, [s0+VY]
        add  t1, t1, t2                 ; t1 = new y
        bge  t1, r0, mb_top_ok          ; top wall: mirror
        sub  t1, r0, t1
        sub  t2, r0, t2
        st   t2, [s0+VY]
mb_top_ok:
        li   t3, 93 << 8                ; bottom wall: mirror
        ble  t1, t3, mb_bot_ok
        shli t3, t3, 1
        sub  t1, t3, t1
        sub  t2, r0, t2
        st   t2, [s0+VY]
mb_bot_ok:
        st   t1, [s0+BY]
        srai t1, t1, 8                  ; t1 = y in pixels
        srai s3, s1, 8                  ; s3 = x in pixels
        ld   t0, [s0+VX]
        bgt  t0, r0, mb_right

        li   t3, 5                      ; moving left: the paddle front is at x = 5
        bgt  s3, t3, mb_check
        blt  s2, t3, mb_check           ; it was already behind the paddle
        ld   t4, [s0+PY]
        addi t2, t1, 3
        ble  t2, t4, mb_check           ; ball is above the paddle
        addi t2, t4, PH
        bge  t1, t2, mb_check           ; ball is below it
        li   s1, 5 << 8                 ; hit: put the ball in front of the paddle
        sub  t0, r0, t0                 ; reverse and speed up
        addi t0, t0, 16
        j    mb_bounce

mb_right:
        li   t3, 120                    ; the paddle front is at x = 120 (ball is 3 wide)
        blt  s3, t3, mb_check
        bgt  s2, t3, mb_check
        ld   t4, [s0+CY]
        addi t2, t1, 3
        ble  t2, t4, mb_check
        addi t2, t4, PH
        bge  t1, t2, mb_check
        li   s1, 120 << 8
        sub  t0, r0, t0
        addi t0, t0, -16
mb_bounce:                              ; t0 = new x speed, t1 = ball y, t4 = paddle y
        st   t0, [s0+VX]
        addi t2, t1, 1                  ; center of the ball minus center of the paddle
        addi t3, t4, PH_HALF
        sub  t2, t2, t3
        li   t3, 40                     ; the further from the center, the steeper
        mul  t2, t2, t3
        st   t2, [s0+VY]
        ld   t0, [s0+VX]                ; at most 2.7 pixels per frame
        li   t3, 700
        ble  t0, t3, mb_cap_low
        st   t3, [s0+VX]
mb_cap_low:
        sub  t3, r0, t3
        bge  t0, t3, mb_check
        st   t3, [s0+VX]

mb_check:
        blt  s3, r0, mb_cpu_scores      ; left the screen on the left
        li   t3, 125
        bge  s3, t3, mb_player_scores   ; ... or on the right
        st   s1, [s0+BX]
        pop  lr
        ret
mb_cpu_scores:
        ld   t0, [s0+SCORE_C]
        addi t0, t0, 1
        st   t0, [s0+SCORE_C]
        li   a0, -1                     ; the one who lost the point gets the serve
        j    mb_serve
mb_player_scores:
        ld   t0, [s0+SCORE_P]
        addi t0, t0, 1
        st   t0, [s0+SCORE_P]
        li   a0, 1
mb_serve:
        call serve
        pop  lr
        ret

clamp:                                  ; t0 = paddle position kept between 0 and 96 - PH
        bge  t0, r0, cl_low
        li   t0, 0
cl_low: li   t1, 96 - PH
        ble  t0, t1, cl_done
        mov  t0, t1
cl_done:
        ret
