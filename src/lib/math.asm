;=======================================================================================
; lib/math.asm - the MEGA65's hardware multiplier and divider.
;
;   mul16          tmp4 * tmp5 -> MULTOUT ($D778, 32-bit; ready immediately)
;   div16          tmp4 / tmp5 -> tmp6 = quotient, tmp7 = fraction (8.8-style: the high
;                  16 bits of the fractional part). Waits for the divider.
;   rand           A = next 8-bit pseudo-random number (16-bit Galois LFSR)
; The registers can also be used directly: write MULTINA ($D770) and MULTINB ($D774),
; read MULTOUT, or DIVOUT ($D768, 32.32) once DIVBUSY ($D70F bit 7) clears.
;=======================================================================================

mul16:
        lda tmp4
        sta MULTINA
        lda tmp4+1
        sta MULTINA+1
        lda #0
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+2
        sta MULTINB+3
        lda tmp5
        sta MULTINB
        lda tmp5+1
        sta MULTINB+1
        rts

div16:
        jsr mul16                       ; same inputs
-       bit DIVBUSY
        bmi -
        lda DIVOUT+4
        sta tmp6
        lda DIVOUT+5
        sta tmp6+1
        lda DIVOUT+2
        sta tmp7
        lda DIVOUT+3
        sta tmp7+1
        rts

; rand_seed_hw - seed rand from the hardware random number generator
rand_seed_hw:
        jsr l_rng_byte
        sta l_rand_seed
        jsr l_rng_byte
        ora #1                          ; never all zero
        sta l_rand_seed+1
        rts
; $D7FE bit 7 = NOT ready; give up after a while (an emulator may never be ready)
l_rng_byte:
        ldy #0
-       bit HWRNG_READY
        bpl +
        dey
        bne -
        lda frame_count                 ; fallback
        eor l_rand_seed
        rts
+       lda HWRNG
        rts

rand:
        lda l_rand_seed
        asl
        rol l_rand_seed+1
        bcc +
        eor #$2d                        ; taps for x^16 + x^14 + x^13 + x^11 + 1 (lo)
+       sta l_rand_seed
        eor l_rand_seed+1
        rts
l_rand_seed:     .word $ace1
