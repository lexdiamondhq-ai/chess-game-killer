import ChessKit
import UIKit
import XCTest
@testable import ChessGameKiller

final class BoardThemeTests: XCTestCase {

    func testEveryThemeHasAllTwelvePieceImages() {
        for theme in BoardTheme.all {
            for color in [Piece.Color.white, .black] {
                for kind in Piece.Kind.allCases {
                    let name = theme.imageName(for: Piece(kind, color: color, square: .a1))
                    XCTAssertNotNil(UIImage(named: name), "\(theme.name) is missing \(name)")
                }
            }
        }
    }

    func testThemesAreFoundByID() {
        for id in BoardTheme.ID.allCases {
            XCTAssertEqual(BoardTheme.named(id).id, id)
        }
    }
}
