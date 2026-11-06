;=======================================================================================
; lib/zp.asm - base-page variables shared by the library routines.
;
; Lives in $02-$8F: the KERNAL still owns $90-$FF while a program loads files at boot.
; A project adds its own base-page variables after LIB_ZP_END (see src/zp.asm).
;=======================================================================================
        .virtual $02
ptr0:           .dword ?                ; 32-bit pointers for lda [ptr],z
ptr1:           .dword ?                ; dma_copy_far source
ptr2:           .dword ?                ; dma_copy_far destination
tmp0:           .byte ?                 ; scratch: any library call may change tmp0-tmp7
tmp1:           .byte ?
tmp2:           .byte ?
tmp3:           .byte ?
tmp4:           .word ?
tmp5:           .word ?                 ; byte counts for dma_copy_far / dma_fill
tmp6:           .word ?
tmp7:           .word ?
txt_ptr:        .word ?                 ; string pointer (print)
frame_count:    .byte ?                 ; +1 every frame (lib/system.asm IRQ)
joy:            .byte ?                 ; lib/input.asm: held now
joy_prev:       .byte ?                 ;   held last read
joy_new:        .byte ?                 ;   pressed since last read
; lib/video_fcm.asm + lib/blit.asm
flip_req:       .byte ?                 ; 0 none, 1 show A, 2 show B (done in the IRQ)
back_buf:       .byte ?                 ; buffer being drawn (0/1)
fb_bank:        .byte ?                 ; its chip-RAM bank
bs_id:          .byte ?                 ; blit_sprite arguments
bs_x:           .word ?
bs_y:           .word ?
bw0:            .byte ?
bsrc:           .dword ?
rstart:         .byte ?
rcount:         .byte ?
dyrow:          .word ?
cxl:            .word ?
; lib/fcm_text.asm
ftext_x:        .word ?                 ; text position (pixels)
ftext_str:      .word ?                 ; string being drawn
ftext_glyph:    .word ?                 ; font bitmap of the current character
ftext_fb:       .dword ?                ; framebuffer pointer for [ftext_fb],z
; lib/audio.asm streamer (IRQ only)
aptr:           .dword ?
rptr:           .dword ?
LIB_ZP_END:
        .endv
