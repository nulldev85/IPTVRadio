#!/usr/bin/env python3
"""Generates the Aether app icon.

The icon is a broadcast mark: a transmitter dot with signal arcs radiating
symmetrically left and right, in a cool gradient on near-black. It is drawn at
4x and downsampled, which is what gives the arcs clean anti-aliased edges.

The output is deliberately opaque RGB — iOS rejects app icons with an alpha
channel — and full-bleed square, because iOS applies its own rounded-rect mask.

Usage:
    python3 scripts/make-app-icon.py [output_path]

Requires Pillow (`pip install Pillow`). Committed so the icon is reproducible
and tweakable instead of an opaque binary.
"""
import sys
from PIL import Image, ImageDraw

FINAL = 1024
SS = 4                      # supersample factor
SIZE = FINAL * SS
CENTER = SIZE // 2

# Near-black backdrop, matching the app's OLED-friendly dark theme.
BG_TOP = (11, 11, 16)
BG_BOTTOM = (5, 5, 10)
# Cool accent gradient for the mark.
ACCENT_FROM = (125, 246, 255)   # pale cyan
ACCENT_TO = (88, 92, 255)       # indigo

DOT_RADIUS = 180 * SS // 4
ARC_RADII = [600, 940, 1280]
ARC_WIDTH = 124
ARC_HALF_ANGLE = 42             # degrees either side of horizontal


def vertical_gradient(size, top, bottom):
    """One-pixel-wide gradient stretched to size — cheap and smooth."""
    strip = Image.new("RGB", (1, size[1]))
    pixels = strip.load()
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        pixels[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
    return strip.resize(size, Image.BILINEAR)


def diagonal_gradient(size, start, end):
    """Diagonal gradient, built by rotating a vertical one."""
    side = int(max(size) * 1.5)
    strip = vertical_gradient((side, side), start, end)
    rotated = strip.rotate(45, resample=Image.BICUBIC, expand=False)
    left = (side - size[0]) // 2
    top = (side - size[1]) // 2
    return rotated.crop((left, top, left + size[0], top + size[1]))


def radial_glow(size, peak, extent):
    """Smooth radial falloff.

    Drawn tiny and upscaled: interpolation gives a clean ramp, where stacked
    ellipses leave visible concentric banding.
    """
    small = 96
    field = Image.new("L", (small, small), 0)
    pixels = field.load()
    mid = (small - 1) / 2
    for y in range(small):
        for x in range(small):
            dx = (x - mid) / mid
            dy = (y - mid) / mid
            d = min(1.0, (dx * dx + dy * dy) ** 0.5 / extent)
            # Smoothstep falloff, brightest at the centre.
            t = 1.0 - d
            pixels[x, y] = round(peak * t * t * (3 - 2 * t))
    return field.resize(size, Image.BICUBIC)


def build():
    canvas = vertical_gradient((SIZE, SIZE), BG_TOP, BG_BOTTOM)

    # A faint glow behind the mark gives depth without adding clutter.
    glow = radial_glow((SIZE, SIZE), peak=34, extent=0.95)
    canvas.paste(diagonal_gradient((SIZE, SIZE), ACCENT_FROM, ACCENT_TO), (0, 0), glow)

    # The mark itself, drawn into a mask so it can be filled with a gradient.
    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse(
        [CENTER - DOT_RADIUS, CENTER - DOT_RADIUS, CENTER + DOT_RADIUS, CENTER + DOT_RADIUS],
        fill=255,
    )
    for radius in ARC_RADII:
        r = radius * SS // 4
        box = [CENTER - r, CENTER - r, CENTER + r, CENTER + r]
        width = ARC_WIDTH * SS // 4
        # Right-hand and left-hand arcs: a signal leaving in both directions.
        draw.arc(box, -ARC_HALF_ANGLE, ARC_HALF_ANGLE, fill=255, width=width)
        draw.arc(box, 180 - ARC_HALF_ANGLE, 180 + ARC_HALF_ANGLE, fill=255, width=width)

    canvas.paste(diagonal_gradient((SIZE, SIZE), ACCENT_FROM, ACCENT_TO), (0, 0), mask)

    # Downsample last: this is what anti-aliases the arcs.
    icon = canvas.resize((FINAL, FINAL), Image.LANCZOS)
    return icon.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "IPTVRadio/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    build().save(out, "PNG", optimize=True)
    print(f"wrote {out}")
