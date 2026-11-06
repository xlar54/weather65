;=======================================================================================
; lib/system.asm - taking over the machine, the frame IRQ.
;
;   #TAKEOVER          40 MHz, VIC-IV unlocked, no MAP, RAM everywhere but I/O, RAM
;                      palette, stack and base page reset, CIA directions re-pinned.
;                      A macro, not a routine: it resets the stack.
;                      Do any KERNAL disk loading BEFORE this (lib/loader.asm).
;   irq_install        one raster IRQ per frame at IRQ_LINE: counts frame_count and
;                      calls the routine in irq_hook (set it before or after; 0 = none).
;                      CIA interrupts are masked. Call with interrupts off, then cli.
;   wait_frame         returns at the start of the next frame
;
; The hook runs inside the IRQ: it must leave tmp*/ptr* alone (they belong to the
; main program) - give it its own variables.
;=======================================================================================

IRQ_LINE        = 250                   ; below the 25 text rows (PAL); change per project

TAKEOVER .macro
        sei
        lda #65
        sta $00                         ; 40 MHz
        lda #$47
        sta VIC4_KEY
        lda #$53
        sta VIC4_KEY
        lda #0                          ; no MAP: legacy banking decides everything
        tax
        tay
        taz
        map
        eom
        lda #$35                        ; RAM everywhere except I/O at $D000
        sta $01
        lda #%00000100                  ; no C65 ROMs; colours 0-15 from the RAM palette
        sta VIC3_ROMBANK
        ldx #$ff
        txs
        lda #0
        tab                             ; base page = $00xx
        lda #$ff                        ; the 40 MHz switch can disturb these:
        sta CIA1_DDRA                   ; port A out (keyboard columns)
        lda #0
        sta CIA1_DDRB                   ; port B in
        sta DMA_ADDRMB
        sta DMA_ADDRBANK
.endmacro

irq_install:
        lda #$7f
        sta CIA1_ICR
        sta CIA2_ICR
        lda CIA1_ICR
        lda CIA2_ICR
        lda #<l_irq_handler
        sta $fffe
        lda #>l_irq_handler
        sta $ffff
        lda #<l_nmi_handler
        sta $fffa
        lda #>l_nmi_handler
        sta $fffb
        lda #<IRQ_LINE
        sta VIC_RASTER
        lda VIC_CTRL1
        and #$7f
        ora #(>IRQ_LINE) << 7
        sta VIC_CTRL1
        lda #1
        sta VIC_IRQ_MASK
        lda #$ff
        sta VIC_IRQ_STATUS
        rts

irq_hook:       .word 0

l_irq_handler:
        pha
        phx
        phy
        phz
        lda #$ff
        sta VIC_IRQ_STATUS
        inc frame_count
        lda irq_hook+1
        beq +
        jsr l_irq_call
+       plz
        ply
        plx
        pla
l_nmi_handler:
        rti
l_irq_call:
        jmp (irq_hook)

; rom_unprotect - make the "ROM" area $20000-$3FFFF writable RAM (after #TAKEOVER, when
; the KERNAL/BASIC are no longer needed). The hypervisor trap toggles, so test first.
rom_unprotect:
        jsr l_rom_writable
        bcs +
        lda #$70
        sta HTRAP00
        clv
+       rts
l_rom_writable:
        lda #$ff
        sta ptr0
        sta ptr0+1
        lda #$02
        sta ptr0+2
        lda #0
        sta ptr0+3
        ldz #0
        lda [ptr0],z
        eor #$5a
        sta tmp0
        sta [ptr0],z
        lda [ptr0],z
        cmp tmp0
        beq +
        clc
        rts
+       sec
        rts

wait_frame:
        lda frame_count
-       cmp frame_count                 ; (a memory read: audio DMA needs idle cycles)
        beq -
        rts
