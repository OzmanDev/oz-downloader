#!/usr/bin/env python3
"""Generate a simple DMG background: arrow + 'Drag here'."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 640, 400
# Soft dark gray matching Finder dark windows
bg = (38, 40, 48, 255)
arrow = (180, 185, 195, 255)
text_c = (210, 214, 220, 255)

out = Path(__file__).resolve().parent.parent / "build" / "dmg-resources" / "background.png"
out.parent.mkdir(parents=True, exist_ok=True)

img = Image.new("RGBA", (W, H), bg)
draw = ImageDraw.Draw(img)

# Horizontal arrow between app (left) and Applications (right)
cx, cy = W // 2, 168
shaft_y0, shaft_y1 = cy - 6, cy + 6
draw.rounded_rectangle([cx - 70, shaft_y0, cx + 40, shaft_y1], radius=4, fill=arrow)
# Arrow head pointing right
draw.polygon(
    [(cx + 38, cy - 22), (cx + 78, cy), (cx + 38, cy + 22)],
    fill=arrow,
)

# Label under arrow
try:
    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 22)
except OSError:
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
    except OSError:
        font = ImageFont.load_default()

label = "Drag here"
bbox = draw.textbbox((0, 0), label, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
draw.text(((W - tw) // 2, cy + 36), label, fill=text_c, font=font)

img.save(out)
print(out)
