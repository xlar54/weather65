"""Zero-run packing for lib/unpack.asm: $00 n = n zero bytes (1-255), other bytes as is.

  import pack; packed = pack.pack(data)
  python tools/pack.py IN OUT [--prg]     pack a file (--prg: prepend a 2-byte PRG header)
"""
import sys


def pack(data):
    out, i = bytearray(), 0
    while i < len(data):
        if data[i] == 0:
            n = 1
            while i + n < len(data) and data[i + n] == 0 and n < 255:
                n += 1
            out += bytes([0, n])
            i += n
        else:
            out.append(data[i])
            i += 1
    return bytes(out)


def unpack(data):
    out, i = bytearray(), 0
    while i < len(data):
        if data[i] == 0:
            out += bytes(data[i + 1])
            i += 2
        else:
            out.append(data[i])
            i += 1
    return bytes(out)


if __name__ == '__main__':
    raw = open(sys.argv[1], 'rb').read()
    packed = pack(raw)
    assert unpack(packed) == raw
    open(sys.argv[2], 'wb').write((b'\0\0' if '--prg' in sys.argv else b'') + packed)
    print('%d -> %d bytes' % (len(raw), len(packed)))
