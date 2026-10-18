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

    func testEveryBoardPictureIsInTheApp() {
        for theme in BoardTheme.all {
            guard let art = theme.boardArt else { continue }
            XCTAssertNotNil(UIImage(named: art), "\(theme.name) is missing \(art)")
            XCTAssertTrue(theme.spritePieces, "\(theme.name) has a board picture but flat pieces")
        }
    }

    func testMalachiteIsTheDefaultLook() {
        XCTAssertEqual(BoardTheme.all.first?.id, .malachite)
        XCTAssertEqual(BoardTheme.named(.malachite).boardArt, "board-malachite")
    }

    func testThemesAreFoundByID() {
        for id in BoardTheme.ID.allCases {
            XCTAssertEqual(BoardTheme.named(id).id, id)
        }
    }
}
