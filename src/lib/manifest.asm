;=======================================================================================
; lib/manifest.asm - load every packed asset file listed in src/gen/manifest.asm into
; attic RAM. The manifest comes from tools/m65assets.py
; write_manifest; build.bat writes the files named in target/assets/files.txt to the D81.
;
;   load_manifest  each file goes to its attic address through lib/unpack.asm. Calls
;                  manifest_hook (if not 0) after each file, e.g. to print a dot. Carry set
;                  on a load failure, X = the file's index. Call before #TAKEOVER.
;
; Needs loader.asm, unpack.asm, dma.asm and an .include of "gen/manifest.asm".
;=======================================================================================

manifest_hook:  .word 0

load_manifest:
        lda #0
        sta l_mf_i
_next:  ldx l_mf_i
        cpx #asset_count
        beq _done
        lda asset_attic0,x
        sta ld_attic
        lda asset_attic1,x
        sta ld_attic+1
        lda asset_attic2,x
        sta ld_attic+2
        lda asset_attic3,x
        sta ld_attic+3
        lda asset_len_lo,x
        sta ld_len
        lda asset_len_hi,x
        sta ld_len+1
        lda asset_name_hi,x
        tay
        lda asset_name_lo,x
        pha
        lda asset_name_len,x
        plx
        jsr load_packed_to_attic
        bcs _fail
        lda manifest_hook
        ora manifest_hook+1
        beq +
        jsr l_mf_call
+       inc l_mf_i
        bra _next
_done:  clc
        rts
_fail:  ldx l_mf_i
        sec
        rts

l_mf_call:
        jmp (manifest_hook)

l_mf_i:         .byte 0
