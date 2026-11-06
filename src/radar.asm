;=======================================================================================
; radar.asm - the radar loop. Reflectivity images come from the Iowa Environmental
; Mesonet's WMS server as 320 x 200 paletted PNGs, in plain lat/lon, over plain HTTP. Its layers
; "-m10m" .. "-m50m" are past frames, so a loop needs no clock.
;
; The map (src/assets/usmap.png, 1 bit per pixel in attic) has 32 pixels per degree of
; longitude and 40 per degree of latitude, about square in the middle of the US. The view is
; 10 x 5 degrees around the location, snapped to whole map bytes (8 px = 0.25 degrees) and
; 5-pixel rows (0.125 degrees), so its edges are short decimals we can send to the server.
;
; Finished frames are whole framebuffers in attic: the loop is one DMA per frame.
;=======================================================================================

MAP_ATTIC       = $8000000
MAP_STRIDE      = 280
MAP_W           = 2240
MAP_H           = 1200
RADAR_FRAMES    = 6
RADAR_ATTIC     = $8500000              ; a frame every $10000
BASEMAP_ATTIC   = $8110000              ; the location's map, before any radar
RADAR_COLOURS   = 15
RADAR_BASE      = 128
MAP_BG          = 144
MAP_LINE        = 145
MAP_MARK        = 146

radar_ok:       .byte 0                 ; the location is on the map
radar_have:     .byte 0                 ; frames in attic
radar_base_ok:  .byte 0                 ; BASEMAP_ATTIC is up to date
radar_i:        .byte 0
rd_px:          .word 0                 ; the location on the map
rd_py:          .word 0
rd_x0:          .word 0                 ; the view's top-left on the map
rd_y0:          .word 0
rd_west:        .word 0                 ; quarter degrees west of 0
rd_north:       .word 0                 ; eighth degrees north of 0
rd_mx:          .word 0                 ; the marker on screen
rd_my:          .byte 0
rd_row:         .byte 0
rd_col:         .byte 0
rd_y8:          .word 0
rd_step:        .byte 0

; layer suffix for each frame, oldest first
rd_suffix_lo:   .byte <rs0,<rs1,<rs2,<rs3,<rs4,<rs5
rd_suffix_hi:   .byte >rs0,>rs1,>rs2,>rs3,>rs4,>rs5
rs0:    .null "-m50m"
rs1:    .null "-m40m"
rs2:    .null "-m30m"
rs3:    .null "-m20m"
rs4:    .null "-m10m"
rs5:    .null ""
rd_label_lo:    .byte <rl0,<rl1,<rl2,<rl3,<rl4,<rl5
rd_label_hi:    .byte >rl0,>rl1,>rl2,>rl3,>rl4,>rl5
rl0:    .null "-50 MIN"
rl1:    .null "-40 MIN"
rl2:    .null "-30 MIN"
rl3:    .null "-20 MIN"
rl4:    .null "-10 MIN"
rl5:    .null "NOW"

radar_r: .byte 4,1,3,2,1,0,253,229,253,253,212,188,248,152,253,160
radar_g: .byte 233,159,0,253,197,142,248,188,149,0,0,0,0,84,253,160
radar_b: .byte 231,244,244,2,1,0,2,0,0,0,0,0,253,198,253,160

; lat100/lon100 -> the view, or radar_ok = 0 when that's off the map (outside the lower 48)
radar_view:
        lda #0
        sta radar_ok
        ; px = (lon100 + 13000) * 32 / 100
        clc
        lda lon100
        adc #<13000
        sta tmp4
        lda lon100+1
        adc #>13000
        sta tmp4+1
        bmi _out                        ; west of the map
        lda #32
        sta tmp5
        lda #0
        sta tmp5+1
        jsr mul16
        jsr rd_div100
        sta rd_px
        stx rd_px+1
        ; py = (5200 - lat100) * 40 / 100
        sec
        lda #<5200
        sbc lat100
        sta tmp4
        lda #>5200
        sbc lat100+1
        sta tmp4+1
        bmi _out
        lda #40
        sta tmp5
        lda #0
        sta tmp5+1
        jsr mul16
        jsr rd_div100
        sta rd_py
        stx rd_py+1
        ; x0 = (px - 160) & ~7, y0 = (py - 100) rounded down to a multiple of 5
        sec
        lda rd_px
        sbc #160
        sta rd_x0
        lda rd_px+1
        sbc #0
        sta rd_x0+1
        bmi _out
        lda rd_x0
        and #$f8
        sta rd_x0
        sec
        lda rd_py
        sbc #100
        sta rd_y0
        lda rd_py+1
        sbc #0
        sta rd_y0+1
        bmi _out
        ; right and bottom edges
        clc
        lda rd_x0
        adc #<320
        sta tmp4
        lda rd_x0+1
        adc #>320
        cmp #>MAP_W
        bcc +
        bne _out
        lda tmp4
        cmp #<MAP_W+1
        bcs _out
+       clc
        lda rd_y0
        adc #200
        sta tmp4
        lda rd_y0+1
        adc #0
        cmp #>MAP_H
        bcc +
        bne _out
        lda tmp4
        cmp #<MAP_H+1
        bcs _out
+       ; y0 / 5 = eighths of a degree below the map's top edge
        lda rd_y0
        sta tmp4
        lda rd_y0+1
        sta tmp4+1
        lda #5
        sta tmp5
        lda #0
        sta tmp5+1
        jsr div16
        lda tmp6
        sta tmp0
        lda tmp6+1
        sta tmp1
        ; rd_y0 = eighths * 5
        lda tmp0
        sta tmp4
        lda tmp1
        sta tmp4+1
        lda #5
        sta tmp5
        lda #0
        sta tmp5+1
        jsr mul16
        lda MULTOUT
        sta rd_y0
        lda MULTOUT+1
        sta rd_y0+1
        ; north edge, in eighths = 52 * 8 - that
        sec
        lda #<416
        sbc tmp0
        sta rd_north
        lda #>416
        sbc tmp1
        sta rd_north+1
        ; west edge, in quarters west of 0 = 130 * 4 - x0 / 8
        lda rd_x0
        sta tmp4
        lda rd_x0+1
        sta tmp4+1
        lsr tmp4+1
        ror tmp4
        lsr tmp4+1
        ror tmp4
        lsr tmp4+1
        ror tmp4
        sec
        lda #<520
        sbc tmp4
        sta rd_west
        lda #>520
        sbc tmp4+1
        sta rd_west+1
        ; marker
        sec
        lda rd_px
        sbc rd_x0
        sta rd_mx
        lda rd_px+1
        sbc rd_x0+1
        sta rd_mx+1
        sec
        lda rd_py
        sbc rd_y0
        sta rd_my
        lda #1
        sta radar_ok
_out:   jsr mul_reset
        rts

; MULTOUT / 100 -> X:A (MULTOUT fits 24 bits: a subtract-free division by the hardware)
rd_div100:
        lda MULTOUT
        sta tmp4
        lda MULTOUT+1
        sta tmp4+1
        lda MULTOUT+2
        sta MULTINA+2
        lda tmp4
        sta MULTINA
        lda tmp4+1
        sta MULTINA+1
        lda #0
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda #100
        sta MULTINB
-       bit DIVBUSY
        bmi -
        lda DIVOUT+4
        ldx DIVOUT+5
        rts

; ---------------------------------------------------------------------------------------
; The WMS request for frame radar_i
; ---------------------------------------------------------------------------------------
radar_url:
        jsr url_reset
        #url_text "/cgi-bin/wms/nexrad/n0q.cgi?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&SRS=EPSG:4326&BBOX="
        ; west: -(quarters) / 4
        lda rd_west
        ldx rd_west+1
        jsr url_neg_quarters
        lda #','
        jsr url_c
        ; south = north - 40 eighths
        sec
        lda rd_north
        sbc #40
        tay
        lda rd_north+1
        sbc #0
        tax
        tya
        jsr url_eighths
        lda #','
        jsr url_c
        ; east = west - 40 quarters
        sec
        lda rd_west
        sbc #40
        tay
        lda rd_west+1
        sbc #0
        tax
        tya
        jsr url_neg_quarters
        lda #','
        jsr url_c
        lda rd_north
        ldx rd_north+1
        jsr url_eighths
        #url_text "&WIDTH=320&HEIGHT=200&STYLES=&FORMAT=image/png;%20mode=8bit&TRANSPARENT=true&LAYERS=nexrad-n0q-900913"
        ldx radar_i
        lda rd_suffix_lo,x
        pha
        lda rd_suffix_hi,x
        tax
        pla
        jmp url_str

; X:A = quarters -> "-deg.frac"
url_neg_quarters:
        pha
        phx
        lda #'-'
        jsr url_c
        plx
        pla
        sta tmp0
        and #3
        asl
        sta tmp1                        ; frac index * 2
        stx tmp4+1
        lda tmp0
        sta tmp4
        lsr tmp4+1
        ror tmp4
        lsr tmp4+1
        ror tmp4
        lda tmp4
        ldx tmp4+1
        jsr url_dec
        lda #'.'
        jsr url_c
        ldx tmp1
        lda url_qfrac,x
        jsr url_c
        ldx tmp1
        lda url_qfrac+1,x
        jmp url_c
url_qfrac: .text "00255075"

; X:A = eighths -> "deg.frac"
url_eighths:
        sta tmp0
        and #7
        sta tmp1
        asl
        clc
        adc tmp1
        sta tmp1                        ; frac index * 3
        stx tmp4+1
        lda tmp0
        sta tmp4
        lsr tmp4+1
        ror tmp4
        lsr tmp4+1
        ror tmp4
        lsr tmp4+1
        ror tmp4
        lda tmp4
        ldx tmp4+1
        jsr url_dec
        lda #'.'
        jsr url_c
        ldx tmp1
        lda url_efrac,x
        jsr url_c
        ldx tmp1
        lda url_efrac+1,x
        jsr url_c
        ldx tmp1
        lda url_efrac+2,x
        jmp url_c
url_efrac: .text "000125250375500625750875"

; ---------------------------------------------------------------------------------------
; The location's map, kept in attic: the background of every frame
; ---------------------------------------------------------------------------------------
radar_build_base:
        ; the background colour
        lda #MAP_BG
        jsr fcm_clear
        ; src = MAP_ATTIC + y0 * 280 + x0 / 8
        lda rd_y0
        sta tmp4
        lda rd_y0+1
        sta tmp4+1
        lda #<MAP_STRIDE
        sta tmp5
        lda #>MAP_STRIDE
        sta tmp5+1
        jsr mul16
        lda rd_x0
        sta tmp4
        lda rd_x0+1
        sta tmp4+1
        lsr tmp4+1
        ror tmp4
        lsr tmp4+1
        ror tmp4
        lsr tmp4+1
        ror tmp4
        clc
        lda MULTOUT
        adc tmp4
        sta rd_base
        lda MULTOUT+1
        adc tmp4+1
        sta rd_base+1
        lda MULTOUT+2
        adc #0
        sta rd_base+2
        jsr mul_reset
        lda #0
        sta rd_col
_col:   ; isrc = base + column, dp0 = the framebuffer column
        clc
        lda rd_base
        adc rd_col
        sta isrc
        lda rd_base+1
        adc #0
        sta isrc+1
        lda rd_base+2
        adc #`MAP_ATTIC
        sta isrc+2
        lda #MAP_ATTIC >> 24
        sta isrc+3
        ldx rd_col
        lda fbcol_lo,x
        sta dp0
        lda fbcol_hi,x
        sta dp0+1
        lda fb_bank
        sta dp0+2
        lda #0
        sta dp0+3
        lda #200
        sta rd_row
_row:   ldz #0
        lda [isrc],z
        beq _skip
        sta rd_bits
        ldz #0
_bit:   asl rd_bits
        bcc +
        lda #MAP_LINE
        sta [dp0],z
+       inz
        cpz #8
        bne _bit
_skip:  clc
        lda isrc
        adc #<MAP_STRIDE
        sta isrc
        lda isrc+1
        adc #>MAP_STRIDE
        sta isrc+1
        bcc +
        inc isrc+2
+       clc
        lda dp0
        adc #8
        sta dp0
        bcc +
        inc dp0+1
+       dec rd_row
        bne _row
        inc rd_col
        lda rd_col
        cmp #40
        bne _col
        ; the marker: a white cross where the location is
        lda #MAP_MARK
        sta draw_col
        sec
        lda rd_mx
        sbc #4
        sta draw_x0
        lda rd_mx+1
        sbc #0
        sta draw_x0+1
        lda rd_my
        sta draw_y0
        lda #9
        sta draw_w
        lda #0
        sta draw_w+1
        lda #2
        sta draw_h
        jsr draw_fill
        lda rd_mx
        sta draw_x0
        lda rd_mx+1
        sta draw_x0+1
        sec
        lda rd_my
        sbc #4
        sta draw_y0
        lda #2
        sta draw_w
        lda #0
        sta draw_w+1
        lda #10
        sta draw_h
        jsr draw_fill
        ; keep it
        lda #0
        sta ptr1
        sta ptr1+1
        sta ptr1+3
        lda fb_bank
        sta ptr1+2
        lda #<BASEMAP_ATTIC
        sta ptr2
        lda #>BASEMAP_ATTIC
        sta ptr2+1
        lda #`BASEMAP_ATTIC
        sta ptr2+2
        lda #BASEMAP_ATTIC >> 24
        sta ptr2+3
        lda #<FB_SIZE
        sta tmp5
        lda #>FB_SIZE
        sta tmp5+1
        jsr dma_copy_far
        lda #1
        sta radar_base_ok
        rts
rd_base: .fill 3
rd_bits: .byte 0

; ---------------------------------------------------------------------------------------
; The decoded image at INFLATE_ATTIC over the map, into the back buffer. Pixels that are
; map lines stay on top, so the states show through the rain.
; ---------------------------------------------------------------------------------------
radar_composite:
        lda #<BASEMAP_ATTIC
        sta ptr1
        lda #>BASEMAP_ATTIC
        sta ptr1+1
        lda #`BASEMAP_ATTIC
        sta ptr1+2
        lda #BASEMAP_ATTIC >> 24
        sta ptr1+3
        lda #0
        sta ptr2
        sta ptr2+1
        sta ptr2+3
        lda fb_bank
        sta ptr2+2
        lda #<FB_SIZE
        sta tmp5
        lda #>FB_SIZE
        sta tmp5+1
        jsr dma_copy_far
        lda #<(INFLATE_ATTIC+1)         ; +1: past the first row's filter byte
        sta isrc
        lda #>(INFLATE_ATTIC+1)
        sta isrc+1
        lda #`INFLATE_ATTIC
        sta isrc+2
        lda #INFLATE_ATTIC >> 24
        sta isrc+3
        lda fb_bank
        sta dp0+2
        lda #0
        sta dp0+3
        sta rd_y8
        sta rd_y8+1
        lda #200
        sta rd_row
_row:   lda #0
        sta rd_col
_cell:  ldx rd_col
        clc
        lda fbcol_lo,x
        adc rd_y8
        sta dp0
        lda fbcol_hi,x
        adc rd_y8+1
        sta dp0+1
        ldz #0
_px:    lda [isrc],z
        tax
        lda png_remap,x
        beq _no
        tax
        lda [dp0],z
        cmp #MAP_LINE
        beq _no
        cmp #MAP_MARK
        beq _no
        txa
        sta [dp0],z
_no:    inz
        cpz #8
        bne _px
        clc
        lda isrc
        adc #8
        sta isrc
        bcc +
        inc isrc+1
        bne +
        inc isrc+2
+       inc rd_col
        lda rd_col
        cmp #40
        bne _cell
        inc isrc                        ; the next row's filter byte
        bne +
        inc isrc+1
        bne +
        inc isrc+2
+       clc
        lda rd_y8
        adc #8
        sta rd_y8
        bcc +
        inc rd_y8+1
+       dec rd_row
        bne _row
        rts

; The title, legend and age onto the back buffer, then the buffer to frame slot radar_i
radar_store:
        jsr radar_furniture
        lda #0
        sta ptr1
        sta ptr1+1
        sta ptr1+3
        lda fb_bank
        sta ptr1+2
        lda #0
        sta ptr2
        sta ptr2+1
        lda radar_i
        clc
        adc #`RADAR_ATTIC
        sta ptr2+2
        lda #RADAR_ATTIC >> 24
        sta ptr2+3
        lda #<FB_SIZE
        sta tmp5
        lda #>FB_SIZE
        sta tmp5+1
        jmp dma_copy_far

radar_furniture:
        jsr header_draw_radar
        ; the colour legend, light to heavy, above the ticker
        lda #0
        sta rd_step
_lg:    lda rd_step
        asl
        asl
        asl
        clc
        adc #<212
        sta draw_x0
        lda #0
        adc #>212
        sta draw_x0+1
        lda #172
        sta draw_y0
        lda #8
        sta draw_w
        lda #0
        sta draw_w+1
        lda #6
        sta draw_h
        lda rd_step
        clc
        adc #RADAR_BASE
        sta draw_col
        jsr draw_fill
        inc rd_step
        lda rd_step
        cmp #13
        bne _lg
        #AT 4, 172, C_YELLOW
        ldx radar_i
        lda rd_label_lo,x
        pha
        lda rd_label_hi,x
        tax
        pla
        jmp ftext_draw

; ---------------------------------------------------------------------------------------
; Fetch every frame. Carry set if none arrived; a frame that fails keeps its old picture.
; The back buffer is used for composing, and is put back afterwards.
; ---------------------------------------------------------------------------------------
radar_fetch:
        lda radar_ok
        bne +
        clc
        rts
+       lda radar_base_ok
        bne +
        jsr radar_build_base
        jsr fb_sync_from_front          ; (it was built in the back buffer: don't show it yet)
+       ldx #RADAR_FRAMES-1             ; every frame must earn its place, each time
        lda #0
-       sta radar_valid,x
        sta radar_err,x
        dex
        bpl -
        sta radar_i
        sta radar_got
_frame: lda #<msg_radar
        ldx #>msg_radar
        jsr status_frame
        jsr radar_url
        lda #H_RADAR
        sta http_host
        lda radar_i
        clc
        adc #MOCK_RADAR
        sta http_kind
        jsr http_get
        bcs _bad
        jsr body_rewind
        jsr png_decode
        bcs _bad
        jsr radar_composite
        jsr radar_store
        jsr fb_sync_from_front
        inc radar_got
        ldx radar_i
        lda #1
        sta radar_valid,x
        stx radar_last                  ; the newest good one, as they arrive oldest first
        bra _next
_bad:   ldx radar_i
        lda net_err
        sta radar_err,x
_next:  inc radar_i
        lda radar_i
        cmp #RADAR_FRAMES
        bne _frame
        jsr fb_sync_from_front
        lda radar_got
        bne _ok
        lda #0
        sta radar_have
        sec
        rts
_ok:    lda #1
        sta radar_have
        clc
        rts
radar_got:   .byte 0
radar_last:  .byte 0                    ; the newest frame that arrived
radar_valid: .fill RADAR_FRAMES         ; 1 = that attic slot holds a real picture. Without this
                                        ; a failed frame plays uninitialised RAM: static.
radar_err:   .fill RADAR_FRAMES         ; why each frame failed (an E_ code), for the N screen

; the frame number radar_show -> back buffer
radar_show:     .byte 0
radar_to_back:
        lda #0
        sta ptr1
        sta ptr1+1
        lda radar_show
        clc
        adc #`RADAR_ATTIC
        sta ptr1+2
        lda #RADAR_ATTIC >> 24
        sta ptr1+3
        lda #0
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
