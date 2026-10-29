import Foundation
import Observation

/// The daily habit on this phone: the streak, today's counts and Today's Move. Saved to
/// daily.json after each change. The game screen hooks it to everything that counts
/// (games, rated puzzles, lessons and sessions) and to the army, the widget and the reminders.
@MainActor
@Observable
final class DailyStore {
    private(set) var state: DailyRecord

    /// Told about every change, so the widget and the reminders can follow.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Told when the streak reaches a milestone; answers with the name of the piece that carries
    /// the mark (the army chooses it), or nil when there's no army to mark.
    @ObservationIgnored var onMilestone: ((Int) -> String?)?

    private let fileURL: URL?
    private let calendar: Calendar

    init(state: DailyRecord = DailyRecord(), fileURL: URL? = nil, calendar: Calendar = .current) {
        self.state = state
        self.fileURL = fileURL
        self.calendar = calendar
    }

    /// The app's store, carrying over the training streak the first time.
    static func live(trainingStreak: Streak) -> DailyStore {
        let url = ProgressFile.url("daily.json")
        let saved = ProgressFile.read(DailyRecord.self, at: url) ?? DailyRecord()
        let store = DailyStore(state: DailyRules.seeded(saved, training: trainingStreak), fileURL: url)
        if !saved.seeded { store.save() }
        return store
    }

    // MARK: Reading

    /// Days in a row, or 0 once the streak has lapsed.
    func streakDays(on date: Date = .now) -> Int { DailyRules.streak(state, on: date, calendar: calendar) }

    var streak: Int { streakDays(on: .now) }

    var bestStreak: Int { max(state.streak.best, streak) }

    /// The day's goal is met.
    func isDone(on date: Date = .now) -> Bool { DailyRules.isDone(state, on: date, calendar: calendar) }

    var doneToday: Bool { isDone() }

    /// Today's Move for `date`.
    func puzzle(on date: Date = .now) -> DailyPuzzle? { DailyMoves.puzzle(for: date, calendar: calendar) }

    /// Today's Move has been played today.
    func playedMove(on date: Date = .now) -> Bool {
        state.moveDay == Trainer.dayString(date, calendar: calendar)
    }

    var playedTodaysMove: Bool { playedMove() }

    /// Rated puzzles solved today, toward the three that make a day.
    var puzzlesToday: Int {
        state.day == Trainer.dayString(.now, calendar: calendar) ? state.puzzlesSolved : 0
    }

    /// The milestone mark earned today, to say so on the home.
    var markToday: StreakMark? {
        guard let mark = state.lastMark, mark.day == Trainer.dayString(.now, calendar: calendar) else { return nil }
        return mark
    }

    /// The next milestone ahead and how many days to it.
    var nextMilestone: (days: Int, toGo: Int)? {
        let current = streak
        guard let next = DailyRules.milestones.first(where: { $0 > current }) else { return nil }
        return (next, next - current)
    }

    /// The hour the reminder comes at.
    var usualHour: Int { DailyRules.usualHour(state) }

    /// What the widget shows, with the army's best piece.
    func snapshot(hero: String?, heroRank: String?) -> DailySnapshot {
        var snapshot = DailySnapshot()
        snapshot.streak = state.streak.current
        snapshot.lastDay = state.streak.lastDay
        snapshot.aliveThrough = DailyRules.aliveThrough(state, calendar: calendar)
        snapshot.moveDay = state.moveDay
        snapshot.moveFound = state.moveFound
        snapshot.hero = hero
        snapshot.heroRank = heroRank
        return snapshot
    }

    // MARK: Recording

    @discardableResult
    func record(_ activity: DailyActivity, at date: Date = .now) -> DailyOutcome {
        let result = DailyRules.record(activity, in: state, at: date, calendar: calendar)
        state = result.record
        if let milestone = result.outcome.milestone, let piece = onMilestone?(milestone) {
            state.lastMark = StreakMark(days: milestone, day: Trainer.dayString(date, calendar: calendar), piece: piece)
        }
        save()
        onChange?()
        return result.outcome
    }

    /// The reminder question was answered (either way): it isn't asked again.
    func markReminderAsked() {
        guard !state.reminderAsked else { return }
        state.reminderAsked = true
        save()
    }

    /// Starts over from nothing (Settings, Reset progress).
    func reset() {
        var fresh = DailyRecord()
        fresh.seeded = true
        state = fresh
        save()
        onChange?()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Couldn't save the daily record: %@", "\(error)")
        }
    }
}
