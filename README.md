# Chess Game Killer

One beautiful iOS chess game, with every feature easy to reach and easy to understand.

## Features
- Play the computer (Stockfish 17, five levels from Beginner to Grandmaster) or a friend on the same phone
- Pick your side: White or Black (Gold or Violet on the Neon board), or random
- Coach bar at the bottom grades every move you make (best, excellent, good, inaccuracy, mistake, blunder) and names the better move
- The two best moves drawn on the board: a solid arrow for the best, a dashed arrow for the next best
- Captured pieces blow apart in sparks in the theme's colors
- Analyzer: take a photo of a real board, pick a screenshot or set up any position, fix any square, and see Stockfish's two best moves with the lines that follow; then play on from there
- Sound effects made with ElevenLabs
- Walnut and Neon boards, undo, promotion picker, haptics

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
Photos are read by Claude through a small server in `scanner/` (a Cloudflare Worker), so the Anthropic key never ships in the app. `.github/workflows/scanner.yml` tests it, deploys it and tries it on the boards in `scanner/test/boards`. It needs three repository secrets: `ANTHROPIC_API_KEY`, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. Each address can scan at most 10 times a minute. The app finds the server through `ScannerConfig.endpoint` in `ChessGameKiller/Engine/BoardReader.swift`.

## Layout
- `ChessGameKiller/App` – app entry point
- `ChessGameKiller/Model` – the game, the match against the computer, sounds
- `ChessGameKiller/Engine` – Stockfish, move grading and notation
- `ChessGameKiller/Views` – SwiftUI screens
- `ChessGameKillerTests` – unit tests
- `scanner` – the photo scanner server (JavaScript, Cloudflare Workers)

## Credits
- Piece artwork: "cburnett" set by Colin M.L. Burnett, licensed GPLv2+ (via Lichess). The Neon pieces are recolored from it with `scripts/make_neon_pieces.py`.
- Stockfish, GPLv3, by the Stockfish developers. Because the app includes Stockfish, the app is open source under the GPL too.
