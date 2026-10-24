import ChessKit
import SwiftUI

/// "How people play here": the moves masters, or players at your level, choose in the
/// position on the board, how often, and how each one scored. Counted from the Lichess
/// databases and shipped with the app (see OpeningStats).
struct OpeningStatsPanel: View {
    /// The position on the board.
    let fen: String
    /// The line's next move here, marked in the list. Nil when the line is over.
    let lineMove: String?
    let theme: BoardTheme
    var stats: OpeningStats = .shared
    @Environment(PuzzleStore.self) private var puzzles: PuzzleStore?
    /// "m" for masters, "level" for players at the chosen band.
    @AppStorage("openingStats.book") private var bookCode = "m"
    /// The chosen band, or -1 to follow the player's puzzle rating.
    @AppStorage("openingStats.band") private var bandCode = -1

    private var band: OpeningStats.Band {
        if let chosen = OpeningStats.Band(rawValue: bandCode) { return chosen }
        return OpeningStats.Band.forPuzzleRating(puzzles?.progress.rating ?? 1300)
    }

    /// "Your level" is Premium's; free players see the masters.
    private var levelOpen: Bool { Premium.shared.opens(.masterGames) }
    @State private var offer: PremiumFeature?

    private var book: OpeningStats.Book { bookCode == "m" || !levelOpen ? .masters : .band(band) }

    private var mover: Piece.Color { TrainingChess.sideToMove(fen) ?? .white }

    /// The line's move, when it fits this position (not for a moment after a wrong move).
    private var marked: String? {
        guard let lineMove, Notation.san(of: lineMove, fen: fen) != nil else { return nil }
        return lineMove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let entry = stats.entry(fen: fen, book: book) {
                VStack(spacing: 6) {
                    ForEach(entry.moves.prefix(4), id: \.uci) { move in
                        OpeningStatsRow(move: move, total: entry.total, fen: fen, mover: mover,
                                        isLine: move.uci == marked, theme: theme)
                    }
                }
                Text(footnote(entry))
                    .font(.system(.caption2, design: .themed))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(stats.isEmpty ? "Game statistics come with the next content update."
                     : "Too few \(book == .masters ? "master games" : "games at this level") reached this position to count.")
                    .font(.system(.footnote, design: .themed))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .trainingCard(theme)
        .onChange(of: bookCode) { _, code in
            if code != "m", !levelOpen {
                bookCode = "m"
                offer = .masterGames
            }
        }
        .premiumOffer($offer)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("HOW PEOPLE PLAY HERE")
                    .font(.system(.caption2, design: .themed).weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(theme.trainingAccent)
                Spacer(minLength: 4)
                if bookCode != "m", levelOpen {
                    bandMenu
                }
            }
            Picker("Whose games", selection: $bookCode) {
                Text("Masters").tag("m")
                Text("Your level").tag("level")
            }
            .pickerStyle(.segmented)
        }
    }

    private var bandMenu: some View {
        Menu {
            ForEach(OpeningStats.Band.allCases) { option in
                Button("Players \(option.range)") { bandCode = option.rawValue }
            }
        } label: {
            HStack(spacing: 3) {
                Text("Players \(band.range)")
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.system(.caption, design: .themed).weight(.semibold))
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Rating band: players \(band.range)")
    }

    private func footnote(_ entry: OpeningStats.Entry) -> String {
        let games = entry.total.formatted()
        let whose = book == .masters ? "\(games) games between players rated 2400+" : "\(games) Lichess games, players \(band.range)"
        guard let lineMove = marked else { return whose + "." }
        let share = entry.share(of: lineMove)
        let san = Notation.san(of: lineMove, fen: fen) ?? lineMove
        if share == 0 {
            return whose + ". This line's move, \(san), is rare here."
        }
        let top = entry.moves.first?.uci == lineMove
        return whose + (top ? ". \(san) is the most played move." : ". \(san) is played \(Int((share * 100).rounded()))% of the time.")
    }
}

/// One move: its notation, how often it's played, and a white–draw–black result bar.
private struct OpeningStatsRow: View {
    let move: OpeningStats.Move
    let total: Int
    let fen: String
    let mover: Piece.Color
    let isLine: Bool
    let theme: BoardTheme

    var body: some View {
        let san: String = Notation.san(of: move.uci, fen: fen) ?? move.uci
        let share: Int = total == 0 ? 0 : Int((Double(move.games) / Double(total) * 100).rounded())
        let score: Int = Int((move.score(for: mover) * 100).rounded())
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text(san)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                if isLine {
                    Circle()
                        .fill(theme.trainingAccent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 70, alignment: .leading)
            Text("\(share)%")
                .font(.system(.caption, design: .themed).weight(.semibold).monospacedDigit())
                .frame(width: 38, alignment: .trailing)
            ResultBar(white: move.whiteShare, draw: move.drawShare)
                .frame(height: 8)
            Text("\(score)")
                .font(.system(.caption2, design: .themed).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(san)\(isLine ? ", this line's move" : ""): played \(share) percent, scores \(score) percent for \(mover.displayName)")
    }
}

/// White wins, draws and black wins, left to right.
private struct ResultBar: View {
    let white: Double
    let draw: Double

    var body: some View {
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            let whiteWidth: CGFloat = width * CGFloat(white)
            let drawWidth: CGFloat = width * CGFloat(draw)
            HStack(spacing: 0) {
                Rectangle().fill(Color(white: 0.92)).frame(width: whiteWidth)
                Rectangle().fill(Color(white: 0.55)).frame(width: drawWidth)
                Rectangle().fill(Color(white: 0.16))
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }
}

/// Master games that went down this line, to play through in Guess the Move.
struct OpeningModelGames: View {
    let games: [ClassicGame]
    let theme: BoardTheme
    let onPick: (ClassicGame) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrainSectionTitle(text: "Masters who played this line")
            GuessGameRows(games: games, theme: theme, onPick: onPick)
        }
    }
}
