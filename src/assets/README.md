# Assets

| File | Format | Becomes |
|---|---|---|
| `usmap.png` | 1 bit, 2240 x 1200. Longitude -130 to -60 at 32 px per degree, latitude 52 down to 22 at 40 px per degree. White = line | `USMAP*`: 280 bytes a row, MSB left, in attic at `$8000000` |
| `icons.png` | RGBA. Row 1: 10 icons of 64 x 48. Row 2: the same 10 at 32 x 24, one every 64 px. Alpha under 128 is transparent | `ICONS*`: `lib/vblit` sprites in attic at `$8060000`, quantised to palette entries 64-127 |
| `bigfont.png` | RGBA, 14 cells of 44 x 52 in one row: `0-9`, `-`, degree, `F`, `C`. Painted for the blue behind the temperature. Alpha under 128 is transparent | Also `lib/vblit` sprites, after the icons, palette entries 160-199; each advances by its own width |

Icon order: sun, sun + cloud, cloud, fog, drizzle, rain, snow, thunder, moon, moon + cloud.

Edit these PNGs freely: `tools/build_assets.py` compiles them on each build. `private/tools/make_assets.py`
generated the first versions, and re-running it overwrites hand edits.

The palette is defined in `tools/build_assets.py`: 0-10 UI, 16-47 background, 48-59 title band, 64-127 icons,
128-142 radar scale, 144-146 map, 160-199 big characters.
