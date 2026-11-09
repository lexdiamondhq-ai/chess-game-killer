import XCTest
@testable import ChessGameKiller

/// Stockfish's output arrives in chunks that need not end at a line break.
final class LineSplitterTests: XCTestCase {

    func testWholeLines() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.append(Array("readyok\nbestmove e2e4 ponder e7e5\n".utf8)),
                       ["readyok", "bestmove e2e4 ponder e7e5"])
    }

    /// The case that lost answers: a chunk ends partway through "bestmove".
    func testALineCutBetweenChunksComesOutWhole() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.append(Array("info depth 5 score cp 30 pv e2e4\nbestmo".utf8)),
                       ["info depth 5 score cp 30 pv e2e4"])
        XCTAssertEqual(splitter.append(Array("ve e2e4".utf8)), [])
        XCTAssertEqual(splitter.append(Array(" ponder e7e5\n".utf8)), ["bestmove e2e4 ponder e7e5"])
    }

    func testCarriageReturnsAndBlankLines() {
        var splitter = LineSplitter()
        XCTAssertEqual(splitter.append(Array("uciok\r\n\nreadyok\n".utf8)), ["uciok", "", "readyok"])
    }
}
