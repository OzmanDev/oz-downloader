#!/usr/bin/env python3
"""Installer window art: theme glows, a blue arrow, and a short instruction."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 640, 400
INK = (16, 18, 24, 255)
BLUE = (10, 132, 255)
VIOLET = (117, 82, 173)
TEAL = (46, 122, 128)
ARROW = (120, 186, 255, 255)
TITLE = (244, 246, 250, 255)
LABEL = (186, 196, 214, 255)


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    if bold:
        candidates.insert(0, "/System/Library/Fonts/Supplemental/Arial Bold.ttf")
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def paint_glow(img: Image.Image, cx: int, cy: int, radius: int, rgb: tuple[int, int, int], peak: int) -> None:
    grad = Image.radial_gradient("L").resize((radius * 2, radius * 2))
    mask = Image.eval(grad, lambda p: int(peak * (255 - p) / 255))
    layer = Image.new("RGBA", (radius * 2, radius * 2), (*rgb, 0))
    layer.putalpha(mask)
    img.alpha_composite(layer, (cx - radius, cy - radius))


def render() -> Image.Image:
    img = Image.new("RGBA", (W, H), INK)
    paint_glow(img, 40, 40, 260, BLUE, 110)
    paint_glow(img, 620, 20, 240, VIOLET, 100)
    paint_glow(img, 300, 420, 280, TEAL, 80)

    draw = ImageDraw.Draw(img)
    title_font = font(28, bold=True)
    sub_font = font(16)
    title = "Oz Downloader"
    subtitle = "Drag the app into Applications"
    title_box = draw.textbbox((0, 0), title, font=title_font)
    sub_box = draw.textbbox((0, 0), subtitle, font=sub_font)
    title_w = title_box[2] - title_box[0]
    sub_w = sub_box[2] - sub_box[0]
    draw.text(((W - title_w) // 2, 28), title, fill=TITLE, font=title_font)
    draw.text(((W - sub_w) // 2, 64), subtitle, fill=LABEL, font=sub_font)

    # Sits on the gap between the app icon and the Applications folder.
    cx, cy = W // 2, 176
    draw.rounded_rectangle([cx - 78, cy - 5, cx + 28, cy + 5], radius=5, fill=ARROW)
    draw.polygon([(cx + 22, cy - 18), (cx + 64, cy), (cx + 22, cy + 18)], fill=ARROW)
    return img


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "build" / "dmg-resources" / "background.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    render().save(out)
    print(out)


if __name__ == "__main__":
    main()
