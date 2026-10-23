import ChessKit
import CoreGraphics
import XCTest
@testable import ChessGameKiller

/// Where a tap on the flat board lands. The sprites stand taller than their squares, so a
/// piece's head is drawn over the square behind it, and a tap there means that piece.
@MainActor
final class BoardTapTests: XCTestCase {
    private let size: CGFloat = 40

    /// A point `up` squares above a square's center and `right` squares to its right, in points.
    private func point(above square: Square, by up: CGFloat, right: CGFloat = 0, flipped: Bool = false) -> CGPoint {
        let center = BoardTapResolver.center(of: square, squareSize: size, flipped: flipped)
        return CGPoint(x: center.x + right * size, y: center.y - up * size)
    }

    private func tap(_ point: CGPoint, on game: GameModel, flipped: Bool = false,
                     isSolid: ((Piece, CGPoint) -> Bool)?) -> Square? {
        BoardTapResolver.square(
            at: point, squareSize: size, flipped: flipped, selected: game.selected, targets: game.targets,
            piece: { game.piece(at: $0) }, isSolid: isSolid
        )
    }

    /// The sprites' own pictures, as the game reads them.
    private func sprites(_ theme: BoardTheme) -> (Piece, CGPoint) -> Bool {
        { piece, offset in SpriteMasks.shared.isSolid(piece, in: theme, at: offset) }
    }

    /// A stand-in for every sprite: solid in a column up the middle, from the foot to 0.95 of
    /// a square above the square's center.
    private func column() -> (Piece, CGPoint) -> Bool {
        { _, offset in abs(offset.x) < 0.15 && offset.y > -0.95 && offset.y < 0.15 }
    }

    /// Plays moves written as "e2e4" by tapping the start and end squares.
    private func play(_ game: GameModel, _ moves: String...) {
        for move in moves {
            game.tap(Square(String(move.prefix(2))))
            game.tap(Square(String(move.suffix(2))))
        }
    }

    /// At the start, 0.75 of a square above d1's center is inside d2's square but on the
    /// queen's crown: the queen.
    func testATapOnAPiecesHeadPicksThatPiece() {
        let game = GameModel()
        let crown = point(above: .d1, by: 0.75)
        XCTAssertEqual(tap(crown, on: game, isSolid: sprites(.gilded)), .d1)
        XCTAssertEqual(tap(crown, on: game, isSolid: sprites(.faberge)), .d1)
        XCTAssertEqual(tap(crown, on: game, isSolid: column()), .d1)
        // Beside the crown it is the pawn's square.
        XCTAssertEqual(tap(point(above: .d1, by: 0.75, right: 0.4), on: game, isSolid: column()), .d2)
        // Where the pieces stay inside their squares, it is the square under the finger.
        XCTAssertEqual(tap(crown, on: game, isSolid: nil), .d2)
    }

    /// With the queen picked up, a tap on the move dot drawn over the king's crown plays the
    /// move; lower down the crown it is still the king.
    func testAMoveDotComesBeforeTheHeadInFrontOfIt() {
        let game = GameModel()
        play(game, "e2e4", "e7e5")
        game.tap(.d1)
        XCTAssertEqual(game.selected, .d1)
        XCTAssertTrue(game.targets.contains(.e2))
        for isSolid in [sprites(.gilded), sprites(.faberge), column()] {
            XCTAssertEqual(tap(point(above: .e1, by: 0.85), on: game, isSolid: isSolid), .e2)
            XCTAssertEqual(tap(point(above: .e1, by: 0.72), on: game, isSolid: isSolid), .e1)
        }
    }

    /// The same from Black's side, with the board turned around.
    func testFromBlacksSide() {
        let game = GameModel()
        play(game, "e2e4", "e7e5", "g1f3")
        game.tap(.d8)
        XCTAssertEqual(game.selected, .d8)
        XCTAssertTrue(game.targets.contains(.e7))
        XCTAssertEqual(tap(point(above: .e8, by: 0.85, flipped: true), on: game, flipped: true, isSolid: column()), .e7)
        XCTAssertEqual(tap(point(above: .e8, by: 0.72, flipped: true), on: game, flipped: true, isSolid: column()), .e8)
        // Black's c-file is to the right of its d-file.
        XCTAssertEqual(tap(point(above: .d8, by: 0.75, right: 1, flipped: true), on: game, flipped: true, isSolid: nil), .c7)
    }

    func testATapOffTheSquaresIsNothing() {
        let game = GameModel()
        XCTAssertNil(tap(CGPoint(x: -1, y: 10), on: game, isSolid: column()))
        XCTAssertNil(tap(CGPoint(x: 10, y: size * 8 + 1), on: game, isSolid: column()))
    }

    func testAMaskTellsSolidFromClear() {
        // Two by two, solid only at the top left.
        let mask = AlphaMask(width: 2, height: 2, alpha: [255, 0, 0, 0])
        XCTAssertTrue(mask.isSolid(atUnit: CGPoint(x: 0.25, y: 0.25)))
        XCTAssertFalse(mask.isSolid(atUnit: CGPoint(x: 0.75, y: 0.25)))
        XCTAssertFalse(mask.isSolid(atUnit: CGPoint(x: 0.25, y: 0.75)))
        XCTAssertFalse(mask.isSolid(atUnit: CGPoint(x: 1.5, y: 0.25)), "off the picture")
        XCTAssertEqual(mask.top, 0)
        XCTAssertNil(AlphaMask(width: 1, height: 1, alpha: [0]).top)
    }

    /// The masks read the pictures the right way up: the king's cross stands above the pawn's head.
    func testMasksReadThePicturesTopDown() throws {
        let king = try XCTUnwrap(SpriteMasks.shared.mask(named: "gilded-wK"))
        let pawn = try XCTUnwrap(SpriteMasks.shared.mask(named: "gilded-wP"))
        let kingTop = try XCTUnwrap(king.top)
        let pawnTop = try XCTUnwrap(pawn.top)
        XCTAssertLessThan(kingTop, 0.3)
        XCTAssertLessThan(kingTop, pawnTop - 0.1)
        XCTAssertNil(SpriteMasks.shared.mask(named: "no-such-picture"))
    }
}
