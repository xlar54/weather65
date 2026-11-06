;=======================================================================================
; lib/c64gfx.asm - turn C64 graphics into Full Colour data (from mega-dust).
;
;   c64_sprite     ptr0 = 63-byte C64 sprite (32-bit pointer), A = sprite id,
;                  gfx_col = sprite colour (+$80 = multicolour), gfx_mc1/gfx_mc2 = $D025/
;                  $D026. Writes the column-major FCM sprite (lib/blit.asm format) and
;                  its bounding box. Black becomes GFX_BLACK so it stays opaque.
;   c64_charset    ptr0 = C64 charset (256 x 8 bytes), ptr2 = per-char colour table
;                  (bit 3 = multicolour, bits 0-2 colour, like colour RAM), ptr1 = dest
;                  (256 x 64 bytes, row-major 8x8), gfx_bg/gfx_mc1/gfx_mc2 = $D021-$D023
;   c64_koala      ptr0 = Koala picture body (10001 bytes: bitmap, screen, colour, bg)
;                  in chip RAM -> the full-screen picture at FB_PIC (lib/video_fcm.asm
;                  layout, 25 rows per column). Show it with fcm_show_full.
; Needs lib/blit.asm (sprite tables) and lib/video_fcm.asm (FB_PIC) for the first and
; last; all 32-bit pointers are chip RAM.
;=======================================================================================

        .weak
GFX_BLACK       = 16                    ; palette entry used for opaque black
        .endweak

gfx_col:        .byte 1
gfx_mc1:        .byte 15
gfx_mc2:        .byte 11
gfx_bg:         .byte 0
l_gfx_lut:       .fill 4
l_gfx_id:        .byte 0
l_gfx_row:       .byte 0
l_gfx_bits:      .byte 0
l_gfx_y1:        .byte 0

;---------------------------------------------------------------------------------------
c64_sprite:
        sta l_gfx_id
        lda #0
        sta l_gfx_lut
        lda gfx_mc1
        jsr l_gfx_opaque
        sta l_gfx_lut+1
        lda gfx_col
        jsr l_gfx_opaque
        sta l_gfx_lut+2
        sta tmp2                        ; hires colour
        lda gfx_mc2
        jsr l_gfx_opaque
        sta l_gfx_lut+3
        ; expand row-major into l_gfx_rows (24 x 21)
        ldz #0
        lda #0
        sta l_gfx_row
l_cs_row:
        ldx l_gfx_row
        lda l_gfx_r24_lo,x
        clc
        adc #<l_gfx_rows
        sta txt_ptr
        lda l_gfx_r24_hi,x
        adc #>l_gfx_rows
        sta txt_ptr+1
        ldy #0
l_cs_byte:
        lda [ptr0],z
        sta l_gfx_bits
        inz
        bit gfx_col
        bpl l_cs_hires
        ldx #4
-       lda l_gfx_bits
        rol
        rol
        rol
        and #3
        phx
        tax
        lda l_gfx_lut,x
        plx
        sta (txt_ptr),y
        iny
        sta (txt_ptr),y
        iny
        asl l_gfx_bits
        asl l_gfx_bits
        dex
        bne -
        bra l_cs_next
l_cs_hires:
        ldx #8
-       lda #0
        asl l_gfx_bits
        bcc +
        lda tmp2
+       sta (txt_ptr),y
        iny
        dex
        bne -
l_cs_next:
        cpy #24
        bne l_cs_byte
        inc l_gfx_row
        lda l_gfx_row
        cmp #21
        bne l_cs_row
        ; bounding box
        lda #$ff
        sta tmp0
        sta tmp3
        lda #0
        sta tmp1
        sta l_gfx_y1
        sta l_gfx_row
l_cs_brow:
        ldx l_gfx_row
        lda l_gfx_r24_lo,x
        clc
        adc #<l_gfx_rows
        sta txt_ptr
        lda l_gfx_r24_hi,x
        adc #>l_gfx_rows
        sta txt_ptr+1
        ldy #0
l_cs_bcol:
        lda (txt_ptr),y
        beq l_cs_bskip
        cpy tmp0
        bcs +
        sty tmp0
+       cpy tmp1
        bcc +
        sty tmp1
+       lda l_gfx_row
        cmp tmp3
        bcs +
        sta tmp3
+       cmp l_gfx_y1
        bcc l_cs_bskip
        sta l_gfx_y1
l_cs_bskip:
        iny
        cpy #24
        bne l_cs_bcol
        inc l_gfx_row
        lda l_gfx_row
        cmp #21
        bne l_cs_brow
        ldx l_gfx_id
        lda tmp0
        sta spr_x0,x
        lda tmp1
        sta spr_x1,x
        lda tmp3
        sta spr_y0,x
        lda l_gfx_y1
        sta spr_y1,x
        ; transpose: row r -> SPR_BASE + id * 512 + r, destination step 21
        lda #0
        sta l_gfx_row
l_cs_t:
        ldx l_gfx_row
        lda l_gfx_r24_lo,x
        clc
        adc #<l_gfx_rows
        sta l_gfx_tsrc
        lda l_gfx_r24_hi,x
        adc #>l_gfx_rows
        sta l_gfx_tsrc+1
        lda l_gfx_id
        and #$7f
        asl
        sta l_gfx_tdst+1
        lda l_gfx_row
        sta l_gfx_tdst
        lda l_gfx_id
        asl
        lda #0
        rol
        clc
        adc #`SPR_BASE
        sta l_gfx_tdst+2
        #DMA_RUN l_gfx_transpose
        inc l_gfx_row
        lda l_gfx_row
        cmp #21
        bne l_cs_t
        rts

l_gfx_transpose:
        .byte DMAOPT_F018B
        .byte DMAOPT_SRC_MB, 0
        .byte DMAOPT_DST_MB, 0
        .byte DMAOPT_DST_STEP_INT, 21
        .byte DMAOPT_END
        .byte DMACMD_COPY
        .word 24
l_gfx_tsrc:
        .word 0
        .byte 0
l_gfx_tdst:
        .word 0
        .byte 0
        .byte 0
        .word 0

l_gfx_opaque:
        and #15
        bne +
        lda #GFX_BLACK
+       rts

l_gfx_r24_lo:    .byte <(range(21) * 24)
l_gfx_r24_hi:    .byte >(range(21) * 24)
l_gfx_rows:      .fill 24 * 21

;---------------------------------------------------------------------------------------
c64_charset:
        lda gfx_bg
        sta l_gfx_lut
        lda gfx_mc1
        and #15
        sta l_gfx_lut+1
        lda gfx_mc2
        and #15
        sta l_gfx_lut+2
        lda #0
        sta tmp3                        ; char number
l_cc_char:
        ldz tmp3
        lda [ptr2],z
        and #15
        sta tmp2                        ; colour nibble
        and #7
        sta l_gfx_lut+3
        ldy #0                          ; source row
        ldz #0                          ; destination pixel
l_cc_row:
        phz
        tya
        taz
        lda [ptr0],z
        sta tmp0
        plz
        lda tmp2
        and #8
        beq l_cc_hires
        ldx #4
-       lda tmp0
        rol
        rol
        rol
        and #3
        phx
        tax
        lda l_gfx_lut,x
        plx
        sta [ptr1],z
        inz
        sta [ptr1],z
        inz
        asl tmp0
        asl tmp0
        dex
        bne -
        bra l_cc_rowdone
l_cc_hires:
        ldx #8
-       lda gfx_bg
        asl tmp0
        bcc +
        lda tmp2
+       sta [ptr1],z
        inz
        dex
        bne -
l_cc_rowdone:
        iny
        cpy #8
        bne l_cc_row
        clc
        lda ptr0
        adc #8
        sta ptr0
        bcc +
        inc ptr0+1
+       clc
        lda ptr1
        adc #64
        sta ptr1
        bcc +
        inc ptr1+1
        bne +
        inc ptr1+2
+       inc tmp3
        bne l_cc_char
        rts

;---------------------------------------------------------------------------------------
c64_koala:
        ; ptr0 = picture; keep the base in ptr2
        ldx #3
-       lda ptr0,x
        sta ptr2,x
        dex
        bpl -
        ; background colour (+10000)
        clc
        lda ptr2
        adc #<10000
        sta ptr0
        lda ptr2+1
        adc #>10000
        sta ptr0+1
        lda ptr2+2
        adc #0
        sta ptr0+2
        ldz #0
        lda [ptr0],z
        and #15
        sta l_gfx_lut
        lda #0
        sta tmp6                        ; cell index = cy * 40 + cx
        sta tmp6+1
        sta tmp3                        ; cy
l_ck_row:
        lda #0
        sta tmp2                        ; cx
l_ck_cell:
        ; colours: screen (+8000) hi = 01, lo = 10; colour RAM (+9000) = 11
        clc
        lda tmp6
        adc #<8000
        sta tmp4
        lda tmp6+1
        adc #>8000
        sta tmp4+1
        jsr l_ck_src
        ldz #0
        lda [ptr0],z
        pha
        lsr
        lsr
        lsr
        lsr
        sta l_gfx_lut+1
        pla
        and #15
        sta l_gfx_lut+2
        clc
        lda tmp6
        adc #<9000
        sta tmp4
        lda tmp6+1
        adc #>9000
        sta tmp4+1
        jsr l_ck_src
        lda [ptr0],z
        and #15
        sta l_gfx_lut+3
        ; bitmap bytes at index * 8
        lda tmp6
        sta tmp4
        lda tmp6+1
        sta tmp4+1
        asw tmp4
        asw tmp4
        asw tmp4
        jsr l_ck_src
        ; destination: FB_PIC + (cx * 25 + cy) * 64
        ldx tmp2
        lda l_gfx_c25_lo,x
        clc
        adc tmp3
        sta tmp4
        lda l_gfx_c25_hi,x
        adc #0
        sta tmp4+1
        ldx #6
-       asw tmp4
        dex
        bne -
        clc
        lda tmp4
        adc #<FB_PIC
        sta ptr1
        lda tmp4+1
        adc #>FB_PIC
        sta ptr1+1
        lda #`FB_PIC
        adc #0
        sta ptr1+2
        lda #0
        sta ptr1+3
        ldy #0
l_ck_line:
        phy
        tya
        taz
        lda [ptr0],z
        sta l_gfx_bits
        tya
        asl
        asl
        asl
        taz
        ldx #4
-       lda l_gfx_bits
        rol
        rol
        rol
        and #3
        phx
        tax
        lda l_gfx_lut,x
        plx
        sta [ptr1],z
        inz
        sta [ptr1],z
        inz
        asl l_gfx_bits
        asl l_gfx_bits
        dex
        bne -
        ply
        iny
        cpy #8
        bne l_ck_line
        inw tmp6
        inc tmp2
        lda tmp2
        cmp #40
        bne l_ck_cell
        inc tmp3
        lda tmp3
        cmp #25
        beq +
        jmp l_ck_row
+       rts
; ptr0 = ptr2 (picture base) + tmp4
l_ck_src:
        clc
        lda ptr2
        adc tmp4
        sta ptr0
        lda ptr2+1
        adc tmp4+1
        sta ptr0+1
        lda ptr2+2
        adc #0
        sta ptr0+2
        lda #0
        sta ptr0+3
        rts

l_gfx_c25_lo:    .byte <(range(40) * 25)
l_gfx_c25_hi:    .byte >(range(40) * 25)
