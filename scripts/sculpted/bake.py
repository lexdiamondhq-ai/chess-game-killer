# Bakes the board for the app.
#  squares : the 8x8 stone squares, albedo only (lighting comes from SceneKit), 2048 px, rank 8 at the top.
#  art     : the whole board lit from above for the flat look, 9 squares wide (half-square frame), 1536 px.
import bpy, sys, math
sys.path.insert(0,'scripts/sculpted'); import board as BD
from mathutils import Vector
argv=sys.argv[sys.argv.index('--')+1:]; mode=argv[0]; out=argv[1]; samples=int(argv[2])
bpy.ops.wm.read_factory_settings(use_empty=True); sc=bpy.context.scene
def vary(m, k):
    """Each square shows a different part of the slab: offset the texture by the object's random number."""
    nt=m.node_tree; N=nt.nodes; L=nt.links
    mp=[n for n in N if n.type=='MAPPING'][0]
    oi=N.new('ShaderNodeObjectInfo'); cx=N.new('ShaderNodeCombineXYZ')
    mul=[N.new('ShaderNodeMath') for _ in range(3)]
    for node,f in zip(mul,(k*37.0,k*23.0,k*11.0)):
        node.operation='MULTIPLY'; node.inputs[1].default_value=f; L.new(oi.outputs['Random'],node.inputs[0])
    for node,s in zip(mul,('X','Y','Z')): L.new(node.outputs[0],cx.inputs[s])
    L.new(cx.outputs['Vector'],mp.inputs['Location'])
light=BD.marble('carrara',(0.2,0.195,0.183),(0.165,0.16,0.152),scale=0.5,rough=0.22,contrast=0.25)
dark=BD.marble('nero',(0.034,0.035,0.04),(0.06,0.062,0.068),scale=0.45,rough=0.18,contrast=0.25)
vary(light,1.0); vary(dark,1.3)
frame=BD.plain('frame',(0.014,0.014,0.016),0.4,0.15)
plat=bpy.data.materials.new('plat'); plat.use_nodes=True; b=plat.node_tree.nodes['Principled BSDF']
b.inputs['Base Color'].default_value=(0.86,0.86,0.88,1); b.inputs['Metallic'].default_value=1; b.inputs['Roughness'].default_value=0.16
objs=BD.build(light,dark,frame,plat)
# no engraved coordinates in either bake: the app draws its own
for o in objs:
    if o.type=='FONT': bpy.data.objects.remove(o)
cam=bpy.data.cameras.new('c'); cam.type='ORTHO'; co=bpy.data.objects.new('c',cam); sc.collection.objects.link(co); sc.camera=co
co.location=(0,0,20); co.rotation_euler=(0,0,0)
sc.render.engine='CYCLES'; sc.cycles.samples=samples; sc.cycles.device='CPU'
if mode=='squares':
    # albedo: route each material's base color straight to an emission shader
    for m in (light,dark):
        nt=m.node_tree; N=nt.nodes; L=nt.links; bsdf=N['Principled BSDF']; outn=N['Material Output']
        src=bsdf.inputs['Base Color'].links[0].from_socket
        em=N.new('ShaderNodeEmission'); L.new(src,em.inputs['Color']); L.new(em.outputs[0],outn.inputs['Surface'])
    cam.ortho_scale=8.0; sc.render.resolution_x=sc.render.resolution_y=2048
    sc.view_settings.view_transform='Standard'; sc.view_settings.look='None'
    sc.cycles.use_denoising=False; sc.cycles.max_bounces=0
    w=bpy.data.worlds.new('w'); sc.world=w; w.use_nodes=True; w.node_tree.nodes['Background'].inputs['Strength'].default_value=0
    sc.render.image_settings.file_format='PNG'
else:
    cam.ortho_scale=9.0; sc.render.resolution_x=sc.render.resolution_y=1536
    sc.view_settings.view_transform='AgX'; sc.view_settings.look='AgX - Medium High Contrast'; sc.cycles.use_denoising=True
    w=bpy.data.worlds.new('w'); sc.world=w; w.use_nodes=True; bg=w.node_tree.nodes['Background']
    bg.inputs['Color'].default_value=(0.02,0.02,0.022,1); bg.inputs['Strength'].default_value=1
    def area(loc,size,energy,target=(0,0,0),sy=None):
        l=bpy.data.lights.new('a','AREA'); l.energy=energy; l.shape='RECTANGLE'; l.size=size; l.size_y=sy or size
        o=bpy.data.objects.new('a',l); sc.collection.objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-Vector(loc)).to_track_quat('-Z','Y').to_euler()
    area((-7,-6,9),6,2600); area((8,5,6),3,700); area((0,9,7),8,500)
    sc.render.image_settings.file_format='PNG'
sc.render.filepath=out; bpy.ops.render.render(write_still=True)
