# The Gilded knight as line art, for the photo-reading screen (KnightLoadingView.swift): the side
# silhouette of the black-and-gold knight (gilded-pieces.bin), the outline of its gold mane stripes,
# trim and poll knob, its almond eye, the base's tier lines and a round nostril.
# Prints Swift literals in a 78 x 96 box (x 4...82, y 6...102, y down, muzzle right).
# Usage: python scripts/sculpted/knight_outline.py   (needs numpy scipy scikit-image pillow)
import struct, zlib, numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.ndimage import gaussian_filter1d
from skimage import measure

BIN = 'ChessGameKiller/Assets.xcassets/Sculpted/gilded-pieces.dataset/gilded-pieces.bin'


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
S, X0, Y0 = 1500, -0.4, -0.02
W, H = int(0.84 * S), int(0.96 * S)


def raster(parts, front=False, ymin=-1.0):
    """The parts seen from the side, filled; `front` keeps only the faces toward the viewer."""
    img = Image.new('L', (W, H), 0)
    draw = ImageDraw.Draw(img)
    for _, P, I in parts:
        T = P[I]
        if front:
            n = np.cross(T[:, 1] - T[:, 0], T[:, 2] - T[:, 0])
            T = T[(n[:, 2] > 0) & (T[:, :, 1].min(1) > ymin)]
        for t in T:
            draw.polygon([((q[0] - X0) * S, H - (q[1] - Y0) * S) for q in t], fill=255)
    return ndimage.binary_fill_holes(np.array(img) > 0)


def contours(mask, minlen=40, tol=0.0012, smooth=1.2):
    out = []
    for c in measure.find_contours(mask.astype(float), 0.5):
        if len(c) < minlen:
            continue
        o = np.array([(x / S + X0, (H - y) / S + Y0) for y, x in c])
        seg = np.r_[0, np.cumsum(np.linalg.norm(np.diff(o, axis=0), axis=1))]
        t = np.linspace(0, seg[-1], max(int(seg[-1] * 600), 30))
        x = gaussian_filter1d(np.interp(t, seg, o[:, 0]), smooth, mode='wrap')
        y = gaussian_filter1d(np.interp(t, seg, o[:, 1]), smooth, mode='wrap')
        out.append(measure.approximate_polygon(np.c_[x, y], tol)[:-1])
    return out


rim = max(contours(raster(knight), smooth=1.5, tol=0.0006), key=len)
rim = np.roll(rim, -int(np.argmax(rim[:, 1])), axis=0)  # the trace sets off from the top
gold = ndimage.binary_opening(raster([p for p in knight if p[0] == 1], front=True, ymin=0.2), iterations=2)
details = contours(gold, minlen=30, smooth=1.0) + contours(raster([p for p in knight if p[0] == 2], front=True), minlen=10, smooth=0.8)


def box(X, Y):
    return round(float(X) * 100 + 40, 2), round((1 - float(Y)) * 100, 2)


def span(level):
    xs = [x1 + (level - y1) * (x2 - x1) / (y2 - y1)
          for (x1, y1), (x2, y2) in zip(rim, np.roll(rim, -1, axis=0)) if (y1 - level) * (y2 - level) < 0]
    return min(xs) + 0.012, max(xs) - 0.012


lit = lambda p: f'CGPoint(x: {p[0]}, y: {p[1]})'


def points(name, pts, indent='    '):
    print(f'{indent}{name}[')
    for i in range(0, len(pts), 4):
        print(indent + '    ' + ', '.join(lit(box(*p)) for p in pts[i:i + 4]) + ',')
    print(f'{indent}]' + (',' if indent != '' else ''))


points('static let rim: [CGPoint] = ', rim, '')
print('/// The gold mane stripes, trim and knob, and the eye: closed shapes.')
print('static let details: [[CGPoint]] = [')
for c in details:
    points('', c)
print(']')
print('static let tiers: [(CGPoint, CGPoint)] = [')
for level in (0.055, 0.079, 0.107, 0.131):
    a, b = span(level)
    print(f'    ({lit(box(a, level))}, {lit(box(b, level))}),')
print(']')
print(f'static let nostril = {lit(box(0.355, 0.385))}')
