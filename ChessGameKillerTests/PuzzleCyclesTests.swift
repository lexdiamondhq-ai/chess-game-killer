import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// Cycles (the Woodpecker Method), the missed-puzzle review queue and per-theme
/// puzzle stats: the rules, as plain values.
final class PuzzleCyclesTests: XCTestCase {

    // MARK: Building a set

    func testASetIsMixedAndBelowThePlayersRating() throws {
        let library = try XCTUnwrap(PuzzleCycleSamples.pack(), "lichess-puzzles.csv isn't in the app")
        var generator = CycleTestGenerator(seed: 7)
        for (rating, size) in [(1000, 20), (1500, 40), (2100, 80), (400, 20), (2900, 20)] {
            let set = try XCTUnwrap(PuzzleCycleSet.make(from: library, size: size, rating: rating, avoid: [],
                                                         now: .now, using: &generator))
            let puzzles = set.puzzleIDs.compactMap(library.puzzle(id:))
            XCTAssertEqual(puzzles.count, size)
            XCTAssertEqual(Set(set.puzzleIDs).count, size, "No puzzle twice")
            XCTAssertEqual(set.level, min(2700, max(450, rating - 200)))
            for puzzle in puzzles {
                XCTAssertLessThanOrEqual(abs(puzzle.rating - set.level), 250, "\(puzzle.id) is far from \(set.level)")
                XCTAssertTrue((1...3).contains(puzzle.length), "\(puzzle.id) is \(puzzle.length) moves")
            }
            let mates = puzzles.filter(\.endsInMate).count
            XCTAssertLessThanOrEqual(mates, Int((Double(size) * 0.3).rounded()), "Not a set of mates")
            XCTAssertLessThanOrEqual(puzzles.filter { $0.mateIn == 1 }.count, Int((Double(size) * 0.1).rounded()))
            let motifs = Dictionary(grouping: puzzles, by: \.leadMotif)
            XCTAssertLessThanOrEqual(motifs.values.map(\.count).max() ?? 0, max(2, Int((Double(size) / 8).rounded(.up))))
            XCTAssertGreaterThanOrEqual(motifs.count, size / 4, "Several ideas, not a few")
            XCTAssertEqual(set.stage, .playing(cycle: 1, puzzle: 1))
            XCTAssertNil(set.currentRun?.target, "The first cycle is played at the player's own pace")
        }
    }

    func testASetAvoidsPuzzlesSeenLately() {
        let library = PuzzleCycleSamples.library(count: 60)
        let seen = Set(library.puzzles.prefix(30).map(\.id))
        var generator = CycleTestGenerator(seed: 1)
        let set = PuzzleCycleSet.make(from: library, size: 20, rating: 1000, avoid: seen, now: .now, using: &generator)
        XCTAssertEqual(set?.count, 20)
        XCTAssertTrue(Set(set?.puzzleIDs ?? []).isDisjoint(with: seen))
    }

    func testASmallPackStillMakesASet() {
        let library = PuzzleCycleSamples.library(count: 8)
        var generator = CycleTestGenerator(seed: 2)
        let everything = Set(library.puzzles.map(\.id))
        let set = PuzzleCycleSet.make(from: library, size: 20, rating: 1000, avoid: everything, now: .now, using: &generator)
        XCTAssertEqual(set?.count, 8, "Seen puzzles come back rather than no set at all")
        XCTAssertNil(PuzzleCycleSet.make(from: PuzzleLibrary(puzzles: []), size: 20, rating: 1000, avoid: [],
                                         now: .now, using: &generator))
    }

    // MARK: Cycles

    func testEachCycleAimsForHalfTheLastOne() throws {
        var set = PuzzleCycleSamples.set(count: 20)
        let start = PuzzleCycleSamples.day
        XCTAssertEqual(set.floor, 20 * (2 + 2 * 2), "Two-move puzzles: six seconds each at the fastest")
        try PuzzleCycleSamples.play(&set, secondsEach: 36, cleanEvery: 4, at: start)
        XCTAssertEqual(set.currentRun?.elapsed, 720)
        XCTAssertEqual(set.currentRun?.cleanCount, 15)
        XCTAssertEqual(set.currentRun?.accuracy ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(set.stage, .between(next: 2, target: 360))

        var generator = CycleTestGenerator(seed: 3)
        let first = try XCTUnwrap(set.currentRun?.order)
        XCTAssertTrue(set.startNextCycle(now: start, using: &generator))
        let second = try XCTUnwrap(set.currentRun)
        XCTAssertEqual(second.target, 360)
        XCTAssertEqual(Set(second.order), Set(first), "The same puzzles")
        XCTAssertNotEqual(second.order, first, "in a new order")
        XCTAssertNotEqual(second.order.first, first.last, "that doesn't open with the one just played")
        XCTAssertEqual(set.stage, .playing(cycle: 2, puzzle: 1))
        XCTAssertFalse(set.startNextCycle(now: start, using: &generator), "Not while a cycle is being played")

        // Faster each time, down to the floor, which ends the set.
        try PuzzleCycleSamples.play(&set, secondsEach: 15, cleanEvery: 0, at: start)
        XCTAssertEqual(set.stage, .between(next: 3, target: 150))
        XCTAssertEqual(set.currentRun?.beatTarget, true)
        XCTAssertTrue(set.startNextCycle(now: start, using: &generator))
        try PuzzleCycleSamples.play(&set, secondsEach: 8, cleanEvery: 0, at: start)
        XCTAssertEqual(set.stage, .between(next: 4, target: 120), "Half of 160 is under the floor")
        XCTAssertTrue(set.startNextCycle(now: start, using: &generator))
        try PuzzleCycleSamples.play(&set, secondsEach: 6, cleanEvery: 0, at: start)
        XCTAssertEqual(set.stage, .complete, "A cycle played against the floor is the last")
        XCTAssertTrue(set.isComplete)
        XCTAssertFalse(set.startNextCycle(now: start, using: &generator))
        XCTAssertEqual(set.finishedRuns.count, 4)
    }

    func testFiveCyclesAtMost() throws {
        var set = PuzzleCycleSamples.set(count: 20)
        var generator = CycleTestGenerator(seed: 4)
        var seconds: TimeInterval = 600
        for cycle in 1...5 {
            XCTAssertEqual(set.stage, .playing(cycle: cycle, puzzle: 1))
            try PuzzleCycleSamples.play(&set, secondsEach: seconds, cleanEvery: 0, at: PuzzleCycleSamples.day)
            seconds /= 1.5
            if cycle < 5 { XCTAssertTrue(set.startNextCycle(now: PuzzleCycleSamples.day, using: &generator)) }
        }
        XCTAssertEqual(set.stage, .complete)
        XCTAssertNil(set.nextTarget)
    }

    func testOnlyThePuzzleUpNextCounts() throws {
        var set = PuzzleCycleSamples.set(count: 20)
        let next = try XCTUnwrap(set.currentRun?.nextPuzzleID)
        let other = try XCTUnwrap(set.currentRun?.order.last)
        XCTAssertFalse(set.record(other, clean: true, seconds: 5, now: .now))
        XCTAssertTrue(set.record(next, clean: false, seconds: 5, now: .now))
        XCTAssertFalse(set.record(next, clean: true, seconds: 5, now: .now), "Recorded once")
        XCTAssertEqual(set.stage, .playing(cycle: 1, puzzle: 2))
    }

    func testLeavingPartWayKeepsTheTime() throws {
        var set = PuzzleCycleSamples.set(count: 20)
        let next = try XCTUnwrap(set.currentRun?.nextPuzzleID)
        set.carry(30)
        set.carry(12)
        XCTAssertEqual(set.currentRun?.elapsed, 42, "The clock shows the time already spent")
        XCTAssertTrue(set.record(next, clean: true, seconds: 8, now: .now))
        XCTAssertEqual(set.currentRun?.attempts.last?.seconds, 50)
        XCTAssertEqual(set.currentRun?.carried, 0)
        XCTAssertEqual(set.currentRun?.elapsed, 50)
    }

    func testStatusLines() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let morning = PuzzleCycleSamples.day.addingTimeInterval(9 * 3600)
        var set = PuzzleCycleSamples.set(count: 20)
        XCTAssertEqual(set.status(now: morning, calendar: calendar), "Cycle 1 · 1 of 20")
        try PuzzleCycleSamples.play(&set, secondsEach: 30, cleanEvery: 0, at: morning, stopAfter: 11)
        XCTAssertEqual(set.status(now: morning, calendar: calendar), "Cycle 1 · 12 of 20")
        try PuzzleCycleSamples.play(&set, secondsEach: 30, cleanEvery: 0, at: morning)
        XCTAssertTrue(set.restSuggested(now: morning.addingTimeInterval(3600), calendar: calendar))
        XCTAssertEqual(set.status(now: morning.addingTimeInterval(3600), calendar: calendar), "Cycle 2 tomorrow")
        let tomorrow = morning.addingTimeInterval(86_400)
        XCTAssertFalse(set.restSuggested(now: tomorrow, calendar: calendar))
        XCTAssertEqual(set.status(now: tomorrow, calendar: calendar), "Cycle 2 ready")
    }

    func testAPuzzleThePackLostLeavesTheSet() throws {
        var set = PuzzleCycleSamples.set(count: 20)
        let first = try XCTUnwrap(set.currentRun?.nextPuzzleID)
        let floor = set.floor
        set.carry(20)
        set.remove(first, now: .now)
        XCTAssertEqual(set.count, 19)
        XCTAssertEqual(set.floor, (floor * 19 / 20).rounded())
        XCTAssertFalse(set.currentRun?.order.contains(first) ?? true)
        XCTAssertEqual(set.currentRun?.carried, 0, "Time on the lost puzzle goes with it")
        XCTAssertEqual(set.stage, .playing(cycle: 1, puzzle: 1))
    }

    // MARK: The clock

    func testTheStopwatchPauses() {
        let start = PuzzleCycleSamples.day
        var watch = CycleStopwatch()
        watch.start(at: start)
        watch.start(at: start.addingTimeInterval(5))
        XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(10)), 10, "A second start doesn't reset it")
        watch.stop(at: start.addingTimeInterval(10))
        XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(100)), 10, "Paused")
        watch.start(at: start.addingTimeInterval(100))
        XCTAssertTrue(watch.isRunning)
        XCTAssertEqual(watch.take(at: start.addingTimeInterval(104)), 14)
        XCTAssertFalse(watch.isRunning)
        XCTAssertEqual(watch.elapsed(at: start.addingTimeInterval(200)), 0)
    }

    func testClockText() {
        XCTAssertEqual(CycleClock.text(0), "0:00")
        XCTAssertEqual(CycleClock.text(250.9), "4:10")
        XCTAssertEqual(CycleClock.text(3725), "1:02:05")
        XCTAssertEqual(CycleClock.spoken(250), "4 minutes 10 seconds")
        XCTAssertEqual(CycleClock.spoken(60), "1 minute")
        XCTAssertEqual(CycleClock.spoken(0), "0 seconds")
    }

    // MARK: Review queue

    func testMissedPuzzlesComeBackOnALeitnerSchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let evening = PuzzleCycleSamples.day.addingTimeInterval(22 * 3600)
        var queue = PuzzleReviewQueue()
        queue.missed("a", now: evening, calendar: calendar)
        let first = try XCTUnwrap(queue.items.first)
        XCTAssertEqual(first.box, 0)
        XCTAssertEqual(first.due, PuzzleCycleSamples.day.addingTimeInterval(86_400), "From the start of tomorrow")
        XCTAssertTrue(queue.due(at: evening).isEmpty)
        XCTAssertEqual(queue.due(at: first.due).map(\.id), ["a"])

        var now = first.due
        for (days, box) in [(3, 1), (7, 2), (16, 3)] {
            XCTAssertEqual(queue.reviewed("a", clean: true, now: now, calendar: calendar), .returns(days: days))
            XCTAssertEqual(queue.items.first?.box, box)
            XCTAssertEqual(queue.items.first?.due, now.addingTimeInterval(Double(days) * 86_400))
            now = queue.items.first?.due ?? now
        }
        XCTAssertEqual(queue.reviewed("a", clean: true, now: now, calendar: calendar), .learned)
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.learned, 1)
        XCTAssertNil(queue.reviewed("a", clean: true, now: now, calendar: calendar), "Gone from the queue")
    }

    func testASlipSendsAReviewBackToTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let day = PuzzleCycleSamples.day
        var queue = PuzzleReviewQueue()
        queue.missed("a", now: day, calendar: calendar)
        queue.reviewed("a", clean: true, now: day.addingTimeInterval(86_400), calendar: calendar)
        queue.reviewed("a", clean: true, now: day.addingTimeInterval(4 * 86_400), calendar: calendar)
        XCTAssertEqual(queue.items.first?.box, 2)
        let slip = day.addingTimeInterval(11 * 86_400)
        XCTAssertEqual(queue.reviewed("a", clean: false, now: slip, calendar: calendar), .returns(days: 1))
        XCTAssertEqual(queue.items.first?.box, 0)
        XCTAssertEqual(queue.items.first?.misses, 2)
        XCTAssertEqual(queue.items.first?.due, day.addingTimeInterval(12 * 86_400))
        XCTAssertEqual(queue.nextDue(after: slip), day.addingTimeInterval(12 * 86_400))
    }

    func testTheQueueKeepsTheNewestHundred() {
        var queue = PuzzleReviewQueue()
        for index in 0...PuzzleReviewQueue.capacity {
            queue.missed("p\(index)", now: PuzzleCycleSamples.day.addingTimeInterval(Double(index)), calendar: .current)
        }
        XCTAssertEqual(queue.count, PuzzleReviewQueue.capacity)
        XCTAssertFalse(queue.contains("p0"), "The oldest leaves first")
        XCTAssertTrue(queue.contains("p\(PuzzleReviewQueue.capacity)"))
    }

    // MARK: Saved files

    /// A puzzle file written before reviews and theme stats existed still loads, with everything kept.
    func testOldProgressFilesStillLoad() throws {
        let old = """
        {"rating":1234,"played":40,"solved":29,"streak":3,"bestStreak":9,"highestRating":1301,
         "rushBest":17,"recent":["a","b"],"themeID":"fork"}
        """
        let progress = try JSONDecoder().decode(PuzzleProgress.self, from: Data(old.utf8))
        XCTAssertEqual(progress.rating, 1234)
        XCTAssertEqual(progress.played, 40)
        XCTAssertEqual(progress.solved, 29)
        XCTAssertEqual(progress.streak, 3)
        XCTAssertEqual(progress.bestStreak, 9)
        XCTAssertEqual(progress.highestRating, 1301)
        XCTAssertEqual(progress.rushBest, 17)
        XCTAssertEqual(progress.recent, ["a", "b"])
        XCTAssertEqual(progress.themeID, "fork")
        XCTAssertTrue(progress.themeStats.isEmpty)
        XCTAssertEqual(progress.reviews, PuzzleReviewQueue())

        XCTAssertEqual(try JSONDecoder().decode(PuzzleProgress.self, from: Data("{}".utf8)), PuzzleProgress())
    }

    func testProgressSurvivesSaving() throws {
        var progress = PuzzleProgress()
        progress.rating = 1480
        progress.themeStats["fork"] = ThemeRecord(attempts: 9, clean: 6)
        progress.reviews.missed("abc", now: PuzzleCycleSamples.day, calendar: .current)
        let data = try JSONEncoder().encode(progress)
        XCTAssertEqual(try JSONDecoder().decode(PuzzleProgress.self, from: data), progress)
    }

    func testCycleFilesSurviveSavingAndOddFiles() throws {
        var set = PuzzleCycleSamples.set(count: 20)
        try PuzzleCycleSamples.play(&set, secondsEach: 20, cleanEvery: 3, at: PuzzleCycleSamples.day, stopAfter: 7)
        set.carry(4)
        let file = PuzzleCycleFile(current: set, setsFinished: 2)
        let data = try JSONEncoder().encode(file)
        XCTAssertEqual(try JSONDecoder().decode(PuzzleCycleFile.self, from: data), file)

        XCTAssertEqual(try JSONDecoder().decode(PuzzleCycleFile.self, from: Data("{}".utf8)), PuzzleCycleFile())
        let broken = try JSONDecoder().decode(PuzzleCycleFile.self, from: Data(#"{"current":{"id":7},"setsFinished":3}"#.utf8))
        XCTAssertNil(broken.current, "A set that can't be read is dropped")
        XCTAssertEqual(broken.setsFinished, 3, "but the rest is kept")
    }

    func testTheLibraryFindsPuzzlesByID() {
        let library = PuzzleCycleSamples.library(count: 30)
        XCTAssertEqual(library.puzzle(id: "s7")?.rating, 807)
        XCTAssertNil(library.puzzle(id: "nope"))
    }
}

/// The store: rated puzzles feeding the review queue and theme stats, reviews,
/// calibration from a placement test, and cycles saved in their own file.
@MainActor
final class PuzzleStoreTrainingTests: XCTestCase {

    private func puzzle(_ id: String, rating: Int = 1000, themes: [String] = ["fork", "middlegame"]) -> LichessPuzzle {
        LichessPuzzle(id: id, fen: "", moves: ["a", "b"], rating: rating, themes: themes)
    }

    func testRatedPuzzlesFeedTheReviewQueueAndThemeStats() {
        let store = PuzzleStore()
        store.record(puzzle("clean"), outcome: .firstTry)
        store.record(puzzle("hint", themes: ["pin", "middlegame"]), outcome: .withHint)
        store.record(puzzle("slip", themes: ["fork", "endgame"]), outcome: .afterMistake)
        store.record(puzzle("miss", themes: ["fork"]), outcome: .missed)

        XCTAssertEqual(store.progress.reviews.ids, ["hint", "slip", "miss"], "Everything short of a clean solve")
        XCTAssertEqual(store.reviewsDue, 0, "Not before tomorrow")
        XCTAssertEqual(store.dueReviews(now: .now.addingTimeInterval(2 * 86_400)).count, 3)

        XCTAssertEqual(store.themeStats["fork"], ThemeRecord(attempts: 3, clean: 1))
        XCTAssertEqual(store.themeStats["middlegame"], ThemeRecord(attempts: 2, clean: 1))
        XCTAssertEqual(store.themeStats["pin"], ThemeRecord(attempts: 1, clean: 0))
        XCTAssertEqual(store.accuracy(forTags: ["fork"], minimumAttempts: 3) ?? -1, 1.0 / 3, accuracy: 0.001)
        XCTAssertNil(store.accuracy(forTags: ["fork"], minimumAttempts: 4), "Too little to go on")
        XCTAssertEqual(store.accuracy(forTags: ["fork", "pin"], minimumAttempts: 1) ?? -1, 0.25, accuracy: 0.001)
        XCTAssertNil(store.accuracy(forTags: ["skewer"], minimumAttempts: 0))
    }

    func testReviewsLeaveTheRatingAlone() throws {
        let store = PuzzleStore()
        store.record(puzzle("miss"), outcome: .missed)
        let rating = store.progress.rating
        let tomorrow = Date.now.addingTimeInterval(86_400 * 1.5)
        XCTAssertEqual(store.dueReviews(now: tomorrow).map(\.id), ["miss"])
        XCTAssertEqual(store.recordReview("miss", outcome: .firstTry, now: tomorrow), .returns(days: 3))
        XCTAssertEqual(store.progress.rating, rating)
        XCTAssertEqual(store.progress.played, 1)
        XCTAssertEqual(store.recordReview("miss", outcome: .missed, now: tomorrow), .returns(days: 1))
        XCTAssertNil(store.recordReview("unknown", outcome: .firstTry))
        store.dropReview("miss")
        XCTAssertEqual(store.progress.reviews.count, 0)
    }

    func testACleanRatedSolveCountsAsAReview() {
        let store = PuzzleStore()
        store.record(puzzle("again"), outcome: .missed)
        store.record(puzzle("again"), outcome: .firstTry)
        XCTAssertEqual(store.progress.reviews.items.first?.box, 1)
    }

    func testCalibration() {
        let store = PuzzleStore()
        store.calibrate(rating: 750)
        XCTAssertEqual(store.progress.rating, 750)
        XCTAssertEqual(store.progress.highestRating, 750, "Before any rated puzzle, the highest follows the placement")
        store.record(puzzle("x", rating: 700), outcome: .firstTry)
        let highest = store.progress.highestRating
        store.calibrate(rating: 600)
        XCTAssertEqual(store.progress.highestRating, highest, "Never drops once puzzles are played")
        store.calibrate(rating: 5000)
        XCTAssertEqual(store.progress.rating, 3200)
        XCTAssertEqual(store.progress.highestRating, 3200)
        store.calibrate(rating: 100)
        XCTAssertEqual(store.progress.rating, 400)
    }

    func testCyclesRunThroughTheStoreAndAreSaved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cyclesURL = folder.appendingPathComponent("puzzle-cycles.json")
        var progress = PuzzleProgress()
        progress.rating = 1000
        let store = PuzzleStore(progress: progress, library: PuzzleCycleSamples.library(count: 60),
                                fileURL: folder.appendingPathComponent("puzzle-progress.json"), cyclesURL: cyclesURL)
        XCTAssertNil(store.cycleStatus)
        XCTAssertFalse(store.cycleSetInProgress)
        XCTAssertTrue(store.startCycleSet(size: .short))
        let set = try XCTUnwrap(store.cycleSet)
        XCTAssertEqual(set.count, 20)
        XCTAssertTrue(store.cycleSetInProgress)
        XCTAssertEqual(store.cycleStatus, "Cycle 1 · 1 of 20")
        XCTAssertTrue(Set(store.progress.recent).isSuperset(of: set.puzzleIDs), "Rated play won't serve them meanwhile")

        let rating = store.progress.rating
        for _ in 0..<20 {
            let next = try XCTUnwrap(store.cycleSet?.currentRun?.nextPuzzleID)
            store.recordCycle(next, clean: true, seconds: 10)
        }
        XCTAssertEqual(store.progress.rating, rating, "Cycles don't change the rating")
        XCTAssertEqual(store.cycleSet?.stage, .between(next: 2, target: 120))
        XCTAssertTrue(store.cycleRestSuggested())
        XCTAssertEqual(store.cycleStatus, "Cycle 2 tomorrow")

        store.pauseCycle(carrying: 5)
        XCTAssertEqual(store.cycleSet?.currentRun?.carried, 0, "Nothing to carry between cycles")
        XCTAssertTrue(store.startNextCycle())
        store.pauseCycle(carrying: 5)
        XCTAssertEqual(store.cycleSet?.currentRun?.elapsed, 5)

        // Saved: a store reading the same file picks up where this one is.
        let saved = try JSONDecoder().decode(PuzzleCycleFile.self, from: Data(contentsOf: cyclesURL))
        XCTAssertEqual(saved.current?.id, set.id)
        XCTAssertEqual(saved.current?.cycles.map(\.order), store.cycleSet?.cycles.map(\.order))
        XCTAssertEqual(saved.current?.stage, .playing(cycle: 2, puzzle: 1))
        XCTAssertEqual(saved.current?.currentRun?.elapsed, 5)

        // A new set replaces this one and keeps away from its puzzles.
        let old = Set(set.puzzleIDs)
        XCTAssertTrue(store.startCycleSet(size: .short))
        XCTAssertTrue(Set(store.cycleSet?.puzzleIDs ?? []).isDisjoint(with: old))
        XCTAssertEqual(store.cycles.setsFinished, 0)
    }

    func testFinishingEveryCycleCountsASet() throws {
        let store = PuzzleStore(library: PuzzleCycleSamples.library(count: 40))
        XCTAssertTrue(store.startCycleSet(size: .short))
        var seconds: TimeInterval = 30
        while let set = store.cycleSet, !set.isComplete {
            if case .between = set.stage { XCTAssertTrue(store.startNextCycle()) }
            let next = try XCTUnwrap(store.cycleSet?.currentRun?.nextPuzzleID)
            store.recordCycle(next, clean: true, seconds: seconds)
            if store.cycleSet?.currentRun?.isFinished == true { seconds /= 2 }
        }
        XCTAssertEqual(store.cycles.setsFinished, 1)
        XCTAssertFalse(store.cycleSetInProgress)
        XCTAssertNil(store.cycleStatus)
    }

    func testAStoreWithoutThePackCantStartASet() {
        let store = PuzzleStore()
        XCTAssertFalse(store.startCycleSet(size: .short))
        XCTAssertNil(store.cycleSet)
    }
}

/// The Cycles and Review screens at phone size, in their main states, a small
/// phone (375 x 667) and the largest text. When SNAPSHOT_DIR is set the pictures
/// are saved there as train-cycles-*.png and train-review-*.png.
@MainActor
final class PuzzleCyclesSnapshotTests: XCTestCase {

    private var theme: BoardTheme { .named(.gilded) }
    private var smallPhone: CGSize { CGSize(width: 375, height: 667) }

    func testCyclesBeforeASet() throws {
        try snapshot(PuzzleCyclesView(theme: theme).environment(try PuzzleScreenSamples.store()), "train-cycles-start")
        try snapshot(PuzzleCyclesView(theme: .named(.neon)).environment(try PuzzleScreenSamples.store()),
                     "train-cycles-start-neon")
    }

    /// Cycle 2, puzzle 12 of 20, 4:10 on the clock against a target of 6:00.
    func testCyclesPlaying() throws {
        let store = try PuzzleScreenSamples.store(cycles: .playing)
        XCTAssertEqual(store.cycleStatus, "Cycle 2 · 12 of 20")
        XCTAssertEqual(store.cycleSet?.currentRun?.elapsed ?? 0, 250, accuracy: 0.01)
        XCTAssertEqual(store.cycleSet?.currentRun?.target, 360)
        try snapshot(PuzzleCyclesView(theme: theme).environment(store), "train-cycles-playing")
        try snapshot(PuzzleCyclesView(theme: theme).environment(try PuzzleScreenSamples.store(cycles: .playing)),
                     "train-cycles-playing-small", size: smallPhone)
    }

    func testCyclesBetweenAndAtTheEnd() throws {
        let resting = try PuzzleScreenSamples.store(cycles: .resting)
        XCTAssertEqual(resting.cycleStatus, "Cycle 3 tomorrow")
        try snapshot(PuzzleCyclesView(theme: theme).environment(resting), "train-cycles-rest")
        try snapshot(PuzzleCyclesView(theme: theme).environment(try PuzzleScreenSamples.store(cycles: .resting))
                        .environment(\.dynamicTypeSize, .accessibility2), "train-cycles-rest-large-type")
        let complete = try PuzzleScreenSamples.store(cycles: .complete)
        XCTAssertNil(complete.cycleStatus)
        try snapshot(PuzzleCyclesView(theme: theme).environment(complete), "train-cycles-complete")
    }

    func testReview() throws {
        let due = try PuzzleScreenSamples.store(reviewsDue: 5)
        XCTAssertEqual(due.reviewsDue, 5)
        try snapshot(PuzzleReviewView(theme: theme).environment(due), "train-review-playing")
        try snapshot(PuzzleReviewView(theme: theme).environment(try PuzzleScreenSamples.store(reviewsDue: 5)),
                     "train-review-playing-small", size: smallPhone)
        let caughtUp = try PuzzleScreenSamples.store(reviewsDue: 0)
        XCTAssertEqual(caughtUp.reviewsDue, 0)
        try snapshot(PuzzleReviewView(theme: theme).environment(caughtUp), "train-review-caught-up")
    }

    // MARK: Drawing

    private func snapshot(_ view: some View, _ name: String, size: CGSize? = nil) throws {
        let window = try show(view, size: size)
        try save(window, name)
        window.isHidden = true
    }

    private func show(_ view: some View, size: CGSize?, wait: TimeInterval = 3) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = size.map { CGRect(origin: .zero, size: $0) } ?? scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        return window
    }

    private func save(_ window: UIWindow, _ name: String) throws {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}

/// Stores for the screen pictures: the real puzzle pack and a player rated 1250.
@MainActor
enum PuzzleScreenSamples {
    enum Cycles { case none, playing, resting, complete }

    private static let pack = PuzzleLibrary.bundled()

    static func store(cycles: Cycles = .none, reviewsDue: Int = 0) throws -> PuzzleStore {
        let library = try XCTUnwrap(pack, "lichess-puzzles.csv isn't in the app")
        var progress = PuzzleProgress()
        progress.rating = 1250
        progress.highestRating = 1310
        progress.played = 140
        progress.solved = 98
        addReviews(to: &progress, due: reviewsDue, library: library)
        let set = try cycleSet(cycles, library: library)
        return PuzzleStore(progress: progress, library: library,
                           cycles: PuzzleCycleFile(current: set, setsFinished: cycles == .none ? 0 : 1))
    }

    /// `due` puzzles missed days ago, four missed today, and twelve learned.
    private static func addReviews(to progress: inout PuzzleProgress, due: Int, library: PuzzleLibrary) {
        let calendar = Calendar.current
        let now = Date.now
        let ids = library.puzzles.filter { (1100...1350).contains($0.rating) && $0.length <= 3 }.map(\.id)
        for id in ids.prefix(due) {
            progress.reviews.missed(id, now: now.addingTimeInterval(-3 * 86_400), calendar: calendar)
        }
        for id in ids.dropFirst(due).prefix(4) {
            progress.reviews.missed(id, now: now, calendar: calendar)
        }
        for id in ids.dropFirst(due + 4).prefix(12) {
            var date = now.addingTimeInterval(-40 * 86_400)
            progress.reviews.missed(id, now: date, calendar: calendar)
            for days in [1, 3, 7, 16] {
                date = date.addingTimeInterval(Double(days) * 86_400)
                progress.reviews.reviewed(id, clean: true, now: date, calendar: calendar)
            }
        }
    }

    /// A set of 20 at the stage asked for. Cycle 1 took 12:00 with three misses.
    private static func cycleSet(_ stage: Cycles, library: PuzzleLibrary) throws -> PuzzleCycleSet? {
        guard stage != .none else { return nil }
        var generator = CycleTestGenerator(seed: 21)
        let now = Date.now
        let yesterday = now.addingTimeInterval(-86_400)
        var set = try XCTUnwrap(PuzzleCycleSet.make(from: library, size: 20, rating: 1250, avoid: [],
                                                     now: yesterday.addingTimeInterval(-3600), using: &generator))
        play(&set, seconds: 720, misses: [3, 9, 15], count: 20, at: yesterday)
        set.startNextCycle(now: now, using: &generator)
        switch stage {
        case .none:
            break
        case .playing:
            play(&set, seconds: 250, misses: [6], count: 11, at: now)
        case .resting:
            play(&set, seconds: 330, misses: [12], count: 20, at: now)
        case .complete:
            var seconds: TimeInterval = 330
            play(&set, seconds: seconds, misses: [12], count: 20, at: now)
            while !set.isComplete {
                set.startNextCycle(now: now, using: &generator)
                seconds *= 0.55
                play(&set, seconds: seconds, misses: [], count: 20, at: now)
            }
        }
        return set
    }

    /// Plays `count` puzzles of the cycle under way in `seconds` all told, missing those at
    /// `misses` (counting from 1).
    private static func play(_ set: inout PuzzleCycleSet, seconds: TimeInterval, misses: Set<Int>, count: Int, at date: Date) {
        for index in 1...count {
            guard let next = set.currentRun?.nextPuzzleID else { return }
            set.record(next, clean: !misses.contains(index), seconds: seconds / Double(count), now: date)
        }
    }
}

// MARK: Samples

/// Puzzles, sets and a steady random source for the tests.
enum PuzzleCycleSamples {
    /// Midnight, 1 June 2026, UTC.
    static let day = Date(timeIntervalSince1970: 1_780_272_000)

    static func pack() -> PuzzleLibrary? {
        PuzzleLibrary.bundled()
    }

    /// `count` two-move puzzles rated 800 up, with a spread of themes.
    static func library(count: Int) -> PuzzleLibrary {
        let themes = ["fork", "pin", "skewer", "discoveredAttack", "deflection", "mateIn2", "hangingPiece", "promotion"]
        let phases = ["middlegame", "endgame", "opening"]
        return PuzzleLibrary(puzzles: (0..<count).map { index in
            LichessPuzzle(id: "s\(index)", fen: "8/8/8/8/8/8/8/8 w - - 0 1", moves: ["a", "b", "c", "d"],
                          rating: 800 + index, themes: [themes[index % themes.count], phases[index % phases.count]])
        })
    }

    static func set(count: Int) -> PuzzleCycleSet {
        var generator = CycleTestGenerator(seed: 11)
        return PuzzleCycleSet.make(from: library(count: count * 3), size: count, rating: 1000, avoid: [],
                                   now: day, using: &generator)!
    }

    /// Plays the cycle under way: every puzzle in `secondsEach`, missing every `cleanEvery`th (0 for none).
    static func play(_ set: inout PuzzleCycleSet, secondsEach: TimeInterval, cleanEvery: Int, at date: Date,
                     stopAfter limit: Int = .max) throws {
        var played = 0
        while played < limit, let next = set.currentRun?.nextPuzzleID {
            played += 1
            let missed = cleanEvery > 0 && played % cleanEvery == 0
            XCTAssertTrue(set.record(next, clean: !missed, seconds: secondsEach, now: date))
        }
    }
}

/// SplitMix64: the same numbers every run, so picks and shuffles can be checked.
struct CycleTestGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
