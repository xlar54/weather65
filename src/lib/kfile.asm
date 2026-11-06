;=======================================================================================
; lib/kfile.asm - loading and saving files AFTER #TAKEOVER (high scores, save games),
; through the KERNAL (from mega-elite's lowfile). The KERNAL only runs in its own
; environment, so a small trampoline copied below $2000 (KF_LOW) puts back the boot
; MAP, $01 and $D030, calls SETBNK/SETLFS/SETNAM/LOAD or SAVE, and restores the game's.
;
;   kfile_capture  call ONCE at boot, before #TAKEOVER: records the boot $01/$D030 and
;                  copies the trampoline to KF_LOW
;   kfile_save     A = name length, X/Y = name (any bank-0 address), kf_bank = data
;                  bank, kf_start / kf_end (end is exclusive) = 16-bit addresses.
;                  The file is replaced if it exists ("@0:" prefix). Carry set = error.
;   kfile_load     same name args; kf_bank / kf_start = where the body goes.
;                  Carry set = error; kf_end = address after the last byte.
;
; Rules: the data must be in bank 1+ (e.g. $12000) or below $2000 - the boot MAP
; puts ROM over bank 0 $2000-$BFFF. Interrupts are off during the call (the frame
; IRQ is paused). The KERNAL overwrites base page $90-$FF and $0200-$03FF. On real
; hardware, test it there: KERNAL disk I/O from a taken-over machine is less proven
; than at boot (mega-simcity TODO.md).
;=======================================================================================

        .weak
KF_LOW          = $1800                 ; must be < $2000 and survive the KERNAL: not
                                        ; $0600-$07FF (the C65's sprite shapes live there)
                                        ; and not a screen
                                        ; RAM in use (lib/video_fcm: $0800-$17CF, $C800)
KF_DEVICE       = 8
        .endweak

kf_bank:        .byte 1
kf_start:       .word 0
kf_end:         .word 0

kfile_capture:
        lda $01
        sta l_kf_boot01
        lda $d030
        sta l_kf_bootd030
        ldx #0                          ; (more than 128 bytes: count up, not BPL down)
-       lda l_kf_src,x
        sta KF_LOW,x
        inx
        cpx #l_kf_size
        bne -
        rts

kfile_save:
        ldz #1                          ; operation: 1 = save, 0 = load
        bra l_kf_go
kfile_load:
        ldz #0
l_kf_go:
        stz l_kf_t_op
        ; name: "@0:" + name for a save (replace), plain for a load
        stx txt_ptr
        sty txt_ptr+1
        sta tmp1                        ; name length
        tay
        ldx #0
        lda l_kf_t_op
        beq +
        lda #'@'
        sta l_kf_t_name
        lda #'0'
        sta l_kf_t_name+1
        lda #':'
        sta l_kf_t_name+2
        ldx #3
+       stx tmp0
        tya
        clc
        adc tmp0
        sta l_kf_t_len
        ldy #0
-       cpy tmp1
        beq +
        lda (txt_ptr),y
        sta l_kf_t_name,x
        inx
        iny
        cpy #20
        bne -
+       lda kf_bank
        sta l_kf_t_bank
        lda kf_start
        sta l_kf_t_start
        lda kf_start+1
        sta l_kf_t_start+1
        lda kf_end
        sta l_kf_t_end
        lda kf_end+1
        sta l_kf_t_end+1
        lda l_kf_boot01
        sta l_kf_t_b01
        lda l_kf_bootd030
        sta l_kf_t_bd030
        jsr KF_LOW
        lda l_kf_t_end                  ; LOAD: the end address it returned
        sta kf_end
        lda l_kf_t_end+1
        sta kf_end+1
        lda #$ff                        ; the 40 MHz / KERNAL may have moved these
        sta CIA1_DDRA
        lda #0
        sta CIA1_DDRB
        lda l_kf_t_ok
        cmp #1                          ; carry set = error (ok = 0)
        rts

l_kf_boot01:    .byte $27
l_kf_bootd030:  .byte $64

; the trampoline (runs at KF_LOW)
l_kf_src:
        .logical KF_LOW
        php
        sei
        lda $01
        sta l_kf_t_g01
        lda $d030
        sta l_kf_t_gd030
        lda VIC_IRQ_MASK
        sta l_kf_t_girq
        lda #0
        sta VIC_IRQ_MASK                ; no frame IRQ while the KERNAL runs
        lda #$ff
        sta VIC_IRQ_STATUS
        lda #$00                        ; boot MAP: $2000-$7FFF and $8000-$BFFF,
        ldx #$e3                        ; $E000-$FFFF -> ROM bank 3
        ldy #$00
        ldz #$b3
        map
        eom
        lda l_kf_t_b01
        sta $01
        lda l_kf_t_bd030
        sta $d030
        cli
        lda l_kf_t_bank                 ; data bank, file name bank 0
        ldx #0
        jsr KERNAL_SETBNK
        lda #0
        ldx #KF_DEVICE
        ldy #0
        jsr KERNAL_SETLFS
        lda l_kf_t_len
        ldx #<l_kf_t_name
        ldy #>l_kf_t_name
        jsr KERNAL_SETNAM
        lda l_kf_t_op
        beq l_kf_t_load
        lda l_kf_t_start                ; SAVE: start pointer in base page $FB/$FC
        sta $fb
        lda l_kf_t_start+1
        sta $fc
        lda #$fb
        ldx l_kf_t_end
        ldy l_kf_t_end+1
        jsr KERNAL_SAVE
        bra l_kf_t_done
l_kf_t_load:
        lda #0
        ldx l_kf_t_start
        ldy l_kf_t_start+1
        jsr KERNAL_LOAD
        bcs l_kf_t_done
        stx l_kf_t_end
        sty l_kf_t_end+1
        clc
l_kf_t_done:
        sei
        lda #0
        rol                             ; carry -> ok flag (0 = success)
        sta l_kf_t_ok
        lda l_kf_t_gd030
        sta $d030
        lda l_kf_t_g01
        sta $01
        lda #0                          ; the game's MAP (none)
        tax
        tay
        taz
        map
        eom
        lda #$ff
        sta VIC_IRQ_STATUS
        lda l_kf_t_girq
        sta VIC_IRQ_MASK
        plp
        rts
l_kf_t_op:      .byte 0
l_kf_t_ok:      .byte 0
l_kf_t_bank:    .byte 0
l_kf_t_start:   .word 0
l_kf_t_end:     .word 0
l_kf_t_b01:     .byte 0
l_kf_t_bd030:   .byte 0
l_kf_t_g01:     .byte 0
l_kf_t_gd030:   .byte 0
l_kf_t_girq:    .byte 0
l_kf_t_len:     .byte 0
l_kf_t_name:    .fill 24
        .endlogical
l_kf_size = * - l_kf_src
        .cerror l_kf_size > 255, "kfile trampoline too big for the copy loop"
        .cerror KF_LOW + l_kf_size > $2000, "kfile trampoline must stay below $2000"
