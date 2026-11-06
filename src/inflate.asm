;=======================================================================================
; inflate.asm - PNG container + DEFLATE (RFC 1951), in the style of zlib's "puff": a canonical
; Huffman decoder that walks the code one bit at a time. Slow per symbol, small in code; at
; 40 MHz a 9 KB image takes well under a second.
;
;   png_decode     the PNG in the attic body (bp..bp_end) -> pixels at INFLATE_ATTIC:
;                  200 rows of (filter byte + 320 bytes), plus png_remap (palette index ->
;                  radar colour, 0 = transparent). Carry set on failure, net_err says why.
;
; Only what the radar needs: 8-bit paletted, 320 x 200, not interlaced, filter 0 on every
; row (filter is checked). Any output is verified against the zlib Adler-32, so a corrupt
; download is noticed and doesn't reach the screen.
;=======================================================================================

INFLATE_ATTIC   = $8400000
PNG_W           = 320
PNG_H           = 200
PNG_ROW         = PNG_W + 1
PNG_RAW         = PNG_ROW * PNG_H

png_remap:      .fill 256               ; palette index -> radar colour; 0 = see-through
png_chunk:      .word 0                 ; IDAT bytes left in this chunk
png_failed:     .byte 0
out_left:       .word 0                 ; 16 bits are enough: PNG_RAW < 65536
i_sym:          .word 0
i_len:          .word 0
i_dist:         .word 0
i_final:        .byte 0
i_type:         .byte 0
i_nlen:         .word 0
i_ndist:        .word 0
i_ncode:        .byte 0
i_n:            .word 0
i_tmp:          .byte 0
i_rep:          .byte 0
i_prev:         .byte 0
ad_a:           .word 0
ad_b:           .word 0
ad_file:        .fill 4
dbg_adler:      .fill 4

; ---- reading the chunked stream ----
; carry set at the end of the data
body_get:
        lda bp+2                        ; compare 24 bits against the end
        cmp bp_end+2
        bne _more
        lda bp+1
        cmp bp_end+1
        bne _more
        lda bp
        cmp bp_end
        bne _more
        lda #0
        sec
        rts
_more:  ldz #0
        lda [bp],z
        inc bp
        bne +
        inc bp+1
        bne +
        inc bp+2
+       clc
        rts

png_be32:                               ; a 32-bit big-endian length -> tmp6 (low 16 bits)
        jsr body_get
        jsr body_get
        jsr body_get
        sta tmp6+1
        jsr body_get
        sta tmp6
        rts

png_skip_tmp6:
        lda tmp6
        ora tmp6+1
        beq _o
-       jsr body_get
        bcs _o
        lda tmp6
        bne +
        dec tmp6+1
+       dec tmp6
        lda tmp6
        ora tmp6+1
        bne -
_o:     rts

; the next byte of the zlib stream, moving through IDAT chunks. On running out it sets
; png_failed and returns 0: the decoder then stops at its next check.
png_stream_byte:
        lda png_chunk
        ora png_chunk+1
        bne _have
        jsr body_get                    ; the CRC
        jsr body_get
        jsr body_get
        jsr body_get
        jsr png_be32
        lda tmp6
        sta png_chunk
        lda tmp6+1
        sta png_chunk+1
        jsr body_get                    ; type
        sta i_tmp
        jsr body_get
        jsr body_get
        jsr body_get
        bcs _dead
        lda i_tmp
        cmp #'I'
        bne _dead
        lda png_chunk
        ora png_chunk+1
        beq png_stream_byte
_have:  lda png_chunk
        bne +
        dec png_chunk+1
+       dec png_chunk
        jsr body_get
        bcs _dead
        rts
_dead:  lda #1
        sta png_failed
        lda #0
        sta png_chunk
        sta png_chunk+1
        rts

; ---- the PNG wrapper ----
png_decode:
        lda #0
        sta png_failed
        ldx #0
-       jsr body_get
        cmp png_sig,x
        bne _badpng
        inx
        cpx #8
        bne -
        ; every colour opaque unless tRNS says otherwise
        ldx #0
        lda #255
-       sta pal_a,x
        inx
        bne -
_chunks:
        jsr png_be32
        lda tmp6
        sta tmp7
        lda tmp6+1
        sta tmp7+1
        jsr body_get
        sta ptype
        jsr body_get
        sta ptype+1
        jsr body_get
        sta ptype+2
        jsr body_get
        sta ptype+3
        bcs _badpng
        lda ptype
        cmp #'I'
        bne _notI
        lda ptype+1
        cmp #'H'
        beq _ihdr
        cmp #'D'
        beq _idat
        bra _badpng                     ; IEND before any data
_notI:  cmp #'P'
        beq _plte
        cmp #'t'
        beq _trns
_skip:  lda tmp7
        sta tmp6
        lda tmp7+1
        sta tmp6+1
_skipn: jsr png_skip_tmp6               ; rest of the chunk
        jsr body_get                    ; CRC
        jsr body_get
        jsr body_get
        jsr body_get
        bcc _chunks
_badpng:
        lda #E_PNG
        sta net_err
        sec
        rts
_ihdr:  jsr png_be32                    ; width
        lda tmp6
        cmp #<PNG_W
        bne _badpng
        lda tmp6+1
        cmp #>PNG_W
        bne _badpng
        jsr png_be32                    ; height
        lda tmp6
        cmp #PNG_H
        bne _badpng
        jsr body_get                    ; bit depth
        cmp #8
        bne _badpng
        jsr body_get                    ; colour type: paletted
        cmp #3
        bne _badpng
        jsr body_get                    ; compression
        jsr body_get                    ; filter method
        jsr body_get                    ; interlace
        cmp #0
        bne _badpng
        lda #0
        sta tmp6
        sta tmp6+1
        bra _skipn
_plte:  ldx #0
        lda tmp7+1                      ; length / 3 entries, at most 256
        sta tmp6+1
        lda tmp7
        sta tmp6
_pl:    lda tmp6
        ora tmp6+1
        beq _pldone
        jsr body_get
        sta pal_r,x
        jsr body_get
        sta pal_g,x
        jsr body_get
        sta pal_b,x
        lda tmp6
        sec
        sbc #3
        sta tmp6
        bcs +
        dec tmp6+1
+       inx
        bne _pl
_pldone:
        stx pal_n
        lda #0
        sta tmp6
        sta tmp6+1
        jmp _skipn
_trns:  ldx #0
_tr:    lda tmp7
        ora tmp7+1
        beq _trdone
        jsr body_get
        sta pal_a,x
        lda tmp7
        bne +
        dec tmp7+1
+       dec tmp7
        inx
        bne _tr
_trdone:
        lda #0
        sta tmp6
        sta tmp6+1
        jmp _skipn
_idat:  lda tmp7
        sta png_chunk
        lda tmp7+1
        sta png_chunk+1
        jsr inflate
        bcs _o
        jsr png_verify
        bcs _o
        jsr png_build_remap
        clc
_o:     rts

png_sig:  .byte $89, 'P', 'N', 'G', 13, 10, 26, 10

; each palette entry -> the nearest radar colour by |dr| + |dg| + |db|
png_build_remap:
        lda #0
        sta tmp0                        ; entry
_ent:   ldx tmp0
        lda pal_a,x
        cmp #128
        bcc _hide
        jsr png_clear_air
        bcc +
_hide:  ldx tmp0
        lda #0
        sta png_remap,x
        jmp _next
+       lda #$ff
        sta tmp4
        sta tmp4+1                      ; best
        lda #0
        sta tmp1                        ; candidate
_cand:  ldy tmp1
        ldx tmp0
        lda pal_r,x
        sec
        sbc radar_r,y
        bcs +
        eor #$ff
        adc #1
+       sta tmp5
        lda #0
        sta tmp5+1
        lda pal_g,x
        sec
        sbc radar_g,y
        bcs +
        eor #$ff
        adc #1
+       clc
        adc tmp5
        sta tmp5
        bcc +
        inc tmp5+1
+       lda pal_b,x
        sec
        sbc radar_b,y
        bcs +
        eor #$ff
        adc #1
+       clc
        adc tmp5
        sta tmp5
        bcc +
        inc tmp5+1
+       lda tmp5+1
        cmp tmp4+1
        bcc _best
        bne _notb
        lda tmp5
        cmp tmp4
        bcs _notb
_best:  lda tmp5
        sta tmp4
        lda tmp5+1
        sta tmp4+1
        lda tmp1
        sta tmp2
_notb:  inc tmp1
        lda tmp1
        cmp #RADAR_COLOURS
        bne _cand
        lda tmp2
        clc
        adc #RADAR_BASE
        ldx tmp0
        sta png_remap,x
_next:  inc tmp0
        bne _ent
        rts

; IEM paints the returns under 5 dBZ (clear air, ground clutter) in pale blue-greys, which
; aren't precipitation. Those have green >= red, low saturation and aren't bright. Carry
; set = hide this entry. Keeps the 70 dBZ purple (red > green) and the 75 dBZ white.
png_clear_air:
        ldx tmp0
        lda pal_g,x
        cmp pal_r,x
        bcc _keep                       ; red > green
        ; here r <= g: min is r or b, max is g or b
        lda pal_b,x
        cmp pal_g,x
        bcs +
        lda pal_g,x
+       sta tmp2                        ; max
        cmp #230
        bcs _keep
        lda pal_b,x
        cmp pal_r,x
        bcc +
        lda pal_r,x
+       sta tmp3                        ; min
        sec
        lda tmp2
        sbc tmp3
        cmp #120
        bcs _keep
        sec
        rts
_keep:  clc
        rts

; zlib's Adler-32 of the output, against the 4 bytes after the last block; and the row
; filters, which this viewer can't undo if they aren't all 0 (type None)
png_verify:
        lda #1
        sta ad_a
        lda #0
        sta ad_a+1
        sta ad_b
        sta ad_b+1
        sta i_n
        sta i_n+1
        jsr inf_out_rewind
_lp:    ldz #0
        lda [iout],z
        clc
        adc ad_a
        sta ad_a
        bcc +
        inc ad_a+1
        bne +
        ; carried out of 16 bits: 65536 mod 65521 = 15
        lda ad_a
        clc
        adc #15
        sta ad_a
+       lda ad_a+1                      ; a >= 65521?
        cmp #$ff
        bne +
        lda ad_a
        cmp #$f1
        bcc +
        sbc #$f1
        sta ad_a
        lda #0
        sta ad_a+1
+       clc
        lda ad_b
        adc ad_a
        sta ad_b
        lda ad_b+1
        adc ad_a+1
        sta ad_b+1
        bcc +
        lda ad_b                        ; as above, for b
        clc
        adc #15
        sta ad_b
        bcc +
        inc ad_b+1
+       lda ad_b+1
        cmp #$ff
        bne +
        lda ad_b
        cmp #$f1
        bcc +
        sbc #$f1
        sta ad_b
        lda #0
        sta ad_b+1
+       inc iout
        bne +
        inc iout+1
        bne +
        inc iout+2
+       inc i_n
        bne +
        inc i_n+1
+       lda i_n
        cmp #<PNG_RAW
        bne _lp
        lda i_n+1
        cmp #>PNG_RAW
        bne _lp
        ; the file's value: big-endian b, a
        lda #0
        sta i_bitcnt                    ; drop to a byte boundary
        jsr png_stream_byte
        sta ad_file
        jsr png_stream_byte
        sta ad_file+1
        jsr png_stream_byte
        sta ad_file+2
        jsr png_stream_byte
        sta ad_file+3
        lda ad_b+1
        sta dbg_adler
        lda ad_b
        sta dbg_adler+1
        lda ad_a+1
        sta dbg_adler+2
        lda ad_a
        sta dbg_adler+3
        ldx #3
-       lda ad_file,x
        cmp dbg_adler,x
        bne _crc
        dex
        bpl -
        ; the row filters
        jsr inf_out_rewind
        lda #PNG_H
        sta tmp0
_row:   ldz #0
        lda [iout],z
        bne _crc
        clc
        lda iout
        adc #<PNG_ROW
        sta iout
        lda iout+1
        adc #>PNG_ROW
        sta iout+1
        lda iout+2
        adc #0
        sta iout+2
        dec tmp0
        bne _row
        clc
        rts
_crc:   lda #E_CRC
        sta net_err
        sec
        rts

inf_out_rewind:
        lda #<INFLATE_ATTIC
        sta iout
        lda #>INFLATE_ATTIC
        sta iout+1
        lda #`INFLATE_ATTIC
        sta iout+2
        lda #INFLATE_ATTIC >> 24
        sta iout+3
        rts

; ---- DEFLATE ----
; one bit -> carry
inf_bit:
        lda i_bitcnt
        bne +
        jsr png_stream_byte
        sta i_bitbuf
        lda #8
        sta i_bitcnt
+       dec i_bitcnt
        lsr i_bitbuf
        rts

; A = bit count (0-16) -> i_tmpw, least significant bit first
inf_bits:
        tax
        lda #0
        sta i_tmpw
        sta i_tmpw+1
        cpx #0
        beq _o
        lda #1
        sta i_code
        lda #0
        sta i_code+1
_lp:    phx
        jsr inf_bit
        plx
        bcc +
        lda i_tmpw
        ora i_code
        sta i_tmpw
        lda i_tmpw+1
        ora i_code+1
        sta i_tmpw+1
+       asl i_code
        rol i_code+1
        dex
        bne _lp
_o:     rts

inflate:
        jsr inf_out_rewind
        lda #<PNG_RAW
        sta out_left
        lda #>PNG_RAW
        sta out_left+1
        lda #0
        sta i_bitcnt
        jsr png_stream_byte             ; the zlib header (CMF, FLG)
        and #$0f
        cmp #8
        bne _ibad
        jsr png_stream_byte
        and #$20                        ; a preset dictionary: not in a PNG
        bne _ibad
_block: jsr inf_bit
        lda #0
        rol
        sta i_final
        lda #2
        jsr inf_bits
        lda i_tmpw
        beq _stored
        cmp #1
        beq _fixed
        cmp #2
        beq _dyn
_ibad:
        lda #E_INFL
        sta net_err
        sec
        rts
_stored:
        jsr inf_stored
        bra _after
_fixed: jsr inf_fixed
        bra _codes
_dyn:   jsr inf_dynamic
        bcs _ibad
_codes: jsr inf_codes
_after: bcs _ibad
        lda png_failed
        bne _ibad
        lda i_final
        beq _block
        lda out_left
        ora out_left+1
        bne _ibad
        clc
        rts

inf_out_byte:                           ; A -> output; carry set when there's no room
        tax
        lda out_left
        ora out_left+1
        beq _full
        txa
        ldz #0
        sta [iout],z
        inc iout
        bne +
        inc iout+1
        bne +
        inc iout+2
+       lda out_left
        bne +
        dec out_left+1
+       dec out_left
        clc
        rts
_full:  sec
        rts

inf_stored:
        lda #0
        sta i_bitcnt
        jsr png_stream_byte
        sta i_n
        jsr png_stream_byte
        sta i_n+1
        jsr png_stream_byte
        jsr png_stream_byte
_lp:    lda i_n
        ora i_n+1
        beq _ok
        jsr png_stream_byte
        jsr inf_out_byte
        bcs _o
        lda png_failed
        bne _bad
        lda i_n
        bne +
        dec i_n+1
+       dec i_n
        bra _lp
_ok:    clc
_o:     rts
_bad:   sec
        rts

; The Huffman tables: counts per code length, and symbols ordered by code
CONSTRUCT .macro cnt_lo, cnt_hi, sym_lo, sym_hi
        ; A/X = symbol count; lengths at inf_lens + i_tabq
        sta i_n
        stx i_n+1
        ldx #15
        lda #0
-       sta \cnt_lo,x
        sta \cnt_hi,x
        dex
        bpl -
        lda #0
        sta i_tmpw
        sta i_tmpw+1
        lda i_tabq
        sta i_tabp
        lda i_tabq+1
        sta i_tabp+1
_count: lda i_tmpw
        cmp i_n
        bne +
        lda i_tmpw+1
        cmp i_n+1
        beq _offs
+       ldy #0
        lda (i_tabp),y
        tax
        inc \cnt_lo,x
        bne +
        inc \cnt_hi,x
+       inw i_tabp
        inw i_tmpw
        bra _count
_offs:  lda #0
        sta inf_offs_lo+1
        sta inf_offs_hi+1
        ldx #1
-       clc
        lda inf_offs_lo,x
        adc \cnt_lo,x
        sta inf_offs_lo+1,x
        lda inf_offs_hi,x
        adc \cnt_hi,x
        sta inf_offs_hi+1,x
        inx
        cpx #15
        bne -
        lda #0
        sta i_tmpw
        sta i_tmpw+1
        lda i_tabq
        sta i_tabp
        lda i_tabq+1
        sta i_tabp+1
_sym:   lda i_tmpw
        cmp i_n
        bne +
        lda i_tmpw+1
        cmp i_n+1
        beq _done
+       ldy #0
        lda (i_tabp),y
        beq _nosym
        tax                             ; length
        clc
        lda inf_offs_lo,x
        adc #<\sym_lo
        sta i_code
        lda inf_offs_hi,x
        adc #>\sym_lo
        sta i_code+1
        lda i_tmpw
        sta (i_code),y
        clc
        lda inf_offs_lo,x
        adc #<\sym_hi
        sta i_code
        lda inf_offs_hi,x
        adc #>\sym_hi
        sta i_code+1
        lda i_tmpw+1
        sta (i_code),y
        inc inf_offs_lo,x
        bne _nosym
        inc inf_offs_hi,x
_nosym: inw i_tabp
        inw i_tmpw
        bra _sym
_done:
.endmacro

DECODE .macro cnt_lo, cnt_hi, sym_lo, sym_hi
        lda #0
        sta i_code
        sta i_code+1
        sta i_first
        sta i_first+1
        sta i_index
        sta i_index+1
        ldy #1
_len:   phy
        jsr inf_bit
        ply
        bcc +
        lda i_code
        ora #1
        sta i_code
+       clc                             ; i_tmpw = first + count
        lda i_first
        adc \cnt_lo,y
        sta i_tmpw
        lda i_first+1
        adc \cnt_hi,y
        sta i_tmpw+1
        lda i_code+1                    ; code < first + count: this length
        cmp i_tmpw+1
        bcc _hit
        bne _on
        lda i_code
        cmp i_tmpw
        bcc _hit
_on:    clc
        lda i_index
        adc \cnt_lo,y
        sta i_index
        lda i_index+1
        adc \cnt_hi,y
        sta i_index+1
        lda i_tmpw
        sta i_first
        lda i_tmpw+1
        sta i_first+1
        asl i_first
        rol i_first+1
        asl i_code
        rol i_code+1
        iny
        cpy #16
        bne _len
        sec                             ; ran out of code lengths
        rts
_hit:   sec                             ; symbol index = index + code - first
        lda i_code
        sbc i_first
        sta i_tmpw
        lda i_code+1
        sbc i_first+1
        sta i_tmpw+1
        clc
        lda i_tmpw
        adc i_index
        sta i_tmpw
        lda i_tmpw+1
        adc i_index+1
        sta i_tmpw+1
        clc
        lda i_tmpw
        adc #<\sym_lo
        sta i_tabp
        lda i_tmpw+1
        adc #>\sym_lo
        sta i_tabp+1
        ldy #0
        lda (i_tabp),y
        sta i_sym
        clc
        lda i_tmpw
        adc #<\sym_hi
        sta i_tabp
        lda i_tmpw+1
        adc #>\sym_hi
        sta i_tabp+1
        lda (i_tabp),y
        sta i_sym+1
        clc
        rts
.endmacro

inf_build_lit:
        #CONSTRUCT inf_lcnt_lo, inf_lcnt_hi, inf_lsym_lo, inf_lsym_hi
        rts
inf_build_dist:
        #CONSTRUCT inf_dcnt_lo, inf_dcnt_hi, inf_dsym_lo, inf_dsym_hi
        rts
inf_decode_lit:
        #DECODE inf_lcnt_lo, inf_lcnt_hi, inf_lsym_lo, inf_lsym_hi
inf_decode_dist:
        #DECODE inf_dcnt_lo, inf_dcnt_hi, inf_dsym_lo, inf_dsym_hi

inf_tabq_set .macro off
        lda #<(inf_lens + \off)
        sta i_tabq
        lda #>(inf_lens + \off)
        sta i_tabq+1
.endmacro

inf_fixed:
        ldx #0
-       lda #8
        cpx #144
        bcc +
        lda #9
+       sta inf_lens,x
        inx
        bne -
        ldx #0
-       lda #7
        cpx #24
        bcc +
        lda #8
+       sta inf_lens+256,x
        inx
        cpx #32
        bne -
        #inf_tabq_set 0
        lda #<288
        ldx #>288
        jsr inf_build_lit
        ldx #0
        lda #5
-       sta inf_lens,x
        inx
        cpx #30
        bne -
        #inf_tabq_set 0
        lda #30
        ldx #0
        jmp inf_build_dist

inf_dynamic:
        lda #5
        jsr inf_bits
        clc
        lda i_tmpw
        adc #<257
        sta i_nlen
        lda #>257
        adc #0
        sta i_nlen+1
        lda #5
        jsr inf_bits
        ldx i_tmpw
        inx
        stx i_ndist
        lda #4
        jsr inf_bits
        lda i_tmpw
        clc
        adc #4
        sta i_ncode
        ; the code-length code, in its odd order
        ldx #18
        lda #0
-       sta inf_lens,x
        dex
        bpl -
        lda #0
        sta i_tmp
_cl:    lda #3
        jsr inf_bits
        ldy i_tmp
        ldx inf_order,y
        lda i_tmpw
        sta inf_lens,x
        inc i_tmp
        lda i_tmp
        cmp i_ncode
        bne _cl
        #inf_tabq_set 0
        lda #19
        ldx #0
        jsr inf_build_lit
        ; read literal/length + distance lengths with it
        lda #0
        sta i_len
        sta i_len+1
        clc
        lda i_nlen
        adc i_ndist
        sta i_dist
        lda i_nlen+1
        adc #0
        sta i_dist+1                    ; total
_ll:    lda i_len+1                     ; a repeat can overshoot on bad data: that's an error,
        cmp i_dist+1                    ;   or it would write on through memory
        bcc _more
        bne _over
        lda i_len
        cmp i_dist
        bcc _more
        bne _over
        jmp _built
_over:  jmp _dbad
_more:  jsr inf_decode_lit
        bcc +
        jmp _dbad
+       lda png_failed
        beq +
        jmp _dbad
+       lda i_sym
        cmp #16
        bcs _rep
        jsr inf_len_put
        jmp _ll
_rep:   ldx #0
        stx i_prev                      ; repeat zeros, unless 16
        cmp #16
        bne _r17
        lda i_len
        ora i_len+1
        bne +
        jmp _dbad                       ; "repeat previous" with no previous
+       sec
        lda i_len
        sbc #1
        sta nptr
        lda i_len+1
        sbc #0
        sta nptr+1
        clc
        lda nptr
        adc #<inf_lens
        sta nptr
        lda nptr+1
        adc #>inf_lens
        sta nptr+1
        ldy #0
        lda (nptr),y
        sta i_prev
        lda #2
        jsr inf_bits
        lda i_tmpw
        clc
        adc #3
        bra _rp
_r17:   cmp #17
        bne _r18
        lda #3
        jsr inf_bits
        lda i_tmpw
        clc
        adc #3
        bra _rp
_r18:   lda #7
        jsr inf_bits
        lda i_tmpw
        clc
        adc #11
_rp:    sta i_rep
_rl:    lda i_prev
        jsr inf_len_put
        dec i_rep
        bne _rl
        jmp _ll
_built: #inf_tabq_set 0
        lda i_nlen
        ldx i_nlen+1
        jsr inf_build_lit
        clc
        lda #<inf_lens
        adc i_nlen
        sta i_tabq
        lda #>inf_lens
        adc i_nlen+1
        sta i_tabq+1
        lda i_ndist
        ldx #0
        jsr inf_build_dist
        clc
        rts
_dbad:  sec
        rts

inf_len_put:
        pha
        clc
        lda i_len
        adc #<inf_lens
        sta nptr
        lda i_len+1
        adc #>inf_lens
        sta nptr+1
        pla
        ldy #0
        sta (nptr),y
        inc i_len
        bne +
        inc i_len+1
+       rts

inf_codes:
_sym:   jsr inf_decode_lit
        bcs _out
        lda png_failed
        bne _bad
        lda i_sym+1
        bne _notlit
        lda i_sym
        jsr inf_out_byte
        bcc _sym
_out:   rts
_bad:   sec
        rts
_notlit:
        lda i_sym
        bne +                           ; 256 is the end of the block
        clc
        rts
+       cmp #30                         ; 257..285 -> 1..29
        bcs _bad
        tax
        dex                             ; 0..28
        lda inf_lbase_lo,x
        sta i_len
        lda inf_lbase_hi,x
        sta i_len+1
        lda inf_lext,x
        jsr inf_bits
        clc
        lda i_len
        adc i_tmpw
        sta i_len
        lda i_len+1
        adc i_tmpw+1
        sta i_len+1
        jsr inf_decode_dist
        bcs _out
        lda i_sym
        cmp #30
        bcs _bad
        tax
        lda inf_dbase_lo,x
        sta i_dist
        lda inf_dbase_hi,x
        sta i_dist+1
        lda inf_dext,x
        jsr inf_bits
        clc
        lda i_dist
        adc i_tmpw
        sta i_dist
        lda i_dist+1
        adc i_tmpw+1
        sta i_dist+1
        ; copy i_len bytes from iout - i_dist. Mustn't reach before the start of the output.
        sec
        lda iout
        sbc i_dist
        sta isrc
        lda iout+1
        sbc i_dist+1
        sta isrc+1
        lda iout+2
        sbc #0
        sta isrc+2
        lda iout+3
        sta isrc+3
        lda isrc+2
        cmp #`INFLATE_ATTIC
        bcc _bad
_cp:    ldz #0
        lda [isrc],z
        jsr inf_out_byte
        bcs _out
        inc isrc
        bne +
        inc isrc+1
        bne +
        inc isrc+2
+       lda i_len
        bne +
        dec i_len+1
+       dec i_len
        lda i_len
        ora i_len+1
        bne _cp
        jmp _sym

inf_order:   .byte 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15
LBASE = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258]
DBASE = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577]
inf_lbase_lo: .byte <LBASE
inf_lbase_hi: .byte >LBASE
inf_lext:     .byte 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0
inf_dbase_lo: .byte <DBASE
inf_dbase_hi: .byte >DBASE
inf_dext:     .byte 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13
