# The gilded set, modeled on a black-and-gold knight artwork. Polished black (or ivory) stone with gold:
# a stepped base with a recessed gold band under each piece, gold bands on the bodies and
# gold crowns, and the knight with its striped gold mane and amber eye.
# The tops and heights are the classic set's (pieces.py), so both sets are read the same way.
# The knight's head, mane and eyes come from knight_icon.py (load_knight reads them).
import bpy, bmesh, math, numpy as np, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pieces import (arc, bead, cove, ogee, line, lathe, uvsphere, rbox, cut, group, mitre_profile, mitre_cut,
                    prism, crenel, shade, ring_lathe, merlon_caps, TAU,
                    beads, gadroons, compose, radius_at, slits, FRONT,
                    pattee, squash_above, cross_finish, crown_gems, KING_H, LATIN_TOP, QUEEN_TOP, QUEEN_H)

FOOT = 0.118          # top of every base: the piece's body starts here


def steps_profile(R):
    """Two stone steps and the core under the gold band; ends at the band's top."""
    p = [(0, 0), (R - 0.008, 0), (R, 0.008)]
    p += line(R, 0.008, R, 0.028, 2)
    p += arc(R - 0.022, 0.028, 0.022, 0, math.pi / 2, 8)            # round top edge of the lower step
    p += line(R - 0.022, 0.05, R - 0.032, 0.05, 1)
    p += line(R - 0.032, 0.05, R - 0.032, 0.062, 1)                  # the upper step
    p += arc(R - 0.04, 0.062, 0.008, 0, math.pi / 2, 5)
    p += line(R - 0.04, 0.07, R - 0.072, 0.07, 2)
    p += line(R - 0.072, 0.07, R - 0.072, 0.096, 2)                  # core, hidden by the band
    return p


def base_profile(R):
    """The steps, then the round foot the body stands on; ends at (R - 0.056, FOOT)."""
    p = steps_profile(R)
    p += line(R - 0.072, 0.096, R - 0.056, 0.096, 2)                 # underside of the foot
    p += arc(R - 0.056, 0.102, 0.006, -math.pi / 2, 0, 4)
    p += arc(R - 0.056, 0.112, 0.006, 0, math.pi / 2, 4)
    return p


def band_beads(name, R, M):
    """Gold beads strung along the recessed band, so it reads as a row of pearls in gold."""
    r = R - 0.064 + 0.001; n = int(TAU * r / 0.021)
    return beads(name, r, 0.083, n, 0.0098, M['metal'])


def band(name, R, M):
    """The recessed gold band between the steps and the foot."""
    r = R - 0.064
    prof = [(r - 0.01, 0.0705), (r - 0.002, 0.0705)] + arc(r - 0.002, 0.0725, 0.002, -math.pi / 2, 0, 3) \
        + arc(r - 0.002, 0.0935, 0.002, 0, math.pi / 2, 3) + [(r - 0.01, 0.0955)]
    return ring_lathe(name, prof, M['metal'])


def mesh_object(name, v, f, mat):
    # Marching cubes winds the faces outward as they come; SceneKit draws only that side.
    me = bpy.data.meshes.new(name); me.from_pydata(v.tolist(), [], f.tolist()); me.update()
    for p in me.polygons: p.use_smooth = True
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o); me.materials.append(mat)
    return o


def finial(name, x, z, M, size=1.0):
    """The gold finial on the knight's poll: a bullet on a small collar."""
    s = size
    prof = [(0, 0), (0.03 * s, 0), (0.031 * s, 0.006 * s), (0.026 * s, 0.012 * s), (0.02 * s, 0.014 * s)]
    prof += [(0.02 * s * math.cos(t) ** 0.7, 0.014 * s + 0.042 * s * math.sin(t)) for t in np.linspace(0, math.pi / 2, 14)]
    o = lathe(name, prof, seg=96, mat=M['metal'])
    o.location = (x, 0, z - 0.008)
    return o


def load_knight(folder='build/sculpted/icon'):
    """The icon knight's stone, gold and eyes, and where its finial stands, from knight_icon.py."""
    parts = {k: (np.load(f'{folder}/{k}v.npy'), np.load(f'{folder}/{k}f.npy')) for k in 'kge'}
    return parts, tuple(np.load(f'{folder}/finial.npy'))


def knight(M, parts, fin):
    """parts: {'k': stone, 'g': gold, 'e': eyes} as (vertices, faces); fin: (x, z) of the finial.
    The muzzle points toward -x, like the classic knight."""
    R = 0.3
    p = base_profile(R) + line(R - 0.056, FOOT, 0.0, FOOT, 3)
    objs = [lathe('Nb', p, mat=M['body']), band('Nband', R, M), band_beads('Nbeadband', R, M)]
    objs.append(mesh_object('Nh', *parts['k'], M['body']))
    objs.append(mesh_object('Nmane', *parts['g'], M['metal']))
    objs.append(mesh_object('Ngem', *parts['e'], M['gem']))
    objs.append(finial('Nfin', fin[0], fin[1], M, 1.35))
    return group('knight', objs)


# ---------- the turned pieces ----------
# The classic set's tops at its heights (see pieces.py): a long Latin cross, a low coronet of
# twelve gold balls, a pointed mitre cut through to its gold core, a tower with five square
# merlons capped in gold round a dark well, one round ball. Smooth polished bodies; the gold is a band under
# each piece, a few stripes on the body as on the knight's mane, a band at the collar and the crown.

def body_start(R):
    """From the foot's top, a small cove up into the body; ends at (R - 0.115, 0.15)."""
    return line(R - 0.056, FOOT, R - 0.084, FOOT, 2) + cove(R - 0.084, FOOT, R - 0.115, 0.15, 10)


def profile_r(prof, z):
    """The body's radius at height z, read from the rising part of a profile."""
    best = None
    for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
        if z0 <= z <= z1 and z1 > z0:
            r = r0 + (r1 - r0) * (z - z0) / (z1 - z0)
            best = r if best is None else max(best, r)
    return best


def sleeve(name, prof, z0, z1, M, proud=0.0025, deep=0.006, n=10):
    """A gold stripe inlaid around the body between z0 and z1, just proud of the stone."""
    zs = np.linspace(z0, z1, n)
    rs = [profile_r(prof, z) for z in zs]
    outer = [(r + proud, z) for r, z in zip(rs, zs)]
    inner = [(r - deep, z) for r, z in zip(rs, zs)][::-1]
    return ring_lathe(name, outer + inner, M['metal'])


def flat_band(name, r, z0, z1, M, edge=0.003, depth=0.02):
    """A flat gold band with softened edges, deep enough to meet the stone under it."""
    prof = [(r - depth, z0), (r - edge, z0)] + arc(r - edge, z0 + edge, edge, -math.pi / 2, 0, 3) \
        + arc(r - edge, z1 - edge, edge, 0, math.pi / 2, 3) + [(r - depth, z1)]
    return ring_lathe(name, prof, M['metal'])


def stripes(name, prof, z_top, M, widths=(0.014, 0.014, 0.014), gap=0.013):
    """Stripes stacked down the body from just under the collar."""
    out = []; z = z_top
    for i, w in enumerate(widths):
        out.append(sleeve(f'{name}{i}', prof, z - w, z, M)); z -= w + gap
    return out


def king(M):
    """The Latin king (see pieces.py) in the gilded finish: a long cross, ivory on the ivory king and
    gold on the onyx one, amber stones round the crown."""
    R = 0.31; p = base_profile(R) + body_start(R)
    p += ogee(R - 0.115, 0.15, 0.125, 0.62, 32)
    body_top = len(p)
    p += line(0.125, 0.62, 0.15, 0.632, 2); p += bead(0.168, 0.632, 0.03)
    p += line(0.16, 0.662, 0.2, 0.67, 2); p += bead(0.205, 0.67, 0.036)
    p += line(0.19, 0.706, 0.11, 0.72, 2)
    p += cove(0.11, 0.72, 0.17, 0.84); p += bead(0.17, 0.84, 0.024, 10)
    p += line(0.158, 0.864, 0.07, 0.875, 2)
    p += [(0.07 * math.cos(t), 0.875 + 0.03 * math.sin(t)) for t in np.linspace(0, math.pi / 2 * 0.9, 8)]
    top = p[-1]; p += line(top[0], top[1], 0.0, top[1], 3)
    objs = [lathe('K', p, mod=gadroons(0.73, 0.83, 18, 0.01), mat=M['body']), band('Kband', R, M), band_beads('Kbeadband', R, M)]
    objs += crown_gems('Kgem', p, 0.79, M)
    objs += stripes('Kst', p[:body_top], 0.595, M)
    objs.append(flat_band('Kring', 0.226, 0.672, 0.704, M))
    objs.append(beads('Kbeadcrown', 0.182, 0.852, 36, 0.011, M['metal']))
    objs += pattee('Kcross', 0.89, LATIN_TOP, 1.30, 0.30, 0.075, 0.10, 0.075, cross_finish(M))
    squash_above(objs, 0.2, (KING_H - 0.2) / (LATIN_TOP - 0.2))
    return group('king', objs)


def queen(M):
    """The short queen (see pieces.py) in the gilded finish: a low coronet ringed with twelve gold balls."""
    R = 0.30; p = base_profile(R) + body_start(R)
    p += ogee(R - 0.115, 0.15, 0.12, 0.5, 32)
    body_top = len(p)
    p += line(0.12, 0.5, 0.145, 0.512, 2); p += bead(0.162, 0.512, 0.028)
    p += line(0.157, 0.54, 0.195, 0.548, 2); p += bead(0.2, 0.548, 0.033)
    p += line(0.185, 0.581, 0.105, 0.596, 2)
    ZR = 0.80
    p += cove(0.105, 0.596, 0.25, ZR - 0.02); p += line(0.25, ZR - 0.02, 0.262, ZR, 2); p += line(0.262, ZR, 0.23, ZR, 2)
    p += line(0.23, ZR, 0.15, 0.74, 4)
    p += [(0.15 * math.cos(t), 0.74 + 0.035 * math.sin(t)) for t in np.linspace(0, math.pi / 2 * 0.8, 8)]
    top = p[-1]; p += line(top[0], top[1], 0.0, top[1], 3)
    body = lathe('Q', p, mod=gadroons(0.62, 0.77, 18, 0.012), mat=M['body'])
    objs = [body, band('Qband', R, M), band_beads('Qbeadband', R, M), beads('Qbeadcollar', 0.1715, 0.526, 36, 0.0105, M['metal'])]
    for i in range(12):
        a = TAU * i / 12; objs.append(uvsphere(f'Qball{i}', 0.036, (math.cos(a) * 0.247, math.sin(a) * 0.247, ZR + 0.03), M['metal']))
    objs += stripes('Qst', p[:body_top], 0.475, M)
    objs.append(flat_band('Qring', 0.2195, 0.5505, 0.5785, M))
    squash_above(objs, 0.2, (QUEEN_H - 0.2) / (QUEEN_TOP - 0.2))
    return group('queen', objs)


def bishop(M):
    R = 0.285; p = base_profile(R) + body_start(R)
    p += ogee(R - 0.115, 0.15, 0.1, 0.42, 28)
    body_top = len(p)
    p += line(0.1, 0.42, 0.13, 0.432, 2); p += bead(0.148, 0.432, 0.026)
    p += line(0.138, 0.458, 0.165, 0.465, 2); p += bead(0.168, 0.465, 0.03)
    p += line(0.15, 0.495, 0.08, 0.51, 2)
    # a tall mitre that comes to a point, cut through to its gold core
    mit = mitre_profile(); p += mit
    body = lathe('B', p, mat=M['body'])
    mitre_cut(body)
    objs = [body, band('Bband', R, M), band_beads('Bbeadband', R, M), beads('Bbeadcollar', 0.1565, 0.445, 30, 0.0098, M['metal'])]
    objs.append(lathe('Bmitre', [(0.0, 0.52)] + [(max(r - 0.012, 0.0), z) for r, z in mit[1:-1]] + [(0.0, mit[-1][1] - 0.02)],
                      seg=128, mat=M['metal']))
    objs += stripes('Bst', p[:body_top], 0.395, M, widths=(0.012, 0.012, 0.012), gap=0.011)
    objs.append(flat_band('Bring', 0.186, 0.4665, 0.4935, M))
    objs.append(lathe('Bstem', [(0.0, 0.925), (0.028, 0.925), (0.015, 0.95), (0.0, 0.95)], seg=96, mat=M['metal']))
    objs.append(uvsphere('Bfin', 0.037, (0, 0, 1.0 - 0.037), M['metal']))
    return group('bishop', objs)


def rook(M):
    R = 0.3; p = base_profile(R)
    # the classic tower: straight walls, a corbelled ledge, a wide parapet of five merlons
    ZT = 0.73; RO = 0.252; RI = 0.158; FLOOR = 0.585; NOTCH = 0.612
    p += line(R - 0.056, FOOT, R - 0.07, FOOT, 2) + cove(R - 0.07, FOOT, 0.2, 0.15, 10)
    p += line(0.2, 0.15, 0.198, 0.49, 10)
    body_top = len(p)
    p += line(0.198, 0.49, 0.206, 0.494, 1)
    p += cove(0.206, 0.494, RO, 0.548, 10)
    p += line(RO, 0.548, RO, ZT, 6)
    p += line(RO, ZT, RI, ZT, 3); p += line(RI, ZT, RI, FLOOR, 4); p += line(RI, FLOOR, 0.0, FLOOR, 3)
    body = lathe('R', p, seg=384, mat=M['body'])
    for i in range(5):
        a = -math.pi / 2 + TAU * i / 5
        cut(body, crenel(f'Rc{i}', a, math.radians(31), NOTCH, ZT + 0.1))
    objs = [body, band('Rband', R, M), band_beads('Rbeadband', R, M)]
    # arrow slits on four sides, under the gold stripes
    objs += slits(body, 'Rslit', 0.199, 0.19, 0.33, 0.036, M, [FRONT + i * math.pi / 2 for i in range(4)])
    objs += stripes('Rst', p[:body_top], 0.43, M)
    objs.append(flat_band('Rring', 0.209, 0.466, 0.492, M))
    # gold caps on the merlons, so the battlements catch the light on every square
    objs.append(merlon_caps('Rcap', RI, RO, ZT, M['metal']))
    objs.append(lathe('Rwell', [(0.0, FLOOR - 0.002), (RI - 0.001, FLOOR - 0.002), (RI - 0.001, FLOOR + 0.004), (0.0, FLOOR + 0.004)],
                      seg=192, mat=shade(M)))
    return group('rook', objs)


def pawn(M):
    R = 0.26; p = base_profile(R) + body_start(R)
    # short and plain under a big round head: the smallest piece, and the only round top
    p += ogee(R - 0.115, 0.15, 0.085, 0.27, 20)
    body_top = len(p)
    p += line(0.085, 0.27, 0.115, 0.28, 2); p += bead(0.125, 0.28, 0.026)
    p += line(0.115, 0.306, 0.06, 0.316, 2)
    rad = 0.13; a0 = math.asin(0.06 / rad); cz = 0.316 + rad * math.cos(a0)
    p += [(rad * math.sin(a), cz - rad * math.cos(a)) for a in np.linspace(a0, math.pi, 40)]
    objs = [lathe('P', p, mat=M['body']), band('Pband', R, M), band_beads('Pbeadband', R, M)]
    objs += stripes('Pst', p[:body_top], 0.25, M, widths=(0.012, 0.012), gap=0.011)
    objs.append(flat_band('Pring', 0.1445, 0.281, 0.305, M))
    return group('pawn', objs)
