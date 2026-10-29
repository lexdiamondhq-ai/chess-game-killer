import ChessKit
import SwiftUI
import UIKit
import XCTest
@testable import ChessGameKiller

/// The Daily Move: the list of daily puzzles, the app-wide streak, the reminders, the widget's
/// faces and the army's streak marks. Pictures go to SNAPSHOT_DIR as zz-daily-*.png.
@MainActor
final class DailyTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    private func date(_ day: String, hour: Int = 12, minute: Int = 0) -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute))!
    }

    // MARK: Today's Move

    func testTheListShipsWithTheAppAndStartsOnOctoberFirst() throws {
        let list = DailyMoves.all
        XCTAssertGreaterThanOrEqual(list.count, 1000)
        XCTAssertEqual(list.first?.number, 1)
        XCTAssertEqual(list.map(\.number), Array(1...list.count), "days are in order with none missing")
        XCTAssertEqual(Set(list.map(\.id)).count, list.count, "no puzzle comes twice")
        XCTAssertEqual(DailyMoves.dayNumber(for: date("2026-10-01"), calendar: calendar), 1)
        XCTAssertEqual(DailyMoves.dayNumber(for: date("2026-10-29", hour: 23), calendar: calendar), 29)
        XCTAssertEqual(DailyMoves.dayNumber(for: date("2025-01-01"), calendar: calendar), 1, "a clock set back still gets day 1")
        XCTAssertEqual(DailyMoves.puzzle(for: date("2026-10-29", hour: 1), calendar: calendar),
                       DailyMoves.puzzle(for: date("2026-10-29", hour: 22), calendar: calendar), "the same all day")
        XCTAssertNotEqual(DailyMoves.puzzle(for: date("2026-10-29"), calendar: calendar),
                          DailyMoves.puzzle(for: date("2026-10-30"), calendar: calendar))
        // Past the end it starts over.
        let wrapped = try XCTUnwrap(calendar.date(byAdding: .day, value: list.count, to: date("2026-10-01")))
        XCTAssertEqual(DailyMoves.puzzle(for: wrapped, calendar: calendar)?.number, 1)
    }

    /// Every puzzle in the list is legal from its position, and the position shown is the one after
    /// the opponent's move, with the solver to move.
    func testEveryDailyPuzzlePlaysOut() throws {
        for puzzle in DailyMoves.all {
            let shown = try XCTUnwrap(TrainingChess.fen(after: [puzzle.moves[0]], from: puzzle.fen), "No. \(puzzle.number)")
            XCTAssertEqual(shown.split(separator: " ").prefix(2), puzzle.shownFEN.split(separator: " ").prefix(2), "No. \(puzzle.number)")
            XCTAssertNotNil(TrainingChess.fen(after: puzzle.moves, from: puzzle.fen), "No. \(puzzle.number) plays out")
            XCTAssertEqual(TrainingChess.sideToMove(shown) == .white, puzzle.solverIsWhite)
        }
    }

    /// Like a newspaper puzzle: Monday the easiest, Sunday the hardest.
    func testTheWeekClimbs() {
        var byWeekday: [Int: [Int]] = [:]
        for puzzle in DailyMoves.all.prefix(140) {
            let day = calendar.date(byAdding: .day, value: puzzle.number - 1, to: date("2026-10-01"))!
            byWeekday[calendar.component(.weekday, from: day), default: []].append(puzzle.rating)
        }
        func average(_ weekday: Int) -> Double { Double(byWeekday[weekday]!.reduce(0, +)) / Double(byWeekday[weekday]!.count) }
        // weekday: 1 Sunday, 2 Monday ... 7 Saturday.
        XCTAssertLessThan(average(2), average(4))
        XCTAssertLessThan(average(4), average(6))
        XCTAssertLessThan(average(6), average(1))
    }

    func testHeadlinesReadLikeAChessColumn() {
        let mate = DailyPuzzle(number: 3, id: "x", fen: "", moves: ["a", "b"], rating: 1500,
                               themes: ["mateIn2"], shownFEN: "8/8/8/8/8/8/8/8 b - - 0 1")
        XCTAssertEqual(mate.headline, "Black to play and mate in two.")
        XCTAssertEqual(mate.difficulty, "Medium")
        let win = DailyPuzzle(number: 3, id: "x", fen: "", moves: ["a", "b"], rating: 2050,
                              themes: ["fork"], shownFEN: "8/8/8/8/8/8/8/8 w - - 0 1")
        XCTAssertEqual(win.headline, "White to play and win.")
        XCTAssertEqual(win.difficulty, "Hardest")
        XCTAssertEqual(DailyMoves.parse("day,id\nbad line\n1,a,f,e2e4,x,t,s\n").count, 0, "unreadable lines are skipped")
    }

    // MARK: The streak

    func testAnyOneThingMakesTheDay() {
        let day = date("2026-10-29", hour: 20)
        for activity in [DailyActivity.game, .training, .todaysMove(found: false)] {
            let result = DailyRules.record(activity, in: DailyRecord(), at: day, calendar: calendar)
            XCTAssertTrue(result.outcome.completedDay, "\(activity)")
            XCTAssertEqual(result.record.streak.current, 1)
            XCTAssertTrue(DailyRules.isDone(result.record, on: day, calendar: calendar))
        }
    }

    func testThreeSolvedPuzzlesMakeTheDay() {
        var record = DailyRecord()
        let day = date("2026-10-29")
        for (index, solved) in [true, false, true].enumerated() {
            let result = DailyRules.record(.ratedPuzzle(solved: solved), in: record, at: day.addingTimeInterval(Double(index)), calendar: calendar)
            record = result.record
            XCTAssertFalse(result.outcome.completedDay)
        }
        XCTAssertEqual(record.puzzlesSolved, 2)
        let third = DailyRules.record(.ratedPuzzle(solved: true), in: record, at: day, calendar: calendar)
        XCTAssertTrue(third.outcome.completedDay)
        // A new day starts the count again.
        let tomorrow = DailyRules.record(.ratedPuzzle(solved: true), in: third.record, at: date("2026-10-30"), calendar: calendar)
        XCTAssertEqual(tomorrow.record.puzzlesSolved, 1)
        XCTAssertFalse(tomorrow.outcome.completedDay)
    }

    func testTodaysMoveCountsOnceAndKeepsTheFirstTry() {
        let day = date("2026-10-29")
        var record = DailyRules.record(.todaysMove(found: true), in: DailyRecord(), at: day, calendar: calendar).record
        record = DailyRules.record(.todaysMove(found: false), in: record, at: day, calendar: calendar).record
        XCTAssertTrue(record.moveFound)
        XCTAssertEqual(record.moveNumber, 29)
        XCTAssertEqual(record.moveDay, "2026-10-29")
    }

    func testDaysInARowWithARestDayAWeekAndMilestones() {
        var record = DailyRecord()
        var milestones: [Int] = []
        // Seven days running, then one missed, then the next day: the rest day keeps it.
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: date("2026-10-01"))!
            let result = DailyRules.record(.game, in: record, at: day, calendar: calendar)
            record = result.record
            if let milestone = result.outcome.milestone { milestones.append(milestone) }
        }
        XCTAssertEqual(record.streak.current, 7)
        XCTAssertEqual(milestones, [7])
        XCTAssertEqual(DailyRules.aliveThrough(record, calendar: calendar), "2026-10-09", "tomorrow, or the day after on the rest day")
        let afterRest = DailyRules.record(.game, in: record, at: date("2026-10-09"), calendar: calendar)
        XCTAssertTrue(afterRest.outcome.usedRestDay)
        XCTAssertEqual(afterRest.record.streak.current, 8)
        XCTAssertNil(afterRest.outcome.milestone, "a mark is earned once")
        // The rest day is used up for the week: the next gap ends the streak.
        XCTAssertEqual(DailyRules.aliveThrough(afterRest.record, calendar: calendar), "2026-10-10")
        XCTAssertEqual(DailyRules.streak(afterRest.record, on: date("2026-10-11"), calendar: calendar), 0)
    }

    func testTheTrainingStreakCarriesOverOnce() {
        let training = Streak(current: 9, best: 12, lastDay: "2026-10-28")
        let seeded = DailyRules.seeded(DailyRecord(), training: training)
        XCTAssertEqual(seeded.streak.current, 9)
        XCTAssertEqual(seeded.streak.best, 12)
        XCTAssertEqual(seeded.marks, [7], "a mark already behind the streak isn't handed out later")
        XCTAssertTrue(seeded.seeded)
        var later = seeded
        later.streak = Streak(current: 1, best: 12, lastDay: "2026-11-02")
        XCTAssertEqual(DailyRules.seeded(later, training: training), later, "only the first time")
    }

    func testTheReminderComesAtTheUsualHour() {
        var record = DailyRecord()
        XCTAssertEqual(DailyRules.usualHour(record), 19)
        record.hours = [8, 20, 21, 22, 7]
        XCTAssertEqual(DailyRules.usualHour(record), 20)
        record.hours = [23, 23, 23]
        XCTAssertEqual(DailyRules.usualHour(record), 21, "never later than 9 at night")
    }

    func testTheStoreSavesAndMarksAMilestone() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("daily-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var record = DailyRecord()
        record.streak = Streak(current: 6, best: 6, lastDay: Trainer.dayString(.now.addingTimeInterval(-86_400)))
        let store = DailyStore(state: record, fileURL: url)
        var asked: [Int] = []
        var changes = 0
        store.onMilestone = { days in asked.append(days); return "Ghost" }
        store.onChange = { changes += 1 }
        store.record(.game)
        XCTAssertEqual(asked, [7])
        XCTAssertEqual(store.streak, 7)
        XCTAssertEqual(store.markToday?.piece, "Ghost")
        XCTAssertTrue(store.doneToday)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(store.nextMilestone?.days, 30)
        let saved = try XCTUnwrap(ProgressFile.read(DailyRecord.self, at: url))
        XCTAssertEqual(saved.streak.current, 7)
        XCTAssertEqual(saved.lastMark?.days, 7)
        let snapshot = store.snapshot(hero: "Ghost", heroRank: "Elite")
        XCTAssertEqual(snapshot.streakShown(on: Trainer.dayString(.now)), 7)
        XCTAssertTrue(snapshot.isDone(on: Trainer.dayString(.now)))
    }

    /// A daily file as the app writes it, by hand. The FIXTURE line is the app's own encoding.
    func testADailyFileReadsBack() throws {
        let json = """
        {"streak":{"current":4,"best":9,"lastDay":"2026-10-28","restDay":"2026-10-20"},"day":"2026-10-28",
         "puzzlesSolved":2,"moveDay":"2026-10-28","moveNumber":28,"moveFound":true,"hours":[19,20],
         "marks":[7],"lastMark":{"days":7,"day":"2026-10-21","piece":"Ghost"},"seeded":true,"reminderAsked":true}
        """
        let record = try JSONDecoder().decode(DailyRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.streak.current, 4)
        XCTAssertEqual(record.lastMark?.piece, "Ghost")
        XCTAssertTrue(record.reminderAsked)
        // An older or partial file still reads.
        let partial = try JSONDecoder().decode(DailyRecord.self, from: Data(#"{"streak":{"current":2}}"#.utf8))
        XCTAssertEqual(partial.streak.current, 2)
        XCTAssertFalse(partial.seeded)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(record), let text = String(data: data, encoding: .utf8) {
            NSLog("FIXTURE %@ %@", "daily.json", text)
        }
    }

    // MARK: Reminders

    func testRemindersPlanOneADayForThreeDays() {
        var facts = ReminderFacts()
        facts.streak = 5
        facts.puzzleHeadline = "White to play and win."
        let morning = date("2026-10-29", hour: 9)
        let plans = DailyReminders.plan(now: morning, hour: 19, facts: facts, calendar: calendar)
        XCTAssertEqual(plans.count, 3)
        XCTAssertEqual(plans.map { calendar.component(.day, from: $0.date) }, [29, 30, 31])
        XCTAssertEqual(plans.map { calendar.component(.hour, from: $0.date) }, [19, 19, 19])
        XCTAssertEqual(plans[0].title, "Day 6 is one move away")
        XCTAssertEqual(Set(plans.map(\.title)).count, 3, "each day says something different")

        // Done today: nothing more today; from tomorrow.
        facts.doneToday = true
        let done = DailyReminders.plan(now: morning, hour: 19, facts: facts, calendar: calendar)
        XCTAssertEqual(done.map { calendar.component(.day, from: $0.date) }, [30, 31, 1])
        XCTAssertEqual(done[0].title, "Day 6 is one move away", "tomorrow, today's streak still stands")

        // The hour has passed already: not today.
        facts.doneToday = false
        let late = DailyReminders.plan(now: date("2026-10-29", hour: 19, minute: 50), hour: 19, facts: facts, calendar: calendar)
        XCTAssertEqual(late.first.map { calendar.component(.day, from: $0.date) }, 30)
    }

    func testRemindersTalkAboutYourArmy() {
        var facts = ReminderFacts()
        facts.captive = ("Ghost", "Pulse")
        facts.hero = "Seraphine"
        facts.heroKind = "queen"
        facts.daysSinceGame = 2
        facts.nearRank = ("Seraphine", 6, "Legend")
        let first = DailyReminders.message(daysAway: 1, facts: facts, index: 0)
        XCTAssertEqual(first.title, "Pulse still holds Ghost")
        XCTAssertEqual(first.body, "Win one game against Pulse to bring Ghost home.")
        XCTAssertEqual(DailyReminders.message(daysAway: 1, facts: facts, index: 1).title, "Seraphine is 6 XP from Legend")
        XCTAssertEqual(DailyReminders.message(daysAway: 1, facts: facts, index: 2).title, "Seraphine hasn't fought in 3 days")
        // A streak is never promised two days out.
        facts.streak = 4
        XCTAssertFalse(DailyReminders.message(daysAway: 2, facts: facts, index: 1).title.hasPrefix("Day"))
    }

    func testFactsComeFromTheArmy() {
        var army = ArmyStore.Army()
        var queen = PieceRecord()
        queen.name = "Seraphine"
        queen.xp = 290
        army.records[.queen] = queen
        var knight = PieceRecord()
        knight.name = "Ghost"
        knight.xp = 40
        army.records[.kingsKnight] = knight
        army.captives[.kingsKnight] = MatchController.Level.club.rawValue
        let store = ArmyStore(army: army)
        let daily = DailyStore()
        let now = Date.now
        let facts = DailyUpkeep.facts(daily: daily, army: store, lastGame: now.addingTimeInterval(-3 * 86_400), now: now)
        XCTAssertEqual(facts.hero, "Seraphine")
        XCTAssertEqual(facts.heroKind, "queen")
        XCTAssertEqual(facts.nearRank?.xp, 10)
        XCTAssertEqual(facts.nearRank?.rank, "Legend")
        XCTAssertEqual(facts.captive?.name, "Ghost")
        XCTAssertEqual(facts.captive?.rival, MatchController.Level.club.rival.name)
        XCTAssertEqual(facts.daysSinceGame, 3)
        XCTAssertNotNil(facts.puzzleHeadline)
    }

    // MARK: The army's marks

    func testAStreakMarkGoesToTheMostExperiencedPieceWithoutIt() {
        var army = ArmyStore.Army()
        var queen = PieceRecord()
        queen.name = "Seraphine"
        queen.xp = 300
        army.records[.queen] = queen
        var knight = PieceRecord()
        knight.xp = 120
        army.records[.kingsKnight] = knight
        let store = ArmyStore(army: army)
        let first = store.markStreak(days: 7)
        XCTAssertEqual(first?.slot, .queen)
        XCTAssertEqual(first?.headline, "Seraphine carries your 7-day streak mark.")
        XCTAssertEqual(first?.label, "7-DAY MARK")
        XCTAssertEqual(store.record(for: .queen).streakMarks, [7])
        XCTAssertEqual(store.markStreak(days: 7)?.slot, .kingsKnight, "the next piece in line")
        XCTAssertEqual(store.markStreak(days: 30)?.slot, .queen)
        XCTAssertEqual(store.hero?.name, "Seraphine")
    }

    // MARK: The widget

    func testTheDiagramReadsAFEN() {
        let cells = DailyDiagram.cells("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
        XCTAssertEqual(cells.count, 64)
        XCTAssertEqual(cells[0], "bR")
        XCTAssertEqual(cells[4], "bK")
        XCTAssertEqual(cells[36], "wP", "e4")
        XCTAssertNil(cells[52], "e2 is empty")
        XCTAssertEqual(cells[60], "wK")
    }

    func testTheWidgetLetsALapsedStreakGo() {
        var snapshot = DailySnapshot()
        snapshot.streak = 12
        snapshot.lastDay = "2026-10-28"
        snapshot.aliveThrough = "2026-10-29"
        XCTAssertEqual(snapshot.streakShown(on: "2026-10-29"), 12)
        XCTAssertEqual(snapshot.streakShown(on: "2026-10-30"), 0)
        XCTAssertFalse(snapshot.isDone(on: "2026-10-29"))
    }

    func testTheWorldTally() {
        XCTAssertEqual(DailyTally(players: 1284, found: 796).percentFound, 62)
        XCTAssertTrue(DailyTally(players: 1284, found: 796).line.hasPrefix("62% of 1"))
        XCTAssertEqual(DailyTally(players: 8, found: 3).line, "You're one of the first 8 players to try it today.")
        XCTAssertEqual(DailyTally(players: 0, found: 0).line, "You're the first to try it today.")
    }

    func testDailyLinks() throws {
        XCTAssertTrue(DailyLink.matches(try XCTUnwrap(URL(string: "chessgamekiller://daily"))))
        XCTAssertFalse(DailyLink.matches(try XCTUnwrap(URL(string: "chessgamekiller://c/7KQ2XM"))))
        XCTAssertNil(ChallengeLink.code(from: DailyLink.url), "never taken for a challenge")
    }

    // MARK: Pictures

    func testWidgetFaces() throws {
        var snapshot = DailySnapshot()
        snapshot.streak = 12
        snapshot.lastDay = Trainer.dayString(.now)
        snapshot.aliveThrough = Trainer.dayString(.now.addingTimeInterval(86_400))
        let done = DailyWidgetEntry(date: .now, puzzle: DailyMoves.puzzle(for: .now), snapshot: snapshot)
        let fresh = DailyWidgetEntry(date: .now, puzzle: DailyMoves.puzzle(for: .now), snapshot: DailySnapshot())
        let faces: [(String, DailyWidgetEntry, DailyWidgetStyle, CGSize)] = [
            ("small", done, .small, CGSize(width: 170, height: 170)),
            ("medium", done, .medium, CGSize(width: 364, height: 170)),
            ("medium-fresh", fresh, .medium, CGSize(width: 364, height: 170)),
        ]
        for (name, entry, style, size) in faces {
            let face = DailyWidgetView(entry: entry, style: style)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(DailyPalette.canvas, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .environment(\.colorScheme, .dark)
            try render(face, "zz-daily-widget-\(name)")
        }
        // The Lock Screen faces, in the one tint the Lock Screen draws them in.
        let lock = HStack(spacing: 18) {
            DailyWidgetView(entry: done, style: .circular)
                .frame(width: 72, height: 72)
                .background(Circle().fill(.white.opacity(0.18)))
            DailyWidgetView(entry: done, style: .rectangular)
                .frame(width: 170, height: 72)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Color(red: 0.12, green: 0.16, blue: 0.24))
        .environment(\.colorScheme, .dark)
        try render(lock, "zz-daily-widget-lock")
    }

    func testTodaysMoveAfterSolving() throws {
        var record = DailyRecord()
        record.streak = Streak(current: 7, best: 7, lastDay: Trainer.dayString(.now))
        record.lastMark = StreakMark(days: 7, day: Trainer.dayString(.now), piece: "Ghost")
        record.moveDay = Trainer.dayString(.now)
        record.moveFound = true
        record.seeded = true
        let view = DailyMoveView(theme: .named(.gilded), morePuzzles: {}, stats: nil,
                                 outcome: .firstTry, tally: DailyTally(players: 1284, found: 796))
            .environment(DailyStore(state: record))
            .environment(PuzzleStore())
            .environment(TrainingStore(library: TrainingLibrary.shared))
        try show(view, "zz-daily-move-solved")
    }

    // MARK: Drawing

    private func render(_ view: some View, _ name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage, "\(name) did not draw")
        try save(image, name)
    }

    private func show(_ view: some View, _ name: String, wait: TimeInterval = 2.5) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        try save(image, name)
    }

    private func save(_ image: UIImage, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], let data = image.pngData() else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }
}
