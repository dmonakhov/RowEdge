#!/usr/bin/env python3
"""Calculate optimal font sizes for each zoom level on a given screen.

Usage: python3 calc_fonts.py [width height]
Default: Edge 540 (246x322)
"""

import sys

W = int(sys.argv[1]) if len(sys.argv) > 1 else 246
H = int(sys.argv[2]) if len(sys.argv) > 2 else 322

LABEL_H = 12  # FONT_XTINY height
CHAR_RATIO = 0.55  # RobotoCondensed-Bold width/height ratio
MAX_CHARS = 5

def max_font_by_width(cell_w):
    return int(cell_w / (MAX_CHARS * CHAR_RATIO))

def max_font_by_height(cell_h):
    return cell_h - LABEL_H - 4

print(f"Screen: {W}x{H}, 5-char max, condensed bold ratio={CHAR_RATIO}")
print()
print(f"{'Zoom':>4} {'Cell':>10} {'WxH':>10} {'MaxW':>5} {'MaxH':>5} {'Font':>5}  Notes")
print("-" * 65)

layouts = [
    ("z1", "hero", W, H, "full-screen"),
    ("z2", "hero", W, H // 2, ""),
    ("z2", "row", W, H // 2, ""),
    ("z3", "hero", W, int(H * 0.4), "40%"),
    ("z3", "row", W, int(H * 0.3), "30%"),
]

for z, gridRows in [(4, 2), (5, 3), (6, 4), (7, 5)]:
    total_units = 2 + gridRows
    unit_h = H // total_units
    hero_h = unit_h * 2
    n = 1 + gridRows * 2
    hero_pct = hero_h * 100 // H
    grid_pct = unit_h * 100 // H
    layouts.append((f"z{z}", "hero", W, hero_h, f"{hero_pct}% ({n}f)"))
    layouts.append((f"z{z}", "grid", W // 2, unit_h, f"{grid_pct}%"))

for zoom, cell_type, cw, ch, note in layouts:
    mw = max_font_by_width(cw)
    mh = max_font_by_height(ch)
    recommended = min(mw, mh)
    print(f"{zoom:>4} {cell_type:>10} {cw:>4}x{ch:<4} {mw:>5} {mh:>5} {recommended:>5}  {note}")
