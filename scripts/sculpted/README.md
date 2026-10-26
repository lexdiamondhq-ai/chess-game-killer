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
   for the gilded set (`gilded-pieces.bin`, copy to `Sculpted/gilded-pieces.dataset`). Each part is one
   finish, the ids `SculptedAssets.Finish` reads: body 0, metal 1, gem 2, pearl 3, and shade 4, the dark
   floor of the rook's well (an app that does not know 4 draws it as the body).
3. `python scripts/sculpted/bake.py -- squares build/sculpted/out/squares.png 16` bakes the stone squares (albedo only),
   and `-- art build/sculpted/out/board-art.png 64` the lit board picture for the flat look.
4. `python scripts/sculpted/sprites.py -- build/sculpted/sprites 48` renders the twelve flat-look sprites
   (add a name such as `sculpted-wN` to render just one); `sprites.py -- build/sculpted/gilded-sprites 48 gilded`
   renders the gilded ones (`gilded-wK` and so on). They follow sprite contract v2, shared by every set in
   the app: 560 x 760 px, orthographic, 28 degrees above the board, 400 px per square, the foot at (280, 600),
   so the picture covers 0.7 squares either side of the foot, 1.5 above it and 0.4 below. The app draws a
   sprite 1.4k squares wide and 1.9k tall with its foot `lift` below the square's center (`SpriteFrame.sideOn`
   in `BoardView.swift`; k 1.2 and lift 0.24 suit these sets: the kings' crosses reach 1.2 squares above the foot,
   the bases 0.15 below it).
   Next to each picture goes `mask/<name>.png`, the piece alone, for the finishing step. `--res 50` renders
   at half size for quick tests and `--light tweaks.json` tries other light levels or finishes.
5. `python scripts/sculpted/env.py` draws the studio light tent the pieces reflect, and `env_studio.py` the dark
   studio (a few soft boxes in a near-black room) used by the richer looks. `marble.py looks/m-<name>.json out.png`
   draws a look's stone squares, and `flat_art.py <squares.jpg> <board.jpg> [line hex]` its flat board picture
   (Noir uses the champagne line CCB88F, Gilded and Portoro the gold DDB06C; copy to `Assets.xcassets/Boards/board-<look>.imageset`).
   A spec with `"crisp": true` draws even, sharp-edged veins: Gilded's brown marble with black veins
   (`m-gilded.json`) and Portoro's black marble with gold veins (`m-portoro.json`), both on deep cream.
   Noir, Bordeaux and Midnight keep their own dark stone on the same deep cream. Keep the ivory well
   brighter than the light squares, in 3D and flat (tests check every look): the ivory sprites of both
   sets use an ivory a little brighter than the 3D looks' (seen from lower, more of each piece is in shade),
   with the same darkening toward the outline (`edge` in `sprites.py`).
6. Finishing for the asset catalog: `python scripts/sculpted/fade.py build/sculpted/sprites build/sculpted/final`
   darkens the ivory toward its outline (a soft band and a fine line, from the masks) and fades each sprite's
   shadow out before its edge (copy to `Assets.xcassets/Pieces/sculpted-*.imageset`, or
   `gilded-*.imageset`), and
   `python scripts/sculpted/frame.py build/sculpted/out/board-art.png build/sculpted/out/board-sculpted.jpg`
   puts the baked squares in a clean lacquer frame (copy to `Assets.xcassets/Boards/board-sculpted.imageset`).

`pieces.py` holds the turned pieces (lathe profiles, flutes, booleans), `gilded.py` the gilded set
(stepped bases, gold bands and crowns, the striped-mane knight), `board.py` the marble, frame and inlay.
Both sets share their tops and heights, so each type is told by its top as much as its height: a long
Latin cross (ivory on the white king, metal on the dark one: the `cross` finish, id 5), a crown of eight
metal points tipped with balls round a ball on top (`queen_crown` in `pieces.py`) on a slim queen standing well
under the king, which from the 3D camera above reads as a star round a ball and never as the rook's ring, a pointed mitre cut through to a metal core,
a tower of five capped merlons round a dark well, the horse's head, one ball. Heights in squares, before
the game's 1.1 scale: K 1.336, B 1.0, Q 0.92, N 0.83 (gilded 0.82), R 0.742, P 0.561.

Fine detail (both sets): a row of carved beads round every plinth (gilded: gold beads along the recessed band),
gadrooned crown cups on the king and queen, four stones round the king's crown (one faces the player), pearl or
gold beading on the queen's and bishop's collars, and on the rook arrow slits on four sides with a dark back
(`slits` in `pieces.py`), plus ashlar masonry with staggered joints on the classic tower. None of it touches the
outlines the pieces are told apart by. Helpers: `beads`, `gadroons`, `compose`, `radius_at`, `slits` in `pieces.py`.

