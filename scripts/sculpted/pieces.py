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
def cut(target, cutter):
    m=target.modifiers.new('cut','BOOLEAN'); m.operation='DIFFERENCE'; m.object=cutter; m.solver=SOLVER
    dg=bpy.context.evaluated_depsgraph_get(); dg.update()
    e=target.evaluated_get(dg); nm=bpy.data.meshes.new_from_object(e); target.modifiers.clear()
    old=target.data; target.data=nm
    for p in nm.polygons: p.use_smooth=True
    bpy.data.objects.remove(cutter)
# ---------- shared base ----------
def base_profile(R):
    p=[(0,0),(R-0.012,0)]
    p+=arc(R-0.012,0.012,0.012,-math.pi/2,0,6)
    p+=line(R,0.012,R,0.03,3)
    p+=bead(R-0.004,0.03,0.04)                 # big bead
    p+=line(R-0.02,0.07,R-0.035,0.075,2)       # fillet step
    p+=cove(R-0.035,0.075,R-0.115,0.135)       # cove up into the body
    p+=bead(R-0.112,0.135,0.018,10)            # fine bead
    return p
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
# ---------- pieces ----------
# Heights: K 1.33 > Q 1.08 > B 1.03 > N 0.80 > R 0.70 > P 0.56 (square = 1), steeper than tournament
# ratios so the sizes tell the pieces apart at phone size, and each top has its own shape:
# king a big cross, queen a spiky coronet, bishop a pointed mitre, rook battlements, pawn a ball.
# Each piece also has its own surface so it reads at a glance:
#   king straight flutes, queen spiral flutes, bishop fine flutes, rook masonry, pawn short flutes.
def body_start(R): return line(R-0.12,0.153,R-0.125,0.17,2)
def king(M):
    R=0.33; p=base_profile(R); p+=body_start(R)
    p+=ogee(R-0.125,0.17,0.13,0.6,32)          # tall body
    p+=line(0.13,0.6,0.155,0.612,2); p+=bead(0.172,0.612,0.03)
    p+=line(0.165,0.642,0.205,0.65,2); p+=bead(0.21,0.65,0.036)     # main collar (ring sits here)
    p+=line(0.195,0.686,0.12,0.7,2)
    p+=cove(0.12,0.7,0.2,0.84)                  # crown cup
    p+=bead(0.202,0.84,0.024,10)
    p+=line(0.19,0.864,0.178,0.868,1)
    p+=[(0.178*math.cos(t),0.868+0.09*math.sin(t)) for t in np.linspace(0,math.pi/2*0.86,16)]   # orb dome
    top=p[-1]; p+=line(top[0],top[1],0.0,top[1],3)
    body=lathe('K',p,mod=flutes(0.2,0.58,28,0.012),mat=M['body'])
    ring=torus('Kring',0.219,0.0095,0.668,M['metal'])
    zt=top[1]-0.01
    # bold, clean cross on a small turned cushion
    objs=[body,ring]
    objs.append(lathe('Kcush',[(0.0,zt-0.005),(0.06,zt-0.005),(0.07,zt+0.012),(0.05,zt+0.03),(0.0,zt+0.03)],seg=128,mat=M['metal']))
    # the cross is what says "king" at a glance, so it is big: half again the old one
    objs.append(rbox('Kcv',(0.1,0.1,0.38),(0,0,zt+0.2),M['metal'],0.022))
    objs.append(rbox('Kch',(0.3,0.1,0.1),(0,0,zt+0.25),M['metal'],0.022))
    for y in (-0.05,0.05):
        objs.append(uvsphere('Kgem',0.03,(0,y,zt+0.25),M['gem'],(1,0.45,1)))
    return group('king',objs)
def queen(M):
    R=0.32; p=base_profile(R); p+=body_start(R)
    p+=ogee(R-0.125,0.17,0.118,0.54,32)
    p+=line(0.118,0.54,0.142,0.552,2); p+=bead(0.16,0.552,0.028)
    p+=line(0.155,0.58,0.192,0.588,2); p+=bead(0.197,0.588,0.033)   # ring sits here
    p+=line(0.182,0.621,0.105,0.636,2)
    p+=cove(0.105,0.636,0.19,0.8)                # crown cup
    # the coronet flares wide and tall, so the queen's top reads as a spiky crown at a glance
    p+=line(0.19,0.8,0.25,0.975,6)
    p+=line(0.25,0.975,0.218,0.975,2)
    p+=line(0.218,0.975,0.17,0.85,3)            # inner wall
    p+=[(0.17*math.cos(t),0.85+0.05*math.sin(t)) for t in np.linspace(0,math.pi/2*0.8,10)]
    top=p[-1]; p+=line(top[0],top[1],0.0,top[1],3)
    body=lathe('Q',p,mod=flutes(0.2,0.52,22,0.012,twist=0.16),mat=M['body'])
    objs=[body]
    NPT=8
    for i in range(NPT):
        a=TAU*(i+0.5)/NPT
        c=rbox(f'Qn{i}',(0.2,0.13,0.13),(math.cos(a)*0.235,math.sin(a)*0.235,1.0),M['body'],0.003)
        c.rotation_mode='XYZ'; c.rotation_euler=(math.radians(45),0,a)
        cut(body,c)
    for i in range(NPT):
        a=TAU*i/NPT; objs.append(uvsphere(f'Qp{i}',0.028,(math.cos(a)*0.236,math.sin(a)*0.236,0.985),M['pearl']))
    objs.append(torus('Qring',0.207,0.0085,0.6045,M['metal']))
    zt=top[1]
    objs.append(lathe('Qstem',[(0.0,zt-0.01),(0.036,zt-0.01),(0.02,zt+0.08),(0.0,zt+0.08)],seg=96,mat=M['metal']))
    objs.append(uvsphere('Qball',0.052,(0,0,zt+0.125),M['metal']))
    return group('queen',objs)
def mitre_profile(z0=0.53,z1=0.95,rmax=0.165,n=48):
    """The bishop's mitre: an almond that comes to a point, never a ball like the pawn's head."""
    out=[]
    for i in range(n+1):
        t=i/n; z=z0+(z1-z0)*t
        r=rmax*math.sin(math.pi*(0.18+0.82*t))**0.6*(1-t)**0.38
        out.append((max(r,0.0),z))
    out[-1]=(0.0,z1)
    return out
def bishop(M):
    R=0.3; p=base_profile(R); p+=body_start(R)
    p+=ogee(R-0.125,0.17,0.098,0.44,28)
    p+=line(0.098,0.44,0.128,0.452,2); p+=bead(0.146,0.452,0.026)
    p+=line(0.136,0.478,0.162,0.485,2); p+=bead(0.165,0.485,0.03)   # ring sits here
    p+=line(0.148,0.515,0.08,0.53,2)
    p+=mitre_profile()
    body=lathe('B',p,mod=flutes(0.2,0.42,32,0.008),mat=M['body'])
    # a wide, deep cleft, turned toward the player so it shows from the game camera
    slot=rbox('Bslot',(0.06,0.4,0.32),(0.07,0,0.8),M['body'],0.006); slot.rotation_euler=(0,math.radians(-40),0)
    cut(body,slot)
    ring=torus('Bring',0.175,0.008,0.5,M['metal'])
    neck=lathe('Bstem',[(0.0,0.935),(0.026,0.935),(0.014,0.962),(0.0,0.962)],seg=96,mat=M['metal'])
    fin=uvsphere('Bfin',0.036,(0,0,0.99),M['metal'])
    return group('bishop',[body,ring,neck,fin])
def rook(M):
    R=0.3; p=base_profile(R); p+=body_start(R)
    p+=line(R-0.125,0.17,0.16,0.45,10)
    p+=line(0.16,0.45,0.17,0.46,1); p+=bead(0.18,0.46,0.026)
    p+=line(0.17,0.486,0.205,0.497,2); p+=bead(0.21,0.497,0.03)     # ring sits here
    p+=line(0.195,0.527,0.19,0.534,1)
    p+=cove(0.19,0.534,0.228,0.6,10)
    p+=line(0.228,0.6,0.228,0.7,4)
    p+=line(0.228,0.7,0.158,0.7,2); p+=line(0.158,0.7,0.158,0.645,2); p+=line(0.158,0.645,0.0,0.645,2)
    def m(r,z,th):  # masonry courses engraved around the tower
        if 0.22<z<0.44:
            for zz in (0.27,0.34,0.41):
                if abs(z-zz)<0.0045: return r-0.006
        return r
    body=lathe('R',p,mod=m,seg=384,mat=M['body'])
    for i in range(6):
        a=TAU*i/6
        c=rbox(f'Rc{i}',(0.13,0.055,0.1),(math.cos(a)*0.2,math.sin(a)*0.2,0.69),M['body'],0.004); c.rotation_euler=(0,0,a)
        cut(body,c)
    ring=torus('Rring',0.219,0.0085,0.512,M['metal'])
    return group('rook',[body,ring])
def pawn(M):
    R=0.27; p=base_profile(R); p+=body_start(R)
    # short and plain under a big round head: the smallest piece, and the only round top
    p+=ogee(R-0.125,0.17,0.085,0.29,20)
    p+=line(0.085,0.29,0.115,0.3,2); p+=bead(0.125,0.3,0.026)        # ring sits here
    p+=line(0.115,0.326,0.058,0.336,2)
    rad=0.128; a0=math.asin(0.058/rad); cz=0.336+rad*math.cos(a0)
    p+=[(rad*math.sin(a),cz-rad*math.cos(a)) for a in np.linspace(a0,math.pi,40)]
    body=lathe('P',p,mod=flutes(0.19,0.28,16,0.008),mat=M['body'])
    ring=torus('Pring',0.134,0.0075,0.313,M['metal'])
    return group('pawn',[body,ring])
def knight(M, verts, faces):
    R=0.3; p=base_profile(R); p+=body_start(R); p+=line(R-0.125,0.17,0.0,0.17,3)
    b=lathe('Nb',p,mat=M['body'])
    v=verts.copy(); s=0.84; v[:,0]*=s; v[:,1]*=s; v[:,2]=0.17+(v[:,2]-0.17)*s
    # marching cubes winds the sculpt's faces outward as they come (SceneKit culls the other side)
    me=bpy.data.meshes.new('Nh'); me.from_pydata(v.tolist(),[],faces.tolist()); me.update()
    for f in me.polygons: f.use_smooth=True
    h=bpy.data.objects.new('Nh',me); bpy.context.scene.collection.objects.link(h); me.materials.append(M['body'])
    ring=torus('Nring',0.185,0.008,0.172,M['metal'])
    return group('knight',[b,h,ring])
