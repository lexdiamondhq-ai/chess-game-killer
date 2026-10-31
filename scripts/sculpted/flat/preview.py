"""Renders a flat set on the Gilded board the way the app's flat view shows it (SceneKit), in Cycles:
the same studio, key and rim light, camera (80 degrees, 12 degree lens) and Gilded finishes. Close
enough to judge reflections before a CI run. Usage (bpy as a module, absolute paths):
python preview.py -- <flat-set.bin> <out.png> [overrides.json|-] [size] [samples]
overrides.json: {"mat": {"black.jewel": {"color": [r, g, b], "rough": .., "metal": .., "coat": ..}}, "env": 1.2}"""
import bpy, math, os, sys, json, struct, zlib, numpy as np
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]
BIN, OUT = argv[0], argv[1]
OVR = json.load(open(argv[2])) if len(argv) > 2 and argv[2] != '-' else {}
MOVR = OVR.get('mat', {})
RES = int(argv[3]) if len(argv) > 3 else 800
SAMPLES = int(argv[4]) if len(argv) > 4 else 32
REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'ChessGameKiller', 'Assets.xcassets', 'Sculpted') + '/'
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def lin(c): return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)

def pbr(name, color, rough, metal=0.0, coat=0.0, coat_rough=0.05, glow=None, spec=0.5):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*lin(color), 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    b.inputs['Coat Weight'].default_value = coat
    b.inputs['Coat Roughness'].default_value = coat_rough
    b.inputs['Specular IOR Level'].default_value = spec
    if glow:
        b.inputs['Emission Color'].default_value = (*lin(glow), 1)
        b.inputs['Emission Strength'].default_value = 1.0
    return m

# Gilded look, as SculptedAssets builds it
GOLD = (1, 0.84, 0.58); GLOW = (0.42, 0.3, 0.12)
MAT = {
    ('white', 'body'): dict(color=(0.88, 0.84, 0.76), rough=0.3, coat=0.6, coat_rough=0.05),
    ('black', 'body'): dict(color=(0.06, 0.06, 0.066), rough=0.22, coat=1, coat_rough=0.04),
    ('white', 'metal'): dict(color=GOLD, rough=0.3, metal=1, glow=GLOW),
    ('black', 'metal'): dict(color=GOLD, rough=0.3, metal=1, glow=GLOW),
    ('white', 'ink'): dict(color=(0.06, 0.06, 0.066), rough=0.22, coat=1, coat_rough=0.04),
    ('black', 'ink'): dict(color=GOLD, rough=0.3, metal=1, glow=GLOW),
    ('white', 'jewel'): dict(color=(0.94, 0.94, 0.94), rough=0.03, metal=0.3, coat=1, coat_rough=0.01),
    ('black', 'jewel'): dict(color=(0.035, 0.035, 0.035), rough=0.03, metal=0.45, coat=1, coat_rough=0.01),
}
for k, v in MOVR.items():
    side, role = k.split('.'); MAT[(side, role)] = v
ROLES = ['body', 'metal', 'ink', 'jewel', 'shade', 'cross']
mats = {k: pbr(f'{k[0]}-{k[1]}', **v) for k, v in MAT.items()}

# meshes
raw = zlib.decompress(open(BIN, 'rb').read(), -15)
o = 0
def take(n):
    global o; b = raw[o:o + n]; o += n; return b
assert take(4) == b'SCLP'; ver, count = struct.unpack('<II', take(8))
meshes = {}
for _ in range(count):
    letter, pc, _ = struct.unpack('<BBH', take(4)); parts = []
    for _ in range(pc):
        fin, vc, ic = struct.unpack('<B3xII', take(12))
        pos = np.frombuffer(take(vc * 12), np.float32).reshape(-1, 3)
        nor = np.frombuffer(take(vc * 12), np.float32).reshape(-1, 3)
        idx = np.frombuffer(take(ic * 4), np.uint32).reshape(-1, 3)
        parts.append((ROLES[fin], pos, nor, idx))
    meshes[chr(letter)] = parts

def place(kind, side, f, r):
    for i, (role, pos, nor, idx) in enumerate(meshes[kind]):
        P = np.stack([pos[:, 0], -pos[:, 2], pos[:, 1]], 1)
        N = np.stack([nor[:, 0], -nor[:, 2], nor[:, 1]], 1)
        me = bpy.data.meshes.new(f'{kind}{i}')
        me.from_pydata(P.tolist(), [], idx.tolist()); me.update()
        me.shade_smooth()
        loopn = N[[l.vertex_index for l in me.loops]]
        me.normals_split_custom_set(loopn.tolist())
        ob = bpy.data.objects.new(f'{side}{kind}{i}', me); sc.collection.objects.link(ob)
        me.materials.append(mats.get((side, role)) or mats[(side, 'body')])
        ob.location = (f - 3.5, r - 3.5, 0)

layout = 'r1bq1b1r/ppp3pp/2n1k3/3np3/2B5/5Q2/PPPP1PPP/RNB1K2R'  # the CI showcase game, move 8
for ri, row in enumerate(layout.split('/')):
    f = 0
    for ch in row:
        if ch.isdigit(): f += int(ch); continue
        place(ch.upper(), 'white' if ch.isupper() else 'black', f, 7 - ri); f += 1

# board
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0)); pl = bpy.context.active_object
bm = bpy.data.materials.new('squares'); bm.use_nodes = True
nt = bm.node_tree; b = nt.nodes['Principled BSDF']
tex = nt.nodes.new('ShaderNodeTexImage'); tex.image = bpy.data.images.load(REPO + 'sculpted-squares-gilded.imageset/sculpted-squares-gilded.jpg')
nt.links.new(tex.outputs['Color'], b.inputs['Base Color'])
b.inputs['Roughness'].default_value = 0.22; b.inputs['Coat Weight'].default_value = 0.5; b.inputs['Coat Roughness'].default_value = 0.05
pl.data.materials.append(bm)

# studio
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
env = w.node_tree.nodes.new('ShaderNodeTexEnvironment')
env.image = bpy.data.images.load(REPO + 'sculpted-env-studio.imageset/sculpted-env-studio.png')
w.node_tree.links.new(env.outputs['Color'], w.node_tree.nodes['Background'].inputs['Color'])
w.node_tree.nodes['Background'].inputs['Strength'].default_value = OVR.get('env', 1.2)

def sun(name, at, strength, color, angle=2.0):
    d = bpy.data.lights.new(name, 'SUN'); d.energy = strength; d.color = lin(color); d.angle = math.radians(angle)
    ob = bpy.data.objects.new(name, d); sc.collection.objects.link(ob)
    ob.location = Vector(at)
    ob.rotation_euler = (-Vector(at)).to_track_quat('-Z', 'Y').to_euler()
sun('key', (-6, -5, 9), OVR.get('key', 0.41 * math.pi * math.pi), (1, 0.95, 0.88))
sun('rim', (7, 6, 4), OVR.get('rim', 0.54 * math.pi), (0.8, 0.87, 1))

cam = bpy.data.cameras.new('cam'); co = bpy.data.objects.new('cam', cam); sc.collection.objects.link(co); sc.camera = co
cam.sensor_fit = 'VERTICAL'; cam.angle = math.radians(12)
el = math.radians(80); d = 4.25 / math.tan(math.radians(6))
co.location = Vector((0, -d * math.cos(el), d * math.sin(el)))
co.rotation_euler = (Vector((0, 0, 0)) - co.location).to_track_quat('-Z', 'Y').to_euler()
sc.render.engine = 'CYCLES'; sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = True
sc.cycles.device = 'CPU'
sc.render.resolution_x = RES; sc.render.resolution_y = RES
sc.view_settings.view_transform = 'Standard'
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
