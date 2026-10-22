import ChessKit
import XCTest
@testable import ChessGameKiller

/// Runs the real Stockfish bundled in the app.
final class StockfishTests: XCTestCase {

    func testNetworkFilesAreBundled() {
        XCTAssertTrue(StockfishEngine.hasNetworks, "Run scripts/fetch_nnue.sh (Xcode does it as a build phase)")
    }

    func testAnalyzesTheStartingPosition() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let start = Position.standard.fen
        let lines = await StockfishEngine.shared.analyze(fen: start, depth: 10, lines: 2)
        XCTAssertEqual(lines.count, 2)
        guard lines.count == 2 else { return }
        for line in lines {
            let move = try XCTUnwrap(line.firstMove)
            XCTAssertNotNil(Notation.san(of: move, fen: start), "\(move) should be legal")
        }
        XCTAssertNotEqual(lines[0].firstMove, lines[1].firstMove)
    }

    func testFindsMateInOne() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let backRank = "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"
        let lines = await StockfishEngine.shared.analyze(fen: backRank, depth: 8, lines: 1)
        XCTAssertEqual(lines.first?.firstMove, "a1a8")
        XCTAssertEqual(lines.first?.evaluation, .mate(1))
    }

    func testChoosesALegalMoveAtLowSkill() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
        let chosen = await StockfishEngine.shared.chooseMove(fen: fen, skill: 0, thinkTimeMs: 100)
        let move = try XCTUnwrap(chosen)
        XCTAssertNotNil(Notation.san(of: move, fen: fen), "\(move) should be legal")
    }

    /// How long the computer takes to answer a move at every level, with the real engine,
    /// while the coach is still busy on the player's turn (as in the app). Printed as
    /// TIMING lines in the CI log; the bound only catches a reply that hangs.
    @MainActor
    func testComputerRepliesQuicklyAtEveryLevel() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        await StockfishEngine.shared.warmUp()
        StockfishEngine.trace = { NSLog("TIMING engine %@", $0) }
        defer { StockfishEngine.trace = nil }
        for level in MatchController.Level.allCases {
            let match = MatchController(engine: StockfishEngine.shared, sounds: nil)
            match.start(.init(opponent: .computer, playerColor: .white, level: level), playSound: false)
            // Let the hint search get going, so the reply has to stop it first.
            try? await Task.sleep(for: .milliseconds(300))
            let started = ContinuousClock.now
            NSLog("TIMING reply level=\(level) person moves")
            match.tap(.e2)
            match.tap(.e4)
            XCTAssertEqual(match.game.plyCount, 1)
            var waited = 0
            while match.game.plyCount < 2, waited < 1000 {
                try? await Task.sleep(for: .milliseconds(5))
                waited += 1
            }
            let elapsed = ContinuousClock.now - started
            let ms = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            NSLog("TIMING reply level=\(level) think=\(level.thinkTimeMs)ms total=\(ms)ms")
            XCTAssertEqual(match.game.plyCount, 2, "\(level) never answered")
            XCTAssertLessThan(ms, level.thinkTimeMs + 2500, "\(level) took \(ms) ms to answer")
            // Leave the engine alone for the next level: no grading or hints still running.
            match.start(.init(opponent: .friend), playSound: false)
        }
    }

    /// Alex's report: Spark as white never made its first move. Every rival opens as
    /// white with the real engine, including when the new game starts while the last
    /// game's hint search is still running (the usual way into a game).
    @MainActor
    func testEveryRivalOpensAsWhite() async throws {
        try XCTSkipUnless(StockfishEngine.hasNetworks)
        await StockfishEngine.shared.warmUp()
        StockfishEngine.trace = { NSLog("TIMING engine %@", $0) }
        defer { StockfishEngine.trace = nil }
        let match = MatchController(engine: StockfishEngine.shared, sounds: nil)
        for level in MatchController.Level.allCases {
            // A game where the person is to move, so a long hint search is under way.
            match.start(.init(opponent: .computer, playerColor: .white, level: level), playSound: false)
            try? await Task.sleep(for: .milliseconds(300))
            let started = ContinuousClock.now
            match.start(.init(opponent: .computer, playerColor: .black, level: level), playSound: false)
            var waited = 0
            while match.game.plyCount < 1, waited < 1200 {
                try? await Task.sleep(for: .milliseconds(5))
                waited += 1
            }
            let elapsed = ContinuousClock.now - started
            NSLog("TIMING opening level=\(level) total=\(elapsed)")
            XCTAssertEqual(match.game.plyCount, 1, "\(level) never opened as white")
            XCTAssertEqual(match.game.sideToMove, .black)
            XCTAssertFalse(match.engineFailed, "\(level) said the engine was unavailable")
        }
        match.start(.init(opponent: .friend), playSound: false)
    }
}
