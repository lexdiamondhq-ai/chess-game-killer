import ChessKit
import Foundation
import Observation

/// One round of the coordinates drill: a square is named, the player taps it on a board
/// with no labels. Right taps score and bring the next name at once; wrong ones cost time.
struct CoordinateRound {
    static let duration: TimeInterval = 30

    /// A square asked for and the one tapped instead.
    struct MixUp: Equatable {
        let asked: Square
        let tapped: Square
    }

    enum Tap: Equatable { case right, wrong }

    /// The side at the bottom of the board.
    let side: Piece.Color
    /// The square to find now.
    private(set) var target: Square
    /// The square after it, shown small so quick players can read ahead.
    private(set) var upcoming: Square
    private(set) var score = 0
    private(set) var misses = 0
    private(set) var mixUps: [MixUp] = []
    private(set) var startedAt: Date?
    private var random: TrainingRandom

    init(side: Piece.Color, seed: UInt64 = UInt64.random(in: .min ... .max)) {
        self.side = side
        random = TrainingRandom(seed: seed)
        let first = Self.pick(avoiding: [], using: &random)
        target = first
        upcoming = Self.pick(avoiding: [first], using: &random)
    }

    mutating func start(at now: Date) {
        startedAt = now
    }

    func timeLeft(at now: Date) -> TimeInterval {
        guard let startedAt else { return Self.duration }
        return max(0, Self.duration - now.timeIntervalSince(startedAt))
    }

    func isRunning(at now: Date) -> Bool {
        startedAt != nil && timeLeft(at: now) > 0
    }

    /// Scores a tap. Nil when the round isn't running, so nothing happened.
    @discardableResult
    mutating func tap(_ square: Square, at now: Date) -> Tap? {
        guard isRunning(at: now) else { return nil }
        guard square == target else {
            misses += 1
            mixUps.append(MixUp(asked: target, tapped: square))
            return .wrong
        }
        score += 1
        target = upcoming
        upcoming = Self.pick(avoiding: [target, square], using: &random)
        return .right
    }

    /// Right taps out of all taps, in percent. Nil before the first tap.
    var accuracy: Int? {
        let taps = score + misses
        return taps == 0 ? nil : Int((Double(score) / Double(taps) * 100).rounded())
    }

    /// The square the player stumbled on most, the latest one if several tie, for the coach's tip.
    var worstMixUp: MixUp? {
        var counts: [Square: Int] = [:]
        for mixUp in mixUps { counts[mixUp.asked, default: 0] += 1 }
        return mixUps.reversed().max { counts[$0.asked, default: 0] < counts[$1.asked, default: 0] }
    }

    /// Any square but the ones just asked, so a name never comes twice in a row.
    private static func pick(avoiding recent: Set<Square>, using random: inout TrainingRandom) -> Square {
        let choices = Square.allCases.filter { !recent.contains($0) }
        return choices.randomElement(using: &random) ?? .e4
    }
}

/// Runs the coordinates drill: the side to play, a 3-2-1 countdown, the 30-second round,
/// the flashes on the board, and the best scores.
@MainActor
@Observable
final class CoordinatesDrill {
    enum Phase: Equatable {
        /// Choosing a side, before the first round or after one.
        case ready
        case countdown(Int)
        case playing
        case finished
    }

    /// A square lighting up for a moment after a tap: the accent when right, red when wrong.
    struct Flash: Identifiable, Equatable {
        let id: Int
        let square: Square
        let right: Bool
    }

    private(set) var phase: Phase = .ready
    private(set) var side: Piece.Color
    private(set) var round: CoordinateRound
    private(set) var flashes: [Flash] = []
    /// Whether the round just played beat the side's best.
    private(set) var newBest = false
    /// The side's best before the round just played.
    private(set) var previousBest = 0
    let store: VisionStore

    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var nextFlashID = 0
    @ObservationIgnored private let seed: UInt64?

    /// `seed` makes the squares repeatable, for tests.
    init(store: VisionStore, side: Piece.Color = .white, seed: UInt64? = nil) {
        self.store = store
        self.side = side
        self.seed = seed
        round = CoordinateRound(side: side, seed: seed ?? UInt64.random(in: .min ... .max))
    }

    var best: Int { store.coordinatesBest(as: side) }

    /// Picks the side to play, between rounds.
    func choose(_ side: Piece.Color) {
        guard phase == .ready || phase == .finished else { return }
        self.side = side
        phase = .ready
        round = freshRound()
    }

    /// Counts down 3, 2, 1, then starts the round.
    func start() {
        guard phase == .ready || phase == .finished else { return }
        clock?.cancel()
        round = freshRound()
        flashes = []
        newBest = false
        clock = Task { [weak self] in
            for count in [3, 2, 1] {
                self?.phase = .countdown(count)
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
            }
            self?.play()
        }
    }

    /// Starts the round at once, and ends it when time is up. A start in the past
    /// leaves less time, for tests and pictures.
    func play(at now: Date = .now) {
        round.start(at: now)
        phase = .playing
        clock?.cancel()
        let left = round.timeLeft(at: .now)
        clock = Task { [weak self] in
            try? await Task.sleep(for: .seconds(left))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func tap(_ square: Square, at now: Date = .now) {
        guard phase == .playing, let result = round.tap(square, at: now) else { return }
        nextFlashID += 1
        let flash = Flash(id: nextFlashID, square: square, right: result == .right)
        flashes.append(flash)
        if flashes.count > 8 { flashes.removeFirst(flashes.count - 8) }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.flashes.removeAll { $0.id == flash.id }
        }
    }

    /// Ends the round: time is up.
    func finish() {
        guard phase == .playing else { return }
        clock?.cancel()
        previousBest = best
        newBest = store.finishCoordinates(score: round.score, as: side)
        flashes = []
        phase = .finished
    }

    /// Stops the clock when the screen closes.
    func stop() {
        clock?.cancel()
        clock = nil
    }

    /// Coach Leo's line under the board.
    func message(sideName: String) -> String {
        switch phase {
        case .ready:
            return "I name a square, you tap it. No labels on the board, thirty seconds on the clock."
        case .countdown, .playing:
            return "Find each square as I name it. A wrong tap only costs time."
        case .finished:
            var lines: [String] = []
            let score = round.score
            let squares = score == 1 ? "1 square" : "\(score) squares"
            if score == 0 {
                lines.append("Time! Tap each square as soon as you see its name.")
            } else if newBest && previousBest == 0 {
                lines.append("\(squares): your first score as \(sideName). Now beat it.")
            } else if newBest {
                lines.append("New best as \(sideName): \(squares)! Your eyes are getting quicker.")
            } else {
                lines.append("\(squares). Your best as \(sideName) is \(best).")
            }
            if let mixUp = round.worstMixUp {
                lines.append("Watch \(mixUp.asked.notation): you tapped \(mixUp.tapped.notation).")
            }
            return lines.joined(separator: " ")
        }
    }

    private func freshRound() -> CoordinateRound {
        CoordinateRound(side: side, seed: seed ?? UInt64.random(in: .min ... .max))
    }
}
