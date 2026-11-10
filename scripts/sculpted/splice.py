# Puts re-exported pieces into a set without rebuilding the rest (the knights take their own
# long build): splice.py set.bin pieces.bin out.bin replaces the pieces found in
# pieces.bin (from ONLY=K export.py) inside set.bin.
import sys, zlib, struct
def read(path):
    d=zlib.decompress(open(path,'rb').read(),-15); o=4
    assert d[:4]==b'SCLP'; ver,n=struct.unpack_from('<II',d,o); o+=8; out={}
    for _ in range(n):
        letter=chr(d[o]); pc=d[o+1]; start=o; o+=4
        for _ in range(pc):
            vc,ic=struct.unpack_from('<II',d,o+4); o+=12+vc*24+ic*4
        out[letter]=d[start:o]
    return out
a=read(sys.argv[1]); b=read(sys.argv[2])
for k,v in b.items(): assert k in a; a[k]=v
buf=b'SCLP'+struct.pack('<II',1,len(a))+b''.join(a.values())
c=zlib.compressobj(9,zlib.DEFLATED,-15); open(sys.argv[3],'wb').write(c.compress(buf)+c.flush())
