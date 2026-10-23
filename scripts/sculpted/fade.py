# Finishes the sprites from sprites.py for the asset catalog:
#  - the ivory pieces get a darker edge along their outline, so they keep a clear contour on the
#    light squares: a soft band (about 1.4 pt on the phone) and a fine line at the very edge (about 0.4 pt),
#    worked out from mask/<name>.png (the piece without its shadow), so the shadow is left alone;
#  - the shadow fades out before the picture's edge, so no hard cut shows on the board.
# It also checks how close each piece comes to the edge.
# Usage: fade.py src dst [band px, default 12] [band strength, default 0.5] [line px, default 3.5] [line strength, default 0.4]
import sys, glob, os
import numpy as np
from PIL import Image
from scipy import ndimage
src, dst = sys.argv[1], sys.argv[2]
BAND = float(sys.argv[3]) if len(sys.argv) > 3 else 12.0
BAND_K = float(sys.argv[4]) if len(sys.argv) > 4 else 0.5
LINE = float(sys.argv[5]) if len(sys.argv) > 5 else 3.5
LINE_K = float(sys.argv[6]) if len(sys.argv) > 6 else 0.4
os.makedirs(dst, exist_ok=True)


def inside_distance(alpha):
    """Distance in px from each pixel of the piece to its outline, with the edge's own coverage."""
    inside = alpha > 0.5
    d = ndimage.distance_transform_edt(inside)
    # sub-pixel: an edge pixel half covered sits on the outline
    return np.where(inside, d - 0.5, 0) + np.clip(alpha, 0, 1) * (~inside) * 0.5


for p in sorted(glob.glob(src + '/*.png')):
    name = os.path.basename(p)
    im = np.asarray(Image.open(p).convert('RGBA')).astype(np.float32)
    h, w = im.shape[:2]
    a = im[..., 3] / 255
    mask_path = os.path.join(src, 'mask', name)
    if '-w' in name and os.path.exists(mask_path):
        m = np.asarray(Image.open(mask_path).convert('RGBA')).astype(np.float32)[..., 3] / 255
        d = inside_distance(m)
        band = np.clip(1 - d / BAND, 0, 1) ** 2
        line = np.clip(1 - d / LINE, 0, 1)
        k = 1 - BAND_K * band - LINE_K * line
        # straight color: the shadow under an edge pixel is black, so darkening the whole pixel is exact
        im[..., :3] *= np.clip(k, 0, 1)[..., None]
    # distance to the nearest edge of the picture, in px
    yy, xx = np.mgrid[0:h, 0:w]
    de = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(np.float32)
    ramp = np.clip(de / 40.0, 0, 1)
    ramp = ramp * ramp * (3 - 2 * ramp)
    edge = a[[0, -1], :].max(), a[:, [0, -1]].max()
    im[..., 3] = a * ramp * 255
    Image.fromarray(im.clip(0, 255).round().astype(np.uint8)).save(os.path.join(dst, name), optimize=True)
    # opaque bounding box (the piece itself, alpha > 0.9)
    ys, xs = np.where(a > 0.9)
    print(name, 'edge alpha', [round(float(e), 3) for e in edge], 'piece box', xs.min(), xs.max(), ys.min(), ys.max())
