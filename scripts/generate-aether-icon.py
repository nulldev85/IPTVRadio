"""Render Aether's record-shaped lettermark as an opaque iOS app icon.

The single-story a is drawn as a record: its bowl is the outer rim, the thin
inner circle is a label groove, and the dot is the spindle. All geometry is
rendered at 3x and downsampled for clean edges at Home Screen sizes.
"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "IPTVRadio/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIDE = 1024
SCALE = 3
FOREST = "#193428"
PAPER = "#F5F3EC"
GROOVE = "#7E9D82"
SPINDLE = "#B5D4B3"


def px(value: int) -> int:
    return value * SCALE


def canvas() -> Image.Image:
    """Make a quiet tonal field so the mark remains crisp at small sizes."""
    size = SIDE * SCALE
    image = Image.new("RGB", (size, size), FOREST)
    glow = Image.new("L", (96, 96))
    pixels = glow.load()
    for y in range(96):
        for x in range(96):
            distance = (((x - 20) / 105) ** 2 + ((y - 8) / 105) ** 2) ** 0.5
            pixels[x, y] = max(0, round(100 * (1 - distance) ** 2))
    glow = glow.resize((size, size), Image.Resampling.BICUBIC)
    image.paste("#365743", (0, 0, size, size), glow)
    return image


def render() -> Image.Image:
    image = canvas()
    draw = ImageDraw.Draw(image)

    # The bowl and short terminal form a bespoke lowercase a without a font.
    draw.ellipse(tuple(map(px, (256, 270, 734, 748))), outline=PAPER, width=px(78))
    draw.rounded_rectangle(
        tuple(map(px, (656, 493, 734, 748))), radius=px(39), fill=PAPER
    )

    # Two restrained record details survive at notification size.
    draw.ellipse(tuple(map(px, (385, 399, 605, 619))), outline=GROOVE, width=px(13))
    draw.ellipse(tuple(map(px, (477, 491, 513, 527))), fill=SPINDLE)

    return image.resize((SIDE, SIDE), Image.Resampling.LANCZOS).convert("RGB")


if __name__ == "__main__":
    render().save(OUTPUT, "PNG", optimize=True)
    print(OUTPUT)
