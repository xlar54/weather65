;=======================================================================================
; weather.asm - JSON scanning, Open-Meteo requests, forecast tables, weather codes, dates.
;
; The JSON "parser" scans forward for a literal key, then reads numbers or strings. Open-Meteo
; answers in the order the request lists the fields, so a fetch is a straight run through
; the body. Numbers are rounded to whole units.
;=======================================================================================

HOURS   = 12
DAYS    = 7
CITIES  = 10

bp_end:         .fill 3
num_val:        .fill 4                 ; signed result of json_num
num_neg:        .byte 0
num_tmp:        .fill 4
js_max:         .byte 0

have_wx:        .byte 0
have_cities:    .byte 0
cur_temp:       .word 0
cur_feels:      .word 0
cur_rh:         .byte 0
cur_isday:      .byte 1
cur_code:       .byte 0
cur_press:      .word 0
cur_wind:       .byte 0
cur_dir:        .word 0
cur_gust:       .byte 0
tz_min:         .word 0                 ; signed minutes from UTC
today_y:        .word 2000              ; local date, from the first daily entry
today_m:        .byte 1
today_d:        .byte 1
hr_hour:        .fill HOURS
hr_temp_lo:     .fill HOURS
hr_temp_hi:     .fill HOURS
hr_pop:         .fill HOURS
hr_code:        .fill HOURS
dy_wday:        .fill DAYS
dy_code:        .fill DAYS
dy_hi_lo:       .fill DAYS
dy_hi_hi:       .fill DAYS
dy_lo_lo:       .fill DAYS
dy_lo_hi:       .fill DAYS
dy_pop:         .fill DAYS
dy_rise_h:      .fill 2                 ; today and tomorrow
dy_rise_m:      .fill 2
dy_set_h:       .fill 2
dy_set_m:       .fill 2
city_code:      .fill CITIES
city_hi_lo:     .fill CITIES
city_hi_hi:     .fill CITIES
city_lo_lo:     .fill CITIES
city_lo_hi:     .fill CITIES

; ---- the configuration: what WXCONFIG on the disk holds ----
CFG_LAT_N = 12
CFG_LON_N = 12
CFG_NAME_N = 24
cfg:
cfg_magic:      .text "WX"
cfg_unit:       .byte 0                 ; 0 = F + mph, 1 = C + km/h
cfg_lat:        .fill CFG_LAT_N, 0
cfg_lon:        .fill CFG_LON_N, 0
cfg_name:       .fill CFG_NAME_N, 0
CFG_SIZE = * - cfg
lat100:         .word 0                 ; signed degrees * 100, from the strings
lon100:         .word 0

; ---------------------------------------------------------------------------------------
; Body scanning
; ---------------------------------------------------------------------------------------
body_rewind:
        lda #<BODY_ATTIC
        sta bp
        lda #>BODY_ATTIC
        sta bp+1
        lda #`BODY_ATTIC
        sta bp+2
        lda #BODY_ATTIC >> 24
        sta bp+3
        clc
        lda bp
        adc http_len
        sta bp_end
        lda bp+1
        adc http_len+1
        sta bp_end+1
        lda bp+2
        adc #0
        sta bp_end+2
        lda http_len+2                  ; (hs_write keeps at most 64 KB)
        beq +
        lda #0
        sta bp_end
        sta bp_end+1
        lda #`BODY_ATTIC + 1
        sta bp_end+2
+       rts

; A/X = zero-terminated key: moves bp just past the next match. Carry set if there is none,
; and bp is left where it was, so a missing field doesn't lose the rest of the body.
json_find:
        sta jkey
        stx jkey+1
        lda bp
        sta num_tmp
        lda bp+1
        sta num_tmp+1
        lda bp+2
        sta num_tmp+2
_at:    lda bp+2
        cmp bp_end+2
        bne _cmp
        lda bp+1
        cmp bp_end+1
        bne _cmp
        lda bp
        cmp bp_end
        bne _cmp
        lda num_tmp
        sta bp
        lda num_tmp+1
        sta bp+1
        lda num_tmp+2
        sta bp+2
        sec
        rts
_cmp:   ldy #0
        ldz #0
_c1:    lda (jkey),y
        beq _found
        cmp [bp],z
        bne _next
        iny
        inz
        bne _c1
_next:  inc bp
        bne _at
        inc bp+1
        bne _at
        inc bp+2
        bra _at
_found: tya
        clc
        adc bp
        sta bp
        bcc +
        inc bp+1
        bne +
        inc bp+2
+       clc
        rts

; The next number -> num_val. Carry set at the end of an array or object (or the data).
; A null counts as 0.
json_num:
        lda #0
        sta num_val
        sta num_val+1
        sta num_val+2
        sta num_val+3
        sta num_neg
_skip:  jsr body_get
        bcs _end
        cmp #']'
        beq _end
        cmp #'}'
        beq _end
        cmp #'n'
        beq _null
        cmp #'-'
        beq _neg
        tax
        sec
        sbc #'0'
        cmp #10
        bcc _digit
        bra _skip
_end:   sec
        rts
_null:  jsr body_get
        jsr body_get
        jsr body_get
        clc
        rts
_neg:   lda #1
        sta num_neg
        jsr body_get
        bcs _end
        sec
        sbc #'0'
        cmp #10
        bcs _end
_digit: tax                             ; X = digit
        ; val = val * 10 + digit
        lda num_val
        sta num_tmp
        lda num_val+1
        sta num_tmp+1
        lda num_val+2
        sta num_tmp+2
        lda num_val+3
        sta num_tmp+3
        jsr _x2
        jsr _x2
        clc
        lda num_val
        adc num_tmp
        sta num_val
        lda num_val+1
        adc num_tmp+1
        sta num_val+1
        lda num_val+2
        adc num_tmp+2
        sta num_val+2
        lda num_val+3
        adc num_tmp+3
        sta num_val+3
        jsr _x2
        txa
        clc
        adc num_val
        sta num_val
        bcc +
        inc num_val+1
        bne +
        inc num_val+2
        bne +
        inc num_val+3
+       jsr body_get
        bcs _sign
        cmp #'.'
        beq _frac
        sec
        sbc #'0'
        cmp #10
        bcc _digit
        ; a terminator: step back so an array's ] is still seen
_unget: lda bp
        bne +
        dec bp+1
+       dec bp
        bra _sign
_frac:  jsr body_get                    ; first decimal: round the magnitude
        bcs _sign
        sec
        sbc #'0'
        cmp #10
        bcs _unget
        cmp #5
        bcc _fracrest
        inc num_val
        bne _fracrest
        inc num_val+1
        bne _fracrest
        inc num_val+2
_fracrest:
        jsr body_get
        bcs _sign
        sec
        sbc #'0'
        cmp #10
        bcc _fracrest
        bra _unget
_sign:  lda num_neg
        beq _ok
        sec
        lda #0
        sbc num_val
        sta num_val
        lda #0
        sbc num_val+1
        sta num_val+1
        lda #0
        sbc num_val+2
        sta num_val+2
        lda #0
        sbc num_val+3
        sta num_val+3
_ok:    clc
        rts
_x2:    asl num_val
        rol num_val+1
        rol num_val+2
        rol num_val+3
        rts

; The next "string" -> nptr (zero-terminated, upper case), js_max bytes at most counting the
; zero. UTF-8 becomes '?'. Carry set if there's no string.
json_str:
        ldy #0
_open:  jsr body_get
        bcs _fail
        cmp #']'
        beq _fail
        cmp #'"'
        bne _open
_ch:    jsr body_get
        bcs _fail
        cmp #'"'
        beq _end
        cmp #$c0                        ; a multi-byte lead
        bcc +
        lda #'?'
        bra _put
+       cmp #$80                        ; a continuation byte: nothing
        bcs _ch
        cmp #'a'
        bcc _put
        cmp #'z'+1
        bcs _put
        and #$df
_put:   tax
        iny
        cpy js_max
        bcs _over
        dey
        txa
        sta (nptr),y
        iny
        bra _ch
_over:  dey
        bra _ch
_end:   lda #0
        sta (nptr),y
        clc
        rts
_fail:  lda #0
        ldy #0
        sta (nptr),y
        sec
        rts

jnum_word .macro lo, hi
        jsr json_num
        lda num_val
        sta \lo
        lda num_val+1
        sta \hi
.endmacro

; find "key", read one number into the word or byte
FIELD_W .macro key, dest
        lda #<\key
        ldx #>\key
        jsr json_find
        #jnum_word \dest, \dest+1
.endmacro
FIELD_B .macro key, dest
        lda #<\key
        ldx #>\key
        jsr json_find
        jsr json_num
        lda num_val
        sta \dest
.endmacro

; find "key", read an array of n numbers; lo, and hi if given
ARR_W .macro key, lo, hi, n
        lda #<\key
        ldx #>\key
        jsr json_find
        ldx #0
-       phx
        jsr json_num
        plx
        lda num_val
        sta \lo,x
        lda num_val+1
        sta \hi,x
        inx
        cpx #\n
        bne -
.endmacro
ARR_B .macro key, lo, n
        lda #<\key
        ldx #>\key
        jsr json_find
        ldx #0
-       phx
        jsr json_num
        plx
        lda num_val
        sta \lo,x
        inx
        cpx #\n
        bne -
.endmacro

k_tz:     .null '"utc_offset_seconds":'
k_cur:    .null '"current":{'
k_hourly: .null '"hourly":{'
k_daily:  .null '"daily":{'
k_t2m:    .null '"temperature_2m":'
k_rh:     .null '"relative_humidity_2m":'
k_feel:   .null '"apparent_temperature":'
k_isday:  .null '"is_day":'
k_code:   .null '"weather_code":'
k_press:  .null '"surface_pressure":'
k_wind:   .null '"wind_speed_10m":'
k_dir:    .null '"wind_direction_10m":'
k_gust:   .null '"wind_gusts_10m":'
k_time:   .null '"time":'
k_pop:    .null '"precipitation_probability":'
k_max:    .null '"temperature_2m_max":'
k_min:    .null '"temperature_2m_min":'
k_rise:   .null '"sunrise":'
k_set:    .null '"sunset":'
k_popmax: .null '"precipitation_probability_max":'

; ---------------------------------------------------------------------------------------
; The forecast for the configured location. Carry set on failure.
; ---------------------------------------------------------------------------------------
wx_units:
        lda cfg_unit
        bne +
        #url_text "&temperature_unit=fahrenheit&wind_speed_unit=mph"
+       rts

wx_latlon:
        #url_text "latitude="
        lda #<cfg_lat
        ldx #>cfg_lat
        jsr url_str
        #url_text "&longitude="
        lda #<cfg_lon
        ldx #>cfg_lon
        jmp url_str

weather_fetch:
        jsr url_reset
        #url_text "/v1/forecast?"
        jsr wx_latlon
        #url_text "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,surface_pressure,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
        #url_text "&hourly=temperature_2m,precipitation_probability,weather_code"
        #url_text "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"
        #url_text "&forecast_hours=12&forecast_days=7&timezone=auto"
        jsr wx_units
        lda #H_FORECAST
        sta http_host
        lda #MOCK_FORECAST
        sta http_kind
        jsr http_get
        bcc +
        rts
+       jsr body_rewind
        lda #<k_tz
        ldx #>k_tz
        jsr json_find
        bcs _bad
        jsr json_num
        jsr wx_set_tz
        lda #<k_cur
        ldx #>k_cur
        jsr json_find
        bcs _bad
        #FIELD_W k_t2m, cur_temp
        #FIELD_B k_rh, cur_rh
        #FIELD_W k_feel, cur_feels
        #FIELD_B k_isday, cur_isday
        #FIELD_B k_code, cur_code
        #FIELD_W k_press, cur_press
        #FIELD_B k_wind, cur_wind
        #FIELD_W k_dir, cur_dir
        #FIELD_B k_gust, cur_gust
        lda #<k_hourly
        ldx #>k_hourly
        jsr json_find
        bcs _bad
        jsr wx_read_hours
        #ARR_W k_t2m, hr_temp_lo, hr_temp_hi, HOURS
        #ARR_B k_pop, hr_pop, HOURS
        #ARR_B k_code, hr_code, HOURS
        lda #<k_daily
        ldx #>k_daily
        jsr json_find
        bcs _bad
        jsr wx_read_dates
        #ARR_B k_code, dy_code, DAYS
        #ARR_W k_max, dy_hi_lo, dy_hi_hi, DAYS
        #ARR_W k_min, dy_lo_lo, dy_lo_hi, DAYS
        lda #<k_rise
        ldx #>k_rise
        jsr json_find
        ldx #0
        jsr wx_read_times_rise
        lda #<k_set
        ldx #>k_set
        jsr json_find
        ldx #0
        jsr wx_read_times_set
        #ARR_B k_popmax, dy_pop, DAYS
        jsr clock_from_http
        lda #1
        sta have_wx
        clc
        rts
_bad:   lda #E_PARSE
        sta net_err
        sec
        rts

; "2026-11-05T17:00" x HOURS -> hr_hour
wx_read_hours:
        lda #<k_time
        ldx #>k_time
        jsr json_find
        lda #0
        sta wx_i
_lp:    jsr json_iso
        ldx wx_i
        lda iso_h
        sta hr_hour,x
        inc wx_i
        lda wx_i
        cmp #HOURS
        bne _lp
        rts

wx_read_dates:
        lda #<k_time
        ldx #>k_time
        jsr json_find
        lda #0
        sta wx_i
_lp:    jsr json_iso
        lda wx_i
        bne +
        lda iso_y
        sta today_y
        lda iso_y+1
        sta today_y+1
        lda iso_mo
        sta today_m
        lda iso_d
        sta today_d
+       jsr date_days
        jsr days_weekday
        ldx wx_i
        sta dy_wday,x
        inc wx_i
        lda wx_i
        cmp #DAYS
        bne _lp
        rts

wx_read_times_rise:
        lda #0
        sta wx_i
_lp:    jsr json_iso
        ldx wx_i
        cpx #2
        bcs +
        lda iso_h
        sta dy_rise_h,x
        lda iso_mi
        sta dy_rise_m,x
+       inc wx_i
        lda wx_i
        cmp #DAYS
        bne _lp
        rts
wx_read_times_set:
        lda #0
        sta wx_i
_lp:    jsr json_iso
        ldx wx_i
        cpx #2
        bcs +
        lda iso_h
        sta dy_set_h,x
        lda iso_mi
        sta dy_set_m,x
+       inc wx_i
        lda wx_i
        cmp #DAYS
        bne _lp
        rts

wx_i:   .byte 0
iso_y:  .word 0
iso_mo: .byte 0
iso_d:  .byte 0
iso_h:  .byte 0
iso_mi: .byte 0
iso_buf: .fill 20

; the next ISO date "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM" -> iso_*
json_iso:
        lda #<iso_buf
        sta nptr
        lda #>iso_buf
        sta nptr+1
        lda #20
        sta js_max
        jsr json_str
        ldx #0
        jsr iso2
        sta tmp0                        ; century * 100
        ldy #100
        sty tmp1
        lda #0
        sta iso_y
        sta iso_y+1
-       lda tmp0
        beq +
        clc
        lda iso_y
        adc #100
        sta iso_y
        bcc ++
        inc iso_y+1
+
+       lda tmp0
        beq +
        dec tmp0
        bra -
+       ldx #2
        jsr iso2
        clc
        adc iso_y
        sta iso_y
        bcc +
        inc iso_y+1
+       ldx #5
        jsr iso2
        sta iso_mo
        ldx #8
        jsr iso2
        sta iso_d
        lda #0
        sta iso_h
        sta iso_mi
        lda iso_buf+10
        cmp #'T'
        bne +
        ldx #11
        jsr iso2
        sta iso_h
        ldx #14
        jsr iso2
        sta iso_mi
+       rts

iso2:   lda iso_buf,x
        sec
        sbc #'0'
        sta tmp2
        asl
        asl
        adc tmp2
        asl
        sta tmp2
        lda iso_buf+1,x
        sec
        sbc #'0'
        clc
        adc tmp2
        rts

; num_val = seconds -> tz_min: signed minutes
wx_set_tz:
        lda num_val+3
        sta tmp3                        ; the sign
        bpl +
        sec
        lda #0
        sbc num_val
        sta num_val
        lda #0
        sbc num_val+1
        sta num_val+1
+       lda #0
        sta tz_min
        sta tz_min+1
_div:   lda num_val+1                   ; while >= 60: at most 840 rounds
        bne _sub
        lda num_val
        cmp #60
        bcc _done
_sub:   sec
        lda num_val
        sbc #60
        sta num_val
        bcs +
        dec num_val+1
+       inc tz_min
        bne _div
        inc tz_min+1
        bra _div
_done:  lda tmp3
        bpl +
        sec
        lda #0
        sbc tz_min
        sta tz_min
        lda #0
        sbc tz_min+1
        sta tz_min+1
+       rts

; ---------------------------------------------------------------------------------------
; The cities list: one request, an array of 10 answers
; ---------------------------------------------------------------------------------------
cities_fetch:
        jsr url_reset
        #url_text "/v1/forecast?latitude=40.71,41.88,34.05,33.75,32.78,39.74,47.61,25.76,42.36,33.45"
        #url_text "&longitude=-74.01,-87.63,-118.24,-84.39,-96.80,-104.99,-122.33,-80.19,-71.06,-112.07"
        #url_text "&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto"
        jsr wx_units
        lda #H_FORECAST
        sta http_host
        lda #MOCK_CITIES
        sta http_kind
        jsr http_get
        bcc +
        rts
+       jsr body_rewind
        lda #0
        sta wx_i
_lp:    lda #<k_daily
        ldx #>k_daily
        jsr json_find
        bcs _bad
        lda #<k_code
        ldx #>k_code
        jsr json_find
        jsr json_num
        ldx wx_i
        lda num_val
        sta city_code,x
        lda #<k_max
        ldx #>k_max
        jsr json_find
        jsr json_num
        ldx wx_i
        lda num_val
        sta city_hi_lo,x
        lda num_val+1
        sta city_hi_hi,x
        lda #<k_min
        ldx #>k_min
        jsr json_find
        jsr json_num
        ldx wx_i
        lda num_val
        sta city_lo_lo,x
        lda num_val+1
        sta city_lo_hi,x
        inc wx_i
        lda wx_i
        cmp #CITIES
        bne _lp
        lda #1
        sta have_cities
        clc
        rts
_bad:   lda #E_PARSE
        sta net_err
        sec
        rts

city_names:
        .text "NEW YORK", 0, "CHICAGO", 0, "LOS ANGELES", 0, "ATLANTA", 0, "DALLAS", 0
        .text "DENVER", 0, "SEATTLE", 0, "MIAMI", 0, "BOSTON", 0, "PHOENIX", 0

; ---------------------------------------------------------------------------------------
; The location search: the query at geo_query -> geo_* (geo_count results). Carry set on failure.
; ---------------------------------------------------------------------------------------
GEO_MAX  = 5
GEO_NAME = 24
GEO_REG  = 16
GEO_NUM  = 12
geo_query:      .fill 32
geo_count:      .byte 0
geo_i:          .byte 0
k_gid:    .null '"id":'
k_gname:  .null '"name":'
k_glat:   .null '"latitude":'
k_glon:   .null '"longitude":'
k_gcc:    .null '"country_code":'
k_gadm:   .null '"admin1":'
geo_lim:  .fill 3

geo_fetch:
        jsr url_reset
        #url_text "/v1/search?count=5&format=json&name="
        ldx #0
_q:     lda geo_query,x
        beq _qe
        cmp #','                        ; "Portland, OR": the list that follows disambiguates
        beq _qe
        cmp #' '
        bne +
        lda #'+'
+       phx
        jsr url_c
        plx
        inx
        bra _q
_qe:    lda #H_GEOCODE
        sta http_host
        lda #MOCK_GEO
        sta http_kind
        jsr http_get
        bcc +
        rts
+       jsr body_rewind
        lda #0
        sta geo_count
_each:  lda #<k_gid
        ldx #>k_gid
        jsr json_find
        bcs _done
        lda geo_count
        sta geo_i
        jsr geo_entry
        inc geo_count
        lda geo_count
        cmp #GEO_MAX
        bne _each
_done:  clc
        rts

geo_entry:
        ; name
        lda #<k_gname
        ldx #>k_gname
        jsr json_find
        jsr geo_nptr_n
        jsr json_str
        ; latitude and longitude, as the server wrote them
        lda #<k_glat
        ldx #>k_glat
        jsr json_find
        jsr geo_nptr_lat
        jsr json_raw_num
        lda #<k_glon
        ldx #>k_glon
        jsr json_find
        jsr geo_nptr_lon
        jsr json_raw_num
        ; country and region: limit the search to this entry (up to the next "id")
        lda bp
        sta geo_lim
        lda bp+1
        sta geo_lim+1
        lda bp+2
        sta geo_lim+2
        lda bp_end
        pha
        lda bp_end+1
        pha
        lda bp_end+2
        pha
        lda #<k_gid
        ldx #>k_gid
        jsr json_find
        bcs +
        lda bp
        sta bp_end
        lda bp+1
        sta bp_end+1
        lda bp+2
        sta bp_end+2
+       lda geo_lim
        sta bp
        lda geo_lim+1
        sta bp+1
        lda geo_lim+2
        sta bp+2
        jsr geo_nptr_reg
        ldy #0
        lda #0
        sta (nptr),y
        lda #<k_gadm
        ldx #>k_gadm
        jsr json_find
        bcs _noreg
        jsr geo_nptr_reg
        lda #GEO_REG
        sta js_max
        jsr json_str
        bra _reg
_noreg: lda #<k_gcc
        ldx #>k_gcc
        jsr json_find
        bcs _reg
        jsr geo_nptr_reg
        lda #GEO_REG
        sta js_max
        jsr json_str
_reg:   lda geo_lim                     ; leave bp at the start of the region search; the
        sta bp                          ; next k_gid scan finds the next entry from there
        lda geo_lim+1
        sta bp+1
        lda geo_lim+2
        sta bp+2
        pla
        sta bp_end+2
        pla
        sta bp_end+1
        pla
        sta bp_end
        rts

; nptr = table + geo_i * entry size
geo_nptr_n:
        lda geo_i
        ldx #GEO_NAME
        ldy #GEO_NAME
        sty js_max
        ldy #0
        jsr geo_mul
        clc
        adc #<geo_name
        sta nptr
        tya
        adc #>geo_name
        sta nptr+1
        rts
geo_nptr_reg:
        lda geo_i
        ldx #GEO_REG
        jsr geo_mul
        clc
        adc #<geo_reg
        sta nptr
        tya
        adc #>geo_reg
        sta nptr+1
        rts
geo_nptr_lat:
        lda geo_i
        ldx #GEO_NUM
        jsr geo_mul
        clc
        adc #<geo_lat
        sta nptr
        tya
        adc #>geo_lat
        sta nptr+1
        rts
geo_nptr_lon:
        lda geo_i
        ldx #GEO_NUM
        jsr geo_mul
        clc
        adc #<geo_lon
        sta nptr
        tya
        adc #>geo_lon
        sta nptr+1
        rts
; A * X (small) -> Y:A
geo_mul:
        sta tmp0
        stx tmp1
        lda #0
        tay
-       ldx tmp0
        beq +
        clc
        adc tmp1
        bcc ++
        iny
+
+       ldx tmp0
        beq +
        dec tmp0
        bra -
+       rts

; the characters of a number -> nptr, zero-terminated (GEO_NUM with the zero)
json_raw_num:
        ldy #0
_l:     jsr body_get
        bcs _e
        cmp #'-'
        beq _keep
        cmp #'.'
        beq _keep
        tax
        sec
        sbc #'0'
        cmp #10
        bcs _e
        txa
_keep:  cpy #GEO_NUM-1
        bcs _l
        sta (nptr),y
        iny
        bra _l
_e:     lda #0
        sta (nptr),y
        rts

; the strings -> lat100 / lon100 (degrees * 100, truncated)
cfg_parse_pos:
        lda #<cfg_lat
        ldx #>cfg_lat
        jsr str_to_100
        sta lat100
        stx lat100+1
        lda #<cfg_lon
        ldx #>cfg_lon
        jsr str_to_100
        sta lon100
        stx lon100+1
        rts

; A/X = "-104.98470" -> A/X = -10498
str_to_100:
        sta tptr
        stx tptr+1
        lda #0
        sta tmp4
        sta tmp4+1
        sta tmp0                        ; negative?
        sta tmp1                        ; decimals seen; $ff once in the integer part
        lda #$ff
        sta tmp1
        ldy #0
_l:     lda (tptr),y
        beq _end
        iny
        cmp #'-'
        bne +
        lda #1
        sta tmp0
        bra _l
+       cmp #'.'
        bne +
        lda #0
        sta tmp1
        bra _l
+       sec
        sbc #'0'
        cmp #10
        bcs _l
        sta tmp2
        lda tmp1
        cmp #2
        beq _l                          ; past 2 decimals
        cmp #$ff
        beq +
        inc tmp1
+       jsr _x10
        clc
        lda tmp4
        adc tmp2
        sta tmp4
        bcc +
        inc tmp4+1
+       bra _l
_end:   lda tmp1                        ; fewer than 2 decimals: scale up
        cmp #$ff
        bne +
        lda #0
        sta tmp1
+       lda tmp1
        cmp #2
        bcs _sgn
        jsr _x10
        inc tmp1
        bra _end
_sgn:   lda tmp0
        beq +
        sec
        lda #0
        sbc tmp4
        sta tmp4
        lda #0
        sbc tmp4+1
        sta tmp4+1
+       lda tmp4
        ldx tmp4+1
        rts
_x10:   lda tmp4
        sta tmp5
        lda tmp4+1
        sta tmp5+1
        asw tmp4
        asw tmp4
        clc
        lda tmp4
        adc tmp5
        sta tmp4
        lda tmp4+1
        adc tmp5+1
        sta tmp4+1
        asw tmp4
        rts

; ---------------------------------------------------------------------------------------
; Dates. days = days since 2000-01-01, good to 2099.
; ---------------------------------------------------------------------------------------
days_val:       .word 0
month_days:     .word 0,31,59,90,120,151,181,212,243,273,304,334

; iso_y, iso_mo, iso_d -> days_val
date_days:
        lda iso_y
        sec
        sbc #<2000
        sta tmp0                        ; years since 2000
        ; days = y * 365 + (y + 3) / 4 + month table + day - 1 + leap correction
        sta tmp4
        lda #0
        sta tmp4+1
        lda #<365
        sta tmp5
        lda #>365
        sta tmp5+1
        jsr mul16
        lda MULTOUT
        sta days_val
        lda MULTOUT+1
        sta days_val+1
        jsr mul_reset
        lda tmp0
        clc
        adc #3
        lsr
        lsr
        clc
        adc days_val
        sta days_val
        bcc +
        inc days_val+1
+       lda iso_mo
        sec
        sbc #1
        cmp #12
        bcc +
        lda #0
+       asl
        tax
        clc
        lda days_val
        adc month_days,x
        sta days_val
        lda days_val+1
        adc month_days+1,x
        sta days_val+1
        lda iso_d
        sec
        sbc #1
        clc
        adc days_val
        sta days_val
        bcc +
        inc days_val+1
+       lda iso_mo                      ; past February of a leap year
        cmp #3
        bcc +
        lda tmp0
        and #3
        bne +
        inc days_val
        bne +
        inc days_val+1
+       rts

; days_val -> A = 0 Sunday .. 6 Saturday. 2000-01-01 was a Saturday.
days_weekday:
        lda days_val
        sta tmp4
        lda days_val+1
        sta tmp4+1
        lda #6
        clc
        adc tmp4
        sta tmp4
        bcc +
        inc tmp4+1
+
-       lda tmp4+1                      ; mod 7, subtracting in big steps first
        beq _small
        sec
        lda tmp4
        sbc #<7000
        sta tmp5
        lda tmp4+1
        sbc #>7000
        bcc _hund
        sta tmp4+1
        lda tmp5
        sta tmp4
        bra -
_hund:  sec
        lda tmp4
        sbc #7
        sta tmp4
        bcs -
        dec tmp4+1
        bra -
_small: lda tmp4
-       cmp #7
        bcc +
        sbc #7
        bra -
+       rts

; today's moon phase: 0-7 (new .. waning crescent). Synodic month = 29.53 days, reference new
; moon 2000-01-06 = day 5. r = ((days - 5) * 100) mod 2953.
moon_phase:
        lda today_y
        sta iso_y
        lda today_y+1
        sta iso_y+1
        lda today_m
        sta iso_mo
        lda today_d
        sta iso_d
        jsr date_days
        sec
        lda days_val
        sbc #5
        sta tmp4
        lda days_val+1
        sbc #0
        sta tmp4+1
        lda #100
        sta tmp5
        lda #0
        sta tmp5+1
        jsr mul16
        lda MULTOUT                     ; dividend: 32 bits
        sta moon_v
        lda MULTOUT+1
        sta moon_v+1
        lda MULTOUT+2
        sta moon_v+2
_m:     lda moon_v+2                    ; subtract 2953 until it's under: at most ~2.5M / 2953
        bne _s
        lda moon_v+1
        cmp #>2953
        bcc _got
        bne _s
        lda moon_v
        cmp #<2953
        bcc _got
_s:     sec
        lda moon_v
        sbc #<2953
        sta moon_v
        lda moon_v+1
        sbc #>2953
        sta moon_v+1
        lda moon_v+2
        sbc #0
        sta moon_v+2
        bra _m
_got:   lda #0                          ; phase = (r + 185) / 369, wrapping at 8
        sta tmp0
        clc
        lda moon_v
        adc #185
        sta moon_v
        bcc _d
        inc moon_v+1
_d:     lda moon_v+1
        cmp #>369
        bcc _p
        bne _q
        lda moon_v
        cmp #<369
        bcc _p
_q:     sec
        lda moon_v
        sbc #<369
        sta moon_v
        lda moon_v+1
        sbc #>369
        sta moon_v+1
        inc tmp0
        bra _d
_p:     jsr mul_reset
        lda tmp0
        and #7
        rts
moon_v: .fill 3

; lib/vblit.asm needs the multiplier's upper input bytes zero
mul_reset:
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        rts

; ---------------------------------------------------------------------------------------
; WMO weather codes -> text and icon
; ---------------------------------------------------------------------------------------
wmo_codes:
        .byte 0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,71,73,75,77,80,81,82,85,86,95,96,99
WMO_N = * - wmo_codes
wmo_text:
        .byte 0,1,2,3,4,4,5,5,5,6,6,7,7,8,9,9,10,10,11,10,12,12,13,14,14,15,16,16
wmo_icon:
        .byte 0,1,1,2,3,3,4,4,4,4,4,5,5,5,5,5,6,6,6,6,5,5,5,6,6,7,7,7
wx_txt_lo: .byte <w0,<w1,<w2,<w3,<w4,<w5,<w6,<w7,<w8,<w9,<w10,<w11,<w12,<w13,<w14,<w15,<w16
wx_txt_hi: .byte >w0,>w1,>w2,>w3,>w4,>w5,>w6,>w7,>w8,>w9,>w10,>w11,>w12,>w13,>w14,>w15,>w16
w0:  .null "CLEAR"
w1:  .null "MOSTLY CLEAR"
w2:  .null "PARTLY CLOUDY"
w3:  .null "CLOUDY"
w4:  .null "FOG"
w5:  .null "DRIZZLE"
w6:  .null "FREEZING DRIZZLE"
w7:  .null "RAIN"
w8:  .null "HEAVY RAIN"
w9:  .null "FREEZING RAIN"
w10: .null "SNOW"
w11: .null "HEAVY SNOW"
w12: .null "SHOWERS"
w13: .null "HEAVY SHOWERS"
w14: .null "SNOW SHOWERS"
w15: .null "THUNDERSTORM"
w16: .null "THUNDER + HAIL"

; A = WMO code -> X = table index
wmo_find:
        ldx #0
-       cmp wmo_codes,x
        beq +
        inx
        cpx #WMO_N
        bne -
        ldx #3                          ; unknown: "cloudy" is the safe guess
+       rts
; A = WMO code -> A/X = text
wmo_string:
        jsr wmo_find
        ldy wmo_text,x
        lda wx_txt_lo,y
        ldx wx_txt_hi,y
        rts
; A = WMO code -> A = icon number
wmo_icon_of:
        jsr wmo_find
        lda wmo_icon,x
        rts
