# The gilded set, modeled on a black-and-gold knight artwork. Polished black (or ivory) stone with gold:
# a stepped base with a recessed gold band under each piece, gold bands on the bodies and
# gold crowns, and the knight with its striped gold mane and amber eye.
# The knight's head, mane and eyes come from knight_icon.py (load_knight reads them).
import bpy, bmesh, math, numpy as np, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pieces import arc, bead, cove, ogee, line, lathe, uvsphere, rbox, cut, group, mitre_profile, TAU

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


def band(name, R, M):
    """The recessed gold band between the steps and the foot."""
    r = R - 0.064
    prof = [(r - 0.01, 0.0705), (r - 0.002, 0.0705)] + arc(r - 0.002, 0.0725, 0.002, -math.pi / 2, 0, 3) \
        + arc(r - 0.002, 0.0935, 0.002, 0, math.pi / 2, 3) + [(r - 0.01, 0.0955)]
    return ring_lathe(name, prof, M['metal'])


def ring_lathe(name, prof, mat, seg=256):
    """A closed profile turned into a ring (no caps)."""
    verts = []; faces = []
    n = len(prof)
    for j in range(seg):
        th = TAU * j / seg
        for (r, z) in prof:
            verts.append((r * math.cos(th), r * math.sin(th), z))
    for j in range(seg):
        a = j * n; b = ((j + 1) % seg) * n
        for i in range(n):
            i2 = (i + 1) % n
            faces.append((a + i, b + i, b + i2, a + i2))
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    bm = bmesh.new(); bm.from_mesh(me); bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob); me.materials.append(mat)
    return ob


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
    objs = [lathe('Nb', p, mat=M['body']), band('Nband', R, M)]
    objs.append(mesh_object('Nh', *parts['k'], M['body']))
    objs.append(mesh_object('Nmane', *parts['g'], M['metal']))
    objs.append(mesh_object('Ngem', *parts['e'], M['gem']))
    objs.append(finial('Nfin', fin[0], fin[1], M, 1.35))
    return group('knight', objs)


# ---------- the turned pieces ----------
# Heights and tops as the classic set (see pieces.py): big king cross, spiky queen coronet,
# pointed bishop, round short pawn. Smooth polished
# bodies; the gold is a band under each piece, a few stripes on the body as on the knight's
# mane, a band at the collar and the crown's metal.

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


def flat_band(name, r, z0, z1, M, edge=0.003, depth=0.012):
    """A flat gold band with softened edges."""
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
    R = 0.33; p = base_profile(R) + body_start(R)
    p += ogee(R - 0.115, 0.15, 0.13, 0.6, 32)
    body_top = len(p)
    p += line(0.13, 0.6, 0.155, 0.612, 2); p += bead(0.172, 0.612, 0.03)
    p += line(0.165, 0.642, 0.205, 0.65, 2); p += bead(0.21, 0.65, 0.036)
    p += line(0.195, 0.686, 0.12, 0.7, 2)
    p += cove(0.12, 0.7, 0.2, 0.84)
    p += bead(0.202, 0.84, 0.024, 10)
    p += line(0.19, 0.864, 0.178, 0.868, 1)
    p += [(0.178 * math.cos(t), 0.868 + 0.09 * math.sin(t)) for t in np.linspace(0, math.pi / 2 * 0.86, 16)]
    top = p[-1]; p += line(top[0], top[1], 0.0, top[1], 3)
    objs = [lathe('K', p, mat=M['body']), band('Kband', R, M)]
    objs += stripes('Kst', p[:body_top], 0.575, M)
    objs.append(flat_band('Kring', 0.231, 0.652, 0.684, M))
    objs.append(flat_band('Kcrown', 0.2155, 0.832, 0.856, M))
    zt = top[1] - 0.01
    objs.append(lathe('Kcush', [(0.0, zt - 0.005), (0.06, zt - 0.005), (0.07, zt + 0.012), (0.05, zt + 0.03), (0.0, zt + 0.03)], seg=128, mat=M['metal']))
    # a big, bold cross: what says "king" at a glance
    objs.append(rbox('Kcv', (0.1, 0.1, 0.38), (0, 0, zt + 0.2), M['metal'], 0.022))
    objs.append(rbox('Kch', (0.3, 0.1, 0.1), (0, 0, zt + 0.25), M['metal'], 0.022))
    for y in (-0.05, 0.05):
        objs.append(uvsphere('Kgem', 0.032, (0, y, zt + 0.25), M['gem'], (1, 0.45, 1)))
    return group('king', objs)


def queen(M):
    R = 0.32; p = base_profile(R) + body_start(R)
    p += ogee(R - 0.115, 0.15, 0.118, 0.54, 32)
    body_top = len(p)
    p += line(0.118, 0.54, 0.142, 0.552, 2); p += bead(0.16, 0.552, 0.028)
    p += line(0.155, 0.58, 0.192, 0.588, 2); p += bead(0.197, 0.588, 0.033)
    p += line(0.182, 0.621, 0.105, 0.636, 2)
    p += cove(0.105, 0.636, 0.19, 0.8)
    # a tall coronet that flares wide into eight sharp points: the queen's spiky crown
    p += line(0.19, 0.8, 0.25, 0.975, 6)
    p += line(0.25, 0.975, 0.218, 0.975, 2)
    p += line(0.218, 0.975, 0.17, 0.85, 3)
    p += [(0.17 * math.cos(t), 0.85 + 0.05 * math.sin(t)) for t in np.linspace(0, math.pi / 2 * 0.8, 10)]
    top = p[-1]; p += line(top[0], top[1], 0.0, top[1], 3)
    body = lathe('Q', p, mat=M['body'])
    objs = [body, band('Qband', R, M)]
    NPT = 8
    for i in range(NPT):
        a = TAU * (i + 0.5) / NPT
        c = rbox(f'Qn{i}', (0.2, 0.13, 0.13), (math.cos(a) * 0.235, math.sin(a) * 0.235, 1.0), M['body'], 0.003)
        c.rotation_mode = 'XYZ'; c.rotation_euler = (math.radians(45), 0, a)
        cut(body, c)
    for i in range(NPT):
        a = TAU * i / NPT; objs.append(uvsphere(f'Qball{i}', 0.028, (math.cos(a) * 0.236, math.sin(a) * 0.236, 0.985), M['metal']))
    objs += stripes('Qst', p[:body_top], 0.515, M)
    objs.append(flat_band('Qring', 0.2155, 0.5895, 0.6195, M))
    objs.append(sleeve('Qcrown', p, 0.81, 0.836, M))
    zt = top[1]
    objs.append(lathe('Qstem', [(0.0, zt - 0.01), (0.036, zt - 0.01), (0.02, zt + 0.08), (0.0, zt + 0.08)], seg=96, mat=M['metal']))
    objs.append(uvsphere('Qtopball', 0.052, (0, 0, zt + 0.125), M['metal']))
    return group('queen', objs)


def bishop(M):
    R = 0.3; p = base_profile(R) + body_start(R)
    p += ogee(R - 0.115, 0.15, 0.098, 0.44, 28)
    body_top = len(p)
    p += line(0.098, 0.44, 0.128, 0.452, 2); p += bead(0.146, 0.452, 0.026)
    p += line(0.136, 0.478, 0.162, 0.485, 2); p += bead(0.165, 0.485, 0.03)
    p += line(0.148, 0.515, 0.08, 0.53, 2)
    # a tall mitre that comes to a point, never round like the pawn's head
    mit = mitre_profile()
    p += mit
    body = lathe('B', p, mat=M['body'])
    slot = rbox('Bslot', (0.05, 0.4, 0.32), (0.07, 0, 0.8), M['body'], 0.006); slot.rotation_euler = (0, math.radians(-40), 0)
    cut(body, slot)
    objs = [body, band('Bband', R, M)]
    # a gold core inside the mitre: through the cut it shows as a gold line
    objs.append(lathe('Bmitre', [(0.0, 0.53)] + [(max(r - 0.009, 0.0), z) for r, z in mit[1:-1]] + [(0.0, mit[-1][1] - 0.012)],
                      seg=128, mat=M['metal']))
    objs += stripes('Bst', p[:body_top], 0.415, M, widths=(0.012, 0.012, 0.012), gap=0.011)
    objs.append(flat_band('Bring', 0.183, 0.486, 0.514, M))
    objs.append(lathe('Bstem', [(0.0, 0.935), (0.026, 0.935), (0.014, 0.962), (0.0, 0.962)], seg=96, mat=M['metal']))
    objs.append(uvsphere('Bfin', 0.038, (0, 0, 0.99), M['metal']))
    return group('bishop', objs)


def rook(M):
    R = 0.3; p = base_profile(R) + body_start(R)
    p += line(R - 0.115, 0.15, 0.16, 0.45, 10)
    body_top = len(p)
    p += line(0.16, 0.45, 0.17, 0.46, 1); p += bead(0.18, 0.46, 0.026)
    p += line(0.17, 0.486, 0.205, 0.497, 2); p += bead(0.21, 0.497, 0.03)
    p += line(0.195, 0.527, 0.19, 0.534, 1)
    p += cove(0.19, 0.534, 0.228, 0.6, 10)
    p += line(0.228, 0.6, 0.228, 0.7, 4)
    p += line(0.228, 0.7, 0.158, 0.7, 2); p += line(0.158, 0.7, 0.158, 0.645, 2); p += line(0.158, 0.645, 0.0, 0.645, 2)
    body = lathe('R', p, seg=384, mat=M['body'])
    for i in range(6):
        a = TAU * i / 6
        c = rbox(f'Rc{i}', (0.13, 0.055, 0.1), (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.69), M['body'], 0.004); c.rotation_euler = (0, 0, a)
        cut(body, c)
    objs = [body, band('Rband', R, M)]
    objs += stripes('Rst', p[:body_top], 0.43, M, widths=(0.014, 0.014, 0.014), gap=0.013)
    objs.append(flat_band('Rring', 0.228, 0.498, 0.526, M))
    return group('rook', objs)


def pawn(M):
    R = 0.27; p = base_profile(R) + body_start(R)
    # short and plain under a big round head: the smallest piece, and the only round top
    p += ogee(R - 0.115, 0.15, 0.085, 0.29, 20)
    body_top = len(p)
    p += line(0.085, 0.29, 0.115, 0.3, 2); p += bead(0.125, 0.3, 0.026)
    p += line(0.115, 0.326, 0.058, 0.336, 2)
    rad = 0.128; a0 = math.asin(0.058 / rad); cz = 0.336 + rad * math.cos(a0)
    p += [(rad * math.sin(a), cz - rad * math.cos(a)) for a in np.linspace(a0, math.pi, 40)]
    objs = [lathe('P', p, mat=M['body']), band('Pband', R, M)]
    objs += stripes('Pst', p[:body_top], 0.27, M, widths=(0.012, 0.012), gap=0.011)
    objs.append(flat_band('Pring', 0.1445, 0.301, 0.325, M))
    return group('pawn', objs)
