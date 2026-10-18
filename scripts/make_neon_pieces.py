# Recolors the cburnett piece SVGs into the Neon set.
# Usage: python3 scripts/make_neon_pieces.py ChessGameKiller/Assets.xcassets/Pieces <out-dir>
import os, re, sys
SRC = sys.argv[1]; OUT = sys.argv[2]
# Neon palette
GOLD_BODY, GOLD_EDGE = "#FFD08A", "#5A2E00"
VIO_BODY, VIO_EDGE, VIO_DETAIL = "#2A1557", "#C59BFF", "#E6D3FF"
os.makedirs(OUT, exist_ok=True)
for n in ["K","Q","R","B","N","P"]:
    for c in "wb":
        s = open(f"{SRC}/{c}{n}.imageset/{c}{n}.svg").read()
        if c == "w":
            s = s.replace('fill="#fff"', f'fill="{GOLD_BODY}"').replace('stroke="#000"', f'stroke="{GOLD_EDGE}"').replace('fill="#000"', f'fill="{GOLD_EDGE}"')
            s = s.replace('<svg ', f'<svg fill="{GOLD_EDGE}" ', 1)
        else:
            s = s.replace('fill="#000"', f'fill="{VIO_BODY}"').replace('stroke="#000"', f'stroke="{VIO_EDGE}"')
            s = s.replace('stroke="#ececec"', f'stroke="{VIO_DETAIL}"').replace('fill="#ececec"', f'fill="{VIO_DETAIL}"')
            s = s.replace('<svg ', f'<svg fill="{VIO_BODY}" ', 1)
        open(f"{OUT}/neon-{c}{n}.svg", "w").write(s)
print("ok")
