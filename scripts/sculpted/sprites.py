# Renders a set as flat-look sprites for the app's small boards:
# 520 x 568 px, 400 px per square, the piece's foot at (260, 400), seen from 50 degrees like the 3D board.
# Usage: sprites.py -- outdir samples [classic | gilded] [one name, such as sculpted-wN or gilded-bK]
import bpy, sys, math, numpy as np
sys.path.insert(0,'scripts/sculpted'); import pieces as P
from mathutils import Vector
argv=sys.argv[sys.argv.index('--')+1:]; outdir=argv[0]; samples=int(argv[1]); rest=argv[2:]
SET=rest.pop(0) if rest and rest[0] in ('classic','gilded') else 'classic'
only=rest[0] if rest else None
PREFIX='gilded' if SET=='gilded' else 'sculpted'
if SET=='gilded':
    import gilded as G
    knight_parts=G.load_knight()
def mat(name,col,rough,metal=0,coat=0,sss=0,trans=0,ior=1.5,coat_rough=0.05,spec=None,emit=None,emit_strength=0,edge=0):
    m=bpy.data.materials.new(name); m.use_nodes=True; b=m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value=(*col,1); b.inputs['Roughness'].default_value=rough; b.inputs['Metallic'].default_value=metal
    if edge:
        # darker toward the silhouette, as the 3D board's ivoryEdge: color * (1 - edge * (1 - N.V)^2)
        nt=m.node_tree; lw=nt.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value=0.5
        pw=nt.nodes.new('ShaderNodeMath'); pw.operation='POWER'; pw.inputs[1].default_value=2
        mu=nt.nodes.new('ShaderNodeMath'); mu.operation='MULTIPLY_ADD'; mu.inputs[1].default_value=-edge; mu.inputs[2].default_value=1
        sc=nt.nodes.new('ShaderNodeVectorMath'); sc.operation='SCALE'; sc.inputs[0].default_value=col
        nt.links.new(lw.outputs['Facing'],pw.inputs[0]); nt.links.new(pw.outputs[0],mu.inputs[0])
        nt.links.new(mu.outputs[0],sc.inputs['Scale']); nt.links.new(sc.outputs[0],b.inputs['Base Color'])
    b.inputs['Coat Weight'].default_value=coat; b.inputs['Coat Roughness'].default_value=coat_rough
    if spec is not None: b.inputs['Specular IOR Level'].default_value=spec
    if emit: b.inputs['Emission Color'].default_value=(*emit,1); b.inputs['Emission Strength'].default_value=emit_strength
    if sss: b.inputs['Subsurface Weight'].default_value=sss; b.inputs['Subsurface Radius'].default_value=(0.02,0.015,0.01); b.inputs['Subsurface Scale'].default_value=0.05
    if trans: b.inputs['Transmission Weight'].default_value=trans; b.inputs['IOR'].default_value=ior
    return m
if SET=='classic': kv=np.load('scripts/sculpted/kv.npy'); kf=np.load('scripts/sculpted/kf.npy')
EL=math.radians(50)
for side in ('w','b'):
    for t in 'KQRBNP':
        name=f'{PREFIX}-{side}{t}'
        if only and only!=name: continue
        bpy.ops.wm.read_factory_settings(use_empty=True); sc=bpy.context.scene
        if SET=='gilded':
            # bright cream ivory, darker toward its outline, and polished onyx; warm gold, the knight's amber eye
            F=dict(white=mat('ivory',(0.745,0.672,0.54),0.3,coat=0.6,sss=0.25,edge=0.35), black=mat('onyx',(0.006,0.006,0.007),0.22,coat=1.0,coat_rough=0.03),
                   metal=mat('gold',(1.0,0.6,0.26),0.2,metal=1), gem=mat('amber',(1.0,0.45,0.08),0.08,coat=1.0,coat_rough=0.02,emit=(1.0,0.38,0.04),emit_strength=2.2))
            F['pearl']=F['metal']
        else:
            # a warm, slightly deep ivory, so the shading reads against the light squares
            F=dict(white=mat('ivory',(0.6,0.52,0.4),0.32,coat=0.35,sss=0.3), black=mat('ebony',(0.012,0.011,0.011),0.42,coat=0.35,coat_rough=0.06,spec=0.25),
                   metal=mat('plat',(0.86,0.86,0.88),0.16,metal=1), gem=mat('sapph',(0.05,0.12,0.6),0.02,trans=1,ior=1.77), pearl=mat('pearl',(0.93,0.9,0.86),0.18,coat=1,sss=0.2))
        M={'body':F['white'] if side=='w' else F['black'],'metal':F['metal'],'gem':F['gem'],'pearl':F['pearl']}
        if SET=='gilded':
            g={'K':G.king,'Q':G.queen,'B':G.bishop,'R':G.rook,'P':G.pawn}[t](M) if t!='N' else G.knight(M,*knight_parts)
        else:
            g={'K':P.king,'Q':P.queen,'B':P.bishop,'R':P.rook,'P':P.pawn}[t](M) if t!='N' else P.knight(M,kv,kf)
        # the classic knight looks left; the gilded knight looks right, as in its artwork
        if t=='N': g.rotation_euler=(0,0,math.radians(186 if SET=='gilded' else 6))
        if t=='B': g.rotation_euler=(0,0,math.radians(-112))
        bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,0)); fl=bpy.context.active_object; fl.is_shadow_catcher=True
        w=bpy.data.worlds.new('w'); sc.world=w; w.use_nodes=True; wn=w.node_tree.nodes; wl=w.node_tree.links
        tc=wn.new('ShaderNodeTexCoord'); sep=wn.new('ShaderNodeSeparateXYZ'); wl.new(tc.outputs['Generated'],sep.inputs[0])
        ramp=wn.new('ShaderNodeValToRGB'); r=ramp.color_ramp; r.elements[0].position=0.45; r.elements[0].color=(0.01,0.01,0.012,1); r.elements[1].position=0.95; r.elements[1].color=((0.33,0.335,0.36,1) if side=='w' else (0.2,0.205,0.22,1))
        mr=wn.new('ShaderNodeMapRange'); mr.inputs['From Min'].default_value=-1; mr.inputs['From Max'].default_value=1
        wl.new(sep.outputs['Z'],mr.inputs['Value']); wl.new(mr.outputs['Result'],ramp.inputs['Fac'])
        wl.new(ramp.outputs['Color'],wn['Background'].inputs['Color'])
        def area(loc,size,energy,col=(1,1,1),target=(0,0,0.4),sy=None):
            l=bpy.data.lights.new('a','AREA'); l.energy=energy; l.color=col; l.shape='RECTANGLE'; l.size=size; l.size_y=sy or size
            o=bpy.data.objects.new('a',l); sc.collection.objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-Vector(loc)).to_track_quat('-Z','Y').to_euler()
        # ivory is light already: a small, low key from the left and little fill, so one side of
        # each piece falls into shade and the flutes, crowns and the knight's face stand out
        lk,lr,lf=(1.25,1.0,0.1) if side=='w' else (1,1,1)
        if side=='w': area((-4.5,-1.2,3.0),1.0,620*lk,target=(0,0,0.4))
        else: area((-2.4,-3,5.2),3,620*lk,target=(0,0,0.4))
        area((3.5,1.5,1.5),0.5,220*lr,(0.9,0.95,1.0),target=(0,0.4,0.5),sy=4)
        area((0,4,3),4,130*lf,target=(0,0,0.5))
        area((0,-4,0.6),6,40*lf,target=(0,0,0.5),sy=1)
        cam=bpy.data.cameras.new('c'); cam.type='ORTHO'; cam.sensor_fit='HORIZONTAL'; cam.ortho_scale=1.3
        co=bpy.data.objects.new('c',cam); sc.collection.objects.link(co); sc.camera=co
        d=Vector((0,math.cos(EL),-math.sin(EL))); u=Vector((0,math.sin(EL),math.cos(EL)))
        tgt=Vector((0,0,0))+u*0.29; co.location=tgt-d*12; co.rotation_euler=d.to_track_quat('-Z','Y').to_euler()
        cam.clip_start=1; cam.clip_end=30
        sc.render.engine='CYCLES'; sc.cycles.samples=samples; sc.cycles.use_denoising=True; sc.cycles.device='CPU'
        sc.render.film_transparent=True; sc.render.resolution_x=520; sc.render.resolution_y=568
        sc.view_settings.view_transform='AgX'; sc.view_settings.look='AgX - High Contrast' if side=='w' else 'AgX - Medium High Contrast'
        # ebony stays deep at phone size: the body well below the dark squares, the highlights still crisp
        if side=='b': sc.view_settings.exposure=-0.9; sc.view_settings.look='AgX - High Contrast'
        if side=='w': sc.view_settings.exposure=-0.1
        sc.render.image_settings.file_format='PNG'; sc.render.image_settings.color_mode='RGBA'
        sc.render.filepath=f'{outdir}/{name}.png'; bpy.ops.render.render(write_still=True)
        print('done',name,flush=True)
