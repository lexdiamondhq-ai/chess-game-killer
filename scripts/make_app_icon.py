# Draws the app icon: the Neon board's backdrop with the gold knight glowing on it.
# Usage: python3 scripts/make_app_icon.py [out.png]
# Needs: pip install pillow cairosvg
import io, math, os, sys

import cairosvg
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KNIGHT = f"{ROOT}/ChessGameKiller/Assets.xcassets/Pieces/neon-wN.imageset/neon-wN.svg"
OUT = sys.argv[1] if len(sys.argv) > 1 else f"{ROOT}/ChessGameKiller/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZE = 1024


def hex_rgb(value):
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def radial_glow(size, color, center, radius, alpha):
    """A soft colored disc fading to clear, like NeonBackdrop's radial gradients."""
    layer = Image.new("RGBA", (size, size), color + (0,))
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    steps = 48
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = int(alpha * (1 - i / steps) ** 1.6 * 255)
        draw.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r], fill=a)
    layer.putalpha(mask)
    return layer


def backdrop(size):
    base = Image.new("RGBA", (size, size), hex_rgb(0x04050D) + (255,))
    base.alpha_composite(radial_glow(size, hex_rgb(0x14BEC8), (size * 0.0, size * 0.18), size * 1.05, 0.30))
    base.alpha_composite(radial_glow(size, hex_rgb(0xC83CD2), (size * 1.0, size * 0.80), size * 1.15, 0.30))
    # A faint board behind the knight, like the glass squares.
    board = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(board)
    cell = size / 8
    for row in range(8):
        for col in range(8):
            light = (row + col) % 2 == 1
            fill = (6, 7, 22, 70) if light else (6, 7, 22, 150)
            draw.rectangle([col * cell, row * cell, (col + 1) * cell, (row + 1) * cell], fill=fill)
            draw.rectangle([col * cell, row * cell, (col + 1) * cell, (row + 1) * cell], outline=(210, 250, 255, 38), width=2)
    base.alpha_composite(board)
    return base


def knight(size):
    scale = 0.72
    px = int(size * scale)
    png = cairosvg.svg2png(url=KNIGHT, output_width=px, output_height=px)
    piece = Image.open(io.BytesIO(png)).convert("RGBA")
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - px) // 2
    y = int(size * 0.14)
    # Gold halo: the piece's silhouette, tinted and blurred, like PieceImage's glow.
    silhouette = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tint = Image.new("RGBA", piece.size, hex_rgb(0xFFAA46) + (255,))
    tint.putalpha(piece.getchannel("A"))
    silhouette.paste(tint, (x, y), tint)
    halo = silhouette.filter(ImageFilter.GaussianBlur(size * 0.045))
    canvas.alpha_composite(halo)
    canvas.alpha_composite(halo)
    soft = silhouette.filter(ImageFilter.GaussianBlur(size * 0.012))
    canvas.alpha_composite(soft)
    canvas.paste(piece, (x, y), piece)
    return canvas


def main():
    image = backdrop(SIZE)
    image.alpha_composite(knight(SIZE))
    # App icons must be opaque.
    flat = Image.new("RGB", (SIZE, SIZE), hex_rgb(0x04050D))
    flat.paste(image, (0, 0), image)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    flat.save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
