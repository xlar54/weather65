;=======================================================================================
; lib/draw.asm - drawing into the lib/video_fcm.asm back buffer (column-major FCM).
; Vertical runs are one DMA fill each (destination step 8 walks down a column of
; chars), so filled rectangles and discs are fast; lines and outlines plot pixels.
;
; Arguments: draw_col = colour; draw_x0/draw_y0 (and draw_x1/draw_y1, draw_w/draw_h,
; draw_r) as noted. x is a word (0-319), y a byte (0..FB_H-1). Everything is clipped.
;   draw_plot      pixel at x0,y0
;   draw_vline     x0, y0, height draw_h
;   draw_hline     x0, y0, width draw_w
;   draw_rect      outline of x0,y0,w,h          draw_fill  filled x0,y0,w,h
;   draw_line      x0,y0 to x1,y1 (Bresenham)
;   draw_circle    outline, centre x0,y0, radius draw_r    draw_disc  filled
; For flood fill, polygons, ellipses and gradients see m65-fcm/src (row-major there:
; only its plot/get_pixel address maths needs changing).
;=======================================================================================

draw_col:       .byte 1
draw_x0:        .word 0
draw_y0:        .byte 0
draw_x1:        .word 0
draw_y1:        .byte 0
draw_w:         .word 0
draw_h:         .byte 0
draw_r:         .byte 0

; ptr0 = back buffer address of (x0, y0); carry set when off the buffer
l_draw_addr:
        lda draw_y0
        cmp #FB_H
        bcs l_da_out
        lda draw_x0+1
        beq +
        cmp #1
        bne l_da_out
        lda draw_x0
        cmp #<FB_W
        bcs l_da_out
        lda #32
        bra ++
+       lda #0
+       sta tmp0
        lda draw_x0
        lsr
        lsr
        lsr
        clc
        adc tmp0
        tax                             ; char column
        lda draw_y0                     ; y * 8
        sta tmp4
        lda #0
        sta tmp4+1
        asw tmp4
        asw tmp4
        asw tmp4
        lda draw_x0
        and #7
        ora tmp4
        clc
        adc fbcol_lo,x
        sta ptr0
        lda tmp4+1
        adc fbcol_hi,x
        sta ptr0+1
        ldx back_buf
        clc
        lda ptr0
        adc l_fs_lo16,x
        sta ptr0
        lda ptr0+1
        adc l_fs_hi16,x
        sta ptr0+1
        lda fb_bank
        sta ptr0+2
        lda #0
        sta ptr0+3
        clc
        rts
l_da_out:
        sec
        rts

l_draw_incx:
        inc draw_x0
        bne +
        inc draw_x0+1
+       rts

draw_plot:
        jsr l_draw_addr
        bcs +
        ldz #0
        lda draw_col
        sta [ptr0],z
+       rts

draw_vline:
        lda draw_h
        beq l_dv_out
        lda draw_y0                     ; clip the bottom
        clc
        adc draw_h
        bcs +
        cmp #FB_H + 1
        bcc ++
+       lda #FB_H
        sec
        sbc draw_y0
        bcc l_dv_out
        beq l_dv_out
        sta draw_h
+       jsr l_draw_addr
        bcs l_dv_out
        lda draw_col
        sta l_dv_val
        lda draw_h
        sta l_dv_cnt
        lda ptr0
        sta l_dv_dst
        lda ptr0+1
        sta l_dv_dst+1
        lda ptr0+2
        sta l_dv_dst+2
        #DMA_RUN l_dv_job
l_dv_out:
        rts
l_dv_job:
        .byte DMAOPT_F018B
        .byte DMAOPT_DST_MB, 0
        .byte DMAOPT_DST_STEP_INT, 8
        .byte DMAOPT_END
        .byte DMACMD_FILL
l_dv_cnt:
        .word 0
l_dv_val:
        .word 0
        .byte 0
l_dv_dst:
        .word 0
        .byte 0
        .byte 0
        .word 0

draw_hline:
        lda draw_x0
        pha
        lda draw_x0+1
        pha
        lda draw_w
        sta tmp6
        lda draw_w+1
        sta tmp6+1
-       lda tmp6
        ora tmp6+1
        beq +
        jsr draw_plot
        jsr l_draw_incx
        dew tmp6
        bra -
+       pla
        sta draw_x0+1
        pla
        sta draw_x0
        rts

; filled rectangle: one vertical DMA run per column
draw_fill:
        lda draw_x0
        pha
        lda draw_x0+1
        pha
        lda draw_w
        sta tmp7
        lda draw_w+1
        sta tmp7+1
        lda draw_h
        sta l_df_h
-       lda tmp7
        ora tmp7+1
        beq +
        lda l_df_h
        sta draw_h
        jsr draw_vline
        jsr l_draw_incx
        dew tmp7
        bra -
+       lda l_df_h
        sta draw_h
        pla
        sta draw_x0+1
        pla
        sta draw_x0
        rts
l_df_h:         .byte 0

draw_rect:
        jsr draw_hline                  ; top
        jsr draw_vline                  ; left
        lda draw_y0
        pha
        clc
        adc draw_h
        sec
        sbc #1
        sta draw_y0
        jsr draw_hline                  ; bottom
        pla
        sta draw_y0
        lda draw_x0
        pha
        lda draw_x0+1
        pha
        clc
        lda draw_x0
        adc draw_w
        sta draw_x0
        lda draw_x0+1
        adc draw_w+1
        sta draw_x0+1
        lda draw_x0
        bne +
        dec draw_x0+1
+       dec draw_x0
        jsr draw_vline                  ; right
        pla
        sta draw_x0+1
        pla
        sta draw_x0
        rts

;---------------------------------------------------------------------------------------
; Bresenham line (16-bit x, 8-bit y). Works on copies; x0/y0 end up at x1/y1.
;---------------------------------------------------------------------------------------
draw_line:
        ; dx = |x1 - x0|, sx = sign
        sec
        lda draw_x1
        sbc draw_x0
        sta l_dl_dx
        lda draw_x1+1
        sbc draw_x0+1
        sta l_dl_dx+1
        lda #1
        sta l_dl_sx
        bit l_dl_dx+1
        bpl +
        lda #$ff
        sta l_dl_sx
        sec
        lda #0
        sbc l_dl_dx
        sta l_dl_dx
        lda #0
        sbc l_dl_dx+1
        sta l_dl_dx+1
+       ; dy = -|y1 - y0|, sy = sign
        lda #1
        sta l_dl_sy
        sec
        lda draw_y1
        sbc draw_y0
        bcs +
        eor #$ff
        inc a
        ldx #$ff
        stx l_dl_sy
+       sta tmp0                        ; |dy|
        sec
        lda #0
        sbc tmp0
        sta l_dl_dy
        lda #0
        sbc #0
        sta l_dl_dy+1                   ; dy = -|dy| (16-bit)
        ; err = dx + dy
        clc
        lda l_dl_dx
        adc l_dl_dy
        sta l_dl_err
        lda l_dl_dx+1
        adc l_dl_dy+1
        sta l_dl_err+1
l_dl_loop:
        jsr draw_plot
        lda draw_x0
        cmp draw_x1
        bne +
        lda draw_x0+1
        cmp draw_x1+1
        bne +
        lda draw_y0
        cmp draw_y1
        beq l_dl_done
+       ; e2 = 2 * err
        lda l_dl_err
        asl
        sta tmp4
        lda l_dl_err+1
        rol
        sta tmp4+1
        ; if e2 >= dy: err += dy, x += sx
        sec
        lda tmp4
        sbc l_dl_dy
        lda tmp4+1
        sbc l_dl_dy+1
        bvc +
        eor #$80
+       bmi l_dl_ychk                   ; (a named label: the next "+" is in l_dl_xdec)
        clc
        lda l_dl_err
        adc l_dl_dy
        sta l_dl_err
        lda l_dl_err+1
        adc l_dl_dy+1
        sta l_dl_err+1
        lda l_dl_sx                     ; x += sx
        bmi l_dl_xdec
        jsr l_draw_incx
        bra l_dl_ychk
l_dl_xdec:
        lda draw_x0
        bne +
        dec draw_x0+1
+       dec draw_x0
l_dl_ychk:
        ; if e2 <= dx: err += dx, y += sy
        sec
        lda l_dl_dx
        sbc tmp4
        lda l_dl_dx+1
        sbc tmp4+1
        bvc +
        eor #$80
+       bmi l_dl_loop
        clc
        lda l_dl_err
        adc l_dl_dx
        sta l_dl_err
        lda l_dl_err+1
        adc l_dl_dx+1
        sta l_dl_err+1
        clc
        lda draw_y0
        adc l_dl_sy
        sta draw_y0
        bra l_dl_loop
l_dl_done:
        rts
l_dl_dx:        .word 0
l_dl_dy:        .word 0
l_dl_err:       .word 0
l_dl_sx:        .byte 0
l_dl_sy:        .byte 0

;---------------------------------------------------------------------------------------
; circles (midpoint). draw_disc fills with vertical runs.
;---------------------------------------------------------------------------------------
l_c_cx:         .word 0
l_c_cy:         .byte 0
l_c_x:          .byte 0
l_c_y:          .byte 0
l_c_err:        .word 0
l_c_fill:       .byte 0

draw_circle:
        lda #0
        bra +
draw_disc:
        lda #1
+       sta l_c_fill
        lda draw_x0
        sta l_c_cx
        lda draw_x0+1
        sta l_c_cx+1
        lda draw_y0
        sta l_c_cy
        lda draw_r
        sta l_c_x
        lda #0
        sta l_c_y
        sec                             ; err = 1 - r
        lda #1
        sbc draw_r
        sta l_c_err
        lda #0
        sbc #0
        sta l_c_err+1
l_c_loop:
        lda l_c_x
        cmp l_c_y
        bcc l_c_done
        ; the eight symmetric points (dx, dy) = (x, y) and (y, x)
        lda l_c_x
        ldx l_c_y
        jsr l_c_pair
        lda l_c_y
        ldx l_c_x
        jsr l_c_pair
        inc l_c_y
        bit l_c_err+1
        bmi l_c_inside
        dec l_c_x                       ; err += 2 * (y - x) + 1
        sec
        lda l_c_y
        sbc l_c_x
        sta tmp4
        lda #0
        sbc #0
        sta tmp4+1
        asw tmp4
        bra l_c_add
l_c_inside:                             ; err += 2 * y + 1
        lda l_c_y
        sta tmp4
        lda #0
        sta tmp4+1
        asw tmp4
l_c_add:
        inw tmp4
        clc
        lda l_c_err
        adc tmp4
        sta l_c_err
        lda l_c_err+1
        adc tmp4+1
        sta l_c_err+1
        bra l_c_loop
l_c_done:
        lda l_c_cx                      ; restore the centre
        sta draw_x0
        lda l_c_cx+1
        sta draw_x0+1
        lda l_c_cy
        sta draw_y0
        rts

; A = dx, X = dy: points (cx +- dx, cy +- dy), or vertical runs for a disc
l_c_pair:
        sta tmp2
        stx tmp3
        ; x = cx - dx
        sec
        lda l_c_cx
        sbc tmp2
        sta draw_x0
        lda l_c_cx+1
        sbc #0
        sta draw_x0+1
        jsr l_c_col
        clc
        lda l_c_cx
        adc tmp2
        sta draw_x0
        lda l_c_cx+1
        adc #0
        sta draw_x0+1
l_c_col:
        lda draw_x0+1
        bmi l_c_skip
        sec                             ; y top = cy - dy (clipped at 0)
        lda l_c_cy
        sbc tmp3
        bcs +
        lda #0
+       sta draw_y0
        lda l_c_fill
        beq l_c_dots
        clc                             ; height = bottom - top + 1
        lda l_c_cy
        adc tmp3
        sec
        sbc draw_y0
        inc a
        sta draw_h
        jmp draw_vline
l_c_dots:
        sec
        lda l_c_cy
        sbc tmp3
        bcc +
        jsr draw_plot
+       clc
        lda l_c_cy
        adc tmp3
        bcs l_c_skip
        sta draw_y0
        jmp draw_plot
l_c_skip:
        rts
