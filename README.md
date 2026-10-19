# Chess Game Killer

One beautiful iOS chess game, with every feature easy to reach and easy to understand.

## Features
- Play the computer or a friend on the same phone. The computer comes as five rivals, Spark to Singularity (Stockfish 17 from Beginner to Grandmaster), each with its own sigil and a line about how it plays
- Pick your side: White or Black (Gold or Violet on the Neon board), or random
- Chess clocks: 3+2, 5+0, 10+0 or 15+10, or no clock. The last ten seconds count down in tenths, and a fallen flag ends the game
- The coach is one orb at the bottom of the screen. Its ring is the live evaluation. After a move it stretches out for a moment with the verdict (best, excellent, good, inaccuracy, mistake, blunder) and the better move, then shrinks back. Tap it and it unfolds into the full coach: eval bar, the two best moves (tap one to play it), Undo, Hints, Flip and New game
- When the game ends the orb opens on its own with the result, your accuracy and how many best moves, mistakes and blunders you made, plus Rematch
- The two best moves drawn on the board: a solid arrow for the best, a dashed arrow for the next best. The coach can be set to full, arrows only, verdicts only or silent
- Player plates above the board: who is to move and the clocks. Down each edge of the board, a rail counts what that side has captured (each piece with how many) and shows the material lead. The moves so far run in a line under the board
- Captured pieces blow apart in sparks in the theme's colors
- Analyzer: take a photo of a real board, pick a screenshot or set up any position, fix any square, and see Stockfish's two best moves with the lines that follow; then play on from there
- Sound effects made with ElevenLabs
- Settings with a live board preview: Malachite (default), Fabergé, Blueprint and Neon boards, arrows, verdicts, sound, haptics, and the open-source licenses
- Undo, flip the board, promotion picker, haptics
- Training with Coach Leo, a grandmaster coach: narrated lessons, daily puzzles and your own mistakes to fix (see below)

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

## Training with Coach Leo
Tap the graduation cap at the top left to meet Coach Leo, a warm grandmaster coach for players who want a hand.
- **Lessons that play like short videos.** The pieces move, arrows and glowing squares point things out, and Leo talks you through it in his ElevenLabs voice. Pause, go back or skip, and make the moves yourself when it's your turn. 15 lessons across 8 units, from what the pieces are worth to mating with a rook.
- **A daily session of about six minutes.** A warm-up, four puzzles on today's skill pitched so you solve about four in five, a review of anything missed (your own game mistakes first), one mixed puzzle with no clue, and a finisher so it ends on a win.
- **One habit before every move, the Traffic Light.** Red: what are they threatening? Yellow: any checks, captures or attacks? Green: is my move safe?
- **Progress you can feel.** XP and ranks named after the pieces (Pawn up to King), a daily streak that forgives one missed day a week, and rings that fill as you master each skill.
- **Help during games.** Against the computer, Leo names the pattern behind your move (a missed mate, a piece left hanging, a fork you found): a small badge on the coach orb shows he has something to say, and opening the orb shows his tip with buttons to try the move again or watch the lesson that teaches it. Mistakes are saved and come back as puzzles. **Think** works through the Traffic Light for the position on the board.

Everything Leo teaches is data in `ChessGameKiller/Training/Content`: `course.json` (units, skills, ranks and what Leo says), `lesson-*.json` and `drills.json` (the puzzles). The scripts in `scripts/training` make and check it (they need `pip install chess` and any UCI Stockfish):
- `build_lessons.py` writes the lessons; `--engine` checks every answer with Stockfish.
- `mine_puzzles.py` mines puzzles from beginner-style engine games, `compose_puzzles.py` composes pattern puzzles and endgames, and `build_drills.py` picks the final set.
- `verify_training.py` checks every move, square and checkmate in the content.
- `make_narration.py` records Leo's lines. The "Record lesson narration with ElevenLabs" workflow runs it when a branch changes a lesson, using the `ELEVENLABS_API_KEY` secret, and commits the recordings to `ChessGameKiller/Training/Narration`. A line is only ever recorded once; until it is, the phone's own voice reads it.

## Layout
- `ChessGameKiller/App` – app entry point
- `ChessGameKiller/Model` – the game, the match against the computer, the clock, sounds
- `ChessGameKiller/Engine` – Stockfish, move grading and notation
- `ChessGameKiller/Views` – SwiftUI screens: the game screen (`ContentView`), the board, the coach orb, player plates, rivals, the new-game sheet and settings
- `ChessGameKiller/Training` – Coach Leo: the course content, lesson player, drills, sessions and progress
- `ChessGameKillerTests` – unit tests
- `scanner` – the photo scanner server (JavaScript, Cloudflare Workers)

## Credits
- Piece artwork: "cburnett" set by Colin M.L. Burnett, licensed GPLv2+ (via Lichess). The Neon pieces are recolored from it with `scripts/make_neon_pieces.py`.
- Stockfish, GPLv3, by the Stockfish developers. Because the app includes Stockfish, the app is open source under the GPL too.
