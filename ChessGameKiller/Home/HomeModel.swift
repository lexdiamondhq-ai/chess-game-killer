import ChessKit
import Foundation

// What the home screen shows, worked out from the stores, so the views only draw it.
// Kept apart from the views so it can be tested without drawing anything.

/// The chess clock card at the foot of the board: the game you left, or the next one, set up and ready.
struct HomeUpNext: Equatable {
    enum Kind: Equatable {
        /// A game under way.
        case resume
        /// The next game, set up as last time.
        case ready
        /// Nothing played yet: a first game against the gentlest rival.
        case firstGame
    }

    let kind: Kind
    let level: MatchController.Level
    /// Your side. For a side picked at random, the side shown is White.
    let playerColor: Piece.Color
    let randomSide: Bool
    let timeControl: TimeControl
    /// Time left on each clock, for a timed game under way.
    let yourTime: Duration?
    let theirTime: Duration?
    /// Whose turn it is in the game under way (White's in a game not started yet).
    let yourMove: Bool
    /// The move number now, from the position (1 before any move).
    let moveNumber: Int
    /// Plies played so far.
    let plies: Int

    var rival: Rival { level.rival }
    var inProgress: Bool { kind == .resume }

    /// The side to move, so its face of the clock is the lit one.
    var sideToMove: Piece.Color {
        inProgress ? (yourMove ? playerColor : playerColor.opposite) : .white
    }

    /// The game under way, or the next one from the choices saved last time.
    @MainActor
    static func make(match: MatchController, side: SideChoice, level: MatchController.Level?,
                     timeControl: TimeControl, hasPlayed: Bool) -> HomeUpNext {
        if match.hasStarted, !match.isOver {
            let you = match.setup.playerColor
            let clock = match.clock
            return HomeUpNext(
                kind: .resume, level: match.setup.level, playerColor: you, randomSide: false,
                timeControl: match.setup.timeControl,
                yourTime: clock?.remaining(for: you), theirTime: clock?.remaining(for: you.opposite),
                yourMove: match.game.isHumanTurn,
                moveNumber: TrainingChess.moveNumber(match.game.fen),
                plies: match.game.plyCount
            )
        }
        // A first game is against Spark, who is learning too, unless a rival was picked already.
        let first = level == nil && !hasPlayed
        let color: Piece.Color = side == .black ? .black : .white
        return HomeUpNext(
            kind: first ? .firstGame : .ready, level: first ? .beginner : (level ?? .club),
            playerColor: color, randomSide: side == .random, timeControl: timeControl,
            yourTime: nil, theirTime: nil, yourMove: color == .white, moveNumber: 1, plies: 0
        )
    }

    /// The game the Play button starts: this rival, the side and clock picked last time.
    func setup(side: SideChoice) -> MatchController.Setup {
        MatchController.Setup(playerColor: side.color, level: level, timeControl: timeControl)
    }
}

// MARK: - The ladder

extension MatchController.Level {
    /// The rival's rough rating as a number, for the ladder.
    var rating: Int {
        switch self {
        case .beginner: return 800
        case .casual: return 1100
        case .club: return 1500
        case .expert: return 2000
        case .grandmaster: return 3000
        }
    }

    /// The rating as it is said aloud, without the "~".
    var spokenRating: String {
        self == .grandmaster ? "over 3000" : "about \(rating)"
    }

    /// Two or three words about how the rival plays.
    var tagline: String {
        switch self {
        case .beginner: return "Learning too"
        case .casual: return "Takes chances"
        case .club: return "Solid, patient"
        case .expert: return "Sharp, precise"
        case .grandmaster: return "Full strength"
        }
    }
}

/// The five rivals as rungs of a ladder, with your score against each.
struct HomeLadder: Equatable {
    struct Rung: Equatable, Identifiable {
        let level: MatchController.Level
        var wins = 0
        var losses = 0
        var draws = 0

        var id: Int { level.rawValue }
        var played: Int { wins + losses + draws }
        /// Points as in a match: a win is 1, a draw a half.
        var yourPoints: Double { Double(wins) + Double(draws) / 2 }
        var theirPoints: Double { Double(losses) + Double(draws) / 2 }

        enum Standing: Equatable { case notPlayed, ahead, behind, level }

        var standing: Standing {
            if played == 0 { return .notPlayed }
            if yourPoints > theirPoints { return .ahead }
            if yourPoints < theirPoints { return .behind }
            return .level
        }

        /// "3½–1½", or nil before the first game.
        var score: String? {
            played == 0 ? nil : "\(HomeLadder.points(yourPoints))–\(HomeLadder.points(theirPoints))"
        }

        var standingText: String {
            switch standing {
            case .notPlayed: return "Not played"
            case .ahead: return "You lead"
            case .behind: return "You trail"
            case .level: return "Level"
            }
        }
    }

    /// Spark first, Singularity last.
    let rungs: [Rung]
    /// The gentlest rival you don't lead yet. Nil once you lead them all.
    let nextToBeat: MatchController.Level?
    /// Your rough rating from your results, once there are a few games to go on.
    let yourRating: Int?
    /// The finished games it rests on.
    let gamesCounted: Int

    static let minimumGamesForRating = 3

    init(games: [SavedGame]) {
        var rungs = MatchController.Level.allCases.map { Rung(level: $0) }
        var counted: [(rating: Int, score: Double)] = []
        for game in games {
            guard let raw = game.level, let level = MatchController.Level(rawValue: raw) else { continue }
            switch game.result {
            case .win:
                rungs[level.rawValue].wins += 1
                counted.append((level.rating, 1))
            case .loss:
                rungs[level.rawValue].losses += 1
                counted.append((level.rating, 0))
            case .draw:
                rungs[level.rawValue].draws += 1
                counted.append((level.rating, 0.5))
            case .unfinished:
                continue
            }
        }
        self.rungs = rungs
        nextToBeat = rungs.first { $0.standing != .ahead }?.level
        gamesCounted = counted.count
        yourRating = Self.performance(counted)
    }

    /// The rating your results are worth, the way tournaments estimate it: the average
    /// rating you played, plus 400 for each win more than losses, over the games.
    /// Rounded to 50, since a handful of games can't say more.
    static func performance(_ results: [(rating: Int, score: Double)]) -> Int? {
        guard results.count >= minimumGamesForRating else { return nil }
        let n = Double(results.count)
        let average = Double(results.map(\.rating).reduce(0, +)) / n
        let margin = results.map { ($0.score - 0.5) * 2 }.reduce(0, +)
        let raw = average + 400 * margin / n
        let rounded = Int((raw / 50).rounded()) * 50
        return min(max(rounded, 400), 3000)
    }

    /// "3", "½" or "2½".
    static func points(_ value: Double) -> String {
        let whole = Int(value.rounded(.down))
        let half = value - Double(whole) >= 0.5
        if !half { return "\(whole)" }
        return whole == 0 ? "½" : "\(whole)½"
    }
}

// MARK: - Your games

/// One line of the scoresheet.
struct HomeGameRow: Identifiable, Equatable {
    let game: SavedGame
    /// "Today", "Wed" or "Oct 18", the way a scoresheet dates a game.
    let day: String
    /// Moves left to go back and fix in Rewind.
    let toFix: Int

    var id: UUID { game.id }
    var level: MatchController.Level? { game.level.flatMap(MatchController.Level.init(rawValue:)) }

    static func rows(_ games: [SavedGame], limit: Int = 5, now: Date = .now, calendar: Calendar = .current) -> [HomeGameRow] {
        games.sorted { $0.date > $1.date }.prefix(limit).map { game in
            HomeGameRow(game: game, day: day(game.date, now: now, calendar: calendar), toFix: game.leftToRewrite)
        }
    }

    static func day(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        if days > 0, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Games played in the last seven days, today included.
    static func thisWeek(_ games: [SavedGame], now: Date = .now, calendar: Calendar = .current) -> Int {
        guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return 0 }
        return games.filter { $0.date >= start && $0.date <= now }.count
    }
}

// MARK: - The puzzle

/// The puzzle the home shows: the position after the opponent's move, ready for you to solve.
struct HomePuzzle: Equatable {
    let puzzle: LichessPuzzle
    /// The position to solve, drawn as a diagram.
    let fen: String
    let solver: Piece.Color

    init?(_ puzzle: LichessPuzzle) {
        guard let setup = puzzle.moves.first,
              let fen = TrainingChess.fen(after: [setup], from: puzzle.fen),
              let solver = TrainingChess.sideToMove(fen) else { return nil }
        self.puzzle = puzzle
        self.fen = fen
        self.solver = solver
    }

    /// The way a chess column puts it: "White to play and mate in two.", "Black to play and win."
    var title: String {
        let side = solver == .white ? "White" : "Black"
        if let mate = puzzle.mateIn {
            return mate == 1 ? "\(side) to play and mate." : "\(side) to play and mate in \(Self.word(mate))."
        }
        if puzzle.themes.contains("equality") {
            return "\(side) to play. Find the best move."
        }
        return "\(side) to play and win."
    }

    static func word(_ n: Int) -> String {
        ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"][safe: n] ?? "\(n)"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
