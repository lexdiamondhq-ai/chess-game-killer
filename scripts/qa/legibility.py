#!/usr/bin/env python3
"""Piece legibility check: judges every look's pieces the way the eye sees them on the phone.

For every look with a board picture (BoardTheme.all except Neon) it lays the flat board out as the app
does at phone size (board 370 pt, at 1x and 3x, White and Black at the bottom, the start position and
two busy middlegames) and measures two things:

  silhouettes  how alike the piece types are from their shape alone. Each opaque body is shrunk to 24 px
               tall with its foot at the bottom centre (the piece brief's test), and compared with
               intersection over union, whole and over its top 40 % (the head, where the type lives).
               The same at the size the piece stands on the board at 1x, plus a nearest-neighbour test
               against every other set. A pair fails when its heads are more alike than that pair is in
               any of 28 widely used piece sets (the reference envelope, REF_HEAD).
  contours     how well each piece's edge stands off the squares: a 1 pt band just inside its opaque
               silhouette (the soft shadow left out) against the colour of the square under each band
               pixel, for light and dark squares and both sides (WCAG contrast ratio and CIE L*
               difference). It fails below 3:1, the WCAG 2.1 non-text contrast minimum.

It writes a JSON report, a markdown summary with pass/fail per look, a contact sheet per look and the
composited boards into the output folder. See scripts/qa/README.md.

Python 3 with Pillow and numpy only.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# MARK: - Contracts and constants

# How a sprite is drawn on its square (squares are the unit; the foot is where the base meets the board).
# The canvas spans x in [-hw, hw] and y in [bottom, top] around the foot; 400 px per square in both.
CONTRACTS = {
    "v1": dict(size=(520, 568), foot=(260, 400), top=1.0, bottom=-0.42, hw=0.65, k=1.22, lift=0.15),
    "v2": dict(size=(560, 760), foot=(280, 600), top=1.5, bottom=-0.4, hw=0.7, k=1.12, lift=0.22),
}
PX_PER_SQUARE = 400

BOARD_PT = 370.0           # the board's width on an iPhone in the executive layout
SCALES = (1, 3)            # 1x is what the eye resolves at arm's length; 3x is the device's pixels
TYPES = "KQRBNP"
CODES = [side + kind for side in "wb" for kind in TYPES]
PAIRS = [a + b for i, a in enumerate(TYPES) for b in TYPES[i + 1:]]
NAMES = dict(K="king", Q="queen", R="rook", B="bishop", N="knight", P="pawn")
SIDE_NAMES = dict(w="white", b="black")
FENS = {
    "start": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
    "mid1": "r1bqk2r/pp1nbppp/2p1pn2/3p4/2PP4/2N1PN2/PPQ2PPP/R1B1KB1R",
    "mid2": "2kr3r/ppp2ppp/2nbbq2/3np3/8/1PNPBNP1/PBQ1PPBP/R4RK1",
}
# The pairs the piece brief names as the ones people mix up.
NAMED_PAIRS = ["RP", "BP", "KQ", "QB"]

# A pixel belongs to the piece's body when its alpha is at least this. Every contact shadow in the
# current sets stays below 0.82 (most at 0.5-0.65), and the bodies are opaque.
BODY_ALPHA = 0.85
# Silhouettes are compared shrunk to this height (the piece brief's test), and at 1x at a common height.
SQUINT_PX = 24
ONBOARD_PX = 48
# The top share of a silhouette that carries its type. Below it every Staunton piece has much the same
# turned body and base, which makes whole shapes look alike for every pair (see README).
HEAD = 0.4
# Within one set, the top 40 % of each pair's 24 px silhouettes may overlap at most as much as that pair
# does in the most alike of 28 Lichess piece sets (both colours), which millions play on every day.
# Recompute with --calibrate DIR (README: Calibration).
REF_HEAD = {
    "KQ": 0.74, "KR": 0.56, "KB": 0.78, "KN": 0.75, "KP": 0.76, "QR": 0.59, "QB": 0.74, "QN": 0.73,
    "QP": 0.70, "RB": 0.64, "RN": 0.72, "RP": 0.70, "BN": 0.69, "BP": 0.83, "NP": 0.80,
}
# The same envelope for whole silhouettes, reported only.
REF_WHOLE = {
    "KQ": 0.85, "KR": 0.72, "KB": 0.87, "KN": 0.86, "KP": 0.80, "QR": 0.75, "QB": 0.83, "QN": 0.83,
    "QP": 0.74, "RB": 0.81, "RN": 0.79, "RP": 0.78, "BN": 0.83, "BP": 0.82, "NP": 0.83,
}
REF_SETS = 28
# Pairs outside the brief's list only warn, and only when their heights are closer than this ratio.
SIZE_APART = 1.5
# Two of the app's sets are one family (made from the same models) when their 24 px masks overlap this
# much (median of the 12); the nearest-neighbour test never compares a set with its own family.
FAMILY_IOU = 0.85
# The piece brief's rules: the rook at least 1.25x the pawn's height, its top clearly wider than the
# pawn's head (both over the top third of each piece); tournament order of heights K > Q > B > N > R > P,
# steps of at least 0.05 squares.
ROOK_HEIGHT_MIN = 1.25
ROOK_TOP_MIN = 1.25
HEIGHT_ORDER = "KQBNRP"
HEIGHT_STEP = 0.05

# The contour band just inside the silhouette, in points.
BAND_PT = 1.0
# WCAG 2.1 SC 1.4.11 (non-text contrast): the parts of a graphic needed to understand it need 3:1
# against the colours next to them. A piece's outline against the square under it is exactly that.
# A type passes on a square colour when the median of its band reaches this (half of its outline).
WCAG_MIN = 3.0
# Contours are judged at the device's pixels (3x), where a fine contour line is resolved; 1x is reported.
GATE_SCALE = 3


# MARK: - Colour

def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def luminance(rgb):
    """WCAG relative luminance of sRGB values in 0..1 (array [..., 3])."""
    return srgb_to_linear(np.clip(rgb, 0, 1)) @ np.array([0.2126, 0.7152, 0.0722])


def lightness(y):
    """CIE L* from relative luminance."""
    d = 6 / 29
    f = np.where(y > d ** 3, np.cbrt(np.maximum(y, 0)), y / (3 * d * d) + 4 / 29)
    return 116 * f - 16


def wcag(y1, y2):
    hi = np.maximum(y1, y2)
    lo = np.minimum(y1, y2)
    return (hi + 0.05) / (lo + 0.05)


# MARK: - The looks, read from BoardTheme.swift

def strip_comments(text):
    out = []
    for line in text.splitlines():
        in_string = False
        cut = None
        for i, ch in enumerate(line):
            if ch == '"':
                in_string = not in_string
            elif not in_string and line.startswith("//", i):
                cut = i
                break
        out.append(line if cut is None else line[:cut])
    return "\n".join(out)


def balanced(text, open_index):
    """The text inside the bracket at open_index, up to its matching close."""
    pairs = {"(": ")", "[": "]"}
    close = pairs[text[open_index]]
    depth = 0
    in_string = False
    for i in range(open_index, len(text)):
        ch = text[i]
        if in_string:
            in_string = ch != '"'
            continue
        if ch == '"':
            in_string = True
        elif ch == text[open_index]:
            depth += 1
        elif ch == close:
            depth -= 1
            if depth == 0:
                return text[open_index + 1:i]
    raise ValueError("unbalanced brackets")


def split_args(body):
    """Top-level `label: value` arguments of a Swift call."""
    args, depth, cur, in_string = [], 0, "", False
    for ch in body:
        if in_string:
            cur += ch
            in_string = ch != '"'
            continue
        if ch == '"':
            in_string = True
        elif ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        args.append(cur.strip())
    labelled = {}
    for arg in args:
        m = re.match(r"(\w+)\s*:\s*(.*)$", arg, re.S)
        if m:
            labelled[m.group(1)] = m.group(2).strip()
    return labelled


def swift_color(expr):
    """(r, g, b, opacity) from `Color(hex: 0x...)`, `Color.white`, with an optional `.opacity(x)`."""
    if expr is None:
        return None
    m = re.search(r"Color\(hex:\s*0x([0-9A-Fa-f]{6})\)", expr)
    if m:
        rgb = tuple(int(m.group(1)[i:i + 2], 16) for i in (0, 2, 4))
    elif "Color.white" in expr or expr.startswith(".white"):
        rgb = (255, 255, 255)
    elif "Color.black" in expr or expr.startswith(".black"):
        rgb = (0, 0, 0)
    else:
        return None
    o = re.search(r"\.opacity\(([0-9.]+)\)", expr)
    return rgb + (float(o.group(1)) if o else 1.0,)


def swift_string(expr):
    m = re.fullmatch(r'"([^"]*)"', expr.strip()) if expr else None
    return m.group(1) if m else None


def parse_themes(path):
    """Every look in BoardTheme.all, in order, with its board picture, piece prefix and colours."""
    text = strip_comments(Path(path).read_text())
    all_match = re.search(r"static let all\s*:\s*\[BoardTheme\]\s*=\s*\[", text)
    if not all_match:
        raise SystemExit(f"{path}: could not find `static let all`")
    order = re.findall(r"\.(\w+)", balanced(text, all_match.end() - 1))

    # Rival boards are made by rivalTheme(...), which derives the prefix and the picture from the id.
    rival_derived = {}
    rf = re.search(r"static func rivalTheme\(", text)
    if rf:
        fn_body_start = text.index("{", rf.end())
        fn_body = text[fn_body_start:text.index("\n    }", fn_body_start)]
        call = re.search(r"BoardTheme\(", fn_body)
        inner = split_args(balanced(fn_body, call.end() - 1))
        piece_expr = inner.get("pieceSet", "").replace(" ", "")
        art_expr = inner.get("boardArt", "").replace(" ", "")
        if piece_expr != 'id.rawValue+"-"' or art_expr != '"board-"+id.rawValue':
            raise SystemExit(f"{path}: rivalTheme derives pieceSet/boardArt in a new way "
                             f"({piece_expr!r}, {art_expr!r}); update parse_themes")
        rival_derived = dict(sprites=inner.get("spritePieces") == "true")

    themes = {}
    for m in re.finditer(r"static let (\w+)\s*=\s*(BoardTheme|rivalTheme)\(", text):
        var, kind = m.group(1), m.group(2)
        a = split_args(balanced(text, m.end() - 1))
        ident = (a.get("id") or "").lstrip(".") or var
        if kind == "rivalTheme":
            piece_set = ident + "-"
            board_art = "board-" + ident
            sprites = rival_derived.get("sprites", True)
        else:
            piece_set = swift_string(a.get("pieceSet"))
            board_art = swift_string(a.get("boardArt")) if "boardArt" in a else None
            sprites = a.get("spritePieces") == "true"
        backdrop = [swift_color(c) for c in re.findall(r"Color\(hex:\s*0x[0-9A-Fa-f]{6}\)", a.get("backdrop", ""))]
        themes[var] = dict(
            id=ident, name=swift_string(a.get("name")) or ident, piece_set=piece_set, board_art=board_art,
            sprite_pieces=sprites, white_name=swift_string(a.get("whiteName")),
            black_name=swift_string(a.get("blackName")),
            label_light=swift_color(a.get("labelOnLight")), label_dark=swift_color(a.get("labelOnDark")),
            backdrop=[c[:3] for c in backdrop if c] or None,
        )
    missing = [o for o in order if o not in themes]
    if missing:
        raise SystemExit(f"{path}: BoardTheme.all names looks it does not define: {missing}")
    return [themes[o] for o in order]


# MARK: - Sprites

def find_file(folder, stem, exts=(".png",)):
    folder = Path(folder)
    for ext in exts:
        for candidate in (folder / f"{stem}{ext}", folder / f"{stem}.imageset" / f"{stem}{ext}"):
            if candidate.exists():
                return candidate
    return None


class SpriteSet:
    """The twelve sprites of one prefix, their contract and their masks."""

    def __init__(self, prefix, catalog, override=None, contract=None, k=None, lift=None):
        self.prefix = prefix
        self.paths = {}
        self.source = "catalog"
        for code in CODES:
            path = None
            if override:
                path = find_file(override, prefix + code) or find_file(override, code)
            if path is not None:
                self.source = f"override {override}"
            else:
                path = find_file(Path(catalog) / "Pieces", prefix + code)
            if path is None:
                raise SystemExit(f"no sprite for {prefix}{code} (catalog {catalog}, override {override})")
            self.paths[code] = path
        self.images = {code: Image.open(p).convert("RGBA") for code, p in self.paths.items()}
        sizes = {im.size for im in self.images.values()}
        if len(sizes) != 1:
            raise SystemExit(f"{prefix}: sprites of different sizes {sorted(sizes)}")
        self.size = sizes.pop()
        if contract:
            self.contract_name = contract
        else:
            match = [n for n, c in CONTRACTS.items() if c["size"] == self.size]
            if not match:
                known = ", ".join(f"{n} {c['size'][0]}x{c['size'][1]}" for n, c in CONTRACTS.items())
                raise SystemExit(f"{prefix}: {self.size[0]}x{self.size[1]} matches no sprite contract ({known})")
            self.contract_name = match[0]
        self.c = dict(CONTRACTS[self.contract_name])
        if k is not None:
            self.c["k"] = k
        if lift is not None:
            self.c["lift"] = lift
        self.alpha = {code: np.asarray(im, dtype=np.float32)[..., 3] / 255 for code, im in self.images.items()}
        self.body = {code: (a >= BODY_ALPHA) for code, a in self.alpha.items()}
        self._drawn = {}

    @property
    def foot(self):
        return self.c["foot"]

    def drawn_size(self, sq):
        c = self.c
        return sq * 2 * c["hw"] * c["k"], sq * (c["top"] - c["bottom"]) * c["k"]

    def placement(self, sq, foot_x, foot_y):
        """Integer left, top, width, height of the sprite whose foot stands at (foot_x, foot_y)."""
        w, h = self.drawn_size(sq)
        left = foot_x - w / 2
        top = foot_y - self.c["top"] * self.c["k"] * sq
        return int(round(left)), int(round(top)), max(1, int(round(w))), max(1, int(round(h)))

    def drawn(self, code, size):
        """The sprite resized to `size` (premultiplied, as Core Graphics does) and its body coverage."""
        key = (code, size)
        if key not in self._drawn:
            im = self.images[code].convert("RGBa").resize(size, Image.Resampling.LANCZOS).convert("RGBA")
            cover = Image.fromarray(self.body[code].astype(np.float32), "F").resize(size, Image.Resampling.BOX)
            self._drawn[key] = (im, np.asarray(cover, dtype=np.float32))
        return self._drawn[key]

    def onboard_mask(self, code, sq):
        """The body as drawn on the board at this square size, and the foot's x in that mask."""
        w, h = self.drawn_size(sq)
        size = (max(1, int(round(w))), max(1, int(round(h))))
        _, cover = self.drawn(code, size)
        return cover >= 0.5, self.foot[0] / self.size[0] * size[0]


# MARK: - The board, laid out as BoardView.flatBoard does

def square_cell(file, rank, flipped):
    return (7 - file, rank) if flipped else (file, 7 - rank)


def parse_fen(fen):
    pieces = []
    for r, row in enumerate(fen.split()[0].split("/")):
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
                continue
            pieces.append((("w" if ch.isupper() else "b") + ch.upper(), f, 7 - r))
            f += 1
    return pieces


def font(size, bold=True, mono=False):
    candidates = (["/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"] if mono else []) + [
        "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf" if bold else "/usr/share/fonts/opentype/inter/Inter-Regular.otf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/SFNS.ttf", "/Library/Fonts/Arial.ttf",
    ]
    for c in candidates:
        if Path(c).exists():
            return ImageFont.truetype(c, max(1, int(round(size))))
    return ImageFont.load_default(size=max(1, int(round(size))))


class Board:
    """One look's flat board at one scale: backdrop, glass frame, the picture, coordinates, pieces."""

    def __init__(self, look, art_path, sprites, scale):
        self.look, self.sprites, self.scale = look, sprites, scale
        self.side = BOARD_PT * scale
        self.sq = self.side / 9          # the picture is 9 squares wide: half a square of frame each side
        self.inset = self.sq / 2
        self.clip = sprites.contract_name == "v1"   # today's PieceImage is clipped at the board's edge
        self.pad = int(math.ceil(0.25 * self.sq))
        # v2 pieces are not clipped, so a king on the far rank may rise above the frame: leave room.
        self.top = int(math.ceil((0.0 if self.clip else 0.45) * self.sq)) + self.pad
        self.width = int(math.ceil(self.side)) + 2 * self.pad
        self.height = int(math.ceil(self.side)) + self.top + self.pad
        art = Image.open(art_path).convert("RGB")
        n = int(round(self.side))
        self.art = art.resize((n, n), Image.Resampling.LANCZOS)
        self._base = {}

    # Geometry in canvas pixels
    def square_rect(self, file, rank, flipped):
        col, row = square_cell(file, rank, flipped)
        x0 = self.pad + self.inset + col * self.sq
        y0 = self.top + self.inset + row * self.sq
        return x0, y0, x0 + self.sq, y0 + self.sq

    def foot(self, file, rank, flipped):
        x0, y0, x1, y1 = self.square_rect(file, rank, flipped)
        return (x0 + x1) / 2, (y0 + y1) / 2 + self.sprites.c["lift"] * self.sq

    def backdrop(self):
        inner, outer = (self.look.get("backdrop") or [(43, 42, 44), (7, 7, 8)])[:2]
        w, h = self.width, self.height
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        cx, cy = w / 2, self.top + self.side * 0.45
        # ThemeBackdrop: a radial gradient over the whole screen (about 874 pt tall), deepened
        # toward black by a 0.2-0.5 linear veil; the board sits near the middle of it.
        r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (0.75 * 874 * self.scale)
        t = np.clip(r, 0, 1)[..., None]
        rgb = np.array(inner, np.float32) * (1 - t) + np.array(outer, np.float32) * t
        veil = 0.2 + 0.3 * np.clip(0.42 + (yy - cy) / (874 * self.scale), 0, 1)
        rgb = rgb * (1 - veil[..., None])
        return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

    def board_layer(self, flipped, labels):
        """The board without pieces: glass frame, the stone squares, the hairline, coordinates."""
        n = int(round(self.side))
        s = self.scale
        # BoardGlass: a faint pane (the fallback before iOS 26) with light falling from the top left.
        yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
        t = (xx + yy) / (2 * n)
        sheen = np.interp(t, [0, 0.3, 0.6, 1], [0.22, 0.07, 0.02, 0.1])
        streak = np.interp(t, [0, 0.22, 0.3, 0.38, 1], [0, 0, 0.12, 0, 0])
        a = 1 - (1 - 0.07) * (1 - sheen) * (1 - streak)
        glass = np.zeros((n, n, 4), np.float32)
        glass[..., :3] = 255
        glass[..., 3] = a * 255
        layer = Image.fromarray(glass.astype(np.uint8), "RGBA")
        d = ImageDraw.Draw(layer)
        edge = max(1, int(round(1.2 * s)))
        for i in range(edge):
            d.rectangle([i, i, n - 1 - i, n - 1 - i], outline=(255, 255, 255, int(255 * 0.32)))
        d.rectangle([edge, edge, n - 1 - edge, n - 1 - edge], outline=(0, 0, 0, int(255 * 0.35)))
        # The stone sits in the glass, a little below its surface.
        inset = int(round(self.inset))
        shadow = Image.new("L", (n, n), 0)
        ImageDraw.Draw(shadow).rectangle([inset, inset + int(round(self.side * 0.004)), n - inset - 1,
                                          n - inset - 1 + int(round(self.side * 0.004))], fill=int(255 * 0.5))
        shadow = shadow.filter(ImageFilter.GaussianBlur(max(0.5, self.side * 0.012 / 2)))
        black = Image.new("RGBA", (n, n), (0, 0, 0, 255))
        black.putalpha(shadow)
        layer.alpha_composite(black)
        art = self.art.rotate(180) if flipped else self.art
        stone = art.crop((inset, inset, n - inset, n - inset)).convert("RGBA")
        layer.alpha_composite(stone, (inset, inset))
        # A fine bright line where the glass meets the stone.
        line = max(1, int(round(0.75 * s)))
        p = int(round(self.inset - self.side * 0.007))
        for i in range(line):
            d.rectangle([p + i, p + i, n - 1 - p - i, n - 1 - p - i], outline=(255, 255, 255, int(255 * 0.28)))
        if labels:
            self.draw_coordinates(layer, flipped)
        return layer

    def draw_coordinates(self, layer, flipped):
        d = ImageDraw.Draw(layer)
        f = font(self.sq * 0.2)
        pad = self.sq * 0.05
        off = self.pad, self.top
        for row in range(8):
            for col in range(8):
                file, rank = (7 - col, row) if flipped else (col, 7 - row)
                light = (file + rank) % 2 == 1
                color = self.look.get("label_light" if light else "label_dark") or (255, 255, 255, 0.7)
                fill = tuple(color[:3]) + (int(255 * color[3]),)
                x0, y0, x1, y1 = self.square_rect(file, rank, flipped)
                x0, x1, y0, y1 = x0 - off[0], x1 - off[0], y0 - off[1], y1 - off[1]
                if col == 0:
                    d.text((x0 + pad, y0 + pad), str(rank + 1), font=f, fill=fill, anchor="lt")
                if row == 7:
                    d.text((x1 - pad, y1 - pad), "abcdefgh"[file], font=f, fill=fill, anchor="rb")

    def base(self, flipped, labels=True):
        key = (flipped, labels)
        if key not in self._base:
            canvas = self.backdrop()
            canvas.alpha_composite(self.board_layer(flipped, labels), (self.pad, self.top))
            self._base[key] = canvas
        return self._base[key]

    def clean(self):
        """The board with nothing on it, White at the bottom, as float RGB 0..1, for the metrics."""
        if not hasattr(self, "_clean"):
            self._clean = np.asarray(self.base(False, labels=False).convert("RGB"), np.float32) / 255
        return self._clean

    def square_luma(self, file, rank):
        """A square's colour as one luminance: the median of its stone, a little in from its edges."""
        x0, y0, x1, y1 = self.square_rect(file, rank, False)
        m = self.sq * 0.08
        patch = self.clean()[int(y0 + m):int(y1 - m), int(x0 + m):int(x1 - m)]
        return float(np.median(luminance(patch.reshape(-1, 3))))

    def square_maps(self):
        """Per canvas pixel (White at the bottom): the luminance of the square under it, and whether that
        square is light (1), dark (0) or not a square at all (-1, the frame and the backdrop)."""
        if not hasattr(self, "_maps"):
            H, W, _ = self.clean().shape
            luma = np.zeros((H, W), np.float32)
            kind = np.full((H, W), -1, np.int8)
            for file in range(8):
                for rank in range(8):
                    x0, y0, x1, y1 = (int(round(v)) for v in self.square_rect(file, rank, False))
                    luma[y0:y1, x0:x1] = self.square_luma(file, rank)
                    kind[y0:y1, x0:x1] = 1 if (file + rank) % 2 == 1 else 0
            self._maps = luma, kind
        return self._maps

    def render(self, fen, flipped):
        canvas = self.base(flipped).copy()
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        placed = []
        for code, file, rank in parse_fen(fen):
            col, row = square_cell(file, rank, flipped)
            placed.append((row, col, code, file, rank))
        # Nearer rows draw last, so tall pieces overlap the ones behind them (zIndex = row).
        for row, col, code, file, rank in sorted(placed):
            fx, fy = self.foot(file, rank, flipped)
            left, top, w, h = self.sprites.placement(self.sq, fx, fy)
            im, _ = self.sprites.drawn(code, (w, h))
            paste(layer, im, left, top)
        if self.clip:
            mask = Image.new("L", canvas.size, 0)
            n = int(round(self.side))
            ImageDraw.Draw(mask).rounded_rectangle([self.pad, self.top, self.pad + n - 1, self.top + n - 1],
                                                   radius=self.sq * 0.12, fill=255)
            layer.putalpha(Image.fromarray(np.minimum(np.asarray(layer)[..., 3], np.asarray(mask))))
        canvas.alpha_composite(layer)
        return canvas.convert("RGB")


def paste(dst, src, left, top):
    """alpha_composite that accepts positions partly off the canvas."""
    x0, y0 = max(0, left), max(0, top)
    x1, y1 = min(dst.width, left + src.width), min(dst.height, top + src.height)
    if x1 <= x0 or y1 <= y0:
        return
    dst.alpha_composite(src.crop((x0 - left, y0 - top, x1 - left, y1 - top)), (x0, y0))


# MARK: - Masks

def erode(mask, r):
    if r <= 0:
        return mask
    im = Image.fromarray(mask.astype(np.uint8) * 255)
    return np.asarray(im.filter(ImageFilter.MinFilter(2 * r + 1))) > 127


def bbox(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def iou(a, b):
    union = np.logical_or(a, b).sum()
    return float(np.logical_and(a, b).sum() / union) if union else 0.0


def normalized(body, foot_x, height, nearest=False):
    """The body scaled to `height` px tall (top of the piece to its lowest pixel), its foot at the
    centre of a canvas twice as wide: two shapes compared this way have their feet aligned."""
    width = 2 * height
    x0, y0, x1, y1 = bbox(body)
    s = height / (y1 - y0)
    w = max(1, int(round((x1 - x0) * s)))
    if nearest:
        small = np.asarray(Image.fromarray(body[y0:y1, x0:x1]).resize((w, height), Image.Resampling.NEAREST))
    else:
        crop = Image.fromarray(body[y0:y1, x0:x1].astype(np.float32), "F").resize((w, height), Image.Resampling.BOX)
        small = np.asarray(crop) >= 0.5
    canvas = np.zeros((height, width), bool)
    off = int(round(width / 2 - (foot_x - x0) * s))
    a0, a1 = max(0, off), min(width, off + w)
    if a1 > a0:
        canvas[:, a0:a1] = small[:, a0 - off:a1 - off]
    return canvas


def head(mask):
    return mask[:max(1, int(round(mask.shape[0] * HEAD)))]


class Shapes:
    """The opaque bodies of one set's twelve pieces, with the x of the foot each stands on."""

    def __init__(self, name, bodies, feet_x, sprites=None):
        self.name, self.bodies, self.feet_x, self.sprites = name, bodies, feet_x, sprites
        self._squint = {}

    @classmethod
    def from_sprites(cls, s):
        return cls(s.prefix, s.body, {c: s.foot[0] for c in CODES}, s)

    @classmethod
    def from_folder(cls, name, folder):
        """A reference set: twelve PNGs (wK.png ... bP.png, or with any prefix) on a transparent ground."""
        bodies, feet = {}, {}
        for code in CODES:
            hits = sorted(Path(folder).glob(f"*{code}.png"))
            if not hits:
                return None
            a = np.asarray(Image.open(hits[0]).convert("RGBA"), np.float32)[..., 3] / 255
            body = a >= 0.5
            if not body.any():
                return None
            bodies[code] = body
            # The foot: the middle of the lowest tenth of the piece (its base).
            x0, y0, x1, y1 = bbox(body)
            low = body[int(y1 - 0.1 * (y1 - y0)):y1]
            cols = np.nonzero(low.any(0))[0]
            feet[code] = (cols.min() + cols.max() + 1) / 2
        return cls(name, bodies, feet)

    def squint(self, code):
        if code not in self._squint:
            self._squint[code] = normalized(self.bodies[code], self.feet_x[code], SQUINT_PX)
        return self._squint[code]


def pair_ious(shapes, side):
    """24 px IoU of every pair of one side, over the head and the whole silhouette."""
    m = {t: shapes.squint(side + t) for t in TYPES}
    return {p: dict(head=iou(head(m[p[0]]), head(m[p[1]])), whole=iou(m[p[0]], m[p[1]])) for p in PAIRS}


def families(sets):
    """Groups of the app's sets made from the same models (their masks nearly the same)."""
    groups = []
    for name, s in sets.items():
        for g in groups:
            first = sets[g[0]]
            if np.median([iou(s.squint(c), first.squint(c)) for c in CODES]) >= FAMILY_IOU:
                g.append(name)
                break
        else:
            groups.append([name])
    return {name: i for i, g in enumerate(groups) for name in g}


# MARK: - Silhouettes

PARTNERS = {"R": "P", "P": "RB", "B": "PQ", "Q": "KB", "K": "Q"}


def nearest(shapes, code, library):
    """Binary nearest-neighbour test on the brief's pairs: the best whole-shape IoU with any other set's
    piece of the same type against the best with any of its partner types."""
    mine = shapes.squint(code)
    kind = code[1]
    own, rival = (0.0, None), (0.0, None)
    for other in library:
        for c in CODES:
            if c[1] != kind and c[1] not in PARTNERS[kind]:
                continue
            v = iou(mine, other.squint(c))
            if c[1] == kind and v > own[0]:
                own = (v, f"{other.name}{c}")
            elif c[1] != kind and v > rival[0]:
                rival = (v, f"{other.name}{c}")
    return dict(own=round(own[0], 3), own_match=own[1], rival=round(rival[0], 3), rival_match=rival[1],
                ok=own[0] >= rival[0])


def silhouettes(sets, references):
    """Per app set and side: heights, pairwise IoU (24 px and at 1x), the brief's rules, nearest neighbours."""
    sq1 = BOARD_PT / 9
    fam = families(sets)
    out = {}
    for prefix, sh in sets.items():
        s = sh.sprites
        library = [o for n, o in sets.items() if fam[n] != fam[prefix]] + list(references)
        sides = {}
        for side in "wb":
            heights, top_widths, info, onboard = {}, {}, {}, {}
            for kind in TYPES:
                code = side + kind
                body = s.body[code]
                x0, y0, x1, y1 = bbox(body)
                h_px = s.foot[1] - y0
                heights[kind] = h_px / PX_PER_SQUARE
                rows = body[y0:y0 + max(1, int(round(h_px / 3)))]
                top_widths[kind] = max(np.ptp(np.nonzero(r)[0]) + 1 for r in rows if r.any()) / PX_PER_SQUARE
                m1, f1 = s.onboard_mask(code, sq1)
                bb = bbox(m1)
                onboard[kind] = (m1, normalized(m1, f1, ONBOARD_PX, nearest=True))
                info[kind] = dict(height=round(heights[kind], 3), top_width=round(top_widths[kind], 3),
                                  board_px=dict(w=int(bb[2] - bb[0]), h=int(bb[3] - bb[1])))
            ious = pair_ious(sh, side)
            pairs = {}
            for p in PAIRS:
                a, b = p
                tall, short = max(heights[a], heights[b]), min(heights[a], heights[b])
                pairs[p] = dict(
                    head24=round(ious[p]["head"], 3), whole24=round(ious[p]["whole"], 3),
                    head1x=round(iou(head(onboard[a][1]), head(onboard[b][1])), 3),
                    whole1x=round(iou(onboard[a][1], onboard[b][1]), 3),
                    drawn1x=round(iou(onboard[a][0], onboard[b][0]), 3),
                    height_ratio=round(tall / short, 3) if short > 0 else 99.0,
                    envelope=REF_HEAD[p], excess=round(ious[p]["head"] - REF_HEAD[p], 3))
            problems, warnings = [], []
            for p in NAMED_PAIRS:
                r = pairs[p]
                if r["head24"] > r["envelope"]:
                    problems.append(f"{NAMES[p[0]]} vs {NAMES[p[1]]}: tops more alike than in any of {REF_SETS} "
                                    f"reference sets (24 px head IoU {r['head24']:.2f} > {r['envelope']:.2f})")
            for p in PAIRS:
                r = pairs[p]
                if p not in NAMED_PAIRS and r["head24"] > r["envelope"] and r["height_ratio"] < SIZE_APART:
                    warnings.append(f"{NAMES[p[0]]} vs {NAMES[p[1]]}: tops alike (head IoU {r['head24']:.2f} > "
                                    f"{r['envelope']:.2f}), heights only x{r['height_ratio']:.2f} apart")
            nn = {kind: nearest(sh, side + kind, library) for kind in PARTNERS} if library else {}
            for kind, r in nn.items():
                if not r["ok"]:
                    warnings.append(f"{NAMES[kind]}'s shape is nearer {r['rival_match']} ({r['rival']:.2f}) "
                                    f"than any other {NAMES[kind]} ({r['own_match']} {r['own']:.2f})")
            rook_pawn = dict(height_ratio=round(heights["R"] / heights["P"], 3),
                             top_width_ratio=round(top_widths["R"] / top_widths["P"], 3))
            if rook_pawn["height_ratio"] < ROOK_HEIGHT_MIN:
                problems.append(f"rook only x{rook_pawn['height_ratio']:.2f} the pawn's height (needs x{ROOK_HEIGHT_MIN})")
            if rook_pawn["top_width_ratio"] < ROOK_TOP_MIN:
                problems.append(f"rook's top only x{rook_pawn['top_width_ratio']:.2f} the pawn head's width "
                                f"(needs x{ROOK_TOP_MIN})")
            if max(heights, key=heights.get) != "K":
                problems.append(f"the king is not the tallest ({NAMES[max(heights, key=heights.get)]} is)")
            if min(heights, key=heights.get) != "P":
                problems.append(f"the pawn is not the smallest ({NAMES[min(heights, key=heights.get)]} is)")
            order = [heights[t] for t in HEIGHT_ORDER]
            steps = {HEIGHT_ORDER[i] + ">" + HEIGHT_ORDER[i + 1]: round(order[i] - order[i + 1], 3)
                     for i in range(len(order) - 1)}
            for key, step in steps.items():
                if step < HEIGHT_STEP:
                    warnings.append(f"height order {key}: {step:+.3f} squares (tournament order wants "
                                    f"≥ {HEIGHT_STEP:.2f})")
            worst = sorted(pairs.items(), key=lambda kv: -kv[1]["excess"])[:3]
            sides[side] = dict(pieces=info, pairs=pairs, nearest=nn, height_steps=steps, rook_pawn=rook_pawn,
                               worst_pairs=[dict(pair=k, **v) for k, v in worst],
                               problems=problems, warnings=warnings, ok=not problems)
        out[prefix] = dict(contract=s.contract_name, k=s.c["k"], lift=s.c["lift"], source=s.source,
                           size=list(s.size), family=fam[prefix],
                           family_members=sorted(n for n in sets if fam[n] == fam[prefix]),
                           nearest_library=[o.name for o in library],
                           sides=sides, ok=all(v["ok"] for v in sides.values()))
    return out


def calibrate(ref_dir, out):
    """The reference envelope from a folder of piece sets (one subfolder of twelve PNGs per set)."""
    refs = [sh for d in sorted(Path(ref_dir).iterdir()) if d.is_dir()
            for sh in [Shapes.from_folder(d.name, d)] if sh is not None]
    if not refs:
        raise SystemExit(f"{ref_dir}: no reference sets (subfolders with wK.png ... bP.png)")
    table = {p: dict(head=[], whole=[]) for p in PAIRS}
    worst = {}
    for sh in refs:
        for side in "wb":
            ious = pair_ious(sh, side)
            for p in PAIRS:
                table[p]["head"].append(ious[p]["head"])
                table[p]["whole"].append(ious[p]["whole"])
        w = pair_ious(sh, "w")
        k = max(PAIRS, key=lambda p: w[p]["head"])
        worst[sh.name] = (k, round(w[k]["head"], 3))
    nn_fail, nn_total = 0, 0
    for sh in refs:
        library = [o for o in refs if o is not sh]
        for side in "wb":
            for kind in PARTNERS:
                nn_total += 1
                nn_fail += not nearest(sh, side + kind, library)["ok"]
    stats = {p: {key: dict(max=round(max(v), 2), p90=round(float(np.percentile(v, 90)), 2),
                           median=round(float(np.median(v)), 2)) for key, v in table[p].items()} for p in PAIRS}
    report = dict(sets=[sh.name for sh in refs], pairs=stats, worst_pair_per_set=worst,
                  nearest_failures=dict(failed=nn_fail, of=nn_total))
    out.mkdir(parents=True, exist_ok=True)
    (out / "calibration.json").write_text(json.dumps(report, indent=1))
    print(f"{len(refs)} reference sets: {', '.join(sh.name for sh in refs)}")
    print("REF_HEAD = {" + ", ".join(f'"{p}": {stats[p]["head"]["max"]:.2f}' for p in PAIRS) + "}")
    print("REF_WHOLE = {" + ", ".join(f'"{p}": {stats[p]["whole"]["max"]:.2f}' for p in PAIRS) + "}")
    print("head p90:", {p: stats[p]["head"]["p90"] for p in PAIRS})
    print(f"nearest-neighbour test: {nn_fail} of {nn_total} reference pieces fail it")
    print(f"wrote {out / 'calibration.json'}")
    return 0


# MARK: - Contours

# The squares the pieces are measured on: the middle of the board, White at the bottom (8 light, 8 dark).
SAMPLE_SQUARES = [(f, r) for r in range(2, 6) for f in range(2, 6)]
SHOW_SQUARES = dict(light=(4, 3), dark=(3, 3))   # e4 and d4


def piece_on(board, code, file, rank):
    """One piece alone on a clean board (White at the bottom): composite, body mask, offsets."""
    s = board.sprites
    fx, fy = board.foot(file, rank, False)
    left, top, w, h = s.placement(board.sq, fx, fy)
    im, cover = s.drawn(code, (w, h))
    clean = board.clean()
    H, W, _ = clean.shape
    x0, y0, x1, y1 = max(0, left), max(0, top), min(W, left + w), min(H, top + h)
    sx0, sy0 = x0 - left, y0 - top
    rgba = np.asarray(im, np.float32)[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)] / 255
    bg = clean[y0:y1, x0:x1]
    a = rgba[..., 3:4]
    out = rgba[..., :3] * a + bg * (1 - a)
    mask = cover[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)] >= 0.5
    return out, mask, (x0, y0)


def band_pixels(board, code, file, rank):
    """The contour band of one placement: its luminance, the luminance and kind of the square under each
    band pixel, and whether the pixel is in the top half of the piece."""
    out, mask, (ox, oy) = piece_on(board, code, file, rank)
    band = mask & ~erode(mask, max(1, int(round(BAND_PT * board.scale))))
    luma, kind = board.square_maps()
    h, w = mask.shape
    sq_y = luma[oy:oy + h, ox:ox + w]
    sq_k = kind[oy:oy + h, ox:ox + w]
    _, y0, _, y1 = bbox(mask)
    top = np.zeros_like(mask)
    top[:int((y0 + y1) / 2)] = True
    keep = band & (sq_k >= 0)
    return luminance(out)[keep], sq_y[keep], sq_k[keep], top[keep]


def contours(board):
    """Per side, type and square colour: the band against the squares under it, pooled over 16 squares."""
    result = {}
    for side in "wb":
        by_color = {"light": {}, "dark": {}}
        for kind in TYPES:
            parts = [band_pixels(board, side + kind, f, r) for f, r in SAMPLE_SQUARES]
            y_band = np.concatenate([p[0] for p in parts])
            y_sq = np.concatenate([p[1] for p in parts])
            k_sq = np.concatenate([p[2] for p in parts])
            top = np.concatenate([p[3] for p in parts])
            for color, flag in (("light", 1), ("dark", 0)):
                sel = k_sq == flag
                if not sel.any():
                    continue
                r = wcag(y_band[sel], y_sq[sel])
                l_band, l_sq = lightness(y_band[sel]), lightness(y_sq[sel])
                t = top[sel]
                by_color[color][kind] = dict(
                    wcag=round(float(np.median(r)), 2),
                    outline=round(float((r >= WCAG_MIN).mean()), 3),
                    top_outline=round(float((r[t] >= WCAG_MIN).mean()), 3) if t.any() else None,
                    delta_l=round(float(np.median(np.abs(l_band - l_sq))), 1),
                    band_l=round(float(np.median(l_band)), 1), square_l=round(float(np.median(l_sq)), 1),
                    pixels=int(sel.sum()))
        result[side] = {}
        for color, types in by_color.items():
            worst = min(types, key=lambda t: types[t]["wcag"])
            result[side][color] = dict(types=types, worst=worst, min_wcag=types[worst]["wcag"],
                                       ok=all(t["wcag"] >= WCAG_MIN for t in types.values()))
    return result


# MARK: - Sheets

INK = (236, 233, 226)
MUTED = (150, 146, 140)
GOOD = (120, 200, 140)
BAD = (240, 110, 100)
WARN = (235, 190, 90)
PAPER = (22, 22, 24)


def lineup_cell(board, code, color, cell_w, cell_h, contour_map=False):
    """A crop of the board around a real light or dark square with one piece standing on it."""
    file, rank = SHOW_SQUARES[color]
    canvas = board.base(False, labels=False).copy()
    fx, fy = board.foot(file, rank, False)
    left, top, w, h = board.sprites.placement(board.sq, fx, fy)
    im, _ = board.sprites.drawn(code, (w, h))
    paste(canvas, im, left, top)
    if contour_map:
        # The band in green where it reaches 3:1 against the square under it, red where it does not.
        out, mask, (ox, oy) = piece_on(board, code, file, rank)
        band = mask & ~erode(mask, max(1, int(round(BAND_PT * board.scale))))
        luma, kind = board.square_maps()
        hh, ww = mask.shape
        r = wcag(luminance(out), luma[oy:oy + hh, ox:ox + ww])
        arr = np.asarray(canvas.convert("RGB")).copy()
        region = arr[oy:oy + hh, ox:ox + ww]
        region[band & (r >= WCAG_MIN)] = (40, 220, 90)
        region[band & (r < WCAG_MIN)] = (255, 40, 40)
        canvas = Image.fromarray(arr).convert("RGBA")
    x0, y0, x1, y1 = board.square_rect(file, rank, False)
    cx = (x0 + x1) / 2
    box = (int(round(cx - cell_w / 2)), int(round(y1 - cell_h + board.sq * 0.25)),
           int(round(cx + cell_w / 2)), int(round(y1 + board.sq * 0.25)))
    return canvas.crop(box).convert("RGB")


def text_block(lines, size, color=INK, width=None, line_gap=1.25):
    f = font(size)
    h = int(math.ceil(len(lines) * size * line_gap)) + 4
    w = width or int(max([f.getlength(l if isinstance(l, str) else l[0]) for l in lines] + [10])) + 8
    im = Image.new("RGB", (w, h), PAPER)
    d = ImageDraw.Draw(im)
    for i, l in enumerate(lines):
        text, c = (l, color) if isinstance(l, str) else l
        d.text((4, 2 + i * size * line_gap), text, font=f, fill=c)
    return im


def stack(images, horizontal=False, gap=12, bg=PAPER):
    images = [i for i in images if i is not None]
    if horizontal:
        W = sum(i.width for i in images) + gap * (len(images) - 1)
        H = max(i.height for i in images)
    else:
        W = max(i.width for i in images)
        H = sum(i.height for i in images) + gap * (len(images) - 1)
    out = Image.new("RGB", (W, H), bg)
    pos = 0
    for i in images:
        out.paste(i, (pos, 0) if horizontal else (0, pos))
        pos += (i.width if horizontal else i.height) + gap
    return out


def verdict_color(ok):
    return GOOD if ok else BAD


def mask_image(mask, zoom, fg=(240, 238, 232), bg=(48, 48, 52), head_rows=None):
    rgb = np.where(mask[..., None], np.array(fg, np.uint8), np.array(bg, np.uint8)).astype(np.uint8)
    if head_rows:
        # The head the gate compares, tinted.
        rgb[:head_rows] = np.where(mask[:head_rows, :, None], np.array((250, 200, 120), np.uint8),
                                   np.array((70, 60, 48), np.uint8))
    im = Image.fromarray(rgb, "RGB")
    return im.resize((im.width * zoom, im.height * zoom), Image.Resampling.NEAREST)


def look_sheet(look, sil, con, boards_1x, board1, board3, sh):
    prefix = look["piece_set"]
    ok_sil = sil["ok"]
    gate = con[GATE_SCALE]
    ok_con = all(gate[s][c]["ok"] for s in "wb" for c in ("light", "dark"))
    title = text_block([(f"{look['name']}  ·  {prefix}  ·  sprites {sil['contract']} {sil['size'][0]}x{sil['size'][1]}"
                         f"  ·  k {sil['k']}  lift {sil['lift']}  ·  board {BOARD_PT:.0f} pt", INK),
                        (("PASS" if ok_sil and ok_con else "FAIL") + f"   silhouettes {'ok' if ok_sil else 'FAIL'}"
                         f"   contours {'ok' if ok_con else 'FAIL'}", verdict_color(ok_sil and ok_con))], 26)
    # The six boards at 1x: what the eye gets.
    tiles = []
    for (fen_name, flipped), im in boards_1x:
        cap = text_block([f"{fen_name} · {'Black' if flipped else 'White'} at the bottom · 1x"], 15, MUTED)
        tiles.append(stack([im, cap], gap=2))
    boards_row = stack(tiles, horizontal=True, gap=14)
    # 3x close-ups of the back ranks of the first middlegame.
    mid = board3.render(FENS["mid1"], False)
    sq3 = board3.sq
    top_crop = mid.crop((0, 0, mid.width, int(board3.top + board3.inset + 2.3 * sq3)))
    bottom_crop = mid.crop((0, int(board3.top + board3.inset + 5.2 * sq3), mid.width, mid.height))
    close = stack([text_block(["3x close-up (device pixels): mid1, ranks 8-7 and 2-1"], 15, MUTED),
                   stack([top_crop, bottom_crop], horizontal=True, gap=14)], gap=2)
    # The lineup: twelve pieces on a light and a dark square, 1x (true size and magnified) and 3x.
    rows = []
    for side in "wb":
        for color in ("light", "dark"):
            m3, m1 = con[3][side][color], con[1][side][color]
            cells1, cells3, maps3, labels = [], [], [], []
            for kind in TYPES:
                t3, t1 = m3["types"][kind], m1["types"][kind]
                size1 = int(round(board1.sq * 1.7)), int(round(board1.sq * 2.1))
                size3 = int(round(board3.sq * 1.7)), int(round(board3.sq * 2.1))
                cells1.append(lineup_cell(board1, side + kind, color, *size1))
                c3 = lineup_cell(board3, side + kind, color, *size3)
                cells3.append(c3)
                maps3.append(lineup_cell(board3, side + kind, color, *size3, contour_map=True))
                labels.append(text_block([(f"{NAMES[kind]}", INK),
                                          (f"3x {t3['wcag']:.2f}:1  {int(round(t3['outline'] * 100))}%",
                                           verdict_color(t3["wcag"] >= WCAG_MIN)),
                                          (f"1x {t1['wcag']:.2f}:1  {int(round(t1['outline'] * 100))}%", MUTED),
                                          (f"ΔL* {t3['delta_l']:.0f}  band L* {t3['band_l']:.0f}", MUTED)],
                                         13, width=c3.width))
            true_size = stack(cells1, horizontal=True, gap=4)
            magnified = true_size.resize((true_size.width * 3, true_size.height * 3), Image.Resampling.NEAREST)
            row3 = stack([stack([c, mp, l], gap=0) for c, mp, l in zip(cells3, maps3, labels)], horizontal=True, gap=4)
            name = look["white_name"] if side == "w" else look["black_name"]
            head_line = text_block([(f"{SIDE_NAMES[side]} ({name}) standing on a {color} square; contour against "
                                     f"{color} squares: median ≥ {WCAG_MIN:.0f}:1 needed, weakest "
                                     f"{NAMES[m3['worst']]} {m3['min_wcag']:.2f}:1 at 3x", verdict_color(m3["ok"]))], 16)
            rows.append(stack([head_line,
                               stack([stack([text_block(["1x true size"], 12, MUTED), true_size], gap=2),
                                      stack([text_block(["1x magnified x3 (nearest)"], 12, MUTED), magnified], gap=2)],
                                     horizontal=True, gap=18),
                               stack([text_block(["3x (device pixels), then the 1 pt band: green ≥ 3:1 against the "
                                                  "square under it, red below"], 12, MUTED), row3], gap=2)], gap=4))
    # Silhouettes: 24 px masks (head tinted) and the 1x masks, with the verdicts.
    sil_rows = []
    sq1 = BOARD_PT / 9
    head_rows = max(1, int(round(SQUINT_PX * HEAD)))
    for side in "wb":
        r = sil["sides"][side]
        m24 = stack([mask_image(sh.squint(side + t), 5, head_rows=head_rows) for t in TYPES], horizontal=True, gap=8)
        m1 = stack([mask_image(sh.sprites.onboard_mask(side + t, sq1)[0], 2) for t in TYPES], horizontal=True, gap=8)
        lines = [(f"{SIDE_NAMES[side]} silhouettes: {'ok' if r['ok'] else 'FAIL'}", verdict_color(r["ok"]))]
        lines += [(p, BAD) for p in r["problems"]] + [(w, WARN) for w in r["warnings"]]
        named = "   ".join(f"{NAMES[p[0]]}-{NAMES[p[1]]} {r['pairs'][p]['head24']:.2f}/{r['pairs'][p]['envelope']:.2f}"
                           for p in NAMED_PAIRS)
        lines.append((f"24 px head IoU / reference max, the brief's pairs: {named}", MUTED))
        lines.append(("most out of line: " + "   ".join(
            f"{p['pair']} head {p['head24']:.2f} (max {p['envelope']:.2f}), whole {p['whole24']:.2f}, "
            f"1x head {p['head1x']:.2f}, h x{p['height_ratio']:.2f}" for p in r["worst_pairs"]), MUTED))
        hs = "  ".join(f"{t} {r['pieces'][t]['height']:.2f}" for t in HEIGHT_ORDER)
        lines.append((f"heights above the foot (squares, before k): {hs}   rook/pawn: height x"
                      f"{r['rook_pawn']['height_ratio']:.2f}, top x{r['rook_pawn']['top_width_ratio']:.2f}", MUTED))
        sil_rows.append(stack([stack([stack([text_block([f"24 px tall, x5 (top {int(HEAD * 100)}% tinted: the head "
                                                         f"the gate compares)"], 12, MUTED), m24], gap=2),
                                      stack([text_block(["as on the board at 1x, x2"], 12, MUTED), m1], gap=2)],
                                     horizontal=True, gap=24),
                               text_block(lines, 15)], gap=4))
    sheet = stack([title, boards_row, close] + rows + sil_rows, gap=22)
    framed = Image.new("RGB", (sheet.width + 48, sheet.height + 48), PAPER)
    framed.paste(sheet, (24, 24))
    return framed


# MARK: - Run

def find_repo(start):
    p = Path(start).resolve()
    for candidate in [p] + list(p.parents):
        if (candidate / "ChessGameKiller" / "Assets.xcassets").exists():
            return candidate
    raise SystemExit("could not find the repository (a folder with ChessGameKiller/Assets.xcassets)")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="output folder (report.json, summary.md, sheets/, boards/)")
    ap.add_argument("--repo", default=Path(__file__).resolve().parent, help="the repository (default: this script's)")
    ap.add_argument("--catalog", help="asset catalog (default: <repo>/ChessGameKiller/Assets.xcassets)")
    ap.add_argument("--themes", help="BoardTheme.swift (default: <repo>/ChessGameKiller/Views/BoardTheme.swift)")
    ap.add_argument("--sprites", action="append", default=[], metavar="PREFIX=DIR",
                    help="use the sprites in DIR for this prefix (e.g. gilded-=build/new); DIR holds "
                         "<prefix>wK.png, wK.png or <prefix>wK.imageset/<prefix>wK.png. Repeatable.")
    ap.add_argument("--looks", help="only these looks, comma separated (e.g. gilded,midnight)")
    ap.add_argument("--contract", choices=sorted(CONTRACTS), help="force a sprite contract (default: from the PNG size)")
    ap.add_argument("--k", type=float, help="draw sprites at this k instead of the contract's")
    ap.add_argument("--lift", type=float, help="the foot this many squares below the square's centre")
    ap.add_argument("--reference", metavar="DIR",
                    help="extra piece sets for the nearest-neighbour test (one subfolder of twelve PNGs per set)")
    ap.add_argument("--calibrate", metavar="DIR",
                    help="only print the reference envelope measured on the sets in DIR (see README)")
    ap.add_argument("--no-sheets", action="store_true", help="metrics only, no pictures")
    a = ap.parse_args(argv)

    t0 = time.time()
    out = Path(a.out)
    if a.calibrate:
        return calibrate(a.calibrate, out)
    repo = find_repo(a.repo)
    catalog = Path(a.catalog) if a.catalog else repo / "ChessGameKiller" / "Assets.xcassets"
    themes_path = Path(a.themes) if a.themes else repo / "ChessGameKiller" / "Views" / "BoardTheme.swift"
    (out / "sheets").mkdir(parents=True, exist_ok=True)
    (out / "boards").mkdir(parents=True, exist_ok=True)

    overrides = {}
    for spec in a.sprites:
        prefix, _, folder = spec.partition("=")
        if not folder:
            raise SystemExit(f"--sprites wants PREFIX=DIR, got {spec!r}")
        overrides[prefix if prefix.endswith("-") else prefix + "-"] = Path(folder)

    themes = [t for t in parse_themes(themes_path) if t["board_art"] and t["sprite_pieces"]]
    looks = themes
    if a.looks:
        wanted = {w.strip() for w in a.looks.split(",")}
        looks = [t for t in themes if t["id"] in wanted]
    if not looks:
        raise SystemExit("no looks to check")

    # Every sprite set in the app joins the silhouette comparison, even when only some looks are drawn.
    prefixes = sorted({t["piece_set"] for t in themes})
    sprite_sets = {p: SpriteSet(p, catalog, overrides.get(p), a.contract, a.k, a.lift) for p in prefixes}
    shapes = {p: Shapes.from_sprites(s) for p, s in sprite_sets.items()}
    references = []
    if a.reference:
        references = [sh for d in sorted(Path(a.reference).iterdir()) if d.is_dir()
                      for sh in [Shapes.from_folder("ref:" + d.name + ":", d)] if sh is not None]
    sil = silhouettes(shapes, references)

    report = dict(generated=time.strftime("%Y-%m-%d %H:%M:%S"), repo=str(repo), catalog=str(catalog),
                  overrides={k: str(v) for k, v in overrides.items()},
                  references=[r.name for r in references],
                  thresholds=dict(body_alpha=BODY_ALPHA, squint_px=SQUINT_PX, head=HEAD, ref_head=REF_HEAD,
                                  ref_sets=REF_SETS, size_apart=SIZE_APART, rook_height_min=ROOK_HEIGHT_MIN,
                                  rook_top_min=ROOK_TOP_MIN, height_step=HEIGHT_STEP, band_pt=BAND_PT,
                                  wcag_min=WCAG_MIN, gate_scale=GATE_SCALE),
                  board_pt=BOARD_PT, fens=FENS, sets=sil, looks={})
    for look in looks:
        prefix = look["piece_set"]
        s = sprite_sets[prefix]
        art = find_file(catalog / "Boards", look["board_art"], (".jpg", ".png", ".jpeg"))
        if art is None:
            raise SystemExit(f"{look['id']}: no board picture {look['board_art']}")
        boards = {scale: Board(look, art, s, scale) for scale in SCALES}
        con = {scale: contours(boards[scale]) for scale in SCALES}
        squares = {}
        for color, (f, r) in SHOW_SQUARES.items():
            y = boards[1].square_luma(f, r)
            squares[color] = dict(luminance=round(y, 4), lightness=round(float(lightness(y)), 1))
        files, boards_1x, sheet_name = [], [], None
        if not a.no_sheets:
            for fen_name, fen in FENS.items():
                for flipped in (False, True):
                    for scale in SCALES:
                        im = boards[scale].render(fen, flipped)
                        name = f"{look['id']}-{fen_name}-{'black' if flipped else 'white'}-{scale}x.png"
                        im.save(out / "boards" / name)
                        files.append(f"boards/{name}")
                        if scale == 1:
                            boards_1x.append(((fen_name, flipped), im))
            sheet = look_sheet(look, sil[prefix], con, boards_1x, boards[1], boards[3], shapes[prefix])
            sheet_name = f"sheets/{look['id']}.png"
            sheet.save(out / sheet_name)
        ok_sil = sil[prefix]["ok"]
        ok_con = all(con[GATE_SCALE][side][c]["ok"] for side in "wb" for c in ("light", "dark"))
        report["looks"][look["id"]] = dict(
            name=look["name"], piece_set=prefix, board=look["board_art"], white_name=look["white_name"],
            black_name=look["black_name"], squares=squares, contour_1x=con[1], contour_3x=con[3],
            ok=dict(silhouettes=ok_sil, contours=ok_con, overall=ok_sil and ok_con),
            boards=files, sheet=sheet_name)
        print(f"{look['id']:12s} {'PASS' if ok_sil and ok_con else 'FAIL'}  silhouettes {'ok' if ok_sil else 'FAIL'}"
              f"  contours {'ok' if ok_con else 'FAIL'}", flush=True)

    (out / "report.json").write_text(json.dumps(report, indent=1))
    (out / "summary.md").write_text(summary(report))
    print(f"wrote {out / 'summary.md'}, {out / 'report.json'}"
          + ("" if a.no_sheets else f" and {len(report['looks'])} sheets") + f" in {time.time() - t0:.0f} s")
    return 0 if all(l["ok"]["overall"] for l in report["looks"].values()) else 1


def summary(report):
    th = report["thresholds"]
    lines = ["# Piece legibility", "",
             f"Generated {report['generated']} from `{report['catalog']}`"
             + (f" with overrides {report['overrides']}" if report["overrides"] else "") + ".", "",
             f"Board {report['board_pt']:.0f} pt. **Silhouettes**: each body shrunk to {th['squint_px']} px tall, feet "
             f"aligned; a pair the brief names (rook-pawn, bishop-pawn, queen-king, bishop-queen) fails when the top "
             f"{int(th['head'] * 100)}% of the two shapes overlap more (IoU) than that pair does in any of "
             f"{th['ref_sets']} widely used piece sets; plus the brief's rules (rook ≥ x{th['rook_height_min']} the "
             f"pawn's height and its top ≥ x{th['rook_top_min']} the pawn's head, king tallest, pawn smallest). "
             f"**Contours**: a {th['band_pt']:g} pt band just inside the opaque silhouette against the square under "
             f"it; every type needs a median of {th['wcag_min']:g}:1 (WCAG non-text contrast) against light and "
             f"against dark squares, both sides, at {th['gate_scale']}x (1x in the report).", "",
             "| Look | Set | Result | Silhouettes | Most out of line (24 px head IoU / max) | White vs light / dark | Black vs light / dark |",
             "|---|---|---|---|---|---|---|"]
    for lid, l in report["looks"].items():
        s = report["sets"][l["piece_set"]]
        sil = []
        for side in "wb":
            r = s["sides"][side]
            sil.append(f"{side}: " + ("ok" if r["ok"] else "; ".join(r["problems"][:3])
                                      + (f" (+{len(r['problems']) - 3})" if len(r["problems"]) > 3 else "")))
        if sil[0][3:] == sil[1][3:]:
            sil = ["both: " + sil[0][3:]]
        worst = ", ".join(f"{p['pair']} {p['head24']:.2f}/{p['envelope']:.2f}" for p in s["sides"]["w"]["worst_pairs"])

        def cell(side):
            parts = []
            for c in ("light", "dark"):
                m = l["contour_3x"][side][c]
                t = m["types"][m["worst"]]
                parts.append(f"{'ok' if m['ok'] else '**FAIL**'} {m['worst']} {t['wcag']:.2f}:1 "
                             f"({int(round(t['outline'] * 100))}%)")
            return " / ".join(parts)

        lines.append(f"| {l['name']} | `{l['piece_set']}` {s['contract']} | "
                     f"{'PASS' if l['ok']['overall'] else '**FAIL**'} | {'<br>'.join(sil)} | {worst} | "
                     f"{cell('w')} | {cell('b')} |")
    lines += ["", "Contour cells: verdict, the weakest type, the median contrast of its band against those squares "
              "at 3x, and in brackets the share of the band at 3:1 or more. Square lightness (L*, e4 and d4) per look:", ""]
    lines += [f"- {l['name']}: light {l['squares']['light']['lightness']}, dark {l['squares']['dark']['lightness']}"
              for l in report["looks"].values()]
    lines += ["", "Sheets: `sheets/<look>.png`; boards: `boards/<look>-<position>-<side at the bottom>-<scale>.png`; "
              "every number: `report.json`.", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    sys.exit(main())
