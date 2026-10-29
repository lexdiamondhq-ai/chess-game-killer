"""The glass tiles for the flat board (Crystal), drawn as pictures the app lays on each tile.

Each tile is rendered on its own in Cycles, built and lit exactly as in the concept render Alex
picked (design/flat-pieces/crystal.jpg): milky glass with the piece inked on top for White,
smoked glass with the piece glowing gold inside for Black, a gold foot under both, one soft key
from the player's left and a faint fill. SceneKit can't draw glass like that, so the app shows
these pictures, lit to follow its own light across the board (SculptedCrystal).

The camera looks at the tile as the flat view does, 80 degrees up from the player's side, but
without perspective, so a picture fits any square. It frames the tile's top and the sliver of
its near side the flat view sees: the picture is as wide as the tile and `w*sin(80) + h*cos(80)`
tall. Pixels outside the tile carry the color of its edge, so the app's rounded tile, cut to
the same outline, never shows a fringe.

Usage (bpy as a module): python glass.py -- <out dir> [width px] [samples] [names, such as wK,bP]
Writes glass-{w,b}{K,Q,R,B,N,P}.png, or only the ones named.
"""
import math
import os
import sys

import bpy
import bmesh  # after bpy, which provides it
import numpy as np
from mathutils import Vector
from shapely.geometry import box

argv = sys.argv[sys.argv.index('--') + 1:]
OUT = argv[0]
WIDTH = int(argv[1]) if len(argv) > 1 else 512
SAMPLES = int(argv[2]) if len(argv) > 2 else 256
ONLY = argv[3].split(',') if len(argv) > 3 else None
HERE = os.path.dirname(os.path.abspath(__file__))
MASKS = os.path.join(HERE, 'crystal-masks')
ELEVATION = math.radians(80)


def size(kind):
    """Width and height of a tile, in squares: the pawn's is smaller (SculptedCrystal.size)."""
    return (0.62, 0.2) if kind == 'P' else (0.78, 0.26)


CORNER = 0.08  # the tile's rounded corners, seen from above
BEVEL = 0.03   # the rounded edges round its top and foot


def srgb(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def principled(name, col, rough=0.3, metal=0.0, coat=0.0, coat_rough=0.05, trans=0.0, ior=1.5, sss=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*col, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    b.inputs['Coat Weight'].default_value = coat
    b.inputs['Coat Roughness'].default_value = coat_rough
    b.inputs['Transmission Weight'].default_value = trans
    b.inputs['IOR'].default_value = ior
    if sss:
        b.inputs['Subsurface Weight'].default_value = sss
        b.inputs['Subsurface Radius'].default_value = (0.05, 0.04, 0.03)
    return m


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def prism(name, poly, z0, z1, mat, bevel=0.0, segs=4):
    """A shapely outline extruded from z0 to z1, its top and bottom edges rounded by `bevel`."""
    bm = bmesh.new()
    edges = []
    for ring in [poly.exterior] + list(poly.interiors):
        pts = list(ring.coords)[:-1]
        vs = [bm.verts.new((x, y, z0)) for x, y in pts]
        edges += [bm.edges.new((vs[i], vs[(i + 1) % len(vs)])) for i in range(len(vs))]
    faces = bmesh.ops.triangle_fill(bm, use_beauty=True, use_dissolve=True, edges=edges)['geom']
    faces = [f for f in faces if isinstance(f, bmesh.types.BMFace)]
    for f in faces:
        if f.normal.z < 0:
            f.normal_flip()
    r = bmesh.ops.extrude_face_region(bm, geom=faces, use_keep_orig=True)
    for v in [e for e in r['geom'] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z = z1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.dissolve_limit(bm, angle_limit=0.01, verts=list(bm.verts), edges=list(bm.edges))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = link(bpy.data.objects.new(name, me))
    ob.data.materials.append(mat)
    if bevel:
        mod = ob.modifiers.new('bev', 'BEVEL')
        mod.width = bevel
        mod.segments = segs
        mod.limit_method = 'ANGLE'
        mod.angle_limit = math.radians(50)
        mod.harden_normals = True
        ob.data.shade_smooth()
    return ob


def disc_face(name, r, z, mat):
    """A round face with UVs spanning the glyph picture, its top away from the player."""
    bpy.ops.mesh.primitive_circle_add(vertices=96, radius=r, fill_type='NGON', location=(0, 0, z))
    ob = bpy.context.active_object
    ob.name = name
    me = ob.data
    uv = me.uv_layers.new()
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (co.x / (2 * r) + 0.5, co.y / (2 * r) + 0.5)
    me.materials.append(mat)
    return ob


def etching(kind, white):
    """The piece, cut from its mask: dark frosted ink on White's tile, glowing gold in Black's."""
    m = bpy.data.materials.new(f'etch{kind}{white}')
    m.use_nodes = True
    nt = m.node_tree
    n, l = nt.nodes, nt.links
    out, b = n['Material Output'], n['Principled BSDF']
    if white:
        b.inputs['Base Color'].default_value = (*srgb('1E1612'), 1)
        b.inputs['Roughness'].default_value = 0.6
    else:
        b.inputs['Base Color'].default_value = (*srgb('F0C878'), 1)
        b.inputs['Roughness'].default_value = 0.3
        b.inputs['Metallic'].default_value = 1
        b.inputs['Emission Color'].default_value = (*srgb('F2C878'), 1)
        b.inputs['Emission Strength'].default_value = 1.5
    tex = n.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(os.path.join(MASKS, f'crystal-{kind}.png'))
    tex.image.colorspace_settings.name = 'Non-Color'
    tex.extension = 'CLIP'
    tc = n.new('ShaderNodeTexCoord')
    l.new(tc.outputs['UV'], tex.inputs['Vector'])
    tr = n.new('ShaderNodeBsdfTransparent')
    mix = n.new('ShaderNodeMixShader')
    l.new(tex.outputs['Alpha'], mix.inputs[0])
    l.new(tr.outputs[0], mix.inputs[1])
    l.new(b.outputs[0], mix.inputs[2])
    l.new(mix.outputs[0], out.inputs['Surface'])
    return m


def tile(kind, white):
    """The concept's Crystal tile (sets.py, crystal): glass block, etching, gold foot."""
    w, h = size(kind)
    outline = box(-w / 2, -w / 2, w / 2, w / 2).buffer(-CORNER).buffer(CORNER, quad_segs=12)
    if white:
        glass = principled('milk', srgb('FFFFFF'), rough=0.04, trans=0.8, ior=1.5, coat=1.0, sss=0.3)
    else:
        glass = principled('smoke', srgb('55504A'), rough=0.05, trans=0.9, ior=1.5, coat=1.0)
    prism('block', outline, 0, h, glass, bevel=BEVEL, segs=6)
    disc_face('etch', w * 0.5, h + 0.002 if white else h * 0.55, etching(kind, white))
    prism('foot', outline.buffer(-0.01), 0, 0.012, principled('golddark', srgb('B98A3A'), rough=0.3, metal=1))


def stage():
    """The concept's board, studio and lights, with the board seen only through the glass."""
    bpy.ops.mesh.primitive_plane_add(size=9.0, location=(0, 0, 0))
    board = bpy.context.active_object
    # Halfway between the Gilded board's cream and brown, so a tile looks the same on either.
    stone = principled('board', srgb('A0938A'), rough=0.35, coat=0.3)
    board.data.materials.append(stone)
    board.visible_camera = False
    world = bpy.data.worlds.new('w')
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.5, 0.5, 0.5, 1)
    bg.inputs['Strength'].default_value = 0.5
    for location, energy, spread in (((-7, -6, 7), 2200, 6), ((7, 2, 5), 400, 8)):
        bpy.ops.object.light_add(type='AREA', location=location)
        light = bpy.context.active_object
        light.data.energy = energy
        light.data.size = spread
        light.rotation_euler = (Vector((0, 0, 0)) - light.location).to_track_quat('-Z', 'Y').to_euler()


def camera(kind):
    """Orthographic, 80 degrees up from the player's side, framing the tile's top and near side."""
    w, h = size(kind)
    cam = bpy.data.cameras.new('cam')
    cam.type = 'ORTHO'
    cam.sensor_fit = 'HORIZONTAL'
    cam.ortho_scale = w
    ob = link(bpy.data.objects.new('cam', cam))
    bpy.context.scene.camera = ob
    target = Vector((0, 0, h / 2))
    ob.location = target + 20 * Vector((0, -math.cos(ELEVATION), math.sin(ELEVATION)))
    ob.rotation_euler = (target - ob.location).to_track_quat('-Z', 'Y').to_euler()
    cam.clip_end = 100
    scene = bpy.context.scene
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = round(WIDTH * (w * math.sin(ELEVATION) + h * math.cos(ELEVATION)) / w)


def render(path):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.cycles.caustics_reflective = False
    scene.cycles.caustics_refractive = False
    scene.cycles.max_bounces = 10
    scene.cycles.transmission_bounces = 10
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def fill_outside(path):
    """Gives every pixel outside the tile the color of the nearest edge, and drops the alpha."""
    from PIL import Image
    image = np.asarray(Image.open(path).convert('RGBA')).astype(np.float64) / 255
    rgb, alpha = image[..., :3], image[..., 3]
    known = alpha > 0.98
    filled = np.where(known[..., None], rgb, 0)
    for _ in range(64):
        if known.all():
            break
        total = np.zeros_like(filled)
        count = np.zeros(known.shape)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            shifted = np.roll(np.roll(filled, dy, 0), dx, 1)
            seen = np.roll(np.roll(known, dy, 0), dx, 1)
            total += shifted * seen[..., None]
            count += seen
        grow = ~known & (count > 0)
        filled[grow] = total[grow] / count[grow][:, None]
        known = known | grow
    # The tile's own edge pixels keep their color, laid over the edge color they fade into.
    out = rgb * alpha[..., None] + filled * (1 - alpha[..., None])
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').save(path)


os.makedirs(OUT, exist_ok=True)
for white in (True, False):
    for kind in 'KQRBNP':
        name = f"{'w' if white else 'b'}{kind}"
        if ONLY and name not in ONLY:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        tile(kind, white)
        stage()
        camera(kind)
        path = os.path.join(os.path.abspath(OUT), f'glass-{name}.png')
        render(path)
        fill_outside(path)
        print('wrote', path)
