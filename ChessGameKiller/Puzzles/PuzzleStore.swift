import Foundation
import Observation

/// The player's puzzle record: rating, streaks, Puzzle Rush bests and the
/// puzzles seen lately. Saved to a small JSON file after each change.
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
}

@MainActor
@Observable
final class PuzzleStore {
    private(set) var progress: PuzzleProgress
    /// Nil until the pack has loaded (it reads in the background).
    private(set) var library: PuzzleLibrary?

    private let fileURL: URL?
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()
    static let recentLimit = 400

    init(progress: PuzzleProgress = PuzzleProgress(), library: PuzzleLibrary? = nil, fileURL: URL? = nil) {
        self.progress = progress
        self.library = library
        self.fileURL = fileURL
    }

    static func live() -> PuzzleStore {
        let url = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("puzzle-progress.json")
        var progress = PuzzleProgress()
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(PuzzleProgress.self, from: data) {
            progress = saved
        }
        return PuzzleStore(progress: progress, fileURL: url)
    }

    /// Reads the bundled pack off the main thread, once.
    func load() async {
        guard library == nil else { return }
        let loaded = await Task.detached(priority: .userInitiated) { PuzzleLibrary.bundled() }.value
        library = loaded ?? PuzzleLibrary(puzzles: [])
    }

    var theme: PuzzleTheme {
        get { PuzzleTheme.named(progress.themeID) }
        set { progress.themeID = newValue.id; save() }
    }

    // MARK: Picking

    /// The next rated puzzle: near the player's rating, in the chosen theme.
    func nextRated() -> LichessPuzzle? {
        library?.pick(near: progress.rating, theme: theme, avoid: Set(progress.recent), using: &generator)
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
    @discardableResult
    func record(_ puzzle: LichessPuzzle, outcome: Outcome) -> Int {
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
        remember(puzzle.id)
        save()
        return change
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
}
