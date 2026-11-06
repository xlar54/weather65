# MEGA65 programming notes

The one reference for MEGA65 machine-code work: memory, boot and KERNAL, MAP, DMA, video, audio,
input, files, maths, Ethernet, Xemu and real hardware, and the toolchain. `.claude/CLAUDE.md`
has the short list of rules; this file has the detail behind them.

Facts are marked when they are not settled:

- **[Xemu]**: seen only in Xemu, not yet confirmed on a real MEGA65.
- **[HW]**: confirmed on real hardware.
- **[?]**: uncertain, inferred, or contradicted between sources.

Book references are to the MEGA65 Compendium (Dec 2024 build) by printed page number. To grep
it, extract its text once with pypdf (`PdfReader(...).pages[i].extract_text()`) into a scratch
file with a marker per page, then search for register names such as `MIXREGSEL`, `CH0CURADDR`,
`hyppo_d81attach0` or `ETRIG`.

| Topic | Book |
|---|---|
| Memory map | Chapter 14 (14-10 to 14-12: chip RAM, attic, reserved areas) |
| Audio DMA | Appendix P, P-18 to P-23 |
| Audio mixer | Appendix V, V-23 to V-26 |
| Hypervisor (HYPPO) calls | Appendix N |
| Memory restrictions | J-5 |

---

## 1. Memory

### Physical layout (28-bit addresses)

| Range | What |
|---|---|
| `$0000000-$005FFFF` | Chip RAM, 384 KB (banks 0-5). The CPU, the DMAgic, the VIC-IV and audio DMA all reach it. |
| `$0020000-$003FFFF` | Banks 2-3: the ROM image (BASIC65, KERNAL, DOS, charsets). Write-protected; hypervisor trap `$70` toggles the protection. Free RAM once the KERNAL is gone for good. |
| `$8000000-$87FFFFF` | Attic RAM (HyperRAM), 8 MB. CPU (32-bit indirect) and DMA only: **the VIC-IV and audio DMA can't read it**. The CPU reaches it more slowly than chip RAM. |
| `$FF80000-$FF87FFF` | Colour RAM, 32 KB |
| `$FFD3000-$FFD3FFF` | VIC-IV and other I/O, as seen at `$D000` |
| `$FFD6E00` | SD card sector buffer |
| `$FFDE800` | Ethernet TX/RX buffer |
| `$FF7E000` | WOM: the character set on real hardware |

### Reserved and free chip RAM

| Range | Status |
|---|---|
| `$00002-$015FF` | KERNAL / BASIC (book) |
| `$01600-$01EFF` | **Always free** for programs. A good base page (`$1600`) and buffers. |
| `$00600-$007FF` | **Not free**: the C65 keeps sprite shapes there. |
| `$0FF00-$0FFFF` | KERNAL (book) |
| `$10000-$11FFF` | **Reserved**: C65 DOS variables and buffers. Disk I/O overwrites it. Never load here. |
| `$12000-$1F6FF` | BASIC arrays and strings: free once BASIC isn't used. Bank-1 data usually starts at `$12000`. |
| `$1F700-$1F7FF` | Reserved (book) |
| `$1F800-$1FFFF` | First 2 KB of colour RAM (a window). A buffer that reaches it garbles the top character rows. |
| `$40000-$5FFFF` | Free after the takeover; the usual place for framebuffers and boot staging. BASIC65's bitplane graphics live here, and loading through bank 5 overwrites whatever is there (for example sprite shapes at `$5FA00`). |

- Banks 2 and 3 hold the ROM, so a program that keeps BASIC65 resident has chip banks 0, 1, 4 and 5 plus attic.
- A 320x200 FCM framebuffer is 64000 bytes and fits one bank. 640x200x8 fits in `$40000-$5F3FF`; 640x400x8 (256 KB) doesn't fit in banks 4-5.
- Real hardware doesn't clear RAM at power-on; Xemu does. Clear the base page and every uninitialised variable at boot. Test with Xemu `-initattic <8 MB random file>`.

### Colour RAM windows

Colour RAM appears three times:

- `$D800` (first 1 KB, only while I/O is banked in);
- `$1F800` (first 2 KB);
- `$FF80000` (all 32 KB).

Use `$FF80000` (32-bit pointer bytes `$00,$00,$F8,$0F`). COLPTR (`$D064-$D065`) moves where the
VIC-IV starts reading colour RAM. Push it 1-2 KB on to free `$D800`/`$1F800` as plain RAM at the
cost of that much colour RAM; the windows themselves don't move.

### Base page (zero page)

- BASIC owns `$02-$8F` while BASIC code runs. The KERNAL owns `$90-$FA` (some sources say up to `$FB`/`$FF`); `$FB-$FF` is free even with BASIC. During boot, use `$02-$8F` only.
- The KERNAL screen editor's line input (CHRIN from the keyboard) writes `$F7-$FE`. CHROUT, GETIN and file CHRIN don't.
- `TAB` moves the base page anywhere (B register). Put B back to `$00` before calling the KERNAL; the KERNAL's IRQ handler preserves a custom B.
- After a full takeover the whole page is yours.

### Example layouts that worked

- **Full takeover game:**
  - program `$2001`-`~$A000`;
  - screen RAMs at `$0800`, `$1000`;
  - sprites `$20000-$3FFFF` (ROM area, unprotected);
  - framebuffers `$40000`, `$50000` (also boot staging);
  - bank-1 data `$12000-$1F7FF`;
  - attic: sprite sheets, per-level sets, background caches.
- **KERNAL kept, ROMs banked out:**
  - base page `$1600`, line buffer `$1700`, stack `$1800-$1DFF`, file-name buffer `$1E00`;
  - code `$2001-$7DFF`;
  - overlay window `$8000-$CFFF`;
  - data `$E000-$EFFF`, code `$F000-$FEFF`.
- Lay the map out in one document and update it whenever a region moves. Guard every section with `.cerror * > $XXXX`.

---

## 2. Boot, KERNAL and loading

### Boot order (each step is where it is for a reason)

```
cld
cli                          ; pristine IRQ state for the boot LOADs
(capture $01, $D030, CHARPTR $D068-$D06B, IRQ/NMI vectors)
(short raster settle: a cold autoload races the drive)
(all KERNAL disk I/O)        ; here and nowhere else
sei
lda #65 / sta $00            ; 40 MHz
(MAP / takeover)
(re-pin CIA DDRs: $DC02 = $FF, $DC03 = 0)   ; the speed switch can disturb them
(screen mode, IRQ install)
```

Every reordering of this that has been tried broke something.

### KERNAL LOAD

- Works only in the pristine BASIC65 state: before `sei`, before the 40 MHz switch, before any MAP. 40 MHz itself is fine for LOAD/SAVE; it's the environment that breaks it.
- Call `SETBNK` (A = data bank, X = 0) before every `SETLFS`/`SETNAM`/`LOAD`/`SAVE`, or the data goes to whatever bank was set last.
- The 2-byte PRG header is part of the load: with secondary address 1 a load to `$07FE` puts the body at `$0800`. Secondary address 0 loads to X/Y and skips the header.
- Load big files to a chip-RAM staging buffer (bank 5, `$50000`) and DMA them up to attic. Files over one bank: split them at build time.
- [?] A SETBNK 5 load failed to land in bank 5 when called from a BASIC-resident runtime (not the boot state); reading the file byte by byte through the DOS data channel worked there. From the pristine boot state, staging at `$50000` works.
- Bound the retry loop for a missing file (3 attempts, then a visible error, for example a border colour). An unbounded retry hangs on hardware.
- A FILE NOT FOUND at start can look like a hang: blue screen, blinking drive LED, PC cycling in the C65 editor at `$E3xx-$EBxx`.
- About 160 KB packed takes a few seconds; 2.5 MB through the KERNAL takes a long time. `hyppo_loadfile_attic` for files on the SD card is a faster option [?, untested].

### BASIC stubs and autoboot

- `BANK 0 : SYS 8210` puts the entry at `$2012` (the template's stub).
- `AUTOBOOT.C65` on the disk starts on reset. Either write the game twice (first file + `AUTOBOOT.C65`) or make `AUTOBOOT.C65` a one-line BASIC program `10 RUN "NAME"`.
- Tokenised BASIC PRG: load address, then lines of (next-line pointer, binary line number, tokens, `$00`), ending with a `$0000` pointer. BASIC65 extended tokens are two bytes, `CE xx` / `FE xx`.
- `DLOAD` of a PRG writes bank-0 RAM from `$2001` and can load contiguously up to `$F6FF`. [?] Bytes past `$C000` in a loaded PRG don't chain-load reliably; clear `$C000-$CFFF` at start.

### Calling the KERNAL after the takeover

Needs a trampoline that rebuilds the boot environment for one call and then puts the game back:

- It runs below `$2000`, so the boot MAP doesn't unmap it. It can be kept in attic and DMAd down only while file I/O runs.
- Restore:
  - the boot MAP (MAPLO `$E300`, MAPHI `$B300`; the SYS map is MAPH `$8300` with `$E000` from `$30000`);
  - the captured `$01` and `$D030` (don't hardcode them);
  - B = 0;
  - the stack on page 1;
  - the KERNAL's IRQ/NMI vectors;
  - then `cli`.
- Mask the VIC IRQ while it runs; put the game's MAP, `$01`, `$D030`, B, stack and IRQ back afterwards.
- The KERNAL changes the VIC-IV screen and charset pointers (`$D060-$D063`, `$D068-$D06A`), and writing `$D031` resets the sprite pointer (`$D06C-$D06E`). Save and restore them around every call. A LOAD of a missing file resets CHARPTR to `$021800`.
- The data must be in bank 1+ or below `$2000`. Code that runs a CHKIN/CHRIN or CHKOUT/CHROUT loop must sit below `$8000`, because the DOS maps itself in above that.
- The C65 DOS lives in the `$8000`/`$A000`/`$C000` ROMs: if the program banked them out, bank them back in before every channel or file call.
- **[Xemu]** In-game OPEN/CHKOUT/CHROUT/CLOSE worked in Xemu without a custom MAP. On hardware the same calls from a custom MAP hang HYPPO. Test disk I/O on hardware every time.

### IRQ vectors with the KERNAL running

Poking `$0314`/`$0315` crashes: the MEGA65 KERNAL's RAM vector table isn't there. Use KERNAL
`VECTOR` (`$FF8D`): SEC with X/Y = a buffer reads the table, patch the IRQ word, CLC writes it
back, and chain with `jmp (oldvec)`.

### Returning to BASIC

- Save CHARPTR (all 4 bytes, `$D068-$D06B`, including the megabyte byte) at boot. Write it back after CINT (`$FF81`): CINT's hot-register writes recompute the pointer and undo an earlier restore. A hardcoded `$02D000` works in Xemu and garbles the font on hardware, where the font is in WOM (`$FF7E000`). [HW]
- Set `$01 = $37` before CINT/IOINIT.
- A warm `JMP ($FFFC)` reloads the default palette.

### Calling code in other banks from BASIC

- `JSRFAR` (`$FF6E`) can enter another bank only in the window `X.$2000-X.$7FFF`; bank-5 code must load at `$52000` or higher.
- `BLOAD "name",P($52000)` loads to a 28-bit address. `BLOAD "x",P($42000),R` loads machine code into bank 4, 2 KB past the bank start to respect BASIC's MAP.
- `SYS addr,a,x,y,z` passes registers in; `RREG A,X,Y,Z` reads them back.

---

## 3. Taking over the machine

```
sei
lda #65 / sta $00                 ; 40 MHz
lda #$47 / sta $D02F              ; VIC-IV unlock
lda #$53 / sta $D02F
lda #0 / tax / tay / taz / map / eom   ; no MAP: plain RAM
lda #$35 / sta $01                ; RAM everywhere except I/O
lda #4 / sta $D030                ; RAM palette
txs
tab                               ; base page = $00
lda #$ff / sta $DC02              ; re-pin the CIA data directions
lda #0 / sta $DC03
```

Then install your own `$FFFE` IRQ. An all-zero MAP while the KERNAL's IRQ is still live removes
its vectors: a BRK storm with PC = `$0000`. `sei` first.

`$C000-$CFFF` becomes usable RAM once the character ROM is mapped out. Until `$D030` banks the
ROMs out, CPU **reads** at `$C000-$CFFF` see the C64 KERNAL ROM shadow (`$2C000`) although writes go
to RAM (symptom: a screenful of pi characters from walking ROM `$FF` padding). One bank-out mask:
`$D030 & %11000111`. Data read before the bank-out must be below `$C000`.

---

## 4. MAP

Most programs don't need MAP. DMA and 32-bit indirect addressing (`lda [ptr],z`) reach all of
memory. Use MAP for fast repeated access to a window, or for banking code.

Dan Sanderson's recommended default model:

- Leave `$00/$01` and `$D030` at their defaults and launch from BASIC with SYS, assuming the SYS MAP.
- Reach above bank 0 with DMA and 32-bit indirect addressing.
- If you need MAP, design its use early and stick to it. Prefer MAPLO, and leave `$0000-$1FFF` alone.
- If you don't need the KERNAL, ditch it and install your own interrupt handlers.

### How it works

- The 64 KB CPU space is eight 8 KB blocks. MAPLO covers `$0000-$7FFF`, MAPHI `$8000-$FFFF`. Each half has **one shared offset** and four enable bits.
- `actual address = CPU address + offset`. The offset is in 256-byte units, and it is an offset, not a destination: `$2000` with offset `$45200` is `$47200`.
- Registers: MAPLO = X:A, MAPHI = Z:Y. X/Z high nibble = block enables, low nibble = offset bits 16-19; A/Y = offset bits 8-15.

  | Enable bit | MAPLO (X) | MAPHI (Z) |
  |---|---|---|
  | 7 | `$6000-$7FFF` | `$E000-$FFFF` |
  | 6 | `$4000-$5FFF` | `$C000-$DFFF` |
  | 5 | `$2000-$3FFF` | `$A000-$BFFF` |
  | 4 | `$0000-$1FFF` | `$8000-$9FFF` |

  Example: `lda #$52 / ldx #$24 / ldy #$00 / ldz #$B3 / map / eom` maps `$2000-$3FFF` with
  offset `$45200`, and `$8000-$BFFF` plus `$E000-$FFFF` with offset `$30000`.
- MAP freezes IRQ and NMI until EOM (the I flag is untouched). Always finish with EOM, and only after the last MAP of a sequence. Never run MAP code from a block the new map removes.
- **Unmapped is not offset 0.** An unmapped block falls through to the legacy banking (`$00/$01`, `$D030`, ROMs, I/O). A block mapped with offset 0 is plain RAM, ignoring all of that: even `$0000/$0001` become RAM.
- **Beyond 1 MB:** issue MAP twice. The first MAP, with X = `$0F` / Z = `$0F`, sets the megabyte byte from A (MAPLO) / Y (MAPHI). The second MAP sets the enables and the offset. The megabyte takes effect right after the first MAP, so the running code must not disappear in between. For example, `$FF80000` to `$4000`: `lda #$FF / ldx #$0F / ldy #$FF / ldz #$0F / map / lda #$C0 / ldx #$C7 / ldy #$C0 / ldz #$17 / map / eom`.
- You can't read MAP back with an instruction: use the hypervisor `hyppo_get_mapping` or the Matrix Mode monitor. The BASIC `MONITOR` shows the CPU's mapped view; the Matrix monitor shows real memory.

### The boot map

| Range | At boot |
|---|---|
| `$0000-$1FFF` | Unmapped: bank 0 RAM |
| `$2000-$BFFF` | Mapped to ROM in bank 3 (MAPLO `$E300`, MAPHI `$B300`) |
| `$C000-$CFFF` | Unmapped, then ROM from bank 2 via `$D030` (a ROM-like mapping independent of MAP) |
| `$D000-$DFFF` | Unmapped, then I/O via `$01` |
| `$E000-$FFFF` | Mapped to the KERNAL in bank 3 |

- The KERNAL's IRQ handlers live at `$E000-$FFFF` through MAPHI. While KERNAL interrupts run, keep `$E000-$FFFF` mapped to `3.E000`.
- The SYS map is MAPH `$8300`, MAPL `$E000`: the KERNAL stays at `$E000`, and `$0000-$1FFF` and `$C000-$DFFF` are unmapped.
- Because each half shares one offset, the KERNAL can't stay mapped next to a movable `$8000` window. One alternative is a DMA swap, about 1 ms with IRQs still running: stash `$8000-$BFFF` to spare RAM, DMA the code in, `jmp ($8000,x)`, then copy it back if it holds state and restore the stash.
- The DOS maps itself in at `$8000`: DOS RAM (8 KB at `$10000`) and its ROM at `$8000 + $18000 = $20000`.

---

## 5. 45GS02 CPU and 64tass

### CPU

- `.cpu "45gs02"` at the top of every file (or `64tass --m45gs02`), or you don't get map/eom/bra/ldz/Q ops.
- **`STZ` stores the Z register, not zero.** Use `lda #0 / sta`. Code that assumes otherwise "works" while Z happens to be 0 and fails intermittently. [HW] Xemu accepted `stz $D063` while real hardware left the screen-pointer megabyte nonzero: never use STZ on VIC-IV registers. Grep for `stz` when something is subtly wrong.
- `inw`/`dew`/`asw` work on the base page only.
- There is no `lda abs,z`, `cpx abs,x`, `cpy abs,x` or `ldx abs,x`.
- 32-bit indirect: `lda [zp],z` / `sta [zp],z` with a 28-bit address in 4 base-page bytes reaches all chip RAM and attic. Set Z (`ldz #0`) before each one. Keep IRQs off if an IRQ handler might change Z [?].
- `ldx #n-1 / ... / dex / bpl` handles at most 128 bytes. Count up (`inx / cpx #n / bne`) for longer blocks.
- An `asl`/`tax` index wraps past 127 entries: use separate lo/hi tables.
- Multi-byte `adc`/`sbc`/`rol`/`ror` loops: count with `dey`/`dex`, never a compare, which changes carry.
- Never keep a loop counter in A/X/Y (or a library `tmp`) across a `jsr` you don't control: use memory or `phx`/`plx`. Make helpers preserve the caller's registers on every path, including the miss path.
- BCD decimal mode works (handy for scores).
- `bra` (2 bytes) can replace a `jmp` (3 bytes) when patching code in place.
- The CPU stack can be 16-bit and outside page 1. Put it back on page 1 for KERNAL calls.
- A 320-pixel screen needs 16-bit X everywhere. Clip tests must be true 16-bit compares: high byte first, then the low byte only when the high bytes are equal.

### Hardware maths

| What | Registers |
|---|---|
| Multiply | MULTINA `$D770` (32-bit) Ã— MULTINB `$D774` (32-bit) = `$D778` (64-bit, immediate). The multiplier and the divider share the inputs: don't interleave unrelated maths. |
| Divide | Results at `$D768-$D76F`, 32.32 fixed point: `+0..+3` is the fraction, `$D76C` (+4) the integer part. Wait while `$D70F` bit 7 is set. |
| Random | `$D7EF`. `$D7FE` bit 7 set means it's **not** ready: bound the wait. |

Code that touches the `$D7xx` registers must not run from a window mapped over I/O.

### 64tass

- Symbols are **case-insensitive by default** (`tool_fill` clashes with `TOOL_FILL`). `-C` makes them case-sensitive.
- `_local` labels are scoped between global labels: a global label in the middle of a routine breaks them. Anonymous `+`/`-` resolve to the next one and cause bugs in branchy code; prefer named labels. `--` can't be a label.
- Macro parameters need defaults to be optional: `NAME .macro a, b="", c=""`.
- `.null "a", "b"` makes one string `"ab"`.
- Data included before `* = $2001` makes the PRG load at `$0000` (`?SYNTAX ERROR`). Include generated data at the end.
- `range()`, `.for x in list`, `sin()` work; list comprehensions don't.
- `.weak` / `.endweak` gives overridable defaults. `.logical` assembles code at one run address while placing it elsewhere in the image (overlay segments).
- `-D NAME=value` sets build-time constants (test builds). A separate PRG can import another build's symbols by `.include`-ing its label file.
- To see by how much something overflows, temporarily turn the `.cerror` guard into `.warn format("...$%04x", *)`.
- The CPU name `45gs02` is case-sensitive. Source typed on the MEGA65 may come out upper-case, so pass `--m45gs02` instead of `.cpu`.

---

## 6. DMA (F018B, enhanced)

- The list is `$0B` (F018B), then options: `$80 mb` / `$81 mb` source/destination megabyte, then `$00`. Then the job: cmd, count (2), source (3), destination (3), sub-command, modulo (2). Trigger by writing the list MSB to `$D701` (and bank to `$D702`), then the LSB to `$D705`.
- Useful options:

  | Option | Effect |
  |---|---|
  | `$83 n` | Source step (whole bytes) |
  | `$85 n` | Destination step (whole bytes) |
  | `$07` + `$86 v` | Transparency on, transparent value v |

  Destination step 8 writes one FCM pixel column. Destination step 21 transposes rows into column-major 24x21 sprites.
- **The DMAgic wraps inside a 1 MB megabyte.** A copy that crosses a megabyte boundary on either side silently wraps. Split it (the library's `dma_copy_far` does).
- DMA doesn't care about the MAP state: once data is in attic, the CPU map can be anything.
- Inline DMA lists (`sta $D707` followed by the list) can't be re-run; use static lists via `$D701`/`$D705` for parameterised jobs.
- About 4 KB moves in microseconds at 40 MHz. Swapping a 20-24 KB overlay takes about 1-2 ms. A DMA fill clears a whole attic region in one job.
- Audio DMA keeps running and steals cycles during other DMA jobs.

---

## 7. Video (VIC-IV)

### General

- Unlock with `$47`, `$53` to `$D02F`. Turn hot registers off (`$D05D` bit 7) so C64-style writes (`$D011`, `$D016`, `$D018`) don't undo your layout.
- `$D012` holds raster bits 0-7; bit 8 is `$D011` bit 7. **Never copy `$D011` bit 7 back**: reading it gives the beam's bit 8, but writing it sets the raster-compare bit 8. A read-modify-write (even TSB/TRB) while the beam is below line 256 moves the IRQ to a line that doesn't exist, and it never fires again. Mask bit 7 and OR in `(>IRQ_LINE) << 7`.
- `TEXTXPOS` and the side border are in H640 units (2 per H320 pixel). A black line at the top: TEXTYPOS hardcoded while TBDRPOS differed; copy TBDRPOS into TEXTYPOS.
- `$D031` holds the column/row mode. Writing it resets the sprite pointer (`$D06C-$D06E`).
- Screen RAM pointer `$D060-$D063`, CHARPTR `$D068-$D06B`, COLPTR `$D064-$D065`.
- The VIC-IV can't fetch from attic: DMA anything shown into chip RAM.
- A 256-line display needs PAL. 60 Hz logic on 50 Hz PAL: 6 logic ticks every 5 frames.
- **[Xemu]** Xemu ignores mid-frame `TEXTXPOS` and side-border changes, so raster splits for scrolling don't work there. Bake fine scroll into the framebuffer instead.

### Palette

- `$D100`/`$D200`/`$D300` = red/green/blue for 256 entries, **nibble-swapped**: write `(v & 15) << 4 | v >> 4`. `$D030` bit 2 selects the RAM palette. `$D070` picks the banks that are edited and shown (screen, sprites, alt).
- Reserve fixed entries (UI colours, cycling logos) and quantise the art around them at build time.
- Palette-only effects (dimming, cycling, night) cost no redraw.

### Full Colour Mode (FCM) framebuffer

- CHR16 + FCLRHI (`$D054` bits 0 and 2): 16-bit char numbers, one byte per pixel, 64 bytes per char. Char number = address / 64. Glyphs above `$3FC0` need char numbers above 255, so 8-bit char code silently truncates.
- Give each cell its own char and lay chars out **column by column**: offset = `(x>>3) * rows * 64 + y*8 + (x&7)` (for 32 rows that's `(x>>3)*$800`). Row-major also works: `((y>>3)*cols + (x>>3))*64 + (y&7)*8 + (x&7)`.
- Clearing colour RAM leaves the per-char NCM bit off, so chars render as FCM.
- Double-buffer by flipping `$D060-$D063` in a raster IRQ in the bottom border. The same IRQ can feed the music.
- Game-loop pattern: logic is plain sequential code that calls `frame` whenever it waits. `frame` draws into the back buffer, flips at the next vertical blank, and reads the controls.
- Sync heavy redraws to vertical blank; poll input before the wait so the blank is all drawing time.

### Software sprites and scrolling in a framebuffer

- DMA blitter: one transparent F018B job per sprite pixel column (destination step 8, colour 0 transparent). No count or multiplexing limit. Store sprites column-major with per-sprite bounding boxes, so empty columns and rows cost nothing; the boxes double as hit boxes. Mirror horizontally by reversing the column order. The hardware multiplier computes offsets.
- Restore what sprites covered from a clean background copy in attic (dirty 8-pixel columns, or a whole-scene cache with one DMA a frame).
- Pixel-exact collision (overlap of two masks inside their boxes) behaves like the C64's hardware sprite collisions. Box tests were measurably different.
- **Fine scroll baked in:** prerender the level into attic column by column. When the scroll crosses a char column, DMA 41 columns into a chip-RAM stage. Every frame, copy the stage into the back buffer with 320 one-pixel-column jobs shifted by the fine scroll. Identical in Xemu and on hardware. **[Xemu]** The throughput on hardware (51 KB stage + 320 jobs a frame) is unmeasured.
- **Cheap 2-pixel scroll:** build the back buffer as the shown buffer moved 2 px left (8 DMA jobs, one per pixel phase, step 8), then DMA 2 new pixel columns from attic. 50 fps = 100 px/s.
- **Menus:** prebuild one full screen per selection and DMA the right one into the back buffer; draw only the changing text.
- **Split screen:** in one FCM screen, rows 0-19 as the double-buffered playfield and rows 20-24 as a static HUD (DMA digit cells into it).
- Draw a playfield that overlaps UI first and the UI on top, or give them separate cells.

### Text and NCM

- Text attributes reverse, underline, blink and bold are "colours 16-31" (VIC-III).
- ROM font A has the ASCII glyphs `{ } [ ] _ | \ ~`. The C64 upper-case font is at `$29000` in the ROM image, lower case at `$29800`.
- BASIC65's default sprite pointer table is at screen + `$7F8`.
- NCM (16 colours per char, 16 px wide chars): coarse and fine scroll work. Circles in 640-wide modes aren't aspect-corrected (the book).

### RRB (raster rewrite buffer) soft sprites

- 40-column screen with CHR16 + FCLRLO + FCLRHI (`$D054`). Each cell is 2 screen bytes + 2 colour bytes.
- Each row: the background cells, then overlay cells. Each soft-sprite row is `GOTOX x` (with the transparent-overlay flag) followed by its tiles. End every row with `GOTOX right edge` plus a blank tile.
- The visible 2 KB colour window limits a row to 80 bytes (6 sprite rows plus the terminator in a 40-column layout).
- Restore each row before appending overlays every frame.

### Hardware sprites

- Coordinates are VIC sprite coordinates: in H320, the top-left visible pixel is X = 24, Y = 50. X low bytes `$D000+2n`, Y `$D001+2n`; the 9th X bit in `$D010`, more MSBs in `$D05F`/`$D077`/`$D078` (read-modify-write to keep other sprites' bits).
- **Real hardware shows sprites 16 px further left than Xemu.** Detect real hardware with `$D60F` bit 5 and correct for it.
- 16-bit sprite pointers: `$D06E` bit 7 (so `$80`) enables; the table base is `$D06C/$D06D`; each entry = data address / 64 (64-byte aligned).
- `$D01B` priority: bit clear = in front of the characters. `$D01D` X-expand. A 24-px sprite shows 16 px by leaving the third byte 0.
- `$D06B` is the 16-colour sprite enable (despite some code calling it a charset register). 16-colour sprites are 16 px wide, 8 bytes a row, high nibble = left pixel. The transparent nibble is `$D027+n`, so set it to 0. Colour c of sprite n is entry n*16+c of the sprite palette bank (`$D070` bits 2-3). After the takeover the screen used bank 3 (`$D070` = `$FF`), so bank 1 is free for sprites.
- Tall sprites: `$D055` enables, `$D056` is the one shared height.
- Two 16-colour sprites side by side make a 32x32 overlay (512 bytes a frame, 15 colours each). Four of them use all 8 sprites and cost no framebuffer drawing.

---

## 8. Audio

### Audio DMA

- Four channels at `$D720`, `$D730`, `$D740`, `$D750` (16 bytes each). Write `$80` to `$D711` (AUDEN) first. Other `$D711` bits: 4 NOMIX (bypass the mixer, full volume, other sources muted), 5 block writes, 6/2-0 debug.
- Per channel (offsets from the base):

  | Offset | What |
  |---|---|
  | +0 | Control |
  | +1..+3 | BADDR (loop start, 24-bit) |
  | +4..+6 | FREQ (24-bit) |
  | +7..+8 | TADDR (end, **16 bits compared**) |
  | +9 | Volume (own side) |
  | +A..+C | CURADDR (start / current, 24-bit) |
  | +D..+F | Timing counter |

- Control bits:
  - 7: enable;
  - 6: loop;
  - 5: **1 = unsigned, 0 = signed** [HW];
  - 4: built-in sine;
  - 3: stopped (set by the hardware at the end);
  - 1-0: width (`11` 16-bit, `10` 8-bit, `01` high nibble, `00` low nibble).

  So `$E2` = unsigned looping 8-bit, `$A2` unsigned one-shot, `$C2` signed looping, `$82` signed one-shot. Silence is `$00` for signed data and `$80` for unsigned.
- Write the start to CURADDR and BADDR, the end to TADDR, the rate, the volumes, and the control byte **last**.
- FREQ = rate Ã— 2^24 / 40.5 MHz:

  | Rate | FREQ |
  |---|---|
  | 8000 Hz | `$000CF2` |
  | 10947 Hz | 4535 |
  | 11025 Hz | `$0011D7` |
  | 20417 Hz | `$00210A` |
  | 22050 Hz | `$0023AE` |
  | 40834 Hz | `$004214` |
  | 44100 Hz | `$00475D` |

  Rate and volume can change while a sample plays.
- Channels 0-1 feed the left output, 2-3 the right. `$D71C-$D71F` set each channel's volume on the opposite side (panning). `$D712` bit 0: saturate instead of wrapping when summing.
- **Chip RAM only** (24-bit addresses). Only the low 16 bits of the end are compared, so a sample is at most 64 KB. The ROM area `$20000-$3FFFF`, unprotected with trap `$70` once the KERNAL is gone, is a good place for samples.
- **The CPU must run at 40 MHz and execute memory reads in its wait loops.** Audio DMA uses the wait state of memory-operand reads; `loop: jmp loop` starves it. Put an `lda abs` in idle loops.
- The C64 trick of writing 4-bit samples to `$D418` depends on ~1 MHz timing and plays 40Ã— too fast at 40 MHz. Use audio DMA.
- The book says audio DMA can't raise interrupts, although IRQ registers exist at `$D713-$D717` [?]: poll.

### Streaming long audio

- Keep the data in attic. Loop a chip-RAM ring buffer (for example 8-16 KB, loop mode with top = ring size) and refill it every frame from attic. Use CURADDR (`$D72A/$D72B`) as the read position. It updates live, but read it hi/lo/hi until stable (the book says it isn't latched). The writer stops when it would reach the read position, which throttles it to real time. A 16 KB prebuffer at ~40.8 kHz gives 0.4 s of cushion.
- Packed audio: 4-bit samples or nibble-packed patterns can be expanded into the ring by the frame IRQ.
- **Stopping a looping channel [HW]:** clearing the enable bit and clearing `$D711` both failed to stop it on hardware. Instead, wait until the read position is within 32 samples of the write position, set TADDR to the write offset, and rewrite the control byte without the loop bit; the hardware stops at TADDR and sets bit 3. Compute the gap as signed (write - read), not masked by the ring size, or it misfires at the wrap. Or play the remaining data as one-shot segments.
- About 50 s of 11 kHz 8-bit mono fits on a D81 beside a few 320x200 pictures.

### Mixer

- Write `$80` to `$D711`, then set coefficients through `$D6F4` (select) / `$D6F5` (data). Wait at least 32 cycles between selects, or a write is lost.
- 128 coefficients of 16 bits, LSB first. Register = `output*32 + source*2`.
  - **Sources:** digital audio L/R = sources 8 and 9 (the DMA channels while AUDEN is on, else `$D6F8-$D6FB`); source `$F` is each output's master volume.
  - **Outputs:** 0/1 speakers (HDMI), 6/7 headphones; 2-5 are MEGAphone only.
- Values that work: `$10,$11,$12,$13,$30,$31,$32,$33,$D0,$D1,$F2,$F3` â† `$FF,$BF,$FF,$3F,$FF,$3F,$FF,$BF,$FF,$BF,$FF,$BF`. Master volumes: `$1E/$1F`, `$3E/$3F`, `$DE/$DF`, `$FE/$FF`.
- The boot defaults for the digital inputs aren't documented. Set them, or use NOMIX (`$90` to `$D711`, which mutes SID). [?] NOMIX may be silent on some cores.

### SID

- SID registers are write-only (peeks read `$FF`).
- Frequency tables must be computed for the PAL clock.
- For stereo, mirror voices: SID 1 to SID 2 and SID 3 to SID 4, so every part sounds in both speakers [?: this assumes the default mixer pans the SID pairs to opposite sides].

---

## 9. Input

- The CIA reverses the ports: `$DC00` = port 2, `$DC01` = port 1. Bits (active low): 0 up, 1 down, 2 left, 3 right, 4 fire.
- The keyboard matrix needs `$DC02 = $FF`, `$DC03 = 0` after the 40 MHz switch, or it returns the last row written.
- `$D610` is the hardware key queue (ASCII-like): 0 = empty; skip `$FF`; write anything to dequeue. It gives `{ } [ ] _ | \ ~` as printed. Function keys are `$F1/$F3/$F5/$F7` (not C64 PETSCII `$85-$88`).
- `$D619` injects a PETSCII key (automation from tests or BASIC) [Xemu].
- Mouse (1351): pots at `$D620/$D621` (port 1) and `$D622/$D623` (port 2). Re-read until two samples agree, but cap the retries and fall back to the last sample, or the loop can spin forever inside `sei`.
- **Xemu puts the 1351's buttons on its joystick-emulation port** (port 2 unless toggled), not on the mouse's port: the pointer moves but a port-1-only button read never sees a click. `lib/mouse.asm` reads the buttons on both ports (`MOUSE_BUTTONS_BOTH`). Source: Xemu `c64_get_joy_state()`. Headless tests that poke click flags don't catch this.
- Printing `$0E` switches the KERNAL screen to upper/lower case.

---

## 10. Files, disks and the DOS

### Disk images and file names

- c1541 stores lower-case ASCII names as PETSCII `$41-$5A` (shown upper case) and upper-case ASCII as shifted `$C1-$DA`. DOS matches bytes exactly. So write files with **lower-case** names in c1541, and name them in the program with **upper-case** bytes (`$41-$5A`; 64tass `.text "NAME"` with the default or `none` encoding).
- Put all D81s of a multi-disk game in the same SD-card directory. Mount another D81 from the program:
  1. Copy the name to a page-aligned buffer below `$7E00` (`$1E00` works).
  2. Call `HYPPO_SETNAME` (`$2E` â†’ `$D640`, then `CLV`).
  3. Call `$40` (d81attach0). Carry is set on success.

  Fall back to "insert disk N (freezer), press RETURN".
- Hypervisor trap `$70` toggles the ROM write protection on `$20000-$3FFFF`; test before and after.

### Reading and writing files

- SEQ names: `name,s,r` read, `@0:name,s,w` write (replace), `name,s,a` append. `,P,W` writes a PRG. KERNAL SAVE replaces a file with the `@:` prefix.
- Status comes from channel 15: 62 = file not found, 26 = write protect on.
- **Closing the command channel closes every file on the unit.** Check DS only while no data file is open.
- `S0:name` scratches (reply `01, FILES SCRATCHED,nn`; nn = 0 means no such file). `R0:new=old` renames. Load `$` for the directory and pick out the quoted names.
- An open file can't be scratched (the drive says no such file). A file being written is only complete once closed.
- Safe save: scratch the target, write a temporary file, rename it after the write succeeds.
- Refuse `* ? , : =` and quotes in names: the DOS reads them as patterns or commands.
- Block I/O: move up to 255 bytes with the whole CHKIN/CHRIN loop inside one KERNAL session, and close as soon as EOF arrives with an empty buffer. A recipe that worked: lfn 4, device 8, secondary 4, CHRIN into a page buffer, no zero-page pointer live across KERNAL calls, then copy each 256-byte chunk far.

---

## 11. Overlays

- Load every overlay PRG once at boot (staged in bank 5, header skipped), DMA it into an attic slot, and keep a "ready" flag per overlay so the caller can degrade gracefully if one was missing.
- To call one, DMA its slot into a fixed window and `JMP` (not `JSR`) to the window base; the overlay's `RTS` returns to the caller's caller.
- Two window classes work well:
  - **modal**: loaded per call, forgotten after RTS;
  - **mode**: stays loaded for a whole session, with a fixed `jmp` entry table at its base. Resident code calls only those offsets.
- Keep all changing state resident. The window is overwritten on every swap, so a swap is one inbound DMA. If a swapped tail must keep state, write it back only while one of its routines is mid-call.
- Each overlay is its own PRG: `.cpu "45gs02"`, `.include` the resident label file, `* = window`. Rebuild every overlay after the resident code changes. End each with a `.cerror` size guard.
- IRQ-resident code (sound engines) can't be swapped out while hooked.
- Re-DMAing a 4 KB overlay per keystroke is cheap. One-time init code can live in an overlay.
- [?] An attic mirror path (`$801xxxx`) written back with enhanced DMA corrupted memory once; a CPU copy loop worked.

---

## 12. Clocks

- RTC at `$FFD7110`: all BCD, except **[Xemu]** Xemu returns the month in binary. Hour byte: bit 7 = 24-hour mode, otherwise bit 5 = PM. It keeps local time with no time zone.
- CIA 1 time-of-day works as a monotonic 0.1 s timer: read hours first (latches) and tenths last (unlatches). It's a 12-hour clock with a PM bit. C65 `RDTIM` returns the TOD in BCD h/m/s, not a C64 jiffy count.
- `$D7FA` counts frames.

---

## 13. Ethernet

| Register | Use |
|---|---|
| `$D6E0` | CTRL1. Reset: write `$00`, wait 100 ms, write `$03`, wait 100 ms. Bit 7 = TX ready. |
| `$D6E1` | CTRL2. Pulse the TX state machine reset with `$03`, `$00`. Bit 5 = a frame is waiting. RX rotate (next frame): `$01` then `$03`. |
| `$D6E2/$D6E3` | TX length LSB/MSB |
| `$D6E4` | Command: `$01` = transmit |
| `$D6E5` | CTRL3: bit 0 NOPROM (1 = not promiscuous), bit 4 broadcast (keep on for ARP), bit 5 multicast, bits 2-3 TX phase, bits 6-7 RX phase delay [?] |
| `$D6E9` | MAC address |
| `$FFDE800` | TX/RX buffer |

- Transmit: wait for `$D6E0` bit 7, write the length, make sure `$D6E0` = `$03`, write `$01` to `$D6E4`.
- **Rotate first, then read.** When RXQ (`$D6E1` bit 5) is set, write `$01` then `$03` to `$D6E1`, and only then read the
  frame. The CPU sees the last buffer until the rotate. Reading first shows no error: each frame is simply handled when the
  next one arrives, which looks like a very slow network.
- Receive buffer: +0 = length LSB; +1 bits 0-3 = length MSB, bit 4 multicast, bit 5 broadcast, bit 6 unicast to us, bit 7 CRC error. The frame starts at `$FFDE802`.

---


**Using mega-ip after a takeover** (weather65 `src/net.asm`). The library normally runs from BASIC through KERNAL
JSRFAR, but it needs nothing from the KERNAL, only bank 4 at `$2000-$7FFF`. A trampoline below `$2000` does
`A=$00, X=$E4, Y=0, Z=0, MAP, EOM`, calls it, and undoes that; interrupts stay off while the program is mapped
away. Registers pass straight through, so the "staged" dispatcher isn't needed. The ring and out-of-order buffers
take `$50000-$515FF`, which collides with `video_fcm`'s default framebuffers; `$20000`/`$30000` are free once
`rom_unprotect` has run. Works on real hardware: DHCP, ARP, DNS, TCP and HTTP.

**Pace mega-ip's polling at several polls a frame.** `ARP_RETRY_TICK` and `ARP_CACHE_PURGE` count polls, so a
flat-out loop at 40 MHz gives up on ARP within milliseconds, before the router answers (DHCP still works, as it needs
no ARP). The DNS, TCP and connect timers instead watch for the raster wrapping, so one poll a frame at a fixed line may
never tick them. `net_pace` waits for `$D012 & $C0` to change: about 5 polls a frame.

**Some servers open with a zero window.** `api.open-meteo.com` sends `Win=0` in its SYN-ACK and opens it after our ACK. mega-ip
doesn't read the peer's window, so wait about 200 ms before sending to such a host.

**HTTP from a small client.** Send `HTTP/1.0` with `Host:` and `Connection: close`: servers then answer without
chunked encoding and close at the end. `ETH_TCP_SEND_BYTE` queues up to 255 bytes: when it returns 0, poll and try
again. The stack advertises at most 1 KB and sends no MSS option. It has no TLS, so plain HTTP only.

**KERNAL after using the ROM area as RAM:** copy `$20000-$3FFFF` to attic at boot, DMA it back before `kfile_save`
(display off), then redraw. Tested in Xemu.

## 14. Xemu, real hardware and testing

### Where Xemu and hardware differ

- **Disk I/O:** KERNAL I/O from a custom MAP works in Xemu and hangs HYPPO on hardware. Test disk I/O on hardware.
- **Timing:** IRQ races on cold autoload and some CIA edge cases differ.
- **Sprite X:** about 16 px; see `$D60F` bit 5.
- **CHARPTR at boot**, and the font in WOM on hardware.
- **STZ on VIC-IV registers.**
- **RAM at power-on:** random on hardware, zero in Xemu.
- **Mid-frame TEXTXPOS changes:** Xemu ignores them.
- **Writes to unmapped addresses:** Xemu logs "Unhandled memory write" with the address and PC; hardware silently loses them.

When something works in Xemu and not on hardware, suspect the environment (MAP, `$01`, `$D030`, IRQ state, hardcoded boot values) before the logic. Save and restore boot state rather than hardcoding it.

### Xemu tools

- Headless run: `-headless -sleepless -besure -uartmon :4510 -screenshot shot.png`. Look at the screenshot: screen RAM can be right while the display is garbage.
- Other options:
  - `-8 disk.d81 -autoload`;
  - `-hdosvirt -hdosdir <dir>` (HYPPO calls find files in `<dir>`);
  - `-prg file` (racy with `-prgexit` while a D81 is mounted);
  - `-importbas file.txt` (types and RUNs a BASIC program);
  - `-dumpscreen f`, `-dumpmem f` (all 384 KB of chip RAM; bank 1 at file offset `$10000`);
  - `-initattic f`;
  - `XEMU_LOG=file`.

  `-silent` isn't an option. Close Xemu gracefully (with `-besure`) rather than killing it, so the exit dumps get written.
- Xemu sometimes stalls at the boot banner: retry up to three times.
- uartmon:
  - `m <28-bit addr>` reads (`m ffd3060` for VIC-IV, `m 8000000` for attic); `r` shows PC and MAP live.
  - The C65 KERNAL image is at `$3E000`.
  - `b` breakpoints didn't stop the CPU, but `t1`/`t` single-stepping from a hold point did.
- Each poke or peek over the monitor takes about 0.3 s, which is many frames. Give the program a frame-timed input script (pairs of joystick bits and frame counts played into a `dbg_joy` byte) instead of timing pokes. In sleepless mode, idle timers run out within seconds; use real-time mode to catch timed animations.
- Expose `dbg_*` bytes and state bytes to poke and peek. Count the frames actually drawn as well as the frame counter. A per-tick trace buffer (x/y/state per logic tick) helps compare against expected motion. A program can also copy its text output to attic for the harness to read.
- Measure the frame rate in real-time mode by reading a frame counter twice, a few seconds apart.

### Hardware debugging

- Write a different colour to `$D020` at each suspect stage: the colour it freezes on names the stage that hung.
- On a hang, capture PC, A/X/Y/Z, MAPHI/MAPLO and a dump of the buffer that should have been written (monitor `m`, `d`, `r`).
- Keep a known-good tag to diff against when something breaks on hardware.

---

## 15. Build environment (Windows)

- Running `cmd.exe /c build.bat` from git-bash does nothing silently: MSYS rewrites `/c`, and the exit code 0 misleads. `cmd //c` can hang. Run batch files from PowerShell; if the batch calls tools by bare name, put the repo root on PATH first: `$env:PATH = "$PWD;$env:PATH"; .\build.bat`.
- VICE `petcat` doesn't know the newer BASIC65 tokens (WPOKE, WPEEK, DECBIN, STRBIN$, CHDIR, HASBIT, RPT$). Patch them into the tokenised output, padding to keep lengths. It accepts lower-case keywords only and doesn't sort line numbers.

---

## 16. BASIC65 ROM notes (for tools that compile or test BASIC)

- `/` always gives a float. Floats are 5-byte CBM MFLP:
  - byte 0: exponent, excess 128 (`$00` = zero);
  - byte 1: mantissa MSB, with the sign in bit 7 (the leading 1 is implied);
  - bytes 2-4: the rest of the mantissa, big-endian.

  About 9 digits. `USR` passes its value in the FAC.
- Variable names are significant to 2 characters. `DT$` and `TI$` give the date and time.
- V920413 rejects FOREGROUND/COLOR values of 16 and above (the book says 0-31). `COLLISION` isn't implemented. MOVSPR motion carries over between RUNs. No space is allowed before the `(` of extended functions. The MOUSE position-pair form is rejected. Out-of-range graphics coordinates, WINDOW coordinates or GCOPY sizes give ILLEGAL QUANTITY.
