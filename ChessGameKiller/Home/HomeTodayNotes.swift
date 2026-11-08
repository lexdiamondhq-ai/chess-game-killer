import ChessKit
import Foundation

/// The player's finest move of the last seven days (Alex's pick, 2026-11-07), hung in a gold frame
/// on Today: a mate, or the strong move that gained the most, from games against the rivals.
struct HomeFinestMove: Equatable {
    let gameID: UUID
    /// The position before the move, and the move, drawn as an arrow over it.
    let fen: String
    let uci: String
    /// "18. Rxf7!".
    let move: String
    /// "Against the Hunter, Tuesday. Stockfish's top choice, and you won."
    let detail: String
    /// The player had Black: the board turns round.
    let flipped: Bool

    /// The best of the week, or nil when no game in it had a move to be proud of.
    static func pick(games: [SavedGame], now: Date = .now, calendar: Calendar = .current) -> HomeFinestMove? {
        let start: Date = now.addingTimeInterval(-7 * 24 * 3600)
        var top: (game: SavedGame, moment: SavedMoment, score: Double)?
        for game in games where game.level != nil && game.date >= start && game.date <= now {
            let gains: [Int: Double] = gains(in: game)
            for moment in game.highlights {
                // A mate beats any other move; between two of a kind, the bigger swing, then the newer.
                let score: Double = moment.moveGrade == .checkmate ? 10 : (gains[moment.ply] ?? 0)
                if let current = top,
                   score < current.score || (score == current.score && game.date <= current.game.date) {
                    continue
                }
                top = (game, moment, score)
            }
        }
        guard let best = top else { return nil }
        let moment: SavedMoment = best.moment
        let mate: Bool = moment.moveGrade == .checkmate
        let move: String = mate || moment.san.hasSuffix("!") ? moment.numbered : moment.numbered + "!"
        return HomeFinestMove(gameID: best.game.id, fen: moment.fenBefore, uci: moment.uci, move: move,
                              detail: detail(game: best.game, moment: moment, now: now, calendar: calendar),
                              flipped: !best.game.playerIsWhite)
    }

    /// How much each of the player's moves gained since their move before, by ply.
    private static func gains(in game: SavedGame) -> [Int: Double] {
        var previous: Double = 0
        var out: [Int: Double] = [:]
        for moment in game.playerMoments {
            out[moment.ply] = moment.after - previous
            previous = moment.after
        }
        return out
    }

    static func detail(game: SavedGame, moment: SavedMoment, now: Date, calendar: Calendar) -> String {
        var who: String = game.opponent
        if who.hasPrefix("The ") { who = "the " + who.dropFirst(4) }
        let first: String = "Against \(who), \(when(game.date, now: now, calendar: calendar))."
        let won: Bool = game.result == .win
        let second: String
        switch moment.moveGrade {
        case .checkmate: second = "Checkmate."
        case .best: second = won ? "Stockfish's top choice, and you won." : "Stockfish's top choice."
        default: second = won ? "An excellent move, and you won." : "An excellent move."
        }
        return first + " " + second
    }

    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "yesterday" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    /// The move's two squares as columns 0-7 from a and rows 0-7 from rank 1.
    var squares: (from: (file: Int, rank: Int), to: (file: Int, rank: Int))? {
        let chars: [Character] = Array(uci)
        guard chars.count >= 4,
              let f1 = chars[0].asciiValue, let r1 = chars[1].wholeNumberValue,
              let f2 = chars[2].asciiValue, let r2 = chars[3].wholeNumberValue,
              let a = Character("a").asciiValue else { return nil }
        let from = (file: Int(f1) - Int(a), rank: r1 - 1)
        let to = (file: Int(f2) - Int(a), rank: r2 - 1)
        guard (0..<8).contains(from.file), (0..<8).contains(from.rank),
              (0..<8).contains(to.file), (0..<8).contains(to.rank) else { return nil }
        return (from, to)
    }
}
