import ChessKit
import XCTest
@testable import ChessGameKiller

/// Talk it through on a training puzzle: when it is offered, what Leo is told, that a send counts
/// like a hint, and that Play makes the learner's answer, judged like a move made on the board.
@MainActor
final class TalkInTrainingTests: XCTestCase {

    // The back rank: Ra8 mates. No setup move, White to move.
    private let backRank = """
    {"id": "t-1", "skill": "back-rank", "type": "move", "rating": 500, "fen": "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "solution": ["a1a8"], "mate": 1}
    """
    // Black blunders the queen with ...Qh4, then White takes it.
    private let freeQueen = """
    {"id": "t-2", "skill": "free-pieces", "type": "move", "rating": 400,
     "fen": "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2", "setup": "d8h4", "solution": ["f3h4"]}
    """
    // An answer in two moves of the learner's, with the other side's reply between.
    private let twoSteps = """
    {"id": "t-7", "skill": "back-rank", "type": "move", "rating": 600, "fen": "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1", "solution": ["a1a7", "h7h6", "a7a8"]}
    """

    private func runner(_ json: String, strict: Bool = false) throws -> DrillRunner {
        let drill = try JSONDecoder().decode(Drill.self, from: Data(json.utf8))
        let made = try XCTUnwrap(DrillRunner(item: SessionItem(content: .drill(drill), role: .focus), library: nil,
                                             engine: nil, playsSounds: false))
        made.strict = strict
        return made
    }

    private func waitUntil(_ what: String, timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline {
                XCTFail("Timed out waiting until \(what)")
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func solving(_ runner: DrillRunner) async {
        runner.begin()
        await waitUntil("the learner is to move") { runner.phase == .solving }
    }

    // MARK: When Talk is offered

    func testTalkIsOfferedOnAFindTheMovePuzzle() async throws {
        let runner = try runner(freeQueen)
        XCTAssertFalse(runner.canTalkItThrough, "not while the other side's move plays")
        XCTAssertNil(runner.talkSession())

        await solving(runner)
        XCTAssertTrue(runner.canTalkItThrough)
        let session = try XCTUnwrap(runner.talkSession())
        XCTAssertEqual(session.fen, runner.game.fen)
        XCTAssertEqual(session.player, .white)
        XCTAssertEqual(session.context, .session)
        XCTAssertFalse(session.reveal, "Leo never names the answer")
        XCTAssertEqual(session.lastMove, "d8h4", "Leo knows the move that set it up")
    }

    func testNoTalkWhereThereIsNoHelp() async throws {
        let rush = try runner(backRank, strict: true)
        await solving(rush)
        XCTAssertFalse(rush.canTalkItThrough, "Rush and Cycles give no help")
        XCTAssertNil(rush.talkSession())

        let tap = try runner("""
        {"id": "t-4", "skill": "threats", "type": "tap", "rating": 500,
         "fen": "r1bqk2r/ppp2ppp/2np1n2/2b1p1B1/2B1P3/2NP1N2/PPP2PPP/R2QK2R b KQkq - 1 6", "setup": "h7h6", "squares": ["g5"]}
        """)
        await solving(tap)
        XCTAssertFalse(tap.canTalkItThrough, "only puzzles that ask for a move")

        let safe = try runner("""
        {"id": "t-3", "skill": "safety", "type": "safe", "rating": 500,
         "fen": "r1bqkbnr/pppp1pp1/2n4p/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4",
         "move": "f3g5", "answer": false, "reply": "h6g5", "explain": "The h6 pawn takes it."}
        """)
        await solving(safe)
        XCTAssertFalse(safe.canTalkItThrough)
    }

    func testNoTalkOnceItIsSolved() async throws {
        let runner = try runner(backRank)
        await solving(runner)
        XCTAssertTrue(runner.playLearnerMove("a1a8"))
        XCTAssertTrue(runner.isDone)
        XCTAssertFalse(runner.canTalkItThrough)
        XCTAssertNil(runner.talkSession())
    }

    // MARK: What counts as help

    func testATalkCountsLikeAHint() async throws {
        let runner = try runner(backRank)
        await solving(runner)
        let session = try XCTUnwrap(runner.talkSession())
        XCTAssertFalse(runner.talkedThrough, "opening the talk is free")
        session.onSend?()
        XCTAssertTrue(runner.talkedThrough)
        XCTAssertFalse(runner.usedHint, "Hint is still there after a talk")
        XCTAssertTrue(runner.canTalkItThrough, "and so is another talk")

        XCTAssertTrue(runner.playLearnerMove("a1a8"))
        XCTAssertEqual(runner.outcome, .withHint)
    }

    func testOpeningATalkWithoutSendingIsFree() async throws {
        let runner = try runner(backRank)
        await solving(runner)
        _ = try XCTUnwrap(runner.talkSession())
        XCTAssertTrue(runner.playLearnerMove("a1a8"))
        XCTAssertEqual(runner.outcome, .firstTry)
    }

    func testAMissStillCountsForMoreThanATalk() async throws {
        let runner = try runner(backRank)
        await solving(runner)
        runner.talkSession()?.onSend?()
        XCTAssertTrue(runner.playLearnerMove("h2h3"))
        await waitUntil("the wrong move is taken back") { runner.phase == .solving }
        XCTAssertTrue(runner.playLearnerMove("a1a8"))
        XCTAssertEqual(runner.outcome, .afterMistake)
    }

    // MARK: Play

    func testPlayIsJudgedLikeAMoveOnTheBoard() async throws {
        let runner = try runner(backRank)
        await solving(runner)
        let start = runner.game.fen

        XCTAssertTrue(runner.playLearnerMove("h2h3"))
        XCTAssertEqual(runner.mistakes, 1)
        XCTAssertEqual(runner.phase, .waiting)
        XCTAssertFalse(runner.canTalkItThrough, "not while the wrong move is shown")
        await waitUntil("the wrong move is taken back") { runner.phase == .solving }
        XCTAssertEqual(runner.game.fen, start)
        XCTAssertNil(runner.talkSession()?.lastMove, "nothing was played before this puzzle")

        XCTAssertTrue(runner.playLearnerMove("a1a8"))
        XCTAssertEqual(runner.outcome, .afterMistake)
    }

    func testPlayNeedsALegalMoveOnTheLearnersTurn() async throws {
        let runner = try runner(backRank)
        XCTAssertFalse(runner.playLearnerMove("a1a8"), "not before the puzzle starts")
        await solving(runner)
        let start = runner.game.fen
        XCTAssertFalse(runner.playLearnerMove("a1h8"), "not a legal move")
        XCTAssertFalse(runner.playLearnerMove("g8h8"), "not the learner's piece")
        XCTAssertFalse(runner.playLearnerMove("e2e4"), "no piece there")
        XCTAssertFalse(runner.playLearnerMove("a1"), "not a move")
        XCTAssertEqual(runner.game.fen, start)
        XCTAssertEqual(runner.mistakes, 0)
        XCTAssertEqual(runner.phase, .solving)
    }

    func testTalkFollowsALongerAnswer() async throws {
        let runner = try runner(twoSteps)
        await solving(runner)
        XCTAssertTrue(runner.playLearnerMove("a1a7"))
        XCTAssertFalse(runner.canTalkItThrough, "not while their reply plays")
        await waitUntil("their reply is played") { runner.phase == .solving }

        let session = try XCTUnwrap(runner.talkSession())
        XCTAssertEqual(session.lastMove, "h7h6", "Leo knows their reply")
        XCTAssertEqual(session.fen, runner.game.fen)
        XCTAssertTrue(runner.playLearnerMove("a7a8"))
        XCTAssertEqual(runner.outcome, .firstTry)
    }

    func testAfterAWrongTryLeoStillKnowsTheMoveThatSetItUp() async throws {
        let runner = try runner(freeQueen)
        await solving(runner)
        XCTAssertTrue(runner.playLearnerMove("a2a3"))
        await waitUntil("the wrong move is taken back") { runner.phase == .solving }
        XCTAssertEqual(runner.talkSession()?.lastMove, "d8h4")
        XCTAssertTrue(runner.playLearnerMove("f3h4"))
        XCTAssertEqual(runner.outcome, .afterMistake)
    }
}
