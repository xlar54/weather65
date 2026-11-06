;=======================================================================================
; lib/vblit.asm - variable-size DMA sprite blitter into the lib/video_fcm.asm back buffer.
; lib/blit.asm's sprites are all one cell size at SPR_BASE + id * 512; these can be any
; size up to 255 x 255, so a bullet takes a few bytes and a boss one sprite.
;
;   vblit_sprite   draw sprite bs_id with its ANCHOR at (bs_x, bs_y) (16-bit signed),
;                  clipped to x = 0..vb_clip-1 and y = 0..FB_H-1
;   vb_clip        right clip edge (word, default VB_CLIP). Set it to FB_W to draw into an
;                  area outside a narrower playfield, such as a side panel.
;
; Sprite tables, one entry per id (tools/build_assets.py writes them, trimmed to the
; opaque box, so empty rows and columns take no memory or time):
;   vs_lo, vs_hi, vs_bank   address of the column-major pixels (column * h + row), colour 0 =
;                           transparent. A sprite may cross a 64 KB bank.
;   vs_mb                   the address's megabyte: 0 for chip RAM, or attic (for example $81),
;                           which DMA can read too, for sprites that don't fit in chip RAM.
;                           Slower on real hardware, so best for the less common frames
;   vs_w, vs_h              size in pixels
;   vs_ox, vs_oy            signed offset from the anchor to the top-left corner
; Each column is one DMA job (dma_blit: destination step 8, colour 0 transparent).
; Uses tmp0, tmp1, tmp4, tmp5, bsrc, rstart, rcount, dyrow, cxl, bw0 and the multiplier's
; low bytes (MULTINA+1.. and MULTINB+1.. must be 0, as lib/palette.asm leaves them).
;=======================================================================================

        .weak
VB_CLIP         = FB_W
        .endweak

vb_clip:        .word VB_CLIP

vblit_sprite:
        ldx bs_id
        ; ---- cxl = left, tmp4 = top (signed) ----
        clc
        lda bs_x
        adc vs_ox,x
        sta cxl
        ldy #0
        lda vs_ox,x
        bpl +
        dey
+       tya
        adc bs_x+1
        sta cxl+1
        clc
        lda bs_y
        adc vs_oy,x
        sta tmp4
        ldy #0
        lda vs_oy,x
        bpl +
        dey
+       tya
        adc bs_y+1
        sta tmp4+1

        ; ---- vertical clip: rstart rows skipped, rcount rows drawn ----
        lda #0
        sta rstart
        lda tmp4+1
        bmi _top
        bne _out                        ; y >= 256
        lda tmp4
        cmp #FB_H
        bcs _out
        bra _rows
_top:   sec
        lda #0
        sbc tmp4
        sta rstart
        lda #0
        sbc tmp4+1
        bne _out                        ; more than 255 rows above
        lda rstart
        cmp vs_h,x
        bcs _out
        lda #0
        sta tmp4
_rows:  sec
        lda vs_h,x
        sbc rstart
        sta rcount
        clc
        adc tmp4                        ; bottom = top + rows
        bcs _bclip
        cmp #FB_H + 1
        bcc _rows_ok
_bclip: sec
        lda #FB_H
        sbc tmp4
        sta rcount
_rows_ok:

        ; ---- horizontal clip: tmp0 columns skipped, bw0 columns drawn ----
        lda #0
        sta tmp0
        lda cxl+1
        bpl _xpos
        sec
        lda #0
        sbc cxl
        sta tmp0
        lda #0
        sbc cxl+1
        bne _out
        lda tmp0
        cmp vs_w,x
        bcs _out
        lda #0
        sta cxl
        sta cxl+1
        bra _cols
_xpos:  lda cxl+1                       ; x >= clip edge?
        cmp vb_clip+1
        bcc _cols
        bne _out
        lda cxl
        cmp vb_clip
        bcs _out
_cols:  sec
        lda vs_w,x
        sbc tmp0
        sta bw0
        clc                             ; right edge: x + columns - clip > 0 ?
        adc cxl
        sta tmp1
        lda cxl+1
        adc #0
        sta tmp5
        sec
        lda vb_clip
        sbc tmp1
        lda vb_clip+1
        sbc tmp5
        bcs _src                        ; x + columns <= clip
        sec
        lda vb_clip
        sbc cxl
        sta bw0
        bra _src
_out:   rts

        ; ---- source = address + skipped columns * h + skipped rows ----
_src:   lda vs_lo,x
        sta bsrc
        lda vs_hi,x
        sta bsrc+1
        lda vs_bank,x
        sta bsrc+2
        lda vs_mb,x
        sta dmab_src_mb
        lda vs_h,x
        sta tmp1                        ; the source step between columns
        lda tmp0
        beq _nosk
        sta MULTINA
        lda tmp1
        sta MULTINB
        clc
        lda bsrc
        adc MULTOUT
        sta bsrc
        lda bsrc+1
        adc MULTOUT+1
        sta bsrc+1
        bcc _nosk
        inc bsrc+2
_nosk:  clc
        lda bsrc
        adc rstart
        sta bsrc
        bcc +
        inw bsrc+1
+
        ; ---- destination = column base + y * 8 + (x & 7) ----
        lda tmp4
        sta dyrow
        lda #0
        sta dyrow+1
        asw dyrow
        asw dyrow
        asw dyrow
        lda cxl+1
        lsr
        lda cxl
        ror
        lsr
        lsr
        tay                             ; char column
        lda cxl
        and #7
        sta tmp0                        ; the phase inside the char
        clc
        adc dyrow
        adc fbcol_lo,y
        sta tmp5
        lda dyrow+1
        adc fbcol_hi,y
        sta tmp5+1

        lda fb_bank
        sta dmab_dst_bank
        lda rcount
        sta dmab_count
        lda #0
        sta dmab_count+1
_col:   lda tmp5
        sta dmab_dst
        lda tmp5+1
        sta dmab_dst+1
        lda bsrc
        sta dmab_src
        lda bsrc+1
        sta dmab_src+1
        lda bsrc+2
        sta dmab_src_bank
        #DMA_RUN dma_blit
        dec bw0
        beq _done
        clc
        lda bsrc
        adc tmp1
        sta bsrc
        bcc +
        inw bsrc+1
+       inc tmp0
        lda tmp0
        cmp #8
        beq _wrap
        inw tmp5
        bra _col
_wrap:  lda #0                          ; next char column
        sta tmp0
        clc
        lda tmp5
        adc #<(FB_COL_BYTES - 7)
        sta tmp5
        lda tmp5+1
        adc #>(FB_COL_BYTES - 7)
        sta tmp5+1
        bra _col
_done:  rts
