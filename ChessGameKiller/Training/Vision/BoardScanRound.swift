import ChessKit
import Foundation

// A board scan round: eight real positions, what the player found in each, and the totals.

extension BoardScan {
    /// Positions in a round.
    static let positionsPerRound = 8
    /// More squares than this to find stops being fun, so such positions are skipped.
    static let mostTargets = 6

    /// One position to scan and the squares to find in it.
    struct Exercise: Identifiable, Hashable, Sendable {
        /// The Lichess puzzle it comes from.
        let puzzleID: String
        let kind: Kind
        /// The position before their move.
        let startFEN: String
        /// Their move, which sets up the position to scan. Nil when the position is shown as it is.
        let theirMove: String?
        /// The position to scan.
        let fen: String
        /// The side to move, at the bottom of the board.
        let player: Piece.Color
        let targets: [Target]

        var id: String { puzzleID + "-" + kind.rawValue }

        /// The puzzle's position after the opponent's first move. Nil when the scan has
        /// nothing to find there, or the position doesn't suit it.
        init?(puzzle: LichessPuzzle, kind: Kind) {
            guard let first = puzzle.moves.first else { return nil }
            self.init(id: puzzle.id, startFEN: puzzle.fen, theirMove: first, kind: kind)
        }

        /// A position to scan after `theirMove` from `startFEN`, or `startFEN` itself.
        init?(id: String, startFEN: String, theirMove: String? = nil, kind: Kind) {
            var fen: String? = startFEN
            if let theirMove {
                fen = TrainingChess.fen(after: [theirMove], from: startFEN)
            }
            guard let fen, let position = Position(fen: fen),
                  let targets = BoardScan.targets(kind, in: position), !targets.isEmpty else { return nil }
            puzzleID = id
            self.kind = kind
            self.startFEN = startFEN
            self.theirMove = theirMove
            self.fen = fen
            player = position.sideToMove
            self.targets = targets
        }

        func target(on square: Square) -> Target? {
            targets.first { $0.square == square }
        }
    }

    /// The player's work on one position: what they found, where they slipped, how long it took.
    struct Attempt: Equatable {
        enum Tap: Equatable {
            /// One of the squares to find.
            case found
            /// A square that isn't one of them.
            case slip
            /// A square tapped before: nothing changes.
            case again
        }

        let exercise: Exercise
        private(set) var found: Set<Square> = []
        /// Wrong squares, in the order they were tapped.
        private(set) var slips: [Square] = []
        /// From the start of the scan to its end, once it has ended.
        var seconds: Double?

        init(exercise: Exercise) {
            self.exercise = exercise
        }

        var isComplete: Bool { found.count == exercise.targets.count }

        var missed: [Target] {
            exercise.targets.filter { !found.contains($0.square) }
        }

        @discardableResult
        mutating func tap(_ square: Square) -> Tap {
            if found.contains(square) || slips.contains(square) { return .again }
            if exercise.target(on: square) != nil {
                found.insert(square)
                return .found
            }
            slips.append(square)
            return .slip
        }

        /// How the position went, in the training screens' colors: clean, found with a slip, or missed.
        var outcome: Outcome {
            if !isComplete { return found.isEmpty ? .missed : .afterMistake }
            return slips.isEmpty ? .firstTry : .afterMistake
        }
    }

    /// A round's totals. Saved as a mode's best, so it decodes even when fields are added later.
    struct Summary: Codable, Equatable, Sendable {
        var found: Int
        var total: Int
        var slips: Int
        /// The average time a position took, in seconds.
        var seconds: Double

        init(found: Int, total: Int, slips: Int, seconds: Double) {
            self.found = found
            self.total = total
            self.slips = slips
            self.seconds = seconds
        }

        init(attempts: [Attempt]) {
            found = attempts.reduce(0) { $0 + $1.found.count }
            total = attempts.reduce(0) { $0 + $1.exercise.targets.count }
            slips = attempts.reduce(0) { $0 + $1.slips.count }
            let times = attempts.compactMap(\.seconds)
            seconds = times.isEmpty ? 0 : times.reduce(0, +) / Double(times.count)
        }

        /// Found out of everything there was to find plus every slip: 100 is a perfect round.
        var percent: Int {
            let out = total + slips
            return out == 0 ? 0 : Int((Double(found) / Double(out) * 100).rounded())
        }

        /// Better on accuracy, or as accurate and quicker.
        func beats(_ other: Summary?) -> Bool {
            guard let other else { return total > 0 }
            if percent != other.percent { return percent > other.percent }
            return seconds < other.seconds
        }

        private enum CodingKeys: String, CodingKey {
            case found, total, slips, seconds
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            found = try values.decodeIfPresent(Int.self, forKey: .found) ?? 0
            total = try values.decodeIfPresent(Int.self, forKey: .total) ?? 0
            slips = try values.decodeIfPresent(Int.self, forKey: .slips) ?? 0
            seconds = try values.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        }
    }

    // MARK: Picking positions

    /// A round's positions from the puzzle pack, near `rating`, none of them in `avoid`.
    /// Mixed changes the kind with every position. Positions with nothing to find, or
    /// more than `mostTargets`, are skipped; ones with a single square now and then.
    static func exercises(
        from library: PuzzleLibrary, mode: Mode, rating: Int, avoid: Set<String>,
        count: Int = positionsPerRound, using generator: inout some RandomNumberGenerator
    ) -> [Exercise] {
        let start = Int.random(in: 0..<Kind.allCases.count, using: &generator)
        var used = avoid
        var picked: [Exercise] = []
        for kind in mode.kinds(count: count, start: start) {
            // Everything near the rating was scanned lately: repeats beat a short round.
            guard let exercise = pick(kind, from: library, rating: rating, avoid: used, using: &generator)
                ?? pick(kind, from: library, rating: rating, avoid: Set(picked.map(\.puzzleID)), using: &generator)
            else { continue }
            picked.append(exercise)
            used.insert(exercise.puzzleID)
        }
        return picked
    }

    private static func pick(
        _ kind: Kind, from library: PuzzleLibrary, rating: Int, avoid: Set<String>,
        using generator: inout some RandomNumberGenerator
    ) -> Exercise? {
        let puzzles = library.puzzles
        for window in [100, 200, 400, 800, 4000] {
            let range = ratingRange(rating - window...rating + window, in: puzzles)
            guard !range.isEmpty else { continue }
            for attempt in 0..<24 {
                let puzzle = puzzles[Int.random(in: range, using: &generator)]
                guard !avoid.contains(puzzle.id), let exercise = Exercise(puzzle: puzzle, kind: kind),
                      exercise.targets.count <= mostTargets else { continue }
                // A single square is quick to find: keep about half of them, so most scans have a few.
                if exercise.targets.count == 1, attempt < 12, Bool.random(using: &generator) { continue }
                return exercise
            }
        }
        return nil
    }

    /// The indices of the puzzles rated within `ratings`. The library keeps them sorted by rating.
    static func ratingRange(_ ratings: ClosedRange<Int>, in puzzles: [LichessPuzzle]) -> Range<Int> {
        func firstIndex(ratedAtLeast rating: Int) -> Int {
            var low = 0
            var high = puzzles.count
            while low < high {
                let middle = (low + high) / 2
                if puzzles[middle].rating < rating { low = middle + 1 } else { high = middle }
            }
            return low
        }
        return firstIndex(ratedAtLeast: ratings.lowerBound)..<firstIndex(ratedAtLeast: ratings.upperBound + 1)
    }
}
