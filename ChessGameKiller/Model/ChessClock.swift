import ChessKit
import Foundation
import Observation

/// How much time each side gets, like "5+0": five minutes, nothing added per move.
enum TimeControl: String, CaseIterable, Identifiable {
    case unlimited = "none"
    case blitz3Plus2 = "3+2"
    case blitz5 = "5+0"
    case rapid10 = "10+0"
    case rapid15Plus10 = "15+10"

    var id: Self { self }

    /// Time each side starts with.
    var initial: Duration {
        switch self {
        case .unlimited: return .zero
        case .blitz3Plus2: return .seconds(3 * 60)
        case .blitz5: return .seconds(5 * 60)
        case .rapid10: return .seconds(10 * 60)
        case .rapid15Plus10: return .seconds(15 * 60)
        }
    }

    /// Time given back after every move.
    var increment: Duration {
        switch self {
        case .blitz3Plus2: return .seconds(2)
        case .rapid15Plus10: return .seconds(10)
        default: return .zero
        }
    }

    var isTimed: Bool { self != .unlimited }

    /// Short name for a chip: "No clock", "3+2".
    var name: String {
        self == .unlimited ? "No clock" : rawValue
    }

    /// The family of the time control, "Blitz" or "Rapid". Nil for no clock.
    var kind: String? {
        switch self {
        case .unlimited: return nil
        case .blitz3Plus2, .blitz5: return "Blitz"
        case .rapid10, .rapid15Plus10: return "Rapid"
        }
    }

    /// One line explaining the choice.
    var detail: String {
        switch self {
        case .unlimited: return "Take all the time you like"
        case .blitz3Plus2: return "Blitz · 3 minutes each, plus 2 seconds per move"
        case .blitz5: return "Blitz · 5 minutes each, no time added per move"
        case .rapid10: return "Rapid · 10 minutes each, no time added per move"
        case .rapid15Plus10: return "Rapid · 15 minutes each, plus 10 seconds per move"
        }
    }
}

/// A two-sided chess clock. Only one side runs at a time; the side that just
/// moved gets its increment and the other side's clock starts.
///
/// Time is measured from instants rather than ticked, so the screen can ask
/// for `remaining(for:at:)` as often as it likes without the clock doing any work.
@MainActor
@Observable
final class ChessClock {
    let initial: Duration
    let increment: Duration

    /// The side whose clock is running, if any.
    private(set) var running: Piece.Color?
    /// Set once a side has run out of time. The clock stops for good.
    private(set) var flagged: Piece.Color?
    /// Set while the clock is held for something outside the game, like the app
    /// going to the background or a lesson over the board. `start` does nothing
    /// until `release`, so a move landing meanwhile can't restart the clock.
    private(set) var held = false
    /// Called on the main actor when a side runs out of time.
    var onFlag: ((Piece.Color) -> Void)?

    private var stored: [Piece.Color: Duration]
    private var startedAt: ContinuousClock.Instant?
    private var flagTask: Task<Void, Never>?

    init(initial: Duration, increment: Duration = .zero) {
        self.initial = initial
        self.increment = increment
        stored = [.white: initial, .black: initial]
    }

    convenience init(control: TimeControl) {
        self.init(initial: control.initial, increment: control.increment)
    }

    /// Time left for a side at a moment, never below zero.
    func remaining(for color: Piece.Color, at now: ContinuousClock.Instant = .now) -> Duration {
        let base = stored[color] ?? .zero
        guard running == color, let startedAt else { return max(base, .zero) }
        return max(base - (now - startedAt), .zero)
    }

    /// Starts (or switches to) a side's clock without giving anyone an increment.
    func start(_ color: Piece.Color, at now: ContinuousClock.Instant = .now) {
        guard flagged == nil, !held else { return }
        if running == color { return }
        stop(at: now)
        running = color
        startedAt = now
        scheduleFlag(for: color)
    }

    /// The side that just moved stops its clock, gets its increment, and the other side starts.
    func moved(by color: Piece.Color, at now: ContinuousClock.Instant = .now) {
        guard flagged == nil else { return }
        if running == color {
            stop(at: now)
            stored[color] = (stored[color] ?? .zero) + increment
        } else if running == nil {
            stored[color] = (stored[color] ?? .zero) + increment
        }
        start(color.opposite, at: now)
    }

    /// A move was taken back: the increment it earned comes off again, never below
    /// zero. Both clocks stop; the caller starts the right side afterwards. (A side
    /// left at zero flags the moment it is started, which is only fair: it had
    /// already spent more than the increment it is giving back.)
    func tookBack(moveBy color: Piece.Color, at now: ContinuousClock.Instant = .now) {
        guard flagged == nil else { return }
        stop(at: now)
        stored[color] = max((stored[color] ?? .zero) - increment, .zero)
    }

    /// Freezes both clocks, for example when the game ends.
    func pause(at now: ContinuousClock.Instant = .now) {
        stop(at: now)
    }

    /// Freezes both clocks until `release(_:)`; `start` is ignored in between.
    func hold(at now: ContinuousClock.Instant = .now) {
        stop(at: now)
        held = true
    }

    /// Lets the clock run again, for `color`; with no color it stays stopped until the next
    /// move starts it (before the first move, nobody's time runs).
    func release(_ color: Piece.Color?, at now: ContinuousClock.Instant = .now) {
        held = false
        if let color { start(color, at: now) }
    }

    private func stop(at now: ContinuousClock.Instant) {
        flagTask?.cancel()
        flagTask = nil
        guard let color = running else { return }
        stored[color] = remaining(for: color, at: now)
        running = nil
        startedAt = nil
    }

    private func scheduleFlag(for color: Piece.Color) {
        let left = remaining(for: color)
        flagTask = Task { [weak self] in
            try? await Task.sleep(for: left)
            guard !Task.isCancelled else { return }
            self?.flag(color)
        }
    }

    private func flag(_ color: Piece.Color) {
        guard flagged == nil, running == color else { return }
        stored[color] = .zero
        running = nil
        startedAt = nil
        flagged = color
        onFlag?(color)
    }
}

extension Duration {
    /// "4:51", or "0:09.4" under ten seconds so the last moments are readable.
    /// Rounded up on both sides of ten seconds, so the running clock never skips
    /// a second there and "0:00.0" only shows once the time is really gone.
    var clockLabel: String {
        let total = max(self, .zero)
        let attosecondsPerTenth: Int64 = 100_000_000_000_000_000
        let tenths = Int(total.components.seconds * 10 + (total.components.attoseconds + attosecondsPerTenth - 1) / attosecondsPerTenth)
        if tenths <= 100 {
            return String(format: "0:%02d.%d", tenths / 10, tenths % 10)
        }
        let whole = (tenths + 9) / 10
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
