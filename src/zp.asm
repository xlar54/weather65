;=======================================================================================
; Project base-page variables, after the library's (lib/zp.asm). Keep below $90: the
; KERNAL owns $90-$FF at boot and during kfile calls. mega-ip saves and restores what it
; borrows ($45-$48, $FB-$FE).
;=======================================================================================
        .virtual LIB_ZP_END
bp:             .dword ?                ; body read pointer (attic)
wp:             .dword ?                ; body write pointer (attic)
iout:           .dword ?                ; inflate output
isrc:           .dword ?                ; inflate match source, compositor source
dp0:            .dword ?                ; compositor / map destination
tptr:           .word ?                 ; string pointer (inline text, tb_str)
jkey:           .word ?                 ; json key
i_bitbuf:       .byte ?
i_bitcnt:       .byte ?
i_code:         .word ?
i_first:        .word ?
i_index:        .word ?
i_tmpw:         .word ?
i_tabp:         .word ?
i_tabq:         .word ?
nptr:           .word ?                 ; general table pointer
tb_addr:        .word ?                 ; text and URL buffer write pointer
zp_end:
        .endv
        .cerror zp_end > $90, "base page variables overflow into KERNAL space"
