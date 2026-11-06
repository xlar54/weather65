;=======================================================================================
; lib/input.asm - joysticks in either port, plus keyboard. Call read_input once a frame.
;   joy = held, joy_new = pressed since the last call (lib/zp.asm), key_extra/key_new
;   for non-joystick keys. dbg_joy is OR'd in (the xemu_run.py test harness can poke it).
;   cursor keys / W A S D move, SPACE or RETURN fires, RUN/STOP pauses
; joy bits (1 = pressed): 0 up, 1 down, 2 left, 3 right, 4 fire
; The sources are also kept apart, for two-player games: joy_port1, joy_port2, joy_keys
; (held, same bits; dbg_joy goes into joy_keys).
;
; On the C64-compatible matrix the MEGA65's cursor-left/up keys arrive as
; SHIFT + cursor-right/down, so shift decides the direction.
;=======================================================================================
JOY_UP          = $01
JOY_DOWN        = $02
JOY_LEFT        = $04
JOY_RIGHT       = $08
JOY_FIRE        = $10

KEY_STOP        = $02

read_input:
        lda joy
        sta joy_prev
        ; ---- joysticks ----
        lda #$ff
        sta CIA1_PRA
        lda CIA1_PRA                    ; port 2
        eor #$ff
        and #$1f
        sta joy_port2
        lda CIA1_PRB                    ; port 1
        eor #$ff
        and #$1f
        sta joy_port1
        lda #0
        sta tmp0                        ; keyboard bits
        ; ---- keyboard ----
        lda #0
        sta key_extra
        lda #%11111110                  ; column 0: CRSR right (bit2), CRSR down (bit7), RETURN (bit1)
        jsr l_scan
        sta tmp1
        lda #%10111111                  ; column 6: right shift (bit4)
        jsr l_scan
        and #$10
        sta tmp2
        lda #%11111101                  ; column 1: left shift (bit7), W (1), A (2), S (5)
        jsr l_scan
        sta tmp3
        and #$80
        ora tmp2
        sta tmp2                        ; nonzero = a shift key is down
        lda tmp1
        and #$04                        ; CRSR right/left
        beq +
        lda tmp2
        beq l_right
        lda #JOY_LEFT
        bra l_or1
l_right: lda #JOY_RIGHT
l_or1:   tsb tmp0
+       lda tmp1
        and #$80                        ; CRSR down/up
        beq +
        lda tmp2
        beq l_down
        lda #JOY_UP
        bra l_or2
l_down:  lda #JOY_DOWN
l_or2:   tsb tmp0
+       lda tmp1
        and #$02                        ; RETURN
        beq +
        lda #JOY_FIRE
        tsb tmp0
+       lda tmp3
        and #$02                        ; W
        beq +
        lda #JOY_UP
        tsb tmp0
+       lda tmp3
        and #$04                        ; A
        beq +
        lda #JOY_LEFT
        tsb tmp0
+       lda tmp3
        and #$20                        ; S
        beq +
        lda #JOY_DOWN
        tsb tmp0
+       lda #%11111011                  ; column 2: D (bit2)
        jsr l_scan
        and #$04
        beq +
        lda #JOY_RIGHT
        tsb tmp0
+       lda #%01111111                  ; column 7: SPACE (bit4), RUN/STOP (bit7)
        jsr l_scan
        sta tmp1
        and #$10
        beq +
        lda #JOY_FIRE
        tsb tmp0
+       lda tmp1
        and #$80
        beq +
        lda #KEY_STOP
        tsb key_extra
+       lda #$ff
        sta CIA1_PRA
        lda tmp0
        ora dbg_joy
        sta joy_keys
        ora joy_port1
        ora joy_port2
        sta joy
        lda joy_prev
        eor #$ff
        and joy
        sta joy_new
        lda key_extra
        and key_prev_inv
        sta key_new
        lda key_extra
        eor #$ff
        sta key_prev_inv
        rts

; select one keyboard column (A = column mask) and return pressed rows as 1 bits
l_scan:
        sta CIA1_PRA
        ldx #8
-       dex                             ; let the matrix settle at 40 MHz
        bne -
        lda CIA1_PRB
        eor #$ff
        rts

joy_port1:      .byte 0
joy_port2:      .byte 0
joy_keys:       .byte 0
key_extra:      .byte 0
key_new:        .byte 0
key_prev_inv:   .byte $ff
dbg_joy:        .byte 0                 ; injected by the test harness
