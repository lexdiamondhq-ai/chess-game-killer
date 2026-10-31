#!/usr/bin/env python3
"""Draws the app's chess icons (the dock, the home tab bar) as template SVGs in the
asset catalog. Every glyph sits on a 24-point grid, solid shapes, so it reads like an
SF Symbol of the same size. Run it again after changing a shape:

    python3 scripts/make_glyphs.py
"""
import json
import math
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "ChessGameKiller", "Assets.xcassets", "Glyphs")


def rrect(x, y, w, h, r):
    return (f"M{x + r:.2f} {y:.2f}H{x + w - r:.2f}A{r} {r} 0 0 1 {x + w:.2f} {y + r:.2f}"
            f"V{y + h - r:.2f}A{r} {r} 0 0 1 {x + w - r:.2f} {y + h:.2f}H{x + r:.2f}"
            f"A{r} {r} 0 0 1 {x:.2f} {y + h - r:.2f}V{y + r:.2f}A{r} {r} 0 0 1 {x + r:.2f} {y:.2f}Z")


def circle(cx, cy, r, clockwise=True):
    sweep = 1 if clockwise else 0
    return (f"M{cx - r:.2f} {cy:.2f}A{r} {r} 0 1 {sweep} {cx + r:.2f} {cy:.2f}"
            f"A{r} {r} 0 1 {sweep} {cx - r:.2f} {cy:.2f}Z")


def transform(path_fn, dx=0.0, dy=0.0, s=1.0):
    """A piece drawn by `path_fn(dx, dy, s)` placed elsewhere and scaled about its own grid."""
    return path_fn(dx, dy, s)


# --- Pieces, each drawn on the full 24 grid, then placed with (dx, dy, s). ---

def P(x, y, dx, dy, s):
    return f"{dx + x * s:.2f} {dy + y * s:.2f}"


def base(dx=0, dy=0, s=1, top=18.3):
    x, w = 5.4, 13.2
    return rrect(dx + x * s, dy + top * s, w * s, 2.5 * s, 1.15 * s)


def pawn(dx=0, dy=0, s=1):
    p = lambda x, y: P(x, y, dx, dy, s)
    return " ".join([
        circle(dx + 12 * s, dy + 6.1 * s, 3.15 * s),
        rrect(dx + 8.3 * s, dy + 9.75 * s, 7.4 * s, 1.75 * s, 0.85 * s),
        f"M{p(9.75, 12.1)}C{p(9.75, 14.4)} {p(8.7, 16.2)} {p(7.6, 17.6)}L{p(16.4, 17.6)}"
        f"C{p(15.3, 16.2)} {p(14.25, 14.4)} {p(14.25, 12.1)}Z",
        base(dx, dy, s),
    ])


def soldier(dx=0, dy=0, s=1):
    """A pawn in an army helmet, like the app icon's boxer."""
    p = lambda x, y: P(x, y, dx, dy, s)
    return " ".join([
        # Helmet dome and brim.
        f"M{p(7.9, 6.3)}C{p(7.9, 3.7)} {p(9.7, 2.0)} {p(12, 2.0)}C{p(14.3, 2.0)} {p(16.1, 3.7)} {p(16.1, 6.3)}Z",
        rrect(dx + 6.3 * s, dy + 6.9 * s, 11.4 * s, 1.5 * s, 0.75 * s),
        # The face under the brim.
        f"M{p(9.4, 8.95)}L{p(14.6, 8.95)}C{p(14.4, 10.4)} {p(13.3, 11.0)} {p(12, 11.0)}C{p(10.7, 11.0)} {p(9.6, 10.4)} {p(9.4, 8.95)}Z",
        rrect(dx + 8.3 * s, dy + 11.55 * s, 7.4 * s, 1.5 * s, 0.75 * s),
        f"M{p(9.9, 13.6)}C{p(9.8, 15.2)} {p(8.8, 16.5)} {p(7.6, 17.6)}L{p(16.4, 17.6)}"
        f"C{p(15.2, 16.5)} {p(14.2, 15.2)} {p(14.1, 13.6)}Z",
        base(dx, dy, s),
    ])


def rook(dx=0, dy=0, s=1):
    p = lambda x, y: P(x, y, dx, dy, s)
    top = [(6.4, 2.8), (9.2, 2.8), (9.2, 5.0), (10.6, 5.0), (10.6, 2.8), (13.4, 2.8), (13.4, 5.0),
           (14.8, 5.0), (14.8, 2.8), (17.6, 2.8), (17.6, 8.5), (6.4, 8.5)]
    return " ".join([
        "M" + "L".join(p(x, y) for x, y in top) + "Z",
        f"M{p(8.3, 9.25)}L{p(15.7, 9.25)}L{p(16.6, 17.6)}L{p(7.4, 17.6)}Z",
        base(dx, dy, s),
    ])


def king(dx=0, dy=0, s=1):
    p = lambda x, y: P(x, y, dx, dy, s)
    return " ".join([
        # The cross as one outline: two overlapping bars would cancel out under even-odd.
        "M" + "L".join(p(x, y) for x, y in [(11.2, 0.9), (12.8, 0.9), (12.8, 2.2), (14.3, 2.2), (14.3, 3.8),
                                              (12.8, 3.8), (12.8, 5.5), (11.2, 5.5), (11.2, 3.8), (9.7, 3.8),
                                              (9.7, 2.2), (11.2, 2.2)]) + "Z",
        f"M{p(7.4, 10.0)}C{p(6.2, 7.4)} {p(8.6, 6.0)} {p(12, 6.0)}C{p(15.4, 6.0)} {p(17.8, 7.4)} {p(16.6, 10.0)}Z",
        rrect(dx + 7.6 * s, dy + 10.65 * s, 8.8 * s, 1.6 * s, 0.8 * s),
        f"M{p(9.3, 12.9)}C{p(9.2, 14.8)} {p(8.5, 16.3)} {p(7.4, 17.6)}L{p(16.6, 17.6)}"
        f"C{p(15.5, 16.3)} {p(14.8, 14.8)} {p(14.7, 12.9)}Z",
        base(dx, dy, s),
    ])


def knight(dx=0, dy=0, s=1, eye=True):
    p = lambda x, y: P(x, y, dx, dy, s)
    head = (
        f"M{p(8.4, 17.6)}"
        f"C{p(8.3, 15.3)} {p(9.4, 13.7)} {p(11.2, 12.4)}"      # chest up to the throat
        f"C{p(9.7, 12.2)} {p(8.5, 12.7)} {p(7.3, 13.3)}"       # under the jaw
        f"C{p(6.0, 13.9)} {p(4.6, 13.2)} {p(4.6, 11.9)}"       # chin to the muzzle
        f"C{p(4.6, 11.0)} {p(5.0, 10.3)} {p(5.8, 9.6)}"        # the nose
        f"L{p(9.6, 5.6)}"                                     # the face, up to the forehead
        f"L{p(9.9, 2.4)}"                                     # the ear
        f"L{p(11.9, 4.0)}"
        f"C{p(15.7, 4.1)} {p(17.9, 7.4)} {p(17.9, 11.4)}"     # the mane
        f"C{p(17.9, 14.0)} {p(17.2, 16.0)} {p(16.5, 17.6)}Z"
    )
    parts = [head, base(dx, dy, s)]
    if eye:
        parts.append(circle(dx + 10.3 * s, dy + 7.9 * s, 0.85 * s, clockwise=False))
    return " ".join(parts)


# --- Other shapes ---

def stroke_line(points, width):
    """A thick polyline with round ends, as a filled outline (template SVGs keep strokes,
    but filled shapes scale more predictably)."""
    return points, width


def svg(paths, strokes=()):
    """`paths`: filled with even-odd; `strokes`: (d, width) drawn as round-capped lines."""
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">']
    for d in paths:
        out.append(f'<path fill="#000" fill-rule="evenodd" d="{d}"/>')
    for d, w in strokes:
        out.append(f'<path fill="none" stroke="#000" stroke-width="{w}" stroke-linecap="round" '
                   f'stroke-linejoin="round" d="{d}"/>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def arrowhead(tip, direction, length=3.4, half=2.6):
    tx, ty = tip
    dx, dy = direction
    n = math.hypot(dx, dy)
    dx, dy = dx / n, dy / n
    bx, by = tx - dx * length, ty - dy * length
    px, py = -dy, dx
    return f"M{tx:.2f} {ty:.2f}L{bx + px * half:.2f} {by + py * half:.2f}L{bx - px * half:.2f} {by - py * half:.2f}Z"


def gear(cx, cy, r_out, r_in, teeth, tooth_frac=0.5):
    pts = []
    step = 2 * math.pi / teeth
    for i in range(teeth):
        a = i * step - math.pi / 2
        half = step * tooth_frac / 2
        lead = step * 0.08
        for ang, r in ((a - half - lead, r_in), (a - half + lead * 0.4, r_out), (a + half - lead * 0.4, r_out), (a + half + lead, r_in)):
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    d = "M" + "L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + "Z"
    return d


def clock():
    """A chess clock: two faces, one button pressed down."""
    body = rrect(2.4, 8.2, 19.2, 12.4, 3.0)
    faces = circle(8.0, 14.4, 3.65, clockwise=False) + " " + circle(16.0, 14.4, 3.65, clockwise=False)
    buttons = rrect(5.6, 5.4, 4.8, 1.9, 0.9) + " " + rrect(13.6, 6.5, 4.8, 1.1, 0.55)
    hands = [("M8 14.4V12.0", 1.4), ("M8 14.4L9.5 15.3", 1.4), ("M16 14.4L17.6 13.0", 1.4)]
    return svg([body + " " + faces, buttons], hands)


def puzzle():
    """A jigsaw piece with a pawn cut out of it."""
    # Square body with a knob on top and on the right, a socket on the left.
    d = ("M4 7.2H8.6C8.3 6.6 8.2 6.1 8.2 5.6C8.2 3.8 9.9 2.6 12 2.6C14.1 2.6 15.8 3.8 15.8 5.6"
         "C15.8 6.1 15.7 6.6 15.4 7.2H19.2C19.7 7.2 20 7.5 20 8V11.4C20.5 11.1 21 11 21.4 11"
         "C22.6 11 23.4 12.2 23.4 13.6C23.4 15.0 22.6 16.2 21.4 16.2C21 16.2 20.5 16.1 20 15.8V20.4"
         "C20 20.9 19.7 21.2 19.2 21.2H4.8C4.3 21.2 4 20.9 4 20.4V15.8C4.5 16.1 5 16.2 5.4 16.2"
         "C6.6 16.2 7.4 15.0 7.4 13.6C7.4 12.2 6.6 11 5.4 11C5 11 4.5 11.1 4 11.4V8C4 7.5 4.3 7.2 4.8 7.2Z")
    hole = pawn(dx=12 - 12 * 0.5, dy=8.4, s=0.5)
    return svg([d + " " + hole])


def analyze():
    """A magnifier over a pawn."""
    ring = circle(10.2, 10.2, 7.6) + " " + circle(10.2, 10.2, 5.9, clockwise=False)
    inside = pawn(dx=10.2 - 12 * 0.42, dy=10.2 - 11.4 * 0.42, s=0.42)
    return svg([ring, inside], [("M15.9 15.9L20.8 20.8", 2.8)])


def rewind():
    """A pawn inside an arrow turning back: replay a game."""
    r, cx, cy = 8.8, 12, 12.4
    a0, a1 = math.radians(-58), math.radians(-122 + 360)
    x0, y0 = cx + r * math.cos(a0), cy + r * math.sin(a0)
    x1, y1 = cx + r * math.cos(a1), cy + r * math.sin(a1)
    # From the upper right, down and all the way round to the upper left.
    arc = f"M{x0:.2f} {y0:.2f}A{r} {r} 0 1 1 {x1:.2f} {y1:.2f}"
    # The head sits on the upper right end, pointing back the way of a rewind (up and left).
    d = (math.sin(a0), -math.cos(a0))
    head = arrowhead((x0 + d[0] * 3.2, y0 + d[1] * 3.2), d, length=4.2, half=2.9)
    inner = pawn(dx=12 - 12 * 0.5, dy=12.4 - 11.6 * 0.5, s=0.5)
    return svg([inner, head], [(arc, 2.1)])


def undo():
    """A knight's move taken back: an L with an arrowhead."""
    return svg([arrowhead((3.4, 8.6), (-1, 0), length=4.6, half=3.4),
                circle(18.2, 19.4, 1.9)],
               [("M18.2 17.2V10.6C18.2 9.5 17.3 8.6 16.2 8.6H6.6", 2.6)])


def hints(off=False):
    """The coach's mark for its best move: a dot in a halo ring, as on the board."""
    paths = [circle(12, 12, 10.0) + " " + circle(12, 12, 7.9, clockwise=False),
             circle(12, 12, 4.2)]
    strokes = []
    if off:
        strokes.append(("M4.4 4.4L19.6 19.6", 2.2))
    return svg(paths, strokes)


def checker_tile(x, y, size, gap=1.0, radius=0.9):
    half = (size - gap) / 2
    return [rrect(x, y, half, half, radius), rrect(x + half + gap, y + half + gap, half, half, radius),
            ]


def checker_outline(x, y, size, gap=1.0, radius=0.9, stroke=1.4):
    half = (size - gap) / 2
    out = []
    for qx, qy in ((x + half + gap, y), (x, y + half + gap)):
        outer = rrect(qx, qy, half, half, radius)
        inner = rrect(qx + stroke, qy + stroke, half - 2 * stroke, half - 2 * stroke, max(radius - 0.6, 0.2))
        out.append(outer + " " + inner)
    return out


def flip():
    """The board turning around."""
    tile = checker_tile(7.4, 7.4, 9.2) + checker_outline(7.4, 7.4, 9.2)
    r, a = 9.8, math.radians(38)
    left_up = (12 - r * math.cos(a), 12 - r * math.sin(a))
    right_up = (12 + r * math.cos(a), 12 - r * math.sin(a))
    right_down = (12 + r * math.cos(a), 12 + r * math.sin(a))
    left_down = (12 - r * math.cos(a), 12 + r * math.sin(a))
    top = f"M{left_up[0]:.2f} {left_up[1]:.2f}A{r} {r} 0 0 1 {right_up[0]:.2f} {right_up[1]:.2f}"
    bottom = f"M{right_down[0]:.2f} {right_down[1]:.2f}A{r} {r} 0 0 1 {left_down[0]:.2f} {left_down[1]:.2f}"
    # Clockwise tangents at the ends.
    t1 = (math.sin(a), math.cos(a))
    t2 = (-math.sin(a), -math.cos(a))
    head1 = arrowhead((right_up[0] + t1[0] * 2.6, right_up[1] + t1[1] * 2.6), t1, length=3.8, half=2.6)
    head2 = arrowhead((left_down[0] + t2[0] * 2.6, left_down[1] + t2[1] * 2.6), t2, length=3.8, half=2.6)
    return svg(tile + [head1, head2], [(top, 2.0), (bottom, 2.0)])


def settings():
    """A gear with a checkered heart."""
    g = gear(12, 12, 10.6, 8.2, 8, tooth_frac=0.42)
    hole = rrect(7.2, 7.2, 9.6, 9.6, 2.2)
    # Even-odd: the gear minus a rounded square, then two squares of a board inside it.
    inner = checker_tile(8.6, 8.6, 6.8, gap=0.0, radius=0.5)
    return svg([g + " " + hole] + inner)


def collapse():
    """Back to the normal view: a small board with corners closing on it."""
    tile = checker_tile(8.0, 8.0, 8.0) + checker_outline(8.0, 8.0, 8.0, stroke=1.3)
    corners = [
        ("M2.6 7.2H7.2V2.6", 2.2), ("M16.8 2.6V7.2H21.4", 2.2),
        ("M2.6 16.8H7.2V21.4", 2.2), ("M16.8 21.4V16.8H21.4", 2.2),
    ]
    return svg(tile, corners)


def expand():
    tile = checker_tile(8.0, 8.0, 8.0) + checker_outline(8.0, 8.0, 8.0, stroke=1.3)
    corners = [
        ("M2.6 7.6V2.6H7.6", 2.2), ("M16.4 2.6H21.4V7.6", 2.2),
        ("M2.6 16.4V21.4H7.6", 2.2), ("M16.4 21.4H21.4V16.4", 2.2),
    ]
    return svg(tile, corners)


def scholar(dx=0, dy=0, s=1):
    """A pawn in a graduation cap: the coach. Two parts, so the cap can sit on the head."""
    p = lambda x, y: P(x, y, dx, dy, s)
    cap = (f"M{p(12, 0.9)}L{p(19.4, 3.6)}L{p(12, 6.3)}L{p(4.6, 3.6)}Z "
           + rrect(dx + 8.6 * s, dy + 4.6 * s, 6.8 * s, 2.0 * s, 0.6 * s))
    body = " ".join([
        f"M{p(9.2, 7.3)}L{p(14.8, 7.3)}C{p(14.8, 9.1)} {p(13.6, 10.2)} {p(12, 10.2)}"
        f"C{p(10.4, 10.2)} {p(9.2, 9.1)} {p(9.2, 7.3)}Z",
        rrect(dx + 8.3 * s, dy + 10.75 * s, 7.4 * s, 1.6 * s, 0.8 * s),
        f"M{p(9.8, 12.9)}C{p(9.75, 14.8)} {p(8.7, 16.3)} {p(7.6, 17.6)}L{p(16.4, 17.6)}"
        f"C{p(15.3, 16.3)} {p(14.25, 14.8)} {p(14.2, 12.9)}Z",
        base(dx, dy, s),
    ])
    tassel = circle(dx + 18.2 * s, dy + 8.4 * s, 0.95 * s)
    return [cap, body, tassel], [(f"M{p(18.2, 3.9)}V{p(18.2, 7.6).split()[1]}", 1.0 * s)]


def coach():
    paths, strokes = scholar()
    return svg(paths, strokes)


def challenge():
    """A knight with a paper plane flying off: an invitation to play."""
    rider = knight(dx=-0.9, dy=4.2, s=0.8)
    plane = ("M22.4 1.6L13.4 5.5L16.9 6.8Z "
             "M22.4 1.6L17.5 7.4L18.6 10.6Z")
    return svg([rider, plane])


def online():
    """A globe with its equator and two meridians: a game with someone anywhere in the world."""
    ring = circle(12, 12, 9.5) + " " + circle(12, 12, 7.9, clockwise=False)
    lines = [
        ("M3.8 12H20.2", 1.6),
        ("M12 3.4C8.2 6.4 8.2 17.6 12 20.6", 1.6),
        ("M12 3.4C15.8 6.4 15.8 17.6 12 20.6", 1.6),
    ]
    return svg([ring], lines)


def centered_pawn(cx, cy, s):
    """A pawn of scale `s` centered on (cx, cy): on its own grid it spans y 2.95 to 20.8."""
    return pawn(dx=cx - 12 * s, dy=cy - 11.875 * s, s=s)


def scan():
    """A pawn in a camera's corner marks: read a real board from a photo."""
    corners = [("M2.6 7.4V2.6H7.4", 2.0), ("M16.6 2.6H21.4V7.4", 2.0),
               ("M2.6 16.6V21.4H7.4", 2.0), ("M16.6 21.4H21.4V16.6", 2.0)]
    return svg([centered_pawn(12, 12, 0.6)], corners)


def today():
    """A calendar page with a pawn on it: the move of the day."""
    page = rrect(3.0, 4.6, 18.0, 16.8, 3.2) + " " + rrect(4.7, 9.6, 14.6, 10.1, 1.7)
    rings = rrect(7.0, 2.3, 2.1, 4.6, 1.05) + " " + rrect(14.9, 2.3, 2.1, 4.6, 1.05)
    return svg([page, rings, centered_pawn(12, 14.75, 0.42)])


GLYPHS = {
    "glyph-home": svg([rook()]),
    "glyph-train": svg([knight()]),
    "glyph-play": clock(),
    "glyph-puzzles": puzzle(),
    "glyph-analyze": analyze(),
    "glyph-army": svg([soldier()]),
    "glyph-games": rewind(),
    "glyph-undo": undo(),
    "glyph-hints": hints(),
    "glyph-hints-off": hints(off=True),
    "glyph-flip": flip(),
    "glyph-settings": settings(),
    "glyph-normal-view": collapse(),
    "glyph-big-board": expand(),
    "glyph-king": svg([king()]),
    "glyph-pawn": svg([pawn()]),
    "glyph-coach": coach(),
    "glyph-challenge": challenge(),
    "glyph-online": online(),
    "glyph-scan": scan(),
    "glyph-today": today(),
}


def main():
    os.makedirs(ROOT, exist_ok=True)
    with open(os.path.join(ROOT, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    for name, body in GLYPHS.items():
        folder = os.path.join(ROOT, f"{name}.imageset")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, f"{name}.svg"), "w") as f:
            f.write(body)
        contents = {
            "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
        }
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump(contents, f, indent=2)
            f.write("\n")
    print(f"wrote {len(GLYPHS)} glyphs to {os.path.normpath(ROOT)}")


if __name__ == "__main__":
    main()
