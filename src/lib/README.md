MEGA65 library modules
======================

Include only what a project needs, after `platform.asm`, `lib/zp.asm` and the project's `zp.asm`.
Each file documents its routines at the top. Everything was tested in Xemu:
`private/examples/libdemo.asm`, `libdemo2.asm` and `libdemo3.asm` (kept out of git) between them use every module. The code comes
from mega-dust, mega-kong, deluxepaint65, mega-simcity, mega-elite, mega-python and
little-mega-people.

| Module | Needs | Gives |
|--------|-------|-------|
| `system.asm` | – | `#TAKEOVER` (macro), `irq_install` + `irq_hook` (per-frame routine), `wait_frame`, `rom_unprotect` |
| `dma.asm` | – | `#DMA_RUN list`, `dma_job` / `dma_go`, `dma_fill`, `dma_copy_far` (28-bit, splits at 1 MB boundaries), `dma_blit` list |
| `loader.asm` | dma | Boot-time KERNAL loading: `load_file` (to chip RAM), `load_to_attic` (through a staging buffer), `mount_d81` (HYPPO, D81 from the SD card), `print` |
| `unpack.asm` | loader, dma | Boot-time `load_packed_to_attic`: files packed by `tools/pack.py` (zero runs; graphics often halve), unpacked through chip RAM into attic. `unpack` on its own |
| `manifest.asm` | loader, unpack, dma | Boot-time `load_manifest`: loads every file in `src/gen/manifest.asm` (written by `tools/m65assets.py` `write_manifest`) to its attic address; `manifest_hook` per file (progress dots). Include `gen/manifest.asm` too |
| `kfile.asm` | – | `kfile_save` / `kfile_load` **after** the takeover (high scores, save games), through a KERNAL trampoline below `$2000`. `kfile_capture` must run at boot. |
| `input.asm` | – | `read_input`: both joysticks, cursor keys, WASD, SPACE/RETURN fire, RUN/STOP; `joy`/`joy_new`, `dbg_joy`. Each source alone too, for two players: `joy_port1`, `joy_port2`, `joy_keys` |
| `keyboard.asm` | – | `key_get` / `key_wait` / `key_flush`: typed keys from the `$D610` hardware queue (for text entry); `dbg_keys` injection |
| `mouse.asm` | – | `mouse_init` / `mouse_poll`: 1351 mouse in either port, clamped position, debounced click and release edges |
| `video_fcm.asm` | dma | 320x200 Full Colour framebuffers (double-buffered, optional static HUD rows), palette, `fcm_present` / `fcm_irq` (hooked automatically), `fcm_clear`, full-screen picture screen |
| `blit.asm` | dma, video_fcm | `blit_sprite`: column-major FCM sprites, transparent, clipped, bounding boxes |
| `vblit.asm` | dma, video_fcm | `vblit_sprite`: sprites of any size up to 255x255 (tables from a build tool, trimmed to the opaque box), from any chip-RAM or attic address; anchor-relative, clipped, `vb_clip` right edge for side panels |
| `fcm_text.asm` | video_fcm | `ftext_draw` / `ftext_centre` / `ftext_char` / `ftext_dec`: 8x8 text at any pixel position in the back buffer, any palette colour, optional drop shadow, multi-line (13). Font: `FTEXT_FONT`, 64 screen-code glyphs |
| `fcm_cache.asm` | dma, video_fcm | `cache_restore` / `cache_save`: keep a scene's static background in attic and restore it with one DMA copy a frame, instead of redrawing it |
| `sprite_touch.asm` | blit | `sprite_touch`: pixel-exact collision of two sprites at an offset (like hardware sprite collisions), reading only their bounding boxes' overlap |
| `draw.asm` | dma, video_fcm | `draw_plot`, `draw_vline` (one DMA), `draw_hline`, `draw_rect`, `draw_fill`, `draw_line`, `draw_circle`, `draw_disc` |
| `c64gfx.asm` | dma, blit, video_fcm | `c64_sprite`, `c64_charset`, `c64_koala`: C64 graphics to Full Colour |
| `hwsprite.asm` | – | The VIC-IV's 8 hardware sprites: `hws_init` (16-bit pointers, Xemu/hardware detection), `hws_shape`, `hws_place` (screen coordinates, all high bits, hardware X correction), `hws_on`/`off`, `hws_colour`, `is_real_hw`. VIC-IV extras: `hws_full_colour` (16 colours, 16 px wide), `hws_height` (tall sprites), `hws_pal_bank` / `hws_pal_edit` (a palette bank of their own; `hws_screen_bank`) |
| `text.asm` | dma | 40 or 80 column text console without the KERNAL: `text_init`, `text_clear`, `text_goto`, `putc`, `puts`, `#PRINT`, `put_hex`, `put_dec`; scrolls by DMA |
| `palette.asm` | video_fcm | `pal_set`, `pal_set_level` (brightness 0-255), `pal_fade_out` / `pal_fade_in` |
| `audio.asm` | – | `audio_init` (mixer routing), `audio_play` / `audio_stop` (samples on any channel), `stream_start` / `stream_frame` (long 8-bit or packed 4-bit audio from attic) |
| `sid.asm` | – | `sid_init`, `sfx_play`, `sfx_frame`: table-driven SID effects; `SID_MIRROR` = a second SID's address sends every write there too, for both speakers |
| `rtc.asm` | – | `rtc_read`: time and date in binary, 24-hour, validated (handles Xemu's binary month) |
| `math.asm` | – | `mul16`, `div16` (hardware), `rand`, `rand_seed_hw` (hardware RNG, bounded wait) |

## Default memory layout

Override any default by defining the symbol before the `.include` (the defaults are `.weak`).

| Area | Default | Notes |
|------|---------|-------|
| Program | `$2001`-`$C7FF` | BASIC stub + `SYS 8210`. Must end below `$C800` when `video_fcm`'s picture screen is used. |
| Screen RAMs A / B | `$0800` / `$1000` | `video_fcm`: 2000 bytes each (16-bit chars) |
| Screen RAM C (pictures) | `$C800` | `video_fcm` |
| Text screen | `$0800` | `text.asm`: a different mode from `video_fcm`, so it can share the space |
| kfile trampoline | `$1800`-`$18C8` | Must be below `$2000`. Not `$0600`-`$07FF`, where the C65's sprite shapes live. |
| HYPPO name buffer | `$1E00` | Only while mounting at boot |
| Hardware sprite pointers | inside the program | `hws_ptrs`, 16-byte aligned. Shapes must be 64-byte aligned. |
| Audio ring | `$14000`-`$15FFF` | Must be chip RAM for audio DMA |
| FCM sprites | `$20000`-`$3FFFF` | Call `rom_unprotect` first. The text font is read from `$29800`, so don't overwrite it while text mode is in use. |
| Framebuffer A / picture | `$40000` | 64,000 bytes at 25 rows |
| Framebuffer B | `$50000` | |
| Loader staging | `$50000` | Boot only |
| Static HUD rows | `$4C800` | Only when `FB_ROWS` < 25 |
| Unpack buffer | `$40000` | `unpack.asm`, boot only |
| Background cache | `$8100000` | `fcm_cache.asm`, 64,000 bytes. Not in bank 1: `$1F800`-`$1FFFF` is colour RAM |
| Attic | `$8000000`-`$87FFFFF` | 8 MB |

Base page: `lib/zp.asm` uses `$02` to about `$44`; the project continues from `LIB_ZP_END`.
Everything stays below `$90` while the KERNAL is in use, either at boot or during `kfile` calls.

## Known working code elsewhere (not ported, use as reference)

| Need | Where |
|------|-------|
| RRB / GOTOX software sprites | `mega65-rrb-sample/src/modules/rrb_sprite.asm` (64tass, character rows only); `Mega65Tutorials/tutorial_8-10_*.asm` ("pixies", KickAss: pixel Y via colour-RAM Y shift, parallax, flipping) |
| NCM (16-colour chars), screen modes, NCM 4-way pixel scrolling | `m65-fcm/src/ncm.asm`, `fcm.asm` (`set_screen_mode`), `ncm_scroll.asm` |
| Flood fill, polygon, ellipse, arcs, gradients (row-major FCM; port the plot/address maths) | `m65-fcm/src/floodfill.asm`, `polygon.asm`, `ellipse.asm`, `gradient.asm`; `basic65-compiler/src/gfx/lib/arc.asm`; `deluxepaint65/src/graphics/` |
| Directory listing, file-exists, scratch, streamed save (KERNAL, boot state) | `deluxepaint65/src/paint/files.asm`; `mega-simcity/src/overlays/ovr-disk.asm` |
| SD-card FAT32 files: HYPPO `loadfile_attic` / findfile / rmfile; raw FAT32 writer | `megapc/src/disk.asm` (1054, 1371), `megapc/src/fat_writer.asm` |
| D81 file loading through the floppy controller (no KERNAL, read-only) | `M65_Examples/_include/floppyio.s` (KickAss) |
| LZ decompressor that copies with DMA, plus its cruncher | `Mega65Tutorials/build/MegaTool/DecrZero.s` (ca65) |
| Line editor with history | `mega-python/src/keyboard.asm` (`rl_read`) |
| Music: BASIC65 PLAY player (6 voices, SID1 + SID3), Elite title-music interpreter, small tune player | `basic65-compiler/src/runtime/runtime.asm` ~8109; `mega-elite/src/overlays/title_music.asm`; `little-mega-people/src/engine/sound.asm` |
| TCP/IP (ARP, DHCP, DNS, TCP) | `mega-ip/src` (64tass, built as a BASIC SYS library) |
| SAM speech into an audio-DMA ring | `megasam/src` |
| IFF ILBM load/save (ByteRun1) | `deluxepaint65/src/overlays/ovr-iff.asm` |
| Signed hardware maths, star field, 3D wireframe | `mega-elite/src/elite_math.asm`, `stars.asm`, `render.asm` |
| Returning cleanly to BASIC | `little-mega-people/src/engine/render.asm` (`screen_restore_basic`). Save the 4 CHARPTR bytes at boot: the font lives in WOM (`$FF7E000`) on real hardware. |
