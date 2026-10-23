import ChessKit
import Foundation
import Observation

/// The level check: ten puzzles from the pack with no hints and one try each,
/// harder after a solve and easier after a miss, then an estimated rating, so a
/// strong player can skip the basics.
@MainActor
@Observable
final class LevelCheckRunner {
    enum Phase: Equatable {
        /// Before the first puzzle.
        case intro
        case solving
        /// A short pause after an answer, before the next puzzle.
        case answered(solved: Bool)
        case finished
    }

    private(set) var phase: Phase = .intro
    private(set) var estimator = LevelEstimator()
    private(set) var puzzle: LichessPuzzle?
    /// Plays the puzzle on the board. Strict: one wrong move ends it.
    private(set) var drill: DrillRunner?

    private let puzzles: [LichessPuzzle]
    private let playsSounds: Bool
    @ObservationIgnored private var used: Set<String> = []
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// A check over `puzzles`. Answers already given can be passed in `estimator`,
    /// as tests and previews do; a full set goes straight to the result.
    init(puzzles: [LichessPuzzle], playsSounds: Bool = true, estimator: LevelEstimator = LevelEstimator()) {
        self.puzzles = puzzles
        self.playsSounds = playsSounds
        self.estimator = estimator
    }

    /// The puzzle on the board, from 1.
    var number: Int {
        min(LevelEstimator.questions, estimator.answers.count + (phase == .solving ? 1 : 0))
    }

    /// From 0 to 1, how much of the check is done.
    var progress: Double {
        Double(estimator.answers.count) / Double(LevelEstimator.questions)
    }

    var rating: Int { estimator.estimate }
    var band: LevelBand { LevelBand(rating: rating) }
    var solved: Int { estimator.answers.filter(\.solved).count }

    /// The player's side in the puzzle on the board.
    var learner: Piece.Color { drill?.learner ?? .white }

    func start() {
        guard phase == .intro else { return }
        if estimator.isDone {
            phase = .finished
        } else {
            next()
        }
    }

    /// A tap on the board. The first wrong move is a miss, and a solve is a solve.
    func tap(_ square: Square) {
        guard phase == .solving, let drill, drill.acceptsTaps else { return }
        drill.tap(square)
        if drill.mistakes > 0 {
            answer(solved: false)
        } else if let outcome = drill.outcome {
            answer(solved: outcome == .firstTry)
        }
    }

    /// Gives up on the puzzle on the board. It counts as a miss.
    func pass() {
        guard phase == .solving else { return }
        answer(solved: false)
    }

    func cancel() {
        pending?.cancel()
        drill?.cancel()
    }

    private func next() {
        let item = ThinkPicker.levelPuzzle(in: puzzles, near: estimator.nextRating, avoid: used, using: &generator)
        guard let item, let made = DrillRunner(item: SessionItem(content: .drill(item.drill), role: .focus),
                                               library: nil, engine: nil, playsSounds: playsSounds) else {
            // Out of puzzles: the estimate stands on the answers so far.
            phase = .finished
            return
        }
        used.insert(item.id)
        made.strict = true
        puzzle = item
        drill = made
        phase = .solving
        made.begin()
    }

    private func answer(solved: Bool) {
        guard let puzzle else { return }
        drill?.cancel()
        estimator.record(rating: puzzle.rating, solved: solved)
        phase = .answered(solved: solved)
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(solved ? 700 : 1000))
            guard let self, !Task.isCancelled else { return }
            if self.estimator.isDone {
                self.phase = .finished
            } else {
                self.next()
            }
        }
    }
}
