# The studio as the flat view needs it. Seen from straight above, polished stone and glass mirror
# whatever hangs overhead: under the studios' big overhead soft box the whole board turns milky.
# Here that light moves out to a ring around the camera, lower in the sky, and the ceiling right
# above turns dark, so the board mirrors a dark ceiling and keeps the deep color it shows tilted.
# The ring is made just bright enough that an upward-facing surface gets as much light as before
# (or as near as a white ring gets: the light tent's comes within a few percent), so the board is
# as bright as it was, only no longer veiled.
import numpy as np

# Elevations in degrees: the dark ceiling fades in between FLAG[0] and FLAG[1] and covers all
# above. The flat camera sits 80 degrees up with a 12 degree lens, so the board mirrors the sky
# between about 74 and 86 degrees; the ceiling's edge keeps well clear of that.
FLAG = (62, 66)
# The ring: rising between RING[0] and RING[1], full until RING[2], gone by RING[3].
RING = (44, 50, 58, 63)


def smooth(el, low, high):
    t = np.clip((np.degrees(el) - low) / (high - low), 0, 1)
    return t * t * (3 - 2 * t)


def light_from_above(img, el, width, height):
    """How much light falls on an upward-facing surface (cosine-weighted, any units)."""
    patch = (2 * np.pi / width) * (np.pi / height) * np.cos(el)
    return float((img * np.clip(np.sin(el), 0, None) * patch).sum())


def above(img, el, ceiling=0.004):
    """The studio with its overhead light moved out to a ring, giving the same light from above."""
    height, width = img.shape
    flag = smooth(el, *FLAG) * np.ones_like(img)
    ring = smooth(el, RING[0], RING[1]) * (1 - smooth(el, RING[2], RING[3])) * np.ones_like(img)
    dark = img * (1 - flag) + ceiling * flag
    target = light_from_above(img, el, width, height)
    low, high = 0.0, 4.0
    for _ in range(40):
        mid = (low + high) / 2
        if light_from_above(np.clip(dark + mid * ring, 0, 1), el, width, height) > target:
            high = mid
        else:
            low = mid
    return np.clip(dark + (low + high) / 2 * ring, 0, 1)
