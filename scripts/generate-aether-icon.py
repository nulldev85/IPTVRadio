"""Render the Aether app lettermark at App Store resolution.

The mark is intentionally typographic: one distinctive Æ glyph, generous
negative space, and the exact ink and paper colors used by the iOS theme.
Run with Pillow installed; the generated PNG is committed for Xcode.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "IPTVRadio/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
FONT_CANDIDATES = (
    Path("C:/Windows/Fonts/georgiab.ttf"),
    Path("/System/Library/Fonts/Supplemental/Georgia Bold.ttf"),
    Path("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"),
)


def main() -> None:
    scale = 4
    side = 1024 * scale
    image = Image.new("RGB", (side, side), "#223B2D")
    draw = ImageDraw.Draw(image)
    font_path = next((path for path in FONT_CANDIDATES if path.exists()), None)
    if font_path is None:
        raise SystemExit("Install Georgia Bold or DejaVu Serif Bold to render the icon")

    font = ImageFont.truetype(str(font_path), 695 * scale)
    mark = "Æ"
    left, top, right, bottom = draw.textbbox((0, 0), mark, font=font)
    width, height = right - left, bottom - top
    x = (side - width) / 2 - left
    y = (side - height) / 2 - top - 20 * scale
    draw.text((x, y), mark, font=font, fill="#F5F3EC")

    image.resize((1024, 1024), Image.Resampling.LANCZOS).save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
