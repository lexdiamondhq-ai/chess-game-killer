# Renders a set as flat-look sprites (sprite contract v2, shared by every set in the app):
# 560 x 760 px RGBA, orthographic, 28 degrees above the board, 400 px per square, the piece's
# foot at (280, 600), so the picture spans 0.7 squares either side of the foot, 1.5 above it
# and 0.4 below. A soft contact shadow lies under each piece. Next to each picture it writes
# mask/<name>.png, the piece alone (no shadow), which fade.py uses for the ivory's contour.
# Usage: sprites.py -- outdir samples [classic | gilded] [names such as sculpted-wN gilded-bK ...]
#        [--res percent] for quick tests, [--light tweaks.json] to try other light levels.
import bpy, sys, os, math, json, numpy as np
sys.path.insert(0,'scripts/sculpted'); import pieces as P
from mathutils import Vector
argv=sys.argv[sys.argv.index('--')+1:]
opts={}
for key in ('--res','--light'):
    while key in argv: i=argv.index(key); opts[key[2:]]=argv[i+1]; del argv[i:i+2]
outdir=argv[0]; samples=int(argv[1]); rest=argv[2:]
SET=rest.pop(0) if rest and rest[0] in ('classic','gilded') else 'classic'
only=set(rest)
PREFIX='gilded' if SET=='gilded' else 'sculpted'
if SET=='gilded':
    import gilded as G
    knight_parts=G.load_knight()
EL=math.radians(28); W,H=560,760; SCALE=1.4; FOOT=(280,600)
# The light, per side. Ivory: a key from the front left and little fill, so one side falls into
# soft shade and the ivory stays brighter than the cream squares; ebony: the same key with more
# fill, and polished, so it shows the studio: a dark card on the floor in front keeps its face
# black, a light floor behind it gives its outline a bright edge on the darkest squares.
LIGHT={
    'w':dict(key=((-3.4,-3.0,3.4),1.2,620),fill=((3.2,-2.6,1.4),4,50),top=((0,1.5,5),3,130),rims=[],exposure=0.25,floor=500,
             look='AgX - Medium High Contrast'),
    'b':dict(key=((-3.0,-3.2,3.6),2.4,560),fill=((3.2,-2.6,1.4),4,120),top=((0,1.5,5),3,160),
             rims=[((-2.6,3.4,1.3),0.35,3,260),((2.8,3.0,1.6),0.35,3,300)],exposure=-0.5,floor=1400,
             card=(0.85,0.06,0.7,-0.05,-1.3,-1.7),look='AgX - Medium High Contrast'),
}
# the gilded ivory carries more gold and a glossier coat: a touch more light keeps it as bright
SET_LIGHT={'gilded':{'w':dict(exposure=0.4)}}
FIN={
    'classic':dict(ivory=(0.8,0.765,0.69),ivory_rough=0.32,ivory_coat=0.35,edge=0.5,power=1.5,
                   ebony=(0.015,0.014,0.014),ebony_rough=0.42,ebony_coat=0.35,metal=(0.86,0.86,0.88),metal_rough=0.16,
                   ivory_metal=(0.09,0.09,0.1)),
    'gilded':dict(ivory=(0.8,0.765,0.69),ivory_rough=0.3,ivory_coat=0.6,edge=0.5,power=1.5,
                  ebony=(0.006,0.006,0.007),ebony_rough=0.22,ebony_coat=1.0,metal=(1.0,0.6,0.26),metal_rough=0.2),
}
for side,v in SET_LIGHT.get(SET,{}).items(): LIGHT[side].update(v)
if 'light' in opts:
    tw=json.load(open(opts['light']))
    for k,v in tw.get('w',{}).items(): LIGHT['w'][k]=v
    for k,v in tw.get('b',{}).items(): LIGHT['b'][k]=v
    for k,v in tw.get('fin',{}).items(): FIN[SET][k]=v
def edge_darkening(m,col,edge,power):
    """Darker toward the silhouette, as the 3D board's ivoryEdge: color * (1 - edge * (1 - N.V)^power)."""
    nt=m.node_tree; b=nt.nodes['Principled BSDF']
    lw=nt.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value=0.5
    pw=nt.nodes.new('ShaderNodeMath'); pw.operation='POWER'; pw.inputs[1].default_value=power
    mu=nt.nodes.new('ShaderNodeMath'); mu.operation='MULTIPLY_ADD'; mu.inputs[1].default_value=-edge; mu.inputs[2].default_value=1
    sc=nt.nodes.new('ShaderNodeVectorMath'); sc.operation='SCALE'; sc.inputs[0].default_value=col
    nt.links.new(lw.outputs['Facing'],pw.inputs[0]); nt.links.new(pw.outputs[0],mu.inputs[0])
    nt.links.new(mu.outputs[0],sc.inputs['Scale']); nt.links.new(sc.outputs[0],b.inputs['Base Color'])
def mat(name,col,rough,metal=0,coat=0,sss=0,trans=0,ior=1.5,coat_rough=0.05,spec=None,emit=None,emit_strength=0,edge=0,power=2):
    m=bpy.data.materials.new(name); m.use_nodes=True; b=m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value=(*col,1); b.inputs['Roughness'].default_value=rough; b.inputs['Metallic'].default_value=metal
    if edge: edge_darkening(m,col,edge,power)
    b.inputs['Coat Weight'].default_value=coat; b.inputs['Coat Roughness'].default_value=coat_rough
    if spec is not None: b.inputs['Specular IOR Level'].default_value=spec
    if emit: b.inputs['Emission Color'].default_value=(*emit,1); b.inputs['Emission Strength'].default_value=emit_strength
    if sss: b.inputs['Subsurface Weight'].default_value=sss; b.inputs['Subsurface Radius'].default_value=(0.02,0.015,0.01); b.inputs['Subsurface Scale'].default_value=0.05
    if trans: b.inputs['Transmission Weight'].default_value=trans; b.inputs['IOR'].default_value=ior
    return m
def finishes(side):
    """The set's materials, as the 3D looks have them (SculptedLook in SculptedAssets.swift)."""
    f=FIN[SET]
    white=mat('ivory',tuple(f['ivory']),f['ivory_rough'],coat=f['ivory_coat'],sss=0.25,edge=f['edge'],power=f['power'])
    if SET=='gilded':
        black=mat('onyx',tuple(f['ebony']),f['ebony_rough'],coat=f['ebony_coat'],coat_rough=0.03)
        metal=mat('gold',tuple(f['metal']),f['metal_rough'],metal=1)
        gem=mat('amber',(1.0,0.45,0.08),0.08,coat=1.0,coat_rough=0.02,emit=(1.0,0.38,0.04),emit_strength=2.2)
        pearl=metal
    else:
        black=mat('ebony',tuple(f['ebony']),f['ebony_rough'],coat=f['ebony_coat'],coat_rough=0.06,spec=0.25)
        gem=mat('sapph',(0.05,0.12,0.6),0.02,trans=1,ior=1.77)
        if side=='w':
            # Ivory takes the ebony's colour for its marks: blackened silver and onyx beads, so the
            # cross, crown, mitre cut, battlements and mane stand out dark on the white pieces, as
            # the platinum does light on the black ones.
            metal=mat('blacksilver',tuple(f['ivory_metal']),0.28,metal=1,coat=0.6,coat_rough=0.05)
            pearl=mat('onyx',(0.012,0.012,0.014),0.15,coat=1,coat_rough=0.03)
        else:
            metal=mat('metal',tuple(f['metal']),f['metal_rough'],metal=1)
            pearl=mat('pearl',(0.93,0.9,0.86),0.18,coat=1,sss=0.2)
    shade=mat('well',(0.09,0.075,0.06) if side=='w' else (0.004,0.004,0.004),0.6)
    return {'body':white if side=='w' else black,'metal':metal,'gem':gem,'pearl':pearl,'shade':shade}
if SET=='classic': kv=np.load('scripts/sculpted/kv.npy'); kf=np.load('scripts/sculpted/kf.npy')
def objects(o): return [o]+[c for c in o.children_recursive]
os.makedirs(f'{outdir}/mask',exist_ok=True)
for side in ('w','b'):
    for t in 'KQRBNP':
        name=f'{PREFIX}-{side}{t}'
        if only and name not in only: continue
        bpy.ops.wm.read_factory_settings(use_empty=True); sc=bpy.context.scene
        M=finishes(side)
        if SET=='gilded':
            g={'K':G.king,'Q':G.queen,'B':G.bishop,'R':G.rook,'P':G.pawn}[t](M) if t!='N' else G.knight(M,*knight_parts)
        else:
            g={'K':P.king,'Q':P.queen,'B':P.bishop,'R':P.rook,'P':P.pawn}[t](M) if t!='N' else P.knight(M,kv,kf)
        # as the 3D board turns them: the classic knight looks left, the gilded knight right, as in its artwork
        if t=='N': g.rotation_euler=(0,0,math.radians(186 if SET=='gilded' else 6))
        if t=='B': g.rotation_euler=(0,0,math.radians(-112))
        piece=bpy.data.collections.new('piece'); sc.collection.children.link(piece)
        for o in objects(g):
            for c in list(o.users_collection): c.objects.unlink(o)
            piece.objects.link(o)
        # the floor: invisible itself, it catches the shadow, and the polished stone and metal reflect it
        bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,0)); fl=bpy.context.active_object; fl.is_shadow_catcher=True
        floor=bpy.data.collections.new('floor'); sc.collection.children.link(floor)
        for c in list(fl.users_collection): c.objects.unlink(fl)
        floor.objects.link(fl)
        card=LIGHT[side].get('card')
        if card:
            # as in a studio: a dark card on the floor in front of the piece keeps its front black,
            # a light floor behind it gives its outline a bright edge; past the card, light again for the metal
            back,front,far,y0,y1,y2=card
            fm=bpy.data.materials.new('floor'); fm.use_nodes=True; fn=fm.node_tree.nodes; flk=fm.node_tree.links
            ftc=fn.new('ShaderNodeTexCoord'); fsep=fn.new('ShaderNodeSeparateXYZ'); flk.new(ftc.outputs['Object'],fsep.inputs[0])
            fr=fn.new('ShaderNodeValToRGB'); e=fr.color_ramp.elements
            e[0].position=0.0; e[0].color=(far,far,far,1); e[1].position=1.0; e[1].color=(back,back,back,1)
            for pos,v in ((y2,far),(y1,front),(y0,front),(y0+0.15,back)):
                el=e.new((pos+3)/6); el.color=(v,v,v,1)
            fmr=fn.new('ShaderNodeMapRange'); fmr.inputs['From Min'].default_value=-3; fmr.inputs['From Max'].default_value=3
            flk.new(fsep.outputs['Y'],fmr.inputs['Value']); flk.new(fmr.outputs['Result'],fr.inputs['Fac'])
            flk.new(fr.outputs['Color'],fn['Principled BSDF'].inputs['Base Color'])
            fl.data.materials.append(fm)
        # the studio the polished pieces reflect: dark below, a soft bright top
        w=bpy.data.worlds.new('w'); sc.world=w; w.use_nodes=True; wn=w.node_tree.nodes; wl=w.node_tree.links
        tc=wn.new('ShaderNodeTexCoord'); sep=wn.new('ShaderNodeSeparateXYZ'); wl.new(tc.outputs['Generated'],sep.inputs[0])
        ramp=wn.new('ShaderNodeValToRGB'); r=ramp.color_ramp; r.elements[0].position=0.45; r.elements[0].color=(0.01,0.01,0.012,1); r.elements[1].position=0.95; r.elements[1].color=((0.33,0.335,0.36,1) if side=='w' else (0.2,0.205,0.22,1))
        mr=wn.new('ShaderNodeMapRange'); mr.inputs['From Min'].default_value=-1; mr.inputs['From Max'].default_value=1
        wl.new(sep.outputs['Z'],mr.inputs['Value']); wl.new(mr.outputs['Result'],ramp.inputs['Fac'])
        wl.new(ramp.outputs['Color'],wn['Background'].inputs['Color'])
        def area(loc,size,energy,col=(1,1,1),target=(0,0,0.4),sy=None,lights=piece):
            l=bpy.data.lights.new('a','AREA'); l.energy=energy; l.color=col; l.shape='RECTANGLE'; l.size=size; l.size_y=sy or size
            o=bpy.data.objects.new('a',l); sc.collection.objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-Vector(loc)).to_track_quat('-Z','Y').to_euler()
            # the studio lights light the piece only; the floor's shadow comes from the soft light overhead
            if lights is not None: o.light_linking.receiver_collection=lights
            return o
        L=LIGHT[side]
        area(*L['key'],target=(0,0,0.45))
        area(*L['fill'],(0.95,0.97,1.0),target=(0,0,0.5))
        area(*L['top'],target=(0,0,0.5))
        for loc,sx,sy,e in L['rims']: area(loc,sx,e,(0.92,0.96,1.0),target=(0,0,0.5),sy=sy)
        # the contact shadow; how bright the floor shows in the pieces' reflections (not how dark the shadow is)
        area((-0.6,-0.4,4.0),2.2,L.get('floor',500),target=(0,0,0),lights=floor)
        cam=bpy.data.cameras.new('c'); cam.type='ORTHO'; cam.sensor_fit='HORIZONTAL'; cam.ortho_scale=SCALE
        co=bpy.data.objects.new('c',cam); sc.collection.objects.link(co); sc.camera=co
        d=Vector((0,math.cos(EL),-math.sin(EL))); u=Vector((0,math.sin(EL),math.cos(EL)))
        # the foot at (280, 600): the picture's middle is 0.55 squares above it
        tgt=u*((FOOT[1]-H/2)/(W/SCALE))
        co.location=tgt-d*12; co.rotation_euler=d.to_track_quat('-Z','Y').to_euler()
        cam.clip_start=1; cam.clip_end=30
        sc.render.engine='CYCLES'; sc.cycles.samples=samples; sc.cycles.use_denoising=True; sc.cycles.device='CPU'
        sc.render.film_transparent=True; sc.render.resolution_x=W; sc.render.resolution_y=H
        sc.render.resolution_percentage=int(opts.get('res',100))
        sc.view_settings.view_transform='AgX'; sc.view_settings.look=L['look']
        sc.view_settings.exposure=L['exposure']
        sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGBA'
        sc.render.filepath=f'{outdir}/{name}.png'; bpy.ops.render.render(write_still=True)
        # the piece alone, for the contour: no floor, a flat material, a few samples
        fl.hide_render=True; flat=bpy.data.materials.new('flat'); sc.view_layers[0].material_override=flat
        sc.cycles.samples=16; sc.cycles.use_denoising=False
        sc.render.filepath=f'{outdir}/mask/{name}.png'; bpy.ops.render.render(write_still=True)
        print('done',name,flush=True)
