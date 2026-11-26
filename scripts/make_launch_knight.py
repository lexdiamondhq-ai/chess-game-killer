"""Draws the launch screen's knight: the same line art as the loading mark
(BoardKnightLines in ChessGameKiller/Views/KnightLoadingView.swift), in the Light home's gold.

Run from the repository's root:
    python3 scripts/make_launch_knight.py ChessGameKiller/Assets.xcassets/Home/launch-knight.imageset
"""
import re, sys, os
from PIL import Image, ImageDraw

src = open('ChessGameKiller/Views/KnightLoadingView.swift').read()
block = src[src.index('enum BoardKnightLines'):src.index('static let box')]
pt = re.compile(r'CGPoint\(x: ([\d.]+), y: ([\d.]+)\)')
rim_text = block[block.index('static let rim'):block.index('static let details')]
rim = [(float(a), float(b)) for a, b in pt.findall(rim_text)]
details_text = block[block.index('static let details'):block.index('static let tiers')]
details = []
for chunk in re.split(r'\n        \[\n', details_text)[1:]:
    pts = [(float(a), float(b)) for a, b in pt.findall(chunk)]
    if pts: details.append(pts)
tiers_text = block[block.index('static let tiers'):block.index('static let nostril')]
tp = [(float(a), float(b)) for a, b in pt.findall(tiers_text)]
tiers = list(zip(tp[0::2], tp[1::2]))
nostril = (75.5, 61.5)
box = (4, 6, 78, 96)

GOLD = (168, 122, 46)      # 0xA87A2E, the Light home's metal
def render(height_px, out):
    ss = 4
    scale = height_px * ss / box[3]
    W = int(round(box[2] * scale)); H = int(round(box[3] * scale))
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def m(p): return ((p[0] - box[0]) * scale, (p[1] - box[1]) * scale)
    lw = max(1, int(round(1.15 * scale)))
    for shape in details:
        d.polygon([m(p) for p in shape], fill=GOLD + (235,))
    d.line([m(p) for p in rim] + [m(rim[0])], fill=GOLD + (255,), width=lw, joint='curve')
    for a, b in tiers:
        d.line([m(a), m(b)], fill=GOLD + (255,), width=max(1, int(round(0.8 * scale))))
    r = 2.2 * scale; c = m(nostril)
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], outline=GOLD + (255,), width=max(1, int(round(0.8 * scale))))
    im = im.resize((W // ss, H // ss), Image.LANCZOS)
    im.save(out)
    return im.size

outdir = sys.argv[1]
os.makedirs(outdir, exist_ok=True)
for name, h in (('launch-knight.png', 148), ('launch-knight@2x.png', 296), ('launch-knight@3x.png', 444)):
    print(name, render(h, os.path.join(outdir, name)))
print(len(rim), len(details), len(tiers))
