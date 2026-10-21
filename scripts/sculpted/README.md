# The sculpted set

Blender sources for the Sculpted look: the six pieces, the board, the studio light, and the
files the app loads. Run from the repository root with Blender's Python module
(`pip install bpy==5.2.2 numpy scikit-image pillow`).

1. `python scripts/sculpted/knight_sdf.py` sculpts the knight's head (marching cubes) into `kv.npy` / `kf.npy`.
2. `python scripts/sculpted/export.py` turns the pieces into game meshes: decimated, split
   normals at sharp edges, SceneKit axes, raw-deflated into `build/sculpted/sculpted-pieces.bin`
   (copy to `Assets.xcassets/Sculpted/sculpted-pieces.dataset`).
3. `python scripts/sculpted/bake.py -- squares build/sculpted/out/squares.png 16` bakes the stone squares (albedo only),
   and `-- art build/sculpted/out/board-art.png 64` the lit board picture for the flat look.
4. `python scripts/sculpted/sprites.py -- build/sculpted/sprites 48` renders the twelve flat-look sprites
   (add a name such as `sculpted-wN` to render just one).
5. `python scripts/sculpted/env.py` draws the studio light tent the pieces reflect, and `env_studio.py` the dark
   studio (a few soft boxes in a near-black room) used by the richer looks. `marble.py looks/m-<name>.json out.png`
   draws a look's stone squares.
6. Finishing for the asset catalog: `python scripts/sculpted/fade.py build/sculpted/sprites build/sculpted/final`
   fades each sprite's shadow out before its edge (copy to `Assets.xcassets/Pieces/sculpted-*.imageset`), and
   `python scripts/sculpted/frame.py build/sculpted/out/board-art.png build/sculpted/out/board-sculpted.jpg`
   puts the baked squares in a clean lacquer frame (copy to `Assets.xcassets/Boards/board-sculpted.imageset`).

`pieces.py` holds the turned pieces (lathe profiles, flutes, booleans), `board.py` the marble,
frame and inlay. Heights follow tournament ratios: K 1.2, Q 1.0, B 0.9, N 0.8, R 0.7, P 0.6 squares.
