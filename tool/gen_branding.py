#!/usr/bin/env python3
"""Generates every pistak. brand asset (icons, splash, web icons, wordmark).
Run from the repo root:  python3 tool/gen_branding.py [hockey]
Needs Pillow. Font: assets/fonts/Poppins-Bold.ttf (SIL OFL, see OFL.txt).
Each sport app only changes ACCENT (the dot colour) and its hero image."""
import os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.getcwd()
FONT = os.path.join(ROOT, 'assets/fonts/Poppins-Bold.ttf')
BG = (11, 15, 20, 255)       # PistakColors.background (#0B0F14)
WHITE = (255, 255, 255, 255)
SPORTS = {'hockey': (184, 242, 58, 255)}   # lime
ACCENT = SPORTS[sys.argv[1] if len(sys.argv) > 1 else 'hockey']
SS = 4  # supersampling


def mark(word, size, box_frac, bg=None, fg=WHITE, dot=ACCENT, track=-0.03):
    """`word` + dot, centred in a size×size (or (w,h)) canvas, spanning box_frac."""
    w, h = (size, size) if isinstance(size, int) else size
    W, H = w * SS, h * SS
    img = Image.new('RGBA', (W, H), bg or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def measure(fs):
        f = ImageFont.truetype(FONT, fs)
        x, adv = 0, []
        for ch in word:
            adv.append(x)
            x += f.getlength(ch) + track * fs
        xb = f.getbbox('x')
        xh = xb[3] - xb[1]
        r = xh * 0.25
        top = min(f.getbbox(c)[1] for c in word)
        bottom = max(f.getbbox(c)[3] for c in word)
        return f, adv, x, r, top, bottom, xb[3], x + r * 0.45 + 2 * r

    lo, hi = 4, H * 2
    while hi - lo > 1:
        mid = (lo + hi) // 2
        m = measure(mid)
        ok = m[7] <= W * box_frac and (m[5] - m[4]) <= H * box_frac
        lo, hi = (mid, hi) if ok else (lo, mid)
    f, adv, x, r, top, bottom, base, total = measure(lo)
    ox = (W - total) / 2
    oy = (H - (bottom - top)) / 2 - top
    for i, ch in enumerate(word):
        d.text((ox + adv[i], oy), ch, font=f, fill=fg)
    cx, cy = ox + x + r * 0.45 + r, oy + base - r
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=dot)
    return img.resize((w, h), Image.LANCZOS)


def rounded(img, radius_frac):
    m = Image.new('L', (img.width * SS, img.height * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, m.width - 1, m.height - 1),
                                        radius=int(m.width * radius_frac), fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), m.resize(img.size, Image.LANCZOS))
    return out


def save(img, rel):
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p, optimize=True)
    print('wrote', rel)


res = 'android/app/src/main/res'
dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, k in dens.items():
    # Legacy launcher icon (48dp): rounded dark square with "p."
    save(rounded(mark('p', int(48 * k), 0.58, bg=BG), 0.22), f'{res}/mipmap-{name}/ic_launcher.png')
    # Adaptive icon layers (108dp canvas, 66dp safe zone)
    save(mark('p', int(108 * k), 0.40), f'{res}/mipmap-{name}/ic_launcher_foreground.png')
    save(mark('p', int(108 * k), 0.40, fg=WHITE, dot=WHITE), f'{res}/mipmap-{name}/ic_launcher_monochrome.png')
    # Splash: wordmark (Android ≤ 11 launch_background)
    save(mark('pistak', (int(200 * k), int(80 * k)), 0.95), f'{res}/drawable-{name}/splash_logo.png')

# Web / PWA
save(rounded(mark('p', 192, 0.58, bg=BG), 0.22), 'web/icons/Icon-192.png')
save(rounded(mark('p', 512, 0.58, bg=BG), 0.22), 'web/icons/Icon-512.png')
save(mark('p', 192, 0.42, bg=BG), 'web/icons/Icon-maskable-192.png')
save(mark('p', 512, 0.42, bg=BG), 'web/icons/Icon-maskable-512.png')
save(rounded(mark('p', 32, 0.62, bg=BG), 0.22), 'web/favicon.png')
# In-app / store assets
save(mark('pistak', 1024, 0.84, bg=BG), 'assets/branding/pistak_icon_1024.png')
save(mark('pistak', (1200, 400), 0.92), 'assets/branding/pistak_wordmark.png')
