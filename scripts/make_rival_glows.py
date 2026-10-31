#!/usr/bin/env python3
"""Turns each rival's portrait (a glowing object on black) into a glow with no backdrop, for
Someone at the Table: the orb that floats over the home's board, and the Live Activity's orb.

Brightness becomes coverage, so the glow lies over anything the way light does (much like a
screen blend), and it fades out toward a circle so the square's edges never show.

    python3 scripts/make_rival_glows.py

Needs Pillow and NumPy. Writes rival-NAME-glow into the app's and the widget's asset catalogs.
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
SOURCE = os.path.join(ROOT, "ChessGameKiller", "Assets.xcassets", "Rivals")
APP = SOURCE
WIDGET = os.path.join(ROOT, "ChessGameKillerWidget", "Assets.xcassets", "Rivals")
NAMES = ["spark", "drift", "pulse", "vector", "singularity"]


def glow(name, size):
    image = Image.open(os.path.join(SOURCE, f"rival-{name}.imageset", f"rival-{name}.jpg"))
    rgb = np.asarray(image.convert("RGB").resize((size, size), Image.LANCZOS)).astype(np.float64) / 255
    peak = rgb.max(axis=2)
    # The portraits' black is not quite black: lift it out, then brightness is coverage.
    floor = 0.06
    alpha = np.clip((peak - floor) / (1 - floor), 0, 1) ** 0.85
    # A soft circle: whole inside 60% of the radius, gone by 98%.
    yy, xx = np.mgrid[0:size, 0:size]
    radius = np.hypot(xx - (size - 1) / 2, yy - (size - 1) / 2) / (size / 2)
    ring = np.clip((0.98 - radius) / (0.98 - 0.6), 0, 1)
    alpha *= ring * ring * (3 - 2 * ring)
    # The light's own hue at full strength; how bright it is lives in the alpha.
    color = rgb / np.maximum(peak, 1e-4)[..., None]
    pixels = np.dstack([np.clip(color, 0, 1), alpha])
    return Image.fromarray((pixels * 255 + 0.5).astype(np.uint8), "RGBA")


def write(folder, name, image):
    os.makedirs(folder, exist_ok=True)
    image.save(os.path.join(folder, f"{name}.png"), optimize=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


def main():
    os.makedirs(WIDGET, exist_ok=True)
    with open(os.path.join(WIDGET, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    for name in NAMES:
        # The home draws it up to 66 points; the Live Activity at most 44, and Apple asks for
        # images there no bigger than they show.
        write(os.path.join(APP, f"rival-{name}-glow.imageset"), f"rival-{name}-glow", glow(name, 240))
        write(os.path.join(WIDGET, f"rival-{name}-glow.imageset"), f"rival-{name}-glow", glow(name, 132))
    print("Wrote", len(NAMES), "glows")


if __name__ == "__main__":
    main()
