;=======================================================================================
; lib/rtc.asm - the real-time clock (from little-mega-people).
;
;   rtc_read       rtc_sec, rtc_min, rtc_hour (0-23), rtc_day, rtc_month, rtc_year
;                  (0-99), all binary. Carry set if the clock gave nonsense (no RTC,
;                  flat battery, emulator) - the values are then unchanged.
; The RTC at $FFD7110 is BCD. Hour bit 7 = 24-hour mode, otherwise bit 5 = PM. Xemu
; returns the month in binary, so 1-12 is accepted as-is.
;=======================================================================================

rtc_sec:        .byte 0
rtc_min:        .byte 0
rtc_hour:       .byte 0
rtc_day:        .byte 1
rtc_month:      .byte 1
rtc_year:       .byte 0
l_rtc:          .fill 6
l_rtc_hraw:     .byte 0

rtc_read:
        lda #<RTC_BASE
        sta ptr0
        lda #>RTC_BASE
        sta ptr0+1
        lda #`RTC_BASE
        sta ptr0+2
        lda #RTC_BASE >> 24
        sta ptr0+3
        ldz #2
        lda [ptr0],z
        sta l_rtc_hraw
        ldx #0
l_rtc_get:
        txa
        taz
        lda [ptr0],z
        cpx #2
        bne +
        and #$3f                        ; hour: drop the mode bits
        bit l_rtc_hraw
        bmi +
        and #$1f
+       sta tmp0
        jsr l_rtc_bcd
        bcc l_rtc_ok
        cpx #4                          ; Xemu: month in binary
        bne l_rtc_bad
        lda tmp0
        beq l_rtc_bad
        cmp #13
        bcs l_rtc_bad
l_rtc_ok:
        sta l_rtc,x
        inx
        cpx #6
        bne l_rtc_get
        ldz #0
        lda l_rtc
        cmp #60
        bcs l_rtc_bad
        lda l_rtc+1
        cmp #60
        bcs l_rtc_bad
        lda l_rtc+3
        beq l_rtc_bad
        cmp #32
        bcs l_rtc_bad
        lda l_rtc+4
        beq l_rtc_bad
        cmp #13
        bcs l_rtc_bad
        lda l_rtc+2                     ; hour -> 24h
        bit l_rtc_hraw
        bmi l_rtc_24
        cmp #12
        bne +
        lda #0
+       pha
        lda l_rtc_hraw
        and #$20
        beq +
        pla
        clc
        adc #12
        bra l_rtc_24
+       pla
l_rtc_24:
        cmp #24
        bcs l_rtc_bad
        sta rtc_hour
        lda l_rtc
        sta rtc_sec
        lda l_rtc+1
        sta rtc_min
        lda l_rtc+3
        sta rtc_day
        lda l_rtc+4
        sta rtc_month
        lda l_rtc+5
        sta rtc_year
        clc
        rts
l_rtc_bad:
        ldz #0
        sec
        rts

; A = BCD -> A = binary, carry set if a digit is not 0-9 (keeps X)
l_rtc_bcd:
        pha
        and #$0f
        cmp #10
        bcs l_rtc_bcd_bad
        sta tmp1
        pla
        lsr
        lsr
        lsr
        lsr
        cmp #10
        bcs l_rtc_bcd_bad2
        sta tmp2                        ; tens * 10 = tens * 8 + tens * 2
        asl
        asl
        asl
        clc
        adc tmp2
        adc tmp2
        adc tmp1
        clc
        rts
l_rtc_bcd_bad:
        pla
l_rtc_bcd_bad2:
        sec
        rts
