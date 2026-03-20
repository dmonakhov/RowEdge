#!/usr/bin/env python3
"""Generate BMFont .fnt + .png for Connect IQ from a TTF file.

Usage: python3 gen_font.py <ttf_path> <pixel_size> <output_prefix>
Example: python3 gen_font.py RobotoCondensed-Bold.ttf 60 big_numbers
Outputs: big_numbers.fnt + big_numbers_0.png
"""

import sys
from PIL import Image, ImageFont, ImageDraw

CHARS = "0123456789:.-km "

def gen_bmfont(ttf_path, size, out_prefix):
    font = ImageFont.truetype(ttf_path, size)

    # Measure all glyphs
    glyphs = []
    for ch in CHARS:
        bbox = font.getbbox(ch)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        xoff = bbox[0]
        yoff = bbox[1]
        glyphs.append((ch, w, h, xoff, yoff))

    # Compute atlas dimensions
    padding = 2
    max_h = max(g[2] for g in glyphs) + padding * 2
    total_w = sum(g[1] + padding * 2 for g in glyphs)
    # Power of 2 width
    atlas_w = 1
    while atlas_w < total_w:
        atlas_w *= 2
    atlas_h = 1
    while atlas_h < max_h:
        atlas_h *= 2

    # Compute line height from font metrics
    ascent, descent = font.getmetrics()
    line_height = ascent + descent

    # Render atlas
    img = Image.new("L", (atlas_w, atlas_h), 0)
    draw = ImageDraw.Draw(img)

    x_cursor = 0
    fnt_chars = []
    for ch, w, h, xoff, yoff in glyphs:
        # Draw glyph
        draw.text((x_cursor + padding - xoff, padding - yoff), ch, font=font, fill=255)
        fnt_chars.append({
            "id": ord(ch),
            "x": x_cursor,
            "y": 0,
            "width": w + padding * 2,
            "height": max_h,
            "xoffset": -padding + xoff,
            "yoffset": -padding + yoff,
            "xadvance": w + padding,
        })
        x_cursor += w + padding * 2

    # Save PNG
    import os
    png_name = f"{out_prefix}_0.png"
    img.save(png_name)

    # Write BMFont text format .fnt
    fnt_name = f"{out_prefix}.fnt"
    png_basename = os.path.basename(png_name)
    with open(fnt_name, "w") as f:
        f.write(f'info face="CustomFont" size=-{size} bold=1 italic=0 '
                f'charset="" unicode=1 stretchH=100 smooth=1 aa=1 '
                f'padding=0,0,0,0 spacing=1,1 outline=0\n')
        f.write(f'common lineHeight={line_height} base={ascent} '
                f'scaleW={atlas_w} scaleH={atlas_h} pages=1 packed=0 '
                f'alphaChnl=1 redChnl=0 greenChnl=0 blueChnl=0\n')
        f.write(f'page id=0 file="{png_basename}"\n')
        f.write(f'chars count={len(fnt_chars)}\n')
        for c in fnt_chars:
            f.write(f'char id={c["id"]}   '
                    f'x={c["x"]}     y={c["y"]}     '
                    f'width={c["width"]}    height={c["height"]}     '
                    f'xoffset={c["xoffset"]}     yoffset={c["yoffset"]}    '
                    f'xadvance={c["xadvance"]}    page=0  chnl=15\n')

    print(f"Generated {fnt_name} ({len(fnt_chars)} chars) + {png_name} ({atlas_w}x{atlas_h})")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <ttf> <size> <output_prefix>")
        sys.exit(1)
    gen_bmfont(sys.argv[1], int(sys.argv[2]), sys.argv[3])
