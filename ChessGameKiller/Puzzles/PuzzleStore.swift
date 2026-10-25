import Foundation
import Observation

/// The player's puzzle record: rating, streaks, Puzzle Rush bests, the puzzles
/// seen lately, how each theme goes and the missed puzzles waiting for review.
/// Saved to a small JSON file after each change.
struct PuzzleProgress: Codable, Equatable {
    var rating = 1000
    var played = 0
    var solved = 0
    /// Puzzles solved cleanly in a row.
    var streak = 0
    var bestStreak = 0
    var highestRating = 1000
    var rushBest = 0
    /// The last few hundred puzzles played, so they don't come back soon.
    var recent: [String] = []
    /// The theme picked last time; empty for all.
    var themeID = ""
    /// Rated puzzles tried and solved cleanly, by Lichess theme tag.
    var themeStats: [String: ThemeRecord] = [:]
    /// Rated puzzles not solved cleanly, back for review on a schedule.
    var reviews = PuzzleReviewQueue()

    enum CodingKeys: String, CodingKey {
        case rating, played, solved, streak, bestStreak, highestRating, rushBest, recent, themeID, themeStats, reviews
    }
}

extension PuzzleProgress {
    /// Reads any saved version: a key a file doesn't have yet keeps its default.
    init(from decoder: Decoder) throws {
        self.init()
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        rating = try saved.decodeIfPresent(Int.self, forKey: .rating) ?? rating
        played = try saved.decodeIfPresent(Int.self, forKey: .played) ?? played
        solved = try saved.decodeIfPresent(Int.self, forKey: .solved) ?? solved
        streak = try saved.decodeIfPresent(Int.self, forKey: .streak) ?? streak
        bestStreak = try saved.decodeIfPresent(Int.self, forKey: .bestStreak) ?? bestStreak
        highestRating = try saved.decodeIfPresent(Int.self, forKey: .highestRating) ?? highestRating
        rushBest = try saved.decodeIfPresent(Int.self, forKey: .rushBest) ?? rushBest
        recent = try saved.decodeIfPresent([String].self, forKey: .recent) ?? recent
        themeID = try saved.decodeIfPresent(String.self, forKey: .themeID) ?? themeID
        themeStats = try saved.decodeIfPresent([String: ThemeRecord].self, forKey: .themeStats) ?? themeStats
        reviews = try saved.decodeIfPresent(PuzzleReviewQueue.self, forKey: .reviews) ?? reviews
    }
}

@MainActor
@Observable
final class PuzzleStore {
    private(set) var progress: PuzzleProgress
    /// Nil until the pack has loaded (it reads in the background).
    private(set) var library: PuzzleLibrary?
    /// The Woodpecker set and how many sets were finished, kept in a file of their own.
    private(set) var cycles: PuzzleCycleFile
    /// The puzzle the home screen shows. Puzzles serves it first, so Solve opens the one shown.
    private(set) var upNext: LichessPuzzle?
    /// The last puzzle served, so the next one picked is a different one even before it is played.
    @ObservationIgnored private var lastServed: String?

    private let fileURL: URL?
    private let cyclesURL: URL?
    private let calendar: Calendar
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()
    static let recentLimit = 400

    init(progress: PuzzleProgress = PuzzleProgress(), library: PuzzleLibrary? = nil, fileURL: URL? = nil,
         cycles: PuzzleCycleFile = PuzzleCycleFile(), cyclesURL: URL? = nil, calendar: Calendar = .current) {
        self.progress = progress
        self.library = library
        self.fileURL = fileURL
        self.cycles = cycles
        self.cyclesURL = cyclesURL
        self.calendar = calendar
    }

    static func live() -> PuzzleStore {
        let url = ProgressFile.url("puzzle-progress.json")
        let cyclesURL = ProgressFile.url("puzzle-cycles.json")
        return PuzzleStore(progress: ProgressFile.read(PuzzleProgress.self, at: url) ?? PuzzleProgress(), fileURL: url,
                           cycles: ProgressFile.read(PuzzleCycleFile.self, at: cyclesURL) ?? PuzzleCycleFile(), cyclesURL: cyclesURL)
    }

    /// Reads the bundled pack off the main thread, once.
    func load() async {
        guard library == nil else { return }
        let loaded = await Task.detached(priority: .userInitiated) { PuzzleLibrary.bundled() }.value
        library = loaded ?? PuzzleLibrary(puzzles: [])
    }

    var theme: PuzzleTheme {
        get { PuzzleTheme.named(progress.themeID) }
        set {
            // The puzzle waiting was picked for the old theme.
            if newValue.id != progress.themeID { upNext = nil }
            progress.themeID = newValue.id
            save()
        }
    }

    // MARK: Picking

    /// The next rated puzzle: the one the home screen is showing, else one near the player's
    /// rating, in the chosen theme.
    func nextRated() -> LichessPuzzle? {
        let puzzle: LichessPuzzle?
        if let waiting = upNext, !progress.recent.contains(waiting.id) {
            puzzle = waiting
        } else {
            puzzle = pickRated()
        }
        upNext = nil
        lastServed = puzzle?.id
        return puzzle
    }

    /// Picks the puzzle the home screen shows, unless one is already waiting.
    func prepareUpNext() {
        guard upNext == nil else { return }
        upNext = pickRated()
    }

    private func pickRated() -> LichessPuzzle? {
        var avoid = Set(progress.recent)
        if let lastServed { avoid.insert(lastServed) }
        return library?.pick(near: progress.rating, theme: theme, avoid: avoid, using: &generator)
    }

    /// A Puzzle Rush puzzle: they start easy and climb with every one solved.
    func nextRush(solvedSoFar: Int, avoid: Set<String>) -> LichessPuzzle? {
        library?.pick(near: Self.rushRating(after: solvedSoFar), theme: .all,
                      avoid: avoid.union(progress.recent), using: &generator)
    }

    static func rushRating(after solved: Int) -> Int {
        min(2800, 600 + solved * 55)
    }

    // MARK: Recording

    /// Records a rated puzzle and returns the rating change. Only a clean solve counts as a win,
    /// as on Lichess; a solve with a hint or after a slip is a loss, but a smaller one.
    /// Every theme tag on the puzzle keeps the score, and anything short of a clean
    /// solve goes into the review queue for tomorrow.
    @discardableResult
    func record(_ puzzle: LichessPuzzle, outcome: Outcome, now: Date = .now) -> Int {
        let won = outcome == .firstTry
        let score: Double
        switch outcome {
        case .firstTry: score = 1
        case .withHint, .afterMistake: score = 0.25
        case .missed: score = 0
        }
        let expected = 1 / (1 + pow(10, Double(puzzle.rating - progress.rating) / 400))
        // Moves fast while the rating is new, then settles.
        let k: Double = progress.played < 20 ? 48 : (progress.played < 60 ? 32 : 20)
        let change = Int((k * (score - expected)).rounded())
        progress.rating = max(400, min(3200, progress.rating + change))
        progress.highestRating = max(progress.highestRating, progress.rating)
        progress.played += 1
        if won {
            progress.solved += 1
            progress.streak += 1
            progress.bestStreak = max(progress.bestStreak, progress.streak)
        } else {
            progress.streak = 0
        }
        for tag in Set(puzzle.themes) {
            progress.themeStats[tag, default: ThemeRecord()].attempts += 1
            if won { progress.themeStats[tag, default: ThemeRecord()].clean += 1 }
        }
        if !won {
            progress.reviews.missed(puzzle.id, now: now, calendar: calendar)
        } else if progress.reviews.contains(puzzle.id) {
            progress.reviews.reviewed(puzzle.id, clean: true, now: now, calendar: calendar)
        }
        remember(puzzle.id)
        save()
        return change
    }

    /// A puzzle played inside a training session: the rating stays put, but it counts
    /// as seen, a miss goes into the review queue, and one already there moves on.
    func recordTraining(_ puzzleID: String, outcome: Outcome, now: Date = .now) {
        let clean = outcome == .firstTry
        if progress.reviews.contains(puzzleID) {
            progress.reviews.reviewed(puzzleID, clean: clean, now: now, calendar: calendar)
        } else if !clean {
            progress.reviews.missed(puzzleID, now: now, calendar: calendar)
        }
        remember(puzzleID)
        save()
    }

    /// Missed puzzles due for review, ready to play in a session.
    func dueReviewPuzzles(limit: Int, now: Date = .now) -> [LichessPuzzle] {
        guard let library else { return [] }
        return dueReviews(now: now).prefix(limit).compactMap { library.puzzle(id: $0.id) }
    }

    /// Notes a Rush puzzle as seen, without touching the rating.
    func seen(_ puzzle: LichessPuzzle) {
        remember(puzzle.id)
        save()
    }

    /// Saves a Puzzle Rush score. True when it is a new best.
    @discardableResult
    func finishRush(score: Int) -> Bool {
        let best = score > progress.rushBest
        if best { progress.rushBest = score }
        save()
        return best
    }

    /// Sets the puzzle rating from a placement test. The highest rating follows
    /// it while no rated puzzle has been played, and never drops after that.
    func calibrate(rating: Int) {
        let placed = max(400, min(3200, rating))
        progress.rating = placed
        progress.highestRating = progress.played == 0 ? placed : max(progress.highestRating, placed)
        save()
    }

    // MARK: Themes

    /// Rated attempts and clean solves, by Lichess theme tag.
    var themeStats: [String: ThemeRecord] { progress.themeStats }

    /// The share of rated puzzles solved cleanly across `tags` (one theme, or a
    /// theme and its relatives), or nil with fewer than `minimumAttempts` to go
    /// on. A puzzle carrying two of the tags counts once for each.
    func accuracy(forTags tags: Set<String>, minimumAttempts: Int = 5) -> Double? {
        let records = tags.compactMap { progress.themeStats[$0] }
        let attempts = records.reduce(0) { $0 + $1.attempts }
        guard attempts > 0, attempts >= minimumAttempts else { return nil }
        return Double(records.reduce(0) { $0 + $1.clean }) / Double(attempts)
    }

    // MARK: Review

    /// Missed puzzles due for review now.
    var reviewsDue: Int { progress.reviews.due(at: .now).count }

    /// The puzzles due for review, most overdue first.
    func dueReviews(now: Date = .now) -> [PuzzleReviewItem] {
        progress.reviews.due(at: now)
    }

    /// Records a review, which never changes the rating. Says when the puzzle
    /// comes back, or that it's learned; nil if it wasn't in the queue.
    @discardableResult
    func recordReview(_ puzzleID: String, outcome: Outcome, now: Date = .now) -> PuzzleReviewQueue.Result? {
        let result = progress.reviews.reviewed(puzzleID, clean: outcome == .firstTry, now: now, calendar: calendar)
        save()
        return result
    }

    /// Takes a puzzle the pack no longer has out of the review queue.
    func dropReview(_ puzzleID: String) {
        progress.reviews.remove(puzzleID)
        save()
    }

    // MARK: Cycles

    /// The Woodpecker set under way, or the last one finished; nil before the first.
    var cycleSet: PuzzleCycleSet? { cycles.current }

    /// A line for the Puzzles door, like "Cycle 2 · 12 of 20", "Cycle 3 ready" or
    /// "Cycle 3 tomorrow". Nil when no set is under way.
    var cycleStatus: String? { cycles.current?.status(now: .now, calendar: calendar) }

    /// Whether a set is part way through, so starting another should ask first.
    var cycleSetInProgress: Bool {
        guard let set = cycles.current else { return false }
        return !set.isComplete
    }

    /// Whether the last cycle ended today, so the next one is better tomorrow.
    func cycleRestSuggested(now: Date = .now) -> Bool {
        cycles.current?.restSuggested(now: now, calendar: calendar) ?? false
    }

    /// Builds a new set from the pack, avoiding puzzles seen lately, and starts
    /// its first cycle. Replaces any set there was. False until the pack has loaded.
    @discardableResult
    func startCycleSet(size: PuzzleCycleSize, now: Date = .now) -> Bool {
        guard let library else { return false }
        var avoid = Set(progress.recent).union(progress.reviews.ids)
        avoid.formUnion(cycles.current?.puzzleIDs ?? [])
        guard let set = PuzzleCycleSet.make(from: library, size: size.count, rating: progress.rating,
                                            avoid: avoid, now: now, using: &generator) else { return false }
        cycles.current = set
        // Seen now, so rated play doesn't serve them while the set is being learned.
        for id in set.puzzleIDs { remember(id) }
        save()
        saveCycles()
        return true
    }

    /// Records the puzzle up next in the current cycle. Cycles never change the puzzle rating.
    func recordCycle(_ puzzleID: String, clean: Bool, seconds: TimeInterval, now: Date = .now) {
        guard var set = cycles.current, set.record(puzzleID, clean: clean, seconds: seconds, now: now) else { return }
        if set.isComplete { cycles.setsFinished += 1 }
        cycles.current = set
        saveCycles()
    }

    /// Keeps the time spent on a puzzle the player left part way through.
    func pauseCycle(carrying seconds: TimeInterval) {
        guard seconds > 0, var set = cycles.current else { return }
        set.carry(seconds)
        cycles.current = set
        saveCycles()
    }

    /// Starts the next cycle of the current set: reshuffled, with its target.
    @discardableResult
    func startNextCycle(now: Date = .now) -> Bool {
        guard var set = cycles.current, set.startNextCycle(now: now, using: &generator) else { return false }
        cycles.current = set
        saveCycles()
        return true
    }

    /// Takes a puzzle the pack no longer has out of the current set.
    func dropFromCycles(_ puzzleID: String, now: Date = .now) {
        guard var set = cycles.current else { return }
        set.remove(puzzleID, now: now)
        cycles.current = set
        saveCycles()
    }

    // MARK: Saving

    private func remember(_ id: String) {
        progress.recent.append(id)
        if progress.recent.count > Self.recentLimit {
            progress.recent.removeFirst(progress.recent.count - Self.recentLimit)
        }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(progress) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func saveCycles() {
        guard let cyclesURL, let data = try? JSONEncoder().encode(cycles) else { return }
        try? data.write(to: cyclesURL, options: .atomic)
    }
}
