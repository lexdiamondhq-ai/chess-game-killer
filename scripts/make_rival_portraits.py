#!/usr/bin/env python3
"""Draws the rivals' portraits: The Crowd as rings of gold dots (more players, more dots).

    python3 scripts/make_rival_portraits.py && python3 scripts/make_rival_glows.py

Needs Pillow and NumPy. Writes rival-NAME into the app's asset catalog (600 px JPEG) and the
widget's (120 px PNG). The glows come from these, through make_rival_glows.py.
"""
import json
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
APP = os.path.join(ROOT, "ChessGameKiller", "Assets.xcassets", "Rivals")
WIDGET = os.path.join(ROOT, "ChessGameKillerWidget", "Assets.xcassets", "Rivals")

SIZE = 600
GROUND = (10, 9, 8)
GOLD = (226, 190, 120)

# Dots per crowd: a few hundred real players stand behind each one.
CROWDS = {"1000s": 230, "1200s": 330, "1600s": 470, "2000s": 620, "masters": 820}


def crowd(name, count):
    rng = random.Random(name)
    image = Image.new("RGB", (SIZE, SIZE), GROUND)
    # A faint warm light in the middle, where the number sits in the app.
    halo = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(halo).ellipse((150, 150, 450, 450), fill=34)
    halo = halo.filter(ImageFilter.GaussianBlur(70))
    image = Image.composite(Image.new("RGB", (SIZE, SIZE), (70, 52, 26)), image, halo)
    dots = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(dots)
    for _ in range(count):
        angle = rng.random() * math.tau
        radius = 150 + (rng.random() ** 0.7) * 120
        x = SIZE / 2 + math.cos(angle) * radius
        y = SIZE / 2 + math.sin(angle) * radius * 0.94
        r = 2.2 + rng.random() * 2.6
        alpha = int(255 * (0.45 + 0.55 * rng.random()))
        draw.ellipse((x - r, y - r, x + r, y + r), fill=GOLD + (alpha,))
    glow = dots.filter(ImageFilter.GaussianBlur(5))
    image = image.convert("RGBA")
    image.alpha_composite(glow)
    image.alpha_composite(dots)
    return image.convert("RGB")



def write(folder, name, image, ext, contents):
    path = os.path.join(folder, f"rival-{name}.imageset")
    os.makedirs(path, exist_ok=True)
    if ext == "jpg":
        image.save(os.path.join(path, f"rival-{name}.jpg"), quality=88, optimize=True)
    else:
        image.save(os.path.join(path, f"rival-{name}.png"), optimize=True)
    with open(os.path.join(path, "Contents.json"), "w") as f:
        json.dump(contents(f"rival-{name}.{ext}"), f, indent=2)
        f.write("\n")


def main():
    portraits = {name: crowd(name, count) for name, count in CROWDS.items()}
    for name, image in portraits.items():
        write(APP, name, image, "jpg",
              lambda file: {"images": [{"filename": file, "idiom": "universal"}],
                            "info": {"author": "xcode", "version": 1}})
        write(WIDGET, name, image.resize((120, 120), Image.LANCZOS), "png",
              lambda file: {"images": [{"filename": file, "idiom": "universal", "scale": "3x"}],
                            "info": {"author": "xcode", "version": 1}})
    print("Wrote", len(portraits), "portraits")


if __name__ == "__main__":
    main()
