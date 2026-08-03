#!/usr/bin/env python3
"""Generate all game assets: 8-bit WAV sounds + AppIcon.icns.

Pure stdlib (wave, zlib, struct) + macOS tools (sips, iconutil).
Run from anywhere: paths are resolved relative to this script.
"""
import math
import os
import random
import shutil
import struct
import subprocess
import wave
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOUNDS = os.path.join(ROOT, "Resources", "Sounds")
RESOURCES = os.path.join(ROOT, "Resources")
RATE = 22050

# ---------------------------------------------------------------- sounds

def write_wav(name, samples):
    os.makedirs(SOUNDS, exist_ok=True)
    path = os.path.join(SOUNDS, name + ".wav")
    data = bytes(max(0, min(255, int(128 + s * 127))) for s in samples)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(1)  # 8-bit unsigned: authentic grit
        f.setframerate(RATE)
        f.writeframes(data)
    print("wav :", path, f"({len(samples)/RATE:.2f}s)")


def square(phase):
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


def sweep(f0, f1, dur, vol=0.6, exp=True):
    """Square wave frequency sweep."""
    n = int(dur * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / n
        f = f0 * (f1 / f0) ** t if exp else f0 + (f1 - f0) * t
        phase += f / RATE
        env = 1.0 - t * 0.6
        out.append(square(phase) * vol * env)
    return out


def noise_burst(dur, vol=0.8, decay=3.0, lowpass=0.25):
    rng = random.Random(1234)
    n = int(dur * RATE)
    out, last = [], 0.0
    for i in range(n):
        t = i / n
        last += (rng.uniform(-1, 1) - last) * lowpass
        out.append(last * vol * math.exp(-decay * t))
    return out


def tone(freq, dur, vol=0.7):
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / n
        env = min(1.0, (1.0 - t) * 4)
        out.append(square(freq * i / RATE) * vol * env)
    return out


def gen_sounds():
    # Player shot: fast descending zap
    write_wav("shoot", sweep(1800, 220, 0.16, vol=0.45))
    # Invader killed: low crunchy blip + noise tail
    hit = sweep(240, 50, 0.22, vol=0.7)
    ns = noise_burst(0.22, vol=0.35, decay=6)
    write_wav("inv_hit", [a + b for a, b in zip(hit, ns)])
    # Player explosion: long filtered noise
    write_wav("explosion", noise_burst(0.75, vol=0.95, decay=3.2, lowpass=0.18))
    # The famous 4-note bass march (descending)
    for i, f in enumerate([110, 98, 88, 78]):
        write_wav(f"march{i + 1}", tone(f, 0.11, vol=0.8))
    # UFO siren: loopable warble (integer number of mod cycles)
    dur, mod_hz = 0.8, 5.0
    n = int(dur * RATE)
    out, phase = [], 0.0
    for i in range(n):
        t = i / RATE
        f = 420 + 160 * math.sin(2 * math.pi * mod_hz * t)
        phase += f / RATE
        out.append(square(phase) * 0.28)
    write_wav("ufo", out)
    # UFO destroyed: descending arpeggio blips
    arp = []
    for f in [1200, 900, 700, 500, 350, 250]:
        arp += tone(f, 0.07, vol=0.6)
    write_wav("ufo_hit", arp)
    # Extra life: ascending blips
    ext = []
    for f in [523, 659, 784, 1047]:
        ext += tone(f, 0.09, vol=0.55)
    write_wav("extra", ext)

# ---------------------------------------------------------------- icon

W = 1024

CRAB = [
    "..#.....#..",
    "...#...#...",
    "..#######..",
    ".##.###.##.",
    "###########",
    "#.#######.#",
    "#.#.....#.#",
    "...##.##...",
]
CANNON = [
    "......#......",
    ".....###.....",
    ".....###.....",
    ".###########.",
    "#############",
    "#############",
    "#############",
    "#############",
]


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.buf = bytearray(w * h * 4)

    def blend(self, x, y, r, g, b, a):
        if not (0 <= x < self.w and 0 <= y < self.h):
            return
        i = (y * self.w + x) * 4
        sa = a / 255.0
        for k, c in enumerate((r, g, b)):
            self.buf[i + k] = int(c * sa + self.buf[i + k] * (1 - sa))
        self.buf[i + 3] = max(self.buf[i + 3], a)

    def rect(self, x0, y0, w, h, r, g, b, a=255):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.blend(x, y, r, g, b, a)

    def png(self, path):
        raw = b""
        for y in range(self.h):
            raw += b"\x00" + bytes(self.buf[y * self.w * 4:(y + 1) * self.w * 4])

        def chunk(tag, data):
            c = tag + data
            return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

        png = b"\x89PNG\r\n\x1a\n"
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 6, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(raw, 9))
        png += chunk(b"IEND", b"")
        with open(path, "wb") as f:
            f.write(png)


def in_squircle(x, y, x0, y0, size, radius):
    dx = max(0, abs(x - (x0 + size / 2)) - (size / 2 - radius))
    dy = max(0, abs(y - (y0 + size / 2)) - (size / 2 - radius))
    return dx * dx + dy * dy <= radius * radius


def draw_pattern(cv, pattern, px, x0, y0, color, alpha=255):
    r, g, b = color
    for row_i, row in enumerate(pattern):
        for col_i, ch in enumerate(row):
            if ch == "#":
                cv.rect(x0 + col_i * px, y0 + row_i * px, px, px, r, g, b, alpha)


def gen_icon():
    cv = Canvas(W, W)
    m, size, radius = 100, 824, 185
    # Background: vertical gradient deep black -> dark blue
    for y in range(m, m + size):
        t = (y - m) / size
        r, g, b = int(4 + 10 * t), int(5 + 14 * t), int(12 + 36 * t)
        for x in range(m, m + size):
            if in_squircle(x, y, m, m, size, radius):
                i = (y * W + x) * 4
                cv.buf[i:i + 4] = bytes((r, g, b, 255))
    # Stars
    rng = random.Random(42)
    for _ in range(46):
        x = rng.randrange(m + 30, m + size - 30)
        y = rng.randrange(m + 30, m + size - 30)
        s = rng.choice([4, 4, 6])
        a = rng.randrange(60, 160)
        if in_squircle(x, y, m, m, size, radius):
            cv.rect(x, y, s, s, 220, 255, 230, a)
    # Big crab invader, phosphor green, with soft drop glow
    px = 52
    iw, ih = 11 * px, 8 * px
    ix, iy = (W - iw) // 2, 230
    draw_pattern(cv, CRAB, px, ix + 8, iy + 10, (10, 90, 40), 160)   # glow/shadow
    draw_pattern(cv, CRAB, px, ix, iy, (60, 255, 110))
    # Player shot
    cv.rect(W // 2 - 5, iy + ih + 40, 10, 120, 240, 255, 240)
    # Cannon at the bottom
    cpx = 16
    cw = 13 * cpx
    draw_pattern(cv, CANNON, cpx, (W - cw) // 2, 700, (60, 255, 110))
    # Scanlines
    for y in range(m, m + size, 6):
        for yy in range(y, min(y + 2, m + size)):
            for x in range(m, m + size):
                if in_squircle(x, yy, m, m, size, radius):
                    i = (yy * W + x) * 4
                    for k in range(3):
                        cv.buf[i + k] = int(cv.buf[i + k] * 0.78)
    # Clip everything outside the squircle
    for y in range(W):
        for x in range(W):
            if not in_squircle(x, y, m, m, size, radius):
                i = (y * W + x) * 4
                cv.buf[i:i + 4] = b"\x00\x00\x00\x00"

    os.makedirs(RESOURCES, exist_ok=True)
    iconset = os.path.join(ROOT, "AppIcon.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)
    master = os.path.join(iconset, "icon_512x512@2x.png")
    cv.png(master)
    sizes = [(16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
             (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
             (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
             (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
             (512, "icon_512x512.png")]
    for s, name in sizes:
        subprocess.run(["sips", "-z", str(s), str(s), master,
                        "--out", os.path.join(iconset, name)],
                       check=True, capture_output=True)
    icns = os.path.join(RESOURCES, "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
    shutil.rmtree(iconset)
    print("icns:", icns)


if __name__ == "__main__":
    gen_sounds()
    gen_icon()
    print("Done.")
