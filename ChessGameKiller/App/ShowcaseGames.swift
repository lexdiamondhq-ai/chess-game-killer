import ChessKit
import Foundation

/// A player with eleven finished games, for the tap tests and CI's pictures of Chess DNA
/// (`-showcaseDNA YES`): attacking wins as White, the older ones with a slip or two, and three
/// quiet games as Black. Enough for a style, a strength with games to show and something to
/// work on. Kept in memory and never saved; a normal launch never passes it.
/// `-showcaseMistakes YES` saves the slips as positions to fix as well.
/// `-showcaseFull YES` is the same player with more to show: the knight fork on f7 was the best
/// move every time, and the older games went wrong from the opening on. That gives a strength
/// with moves to show and puzzles behind it (Forks), and a second thing to work on, in the
/// middlegame, so every kind of row on Chess DNA is there to tap.
extension Showcase {
    @MainActor
    static func vault(_ defaults: UserDefaults = .standard) -> GameVault? {
        guard asked("showcaseDNA", defaults) else { return nil }
        let full = asked("showcaseFull", defaults)
        let clean: [Int: MoveReview.Grade] = full ? [11: .best] : [:]
        // The fuller player's slips are heavy enough to sit behind real players in the opening
        // and level with them in the middlegame (`RealPlayers`), so both are listed to work on.
        let slip: [Int: MoveReview.Grade] = full
            ? [11: .best, 17: .blunder, 19: .blunder, 21: .mistake, 23: .mistake,
               25: .blunder, 27: .blunder, 29: .blunder, 31: .blunder]
            : [21: .mistake, 25: .blunder]
        var games: [SavedGame] = []
        for day in 0..<8 {
            games.append(game(friedLiver, white: true, result: day == 1 || day == 6 ? .loss : .win,
                              accuracy: day < 4 ? 86 : 71, daysAgo: Double(day * 2), grades: day < 4 ? clean : slip))
        }
        for day in 0..<3 {
            games.append(game(quietLondon, white: false, result: day == 0 ? .draw : .loss, accuracy: 78,
                              daysAgo: Double(day * 2 + 1), grades: [:]))
        }
        return GameVault(games: games.sorted { $0.date > $1.date })
    }

    /// The same player's training with the slips from those games saved to fix
    /// (`-showcaseMistakes YES`, with `-showcaseDNA YES`), so "Fix your mistakes" and practice
    /// from the player's own positions have something to open. Kept in memory and never saved.
    @MainActor
    static func training(_ defaults: UserDefaults = .standard) -> TrainingStore? {
        guard asked("showcaseMistakes", defaults), let sample = vault(defaults) else { return nil }
        var progress = TrainingProgress()
        var saved = Set<String>()
        for game in sample.games {
            for moment in game.moments {
                guard let grade = MoveReview.Grade(rawValue: moment.grade), CoachReport.weight(of: grade) != nil,
                      saved.insert(moment.fenBefore).inserted else { continue }
                // Castling was there to play in both slips, and either one is a calmer move.
                progress.mistakes.append(GameMistake(id: "showcase-\(saved.count)", fen: moment.fenBefore, best: "e1g1",
                                                     played: moment.uci, skill: "", title: "",
                                                     created: game.date, due: game.date))
            }
        }
        return TrainingStore(library: TrainingLibrary.shared, progress: progress)
    }

    /// A YES launch argument. Arguments arrive as text, which a Bool setting won't read.
    private static func asked(_ key: String, _ defaults: UserDefaults) -> Bool {
        guard let text = defaults.string(forKey: key)?.lowercased() else { return false }
        return ["yes", "true", "1"].contains(text)
    }

    /// The Fried Liver: a knight given up on f7 for an attack on the king, checks all the way.
    private static let friedLiver = "e2e4 e7e5 g1f3 b8c6 f1c4 g8f6 f3g5 d7d5 e4d5 f6d5 g5f7 e8f7 d1f3 f7e6 b1c3 c6b4 f3e4 c7c6 a2a3 b4a6 d2d4 a6c7 c1f4 e6f7 f4e5 c8e6 c3d5 c6d5 c4d5 e6d5 e4f5 f7e8"
    /// A London System, castled early, then rooks shuffling: no checks, no captures.
    private static let quietLondon = "d2d4 d7d5 g1f3 g8f6 c1f4 e7e6 e2e3 f8e7 f1d3 e8g8 e1g1 c7c5 c2c3 b8c6 b1d2 b7b6 d1e2 c8b7 h2h3 a8c8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8 f1e1 f8e8 e1f1 e8f8"

    /// A game played out from the start in engine notation. The player's moves are graded good
    /// unless `grades` says otherwise, by ply.
    private static func game(_ line: String, white: Bool, result: SavedGame.Result, accuracy: Int,
                             daysAgo: Double, grades: [Int: MoveReview.Grade]) -> SavedGame {
        var fen = Position.standard.fen
        var positions = [fen]
        var moves: [String] = []
        var moments: [SavedMoment] = []
        for (offset, uci) in line.split(separator: " ").map(String.init).enumerated() {
            guard let san = Notation.san(of: uci, fen: fen),
                  let next = TrainingChess.fen(after: [uci], from: fen) else { break }
            let byWhite = offset % 2 == 0
            if byWhite == white {
                let grade = grades[offset + 1] ?? .good
                let bad = CoachReport.weight(of: grade) != nil
                moments.append(SavedMoment(ply: offset + 1, grade: grade.rawValue, san: san, uci: uci, byWhite: byWhite,
                                           fenBefore: fen, fenAfter: next, before: 0.1, after: bad ? -0.3 : 0.1))
            }
            moves.append(san)
            positions.append(next)
            fen = next
        }
        return SavedGame(id: UUID(), date: Date().addingTimeInterval(-daysAgo * 86_400 - 60), opponent: "Drift",
                         level: 2, playerIsWhite: white, result: result, accuracy: accuracy,
                         positions: positions, moves: moves, moments: moments)
    }
}
