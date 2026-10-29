import Foundation

// The daily habit: one streak for the whole app. A day counts once any one of these is done:
// a game finished, Today's Move played, three rated puzzles solved, or a lesson or session with
// the coach. One missed day a week is forgiven, as in training (Trainer.streak), because losing
// a long streak to one busy day is the fastest way to make someone quit.
// Pure rules here; DailyStore keeps the record on disk.

/// Something the player did that may count toward the day.
enum DailyActivity: Equatable {
    /// A game finished (against a rival, a friend or a player online). Walking away doesn't count.
    case game
    /// A rated puzzle, solved or not. Three solved make a day.
    case ratedPuzzle(solved: Bool)
    /// Today's Move, played to the end: found or not, it makes the day.
    case todaysMove(found: Bool)
    /// A lesson or a session with the coach finished.
    case training
}

/// The player's daily record, saved in daily.json.
struct DailyRecord: Codable, Equatable {
    var streak = Streak()
    /// The day the counts below are for.
    var day: String?
    /// Rated puzzles solved on `day`.
    var puzzlesSolved = 0
    /// The day Today's Move was last played, its number, and whether it was found.
    var moveDay: String?
    var moveNumber: Int?
    var moveFound = false
    /// The hour of the day the goal was met, latest last, for the reminder's time.
    var hours: [Int] = []
    /// Streak milestones already marked on a piece (7, 30, 100, 365).
    var marks: [Int] = []
    /// The latest mark: the day it was earned, the days it stands for and the piece that carries it.
    var lastMark: StreakMark?
    /// The training streak was carried over once, the first time the daily habit ran.
    var seeded = false
    /// Asked once, after the first day done, whether to send a reminder.
    var reminderAsked = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case streak, day, puzzlesSolved, moveDay, moveNumber, moveFound, hours, marks, lastMark, seeded, reminderAsked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streak = try c.decodeIfPresent(Streak.self, forKey: .streak) ?? Streak()
        day = try c.decodeIfPresent(String.self, forKey: .day)
        puzzlesSolved = try c.decodeIfPresent(Int.self, forKey: .puzzlesSolved) ?? 0
        moveDay = try c.decodeIfPresent(String.self, forKey: .moveDay)
        moveNumber = try c.decodeIfPresent(Int.self, forKey: .moveNumber)
        moveFound = try c.decodeIfPresent(Bool.self, forKey: .moveFound) ?? false
        hours = try c.decodeIfPresent([Int].self, forKey: .hours) ?? []
        marks = try c.decodeIfPresent([Int].self, forKey: .marks) ?? []
        lastMark = try? c.decodeIfPresent(StreakMark.self, forKey: .lastMark)
        seeded = try c.decodeIfPresent(Bool.self, forKey: .seeded) ?? false
        reminderAsked = try c.decodeIfPresent(Bool.self, forKey: .reminderAsked) ?? false
    }
}

/// A streak milestone, carried by one piece of the army for good.
struct StreakMark: Codable, Equatable {
    var days: Int
    var day: String
    /// The piece's name when it earned the mark.
    var piece: String
}

/// What one recorded activity changed.
struct DailyOutcome: Equatable {
    /// The day's goal was met just now (it wasn't before).
    var completedDay = false
    /// The streak reached a milestone not marked before.
    var milestone: Int?
    /// A missed day was forgiven as the week's rest day.
    var usedRestDay = false
}

enum DailyRules {
    /// Rated puzzles solved that make a day.
    static let puzzlesForTheDay = 3
    /// Streak lengths a piece is marked for.
    static let milestones = [7, 30, 100, 365]
    /// The reminder's hour before there is anything to go on: early evening.
    static let defaultHour = 19
    /// How many recent days set the reminder's hour.
    static let hoursKept = 14

    static func record(_ activity: DailyActivity, in record: DailyRecord, at date: Date,
                       calendar: Calendar = .current) -> (record: DailyRecord, outcome: DailyOutcome) {
        var r = record
        let today = Trainer.dayString(date, calendar: calendar)
        if r.day != today {
            r.day = today
            r.puzzlesSolved = 0
        }
        let counts: Bool
        switch activity {
        case .game, .training:
            counts = true
        case .ratedPuzzle(let solved):
            if solved { r.puzzlesSolved += 1 }
            counts = r.puzzlesSolved >= puzzlesForTheDay
        case .todaysMove(let found):
            if r.moveDay != today {
                r.moveDay = today
                r.moveFound = found
                r.moveNumber = DailyMoves.dayNumber(for: date, calendar: calendar)
            }
            counts = true
        }
        var outcome = DailyOutcome()
        guard counts, r.streak.lastDay != today else { return (r, outcome) }
        let result = Trainer.streak(r.streak, trainingOn: date, calendar: calendar)
        r.streak = result.streak
        outcome.completedDay = true
        outcome.usedRestDay = result.usedRestDay
        r.hours.append(calendar.component(.hour, from: date))
        if r.hours.count > hoursKept { r.hours.removeFirst(r.hours.count - hoursKept) }
        if let milestone = milestones.last(where: { r.streak.current >= $0 }), !r.marks.contains(milestone) {
            r.marks.append(milestone)
            outcome.milestone = milestone
        }
        return (r, outcome)
    }

    /// Whether the day's goal is met on `date`.
    static func isDone(_ record: DailyRecord, on date: Date, calendar: Calendar = .current) -> Bool {
        record.streak.lastDay == Trainer.dayString(date, calendar: calendar)
    }

    /// Days in a row on `date`, or 0 once the streak has lapsed.
    static func streak(_ record: DailyRecord, on date: Date, calendar: Calendar = .current) -> Int {
        Trainer.isAlive(record.streak, on: date, calendar: calendar) ? record.streak.current : 0
    }

    /// The last day the streak still stands if nothing more is done: tomorrow, or the day after
    /// when the week's rest day is still free. Nil with no streak.
    static func aliveThrough(_ record: DailyRecord, calendar: Calendar = .current) -> String? {
        guard let last = record.streak.lastDay, let lastDate = Trainer.date(from: last, calendar: calendar) else { return nil }
        var through = last
        for offset in 1...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: lastDate) else { break }
            // Alive on that day means: one more done on it would still continue the streak.
            if Trainer.isAlive(record.streak, on: day, calendar: calendar) {
                through = Trainer.dayString(day, calendar: calendar)
            }
        }
        return through
    }

    /// The hour the player usually meets the goal (the middle of the recent ones), kept between
    /// 9 in the morning and 9 at night; early evening until there's something to go on.
    static func usualHour(_ record: DailyRecord) -> Int {
        guard !record.hours.isEmpty else { return defaultHour }
        let sorted = record.hours.sorted()
        return min(21, max(9, sorted[sorted.count / 2]))
    }

    /// The training streak, carried over the first time, so nobody loses the days they have.
    static func seeded(_ record: DailyRecord, training: Streak) -> DailyRecord {
        guard !record.seeded else { return record }
        var r = record
        r.seeded = true
        if r.streak.lastDay == nil || (training.lastDay ?? "") > (r.streak.lastDay ?? "") {
            r.streak = training
        }
        r.streak.best = max(r.streak.best, training.best)
        // Milestones already behind the carried-over streak aren't awarded all at once later.
        r.marks = Array(Set(r.marks + milestones.filter { $0 < r.streak.current })).sorted()
        return r
    }
}
