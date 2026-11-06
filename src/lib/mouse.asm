;=======================================================================================
; lib/mouse.asm - 1351-compatible mouse (from deluxepaint65 / mega-simcity).
;
;   mouse_init     centre the pointer, prime the pot baseline
;   mouse_poll     once a frame: mouse_x (0..MOUSE_MAX_X, word), mouse_y (0..MOUSE_MAX_Y),
;                  mouse_buttons (raw), and one-frame edges mouse_left_click /
;                  _release, mouse_right_click / _release (debounced)
;
; The CIA reverses the joystick ports: $DC00 = port 2, $DC01 = port 1. Pots for port 1
; are $D620/$D621, port 2 $D622/$D623, selected with CIA1 PRA bits 7-6. The DDRs are
; flipped, the pots allowed to settle and each read twice. Interrupts are held off
; briefly while sampling. Show the pointer with lib/hwsprite.asm.
;
; Buttons are read on BOTH ports by default (MOUSE_BUTTONS_BOTH): Xemu does not put the
; mouse buttons on the mouse's port but on its joystick-emulation port (port 2 unless
; toggled), so a port-1-only read sees the pointer move but never a click there. On real
; hardware a joystick's fire in the other port then also clicks.
;=======================================================================================

        .weak
MOUSE_PORT      = 1                     ; 1 or 2
MOUSE_MAX_X     = 319
MOUSE_MAX_Y     = 199
MOUSE_INVERT_X  = 0
MOUSE_INVERT_Y  = 1                     ; the 1351's POTY rises as the mouse moves up
MOUSE_MAX_DELTA = 24
MOUSE_BUTTONS_BOTH = 1                  ; buttons from either port (Xemu: see above)
        .endweak

MOUSE_BUTTON_LEFT  = $10
MOUSE_BUTTON_RIGHT = $01                ; the 1351's right button is joystick "up"
        .if MOUSE_PORT == 2
l_mou_potx      = POT_P2X
l_mou_poty      = POT_P2Y
l_mou_select    = $bf                   ; PRA bits 7,6 = %10
l_mou_buttons   = CIA1_PRA
        .else
l_mou_potx      = POT_P1X
l_mou_poty      = POT_P1Y
l_mou_select    = $7f                   ; PRA bits 7,6 = %01
l_mou_buttons   = CIA1_PRB
        .endif

mouse_x:             .word 0
mouse_y:             .byte 0
mouse_buttons:       .byte 0
mouse_left_click:    .byte 0
mouse_left_release:  .byte 0
mouse_right_click:   .byte 0
mouse_right_release: .byte 0
l_mou_ldown:         .byte 0
l_mou_ldeb:          .byte 0
l_mou_rdown:         .byte 0
l_mou_rdeb:          .byte 0
l_mou_oldx:          .byte 0
l_mou_oldy:          .byte 0
l_mou_sx:            .byte 0
l_mou_sy:            .byte 0
l_mou_d:             .byte 0
l_mou_pra:           .byte 0
l_mou_ddra:          .byte 0
l_mou_ddrb:          .byte 0
l_mou_t:             .word 0

mouse_init:
        lda #0
        ldx #l_mou_rdeb - mouse_buttons
-       sta mouse_buttons,x
        dex
        bpl -
        lda #<((MOUSE_MAX_X + 1) / 2)
        sta mouse_x
        lda #>((MOUSE_MAX_X + 1) / 2)
        sta mouse_x+1
        lda #(MOUSE_MAX_Y + 1) / 2
        sta mouse_y
        jsr l_mou_sample
        lda l_mou_sx
        sta l_mou_oldx
        lda l_mou_sy
        sta l_mou_oldy
        rts

mouse_poll:
        lda #0
        sta mouse_left_click
        sta mouse_left_release
        sta mouse_right_click
        sta mouse_right_release
        jsr l_mou_sample
        ; x
        lda l_mou_sx
        ldx l_mou_oldx
        jsr l_mou_delta
        .if MOUSE_INVERT_X
        jsr l_mou_neg
        .endif
        sta l_mou_d
        lda l_mou_sx
        sta l_mou_oldx
        lda l_mou_d
        jsr l_mou_addx
        ; y
        lda l_mou_sy
        ldx l_mou_oldy
        jsr l_mou_delta
        .if MOUSE_INVERT_Y
        jsr l_mou_neg
        .endif
        sta l_mou_d
        lda l_mou_sy
        sta l_mou_oldy
        lda l_mou_d
        jsr l_mou_addy
        ; buttons
        php
        sei
        jsr l_mou_save
        lda #0
        sta CIA1_DDRB
        sta CIA1_DDRA
        ldx #$40
-       dex
        bne -
        lda l_mou_buttons
        .if MOUSE_BUTTONS_BOTH
        and CIA1_PRA                    ; (active low: AND = pressed on either)
        and CIA1_PRB
        .endif
        eor #$ff
        and #MOUSE_BUTTON_LEFT | MOUSE_BUTTON_RIGHT
        sta mouse_buttons
        jsr l_mou_restore
        plp
        ; debounced edges: left
        lda mouse_buttons
        and #MOUSE_BUTTON_LEFT
        beq l_mou_lrel
        lda l_mou_ldeb
        cmp #2
        bcs l_mou_right
        inc l_mou_ldeb
        lda l_mou_ldeb
        cmp #2
        bne l_mou_right
        lda #1
        sta mouse_left_click
        sta l_mou_ldown
        bra l_mou_right
l_mou_lrel:
        lda l_mou_ldown
        beq +
        lda #1
        sta mouse_left_release
+       lda #0
        sta l_mou_ldown
        sta l_mou_ldeb
l_mou_right:
        lda mouse_buttons
        and #MOUSE_BUTTON_RIGHT
        beq l_mou_rrel
        lda l_mou_rdeb
        cmp #2
        bcs l_mou_done
        inc l_mou_rdeb
        lda l_mou_rdeb
        cmp #2
        bne l_mou_done
        lda #1
        sta mouse_right_click
        sta l_mou_rdown
l_mou_done:
        rts
l_mou_rrel:
        lda l_mou_rdown
        beq +
        lda #1
        sta mouse_right_release
+       lda #0
        sta l_mou_rdown
        sta l_mou_rdeb
        rts

; both pots -> l_mou_sx / l_mou_sy (7 bits)
l_mou_sample:
        php
        sei
        jsr l_mou_save
        lda #0
        sta CIA1_DDRB
        sta CIA1_DDRA
        lda CIA1_DDRA                   ; select this port's pots
        ora #%11000000
        sta CIA1_DDRA
        lda #l_mou_select
        sta CIA1_PRA
        ldy #24                         ; let the pots settle
l_mou_settle:
        ldx #0
-       dex
        bne -
        dey
        bne l_mou_settle
        ldy #$20
-       lda l_mou_potx                  ; two equal reads
        cmp l_mou_potx
        beq +
        dey
        bne -
        lda l_mou_oldx
+       and #$7f
        sta l_mou_sx
        ldy #$20
-       lda l_mou_poty
        cmp l_mou_poty
        beq +
        dey
        bne -
        lda l_mou_oldy
+       and #$7f
        sta l_mou_sy
        jsr l_mou_restore
        plp
        rts

l_mou_save:
        lda CIA1_PRA
        sta l_mou_pra
        lda CIA1_DDRA
        sta l_mou_ddra
        lda CIA1_DDRB
        sta l_mou_ddrb
        rts
l_mou_restore:
        lda l_mou_pra
        sta CIA1_PRA
        lda l_mou_ddra
        sta CIA1_DDRA
        lda l_mou_ddrb
        sta CIA1_DDRB
        rts

; A = new, X = old -> A = signed movement ((new - old) mod 128 as -64..63) / 2, clamped
l_mou_delta:
        stx l_mou_t
        sec
        sbc l_mou_t
        clc
        adc #64
        and #$7f
        sec
        sbc #64
        asr a
        cmp #$80
        bcs +
        cmp #MOUSE_MAX_DELTA + 1
        bcc ++
        lda #MOUSE_MAX_DELTA
        rts
+       cmp #256 - MOUSE_MAX_DELTA
        bcs +
        lda #256 - MOUSE_MAX_DELTA
+       rts
l_mou_neg:
        eor #$ff
        inc a
        rts

l_mou_addx:
        ldx #0
        cmp #$80
        bcc +
        ldx #$ff
+       clc
        adc mouse_x
        sta l_mou_t
        txa
        adc mouse_x+1
        sta l_mou_t+1
        bmi l_mou_x0
        cmp #>MOUSE_MAX_X
        bcc l_mou_xok
        bne l_mou_xmax
        lda l_mou_t
        cmp #<MOUSE_MAX_X + 1
        bcc l_mou_xok
l_mou_xmax:
        lda #<MOUSE_MAX_X
        sta mouse_x
        lda #>MOUSE_MAX_X
        sta mouse_x+1
        rts
l_mou_x0:
        lda #0
        sta mouse_x
        sta mouse_x+1
        rts
l_mou_xok:
        lda l_mou_t
        sta mouse_x
        lda l_mou_t+1
        sta mouse_x+1
        rts

l_mou_addy:
        ldx #0
        cmp #$80
        bcc +
        ldx #$ff
+       clc
        adc mouse_y
        sta l_mou_t
        txa
        adc #0
        bmi l_mou_y0
        bne l_mou_ymax
        lda l_mou_t
        cmp #MOUSE_MAX_Y + 1
        bcs l_mou_ymax
        sta mouse_y
        rts
l_mou_ymax:
        lda #MOUSE_MAX_Y
        sta mouse_y
        rts
l_mou_y0:
        lda #0
        sta mouse_y
        rts
