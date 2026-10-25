#!/usr/bin/env python3
"""Exports the app's board looks for the browser game (play/public).

Reads every look in ChessGameKiller/Views/BoardTheme.swift and writes:
  play/public/looks/boards/{look}.webp   the board picture (looks that have one)
  play/public/looks/{set}/{wK..bP}.webp  the 3D piece pictures, baked shadow taken out as the app does
  play/public/looks/neon/*.svg           Neon's vector pieces
  play/public/looks.css                  one block per look: colors, board picture, piece pictures

The browser shows the look the friend who sent the link plays with in the app.
Run from the repo root after changing a look: python3 scripts/play/export_looks.py
"""
import json
import re
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
THEME = ROOT / "ChessGameKiller/Views/BoardTheme.swift"
ASSETS = ROOT / "ChessGameKiller/Assets.xcassets"
OUT = ROOT / "play/public/looks"
CSS = ROOT / "play/public/looks.css"
PIECES = [c + k for c in "wb" for k in "KQRBNP"]

# The side-on sprite contract (SpriteFrame.sideOn in BoardView.swift), in squares.
WIDTH, HEIGHT, FOOT, SCALE, LIFT = 1.4, 1.9, 1.5, 1.2, 0.24
SHADOW_ALPHA = 215  # BoardSprite.shadowAlpha
SPRITE_SIZE = (280, 380)  # half the app's 560 x 760: sharp at three times a phone's square
BOARD_SIZE = 1152

GOLD_WASH = "rgba(217, 169, 43, 0.38)"
GREEN_WASH = "rgba(185, 194, 74, 0.45)"


def rgba(expr, default_alpha=1.0):
    """A Swift Color expression as CSS."""
    expr = expr.strip()
    if "goldWash" in expr:
        return GOLD_WASH
    if "greenWash" in expr:
        return GREEN_WASH
    alpha = default_alpha
    m = re.search(r"\.opacity\(([\d.]+)\)", expr)
    if m:
        alpha = float(m.group(1))
    m = re.search(r"0x([0-9A-Fa-f]{6})", expr)
    if m:
        h = int(m.group(1), 16)
        r, g, b = h >> 16, (h >> 8) & 255, h & 255
    elif "Color.white" in expr or expr.startswith(".white"):
        r = g = b = 255
    else:
        raise ValueError(f"can't read color {expr!r}")
    return f"rgba({r}, {g}, {b}, {alpha:g})"


def field(block, name):
    m = re.search(rf"\b{name}: (.+?)(?:,\n|\n\s*\))", block)
    return m.group(1).strip() if m else None


def looks():
    src = THEME.read_text()
    out = {}
    for m in re.finditer(r"static let (\w+) = (BoardTheme|rivalTheme)\((.*?)\n    \)\n", src, re.S):
        name, kind, block = m.groups()
        look = {"id": name}
        if kind == "rivalTheme":
            accent = field(block, "accent")
            look.update(
                light=rgba(field(block, "light")), dark=rgba(field(block, "dark")),
                coordLight=rgba(field(block, "labelOnLight")), coordDark=rgba(field(block, "labelOnDark")),
                sel=rgba(field(block, "selected"), 0.22) if True else None,
                last=rgba(field(block, "lastMove") or "goldWash"),
                hint=rgba(re.sub(r"\.opacity\(.*", "", accent), 0.9),
                set=name, art=f"board-{name}",
            )
            look["sel"] = rgba(re.sub(r"\.opacity\(.*", "", field(block, "selected")) + ".opacity(0.22)")
        else:
            art = field(block, "boardArt")
            look.update(
                light=rgba(field(block, "light")), dark=rgba(field(block, "dark")),
                coordLight=rgba(field(block, "labelOnLight")), coordDark=rgba(field(block, "labelOnDark")),
                sel=rgba(field(block, "selected")), last=rgba(field(block, "lastMove")),
                hint=rgba(field(block, "hint")),
                set=field(block, "pieceSet").strip('"').rstrip("-"),
                art=art.strip('"') if art else None,
            )
            surface = field(block, "surface")
            if surface and surface != "nil":
                look["surface"] = [rgba(c) for c in re.findall(r"Color\(hex: 0x[0-9A-Fa-f]{6}\)", surface)]
        out[name] = look
    return out


def without_shadow(im):
    """The app's BoardSprite.withoutShadow: clears the baked shadow, stretches the body's edge."""
    im = im.convert("RGBA")
    span = 255 - SHADOW_ALPHA
    a = im.getchannel("A").point(lambda v: 0 if v <= SHADOW_ALPHA else (v - SHADOW_ALPHA) * 255 // span)
    im.putalpha(a)
    return im


def solid_mid_x(im):
    """The middle of the piece's body (alpha above the shadow's), as a fraction of the width."""
    box = im.getchannel("A").point(lambda v: 255 if v > SHADOW_ALPHA else 0).getbbox()
    return 0.5 if not box else (box[0] + box[2]) / 2 / im.width


STATIC = """
/* ---- Looks with a board picture: the picture, frame and all, behind the squares ---------- */
/* The picture is nine squares wide (a half-square frame round the board), so the board keeps
   its outer size and the squares shrink to fit the frame inside it. */
{art} .board {{
  --sq: calc(var(--board-size) / 9);
  width: calc(var(--sq) * 8);
  height: calc(var(--sq) * 8);
  margin: calc(var(--sq) / 2);
  border-radius: 0;
  background: none;
  box-shadow: none;
}}
{art} .board::before {{
  content: "";
  position: absolute;
  inset: -6.25%;
  border-radius: 6px;
  background: var(--board-art) 0 0 / 100% 100% no-repeat;
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.07), 0 30px 70px -10px rgba(0, 0, 0, 0.7);
  pointer-events: none;
}}
{art} .board.flipped::before {{ transform: rotate(180deg); }}
{art} .squares {{ border-radius: 0; }}

/* ---- 3D pieces: they stand on their square and rise above it, as in the app -------------- */
/* SpriteFrame.sideOn: the picture is 1.68 x 2.28 squares, its center 0.42 squares above the
   square's center, nudged across by --shift so the piece's body is centered. */
{sprite} .pc {{ background-image: none; filter: none; }}
{sprite} .pc::before {{
  content: "";
  position: absolute;
  left: calc(-34% + var(--shift, 0) * 100%);
  top: -106%;
  width: 168%;
  height: 228%;
  background: var(--img) 0 0 / 100% 100% no-repeat;
}}
{sprite} .pc.w::before {{ filter: drop-shadow(0 0 0.5px rgba(0, 0, 0, 0.6)); }}
{sprite} .drag-ghost, {sprite} .promo-piece {{
  background-image: var(--img);
  background-size: contain;
  background-position: 50% 70%;
  background-repeat: no-repeat;
}}
{sprite} .promo-piece {{ width: 96%; height: 96%; }}

/* A sliding piece passes over the others; the rest stand in front of the rank behind them. */
.pc.moving {{ z-index: 20 !important; }}

/* ---- Neon: glowing glass squares over a color sweep ------------------------------------- */
[data-look="neon"] .board {{
  background:
    repeating-conic-gradient(var(--dark) 0 25%, var(--light) 0 50%) 0 0 / 25% 25%,
    var(--surface);
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.35), 0 0 40px rgba(60, 220, 230, 0.3), 0 0 60px rgba(200, 70, 220, 0.3);
}}
[data-look="neon"] .pc.w {{ filter: drop-shadow(0 0 calc(var(--sq) * 0.05) rgba(255, 170, 70, 0.95)); }}
[data-look="neon"] .pc.b {{ filter: drop-shadow(0 0 calc(var(--sq) * 0.05) rgba(170, 110, 255, 0.95)); }}
"""


def default_look():
    m = re.search(r"static let all: \[BoardTheme\] = \[\s*\.(\w+)", THEME.read_text())
    return m.group(1)


def main():
    import sys
    css_only = "--css-only" in sys.argv
    all_looks = looks()
    if not css_only:
        if OUT.exists():
            shutil.rmtree(OUT)
        (OUT / "boards").mkdir(parents=True)
    shifts = {}
    css = [
        "/* Generated by scripts/play/export_looks.py from the app's BoardTheme.swift. Do not edit. */",
        "/* The browser shows the look of the friend who sent the link (html[data-look], set in looks.js). */",
        "",
    ]
    art_looks, sprite_looks = [], []
    for look in all_looks.values():
        lid, pset = look["id"], look["set"]
        if look["art"]:
            art_looks.append(lid)
            if not css_only:
                board = Image.open(next((ASSETS / "Boards" / f"{look['art']}.imageset").glob("*.jpg"))).convert("RGB")
                board.resize((BOARD_SIZE, BOARD_SIZE), Image.LANCZOS).save(OUT / "boards" / f"{lid}.webp", quality=86, method=6)
        if pset and pset not in shifts:
            shifts[pset] = {}
            if not css_only:
                (OUT / pset).mkdir()
            for code in PIECES:
                folder = ASSETS / "Pieces" / f"{pset}-{code}.imageset"
                svg = list(folder.glob("*.svg"))
                if svg:
                    if not css_only:
                        shutil.copy(svg[0], OUT / pset / f"{code}.svg")
                    continue
                im = without_shadow(Image.open(next(folder.glob("*.png"))))
                shifts[pset][code] = (0.5 - solid_mid_x(im)) * WIDTH * SCALE
                if not css_only:
                    im.resize(SPRITE_SIZE, Image.LANCZOS).save(OUT / pset / f"{code}.webp", quality=88, method=6)

        sel = f'[data-look="{lid}"]'
        css.append(f"{sel} {{")
        for var, key in [("light", "light"), ("dark", "dark"), ("sel", "sel"), ("last", "last"),
                         ("hint", "hint"), ("coord-light", "coordLight"), ("coord-dark", "coordDark")]:
            css.append(f"  --{var}: {look[key]};")
        if look["art"]:
            css.append(f"  --board-art: url(/looks/boards/{lid}.webp);")
        if look.get("surface"):
            css.append(f"  --surface: linear-gradient(135deg, {', '.join(look['surface'])});")
        css.append("}")
        if pset:
            sprite = bool(shifts[pset])
            if sprite:
                sprite_looks.append(lid)
            for code in PIECES:
                if sprite:
                    rule = f"{sel} .{code} {{ --img: url(/looks/{pset}/{code}.webp);"
                    if abs(shifts[pset][code]) > 0.001:
                        rule += f" --shift: {shifts[pset][code]:.4f};"
                else:
                    rule = f"{sel} .{code} {{ background-image: url(/looks/{pset}/{code}.svg);"
                css.append(rule + " }")
        # else: the classic printed pieces in /pieces, as app.css draws them
        css.append("")

    group = lambda ids: ":is(" + ", ".join(f'[data-look="{i}"]' for i in ids) + ")"
    css.append(STATIC.format(art=group(art_looks), sprite=group(sprite_looks)).strip())
    CSS.write_text("\n".join(css) + "\n")

    ids = sorted(all_looks)
    (ROOT / "play/public/looks.js").write_text(
        "// Generated by scripts/play/export_looks.py from the app's BoardTheme.swift. Do not edit.\n"
        "// Every board look in the app; the browser shows the one the friend who sent the link uses.\n\n"
        f"export const LOOKS = {json.dumps(ids)};\n"
        f"export const DEFAULT_LOOK = {json.dumps(default_look())};\n\n"
        "/** Shows a look on every board on the page: the app's default for a game without one. */\n"
        "export function setLook(id) {\n"
        "  const look = LOOKS.includes(id) ? id : DEFAULT_LOOK;\n"
        "  if (document.documentElement.dataset.look !== look) document.documentElement.dataset.look = look;\n"
        "  return look;\n"
        "}\n"
    )
    print("looks:", ", ".join(ids), "| default:", default_look())


if __name__ == "__main__":
    main()
