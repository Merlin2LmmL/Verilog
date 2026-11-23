#!/usr/bin/env python3
"""Assemble example programs and pack them into ui/examples.bin for the playground.

    python3 tools/mkexamples.py [-o file] [program ...]

The playground fetches examples.bin and adds the programs to its example menu, so the
assembled hex of the bigger programs does not have to be pasted into app.js. Without
arguments every program in PROGRAMS is packed.

File format (little-endian):
    8 bytes "CPUEXAM1", u32 number of programs, then for every program
    u16 name length, name (utf-8), u32 header length, header (utf-8: the comment block
    shown above the program), u32 instruction count, u32 data word count,
    the instruction words, the data words (u32 each)
"""
import os
import struct
import subprocess
import sys

here = os.path.dirname(os.path.abspath(os.path.join(__file__, '..')))
PROGRAMS = [                      # file name in programs/, name in the example menu
    ('mandelbrot', 'Mandelbrot'),
    ('life', 'Game of Life'),
    ('pong', 'Pong'),
    ('tetris', 'Tetris'),
    ('cube', 'Spinning cube'),
    ('plasma', 'Plasma'),
    ('paint', 'Paint with mouse or touch'),
    ('hexrun', 'Hexrun'),
    ('platformer/build/platformer', 'Platformer', [     # built from C (see platformer/DESIGN.md)
        '; A side-scrolling platformer written in C, compiled to RV32E assembly and translated to',
        '; this CPU by platformer/tools/rv2cpu.py. Left/right (A/D) walk, space jumps, up (W) runs,',
        '; down (S) crouches. It runs at 60 fps at 2.5 MHz.']),
]


def words(path):
    with open(path) as f:
        return [int(line.split(';')[0].strip(), 16) for line in f if line.split(';')[0].strip()]


def pack(prog, title, note=None):
    if note:                          # a program that is generated in its own folder
        subprocess.run(['make', '-s', '-C', os.path.join(here, 'platformer'), 'cpu'], check=True,
                       capture_output=True)
        src = os.path.join(here, prog.split('/build/')[0], 'build', prog.split('/build/')[1] + '.asm')
        out = os.path.join(here, 'build', prog.split('/')[-1])
    else:
        src = os.path.join(here, 'programs', prog + '.asm')
        out = os.path.join(here, 'build', prog)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run([sys.executable, os.path.join(here, 'tools', 'asm.py'), src, '-o', out],
                   check=True, capture_output=True)
    header = list(note or [])
    with open(src) as f:
        for line in f:
            if note or not line.startswith(';'):
                break
            header.append(line.rstrip('\n'))
    while header and header[-1] == ';':
        header.pop()
    header.append('; Assembled from %s.asm.' % (prog if note else 'programs/' + prog))
    text, data = words(out + '.text.hex'), words(out + '.data.hex')
    name, head = title.encode(), '\n'.join(header).encode()
    blob = struct.pack('<H', len(name)) + name + struct.pack('<I', len(head)) + head
    blob += struct.pack('<II', len(text), len(data))
    blob += struct.pack('<%dI' % len(text), *text) + struct.pack('<%dI' % len(data), *data)
    return blob


def main(argv):
    target = os.path.join(here, 'ui', 'examples.bin')
    if argv[:1] == ['-o']:
        target, argv = argv[1], argv[2:]
    chosen = [p for p in PROGRAMS if not argv or p[0] in argv]
    blobs = [pack(*p) for p in chosen]
    with open(target, 'wb') as f:
        f.write(b'CPUEXAM1' + struct.pack('<I', len(blobs)) + b''.join(blobs))
    print('wrote %s: %d programs, %d bytes' % (target, len(blobs), os.path.getsize(target)))


if __name__ == '__main__':
    main(sys.argv[1:])
