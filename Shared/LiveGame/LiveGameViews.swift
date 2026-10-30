import SwiftUI

// The game's faces on the Lock Screen and in the Dynamic Island. Compiled into the app too, so
// the app's tests can draw them; the widget extension puts them in ActivityKit's frames
// (ChessGameKillerWidget/LiveGameWidget.swift). SwiftUI and Foundation only.

/// The colors: the home's espresso and ivory ink, and the rival's own light.
enum LiveGamePalette {
    /// Behind the Lock Screen's card: the home's dark, a little see-through.
    static let background = Color(red: 0.086, green: 0.063, blue: 0.047)
    static let ink = Color(red: 0.965, green: 0.945, blue: 0.91)
    static let ink2 = ink.opacity(0.72)
    static let ivory = Color(red: 0.957, green: 0.929, blue: 0.875)
    static let onIvory = Color(red: 0.082, green: 0.067, blue: 0.047)

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

/// The rival's glowing portrait, as light with no backdrop, so it sits on black or on glass.
struct LiveGameOrb: View {
    let game: LiveGameAttributes
    var size: CGFloat = 20

    var body: some View {
        Image(game.glow)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The Lock Screen (and StandBy, where iOS draws it larger): the board from your side, the
/// rival and the opening, what just happened, your clock, and the way back to the board.
struct LiveGameLockView: View {
    let game: LiveGameAttributes
    let state: LiveGameAttributes.ContentState

    @ScaledMetric(relativeTo: .body) private var board: CGFloat = 104

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            DailyDiagram(fen: state.fen, flipped: !game.youAreWhite)
                .frame(width: min(board, 124), height: min(board, 124))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                who
                Text(state.headline(rival: game.rival))
                    .font(.app(.title3, weight: .semibold))
                    .foregroundStyle(LiveGamePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.top, 5)
                Text(state.detail(rival: game.rival))
                    .font(.app(.subheadline).monospacedDigit())
                    .foregroundStyle(LiveGamePalette.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 1)
                Spacer(minLength: 8)
                Text(state.result == nil ? "Open board" : "See the game")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(LiveGamePalette.onIvory)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(Capsule().fill(LiveGamePalette.ivory))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: min(board, 124))
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// The rival's light, its name, and the opening (or the clock) in a quieter voice.
    private var who: some View {
        HStack(spacing: 6) {
            LiveGameOrb(game: game, size: 20)
            Text(game.rival)
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(LiveGamePalette.ink)
            Text("· \(state.opening ?? game.clock)")
                .font(.app(.footnote))
                .foregroundStyle(LiveGamePalette.ink2)
                .lineLimit(1)
        }
    }

    private var spoken: String {
        "Your game against \(game.rival). \(state.headline(rival: game.rival)). \(state.detail(rival: game.rival))."
    }
}

/// The Dynamic Island, held open: the rival on the left, your clock on the right, and under
/// them the board and what just happened.
enum LiveGameIsland {
    struct Leading: View {
        let game: LiveGameAttributes

        var body: some View {
            HStack(spacing: 8) {
                LiveGameOrb(game: game, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(game.rival)
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(LiveGamePalette.ink)
                    Text(game.clock)
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
                    .font(.app(size: state.yourSeconds == nil ? 15 : 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(game.light)
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
                DailyDiagram(fen: state.fen, flipped: !game.youAreWhite)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.headline(rival: game.rival))
                        .font(.app(.headline))
                        .foregroundStyle(LiveGamePalette.ink)
                    Text(state.opening ?? "Move \(state.moveNumber)")
                        .font(.app(.subheadline))
                        .foregroundStyle(LiveGamePalette.ink2)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
    }

    /// Folded up, left of the camera: the rival's light.
    struct CompactLeading: View {
        let game: LiveGameAttributes

        var body: some View {
            LiveGameOrb(game: game, size: 22)
        }
    }

    /// Folded up, right of the camera: your clock, or whose move it is, in the rival's light.
    struct CompactTrailing: View {
        let game: LiveGameAttributes
        let state: LiveGameAttributes.ContentState

        var body: some View {
            Text(state.shortStatus)
                .font(.app(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(game.light)
                .lineLimit(1)
        }
    }
}
