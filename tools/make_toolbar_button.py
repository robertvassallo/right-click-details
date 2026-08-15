#!/usr/bin/env python3
"""Bake the whole toolbar button -- disc, ring and mouse glyph -- into one RGBA
texture.

WHY BAKED, rather than styled from the game's own assets like every other
button on that bar:

The engine's UI art (icons/game-menu/*, design/buttons/disk_*) is 8-bit
GREYSCALE -- PIL mode "L", TGA bpp 8 -- used as a coverage mask and tinted by
the stylesheet. That works when the mask is a `backgroundImage` on a Button.
It does NOT work as an ImageView's image: `color` only tints RGBA art there.
Mode-L art in an ImageView renders raw, which is why the disc came out light
grey -- and why the game's own bulldozer icon did too when dropped in as a test.

The alternative, putting the disc on the Button as a backgroundImage, tints
correctly but composites OVER the child glyph and dims it to slate.

So: do the tinting here, in Python, and hand the engine a finished RGBA image.
The disc SHAPES are still the game's own (disk_big_surface / disk_big_contour),
so the silhouette matches its neighbours exactly -- only the compositing moves.

Colours are game-menu.lua:154, the rule shared by ConstructionMenuIndicator,
LineManagerButton, VehicleManagerButton and BulldozerButton.

    python3 tools/make_toolbar_button.py
"""
import os
import zipfile

from PIL import Image

GAME_UI_ZIP = ("/mnt/DueceGigalow/SteamLibrary/steamapps/common/"
               "Transport Fever 2/res/textures/ui/ui.zip")

SIZE = 60                       # disk_big_* is 120 @2x -> 60px
FILL = (15, 35, 50, 255)        # backgroundColor2
RING = (255, 255, 255, 128)     # borderColor
GLYPH = (255, 255, 255, 255)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "res", "textures", "ui", "rlvcityoverlay")
GLYPH_SRC = os.path.join(OUT_DIR, "mouse_right.tga")


def mask(zf, name):
    """Load a greyscale asset from ui.zip as an alpha mask at SIZE."""
    with zf.open(name) as fh:
        im = Image.open(fh).convert("L")
    return im.resize((SIZE, SIZE), Image.LANCZOS)


def tinted(m, rgba):
    layer = Image.new("RGBA", (SIZE, SIZE), rgba[:3] + (0,))
    # Scale the mask by the colour's alpha so RING stays translucent.
    a = m.point(lambda p: int(p * rgba[3] / 255))
    layer.putalpha(a)
    return layer


with zipfile.ZipFile(GAME_UI_ZIP) as zf:
    surface = mask(zf, "design/buttons/disk_big_surface@2x.tga")
    contour = mask(zf, "design/buttons/disk_big_contour@2x.tga")

out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
out.alpha_composite(tinted(surface, FILL))
out.alpha_composite(tinted(contour, RING))

# The glyph: our generated mouse, already RGBA white-on-transparent with its
# margin baked in. Composite it centred at the same size.
g = Image.open(GLYPH_SRC).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
out.alpha_composite(g)

dst = os.path.join(OUT_DIR, "toolbar_button.tga")
out.save(os.path.normpath(dst))
chk = Image.open(os.path.normpath(dst))
print(f"wrote {os.path.normpath(dst)}  {chk.size[0]}x{chk.size[1]}  mode={chk.mode}")
