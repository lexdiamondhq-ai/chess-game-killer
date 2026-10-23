import ChessKit
import Foundation
import Observation

/// Runs a board scan round: shows each position with their move played in, takes the
/// player's taps, reveals what was missed, and saves the round when it's over.
@MainActor
@Observable
final class BoardScanRunner {
    enum Phase: Equatable {
        /// Their move is being played.
        case intro
        case scanning
        /// Everything was found, or the player tapped Done: the misses are on the board.
        case revealed
        case finished
    }

    let mode: BoardScan.Mode
    let exercises: [BoardScan.Exercise]
    private(set) var index = 0
    private(set) var attempts: [BoardScan.Attempt]
    private(set) var game: GameModel
    private(set) var phase: Phase = .intro
    /// Go up with every square found and every slip, for haptics.
    private(set) var foundTaps = 0
    private(set) var slipTaps = 0
    private(set) var summary: BoardScan.Summary?
    private(set) var newBest = false

    private let store: VisionStore?
    private let sounds: SoundPlaying?
    @ObservationIgnored private var animates = true
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// Nil without positions to scan. Without a store nothing is saved.
    init?(mode: BoardScan.Mode, exercises: [BoardScan.Exercise], store: VisionStore?, sounds: SoundPlaying?) {
        guard let first = exercises.first else { return nil }
        self.mode = mode
        self.exercises = exercises
        self.store = store
        self.sounds = sounds
        attempts = exercises.map(BoardScan.Attempt.init)
        game = Self.board(for: first)
    }

    var exercise: BoardScan.Exercise { exercises[index] }
    var attempt: BoardScan.Attempt { attempts[index] }
    var isLast: Bool { index == exercises.count - 1 }

    /// Squares still to find in this position.
    var remaining: Int { attempt.exercise.targets.count - attempt.found.count }

    /// How each position has gone so far, for the dots above the board.
    var outcomes: [Outcome] {
        let done = phase == .revealed || phase == .finished ? index + 1 : index
        return attempts.prefix(done).map(\.outcome)
    }

    // MARK: Playing

    /// Shows the first position, plays their move, then starts the scan. Not animated,
    /// every position starts at once (for tests and pictures).
    func begin(animated: Bool = true) {
        animates = animated
        show()
    }

    func tap(_ square: Square, at now: Date = .now) {
        guard phase == .scanning else { return }
        switch attempts[index].tap(square) {
        case .found:
            foundTaps += 1
            if attempts[index].isComplete { reveal(at: now) }
        case .slip:
            slipTaps += 1
        case .again:
            break
        }
    }

    /// The player has found all they can see: show the rest.
    func done(at now: Date = .now) {
        guard phase == .scanning else { return }
        reveal(at: now)
    }

    /// On to the next position, or the round's results after the last one.
    func next() {
        guard phase == .revealed else { return }
        if isLast {
            finish()
        } else {
            index += 1
            show()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    // MARK: What the screen shows

    /// Once the position is revealed, an arrow to each square that was missed, from the
    /// piece that checks, takes or attacks there.
    var arrows: [BoardArrow] {
        guard phase == .revealed else { return [] }
        return attempt.missed.map { BoardArrow(from: $0.from.notation, to: $0.square.notation, color: .orange, dashed: true) }
    }

    /// Coach Leo's line under the board.
    var message: String {
        switch phase {
        case .intro, .scanning:
            return exercise.kind.instruction
        case .revealed:
            return feedback(for: attempt)
        case .finished:
            return closing
        }
    }

    var tone: DrillRunner.Tone {
        switch phase {
        case .intro, .scanning:
            return .coach
        case .revealed:
            if !attempt.missed.isEmpty { return .wrong }
            return attempt.slips.isEmpty ? .success : .hint
        case .finished:
            return summary?.percent == 100 ? .success : .coach
        }
    }

    /// Seconds for the screen, like "4.2 s".
    static func time(_ seconds: Double) -> String {
        String(format: "%.1f s", seconds)
    }

    // MARK: Helpers

    /// Sets up the current position and, when animated, plays their move into it first.
    private func show() {
        pending?.cancel()
        let exercise = self.exercise
        game = Self.board(for: exercise)
        phase = .intro
        guard animates else {
            if let move = exercise.theirMove { game.playEngineMove(move) }
            startScanning()
            return
        }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled else { return }
            if let move = exercise.theirMove { self.play(move) }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self.startScanning()
        }
    }

    private func startScanning() {
        startedAt = .now
        phase = .scanning
    }

    private func reveal(at now: Date) {
        attempts[index].seconds = startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        phase = .revealed
    }

    private func finish() {
        let summary = BoardScan.Summary(attempts: attempts)
        self.summary = summary
        newBest = store?.finishScan(summary, mode: mode, puzzles: exercises.map(\.puzzleID)) ?? false
        phase = .finished
    }

    private func feedback(for attempt: BoardScan.Attempt) -> String {
        let total = attempt.exercise.targets.count
        let time = Self.time(attempt.seconds ?? 0)
        let missed = attempt.missed
        guard !missed.isEmpty else {
            let found = total == 1 ? "Found it" : "All \(total) found"
            switch attempt.slips.count {
            case 0: return "\(found) in \(time). Clean scan."
            case 1: return "\(found) in \(time), with one slip."
            default: return "\(found) in \(time), with \(attempt.slips.count) slips."
            }
        }
        var names = missed.prefix(3).map(\.name)
        if missed.count > 3 { names.append("\(missed.count - 3) more") }
        let opener = attempt.found.isEmpty ? "" : "\(attempt.found.count) of \(total). "
        return opener + "You missed \(BoardGeometry.list(names))."
    }

    private var closing: String {
        guard let summary else { return "" }
        if summary.percent == 100 {
            return "A perfect scan. That's how strong players look at every position."
        }
        if summary.found == summary.total {
            return "Everything found. Now make every tap count: look once more before you tap."
        }
        return "You found \(summary.found) of \(summary.total). Checks, captures, threats: every position, every move."
    }

    private static func board(for exercise: BoardScan.Exercise) -> GameModel {
        let game = Position(fen: exercise.startFEN).map { GameModel(position: $0) } ?? GameModel()
        game.humanColors = []
        return game
    }

    private func play(_ move: String) {
        guard game.playEngineMove(move), let played = game.lastPlayed, let sounds else { return }
        if played.isCapture {
            sounds.play(.capture)
        } else if played.givesCheck {
            sounds.play(.check)
        } else if played.isCastle {
            sounds.play(.castle)
        } else {
            sounds.play(.move)
        }
    }
}
