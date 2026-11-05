import ActivityKit
import SwiftUI

// Today's Move on the Lock Screen and in the Dynamic Island, until it's solved: the puzzle on the
// Flat board, your streak, the time until a new one, and Solve. The app starts it while today's
// move is still open and no game is on the Lock Screen, and ends it once the move is done
// (DailyActivityKeeper). Compiled into both the app and the widget extension.

/// What stays the same all day: the puzzle.
struct DailyActivityAttributes: ActivityAttributes, Equatable {
    /// Counted from 1 on October 1, 2026.
    var number: Int
    /// The position the solver sees.
    var fen: String
    var solverIsWhite: Bool
    /// "Mate in 2", "Find the win".
    var title: String
    /// "White to play".
    var side: String
    /// The next midnight, when a new move arrives.
    var resets: Date

    struct ContentState: Codable, Hashable {
        /// Days in a row, counting today once it's done.
        var streak: Int
    }

    /// Opens Today's Move.
    static let link = URL(string: "chessgamekiller://daily")!
}

extension DailyActivityAttributes {
    init(puzzle: DailyPuzzle, resets: Date) {
        let words = ["zero", "one", "two", "three", "four", "five"]
        let title: String
        if let mate = puzzle.mateIn {
            title = mate == 1 ? "Mate in one" : "Mate in \(words[mate])"
        } else {
            title = "Find the win"
        }
        self.init(number: puzzle.number, fen: puzzle.shownFEN, solverIsWhite: puzzle.solverIsWhite,
                  title: title, side: puzzle.solverIsWhite ? "White to play" : "Black to play", resets: resets)
    }
}

/// The streak's flame and count, in gold.
struct DailyActivityStreak: View {
    let streak: Int
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: size, weight: .semibold))
            Text("\(streak)")
                .font(.app(size: size + 1, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(LiveGamePalette.gold)
    }
}

/// The Lock Screen card.
struct DailyActivityLockView: View {
    let puzzle: DailyActivityAttributes
    let state: DailyActivityAttributes.ContentState

    @ScaledMetric(relativeTo: .body) private var board: CGFloat = 112

    var body: some View {
        let side = min(board, 124)
        HStack(alignment: .center, spacing: 14) {
            LiveGameBoard(fen: puzzle.fen, flipped: !puzzle.solverIsWhite)
                .frame(width: side, height: side)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("Today's Move")
                        .font(.app(.footnote, weight: .semibold))
                        .foregroundStyle(LiveGamePalette.gold)
                    Spacer(minLength: 4)
                    if state.streak > 0 { DailyActivityStreak(streak: state.streak) }
                }
                Text(puzzle.title)
                    .font(.app(.title3, weight: .semibold))
                    .foregroundStyle(LiveGamePalette.ink)
                    .lineLimit(1)
                    .padding(.top, 6)
                Text(state.streak > 0 ? "\(puzzle.side) · keep your streak" : puzzle.side)
                    .font(.app(.subheadline))
                    .foregroundStyle(LiveGamePalette.ink2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 1)
                Spacer(minLength: 6)
                HStack(spacing: 10) {
                    countdown
                    Spacer(minLength: 0)
                    LiveGameButton(title: "Solve", url: DailyActivityAttributes.link, fill: LiveGamePalette.gold)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: side)
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    /// The time until a new move, counting down on its own.
    private var countdown: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(timerInterval: Date.now...max(puzzle.resets, Date.now), countsDown: true)
                .font(.app(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(LiveGamePalette.ink2)
                .frame(maxWidth: 76, alignment: .leading)
            Text("NEW MOVE IN")
                .font(.app(size: 9, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(LiveGamePalette.ink3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(LiveGamePalette.pill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The Dynamic Island.
enum DailyActivityIsland {
    struct Leading: View {
        let puzzle: DailyActivityAttributes

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today's Move")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(LiveGamePalette.gold)
                Text(puzzle.side)
                    .font(.app(.caption))
                    .foregroundStyle(LiveGamePalette.ink2)
            }
            .lineLimit(1)
            .padding(.leading, 4)
        }
    }

    struct Trailing: View {
        let state: DailyActivityAttributes.ContentState

        var body: some View {
            DailyActivityStreak(streak: state.streak, size: 17)
                .padding(.trailing, 4)
        }
    }

    struct Bottom: View {
        let puzzle: DailyActivityAttributes

        var body: some View {
            HStack(spacing: 12) {
                LiveGameBoard(fen: puzzle.fen, flipped: !puzzle.solverIsWhite, corner: 5)
                    .frame(width: 64, height: 64)
                Text(puzzle.title)
                    .font(.app(.headline))
                    .foregroundStyle(LiveGamePalette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LiveGameButton(title: "Solve", url: DailyActivityAttributes.link, fill: LiveGamePalette.gold)
            }
            .padding(.top, 6)
        }
    }

    /// Folded up, left of the camera: the flame.
    struct CompactLeading: View {
        var body: some View {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LiveGamePalette.gold)
        }
    }

    /// Folded up, right of the camera: the streak.
    struct CompactTrailing: View {
        let state: DailyActivityAttributes.ContentState

        var body: some View {
            Text("\(state.streak)")
                .font(.app(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(LiveGamePalette.gold)
        }
    }
}
