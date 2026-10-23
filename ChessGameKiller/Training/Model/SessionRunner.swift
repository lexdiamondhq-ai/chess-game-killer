import Foundation
import Observation

/// Runs a training session: the lesson if there is one, then the drills one
/// by one, then a summary. Records every result as it happens, so leaving
/// early keeps what was done.
@MainActor
@Observable
final class SessionRunner {
    enum Stage: Equatable {
        case intro, lesson, drills, summary
    }

    let plan: SessionPlan
    let store: TrainingStore
    private(set) var stage: Stage = .intro
    private(set) var items: [SessionItem]
    private(set) var index = 0
    private(set) var drill: DrillRunner?
    /// Results so far, in order.
    private(set) var outcomes: [Outcome] = []
    private(set) var reward = TrainingReward()
    /// A word from the coach between drills, like after two misses in a row.
    private(set) var coachNote: String?
    /// Stopped before the last drill, so there's no session bonus.
    private(set) var endedEarly = false

    private let engine: ChessEngine?
    private let playsSounds: Bool
    @ObservationIgnored private var missesInARow = 0
    @ObservationIgnored private var used: Set<String>
    @ObservationIgnored private var recorded = false

    init(plan: SessionPlan, store: TrainingStore, engine: ChessEngine?, playsSounds: Bool = true) {
        self.plan = plan
        self.store = store
        self.engine = engine
        self.playsSounds = playsSounds
        items = plan.items
        used = Set(plan.items.compactMap { item in
            if case .drill(let drill) = item.content { return drill.id }
            return nil
        })
    }

    var current: SessionItem? { items.indices.contains(index) ? items[index] : nil }

    var solvedCount: Int { outcomes.filter(\.solved).count }

    var accuracy: Double {
        guard !outcomes.isEmpty else { return 1 }
        return outcomes.reduce(0) { $0 + $1.score } / Double(outcomes.count)
    }

    // MARK: Flow

    func begin() {
        if plan.lesson != nil {
            stage = .lesson
        } else {
            startDrills()
        }
    }

    func lessonFinished() {
        if let lesson = plan.lesson {
            reward.add(store.completeLesson(lesson.id))
        }
        startDrills()
    }

    func skipLesson() {
        startDrills()
    }

    /// Call when the current drill is done.
    func record(_ outcome: Outcome) {
        guard let item = current, !recorded else { return }
        recorded = true
        outcomes.append(outcome)
        switch item.content {
        case .drill(let drill):
            reward.add(store.record(drill, outcome: outcome))
        case .mistake(let mistake):
            reward.add(store.record(mistake: mistake, outcome: outcome))
        }

        coachNote = nil
        missesInARow = outcome == .missed ? missesInARow + 1 : 0
        if missesInARow >= 2 {
            missesInARow = 0
            // The note promises something lighter, so only say it when there is one.
            if insertEasierDrill() {
                coachNote = store.library?.course.lines.tilt.randomElement()
                    ?? "Deep breath. Even grandmasters miss these. Here's a friendlier one."
            }
        }
    }

    func next() {
        drill?.cancel()
        if index + 1 < items.count {
            index += 1
            makeDrill()
        } else {
            finish()
        }
    }

    /// Ends the session early, keeping what was done. The session bonus (and the
    /// session counting toward how gentle the next one is) is only for finishing.
    func end() {
        drill?.cancel()
        if !outcomes.isEmpty, stage == .drills {
            finish(completed: false)
        }
    }

    // MARK: Private

    private func startDrills() {
        guard !items.isEmpty else {
            finish()
            return
        }
        index = 0
        stage = .drills
        makeDrill()
    }

    private func makeDrill() {
        recorded = false
        guard let item = current else { return finish() }
        if let runner = DrillRunner(item: item, library: store.library, engine: engine, playsSounds: playsSounds) {
            drill = runner
            runner.begin()
        } else {
            // A broken item shouldn't stop the session.
            items.remove(at: index)
            if index < items.count {
                makeDrill()
            } else {
                finish()
            }
        }
    }

    /// After two misses, the next drill is an easy one of the same skill.
    /// False when there's none to add, like a game mistake with no pattern behind it.
    private func insertEasierDrill() -> Bool {
        guard let item = current else { return false }
        let skill: String
        switch item.content {
        case .drill(let missed): skill = missed.skill
        case .mistake(let mistake): skill = mistake.skill
        }
        guard !skill.isEmpty, let easier = store.easierDrill(for: skill, excluding: used) else { return false }
        used.insert(easier.id)
        items.insert(SessionItem(content: .drill(easier), role: .warmUp), at: index + 1)
        return true
    }

    private func finish(completed: Bool = true) {
        guard stage != .summary else { return }
        if completed {
            reward.add(store.finishSession(accuracy: accuracy))
        }
        endedEarly = !completed
        drill = nil
        stage = .summary
    }
}
