;=======================================================================================
; lib/fcm_text.asm - 8x8 text drawn into the lib/video_fcm.asm back buffer, at any pixel
; position, in any palette colour, with an optional drop shadow.
;
;   ftext_draw     A/X = zero-terminated string at (ftext_x, ftext_y) in ftext_col; a
;                  drop shadow in ftext_shadow (0 = none). 13 starts a new line (at the
;                  same x, FTEXT_LINE_H lower). Clipped at the right edge.
;   ftext_centre   as ftext_draw, every line centred on x = 160
;   ftext_char     A = one character at (ftext_x, ftext_y); ftext_x += 8
;   ftext_dec      A = 0-255 in decimal
; The font: FTEXT_FONT = 64 glyphs of 8 bytes (1 bit per pixel, bit 7 = left) in C64
; screen-code order; a character is drawn as glyph (code & 63), so upper-case ASCII,
; digits and punctuation work. The C64 upper-case font is at $29000 in the MEGA65 ROM ($29800 is lower case) (copy it out
; before using that area for sprites), or supply your own font.
; Needs lib/video_fcm.asm (fbcol_lo/hi, fb_bank) with 64 KB aligned framebuffers.
;=======================================================================================

        .cerror (FB0 & $ffff) != 0 || (FB1 & $ffff) != 0, "fcm_text.asm needs 64 KB aligned framebuffers"

; ---- text ----
FTEXT_LINE_H    = 9                     ; pixels from one text line to the next

ftext_y:        .byte 0
ftext_col:      .byte 1
ftext_shadow:   .byte 0

; every line (ended by 13 or 0) centred on x = 160
ftext_centre:
        sta ftext_str
        stx ftext_str+1
_line:  ldy #0
-       lda (ftext_str),y                 ; line length
        beq +
        cmp #13
        beq +
        iny
        bne -
+       phy
        tya                             ; x = 160 - len * 4
        asl
        asl
        sta tmp0
        lda #0
        rol
        sta tmp1
        sec
        lda #<160
        sbc tmp0
        sta ftext_x
        lda #>160
        sbc tmp1
        sta ftext_x+1
        jsr l_td_line
        ply
        lda (ftext_str),y
        beq +
        iny                             ; next line
        tya
        clc
        adc ftext_str
        sta ftext_str
        bcc _nl
        inc ftext_str+1
_nl:    lda ftext_y
        clc
        adc #FTEXT_LINE_H
        sta ftext_y
        bra _line
+       rts

; all lines at ftext_x
ftext_draw:
        sta ftext_str
        stx ftext_str+1
        lda ftext_x
        sta l_td_x
        lda ftext_x+1
        sta l_td_x+1
_line:  jsr l_td_line
        lda (ftext_str),y
        beq +
        iny
        tya
        clc
        adc ftext_str
        sta ftext_str
        bcc _nl
        inc ftext_str+1
_nl:    lda l_td_x
        sta ftext_x
        lda l_td_x+1
        sta ftext_x+1
        lda ftext_y
        clc
        adc #FTEXT_LINE_H
        sta ftext_y
        bra _line
+       rts
l_td_x: .word 0

; one line of ftext_str at ftext_x/ftext_y, with its shadow; Y = index of its end (0 or 13)
l_td_line:
        lda ftext_shadow
        beq l_td_run
        ; shadow pass one pixel down and right, then the text itself
        lda ftext_x
        pha
        lda ftext_x+1
        pha
        lda ftext_col
        pha
        lda ftext_shadow
        sta ftext_col
        inc ftext_y
        inw ftext_x
        jsr l_td_run
        dec ftext_y
        pla
        sta ftext_col
        pla
        sta ftext_x+1
        pla
        sta ftext_x
l_td_run:
        ldy #0
-       lda (ftext_str),y
        beq +
        cmp #13
        beq +
        phy
        jsr ftext_char
        ply
        iny
        bne -
+       rts

ftext_dec:
        ldx #0                          ; hundreds, tens, ones -> digits
        stx tmp3                        ; 1 once a digit is out (ftext_char keeps tmp3)
-       cmp #100
        bcc +
        sbc #100
        inx
        bra -
+       pha
        txa
        beq +
        ora #'0'
        jsr ftext_char
        lda #1
        sta tmp3
+       pla
        ldx #0
-       cmp #10
        bcc +
        sbc #10
        inx
        bra -
+       pha
        txa
        bne +
        lda tmp3
        beq ++
+       ora #'0'
        jsr ftext_char
+       pla
        ora #'0'

ftext_char:
        and #63
        sta ftext_glyph
        lda #0
        sta ftext_glyph+1
        asl ftext_glyph
        rol ftext_glyph+1
        asl ftext_glyph
        rol ftext_glyph+1
        asl ftext_glyph
        rol ftext_glyph+1
        clc
        lda ftext_glyph
        adc #<FTEXT_FONT
        sta ftext_glyph
        lda ftext_glyph+1
        adc #>FTEXT_FONT
        sta ftext_glyph+1
        lda ftext_y                       ; tmp4 = y * 8 (rows are 8 bytes apart)
        sta tmp4
        lda #0
        sta tmp4+1
        asw tmp4
        asw tmp4
        asw tmp4
        lda fb_bank
        sta ftext_fb+2
        lda #0
        sta ftext_fb+3
        lda #$80
        sta tmp2                        ; glyph bit of this pixel column
l_tc_col:
        lda ftext_x+1                     ; skip columns at x >= 320
        beq +
        cmp #1
        bne l_tc_next
        lda ftext_x
        cmp #<FB_W
        bcs l_tc_next
        lda #32
        bra ++
+       lda #0
+       sta tmp0
        lda ftext_x
        lsr
        lsr
        lsr
        clc
        adc tmp0
        tax
        lda ftext_x
        and #7
        ora tmp4
        clc
        adc fbcol_lo,x
        sta ftext_fb
        lda tmp4+1
        adc fbcol_hi,x
        sta ftext_fb+1
        ldy #0
        ldz #0
-       lda (ftext_glyph),y
        and tmp2
        beq +
        lda ftext_col
        sta [ftext_fb],z
+       tza
        clc
        adc #8
        taz
        iny
        cpy #8
        bne -
l_tc_next:
        inw ftext_x
        lsr tmp2
        bne l_tc_col
        rts

