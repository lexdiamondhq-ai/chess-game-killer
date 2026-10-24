import ChessKit
import UIKit
import XCTest
@testable import ChessGameKiller

/// Every sprite piece on a flat board stands the way the game board shows it: centered across its
/// square, its base a little above the square's bottom edge, on one line with every other piece of
/// its set. The home puzzle card used to fit each piece into its square instead, so kings filled
/// theirs while pawns sat small at the bottom.
@MainActor
final class PieceAlignmentTests: XCTestCase {

    /// Where the piece's solid outline is drawn, relative to its square's center, in squares.
    private func outline(_ name: String) throws -> CGRect {
        let solid = try XCTUnwrap(SpriteMasks.shared.mask(named: name)?.solid, "\(name) has no outline")
        let rect = PieceImage.boardRect(of: name, squareSize: 1)
        return CGRect(x: rect.minX + solid.minX * rect.width, y: rect.minY + solid.minY * rect.height,
                      width: solid.width * rect.width, height: solid.height * rect.height)
    }

    func testEveryPieceStandsCenteredOnOneLine() throws {
        var sets: Set<String> = []
        for theme in BoardTheme.all where theme.spritePieces && sets.insert(theme.pieceSet).inserted {
            var bases: [CGFloat] = []
            for kind in Piece.Kind.allCases {
                for color in [Piece.Color.white, .black] {
                    let box = try outline(theme.imageName(for: Piece(kind, color: color, square: .a1)))
                    let label = "\(theme.name) \(color) \(kind) at \(box)"
                    XCTAssertLessThanOrEqual(abs(box.midX), 0.02, "\(label) is off center across its square")
                    XCTAssertGreaterThan(box.maxY, 0.3, "\(label) floats above its square's bottom")
                    XCTAssertLessThanOrEqual(box.maxY, 0.48, "\(label) hangs out of the bottom of its square")
                    XCTAssertLessThanOrEqual(box.width, 1, "\(label) is wider than its square")
                    bases.append(box.maxY)
                }
            }
            let spread = (bases.max() ?? 0) - (bases.min() ?? 0)
            XCTAssertLessThanOrEqual(spread, 0.05, "\(theme.name) pieces stand on different lines")
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
