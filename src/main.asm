;=======================================================================================
; Weather65 - a retro weather channel for the MEGA65, over its own Ethernet port.
; See README.md. Files: net (mega-ip + HTTP), weather (JSON + forecast), inflate (PNG),
; radar (map + loop), ui (screens).
;=======================================================================================
        .cpu "45gs02"
        .enc "ascii"                    ; strings are real ASCII: URLs and HTTP need it
        .cdef " ~", 32

        .weak
MOCK_NET        = 0                     ; -D MOCK_NET=1: replay captured responses (Xemu)
        .endweak

; Memory: mega-ip takes $42000-$47FFF and $50000-$515FF, so the framebuffers go in the ROM
; area, which is why the ROM has a copy in attic (see cfg_save).
FB0             = $20000
FB1             = $30000
FB_PIC          = $20000
FTEXT_FONT      = font_ram
FCM_CACHE       = $8100000
ROM_BACKUP      = $8200000

; which reply each kind of request replays (the order of the mockN files)
MOCK_FORECAST   = 0
MOCK_CITIES     = 1
MOCK_GEO        = 2
MOCK_RADAR      = 3

        .include "platform.asm"
        .include "lib/zp.asm"
        .include "zp.asm"

        * = $2001                       ; BASIC stub: BANK 0 : SYS 8210
        .word (+), 2026
        .byte $fe, $02, $30
        .byte ':'
        .byte $9e
        .text "8210"
        .byte 0
+       .word 0

        * = $2012
entry:
        cld
        ; real hardware's RAM is random at power-on
        ldx #$02
        lda #0
-       sta $00,x
        inx
        cpx #$90
        bne -
        jsr kfile_capture
        lda #<s_loading
        ldy #>s_loading
        jsr print
        lda #<dot_hook
        sta manifest_hook
        lda #>dot_hook
        sta manifest_hook+1
        jsr load_manifest
        bcc +
        lda #<s_diskerr
        ldy #>s_diskerr
        jsr print
-       jmp -
+       jsr cfg_load
        .if MOCK_NET != 0
        jsr mock_load_all
        .endif
        ; last, because the unpacker above uses bank 4 as its buffer
        lda #<MIP_LOAD
        sta ld_dest
        lda #>MIP_LOAD
        sta ld_dest+1
        lda #`MIP_LOAD
        sta ld_dest+2
        lda #s_ethbin_end-s_ethbin
        ldx #<s_ethbin
        ldy #>s_ethbin
        jsr load_file
        bcc +
        lda #<s_diskerr
        ldy #>s_diskerr
        jsr print
-       jmp -
+
        #TAKEOVER
        jsr bss_clear
        jsr font_copy
        jsr rom_backup
        jsr rom_unprotect
        jsr net_install
        jsr irq_install
        cli
        jsr dma_init
        jsr fcm_init
        jsr palette_load
        jsr fps_detect
        jsr font_patch
        jsr boot_begin
        jsr cfg_parse_pos
        jsr radar_view
        jsr tick_build

; ---------------------------------------------------------------------------------------
; Network up, location known, first data, then round and round
; ---------------------------------------------------------------------------------------
start_net:
        jsr net_setup
        bcc _up
        lda net_err
        sta last_fail
        lda #SCR_NODATA
        jsr screen_draw
        jsr tick_build
_wait:  jsr tick_step
        jsr fcm_present
        .if MOCK_NET == 0
        lda dbg_dns                     ; (test harness: try a DNS start without DHCP)
        beq +
        sec
        sbc #1
        sta http_host
        lda #0
        sta dbg_dns
        jsr dbg_dns_call
+
        .endif
        jsr key_get
        beq _wait
        and #$df
        cmp #'R'
        beq start_net
        cmp #'N'
        bne _wait
        lda #SCR_NET
        jsr screen_draw
        jsr key_wait
        lda #SCR_NODATA
        jsr screen_draw
        bra _wait
_up:    lda #1
        sta net_up
        lda cfg_lat
        bne _have
        jsr change_location
_have:  lda #0
        sta scr_cur
        jsr screen_loading
        jsr refresh_all
        jsr tick_build
        jsr show_current

main_loop:
        jsr net_tick
        jsr tick_step
        jsr net_tick                    ; (a different raster line: see net_pace)
        jsr fcm_present
        ; radar animation
        lda scr_now
        cmp #SCR_RADAR
        bne _noanim
        jsr radar_anim
_noanim:
        ; the clock: a new minute redraws the picture
        jsr clock_tick
        bcc +
        lda scr_now                     ; (the network screen stays until a key)
        cmp #SCR_NET
        bcs +
        jsr show_current
+       ; time for the next screen?
        lda scr_now
        cmp #SCR_NET
        bcs _notimer
        lda dbg_hold                    ; (test harness: stay on this screen)
        bne _notimer
        lda scr_timer
        bne +
        dec scr_timer+1
+       dec scr_timer
        lda scr_timer
        ora scr_timer+1
        bne _notimer
        jsr next_screen
_notimer:
        ; time for new data?
        lda refresh_timer
        bne +
        dec refresh_timer+1
+       dec refresh_timer
        lda refresh_timer
        ora refresh_timer+1
        bne +
        jsr refresh_all
        jsr tick_build
        jsr show_current
+       jsr key_get
        beq main_loop
        cmp #' '
        beq _next
        cmp #K_RIGHT
        beq _next
        cmp #K_LEFT
        beq _prev
        and #$df
        cmp #'R'
        beq _refresh
        cmp #'L'
        beq _loc
        cmp #'U'
        beq _unit
        cmp #'N'
        beq _net
        lda scr_now
        cmp #SCR_NET
        bne main_loop
        jsr show_current
        bra main_loop
_next:  jsr next_screen
        bra main_loop
_prev:  jsr prev_screen
        bra main_loop
_refresh:
        jsr refresh_all
        jsr tick_build
        jsr show_current
        bra main_loop
_loc:   jsr change_location
        bcs +
        jsr refresh_all
        jsr tick_build
+       jsr show_current
        bra main_loop
_unit:  lda cfg_unit
        eor #1
        sta cfg_unit
        jsr cfg_save
        jsr screen_loading
        jsr refresh_weather
        jsr refresh_cities
        jsr tick_build
        jsr show_current
        jmp main_loop
_net:   lda #SCR_NET
        jsr screen_draw
        jmp main_loop

scr_cur:        .byte 0
dbg_hold:       .byte 0
dbg_dns:        .byte 0
dbg_dns_kind:   .byte 0
dbg_a:          .fill 4
        .if MOCK_NET == 0
; test harness: the real send and receive paths, against a stack poked into "established".
; The request collects in the stack's queue and a planted reply comes out of its ring.
dbg_txrx:
        jsr url_reset
        #url_text "/probe?x=1"
        lda #1
        sta http_host
        jsr net_req_timer
        jsr http_request
        lda #0
        rol
        sta dbg_a                       ; carry: the send failed
        jsr http_begin
_rx:    lda #<RX_BUF
        ldx #>RX_BUF
        ldy #0
        ldz #RX_MAX
        #NET MIP_RECV_BLOCK
        cmp #0
        beq _done
        jsr http_feed_block
        bra _rx
_done:  rts
dbg_dns_call:
        lda dbg_dns_kind
        beq +
        lda #0
        sta dbg_dns_kind
        jmp dbg_txrx
+       lda http_host
        asl
        asl
        tax
        lda #0
        sta host_ip,x
        sta host_ip+1,x
        sta host_ip+2,x
        sta host_ip+3,x
        jmp net_resolve
        .endif
scr_timer:      .word 0
refresh_timer:  .word 0
last_fail:      .byte 0
net_up:         .byte 0
rd_anim_t:      .byte 0

SCR_SECONDS     = 12

; the screen in scr_cur, or the fallback when there is nothing to show
show_current:
        lda have_wx
        bne +
        lda #SCR_NODATA
        jmp screen_draw
+       lda scr_cur
        jsr screen_draw
        lda fps
        sta tmp4
        lda #0
        sta tmp4+1
        lda #SCR_SECONDS
        sta tmp5
        lda #0
        sta tmp5+1
        jsr mul16
        lda MULTOUT
        sta scr_timer
        lda MULTOUT+1
        sta scr_timer+1
        jsr mul_reset
        lda radar_last
        sta radar_show
        lda #60
        sta rd_anim_t
        rts

next_screen:
        lda scr_cur
_try:   clc
        adc #1
        cmp #SCR_COUNT
        bcc +
        lda #0
+       jsr scr_usable
        bcs _try
        sta scr_cur
        jmp show_current
prev_screen:
        lda scr_cur
_try:   sec
        sbc #1
        bpl +
        lda #SCR_COUNT-1
+       jsr scr_usable
        bcs _try
        sta scr_cur
        jmp show_current
; A = screen: carry set when it has nothing to show. A is kept.
scr_usable:
        cmp #SCR_RADAR
        bne _yes
        ldx radar_have
        bne _yes
        sec
        rts
_yes:   clc
        rts

; loop the radar: hold the newest frame longer
radar_anim:
        lda radar_have
        beq _o
        dec rd_anim_t
        bne _o
        lda radar_show
        ldy #RADAR_FRAMES               ; on to the next frame that arrived
_step:  clc
        adc #1
        cmp #RADAR_FRAMES
        bcc +
        lda #0
+       tax
        ldz radar_valid,x
        bne _found
        dey
        bne _step
        lda radar_last
_found: sta radar_show
        ldx #18
        cmp radar_last
        bne +
        ldx #70
+       stx rd_anim_t
        ; both buffers, or the ticker's flips would show the old frame
        jsr radar_to_back
        jsr header_clock
        jsr fcm_present
        jsr radar_to_back
        jmp header_clock
_o:     rts

; ---------------------------------------------------------------------------------------
; Fetching
; ---------------------------------------------------------------------------------------
REFRESH_SECONDS = 600

refresh_all:
        jsr refresh_weather
        jsr refresh_cities
        jsr refresh_radar
        jsr tick_build
        jmp refresh_timer_set

refresh_weather:
        lda #<msg_update
        ldx #>msg_update
        jsr status_show
        lda #0
        sta last_fail
        jsr weather_fetch
        bcc +
        lda net_err
        sta last_fail
+       jmp refresh_timer_set

refresh_cities:
        lda #<msg_cities
        ldx #>msg_cities
        jsr status_show
        jsr cities_fetch
        bcc +
        lda net_err
        sta last_fail
+       rts

refresh_radar:
        jsr radar_fetch
        bcc +
        lda net_err
        sta last_fail
+       rts

refresh_timer_set:
        lda fps
        sta tmp4
        lda #0
        sta tmp4+1
        lda #<REFRESH_SECONDS
        sta tmp5
        lda #>REFRESH_SECONDS
        sta tmp5+1
        jsr mul16
        lda MULTOUT
        sta refresh_timer
        lda MULTOUT+1
        sta refresh_timer+1
        jmp mul_reset

change_location:
        jsr setup_location
        bcs _out
        lda #<msg_saving
        ldx #>msg_saving
        jsr status_show
        jsr cfg_parse_pos
        jsr radar_view
        lda #0
        sta radar_base_ok
        sta radar_have
        sta have_wx
        sta scr_cur
        sta clock_valid                 ; (the old place's time)
        jsr cfg_save
        jsr screen_loading
        clc
_out:   rts

; ---------------------------------------------------------------------------------------
; The configuration file. Loading is at boot. Saving has to use the KERNAL, which lives
; in the ROM area the framebuffers took over, so: blank the display, put the ROM back from
; attic, save, then redraw. The screen goes dark for the second or two that takes.
; ---------------------------------------------------------------------------------------
CFG_STAGE       = $12000
s_cfgname:      .text "WXCONFIG"
s_cfgname_end:

cfg_load:
        lda #<CFG_STAGE
        sta ld_dest
        lda #>CFG_STAGE
        sta ld_dest+1
        lda #`CFG_STAGE
        sta ld_dest+2
        lda #s_cfgname_end-s_cfgname
        ldx #<s_cfgname
        ldy #>s_cfgname
        jsr load_file
        bcs _no
        lda #<CFG_STAGE
        sta ptr0
        lda #>CFG_STAGE
        sta ptr0+1
        lda #`CFG_STAGE
        sta ptr0+2
        lda #0
        sta ptr0+3
        ldz #0
        lda [ptr0],z
        cmp #'W'
        bne _no
        ldz #1
        lda [ptr0],z
        cmp #'X'
        bne _no
        ldz #0
-       lda [ptr0],z
        tax
        tza
        tay
        txa
        sta cfg,y
        inz
        cpz #CFG_SIZE
        bne -
_no:    rts

cfg_save:
        ; copy down below the KERNAL's reach
        lda #<CFG_STAGE
        sta ptr0
        lda #>CFG_STAGE
        sta ptr0+1
        lda #`CFG_STAGE
        sta ptr0+2
        lda #0
        sta ptr0+3
        ldy #0
        ldz #0
-       lda cfg,y
        sta [ptr0],z
        iny
        inz
        cpy #CFG_SIZE
        bne -
        ; dark
        lda VIC_CTRL1
        and #%01101111
        ora #(>IRQ_LINE) << 7
        sta VIC_CTRL1
        jsr rom_restore
        lda #1
        sta kf_bank
        lda #<CFG_STAGE
        sta kf_start
        lda #>CFG_STAGE
        sta kf_start+1
        lda #<(CFG_STAGE+CFG_SIZE)
        sta kf_end
        lda #>(CFG_STAGE+CFG_SIZE)
        sta kf_end+1
        lda #s_cfgname_end-s_cfgname
        ldx #<s_cfgname
        ldy #>s_cfgname
        jsr kfile_save
        lda #0
        rol
        sta cfg_save_err
        beq +
        lda #E_SAVE
        sta last_fail
+       ; both framebuffers hold ROM now: the background over one, shown (the display is still
        ; off), then copied to the other
        jsr bg_restore
        jsr screen_show
        lda VIC_CTRL1
        and #%01111111
        ora #%00010000 | (>IRQ_LINE) << 7
        sta VIC_CTRL1
        jsr mul_reset
        rts
cfg_save_err:   .byte 0

; the ROM area <-> attic, 32 KB at a time
rom_backup:
        lda #$00
        sta rc_dir
        bra rom_copy
rom_restore:
        lda #$01
        sta rc_dir
rom_copy:
        lda #0
        sta rc_i
_l:     ; address = $20000 + i * $8000
        lda rc_i
        lsr
        php
        clc
        adc #2
        sta tmp2                        ; bank
        lda #0
        plp
        ror                             ; $00 or $80
        sta tmp3                        ; high byte
        lda rc_dir
        bne _restore
        lda #0
        sta ptr1
        sta ptr2
        sta ptr1+3
        lda tmp3
        sta ptr1+1
        sta ptr2+1
        lda tmp2
        sta ptr1+2
        clc
        adc #`ROM_BACKUP-2
        sta ptr2+2
        lda #ROM_BACKUP >> 24
        sta ptr2+3
        bra _go
_restore:
        lda #0
        sta ptr1
        sta ptr2
        sta ptr2+3
        lda tmp3
        sta ptr1+1
        sta ptr2+1
        lda tmp2
        sta ptr2+2
        clc
        adc #`ROM_BACKUP-2
        sta ptr1+2
        lda #ROM_BACKUP >> 24
        sta ptr1+3
_go:    lda #<$8000
        sta tmp5
        lda #>$8000
        sta tmp5+1
        jsr dma_copy_far
        inc rc_i
        lda rc_i
        cmp #4
        bne _l
        rts
rc_dir: .byte 0
rc_i:   .byte 0

; ---------------------------------------------------------------------------------------
; Little setup jobs
; ---------------------------------------------------------------------------------------
dot_hook:
        lda #'.'
        jmp KERNAL_CHROUT

bss_clear:
        lda #<bss_start
        sta tmp4
        lda #>bss_start
        sta tmp4+1
        lda #<(bss_end-bss_start)
        sta tmp5
        lda #>(bss_end-bss_start)
        sta tmp5+1
        lda #0
        ldx #0
        ldy #0
        jmp dma_fill

; the 64 upper-case glyphs, out of the ROM before it's overwritten
font_copy:
        lda #<$29000
        sta ptr1
        lda #>$29000
        sta ptr1+1
        lda #`$29000
        sta ptr1+2
        lda #0
        sta ptr1+3
        lda #<font_ram
        sta ptr2
        lda #>font_ram
        sta ptr2+1
        lda #0
        sta ptr2+2
        sta ptr2+3
        lda #<512
        sta tmp5
        lda #>512
        sta tmp5+1
        jmp dma_copy_far

; '^' draws as a degree sign
font_patch:
        ldx #7
-       lda deg_glyph,x
        sta font_ram + 30 * 8,x
        dex
        bpl -
        rts
deg_glyph: .byte %00111000, %01101100, %01101100, %00111000, 0, 0, 0, 0

palette_load:
        ldx #0
-       lda palette_rgb,x
        jsr l_pal_swap
        sta $d100,x
        lda palette_rgb+256,x
        jsr l_pal_swap
        sta $d200,x
        lda palette_rgb+512,x
        jsr l_pal_swap
        sta $d300,x
        inx
        bne -
        rts

; bit 7 of $D06F = NTSC
fps_detect:
        lda #50
        bit $d06f
        bpl +
        lda #60
+       sta fps
        rts

s_loading:   .text "LOADING WEATHER65", 0
s_diskerr:   .byte 13
             .text "DISK ERROR", 0
s_ethbin:    .text "ETHBIN"
s_ethbin_end:

        .include "lib/system.asm"
        .include "lib/dma.asm"
        .include "lib/loader.asm"
        .include "lib/unpack.asm"
        .include "lib/manifest.asm"
        .include "lib/kfile.asm"
        .include "lib/keyboard.asm"
        .include "lib/video_fcm.asm"
        .include "lib/fcm_text.asm"
        .include "lib/fcm_cache.asm"
        .include "lib/draw.asm"
        .include "lib/vblit.asm"
        .include "lib/palette.asm"
        .include "lib/math.asm"
        .include "net.asm"
        .include "weather.asm"
        .include "inflate.asm"
        .include "radar.asm"
        .include "ui.asm"
        .include "gen/manifest.asm"
        .include "gen/palette.asm"
        .include "gen/icons.asm"

program_end:
        .cerror * > $c800, "program overflows SCREEN_C at $C800"

; ---- uninitialised memory: not in the PRG, cleared at boot ----
        .virtual *
bss_start:
font_ram:       .fill 512
pal_r:          .fill 256
pal_g:          .fill 256
pal_b:          .fill 256
pal_a:          .fill 256
pal_n:          .byte ?
ptype:          .fill 4
inf_lens:       .fill 512
inf_lcnt_lo:    .fill 16
inf_lcnt_hi:    .fill 16
inf_dcnt_lo:    .fill 16
inf_dcnt_hi:    .fill 16
inf_offs_lo:    .fill 17
inf_offs_hi:    .fill 17
inf_lsym_lo:    .fill 288
inf_lsym_hi:    .fill 288
inf_dsym_lo:    .fill 32
inf_dsym_hi:    .fill 32
geo_name:       .fill GEO_MAX * GEO_NAME
geo_reg:        .fill GEO_MAX * GEO_REG
geo_lat:        .fill GEO_MAX * GEO_NUM
geo_lon:        .fill GEO_MAX * GEO_NUM
bss_end:
        .endv
        .cerror bss_end > $c800, "memory overflows SCREEN_C at $C800"
