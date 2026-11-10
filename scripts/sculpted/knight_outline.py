# The board knight as line art, for the photo-reading screen (KnightLoadingView.swift): the
# side silhouette of the stone knight the app draws on the board (sculpted-pieces.bin), its
# mane beads and eye taken from the gold and gem parts, plus the base's tier lines, mouth and
# nostril. Prints Swift literals in a 80 x 96 box (x 0...80, y 6...102, y down, muzzle left).
# Usage: python scripts/sculpted/knight_outline.py   (needs numpy scipy scikit-image pillow)
import struct, zlib, numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.ndimage import gaussian_filter1d
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from skimage import measure

BIN = 'ChessGameKiller/Assets.xcassets/Sculpted/sculpted-pieces.dataset/sculpted-pieces.bin'


def load(path):
    """Reads the export the way SculptedAssets.loadMeshes does."""
    d = zlib.decompress(open(path, 'rb').read(), -15)
    assert d[:4] == b'SCLP'
    n = struct.unpack_from('<I', d, 8)[0]
    o, out = 12, {}
    for _ in range(n):
        letter, count = chr(d[o]), d[o + 1]
        o += 4
        parts = []
        for _ in range(count):
            finish = d[o]
            o += 4
            vc, ic = struct.unpack_from('<II', d, o)
            o += 8
            P = np.frombuffer(d, '<f4', vc * 3, o).reshape(-1, 3); o += vc * 12
            o += vc * 12  # normals
            I = np.frombuffer(d, '<u4', ic, o).reshape(-1, 3); o += ic * 4
            parts.append((finish, P, I))
        out[letter] = parts
    return out


knight = load(BIN)['N']
S, X0, Y0 = 2000, -0.4, -0.02
W, H = int(0.8 * S), int(1.0 * S)
img = Image.new('L', (W, H), 0)
draw = ImageDraw.Draw(img)
for _, P, I in knight:
    for t in P[I]:
        draw.polygon([((q[0] - X0) * S, H - (q[1] - Y0) * S) for q in t], fill=255)
mask = ndimage.binary_fill_holes(np.array(img) > 0)
c = max(measure.find_contours(mask.astype(float), 0.5), key=len)
o = np.array([(x / S + X0, (H - y) / S + Y0) for y, x in c])
seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(o, axis=0), axis=1))]
t = np.linspace(0, seg[-1], 600)
x = gaussian_filter1d(np.interp(t, seg, o[:, 0]), 1.2, mode='wrap')
y = gaussian_filter1d(np.interp(t, seg, o[:, 1]), 1.2, mode='wrap')
pts = measure.approximate_polygon(np.c_[x, y], 0.0012)[:-1]
# Start the trace at the ear tip, so the spark sets off from the top.
pts = np.roll(pts, -int(np.argmax(pts[:, 1])), axis=0)


def box(X, Y):
    return round(float(X) * 100 + 40, 2), round((1 - float(Y)) * 100, 2)


def span(level):
    xs = [x1 + (level - y1) * (x2 - x1) / (y2 - y1)
          for (x1, y1), (x2, y2) in zip(pts, np.roll(pts, -1, axis=0)) if (y1 - level) * (y2 - level) < 0]
    return min(xs) + 0.012, max(xs) - 0.012


beads = []
for finish, P, I in knight:
    if finish == 2:
        eye = P.mean(0)
    if finish == 1:
        r = np.r_[I[:, 0], I[:, 1], I[:, 2]]; k = np.r_[I[:, 1], I[:, 2], I[:, 0]]
        n, lab = connected_components(coo_matrix((np.ones(len(r)), (r, k)), shape=(len(P), len(P))))
        for i in range(n):
            q = P[lab == i]
            if q[:, 1].mean() > 0.3 and q[:, 2].mean() > 0:
                beads.append(q.mean(0))
beads.sort(key=lambda p: -p[1])

lit = lambda p: f'CGPoint(x: {p[0]}, y: {p[1]})'
print('static let rim: [CGPoint] = [')
for i in range(0, len(pts), 4):
    print('    ' + ', '.join(lit(box(*p)) for p in pts[i:i + 4]) + ',')
print(']')
print('static let tiers: [(CGPoint, CGPoint)] = [')
for level in (0.058, 0.128, 0.149):
    a, b = span(level)
    print(f'    ({lit(box(a, level))}, {lit(box(b, level))}),')
print(']')
print(f'static let eye = {lit(box(eye[0], eye[1]))}')
print('static let beads: [CGPoint] = [')
print('    ' + ', '.join(lit(box(p[0], p[1])) for p in beads) + ',')
print(']')
