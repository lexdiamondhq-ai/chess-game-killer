import Foundation

/// What's costing the player games: Coach Leo reads their recent saved games (every
/// move the engine graded, and the pattern behind each costly one) and sorts the
/// mistakes into six areas, says where each sits next to real players, and names up to
/// three things to work on (the first is the leak) with the training that fixes each.
/// Pure data in, so it's easy to test.
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
        /// Games the score was read from, whether or not they reached this area.
        var gamesRead = 0

        var id: String { area.rawValue }

        /// Where the score sits on the real players' ruler (`RealPlayers`), however few games
        /// it is from. Good for putting areas in order; too rough to say out loud before
        /// `gamesToCompare` games.
        var roughStanding: RealPlayers.Standing? {
            value.map { RealPlayers.area(area).standing(of: $0) }
        }

        /// Where the score sits next to real players, once enough games are read to say so.
        var standing: RealPlayers.Standing? {
            gamesRead >= CoachReport.gamesToCompare ? roughStanding : nil
        }

        /// A few words for the bar: "Better than 7 in 10", "Like most players" or "Below most
        /// players". Before there are enough games to compare, the player's own count.
        var verdict: String {
            if let standing { return standing.words }
            guard value != nil else { return "Not enough yet" }
            if mistakes == 0 { return "Clean so far" }
            return mistakes == 1 ? "1 costly move" : "\(mistakes) costly moves"
        }
    }

    /// Something to work on, and the training that fixes it. The first one is the leak.
    struct Leak: Equatable, Identifiable {
        let area: Area
        /// Like "Loose pieces".
        let headline: String
        /// One or two sentences in Leo's words, with the count from the games.
        let detail: String
        /// The Coach Leo skill whose practice fixes it, when there is one.
        let skill: String?
        /// The button's words, like "Practice safe moves".
        let action: String
        /// The count alone, for a list: "Left one hanging 12 times."
        var proof = ""
        /// Which of the positions saved from the player's games are this kind of mistake.
        var positions: Positions = .skills([])

        var id: String { headline }
    }

    /// The positions saved from the player's own games ("Fix your mistakes") that belong to
    /// one thing to work on: a pattern by the skill Leo named, or, for a mistake with no
    /// pattern behind it, the part of the game it was made in.
    enum Positions: Equatable {
        case skills(Set<String>)
        case opening, endgame, middlegame

        func holds(_ mistake: GameMistake) -> Bool {
            switch self {
            case .skills(let skills):
                return skills.contains(mistake.skill)
            case .opening:
                return mistake.skill == "opening" || (mistake.skill.isEmpty && phase(of: mistake) == .opening)
            case .endgame:
                return mistake.skill.isEmpty && phase(of: mistake) == .endgame
            case .middlegame:
                return mistake.skill.isEmpty && phase(of: mistake) == .middlegame
            }
        }

        private func phase(of mistake: GameMistake) -> Phase {
            if Phase.isEndgame(fen: mistake.fen) { return .endgame }
            return TrainingChess.moveNumber(mistake.fen) <= CoachReport.openingPlies / 2 ? .opening : .middlegame
        }
    }

    let gamesRead: Int
    let scores: [Score]
    /// Up to three things to work on: the areas furthest behind real players, the furthest first.
    let weakSpots: [Leak]
    /// Costly moves by the pattern behind them, for the ones Leo could name.
    var missed: [CoachMoment.Kind: Int] = [:]

    /// The one thing to work on first.
    var leak: Leak? { weakSpots.first }

    /// The most things to work on that are listed.
    static let weakSpotLimit = 3

    /// Games read, newest first.
    static let gameLimit = 20
    /// Games read before an area is compared with real players. The ruler was measured on 20
    /// games a player; from the newest 8 of those, an area said to be ahead of most players
    /// was really behind them for 1 player in 11, and from one game for 1 in 4.
    static let gamesToCompare = 8
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
    /// Enough games are read to put the areas next to real players.
    var isCompared: Bool { gamesRead >= Self.gamesToCompare }
    /// Games still to play before that.
    var gamesLeftToCompare: Int { max(0, Self.gamesToCompare - gamesRead) }

    // MARK: Reading the games

    /// Reads the games Leo has graded for the player's side: against the rivals, brought in
    /// from a chess site, and against a person once that game has been graded.
    static func make(games: [SavedGame]) -> CoachReport {
        let recent = games.filter(\.isPlayersOwn).sorted { $0.date > $1.date }.prefix(gameLimit)
        return make(tallies: recent.map { Tally($0) })
    }

    /// One game's part of the report: the player's moves in each area, and the costly ones.
    struct Tally: Equatable {
        /// The player's moves each area is judged on.
        var moves: [Area: Int] = [:]
        /// Costly moves, a blunder counting three times an inaccuracy.
        var weighted: [Area: Double] = [:]
        var mistakes: [Area: Int] = [:]
        /// Costly moves by the pattern behind them.
        var kinds: [CoachMoment.Kind: Int] = [:]

        init() {}

        init(_ game: SavedGame) {
            for moment in game.playerMoments {
                let phase = Phase.of(moment)
                for area in Area.allCases where phase.counts(for: area) {
                    moves[area, default: 0] += 1
                }
                guard let weight = CoachReport.weight(of: moment.moveGrade) else { continue }
                let found = MomentFinder.find(in: moment.review)
                if let kind = found?.kind, !kind.isPraise {
                    kinds[kind, default: 0] += 1
                }
                let area = CoachReport.area(for: found?.kind, phase: phase)
                weighted[area, default: 0] += weight
                mistakes[area, default: 0] += 1
            }
        }
    }

    /// The report from games already tallied, newest first. Reads the newest `gameLimit`.
    static func make(tallies: [Tally]) -> CoachReport {
        let recent = tallies.prefix(gameLimit)
        var kinds: [CoachMoment.Kind: Int] = [:]
        for tally in recent {
            kinds.merge(tally.kinds, uniquingKeysWith: +)
        }
        let scores = Area.allCases.map { score(for: $0, in: recent) }
        return CoachReport(gamesRead: recent.count, scores: scores,
                           weakSpots: weakSpots(scores: scores, kinds: kinds, games: recent.count),
                           missed: kinds)
    }

    /// How one area went across some games.
    static func score(for area: Area, in tallies: ArraySlice<Tally>) -> Score {
        var weighted = 0.0, mistakes = 0, moves = 0, games = 0
        for tally in tallies {
            let inGame = tally.moves[area] ?? 0
            moves += inGame
            if inGame >= movesToCount { games += 1 }
            weighted += tally.weighted[area] ?? 0
            mistakes += tally.mistakes[area] ?? 0
        }
        var value: Double?
        if games >= 1, moves >= minimumMoves {
            value = exp(-(weighted / Double(games)) / softness)
        }
        return Score(area: area, value: value, mistakes: mistakes, moves: moves, games: games, gamesRead: tallies.count)
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

    // MARK: What to work on

    /// The areas to work on, the one furthest behind real players first. An area counts once
    /// it has real mistakes in it; one with next to none is left alone however it ranks. An
    /// area where the player is clearly ahead of most players isn't listed either, unless
    /// they are ahead everywhere: then the lowest one alone is still the thing to work on.
    private static func weakSpots(scores: [Score], kinds: [CoachMoment.Kind: Int], games: Int) -> [Leak] {
        let judged = scores.filter { ($0.value ?? 1) < 0.9 && $0.mistakes >= 2 }
        let ranked = judged.sorted { a, b in
            let pa = a.roughStanding?.place ?? 1, pb = b.roughStanding?.place ?? 1
            if abs(pa - pb) > 0.001 { return pa < pb }
            if a.mistakes != b.mistakes { return a.mistakes > b.mistakes }
            return (Area.allCases.firstIndex(of: a.area) ?? 0) < (Area.allCases.firstIndex(of: b.area) ?? 0)
        }
        let behind = ranked.filter { $0.roughStanding?.isAhead != true }
        let listed = behind.isEmpty ? Array(ranked.prefix(1)) : Array(behind.prefix(weakSpotLimit))
        return listed.map { spot(for: $0, kinds: kinds, games: games) }
    }

    /// What to work on in one area: the pattern behind most of its mistakes when Leo can
    /// name one, otherwise the area itself.
    private static func spot(for worst: Score, kinds: [CoachMoment.Kind: Int], games: Int) -> Leak {
        let inGames = games == 1 ? "in your last game" : "in your last \(games) games"
        func times(_ n: Int) -> String { n == 1 ? "once" : (n == 2 ? "twice" : "\(n) times") }
        func moves(_ n: Int) -> String { n == 1 ? "1 costly move" : "\(n) costly moves" }

        switch worst.area {
        case .safety:
            let hung = kinds[.hungPiece] ?? 0
            let forks = kinds[.allowedFork] ?? 0
            let mates = kinds[.allowedMate] ?? 0
            if hung >= forks, hung >= mates, hung > 0 {
                return Leak(area: .safety, headline: "Loose pieces",
                            detail: "You left a piece hanging \(times(hung)) \(inGames). Before you let go of a piece, ask: can they take it for free?",
                            skill: "safety", action: "Practice safe moves",
                            proof: "Left one hanging \(times(hung)).", positions: .skills(["safety"]))
            }
            if mates > forks {
                return Leak(area: .safety, headline: "Missed threats",
                            detail: "A mate threat slipped past you \(times(mates)) \(inGames). After every move they make, ask what it attacks.",
                            skill: "threats", action: "Practice spotting threats",
                            proof: "A mate threat got past you \(times(mates)).", positions: .skills(["threats", "back-rank"]))
            }
            return Leak(area: .safety, headline: "Walking into forks",
                        detail: "You walked into a fork \(times(max(forks, 1))) \(inGames). Check every square their knights and queen can reach before you move.",
                        skill: "threats", action: "Practice spotting threats",
                        proof: "Walked into one \(times(max(forks, 1))).", positions: .skills(["forks"]))
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
                            skill: top.2, action: "Practice \(practiceName(top.2))",
                            proof: "Missed \(times(count)).", positions: .skills([top.2]))
            }
            return Leak(area: .tactics, headline: "Tactics slipping by",
                        detail: "Chances to win material went by \(times(worst.mistakes)) \(inGames).",
                        skill: "forks", action: "Practice forks",
                        proof: "Went by \(times(worst.mistakes)).",
                        positions: .skills(["forks", "free-pieces", "pins", "skewers"]))
        case .checkmates:
            let count = max(kinds[.missedMate] ?? 0, worst.mistakes)
            return Leak(area: .checkmates, headline: "Missed checkmates",
                        detail: "You had a mate on the board and missed it \(times(count)) \(inGames). When their king is short of squares, look at every check.",
                        skill: "mate-in-2", action: "Practice mates",
                        proof: "Missed \(times(count)).", positions: .skills(["mate-in-1", "mate-in-2"]))
        case .openings:
            return Leak(area: .openings, headline: "Shaky starts",
                        detail: "\(worst.mistakes) costly moves came in the first 12 moves \(inGames). Center, develop, castle: then build a repertoire you trust.",
                        skill: "opening", action: "Practice the opening rules",
                        proof: "\(moves(worst.mistakes)) in the first 12 moves.", positions: .opening)
        case .endgames:
            return Leak(area: .endgames, headline: "Endgames getting away",
                        detail: "\(worst.mistakes) costly moves came in the endgame \(inGames). The essential endgames turn those into wins.",
                        skill: nil, action: "Train endgames",
                        proof: "\(moves(worst.mistakes)) in the endgame.", positions: .endgame)
        case .calculation:
            return Leak(area: .calculation, headline: "Middlegame decisions",
                        detail: "\(worst.mistakes) costly moves came in the middlegame with no single pattern behind them. List two or three candidate moves before you choose.",
                        skill: nil, action: "Train calculation",
                        proof: "\(moves(worst.mistakes)) with no single pattern.", positions: .middlegame)
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
