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
}
