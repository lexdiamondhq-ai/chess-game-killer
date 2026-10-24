import ChessKit
import UIKit
import XCTest
@testable import ChessGameKiller

/// Every sprite piece on a flat board stands inside its own square, dead center, at its
/// kind's height, and white and black pieces of a kind stand alike: on the home puzzle card the
/// kings used to reach into the square above while the pawns sat small at the bottom of theirs.
@MainActor
final class PieceAlignmentTests: XCTestCase {

    /// Where the piece's solid outline is drawn, relative to its square's center, in squares.
    private func outline(_ name: String) throws -> CGRect {
        let solid = try XCTUnwrap(SpriteMasks.shared.mask(named: name)?.solid, "\(name) has no outline")
        let rect = PieceImage.boardRect(of: name, squareSize: 1)
        return CGRect(x: rect.minX + solid.minX * rect.width, y: rect.minY + solid.minY * rect.height,
                      width: solid.width * rect.width, height: solid.height * rect.height)
    }

    func testEveryPieceStandsCenteredInItsSquare() throws {
        var sets: Set<String> = []
        for theme in BoardTheme.all where theme.spritePieces && sets.insert(theme.pieceSet).inserted {
            for kind in Piece.Kind.allCases {
                let white = try outline(theme.imageName(for: Piece(kind, color: .white, square: .a1)))
                let black = try outline(theme.imageName(for: Piece(kind, color: .black, square: .a1)))
                for (name, box) in [("white \(kind)", white), ("black \(kind)", black)] {
                    let label = "\(theme.name) \(name) at \(box)"
                    XCTAssertGreaterThanOrEqual(box.minY, -0.48, "\(label) reaches out of the top of its square")
                    XCTAssertLessThanOrEqual(box.maxY, 0.48, "\(label) hangs out of the bottom of its square")
                    XCTAssertLessThanOrEqual(abs(box.midX), 0.02, "\(label) is off center sideways")
                    XCTAssertLessThanOrEqual(abs(box.midY), 0.02, "\(label) is off center up or down")
                    XCTAssertGreaterThanOrEqual(box.height, 0.5, "\(label) is too small to read")
                }
                XCTAssertEqual(white.height, black.height, accuracy: 0.04, "\(theme.name) \(kind)s differ in height")
            }
        }
        XCTAssertFalse(sets.isEmpty)
    }

    func testKingsStandTallerThanPawns() throws {
        for theme in BoardTheme.all where theme.spritePieces {
            let king = try outline(theme.imageName(for: Piece(.king, color: .white, square: .e1)))
            let pawn = try outline(theme.imageName(for: Piece(.pawn, color: .white, square: .e2)))
            XCTAssertGreaterThan(king.height, pawn.height + 0.12, "\(theme.name): the king must still stand over the pawn")
        }
    }
}
