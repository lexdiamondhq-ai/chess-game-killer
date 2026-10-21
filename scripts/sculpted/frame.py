# The flat board art: the baked stone squares inside a clean, even lacquer frame with a
# fine platinum line, so no light falls unevenly on the frame.
import sys, numpy as np
from PIL import Image, ImageDraw
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert('RGB')
N = im.size[0]; sq = N / 9; m = sq / 2
a = np.asarray(im).astype(np.float32)
lo, hi = int(round(m)), int(round(N - m))
# frame: a soft vertical gradient of near-black lacquer
yy = np.linspace(0, 1, N)[:, None]
top = np.array([0x1A, 0x1A, 0x1D], np.float32); bot = np.array([0x0E, 0x0E, 0x10], np.float32)
frame = (top * (1 - yy[..., None]) + bot * yy[..., None]) * np.ones((N, N, 1), np.float32)
out = frame.copy()
out[lo:hi, lo:hi] = a[lo:hi, lo:hi]
img = Image.fromarray(out.clip(0, 255).astype(np.uint8))
d = ImageDraw.Draw(img, 'RGBA')
# a fine platinum line a little outside the squares, and a dark seam at the squares' edge
g = int(round(sq * 0.11))
d.rectangle([lo - g, lo - g, hi - 1 + g, hi - 1 + g], outline=(214, 218, 226, 120), width=2)
d.rectangle([lo - 1, lo - 1, hi, hi], outline=(0, 0, 0, 160), width=2)
img.save(dst, quality=90)
sqs = a[lo:hi, lo:hi]
k = (hi - lo) / 8
light, dark = [], []
for r in range(8):
    for f in range(8):
        cell = sqs[int(r * k + k * 0.15):int((r + 1) * k - k * 0.15), int(f * k + k * 0.15):int((f + 1) * k - k * 0.15)].reshape(-1, 3).mean(0)
        # row 0 is rank 8; a8 (f=0, rank 8) is light
        (light if (r + f) % 2 == 0 else dark).append(cell)
for name, v in (('light', light), ('dark', dark)):
    c = np.mean(v, 0); print(name, '#%02X%02X%02X' % tuple(int(x) for x in c))
