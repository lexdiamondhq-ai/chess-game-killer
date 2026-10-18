# Chess Game Killer

One beautiful iOS chess game, with every feature easy to reach and easy to understand.

## Features
- Play the computer or a friend on the same phone. The computer comes as five rivals, Spark to Singularity (Stockfish 17 from Beginner to Grandmaster), each with its own sigil and a line about how it plays
- Pick your side: White or Black (Gold or Violet on the Neon board), or random
- Chess clocks: 3+2, 5+0, 10+0 or 15+10, or no clock. The last ten seconds count down in tenths, and a fallen flag ends the game
- The coach is one orb at the bottom of the screen. Its ring is the live evaluation. After a move it stretches out for a moment with the verdict (best, excellent, good, inaccuracy, mistake, blunder) and the better move, then shrinks back. Tap it and it unfolds into the full coach: eval bar, the two best moves (tap one to play it), Undo, Hints, Flip and New game
- When the game ends the orb opens on its own with the result, your accuracy and how many best moves, mistakes and blunders you made, plus Rematch
- The two best moves drawn on the board: a solid arrow for the best, a dashed arrow for the next best. The coach can be set to full, arrows only, verdicts only or silent
- Player plates above the board: who is to move, the clocks, captured pieces and the material lead. The moves so far run in a line under the board
- Captured pieces blow apart in sparks in the theme's colors
- Analyzer: take a photo of a real board, pick a screenshot or set up any position, fix any square, and see Stockfish's two best moves with the lines that follow; then play on from there
- Sound effects made with ElevenLabs
- Settings with a live board preview: Walnut and Neon boards, arrows, verdicts, sound, haptics, and the open-source licenses
- Undo, flip the board, promotion picker, haptics

## Stack
- SwiftUI, iOS 17+
- Xcode project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [ChessKit](https://github.com/chesskit-app/chesskit-swift) for the rules
- [ChessKitEngine](https://github.com/chesskit-app/chesskit-engine) to run Stockfish on the device

## Run it
```sh
brew install xcodegen
xcodegen
open ChessGameKiller.xcodeproj
```
Then press Run in Xcode. The first build downloads Stockfish's neural network files (about 78 MB) into `.nnue-cache`; later builds reuse them (`scripts/fetch_nnue.sh`).

## Tests
`xcodebuild test -scheme ChessGameKiller -destination 'platform=iOS Simulator,name=iPhone 16'`
GitHub Actions runs the same build and tests on every pull request, including a real Stockfish search.

## Sounds
The sounds in `ChessGameKiller/Sounds` are made with the ElevenLabs Sound Effects API by `scripts/make_sounds.py`. To change one, edit its prompt in that script and push to the `generate-sounds` branch (or run the "Generate sounds with ElevenLabs" workflow). The workflow uses the `ELEVENLABS_API_KEY` repository secret and commits the new files back to that branch.

## Photo scanner
Photos are read by Claude through a small server in `scanner/` (a Cloudflare Worker), so the Anthropic key never ships in the app. `.github/workflows/scanner.yml` tests it, deploys it and tries it on the boards in `scanner/test/boards`. It needs two repository secrets: `ANTHROPIC_API_KEY` and `CLOUDFLARE_API_TOKEN` (made from Cloudflare's "Edit Cloudflare Workers" template); the account ID is looked up from the token. Each address can scan at most 10 times a minute. The app finds the server through `ScannerConfig.endpoint` in `ChessGameKiller/Engine/BoardReader.swift`.

## Layout
- `ChessGameKiller/App` – app entry point
- `ChessGameKiller/Model` – the game, the match against the computer, the clock, sounds
- `ChessGameKiller/Engine` – Stockfish, move grading and notation
- `ChessGameKiller/Views` – SwiftUI screens: the game screen (`ContentView`), the board, the coach orb, player plates, rivals, the new-game sheet and settings
- `ChessGameKillerTests` – unit tests
- `scanner` – the photo scanner server (JavaScript, Cloudflare Workers)

## Credits
- Piece artwork: "cburnett" set by Colin M.L. Burnett, licensed GPLv2+ (via Lichess). The Neon pieces are recolored from it with `scripts/make_neon_pieces.py`.
- Stockfish, GPLv3, by the Stockfish developers. Because the app includes Stockfish, the app is open source under the GPL too.
