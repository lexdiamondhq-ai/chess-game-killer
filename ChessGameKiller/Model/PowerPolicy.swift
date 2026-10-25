import Foundation
import Observation

/// How hard the app may work right now. On a hot phone, or with Low Power Mode on, the engine
/// searches on one thread, less deeply and for less time, and the 3D boards draw at 30 frames
/// a second with lighter smoothing. Everything comes back the moment the phone cools down or
/// Low Power Mode goes off. The rival's own moves are untouched: its searches are shallow anyway.
@MainActor
@Observable
final class PowerPolicy {
    static let shared = PowerPolicy.live()

    private(set) var thermalState: ProcessInfo.ThermalState
    private(set) var lowPowerMode: Bool
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(thermalState: ProcessInfo.ThermalState = .nominal, lowPowerMode: Bool = false) {
        self.thermalState = thermalState
        self.lowPowerMode = lowPowerMode
    }

    /// The app's policy: the phone's state now, kept up to date as it changes.
    static func live() -> PowerPolicy {
        let info = ProcessInfo.processInfo
        let policy = PowerPolicy(thermalState: info.thermalState, lowPowerMode: info.isLowPowerModeEnabled)
        policy.watch()
        return policy
    }

    /// Whether to hold back: the phone is hot, or Low Power Mode is on.
    var isConstrained: Bool { Self.constrained(thermal: thermalState, lowPower: lowPowerMode) }

    /// A phone that is "serious" or "critical" about heat is already being slowed down by iOS;
    /// "fair" is normal for a game and gets everything.
    nonisolated static func constrained(thermal: ProcessInfo.ThermalState, lowPower: Bool) -> Bool {
        lowPower || thermal == .serious || thermal == .critical
    }

    /// The phone's state right now, read directly: for code that runs outside the main actor.
    nonisolated static func systemConstrained() -> Bool {
        let info = ProcessInfo.processInfo
        return constrained(thermal: info.thermalState, lowPower: info.isLowPowerModeEnabled)
    }

    var engineBudget: EngineBudget { isConstrained ? .light : .full }

    /// How fast a 3D board draws, and how much it smooths its edges.
    var framesPerSecond: Int { Self.framesPerSecond(constrained: isConstrained) }

    nonisolated static func framesPerSecond(constrained: Bool) -> Int { constrained ? 30 : 60 }

    private func watch() {
        // Both notifications arrive on any thread.
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    private func refresh() {
        let info = ProcessInfo.processInfo
        update(thermal: info.thermalState, lowPower: info.isLowPowerModeEnabled)
    }

    /// Takes a new reading. Tests call it directly.
    func update(thermal: ProcessInfo.ThermalState, lowPower: Bool) {
        thermalState = thermal
        lowPowerMode = lowPower
    }
}

/// How much engine work the coach's part of a turn may cost: the look-ahead on the person's
/// turn (the hints, the eval ring and Ghost Vision) and the grading of their move.
struct EngineBudget: Equatable {
    var lookaheadDepth: Int
    var lookaheadMs: Int
    /// Grading looks at the position before the person's move (when the look-ahead didn't
    /// already) and after it.
    var gradeDepth: Int
    var gradeBeforeMs: Int
    var gradeAfterMs: Int

    static let full = EngineBudget(lookaheadDepth: 14, lookaheadMs: 2000, gradeDepth: 12, gradeBeforeMs: 900, gradeAfterMs: 700)
    /// About a third of the work: still enough to grade a move and light the best one.
    static let light = EngineBudget(lookaheadDepth: 10, lookaheadMs: 800, gradeDepth: 10, gradeBeforeMs: 500, gradeAfterMs: 400)
}
