#!/usr/bin/env python3
"""Generate the debug-toggle icon: a ladybug.

The game ships no bug icon of any kind -- ui.zip has nothing under bug/beetle/
insect -- so this draws one, the same way make_mouse_icon.py draws the mouse.

White on transparent, matching the game's own HUD icons, which are
single-channel silhouettes the engine tints via the stylesheet. That is what
lets one texture serve both states: the stylesheet drops it to a dim grey when
debug logging is off and lifts it to red when on, with no second asset.

Because it is a silhouette, the spots and the wing seam are punched OUT rather
than drawn darker -- holes read as spots against any tint, whereas a second
colour would be flattened by the engine's tinting.

    python3 tools/make_ladybug_icon.py
"""
import os

from PIL import Image, ImageDraw

SIZE = 64          # matches mouse_right.tga and icons/game-menu/cargo@2x.tga
SS = 8             # supersample for clean curves

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "res", "textures", "ui",
                   "rlvcityoverlay", "ladybug.tga")

w = h = SIZE * SS
img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
d = ImageDraw.Draw(img)

WHITE = (255, 255, 255, 255)
CLEAR = (255, 255, 255, 0)

# Head: a small circle at the top, drawn first so the body overlaps it and the
# two read as one creature rather than a stack of discs.
head_r = int(w * 0.15)
head_cx, head_cy = w // 2, int(h * 0.19)
d.ellipse((head_cx - head_r, head_cy - head_r,
           head_cx + head_r, head_cy + head_r), fill=WHITE)

# Antennae -- short strokes angling out from the head. Without them the
# silhouette reads as a generic beetle; these are what make it a ladybug.
ant_len = int(w * 0.13)
ant_wid = max(2, int(w * 0.022))
for dx in (-1, 1):
    d.line((head_cx + dx * int(head_r * 0.55), head_cy - int(head_r * 0.55),
            head_cx + dx * (int(head_r * 0.55) + ant_len),
            head_cy - int(head_r * 0.55) - ant_len),
           fill=WHITE, width=ant_wid)

# Body: a near-circle, slightly taller than wide.
bx0, bx1 = int(w * 0.14), int(w * 0.86)
by0, by1 = int(h * 0.26), int(h * 0.94)
d.ellipse((bx0, by0, bx1, by1), fill=WHITE)

# Wing seam: a vertical slot down the middle, stopping short of the bottom so
# the body stays a single connected shape.
seam_w = max(3, int(w * 0.030))
d.rectangle((w // 2 - seam_w // 2, by0 + int(h * 0.02),
             w // 2 + seam_w // 2, by1 - int(h * 0.06)), fill=CLEAR)

# Spots: three per wing, punched out. Positions are fractions of the body box
# so they scale with any SIZE change.
body_w, body_h = bx1 - bx0, by1 - by0
spot_r = int(body_w * 0.115)
for fx, fy in ((0.26, 0.30), (0.26, 0.62), (0.36, 0.85)):
    for side in (0, 1):
        cx = bx0 + int(body_w * (fx if side == 0 else 1.0 - fx))
        cy = by0 + int(body_h * fy)
        d.ellipse((cx - spot_r, cy - spot_r, cx + spot_r, cy + spot_r),
                  fill=CLEAR)

# TWO BAKED RGBA VARIANTS -- not one greyscale mask.
#
# Same lesson as the toolbar button: the engine's own UI art is 8-bit greyscale
# used as a coverage mask, but `color` on an ImageView only tints RGBA. A mode
# "L" file in an ImageView renders RAW -- it comes out grey and does not respond
# to the stylesheet at all. So the on/off states cannot be a colour swap on one
# mask; they have to be two finished images.
#
# Off  dim slate, matching the panel's muted text
# On   ladybird red
small = img.resize((SIZE, SIZE), Image.LANCZOS)
alpha = small.split()[3]

for name, rgb in (("ladybug_off", (150, 165, 180)), ("ladybug_on", (220, 60, 50))):
    layer = Image.new("RGBA", (SIZE, SIZE), rgb + (0,))
    layer.putalpha(alpha if name == "ladybug_on"
                   else alpha.point(lambda p: int(p * 0.55)))
    dst = os.path.join(os.path.dirname(OUT), name + ".tga")
    layer.save(os.path.normpath(dst))
    chk = Image.open(os.path.normpath(dst))
    print(f"wrote {os.path.normpath(dst)}  {chk.size[0]}x{chk.size[1]}  mode={chk.mode}")
