#!/usr/bin/env python3
"""Turns Maia's lc0 networks into the small files the app reads (ChessGameKiller/Maia/maia-*.bin).

Maia (https://github.com/CSSLab/maia-chess, GPLv3) is a set of networks trained on Lichess games
to play the move a person of a given rating would play. Download the .pb.gz files from its
maia_weights folder, then:

    python3 scripts/maia/convert_maia.py maia-1100.pb.gz maia-1200.pb.gz maia-1600.pb.gz maia-1900.pb.gz

Each batch norm is folded into one scale and shift per channel. The file is little-endian:
"MAIA", then five uint32 (version 1, blocks, filters, squeeze-excitation channels, policy planes),
then, in this order, weights as float16 and per-channel vectors as float32:
  input conv [F][112][3][3], scale [F], shift [F]
  per block: conv1 [F][F][3][3], scale, shift; conv2 [F][F][3][3], scale, shift;
             se w1 [S][F], b1 [S], w2 [2F][S], b2 [2F]
  policy1 conv [F][F][3][3], scale, shift
  policy conv [P][F][3][3], bias [P]
"""
import os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lc0net

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "ChessGameKiller", "Maia")

def write(net, path):
    F = net["input"]["cout"]; S = len(net["res"][0]["se"][1]); P = net["policy"]["cout"]
    with open(path, "wb") as f:
        f.write(b"MAIA" + struct.pack("<5I", 1, len(net["res"]), F, S, P))
        half = lambda a: f.write(np.asarray(a, "<f2").tobytes())
        full = lambda a: f.write(np.asarray(a, "<f4").tobytes())
        def conv(c): half(c["w"]); full(c["scale"]); full(c["shift"])
        conv(net["input"])
        for r in net["res"]:
            conv(r["c1"]); conv(r["c2"])
            w1, b1, w2, b2 = r["se"]; half(w1); full(b1); half(w2); full(b2)
        conv(net["policy1"])
        half(net["policy"]["w"]); full(net["policy"]["shift"])

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for src in sys.argv[1:]:
        name = os.path.basename(src).split(".")[0]
        net = lc0net.load_conv_policy(src)
        dest = os.path.join(OUT, name + ".bin")
        write(net, dest)
        print(dest, os.path.getsize(dest))
