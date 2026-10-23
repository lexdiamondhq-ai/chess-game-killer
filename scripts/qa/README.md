# Piece legibility check

`legibility.py` answers one question for every look with a board picture: can a player tell every piece
apart at a glance on the phone, on both square colours, from both sides? It lays each flat board out the
way `BoardView` does, measures the pieces, and fails a look whose pieces would be mistaken for one another
or melt into their squares. `ChessGameKillerTests/PieceLegibilityTests.swift` guards the same sprites in
the test suite, without pictures.

Python 3 with Pillow and numpy only. No network, no app build.

## Run it

```sh
# Today's sprites, every look (about a minute); exit code 1 when any look fails.
python3 scripts/qa/legibility.py --out /tmp/legibility

# New sprites before they go into the catalog: one --sprites per prefix. The folder may hold
# gilded-wK.png ... gilded-bP.png, wK.png ... bP.png, or *.imageset folders. The contract
# (v1 520x568 or v2 560x760) is read from the PNG size.
python3 scripts/qa/legibility.py --out /tmp/legibility-new --sprites gilded-=path/to/new-gilded --sprites sculpted-=path/to/new-carved

# Just some looks, numbers only.
python3 scripts/qa/legibility.py --out /tmp/legibility --looks gilded,midnight --no-sheets

# Try another size on the square (k) or foot position (lift) before changing PieceImage.
python3 scripts/qa/legibility.py --out /tmp/legibility-k --sprites spark-=new --k 1.18 --lift 0.2
```

Every sprite set in the app takes part in the silhouette comparison even when `--looks` picks a few.
`--reference DIR` adds outside piece sets to the nearest-neighbour test, and `--calibrate DIR` recomputes
the reference envelope (see Calibration).

Output, in the `--out` folder:

- `summary.md`: a table with PASS/FAIL per look, its failing rules, the pairs most out of line and the
  weakest contour per side and square colour.
- `report.json`: every number (per set and side: heights, all 15 pairs, nearest neighbours; per look:
  contour figures per side, square colour, type and scale).
- `sheets/<look>.png`: the contact sheet. Six boards at 1x (start, two middlegames; White and Black at the
  bottom), a 3x close-up of the back ranks, then for each side on a light and a dark square: the twelve
  pieces at 1x true size, magnified, and at 3x with the contour band painted green where it reaches 3:1
  and red where it does not, with the numbers under each piece; last the 24 px silhouettes (the compared
  head tinted) and the 1x masks, with every verdict and warning.
- `boards/<look>-<start|mid1|mid2>-<white|black>-<1x|3x>.png`: the composited boards.

Look at the sheets, not just the table: the numbers are there to catch what the eye then confirms.

## How the board is drawn

As `BoardView.flatBoard` lays it out on an iPhone: the board 370 pt wide, the picture nine squares wide
(half a square of frame each side, `side / 18`), squares `side / 9`, the pre-iOS 26 glass frame, the
stone's drop shadow, the hairline, the coordinates, pieces drawn back rank first so nearer pieces overlap.
The look's colours, names and board picture are read from `BoardTheme.swift`, so new looks are picked up
by themselves (Neon has no board picture and is skipped).

Sprites are placed by their contract; 400 px per square in both:

| | canvas | foot (px) | above / below the foot | half width | k | lift |
|---|---|---|---|---|---|---|
| v1 (today) | 520 x 568 | 260, 400 | 1.0 / 0.42 sq | 0.65 sq | 1.22 | 0.15 |
| v2 (piece brief) | 560 x 760 | 280, 600 | 1.5 / 0.4 sq | 0.7 sq | 1.12 | 0.22 |

A sprite is drawn `2·hw·k` by `(top − bottom)·k` squares with its foot `lift` squares below the square's
centre. v1 pieces are clipped at the board's rounded edge, as `PieceImage` does today; v2 pieces are not, so
the board gets headroom for a king on the far rank. Not simulated: the iOS 26 Liquid Glass frame (the
older fallback is drawn; either only touches the frame), the 3D board, move marks, Core Graphics' exact
resampling (Lanczos here).

## What it measures, and why these thresholds

A pixel is part of a piece's **body** when its alpha is at least 0.85. Every contact shadow in today's sets
stays below 0.82 (most at 0.5-0.65) and bodies are opaque, so this keeps the solid piece and drops the
shadow, which must not count as the piece's outline.

### Silhouettes

The piece brief's test: shrink each body to **24 px tall** and name the type from the black shape alone.
The tool scales each shape to 24 px from its top to its lowest pixel, puts its foot at the bottom centre
(feet aligned) and compares every pair of types of one set by intersection over union (IoU): 1 is the
same shape, 0 nothing in common.

- **The head carries the type.** The bottom of every Staunton piece is the same turned base and body, so
  whole shapes overlap a lot for every pair, in good sets as in bad: over 28 well-known sets the whole-shape
  IoU of rook and pawn runs 0.51-0.78, and today's sets score 0.78-0.82, no clear line. The **top 40 %**
  (crown, cross, battlements, mitre, ball) separates them: 0.36-0.70 in the 28 sets, 0.73-0.78 in today's.
  The gate compares heads; whole shapes are reported.
- **Reference envelope.** A pair fails when its heads overlap more than that pair does in *any* of 28 piece
  sets from Lichess (both colours; `REF_HEAD` in the script), the sets millions of players read every day:
  alpha, caliente, california, cardinal, cburnett, celtic, chess7, chessnut, companion, cooke, dubrovny,
  fantasy, fresca, gioco, governor, icpieces, kosal, leipzig, maestro, merida, mpchess, pirouetti,
  reillycraig, rhosgfx, riohacha, spatial, staunty, tatiana. That is a lenient bar (as distinct as the
  least distinct of them), so a failure is a real problem. Envelope maxima for the brief's pairs:
  rook-pawn 0.70, bishop-pawn 0.83, queen-king 0.74, bishop-queen 0.74.
- **Which pairs fail.** The four the brief names (rook-pawn, bishop-pawn, queen-king, bishop-queen) fail the
  look, whatever their heights: today's rooks stand 1.44-1.49x the pawn's height and still read as pawns,
  so height does not rescue a shape. Any other pair over its envelope is a warning when its heights are less
  than 1.5x apart (a king and a pawn may share a round head; nobody mixes them up).
- **The brief's rules**, also failing: the rook at least 1.25x the pawn's height above the foot, the rook's
  top third at least 1.25x as wide as the pawn's (its head), the king the tallest, the pawn the smallest.
  The tournament order K > Q > B > N > R > P in steps of 0.05 squares is a warning on the sprites (the 3D
  mesh test in `SculptedBoardTests` holds the meshes to it; on screen, perspective can tip a close step).
- **At 1x**: the same IoU on the masks as they stand on the board at 1x (31-59 px tall today), and their
  overlap as drawn, unscaled, are reported for every pair.
- **Nearest neighbour** (warning only): for the brief's pairs, is a piece's shape closer to some other set's
  piece of its own type than to any of its partner types? It compares against the app's other set
  families (sets made from the same models, median 24 px IoU of 0.85 or more, are one family and never
  compared with each other) and any `--reference` sets. It is advisory because it is noisy: on the 28
  reference sets 27 of 280 pieces fail it.

### Contours

The piece brief's second test: every piece keeps a visible edge on the light and the dark square of its
board, for both sides. Each type stands alone on the 16 middle squares (c3-f6, 8 of each colour). The
**band** is the outermost 1 pt of its body (3 px at 3x); each band pixel is compared with the colour of the
square under that very pixel (the median of that square's stone), so a tall piece's top is judged against
the square behind it, as the eye sees it. Pixels over light squares and over dark squares are pooled
separately.

- **3:1, WCAG 2.1 SC 1.4.11** (non-text contrast): parts of a graphic needed to understand it need 3:1
  against adjacent colours. A piece's outline against its square is that. The **median** band pixel must
  reach it, that is at least half of the outline: lit from one side, a piece may lose its edge on the lit
  side but must keep it on the other. On the carved looks' squares (L* 80 and 25) 3:1 is a lightness step
  of about 30-34 L* (ΔL* is reported; one L* threshold would be too strict on dark squares or too lenient
  on light ones, so the ratio is the gate).
- **Judged at 3x**, the device's pixels, where a fine contour line (the brief allows one up to about
  0.6 pt) is resolved; 1x figures are in the report and on the sheets for what blurs at arm's length.
- Luminance only. A saturated gold on white enamel reads a little better than its ratio says, but shape is
  seen through luminance; colour alone gives soft, unstable edges.
- The cast shadow on the square is left out (the square's own colour is the reference): it falls on one
  side only and does not outline the piece.

## Baseline (today's sprites)

Every look fails. Silhouettes: rook vs pawn on every set (heads 0.77-0.78, envelope 0.70; vector 0.73), and
king vs queen on every set but `gilded-` (0.76-0.82, envelope 0.74). Contours: ivory on the cream squares
of every carved look at 1.2:1 (2.1:1 on Sculpted's grey), and the dark pieces on the dark squares of every
carved look (1.2-1.9:1); the rival sets fail most combinations on their mid-tone boards. Blueprint's plaster
pieces pass (4.8:1 and 7.3:1). The full table: the `summary.md` of a run.

## The Swift test

`PieceLegibilityTests` reads the sprites' alpha with Core Graphics, for every look with sprite pieces:

- every sprite is 560 x 760 (v2), nothing solid (alpha ≥ 0.85) within 4 px of the canvas edge, the
  shadow faded out at the edge (alpha ≤ 8/255), solid at the foot (280, 600) with the base centred on
  x 280 (± 6 px);
- the rook against the pawn of its colour: at least 1.25x its height, its top third at least 1.25x as wide,
  and flat-topped: 8 % of its height below its top it is already at least 0.85 of its widest. That last
  rule is the one that catches a rook read as a pawn: today's rooks are 0.71-0.82 (their battlements are a
  ring seen from above, rounded like a ball), the 28 reference rooks 0.92-1.00, the work-in-progress v2
  jewel renders 0.91. Width and height alone do not tell them apart (today's rook tops are 1.8x the pawn's
  head, their heights 1.44-1.49x).
- a self-check on two drawn rooks (a tower passes, a dome fails), so the measure itself is tested.

The size test fails on today's v1 sprites by design; it lands with the v2 sprites and the `PieceImage`
change.

## Calibration

The envelope (`REF_HEAD`, `REF_WHOLE`) was measured with this script on the 28 Lichess sets, each
rasterized from `lichess-org/lila/public/piece/<set>/<wK..bP>.svg` to a transparent 400 x 400 PNG (one
square). To recompute it, or measure other sets, put each set in its own folder (`wK.png` ... `bP.png`)
and run:

```sh
python3 scripts/qa/legibility.py --out /tmp/calibration --calibrate path/to/reference-sets
```

It prints new `REF_HEAD` and `REF_WHOLE` lines, the 90th percentiles and the nearest-neighbour failure rate,
and writes `calibration.json`. The same folder can be passed as `--reference` to a normal run. The
reference sets are not kept in this repository; they come under their own licences.
