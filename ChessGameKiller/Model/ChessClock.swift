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

    /// One line explaining the choice.
    var detail: String {
        switch self {
        case .unlimited: return "Take all the time you like"
        case .blitz3Plus2: return "Blitz · 3 minutes each, 2 seconds back per move"
        case .blitz5: return "Blitz · 5 minutes each, no time added per move"
        case .rapid10: return "Rapid · 10 minutes each, no time added per move"
        case .rapid15Plus10: return "Rapid · 15 minutes each, 10 seconds back per move"
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
        guard flagged == nil else { return }
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

    /// Freezes both clocks, for example when the game ends.
    func pause(at now: ContinuousClock.Instant = .now) {
        stop(at: now)
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
    var clockLabel: String {
        let total = max(self, .zero)
        let seconds = Double(total.components.seconds) + Double(total.components.attoseconds) / 1e18
        if seconds < 10 {
            return String(format: "0:%04.1f", seconds)
        }
        let whole = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
