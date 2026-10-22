# A classic Staunton knight head, carved from a side profile: a smooth closed outline (arched
# neck, ears, forehead, long tapering muzzle, round jaw, chest) is extruded with a pillowed,
# rounded cross-section whose thickness tapers from neck to muzzle, then given a few shallow
# carvings: round cheek, eye and brow, nostril, mouth line, mane strands and split ears.
# Units as the rest of the set before the knight's 0.84 scale: base top at z=0.17, muzzle toward -x.
# Writes kv.npy / kf.npy (vertices, faces) for pieces.knight.  Usage: knight_profile.py outdir [res]
import sys, numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from skimage import measure

OUT = sys.argv[1] if len(sys.argv) > 1 else 'scripts/sculpted'
RES = float(sys.argv[2]) if len(sys.argv) > 2 else 0.003

# The outline, counterclockwise from the front of the base: chest, throat, jaw, muzzle, face,
# forehead, ears, poll, mane, back of the neck.
OUTLINE = [
    (-0.160, 0.170), (-0.172, 0.235), (-0.165, 0.315), (-0.140, 0.385), (-0.112, 0.440),
    (-0.118, 0.478), (-0.175, 0.468), (-0.250, 0.450), (-0.310, 0.452), (-0.345, 0.472),
    (-0.360, 0.508), (-0.356, 0.552), (-0.330, 0.585), (-0.262, 0.630), (-0.170, 0.705),
    (-0.100, 0.775), (-0.062, 0.828), (-0.040, 0.868), (-0.018, 0.948), (0.012, 0.935),
    (0.040, 0.880), (0.068, 0.838), (0.112, 0.780), (0.158, 0.690), (0.192, 0.585),
    (0.210, 0.470), (0.216, 0.350), (0.212, 0.250), (0.202, 0.170),
]


def spline(points, per=24):
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


def signed_distance_2d(curve, x0, z0, x1, z1, step):
    """Signed distance to the outline (negative inside) on a fine raster."""
    w = int(np.ceil((x1 - x0) / step)) + 1
    h = int(np.ceil((z1 - z0) / step)) + 1
    img = Image.new('L', (w, h), 0)
    pts = [((x - x0) / step, (z - z0) / step) for x, z in curve]
    ImageDraw.Draw(img).polygon(pts, fill=255)
    inside = np.asarray(img) > 127                       # [z, x]
    d_out = ndimage.distance_transform_edt(~inside) * step
    d_in = ndimage.distance_transform_edt(inside) * step
    # Smoothed, so the carved surfaces come out without terraces from the raster.
    return ndimage.gaussian_filter((d_out - d_in).T, 2.0), (x0, z0, step)   # [x, z]


def sample(field, meta, X, Z):
    x0, z0, step = meta
    return ndimage.map_coordinates(field, [(X - x0) / step, (Z - z0) / step], order=1, mode='nearest')


def smooth01(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def bump(X, Z, cx, cz, rx, rz):
    """1 at the center, easing to 0 at the ellipse's edge."""
    r = np.sqrt(((X - cx) / rx) ** 2 + ((Z - cz) / rz) ** 2)
    return smooth01(1 - r)


def segment_bump(X, Z, a, b, r):
    ax, az = a; bx, bz = b
    vx, vz = bx - ax, bz - az
    t = np.clip(((X - ax) * vx + (Z - az) * vz) / (vx * vx + vz * vz), 0, 1)
    d = np.sqrt((X - ax - t * vx) ** 2 + (Z - az - t * vz) ** 2)
    return smooth01(1 - d / r)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def build(res=RES):
    curve = spline(OUTLINE)
    d2f, meta = signed_distance_2d(curve, -0.45, 0.10, 0.32, 1.02, 0.0015)

    xs = np.arange(-0.40, 0.27, res); ys = np.arange(-0.20, 0.20, res); zs = np.arange(0.14, 0.99, res)
    X2, Z2 = np.meshgrid(xs, zs, indexing='ij')           # the side view, [x, z]
    d2 = sample(d2f, meta, X2, Z2)

    # Half thickness: full at the neck, narrowing up the neck and along the head to the muzzle.
    neck = np.interp(Z2, [0.17, 0.30, 0.55, 0.80, 0.95], [0.150, 0.132, 0.118, 0.104, 0.080])
    head = smooth01((Z2 - 0.36) / 0.24) * smooth01((0.04 - X2) / 0.16)   # 0 on the neck, 1 on the face
    taper = np.interp(X2, [-0.36, -0.25, -0.12, 0.0], [0.66, 0.74, 0.92, 1.0])
    w = neck * (1 - head) + 0.104 * taper * head
    # Ears: thinner than the forehead.
    ears = smooth01((Z2 - 0.83) / 0.05) * smooth01((X2 + 0.07) / 0.03)
    w = w * (1 - ears) + 0.072 * ears

    # Carvings, as changes to the thickness of each side.
    cheek = np.sqrt(((X2 + 0.055) / 0.088) ** 2 + ((Z2 - 0.585) / 0.082) ** 2)
    w += 0.016 * smooth01(1 - cheek)                                  # round cheek
    w += 0.006 * bump(X2, Z2, -0.090, 0.770, 0.045, 0.016)            # brow over the eye
    w -= 0.020 * bump(X2, Z2, -0.108, 0.738, 0.028, 0.018)            # eye socket
    w += 0.009 * bump(X2, Z2, -0.111, 0.737, 0.012, 0.009)            # the eye itself
    w -= 0.012 * bump(X2, Z2, -0.330, 0.535, 0.018, 0.016)            # nostril
    w -= 0.007 * segment_bump(X2, Z2, (-0.356, 0.490), (-0.270, 0.484), 0.006)   # mouth line
    # Mane: a raised band along the back of the neck, cut with strands that sweep down and back.
    back = smooth01((X2 - 0.03) / 0.05) * smooth01((Z2 - 0.28) / 0.06) * (1 - smooth01((Z2 - 0.86) / 0.04))
    band = back * smooth01((0.055 + d2) / 0.03)                       # near the outline only
    w += 0.014 * band
    strands = 0.5 + 0.5 * np.cos((Z2 * 0.85 + X2 * 0.55) * 2 * np.pi * 11)
    w -= 0.006 * band * strands ** 2

    # Pillowed: full in the middle of the shape, easing thinner toward its outline.
    w *= 0.58 + 0.42 * np.sqrt(smooth01(-d2 / 0.075))
    w = ndimage.gaussian_filter(w, 1.2)

    X, Y, Z = np.meshgrid(xs, ys, zs, indexing='ij')
    # The strands also cut across the rounded back edge, so they show from behind and in outline.
    D2 = (d2 + 0.014 * band * strands ** 3)[:, None, :]
    W = w[:, None, :]
    r = 0.028
    qx = D2 + r
    qy = np.abs(Y) - W + r
    d = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - r

    # Split the ears with a narrow gap.
    gap = 0.013 * smooth01((Z - 0.86) / 0.03) * smooth01((X + 0.05) / 0.03)
    d = smax(d, gap - np.abs(Y), 0.006)

    # Flare into the base, and a flat bottom.
    collar = np.maximum(np.sqrt(X ** 2 + Y ** 2) - 0.172, np.abs(Z - 0.19) - 0.025)
    d = smin(d, collar, 0.045)
    d = np.maximum(d, 0.17 - Z)

    v, f, _, _ = measure.marching_cubes(d.astype(np.float32), 0.0, spacing=(res, res, res))
    v += np.array([xs[0], ys[0], zs[0]])
    return taubin(v, f), f


def taubin(v, f, rounds=12, lam=0.5, mu=-0.53):
    """Smooths away the grid's faint steps without shrinking the shape; the flat bottom stays put."""
    n = len(v)
    e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    deg = np.bincount(e[:, 0], minlength=n).astype(np.float64)
    fixed = v[:, 2] < 0.171
    v = v.astype(np.float64)
    for _ in range(rounds):
        for k in (lam, mu):
            acc = np.zeros_like(v)
            np.add.at(acc, e[:, 0], v[e[:, 1]])
            step = acc / np.maximum(deg, 1)[:, None] - v
            step[fixed] = 0
            v = v + k * step
    return v


if __name__ == '__main__':
    import time
    t = time.time()
    v, f = build()
    print(len(v), 'vertices', len(f), 'faces', round(time.time() - t, 1), 's')
    np.save(f'{OUT}/kv.npy', v)
    np.save(f'{OUT}/kf.npy', f)
