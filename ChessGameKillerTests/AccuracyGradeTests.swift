import XCTest
@testable import ChessGameKiller

/// The result's accuracy takes the color of the grade it reads as: green only for a good game.
final class AccuracyGradeTests: XCTestCase {
    func testHighAccuracyReadsAsBest() {
        XCTAssertEqual(MoveReview.Grade.forAccuracy(100), .best)
        XCTAssertEqual(MoveReview.Grade.forAccuracy(90), .best)
    }

    func testEachBandHasItsGrade() {
        XCTAssertEqual(MoveReview.Grade.forAccuracy(89), .excellent)
        XCTAssertEqual(MoveReview.Grade.forAccuracy(75), .good)
        XCTAssertEqual(MoveReview.Grade.forAccuracy(60), .inaccuracy)
        XCTAssertEqual(MoveReview.Grade.forAccuracy(45), .mistake)
    }

    func testLowAccuracyIsNeverGreen() {
        XCTAssertEqual(MoveReview.Grade.forAccuracy(10), .blunder)
        XCTAssertEqual(MoveReview.Grade.forAccuracy(0), .blunder)
    }
}
