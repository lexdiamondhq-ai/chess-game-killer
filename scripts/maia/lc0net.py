"""Reads an lc0 weights file (a Maia network) and runs its policy head with numpy.

Maia's networks are lc0 networks: 6 residual blocks of 64 filters with squeeze-excitation,
classical 112-plane input and a convolutional policy head (80 planes of 8x8).
"""
import gzip, struct
import numpy as np

def varint(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1
        r |= (c & 0x7F) << s; s += 7
        if c < 0x80: return r, i

def fields(b):
    i, out = 0, []
    while i < len(b):
        key, i = varint(b, i); f, t = key >> 3, key & 7
        if t == 0: v, i = varint(b, i)
        elif t == 1: v = b[i:i+8]; i += 8
        elif t == 5: v = b[i:i+4]; i += 4
        elif t == 2:
            n, i = varint(b, i); v = b[i:i+n]; i += n
        else: raise ValueError(t)
        out.append((f, t, v))
    return out

def msg(b):
    d = {}
    for f, t, v in fields(b): d.setdefault(f, []).append((t, v))
    return d

def layer(b):
    d = msg(b)
    if 3 not in d: return None
    mn = struct.unpack('<f', d[1][0][1])[0] if 1 in d else 0.0
    mx = struct.unpack('<f', d[2][0][1])[0] if 2 in d else 0.0
    enc = d[4][0][1] if 4 in d else 1
    raw = d[3][0][1]
    if enc in (0, 1):
        u = np.frombuffer(raw, dtype='<u2').astype(np.float32)
        return (mn + (mx - mn) * u / 65535.0).astype(np.float32)
    if enc == 2: return np.frombuffer(raw, dtype='<f2').astype(np.float32)
    raise ValueError(enc)

def conv(b):
    d = msg(b)
    g = lambda k: layer(d[k][0][1]) if k in d else None
    w, bias, mean, var, gam, bet = (g(k) for k in range(1, 7))
    C = len(mean) if mean is not None else len(bias)
    if gam is None: gam = np.ones(C, np.float32); bet = np.zeros(C, np.float32)
    if bias is not None and mean is not None: mean = mean - bias
    inv = 1.0 / np.sqrt(var + 1e-5)
    # Fold batch norm into one scale and shift: y = conv*scale + shift.
    scale = gam * inv; shift = bet - mean * scale
    return dict(w=w, scale=scale.astype(np.float32), shift=shift.astype(np.float32), cout=C)

def conv2d(x, c, k):
    cin = x.shape[0]; cout = c['cout']
    w = c['w'].reshape(cout, cin, k, k)
    if k == 1:
        y = np.einsum('oi,ihw->ohw', w[:, :, 0, 0], x)
    else:
        p = np.pad(x, ((0,0),(1,1),(1,1)))
        y = np.zeros((cout, 8, 8), np.float32)
        for dy in range(3):
            for dx in range(3):
                y += np.einsum('oi,ihw->ohw', w[:, :, dy, dx], p[:, dy:dy+8, dx:dx+8])
    return y * c['scale'][:, None, None] + c['shift'][:, None, None]

relu = lambda x: np.maximum(x, 0)

def load_conv_policy(path):
    net = msg(gzip.open(path).read())
    W = msg(net[10][0][1])
    res = []
    for _, rb in W[2]:
        r = msg(rb); se = msg(r[3][0][1])
        res.append(dict(c1=conv(r[1][0][1]), c2=conv(r[2][0][1]), se=[layer(se[k][0][1]) for k in (1, 2, 3, 4)]))
    pd = msg(W[3][0][1])
    return dict(input=conv(W[1][0][1]), res=res, policy1=conv(W[11][0][1]),
                policy=dict(w=layer(pd[1][0][1]), scale=np.ones(80, np.float32), shift=layer(pd[2][0][1]), cout=80))

def policy_conv(net, planes):
    x = relu(conv2d(planes, net['input'], 3))
    for r in net['res']:
        y = relu(conv2d(x, r['c1'], 3))
        y = conv2d(y, r['c2'], 3)
        w1, b1, w2, b2 = r['se']; C = y.shape[0]
        h = relu(w1.reshape(-1, C) @ y.mean(axis=(1, 2)) + b1)
        z = w2.reshape(2 * C, -1) @ h + b2
        y = y * (1 / (1 + np.exp(-z[:C])))[:, None, None] + z[C:][:, None, None]
        x = relu(y + x)
    x = relu(conv2d(x, net['policy1'], 3))
    return conv2d(x, net['policy'], 3).reshape(-1)
