;=======================================================================================
; ui.asm - the look of the thing: colours, background, text helpers, big text, ticker, screens.
;
; One screen is drawn into the back buffer once, shown, and copied to the other buffer. After
; that only the ticker strip changes: the two buffers stay identical above it.
;=======================================================================================

C_BLACK  = 0
C_WHITE  = 1
C_YELLOW = 2
C_LBLUE  = 3
C_ORANGE = 4
C_SHADOW = 5
C_GREY   = 6
C_RED    = 7
C_GREEN  = 8
C_STRIP  = 9
C_GRID   = 10
BG_BASE  = 16
HD_BASE  = 48

TICK_Y   = 188
STRIP_Y  = 184

; set the text position and colour
AT .macro x, y, col
        lda #<\x
        sta ftext_x
        lda #>\x
        sta ftext_x+1
        lda #\y
        sta ftext_y
        lda #\col
        sta ftext_col
.endmacro

; draw a literal
SAY .macro str
        jsr say_inline
        .null \str
.endmacro

say_inline:
        pla
        sta tptr
        pla
        sta tptr+1
        inw tptr                        ; rts stacked the last byte of the jsr
        lda tptr+1
        pha
        lda tptr
        pha                             ; (temporarily the string; fixed below)
        lda tptr
        ldx tptr+1
        jsr ftext_draw
        pla
        sta tptr
        pla
        sta tptr+1
        ldy #0
-       lda (tptr),y
        beq +
        inw tptr
        bra -
+       lda tptr+1
        pha
        lda tptr
        pha
        rts

; ---- URL buffer ----
url_buf: .fill 700
url_p:  .word 0
url_reset:
        lda #<url_buf
        sta url_p
        lda #>url_buf
        sta url_p+1
        lda #0
        sta url_buf
        rts
url_c:  phy
        ldy url_p
        sty tb_addr
        ldy url_p+1
        sty tb_addr+1
        ldy #0
        sta (tb_addr),y
        inc url_p
        bne +
        inc url_p+1
+       ldy url_p
        sty tb_addr
        ldy url_p+1
        sty tb_addr+1
        ldy #0
        pha
        lda #0
        sta (tb_addr),y
        pla
        ply
        rts
url_str:
        sta tptr
        stx tptr+1
        ldy #0
-       lda (tptr),y
        beq +
        jsr url_c
        iny
        bne -
+       rts
url_text .macro str
        jsr url_inline
        .null \str
.endmacro
url_inline:
        pla
        sta tptr
        pla
        sta tptr+1
_l:     inw tptr
        ldy #0
        lda (tptr),y
        beq _e
        jsr url_c
        bra _l
_e:     lda tptr+1
        pha
        lda tptr
        pha
        rts
; X:A -> decimal, no leading zeros
url_dec:
        jsr dec_digits
        ldx dec_n
-       dex
        lda dec_buf,x
        phx
        jsr url_c
        plx
        cpx #0
        bne -
        rts

; ---- number to digits: X:A -> dec_buf (reversed), dec_n ----
dec_buf: .fill 6
dec_n:  .byte 0
dec_v:  .word 0
dec_digits:
        sta dec_v
        stx dec_v+1
        lda #0
        sta dec_n
_l:     lda #0                          ; 16 / 10, by shifting: remainder in A
        ldy #16
_b:     asl dec_v
        rol dec_v+1
        rol
        cmp #10
        bcc +
        sbc #10
        inc dec_v
+       dey
        bne _b
        ora #'0'
        ldx dec_n
        sta dec_buf,x
        inc dec_n
        lda dec_v
        ora dec_v+1
        bne _l
        rts

; ---- the text buffer ----
tbuf:   .fill 420
tb_p:   .word 0
tb_reset:
        lda #<tbuf
        sta tb_p
        lda #>tbuf
        sta tb_p+1
        lda #0
        sta tbuf
        rts
; A = a character
tb_c:   phy
        ldy tb_p
        sty tb_addr
        ldy tb_p+1
        sty tb_addr+1
        ldy #0
        sta (tb_addr),y
        iny
        pha
        lda #0
        sta (tb_addr),y
        pla
        inc tb_p
        bne +
        inc tb_p+1
+       ply
        rts
tb_str: sta tptr
        stx tptr+1
        ldy #0
-       lda (tptr),y
        beq +
        jsr tb_c
        iny
        bne -
+       rts
tb_text .macro str
        jsr tb_inline
        .null \str
.endmacro
tb_inline:
        pla
        sta tptr
        pla
        sta tptr+1
_l:     inw tptr
        ldy #0
        lda (tptr),y
        beq _e
        jsr tb_c
        bra _l
_e:     lda tptr+1
        pha
        lda tptr
        pha
        rts
; X:A = signed
tb_int: cpx #$80
        bcc tb_uint
        sta tb_tmp
        lda #'-'
        jsr tb_c
        sec
        lda #0
        sbc tb_tmp
        sta tb_tmp
        txa
        eor #$ff
        adc #0
        tax
        lda tb_tmp
tb_uint:
        jsr dec_digits
        ldx dec_n
-       dex
        lda dec_buf,x
        jsr tb_c
        cpx #0
        bne -
        rts
tb_tmp: .byte 0
; A = 0..99, two digits
tb_02:  ldx #0
-       cmp #10
        bcc +
        sbc #10
        inx
        bra -
+       pha
        txa
        ora #'0'
        jsr tb_c
        pla
        ora #'0'
        jmp tb_c
tb_draw:
        lda #<tbuf
        ldx #>tbuf
        jmp ftext_draw
tb_unit_temp:
        lda #'^'
        jsr tb_c
        lda cfg_unit
        bne +
        lda #'F'
        jmp tb_c
+       lda #'C'
        jmp tb_c
tb_unit_speed:
        lda cfg_unit
        bne +
        #tb_text " MPH"
        rts
+       #tb_text " KM/H"
        rts
; A = hour, X = minute -> "5:29 PM"
tb_time:
        sta tb_h
        stx tb_m
        lda tb_h
        bne +
        lda #12
        bra _h
+       cmp #13
        bcc _h
        sec
        sbc #12
_h:     ldx #0
        jsr tb_uint
        lda #':'
        jsr tb_c
        lda tb_m
        jsr tb_02
        lda tb_h
        cmp #12
        bcs +
        #tb_text " AM"
        rts
+       #tb_text " PM"
        rts
; A = hour -> "5P"
tb_hour:
        sta tb_h
        lda tb_h
        bne +
        lda #12
        bra _h
+       cmp #13
        bcc _h
        sec
        sbc #12
_h:     ldx #0
        jsr tb_uint
        lda tb_h
        cmp #12
        bcs +
        lda #'A'
        jmp tb_c
+       lda #'P'
        jmp tb_c
tb_h:   .byte 0
tb_m:   .byte 0

; ---- big text: anti-aliased character sprites (src/assets/bigfont.png) ----
big_i:   .byte 0
big_y:   .byte 0

; tbuf at (ic_x, big_y). Digits, '-', '^' (degree), F and C.
big_draw:
        lda #0
        sta big_i
_ch:    ldx big_i
        lda tbuf,x
        bne +
        rts
+       ldy #10
        cmp #'-'
        beq _go
        iny
        cmp #'^'
        beq _go
        iny
        cmp #'F'
        beq _go
        iny
        cmp #'C'
        beq _go
        sec
        sbc #'0'
        cmp #10
        bcs _next                       ; anything else: skip it
        tay
_go:    sty big_g
        ; the sprite's anchor keeps its cell's left margin out: draw at x - margin
        sec
        lda ic_x
        sbc big_ox,y
        sta ic_x
        bcs +
        dec ic_x+1
+       tya
        clc
        adc #BIG_FIRST
        ldy big_y
        jsr icon_draw_w
        ldy big_g
        clc
        lda ic_x
        adc big_ox,y
        php
        clc
        adc big_adv,y
        sta ic_x
        lda ic_x+1
        adc #0
        plp
        adc #0
        sta ic_x+1
_next:  inc big_i
        bra _ch
big_g:  .byte 0

; ---- icons ----
; A = icon, X = x, Y = y (small icons are 10-19)
icon_draw:
        sta bs_id
        stx bs_x
        sty bs_y
        lda #0
        sta bs_x+1
        sta bs_y+1
        jsr mul_reset
        jmp vblit_sprite

; as icon_draw, with the x in ic_x
ic_x:   .word 0
icon_draw_w:
        sta bs_id
        sty bs_y
        lda ic_x
        sta bs_x
        lda ic_x+1
        sta bs_x+1
        lda #0
        sta bs_y+1
        jsr mul_reset
        jmp vblit_sprite

; ---- buffers ----
; show the back buffer, then bring the new back buffer up to the same picture
screen_show:
        jsr fcm_present
fb_sync_from_front:
        lda back_buf                    ; the front is the other one
        eor #1
        tax
        lda l_fs_front_bank,x
        sta ptr1+2
        lda #0
        sta ptr1
        sta ptr1+1
        sta ptr1+3
        sta ptr2
        sta ptr2+1
        sta ptr2+3
        lda fb_bank
        sta ptr2+2
        lda #<FB_SIZE
        sta tmp5
        lda #>FB_SIZE
        sta tmp5+1
        jmp dma_copy_far
l_fs_front_bank: .byte `FB0, `FB1

; ---- the background, in attic after its first use ----
BG_KEY = 1
bg_i:   .byte 0
bg_restore:
        lda #BG_KEY
        jsr cache_restore
        bcs +
        rts
+       ; 32 bands, 5 pixels each, from under the title band to the ticker
        lda #0
        sta bg_i
_b:     lda bg_i
        asl
        asl
        clc
        adc bg_i
        clc
        adc #24
        sta draw_y0
        lda #0
        sta draw_x0
        sta draw_x0+1
        lda #<320
        sta draw_w
        lda #>320
        sta draw_w+1
        lda #5
        sta draw_h
        lda bg_i
        clc
        adc #BG_BASE
        sta draw_col
        jsr draw_fill
        inc bg_i
        lda bg_i
        cmp #32
        bne _b
        ; the title band
        lda #0
        sta bg_i
_t:     lda bg_i
        asl
        sta draw_y0
        lda #0
        sta draw_x0
        sta draw_x0+1
        lda #<320
        sta draw_w
        lda #>320
        sta draw_w+1
        lda #2
        sta draw_h
        lda bg_i
        clc
        adc #HD_BASE
        sta draw_col
        jsr draw_fill
        inc bg_i
        lda bg_i
        cmp #12
        bne _t
        jsr strip_clear
        jmp cache_save

strip_clear:
        lda #0
        sta draw_x0
        sta draw_x0+1
        lda #STRIP_Y
        sta draw_y0
        lda #<320
        sta draw_w
        lda #>320
        sta draw_w+1
        lda #16
        sta draw_h
        lda #C_STRIP
        sta draw_col
        jmp draw_fill

; ---- the title band: A/X = the screen's title ----
header_draw:
        pha
        phx
        lda #C_SHADOW
        sta ftext_shadow
        #AT 4, 3, C_WHITE
        plx
        pla
        jsr ftext_draw
        #AT 4, 13, C_YELLOW
        lda #<cfg_name
        ldx #>cfg_name
        jsr ftext_draw
header_clock:
        lda clock_valid
        bne +
        rts
+       jsr tb_reset
        lda clock_h
        ldx clock_m
        jsr tb_time
        #AT 0, 3, C_WHITE
        jsr tb_draw_right
        jsr tb_reset
        ldx dy_wday
        jsr tb_day_name
        lda #' '
        jsr tb_c
        lda today_m
        ldx #0
        jsr tb_uint
        lda #'/'
        jsr tb_c
        lda today_d
        ldx #0
        jsr tb_uint
        #AT 0, 13, C_YELLOW
tb_draw_right:                          ; tbuf, ending at x = 316
        sec
        lda tb_p
        sbc #<tbuf
        asl
        asl
        asl
        sta tmp0
        sec
        lda #<316
        sbc tmp0
        sta ftext_x
        lda #>316
        sbc #0
        sta ftext_x+1
        jmp tb_draw

; the radar frames have no background of their own: a plain band
header_draw_radar:
        lda #0
        sta draw_x0
        sta draw_x0+1
        sta draw_y0
        lda #<320
        sta draw_w
        lda #>320
        sta draw_w+1
        lda #24
        sta draw_h
        lda #HD_BASE+6
        sta draw_col
        jsr draw_fill
        jsr strip_clear
        lda #C_SHADOW
        sta ftext_shadow
        #AT 4, 3, C_WHITE
        #SAY "LOCAL RADAR"
        #AT 4, 13, C_YELLOW
        lda #<cfg_name
        ldx #>cfg_name
        jmp ftext_draw

day_names: .text "SUNMONTUEWEDTHUFRISAT"
; X = weekday
tb_day_name:
        txa
        asl
        stx tb_tmp
        clc
        adc tb_tmp
        tax
        lda day_names,x
        jsr tb_c
        lda day_names+1,x
        jsr tb_c
        lda day_names+2,x
        jmp tb_c

; ---- the clock ----
clock_valid:    .byte 0
clock_h:        .byte 0
clock_m:        .byte 0
clock_s:        .byte 0
clock_frames:   .byte 0
fps:            .byte 50

; from the Date: header, in UTC, and the location's offset
clock_from_http:
        lda http_h
        cmp #$ff
        beq _out
        ; minutes of the day = h * 60 + m + tz, wrapped to 0..1439
        sta tmp4
        lda #0
        sta tmp4+1
        lda #60
        sta tmp5
        lda #0
        sta tmp5+1
        jsr mul16
        clc
        lda MULTOUT
        adc http_m
        sta tmp4
        lda MULTOUT+1
        adc #0
        sta tmp4+1
        jsr mul_reset
        clc
        lda tmp4
        adc tz_min
        sta tmp4
        lda tmp4+1
        adc tz_min+1
        sta tmp4+1
        bpl +
        clc
        lda tmp4
        adc #<1440
        sta tmp4
        lda tmp4+1
        adc #>1440
        sta tmp4+1
+
-       lda tmp4+1
        cmp #>1440
        bcc +
        bne _over
        lda tmp4
        cmp #<1440
        bcc +
_over:  sec
        lda tmp4
        sbc #<1440
        sta tmp4
        lda tmp4+1
        sbc #>1440
        sta tmp4+1
        bra -
+       lda #0
        sta clock_h
-       lda tmp4+1                      ; / 60
        bne _sub
        lda tmp4
        cmp #60
        bcc +
_sub:   sec
        lda tmp4
        sbc #60
        sta tmp4
        bcs _nd
        dec tmp4+1
_nd:    inc clock_h
        bra -
+       lda tmp4
        sta clock_m
        lda http_s
        sta clock_s
        lda #0
        sta clock_frames
        lda #1
        sta clock_valid
_out:   rts

; once a frame; carry set when the minute changed
clock_tick:
        lda clock_valid
        beq _no
        inc clock_frames
        lda clock_frames
        cmp fps
        bcc _no
        lda #0
        sta clock_frames
        inc clock_s
        lda clock_s
        cmp #60
        bcc _no
        lda #0
        sta clock_s
        inc clock_m
        lda clock_m
        cmp #60
        bcc _yes
        lda #0
        sta clock_m
        inc clock_h
        lda clock_h
        cmp #24
        bcc _yes
        lda #0
        sta clock_h
_yes:   sec
        rts
_no:    clc
        rts

; ---- the ticker ----
tick_x:   .word 320
tick_buf: .fill 420
tick_str: .word 0

tick_step:
        jsr strip_clear
        lda #0
        sta ftext_shadow
        lda #C_WHITE
        sta ftext_col
        lda #TICK_Y
        sta ftext_y
        lda tick_x
        sta ftext_x
        lda tick_x+1
        sta ftext_x+1
        lda #<tick_buf
        sta tick_str
        lda #>tick_buf
        sta tick_str+1
_ch:    ldy #0
        lda tick_str
        sta tb_addr
        lda tick_str+1
        sta tb_addr+1
        lda (tb_addr),y
        beq _end
        ldx ftext_x+1                   ; past the right edge: done
        cpx #$80
        bcs _draw
        cpx #2
        bcs _adv
        cpx #1
        bne _draw
        ldx ftext_x
        cpx #<320
        bcs _adv
_draw:  jsr ftext_char
        inc tick_str
        bne _ch
        inc tick_str+1
        bra _ch
_end:   lda ftext_x+1                   ; the whole text has left: start again
        cmp #$80
        bcc _adv
        lda #<320
        sta tick_x
        lda #>320
        sta tick_x+1
        rts
_adv:   lda tick_x
        bne +
        dec tick_x+1
+       dec tick_x
        rts

tick_build:
        jsr tb_reset
        lda last_fail
        beq +
        #tb_text "UPDATE FAILED: "
        ldx last_fail
        lda net_err_lo,x
        pha
        lda net_err_hi,x
        tax
        pla
        jsr tb_str
        #tb_text "    "
+       lda have_wx
        beq _noinfo
        lda #<cfg_name
        ldx #>cfg_name
        jsr tb_str
        #tb_text ": "
        lda cur_temp
        ldx cur_temp+1
        jsr tb_int
        jsr tb_unit_temp
        lda #' '
        jsr tb_c
        lda cur_code
        jsr wmo_string
        jsr tb_str
        #tb_text ". TODAY "
        lda dy_code
        jsr wmo_string
        jsr tb_str
        #tb_text ", HIGH "
        lda dy_hi_lo
        ldx dy_hi_hi
        jsr tb_int
        #tb_text " LOW "
        lda dy_lo_lo
        ldx dy_lo_hi
        jsr tb_int
        #tb_text ".    "
_noinfo:
        lda radar_ok
        beq _rok
        lda radar_got
        cmp #RADAR_FRAMES
        beq _rok
        #tb_text "RADAR: "
        lda radar_got
        ldx #0
        jsr tb_uint
        #tb_text " OF 6 FRAMES.    "
_rok:   #tb_text "SPACE NEXT   L LOCATION   U UNITS   R REFRESH   N NETWORK    "
        #tb_text "WEATHER DATA BY OPEN-METEO.COM.  RADAR FROM IOWA ENVIRONMENTAL MESONET."
        ldy #0
-       lda tbuf,y
        sta tick_buf,y
        beq +
        iny
        bne -
        lda #0
        sta tick_buf+255                ; (can't reach this with the text above)
+       ; the second page of a text over 255 bytes
        lda tb_p+1
        cmp #>tbuf
        beq _out
        ldy #0
-       lda tbuf+$100,y
        sta tick_buf+$100,y
        beq _out
        iny
        bne -
_out:   rts

; ---------------------------------------------------------------------------------------
; Status while fetching: a message in the strip of the visible picture
; ---------------------------------------------------------------------------------------
status_show:
        sta status_lo
        stx status_hi
        jsr strip_clear
        #AT 4, TICK_Y, C_YELLOW
        lda #0
        sta ftext_shadow
        lda status_lo
        ldx status_hi
        jsr ftext_draw
        jmp screen_show
status_lo: .byte 0
status_hi: .byte 0

; as status_show, with the radar frame number added
status_frame:
        pha
        phx
        jsr tb_reset
        plx
        pla
        jsr tb_str
        lda radar_i
        clc
        adc #'1'
        jsr tb_c
        #tb_text " OF 6"
        lda #<tbuf
        ldx #>tbuf
        jmp status_show

; ---------------------------------------------------------------------------------------
; A plain message screen and the boot log
; ---------------------------------------------------------------------------------------
boot_y: .byte 40

boot_begin:
        jsr bg_restore
        lda #C_SHADOW
        sta ftext_shadow
        #AT 104, 6, C_WHITE
        #SAY "WEATHER65"
        lda #40
        sta boot_y
        jmp screen_show

; A/X = a line, added to the log
boot_line:
        pha
        phx
        lda #C_SHADOW
        sta ftext_shadow
        #AT 16, 0, C_WHITE
        lda boot_y
        sta ftext_y
        plx
        pla
        jsr ftext_draw
        clc
        lda boot_y
        adc #11
        sta boot_y
        jmp screen_show

; while there's nothing to show: the background, the place, and a status line below
screen_loading:
        jsr bg_restore
        lda #<t_loading
        ldx #>t_loading
        jsr header_draw
        #AT 0, 84, C_LBLUE
        lda #<t_loading2
        ldx #>t_loading2
        jsr ftext_centre
        #AT 0, 100, C_YELLOW
        lda #<cfg_name
        ldx #>cfg_name
        jsr ftext_centre
        jmp screen_show
t_loading:  .null "WEATHER65"
t_loading2: .null "GETTING THE LATEST WEATHER FOR"

msg_loading:  .null "LOADING"
msg_ethstart: .null "STARTING ETHERNET..."
msg_dhcp:     .null "ASKING FOR AN ADDRESS (DHCP)..."
msg_update:   .null "UPDATING FORECAST..."
msg_cities:   .null "UPDATING CITIES..."
msg_radar:    .null "FETCHING RADAR FRAME "
msg_search:   .null "SEARCHING..."
msg_saving:   .null "SAVING..."

; ---------------------------------------------------------------------------------------
; The screens
; ---------------------------------------------------------------------------------------
SCR_CURRENT = 0
SCR_HOURLY  = 1
SCR_DAILY   = 2
SCR_CITIES  = 3
SCR_ALMANAC = 4
SCR_RADAR   = 5
SCR_COUNT   = 6
SCR_NET     = 6
SCR_NODATA  = 7

scr_lo: .byte <scr_current,<scr_hourly,<scr_daily,<scr_cities,<scr_almanac,<scr_radar,<scr_net,<scr_nodata
scr_hi: .byte >scr_current,>scr_hourly,>scr_daily,>scr_cities,>scr_almanac,>scr_radar,>scr_net,>scr_nodata

; draw screen A into the back buffer and show it
screen_draw:
        sta scr_now
        tax
        lda scr_lo,x
        sta _j+1
        lda scr_hi,x
        sta _j+2
        jsr bg_restore
_j:     jsr $ffff
        jmp screen_show
scr_now: .byte 0

; a label + value pair, at x, y
LABEL .macro x, y, str
        #AT \x, \y, C_LBLUE
        #SAY \str
.endmacro

scr_current:
        lda #<t_current
        ldx #>t_current
        jsr header_draw
        lda cur_code
        jsr wmo_icon_of
        ldx cur_isday
        bne +
        cmp #2                          ; at night, the moon replaces the sun
        bcs +
        clc
        adc #8
+       ldx #20
        ldy #32
        jsr icon_draw
        ; the temperature, big
        jsr tb_reset
        lda cur_temp
        ldx cur_temp+1
        jsr tb_int
        jsr tb_unit_temp
        lda #<116
        sta ic_x
        lda #>116
        sta ic_x+1
        lda #28
        sta big_y
        jsr big_draw
        ; the words
        #AT 16, 84, C_YELLOW
        lda cur_code
        jsr wmo_string
        jsr ftext_draw
        #AT 192, 84, C_LBLUE
        jsr tb_reset
        #tb_text "FEELS LIKE "
        lda cur_feels
        ldx cur_feels+1
        jsr tb_int
        jsr tb_unit_temp
        jsr tb_draw
        ; the table
        #LABEL 16, 104, "HUMIDITY"
        #AT 96, 104, C_WHITE
        jsr tb_reset
        lda cur_rh
        ldx #0
        jsr tb_uint
        lda #'%'
        jsr tb_c
        jsr tb_draw
        #LABEL 16, 118, "PRESSURE"
        #AT 96, 118, C_WHITE
        jsr tb_reset
        lda cur_press
        ldx cur_press+1
        jsr tb_uint
        #tb_text " HPA"
        jsr tb_draw
        #LABEL 16, 132, "RAIN"
        #AT 96, 132, C_WHITE
        jsr tb_reset
        lda dy_pop
        ldx #0
        jsr tb_uint
        lda #'%'
        jsr tb_c
        jsr tb_draw
        #LABEL 176, 104, "WIND"
        #AT 224, 104, C_WHITE
        jsr tb_reset
        jsr tb_wind_dir
        lda #' '
        jsr tb_c
        lda cur_wind
        ldx #0
        jsr tb_uint
        jsr tb_unit_speed
        jsr tb_draw
        #LABEL 176, 118, "GUSTS"
        #AT 224, 118, C_WHITE
        jsr tb_reset
        lda cur_gust
        ldx #0
        jsr tb_uint
        jsr tb_unit_speed
        jsr tb_draw
        #LABEL 176, 132, "HI/LO"
        #AT 224, 132, C_WHITE
        jsr tb_reset
        lda dy_hi_lo
        ldx dy_hi_hi
        jsr tb_int
        lda #'/'
        jsr tb_c
        lda dy_lo_lo
        ldx dy_lo_hi
        jsr tb_int
        jsr tb_unit_temp
        jsr tb_draw
        #AT 16, 156, C_YELLOW
        jsr tb_reset
        #tb_text "SUNRISE "
        lda dy_rise_h
        ldx dy_rise_m
        jsr tb_time
        #tb_text "    SUNSET "
        lda dy_set_h
        ldx dy_set_m
        jsr tb_time
        jmp tb_draw

wind_names: .text "N NEE E SES S SWW NWN "
tb_wind_dir:
        ; 8 points: (deg + 22) / 45
        clc
        lda cur_dir
        adc #22
        sta tmp4
        lda cur_dir+1
        adc #0
        sta tmp4+1
        ldx #0
-       lda tmp4+1
        bne _s
        lda tmp4
        cmp #45
        bcc +
_s:     sec
        lda tmp4
        sbc #45
        sta tmp4
        bcs _n
        dec tmp4+1
_n:     inx
        bra -
+       txa
        and #7
        asl
        tax
        lda wind_names,x
        jsr tb_c
        lda wind_names+1,x
        cmp #' '
        beq +
        jsr tb_c
+       rts

; ---- the next 12 hours: a graph ----
HG_TOP = 64
HG_H   = 52
hg_min: .word 0
hg_max: .word 0
hg_i:   .byte 0
hg_x:   .word 0
hg_y:   .fill HOURS

scr_hourly:
        lda #<t_hourly
        ldx #>t_hourly
        jsr header_draw
        ; the temperature range
        lda hr_temp_lo
        sta hg_min
        sta hg_max
        lda hr_temp_hi
        sta hg_min+1
        sta hg_max+1
        ldx #1
_rng:   lda hr_temp_lo,x                ; signed compare with min
        sec
        sbc hg_min
        lda hr_temp_hi,x
        sbc hg_min+1
        bvc +
        eor #$80
+       bpl +
        lda hr_temp_lo,x
        sta hg_min
        lda hr_temp_hi,x
        sta hg_min+1
+       lda hg_max
        sec
        sbc hr_temp_lo,x
        lda hg_max+1
        sbc hr_temp_hi,x
        bvc +
        eor #$80
+       bpl +
        lda hr_temp_lo,x
        sta hg_max
        lda hr_temp_hi,x
        sta hg_max+1
+       inx
        cpx #HOURS
        bne _rng
        ; y for each hour: top + (max - t) * height / range
        sec
        lda hg_max
        sbc hg_min
        bne +
        lda #1
+       sta hg_range
        ldx #0
        stx hg_i
_ys:    ldx hg_i
        sec
        lda hg_max
        sbc hr_temp_lo,x
        sta tmp4
        lda #0
        sta tmp4+1
        lda #HG_H
        sta tmp5
        lda #0
        sta tmp5+1
        jsr mul16
        lda MULTOUT
        sta tmp4
        lda MULTOUT+1
        sta tmp4+1
        lda hg_range
        sta tmp5
        lda #0
        sta tmp5+1
        jsr div16
        ldx hg_i
        lda tmp6
        clc
        adc #HG_TOP
        sta hg_y,x
        inc hg_i
        lda hg_i
        cmp #HOURS
        bne _ys
        jsr mul_reset
        ; the grid
        lda #C_GRID
        sta draw_col
        lda #<20
        sta draw_x0
        lda #0
        sta draw_x0+1
        lda #HG_TOP
        sta draw_y0
        lda #<288
        sta draw_w
        lda #>288
        sta draw_w+1
        jsr draw_hline
        lda #HG_TOP+HG_H
        sta draw_y0
        jsr draw_hline
        ; each hour: the line, the dot, the labels, the rain bar
        lda #0
        sta hg_i
_h:     ldx hg_i
        lda hg_xs,x
        sta hg_x
        lda hg_xh,x
        sta hg_x+1
        ; the line from the previous hour
        cpx #0
        beq _noline
        lda hg_xs-1,x
        sta draw_x0
        lda hg_xh-1,x
        sta draw_x0+1
        lda hg_y-1,x
        sta draw_y0
        lda hg_x
        sta draw_x1
        lda hg_x+1
        sta draw_x1+1
        lda hg_y,x
        sta draw_y1
        lda #C_YELLOW
        sta draw_col
        jsr draw_line
_noline:
        ; the dot
        ldx hg_i
        sec
        lda hg_x
        sbc #1
        sta draw_x0
        lda hg_x+1
        sbc #0
        sta draw_x0+1
        lda hg_y,x
        sec
        sbc #1
        sta draw_y0
        lda #3
        sta draw_w
        lda #0
        sta draw_w+1
        lda #3
        sta draw_h
        lda #C_WHITE
        sta draw_col
        jsr draw_fill
        ; every other hour: its label and temperature
        lda hg_i
        and #1
        bne _noT
        ldx hg_i
        sec
        lda hg_x
        sbc #8
        sta ftext_x
        lda hg_x+1
        sbc #0
        sta ftext_x+1
        sec
        lda hg_y,x
        sbc #11
        sta ftext_y
        lda #C_WHITE
        sta ftext_col
        jsr tb_reset
        ldx hg_i
        lda hr_temp_lo,x
        pha
        lda hr_temp_hi,x
        tax
        pla
        jsr tb_int
        jsr tb_draw
        ldx hg_i
        sec
        lda hg_x
        sbc #8
        sta ftext_x
        lda hg_x+1
        sbc #0
        sta ftext_x+1
        lda #HG_TOP+HG_H+5
        sta ftext_y
        lda #C_LBLUE
        sta ftext_col
        jsr tb_reset
        ldx hg_i
        lda hr_hour,x
        jsr tb_hour
        jsr tb_draw
_noT:
        ; the chance of rain: a bar growing up from the bottom
        ldx hg_i
        lda hr_pop,x
        lsr
        lsr
        beq _nobar
        sta draw_h
        sta tmp3
        sec
        lda #176
        sbc tmp3
        sta draw_y0
        sec
        lda hg_x
        sbc #5
        sta draw_x0
        lda hg_x+1
        sbc #0
        sta draw_x0+1
        lda #11
        sta draw_w
        lda #0
        sta draw_w+1
        lda #C_ORANGE
        sta draw_col
        jsr draw_fill
_nobar:
        inc hg_i
        lda hg_i
        cmp #HOURS
        beq +
        jmp _h
+       ; icons along the top, every third hour
        lda #0
        sta hg_i
_ic:    ldx hg_i
        lda hr_code,x
        jsr wmo_icon_of
        clc
        adc #10
        pha
        ldx hg_i
        sec
        lda hg_xs,x
        sbc #16
        sta ic_x
        lda hg_xh,x
        sbc #0
        sta ic_x+1
        pla
        ldy #26
        jsr icon_draw_w
        clc
        lda hg_i
        adc #3
        sta hg_i
        cmp #HOURS
        bcc _ic
        #AT 4, 148, C_LBLUE
        #SAY "RAIN"
        rts
hg_range: .byte 1
HG_X = [30,54,78,102,126,150,174,198,222,246,270,294]
hg_xs:  .byte <HG_X
hg_xh:  .byte >HG_X

; ---- the week ----
scr_daily:
        lda #<t_daily
        ldx #>t_daily
        jsr header_draw
        lda #0
        sta hg_i
_d:     ldx hg_i
        lda dy_cx,x
        sta hg_x
        lda dy_ch,x
        sta hg_x+1
        lda #C_GRID
        sta draw_col
        lda hg_i
        beq _nosep
        sec
        lda hg_x
        sbc #1
        sta draw_x0
        lda hg_x+1
        sbc #0
        sta draw_x0+1
        lda #30
        sta draw_y0
        lda #120
        sta draw_h
        jsr draw_vline
_nosep: ldx hg_i
        clc
        lda hg_x
        adc #10
        sta ftext_x
        lda hg_x+1
        adc #0
        sta ftext_x+1
        lda #32
        sta ftext_y
        lda #C_YELLOW
        sta ftext_col
        jsr tb_reset
        ldx hg_i
        lda dy_wday,x
        tax
        jsr tb_day_name
        jsr tb_draw
        ; the icon
        ldx hg_i
        lda dy_code,x
        jsr wmo_icon_of
        clc
        adc #10
        pha
        clc
        lda hg_x
        adc #6
        sta ic_x
        lda hg_x+1
        adc #0
        sta ic_x+1
        pla
        ldy #46
        jsr icon_draw_w
        ; high, low, chance of rain
        clc
        lda hg_x
        adc #10
        sta ftext_x
        lda hg_x+1
        adc #0
        sta ftext_x+1
        lda #80
        sta ftext_y
        lda #C_WHITE
        sta ftext_col
        jsr tb_reset
        ldx hg_i
        lda dy_hi_lo,x
        pha
        lda dy_hi_hi,x
        tax
        pla
        jsr tb_int
        lda #'^'
        jsr tb_c
        jsr tb_draw
        clc
        lda hg_x
        adc #10
        sta ftext_x
        lda hg_x+1
        adc #0
        sta ftext_x+1
        lda #96
        sta ftext_y
        lda #C_LBLUE
        sta ftext_col
        jsr tb_reset
        ldx hg_i
        lda dy_lo_lo,x
        pha
        lda dy_lo_hi,x
        tax
        pla
        jsr tb_int
        lda #'^'
        jsr tb_c
        jsr tb_draw
        clc
        lda hg_x
        adc #10
        sta ftext_x
        lda hg_x+1
        adc #0
        sta ftext_x+1
        lda #118
        sta ftext_y
        lda #C_ORANGE
        sta ftext_col
        jsr tb_reset
        ldx hg_i
        lda dy_pop,x
        ldx #0
        jsr tb_uint
        lda #'%'
        jsr tb_c
        jsr tb_draw
        inc hg_i
        lda hg_i
        cmp #DAYS
        beq +
        jmp _d
+       #AT 4, 134, C_ORANGE
        #SAY "RAIN"
        #AT 4, 160, C_YELLOW
        jsr tb_reset
        #tb_text "TODAY: "
        lda dy_code
        jsr wmo_string
        jsr tb_str
        jmp tb_draw
DY_X = [2,47,92,137,182,227,272]
dy_cx:  .byte <DY_X
dy_ch:  .byte >DY_X

; ---- the cities ----
scr_cities:
        lda #<t_cities
        ldx #>t_cities
        jsr header_draw
        #AT 120, 28, C_LBLUE
        #SAY "HI  LO"
        lda have_cities
        bne +
        #AT 16, 80, C_WHITE
        #SAY "NO CITY DATA YET"
        rts
+       lda #<city_names
        sta city_p
        lda #>city_names
        sta city_p+1
        lda #0
        sta hg_i
_c:     lda hg_i                        ; y = 40 + i * 14
        asl
        asl
        asl
        sta tmp0
        lda hg_i
        asl
        asl
        clc
        adc tmp0
        sta tmp0
        lda hg_i
        asl
        clc
        adc tmp0
        clc
        adc #40
        sta hg_row
        #AT 8, 0, C_YELLOW
        lda hg_row
        sta ftext_y
        lda city_p
        ldx city_p+1
        jsr ftext_draw
        lda city_p                      ; on to the next name
        sta tptr
        lda city_p+1
        sta tptr+1
        ldy #0
-       lda (tptr),y
        beq +
        inw tptr
        bra -
+       inw tptr
        lda tptr
        sta city_p
        lda tptr+1
        sta city_p+1
        #AT 120, 0, C_WHITE
        lda hg_row
        sta ftext_y
        jsr tb_reset
        ldx hg_i
        lda city_hi_lo,x
        pha
        lda city_hi_hi,x
        tax
        pla
        jsr tb_int
        jsr tb_draw
        #AT 152, 0, C_LBLUE
        lda hg_row
        sta ftext_y
        jsr tb_reset
        ldx hg_i
        lda city_lo_lo,x
        pha
        lda city_lo_hi,x
        tax
        pla
        jsr tb_int
        jsr tb_draw
        #AT 184, 0, C_WHITE
        lda hg_row
        sta ftext_y
        ldx hg_i
        lda city_code,x
        jsr wmo_string
        jsr ftext_draw
        inc hg_i
        lda hg_i
        cmp #CITIES
        beq +
        jmp _c
+       rts
city_p: .word 0
hg_row: .byte 0

; ---- sun and moon ----
scr_almanac:
        lda #<t_almanac
        ldx #>t_almanac
        jsr header_draw
        #AT 120, 34, C_YELLOW
        #SAY "SUNRISE"
        #AT 216, 34, C_YELLOW
        #SAY "SUNSET"
        #LABEL 16, 48, "TODAY"
        #LABEL 16, 62, "TOMORROW"
        lda #0
        sta hg_i
_s:     #AT 120, 48, C_WHITE
        ldx hg_i
        lda alm_y,x
        sta ftext_y
        jsr tb_reset
        ldx hg_i
        lda dy_rise_h,x
        pha
        lda dy_rise_m,x
        tax
        pla
        jsr tb_time
        jsr tb_draw
        #AT 216, 48, C_WHITE
        ldx hg_i
        lda alm_y,x
        sta ftext_y
        jsr tb_reset
        ldx hg_i
        lda dy_set_h,x
        pha
        lda dy_set_m,x
        tax
        pla
        jsr tb_time
        jsr tb_draw
        inc hg_i
        lda hg_i
        cmp #2
        bne _s
        ; daylight today
        #LABEL 16, 84, "DAYLIGHT"
        #AT 120, 84, C_WHITE
        jsr tb_reset
        sec
        lda dy_set_h
        sbc dy_rise_h
        sta tmp0
        sec
        lda dy_set_m
        sbc dy_rise_m
        bcs +
        adc #60
        dec tmp0
+       sta tmp1
        lda tmp0
        ldx #0
        jsr tb_uint
        #tb_text " HR "
        lda tmp1
        pha
        ldx #0
        pla
        jsr tb_uint
        #tb_text " MIN"
        jsr tb_draw
        ; the moon
        #LABEL 16, 112, "MOON"
        jsr moon_phase
        sta alm_phase
        tax
        lda moon_lo,x
        pha
        lda moon_hi,x
        tax
        pla
        pha
        phx
        #AT 120, 112, C_WHITE
        plx
        pla
        jsr ftext_draw
        jmp moon_draw
alm_y:  .byte 48, 62
alm_phase: .byte 0
moon_lo: .byte <m0,<m1,<m2,<m3,<m4,<m5,<m6,<m7
moon_hi: .byte >m0,>m1,>m2,>m3,>m4,>m5,>m6,>m7
m0:     .null "NEW MOON"
m1:     .null "WAXING CRESCENT"
m2:     .null "FIRST QUARTER"
m3:     .null "WAXING GIBBOUS"
m4:     .null "FULL MOON"
m5:     .null "WANING GIBBOUS"
m6:     .null "LAST QUARTER"
m7:     .null "WANING CRESCENT"

; a disc lit according to the phase: dark disc, lit disc, dark disc offset to shape it
moon_draw:
        lda #<64
        sta draw_x0
        lda #0
        sta draw_x0+1
        lda #142
        sta draw_y0
        lda #16
        sta draw_r
        lda #C_SHADOW
        sta draw_col
        ldx alm_phase
        bne +
        jmp draw_disc                   ; new: only the dark disc
+       lda #C_WHITE
        sta draw_col
        jsr draw_disc
        ldx alm_phase
        lda moon_off,x
        beq _o                          ; full
        clc
        adc #64
        sta draw_x0
        lda moon_off,x
        bpl +
        lda #<64
        clc
        adc moon_off,x
        sta draw_x0
+       lda #0
        sta draw_x0+1
        lda #142
        sta draw_y0
        lda #16
        sta draw_r
        lda #C_SHADOW
        sta draw_col
        jsr draw_disc
_o:     rts
; the dark disc's offset per phase, in pixels: negative on the left when waxing
moon_off: .char 0, -10, -16, -24, 0, 24, 16, 10

; ---- radar: the first frame; the main loop animates the rest ----
scr_radar:
        lda radar_last
        sta radar_show
        jmp radar_to_back

; ---- network information ----
ip_print:
        pha
        phx
        phy
        tza
        sta tb_tmp2
        jsr tb_reset
        ply
        plx
        pla
        sta tb_ip
        stx tb_ip+1
        sty tb_ip+2
        lda tb_tmp2
        sta tb_ip+3
        ldy #0
_l:     phy
        lda tb_ip,y
        ldx #0
        jsr tb_uint
        ply
        iny
        cpy #4
        beq +
        lda #'.'
        jsr tb_c
        bra _l
+       jmp tb_draw
tb_tmp2: .byte 0
tb_ip:  .fill 4

scr_net:
        lda #<t_net
        ldx #>t_net
        jsr header_draw
        #LABEL 16, 34, "ADDRESS"
        .if MOCK_NET == 0
        #NET_A MIP_GET_LOCAL_IP
        .else
        lda #0
        tax
        tay
        taz
        .endif
        pha
        phx
        #AT 112, 34, C_WHITE
        plx
        pla
        jsr ip_print
        #LABEL 16, 46, "GATEWAY"
        .if MOCK_NET == 0
        #NET_A MIP_GET_GATEWAY
        .else
        lda #0
        tax
        tay
        taz
        .endif
        pha
        phx
        #AT 112, 46, C_WHITE
        plx
        pla
        jsr ip_print
        #LABEL 16, 58, "DNS"
        .if MOCK_NET == 0
        #NET_A MIP_GET_DNS
        .else
        lda #0
        tax
        tay
        taz
        .endif
        pha
        phx
        #AT 112, 58, C_WHITE
        plx
        pla
        jsr ip_print
        #LABEL 16, 76, "LAST CODE"
        #AT 112, 76, C_WHITE
        jsr tb_reset
        lda http_code
        ldx http_code+1
        jsr tb_uint
        jsr tb_draw
        #LABEL 16, 88, "LAST SIZE"
        #AT 112, 88, C_WHITE
        jsr tb_reset
        lda http_len
        ldx http_len+1
        jsr tb_uint
        #tb_text " BYTES"
        jsr tb_draw
        #LABEL 16, 100, "FETCHES OK"
        #AT 112, 100, C_WHITE
        jsr tb_reset
        lda net_ok_count
        ldx net_ok_count+1
        jsr tb_uint
        jsr tb_draw
        #LABEL 16, 112, "FAILED"
        #AT 112, 112, C_WHITE
        jsr tb_reset
        lda net_fail_count
        ldx net_fail_count+1
        jsr tb_uint
        jsr tb_draw
        #LABEL 16, 130, "LAST ERROR"
        #AT 112, 130, C_YELLOW
        ldx last_fail
        lda net_err_lo,x
        pha
        lda net_err_hi,x
        tax
        pla
        jsr ftext_draw
        lda radar_ok
        beq _nora
        #LABEL 16, 142, "RADAR"
        #AT 112, 142, C_WHITE
        jsr tb_reset
        lda radar_got
        ldx #0
        jsr tb_uint
        #tb_text "/6  ERR"
        ldy #0
_re:    phy
        lda #' '
        jsr tb_c
        ply
        phy
        lda radar_err,y
        ldx #0
        jsr tb_uint
        ply
        iny
        cpy #RADAR_FRAMES
        bne _re
        jsr tb_draw
_nora:  #AT 16, 156, C_LBLUE
        #SAY "ANY KEY TO GO BACK"
        rts

; ---- nothing to show yet ----
scr_nodata:
        lda #<t_nodata
        ldx #>t_nodata
        jsr header_draw
        #AT 16, 60, C_YELLOW
        ldx last_fail
        lda net_err_lo,x
        pha
        lda net_err_hi,x
        tax
        pla
        jsr ftext_draw
        #AT 16, 84, C_WHITE
        #SAY "R TO TRY AGAIN"
        #AT 16, 96, C_WHITE
        #SAY "N FOR NETWORK DETAILS"
        lda net_up                      ; searching for a place needs the network
        beq +
        #AT 16, 108, C_WHITE
        #SAY "L TO CHANGE LOCATION"
+       rts

t_current: .null "CURRENT CONDITIONS"
t_hourly:  .null "NEXT 12 HOURS"
t_daily:   .null "7 DAY FORECAST"
t_cities:  .null "NATIONAL CITIES"
t_almanac: .null "ALMANAC"
t_net:     .null "NETWORK"
t_nodata:  .null "NO WEATHER DATA"

; ---------------------------------------------------------------------------------------
; Choosing a location: type a name, pick from the list, save. Carry set if nothing changed.
; ---------------------------------------------------------------------------------------
setup_len: .byte 0
setup_i:   .byte 0

setup_draw_prompt:
        jsr bg_restore
        lda #<t_setup
        ldx #>t_setup
        jsr header_draw
        #AT 16, 44, C_LBLUE
        #SAY "TYPE A CITY NAME OR ZIP CODE,"
        #AT 16, 56, C_LBLUE
        #SAY "THEN PRESS RETURN."
        lda cfg_name
        beq +
        #AT 16, 140, C_GREY
        #SAY "ESC KEEPS THE CURRENT LOCATION"
+       #AT 16, 80, C_YELLOW
        lda #<geo_query
        ldx #>geo_query
        jsr ftext_draw
        lda #'_'
        jsr ftext_char
        lda setup_err
        beq _noerr
        #AT 16, 104, C_RED
        lda setup_err
        cmp #$ff
        bne _neterr
        #SAY "NOTHING FOUND. TRY AGAIN."
        bra _hint
_neterr:
        ldx setup_err
        lda net_err_lo,x
        pha
        lda net_err_hi,x
        tax
        pla
        jsr ftext_draw
_hint:  #AT 16, 116, C_LBLUE
        #SAY "F1 FOR NETWORK DETAILS"
_noerr: jmp screen_show
setup_err: .byte 0                      ; 0 none, $ff no results, or an E_ code
t_setup: .null "SET YOUR LOCATION"

setup_location:
        lda #0
        sta setup_len
        sta geo_query
        sta setup_err
_type:  jsr setup_draw_prompt
_key:   jsr net_tick
        jsr wait_frame
        jsr key_get
        beq _key
        cmp #K_RETURN
        beq _go
        cmp #K_ESC
        beq _esc
        cmp #K_DEL
        beq _del
        cmp #K_F1
        beq _details
        cmp #' '
        bcc _key
        cmp #'z'+1
        bcs _key
        cmp #'a'
        bcc +
        and #$df
+       ldx setup_len
        cpx #24
        bcs _key
        sta geo_query,x
        inx
        lda #0
        sta geo_query,x
        stx setup_len
        bra _type
_del:   ldx setup_len
        beq _key
        dex
        stx setup_len
        lda #0
        sta geo_query,x
        bra _type
_details:
        lda #SCR_NET
        jsr screen_draw
        jsr key_wait
        jmp _type
_esc:   lda cfg_name
        beq _key                        ; nothing to fall back on
        sec
        rts
_go:    lda setup_len
        beq _key
        lda #<msg_search
        ldx #>msg_search
        jsr status_show
        jsr geo_fetch
        bcc +
        lda net_err                     ; it failed: say how, and keep what was typed
        sta setup_err
        sta last_fail
        jmp _type
+       lda geo_count
        bne _list
        lda #$ff                        ; it worked, and there are no such places
        sta setup_err
        lda #0
        sta setup_len
        sta geo_query
        jmp _type
_list:  jsr setup_draw_list
_pick:  jsr net_tick
        jsr wait_frame
        jsr key_get
        beq _pick
        cmp #K_ESC
        beq _esc
        sec
        sbc #'1'
        cmp geo_count
        bcs _pick
        sta setup_i
        jsr setup_apply
        clc
        rts

setup_draw_list:
        jsr bg_restore
        lda #<t_setup
        ldx #>t_setup
        jsr header_draw
        #AT 16, 34, C_LBLUE
        #SAY "PRESS THE NUMBER OF YOUR LOCATION:"
        lda #0
        sta geo_i
_e:     lda geo_i
        asl
        asl
        asl
        sta tmp0
        lda geo_i
        asl
        asl
        clc
        adc tmp0
        sta tmp0
        asl                             ; y = 52 + i * 24
        clc
        adc #52
        sta hg_row
        #AT 16, 0, C_YELLOW
        lda hg_row
        sta ftext_y
        lda geo_i
        clc
        adc #'1'
        jsr ftext_char
        #AT 32, 0, C_WHITE
        lda hg_row
        sta ftext_y
        jsr geo_nptr_n
        lda nptr
        ldx nptr+1
        jsr ftext_draw
        #AT 32, 0, C_LBLUE
        clc
        lda hg_row
        adc #10
        sta ftext_y
        jsr geo_nptr_reg
        lda nptr
        ldx nptr+1
        jsr ftext_draw
        inc geo_i
        lda geo_i
        cmp geo_count
        bne _e
        jmp screen_show

; result setup_i -> cfg
setup_apply:
        lda setup_i
        sta geo_i
        jsr geo_nptr_n
        ldy #0
-       lda (nptr),y
        sta cfg_name,y
        beq +
        iny
        cpy #CFG_NAME_N-1
        bne -
        lda #0
        sta cfg_name,y
+       jsr geo_nptr_lat
        ldy #0
-       lda (nptr),y
        sta cfg_lat,y
        beq +
        iny
        cpy #CFG_LAT_N-1
        bne -
+       jsr geo_nptr_lon
        ldy #0
-       lda (nptr),y
        sta cfg_lon,y
        beq +
        iny
        cpy #CFG_LON_N-1
        bne -
+       lda #'W'
        sta cfg_magic
        lda #'X'
        sta cfg_magic+1
        rts
