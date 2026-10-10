#!/usr/bin/env python3
"""Installer window art, drawn at retina size so the arrow stays sharp."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Finder shows this in a 640 by 400 point window. Two pixels per point.
POINTS_W, POINTS_H = 640, 400
SCALE = 2
W, H = POINTS_W * SCALE, POINTS_H * SCALE
INK = (16, 18, 24, 255)
BLUE = (10, 132, 255)
VIOLET = (117, 82, 173)
TEAL = (46, 122, 128)
ARROW = (150, 202, 255, 255)
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


def paint_glow(img: Image.Image, cx: int, cy: int, radius: int, rgb: tuple[int, int, int], alpha: int) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(
        (cx - radius, cy - radius, cx + radius, cy + radius),
        fill=(*rgb, alpha),
    )
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius=radius)))


def paint_arrow(img: Image.Image) -> None:
    """Draw the arrow several times larger, then scale it down so the edge is smooth."""
    oversample = 4
    big = Image.new("RGBA", (img.width * oversample, img.height * oversample), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    cx, cy = (img.width // 2) * oversample, int(176 * SCALE) * oversample
    shaft = (
        cx - 150 * oversample,
        cy - 9 * oversample,
        cx + 36 * oversample,
        cy + 9 * oversample,
    )
    draw.rounded_rectangle(shaft, radius=9 * oversample, fill=ARROW)
    draw.polygon(
        [
            (cx + 16 * oversample, cy - 32 * oversample),
            (cx + 108 * oversample, cy),
            (cx + 16 * oversample, cy + 32 * oversample),
        ],
        fill=ARROW,
    )
    smooth = big.resize(img.size, Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(radius=1.1))
    img.alpha_composite(smooth)


def render() -> Image.Image:
    img = Image.new("RGBA", (W, H), INK)
    paint_glow(img, 180, 220, 150, BLUE, 150)
    paint_glow(img, 1140, 80, 160, VIOLET, 140)
    paint_glow(img, 640, 760, 170, TEAL, 120)

    draw = ImageDraw.Draw(img)
    title_font = font(28 * SCALE, bold=True)
    sub_font = font(16 * SCALE)
    title = "Oz Downloader"
    subtitle = "Drag the app into Applications"
    title_box = draw.textbbox((0, 0), title, font=title_font)
    sub_box = draw.textbbox((0, 0), subtitle, font=sub_font)
    title_w = title_box[2] - title_box[0]
    sub_w = sub_box[2] - sub_box[0]
    draw.text(((W - title_w) // 2, 28 * SCALE), title, fill=TITLE, font=title_font)
    draw.text(((W - sub_w) // 2, 64 * SCALE), subtitle, fill=LABEL, font=sub_font)
    paint_arrow(img)
    return img


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "build" / "dmg-resources" / "background.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    render().save(out, dpi=(72 * SCALE, 72 * SCALE))
    print(out)


if __name__ == "__main__":
    main()
