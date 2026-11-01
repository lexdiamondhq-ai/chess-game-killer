import SwiftUI

// The game's faces on the Lock Screen and in the Dynamic Island, in the app's Flat look: cream
// and walnut squares, the Icon pieces, the rival's portrait, grey glass and grey clock pills.
// Compiled into the app too, so the app's tests can draw them; the widget extension puts them in
// ActivityKit's frames (ChessGameKillerWidget/LiveGameWidget.swift). SwiftUI and Foundation only.

/// The colors: the game screen's grey glass and ivory ink, and the Flat board's squares.
enum LiveGamePalette {
    /// Behind the Lock Screen's card: the game screen's grey glass.
    static let background = Color(red: 0.157, green: 0.141, blue: 0.137)
    static let ink = Color(red: 0.965, green: 0.945, blue: 0.91)
    static let ink2 = ink.opacity(0.68)
    static let ink3 = ink.opacity(0.45)
    static let ivory = Color(red: 0.957, green: 0.929, blue: 0.875)
    static let onIvory = Color(red: 0.082, green: 0.067, blue: 0.047)
    /// The game screen's clock pill.
    static let pill = Color(red: 0.239, green: 0.231, blue: 0.243)
    static let gold = Color(red: 0.847, green: 0.706, blue: 0.416)

    /// The Flat board: cream and walnut, and the last move's squares in warm gold.
    static let lightSquare = Color(red: 0.847, green: 0.769, blue: 0.631)
    static let darkSquare = Color(red: 0.333, green: 0.212, blue: 0.141)
    static let lightMarked = Color(red: 0.776, green: 0.663, blue: 0.443)
    static let darkMarked = Color(red: 0.553, green: 0.424, blue: 0.255)

    /// A color from a hex number like 0x2FA8FF.
    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }
}

extension LiveGameAttributes {
    /// The rival's light.
    var light: Color { LiveGamePalette.color(lightHex) }
}

/// The board as the Flat view shows it, small: the Icon pieces (flat-wK…, drawn from the app's own
/// piece outlines) on cream and walnut, with the last move's two squares in gold.
struct LiveGameBoard: View {
    let fen: String
    /// Black at the bottom.
    let flipped: Bool
    /// The last move in engine notation ("g8f6"), to mark.
    var lastMove: String?
    var corner: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let square = side / 8
            let cells = DailyDiagram.cells(fen)
            let marked = Self.marked(lastMove)
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { column in
                            cell(row: row, column: column, cells: cells, marked: marked, square: square)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(LiveGamePalette.gold.opacity(0.55), lineWidth: 0.75)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private func cell(row: Int, column: Int, cells: [String?], marked: Set<Int>, square: CGFloat) -> some View {
        // Row 0 is the top of the picture: rank 8 for White at the bottom, rank 1 for Black.
        let rank = flipped ? row : 7 - row
        let file = flipped ? 7 - column : column
        let index = (7 - rank) * 8 + file
        let isLight = (rank + file) % 2 == 1
        let isMarked = marked.contains(index)
        let fill: Color = isLight
            ? (isMarked ? LiveGamePalette.lightMarked : LiveGamePalette.lightSquare)
            : (isMarked ? LiveGamePalette.darkMarked : LiveGamePalette.darkSquare)
        return ZStack {
            Rectangle().fill(fill)
            if let piece = cells[index] {
                Image("flat-" + piece)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(square * 0.03)
            }
        }
        .frame(width: square, height: square)
    }

    /// "e2e4": the places of e2 and e4 in DailyDiagram.cells' order (rank 8 first).
    static func marked(_ uci: String?) -> Set<Int> {
        guard let uci else { return [] }
        let characters = Array(uci.lowercased())
        guard characters.count >= 4 else { return [] }
        var places = Set<Int>()
        for start in [0, 2] {
            guard let letter = characters[start].asciiValue, letter >= 97, letter <= 104,
                  let rank = characters[start + 1].wholeNumberValue, (1...8).contains(rank) else { continue }
            places.insert((8 - rank) * 8 + Int(letter - 97))
        }
        return places
    }
}

/// The rival's portrait, as on the game screen: a rounded tile with a hairline in its light.
struct LiveGamePortrait: View {
    let game: LiveGameAttributes
    var size: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Image(game.portrait)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay { shape.strokeBorder(game.light.opacity(0.4), lineWidth: 0.75) }
            .accessibilityHidden(true)
    }
}

/// The clock in the game screen's grey pill, with a small label under the time.
struct LiveGameClockPill: View {
    let seconds: Int
    var label = "YOUR CLOCK"
    /// Running (your move) or waiting.
    var running = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(LiveGameAttributes.ContentState.clockText(seconds))
                .font(.app(size: 19, weight: .medium).monospacedDigit())
                .foregroundStyle(running ? LiveGamePalette.ink : LiveGamePalette.ink3)
            Text(label)
                .font(.app(size: 9, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(LiveGamePalette.ink3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(LiveGamePalette.pill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The one button: an ivory capsule that opens the game.
struct LiveGameButton: View {
    let title: String
    let url: URL
    var fill = LiveGamePalette.ivory

    var body: some View {
        Link(destination: url) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(LiveGamePalette.onIvory)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(Capsule().fill(fill))
        }
    }
}

/// The Lock Screen (and StandBy, where iOS draws it larger): the board from your side with the last
/// move marked; the rival, the opening and the clock; whose move it is and what just happened;
/// your clock; and the way back to the board.
struct LiveGameLockView: View {
    let game: LiveGameAttributes
    let state: LiveGameAttributes.ContentState

    @ScaledMetric(relativeTo: .body) private var board: CGFloat = 112

    var body: some View {
        let side = min(board, 124)
        HStack(alignment: .center, spacing: 14) {
            LiveGameBoard(fen: state.fen, flipped: !game.youAreWhite, lastMove: state.lastMoveUCI)
                .frame(width: side, height: side)
            VStack(alignment: .leading, spacing: 0) {
                who
                headline
                    .padding(.top, 6)
                Text(state.detail(rival: game.rival))
                    .font(.app(.subheadline))
                    .foregroundStyle(LiveGamePalette.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 1)
                Spacer(minLength: 6)
                HStack(spacing: 10) {
                    if let seconds = state.yourSeconds, state.result == nil {
                        LiveGameClockPill(seconds: seconds, running: state.yourMove)
                    }
                    Spacer(minLength: 0)
                    LiveGameButton(title: state.result == nil ? "Open board" : "Review", url: LiveGameLink.url)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: side)
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The rival's portrait, its name, the opening in a quieter voice, and the time control.
    private var who: some View {
        HStack(spacing: 7) {
            LiveGamePortrait(game: game, size: 20)
            Text(game.rival)
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(LiveGamePalette.ink)
            if let opening = state.opening {
                Text("· \(opening)")
                    .font(.app(.footnote))
                    .foregroundStyle(LiveGamePalette.ink2)
            }
            Spacer(minLength: 4)
            Text(game.clock)
                .font(.app(.caption).monospacedDigit())
                .foregroundStyle(LiveGamePalette.ink3)
        }
        .lineLimit(1)
    }

    /// "Your move" with a dot in the rival's light, as the game screen marks it; "Pulse is
    /// thinking"; or the result in gold.
    private var headline: some View {
        HStack(spacing: 7) {
            if state.yourMove, state.result == nil {
                Circle().fill(game.light).frame(width: 8, height: 8)
            }
            Text(state.headline(rival: game.rival))
                .font(.app(.title3, weight: .semibold))
                .foregroundStyle(state.result == nil ? LiveGamePalette.ink : LiveGamePalette.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var spoken: String {
        var words = "Your game against \(game.rival). \(state.headline(rival: game.rival)). \(state.detail(rival: game.rival))."
        if let seconds = state.yourSeconds, state.result == nil {
            words += " \(LiveGameAttributes.ContentState.clockText(seconds)) on your clock."
        }
        return words
    }
}

/// The Dynamic Island, held open: the rival on the left, your clock on the right, and under
/// them the board, what just happened, and Open.
enum LiveGameIsland {
    /// Folded up: from each rounded end of the island to the portrait or the clock.
    static let endMargin: CGFloat = 8
    /// Folded up: from the camera to the portrait or the clock. Snug, as Apple asks, with just
    /// enough room that neither touches it.
    static let cameraMargin: CGFloat = 3

    struct Leading: View {
        let game: LiveGameAttributes
        let state: LiveGameAttributes.ContentState

        var body: some View {
            HStack(spacing: 9) {
                LiveGamePortrait(game: game, size: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.rival)
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(LiveGamePalette.ink)
                    Text(state.opening.map { "\(game.clock) · \($0)" } ?? game.clock)
                        .font(.app(.caption))
                        .foregroundStyle(LiveGamePalette.ink2)
                }
                .lineLimit(1)
            }
            .padding(.leading, 2)
        }
    }

    struct Trailing: View {
        let game: LiveGameAttributes
        let state: LiveGameAttributes.ContentState

        var body: some View {
            VStack(alignment: .trailing, spacing: 0) {
                Text(state.shortStatus)
                    .font(.app(size: state.yourSeconds == nil ? 15 : 24, weight: .medium).monospacedDigit())
                    .foregroundStyle(state.yourMove ? LiveGamePalette.ink : game.light)
                if state.yourSeconds != nil, state.result == nil {
                    Text("your clock")
                        .font(.app(.caption))
                        .foregroundStyle(LiveGamePalette.ink2)
                }
            }
            .lineLimit(1)
            .padding(.trailing, 2)
        }
    }

    struct Bottom: View {
        let game: LiveGameAttributes
        let state: LiveGameAttributes.ContentState

        var body: some View {
            HStack(spacing: 12) {
                LiveGameBoard(fen: state.fen, flipped: !game.youAreWhite, lastMove: state.lastMoveUCI, corner: 5)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.headline(rival: game.rival))
                        .font(.app(.headline))
                        .foregroundStyle(state.result == nil ? LiveGamePalette.ink : LiveGamePalette.gold)
                    Text(state.detail(rival: game.rival))
                        .font(.app(.subheadline))
                        .foregroundStyle(LiveGamePalette.ink2)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                if state.yourMove || state.result != nil {
                    LiveGameButton(title: state.result == nil ? "Open" : "Review", url: LiveGameLink.url)
                }
            }
            .padding(.top, 6)
        }
    }

    /// Folded up, left of the camera: the rival's portrait.
    struct CompactLeading: View {
        let game: LiveGameAttributes

        var body: some View {
            LiveGamePortrait(game: game, size: 22)
        }
    }

    /// Folded up, right of the camera: your clock, or whose move it is. Ivory on your move, the
    /// rival's light while it thinks.
    struct CompactTrailing: View {
        let game: LiveGameAttributes
        let state: LiveGameAttributes.ContentState

        var body: some View {
            Text(state.shortStatus)
                .font(.app(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(state.yourMove ? LiveGamePalette.ink : game.light)
                .lineLimit(1)
        }
    }

    /// Sharing the island with another app: the portrait alone, ringed in the rival's light
    /// when it's your move.
    struct Minimal: View {
        let game: LiveGameAttributes
        let state: LiveGameAttributes.ContentState

        var body: some View {
            LiveGamePortrait(game: game, size: 20)
                .padding(2)
                .overlay {
                    if state.yourMove {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(game.light, lineWidth: 1.5)
                    }
                }
        }
    }
}
