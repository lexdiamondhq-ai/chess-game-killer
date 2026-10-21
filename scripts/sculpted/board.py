import bpy, math
def marble(name, base, vein, scale=3.0, contrast=0.6, rough=0.12, seed=0.0):
    m=bpy.data.materials.new(name); m.use_nodes=True; nt=m.node_tree; N=nt.nodes; Lk=nt.links
    b=N['Principled BSDF']; b.inputs['Roughness'].default_value=rough; b.inputs['Coat Weight'].default_value=0.6; b.inputs['Coat Roughness'].default_value=0.04
    tc=N.new('ShaderNodeTexCoord'); mp=N.new('ShaderNodeMapping'); mp.inputs['Location'].default_value=(seed,seed*1.7,0); mp.inputs['Scale'].default_value=(scale,scale,scale)
    Lk.new(tc.outputs['Object'],mp.inputs['Vector'])
    nz=N.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value=2.2; nz.inputs['Detail'].default_value=12; nz.inputs['Roughness'].default_value=0.62
    Lk.new(mp.outputs['Vector'],nz.inputs['Vector'])
    wv=N.new('ShaderNodeTexWave'); wv.inputs['Scale'].default_value=1.4; wv.inputs['Distortion'].default_value=9; wv.inputs['Detail'].default_value=10; wv.inputs['Detail Roughness'].default_value=0.7
    mix=N.new('ShaderNodeVectorMath'); mix.operation='ADD'; Lk.new(mp.outputs['Vector'],mix.inputs[0]); Lk.new(nz.outputs['Color'],mix.inputs[1])
    Lk.new(mix.outputs['Vector'],wv.inputs['Vector'])
    cr=N.new('ShaderNodeValToRGB'); e=cr.color_ramp; e.elements[0].position=0.0; e.elements[0].color=(*vein,1); e.elements[1].position=0.05; e.elements[1].color=(*base,1)
    Lk.new(wv.outputs['Fac'],cr.inputs['Fac'])
    # subtle cloud variation
    nz2=N.new('ShaderNodeTexNoise'); nz2.inputs['Scale'].default_value=6; nz2.inputs['Detail'].default_value=6; Lk.new(mp.outputs['Vector'],nz2.inputs['Vector'])
    mx=N.new('ShaderNodeMix'); mx.data_type='RGBA'; mx.blend_type='MULTIPLY'; mx.inputs['Factor'].default_value=contrast*0.25
    Lk.new(cr.outputs['Color'],mx.inputs['A']); Lk.new(nz2.outputs['Color'],mx.inputs['B'])
    Lk.new(mx.outputs['Result'],b.inputs['Base Color'])
    return m
def metalmat(name,col,rough):
    m=bpy.data.materials.new(name); m.use_nodes=True; b=m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value=(*col,1); b.inputs['Metallic'].default_value=1; b.inputs['Roughness'].default_value=rough; return m
def plain(name,col,rough,coat=0.5):
    m=bpy.data.materials.new(name); m.use_nodes=True; b=m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value=(*col,1); b.inputs['Roughness'].default_value=rough; b.inputs['Coat Weight'].default_value=coat; return m
def build(light_m, dark_m, frame_m, inlay_m, S=1.0):
    objs=[]
    T=0.12
    for f in range(8):
        for r in range(8):
            lt=(f+r)%2==1
            bpy.ops.mesh.primitive_cube_add(size=1,location=((f-3.5)*S,(r-3.5)*S,-T/2))
            o=bpy.context.active_object; o.scale=(S*0.999,S*0.999,T)
            o.data.materials.append(light_m if lt else dark_m)
            # each square samples a different part of the slab
            o.location.z=-T/2; objs.append(o)
    # frame: four bevelled rails
    W=0.55; Z=0.14
    for (x,y,sx,sy) in [(0,4*S+W/2,8*S+2*W,W),(0,-4*S-W/2,8*S+2*W,W),(4*S+W/2,0,W,8*S),(-4*S-W/2,0,W,8*S)]:
        bpy.ops.mesh.primitive_cube_add(size=1,location=(x,y,-Z/2+0.005)); o=bpy.context.active_object; o.scale=(sx,sy,Z)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        m=o.modifiers.new('b','BEVEL'); m.width=0.012; m.segments=4; o.data.materials.append(frame_m); objs.append(o)
    # platinum inlay line around the playing field
    g=0.09
    for (x,y,sx,sy) in [(0,4*S+g,8*S+2*g+0.012,0.012),(0,-4*S-g,8*S+2*g+0.012,0.012),(4*S+g,0,0.012,8*S+2*g),(-4*S-g,0,0.012,8*S+2*g)]:
        bpy.ops.mesh.primitive_cube_add(size=1,location=(x,y,0.0057)); o=bpy.context.active_object; o.scale=(sx,sy,0.003); o.data.materials.append(inlay_m); objs.append(o)
    # engraved coordinates in platinum
    for i,ch in enumerate('abcdefgh'):
        for y,rot in ((-4*S-0.3,0),):
            bpy.ops.object.text_add(location=((i-3.5)*S,y,0.006),rotation=(0,0,rot)); t=bpy.context.active_object; t.data.body=ch; t.data.align_x='CENTER'; t.data.align_y='CENTER'; t.data.size=0.19; t.data.extrude=0.002
            t.data.materials.append(inlay_m); objs.append(t)
    for i in range(8):
        for x,rot in ((-4*S-0.3,0),):
            bpy.ops.object.text_add(location=(x,(i-3.5)*S,0.006),rotation=(0,0,rot)); t=bpy.context.active_object; t.data.body=str(i+1); t.data.align_x='CENTER'; t.data.align_y='CENTER'; t.data.size=0.19; t.data.extrude=0.002
            t.data.materials.append(inlay_m); objs.append(t)
    return objs
