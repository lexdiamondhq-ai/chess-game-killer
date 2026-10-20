import ChessKit
import XCTest
@testable import ChessGameKiller

final class HighlightReelTests: XCTestCase {

    private func moment(_ ply: Int, _ grade: MoveReview.Grade, before: Double, after: Double) -> ReelMoment {
        ReelMoment(ply: ply, grade: grade, san: "m\(ply)", uci: "e2e4", color: .white,
                   fenBefore: Position.standard.fen, fenAfter: Position.standard.fen, best: "Nf3",
                   before: before, after: after)
    }

    func testPicksTheStory() {
        let log = [
            1: moment(1, .good, before: 0.05, after: 0.04),
            3: moment(3, .blunder, before: 0.05, after: -0.6),
            5: moment(5, .best, before: 0.5, after: 0.5),     // they blundered back; this punishes it
            7: moment(7, .excellent, before: 0.55, after: 0.6),
        ]
        let reel = GameReel.make(log: log, player: "You", opponent: "Pulse", playerColor: .white, winner: .white,
                                 isOver: true, accuracy: 80, moveCount: 20, finalFEN: Position.standard.fen)
        XCTAssertEqual(reel.result, .win)
        XCTAssertEqual(reel.highlights.map(\.kind), [.blunder, .brilliant])
        XCTAssertEqual(reel.highlights.map(\.moment.ply), [3, 5])
        XCTAssertEqual(reel.narration.count, 4)
    }

    func testMateIsTheFinish() {
        let log = [9: moment(9, .checkmate, before: 0.9, after: 1)]
        let reel = GameReel.make(log: log, player: "You", opponent: "Spark", playerColor: .white, winner: .white,
                                 isOver: true, accuracy: nil, moveCount: 5, finalFEN: Position.standard.fen)
        XCTAssertEqual(reel.highlights.map(\.kind), [.finish])
    }

    func testScenesFollowTheClock() {
        let reel = GameReel.make(log: [3: moment(3, .blunder, before: 0, after: -0.5)], player: "You", opponent: "X",
                                 playerColor: .black, winner: nil, isOver: true, accuracy: nil, moveCount: 3,
                                 finalFEN: Position.standard.fen)
        XCTAssertEqual(reel.scene(at: 0.1), .intro(progress: 0.1 / GameReel.introLength))
        if case .highlight(let index, _) = reel.scene(at: GameReel.introLength + 1) {
            XCTAssertEqual(index, 0)
        } else {
            XCTFail("Expected the first highlight")
        }
        if case .outro = reel.scene(at: reel.length - 0.1) {} else { XCTFail("Expected the outro") }
        XCTAssertEqual(GameReel.allLines.count, 8)
    }
}
