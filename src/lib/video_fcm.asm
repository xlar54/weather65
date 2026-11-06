;=======================================================================================
; lib/video_fcm.asm - 320x200 Full Colour Mode (one byte per pixel = palette index),
; 40 x 25 cells, used as double-buffered framebuffers.
;
; Every cell has its own FCM char (char number = address / 64), allocated column by
; column, so each 8-pixel column of a buffer is one contiguous run:
;     offset(x, y) = (x >> 3) * FB_COL_BYTES + y * 8 + (x & 7)
; Rows 0..FB_ROWS-1 are the double-buffered area; rows FB_ROWS..24 (if any) show a
; static area at FB_STATIC (a HUD), the same in both screens.
;
;   (program code must end below $C800 with the default SCREEN_C)
;   fcm_init         set the mode, build both screen RAMs, clear colour RAM, load the
;                    palette (fcm_palette: 17 entries, C64 colours + black at 16), clear
;                    the buffers. Shows buffer B; buffer A (back_buf 0) is drawn first.
;   fcm_present      ask the IRQ to show the buffer just drawn, wait for it, then make
;                    the other buffer the target (fb_bank). Needs fcm_irq called once a
;                    frame from the IRQ: fcm_init sets irq_hook = fcm_irq if no hook is
;                    set; a project with its own hook must call fcm_irq from it.
;   fcm_irq          does a requested flip (call from the frame IRQ, below row FB_ROWS)
;   fcm_clear        A = colour: fill the back buffer
;   fcm_show_full    one full-screen 40x25 picture at FB_PIC (screen RAM C), e.g. after
;                    c64_koala_to_fcm; fcm_show_game switches back
;   fbcol_lo/hi      column offsets (x >> 3) * FB_COL_BYTES, 41 entries
;
; Palette bytes are written nibble-swapped, as the VIC-IV wants.
;=======================================================================================

        .weak
FB_ROWS         = 25                    ; double-buffered rows (e.g. 20 + a 5-row HUD)
FB0             = $40000                ; buffer A (FB_ROWS * 40 * 64 bytes)
FB1             = $50000                ; buffer B
FB_STATIC       = $4C800                ; static rows below the buffers (if FB_ROWS < 25)
FB_PIC          = $40000                ; full-screen picture (40 x 25 cells)
SCREEN_A        = $0800                 ; three 2000-byte screen RAMs in bank 0
SCREEN_B        = $1000
SCREEN_C        = $C800                 ; (keeps $1800-$1FFF free: lib/kfile.asm)
FB_PALETTE_N    = 17
        .endweak

FB_COL_BYTES    = FB_ROWS * 64
FB_SIZE         = 40 * FB_COL_BYTES
FB_W            = 320
FB_H            = FB_ROWS * 8
FB_STATIC_ROWS  = 25 - FB_ROWS

fcm_init:
        lda #$47
        sta VIC4_KEY
        lda #$53
        sta VIC4_KEY
        lda #$80
        trb VIC4_HOTREG                 ; hot registers off: our layout must stick
        lda VIC_CTRL1                   ; display off while we rebuild. Bit 7 READS the
        and #%01101111                  ;   beam's line bit 8 but WRITES the IRQ compare's:
        ora #(>IRQ_LINE) << 7           ;   copying it back can move the IRQ off-screen
        sta VIC_CTRL1
        lda VIC3_CTRL                   ; H320, V200, no ATTR (keep 40 MHz)
        and #%01010111
        sta VIC3_CTRL
        lda VIC4_CTRL                   ; CHR16 + FCLRHI (keep VFAST)
        and #%01000000
        ora #%00000101
        sta VIC4_CTRL
        lda #80
        sta VIC4_LINESTEP
        lda #0
        sta VIC4_LINESTEP+1
        lda #40
        sta VIC4_CHRCOUNT
        lda #25
        sta VIC4_DISPROWS
        lda #<SCREEN_B
        sta VIC4_SCRNPTR
        lda #>SCREEN_B
        sta VIC4_SCRNPTR+1
        lda #0
        sta VIC4_SCRNPTR+2
        sta VIC4_SCRNPTR+3
        sta VIC4_COLPTR
        sta VIC4_COLPTR+1
        sta $d015                       ; no hardware sprites
        lda #$50                        ; default H640 text position / side border
        sta VIC4_TEXTXPOS
        sta VIC4_SDBDRWD
        jsr l_fcm_screens
        ; colour RAM: 2 bytes per cell, all zero
        lda #<2000
        sta tmp5
        lda #>2000
        sta tmp5+1
        lda #0
        sta tmp4
        sta tmp4+1
        ldx #$ff
        ldy #$08
        jsr dma_fill
        jsr fcm_palette_load
        lda #0
        sta BORDERCOL
        sta BACKCOL
        sta flip_req
        sta back_buf
        jsr fcm_set_target
        lda #0
        jsr fcm_clear
        lda #1
        sta back_buf
        jsr fcm_set_target
        lda #0
        jsr fcm_clear
        lda #0
        sta back_buf
        jsr fcm_set_target
        lda irq_hook+1                  ; no frame hook yet: flips need fcm_irq
        bne +
        lda #<fcm_irq
        sta irq_hook
        lda #>fcm_irq
        sta irq_hook+1
+       lda VIC_CTRL1                   ; display on (bit 7: as above)
        and #%01111111
        ora #%00010000 | (>IRQ_LINE) << 7
        sta VIC_CTRL1
        rts

fcm_palette_load:
        lda #4
        tsb VIC3_ROMBANK                ; colours 0-15 from the RAM palette too
        ldx #0
-       lda fcm_pal_r,x
        sta $d100,x
        lda fcm_pal_g,x
        sta $d200,x
        lda fcm_pal_b,x
        sta $d300,x
        inx
        cpx #FB_PALETTE_N
        bne -
        rts

L_NIBSWAP .function v
        .endf ((v & 15) << 4) | (v >> 4)
        .weak
FCM_PALETTE = [($00,$00,$00), ($ff,$ff,$ff), ($88,$39,$32), ($67,$b6,$bd), ($8b,$3f,$96), ($55,$a0,$49), ($40,$31,$8d), ($bf,$ce,$72), ($8b,$54,$29), ($57,$42,$00), ($b8,$69,$62), ($50,$50,$50), ($78,$78,$78), ($94,$e0,$89), ($78,$69,$c4), ($9f,$9f,$9f), ($00,$00,$00)]
        .endweak
fcm_pal_r:
        .for c in FCM_PALETTE
        .byte L_NIBSWAP(c[0])
        .next
fcm_pal_g:
        .for c in FCM_PALETTE
        .byte L_NIBSWAP(c[1])
        .next
fcm_pal_b:
        .for c in FCM_PALETTE
        .byte L_NIBSWAP(c[2])
        .next

; screen RAMs: A/B rows < FB_ROWS -> buffer chars (base + col * FB_ROWS + row), rows
; >= FB_ROWS -> static chars; C: the full-screen picture (col * 25 + row)
l_fcm_screens:
        lda #<SCREEN_A
        ldx #>SCREEN_A
        ldy #0
        jsr l_fs_game
        lda #<SCREEN_B
        ldx #>SCREEN_B
        ldy #1
        jsr l_fs_game
        lda #<SCREEN_C
        sta ptr0
        lda #>SCREEN_C
        sta ptr0+1
        lda #<(FB_PIC / 64)
        sta tmp4
        lda #>(FB_PIC / 64)
        sta tmp4+1
        lda #25
        sta tmp1
        sta tmp0
        jmp l_fs_rows
l_fs_game:
        sta ptr0
        stx ptr0+1
        lda l_fs_base_lo,y
        sta tmp4
        lda l_fs_base_hi,y
        sta tmp4+1
        lda #FB_ROWS
        sta tmp1
        sta tmp0
        jsr l_fs_rows
        .if FB_STATIC_ROWS > 0
        lda #<(FB_STATIC / 64)
        sta tmp4
        lda #>(FB_STATIC / 64)
        sta tmp4+1
        lda #FB_STATIC_ROWS
        sta tmp1
        sta tmp0
        jmp l_fs_rows
        .else
        rts
        .endif
l_fs_base_lo:    .byte <(FB0 / 64), <(FB1 / 64)
l_fs_base_hi:    .byte >(FB0 / 64), >(FB1 / 64)
; tmp0 rows at ptr0: entry(c, r) = tmp4 + c * tmp1 + r
l_fs_rows:
        lda tmp4
        sta tmp5
        lda tmp4+1
        sta tmp5+1
        ldy #0
-       lda tmp5
        sta (ptr0),y
        iny
        lda tmp5+1
        sta (ptr0),y
        iny
        clc
        lda tmp5
        adc tmp1
        sta tmp5
        bcc +
        inc tmp5+1
+       cpy #80
        bne -
        inw tmp4
        clc
        lda ptr0
        adc #80
        sta ptr0
        bcc +
        inc ptr0+1
+       dec tmp0
        bne l_fs_rows
        rts

fcm_set_target:
        lda back_buf
        bne +
        lda #`FB0
        bra ++
+       lda #`FB1
+       sta fb_bank
        rts

; A = colour: fill the back buffer
fcm_clear:
        pha
        lda back_buf
        tax
        lda l_fs_lo16,x
        sta tmp4
        lda l_fs_hi16,x
        sta tmp4+1
        lda #<FB_SIZE
        sta tmp5
        lda #>FB_SIZE
        sta tmp5+1
        pla
        ldx #0
        ldy fb_bank
        jmp dma_fill
l_fs_lo16:       .byte <FB0, <FB1
l_fs_hi16:       .byte >FB0, >FB1

fcm_present:
        lda back_buf
        clc
        adc #1                          ; buffer 0 -> request 1 (A), 1 -> 2 (B)
        sta flip_req
-       lda flip_req
        bne -
        lda back_buf
        eor #1
        sta back_buf
        jmp fcm_set_target

fcm_irq:
        lda flip_req
        beq +
        cmp #1
        bne l_fi_b
        lda #<SCREEN_A
        sta VIC4_SCRNPTR
        lda #>SCREEN_A
        bra l_fi_set
l_fi_b:  lda #<SCREEN_B
        sta VIC4_SCRNPTR
        lda #>SCREEN_B
l_fi_set:
        sta VIC4_SCRNPTR+1
        lda #0
        sta flip_req
+       rts

fcm_show_full:
        lda #<SCREEN_C
        sta VIC4_SCRNPTR
        lda #>SCREEN_C
        sta VIC4_SCRNPTR+1
        rts

fcm_show_game:
        sei
        lda #0
        sta flip_req
        sta back_buf
        lda #<SCREEN_B
        sta VIC4_SCRNPTR
        lda #>SCREEN_B
        sta VIC4_SCRNPTR+1
        cli
        jmp fcm_set_target

fbcol_lo:       .byte <(range(41) * FB_COL_BYTES)
fbcol_hi:       .byte >(range(41) * FB_COL_BYTES)
