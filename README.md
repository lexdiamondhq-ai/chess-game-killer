# Chess Game Killer

One beautiful iOS chess game, with every feature easy to reach and easy to understand.

## Stack
- SwiftUI, iOS 17+
- Xcode project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Run it
```sh
brew install xcodegen
xcodegen
open ChessGameKiller.xcodeproj
```
Then press Run in Xcode.

## Tests
`xcodebuild test -scheme ChessGameKiller -destination 'platform=iOS Simulator,name=iPhone 16'`
GitHub Actions runs the same build and tests on every pull request.

## Layout
- `ChessGameKiller/App` – app entry point
- `ChessGameKiller/Model` – game state on top of [ChessKit](https://github.com/chesskit-app/chesskit-swift) (rules)
- `ChessGameKiller/Views` – SwiftUI screens
- `ChessGameKillerTests` – unit tests

## Credits
Piece artwork: "cburnett" set by Colin M.L. Burnett, licensed GPLv2+ (via Lichess).
