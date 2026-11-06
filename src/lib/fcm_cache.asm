;=======================================================================================
; lib/fcm_cache.asm - keep a scene's static background and restore it with one DMA
; copy per frame, instead of redrawing it (from archon65).
;
;   cache_restore  A = key of the background wanted. Carry clear: the cache held it and
;                  it is now in the back buffer. Carry set: draw it into the back buffer
;                  yourself, then call cache_save (which remembers the key).
;   cache_key      the key held ($ff = nothing); write $ff to drop the cache
; FCM_CACHE (default attic $8100000) holds one buffer (FB_SIZE bytes). Don't put it in
; bank 1: $1F800-$1FFFF there is the first 2 KB of colour RAM. Needs lib/dma.asm,
; lib/video_fcm.asm.
;=======================================================================================

        .weak
FCM_CACHE       = $8100000
        .endweak
cache_key:         .byte $ff               ; what the cache holds ($ff = nothing)

; A = key of the background wanted: carry clear when the cache had it and it is now
; in the back buffer; carry set when the caller must draw it, then call cache_save
cache_restore:
        cmp cache_key
        bne _miss
        lda #<FCM_CACHE
        sta ptr1
        lda #>FCM_CACHE
        sta ptr1+1
        lda #`FCM_CACHE
        sta ptr1+2
        lda #FCM_CACHE >> 24
        sta ptr1+3
        lda #0
        sta ptr2
        sta ptr2+1
        sta ptr2+3
        lda fb_bank
        sta ptr2+2
        jsr l_cache_copy
        clc
        rts
_miss:  sta l_cache_want
        sec
        rts
l_cache_want:      .byte 0

; the back buffer is the background for key l_cache_want: keep it
cache_save:
        lda #0
        sta ptr1
        sta ptr1+1
        sta ptr1+3
        lda fb_bank
        sta ptr1+2
        lda #<FCM_CACHE
        sta ptr2
        lda #>FCM_CACHE
        sta ptr2+1
        lda #`FCM_CACHE
        sta ptr2+2
        lda #FCM_CACHE >> 24
        sta ptr2+3
        jsr l_cache_copy
        lda l_cache_want
        sta cache_key
        rts
l_cache_copy:
        lda #<FB_SIZE
        sta tmp5
        lda #>FB_SIZE
        sta tmp5+1
        jmp dma_copy_far

