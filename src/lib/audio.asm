;=======================================================================================
; lib/audio.asm - audio DMA (book appendix P, mixer appendix V).
;
;   audio_init     audio DMA on, mixer routes digital audio L/R to both speakers and
;                  the headphones (the power-on levels can be zero = silence), all four
;                  channels stopped
;   audio_play     X = channel 0-3. aud_addr (24-bit CHIP RAM - audio DMA cannot read
;                  attic), aud_len (<= 64 KB: only 16 address bits are compared),
;                  aud_rate (24-bit: Hz * 2^24 / 40.5 MHz, e.g. 11025 Hz = $0011D7),
;                  aud_vol, aud_ctrl ($A2 one-shot 8-bit signed, $E2 looping, +$20 =
;                  unsigned, low bits 11 = 16-bit, 01/00 = upper/lower nybble)
;   audio_stop     X = channel
;   stream_start   play long audio from ATTIC on channel 0 through a chip-RAM ring
;                  (AUD_RING, AUD_RING_SIZE): str_src (28-bit), str_len (24-bit bytes),
;                  str_rate, str_packed4 (1 = two 4-bit samples per byte, low nibble
;                  first, like many C64 digis; 0 = 8-bit unsigned), str_loop
;   stream_frame   call once a frame from the IRQ: refills what the channel has played
;   stream_stop
; The CPU must run at 40 MHz and its waiting loops must read memory: audio DMA uses
; the idle cycles of memory-reading instructions.
;=======================================================================================

        .weak
AUD_RING        = $14000                ; chip RAM, 256-aligned (bank 1: free after #TAKEOVER;
                                        ; banks 4-5 hold full-screen framebuffers)
AUD_RING_SIZE   = $2000                 ; power of two, <= 64 KB
        .endweak

aud_addr:       .fill 3
aud_len:        .word 0
aud_rate:       .fill 3
aud_vol:        .byte $c0
aud_ctrl:       .byte $a2

audio_init:
        lda #$80                        ; AUDEN, through the mixer
        sta AUD_CTRL
        ldx #0
-       lda l_aud_mix_regs,x
        beq +
        sta MIX_SEL
        lda l_aud_mix_vals,x
        sta MIX_DATA
        ldy #20                         ; > 32 cycles before the next select
l_ai_w:  dey
        bne l_ai_w
        inx
        bra -
+       ldx #3
-       jsr audio_stop
        dex
        bpl -
        rts

; coefficient = output * 32 + source * 2 (LSB, MSB); digital L/R are sources 8/9,
; outputs 0/1 = speakers, 6/7 = headphones
l_aud_mix_regs:  .byte $10, $11, $12, $13, $30, $31, $32, $33, $d0, $d1, $f2, $f3, 0
l_aud_mix_vals:  .byte $ff, $bf, $ff, $3f, $ff, $3f, $ff, $bf, $ff, $bf, $ff, $bf

audio_stop:
        txa
        asl
        asl
        asl
        asl
        tay
        lda #0
        sta AUD_CH0,y
        rts

audio_play:
        jsr audio_stop                  ; Y = register offset
        lda aud_addr                    ; loop base and current address = start
        sta AUD_CH0+1,y
        sta AUD_CH0+$a,y
        lda aud_addr+1
        sta AUD_CH0+2,y
        sta AUD_CH0+$b,y
        lda aud_addr+2
        sta AUD_CH0+3,y
        sta AUD_CH0+$c,y
        clc                             ; end address, low 16 bits
        lda aud_addr
        adc aud_len
        sta AUD_CH0+7,y
        lda aud_addr+1
        adc aud_len+1
        sta AUD_CH0+8,y
        lda aud_rate
        sta AUD_CH0+4,y
        lda aud_rate+1
        sta AUD_CH0+5,y
        lda aud_rate+2
        sta AUD_CH0+6,y
        lda aud_vol
        sta AUD_CH0+9,y
        sta AUD_RVOL,x                  ; same volume on the other side
        lda aud_ctrl                    ; control byte last
        sta AUD_CH0,y
        rts

;---------------------------------------------------------------------------------------
; streaming from attic
;---------------------------------------------------------------------------------------
str_src:        .fill 4
str_len:        .fill 3
str_rate:       .fill 3
str_packed4:    .byte 0
str_loop:       .byte 1
l_str_on:        .byte 0
l_str_rem:       .fill 3
l_str_wpos:      .word 0
l_str_fill:      .word 0
l_str_tmp:       .byte 0

stream_start:
        lda #0
        sta l_str_on
        sta AUD_CH0
        jsr l_str_rewind
        lda #<AUD_RING
        sta rptr
        lda #>AUD_RING
        sta rptr+1
        lda #`AUD_RING
        sta rptr+2
        lda #0
        sta rptr+3
        sta l_str_wpos
        sta l_str_wpos+1
        lda #<(AUD_RING_SIZE - $400)    ; prefill most of the ring
        sta l_str_fill
        lda #>(AUD_RING_SIZE - $400)
        sta l_str_fill+1
        jsr l_str_fill_n
        lda #<AUD_RING
        sta aud_addr
        lda #>AUD_RING
        sta aud_addr+1
        lda #`AUD_RING
        sta aud_addr+2
        lda #<(AUD_RING_SIZE - 1)
        sta aud_len
        lda #>(AUD_RING_SIZE - 1)
        sta aud_len+1
        ldx #2
-       lda str_rate,x
        sta aud_rate,x
        dex
        bpl -
        lda #$e2                        ; enable, loop, unsigned, 8 bit
        sta aud_ctrl
        ldx #0
        jsr audio_play
        lda #1
        sta l_str_on
        rts

stream_stop:
        lda #0
        sta l_str_on
        sta AUD_CH0
        rts

l_str_rewind:
        ldx #3
-       lda str_src,x
        sta aptr,x
        dex
        bpl -
        ldx #2
-       lda str_len,x
        sta l_str_rem,x
        dex
        bpl -
        rts

stream_frame:
        lda l_str_on
        bne +
        rts
+       ; free = (played - written - 256) & (size - 1)
        lda AUD_CH0+$a
        sta l_str_fill
        lda AUD_CH0+$b
        sec
        sbc #>AUD_RING
        and #>(AUD_RING_SIZE - 1)
        sta l_str_fill+1
        sec
        lda l_str_fill
        sbc l_str_wpos
        sta l_str_fill
        lda l_str_fill+1
        sbc l_str_wpos+1
        sec
        sbc #1
        and #>(AUD_RING_SIZE - 1)
        sta l_str_fill+1
        cmp #4                          ; at most 1 KB per frame
        bcc l_str_fill_n
        lda #0
        sta l_str_fill
        lda #4
        sta l_str_fill+1

; write l_str_fill samples (even) into the ring
l_str_fill_n:
        lda str_packed4
        beq +
        lsr l_str_fill+1                 ; two samples per source byte
        ror l_str_fill
+       lda l_str_fill
        ora l_str_fill+1
        beq l_sf_done
l_sf_byte:
        lda l_str_rem
        ora l_str_rem+1
        ora l_str_rem+2
        bne +
        lda str_loop
        beq l_sf_silence
        jsr l_str_rewind
+       ldz #0
        lda [aptr],z
        ldx str_packed4
        beq l_sf_8bit
        sta l_str_tmp
        asl
        asl
        asl
        asl                             ; low nibble first
        sta [rptr],z
        inz
        lda l_str_tmp
        and #$f0
        sta [rptr],z
        lda #2
        bra l_sf_adv
l_sf_silence:                            ; finished, not looping: write silence
        lda #$80
        ldz #0
        sta [rptr],z
        ldx str_packed4
        beq +
        inz
        sta [rptr],z
        lda #2
        bra l_sf_adv2
+       lda #1
        bra l_sf_adv2
l_sf_8bit:
        sta [rptr],z
        lda #1
l_sf_adv:
        pha
        inc aptr                        ; source++
        bne +
        inc aptr+1
        bne +
        inc aptr+2
+       lda l_str_rem                    ; remaining--
        bne l_sf_dl
        lda l_str_rem+1
        bne l_sf_dm
        dec l_str_rem+2
l_sf_dm: dec l_str_rem+1
l_sf_dl: dec l_str_rem
        pla
l_sf_adv2:
        clc                             ; ring += A
        adc l_str_wpos
        sta l_str_wpos
        lda l_str_wpos+1
        adc #0
        and #>(AUD_RING_SIZE - 1)
        sta l_str_wpos+1
        clc
        lda l_str_wpos
        adc #<AUD_RING
        sta rptr
        lda l_str_wpos+1
        adc #>AUD_RING
        sta rptr+1
        lda l_str_fill
        bne +
        dec l_str_fill+1
+       dec l_str_fill
        lda l_str_fill
        ora l_str_fill+1
        bne l_sf_byte
l_sf_done:
        rts
