#!/usr/bin/env python3
"""Turn an assembler .data.hex (one 32-bit word per line) into a binary RAM image.

    python3 tools/hex2bin.py in.data.hex out.bin
"""
import struct
import sys

with open(sys.argv[1]) as f:
    words = [int(line.split(';')[0], 16) for line in f if line.split(';')[0].strip()]
with open(sys.argv[2], 'wb') as f:
    f.write(struct.pack('<%dI' % len(words), *words))
print('%s: %d bytes' % (sys.argv[2], 4 * len(words)))
