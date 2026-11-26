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
        XCTAssertNil(report.leak, "Nothing to fix")
        // Two games are too few to put next to real players: the bar says what it has seen.
        XCTAssertFalse(report.isCompared)
        XCTAssertEqual(report.gamesLeftToCompare, 6)
        XCTAssertNil(safety?.standing)
        XCTAssertEqual(safety?.verdict, "Clean so far")
        XCTAssertEqual(report.scores.first { $0.area == .endgames }?.verdict, "Not enough yet")

        // Eight are enough. Nothing left hanging in eight games is rarer than it sounds.
        let more = CoachReport.make(games: (0..<8).map { game(cleanMoves(30), daysAgo: Double($0)) })
        XCTAssertTrue(more.isCompared)
        XCTAssertEqual(more.scores.first { $0.area == .safety }?.verdict, "Better than 9 in 10")
        // More than half of real players never miss a short mate either: level with them, not ahead.
        XCTAssertEqual(more.scores.first { $0.area == .checkmates }?.verdict, "Like most players")
    }

    func testBeforeEnoughGamesABarCountsTheCostlyMoves() throws {
        var moves = cleanMoves(20)
        moves.append(moment(ply: 7, grade: .blunder, fen: hangingFEN, uci: "f3g5", bestUCI: "d2d3", reply: "h6g5"))
        let one = CoachReport.make(games: [game(moves)])
        XCTAssertEqual(one.scores.first { $0.area == .safety }?.verdict, "1 costly move")
        let two = CoachReport.make(games: [game(moves), game(moves, daysAgo: 1)])
        XCTAssertEqual(two.scores.first { $0.area == .safety }?.verdict, "2 costly moves")
        // What to work on doesn't wait for the comparison: two real mistakes are enough.
        XCTAssertEqual(two.leak?.headline, "Loose pieces")
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
        XCTAssertEqual(leak.proof, "Left one hanging twice.")
        XCTAssertEqual(report.weakSpots, [leak])
        XCTAssertEqual(report.missed[.hungPiece], 2)
        // Its practice starts with the positions saved from the player's games under that skill.
        XCTAssertTrue(leak.positions.holds(saved(skill: "safety", fen: hangingFEN)))
        XCTAssertFalse(leak.positions.holds(saved(skill: "forks", fen: hangingFEN)))
    }

    private func saved(skill: String, fen: String) -> GameMistake {
        GameMistake(id: UUID().uuidString, fen: fen, best: "d2d3", played: "f3g5", skill: skill, title: "Missed",
                    created: .now, due: .now)
    }

    // MARK: What to work on

    /// One game's part of a report, written out by hand.
    private func tally(weighted: [CoachReport.Area: Double] = [:], mistakes: [CoachReport.Area: Int] = [:],
                       kinds: [CoachMoment.Kind: Int] = [:]) -> CoachReport.Tally {
        var tally = CoachReport.Tally()
        for area in CoachReport.Area.allCases { tally.moves[area] = 20 }
        tally.weighted = weighted
        tally.mistakes = mistakes
        tally.kinds = kinds
        return tally
    }

    func testTheAreasFurthestBehindRealPlayersComeFirst() {
        // A blunder a game left hanging, two in the opening, three in the middlegame. Real players
        // lose most in the middlegame too, so the order isn't simply the lowest score first.
        let game = tally(weighted: [.safety: 3, .openings: 6, .calculation: 9],
                         mistakes: [.safety: 1, .openings: 2, .calculation: 3], kinds: [.hungPiece: 1])
        let report = CoachReport.make(tallies: Array(repeating: game, count: 8))
        XCTAssertEqual(report.gamesRead, 8)
        func verdict(_ area: CoachReport.Area) -> String? { report.scores.first { $0.area == area }?.verdict }
        XCTAssertEqual(verdict(.safety), "Like most players")
        XCTAssertEqual(verdict(.openings), "Below most players")
        XCTAssertEqual(verdict(.calculation), "Below most players")
        XCTAssertEqual(verdict(.tactics), "Better than 9 in 10")
        XCTAssertEqual(report.weakSpots.map(\.area), [.calculation, .openings, .safety])
        XCTAssertEqual(report.weakSpots.map(\.headline), ["Middlegame decisions", "Shaky starts", "Loose pieces"])
        XCTAssertEqual(report.weakSpots.map(\.proof), ["24 costly moves with no single pattern.",
                                                       "16 costly moves in the first 12 moves.",
                                                       "Left one hanging 8 times."])
        XCTAssertEqual(report.leak?.area, .calculation)
        // The same order from the first games on, before any bar says where the player sits.
        let early = CoachReport.make(tallies: [game, game])
        XCTAssertFalse(early.isCompared)
        XCTAssertEqual(early.weakSpots.map(\.area), [.calculation, .openings, .safety])
    }

    func testAtMostThreeThingsToWorkOn() {
        let game = tally(weighted: [.safety: 3, .tactics: 6, .checkmates: 3, .openings: 6, .calculation: 9],
                         mistakes: [.safety: 1, .tactics: 2, .checkmates: 1, .openings: 2, .calculation: 3])
        let report = CoachReport.make(tallies: Array(repeating: game, count: 8))
        XCTAssertEqual(report.weakSpots.count, CoachReport.weakSpotLimit)
        XCTAssertEqual(report.weakSpots.first, report.leak)
    }

    func testAnAreaAheadOfMostPlayersIsLeftAloneUnlessItIsAllThereIs() {
        // Two small slips in tactics over three games: still ahead of most real players.
        let slip = tally(weighted: [.tactics: 1], mistakes: [.tactics: 1])
        let alone = CoachReport.make(tallies: [slip, slip, tally()])
        XCTAssertEqual(alone.weakSpots.map(\.area), [.tactics], "Ahead everywhere: the lowest is still the thing to work on")
        XCTAssertEqual(alone.weakSpots.first?.headline, "Tactics slipping by")
        XCTAssertEqual(alone.weakSpots.first?.proof, "Went by twice.")
        // With a real gap elsewhere, that gap is the list.
        let shaky = tally(weighted: [.tactics: 1, .openings: 8], mistakes: [.tactics: 1, .openings: 3])
        let both = CoachReport.make(tallies: [shaky, shaky, tally()])
        XCTAssertEqual(both.weakSpots.map(\.area), [.openings])
    }

    func testOneCostlyMoveIsNotAHabit() {
        let once = tally(weighted: [.openings: 3], mistakes: [.openings: 1])
        XCTAssertTrue(CoachReport.make(tallies: [once, tally(), tally()]).weakSpots.isEmpty)
    }

    func testWhichSavedPositionsBelongToWhichThingToWorkOn() {
        // A middlegame with every piece still on, at move 20.
        let middlegameFEN = "r1bq1rk1/pp2bppp/2n1pn2/3p4/3P4/2NBPN2/PP3PPP/R1BQ1RK1 w - - 0 20"
        typealias Positions = CoachReport.Positions
        // A pattern Leo named goes by its skill, wherever in the game it happened.
        XCTAssertTrue(Positions.skills(["threats", "back-rank"]).holds(saved(skill: "back-rank", fen: endgameFEN)))
        XCTAssertFalse(Positions.endgame.holds(saved(skill: "forks", fen: endgameFEN)))
        // A mistake with no pattern goes by the part of the game.
        XCTAssertTrue(Positions.opening.holds(saved(skill: "", fen: quietFEN)))
        XCTAssertTrue(Positions.opening.holds(saved(skill: "opening", fen: middlegameFEN)))
        XCTAssertFalse(Positions.opening.holds(saved(skill: "", fen: middlegameFEN)))
        XCTAssertTrue(Positions.middlegame.holds(saved(skill: "", fen: middlegameFEN)))
        XCTAssertFalse(Positions.middlegame.holds(saved(skill: "", fen: endgameFEN)))
        XCTAssertTrue(Positions.endgame.holds(saved(skill: "", fen: endgameFEN)))
        XCTAssertFalse(Positions.endgame.holds(saved(skill: "", fen: quietFEN)))
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

    func testAGameAgainstAPersonCountsOnceItIsGraded() {
        // Kept the moment it ends with no grades of the player's own: nothing to read yet.
        var friend = game(cleanMoves(20), level: nil)
        XCTAssertEqual(CoachReport.make(games: [friend]).gamesRead, 0)
        XCTAssertEqual(CoachReport.make(games: [friend, game(cleanMoves(20))]).gamesRead, 1)
        friend.graded = true
        XCTAssertEqual(CoachReport.make(games: [friend]).gamesRead, 1)
        XCTAssertEqual(CoachReport.make(games: [friend, game(cleanMoves(20))]).gamesRead, 2)
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
