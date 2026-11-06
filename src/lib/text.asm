;=======================================================================================
; lib/text.asm - a text console without the KERNAL (from mega-python): 40 or 80
; columns x 25 rows using the ROM character set, scrolling by DMA.
;
;   text_init      A = 40 or 80: set the text mode (clears the screen). After #TAKEOVER;
;                  the font is read from the C65 ROM area (don't overwrite $29800 - e.g.
;                  with sprites - while using it)
;   text_clear     clear to text_colour, cursor home
;   text_goto      X = row, Y = column
;   putc           A = ASCII character (13/10 = new line, 9 = tab); scrolls at the bottom
;   puts           A/X = zero-terminated ASCII string (lo/hi)
;   #PRINT "text"  print an inline string
;   put_hex        A = byte as two hex digits
;   put_dec        A = 0-255 in decimal
;   text_colour    colour (0-15) used for new characters
; Not compatible with lib/video_fcm.asm on screen at the same time (another mode).
;=======================================================================================

        .weak
TEXT_SCREEN     = $0800                 ; 2000 bytes (40 or 80 x 25)
TEXT_FONT       = $29800                ; ROM font with ASCII-friendly lower case
        .endweak

text_colour:    .byte 1
text_cols:      .byte 40
text_row:       .byte 0
text_col:       .byte 0
l_txt_ptr:      .word 0                 ; screen address of the cursor
l_txt_cram:     .dword 0                ; colour RAM address of the cursor

text_init:
        sta text_cols
        lda #$47
        sta VIC4_KEY
        lda #$53
        sta VIC4_KEY
        lda #$80
        trb VIC4_HOTREG
        lda #0
        sta VIC4_CTRL                   ; 8-bit screen codes, no full colour
        lda VIC3_CTRL
        and #%01010111                  ; H320, no ATTR (keep 40 MHz)
        ldx text_cols
        cpx #80
        bne +
        ora #%10000000                  ; H640
+       sta VIC3_CTRL
        lda text_cols
        sta VIC4_LINESTEP
        sta VIC4_CHRCOUNT
        lda #0
        sta VIC4_LINESTEP+1
        lda #25
        sta VIC4_DISPROWS
        lda #<TEXT_SCREEN
        sta VIC4_SCRNPTR
        lda #>TEXT_SCREEN
        sta VIC4_SCRNPTR+1
        lda #`TEXT_SCREEN
        sta VIC4_SCRNPTR+2
        lda #0
        sta VIC4_SCRNPTR+3
        sta VIC4_COLPTR
        sta VIC4_COLPTR+1
        lda #<TEXT_FONT
        sta VIC4_CHARPTR
        lda #>TEXT_FONT
        sta VIC4_CHARPTR+1
        lda #`TEXT_FONT
        sta VIC4_CHARPTR+2
        lda #$50
        sta VIC4_TEXTXPOS
        sta VIC4_SDBDRWD
        lda #0
        sta BORDERCOL
        sta BACKCOL
text_clear:
        lda #<TEXT_SCREEN
        sta tmp4
        lda #>TEXT_SCREEN
        sta tmp4+1
        lda #<2000
        sta tmp5
        lda #>2000
        sta tmp5+1
        lda #32
        ldx #0
        ldy #`TEXT_SCREEN
        jsr dma_fill
        lda #0
        sta tmp4
        sta tmp4+1
        lda text_colour
        ldx #$ff                        ; colour RAM $FF80000
        ldy #$08
        jsr dma_fill
        ldx #0
        ldy #0
text_goto:
        stx text_row
        sty text_col
l_txt_sync:
        lda text_row                    ; offset = row * cols + col
        sta MULTINA
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda text_cols
        sta MULTINB
        clc
        lda MULTOUT
        adc text_col
        sta l_txt_cram
        lda MULTOUT+1
        adc #0
        sta l_txt_cram+1
        clc
        lda l_txt_cram
        adc #<TEXT_SCREEN
        sta l_txt_ptr
        lda l_txt_cram+1
        adc #>TEXT_SCREEN
        sta l_txt_ptr+1
        lda #$f8                        ; $FF8.0000 + offset
        sta l_txt_cram+2
        lda #$0f
        sta l_txt_cram+3
        rts

putc:
        phx
        phy
        phz
        cmp #13
        beq l_txt_nl
        cmp #10
        beq l_txt_nl
        cmp #9
        beq l_txt_tab
        and #$7f
        cmp #32
        bcc l_txt_out
        tax
        lda l_txt_scr,x
        ldx l_txt_ptr
        stx txt_ptr
        ldx l_txt_ptr+1
        stx txt_ptr+1
        ldy #0
        sta (txt_ptr),y
        ldx #3
-       lda l_txt_cram,x
        sta ptr0,x
        dex
        bpl -
        ldz #0
        lda text_colour
        sta [ptr0],z
        inc l_txt_ptr
        bne +
        inc l_txt_ptr+1
+       inc l_txt_cram
        bne +
        inc l_txt_cram+1
+        inc text_col
        lda text_col
        cmp text_cols
        bcc l_txt_out
l_txt_nl:
        jsr l_txt_newline
l_txt_out:
        plz
        ply
        plx
        rts
l_txt_tab:
        lda #32
        jsr putc
        lda text_col
        and #7
        bne l_txt_tab
        bra l_txt_out

l_txt_newline:
        lda #0
        sta text_col
        inc text_row
        lda text_row
        cmp #25
        bcc +
        jsr l_txt_scroll
        lda #24
        sta text_row
+       jmp l_txt_sync

; scroll screen and colour RAM up one line
l_txt_scroll:
        lda text_cols
        sta tmp6
        lda #0
        sta tmp6+1
        ; screen
        clc
        lda #<TEXT_SCREEN
        sta ptr2
        adc tmp6
        sta ptr1
        lda #>TEXT_SCREEN
        sta ptr2+1
        adc #0
        sta ptr1+1
        lda #`TEXT_SCREEN
        sta ptr1+2
        sta ptr2+2
        lda #0
        sta ptr1+3
        sta ptr2+3
        jsr l_txt_movelen
        jsr dma_copy_far
        ; colour RAM ($FF80000)
        lda tmp6
        sta ptr1
        lda #0
        sta ptr1+1
        sta ptr2
        sta ptr2+1
        lda #$f8
        sta ptr1+2
        sta ptr2+2
        lda #$0f
        sta ptr1+3
        sta ptr2+3
        jsr l_txt_movelen
        jsr dma_copy_far
        ; clear the last line
        lda #24
        sta text_row
        lda #0
        sta text_col
        jsr l_txt_sync
        lda l_txt_ptr
        sta tmp4
        lda l_txt_ptr+1
        sta tmp4+1
        lda tmp6
        sta tmp5
        lda #0
        sta tmp5+1
        lda #32
        ldx #0
        ldy #`TEXT_SCREEN
        jsr dma_fill
        lda l_txt_cram
        sta tmp4
        lda l_txt_cram+1
        sta tmp4+1
        lda text_colour
        ldx #$ff
        ldy #$08
        jmp dma_fill
; tmp5 = 24 * cols
l_txt_movelen:
        lda text_cols
        sta MULTINA
        lda #24
        sta MULTINB
        lda #0
        sta MULTINA+1
        sta MULTINB+1
        lda MULTOUT
        sta tmp5
        lda MULTOUT+1
        sta tmp5+1
        rts

puts:
        sta l_txt_s
        stx l_txt_s+1
        ldy #0
-       lda (l_txt_s),y                 ; (indirect through a base-page copy)
        beq +
        jsr putc
        iny
        bne -
        inc l_txt_s+1
        bra -
+       rts
l_txt_s = tmp7

PRINT   .macro a, b="", c="", d=""
        jsr l_puts_inline
        .text \a, \b, \c, \d, 0         ; e.g. #PRINT 13, "score: "
        .endmacro

l_puts_inline:
        pla
        sta tmp7
        pla
        sta tmp7+1
        ldy #1
-       lda (tmp7),y
        beq +
        jsr putc
        iny
        bra -
+       tya
        clc
        adc tmp7
        tax
        lda tmp7+1
        adc #0
        pha
        phx
        rts

put_hex:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr l_txt_hex1
        pla
        and #15
l_txt_hex1:
        cmp #10
        bcc +
        adc #6                          ; 'A' - '0' - 10 - 1 (carry set)
+       adc #'0'
        jmp putc

put_dec:
        ldx #0                          ; hundreds
-       cmp #100
        bcc +
        sbc #100
        inx
        bra -
+       ldy #0                          ; tens
-       cmp #10
        bcc +
        sbc #10
        iny
        bra -
+       pha
        cpx #0
        beq +
        txa
        ora #'0'
        jsr putc
        tya
        ora #'0'
        jsr putc
        bra ++
+       cpy #0
        beq +
        tya
        ora #'0'
        jsr putc
+       pla
        ora #'0'
        jmp putc

; ASCII -> screen code (ROM lower-case set)
l_txt_scr:
        .fill 32, 32
        .byte range(32, 64)
        .byte 0
        .byte range(65, 91)
        .byte 27, 28, 29, 30, 31
        .byte $40
        .byte range(1, 27)
        .byte $5b, $5c, $5d, $5e, $66
