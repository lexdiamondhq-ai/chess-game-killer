# Stone squares for the app, drawn as two continuous slabs (one per color) so every square shows
# a different part of the stone: soft clouding, a few long fine veins, a hairline groove between squares.
# Albedo only, 2048 px, rank 8 at the top, a1 dark. Usage: marble.py spec.json out.png [size]
import sys, json, numpy as np
from PIL import Image
spec = json.load(open(sys.argv[1])); out = sys.argv[2]; N = int(sys.argv[3]) if len(sys.argv) > 3 else 2048
def hexc(h): return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255
def to_lin(c): return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def to_srgb(c): c = np.clip(c, 0, 1); return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)
def noise(seed, cells, size):
    """Smooth value noise: a random grid of `cells`, upsampled with bicubic filtering."""
    rng = np.random.default_rng(seed)
    g = rng.random((cells + 3, cells + 3)).astype(np.float32)
    im = Image.fromarray(g, mode='F').resize((size * (cells + 3) // cells,) * 2, Image.BICUBIC)
    a = np.asarray(im)
    o = size * 3 // (2 * cells)
    return a[o:o + size, o:o + size]
def fbm(seed, size, base=3, octaves=5):
    total = np.zeros((size, size), np.float32); amp = 1.0; norm = 0
    for i in range(octaves):
        total += amp * noise(seed + i * 101, base * 2 ** i, size); norm += amp; amp *= 0.5
    return total / norm
def slab(s, seed):
    y, x = np.mgrid[0:N, 0:N].astype(np.float32) / N * 8  # board units
    a = np.radians(s.get('angle', 32))
    turb = fbm(seed, N, base=2, octaves=6) - 0.5
    col = np.broadcast_to(to_lin(hexc(s['base'])), (N, N, 3)).copy()
    # clouding: broad, gentle changes of tone
    cloud = fbm(seed + 7, N, base=3, octaves=6) - 0.5
    col *= (1 + s.get('cloud', 0.12) * cloud)[..., None]
    grain = noise(seed + 13, 512, N) - 0.5
    col *= (1 + 0.025 * grain)[..., None]
    # veins: where a warped sine crosses zero, soft-edged; a main family and a finer one
    for fam, (freq, warp, width, strength, colour) in enumerate(s['veins']):
        u = (x * np.cos(a + fam * 0.6) + y * np.sin(a + fam * 0.6)) * freq + warp * turb * (1 + fam)
        d = np.abs(np.sin(u * np.pi))
        # vary the vein along its length so it fades in and out like real stone
        fade = np.clip((fbm(seed + 31 + fam, N, base=3, octaves=3) - 0.36) * 3.0, 0, 1)
        if s.get('crisp'):
            # even, sharp-edged veins: divide by the slope of u so the line keeps its width where the
            # warp stretches it (no smudges), a hard core with a pixel of anti-aliasing and a faint halo
            gy, gx = np.gradient(u, 8 / N)
            dist = d / (np.pi * np.hypot(gx, gy) + 1e-6)
            w = width * (0.75 + 0.5 * fbm(seed + 47 + fam, N, base=4, octaves=3))
            aa = 1.2 * 8 / N
            core = np.clip((w - dist) / aa + 0.5, 0, 1)
            m = (core + 0.12 * np.exp(-(dist / (w * 3.5)) ** 2) * (1 - core)) * fade * strength
        else:
            m = np.exp(-(d / width) ** 2) * fade * strength
        col = col * (1 - m[..., None]) + to_lin(hexc(colour)) * m[..., None]
    return col
light = slab(spec['light'], 11); dark = slab(spec['dark'], 23)
y, x = np.mgrid[0:N, 0:N]
f = (x * 8 // N); r = 7 - (y * 8 // N)  # top row is rank 8
is_light = ((f + r) % 2 == 1)[..., None]
img = np.where(is_light, light, dark)
# the groove: a hairline of the dark bed between squares, softened by a pixel
sq = N / 8; g = spec.get('groove_px', 3.0)
dx = np.minimum(x % sq, sq - (x % sq)); dy = np.minimum(y % sq, sq - (y % sq)); dmin = np.minimum(dx, dy)
edge = np.clip((dmin - g / 2) / 1.2, 0, 1)[..., None]
# the outer edge of the field gets no groove: the inlay line sits there
outer = (np.minimum(np.minimum(x, N - 1 - x), np.minimum(y, N - 1 - y)) < g)[..., None]
edge = np.where(outer, 1.0, edge)
bed = to_lin(hexc(spec.get('bed', '0A0A0B')))
img = img * edge + bed * (1 - edge)
Image.fromarray((to_srgb(img) * 255 + 0.5).astype(np.uint8)).save(out)
print('ok', out)
