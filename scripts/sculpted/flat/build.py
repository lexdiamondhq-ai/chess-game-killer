"""Builds a flat-board piece set and exports it for SceneKit (SCLP v1, raw deflate, as
scripts/sculpted/export.py writes the carved sets), and optionally renders a preview.
Usage (from the repo root): python build.py -- <style> [preview.png]   (Blender's bpy as a module)
style: icon | regalia | gem | rose -> build/sculpted/flat-<style>.bin, which goes in
ChessGameKiller/Assets.xcassets/Sculpted/flat-<style>.dataset. Sizes in squares; Blender y = away from White.
Part finishes are roles the app reads (SculptedFlatSet.swift): body = the look's stone, metal = its
metal, ink (the "gem" slot) = lines drawn on the piece, jewel (the "pearl" slot) = a cut stone."""
import bpy, bmesh, math, sys, os, json, struct, zlib, numpy as np
from mathutils import Vector
from shapely.geometry import Polygon, MultiPolygon, Point, box
from shapely.ops import unary_union
from shapely import affinity

argv = sys.argv[sys.argv.index('--') + 1:]
STYLE = argv[0]; PREVIEW = argv[1] if len(argv) > 1 else None
G = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'glyphs.json')))
bpy.ops.wm.read_factory_settings(use_empty=True)
ROLES = ('body', 'metal', 'ink', 'jewel')        # SculptedAssets.Finish raw values 0..3
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

def glyph(kind, s):
    polys = [Polygon(p[0], p[1:]) for p in G[kind]['outline']]
    det = [Polygon(p[0], p[1:]) for p in G[kind]['details']]
    sc = lambda g: affinity.scale(g, s, s, origin=(0, 0))
    return sc(unary_union(polys).buffer(0)), sc(unary_union(det).buffer(0)) if det else None

def circle(r, n=128): return Point(0, 0).buffer(r, quad_segs=n // 4)
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

# ---------- Gem Cut: each piece a jewel cut, set in gold ----------
def facet_gem(outline, h_girdle, h_table, table=0.55, mid=0.82, twist=0.0):
    pts = list(outline.exterior.coords)[:-1]; n = len(pts)
    bm = bmesh.new()
    def ring(scale, z, rot=0.0):
        c, s = math.cos(rot), math.sin(rot)
        return [bm.verts.new((scale * (x * c - y * s), scale * (x * s + y * c), z)) for x, y in pts]
    base = ring(1.0, 0.0); gird = ring(1.0, h_girdle)
    star = ring(mid, h_girdle + (h_table - h_girdle) * 0.55, twist); top = ring(table, h_table)
    bm.faces.new(list(reversed(base)))
    for a, b_ in ((base, gird), (gird, star), (star, top)):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b_[j], b_[i]))
    bm.faces.new(top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new('gem'); bm.to_mesh(me); bm.free()
    ob = link(bpy.data.objects.new('gem', me)); me.materials.append(M['jewel'])
    return ob

def resample(poly, n):
    ring = poly.exterior
    return Polygon([ring.interpolate(i / n, normalized=True).coords[0] for i in range(n)])

def ball(r, loc, role, squash=1.0, seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=seg, ring_count=seg // 2, location=loc)
    s = bpy.context.active_object; s.scale = (1, 1, squash); s.data.materials.append(M[role]); s.data.shade_smooth()
    return s

def dome(r, h, role, seg=64, z=0.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, segments=seg, ring_count=seg // 2, location=(0, 0, 0))
    s = bpy.context.active_object
    bm = bmesh.new(); bm.from_mesh(s.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-5], context='VERTS')
    for v in bm.verts: v.co.x *= r; v.co.y *= r; v.co.z = v.co.z * h + z
    bm.to_mesh(s.data); bm.free()
    s.data.materials.append(M[role]); s.data.shade_smooth()
    return s

def gem(kind):
    objs = []
    if kind == 'K':     # emerald cut, a gold cross on the table
        a, b, c = 0.29, 0.33, 0.09
        o = Polygon([(-a + c, -b), (a - c, -b), (a, -b + c), (a, b - c), (a - c, b), (-a + c, b), (-a, b - c), (-a, -b + c)])
        g = facet_gem(o, 0.05, 0.2, table=0.55, mid=0.8)
        cross = unary_union([box(-0.028, -0.13, 0.028, 0.13), box(-0.09, 0.025, 0.09, 0.075)])
        objs += prism('cross', cross, 0.19, 0.228, 'metal', bevel=0.008, segs=3)
    elif kind == 'Q':   # round brilliant, a coronet of eight gold beads
        o = resample(circle(0.34), 16)
        g = facet_gem(o, 0.05, 0.22, table=0.5, mid=0.82, twist=math.pi / 16)
        for i in range(8):
            t = 2 * math.pi * i / 8 + math.pi / 8
            objs.append(ball(0.042, (0.345 * math.cos(t), 0.345 * math.sin(t), 0.075), 'metal'))
    elif kind == 'R':   # princess: a sharp square
        o = box(-0.28, -0.28, 0.28, 0.28)
        g = facet_gem(resample(o, 16), 0.05, 0.19, table=0.55, mid=0.8)
    elif kind == 'B':   # marquise, on the diagonal
        lens = Point(-0.22, 0).buffer(0.44, quad_segs=24).intersection(Point(0.22, 0).buffer(0.44, quad_segs=24))
        o = affinity.rotate(affinity.scale(lens, 1.0, 1.3), 45, origin=(0, 0))
        g = facet_gem(resample(o, 20), 0.05, 0.19, table=0.45, mid=0.78)
    elif kind == 'N':   # trillion, its point forward
        o = Polygon([(0, 0.35), (-0.32, -0.21), (0.32, -0.21)]).buffer(0.04, quad_segs=6)
        g = facet_gem(resample(o, 18), 0.05, 0.19, table=0.5, mid=0.8)
    else:               # pawn: a round cabochon
        g = dome(0.24, 0.13, 'jewel')
        o = circle(0.24)
    if kind != 'P':
        g.data.shade_flat()
    objs.append(g)
    bezel = o.buffer(0.03, quad_segs=8).difference(o.buffer(-0.005))
    objs += prism('bezel', bezel, 0, 0.075, 'metal', bevel=0.01, segs=3)
    return objs

# ---------- Regalia: each piece as its emblem: cross, coronet, tower, mitre, horseshoe, orb ----------
def regalia(kind):
    objs = []
    if kind == 'K':     # a Latin cross with rounded ends, gold-edged
        cross = unary_union([box(-0.065, -0.39, 0.065, 0.33), box(-0.27, 0.06, 0.27, 0.19)]).buffer(0.012, join_style=1)
        objs += prism('body', cross, 0.014, 0.125, 'body', bevel=0.022, segs=4)
        objs += prism('edge', cross.buffer(0.014, join_style=1), 0.0, 0.016, 'metal', bevel=0.004, segs=2)
        objs.append(ball(0.05, (0, 0.125, 0.125), 'metal', squash=0.5))
    elif kind == 'Q':   # a coronet: a gold ring of eight pearls round a domed cap
        objs.append(dome(0.24, 0.15, 'body'))
        ring = circle(0.34).difference(circle(0.235))
        objs += prism('ring', ring, 0.0, 0.07, 'metal', bevel=0.012, segs=3)
        for i in range(8):
            t = 2 * math.pi * i / 8 + math.pi / 8
            objs.append(ball(0.045, (0.288 * math.cos(t), 0.288 * math.sin(t), 0.085), 'body'))
        objs.append(ball(0.045, (0, 0, 0.15), 'metal', squash=0.8))
    elif kind == 'R':   # a tower seen from above: crenellated walls round a gold floor
        outer = box(-0.3, -0.3, 0.3, 0.3); inner = box(-0.19, -0.19, 0.19, 0.19)
        objs += prism('wall', outer.difference(inner), 0.0, 0.11, 'body', bevel=0.012, segs=3)
        objs += prism('floor', inner.buffer(0.004), 0.0, 0.04, 'metal')
        merlons = []
        for c in (-0.245, 0.0, 0.245):
            for (x, y) in ((c, -0.245), (c, 0.245), (-0.245, c), (0.245, c)):
                merlons.append(box(x - 0.055, y - 0.055, x + 0.055, y + 0.055))
        objs += prism('merlon', unary_union(merlons), 0.11, 0.165, 'body', bevel=0.01, segs=3)
    elif kind == 'B':   # a mitre from above: a pointed oval, its slit in gold
        lens = Point(-0.12, 0).buffer(0.33, quad_segs=32).intersection(Point(0.12, 0).buffer(0.33, quad_segs=32))
        lens = affinity.scale(lens, 1.0, 1.15)
        objs += prism('mitre', lens, 0.0, 0.13, 'body', bevel=0.045, segs=6)
        slit = affinity.rotate(box(-0.012, -0.2, 0.012, 0.2), -32, origin=(0, 0)).intersection(lens.buffer(-0.07))
        objs += prism('slit', slit, 0.122, 0.134, 'metal', bevel=0.003, segs=1)
        objs.append(ball(0.04, (0, 0.33, 0.06), 'metal'))
    elif kind == 'N':   # a horseshoe, open away from the player, gold nails
        shoe = circle(0.32).difference(circle(0.17))
        gap = Polygon([(0, 0), (-0.5, 0.42), (0.5, 0.42)])
        shoe = shoe.difference(affinity.translate(gap, 0, 0.06)).buffer(0.02, join_style=1).buffer(-0.02, join_style=1)
        objs += prism('shoe', shoe, 0.0, 0.1, 'body', bevel=0.025, segs=4)
        for a in (200, 230, 260, 280, 310, 340):
            r = 0.245
            objs.append(ball(0.022, (r * math.cos(math.radians(a)), r * math.sin(math.radians(a)), 0.1), 'metal', squash=0.6))
    else:               # an orb: a pearl on a fine gold ring
        objs.append(dome(0.2, 0.15, 'body'))
        objs += prism('ring', circle(0.235).difference(circle(0.19)), 0.0, 0.035, 'metal', bevel=0.008, segs=2)
    return objs

# ---------- Compass Rose: domed stones, gold rays for the way each piece moves ----------
def rose(kind):
    r = 0.33 if kind != 'P' else 0.25
    objs = prism('stone', circle(r), 0.0, 0.085, 'body', bevel=0.045, segs=6)
    top = 0.085
    def rays(angles, r0, r1, w=0.026):
        return unary_union([affinity.rotate(box(-w / 2, r0, w / 2, r1), a, origin=(0, 0)) for a in angles]).buffer(0.004, join_style=1)
    if kind == 'R':
        lines = rays([0, 90, 180, 270], 0.07, 0.25)
    elif kind == 'B':
        lines = rays([45, 135, 225, 315], 0.07, 0.25)
    elif kind == 'Q':
        lines = rays(range(0, 360, 45), 0.07, 0.25)
    elif kind == 'K':
        lines = unary_union([rays(range(0, 360, 45), 0.07, 0.15), circle(0.21).difference(circle(0.185))])
    elif kind == 'N':
        ang = [math.atan2(dy, dx) for dx, dy in [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]]
        lines = unary_union([Point(0.215 * math.cos(a), 0.215 * math.sin(a)).buffer(0.032) for a in ang])
    else:
        lines = None
    if lines is not None:
        objs += prism('inlay', lines, top - 0.004, top + 0.005, 'metal', bevel=0.002, segs=1)
    objs.append(ball(0.05 if kind != 'P' else 0.06, (0, 0, top), 'metal', squash=0.55))
    return objs

BUILD = dict(icon=icon, regalia=regalia, gem=gem, rose=rose)[STYLE]
SHARP = math.radians(15 if STYLE == 'gem' else 45)

# ---------- build and export ----------
out = {}; built = {}
dg = bpy.context.evaluated_depsgraph_get()
for kind in 'KQRBNP':
    objs = BUILD(kind); dg.update()
    built[kind] = objs
    per = {r: [] for r in ROLES}
    for c in objs:
        e = c.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(e, preserve_all_data_layers=False, depsgraph=dg)
        me.transform(c.matrix_world)
        if not (STYLE == 'gem' and c.name.startswith('gem') and kind != 'P'):
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
    if not PREVIEW:
        for o in list(bpy.data.objects): bpy.data.objects.remove(o)

buf = bytearray(b'SCLP'); buf += struct.pack('<II', 1, len(out))
for kind, merged in out.items():
    buf += struct.pack('<BBH', ord(kind), len(merged), 0)
    for r, (pos, nor, idx) in merged.items():
        buf += struct.pack('<B3xII', ROLES.index(r), len(pos), len(idx))
        buf += pos.tobytes(); buf += nor.tobytes(); buf += idx.tobytes()
c = zlib.compressobj(9, zlib.DEFLATED, -15); comp = c.compress(bytes(buf)) + c.flush()
os.makedirs('build/sculpted', exist_ok=True)
open(f'build/sculpted/flat-{STYLE}.bin', 'wb').write(comp)
for kind, merged in out.items():
    tri = sum(len(v[2]) // 3 for v in merged.values())
    lo = np.min(np.concatenate([v[0] for v in merged.values()]), 0); hi = np.max(np.concatenate([v[0] for v in merged.values()]), 0)
    print(kind, 'tris', tri, 'x %.3f..%.3f y %.3f..%.3f z %.3f..%.3f' % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]),
          {r: len(v[0]) for r, v in merged.items()})
print('bytes', len(buf), 'compressed', len(comp))

if PREVIEW:
    import os
    def principled(m, col, rough, metal=0.0, coat=0.0):
        m.use_nodes = True; b = m.node_tree.nodes['Principled BSDF']
        b.inputs['Base Color'].default_value = (*col, 1); b.inputs['Roughness'].default_value = rough
        b.inputs['Metallic'].default_value = metal; b.inputs['Coat Weight'].default_value = coat
    # two copies: white materials and black ones
    WM = {'body': ((0.86, 0.80, 0.70), 0.3, 0, 0.6), 'metal': ((0.85, 0.62, 0.30), 0.22, 1, 0),
          'ink': ((0.02, 0.018, 0.016), 0.35, 0, 0.5), 'jewel': ((0.92, 0.92, 0.95), 0.05, 0.3, 1)}
    BM = {'body': ((0.012, 0.010, 0.009), 0.25, 0, 0.8), 'metal': ((0.85, 0.62, 0.30), 0.22, 1, 0),
          'ink': ((0.85, 0.62, 0.30), 0.22, 1, 0), 'jewel': ((0.01, 0.01, 0.012), 0.04, 0.5, 1)}
    for r in ROLES: principled(M[r], *WM[r])
    blacks = {}
    for r in ROLES:
        m = bpy.data.materials.new(r + 'B'); principled(m, *BM[r]); blacks[r] = m
    for i, kind in enumerate('KQRBNP'):
        for o in built[kind]:
            o.location.x += i - 2.5; o.location.y += 0.6
            d = o.copy(); d.data = o.data.copy(); link(d)
            d.location.y -= 1.2
            d.data.materials[0] = blacks[o.data.materials[0].name]
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    pl = bpy.context.active_object; pm = bpy.data.materials.new('floor'); principled(pm, (0.55, 0.42, 0.30), 0.4); pl.data.materials.append(pm)
    scene = bpy.context.scene
    world = bpy.data.worlds.new('w'); scene.world = world; world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.6
    bpy.ops.object.light_add(type='AREA', location=(-6, -5, 6)); key = bpy.context.active_object
    key.data.energy = 1500; key.data.size = 5
    key.rotation_euler = (Vector((0, 0, 0)) - key.location).to_track_quat('-Z', 'Y').to_euler()
    cam = bpy.data.cameras.new('cam'); co_ = link(bpy.data.objects.new('cam', cam)); scene.camera = co_
    cam.lens = 85; el = math.radians(80); d = 22
    co_.location = Vector((0, -d * math.cos(el), d * math.sin(el)))
    co_.rotation_euler = (Vector((0, 0, 0)) - co_.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.engine = 'CYCLES'; scene.cycles.samples = 24; scene.cycles.use_denoising = True
    scene.render.resolution_x = 1200; scene.render.resolution_y = 520
    scene.view_settings.view_transform = 'AgX'
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
