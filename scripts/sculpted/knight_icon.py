# The gilded knight: the stylized horse head of a black-and-gold knight artwork (an icon
# design), with its gold-striped mane (a fan
# of stripes, a trim down the back of the neck and a band from the poll to the throat), an
# almond amber eye under a brow, and a flared nostril.
#
# Carved from the artwork's side outline: the outline is extruded with a rounded, softly
# chamfered cross-section that is full at the neck and narrows along the face; the gold is a
# thin shell over the stone wherever the artwork's pattern lies, and the eye a lens in its socket.
# Units are squares: the neck stands on the round foot of the base at z = 0.118, muzzle toward -x.
#
# Writes kv/kf (stone), gv/gf (gold) and ev/ef (eyes) as .npy for pieces.  Usage:
#   knight_icon.py outdir [res]
import sys, os, numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from skimage import measure

OUT = sys.argv[1] if len(sys.argv) > 1 else 'build/sculpted/icon'
RES = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0028

# Icon pixels to squares: the ear tip (y 45) is 0.8 above the floor, the neck's foot (y 884)
# stands on the base's round foot at 0.118.
FOOT = 0.118
S = (0.8 - FOOT) / (884 - 45)
CX = 470


def to_units(x, y):
    return -(np.asarray(x, float) - CX) * S, FOOT + (884 - np.asarray(y, float)) * S


def to_px(X, Z):
    return CX - np.asarray(X) / S, 884 - (np.asarray(Z) - FOOT) / S


# The outline in icon pixels, facing right: up the back of the neck to the poll, the ear,
# the forehead and nose, the muzzle, the open mouth, the jaw, the throat and the front of
# the neck. It runs below the foot so the cut there is clean.
OUTLINE = [
    (205, 905), (205, 884), (180, 858), (158, 815), (138, 740), (125, 635), (127, 545), (138, 455), (159, 370), (191, 293), (236, 228), (291, 178),
    (356, 140), (430, 115), (505, 104), (560, 101),
    (620, 108), (652, 110),
    (683, 88), (710, 64), (731, 45),
    (730, 78), (724, 115), (711, 152), (691, 182),
    (699, 206), (723, 252), (754, 307), (789, 372), (823, 437), (853, 497), (879, 541), (897, 573), (906, 606),
    (903, 641), (892, 672), (877, 695),
    (848, 686), (812, 666), (779, 640), (752, 614),
    (767, 636), (791, 661), (812, 683), (821, 697),
    (797, 699), (767, 684), (743, 654),
    (713, 618), (676, 583), (632, 552), (583, 533), (537, 524), (506, 522),
    (512, 562), (535, 622), (570, 690), (615, 750), (665, 800), (706, 836), (726, 860),
    (732, 884), (732, 905),
]
BACK = OUTLINE[1:16]          # the back of the neck, foot to poll: where the gold trim runs

# The gold, after the icon: a band from the poll to the throat (A), two stripes that fan in to
# meet it there (B, C) and three that run back to the trim and end in a slanted cut (D, E, F).
# Each runs out past the back of the neck; the trim's edge cuts them clean.
STRIPES = [
    [(380, 60), (450, 60), (446, 200), (442, 280), (446, 350), (462, 420), (486, 470), (508, 505), (494, 524),
     (458, 480), (432, 420), (414, 350), (406, 280), (398, 200)],
    [(478, 504), (288, 137), (228, 213), (487, 516)],
    [(489, 518), (160, 281), (127, 337), (495, 526)],
    [(345, 545), (104, 416), (97, 488), (345, 551)],
    [(355, 625), (90, 588), (90, 657), (366, 652)],
    [(330, 730), (100, 730), (100, 778), (395, 778), (387, 760), (372, 745), (352, 733)],
]
TRIM = 14.0          # the trim's width along the back, in icon pixels
GROOVE = 2.5         # the dark line between the trim and the stripes
EYE = dict(back=(632, 292), front=(737, 349), height=21)      # almond: corners and half-height
NOSTRIL = (869, 598)
FINIAL = (595, 104)


def spline(points, per=12):
    """A closed Catmull-Rom curve through the points."""
    p = np.array(points, np.float64)
    n = len(p)
    out = []
    for i in range(n):
        p0, p1, p2, p3 = p[(i - 1) % n], p[i], p[(i + 1) % n], p[(i + 2) % n]
        for t in np.linspace(0, 1, per, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return np.array(out)


def open_spline(points, per=12):
    p = np.array(points, np.float64)
    p = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for t in np.linspace(0, 1, per, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(p[-2])
    return np.array(out)


K = 2                                   # raster: two samples per icon pixel
W_PX, H_PX = 1024 * K, 1024 * K


def raster(poly):
    img = Image.new('L', (W_PX, H_PX), 0)
    ImageDraw.Draw(img).polygon([(x * K, y * K) for x, y in poly], fill=255)
    return np.asarray(img) > 127                      # [y, x]


def sdf(inside):
    """Signed distance in icon pixels, negative inside."""
    return (ndimage.distance_transform_edt(~inside) - ndimage.distance_transform_edt(inside)) / K


def line_distance(curve):
    img = Image.new('L', (W_PX, H_PX), 255)
    ImageDraw.Draw(img).line([(x * K, y * K) for x, y in curve], fill=0, width=1)
    return ndimage.distance_transform_edt(np.asarray(img) > 127) / K


def gold_pattern(outline_inside):
    """The gold inside the outline: the trim along the back, then the stripes past a fine groove."""
    back = line_distance(open_spline(BACK))
    gold = np.zeros_like(outline_inside)
    for poly in STRIPES:
        gold |= raster(poly)
    gold &= back > TRIM + GROOVE
    gold |= back < TRIM
    # Past the outline too, so the shell over the edge of the neck is whole.
    return gold & ndimage.binary_dilation(outline_inside, iterations=12 * K)


def almond(X, Z):
    """Signed distance (squares, negative inside) to the eye's almond, roughly."""
    (bx, bz), (fx, fz) = [to_units(*p) for p in (EYE['back'], EYE['front'])]
    cx, cz = (bx + fx) / 2, (bz + fz) / 2
    ux, uz = fx - bx, fz - bz
    L = np.hypot(ux, uz) / 2
    ux, uz = ux / (2 * L), uz / (2 * L)
    s = (X - cx) * ux + (Z - cz) * uz                  # along the eye
    t = -(X - cx) * uz + (Z - cz) * ux                 # across
    h = EYE['height'] * S * (1 - (s / L) ** 2).clip(0)  # half-height at s
    return np.maximum(np.abs(t) - h, np.abs(s) - L) * 0.7, s / L, t


def smooth01(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def bump(X, Z, cx, cz, rx, rz):
    r = np.sqrt(((X - cx) / rx) ** 2 + ((Z - cz) / rz) ** 2)
    return smooth01(1 - r)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def sample(field_px, X, Z):
    px, py = to_px(X, Z)
    return ndimage.map_coordinates(field_px, [py * K, px * K], order=1, mode='nearest')


def build(res=RES, want=('k', 'g', 'e')):
    curve = spline(OUTLINE, 10)
    inside = raster(curve)
    d_out = ndimage.gaussian_filter(sdf(inside), 1.0 * K)          # icon px
    gold = gold_pattern(inside)
    d_gold = ndimage.gaussian_filter(sdf(gold), 0.6 * K)

    xs = np.arange(-0.40, 0.31, res); ys = np.arange(-0.24, 0.24 + res, res); zs = np.arange(FOOT - 0.012, 0.83, res)
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')
    d2 = sample(d_out, X2, Z2) * S                                   # squares
    g2 = sample(d_gold, X2, Z2) * S

    # Half thickness: a broad neck, narrowing up to the poll and along the face to the muzzle.
    neck = np.interp(Z2, [FOOT, 0.25, 0.45, 0.62, 0.78], [0.13, 0.124, 0.113, 0.1, 0.082])
    head = smooth01((Z2 - 0.40) / 0.16) * smooth01((-0.03 - X2) / 0.12)
    face = np.interp(X2, [-0.37, -0.31, -0.22, -0.12, 0.0], [0.054, 0.062, 0.079, 0.088, 0.09])
    w = neck * (1 - head) + face * head
    ex0, ez0 = to_units(650, 180); ex1, ez1 = to_units(731, 45)
    ears = smooth01((Z2 - (ez0 - 0.01)) / 0.03) * smooth01((X2 - ex1 + 0.01) / 0.02) * smooth01((ex0 + 0.03 - X2) / 0.03)
    w = w * (1 - ears) + 0.064 * ears

    # Carvings: a round cheek, a brow over the eye, the eye socket and the nostril's flare.
    cx, cz = to_units(615, 455)
    w += 0.013 * bump(X2, Z2, cx, cz, 0.075, 0.07)
    bx, bz = to_units(686, 286)
    w += 0.007 * bump(X2, Z2, bx, bz, 0.05, 0.017)
    eye_d, eye_s, _ = almond(X2, Z2)
    w -= 0.011 * smooth01(-eye_d / 0.006)
    nx, nz = to_units(*NOSTRIL)
    w += 0.006 * bump(X2, Z2, nx, nz, 0.034, 0.032)                   # the flare around it

    # Near the foot the neck rounds off front and back, so it stands inside the round foot.
    plan = np.sqrt(np.clip(0.242 ** 2 - X2 ** 2, 0, None))
    near = 1 - smooth01((Z2 - FOOT - 0.02) / 0.12)
    w = np.minimum(w, w * (1 - near) + np.maximum(plan, 0.06) * near)
    # Rounded and softly chamfered toward the outline, so the faces read as planes.
    w *= 0.62 + 0.38 * smooth01(-d2 / 0.05)
    w = ndimage.gaussian_filter(w, 0.8)

    X, Y, Z = (a.astype(np.float32) for a in np.meshgrid(xs, ys, zs, indexing='ij'))
    D2 = d2[:, None, :]
    W = w[:, None, :]
    # Crisp edges on the neck and mane, softer down the face.
    r = (0.022 + 0.008 * head)[:, None, :]
    qx = D2 + r
    qy = np.abs(Y) - W + r
    d = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - r
    del qx, qy

    # Split the ears.
    gap = 0.012 * smooth01((Z - (ez0 + 0.01)) / 0.03) * smooth01((X - ex1 + 0.01) / 0.02) * smooth01((ex0 + 0.02 - X) / 0.03)
    d = smax(d, gap - np.abs(Y), 0.005)
    # The nostril: a deep round hole on each side of the muzzle.
    wn = float(ndimage.map_coordinates(w, [[(nx - xs[0]) / res], [(nz - zs[0]) / res]], order=1)[0])
    for sgn in (-1, 1):
        hole = np.sqrt((X - nx) ** 2 + ((Y - sgn * (wn + 0.004)) / 1.15) ** 2 + (Z - nz) ** 2) - 0.02
        d = smax(d, -hole, 0.006)
    # Flare into a thin disc on the foot, then cut flat there.
    collar = np.maximum(np.sqrt(X ** 2 + Y ** 2) - 0.212, np.abs(Z - FOOT) - 0.01)
    d = smin(d, collar, 0.024)
    d = np.maximum(d, FOOT - Z)

    # Gold: a thin shell, just proud of the stone, wherever the pattern lies.
    G = np.maximum(np.maximum(d - 0.0028, -(d + 0.009)), g2[:, None, :])
    G = np.maximum(G, FOOT + 0.004 - Z)

    # The eye: a lens filling its socket, rising almost to the face around it.
    dome = smooth01(-eye_d / 0.008) * (0.0085 + 0.0025 * (1 - eye_s ** 2).clip(0))
    E = np.maximum(eye_d[:, None, :], np.maximum(np.abs(Y) - (w[:, None, :] + dome[:, None, :]), (w[:, None, :] - 0.006) - np.abs(Y)))

    out = {}
    for name, field, rounds in (('k', d, 12), ('g', G, 6), ('e', E, 6)):
        if name not in want:
            continue
        v, f, _, _ = measure.marching_cubes(field.astype(np.float32), 0.0, spacing=(res, res, res))
        if name == 'g':
            # The shell's underside lies inside the stone where nothing sees it: leave it out.
            depth = ndimage.map_coordinates(d, (v / res).T, order=1, mode='nearest')
            f = f[(depth[f] > -0.005).any(axis=1)]
            used = np.unique(f)
            remap = np.full(len(v), -1); remap[used] = np.arange(len(used))
            v, f = v[used], remap[f]
        v += np.array([xs[0], ys[0], zs[0]])
        out[name] = (taubin(v, f, rounds), f)
    return out


def taubin(v, f, rounds=12, lam=0.5, mu=-0.53):
    """Smooths away the grid's faint steps without shrinking the shape; the flat foot stays put."""
    n = len(v)
    e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    deg = np.bincount(e[:, 0], minlength=n).astype(np.float64)
    fixed = v[:, 2] < FOOT + 0.001
    v = v.astype(np.float64)
    for _ in range(rounds):
        for k in (lam, mu):
            acc = np.zeros_like(v)
            np.add.at(acc, e[:, 0], v[e[:, 1]])
            step = acc / np.maximum(deg, 1)[:, None] - v
            step[fixed] = 0
            v = v + k * step
    return v


def finial():
    """Where the gold finial stands on the poll, in squares."""
    return to_units(*FINIAL)


if __name__ == '__main__':
    import time
    t = time.time()
    os.makedirs(OUT, exist_ok=True)
    # The stone and the eyes at the working resolution; the gold finer, for clean stripe edges.
    parts = build(RES, ('k', 'e'))
    parts.update(build(RES * 0.72, ('g',)))
    for name, (v, f) in parts.items():
        print(name, len(v), 'vertices', len(f), 'faces')
        np.save(f'{OUT}/{name}v.npy', v)
        np.save(f'{OUT}/{name}f.npy', f)
    np.save(f'{OUT}/finial.npy', np.array(finial()))
    print('finial', finial(), round(time.time() - t, 1), 's')
