import ChessKit
import XCTest
@testable import ChessGameKiller

/// Coach Leo's report on the player's own games, and how those games steer today's training.
final class CoachReportTests: XCTestCase {

    // 1.e4 e5 2.Nf3 Nc6 3.Bc4 h6, then 4.Ng5?? hxg5: a knight left hanging.
    private let hangingFEN = "r1bqkbnr/pppp1pp1/2n4p/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4"
    private let quietFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    // Kings, a rook and a pawn each: an endgame.
    private let endgameFEN = "8/5k2/8/3r4/8/2R5/5PK1/8 w - - 0 40"

    private func moment(ply: Int, grade: MoveReview.Grade, fen: String, uci: String,
                        bestUCI: String? = nil, reply: String? = nil) -> SavedMoment {
        SavedMoment(ply: ply, grade: grade.rawValue, san: uci, uci: uci, byWhite: true, fenBefore: fen,
                    fenAfter: TrainingChess.fen(after: [uci], from: fen) ?? fen,
                    best: bestUCI, bestUCI: bestUCI, reply: reply, before: 0.1, after: -0.4)
    }

    private func game(_ moments: [SavedMoment], daysAgo: Double = 0, level: Int? = 1) -> SavedGame {
        SavedGame(id: UUID(), date: Date().addingTimeInterval(-daysAgo * 86_400), opponent: "Spark", level: level,
                  playerIsWhite: true, result: .loss, accuracy: 70, positions: [quietFEN], moves: [],
                  moments: moments)
    }

    /// A game of `count` clean moves: opening moves first, then middlegame.
    private func cleanMoves(_ count: Int, from ply: Int = 1) -> [SavedMoment] {
        (0..<count).map { moment(ply: ply + $0 * 2, grade: .good, fen: quietFEN, uci: "e2e4") }
    }

    func testNoGamesNoReport() {
        let report = CoachReport.make(games: [])
        XCTAssertEqual(report.gamesRead, 0)
        XCTAssertFalse(report.hasEnough)
        XCTAssertNil(report.leak)
    }

    func testCleanGamesAreStrong() {
        let report = CoachReport.make(games: [game(cleanMoves(30)), game(cleanMoves(30))])
        let safety = report.scores.first { $0.area == .safety }
        XCTAssertEqual(safety?.value ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(safety?.verdict, "Strong")
        XCTAssertNil(report.leak, "Nothing to fix")
    }

    func testHangingPiecesAreTheLeak() throws {
        var moves = cleanMoves(20)
        moves.append(moment(ply: 7, grade: .blunder, fen: hangingFEN, uci: "f3g5", bestUCI: "d2d3", reply: "h6g5"))
        let report = CoachReport.make(games: [game(moves), game(moves, daysAgo: 1)])
        let safety = try XCTUnwrap(report.scores.first { $0.area == .safety })
        XCTAssertEqual(safety.mistakes, 2)
        XCTAssertLessThan(safety.value ?? 1, 0.5, "A blunder a game needs work")
        let leak = try XCTUnwrap(report.leak)
        XCTAssertEqual(leak.area, .safety)
        XCTAssertEqual(leak.headline, "Loose pieces")
        XCTAssertEqual(leak.skill, "safety")
        XCTAssertTrue(leak.detail.contains("twice"), leak.detail)
    }

    func testMistakesWithNoPatternGoByPhase() {
        XCTAssertEqual(CoachReport.area(for: nil, phase: .opening), .openings)
        XCTAssertEqual(CoachReport.area(for: nil, phase: .middlegame), .calculation)
        XCTAssertEqual(CoachReport.area(for: nil, phase: .endgame), .endgames)
        XCTAssertEqual(CoachReport.area(for: .missedFork, phase: .endgame), .tactics)
        XCTAssertEqual(CoachReport.area(for: .missedMate, phase: .opening), .checkmates)
    }

    func testTheEndgameIsFewPiecesLeft() {
        XCTAssertTrue(CoachReport.Phase.isEndgame(fen: endgameFEN))
        XCTAssertFalse(CoachReport.Phase.isEndgame(fen: quietFEN))
        let late = moment(ply: 80, grade: .good, fen: endgameFEN, uci: "c3c7")
        XCTAssertEqual(CoachReport.Phase.of(late), .endgame)
        XCTAssertEqual(CoachReport.Phase.of(moment(ply: 9, grade: .good, fen: quietFEN, uci: "e2e4")), .opening)
    }

    func testAnAreaNeedsEnoughMovesToBeJudged() {
        // Two endgame moves aren't enough to say anything about endgames.
        var moves = cleanMoves(20)
        moves += [moment(ply: 60, grade: .blunder, fen: endgameFEN, uci: "c3c7"),
                  moment(ply: 62, grade: .good, fen: endgameFEN, uci: "c3c7")]
        let report = CoachReport.make(games: [game(moves)])
        XCTAssertNil(report.scores.first { $0.area == .endgames }?.value)
    }

    func testOnlyTheNewestGamesAreRead() {
        let games = (0..<30).map { game(cleanMoves(5), daysAgo: Double($0)) }
        XCTAssertEqual(CoachReport.make(games: games).gamesRead, CoachReport.gameLimit)
    }

    func testGamesAgainstAFriendAreLeftOut() {
        let friend = game(cleanMoves(20), level: nil)
        XCTAssertEqual(CoachReport.make(games: [friend]).gamesRead, 0)
        XCTAssertEqual(CoachReport.make(games: [friend, game(cleanMoves(20))]).gamesRead, 1)
    }
}

/// Today's skill follows the player's own games.
@MainActor
final class GameSteeredFocusTests: XCTestCase {

    private func library() throws -> TrainingLibrary {
        try XCTUnwrap(TrainingLibrary.shared, "The training content didn't load")
    }

    private func mistake(_ skill: String, daysAgo: Double = 1) -> GameMistake {
        let date = Date().addingTimeInterval(-daysAgo * 86_400)
        return GameMistake(id: UUID().uuidString, fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", best: "a1a8",
                           played: "h2h3", skill: skill, title: "Missed", created: date, due: date)
    }

    private func settled() -> TrainingProgress {
        var progress = TrainingProgress()
        progress.sessionsDone = 4
        progress.lessonsDone["welcome"] = .now
        return progress
    }

    func testTwoMissedForksMakeForksTodaysSkill() throws {
        var progress = settled()
        progress.mistakes = [mistake("forks"), mistake("forks"), mistake("pins")]
        let planner = TrainingPlanner(library: try library(), progress: progress, seed: 1)
        let choice = try XCTUnwrap(planner.focusChoice())
        XCTAssertEqual(choice.skill.id, "forks")
        XCTAssertEqual(choice.reason, .fromGames(2))
    }

    func testOneMissIsNotEnough() throws {
        var progress = settled()
        progress.mistakes = [mistake("forks")]
        let choice = try XCTUnwrap(TrainingPlanner(library: try library(), progress: progress, seed: 1).focusChoice())
        XCTAssertNotEqual(choice.skill.id, "forks")
        XCTAssertEqual(choice.reason, .nextOnPath)
    }

    func testOldMissesFadeOut() throws {
        var progress = settled()
        progress.mistakes = [mistake("forks", daysAgo: 30), mistake("forks", daysAgo: 40)]
        let choice = try XCTUnwrap(TrainingPlanner(library: try library(), progress: progress, seed: 1).focusChoice())
        XCTAssertNotEqual(choice.reason, .fromGames(2))
    }

    func testAStrongSkillIsLeftToTheGames() throws {
        let library = try library()
        var progress = settled()
        progress.mistakes = [mistake("forks"), mistake("forks")]
        progress.skills["forks"] = SkillRecord(rating: library.bands(for: "forks").strong + 50, attempts: 12)
        let choice = try XCTUnwrap(TrainingPlanner(library: library, progress: progress, seed: 1).focusChoice())
        XCTAssertNotEqual(choice.skill.id, "forks")
    }

    func testTheFirstDayIsStillTheWelcome() throws {
        var progress = TrainingProgress()
        progress.mistakes = [mistake("forks"), mistake("forks")]
        let choice = try XCTUnwrap(TrainingPlanner(library: try library(), progress: progress, seed: 1).focusChoice())
        XCTAssertEqual(choice.reason, .firstDay)
    }

    func testTheLevelCheckSkipsWhatThePlayerKnows() throws {
        let store = TrainingStore(library: try library())
        store.applyLevel(1800)
        XCTAssertEqual(store.progress.placement, 1800)
        XCTAssertNil(store.todaysLesson.flatMap { $0.id == "welcome" ? $0 : nil }, "A strong player skips the welcome")
        let focus = try XCTUnwrap(store.todaysFocus)
        XCTAssertNotEqual(focus.id, "counting", "The basics count as learned")
        // A beginner's result changes nothing on the path.
        let beginner = TrainingStore(library: try library())
        beginner.applyLevel(500)
        XCTAssertEqual(beginner.todaysLesson?.id, "welcome")
    }
}

/// Puzzles inside a training session: the rating stays put, misses come back for review,
/// and they earn XP without filling Coach Leo's drill records.
@MainActor
final class TrainingPuzzleTests: XCTestCase {

    func testSessionPuzzlesFeedTheReviewQueue() throws {
        let pack = try XCTUnwrap(PuzzleLibrary.bundled(), "lichess-puzzles.csv isn't in the app")
        let store = PuzzleStore(library: pack)
        let missed = pack.puzzles[10], solved = pack.puzzles[20]
        store.recordTraining(missed.id, outcome: .missed)
        store.recordTraining(solved.id, outcome: .firstTry)
        XCTAssertTrue(store.progress.reviews.contains(missed.id))
        XCTAssertFalse(store.progress.reviews.contains(solved.id))
        XCTAssertEqual(store.progress.rating, PuzzleProgress().rating)
        XCTAssertTrue(store.progress.recent.contains(missed.id))
        let later = Date.now.addingTimeInterval(2 * 86_400)
        XCTAssertEqual(store.dueReviewPuzzles(limit: 2, now: later).map(\.id), [missed.id])
        XCTAssertEqual(missed.drill.lichessPuzzleID, missed.id)
    }

    func testPuzzleDrillsOnlyEarnXP() throws {
        let pack = try XCTUnwrap(PuzzleLibrary.bundled())
        let store = TrainingStore(library: try XCTUnwrap(TrainingLibrary.shared))
        let reward = store.record(pack.puzzles[0].drill, outcome: .firstTry)
        XCTAssertGreaterThan(reward.xp, 0)
        XCTAssertTrue(store.progress.items.isEmpty)
        XCTAssertNil(store.progress.skills["puzzles"])
        XCTAssertTrue(store.trainedToday)
    }

    func testPracticeKeepsTheStreak() throws {
        let store = TrainingStore(library: try XCTUnwrap(TrainingLibrary.shared))
        XCTAssertFalse(store.trainedToday)
        store.recordPractice(xp: 6)
        XCTAssertTrue(store.trainedToday)
        XCTAssertEqual(store.progress.xp, 6)
    }
}
