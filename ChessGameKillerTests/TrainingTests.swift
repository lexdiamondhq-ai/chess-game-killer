import ChessKit
import XCTest
@testable import ChessGameKiller

/// The bundled course. TRAINING_CONTENT can point the tests at a content folder instead.
@MainActor
private func loadLibrary() throws -> TrainingLibrary {
    if let path = ProcessInfo.processInfo.environment["TRAINING_CONTENT"], let bundle = Bundle(path: path) {
        return try TrainingLibrary.load(from: bundle)
    }
    return try XCTUnwrap(TrainingLibrary.shared, "The training content didn't load")
}

private let day: TimeInterval = 24 * 60 * 60

/// Noon on a fixed day, far from midnight so calendar math is predictable.
private func noon(_ offset: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 12))!
    return start.addingTimeInterval(Double(offset) * day)
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

// MARK: Content

@MainActor
final class TrainingContentTests: XCTestCase {

    func testTheCourseLoads() throws {
        let library = try loadLibrary()
        XCTAssertEqual(library.coach.name, "Leo")
        XCTAssertEqual(library.course.habit.map(\.id), ["red", "yellow", "green"])
        XCTAssertEqual(library.lessons.count, library.course.units.flatMap(\.lessons).count)
        XCTAssertEqual(library.lessons.first?.id, "welcome")
        XCTAssertEqual(library.rank(forXP: 0).id, "pawn")
    }

    func testEverySkillHasALessonAndDrills() throws {
        let library = try loadLibrary()
        for skill in library.course.skills {
            XCTAssertNotNil(library.lesson(skill.lesson), "\(skill.id) points to a missing lesson")
            XCTAssertFalse(library.drills(for: skill.id).isEmpty, "\(skill.id) has no drills")
            XCTAssertNotNil(library.unit(containingSkill: skill.id), "\(skill.id) isn't in any unit")
        }
    }

    func testEveryLessonPlays() throws {
        let library = try loadLibrary()
        for lesson in library.lessons {
            XCTAssertNotNil(LessonPlayer.startPositions(of: lesson), "\(lesson.id) has a move that doesn't fit")
            XCTAssertNotNil(LessonPlayer(lesson: lesson, playsSounds: false), "\(lesson.id) won't play")
            XCTAssertNotNil(library.skill(lesson.skill), "\(lesson.id) has an unknown skill")
        }
    }

    func testEveryDrillLoads() throws {
        let library = try loadLibrary()
        XCTAssertGreaterThan(library.drills.count, 500)
        for drill in library.drills {
            let item = SessionItem(content: .drill(drill), role: .focus)
            XCTAssertNotNil(DrillRunner(item: item, library: library, engine: nil, playsSounds: false),
                            "\(drill.id) won't load")
        }
    }

    func testTheCoachHasWordsForEveryMoment() throws {
        let library = try loadLibrary()
        for kind in CoachMoment.Kind.allCases {
            XCTAssertNotNil(library.moment(kind.rawValue), "No words for \(kind)")
        }
    }

    func testRecordingsAreNamedByTheirText() {
        // make_narration.py names files the same way.
        XCTAssertEqual(CoachVoice.fileName(for: "Hello"), "nar-f7ff9e8b7bb2")
        XCTAssertEqual(CoachVoice.fileName(for: "Exactly right."), CoachVoice.fileName(for: "Exactly right."))
    }
}

// MARK: Rules

final class TrainerTests: XCTestCase {

    func testEqualRatingsAreAFiftyFiftyChance() {
        XCTAssertEqual(Trainer.expected(rating: 800, difficulty: 800), 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(Trainer.expected(rating: 800, difficulty: 600), 0.7)
    }

    func testSolvingRaisesTheRatingAndMissingLowersIt() {
        let start = SkillRecord()
        let up = Trainer.updated(start, difficulty: 600, outcome: .firstTry, at: noon())
        let down = Trainer.updated(start, difficulty: 600, outcome: .missed, at: noon())
        XCTAssertGreaterThan(up.rating, start.rating)
        XCTAssertLessThan(down.rating, start.rating)
        XCTAssertEqual(up.attempts, 1)
        XCTAssertEqual(up.solved, 1)
        XCTAssertEqual(down.solved, 0)
        // A hint counts for less than solving alone.
        let hinted = Trainer.updated(start, difficulty: 600, outcome: .withHint, at: noon())
        XCTAssertLessThan(hinted.rating, up.rating)
    }

    func testReviewsSpreadOutAndMissesComeBackTomorrow() {
        var box = 0
        var gaps: [Int] = []
        for _ in 0..<4 {
            let next = Trainer.scheduled(box: box, outcome: .firstTry, at: noon(), calendar: utc)
            gaps.append(Int((next.due.timeIntervalSince(noon()) / day).rounded()))
            box = next.box
        }
        XCTAssertEqual(gaps, [1, 3, 7, 16])
        let missed = Trainer.scheduled(box: 4, outcome: .missed, at: noon(), calendar: utc)
        XCTAssertEqual(missed.box, 1)
        XCTAssertEqual(missed.due, noon(1))
    }

    func testStreaksCountDaysInARow() {
        var streak = Streak()
        for offset in 0..<3 {
            streak = Trainer.streak(streak, trainingOn: noon(offset), calendar: utc).streak
        }
        XCTAssertEqual(streak.current, 3)
        // Training twice in a day still counts once.
        streak = Trainer.streak(streak, trainingOn: noon(2).addingTimeInterval(3600), calendar: utc).streak
        XCTAssertEqual(streak.current, 3)
    }

    func testOneMissedDayIsARestDay() {
        var streak = Streak()
        streak = Trainer.streak(streak, trainingOn: noon(0), calendar: utc).streak
        streak = Trainer.streak(streak, trainingOn: noon(1), calendar: utc).streak
        let result = Trainer.streak(streak, trainingOn: noon(3), calendar: utc)
        XCTAssertTrue(result.usedRestDay)
        XCTAssertEqual(result.streak.current, 3)
        // Only one a week: missing another day soon after starts over.
        let again = Trainer.streak(result.streak, trainingOn: noon(5), calendar: utc)
        XCTAssertFalse(again.usedRestDay)
        XCTAssertEqual(again.streak.current, 1)
    }

    func testTwoMissedDaysStartOver() {
        var streak = Streak()
        streak = Trainer.streak(streak, trainingOn: noon(0), calendar: utc).streak
        streak = Trainer.streak(streak, trainingOn: noon(3), calendar: utc).streak
        XCTAssertEqual(streak.current, 1)
        XCTAssertFalse(Trainer.isAlive(streak, on: noon(6), calendar: utc))
    }

    func testADayThatGoesBackwardsIsTheSameDay() {
        var streak = Streak()
        streak = Trainer.streak(streak, trainingOn: noon(0), calendar: utc).streak
        streak = Trainer.streak(streak, trainingOn: noon(1), calendar: utc).streak
        // Flying west can make the local date yesterday again. That's no break.
        let back = Trainer.streak(streak, trainingOn: noon(0), calendar: utc)
        XCTAssertEqual(back.streak.current, 2)
        XCTAssertEqual(back.streak.lastDay, streak.lastDay)
        XCTAssertFalse(back.usedRestDay)
        // And the next day still counts once the clock catches up.
        XCTAssertEqual(Trainer.streak(back.streak, trainingOn: noon(2), calendar: utc).streak.current, 3)
    }
}

// MARK: Board geometry

final class BoardGeometryTests: XCTestCase {

    func testAKingOnlyForksUndefendedPieces() throws {
        // The rook is guarded by the c6 pawn and the knight by the g6 pawn: no fork.
        let guarded = try XCTUnwrap(BoardGeometry(fen: "8/8/2p3p1/3r1n2/4K3/8/8/7k b - - 1 1"))
        XCTAssertTrue(guarded.forkTargets(from: .e4).isEmpty)
        // Loose pieces next to the king really are forked.
        let loose = try XCTUnwrap(BoardGeometry(fen: "8/8/8/3r4/4K3/5n2/8/7k b - - 1 1"))
        XCTAssertEqual(Set(loose.forkTargets(from: .e4)), [.d5, .f3])
    }

    func testAKnightForksTheKingAndARook() throws {
        let board = try XCTUnwrap(BoardGeometry(fen: "r3k3/2N5/8/8/8/8/8/4K3 b - - 0 1"))
        XCTAssertEqual(Set(board.forkTargets(from: .c7)), [.a8, .e8])
    }
}

// MARK: Planning

@MainActor
final class TrainingPlannerTests: XCTestCase {

    func testTheFirstSessionOpensWithTheWelcomeLesson() throws {
        let library = try loadLibrary()
        var planner = TrainingPlanner(library: library, progress: TrainingProgress(), now: noon(), seed: 1)
        let plan = planner.dailySession()
        XCTAssertEqual(plan.lesson?.id, "welcome")
        XCTAssertEqual(plan.focus?.id, library.lesson("welcome")?.skill)
        XCTAssertGreaterThanOrEqual(plan.items.count, 4)
        XCTAssertEqual(plan.items.last?.role, .finisher)
    }

    func testAfterThatTheJourneyStartsAtTheBeginning() throws {
        let library = try loadLibrary()
        var progress = TrainingProgress()
        progress.lessonsDone["welcome"] = noon()
        progress.sessionsDone = 1
        var planner = TrainingPlanner(library: library, progress: progress, now: noon(), seed: 1)
        let plan = planner.dailySession()
        XCTAssertEqual(plan.focus?.id, library.orderedSkills.first?.id)
        XCTAssertEqual(plan.lesson?.id, plan.focus?.lesson)
    }

    func testTheFocusMovesOnAfterEnoughPractice() throws {
        let library = try loadLibrary()
        let skills = library.orderedSkills
        var progress = TrainingProgress()
        progress.sessionsDone = 3
        progress.skills[skills[0].id] = SkillRecord(rating: 900, attempts: TrainingPlanner.attemptsPerSkill)
        let planner = TrainingPlanner(library: library, progress: progress, now: noon(), seed: 1)
        XCTAssertEqual(planner.focusSkill()?.id, skills[1].id)
    }

    func testAStrugglingSkillComesBackFirst() throws {
        let library = try loadLibrary()
        let skills = library.orderedSkills
        var progress = TrainingProgress()
        progress.sessionsDone = 5
        progress.skills[skills[0].id] = SkillRecord(rating: 900, attempts: 10)
        progress.skills[skills[1].id] = SkillRecord(rating: 250, attempts: 10)
        let planner = TrainingPlanner(library: library, progress: progress, now: noon(), seed: 1)
        XCTAssertEqual(planner.focusSkill()?.id, skills[1].id)
    }

    func testSessionsAreRepeatableWithTheSameSeed() throws {
        let library = try loadLibrary()
        var a = TrainingPlanner(library: library, progress: TrainingProgress(), now: noon(), seed: 42)
        var b = TrainingPlanner(library: library, progress: TrainingProgress(), now: noon(), seed: 42)
        XCTAssertEqual(a.dailySession().items.map(\.id), b.dailySession().items.map(\.id))
    }

    func testSessionsNeverRepeatADrill() throws {
        let library = try loadLibrary()
        var progress = TrainingProgress()
        progress.sessionsDone = 2
        progress.lessonsDone = Dictionary(uniqueKeysWithValues: library.lessons.map { ($0.id, noon()) })
        var planner = TrainingPlanner(library: library, progress: progress, now: noon(), seed: 7)
        let ids = planner.dailySession().items.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        // With every lesson done there's a warm-up and a mixed drill too.
        XCTAssertEqual(planner.dailySession().items.first?.role, .warmUp)
    }

    func testGameMistakesComeBackInTheNextSession() throws {
        let library = try loadLibrary()
        var progress = TrainingProgress()
        progress.sessionsDone = 1
        progress.mistakes = [GameMistake(id: "m1", fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", best: "a1a8",
                                         played: "h2h3", skill: "back-rank", title: "You had checkmate!",
                                         created: noon(), due: noon())]
        var planner = TrainingPlanner(library: library, progress: progress, now: noon(), seed: 3)
        let plan = planner.dailySession()
        XCTAssertTrue(plan.items.contains { $0.id == "m-m1" && $0.role == .review })
        XCTAssertEqual(planner.mistakesSession().items.map(\.id), ["m-m1"])
    }

    func testFocusDrillsAimForFourInFive() throws {
        let library = try loadLibrary()
        let skill = try XCTUnwrap(library.orderedSkills.first)
        var progress = TrainingProgress()
        progress.sessionsDone = 1
        progress.skills[skill.id] = SkillRecord(rating: 700, attempts: 2)
        var planner = TrainingPlanner(library: library, progress: progress, now: noon(), seed: 9)
        let plan = planner.practice(skill)
        let focus = plan.items.filter { $0.role == .focus }
        XCTAssertFalse(focus.isEmpty)
        let bestPossible = library.drills(for: skill.id)
            .map { abs(Trainer.expected(rating: 700, difficulty: Double($0.rating)) - TrainingPlanner.focusTarget) }
            .min() ?? 0
        for item in focus {
            guard case .drill(let drill) = item.content else { return XCTFail("expected a drill") }
            let chance = Trainer.expected(rating: 700, difficulty: Double(drill.rating))
            XCTAssertLessThan(abs(chance - TrainingPlanner.focusTarget), bestPossible + 0.15)
        }
    }
}

// MARK: The learner's record

@MainActor
final class TrainingStoreTests: XCTestCase {

    private func store() throws -> TrainingStore {
        TrainingStore(library: try loadLibrary(), calendar: utc)
    }

    func testADrillEarnsXPAndComesBackLater() throws {
        let store = try store()
        let drill = try XCTUnwrap(store.library?.drills.first)
        let reward = store.record(drill, outcome: .firstTry, at: noon())
        XCTAssertEqual(reward.xp, Outcome.firstTry.xp)
        XCTAssertEqual(reward.streak, 1)
        XCTAssertEqual(store.progress.items[drill.id]?.box, 1)
        XCTAssertEqual(store.progress.items[drill.id]?.due, noon(1))
        XCTAssertEqual(store.progress.skills[drill.skill]?.attempts, 1)
    }

    func testMissingStillEarnsSomething() throws {
        let store = try store()
        let drill = try XCTUnwrap(store.library?.drills.first)
        XCTAssertGreaterThan(store.record(drill, outcome: .missed, at: noon()).xp, 0)
    }

    func testLessonsPayMoreTheFirstTime() throws {
        let store = try store()
        XCTAssertEqual(store.completeLesson("welcome", at: noon()).xp, Trainer.lessonXP)
        XCTAssertLessThan(store.completeLesson("welcome", at: noon()).xp, Trainer.lessonXP)
        XCTAssertTrue(store.isDone("welcome"))
    }

    func testEnoughXPIsAPromotion() throws {
        let store = try store()
        let knight = try XCTUnwrap(store.library?.course.ranks.first { $0.id == "knight" })
        var promotion: Rank?
        var date = noon()
        while store.progress.xp < knight.xp {
            let reward = store.completeLesson(UUID().uuidString, at: date)
            promotion = reward.promotion ?? promotion
            date = date.addingTimeInterval(60)
        }
        XCTAssertEqual(promotion?.id, "knight")
        XCTAssertEqual(store.rank?.id, "knight")
    }

    func testAMistakeIsSavedOnce() throws {
        let store = try store()
        let fen = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
        XCTAssertTrue(store.addMistake(fen: fen, best: "a1a8", played: "h2h3", skill: "back-rank", title: "Mate", at: noon()))
        XCTAssertFalse(store.addMistake(fen: fen, best: "a1a8", played: "g2g3", skill: "back-rank", title: "Mate", at: noon()))
        XCTAssertEqual(store.openMistakes.count, 1)
    }

    func testAMistakeIsFixedAfterThreeCleanSolves() throws {
        let store = try store()
        store.addMistake(fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", best: "a1a8", played: "h2h3",
                         skill: "back-rank", title: "Mate", at: noon())
        for offset in [0, 1, 4] {
            let mistake = try XCTUnwrap(store.openMistakes.first)
            store.record(mistake: mistake, outcome: .firstTry, at: noon(offset))
        }
        XCTAssertTrue(store.openMistakes.isEmpty)
        XCTAssertEqual(store.progress.mistakes.first?.fixed, true)
    }

    func testThreeSolvesInOneDayDoNotFixAMistake() throws {
        let store = try store()
        store.addMistake(fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", best: "a1a8", played: "h2h3",
                         skill: "back-rank", title: "Mate", at: noon())
        for _ in 0..<3 {
            let mistake = try XCTUnwrap(store.openMistakes.first)
            store.record(mistake: mistake, outcome: .firstTry, at: noon())
        }
        XCTAssertEqual(store.openMistakes.count, 1)
        XCTAssertEqual(store.openMistakes.first?.box, 1)
    }

    func testTheTodayCardNamesTheLessonTheSessionOpensWith() throws {
        let store = try store()
        // A brand-new learner starts with the welcome lesson, whatever skill is in focus.
        XCTAssertEqual(store.todaysLesson?.id, "welcome")
        XCTAssertEqual(store.todaysLesson?.id, store.dailyPlan()?.lesson?.id)
        XCTAssertEqual(store.todaysMinutes, store.dailyPlan()?.minutes ?? 0)
        store.completeLesson("welcome", at: noon())
        store.finishSession(accuracy: 1, at: noon())
        XCTAssertEqual(store.todaysLesson?.id, store.todaysFocus?.lesson)
        XCTAssertEqual(store.todaysLesson?.id, store.dailyPlan()?.lesson?.id)
    }

    func testProgressIsSavedAndReadBack() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("training-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TrainingStore(library: try loadLibrary(), fileURL: url, calendar: utc)
        store.completeLesson("welcome", at: noon())
        let saved = try JSONDecoder().decode(TrainingProgress.self, from: Data(contentsOf: url))
        XCTAssertEqual(saved, store.progress)
    }
}

// MARK: The coach in games

final class CoachMomentTests: XCTestCase {

    private func review(_ grade: MoveReview.Grade, played: String, fen: String, best: String? = nil,
                        before: Evaluation? = nil, after: Evaluation? = nil, reply: String? = nil) -> MoveReview {
        let fenAfter = TrainingChess.fen(after: [played], from: fen)
        return MoveReview(id: 1, grade: grade, played: Notation.san(of: played, fen: fen) ?? played,
                          best: best.flatMap { Notation.san(of: $0, fen: fen) }, evaluation: after,
                          fenBefore: fen, fenAfter: fenAfter, playedUCI: played, bestUCI: best,
                          before: before, reply: reply)
    }

    func testAMissedMateIsNamed() {
        let found = MomentFinder.find(in: review(.blunder, played: "h2h3", fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1",
                                                 best: "a1a8", before: .mate(1), after: .centipawns(400)))
        XCTAssertEqual(found?.kind, .missedMate)
        XCTAssertEqual(found?.skill, "mate-in-1")
        XCTAssertEqual(found?.values["best"], "Ra8#")
    }

    func testAHangingPieceIsNamed() {
        // 1.e4 e5 2.Nf3 Nc6 3.Bc4 h6, then 4.Ng5?? hxg5.
        let fen = "r1bqkbnr/pppp1pp1/2n4p/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4"
        let found = MomentFinder.find(in: review(.mistake, played: "f3g5", fen: fen, best: "d2d3",
                                                 before: .centipawns(40), after: .centipawns(-250), reply: "h6g5"))
        XCTAssertEqual(found?.kind, .hungPiece)
        XCTAssertEqual(found?.values["piece"], "knight")
        XCTAssertEqual(found?.values["square"], "g5")
    }

    func testADefendedPieceIsNotCalledFree() {
        // The a8 rook is covered by the queen along the back rank, so the knight
        // could take it but it wasn't unprotected.
        let fen = "r2qkbnr/pppppppp/1N6/8/8/8/PPPPPPPP/R1BQKBNR w KQkq - 0 1"
        let found = MomentFinder.find(in: review(.mistake, played: "a2a3", fen: fen, best: "b6a8",
                                                 before: .centipawns(200), after: .centipawns(-100)))
        XCTAssertNotEqual(found?.kind, .missedFreePiece)
    }

    func testAFreePieceTakenIsPraised() {
        // 1.e4 e5 2.Nf3 Qh4?? 3.Nxh4.
        let fen = "rnb1kbnr/pppp1ppp/8/4p3/4P2q/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3"
        let found = MomentFinder.find(in: review(.best, played: "f3h4", fen: fen, after: .centipawns(900)))
        XCTAssertEqual(found?.kind, .foundFreePiece)
        XCTAssertEqual(found?.values["piece"], "queen")
    }

    func testCastlingIsPraised() {
        let fen = "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
        XCTAssertEqual(MomentFinder.find(in: review(.best, played: "e1g1", fen: fen, after: .centipawns(30)))?.kind, .castled)
    }

    func testAnOrdinaryGoodMoveNeedsNoComment() {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        XCTAssertNil(MomentFinder.find(in: review(.good, played: "e2e4", fen: fen, after: .centipawns(30))))
    }

    func testTheWordsFillIn() {
        XCTAssertEqual(MomentFinder.fill("{best} wins the {piece}.", with: ["best": "Nxh4", "piece": "queen"]),
                       "Nxh4 wins the queen.")
    }
}

final class TrafficLightTests: XCTestCase {

    func testTheRedLightSeesWhatTheirMoveAttacks() throws {
        // 1.e4 e5 2.Nf3 Nc6 3.Bc4 Nf6 4.d3 Bc5 5.Nc3 d6 6.Bg5 h6: the pawn hits the bishop.
        let fen = "r1bqk2r/ppp2pp1/2np1n1p/2b1p1B1/2B1P3/2NP1N2/PPP2PPP/R2QK2R w KQkq - 0 7"
        let scan = try XCTUnwrap(TrafficLightScan(fen: fen, lastMove: LastMove(from: .h7, to: .h6)))
        XCTAssertTrue(scan.red.contains { $0.contains("bishop") && $0.contains("h6") }, "\(scan.red)")
    }

    func testTheRedLightSeesAMateThreat() throws {
        // Scholar's Mate is coming: 1.e4 e5 2.Bc4 Nc6 3.Qh5, Black to move.
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 3 3"
        let scan = try XCTUnwrap(TrafficLightScan(fen: fen, lastMove: LastMove(from: .d1, to: .h5)))
        XCTAssertTrue(scan.red.contains { $0.contains("checkmate") }, "\(scan.red)")
    }

    func testAQuietPositionHasNoThreats() throws {
        let scan = try XCTUnwrap(TrafficLightScan(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", lastMove: nil))
        XCTAssertEqual(scan.red.count, 1)
        XCTAssertTrue(scan.red[0].hasPrefix("No threats"))
    }
}

// MARK: Drills

@MainActor
final class DrillRunnerTests: XCTestCase {

    private func runner(_ json: String) throws -> DrillRunner {
        let drill = try JSONDecoder().decode(Drill.self, from: Data(json.utf8))
        return try XCTUnwrap(DrillRunner(item: SessionItem(content: .drill(drill), role: .focus), library: nil,
                                         engine: nil, playsSounds: false))
    }

    private func started(_ runner: DrillRunner) async throws {
        runner.begin()
        for _ in 0..<40 where runner.phase != .solving {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(runner.phase, .solving)
    }

    private func move(_ runner: DrillRunner, _ uci: String) {
        guard let squares = Notation.squares(of: uci) else { return XCTFail("bad move \(uci)") }
        runner.tap(squares.from)
        runner.tap(squares.to)
    }

    private let backRank = """
    {"id": "t-1", "skill": "back-rank", "type": "move", "rating": 500, "fen": "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "solution": ["a1a8"], "mate": 1}
    """

    func testTheRightMoveSolvesIt() async throws {
        let runner = try runner(backRank)
        XCTAssertEqual(runner.learner, .white)
        try await started(runner)
        move(runner, "a1a8")
        XCTAssertEqual(runner.outcome, .firstTry)
    }

    func testAWrongMoveIsTakenBackForAnotherTry() async throws {
        let runner = try runner(backRank)
        try await started(runner)
        let start = runner.game.fen
        move(runner, "h2h3")
        XCTAssertEqual(runner.mistakes, 1)
        XCTAssertNotEqual(runner.game.fen, start)
        for _ in 0..<40 where runner.phase != .solving {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(runner.phase, .solving)
        XCTAssertEqual(runner.game.fen, start)
        move(runner, "a1a8")
        XCTAssertEqual(runner.outcome, .afterMistake)
    }

    func testTwoMissesScoreBelowOneEvenWithTheFreeHint() async throws {
        let runner = try runner(backRank)
        try await started(runner)
        for wrong in ["h2h3", "g2g3"] {
            move(runner, wrong)
            for _ in 0..<40 where runner.phase != .solving {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        XCTAssertEqual(runner.mistakes, 2)
        // The second miss hands out a hint, which mustn't make the result look better.
        XCTAssertTrue(runner.usedHint)
        move(runner, "a1a8")
        XCTAssertEqual(runner.outcome, .afterMistake)
    }

    func testTheOpponentsMoveComesFirst() async throws {
        // Black blunders the queen with ...Qh4, then it's White's turn.
        let runner = try runner("""
        {"id": "t-2", "skill": "free-pieces", "type": "move", "rating": 400,
         "fen": "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2", "setup": "d8h4", "solution": ["f3h4"]}
        """)
        XCTAssertEqual(runner.learner, .white)
        try await started(runner)
        XCTAssertEqual(runner.game.moveCount, 1)
        move(runner, "f3h4")
        XCTAssertEqual(runner.outcome, .firstTry)
    }

    func testYesOrNoDrills() async throws {
        let runner = try runner("""
        {"id": "t-3", "skill": "safety", "type": "safe", "rating": 500,
         "fen": "r1bqkbnr/pppp1pp1/2n4p/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4",
         "move": "f3g5", "answer": false, "reply": "h6g5", "explain": "The h6 pawn takes it."}
        """)
        try await started(runner)
        runner.answer(false)
        for _ in 0..<60 where !runner.isDone {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(runner.outcome, .firstTry)
        XCTAssertTrue(runner.message.contains("The h6 pawn takes it."))
    }

    func testTapDrillsWantEveryPieceInDanger() async throws {
        let runner = try runner("""
        {"id": "t-4", "skill": "threats", "type": "tap", "rating": 500,
         "fen": "r1bqk2r/ppp2ppp/2np1n2/2b1p1B1/2B1P3/2NP1N2/PPP2PPP/R2QK2R b KQkq - 1 6", "setup": "h7h6", "squares": ["g5"]}
        """)
        try await started(runner)
        runner.tap(.c4)
        XCTAssertEqual(runner.mistakes, 1)
        runner.tap(.g5)
        XCTAssertEqual(runner.outcome, .afterMistake)
    }

    func testTapDrillsPointAtTheRealAttacker() async throws {
        // The knight steps aside and the bishop behind it hits the rook.
        let runner = try runner("""
        {"id": "t-6", "skill": "threats", "type": "tap", "rating": 500,
         "fen": "7k/8/5r2/8/3N4/8/1B6/6K1 w - - 0 1", "setup": "d4c6", "squares": ["f6"]}
        """)
        XCTAssertEqual(runner.learner, .black)
        try await started(runner)
        runner.hint()
        XCTAssertEqual(runner.marks.map(\.square), ["b2"])
        XCTAssertTrue(runner.message.contains("bishop on b2"), runner.message)
        runner.tap(.f6)
        XCTAssertEqual(runner.outcome, .withHint)
        XCTAssertEqual(runner.arrows.map(\.from), ["b2"])
        XCTAssertEqual(runner.arrows.map(\.to), ["f6"])
    }

    func testYesOrNoDrillsNameTheMoveFromTheStart() throws {
        // The question is ready before the setup move has even been played.
        let runner = try runner("""
        {"id": "t-7", "skill": "safety", "type": "safe", "rating": 500, "prompt": "Is {move} safe?",
         "fen": "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3",
         "setup": "h7h6", "move": "f3g5", "answer": false}
        """)
        XCTAssertEqual(runner.message, "Is Ng5 safe?")
    }

    func testAPlayoutCanBeGivenUp() async throws {
        let runner = try runner("""
        {"id": "t-8", "skill": "queen-mate", "type": "playout", "rating": 500,
         "fen": "8/8/8/4k3/8/8/8/4K2Q w - - 0 1", "limit": 10}
        """)
        try await started(runner)
        runner.reveal()
        XCTAssertEqual(runner.outcome, .missed)
        XCTAssertEqual(runner.tone, .hint)
        XCTAssertFalse(runner.acceptsTaps)
    }

    func testChoices() async throws {
        let runner = try runner("""
        {"id": "t-5", "skill": "opening", "type": "choice", "rating": 400,
         "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
         "options": [{"text": "Pawn to a4", "move": "a2a4", "correct": false, "why": "Edge pawn."},
                     {"text": "Pawn to e4", "move": "e2e4", "correct": true, "why": "Center!"}]}
        """)
        try await started(runner)
        runner.choose(0)
        XCTAssertEqual(runner.message, "Edge pawn.")
        XCTAssertFalse(runner.isDone)
        runner.choose(1)
        XCTAssertEqual(runner.outcome, .afterMistake)
    }
}

// MARK: Sessions

@MainActor
final class SessionRunnerTests: XCTestCase {

    private func runner(_ items: [SessionItem]) throws -> SessionRunner {
        let store = TrainingStore(library: try loadLibrary(), calendar: utc)
        let plan = SessionPlan(title: "Test", focus: nil, lesson: nil, items: items)
        return SessionRunner(plan: plan, store: store, engine: nil, playsSounds: false)
    }

    func testTwoMissesInARowBringAnEasierDrillAndANote() throws {
        let library = try loadLibrary()
        let skill = try XCTUnwrap(library.orderedSkills.first)
        let items = library.drills(for: skill.id).prefix(2).map { SessionItem(content: .drill($0), role: .focus) }
        let runner = try runner(items)
        runner.begin()
        runner.record(.missed)
        XCTAssertNil(runner.coachNote)
        runner.next()
        runner.record(.missed)
        XCTAssertEqual(runner.items.count, 3)
        XCTAssertEqual(runner.items[2].role, .warmUp)
        XCTAssertNotNil(runner.coachNote)
        runner.end()
    }

    func testNoNotePromisesAnEasierDrillWhenThereIsNone() throws {
        // Game mistakes with no pattern behind them have nothing lighter to offer.
        let items = ["m1", "m2"].map { id in
            SessionItem(content: .mistake(GameMistake(id: id, fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", best: "a1a8",
                                                      played: "h2h3", skill: "", title: "Find the better move",
                                                      created: noon(), due: noon())), role: .review)
        }
        let runner = try runner(items)
        runner.begin()
        runner.record(.missed)
        runner.next()
        runner.record(.missed)
        XCTAssertEqual(runner.items.count, 2)
        XCTAssertNil(runner.coachNote)
        runner.end()
    }

    func testOnlyAFinishedSessionEarnsTheBonus() throws {
        let library = try loadLibrary()
        let skill = try XCTUnwrap(library.orderedSkills.first)
        let items = library.drills(for: skill.id).prefix(3).map { SessionItem(content: .drill($0), role: .focus) }

        let quitter = try runner(items)
        quitter.begin()
        quitter.record(.firstTry)
        quitter.end()
        XCTAssertEqual(quitter.stage, .summary)
        XCTAssertTrue(quitter.endedEarly)
        XCTAssertEqual(quitter.store.progress.sessionsDone, 0)
        XCTAssertNil(quitter.store.progress.lastAccuracy)

        let finisher = try runner(items)
        finisher.begin()
        for _ in items {
            finisher.record(.firstTry)
            finisher.next()
        }
        XCTAssertEqual(finisher.stage, .summary)
        XCTAssertFalse(finisher.endedEarly)
        XCTAssertEqual(finisher.store.progress.sessionsDone, 1)
        XCTAssertGreaterThan(finisher.reward.xp, quitter.reward.xp * 3)
    }
}
