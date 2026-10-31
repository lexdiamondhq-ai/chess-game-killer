"""Builds the flat board's pieces and exports them for SceneKit (SCLP v1, raw deflate, as
scripts/sculpted/export.py writes the carved sets).
Usage (from the repo root, Blender's bpy as a module): python scripts/sculpted/flat/build.py
-> build/sculpted/flat-icon.bin, which goes in ChessGameKiller/Assets.xcassets/Sculpted/flat-icon.dataset.
To see it under the app's light first: scripts/sculpted/flat/preview.py.
Each piece is its familiar outline (glyphs.json, traced by trace.py) cut solid, on a fine foot, with
its inner lines on top. Sizes in squares; Blender y = away from White. Part finishes are roles the
app reads (SculptedFlatSet.swift): body = the look's stone, metal = its metal, ink (the "gem" slot) =
lines drawn on the piece."""
import bpy, bmesh, math, sys, os, json, struct, zlib, numpy as np
from shapely.geometry import Polygon, LineString, box
from shapely.ops import unary_union
from shapely import affinity

G = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'glyphs.json')))
bpy.ops.wm.read_factory_settings(use_empty=True)
ROLES = ('body', 'metal', 'ink')        # SculptedAssets.Finish raw values 0..2
M = {r: bpy.data.materials.new(r) for r in ROLES}

def link(o): bpy.context.collection.objects.link(o); return o

def parts(shape):
    if shape is None or shape.is_empty: return []
    return [p for p in (shape.geoms if hasattr(shape, 'geoms') else [shape]) if p.geom_type == 'Polygon']

def prism(name, shape, z0, z1, role, bevel=0.0, segs=3):
    objs = []
    for i, poly in enumerate(parts(shape)):
        if poly.area < 2e-4: continue
        bm = bmesh.new(); edges = []
        for ring in [poly.exterior] + list(poly.interiors):
            pts = list(ring.coords)[:-1]
            vs = [bm.verts.new((x, y, z0)) for x, y in pts]
            edges += [bm.edges.new((vs[j], vs[(j + 1) % len(vs)])) for j in range(len(vs))]
        faces = [f for f in bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=True, edges=edges)['geom']
                 if isinstance(f, bmesh.types.BMFace)]
        for f in faces:
            if f.normal.z < 0: f.normal_flip()
        r = bmesh.ops.extrude_face_region(bm, geom=faces, use_keep_orig=True)
        for v in [e for e in r['geom'] if isinstance(e, bmesh.types.BMVert)]: v.co.z = z1
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.dissolve_limit(bm, angle_limit=0.01, verts=list(bm.verts), edges=list(bm.edges))
        me = bpy.data.meshes.new(f'{name}{i}'); bm.to_mesh(me); bm.free()
        ob = link(bpy.data.objects.new(f'{name}{i}', me)); me.materials.append(M[role])
        if bevel:
            mod = ob.modifiers.new('bev', 'BEVEL'); mod.width = bevel; mod.segments = segs
            mod.limit_method = 'ANGLE'; mod.angle_limit = math.radians(50); mod.harden_normals = False
        objs.append(ob)
    return objs

# The pawn's own lines. The cburnett pawn has none, so next to the others' bands it read as a plain
# blob: a collar under the head and a band round the base, arcs like the king's and queen's bands.
# Each is (height, inset from the outline at that height, how far its middle rises), in glyph units.
PAWN_LINES = [(0.168, 0.03, 0.012), (-0.30, 0.06, 0.03)]
LINE = 0.032   # as thick as the traced pieces' lines


def pawn_lines(outline):
    bars = []
    for y, inset, rise in PAWN_LINES:
        x0, _, x1, _ = outline.intersection(box(-1, y - 1e-4, 1, y + 1e-4)).bounds
        x0 += inset; x1 -= inset
        xs = np.linspace(x0, x1, 40); half = (x1 - x0) / 2; mid = (x0 + x1) / 2
        ys = y + rise * (1 - ((xs - mid) / half) ** 2)
        bars.append(LineString(list(zip(xs, ys))).buffer(LINE / 2, cap_style=1))
    return unary_union(bars)


def glyph(kind, s):
    polys = [Polygon(p[0], p[1:]) for p in G[kind]['outline']]
    det = [Polygon(p[0], p[1:]) for p in G[kind]['details']]
    sc = lambda g: affinity.scale(g, s, s, origin=(0, 0))
    outline = unary_union(polys).buffer(0)
    lines = unary_union(det).buffer(0) if det else pawn_lines(outline) if kind == 'P' else None
    return sc(outline), sc(lines) if lines is not None else None

SCALE = 0.80 / 0.861          # the widest icon (the queen) comes out 0.80 square

# ---------- Icon: the familiar piece, cut solid, on a fine gold foot ----------
def icon(kind):
    sil, det = glyph(kind, SCALE)
    h = 0.105 if kind != 'P' else 0.09
    objs = prism('body', sil, 0.012, h, 'body', bevel=0.018, segs=4)
    objs += prism('foot', sil.buffer(0.02, join_style=1), 0.0, 0.016, 'metal', bevel=0.005, segs=2)
    if det is not None:
        lines = det.intersection(sil.buffer(-0.02))
        objs += prism('ink', lines, h - 0.004, h + 0.004, 'ink', bevel=0.0015, segs=1)
    return objs

SHARP = math.radians(45)

# ---------- build and export ----------
out = {}
dg = bpy.context.evaluated_depsgraph_get()
for kind in 'KQRBNP':
    objs = icon(kind); dg.update()
    per = {r: [] for r in ROLES}
    for c in objs:
        e = c.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(e, preserve_all_data_layers=False, depsgraph=dg)
        me.transform(c.matrix_world)
        for p in me.polygons: p.use_smooth = True
        me.set_sharp_from_angle(angle=SHARP)
        me.calc_loop_triangles()
        nt = len(me.loop_triangles)
        if nt == 0: bpy.data.meshes.remove(me); continue
        tl = np.empty(nt * 3, np.int32); me.loop_triangles.foreach_get('loops', tl)
        lv = np.empty(len(me.loops), np.int32); me.loops.foreach_get('vertex_index', lv)
        co = np.empty(len(me.vertices) * 3, np.float32); me.vertices.foreach_get('co', co); co = co.reshape(-1, 3)
        cn = np.empty(len(me.loops) * 3, np.float32); me.corner_normals.foreach_get('vector', cn); cn = cn.reshape(-1, 3)
        vi = lv[tl]; nn = cn[tl]
        key = np.concatenate([vi[:, None].astype(np.int64), np.round(nn * 2000).astype(np.int64)], axis=1)
        uk, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        pos = co[vi[first]]; nor = nn[first]; nor /= np.linalg.norm(nor, axis=1, keepdims=True) + 1e-12
        per[c.data.materials[0].name].append((pos, nor, inv.reshape(-1).astype(np.uint32)))
        bpy.data.meshes.remove(me)
    merged = {}
    for r, lst in per.items():
        if not lst: continue
        P_, N_, I_, off = [], [], [], 0
        for pos, nor, idx in lst: P_.append(pos); N_.append(nor); I_.append(idx + off); off += len(pos)
        pos = np.concatenate(P_); nor = np.concatenate(N_); idx = np.concatenate(I_)
        pos = np.stack([pos[:, 0], pos[:, 2], -pos[:, 1]], 1)     # blender -> scenekit: y up, away from White = -z
        nor = np.stack([nor[:, 0], nor[:, 2], -nor[:, 1]], 1)
        merged[r] = (pos.astype(np.float32), nor.astype(np.float32), idx.astype(np.uint32))
    out[kind] = merged
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)

buf = bytearray(b'SCLP'); buf += struct.pack('<II', 1, len(out))
for kind, merged in out.items():
    buf += struct.pack('<BBH', ord(kind), len(merged), 0)
    for r, (pos, nor, idx) in merged.items():
        buf += struct.pack('<B3xII', ROLES.index(r), len(pos), len(idx))
        buf += pos.tobytes(); buf += nor.tobytes(); buf += idx.tobytes()
c = zlib.compressobj(9, zlib.DEFLATED, -15); comp = c.compress(bytes(buf)) + c.flush()
os.makedirs('build/sculpted', exist_ok=True)
open('build/sculpted/flat-icon.bin', 'wb').write(comp)
for kind, merged in out.items():
    tri = sum(len(v[2]) // 3 for v in merged.values())
    lo = np.min(np.concatenate([v[0] for v in merged.values()]), 0); hi = np.max(np.concatenate([v[0] for v in merged.values()]), 0)
    print(kind, 'tris', tri, 'x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f' % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]),
          {r: len(v[0]) for r, v in merged.items()})
print('bytes', len(buf), 'compressed', len(comp))

