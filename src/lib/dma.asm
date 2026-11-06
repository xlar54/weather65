;=======================================================================================
; DMAgic helpers.
;
; All jobs use enhanced (F018B) lists that live in bank 0 and are patched in place,
; then started by writing the list address with the LSB going to $D705 (ETRIG).
;
; F018B job layout (after the option bytes, which end with $00):
;     +0  command   ($00 copy, $03 fill)
;     +1  count     (word)
;     +3  source    (word + bank byte; for a fill, the low byte is the fill value)
;     +6  dest      (word + bank byte)
;     +9  sub-command
;     +10 modulo    (word)
; Option $80/$81 give the source/dest megabyte (address bits 20-27); the bank byte
; holds address bits 16-19.
;=======================================================================================

DMA_RUN .macro list
        lda #>\list
        sta DMA_ADDRMSB
        lda #<\list
        sta DMA_ADDRLSB_ETRIG
.endmacro

dma_init:
        lda #0
        sta DMA_ADDRMB
        sta DMA_ADDRBANK
        rts

;---------------------------------------------------------------------------------------
; Generic copy / fill. Callers patch the fields then jsr dma_go.
;---------------------------------------------------------------------------------------
dma_job:
        .byte DMAOPT_F018B
        .byte DMAOPT_SRC_MB
dmaj_src_mb:
        .byte 0
        .byte DMAOPT_DST_MB
dmaj_dst_mb:
        .byte 0
        .byte DMAOPT_END
dmaj_cmd:
        .byte DMACMD_COPY
dmaj_count:
        .word 0
dmaj_src:
        .word 0
dmaj_src_bank:
        .byte 0
dmaj_dst:
        .word 0
dmaj_dst_bank:
        .byte 0
        .byte 0
        .word 0

dma_go:
        #DMA_RUN dma_job
        rts

;---------------------------------------------------------------------------------------
; Sprite column blit: source step 1, destination step 8 (one FCM char row), with
; transparency on colour 0. One job draws one sprite column.
;---------------------------------------------------------------------------------------
dma_blit:
        .byte DMAOPT_F018B
        .byte DMAOPT_SRC_MB
dmab_src_mb:
        .byte 0
        .byte DMAOPT_DST_MB, 0
        .byte DMAOPT_DST_STEP_INT, 8
        .byte DMAOPT_TRANSP_ON
        .byte DMAOPT_TRANSP_VAL, 0
        .byte DMAOPT_END
        .byte DMACMD_COPY
dmab_count:
        .word 0
dmab_src:
        .word 0
dmab_src_bank:
        .byte 0
dmab_dst:
        .word 0
dmab_dst_bank:
        .byte 0
        .byte 0
        .word 0

;---------------------------------------------------------------------------------------
; dma_fill - A = value, X = dest MB, Y = dest bank, tmp4 = address, tmp5 = count
;---------------------------------------------------------------------------------------
dma_fill:
        sta dmaj_src
        stx dmaj_dst_mb
        sty dmaj_dst_bank
        lda #DMACMD_FILL
        sta dmaj_cmd
        lda #0
        sta dmaj_src_mb
        sta dmaj_src+1
        sta dmaj_src_bank
        lda tmp4
        sta dmaj_dst
        lda tmp4+1
        sta dmaj_dst+1
        lda tmp5
        sta dmaj_count
        lda tmp5+1
        sta dmaj_count+1
        jsr dma_go
        lda #DMACMD_COPY
        sta dmaj_cmd
        rts

;---------------------------------------------------------------------------------------
; dma_copy_far - copy tmp5 bytes from 28-bit ptr1 to 28-bit ptr2 (dword pointers,
;                byte 3 = address bits 24-27). The DMAgic wraps addresses inside a
;                megabyte, so the copy is split at the first 1 MB boundary that either
;                the source or the destination crosses.
;---------------------------------------------------------------------------------------
dma_copy_far:
        ; room = bytes left in the megabyte = $100000 - (ptr & $fffff), for both
        ldx #ptr2 - ptr1
        jsr l_dcf_room
        sta tmp1                        ; destination: tmp1 (0 = under 64 KB) : tmp6
        lda tmp6
        sta tmp7
        lda tmp6+1
        sta tmp7+1
        ldx #0
        jsr l_dcf_room                   ; source: A : tmp6
        bne l_dcf_dst                    ; source has >= 64 KB room: the destination decides
        lda tmp1
        bne l_dcf_min                    ; destination has >= 64 KB: source room stands
        lda tmp7+1                      ; both under 64 KB: take the smaller
        cmp tmp6+1
        bcc l_dcf_dst
        bne l_dcf_min
        lda tmp7
        cmp tmp6
        bcs l_dcf_min
l_dcf_dst:
        lda tmp1
        bne l_dcf_one                    ; both have >= 64 KB room: fits
        lda tmp7
        sta tmp6
        lda tmp7+1
        sta tmp6+1
l_dcf_min:
        ; tmp6 = room (< 64 KB); split when it is smaller than the count
        lda tmp6+1
        cmp tmp5+1
        bcc l_dcf_split
        bne l_dcf_one
        lda tmp6
        cmp tmp5
        bcs l_dcf_one
l_dcf_split:
        ; first part: tmp6 bytes
        lda tmp5
        pha
        lda tmp5+1
        pha
        lda tmp6
        sta tmp5
        lda tmp6+1
        sta tmp5+1
        jsr l_dcf_job
        ; advance both pointers by tmp6, count -= tmp6
        clc
        lda ptr1
        adc tmp6
        sta ptr1
        lda ptr1+1
        adc tmp6+1
        sta ptr1+1
        lda ptr1+2
        adc #0
        sta ptr1+2
        lda ptr1+3
        adc #0
        sta ptr1+3
        clc
        lda ptr2
        adc tmp6
        sta ptr2
        lda ptr2+1
        adc tmp6+1
        sta ptr2+1
        lda ptr2+2
        adc #0
        sta ptr2+2
        lda ptr2+3
        adc #0
        sta ptr2+3
        pla
        sta tmp5+1
        pla
        sta tmp5
        sec
        lda tmp5
        sbc tmp6
        sta tmp5
        lda tmp5+1
        sbc tmp6+1
        sta tmp5+1
        jmp dma_copy_far                ; the rest may cross the other pointer's boundary
l_dcf_one:
l_dcf_job:
        lda tmp5
        ora tmp5+1
        beq +
        lda tmp5
        sta dmaj_count
        lda tmp5+1
        sta dmaj_count+1
        lda ptr1
        sta dmaj_src
        lda ptr1+1
        sta dmaj_src+1
        lda ptr1+2
        and #$0f
        sta dmaj_src_bank
        jsr l_dcf_mb1
        sta dmaj_src_mb
        lda ptr2
        sta dmaj_dst
        lda ptr2+1
        sta dmaj_dst+1
        lda ptr2+2
        and #$0f
        sta dmaj_dst_bank
        jsr l_dcf_mb2
        sta dmaj_dst_mb
        jmp dma_go
+       rts
; room left in the megabyte of the pointer at ptr1 + X: A = bits 16-20 (0 means
; under 64 KB, flags set from it), tmp6 = bits 0-15
l_dcf_room:
        lda ptr1+2,x
        and #$0f
        sta tmp0
        sec
        lda #0
        sbc ptr1,x
        sta tmp6
        lda #0
        sbc ptr1+1,x
        sta tmp6+1
        lda #$10
        sbc tmp0
        rts
; megabyte number = address bits 20-27
l_dcf_mb1:
        lda ptr1+3
        asl
        asl
        asl
        asl
        sta tmp0
        lda ptr1+2
        lsr
        lsr
        lsr
        lsr
        ora tmp0
        rts
l_dcf_mb2:
        lda ptr2+3
        asl
        asl
        asl
        asl
        sta tmp0
        lda ptr2+2
        lsr
        lsr
        lsr
        lsr
        ora tmp0
        rts
