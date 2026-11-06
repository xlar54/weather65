;=======================================================================================
; lib/keyboard.asm - typed keys from the MEGA65's hardware key queue ($D610, ASCII-like
; codes). Works after #TAKEOVER (the KERNAL's GETIN only reads this same queue). For
; game controls use lib/input.asm (matrix scan: keys held down); use this for typing.
;
;   key_get        A = next key or 0 (Z flag set when none), doesn't wait
;   key_wait       waits for a key, A = key
;   key_flush      empty the queue
; dbg_keys / dbg_klen / dbg_kpos let the xemu_run.py test harness inject a string of keys.
;=======================================================================================

K_RETURN        = $0d
K_DEL           = $14
K_INST          = $94
K_LEFT          = $9d
K_RIGHT         = $1d
K_UP            = $91
K_DOWN          = $11
K_HOME          = $13
K_CLR           = $93
K_STOP          = $03
K_ESC           = $1b
K_TAB           = $09
K_F1            = $f1
K_F3            = $f3
K_F5            = $f5
K_F7            = $f7

dbg_keys:       .fill 16
dbg_klen:       .byte 0
dbg_kpos:       .byte 0

key_get:
        phx
        ldx dbg_kpos
        cpx dbg_klen
        bcs +
        lda dbg_keys,x
        inc dbg_kpos
        plx
        ora #0
        rts
+       lda ASCIIKEY
        beq +
        sta ASCIIKEY                    ; dequeue
        cmp #$ff                        ; the queue can hold $FF: skip it
        bne +
        lda #0
+       plx
        ora #0
        rts

key_wait:
-       jsr key_get
        beq -
        rts

key_flush:
-       jsr key_get
        bne -
        rts
