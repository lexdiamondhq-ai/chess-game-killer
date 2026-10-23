# The jewel sets

Three.js source for the pre-rendered sets that are not carved in Blender: Fabergé, Blueprint and the
five rival boards (Spark, Drift, Pulse, Vector, Singularity). `scene.js` builds the board and the
pieces; `render.mjs` drives headless Chromium.

    npm install
    python3 -m http.server 8765 &
    node render.mjs "theme=faberge&shot=sprites&w=560&h=760&el=28&st=1.5&sb=-0.4&hw=0.7" out/faberge-%s.png

That writes the twelve sprites (`faberge-wK.png` and so on) for `Assets.xcassets/Pieces`. To use
another port, serve the folder there and set `JEWEL_PORT` (for example `JEWEL_PORT=8791 node render.mjs ...`).
`only=wK,bN` renders just those sprites. Other shots: `shot=board` (the flat board picture), `hero` and
`lineup`. `render.mjs` points at the Chromium that Playwright installs under `/opt/pw-browsers`; change
`executablePath` to run it elsewhere.

## Sprite contract (v2)

- 560 x 760 px, transparent, orthographic camera 28 degrees above the board, 400 px per square.
- The centre of the piece's foot at x 280, y 600: the canvas covers 0.7 squares either side of it,
  1.5 above and 0.4 below. Every piece, its contact shadow included, stays well clear of the edges.
- The app draws a sprite 1.4 k squares wide and 1.9 k tall, the foot `lift` squares below the square's
  centre. These sets were checked at k 1.2, lift 0.24.

## What makes each piece read at phone size

- King: the tallest, with a big thick cross (arms much wider than the stem) set with a gem.
- Queen: eight ball-tipped points leaning out of a coronet, around a taller ball. No cross.
- Bishop: a tall mitre with a deep cut and a small ball on its tip. The cut runs along the camera's line
  of sight (clipping planes), so it shows in the outline; it is lined in the accent.
- Knight: a carved head. The profile is filled with points, triangulated (Delaunay) and raised into
  rounded sides with the cheek, brow, eye socket and nostril modelled in. A scalloped mane in the accent
  runs down the back of the neck.
- Rook: a straight tower with four big merlons around a dark well. The notches face front, back and
  sides, so they show from the camera. The merlon caps are in the accent.
- Pawn: one ball on a collar.
- Heights on screen, in squares above the foot: king 1.163, queen 1.035, bishop 0.920, knight 0.843,
  rook 0.777, pawn 0.562 (in 3D: 1.30, 1.16, 1.03, 0.92, 0.75, 0.62). From 28 degrees the rook's back
  merlons stand higher than its middle, so the rook is kept low enough to stay under the knight.

## Light

- A key light from the front left, the right side of each piece in soft shade.
- Light pieces darken toward their outline (`edgeShade`, applied after tone mapping), so they keep a
  contour on light squares. On Spark, Drift and Pulse, whose middle squares glow as bright as the
  pieces, they also get a fine contour shade (`contour()`, `GLOW_CONTOUR`, about 0.55 pt on the phone).
- Dark pieces get bright rims from strip lights behind and below them. A black flag keeps the warm
  reflector card off the dark bodies (the knight's side would mirror it as a flat brown), while the gold
  and other metals still catch it.
- One accent family per set, on the parts that name the piece (`sideMats`: cross, crown, cap, tip,
  lining, mane, eye).

Tuning parameters can go on the query string for experiments, for example `ef`, `ew`, `elo` (edge
shading), `lw`, `lf`, `ls` (contour), `kk`, `rb` (rims), `fr` (reflector) and `ff` (front fill).
