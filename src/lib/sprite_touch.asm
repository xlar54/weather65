;=======================================================================================
; lib/sprite_touch.asm - pixel-exact collision of two lib/blit.asm sprites, like the
; C64's hardware sprite collisions (from archon65).
;
;   sprite_touch   carry set when an opaque pixel of sprite touch_a lies on an opaque
;                  pixel of sprite touch_b, B's top-left being touch_dx / touch_dy pixels
;                  (signed, -64..63) from A's. Only the overlap of the two bounding boxes
;                  (spr_x0..spr_y1) is read. Keeps X and Y; uses ptr1, ptr2, Z (left 0).
; Test the boxes (or the distance) first: it is cheap to reject sprites that are far
; apart, and the offsets must fit in a signed byte.
;=======================================================================================

touch_a:           .byte 0
touch_b:           .byte 0
touch_dx:          .byte 0
touch_dy:          .byte 0
L_ST_BIAS         = 64                    ; local coordinates + 64: signed becomes unsigned

sprite_touch:
        phx
        phy
        ldx touch_a
        ldy touch_b
        ; columns, in A's coordinates: max(ax0, dx + bx0) .. min(ax1, dx + bx1)
        lda spr_x0,x
        clc
        adc #L_ST_BIAS
        sta l_st_x0
        lda spr_x0,y
        clc
        adc touch_dx
        clc
        adc #L_ST_BIAS
        cmp l_st_x0
        bcc +
        sta l_st_x0
+       lda spr_x1,x
        clc
        adc #L_ST_BIAS
        sta l_st_x1
        lda spr_x1,y
        clc
        adc touch_dx
        clc
        adc #L_ST_BIAS
        cmp l_st_x1
        bcs +
        sta l_st_x1
+       ; rows the same way
        lda spr_y0,x
        clc
        adc #L_ST_BIAS
        sta l_st_y0
        lda spr_y0,y
        clc
        adc touch_dy
        clc
        adc #L_ST_BIAS
        cmp l_st_y0
        bcc +
        sta l_st_y0
+       lda spr_y1,x
        clc
        adc #L_ST_BIAS
        sta l_st_y1
        lda spr_y1,y
        clc
        adc touch_dy
        clc
        adc #L_ST_BIAS
        cmp l_st_y1
        bcs +
        sta l_st_y1
+       lda l_st_x1                     ; no overlap?
        cmp l_st_x0
        bcc _miss
        lda l_st_y1
        cmp l_st_y0
        bcc _miss
        lda touch_a
        jsr l_st_addr
        sta l_st_base_a
        stx l_st_base_a+1
        lda touch_b
        jsr l_st_addr
        sta l_st_base_b
        stx l_st_base_b+1
        lda l_st_x0
        sta l_st_c
_col:   ; A's column c - 64 and B's column c - 64 - dx: ptr1 / ptr2 = their tops
        lda l_st_c
        sec
        sbc #L_ST_BIAS
        tay
        lda col21,y
        sta ptr1
        lda col21h,y
        clc
        adc l_st_base_a
        sta ptr1+1
        lda l_st_base_a+1
        sta ptr1+2
        lda l_st_c
        sec
        sbc #L_ST_BIAS
        sec
        sbc touch_dx
        tay
        lda col21,y
        sta ptr2
        lda col21h,y
        clc
        adc l_st_base_b
        sta ptr2+1
        lda l_st_base_b+1
        sta ptr2+2
        lda #0
        sta ptr1+3
        sta ptr2+3
        lda l_st_y0
        sta l_st_r
_row:   lda l_st_r                      ; A's row
        sec
        sbc #L_ST_BIAS
        taz
        lda [ptr1],z
        beq _next
        tza                             ; B's row = A's row - dy
        sec
        sbc touch_dy
        taz
        lda [ptr2],z
        bne _hit
_next:  lda l_st_r
        cmp l_st_y1
        beq _ncol
        inc l_st_r
        bra _row
_ncol:  lda l_st_c
        cmp l_st_x1
        beq _miss
        inc l_st_c
        bra _col
_hit:   ldz #0
        ply
        plx
        sec
        rts
_miss:  ldz #0
        ply
        plx
        clc
        rts
l_st_x0:        .byte 0
l_st_x1:        .byte 0
l_st_y0:        .byte 0
l_st_y1:        .byte 0
l_st_c:         .byte 0
l_st_r:         .byte 0
l_st_base_a:    .word 0                 ; address bits 8-15, 16-23 (bits 0-7 are 0)
l_st_base_b:    .word 0
; A = sprite id -> A = address bits 8-15, X = bits 16-23 of SPR_BASE + id * 512
l_st_addr:
        pha
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc #`SPR_BASE
        tax
        pla
        and #$7f
        asl
        rts

