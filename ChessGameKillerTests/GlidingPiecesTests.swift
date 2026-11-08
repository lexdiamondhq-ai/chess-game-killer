import ChessKit
import XCTest
@testable import ChessGameKiller

/// The boards that draw a position (Analyze, the editor, the home's small boards) keep each
/// piece's identity from one position to the next, so a piece glides to its new square.
final class GlidingPiecesTests: XCTestCase {
    private static let start = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    private func arrange(_ fen: String, with identities: PieceIdentities) throws -> PieceIdentities.Arrangement {
        let draft = try XCTUnwrap(PositionDraft(fen: fen), fen)
        return identities.arrange(draft.pieces, key: draft.placementFEN)
    }

    private func id(at square: Square, in arrangement: PieceIdentities.Arrangement) throws -> Int {
        try XCTUnwrap(arrangement.pieces.first { $0.square == square }?.id, "nothing on \(square)")
    }

    func testAMoveKeepsEveryPieceAndOnlyTheMovedOneTravels() throws {
        let identities = PieceIdentities()
        let start = try arrange(Self.start, with: identities)
        XCTAssertEqual(start.pieces.count, 32)
        XCTAssertTrue(start.moving.isEmpty)

        let e4 = try arrange("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", with: identities)
        XCTAssertEqual(Set(e4.pieces.map(\.id)), Set(start.pieces.map(\.id)), "No piece is new, none is lost")
        XCTAssertEqual(try id(at: .e4, in: e4), try id(at: .e2, in: start), "The pawn slides from e2 to e4")
        XCTAssertEqual(e4.moving, [try id(at: .e2, in: start)])
    }

    func testTheSamePositionAskedAgainChangesNothing() throws {
        let identities = PieceIdentities()
        let first = try arrange(Self.start, with: identities)
        let again = try arrange(Self.start, with: identities)
        XCTAssertEqual(first, again)
    }

    func testACaptureKeepsTheTakerAndDropsTheTaken() throws {
        let identities = PieceIdentities()
        // 1. e4 d5: White's pawn can take on d5.
        let before = try arrange("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2", with: identities)
        let taker = try id(at: .e4, in: before)
        let taken = try id(at: .d5, in: before)
        let after = try arrange("rnbqkbnr/ppp1pppp/8/3P4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2", with: identities)
        XCTAssertEqual(try id(at: .d5, in: after), taker)
        XCTAssertFalse(after.pieces.contains { $0.id == taken }, "The taken pawn fades away")
        XCTAssertEqual(after.moving, [taker])
    }

    func testCastlingSlidesTheKingAndTheRook() throws {
        let identities = PieceIdentities()
        let before = try arrange("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", with: identities)
        let king = try id(at: .e1, in: before)
        let rook = try id(at: .h1, in: before)
        let after = try arrange("r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1", with: identities)
        XCTAssertEqual(try id(at: .g1, in: after), king)
        XCTAssertEqual(try id(at: .f1, in: after), rook)
        XCTAssertEqual(after.moving, [king, rook])
    }

    func testSteppingBackSeveralMovesSendsEachPieceHome() throws {
        let identities = PieceIdentities()
        let start = try arrange(Self.start, with: identities)
        // 1. e4 e5 2. Nf3 Nc6 3. Bb5 a6, then straight back to the start.
        _ = try arrange("r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4", with: identities)
        let back = try arrange(Self.start, with: identities)
        for square in [Square.e2, .e7, .g1, .b8, .f1, .a7] {
            XCTAssertEqual(try id(at: square, in: back), try id(at: square, in: start), "\(square)")
        }
        XCTAssertEqual(Set(back.pieces.map(\.id)), Set(start.pieces.map(\.id)))
    }

    func testAPromotedPieceIsNew() throws {
        let identities = PieceIdentities()
        let before = try arrange("8/4P3/8/8/8/8/k7/4K3 w - - 0 1", with: identities)
        let pawn = try id(at: .e7, in: before)
        let after = try arrange("4Q3/8/8/8/8/8/k7/4K3 b - - 0 1", with: identities)
        let queen = try id(at: .e8, in: after)
        XCTAssertNotEqual(queen, pawn)
        XCTAssertFalse(after.pieces.contains { $0.id == pawn })
        XCTAssertFalse(before.pieces.contains { $0.id == queen }, "A new identity, never one already used")
    }
}
