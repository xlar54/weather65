"""Build-time asset helpers: PNG sheets -> the
library's data formats. A project's tools/build_assets.py imports this and adds its own
layout (which sheets, palette entries, attic addresses).

  sheet_load / sheet_save   an RGBA PNG of w x h cells <-> sprites as RGB rows (None = transparent)
  quantize                  every art colour -> one of `count` palette entries
  encode_blit               sprites -> lib/blit.asm format (column-major, 512 bytes each) + boxes
  encode_hws16              16 px wide sprite rows -> lib/hwsprite.asm 16-colour format
  write_parts               data -> files packed for lib/unpack.asm (2-byte PRG header)
  write_palette / write_manifest / write_boxes / write_gen   src/gen/*.asm
Pixels with alpha < 128 are transparent. Palette tables are raw r/g/b (lib/palette.asm
nibble-swaps them for the VIC-IV).
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pack import pack  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_ASSETS = os.path.join(ROOT, 'src', 'assets')
GEN = os.path.join(ROOT, 'src', 'gen')
ASSETS = os.path.join(ROOT, 'target', 'assets')
GENERATOR = 'tools/build_assets.py'


# ---- PNG sheets ----------------------------------------------------------------------

def sheet_save(sprites, path, cols, w=24, h=21):
    """RGB rows (None = transparent) -> an RGBA PNG of w x h cells, cols a row"""
    rows_n = (len(sprites) + cols - 1) // cols
    im = Image.new('RGBA', (cols * w, rows_n * h), (0, 0, 0, 0))
    for n, rows in enumerate(sprites):
        ox, oy = (n % cols) * w, (n // cols) * h
        for y in range(h):
            for x in range(w):
                if rows[y][x] is not None:
                    im.putpixel((ox + x, oy + y), tuple(rows[y][x]) + (255,))
    im.save(path)


def sheet_load(path, count, cols, w=24, h=21):
    """an RGBA PNG of w x h cells -> count sprites of RGB rows (None = transparent)"""
    im = Image.open(path).convert('RGBA')
    out = []
    for n in range(count):
        ox, oy = (n % cols) * w, (n // cols) * h
        rows = []
        for y in range(h):
            r = []
            for x in range(w):
                inside = ox + x < im.width and oy + y < im.height
                p = im.getpixel((ox + x, oy + y)) if inside else (0, 0, 0, 0)
                r.append(tuple(p[:3]) if p[3] >= 128 else None)
            rows.append(r)
        out.append(rows)
    return out


def load_names(path):
    """a names file (one per line, in id order) -> list"""
    return [n.strip() for n in open(path) if n.strip()]


# ---- colours ------------------------------------------------------------------------

def mix(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def shades(c):
    """a colour, its highlight, shadow and deep shadow"""
    return [c, mix(c, (255, 255, 255), 0.30), mix(c, (0, 0, 0), 0.35), mix(c, (0, 0, 0), 0.60)]


def nibble_swap(v):
    return (v & 15) << 4 | v >> 4


def quantize(sprites, count, fixed=()):
    """map every art colour (not in `fixed`) to one of `count` entries -> (colours, lookup)"""
    colours = sorted({c for rows in sprites for r in rows for c in r
                      if c is not None and c not in fixed})
    if len(colours) <= count:
        return colours, {c: i for i, c in enumerate(colours)}
    img = Image.new('RGB', (len(colours), 1))
    img.putdata(colours)
    q = img.quantize(colors=count, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()[:count * 3]
    idx = list(q.getdata())
    return [tuple(pal[i * 3:i * 3 + 3]) for i in range(count)], {c: idx[i] for i, c in enumerate(colours)}


# ---- encoders -----------------------------------------------------------------------

def encode_blit(sprites, index, w=24, h=21, stride=512):
    """RGB sprites -> (column-major bytes, `stride` per sprite; [(x0, x1, y0, y1)] boxes).
    index(colour) gives the palette entry (not 0, which is transparent). An empty sprite
    gets the box (1, 0, 0, 0): x1 < x0."""
    data = bytearray(len(sprites) * stride)
    boxes = []
    for n, rows in enumerate(sprites):
        xs, ys = [], []
        for x in range(w):
            for y in range(h):
                c = rows[y][x]
                if c is not None:
                    data[n * stride + x * h + y] = index(c)
                    xs.append(x)
                    ys.append(y)
        boxes.append((min(xs), max(xs), min(ys), max(ys)) if xs else (1, 0, 0, 0))
    return data, boxes


def encode_hws16(rows, lookup, x0=0):
    """16 px of each row from x0 -> 8 bytes a row, high nibble = left pixel. lookup maps a
    colour to a nibble 1-15 (0 is transparent)."""
    out = bytearray()
    for r in rows:
        for b in range(8):
            pix = [lookup[r[x0 + b * 2 + i]] if r[x0 + b * 2 + i] is not None else 0 for i in range(2)]
            out.append(pix[0] << 4 | pix[1])
    return out


# ---- output files -------------------------------------------------------------------

def write_parts(prefix, data, part_size=0xF000, assets=ASSETS):
    """split data into loadable files packed for lib/unpack.asm (2-byte PRG header)
    -> [(name, offset, unpacked length)]; part_size < 64 KB (it unpacks into one bank)"""
    os.makedirs(assets, exist_ok=True)
    parts = []
    for i in range(0, len(data), part_size):
        name = '%s%d' % (prefix, i // part_size)
        chunk = data[i:i + part_size]
        packed = pack(chunk)
        assert len(packed) <= 0xF000, name + ' does not fit the staging buffer'
        open(os.path.join(assets, name), 'wb').write(bytes([0, 0]) + packed)
        parts.append((name, i, len(chunk)))
    return parts


def asm_bytes(label, data, per_line=16, fmt='$%02x'):
    out = ['%s:' % label] if label else []
    for i in range(0, len(data), per_line):
        out.append('        .byte ' + ','.join(fmt % b for b in data[i:i + per_line]))
    return out


def write_gen(name, lines, what, gen=GEN):
    os.makedirs(gen, exist_ok=True)
    head = ['; %s - generated by %s: %s. Do not edit.' % (name, GENERATOR, what), '']
    open(os.path.join(gen, name), 'w').write('\n'.join(head + lines) + '\n')


def write_palette(colours, label='palette_rgb'):
    """256 colours -> r, g, b tables of 256 (lib/palette.asm pal_src)"""
    colours = list(colours) + [(0, 0, 0)] * (256 - len(colours))
    lines = [label + ':']
    for ch in range(3):
        lines += asm_bytes('', [c[ch] for c in colours])
    write_gen('palette.asm', lines, '256-colour palette, r/g/b tables')


def write_boxes(name, ids, boxes, extra=(), prefix='SPR_', labels=('sprite_x0', 'sprite_x1', 'sprite_y0', 'sprite_y1')):
    """sprite ids (names in order) and their boxes -> src/gen/<name>. Copy the boxes into
    lib/blit.asm's spr_x0/x1/y0/y1 at boot."""
    lines = ['%s%-22s= %d' % (prefix, n, i) for i, n in enumerate(ids)]
    lines += list(extra) + ['']
    for k, label in enumerate(labels):
        lines += asm_bytes(label, [b[k] for b in boxes], fmt='%d')
    write_gen(name, lines, 'sprite ids and boxes')


def write_manifest(files, extra=(), assets=ASSETS):
    """files: [(disk name, attic address, unpacked length)] -> src/gen/manifest.asm, for a
    boot loop calling lib/unpack.asm load_packed_to_attic, and target/assets/files.txt
    for build.bat to write to the D81"""
    lines = ['asset_count = %d' % len(files)] + list(extra)
    lines += ['asset_name_len: .byte ' + ','.join(str(len(n)) for n, _, _ in files)]
    lines += ['asset_name_lo: .byte ' + ','.join('<_an%d' % i for i in range(len(files)))]
    lines += ['asset_name_hi: .byte ' + ','.join('>_an%d' % i for i in range(len(files)))]
    for k in range(4):
        lines += ['asset_attic%d: .byte ' % k +
                  ','.join('$%02x' % ((a >> (8 * k)) & 255) for _, a, _ in files)]
    lines += ['asset_len_lo: .byte ' + ','.join('$%02x' % (n & 255) for _, _, n in files)]
    lines += ['asset_len_hi: .byte ' + ','.join('$%02x' % (n >> 8) for _, _, n in files)]
    lines += ['_an%d: .text "%s"' % (i, n) for i, (n, _, _) in enumerate(files)]
    write_gen('manifest.asm', lines, 'packed asset files: attic addresses, unpacked lengths')
    # c1541 stores lower-case ASCII as unshifted PETSCII, which matches the upper-case .text
    os.makedirs(assets, exist_ok=True)
    open(os.path.join(assets, 'files.txt'), 'w').write('\n'.join(n.lower() for n, _, _ in files) + '\n')
