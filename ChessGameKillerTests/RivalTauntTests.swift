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

    func testTheLineHoldsForTwoMovesThenRotates() {
        let game = UUID()
        let step = RivalTaunt.pliesPerLine
        let first = RivalTaunt.line(for: .grandmaster, game: game, ply: 0)
        XCTAssertEqual(RivalTaunt.line(for: .grandmaster, game: game, ply: step - 1), first)
        XCTAssertNotEqual(RivalTaunt.line(for: .grandmaster, game: game, ply: step), first)
        XCTAssertTrue(RivalTaunt.lines(for: .grandmaster).contains(first))
    }

    func testEveryLineComesRoundInAGame() {
        let game = UUID()
        for level in MatchController.Level.allCases {
            let lines = RivalTaunt.lines(for: level)
            let seen = Set((0..<lines.count).map { RivalTaunt.line(for: level, game: game, ply: $0 * RivalTaunt.pliesPerLine) })
            XCTAssertEqual(seen.count, lines.count, "\(level)")
        }
    }
}
