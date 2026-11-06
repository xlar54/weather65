;=======================================================================================
; net.asm - mega-ip after #TAKEOVER, and an HTTP/1.0 client.
;
; mega-ip is the unmodified BASIC library, loaded at $42000. It expects to run with bank 4
; mapped at $2000-$7FFF. BASIC gets that from KERNAL JSRFAR; after the takeover this file
; does it with a MAP trampoline below $2000, so the program at $2000+ vanishes during the
; call. Interrupts stay off for that time, because the IRQ handler lives up there too.
;
;   net_setup      start Ethernet, DHCP, self test. Carry set on failure (net_err)
;   http_get       http_host = 0..N, url_buf = path. Body goes to BODY_ATTIC. Carry set on
;                  failure (net_err). http_code, http_len, and the Date: header's time.
;   net_tick       once a frame while idle, so the stack can answer ARP
;
; Building with -D MOCK_NET=1 replaces the network with files replayed through the same
; header and chunked-body parser, which is how this all gets tested in Xemu.
;=======================================================================================

; ---- mega-ip entry points, as seen with bank 4 mapped ----
MIP_INIT        = $2000
MIP_SET_LOCAL_PORT = $2009
MIP_SET_REMOTE_IP = $200c
MIP_SET_REMOTE_PORT = $200f
MIP_SET_XLATE   = $2015
MIP_DISCONNECT  = $2021
MIP_POLL        = $2024
MIP_CONN_START  = $2027
MIP_CONN_POLL   = $202a
MIP_DNS_RESULT  = $2033
MIP_DNS_STATE   = $2036
MIP_DHCP_START  = $2042
MIP_DHCP_POLL   = $2045
MIP_SET_DNS     = $204b
MIP_GET_LOCAL_IP = $204e
MIP_GET_GATEWAY = $2051
MIP_GET_MASK    = $2054
MIP_GET_DNS     = $2057
MIP_FORCE_CLOSE = $205d
MIP_ABI_INFO    = $2060
MIP_SEND_BYTE   = $7600
MIP_DNS_START   = $760f
MIP_RECV_BLOCK  = $7621

MIP_LOAD        = $42000
CONN_OK         = 1
CONN_BAD        = 2
DHCP_BOUND      = 4
DHCP_FAILED     = $7f
DNS_DONE        = 2
DNS_FAILED      = 3

NC_LOW          = $1900                 ; the trampoline (below the MAP window)
RX_BUF          = $1a00                 ; a receive block (physical, so any bank-0 address)
RX_MAX          = 128
BODY_ATTIC      = $8300000

; errors, in the order of net_err_tab
E_NONE  = 0
E_STACK = 1
E_DHCP  = 2
E_DNS   = 3
E_CONN  = 4
E_SEND  = 5
E_RECV  = 6
E_HTTP  = 7
E_PARSE = 8
E_PNG   = 9
E_INFL  = 10
E_CRC   = 11
E_SAVE  = 12

net_err:        .byte 0
net_ok_count:   .word 0
net_fail_count: .word 0
http_host:      .byte 0
http_code:      .word 0
http_len:       .fill 3
http_h:         .byte $ff               ; Date: header (UTC); $ff = none seen
http_m:         .byte 0
http_s:         .byte 0
http_kind:      .byte 0                 ; the replay build's file number
dhcp_state:     .byte 0
hs_state:       .byte 0                 ; HTTP parser
hs_first:       .byte 0
hs_chunked:     .byte 0
hs_hlen:        .byte 0
hs_clen:        .fill 3
hs_havelen:     .byte 0
hs_csize:       .fill 3
hs_done:        .byte 0
hs_prev:        .byte 0
net_timer:      .word 0
net_last:       .byte 0
net_saw_close:  .byte 0
net_retry:      .byte 0
net_dns_public: .byte 0                 ; 1 once we've fallen back to 8.8.8.8

; A/X/Y/Z = arguments, net_target = the routine: returns its A/X/Y/Z
NET .macro addr
        pha                             ; A is the first argument: setting the target must keep it
        lda #<\addr
        sta NC_JSR+1
        lda #>\addr
        sta NC_JSR+2
        pla
        jsr NC_LOW
.endmacro
NET_A .macro addr, a=0, x=0, y=0, z=0
        lda #<\addr
        sta NC_JSR+1
        lda #>\addr
        sta NC_JSR+2
        lda #\a
        ldx #\x
        ldy #\y
        ldz #\z
        jsr NC_LOW
.endmacro

; ---- the trampoline: position-dependent, copied to NC_LOW at boot ----
nc_image:
        .logical NC_LOW
        php
        sei
        sta nc_a
        stx nc_x
        sty nc_y
        tza
        sta nc_z
        lda #$00                        ; offset $40000 for blocks 1-3 ($2000-$7FFF)
        ldx #$e4
        ldy #$00
        ldz #$00
        map
        eom
        lda nc_z
        taz
        ldy nc_y
        ldx nc_x
        lda nc_a
NC_JSR: jsr $ffff
        sta nc_a
        stx nc_x
        sty nc_y
        tza
        sta nc_z
        lda #$00
        tax
        tay
        taz
        map
        eom
        lda nc_z
        taz
        ldy nc_y
        ldx nc_x
        lda nc_a
        plp
        rts
nc_a:   .byte 0
nc_x:   .byte 0
nc_y:   .byte 0
nc_z:   .byte 0
NC_END:
        .endlogical
NC_SIZE = NC_END - NC_LOW
        .cerror NC_END > RX_BUF, "trampoline overlaps the receive block"

net_install:
        ldx #0
-       lda nc_image,x
        sta NC_LOW,x
        inx
        cpx #NC_SIZE
        bne -
        rts

        .if MOCK_NET == 0
; ---------------------------------------------------------------------------------------
; Start: returns carry set with net_err on failure. Takes about 5 s plus DHCP.
; ---------------------------------------------------------------------------------------
net_selftest:
        #NET_A MIP_ABI_INFO             ; proves the mapping: a real answer from bank 4
        cmp #1
        bne _bad
        cpx #0
        bne _bad
        cpy #1
        bne _bad
        cpz #1
        bne _bad
        ; an argument round trip through the stack's own state
        lda #10                         ; (through #NET: it must deliver all four registers)
        ldx #20
        ldy #30
        ldz #40
        #NET MIP_SET_REMOTE_IP
        #NET_A $205a                    ; get remote IP
        cmp #10
        bne _bad
        cpx #20
        bne _bad
        cpy #30
        bne _bad
        cpz #40
        bne _bad
        clc
        rts
_bad:   lda #E_STACK
        sta net_err
        sec
        rts

net_setup:
        lda #0
        sta net_err
        jsr net_selftest
        bcs _out
        lda #<msg_ethstart
        ldx #>msg_ethstart
        jsr boot_line
        #NET_A MIP_INIT                 ; about 4 s with interrupts off (PHY reset)
        #NET_A MIP_SET_XLATE, 0         ; binary safe: no PETSCII translation
        ; a different port block per boot: a reused port would meet the server's TIME_WAIT
        lda $d012
        eor $d7ef
        and #$1f
        ora #$c0
        tax
        lda $d7ef
        eor frame_count
        sta tmp0
        txa
        ldx tmp0
        #NET MIP_SET_LOCAL_PORT
        jsr net_dhcp
        bcs _out
        clc
_out:   rts

net_dhcp:
        lda #0
        sta net_dns_public
        lda #<msg_dhcp
        ldx #>msg_dhcp
        jsr boot_line
        #NET_A MIP_DHCP_START
        jsr net_timer_30s
_loop:  #NET_A MIP_POLL
        #NET_A MIP_DHCP_POLL
        sta dhcp_state
        cmp #DHCP_BOUND
        beq _ok
        cmp #DHCP_FAILED
        beq _bad
        jsr net_pace
        jsr net_timer_tick
        bcc _loop
_bad:   lda #E_DHCP
        sta net_err
        sec
        rts
_ok:    #NET_A MIP_FORCE_CLOSE          ; as ansi-term does before its first connection
        clc
        rts

net_tick:
        #NET_A MIP_POLL
        rts

; The pace of every polling loop, about 5 polls a frame. It matters both ways:
; - ARP_RETRY_TICK and ARP_CACHE_PURGE count polls, not time. Flat out at 40 MHz, ARP gives up
;   in a few milliseconds, before the router has answered.
; - The DNS, TCP and connect timers count raster wraps, seen by comparing the raster with
;   its last value. Polling once a frame at one fixed line might never see a wrap.
net_pace:
        lda $d012
        and #$c0
        sta net_band
-       lda $d012
        and #$c0
        cmp net_band
        beq -
        rts
net_band: .byte 0

; ---------------------------------------------------------------------------------------
; Timers count frames, as long as the caller keeps interrupts on between calls
; ---------------------------------------------------------------------------------------
net_timer_30s:
        lda #<1500
        sta net_timer
        lda #>1500
        sta net_timer+1
net_timer_sync:
        lda frame_count
        sta net_last
        rts
; carry set = expired
net_timer_tick:
        lda frame_count
        cmp net_last
        beq _no
        sta net_last
        lda net_timer
        bne +
        dec net_timer+1
+       dec net_timer
        lda net_timer
        ora net_timer+1
        beq _exp
_no:    clc
        rts
_exp:   sec
        rts

; ---------------------------------------------------------------------------------------
; Resolve http_host; the answer is kept, so each host costs one lookup
; ---------------------------------------------------------------------------------------
net_resolve:
        lda http_host
        asl
        asl
        tax
        lda host_ip,x
        ora host_ip+1,x
        ora host_ip+2,x
        ora host_ip+3,x
        beq _lookup
        clc
        rts
_lookup:
        ldx http_host
        lda host_lo,x
        sta tptr
        lda host_hi,x
        sta tptr+1
        ldy #0
-       lda (tptr),y
        beq +
        iny
        bne -
+       tya
        taz                             ; Z = length
        lda tptr
        ldx tptr+1
        ldy #0                          ; bank 0
        #NET MIP_DNS_START
        cmp #1
        bne _fail
        jsr net_timer_30s
_wait:  #NET_A MIP_POLL
        #NET_A MIP_DNS_STATE
        cmp #DNS_DONE
        beq _done
        cmp #DNS_FAILED
        beq _fail
        jsr net_pace
        jsr net_timer_tick
        bcc _wait
_fail:  lda net_dns_public                ; no answer from the network's own DNS server:
        bne _give_up                    ;   try a public one once, through the gateway
        inc net_dns_public
        lda #8
        ldx #8
        ldy #8
        ldz #8
        #NET MIP_SET_DNS
        jmp _lookup
_give_up:
        lda #E_DNS
        sta net_err
        sec
        rts
_done:  #NET_A MIP_DNS_RESULT
        sta tmp0
        stx tmp1
        sty tmp2
        tza
        sta tmp3
        lda http_host
        asl
        asl
        tax
        lda tmp0
        sta host_ip,x
        lda tmp1
        sta host_ip+1,x
        lda tmp2
        sta host_ip+2,x
        lda tmp3
        sta host_ip+3,x
        clc
        rts

; ---------------------------------------------------------------------------------------
; http_get: one retry, with a fresh DNS answer in case the old address has gone
; ---------------------------------------------------------------------------------------
http_get:
        lda #0
        sta net_err
        lda #1
        sta net_retry
_try:   jsr http_once
        bcc _good
        lda net_retry
        beq _fail
        dec net_retry
        lda net_err
        cmp #E_HTTP                     ; a real answer from the server: don't repeat it
        beq _fail
        cmp #E_CONN
        bne _try
        lda http_host                   ; connection refused: look the name up again
        asl
        asl
        tax
        lda #0
        sta host_ip,x
        sta host_ip+1,x
        sta host_ip+2,x
        sta host_ip+3,x
        bra _try
_fail:  #inw_abs net_fail_count
        sec
        rts
_good:  #inw_abs net_ok_count
        clc
        rts

inw_abs .macro addr
        inc \addr
        bne +
        inc \addr+1
+
.endmacro

; api.open-meteo.com answers a SYN with a window of 0, then opens it once it has our ACK. The
; stack doesn't read the peer's window, so its first byte would be dropped and resent 0.9 s
; later. Give the update time to arrive (it took about 80 ms).
net_settle:
        lda http_host
        cmp #H_FORECAST
        bne _o
        lda #10
        sta net_timer
        lda #0
        sta net_timer+1
        jsr net_timer_sync
_w:     #NET_A MIP_POLL
        jsr net_pace
        jsr net_timer_tick
        bcc _w
_o:     rts

http_once:
        jsr net_resolve
        bcc +
        rts
+       lda http_host
        asl
        asl
        tax
        lda host_ip,x
        pha
        lda host_ip+1,x
        sta tmp0
        lda host_ip+2,x
        tay
        lda host_ip+3,x
        taz
        ldx tmp0
        pla
        #NET MIP_SET_REMOTE_IP
        #NET_A MIP_SET_REMOTE_PORT, 0, 80
        ; ---- connect ----
        #NET_A MIP_CONN_START
        lda #<750
        sta net_timer
        lda #>750
        sta net_timer+1
        jsr net_timer_sync
_conn:  #NET_A MIP_POLL
        #NET_A MIP_CONN_POLL
        sta tmp0
        and #CONN_OK
        bne _sendit
        lda tmp0
        and #CONN_BAD
        bne _noconn
        jsr net_pace
        jsr net_timer_tick
        bcc _conn
_noconn:
        #NET_A MIP_FORCE_CLOSE
        lda #E_CONN
        sta net_err
        sec
        rts
        ; ---- request ----
_sendit:
        jsr net_settle
        jsr http_request
        bcc +
        #NET_A MIP_FORCE_CLOSE
        lda #E_SEND
        sta net_err
        sec
        rts
        ; ---- response ----
+       jsr http_begin
        lda #<1000
        sta net_timer
        lda #>1000
        sta net_timer+1
        jsr net_timer_sync
        lda #0
        sta net_saw_close
_rx:    #NET_A MIP_POLL
        cmp #0
        beq +
        lda #1
        sta net_saw_close
+
_block: lda #<RX_BUF
        ldx #>RX_BUF
        ldy #0
        ldz #RX_MAX
        #NET MIP_RECV_BLOCK
        cmp #0
        beq _empty
        jsr http_feed_block
        lda hs_done
        bne _finish
        lda #<1000                      ; quiet time is what times out, not total time
        sta net_timer
        lda #>1000
        sta net_timer+1
        bra _block
_empty: lda net_saw_close
        bne _finish
        jsr net_pace
        jsr net_timer_tick
        bcc _rx
        #NET_A MIP_FORCE_CLOSE
        lda #E_RECV
        sta net_err
        sec
        rts
        ; ---- close ----
_finish:
        #NET_A MIP_DISCONNECT
        lda #25
        sta net_timer
        lda #0
        sta net_timer+1
        jsr net_timer_sync
_close: #NET_A MIP_POLL
        cmp #0
        bne _closed
        jsr net_pace
        jsr net_timer_tick
        bcc _close
_closed:
        #NET_A MIP_FORCE_CLOSE
        jmp http_check

; A = a request byte. The queue can refuse it: wait for it to drain. Carry set = failed.
req_byte:
        sta req_b
_again: lda req_b
        #NET MIP_SEND_BYTE
        cmp #1
        beq _sent
        #NET_A MIP_POLL
        jsr net_pace
        jsr net_timer_tick
        bcc _again
        sec
        rts
_sent:  clc
        rts
req_b:  .byte 0
net_req_timer:
        lda #<750
        sta net_timer
        lda #>750
        sta net_timer+1
        jmp net_timer_sync

        .else
; ---------------------------------------------------------------------------------------
; Replay build: mockN files in attic stand in for the server
; ---------------------------------------------------------------------------------------
MOCK_ATTIC = $8600000
MOCK_MAX   = 10
mock_len_lo:    .fill MOCK_MAX
mock_len_hi:    .fill MOCK_MAX
mock_left:      .word 0
mock_src:       .dword 0
dbg_stall:      .byte 0
dbg_mock_fail:  .byte 0                 ; poke an E_ code: the next http_get fails with it

; the request goes to attic instead: private/tools/check_requests.py sends these exact bytes
; to the real servers
MOCK_REQ = $8700000
req_w:  .dword 0
req_byte:
        sta req_b
        lda req_w
        sta ptr0
        lda req_w+1
        sta ptr0+1
        lda req_w+2
        sta ptr0+2
        lda req_w+3
        sta ptr0+3
        lda req_b
        ldz #0
        sta [ptr0],z
        ldz #1
        lda #0
        sta [ptr0],z
        inc req_w
        bne +
        inc req_w+1
+       clc
        rts
req_b:  .byte 0
net_req_timer:
        lda #0
        sta req_w
        lda http_kind                   ; one page-group per kind of request
        asl
        asl
        asl
        asl
        sta req_w+1
        lda #`MOCK_REQ
        sta req_w+2
        lda #MOCK_REQ >> 24
        sta req_w+3
        rts

net_selftest:
        clc
        rts
net_setup:
        jsr net_selftest
        rts
net_dhcp:
        clc
        rts
net_tick:
        rts

http_get:
        lda #0
        sta net_err
-       lda dbg_stall                   ; kind + 1: freeze before this request, to see the screen
        beq +
        sec
        sbc #1
        cmp http_kind
        beq -
+       lda dbg_mock_fail
        beq +
        sta net_err
        lda #0
        sta dbg_mock_fail
        sec
        rts
+       jsr http_request
        jsr http_begin
        ldx http_kind
        lda mock_len_lo,x
        sta mock_left
        lda mock_len_hi,x
        sta mock_left+1
        lda #0
        sta mock_src
        sta mock_src+1
        sta mock_src+3
        txa
        clc
        adc #`MOCK_ATTIC
        sta mock_src+2
        lda #MOCK_ATTIC >> 24
        sta mock_src+3
_next:  lda mock_left
        ora mock_left+1
        beq _end
        ldz #0                          ; the same block size as the real receive loop
_cp:    lda mock_left
        ora mock_left+1
        beq _flush
        lda mock_src
        sta ptr0
        lda mock_src+1
        sta ptr0+1
        lda mock_src+2
        sta ptr0+2
        lda mock_src+3
        sta ptr0+3
        phz
        ldz #0
        lda [ptr0],z
        plz
        tax
        tza
        tay
        txa
        sta RX_BUF,y
        inz
        inc mock_src
        bne +
        inc mock_src+1
        bne +
        inc mock_src+2
+       lda mock_left
        bne +
        dec mock_left+1
+       dec mock_left
        cpz #RX_MAX
        bne _cp
_flush: tza
        jsr http_feed_block
        lda hs_done
        beq _next
_end:   jmp http_check

; boot: load the replay files
mock_names:
        .text "MOCK0MOCK1MOCK2MOCK3MOCK4MOCK5MOCK6MOCK7MOCK8MOCK9"
mock_load_all:
        lda #0
        sta tmp7
_lp:    lda tmp7
        cmp #MOCK_MAX
        beq _done
        lda #0
        sta ld_attic
        sta ld_attic+1
        lda tmp7
        clc
        adc #`MOCK_ATTIC
        sta ld_attic+2
        lda #MOCK_ATTIC >> 24
        sta ld_attic+3
        lda tmp7                        ; name = mock_names + i * 5
        asl
        asl
        clc
        adc tmp7
        clc
        adc #<mock_names
        tax
        lda #>mock_names
        adc #0
        tay
        lda tmp7
        pha
        lda #5
        jsr load_to_attic
        pla
        sta tmp7
        bcs _skip
        ldx tmp7
        lda ld_len
        sta mock_len_lo,x
        lda ld_len+1
        sta mock_len_hi,x
_skip:  inc tmp7
        bra _lp
_done:  rts
        .endif

; ---------------------------------------------------------------------------------------
; The request: "GET url HTTP/1.0" and the headers, one byte at a time
; ---------------------------------------------------------------------------------------
http_request:
        jsr net_req_timer
        lda #<req_get
        ldx #>req_get
        jsr req_send
        bcs _out
        lda #<url_buf
        ldx #>url_buf
        jsr req_send
        bcs _out
        lda #<req_ver
        ldx #>req_ver
        jsr req_send
        bcs _out
        ldx http_host
        lda host_lo,x
        pha
        lda host_hi,x
        tax
        pla
        jsr req_send
        bcs _out
        lda #<req_tail
        ldx #>req_tail
        jsr req_send
_out:   rts

req_send:
        sta nptr
        stx nptr+1
_next:  ldy #0
        lda (nptr),y
        beq _ok
        jsr req_byte
        bcs _fail
        inw nptr
        bra _next
_ok:    clc
        rts
_fail:  sec
        rts

req_get:  .null "GET "
req_ver:  .text " HTTP/1.0", 13, 10, "Host: "
          .byte 0
req_tail: .text 13, 10, "User-Agent: weather65 (MEGA65)", 13, 10
          .text "Accept: */*", 13, 10, "Connection: close", 13, 10, 13, 10
          .byte 0

; ---------------------------------------------------------------------------------------
; The HTTP response parser: status line, headers, then a plain or chunked body, written
; to attic. Used by both the real and the replay paths.
; ---------------------------------------------------------------------------------------
HS_HEAD  = 0
HS_BODY  = 1
HS_CSIZE = 2
HS_CDATA = 3
HS_CEND  = 4
HLINE_MAX = 64
hline:  .fill HLINE_MAX

http_begin:
        lda #HS_HEAD
        sta hs_state
        lda #1
        sta hs_first
        lda #0
        sta hs_chunked
        sta hs_hlen
        sta hs_havelen
        sta hs_done
        sta hs_csize
        sta hs_csize+1
        sta hs_csize+2
        sta http_len
        sta http_len+1
        sta http_len+2
        sta http_code
        sta http_code+1
        lda #<BODY_ATTIC
        sta wp
        lda #>BODY_ATTIC
        sta wp+1
        lda #`BODY_ATTIC
        sta wp+2
        lda #BODY_ATTIC >> 24
        sta wp+3
        rts

; A = bytes in RX_BUF
http_feed_block:
        sta fb_n
        lda #0
        sta fb_i
_lp:    ldx fb_i
        lda RX_BUF,x
        jsr http_feed
        inc fb_i
        lda fb_i
        cmp fb_n
        bne _lp
        rts
fb_i:   .byte 0
fb_n:   .byte 0

http_feed:
        ldx hs_state
        cpx #HS_BODY
        bne +
        jmp hs_store
+       cpx #HS_HEAD
        bne _chunk
        ; ---- header lines ----
        cmp #10
        beq _eol
        cmp #13
        beq _skip
        ldx hs_hlen
        cpx #HLINE_MAX-1
        bcs _skip
        cmp #'A'
        bcc +
        cmp #'Z'+1
        bcs +
        ora #$20                        ; lower case
+       sta hline,x
        inc hs_hlen
_skip:  rts
_eol:   ldx hs_hlen
        beq _endhead
        lda #0
        sta hline,x
        sta hs_hlen
        lda hs_first
        beq +
        lda #0
        sta hs_first
        jmp hs_status_line
+       jmp hs_header_line
_endhead:
        lda hs_havelen
        beq +
        lda hs_clen
        ora hs_clen+1
        ora hs_clen+2
        bne +
        lda #1                          ; "Content-Length: 0"
        sta hs_done
        rts
+       lda hs_chunked
        beq +
        lda #HS_CSIZE
        sta hs_state
        rts
+       lda #HS_BODY
        sta hs_state
        rts
        ; ---- chunked body ----
_chunk: cpx #HS_CDATA
        bne _notdata
        jsr hs_write
        lda hs_csize
        bne +
        lda hs_csize+1
        bne ++
        dec hs_csize+2
+
+       lda hs_csize
        bne +
        dec hs_csize+1
+       dec hs_csize
        lda hs_csize
        ora hs_csize+1
        ora hs_csize+2
        bne +
        lda #HS_CEND
        sta hs_state
+       rts
_notdata:
        cpx #HS_CEND
        bne _size
        cmp #10                         ; the CRLF after a chunk
        bne +
        lda #HS_CSIZE
        sta hs_state
+       rts
_size:  cmp #10
        beq _sizeend
        jsr hex_val
        bcs +                           ; "\r" or a chunk extension: ignore it
        pha
        ldx #4
-       asl hs_csize
        rol hs_csize+1
        rol hs_csize+2
        dex
        bne -
        pla
        ora hs_csize
        sta hs_csize
+       rts
_sizeend:
        lda hs_csize
        ora hs_csize+1
        ora hs_csize+2
        bne +
        lda #1                          ; the last chunk
        sta hs_done
        rts
+       lda #HS_CDATA
        sta hs_state
        rts

hs_store:
        jsr hs_write
        lda hs_havelen
        beq _o
        lda http_len
        cmp hs_clen
        bne _o
        lda http_len+1
        cmp hs_clen+1
        bne _o
        lda http_len+2
        cmp hs_clen+2
        bne _o
        lda #1
        sta hs_done
_o:     rts

; A = a body byte. At most 64 KB, everything we fetch is smaller; the rest is dropped.
hs_write:
        ldz #0
        ldy http_len+2
        bne _full
        sta [wp],z
        inc wp
        bne +
        inc wp+1
        bne +
        inc wp+2
+
_full:  inc http_len
        bne +
        inc http_len+1
        bne +
        inc http_len+2
+       rts

; A = char -> A = 0..15, carry clear; carry set when not a hex digit
hex_val:
        cmp #'0'
        bcc _no
        cmp #'9'+1
        bcs +
        sbc #'0'-1
        clc
        rts
+       ora #$20
        cmp #'a'
        bcc _no
        cmp #'f'+1
        bcs _no
        sbc #'a'-11
        clc
        rts
_no:    sec
        rts

; "http/1.1 200 ok"
hs_status_line:
        ldx #0
-       lda hline,x
        beq _o
        cmp #' '
        beq _num
        inx
        cpx #HLINE_MAX
        bne -
_o:     rts
_num:   inx
_d:     lda hline,x
        sec
        sbc #'0'
        cmp #10
        bcs _o
        pha
        lda http_code                   ; code = code * 10 + digit
        sta tmp0
        lda http_code+1
        sta tmp1
        asl http_code
        rol http_code+1
        asl http_code
        rol http_code+1
        clc
        lda http_code
        adc tmp0
        sta http_code
        lda http_code+1
        adc tmp1
        sta http_code+1
        asl http_code
        rol http_code+1
        pla
        clc
        adc http_code
        sta http_code
        bcc +
        inc http_code+1
+       inx
        bra _d

; does hline start with the string at A/X? zero flag set when it does
hs_match:
        sta tptr
        stx tptr+1
        ldy #0
-       lda (tptr),y
        beq _yes
        cmp hline,y
        bne _no
        iny
        bra -
_yes:   lda #0
_no:    rts

s_clen: .null "content-length:"
s_te:   .null "transfer-encoding: chunked"
s_date: .null "date:"

hs_header_line:
        lda #<s_clen
        ldx #>s_clen
        jsr hs_match
        bne +
        ldx #15
        jmp hs_parse_clen
+       lda #<s_te
        ldx #>s_te
        jsr hs_match
        bne +
        lda #1
        sta hs_chunked
        rts
+       lda #<s_date
        ldx #>s_date
        jsr hs_match
        bne _o
        ; "date: fri, 06 nov 2026 00:29:23 gmt": the time starts at column 23
        lda hline+25
        cmp #':'
        bne _o
        ldx #23
        jsr hs_2d
        sta http_h
        ldx #26
        jsr hs_2d
        sta http_m
        ldx #29
        jsr hs_2d
        sta http_s
_o:     rts

hs_2d:  lda hline,x
        sec
        sbc #'0'
        sta tmp0
        asl
        asl
        adc tmp0
        asl
        sta tmp0
        lda hline+1,x
        sec
        sbc #'0'
        clc
        adc tmp0
        rts

hs_parse_clen:
        lda #0
        sta hs_clen
        sta hs_clen+1
        sta hs_clen+2
-       lda hline,x
        beq _end
        sec
        sbc #'0'
        cmp #10
        bcs _nx                         ; (the space after the colon)
        pha
        lda hs_clen                     ; x10
        sta tmp0
        lda hs_clen+1
        sta tmp1
        lda hs_clen+2
        sta tmp2
        asl hs_clen
        rol hs_clen+1
        rol hs_clen+2
        asl hs_clen
        rol hs_clen+1
        rol hs_clen+2
        clc
        lda hs_clen
        adc tmp0
        sta hs_clen
        lda hs_clen+1
        adc tmp1
        sta hs_clen+1
        lda hs_clen+2
        adc tmp2
        sta hs_clen+2
        asl hs_clen
        rol hs_clen+1
        rol hs_clen+2
        pla
        clc
        adc hs_clen
        sta hs_clen
        bcc _nx
        inc hs_clen+1
        bne _nx
        inc hs_clen+2
_nx:    inx
        cpx #HLINE_MAX
        bne -
_end:   lda #1
        sta hs_havelen
        rts

; Common end of a fetch: an answer needs status 200 and a body. Carry set = failed.
http_check:
        lda http_code+1
        cmp #>200
        bne _bad
        lda http_code
        cmp #<200
        bne _bad
        lda http_len
        ora http_len+1
        ora http_len+2
        beq _nobody
        clc
        rts
_nobody:
        lda #E_RECV
        bra +
_bad:   lda #E_HTTP
+       sta net_err
        sec
        rts

; ---- hosts: names and resolved addresses ----
H_FORECAST = 0
H_GEOCODE  = 1
H_RADAR    = 2
host_ip:   .fill 12, 0
host_lo:   .byte <host0, <host1, <host2
host_hi:   .byte >host0, >host1, >host2
host0:     .null "api.open-meteo.com"
host1:     .null "geocoding-api.open-meteo.com"
host2:     .null "mesonet.agron.iastate.edu"

net_err_lo: .byte <e0,<e1,<e2,<e3,<e4,<e5,<e6,<e7,<e8,<e9,<e10,<e11,<e12
net_err_hi: .byte >e0,>e1,>e2,>e3,>e4,>e5,>e6,>e7,>e8,>e9,>e10,>e11,>e12
e0:     .null "OK"
e1:     .null "STACK NOT LOADED"
e2:     .null "DHCP TIMEOUT - CHECK CABLE"
e3:     .null "DNS LOOKUP FAILED"
e4:     .null "CANNOT CONNECT"
e5:     .null "SEND FAILED"
e6:     .null "NO DATA FROM SERVER"
e7:     .null "SERVER ERROR"
e8:     .null "BAD DATA FROM SERVER"
e9:     .null "BAD RADAR IMAGE"
e10:    .null "RADAR DECODE FAILED"
e11:    .null "RADAR CHECKSUM BAD"
e12:    .null "COULD NOT SAVE"
