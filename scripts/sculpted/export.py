# Exports the sculpted set as game-ready meshes for SceneKit.
# Each piece type: up to four parts (body, metal, gem, pearl), decimated, with corner normals
# split at sharp edges, converted to SceneKit axes (y up, ranks run toward -z), scaled to squares.
import bpy, sys, numpy as np, math, struct, zlib, json
sys.path.insert(0,'scripts/sculpted'); import pieces as P
bpy.ops.wm.read_factory_settings(use_empty=True)
MATS=('body','metal','gem','pearl')
M={k:bpy.data.materials.new(k) for k in MATS}
kv=np.load('scripts/sculpted/kv.npy'); kf=np.load('scripts/sculpted/kf.npy')
B={'K':P.king,'Q':P.queen,'B':P.bishop,'R':P.rook,'P':P.pawn,'N':lambda m:P.knight(m,kv,kf)}
# triangle budgets per object name prefix (body parts get the most)
BUDGET={'K':20000,'Q':20000,'B':16000,'R':16000,'P':10000,'Nh':30000,'Nb':5000}
SMALL={'ring':2400,'gem':700,'p':500,'ball':700,'fin':700}
SCALE=1.1
SHARP=math.radians(float(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else 60)
def budget(name):
    if name in BUDGET: return BUDGET[name]
    low=name.lower()
    if 'ring' in low: return SMALL['ring']
    if 'gem' in low: return SMALL['gem']
    if name.startswith('Qp'): return SMALL['p']
    if 'ball' in low or 'fin' in low: return SMALL['ball']
    return None
out={}
stats={}
dg=bpy.context.evaluated_depsgraph_get()
for t,f in B.items():
    g=f(M); dg.update()
    parts={k:[] for k in MATS}
    for c in g.children:
        e=c.evaluated_get(dg); m0=e.to_mesh(); m0.calc_loop_triangles(); n0=len(m0.loop_triangles); e.to_mesh_clear()
        tgt=budget(c.name)
        if tgt and n0>tgt:
            d=c.modifiers.new('dec','DECIMATE'); d.decimate_type='COLLAPSE'; d.ratio=tgt/n0; d.use_collapse_triangulate=True
            dg.update()
        e=c.evaluated_get(dg)
        me=bpy.data.meshes.new_from_object(e, preserve_all_data_layers=False, depsgraph=dg)
        me.transform(c.matrix_world)
        for p in me.polygons: p.use_smooth=True
        me.set_sharp_from_angle(angle=SHARP)
        me.calc_loop_triangles()
        nt=len(me.loop_triangles)
        tl=np.empty(nt*3,np.int32); me.loop_triangles.foreach_get('loops',tl)
        lv=np.empty(len(me.loops),np.int32); me.loops.foreach_get('vertex_index',lv)
        co=np.empty(len(me.vertices)*3,np.float32); me.vertices.foreach_get('co',co); co=co.reshape(-1,3)
        cn=np.empty(len(me.loops)*3,np.float32); me.corner_normals.foreach_get('vector',cn); cn=cn.reshape(-1,3)
        vi=lv[tl]; nn=cn[tl]
        key=np.concatenate([vi[:,None].astype(np.int64), np.round(nn*2000).astype(np.int64)],axis=1)
        uk,first,inv=np.unique(key,axis=0,return_index=True,return_inverse=True)
        pos=co[vi[first]]; nor=nn[first]; nor/=np.linalg.norm(nor,axis=1,keepdims=True)+1e-12
        idx=inv.reshape(-1).astype(np.uint32)
        mat=c.data.materials[0].name if c.data.materials else 'body'
        parts[mat].append((pos,nor,idx))
        stats.setdefault(t,[]).append((c.name,mat,n0,nt,len(pos)))
        bpy.data.meshes.remove(me)
    # merge per material
    merged={}
    for k,lst in parts.items():
        if not lst: continue
        P_=[];N_=[];I_=[];off=0
        for pos,nor,idx in lst: P_.append(pos);N_.append(nor);I_.append(idx+off);off+=len(pos)
        pos=np.concatenate(P_);nor=np.concatenate(N_);idx=np.concatenate(I_)
        # blender (x,y,z) -> scenekit (x,z,-y), scaled to squares
        pos=np.stack([pos[:,0],pos[:,2],-pos[:,1]],1)*SCALE
        nor=np.stack([nor[:,0],nor[:,2],-nor[:,1]],1)
        merged[k]=(pos.astype(np.float32),nor.astype(np.float32),idx.astype(np.uint32))
    out[t]=merged
    # clear scene for next piece
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
# write binary: "SCLP" v1, count; per piece: kind char, partCount; per part: mat id, vc, ic, positions, normals, indices
buf=bytearray(b'SCLP'); buf+=struct.pack('<II',1,len(out))
for t,merged in out.items():
    buf+=struct.pack('<BBH',ord(t),len(merged),0)
    for k,(pos,nor,idx) in merged.items():
        buf+=struct.pack('<B3xII',MATS.index(k),len(pos),len(idx))
        buf+=pos.tobytes(); buf+=nor.tobytes(); buf+=idx.tobytes()
raw=bytes(buf)
c=zlib.compressobj(9,zlib.DEFLATED,-15); comp=c.compress(raw)+c.flush()
open('build/sculpted/sculpted-pieces.bin','wb').write(comp)
np.savez('build/sculpted/meshes.npz',**{f'{t}_{k}_{a}':v for t,m in out.items() for k,arrs in m.items() for a,v in zip('pni',arrs)})
tot=0
for t,s in stats.items():
    for row in s: print(t,*row)
    tri=sum(len(v[2])//3 for v in out[t].values()); tot+=tri*{'K':1,'Q':1,'B':2,'N':2,'R':2,'P':8}[t]*2
    print(t,'tris',tri, {k:(len(v[0]),len(v[2])//3) for k,v in out[t].items()})
print('raw',len(raw),'compressed',len(comp),'board tris',tot)
