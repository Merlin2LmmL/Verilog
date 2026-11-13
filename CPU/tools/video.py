#!/usr/bin/env python3
"""Turn a black-and-white video into the compressed format that programs/video.asm plays.

    tools/video.py --demo                     the built-in demo animation -> programs/video.bin
    tools/video.py --video clip.mp4 --fps 15  any video (needs ffmpeg)
    tools/video.py --frames dir/              a folder of images, sorted by name
    add --preview out.gif to check the result (decoded from the .bin again)

The screen is 128 x 96 and only black (0x00) and white (0xFF) are used. The format, "delta
runs", only stores which pixels change from one frame to the next:

    word   number of frames
    word   screen refreshes per frame (60 refreshes per second, so 5 = 12 fps)
    then for every frame: pairs of numbers (skip, flip)
        skip  pixels that stay as they are
        flip  pixels that change (black <-> white), so the player XORs them with 0xFF
        flip = 0 ends the frame
    numbers are LEB128: 7 bits per byte, the top bit says "another byte follows"

Pixels are counted from the top left, row by row, without restarting at a new row, so a
still picture costs 2 bytes per frame and a moving shape only costs its edges.
"""
import argparse
import math
import os
import struct
import subprocess
import sys

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit('needs numpy and Pillow:  pip install numpy pillow')

W, H = 128, 96
REFRESH_HZ = 60         # the VSYNC register counts this many screen refreshes per second


def leb128(n):
    out = bytearray()
    while True:
        byte = n & 0x7F
        n >>= 7
        if n:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return out


def encode(frames, refreshes):
    """frames: list of bool arrays (H, W), True = white"""
    out = bytearray(struct.pack('<II', len(frames), refreshes))
    prev = np.zeros(W * H, dtype=bool)
    for frame in frames:
        cur = frame.reshape(-1)
        changed = np.flatnonzero(np.diff(np.concatenate(([0], (cur != prev).astype(np.int8), [0]))))
        pos = 0
        for start, end in zip(changed[0::2], changed[1::2]):    # runs of changed pixels
            out += leb128(start - pos) + leb128(end - start)
            pos = end
        out += b'\x00\x00'
        prev = cur
    return bytes(out)


def decode(data):
    """the same thing the CPU does, to check the encoder and for --preview"""
    count, refreshes = struct.unpack_from('<II', data)
    i = 8

    def number():
        nonlocal i
        n = shift = 0
        while True:
            byte = data[i]
            i += 1
            n |= (byte & 0x7F) << shift
            shift += 7
            if not byte & 0x80:
                return n

    screen = np.zeros(W * H, dtype=bool)
    frames = []
    for _ in range(count):
        pos = 0
        while True:
            pos += number()
            flip = number()
            if flip == 0:
                break
            screen[pos:pos + flip] ^= True
            pos += flip
        frames.append(screen.reshape(H, W).copy())
    return frames, refreshes


# ---------- input ----------

def to_bw(gray, threshold):
    return np.asarray(gray, dtype=np.uint8) >= threshold


def fit(img):
    """scale an image into 128 x 96, black bars if the shape doesn't match"""
    img = img.convert('L')
    scale = min(W / img.width, H / img.height)
    w, h = max(1, round(img.width * scale)), max(1, round(img.height * scale))
    canvas = Image.new('L', (W, H), 0)
    canvas.paste(img.resize((w, h), Image.LANCZOS), ((W - w) // 2, (H - h) // 2))
    return canvas


def read_frames_dir(path, threshold):
    names = sorted(n for n in os.listdir(path) if n.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp', '.gif')))
    if not names:
        sys.exit(f'no images in {path}')
    return [to_bw(fit(Image.open(os.path.join(path, n))), threshold) for n in names]


def read_video(path, fps, threshold):
    vf = (f'fps={fps},scale={W}:{H}:force_original_aspect_ratio=decrease,'
          f'pad={W}:{H}:(ow-iw)/2:(oh-ih)/2')
    try:
        raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-vf', vf, '-f', 'rawvideo',
                              '-pix_fmt', 'gray', '-'], check=True, capture_output=True).stdout
    except FileNotFoundError:
        sys.exit('--video needs ffmpeg')
    except subprocess.CalledProcessError as e:
        sys.exit(e.stderr.decode(errors='replace'))
    return [np.frombuffer(raw[i:i + W * H], np.uint8).reshape(H, W) >= threshold
            for i in range(0, len(raw) - W * H + 1, W * H)]


# ---------- the demo animation ----------

def demo_frames(fps):
    """an original black-and-white animation, drawn with Pillow"""
    frames = []
    big = ImageFont.load_default()

    def frame(draw_fn, seconds):
        n = round(seconds * fps)
        for k in range(n):
            img = Image.new('1', (W, H), 0)
            draw_fn(ImageDraw.Draw(img), k / max(1, n - 1))
            frames.append(np.array(img, dtype=bool))

    def ease(t):
        return t * t * (3 - 2 * t)

    def text_image(text):
        box = big.getbbox(text)
        img = Image.new('1', (box[2] + 2, box[3] + 2), 0)
        ImageDraw.Draw(img).text((1, 1), text, fill=1, font=big)
        return img

    # 1: a white circle opens from the middle
    def iris_open(d, t):
        r = ease(t) * 85
        d.ellipse((64 - r, 48 - r, 64 + r, 48 + r), fill=1)
    frame(iris_open, 1.5)

    # 2: a black ball bouncing on the ground, squashed when it lands
    def bounce(d, t):
        d.rectangle((0, 0, W, H), fill=1)
        d.rectangle((0, 84, W, H), fill=0)
        x = 10 + t * 108
        phase = (t * 4) % 1                      # 4 bounces
        y = 84 - 70 * 4 * phase * (1 - phase)
        squash = max(0.0, 1 - min(phase, 1 - phase) * 12)
        rx, ry = 8 + 3 * squash, 8 - 3 * squash
        d.ellipse((x - rx, y - 2 * ry, x + rx, y), fill=0)
    frame(bounce, 4)

    # 3: a growing, spinning star
    def star(d, t):
        size = 8 + 36 * ease(min(1, t * 2))
        angle = t * 2 * math.pi
        pts = []
        for i in range(10):
            r = size if i % 2 == 0 else size * 0.45
            a = angle + i * math.pi / 5 - math.pi / 2
            pts.append((64 + r * math.cos(a), 48 + r * math.sin(a)))
        d.polygon(pts, fill=1)
    frame(star, 4)

    # 4: someone walking over a hill under the moon
    def walk(d, t):
        d.rectangle((0, 0, W, H), fill=1)
        d.ellipse((92, 8, 112, 28), fill=0)
        d.ellipse((96, 6, 116, 26), fill=1)            # crescent moon
        d.ellipse((-40, 70, 168, 160), fill=0)          # the hill
        x = -10 + t * 148
        ground = 70 + 45 - math.sqrt(max(0, 104 ** 2 - (x - 64) ** 2)) * 45 / 104
        step = math.sin(t * 2 * math.pi * 6)
        hip = (x, ground - 14)
        for s in (step, -step):                          # legs
            d.line((hip, (x + 6 * s, ground)), fill=0, width=3)
        neck = (x, ground - 26)
        d.line((hip, neck), fill=0, width=4)             # body
        for s in (step, -step):                          # arms
            d.line(((x, ground - 23), (x - 6 * s, ground - 15)), fill=0, width=2)
        d.ellipse((x - 5, ground - 37, x + 5, ground - 27), fill=0)    # head
    frame(walk, 6)

    # 5: rain drops falling into rising water
    def rain(d, t):
        level = 96 - 40 * ease(t)
        for i in range(24):
            x = (i * 53) % 128
            y = ((i * 37) + t * 400) % 120 - 20
            if y < level:
                d.line((x, y, x, y + 5), fill=1)
        for x in range(0, W, 2):
            wave = math.sin(x / 8 + t * 12) * 2
            d.line((x, level + wave, x, H), fill=1)
            d.line((x + 1, level + wave, x + 1, H), fill=1)
    frame(rain, 4)

    # 6: a scrolling message
    msg = text_image('HELLO FROM MY CPU')
    msg = msg.resize((msg.width * 3, msg.height * 3), Image.NEAREST)

    def scroll(d, t):
        d.rectangle((0, 0, W, H), fill=1)
        x = round(W - t * (msg.width + W))
        d.bitmap((x, 48 - msg.height // 2), msg, fill=0)
    frame(scroll, 5)

    # 7: and the circle closes again
    def iris_close(d, t):
        r = (1 - ease(t)) * 85
        d.ellipse((64 - r, 48 - r, 64 + r, 48 + r), fill=1)
    frame(iris_close, 1.5)
    return frames


def main():
    p = argparse.ArgumentParser(description='Encode a black-and-white video for programs/video.asm.')
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument('--demo', action='store_true', help='the built-in demo animation')
    src.add_argument('--video', help='a video file (needs ffmpeg)')
    src.add_argument('--frames', help='a folder of images, sorted by name')
    p.add_argument('--fps', type=float, default=12, help='frames per second (default 12)')
    p.add_argument('--threshold', type=int, default=128, help='brighter than this is white (0-255)')
    p.add_argument('--max-bytes', type=int, default=200_000,
                   help='stop adding frames before the file gets bigger (RAM is 256 KB)')
    p.add_argument('-o', '--out', default=os.path.join(os.path.dirname(__file__), '..', 'programs', 'video.bin'))
    p.add_argument('--preview', help='also save the decoded video as a GIF to check it')
    p.add_argument('--js', default=os.path.join(os.path.dirname(__file__), '..', 'ui', 'video-data.js'),
                   help='the data memory for the playground example (default ui/video-data.js), "" = none')
    a = p.parse_args()

    # every frame stays on screen for a whole number of refreshes, so 60 / n fps
    refreshes = max(1, round(REFRESH_HZ / a.fps))
    if REFRESH_HZ / refreshes != a.fps:
        print(f'using {REFRESH_HZ / refreshes:g} fps (60 / {refreshes}) instead of {a.fps:g}')
    a.fps = REFRESH_HZ / refreshes

    if a.demo:
        frames = demo_frames(a.fps)
    elif a.video:
        frames = read_video(a.video, a.fps, a.threshold)
    else:
        frames = read_frames_dir(a.frames, a.threshold)
    if not frames:
        sys.exit('no frames')

    data = encode(frames, refreshes)
    if len(data) > a.max_bytes:          # too long for the RAM: cut it at the last frame that fits
        lo, hi = 1, len(frames)
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if len(encode(frames[:mid], refreshes)) <= a.max_bytes:
                lo = mid
            else:
                hi = mid - 1
        print(f'warning: only the first {lo} of {len(frames)} frames fit into {a.max_bytes} bytes')
        frames = frames[:lo]
        data = encode(frames, refreshes)

    back, _ = decode(data)
    assert all((x == y).all() for x, y in zip(back, frames)), 'decoding gives different frames'
    with open(a.out, 'wb') as f:
        f.write(data)
    raw = len(frames) * W * H // 8
    print(f'{a.out}: {len(frames)} frames, {len(frames) / a.fps:.1f} s at {a.fps:g} fps, '
          f'{len(data)} bytes ({raw} as plain 1-bit pictures, {raw / len(data):.1f}x smaller)')

    if a.js:
        # video.asm has nothing in .data except the video, so its data memory is just these
        # bytes as little-endian hex words (the same thing asm.py writes into .data.hex)
        padded = data + bytes(-len(data) % 4)
        words = '\n'.join(f"{int.from_bytes(padded[i:i + 4], 'little'):08x}" for i in range(0, len(padded), 4))
        with open(a.js, 'w') as f:
            f.write('// data memory of programs/video.asm for the playground, made by tools/video.py\n')
            f.write(f'window.CPU_VIDEO_DATA = `{words}`;\n')
        print(f'playground data: {a.js}')

    if a.preview:
        imgs = [Image.fromarray(f.astype(np.uint8) * 255).resize((W * 2, H * 2), Image.NEAREST) for f in back]
        imgs[0].save(a.preview, save_all=True, append_images=imgs[1:], duration=round(1000 / a.fps), loop=0)
        print(f'preview: {a.preview}')


if __name__ == '__main__':
    main()
