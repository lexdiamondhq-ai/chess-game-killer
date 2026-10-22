import Foundation

/// All the training content, loaded once from the app bundle.
final class TrainingLibrary {
    let course: Course
    /// Lessons in journey order.
    let lessons: [Lesson]
    let drills: [Drill]

    private let lessonsByID: [String: Lesson]
    private let skillsByID: [String: Skill]
    private let drillsBySkill: [String: [Drill]]
    private let bandsBySkill: [String: SkillBands]

    enum LoadError: Error, CustomStringConvertible {
        case missing(String)
        case unreadable(String, Error)

        var description: String {
            switch self {
            case .missing(let name): return "Missing training file \(name)"
            case .unreadable(let name, let error): return "Couldn't read \(name): \(error)"
            }
        }
    }

    init(course: Course, lessons: [Lesson], drills: [Drill]) {
        self.course = course
        self.drills = drills
        let byID = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lessonsByID = byID
        skillsByID = Dictionary(course.skills.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.lessons = course.units.flatMap(\.lessons).compactMap { byID[$0] }
        let grouped = Dictionary(grouping: drills, by: \.skill)
        drillsBySkill = grouped.mapValues { $0.sorted { $0.rating < $1.rating } }
        bandsBySkill = grouped.mapValues { SkillBands(ratings: $0.map(\.rating)) }
    }

    /// The app's content, or nil (with a log) if a file is missing or broken.
    static let shared: TrainingLibrary? = {
        do {
            return try load()
        } catch {
            NSLog("Training content failed to load: %@", "\(error)")
            return nil
        }
    }()

    static func load(from bundle: Bundle = .main) throws -> TrainingLibrary {
        let course: Course = try decode("course", from: bundle)
        var lessons: [Lesson] = []
        for id in course.units.flatMap(\.lessons) {
            lessons.append(try decode("lesson-\(id)", from: bundle))
        }
        let drills: DrillFile = try decode("drills", from: bundle)
        return TrainingLibrary(course: course, lessons: lessons, drills: drills.drills)
    }

    private static func decode<T: Decodable>(_ name: String, from bundle: Bundle) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw LoadError.missing("\(name).json")
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            throw LoadError.unreadable("\(name).json", error)
        }
    }

    // MARK: Lookups

    var coach: CoachProfile { course.coach }

    func lesson(_ id: String) -> Lesson? { lessonsByID[id] }

    func skill(_ id: String) -> Skill? { skillsByID[id] }

    /// Skills in the order the journey teaches them.
    var orderedSkills: [Skill] {
        var seen = Set<String>()
        return course.units.flatMap(\.skills).compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return skillsByID[id]
        }
    }

    func unit(containingSkill skill: String) -> CourseUnit? {
        course.units.first { $0.skills.contains(skill) }
    }

    func unit(containingLesson lesson: String) -> CourseUnit? {
        course.units.first { $0.lessons.contains(lesson) }
    }

    /// Drills for a skill, easiest first.
    func drills(for skill: String) -> [Drill] { drillsBySkill[skill] ?? [] }

    func drill(_ id: String) -> Drill? { drills.first { $0.id == id } }

    func bands(for skill: String) -> SkillBands { bandsBySkill[skill] ?? SkillBands(ratings: []) }

    func moment(_ kind: String) -> MomentText? { course.moments.first { $0.kind == kind } }

    func rank(forXP xp: Int) -> Rank {
        course.ranks.last { xp >= $0.xp } ?? course.ranks[0]
    }

    func nextRank(afterXP xp: Int) -> Rank? {
        course.ranks.first { $0.xp > xp }
    }
}

/// Rating levels for one skill, taken from how hard its own drills are,
/// so "strong at mate in two" means the same thing as "strong at forks".
struct SkillBands: Equatable {
    /// Comfortable with the easier third.
    let learned: Double
    /// Solves the typical drill.
    let strong: Double
    /// Solves the hard ones.
    let mastered: Double

    init(ratings: [Int]) {
        let sorted = ratings.sorted().map(Double.init)
        func percentile(_ p: Double, fallback: Double) -> Double {
            guard !sorted.isEmpty else { return fallback }
            let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * p).rounded())))
            return sorted[index]
        }
        learned = percentile(0.3, fallback: 600)
        strong = max(learned + 50, percentile(0.55, fallback: 800))
        mastered = max(strong + 50, percentile(0.8, fallback: 1000))
    }
}
