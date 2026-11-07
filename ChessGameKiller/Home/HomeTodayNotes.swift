import ChessKit
import Foundation

/// Coach Leo's note at the top of Today (Alex's pick, 2026-11-07): a greeting, one line of
/// advice, and what in the player's games it comes from. The advice is aimed at the habit that
/// costs them most (CoachReport's leak) and turns between two lines for it day by day; with no
/// leak yet, a line of general wisdom for the day. Every line Leo can say here is fixed, so it
/// can be recorded in his voice (scripts/training/make_narration.py, NOTE_LINES); the counts
/// from the games stay in the written line under it.
struct HomeLeoNote: Equatable {
    /// "Good morning, Alex".
    let greeting: String
    /// Leo's advice, a line he can say.
    let line: String
    /// Where it comes from, like "You left a piece hanging twice in your last 6 games."
    let evidence: String?

    static func make(report: CoachReport?, name: String, now: Date = .now,
                     calendar: Calendar = .current) -> HomeLeoNote {
        let day: Int = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let greeting: String = greeting(name: name, hour: calendar.component(.hour, from: now))
        if let leak = report?.leak {
            let lines: [String] = advice(for: leak)
            return HomeLeoNote(greeting: greeting, line: lines[day % lines.count],
                               evidence: firstSentence(of: leak.detail))
        }
        return HomeLeoNote(greeting: greeting, line: daily[day % daily.count], evidence: nil)
    }

    static func greeting(name: String, hour: Int) -> String {
        let part: String = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        let trimmed: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? part : "\(part), \(trimmed)"
    }

    /// The first sentence of the report's detail: the part with the count from the games.
    static func firstSentence(of text: String) -> String {
        guard let end = text.range(of: ". ") else { return text }
        return String(text[..<end.lowerBound]) + "."
    }

    // MARK: What Leo says

    static func advice(for leak: CoachReport.Leak) -> [String] {
        switch leak.area {
        case .safety:
            switch leak.headline {
            case "Missed threats": return threats
            case "Walking into forks": return forks
            default: return loosePieces
            }
        case .tactics: return tactics
        case .checkmates: return checkmates
        case .openings: return openings
        case .endgames: return endgames
        case .calculation: return calculation
        }
    }

    static let loosePieces = [
        "Before you let go of a piece, ask one question: can they take it for free?",
        "Count the guards. If a piece has more attackers than defenders, it needs help.",
    ]
    static let threats = [
        "After every move they make, ask what it attacks. Then make yours.",
        "Their last move is a message. Read it before you answer.",
    ]
    static let forks = [
        "Before you move, check every square their knights and queen can reach.",
        "Two of your pieces a knight's jump apart is an invitation. Don't send it.",
    ]
    static let tactics = [
        "Checks, captures, attacks. Look for all three before anything else.",
        "When something on their side feels loose, look harder. That's where the tactic is.",
    ]
    static let checkmates = [
        "When their king is short of squares, look at every check. One of them may end it.",
        "Count their king's escape squares. When there are none left, a check is mate.",
    ]
    static let openings = [
        "Center, develop, castle. Do those three before anything clever.",
        "Move each piece once in the opening, and get your king safe early.",
    ]
    static let endgames = [
        "In the endgame, the king is a fighter. Bring him forward.",
        "Rooks belong behind passed pawns, yours or theirs.",
    ]
    static let calculation = [
        "Name two or three candidate moves before you choose one.",
        "Before you play, picture the board after your move. Then find their best reply.",
    ]
    /// For a day with no habit to work on: a little wisdom, a different line each day.
    static let daily = [
        "If you see a good move, look for a better one.",
        "Ask what your opponent wants before you ask what you want.",
        "Every piece should have a job. Find the one that doesn't, and give it one.",
        "When you're ahead, trade pieces. When you're behind, keep them on.",
        "A knight on the rim is dim. Bring it toward the center.",
        "Rooks love open files. Find one, and put a rook on it.",
        "When you're winning, don't hurry. Make it safe, then make it count.",
        "Sit on your hands for a moment. The first move you see is rarely the best.",
    ]

    /// Every line Leo can say on Today, for recording.
    static var allLines: [String] {
        loosePieces + threats + forks + tactics + checkmates + openings + endgames + calculation + daily
    }
}

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
