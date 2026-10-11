#!/usr/bin/env python3
"""Generate the ConvertAll icon set in the "Precision Instrument" DA.

Mark: two thick swap arrows (azure = from, indigo = to) on a deep navy
rounded square.  Everything is drawn at 4096 px and downsampled with LANCZOS,
and the small sizes are palette-reduced to keep the packaged files tiny.

Requires Pillow:  python3 -m pip install pillow
Usage:            python3 linux/packaging/make_icons.py
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
NAVY_TOP = (0x12, 0x1E, 0x38)
NAVY_BOTTOM = (0x0A, 0x11, 0x20)
AZURE = (0x6E, 0x9B, 0xFF)
INDIGO = (0xA9, 0xA6, 0xFF)
AZURE_DARK = (0x1E, 0x5A, 0xE8)
INDIGO_DARK = (0x4F, 0x46, 0xE5)
WHITE = (0xFF, 0xFF, 0xFF)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def rounded_mask(size, radius):
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def gradient(size, top, bottom):
    img = Image.new('RGB', (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        d.line([(0, y), (size, y)], fill=lerp(top, bottom, y / (size - 1)))
    return img


def draw_arrows(d, size, azure, indigo):
    """Draw the two swap arrows centered on the canvas."""
    s = size
    thick = 0.150 * s
    head = 0.150 * s   # head length past the bar end
    half = 0.168 * s   # head half height

    def arrow(cy, x_tail, x_tip, colour):
        sign = 1 if x_tip > x_tail else -1
        bar_end = x_tip - sign * head * 0.55
        d.rounded_rectangle([min(x_tail, bar_end), cy - thick / 2,
                             max(x_tail, bar_end), cy + thick / 2],
                            radius=thick / 2, fill=colour)
        d.polygon([(x_tip, cy), (x_tip - sign * head, cy - half),
                   (x_tip - sign * head, cy + half)], fill=colour)

    # Top arrow points right, bottom arrow points left.
    arrow(0.348 * s, 0.130 * s, 0.870 * s, azure)
    arrow(0.652 * s, 0.870 * s, 0.130 * s, indigo)



def mark(size, azure, indigo, scale=1.0):
    """Transparent image holding just the arrows."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    tmp = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw_arrows(ImageDraw.Draw(tmp), size, azure, indigo)
    if scale != 1.0:
        inner = int(size * scale)
        tmp = tmp.resize((inner, inner), Image.LANCZOS)
        off = (size - inner) // 2
        img.paste(tmp, (off, off), tmp)
    else:
        img = tmp
    return img


def badge(size, dark=True):
    """Full icon: rounded square background plus the arrows."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    if dark:
        img.paste(gradient(size, NAVY_TOP, NAVY_BOTTOM), (0, 0),
                  rounded_mask(size, int(size * 0.222)))
        inner = mark(size, AZURE, INDIGO)
        # Hairline highlight just inside the edge.
        border = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(border).rounded_rectangle(
            [int(size * 0.012), int(size * 0.012),
             size - 1 - int(size * 0.012), size - 1 - int(size * 0.012)],
            radius=int(size * 0.212), outline=(255, 255, 255, 26),
            width=max(1, int(size * 0.003)))
        img = Image.alpha_composite(img, inner)
        img = Image.alpha_composite(img, border)
    else:
        img.paste((255, 255, 255, 255), (0, 0),
                  rounded_mask(size, int(size * 0.222)))
        img = Image.alpha_composite(img, mark(size, AZURE_DARK, INDIGO_DARK))
    return img


def square_badge(size, content_scale):
    """Full-bleed square (for maskable web icons)."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    img.paste(gradient(size, NAVY_TOP, NAVY_BOTTOM), (0, 0))
    img = Image.alpha_composite(img, mark(size, AZURE, INDIGO,
                                          scale=content_scale))
    return img


def save(img, path, size=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if size is not None:
        img = img.resize((size, size), Image.LANCZOS)
    if size is not None and size <= 64:
        # Lossless-looking palette reduction for the small sizes: identical
        # to the eye, a fraction of the file.
        img = img.convert('RGBA').quantize(colors=64,
                                          method=Image.FASTOCTREE,
                                          dither=Image.FLOYDSTEINBERG)
    img.save(path, optimize=True, compress_level=9)
    print('wrote', path, img.size)


SS = 4096  # supersampled master
master = badge(SS, dark=True)
master_white = badge(SS, dark=False)
m1024 = master.resize((1024, 1024), Image.LANCZOS)
w1024 = master_white.resize((1024, 1024), Image.LANCZOS)

save(master, f'{OUT}/assets/launcher/convertall_icon_1024.png', 1024)
save(master_white, f'{OUT}/assets/launcher/convertall_icon_1024_white.png', 1024)
save(master, f'{OUT}/assets/launcher/convertall_icon_512.png', 512)
# Android adaptive foreground: arrows only, inside the safe zone.
save(mark(SS, AZURE, INDIGO, scale=0.62),
     f'{OUT}/assets/launcher/convertall_icon_108.png', 108)
for px in (32, 48, 64):
    save(master, f'{OUT}/assets/images/convertall_icon_{px}.png', px)
save(master, f'{OUT}/convertall_icon_64.png', 64)
for px in (48, 64, 128, 256, 512):
    save(master, f'{OUT}/linux/packaging/icons/hicolor/{px}x{px}/apps/'
                 f'convertall.png', px)
save(master, f'{OUT}/web/icons/Icon-192.png', 192)
save(master, f'{OUT}/web/icons/Icon-512.png', 512)
save(square_badge(SS, 0.66), f'{OUT}/web/icons/Icon-maskable-192.png', 192)
save(square_badge(SS, 0.66), f'{OUT}/web/icons/Icon-maskable-512.png', 512)
save(master, f'{OUT}/web/favicon.png', 48)
save(master, f'{OUT}/docs/favicon.png', 48)
save(master, '/tmp/icon_preview.png', 256)
