; Video player: plays the black-and-white video in video.bin on the pixel screen.
; Make video.bin with tools/video.py (the format is explained at the top of that file).
;
; Every frame only stores the pixels that change, as runs: skip some pixels, then flip
; some pixels between black and white (XOR 0xFF). Long runs are flipped 4 pixels per
; load/store. After a frame the program shows it and waits for the screen refresh
; (VSYNC) where the next frame is due, so the video runs at its speed on every simulator.

        .equ FB,        0xFFFD0000      ; 128 x 96 pixels, one byte each
        .equ IO,        0xFFFF0000
        .equ FB_SHOW,   0x20
        .equ VSYNC,     0x24            ; counts screen refreshes, 60 per second

        .data
video:  .incbin "video.bin"

        .text
start:  li   sp, 0x00040000
        li   s3, IO
        la   s0, video
        ld   s2, [s0]                   ; number of frames
        ld   t0, [s0+4]
        push t0                         ; screen refreshes per frame, at [sp]
        addi s0, s0, 8                  ; s0 = next byte of the video
        ld   t0, [s3+VSYNC]
        push t0                         ; the refresh this frame belongs to, at [sp]

frame:  li   s1, FB                     ; s1 = current pixel
run:    call number
        add  s1, s1, a0                 ; skip
        call number                     ; flip
        beqz a0, frame_done
        add  t0, s1, a0                 ; t0 = end of the run
        li   t4, -1                     ; XOR with this flips 4 pixels at once

head:   beq  s1, t0, run                ; single pixels until s1 is word aligned
        andi t1, s1, 3
        beqz t1, words
        ldbu t1, [s1]
        xori t1, t1, 0xFF
        stb  t1, [s1]
        addi s1, s1, 1
        j    head
words:  addi t2, t0, -4                 ; 4 pixels per word while at least 4 are left
words_loop:
        bgtu s1, t2, tail
        ld   t1, [s1]
        xor  t1, t1, t4
        st   t1, [s1]
        addi s1, s1, 4
        j    words_loop
tail:   beq  s1, t0, run                ; the last 1 to 3 pixels
        ldbu t1, [s1]
        xori t1, t1, 0xFF
        stb  t1, [s1]
        addi s1, s1, 1
        j    tail

frame_done:
        st   r0, [s3+FB_SHOW]           ; show the frame
        ld   t0, [sp]                   ; wait for the refresh of the next frame
        ld   t1, [sp+4]
        add  t0, t0, t1
wait:   ld   t2, [s3+VSYNC]
        sub  t3, t2, t0
        blt  t3, r0, wait
        st   t0, [sp]
        addi s2, s2, -1
        bnez s2, frame
        halt

number:                                 ; a0 = next LEB128 number from s0 (7 bits per byte)
        li   a0, 0
        li   t2, 0                      ; shift
number_loop:
        ldbu t1, [s0]
        addi s0, s0, 1
        andi t3, t1, 0x7F
        shl  t3, t3, t2
        or   a0, a0, t3
        addi t2, t2, 7
        andi t1, t1, 0x80
        bnez t1, number_loop
        ret
