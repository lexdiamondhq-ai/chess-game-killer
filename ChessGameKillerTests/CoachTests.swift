import ChessKit
import XCTest
@testable import ChessGameKiller

final class CoachTests: XCTestCase {

    // MARK: Evaluation

    /// The spotlight's words under the board.
    func testHintWords() {
        XCTAssertEqual(HintWords.phrase(san: "Nxe4", mover: .knight, taken: .queen), "Knight takes the queen")
        XCTAssertEqual(HintWords.phrase(san: "e4", mover: .pawn, taken: nil), "Pawn to e4")
        XCTAssertEqual(HintWords.phrase(san: "Qh7#", mover: .queen, taken: nil), "Queen to h7, checkmate")
        XCTAssertEqual(HintWords.phrase(san: "Bb5+", mover: .bishop, taken: nil), "Bishop to b5, check")
        XCTAssertEqual(HintWords.phrase(san: "O-O", mover: .king, taken: nil), "Castle kingside")
        XCTAssertEqual(HintWords.phrase(san: "O-O-O+", mover: .king, taken: nil), "Castle queenside, check")
        XCTAssertEqual(HintWords.phrase(san: "exd6", mover: .pawn, taken: nil), "Pawn takes the pawn", "En passant")
        XCTAssertEqual(HintWords.phrase(san: "e8=Q", mover: .pawn, taken: nil), "Pawn to e8, becomes a queen")
        XCTAssertEqual(HintWords.phrase(san: "dxc8=N+", mover: .pawn, taken: .rook), "Pawn takes the rook, becomes a knight, check")
    }

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
        XCTAssertEqual(Evaluation.centipawns(0).label, "0.0")
        // A level position never flickers between "+0.0" and "-0.0".
        XCTAssertEqual(Evaluation.centipawns(-3).label, "0.0")
        XCTAssertEqual(Evaluation.centipawns(4).label, "0.0")
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

    // MARK: Grading a game that is already lopsided
    // Winning chances flatten out far from equal, so these used to read "Excellent" or "Good".

    /// From a game against the 1200s: White twelve pawns down, every rook or knight move
    /// but one walked into mate, and each was called "Good".
    func testWalkingIntoMateIsABlunderEvenWhenAlreadyLost() {
        XCTAssertEqual(MoveReview.grade(before: .centipawns(-1220), after: .mate(-1), playedBest: false), .blunder)
        XCTAssertEqual(MoveReview.grade(before: .centipawns(-1220), after: .mate(-10), playedBest: false), .blunder)
        XCTAssertEqual(MoveReview.grade(before: .centipawns(-300), after: .mate(-4), playedBest: false), .blunder)
    }

    func testAMateThatWasComingAnywayIsNoBlunder() {
        XCTAssertEqual(MoveReview.grade(before: .mate(-3), after: .mate(-2), playedBest: false), .excellent)
    }

    /// White is ten pawns down and the bishop on c5 is attacked. 10. a3?? leaves it to be taken.
    /// The lines are Stockfish 17's at depth 12.
    private let hangingBishop = "r1bqkbnr/ppp2ppp/2n5/2B5/8/8/PPP2PPP/R3K2R w KQkq - 1 10"
    private let tradeTheBishop = ["c5f8", "e8f8", "e1g1", "f8e8"]

    func testHangingAPieceWhenAlreadyLostIsABlunder() {
        let played = ["a2a3", "f8c5", "e1g1", "g8f6", "f1e1", "c8e6", "b2b4"]
        let loss = MoveReview.materialLoss(fen: hangingBishop, best: tradeTheBishop, played: played)
        XCTAssertEqual(loss, 3)
        XCTAssertEqual(MoveReview.grade(before: .centipawns(-1009), after: .centipawns(-1204), playedBest: false,
                                        materialLoss: loss), .blunder)
        // The curve alone can't see it.
        XCTAssertEqual(MoveReview.grade(before: .centipawns(-1009), after: .centipawns(-1204), playedBest: false), .excellent)
    }

    /// 10. g3 lets Black move first, but the bishops still come off a move later: no loss.
    func testATradeAMoveLaterIsNotALoss() {
        let played = ["g2g3", "c8e6", "c5f8", "e8f8", "e1g1", "g8f6", "f1e1"]
        XCTAssertEqual(MoveReview.materialLoss(fen: hangingBishop, best: tradeTheBishop, played: played), 0)
    }

    func testMissingAFreePieceCounts() {
        // White is twelve pawns up and Black's bishop on c4 is free. 10. a3 lets it trade itself off
        // instead: passing over a free piece costs the same as giving one away.
        let fen = "r3k2r/ppp2ppp/8/8/2b5/8/PPP2PPP/RNBQKBNR w KQkq - 0 10"
        let loss = MoveReview.materialLoss(fen: fen, best: ["f1c4", "e8g8", "b1c3", "a8e8"],
                                           played: ["a2a3", "c4f1", "e1f1", "e8g8", "b1c3"])
        XCTAssertEqual(loss, 3)
    }

    func testASoundSacrificeIsNotPunished() {
        // The engine scores it about as well as its own move, so the material isn't held against it.
        XCTAssertEqual(MoveReview.grade(before: .centipawns(50), after: .centipawns(40), playedBest: false,
                                        materialLoss: 3), .excellent)
    }

    func testGivingBackMaterialWhileStillWinningIsAtWorstAMistake() {
        XCTAssertEqual(MoveReview.grade(before: .centipawns(1200), after: .centipawns(950), playedBest: false,
                                        materialLoss: 3), .mistake)
        XCTAssertEqual(MoveReview.grade(before: .centipawns(1200), after: .centipawns(950), playedBest: false,
                                        materialLoss: 1), .inaccuracy)
    }

    func testMaterialNeedsAWholeMoveOfEachLine() {
        XCTAssertNil(MoveReview.materialLoss(fen: hangingBishop, best: ["c5f8"], played: ["a2a3", "f8c5"]))
        XCTAssertNil(MoveReview.materialLoss(fen: hangingBishop, best: tradeTheBishop, played: []))
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
