# The sculpted sets

Blender sources for the 3D looks: two sets of six pieces (the classic carved set and the black-and-gold
gilded set), the board, the studio light, and the files the app loads. Run from the
repository root with Blender's Python module (`pip install bpy==5.2.2 numpy scipy scikit-image pillow`).

1. `python scripts/sculpted/knight_profile.py` carves the classic knight's head from a side profile into
   `kv.npy` / `kf.npy`, and `python scripts/sculpted/knight_icon.py` the gilded knight (stone, gold mane
   and amber eyes) into `build/sculpted/icon`.
2. `python scripts/sculpted/export.py` turns the pieces into game meshes: decimated, split
   normals at sharp edges, SceneKit axes, raw-deflated into `build/sculpted/sculpted-pieces.bin`
   (copy to `Assets.xcassets/Sculpted/sculpted-pieces.dataset`). `export.py -- gilded` does the same
   for the gilded set (`gilded-pieces.bin`, copy to `Sculpted/gilded-pieces.dataset`).
3. `python scripts/sculpted/bake.py -- squares build/sculpted/out/squares.png 16` bakes the stone squares (albedo only),
   and `-- art build/sculpted/out/board-art.png 64` the lit board picture for the flat look.
4. `python scripts/sculpted/sprites.py -- build/sculpted/sprites 48` renders the twelve flat-look sprites
   (add a name such as `sculpted-wN` to render just one); `sprites.py -- build/sculpted/gilded-sprites 48 gilded`
   renders the gilded ones (`gilded-wK` and so on).
5. `python scripts/sculpted/env.py` draws the studio light tent the pieces reflect, and `env_studio.py` the dark
   studio (a few soft boxes in a near-black room) used by the richer looks. `marble.py looks/m-<name>.json out.png`
   draws a look's stone squares, and `flat_art.py <squares.jpg> <board.jpg> [line hex]` its flat board picture
   (Noir uses the champagne line CCB88F, Gilded the gold DDB06C; copy to `Assets.xcassets/Boards/board-<look>.imageset`).
   A spec with `"crisp": true` draws even, sharp-edged veins, as Gilded's gold-veined Portoro does.
6. Finishing for the asset catalog: `python scripts/sculpted/fade.py build/sculpted/sprites build/sculpted/final`
   fades each sprite's shadow out before its edge (copy to `Assets.xcassets/Pieces/sculpted-*.imageset`, or
   `gilded-*.imageset`), and
   `python scripts/sculpted/frame.py build/sculpted/out/board-art.png build/sculpted/out/board-sculpted.jpg`
   puts the baked squares in a clean lacquer frame (copy to `Assets.xcassets/Boards/board-sculpted.imageset`).

`pieces.py` holds the turned pieces (lathe profiles, flutes, booleans), `gilded.py` the gilded set
(stepped bases, gold bands and crowns, the striped-mane knight), `board.py` the marble, frame and inlay. Heights follow tournament ratios: K 1.2, Q 1.0, B 0.9, N 0.8, R 0.7, P 0.6 squares.
