# Fades the shadow out toward the sprite's edges so no hard cut shows on the board,
# and checks how close each piece comes to the edge.
import sys, numpy as np
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
import glob, os
for p in sorted(glob.glob(src + '/sculpted-*.png')):
    im = np.asarray(Image.open(p).convert('RGBA')).astype(np.float32)
    h, w = im.shape[:2]
    a = im[..., 3] / 255
    # distance to the nearest edge, in px
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float32)
    ramp = np.clip(d / 36.0, 0, 1)
    ramp = ramp * ramp * (3 - 2 * ramp)
    edge = a[[0, -1], :].max(), a[:, [0, -1]].max()
    im[..., 3] = a * ramp * 255
    Image.fromarray(im.clip(0, 255).astype(np.uint8)).save(os.path.join(dst, os.path.basename(p)), optimize=True)
    # opaque bounding box (the piece itself, alpha > 0.9)
    ys, xs = np.where(a > 0.9)
    print(os.path.basename(p), 'edge alpha', [round(float(e), 3) for e in edge], 'piece box', xs.min(), xs.max(), ys.min(), ys.max())
