;=======================================================================================
; lib/palette.asm - palette brightness and fades (the scaling from little-mega-people).
;
;   pal_set_level  A = brightness 0 (black) .. 255 (full): writes entries 0..pal_count-1
;                  scaled from the master table pal_src_r/g/b (8-bit values)
;   pal_fade_out   fade to black over A frames (blocks; needs lib/system wait_frame)
;   pal_fade_in    fade up from black over A frames
;   pal_set        X = entry, A/Y/Z = red/green/blue (8-bit) - writes the hardware
;                  entry directly (nibble-swapped as the VIC-IV wants)
; The master table: set pal_src (pointer to 3 tables of 256: r, g, b) and pal_count.
; By default it points at lib/video_fcm.asm's palette (FB_PALETTE_N entries).
;=======================================================================================

pal_count:      .byte FB_PALETTE_N
pal_src:        .word l_pal_default     ; r table; g = +256, b = +512
pal_level:      .byte 255

pal_set:
        jsr l_pal_swap
        sta $d100,x
        tya
        jsr l_pal_swap
        sta $d200,x
        tza
        jsr l_pal_swap
        sta $d300,x
        rts

pal_set_level:
        sta pal_level
        lda #4
        tsb VIC3_ROMBANK                ; colours 0-15 from the RAM palette
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda pal_level
        sta MULTINB
        lda pal_src
        sta txt_ptr
        lda pal_src+1
        sta txt_ptr+1
        ldy #0
-       lda (txt_ptr),y                 ; red
        jsr l_pal_scale
        sta $d100,y
        inc txt_ptr+1
        lda (txt_ptr),y                 ; green
        jsr l_pal_scale
        sta $d200,y
        inc txt_ptr+1
        lda (txt_ptr),y                 ; blue
        jsr l_pal_scale
        sta $d300,y
        dec txt_ptr+1
        dec txt_ptr+1
        iny
        cpy pal_count
        bne -
        rts
; A * pal_level / 256, nibble-swapped
l_pal_scale:
        sta MULTINA
        lda MULTOUT+1
l_pal_swap:
        sta tmp0
        asl
        asl
        asl
        asl
        sta tmp1
        lda tmp0
        lsr
        lsr
        lsr
        lsr
        ora tmp1
        rts

pal_fade_out:
        jsr l_pal_step
-       jsr wait_frame
        sec
        lda pal_level
        sbc tmp6
        bcs +
        lda #0
+       jsr pal_set_level
        lda pal_level
        bne -
        rts

pal_fade_in:
        jsr l_pal_step
        lda #0
        jsr pal_set_level
-       jsr wait_frame
        clc
        lda pal_level
        adc tmp6
        bcc +
        lda #255
+       jsr pal_set_level
        lda pal_level
        cmp #255
        bne -
        rts
; tmp6 = 255 / frames (at least 1)
l_pal_step:
        sta tmp4
        lda #0
        sta tmp4+1
        tax
-       inx
        clc
        adc tmp4
        bcc -
        stx tmp6                        ; ~255 / frames
        rts

; the default master palette: lib/video_fcm.asm's FCM_PALETTE, unswapped
l_pal_default:
        .for c in FCM_PALETTE
        .byte c[0]
        .next
        .fill 256 - len(FCM_PALETTE)
        .for c in FCM_PALETTE
        .byte c[1]
        .next
        .fill 256 - len(FCM_PALETTE)
        .for c in FCM_PALETTE
        .byte c[2]
        .next
        .fill 256 - len(FCM_PALETTE)
