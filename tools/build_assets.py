"""Build-time asset compiler: src/assets -> src/gen + target/assets. build.bat runs it.

  src/mega-ip/eth.asm  -> target/assets/ethbin (the TCP/IP stack, loaded to $42000)
  src/assets/usmap.png -> USMAP* (1 bit per pixel, 280 bytes a row, 1200 rows, attic ATTIC_MAP)
  src/assets/icons.png -> ICONS* (lib/vblit.asm sprites in attic ATTIC_ICONS), vs_* tables
  palette              -> src/gen/palette.asm

--mock DIR adds captured HTTP responses (mock0 .. mockN) for the Xemu replay build.
"""
import os
import subprocess
import sys

from PIL import Image

import m65assets as m

ATTIC_MAP = 0x8000000
ATTIC_ICONS = 0x8060000

C_FIXED = [
    (0, 0, 0),          # 0  black
    (255, 255, 255),    # 1  white
    (255, 230, 80),     # 2  yellow
    (140, 215, 255),    # 3  light blue
    (255, 160, 50),     # 4  orange
    (6, 12, 48),        # 5  shadow navy
    (170, 180, 205),    # 6  grey
    (255, 80, 70),      # 7  red
    (110, 230, 120),    # 8  green
    (10, 22, 80),       # 9  ticker strip
    (60, 90, 170),      # 10 grid line
]
BG_BASE, BG_N = 16, 32          # the blue background gradient
HD_BASE, HD_N = 48, 12          # the title band
ICON_BASE, ICON_N = 64, 64
BIG_BASE, BIG_N = 160, 40       # the big temperature characters' shades
BIG_W, BIG_H, BIG_COUNT = 44, 52, 14
BIG_FIRST = 20                  # sprite id of the first big character, after the icons
RADAR_BASE = 128
# reflectivity colours, 5 dBZ to 75+ dBZ: the conventional radar ramp
RADAR = [(4, 233, 231), (1, 159, 244), (3, 0, 244), (2, 253, 2), (1, 197, 1), (0, 142, 0),
         (253, 248, 2), (229, 188, 0), (253, 149, 0), (253, 0, 0), (212, 0, 0), (188, 0, 0),
         (248, 0, 253), (152, 84, 198), (253, 253, 253), (160, 160, 160)]
MAP_BG, MAP_LINE, MAP_MARK = 144, 145, 146


def assemble_stack():
    """the stack is a flat image for $2000 in bank 4: give it a PRG header for load_file"""
    out = os.path.join(m.ROOT, 'target', 'eth.tmp')
    subprocess.check_call([os.path.join(m.ROOT, '64tass.exe'), '-q', '--nostart',
                           os.path.join(m.ROOT, 'src', 'mega-ip', 'eth.asm'), '-o', out])
    data = open(out, 'rb').read()
    os.remove(out)
    os.makedirs(m.ASSETS, exist_ok=True)
    open(os.path.join(m.ASSETS, 'ethbin'), 'wb').write(bytes([0x00, 0x20]) + data)
    assert len(data) < 0x6000, 'stack overflows bank 4 mapping'


def build_map():
    im = Image.open(os.path.join(m.SRC_ASSETS, 'usmap.png')).convert('1')
    assert im.size == (2240, 1200), im.size
    return m.write_parts('USMAP', im.tobytes())


def build_icons():
    im = Image.open(os.path.join(m.SRC_ASSETS, 'icons.png')).convert('RGBA')
    cells = [(n * 64, 0, 64, 48) for n in range(10)] + [(n * 64, 48, 32, 24) for n in range(10)]
    sprites = []
    for (ox, oy, w, h) in cells:
        rows = []
        for y in range(h):
            r = []
            for x in range(w):
                p = im.getpixel((ox + x, oy + y))
                r.append(tuple(p[:3]) if p[3] >= 128 else None)
            rows.append(r)
        sprites.append(rows)
    colours, lookup = m.quantize(sprites, ICON_N)
    data = bytearray()
    tab = []
    for (ox, oy, w, h), rows in zip(cells, sprites):
        xs = [x for x in range(w) for y in range(h) if rows[y][x] is not None]
        ys = [y for x in range(w) for y in range(h) if rows[y][x] is not None]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        addr = ATTIC_ICONS + len(data)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                c = rows[y][x]
                data.append(0 if c is None else ICON_BASE + lookup[c])
        tab.append((addr, x1 - x0 + 1, y1 - y0 + 1, x0, y0))
    # the big characters: each advances by its own width
    big = Image.open(os.path.join(m.SRC_ASSETS, 'bigfont.png')).convert('RGBA')
    glyphs = []
    for n in range(BIG_COUNT):
        rows = []
        for y in range(BIG_H):
            r = []
            for x in range(BIG_W):
                p = big.getpixel((n * BIG_W + x, y))
                r.append(tuple(p[:3]) if p[3] >= 128 else None)
            rows.append(r)
        glyphs.append(rows)
    big_colours, big_lookup = m.quantize(glyphs, BIG_N)
    adv = []
    for rows in glyphs:
        xs = [x for x in range(BIG_W) for y in range(BIG_H) if rows[y][x] is not None]
        ys = [y for x in range(BIG_W) for y in range(BIG_H) if rows[y][x] is not None]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        addr = ATTIC_ICONS + len(data)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                c = rows[y][x]
                data.append(0 if c is None else BIG_BASE + big_lookup[c])
        tab.append((addr, x1 - x0 + 1, y1 - y0 + 1, x0, y0))
        adv.append(x1 - x0 + 2)
    lines = ['BIG_FIRST = %d' % BIG_FIRST] + m.asm_bytes('big_w_tab', [t[1] for t in tab[BIG_FIRST:]], fmt='%d')
    lines += m.asm_bytes('big_adv', adv, fmt='%d')
    lines += m.asm_bytes('big_ox', [t[3] for t in tab[BIG_FIRST:]], fmt='%d')
    for name, f in (('vs_lo', lambda t: t[0] & 255), ('vs_hi', lambda t: (t[0] >> 8) & 255),
                    ('vs_bank', lambda t: (t[0] >> 16) & 15), ('vs_mb', lambda t: t[0] >> 20),
                    ('vs_w', lambda t: t[1]), ('vs_h', lambda t: t[2]),
                    ('vs_ox', lambda t: t[3]), ('vs_oy', lambda t: t[4])):
        lines += m.asm_bytes(name, [f(t) for t in tab], fmt='%d')
    m.write_gen('icons.asm', lines, 'icon sprite tables')
    return colours, big_colours, m.write_parts('ICONS', bytes(data))


def build_palette(icon_colours, big_colours):
    pal = list(C_FIXED) + [(0, 0, 0)] * (16 - len(C_FIXED))
    pal += [m.mix((14, 26, 110), (58, 110, 200), i / (BG_N - 1)) for i in range(BG_N)]
    pal += [m.mix((255, 180, 60), (190, 70, 10), i / (HD_N - 1)) for i in range(HD_N)]
    pal += [(0, 0, 0)] * (ICON_BASE - len(pal))
    pal += list(icon_colours) + [(0, 0, 0)] * (ICON_N - len(icon_colours))
    pal += RADAR
    pal += [(16, 24, 44), (150, 165, 190), (255, 255, 255)]     # map bg, line, marker
    pal += [(0, 0, 0)] * (BIG_BASE - len(pal))
    pal += list(big_colours)
    m.write_palette(pal)


def main():
    assemble_stack()
    parts = [(n, ATTIC_MAP + o, ln) for n, o, ln in build_map()]
    colours, big_colours, ip = build_icons()
    parts += [(n, ATTIC_ICONS + o, ln) for n, o, ln in ip]
    build_palette(colours, big_colours)
    m.write_manifest(parts)
    extra = ['ethbin']
    if '--mock' in sys.argv:
        src = sys.argv[sys.argv.index('--mock') + 1]
        names = sorted(f for f in os.listdir(src) if f.startswith('mock'))
        for f in names:
            data = open(os.path.join(src, f), 'rb').read()
            open(os.path.join(m.ASSETS, f), 'wb').write(bytes([0, 0]) + data)
        extra += names
    with open(os.path.join(m.ASSETS, 'files.txt'), 'a') as fh:
        fh.write('\n'.join(extra) + '\n')


if __name__ == '__main__':
    main()
