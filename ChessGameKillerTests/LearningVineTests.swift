import XCTest
@testable import ChessGameKiller

/// The vine on Learn: leaves from the training diary, lessons and endgames; the flower and buds.
@MainActor
final class LearningVineTests: XCTestCase {
    private let day: TimeInterval = 86_400

    private func store(_ progress: TrainingProgress = TrainingProgress()) -> TrainingStore {
        TrainingStore(library: TrainingLibrary.shared, progress: progress)
    }

    private func emptyEndgames() -> EndgameProgress {
        EndgameProgress(studies: GrandmasterContent.shared.endgames, records: [:])
    }

    func testTrainingWritesTheDiary() throws {
        let library = try XCTUnwrap(TrainingLibrary.shared)
        let store = store()
        let lesson = try XCTUnwrap(library.lessons.first)
        store.completeLesson(lesson.id)
        store.finishSession(accuracy: 0.8, title: "Forks")
        store.recordPractice(xp: 6)
        let key = Trainer.dayString(.now)
        let note = try XCTUnwrap(store.progress.days[key])
        XCTAssertEqual(note.highlights, [lesson.title, "Forks"])
        XCTAssertGreaterThan(note.xp, 6)
        // The same thing twice in a day is written once.
        store.note("Forks")
        XCTAssertEqual(store.progress.days[key]?.highlights.count, 2)
    }

    func testOldProgressWithoutADiaryStillLoads() throws {
        let data = Data(#"{"xp": 40}"#.utf8)
        let progress = try JSONDecoder().decode(TrainingProgress.self, from: data)
        XCTAssertEqual(progress.xp, 40)
        XCTAssertTrue(progress.days.isEmpty)
    }

    func testLeavesComeFromTheDiaryLessonsAndEndgamesNewestFirst() throws {
        let library = try XCTUnwrap(TrainingLibrary.shared)
        var progress = TrainingProgress()
        let lesson = try XCTUnwrap(library.lessons.first)
        progress.lessonsDone[lesson.id] = .now.addingTimeInterval(-3 * day)
        progress.days[Trainer.dayString(.now)] = DayNote(xp: 30, highlights: ["Their threats"])
        progress.days[Trainer.dayString(.now.addingTimeInterval(-1 * day))] = DayNote(xp: 12)
        let studies = GrandmasterContent.shared.endgames
        let study = try XCTUnwrap(studies.first)
        let endgames = EndgameProgress(studies: studies, records: [study.id: EndgameRecord(date: .now.addingTimeInterval(-2 * day), moves: 10, clean: true)])
        let vine = LearningVine.make(progress: progress, library: library, endgames: endgames,
                                     today: nil, trainedToday: true, lessonsOpen: false)
        XCTAssertEqual(vine.leaves.map(\.title), ["Their threats", "Puzzles and practice", study.title, lesson.title])
        XCTAssertEqual(vine.leaves[1].detail, "+12 XP")
        XCTAssertEqual(vine.daysThisWeek(), 4)
    }

    func testTheFlowerIsTodaysPlanThenTheNextLesson() throws {
        let library = try XCTUnwrap(TrainingLibrary.shared)
        let store = store()
        let plan = SessionPlan(title: "Today", focus: nil, lesson: nil, items: [], headline: "Forks")
        // An empty plan is no flower; the next lesson blooms instead.
        let vine = LearningVine.make(progress: store.progress, library: library, endgames: emptyEndgames(),
                                     today: plan, trainedToday: false, lessonsOpen: true)
        XCTAssertEqual(vine.bloom?.title, library.lessons.first?.title)
        if let today = store.dailyPlan(), !today.isEmpty {
            let planned = LearningVine.make(progress: store.progress, library: library, endgames: emptyEndgames(),
                                            today: today, trainedToday: false, lessonsOpen: true)
            XCTAssertTrue(planned.bloom?.detail.hasPrefix("Today") == true)
        }
    }

    func testAFreePlayerSeesAPremiumBudAndPremiumDoesNot() throws {
        let library = try XCTUnwrap(TrainingLibrary.shared)
        let progress = TrainingProgress()
        let free = LearningVine.make(progress: progress, library: library, endgames: emptyEndgames(),
                                     today: nil, trainedToday: true, lessonsOpen: false)
        let bud = try XCTUnwrap(free.buds.last)
        XCTAssertTrue(bud.premium)
        XCTAssertEqual(bud.title, "\(library.lessons.count - TrainingLibrary.freeLessonCount) more lessons")
        let open = LearningVine.make(progress: progress, library: library, endgames: emptyEndgames(),
                                     today: nil, trainedToday: true, lessonsOpen: true)
        XCTAssertFalse(open.buds.contains { $0.premium })
        XCTAssertTrue(open.buds.contains { $0.title.hasSuffix("rank") })
    }

    func testDayLabels() {
        let now = Date.now
        XCTAssertEqual(LearningVine.dayLabel(now, now: now), "Today")
        XCTAssertEqual(LearningVine.dayLabel(now.addingTimeInterval(-day), now: now), "Yesterday")
    }
}
