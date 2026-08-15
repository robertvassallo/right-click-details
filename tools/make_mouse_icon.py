#!/usr/bin/env python3
"""Generate the toolbar icon: a mouse with its RIGHT button highlighted.

The game ships no mouse icon -- input_devices only covers console pads -- so
this draws one.

FORMAT MATTERS, and it is not what you would guess. Measured off the game's own
bar icons (icons/game-menu/bulldozer@2x.tga and friends):

    file            <name>@2x.tga, 120 x 120
    format          8-BIT GREYSCALE -- PIL mode "L", TGA header bpp 8
    field           0
    glyph           255, ~50 x 35 -- about 42% of the frame

Single channel, and the engine reads that channel as COVERAGE, then tints it
with `color` from the stylesheet. 0 is transparent: it is a mask, not a picture.
The disk behind it comes from backgroundImage1/2 + borderImage.

Note the "@2x": those 120px files are the HIGH-DPI variant and draw at 60. A
plain 120px file is treated as 1x and renders at double the size of every
neighbour, so both variants are emitted here.

Wrong turns taken getting here, recorded so they are not repeated:

  * 64x64 RGBA silhouette, glyph filling 66% of the frame -- wrong size and
    margin, never matched its neighbours however the stylesheet was tuned.
  * 120x120 RGBA with alpha 255 everywhere -- rendered as a black SQUARE over
    the disk. Came from inspecting the game's files with .convert("RGBA"),
    which fabricates an opaque alpha and hides that they are mode "L".
  * A brief revert back to RGBA, on the belief that mode "L" had been tried and
    failed. It had not: that build was never loaded, because stylesheets and
    textures only reload on a full game restart, not a save reload.

    python3 tools/make_mouse_icon.py
"""
import os

from PIL import Image, ImageDraw

SIZE = 64          # the size that demonstrably rendered a proper disc
SS = 8             # supersample for clean curves

# Fraction of the frame the glyph should occupy, measured off the bulldozer
# icon: 50/120. The mouse is portrait rather than landscape, so this is applied
# to its HEIGHT -- matching the largest dimension keeps the optical weight the
# same as its neighbours.
GLYPH_FRAC = 50.0 / 120.0

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "res", "textures", "ui",
                   "rlvcityoverlay", "mouse_right.tga")

# --- draw the mouse, oversized, on transparent -----------------------------
w = h = SIZE * SS
img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
d = ImageDraw.Draw(img)

# Body: rounded rectangle, slightly taller than wide.
pad_x, pad_y = int(w * 0.22), int(h * 0.10)
body = (pad_x, pad_y, w - pad_x, h - pad_y)
radius = int(w * 0.28)
d.rounded_rectangle(body, radius=radius, fill=(255, 255, 255, 255))

# Punch out the interior, leaving a stroke -- silhouette icons read better
# outlined at small sizes than as a solid blob.
inset = int(w * 0.055)
d.rounded_rectangle(
    (body[0] + inset, body[1] + inset, body[2] - inset, body[3] - inset),
    radius=radius - inset, fill=(255, 255, 255, 0),
)

# Divider between the two buttons, down to the waist.
mid_x = w // 2
waist = int(h * 0.42)
d.rectangle((mid_x - inset // 2, body[1] + inset, mid_x + inset // 2, waist),
            fill=(255, 255, 255, 255))
d.rectangle((body[0] + inset, waist - inset // 2, body[2] - inset, waist + inset // 2),
            fill=(255, 255, 255, 255))

# Fill the RIGHT button solid -- this is a right-click mod, so say so.
d.rounded_rectangle(
    (mid_x + inset // 2, body[1] + inset, body[2] - inset, waist - inset // 2),
    radius=inset, fill=(255, 255, 255, 255),
)

# Crop to the glyph, scale it to the same fraction of the frame the game's own
# bar glyphs use, and centre it. RGBA -- NOT mode "L".
#
# Two things this deliberately does NOT do:
#   * no mode "L". A faithful copy of the engine's single-channel mask format
#     was tried at length and the disc rendered grey -- the background tints do
#     not apply to an ImageView carrying an L-format image.
#   * no stylesheet padding to fake the inset. Padding interacts with `size` in
#     ways that made the button the wrong dimensions; baking the margin into the
#     texture means the stylesheet sets `size` only.
#
# GLYPH_FRAC is measured off icons/game-menu/bulldozer@2x.tga: its glyph is
# 50 of 120 px. The disc art (disk_big_*) is 120@2x = 60px, so at this fraction
# ours carries the same optical weight as its neighbours.
glyph = img.crop(img.split()[3].getbbox())
target_h = int(round(SIZE * GLYPH_FRAC))
scale = target_h / glyph.height
target_w = max(1, int(round(glyph.width * scale)))
glyph = glyph.resize((target_w, target_h), Image.LANCZOS)

tile = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
tile.alpha_composite(glyph, ((SIZE - target_w) // 2, (SIZE - target_h) // 2))
tile.save(os.path.normpath(OUT))

chk = Image.open(os.path.normpath(OUT))
print(f"wrote {os.path.normpath(OUT)}  {chk.size[0]}x{chk.size[1]}  mode={chk.mode} "
      f"(must be RGBA)  glyph {target_w}x{target_h}")
