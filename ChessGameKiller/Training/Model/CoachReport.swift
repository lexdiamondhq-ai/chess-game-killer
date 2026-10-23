import Foundation

/// What's costing the player games: Coach Leo reads their recent saved games (every
/// move the engine graded, and the pattern behind each costly one) and sorts the
/// mistakes into six areas, then names the one leak worth fixing first and the
/// training that fixes it. Pure data in, so it's easy to test.
struct CoachReport: Equatable {
    enum Area: String, CaseIterable, Identifiable {
        /// Leaving pieces loose, walking into forks and mates: the red and green lights.
        case safety
        /// Missing forks, pins, skewers and free pieces: the yellow light.
        case tactics
        case checkmates
        case openings
        case endgames
        /// Everything else in the middlegame: choosing between moves and seeing far enough.
        case calculation

        var id: String { rawValue }

        var title: String {
            switch self {
            case .safety: return "Safety"
            case .tactics: return "Tactics"
            case .checkmates: return "Checkmates"
            case .openings: return "Openings"
            case .endgames: return "Endgames"
            case .calculation: return "Calculation"
            }
        }

        var symbol: String {
            switch self {
            case .safety: return "checkmark.shield.fill"
            case .tactics: return "arrow.triangle.branch"
            case .checkmates: return "crown.fill"
            case .openings: return "book.closed.fill"
            case .endgames: return "flag.checkered"
            case .calculation: return "brain.head.profile"
            }
        }
    }

    /// How one area went in the games read.
    struct Score: Equatable, Identifiable {
        let area: Area
        /// From 0 to 1, higher is better. Nil until there are enough moves to judge.
        let value: Double?
        /// Costly moves in this area.
        let mistakes: Int
        /// The player's moves this area was judged on.
        let moves: Int
        /// Games that reached this area (an endgame, say) and were judged on it.
        let games: Int

        var id: String { area.rawValue }

        /// A word for the bar: "Strong", "Solid", "Shaky" or "Needs work".
        var verdict: String {
            guard let value else { return "Not enough yet" }
            switch value {
            case 0.85...: return "Strong"
            case 0.7..<0.85: return "Solid"
            case 0.5..<0.7: return "Shaky"
            default: return "Needs work"
            }
        }
    }

    /// The one thing to work on first, and the training that fixes it.
    struct Leak: Equatable {
        let area: Area
        /// Like "Loose pieces".
        let headline: String
        /// One or two sentences in Leo's words, with the count from the games.
        let detail: String
        /// The Coach Leo skill whose practice fixes it, when there is one.
        let skill: String?
        /// The button's words, like "Practice safe moves".
        let action: String
    }

    let gamesRead: Int
    let scores: [Score]
    let leak: Leak?

    /// Games read, newest first.
    static let gameLimit = 20
    /// Fewer player moves than this in an area and it isn't judged yet.
    static let minimumMoves = 10
    /// A game counts toward an area once the player made this many moves in it.
    static let movesToCount = 3
    /// Moves up to this ply count as the opening (the first 12 moves each).
    static let openingPlies = 24
    /// Costly-move weight per game that takes a score from 1 down to about 0.37
    /// (a blunder a game, say): about 0.85 is Strong, 0.5 Shaky.
    static let softness = 3.0

    var hasEnough: Bool { scores.contains { $0.value != nil } }

    // MARK: Reading the games

    /// Reads games against the computer only: against a friend both sides' moves are
    /// saved, and Leo can't tell which were the player's.
    static func make(games: [SavedGame]) -> CoachReport {
        let recent = Array(games.filter { $0.level != nil }.sorted { $0.date > $1.date }.prefix(gameLimit))
        var weighted: [Area: Double] = [:]
        var counts: [Area: Int] = [:]
        var moves: [Area: Int] = [:]
        var gamesSeen: [Area: Int] = [:]
        var kinds: [CoachMoment.Kind: Int] = [:]

        for game in recent {
            var inGame: [Area: Int] = [:]
            for moment in game.playerMoments {
                let phase = Phase.of(moment)
                for area in Area.allCases where phase.counts(for: area) {
                    inGame[area, default: 0] += 1
                }
                guard let weight = weight(of: moment.moveGrade) else { continue }
                let found = MomentFinder.find(in: moment.review)
                if let kind = found?.kind, !kind.isPraise {
                    kinds[kind, default: 0] += 1
                }
                let area = area(for: found?.kind, phase: phase)
                weighted[area, default: 0] += weight
                counts[area, default: 0] += 1
            }
            for (area, count) in inGame {
                moves[area, default: 0] += count
                if count >= movesToCount { gamesSeen[area, default: 0] += 1 }
            }
        }

        let scores = Area.allCases.map { area -> Score in
            let judgedGames = gamesSeen[area] ?? 0
            let judgedMoves = moves[area] ?? 0
            var value: Double?
            if judgedGames >= 1, judgedMoves >= minimumMoves {
                let perGame = (weighted[area] ?? 0) / Double(judgedGames)
                value = exp(-perGame / softness)
            }
            return Score(area: area, value: value, mistakes: counts[area] ?? 0, moves: judgedMoves, games: judgedGames)
        }
        return CoachReport(gamesRead: recent.count, scores: scores,
                           leak: leak(scores: scores, kinds: kinds, games: recent.count))
    }

    /// How much a costly move counts: a blunder three times an inaccuracy. Nil for good moves.
    static func weight(of grade: MoveReview.Grade) -> Double? {
        switch grade {
        case .blunder: return 3
        case .mistake: return 2
        case .inaccuracy: return 1
        default: return nil
        }
    }

    /// Where a costly move belongs: by the pattern behind it when Leo can name one,
    /// otherwise by the phase of the game it was played in.
    static func area(for kind: CoachMoment.Kind?, phase: Phase) -> Area {
        switch kind {
        case .hungPiece, .allowedFork, .allowedMate: return .safety
        case .missedFreePiece, .missedFork, .missedPin, .missedSkewer: return .tactics
        case .missedMate: return .checkmates
        case .earlyQueen: return .openings
        default:
            switch phase {
            case .opening: return .openings
            case .endgame: return .endgames
            case .middlegame: return .calculation
            }
        }
    }

    // MARK: The leak

    private static func leak(scores: [Score], kinds: [CoachMoment.Kind: Int], games: Int) -> Leak? {
        // The weakest judged area with real mistakes in it.
        let judged = scores.filter { $0.value != nil && $0.mistakes >= 2 }
        guard let worst = judged.min(by: { a, b in
            if abs((a.value ?? 1) - (b.value ?? 1)) > 0.02 { return (a.value ?? 1) < (b.value ?? 1) }
            return a.mistakes > b.mistakes
        }), (worst.value ?? 1) < 0.9 else {
            return nil
        }
        let inGames = games == 1 ? "in your last game" : "in your last \(games) games"
        func times(_ n: Int) -> String { n == 1 ? "once" : (n == 2 ? "twice" : "\(n) times") }

        switch worst.area {
        case .safety:
            let hung = kinds[.hungPiece] ?? 0
            let forks = kinds[.allowedFork] ?? 0
            let mates = kinds[.allowedMate] ?? 0
            if hung >= forks, hung >= mates, hung > 0 {
                return Leak(area: .safety, headline: "Loose pieces",
                            detail: "You left a piece hanging \(times(hung)) \(inGames). Before you let go of a piece, ask: can they take it for free?",
                            skill: "safety", action: "Practice safe moves")
            }
            if mates > forks {
                return Leak(area: .safety, headline: "Missed threats",
                            detail: "A mate threat slipped past you \(times(mates)) \(inGames). After every move they make, ask what it attacks.",
                            skill: "threats", action: "Practice spotting threats")
            }
            return Leak(area: .safety, headline: "Walking into forks",
                        detail: "You walked into a fork \(times(max(forks, 1))) \(inGames). Check every square their knights and queen can reach before you move.",
                        skill: "threats", action: "Practice spotting threats")
        case .tactics:
            let missed: [(CoachMoment.Kind, String, String, String)] = [
                (.missedFork, "Missed forks", "forks", "a fork"),
                (.missedFreePiece, "Free pieces left on the board", "free-pieces", "a free piece"),
                (.missedPin, "Missed pins", "pins", "a pin"),
                (.missedSkewer, "Missed skewers", "skewers", "a skewer"),
            ]
            let top = missed.max { (kinds[$0.0] ?? 0) < (kinds[$1.0] ?? 0) }
            if let top, let count = kinds[top.0], count > 0 {
                return Leak(area: .tactics, headline: top.1,
                            detail: "You had \(top.3) and missed it \(times(count)) \(inGames). Look for checks, captures and attacks before anything else.",
                            skill: top.2, action: "Practice \(practiceName(top.2))")
            }
            return Leak(area: .tactics, headline: "Tactics slipping by",
                        detail: "Chances to win material went by \(times(worst.mistakes)) \(inGames).",
                        skill: "forks", action: "Practice forks")
        case .checkmates:
            let count = max(kinds[.missedMate] ?? 0, worst.mistakes)
            return Leak(area: .checkmates, headline: "Missed checkmates",
                        detail: "You had a mate on the board and missed it \(times(count)) \(inGames). When their king is short of squares, look at every check.",
                        skill: "mate-in-2", action: "Practice mates")
        case .openings:
            return Leak(area: .openings, headline: "Shaky starts",
                        detail: "\(worst.mistakes) costly moves came in the first 12 moves \(inGames). Center, develop, castle: then build a repertoire you trust.",
                        skill: "opening", action: "Practice the opening rules")
        case .endgames:
            return Leak(area: .endgames, headline: "Endgames getting away",
                        detail: "\(worst.mistakes) costly moves came in the endgame \(inGames). The essential endgames turn those into wins.",
                        skill: nil, action: "Train endgames")
        case .calculation:
            return Leak(area: .calculation, headline: "Middlegame decisions",
                        detail: "\(worst.mistakes) costly moves came in the middlegame with no single pattern behind them. List two or three candidate moves before you choose.",
                        skill: nil, action: "Train calculation")
        }
    }

    private static func practiceName(_ skill: String) -> String {
        switch skill {
        case "free-pieces": return "free pieces"
        default: return skill
        }
    }

    // MARK: Phases

    /// The phase a move was played in: the first 12 moves are the opening; few pieces
    /// left is the endgame; the rest is the middlegame.
    enum Phase: Equatable {
        case opening, middlegame, endgame

        static func of(_ moment: SavedMoment) -> Phase {
            if isEndgame(fen: moment.fenBefore) { return .endgame }
            return moment.ply <= CoachReport.openingPlies ? .opening : .middlegame
        }

        /// Queens off with little left, or very little material at all.
        static func isEndgame(fen: String) -> Bool {
            let board = fen.split(separator: " ").first.map(String.init) ?? ""
            var queens = 0
            var material = 0
            for char in board {
                switch char.lowercased() {
                case "q": queens += 1; material += 9
                case "r": material += 5
                case "b", "n": material += 3
                default: break
                }
            }
            // Both sides together: a rook and minor piece each, or less, is an endgame.
            return material <= 16 || (queens == 0 && material <= 26)
        }

        func counts(for area: Area) -> Bool {
            switch area {
            case .openings: return self == .opening
            case .endgames: return self == .endgame
            case .calculation: return self == .middlegame
            case .safety, .tactics, .checkmates: return true
            }
        }
    }
}
