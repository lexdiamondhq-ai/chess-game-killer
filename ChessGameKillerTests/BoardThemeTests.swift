import ChessKit
import SwiftUI
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

    /// Hiding the coordinates trades the half-square frame for a thin rim, so the squares grow;
    /// boards drawn without a picture have no frame either way.
    func testHidingCoordinatesGrowsTheSquares() {
        let side: CGFloat = 360
        let framed = BoardTheme.gilded.frameInset(side: side)
        let rim = BoardTheme.gilded.frameInset(side: side, coordinates: false)
        XCTAssertEqual(framed, side / 18, accuracy: 0.001)
        XCTAssertGreaterThan(rim, 0)
        XCTAssertLessThan(rim, framed / 2)
        XCTAssertEqual(BoardTheme.gilded.squaresAcross(), 9, accuracy: 0.001)
        XCTAssertLessThan(BoardTheme.gilded.squaresAcross(coordinates: false), 8.4)
        XCTAssertEqual(BoardTheme.neon.frameInset(side: side, coordinates: false), 0)
    }

    func testGildedIsTheDefaultLook() {
        XCTAssertEqual(BoardTheme.all.first?.id, .gilded)
        XCTAssertEqual(BoardTheme.named(.gilded).pieceSet, "gilded-")
        XCTAssertEqual(BoardTheme.named(.gilded).sculptedLook?.name, "Gilded")
        XCTAssertEqual(BoardTheme.named(.gilded).sculptedLook?.pieces, "gilded-pieces")
        // Portoro, the same set on black marble with gold veins, sits next to it in Settings.
        XCTAssertEqual(BoardTheme.all.dropFirst().first?.id, .portoro)
        XCTAssertEqual(BoardTheme.named(.portoro).pieceSet, "gilded-")
        XCTAssertEqual(BoardTheme.named(.portoro).sculptedLook?.pieces, "gilded-pieces")
        XCTAssertEqual(BoardTheme.named(.portoro).boardArt, "board-portoro")
        // Noir stays in Settings with the classic set.
        XCTAssertEqual(BoardTheme.named(.noir).pieceSet, "sculpted-")
        XCTAssertEqual(BoardTheme.named(.noir).sculptedLook?.name, "Noir")
        XCTAssertEqual(BoardTheme.named(.noir).sculptedLook?.pieces, "sculpted-pieces")
    }

    /// Classic, the clean flat board from the browser game: printed pieces on plain squares, free for everyone.
    @MainActor
    func testClassicIsAFreeFlatLook() {
        let classic = BoardTheme.named(.classic)
        XCTAssertEqual(classic.name, "Classic")
        XCTAssertEqual(classic.pieceSet, "")
        XCTAssertNil(classic.boardArt)
        XCTAssertNil(classic.sculptedLook)
        XCTAssertFalse(classic.spritePieces)
        XCTAssertTrue(BoardTheme.freeLooks.contains(.classic))
        XCTAssertTrue(RivalBoardsEarned.opens(classic))
        XCTAssertNotEqual(BoardTheme.all.first?.id, .classic, "Classic is an option, not the default")
    }

    func testTheCarvedLooksPlayIn3DAndTheRestStayFlat() {
        for id in [BoardTheme.ID.gilded, .portoro, .noir, .sculpted, .bordeaux, .midnight] {
            let theme = BoardTheme.named(id)
            XCTAssertNotNil(theme.sculptedLook, "\(theme.name) lost its 3D look")
            XCTAssertEqual(theme.sculptedLook?.name, theme.name)
        }
        for theme in BoardTheme.all where ![.gilded, .portoro, .noir, .sculpted, .bordeaux, .midnight].contains(theme.id) {
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

    /// The last move reads at a glance on light and dark squares alike: a color difference of
    /// at least 15, where under 5 can't be seen. Neon is left out; it has a glow of its own.
    @MainActor
    func testTheLastMoveShowsOnLightAndDarkSquares() {
        for theme in BoardTheme.all where !theme.glows {
            for (name, square) in [("light", theme.light), ("dark", theme.dark)] {
                let bare = Self.rgba(square)
                let wash = Self.rgba(theme.lastMove)
                let washed = (0..<3).map { wash[$0] * wash[3] + bare[$0] * (1 - wash[3]) }
                let difference = Self.deltaE(Array(bare.prefix(3)), washed)
                XCTAssertGreaterThanOrEqual(difference, 15, "\(theme.name): the last move is hard to see on \(name) squares")
            }
        }
    }

    @MainActor
    private static func rgba(_ color: Color) -> [Double] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a].map { Double($0) }
    }

    /// The CIE76 difference between two sRGB colors with components from 0 to 1.
    private static func deltaE(_ one: [Double], _ other: [Double]) -> Double {
        let a = lab(one), b = lab(other)
        return sqrt((0..<3).map { pow(a[$0] - b[$0], 2) }.reduce(0, +))
    }

    private static func lab(_ rgb: [Double]) -> [Double] {
        let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let x = (0.4124 * linear[0] + 0.3576 * linear[1] + 0.1805 * linear[2]) / 0.95047
        let y = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        let z = (0.0193 * linear[0] + 0.1192 * linear[1] + 0.9505 * linear[2]) / 1.08883
        let f = { (t: Double) -> Double in t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0 }
        return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))]
    }
}
