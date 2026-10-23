import bpy, bmesh, numpy as np, math
SOLVER='EXACT'
from mathutils import Vector, Matrix
TAU=2*math.pi
# ---------- profile helpers: lists of (r, z), bottom to top ----------
def arc(cx,cz,rad,a0,a1,n=16): return [(cx+rad*math.cos(a0+(a1-a0)*i/n), cz+rad*math.sin(a0+(a1-a0)*i/n)) for i in range(n+1)]
def bead(r,z0,h,n=16):  # half-round bulging outward, centered at radius r, from z0 to z0+h
    return arc(r,z0+h/2,h/2,-math.pi/2,math.pi/2,n)
def cove(r0,z0,r1,z1,n=16):  # concave sweep from (r0,z0) to (r1,z1)
    pts=[]
    for i in range(n+1):
        t=i/n; e=1-math.cos(t*math.pi/2); f=math.sin(t*math.pi/2)
        pts.append((r0+(r1-r0)*f, z0+(z1-z0)*e))
    return pts
def ogee(r0,z0,r1,z1,n=20):  # S curve
    return [(r0+(r1-r0)*(0.5-0.5*math.cos(math.pi*i/n)), z0+(z1-z0)*i/n) for i in range(n+1)]
def line(r0,z0,r1,z1,n=8): return [(r0+(r1-r0)*i/n, z0+(z1-z0)*i/n) for i in range(n+1)]
def dedupe(p):
    out=[p[0]]
    for q in p[1:]:
        if abs(q[0]-out[-1][0])+abs(q[1]-out[-1][1])>1e-5: out.append(q)
    return out
def lathe(name, prof, seg=256, mod=None, mat=None):
    """mod(r,z,theta)->r'  for flutes and crowns"""
    prof=dedupe(prof)
    z_lo=prof[0][1]; z_hi=prof[-1][1]
    if prof[0][0]<1e-4: prof=prof[1:]
    if prof[-1][0]<1e-4: prof=prof[:-1]
    verts=[]; faces=[]
    n=len(prof)
    for j in range(seg):
        th=TAU*j/seg
        for (r,z) in prof:
            rr=mod(r,z,th) if mod else r
            verts.append((rr*math.cos(th), rr*math.sin(th), z))
    for j in range(seg):
        a=j*n; b=((j+1)%seg)*n
        for i in range(n-1):
            faces.append((a+i,b+i,b+i+1,a+i+1))
    # caps
    verts.append((0,0,z_lo)); c0=len(verts)-1
    verts.append((0,0,z_hi)); c1=len(verts)-1
    for j in range(seg):
        a=j*n; b=((j+1)%seg)*n
        faces.append((b,a,c0)); faces.append((a+n-1,b+n-1,c1))
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.remove_doubles(bm,verts=bm.verts,dist=1e-6); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
    me.shade_smooth() if hasattr(me,'shade_smooth') else [setattr(p,'use_smooth',True) for p in me.polygons]
    ob=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(ob)
    if mat: me.materials.append(mat)
    return ob
def ring_lathe(name, prof, mat, seg=256):
    """A closed profile turned into a ring (no caps)."""
    verts=[]; faces=[]; n=len(prof)
    for j in range(seg):
        th=TAU*j/seg
        for (r,z) in prof: verts.append((r*math.cos(th),r*math.sin(th),z))
    for j in range(seg):
        a=j*n; b=((j+1)%seg)*n
        for i in range(n):
            i2=(i+1)%n; faces.append((a+i,b+i,b+i2,a+i2))
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.remove_doubles(bm,verts=bm.verts,dist=1e-6)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth=True
    ob=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(ob); me.materials.append(mat)
    return ob
def torus(name,R,r,z,mat):
    bpy.ops.mesh.primitive_torus_add(major_radius=R,minor_radius=r,major_segments=192,minor_segments=24,location=(0,0,z))
    o=bpy.context.active_object; o.name=name; bpy.ops.object.shade_smooth(); o.data.materials.append(mat); return o
def uvsphere(name,r,loc,mat,scale=(1,1,1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=64,ring_count=32); o=bpy.context.active_object; o.name=name; o.scale=scale
    bpy.ops.object.shade_smooth(); o.data.materials.append(mat); return o
def rbox(name,size,loc,mat,bevel=0.01,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc,rotation=rot); o=bpy.context.active_object; o.name=name; o.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    m=o.modifiers.new('bev','BEVEL'); m.width=bevel; m.segments=5; m.limit_method='NONE'
    o.data.materials.append(mat); bpy.ops.object.shade_smooth(); return o
def prism(name,pts,r0,r1,angle,mat=None):
    """A cutter: the polygon pts (tangential offset, z), extruded radially from r0 to r1 at `angle`."""
    verts=[]
    for r in (r0,r1):
        for (t,z) in pts:
            verts.append((r*math.cos(angle)-t*math.sin(angle), r*math.sin(angle)+t*math.cos(angle), z))
    n=len(pts)
    faces=[tuple(range(n))[::-1], tuple(range(n,2*n))]+[(i,(i+1)%n,n+(i+1)%n,n+i) for i in range(n)]
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
    ob=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(ob)
    if mat: me.materials.append(mat)
    return ob
def crenel(name,angle,width,z0,z1,r=0.4):
    """A cutter for a crenel: a wedge from the axis out past the wall, `width` radians wide."""
    verts=[(0,0,z0),(0,0,z1)]
    for da in (-width/2,width/2):
        verts+=[(r*math.cos(angle+da),r*math.sin(angle+da),z0),(r*math.cos(angle+da),r*math.sin(angle+da),z1)]
    faces=[(0,2,4),(1,5,3),(0,1,3,2),(4,5,1,0),(2,3,5,4)]
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
    ob=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(ob)
    return ob
def cut(target, cutter):
    m=target.modifiers.new('cut','BOOLEAN'); m.operation='DIFFERENCE'; m.object=cutter; m.solver=SOLVER
    dg=bpy.context.evaluated_depsgraph_get(); dg.update()
    e=target.evaluated_get(dg); nm=bpy.data.meshes.new_from_object(e); target.modifiers.clear()
    old=target.data; target.data=nm
    for p in nm.polygons: p.use_smooth=True
    bpy.data.objects.remove(cutter)
# ---------- shared base ----------
TOP=0.125   # the top of every base: the body starts here
def base_profile(R):
    """A low plinth: a rounded foot, one bold bead, a short cove; ends at (R - 0.085, 0.114)."""
    p=[(0,0),(R-0.01,0)]
    p+=arc(R-0.01,0.01,0.01,-math.pi/2,0,6)
    p+=line(R,0.01,R,0.02,2)
    p+=bead(R-0.006,0.02,0.032)                 # the bold bead
    p+=line(R-0.02,0.052,R-0.03,0.056,2)        # fillet step
    p+=cove(R-0.03,0.056,R-0.085,0.1,12)        # a short cove up toward the body
    p+=bead(R-0.085,0.1,0.014,8)                # fine bead
    return p
def body_start(R): return line(R-0.09,0.114,R-0.095,TOP,2)
def flutes(z0,z1,n,depth,twist=0.0):
    """n vertical flutes between z0 and z1; twist = fraction of a turn the flutes rotate over the span"""
    def m(r,z,th):
        if z<z0 or z>z1: return r
        t=(z-z0)/(z1-z0); w=math.sin(math.pi*t)**0.6
        return r-depth*w*(0.5+0.5*math.cos(n*(th+twist*TAU*t)))**2
    return m
def group(name, objs):
    e=bpy.data.objects.new(name,None); bpy.context.scene.collection.objects.link(e)
    for o in objs: o.parent=e
    return e
def shade(M): return M.get('shade',M['body'])
def merlon_caps(name,ri,ro,z,mat,count=5,notch=math.radians(31),t=0.012,e=0.004):
    """Metal caps on a rook's merlons: a flat ring over the parapet's top, a hair proud of its walls,
    cut by the same crenels, so each merlon's top catches the light."""
    r0=ri-0.002; r1=ro+0.002; zb=z-0.004
    prof=[(r0,zb),(r1,zb)]+arc(r1-e,z+t-e,e,0,math.pi/2,4)+arc(r0+e,z+t-e,e,math.pi/2,math.pi,4)
    caps=ring_lathe(name,prof,mat,seg=192)
    for i in range(count):
        cut(caps,crenel(f'{name}c{i}',-math.pi/2+TAU*i/count,notch,z-0.05,z+0.1))
    return caps
# ---------- pieces ----------
# Heights (squares, before the game's 1.1 scale): K 1.336 > Q 1.08 > B 1.0 > N 0.83 > R 0.742 > P 0.56.
# Every piece is told by its top, made big enough to read on a phone, over a low base:
#   king a thick cross, queen a coronet of eight ball-tipped spikes round a central ball,
#   bishop a tall pointed mitre with a diagonal cut showing its metal core, rook a tower with
#   five square merlons capped in metal round a dark well, knight a horse's head, pawn one ball on a collar.
# The surfaces differ too: king straight flutes, queen spiral flutes, bishop fine flutes,
# rook masonry, pawn short flutes.
def king(M):
    R=0.31; p=base_profile(R); p+=body_start(R)
    p+=ogee(R-0.095,TOP,0.135,0.56,32)        # tall body
    p+=line(0.135,0.56,0.16,0.572,2); p+=bead(0.177,0.572,0.03)
    p+=line(0.17,0.602,0.208,0.61,2); p+=bead(0.213,0.61,0.036)     # main collar (ring sits here)
    p+=line(0.198,0.646,0.12,0.66,2)
    p+=cove(0.12,0.66,0.205,0.8)                # crown cup
    p+=bead(0.207,0.8,0.024,10)
    p+=line(0.195,0.824,0.183,0.828,1)
    p+=[(0.183*math.cos(t),0.828+0.085*math.sin(t)) for t in np.linspace(0,math.pi/2*0.86,16)]   # orb dome
    top=p[-1]; p+=line(top[0],top[1],0.0,top[1],3)
    body=lathe('K',p,mod=flutes(0.19,0.54,28,0.012),mat=M['body'])
    ring=torus('Kring',0.224,0.0095,0.628,M['metal'])
    zt=top[1]-0.008
    objs=[body,ring]
    objs.append(lathe('Kcush',[(0.0,zt-0.005),(0.065,zt-0.005),(0.076,zt+0.012),(0.056,zt+0.03),(0.0,zt+0.03)],seg=128,mat=M['metal']))
    # the cross is what says "king": thick bars, arms three times the bar's width
    H=1.336; bar=0.12; span=0.36
    z0=zt+0.02; zc=H-0.115-bar/2
    objs.append(rbox('Kcv',(bar,bar,H-z0),(0,0,(H+z0)/2),M['metal'],0.024))
    objs.append(rbox('Kch',(span,bar,bar),(0,0,zc),M['metal'],0.024))
    for y in (-bar/2,bar/2):
        objs.append(uvsphere('Kgem',0.034,(0,y,zc),M['gem'],(1,0.45,1)))
    return group('king',objs)
def queen(M):
    R=0.30; p=base_profile(R); p+=body_start(R)
    p+=ogee(R-0.095,TOP,0.12,0.5,32)
    p+=line(0.12,0.5,0.145,0.512,2); p+=bead(0.162,0.512,0.028)
    p+=line(0.157,0.54,0.195,0.548,2); p+=bead(0.2,0.548,0.033)     # ring sits here
    p+=line(0.185,0.581,0.105,0.596,2)
    p+=cove(0.105,0.596,0.19,0.75)               # crown cup
    # the coronet flares wide: eight tall spikes, each with a ball on its tip
    ZR=0.96; RO=0.268; RI=0.236
    p+=line(0.19,0.75,RO,ZR,8)
    p+=line(RO,ZR,RI,ZR,2)
    p+=line(RI,ZR,0.172,0.82,4)                 # inner wall
    p+=[(0.172*math.cos(t),0.82+0.05*math.sin(t)) for t in np.linspace(0,math.pi/2*0.8,10)]
    top=p[-1]; p+=line(top[0],top[1],0.0,top[1],3)
    body=lathe('Q',p,mod=flutes(0.19,0.48,22,0.012,twist=0.16),mat=M['body'])
    objs=[body]
    NPT=8; apex=0.845; hw=0.088*(ZR+0.06-apex)/(ZR-apex)
    for i in range(NPT):
        a=TAU*(i+0.5)/NPT
        cut(body,prism(f'Qn{i}',[(-hw,ZR+0.06),(hw,ZR+0.06),(0,apex)],0.12,0.36,a))
    for i in range(NPT):
        a=TAU*i/NPT; objs.append(uvsphere(f'Qp{i}',0.036,(math.cos(a)*0.252,math.sin(a)*0.252,ZR+0.026),M['pearl']))
    objs.append(torus('Qring',0.21,0.0085,0.5645,M['metal']))
    zt=top[1]; zb=1.08-0.058
    objs.append(lathe('Qstem',[(0.0,zt-0.01),(0.04,zt-0.01),(0.022,zb-0.02),(0.0,zb-0.02)],seg=96,mat=M['metal']))
    objs.append(uvsphere('Qball',0.058,(0,0,zb),M['metal']))
    return group('queen',objs)
def mitre_profile(z0=0.51,z1=0.935,rmax=0.178,n=48):
    """The bishop's mitre: an almond that comes to a point, never a ball like the pawn's head."""
    out=[]
    for i in range(n+1):
        t=i/n; z=z0+(z1-z0)*t
        r=rmax*math.sin(math.pi*(0.18+0.82*t))**0.6*(1-t)**0.38
        out.append((max(r,0.0),z))
    out[-1]=(0.0,z1)
    return out
# the side of the bishop that faces the player: the game and the pictures turn it -112 degrees
BISHOP_FRONT=math.radians(22)
def mitre_cut(body, front=BISHOP_FRONT, width=0.075, z=0.745, slope=48):
    """A slot through the mitre, slanting down from the upper left as the player sees it."""
    f=Vector((math.cos(front),math.sin(front),0)); s=Vector((-math.sin(front),math.cos(front),0))
    t=(math.cos(math.radians(slope))*Vector((0,0,1))-math.sin(math.radians(slope))*s).normalized()
    n=f.cross(t).normalized()
    c=Vector((0,0,z))+s*0.02
    bpy.ops.mesh.primitive_cube_add(size=1); o=bpy.context.active_object; o.name='Bslot'
    o.matrix_world=Matrix.Translation(c)@Matrix((n,f,t)).transposed().to_4x4()@Matrix.Diagonal((width,0.6,0.34,1))
    cut(body,o)
def bishop(M):
    R=0.285; p=base_profile(R); p+=body_start(R)
    p+=ogee(R-0.095,TOP,0.1,0.42,28)
    p+=line(0.1,0.42,0.13,0.432,2); p+=bead(0.148,0.432,0.026)
    p+=line(0.138,0.458,0.165,0.465,2); p+=bead(0.168,0.465,0.03)   # ring sits here
    p+=line(0.15,0.495,0.08,0.51,2)
    mit=mitre_profile(); p+=mit
    body=lathe('B',p,mod=flutes(0.19,0.4,32,0.008),mat=M['body'])
    mitre_cut(body)
    # a metal core inside the mitre: through the cut it shows as a bright diagonal line
    core=lathe('Bmitre',[(0.0,0.52)]+[(max(r-0.012,0.0),z) for r,z in mit[1:-1]]+[(0.0,mit[-1][1]-0.02)],seg=128,mat=M['metal'])
    ring=torus('Bring',0.178,0.008,0.48,M['metal'])
    neck=lathe('Bstem',[(0.0,0.925),(0.028,0.925),(0.015,0.95),(0.0,0.95)],seg=96,mat=M['metal'])
    fin=uvsphere('Bfin',0.037,(0,0,1.0-0.037),M['metal'])
    return group('bishop',[body,core,ring,neck,fin])
def rook(M):
    R=0.295; p=base_profile(R); p+=body_start(R)
    # a tower: straight walls, a corbelled ledge, then a wide parapet
    ZT=0.73; RO=0.252; RI=0.158; FLOOR=0.585; NOTCH=0.612
    p+=line(R-0.095,TOP,0.198,0.49,10)
    p+=line(0.198,0.49,0.206,0.494,1)
    p+=cove(0.206,0.494,RO,0.548,10)
    p+=line(RO,0.548,RO,ZT,6)
    p+=line(RO,ZT,RI,ZT,3); p+=line(RI,ZT,RI,FLOOR,4); p+=line(RI,FLOOR,0.0,FLOOR,3)
    def m(r,z,th):  # masonry courses engraved around the tower
        if 0.2<z<0.46:
            for zz in (0.24,0.32,0.4):
                if abs(z-zz)<0.0045: return r-0.006
        return r
    body=lathe('R',p,mod=m,seg=384,mat=M['body'])
    # five square merlons, one at the back, so the player looks through a crenel into the well;
    # the crenels' sides run to the center, so each merlon is a full block of the wall
    for i in range(5):
        a=-math.pi/2+TAU*i/5
        cut(body,crenel(f'Rc{i}',a,math.radians(31),NOTCH,ZT+0.1))
    ring=torus('Rring',0.2,0.0085,0.492,M['metal'])
    # the floor of the well, darker, so the top reads as a castle and never as a ball
    well=lathe('Rwell',[(0.0,FLOOR-0.002),(RI-0.001,FLOOR-0.002),(RI-0.001,FLOOR+0.004),(0.0,FLOOR+0.004)],seg=192,mat=shade(M))
    # metal caps on the merlons: the battlements catch the light on the light and the dark squares
    caps=merlon_caps('Rcap',RI,RO,ZT,M['metal'])
    return group('rook',[body,ring,caps,well])
def pawn(M):
    R=0.26; p=base_profile(R); p+=body_start(R)
    # short and plain under a big round head: the smallest piece, and the only round top
    p+=ogee(R-0.095,TOP,0.085,0.27,20)
    p+=line(0.085,0.27,0.115,0.28,2); p+=bead(0.125,0.28,0.026)        # ring sits here
    p+=line(0.115,0.306,0.06,0.316,2)
    rad=0.13; a0=math.asin(0.06/rad); cz=0.316+rad*math.cos(a0)
    p+=[(rad*math.sin(a),cz-rad*math.cos(a)) for a in np.linspace(a0,math.pi,40)]
    body=lathe('P',p,mod=flutes(0.15,0.26,16,0.008),mat=M['body'])
    ring=torus('Pring',0.133,0.0075,0.293,M['metal'])
    return group('pawn',[body,ring])
KNIGHT_SCALE=0.9
def knight(M, verts, faces):
    R=0.29; p=base_profile(R); p+=body_start(R); p+=line(R-0.095,TOP,0.0,TOP,3)
    b=lathe('Nb',p,mat=M['body'])
    v=verts.copy(); s=KNIGHT_SCALE; v[:,0]*=s; v[:,1]*=s; v[:,2]=TOP+(v[:,2]-0.17)*s
    # marching cubes winds the sculpt's faces outward as they come (SceneKit culls the other side)
    me=bpy.data.meshes.new('Nh'); me.from_pydata(v.tolist(),[],faces.tolist()); me.update()
    for f in me.polygons: f.use_smooth=True
    h=bpy.data.objects.new('Nh',me); bpy.context.scene.collection.objects.link(h); me.materials.append(M['body'])
    ring=torus('Nring',0.17,0.008,TOP+0.002,M['metal'])
    return group('knight',[b,h,ring])
