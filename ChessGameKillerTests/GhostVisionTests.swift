import ChessKit
import XCTest
@testable import ChessGameKiller

/// Ghost Vision: the engine's line played out on a copy of the game, the slide through it,
/// and how a game learns of it (it is help, and costs the engine nothing extra).
@MainActor
final class GhostVisionTests: XCTestCase {

    private func line(_ moves: String..., cp: Int = 30) -> EngineLine {
        EngineLine(moves: moves, evaluation: .centipawns(cp))
    }

    private func fen(after moves: String...) -> String {
        let game = GameModel()
        for move in moves { XCTAssertTrue(game.playEngineMove(move), "\(move) should be legal") }
        return game.fen
    }

    // MARK: The line

    func testStepsFollowTheLineFourMovesDeep() throws {
        let start = Position.standard.fen
        let ghost = try XCTUnwrap(GhostLine.build(fen: start, line: line("e2e4", "e7e5", "g1f3", "b8c6", "f1c4")))
        XCTAssertEqual(ghost.steps.count, GhostLine.depth, "four moves ahead, no more")
        XCTAssertEqual(ghost.steps.map(\.san), ["e4", "e5", "Nf3", "Nc6"])
        XCTAssertEqual(ghost.steps.map(\.color), [.white, .black, .white, .black])
        XCTAssertEqual(ghost.steps[2].main.from, .g1)
        XCTAssertEqual(ghost.steps[2].main.to, .f3)
        XCTAssertEqual(ghost.steps[2].main.piece.kind, .knight)
        XCTAssertNil(ghost.steps[0].captured)
        XCTAssertEqual(ghost.notation(), ["1. e4", "e5", "2. Nf3", "Nc6"])
        XCTAssertEqual(ghost.notation(upTo: 1), ["1. e4", "e5"])
    }

    func testACaptureMarksTheTakenPiece() throws {
        let start = fen(after: "e2e4", "d7d5")
        let ghost = try XCTUnwrap(GhostLine.build(fen: start, line: line("e4d5", "d8d5")))
        XCTAssertEqual(ghost.steps[0].captured?.square, .d5)
        XCTAssertEqual(ghost.steps[0].captured?.color, .black)
        XCTAssertEqual(ghost.steps[1].captured?.kind, .pawn)
        XCTAssertEqual(ghost.steps[1].captured?.color, .white)
        XCTAssertEqual(ghost.notation(), ["2. exd5", "Qxd5"])
    }

    func testEnPassantTakesThePawnBeside() throws {
        let start = fen(after: "e2e4", "a7a6", "e4e5", "d7d5")
        let ghost = try XCTUnwrap(GhostLine.build(fen: start, line: line("e5d6")))
        XCTAssertEqual(ghost.steps[0].main.to, .d6)
        XCTAssertEqual(ghost.steps[0].captured?.square, .d5, "the pawn taken stood beside, not on d6")
    }

    func testCastlingMovesTheRookToo() throws {
        let start = fen(after: "e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5")
        let ghost = try XCTUnwrap(GhostLine.build(fen: start, line: line("e1g1")))
        let moves = ghost.steps[0].moves
        XCTAssertEqual(moves.count, 2)
        XCTAssertEqual(moves[0].piece.kind, .king)
        XCTAssertEqual(moves[0].to, .g1)
        XCTAssertEqual(moves[1].piece.kind, .rook)
        XCTAssertEqual(moves[1].from, .h1)
        XCTAssertEqual(moves[1].to, .f1)
    }

    func testAPromotedPawnLandsAsItsNewPiece() throws {
        let start = "8/4P1k1/8/8/8/8/8/4K3 w - - 0 1"
        let ghost = try XCTUnwrap(GhostLine.build(fen: start, line: line("e7e8q", "g7h7")))
        XCTAssertEqual(ghost.steps[0].main.piece.kind, .queen)
        XCTAssertEqual(ghost.steps[0].main.from, .e7)
        XCTAssertEqual(ghost.steps[0].main.to, .e8)
        XCTAssertTrue(ghost.notation().first?.hasPrefix("1. e8") == true)
    }

    func testTheLineStopsAtAMoveThatDoesNotFit() throws {
        let start = Position.standard.fen
        let ghost = try XCTUnwrap(GhostLine.build(fen: start, line: line("e2e4", "e2e4", "g1f3")))
        XCTAssertEqual(ghost.steps.count, 1)
        XCTAssertNil(GhostLine.build(fen: start, line: line("e7e5")), "Black can't move first")
    }

    func testBlackToMoveCountsMovesFromTheFEN() throws {
        let start = fen(after: "e2e4")
        let ghost = try XCTUnwrap(GhostLine.build(fen: start, line: line("c7c5", "g1f3", "d7d6")))
        XCTAssertEqual(ghost.notation(), ["1… c5", "2. Nf3", "d6"])
    }

    // MARK: Fading and sliding

    func testEachStepIsFainterAndLaterOnesHide() {
        let opacities = (0..<4).map { GhostLine.opacity(of: $0, focus: 3) }
        XCTAssertEqual(opacities, [0.6, 0.4, 0.25, 0.15])
        XCTAssertEqual(GhostLine.opacity(of: 2, focus: 1), 0)
        XCTAssertEqual(GhostLine.opacity(of: 1, focus: 1), 0.4)
    }

    func testSlidingLeftTakesMovesAwayAndRightBringsThemBack() {
        let width = GhostVision.stepWidth
        XCTAssertNil(GhostVision.focus(forDrag: 0, steps: 4), "the whole line to start")
        XCTAssertNil(GhostVision.focus(forDrag: -width * 0.4, steps: 4), "a wobble isn't a step")
        XCTAssertEqual(GhostVision.focus(forDrag: -width, steps: 4), 2)
        XCTAssertEqual(GhostVision.focus(forDrag: -width * 3, steps: 4), 0)
        XCTAssertEqual(GhostVision.focus(forDrag: -width * 9, steps: 4), 0, "never past the first move")
        XCTAssertNil(GhostVision.focus(forDrag: width * 2, steps: 4))

        let vision = GhostVision()
        vision.begin()
        XCTAssertTrue(vision.isHolding)
        XCTAssertTrue(vision.swallowsTap)
        vision.scrub(dx: -width * 2, steps: 4)
        XCTAssertEqual(vision.shownFocus(steps: 4), 1)
        vision.end()
        XCTAssertFalse(vision.isHolding)
        XCTAssertNil(vision.focus)
        XCTAssertTrue(vision.swallowsTap, "the tap that ends a hold isn't a move")
    }

    // MARK: In a game

    func testTheLineComesWithTheHintsEvenWhenTheyAreHidden() async throws {
        let start = Position.standard.fen
        let engine = FakeEngine(scripted: [start: [
            line("e2e4", "e7e5", "g1f3", "b8c6"),
            line("d2d4", "d7d5"),
        ]])
        let match = MatchController(engine: engine, sounds: nil)
        match.showBestMoves = false
        match.start(MatchController.Setup(playerColor: .white, level: .club))
        await waitUntil("the line is found") { match.ghostLine != nil }
        XCTAssertTrue(match.hints.isEmpty, "hints stay hidden")
        XCTAssertEqual(match.ghostLine?.steps.map(\.san), ["e4", "e5", "Nf3", "Nc6"])
        XCTAssertTrue(match.canPeekAhead)
        let searches = await engine.analyzed.count

        // A move on the board puts the old line away.
        match.tap(.d2)
        match.tap(.d4)
        XCTAssertNil(match.ghostLine)
        XCTAssertFalse(match.canPeekAhead, "the rival's turn")
        let searchesAfter = await engine.analyzed.count
        XCTAssertEqual(searches, searchesAfter, "Ghost Vision asks the engine for nothing of its own")
    }

    func testSeeingTheLineIsHelp() async {
        let match = MatchController(engine: FakeEngine(), sounds: nil)
        match.startTapping()
        match.tap(.e2)
        match.tap(.e4)
        await waitUntil("the line is found") { match.ghostLine != nil }
        XCTAssertFalse(match.wasAssisted)
        match.markAssisted()
        XCTAssertTrue(match.wasAssisted)
        XCTAssertTrue(match.armyStakes.assisted)
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
}
