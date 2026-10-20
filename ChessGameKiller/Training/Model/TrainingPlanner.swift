import Foundation

/// A training session: maybe a lesson first, then a short run of drills.
struct SessionPlan: Identifiable {
    let id = UUID()
    let title: String
    let focus: Skill?
    /// Shown before the drills when the focus skill hasn't been taught yet.
    let lesson: Lesson?
    let items: [SessionItem]

    var minutes: Int {
        let lessonMinutes = lesson == nil ? 0.0 : 2.0
        return max(1, Int((lessonMinutes + Double(items.count) * 0.6).rounded(.up)))
    }

    var isEmpty: Bool { lesson == nil && items.isEmpty }
}

struct SessionItem: Identifiable, Hashable {
    enum Role: String {
        /// Something easy to start with a win.
        case warmUp
        /// Today's skill, at about four-in-five difficulty.
        case focus
        /// Back for another look: missed before, or from one of your games.
        case review
        /// A different skill with no label, like in a real game.
        case mixed
        /// End on a high note.
        case finisher
    }

    enum Content: Hashable {
        case drill(Drill)
        case mistake(GameMistake)
    }

    let content: Content
    let role: Role

    var id: String {
        switch content {
        case .drill(let drill): return "d-\(drill.id)"
        case .mistake(let mistake): return "m-\(mistake.id)"
        }
    }
}

/// Builds sessions. The rules, in coach's terms:
/// - Start with a win, end with a win (people remember the peak and the end).
/// - Keep the focus drills at about four out of five solved: hard enough to
///   learn from, easy enough to stay fun.
/// - Bring back what was missed, on a widening schedule, and the learner's
///   own game mistakes first.
/// - Mix in one other skill without saying which, because real games never
///   announce the pattern.
/// - Move on to a new skill after a few sessions, but go back to anything
///   the learner is struggling with first.
struct TrainingPlanner {
    let library: TrainingLibrary
    let progress: TrainingProgress
    let now: Date
    private var random: TrainingRandom

    /// Attempts on a skill before the journey moves to the next one.
    static let attemptsPerSkill = 6
    static let focusTarget = 0.8
    static let gentleTarget = 0.86
    static let easyTarget = 0.93

    init(library: TrainingLibrary, progress: TrainingProgress, now: Date = .now, seed: UInt64? = nil) {
        self.library = library
        self.progress = progress
        self.now = now
        random = TrainingRandom(seed: seed ?? UInt64(truncatingIfNeeded: Int(now.timeIntervalSince1970 * 1000)))
    }

    // MARK: Sessions

    mutating func dailySession() -> SessionPlan {
        let focus = todaysFocus()
        var used = Set<String>()
        var items: [SessionItem] = []
        let gentle = (progress.lastAccuracy ?? 1) < 0.55
        let strong = learnedSkills().filter { $0.id != focus?.id }

        if let warm = pick(from: strong.map(\.id), target: Self.easyTarget, used: &used) {
            items.append(SessionItem(content: .drill(warm), role: .warmUp))
        }
        if let focus {
            for _ in 0..<4 {
                if let drill = pick(from: [focus.id], target: gentle ? Self.gentleTarget : Self.focusTarget, used: &used) {
                    items.append(SessionItem(content: .drill(drill), role: .focus))
                }
            }
        }
        let mistakes = dueMistakes().prefix(2)
        items += mistakes.map { SessionItem(content: .mistake($0), role: .review) }
        for drill in dueDrills(excluding: used).prefix(max(1, 3 - mistakes.count)) {
            used.insert(drill.id)
            items.append(SessionItem(content: .drill(drill), role: .review))
        }
        if let mixed = pick(from: strong.map(\.id), target: Self.focusTarget, used: &used) {
            items.append(SessionItem(content: .drill(mixed), role: .mixed))
        }
        let finisherSkills = [focus?.id].compactMap { $0 } + strong.map(\.id)
        if let finisher = pick(from: finisherSkills, target: Self.easyTarget, used: &used) {
            items.append(SessionItem(content: .drill(finisher), role: .finisher))
        }

        return SessionPlan(title: "Today's training", focus: focus, lesson: todaysLesson(focus: focus), items: items)
    }

    /// Practice one skill: easy start, then drills at the learner's level, easy finish.
    mutating func practice(_ skill: Skill, count: Int = 8) -> SessionPlan {
        var used = Set<String>()
        var items: [SessionItem] = []
        let gentle = (progress.lastAccuracy ?? 1) < 0.55
        for index in 0..<count {
            let target: Double
            if index == 0 || index == count - 1 {
                target = Self.easyTarget
            } else {
                target = gentle ? Self.gentleTarget : Self.focusTarget
            }
            if let drill = pick(from: [skill.id], target: target, used: &used) {
                items.append(SessionItem(content: .drill(drill), role: index == 0 ? .warmUp : (index == count - 1 ? .finisher : .focus)))
            }
        }
        let lesson = progress.lessonsDone[skill.lesson] == nil ? library.lesson(skill.lesson) : nil
        return SessionPlan(title: skill.title, focus: skill, lesson: lesson, items: items)
    }

    /// The learner's own game mistakes, due ones first.
    func mistakesSession(limit: Int = 8) -> SessionPlan {
        let open = progress.mistakes.filter { !$0.fixed }
        let due = open.filter { $0.due <= now }.sorted { $0.due < $1.due }
        let rest = open.filter { $0.due > now }.sorted { $0.due < $1.due }
        let items = (due + rest).prefix(limit).map { SessionItem(content: .mistake($0), role: .review) }
        return SessionPlan(title: "Fix your mistakes", focus: nil, lesson: nil, items: Array(items))
    }

    // MARK: Choosing

    /// The course's first lesson, for a brand-new learner who hasn't watched it yet.
    var openingLesson: Lesson? {
        guard progress.sessionsDone == 0, progress.items.isEmpty, let first = library.lessons.first,
              progress.lessonsDone[first.id] == nil else {
            return nil
        }
        return first
    }

    /// The lesson today's session opens with: the course's first for a brand-new
    /// learner, otherwise the focus skill's when it hasn't been watched yet.
    func todaysLesson(focus: Skill?) -> Lesson? {
        openingLesson ?? focus.flatMap { skill in
            progress.lessonsDone[skill.lesson] == nil ? library.lesson(skill.lesson) : nil
        }
    }

    /// Today's skill: the first lesson's on day one, then the next one on the journey.
    func todaysFocus() -> Skill? {
        if let opening = openingLesson, let skill = library.skill(opening.skill), !library.drills(for: skill.id).isEmpty {
            return skill
        }
        return focusSkill()
    }

    /// The next skill on the journey, or the one that needs the most work.
    func focusSkill() -> Skill? {
        let skills = library.orderedSkills.filter { !library.drills(for: $0.id).isEmpty }
        // Struggling with something already taught? That comes first.
        let struggling = skills.filter { skill in
            guard let record = progress.skills[skill.id], record.attempts >= Self.attemptsPerSkill else { return false }
            return record.rating < library.bands(for: skill.id).learned - 60
        }
        if let weakest = struggling.min(by: { gap($0) > gap($1) }) {
            return weakest
        }
        // Otherwise the next skill on the journey that hasn't had its turn.
        if let next = skills.first(where: { (progress.skills[$0.id]?.attempts ?? 0) < Self.attemptsPerSkill }) {
            return next
        }
        // Everything has had a turn: the least mastered, least recently practiced.
        return skills.min { a, b in
            let ma = Trainer.mastery(of: progress.skills[a.id], bands: library.bands(for: a.id))
            let mb = Trainer.mastery(of: progress.skills[b.id], bands: library.bands(for: b.id))
            if abs(ma - mb) > 0.05 { return ma < mb }
            let da = progress.skills[a.id]?.lastPracticed ?? .distantPast
            let db = progress.skills[b.id]?.lastPracticed ?? .distantPast
            return da < db
        }
    }

    /// How far below its "learned" level a skill is.
    private func gap(_ skill: Skill) -> Double {
        library.bands(for: skill.id).learned - (progress.skills[skill.id]?.rating ?? Trainer.startingRating)
    }

    /// Skills that have been taught or practiced a little.
    func learnedSkills() -> [Skill] {
        library.orderedSkills.filter { skill in
            progress.lessonsDone[skill.lesson] != nil || (progress.skills[skill.id]?.attempts ?? 0) >= 3
        }.filter { !library.drills(for: $0.id).isEmpty }
    }

    func dueMistakes() -> [GameMistake] {
        progress.mistakes.filter { !$0.fixed && $0.due <= now }.sorted { $0.due < $1.due }
    }

    /// Drills due for review: missed ones (low boxes) first, then the oldest.
    func dueDrills(excluding used: Set<String>) -> [Drill] {
        progress.items
            .filter { $0.value.due <= now && !used.contains($0.key) }
            .sorted { a, b in a.value.box != b.value.box ? a.value.box < b.value.box : a.value.due < b.value.due }
            .compactMap { library.drill($0.key) }
    }

    /// A drill from `skills` whose chance of being solved is closest to `target`.
    /// New drills first; seen ones only when a skill runs out.
    mutating func pick(from skills: [String], target: Double, used: inout Set<String>) -> Drill? {
        guard !skills.isEmpty else { return nil }
        func candidates(includeSeen: Bool) -> [(drill: Drill, distance: Double)] {
            skills.flatMap { skill -> [(drill: Drill, distance: Double)] in
                let rating = progress.skills[skill]?.rating ?? Trainer.startingRating
                return library.drills(for: skill).compactMap { drill in
                    guard !used.contains(drill.id) else { return nil }
                    if !includeSeen, progress.items[drill.id] != nil { return nil }
                    let chance = Trainer.expected(rating: rating, difficulty: Double(drill.rating))
                    return (drill, abs(chance - target))
                }
            }
        }
        var pool = candidates(includeSeen: false)
        if pool.isEmpty {
            pool = candidates(includeSeen: true).sorted {
                (progress.items[$0.drill.id]?.lastSeen ?? .distantPast) < (progress.items[$1.drill.id]?.lastSeen ?? .distantPast)
            }
            pool = Array(pool.prefix(10))
        }
        pool.sort { $0.distance < $1.distance }
        let shortlist = pool.prefix(4)
        guard !shortlist.isEmpty else { return nil }
        let choice = shortlist[Int(random.next() % UInt64(shortlist.count))].drill
        used.insert(choice.id)
        return choice
    }
}

/// Small repeatable random numbers (SplitMix64), so tests get the same sessions.
struct TrainingRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
