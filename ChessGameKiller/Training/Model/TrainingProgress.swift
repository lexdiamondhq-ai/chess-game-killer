import Foundation

/// Everything the app remembers about a learner's training. Saved as JSON.
struct TrainingProgress: Codable, Equatable {
    var skills: [String: SkillRecord] = [:]
    var items: [String: ItemRecord] = [:]
    var lessonsDone: [String: Date] = [:]
    /// Positions where the learner went wrong in a game, to practice later.
    var mistakes: [GameMistake] = []
    var xp = 0
    var streak = Streak()
    var sessionsDone = 0
    /// How the last session went, from 0 to 1, so the next one can be gentler.
    var lastAccuracy: Double?
    /// The rating from the level check, when the learner took it.
    var placement: Int?
}

/// A learner's level at one skill, on the same scale as drill ratings.
struct SkillRecord: Codable, Equatable {
    var rating: Double = Trainer.startingRating
    var attempts = 0
    var solved = 0
    /// Patterns found or missed in real games.
    var gameHits = 0
    var gameMisses = 0
    var lastPracticed: Date?
}

/// Spaced-repetition state for one drill the learner has seen.
struct ItemRecord: Codable, Equatable {
    /// Leitner box: 0 is new or just missed, 5 is well known.
    var box = 0
    var due: Date
    var attempts = 0
    var lastSeen: Date
    var lastSolved = false
}

/// A position from one of the learner's games where a better move was missed.
struct GameMistake: Codable, Hashable, Identifiable {
    let id: String
    /// The position before the learner's move.
    let fen: String
    /// The engine's move there, in engine notation.
    let best: String
    let played: String
    let skill: String
    let title: String
    let created: Date
    var box = 0
    var due: Date
    var attempts = 0
    var fixed = false
}

struct Streak: Codable, Equatable {
    var current = 0
    var best = 0
    /// Last day with training, as "yyyy-MM-dd" in the learner's time zone.
    var lastDay: String?
    /// The most recent day that was forgiven as a rest day.
    var restDay: String?
}

/// How a drill went.
enum Outcome: String, Codable {
    case firstTry
    case withHint
    case afterMistake
    case missed

    /// Score for the rating update: solving cleanly counts most.
    var score: Double {
        switch self {
        case .firstTry: return 1
        case .withHint: return 0.6
        case .afterMistake: return 0.35
        case .missed: return 0
        }
    }

    var solved: Bool { self != .missed }

    /// Effort always earns something.
    var xp: Int {
        switch self {
        case .firstTry: return 10
        case .withHint: return 6
        case .afterMistake: return 5
        case .missed: return 2
        }
    }
}

/// The rules of the training: how levels move, when things come back for
/// review, and how streaks forgive a missed day. Pure functions, easy to test.
enum Trainer {
    static let startingRating = 600.0
    static let ratingRange = 200.0...2400.0
    /// Days until a drill comes back, by Leitner box.
    static let reviewDays = [0, 1, 3, 7, 16, 35]

    static let lessonXP = 40
    static let sessionXP = 30
    static let gamePatternXP = 15
    static let mistakeFixedXP = 15

    /// Chance of solving a drill of `difficulty` at `rating` (Elo formula).
    static func expected(rating: Double, difficulty: Double) -> Double {
        1 / (1 + pow(10, (difficulty - rating) / 400))
    }

    /// Moves fast at first, then settles, so a few drills find the right level.
    static func kFactor(attempts: Int) -> Double {
        switch attempts {
        case ..<8: return 56
        case ..<25: return 36
        default: return 22
        }
    }

    static func updated(_ record: SkillRecord, difficulty: Double, outcome: Outcome, weight: Double = 1, at date: Date) -> SkillRecord {
        var record = record
        let k = kFactor(attempts: record.attempts) * weight
        let change = k * (outcome.score - expected(rating: record.rating, difficulty: difficulty))
        record.rating = min(ratingRange.upperBound, max(ratingRange.lowerBound, record.rating + change))
        record.attempts += 1
        if outcome.solved { record.solved += 1 }
        record.lastPracticed = date
        return record
    }

    /// Leitner spacing: solved moves up a box, missed goes back to tomorrow.
    static func scheduled(box: Int, outcome: Outcome, at date: Date, calendar: Calendar = .current) -> (box: Int, due: Date) {
        let newBox: Int
        switch outcome {
        case .firstTry: newBox = min(box + 1, reviewDays.count - 1)
        case .withHint, .afterMistake: newBox = max(1, box)
        case .missed: newBox = 1
        }
        let due = calendar.date(byAdding: .day, value: reviewDays[newBox], to: date) ?? date
        return (newBox, due)
    }

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Counts a day of training. One missed day a week is forgiven as a rest
    /// day, because breaking a streak is the fastest way to make people quit.
    static func streak(_ streak: Streak, trainingOn date: Date, calendar: Calendar = .current) -> (streak: Streak, usedRestDay: Bool) {
        var s = streak
        let today = dayString(date, calendar: calendar)
        guard s.lastDay != today else { return (s, false) }
        var usedRest = false
        if let last = s.lastDay, let lastDate = Self.date(from: last, calendar: calendar) {
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastDate),
                                              to: calendar.startOfDay(for: date)).day ?? 99
            // The clock went backwards (a time zone change, say): still the same day.
            guard gap > 0 else { return (s, false) }
            if gap == 1 {
                s.current += 1
            } else if gap == 2, canRest(s, on: date, calendar: calendar) {
                s.current += 1
                s.restDay = dayString(calendar.date(byAdding: .day, value: -1, to: date) ?? date, calendar: calendar)
                usedRest = true
            } else {
                s.current = 1
            }
        } else {
            s.current = 1
        }
        s.lastDay = today
        s.best = max(s.best, s.current)
        return (s, usedRest)
    }

    /// Whether the streak is still alive today (trained today or yesterday,
    /// or the day before with a rest day available).
    static func isAlive(_ streak: Streak, on date: Date, calendar: Calendar = .current) -> Bool {
        guard let last = streak.lastDay, let lastDate = Self.date(from: last, calendar: calendar) else { return false }
        let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastDate),
                                          to: calendar.startOfDay(for: date)).day ?? 99
        return gap <= 1 || (gap == 2 && canRest(streak, on: date, calendar: calendar))
    }

    private static func canRest(_ streak: Streak, on date: Date, calendar: Calendar) -> Bool {
        guard let rest = streak.restDay, let restDate = Self.date(from: rest, calendar: calendar) else { return true }
        let since = calendar.dateComponents([.day], from: calendar.startOfDay(for: restDate),
                                            to: calendar.startOfDay(for: date)).day ?? 99
        return since >= 7
    }

    static func date(from day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// 0 = not started, 1 = learned, 2 = strong, 3 = mastered.
    static func level(of record: SkillRecord?, bands: SkillBands, lessonDone: Bool) -> Int {
        guard let record else { return lessonDone ? 1 : 0 }
        if record.attempts >= 20, record.rating >= bands.mastered { return 3 }
        if record.attempts >= 8, record.rating >= bands.strong { return 2 }
        if lessonDone || record.attempts >= 3 { return 1 }
        return 0
    }

    /// Progress toward mastery from 0 to 1, for the glowing rings.
    static func mastery(of record: SkillRecord?, bands: SkillBands) -> Double {
        guard let record, record.attempts > 0 else { return 0 }
        let low = bands.learned - 200
        let fraction = (record.rating - low) / max(1, bands.mastered - low)
        let confidence = min(1, Double(record.attempts) / 20)
        return min(1, max(0, fraction)) * (0.4 + 0.6 * confidence)
    }
}
