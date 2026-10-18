import ChessKit
import XCTest
@testable import ChessGameKiller

final class CoachTests: XCTestCase {

    // MARK: Evaluation

    func testWinningChancesFollowTheLichessCurve() {
        XCTAssertEqual(Evaluation.centipawns(0).winningChances, 0, accuracy: 0.0001)
        XCTAssertEqual(Evaluation.centipawns(100).winningChances, 0.182, accuracy: 0.001)
        XCTAssertEqual(Evaluation.centipawns(-100).winningChances, -0.182, accuracy: 0.001)
        // Clamped at ten pawns.
        XCTAssertEqual(Evaluation.centipawns(5000).winningChances, Evaluation.centipawns(1000).winningChances)
        XCTAssertEqual(Evaluation.mate(3).winningChances, 1)
        XCTAssertEqual(Evaluation.mate(-2).winningChances, -1)
    }

    func testFlippingSwapsSides() {
        XCTAssertEqual(Evaluation.centipawns(120).flipped, .centipawns(-120))
        XCTAssertEqual(Evaluation.mate(2).flipped, .mate(-2))
    }

    func testLabels() {
        XCTAssertEqual(Evaluation.centipawns(130).label, "+1.3")
        XCTAssertEqual(Evaluation.centipawns(-46).label, "-0.5")
        XCTAssertEqual(Evaluation.centipawns(0).label, "+0.0")
        XCTAssertEqual(Evaluation.mate(3).label, "M3")
        XCTAssertEqual(Evaluation.mate(-1).label, "-M1")
    }

    // MARK: Grading

    func testPlayingTheEnginesMoveIsBest() {
        XCTAssertEqual(MoveReview.grade(before: .centipawns(30), after: .centipawns(-500), playedBest: true), .best)
    }

    func testGradesFollowTheLossInWinningChances() {
        let before = Evaluation.centipawns(0)
        XCTAssertEqual(MoveReview.grade(before: before, after: .centipawns(-5), playedBest: false), .excellent)
        XCTAssertEqual(MoveReview.grade(before: before, after: .centipawns(-30), playedBest: false), .good)
        XCTAssertEqual(MoveReview.grade(before: before, after: .centipawns(-60), playedBest: false), .inaccuracy)
        XCTAssertEqual(MoveReview.grade(before: before, after: .centipawns(-130), playedBest: false), .mistake)
        XCTAssertEqual(MoveReview.grade(before: before, after: .centipawns(-400), playedBest: false), .blunder)
    }

    func testMissingAMateIsABlunder() {
        XCTAssertEqual(MoveReview.grade(before: .mate(2), after: .centipawns(150), playedBest: false), .blunder)
    }

    func testReviewTextNamesTheBetterMove() {
        let review = MoveReview(id: 0, grade: .mistake, played: "a3", best: "e4", evaluation: .centipawns(-120))
        XCTAssertEqual(review.title, "Mistake")
        XCTAssertTrue(review.detail.contains("a3"))
        XCTAssertTrue(review.detail.contains("e4"))
    }

    // MARK: Notation

    func testSquaresFromEngineMoves() {
        let squares = Notation.squares(of: "g1f3")
        XCTAssertEqual(squares?.from, .g1)
        XCTAssertEqual(squares?.to, .f3)
        XCTAssertEqual(Notation.squares(of: "e7e8q")?.to, .e8)
        XCTAssertNil(Notation.squares(of: "z9a1"))
        XCTAssertNil(Notation.squares(of: "(none)"))
    }

    func testStandardNotationFromEngineMoves() {
        let start = Position.standard.fen
        XCTAssertEqual(Notation.san(of: "g1f3", fen: start), "Nf3")
        XCTAssertEqual(Notation.san(of: "e2e4", fen: start), "e4")
        XCTAssertNil(Notation.san(of: "e2e5", fen: start))
    }

    func testCastlingAndPromotionNotation() {
        let castling = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
        XCTAssertEqual(Notation.san(of: "e1g1", fen: castling), "O-O")
        XCTAssertEqual(Notation.san(of: "e1c1", fen: castling), "O-O-O")

        let promotion = "7k/P7/8/8/8/8/8/K7 w - - 0 1"
        XCTAssertEqual(Notation.san(of: "a7a8q", fen: promotion), "a8=Q+")
        XCTAssertEqual(Notation.san(of: "a7a8n", fen: promotion), "a8=N")
    }
}
