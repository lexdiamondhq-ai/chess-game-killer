import Foundation

/// Training for players past Coach Leo's course: real puzzles from the Lichess pack at
/// their own level, aimed at what their games say is weakest, with their own game
/// mistakes (and puzzles they missed) coming back for review. Same shape as the course
/// sessions: start with a win, a run at the focus, review, one unlabeled, end on a high.
struct PuzzleSessionBuilder {
    let library: PuzzleLibrary
    /// The player's puzzle rating.
    let rating: Int
    /// Puzzles played lately, so today's are new.
    let avoid: Set<String>
    private var random: TrainingRandom

    static let focusCount = 4
    /// How far below the rating the warm-up and the finisher sit.
    static let easier = 250

    init(library: PuzzleLibrary, rating: Int, avoid: Set<String>, seed: UInt64) {
        self.library = library
        self.rating = rating
        self.avoid = avoid
        random = TrainingRandom(seed: seed)
    }

    /// Today's session, aimed at `theme`.
    mutating func daily(theme: PuzzleTheme, reason: String, mistakes: [GameMistake],
                        reviews: [LichessPuzzle] = []) -> SessionPlan {
        var used = Set<String>()
        var items: [SessionItem] = []
        func add(_ puzzle: LichessPuzzle?, _ role: SessionItem.Role) {
            guard let puzzle, !used.contains(puzzle.id) else { return }
            used.insert(puzzle.id)
            items.append(SessionItem(content: .drill(puzzle.drill), role: role))
        }
        add(pick(.all, near: rating - Self.easier, used: used), .warmUp)
        for _ in 0..<Self.focusCount {
            add(pick(theme, near: rating, used: used), .focus)
        }
        items += mistakes.prefix(2).map { SessionItem(content: .mistake($0), role: .review) }
        for puzzle in reviews.prefix(2) where !used.contains(puzzle.id) {
            add(puzzle, .review)
        }
        add(pick(.all, near: rating + 50, used: used), .mixed)
        add(pick(theme, near: rating - Self.easier, used: used), .finisher)
        return SessionPlan(title: "Today's training", focus: nil, lesson: nil, items: items,
                           headline: theme.name, symbol: theme.symbol, reason: reason)
    }

    /// A short run of one theme at the player's level, easier at both ends.
    mutating func practice(theme: PuzzleTheme, count: Int = 8) -> SessionPlan {
        var used = Set<String>()
        var items: [SessionItem] = []
        for index in 0..<count {
            let edge = index == 0 || index == count - 1
            guard let puzzle = pick(theme, near: edge ? rating - Self.easier : rating, used: used),
                  !used.contains(puzzle.id) else { continue }
            used.insert(puzzle.id)
            let role: SessionItem.Role = index == 0 ? .warmUp : (index == count - 1 ? .finisher : .focus)
            items.append(SessionItem(content: .drill(puzzle.drill), role: role))
        }
        return SessionPlan(title: theme.name, focus: nil, lesson: nil, items: items,
                           headline: theme.name, symbol: theme.symbol,
                           reason: "Real positions at your level, easier at both ends.")
    }

    private mutating func pick(_ theme: PuzzleTheme, near target: Int, used: Set<String>) -> LichessPuzzle? {
        library.pick(near: target, theme: theme, avoid: avoid.union(used), using: &random)
    }

    // MARK: Choosing the theme

    /// The puzzle theme that trains what a leak in the player's games is about.
    static func theme(for leak: CoachReport.Leak) -> PuzzleTheme {
        let id: String
        switch leak.area {
        case .safety: id = "defensiveMove"
        case .tactics:
            switch leak.skill {
            case "pins": id = "pin"
            case "skewers": id = "skewer"
            case "free-pieces": id = "hangingPiece"
            default: id = "fork"
            }
        case .checkmates: id = "mateIn2"
        case .openings: id = "opening"
        case .endgames: id = "endgame"
        case .calculation: id = "veryLong"
        }
        return PuzzleTheme.named(id)
    }

    /// With nothing from the games to go on, a theme of the day from the ones that win most games.
    static let rotation = ["fork", "pin", "mateIn2", "discoveredAttack", "deflection", "skewer", "rookEndgame",
                           "attraction", "hangingPiece", "mateIn3", "sacrifice", "pawnEndgame", "intermezzo",
                           "defensiveMove"]

    static func themeOfTheDay(_ date: Date, calendar: Calendar = .current) -> PuzzleTheme {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return PuzzleTheme.named(rotation[day % rotation.count])
    }
}

extension TrainingStore {
    /// Past the course: the level check put the player beyond it, or they've had a turn
    /// at every skill on it, or their puzzle rating is well past its hardest drills.
    func isPastTheCourse(puzzleRating: Int, puzzlesPlayed: Int) -> Bool {
        if (progress.placement ?? 0) >= TrainingPlanner.skipWelcomeRating { return true }
        if puzzlesPlayed >= 30, puzzleRating >= 1400 { return true }
        guard let library, !library.orderedSkills.isEmpty else { return false }
        return library.orderedSkills.allSatisfy {
            (progress.skills[$0.id]?.attempts ?? 0) >= TrainingPlanner.attemptsPerSkill
        }
    }

    /// Today's session: Coach Leo's course while there's course left, then real puzzles
    /// at the player's level aimed at the leak their games show.
    func todayPlan(puzzles: PuzzleLibrary?, rating: Int, played: Int, recent: [String],
                   report: CoachReport?, reviews: [LichessPuzzle] = [], now: Date = .now) -> SessionPlan? {
        guard let puzzles, !puzzles.puzzles.isEmpty, isPastTheCourse(puzzleRating: rating, puzzlesPlayed: played),
              let library else {
            return dailyPlan(now: now)
        }
        let planner = TrainingPlanner(library: library, progress: progress, now: now)
        let theme: PuzzleTheme
        let reason: String
        if let leak = report?.leak {
            theme = PuzzleSessionBuilder.theme(for: leak)
            reason = "Your games say: \(leak.headline.lowercased()). Today's puzzles work on it."
        } else {
            theme = PuzzleSessionBuilder.themeOfTheDay(now)
            reason = "Today's theme, at your level. Your own mistakes come back too."
        }
        var builder = PuzzleSessionBuilder(library: puzzles, rating: rating, avoid: Set(recent),
                                           seed: UInt64(truncatingIfNeeded: Int(now.timeIntervalSince1970 * 1000)))
        let plan = builder.daily(theme: theme, reason: reason, mistakes: planner.dueMistakes(), reviews: reviews)
        return plan.isEmpty ? dailyPlan(now: now) : plan
    }
}

extension TrainingStore {
    /// Today's session, ready to start: what the Train page's Today card shows, for any
    /// screen that wants to offer it. Reads the games off the main thread.
    func planToday(puzzles: PuzzleStore, games: [SavedGame], now: Date = .now) async -> SessionPlan? {
        guard isPastTheCourse(puzzleRating: puzzles.progress.rating, puzzlesPlayed: puzzles.progress.played) else {
            return dailyPlan(now: now)
        }
        await puzzles.load()
        let report = await Task.detached(priority: .userInitiated) { CoachReport.make(games: games) }.value
        return todayPlan(puzzles: puzzles.library, rating: puzzles.progress.rating, played: puzzles.progress.played,
                         recent: puzzles.progress.recent, report: report,
                         reviews: puzzles.dueReviewPuzzles(limit: 2), now: now)
    }
}

extension Drill {
    /// A puzzle from the Lichess pack, rather than one of Coach Leo's drills.
    var isLichessPuzzle: Bool { id.hasPrefix("lichess-") }
}
