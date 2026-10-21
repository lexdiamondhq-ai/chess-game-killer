# The flat board art for a 3D look: its stone squares lit about as the 3D board lights them
# (brightest toward the near left, where the key light falls) inside a clean lacquer frame
# with a fine metal line. 9 squares wide, so the frame is half a square on each side.
# Usage: flat_art.py squares.jpg out.jpg [line hex, default platinum D6DAE2] [size, default 1536]
import sys, numpy as np
from PIL import Image, ImageDraw
src, dst = sys.argv[1], sys.argv[2]
line = sys.argv[3] if len(sys.argv) > 3 else 'D6DAE2'
N = int(sys.argv[4]) if len(sys.argv) > 4 else 1536
def to_lin(c): return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def to_srgb(c): c = np.clip(c, 0, 1); return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)
sq = N / 9; lo, hi = int(round(sq / 2)), int(round(N - sq / 2)); side = hi - lo
stone = np.asarray(Image.open(src).convert('RGB').resize((side, side), Image.LANCZOS)).astype(np.float32) / 255
y, x = np.mgrid[0:side, 0:side].astype(np.float32) / side
# key light from the near left: 1.42 there, falling to 1.12 at the far right
gain = 1.42 - 0.3 * np.clip(0.55 * x + 0.45 * (1 - y), 0, 1)
lit = to_srgb(to_lin(stone) * gain[..., None]) * 255
yy = np.linspace(0, 1, N)[:, None]
top = np.array([0x16, 0x16, 0x18], np.float32); bot = np.array([0x0A, 0x0A, 0x0B], np.float32)
out = (top * (1 - yy[..., None]) + bot * yy[..., None]) * np.ones((N, N, 1), np.float32)
out[lo:hi, lo:hi] = lit
img = Image.fromarray(out.clip(0, 255).astype(np.uint8))
d = ImageDraw.Draw(img, 'RGBA')
g = int(round(sq * 0.11))
rgb = tuple(int(line[i:i + 2], 16) for i in (0, 2, 4))
d.rectangle([lo - g, lo - g, hi - 1 + g, hi - 1 + g], outline=rgb + (150,), width=2)
d.rectangle([lo - 1, lo - 1, hi, hi], outline=(0, 0, 0, 160), width=2)
img.save(dst, quality=90)
