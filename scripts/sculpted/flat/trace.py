"""Traces the cburnett pieces into polygons: each piece's outline and its inner detail lines, in
squares, image-up = +y (away from White). The Lock Screen's small board draws its pieces from them
(LiveGamePieces/flat-*.svg). Reads 1024-px height maps of play/public/pieces/b?.svg (outline white,
detail lines mid-grey) from GLYPH, writes glyphs.json:
{kind: {"outline": [[exterior, holes...], ...], "details": [[exterior, holes...], ...]}}."""
import json, sys, numpy as np
from PIL import Image
from shapely.geometry import LineString, Polygon, MultiPolygon, Point
from shapely.ops import polygonize, unary_union, linemerge

GLYPH = sys.argv[1] if len(sys.argv) > 1 else 'build/glyph'
PX = 0.78 / 800          # squares per pixel: the king, 807 px tall, comes out ~0.79 square

def contours(f, t):
    """Marching squares: the level-t contour of f as shapely polygons covering f > t."""
    f = np.pad(f.astype(np.float32), 1)
    H, W = f.shape
    a = f[:-1, :-1]; b = f[:-1, 1:]; c = f[1:, 1:]; d = f[1:, :-1]   # tl tr br bl
    idx = (a > t) * 1 + (b > t) * 2 + (c > t) * 4 + (d > t) * 8
    ys, xs = np.nonzero((idx > 0) & (idx < 15))
    def lerp(p, q):
        return np.clip((t - p) / np.where(q - p == 0, 1e-6, q - p), 0, 1)
    segs = []
    for y, x in zip(ys, xs):
        A, B, C, D = a[y, x], b[y, x], c[y, x], d[y, x]
        top = (x + lerp(A, B), y); right = (x + 1, y + lerp(B, C))
        bottom = (x + lerp(D, C), y + 1); left = (x, y + lerp(A, D))
        k = idx[y, x]
        table = {1: [(left, top)], 2: [(top, right)], 3: [(left, right)], 4: [(right, bottom)],
                 6: [(top, bottom)], 7: [(left, bottom)], 8: [(bottom, left)], 9: [(bottom, top)],
                 11: [(bottom, right)], 12: [(right, left)], 13: [(right, top)], 14: [(top, left)]}
        if k in (5, 10):
            center = (A + B + C + D) / 4 > t
            if k == 5:
                s = [(left, bottom), (right, top)] if center else [(left, top), (right, bottom)]
            else:
                s = [(top, left), (bottom, right)] if center else [(top, right), (bottom, left)]
        else:
            s = table[k]
        segs += s
    lines = linemerge([LineString(s) for s in segs])
    faces = list(polygonize(lines))
    keep = []
    for p in faces:
        q = p.representative_point()
        if f[int(q.y), int(q.x)] > t if 0 <= int(q.y) < H and 0 <= int(q.x) < W else False:
            keep.append(p)
    shape = unary_union(keep)
    # back to image pixels (the pad added one)
    from shapely import affinity
    return affinity.translate(shape, -1, -1)

def to_squares(shape, cx, cy):
    from shapely import affinity
    s = affinity.translate(shape, -cx, -cy)
    return affinity.scale(s, PX, -PX, origin=(0, 0))   # image down is -y

def rings(poly):
    return [list(map(list, poly.exterior.coords))] + [list(map(list, r.coords)) for r in poly.interiors]

def parts(shape):
    if shape.is_empty: return []
    return list(shape.geoms) if hasattr(shape, 'geoms') else [shape]

out = {}
for k in 'KQRBNP':
    h = np.asarray(Image.open(f'{GLYPH}/h{k}.png').convert('L')).astype(np.float32)
    sil = contours(h, 15).buffer(0)
    # the piece sits on its square's center: the middle of the 1024 picture
    cx = cy = 512
    outline = to_squares(sil, cx, cy).simplify(0.0006).buffer(0)
    # detail lines: the mid-grey strokes inside, away from the outline's soft edge
    inner = sil.buffer(-6)
    det = contours(np.where(h < 140, 255 - h, 0) * (h > 15), 255 - 140)   # pixels darker than 140 but inside
    det = det.intersection(inner).buffer(0)
    det = unary_union([p for p in parts(det) if p.area > 120])
    details = to_squares(det, cx, cy).simplify(0.0005).buffer(0)
    out[k] = {'outline': [rings(p) for p in parts(outline)],
              'details': [rings(p) for p in parts(details)]}
    b = outline.bounds
    print(k, 'outline parts', len(parts(outline)), 'bounds %.3f %.3f %.3f %.3f' % b,
          'pts', sum(len(r) for p in parts(outline) for r in rings(p)), 'details', len(parts(details)))
json.dump(out, open('scripts/sculpted/flat/glyphs.json', 'w'))
