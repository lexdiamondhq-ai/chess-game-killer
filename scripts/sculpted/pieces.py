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

# ---------- fine detail: beading, gadroons, arrow slits ----------
def beads(name,r,z,n,size,mat,sub=1,phase=0.0):
    """A ring of n small round beads (pearl beading) centred at radius r, height z: one object."""
    bm=bmesh.new()
    for i in range(n):
        a=TAU*(i+phase)/n
        bmesh.ops.create_icosphere(bm,subdivisions=sub,radius=size,matrix=Matrix.Translation((r*math.cos(a),r*math.sin(a),z)))
    me=bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth=True
    ob=bpy.data.objects.new(name,me); bpy.context.scene.collection.objects.link(ob); me.materials.append(mat)
    return ob
def gadroons(z0,z1,n,depth,phase=0.0):
    """n rounded lobes standing out of the surface between z0 and z1 (a gadrooned cup), fading in and out."""
    def m(r,z,th):
        if z<=z0 or z>=z1: return r
        t=(z-z0)/(z1-z0); w=math.sin(math.pi*t)**0.7
        return r+depth*w*(abs(math.cos(n*(th+phase)/2))**0.8-0.7)
    return m
def compose(*mods):
    """Several surface modifiers at once: their changes add up."""
    def m(r,z,th):
        return r+sum(f(r,z,th)-r for f in mods)
    return m
def radius_at(prof,z):
    """The outermost radius of a profile at height z."""
    best=0.0
    for (r0,z0),(r1,z1) in zip(prof,prof[1:]):
        if min(z0,z1)<=z<=max(z0,z1) and z1!=z0:
            best=max(best,r0+(r1-r0)*(z-z0)/(z1-z0))
    return best
def slits(body,name,r_wall,z0,z1,width,M,angles,depth=0.026):
    """Arrow slits cut into a tower wall, each with a dark back so it reads as an opening."""
    zt=z1-width/2
    pts=[(-width/2,z0),(width/2,z0),(width/2,zt)]+[(width/2*math.cos(a),zt+width/2*math.sin(a)) for a in np.linspace(0,math.pi,10)[1:-1]]+[(-width/2,zt)]
    backs=[]
    for i,a in enumerate(angles):
        cut(body,prism(f'{name}c{i}',pts,r_wall-depth,r_wall+0.1,a))
        backs.append(prism(f'{name}{i}',pts,r_wall-depth-0.004,r_wall-depth+0.0015,a,shade(M)))
    return backs
FRONT=-math.pi/2   # the side of every piece that faces the player
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
def base_beads(name,R,M):
    """The plinth's fine bead turned into a row of carved beads, in the body's own stone."""
    r=R-0.085+0.0055; n=int(TAU*r/0.0165)
    return beads(name,r,0.107,n,0.0082,M['body'])
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
# Heights (squares, before the game's 1.1 scale): K 1.336 > B 1.0 > Q 0.92 > N 0.83 > R 0.742 > P 0.56.
# Every piece is told by its top, made big enough to read on a phone, over a low base:
#   king a long Latin cross, queen a crown of eight ball-tipped points round a ball (and far shorter),
#   bishop a tall pointed mitre with a diagonal cut showing its metal core, rook a tower with
#   five square merlons capped in metal round a dark well, knight a horse's head, pawn one ball on a collar.
# The surfaces differ too: king straight flutes, queen spiral flutes, bishop fine flutes,
# rook masonry, pawn short flutes.
def pattee(name, z0, z1, zc, span, bar, flare, depth, mat):
    """A cross standing in the plane facing the player, `depth` thick: a centre block and four arms
    widening a little toward their ends (flare = an arm's width at its end). Built from convex parts:
    a concave outline turned into one prism fills its own notches."""
    h=bar/2; f=flare/2; arm=span/2
    quads=[[(-h,zc-h),(h,zc-h),(h,zc+h),(-h,zc+h)],
           [(-h,zc+h-0.002),(h,zc+h-0.002),(f,z1),(-f,z1)],
           [(-h,z0),(h,z0),(h,zc-h+0.002),(-h,zc-h+0.002)],
           [(h-0.002,zc-h),(arm,zc-f),(arm,zc+f),(h-0.002,zc+h)],
           [(-arm,zc-f),(-h+0.002,zc-h),(-h+0.002,zc+h),(-arm,zc+f)]]
    parts=[]
    for k,q in enumerate(quads):
        o=prism(f'{name}{k}',q,-depth/2,depth/2,FRONT,mat)
        m=o.modifiers.new('bev','BEVEL'); m.width=0.008; m.segments=3; m.limit_method='ANGLE'
        parts.append(o)
    return parts
def squash_above(objs, z0, s):
    """Shortens a piece above z0 by the factor s, so the base keeps the set's height."""
    for o in objs:
        if o.type!='MESH': continue
        o.data.transform(o.matrix_basis); o.matrix_basis=Matrix.Identity(4)
        for v in o.data.vertices:
            if v.co.z>z0: v.co.z=z0+(v.co.z-z0)*s
        o.data.update()
def cross_finish(M):
    """The king's cross: the ivory king's in its own stone, the black king's in metal, so it shows
    light against the dark frame behind the far rank. The game meshes carry it as its own finish
    (`cross`, id 5), which the app draws that way."""
    if 'cross' in M: return M['cross']
    return M['body'] if M['body'].name.startswith('ivory') else M['metal']
def crown_gems(name,p,z,M,size=0.024):
    """Four stones set round a crown cup, one facing the player."""
    out=[]
    for i in range(4):
        a=FRONT+i*math.pi/2; rr=radius_at(p,z)+0.005
        g=uvsphere(f'{name}{i}',size,(rr*math.cos(a),rr*math.sin(a),z),M['gem'],(1,1,1))
        g.scale=(0.55,0.55,1.0); g.rotation_euler=(0,0,a); out.append(g)
    return out
KING_H=1.336     # the king's height, cross included: every set's frame is fitted to it
LATIN_TOP=1.46   # the Latin king as drawn, before it is brought down to KING_H
QUEEN_H=0.92     # the queen's height, her ball's top: under the bishop, over the knight, far under the king
# The queen's crown, shared by both sets: a slim neck flaring into a cup whose rim carries eight
# points tipped with balls, round a dome under a ball on a stem. From the side a spiked crown under
# a ball, from the 3D camera above a star round a bright ball: never a rook's open ring of merlons.
QRIM=0.665; QRIM_R=0.232; QDOME=0.765; QBALL_R=0.056
def queen_crown_profile(r0,z0):
    """From the neck (r0, z0): the flaring cup, the rim and the dome inside it; ends on the axis."""
    p=cove(r0,z0,QRIM_R-0.012,QRIM-0.012,14); p+=line(QRIM_R-0.012,QRIM-0.012,QRIM_R,QRIM,2)
    p+=line(QRIM_R,QRIM,QRIM_R-0.03,QRIM+0.006,2)
    rd=QRIM_R-0.03
    p+=[(rd*math.cos(t),QRIM+0.006+(QDOME-QRIM-0.006)*math.sin(t)) for t in np.linspace(0,math.pi/2,18)[1:]]
    return p
def queen_crown(name,M,point_mat,tip_mat,ball_mat,n=8):
    """The eight points round the rim, leaning out, each tipped with a ball, and the ball on top."""
    out=[]; L=0.15; lean=math.radians(20)
    for i in range(n):
        a=FRONT+math.pi/n+TAU*i/n
        foot=Vector((QRIM_R*0.9*math.cos(a),QRIM_R*0.9*math.sin(a),QRIM-0.02))
        turn=Matrix.Rotation(a,4,'Z')@Matrix.Rotation(lean,4,'Y')
        o=lathe(f'{name}pt{i}',[(0.0,0.0),(0.036,0.0),(0.03,0.035),(0.009,L),(0.0,L)],seg=48,mat=point_mat)
        o.matrix_world=Matrix.Translation(foot)@turn
        tip=foot+(turn.to_3x3()@Vector((0,0,L)))
        out+=[o,uvsphere(f'{name}tip{i}',0.03,tuple(tip),tip_mat)]
    zc=QUEEN_H-QBALL_R
    out.append(lathe(f'{name}stem',[(0.0,QDOME-0.01),(0.05,QDOME-0.01),(0.034,QDOME+0.01),(0.022,zc-QBALL_R+0.012),(0.0,zc-QBALL_R+0.012)],seg=96,mat=ball_mat))
    out.append(uvsphere(f'{name}topball',QBALL_R,(0,0,zc),ball_mat))
    return out
def king(M):
    """A tall king under a long Latin cross: the cross alone says king."""
    R=0.31; p=base_profile(R); p+=body_start(R)
    p+=ogee(R-0.095,TOP,0.125,0.62,32)
    p+=line(0.125,0.62,0.15,0.632,2); p+=bead(0.168,0.632,0.03)
    p+=line(0.16,0.662,0.2,0.67,2); p+=bead(0.205,0.67,0.036)      # main collar (ring sits here)
    p+=line(0.19,0.706,0.11,0.72,2)
    p+=cove(0.11,0.72,0.17,0.84); p+=bead(0.17,0.84,0.024,10)       # crown cup
    p+=line(0.158,0.864,0.07,0.875,2)
    p+=[(0.07*math.cos(t),0.875+0.03*math.sin(t)) for t in np.linspace(0,math.pi/2*0.9,8)]
    top=p[-1]; p+=line(top[0],top[1],0.0,top[1],3)
    body=lathe('K',p,mod=compose(flutes(0.19,0.6,28,0.012),gadroons(0.73,0.83,18,0.01)),mat=M['body'])
    objs=[body,torus('Kring',0.215,0.0095,0.688,M['metal']),base_beads('Kbeadbase',R,M),beads('Kbeadcrown',0.18,0.852,36,0.0105,M['metal'])]
    objs+=crown_gems('Kgem',p,0.79,M)
    objs+=pattee('Kcross',0.89,LATIN_TOP,1.30,0.30,0.075,0.10,0.075,cross_finish(M))
    squash_above(objs,0.2,(KING_H-0.2)/(LATIN_TOP-0.2))
    return group('king',objs)
def queen(M):
    """A queen well below the king: a slim neck under a crown of eight ball-tipped points round a ball."""
    R=0.30; p=base_profile(R); p+=body_start(R)
    p+=ogee(R-0.095,TOP,0.105,0.44,32)
    p+=line(0.105,0.44,0.13,0.452,2); p+=bead(0.148,0.452,0.026)
    p+=line(0.143,0.478,0.178,0.486,2); p+=bead(0.183,0.486,0.03)     # ring sits here
    p+=line(0.17,0.516,0.095,0.53,2)
    p+=queen_crown_profile(0.095,0.53)
    body=lathe('Q',p,mod=compose(flutes(0.19,0.42,22,0.012,twist=0.16),gadroons(0.55,0.66,16,0.01)),mat=M['body'])
    objs=[body,base_beads('Qbeadbase',R,M),beads('Qbeadcollar',0.1575,0.465,34,0.0098,M['pearl']),torus('Qring',0.192,0.0085,0.501,M['metal'])]
    objs+=queen_crown('Q',M,M['metal'],M['pearl'],M['pearl'])   # metal points: the only metal crown on the board
    return group('queen',objs)
def mitre_profile(z0=0.51,z1=0.935,rmax=0.19,n=48):
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
def mitre_cut(body, front=BISHOP_FRONT, width=0.105, z=0.745, slope=48):
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
    pearls=beads('Bbeadcollar',0.1565,0.445,30,0.0098,M['metal'])
    neck=lathe('Bstem',[(0.0,0.925),(0.028,0.925),(0.015,0.95),(0.0,0.95)],seg=96,mat=M['metal'])
    fin=uvsphere('Bfin',0.037,(0,0,1.0-0.037),M['metal'])
    return group('bishop',[body,core,ring,neck,fin,pearls,base_beads('Bbeadbase',R,M)])
def rook(M):
    R=0.295; p=base_profile(R); p+=body_start(R)
    # a tower: straight walls, a corbelled ledge, then a wide parapet
    ZT=0.73; RO=0.252; RI=0.158; FLOOR=0.585; NOTCH=0.612
    p+=line(R-0.095,TOP,0.198,0.49,10)
    p+=line(0.198,0.49,0.206,0.494,1)
    p+=cove(0.206,0.494,RO,0.548,10)
    p+=line(RO,0.548,RO,ZT,6)
    p+=line(RO,ZT,RI,ZT,3); p+=line(RI,ZT,RI,FLOOR,4); p+=line(RI,FLOOR,0.0,FLOOR,3)
    COURSES=(0.16,0.235,0.31,0.385,0.46)
    def m(r,z,th):  # ashlar masonry: courses of stone with staggered joints, engraved round the tower
        if not 0.15<z<0.47: return r
        D=0.0045; W=0.0042
        groove=max(max(0.0,1-((z-zz)/W)**2) for zz in COURSES)
        k=sum(1 for zz in COURSES if z>zz)
        if 0<k<len(COURSES):
            n=12; a=(th-FRONT)*n/TAU+(0.5 if k%2 else 0.0)+0.25
            d=abs(a-round(a))*TAU/n*r
            groove=max(groove,max(0.0,1-(d/W)**2))
        return r-D*groove
    body=lathe('R',p,mod=m,seg=720,mat=M['body'])
    # five square merlons, one at the back, so the player looks through a crenel into the well;
    # the crenels' sides run to the center, so each merlon is a full block of the wall
    for i in range(5):
        a=-math.pi/2+TAU*i/5
        cut(body,crenel(f'Rc{i}',a,math.radians(31),NOTCH,ZT+0.1))
    ring=torus('Rring',0.2,0.0085,0.492,M['metal'])
    # arrow slits on four sides, so one always faces the player
    backs=slits(body,'Rslit',0.198,0.25,0.37,0.036,M,[FRONT+i*math.pi/2 for i in range(4)])
    # the floor of the well, darker, so the top reads as a castle and never as a ball
    well=lathe('Rwell',[(0.0,FLOOR-0.002),(RI-0.001,FLOOR-0.002),(RI-0.001,FLOOR+0.004),(0.0,FLOOR+0.004)],seg=192,mat=shade(M))
    # metal caps on the merlons: the battlements catch the light on the light and the dark squares
    caps=merlon_caps('Rcap',RI,RO,ZT,M['metal'])
    return group('rook',[body,ring,caps,well,base_beads('Rbeadbase',R,M)]+backs)
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
    return group('pawn',[body,ring,base_beads('Pbeadbase',R,M)])
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
    objs=[b,h,ring,base_beads('Nbeadbase',R,M)]
    # a mane of metal studs down the crest of the neck and an eye set in each socket, so the
    # head reads as a horse at a glance, as the gilded knight's gold mane does
    crest=[(0.45,0.212),(0.53,0.199),(0.61,0.184),(0.69,0.159),(0.77,0.113),(0.81,0.077),(0.85,0.061)]
    zs=np.linspace(0.47,0.84,12)
    for i,z in enumerate(zs):
        x=float(np.interp(z,[c[0] for c in crest],[c[1] for c in crest]))
        hw=float(np.interp(z,[0.45,0.65,0.77,0.85],[0.11,0.104,0.097,0.073]))
        # a row of studs down each side of the crest, where the gilded knight has its gold mane
        for side in (-1,1):
            objs.append(uvsphere(f'Nmane{i}{side+1}',0.02,((x-0.03)*s,side*(hw-0.012)*s,TOP+(z-0.17)*s),M['metal'],(1,0.6,1.15)))
    for side in (-1,1):
        objs.append(uvsphere(f'Ngem{side+1}',0.021,(-0.111*s,side*(0.069*s-0.007),TOP+(0.737-0.17)*s),M['gem'],(1,0.45,1)))
    return group('knight',objs)
