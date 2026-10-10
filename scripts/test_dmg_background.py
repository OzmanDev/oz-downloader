#!/usr/bin/env python3
"""The installer art is sharp retina size, with a soft glow and a smooth arrow."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_dmg_background import H, POINTS_H, SCALE, W, render

img = render()
failures = []
if img.size != (W, H) or SCALE < 2:
    failures.append(f"1. installer art expected a retina image, got {img.size} at scale {SCALE}")

glow = [img.getpixel((x, 160))[2] for x in range(40, 420, 16)]
if glow[0] <= glow[-1]:
    failures.append(f"2. the blue glow should fade toward the middle, got {glow[0]} then {glow[-1]}")
for earlier, later in zip(glow, glow[1:]):
    if abs(earlier - later) > 28:
        failures.append(f"2. the blue glow has a hard step, {earlier} then {later}")
        break

top_right = img.getpixel((1180, 70))
middle = img.getpixel((640, 300))
if top_right[0] <= middle[0]:
    failures.append(f"3. the violet glow should tint the top corner, got {top_right} vs {middle}")

arrow = img.getpixel((640, 176 * SCALE))
if arrow[2] < 180 or arrow[0] > arrow[2]:
    failures.append(f"4. the arrow should read as blue, got {arrow}")

edge = [img.getpixel((640, y))[2] for y in range(176 * SCALE - 16, 176 * SCALE)]
if not any(35 < channel < 220 for channel in edge):
    failures.append(f"5. the arrow edge should be smoothed, got {edge}")
if any(later - earlier > 90 for earlier, later in zip(edge, edge[1:])):
    failures.append(f"5. the arrow edge jumps in one pixel, got {edge}")

# Icons are centered at y=180 and are 96 points tall. A name under them needs
# more room than the 4 points left below the icon.
if POINTS_H > 180 + 48 + 4:
    failures.append(f"6. the window should end at the icons so the names are outside, height {POINTS_H}")

if failures:
    print("\n".join(failures))
    sys.exit(1)
