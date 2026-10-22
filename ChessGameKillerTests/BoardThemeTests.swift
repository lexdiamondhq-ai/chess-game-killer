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

    func testGildedIsTheDefaultLook() {
        XCTAssertEqual(BoardTheme.all.first?.id, .gilded)
        XCTAssertEqual(BoardTheme.named(.gilded).pieceSet, "gilded-")
        XCTAssertEqual(BoardTheme.named(.gilded).sculptedLook?.name, "Gilded")
        XCTAssertEqual(BoardTheme.named(.gilded).sculptedLook?.pieces, "gilded-pieces")
        // Noir stays in Settings with the classic set.
        XCTAssertEqual(BoardTheme.named(.noir).pieceSet, "sculpted-")
        XCTAssertEqual(BoardTheme.named(.noir).sculptedLook?.name, "Noir")
        XCTAssertEqual(BoardTheme.named(.noir).sculptedLook?.pieces, "sculpted-pieces")
    }

    func testTheCarvedLooksPlayIn3DAndTheRestStayFlat() {
        for id in [BoardTheme.ID.gilded, .noir, .sculpted, .bordeaux, .midnight] {
            let theme = BoardTheme.named(id)
            XCTAssertNotNil(theme.sculptedLook, "\(theme.name) lost its 3D look")
            XCTAssertEqual(theme.sculptedLook?.name, theme.name)
        }
        for theme in BoardTheme.all where ![.gilded, .noir, .sculpted, .bordeaux, .midnight].contains(theme.id) {
            XCTAssertNil(theme.sculptedLook, "\(theme.name) should stay flat")
        }
    }

    func testSavedSettingsForRemovedThemesOpenTheDefault() {
        // Walnut and Malachite were removed; @AppStorage falls back to its default when the saved value no longer parses.
        let defaults = UserDefaults(suiteName: "BoardThemeTests")!
        for removed in ["walnut", "malachite"] {
            XCTAssertNil(BoardTheme.ID(rawValue: removed))
            defaults.set(removed, forKey: "boardTheme")
            let saved = defaults.string(forKey: "boardTheme").flatMap(BoardTheme.ID.init(rawValue:)) ?? .gilded
            XCTAssertEqual(saved, .gilded)
        }
        defaults.removePersistentDomain(forName: "BoardThemeTests")
    }

    func testEveryRivalHasItsOwnBoard() {
        for rival in Rival.all {
            let theme = BoardTheme.named(rival.boardTheme)
            XCTAssertEqual(theme.id, rival.boardTheme, "\(rival.name) points at a theme that does not exist")
            XCTAssertEqual(theme.name, rival.name)
            XCTAssertNotNil(theme.boardArt)
        }
        XCTAssertEqual(Set(Rival.all.map(\.boardTheme)).count, Rival.all.count, "two rivals share a board")
    }

    func testThemesAreFoundByID() {
        for id in BoardTheme.ID.allCases {
            XCTAssertEqual(BoardTheme.named(id).id, id)
        }
    }
}
