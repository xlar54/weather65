;=======================================================================================
; lib/unpack.asm - load zero-run packed files into attic RAM at boot (from archon65).
; Game graphics are mostly transparent zeros: packing them often halves the disk data
; and the KERNAL loading time.
;
;   load_packed_to_attic   A = name length, X/Y = name (as lib/loader.asm load_file),
;                  ld_attic = 28-bit attic address (dword), ld_len = unpacked length
;                  (<= 64 KB - 1). KERNAL-loads to LD_STAGE, unpacks into UNPACK_BUF,
;                  DMAs that up to the attic. Carry set on a load failure.
;   unpack         ptr0 -> ptr1 (32-bit pointers), tmp6 = unpacked length
;
; Format (tools/pack.py): $00 n = n zero bytes (n = 1-255), any other byte is itself.
; Call before #TAKEOVER, like the rest of lib/loader.asm (which it needs, with dma.asm).
;=======================================================================================

        .weak
UNPACK_BUF      = $40000                ; 64 KB of chip RAM free at boot (FB0 by default)
        .endweak

load_packed_to_attic:
        pha
        lda #<LD_STAGE
        sta ld_dest
        lda #>LD_STAGE
        sta ld_dest+1
        lda #`LD_STAGE
        sta ld_dest+2
        pla
        jsr load_file
        bcs _out
        lda #<LD_STAGE
        sta ptr0
        lda #>LD_STAGE
        sta ptr0+1
        lda #`LD_STAGE
        sta ptr0+2
        lda #0
        sta ptr0+3
        sta ptr1+3
        lda #<UNPACK_BUF
        sta ptr1
        lda #>UNPACK_BUF
        sta ptr1+1
        lda #`UNPACK_BUF
        sta ptr1+2
        lda ld_len
        sta tmp6
        lda ld_len+1
        sta tmp6+1
        jsr unpack
        ; UNPACK_BUF -> the attic
        lda #<UNPACK_BUF
        sta ptr1
        lda #>UNPACK_BUF
        sta ptr1+1
        lda #`UNPACK_BUF
        sta ptr1+2
        lda #0
        sta ptr1+3
        ldx #3
-       lda ld_attic,x
        sta ptr2,x
        dex
        bpl -
        lda ld_len
        sta tmp5
        lda ld_len+1
        sta tmp5+1
        jsr dma_copy_far
        clc
_out:   rts

unpack:
        ldz #0
_byte:  lda tmp6
        ora tmp6+1
        beq _out
        lda [ptr0],z
        inw ptr0
        cmp #0
        bne _lit
        lda [ptr0],z                    ; a run of zeros
        inw ptr0
        tax
        lda #0
-       sta [ptr1],z
        inw ptr1
        dew tmp6
        dex
        bne -
        bra _byte
_lit:   sta [ptr1],z
        inw ptr1
        dew tmp6
        bra _byte
_out:   rts
