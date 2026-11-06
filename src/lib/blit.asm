;=======================================================================================
; lib/blit.asm - DMA sprite blitter into the lib/video_fcm.asm back buffer.
;
;   blit_sprite   draw sprite bs_id with its top-left at (bs_x, bs_y) (16-bit signed,
;                 framebuffer pixels), clipped to the buffer
;   spr_x0/x1/y0/y1  per sprite opaque bounding box (fill them when making sprites, e.g.
;                 lib/c64gfx.asm does; also handy as hit boxes). x1 < x0 = empty sprite.
;
; Sprite format (SPR_W x SPR_H, default 24 x 21): Full Colour, column-major
; (column * SPR_H + row), at SPR_BASE + id * 512 (up to 256 sprites = 128 KB from a
; 64 KB-aligned SPR_BASE), colour 0 = transparent. Each sprite column is one DMA job:
; source step 1, destination step 8 (the next pixel row inside a column of chars),
; colour 0 transparent. spr_x0/x1/y0/y1 hold each sprite's opaque bounding box, so
; empty columns and rows cost nothing - and the same boxes are the hit boxes.
;=======================================================================================

        .weak
SPR_BASE        = $20000                ; ROM area: unprotect it first (hypervisor $70)
SPR_W           = 24
SPR_H           = 21
SPR_STRIDE      = 512
        .endweak
        .cerror SPR_STRIDE != 512 || (SPR_BASE & $ffff) != 0, "blit.asm addresses sprites as SPR_BASE + id * 512"

spr_x0:         .fill 256
spr_x1:         .fill 256
spr_y0:         .fill 256
spr_y1:         .fill 256


;---------------------------------------------------------------------------------------
; blit_sprite - draw sprite bs_id at framebuffer position (bs_x, bs_y) (16-bit signed,
;               the sprite's top-left corner).
;---------------------------------------------------------------------------------------
blit_sprite:
        ldx bs_id
        lda spr_x1,x
        cmp spr_x0,x
        bcs +
        rts                             ; empty sprite
+
        ; ---- vertical clip: top = y + y0, bottom = y + y1 ----
        clc
        lda bs_y
        adc spr_y0,x
        sta tmp4
        lda bs_y+1
        adc #0
        sta tmp4+1                      ; tmp4 = top (signed)
        clc
        lda bs_y
        adc spr_y1,x
        sta tmp5
        lda bs_y+1
        adc #0
        sta tmp5+1                      ; tmp5 = bottom (signed)
        bmi l_bs_out                     ; bottom above the playfield
        lda tmp4+1
        bmi l_bs_topclip
        bne l_bs_out                     ; top >= 256
        lda tmp4
        cmp #FB_H
        bcs l_bs_out
        lda spr_y0,x
        sta rstart
        bra l_bs_bot
l_bs_topclip:
        ; rows hidden above: -top
        sec
        lda #0
        sbc tmp4
        clc
        adc spr_y0,x
        sta rstart
        lda #0
        sta tmp4
        sta tmp4+1
l_bs_bot:
        lda tmp5+1
        bne l_bs_botclip
        lda tmp5
        cmp #FB_H
        bcc +
l_bs_botclip:
        lda #FB_H - 1
        sta tmp5
+       sec
        lda tmp5
        sbc tmp4
        bcc l_bs_out
        inc a
        sta rcount
        ; dyrow = top * 8
        lda tmp4
        sta dyrow
        lda #0
        sta dyrow+1
        asw dyrow
        asw dyrow
        asw dyrow

        ; ---- source: sprite base + x0 * 21 + rstart ----
        txa
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc #`SPR_BASE
        sta bsrc+2
        txa
        and #$7f
        asl
        sta bsrc+1
        lda #0
        sta bsrc
        ldy spr_x0,x
        lda col21,y
        clc
        adc rstart
        sta bsrc
        lda col21h,y
        adc bsrc+1
        sta bsrc+1

        lda #0                          ; (lib/vblit.asm may have left another source)
        sta dmab_src_mb
        lda fb_bank
        sta dmab_dst_bank
        lda rcount
        sta dmab_count
        lda #0
        sta dmab_count+1

        ; ---- column loop: cxl = x + col ----
        clc
        lda bs_x
        adc spr_x0,x
        sta cxl
        lda bs_x+1
        adc #0
        sta cxl+1
        lda spr_x1,x
        sec
        sbc spr_x0,x
        inc a
        sta bw0                         ; columns to draw
l_bs_col:
        lda cxl+1
        beq +                           ; 0..255
        cmp #1
        bne l_bs_next                    ; x < 0 or x >= 512
        lda cxl
        cmp #<FB_W                      ; 256..319
        bcs l_bs_next
        lda #32
        bra ++
+       lda #0
+       sta tmp0                        ; char column offset for x >= 256
        lda cxl
        lsr
        lsr
        lsr
        clc
        adc tmp0
        tay
        lda cxl
        and #7
        ora dyrow
        clc
        adc fbcol_lo,y
        sta dmab_dst
        lda dyrow+1
        adc fbcol_hi,y
        sta dmab_dst+1
        lda bsrc
        sta dmab_src
        lda bsrc+1
        sta dmab_src+1
        lda bsrc+2
        sta dmab_src_bank
        #DMA_RUN dma_blit
l_bs_next:
        clc
        lda bsrc
        adc #SPR_H
        sta bsrc
        bcc +
        inc bsrc+1
+       inw cxl
        dec bw0
        bne l_bs_col
l_bs_out:
        rts

col21:          .byte <(range(SPR_W) * SPR_H)
col21h:         .byte >(range(SPR_W) * SPR_H)
