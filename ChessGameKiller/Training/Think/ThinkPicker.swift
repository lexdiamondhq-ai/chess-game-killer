import Foundation

/// Picks positions for the candidates drill and puzzles for the level check
/// from the Lichess pack.
enum ThinkPicker {
    /// Rating windows to try around the target, narrowest first.
    static let windows = [100, 200, 400, 800, 3000]

    /// Whether a puzzle suits the candidates drill: at least two moves to find, so
    /// there's a real choice to weigh (which leaves out mate in one), and not a
    /// defensive puzzle, whose answer only holds the balance instead of winning.
    static func suitsCandidates(_ puzzle: LichessPuzzle) -> Bool {
        puzzle.length >= 2 && !puzzle.themes.contains("mateIn1") && !puzzle.themes.contains("defensiveMove")
    }

    /// A position for the candidates drill near `rating`: a middlegame when there
    /// is one, then an opening, then any position that suits.
    static func candidatePosition(in puzzles: [LichessPuzzle], near rating: Int, avoid: Set<String>,
                                  using generator: inout some RandomNumberGenerator) -> LichessPuzzle? {
        let suitable = puzzles.filter(suitsCandidates)
        let fresh = suitable.filter { !avoid.contains($0.id) }
        let tiers = [
            fresh.filter { $0.themes.contains("middlegame") },
            fresh.filter { $0.themes.contains("opening") },
            fresh,
        ]
        for tier in tiers {
            if let puzzle = pick(from: tier, near: rating, using: &generator) { return puzzle }
        }
        // Every position was played lately: a repeat rather than nothing.
        return suitable.min { abs($0.rating - rating) < abs($1.rating - rating) }
    }

    /// A puzzle for the level check near `rating`. Short ones come first, so ten
    /// puzzles fit in a couple of minutes.
    static func levelPuzzle(in puzzles: [LichessPuzzle], near rating: Int, avoid: Set<String>,
                            using generator: inout some RandomNumberGenerator) -> LichessPuzzle? {
        let fresh = puzzles.filter { !avoid.contains($0.id) }
        for (longest, window) in [(2, 75), (2, 150), (3, 150), (3, 300), (5, 600), (Int.max, 3000)] {
            let near = fresh.filter { $0.length <= longest && abs($0.rating - rating) <= window }
            if let puzzle = near.randomElement(using: &generator) { return puzzle }
        }
        return nil
    }

    /// A random puzzle in the narrowest window around `rating` that has one.
    private static func pick(from pool: [LichessPuzzle], near rating: Int,
                             using generator: inout some RandomNumberGenerator) -> LichessPuzzle? {
        for window in windows {
            let near = pool.filter { abs($0.rating - rating) <= window }
            if let puzzle = near.randomElement(using: &generator) { return puzzle }
        }
        return nil
    }
}
