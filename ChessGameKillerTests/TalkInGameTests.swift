import ChessKit
import XCTest
@testable import ChessGameKiller

/// Talk it through inside a game: when it is offered, what Leo is told, what counts as help,
/// and that Play makes the player's own move.
@MainActor
final class TalkInGameTests: XCTestCase {

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

    func testTalkIsOfferedOnThePlayersTurnOnly() async throws {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.start(MatchController.Setup())
        XCTAssertTrue(match.canTalkItThrough)
        let opening = try XCTUnwrap(match.talkSession())
        XCTAssertEqual(opening.fen, match.game.fen)
        XCTAssertEqual(opening.player, .white)
        XCTAssertEqual(opening.context, .game)
        XCTAssertFalse(opening.reveal, "in a game Leo never names the best move")
        XCTAssertNil(opening.lastMove)

        XCTAssertTrue(match.playOwnMove("e2e4"))
        XCTAssertFalse(match.canTalkItThrough, "the rival is to move")
        XCTAssertNil(match.talkSession())

        await waitUntil("the rival replies") { match.game.plyCount == 2 && match.game.isHumanTurn }
        let reply = try XCTUnwrap(match.game.lastPlayed)
        let next = try XCTUnwrap(match.talkSession())
        XCTAssertEqual(next.lastMove, reply.uci, "Leo knows what they just played")
        XCTAssertEqual(next.fen, match.game.fen)
    }

    func testNoTalkOnceTheGameIsOver() throws {
        let match = MatchController(engine: nil, sounds: nil)
        match.startTapping()
        XCTAssertTrue(match.playOwnMove("e2e4"))
        match.resign()
        XCTAssertTrue(match.isOver)
        XCTAssertFalse(match.canTalkItThrough)
        XCTAssertNil(match.talkSession())
    }

    func testAMovePlayedFromTalkIsTheirOwnAndGraded() async {
        let start = GameModel().fen
        let engine = FakeEngine(scripted: [
            start: [
                EngineLine(moves: ["e2e4", "e7e5"], evaluation: .centipawns(30)),
                EngineLine(moves: ["d2d4", "d7d5"], evaluation: .centipawns(25)),
            ],
        ])
        let match = MatchController(engine: engine, sounds: nil)
        match.startTapping()
        await waitUntil("hints appear") { match.hints.count == 2 }

        XCTAssertTrue(match.playOwnMove("e2e4"))
        XCTAssertEqual(match.game.moves, ["e4"])
        await waitUntil("the move is graded") { match.review != nil }
        XCTAssertEqual(match.review?.grade, .best)
        XCTAssertEqual(match.review?.played, "e4")
        XCTAssertFalse(match.wasAssisted, "their own move isn't help, unlike playing Leo's pick")
    }

    func testPlayFromTalkNeedsALegalMoveOnTheirTurn() {
        let match = MatchController(engine: nil, sounds: nil)
        match.start(MatchController.Setup())
        XCTAssertFalse(match.playOwnMove("e2e5"), "not a legal move")
        XCTAssertFalse(match.playOwnMove("e7e5"), "not their piece")
        XCTAssertFalse(match.playOwnMove("e2"), "not a move")
        XCTAssertEqual(match.game.plyCount, 0)

        XCTAssertTrue(match.playOwnMove("g1f3"))
        XCTAssertEqual(match.game.moves, ["Nf3"])
        XCTAssertFalse(match.playOwnMove("b8c6"), "the rival is to move")
        XCTAssertEqual(match.game.plyCount, 1)
    }

    func testTalkingItThroughCountsAsHelp() throws {
        let match = MatchController(engine: nil, sounds: nil)
        match.startTapping()
        XCTAssertFalse(match.talkCountsAsHelp, "before the first move there is nothing to help with")
        XCTAssertTrue(match.playOwnMove("e2e4"))
        XCTAssertTrue(match.talkCountsAsHelp)

        let session = try XCTUnwrap(match.talkSession())
        XCTAssertEqual(session.player, .black)
        XCTAssertEqual(session.lastMove, "e2e4")
        XCTAssertFalse(match.wasAssisted, "opening the talk is free")
        session.onSend?()
        XCTAssertTrue(match.wasAssisted)
        XCTAssertFalse(match.talkCountsAsHelp, "the game has had help already")
    }
}
