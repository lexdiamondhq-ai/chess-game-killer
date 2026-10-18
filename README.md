# Chess Game Killer

One beautiful iOS chess game, with every feature easy to reach and easy to understand.

## Features
- Play the computer (Stockfish 17, five levels from Beginner to Grandmaster) or a friend on the same phone
- Pick your side: White or Black (Gold or Violet on the Neon board), or random
- Coach bar at the bottom grades every move you make (best, excellent, good, inaccuracy, mistake, blunder) and names the better move
- The two best moves drawn on the board: a solid arrow for the best, a dashed arrow for the next best
- Captured pieces blow apart in sparks in the theme's colors
- Sound effects made with ElevenLabs
- Walnut and Neon boards, undo, promotion picker, haptics
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

## Training with Coach Leo
Tap **Train** at the top left to meet Coach Leo, a warm grandmaster coach for players who want a hand.
- **Lessons that play like short videos.** The pieces move, arrows and glowing squares point things out, and Leo talks you through it in his ElevenLabs voice. Pause, go back or skip, and make the moves yourself when it's your turn. 15 lessons across 8 units, from what the pieces are worth to mating with a rook.
- **A daily session of about six minutes.** A warm-up, four puzzles on today's skill pitched so you solve about four in five, a review of anything missed (your own game mistakes first), one mixed puzzle with no clue, and a finisher so it ends on a win.
- **One habit before every move, the Traffic Light.** Red: what are they threatening? Yellow: any checks, captures or attacks? Green: is my move safe?
- **Progress you can feel.** XP and ranks named after the pieces (Pawn up to King), a daily streak that forgives one missed day a week, and rings that fill as you master each skill.
- **Help during games.** Against the computer, Leo names the pattern behind your move in the coach bar (a missed mate, a piece left hanging, a fork you found), lets you try the move again, and opens the lesson that teaches it. Mistakes are saved and come back as puzzles. **Think** works through the Traffic Light for the position on the board.

Everything Leo teaches is data in `ChessGameKiller/Training/Content`: `course.json` (units, skills, ranks and what Leo says), `lesson-*.json` and `drills.json` (the puzzles). The scripts in `scripts/training` make and check it (they need `pip install chess` and any UCI Stockfish):
- `build_lessons.py` writes the lessons; `--engine` checks every answer with Stockfish.
- `mine_puzzles.py` mines puzzles from beginner-style engine games, `compose_puzzles.py` composes pattern puzzles and endgames, and `build_drills.py` picks the final set.
- `verify_training.py` checks every move, square and checkmate in the content.
- `make_narration.py` records Leo's lines. The "Record lesson narration with ElevenLabs" workflow runs it when a branch changes a lesson, using the `ELEVENLABS_API_KEY` secret, and commits the recordings to `ChessGameKiller/Training/Narration`. A line is only ever recorded once; until it is, the phone's own voice reads it.

## Layout
- `ChessGameKiller/App` – app entry point
- `ChessGameKiller/Model` – the game, the match against the computer, sounds
- `ChessGameKiller/Engine` – Stockfish, move grading and notation
- `ChessGameKiller/Views` – SwiftUI screens
- `ChessGameKiller/Training` – Coach Leo: the course content, lesson player, drills, sessions and progress
- `ChessGameKillerTests` – unit tests

## Credits
- Piece artwork: "cburnett" set by Colin M.L. Burnett, licensed GPLv2+ (via Lichess). The Neon pieces are recolored from it with `scripts/make_neon_pieces.py`.
- Stockfish, GPLv3, by the Stockfish developers. Because the app includes Stockfish, the app is open source under the GPL too.
