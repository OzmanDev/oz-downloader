#!/usr/bin/env python3
"""The installer art is the theme colors, not a flat gray panel."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_dmg_background import H, W, render

img = render()
failures = []
if img.size != (W, H):
    failures.append(f"1. installer art expected {W} by {H}, got {img.size}")

left = img.getpixel((48, 48))
mid = img.getpixel((320, 200))
if left[2] <= mid[2]:
    failures.append(f"2. the blue glow should be stronger than the middle, got left {left} mid {mid}")

top_right = img.getpixel((600, 36))
if top_right[0] <= mid[0] or top_right[2] <= 40:
    failures.append(f"3. the violet glow should tint the top corner, got {top_right}")

arrow = img.getpixel((320, 176))
if arrow[2] < 180 or arrow[0] > arrow[2]:
    failures.append(f"4. the arrow should read as blue, got {arrow}")

if failures:
    print("\n".join(failures))
    sys.exit(1)
