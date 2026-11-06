# MEGA65 project: standing instructions

This repo was started from the MEGA65 project template. Read this file first; it answers what the
user would otherwise have to repeat.

**MEGA65 technical detail is in [`docs/MEGA65_NOTES.md`](../docs/MEGA65_NOTES.md)**: memory map,
boot and KERNAL, MAP, DMA, video, audio, files, Xemu vs hardware. The gotcha list below is the
short version. Read the notes for the topic before working on it, and add new discoveries
there, not here.

**See `private/CLAUDE.md` for more details.** `private/` is gitignored; its notes are imported
here:

@../private/CLAUDE.md

If `private/` is missing (a fresh clone), carry on without it. Put anything personal or
machine-specific in `private/`, not in checked-in files.

**Where scripts and data go:**
- `tools/`: only the Python scripts the build needs to make the app or game, for example
  `pack.py` and an asset build script that `build.bat` runs.
- `private/tools/`: every other script, such as test harnesses, emulator helpers and data
  extraction.
- `private/temp/`: temporary or intermediate data.

## How the user wants MEGA65 projects done

- **Use this build template.** `build.bat` assembles with the bundled `64tass.exe` and writes a D81 with
  the bundled `c1541.exe`. `run.bat` builds and launches Xemu. Keep this structure.
- **Use the library in `src/lib/`** (see `src/lib/README.md`). Include only the modules the game
  needs, rather than rewriting:
  - takeover and frame IRQ;
  - DMA;
  - boot loader (chip RAM, attic, HYPPO D81 mount);
  - file save/load after the takeover (`kfile`: high scores, save games);
  - joystick, typed keys (`keyboard`), 1351 mouse;
  - Full Colour framebuffers, palette fades;
  - FCM text at any pixel position (`fcm_text`), a background cache in attic (`fcm_cache`),
    packed asset loading into attic (`unpack` with `tools/pack.py`);
  - sprite blitter, pixel-exact sprite collisions (`sprite_touch`), shape drawing (`draw`:
    lines, rectangles, circles);
  - VIC-IV hardware sprites;
  - C64 graphics converters;
  - 40/80-column text console;
  - audio DMA, streaming and SID effects;
  - real-time clock;
  - maths and random numbers.

  The library README also lists working code that wasn't ported (RRB sprites, NCM, flood fill,
  FAT32, LZ decompression, music players, TCP/IP). Add new reusable code to the library, in the
  template as well.
- **Loading assets:** do all KERNAL disk I/O once at boot, in the untouched BASIC65 state, then
  take over and never call the KERNAL again.
  - Load into chip RAM directly (`load_file`) when it fits.
  - For big data (music, many levels), load into attic RAM (`load_to_attic`) and DMA it in as
    needed.
- **Don't build loading/option screens** (crack intros, publisher animations, drive-selection menus)
  unless asked. Skip straight to the game's own title or menu.
- **Keep `README.md` up to date** with what the project is, how to build and run it, controls,
  architecture and known differences. Keep a `TODO.md` for remaining work.
- **Assets** are editable sources in `src/assets/` (PNG sprite sheets, asm tables, font and sound
  data), all checked in. `tools/build_assets.py` (a starting point; adapt it) turns them into
  `target/assets/*` plus `src/gen/*.asm` on every build. It uses `tools/m65assets.py`:
  - PNG cell sheets;
  - palette quantising;
  - `lib/blit.asm` sprites with boxes, and 16-colour hardware sprites;
  - packed parts for `lib/unpack.asm`;
  - the palette and the attic manifest that `lib/manifest.asm` loads at boot.

  Uncomment its lines in `build.bat`. Document the formats in `src/assets/README.md`.
- **Test in Xemu yourself** (headless harness below) and look at the screenshots before reporting.
  Say plainly what was and wasn't tested.

## Tools

| What | Where |
|---|---|
| Assembler / disk tool | `64tass.exe` (v1.60) and `c1541.exe` in the repo root |
| 64tass manual | https://tass64.sourceforge.net/ (directives, `.weak`, `.virtual`, functions, list expressions, `--cbm-prg`, `-C` case-sensitive, `-I` include path) |
| Python | `python` (Pillow and pypdf) |

The MEGA65 book (the "Compendium"): see the page table at the top of `docs/MEGA65_NOTES.md`.

## Testing in Xemu

- **Interactive:** `xmega65.exe -8 target\game.d81 -autoload`. Add `-hdosvirt -hdosdir <dir>`
  so the program's HYPPO `d81attach` / `loadfile` calls find files in `<dir>`.
- **Headless test:** `python private\tools\xemu_run.py shot.png [actions]` boots the D81 with
  `-headless -sleepless -besure -uartmon :4510 -screenshot shot.png`, then runs these actions:

  | Action | Meaning |
  |---|---|
  | `wait:SECS` | Sleep |
  | `poke:ADDR=B,B` | Write bytes |
  | `peek:ADDR:N` | Print N bytes |
  | `regs` | Print CPU registers |
  | `realtime` | Run at 50 fps (first action only) |
  | `xemu:ARG` | Extra Xemu argument |

  ADDR can be a label from `target/*.lbl`, for example `poke:dbg_joy=10` to inject joystick fire.
  Xemu writes the screenshot on exit. Read it with the Read tool and check it.
- Give the program `dbg_*` bytes for the harness to poke: `dbg_joy` (OR'd into the joystick),
  `dbg_god`, `dbg_level` and so on.
- **Each poke or peek takes about 0.3 s**, and peeks before the exit delay the screenshot too, which is many frames, more still in sleepless mode. So
  "press for 2 frames" can't be done with pokes; a held direction auto-repeats. Give the
  program a frame-timed input script instead: pairs of (joystick bits, frames) that it plays
  into `dbg_joy`. In sleepless mode, idle timers such as a title's demo countdown run out
  within a couple of seconds, so poke early or suspend the timer while a script runs.
- Count the frames actually drawn as well as `frame_count`: a long computation with no frames
  (an AI search) shows up as a gap.
- SID registers are write-only: peeks read `$FF`. Check music and effects through the
  player's own state (note pointers, counters), then listen.
- The uartmon `m` command reads 28-bit addresses: `m ffd3060` for VIC-IV registers, `m 8200000`
  for attic.
- **Measure the frame rate:** run with `realtime` and peek a per-frame counter twice, a few seconds
  apart.

## MEGA65 gotchas (each of these cost real time)

**CPU and assembler**

- `.cpu "45gs02"` at the top of every file.
- **`STZ` stores the Z register, not zero.** Use `LDA #0 / STA`. Xemu tolerated `stz $D063`; real
  hardware broke.
- **Real hardware RAM is random at power-on** (Xemu zeroes it). Clear the base page and every
  variable at boot.
- `inw`/`dew`/`asw` work on the base page only, not absolute addresses.
- 64tass `_local` labels are scoped between global labels. Referencing one across a global label
  gives "not defined symbol". Anonymous `+`/`-` labels resolve to the *next* one, which is easy to
  get wrong in branchy code; prefer named labels. `--` can't be a label definition.
- **`ldx #n-1 / ... / dex / bpl -` copies at most 128 bytes.** For longer blocks, count up with
  `inx / cpx #n / bne -`. This silently truncated the kfile trampoline.
- Macro parameters need defaults to be optional: `PRINT .macro a, b="", c=""`.
- The library's private labels start with `l_`; don't use that prefix in projects.
- There is no `cpx abs,x`, `cpy abs,x` or `ldx abs,x`. Copy the value to a base-page temp
  and compare against that.
- Library calls may change all of `tmp0`-`tmp7`. For example, `draw_fill` uses `tmp7`. Never
  keep a loop counter in a `tmp` across a library call or across `frame`/drawing.
- `.null "a", "b"` makes ONE string `"ab"`. Give each string its own label.
- A generated file with data (not just `=` constants) included before `* = $2001` makes the
  PRG load at `$0000`, and BASIC says `?SYNTAX ERROR`. Include generated data at the end.
- 64tass supports `range()`, `.for x in list` and `sin()`. List comprehensions (`[f(x) for x in ...]`)
  aren't supported.

**Boot and KERNAL**

- KERNAL `LOAD` only works in the pristine BASIC65 state. Do it before `sei`, before the 40 MHz
  switch and before any MAP.
- Call `SETBNK` (A = data bank, X = 0) before every `SETLFS`/`SETNAM`/`LOAD`.
- Secondary address 0 loads to X/Y and skips the 2-byte header.
- During boot, use base page `$02`-`$8F` only; the KERNAL owns `$90`-`$FF`.
- `$1600`-`$1EFF` is always free. `$0600`-`$07FF` is **not**: the C65 keeps sprite shapes there,
  and it overwrote the kfile trampoline.
- Never load into `$10000`-`$11FFF`; disk I/O overwrites it (DOS buffers). The SD sector buffer
  is at `$FFD6E00`.
- **Calling the KERNAL after the takeover** (`lib/kfile.asm`): it needs a trampoline below `$2000`
  that restores the boot MAP (`$E3`/`$B3`), `$01` and `$D030`, masks the VIC IRQ, and puts the
  game's state back afterwards. The data must be in bank 1+ or below `$2000`.
- **Returning to BASIC:** on real hardware the font is in WOM (`$FF7E000`). Save the CHARPTR
  bytes at boot and put them back.
- c1541 writes lowercase ASCII names as PETSCII *unshifted*. Put names in upper case in the
  asm `.text` (for example `"MDCOMMON"`). Write the game twice, as the first file and as `autoboot.c65`.

**Taking over the machine**

```
sei
lda #65 / sta $00                 ; 40 MHz
VIC-IV unlock: $47, $53 -> $D02F
lda #0 / tax / tay / taz / map / eom
lda #$35 / sta $01
lda #4 / sta $D030                ; RAM palette
txs
tab                               ; base page = $00
$DC02 = $FF, $DC03 = 0            ; re-pin the CIA data directions
```

Then install your own `$FFFE` IRQ.

**DMA (F018B, enhanced)**

- The list is `$0B` (F018B), `$80`/`$81` src/dst MB, options, `$00`, then cmd, count, src (3 bytes),
  dst (3 bytes), sub-command, modulo. Trigger by writing the list MSB to `$D701`, then the LSB to `$D705`.
- **The DMAgic wraps addresses inside a 1 MB megabyte.** A copy that crosses a MB boundary on either
  side silently wraps. Split copies at boundaries; `lib/dma.asm`'s `dma_copy_far` does this. This bug
  corrupted music data.
- Useful options:

  | Option | Effect |
  |---|---|
  | `$83 n` | Source step (whole bytes) |
  | `$85 n` | Destination step |
  | `$07` + `$86 v` | Transparency on, with transparent value v |

  A destination step of 8 writes one FCM pixel column; a destination step of 21 transposes rows
  into column-major sprites.
- `dma_copy_far` moves `ptr1`/`ptr2` on only when it splits a copy at a megabyte. For two
  copies in a row from one source, set the second source address yourself.
- **`$1F800`-`$1FFFF` is the first 2 KB of colour RAM.** A buffer in bank 1 that reaches it
  corrupts the colour attributes of the top character rows: in FCM, a garbled band at the top
  of the screen. Keep big buffers in attic (`lib/fcm_cache.asm` uses `$8100000`).

**Video (VIC-IV)**

- **Full Colour Mode framebuffer:** CHR16 + FCLRHI (`$D054` bits 0 and 2). Give each cell its own
  char (char number = address / 64) and lay the chars out column by column:
  offset = `(x>>3) * rows * 64 + y*8 + (x&7)`.
- Double-buffer by flipping `$D060`-`$D063` in an IRQ below the playfield.
- **Xemu ignores mid-frame `TEXTXPOS`/side-border changes**, so raster splits for scrolling don't
  work there. Bake fine scroll into the framebuffer instead.
- Turn hot registers off (`$D05D` bit 7) so `$D016`-style writes don't undo your layout.
- Palette bytes are nibble-swapped: `$D100`/`$D200`/`$D300` take `(v & 15) << 4 | v >> 4`.
- `TEXTXPOS` and the side border are in H640 units (2 per H320 pixel).
- `$D012` holds raster bits 0-7; bit 8 is `$D011` bit 7.
- **Never copy `$D011` bit 7 back.** Reading it gives the beam's line bit 8; writing it sets the
  raster IRQ compare's bit 8. A read-modify-write of `$D011` (even `TSB`/`TRB`) done while the
  beam is below line 256 moves the IRQ to a line that doesn't exist, and it never fires again.
  It depends on timing: it can show up only when bigger assets change the boot time.
  Mask bit 7 and OR in `(>IRQ_LINE) << 7`, as `lib/video_fcm.asm` does.
- Hardware sprite X differs between Xemu and real hardware by about 16 px. `lib/hwsprite.asm`
  handles it with the `$D60F` bit 5 check (set on real hardware).
- The default `video_fcm` layout uses screen RAM at `$0800`, `$1000` and `$C800`, so the program
  must end below `$C800`.
- `$D06B` is the 16-colour-sprite enable, not a charset register (some code mislabels it).
- **16-colour sprites** (`lib/hwsprite.asm` `hws_full_colour`): 16 px wide, 8 bytes a row,
  high nibble = left pixel. The transparent nibble is `$D027+n`, so set it to 0. Sprite n's
  colour c is entry n*16+c of the sprite palette bank (`$D070` bits 2-3). After the takeover
  the screen used bank 3 (`$D070` = `$FF`), so bank 1 is free for the sprites. Tall sprites:
  `$D055` enables, `$D056` = the one shared height.

**Audio**

- Audio DMA reads **chip RAM only**: 24-bit addresses, nothing from attic. The end address compares
  only 16 bits, so a sample is at most 64 KB.
- To stream long audio, loop a chip-RAM ring buffer and refill it from attic every frame, using
  `CHxCURADDR` (`$D72A`/`$D72B`) as the read position.
- `$D720` control: `$E2` = enable + loop + unsigned + 8 bit (bit 5 set = unsigned; `$C2` is signed).
- Clearing the enable bit doesn't stop a looping channel on real hardware. Set the end address
  and drop the loop bit instead (see the notes).
- FREQ = rate × 2^24 / 40.5 MHz. For example, 10947 Hz is 4535.
- **Route the mixer, or you hear nothing.**
  - Write `$80` to `$D711` (AUDEN), then set the digital-audio coefficients through
    `$D6F4` (select) / `$D6F5` (data), waiting at least 32 cycles between selects.
  - Register = `output*32 + source*2`. Digital audio L/R are sources 8 and 9. Outputs: 0/1
    speakers, 6/7 headphones.
  - Values that work: `$10,$11,$12,$13,$30,$31,$32,$33,$D0,$D1,$F2,$F3` <- `$FF,$BF,$FF,$3F,$FF,$3F,$FF,$BF,$FF,$BF,$FF,$BF`.
- The CPU must run at 40 MHz and execute memory-reading instructions in its wait loops, because
  audio DMA steals idle cycles.

**Attic RAM and HYPPO**

- Attic RAM is `$8000000`-`$87FFFFF` (8 MB). KERNAL loads land in a chip-RAM staging buffer
  (for example bank 5); DMA them up from there.
- Mount another D81 from the SD card: copy the name into a page-aligned buffer below `$7E00`
  (`$1E00` works), then call `HYPPO_SETNAME` (`$2E` -> `$D640`, `CLV`), then `$40` (d81attach0).
  Carry is set on success. Fall back to "insert disk N, press RETURN".
- To make the ROM area `$20000`-`$3FFFF` writable, call hypervisor trap `$70` (it toggles; test
  before and after).

**Hardware multiplier and divider**

- The multiplier is `$D770` (A) × `$D774` (B) = `$D778` (result, immediate).
- The divider gives `$D768`-`$D76F` as 32.32 fixed point; the integer part is at `$D76C` (+4).
  Wait while `$D70F` bit 7 is set.
- The hardware random generator is `$D7EF`. `$D7FE` bit 7 set means it is **not** ready yet, so
  bound the wait.

**Input and other I/O**

- The CIA reverses the ports: `$DC00` = port 2, `$DC01` = port 1. The mouse's pots are
  `$D620`/`$D621` (port 1) and `$D622`/`$D623` (port 2).
- `$D610` is the hardware key queue (ASCII). Write anything to dequeue. Skip `$FF`.
- RTC (`$FFD7110`): everything is BCD, except that Xemu returns the month in binary. In the hour
  byte, bit 7 means 24-hour mode; otherwise bit 5 means PM. `lib/rtc.asm` deals with all of this.

## Making a game

1. **Pin down the design first.**
2. **Pick the screen technique:**
   - `video_fcm` + `blit`: unlimited software sprites, any count.
   - `hwsprite`: few objects, like mouse pointers.
   - `text`: text-mode games and tools.
   - RRB (character-based sprites, parallax) or NCM: see the reference code listed in
     `src/lib/README.md`.
3. Start from `src/main.asm` and include the modules. The game logic (objects, rules, waves,
   levels) is game-specific.
4. Generate data with a Python tool from `src/assets/`. Keep generated asm in `src/gen/`.

## Workflow that worked

1. Write a build tool that turns `src/assets/` into `target/assets/*` plus `src/gen/*.asm`
   (manifest, palette, ids) on every build.
2. Write the boot loader (loads to attic), the takeover, video, blitter, game loop and sound.
3. Build with `build.bat`. Test with `private/tools/xemu_run.py` screenshots and peeks; measure the frame rate.
4. Save non-obvious discoveries to memory and the README. Leave a `TODO.md`.
