;=======================================================================================
; lib/loader.asm - disk loading at boot (KERNAL), optional attic staging, HYPPO.
;
; Call these BEFORE #TAKEOVER, in the untouched BASIC65 state (KERNAL IRQ running, no
; custom MAP, 1 MHz-era $01/$D030). Needs lib/dma.asm for load_to_attic.
;
;   load_file      A = name length, X/Y = name (PETSCII; upper-case letters as in the
;                  directory), ld_dest = 24-bit chip-RAM address.
;                  Loads the file body (the 2-byte PRG header is skipped) to ld_dest,
;                  3 tries. Carry set on failure. ld_end = address after the last byte.
;   load_to_attic  same name args, ld_attic = 28-bit attic address (dword). Loads to
;                  LD_STAGE (chip RAM, <= LD_STAGE_MAX bytes per file) and DMAs it up.
;                  Carry set on failure; ld_len = bytes copied.
;   mount_d81      X/Y = zero-terminated ASCII file name of a D81 on the SD card (e.g.
;                  "DISK2.D81"), attached as drive 8 through HYPPO. Carry set on
;                  success. In Xemu, run with -hdosvirt -hdosdir <dir>.
;   print          A/Y = zero-terminated PETSCII string, via CHROUT
;
; Device: ld_device (default 8). Files bigger than one staging buffer: split them at
; build time (tools/m65assets.py write_parts does) and load each part to its offset.
;=======================================================================================

        .weak
LD_STAGE        = $50000                ; chip RAM staging buffer (bank 5)
LD_STAGE_MAX    = $F000
LD_NAMEBUF      = $1E00                 ; page aligned, below $7E00 (HYPPO rule)
        .endweak

ld_device:      .byte 8
ld_dest:        .fill 3
ld_end:         .fill 3
ld_attic:       .fill 4
ld_len:         .word 0
ld_tries:       .byte 0
l_ld_name:       .fill 3                 ; length, lo, hi

load_file:
        sta l_ld_name
        stx l_ld_name+1
        sty l_ld_name+2
        lda #3
        sta ld_tries
l_lf_try:
        lda ld_dest+2                   ; data bank
        ldx #0                          ; file name bank
        jsr KERNAL_SETBNK
        lda #0
        ldx ld_device
        ldy #0                          ; secondary 0: load to X/Y, skip the PRG header
        jsr KERNAL_SETLFS
        lda l_ld_name
        ldx l_ld_name+1
        ldy l_ld_name+2
        jsr KERNAL_SETNAM
        lda #0                          ; LOAD (not verify)
        ldx ld_dest
        ldy ld_dest+1
        jsr KERNAL_LOAD
        bcc +
        dec ld_tries
        bne l_lf_try
        sec
        rts
+       stx ld_end                      ; end address (bank as loaded)
        sty ld_end+1
        lda ld_dest+2
        sta ld_end+2
        clc
        rts

load_to_attic:
        pha
        lda #<LD_STAGE
        sta ld_dest
        lda #>LD_STAGE
        sta ld_dest+1
        lda #`LD_STAGE
        sta ld_dest+2
        pla
        jsr load_file
        bcs l_lta_out
        sec
        lda ld_end
        sbc #<LD_STAGE
        sta ld_len
        sta tmp5
        lda ld_end+1
        sbc #>LD_STAGE
        sta ld_len+1
        sta tmp5+1
        lda #<LD_STAGE
        sta ptr1
        lda #>LD_STAGE
        sta ptr1+1
        lda #`LD_STAGE
        sta ptr1+2
        lda #0
        sta ptr1+3
        ldx #3
-       lda ld_attic,x
        sta ptr2,x
        dex
        bpl -
        jsr dma_copy_far                ; splits at 1 MB boundaries
        clc
l_lta_out:
        rts

mount_d81:
        stx txt_ptr
        sty txt_ptr+1
        ldy #0
-       lda (txt_ptr),y
        sta LD_NAMEBUF,y
        beq +
        iny
        cpy #63
        bne -
        lda #0
        sta LD_NAMEBUF,y
+       ldy #>LD_NAMEBUF
        lda #HYPPO_SETNAME
        sta HTRAP00
        clv
        bcc l_md_fail
        lda #HYPPO_D81ATTACH0
        sta HTRAP00
        clv
        rts                             ; carry from HYPPO: set = attached
l_md_fail:
        clc
        rts

print:
        sta txt_ptr
        sty txt_ptr+1
        ldy #0
-       lda (txt_ptr),y
        beq +
        jsr KERNAL_CHROUT
        iny
        bne -
+       rts
