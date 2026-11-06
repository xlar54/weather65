;=======================================================================================
; MEGA65 hardware registers. Extend as needed; mega-dust/src/platform.asm has more.
;=======================================================================================
VIC_CTRL1               = $D011         ; bit7 = raster bit 8, bit4 = DEN
VIC_RASTER              = $D012
VIC_IRQ_STATUS          = $D019
VIC_IRQ_MASK            = $D01A
BORDERCOL               = $D020
BACKCOL                 = $D021
VIC4_KEY                = $D02F         ; write $47,$53 to unlock VIC-IV
VIC3_ROMBANK            = $D030
VIC3_CTRL               = $D031         ; bit6 = 40 MHz, bit7 = H640
VIC4_TEXTXPOS           = $D04C         ; 12 bit, H640 units
VIC4_TEXTYPOS           = $D04E
VIC4_CTRL               = $D054         ; bit0 CHR16, bit2 FCLRHI
VIC4_LINESTEP           = $D058         ; bytes per screen row
VIC4_SDBDRWD            = $D05C         ; side border width
VIC4_HOTREG             = $D05D         ; bit7 = hot registers
VIC4_CHRCOUNT           = $D05E
VIC4_SCRNPTR            = $D060         ; 28 bit
VIC4_COLPTR             = $D064
VIC4_DISPROWS           = $D07B

VIC4_CHARPTR            = $D068         ; 24 bit charset address (text modes)

; hardware sprites (VIC-II layout + VIC-IV extras)
SPR_XLO                 = $D000         ; sprite n X = $D000 + 2n, Y = $D001 + 2n
SPR_XMSB                = $D010         ; X bit 8, one bit per sprite
SPR_ENABLE              = $D015
SPR_YEXP                = $D017
SPR_PRIO                = $D01B         ; 1 = behind the foreground
SPR_MC                  = $D01C
SPR_XEXP                = $D01D
SPR_MC1                 = $D025
SPR_MC2                 = $D026
SPR_COLOR               = $D027         ; + n
SPR_XMSB9               = $D05F         ; X bit 9 (VIC-IV)
SPR_PTRLO               = $D06C         ; 16-bit sprite pointer table address
SPR_PTRHI               = $D06D
SPR_PTRBNK              = $D06E         ; bit 7 = 16-bit pointers
SPR_16COL               = $D06B         ; 16-colour sprite enable (NOT a charset register)
SPR_YMSB8               = $D077
SPR_YMSB9               = $D078

PLATFORM_FLAGS          = $D60F         ; bit 5 set on real hardware, clear in Xemu
ASCIIKEY                = $D610         ; hardware typing queue (write to dequeue)
POT_P1X                 = $D620         ; 1351 mouse / paddles, port 1
POT_P1Y                 = $D621
POT_P2X                 = $D622         ; port 2
POT_P2Y                 = $D623
RTC_BASE                = $FFD7110      ; real-time clock (BCD; see lib/rtc.asm)
HWRNG                   = $D7EF         ; hardware random number; ready = $D7FE bit 7
HWRNG_READY             = $D7FE
COLOUR_RAM              = $FF80000

SID1                    = $D400
AUD_CTRL                = $D711         ; bit7 = audio DMA enable
AUD_CH0                 = $D720         ; channel n at $D720 + n * 16
AUD_RVOL                = $D71C         ; channel n volume on the other side: $D71C + n
MIX_SEL                 = $D6F4
MIX_DATA                = $D6F5
DIVOUT                  = $D768         ; 32.32 quotient of MULTINA / MULTINB
DIVBUSY                 = $D70F         ; bit 7

CIA1_PRA                = $DC00
CIA1_PRB                = $DC01
CIA1_DDRA               = $DC02
CIA1_DDRB               = $DC03
CIA1_ICR                = $DC0D
CIA2_ICR                = $DD0D

MULTINA                 = $D770
MULTINB                 = $D774
MULTOUT                 = $D778

DMA_ADDRLSB_ETRIG       = $D705
DMA_ADDRMSB             = $D701
DMA_ADDRBANK            = $D702
DMA_ADDRMB              = $D704
DMAOPT_F018B            = $0B
DMAOPT_SRC_MB           = $80
DMAOPT_DST_MB           = $81
DMAOPT_DST_STEP_INT     = $85
DMAOPT_TRANSP_ON        = $07
DMAOPT_TRANSP_VAL       = $86
DMAOPT_END              = $00
DMACMD_COPY             = $00
DMACMD_FILL             = $03

HTRAP00                 = $D640
HYPPO_SETNAME           = $2E
HYPPO_D81ATTACH0        = $40

KERNAL_SETBNK           = $FF6B
KERNAL_SETLFS           = $FFBA
KERNAL_SETNAM           = $FFBD
KERNAL_LOAD             = $FFD5
KERNAL_SAVE             = $FFD8
KERNAL_CHROUT           = $FFD2

STAGE                   = $50000        ; boot staging buffer for KERNAL loads (<= 60 KB)
ATTIC                   = $8000000
