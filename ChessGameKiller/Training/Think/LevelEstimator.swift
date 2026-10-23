import Foundation

/// Estimates a player's puzzle rating from a short run of puzzles. It keeps a
/// belief about every rating the player could have and, after each answer,
/// weighs each by how likely that answer was for a player of that rating. The
/// next puzzle is pitched at the middle of what's left, so the first steps are
/// big and the later ones small.
struct LevelEstimator: Equatable {
    struct Answer: Equatable {
        let rating: Int
        let solved: Bool
    }

    /// How many puzzles the check asks.
    static let questions = 10
    /// The first puzzle's rating, and the middle of the starting belief.
    static let start = 1200
    /// The ratings the estimate can take.
    static let grid = Array(stride(from: 400, through: 2900, by: 10))
    /// How widely the starting belief spreads around `start`: wide, so it never holds a strong player back.
    static let spread = 800.0
    /// The chance of solving a puzzle far too hard (a lucky guess) and of missing one far too easy (a slip).
    static let guess = 0.02
    static let slip = 0.1
    /// Where puzzles are pitched: inside the pack's range.
    static let pitch = 500...2700

    private(set) var answers: [Answer] = []
    /// How believable each rating in `grid` is, adding up to 1.
    private var weights: [Double]

    init() {
        weights = Self.grid.map { rating in
            let z = (Double(rating) - Double(Self.start)) / Self.spread
            return exp(-0.5 * z * z)
        }
        normalize()
    }

    var isDone: Bool { answers.count >= Self.questions }

    /// The estimate, to the nearest 10.
    var estimate: Int { Int((mean / 10).rounded()) * 10 }

    /// How sure the estimate is: one standard deviation, in rating points.
    var uncertainty: Int {
        let mean = mean
        let variance = zip(Self.grid, weights).reduce(0) { total, item in
            total + item.1 * (Double(item.0) - mean) * (Double(item.0) - mean)
        }
        return Int(variance.squareRoot().rounded())
    }

    /// The rating to pitch the next puzzle at: `start` first, then the middle of the belief.
    var nextRating: Int {
        guard !answers.isEmpty else { return Self.start }
        return min(Self.pitch.upperBound, max(Self.pitch.lowerBound, Int(mean.rounded())))
    }

    /// The chance a player of `ability` solves a puzzle rated `rating`: the Elo
    /// curve puzzle ratings use, softened by the odd lucky guess and slip.
    static func chance(ability: Double, rating: Int) -> Double {
        let elo = 1 / (1 + pow(10, (Double(rating) - ability) / 400))
        return guess + (1 - guess - slip) * elo
    }

    mutating func record(rating: Int, solved: Bool) {
        guard !isDone else { return }
        answers.append(Answer(rating: rating, solved: solved))
        for index in weights.indices {
            let chance = Self.chance(ability: Double(Self.grid[index]), rating: rating)
            weights[index] *= solved ? chance : 1 - chance
        }
        normalize()
    }

    private var mean: Double {
        zip(Self.grid, weights).reduce(0) { $0 + Double($1.0) * $1.1 }
    }

    private mutating func normalize() {
        let total = weights.reduce(0, +)
        guard total > 0 else { return }
        weights = weights.map { $0 / total }
    }
}

/// A friendly name for a range of puzzle ratings, and what it means for training.
enum LevelBand: Int, CaseIterable, Identifiable {
    case beginner, improver, club, strongClub, expert

    init(rating: Int) {
        self = Self.allCases.last { rating >= $0.floor } ?? .beginner
    }

    var id: Int { rawValue }

    /// The lowest rating in the band.
    var floor: Int {
        switch self {
        case .beginner: return 0
        case .improver: return 1000
        case .club: return 1400
        case .strongClub: return 1800
        case .expert: return 2200
        }
    }

    var name: String {
        switch self {
        case .beginner: return "Beginner"
        case .improver: return "Improver"
        case .club: return "Club player"
        case .strongClub: return "Strong club player"
        case .expert: return "Expert"
        }
    }

    /// One sentence on what the band means for the player's training.
    var advice: String {
        switch self {
        case .beginner:
            return "We'll start with the essentials: how pieces get won, and how to keep yours safe."
        case .improver:
            return "You know the basics, so we'll drill forks, pins and safe moves until they're second nature."
        case .club:
            return "You see the common tactics. Now we'll sharpen your calculation and your endgames."
        case .strongClub:
            return "You can skip the basics. Deeper combinations and precise endgames are where your points are."
        case .expert:
            return "Expect hard puzzles, long calculation and grandmaster games. The basics won't slow you down."
        }
    }
}
