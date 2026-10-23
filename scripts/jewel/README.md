# The jewel sets

Three.js source for the pre-rendered sets that are not carved in Blender: Fabergé, Blueprint and the
five rival boards (Spark, Drift, Pulse, Vector, Singularity). `scene.js` builds the board and the
pieces; `render.mjs` drives headless Chromium.

    npm install
    python3 -m http.server 8765 &
    node render.mjs "theme=faberge&shot=sprites&w=520&h=568" out/faberge-%s.png

That writes the twelve sprites (`faberge-wK.png` and so on) for `Assets.xcassets/Pieces`. Other shots:
`shot=board` (the flat board picture), `hero` and `lineup`. `render.mjs` points at the Chromium that
Playwright installs under `/opt/pw-browsers`; change `executablePath` to run it elsewhere.

Every top says what the piece is at phone size, as in the carved sets: the king a big cross, the
queen a coronet of eight points tipped with gems, the bishop a mitre that comes to a point, the
pawn a big round head.
