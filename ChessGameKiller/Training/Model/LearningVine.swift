import Foundation

/// The story Learn's gilded vine tells: a leaf for each day of training (newest on top), the
/// step in bloom that comes next, the buds after it, and a gold bud for what Premium opens.
struct LearningVine: Equatable {
    struct Leaf: Equatable, Identifiable {
        /// The day, "yyyy-MM-dd".
        let id: String
        let date: Date
        let title: String
        /// "and 2 more", or the XP earned.
        let detail: String
    }

    struct Bud: Equatable, Identifiable {
        var id: String { title }
        let title: String
        let detail: String
        /// Opens with Premium: drawn as a gold bud under a small crown.
        var premium = false
    }

    /// Newest first.
    let leaves: [Leaf]
    /// What to do next: the flower.
    let bloom: Bud?
    /// What follows, nearest first, the Premium bud last.
    let buds: [Bud]
    /// Days with training beyond the leaves shown.
    let earlierDays: Int

    /// The most leaves the vine draws; older days are counted under it.
    static let shownLeaves = 12

    var isEmpty: Bool { leaves.isEmpty }

    /// Leaves in the last seven days, today included.
    func daysThisWeek(now: Date = .now, calendar: Calendar = .current) -> Int {
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        return leaves.filter { $0.date >= start }.count
    }

    /// Builds the vine from what the app already remembers: the training diary, the dates
    /// lessons were finished, and the dates endgames were first learned.
    @MainActor
    static func make(progress: TrainingProgress,
                     library: TrainingLibrary?,
                     endgames: EndgameProgress,
                     today: SessionPlan?,
                     trainedToday: Bool,
                     lessonsOpen: Bool,
                     calendar: Calendar = .current) -> LearningVine {
        var titles: [String: [String]] = [:]
        var xp: [String: Int] = [:]
        func add(_ title: String, on key: String) {
            if !(titles[key] ?? []).contains(title) { titles[key, default: []].append(title) }
        }
        // Lessons and endgames first: they are the day's real milestones.
        for (id, date) in progress.lessonsDone.sorted(by: { $0.value < $1.value }) {
            if let lesson = library?.lesson(id) { add(lesson.title, on: Trainer.dayString(date, calendar: calendar)) }
        }
        for study in endgames.studies {
            if let record = endgames.records[study.id] {
                add(study.title, on: Trainer.dayString(record.firstDone, calendar: calendar))
            }
        }
        for (key, note) in progress.days {
            note.highlights.forEach { add($0, on: key) }
            xp[key] = note.xp
            if titles[key] == nil, note.xp > 0 { titles[key] = [] }
        }
        let leaves = titles.keys.sorted(by: >).compactMap { key -> Leaf? in
            guard let date = Self.date(key, calendar: calendar) else { return nil }
            let list = titles[key] ?? []
            let title = list.first ?? "Puzzles and practice"
            let detail: String
            if list.count > 1 {
                detail = "and \(list.count - 1) more"
            } else if let earned = xp[key], earned > 0 {
                detail = "+\(earned) XP"
            } else {
                detail = ""
            }
            return Leaf(id: key, date: date, title: title, detail: detail)
        }

        // The flower: today's plan while it's still to do, then the next lesson, then the next endgame.
        var used = Set<String>()
        var bloom: Bud?
        if !trainedToday, let today, !today.isEmpty {
            let title = today.headline ?? today.lesson?.title ?? today.focus?.title ?? "Today's training"
            bloom = Bud(title: title, detail: "Today · \(today.minutes) min")
        }
        let nextLesson = library?.lessons.first { lesson in
            progress.lessonsDone[lesson.id] == nil && (lessonsOpen || library?.isFreeLesson(lesson.id) == true)
        }
        if bloom == nil, let nextLesson {
            bloom = Bud(title: nextLesson.title, detail: "Next lesson")
            used.insert(nextLesson.id)
        }
        let nextEndgame = endgames.nextUp
        if bloom == nil, let nextEndgame {
            bloom = Bud(title: nextEndgame.title, detail: "Next endgame")
            used.insert(nextEndgame.id)
        }

        var buds: [Bud] = []
        if let nextLesson, !used.contains(nextLesson.id), bloom?.title != nextLesson.title {
            buds.append(Bud(title: nextLesson.title, detail: "Next lesson"))
        } else if let nextEndgame, !used.contains(nextEndgame.id) {
            buds.append(Bud(title: nextEndgame.title, detail: "Next endgame"))
        }
        if let library, let rank = library.nextRank(afterXP: progress.xp) {
            buds.append(Bud(title: "\(rank.title) rank", detail: "\(max(0, rank.xp - progress.xp)) XP to go"))
        }
        if !lessonsOpen, let library {
            let locked = library.lessons.filter { !library.isFreeLesson($0.id) && progress.lessonsDone[$0.id] == nil }.count
            if locked > 0 {
                buds.append(Bud(title: locked == 1 ? "1 more lesson" : "\(locked) more lessons", detail: "Premium", premium: true))
            }
        }

        let shown = Array(leaves.prefix(shownLeaves))
        return LearningVine(leaves: shown, bloom: bloom, buds: buds, earlierDays: leaves.count - shown.count)
    }

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// "Today", "Yesterday", "Wed" within the week, then "Nov 2".
    static func dayLabel(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let format = Date.FormatStyle(date: .omitted, time: .omitted)
        if days < 7 { return date.formatted(format.weekday(.abbreviated)) }
        return date.formatted(format.month(.abbreviated).day())
    }
}
