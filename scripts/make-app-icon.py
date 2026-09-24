#!/usr/bin/env python3
"""Generates the Aether app icon.

The icon is a broadcast mark: a transmitter dot with signal arcs radiating
symmetrically left and right, in white shading to light grey on a dark grey
field — the app's whole palette, and nothing else (see Theme.swift). It is drawn
at 4x and downsampled, which is what gives the arcs clean anti-aliased edges.

Deliberately matte: a flat grey field and no glow behind the mark. The only
gradients are shallow two-tone sweeps, which keep the mark from looking like
flat paint without turning the icon glossy.

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

# Dark grey backdrop, one shade either side of the app's base colour.
BG_TOP = (46, 46, 51)
BG_BOTTOM = (26, 26, 29)
# The mark: white falling away to light grey.
ACCENT_FROM = (255, 255, 255)   # white
ACCENT_TO = (198, 198, 205)     # light grey

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


def build():
    canvas = vertical_gradient((SIZE, SIZE), BG_TOP, BG_BOTTOM)

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
