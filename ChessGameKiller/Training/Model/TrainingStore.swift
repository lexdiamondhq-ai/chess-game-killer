import Foundation
import Observation

/// What a learner earned from a drill, lesson or session.
struct TrainingReward: Equatable {
    var xp = 0
    /// The new rank, when this earned one.
    var promotion: Rank?
    var streak = 0
    var usedRestDay = false

    mutating func add(_ other: TrainingReward) {
        xp += other.xp
        promotion = other.promotion ?? promotion
        streak = max(streak, other.streak)
        usedRestDay = usedRestDay || other.usedRestDay
    }
}

/// The learner's training: the content, their progress, and every way
/// progress changes. Saved to a small JSON file after each change.
@MainActor
@Observable
final class TrainingStore {
    let library: TrainingLibrary?
    private(set) var progress: TrainingProgress

    private let fileURL: URL?
    private let calendar: Calendar

    init(library: TrainingLibrary?, progress: TrainingProgress = TrainingProgress(), fileURL: URL? = nil,
         calendar: Calendar = .current) {
        self.library = library
        self.progress = progress
        self.fileURL = fileURL
        self.calendar = calendar
    }

    /// The app's store: the bundled course and the progress saved on this device.
    static func live() -> TrainingStore {
        let url = try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("training-progress.json")
        var progress = TrainingProgress()
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(TrainingProgress.self, from: data) {
            progress = saved
        }
        return TrainingStore(library: TrainingLibrary.shared, progress: progress, fileURL: url)
    }

    // MARK: Reading

    var rank: Rank? { library?.rank(forXP: progress.xp) }

    var nextRank: Rank? { library?.nextRank(afterXP: progress.xp) }

    /// From 0 to 1, how far along to the next rank.
    var rankProgress: Double {
        guard let rank, let next = nextRank else { return 1 }
        return Double(progress.xp - rank.xp) / Double(max(1, next.xp - rank.xp))
    }

    /// Days in a row, or 0 once the streak has lapsed.
    var streak: Int {
        Trainer.isAlive(progress.streak, on: .now, calendar: calendar) ? progress.streak.current : 0
    }

    var trainedToday: Bool {
        progress.streak.lastDay == Trainer.dayString(.now, calendar: calendar)
    }

    var openMistakes: [GameMistake] { progress.mistakes.filter { !$0.fixed } }

    func isDone(_ lessonID: String) -> Bool { progress.lessonsDone[lessonID] != nil }

    /// 0 = not started, 1 = learned, 2 = strong, 3 = mastered.
    func level(of skill: Skill) -> Int {
        guard let library else { return 0 }
        return Trainer.level(of: progress.skills[skill.id], bands: library.bands(for: skill.id), lessonDone: isDone(skill.lesson))
    }

    /// From 0 to 1, for the rings around each skill.
    func mastery(of skill: Skill) -> Double {
        guard let library else { return 0 }
        return Trainer.mastery(of: progress.skills[skill.id], bands: library.bands(for: skill.id))
    }

    /// The skill today's session will work on.
    var todaysFocus: Skill? {
        guard let library else { return nil }
        return TrainingPlanner(library: library, progress: progress).todaysFocus()
    }

    static func levelName(_ level: Int) -> String {
        switch level {
        case 3: return "Mastered"
        case 2: return "Strong"
        case 1: return "Learned"
        default: return "New"
        }
    }

    // MARK: Plans

    func dailyPlan(now: Date = .now) -> SessionPlan? {
        guard let library else { return nil }
        var planner = TrainingPlanner(library: library, progress: progress, now: now)
        let plan = planner.dailySession()
        return plan.isEmpty ? nil : plan
    }

    func practicePlan(for skill: Skill, now: Date = .now) -> SessionPlan? {
        guard let library else { return nil }
        var planner = TrainingPlanner(library: library, progress: progress, now: now)
        let plan = planner.practice(skill)
        return plan.isEmpty ? nil : plan
    }

    func mistakesPlan(now: Date = .now) -> SessionPlan? {
        guard let library else { return nil }
        let plan = TrainingPlanner(library: library, progress: progress, now: now).mistakesSession()
        return plan.isEmpty ? nil : plan
    }

    /// An easy drill to rebuild confidence after a couple of misses.
    func easierDrill(for skill: String, excluding used: Set<String>) -> Drill? {
        guard let library else { return nil }
        var planner = TrainingPlanner(library: library, progress: progress)
        var used = used
        return planner.pick(from: [skill], target: TrainingPlanner.easyTarget, used: &used)
    }

    // MARK: Recording

    @discardableResult
    func record(_ drill: Drill, outcome: Outcome, at date: Date = .now) -> TrainingReward {
        let skill = progress.skills[drill.skill] ?? SkillRecord()
        progress.skills[drill.skill] = Trainer.updated(skill, difficulty: Double(drill.rating), outcome: outcome, at: date)
        let item = progress.items[drill.id]
        let schedule = Trainer.scheduled(box: item?.box ?? 0, outcome: outcome, at: date, calendar: calendar)
        progress.items[drill.id] = ItemRecord(
            box: schedule.box, due: schedule.due, attempts: (item?.attempts ?? 0) + 1,
            lastSeen: date, lastSolved: outcome.solved
        )
        return earn(outcome.xp, at: date)
    }

    @discardableResult
    func record(mistake: GameMistake, outcome: Outcome, at date: Date = .now) -> TrainingReward {
        guard let index = progress.mistakes.firstIndex(where: { $0.id == mistake.id }) else {
            return earn(outcome.xp, at: date)
        }
        var updated = progress.mistakes[index]
        let schedule = Trainer.scheduled(box: updated.box, outcome: outcome, at: date, calendar: calendar)
        updated.box = schedule.box
        updated.due = schedule.due
        updated.attempts += 1
        var bonus = 0
        // Solved cleanly on three separate days: fixed for good.
        if outcome == .firstTry, updated.box >= 3 {
            updated.fixed = true
            bonus = Trainer.mistakeFixedXP
        }
        progress.mistakes[index] = updated
        return earn(outcome.xp + bonus, at: date)
    }

    @discardableResult
    func completeLesson(_ id: String, at date: Date = .now) -> TrainingReward {
        let firstTime = progress.lessonsDone[id] == nil
        progress.lessonsDone[id] = date
        return earn(firstTime ? Trainer.lessonXP : 10, at: date)
    }

    @discardableResult
    func finishSession(accuracy: Double, at date: Date = .now) -> TrainingReward {
        progress.sessionsDone += 1
        progress.lastAccuracy = accuracy
        return earn(Trainer.sessionXP, at: date)
    }

    /// Saves a position from a game to practice later. False if it's already saved.
    @discardableResult
    func addMistake(fen: String, best: String, played: String, skill: String, title: String, at date: Date = .now) -> Bool {
        let key = TrainingChess.key(fen)
        guard !progress.mistakes.contains(where: { TrainingChess.key($0.fen) == key }) else { return false }
        progress.mistakes.append(GameMistake(
            id: UUID().uuidString, fen: fen, best: best, played: played, skill: skill, title: title,
            created: date, due: date
        ))
        // Keep the newest 60 still to fix, and drop old fixed ones.
        let open = progress.mistakes.filter { !$0.fixed }
        if open.count > 60, let oldest = open.min(by: { $0.created < $1.created }) {
            progress.mistakes.removeAll { $0.id == oldest.id }
        }
        let fixed = progress.mistakes.filter(\.fixed)
        if fixed.count > 40 {
            let keep = Set(fixed.sorted { $0.created > $1.created }.prefix(40).map(\.id))
            progress.mistakes.removeAll { $0.fixed && !keep.contains($0.id) }
        }
        save()
        return true
    }

    /// A pattern found (or missed) in a real game.
    @discardableResult
    func recordGamePattern(skill: String, found: Bool, at date: Date = .now) -> TrainingReward {
        var record = progress.skills[skill] ?? SkillRecord()
        if found {
            record.gameHits += 1
        } else {
            record.gameMisses += 1
        }
        progress.skills[skill] = record
        guard found else {
            save()
            return TrainingReward()
        }
        return earn(Trainer.gamePatternXP, at: date, countsTowardStreak: false)
    }

    /// Starts over from nothing.
    func reset() {
        progress = TrainingProgress()
        save()
    }

    // MARK: Private

    private func earn(_ xp: Int, at date: Date, countsTowardStreak: Bool = true) -> TrainingReward {
        let rankBefore = rank
        progress.xp += xp
        var reward = TrainingReward(xp: xp)
        if countsTowardStreak {
            let result = Trainer.streak(progress.streak, trainingOn: date, calendar: calendar)
            progress.streak = result.streak
            reward.usedRestDay = result.usedRestDay
        }
        reward.streak = progress.streak.current
        if let rankAfter = rank, rankAfter != rankBefore {
            reward.promotion = rankAfter
        }
        save()
        return reward
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder().encode(progress)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Couldn't save training progress: \(error)")
        }
    }
}
