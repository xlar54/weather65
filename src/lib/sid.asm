;=======================================================================================
; lib/sid.asm - simple SID sound effects (from mega-dust). One voice per effect class;
; each effect is a waveform, start pitch, per-frame pitch slide, length and envelope.
;
;   sid_init       SID 1 silent, full volume
;   sfx_play       A = effect number (index into the sfx_* tables)
;   sfx_frame      call once a frame (from the IRQ hook)
;
; Edit the tables for your game (or define SFX_TABLES_OWN = 1 and supply your own
; sfx_voice .. sfx_sr with SFX_COUNT entries).
;=======================================================================================

        .weak
SFX_TABLES_OWN  = 0
SID_MIRROR      = 0                     ; a second SID's address: every write goes there too
        .endweak                        ; (SID 1 and 2 are panned to opposite speakers)

        .if !SFX_TABLES_OWN
SFX_SHOT        = 0
SFX_EXPLODE     = 1
SFX_BIGBOOM     = 2
SFX_PICKUP      = 3
SFX_HIT         = 4
SFX_CHARGE      = 5
SFX_DIE         = 6
;               shot  expl  big   pick  hit   charge die
sfx_voice:  .byte 0,    7,    7,    14,   14,   0,     7     ; voice register offset
sfx_wave:   .byte $41,  $81,  $81,  $11,  $21,  $41,   $81   ; waveform + gate
sfx_fhi:    .byte $30,  $10,  $08,  $20,  $40,  $08,   $0c   ; start pitch (high byte)
sfx_fstep:  .byte $fd,  $ff,  $00,  $02,  $f8,  $01,   $ff   ; signed slide per frame
sfx_len:    .byte 6,    20,   40,   16,   4,    30,    50    ; frames
sfx_ad:     .byte $08,  $09,  $0b,  $08,  $00,  $0a,   $0c
sfx_sr:     .byte $80,  $f9,  $fb,  $a8,  $a0,  $a8,   $fc
        .endif

l_sfx_timer: .fill 3
l_sfx_cur:   .fill 3
l_sfx_freq:  .fill 3
l_sfx_vidx:  .byte 0,0,0,0,0,0,0,1,0,0,0,0,0,0,2
l_sfx_voffs: .byte 0, 7, 14

L_SID_W .macro
        sta SID1+\1,x
        .if SID_MIRROR
        sta SID_MIRROR+\1,x
        .endif
.endmacro

sid_init:
        ldx #$18
        lda #0
-       sta SID1,x
        .if SID_MIRROR
        sta SID_MIRROR,x
        .endif
        dex
        bpl -
        lda #$0f
        sta SID1+$18
        .if SID_MIRROR
        sta SID_MIRROR+$18
        .endif
        rts

sfx_play:
        tay
        ldx sfx_voice,y
        lda l_sfx_vidx,x
        tax
        tya
        sta l_sfx_cur,x
        lda sfx_len,y
        sta l_sfx_timer,x
        lda sfx_fhi,y
        sta l_sfx_freq,x
        ldx sfx_voice,y
        lda #0
        #L_SID_W 4                      ; gate off to retrigger
        #L_SID_W 0
        #L_SID_W 2
        lda sfx_fhi,y
        #L_SID_W 1
        lda #$08
        #L_SID_W 3                      ; pulse width
        lda sfx_ad,y
        #L_SID_W 5
        lda sfx_sr,y
        #L_SID_W 6
        lda sfx_wave,y
        #L_SID_W 4
        rts

sfx_frame:
        ldx #0
l_sf_v:
        lda l_sfx_timer,x
        beq l_sf_next
        dec l_sfx_timer,x
        ldy l_sfx_cur,x
        lda l_sfx_voffs,x
        taz
        lda l_sfx_timer,x
        bne +
        phx                             ; release
        tza
        tax
        lda sfx_wave,y
        and #$fe
        #L_SID_W 4
        plx
        bra l_sf_next
+       clc
        lda l_sfx_freq,x
        adc sfx_fstep,y
        sta l_sfx_freq,x
        phx
        pha
        tza
        tax
        pla
        #L_SID_W 1
        plx
l_sf_next:
        inx
        cpx #3
        bne l_sf_v
        rts
