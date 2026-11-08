import XCTest
@testable import ChessGameKiller

/// The line under a rival's name while it waits.
final class RivalTauntTests: XCTestCase {
    func testEveryRivalHasShortLines() {
        for level in MatchController.Level.allCases {
            let lines = RivalTaunt.lines(for: level)
            XCTAssertFalse(lines.isEmpty, "\(level)")
            for line in lines {
                XCTAssertLessThanOrEqual(line.count, 38, "Too long for one row: \(line)")
            }
        }
    }

    func testOneLinePerGame() {
        let game = UUID()
        let first = RivalTaunt.line(for: .grandmaster, game: game)
        XCTAssertEqual(RivalTaunt.line(for: .grandmaster, game: game), first)
        XCTAssertTrue(RivalTaunt.lines(for: .grandmaster).contains(first))
    }
}
