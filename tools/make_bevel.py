#!/usr/bin/env python3
"""Regenerate the panel's beveled 9-slice background.

The engine has no corner-radius style property, so panel corners come from
artwork. This writes a white octagon with an alpha-cut chamfer; the stylesheet
tints it via backgroundColor1.

    python3 tools/make_bevel.py [bevel_px]

After changing BEVEL, update the 9-slice margins in
res/config/style_sheet/rlv_cityoverlay.lua to { 0, BEVEL+1, SIZE-BEVEL-1, SIZE }.
"""
import os
import sys

from PIL import Image, ImageDraw

SIZE = 32
BEVEL = int(sys.argv[1]) if len(sys.argv) > 1 else 9
SS = 8  # supersample, so the 45-degree edges downsample cleanly

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "res", "textures", "ui",
                   "rlvcityoverlay", "panel_bevel.tga")

w = h = SIZE * SS
b = BEVEL * SS

img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
ImageDraw.Draw(img).polygon(
    [(b, 0), (w - b, 0), (w - 1, b), (w - 1, h - b),
     (w - b, h - 1), (b, h - 1), (0, h - b), (0, b)],
    fill=(255, 255, 255, 255),
)
img.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.normpath(OUT))

print(f"wrote {os.path.normpath(OUT)}  {SIZE}x{SIZE}, {BEVEL}px chamfer")
print(f"9-slice margins: {{ 0, {BEVEL + 1}, {SIZE - BEVEL - 1}, {SIZE} }}")
